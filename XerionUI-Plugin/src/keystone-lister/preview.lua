local addonName, XerionUIFeatures = ...

local moduleName = "KeystoneLister"
local KeystoneLister = XerionUIFeatures:GetModule(moduleName)

KeystoneLister.pageDisplay = "Display"
KeystoneLister.pageListing = "Listing"

function KeystoneLister:PreparePreview(frame)
    frame:UpdateStyles()
    frame:Show()
end
