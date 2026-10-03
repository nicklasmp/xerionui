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
}

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
		elseif XUI.DB:ProfileExists(rest) then
			XUI.DB:SetProfile(rest)
			XUI.Printf("switched to profile |cffffffff%s|r", rest)
		else
			XUI.Printf("no profile named |cffffffff%s|r", rest)
		end
	elseif cmd == "preview" then
		for _, m in ipairs(XUI.modules) do m:SetPreview(false) end
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
