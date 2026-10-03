local addonName, XerionUIFeatures = ...

local moduleName = "MovementAlert"
local MovementAlert = XerionUIFeatures:GetModule(moduleName)

-- What the two options files draw their lists from: the ability lists named,
-- coloured and ordered for display. Nothing here is read at runtime, and the game
-- data behind it never changes, so it is built once on first use.
local classes

local function getClasses()
    if classes then
        return classes
    end

    classes = {}

    for classId = 1, GetNumClasses() do
        local classInfo = C_CreatureInfo.GetClassInfo(classId)

        if classInfo then
            local color = C_ClassColor.GetClassColor(classInfo.classFile)
            local specs = {}

            if XerionUIFeatures.isForever then
                if MovementAlert.movementAbilitiesBySpec[classInfo.classFile] then
                    specs[1] = {specId = classInfo.classFile, specName = "Abilities"}
                end
            else
                for specIndex = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classId) do
                    local specId, specName = GetSpecializationInfoForClassID(classId, specIndex)

                    if specId and MovementAlert.movementAbilitiesBySpec[specId] then
                        specs[#specs + 1] = {specId = specId, specName = specName}
                    end
                end
            end

            classes[#classes + 1] = {
                classFile = classInfo.classFile,
                className = classInfo.className,
                colorString = color and color:GenerateHexColorMarkup() or "",
                specs = specs,
                timeSpiralSpells = MovementAlert.timeSpiralAbilities[classInfo.classFile] or {},
            }
        end
    end

    table.sort(classes, function(a, b)
        return a.className < b.className
    end)

    return classes
end

local function spellItems(spellIds)
    local items = {}

    for index, spellId in ipairs(spellIds) do
        local spellInfo = C_Spell.GetSpellInfo(spellId)

        items[index] = {
            key = spellId,
            label = spellInfo and spellInfo.name or tostring(spellId),
            icon = C_Spell.GetSpellTexture(spellId),
        }
    end

    return items
end

function MovementAlert:GetTrackedSpecs()
    if not self.trackedSpecs then
        self.trackedSpecs = {}

        for _, class in ipairs(getClasses()) do
            if #class.specs > 0 then
                self.trackedSpecs[#self.trackedSpecs + 1] = class
            end
        end
    end

    return self.trackedSpecs
end

function MovementAlert:GetTimeSpiralClasses()
    if not self.timeSpiralClasses then
        self.timeSpiralClasses = {}

        for _, class in ipairs(getClasses()) do
            if #class.timeSpiralSpells > 0 then
                self.timeSpiralClasses[#self.timeSpiralClasses + 1] = class
            end
        end
    end

    return self.timeSpiralClasses
end

function MovementAlert:GetTrackedSpellItems(specId)
    local spellIds = self:GetMovementSpellChoices(specId)

    if not spellIds then
        return nil
    end

    return spellItems(spellIds)
end

function MovementAlert:GetTimeSpiralSpellItems(class)
    return spellItems(class.timeSpiralSpells)
end

-- The write side of both filters. Their readers stay in init.lua, where the alert
-- itself asks the same questions every update.
function MovementAlert:SetSpellTracked(specId, spellId, tracked)
    if not specId then
        return
    end

    self.db.trackedSpells[specId] = self.db.trackedSpells[specId] or {}
    self.db.trackedSpells[specId][spellId] = tracked and true or false

    if self.frame then
        self.frame:CacheMovementId()
    end
end

function MovementAlert:SetTimeSpiralSpellTracked(spellId, tracked)
    self.db.timeSpiralSpells[spellId] = tracked and true or false
end
