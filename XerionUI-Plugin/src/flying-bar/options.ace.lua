local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "FlyingBar"
local FlyingBar = XerionUIFeatures:GetModule(moduleName)

local createStatusbarOptions = function (statusBar, onChange, additionalOptions)
    return XerionUIFeatures:MergeDeep({
        color = {
            order = 10,
            name = "Color",
            type = "color",
            hasAlpha = true, 
            width = 0.4,
            get = function()
                local color = FlyingBar.db[statusBar].color
                return color.r, color.g, color.b, color.a
            end,
            set = function(_, r, g, b, a)
                FlyingBar.db[statusBar].color = {
                    r = r,
                    g = g,
                    b = b,
                    a = a,
                }
                onChange()
            end,
        },
        statusbarTexture = {
            order = 20,
            type = "select",
            width = 0.75,
            dialogControl = "LSM30_Statusbar", 
            name = "Statusbar texture",
            values = LSM:HashTable("statusbar"),
            get = function()
                return FlyingBar.db[statusBar].statusbarTexture
            end,
            set = function(_, value)
                FlyingBar.db[statusBar].statusbarTexture = value
                onChange()
            end,
        },
        height = {
            order = 30,
            type = "range",
            width = 0.75,
            name = "Height",
            min = 3,
            max = 20,
            step = 1,
            get = function()
                return FlyingBar.db[statusBar].height
            end,
            set = function(_, value)
                FlyingBar.db[statusBar].height = value
                onChange()
            end
        },
    }, additionalOptions or {})
end

function FlyingBar:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Flying Bar",
        args = {
            preview = XerionUIFeatures:CreatePreviewOption(FlyingBar),
            description = {
                type = "description",
                name = "Dragonflying bar \n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return FlyingBar.db.enabled
                end,
                set = function(_, value)
                    FlyingBar.db.enabled = value
                    FlyingBar:RefreshConfig()
                end
            },
            displaySettings = {
                type = "group",
                name = "",
                order = 4,
                inline = true,
                args = {
                    width = {
                        order = 1,
                        type = "range",
                        width = 0.75,
                        name = "Width",
                        min = 10,
                        max = 500,
                        step = 1,
                        get = function()
                            return FlyingBar.db.width
                        end,
                        set = function(_, value)
                            FlyingBar.db.width = value
                            onChange()
                        end
                    },
                    frameStrata = {
                        order = 2,
                        type = "select",
                        width = 0.75,
                        name = "Frame strata",
                        values = XerionUIFeatures.FrameStrataSettings,
                        get = function()
                            return FlyingBar.db.frameStrata or XerionUIFeatures.FrameStrataSettings.BACKGROUND
                        end,
                        set = function(_, value)
                            FlyingBar.db.frameStrata = value
                            onChange()
                        end,
                    },
                    frameLevel = {
                        order = 3,
                        type = "range",
                        width = 0.75,
                        name = "Frame level",
                        min = 1,
                        max = 10,
                        step = 1,
                        get = function()
                            return FlyingBar.db.frameLevel or 1
                        end,
                        set = function(_, value)
                            FlyingBar.db.frameLevel = value
                            onChange()
                        end
                    }
                }
            },
            vigor = {
                type = "group",
                name = "Vigor",
                order = 5,
                inline = true,
                args =  createStatusbarOptions('vigor', onChange),
            },
            secondWind = {
                type = "group",
                name = "Second Wind",
                order = 6,
                inline = true,
                args =  createStatusbarOptions('secondWind', onChange),
            },
            speed = {
                type = "group",
                name = "Speed",
                order = 7,
                inline = true,
                args =  createStatusbarOptions('speed', onChange),
            },
        }
    }
end