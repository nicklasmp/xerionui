local addonName, XerionUIFeatures = ...
local moduleName = "MovementAlert"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local MovementAlert = XerionUIFeatures:NewModule(moduleName)

local movementAbilities

if XerionUIFeatures.isForever then
    movementAbilities = {
        DRUID = {1850},         -- Dash
        MAGE = {1953},          -- Blink
        ROGUE = {2983},         -- Sprint
        WARRIOR = {100, 20252}, -- Charge, Intercept
    }
else
    movementAbilities = {
        DEATHKNIGHT = {[250] = {48265, 212552}, [251] = {48265, 212552}, [252] = {48265, 212552}},
        DEMONHUNTER = {[577] = {195072}, [581] = {189110}, [1480] = {1234796}},
        DRUID = {[102] = {102401, 252216, 1850}, [103] = {102401, 252216, 1850}, [104] = {102401, 106898}, [105] = {102401, 252216, 1850}},
        EVOKER = {[1467] = {358267}, [1468] = {358267}, [1473] = {358267}},
        HUNTER = {[253] = {781, 186257}, [254] = {781, 186257}, [255] = {781, 186257}},
        MAGE = {[62] = {212653, 1953}, [63] = {212653, 1953}, [64] = {212653, 1953}},
        MONK = {[268] = {115008, 109132}, [269] = {109132}, [270] = {109132}},
        PALADIN = {[65] = {190784} , [66] = {190784} , [70] = {190784} },
        PRIEST = {[256] = {121536,73325}, [257] = {121536,73325}, [258] = {121536,73325}},
        ROGUE = {[259] = {36554}, [260] = {195457}, [261] = {36554}},
        SHAMAN = {[262] = {79206, 90328, 192063}, [263] = {90328, 192063}, [264] = {79206, 90328, 192063}},
        WARLOCK = {[265] = {48020}, [266] = {48020}, [267] = {48020}},
        WARRIOR = {[71] = {6544, 100}, [72] = {6544, 100}, [73] = {6544, 100}}
    }
end

-- Spec ids are unique across classes, so the class layer above is only there to keep
-- the list readable. On Forever the class name stands in for the spec id, in the
-- profile included. Exposed because defaults.lua seeds a profile from it and
-- options.shared.lua builds the options lists from it.
MovementAlert.movementAbilitiesBySpec = {}

if XerionUIFeatures.isForever then
    for class, spellIds in pairs(movementAbilities) do
        MovementAlert.movementAbilitiesBySpec[class] = spellIds
    end
else
    for _, specs in pairs(movementAbilities) do
        for specId, spellIds in pairs(specs) do
            MovementAlert.movementAbilitiesBySpec[specId] = spellIds
        end
    end
end

-- List taken from: https://www.curseforge.com/wow/addons/time-spiral-tracker
-- Exposed because options.shared.lua lists it per class.
local timeSpiralAbilities = {
    DEATHKNIGHT = {
        48265, -- Death's Advance
    },
    DEMONHUNTER = {
        195072, -- Fel Rush
        189110, -- Infernal Strike
        1234796, -- Shift
    },
    DRUID = {
        1850, -- Dash
        252216, -- Tiger Dash
    },
    EVOKER = {
        358267, -- Hover
    },
    HUNTER = {
        186257, -- Aspect of the Cheetah
    },
    MAGE = {
        212653, -- Shimmer
        1953, -- Blink
    },
    MONK = {
        119085, -- Chi Torpedo
        361138, -- Roll
    },
    PALADIN = {
        190784, -- Divine Steed
    },
    PRIEST = {
        73325, -- Leap of Faith
    },
    ROGUE = {
        2983, -- Sprint
    },
    SHAMAN = {
        192063, -- Gust of Wind
        58875, -- Spirit Walk
        79206, -- Spiritwalker's Grace
    },
    WARLOCK = {
        48020, -- Demonic Circle: Teleport
    },
    WARRIOR = {
        6544, -- Heroic Leap
    },
}

MovementAlert.timeSpiralAbilities = timeSpiralAbilities

-- Priest lmao
local timeSpiralDefaultOff = {
    [73325] = true, -- Leap of Faith
}

MovementAlert.timeSpiralAbilitiesBySpell = {}
for _, spellIds in pairs(timeSpiralAbilities) do
    for _, spellId in ipairs(spellIds) do
        MovementAlert.timeSpiralAbilitiesBySpell[spellId] = not timeSpiralDefaultOff[spellId]
    end
end

local spellsThatTriggerGlows = {
	DEMONHUNTER = {
        [577] = {
            { talent = 427640, spellId = 370965, delay = 1 }, -- Inertia / The hunt
            { talent = 427640, spellId = 198793 }, -- Inertia / Vengeful retreat
            { talent = 427794, spellId = 195072 }, -- Dash of Chaos / Fel Rush
        },
	},
    WARLOCK = {
        [265] = {
            { talent = 385899, spellId = 385899 } -- Soulburn
        },
        [266] = {
            { talent = 385899, spellId = 385899 } -- Soulburn
        },
        [267] = {
            { talent = 385899, spellId = 385899 } -- Soulburn
        },
    },
}

local spellsWithOwnGCD = {
	[1234796] = 0.8
}

function MovementAlert:GetMovementSpellChoices(specId)
    return specId and self.movementAbilitiesBySpec[specId]
end

function MovementAlert:IsTimeSpiralSpell(spellId)
    return self.timeSpiralAbilitiesBySpell[spellId] ~= nil
end

function MovementAlert:IsTimeSpiralSpellTracked(spellId)
    if not self:IsTimeSpiralSpell(spellId) then
        return false
    end

    local tracked = self.db.timeSpiralSpells[spellId]

    if tracked == nil then
        return self.timeSpiralAbilitiesBySpell[spellId]
    end

    return tracked
end

function MovementAlert:IsSpellTracked(specId, spellId)
    local trackedSpells = self.db.trackedSpells[specId]
    local tracked = trackedSpells and trackedSpells[spellId]

    return tracked
end

function MovementAlert:GetCurrentSpecId()
    if XerionUIFeatures.isForever then
        return XerionUIFeatures.playerClass
    end

    local specIndex = C_SpecializationInfo.GetSpecialization()

    return specIndex and (C_SpecializationInfo.GetSpecializationInfo(specIndex))
end

local function OnUpdate(self, elapsed, ...)
    if not self.timeSinceLastUpdate then
        self.timeSinceLastUpdate = 0
    end

    self.timeSinceLastUpdate = self.timeSinceLastUpdate + elapsed

    if self.timeSinceLastUpdate > MovementAlert.db.updateInterval then
        if not XerionUIFeatures.testMode then
            if self.timeSpiralOn then
                local timeSpiralText = CreateColor(
                    MovementAlert.db.timeSpiralColor.r,
                    MovementAlert.db.timeSpiralColor.g,
                    MovementAlert.db.timeSpiralColor.b,
                    MovementAlert.db.timeSpiralColor.a
                ):WrapTextInColorCode(MovementAlert.db.timeSpiralText .. "\n" .. string.format(
                    "%." .. MovementAlert.db.precision .. "f", 10 - (GetTime() - self.timeSpiralOn)
                ))
                self.text:SetText(timeSpiralText)
                self.text:Show()
            else
                local spell, cdInfo = self:GetMovementSpellOnCooldown()

                if spell then
                    self.text:SetText("No " .. spell.name .. "\n" .. string.format("%." .. MovementAlert.db.precision .. "f", cdInfo.timeUntilEndOfStartRecovery))
                    self.text:Show()
                else
                    self.text:Hide()
                end
            end
        end

        self.timeSinceLastUpdate = 0
    end
end

local function OnEvent(self, event, ...)
    if not InCombatLockdown() then
        self:CacheMovementId()
    end

    if XerionUIFeatures.testMode then
        self.text:SetText("No " .. (self.movementName or "movement ability") .. "\n" .. string.format("%." .. MovementAlert.db.precision .. "f", 15.3))
        self.text:Show()
        return
    end

    if MovementAlert.db.showTimeSpiral then
        local spellId = ...
        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" and not self.ignoreGlow then
            if MovementAlert:IsTimeSpiralSpellTracked(spellId) then
                self.timeSpiralOn = GetTime();

                if MovementAlert.db.timeSpiralPlaySound and MovementAlert.db.timeSpiralSound then
                    PlaySoundFile(LSM:Fetch("sound", MovementAlert.db.timeSpiralSound), "Master")
                elseif MovementAlert.db.timeSpiralPlayTTS and MovementAlert.db.timeSpiralTTS then
                    C_VoiceChat.SpeakText(MovementAlert.db.timeSpiralTTSVoice, MovementAlert.db.timeSpiralTTS, 1, MovementAlert.db.timeSpiralTTSVolume, true)
                end
            end
        elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
            -- Membership rather than the filter, so a spell switched off mid glow
            -- still clears the alert it started.
            if MovementAlert:IsTimeSpiralSpell(spellId) then
                self.timeSpiralOn = nil;
            end
        elseif event == "UNIT_SPELLCAST_SENT" then
            local spellId = select(4, ...)

            if self.spellsToIgnoreGlowsFrom and self.spellsToIgnoreGlowsFrom[spellId] then
                self.ignoreGlow = true

                C_Timer.After(self.spellsToIgnoreGlowsFrom[spellId], function()
                    self.ignoreGlow = false;
                end)
            end

            if self.spellsThatHaveTheirOwnGCD[spellId] then
                self.ignoreMovementCd = true

                C_Timer.After(self.spellsThatHaveTheirOwnGCD[spellId], function()
                    self.ignoreMovementCd = false;
                end)
            end
        else
            self.timeSpiralOn = nil;
        end
    end
end

function MovementAlert:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 300)
    PixelUtil.SetSize(frame, 28, 28)
    frame.movementName = nil;
    frame.movementSpells = {}
    frame.ignoreMovementCd = false
    frame.spellsToIgnoreGlowsFrom = {}
    frame.timeSpiralOn = false;
    frame.ignoreGlow = false

    frame.spellsThatTriggerGlows = spellsThatTriggerGlows
    frame.spellsThatHaveTheirOwnGCD = spellsWithOwnGCD

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 14, "OUTLINE")
    frame.text:SetTextColor(1, 1, 1, 1)
    frame.text:SetJustifyH("CENTER")
    frame.text:Hide();

    -- Every tracked ability the character actually has, in list order, so the list
    -- doubles as the priority the alert reports them in.
    function frame:GetSpellsToCheck()
        local specId = MovementAlert:GetCurrentSpecId()
        local spellIds = MovementAlert:GetMovementSpellChoices(specId)
        local spells = {}

        if not spellIds then
            return spells
        end

        for _, spellId in ipairs(spellIds) do
            local spellInfo = MovementAlert:IsSpellTracked(specId, spellId)
                and XerionUIFeatures:IsSpellKnown(spellId)
                and C_Spell.GetSpellInfo(spellId)

            if spellInfo then
                spells[#spells + 1] = {id = spellId, name = spellInfo.name}
            end
        end

        return spells
    end

    function frame:GetMovementSpellOnCooldown()
        if self.ignoreMovementCd or not self.movementSpells then
            return nil
        end

        for _, spell in ipairs(self.movementSpells) do
            local cdInfo = C_Spell.GetSpellCooldown(spell.id)

            if cdInfo
                and cdInfo.timeUntilEndOfStartRecovery
                and not cdInfo.isOnGCD
                -- cdInfo.isOnGCD is nil when double jumping (evoker / dh)
                -- WL teleport isOnGCD exists while on gcd and then is nil
                and (cdInfo.isOnGCD ~= nil or XerionUIFeatures.playerClass == "WARLOCK")
            then
                return spell, cdInfo
            end
        end

        return nil
    end

    function frame:GetSpellsToIgnoreGlowsFrom()
        local class = XerionUIFeatures.playerClass
        local specId = MovementAlert:GetCurrentSpecId()
        local specs = self.spellsThatTriggerGlows[class]

        if not specs or not specId then
            return nil
        end

        if not specs[specId] then
            return nil
        end

        local ignoredList = {}
        for _, entry in ipairs(specs[specId]) do
            if XerionUIFeatures:IsSpellKnown(entry.talent) then
                ignoredList[entry.spellId] = 0.05 + (entry.delay or 0)
            end
        end

        return ignoredList
    end

    function frame:CacheMovementId()
        self.movementSpells = self:GetSpellsToCheck()

        local first = self.movementSpells[1]
        self.movementName = first and first.name
        self.spellsToIgnoreGlowsFrom = self:GetSpellsToIgnoreGlowsFrom()
    end

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, MovementAlert.db.point.point, self:GetParent() or UIParent, MovementAlert.db.point.point, MovementAlert.db.point.x, MovementAlert.db.point.y)
        end

        self:SetFrameStrata(MovementAlert.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(MovementAlert.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(MovementAlert.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(MovementAlert.db.font.justifyH or "CENTER")
        self.text:SetTextColor(MovementAlert.db.color.r, MovementAlert.db.color.g, MovementAlert.db.color.b, MovementAlert.db.color.a)
        if MovementAlert.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(MovementAlert.db.font.fontShadowColor.r, MovementAlert.db.font.fontShadowColor.g, MovementAlert.db.font.fontShadowColor.b, MovementAlert.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(MovementAlert.db.font.fontShadowXOffset, MovementAlert.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", MovementAlert.db.font.fontFamily), MovementAlert.db.font.fontSize, MovementAlert.db.font.fontOutline)

        if not self:HasAnySecretAspect() and not self.text:HasAnySecretAspect() then
            PixelUtil.SetSize(self, math.max(self.text:GetStringWidth(), 28), math.max(self.text:GetStringHeight(), 28))
        end
    end

    return frame
end

function MovementAlert:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("PLAYER_TALENT_UPDATE")
    frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")

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

function MovementAlert:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.MovementAlert = profile.MovementAlert or self:GetDefaults()
    self.db = profile.MovementAlert

    -- Migration
    self.db.timeSpiralTTSVoice = self.db.timeSpiralTTSVoice or self:GetDefaults().timeSpiralTTSVoice
    self.db.trackedSpells = self.db.trackedSpells or self:GetDefaults().trackedSpells
    self.db.timeSpiralSpells = self.db.timeSpiralSpells or self:GetDefaults().timeSpiralSpells
end

function MovementAlert:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.MovementAlert = profile.MovementAlert or self:GetDefaults()
    self.db = profile.MovementAlert

    -- Migration
    self.db.timeSpiralTTSVoice = self.db.timeSpiralTTSVoice or self:GetDefaults().timeSpiralTTSVoice
    self.db.trackedSpells = self.db.trackedSpells or self:GetDefaults().trackedSpells
    self.db.timeSpiralSpells = self.db.timeSpiralSpells or self:GetDefaults().timeSpiralSpells

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:UpdateStyles()
        frame:CacheMovementId()
        frame:SetScript("OnEvent", OnEvent)
        frame:SetScript("OnUpdate", OnUpdate)
        OnEvent(frame)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame.text:Hide()
    end
end

function MovementAlert:ApplyFontSettings(font)
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

function MovementAlert:OnEnable()
    self:RefreshConfig()
end

function MovementAlert:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function MovementAlert:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
