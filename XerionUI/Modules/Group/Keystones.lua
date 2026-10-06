--------------------------------------------------------------------------------
-- Keystones
-- Who in the group holds which keystone, shown when you zone into a dungeon so
-- the key can be picked before it starts.
--
-- THE PROTOCOL
-- Group members' keys are not readable through the game's API: they come over
-- an addon channel. This speaks the same small protocol as LibKeystone (the
-- library BigWigs and EllesmereUI embed), so a member running any of those is
-- heard, and they hear us:
--     prefix "LibKS"; "R" asks the group to report; a report is
--     "level,challengeMapID,rating" ("0,0,rating" = no key).
-- A member without an addon that shares keys never answers; with "Show members
-- without a key" on, such a member reads "no reply".
-- Your own key is read locally and always shows. When LibKeystone is loaded
-- (BigWigs), it answers requests for us and we stay quiet.
--
-- WHEN IT SHOWS
-- In a dungeon, until the key starts (the first start dismisses it until the
-- next loading screen), or on demand with /xui keys. Right-click it to dismiss.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local M = XUI:NewModule("Keystones", {
	name = "Keystones",
	desc = "Shows who in your group holds which keystone when you enter a dungeon.",
	category = "group",
	icon = [[Interface\Icons\INV_Relics_Hourglass]],
	order = 80,
	untested = true,
	defaults = {
		width = 300,
		gap = 2,
		padding = 6,
		autoHide = 0,
		showMissing = false,
		showRating = false,
		showIcon = true,
		classColors = true,
		highlightCurrent = true,
		matchColor = { 0.35, 1, 0.45, 1 },
		nameText = T.Font(14, { color = { 1, 1, 1, 1 } }),
		keyText = T.Font(14, { color = { 1, 1, 1, 1 } }),
		icon = T.Icon(20),
		border = T.Border(),
		background = T.Background(),
		position = T.Position(0, 140),
	},
})

local IsSecret = XUI.IsSecret

local PREFIX = "LibKS"
local THROTTLE = 3 -- seconds between our own sends; the library uses the same
local UNITS = { "player", "party1", "party2", "party3", "party4" }
local MUTED = { 0.55, 0.55, 0.55 }

local holder
local rows = {}
local reported = {}       -- ["Name-Realm"] = { level, map, rating }
local mapInfo = {}        -- challengeMapID = { name, texture, instanceMap }
local forced, dismissed = false, false
local lastSent, lastAsked = -10, -10
local sendPending, askPending = false, false
local showToken = 0
local counts = { got = 0, sent = 0, asked = 0 }

--------------------------------------------------------------------------------
-- Names. A report arrives as Ambiguate(sender, "none"), the roster is walked
-- with unit tokens that hand the name and realm back apart: everything is put
-- into one realm-qualified form before it is compared.
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

-- name, icon and the instance's own map id of a challenge map (cached once known)
local function MapInfo(map)
	local hit = mapInfo[map]
	if hit then return hit end
	local CM = C_ChallengeMode
	if not (CM and CM.GetMapUIInfo) then return nil end
	local ok, name, _, _, texture, _, instanceMap = pcall(CM.GetMapUIInfo, map)
	if not ok or type(name) ~= "string" then return nil end
	hit = { name = name, texture = texture, instanceMap = instanceMap }
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
function M:Request()
	if askPending then return end
	local wait = lastAsked + THROTTLE - GetTime()
	if wait <= 0 then
		Ask()
		return
	end
	askPending = true
	self:After(wait + 0.1, Ask)
end

local function OnAddon(_, _, prefix, msg, channel, sender)
	if IsSecret(prefix) or prefix ~= PREFIX then return end
	if channel ~= "PARTY" and channel ~= "INSTANCE_CHAT" then return end
	if IsSecret(msg) or type(msg) ~= "string" or IsSecret(sender) or type(sender) ~= "string" then return end
	if msg == "R" then
		-- the library answers for us when it is loaded
		if not LibStub("LibKeystone", true) then QueueSendOwn() end
		return
	end
	local level, map, rating = msg:match("^(%d+),(%d+),(%d+)$")
	if not level then return end
	local name = Qualified(Ambiguate(sender, "none"))
	if not name then return end
	counts.got = counts.got + 1
	reported[name] = { level = tonumber(level), map = tonumber(map), rating = tonumber(rating) }
	M:RefreshSoon()
end

--------------------------------------------------------------------------------
-- The roster
--------------------------------------------------------------------------------
local function InDungeon()
	local _, kind = GetInstanceInfo()
	return kind == "party"
end

-- Group members with what is known of their key, best key first. Members who
-- have no key, or never answered, only when `showMissing` asks for them.
local function Roster()
	local out = {}
	local instanceMap = select(8, GetInstanceInfo())
	local db = M.db
	for idx, unit in ipairs(UNITS) do
		if UnitExists(unit) then
			local name, realm = UnitFullName(unit)
			local key = Qualified(name, realm)
			if key then
				local entry
				if unit == "player" then
					local level, map, rating = OwnKey()
					entry = { level = level, map = map, rating = rating }
				else
					entry = reported[key]
				end
				local item = { name = name, idx = idx, known = entry ~= nil, level = entry and entry.level or 0, rating = entry and entry.rating or 0 }
				local _, class = UnitClass(unit)
				item.class = class
				if item.level > 0 then
					local info = MapInfo(entry.map)
					item.dungeon = info and info.name or "Unknown dungeon"
					item.texture = info and info.texture
					item.match = info ~= nil and instanceMap ~= nil and info.instanceMap == instanceMap
				end
				if item.level > 0 or db.showMissing then out[#out + 1] = item end
			end
		end
	end
	table.sort(out, function(a, b)
		if a.level ~= b.level then return a.level > b.level end
		if a.known ~= b.known then return a.known end
		return a.idx < b.idx
	end)
	return out
end

-- keys of members who left the group are forgotten
local function Prune()
	if not IsInGroup() then
		wipe(reported)
		return
	end
	local here = {}
	for _, unit in ipairs(UNITS) do
		if UnitExists(unit) then
			local key = Qualified(UnitFullName(unit))
			if key then here[key] = true end
		end
	end
	for key in pairs(reported) do
		if not here[key] then reported[key] = nil end
	end
end

local ICON_SAMPLE = [[Interface\Icons\INV_Relics_Hourglass]]
local PREVIEW = {
	{ name = "Xerion", class = "DEATHKNIGHT", level = 12, dungeon = "Ara-Kara, City of Echoes", texture = ICON_SAMPLE, match = true, rating = 2840, known = true },
	{ name = "Brewnado", class = "MONK", level = 11, dungeon = "The Dawnbreaker", texture = ICON_SAMPLE, rating = 2610, known = true },
	{ name = "Stormcall", class = "SHAMAN", level = 9, dungeon = "Operation: Floodgate", texture = ICON_SAMPLE, rating = 2305, known = true },
	{ name = "Pyroclast", class = "MAGE", level = 0, rating = 0, known = true },
	{ name = "Nightblade", class = "ROGUE", level = 0, rating = 0, known = false },
}

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
local function Holder()
	if holder then return holder end
	holder = CreateFrame("Frame", "XUI_Keystones", UIParent)
	holder:Hide()
	holder:SetSize(300, 40)
	holder.bg = Style:Background(holder)
	holder.border = Style:Border(holder)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and not M:IsPreview() then
			dismissed, forced = true, false
			M:Refresh()
		end
	end)
	XUI.Movers:Register(holder, M, "position")
	return holder
end

local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, holder)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.name = r:CreateFontString(nil, "OVERLAY")
	r.key = r:CreateFontString(nil, "OVERLAY")
	r.name:SetWordWrap(false)
	r.key:SetWordWrap(false)
	Style:ApplyFont(r.name, nil, 12)
	Style:ApplyFont(r.key, nil, 12)
	rows[i] = r
	return r
end

local function KeyText(db, item)
	if item.level > 0 then
		local text = ("+%d  %s"):format(item.level, item.dungeon or "")
		if db.showRating and item.rating and item.rating > 0 then
			text = text .. ("  |cff9d9d9d%d|r"):format(item.rating)
		end
		return text
	end
	return item.known and "no key" or "no reply"
end

local function Render()
	local db = M.db
	local list = M:IsPreview() and PREVIEW or Roster()
	local n = #list
	local pad, gap = db.padding, db.gap
	local inset = holder.border:Apply(db.border)
	Style:ApplyBackground(holder.bg, db.background)

	local ib = Style:Resolve("icon", db.icon)
	local iconSize = ib.width or ib.size or 20
	local fontSize = Style:Resolve("font", db.nameText).size or 14
	local rowH = math.max(db.showIcon and iconSize or 0, fontSize + 4)
	local textLeft = db.showIcon and (iconSize + 6) or 0
	local match = db.matchColor

	for i = 1, n do
		local item, r = list[i], Row(i)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", holder, "TOPLEFT", pad + inset, -(pad + inset + (i - 1) * (rowH + gap)))
		r:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -(pad + inset), -(pad + inset + (i - 1) * (rowH + gap)))
		r:SetHeight(rowH)

		r.icon:ClearAllPoints()
		r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
		r.icon:SetSize(iconSize, iconSize)
		if db.showIcon and item.texture then
			r.icon:SetTexture(item.texture)
			Style:IconTexCoord(r.icon, iconSize, iconSize, ib.zoom)
			r.icon:Show()
		else
			r.icon:Hide()
		end

		Style:ApplyFont(r.key, db.keyText)
		r.key:ClearAllPoints()
		r.key:SetPoint("RIGHT", r, "RIGHT", 0, 0)
		r.key:SetJustifyH("RIGHT")
		r.key:SetText(KeyText(db, item))
		if item.level <= 0 then
			r.key:SetTextColor(MUTED[1], MUTED[2], MUTED[3], 1)
		elseif db.highlightCurrent and item.match then
			r.key:SetTextColor(XUI.UnpackColor(match))
		end

		Style:ApplyFont(r.name, db.nameText)
		r.name:ClearAllPoints()
		r.name:SetPoint("LEFT", r, "LEFT", textLeft, 0)
		r.name:SetPoint("RIGHT", r.key, "LEFT", -8, 0)
		r.name:SetJustifyH("LEFT")
		r.name:SetText(item.name or "?")
		if db.classColors and item.class then
			r.name:SetTextColor(XUI.ClassColor(item.class))
		end
		r:Show()
	end
	for i = n + 1, #rows do rows[i]:Hide() end

	local shownRows = math.max(1, n)
	holder:SetSize(db.width, (pad + inset) * 2 + shownRows * rowH + (shownRows - 1) * gap)
	return n
end

local function Wanted()
	if M:IsPreview() then return true end
	if not M.running or dismissed then return false end
	if forced then return true end
	if not InDungeon() then return false end
	-- after a reload in a running key there is nothing left to choose
	return not XUI.KeyActive()
end

function M:OnRefresh()
	if not (holder or self:IsPreview()) then return end
	local h = Holder()
	XUI.Movers:Apply(h)
	local show = Wanted()
	if show then Render() end
	h:SetShown(show)
	if show and not self:IsPreview() then
		if not h.live then
			h.live = true
			showToken = showToken + 1
			local token, wait = showToken, self.db.autoHide
			if wait > 0 then
				self:After(wait, function(self)
					if token == showToken then
						dismissed = true
						self:Refresh()
					end
				end)
			end
		end
	else
		h.live = false
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
local RequestSoon = XUI.Coalesce(function()
	if M.running then M:After(1.5, function(self) self:Request() end) end
end)

function M:OnEnable()
	Holder()
	local CI = C_ChatInfo
	if CI and CI.RegisterAddonMessagePrefix then pcall(CI.RegisterAddonMessagePrefix, PREFIX) end
	-- the game only knows the owned key once it has been asked
	if C_MythicPlus and C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
	self:RegisterEvent("CHAT_MSG_ADDON", OnAddon)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		dismissed = false
		self:After(2, function(self)
			self:Request()
			self:Refresh()
		end)
		self:After(8, function(self) self:Request() end)
	end)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function(self)
		Prune()
		self:RefreshSoon()
		RequestSoon()
	end)
	-- the key has started: nothing left to choose, until the next loading screen
	self:RegisterEvent("CHALLENGE_MODE_START", function(self)
		dismissed = true
		self:Refresh()
	end)
	RequestSoon()
end

function M:OnDisable()
	forced = false
	sendPending, askPending = false, false
	if holder then
		holder.live = false
		if not self:IsPreview() then holder:Hide() end
	end
end

-- Shows the list now (also outside a dungeon) and asks the group again.
function M:Test()
	if not self:RequireRunning() then return end
	forced, dismissed = true, false
	self:Request()
	self:Refresh()
end

-- /xui keys: hide it when it is up, show it when it is not.
function M:Toggle()
	if not self:RequireRunning() then return end
	if holder and holder:IsShown() and not self:IsPreview() then
		dismissed, forced = true, false
	else
		dismissed, forced = false, true
		self:Request()
	end
	self:Refresh()
end

function M:DebugInfo()
	local known = 0
	for _ in pairs(reported) do known = known + 1 end
	local level, map = OwnKey()
	local info = map > 0 and MapInfo(map)
	return {
		("channel: %s, in a dungeon: %s, key active: %s"):format(tostring(Channel()), tostring(InDungeon()), tostring(XUI.KeyActive())),
		("your key: %s"):format(level > 0 and ("+%d %s"):format(level, info and info.name or ("map " .. map)) or "none"),
		("reports kept: %d (received %d, requests sent %d, own reports sent %d)"):format(known, counts.got, counts.asked, counts.sent),
		("LibKeystone loaded (answers for us): %s"):format(tostring(LibStub("LibKeystone", true) ~= nil)),
		("shown: %s, dismissed: %s, forced: %s"):format(tostring(holder and holder:IsShown()), tostring(dismissed), tostring(forced)),
	}
end
