local addonName, XerionUIFeatures = ...

local moduleName = "SelfDispelAlert"
local SelfDispelAlert = XerionUIFeatures:GetModule(moduleName)

-- Keys must match the sourceKey values on SelfDispelAlert.sources in init.lua.
local sourceOptions = {
    {key = "DRUID", label = "Druid"},
    {key = "EVOKER", label = "Evoker"},
    {key = "HUNTER", label = "Hunter (Feign Death)"},
    {key = "MAGE", label = "Mage"},
    {key = "MONK", label = "Monk"},
    {key = "PALADIN", label = "Paladin"},
    {key = "PRIEST", label = "Priest"},
    {key = "SHAMAN", label = "Shaman"},
    {key = "RACIAL", label = "Dwarf racials"},
}

function SelfDispelAlert:GetSourceItems()
    local items = {}

    for index, option in ipairs(sourceOptions) do
        items[index] = {key = option.key, label = option.label}
    end

    return items
end

function SelfDispelAlert:SetSourceEnabled(key, enabled)
    self.db.enabledSources[key] = enabled and true or false
end
