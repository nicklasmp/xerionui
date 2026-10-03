local addonName, XerionUIFeatures = ...

XerionUIFeatures.playerClass = select(2, UnitClass("player"));

-- Forever runs the 12.x engine with vanilla content and reports a 1.60+ interface number (16001). 
-- Classic Era reports 115xx and retail 12xxxx.
XerionUIFeatures.interfaceVersion = select(4, GetBuildInfo())
XerionUIFeatures.isForever = type(XerionUIFeatures.interfaceVersion) == "number" and XerionUIFeatures.interfaceVersion >= 16000 and XerionUIFeatures.interfaceVersion < 20000

if XerionUIFeatures.isForever then
    XerionUIFeatures.displayName = "XerionUI Plugin"
    XerionUIFeatures.displayNameColored = "|cffff7d0aXerionUI|r Plugin"
else
    XerionUIFeatures.displayName = "XerionUI Plugin"
    XerionUIFeatures.displayNameColored = "|cffff7d0aXerionUI|r Plugin"
end

if XerionUIFeatures.isForever then
    XerionUIFeatures.interruptSpells = {
        MAGE = {2139},          -- Counterspell
        PRIEST = {15487},       -- Silence
        ROGUE = {1766},         -- Kick
        SHAMAN = {8042},        -- Earth Shock
        WARLOCK = {19244},      -- Spell Lock (Felhunter)
        WARRIOR = {6552, 72},   -- Pummel, Shield Bash
    }
else
    XerionUIFeatures.interruptSpells = {
        DEATHKNIGHT = {[250] = 47528, [251] = 47528, [252] = 47528},
        DEMONHUNTER = {[577] = 183752, [581] = 183752, [1480] = 183752},
        DRUID = {[102] = 78675, [103] = 106839, [104] = 106839, [105] = nil},
        EVOKER = {[1467] = 351338, [1468] = 351338, [1473] = 351338},
        HUNTER = {[253] = 147362, [254] = 147362, [255] = 187707},
        MAGE = {[62] = 2139, [63] = 2139, [64] = 2139},
        MONK = {[268] = 116705, [269] = 116705, [270] = nil},
        PALADIN = {[65] = nil, [66] = 96231, [70] = 96231},
        PRIEST = {[256] = nil, [257] = nil, [258] = 15487},
        ROGUE = {[259] = 1766, [260] = 1766, [261] = 1766},
        SHAMAN = {[262] = 57994, [263] = 57994, [264] = 57994},
        WARLOCK = {[265] = 19647, [266] = 119914, [267] = 19647},
        WARRIOR = {[71] = 6552, [72] = 6552, [73] = 6552}
    }
end

function XerionUIFeatures:GetClassInterruptSpells()
    local entry = self.interruptSpells[self.playerClass]
    local spells = {}

    if not entry then
        return spells
    end

    if self.isForever then
        for _, spellId in ipairs(entry) do
            table.insert(spells, spellId)
        end

        return spells
    end

    local specIds = {}
    for specId in pairs(entry) do
        table.insert(specIds, specId)
    end
    table.sort(specIds)

    local seen = {}
    for _, specId in ipairs(specIds) do
        local spellId = entry[specId]

        if spellId and not seen[spellId] then
            seen[spellId] = true
            table.insert(spells, spellId)
        end
    end

    return spells
end

function XerionUIFeatures:GetInterruptSpell()
    local entry = self.interruptSpells[self.playerClass]

    if not entry then
        return nil
    end

    if self.isForever then
        for _, spellId in ipairs(entry) do
            if self:IsSpellKnown(spellId) then
                return spellId
            end
        end

        return entry[1]
    end

    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specId = specIndex and C_SpecializationInfo.GetSpecializationInfo(specIndex)

    return specId and entry[specId] or nil
end


XerionUIFeatures.battleRezSpells = {
    DEATHKNIGHT = 61999,  -- Raise Ally
    DRUID = 20484,        -- Rebirth (same id in forever)
    PALADIN = 391054,     -- Intercession
    WARLOCK = 20707,      -- Soulstone
}

function XerionUIFeatures:GetBattleRezSpell()
    return self.battleRezSpells[self.playerClass]
end

if XerionUIFeatures.isForever then
    XerionUIFeatures.petSpecs = {
        HUNTER = {excludes = 415370}, -- Lone Wolf
        WARLOCK = true,
    }
else
    XerionUIFeatures.petSpecs = {
        DEATHKNIGHT = {[250] = false, [251] = false, [252] = true},
        DEMONHUNTER = {[577] = false, [581] = false, [1480] = false},
        DRUID = {[102] = false, [103] = false, [104] = false, [105] = false},
        EVOKER = {[1467] = false, [1468] = false, [1473] = false},
        HUNTER = {[253] = true, [254] = {requires = 1223323}, [255] = {excludes = 155228}}, -- Unbreakable Bond, Lone Wolf
        MAGE = {[62] = false, [63] = false, [64] = {requires = 31687}}, -- Summon Water Elemental
        MONK = {[268] = false, [269] = false, [270] = false},
        PALADIN = {[65] = false, [66] = false, [70] = false},
        PRIEST = {[256] = false, [257] = false, [258] = false},
        ROGUE = {[259] = false, [260] = false, [261] = false},
        SHAMAN = {[262] = false, [263] = false, [264] = false},
        WARLOCK = {[265] = true, [266] = true, [267] = true},
        WARRIOR = {[71] = false, [72] = false, [73] = false}
    }
end

local function ResolvePetRule(rule)
    if type(rule) ~= "table" then
        return rule or false
    end

    if rule.requires then
        return XerionUIFeatures:IsSpellKnown(rule.requires)
    end

    if rule.excludes then
        return not XerionUIFeatures:IsSpellKnown(rule.excludes)
    end

    return false
end

function XerionUIFeatures:IsPetSpec()
    local entry = self.petSpecs[self.playerClass]

    if not entry then
        return false
    end

    if self.isForever then
        return ResolvePetRule(entry)
    end

    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specId = specIndex and C_SpecializationInfo.GetSpecializationInfo(specIndex)

    return ResolvePetRule(specId and entry[specId])
end

function XerionUIFeatures:InDungeon()
    local inInstance, instanceType = IsInInstance()

    return inInstance and instanceType == "party"
end

function XerionUIFeatures:InMythicDungeon()
    if not self:InDungeon() then
        return false
    end

    local name = GetDifficultyInfo(GetDungeonDifficultyID())

    return name == "Mythic";
end

function XerionUIFeatures:InRaid()
    local inInstance, instanceType = IsInInstance()

    return inInstance and instanceType == "raid"
end

function XerionUIFeatures:IsSpellKnown(spellId)
    if not spellId then
        return
    end

    -- C_SpellBook.IsSpellInSpellBook might return false for w/e reason (like Fel Rush)
    -- C_SpellBook.IsSpellKnown doesn'parts work with overriden spells
    -- IsPlayerSpell is what answers for passive talents, which the spellbook may not
    -- list. Deprecated, hence the existence check.

    return C_SpellBook.IsSpellInSpellBook(spellId, Enum.SpellBookSpellBank.Player, false)
        or C_SpellBook.IsSpellKnown(spellId, Enum.SpellBookSpellBank.Player)
        or (IsPlayerSpell and IsPlayerSpell(spellId))
        or false
end

function XerionUIFeatures:SplitAndTrim(str)
    local parts = {}

    for part in string.gmatch(str, "([^,]+)") do
        part = part:match("^%s*(.-)%s*$") -- trim whitespace
        table.insert(parts, part)
    end

    return parts
end

function XerionUIFeatures:GetGroupUnits()
    local units = {}

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            table.insert(units, "raid" .. i)
        end
    elseif IsInGroup() then
        table.insert(units, "player")
        for i = 1, GetNumSubgroupMembers() do
            table.insert(units, "party" .. i)
        end
    else
        table.insert(units, "player")
    end

    return units
end

function XerionUIFeatures:GetActiveStanceSpell()
    local numForms = GetNumShapeshiftForms() or 0

    for i = 1, numForms do
        local _, isActive, _, spellId = GetShapeshiftFormInfo(i)

        if isActive then
            return spellId
        end
    end

    return nil
end

function XerionUIFeatures:CanGlide()
    local canGlide = select(2, C_PlayerInfo.GetGlidingInfo())

    if not canGlide then
        return false
    end

    -- can glide is slow
    return IsMounted() or UnitInVehicle("player") or GetShapeshiftFormID() ~= nil
end

function XerionUIFeatures:OnDragonRidingChange(onEvent)
    local mountFrame = CreateFrame("frame", nil, UIParent)
    mountFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    mountFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
    mountFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    mountFrame:SetScript("OnEvent", function() 
        onEvent(XerionUIFeatures:CanGlide())
    end)

    return mountFrame
end

local chatLinkHandlers = {}
local chatLinkHooked = false

-- garrmission links are one of the few link types the chat frame renders for addons,
-- clicking one runs through SetItemRef and the default handler ignores unknown payloads
function XerionUIFeatures:RegisterChatLink(handlerName, handler)
    chatLinkHandlers[handlerName] = handler

    if chatLinkHooked then
        return
    end

    chatLinkHooked = true

    hooksecurefunc("SetItemRef", function(link)
        local name, payload = link:match("^garrmission:" .. addonName .. ":([^:]+):?(.*)$")
        if not name then
            return
        end

        local registered = chatLinkHandlers[name]
        if registered then
            registered(payload)
        end
    end)
end

function XerionUIFeatures:ChatLink(handlerName, payload, text)
    return ("|Hgarrmission:%s:%s:%s|h|cff00ccff[%s]|r|h"):format(addonName, handlerName, payload or "", text)
end

function XerionUIFeatures:UnitTokenFromGUID(guid)
    if not guid or hasanysecretvalues(guid) then
        return nil
    end

    local token = UnitTokenFromGUID(guid)

    if token then
        return token
    end

    if guid == UnitGUID("player") then
        return "player"
    end

    if IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i

            if guid == UnitGUID(unit) then
                return unit
            end
        end
    end

    if IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i

            if guid == UnitGUID(unit) then
                return unit
            end
        end
    end

    return nil
end

function XerionUIFeatures:IsChatLocked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

-- static skips the event and script wiring: a border built inside an aura button's
-- initializeFrame must not register events or scripts, since those are among the
-- button tree's forbidden aspects and a throw there kills the engine's whole frame
-- batch. Scripts on button children never dispatch anyway.
function XerionUIFeatures:CreateBorder(frame, r, g, b, a, static)
    local border = CreateFrame("frame", nil, frame, "BackdropTemplate")
    PixelUtil.SetPoint(border, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(border, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    border:SetFrameStrata(frame:GetFrameStrata())
    border:SetFrameLevel(frame:GetFrameLevel() + 2)
    border.borderColor = {r or 0, g or 0, b or 0, a or 1}

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

        self:SetBackdropBorderColor(unpack(self.borderColor))
        self:SetBackdropColor(0, 0, 0, 0)
    end

    function border:SetBorderColor(r2, g2, b2, a2)
        self.borderColor = {r2, g2, b2, a2 or 1}
        self:SetBackdropBorderColor(r2, g2, b2, a2 or 1)
    end

    if not static then
        border:RegisterEvent("UI_SCALE_CHANGED")
        border:RegisterEvent("DISPLAY_SIZE_CHANGED")
        border:SetScript("OnEvent", border.UpdateSize)
        border:SetScript("OnSizeChanged", border.UpdateSize)
    end

    border:UpdateSize()

    return border
end

-- (values, order) for a TTS voice dropdown -- values keyed by voiceID (the id
-- C_VoiceChat.SpeakText's first argument takes), "Default" (voiceID 0, the
-- system default every module used before voice selection existed) pinned
-- first, the rest of the installed voices alphabetical after it.
function XerionUIFeatures:GetTTSVoiceOptions()
    local values, order = {[0] = "Default"}, {0}

    local voices = C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices() or {}

    for _, voice in ipairs(voices) do
        if voice.voiceID ~= 0 then
            values[voice.voiceID] = voice.name
            order[#order + 1] = voice.voiceID
        end
    end

    table.sort(order, function(a, b)
        if a == 0 or b == 0 then
            return a == 0
        end

        return values[a] < values[b]
    end)

    return values, order
end

function XerionUIFeatures:CreateBackground(frame, r, g, b, a)
    local background = CreateFrame("frame", "$parent_Background", frame, "BackdropTemplate")
    background:SetAllPoints()
    background:SetFrameStrata(frame:GetFrameStrata())
    background:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))

    -- No edgeFile here: CreateBorder draws the ring, and an uncolored backdrop
    -- edge renders white, poking out whenever the two edge sizes disagree.
    background:SetBackdrop({
        bgFile = [[Interface\Buttons\WHITE8x8]],
    })
    background:SetBackdropColor(r or 0, g or 0, b or 0, a or 0.35)

    function background:SetColor(r2, g2, b2, a2)
        self:SetBackdropColor(r2, g2, b2, a2 or 1)
    end

    return background
end
