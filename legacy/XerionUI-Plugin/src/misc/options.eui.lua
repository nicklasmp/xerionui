local addonName, XerionUIFeatures = ...

local moduleName = "Misc"
local Misc = XerionUIFeatures:GetModule(moduleName)
-- Catch-all row, so it sits at the end of the EllesmereUI sidebar rather than under M.
Misc.EUISortLast = true

function Misc:GetEUIOptions()
    return {
        name = "Misc",
        rows = {
            {
                type = "toggle",
                label = "Auction house filter defaults",
                tooltip = "Preselects 'Current expansion only' and 'Usable items only' in the auction house browse filters",
                get = function()
                    return Misc.db.auctionHouseFilters.enabled
                end,
                set = function(value)
                    Misc.db.auctionHouseFilters.enabled = value
                    Misc:RefreshConfig()
                end,
            },
        },
    }
end
