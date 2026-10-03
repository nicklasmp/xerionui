local addonName, XerionUIFeatures = ...
local moduleName = "DefensiveIndicator"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local DefensiveIndicator = XerionUIFeatures:NewModule(moduleName)

DefensiveIndicator.displayCircle = "CIRCLE"
DefensiveIndicator.displayBar = "BAR"
DefensiveIndicator.displayNone = "NONE"

DefensiveIndicator.categoryMassive = "MASSIVE"
DefensiveIndicator.categoryMajor = "MAJOR"
DefensiveIndicator.categoryMinor = "MINOR"
DefensiveIndicator.categoryExternal = "EXTERNAL"

DefensiveIndicator.defensiveAuras = {
    DEATHKNIGHT = {
        {auraId = 48707}, -- Anti-Magic Shell
        {auraId = 444741, spellId = 48707}, -- Anti-Magic Shell, the Horsemen's cast on you
        {auraId = 48792, category = "MASSIVE"}, -- Icebound Fortitude
        {auraId = 49039, category = "MINOR", defaultOff = true}, -- Lichborne
        {auraId = 55233}, -- Vampiric Blood
        {auraId = 101568, spellId = 178819, category = "MINOR"}, -- Dark Succor
    },
    DEMONHUNTER = {
        {auraId = 442715, spellId = 442714, category = "MINOR", defaultOff = true}, -- Blade Ward
        {auraId = 212800}, -- Blur
        {auraId = 1266616, spellId = 1266329, category = "MINOR", defaultOff = true}, -- Demon Muzzle
        {auraId = 394933, spellId = 388111, category = "MINOR", defaultOff = true}, -- Demon Muzzle
        {auraId = 427912, spellId = 258920, category = "MINOR", defaultOff = true}, -- Immolation Aura
        {auraId = 258920, category = "MINOR", defaultOff = true}, -- Immolation Aura
        {auraId = 187827, category = "MASSIVE"}, -- Metamorphosis
        {auraId = 207771}, -- Fiery Brand
        {auraId = 209426, spellId = 196718, defaultOff = true}, -- Darkness
    },
    DRUID = {
        {auraId = 22812}, -- Barkskin
        {auraId = 22842, category = "MINOR"}, -- Frenzied Regeneration
        {auraId = 192081, category = "MINOR", defaultOff = true}, -- Ironfur
        {auraId = 61336, category = "MASSIVE"}, -- Survival Instincts
        {auraId = 393903, spellId = 377842, category = "MINOR", defaultOff = true}, -- Ursine Vigor
        {auraId = 1261872, spellId = 1261867, category = "MINOR"}, -- Heart of the Wild
    },
    EVOKER = {
        {auraId = 404381, spellId = 404195, category = "MASSIVE"}, -- Defy Fate
        {auraId = 363916}, -- Obsidian Scales
        {auraId = 374349}, -- Renewing Blaze
    },
    HUNTER = {
        {auraId = 186265, category = "MASSIVE"}, -- Aspect of the Turtle
        {auraId = 472708, spellId = 472707, category = "MINOR", defaultOff = true}, -- Shell Cover
        {auraId = 264735}, -- Survival of the Fittest
    },
    MAGE = {
        {auraId = 342246, spellId = 342245, category = "MINOR"}, -- Alter Time
        {auraId = 235313, category = "MINOR", defaultOff = true}, -- Blazing Barrier
        {auraId = 11426, category = "MINOR", defaultOff = true}, -- Ice Barrier
        {auraId = 45438, category = "MASSIVE"}, -- Ice Block
        {auraId = 414658, spellId = 45438, category = "MASSIVE"}, -- Ice Cold
        {auraId = 235450, category = "MINOR", defaultOff = true}, -- Prismatic Barrier
        {auraId = 449336, spellId = 449330}, -- Merely a Setback
        {auraId = 1309793, spellId = 1309497, category = "MINOR"}, -- Amplified Refraction
    },
    MONK = {
        {auraId = 122783}, -- Diffuse Magic
        {auraId = 115203, category = "MASSIVE"}, -- Fortifying Brew
        {auraId = 120954, spellId = 115203, category = "MASSIVE"}, -- Fortifying Brew
        {auraId = 125174, spellId = 122470}, -- Touch of Karma
        {auraId = 132578}, -- Invoke Niuzao, the Black Ox
        {auraId = 322507, category = "MINOR"}, -- Celestial Brew
        {auraId = 432180, spellId = 432181, category = "MINOR", defaultOff = true}, -- Dance of the Wind
        {auraId = 1241059, category = "MINOR"}, -- Celestial Infusion
    },
    PALADIN = {
        {auraId = 498, category = "MINOR"}, -- Divine Protection
        {auraId = 403876, category = "MINOR"}, -- Divine Protection
        {auraId = 642, category = "MASSIVE"}, -- Divine Shield
        {auraId = 184662, category = "MINOR", defaultOff = true}, -- Shield of Vengeance
        {auraId = 31850, category = "MASSIVE"}, -- Ardent Defender
        {auraId = 86659}, -- Guardian of Ancient Kings
    },
    PRIEST = {
        {auraId = 114216, spellId = 108945, category = "MINOR", defaultOff = true}, -- Angelic Bulwark
        {auraId = 114214, spellId = 108945, category = "MINOR", defaultOff = true}, -- Angelic Bulwark
        {auraId = 19236, category = "MINOR"}, -- Desperate Prayer
        {auraId = 47585, category = "MASSIVE"}, -- Dispersion
        {auraId = 586, category = "MINOR"}, -- Fade
        {auraId = 45242, spellId = 45243, category = "MINOR", defaultOff = true}, -- Focused Will
        {auraId = 426401, spellId = 45243, category = "MINOR", defaultOff = true}, -- Focused Will
        {auraId = 193065, spellId = 193063, category = "MINOR"}, -- Protective Light
        {auraId = 27827, spellId = 20711, category = "MASSIVE"}, -- Spirit of Redemption
    },
    ROGUE = {
        {auraId = 31224, category = "MASSIVE"}, -- Cloak of Shadows
        {auraId = 5277}, -- Evasion
        {auraId = 1966, category = "MINOR"}, -- Feint
        {auraId = 185311, category = "MINOR"}, -- Crimson Vial
    },
    SHAMAN = {
        {auraId = 108271}, -- Astral Shift
        {auraId = 260881, spellId = 260878, category = "MINOR"}, -- Spirit Wolf
    },
    WARLOCK = {
        {auraId = 108416}, -- Dark Pact
        {auraId = 104773}, -- Unending Resolve
        {auraId = 132413, spellId = 108503, category = "MINOR"}, -- Shadow Bulwark
        {auraId = 387636, spellId = 385899, category = "MINOR"}, -- Soulburn: Healthstone
        {auraId = 389614, spellId = 389609, category = "MINOR"}, -- Abyss Walker
    },
    WARRIOR = {
        {auraId = 118038}, -- Die by the Sword
        {auraId = 184364}, -- Enraged Regeneration
        {auraId = 190456, category = "MINOR"}, -- Ignore Pain
        {auraId = 1277297, spellId = 190456, category = "MINOR"}, -- Ignore Pain
        {auraId = 147833, spellId = 3411, category = "MINOR"}, -- Intervene
        {auraId = 23920, category = "MINOR"}, -- Spell Reflection
        {auraId = 385391, spellId = 23920, category = "MINOR"}, -- Spell Reflection
        {auraId = 871, category = "MASSIVE"}, -- Shield Wall
        {auraId = 202147, spellId = 29838, category = "MINOR", defaultOff = true}, -- Second Wind
    },
}

DefensiveIndicator.externalAuras = {
    -- Druid
    {auraId = 102342}, -- Ironbark
    -- Evoker
    {auraId = 357170}, -- Time Dilation
    -- Hunter
    {auraId = 53480}, -- Roar of Sacrifice
    -- Monk
    {auraId = 116849}, -- Life Cocoon
    -- Paladin
    {auraId = 1022}, -- Blessing of Protection
    {auraId = 1309794}, -- Blessing of Protection
    {auraId = 6940}, -- Blessing of Sacrifice
    {auraId = 204018}, -- Blessing of Spellwarding
    -- Priest
    {auraId = 47788}, -- Guardian Spirit
    {auraId = 33206}, -- Pain Suppression
}

if XerionUIFeatures.isForever then
    DefensiveIndicator.defensiveAuras = {
        DRUID = {
            {auraId = 22812}, -- Barkskin
            {auraId = 22842, category = "MINOR"}, -- Frenzied Regeneration
        },
        HUNTER = {
            {auraId = 19263}, -- Deterrence
            {auraId = 5384, category = "MINOR", defaultOff = true}, -- Feign Death
        },
        MAGE = {
            {auraId = 11958, category = "MASSIVE"}, -- Ice Block
            {auraId = 11426, ranks = {13031, 13032, 13033}, category = "MINOR"}, -- Ice Barrier
            {auraId = 1463, ranks = {8494, 8495, 10191, 10192, 10193}, category = "MINOR", defaultOff = true}, -- Mana Shield
            {auraId = 6143, ranks = {8461, 8462, 10177}, category = "MINOR", defaultOff = true}, -- Frost Ward
            {auraId = 543, ranks = {8457, 8458, 10223, 10225}, category = "MINOR", defaultOff = true}, -- Fire Ward
        },
        PALADIN = {
            {auraId = 498, ranks = {5573}, category = "MASSIVE"}, -- Divine Protection
            {auraId = 642, ranks = {1020}, category = "MASSIVE"}, -- Divine Shield
            {auraId = 20925, ranks = {20927, 20928}, category = "MINOR", defaultOff = true}, -- Holy Shield
        },
        PRIEST = {
            {auraId = 17, ranks = {592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901}, category = "MINOR"}, -- Power Word: Shield
            {auraId = 586, ranks = {9578, 9579, 9592, 10941, 10942}, category = "MINOR"}, -- Fade
            {auraId = 27827, spellId = 20711, category = "MASSIVE"}, -- Spirit of Redemption
        },
        ROGUE = {
            {auraId = 5277}, -- Evasion
            {auraId = 11327, spellId = 1856, ranks = {11329}, category = "MINOR", defaultOff = true}, -- Vanish
        },
        WARLOCK = {
            {auraId = 7812, spellId = 697, ranks = {19438, 19440, 19441, 19442, 19443}}, -- Sacrifice, cast by the Voidwalker
            {auraId = 6229, ranks = {11739, 11740}, category = "MINOR", defaultOff = true}, -- Shadow Ward
            {auraId = 25228, spellId = 19028, category = "MINOR", defaultOff = true}, -- Soul Link
        },
        WARRIOR = {
            {auraId = 871, category = "MASSIVE"}, -- Shield Wall
            {auraId = 12976, spellId = 12975}, -- Last Stand
            {auraId = 2565, category = "MINOR", defaultOff = true}, -- Shield Block
            {auraId = 18499, category = "MINOR", defaultOff = true}, -- Berserker Rage
        },
    }

    DefensiveIndicator.externalAuras = {
        -- Paladin
        {auraId = 1022, ranks = {5599, 10278}}, -- Blessing of Protection
        {auraId = 6940, ranks = {20729}}, -- Blessing of Sacrifice
    }
end

DefensiveIndicator.defensiveAurasBySpell = {}
DefensiveIndicator.auraCategories = {}
DefensiveIndicator.rankBase = {}

local function registerAura(entry, category)
    DefensiveIndicator.auraCategories[entry.auraId] = category
    DefensiveIndicator.defensiveAurasBySpell[entry.auraId] = not entry.defaultOff

    for _, rankId in ipairs(entry.ranks or {}) do
        DefensiveIndicator.auraCategories[rankId] = category
        DefensiveIndicator.rankBase[rankId] = entry.auraId
    end
end

for _, entries in pairs(DefensiveIndicator.defensiveAuras) do
    for _, entry in ipairs(entries) do
        registerAura(entry, entry.category or DefensiveIndicator.categoryMajor)
    end
end

for _, entry in ipairs(DefensiveIndicator.externalAuras) do
    registerAura(entry, DefensiveIndicator.categoryExternal)
end

function DefensiveIndicator:GetAuraCategory(spellId)
    return self.auraCategories[spellId] or self.categoryMajor
end

function DefensiveIndicator:GetColor(category)
    return self.db.colors[category] or self.db.colors[self.categoryMajor]
end

function DefensiveIndicator:IsAuraTracked(spellId)
    spellId = self.rankBase[spellId] or spellId

    local tracked = self.db.trackedAuras[spellId]

    if tracked == nil then
        return self.defensiveAurasBySpell[spellId] or false
    end

    return tracked
end

function DefensiveIndicator:CacheKnownAuras()
    local known = {}
    local changed = not self.knownAuras
    local previous = self.knownAuras or {}

    for _, entry in ipairs(self.defensiveAuras[XerionUIFeatures.playerClass] or {}) do
        if XerionUIFeatures:IsSpellKnown(entry.spellId or entry.auraId) then
            known[entry.auraId] = true

            if not previous[entry.auraId] then
                changed = true
            end
        elseif previous[entry.auraId] then
            changed = true
        end
    end

    self.knownAuras = known

    return changed
end

function DefensiveIndicator:IsAuraKnown(spellId)
    if self:GetAuraCategory(spellId) == self.categoryExternal then
        return true
    end

    if not self.knownAuras then
        self:CacheKnownAuras()
    end

    return self.knownAuras[self.rankBase[spellId] or spellId] or false
end

function DefensiveIndicator:UpdateKnownAuras()
    if not self:CacheKnownAuras() then
        return
    end

    self.trackedAuras = nil
    self:UpdateContainerFilters()
end

function DefensiveIndicator:CacheTrackedAuras()
    local tracked = {}

    local function add(entries)
        for _, entry in ipairs(entries or {}) do
            if self:IsAuraTracked(entry.auraId) and self:IsAuraKnown(entry.auraId) then
                tracked[#tracked + 1] = entry.auraId

                for _, rankId in ipairs(entry.ranks or {}) do
                    tracked[#tracked + 1] = rankId
                end
            end
        end
    end

    add(self.defensiveAuras[XerionUIFeatures.playerClass])
    add(self.externalAuras)

    self.trackedAuras = tracked
end

function DefensiveIndicator:GetTrackedAuras()
    if not self.trackedAuras then
        self:CacheTrackedAuras()
    end

    return self.trackedAuras
end

function DefensiveIndicator:GetSampleSpell()
    local tracked = self:GetTrackedAuras()

    if tracked[1] then
        return tracked[1]
    end

    local entries = self.defensiveAuras[XerionUIFeatures.playerClass]

    return entries and entries[1] and entries[1].auraId or 871
end

local function createArcPart(parent)
    local part = CreateFrame("frame", nil, parent)

    part.base = part:CreateTexture(nil, "BACKGROUND", nil, -8)
    part.base:SetAllPoints()

    part.track = part:CreateTexture(nil, "BACKGROUND")
    part.track:SetAllPoints()

    part.swipe = CreateFrame("Cooldown", nil, part, "CooldownFrameTemplate")
    part.swipe:SetAllPoints()
    part.swipe:SetDrawBling(false)
    part.swipe:SetDrawEdge(false)
    part.swipe:SetReverse(false)
    part.swipe:SetHideCountdownNumbers(true)

    return part
end

local function stylePart(part)
    local background = DefensiveIndicator.db.backgroundColor
    local texture = DefensiveIndicator.db.ringTexture
    local showRing = DefensiveIndicator.db.display == DefensiveIndicator.displayCircle

    part.base:SetTexture(texture)
    part.base:SetVertexColor(0, 0, 0, 1)
    part.base:SetShown(showRing)

    part.track:SetTexture(texture)
    part.track:SetVertexColor(background.r, background.g, background.b, background.a)
    part.track:SetShown(showRing)

    part.swipe:SetSwipeTexture(texture)

    if part.swipe.SetDrawSwipe then
        part.swipe:SetDrawSwipe(showRing)
    end
end

function DefensiveIndicator:CreateRing(parent)
    local ring = CreateFrame("frame", nil, parent)

    ring.full = createArcPart(ring)
    ring.full:SetAllPoints()

    ring.parts = {ring.full}

    ring.bar = CreateFrame("StatusBar", nil, ring)
    ring.bar:SetAllPoints()
    ring.bar:SetOrientation("HORIZONTAL")
    ring.bar:SetMinMaxValues(0, 1)

    ring.barBase = ring.bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    ring.barBase:SetAllPoints()
    ring.barBase:SetColorTexture(0, 0, 0, 1)

    ring.barBackground = ring.bar:CreateTexture(nil, "BACKGROUND")
    ring.barBackground:SetAllPoints()

    ring.barBorder = XerionUIFeatures:CreateBorder(ring.bar, nil, nil, nil, nil, true)

    return ring
end

function DefensiveIndicator:GetDisplaySize()
    if self.db.display == self.displayBar then
        return self.db.barWidth, self.db.barHeight
    end

    return self.db.size, self.db.size
end

function DefensiveIndicator:GetTextOffsets()
    local offset = self.db.textOffset

    if self.db.showName and self.db.showDuration then
        local gap = (self.db.font.fontSize + 2) / 2

        return offset.y + gap, offset.y - gap
    end

    return offset.y, offset.y
end

function DefensiveIndicator:StyleText(text, offsetY)
    local font = self.db.font

    text:ClearAllPoints()
    PixelUtil.SetPoint(text, "CENTER", self.frame, "CENTER", self.db.textOffset.x, offsetY)
    text:SetJustifyH(font.justifyH or "CENTER")
    text:SetTextColor(self.db.textColor.r, self.db.textColor.g, self.db.textColor.b, self.db.textColor.a)

    if font.fontOutline ~= "OUTLINESLUG" then
        text:SetShadowColor(font.fontShadowColor.r, font.fontShadowColor.g, font.fontShadowColor.b, font.fontShadowColor.a)
        text:SetShadowOffset(font.fontShadowXOffset, font.fontShadowYOffset)
    else
        text:SetShadowColor(0, 0, 0, 0)
        text:SetShadowOffset(0, 0)
    end

    text:SetFont(LSM:Fetch("font", font.fontFamily), font.fontSize, font.fontOutline)
end

function DefensiveIndicator:StyleRing(ring)
    local barTexture = LSM:Fetch("statusbar", self.db.barTexture)

    PixelUtil.SetSize(ring, self:GetDisplaySize())

    ring.full:SetShown(self.db.display == self.displayCircle)
    ring.bar:SetShown(self.db.display == self.displayBar)

    for _, part in ipairs(ring.parts) do
        stylePart(part)
    end

    ring.bar:SetStatusBarTexture(barTexture)
    ring.barBackground:SetTexture(barTexture)
end

function DefensiveIndicator:ColorRing(ring, category)
    local color = self:GetColor(category)

    for _, part in ipairs(ring.parts) do
        part.swipe:SetSwipeColor(color.r, color.g, color.b, color.a)
    end

    ring.bar:SetStatusBarColor(color.r, color.g, color.b, color.a)
    ring.barBackground:SetVertexColor(color.r * 0.25, color.g * 0.25, color.b * 0.25, 0.9)
end

function DefensiveIndicator:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, -140)
    PixelUtil.SetSize(frame, 46, 46)

    frame.display = CreateFrame("frame", "$parent_Display", frame)
    frame.display:SetAllPoints()
    frame.display:Hide()

    frame.ring = DefensiveIndicator:CreateRing(frame.display)
    frame.ring:SetPoint("CENTER", frame.display, "CENTER")

    frame.text = frame.display:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 12, "OUTLINE")
    frame.text:SetJustifyH("CENTER")

    function frame:ApplyTimer()
        if not self.showing then
            return
        end

        self.ring.full.swipe:SetCooldown(self.startTime, self.duration)
        self.ring.bar:SetValue(1)
    end

    function frame:UpdateText()
        if not self.showing then
            return
        end

        local text = ""

        if DefensiveIndicator.db.showName and self.spellName then
            text = self.spellName
        end

        if DefensiveIndicator.db.showDuration then
            local remaining = self.startTime + self.duration - GetTime()

            if text ~= "" then
                text = text .. "\n"
            end

            text = text .. string.format("%." .. DefensiveIndicator.db.precision .. "f", remaining)
        end

        self.text:SetText(text)
    end

    function frame:ApplyColors()
        DefensiveIndicator:ColorRing(self.ring, self.category)
    end

    function frame:ShowAura(spellId, startTime, duration, isSample)
        local spellInfo = spellId and C_Spell.GetSpellInfo(spellId)

        self.showing = true
        self.spellId = spellId
        self.spellName = spellInfo and spellInfo.name
        self.category = spellId and DefensiveIndicator:GetAuraCategory(spellId)
        self.startTime = startTime
        self.duration = duration
        self.isSample = isSample

        self:ApplyColors()
        self:ApplyTimer()
        self:UpdateText()
        self.display:Show()
    end

    function frame:HideAura()
        self.showing = nil
        self.spellId = nil
        self.category = nil
        self.isSample = nil
        self.display:Hide()
    end

    function frame:ShowSample()
        self:ShowAura(DefensiveIndicator:GetSampleSpell(), GetTime(), 8, true)
    end

    function frame:Tick(elapsed)
        if not self.timeSinceLastUpdate then
            self.timeSinceLastUpdate = 0
        end

        self.timeSinceLastUpdate = self.timeSinceLastUpdate + elapsed

        if self.timeSinceLastUpdate < DefensiveIndicator.db.updateInterval then
            return
        end

        self.timeSinceLastUpdate = 0
        DefensiveIndicator:UpdateCarriedState()

        if not self.showing then
            return
        end

        local remaining = self.startTime + self.duration - GetTime()

        if remaining <= 0 then
            if self.isSample then
                self:ShowSample()
            else
                self:HideAura()
            end

            return
        end

        self.ring.bar:SetValue(remaining / self.duration)
        self:UpdateText()
    end

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, DefensiveIndicator.db.point.point, self:GetParent() or UIParent, DefensiveIndicator.db.point.point, DefensiveIndicator.db.point.x, DefensiveIndicator.db.point.y)
        end

        PixelUtil.SetSize(self, DefensiveIndicator:GetDisplaySize())
        self:SetFrameStrata(DefensiveIndicator.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(DefensiveIndicator.db.font.frameLevel or 1)

        DefensiveIndicator:StyleRing(self.ring)
        self:ApplyColors()

        self.text:SetShown(DefensiveIndicator.db.showName or DefensiveIndicator.db.showDuration)
        self.text:ClearAllPoints()
        PixelUtil.SetPoint(self.text, "CENTER", self, "CENTER", DefensiveIndicator.db.textOffset.x, DefensiveIndicator.db.textOffset.y)
        self.text:SetJustifyH(DefensiveIndicator.db.font.justifyH or "CENTER")
        self.text:SetTextColor(DefensiveIndicator.db.textColor.r, DefensiveIndicator.db.textColor.g, DefensiveIndicator.db.textColor.b, DefensiveIndicator.db.textColor.a)

        if DefensiveIndicator.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(DefensiveIndicator.db.font.fontShadowColor.r, DefensiveIndicator.db.font.fontShadowColor.g, DefensiveIndicator.db.font.fontShadowColor.b, DefensiveIndicator.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(DefensiveIndicator.db.font.fontShadowXOffset, DefensiveIndicator.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", DefensiveIndicator.db.font.fontFamily), DefensiveIndicator.db.font.fontSize, DefensiveIndicator.db.font.fontOutline)

        self:ApplyTimer()
        self:UpdateText()

        DefensiveIndicator:RestyleRings()
    end

    return frame
end

local spellEvents = {
    SPELLS_CHANGED = true,
    PLAYER_TALENT_UPDATE = true,
    TRAIT_CONFIG_UPDATED = true,
}

local function OnEvent(self, event)
    if spellEvents[event] then
        DefensiveIndicator:UpdateKnownAuras()

        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if DefensiveIndicator.restyleDenied then
            DefensiveIndicator:RestyleRings()
        end

        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        DefensiveIndicator:UpdateKnownAuras()
    end

    DefensiveIndicator:UpdateCarriedState()

    if XerionUIFeatures.testMode then
        if not self.isSample then
            self:ShowSample()
        end

        return
    end

    self:HideAura()
end

function DefensiveIndicator:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent("PLAYER_TALENT_UPDATE")
    frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_CONTROL_LOST")
    frame:RegisterEvent("PLAYER_CONTROL_GAINED")
    frame:RegisterUnitEvent("UNIT_ENTERING_VEHICLE", "player")
    frame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    frame:RegisterUnitEvent("UNIT_EXITING_VEHICLE", "player")
    frame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")

    if E then
        E:CreateMover(frame, frame:GetName() .. "Mover", moduleName, nil,
            nil,
            nil,
            "ALL,ITRULIA",
            function()
                return self.db.enabled
            end,
            addonName .. "," .. moduleName
        )
    elseif XerionUIFeatures.EUI then
        XerionUIFeatures:CreateEUIMover(self, frame, moduleName)
    else
        LEM:AddFrame(frame, function(_, layoutName, point, x, y)
            self.db.point = {point = point, x = x, y = y}
        end, self:GetDefaults().point)
    end

    return frame
end

function DefensiveIndicator:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile[moduleName] = profile[moduleName] or self:GetDefaults()
    self.db = profile[moduleName]
end

function DefensiveIndicator:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile[moduleName] = profile[moduleName] or self:GetDefaults()
    self.db = profile[moduleName]

    self.trackedAuras = nil
    self.knownAuras = nil

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:UpdateStyles()
        frame:SetScript("OnEvent", OnEvent)
        frame:SetScript("OnUpdate", frame.Tick)

        self:EnsureContainers()
        self:UpdateContainerFilters()
        self:RestyleRings()
        self.carried = nil
        self:UpdateCarriedState()

        OnEvent(frame)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame:HideAura()
        self:SetContainersShown(false)
    end
end

function DefensiveIndicator:ApplyFontSettings(font)
    self.db.font.fontFamily = font.fontFamily
    self.db.font.fontOutline = font.fontOutline
    self.db.font.fontShadowColor = font.fontShadowColor
    self.db.font.fontShadowXOffset = font.fontShadowXOffset
    self.db.font.fontShadowYOffset = font.fontShadowYOffset
    self.db.font.justifyH = font.justifyH

    if self.frame then
        self.frame:UpdateStyles()
    end
end

function DefensiveIndicator:OnEnable()
    self:RefreshConfig()
end

function DefensiveIndicator:UpdateVisibility()
    if not self.db.enabled or not self.frame then
        return
    end

    self:UpdateContainerFilters()
    OnEvent(self.frame)
end

function DefensiveIndicator:ToggleTestMode()
    self:UpdateVisibility()
end

function DefensiveIndicator:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
