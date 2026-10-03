local addonName, XerionUIFeatures = ...

local moduleName = "KeystoneLister"
local KeystoneLister = XerionUIFeatures:GetModule(moduleName)

-- Everyone else's keystone comes over an addon channel, so only group members
-- running an addon that embeds LibKeystone (BigWigs and EllesmereUI both do)
-- report one. Your own key is read locally and always shows.
local LibKeystone = LibStub("LibKeystone", true)

-- "Name-Realm" -> {level, challengeMapId, rating}. Keyed by name rather than unit
-- because that is what arrives over the wire; the roster is filtered back down
-- to the current group when the menu is built.
local reported = {}

-- Three sources, three shapes of name, and comparing them raw is what kept every
-- party member out of the menu:
--
--   * a group member's key arrives as Ambiguate(sender, "none"), which keeps the
--     realm on it -- "Cyanidia-TarrenMill"
--   * our own arrives from UnitNameUnmodified("player"), which never has one
--   * the roster is walked with unit tokens, which hand back the two halves apart
--
-- So everything is put into the realm-qualified form. The realm is read per call
-- rather than cached: this file loads before the player is in the world, where
-- GetNormalizedRealmName has nothing to say yet.
local function qualifiedName(name, realm)
    if not name or name == "" then
        return nil
    end

    if realm and realm ~= "" then
        return name .. "-" .. realm
    end

    if name:find("-", 1, true) then
        return name
    end

    return name .. "-" .. (GetNormalizedRealmName() or "")
end

if LibKeystone then
    LibKeystone.Register(KeystoneLister, function(level, challengeMapId, rating, sender, channel)
        local name = channel == "PARTY" and qualifiedName(sender)

        if not name then
            return
        end

        -- A zeroed pair means "no key", which is also how a key that was just
        -- used is reported -- drop the entry rather than keep a stale one.
        if not level or level == 0 or not challengeMapId or challengeMapId == 0 then
            reported[name] = nil

            return
        end

        reported[name] = {level = level, challengeMapId = challengeMapId, rating = rating}
    end)
end

function KeystoneLister:RequestGroupKeystones()
    if not LibKeystone then
        return
    end

    -- Throttled inside the library, so calling this on roster changes and on
    -- every menu open costs nothing.
    LibKeystone.Request("PARTY")
end

-- challengeMapId -> group finder activityId.
--
-- C_ChallengeMode.GetMapUIInfo returns the instance's mapID as its sixth value,
-- and GroupFinderActivityInfo carries the same mapID -- so the two sides join on
-- that without going anywhere near dungeon names.
--
-- Only your own key has a purpose-built lookup
-- (C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel); listing someone else's
-- means resolving their dungeon ourselves.
local activityByChallengeMap

-- GetAvailableActivities' trailing parameters have moved between clients, so try
-- the plain category listing first and fall back to the explicit-filter form
-- Blizzard's own UI uses.
local function availableActivities(categoryId)
    local ok, activities = pcall(C_LFGList.GetAvailableActivities, categoryId, nil, 0)

    if not ok or not activities then
        ok, activities = pcall(C_LFGList.GetAvailableActivities, categoryId)
    end

    return (ok and activities) or {}
end

local function buildActivityMap()
    local byMapId = {}
    local byName = {}

    for _, categoryId in ipairs(C_LFGList.GetAvailableCategories() or {}) do
        for _, activityId in ipairs(availableActivities(categoryId)) do
            local info = C_LFGList.GetActivityInfoTable(activityId)

            if info and info.isMythicPlusActivity then
                if info.mapID then
                    byMapId[info.mapID] = activityId
                end

                -- Name match as a second chance, in case mapID ever stops lining
                -- up between the two APIs.
                if info.fullName then
                    byName[info.fullName] = activityId
                end
            end
        end
    end

    local map = {}

    for _, challengeMapId in ipairs(C_ChallengeMode.GetMapTable() or {}) do
        local name, _, _, _, _, mapId = C_ChallengeMode.GetMapUIInfo(challengeMapId)
        local activityId = (mapId and byMapId[mapId]) or (name and byName[name])

        if activityId then
            map[challengeMapId] = activityId
        end
    end

    return map
end

function KeystoneLister:GetActivityForChallengeMap(challengeMapId, rebuilt)
    if not challengeMapId then
        return nil
    end

    activityByChallengeMap = activityByChallengeMap or buildActivityMap()

    local activityId = activityByChallengeMap[challengeMapId]

    if activityId or rebuilt then
        return activityId
    end

    -- Built before the activity list arrived, or a season rotated a dungeon in.
    -- Worth exactly one rebuild before giving up on this key.
    activityByChallengeMap = nil

    return self:GetActivityForChallengeMap(challengeMapId, true)
end

function KeystoneLister:ResetActivityMap()
    activityByChallengeMap = nil
end

function KeystoneLister:GetChallengeMapName(challengeMapId)
    return (challengeMapId and C_ChallengeMode.GetMapUIInfo(challengeMapId)) or "Unknown"
end

-- The group's keystones, best first. Filtered against who is actually here, so a
-- key reported by someone who has since left cannot linger in the menu.
function KeystoneLister:GetGroupKeystones()
    local entries = {}
    local seen = {}

    for _, unit in ipairs(XerionUIFeatures:GetGroupUnits()) do
        -- Matched on the realm-qualified name, shown by the bare one: two realms can
        -- send the same first name, and only the menu has room to care.
        local key = qualifiedName(UnitFullName(unit))
        local entry = key and reported[key]

        if key and entry and not seen[key] then
            seen[key] = true

            entries[#entries + 1] = {
                name = UnitName(unit) or key,
                unit = unit,
                level = entry.level,
                challengeMapId = entry.challengeMapId,
                dungeon = self:GetChallengeMapName(entry.challengeMapId),
            }
        end
    end

    table.sort(entries, function(a, b)
        if a.level ~= b.level then
            return a.level > b.level
        end

        return a.name < b.name
    end)

    return entries
end
