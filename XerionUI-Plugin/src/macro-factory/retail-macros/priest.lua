local addonName, XerionUIFeatures = ...
local moduleName = "MacroFactory"
local MacroFactory = XerionUIFeatures:GetModule(moduleName)

if XerionUIFeatures.playerClass ~= "PRIEST" then
    return
end

-- PI
MacroFactory:RegisterMacro({
    group = "Priest",
    name = "PI",
    icon = 10060, -- Power Infusion
    create = function(name)
        local body = table.concat({
            "#showtooltip Power Infusion",
            "/cast [@mouseover,help,nodead][@player] Power Infusion",
            "/cast [known:Void Volley] Void Volley",
        }, "\n")

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})

-- PI:Set
MacroFactory:RegisterMacro({
    group = "Priest",
    name = "PI:Set",
    desc = "Requires there to be another macro called `PI` that contains `] Power Infusion`, this will automatically update that macro with your targets name so you can use focus for interrupting",
    icon = 10060, -- Power Infusion
    create = function(name)
        -- Long string so the literal \n in the pattern is preserved for the macro.
        local body = [[/run local i=GetMacroIndexByName("PI")local t=",help,nodead"local x,y,b=GetMacroInfo(i)local n=UnitName("target")or"player"EditMacro(i,nil,nil,(b:gsub("[^\n]*%] ?Power Infusion","/cast [@mouseover"..t.."][@"..n..t.."][] Power Infusion")))print("PI "..n)]]

        MacroFactory:CreateOrUpdateMacro(name, body, true)
    end
})
