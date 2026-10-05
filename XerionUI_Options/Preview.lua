--------------------------------------------------------------------------------
-- XerionUI_Options - Preview.lua
-- (split out of Panel.lua; the window state lives in O.S)
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local S = O.S

--------------------------------------------------------------------------------
-- Preview that follows the page, and a window that steps aside for it
--------------------------------------------------------------------------------
function O.SyncAutoPreview(key)
	for m in pairs(S.autoStarted) do
		if m.key ~= key then
			S.autoStarted[m] = nil
			m:SetPreview(false)
		end
	end
	if XUI.DB.global.panel.autoPreview == false then return end
	local m = XUI:GetModule(key)
	if m and not m.preview and not S.autoStarted[m] then
		S.autoStarted[m] = true
		m:SetPreview(true)
	end
end

local function RectsOverlap(a, b)
	return a.l < b.r and a.r > b.l and a.b < b.t and a.t > b.b
end
local function ScreenRect(f)
	local l, b, w, h = f:GetRect()
	if not l then return nil end
	local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return { l = l * s, b = b * s, r = (l + w) * s, t = (b + h) * s }
end

function O:UpdateDock()
	if not (S.frame and S.frame:IsShown()) then return end
	local mine = ScreenRect(S.frame)
	if XUI.DB.global.panel.dock ~= false and mine then
		for _, entry in ipairs(XUI.Movers.list) do
			local m = entry.module
			if m.preview and entry.frame:IsShown() then
				local r = ScreenRect(entry.frame)
				if r and RectsOverlap(mine, r) then
					-- the side the preview is not on
					local cx = (r.l + r.r) / 2
					S.frame:ClearAllPoints()
					if cx > UIParent:GetWidth() / 2 then
						S.frame:SetPoint("LEFT", UIParent, "LEFT", 24, 0)
					else
						S.frame:SetPoint("RIGHT", UIParent, "RIGHT", -24, 0)
					end
					S.docked = true
					return
				end
			end
		end
	end
	if S.docked then
		S.docked = false
		S.frame:ClearAllPoints()
		local p = XUI.DB.global.panel.point
		if type(p) == "table" and p[1] then
			S.frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
		else
			S.frame:SetPoint("CENTER")
		end
	end
end

S.UpdateDockSoon = XUI.Coalesce(function() C_Timer.After(0.05, function() O:UpdateDock() end) end)
