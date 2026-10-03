-- The scenario: log in, open the options, visit every page, touch every
-- control, run each module through combat, previews, profiles and unlock
-- mode, then log out. Any Lua error fails the run.

local function Step(name, fn)
	local before = #MOCK.errors
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then MOCK.errors[#MOCK.errors + 1] = name .. ": " .. tostring(err) end
	MOCK.Advance(0.5)
	local n = #MOCK.errors - before
	print(("%-44s %s"):format(name, n == 0 and "ok" or ("FAILED (" .. n .. ")")))
end

local XUI

Step("load XerionUI", function()
	MOCK.LoadTOC("XerionUI")
	XUI = _G.XerionUI
	assert(XUI and XUI.DB.profile, "database not initialised")
end)

Step("login", function()
	MOCK.Fire("PLAYER_LOGIN")
	MOCK.Fire("PLAYER_ENTERING_WORLD", true, false)
	assert(XUI.loggedIn)
end)

Step("open options (/xui)", function()
	SlashCmdList.XERIONUI("")
	MOCK.Advance(0.1)
	assert(XUI.Options and XUI.Options:IsShown(), "options did not open")
end)

local function Controls()
	local out = {}
	for _, f in ipairs(MOCK.frames) do
		if type(rawget(f, "desc")) == "table" and rawget(f, "ctx") and rawget(f, "Refresh") then out[#out + 1] = f end
	end
	return out
end

local exercised = {}
local function Exercise(control)
	local O, desc, ctx = XUI.Options, control.desc, control.ctx
	if exercised[control] then return end
	exercised[control] = true
	local t = desc.type
	if t == "toggle" then
		local v = O:GetValue(desc, ctx)
		O:SetValue(desc, ctx, not v)
		MOCK.Advance(0.05)
		O:SetValue(desc, ctx, v and true or false)
	elseif t == "slider" then
		local step = desc.step or 1
		local mid = desc.min + math.floor((desc.max - desc.min) / 2 / step) * step
		O:SetValue(desc, ctx, mid)
		MOCK.Advance(0.05)
		O:SetValue(desc, ctx, desc.min)
	elseif t == "dropdown" then
		local values = O:DropdownValues(desc, ctx)
		O:OpenDropdown(control.field, desc, ctx, O:GetValue(desc, ctx), function() end)
		MOCK.Advance(0.05)
		O.CloseDropdown()
		local pick = values[2] or values[1]
		if pick then O:SetValue(desc, ctx, pick.value) end
	elseif t == "color" then
		O:SetValue(desc, ctx, { 0.2, 0.4, 0.6, 1 })
	elseif t == "input" and not desc.readOnly then
		O:SetValue(desc, ctx, "test")
	elseif t == "button" and desc.onClick then
		desc.onClick(ctx, control)
	end
	MOCK.Advance(0.05)
	control:Refresh()
end

local pageKeys = { "style", "general", "profiles" }
for _, m in ipairs(XUI.modules) do pageKeys[#pageKeys + 1] = m.key end
for _, c in ipairs(XUI.Options.CLASSES) do pageKeys[#pageKeys + 1] = "class:" .. c.token end
pageKeys[#pageKeys + 1] = "class:ANY"

for _, key in ipairs(pageKeys) do
	Step("page " .. key, function()
		XUI.Options:Open(key)
		MOCK.Advance(0.1)
	end)
end

MOCK.autoAccept = true
Step("touch every control", function()
	for _, key in ipairs(pageKeys) do
		XUI.Options:Open(key)
		MOCK.Advance(0.05)
		for _, c in ipairs(Controls()) do
			local ok, err = xpcall(Exercise, debug.traceback, c)
			if not ok then
				MOCK.errors[#MOCK.errors + 1] = ("control '%s' (%s) on %s: %s"):format(
					tostring(c.desc.label or c.desc.text or c.desc.path), c.desc.type, key, err)
			end
		end
	end
	MOCK.autoAccept = false
end)

Step("modules: enable all", function()
	XUI.Options:Open("style")
	for _, m in ipairs(XUI.modules) do m:SetEnabled(true) end
end)

Step("combat start / end", function()
	MOCK.inCombat = true
	MOCK.Fire("PLAYER_REGEN_DISABLED")
	MOCK.Advance(3)
	MOCK.inCombat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	MOCK.Advance(5)
end)

Step("stoneform bleed", function()
	MOCK.bleed = true
	MOCK.Fire("UNIT_AURA", "player")
	MOCK.Fire("SPELL_UPDATE_COOLDOWN")
	MOCK.bleed = false
	MOCK.Fire("UNIT_AURA", "player")
end)

Step("previews on / off", function()
	for _, m in ipairs(XUI.modules) do m:SetPreview(true) end
	MOCK.Advance(0.1)
	for _, m in ipairs(XUI.modules) do m:SetPreview(false) end
end)

Step("module reset", function()
	for _, m in ipairs(XUI.modules) do m:Reset() end
end)

-- LibDeflate's inflate does not survive fengari's Lua 5.3 number semantics
-- (it is fine in the 5.1 client); compression is stubbed so the profile
-- logic around it can still be tested.
do
	local LD = LibStub("LibDeflate")
	local probe = LD:CompressDeflate("probe probe probe")
	if LD:DecompressDeflate(probe) ~= "probe probe probe" then
		LD.CompressDeflate = function(_, s) return s end
		LD.DecompressDeflate = function(_, s) return s end
		print("(LibDeflate stubbed for the 5.3 VM)")
	end
end

Step("profiles: new / switch / copy / export / import", function()
	local DB = XUI.DB
	assert(DB:NewProfile("Second", true))
	assert(DB:GetProfileName() == "Second")
	DB:SetProfile("Default")
	DB:CopyProfile("Second")
	local s = DB:ExportProfile()
	assert(type(s) == "string" and s:find("^!XUI1!"), "export failed")
	local ok, name = DB:ImportProfile(s, "Imported")
	assert(ok, name)
	assert(DB:GetProfileName() == name)
	DB:SetProfile("Default")
	assert(DB:DeleteProfile("Imported"))
	local bad = DB:ImportProfile("garbage")
	assert(bad == false)
end)

Step("unlock mode", function()
	XUI:SetUnlocked(true)
	MOCK.Advance(0.1)
	assert(XUI.unlockActive, "unlock did not activate")
	XUI:SetUnlocked(false)
	assert(not XUI.unlockActive)
end)

Step("global style change reaches modules", function()
	XUI.DB.style.font.outline = "THICKOUTLINE"
	XUI:Fire("StyleChanged")
	MOCK.Advance(0.1)
end)

Step("close options + slash commands", function()
	XUI.Options:Close()
	SlashCmdList.XERIONUI("help")
	SlashCmdList.XERIONUI("profile")
	SlashCmdList.XERIONUI("version")
end)

Step("logout strips defaults", function()
	MOCK.Fire("PLAYER_LOGOUT")
	local sv = _G.XerionUIDB
	assert(sv and sv.profiles and sv.profiles.Default)
end)

print("")
print(("build %d: aura containers made %d, engine sound registrations %d"):format(XUI.BUILD, MOCK.containers or 0, MOCK.auraSounds or 0))
local running = {}
for _, m in ipairs(XUI.modules) do if m.running then running[#running + 1] = m.key end end
print("running at the end: " .. table.concat(running, ", "))
local unknown = {}
for k in pairs(MOCK.unknown) do unknown[#unknown + 1] = k end
table.sort(unknown)
print("mocked no-op methods used: " .. table.concat(unknown, ", "))
print("")
if #MOCK.errors > 0 then
	for i, e in ipairs(MOCK.errors) do print(("ERROR %d: %s"):format(i, e)) end
	error(#MOCK.errors .. " error(s)")
else
	print("ALL OK")
end
