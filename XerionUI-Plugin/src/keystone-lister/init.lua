local addonName, XerionUIFeatures = ...
local moduleName = "KeystoneLister"

local LSM = XerionUIFeatures.LSM
local LEM = XerionUIFeatures.LEM
local E = XerionUIFeatures.E

local KeystoneLister = XerionUIFeatures:NewModule(moduleName)

-- No state for "cannot list": without lead the button is hidden outright, so there is
-- nothing for it to say.
KeystoneLister.states = {
    LIST = "LIST",
    DELIST = "DELIST",
}

local labels = {
    LIST = "List Key",
    DELIST = "Delist",
}

KeystoneLister.playstyleOrder = {0, 1, 2, 3, 4}

function KeystoneLister:GetPlaystyles()
    local values = {[0] = rawget(_G, "NONE") or "None"}

    for index = 1, 4 do
        values[index] = rawget(_G, "GROUP_FINDER_GENERAL_PLAYSTYLE" .. index)
    end

    return values
end

function KeystoneLister:GetKeystone()
    local getOwned = C_LFGList and C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel

    if not getOwned then
        return nil
    end

    local activityId, groupId, level = getOwned()

    if not activityId then
        activityId, groupId, level = getOwned(true)
    end

    if not activityId then
        return nil
    end

    return activityId, level, groupId
end

function KeystoneLister:OwnsKeystone()
    local getMap = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID
    local mapId = getMap and getMap()

    return mapId ~= nil and mapId > 0
end

local function requestActivities()
    if not (C_LFGList and C_LFGList.RequestAvailableActivities) then
        return
    end

    C_LFGList.RequestAvailableActivities()
end

function KeystoneLister:IsListed()
    return C_LFGList.HasActiveEntryInfo()
end

function KeystoneLister:HasPermission()
    return not IsInGroup() or UnitIsGroupLeader("player")
end

function KeystoneLister:IsMaxLevel()
    return UnitLevel("player") >= GetMaxLevelForPlayerExpansion()
end

function KeystoneLister:GetState()
    if self:IsListed() then
        return self.states.DELIST
    end

    return self.states.LIST
end

function KeystoneLister:GetLabel(state)
    return labels[state] or labels.LIST
end

function KeystoneLister:GetTooltip(state)
    if state == self.states.DELIST then
        return "Removes your group from the group finder."
    end

    return "Pick a keystone from the group to list your group. |cffff8000Due to a limitation by the WoW API|r you will have to adjust the title yourself."
end

-- Blizzard's group finder loads on demand, so PVEFrame_ShowFrame does not exist until something has loaded it.
function KeystoneLister:OpenGroupFinder()
    if not PVEFrame_ShowFrame and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_GroupFinder")
    end

    if not PVEFrame_ShowFrame then
        return false
    end

    PVEFrame_ShowFrame("GroupFinderFrame", "LFGListPVEStub")

    return true
end

local verifyDelay = 0.5

function KeystoneLister:FallBackToGroupFinder()
    if self:IsListed() then
        return
    end

    self:OpenGroupFinder()

    -- Dungeons is pre-picked so you just have to click the button
    self:SelectDungeonCategory()
    XerionUIFeatures:Print("|cffff8000Due to a limitation by the WoW API|r I could not list the key without a title. Opened the group finder with |cffffd100Dungeons|r pre-selected. Click |cffffd100Start a Group|r once, then the button starts working.")
end

function KeystoneLister:OpenListingEdit()
    if not self:OpenGroupFinder() then
        return false
    end

    local viewer = LFGListFrame and LFGListFrame.ApplicationViewer
    local editButton = viewer and viewer.EditButton

    if editButton and pcall(editButton.Click, editButton) then
        return true
    end

    -- No Edit button on this client. The same two steps by hand.
    local panel = LFGListFrame and LFGListFrame.EntryCreation
    if not (panel and LFGListEntryCreation_SetEditMode and LFGListFrame_SetActivePanel) then
        return false
    end

    return pcall(LFGListEntryCreation_SetEditMode, panel, true) and pcall(LFGListFrame_SetActivePanel, LFGListFrame, panel)
end

local function requiredItemLevel(wanted)
    local _, equipped = GetAverageItemLevel()

    return math.floor(math.min(wanted or 0, equipped or 0))
end

local function requiredRating(wanted)
    local score = C_ChallengeMode.GetOverallDungeonScore and C_ChallengeMode.GetOverallDungeonScore() or 0

    return math.floor(math.min(wanted or 0, score or 0))
end

function KeystoneLister:NoticeTitle()
    if self.titleNoticeShown then
        return
    end

    self.titleNoticeShown = true
    XerionUIFeatures:Print("|cffff8000Due to a limitation by the WoW API|r only Blizzard's own group finder may set the title of a group. Edit the title and then press |cffffd100Update|r.")
end

function KeystoneLister:SelectDungeonCategory()
    local selection = LFGListFrame and LFGListFrame.CategorySelection

    if not (selection and LFGListCategorySelection_SelectCategory) then
        return false
    end

    local categoryId = rawget(_G, "GROUP_FINDER_CATEGORY_ID_DUNGEONS") or 2

    return pcall(LFGListCategorySelection_SelectCategory, selection, categoryId, 0)
end

function KeystoneLister:SendListing(activityId)
    return C_LFGList.CreateListing({
        activityIDs = {activityId},
        isAutoAccept = false,
        isCrossFactionListing = true,
        isPrivateGroup = false,
        playstyle = Enum.LFGEntryPlaystyle and Enum.LFGEntryPlaystyle.None or 0,
        generalPlaystyle = self.db.playstyle or 0,
        requiredDungeonScore = requiredRating(self.db.requiredRating),
        requiredItemLevel = requiredItemLevel(self.db.itemLevel),
    })
end

function KeystoneLister:AfterListed()
    if not self:OpenListingEdit() then
        return
    end

    self:NoticeTitle()
end

function KeystoneLister:ListActivity(activityId)
    if not activityId then
        XerionUIFeatures:Print("|cffff0000That keystone's dungeon is not in the group finder.|r")

        return
    end

    if not self:SendListing(activityId) then
        self:FallBackToGroupFinder()

        return
    end

    C_Timer.After(verifyDelay, function()
        if not self:IsListed() then
            self:FallBackToGroupFinder()

            return
        end

        self:AfterListed()
    end)
end

function KeystoneLister:DelistKeystone()
    if not self:IsListed() then
        return
    end

    C_LFGList.RemoveListing()
end

function KeystoneLister:ShowKeystoneMenu(anchor)
    self:RequestGroupKeystones()

    local keystones = self:GetGroupKeystones()

    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle("List a keystone")

        if #keystones == 0 then
            root:CreateTitle("|cff808080No keystones found|r")

            return
        end

        for _, keystone in ipairs(keystones) do
            local label = ("%s |cffffd100+%d|r %s"):format(keystone.name, keystone.level, keystone.dungeon)

            root:CreateButton(label, function()
                KeystoneLister:ListActivity(KeystoneLister:GetActivityForChallengeMap(keystone.challengeMapId))
            end)
        end
    end)
end

function KeystoneLister:ShouldShow()
    if not self.db.enabled then
        return false
    end

    if XerionUIFeatures.testMode then
        return true
    end

    if not self:IsMaxLevel() then
        return false
    end

    if IsInRaid() or GetNumGroupMembers() >= 5 then
        return false
    end

    -- Nothing the button offers can be done without lead: listing and delisting are
    -- both the leader's, so the button goes away rather than sitting there dimmed.
    if not self:HasPermission() then
        return false
    end

    return self:IsListed() or #self:GetGroupKeystones() > 0
end

local function mouseoverAlpha(frame)
    if frame:IsMouseOver() then
        return KeystoneLister.db.mouseoverAlpha or 1
    end

    return KeystoneLister.db.mouseoverFadeAlpha or 0
end

local function OnMouseoverUpdate(self, elapsed)
    self.mouseoverElapsed = (self.mouseoverElapsed or 0) + elapsed

    if self.mouseoverElapsed < 0.1 then
        return
    end

    self.mouseoverElapsed = 0
    self:SetAlpha(mouseoverAlpha(self))
end

local function OnEvent(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then
            C_MythicPlus.RequestMapInfo()
        end

        requestActivities()
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        KeystoneLister:RequestGroupKeystones()
    end

    if event == "LFG_LIST_AVAILABILITY_UPDATE" then
        KeystoneLister:ResetActivityMap()
    end

    if event ~= "LFG_LIST_AVAILABILITY_UPDATE" and KeystoneLister:OwnsKeystone() and not KeystoneLister:GetKeystone() then
        requestActivities()
    end

    self:UpdateStyles()
    self:UpdateVisibility()
end

function KeystoneLister:GenerateFrame(name, parent)
    local frame = CreateFrame("frame", name, parent or UIParent)
    PixelUtil.SetPoint(frame, "CENTER", frame:GetParent() or UIParent, "CENTER", 0, 0)
    PixelUtil.SetSize(frame, 80, 20)

    local btn = CreateFrame("Button", "$parent_Button", frame)
    btn:SetAllPoints()
    frame.button = btn

    btn.bg = XerionUIFeatures:CreateBackground(btn)
    btn.border = XerionUIFeatures:CreateBorder(btn)

    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetPoint("CENTER")
    btn.text:SetFont(LSM:Fetch("font", "GothamNarrowBlack"), 12, "OUTLINE")

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.12)

    btn:SetScript("OnClick", function(button)
        if frame.isPreview then
            return
        end

        if not self:HasPermission() then
            return
        end

        if self:IsListed() then
            self:DelistKeystone()

            return
        end

        if not (MenuUtil and MenuUtil.CreateContextMenu) then
            self:ListActivity(self:GetKeystone())

            return
        end

        self:ShowKeystoneMenu(button)
    end)

    btn:SetScript("OnEnter", function(button)
        if not KeystoneLister.db.showTooltips then
            return
        end

        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:AddLine("Keystone Lister")
        GameTooltip:AddLine(KeystoneLister:GetTooltip(frame.state), 1, 1, 1, true)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    function frame:UpdateButton()
        local font = KeystoneLister.db.font
        local justify = font.justifyH or "CENTER"

        self.state = self.isPreview and KeystoneLister.states.LIST or KeystoneLister:GetState()

        btn.bg:SetColor(KeystoneLister.db.buttonColor.r, KeystoneLister.db.buttonColor.g, KeystoneLister.db.buttonColor.b, KeystoneLister.db.buttonColor.a)

        btn.text:SetText(KeystoneLister:GetLabel(self.state))
        btn.text:SetFont(LSM:Fetch("font", font.fontFamily), font.fontSize, font.fontOutline)
        btn.text:SetTextColor(KeystoneLister.db.textColor.r, KeystoneLister.db.textColor.g, KeystoneLister.db.textColor.b, KeystoneLister.db.textColor.a)
        btn.text:SetJustifyH(justify)
        btn.text:ClearAllPoints()

        if justify == "LEFT" then
            PixelUtil.SetPoint(btn.text, "LEFT", btn.text:GetParent() or UIParent, "LEFT", KeystoneLister.db.paddingX, 0)
        elseif justify == "RIGHT" then
            PixelUtil.SetPoint(btn.text, "RIGHT", btn.text:GetParent() or UIParent, "RIGHT", -KeystoneLister.db.paddingX, 0)
        else
            btn.text:SetPoint("CENTER")
        end

        if font.fontOutline ~= "OUTLINESLUG" then
            btn.text:SetShadowColor(font.fontShadowColor.r, font.fontShadowColor.g, font.fontShadowColor.b, font.fontShadowColor.a)
            btn.text:SetShadowOffset(font.fontShadowXOffset, font.fontShadowYOffset)
        else
            btn.text:SetShadowColor(0, 0, 0, 0)
            btn.text:SetShadowOffset(0, 0)
        end

        PixelUtil.SetSize(
            self,
            math.ceil(btn.text:GetStringWidth()) + KeystoneLister.db.paddingX * 2,
            math.ceil(math.max(btn.text:GetStringHeight(), font.fontSize)) + KeystoneLister.db.paddingY * 2
        )

        btn:SetAlpha(1)
    end

    function frame:UpdateMouseover()
        if self.isPreview then
            return
        end

        if not KeystoneLister.db.mouseover or not self:IsShown() then
            self:SetScript("OnUpdate", nil)
            self:SetAlpha(1)

            return
        end

        self.mouseoverElapsed = 0
        self:SetAlpha(mouseoverAlpha(self))
        self:SetScript("OnUpdate", OnMouseoverUpdate)
    end

    function frame:UpdateVisibility()
        if self.isPreview then
            self:Show()

            return
        end

        self:SetShown(KeystoneLister:ShouldShow())
        self:UpdateMouseover()
    end

    function frame:UpdateStyles()
        if not E then
            self:ClearAllPoints()
            PixelUtil.SetPoint(self, KeystoneLister.db.point.point, self:GetParent() or UIParent, KeystoneLister.db.point.point, KeystoneLister.db.point.x, KeystoneLister.db.point.y)
        end

        self:SetFrameStrata(KeystoneLister.db.font.frameStrata or "MEDIUM")
        self:SetFrameLevel(KeystoneLister.db.font.frameLevel or 1)
        self:UpdateButton()
    end

    return frame
end

function KeystoneLister:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = self:GenerateFrame(addonName .. moduleName)
    self.frame = frame

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PARTY_LEADER_CHANGED")
    frame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    frame:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")

    if E then
        E:CreateMover(frame, frame:GetName() .. "Mover", moduleName, nil,
            nil,
            nil,
            "ALL,ITRULIA",
            function()
                return self.db.enabled
            end,
            addonName .. "," .. moduleName
        )
    elseif XerionUIFeatures.EUI then
        XerionUIFeatures:CreateEUIMover(self, frame, moduleName)
    else
        LEM:AddFrame(frame, function(_, layoutName, point, x, y)
            self.db.point = {point = point, x = x, y = y}
        end, self:GetDefaults().point)
    end

    return frame
end

function KeystoneLister:LoadDB()
    local profile = XerionUIFeatures.db.profile
    profile[moduleName] = profile[moduleName] or self:GetDefaults()

    return profile[moduleName]
end

function KeystoneLister:OnInitialize()
    self.db = self:LoadDB()
end

function KeystoneLister:RefreshConfig()
    self.db = self:LoadDB()

    if self.db.enabled then
        local frame = self:EnsureFrame()

        OnEvent(frame, "PLAYER_ENTERING_WORLD")

        frame:SetScript("OnEvent", OnEvent)
        frame:UpdateStyles()
        frame:UpdateVisibility()
    elseif self.frame then
        self.frame:SetScript("OnEvent", nil)
        self.frame:SetScript("OnUpdate", nil)
        self.frame:SetAlpha(1)
        self.frame:Hide()
    end
end

function KeystoneLister:ApplyFontSettings(font)
    self.db.font.fontFamily = font.fontFamily
    self.db.font.fontOutline = font.fontOutline
    self.db.font.fontShadowColor = font.fontShadowColor
    self.db.font.fontShadowXOffset = font.fontShadowXOffset
    self.db.font.fontShadowYOffset = font.fontShadowYOffset
    self.db.font.justifyH = font.justifyH

    if self.frame then
        self.frame:UpdateStyles()
    end
end

function KeystoneLister:OnEnable()
    self:RefreshConfig()
end

function KeystoneLister:ToggleTestMode()
    if not self.db.enabled or not self.frame then
        return
    end

    self.frame:UpdateVisibility()
end

function KeystoneLister:RegisterOptions(parentOptions)
    parentOptions.args[moduleName] = self:GetOptions(function()
        if self.frame then
            self.frame:UpdateStyles()
            self.frame:UpdateVisibility()
        end

        XerionUIFeatures:RefreshPreview(self)
    end)
end
