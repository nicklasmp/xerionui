local addonName, XerionUIFeatures = ...

local moduleName = "StanceAlert"
local StanceAlert = XerionUIFeatures:GetModule(moduleName)

function StanceAlert:PreparePreview(frame)
    frame.text:Show()
end
