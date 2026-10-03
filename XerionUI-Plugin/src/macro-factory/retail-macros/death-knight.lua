local addonName, XerionUIFeatures = ...
local moduleName = "MacroFactory"
local MacroFactory = XerionUIFeatures:GetModule(moduleName)

if XerionUIFeatures.playerClass ~= "DEATHKNIGHT" then
    return
end

-- DA
MacroFactory:RegisterMacro({
    group = "Death Knight",
    name = "DA",
    desc = "Puts Death's Advance in a castsequence macro to not accidentally consume both charges",
    icon = 48265, -- Death's Advance
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/castsequence reset=2 Death's Advance,null",
            "/cqs",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})

-- Cursor AMZ
MacroFactory:RegisterMacro({
    group = "Death Knight",
    name = "Cursor AMZ",
    icon = 51052, -- Anti-Magic Zone
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/cast [@cursor] Anti-Magic Zone",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})

-- Mouseover Grip
MacroFactory:RegisterMacro({
    group = "Death Knight",
    name = "Mouseover Grip",
    icon = 49576, -- Death Grip
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/cast [@mouseover, harm][] Death Grip",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})

-- Focus Grip
MacroFactory:RegisterMacro({
    group = "Death Knight",
    name = "Focus Grip",
    icon = 49576, -- Death Grip
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/cast [@focus, harm][] Death Grip",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})

-- Mouseover Asphyxiate
MacroFactory:RegisterMacro({
    group = "Death Knight",
    name = "Mouseover Asphyxiate",
    icon = 221562, -- Asphyxiate
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/cast [@mouseover, harm][] Asphyxiate",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})

-- Focus Asphyxiate
MacroFactory:RegisterMacro({
    group = "Death Knight",
    name = "Focus Asphyxiate",
    icon = 221562, -- Asphyxiate
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/cast [@focus, harm][] Asphyxiate",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})

-- Frost
MacroFactory:RegisterMacro({
    group = "Death Knight",
    subgroup = "Frost",
    name = "Frostbane",
    desc = "Combines Frostbane and Glacial Advance into 1 macro, will use Frostbane when available else casts Glacial Advance",
    icon = 1273742, -- Frost Bane
    create = function(name)
        local body = table.concat({
            "#showtooltip Glacial Advance",
            "/cast Frostbane",
            "/cast Glacial Advance",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})

-- Unholy
MacroFactory:RegisterMacro({
    group = "Death Knight",
    subgroup = "Unholy",
    name = "Scourge Strike",
    desc = "Combines Scourge Strike and the pet ability Claw, to fix your Ghoul sometimes not casting Claw enough",
    icon = 55090, -- Scourge Strike
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/cast Scourge Strike",
            "/cast Claw",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})

MacroFactory:RegisterMacro({
    group = "Death Knight",
    subgroup = "Unholy",
    name = "Death Coil",
    desc = "Combines Death Coil and the pet ability Claw, to fix your Ghoul sometimes not casting Claw enough",
    icon = 333470, -- Death Coil
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/cast Death Coil",
            "/cast Claw",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})
