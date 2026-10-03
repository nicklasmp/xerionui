local addonName, XerionUIFeatures = ...

local moduleName = "MeleeIndicator"
local MeleeIndicator = XerionUIFeatures:GetModule(moduleName)

function MeleeIndicator:PreparePreview(frame)
    frame.text:Show()
end
