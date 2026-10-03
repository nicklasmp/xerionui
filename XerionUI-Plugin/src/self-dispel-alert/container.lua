local addonName, XerionUIFeatures = ...

local moduleName = "SelfDispelAlert"
local SelfDispelAlert = XerionUIFeatures:GetModule(moduleName)

function SelfDispelAlert:ApplyAlertStrata(display)
    local font = self.db.font

    display:SetFrameStrata(font.frameStrata or "BACKGROUND")
    display:SetFrameLevel((font.frameLevel or 1) + 4)
end

function SelfDispelAlert:InitialiseButton(button, token)
    pcall(button.SetMouseClickEnabled, button, false)

    if button.SetMouseMotionEnabled then
        pcall(button.SetMouseMotionEnabled, button, false)
    end

    pcall(button.SetScale, button, 1)
    button:SetSize(1, 1)
    button:SetPoint("CENTER", self.frame.gate, "CENTER")

    local display = self:CreateDisplay(button)

    display.dispelType = token

    -- Rect from the gate, visibility from the button's parent chain.
    display:SetAllPoints(self.frame.gate)

    self.alerts[#self.alerts + 1] = display

    self:ApplyAlertStrata(display)
    self:StyleDisplay(display)
end

function SelfDispelAlert:EnsureContainers()
    if self.containers then
        return
    end

    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end

    self.containers = {}
    self.alerts = {}

    local gate = self.frame.gate

    for _, token in ipairs(self.dispelTypes) do
        local container = CreateFrame("AuraContainer", nil, gate, "CustomAuraContainerTemplate")
        container:SetPoint("CENTER", gate, "CENTER")
        container:SetSize(1, 1)
        container:SetScale(1)

        container:AddAuraSlot("dispel", "HARMFUL", {
            candidateFilters = {includeDispelTypes = {[token] = true}},
            initializeFrame = function(button)
                SelfDispelAlert:InitialiseButton(button, token)
            end,
        })
        container:SetUnit("player")
        container:UpdateAllAuras()

        self.containers[token] = container
    end
end

function SelfDispelAlert:ApplyCooldownAlpha(target, source)
    local ready = self:IsSourceReady(source)

    if ready ~= nil then
        target:SetAlpha(ready and 1 or 0)

        return
    end

    local ok, duration = pcall(function()
        return C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(source.spellId)
    end)

    if ok and not issecretvalue(duration) and duration ~= nil and target.SetAlphaFromBoolean then
        local applied = pcall(function()
            target:SetAlphaFromBoolean(duration:IsZero())
        end)

        if applied then
            return
        end
    end

    target:SetAlpha(1)
end

function SelfDispelAlert:ApplyContainerGates()
    if not self.containers then
        return
    end

    local gated = self.db.hideOnCooldown and not XerionUIFeatures.testMode

    for token, container in pairs(self.containers) do
        local source = self.typeSources and self.typeSources[token]

        if not source then
            container:SetAlpha(0)
        elseif not gated then
            container:SetAlpha(1)
        else
            self:ApplyCooldownAlpha(container, source)
        end
    end
end

function SelfDispelAlert:ApplyShownGate()
    if not self.containers then
        return
    end

    local shown = self.db.enabled
        and not (UnitOnTaxi("player") or UnitInVehicle("player"))
        and not (self.db.disableInRaid and XerionUIFeatures:InRaid())

    for _, container in pairs(self.containers) do
        container:SetShown(shown)
    end
end

function SelfDispelAlert:RestyleAlerts()
    if not self.alerts then
        return
    end

    local denied = false

    for _, display in ipairs(self.alerts) do
        local ok = pcall(function()
            self:ApplyAlertStrata(display)
            self:StyleDisplay(display)
        end)

        if not ok then
            denied = true
        end
    end

    self.restyleDenied = denied
end
