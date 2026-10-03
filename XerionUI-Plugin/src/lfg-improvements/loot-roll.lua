local addonName, XerionUIFeatures = ...

local moduleName = "LFGImprovements"
local LFGImprovements = XerionUIFeatures:GetModule(moduleName)

local lootRollLinkHandler = "lfg-loot-roll"

local rollTypes = {
    pass = 0,
    need = 1,
    greed = 2,
    disenchant = 3,
    transmog = 4,
}

-- the default ui keeps at most four roll frames around and reuses them
local numLootRollFrames = 4

local disabledUntilReload = false
local reminded = false

local function RCLootCouncilHandlesLoot()
    local rc = _G.RCLootCouncil

    if not rc or rc.enabled == false then
        return false
    end

    return rc.handleLoot == true
end

-- rolling through the api leaves the frame on screen with dead buttons, the default ui only tears it down from its own button handlers
local function HideLootRollFrame(rollId)
    local container = _G.GroupLootContainer
    local removeFrame = _G.GroupLootContainer_RemoveFrame

    if not container or not removeFrame then
        return
    end

    for i = 1, numLootRollFrames do
        local frame = _G["GroupLootFrame" .. i]

        if frame and frame:IsShown() and frame.rollID == rollId then
            removeFrame(container, frame)
        end
    end
end

local function Remind(label, link)
    if reminded then
        return
    end

    reminded = true

    XerionUIFeatures:Print(("Rolled |cffffff00%s|r on %s because you can't roll need for it. %s or %s"):format(
        label,
        link or "an item",
        XerionUIFeatures:ChatLink(lootRollLinkHandler, "off", "Turn this off"),
        XerionUIFeatures:ChatLink(lootRollLinkHandler, "session", "Turn this off until reload")
    ))
end

function LFGImprovements:AutoRollLoot(rollId)
    if not rollId or disabledUntilReload then
        return
    end

    if RCLootCouncilHandlesLoot() then
        return
    end

    local _, _, _, _, _, canNeed, canGreed, _, _, _, _, _, canTransmog = GetLootRollItemInfo(rollId)

    -- nil means the roll is already gone, true means the player gets to make the call
    if canNeed == nil or canNeed then
        return
    end

    local rollType, label

    if canTransmog then
        rollType, label = rollTypes.transmog, "Transmog"
    elseif canGreed then
        rollType, label = rollTypes.greed, "Greed"
    else
        return
    end

    local link = GetLootRollItemLink(rollId)

    -- other addons can still be reshuffling the group loot frame when the event fires, rclc delays its own rolls by the same amount for that reason
    C_Timer.After(0.05, function()
        RollOnLoot(rollId, rollType)
        HideLootRollFrame(rollId)
    end)

    Remind(label, link)
end

function LFGImprovements:RemindAutoLootRoll()
    if disabledUntilReload then
        return
    end

    XerionUIFeatures:Print(("Items you can't roll need for will be rolled |cffffff00greed / transmog|r automatically. %s or %s"):format(
        XerionUIFeatures:ChatLink(lootRollLinkHandler, "off", "Turn this off"),
        XerionUIFeatures:ChatLink(lootRollLinkHandler, "session", "Turn this off until reload")
    ))
end

XerionUIFeatures:RegisterChatLink(lootRollLinkHandler, function(payload)
    if payload == "session" then
        disabledUntilReload = true

        XerionUIFeatures:Print("Loot will no longer be rolled for automatically until reload.")

        return
    end

    if payload ~= "off" then
        return
    end

    LFGImprovements.db.autoLootRoll.enabled = false
    LFGImprovements:RefreshConfig()

    XerionUIFeatures:Print("Automatic greed / transmog rolls are now turned off.")
end)
