local addonName, XerionUIFeatures = ...

local moduleName = "DefensiveIndicator"
local DefensiveIndicator = XerionUIFeatures:GetModule(moduleName)

DefensiveIndicator.pageDisplay = "Display"
DefensiveIndicator.pageDefensives = "Defensives"

-- The sample runs on a real cooldown, so the preview needs the same tick the live
-- frame gets or the ring would drain once and then sit empty. Tick re-arms a sample
-- that has run out, and a parked preview is hidden, which stops the script.
function DefensiveIndicator:PreparePreview(frame)
    frame:ShowSample()
    frame:SetScript("OnUpdate", frame.Tick)
end
