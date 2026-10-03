--------------------------------------------------------------------------------
-- Alter Time health (Mage)
-- Your health percent at the moment you cast Alter Time, shown for as long as
-- the buff lasts (it returns you to that health). Optionally hung on the
-- Cooldown Manager's Alter Time buff icon, else at its own place.
--
-- Triggered by the cast (readable spell ID of your own spell); ended by the
-- return cast, by the buff vanishing (a scan of your helpful auras, skipped
-- when a readable payload cannot have added or dropped an aura) or by the
-- 10 s the buff can last. The percent comes from UnitHealthPercent with a
-- 0-100 curve, which works on secret health.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local ALTER_TIME_CAST, ALTER_TIME_BUFF, ALTER_TIME_BUFF_2, ALTER_TIME_RETURN = 342245, 342246, 444754, 342247
local MAX_WINDOW = 10.2
local TARGET_BUFFS = { [ALTER_TIME_BUFF] = true, [ALTER_TIME_BUFF_2] = true }

local M = XUI:NewModule("AlterTime", {
	name = "Alter Time Health",
	desc = "Your health percent when you cast Alter Time, while the buff lasts.",
	category = "class",
	icon = [[Interface\Icons\Spell_Mage_AlterTime]],
	order = 30,
	classes = { "MAGE" },
	untested = true,
	defaults = {
		font = T.Font(24, { color = { 0.25, 0.78, 0.92, 1 } }),
		anchorCDM = true,
		anchorX = 0,
		anchorY = 0,
		position = T.Position(0, -180),
	},
})

local IsSecret = XUI.IsSecret
local display
local activeUntil, armedAt, token, lastPresent = nil, 0, nil, nil

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateText("XUI_AlterTime")
	display:Hide()
	XUI.Movers:Register(display, M, "position")
	return display
end

local function Detach()
	if not display then return end
	display:SetParent(UIParent)
	XUI.Movers:Apply(display)
end

local function TryAnchor()
	if not (activeUntil and M.db.anchorCDM and display) then return false end
	local frames = XUI.FindCDMFrames(ALTER_TIME_BUFF)
	if #frames == 0 then frames = XUI.FindCDMFrames(ALTER_TIME_BUFF_2) end
	if #frames == 0 then frames = XUI.FindCDMFrames(ALTER_TIME_CAST) end
	local icon = frames[1]
	if not icon then return false end
	display:SetParent(icon)
	display:SetFrameLevel(icon:GetFrameLevel() + 30)
	display:ClearAllPoints()
	display:SetPoint("CENTER", icon, "CENTER", M.db.anchorX, M.db.anchorY)
	return true
end

local pctCurve
local function Curve()
	if pctCurve ~= nil then return pctCurve or nil end
	pctCurve = false
	if CurveConstants and CurveConstants.ScaleTo100 then
		pctCurve = CurveConstants.ScaleTo100
	end
	return pctCurve or nil
end

local function HideSnapshot()
	activeUntil = nil
	if display then
		if not M:IsPreview() then display:Hide() end
		Detach()
	end
end

local function StartSnapshot()
	if M:IsPreview() then return end
	local d = Display()
	M:Refresh()
	local shown = false
	local curve = UnitHealthPercent and Curve()
	if curve then
		shown = pcall(function() d.text:SetFormattedText("%.0f%%", UnitHealthPercent("player", false, curve)) end)
	end
	if not shown then
		shown = pcall(function() d.text:SetFormattedText("%.0f%%", UnitHealth("player") / UnitHealthMax("player") * 100) end)
	end
	if not shown then d.text:SetText("?") end
	d:Fit()
	armedAt = GetTime()
	activeUntil = armedAt + MAX_WINDOW
	d:Show()
	if not TryAnchor() then M:After(0.3, TryAnchor) end
	local t = {}
	token = t
	C_Timer.After(MAX_WINDOW, function() if token == t then HideSnapshot() end end)
end

local sawAny, found
local function Visit(a)
	if not a then return end
	sawAny = true
	local id = a.spellId
	if id ~= nil and not IsSecret(id) and TARGET_BUFFS[id] then found = true return true end
	local nm = a.name
	if type(nm) == "string" and not IsSecret(nm) and nm:lower():find("alter time") then found = true return true end
end

local function BuffPresent()
	local AU = AuraUtil
	if not (AU and AU.ForEachAura) then return nil end
	sawAny, found = false, false
	if not pcall(AU.ForEachAura, "player", "HELPFUL", nil, Visit, true) then return nil end
	if found then return true end
	if sawAny then return false end
	return nil
end

-- one scan per change, not per event
local function OnAura(_, _, _, info)
	if M:IsPreview() then lastPresent = nil return end
	local present
	if lastPresent ~= nil and not XUI.AuraPayloadChurns(info) then
		present = lastPresent
	else
		present = BuffPresent()
		lastPresent = present
	end
	if not activeUntil then
		if present == true then StartSnapshot() end
		return
	end
	local now = GetTime()
	if now >= activeUntil then HideSnapshot() return end
	if now - armedAt < 0.5 then return end
	if present == false then HideSnapshot() end
end

function M:OnEnable()
	Display()
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(self, _, _, _, spellID)
		if IsSecret(spellID) then return end
		if spellID == ALTER_TIME_CAST then StartSnapshot() elseif spellID == ALTER_TIME_RETURN then HideSnapshot() end
	end)
	self:RegisterUnitEvent("UNIT_AURA", "player", OnAura)
	local reset = function() lastPresent = nil HideSnapshot() end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", reset)
	self:RegisterEvent("PLAYER_DEAD", reset)
end

function M:OnDisable()
	lastPresent, token = nil, nil
	HideSnapshot()
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d = Display()
	XUI.Movers:Apply(d)
	d:ApplyStyle(self.db.font)
	d:SetTextColor(XUI.UnpackColor(XUI.Style:Resolve("font", self.db.font).color))
	if self:IsPreview() then
		d:SetText("87%")
		d:Show()
	elseif activeUntil then
		TryAnchor()
	else
		d:Hide()
	end
end

function M:Test()
	if self:RequireRunning() then StartSnapshot() end
end

function M:DebugInfo()
	local p = BuffPresent()
	return {
		("buff present: %s, snapshot showing: %s"):format(p == nil and "unknown (secret)" or tostring(p), tostring(activeUntil ~= nil)),
		("UnitHealthPercent: %s, 0-100 curve: %s"):format(tostring(UnitHealthPercent ~= nil), tostring(Curve() ~= nil)),
		("Cooldown Manager icon found: %s"):format(tostring(#XUI.FindCDMFrames(ALTER_TIME_BUFF) > 0)),
	}
end
