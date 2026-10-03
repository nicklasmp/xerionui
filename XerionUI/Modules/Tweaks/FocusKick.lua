--------------------------------------------------------------------------------
-- FocusKick Sound
-- One spoken alert for EllesmereUI's FocusKick: it plays when your interrupt
-- is ready AND the FocusKick unit (focus, or target with its "Show on
-- Target") is casting something that can be interrupted. Either can come
-- second, so it speaks when a cast starts with the kick ready, when the kick
-- comes back mid-cast, and when a cast loses its "not interruptible" shield.
--
-- WHY SPEECH AND NEVER A SOUND FILE
-- "Can be interrupted" is a secret boolean for other units in keys. Lua
-- cannot branch on it and PlaySoundFile refuses secrets, but SpeakText takes
-- a secret text. The engine turns the flag into the words or nothing:
--   C_CurveUtil.EvaluateColorValueFromBoolean(notInterruptible, 0, 1)  -> 0 / 1
--   C_StringUtil.TruncateWhenZero(n)                                   -> "" / "1"
--   C_StringUtil.WrapString(s, '<silence msec="', '"/>Kick')          -> "" / words
-- (a 1 ms silence tag on Windows, [[slnc 1]] on Mac), so a protected cast
-- says nothing and Lua never learns which it was.
--
-- The kick's own cooldown is readable; a Cooldown frame fed its duration
-- object calls OnCooldownDone the moment it ends (SPELL_UPDATE_COOLDOWN does
-- not reliably fire then).
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local M = XUI:NewModule("EUIFocusKick", {
	name = "FocusKick Sound",
	desc = "Speaks when your FocusKick target casts something you can interrupt and your kick is ready.",
	category = "tweaks",
	icon = [[Interface\Icons\Ability_Kick]],
	order = 20,
	requires = "EllesmereUICooldownManager",
	defaults = {
		text = "Kick",
		voice = "",
		volume = 100,
		rate = 0,
	},
})

local IsSecret = XUI.IsSecret
local EvalBool = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
local TruncateWhenZero = C_StringUtil and C_StringUtil.TruncateWhenZero
local WrapString = C_StringUtil and C_StringUtil.WrapString
local CAN_GATE = (EvalBool and TruncateWhenZero and WrapString) and true or false
local IS_MAC = (IsMacClient and IsMacClient()) and true or false
local READY_GAP = 1
local SHIELD_AFTER_START = 0.3

local function CDM()
	return XUI.EUI and XUI.EUI.Module("EllesmereUICooldownManager")
end

local function FKBar()
	local m = CDM()
	local byKey = m and m.barDataByKey
	return byKey and byKey[m.FOCUSKICK_BAR_KEY or "focuskick"], m
end

-- EllesmereUI's GetFocusKickUnit: "target" with Show on Target, else "focus"
local function WatchUnit()
	local m = CDM()
	local f = m and m.GetFocusKickUnit
	if f then
		local ok, u = pcall(f)
		if ok and (u == "focus" or u == "target") then return u end
	end
	return "focus"
end

-- the FocusKick pick, then its bar, then our own interrupt list
local function ResolveKick()
	local bd, m = FKBar()
	local resolve = m and m.ResolveCastableInterrupt
	if bd and resolve then
		local pick = bd.focusKickInterruptSpellID
		if type(pick) == "number" and pick > 0 then
			local ok, id = pcall(resolve, pick)
			if ok and id then return id end
		end
		local ok, sd = pcall(m.GetBarSpellData, m.FOCUSKICK_BAR_KEY or "focuskick")
		local spells = ok and type(sd) == "table" and sd.assignedSpells
		if type(spells) == "table" then
			for _, sid in ipairs(spells) do
				if type(sid) == "number" and sid > 0 then
					local ok2, id = pcall(resolve, sid)
					if ok2 and id then return id end
				end
			end
		end
	end
	local id, poll = XUI.Data.PlayerKick()
	return poll or id or false
end

--------------------------------------------------------------------------------
-- Speaking
--------------------------------------------------------------------------------
local function Words()
	local w = M.db.text
	if type(w) ~= "string" or not w:find("%S") then return "Kick" end
	return w
end

local function Say(text)
	local db = M.db
	XUI.Audio:Speak(text, db.voice, db.volume, db.rate)
end

local function XmlEscape(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function GatedWords(words, notInt)
	local digit = TruncateWhenZero(EvalBool(notInt, 0, 1))
	if IS_MAC then return WrapString(digit, "[[slnc ", "]]" .. words) end
	return WrapString(digit, '<silence msec="', '"/>' .. XmlEscape(words))
end

local function Hostile(unit)
	return XUI.Ask(UnitCanAttack, "player", unit) ~= false
end

local function CastState(unit, channel)
	if channel then
		local name, _, _, _, _, _, notInt = UnitChannelInfo(unit)
		return name, notInt
	end
	local name, _, _, _, _, _, _, notInt = UnitCastingInfo(unit)
	return name, notInt
end

-- Speaks for the unit's current cast when it can be interrupted (or lets the
-- engine decide when that is secret). channel nil looks at both.
local function RingForCast(unit, channel)
	local ok, name, notInt
	if channel == nil then
		ok, name, notInt = pcall(CastState, unit, false)
		if not ok or type(name) == "nil" then ok, name, notInt = pcall(CastState, unit, true) end
	else
		ok, name, notInt = pcall(CastState, unit, channel)
	end
	if not ok or type(name) == "nil" then return false end
	if not IsSecret(notInt) then
		if notInt then return true end
		Say(Words())
		return true
	end
	if not CAN_GATE then return true end
	local okText, text = pcall(GatedWords, Words(), notInt)
	if okText then Say(text) end
	return true
end

--------------------------------------------------------------------------------
-- The kick's cooldown
--------------------------------------------------------------------------------
local kickID, tracker, armed, lastReadyAt = nil, nil, false, -READY_GAP

local function Kick()
	if kickID == nil then kickID = ResolveKick() end
	return kickID or nil
end

-- running, duration object (nil when the duration API does not know the spell)
local function KickState(id)
	local info = C_Spell.GetSpellCooldown(id)
	local active, onGCD = XUI.Readable(info and info.isActive), XUI.Readable(info and info.isOnGCD)
	local running = (active and not onGCD) and true or false
	local dur
	if running and C_Spell.GetSpellCooldownDuration then
		local ok, d = pcall(C_Spell.GetSpellCooldownDuration, id)
		if ok then dur = d end
	end
	return running, dur
end

-- true = on cooldown, false = ready, nil = no interrupt
local function KickBusy()
	local id = Kick()
	if not id then return nil end
	local ok, running = pcall(KickState, id)
	if not ok then return nil end
	return running
end

local function KickBack()
	local now = GetTime()
	if now - lastReadyAt < READY_GAP then return end
	lastReadyAt = now
	if not M.running then return end
	local unit = WatchUnit()
	if UnitExists(unit) and Hostile(unit) then RingForCast(unit, nil) end
end

local function EnsureTracker()
	if tracker then return tracker end
	local bucket = CreateFrame("Frame", nil, UIParent)
	bucket:SetSize(1, 1)
	bucket:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
	tracker = CreateFrame("Cooldown", nil, bucket, "CooldownFrameTemplate")
	tracker:SetAllPoints(bucket)
	tracker:SetDrawSwipe(false)
	tracker:SetDrawEdge(false)
	tracker:SetDrawBling(false)
	tracker:SetHideCountdownNumbers(true)
	tracker.noCooldownCount = true
	tracker:SetScript("OnCooldownDone", function()
		if not armed then return end
		armed = false
		KickBack()
	end)
	return tracker
end

local ReadKick
local QueueReread = XUI.Coalesce(function() M:After(0.25, function() ReadKick() end) end)

ReadKick = function()
	local id = Kick()
	if not id then armed = false return end
	local ok, running, dur = pcall(KickState, id)
	if not ok then return end
	if running then
		-- right after it came back a read can still say "running"
		local since = GetTime() - lastReadyAt
		if since < READY_GAP then
			M:After(READY_GAP - since + 0.05, ReadKick)
			return
		end
		armed = true
		if dur then
			local t = EnsureTracker()
			pcall(t.SetCooldownFromDurationObject, t, dur)
		else
			QueueReread()
		end
	elseif armed then
		-- ended early: a reset or a refund
		armed = false
		if tracker then tracker:Clear() end
		KickBack()
	end
end

local function RefreshKick()
	local old = kickID
	kickID = nil
	if Kick() ~= old then
		armed = false
		if tracker then tracker:Clear() end
	end
end

--------------------------------------------------------------------------------
-- Casts
--------------------------------------------------------------------------------
local lastStartAt = 0

local function OnCast(event, unit)
	if unit ~= WatchUnit() then return end
	local shield = event == "UNIT_SPELLCAST_INTERRUPTIBLE"
	local now = GetTime()
	if shield then
		if now - lastStartAt < SHIELD_AFTER_START then return end
	else
		lastStartAt = now
	end
	if not Hostile(unit) then return end
	-- on cooldown: the kick half speaks if the cast is still going later
	if KickBusy() ~= false then return end
	if shield then
		local ok, name = pcall(CastState, unit, false)
		if not ok or type(name) == "nil" then ok, name = pcall(CastState, unit, true) end
		if ok and type(name) ~= "nil" then Say(Words()) end
		return
	end
	RingForCast(unit, event == "UNIT_SPELLCAST_CHANNEL_START")
end

function M:OnEnable()
	RefreshKick()
	local QueueRead = XUI.Coalesce(function() if M.running then ReadKick() end end)
	local function changed()
		RefreshKick()
		QueueRead()
	end
	self:RegisterEvent("SPELLS_CHANGED", changed)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", changed)
	self:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player", changed)
	self:RegisterUnitEvent("UNIT_PET", "player", changed)
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function(_, _, id, base)
		-- a readable spell that is not the interrupt cannot move it
		if id ~= nil and not IsSecret(id) and kickID and id ~= kickID
			and not (base ~= nil and not IsSecret(base) and base == kickID) then
			return
		end
		QueueRead()
	end)
	self:RegisterEvent("SPELL_UPDATE_CHARGES", QueueRead)
	self:RegisterEvent("PET_BAR_UPDATE_COOLDOWN", QueueRead)
	-- both tokens: Show on Target can switch at any time
	local function cast(_, event, unit) OnCast(event, unit) end
	self:RegisterUnitEvent("UNIT_SPELLCAST_START", { "focus", "target" }, cast)
	self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", { "focus", "target" }, cast)
	self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", { "focus", "target" }, cast)
	ReadKick()
end

function M:OnDisable()
	armed = false
	if tracker then tracker:Clear() end
end

-- The gated path with a plain "interruptible", as a key would run it.
function M:Test()
	if CAN_GATE then
		local ok, text = pcall(GatedWords, Words(), false)
		if ok then Say(text) return end
	end
	Say(Words())
end
