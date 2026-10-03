--------------------------------------------------------------------------------
-- XerionUI_Options - Pages/Profiles.lua
-- Switch, create, copy, delete, reset, export and import profiles.
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local DB = XUI.DB

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
