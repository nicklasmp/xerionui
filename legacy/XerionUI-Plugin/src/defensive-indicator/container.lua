local addonName, XerionUIFeatures = ...

local moduleName = "DefensiveIndicator"
local DefensiveIndicator = XerionUIFeatures:GetModule(moduleName)

local issecretvalue = issecretvalue or function() return false end

-- Where the live display comes from. Addon code cannot read a player's auras in combat
-- on 12.1, even outside restricted content, so presence comes from the engine: an
-- AuraContainer shows and hides a button per matching aura entirely C-side, and the
-- engine calls SetCooldown on a cooldown of ours whenever the aura refreshes, so the
-- swipe runs on times we are never allowed to read.
--
-- Nothing may ask which buttons the engine is showing either: in combat a button and
-- everything under it is a forbidden object, so no Lua arbitration can narrow several
-- active defensives down to one. The display narrows by construction instead:
--  * One container per tier draws the ring or bar. The tiers stack on the same spot,
--    each on a higher frame level than the last over an opaque base, so when several
--    are up only the biggest one is visible.
--  * One more container holds every tracked id in a single one-frame group, so the
--    engine itself picks a single aura. That button carries the name (SetSpellName)
--    and the duration (SetDurationText), which is why two defensives can never put
--    two readouts on screen. Newest application wins the pick.

-- Highest tier last: the draw order IS the priority, and the opaque base under each
-- ring is what makes the higher tier actually hide the lower one.
local containerOrder = {"MINOR", "MAJOR", "EXTERNAL", "MASSIVE"}

-- Wide enough steps that a tier's whole subtree, bar border and swipe included, sits
-- below the next tier's base.
local tierLevelStep = 10

-- An include map is not optional: a tier that holds none matches every buff there is,
-- whatever its frame count. A tier with nothing ticked gets a map that cannot match,
-- spell id 0, rather than none at all; an empty map is the same as no map.
local noMatchIds = {[0] = true}

local function includeFilters(ids)
    return {includeSpellIDs = ids or noMatchIds}
end

-- One per decimal precision. The countdown is drawn engine side against a duration Lua
-- may not read, so the precision is baked into a formatter rather than string.format.
local durationFormatters = {}

local function getDurationFormatter(precision)
    local cached = durationFormatters[precision]

    if cached ~= nil then
        return cached or nil
    end

    durationFormatters[precision] = false

    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding) then
        return nil
    end

    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local up = Enum.NumericRuleFormatRounding.Up
    local down = Enum.NumericRuleFormatRounding.Down

    -- Seconds round up so the text never reads 0 while time remains; minutes and above
    -- floor.
    local ok = pcall(formatter.SetBreakpoints, formatter, {
        {
            threshold = 0,
            format = precision > 0 and ("%." .. precision .. "f") or "%d",
            step = precision > 0 and 0.1 or 1,
            rounding = up,
        },
        {threshold = 60, format = "%dm", step = 1, rounding = up, components = {{div = 60}}},
        {threshold = 61, format = "%dm", step = 1, rounding = down, components = {{div = 60}}},
    })

    if not ok then
        return nil
    end

    durationFormatters[precision] = formatter

    return formatter
end

function DefensiveIndicator:ApplyDurationText(button, text)
    if not (button and text) then
        return
    end

    local precision = self.db.precision or 0
    local formatter = getDurationFormatter(precision)

    if not formatter then
        return
    end

    -- A decimal requires faster refreshes
    if precision > 0 and C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
        local binding = C_DurationUtil.CreateDurationTextBinding()

        binding:SetFormatter(formatter)
        binding:SetUpdateInterval(0.1)

        if pcall(button.SetDurationText, button, text, {binding = binding}) then
            return
        end
    end

    pcall(button.SetDurationText, button, text, {textFormatter = formatter})
end

function DefensiveIndicator:GetTrackedIds(category)
    local ids

    local function add(entries)
        for _, entry in ipairs(entries or {}) do
            if self:GetAuraCategory(entry.auraId) == category and self:IsAuraTracked(entry.auraId) and self:IsAuraKnown(entry.auraId) then
                ids = ids or {}
                ids[entry.auraId] = true

                for _, rankId in ipairs(entry.ranks or {}) do
                    ids[rankId] = true
                end
            end
        end
    end

    add(self.defensiveAuras[XerionUIFeatures.playerClass])

    add(self.externalAuras)

    return ids
end

function DefensiveIndicator:GetWinnerIds()
    local ids

    for _, spellId in ipairs(self:GetTrackedAuras()) do
        ids = ids or {}
        ids[spellId] = true
    end

    return ids
end

-- Neither clicks nor tooltips: the display is a readout, and an engine aura button
-- comes with both alive. Only legal in the creation window, post-creation writes on
-- the button being denied while auras are secret.
local function silenceButton(button)
    pcall(button.SetMouseClickEnabled, button, false)

    if button.SetMouseMotionEnabled then
        pcall(button.SetMouseMotionEnabled, button, false)
    end
end

function DefensiveIndicator:InitialiseRingButton(button, category)
    silenceButton(button)

    local ring = self:CreateRing(button)
    ring.category = category

    -- Anchored to the module's own frame so the mover owns where the ring sits; the
    -- button's parentage is only for the visibility it inherits. Scale pinned first,
    -- or PixelUtil snaps the ring against a different effective scale than the frame
    -- it is anchored to.
    pcall(button.SetScale, button, 1)
    PixelUtil.SetPoint(ring, "CENTER", self.frame, "CENTER", 0, 0)

    -- The engine leaves its buttons unsized. Only legal here, so a later size change
    -- re-applies through RestyleRings, a no-op while the write is denied.
    local width, height = self:GetDisplaySize()

    pcall(PixelUtil.SetSize, button, width, height)
    ring.button = button

    -- The engine sets it and never shows it: the ring has no icon, but the button
    -- expects one to be registered.
    ring.icon = ring:CreateTexture(nil, "BACKGROUND")
    ring.icon:Hide()

    pcall(button.SetIcon, button, ring.icon)

    -- The ring's own swipe IS the button's duration source: the engine drives it from
    -- C, so its times can never be intercepted.
    pcall(button.SetDurationCooldown, button, ring.full.swipe)

    -- Bound alongside the cooldown rather than instead of it, both registrations being
    -- creation-window only while the display setting can change afterwards.
    local barOptions = {}

    -- Eased rather than Immediate: the engine refreshes the binding in steps, and
    -- snapping to each new value makes the drain visibly tick.
    if Enum.StatusBarInterpolation then
        barOptions.interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut or Enum.StatusBarInterpolation.Immediate
    end

    if Enum.StatusBarTimerDirection then
        barOptions.direction = Enum.StatusBarTimerDirection.RemainingTime
    end

    if not pcall(button.SetDurationBar, button, ring.bar, barOptions) then
        pcall(button.SetDurationBar, button, ring.bar)
    end

    self.rings[#self.rings + 1] = ring

    self:StyleRing(ring)
    self:ColorRing(ring, category)
end

function DefensiveIndicator:StyleWinnerText(winner)
    local nameY, durationY = self:GetTextOffsets()

    self:StyleText(winner.name, nameY)
    self:StyleText(winner.duration, durationY)

    -- Alpha as well as the shown flag: the engine writes into these strings and may
    -- put one back on screen doing it.
    winner.name:SetShown(self.db.showName)
    winner.name:SetAlpha(self.db.showName and 1 or 0)
    winner.duration:SetShown(self.db.showDuration)
    winner.duration:SetAlpha(self.db.showDuration and 1 or 0)
end

function DefensiveIndicator:InitialiseWinnerButton(button)
    silenceButton(button)

    pcall(button.SetScale, button, 1)

    local carrier = CreateFrame("frame", nil, button)
    PixelUtil.SetPoint(carrier, "CENTER", self.frame, "CENTER", 0, 0)
    PixelUtil.SetSize(carrier, 1, 1)
    carrier:EnableMouse(false)

    local winner = {
        button = button,
        name = carrier:CreateFontString(nil, "OVERLAY"),
        duration = carrier:CreateFontString(nil, "OVERLAY"),
    }

    winner.icon = carrier:CreateTexture(nil, "BACKGROUND")
    winner.icon:Hide()

    pcall(button.SetIcon, button, winner.icon)

    self.winners[#self.winners + 1] = winner

    -- Fonts before the bindings, never after: the engine writes into these strings,
    -- and SetText on a font string that has no font throws, which inside the engine's
    -- frame batch takes every button in it down.
    self:StyleWinnerText(winner)

    local named, nameErr = pcall(button.SetSpellName, button, winner.name)

    if not named then
        self.winnerError = nameErr
    end

    self:ApplyDurationText(button, winner.duration)
end

local function createContainerShell(frame, level)
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, frame, "CustomAuraContainerTemplate")

    if not ok or not container then
        return nil, container or "CreateFrame failed"
    end

    -- A renderable rect from the first dirty mark, the way AuraKit sets its own up;
    -- the engine replaces the size on every layout pass.
    container:SetScale(1)
    container:SetPoint("CENTER", frame, "CENTER")
    container:SetSize(1, 1)
    container:SetFrameLevel(level)

    return container
end

function DefensiveIndicator:EnsureContainers()
    if self.containers then
        return self.containers
    end

    if not (CreateFrame and C_AddOns) then
        return nil
    end

    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end

    local frame = self:EnsureFrame()
    local containers = {}

    self.rings = self.rings or {}
    self.winners = self.winners or {}

    for index, category in ipairs(containerOrder) do
        local container, shellErr = createContainerShell(frame, frame:GetFrameLevel() + index * tierLevelStep)

        if not container then
            self.containerError = shellErr

            return nil
        end

        local ids = self:GetTrackedIds(category)
        local added, err = pcall(container.AddAuraGroup, container, "defensive", "HELPFUL", {
            maxFrameCount = 1,
            candidateFilters = includeFilters(ids),
            initializeFrame = function(button)
                self:InitialiseRingButton(button, category)
            end,
        })

        if not added then
            self.containerError = err
        end

        local bound, unitErr = pcall(container.SetUnit, container, "player")

        if not bound then
            self.containerError = unitErr
        end

        pcall(container.UpdateAllAuras, container)

        containers[category] = container
    end

    local winnerContainer, winnerShellErr = createContainerShell(frame, frame:GetFrameLevel() + (#containerOrder + 1) * tierLevelStep)

    if winnerContainer then
        local ids = self:GetWinnerIds()
        local added, err = pcall(winnerContainer.AddAuraGroup, winnerContainer, "defensive", "HELPFUL", {
            maxFrameCount = 1,
            sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.AuraInstanceIDOnly,
            sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Reverse,
            candidateFilters = includeFilters(ids),
            initializeFrame = function(button)
                self:InitialiseWinnerButton(button)
            end,
        })

        if not added then
            self.winnerError = err
        end

        pcall(winnerContainer.SetUnit, winnerContainer, "player")
        pcall(winnerContainer.UpdateAllAuras, winnerContainer)

        self.winnerContainer = winnerContainer
    else
        self.winnerError = winnerShellErr
    end

    self.containers = containers

    return containers
end

function DefensiveIndicator:UpdateContainerFilters()
    if not self.containers then
        return
    end

    for category, container in pairs(self.containers) do
        local ids = self:GetTrackedIds(category)
        local applied, err = pcall(container.SetAuraGroupCandidateFilters, container, "defensive", includeFilters(ids))

        if not applied then
            self.containerError = err
        end

        pcall(container.SetAuraGroupMaxFrameCount, container, "defensive", ids and 1 or 0)
        pcall(container.UpdateAllAuras, container)
    end

    if self.winnerContainer then
        local ids = self:GetWinnerIds()
        local applied, err = pcall(self.winnerContainer.SetAuraGroupCandidateFilters, self.winnerContainer, "defensive", includeFilters(ids))

        if not applied then
            self.winnerError = err
        end

        pcall(self.winnerContainer.SetAuraGroupMaxFrameCount, self.winnerContainer, "defensive", ids and 1 or 0)
        pcall(self.winnerContainer.UpdateAllAuras, self.winnerContainer)
    end
end

function DefensiveIndicator:SetContainersShown(shown)
    local alpha = shown and 1 or 0

    for _, container in pairs(self.containers or {}) do
        container:SetAlpha(alpha)
        container:SetShown(shown)
    end

    if self.winnerContainer then
        self.winnerContainer:SetAlpha(alpha)
        self.winnerContainer:SetShown(shown)
    end
end

function DefensiveIndicator:RestyleRings()
    local landed = true

    for _, ring in ipairs(self.rings or {}) do
        if ring.button then
            local width, height = self:GetDisplaySize()

            landed = pcall(PixelUtil.SetSize, ring.button, width, height) and landed
        end

        landed = pcall(self.StyleRing, self, ring) and landed
        landed = pcall(self.ColorRing, self, ring, ring.category) and landed
    end

    for _, winner in ipairs(self.winners or {}) do
        landed = pcall(self.StyleWinnerText, self, winner) and landed

        self:ApplyDurationText(winner.button, winner.duration)
    end

    self.restyleDenied = not landed
end

function DefensiveIndicator:UpdateCarriedState()
    local carried = (UnitOnTaxi("player") or UnitInVehicle("player")) and true or false

    if carried == self.carried then
        return
    end

    self.carried = carried

    self:SetContainersShown(self.db.enabled and not carried)

    if carried then
        return
    end

    for _, container in pairs(self.containers or {}) do
        pcall(container.UpdateAllAuras, container)
    end

    if self.winnerContainer then
        pcall(self.winnerContainer.UpdateAllAuras, self.winnerContainer)
    end
end