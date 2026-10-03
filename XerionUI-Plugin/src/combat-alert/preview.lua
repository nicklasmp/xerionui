local addonName, XerionUIFeatures = ...

local moduleName = "CombatAlert"
local CombatAlert = XerionUIFeatures:GetModule(moduleName)

function CombatAlert:PreparePreview(frame)
    frame.text.anim:Stop()
    frame.text:SetText(self.db.combatStartsText)
    frame.text:SetTextColor(self.db.combatStartsColor.r, self.db.combatStartsColor.g, self.db.combatStartsColor.b, self.db.combatStartsColor.a)
    frame.text:SetAlpha(1)
    frame:UpdateStyles()
end
