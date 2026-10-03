local addonName, XerionUIFeatures = ...
local moduleName = "LFGImprovements"

local LFGImprovements = XerionUIFeatures:NewModule(moduleName)

local function OnEvent(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local initialLoginOrReload = select(1, ...) or select(2, ...)
        local inInstance = IsInInstance()
        local leftInstance = self.wasInInstance and not inInstance
        self.wasInInstance = inInstance

        if leftInstance or (initialLoginOrReload and not inInstance) then
            -- the group and instance state is still settling right after the loading screen, so give it a moment before asking for a change
            C_Timer.After(1, function()
                LFGImprovements:ApplyDifficulties()
            end)
        end
    end

    if event == "PLAYER_LEVEL_UP" then
        if UnitLevel("player") == GetMaxLevelForPlayerExpansion() then
            LFGImprovements:ApplyDifficulties()
        end
    end

    if LFGImprovements.db.autoLootRoll.enabled then
        if event == "PLAYER_ENTERING_WORLD" then
            if XerionUIFeatures:InRaid() and LFGImprovements.db.autoLootRoll.enabled then
                LFGImprovements:RemindAutoLootRoll()
            end
        end

        if event == "START_LOOT_ROLL" then
            local rollId = ...
            LFGImprovements:AutoRollLoot(rollId)
        end
    end

    if LFGImprovements.db.groupJoinedReminder.enabled then
        if event == "GROUP_LEFT" then
            self.groupName = nil
        end

        if event == "LFG_LIST_JOINED_GROUP" then
            local _, groupName = ...
            self.groupName = groupName
        end

        if event == "LFG_LIST_JOINED_GROUP" or event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
            local created = ...
            if not created then
                return
            end

            local entryData = C_LFGList.GetActiveEntryInfo()
            if not entryData then
                return
            end

            local activityId = nil
            for _, id in ipairs(entryData.activityIDs) do
                activityId = id
                break;
            end

            if not activityId then
                return
            end

            local activityInfo = C_LFGList.GetActivityInfoTable(activityId)
            if not activityInfo or (not activityInfo.isMythicPlusActivity and not activityInfo.isMythicActivity) then
                return
            end

            local fullName = activityInfo.fullName .. " " .. (self.groupName or "")
            XerionUIFeatures:Print("Joined: " .. fullName)
        end
    end
end

function LFGImprovements:GenerateFrame(name, parent)
    return CreateFrame("frame", name, parent or UIParent)
end

function LFGImprovements:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame.groupName = nil
    frame.wasInInstance = IsInInstance()

    frame:RegisterEvent("GROUP_LEFT")
    frame:RegisterEvent("LFG_LIST_JOINED_GROUP")
    frame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_LEVEL_UP")
    frame:RegisterEvent("START_LOOT_ROLL")

    return frame
end

function LFGImprovements:LoadDB()
    local profile = XerionUIFeatures.db.profile
    profile.LFGImprovements = profile.LFGImprovements or self:GetDefaults()
    local db = profile.LFGImprovements

    -- Migration
    db.autoLootRoll = db.autoLootRoll or self:GetDefaults().autoLootRoll
    db.autoDungeonDifficulty = db.autoDungeonDifficulty or self:GetDefaults().autoDungeonDifficulty
    db.autoRaidDifficulty = db.autoRaidDifficulty or self:GetDefaults().autoRaidDifficulty

    return db
end

function LFGImprovements:OnInitialize()
    self.db = self:LoadDB()
end

function LFGImprovements:RefreshConfig()
    self.db = self:LoadDB()

    if self.db.enabled then
        self:EnsureFrame():SetScript("OnEvent", OnEvent)
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
    end
end

function LFGImprovements:OnEnable()
    LFDRoleCheckPopupAcceptButton:SetScript("OnShow", function()
        if self.db.enabled and self.db.autoAcceptRole.enabled then
            LFDRoleCheckPopupAcceptButton:Click()
        end
    end)

    self:RefreshConfig()
end

function LFGImprovements:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
    end)
end
