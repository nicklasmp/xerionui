local addonName, XerionUIFeatures = ...

local moduleName = "RuneforgeAlert"
local RuneforgeAlert = XerionUIFeatures:GetModule(moduleName)

local function defaultSetups()
    local setups = {}

    for _, setup in ipairs(RuneforgeAlert.Setups) do
        local slots = {}

        for _, slot in ipairs(setup.slots) do
            local runes = {}

            for _, enchantId in ipairs(slot.defaults) do
                runes[enchantId] = true
            end

            slots[slot.key] = runes
        end

        setups[setup.key] = slots
    end

    return setups
end

function RuneforgeAlert:GetDefaults()
    return {
        enabled = false,
        displayText = "Check Runeforge",
        color = {r = 1, g = 1, b = 1, a = 1},
        point = {point = "CENTER", x = 0, y = 25},
        setups = defaultSetups(),

        font = {
            fontFamily = "GothamNarrowBlack",
            fontSize = 14,
            fontOutline = "OUTLINE",
            fontShadowColor = {r = 0, g = 0, b = 0, a = 1},
            fontShadowXOffset = 1,
            fontShadowYOffset = -1,
            frameStrata = XerionUIFeatures.FrameStrataSettings.BACKGROUND,
            frameLevel = 1,
            justifyH = XerionUIFeatures.JustifyHSettings.CENTER,
        }
    }
end
