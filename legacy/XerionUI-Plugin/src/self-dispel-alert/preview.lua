local addonName, XerionUIFeatures = ...

local moduleName = "SelfDispelAlert"
local SelfDispelAlert = XerionUIFeatures:GetModule(moduleName)

function SelfDispelAlert:PreparePreview(frame)
    frame.gate:SetAlpha(1)
    frame.display:Show()
end
