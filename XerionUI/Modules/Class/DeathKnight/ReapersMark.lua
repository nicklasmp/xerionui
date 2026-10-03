--------------------------------------------------------------------------------
-- Reaper's Mark (Deathbringer)
-- The mark is a debuff on one enemy that gathers stacks and bursts after its
-- time runs out or at 40 stacks. The Cooldown Manager reads auras off the
-- player and the target only, so the moment you switch targets its seconds and
-- stacks vanish from it. This is one icon that shows YOUR mark wherever it is:
-- seconds, stacks and a swipe, on whichever enemy carries it, as long as that
-- enemy has a nameplate or is your target.
--
-- With the aura secret the engine draws it. Every enemy nameplate token, and
-- the target, gets an aura container holding ONE slot filtered to the debuff
-- and to auras you applied (HARMFUL|PLAYER). All slots are pinned to the
-- holder's centre, so whichever mob carries the mark lights the icon in that
-- one spot. The engine binds the swipe, the seconds and the stacks; the frame,
-- border and art are ours. The spell filter only holds on units you cannot
-- assist, so a container is only switched on for a unit that plainly answers
-- "cannot assist". The target's slot covers a target without a nameplate, and
-- is only on when no nameplate is plainly the target (two swipes would stack).
--
-- Once a button's initializer returns, the engine locks it against addon code
-- for as long as auras are secret, so the button stays 1x1 at the centre and
-- every piece hangs off a frame of ours. A restyle the client refuses waits
-- for the fight (or the key) to end.
--
-- It cannot glow or play a sound at a stack count (that needs the numbers in
-- Lua), and cannot show a mark on a mob with no nameplate that is not your
-- target.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local DEBUFF, CAST = 434765, 439843
local SLOT_KEY, FILTER = "rkm", "HARMFUL|PLAYER"
local BUILD_STEP = 6

local UNITS, SLOT_OF = {}, {}
for i = 1, 40 do UNITS[i] = "nameplate" .. i end
UNITS[#UNITS + 1] = "target"
local TARGET_SLOT = #UNITS
for i, u in ipairs(UNITS) do SLOT_OF[u] = i end

local M = XUI:NewModule("ReapersMark", {
	name = "Reaper's Mark",
	desc = "Your Reaper's Mark with seconds and stacks, on whichever enemy carries it.",
	category = "class",
	icon = [[Interface\Icons\Ability_Warlock_ImprovedSoulFire]],
	order = 80,
	classes = { "DEATHKNIGHT" },
	untested = true,
	defaults = {
		icon = T.Icon(44),
		border = T.Border(),
		showSwipe = true,
		timerText = T.Font(16, { enabled = true }),
		stackText = T.Font(16, { enabled = true, color = { 1, 1, 1, 1 } }),
		position = T.Position(0, -160),
	},
})

function M:CanLoad()
	if not XUI.HasAuraContainers() then return false, "Needs the 12.1 aura containers." end
	if not XUI.IsSpellKnown(CAST) then return false, "Requires the Reaper's Mark talent." end
	return true
end

local Ask = XUI.Ask
local holder, sample
local containers, enabledOn, buttons = {}, {}, {}
local failed, tracking, stylePending = nil, false, false

local function Holder()
	if holder then return holder end
	holder = CreateFrame("Frame", "XUI_ReapersMark", UIParent)
	holder:SetSize(44, 44)
	holder:Hide()
	XUI.Movers:Register(holder, M, "position")
	return holder
end

local function IconTexture()
	return XUI.GetSpellIcon(DEBUFF, XUI.GetSpellIcon(CAST))
end

-- The pieces of one icon on `parent`: the live button and the preview share them.
local function MakeFace(parent)
	local p = {}
	p.root = CreateFrame("Frame", nil, parent)
	p.root:SetAllPoints(parent)
	p.face = CreateFrame("Frame", nil, p.root)
	p.face:SetPoint("CENTER", p.root, "CENTER", 0, 0)
	p.face:SetSize(44, 44)
	p.icon = p.face:CreateTexture(nil, "ARTWORK")
	p.icon:SetTexture(IconTexture())
	p.border = Style:Border(p.face)
	p.cd = CreateFrame("Cooldown", nil, p.face, "CooldownFrameTemplate")
	p.cd:SetDrawEdge(false)
	p.cd:SetDrawBling(false)
	p.cd:SetReverse(true)
	p.cd:SetHideCountdownNumbers(true)
	p.texts = CreateFrame("Frame", nil, p.face)
	p.texts:SetAllPoints(p.face)
	p.texts:SetFrameLevel(p.cd:GetFrameLevel() + 5)
	p.dur = p.texts:CreateFontString(nil, "OVERLAY")
	p.stack = p.texts:CreateFontString(nil, "OVERLAY")
	Style:ApplyFont(p.dur, nil, 14)
	Style:ApplyFont(p.stack, nil, 14)
	return p
end

local function PlaceText(fs, face, block)
	local a = block.anchor or "CENTER"
	fs:ClearAllPoints()
	fs:SetPoint(a, face, a, block.x or 0, block.y or 0)
end

local function StyleFace(p)
	local db = M.db
	local i = Style:Resolve("icon", db.icon)
	local w = i.width or i.size or 44
	local h = i.height or i.size or w
	p.face:SetSize(w, h)
	local inset = p.border:Apply(db.border)
	for _, r in ipairs({ p.icon, p.cd }) do
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", p.face, "TOPLEFT", inset, -inset)
		r:SetPoint("BOTTOMRIGHT", p.face, "BOTTOMRIGHT", -inset, inset)
	end
	Style:IconTexCoord(p.icon, w, h, i.zoom)
	p.cd:SetAlpha(db.showSwipe ~= false and 1 or 0)
	Style:ApplyFont(p.dur, db.timerText)
	PlaceText(p.dur, p.face, db.timerText)
	p.dur:SetShown(db.timerText.enabled ~= false)
	Style:ApplyFont(p.stack, db.stackText)
	p.stack:SetTextColor(XUI.UnpackColor(Style:Resolve("font", db.stackText).color))
	PlaceText(p.stack, p.face, db.stackText)
	p.stack:SetShown(db.stackText.enabled ~= false)
end

local function InitSlot(b)
	pcall(b.SetMouseClickEnabled, b, false)
	pcall(b.SetMouseMotionEnabled, b, false)
	pcall(b.SetSize, b, 1, 1)
	pcall(b.SetPoint, b, "CENTER", holder, "CENTER", 0, 0)
	local p = MakeFace(b)
	pcall(StyleFace, p)
	pcall(b.SetDurationCooldown, b, p.cd)
	pcall(b.SetDurationText, b, p.dur, XUI.DurationTextOptions())
	pcall(b.SetApplicationCount, b, p.stack)
	buttons[#buttons + 1] = p
end

local function Build(i)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	if not ok or not c then failed = "the client refused the AuraContainer frame" return false end
	c:SetSize(1, 1)
	c:SetPoint("CENTER", holder, "CENTER", 0, 0)
	pcall(c.SetEnabled, c, false)
	local okS, errS = pcall(c.AddAuraSlot, c, SLOT_KEY, FILTER, {
		candidateFilters = { includeSpellIDs = { [DEBUFF] = true } },
		initializeFrame = InitSlot,
	})
	if not okS then failed = "aura slot refused: " .. tostring(errS) c:Hide() return false end
	local okU, errU = pcall(c.SetUnit, c, UNITS[i])
	if not okU then failed = "unit " .. UNITS[i] .. " refused: " .. tostring(errU) c:Hide() return false end
	containers[i] = c
	return true
end

-- A few containers per frame, so a login never builds all 41 at once.
local function BuildSome()
	if failed or not M.running then return end
	for _ = 1, BUILD_STEP do
		local i = #containers + 1
		if i > #UNITS or not Build(i) then break end
	end
	M:Rescan()
	if #containers < #UNITS and not failed then M:After(0, BuildSome) end
end

-- why a unit's container stays off, or nil to switch it on
local function Verdict(unit)
	if Ask(UnitExists, unit) ~= true then return "no such unit" end
	if Ask(UnitCanAttack, "player", unit) == false then return "not attackable" end
	if Ask(UnitCanAssist, "player", unit) ~= false then return "friendly, or the client would not say" end
	if Ask(UnitIsDeadOrGhost, unit) == true then return "dead" end
	return nil
end

local function TargetHasPlate()
	for i = 1, TARGET_SLOT - 1 do
		local plate = UNITS[i]
		if Ask(UnitExists, plate) == true and Ask(UnitIsUnit, "target", plate) ~= false then return true end
	end
	return false
end

local function Why(i)
	local why = Verdict(UNITS[i])
	if why then return why end
	if i == TARGET_SLOT and TargetHasPlate() then return "its nameplate shows the mark (or the client would not say)" end
	return nil
end

local function Refresh(i, reread)
	local c = containers[i]
	if not c then return end
	local on = tracking and not M:IsPreview() and Why(i) == nil
	if on then
		if not enabledOn[i] then
			if pcall(c.SetEnabled, c, true) then enabledOn[i] = true end
		elseif reread then
			pcall(c.UpdateAllAuras, c)
		end
	elseif enabledOn[i] then
		pcall(c.SetEnabled, c, false)
		enabledOn[i] = nil
	end
end

function M:Rescan()
	for i = 1, #containers do Refresh(i, false) end
end

local flagged = {}
local QueueFlagged = XUI.Coalesce(function()
	for i in pairs(flagged) do Refresh(i, false) end
	wipe(flagged)
end)
local QueueTarget = XUI.Coalesce(function() Refresh(TARGET_SLOT, false) end)

local function OnWatch(self, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then
		Refresh(TARGET_SLOT, true)
		self:After(0, function() Refresh(TARGET_SLOT, true) end)
		return
	end
	local i = unit and SLOT_OF[unit]
	if not i then return end
	if event == "NAME_PLATE_UNIT_REMOVED" then
		if enabledOn[i] then
			pcall(containers[i].SetEnabled, containers[i], false)
			enabledOn[i] = nil
		end
		QueueTarget()
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		Refresh(i, true)
		QueueTarget()
	else
		flagged[i] = true
		QueueFlagged()
	end
end

local function Restyle()
	stylePending = false
	for _, p in ipairs(buttons) do
		if not pcall(StyleFace, p) then stylePending = true end
	end
end

function M:OnEnable()
	Holder()
	tracking = true
	for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_FLAGS", "PLAYER_TARGET_CHANGED" }) do
		self:RegisterEvent(e, OnWatch)
	end
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() if stylePending then Restyle() end end)
	self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(self)
		if stylePending then self:After(0, Restyle) end
	end)
	BuildSome()
end

function M:OnDisable()
	tracking = false
	wipe(flagged)
	for i = 1, #containers do Refresh(i, false) end
end

function M:OnRefresh()
	if not (holder or self:IsPreview()) then return end
	local h = Holder()
	XUI.Movers:Apply(h)
	if self:IsPreview() then
		if not sample then
			local f = CreateFrame("Frame", nil, h)
			f:SetSize(1, 1)
			f:SetPoint("CENTER", h, "CENTER", 0, 0)
			sample = MakeFace(f)
			sample.host = f
		end
		sample.host:SetFrameLevel(h:GetFrameLevel() + 20)
		StyleFace(sample)
		sample.icon:SetTexture(IconTexture())
		sample.cd:SetCooldown(GetTime() - 4, 12)
		sample.dur:SetText("8")
		sample.stack:SetText("23")
		sample.root:Show()
		local i = Style:Resolve("icon", self.db.icon)
		h:SetSize(i.width or i.size or 44, i.height or i.size or 44)
	elseif sample then
		sample.root:Hide()
	end
	if self.running then
		Restyle()
		self:Rescan()
	end
	h:SetShown(self:IsPreview() or self.running)
end

function M:DebugInfo()
	local on = 0
	for i in pairs(enabledOn) do on = on + 1 end
	return {
		("containers built: %d of %d, switched on: %d, failure: %s"):format(#containers, #UNITS, on, tostring(failed)),
		("restyle waiting: %s"):format(tostring(stylePending)),
	}
end
