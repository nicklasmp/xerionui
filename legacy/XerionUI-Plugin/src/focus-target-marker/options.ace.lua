local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

local moduleName = "FocusTargetMarker"
local FocusTargetMarker = XerionUIFeatures:GetModule(moduleName)

local function RaidMarkerString(index)
    local table = {
        [1] = {0.00, 0.25, 0.00, 0.25}, -- Star
        [2] = {0.25, 0.50, 0.00, 0.25}, -- Circle
        [3] = {0.50, 0.75, 0.00, 0.25}, -- Diamond
        [4] = {0.75, 1.00, 0.00, 0.25}, -- Triangle
        [5] = {0.00, 0.25, 0.25, 0.50}, -- Moon
        [6] = {0.25, 0.50, 0.25, 0.50}, -- Square
        [7] = {0.50, 0.75, 0.25, 0.50}, -- Cross
        [8] = {0.75, 1.00, 0.25, 0.50}, -- Skull
    }
    local left, right, top, bottom = unpack(table[index])

    return string.format(
        "|TInterface\\TargetingFrame\\UI-RaidTargetingIcons:16:16:0:0:256:256:%d:%d:%d:%d|t %s",
        left * 256, right * 256, top * 256, bottom * 256,
        _G["RAID_TARGET_" .. index]
    )
end

function FocusTargetMarker:GetOptions(onChange)
    return {
        order = 2,
        type = "group",
        name = "Focus Marker",
        args = {
            description = {
                type = "description",
                name =  "Creates a macro called FocusTargetMarker which automatically marks your mouseover or target with the configured raid marker\n\n",
                width = "full",
                order = 1,
            },
            enable = {
                order = 2,
                type = "toggle",
                width = "full",
                name = "Enable",
                get = function() 
                    return FocusTargetMarker.db.enabled
                end,
                set = function(_, value)
                    FocusTargetMarker.db.enabled = value
                    FocusTargetMarker:RefreshConfig()
                end,
            },
            announce = {
                order = 3,
                type = "toggle",
                width = "full",
                name = "Announce on ready check",
                get = function() 
                    return FocusTargetMarker.db.announce
                end,
                set = function(_, value)
                    FocusTargetMarker.db.announce = value
                end,
            },
            marker = {
                order = 4,
                type = "select",
                name = "Focus Marker",
                values = {
                    [1] = RaidMarkerString(1),
                    [2] = RaidMarkerString(2),
                    [3] = RaidMarkerString(3),
                    [4] = RaidMarkerString(4),
                    [5] = RaidMarkerString(5),
                    [6] = RaidMarkerString(6),
                    [7] = RaidMarkerString(7),
                    [8] = RaidMarkerString(8),
                },
                style = "dropdown",
                get = function()
                    return FocusTargetMarker.db.marker
                end,
                set = function(_, value)
                    FocusTargetMarker.db.marker = value
                    onChange()
                end,
            },
        }
    }
end