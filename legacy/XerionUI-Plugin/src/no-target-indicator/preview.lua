local addonName, XerionUIFeatures = ...

local moduleName = "NoTargetIndicator"
local NoTargetIndicator = XerionUIFeatures:GetModule(moduleName)

function NoTargetIndicator:PreparePreview(frame)
    frame.text:Show()
end
