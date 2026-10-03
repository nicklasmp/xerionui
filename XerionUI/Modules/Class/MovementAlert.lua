--------------------------------------------------------------------------------
-- Movement alert (every class)
-- "No Blink 4" while your movement ability for this specialization is on
-- cooldown, and "Free Movement 9" for the 10 seconds a Time Spiral lights your
-- movement abilities (read off the spell activation glow).
-- Ported from ItruliaQoL (MIT, (c) Itrulia); Time Spiral list from the Time
-- Spiral Tracker addon.
--
-- Midnight: cooldown numbers can be secret in combat. A secret answer counts as
-- unknown and that ability is skipped, so the alert never guesses. A cooldown
-- that is only the global cooldown is not shown, and the abilities listed first
-- take priority.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

-- spec ID -> movement abilities, in priority order
local BY_SPEC = {
	[250] = { 48265, 212552 }, [251] = { 48265, 212552 }, [252] = { 48265, 212552 },
	[577] = { 195072 }, [581] = { 189110 }, [1480] = { 1234796 },
	[102] = { 102401, 252216, 1850 }, [103] = { 102401, 252216, 1850 }, [104] = { 102401, 106898 }, [105] = { 102401, 252216, 1850 },
	[1467] = { 358267 }, [1468] = { 358267 }, [1473] = { 358267 },
	[253] = { 781, 186257 }, [254] = { 781, 186257 }, [255] = { 781, 186257 },
	[62] = { 212653, 1953 }, [63] = { 212653, 1953 }, [64] = { 212653, 1953 },
	[268] = { 115008, 109132 }, [269] = { 109132 }, [270] = { 109132 },
	[65] = { 190784 }, [66] = { 190784 }, [70] = { 190784 },
	[256] = { 121536, 73325 }, [257] = { 121536, 73325 }, [258] = { 121536, 73325 },
	[259] = { 36554 }, [260] = { 195457 }, [261] = { 36554 },
	[262] = { 79206, 90328, 192063 }, [263] = { 90328, 192063 }, [264] = { 79206, 90328, 192063 },
	[265] = { 48020 }, [266] = { 48020 }, [267] = { 48020 },
	[71] = { 6544, 100 }, [72] = { 6544, 100 }, [73] = { 6544, 100 },
}

-- class -> abilities a Time Spiral frees (Time Spiral Tracker's list)
local TIME_SPIRAL = {
	DEATHKNIGHT = { 48265 },
	DEMONHUNTER = { 195072, 189110, 1234796 },
	DRUID = { 1850, 252216 },
	EVOKER = { 358267 },
	HUNTER = { 186257 },
	MAGE = { 212653, 1953 },
	MONK = { 119085, 361138 },
	PALADIN = { 190784 },
	PRIEST = { 73325 },
	ROGUE = { 2983 },
	SHAMAN = { 192063, 58875, 79206 },
	WARLOCK = { 48020 },
	WARRIOR = { 6544 },
}
local TIME_SPIRAL_DEFAULT_OFF = { [73325] = true } -- Leap of Faith

local TS_SPELLS = {}
for _, ids in pairs(TIME_SPIRAL) do
	for _, id in ipairs(ids) do TS_SPELLS[id] = not TIME_SPIRAL_DEFAULT_OFF[id] end
end

-- A talent that makes one cast also light another spell's glow: that glow is
-- the cast's own, not a Time Spiral. { talent, spellId, delay }
local GLOW_ECHOES = {
	DEMONHUNTER = {
		[577] = {
			{ talent = 427640, spellId = 370965, delay = 1 },
			{ talent = 427640, spellId = 198793 },
			{ talent = 427794, spellId = 195072 },
		},
	},
	WARLOCK = {
		[265] = { { talent = 385899, spellId = 385899 } },
		[266] = { { talent = 385899, spellId = 385899 } },
		[267] = { { talent = 385899, spellId = 385899 } },
	},
}
local OWN_GCD = { [1234796] = 0.8 }
local TIME_SPIRAL_SECONDS = 10

local function DefaultTracked()
	local out = {}
	for spec, ids in pairs(BY_SPEC) do
		local t = {}
		for _, id in ipairs(ids) do t[id] = true end
		out[spec] = t
	end
	return out
end

local M = XUI:NewModule("MovementAlert", {
	name = "Movement Alert",
	desc = "Warns when your movement ability is on cooldown, and when a Time Spiral frees it.",
	category = "class",
	icon = [[Interface\Icons\Ability_Rogue_Sprint]],
	order = 110,
	untested = true,
	defaults = {
		precision = 0,
		color = { 1, 1, 1, 1 },
		font = T.Font(14),
		trackedSpells = DefaultTracked(),
		showTimeSpiral = true,
		timeSpiralSpells = TS_SPELLS,
		timeSpiralText = "Free Movement",
		timeSpiralColor = { 0.5333, 1, 0, 1 },
		timeSpiralAlert = T.Alert("NONE"),
		position = T.Position(0, 50),
	},
})
M.BY_SPEC, M.TIME_SPIRAL = BY_SPEC, TIME_SPIRAL

local IsSecret = XUI.IsSecret
local display, ticker
local spells, ignoreCd, ignoreGlow, glowIgnores = {}, false, false, nil
local timeSpiralOn
local previewName

local function Display()
	if display then return display end
	display = XUI.Widgets:CreateText("XUI_MovementAlert")
	display:Hide()
	XUI.Movers:Register(display, M, "position")
	return display
end

function M:IsTracked(spec, id)
	local t = self.db.trackedSpells[spec]
	return t and t[id] == true or false
end

function M:SetTracked(spec, id, on)
	local all = self.db.trackedSpells
	all[spec] = all[spec] or {}
	all[spec][id] = on and true or false -- false, not nil: a default switched off stays off
end

function M:IsTimeSpiralTracked(id)
	if TS_SPELLS[id] == nil then return false end
	local v = self.db.timeSpiralSpells[id]
	if v == nil then return TS_SPELLS[id] end
	return v == true
end

function M:SetTimeSpiralTracked(id, on) self.db.timeSpiralSpells[id] = on and true or false end

-- every tracked ability the character has, in list order
local function Cache()
	spells = {}
	local spec = XUI.GetSpecID()
	local ids = spec and BY_SPEC[spec]
	if ids then
		for _, id in ipairs(ids) do
			if M:IsTracked(spec, id) and XUI.IsSpellKnown(id) then
				local name = XUI.GetSpellName(id)
				spells[#spells + 1] = { id = id, name = name }
			end
		end
	end
	glowIgnores = nil
	local echoes = GLOW_ECHOES[XUI.playerClass]
	echoes = echoes and spec and echoes[spec]
	if echoes then
		glowIgnores = {}
		for _, e in ipairs(echoes) do
			if XUI.IsSpellKnown(e.talent) then glowIgnores[e.spellId] = 0.05 + (e.delay or 0) end
		end
	end
end

-- the first tracked ability on a real cooldown, with the seconds left; abilities
-- whose cooldown reads secret are skipped
local function OnCooldown()
	if ignoreCd then return nil end
	for _, s in ipairs(spells) do
		local info = C_Spell.GetSpellCooldown(s.id)
		if type(info) == "table" and not IsSecret(info) then
			local left, onGCD = info.timeUntilEndOfStartRecovery, info.isOnGCD
			if type(left) == "number" and not IsSecret(left) and not IsSecret(onGCD) and left > 0
				and not onGCD and (onGCD ~= nil or XUI.playerClass == "WARLOCK") then
				return s, left
			end
		end
	end
	return nil
end

local function Precision() return M.db.precision == 1 and "%.1f" or "%.0f" end

local function Hex(c)
	local r, g, b = XUI.UnpackColor(c)
	return ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function Tick()
	local d = display
	if not d or M:IsPreview() then return end
	if timeSpiralOn then
		local left = TIME_SPIRAL_SECONDS - (GetTime() - timeSpiralOn)
		if left <= 0 then timeSpiralOn = nil else
			d:SetText(("|cff%s%s|r\n|cff%s%s|r"):format(Hex(M.db.timeSpiralColor), M.db.timeSpiralText, Hex(M.db.timeSpiralColor), Precision():format(left)))
			d:Show()
			return
		end
	end
	local s, left = OnCooldown()
	if s then
		d:SetText(("No %s\n%s"):format(s.name, Precision():format(left)))
		d:Show()
	else
		d:Hide()
	end
end

function M:OnEnable()
	Display()
	Cache()
	local function recache(self) if not InCombatLockdown() then Cache() end end
	for _, e in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "SPELLS_CHANGED" }) do
		self:RegisterEvent(e, recache)
	end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self) recache(self) timeSpiralOn = nil end)
	self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(self, _, spellID)
		if not self.db.showTimeSpiral or ignoreGlow or IsSecret(spellID) then return end
		if self:IsTimeSpiralTracked(spellID) then
			timeSpiralOn = GetTime()
			XUI.Audio:Play(self.db.timeSpiralAlert, self.db.timeSpiralText)
		end
	end)
	self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(self, _, spellID)
		if IsSecret(spellID) then return end
		-- membership, not the filter, so a spell switched off mid glow still clears its alert
		if TS_SPELLS[spellID] ~= nil then timeSpiralOn = nil end
	end)
	self:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player", function(self, _, _, _, _, spellID)
		if IsSecret(spellID) then return end
		local wait = glowIgnores and glowIgnores[spellID]
		if wait then
			ignoreGlow = true
			C_Timer.After(wait, function() ignoreGlow = false end)
		end
		wait = OWN_GCD[spellID]
		if wait then
			ignoreCd = true
			C_Timer.After(wait, function() ignoreCd = false end)
		end
	end)
	ticker = self:NewTicker(0.1, Tick)
end

function M:OnDisable()
	ticker, timeSpiralOn = nil, nil
	if display and not self:IsPreview() then display:Hide() end
end

function M:OnRefresh()
	if not (display or self:IsPreview()) then return end
	local d, db = Display(), self.db
	XUI.Movers:Apply(d)
	d:ApplyStyle(db.font)
	d:SetTextColor(XUI.UnpackColor(db.color))
	if self:IsPreview() then
		local spec = XUI.GetSpecID()
		local ids = spec and BY_SPEC[spec]
		previewName = ids and XUI.GetSpellName(ids[1]) or "movement ability"
		d:SetText(("No %s\n%s"):format(previewName, Precision():format(15.3)))
		d:Show()
	elseif self.running then
		Cache()
		Tick()
	else
		d:Hide()
	end
end

-- a Time Spiral, as if the glow had just lit
function M:Test()
	if not self:RequireRunning() then return end
	timeSpiralOn = GetTime()
	XUI.Audio:Play(self.db.timeSpiralAlert, self.db.timeSpiralText, true)
	Tick()
end

function M:DebugInfo()
	local names = {}
	for _, s in ipairs(spells) do names[#names + 1] = s.name .. " (" .. s.id .. ")" end
	local s, left = OnCooldown()
	return {
		("spec %s, tracked and known: %s"):format(tostring(XUI.GetSpecID()), #names > 0 and table.concat(names, ", ") or "none"),
		("on cooldown: %s, Time Spiral showing: %s"):format(s and (s.name .. " " .. tostring(left)) or "no", tostring(timeSpiralOn ~= nil)),
	}
end
