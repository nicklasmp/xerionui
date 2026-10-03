local addonName, XerionUIFeatures = ...

local moduleName = "LFGImprovements"
local LFGImprovements = XerionUIFeatures:GetModule(moduleName)

function LFGImprovements:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "LFG Improvements",
        args = {
            description = {
                type = "description",
                name = "Group Finder helpers: automatic role confirmation, a reminder of the key you joined, automatic loot rolls and automatic difficulty selection\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function()
                    return LFGImprovements.db.enabled
                end,
                set = function(_, value)
                    LFGImprovements.db.enabled = value
                    LFGImprovements:RefreshConfig()
                end,
            },
            autoAcceptRole = {
                order = 10,
                type = "toggle",
                width = "full",
                name = "Automatically accept the role call when signing up",
                disabled = function()
                    return not LFGImprovements.db.enabled
                end,
                get = function()
                    return LFGImprovements.db.autoAcceptRole.enabled
                end,
                set = function(_, value)
                    LFGImprovements.db.autoAcceptRole.enabled = value
                    LFGImprovements:RefreshConfig()
                end,
            },
            groupJoinedReminder = {
                order = 20,
                type = "toggle",
                width = "full",
                name = "Remind you in the chat what mythic+ key you joined",
                disabled = function()
                    return not LFGImprovements.db.enabled
                end,
                get = function()
                    return LFGImprovements.db.groupJoinedReminder.enabled
                end,
                set = function(_, value)
                    LFGImprovements.db.groupJoinedReminder.enabled = value
                    LFGImprovements:RefreshConfig()
                end,
            },
            autoDungeonDifficulty = {
                order = 30,
                type = "select",
                style = "dropdown",
                name = "Auto dungeon difficulty",
                values = function()
                    return (LFGImprovements:GetDifficultyOptions("dungeon"))
                end,
                sorting = function()
                    local _, order = LFGImprovements:GetDifficultyOptions("dungeon")
                    return order
                end,
                disabled = function()
                    return not LFGImprovements.db.enabled
                end,
                get = function()
                    return LFGImprovements:GetDifficulty("dungeon")
                end,
                set = function(_, value)
                    LFGImprovements:SaveDifficulty("dungeon", value)
                    LFGImprovements:RefreshConfig()
                end,
            },
            spacer = {
                type = "description",
                name = "",
                width = "full",
                order = 31,
            },
            autoRaidDifficulty = {
                order = 40,
                type = "select",
                style = "dropdown",
                name = "Auto raid difficulty",
                values = function()
                    return (LFGImprovements:GetDifficultyOptions("raid"))
                end,
                sorting = function()
                    local _, order = LFGImprovements:GetDifficultyOptions("raid")
                    return order
                end,
                disabled = function()
                    return not LFGImprovements.db.enabled
                end,
                get = function()
                    return LFGImprovements:GetDifficulty("raid")
                end,
                set = function(_, value)
                    LFGImprovements:SaveDifficulty("raid", value)
                    LFGImprovements:RefreshConfig()
                end,
            },
            autoLootRoll = {
                order = 50,
                type = "toggle",
                width = "full",
                name = "Auto transmog/greed",
                desc = "Stays out of the way while RCLootCouncil is handling the loot for the group.",
                disabled = function()
                    return not LFGImprovements.db.enabled
                end,
                get = function()
                    return LFGImprovements.db.autoLootRoll.enabled
                end,
                set = function(_, value)
                    LFGImprovements.db.autoLootRoll.enabled = value
                    LFGImprovements:RefreshConfig()
                end,
            },
        }
    }
end
