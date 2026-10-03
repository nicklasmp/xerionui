local addonName, XerionUIFeatures = ...

local moduleName = "MovementAlert"
local MovementAlert = XerionUIFeatures:GetModule(moduleName)

MovementAlert.pageDisplay = "Movement Alert"
MovementAlert.pageTrackedSpells = "Tracked Spells"
MovementAlert.pageTimeSpiral = "Time Spiral"
MovementAlert.pageTimeSpiralSpells = "Spiral Spells"

function MovementAlert:PreparePreview(frame, page)
    frame:CacheMovementId()

    if page == self.pageTimeSpiral or page == self.pageTimeSpiralSpells then
        frame.text:SetText(CreateColor(
            self.db.timeSpiralColor.r,
            self.db.timeSpiralColor.g,
            self.db.timeSpiralColor.b,
            self.db.timeSpiralColor.a
        ):WrapTextInColorCode(self.db.timeSpiralText .. "\n" .. string.format("%." .. self.db.precision .. "f", 7.4)))
    else
        frame.text:SetText("No " .. (frame.movementName or "movement ability") .. "\n" .. string.format("%." .. self.db.precision .. "f", 15.3))
    end

    frame.text:Show()
    frame:UpdateStyles()
end
