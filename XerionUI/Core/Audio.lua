--------------------------------------------------------------------------------
-- XerionUI - Core/Audio.lua
-- Sound and text-to-speech alerts behind one block shape, so every module
-- that makes a noise is configured the same way:
--     alert = {
--         mode = "SOUND" | "TTS" | "NONE",
--         sound = "<LibSharedMedia sound name>",
--         channel = "Master",
--         text = "Spoken text",            -- TTS
--         voice = "",                      -- TTS voice name, "" = system default
--         volume = 100,                    -- TTS volume 0-100
--         rate = 0,                        -- TTS rate -10..10
--     }
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local Media = XUI.Media

local Audio = {}
XUI.Audio = Audio

Audio.MODES = {
	{ value = "NONE", text = "None" },
	{ value = "SOUND", text = "Sound" },
	{ value = "TTS", text = "Text to speech" },
}

Audio.CHANNELS = {
	{ value = "Master", text = "Master" },
	{ value = "SFX", text = "Effects" },
	{ value = "Music", text = "Music" },
	{ value = "Ambience", text = "Ambience" },
	{ value = "Dialog", text = "Dialog" },
}

-- Voices installed on this machine: list of { value = name, text = name },
-- with the system default first.
function Audio:Voices()
	local out = { { value = "", text = "System default" } }
	local V = C_VoiceChat
	local voices = V and V.GetTtsVoices and XUI.Probe(V.GetTtsVoices)
	if type(voices) == "table" then
		for _, voice in ipairs(voices) do
			if voice.name then out[#out + 1] = { value = voice.name, text = voice.name } end
		end
	end
	return out
end

-- voice name (lower case) -> voiceID; the installed voices do not change mid-session
local voiceIDs = {}

local function VoiceID(name)
	local V = C_VoiceChat
	if name and name ~= "" then
		local wanted = name:lower()
		if voiceIDs[wanted] then return voiceIDs[wanted] end
		local voices = V.GetTtsVoices and XUI.Probe(V.GetTtsVoices)
		if type(voices) == "table" then
			for _, voice in ipairs(voices) do
				if voice.name and voice.name:lower() == wanted then
					voiceIDs[wanted] = voice.voiceID
					return voice.voiceID
				end
			end
		end
	end
	local S = C_TTSSettings
	local id = S and S.GetVoiceOptionID and XUI.Probe(S.GetVoiceOptionID, 0)
	return id or 0
end

-- The same alert twice within this window is played once: one aura event
-- often arrives as several UNIT_AURA updates.
local THROTTLE = 0.25
local lastPlayed = setmetatable({}, { __mode = "k" })

function Audio:Speak(text, voice, volume, rate)
	local V = C_VoiceChat
	if not (V and V.SpeakText) or text == nil then return end
	-- a secret text (a name read in combat) is handed over as it is
	if not XUI.IsSecret(text) and (type(text) ~= "string" or not text:find("%S")) then return end
	pcall(V.SpeakText, VoiceID(voice), text, rate or 0, volume or 100, true)
end

-- The game's own sounds, offered next to LibSharedMedia's under these names.
Audio.GAME_SOUNDS = {
	{ name = "WoW: Raid Warning", kit = "RAID_WARNING" },
	{ name = "WoW: Ready Check", kit = "READY_CHECK" },
	{ name = "WoW: Alarm Clock", kit = "ALARM_CLOCK_WARNING_3" },
	{ name = "WoW: Level Up", kit = "LEVEL_UP" },
}
local gameKit = {}
for _, s in ipairs(Audio.GAME_SOUNDS) do gameKit[s.name] = s.kit end

function Audio:PlaySound(name, channel)
	local kit = gameKit[name]
	if kit then
		local id = SOUNDKIT and SOUNDKIT[kit]
		if id then PlaySound(id, channel or "Master") end
		return
	end
	local path = Media:Fetch("sound", name)
	if path then PlaySoundFile(path, channel or "Master") end
end

-- The file behind a sound name, for engine-played sounds (AddAuraSound);
-- nil for "None" and for the game's own sounds, which have no file path.
function Audio:SoundFile(name)
	if not name or name == "" or gameKit[name] then return nil end
	return Media:Fetch("sound", name)
end

-- Plays an alert block. TTS speaks the block's own text, or `fallbackText`
-- when that is empty (usually the text the module shows on screen).
-- `force` ignores the throttle (test buttons).
function Audio:Play(block, fallbackText, force)
	if type(block) ~= "table" or block.mode == "NONE" or not block.mode then return end
	local now = GetTime()
	if not force then
		local last = lastPlayed[block]
		if last and now - last < THROTTLE then return end
	end
	lastPlayed[block] = now
	if block.mode == "SOUND" then
		self:PlaySound(block.sound, block.channel)
	elseif block.mode == "TTS" then
		local text = block.text
		if type(text) ~= "string" or not text:find("%S") then text = fallbackText end
		self:Speak(text, block.voice, block.volume, block.rate)
	end
end
