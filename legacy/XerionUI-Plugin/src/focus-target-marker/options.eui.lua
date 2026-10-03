local addonName, XerionUIFeatures = ...

local moduleName = "FocusTargetMarker"
local FocusTargetMarker = XerionUIFeatures:GetModule(moduleName)

-- Raid-marker dropdown entries: icon texture + localized marker name, matching
-- the AceConfig select in options.ace.lua.
local function RaidMarkerString(index)
    local coords = {
        [1] = {0.00, 0.25, 0.00, 0.25}, -- Star
        [2] = {0.25, 0.50, 0.00, 0.25}, -- Circle
        [3] = {0.50, 0.75, 0.00, 0.25}, -- Diamond
        [4] = {0.75, 1.00, 0.00, 0.25}, -- Triangle
        [5] = {0.00, 0.25, 0.25, 0.50}, -- Moon
        [6] = {0.25, 0.50, 0.25, 0.50}, -- Square
        [7] = {0.50, 0.75, 0.25, 0.50}, -- Cross
        [8] = {0.75, 1.00, 0.25, 0.50}, -- Skull
    }
    local left, right, top, bottom = unpack(coords[index])

    return string.format(
        "|TInterface\\TargetingFrame\\UI-RaidTargetingIcons:16:16:0:0:256:256:%d:%d:%d:%d|t %s",
        left * 256, right * 256, top * 256, bottom * 256,
        _G["RAID_TARGET_" .. index]
    )
end

function FocusTargetMarker:GetEUIOptions()
    return {
        name = "Focus Marker",
        rows = {
            {
                text = "Creates a macro called FocusTargetMarker which automatically marks your mouseover or target with the configured raid marker",
            },
            {
                pair = {
                    {
                        type = "select",
                        label = "Marker",
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
                        order = { 1, 2, 3, 4, 5, 6, 7, 8 },
                        get = function()
                            return FocusTargetMarker.db.marker
                        end,
                        set = function(value)
                            FocusTargetMarker.db.marker = value
                            FocusTargetMarker:RefreshConfig()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Announce on ready check",
                        get = function()
                            return FocusTargetMarker.db.announce
                        end,
                        set = function(value)
                            FocusTargetMarker.db.announce = value
                        end,
                    },
                },
            },
        },
    }
end
