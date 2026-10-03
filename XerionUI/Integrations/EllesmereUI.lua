--------------------------------------------------------------------------------
-- XerionUI - Integrations/EllesmereUI.lua
-- With EllesmereUI installed, our movers join ITS unlock mode (one screen to
-- arrange the whole UI) and entering it previews our modules. Can be turned
-- off in General > Unlock mode, which brings back our own overlay.
--
-- EllesmereUI's unlock API (EllesmereUI.lua, EUI_UnlockMode.lua):
--   EllesmereUI.MakeUnlockElement(opts)                 element factory
--   EllesmereUI:RegisterUnlockElements(list, folder)    adds movers
--   EllesmereUI:RegisterUnlockModeListener(owner, fn)   fn(active) on open/close
--   EllesmereUI:OpenUnlockMode() / :ToggleUnlockMode()
-- Positions are exchanged as CENTER/CENTER offsets, which is also how ours are
-- stored, so no conversion is needed.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local Movers = XUI.Movers

XUI.Integrations = XUI.Integrations or {}

local registered = {}

local function EUI()
	local E = _G.EllesmereUI
	if type(E) ~= "table" or not (E.RegisterUnlockElements and E.MakeUnlockElement) then return nil end
	return E
end

local function Active()
	return EUI() ~= nil and XUI.DB and XUI.DB.global.unlock.useEllesmere
end

local function Register(entry)
	local E = EUI()
	if not E or registered[entry.key] or not XUI.DB.global.unlock.useEllesmere then return end
	registered[entry.key] = true
	local ok, err = pcall(E.RegisterUnlockElements, E, {
		E.MakeUnlockElement({
			key = entry.key,
			label = entry.label,
			group = "XerionUI",
			order = 900,
			noResize = true,
			getFrame = function() return entry.frame end,
			getSize = function() return entry.frame:GetWidth(), entry.frame:GetHeight() end,
			isHidden = function() return not entry.module.db.enabled end,
			savePos = function(_, point, relPoint, x, y)
				local p = Movers:GetPosition(entry)
				if not p then return end
				p.point, p.relPoint = point or "CENTER", relPoint or point or "CENTER"
				p.x, p.y = math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
				Movers:Apply(entry.frame)
			end,
			loadPos = function()
				local p = Movers:GetPosition(entry)
				if not p then return nil end
				return { point = p.point or "CENTER", relPoint = p.relPoint or p.point or "CENTER", x = p.x or 0, y = p.y or 0 }
			end,
			clearPos = function() Movers:Reset(entry) end,
			-- EllesmereUI applies every element at login whether it is hidden
			-- or not; placing a disabled module's frame would be harmless, but
			-- there is nothing to place.
			applyPos = function()
				if entry.module.db.enabled then Movers:Apply(entry.frame) end
			end,
		}),
	}, XUI.ADDON_NAME)
	if not ok then
		registered[entry.key] = nil
		geterrorhandler()(err)
	end
end

-- Called by XUI:SetUnlocked(true): opens EllesmereUI's unlock mode instead of
-- ours. Returns true when it did.
function XUI.Integrations.EllesmereUnlock()
	if not Active() then return false end
	local E = EUI()
	if E.OpenUnlockMode then
		E:OpenUnlockMode()
		return true
	elseif E.ToggleUnlockMode then
		E:ToggleUnlockMode()
		return true
	end
	return false
end

local owner = {}

XUI:On("MoverRegistered", owner, function(_, entry)
	if XUI.loggedIn then Register(entry) end
end)

XUI:On("LoggedIn", owner, function()
	local E = EUI()
	if not E then return end
	for _, entry in ipairs(Movers.list) do Register(entry) end
	if E.RegisterUnlockModeListener then
		E:RegisterUnlockModeListener(XUI.ADDON_NAME, function(active)
			if XUI.DB.global.unlock.useEllesmere then XUI:SetUnlockPreview(active and true or false) end
		end)
	end
end)

--------------------------------------------------------------------------------
-- Reaching into EllesmereUI modules (for the EllesmereUI Tweaks). Everything
-- here reads EllesmereUI's own published tables and degrades to nil when an
-- update moves them.
--------------------------------------------------------------------------------
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
