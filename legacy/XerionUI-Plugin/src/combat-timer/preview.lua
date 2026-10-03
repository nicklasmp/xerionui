local addonName, XerionUIFeatures = ...

local moduleName = "CombatTimer"
local CombatTimer = XerionUIFeatures:GetModule(moduleName)

function CombatTimer:PreparePreview(frame)
    frame.text:SetText(frame:FormatTime(83))
    frame.text:Show()
    frame:UpdateStyles()
end
