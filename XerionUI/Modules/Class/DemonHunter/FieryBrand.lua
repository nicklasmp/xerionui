--------------------------------------------------------------------------------
-- Fiery Brand (Vengeance)
-- One icon spot showing both halves of the brand: the damage-reduction buff on
-- you (bright, orange border) and the debuff you put on your hostile target
-- (desaturated, grey border), each with the seconds left. The engine draws
-- them: an aura container per layer holds one slot filtered to the Fiery
-- Brand spell IDs, bound to the pieces (icon, swipe, seconds) built here, so it
-- works while the auras are secret in a key.
--
-- Once the initializer returns the engine locks a button against addon code
-- for as long as auras are secret, so a restyle the client refuses waits for
-- the fight to end.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local FB_IDS = { [204021] = true, [207744] = true, [207771] = true }
local ICON_FALLBACK = 1344647

local M = XUI:NewModule("FieryBrand", {
	name = "Fiery Brand",
	desc = "Fiery Brand on you and on your target, with the seconds left.",
	category = "class",
	icon = ICON_FALLBACK,
	order = 30,
	classes = { "DEMONHUNTER" },
	specs = { 581 },
	untested = true,
	defaults = {
		icon = T.Icon(44),
		buffBorder = T.Border({ useGlobal = false, style = "SOLID", size = 2, color = { 1, 0.49, 0.04, 1 } }),
		debuffBorder = T.Border({ useGlobal = false, style = "SOLID", size = 2, color = { 0.45, 0.45, 0.45, 1 } }),
		desatDebuff = true,
		timerText = T.Font(16, { enabled = true }),
		showSwipe = true,
		position = T.Position(0, -120),
	},
})

function M:CanLoad()
	if not XUI.HasAuraContainers() then return false, "Needs the 12.1 aura containers." end
	return true
end

local holder, preview
local layers = {
	buff = { filter = "HELPFUL", unit = "player" },
	debuff = { filter = "HARMFUL|PLAYER", unit = "target", debuff = true },
}
local stylePending = false

local function Holder()
	if holder then return holder end
	holder = CreateFrame("Frame", "XUI_FieryBrand", UIParent)
	holder:SetSize(44, 44)
	holder:Hide()
	XUI.Movers:Register(holder, M, "position")
	return holder
end

local function Size()
	local i = Style:Resolve("icon", M.db.icon)
	local w = i.width or i.size or 44
	return w, i.height or i.size or w
end

-- The pieces of one layer on `parent`; the live button and the preview share them.
local function MakePieces(parent)
	local p = {}
	p.box = CreateFrame("Frame", nil, parent)
	p.box:SetAllPoints(parent)
	p.icon = p.box:CreateTexture(nil, "ARTWORK")
	p.border = Style:Border(p.box)
	p.cd = CreateFrame("Cooldown", nil, p.box, "CooldownFrameTemplate")
	p.cd:SetDrawEdge(false)
	p.cd:SetDrawBling(false)
	p.cd:SetReverse(true)
	p.cd:SetHideCountdownNumbers(true)
	p.text = CreateFrame("Frame", nil, p.box)
	p.text:SetAllPoints(p.box)
	p.text:SetFrameLevel(p.cd:GetFrameLevel() + 5)
	p.dur = p.text:CreateFontString(nil, "OVERLAY")
	Style:ApplyFont(p.dur, nil, 12)
	return p
end

local function StylePieces(p, layer)
	local db = M.db
	local w, h = Size()
	local inset = p.border:Apply(layer.debuff and db.debuffBorder or db.buffBorder)
	for _, r in ipairs({ p.icon, p.cd }) do
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", p.box, "TOPLEFT", inset, -inset)
		r:SetPoint("BOTTOMRIGHT", p.box, "BOTTOMRIGHT", -inset, inset)
	end
	Style:IconTexCoord(p.icon, w, h)
	p.icon:SetDesaturated(layer.debuff and db.desatDebuff or false)
	p.cd:SetShown(db.showSwipe ~= false)
	Style:ApplyFont(p.dur, db.timerText)
	p.dur:ClearAllPoints()
	local a = db.timerText.anchor or "CENTER"
	p.dur:SetPoint(a, p.box, a, db.timerText.x or 0, db.timerText.y or 0)
	p.dur:SetShown(db.timerText.enabled ~= false)
end

local function InitButton(layer, b)
	pcall(b.SetMouseClickEnabled, b, false)
	pcall(b.SetMouseMotionEnabled, b, false)
	local w, h = Size()
	b:SetSize(w, h)
	local p = MakePieces(b)
	pcall(StylePieces, p, layer)
	b:SetIcon(p.icon)
	pcall(b.SetDurationCooldown, b, p.cd)
	pcall(b.SetDurationText, b, p.dur, XUI.DurationTextOptions())
	layer.pieces = p
	layer.button = b
end

local function EnsureContainer(layer, name)
	if layer.container or layer.failed then return end
	local sub = CreateFrame("Frame", nil, holder)
	sub:SetAllPoints(holder)
	sub:SetFrameLevel(holder:GetFrameLevel() + (layer.debuff and 1 or 16))
	local ok, c = pcall(CreateFrame, "AuraContainer", "XUI_FieryBrand_" .. name, sub, "CustomAuraContainerTemplate")
	if not ok or not c then layer.failed = true return end
	c:SetPoint("CENTER", holder, "CENTER", 0, 0)
	c:SetSize(1, 1)
	local okSlot, slot = pcall(c.AddAuraSlot, c, name, layer.filter, {
		candidateFilters = { includeSpellIDs = FB_IDS },
		initializeFrame = function(b) InitButton(layer, b) end,
	})
	if not okSlot or not slot then layer.failed = true c:Hide() return end
	slot:SetPoint("CENTER", holder, "CENTER", 0, 0)
	pcall(c.SetUnit, c, layer.unit)
	pcall(c.SetEnabled, c, false)
	layer.container = c
end

local function CanAttack()
	return XUI.Ask(UnitCanAttack, "player", "target") ~= false -- unreadable counts as hostile
end

local function Readable(unit)
	return XUI.Ask(UnitExists, unit) and XUI.Ask(UnitIsConnected, unit) ~= false and XUI.Ask(UnitIsVisible, unit) ~= false
end

function M:UpdateLayers()
	local on = self.running and not self:IsPreview()
	local buff, debuff = layers.buff.container, layers.debuff.container
	if buff then
		local want = on and Readable("player") and true or false
		if pcall(buff.SetEnabled, buff, want) and want then pcall(buff.UpdateAllAuras, buff) end
	end
	if debuff then
		local want = on and CanAttack() and Readable("target") and true or false
		if pcall(debuff.SetEnabled, debuff, want) and want then
			pcall(debuff.UpdateAllAuras, debuff)
			self:After(0, function() pcall(debuff.UpdateAllAuras, debuff) end)
		end
	end
end

local function Restyle()
	stylePending = false
	local w, h = Size()
	for _, layer in pairs(layers) do
		if layer.pieces then
			local ok = pcall(function()
				layer.button:SetSize(w, h)
				StylePieces(layer.pieces, layer)
			end)
			if not ok then stylePending = true end
		end
	end
end

function M:OnEnable()
	Holder()
	self:RegisterUnitEvent("UNIT_PHASE", { "target", "player" }, "UpdateLayers")
	self:RegisterUnitEvent("UNIT_CONNECTION", { "target", "player" }, "UpdateLayers")
	self:RegisterUnitEvent("UNIT_FLAGS", "player", "UpdateLayers")
	self:RegisterUnitEvent("UNIT_FACTION", "player", "UpdateLayers")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateLayers")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		self:RefreshSoon()
		self:After(2, function() self:Refresh() end)
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if stylePending then Restyle() end end)
	self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(self)
		if stylePending then self:After(0, Restyle) end
	end)
end

function M:OnDisable() self:UpdateLayers() end

function M:OnRefresh()
	if not (holder or self:IsPreview()) then return end
	local h = Holder()
	XUI.Movers:Apply(h)
	local w, ht = Size()
	h:SetSize(w, ht)
	-- the sample the settings are tuned on, drawn on the holder
	if self:IsPreview() then
		preview = preview or MakePieces(h)
		StylePieces(preview, layers.buff)
		preview.icon:SetTexture(XUI.GetSpellIcon(204021, ICON_FALLBACK))
		preview.cd:SetCooldown(GetTime() - 4, 12)
		preview.dur:SetText("8")
		preview.box:Show()
	elseif preview then
		preview.box:Hide()
	end
	if self.running and not self:IsPreview() then
		EnsureContainer(layers.buff, "buff")
		EnsureContainer(layers.debuff, "debuff")
		Restyle()
	end
	h:SetShown(self:IsPreview() or self.running)
	self:UpdateLayers()
end
