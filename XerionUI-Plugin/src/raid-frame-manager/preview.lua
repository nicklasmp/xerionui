local addonName, XerionUIFeatures = ...

local moduleName = "RaidFrameManager"
local RaidFrameManager = XerionUIFeatures:GetModule(moduleName)

RaidFrameManager.pageDisplay = "Display"
RaidFrameManager.pageActions = "Actions"
RaidFrameManager.pagePullTimers = "Pull Timers"

function RaidFrameManager:PreparePreview(frame)
    frame:UpdateStyles()
    frame:Show()
end
