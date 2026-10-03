local addonName, XerionUIFeatures = ...

local moduleName = "RepairIndicator"
local RepairIndicator = XerionUIFeatures:GetModule(moduleName)

function RepairIndicator:PreparePreview(frame)
    frame.text:Show()
end
