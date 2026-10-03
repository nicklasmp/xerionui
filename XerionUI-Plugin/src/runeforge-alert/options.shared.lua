local addonName, XerionUIFeatures = ...

local moduleName = "RuneforgeAlert"
local RuneforgeAlert = XerionUIFeatures:GetModule(moduleName)

local deathKnightClassId = 6

-- What both options files draw their lists from: the setups grouped by spec, their
-- controls already laid out two to a row. Nothing here is read at runtime, and the
-- game data behind it never changes, so it is built once on first use.
local groups

local function specNames()
    local names = {}

    for specIndex = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(deathKnightClassId) do
        local specId, specName = GetSpecializationInfoForClassID(deathKnightClassId, specIndex)

        if specId then
            names[specId] = specName
        end
    end

    return names
end

-- A setup with one weapon is named on its own, since the slot it cannot have would
-- only be noise. With two it prefixes them, unless it has no name of its own, which
-- is how the Frost fallback ends up as a plain MH and OH pair.
local function controlLabel(setup, slot)
    if #setup.slots == 1 then
        return setup.label or slot.label
    end

    if not setup.label then
        return slot.label
    end

    return setup.label .. " " .. slot.label
end

-- Two controls to a row: a setup that has both weapons keeps them on a row of their
-- own, and the single weapon setups pair up with each other, so a spec never mixes
-- one setup's weapon with another's.
local function controlRows(setups)
    local rows = {}
    local pending

    local function flush()
        if pending then
            rows[#rows + 1] = pending
            pending = nil
        end
    end

    for _, controls in ipairs(setups) do
        if #controls > 1 then
            flush()

            for index = 1, #controls, 2 do
                rows[#rows + 1] = {controls[index], controls[index + 1]}
            end
        elseif pending then
            pending[2] = controls[1]
            flush()
        else
            pending = {controls[1]}
        end
    end

    flush()

    return rows
end

function RuneforgeAlert:GetSetupGroups()
    if groups then
        return groups
    end

    local names = specNames()
    local groupBySpec = {}
    local setupsBySpec = {}

    groups = {}

    for _, setup in ipairs(self.Setups) do
        local group = groupBySpec[setup.specId]

        if not group then
            group = {
                specId = setup.specId,
                specName = names[setup.specId] or tostring(setup.specId),
            }

            groupBySpec[setup.specId] = group
            setupsBySpec[setup.specId] = {}
            groups[#groups + 1] = group
        end

        local controls = {}

        for _, slot in ipairs(setup.slots) do
            controls[#controls + 1] = {
                key = setup.key .. slot.key,
                setupKey = setup.key,
                slotKey = slot.key,
                label = controlLabel(setup, slot),
            }
        end

        local setups = setupsBySpec[setup.specId]
        setups[#setups + 1] = controls
    end

    for _, group in ipairs(groups) do
        group.rows = controlRows(setupsBySpec[group.specId])
    end

    return groups
end

-- Built per call rather than cached: the icon comes from the runeforging spell, and a
-- texture the client has not loaded yet would otherwise be missing for the session.
function RuneforgeAlert:GetRuneItems()
    local items = {}

    for index, rune in ipairs(self.Runes) do
        items[index] = {
            key = rune.enchantId,
            label = rune.name,
            icon = C_Spell.GetSpellTexture(rune.spellId),
        }
    end

    return items
end

-- The write side of the rune lists. Their readers stay in init.lua, where the alert
-- itself asks the same question on every event.
function RuneforgeAlert:SetRuneAccepted(setupKey, slotKey, enchantId, accepted)
    self.db.setups[setupKey] = self.db.setups[setupKey] or {}
    self.db.setups[setupKey][slotKey] = self.db.setups[setupKey][slotKey] or {}
    self.db.setups[setupKey][slotKey][enchantId] = accepted and true or false
end
