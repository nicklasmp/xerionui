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

local pageKeys = { "overview", "style", "general", "profiles" }
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

Step("sidebar: search, class folding, dock", function()
	local O = XUI.Options
	O:Open("general")
	for _, text in ipairs({ "tank", "interrupt", "druid", "zzzz", "" }) do
		O.S.searchText = text
		O:RefreshSidebar()
	end
	XUI.DB.global.panel.classFolded = true
	O:RefreshSidebar()
	XUI.DB.global.panel.classFolded = false
	O:RefreshSidebar()
	O:Open("class:DRUID")
	O:UpdateDock()
	O:RebuildAll()
end)

Step("diagnostics, self-check and perf", function()
	XUI.perfOn = true
	local text = XUI.Health.Report()
	assert(#text > 100, "report is empty")
	for _, m in ipairs(XUI.modules) do
		XUI.Health.Report(m)
		XUI.Health.Issues(m, true)
	end
	XUI.Options:ShowText("test", text)
	SlashCmdList.XERIONUI("perf")
	SlashCmdList.XERIONUI("perf reset")
	XUI.perfOn = false
end)

Step("close options + slash commands", function()
	XUI.Options:Close()
	SlashCmdList.XERIONUI("help")
	SlashCmdList.XERIONUI("profile")
	SlashCmdList.XERIONUI("version")
end)

Step("message bus survives listeners that add listeners", function()
	local owner, late, hits = {}, {}, 0
	XUI:On("XUITestMessage", owner, function()
		hits = hits + 1
		XUI:On("XUITestMessage", late, function() hits = hits + 100 end)
	end)
	XUI:Fire("XUITestMessage")
	assert(hits == 1, "a listener added during Fire must wait for the next one, got " .. hits)
	XUI:Fire("XUITestMessage")
	assert(hits == 102, "the added listener runs on the next Fire, got " .. hits)
	XUI:Off("XUITestMessage", owner)
	XUI:Off("XUITestMessage", late)
end)

Step("media lists are sorted once and shared", function()
	local a = XUI.Media:List("font")
	assert(XUI.Media:List("font") == a, "the font list should be cached")
	for i = 2, #a do
		assert(a[i - 1]:lower() <= a[i]:lower(), "font list not sorted at " .. i)
	end
	local v = XUI.Media.version
	XUI.Media.LSM:Register("font", "ZZ Test Font", [[Fonts\ARIALN.TTF]])
	assert(XUI.Media.version == v + 1, "registering media should bump the list version")
	local b = XUI.Media:List("font")
	assert(b ~= a and b[#b] == "ZZ Test Font", "the new font should be listed last")
end)

Step("profile command ignores capitalisation", function()
	XUI.DB:NewProfile("CaseTest", false)
	XUI.DB:SetProfile("Default")
	SlashCmdList.XERIONUI("profile casetest")
	assert(XUI.DB:GetProfileName() == "CaseTest", "got " .. tostring(XUI.DB:GetProfileName()))
	XUI.DB:SetProfile("Default")
	XUI.DB:DeleteProfile("CaseTest")
end)

Step("who has the key: lists this dungeon's keys", function()
	local m = XUI:GetModule("InstanceKeys")
	assert(m and m.running, "the module should be running")
	local saved = {
		UnitFullName = _G.UnitFullName, Ambiguate = _G.Ambiguate, GetNormalizedRealmName = _G.GetNormalizedRealmName,
		GetInstanceInfo = _G.GetInstanceInfo, C_MythicPlus = _G.C_MythicPlus, C_ChallengeMode = _G.C_ChallengeMode,
		send = C_ChatInfo.SendAddonMessage,
	}
	local sent = {}
	MOCK.inGroup = true
	local names = { player = "Xerion", party1 = "Brew", party2 = "Cleric" }
	_G.UnitFullName = function(u) return names[u], nil end
	_G.Ambiguate = function(s) return s end
	_G.GetNormalizedRealmName = function() return "Realm" end
	_G.GetInstanceInfo = function() return "Ara-Kara", "party", 23, "", 5, 0, false, 2660 end
	_G.C_MythicPlus = {
		GetOwnedKeystoneLevel = function() return 10 end,
		GetOwnedKeystoneChallengeMapID = function() return 503 end,
		RequestMapInfo = function() end,
	}
	_G.C_ChallengeMode = {
		GetMapUIInfo = function(id) return id == 503 and "Ara-Kara" or "Dawnbreaker", id, 0, 0, 0, id == 503 and 2660 or 9999 end,
		IsChallengeModeActive = function() return false end,
	}
	C_ChatInfo.SendAddonMessage = function(prefix, text, channel) sent[#sent + 1] = prefix .. "|" .. text .. "|" .. channel end
	local function text()
		local d = _G.XUI_InstanceKeys
		return d and d:IsShown() and d.text:GetText() or nil
	end

	MOCK.Advance(4)
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	MOCK.Advance(0.5)
	assert(sent[1] == "LibKS|R|PARTY", "entering a Mythic dungeon should ask the group, sent " .. tostring(sent[1]))
	assert(text() and text():find("Xerion", 1, true) and text():find("+10", 1, true), "your own key should be listed: " .. tostring(text()))

	MOCK.Fire("CHAT_MSG_ADDON", "LibKS", "12,503,2500", "PARTY", "Brew")
	MOCK.Fire("CHAT_MSG_ADDON", "LibKS", "11,504,1000", "PARTY", "Cleric")
	MOCK.Fire("CHAT_MSG_ADDON", "LibKS", "garbage", "PARTY", "Brew")
	MOCK.Fire("CHAT_MSG_ADDON", "Other", "5,503,1", "PARTY", "Brew")
	MOCK.Advance(0.5)
	local shown = text()
	assert(shown:find("Brew", 1, true) and shown:find("+12", 1, true), "a member with this dungeon's key should be listed: " .. shown)
	assert(not shown:find("Cleric", 1, true), "a key for another dungeon must not be listed: " .. shown)
	assert(shown:find("Xerion", 1, true) < shown:find("Brew", 1, true), "lowest key first: " .. shown)
	assert(shown:find("Who has a key?", 1, true), "the title should show")

	m.db.showAll = true
	m:Refresh()
	shown = text()
	assert(shown:find("Cleric", 1, true) and shown:find("(Dawnbreaker)", 1, true), "showAll lists other dungeons' keys, named: " .. shown)
	m.db.showAll = false

	MOCK.Advance(4)
	MOCK.Fire("CHAT_MSG_ADDON", "LibKS", "R", "PARTY", "Brew")
	assert(sent[#sent] == "LibKS|10,503,0|PARTY", "a request should be answered with our key, sent " .. tostring(sent[#sent]))

	MOCK.Fire("PLAYER_REGEN_DISABLED")
	assert(text() == nil, "combat should hide it")
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	MOCK.Advance(10.5)
	assert(text() ~= nil, "it should return ten seconds after the fight")
	MOCK.Fire("ENCOUNTER_START")
	assert(text() == nil, "a boss fight should dismiss it")

	-- not a Mythic dungeon: nothing is asked, nothing shown
	_G.GetInstanceInfo = function() return "World", "none", 0, "", 0, 0, false, 1 end
	local before = #sent
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	MOCK.Advance(0.5)
	assert(text() == nil and #sent == before, "outside a Mythic dungeon nothing should happen")

	MOCK.inGroup = false
	_G.UnitFullName, _G.Ambiguate, _G.GetNormalizedRealmName = saved.UnitFullName, saved.Ambiguate, saved.GetNormalizedRealmName
	_G.GetInstanceInfo, _G.C_MythicPlus, _G.C_ChallengeMode = saved.GetInstanceInfo, saved.C_MythicPlus, saved.C_ChallengeMode
	C_ChatInfo.SendAddonMessage = saved.send
	m:Refresh()
end)

Step("nameplates: auto-cast shine overrides the dispel glow style", function()
	local m = XUI:GetModule("EUINameplates")
	local reloads, drawn = 0, {}
	_G.EllesmereNameplates_NS = {
		plates = {},
		NPC_ReloadAll = function() reloads = reloads + 1 end,
		GetDispelGlowSpec = function(_, out)
			out = out or {}
			out.style, out.r, out.g, out.b, out.speed = 2, 0.2, 0.6, 1, 4
			return out
		end,
	}
	_G.EllesmereUI = { Glows = {
		PrewarmEngineHost = function() end,
		StartSpecGlow = function(wrapper, spec) drawn[#drawn + 1] = "eui:" .. tostring(spec.style) return spec.style, false end,
		StopGlow = function(wrapper) wrapper._euiGlowActive = false end,
	} }
	local ns, Glows = _G.EllesmereNameplates_NS, _G.EllesmereUI.Glows
	-- the caller of the prewarm: EllesmereUI's nameplate aura code
	local savedStack = _G.debugstack
	_G.debugstack = function() return "[EllesmereUINameplates/EUI_Nameplates_AuraContainers.lua]:326: in function ApplyNPBuffExtra" end
	m.running = true
	m.db.enabled = true
	m.db.dispelShine = true
	m:OnEnable()

	local host = CreateFrame("Frame")
	-- the host is prepared in EllesmereUI's creation window, before anything is drawn
	Glows.PrewarmEngineHost(host, 24, 24, nil)
	assert(host.__xuiShine and host.__xuiShine.locked and #host.__xuiShine.sparks == 6, "the shine's regions should be made with the host")
	-- an engine button's host reads 1x1 until the engine lays it out: the size comes with the call
	host:SetSize(1, 1)
	host._euiGlowActive = true
	local spec = ns.GetDispelGlowSpec(nil, {})
	assert(spec.xuiShine and spec.style == 3, "the spec should be flagged and fingerprinted as Auto-Cast")
	Glows.StartSpecGlow(host, spec, 24, 24, "engine")
	assert(#drawn == 0, "EllesmereUI's own glow must not be drawn while the shine is on")
	assert(host.__xuiGlow ~= nil, "our shine should be on the host")
	assert(host.__xuiShine and host.__xuiShine.frame:IsShown(), "the shine should be drawn, though the host reads almost no size")
	assert(host.__xuiShine.frame:GetWidth() == 24 and host.__xuiShine.frame:GetHeight() == 24, "and at the size passed in, not the host's")
	assert(host._euiGlowActive == false, "EllesmereUI's glow should be taken off the host first")

	-- a prewarmed host cannot grow more sparks, however many are asked for
	m.db.dispelGlow.particles = 16
	XUI:NotifySettingChanged(m, "dispelGlow.particles")
	Glows.StartSpecGlow(host, ns.GetDispelGlowSpec(nil, {}), 24, 24, "engine")
	assert(#host.__xuiShine.sparks == 6, "no spark may be created after the host was made")
	m.db.dispelGlow.particles = nil

	-- a changed look reaches EllesmereUI's fingerprint
	local before = ns.GetDispelGlowSpec(nil, {}).speed
	m.db.dispelGlow.color = { 1, 0, 0, 1 }
	XUI:NotifySettingChanged(m, "dispelGlow.color")
	MOCK.Advance(0.5)
	local after = ns.GetDispelGlowSpec(nil, {})
	assert(reloads >= 1, "a setting change should reload the plates")
	assert(after.speed ~= before and after.r == 1 and after.g == 0, "the fingerprint should follow the shine's look")

	-- off again: EllesmereUI's glow is used and ours is gone
	m.db.dispelShine = false
	XUI:NotifySettingChanged(m, "dispelShine")
	local plain = ns.GetDispelGlowSpec(nil, {})
	assert(not plain.xuiShine and plain.style == 2, "the spec should be EllesmereUI's own again")
	Glows.StartSpecGlow(host, plain, 24, 24, "engine")
	assert(drawn[1] == "eui:2" and host.__xuiGlow == nil, "EllesmereUI draws again and our shine is removed")

	m.running = true
	m.db.dispelShine = false
	m.db.enabled = false
	XUI:UpdateModuleState(m)
	_G.EllesmereNameplates_NS, _G.EllesmereUI = nil, nil
	_G.debugstack = savedStack
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
