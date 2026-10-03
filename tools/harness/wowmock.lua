-- A small mock of the WoW client API, enough to load XerionUI, open its
-- options window and drive every control. Runs under fengari (Lua 5.3).
-- Unknown widget methods are no-ops that return nil; they are recorded in
-- MOCK.unknown so missing return values can be spotted.

MOCK = { errors = {}, unknown = {}, timers = {}, now = 1000, events = {}, frames = {} }

-- Lua 5.1 compatibility
unpack = table.unpack
loadstring = load
function table.getn(t) return #t end
math.mod = math.fmod
string.gfind = string.gmatch
local real_format = string.format
string.format = function(fmt, ...)
	local args = table.pack(...)
	for i = 1, args.n do
		if math.type(args[i]) == "float" and args[i] == math.floor(args[i]) and args[i] > -2^53 and args[i] < 2^53 then
			args[i] = math.tointeger(args[i]) or args[i]
		end
	end
	local ok, res = pcall(real_format, fmt, table.unpack(args, 1, args.n))
	if ok then return res end
	-- WoW (5.1) truncates floats for %d; mimic it
	for i = 1, args.n do
		if math.type(args[i]) == "float" then args[i] = math.floor(args[i]) end
	end
	return real_format(fmt, table.unpack(args, 1, args.n))
end
format = string.format
strfind, strsub, strlower, strupper, strlen, strrep = string.find, string.sub, string.lower, string.upper, string.len, string.rep
gsub, strmatch, strbyte, strchar = string.gsub, string.match, string.byte, string.char
tinsert, tremove, tsort = table.insert, table.remove, table.sort
floor, ceil, abs, min, max = math.floor, math.ceil, math.abs, math.min, math.max
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s, n)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
	return table.unpack(out)
end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function CopyTable(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and CopyTable(v) or v end return o end

bit = {
	band = function(a, b) return math.tointeger(a) & math.tointeger(b) end,
	bor = function(a, b) return math.tointeger(a) | math.tointeger(b) end,
	bxor = function(a, b) return math.tointeger(a) ~ math.tointeger(b) end,
	lshift = function(a, n) return (math.tointeger(a) << n) & 0xFFFFFFFF end,
	rshift = function(a, n) return (math.tointeger(a) & 0xFFFFFFFF) >> n end,
	bnot = function(a) return (~math.tointeger(a)) & 0xFFFFFFFF end,
}

function debugstack() return "" end
function getfenv() return _G end
function setfenv() end

local function Pool(create, reset)
	local pool = { active = {}, inactive = {} }
	function pool:Acquire()
		local o = table.remove(self.inactive)
		local new = o == nil
		if new then o = create() end
		self.active[o] = true
		return o, new
	end
	function pool:Release(o)
		if not self.active[o] then return false end
		self.active[o] = nil
		if reset then reset(self, o) end
		table.insert(self.inactive, o)
		return true
	end
	function pool:ReleaseAll() for o in pairs(self.active) do self:Release(o) end end
	function pool:EnumerateActive() return pairs(self.active) end
	return pool
end
function CreateTexturePool(parent, layer, sub, template, reset)
	return Pool(function() return parent:CreateTexture(nil, layer, template, sub) end, reset)
end
function CreateFramePool(kind, parent, template, reset)
	return Pool(function() return CreateFrame(kind, nil, parent, template) end, reset)
end
function debugprofilestop() return MOCK.now * 1000 end
function geterrorhandler()
	return function(err)
		MOCK.errors[#MOCK.errors + 1] = tostring(err) .. "\n" .. (debug.traceback("", 2) or "")
		return err
	end
end
function seterrorhandler() end
function securecall(fn, ...) return fn(...) end
function issecure() return false end
function InCombatLockdown() return MOCK.inCombat or false end
function GetTime() return MOCK.now end
function time() return 1700000000 end
function date(fmt) return os.date(fmt, 0) end
function GetLocale() return "enUS" end
function GetBuildInfo() return "12.0.5", "60000", "Oct 1 2026", 120005 end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitName() return "Xerion" end
function UnitRace() return "Dwarf", "Dwarf" end
function GetRealmName() return "Ravencrest" end
function UnitGUID() return "Player-1-0001" end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function GetCursorPosition() return 500, 400 end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function PlaySoundFile() return true end
function PlaySound() return true end
function IsPlayerSpell(id) return id == 20594 end
function hooksecurefunc(a, b, c)
	if type(a) == "table" then
		local orig = a[b]
		a[b] = function(...) local r = { orig(...) } c(...) return table.unpack(r) end
	else
		local orig = _G[a]
		_G[a] = function(...) local r = { orig(...) } b(...) return table.unpack(r) end
	end
end
function Mixin(o, ...)
	for i = 1, select("#", ...) do
		for k, v in pairs((select(i, ...))) do o[k] = v end
	end
	return o
end
function CreateFromMixins(...) return Mixin({}, ...) end
YES, NO, ACCEPT, CANCEL, OKAY = "Yes", "No", "Accept", "Cancel", "Okay"
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UISpecialFrames = {}
StaticPopupDialogs = {}
function StaticPopup_Show(which, a1, a2, data)
	MOCK.lastPopup = { which = which, data = data }
	local d = StaticPopupDialogs[which]
	if d and d.OnAccept and MOCK.autoAccept then d.OnAccept({}, data) end
end
function HideUIPanel(f) if f then f:Hide() end end
SlashCmdList = {}
Enum = { SpellBookSpellBank = { Player = 0 } }

PixelUtil = {
	GetPixelToUIUnitFactor = function() return 768 / 1080 end,
	GetNearestPixelSize = function(v) return v end,
	SetPoint = function(r, ...) r:SetPoint(...) end,
	SetSize = function(r, w, h) r:SetSize(w, h) end,
	SetWidth = function(r, w) r:SetWidth(w) end,
	SetHeight = function(r, h) r:SetHeight(h) end,
}

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------
local Object = {}
local ObjectMeta = {
	__index = function(self, k)
		local v = Object[k]
		if v ~= nil then return v end
		-- only CamelCase keys are widget methods; anything else is a field
		if type(k) ~= 'string' or not k:match('^[A-Z]') then return nil end
		MOCK.unknown[k] = true
		return function() return nil end
	end,
}

local nameCount = 0
local function New(kind, name, parent)
	local o = setmetatable({
		_kind = kind, _name = name, _parent = parent, _w = 0, _h = 0, _shown = true, _scripts = {},
		_points = {}, _level = parent and (parent._level or 0) + 1 or 0, _strata = "MEDIUM", _scale = 1,
		_alpha = 1, _text = nil, _children = {},
	}, ObjectMeta)
	if parent and parent._children then table.insert(parent._children, o) end
	if name then _G[name] = o end
	MOCK.frames[#MOCK.frames + 1] = o
	return o
end
MOCK.New = New

function Object:GetName() return self._name end
function Object:GetObjectType() return self._kind end
function Object:IsObjectType(t) return self._kind == t end
function Object:GetParent() return self._parent end
function Object:SetParent(p) self._parent = p end
function Object:SetSize(w, h) self._w, self._h = w or 0, h or 0 end
function Object:SetWidth(w) self._w = w or 0 end
function Object:SetHeight(h) self._h = h or 0 end
function Object:GetWidth() return self._w end
function Object:GetHeight() return self._h end
function Object:GetSize() return self._w, self._h end
function Object:GetRect() return 0, 0, self._w, self._h end
function Object:GetScaledRect() return 0, 0, self._w, self._h end
function Object:SetPoint(...) table.insert(self._points, { ... }) end
function Object:ClearAllPoints() self._points = {} end
function Object:SetAllPoints() end
function Object:GetPoint(i) local p = self._points[i or 1] if p then return table.unpack(p) end end
function Object:GetNumPoints() return #self._points end
function Object:GetCenter() return 960, 540 end
function Object:GetLeft() return 0 end
function Object:GetRight() return self._w end
function Object:GetTop() return self._h end
function Object:GetBottom() return 0 end
function Object:Show() self._shown = true local s = self._scripts.OnShow if s then s(self) end end
function Object:Hide()
	local was = self._shown
	self._shown = false
	local s = self._scripts.OnHide
	if s and was then s(self) end
end
function Object:SetShown(v) if v then self:Show() else self:Hide() end end
function Object:IsShown() return self._shown end
function Object:IsVisible() return self._shown end
function Object:SetAlpha(a) self._alpha = a end
function Object:GetAlpha() return self._alpha end
function Object:GetEffectiveAlpha() return self._alpha end
function Object:SetScale(s) self._scale = s end
function Object:GetScale() return self._scale end
function Object:GetEffectiveScale() return self._scale end
function Object:SetFrameLevel(l) self._level = l end
function Object:GetFrameLevel() return self._level end
function Object:SetFrameStrata(s) self._strata = s end
function Object:GetFrameStrata() return self._strata end
function Object:IsForbidden() return false end
function Object:IsProtected() return false end
function Object:IsMouseOver() return false end
function Object:IsMouseEnabled() return self._mouse or false end
function Object:EnableMouse(v) self._mouse = v end
function Object:SetScript(name, fn) self._scripts[name] = fn end
function Object:GetScript(name) return self._scripts[name] end
function Object:HookScript(name, fn)
	local old = self._scripts[name]
	self._scripts[name] = function(...) if old then old(...) end fn(...) end
end
function Object:RegisterEvent(e) MOCK.events[e] = MOCK.events[e] or {} MOCK.events[e][self] = true end
function Object:RegisterUnitEvent(e) self:RegisterEvent(e) end
function Object:UnregisterEvent(e) if MOCK.events[e] then MOCK.events[e][self] = nil end end
function Object:UnregisterAllEvents() for _, set in pairs(MOCK.events) do set[self] = nil end end
function Object:IsEventRegistered(e) return MOCK.events[e] and MOCK.events[e][self] or false end
function Object:GetChildren() return table.unpack(self._children) end
function Object:GetRegions() return end
-- textures / font strings
local function Region(self, kind, layer)
	local r = New(kind, nil, self)
	r._layer = layer
	return r
end
function Object:CreateTexture(name, layer) return Region(self, "Texture", layer) end
function Object:CreateMaskTexture() return Region(self, "MaskTexture") end
function Object:CreateLine() return Region(self, "Line") end
function Object:CreateFontString(name, layer, template)
	local r = Region(self, "FontString", layer)
	if template then r._font = { [[FontsFRIZQT__.TTF]], 12, "" } end
	return r
end
function Object:CreateAnimationGroup()
	local g = Region(self, "AnimationGroup")
	g._playing = false
	return g
end
function Object:CreateAnimation(kind) return Region(self, kind or "Animation") end
function Object:Play() self._playing = true end
function Object:Stop() self._playing = false end
function Object:IsPlaying() return self._playing or false end
function Object:SetTexture(t) self._texture = t return true end
function Object:GetTexture() return self._texture end
function Object:SetFont(path, size, flags)
	if type(path) ~= "string" or path == "" then error("SetFont: bad path " .. tostring(path), 2) end
	if type(size) ~= "number" or size <= 0 then error("SetFont: bad size " .. tostring(size), 2) end
	self._font = { path, size, flags }
	return true
end
function Object:GetFont() if self._font then return table.unpack(self._font) end end
function Object:SetText(t)
	if self._kind == "FontString" and not self._font and not self._fontObject then
		error("FontString:SetText(): Font not set", 2)
	end
	self._text = t
end
function Object:SetFormattedText(fmt, ...) self:SetText(string.format(fmt, ...)) end
function Object:GetText() return self._text end
function Object:SetFontObject(o) self._fontObject = o if o and o._font then self._font = o._font end end
function Object:GetStringWidth() return #(tostring(self._text or "")) * 6 end
function Object:GetUnboundedStringWidth() return #(tostring(self._text or "")) * 6 end
function Object:GetStringHeight() return self._font and self._font[2] or 12 end
-- status bars / sliders
function Object:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Object:GetMinMaxValues() return self._min or 0, self._max or 1 end
function Object:SetValue(v)
	self._value = v
	local s = self._scripts.OnValueChanged
	if s and self._kind == "Slider" then s(self, v, false) end
end
function Object:GetValue() return self._value or 0 end
function Object:SetStatusBarTexture(t) self._sbt = t end
function Object:GetStatusBarTexture() return self._sbtObj or New("Texture", nil, self) end
-- scroll
function Object:GetVerticalScrollRange() return 0 end
function Object:GetVerticalScroll() return 0 end
function Object:SetScrollChild(c) self._scrollChild = c end
-- edit boxes
function Object:HasFocus() return false end
function Object:GetNumber() return tonumber(self._text) or 0 end
function Object:GetNumMaskTextures() return 0 end
function Object:GetTextColor() return 1, 1, 1, 1 end
function Object:GetVertexColor() return 1, 1, 1, 1 end
function Object:IsDesaturated() return false end
function Object:GetDrawLayer() return self._layer or "ARTWORK", 0 end
-- cooldowns
function Object:SetCooldown() end
-- backdrop
function Object:SetBackdrop(b) self._backdrop = b end

function CreateFrame(kind, name, parent, template)
	local f = New(kind, name, parent)
	f._template = template
	if template and template:find("BackdropTemplate") then
		f.SetBackdropColor = function() end
		f.SetBackdropBorderColor = function() end
	end
	if template == "ScrollFrameTemplate" then
		f.ScrollBar = New("Frame", nil, f)
	end
	return f
end

function CreateFont(name)
	local f = New("Font", name)
	return f
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920 * 768 / 1080, 768)
WorldFrame = CreateFrame("Frame", "WorldFrame")
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
SettingsPanel = CreateFrame("Frame", "SettingsPanel", UIParent)
ColorPickerFrame = CreateFrame("Frame", "ColorPickerFrame", UIParent)
function ColorPickerFrame:SetupColorPickerAndShow(info)
	MOCK.colorInfo = info
end
function ColorPickerFrame:GetColorRGB() return 0.25, 0.5, 0.75 end
function ColorPickerFrame:GetColorAlpha() return 0.8 end

Settings = {
	RegisterCanvasLayoutCategory = function(frame, name) return { name = name } end,
	RegisterAddOnCategory = function() end,
}

--------------------------------------------------------------------------------
-- Timers
--------------------------------------------------------------------------------
C_Timer = {}
function C_Timer.After(d, fn)
	table.insert(MOCK.timers, { at = MOCK.now + (d or 0), fn = fn })
end
function C_Timer.NewTicker(d, fn, n)
	local t = { cancelled = false }
	function t:Cancel() self.cancelled = true end
	function t:IsCancelled() return self.cancelled end
	local count = 0
	local function step()
		if t.cancelled then return end
		count = count + 1
		fn(t)
		if not n or count < n then C_Timer.After(d, step) end
	end
	C_Timer.After(d, step)
	return t
end
function C_Timer.NewTimer(d, fn)
	local t = { cancelled = false }
	function t:Cancel() self.cancelled = true end
	C_Timer.After(d, function() if not t.cancelled then fn(t) end end)
	return t
end

-- Advances time and runs due timers (bounded, since tickers re-arm).
function MOCK.Advance(seconds)
	local target = MOCK.now + (seconds or 0)
	for _ = 1, 10000 do
		table.sort(MOCK.timers, function(a, b) return a.at < b.at end)
		local t = MOCK.timers[1]
		if not t or t.at > target then break end
		table.remove(MOCK.timers, 1)
		MOCK.now = math.max(MOCK.now, t.at)
		local ok, err = xpcall(t.fn, debug.traceback)
		if not ok then MOCK.errors[#MOCK.errors + 1] = "timer: " .. tostring(err) end
	end
	MOCK.now = target
end

function MOCK.Fire(event, ...)
	local set = MOCK.events[event]
	if not set then return end
	local list = {}
	for f in pairs(set) do list[#list + 1] = f end
	for _, f in ipairs(list) do
		local s = f._scripts.OnEvent
		if s then
			local ok, err = xpcall(s, debug.traceback, f, event, ...)
			if not ok then MOCK.errors[#MOCK.errors + 1] = event .. ": " .. tostring(err) end
		end
	end
end

--------------------------------------------------------------------------------
-- Game APIs used by the addon
--------------------------------------------------------------------------------
MOCK.loaded = {}
C_AddOns = {
	GetAddOnMetadata = function(name, key) if key == "Version" then return "2.0.0-test" end end,
	IsAddOnLoaded = function(name) return MOCK.loaded[name] or false end,
	LoadAddOn = function(name)
		if MOCK.loaded[name] then return true end
		if MOCK.LoadAddOn then return MOCK.LoadAddOn(name) end
		return false, "MISSING"
	end,
	EnableAddOn = function() end,
}
C_Spell = {
	GetSpellTexture = function(id) return 100000 + (id or 0) end,
	GetSpellName = function(id) return "Spell" .. tostring(id) end,
	GetSpellCooldown = function() return { isActive = false, isOnGCD = false, startTime = 0, duration = 0 } end,
}
C_SpellBook = { IsSpellKnown = function(id) return id == 20594 end }
C_UnitAuras = {
	GetAuraDataByIndex = function(unit, i, filter)
		if MOCK.bleed and i == 1 and filter == "HARMFUL" then return { dispelName = "Bleed", spellId = 1 } end
		return nil
	end,
}
C_SpecializationInfo = {
	GetSpecialization = function() return 1 end,
	GetSpecializationInfo = function() return 71 end,
}
C_VoiceChat = {
	GetTtsVoices = function() return { { voiceID = 0, name = "Microsoft Zira" }, { voiceID = 1, name = "Microsoft David" } } end,
	SpeakText = function(...) MOCK.spoke = { ... } end,
	StopSpeakingText = function() end,
}
C_TTSSettings = { GetVoiceOptionID = function() return 0 end, GetSpeechRate = function() return 0 end }
C_UIFileAsset = { IsKnownFile = function() return true end }
C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function() end }
