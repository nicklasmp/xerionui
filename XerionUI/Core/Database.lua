--------------------------------------------------------------------------------
-- XerionUI - Core/Database.lua
-- Saved variables, profiles, defaults and profile import/export.
--
-- Layout of XerionUIDB:
--   version      schema version (for future migrations)
--   global       account-wide settings (options panel, accent, unlock mode)
--   profileKeys  ["Name - Realm"] = profile name
--   profiles     [name] = { general = {}, style = {}, modules = { [key] = {} } }
--
-- Defaults are filled into the ACTIVE profile when it is activated and stripped
-- again on logout or when switching away, so the saved file only holds what
-- the user changed and a changed default reaches everyone who never touched it.
-- Tables with a [1] entry are lists and are treated as one value: a default
-- list is never merged into a user's list index by index.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local type, pairs, next, wipe = type, pairs, next, wipe
local CopyTable, IsList, DeepEqual = XUI.CopyTable, XUI.IsList, XUI.DeepEqual

local DB = {}
XUI.DB = DB

local SCHEMA_VERSION = 1
local DEFAULT_PROFILE = "Default"
local EXPORT_PREFIX = "!XUI1!"

--------------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------------

-- Account-wide.
DB.GLOBAL_DEFAULTS = {
	accent = { 1, 0.49, 0.04, 1 },
	loginMessage = false,
	panel = {
		scale = 1,
		font = "Arial Narrow",
		autoPreview = true,
		dock = true,
		density = "normal",
		classFolded = false,
	},
	-- named looks of the global style, shared by every profile
	themes = {},
	-- switch profile by instance type or specialization (Core/AutoProfile.lua)
	autoProfiles = { enabled = false, spec = {}, instance = {} },
	unlock = {
		gridSize = 32,
		snap = true,
		showGrid = true,
	},
}

-- The global look. Every module element that shows text, a border, a glow, a
-- bar or an icon resolves its style against these (see Core/Style.lua).
DB.STYLE_DEFAULTS = {
	font = {
		face = "GothamNarrowBlack",
		outline = "SLUGOUTLINE",
		shadow = false,
		shadowColor = { 0, 0, 0, 1 },
		shadowX = 1,
		shadowY = -1,
	},
	border = {
		style = "SOLID",
		size = 1,
		color = { 0, 0, 0, 1 },
	},
	background = {
		texture = "Xerion Solid",
		color = { 0.05, 0.05, 0.05, 0.6 },
	},
	bar = {
		texture = "Xerion Flat",
		bgColor = { 0, 0, 0, 0.5 },
	},
	glow = {
		type = "PIXEL",
		color = { 1, 0.49, 0.04, 1 },
		lines = 8,
		frequency = 0.25,
		length = 0,
		thickness = 2,
		particles = 4,
		scale = 1,
		offset = 0,
	},
	icon = {
		zoom = 8,
	},
}

DB.GENERAL_DEFAULTS = {}

-- [key] = defaults, filled by XUI:NewModule before the database initialises.
DB.moduleDefaults = {}

local profileDefaults = {
	general = DB.GENERAL_DEFAULTS,
	style = DB.STYLE_DEFAULTS,
	modules = DB.moduleDefaults,
}

--------------------------------------------------------------------------------
-- Inflate / strip
--------------------------------------------------------------------------------
local function IsAtomic(t)
	return IsList(t) or next(t) == nil
end

-- Fills every missing key of `dst` from `defaults`. A value whose type does
-- not match its default (a damaged or hand-edited import) is replaced too, so
-- module code can trust the types it reads.
local function Inflate(dst, defaults)
	for k, v in pairs(defaults) do
		local cur = dst[k]
		if type(v) == "table" then
			if IsAtomic(v) then
				if type(cur) ~= "table" then dst[k] = CopyTable(v) end
			else
				if type(cur) ~= "table" then
					cur = {}
					dst[k] = cur
				end
				Inflate(cur, v)
			end
		elseif cur == nil or type(cur) ~= type(v) then
			dst[k] = v
		end
	end
end
DB.Inflate = Inflate

local function Strip(dst, defaults)
	for k, v in pairs(defaults) do
		local cur = dst[k]
		if cur ~= nil then
			if type(v) == "table" then
				if type(cur) == "table" then
					if IsAtomic(v) then
						if DeepEqual(cur, v) then dst[k] = nil end
					else
						Strip(cur, v)
						if next(cur) == nil then dst[k] = nil end
					end
				end
			elseif cur == v then
				dst[k] = nil
			end
		end
	end
end
DB.Strip = Strip

-- A copy of the style with every default value removed.
local function StrippedStyle(style)
	local copy = CopyTable(style)
	Strip(copy, DB.STYLE_DEFAULTS)
	return copy
end

-- A copy of `profile` with every default value removed.
local function StrippedCopy(profile)
	local copy = CopyTable(profile)
	Strip(copy, profileDefaults)
	return copy
end

--------------------------------------------------------------------------------
-- Font migration: "outline" and a separate "slug" switch became one outline
-- choice with slug variants (SLUGOUTLINE is the default, like EllesmereUI).
--------------------------------------------------------------------------------
local function MigrateFontBlock(t, isGlobal)
	if t.slug == nil and t.outline == nil then return end
	if t.slug == true then
		if t.outline == nil or t.outline == "OUTLINE" then t.outline = "SLUGOUTLINE"
		elseif t.outline == "THICKOUTLINE" then t.outline = "SLUGTHICKOUTLINE" end
	elseif t.slug == false and (t.outline == nil or t.outline == "OUTLINE") then
		t.outline = "OUTLINE"
	elseif t.slug == nil and isGlobal and t.outline == "THICKOUTLINE" then
		-- the old global default had slug on
		t.outline = "SLUGTHICKOUTLINE"
	end
	t.slug = nil
end

local function WalkFonts(t, depth)
	if depth > 4 then return end
	for _, v in pairs(t) do
		if type(v) == "table" then
			MigrateFontBlock(v, false)
			WalkFonts(v, depth + 1)
		end
	end
end

local function MigrateFonts(profile)
	if profile.fontsMigrated then return end
	if type(profile.style) == "table" and type(profile.style.font) == "table" then
		MigrateFontBlock(profile.style.font, true)
	end
	if type(profile.modules) == "table" then WalkFonts(profile.modules, 0) end
	profile.fontsMigrated = 1
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
function DB:RegisterModuleDefaults(key, defaults)
	self.moduleDefaults[key] = defaults
	-- A module registered after login (should not happen, but be safe).
	if self.profile then
		self.profile.modules[key] = self.profile.modules[key] or {}
		Inflate(self.profile.modules[key], defaults)
	end
end

function DB:Initialize()
	local sv = _G.XerionUIDB
	if type(sv) ~= "table" then
		sv = {}
		_G.XerionUIDB = sv
	end
	sv.version = sv.version or SCHEMA_VERSION
	sv.global = type(sv.global) == "table" and sv.global or {}
	sv.profiles = type(sv.profiles) == "table" and sv.profiles or {}
	sv.profileKeys = type(sv.profileKeys) == "table" and sv.profileKeys or {}
	self.sv = sv

	Inflate(sv.global, self.GLOBAL_DEFAULTS)
	self.global = sv.global

	local char = _G.XerionUICharDB
	if type(char) ~= "table" then
		char = {}
		_G.XerionUICharDB = char
	end
	self.char = char

	self.charKey = ("%s - %s"):format(UnitName("player") or "?", GetRealmName() or "?")
	self:Activate(sv.profileKeys[self.charKey] or DEFAULT_PROFILE)

	local logout = CreateFrame("Frame")
	logout:RegisterEvent("PLAYER_LOGOUT")
	logout:SetScript("OnEvent", function()
		if self.profile then Strip(self.profile, profileDefaults) end
		Strip(self.global, self.GLOBAL_DEFAULTS)
	end)
end

-- Makes `name` the active profile without notifying anyone.
function DB:Activate(name)
	local sv = self.sv
	if self.profile then Strip(self.profile, profileDefaults) end
	local profile = sv.profiles[name]
	if type(profile) ~= "table" then
		profile = {}
		sv.profiles[name] = profile
	end
	MigrateFonts(profile)
	Inflate(profile, profileDefaults)
	self.profile = profile
	self.profileName = name
	self.style = profile.style
	self.general = profile.general
	sv.profileKeys[self.charKey] = name
end

function DB:ModuleDB(key)
	return self.profile.modules[key]
end

-- Restores a module's settings to their defaults.
function DB:ResetModuleDB(key)
	local t = self.profile.modules[key]
	wipe(t)
	Inflate(t, self.moduleDefaults[key] or {})
	return t
end

function DB:ResetStyle()
	wipe(self.style)
	Inflate(self.style, self.STYLE_DEFAULTS)
end

--------------------------------------------------------------------------------
-- Profiles
--------------------------------------------------------------------------------
local function Changed()
	XUI:Fire("ProfileChanged")
end

function DB:GetProfileName()
	return self.profileName
end

function DB:ListProfiles()
	local out = {}
	for name in pairs(self.sv.profiles) do out[#out + 1] = name end
	table.sort(out, function(a, b) return a:lower() < b:lower() end)
	return out
end

function DB:ProfileExists(name)
	return type(self.sv.profiles[name]) == "table"
end

function DB:SetProfile(name)
	if not name or name == "" or name == self.profileName then return end
	self:Activate(name)
	Changed()
end

-- Creates `name` as a copy of the active profile (or empty) and switches to it.
function DB:NewProfile(name, copyActive)
	if not name or name == "" or self:ProfileExists(name) then return false end
	self.sv.profiles[name] = copyActive and StrippedCopy(self.profile) or {}
	self:SetProfile(name)
	return true
end

-- Overwrites the active profile with the contents of `source`.
function DB:CopyProfile(source)
	local src = self.sv.profiles[source]
	if type(src) ~= "table" or source == self.profileName then return false end
	local data = CopyTable(src)
	wipe(self.profile)
	for k, v in pairs(data) do self.profile[k] = v end
	MigrateFonts(self.profile)
	Inflate(self.profile, profileDefaults)
	self.style, self.general = self.profile.style, self.profile.general
	Changed()
	return true
end

function DB:DeleteProfile(name)
	if name == self.profileName or not self:ProfileExists(name) then return false end
	self.sv.profiles[name] = nil
	for char, profile in pairs(self.sv.profileKeys) do
		if profile == name then self.sv.profileKeys[char] = nil end
	end
	return true
end

function DB:ResetProfile()
	wipe(self.profile)
	Inflate(self.profile, profileDefaults)
	self.style, self.general = self.profile.style, self.profile.general
	Changed()
end

--------------------------------------------------------------------------------
-- Import / export
--------------------------------------------------------------------------------
local function Libs()
	local LS = LibStub("LibSerialize", true)
	local LD = LibStub("LibDeflate", true)
	return LS, LD
end

function DB:ExportProfile()
	local LS, LD = Libs()
	if not (LS and LD) then return nil, "serializer missing" end
	local payload = {
		addon = XUI.ADDON_NAME,
		schema = SCHEMA_VERSION,
		version = XUI.version,
		profile = StrippedCopy(self.profile),
	}
	local serialized = LS:Serialize(payload)
	local compressed = LD:CompressDeflate(serialized, { level = 9 })
	return EXPORT_PREFIX .. LD:EncodeForPrint(compressed)
end

function DB:DecodeProfile(str)
	local LS, LD = Libs()
	if not (LS and LD) then return nil, "serializer missing" end
	if type(str) ~= "string" then return nil, "nothing to import" end
	str = str:gsub("%s", "")
	if str:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
		return nil, "not a XerionUI profile string"
	end
	local decoded = LD:DecodeForPrint(str:sub(#EXPORT_PREFIX + 1))
	local inflated = decoded and LD:DecompressDeflate(decoded)
	if not inflated then return nil, "the string is damaged" end
	local ok, payload = LS:Deserialize(inflated)
	if not ok or type(payload) ~= "table" or type(payload.profile) ~= "table" then
		return nil, "the string is damaged"
	end
	return payload
end

-- Imports `str` as a new profile called `name` and switches to it.
function DB:ImportProfile(str, name)
	local payload, err = self:DecodeProfile(str)
	if not payload then return false, err end
	if not name or name == "" then name = "Imported" end
	local base, n = name, 1
	while self:ProfileExists(name) do
		n = n + 1
		name = ("%s (%d)"):format(base, n)
	end
	self.sv.profiles[name] = payload.profile
	self:SetProfile(name)
	return true, name
end

--------------------------------------------------------------------------------
-- Style themes: the global style saved under a name, usable from any profile
--------------------------------------------------------------------------------
function DB:ListThemes()
	local out = {}
	for name in pairs(self.global.themes) do out[#out + 1] = name end
	table.sort(out, function(a, b) return a:lower() < b:lower() end)
	return out
end

function DB:SaveTheme(name)
	if not name or name == "" then return false end
	self.global.themes[name] = StrippedStyle(self.style)
	return true
end

function DB:ApplyTheme(name)
	local theme = self.global.themes[name]
	if type(theme) ~= "table" then return false end
	wipe(self.style)
	for k, v in pairs(CopyTable(theme)) do self.style[k] = v end
	Inflate(self.style, self.STYLE_DEFAULTS)
	return true
end

function DB:DeleteTheme(name)
	self.global.themes[name] = nil
end

--------------------------------------------------------------------------------
-- One module's settings, as a string of its own
--------------------------------------------------------------------------------
local MODULE_PREFIX = "!XUIM1!"

function DB:ExportModule(key)
	local LS, LD = Libs()
	if not (LS and LD) then return nil, "serializer missing" end
	local t = self.profile.modules[key]
	if not t then return nil, "no such module" end
	local data = CopyTable(t)
	data.enabled = nil
	Strip(data, self.moduleDefaults[key] or {})
	local payload = { addon = XUI.ADDON_NAME, schema = SCHEMA_VERSION, kind = "module", key = key, data = data }
	local compressed = LD:CompressDeflate(LS:Serialize(payload), { level = 9 })
	return MODULE_PREFIX .. LD:EncodeForPrint(compressed)
end

-- Replaces the settings of module `key` (not whether it is enabled) with those
-- in `str`, which must have been exported from the same module.
function DB:ImportModule(str, key)
	local LS, LD = Libs()
	if not (LS and LD) then return false, "serializer missing" end
	if type(str) ~= "string" then return false, "nothing to import" end
	str = str:gsub("%s", "")
	if str:sub(1, #MODULE_PREFIX) ~= MODULE_PREFIX then return false, "not a XerionUI module string" end
	local decoded = LD:DecodeForPrint(str:sub(#MODULE_PREFIX + 1))
	local inflated = decoded and LD:DecompressDeflate(decoded)
	local ok, payload = false, nil
	if inflated then ok, payload = LS:Deserialize(inflated) end
	if not ok or type(payload) ~= "table" or type(payload.data) ~= "table" then return false, "the string is damaged" end
	if payload.key ~= key then return false, ("that string is for %s"):format(tostring(payload.key)) end
	local t = self.profile.modules[key]
	local enabled = t.enabled
	wipe(t)
	for k, v in pairs(payload.data) do t[k] = v end
	Inflate(t, self.moduleDefaults[key] or {})
	t.enabled = enabled
	return true
end
