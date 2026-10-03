--------------------------------------------------------------------------------
-- Ironfur (Guardian)
-- Warns when your last Ironfur is about to run out: the Ironfur icon in the
-- Cooldown Manager glows, and a voice or sound plays, when ONE stack is left
-- and it has only a few seconds to go. Several stacks up means you are covered
-- and nothing happens. Optionally an icon of its own with the seconds left.
--
-- THE CLOCK
-- In a key the aura's stack count and expiration are hidden, so the module keeps
-- its own: every Ironfur cast of yours is one stack that lasts the configured
-- seconds (7), stacks run out one by one, and the real stack count and
-- expiration take over whenever they are readable.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local IRONFUR = 192081

local M = XUI:NewModule("Ironfur", {
	name = "Ironfur",
	desc = "Glows and speaks when your last Ironfur stack is about to run out.",
	category = "class",
	icon = [[Interface\Icons\Ability_Druid_Ironfur]],
	iconSpell = IRONFUR,
	order = 50,
	classes = { "DRUID" },
	specs = { 104 },
	untested = true,
	defaults = {
		duration = 7,
		glow = T.Glow(true, { useGlobal = false, type = "PULSE", color = { 1, 0.49, 0.04, 1 } }),
		glowThreshold = 3,
		alert = T.Alert("TTS", { text = "Ironfur" }),
		soundThreshold = 2,
		soundInCombatOnly = true,
		showIcon = false,
		icon = T.Icon(44),
		border = T.Border(),
		timerText = T.Font(18, { enabled = true }),
		position = T.Position(0, -200),
	},
})

local IsSecret = XUI.IsSecret
local GPA = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID

--------------------------------------------------------------------------------
-- The stacks: one end time per cast
--------------------------------------------------------------------------------
local ends = {}

local function Prune(now)
	for i = #ends, 1, -1 do
		if ends[i] <= now then table.remove(ends, i) end
	end
end

-- the real stacks and expiration when the game lets Lua read them
local function Reconcile(now)
	if not GPA then return end
	local ok, aura = pcall(GPA, IRONFUR)
	if not ok or not aura or IsSecret(aura) then return end
	local n, exp = aura.applications, aura.expirationTime
	if IsSecret(n) or IsSecret(exp) or type(n) ~= "number" or type(exp) ~= "number" or exp <= 0 then return end
	n = math.max(1, n)
	while #ends > n do table.remove(ends, 1) end
	while #ends < n do table.insert(ends, 1, exp) end
	table.sort(ends)
	ends[#ends] = exp
end

--------------------------------------------------------------------------------
-- The glow on the Cooldown Manager's Ironfur icon
--------------------------------------------------------------------------------
local overlays = setmetatable({}, { __mode = "k" })
local targets, lastScan = {}, 0

local function Overlay(f)
	local ov = overlays[f]
	if not ov or ov:GetParent() ~= f then
		ov = CreateFrame("Frame", nil, f)
		ov:EnableMouse(false)
		overlays[f] = ov
	end
	ov:SetAllPoints(f)
	local lvl = XUI.Probe(f.GetFrameLevel, f)
	if type(lvl) == "number" then ov:SetFrameLevel(lvl) end
	ov:Show()
	return ov
end

local function StopGlowOn(ov)
	if not ov then return end
	Style:HideGlow(ov)
	ov:Hide()
end

local icon, iconGlow

local function SetGlow(on)
	if on then
		if #targets == 0 and GetTime() - lastScan > 1 then
			targets = XUI.FindCDMFrames(IRONFUR)
			lastScan = GetTime()
		end
		for _, f in ipairs(targets) do
			if XUI.FrameActive(f) then
				Style:ShowGlow(Overlay(f), M.db.glow, true)
			elseif overlays[f] then
				StopGlowOn(overlays[f])
			end
		end
	else
		for _, ov in pairs(overlays) do StopGlowOn(ov) end
	end
	if icon then icon:SetGlow(M.db.glow, on and iconGlow ~= false and icon:IsShown()) end
end

--------------------------------------------------------------------------------
-- The icon of its own
--------------------------------------------------------------------------------
local function Icon()
	if icon then return icon end
	icon = XUI.Widgets:CreateIcon("XUI_Ironfur")
	icon:SetIcon(XUI.GetSpellIcon(IRONFUR, 1378702))
	icon:Hide()
	XUI.Movers:Register(icon, M, "position")
	return icon
end

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------
local armed = true
local ticker

local function Tick()
	if M:IsPreview() or not M.running then return end
	local db = M.db
	local now = GetTime()
	Reconcile(now)
	Prune(now)
	local stacks = #ends
	if stacks == 0 then
		SetGlow(false)
		armed = true
		if icon and not M:IsPreview() then icon:Hide() end
		M:After(0, function() if ticker and #ends == 0 then M:CancelTicker(ticker) ticker = nil end end)
		return
	end
	local rem = ends[stacks] - now
	local last = stacks == 1
	-- covered again by another stack: ready to speak the next time it is the last
	if not last or rem > db.soundThreshold + 0.5 then armed = true end
	SetGlow(db.glow.enabled ~= false and last and rem <= db.glowThreshold)
	if icon then
		if db.showIcon then
			icon:SetShown(true)
			icon.timer:SetText(("%d"):format(math.ceil(rem)))
			local cd = icon:GetCooldown()
			cd:SetReverse(true)
			cd:SetCooldown(ends[stacks] - db.duration, db.duration)
		else
			icon:Hide()
		end
	end
	local mayRing = not db.soundInCombatOnly or InCombatLockdown() or XUI.Ask(UnitAffectingCombat, "player")
	if last and armed and rem <= db.soundThreshold and mayRing then
		armed = false
		XUI.Audio:Play(db.alert, "Ironfur")
	end
end

local function SyncTicker()
	if M.running and not M:IsPreview() and #ends > 0 and not ticker then
		ticker = M:NewTicker(0.1, Tick)
	end
end

function M:OnEnable()
	Icon()
	wipe(ends)
	armed = true
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(self, _, _, _, spellID)
		if IsSecret(spellID) or spellID ~= IRONFUR then return end
		ends[#ends + 1] = GetTime() + self.db.duration
		SyncTicker()
		Tick()
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() wipe(ends) armed, targets = true, {} end)
	self:RegisterEvent("PLAYER_DEAD", function() wipe(ends) SetGlow(false) end)
end

function M:OnDisable()
	ticker = nil
	wipe(ends)
	SetGlow(false)
	if icon and not self:IsPreview() then icon:Hide() end
end

function M:OnRefresh()
	if not (icon or self:IsPreview()) then return end
	local d, db = Icon(), self.db
	XUI.Movers:Apply(d)
	d:ApplyLayout(db.icon, db.border)
	d:ApplyTimerText(db.timerText)
	local preview = self:IsPreview()
	if preview then
		d:Show()
		d.timer:SetText("2")
		local cd = d:GetCooldown()
		cd:SetReverse(true)
		cd:SetCooldown(GetTime() - (db.duration - 2), db.duration)
		d:SetGlow(db.glow, true)
	elseif not (self.running and #ends > 0 and db.showIcon) then
		d:SetGlow(db.glow, false)
		d:Hide()
	end
end

function M:Test()
	if not self:RequireRunning() then return end
	-- one stack that ends in a few seconds
	wipe(ends)
	ends[1] = GetTime() + math.max(self.db.soundThreshold, self.db.glowThreshold) + 1
	armed = true
	SyncTicker()
	Tick()
end

function M:DebugInfo()
	local now = GetTime()
	local lines = {}
	for i, e in ipairs(ends) do lines[#lines + 1] = ("%.1fs"):format(e - now) end
	return {
		("stacks on our clock: %d (%s), alert armed: %s"):format(#ends, table.concat(lines, ", "), tostring(armed)),
		("Cooldown Manager icons found: %d"):format(#XUI.FindCDMFrames(IRONFUR)),
	}
end
