local addonName, XerionUIFeatures = ...

local moduleName = "Misc"
local Misc = XerionUIFeatures:GetModule(moduleName)

function Misc:GetOptions(onChange)
    return {
        order = 50,
        type = "group",
        name = "Misc",
        args = {
            description = {
                type = "description",
                name = "Smaller tweaks that do not warrant a module of their own\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return Misc.db.enabled
                end,
                set = function(_, value)
                    Misc.db.enabled = value
                    Misc:RefreshConfig()
                end,
            },
            auctionHouseFilters = {
                order = 10,
                type = "toggle",
                width = "full",
                name = "Auction house filter defaults",
                desc = "Preselects 'Current expansion only' and 'Usable items only' in the auction house browse filters",
                disabled = function()
                    return not Misc.db.enabled
                end,
                get = function()
                    return Misc.db.auctionHouseFilters.enabled
                end,
                set = function(_, value)
                    Misc.db.auctionHouseFilters.enabled = value
                    Misc:RefreshConfig()
                end,
            },
        }
    }
end
