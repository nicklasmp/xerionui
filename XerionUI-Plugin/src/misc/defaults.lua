local addonName, XerionUIFeatures = ...

local moduleName = "Misc"
local Misc = XerionUIFeatures:GetModule(moduleName)

function Misc:GetDefaults()
    return {
        enabled = false,
        auctionHouseFilters = {
            enabled = false,
        },
    }
end
