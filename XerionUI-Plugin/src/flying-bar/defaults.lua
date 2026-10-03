local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "FlyingBar"
local FlyingBar = XerionUIFeatures:GetModule(moduleName)

function FlyingBar:GetDefaults()
    return {
        enabled = false,
        width = 350,
        point = {point = "CENTER", x = 0, y = 0},
        updateInterval = 0.1,
        speed = {
            height = 12,
            statusbarTexture = "Skullflower2",
            color = {r = 0.451, g = 0.741, b = 0.522, a = 1},
        },
        vigor = {
            height = 5,
            statusbarTexture = "Skullflower2",
            color = {r = 0, g = 0.690, b = 0.980, a = 1},
        },
        secondWind = {
            height = 5,
            statusbarTexture = "Skullflower2",
            color = {r = 1, g = 0.502, b = 0.251, a = 1},
        }
    }
end