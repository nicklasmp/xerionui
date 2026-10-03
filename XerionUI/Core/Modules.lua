--------------------------------------------------------------------------------
-- XerionUI - Core/Modules.lua
-- Feature modules and their lifecycle.
--
--   local M = XUI:NewModule("DeathAlert", {
--       name = "Death Alert", desc = "...", category = "group",
--       icon = 132147,              -- texture/fileID shown in the options sidebar
--       classes = { "WARRIOR" },    -- optional: only load for these classes
--       specs = { 73 },             -- optional: only run in these specializations
--       requires = "EllesmereUI",   -- optional: only run when this addon is loaded
--       defaults = { ... },         -- the module's saved settings
--       untested = true,            -- optional: flagged as untested in the options
--   })
--
-- A module RUNS while it is enabled and its load conditions hold. Running is
-- when it listens to the game: OnEnable registers events, OnDisable is called
-- after the framework has already dropped every event, timer and hook guard
-- the module made through its own API, so most modules need no OnDisable.
--
-- Display goes through OnRefresh, which is called whenever anything that
-- could change the module's look happens (settings, style, profile, preview,
-- running state). It decides what to show from IsRunning() and IsPreview():
-- a module can be previewed from the options even when it is not running.
--
-- Modules that are disabled cost nothing: no frames are created and no events
-- are registered until they are first enabled or previewed.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local DB = XUI.DB

local type, ipairs, pairs, tinsert = type, ipairs, pairs, table.insert
local SafeCall, SafeCallFor = XUI.SafeCall, XUI.SafeCallFor

XUI.CATEGORIES = {
	{ key = "general", name = "General" },
	{ key = "combat", name = "Combat" },
	{ key = "group", name = "Group" },
	{ key = "class", name = "Class" },
	{ key = "tweaks", name = "EllesmereUI Tweaks" },
}

XUI.modules = {}
XUI.moduleByKey = {}

local Module = {}
XUI.ModulePrototype = Module

--------------------------------------------------------------------------------
-- Creation
--------------------------------------------------------------------------------
function XUI:NewModule(key, info)
	assert(type(key) == "string" and not self.moduleByKey[key], "XUI:NewModule: bad or duplicate key " .. tostring(key))
	info = info or {}
	local m = setmetatable({}, { __index = Module })
	m.key = key
	m.name = info.name or key
	m.desc = info.desc
	m.category = info.category or "general"
	m.icon = info.icon
	m.order = info.order or 100
	m.classes = info.classes
	m.specs = info.specs
	m.requires = info.requires
	-- ported but never run in game by the author; the options say so
	m.untested = info.untested and true or false
	m.defaults = info.defaults or {}
	if m.defaults.enabled == nil then m.defaults.enabled = false end
	m.running = false
	m.preview = false
	m._gen = 0
	m.RefreshSoon = XUI.Coalesce(function() m:Refresh() end)

	DB:RegisterModuleDefaults(key, m.defaults)
	tinsert(self.modules, m)
	self.moduleByKey[key] = m
	return m
end

function XUI:GetModule(key)
	return self.moduleByKey[key]
end

-- Modules sorted for display: by category order, then order, then name.
function XUI:SortedModules(category)
	local out = {}
	for _, m in ipairs(self.modules) do
		if not category or m.category == category then out[#out + 1] = m end
	end
	table.sort(out, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name < b.name
	end)
	return out
end

--------------------------------------------------------------------------------
-- Load conditions
--------------------------------------------------------------------------------
local function Contains(list, value)
	if type(list) ~= "table" then return list == value end
	for i = 1, #list do
		if list[i] == value then return true end
	end
	return false
end

-- False plus a reason when the module cannot run on this character.
function Module:CanRun()
	if self.classes and not Contains(self.classes, XUI.playerClass) then
		return false, "Not available for your class."
	end
	if self.specs then
		local spec = XUI.GetSpecID()
		if spec and not Contains(self.specs, spec) then
			return false, "Not available in your current specialization."
		end
	end
	if self.requires and not XUI.IsAddOnLoaded(self.requires) then
		return false, ("Requires %s."):format(self.requires)
	end
	if self.CanLoad then
		local ok, why = self:CanLoad()
		if ok == false then return false, why end
	end
	return true
end

-- True when the module is offered on this character at all (class modules
-- for other classes are hidden from the options sidebar).
function Module:IsAvailable()
	return not self.classes or Contains(self.classes, XUI.playerClass)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local function EventFrame(m)
	local f = m._events
	if f then return f end
	f = CreateFrame("Frame")
	f.handlers = {}
	f:SetScript("OnEvent", function(_, event, ...)
		local h = f.handlers[event]
		if h then SafeCallFor(m, h, m, event, ...) end
	end)
	m._events = f
	return f
end

local function Handler(m, event, handler)
	if type(handler) == "function" then return handler end
	local method = handler or event
	return function(self, ...)
		local fn = self[method]
		if fn then fn(self, ...) end
	end
end

-- handler: function(self, event, ...), a method name, or nil for self[event].
function Module:RegisterEvent(event, handler)
	local f = EventFrame(self)
	f.handlers[event] = Handler(self, event, handler)
	f:RegisterEvent(event)
end

-- units: one unit token or a list of up to two.
function Module:RegisterUnitEvent(event, units, handler)
	local f = EventFrame(self)
	f.handlers[event] = Handler(self, event, handler)
	if type(units) == "table" then
		f:RegisterUnitEvent(event, units[1], units[2])
	else
		f:RegisterUnitEvent(event, units)
	end
end

function Module:UnregisterEvent(event)
	local f = self._events
	if not f then return end
	f.handlers[event] = nil
	f:UnregisterEvent(event)
end

function Module:UnregisterAllEvents()
	local f = self._events
	if not f then return end
	f:UnregisterAllEvents()
	wipe(f.handlers)
end

--------------------------------------------------------------------------------
-- Timers. Every timer made here dies with the module's running state.
--------------------------------------------------------------------------------
function Module:After(delay, fn)
	local gen = self._gen
	C_Timer.After(delay, function()
		if self._gen == gen then SafeCallFor(self, fn, self) end
	end)
end

function Module:NewTicker(interval, fn, iterations)
	local ticker = C_Timer.NewTicker(interval, function(t)
		SafeCallFor(self, fn, self, t)
	end, iterations)
	self._tickers = self._tickers or {}
	self._tickers[ticker] = true
	return ticker
end

function Module:CancelTicker(ticker)
	if not ticker then return end
	ticker:Cancel()
	if self._tickers then self._tickers[ticker] = nil end
end

function Module:CancelTimers()
	self._gen = self._gen + 1
	if self._tickers then
		for ticker in pairs(self._tickers) do ticker:Cancel() end
		wipe(self._tickers)
	end
end

--------------------------------------------------------------------------------
-- Hooks. hooksecurefunc cannot be undone, so a hook is installed once and
-- simply does nothing while its module is not running.
--------------------------------------------------------------------------------
function Module:SecureHook(target, method, fn)
	self._hooks = self._hooks or {}
	local id
	if type(target) == "string" then
		target, method, fn = nil, target, method
		id = method
	else
		id = tostring(target) .. ":" .. method
	end
	if self._hooks[id] then
		self._hooks[id].fn = fn
		return
	end
	local entry = { fn = fn }
	self._hooks[id] = entry
	local function hook(...)
		if self.running then SafeCallFor(self, entry.fn, self, ...) end
	end
	if target then hooksecurefunc(target, method, hook) else hooksecurefunc(method, hook) end
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------
function Module:IsRunning() return self.running end
function Module:IsPreview() return self.preview or XUI.unlockActive and self.db.enabled end
function Module:IsEnabled() return self.db.enabled end

function Module:Refresh()
	if self.OnRefresh then SafeCallFor(self, self.OnRefresh, self) end
end

local function Start(m)
	m.running = true
	m.errorCount, m.errors = 0, nil
	if m.OnEnable then SafeCallFor(m, m.OnEnable, m) end
end

local function Stop(m)
	m.running = false
	m:UnregisterAllEvents()
	m:CancelTimers()
	if m.OnDisable then SafeCallFor(m, m.OnDisable, m) end
end

-- Starts or stops the module to match its setting and load conditions.
function XUI:UpdateModuleState(m)
	if not self.loggedIn then return end
	local want = m.db.enabled and m:CanRun()
	if want and not m.running then
		Start(m)
		m:Refresh()
	elseif not want and m.running then
		Stop(m)
		m:Refresh()
	end
end

function Module:SetEnabled(on)
	self.db.enabled = on and true or false
	XUI:UpdateModuleState(self)
	XUI:Fire("ModuleStateChanged", self)
end

function Module:SetPreview(on)
	on = on and true or false
	if self.preview == on then return end
	self.preview = on
	if not on then self.previewState = nil end
	self:Refresh()
	XUI:Fire("PreviewChanged", self)
end

-- A module may list the looks its preview can take (PREVIEW_STATES, a list of
-- { value, text }); OnRefresh reads self.previewState. Setting one also starts
-- the preview.
function Module:SetPreviewState(value)
	self.previewState = value
	if not self.preview then self.preview = true end
	self:Refresh()
	XUI:Fire("PreviewChanged", self)
end

-- For Test buttons: a test goes through the module's real code, which only
-- listens while it runs.
function Module:RequireRunning()
	if self.running then return true end
	self:Print("switch the module on first - a test runs through its real code.")
	return false
end

-- True while previewing in this state (or in no particular state).
function Module:PreviewIs(value)
	return self:IsPreview() and (self.previewState == nil or self.previewState == value)
end

-- Restores defaults but keeps the module's enabled state.
function Module:Reset()
	local enabled = self.db.enabled
	if self.running then Stop(self) end
	self.db = DB:ResetModuleDB(self.key)
	self.db.enabled = enabled
	XUI.Style:Invalidate()
	if self.OnReset then SafeCall(self.OnReset, self) end
	XUI:UpdateModuleState(self)
	self:Refresh()
end

-- Called by the options panel after it wrote `path` in the module's db.
function Module:OnSettingChanged(path)
	self:RefreshSoon()
end

function XUI:NotifySettingChanged(m, path)
	XUI.Style:Invalidate()
	if path == "enabled" then
		m:SetEnabled(m.db.enabled)
	else
		SafeCallFor(m, m.OnSettingChanged, m, path)
	end
end

function Module:Print(...)
	XUI.Print(("|cffaaaaaa%s:|r"):format(self.name), ...)
end

--------------------------------------------------------------------------------
-- Global reactions
--------------------------------------------------------------------------------
local function RefreshVisible()
	for _, m in ipairs(XUI.modules) do
		if m.running or m.preview then m:RefreshSoon() end
	end
end

XUI:On("StyleChanged", Module, RefreshVisible)
XUI:On("MediaChanged", Module, RefreshVisible)

XUI:On("ProfileChanged", Module, function()
	for _, m in ipairs(XUI.modules) do
		if m.running then Stop(m) end
		m.preview = false
		m.db = DB:ModuleDB(m.key)
	end
	for _, m in ipairs(XUI.modules) do
		XUI:UpdateModuleState(m)
		m:Refresh()
	end
end)

local function EvaluateAll()
	for _, m in ipairs(XUI.modules) do XUI:UpdateModuleState(m) end
end
local EvaluateSoon = XUI.Coalesce(EvaluateAll)

--------------------------------------------------------------------------------
-- Bootstrap
--------------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= XUI.ADDON_NAME then return end
		self:UnregisterEvent("ADDON_LOADED")
		DB:Initialize()
		for _, m in ipairs(XUI.modules) do
			m.db = DB:ModuleDB(m.key)
			if m.OnInitialize then SafeCall(m.OnInitialize, m) end
		end
		XUI:Fire("Initialized")
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		XUI.loggedIn = true
		EvaluateAll()
		-- Specialization, spell and addon-dependent modules re-check their
		-- conditions (a talent or racial may only be known once the spellbook
		-- has loaded, which can be after login).
		self:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
		self:RegisterEvent("SPELLS_CHANGED")
		for _, m in ipairs(XUI.modules) do
			if m.requires and not XUI.IsAddOnLoaded(m.requires) then
				XUI.OnAddOnLoaded(m.requires, function() XUI:UpdateModuleState(m) end)
			end
		end
		XUI:Fire("LoggedIn")
		if DB.global.loginMessage then
			XUI.Printf("%s loaded. Type |cffffffff/xui|r for options.", XUI.version)
		end
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then
		EvaluateSoon()
	end
end)
