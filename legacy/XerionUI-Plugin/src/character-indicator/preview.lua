local addonName, XerionUIFeatures = ...

local moduleName = "CharacterIndicator"
local CharacterIndicator = XerionUIFeatures:GetModule(moduleName)

function CharacterIndicator:PreparePreview(frame)
    frame.text:Show()
end
