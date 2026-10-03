local addonName, XerionUIFeatures = ...

local moduleName = "CursorCircle"
local CursorCircle = XerionUIFeatures:GetModule(moduleName)

function CursorCircle:PreparePreview(frame)
    frame:Show()
end
