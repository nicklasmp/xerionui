local addonName, XerionUIFeatures = ...

local moduleName = "FlyingBar"
local FlyingBar = XerionUIFeatures:GetModule(moduleName)

function FlyingBar:PreparePreview(frame)
    frame:SetAlpha(1)
    frame:Show()

    for index, bar in ipairs(frame.vigor) do
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(index < #frame.vigor and 1 or 0.35)
    end

    for index, bar in ipairs(frame.secondWind) do
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(index < #frame.secondWind and 1 or 0)
    end

    frame.speed:SetValue(select(2, frame.speed:GetMinMaxValues()) / 2)
end
