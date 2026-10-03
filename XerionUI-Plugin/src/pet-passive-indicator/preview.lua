local addonName, XerionUIFeatures = ...

local moduleName = "PetPassiveIndicator"
local PetPassiveIndicator = XerionUIFeatures:GetModule(moduleName)

function PetPassiveIndicator:PreparePreview(frame)
    frame.text:Show()
end
