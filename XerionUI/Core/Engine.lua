--------------------------------------------------------------------------------
-- XerionUI - Core/Engine.lua
-- The small, repeated parts of drawing through the game's aura engine
-- (AuraContainer), shared by every module that does it.
--
--   Engine.NewContainer(parent, name)   a container ready for AddAuraSlot/Group
--   Engine.Silence(button)              no clicks or tooltips on an engine button
--   Engine.WhenFree(module, pending, fn)  run a refused restyle when the fight
--                                        or restriction that refused it ends
--
-- Why the last one: once an engine button's initializer returns, the client
-- locks it against addon code for as long as auras are secret (combat, keys,
-- boss fights). A restyle made then is refused; the module notes that, and it
-- is repeated when the restriction lifts.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local Engine = {}
XUI.Engine = Engine

-- A container frame, or nil and the reason. Anchoring and the slot/group are
-- the caller's: they differ.
function Engine.NewContainer(parent, name)
	if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end
	local ok, c = pcall(CreateFrame, "AuraContainer", name, parent, "CustomAuraContainerTemplate")
	if not ok or not c then return nil, "the client refused the AuraContainer frame" end
	c:SetSize(1, 1)
	c:SetScale(1)
	return c
end

-- Neither clicks nor tooltips: these are readouts, and an engine button comes
-- with both alive. Only legal inside the initializer.
function Engine.Silence(button)
	pcall(button.SetMouseClickEnabled, button, false)
	pcall(button.SetMouseMotionEnabled, button, false)
end

-- Registers, on `module`, the two events that end a restriction. `pending()`
-- says whether a restyle is waiting; `fn` is the restyle.
function Engine.WhenFree(module, pending, fn)
	module:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if pending() then fn() end
	end)
	module:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function(self)
		-- the restriction still reads its old answer while its own event is handed out
		if pending() then self:After(0, fn) end
	end)
end
