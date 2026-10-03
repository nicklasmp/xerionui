local addonName, XerionUIFeatures = ...

local LSM = XerionUIFeatures.LSM

local moduleName = "SummonHelper"
local SummonHelper = XerionUIFeatures:GetModule(moduleName)

local function ensureDummy(frame)
    if frame.dummy then
        return frame.dummy
    end

    local dummy = CreateFrame("frame", nil, frame, "BackdropTemplate")
    dummy:SetPoint("CENTER")
    PixelUtil.SetSize(dummy, 95, 30)
    dummy:SetBackdrop({
        edgeFile = [[Interface\Buttons\WHITE8x8]],
        bgFile = [[Interface\Buttons\WHITE8x8]],
        edgeSize = 1,
    })
    dummy:SetBackdropBorderColor(0, 0, 0, 1)

    local classColor = C_ClassColor.GetClassColor(XerionUIFeatures.playerClass)
    dummy:SetBackdropColor(classColor.r, classColor.g, classColor.b, 1)

    dummy.name = dummy:CreateFontString(nil, "OVERLAY")
    dummy.name:SetPoint("CENTER")
    dummy.name:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 12, "OUTLINE")
    dummy.name:SetText(UnitName("player"))

    dummy.highlight = CreateFrame("frame", nil, dummy, "BackdropTemplate")
    dummy.highlight:EnableMouse(false)

    frame.dummy = dummy

    return dummy
end

function SummonHelper:PreparePreview(frame)
    frame:HideMessage()

    local dummy = ensureDummy(frame)

    dummy:Show()

    self:AnchorHighlight(dummy.highlight, dummy)
    self:StyleHighlight(dummy.highlight)
    dummy.highlight:Show()
end
