--------------------------------------------------------------------------------
-- Targeted Spell Bars tweaks (EllesmereUI Mythic+ Tools)
--
-- Hide boss casts: Targeted Spell Bars' event handler is a nameless frame of
-- that module. It is found by its exact event footprint (registered for the
-- cast and plate events it needs and none it does not), and wrapped: a cast
-- start or plate add from a boss nameplate is passed on as "plate removed",
-- so the module never draws it. Switching takes effect for plates already on
-- screen.
--
-- Cast spark: a texture pinned to the right edge of each bar's fill. The fill
-- runs on SetTimerDuration, so the engine moves the spark with it - no
-- OnUpdate, no cast time read. Bars are pooled and built lazily, so cast
-- starts are watched until the pool is full, then the watcher stops.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local TSB_ADDON = "EllesmereUIMythicTimer"
local UNLOCK_KEY = "EMT_TargetedSpellBars"
local WHITE = [[Interface\Buttons\WHITE8X8]]

local M = XUI:NewModule("EUITargetedSpellBars", {
	name = "Targeted Spell Bars",
	desc = "Hide boss casts and add a cast spark to EllesmereUI's Targeted Spell Bars.",
	category = "tweaks",
	icon = [[Interface\Icons\Spell_Shadow_ShadowBolt]],
	order = 40,
	requires = TSB_ADDON,
	defaults = {
		hideBossCasts = false,
		spark = false,
		sparkWidth = 2,
		sparkColor = { 1, 1, 1, 1 },
	},
})

local IsSecret = XUI.IsSecret

local function TSBCfg()
	local db = _G._EMT_AceDB
	local prof = db and db.profile
	return prof and type(prof.tsb) == "table" and prof.tsb or nil
end

local function TSBEnabled()
	local tsb = TSBCfg()
	return tsb and tsb.enabled == true or false
end

local function EMT()
	return XUI.EUI and XUI.EUI.Module(TSB_ADDON)
end

--------------------------------------------------------------------------------
-- Boss filter
--------------------------------------------------------------------------------
local BOSS_CLASSES = { elite = true, rareelite = true, worldboss = true }

local function EffLevel(unit)
	local lvl = XUI.Probe(UnitEffectiveLevel, unit)
	return type(lvl) == "number" and lvl or nil
end

local function IsBossUnit(unit)
	if not unit then return false end
	local class = XUI.Probe(UnitClassification, unit)
	if not BOSS_CLASSES[class] then return false end
	local lvl = EffLevel(unit)
	if lvl == -1 then return true end
	if UnitIsLieutenant and XUI.Ask(UnitIsLieutenant, unit) then return false end
	if class == "worldboss" then return true end
	if not lvl then return false end
	local plvl = EffLevel("player")
	return plvl ~= nil and lvl >= plvl + 2
end

local MUST_HAVE = {
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP",
}
local MUST_NOT = {
	"PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_LOGIN", "ADDON_LOADED",
	"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_HEALTH", "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED",
	"SPELL_UPDATE_COOLDOWN", "CHALLENGE_MODE_START", "GROUP_ROSTER_UPDATE", "NAME_PLATE_CREATED",
	"COMBAT_LOG_EVENT_UNFILTERED", "ZONE_CHANGED_NEW_AREA",
}

local function IsTSBFrame(f)
	if f.IsForbidden and f:IsForbidden() then return false end
	if f:GetObjectType() ~= "Frame" or f:GetName() ~= nil or f:GetParent() ~= nil then return false end
	if f:GetNumChildren() ~= 0 or f:GetNumRegions() ~= 0 then return false end
	if type(f:GetScript("OnEvent")) ~= "function" then return false end
	for _, e in ipairs(MUST_HAVE) do
		if f:IsEventRegistered(e) ~= true then return false end
	end
	for _, e in ipairs(MUST_NOT) do
		if f:IsEventRegistered(e) == true then return false end
	end
	return true
end

local function FindTSBFrame()
	if type(GetFramesRegisteredForEvent) ~= "function" then return nil end
	local ok, list = pcall(function() return { GetFramesRegisteredForEvent("UNIT_SPELLCAST_EMPOWER_STOP") } end)
	if not ok then return nil end
	for _, f in ipairs(list) do
		local okF, match = pcall(IsTSBFrame, f)
		if okF and match then return f end
	end
	return nil
end

local DROP = { NAME_PLATE_UNIT_ADDED = true, UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_EMPOWER_START = true }

local function IsPlate(unit)
	return type(unit) == "string" and unit:sub(1, 9) == "nameplate"
end

local evtFrame, origOnEvent
local lastScan = 0

local function Install(force)
	if evtFrame then return true end
	local now = GetTime()
	if not force and now - lastScan < 5 then return false end
	lastScan = now
	local f = FindTSBFrame()
	local orig = f and f:GetScript("OnEvent")
	if type(orig) ~= "function" then return false end
	evtFrame, origOnEvent = f, orig
	f:SetScript("OnEvent", function(self, event, unit, ...)
		if unit and DROP[event] and IsPlate(unit) and M.running and M.db.hideBossCasts and IsBossUnit(unit) then
			return origOnEvent(self, "NAME_PLATE_UNIT_REMOVED", unit)
		end
		return origOnEvent(self, event, unit, ...)
	end)
	return true
end

-- plates already up are re-announced with the filter as it is now
local function Resync()
	if not evtFrame then return end
	local np = C_NamePlate
	local ok, plates = pcall(np.GetNamePlates)
	if not ok or type(plates) ~= "table" then return end
	local filtering = M.running and M.db.hideBossCasts
	for _, p in ipairs(plates) do
		local unit = p.namePlateUnitToken
		if unit then
			if filtering and IsBossUnit(unit) then
				pcall(origOnEvent, evtFrame, "NAME_PLATE_UNIT_REMOVED", unit)
			else
				pcall(origOnEvent, evtFrame, "NAME_PLATE_UNIT_ADDED", unit)
			end
		end
	end
end

function M:Redetect()
	local ok = Install(true)
	if ok then
		Resync()
		self:Print("attached to Targeted Spell Bars.")
	elseif not TSBEnabled() then
		self:Print("Targeted Spell Bars is switched off in EllesmereUI - turn it on first.")
	else
		self:Print("could not find Targeted Spell Bars yet. It only exists where its bars can show; try again there.")
	end
end

--------------------------------------------------------------------------------
-- Spark
--------------------------------------------------------------------------------
local sparks = {}
local barCount, knownChildren = 0, 0
local watching = false

local function Container()
	local E = _G.EllesmereUI
	local reg = E and E._unlockRegisteredElements
	local elem = reg and reg[UNLOCK_KEY]
	if not (elem and type(elem.getFrame) == "function") then return nil end
	local ok, f = pcall(elem.getFrame)
	if ok and type(f) == "table" and f.GetChildren then return f end
	return nil
end

local function MaxBars()
	local tsb = TSBCfg()
	return tsb and type(tsb.maxBars) == "number" and tsb.maxBars or 5
end

local function StyleSpark(holder)
	local spark = sparks[holder]
	if not spark then return end
	local db = M.db
	local fill = M.running and db.spark and holder.sb:GetStatusBarTexture()
	if not fill then
		spark:Hide()
		return
	end
	spark:SetVertexColor(XUI.UnpackColor(db.sparkColor))
	spark:SetWidth(db.sparkWidth)
	spark:ClearAllPoints()
	spark:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
	spark:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
	spark:Show()
end

local function Decorate(holder)
	local spark = holder.sb:CreateTexture(nil, "OVERLAY", nil, 7)
	spark:SetTexture(WHITE)
	if spark.SetSnapToPixelGrid then
		spark:SetSnapToPixelGrid(false)
		spark:SetTexelSnappingBias(0)
	end
	spark:Hide()
	sparks[holder] = spark
	barCount = barCount + 1
	-- a restyle mints a new fill texture
	hooksecurefunc(holder.sb, "SetStatusBarTexture", function() StyleSpark(holder) end)
	StyleSpark(holder)
end

local function IsBar(f)
	return type(f) == "table" and not sparks[f] and type(f.sb) == "table" and f.sb.GetStatusBarTexture ~= nil
end

local function Scan()
	if not (M.running and M.db.spark and TSBEnabled()) then return end
	local c = Container()
	if not c then return end
	local n = c:GetNumChildren()
	if n == knownChildren then return end
	knownChildren = n
	for _, kid in ipairs({ c:GetChildren() }) do
		if IsBar(kid) then Decorate(kid) end
	end
end

local SyncWatcher
SyncWatcher = function()
	local want = M.running and M.db.spark and TSBEnabled() and barCount < MaxBars()
	want = want and true or false
	if want == watching then return end
	watching = want
	local events = { "NAME_PLATE_UNIT_ADDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START" }
	for _, e in ipairs(events) do
		if want then
			M:RegisterEvent(e, function(self, _, unit)
				if IsPlate(unit) then self:After(0, function() Scan() SyncWatcher() end) end
			end)
		else
			M:UnregisterEvent(e)
		end
	end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
function M:OnEnable()
	watching = false
	local emt = EMT()
	if emt and type(emt.TSB_Refresh) == "function" then
		self:SecureHook(emt, "TSB_Refresh", function() Scan() SyncWatcher() end)
	end
	if emt and type(emt.TSB_SetPreview) == "function" then
		self:SecureHook(emt, "TSB_SetPreview", function() Scan() SyncWatcher() end)
	end
	local function maybeInstall(self)
		if not self.db.hideBossCasts then return end
		self:After(0, function()
			Install(false)
			Resync()
		end)
	end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", maybeInstall)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", maybeInstall)
	self:RegisterEvent("CHALLENGE_MODE_START", maybeInstall)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", maybeInstall)
end

function M:OnDisable()
	watching = false
	Resync()
	for holder in pairs(sparks) do StyleSpark(holder) end
end

function M:OnRefresh()
	if not self.running then return end
	if self.db.hideBossCasts then Install(true) end
	Resync()
	Scan()
	for holder in pairs(sparks) do StyleSpark(holder) end
	SyncWatcher()
end

-- EllesmereUI's own preview of the bars.
function M:TogglePreview()
	local emt = EMT()
	if not (emt and type(emt.TSB_SetPreview) == "function") then return end
	if not TSBEnabled() then
		self:Print("Targeted Spell Bars is switched off in EllesmereUI - turn it on there first.")
		return
	end
	local on = type(emt.TSB_IsPreview) == "function" and select(2, pcall(emt.TSB_IsPreview))
	pcall(emt.TSB_SetPreview, not on)
end
