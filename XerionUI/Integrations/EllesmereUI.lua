--------------------------------------------------------------------------------
-- XerionUI - Integrations/EllesmereUI.lua
-- Helpers for reaching into EllesmereUI modules (for the EllesmereUI Tweaks).
-- Everything here reads EllesmereUI's own published tables and degrades to nil
-- when an update moves them.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local EUIx = {}
XUI.EUI = EUIx

-- A module's namespace as EllesmereUI publishes it (EllesmereUI._ModuleNS).
function EUIx.Module(name)
	local E = _G.EllesmereUI
	local reg = type(E) == "table" and E._ModuleNS
	local m = type(reg) == "table" and reg[name]
	return type(m) == "table" and m or nil
end

-- The health bar of an EllesmereUI party frame showing `unit`, or nil.
function EUIx.PartyHealthBar(unit)
	local RF = EUIx.Module("EllesmereUIRaidFrames")
	if not (RF and type(RF.GetFFD) == "function") then return nil end
	local btn = RF._partyUnitToButton and RF._partyUnitToButton[unit]
	-- the unit map is rebuilt as the secure header changes; between that and
	-- the next refresh, ask the buttons directly
	if not btn and RF._partyAllButtons then
		for _, candidate in ipairs(RF._partyAllButtons) do
			local ok, token = pcall(candidate.GetAttribute, candidate, "unit")
			if ok and token == unit then
				btn = candidate
				break
			end
		end
	end
	if not btn then return nil end
	local ok, d = pcall(RF.GetFFD, btn)
	return ok and d and d.health or nil
end
