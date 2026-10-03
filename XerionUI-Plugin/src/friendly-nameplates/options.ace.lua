local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "FriendlyNameplates"
local FriendlyNameplates = XerionUIFeatures:GetModule(moduleName)

function FriendlyNameplates:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Friendly Nameplates",
        args = {
            description = {
                type = "description",
                name =  "Improves the display of the friendly nameplates in instances\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function() 
                    return FriendlyNameplates.db.enabled
                end,
                set = function(_, value)
                    FriendlyNameplates.db.enabled = value
                    FriendlyNameplates:RefreshConfig()
                end,
            },
            fontSettings = {
                type = "group",
                name = "",
                order = 3,
                inline = true,
                args = XerionUIFeatures:createFontOptions(function() return FriendlyNameplates.db.font end, function() 
                    onChange()
                end, {
                    justifyH = XerionUIFeatures.MergeDeep_Delete_Key,
                    spacer = XerionUIFeatures.MergeDeep_Delete_Key,
                    fontShadowXOffset = XerionUIFeatures.MergeDeep_Delete_Key,
                    fontShadowYOffset = XerionUIFeatures.MergeDeep_Delete_Key,
                    fontShadowColor = XerionUIFeatures.MergeDeep_Delete_Key,
                    spacer2 = XerionUIFeatures.MergeDeep_Delete_Key,
                    frameStrata = XerionUIFeatures.MergeDeep_Delete_Key,
                    frameLevel = XerionUIFeatures.MergeDeep_Delete_Key,
                })
            },
        }
    }
end