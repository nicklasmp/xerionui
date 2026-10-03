local addonName, XerionUIFeatures = ...

local moduleName = "HealerManaIndicator"
local HealerManaIndicator = XerionUIFeatures:GetModule(moduleName)

function HealerManaIndicator:PreparePreview(frame)
    frame:ClearTexts()
    frame:UpdateManaText(1, "player", 69)
    frame:UpdateManaText(2, "player", 50)
    frame:UpdateStyles()
end
