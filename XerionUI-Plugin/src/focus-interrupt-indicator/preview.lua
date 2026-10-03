local addonName, XerionUIFeatures = ...

local moduleName = "FocusInterruptIndicator"
local FocusInterruptIndicator = XerionUIFeatures:GetModule(moduleName)

function FocusInterruptIndicator:PreparePreview(frame)
    frame.text:Show()
    frame.text:SetAlpha(1)
end
