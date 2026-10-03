local addonName, XerionUIFeatures = ...
local moduleName = "SelfDispelAlert"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local SelfDispelAlert = XerionUIFeatures:NewModule(moduleName)

local iconGap = 4

local fallbackSpellId = 20594 -- Stoneform, for characters with no self dispel

local racialTypes = {Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true}

-- Ordered: class dispels first, spec versions before base ones, the dwarf racials last.
-- Each type resolves to the first known source covering it.
SelfDispelAlert.sources = {
    {sourceKey = "DRUID", spellId = 88423, types = {Magic = true, Curse = true, Poison = true}}, -- Nature's Cure
    {sourceKey = "DRUID", spellId = 2782, types = {Curse = true, Poison = true}}, -- Remove Corruption
    {sourceKey = "EVOKER", spellId = 374251, types = {Bleed = true, Curse = true, Disease = true, Poison = true}}, -- Cauterizing Flame
    {sourceKey = "EVOKER", spellId = 360823, types = {Magic = true, Poison = true}}, -- Naturalize
    {sourceKey = "EVOKER", spellId = 365585, types = {Poison = true}}, -- Expunge
    {sourceKey = "HUNTER", spellId = 5384, talentSpellId = 459517, types = {Poison = true, Disease = true}}, -- Feign Death via Emergency Salve
    {sourceKey = "MAGE", spellId = 475, types = {Curse = true}}, -- Remove Curse
    {sourceKey = "MONK", spellId = 115450, types = {Magic = true, Poison = true, Disease = true}}, -- Detox (Mistweaver)
    {sourceKey = "MONK", spellId = 218164, types = {Poison = true, Disease = true}}, -- Detox
    {sourceKey = "PALADIN", spellId = 4987, types = {Magic = true, Poison = true, Disease = true}}, -- Cleanse
    {sourceKey = "PALADIN", spellId = 213644, types = {Poison = true, Disease = true}}, -- Cleanse Toxins
    {sourceKey = "PRIEST", spellId = 527, types = {Magic = true, Disease = true}}, -- Purify
    {sourceKey = "PRIEST", spellId = 213634, types = {Disease = true}}, -- Purify Disease
    {sourceKey = "SHAMAN", spellId = 77130, types = {Magic = true, Curse = true}}, -- Purify Spirit
    {sourceKey = "SHAMAN", spellId = 51886, types = {Curse = true}}, -- Cleanse Spirit
    {sourceKey = "RACIAL", spellId = 20594, types = racialTypes}, -- Stoneform
    {sourceKey = "RACIAL", spellId = 265221, types = racialTypes}, -- Fireblood
}

-- The harmful dispel types, enrage being buff only.
SelfDispelAlert.dispelTypes = {
    "Magic",
    "Curse",
    "Disease",
    "Poison",
    "Bleed",
}

-- Layout is measured from a parked font string: the live alerts hang off engine aura
-- buttons and refuse reads while auras are secret, and an object that took a secret
-- refuses GetStringWidth afterwards.
local measurePool = CreateFrame("frame")
measurePool:Hide()

local measureText = measurePool:CreateFontString(nil, "BACKGROUND")
measureText:SetPoint("CENTER")

function SelfDispelAlert:IsSourceEnabled(key)
    local enabled = self.db.enabledSources[key]

    if enabled == nil then
        return true
    end

    return enabled
end

-- Cached because the spellbook is not necessarily readable at login; the spell events
-- and the options refill it. The signature is what change detection compares, so a
-- restyle only happens when a type actually changed hands.
function SelfDispelAlert:ResolveTypeSources()
    local map = {}
    local primary = nil

    for _, source in ipairs(self.sources) do
        if self:IsSourceEnabled(source.sourceKey)
            and (not source.talentSpellId or XerionUIFeatures:IsSpellKnown(source.talentSpellId))
            and XerionUIFeatures:IsSpellKnown(source.spellId)
        then
            for _, token in ipairs(self.dispelTypes) do
                if source.types[token] and not map[token] then
                    map[token] = source
                    primary = primary or source
                end
            end
        end
    end

    self.typeSources = map
    self.primarySource = primary

    local parts = {}

    for _, token in ipairs(self.dispelTypes) do
        local source = map[token]
        parts[#parts + 1] = token .. "=" .. (source and source.spellId or 0)
    end

    self.sourceSignature = table.concat(parts, ",")
end

function SelfDispelAlert:GetSourceForDisplay(display)
    local token = display and display.dispelType
    local source = token and self.typeSources and self.typeSources[token]

    return source or self.primarySource
end

function SelfDispelAlert:GetDisplaySpellId(display)
    local source = self:GetSourceForDisplay(display)

    return source and source.spellId or fallbackSpellId
end

function SelfDispelAlert:GetDisplayText(display)
    if not self.db.showText then
        return ""
    end

    local text = self.db.displayText

    if text and text ~= "" then
        return text
    end

    local spellInfo = C_Spell.GetSpellInfo(self:GetDisplaySpellId(display))

    return spellInfo and spellInfo.name or ""
end

-- true, false, or nil for unreadable. A rolling GCD counts as ready, or the alert would
-- flicker with the rotation.
function SelfDispelAlert:IsSourceReady(source)
    if not source then
        return nil
    end

    local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, source.spellId)

    if not ok or issecretvalue(cdInfo) or type(cdInfo) ~= "table" then
        return nil
    end

    local remaining = cdInfo.timeUntilEndOfStartRecovery
    local onGCD = cdInfo.isOnGCD

    if issecretvalue(remaining) or issecretvalue(onGCD) or type(remaining) ~= "number" then
        return nil
    end

    return remaining == 0 or onGCD == true
end

-- Not XerionUIFeatures:CreateBorder: that registers events and an OnSizeChanged script, and
-- the live copies are children of engine aura buttons, where scripts never dispatch,
-- event registrations are forbidden, and one throw inside initializeFrame silently
-- kills the engine's whole frame batch.
local function createAlertBorder(parent)
    local border = CreateFrame("frame", nil, parent, "BackdropTemplate")
    PixelUtil.SetPoint(border, "TOPLEFT", parent, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(border, "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

    function border:UpdateSize()
        local edgeSize = PixelUtil.GetNearestPixelSize(1, self:GetEffectiveScale(), 1)

        if self.edgeSize == edgeSize then
            return
        end

        self.edgeSize = edgeSize

        self:SetBackdrop({
            edgeFile = [[Interface\Buttons\WHITE8x8]],
            bgFile = [[Interface\Buttons\WHITE8x8]],
            edgeSize = edgeSize,
        })

        self:SetBackdropBorderColor(0, 0, 0, 1)
        self:SetBackdropColor(0, 0, 0, 0)
    end

    border:UpdateSize()

    return border
end

-- Shared by the preview display and the live copies on engine aura buttons, so nothing
-- in here may register events or scripts.
function SelfDispelAlert:CreateDisplay(parent)
    local display = CreateFrame("frame", nil, parent)
    display:EnableMouse(false)

    display.icon = CreateFrame("frame", nil, display)
    display.icon.texture = display.icon:CreateTexture(nil, "ARTWORK")
    display.icon.texture:SetAllPoints()
    display.icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    display.icon.border = createAlertBorder(display.icon)

    display.text = display:CreateFontString(nil, "OVERLAY")

    return display
end

function SelfDispelAlert:GetDisplaySize(display)
    local font = self.db.font
    local text = self:GetDisplayText(display)
    local showText = text ~= ""
    local textWidth = 0
    local textHeight = 0

    if showText then
        measureText:SetFont(LSM:Fetch("font", font.fontFamily), font.fontSize, font.fontOutline)
        measureText:SetText(text)

        textWidth = measureText:GetStringWidth()
        textHeight = measureText:GetStringHeight()
    end

    local width = 0

    if self.db.showIcon then
        width = self.db.iconSize
    end

    if showText then
        width = width + textWidth

        if self.db.showIcon then
            width = width + iconGap
        end
    end

    local height = math.max(self.db.showIcon and self.db.iconSize or 0, textHeight)

    return math.max(width, 1), math.max(height, 1)
end

function SelfDispelAlert:StyleDisplay(display)
    local font = self.db.font
    local fontFile = LSM:Fetch("font", font.fontFamily)
    local text = self:GetDisplayText(display)
    local showText = text ~= ""
    local showIcon = self.db.showIcon
    local width = self:GetDisplaySize(display)

    display.text:SetFont(fontFile, font.fontSize, font.fontOutline)
    display.text:SetText(text)
    display.text:SetJustifyH(font.justifyH or "CENTER")
    display.text:SetTextColor(self.db.color.r, self.db.color.g, self.db.color.b, self.db.color.a)
    display.text:SetShown(showText)

    if font.fontOutline ~= "OUTLINESLUG" then
        display.text:SetShadowColor(font.fontShadowColor.r, font.fontShadowColor.g, font.fontShadowColor.b, font.fontShadowColor.a)
        display.text:SetShadowOffset(font.fontShadowXOffset, font.fontShadowYOffset)
    else
        display.text:SetShadowColor(0, 0, 0, 0)
        display.text:SetShadowOffset(0, 0)
    end

    display.icon:SetShown(showIcon)
    display.icon.texture:SetTexture(C_Spell.GetSpellTexture(self:GetDisplaySpellId(display)))
    PixelUtil.SetSize(display.icon, self.db.iconSize, self.db.iconSize)

    display.icon.border:SetFrameStrata(display.icon:GetFrameStrata())
    display.icon.border:SetFrameLevel(display.icon:GetFrameLevel() + 2)
    display.icon.border:UpdateSize()

    display.icon:ClearAllPoints()
    display.text:ClearAllPoints()

    if showIcon then
        PixelUtil.SetPoint(display.icon, "LEFT", display, "CENTER", -width / 2, 0)
    end

    if showText and showIcon then
        PixelUtil.SetPoint(display.text, "LEFT", display.icon, "RIGHT", iconGap, 0)
    elseif showText then
        PixelUtil.SetPoint(display.text, "LEFT", display, "CENTER", -width / 2, 0)
    end
end

function SelfDispelAlert:ApplyGates()
    self:ApplyContainerGates()
    self:ApplyShownGate()
end

function SelfDispelAlert:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, -100)
    PixelUtil.SetSize(frame, 28, 28)

    frame.gate = CreateFrame("frame", nil, frame)
    frame.gate:SetAllPoints()

    frame.display = SelfDispelAlert:CreateDisplay(frame.gate)
    frame.display:SetAllPoints(frame.gate)
    frame.display:Hide()

    function frame:UpdateAlert()
        if XerionUIFeatures.testMode then
            self.gate:SetAlpha(1)
            self.display:Show()

            return
        end

        self.display:Hide()
        SelfDispelAlert:ApplyGates()
    end

    function frame:Tick(elapsed)
        self.timeSinceLastUpdate = (self.timeSinceLastUpdate or 0) + elapsed

        if self.timeSinceLastUpdate < SelfDispelAlert.db.updateInterval then
            return
        end

        self.timeSinceLastUpdate = 0
        SelfDispelAlert:ApplyGates()
    end

    function frame:UpdateStyles()
        local font = SelfDispelAlert.db.font

        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, SelfDispelAlert.db.point.point, self:GetParent() or UIParent, SelfDispelAlert.db.point.point, SelfDispelAlert.db.point.x, SelfDispelAlert.db.point.y)
        end

        PixelUtil.SetSize(self, SelfDispelAlert:GetDisplaySize(self.display))
        self:SetFrameStrata(font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(font.frameLevel or 1)

        SelfDispelAlert:StyleDisplay(self.display)
        SelfDispelAlert:RestyleAlerts()
    end

    return frame
end

local function OnEvent(self, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED"
        or event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" then
        local previous = SelfDispelAlert.sourceSignature

        SelfDispelAlert:ResolveTypeSources()

        if SelfDispelAlert.sourceSignature ~= previous then
            self:UpdateStyles()
        end
    end

    if event == "PLAYER_REGEN_ENABLED" and SelfDispelAlert.restyleDenied then
        SelfDispelAlert:RestyleAlerts()
    end

    self:UpdateAlert()
end

function SelfDispelAlert:EnsureFrame()
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
    frame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
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

function SelfDispelAlert:UpdateTicker()
    if not self.frame then
        return
    end

    local ticking = self.db.enabled and not XerionUIFeatures.testMode

    self.frame:SetScript("OnUpdate", ticking and self.frame.Tick or nil)
    self:ApplyGates()
end

function SelfDispelAlert:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile[moduleName] = profile[moduleName] or self:GetDefaults()
    self.db = profile[moduleName]
end

function SelfDispelAlert:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile[moduleName] = profile[moduleName] or self:GetDefaults()
    self.db = profile[moduleName]

    self:ResolveTypeSources()

    if self.db.enabled then
        local frame = self:EnsureFrame()

        self:EnsureContainers()

        frame:UpdateStyles()
        frame:SetScript("OnEvent", OnEvent)

        self:UpdateTicker()

        OnEvent(frame, "PLAYER_ENTERING_WORLD")
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame.display:Hide()
        self:ApplyShownGate()
    end
end

function SelfDispelAlert:ApplyFontSettings(font)
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

function SelfDispelAlert:OnEnable()
    self:RefreshConfig()
end

function SelfDispelAlert:UpdateVisibility()
    if not self.db.enabled or not self.frame then
        return
    end

    self:ResolveTypeSources()
    self:UpdateTicker()
    self.frame:UpdateAlert()
end

function SelfDispelAlert:ToggleTestMode()
    self:UpdateVisibility()
end

function SelfDispelAlert:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
