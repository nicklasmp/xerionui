--------------------------------------------------------------------------------
-- XerionUI - Core/Init.lua
-- Namespace, shared constants and small utilities every other file builds on.
--
-- Everything public hangs off one table, exposed as the global `XerionUI` so
-- the load-on-demand options addon (and macros) can reach it. Inside the addon
-- files take it from the private namespace: `local XUI = select(2, ...).XUI`.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local XUI = {}
ns.XUI = XUI
_G.XerionUI = XUI

local type, pairs, next, select, tostring = type, pairs, next, select, tostring
local pcall, xpcall, geterrorhandler = pcall, xpcall, geterrorhandler
local floor = math.floor

XUI.ADDON_NAME = ADDON_NAME
XUI.OPTIONS_ADDON = ADDON_NAME .. "_Options"
XUI.version = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"
XUI.MEDIA_PATH = [[Interface\AddOns\]] .. ADDON_NAME .. [[\Media\]]

-- Brand colours. ACCENT is the default; the live accent is read from the
-- database (XUI.DB.global.accent) once it exists, so code that paints with the
-- accent calls XUI.GetAccent() rather than reading this table.
XUI.ACCENT = { 1, 0.49, 0.04, 1 }
XUI.TITLE = "|cffff7d0aXerion|r|cffffffffUI|r"

local _, playerClass = UnitClass("player")
XUI.playerClass = playerClass

--------------------------------------------------------------------------------
-- Printing
--------------------------------------------------------------------------------
local PREFIX = "|cffff7d0aXerion|rUI:"

function XUI.Print(...)
	print(PREFIX, ...)
end

function XUI.Printf(fmt, ...)
	print(PREFIX, fmt:format(...))
end

--------------------------------------------------------------------------------
-- Midnight secret values
-- In restricted content (combat in instances) many API returns are "secret":
-- they can be passed back into the API but not compared, indexed or used in
-- arithmetic. Every read of combat data goes through these helpers so a module
-- never errors on one; a secret simply reads as "unknown".
--------------------------------------------------------------------------------
local issecretvalue = _G.issecretvalue
local issecrettable = _G.issecrettable

function XUI.IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

function XUI.IsSecretTable(t)
	return issecrettable ~= nil and issecrettable(t) or false
end

-- `v` when it is a readable value, otherwise `fallback`.
function XUI.Readable(v, fallback)
	if v == nil or (issecretvalue and issecretvalue(v)) then return fallback end
	return v
end

-- Calls fn(...) and returns its first result when the call succeeded and the
-- result is readable; nil otherwise. For API probes that may error or answer
-- with a secret.
function XUI.Probe(fn, ...)
	if not fn then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or (issecretvalue and issecretvalue(v)) then return nil end
	return v
end

--------------------------------------------------------------------------------
-- Error isolation
-- Module code runs through SafeCall so one broken feature never takes the
-- rest of the addon down with it. Errors still reach the error handler
-- (BugSack etc.) with a full stack.
--------------------------------------------------------------------------------
XUI.errors = {} -- the last few caught errors, shown by /xui debug

local function ErrorHandler(err)
	local list = XUI.errors
	list[#list + 1] = tostring(err):sub(1, 300)
	if #list > 20 then table.remove(list, 1) end
	return geterrorhandler()(err)
end

function XUI.SafeCall(fn, ...)
	if type(fn) ~= "function" then return false end
	return xpcall(fn, ErrorHandler, ...)
end

--------------------------------------------------------------------------------
-- Tables
--------------------------------------------------------------------------------
local function CopyTable(src)
	if type(src) ~= "table" then return src end
	local out = {}
	for k, v in pairs(src) do out[k] = CopyTable(v) end
	return out
end
XUI.CopyTable = CopyTable

-- A table with a [1] entry is treated as a list: defaults never merge into a
-- list index by index (that would resurrect entries the user removed), the
-- whole list is copied only when the key is missing.
local function IsList(t)
	return type(t) == "table" and t[1] ~= nil
end
XUI.IsList = IsList

local function DeepEqual(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do
		if not DeepEqual(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end
XUI.DeepEqual = DeepEqual

-- Value at a dotted path ("text.font.size") inside `root`.
function XUI.GetPath(root, path)
	local node = root
	for key in path:gmatch("[^%.]+") do
		if type(node) ~= "table" then return nil end
		local n = tonumber(key)
		node = node[n or key]
	end
	return node
end

-- Sets the value at a dotted path, creating intermediate tables.
function XUI.SetPath(root, path, value)
	local node, last = root, nil
	for key in path:gmatch("[^%.]+") do
		if last ~= nil then
			local n = tonumber(last)
			local k = n or last
			if type(node[k]) ~= "table" then node[k] = {} end
			node = node[k]
		end
		last = key
	end
	if last ~= nil then
		local n = tonumber(last)
		node[n or last] = value
	end
end

--------------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------------
function XUI.Round(v, step)
	step = step or 1
	return floor(v / step + 0.5) * step
end

function XUI.Clamp(v, lo, hi)
	if v < lo then return lo elseif v > hi then return hi end
	return v
end

--------------------------------------------------------------------------------
-- Colours are stored as { r, g, b, a } arrays everywhere in the addon.
--------------------------------------------------------------------------------
function XUI.UnpackColor(c, fr, fg, fb, fa)
	if type(c) ~= "table" then return fr or 1, fg or 1, fb or 1, fa or 1 end
	return c[1] or fr or 1, c[2] or fg or 1, c[3] or fb or 1, c[4] or fa or 1
end

function XUI.ColorHex(c)
	local r, g, b = XUI.UnpackColor(c)
	return ("%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

--------------------------------------------------------------------------------
-- Coalesce: runs fn once on the next frame however many times it is requested
-- this frame. Options sliders fire on every step and a pull is a burst of
-- events; one pass on the next frame answers all of them.
--------------------------------------------------------------------------------
function XUI.Coalesce(fn)
	local queued = false
	local function run()
		queued = false
		XUI.SafeCall(fn)
	end
	return function()
		if queued then return end
		queued = true
		C_Timer.After(0, run)
	end
end

--------------------------------------------------------------------------------
-- Internal message bus
-- Core systems announce changes here; modules and the options panel listen.
--   ProfileChanged      the active profile was switched, copied, reset or imported
--   StyleChanged        a global style value changed (fonts, borders, glows ...)
--   MediaChanged        LibSharedMedia registered new media
--   UnlockModeChanged   (active) the mover overlay was toggled
--   ModuleStateChanged  (module) a module was enabled or disabled
--------------------------------------------------------------------------------
local listeners = {}

function XUI:On(message, owner, fn)
	local list = listeners[message]
	if not list then
		list = {}
		listeners[message] = list
	end
	list[owner] = fn
end

function XUI:Off(message, owner)
	local list = listeners[message]
	if list then list[owner] = nil end
end

function XUI:Fire(message, ...)
	local list = listeners[message]
	if not list then return end
	for owner, fn in pairs(list) do
		XUI.SafeCall(fn, owner, ...)
	end
end

--------------------------------------------------------------------------------
-- Addon load helpers
--------------------------------------------------------------------------------
function XUI.IsAddOnLoaded(name)
	local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
	return ok and loaded and true or false
end

-- Runs fn once the named addon has loaded (immediately when it already has).
local loadWaiters = {}
local loadFrame = CreateFrame("Frame")
loadFrame:SetScript("OnEvent", function(_, _, name)
	local waiting = loadWaiters[name]
	if not waiting then return end
	loadWaiters[name] = nil
	for i = 1, #waiting do XUI.SafeCall(waiting[i]) end
	if not next(loadWaiters) then loadFrame:UnregisterEvent("ADDON_LOADED") end
end)

function XUI.OnAddOnLoaded(name, fn)
	if XUI.IsAddOnLoaded(name) then
		XUI.SafeCall(fn)
		return
	end
	local waiting = loadWaiters[name]
	if not waiting then
		waiting = {}
		loadWaiters[name] = waiting
	end
	waiting[#waiting + 1] = fn
	loadFrame:RegisterEvent("ADDON_LOADED")
end

--------------------------------------------------------------------------------
-- Player info
--------------------------------------------------------------------------------
-- Specialization ID (e.g. 250 for Blood) or nil when unknown.
function XUI.GetSpecID()
	local CSI = C_SpecializationInfo
	local getIndex = (CSI and CSI.GetSpecialization) or _G.GetSpecialization
	local getInfo = (CSI and CSI.GetSpecializationInfo) or _G.GetSpecializationInfo
	local index = XUI.Probe(getIndex)
	if not index then return nil end
	return XUI.Probe(getInfo, index)
end

function XUI.IsSpellKnown(spellID)
	if not spellID then return false end
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local known = XUI.Probe(C_SpellBook.IsSpellKnown, spellID)
		if known then return true end
	end
	if _G.IsPlayerSpell then
		return XUI.Probe(_G.IsPlayerSpell, spellID) and true or false
	end
	return false
end

function XUI.GetSpellIcon(spellID, fallback)
	local tex = C_Spell and C_Spell.GetSpellTexture and XUI.Probe(C_Spell.GetSpellTexture, spellID)
	return tex or fallback or 134400 -- question mark
end

function XUI.GetSpellName(spellID)
	return C_Spell and C_Spell.GetSpellName and XUI.Probe(C_Spell.GetSpellName, spellID) or ("Spell " .. tostring(spellID))
end
