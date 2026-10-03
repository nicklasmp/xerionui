local addonName, XerionUIFeatures = ...

local moduleName = "DeathAlert"
local DeathAlert = XerionUIFeatures:GetModule(moduleName)

-- Per-role settings block, mirroring options.ace.lua's optionsForRole(role).
local function roleRows(role)
    return {
        {
            type = "toggle",
            label = "Show alert",
            get = function()
                return DeathAlert.db.byRole.display[role].enabled
            end,
            set = function(value)
                DeathAlert.db.byRole.display[role].enabled = value
            end,
        },
        {
            type = "toggle",
            label = "Play sound",
            refresh = true,
            disabled = function()
                return not DeathAlert.db.playSound
            end,
            get = function()
                return DeathAlert.db.byRole.sound[role].enabled
            end,
            set = function(value)
                DeathAlert.db.byRole.sound[role].enabled = value
            end,
        },
        XerionUIFeatures:EUISoundRow({
            disabled = function()
                return not DeathAlert.db.playSound or not DeathAlert.db.byRole.sound[role].enabled
            end,
            get = function()
                return DeathAlert.db.byRole.sound[role].sound
            end,
            set = function(value)
                DeathAlert.db.byRole.sound[role].sound = value
            end,
        }),
        {
            type = "execute",
            label = "Clear",
            refresh = true,
            disabled = function()
                return not DeathAlert.db.playSound or not DeathAlert.db.byRole.sound[role].enabled
            end,
            func = function()
                DeathAlert.db.byRole.sound[role].sound = nil
            end,
        },
        {
            type = "toggle",
            label = "Play TTS",
            disabled = function()
                return DeathAlert.db.playSound or not DeathAlert.db.playTTS
            end,
            get = function()
                return DeathAlert.db.byRole.tts[role].enabled
            end,
            set = function(value)
                DeathAlert.db.byRole.tts[role].enabled = value
            end,
        },
        XerionUIFeatures:EUITTSRow({
            disabled = function()
                return DeathAlert.db.playSound or not DeathAlert.db.playTTS or not DeathAlert.db.byRole.tts[role].enabled
            end,
            get = function()
                return DeathAlert.db.byRole.tts[role].TTS
            end,
            set = function(value)
                if value == "" then
                    value = nil
                end
                DeathAlert.db.byRole.tts[role].TTS = value
            end,
            volume = {
                get = function() return DeathAlert.db.TTSVolume end,
                set = function(value) DeathAlert.db.TTSVolume = value end,
            },
            voice = {
                get = function() return DeathAlert.db.TTSVoice end,
                set = function(value) DeathAlert.db.TTSVoice = value end,
            },
        }),
    }
end


DeathAlert.EUIPages = { "Display", "Sound Alert", "Filters" }

function DeathAlert:GetEUIOptions(pageName)
    local function apply() XerionUIFeatures:ApplyModuleStyles(moduleName) end

    if pageName == "Sound Alert" then
        return {
            name = "Death Alert",
            rows = {
                {
                    header = "Sound",
                },
                {
                    type = "toggle",
                    label = "Play sound",
                    refresh = true,
                    get = function()
                        return DeathAlert.db.playSound
                    end,
                    set = function(value)
                        DeathAlert.db.playSound = value
                    end,
                },
                XerionUIFeatures:EUISoundRow({
                    disabled = function()
                        return not DeathAlert.db.playSound
                    end,
                    get = function()
                        return DeathAlert.db.sound
                    end,
                    set = function(value)
                        DeathAlert.db.sound = value
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
                        return DeathAlert.db.playSound
                    end,
                    get = function()
                        return DeathAlert.db.playTTS
                    end,
                    set = function(value)
                        DeathAlert.db.playTTS = value
                    end,
                },
                XerionUIFeatures:EUITTSRow({
                    disabled = function()
                        return DeathAlert.db.playSound or not DeathAlert.db.playTTS
                    end,
                    get = function()
                        return DeathAlert.db.TTS
                    end,
                    set = function(value)
                        DeathAlert.db.TTS = value
                    end,
                    volume = {
                        get = function() return DeathAlert.db.TTSVolume end,
                        set = function(value) DeathAlert.db.TTSVolume = value end,
                    },
                    voice = {
                        get = function() return DeathAlert.db.TTSVoice end,
                        set = function(value) DeathAlert.db.TTSVoice = value end,
                    },
                }),
            },
        }
    end

    if pageName == "Filters" then
        return {
            name = "Death Alert",
            rows = {
                {
                    header = "Names",
                },
                {
                    type = "input",
                    label = "Whitelist names",
                    tooltip = "Comma seperated list of names",
                    get = function()
                        return DeathAlert.db.whitelist
                    end,
                    set = function(value)
                        DeathAlert.db.whitelist = value
                    end,
                },
                {
                    type = "input",
                    label = "Blacklist names",
                    tooltip = "Comma seperated list of names",
                    disabled = function()
                        return DeathAlert.db.whitelist ~= nil and DeathAlert.db.whitelist ~= ""
                    end,
                    get = function()
                        return DeathAlert.db.blacklist
                    end,
                    set = function(value)
                        DeathAlert.db.blacklist = value
                    end,
                },
                {
                    header = "Settings based on dead player's role",
                },
                {
                    text = "These settings only work while in a raid as you might not care about a dps standing in fire ;)",
                },
                {
                    text = "Empty settings will fallback to the settings above",
                },
                {
                    header = "DPS",
                    rows = roleRows("DAMAGER"),
                },
                {
                    header = "Healer",
                    rows = roleRows("HEALER"),
                },
                {
                    header = "Tank",
                    rows = roleRows("TANK"),
                },
            },
        }
    end

    local displayRow = {
        type = "color",
        label = "Display",
        hasAlpha = true,
        get = function()
            local color = DeathAlert.db.color
            return color.r, color.g, color.b, color.a
        end,
        set = function(r, g, b, a)
            DeathAlert.db.color = {
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
                    label = "Suffix",
                    width = 120,
                    get = function()
                        return DeathAlert.db.displayText or ""
                    end,
                    set = function(value)
                        DeathAlert.db.displayText = value
                        apply()
                    end,
                },
                {
                    type = "slider",
                    label = "Display duration",
                    min = 1,
                    max = 10,
                    step = 1,
                    get = function()
                        return DeathAlert.db.messageDuration
                    end,
                    set = function(value)
                        DeathAlert.db.messageDuration = value
                        apply()
                    end,
                },
            },
        },
    }

    return {
        name = "Death Alert",
        rows = XerionUIFeatures:EUIFontRows(function() return DeathAlert.db.font end, apply, nil, { displayRow }),
    }
end
