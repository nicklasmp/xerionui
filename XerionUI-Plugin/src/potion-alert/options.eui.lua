local addonName, XerionUIFeatures = ...

local moduleName = "PotionAlert"
local PotionAlert = XerionUIFeatures:GetModule(moduleName)

PotionAlert.EUIPages = { "Display", "Sound Alert", "Filters" }

function PotionAlert:GetEUIOptions(pageName)
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    if pageName == "Sound Alert" then
        return {
            name = "Potion Alert",
            rows = {
                {
                    header = "Sound",
                },
                {
                    type = "toggle",
                    label = "Play sound",
                    refresh = true,
                    get = function()
                        return PotionAlert.db.playSound
                    end,
                    set = function(value)
                        PotionAlert.db.playSound = value
                    end,
                },
                XerionUIFeatures:EUISoundRow({
                    disabled = function()
                        return not PotionAlert.db.playSound
                    end,
                    get = function()
                        return PotionAlert.db.sound
                    end,
                    set = function(value)
                        PotionAlert.db.sound = value
                    end,
                }),
                {
                    header = "Text-to-Speech",
                },
                {
                    type = "toggle",
                    label = "Play TTS",
                    refresh = true,
                    disabled = function()
                        return PotionAlert.db.playSound
                    end,
                    get = function()
                        return PotionAlert.db.playTTS
                    end,
                    set = function(value)
                        PotionAlert.db.playTTS = value
                    end,
                },
                XerionUIFeatures:EUITTSRow({
                    disabled = function()
                        return PotionAlert.db.playSound or not PotionAlert.db.playTTS
                    end,
                    get = function()
                        return PotionAlert.db.TTS
                    end,
                    set = function(value)
                        PotionAlert.db.TTS = value
                    end,
                    volume = {
                        get = function() return PotionAlert.db.TTSVolume end,
                        set = function(value) PotionAlert.db.TTSVolume = value end,
                    },
                    voice = {
                        get = function() return PotionAlert.db.TTSVoice end,
                        set = function(value) PotionAlert.db.TTSVoice = value end,
                    },
                }),
            },
        }
    end

    if pageName == "Filters" then
        return {
            name = "Potion Alert",
            rows = {
                {
                    header = "Instances",
                },
                {
                    pair = {
                        {
                            type = "toggle",
                            label = "Enable in m0/m+",
                            get = function()
                                return PotionAlert.db.enabledInDungeons
                            end,
                            set = function(value)
                                PotionAlert.db.enabledInDungeons = value
                                apply()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Enable in raids",
                            get = function()
                                return PotionAlert.db.enabledInRaids
                            end,
                            set = function(value)
                                PotionAlert.db.enabledInRaids = value
                                apply()
                            end,
                        },
                    },
                },
            },
        }
    end

    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = PotionAlert.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            PotionAlert.db.color = {
                r = r,
                g = g,
                b = b,
                a = a,
            }
            apply()
        end,
        cog = {
            title = "Alert Text",
            rows = {
                {
                    type = "input",
                    label = "Text",
                    width = 120,
                    get = function()
                        return PotionAlert.db.displayText or ""
                    end,
                    set = function(value)
                        PotionAlert.db.displayText = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Potion Alert",
        rows = XerionUIFeatures:EUIFontRows(function() return PotionAlert.db.font end, apply, nil, { displayRow }),
    }
end
