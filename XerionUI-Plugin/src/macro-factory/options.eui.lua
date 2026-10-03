local addonName, XerionUIFeatures = ...

local moduleName = "MacroFactory"
local MacroFactory = XerionUIFeatures:GetModule(moduleName)

MacroFactory.EUINoEnableSwitch = true

function MacroFactory:GetEUIOptions()
    local function iconItem(macro)
        return {
            icon = MacroFactory:ResolveIcon(macro.icon),
            label = macro.name,
            tooltip = macro.desc,
            desaturated = function()
                return GetMacroIndexByName(macro.name) ~= 0
            end,
            onClick = function()
                macro.create(macro.name)
            end,
        }
    end

    local function iconItems(macros)
        local items = {}

        for _, macro in ipairs(macros) do
            items[#items + 1] = iconItem(macro)
        end

        return items
    end

    local rows = {
        { text = "Click an icon to create that macro. If one with the same name already exists you'll be asked before it's overwritten. Macros you've already made show greyed out." },
    }

    for _, group in ipairs(self:GetGroupedMacros()) do
        rows[#rows + 1] = { header = group.name }

        if #group.macros > 0 then
            rows[#rows + 1] = { type = "icons", items = iconItems(group.macros) }
        end

        for _, sub in ipairs(group.subgroups) do
            rows[#rows + 1] = { header = sub.name }
            rows[#rows + 1] = { type = "icons", items = iconItems(sub.macros) }
        end
    end

    return {
        name = "Macro Factory",
        rows = rows,
    }
end
