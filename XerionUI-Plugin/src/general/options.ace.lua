local addonName, XerionUIFeatures = ...

function XerionUIFeatures:GetGeneralOptions()
    return {
        description = {
            type = "description",
            name =  "You can move things around using the native Edit Mode. Test mode will automatically be turned on\n\n Note that it ignores the Edit Mode layouts \n\n",
            width = "full",
            order = 1,
        },
        enable = {
            order = 2,
            type = "toggle",
            width = "full",
            name = "Test mode",
            get = function()
                return XerionUIFeatures.testMode
            end,
            set = function(_, value)
                XerionUIFeatures:ToggleTestMode(value)
            end
        },
        all = {
            type = "group",
            name = "All",
            order = 1,
            args = {
                fontSettings = {
                    type = "group",
                    name = "Font",
                    inline = true,
                    args = XerionUIFeatures:createFontOptions(function() return XerionUIFeatures.db.profile.all.font end, function() end, {
                        frameStrata = XerionUIFeatures.MergeDeep_Delete_Key,
                        frameLevel = XerionUIFeatures.MergeDeep_Delete_Key,
                        applyAll = {
                            type = "execute",
                            name = "Apply to all",
                            func = function()
                                XerionUIFeatures:ApplyFontSettings()
                            end,
                        },
                    })
                },
            }
        },
    }
end
