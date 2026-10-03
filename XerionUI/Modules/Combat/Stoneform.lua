--------------------------------------------------------------------------------
-- Stoneform Bleed Alert
-- Dwarves: shows the Stoneform icon (and optionally speaks or plays a sound)
-- while you have a bleed on you and Stoneform is ready to remove it.
--
-- THE ICON is drawn by the game's own aura engine: an aura container on you
-- holds one slot filtered to the Bleed dispel type, and its button carries our
-- icon, so it shows exactly while you have a bleed - also where auras are
-- secret (keys, fights) and Lua cannot read them. Its alpha follows Stoneform's
-- cooldown (ready = visible; read in the clear, else through the cooldown
-- duration object whose zero-ness the client turns into the alpha).
--
-- THE SOUND needs to know a bleed arrived. Where auras can be read, Lua sees it
-- (a bleed is recognised by its dispel name, dispel type number or a bleed
-- flag). Where they are secret (combat), a small frame inside the engine's
-- button plays it when it is shown: the engine shows that button exactly when
-- a bleed lands, and a frame is told when its parent is shown. Whether the
-- client delivers that script on an engine button is tested by /xui debug
-- Stoneform ("show events seen").
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local STONEFORM = 20594
local FALLBACK_ICON = 132275

local M = XUI:NewModule("Stoneform", {
	name = "Stoneform Bleed Alert",
	desc = "Shows Stoneform when you have a bleed and Stoneform is ready.",
	category = "combat",
	icon = FALLBACK_ICON,
	iconSpell = STONEFORM, -- the dwarf racial's own icon in the options
	order = 50,
	defaults = {
		icon = T.Icon(48),
		border = T.Border(),
		glow = T.Glow(false),
		alert = T.Alert("TTS", { text = "Bleed detected" }),
		position = T.Position(0, 140, "HIGH"),
	},
})

function M:CanLoad()
	if not XUI.IsSpellKnown(STONEFORM) then
		return false, "Requires the Dwarf racial Stoneform."
	end
	if not XUI.HasAuraContainers() then
		return false, "Needs the 12.1 aura containers."
	end
	return true
end

local Readable, IsSecret = XUI.Readable, XUI.IsSecret
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetSpellCooldown = C_Spell and C_Spell.GetSpellCooldown

local host, sample, container, live
local bleeding = false
local showEvents, lastSound = 0, 0
local glowState, styleError = "not applied yet", nil
local stylePending = false

--------------------------------------------------------------------------------
-- Recognising a bleed in the clear (for the sound)
--------------------------------------------------------------------------------
local function IsBleed(aura)
	local name = aura.dispelName
	if not IsSecret(name) and name == "Bleed" then return true end
	local kind = aura.dispelType
	local E = Enum and Enum.SpellDispelType
	if not IsSecret(kind) and E and E.Bleed ~= nil and kind == E.Bleed then return true end
	local flag = aura.isBleed
	if not IsSecret(flag) and flag == true then return true end
	return false
end

local function ScanBleed()
	for i = 1, 40 do
		local aura = GetAuraDataByIndex("player", i, "HARMFUL")
		if aura == nil or IsSecret(aura) then return false end
		if IsBleed(aura) then return true end
	end
	return false
end

local function HasBleed()
	if not GetAuraDataByIndex then return false end
	local ok, found = pcall(ScanBleed)
	return ok and found or false
end

--------------------------------------------------------------------------------
-- Stoneform's cooldown
--------------------------------------------------------------------------------
-- true, false, or nil when the client will not say. A rolling global cooldown
-- counts as ready. The record has had different fields over the builds.
local function Ready()
	if not GetSpellCooldown then return nil end
	local info = XUI.Probe(GetSpellCooldown, STONEFORM)
	if type(info) ~= "table" then return nil end
	local onGCD = Readable(info.isOnGCD)
	local active = Readable(info.isActive)
	if type(active) == "boolean" then return not active or onGCD == true end
	local remaining = Readable(info.timeUntilEndOfStartRecovery)
	if type(remaining) == "number" then return remaining <= 0 or onGCD == true end
	local duration = Readable(info.duration)
	if type(duration) == "number" then return duration <= 0 or onGCD == true end
	return nil
end

local function ApplyCooldownAlpha(c)
	local ready = Ready()
	if ready ~= nil then
		c:SetAlpha(ready and 1 or 0)
		return
	end
	local ok, duration = pcall(function()
		return C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(STONEFORM)
	end)
	if ok and not IsSecret(duration) and duration ~= nil and c.SetAlphaFromBoolean then
		if pcall(function() c:SetAlphaFromBoolean(duration:IsZero()) end) then return end
	end
	c:SetAlpha(1)
end

--------------------------------------------------------------------------------
-- The frames
--------------------------------------------------------------------------------
local function Host()
	if host then return host end
	host = CreateFrame("Frame", "XUI_Stoneform", UIParent)
	host:SetSize(48, 48)
	host:Hide()
	-- the sample the settings are tuned on; the live icon is the engine's
	sample = XUI.Widgets:CreateIcon(nil, host)
	sample:SetIcon(XUI.GetSpellIcon(STONEFORM, FALLBACK_ICON))
	sample:SetAllPoints(host)
	sample:Hide()
	XUI.Movers:Register(host, M, "position")
	return host
end

local function Size()
	local i = Style:Resolve("icon", M.db.icon)
	local w = i.width or i.size or 48
	return w, i.height or i.size or w
end

local function StyleLive()
	if not live then return end
	live:ApplyLayout(M.db.icon, M.db.border)
	live:ClearAllPoints()
	live:SetAllPoints(host)
	-- the engine's buttons only take the scriptless glows
	Style:SetGlow(live, M.db.glow, true, true)
	glowState = ("%s (set %s)"):format(tostring(live.__xuiGlow), tostring(M.db.glow.type))
end

local function InitButton(b)
	pcall(b.SetMouseClickEnabled, b, false)
	pcall(b.SetMouseMotionEnabled, b, false)
	b:SetSize(1, 1)
	b:SetPoint("CENTER", host, "CENTER")
	live = XUI.Widgets:CreateIcon(nil, b)
	live:SetIcon(XUI.GetSpellIcon(STONEFORM, FALLBACK_ICON))
	-- told when the engine shows the button, i.e. when a bleed lands
	local probe = CreateFrame("Frame", nil, b)
	pcall(probe.SetScript, probe, "OnShow", function() M:BleedShown() end)
	-- the rect comes from our frame, the visibility from the button's chain
	pcall(StyleLive)
end

local function EnsureContainer()
	if container then return end
	if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then C_AddOns.LoadAddOn("Blizzard_AuraContainer") end
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not ok or not c then return end
	c:SetPoint("CENTER", host, "CENTER")
	c:SetSize(1, 1)
	c:SetScale(1)
	pcall(c.AddAuraSlot, c, "bleed", "HARMFUL", {
		candidateFilters = { includeDispelTypes = { Bleed = true } },
		initializeFrame = InitButton,
	})
	pcall(c.SetUnit, c, "player")
	pcall(c.UpdateAllAuras, c)
	container = c
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
local function Gate()
	if container then ApplyCooldownAlpha(container) end
end

-- the engine just showed the bleed button: a bleed arrived (even if secret)
function M:BleedShown()
	showEvents = showEvents + 1
	if not self.running or self:IsPreview() then return end
	local now = GetTime()
	if now - lastSound < 1 then return end
	-- Stoneform on cooldown cannot answer it; an unreadable cooldown plays
	if Ready() == false then return end
	lastSound = now
	XUI.Audio:Play(self.db.alert, nil, true)
end

function M:Update(fromAura)
	local was = bleeding
	bleeding = HasBleed()
	-- the sound: a bleed that just arrived while Stoneform can answer it
	if fromAura and bleeding and not was and Ready() ~= false and GetTime() - lastSound >= 1 then
		lastSound = GetTime()
		XUI.Audio:Play(self.db.alert)
	end
end

function M:OnEnable()
	Host()
	EnsureContainer()
	bleeding = HasBleed()
	self:RegisterUnitEvent("UNIT_AURA", "player", function(self) self:Update(true) end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		self:Update(false)
		if container then pcall(container.UpdateAllAuras, container) end
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function(self)
		if stylePending then
			stylePending = not pcall(StyleLive)
		end
	end)
	-- the cooldown gate follows Stoneform's cooldown
	self:NewTicker(0.2, Gate)
	Gate()
end

function M:OnDisable()
	bleeding = false
	if container then container:SetAlpha(0) end
	if host and not self:IsPreview() then host:Hide() end
end

function M:OnRefresh()
	if not (host or self:IsPreview()) then return end
	local h, db = Host(), self.db
	XUI.Movers:Apply(h)
	h:SetSize(Size())
	local preview = self:IsPreview()
	sample:ApplyLayout(db.icon, db.border)
	sample:ClearAllPoints()
	sample:SetAllPoints(h)
	sample:SetGlow(db.glow, preview)
	sample:SetShown(preview)
	if self.running then
		EnsureContainer()
		-- a restyle the client refuses (in combat) waits for the fight to end
		local ok, err = pcall(StyleLive)
		stylePending, styleError = not ok, not ok and tostring(err) or nil
		container:SetShown(not preview)
	end
	h:SetShown(preview or self.running)
end

-- Options test button.
function M:TestAlert()
	XUI.Audio:Play(self.db.alert, nil, true)
end

function M:DebugInfo()
	local out = {
		("bleed seen by Lua: %s, Stoneform ready: %s, engine icon: %s, show events seen: %d"):format(tostring(bleeding), tostring(Ready()), container and "built" or "NOT built", showEvents),
	}
	local info = GetSpellCooldown and XUI.Probe(GetSpellCooldown, STONEFORM)
	if type(info) == "table" then
		local parts = {}
		for k, v in pairs(info) do parts[#parts + 1] = k .. "=" .. (IsSecret(v) and "<secret>" or tostring(v)) end
		table.sort(parts)
		out[#out + 1] = "cooldown record: " .. table.concat(parts, ", ")
	else
		out[#out + 1] = "cooldown record: unreadable"
	end
	out[#out + 1] = ("glow on the engine icon: %s, glow error: %s, restyle error: %s"):format(
		glowState, tostring(XUI.glowError), tostring(styleError))
	-- what the harmful auras on you look like to this addon
	for i = 1, 12 do
		local ok, aura = pcall(GetAuraDataByIndex, "player", i, "HARMFUL")
		if not ok or aura == nil then break end
		if IsSecret(aura) then out[#out + 1] = ("  debuff %d: secret"):format(i) break end
		local dispel, kind = aura.dispelName, aura.dispelType
		out[#out + 1] = ("  debuff %d: %s, dispelName %s, dispelType %s, bleed %s"):format(i,
			IsSecret(aura.name) and "<secret name>" or tostring(aura.name),
			IsSecret(dispel) and "<secret>" or tostring(dispel), IsSecret(kind) and "<secret>" or tostring(kind), tostring(IsBleed(aura)))
	end
	return out
end
