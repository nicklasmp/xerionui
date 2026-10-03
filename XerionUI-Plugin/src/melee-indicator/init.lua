local addonName, XerionUIFeatures = ...
local moduleName = "MeleeIndicator"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local MeleeIndicator = XerionUIFeatures:NewModule(moduleName)

local meleeSpells

if XerionUIFeatures.isForever then
    meleeSpells = {
        DRUID = {1082, 6807},   -- Claw (cat), Maul (bear)
        PALADIN = {17143},      -- Holy Strike
        ROGUE = {1752},         -- Sinister Strike
        SHAMAN = {17364},       -- Stormstrike
        WARRIOR = {78, 1715},   -- Heroic Strike, Hamstring
    }
else
    meleeSpells = {
        DEATHKNIGHT = {
            [250] = 49998, -- Death Strike
            [251] = 49998, -- Death Strike
            [252] = 49998, -- Death Strike
        },
        DEMONHUNTER = {
            [577] = 162794, -- Chaos Strike
            [581] = 344859, -- Demon's Bite
        },
        DRUID = {
            [103] = 5221, -- Shred
            [104] = 33917, -- Mangle
            [105] = 22568, -- Ferocious Bite
        },
        HUNTER = {
            [255] = 186270, -- Raptor Strike
        },
        MONK = {
            [268] = 205523, -- Blackout Kick
            [269] = 205523, -- Blackout Kick
            [270] = 205523, -- Blackout Kick
        },
        PALADIN = {
            [65] = 415091, -- Shield of the Righteous
            [66] = 96231, -- Rebuke
            [70] = 96231, -- Rebuke
        },
        ROGUE = {
            [259] = 1752, -- Sinister Strike
            [260] = 1752, -- Sinister Strike
            [261] = 1752, -- Sinister Strike
        },
        SHAMAN = {
            [263] = 73899, -- Primal Strike
        },
        WARRIOR = {
            [71] = 1715, -- Hamstring
            [72] = 1715, -- Hamstring
            [73] = 1715, -- Hamstring
        },
    }
end

local function OnEvent(self, ...)
    self:CacheMeleeSpellId()

    if XerionUIFeatures.testMode then
        self.text:Show()
        return
    end
end

local function OnUpdate(self, elapsed)
    if not self.timeSinceLastUpdate then
        self.timeSinceLastUpdate = 0
    end

    self.timeSinceLastUpdate = self.timeSinceLastUpdate + elapsed

    if self.timeSinceLastUpdate > MeleeIndicator.db.updateInterval then
        if not XerionUIFeatures.testMode then
            self:UpdateMeleeIndicator()
        elseif not self.meleeSpellId then
            self.text:Hide()
        end

        self.timeSinceLastUpdate = 0
    end
end

function MeleeIndicator:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 0)
    PixelUtil.SetSize(frame, 28, 28)
    frame.meleeSpellId = nil
    frame.meleeSpellName = nil
    frame.meleeSpells = meleeSpells

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 28, "OUTLINE")
    frame.text:SetText("+")
    frame.text:SetTextColor(1, 0, 0)
    frame.text:SetJustifyH("CENTER")
    frame.text:Hide()

    function frame:GetSpellToCheck()
        local entry = self.meleeSpells[XerionUIFeatures.playerClass]

        if not entry then
            return nil
        end

        if XerionUIFeatures.isForever then
            local fallback = nil

            for _, spellId in ipairs(entry) do
                if XerionUIFeatures:IsSpellKnown(spellId) then
                    local usable, missingResources = C_Spell.IsSpellUsable(spellId)

                    if usable or missingResources then
                        return spellId
                    end

                    fallback = fallback or spellId
                end
            end

            return fallback
        end

        local specIndex = C_SpecializationInfo.GetSpecialization()
        local specId = specIndex and C_SpecializationInfo.GetSpecializationInfo(specIndex)
        local spellId = specId and entry[specId]

        if not spellId or not C_Spell.GetSpellInfo(spellId) then
            return nil
        end

        return spellId
    end

    function frame:CacheMeleeSpellId()
        self.meleeSpellId = self:GetSpellToCheck()
        local spellInfo = self.meleeSpellId and C_Spell.GetSpellInfo(self.meleeSpellId)
        self.meleeSpellName = spellInfo and spellInfo.name
    end

    function frame:UpdateMeleeIndicator()
        local targetExists = UnitExists("target")
        local targetAttackable = UnitCanAttack("player", "target")

        local class = select(2, UnitClass("player"))
        local inCombat = UnitAffectingCombat("player")

        local spellUsable = true

        if not inCombat then
            self.text:Hide()
            return
        end

        -- Only show when druid in cat or bear form
        if class == "DRUID" and self.meleeSpellId then
            local usable, missingResources = C_Spell.IsSpellUsable(self.meleeSpellId)
            spellUsable = usable or missingResources
        end

        if targetExists and targetAttackable and self.meleeSpellName then
            local inRange = C_Spell.IsSpellInRange(self.meleeSpellId, "target")

            if inRange then
                self.text:Hide()
            else
                if class == "DRUID" then
                    if spellUsable then
                        self.text:Show()
                    else
                        self.text:Hide()
                    end
                else
                    self.text:Show()
                end
            end
        else
            self.text:Hide()
        end
    end

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, MeleeIndicator.db.point.point, self:GetParent() or UIParent, MeleeIndicator.db.point.point, MeleeIndicator.db.point.x, MeleeIndicator.db.point.y)
        end

        self:SetFrameStrata(MeleeIndicator.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(MeleeIndicator.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(MeleeIndicator.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(MeleeIndicator.db.font.justifyH or "CENTER")
        self.text:SetTextColor(MeleeIndicator.db.color.r, MeleeIndicator.db.color.g, MeleeIndicator.db.color.b, MeleeIndicator.db.color.a)
        self.text:SetText(MeleeIndicator.db.displayText)
        if MeleeIndicator.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(MeleeIndicator.db.font.fontShadowColor.r, MeleeIndicator.db.font.fontShadowColor.g, MeleeIndicator.db.font.fontShadowColor.b, MeleeIndicator.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(MeleeIndicator.db.font.fontShadowXOffset, MeleeIndicator.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", MeleeIndicator.db.font.fontFamily), MeleeIndicator.db.font.fontSize, MeleeIndicator.db.font.fontOutline)
        PixelUtil.SetSize(self, math.max(self.text:GetStringWidth(), 28), math.max(self.text:GetStringHeight(), 28))
    end

    return frame
end

function MeleeIndicator:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

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

function MeleeIndicator:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.MeleeIndicator = profile.MeleeIndicator or self:GetDefaults()
    self.db = profile.MeleeIndicator
end

function MeleeIndicator:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.MeleeIndicator = profile.MeleeIndicator or self:GetDefaults()
    self.db = profile.MeleeIndicator

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:UpdateStyles()
        frame:CacheMeleeSpellId()
        frame:SetScript("OnEvent", OnEvent)
        frame:SetScript("OnUpdate", OnUpdate)
        OnEvent(frame)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame.text:Hide()
    end
end

function MeleeIndicator:ApplyFontSettings(font)
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

function MeleeIndicator:OnEnable()
    self:RefreshConfig()
end

function MeleeIndicator:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function MeleeIndicator:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
