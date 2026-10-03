local addonName, XerionUIFeatures = ...
local moduleName = "Misc"

local Misc = XerionUIFeatures:NewModule(moduleName)

Misc.AuctionHouseFilters = {
    [Enum.AuctionHouseFilter.UsableOnly] = true,
    [Enum.AuctionHouseFilter.CurrentExpansionOnly] = true,
    [Enum.AuctionHouseFilter.UpgradesOnly] = false,
    [Enum.AuctionHouseFilter.UncollectedOnly] = false,

    [Enum.AuctionHouseFilter.PoorQuality] = true,
    [Enum.AuctionHouseFilter.CommonQuality] = true,
    [Enum.AuctionHouseFilter.UncommonQuality] = true,
    [Enum.AuctionHouseFilter.RareQuality] = true,
    [Enum.AuctionHouseFilter.EpicQuality] = true,
    [Enum.AuctionHouseFilter.LegendaryQuality] = true,
    [Enum.AuctionHouseFilter.ArtifactQuality] = true,
}

local blizzardAuctionHouseFilters

local frame = CreateFrame("frame", addonName .. moduleName)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")

frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == "Blizzard_AuctionHouseUI" then
        Misc:SwapAuctionHouseDefaults()
    elseif event == "AUCTION_HOUSE_SHOW" then
        Misc:ApplyAuctionHouseFilters()
    end
end)

function Misc:IsAuctionHouseFiltersActive()
    return self.db.enabled and self.db.auctionHouseFilters.enabled
end

function Misc:SwapAuctionHouseDefaults()
    if not AUCTION_HOUSE_DEFAULT_FILTERS then
        return
    end

    if self:IsAuctionHouseFiltersActive() then
        blizzardAuctionHouseFilters = blizzardAuctionHouseFilters or AUCTION_HOUSE_DEFAULT_FILTERS
        AUCTION_HOUSE_DEFAULT_FILTERS = self.AuctionHouseFilters
    elseif blizzardAuctionHouseFilters then
        AUCTION_HOUSE_DEFAULT_FILTERS = blizzardAuctionHouseFilters
    end
end

function Misc:ApplyAuctionHouseFilters()
    if not self:IsAuctionHouseFiltersActive() then
        return
    end

    self:SwapAuctionHouseDefaults()

    -- A frame later, so the search bar is done setting itself up for this visit.
    C_Timer.After(0, function()
        local searchBar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
        local filterButton = searchBar and searchBar.FilterButton

        if not filterButton or not filterButton.GetFilters or not filterButton.ToggleFilter then
            return
        end

        local filters = filterButton:GetFilters()

        for filter, value in pairs(self.AuctionHouseFilters) do
            if (filters[filter] or false) ~= value then
                filterButton:ToggleFilter(filter)
            end
        end

        if filterButton.UpdateSelections then
            filterButton:UpdateSelections()
        end

        if filterButton.ValidateResetState then
            filterButton:ValidateResetState()
        end
    end)
end

function Misc:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.Misc = profile.Misc or Misc:GetDefaults()
    self.db = profile.Misc
end

function Misc:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.Misc = profile.Misc or Misc:GetDefaults()
    self.db = profile.Misc

    self:ApplyAuctionHouseFilters()
end

function Misc:OnEnable()
    self:RefreshConfig()
end

function Misc:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
    end);
end