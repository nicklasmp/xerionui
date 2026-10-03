local addonName, XerionUIFeatures = ...

local moduleName = "PetMissingIndicator"
local PetMissingIndicator = XerionUIFeatures:GetModule(moduleName)

function PetMissingIndicator:PreparePreview(frame)
    frame.text:Show()
end
