--------------------------------------------------------------------------------
-- XerionUI - Core/Health.lua
-- Two things that make "does it work in the game?" answerable without guessing:
--
--  * Self-check: every module that leans on something outside this addon (an
--    EllesmereUI module and its fields, the Cooldown Manager, the damage meter,
--    the aura sound API ...) has a check. Issues are shown on the module's page
--    and sidebar entry, so a game or EllesmereUI update that moves something is
--    noticed the first time you look, not after a day of "nothing happens".
--  * Diagnostics: one text with everything needed to understand a problem
--    (build, class, EllesmereUI modules, module status, recent errors, the
--    module's own DebugInfo lines). The options copy it with one click.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local Health = {}
XUI.Health = Health

local IsSecret = XUI.IsSecret

local function EUI(name) return XUI.EUI and XUI.EUI.Module(name) end

local function HasViewer(name) return type(_G[name]) == "table" end

--------------------------------------------------------------------------------
-- The checks: function(problem) calls problem("text") for each issue
--------------------------------------------------------------------------------
local function NeedCooldownManager(problem)
	if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then
		problem("the Cooldown Manager API is missing in this client")
	elseif not HasViewer("BuffIconCooldownViewer") then
		problem("the Cooldown Manager's buff viewer was not found - turn the Cooldown Manager on in the game's options")
	end
end

local function NeedDamageMeter(problem)
	local DM, E = _G.C_DamageMeter, _G.Enum
	if not (DM and DM.GetCombatSessionSourceFromType and E and E.DamageMeterSessionType and E.DamageMeterType) then
		problem("the game's damage meter API is missing")
	end
end

local function NeedAuraSounds(problem)
	local api = C_UnitAuras
	if not (api and api.AddAuraSound and api.RemoveAuraSound and Enum and Enum.UnitAuraSoundTrigger) then
		problem("the game's aura sound API is missing")
	end
end

local function NeedAuraContainers(problem)
	if not XUI.HasAuraContainers() then problem("the aura containers (12.1) are missing") end
end

Health.CHECKS = {
	EUIFocusCastbar = function(problem)
		local mod = EUI("EllesmereUIMythicTimer")
		if not mod then problem("EllesmereUI Mythic+ Tools is not loaded") return end
		if type(mod.TFB_Refresh) ~= "function" then problem("Mythic+ Tools has no TFB_Refresh - EllesmereUI may have changed") end
		local db = _G._EMT_AceDB
		if not (db and db.profile and db.profile.tfb and db.profile.tfb.focus) then
			problem("the focus cast bar settings (_EMT_AceDB.profile.tfb.focus) were not found")
		end
	end,
	EUIPartyFrames = function(problem)
		local rf = EUI("EllesmereUIRaidFrames")
		if not rf then problem("EllesmereUI Raid Frames is not loaded") return end
		if type(rf.GetFFD) ~= "function" then problem("Raid Frames has no GetFFD - EllesmereUI may have changed") end
		if type(rf._partyAllButtons) ~= "table" then problem("Raid Frames has no _partyAllButtons list") end
		if type(rf._partyUnitToButton) ~= "table" then problem("Raid Frames has no _partyUnitToButton map") end
		local ak = _G.EllesmereUI and _G.EllesmereUI.AuraKit
		if not (ak and ak.styles and ak.styles["rf:debuff:party"]) then
			problem("EllesmereUI's party debuff style (AuraKit rf:debuff:party) was not found - stack placement cannot work")
		end
	end,
	EUINameplates = function(problem)
		local np = _G.EllesmereNameplates_NS
		if type(np) ~= "table" then problem("EllesmereUI Nameplates is not loaded") return end
		if type(np.plates) ~= "table" then problem("Nameplates has no plates table - EllesmereUI may have changed") end
	end,
	EUITargetedSpellBars = function(problem)
		local mod = EUI("EllesmereUIMythicTimer")
		if not mod then problem("EllesmereUI Mythic+ Tools is not loaded") return end
		if type(mod.TSB_SetPreview) ~= "function" then problem("Mythic+ Tools has no TSB_SetPreview - the preview link cannot work") end
		local db = _G._EMT_AceDB
		if not (db and db.profile and db.profile.tsb) then problem("the targeted spell bars settings (_EMT_AceDB.profile.tsb) were not found") end
	end,
	EUIFocusKick = function(problem)
		if not EUI("EllesmereUICooldownManager") then problem("EllesmereUI Cooldown Manager is not loaded") end
	end,
	Interrupts = function(problem)
		local m = XUI.moduleByKey.Interrupts
		if m and m.db.displayMode == "icon" then
			local rf = EUI("EllesmereUIRaidFrames")
			if not (rf and type(rf.GetFFD) == "function") then problem("icon mode places icons on EllesmereUI's party frames, which are not available") end
		end
	end,
	CCTracker = function(problem) NeedAuraContainers(problem) NeedAuraSounds(problem) end,
	Shroud = NeedAuraContainers,
	FieryBrand = NeedAuraContainers,
	ReapersMark = NeedAuraContainers,
	ForbiddenSacrifice = NeedAuraContainers,
	Stoneform = NeedAuraContainers,
	WellHoned = NeedAuraSounds,
	BoneShield = NeedCooldownManager,
	DRWSound = NeedCooldownManager,
	ShiningLight = NeedCooldownManager,
	ElementalBlast = NeedCooldownManager,
	Ironfur = function() end, -- works without the Cooldown Manager (own icon)
	BloodBeast = NeedDamageMeter,
	SpellReflect = NeedDamageMeter,
}

local cache = {}

-- The issues of a module (a list of strings; empty when all is well), cached for
-- a few seconds so painting the sidebar costs nothing.
function Health.Issues(m, fresh)
	local entry = cache[m.key]
	local now = GetTime()
	if entry and not fresh and now - entry.at < 5 then return entry.issues end
	local issues = {}
	local check = Health.CHECKS[m.key]
	if check then
		local ok, err = pcall(check, function(text) issues[#issues + 1] = text end)
		if not ok then issues[#issues + 1] = "the self-check itself failed: " .. tostring(err) end
	end
	cache[m.key] = { at = now, issues = issues }
	return issues
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------
local function Line(lines, fmt, ...)
	lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
end

local function ModuleStatus(m)
	if (m.errorCount or 0) > 0 then return "ERRORS" end
	if m.running then return "running" end
	if not m.db.enabled then return "off" end
	local ok, why = m:CanRun()
	return ok and "enabled, not started" or ("not running: " .. tostring(why))
end

local function Header(lines)
	local version, build, _, toc = GetBuildInfo()
	Line(lines, "%s %s", XUI.TITLE or "XerionUI", tostring(XUI.version))
	Line(lines, "WoW %s (build %s, interface %s)", tostring(version), tostring(build), tostring(toc))
	local spec = XUI.GetSpecID()
	Line(lines, "class %s, spec %s, profile %s", tostring(XUI.playerClass), tostring(spec), tostring(XUI.DB:GetProfileName()))
	local loaded = {}
	for _, name in ipairs({ "EllesmereUI", "EllesmereUIMythicTimer", "EllesmereUIRaidFrames", "EllesmereUINameplates", "EllesmereUICooldownManager" }) do
		if XUI.IsAddOnLoaded(name) then loaded[#loaded + 1] = name end
	end
	Line(lines, "EllesmereUI loaded: %s", #loaded > 0 and table.concat(loaded, ", ") or "none")
	Line(lines, "aura containers: %s, in combat: %s", tostring(XUI.HasAuraContainers()), tostring(InCombatLockdown()))
end

local function ModuleBlock(lines, m)
	Line(lines, "")
	Line(lines, "[%s] %s - %s", m.key, m.name, ModuleStatus(m))
	for _, issue in ipairs(Health.Issues(m, true)) do Line(lines, "  CHECK: %s", issue) end
	for _, err in ipairs(m.errors or {}) do Line(lines, "  ERROR: %s", (err:gsub("\n", " "))) end
	if m.DebugInfo then
		local ok, info = pcall(m.DebugInfo, m)
		if ok and type(info) == "table" then
			for _, text in ipairs(info) do Line(lines, "  %s", tostring(text)) end
		else
			Line(lines, "  DebugInfo failed: %s", tostring(info))
		end
	end
	if XUI.PerfLine then
		local p = XUI.PerfLine(m)
		if p then Line(lines, "  %s", p) end
	end
end

-- One module's report, or every module's when `m` is nil.
function Health.Report(m)
	local lines = {}
	Header(lines)
	if m then
		ModuleBlock(lines, m)
	else
		for _, mod in ipairs(XUI.modules) do
			if mod.db.enabled or (mod.errorCount or 0) > 0 then ModuleBlock(lines, mod) end
		end
	end
	if XUI.errors and #XUI.errors > 0 then
		Line(lines, "")
		Line(lines, "recent errors:")
		for _, e in ipairs(XUI.errors) do Line(lines, "  %s", (tostring(e):gsub("\n", " "))) end
	end
	return table.concat(lines, "\n")
end
