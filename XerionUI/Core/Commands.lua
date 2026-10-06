--------------------------------------------------------------------------------
-- XerionUI - Core/Commands.lua
-- Slash commands, the load-on-demand options addon, the Blizzard settings
-- entry and the addon compartment button.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

--------------------------------------------------------------------------------
-- Options addon
--------------------------------------------------------------------------------
local function LoadOptions()
	if XUI.IsAddOnLoaded(XUI.OPTIONS_ADDON) then return true end
	local loaded, reason = C_AddOns.LoadAddOn(XUI.OPTIONS_ADDON)
	if not loaded and reason == "DISABLED" then
		C_AddOns.EnableAddOn(XUI.OPTIONS_ADDON, UnitName("player"))
		loaded, reason = C_AddOns.LoadAddOn(XUI.OPTIONS_ADDON)
	end
	if loaded then return true end
	XUI.Printf("the options could not be loaded (%s). Make sure %s is installed and enabled.",
		_G["ADDON_" .. tostring(reason)] or tostring(reason), XUI.OPTIONS_ADDON)
	return false
end

-- Opens the options window, optionally on a page ("style", "profiles" or a
-- module key).
function XUI:OpenOptions(page)
	if not LoadOptions() then return end
	if self.Options and self.Options.Open then
		self.Options:Open(page)
	end
end

function XUI:ToggleOptions()
	if self.Options and self.Options.IsShown and self.Options:IsShown() then
		self.Options:Close()
	else
		self:OpenOptions()
	end
end

-- Minimap addon compartment (## AddonCompartmentFunc in the TOC).
function _G.XerionUI_OnAddonCompartmentClick()
	XUI:ToggleOptions()
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------
local HELP = {
	{ "/xui", "open the options" },
	{ "/xui unlock", "move frames (also: /xui move)" },
	{ "/xui profile <name>", "switch to a profile" },
	{ "/xui preview off", "end every module preview" },
	{ "/xui version", "show the installed version" },
	{ "/xui debug [module]", "why modules are or are not running, plus their live state" },
	{ "/xui perf [on|off|reset]", "time spent in each module's code (on, play, then /xui perf)" },
}

-- /xui debug: one line per module (enabled, running, why not), and with a
-- module key its own DebugInfo lines. Meant for in-game bug reports.
local function Debug(name)
	name = (name or ""):lower()
	for _, m in ipairs(XUI.modules) do
		if name == "" or m.key:lower() == name or m.name:lower() == name then
			local ok, why = m:CanRun()
			local state = m.running and "|cff55ff55running|r"
				or (not m.db.enabled and "|cffaaaaaaoff|r")
				or ("|cffff5555not running|r: " .. tostring(why))
			print(("  |cffffffff%s|r  %s"):format(m.key, state))
			if name ~= "" and m.DebugInfo then
				local good, lines = pcall(m.DebugInfo, m)
				if good and type(lines) == "table" then
					for _, line in ipairs(lines) do print("    " .. tostring(line)) end
				elseif not good then
					print("    DebugInfo failed: " .. tostring(lines))
				end
			end
		end
	end
	if XUI.errors and #XUI.errors > 0 then
		print(("  |cffff5555%d Lua error(s) caught so far, last:|r %s"):format(#XUI.errors, tostring(XUI.errors[#XUI.errors])))
	end
end

local function Handle(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "options" or cmd == "config" then
		XUI:ToggleOptions()
	elseif cmd == "unlock" or cmd == "move" or cmd == "lock" then
		XUI:ToggleUnlocked()
	elseif cmd == "profile" then
		if rest == "" then
			XUI.Printf("active profile: |cffffffff%s|r", XUI.DB:GetProfileName())
		else
			-- the exact name first, then any capitalisation of it
			local name = XUI.DB:ProfileExists(rest) and rest
			if not name then
				for _, existing in ipairs(XUI.DB:ListProfiles()) do
					if existing:lower() == rest:lower() then name = existing break end
				end
			end
			if name then
				XUI.DB:SetProfile(name)
				XUI.Printf("switched to profile |cffffffff%s|r", name)
			else
				XUI.Printf("no profile named |cffffffff%s|r", rest)
			end
		end
	elseif cmd == "preview" then
		for _, m in ipairs(XUI.modules) do m:SetPreview(false) end
	elseif cmd == "debug" then
		Debug(rest)
	elseif cmd == "perf" then
		rest = rest:lower()
		if rest == "on" then
			XUI.PerfReset()
			XUI.perfOn = true
			XUI.Print("timing every module's code. Play a while, then /xui perf for the result; /xui perf off stops.")
		elseif rest == "off" then
			XUI.perfOn = false
			XUI.Print("timing stopped.")
		elseif rest == "reset" then
			XUI.PerfReset()
			XUI.Print("timings cleared.")
		else
			local list = {}
			for _, m in ipairs(XUI.modules) do
				if m.perfCalls then list[#list + 1] = m end
			end
			table.sort(list, function(a, b) return a.perfMs > b.perfMs end)
			local secs = XUI.perfSince and (GetTime() - XUI.perfSince) or 0
			XUI.Print(("timing %s, %.0f s so far (inclusive per module, outermost call):"):format(XUI.perfOn and "ON" or "off", secs))
			if #list == 0 then print("  nothing measured - use /xui perf on first") end
			for _, m in ipairs(list) do
				print(("  |cffffffff%-22s|r %s"):format(m.key, XUI.PerfLine(m)))
			end
		end
	elseif cmd == "version" or cmd == "ver" then
		XUI.Printf("version |cffffffff%s|r", XUI.version)
	else
		XUI.Print("commands:")
		for _, line in ipairs(HELP) do
			print(("  |cffffffff%s|r  |cffaaaaaa%s|r"):format(line[1], line[2]))
		end
	end
end

_G.SLASH_XERIONUI1 = "/xui"
_G.SLASH_XERIONUI2 = "/xerionui"
SlashCmdList.XERIONUI = Handle

--------------------------------------------------------------------------------
-- Blizzard settings: a small page under AddOns that opens our window.
--------------------------------------------------------------------------------
local settingsOwner = {}
XUI:On("LoggedIn", settingsOwner, function()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local panel = CreateFrame("Frame")
	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(XUI.TITLE)
	local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	note:SetText("All settings live in the XerionUI window.")
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(160, 24)
	button:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
	button:SetText("Open XerionUI")
	button:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		XUI:OpenOptions()
	end)
	local category = Settings.RegisterCanvasLayoutCategory(panel, "XerionUI")
	Settings.RegisterAddOnCategory(category)
end)
