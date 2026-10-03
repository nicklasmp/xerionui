local addonName, namespace = ...

XerionUIFeatures = LibStub("AceAddon-3.0"):NewAddon(namespace, addonName, "AceConsole-3.0")
XerionUIFeatures.C = LibStub("AceConfig-3.0")
XerionUIFeatures.CD = LibStub("AceConfigDialog-3.0")
XerionUIFeatures.LSM = LibStub("LibSharedMedia-3.0")
XerionUIFeatures.LEM = LibStub("LibEditMode")
XerionUIFeatures.LGF = LibStub("LibGetFrame-1.0")
XerionUIFeatures.testMode = false
XerionUIFeatures.E = ElvUI and unpack(ElvUI)
XerionUIFeatures.EUI = _G.EllesmereUI

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

function XerionUIFeatures:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("XerionUIFeaturesDB", {}, true)

    self.db.profile.all = self.db.profile.all or {
        font = {
            fontFamily = "GothamNarrowBlack",
            fontOutline = "OUTLINE",
            fontShadowColor = {r = 0, g = 0, b = 0, a = 1},
            fontShadowXOffset = 1,
            fontShadowYOffset = -1,
        }
    }

    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshModules")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshModules")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshModules")
end

function XerionUIFeatures:OnEnable()
	self:RegisterOptions()
    self:WatchSharedMedia()
end

function XerionUIFeatures:RefreshModules()
    for _, module in self:IterateModules() do
        if module.RefreshConfig then
            module:RefreshConfig()
        end
    end
end

function XerionUIFeatures:RestyleModules()
    for _, module in self:IterateModules() do
        if not module.db or module.db.enabled then
            
            if module.Restyle then
                module:Restyle()
            elseif module.frame and module.frame.UpdateStyles then
                module.frame:UpdateStyles()
            end
        end
    end
end

function XerionUIFeatures:WatchSharedMedia()
    local rerenderPending = false

    local mediaTypesToRerender = {
        font = true,
        statusbar = true,
        border = true,
        background = true,
    }

    local function batchRerender()
        if rerenderPending then
            return
        end

        rerenderPending = true

        C_Timer.After(0, function()
            rerenderPending = false
            self:RestyleModules()
        end)
    end

    self.LSM.RegisterCallback(self, "LibSharedMedia_Registered", function(_, mediatype)
        if mediaTypesToRerender[mediatype] then
            batchRerender()
        end
    end)

    self.LSM.RegisterCallback(self, "LibSharedMedia_SetGlobal", function(_, mediatype)
        if mediaTypesToRerender[mediatype] then
            batchRerender()
        end
    end)
end

function XerionUIFeatures:ApplyFontSettings()
    for _, module in self:IterateModules() do
        if module.ApplyFontSettings then
            module:ApplyFontSettings(self.db.profile.all.font)
        end
    end
end

function XerionUIFeatures:RegisterOptions()
    local options = self:GetGeneralOptions()

    local AceDBOptions = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

	local parentOptions = {
        type = "group",
        name = self.displayName,
        childGroups = "tree",
        args = options
    }

	self.C:RegisterOptionsTable(addonName, parentOptions)
    self.CD:AddToBlizOptions(addonName, self.displayName)

    for _, module in self:IterateModules() do
        if module.RegisterOptions then
            module:RegisterOptions(parentOptions)
        end
    end

    parentOptions.args['profiles'] = AceDBOptions;
    parentOptions.args['importExport'] = {
        order = 500,
        type = "group",
        name = "Import / Export",
        args = {
            export = {
                order = 1,
                type = "input",
                name = "Export Profile",
                multiline = true,
                width = "full",
                get = function()
                    return XerionUIFeatures:ExportFeatureProfile()
                end,
            },
            spacer = {
                order = 2,
                type = "description",
                name =  "\n\n\n",
                width = "full",
            },
            importOverwrite = {
                type = "input",
                name = "Import (Overwrite Current Profile)",
                desc = "Replaces all settings in the current profile",
                multiline = true,
                width = "full",
                set = function(_, value)
                    StaticPopup_Show(
                        "ITRULIAQOL_CONFIRM_OVERWRITE",
                        nil,
                        nil,
                        value
                    )
                end,
            },
            importNew = {
                type = "input",
                name = "Import as New Profile",
                desc = "Creates a new profile from this string",
                multiline = true,
                width = "full",
                set = function(_, value)
                    StaticPopup_Show(
                        "ITRULIAQOL_IMPORT_NEW_PROFILE",
                        nil,
                        nil,
                        value
                    )
                end,
            },
        },
    }

    local LibDualSpec = LibStub('LibDualSpec-1.0')
    LibDualSpec:EnhanceDatabase(self.db, addonName)
    LibDualSpec:EnhanceOptions(parentOptions.args['profiles'], self.db)

    if (XerionUIFeatures.E) then
        XerionUIFeatures.E.Options.args[addonName] = parentOptions;
        XerionUIFeatures.E.Options.args[addonName].order = 50;
        XerionUIFeatures.E.Options.args[addonName].args.description.name = "You can move things around using the ElvUI movers. Test mode will automatically be turned on\n\n";

        tinsert(XerionUIFeatures.E.ConfigModeLayouts, "XerionUI")
        XerionUIFeatures.E.ConfigModeLocalizedStrings["XerionUI"] = "XerionUI"
    elseif XerionUIFeatures.EUI then
        XerionUIFeatures:RegisterEUI(parentOptions)
    end
end

function XerionUIFeatures:ExportFeatureProfile()
  local profileName = self.db:GetCurrentProfile()
  local profileData = self.db.profiles[profileName]

  local serialized = AceSerializer:Serialize(profileData)
  local compressed = LibDeflate:CompressDeflate(serialized)
  local encoded = LibDeflate:EncodeForPrint(compressed)

  return addonName .. encoded
end

function XerionUIFeatures:DecodeImportString(str)
  if type(str) ~= "string" or not str:find("^" .. addonName) then
    return false, "Missing or invalid prefix"
  end

  local payload = str:sub(#addonName + 1)

  local decoded = LibDeflate:DecodeForPrint(payload)
  if not decoded then
    return false, "Invalid encoded data"
  end

  local decompressed = LibDeflate:DecompressDeflate(decoded)
  if not decompressed then
    return false, "Decompression failed"
  end

  local success, data = AceSerializer:Deserialize(decompressed)
  if not success or type(data) ~= "table" then
    return false, "Invalid serialized profile"
  end

  return true, data
end

local function finish(callback, ok, err)
  if callback then
    callback(ok, err)
  end

  return ok, err
end

function XerionUIFeatures:ImportAsNewProfile(str, profileName, override, callback)
  if not profileName or profileName == "" then
    return finish(callback, false, "Invalid profile name")
  end

  if self.db.profiles[profileName] and not override then
    return finish(callback, false, "Profile already exists")
  end

  local ok, data = self:DecodeImportString(str)
  if not ok then
    return finish(callback, false, data)
  end

  self.db:SetProfile(profileName)

  local profile = self.db.profile
  for k in pairs(profile) do
    profile[k] = nil
  end

  for k, v in pairs(data) do
    profile[k] = v
  end

  self:RefreshModules()

  return finish(callback, true)
end

function XerionUIFeatures:ImportIntoCurrentProfile(str, callback)
  local ok, dataOrErr = self:DecodeImportString(str)
  if not ok then
    return finish(callback, false, dataOrErr)
  end

  local profile = self.db.profile

  for k in pairs(profile) do
    profile[k] = nil
  end

  for k, v in pairs(dataOrErr) do
    profile[k] = v
  end

  self:RefreshModules()

  return finish(callback, true)
end

function XerionUIFeatures:ToggleTestMode(enabled)
    self.testMode = enabled

    for _, module in self:IterateModules() do
        if module.ToggleTestMode then
            xpcall(module.ToggleTestMode, geterrorhandler(), module, enabled)
        end
    end
end


-- The three config hosts, each a { available, open } pair, so the automatic pick
-- and the explicit subcommands go through the same code.
local hosts = {
    elvui = {
        label = "ElvUI",
        available = function(self)
            return self.E and self.E.ToggleOptions and true or false
        end,
        open = function(self)
            self.E:ToggleOptions(addonName)
        end,
    },
    eui = {
        label = "EllesmereUI",
        available = function(self)
            return self.EUI and self.EUI.ShowModule and true or false
        end,
        open = function(self)
            -- Back to the row it was left on, General on the first open of the
            -- session (see integrations/ellesmere/ellesmere.lua's addEntry keys).
            -- EllesmereUI restores that row's own tab.
            local moduleKey = self:GetLastEUIModule() or (addonName .. "_General")

            self.EUI:ShowModule(moduleKey)

            -- Our group sits below EllesmereUI's own suite, so the row we just
            -- selected is off screen until the sidebar is scrolled to it.
            if self.ScrollEUISidebarToGroup then
                self:ScrollEUISidebarToGroup(moduleKey)
            end
        end,
    },
    standalone = {
        label = "standalone",
        available = function()
            return true
        end,
        open = function(self)
            self.CD:Open(addonName)
        end,
    },
}

local hostAliases = {
    elv = "elvui",
    elvui = "elvui",
    tukui = "elvui",
    eui = "eui",
    ellesmere = "eui",
    ellesmereui = "eui",
    standalone = "standalone",
    ace = "standalone",
    blizzard = "standalone",
}

local autoOrder = { "elvui", "eui", "standalone" }

function XerionUIFeatures:OpenConfig(host)
    if host then
        local spec = hosts[host]

        if not spec.available(self) then
            self:Print("|cffff0000" .. spec.label .. " is not available.|r Opening the standalone config instead.")
            hosts.standalone.open(self)

            return
        end

        spec.open(self)

        return
    end

    for _, key in ipairs(autoOrder) do
        local spec = hosts[key]

        if spec.available(self) then
            spec.open(self)

            return
        end
    end
end

function XerionUIFeatures:MySlashProcessorFunc(input)
    local arg = input and input:lower():match("^%s*(%S*)") or ""

    if arg == "" or arg == "config" or arg == "c" then
        self:OpenConfig()
    elseif hostAliases[arg] then
        self:OpenConfig(hostAliases[arg])
    elseif arg == "test" or arg == "t" then
        self:ToggleTestMode(not XerionUIFeatures.testMode)
    else
        self:Print("AddOn commands:")
        self:Print("/xui")
        self:Print("/xui config")
        self:Print("/xui elvui")
        self:Print("/xui eui")
        self:Print("/xui standalone")
        self:Print("/xui help")
        self:Print("/xui test")
    end
end

if XerionUIFeatures.E then
  hooksecurefunc(XerionUIFeatures.E, "ToggleMovers", function(_, enabled)
      XerionUIFeatures:ToggleTestMode(enabled)
  end)
elseif not XerionUIFeatures.EUI then
    -- EllesmereUI drives test mode via RegisterUnlockModeListener (see ellesmere.lua).
    XerionUIFeatures.LEM:RegisterCallback('enter', function()
	    XerionUIFeatures:ToggleTestMode(true)
    end)

    XerionUIFeatures.LEM:RegisterCallback('exit', function()
        XerionUIFeatures:ToggleTestMode(false)
    end)
end

StaticPopupDialogs["ITRULIAQOL_CONFIRM_OVERWRITE"] = {
  text = "This will replace every setting in your current profile. Continue?",
  button1 = YES,
  button2 = NO,

  OnAccept = function(self)
    local ok, err = XerionUIFeatures:ImportIntoCurrentProfile(self.data)

    if not ok then
      XerionUIFeatures:Print("|cffff0000Import failed:|r", err)
    else
      XerionUIFeatures:Print("|cff00ff00Profile imported.|r")
    end

    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
  end,

  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

StaticPopupDialogs["ITRULIAQOL_IMPORT_NEW_PROFILE"] = {
  text = "Enter a name for the new profile:",
  button1 = ACCEPT,
  button2 = CANCEL,
  hasEditBox = true,
  maxLetters = 50,

  OnAccept = function(self)
    local profileName = self.EditBox:GetText()
    local str = self.data

    local ok, err = XerionUIFeatures:ImportAsNewProfile(str, profileName)
    if not ok then
      XerionUIFeatures:Print("|cffff0000Import failed:|r", err)
    else
      XerionUIFeatures:Print("|cff00ff00Profile created:|r", profileName)
    end

    LibStub("AceConfigRegistry-3.0"):NotifyChange(addonName)
  end,

  OnShow = function(self)
    self.EditBox:SetText("")
    self.EditBox:SetFocus()
  end,

  EditBoxOnEnterPressed = function(self)
    StaticPopup_OnClick(self:GetParent(), 1)
  end,

  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

hooksecurefunc("StaticPopup_Show", function(which)
  if which and which:find("^ITRULIAQOL_") then
    local frame = StaticPopup_FindVisible(which)
    
    if frame then
      frame:SetFrameStrata("TOOLTIP")
      frame:SetFrameLevel(1000)
    end
  end
end)
