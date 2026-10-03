local addonName, XerionUIFeatures = ...

local moduleName = "LFGImprovements"
local LFGImprovements = XerionUIFeatures:GetModule(moduleName)

local function migrateOldModules(old, fallback)
    if type(old) == "table" and old.enabled ~= nil then
        return old.enabled
    end

    return fallback
end

function LFGImprovements:GetDefaults()
    local profile = XerionUIFeatures.db.profile

    return {
        enabled = true,
        autoAcceptRole = {
            enabled = migrateOldModules(profile.AutoAcceptRole, true),
        },
        groupJoinedReminder = {
            enabled = migrateOldModules(profile.GroupJoinedReminder, true),
        },
        autoLootRoll = {
            enabled = false,
        },
        autoDungeonDifficulty = {
            difficulty = nil,
        },
        autoRaidDifficulty = {
            difficulty = nil,
        },
    }
end
