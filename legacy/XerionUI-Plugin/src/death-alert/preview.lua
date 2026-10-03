local addonName, XerionUIFeatures = ...

local moduleName = "DeathAlert"
local DeathAlert = XerionUIFeatures:GetModule(moduleName)

function DeathAlert:PreparePreview(frame)
    frame.text.anim:Stop()

    local name = UnitName("player")
    local _, class = UnitClass("player")
    local classColor = C_ClassColor.GetClassColor(class)

    local displayText = CreateColor(
        self.db.color.r,
        self.db.color.g,
        self.db.color.b,
        self.db.color.a
    ):WrapTextInColorCode(self.db.displayText)

    frame.text:SetText(classColor:WrapTextInColorCode(name) .. " " .. displayText)
    frame.text:SetAlpha(1)
    frame:UpdateStyles()
end
