local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "CursorCircle"
local CursorCircle = XerionUIFeatures:GetModule(moduleName)

function CursorCircle:GetDefaults()
    return {
        enabled = false,
        onlyDuringCombat = false,
        displayTexture = [[Interface\AddOns\XerionUI-Plugin\Media\textures\ItruliaCircleMedium.tga]],
        size = 28,
        color = {r = 0.769, g = 0.118, b = 0.227, a = 1},
    }
end