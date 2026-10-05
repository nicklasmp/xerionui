--------------------------------------------------------------------------------
-- XerionUI_Options - PageHead.lua
-- (split out of Panel.lua; the window state lives in O.S)
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local S = O.S
local PAGEHEAD_H = O.LAYOUT.PAGEHEAD_H

--------------------------------------------------------------------------------
-- Page header
--------------------------------------------------------------------------------
function O.CreatePageHead(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(PAGEHEAD_H)

	f.iconFrame = CreateFrame("Frame", nil, f)
	f.iconFrame:SetSize(36, 36)
	f.iconFrame:SetPoint("LEFT", 20, 2)
	f.icon = f.iconFrame:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("TOPLEFT", 1, -1)
	f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	f.iconBorder = XUI.Style:Border(f.iconFrame, 1)

	f.title = O:Text(f, O.SIZE.title, "text")
	f.title:SetPoint("TOPLEFT", f.iconFrame, "TOPRIGHT", 14, 0)
	f.desc = O:Text(f, O.SIZE.text, "muted")
	f.desc:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
	f.status = O:Text(f, O.SIZE.small, "danger")
	f.status:SetPoint("TOPLEFT", f.desc, "BOTTOMLEFT", 0, -4)

	-- module controls, right to left
	f.enable = CreateFrame("Button", nil, f)
	f.enable:SetSize(64, 28)
	f.enable:SetPoint("RIGHT", -20, 0)
	f.enable.switch = O.Switch(f.enable)
	f.enable.switch:SetPoint("RIGHT")
	f.enable.label = O:Text(f.enable, O.SIZE.small, "muted")
	f.enable.label:SetPoint("RIGHT", f.enable.switch, "LEFT", -8, 0)
	f.enable:SetScript("OnClick", function()
		local m = f.module
		if m then
			m:SetEnabled(not m.db.enabled)
			O:RefreshPageHead()
			O:RefreshSidebar()
			if S.pages[m.key] then S.pages[m.key]:Refresh() end
		end
	end)

	f.reset = O:IconButton(f, "reset", 28, "Reset to defaults", function()
		local m = f.module
		if not m then return end
		StaticPopup_Show("XERIONUI_RESET_MODULE", m.name, nil, m)
	end)
	f.reset:SetPoint("RIGHT", f.enable, "LEFT", -12, 0)

	f.preview = CreateFrame("Button", nil, f)
	f.preview:SetSize(96, 28)
	f.preview:SetPoint("RIGHT", f.reset, "LEFT", -8, 0)
	O:Skin(f.preview, "control", "controlLine")
	f.preview.icon = O:Icon(f.preview, "eye", 16, "muted")
	f.preview.icon:SetPoint("LEFT", 10, 0)
	f.preview.text = O:Text(f.preview, O.SIZE.text, "label")
	f.preview.text:SetPoint("LEFT", f.preview.icon, "RIGHT", 8, 0)
	f.preview.text:SetText("Preview")
	f.preview:SetScript("OnClick", function()
		local m = f.module
		if m then
			m:SetPreview(not m.preview)
			O:RefreshPageHead()
		end
	end)
	f.preview:SetScript("OnEnter", function(self) O:SetSkinColor(self, "controlHover") end)
	f.preview:SetScript("OnLeave", function(self) O:SetSkinColor(self, "control") end)
	O:Tooltip(f.preview, "Preview", "Shows the module with sample content so you can see your changes. Ends when the window closes.")

	local function HeadButton(icon, text, width, tip, onClick)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(width, 28)
		O:Skin(b, "control", "controlLine")
		b.icon = O:Icon(b, icon, 16, "muted")
		b.icon:SetPoint("LEFT", 10, 0)
		b.text = O:Text(b, O.SIZE.text, "label")
		b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
		b.text:SetText(text)
		b:SetScript("OnClick", onClick)
		b:SetScript("OnEnter", function(self) O:SetSkinColor(self, "controlHover") end)
		b:SetScript("OnLeave", function(self) O:SetSkinColor(self, "control") end)
		if tip then O:Tooltip(b, text, tip) end
		return b
	end

	-- plays a short sample through the module's real code
	f.test = HeadButton("play", "Test", 76, "Runs a short sample through the real code, as if it had been triggered in the game.", function()
		local m = f.module
		if m and m.Test then
			-- a test goes through the real code, not the sample
			if m.preview then S.autoStarted[m] = nil m:SetPreview(false) end
			XUI.SafeCallFor(m, m.Test, m)
			O:RefreshPageHead()
		end
	end)
	f.test:SetPoint("RIGHT", f.preview, "LEFT", -8, 0)

	-- cycles the looks the preview can take
	f.state = HeadButton("layers", "", 150, "Switch which look the preview shows.", function()
		local m = f.module
		local list = m and m.PREVIEW_STATES
		if not list then return end
		local index = 0
		for i, s in ipairs(list) do if s.value == m.previewState then index = i end end
		m:SetPreviewState(list[index % #list + 1].value)
		O:RefreshPageHead()
	end)
	f.state:SetPoint("RIGHT", f.test, "LEFT", -8, 0)

	-- everything needed to understand a problem, as one text to copy
	f.diag = HeadButton("search", "Diagnostics", 118, "A text with the game build, this module's status, its checks, recent errors and its own debug lines - copy it when something does not work.", function()
		local m = f.module
		if m then O:ShowText(m.name .. " - diagnostics", XUI.Health.Report(m)) end
	end)

	f.line = O:Rect(f, "line", "ARTWORK")
	f.line:SetHeight(1)
	f.line:SetPoint("BOTTOMLEFT")
	f.line:SetPoint("BOTTOMRIGHT")
	return f
end

function O:RefreshPageHead()
	local f = S.pageHead
	if not f then return end
	local m = XUI:GetModule(S.currentKey or "")
	f.module = m
	local showModule = m ~= nil
	f.enable:SetShown(showModule)
	f.reset:SetShown(showModule)
	f.preview:SetShown(showModule)
	f.test:SetShown(showModule and m.Test ~= nil)
	local states = showModule and m.PREVIEW_STATES
	f.state:SetShown(states and true or false)
	if states then
		local label = states[1].text
		for _, st in ipairs(states) do if st.value == m.previewState then label = st.text end end
		f.state.text:SetText(label)
		f.state:ClearAllPoints()
		f.state:SetPoint("RIGHT", m.Test and f.test or f.preview, "LEFT", -8, 0)
	end
	local last = (states and f.state) or ((showModule and m.Test) and f.test) or f.preview
	f.diag:SetShown(showModule)
	f.diag:ClearAllPoints()
	f.diag:SetPoint("RIGHT", last, "LEFT", -8, 0)
	f.status:SetText("")
	if m then
		f.icon:SetTexture(XUI.ModuleIcon(m))
		f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.icon:SetVertexColor(1, 1, 1)
		f.iconBorder:Apply({ useGlobal = false, style = "SOLID", size = 1, color = { 0, 0, 0, 1 } })
		f.title:SetText(m.name)
		f.desc:SetText(m.desc or "")
		f.enable.switch:SetState(m.db.enabled)
		f.enable.label:SetText(m.db.enabled and "Enabled" or "Disabled")
		local ok, why = m:CanRun()
		local note = m.untested and "  |cff888888Untested in game.|r" or ""
		if (m.errorCount or 0) > 0 then
			f.status:SetTextColor(O:Color("danger"))
			f.status:SetText(("%d Lua error(s), last: %s"):format(m.errorCount, (m.errors and m.errors[#m.errors] or ""):match("^[^\n]*"):sub(1, 140)))
		elseif m.db.enabled and not ok then
			f.status:SetTextColor(O:Color("danger"))
			f.status:SetText("Not running: " .. (why or "unknown reason"))
		elseif m.db.enabled and m.running and #XUI.Health.Issues(m) > 0 then
			f.status:SetTextColor(1, 0.8, 0.2)
			f.status:SetText("Running, but check this: " .. XUI.Health.Issues(m)[1] .. note)
		elseif m.db.enabled and m.running then
			f.status:SetTextColor(O:Accent())
			f.status:SetText("Running." .. note)
		elseif m.db.enabled then
			f.status:SetTextColor(O:Color("muted"))
			f.status:SetText("Enabled, starting..." .. note)
		else
			f.status:SetTextColor(O:Color("muted"))
			f.status:SetText("Off - switch it on, or use Preview to see it." .. note)
		end
		local ar, ag, ab = O:Accent()
		if m.preview then
			f.preview.icon:SetVertexColor(ar, ag, ab)
			f.preview.text:SetTextColor(ar, ag, ab)
		else
			f.preview.icon:SetVertexColor(O:Color("muted"))
			f.preview.text:SetTextColor(O:Color("label"))
		end
	elseif O.ClassKey(S.currentKey) then
		local c = O.classByToken[O.ClassKey(S.currentKey)]
		f.icon:SetTexture(c and c.icon or 134400)
		f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		f.icon:SetVertexColor(1, 1, 1)
		f.iconBorder:Apply({ useGlobal = false, style = "SOLID", size = 1, color = { 0, 0, 0, 1 } })
		f.title:SetText(c and c.name or "")
		f.desc:SetText(c and c.token ~= "ANY" and "Pick a specialization to see its modules." or "Modules that work for every class.")
	else
		local s
		for _, sp in ipairs(O.systemPages) do if sp.key == S.currentKey then s = sp end end
		f.icon:SetTexture(O.MEDIA .. (s and s.icon or "sliders"))
		f.icon:SetTexCoord(0, 1, 0, 1)
		f.icon:SetVertexColor(O:Accent())
		f.iconBorder:Apply({ useGlobal = false, style = "NONE" })
		f.title:SetText(s and s.title or "")
		f.desc:SetText(s and s.desc or "")
	end
end

--------------------------------------------------------------------------------
-- A window with a text to copy (Ctrl+A, Ctrl+C)
--------------------------------------------------------------------------------
local textPopup

function O:ShowText(title, text)
	if not textPopup then
		local p = CreateFrame("Frame", "XUI_TextPopup", UIParent)
		p:SetSize(640, 440)
		p:SetFrameStrata("FULLSCREEN_DIALOG")
		p:SetPoint("CENTER")
		p:SetToplevel(true)
		p:EnableMouse(true)
		O:Skin(p, "window", "line")
		tinsert(UISpecialFrames, "XUI_TextPopup")
		p.title = O:Text(p, O.SIZE.heading, "text")
		p.title:SetPoint("TOPLEFT", 16, -14)
		p.hint = O:Text(p, O.SIZE.small, "muted")
		p.hint:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -4)
		p.hint:SetText("Press Ctrl+C to copy, then paste it where it is needed.")
		local close = O:IconButton(p, "close", 26, nil, function() p:Hide() end)
		close:SetPoint("TOPRIGHT", -8, -8)
		local holder = CreateFrame("Frame", nil, p)
		holder:SetPoint("TOPLEFT", 16, -62)
		holder:SetPoint("BOTTOMRIGHT", -16, 16)
		O:Skin(holder, "control", "controlLine")
		local sf = CreateFrame("ScrollFrame", nil, holder, "ScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 6, -6)
		sf:SetPoint("BOTTOMRIGHT", -24, 6)
		local box = CreateFrame("EditBox", nil, sf)
		box:SetMultiLine(true)
		box:SetWidth(580)
		box:SetAutoFocus(false)
		box:SetFont(O:FontPath(), O.SIZE.small, "")
		box:SetTextColor(O:Color("text"))
		box:SetScript("OnEscapePressed", function() p:Hide() end)
		sf:SetScrollChild(box)
		sf:SetScript("OnSizeChanged", function(_, w) box:SetWidth(w) end)
		p.box = box
		textPopup = p
	end
	textPopup.title:SetText(title or "")
	textPopup.box:SetText(text or "")
	textPopup:Show()
	textPopup.box:SetFocus()
	textPopup.box:HighlightText()
end

StaticPopupDialogs.XERIONUI_RESET_MODULE = {
	text = "Reset all settings of %s to their defaults?",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, m)
		m:Reset()
		if S.pages[m.key] then S.pages[m.key]:Refresh() end
		O:RefreshPageHead()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
