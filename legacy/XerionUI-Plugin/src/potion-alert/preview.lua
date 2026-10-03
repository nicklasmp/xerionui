local addonName, XerionUIFeatures = ...

local moduleName = "PotionAlert"
local PotionAlert = XerionUIFeatures:GetModule(moduleName)

function PotionAlert:PreparePreview(frame)
    frame.text:Show()
end
