--------------------------------------------------------------------------------
-- Dancing Rune Weapon sound (Blood)
-- A sound when Dancing Rune Weapon is extended (refreshed) and, optionally,
-- when it starts. The Cooldown Manager's frame for the weapon is hooked: its
-- aura update hands over the buff's expiration where readable, so only a
-- later expiration counts as a refresh; where it is secret every update
-- rings. The weapon must be on a Cooldown Manager bar (buff or cooldown).
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates

local DRW_ABILITY, DRW_BUFF = 49028, 81256
local RING_GAP, SETTLE = 0.3, 3

local M = XUI:NewModule("DRWSound", {
	name = "Dancing Rune Weapon Sound",
	desc = "A sound when Dancing Rune Weapon is extended or starts.",
	category = "class",
	icon = [[Interface\Icons\INV_Sword_07]],
	order = 20,
	classes = { "DEATHKNIGHT" },
	specs = { 250 },
	defaults = {
		onRefresh = true,
		onGain = false,
		alert = T.Alert("SOUND", { sound = "Xerion: External" }),
	},
})

local IsSecret = XUI.IsSecret
local ident = setmetatable({}, { __mode = "k" })
local lastExp = setmetatable({}, { __mode = "k" })
local removedAt = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local hookedViewers = {}
local lastRing, quietUntil = 0, 0

local function IsDRW(f)
	local id = f and f.GetCooldownID and XUI.Probe(f.GetCooldownID, f)
	if type(id) ~= "number" then return false end
	local c = ident[f]
	if c and c.id == id then return c.drw end
	local drw = XUI.CooldownMatches(id, DRW_BUFF) or XUI.CooldownMatches(id, DRW_ABILITY)
	ident[f] = { id = id, drw = drw }
	return drw
end

local function ReadExpiration(f)
	if not f.GetAuraDataCached then return nil end
	local ok, data = pcall(f.GetAuraDataCached, f)
	if not ok or IsSecret(data) or type(data) ~= "table" then return nil end
	local exp = data.expirationTime
	if IsSecret(exp) or type(exp) ~= "number" then return nil end
	return exp
end

local function Ring()
	local now = GetTime()
	if now < quietUntil or now - lastRing < RING_GAP then return end
	lastRing = now
	XUI.Audio:Play(M.db.alert, "Rune Weapon")
end

local function OnUpdated(f)
	if not M.running or not IsDRW(f) then return end
	local exp = ReadExpiration(f)
	local last = lastExp[f]
	lastExp[f] = exp
	if not M.db.onRefresh then return end
	if exp and last and exp <= last + 0.05 then return end
	Ring()
end

local function OnGain(f)
	if not M.running or not IsDRW(f) then return end
	lastExp[f] = ReadExpiration(f)
	-- removed and re-added in the same frame is a refresh
	local replaced = removedAt[f] == GetTime()
	if (replaced and M.db.onRefresh) or M.db.onGain then Ring() end
end

local function OnRemoved(f)
	lastExp[f] = nil
	removedAt[f] = GetTime()
end

local function Hook(f)
	if not f or hooked[f] or type(f.OnUnitAuraUpdatedEvent) ~= "function" then return end
	hooked[f] = true
	hooksecurefunc(f, "OnUnitAuraUpdatedEvent", OnUpdated)
	if type(f.TriggerAuraAppliedAlert) == "function" then hooksecurefunc(f, "TriggerAuraAppliedAlert", OnGain) end
	if type(f.TriggerAuraRemovedAlert) == "function" then hooksecurefunc(f, "TriggerAuraRemovedAlert", OnRemoved) end
end

local function Scan()
	if not M.running then return end
	for _, name in ipairs(XUI.CDM_ALL_VIEWERS) do
		local viewer = _G[name]
		if viewer and viewer.GetChildren then
			for _, f in ipairs({ viewer:GetChildren() }) do Hook(f) end
		end
	end
end
local QueueScan = XUI.Coalesce(Scan)

local function HookViewers()
	for _, name in ipairs(XUI.CDM_ALL_VIEWERS) do
		local v = _G[name]
		if v and v.RefreshData and not hookedViewers[v] then
			hookedViewers[v] = true
			M:SecureHook(v, "RefreshData", QueueScan)
		end
	end
end

function M:OnEnable()
	-- the Cooldown Manager builds its frames on its own schedule
	local function pass()
		HookViewers()
		Scan()
	end
	pass()
	self:NewTicker(5, pass)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		quietUntil = GetTime() + SETTLE
		self:After(2, pass)
		self:After(6, pass)
	end)
end

function M:TestAlert()
	XUI.Audio:Play(self.db.alert, "Rune Weapon", true)
end
