local addonName, XerionUIFeatures = ...

local moduleName = "DefensiveIndicator"
local DefensiveIndicator = XerionUIFeatures:GetModule(moduleName)

-- The labels and orders the dropdowns are built from. Only the options read these; the
-- values they key off live in init.lua, because those are what the display runs on.
DefensiveIndicator.DisplaySettings = {
    CIRCLE = "Circle",
    BAR = "Bar",
    NONE = "Text only",
}

DefensiveIndicator.DisplayOrder = {"CIRCLE", "BAR", "NONE"}

local thinRing = "Interface\\AddOns\\XerionUI-Plugin\\Media\\textures\\ItruliaCircleThin.tga"
local mediumRing = "Interface\\AddOns\\XerionUI-Plugin\\Media\\textures\\ItruliaCircleMedium.tga"
local thickRing = "Interface\\AddOns\\XerionUI-Plugin\\Media\\textures\\ItruliaCircleThick.tga"

DefensiveIndicator.RingTextures = {
    [thinRing] = "Thin",
    [mediumRing] = "Medium",
    [thickRing] = "Thick",
}

-- Thinnest first, rather than the alphabetical order a dropdown falls back to.
DefensiveIndicator.RingTextureOrder = {thinRing, mediumRing, thickRing}

DefensiveIndicator.CategorySettings = {
    MASSIVE = "Massive",
    MAJOR = "Major",
    MINOR = "Minor",
    EXTERNAL = "External",
}

DefensiveIndicator.CategoryOrder = {"MASSIVE", "MAJOR", "MINOR"}

-- The ids this class can put on itself, in the order the options list them. Externals
-- ignore the class entirely: every class is offered the same list.
function DefensiveIndicator:GetClassAuras(classFile, category)
    local entries = category == self.categoryExternal
        and self.externalAuras
        or self.defensiveAuras[classFile]

    local spellIds = {}

    for _, entry in ipairs(entries or {}) do
        if self:GetAuraCategory(entry.auraId) == category then
            spellIds[#spellIds + 1] = entry.auraId
        end
    end

    return spellIds
end

-- What the two options files draw their lists from: every class that has anything to
-- list, named and coloured, with its defensives split into the tiers the options show
-- as columns. Nothing here is read at runtime, and the game data behind it never
-- changes, so it is built once on first use.
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
            local categories = {}
            local total = 0

            for _, category in ipairs(DefensiveIndicator.CategoryOrder) do
                categories[category] = DefensiveIndicator:GetClassAuras(classInfo.classFile, category) or {}
                total = total + #categories[category]
            end

            categories[DefensiveIndicator.categoryExternal] = DefensiveIndicator:GetClassAuras(classInfo.classFile, DefensiveIndicator.categoryExternal) or {}
            total = total + #categories[DefensiveIndicator.categoryExternal]

            if total > 0 then
                classes[#classes + 1] = {
                    classFile = classInfo.classFile,
                    className = classInfo.className,
                    colorString = color and color:GenerateHexColorMarkup() or "",
                    categories = categories,
                }
            end
        end
    end

    table.sort(classes, function(a, b)
        return a.className < b.className
    end)

    return classes
end

function DefensiveIndicator:GetDefensiveClasses()
    return getClasses()
end

-- The four columns a class is listed in, external last since it is the one that is
-- not filtered by what you play.
function DefensiveIndicator:GetColumnCategories()
    local columns = {}

    for _, category in ipairs(self.CategoryOrder) do
        columns[#columns + 1] = category
    end

    columns[#columns + 1] = self.categoryExternal

    return columns
end

function DefensiveIndicator:GetAuraItems(spellIds)
    local items = {}

    for index, spellId in ipairs(spellIds or {}) do
        local spellInfo = C_Spell.GetSpellInfo(spellId)

        items[index] = {
            key = spellId,
            label = spellInfo and spellInfo.name or tostring(spellId),
            icon = C_Spell.GetSpellTexture(spellId),
        }
    end

    return items
end

-- The write side of the filter. Its reader stays in init.lua, where the indicator
-- asks the same question every time the player's auras change.
function DefensiveIndicator:SetAuraTracked(spellId, tracked)
    self.db.trackedAuras[spellId] = tracked and true or false
    self.trackedAuras = nil
end
