local addonName, XerionUIFeatures = ...

local moduleName = "RuneforgeAlert"
local RuneforgeAlert = XerionUIFeatures:GetModule(moduleName)

RuneforgeAlert.pageDisplay = "Display"
RuneforgeAlert.pageRuneforges = "Runeforges"

function RuneforgeAlert:PreparePreview(frame)
    frame.text:Show()
end
