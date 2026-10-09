--------------------------------------------------------------------------------
-- Who Has the Key
-- A short text when you enter a Mythic dungeon: the group members whose
-- keystone is for THIS dungeon, as "Name: +level" in class colors. The same
-- idea as BigWigs' "Who has a key?".
--
-- It goes away when you leave, when a boss fight or the key starts, and while
-- you are in combat (it comes back ten seconds after a fight, three fights at
-- most).
--
-- THE PROTOCOL
-- Other players' keys are not readable through the game's API, they are
-- shared over an addon channel. This speaks the small protocol LibKeystone
-- uses (the library BigWigs and EllesmereUI embed), written here from scratch:
--     prefix "LibKS"; "R" asks the group to report; a report is
--     "level,challengeMapID,rating" ("0,0,rating" = no key).
-- So members running BigWigs, EllesmereUI or this addon are heard, and hear
-- us. Your own key is read locally. When LibKeystone is loaded (BigWigs) it
-- answers requests for us and we stay quiet.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local M = XUI:NewModule("InstanceKeys", {
	name = "Who Has the Key",
	desc = "When you enter a Mythic dungeon, lists the group members who hold a keystone for it.",
	category = "group",
	icon = [[Interface\Icons\INV_Relics_Hourglass]],
	order = 80,
	untested = true,
	defaults = {
		showTitle = true,
		showAll = false,
		hideInCombat = true,
		align = "CENTER",
		otherColor = { 0.6, 0.6, 0.6, 1 },
		text = T.Font(16, { color = { 1, 1, 1, 1 } }),
		position = T.Position(0, 300),
	},
})

local IsSecret = XUI.IsSecret

local PREFIX = "LibKS"
local THROTTLE = 3          -- seconds between our own sends; the library uses the same
local MYTHIC = 23           -- the difficulty of a Mythic dungeon
local COMBAT_HIDES = 3      -- fights it hides for, then it stays away
local COMBAT_RETURN = 10    -- seconds after a fight it comes back
local UNITS = { "player", "party1", "party2", "party3", "party4" }
local TITLE = "Who has a key?"
-- dungeons that hold more than one challenge map: the key's dungeon is named
local SEVERAL_MAPS = { [1651] = true, [2441] = true }

local display
local reported = {}         -- ["Name-Realm"] = { level, map }
local mapInfo = {}          -- challengeMapID = { name, instanceMap }
local active, instanceID = false, nil
local combatHidden, combatHides = false, 0
local lastSent, lastAsked = -10, -10
local sendPending, askPending = false, false
local counts = { got = 0, sent = 0, asked = 0 }

--------------------------------------------------------------------------------
-- Names: a report arrives as Ambiguate(sender, "none"), the roster is walked
-- with unit tokens that hand name and realm back apart. Both are put into one
-- realm-qualified form before they are compared.
--------------------------------------------------------------------------------
local function Qualified(name, realm)
	if type(name) ~= "string" or IsSecret(name) or name == "" then return nil end
	if type(realm) == "string" and not IsSecret(realm) and realm ~= "" then return name .. "-" .. realm end
	if name:find("-", 1, true) then return name end
	return name .. "-" .. (GetNormalizedRealmName() or "")
end

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------
local function OwnKey()
	local MP = C_MythicPlus
	local level = MP and MP.GetOwnedKeystoneLevel and XUI.Probe(MP.GetOwnedKeystoneLevel)
	local map = MP and MP.GetOwnedKeystoneChallengeMapID and XUI.Probe(MP.GetOwnedKeystoneChallengeMapID)
	if type(level) ~= "number" then level = 0 end
	if type(map) ~= "number" then map = 0 end
	local rating = 0
	local PI = C_PlayerInfo
	local summary = PI and PI.GetPlayerMythicPlusRatingSummary and XUI.Probe(PI.GetPlayerMythicPlusRatingSummary, "player")
	if type(summary) == "table" and type(summary.currentSeasonScore) == "number" then rating = summary.currentSeasonScore end
	return level, map, rating
end

-- name and the instance's own map id of a challenge map (cached once known)
local function MapInfo(map)
	local hit = mapInfo[map]
	if hit then return hit end
	local CM = C_ChallengeMode
	if not (CM and CM.GetMapUIInfo) then return nil end
	local ok, name, _, _, _, _, instanceMap = pcall(CM.GetMapUIInfo, map)
	if not ok or type(name) ~= "string" then return nil end
	hit = { name = name, instanceMap = instanceMap }
	mapInfo[map] = hit
	return hit
end

--------------------------------------------------------------------------------
-- The addon channel
--------------------------------------------------------------------------------
local function Channel()
	if IsInGroup(_G.LE_PARTY_CATEGORY_INSTANCE or 2) then return "INSTANCE_CHAT" end
	if IsInGroup() then return "PARTY" end
	return nil
end

local function Send(text)
	local channel = Channel()
	local CI = C_ChatInfo
	if not (channel and CI and CI.SendAddonMessage) then return false end
	counts.sent = counts.sent + 1
	return pcall(CI.SendAddonMessage, PREFIX, text, channel)
end

local function SendOwn()
	sendPending = false
	lastSent = GetTime()
	local level, map, rating = OwnKey()
	Send(("%d,%d,%d"):format(level, map, rating))
end

local function QueueSendOwn()
	if sendPending then return end
	local wait = lastSent + THROTTLE - GetTime()
	if wait <= 0 then
		SendOwn()
		return
	end
	sendPending = true
	M:After(wait + 0.1, SendOwn)
end

local function Ask()
	askPending = false
	lastAsked = GetTime()
	counts.asked = counts.asked + 1
	Send("R")
end

-- Asks the group to report its keys (throttled, so calling it often is fine).
local function Request()
	if askPending then return end
	local wait = lastAsked + THROTTLE - GetTime()
	if wait <= 0 then
		Ask()
		return
	end
	askPending = true
	M:After(wait + 0.1, Ask)
end

local function OnAddon(_, _, prefix, msg, channel, sender)
	if not active then return end
	if IsSecret(prefix) or prefix ~= PREFIX then return end
	if channel ~= "PARTY" and channel ~= "INSTANCE_CHAT" then return end
	if IsSecret(msg) or type(msg) ~= "string" or IsSecret(sender) or type(sender) ~= "string" then return end
	if msg == "R" then
		-- the library answers for us when it is loaded
		if not LibStub("LibKeystone", true) then QueueSendOwn() end
		return
	end
	local level, map = msg:match("^(%d+),(%d+),%d+$")
	if not level then return end
	local name = Qualified(Ambiguate(sender, "none"))
	if not name then return end
	counts.got = counts.got + 1
	reported[name] = { level = tonumber(level), map = tonumber(map) }
	M:Trace("report from %s (kept as %s): +%s, map %s, channel %s", sender, name, level, map, channel)
	M:RefreshSoon()
end

--------------------------------------------------------------------------------
-- What to show
--------------------------------------------------------------------------------
local function Hex(r, g, b)
	return XUI.ColorHex({ r, g, b })
end

-- The members to list, lowest key first (then by name), as
-- { name, class, level, dungeon, here }. Only keys for this dungeon, or every
-- key when `showAll` asks for them.
local function Holders()
	local out = {}
	local showAll = M.db.showAll
	for _, unit in ipairs(UNITS) do
		if UnitExists(unit) then
			local name, realm = UnitFullName(unit)
			local key = Qualified(name, realm)
			if key then
				local level, map
				if unit == "player" then
					level, map = OwnKey()
				else
					local entry = reported[key]
					level, map = entry and entry.level or 0, entry and entry.map or 0
				end
				if level > 0 and map > 0 then
					local info = MapInfo(map)
					local here = info ~= nil and info.instanceMap == instanceID
					if here or showAll then
						local _, class = UnitClass(unit)
						out[#out + 1] = {
							name = name, class = class, level = level, here = here,
							dungeon = info and info.name,
							instance = info and info.instanceMap,
						}
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.level ~= b.level then return a.level < b.level end
		return a.name < b.name
	end)
	return out
end

local PREVIEW = {
	{ name = "Brewnado", class = "MONK", level = 8, here = true },
	{ name = "Pyroclast", class = "MAGE", level = 10, here = true },
	{ name = "Stormcall", class = "SHAMAN", level = 11, here = false, dungeon = "The Dawnbreaker" },
}

local function Line(db, item)
	local r, g, b = XUI.ClassColor(item.class)
	local who = ("|cff%s%s:|r"):format(Hex(r, g, b), item.name or "?")
	local dungeon = item.dungeon and (" (" .. item.dungeon .. ")") or ""
	if not item.here then
		-- another dungeon's key: dimmed, and named
		return ("%s |cff%s+%d%s|r"):format(who, Hex(XUI.UnpackColor(db.otherColor)), item.level, dungeon)
	end
	-- a dungeon that holds several keys: the name tells them apart
	if item.instance and SEVERAL_MAPS[item.instance] then
		return ("%s +%d%s"):format(who, item.level, dungeon)
	end
	return ("%s +%d"):format(who, item.level)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
local function Display()
	if display then return display end
	display = XUI.Widgets:CreateText("XUI_InstanceKeys")
	display:Hide()
	XUI.Movers:Register(display, M, "position")
	return display
end

-- The frame is as large as the text, and the text has that width to itself: a
-- string measured while its frame is hidden, or before the font is in place,
-- reads too short and the client cuts the text off with "...". So it is shown
-- first, measured again a frame later, and given its width outright.
local function Refit(d)
	-- The string is never given a width of its own: a bounded string is the only
	-- kind the client cuts off with "...", so a width measured too short would
	-- show up as exactly that. Only the frame (the mover outline) follows it.
	-- Left to size itself the client still cut the text off, so the string gets
	-- far more room than any line needs and sits at the frame's own edge.
	local align = M.db.align or "LEFT"
	d.text:ClearAllPoints()
	d.text:SetPoint(align, d, align)
	d.text:SetWidth(1000)
	local ok, w = pcall(d.text.GetUnboundedStringWidth, d.text)
	local h = d.text:GetStringHeight()
	if not ok or IsSecret(w) or not w or w <= 0 then return end
	d:SetSize(w + 8, math.max(1, h or 1))
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d, db = Display(), self.db
	XUI.Movers:Apply(d)
	d:ApplyStyle(db.text)
	d.text:SetJustifyH(db.align)

	local items
	if self:IsPreview() then
		items = PREVIEW
	elseif self:IsRunning() and active and not combatHidden then
		items = Holders()
	end
	if not items or #items == 0 then
		d:Hide()
		return
	end
	local lines = {}
	if db.showTitle then lines[1] = TITLE end
	for _, item in ipairs(items) do lines[#lines + 1] = Line(db, item) end
	d:Show()
	d:SetText(table.concat(lines, "\n"))
	Refit(d)
	for _, delay in ipairs({ 0, 0.5 }) do
		self:After(delay, function() if display and display:IsShown() then Refit(display) end end)
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
-- Gone for this visit: left the zone, a boss or the key started.
local function Deactivate()
	active = false
	combatHidden, combatHides = false, 0
	wipe(reported)
	M:UnregisterEvent("UNIT_CONNECTION")
	M:UnregisterEvent("GROUP_ROSTER_UPDATE")
	M:UnregisterEvent("PLAYER_REGEN_ENABLED")
	M:UnregisterEvent("PLAYER_REGEN_DISABLED")
	M:Refresh()
end

local function Activate(id)
	active, instanceID = true, id
	combatHidden, combatHides = false, 0
	wipe(reported)
	if M.db.hideInCombat then
		M:RegisterEvent("PLAYER_REGEN_DISABLED", function(self)
			if combatHides >= COMBAT_HIDES then
				Deactivate()
				return
			end
			combatHides = combatHides + 1
			combatHidden = true
			self:Refresh()
		end)
		M:RegisterEvent("PLAYER_REGEN_ENABLED", function(self)
			self:After(COMBAT_RETURN, function(self)
				if active then
					combatHidden = false
					self:Refresh()
				end
			end)
		end)
	end
	-- somebody new in the group, or back online: ask once more
	M:RegisterEvent("UNIT_CONNECTION", function(self, _, _, isConnected)
		if isConnected == true then self:After(1, Request) end
	end)
	M:RegisterEvent("GROUP_ROSTER_UPDATE", function(self) self:After(1, Request) end)
	Request()
	-- the others' clients are still loading when the first request goes out, and
	-- an answer sent before this client listens is gone: ask again a few times
	for _, delay in ipairs({ 2, 5, 10, 20 }) do
		M:After(delay, function() if active then Request() end end)
	end
	M:Refresh()
end

-- Difficulty is only right one frame after the loading screen.
local function Arrived()
	if not M.running then return end
	local _, _, difficulty, _, _, _, _, id = GetInstanceInfo()
	if difficulty == MYTHIC and id then Activate(id) end
end

function M:OnEnable()
	Display()
	local CI = C_ChatInfo
	if CI and CI.RegisterAddonMessagePrefix then pcall(CI.RegisterAddonMessagePrefix, PREFIX) end
	-- the game only knows the owned key once it has been asked
	if C_MythicPlus and C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
	self:RegisterEvent("CHAT_MSG_ADDON", OnAddon)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		Deactivate()
		self:After(0, Arrived)
	end)
	self:RegisterEvent("PLAYER_LEAVING_WORLD", Deactivate)
	self:RegisterEvent("CHALLENGE_MODE_START", Deactivate)
	self:RegisterEvent("ENCOUNTER_START", Deactivate)
	-- enabled while already standing in the dungeon
	self:After(0, Arrived)
end

function M:OnDisable()
	active = false
	combatHidden = false
	sendPending, askPending = false, false
	wipe(reported)
	if display and not self:IsPreview() then display:Hide() end
end

function M:DebugInfo()
	local known = 0
	for _ in pairs(reported) do known = known + 1 end
	local level, map = OwnKey()
	local info = map > 0 and MapInfo(map)
	return {
		("channel: %s, listing: %s, this dungeon: %s"):format(tostring(Channel()), tostring(active), tostring(instanceID)),
		("your key: %s"):format(level > 0 and ("+%d %s"):format(level, info and info.name or ("map " .. map)) or "none"),
		("reports kept: %d (received %d, requests sent %d, own reports sent %d)"):format(known, counts.got, counts.asked, counts.sent),
		("LibKeystone loaded (answers for us): %s"):format(tostring(LibStub("LibKeystone", true) ~= nil)),
		("hidden for combat: %s (%d of %d)"):format(tostring(combatHidden), combatHides, COMBAT_HIDES),
		"reports: " .. (function()
			local out = {}
			for name, r in pairs(reported) do out[#out + 1] = ("%s +%d (map %d)"):format(name, r.level, r.map) end
			return #out > 0 and table.concat(out, "; ") or "none"
		end)(),
		"group: " .. (function()
			local out = {}
			for _, unit in ipairs(UNITS) do
				if UnitExists(unit) then
					local name, realm = UnitFullName(unit)
					local key = Qualified(name, realm)
					local r = key and reported[key]
					out[#out + 1] = ("%s=%s%s"):format(unit, tostring(key), r and "" or " (no report)")
				end
			end
			return table.concat(out, "; ")
		end)(),
	}
end
