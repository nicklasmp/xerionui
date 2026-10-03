local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "PreventRelease"
local PreventRelease = XerionUIFeatures:GetModule(moduleName)

function PreventRelease:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Prevent Release",
        args = {
            description = {
                type = "description",
                name =  "Disable release button unless you hold down ctrl\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function() 
                    return PreventRelease.db.enabled
                end,
                set = function(_, value)
                    PreventRelease.db.enabled = value
                    PreventRelease:RefreshConfig()
                end,
            },
            raidOnly = {
                order = 3,
                type = "toggle",
                width = "full",
                name = "Only in a raid",
                disabled = function()
                    return not PreventRelease.db.enabled
                end,
                get = function()
                    return PreventRelease.db.raidOnly
                end,
                set = function(_, value)
                    PreventRelease.db.raidOnly = value
                    PreventRelease:RefreshConfig()
                end,
            },
        }
    }
end