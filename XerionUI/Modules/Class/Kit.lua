--------------------------------------------------------------------------------
-- Class kit: the few building blocks the class modules share.
--
--   Kit.TimedIcon(M, opts)   an icon that counts down after a cast of yours
--   Kit.Meter(M, opts)       "label value" text for damage a trigger caused
--   Kit.ReadSpells()         your Overall damage done per spell, or nil
--   Kit.FormatClock(secs)    "4:07" above a minute, whole seconds below
--   Kit.FormatShort(n)       12.5M / 845K
--
-- Modules keep their own behaviour (what triggers, which spec); the kit only
-- draws and counts, through the shared style blocks.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local Kit = {}
XUI.ClassKit = Kit

local IsSecret = XUI.IsSecret
local floor, ceil = math.floor, math.ceil

function Kit.FormatClock(secs)
	if secs >= 60 then return ("%d:%02d"):format(floor(secs / 60), floor(secs % 60)) end
	return ("%d"):format(ceil(secs))
end

local UNITS = { { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
function Kit.FormatShort(n)
	n = tonumber(n) or 0
	local neg = n < 0
	if neg then n = -n end
	local out
	for _, u in ipairs(UNITS) do
		if n >= u[1] - u[1] / 2000 then
			out = ("%.1f"):format(n / u[1]):gsub("%.0$", "") .. u[2]
			break
		end
	end
	return (neg and "-" or "") .. (out or ("%d"):format(floor(n + 0.5)))
end

--------------------------------------------------------------------------------
-- TimedIcon
-- opts: frame (global name), icon (texture or function), duration (seconds),
--       format (function(secs) -> text), previewSeconds, hideWhen (function,
--       true = clear now; checked every tick)
-- Settings it reads from M.db: icon, border, glow, timerText, showSwipe,
-- position (all optional except icon/position).
-- Adds M:Start(), M:Clear(), M:IsActive() and an OnRefresh that draws it;
-- a module may define M:OnTick(left, display) to recolour the text.
--------------------------------------------------------------------------------
function Kit.TimedIcon(M, opts)
	local display, ticker
	local expires, total = 0, 0

	local function Texture()
		local t = opts.icon
		if type(t) == "function" then t = t() end
		return t
	end

	local function Display()
		if display then return display end
		display = XUI.Widgets:CreateIcon(opts.frame)
		display:Hide()
		XUI.Movers:Register(display, M, "position")
		return display
	end

	function M:IsActive() return expires > GetTime() end

	local function Paint()
		local left = expires - GetTime()
		if left <= 0 then return end
		display.timer:SetText((opts.format or Kit.FormatClock)(left))
		if M.OnTick then M:OnTick(left, display) end
	end

	function M:Clear()
		expires = 0
		if ticker then self:CancelTicker(ticker) ticker = nil end
		if display and display.cooldown then display.cooldown:Clear() end
		self:Refresh()
	end

	function M:Start(duration)
		duration = duration or opts.duration
		total, expires = duration, GetTime() + duration
		Display()
		if ticker then self:CancelTicker(ticker) end
		ticker = self:NewTicker(0.25, function(self)
			if not self:IsActive() or (opts.hideWhen and opts.hideWhen()) then self:Clear() return end
			Paint()
		end)
		self:Refresh()
	end

	function M:OnDisable()
		expires = 0
		ticker = nil
		if display and not self:IsPreview() then display:Hide() end
	end

	function M:OnRefresh()
		if not (display or self:IsPreview()) then return end
		local d, db = Display(), self.db
		XUI.Movers:Apply(d)
		d:ApplyLayout(db.icon, db.border)
		d:SetIcon(Texture())
		d:ApplyTimerText(db.timerText)
		local preview = self:IsPreview()
		local live = self:IsRunning() and self:IsActive()
		local visible = preview or live
		local sample = opts.previewSeconds or (opts.duration * 0.6)
		if db.showSwipe ~= false then
			local cd = d:GetCooldown()
			cd:SetReverse(true)
			if live then
				cd:SetCooldown(expires - total, total)
			elseif preview then
				cd:SetCooldown(GetTime() - (opts.duration - sample), opts.duration)
			else
				cd:Clear()
			end
			cd:SetShown(visible)
		elseif d.cooldown then
			d.cooldown:Hide()
		end
		if live then
			Paint()
		elseif preview then
			d.timer:SetText((opts.format or Kit.FormatClock)(sample))
		end
		if db.glow then d:SetGlow(db.glow, visible) end
		d:SetShown(visible)
	end
end

--------------------------------------------------------------------------------
-- Damage meter
--------------------------------------------------------------------------------
-- Your Overall damage done as { [spellID] = amount }; nil while the meter is
-- secret (in combat) or missing, {} when it simply has nothing.
function Kit.ReadSpells()
	local DM, E = _G.C_DamageMeter, _G.Enum
	if not (DM and DM.GetCombatSessionSourceFromType and E and E.DamageMeterSessionType and E.DamageMeterType) then return nil end
	local guid = UnitGUID("player")
	if not guid or IsSecret(guid) then return nil end
	local ok, src = pcall(DM.GetCombatSessionSourceFromType, E.DamageMeterSessionType.Overall, E.DamageMeterType.DamageDone, guid, nil)
	if not ok then return nil end
	if src == nil then return {} end
	if type(src) ~= "table" then return nil end
	local lines = src.combatSpells
	if type(lines) ~= "table" then return {} end
	local out = {}
	for i = 1, #lines do
		local l = lines[i]
		if type(l) == "table" then
			local id, amt = l.spellID, l.totalAmount
			if IsSecret(id) or IsSecret(amt) then return nil end
			if type(id) == "number" and type(amt) == "number" then out[id] = (out[id] or 0) + amt end
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Meter: text "Label: 845K" for the damage a trigger spell of yours caused,
-- read from the meter once the numbers can be read (after the fight) and
-- shown for `showFor` seconds. Several triggers inside the settle window add
-- up.
-- opts: frame, label, count (function(spellID) -> bool, the lines to sum),
--       isTrigger (function(spellID) -> bool), settle (s after the last cast),
--       showFor, preview (number)
-- Settings it reads: font, labelColor, valueColor, position.
-- Adds M:StartMeterEvents(), M:Hide() and an OnRefresh.
--------------------------------------------------------------------------------
function Kit.Meter(M, opts)
	local display, hideTimer, resolveTimer
	local pending, castAt, baseline, lastPlain, retries, shownValue = false, 0, 0, nil, 0, nil
	local RETRY_GAP, RETRY_MAX = 0.5, 12

	local function Display()
		if display then return display end
		display = XUI.Widgets:CreateText(opts.frame)
		display:Hide()
		XUI.Movers:Register(display, M, "position")
		return display
	end

	local function Hex(c)
		local r, g, b = XUI.UnpackColor(c)
		return ("%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
	end

	local function Paint(value)
		local d, db = Display(), M.db
		d:ApplyStyle(db.font)
		d:SetText(("|cff%s%s|r |cff%s%s|r"):format(Hex(db.labelColor), opts.label, Hex(db.valueColor), Kit.FormatShort(value)))
	end

	local function Total()
		local spells = Kit.ReadSpells()
		if not spells then return nil end
		local sum = 0
		for id, amt in pairs(spells) do
			if opts.count(id, spells) then sum = sum + amt end
		end
		return sum
	end

	function M:Hide()
		if hideTimer then hideTimer:Cancel() hideTimer = nil end
		shownValue = nil
		if display and not self:IsPreview() then display:Hide() end
	end

	function M:ShowValue(value)
		shownValue = value
		Display()
		self:Refresh()
		if hideTimer then hideTimer:Cancel() end
		hideTimer = C_Timer.NewTimer(opts.showFor or 10, function()
			hideTimer = nil
			if not M:IsPreview() then M:Hide() end
		end)
	end

	local Schedule
	local function Resolve()
		resolveTimer = nil
		if not pending then return end
		local left = castAt + opts.settle - GetTime()
		if left > 0 then Schedule(left) return end
		local total = Total()
		if total == nil then
			if not InCombatLockdown() and retries < RETRY_MAX then
				retries = retries + 1
				Schedule(RETRY_GAP)
			end
			return
		end
		pending, retries = false, 0
		local dmg = total - baseline
		if dmg < 0 then dmg = total end
		lastPlain = total
		if dmg > 0 and M:IsRunning() then M:ShowValue(dmg) end
	end

	Schedule = function(delay)
		if resolveTimer then resolveTimer:Cancel() end
		resolveTimer = C_Timer.NewTimer(delay, Resolve)
	end

	function M:OnCast()
		local total = Total()
		if total ~= nil then lastPlain = total end
		if not pending then
			baseline = lastPlain or 0
			pending = true
		end
		castAt, retries = GetTime(), 0
		Schedule(opts.settle)
	end

	function M:Cancel()
		pending, retries = false, 0
		if resolveTimer then resolveTimer:Cancel() resolveTimer = nil end
	end

	-- the fight ended (or restrictions lifted): read what could not be read
	function M:Nudge()
		if not pending then return end
		retries = 0
		Schedule(RETRY_GAP)
	end

	function M:ResetMeter() lastPlain, baseline = 0, 0 end

	function M:StartMeterEvents()
		self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(self, _, _, _, spellID)
			if IsSecret(spellID) then return end
			if opts.isTrigger(spellID) then self:OnCast() end
		end)
		self:RegisterEvent("PLAYER_REGEN_ENABLED", "Nudge")
		pcall(self.RegisterEvent, self, "ADDON_RESTRICTION_STATE_CHANGED", "Nudge")
		pcall(self.RegisterEvent, self, "DAMAGE_METER_RESET", "ResetMeter")
		self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
			self:Cancel()
			self:After(2, function()
				if pending then return end
				local total = Total()
				if total ~= nil then lastPlain = total end
			end)
		end)
	end

	function M:OnDisable()
		self:Cancel()
		if display and not self:IsPreview() then display:Hide() end
	end

	function M:OnRefresh()
		if not (display or self:IsPreview()) then return end
		local d = Display()
		XUI.Movers:Apply(d)
		if self:IsPreview() then
			Paint(opts.preview or 12500000)
			d:Show()
		elseif shownValue and self:IsRunning() then
			Paint(shownValue)
			d:Show()
		else
			d:Hide()
		end
	end
end

--------------------------------------------------------------------------------
-- San'layn trigger: Dancing Rune Weapon (Blood) or Dark Transformation
-- (Unholy) is what summons the Vampiric Strike beast / opens the window.
--------------------------------------------------------------------------------
local DRW = 49028
local DARK_TRANSFORMATION = { [1233448] = true, [63560] = true }

local function BaseOf(id)
	local v = C_Spell and C_Spell.GetBaseSpell and XUI.Probe(C_Spell.GetBaseSpell, id)
	return type(v) == "number" and v or id
end

function Kit.IsSanlaynTrigger(id)
	if type(id) ~= "number" or IsSecret(id) then return false end
	local spec = XUI.GetSpecID()
	if spec == 250 then return id == DRW or BaseOf(id) == DRW end
	if spec == 252 then return DARK_TRANSFORMATION[id] == true end
	return false
end
