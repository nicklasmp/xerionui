--------------------------------------------------------------------------------
-- Death Alert
-- "<Name> died" in the dead player's class color when someone in your group
-- dies, with an optional sound or spoken alert. In a raid each role can be
-- switched on or off on its own.
-- Ported from ItruliaQoL (MIT, (c) Itrulia).
--
-- Midnight: UNIT_DIED hands over a GUID; names may be secret in combat. A
-- secret name is still shown (FontStrings take secrets) but cannot be matched
-- against the white/black lists, so those lists only apply when it is
-- readable.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local M = XUI:NewModule("DeathAlert", {
	name = "Death Alert",
	desc = "Shows who died in your party or raid.",
	category = "group",
	icon = [[Interface\Icons\Spell_Shadow_DeathScream]],
	order = 10,
	defaults = {
		suffix = "died",
		suffixColor = { 1, 1, 1, 1 },
		hold = 2,
		fade = 1,
		whitelist = "",
		blacklist = "",
		roles = {
			TANK = { show = true, alert = true },
			HEALER = { show = true, alert = true },
			DAMAGER = { show = true, alert = true },
		},
		text = T.Font(26),
		alert = T.Alert(),
		position = T.Position(0, 280),
	},
})

local IsSecret = XUI.IsSecret
local display
local lastAlert = 0

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateText("XUI_DeathAlert")
	display:Hide()
	local anim = display:CreateAnimationGroup()
	display.fadeOut = anim:CreateAnimation("Alpha")
	display.fadeOut:SetFromAlpha(1)
	display.fadeOut:SetToAlpha(0)
	anim:SetScript("OnFinished", function() display:Hide() end)
	display.anim = anim
	XUI.Movers:Register(display, M, "position")
	return display
end

local function UnitFromGUID(guid)
	if guid == nil or (hasanysecretvalues and hasanysecretvalues(guid)) or IsSecret(guid) then return nil end
	-- UNIT_DIED fires for every mob that dies: only a player can be the group
	if type(guid) ~= "string" or guid:sub(1, 7) ~= "Player-" then return nil end
	local token = UnitTokenFromGUID and UnitTokenFromGUID(guid)
	if token then return token end
	if guid == UnitGUID("player") then return "player" end
	if IsInRaid() then
		for i = 1, 40 do
			if guid == UnitGUID("raid" .. i) then return "raid" .. i end
		end
	elseif IsInGroup() then
		for i = 1, 4 do
			if guid == UnitGUID("party" .. i) then return "party" .. i end
		end
	end
	return nil
end

local function InList(list, name)
	for part in list:gmatch("[^,]+") do
		if part:match("^%s*(.-)%s*$") == name then return true end
	end
	return false
end

-- Whether a readable name passes the white/black lists.
local function NameAllowed(db, name)
	if IsSecret(name) or (canaccessvalue and not canaccessvalue(name)) then return true end
	if db.whitelist:find("%S") then return InList(db.whitelist, name) end
	if db.blacklist:find("%S") then return not InList(db.blacklist, name) end
	return true
end

local function Message(db, unit)
	local name = UnitName(unit)
	if not IsSecret(name) and name == nil then name = UNKNOWN or "?" end
	local _, class = UnitClass(unit)
	local r, g, b = XUI.ClassColor(class)
	local nameText = CreateColor(r, g, b):WrapTextInColorCode(name)
	local suffix = CreateColor(XUI.UnpackColor(db.suffixColor)):WrapTextInColorCode(db.suffix)
	return nameText .. " " .. suffix, name
end

function M:Show(text, hold)
	local d, db = Display(), self.db
	d.anim:Stop()
	d:ApplyStyle(db.text)
	d:SetText(text)
	d:SetAlpha(1)
	d:Show()
	if not hold then
		d.fadeOut:SetStartDelay(db.hold)
		d.fadeOut:SetDuration(math.max(0.05, db.fade))
		d.anim:Play()
	end
end

function M:OnDied(_, guid)
	local unit = UnitFromGUID(guid)
	-- a hunter's Feign Death fires the event without the hunter being dead
	if not unit or XUI.Ask(UnitIsDead, unit) == false then return end
	-- an unreadable answer counts as "in the group"
	if not (unit == "player" or XUI.Ask(UnitInParty, unit) ~= false or XUI.Ask(UnitInRaid, unit) ~= false) then return end

	local db = self.db
	local text, name = Message(db, unit)
	if not NameAllowed(db, name) then return end

	local show, alert = true, true
	if IsInRaid() then
		local role = XUI.Probe(UnitGroupRolesAssigned, unit)
		if role == nil or role == "NONE" then role = "DAMAGER" end
		local r = db.roles[role]
		if r then show, alert = r.show, r.alert end
	end
	if show then self:Show(text) end
	if alert and GetTime() - lastAlert > 2 then
		lastAlert = GetTime()
		-- spoken: the alert's own text, else "<name> died"
		local spoken = name
		if not IsSecret(name) then spoken = (name or "") .. " " .. db.suffix end
		XUI.Audio:Play(db.alert, spoken)
	end
end

function M:OnEnable()
	Display()
	self:RegisterEvent("UNIT_DIED", "OnDied")
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d = Display()
	XUI.Movers:Apply(d)
	if self:IsPreview() then
		self:Show((Message(self.db, "player")), true)
	elseif display.anim:IsPlaying() and self:IsRunning() then
		d:ApplyStyle(self.db.text)
	else
		d.anim:Stop()
		d:Hide()
	end
end
