local addonName, XerionUIFeatures = ...
local LSM = XerionUIFeatures.LSM

XerionUIFeatures.MergeDeep_Delete_Key = {}

function XerionUIFeatures:MergeDeep(a, b)
    local result = {}

    for k, v in pairs(a) do
        if type(v) == "table" then
            result[k] = self:MergeDeep(v, {})
        else
            result[k] = v
        end
    end

    for k, v in pairs(b) do
        if v == XerionUIFeatures.MergeDeep_Delete_Key then
          result[k] = nil
        elseif type(v) == "table" and type(result[k]) == "table" then
            result[k] = self:MergeDeep(result[k], v)
        else
            result[k] = v
        end
    end

    return result
end

XerionUIFeatures.FrameStrataSettings = {
    BACKGROUND = "BACKGROUND",
    LOW = "LOW",
    MEDIUM = "MEDIUM",
    HIGH = "HIGH",
    DIALOG = "DIALOG",
    FULLSCREEN = "FULLSCREEN",
    FULLSCREEN_DIALOG = "FULLSCREEN_DIALOG",
    TOOLTIP = "TOOLTIP",
}

XerionUIFeatures.OutlineSettings = {
    NONE = "None",
    OUTLINE = "Outline",
    OUTLINESLUG = "Slug",
    THICKOUTLINE = "Thick Outline",
    MONOCHROME = "Monochrome"
}

XerionUIFeatures.JustifyHSettings = {
    CENTER = "CENTER",
    LEFT = "LEFT",
    RIGHT = "RIGHT",
}

function XerionUIFeatures:TTSPreviewButton(order, getMessage, getVolume, getVoice, disabled)
    return {
        order = order,
        type = "execute",
        name = "Preview",
        width = 0.5,
        func = function()
            local message = getMessage()

            if message and message ~= "" then
                C_VoiceChat.SpeakText(getVoice and getVoice() or 0, message, 1, getVolume and getVolume() or 100, true)
            end
        end,
        disabled = function()
            local message = getMessage()

            return not message or message == "" or (disabled and disabled())
        end,
    }
end

function XerionUIFeatures:TTSVoiceOption(order, get, set, disabled)
    local values, sortOrder = self:GetTTSVoiceOptions()

    return {
        order = order,
        type = "select",
        name = "Voice",
        values = values,
        sorting = sortOrder,
        get = get,
        set = set,
        disabled = disabled,
    }
end

-- `getFont` returns the font settings table, rather than being that table.
--
-- The options are built once, at login, but the table they edit is not the same one
-- forever: switching profiles points the module at the new profile's table, and so
-- does resetting a module or copying one over from another profile. A captured
-- table would leave every control below reading and writing one that nothing else
-- points at any more, so the panel would show the old profile's font and edits to it
-- would go nowhere. Reading it per call is what keeps them on the live one.
function XerionUIFeatures:createFontOptions(getFont, onChange, additionalOptions)
    local function shadowHidden()
        return getFont().fontOutline == "OUTLINESLUG"
    end

    return XerionUIFeatures:MergeDeep({
        fontSize = {
            order = 10,
            type = "range",
            name = "Size",
            min = 1,
            max = 68,
            step = 1,
            width = 0.75,
            get = function()
                return getFont().fontSize
            end,
            set = function(_, value)
                getFont().fontSize = value
                
                if onChange then
                    onChange()
                end
            end
        },
        font = {
            order = 20,
            type = "select",
            width = 0.75,
            dialogControl = "LSM30_Font",
            name = "Font",
            values = LSM:HashTable("font"),
            get = function()
                return getFont().fontFamily
            end,
            set = function(_, value)
                getFont().fontFamily = value
                
                if onChange then
                    onChange()
                end
            end
        },
        fontOutline = {
            order = 30,
            type = "select",
            width = 0.75,
            name = "Outline",
            values = XerionUIFeatures.OutlineSettings,
            get = function()
                return getFont().fontOutline
            end,
            set = function(_, value)
                getFont().fontOutline = value ~= "NONE" and value or nil
                
                if onChange then
                    onChange()
                end
            end
        },
        justifyH = {
            order = 40,
            type = "select",
            name = "Justify",
            width = 0.75,
            values = XerionUIFeatures.JustifyHSettings,
            get = function()
                return getFont().justifyH or XerionUIFeatures.JustifyHSettings.CENTER
            end,
            set = function(_, value)
                getFont().justifyH = value
                
                if onChange then
                    onChange()
                end
            end,
        },
        spacer = {
            type = "description",
            name =  "",
            width = "full",
            order = 49,
            hidden = shadowHidden,
        },
        fontShadowXOffset = {
            order = 50,
            type = "range",
            width = 0.75,
            name = "Shadow X Offset",
            min = -5,
            max = 5,
            step = 1,
            get = function()
                return getFont().fontShadowXOffset
            end,
            set = function(_, value)
                getFont().fontShadowXOffset = value
                
                if onChange then
                    onChange()
                end
            end,
            hidden = shadowHidden
        },
        fontShadowYOffset = {
            order = 60,
            type = "range",
            width = 0.75,
            name = "Shadow Y Offset",
            min = -5,
            max = 5,
            step = 1,
            get = function()
                return getFont().fontShadowYOffset
            end,
            set = function(_, value)
                getFont().fontShadowYOffset = value
                
                if onChange then
                    onChange()
                end
            end,
            hidden = shadowHidden
        },
        fontShadowColor = {
            order = 70,
            type = "color",
            width = 0.7,
            name = "Shadow Color",
            hasAlpha = true,
            get = function()
                local color = getFont().fontShadowColor
                return color.r, color.g, color.b, color.a
            end,
            set = function(_, r, g, b, a)
                getFont().fontShadowColor = {
                    r = r,
                    g = g,
                    b = b,
                    a = a
                }
                
                if onChange then
                    onChange()
                end
            end,
            hidden = shadowHidden
        },
        spacer2 = {
            type = "description",
            name =  "",
            width = "full",
            order = 79,
        },
        frameStrata = {
            order = 80,
            type = "select",
            width = 0.75,
            name = "Frame strata",
            values = XerionUIFeatures.FrameStrataSettings,
            get = function()
                return getFont().frameStrata or XerionUIFeatures.FrameStrataSettings.BACKGROUND
            end,
            set = function(_, value)
                getFont().frameStrata = value
                
                if onChange then
                    onChange()
                end
            end,
        },
        frameLevel = {
            order = 90,
            type = "range",
            width = 0.75,
            name = "Frame level",
            min = 1,
            max = 10,
            step = 1,
            get = function()
                return getFont().frameLevel or 1
            end,
            set = function(_, value)
                getFont().frameLevel = value
                
                if onChange then
                    onChange()
                end
            end
        }
    }, additionalOptions or {})
end