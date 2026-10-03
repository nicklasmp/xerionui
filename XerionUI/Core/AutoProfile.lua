--------------------------------------------------------------------------------
-- XerionUI - Core/AutoProfile.lua
-- Switches profile by context: the kind of instance you are in (dungeon, raid,
-- battleground, arena, scenario, open world) or, failing that, your
-- specialization. Off by default. A rule left on "no change" does nothing; the
-- instance rule wins over the specialization rule. Never in combat: a switch
-- that has to wait happens when the fight ends.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local DB = XUI.DB

XUI.INSTANCE_KINDS = {
	{ value = "none", text = "Open world" },
	{ value = "party", text = "Dungeon" },
	{ value = "raid", text = "Raid" },
	{ value = "pvp", text = "Battleground" },
	{ value = "arena", text = "Arena" },
	{ value = "scenario", text = "Scenario" },
}

local function Wanted()
	local rules = DB.global.autoProfiles
	if not rules.enabled then return nil end
	local ok, _, kind = pcall(GetInstanceInfo)
	if ok and type(kind) == "string" and not XUI.IsSecret(kind) then
		local name = rules.instance[kind]
		if name and DB:ProfileExists(name) then return name end
	end
	local spec = XUI.GetSpecID()
	local name = spec and rules.spec[spec]
	if name and DB:ProfileExists(name) then return name end
	return nil
end

local waiting = false
local function Apply()
	local name = Wanted()
	if not name or name == DB:GetProfileName() then waiting = false return end
	if InCombatLockdown() then waiting = true return end
	waiting = false
	DB:SetProfile(name)
end
local ApplySoon = XUI.Coalesce(Apply)
XUI.ApplyAutoProfile = ApplySoon

local f = CreateFrame("Frame")
XUI:On("LoggedIn", f, function()
	for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_SPECIALIZATION_CHANGED" }) do
		f:RegisterEvent(e)
	end
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" and not waiting then return end
		ApplySoon()
	end)
	ApplySoon()
end)
