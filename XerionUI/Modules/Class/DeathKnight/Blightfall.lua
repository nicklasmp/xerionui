--------------------------------------------------------------------------------
-- Blightfall chain (Unholy)
-- Dark Transformation, then Soul Reaper a few seconds later, then Blightfall a
-- few seconds after that, so both land inside the window they amplify. Each
-- press arms a countdown for the NEXT press:
--   Dark Transformation -> counts to Soul Reaper (when talented)
--   Soul Reaper         -> while that countdown is armed, counts to Blightfall
--   Blightfall          -> chain done
-- A countdown that reaches 0 stays on NOW until the press, for at most 20 s,
-- and leaving combat clears it. Everything runs on our own clock from your own
-- readable casts. The countdown runs red, yellow, green over the last seconds;
-- optional voice counts it out.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local DARK_TRANSFORMATION = { [1233448] = true, [63560] = true }
local SOUL_REAPER, BLIGHTFALL, BLIGHTFALL_TALENT = 343294, 1271967, 1271974
local LABELS = { [SOUL_REAPER] = "Soul Reaper", [BLIGHTFALL] = "Blightfall" }
local FALLBACK = { [SOUL_REAPER] = 636333, [BLIGHTFALL] = 5976940 }
local GRACE, RAMP, GREEN_AT, NOW_AT, SAY_LABEL, SAY_COUNT = 20, 3, 1, 0.05, 5, 3
local RED, YELLOW, GREEN = { 1, 0.15, 0.15 }, { 1, 0.85, 0.1 }, { 0.3, 1, 0.3 }

local M = XUI:NewModule("Blightfall", {
	name = "Blightfall Chain",
	desc = "Countdowns for Soul Reaper and Blightfall after Dark Transformation.",
	category = "class",
	icon = 5976940,
	order = 70,
	classes = { "DEATHKNIGHT" },
	specs = { 252 },
	untested = true,
	defaults = {
		delaySR = 7,
		delayBF = 7,
		decimals = 1,
		voice = true,
		alert = T.Alert("NONE"),
		growPulse = false,
		growStart = 3,
		growMax = 2,
		icon = T.Icon(64),
		border = T.Border(),
		glow = T.Glow(true, { useGlobal = false, type = "PIXEL", color = { 0.72, 0.4, 1, 1 } }),
		timerText = T.Font(24, { enabled = true, anchor = "BOTTOM", y = -20 }),
		position = T.Position(0, -220),
	},
})

M.PREVIEW_STATES = {
	{ value = "loop", text = "Looping chain" },
	{ value = "sr", text = "Soul Reaper" },
	{ value = "bf", text = "Blightfall" },
	{ value = "now", text = "NOW" },
}

local IsSecret = XUI.IsSecret
local display, ticker
local step, armedAt, armedDelay = nil, 0, 0
local lastSecond, shownID

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateIcon("XUI_Blightfall")
	display:Hide()
	XUI.Movers:Register(display, M, "position")
	return display
end

local function Known(id) return XUI.IsSpellKnown(id) end

local function Lerp(a, b, t) return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t end

local function CountdownColor(eta)
	if eta <= GREEN_AT then return GREEN[1], GREEN[2], GREEN[3] end
	if eta >= RAMP then return RED[1], RED[2], RED[3] end
	local mid = (RAMP + GREEN_AT) / 2
	if eta > mid then return Lerp(RED, YELLOW, (RAMP - eta) / (RAMP - mid)) end
	return Lerp(YELLOW, GREEN, (mid - eta) / (mid - GREEN_AT))
end

-- the spell being counted to and the seconds left, or nil
local function Current()
	if M:IsPreview() then
		local state = M.previewState
		if state == "sr" then return SOUL_REAPER, M.db.delaySR end
		if state == "bf" then return BLIGHTFALL, M.db.delayBF end
		if state == "now" then return BLIGHTFALL, 0 end
		local a, b = M.db.delaySR, M.db.delayBF
		local total = a + b
		if total <= 0 then return SOUL_REAPER, 0 end
		local e = (GetTime() % total)
		if e < a then return SOUL_REAPER, a - e end
		return BLIGHTFALL, total - e
	end
	if not step then return nil end
	local left = armedDelay - (GetTime() - armedAt)
	if left < -GRACE then step = nil return nil end
	return step, math.max(0, left)
end

local function CountdownVoice(label, eta)
	local second = (eta <= NOW_AT) and 0 or math.ceil(eta)
	if second == lastSecond then return end
	lastSecond = second
	if M:IsPreview() then return end
	local db = M.db
	if second == 0 then
		if db.voice then XUI.Audio:Speak("Now") end
		XUI.Audio:Play(db.alert, nil, true)
	elseif db.voice then
		if second == SAY_LABEL then XUI.Audio:Speak(label .. " in")
		elseif second <= SAY_COUNT then XUI.Audio:Speak(tostring(second)) end
	end
end

local function Render()
	local d, db = Display(), M.db
	local id, eta = Current()
	if not id then
		lastSecond, shownID = nil, nil
		d:SetGlow(db.glow, false)
		d:Hide()
		return
	end
	if id ~= shownID then
		shownID, lastSecond = id, nil
		d:SetIcon(XUI.GetSpellIcon(id, FALLBACK[id]))
	end
	local r, g, b = CountdownColor(eta)
	d.timer:SetText(eta <= NOW_AT and "NOW" or (db.decimals == 0 and tostring(math.ceil(eta)) or ("%.1f"):format(eta)))
	d.timer:SetTextColor(r, g, b)
	d:SetScale((db.growPulse and eta <= db.growStart and db.growStart > 0)
		and (1 + (db.growMax - 1) * (1 - eta / db.growStart)) or 1)
	d:SetGlow(db.glow, eta <= RAMP)
	d:Show()
	CountdownVoice(LABELS[id], eta)
end

local function Arm(spell, delay)
	step, armedAt, armedDelay = spell, GetTime(), delay
	lastSecond = nil
end

local function OnCast(self, _, _, _, spellID)
	if IsSecret(spellID) or type(spellID) ~= "number" then return end
	local db = self.db
	if DARK_TRANSFORMATION[spellID] then
		if Known(SOUL_REAPER) then Arm(SOUL_REAPER, db.delaySR) else step = nil end
	elseif spellID == SOUL_REAPER then
		if step == SOUL_REAPER and (Known(BLIGHTFALL_TALENT) or Known(BLIGHTFALL)) then
			Arm(BLIGHTFALL, db.delayBF)
		elseif step == SOUL_REAPER then
			step = nil
		end
	elseif spellID == BLIGHTFALL then
		step = nil
	end
	Render()
end

function M:OnEnable()
	Display()
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", OnCast)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() step = nil Render() end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() step = nil Render() end)
	-- the countdown redraws ten times a second while one is running
	ticker = self:NewTicker(0.1, function() if step then Render() end end)
end

function M:OnDisable()
	step, ticker = nil, nil
	if display and not self:IsPreview() then display:Hide() end
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d, db = Display(), self.db
	XUI.Movers:Apply(d)
	d:ApplyLayout(db.icon, db.border)
	d:ApplyTimerText(db.timerText)
	if self:IsPreview() and not self._previewTicker then
		self._previewTicker = C_Timer.NewTicker(0.1, function()
			if M:IsPreview() then Render() else M._previewTicker:Cancel() M._previewTicker = nil end
		end)
	end
	Render()
end

function M:TestVoice() XUI.Audio:Speak("Soul Reaper in") end

-- as if Dark Transformation had just been cast
function M:Test()
	if not self:RequireRunning() then return end
	Arm(SOUL_REAPER, self.db.delaySR)
	Render()
end
