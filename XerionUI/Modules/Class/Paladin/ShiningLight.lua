--------------------------------------------------------------------------------
-- Shining Light bar (Protection)
-- An eight-segment bar of Shield of the Righteous: each free Shining Light
-- (the proc that makes Word of Glory free) fills three segments in the free
-- colour, and the charge your own Shields of the Righteous build (up to two,
-- 29.5 seconds each) fills one segment per charge in the charge colour. The
-- seconds left show at either end.
--
-- Where the numbers come from: the free procs are read off the Cooldown
-- Manager's own Shining Light buff icon (one stack text means two procs, a
-- visible icon without it one), because the aura is hidden in combat; the
-- charge is our own clock, started by your Shield of the Righteous casts. The
-- cooldown ID the viewer gave the pooled frame is checked every pass, since a
-- relayout can hand the frame to another buff. Shining Light must be on a
-- Cooldown Manager buff bar for the free part to work.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local FREE_ID, BASE_FREE_ID, SHIELD = 327510, 321136, 53600
local SEGMENTS, FREE_VAL, CHARGE_SECONDS = 8, 3, 29.5

local M = XUI:NewModule("ShiningLight", {
	name = "Shining Light Bar",
	desc = "Free Word of Glory procs and Shield of the Righteous charges as one segmented bar.",
	category = "class",
	icon = [[Interface\Icons\Ability_Paladin_ShieldoftheTemplar]],
	order = 40,
	classes = { "PALADIN" },
	specs = { 66 },
	untested = true,
	defaults = {
		alwaysShow = true,
		bar = T.Bar(348, 8),
		border = T.Border(),
		freeColor = { 0.23, 0.78, 0.88, 1 },
		chargeColor = { 1, 0.9333, 0.4627, 1 },
		showTimers = true,
		timerText = T.Font(12),
		position = T.Position(0, -220),
	},
})

M.PREVIEW_STATES = {
	{ value = "procs", text = "Procs and charges" },
	{ value = "empty", text = "Empty" },
	{ value = "full", text = "Full" },
}

local frame, segs, ticks, textFree, textCharge
local charge, freeN, chargeExpire = 0, 0, 0
local bigBuff, bigBuffCdID
local drawnFree, drawnCharge
local ticker

local function Frame()
	if frame then return frame end
	frame = CreateFrame("Frame", "XUI_ShiningLight", UIParent)
	frame:SetSize(348, 8)
	frame:Hide()
	frame.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	frame.bg:SetAllPoints()
	frame.border = Style:Border(frame)
	segs, ticks = {}, {}
	for i = 1, SEGMENTS - 1 do ticks[i] = frame:CreateTexture(nil, "BACKGROUND", nil, -6) end
	for i = 1, SEGMENTS do segs[i] = frame:CreateTexture(nil, "ARTWORK") end
	frame.texts = CreateFrame("Frame", nil, frame)
	frame.texts:SetAllPoints()
	frame.texts:SetFrameLevel(frame:GetFrameLevel() + 5)
	textFree = frame.texts:CreateFontString(nil, "OVERLAY")
	textCharge = frame.texts:CreateFontString(nil, "OVERLAY")
	Style:ApplyFont(textFree, nil, 12)
	Style:ApplyFont(textCharge, nil, 12)
	XUI.Movers:Register(frame, M, "position")
	return frame
end

local function Layout()
	local f, db = Frame(), M.db
	local b = Style:Resolve("bar", db.bar)
	local w, h = b.width or 348, b.height or 8
	f:SetSize(w, h)
	local inset = f.border:Apply(db.border)
	f.bg:SetColorTexture(XUI.UnpackColor(b.bgColor, 0, 0, 0, 0.5))
	local gap = 1
	local innerW, innerH = w - 2 * inset, h - 2 * inset
	local segW = (innerW - gap * (SEGMENTS - 1)) / SEGMENTS
	for i = 1, SEGMENTS do
		local s = segs[i]
		s:ClearAllPoints()
		s:SetSize(math.max(1, segW), math.max(1, innerH))
		s:SetPoint("LEFT", f, "LEFT", inset + (i - 1) * (segW + gap), 0)
	end
	for i = 1, SEGMENTS - 1 do
		local t = ticks[i]
		t:SetColorTexture(0, 0, 0, 1)
		t:ClearAllPoints()
		t:SetSize(gap, math.max(1, innerH))
		t:SetPoint("LEFT", f, "LEFT", inset + i * segW + (i - 1) * gap, 0)
	end
	Style:ApplyFont(textFree, db.timerText)
	Style:ApplyFont(textCharge, db.timerText)
	textFree:ClearAllPoints()
	textFree:SetPoint("LEFT", f, "LEFT", 4, 0)
	textFree:SetJustifyH("LEFT")
	textCharge:ClearAllPoints()
	textCharge:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	textCharge:SetJustifyH("RIGHT")
	local c = Style:Resolve("font", db.timerText).color
	textFree:SetTextColor(XUI.UnpackColor(c))
	textCharge:SetTextColor(XUI.UnpackColor(c))
end

local function Render()
	if not frame then return end
	local db = M.db
	local preview = M:IsPreview()
	if not (preview or M.running) then frame:Hide() return end
	local b = Style:Resolve("bar", db.bar)
	local bg = b.bgColor or { 0.2, 0.2, 0.2, 1 }
	local fr, fg, fb, fa = XUI.UnpackColor(db.freeColor)
	local cr, cg, cb, ca = XUI.UnpackColor(db.chargeColor)
	local filledFree = freeN * FREE_VAL
	for i = 1, SEGMENTS do
		local s = segs[i]
		if i <= filledFree then
			s:SetColorTexture(fr, fg, fb, fa)
			s:Show()
		elseif i <= filledFree + charge then
			s:SetColorTexture(cr, cg, cb, ca)
			s:Show()
		else
			s:Hide() -- the bar's own background shows
		end
	end
	frame:SetShown(preview or (filledFree + charge) > 0 or db.alwaysShow)
	drawnFree, drawnCharge = freeN, charge
end

--------------------------------------------------------------------------------
-- The free procs, off the Cooldown Manager's buff icon
--------------------------------------------------------------------------------
local function CdIDOf(f)
	if type(f.GetCooldownID) ~= "function" then return nil end
	return XUI.Probe(f.GetCooldownID, f)
end

local function FindBigBuff()
	local viewer = _G.BuffIconCooldownViewer
	if not (viewer and viewer.GetChildren) then return end
	for _, f in ipairs({ viewer:GetChildren() }) do
		local id = type(f.GetSpellID) == "function" and XUI.Probe(f.GetSpellID, f) or nil
		if id and (id == FREE_ID or id == BASE_FREE_ID) then
			bigBuff, bigBuffCdID = f, CdIDOf(f)
			return
		end
	end
end

-- pooled frames: one handed to another buff after a relayout is dropped
local function StillOurs(f)
	if bigBuffCdID == nil then return true end
	local id = CdIDOf(f)
	return id == nil or id == bigBuffCdID
end

local function Tick()
	if M:IsPreview() then return end
	local db = M.db
	if chargeExpire > 0 then
		chargeExpire = chargeExpire - 0.25
		if chargeExpire <= 0 then charge, chargeExpire = 0, 0 end
	end
	if bigBuff and not StillOurs(bigBuff) then bigBuff, bigBuffCdID, freeN = nil, nil, 0 end
	if not bigBuff then
		FindBigBuff()
	elseif bigBuff.Applications and bigBuff.Applications.Applications then
		if bigBuff:IsVisible() then
			freeN = bigBuff.Applications.Applications:GetText() and 2 or 1
		else
			freeN = 0
		end
	end
	if db.showTimers then
		local freeTxt = ""
		local cd = bigBuff and bigBuff.Cooldown
		if freeN > 0 and cd and cd.GetCountdownFontString then
			local ok, fs = pcall(cd.GetCountdownFontString, cd)
			if ok and fs then freeTxt = fs:GetText() or "" end
		end
		textFree:SetText(freeTxt)
		textCharge:SetText(chargeExpire > 0 and tostring(math.ceil(chargeExpire)) or "")
	else
		textFree:SetText("")
		textCharge:SetText("")
	end
	if freeN ~= drawnFree or charge ~= drawnCharge then Render() end
end

function M:OnEnable()
	Frame()
	charge, freeN, chargeExpire = 0, 0, 0
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, _, spellID)
		if XUI.IsSecret(spellID) or spellID ~= SHIELD then return end
		if charge + 1 > 2 then
			charge, chargeExpire = 0, 0
		else
			charge, chargeExpire = charge + 1, CHARGE_SECONDS
		end
		Render()
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		bigBuff, bigBuffCdID = nil, nil
		self:After(2, FindBigBuff)
	end)
	ticker = self:NewTicker(0.25, Tick)
	Tick()
end

function M:OnDisable()
	ticker = nil
	charge, freeN, chargeExpire = 0, 0, 0
	if frame and not self:IsPreview() then frame:Hide() end
end

function M:OnRefresh()
	if not (frame or self:IsPreview()) then return end
	local f = Frame()
	XUI.Movers:Apply(f)
	Layout()
	if self:IsPreview() then
		local state = self.previewState
		if state == "empty" then
			charge, freeN, chargeExpire = 0, 0, 0
			textFree:SetText("")
			textCharge:SetText("")
		elseif state == "full" then
			charge, freeN, chargeExpire = 2, 2, 29
			textFree:SetText("12")
			textCharge:SetText("26")
		else
			charge, freeN, chargeExpire = 2, 1, 29
			textFree:SetText("12")
			textCharge:SetText("26")
		end
	elseif not self.running then
		charge, freeN, chargeExpire = 0, 0, 0
		textFree:SetText("")
		textCharge:SetText("")
	end
	Render()
end

function M:DebugInfo()
	return {
		("Cooldown Manager Shining Light icon: %s (cooldown %s)"):format(tostring(bigBuff ~= nil), tostring(bigBuffCdID)),
		("free procs %d, charges %d (%.1fs)"):format(freeN, charge, chargeExpire),
	}
end
