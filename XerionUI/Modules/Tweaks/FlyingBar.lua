--------------------------------------------------------------------------------
-- Skyriding bar tweaks
-- Changes to EllesmereUI's Skyriding HUD (the speed / vigor / Second Wind bars,
-- EllesmereUIBlizzardSkin). Today: remove the Whirling Surge icon beside the
-- bars.
--
-- EllesmereUI keeps that as its own setting (showWhirlingSurge in its
-- skyriding profile) and lays the bars out around it, so the icon is removed by
-- switching that setting off - the bars close up instead of leaving a gap - and
-- the player's own value is put back when this module is switched off. Its
-- profile rebuild is hooked so a profile switch cannot bring the icon back.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local M = XUI:NewModule("EUIFlyingBar", {
	name = "Skyriding Bar",
	desc = "Tweaks to EllesmereUI's Skyriding bar, starting with removing the Whirling Surge icon.",
	category = "tweaks",
	icon = [[Interface\Icons\Ability_DragonRiding_Glyph01]],
	order = 60,
	requires = "EllesmereUIBlizzardSkin",
	defaults = {
		hideIcon = true,
		-- EllesmereUI's own icon setting from before we changed it (nil = untouched)
		original = nil,
	},
})

local why -- why nothing was changed, for /xui debug
local busy = false

local function Profile()
	local ns = XUI.EUI and XUI.EUI.Module("EllesmereUIBlizzardSkin")
	local db = ns and ns.edrDB
	local p = type(db) == "table" and db.profile
	if type(p) ~= "table" then
		why = "EllesmereUI's Skyriding settings are not loaded yet (is its Skyriding HUD available?)"
		return nil
	end
	why = nil
	return p
end

local function Rebuild()
	if type(_G._EDR_Rebuild) == "function" then
		busy = true
		pcall(_G._EDR_Rebuild)
		busy = false
	end
end

-- Puts EllesmereUI's icon setting in the state we want. `want` = hide the icon.
local function Sync(self, want)
	local p = Profile()
	if not p then return end
	local shown = p.showWhirlingSurge ~= false
	if want then
		if shown then
			if self.db.original == nil then self.db.original = true end
			p.showWhirlingSurge = false
			Rebuild()
		elseif self.db.original == nil then
			-- it was already off before we came: nothing to put back
			self.db.original = false
		end
	elseif self.db.original ~= nil then
		local original = self.db.original
		self.db.original = nil
		if original and not shown then
			p.showWhirlingSurge = true
			Rebuild()
		end
	end
end

function M:OnEnable()
	-- EllesmereUI builds its settings at login; look again a moment later
	local function try() Sync(self, self.db.hideIcon) end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:After(1, try) end)
	if type(_G._EDR_Rebuild) == "function" then
		-- a profile switch rebuilds from the new profile's settings
		self:SecureHook(_G, "_EDR_Rebuild", function()
			if not busy then try() end
		end)
	end
	try()
end

function M:OnDisable()
	Sync(self, false)
end

function M:OnRefresh()
	if self.running then Sync(self, self.db.hideIcon) end
end

function M:DebugInfo()
	local p = Profile()
	return {
		why or ("EllesmereUI shows the Whirling Surge icon: " .. tostring(p.showWhirlingSurge ~= false)),
		"icon setting before we changed it: " .. tostring(self.db.original),
	}
end
