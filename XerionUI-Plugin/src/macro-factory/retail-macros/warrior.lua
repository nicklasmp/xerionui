local addonName, XerionUIFeatures = ...
local moduleName = "MacroFactory"
local MacroFactory = XerionUIFeatures:GetModule(moduleName)

if XerionUIFeatures.playerClass ~= "WARRIOR" then
    return
end

-- Cursor Champion's Spear
MacroFactory:RegisterMacro({
    group = "Warrior",
    name = "Cursor Champion's Spear",
    icon = 376079, -- Champion's Spear
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/cast [@cursor] Champion's Spear",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})

-- Cursor Heroic Leap
MacroFactory:RegisterMacro({
    group = "Warrior",
    name = "Cursor Heroic Leap",
    icon = 6544, -- Heroic Leap
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/cast [@cursor] Heroic Leap",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})


-- Mouseover Storm Bolt
MacroFactory:RegisterMacro({
    group = "Warrior",
    name = "Mouseover Storm Bolt",
    icon = 107570, -- Storm Bolt
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/cast [@mouseover, harm][] Storm Bolt",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})

-- Focus Storm Bolt
MacroFactory:RegisterMacro({
    group = "Warrior",
    name = "Focus Storm Bolt",
    icon = 107570, -- Storm Bolt
    create = function(name)
        local body = table.concat({
            "#showtooltip",
            "/cast [@focus, harm][] Storm Bolt",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})
