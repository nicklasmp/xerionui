--------------------------------------------------------------------------------
-- XerionUI_Options - Pages/Profiles.lua
-- Switch, create, copy, delete, reset, export and import profiles.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local DB = XUI.DB
local AutoItems

-- Text typed into the page that is not a setting.
local scratch = { newName = "", copyCurrent = true, copyFrom = "", delete = "", importText = "", importName = "" }

local function ProfileValues(excludeActive)
	local out = {}
	for _, name in ipairs(DB:ListProfiles()) do
		if not (excludeActive and name == DB:GetProfileName()) then
			out[#out + 1] = { value = name, text = name }
		end
	end
	return out
end

StaticPopupDialogs.XERIONUI_PROFILE_CONFIRM = {
	text = "%s",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, fn) fn() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function Confirm(text, fn)
	StaticPopup_Show("XERIONUI_PROFILE_CONFIRM", text, nil, fn)
end

-- Rules for switching profile by context (Core/AutoProfile.lua).
local NONE = "(no change)"
local function RuleValues()
	local out = { { value = "", text = NONE } }
	for _, name in ipairs(DB:ListProfiles()) do out[#out + 1] = { value = name, text = name } end
	return out
end

local function Rule(label, tableName, key)
	return {
		type = "dropdown", label = label, values = RuleValues,
		disabled = function() return not DB.global.autoProfiles.enabled end,
		get = function() return DB.global.autoProfiles[tableName][key] or "" end,
		set = function(_, v)
			DB.global.autoProfiles[tableName][key] = (v ~= "") and v or nil
			XUI.ApplyAutoProfile()
		end,
	}
end

AutoItems = function()
	local items = {
		{ type = "description", width = "full", text = "Pick a profile for a kind of content or a specialization. The kind of content wins over the specialization; \"no change\" leaves the profile alone. Never switches in combat." },
		{
			type = "toggle", label = "Switch profiles automatically", width = "full",
			get = function() return DB.global.autoProfiles.enabled end,
			set = function(_, on) DB.global.autoProfiles.enabled = on and true or false XUI.ApplyAutoProfile() end,
		},
	}
	for _, k in ipairs(XUI.INSTANCE_KINDS) do items[#items + 1] = Rule(k.text, "instance", k.value) end
	local CSI = C_SpecializationInfo
	local num = (CSI and CSI.GetNumSpecializations) and CSI.GetNumSpecializations() or 0
	for i = 1, num do
		local id, name = CSI.GetSpecializationInfo(i)
		if id then items[#items + 1] = Rule("Spec: " .. tostring(name), "spec", id) end
	end
	return items
end

O:RegisterSystemPage({
	key = "profiles",
	title = "Profiles",
	icon = "layers",
	desc = "Every character can use its own profile or share one.",
	root = function() return scratch end,
	build = function(ctx)
		return {
			O.Card("Active profile", {
				{
					type = "dropdown", label = "Profile",
					values = function() return ProfileValues(false) end,
					get = function() return DB:GetProfileName() end,
					set = function(_, name) DB:SetProfile(name) end,
				},
				{
					type = "description",
					text = function() return ("|cffaaaaaa%s|r uses |cffffffff%s|r."):format(DB.charKey, DB:GetProfileName()) end,
				},
			}),
			O.Card("New profile", {
				{ type = "input", label = "Name", path = "newName" },
				{ type = "toggle", label = "Start from the current settings", path = "copyCurrent" },
				{
					type = "button", text = "Create profile", primary = true,
					disabled = function() return scratch.newName == "" or DB:ProfileExists(scratch.newName) end,
					onClick = function()
						if DB:NewProfile(scratch.newName, scratch.copyCurrent) then scratch.newName = "" end
					end,
				},
			}),
			O.Card("Manage", {
				{ type = "dropdown", label = "Copy settings from", path = "copyFrom", values = function() return ProfileValues(true) end },
				{
					type = "button", text = "Copy into current",
					disabled = function() return scratch.copyFrom == "" or not DB:ProfileExists(scratch.copyFrom) end,
					onClick = function()
						Confirm(("Replace the settings of '%s' with those of '%s'?"):format(DB:GetProfileName(), scratch.copyFrom), function()
							DB:CopyProfile(scratch.copyFrom)
						end)
					end,
				},
				{ type = "dropdown", label = "Delete a profile", path = "delete", values = function() return ProfileValues(true) end },
				{
					type = "button", text = "Delete",
					disabled = function() return scratch.delete == "" or not DB:ProfileExists(scratch.delete) end,
					onClick = function()
						local name = scratch.delete
						Confirm(("Delete the profile '%s'?"):format(name), function()
							DB:DeleteProfile(name)
							scratch.delete = ""
							if ctx.page then ctx.page:Refresh() end
						end)
					end,
				},
				{
					type = "button", text = "Reset current profile",
					onClick = function()
						Confirm(("Reset every setting of '%s' to its default?"):format(DB:GetProfileName()), function()
							DB:ResetProfile()
						end)
					end,
				},
			}),
			O.Card("Switch automatically", AutoItems()),
			O.Card("Export", {
				{
					type = "description", width = "full",
					text = "Copy this string (Ctrl+A, Ctrl+C) to share the current profile or keep a backup.",
				},
				{
					type = "input", width = "full", multiline = 90, readOnly = true, selectAll = true,
					get = function() return DB:ExportProfile() or "" end,
				},
			}),
			O.Card("Import", {
				{ type = "input", label = "Profile string", width = "full", multiline = 90, path = "importText" },
				{ type = "input", label = "Name for the new profile", path = "importName" },
				{
					type = "button", text = "Import", primary = true,
					disabled = function() return scratch.importText == "" end,
					onClick = function()
						local ok, result = DB:ImportProfile(scratch.importText, scratch.importName)
						if ok then
							XUI.Printf("imported profile |cffffffff%s|r.", result)
							scratch.importText, scratch.importName = "", ""
						else
							XUI.Printf("import failed: %s", result)
						end
					end,
				},
			}),
		}
	end,
})
