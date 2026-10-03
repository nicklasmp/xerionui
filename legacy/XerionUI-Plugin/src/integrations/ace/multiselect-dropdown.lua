local addonName, XerionUIFeatures = ...

-- AceGUI's multiselect dropdown appends a Close entry to its own list, which reads
-- as one more thing to tick in a list of spells. This is that dropdown without it:
-- AceConfigDialog picks it up through `dialogControl = "ItruliaMultiselect"`, and
-- the list still closes by clicking the dropdown again or anywhere outside it.
local AceGUI = LibStub("AceGUI-3.0")

local widgetType, widgetVersion = "ItruliaMultiselect", 1

if (AceGUI:GetWidgetVersion(widgetType) or 0) >= widgetVersion then
    return
end

local itemHeight = 16
local pulloutPadding = 34

-- The Close entry is always the last item the dropdown added. The pullout only
-- sizes itself while items are added to it, so its heights are corrected here.
local function removeCloseItem(widget)
    if not widget.hasClose then
        return
    end

    local pullout = widget.pullout
    local items = pullout and pullout.items
    local closeItem = items and items[#items]

    if not closeItem then
        return
    end

    items[#items] = nil
    AceGUI:Release(closeItem)
    widget.hasClose = nil

    local height = #items * itemHeight
    pullout.itemFrame:SetHeight(height)
    pullout.frame:SetHeight(math.min(height + pulloutPadding, pullout.maxHeight))
end

-- Built from the stock dropdown's own constructor rather than a copy of it, so it
-- keeps every behaviour of the widget it replaces. The registry is called directly
-- because AceGUI:Create would also run OnAcquire, which the caller does.
local function Constructor()
    local widget = AceGUI.WidgetRegistry["Dropdown"]()
    widget.type = widgetType

    local setList = widget.SetList
    local setMultiselect = widget.SetMultiselect

    widget.SetList = function(self, ...)
        setList(self, ...)
        removeCloseItem(self)
    end

    widget.SetMultiselect = function(self, multiselect)
        setMultiselect(self, multiselect)
        removeCloseItem(self)
    end

    -- AceConfigDialog sorts a multiselect by its keys, which for a list of spell ids
    -- is an order nobody chose. An option can pass its own through `arg`, as the
    -- array of keys the entries should appear in. It arrives after the list is
    -- filled, so what is checked has to be carried across the rebuild.
    widget.SetCustomData = function(self, order)
        if type(order) ~= "table" or not self.list then
            return
        end

        local checked = {}

        for _, item in self.pullout:IterateItems() do
            if item.type == "Dropdown-Item-Toggle" then
                checked[item.userdata.value] = item:GetValue()
            end
        end

        self:SetList(self.list, order)

        for value, isChecked in pairs(checked) do
            self:SetItemValue(value, isChecked)
        end
    end

    return widget
end

AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)
