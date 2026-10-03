local addonName, XerionUIFeatures = ...

local moduleName = "StealthIndicator"
local StealthIndicator = XerionUIFeatures:GetModule(moduleName)

function StealthIndicator:PreparePreview(frame)
    frame.text:Show()
end
