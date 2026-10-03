local addonName, XerionUIFeatures = ...

local moduleName = "LFGImprovements"
local LFGImprovements = XerionUIFeatures:GetModule(moduleName)

local noDifficultyKey = "none"

local difficultyKinds = {
    {
        key = "dungeon",
        label = "Dungeon",
        setting = "autoDungeonDifficulty",
        difficulties = {noDifficultyKey, 1, 2, 23},
        Get = function() return GetDungeonDifficultyID() end,
        Set = function(difficulty) SetDungeonDifficultyID(difficulty) end,
    },
    {
        key = "raid",
        label = "Raid",
        setting = "autoRaidDifficulty",
        difficulties = {noDifficultyKey, 14, 15, 16},
        Get = function() return GetRaidDifficultyID() end,
        Set = function(difficulty) SetRaidDifficultyID(difficulty) end,
    },
}

local difficultyKindsByKey = {}
for _, kind in ipairs(difficultyKinds) do
    difficultyKindsByKey[kind.key] = kind
end

local difficultyLinkHandler = "lfg-difficulty"

local function CanChangeDifficulty()
    return not IsInInstance() and not (IsInGroup() and not UnitIsGroupLeader("player"))
end

local function DifficultyName(difficulty)
    return difficulty and GetDifficultyInfo(difficulty) or "unknown"
end

function LFGImprovements:ApplyDifficulties()
    if not CanChangeDifficulty() then
        return
    end

    for _, kind in ipairs(difficultyKinds) do
        local wanted = self.db[kind.setting].difficulty
        local current = kind.Get()

        if wanted and current ~= wanted and not kind.ignoredUntilReload then
            kind.Set(wanted)
            kind.previous = current

            XerionUIFeatures:Print(("%s difficulty changed from |cffffff00%s|r to |cffffff00%s|r. %s or %s"):format(
                kind.label,
                DifficultyName(current),
                DifficultyName(wanted),
                XerionUIFeatures:ChatLink(difficultyLinkHandler, "revert:" .. kind.key, "Revert and ignore until reload"),
                XerionUIFeatures:ChatLink(difficultyLinkHandler, "ignore:" .. kind.key, "Ignore until reload")
            ))
        end
    end
end

XerionUIFeatures:RegisterChatLink(difficultyLinkHandler, function(payload)
    local action, key = strsplit(":", payload)
    local kind = difficultyKindsByKey[key]

    if not kind then
        return
    end

    kind.ignoredUntilReload = true

    if action == "ignore" then
        XerionUIFeatures:Print(("%s difficulty will no longer be changed automatically until reload."):format(kind.label))

        return
    end

    if action ~= "revert" or not kind.previous then
        return
    end

    if not CanChangeDifficulty() then
        XerionUIFeatures:Print(("|cffff0000Can't change the %s difficulty right now.|r"):format(kind.label:lower()))

        return
    end

    local previous = kind.previous
    kind.previous = nil
    kind.Set(previous)

    XerionUIFeatures:Print(("%s difficulty reverted to |cffffff00%s|r, it won't be changed automatically until reload."):format(
        kind.label,
        DifficultyName(previous)
    ))
end)

function LFGImprovements:GetDifficultyOptions(key)
    local order = difficultyKindsByKey[key].difficulties
    local values = {}

    for _, difficulty in ipairs(order) do
        if difficulty == noDifficultyKey then
            values[difficulty] = "Don't change"
        else
            values[difficulty] = DifficultyName(difficulty)
        end
    end

    return values, order
end

function LFGImprovements:GetDifficulty(key)
    return self.db[difficultyKindsByKey[key].setting].difficulty or noDifficultyKey
end

function LFGImprovements:SaveDifficulty(key, value)
    local kind = difficultyKindsByKey[key]

    self.db[kind.setting].difficulty = value ~= noDifficultyKey and value or nil
end
