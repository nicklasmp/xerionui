local addonName, XerionUIFeatures = ...
local moduleName = "CursorCircle"
local E = XerionUIFeatures.E

local CursorCircle = XerionUIFeatures:NewModule(moduleName)

CursorCircle.CursorTextures = {
    ["Interface\\AddOns\\XerionUI-Plugin\\Media\\textures\\ItruliaCircleThin.tga"] = "Thin",
    ["Interface\\AddOns\\XerionUI-Plugin\\Media\\textures\\ItruliaCircleMedium.tga"] = "Medium",
    ["Interface\\AddOns\\XerionUI-Plugin\\Media\\textures\\ItruliaCircleThick.tga"] = "Thick",
}

local function OnUpdate(self)
    if CursorCircle.db.onlyDuringCombat and not PlayerIsInCombat() then
        self:SetAlpha(0)
        return
    end

    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = floor(x / scale + 0.5), floor(y / scale + 0.5)

    if x ~= self.previousX or y ~= self.previousY then
        self.previousX = x
        self.previousY = y
        self:SetAlpha(1)
        PixelUtil.SetPoint(self, "CENTER", UIParent, "BOTTOMLEFT", x, y)
    end
end

function CursorCircle:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame.texture = frame:CreateTexture("$parent_Texture", "OVERLAY")
    frame.texture:SetAllPoints(frame)

    function frame:UpdateStyles()
        PixelUtil.SetSize(self, CursorCircle.db.size, CursorCircle.db.size)
        self.texture:SetTexture(CursorCircle.db.displayTexture)
        self.texture:SetVertexColor(CursorCircle.db.color.r, CursorCircle.db.color.g, CursorCircle.db.color.b, CursorCircle.db.color.a)
    end

    return frame
end

function CursorCircle:EnsureFrame()
    if self.frame then
        return self.frame
    end

    self.frame = self:GenerateFrame(addonName .. moduleName)

    return self.frame
end

function CursorCircle:OnInitialize()
    local profile = XerionUIFeatures.db.profile
    profile[moduleName] = profile[moduleName] or self:GetDefaults()
    self.db = profile[moduleName]
end

function CursorCircle:RefreshConfig()
    local profile = XerionUIFeatures.db.profile
    profile[moduleName] = profile[moduleName] or self:GetDefaults()
    self.db = profile[moduleName]

    if self.db.enabled then
        local frame = self:EnsureFrame()

        frame:Show()
        frame:UpdateStyles()
        frame:SetScript("OnUpdate", OnUpdate)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
end

function CursorCircle:OnEnable()
    self:RefreshConfig()
end

function CursorCircle:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
