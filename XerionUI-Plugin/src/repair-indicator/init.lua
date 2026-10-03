local addonName, XerionUIFeatures = ...
local moduleName = "RepairIndicator"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local RepairIndicator = XerionUIFeatures:NewModule(moduleName)

local function OnEvent(self, event, ...)
    if XerionUIFeatures.testMode then
        self.text:Show()
        return
    end

    if not PlayerIsInCombat() and self:RequiresRepair() then
        self.text:Show()
    else
        self.text:Hide()
    end
end

function RepairIndicator:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 300)
    PixelUtil.SetSize(frame, 28, 28)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("CENTER")
    frame.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 28, "OUTLINE")
    frame.text:SetText("**Low Durability!**")
    frame.text:SetTextColor(1, 1, 1)
    frame.text:SetJustifyH("CENTER")
    frame.text:Hide()

    function frame:RequiresRepair()
        for slot = 1, 18 do
            local current, maximum = GetInventoryItemDurability(slot)

            if current and maximum then
                if current == 0 or current / maximum < 0.2 then
                    return true
                end
            end
        end

        return false
    end

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, RepairIndicator.db.point.point, self:GetParent() or UIParent, RepairIndicator.db.point.point, RepairIndicator.db.point.x, RepairIndicator.db.point.y)
        end

        self:SetFrameStrata(RepairIndicator.db.font.frameStrata or "BACKGROUND")
        self:SetFrameLevel(RepairIndicator.db.font.frameLevel or 1)
        self.text:ClearAllPoints()
        self.text:SetPoint(RepairIndicator.db.font.justifyH or "CENTER")
        self.text:SetJustifyH(RepairIndicator.db.font.justifyH or "CENTER")
        self.text:SetText(RepairIndicator.db.displayText)
        self.text:SetTextColor(RepairIndicator.db.color.r, RepairIndicator.db.color.g, RepairIndicator.db.color.b, RepairIndicator.db.color.a)
        if RepairIndicator.db.font.fontOutline ~= "OUTLINESLUG" then
            self.text:SetShadowColor(RepairIndicator.db.font.fontShadowColor.r, RepairIndicator.db.font.fontShadowColor.g, RepairIndicator.db.font.fontShadowColor.b, RepairIndicator.db.font.fontShadowColor.a)
            self.text:SetShadowOffset(RepairIndicator.db.font.fontShadowXOffset, RepairIndicator.db.font.fontShadowYOffset)
        else
            self.text:SetShadowColor(0, 0, 0, 0)
            self.text:SetShadowOffset(0, 0)
        end
        self.text:SetFont(LSM:Fetch("font", RepairIndicator.db.font.fontFamily), RepairIndicator.db.font.fontSize, RepairIndicator.db.font.fontOutline)

        PixelUtil.SetSize(self, self.text:GetStringWidth(), self.text:GetStringHeight())
    end

    return frame
end

function RepairIndicator:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    frame:RegisterEvent("PLAYER_DEAD")
    frame:RegisterEvent("PLAYER_ALIVE")

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

function RepairIndicator:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile.RepairIndicator = profile.RepairIndicator or self:GetDefaults()
    self.db = profile.RepairIndicator
end

function RepairIndicator:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile.RepairIndicator = profile.RepairIndicator or self:GetDefaults()
    self.db = profile.RepairIndicator

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

function RepairIndicator:ApplyFontSettings(font)
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

function RepairIndicator:OnEnable()
    self:RefreshConfig()
end

function RepairIndicator:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    OnEvent(self.frame)
end

function RepairIndicator:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
