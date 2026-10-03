local addonName, XerionUIFeatures = ...
local moduleName = "RuneforgeAlert"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local RuneforgeAlert = XerionUIFeatures:NewModule(moduleName)

local bloodSpecId = 250
local frostSpecId = 251
local unholySpecId = 252

-- Hero talent subTreeIds, the ids C_ClassTalents.GetActiveHeroTalentSpec returns.
local sanlayn = 31
local riderOfTheApocalypse = 32
local deathbringer = 33

-- Talent Ids
local frostbaneTalent = 455993

-- Runeforging enchant ids. An equipped weapon carries its runeforge as the enchant
-- field of its item link, so these are what the check compares against.
local fallenCrusader = 3368
local razorice = 3370
local stoneskinGargoyle = 3847
local sanguination = 6241
local spellwarding = 6242
local hysteria = 6243
local unendingThirst = 6244
local apocalypse = 6245

-- `spellId` is the runeforging spell, which is only there to give the options lists
-- the rune's icon.
RuneforgeAlert.Runes = {
    {enchantId = fallenCrusader, spellId = 53344, name = "Rune of the Fallen Crusader"},
    {enchantId = razorice, spellId = 53343, name = "Rune of Razorice"},
    {enchantId = stoneskinGargoyle, spellId = 62158, name = "Rune of the Stoneskin Gargoyle"},
    {enchantId = sanguination, spellId = 326801, name = "Rune of Sanguination"},
    {enchantId = apocalypse, spellId = 327082, name = "Rune of the Apocalypse"},
    {enchantId = unendingThirst, spellId = 326977, name = "Rune of Unending Thirst"},
    {enchantId = hysteria, spellId = 326911, name = "Rune of Hysteria"},
    {enchantId = spellwarding, spellId = 326855, name = "Rune of Spellwarding"},
}

local function mainHand(defaults)
    return {key = "mainHand", label = "MH", inventorySlot = INVSLOT_MAINHAND, defaults = defaults}
end

local function offHand(defaults)
    return {key = "offHand", label = "OH", inventorySlot = INVSLOT_OFFHAND, defaults = defaults}
end

RuneforgeAlert.Setups = {
    -- Blood
    {
        key = "bloodSanlayn",
        label = "San'layn",
        specId = bloodSpecId,
        heroTree = sanlayn,
        slots = {mainHand({sanguination})},
    },
    {
        key = "bloodDeathbringer",
        label = "Deathbringer",
        specId = bloodSpecId,
        heroTree = deathbringer,
        slots = {mainHand({sanguination})},
    },
    -- Frost
    {
        key = "frostFrostbane",
        label = "Frostbane",
        specId = frostSpecId,
        matches = function()
            return XerionUIFeatures:IsSpellKnown(frostbaneTalent) and true or false
        end,
        slots = {mainHand({razorice}), offHand({fallenCrusader})},
    },
    {
        key = "frostWeapons",
        specId = frostSpecId,
        slots = {mainHand({fallenCrusader, stoneskinGargoyle}), offHand({fallenCrusader, stoneskinGargoyle})},
    },
    -- Unholy
    {
        key = "unholySanlayn",
        label = "San'layn",
        specId = unholySpecId,
        heroTree = sanlayn,
        slots = {mainHand({apocalypse})},
    },
    {
        key = "unholyRider",
        label = "Rider of the Apocalypse",
        specId = unholySpecId,
        heroTree = riderOfTheApocalypse,
        slots = {mainHand({apocalypse})},
    },
}

local function equippedRune(inventorySlot)
    local link = GetInventoryItemLink("player", inventorySlot)

    if not link then
        return nil
    end

    local enchantId = link:match("item:%d+:(%d*)")

    return tonumber(enchantId)
end

local function hasAnyRune(runes)
    if not runes then
        return false
    end

    for _, accepted in pairs(runes) do
        if accepted then
            return true
        end
    end

    return false
end

function RuneforgeAlert:GetAcceptedRunes(setupKey, slotKey)
    local setup = self.db.setups and self.db.setups[setupKey]

    return setup and setup[slotKey]
end

function RuneforgeAlert:IsRuneAccepted(setupKey, slotKey, enchantId)
    local runes = self:GetAcceptedRunes(setupKey, slotKey)

    return runes and runes[enchantId] or false
end

function RuneforgeAlert:GetActiveSetup()
    local specialization = GetSpecialization()
    local specId = specialization and (GetSpecializationInfo(specialization))

    if not specId then
        return nil
    end

    local heroTree = C_ClassTalents.GetActiveHeroTalentSpec and C_ClassTalents.GetActiveHeroTalentSpec()

    for _, setup in ipairs(self.Setups) do
        if setup.specId == specId
            and (not setup.heroTree or setup.heroTree == heroTree)
            and (not setup.matches or setup.matches())
        then
            return setup
        end
    end

    return nil
end

function RuneforgeAlert:IsWrongRuneforge()
    if XerionUIFeatures.playerClass ~= "DEATHKNIGHT" then
        return false
    end

    if UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") then
        return false
    end

    if C_ChallengeMode.IsChallengeModeActive() then
        return false
    end

    local setup = self:GetActiveSetup()

    if not setup then
        return false
    end

    for _, slot in ipairs(setup.slots) do
        local runes = self:GetAcceptedRunes(setup.key, slot.key)

        if hasAnyRune(runes) and GetInventoryItemID("player", slot.inventorySlot) then
            local equipped = equippedRune(slot.inventorySlot)

            if not equipped or not runes[equipped] then
                return true
            end
        end
    end

    return false
end

local function OnEvent(self)
    if XerionUIFeatures.testMode then
        self.text:Show()

        return
    end

    if RuneforgeAlert:IsWrongRuneforge() then
        self.text:Show()
    else
        self.text:Hide()
    end
end

function RuneforgeAlert:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 25)
    PixelUtil.SetSize(frame, 28, 28)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 14, "OUTLINE")
    frame.text:SetTextColor(1, 1, 1)
    frame.text:SetJustifyH("CENTER")
    frame.text:Hide()

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, RuneforgeAlert.db.point.point, self:GetParent() or UIParent, RuneforgeAlert.db.point.point, RuneforgeAlert.db.point.x, RuneforgeAlert.db.point.y)
        end

        self:SetFrameStrata(RuneforgeAlert.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(RuneforgeAlert.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(RuneforgeAlert.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(RuneforgeAlert.db.font.justifyH or "CENTER")
        self.text:SetText(RuneforgeAlert.db.displayText)
        self.text:SetTextColor(RuneforgeAlert.db.color.r, RuneforgeAlert.db.color.g, RuneforgeAlert.db.color.b, RuneforgeAlert.db.color.a)

        if RuneforgeAlert.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(RuneforgeAlert.db.font.fontShadowColor.r, RuneforgeAlert.db.font.fontShadowColor.g, RuneforgeAlert.db.font.fontShadowColor.b, RuneforgeAlert.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(RuneforgeAlert.db.font.fontShadowXOffset, RuneforgeAlert.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", RuneforgeAlert.db.font.fontFamily), RuneforgeAlert.db.font.fontSize, RuneforgeAlert.db.font.fontOutline)

        PixelUtil.SetSize(self, self.text:GetStringWidth(), self.text:GetStringHeight())
    end

    return frame
end

function RuneforgeAlert:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    if XerionUIFeatures.playerClass == "DEATHKNIGHT" then
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        frame:RegisterEvent("PLAYER_TALENT_UPDATE")
        frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("CHALLENGE_MODE_START")
        frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        frame:RegisterEvent("CHALLENGE_MODE_RESET")
        frame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    end

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

-- Setups are matched by key, so a profile written by an older build can be missing
-- one the build knows about (a new hero tree) or keep one it no longer has (the two
-- handed Frost setup, folded into the weapons one). A missing key would leave that
-- build silently unchecked, so the stored lists are brought in line with the setups
-- rather than only seeded once.
function RuneforgeAlert:MigrateSetups()
    local defaults = self:GetDefaults().setups

    self.db.setups = self.db.setups or {}

    for setupKey in pairs(self.db.setups) do
        if not defaults[setupKey] then
            self.db.setups[setupKey] = nil
        end
    end

    for setupKey, slots in pairs(defaults) do
        local stored = self.db.setups[setupKey]

        if not stored then
            self.db.setups[setupKey] = slots
        else
            for slotKey, runes in pairs(slots) do
                if not stored[slotKey] then
                    stored[slotKey] = runes
                end
            end

            for slotKey in pairs(stored) do
                if not slots[slotKey] then
                    stored[slotKey] = nil
                end
            end
        end
    end
end

function RuneforgeAlert:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.RuneforgeAlert = profile.RuneforgeAlert or self:GetDefaults()
    self.db = profile.RuneforgeAlert

    self:MigrateSetups()
end

function RuneforgeAlert:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.RuneforgeAlert = profile.RuneforgeAlert or self:GetDefaults()
    self.db = profile.RuneforgeAlert

    self:MigrateSetups()

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:UpdateStyles()
        frame:SetScript("OnEvent", OnEvent)
        OnEvent(frame)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame.text:Hide()
    end
end

function RuneforgeAlert:ApplyFontSettings(font)
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

function RuneforgeAlert:OnEnable()
    self:RefreshConfig()
end

-- Editing a rune list changes what the alert answers, not how it looks, so the
-- options run this on top of their restyle to show the result right away.
function RuneforgeAlert:UpdateVisibility()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function RuneforgeAlert:ToggleTestMode()
    self:UpdateVisibility()
end

function RuneforgeAlert:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
