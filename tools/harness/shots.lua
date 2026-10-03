-- Renders each options page (and the module previews) to tools/harness/out.
MOCK.LoadTOC("XerionUI")
MOCK.Fire("PLAYER_LOGIN")
MOCK.Advance(0.5)
local XUI = _G.XerionUI
for _, m in ipairs(XUI.modules) do m:SetEnabled(true) end
SlashCmdList.XERIONUI("")
MOCK.Advance(0.5)
MOCK.crop = "XUI_OptionsFrame"
local keys = { "style", "general", "profiles" }
for _, m in ipairs(XUI.modules) do keys[#keys + 1] = m.key end
for _, key in ipairs(keys) do
	XUI.Options:Open(key)
	MOCK.Advance(0.2)
	MOCK.Shot("page-" .. key)
end
XUI.Options:Open("Stoneform")
for _, m in ipairs(XUI.modules) do m:SetPreview(true) end
MOCK.Advance(0.2)
XUI.Options:Close()
MOCK.crop = nil
for _, m in ipairs(XUI.modules) do m:SetPreview(true) end
MOCK.Advance(0.2)
MOCK.Shot("previews")
XUI:SetUnlocked(true)
MOCK.Advance(0.2)
MOCK.Shot("unlock")
for i, e in ipairs(MOCK.errors) do print("ERROR " .. i .. ": " .. e) end
