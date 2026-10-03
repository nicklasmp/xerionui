--------------------------------------------------------------------------------
-- XerionUI_Options - Extras.lua
-- Cards every module page gets at the bottom: copy the styling of another
-- module, and share this module's settings as a string.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local scratch = {}
local function Scratch(m)
	scratch[m.key] = scratch[m.key] or { copyFrom = "", importText = "" }
	return scratch[m.key]
end

-- A style block is a table with a useGlobal field (see Core/Widgets.lua T.*).
local function IsBlock(v) return type(v) == "table" and v.useGlobal ~= nil end

local function SharedBlocks(a, b)
	local n = 0
	for key, v in pairs(a.db) do
		if IsBlock(v) and IsBlock(b.db[key]) then n = n + 1 end
	end
	return n
end

-- placement and on/off belong to the element, not to the look
local KEEP = { enabled = true, anchor = true, x = true, y = true }

local function CopyStyling(from, to)
	local n = 0
	for key, block in pairs(to.db) do
		local src = from.db[key]
		if IsBlock(block) and IsBlock(src) then
			for k, v in pairs(src) do
				if not KEEP[k] then block[k] = XUI.CopyTable(v) end
			end
			n = n + 1
		end
	end
	return n
end

function O:ModuleExtras(m, ctx)
	local s = Scratch(m)
	local function Sources()
		local out = {}
		for _, other in ipairs(XUI:SortedModules()) do
			if other ~= m and other:IsAvailable() and SharedBlocks(m, other) > 0 then
				out[#out + 1] = { value = other.key, text = other.name }
			end
		end
		return out
	end
	return {
		O.Card("Where it runs", {
			{ type = "description", width = "full", text = "Keeps the module off outside the situations you pick. A module that is off does not listen to the game at all." },
			{ type = "dropdown", label = "Group", path = "visibility.group", values = XUI.VISIBILITY.group },
			{ type = "dropdown", label = "Kind of content", path = "visibility.instance", values = XUI.VISIBILITY.instance },
			{ type = "dropdown", label = "Role", path = "visibility.role", values = XUI.VISIBILITY.role },
		}),
		O.Card("Copy styling", {
			{ type = "description", width = "full",
				text = "Copies fonts, borders, bars, icons and glows from another module onto the ones this module shares with it. Positions and on/off switches stay." },
			{ type = "dropdown", label = "Copy from", values = Sources,
				get = function() return s.copyFrom end, set = function(_, v) s.copyFrom = v end },
			{
				type = "button", text = "Copy styling",
				disabled = function() return s.copyFrom == "" or not XUI:GetModule(s.copyFrom) end,
				onClick = function()
					local from = XUI:GetModule(s.copyFrom)
					if not from then return end
					local n = CopyStyling(from, m)
					XUI:NotifySettingChanged(m, nil)
					if ctx.page then ctx.page:Refresh() end
					XUI.Printf("copied %d style block(s) from |cffffffff%s|r to |cffffffff%s|r.", n, from.name, m.name)
				end,
			},
		}),
		O.Card("Share this module", {
			{ type = "description", width = "full", text = "Copy the string to give this module's settings to someone else or keep a backup. The on/off switch is not included." },
			{
				type = "input", width = "full", multiline = 70, readOnly = true, selectAll = true,
				get = function() return XUI.DB:ExportModule(m.key) or "" end,
			},
			{ type = "input", label = "Import a string for this module", width = "full", multiline = 70,
				get = function() return s.importText end, set = function(_, v) s.importText = v end },
			{
				type = "button", text = "Import", primary = true,
				disabled = function() return s.importText == "" end,
				onClick = function()
					local ok, err = XUI.DB:ImportModule(s.importText, m.key)
					if ok then
						s.importText = ""
						XUI.Style:Invalidate()
						XUI:NotifySettingChanged(m, nil)
						if ctx.page then ctx.page:Refresh() end
						XUI.Printf("imported settings for |cffffffff%s|r.", m.name)
					else
						XUI.Printf("import failed: %s", err)
					end
				end,
			},
		}),
	}
end
