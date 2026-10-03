-- Scrolled snapshots of long pages.
MOCK.LoadTOC("XerionUI")
MOCK.Fire("PLAYER_LOGIN")
MOCK.Advance(0.5)
local XUI = _G.XerionUI
for _, m in ipairs(XUI.modules) do m:SetEnabled(true) end
SlashCmdList.XERIONUI("")
MOCK.Advance(0.5)
MOCK.crop = "XUI_OptionsFrame"
local function ScrollPages(fraction)
	for _, f in ipairs(MOCK.frames) do
		if f._kind == "ScrollFrame" and f._scrollChild and f:IsVisible() and (f._scrollChild._h or 0) > 1000 then
			f:SetVerticalScroll(f:GetVerticalScrollRange() * fraction)
		end
	end
end
for _, key in ipairs({ "CCTracker", "Externals", "CoTank", "EUIPartyFrames" }) do
	XUI.Options:Open(key)
	MOCK.Advance(0.2)
	MOCK.Shot("page-" .. key)
	ScrollPages(0.5)
	MOCK.Shot("page-" .. key .. "-mid")
	ScrollPages(1)
	MOCK.Shot("page-" .. key .. "-end")
end
for i, e in ipairs(MOCK.errors) do print("ERROR " .. i .. ": " .. e) end
