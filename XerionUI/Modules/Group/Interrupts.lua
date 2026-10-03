--------------------------------------------------------------------------------
-- Party Interrupts
-- Every party member's interrupt as a bar (or an icon beside their
-- EllesmereUI party frame) that drains while it is on cooldown.
--
-- WHO KICKED, WHEN THE GAME WILL NOT SAY
-- In a key a party member's cast IDs and the interruptedBy GUID are secret.
-- What is left:
--   * your own kick's cooldown is readable;
--   * "an enemy's cast was interrupted" (UNIT_SPELLCAST_INTERRUPTED) still
--     fires, just without the kicker;
--   * the built-in damage meter's Interrupts list. Its amounts are secret,
--     but the ORDER is not (the client sorts before handing it over), and per
--     entry classFilename, specIconID and isLocalPlayer are never secret.
--     Only the kicker's amount changes on a kick, so a newcomer to the list,
--     or an entry that climbed, is the kicker; a one-entry list names them.
-- Cast-ended events and meter hits are queued separately and paired oldest
-- first (two kicks a moment apart are two of each); an event no meter hit
-- confirms was a stun, a knock or a death and expires.
--
-- HEALER KICK LENGTH
-- A Restoration Shaman's Wind Shear is 30 s while the other specs keep 12,
-- under the same spell ID, so a member who heals uses the healer length; the
-- spec decides once an inspect has told it, the assigned role until then.
--
-- YOUR OWN COOLDOWN IS LEARNED
-- Talents shorten kicks (Coldthirst refunds Mind Freeze on a successful
-- interrupt). The real duration is read when the client allows and the
-- shortest one seen is remembered per character - but a measured length may
-- only ever shorten the table's value, never lengthen it.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style
local D = XUI.Data

local M = XUI:NewModule("Interrupts", {
	name = "Party Interrupts",
	desc = "Tracks your party's interrupt cooldowns, even inside keys.",
	category = "group",
	icon = [[Interface\Icons\Ability_Kick]],
	order = 30,
	defaults = {
		showSelf = true,
		groupOnly = true,
		hideInRaid = true,
		showReady = true,
		showIcon = true,
		iconSource = "kick",
		showTimer = true,
		showMark = true,
		growth = "DOWN",
		spacing = 2,
		iconGap = 2,
		observe = true,
		meterConfirm = true,
		partyCd = 15,
		displayMode = "bar",
		partySide = "RIGHT",
		partyGap = 3,
		bar = T.Bar(180, 20),
		border = T.Border(),
		nameText = T.Font(12),
		timerText = T.Font(12),
		icon = T.Icon(24),
		position = T.Position(-420, 0),
	},
})

M.MODES = { { value = "bar", text = "Bars" }, { value = "icon", text = "Icons on party frames" } }
M.ICON_SOURCES = { { value = "kick", text = "The interrupt" }, { value = "kicked", text = "The interrupted spell" } }
M.GROWTH = { { value = "DOWN", text = "Down" }, { value = "UP", text = "Up" } }
M.SIDES = { { value = "LEFT", text = "Left" }, { value = "RIGHT", text = "Right" } }

local IsSecret, Ask = XUI.IsSecret, XUI.Ask
local KICKS = D.KICKS
local floor, abs, max = math.floor, math.abs, math.max
local format = string.format

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
local PET_OF = { player = "pet", party1 = "partypet1", party2 = "partypet2", party3 = "partypet3", party4 = "partypet4" }
local CAST_OWNER = {}
for unit, pet in pairs(PET_OF) do
	CAST_OWNER[unit] = unit
	CAST_OWNER[pet] = unit
end
local KICK_ICON = [[Interface\Icons\Ability_Kick]]

local function Read(fn, ...)
	if not fn then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or IsSecret(v) then return nil end
	return v
end

local obs = { total = 0, readable = 0, secret = 0, mine = 0, guessed = 0, unmatched = 0, meter = 0, confirmed = 0, named = 0, unconfirmed = 0 }

--------------------------------------------------------------------------------
-- Members and lengths
--------------------------------------------------------------------------------
local members = {}
local specByGUID = {}

local function Heals(spec, role)
	if spec then return D.HEALER_SPEC[spec] or false end
	return role == "HEALER"
end

local function KickCd(spell, heals)
	local kick = spell and KICKS[spell]
	if not kick then return nil end
	return heals and kick.healerCd or kick.cd
end

local function MemberSpell(m)
	if m.spec and D.SPEC_KICK[m.spec] ~= nil then return D.SPEC_KICK[m.spec] or nil end
	if m.role == "HEALER" and D.HEALER_NO_KICK[m.class] then return nil end
	return D.CLASS_KICK[m.class]
end

local function MemberCd(row)
	local spell = row.spell
	if spell and KICKS[spell] then return row.cd or KICKS[spell].cd end
	return M.db.partyCd
end

local learnedSwept = false
local function LearnedStore()
	local char = XUI.DB.char
	char.interruptLearned = type(char.interruptLearned) == "table" and char.interruptLearned or {}
	local store = char.interruptLearned
	if not learnedSwept then
		learnedSwept = true
		for spell, v in pairs(store) do
			local cap = KICKS[spell] and KICKS[spell].cd
			if type(v) == "number" and cap and v > cap + 0.25 then store[spell] = nil end
		end
	end
	return store
end

-- our own kick on its healer length is never learned (the store keeps the
-- shortest length, and the other specs would teach it theirs)
local function OwnHealerCd(spell)
	local m = members.player
	return m and m.heals and KICKS[spell] and KICKS[spell].healerCd or nil
end

local function LearnLength(spell, secs)
	if not spell or type(secs) ~= "number" or secs < 3 or OwnHealerCd(spell) then return end
	local cap = KICKS[spell] and KICKS[spell].cd
	if cap and secs > cap + 0.25 then return end
	local store = LearnedStore()
	local cur = store[spell]
	if type(cur) ~= "number" or secs < cur then store[spell] = floor(secs * 2 + 0.5) / 2 end
end

local function OwnCd(spell)
	local healer = OwnHealerCd(spell)
	if healer then return healer end
	local v = spell and LearnedStore()[spell]
	if type(v) == "number" and v > 0 then return v end
	local cap = spell and KICKS[spell] and KICKS[spell].cd
	return cap or M.db.partyCd
end

local function SelfSpecId()
	return XUI.GetSpecID()
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------
local holder
local rows, pool, shown = {}, {}, {}

local function Holder()
	if holder then return holder end
	holder = CreateFrame("Frame", "XUI_Interrupts", UIParent)
	holder:SetSize(180, 20)
	holder:Hide()
	XUI.Movers:Register(holder, M, "position")
	return holder
end

local function NewRow()
	local row = CreateFrame("Frame", nil, holder)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.iconBox = CreateFrame("Frame", nil, row)
	row.icon = row.iconBox:CreateTexture(nil, "ARTWORK")
	row.iconBorder = Style:Border(row.iconBox)
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
	row.mark:Hide()
	row.barBox = CreateFrame("Frame", nil, row)
	row.bar = CreateFrame("StatusBar", nil, row.barBox)
	row.bar:SetMinMaxValues(0, 1)
	row.bar:SetValue(1)
	row.barBorder = Style:Border(row.barBox)
	row.texts = CreateFrame("Frame", nil, row)
	row.texts:SetAllPoints(row.barBox)
	row.name = row.texts:CreateFontString(nil, "OVERLAY")
	row.name:SetWordWrap(false)
	row.timer = row.texts:CreateFontString(nil, "OVERLAY")
	Style:ApplyFont(row.name, nil, 12)
	Style:ApplyFont(row.timer, nil, 12)
	row.swipe = CreateFrame("Cooldown", nil, row.iconBox, "CooldownFrameTemplate")
	row.swipe:SetDrawEdge(false)
	row.swipe:SetDrawBling(false)
	row.swipe:SetHideCountdownNumbers(true)
	row.swipe:Hide()
	return row
end

local function AcquireRow()
	local row = table.remove(pool) or NewRow()
	row.cdStart, row.cdDur, row.previewRestart = nil, nil, nil
	row.kickedTex, row.markIdx, row.previewKicked = nil, nil, nil
	return row
end

local function ReleaseRow(row)
	row:Hide()
	row.cdStart, row.cdDur, row.previewRestart, row.guid = nil, nil, nil, nil
	row.kickedTex, row.markIdx, row.previewKicked = nil, nil, nil
	-- cleared, not just hidden: a pooled row must not carry a marker over
	row.hasMark = nil
	row.mark:Hide()
	pool[#pool + 1] = row
end

-- In a key the interrupted spell's ID is secret, but its texture travels
-- through C_Spell.GetSpellTexture and SetTexture untouched: row.kickedTex is
-- only ever stored and handed to SetTexture.
local function PaintIcon(row)
	if M.db.iconSource == "kicked" and type(row.kickedTex) ~= "nil"
		and pcall(row.icon.SetTexture, row.icon, row.kickedTex) then
		return
	end
	row.icon:SetTexture(XUI.GetSpellIcon(row.spell, KICK_ICON))
end

local function Inset(region, parent, inset)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
	region:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
end

local function StyleRow(row)
	local db = M.db
	row.__urgent, row.__lastText = nil, nil
	if db.displayMode == "icon" then
		local i = Style:Resolve("icon", db.icon)
		local w, h = i.width or 24, i.height or i.width or 24
		row:SetSize(w, h)
		row.bg:Hide()
		row.mark:Hide()
		row.barBox:Hide()
		row.iconBox:ClearAllPoints()
		row.iconBox:SetAllPoints(row)
		row.iconBox:Show()
		-- the seconds sit on the icon, above the swipe
		row.texts:ClearAllPoints()
		row.texts:SetAllPoints(row.iconBox)
		row.texts:SetFrameLevel(row.iconBox:GetFrameLevel() + 6)
		row.texts:Show()
		row.name:Hide()
		Style:ApplyFont(row.timer, db.timerText)
		row.timer:ClearAllPoints()
		row.timer:SetPoint("CENTER", row.iconBox, "CENTER", 0, 0)
		row.timer:SetJustifyH("CENTER")
		row.timer:SetShown(db.showTimer)
		local inset = row.iconBorder:Apply(db.border)
		Inset(row.icon, row.iconBox, inset)
		Inset(row.swipe, row.iconBox, inset)
		Style:IconTexCoord(row.icon, w, h, i.zoom)
		if row.cdStart and row.cdDur then
			row.swipe:SetCooldown(row.cdStart, row.cdDur)
			row.swipe:Show()
		else
			row.swipe:Hide()
		end
		PaintIcon(row)
		return
	end
	local b = Style:Resolve("bar", db.bar)
	local w, h = b.width or 180, b.height or 20
	row:SetSize(w, h)
	row.swipe:Hide()
	row.texts:ClearAllPoints()
	row.texts:SetAllPoints(row.barBox)
	row.texts:Show()
	row.name:Show()
	local r, g, bl = XUI.ClassColor(row.class)
	local left = 0
	row.iconBox:SetShown(db.showIcon)
	if db.showIcon then
		row.iconBox:ClearAllPoints()
		row.iconBox:SetPoint("TOPLEFT")
		row.iconBox:SetSize(h, h)
		local inset = row.iconBorder:Apply(db.border)
		Inset(row.icon, row.iconBox, inset)
		Style:IconTexCoord(row.icon, h, h)
		-- the gap between icon and bar is a hole, not a sliver of background
		left = h + db.iconGap
	end
	row.barBox:ClearAllPoints()
	row.barBox:SetPoint("TOPLEFT", left, 0)
	row.barBox:SetPoint("BOTTOMRIGHT")
	row.barBox:Show()
	local inset = row.barBorder:Apply(db.border)
	Inset(row.bar, row.barBox, inset)
	Style:ApplyBar(row.bar, db.bar)
	row.bar:SetStatusBarColor(r, g, bl)
	row.bg:Hide()
	row.mark:ClearAllPoints()
	row.mark:SetPoint("RIGHT", row, "LEFT", -3, 0)
	row.mark:SetSize(h, h)
	row.mark:SetShown((db.showMark and row.hasMark) and true or false)
	Style:ApplyFont(row.timer, db.timerText)
	row.timer:ClearAllPoints()
	row.timer:SetPoint("RIGHT", row.bar, "RIGHT", -4, 0)
	row.timer:SetJustifyH("RIGHT")
	row.timer:SetShown(db.showTimer)
	Style:ApplyFont(row.name, db.nameText)
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", row.bar, "LEFT", 4, 0)
	row.name:SetPoint("RIGHT", row.timer, "LEFT", -4, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetText(row.label or "")
	PaintIcon(row)
end

-- The preview rows have no unit; in icon mode they take the party frames that
-- exist, in order, so the placement beside the frames can be judged.
local PREVIEW_UNITS = { "player", "party1", "party2", "party3", "party4" }
local function PreviewUnits()
	local out = {}
	if XUI.EUI then
		for _, u in ipairs(PREVIEW_UNITS) do
			if XUI.EUI.PartyHealthBar(u) then out[#out + 1] = u end
		end
	end
	return out
end

local function Layout(list)
	local db = M.db
	local iconMode = db.displayMode == "icon"
	local gap = iconMode and db.partyGap or db.spacing
	local first = list[1]
	if first then holder:SetSize(first:GetWidth(), first:GetHeight()) end
	local previewUnits = iconMode and M:IsPreview() and PreviewUnits() or nil
	local prev
	for _, row in ipairs(list) do
		row:ClearAllPoints()
		local unit = row.unit or (previewUnits and previewUnits[row.order or 0])
		local health = iconMode and unit and XUI.EUI and XUI.EUI.PartyHealthBar(unit)
		if previewUnits and #previewUnits > 0 and not unit then
			-- more sample rows than party frames: only members have an icon
			row:Hide()
		elseif health then
			-- beside EllesmereUI's party health bar, in its strata and above it
			local strata = health:GetFrameStrata()
			if strata then row:SetFrameStrata(strata) end
			row:SetFrameLevel(health:GetFrameLevel() + 5)
			if db.partySide == "LEFT" then
				row:SetPoint("RIGHT", health, "LEFT", -gap, 0)
			else
				row:SetPoint("LEFT", health, "RIGHT", gap, 0)
			end
		else
			row:SetFrameStrata(holder:GetFrameStrata())
			row:SetFrameLevel(holder:GetFrameLevel() + 1)
			if not prev then
				row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
			elseif db.growth == "UP" then
				row:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, gap)
			else
				row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap)
			end
			prev = row
		end
	end
end

local function ShouldShow()
	if M:IsPreview() then return true end
	local db = M.db
	if not M.running or #shown == 0 then return false end
	if db.groupOnly and not IsInGroup() then return false end
	if db.hideInRaid and IsInRaid() then return false end
	return true
end

-- busy rows first, soonest back on top; ready rows by shortest cooldown
local function StackBefore(a, b)
	local ra, rb = a.cdStart ~= nil, b.cdStart ~= nil
	if ra ~= rb then return rb end
	if ra then
		local la, lb = a.cdStart + a.cdDur, b.cdStart + b.cdDur
		if la ~= lb then return la < lb end
	else
		local ca = KICKS[a.spell] and (a.cd or KICKS[a.spell].cd) or 99
		local cb = KICKS[b.spell] and (b.cd or KICKS[b.spell].cd) or 99
		if ca ~= cb then return ca < cb end
	end
	return (a.order or 0) < (b.order or 0)
end

local function ShowRows()
	table.sort(shown, StackBefore)
	local visible = {}
	for _, row in ipairs(shown) do
		if row:IsShown() then visible[#visible + 1] = row end
	end
	Layout(visible)
	holder:SetShown(ShouldShow())
end

local Tick
local function StartTicker()
	if holder and not holder:GetScript("OnUpdate") then
		holder.__acc = 0
		holder:SetScript("OnUpdate", Tick)
	end
end

local function SetMark(row, idx)
	row.hasMark = false
	row.markIdx = idx
	if type(idx) ~= "nil" and SetRaidTargetIconTexture then
		row.hasMark = pcall(SetRaidTargetIconTexture, row.mark, idx) and true or false
	end
	row.mark:SetShown((row.hasMark and M.db.showMark and M.db.displayMode ~= "icon") and true or false)
end

local function SetKicked(row, tex)
	row.kickedTex = tex
	PaintIcon(row)
end

local function SetReady(row)
	row.cdStart, row.cdDur = nil, nil
	row.timer:SetText("")
	row.__lastText = nil
	row.bar:SetMinMaxValues(0, 1)
	row.bar:SetValue(1)
	row.swipe:Hide()
	SetMark(row, nil)
	SetKicked(row, nil)
	if not M.db.showReady and not M:IsPreview() then row:Hide() end
	ShowRows()
end

local function StartCooldown(row, start, dur)
	if not dur or dur <= 0 then return end
	row.cdStart, row.cdDur = start, dur
	if M.db.displayMode == "icon" then
		row.swipe:SetCooldown(start, dur)
		row.swipe:Show()
	end
	row.bar:SetMinMaxValues(0, dur)
	row.bar:SetValue(dur - (GetTime() - start))
	row:Show()
	ShowRows()
	StartTicker()
end

--------------------------------------------------------------------------------
-- Your own row
--------------------------------------------------------------------------------
local function RefreshSelf(castSpell)
	local row = rows.player
	if not row or M:IsPreview() then return end
	local poll = row.poll or row.spell
	local now = GetTime()
	local info = poll and C_Spell.GetSpellCooldown(poll)
	if not info then
		if castSpell and KICKS[castSpell] and not row.cdStart then StartCooldown(row, now, OwnCd(castSpell)) end
		return
	end
	local active, onGCD = XUI.Readable(info.isActive), XUI.Readable(info.isOnGCD)
	local running = (active and not onGCD) and true or false
	if not running then
		if row.cdStart then SetReady(row) end
		return
	end
	local st, du = info.startTime, info.duration
	if not IsSecret(st) and not IsSecret(du) and type(st) == "number" and type(du) == "number" and du > 2 then
		LearnLength(poll, du)
		if not row.cdStart or row.cdDur ~= du or abs(row.cdStart - st) > 0.5 then StartCooldown(row, st, du) end
		row.fromCast = nil
		return
	end
	if row.cdStart then return end
	StartCooldown(row, now, OwnCd(poll))
	row.fromCast = castSpell ~= nil
end

local function SelfStillDown(row, now)
	row.__pollAt = now
	local poll = row.poll or row.spell
	local info = poll and C_Spell.GetSpellCooldown(poll)
	if not info then return true end
	local active, onGCD = XUI.Readable(info.isActive), XUI.Readable(info.isOnGCD)
	if active == nil then return true end
	return (active and not onGCD) and true or false
end

local function SelfEndedEarly(row, now)
	if SelfStillDown(row, now) then return false end
	if row.fromCast then LearnLength(row.poll or row.spell, now - row.cdStart) end
	row.fromCast = nil
	return true
end

-- whole seconds, rounded up so it never reads 0 while time remains
local function FormatRem(rem)
	return format("%d", math.ceil(rem))
end

local URGENT = 3 -- seconds left when the number turns red
local function PaintTimerColor(row, urgent)
	if urgent then
		row.timer:SetTextColor(1, 0.2, 0.2, 1)
	else
		local c = Style:Resolve("font", M.db.timerText).color
		row.timer:SetTextColor(XUI.UnpackColor(c, 1, 1, 1, 1))
	end
end

-- 20 times a second while any bar runs; stops itself when none does. The
-- timer text is cached so it is only written when what it prints changes.
Tick = function(self, elapsed)
	self.__acc = (self.__acc or 0) + elapsed
	if self.__acc < 0.05 then return end
	self.__acc = 0
	local now, busy = GetTime(), false
	local preview = M:IsPreview()
	local showTimer = M.db.showTimer
	for _, row in ipairs(shown) do
		if row.cdStart then
			local rem = row.cdStart + row.cdDur - now
			if rem <= 0 and row.unit == "player" and not preview and SelfStillDown(row, now) then
				-- the table length was too short: stretch rather than lie
				row.cdDur = row.cdDur + 0.5
				row.bar:SetMinMaxValues(0, row.cdDur)
				busy = true
			elseif rem <= 0 then
				if preview then row.previewRestart = now + 2 busy = true end
				SetReady(row)
			elseif row.unit == "player" and not preview and now - (row.__pollAt or 0) >= 0.15 and SelfEndedEarly(row, now) then
				SetReady(row)
			else
				row.bar:SetValue(rem)
				if showTimer then
					local text = FormatRem(rem)
					if text ~= row.__lastText then
						row.__lastText = text
						row.timer:SetText(text)
					end
					local urgent = rem <= URGENT
					if urgent ~= row.__urgent then
						row.__urgent = urgent
						PaintTimerColor(row, urgent)
					end
				end
				busy = true
			end
		elseif preview and row.previewRestart then
			if now >= row.previewRestart then
				row.previewRestart = nil
				StartCooldown(row, now, row.cd or 15)
				SetMark(row, 8)
				SetKicked(row, row.previewKicked)
			end
			busy = true
		end
	end
	if not busy then self:SetScript("OnUpdate", nil) end
end

--------------------------------------------------------------------------------
-- Inspecting party members for their spec
--------------------------------------------------------------------------------
local inspectQueue = {}
local inspectTicker
local lastInspectAt = 0
local QueueInspect, ScheduleRebuild

local function UnitForGUID(guid)
	for unit, m in pairs(members) do
		if m.guid == guid then return unit end
	end
end

local function ReadSpec(unit)
	local CSI = C_SpecializationInfo
	local get = (CSI and CSI.GetInspectSpecialization) or _G.GetInspectSpecialization
	local spec = Read(get, unit)
	if type(spec) == "number" and spec > 0 then return spec end
	return nil
end

local function StopInspects()
	wipe(inspectQueue)
	if inspectTicker then M:CancelTicker(inspectTicker) inspectTicker = nil end
	for _, m in pairs(members) do m.tries = nil end
end

local function InspectStep()
	if #inspectQueue == 0 then
		M:CancelTicker(inspectTicker)
		inspectTicker = nil
		return
	end
	if InspectFrame and InspectFrame:IsShown() then return end
	if GetTime() - lastInspectAt < 2 then return end
	local unit = table.remove(inspectQueue, 1)
	local m = members[unit]
	if not m or m.spec then return end
	if m.guid and specByGUID[m.guid] then
		m.spec = specByGUID[m.guid]
		ScheduleRebuild()
		return
	end
	m.tries = (m.tries or 0) + 1
	if m.tries > 12 then
		M:After(30, function()
			local cur = members[unit]
			if cur and cur.guid == m.guid and not cur.spec then
				cur.tries = 0
				QueueInspect(unit)
			end
		end)
		return
	end
	if Read(CanInspect, unit) and NotifyInspect then
		lastInspectAt = GetTime()
		pcall(NotifyInspect, unit)
	end
	inspectQueue[#inspectQueue + 1] = unit
end

QueueInspect = function(unit)
	for _, u in ipairs(inspectQueue) do if u == unit then return end end
	inspectQueue[#inspectQueue + 1] = unit
	if not inspectTicker then inspectTicker = M:NewTicker(1, InspectStep) end
end

local function OnInspectReady(guid)
	if IsSecret(guid) then return end
	local unit = UnitForGUID(guid)
	if not unit then return end
	local spec = ReadSpec(unit)
	if spec then
		specByGUID[guid] = spec
		if members[unit].spec ~= spec then
			members[unit].spec = spec
			ScheduleRebuild()
		end
	end
end

--------------------------------------------------------------------------------
-- The roster
--------------------------------------------------------------------------------
local function Rebuild()
	if M:IsPreview() or not holder or not M.running then return end
	local db = M.db
	local old = members
	members = {}
	wipe(shown)
	local keep = {}
	for idx, unit in ipairs(UNITS) do
		local isSelf = unit == "player"
		if (not isSelf or db.showSelf) and UnitExists(unit) then
			local class = Read(UnitClassBase, unit)
			if class then
				local guid = Read(UnitGUID, unit)
				local m = {
					guid = guid,
					name = Read(UnitName, unit),
					class = class,
					role = Read(UnitGroupRolesAssigned, unit),
					spec = guid and specByGUID[guid] or nil,
					tries = old[unit] and old[unit].guid == guid and old[unit].tries or nil,
				}
				m.heals = Heals(isSelf and SelfSpecId() or m.spec, m.role)
				members[unit] = m
				local spell, poll
				if isSelf then
					spell, poll = D.PlayerKick()
				else
					spell = MemberSpell(m)
					if not m.spec then QueueInspect(unit) end
				end
				m.spell = spell
				if spell then
					local row = rows[unit]
					if row and row.guid ~= guid then
						ReleaseRow(row)
						row = nil
					end
					if not row then
						row = AcquireRow()
						rows[unit] = row
					end
					keep[unit] = true
					row.unit, row.guid, row.class, row.order = unit, guid, class, idx
					row.label = m.name or unit
					row.spell, row.poll = spell, poll
					row.cd = KickCd(spell, m.heals) or 15
					StyleRow(row)
					if not row.cdStart then
						row.bar:SetMinMaxValues(0, 1)
						row.bar:SetValue(1)
						row.timer:SetText("")
						row.__lastText = nil
					end
					row:SetShown((db.showReady or row.cdStart ~= nil) and true or false)
					shown[#shown + 1] = row
				end
			end
		end
	end
	for unit, row in pairs(rows) do
		if not keep[unit] then
			ReleaseRow(row)
			rows[unit] = nil
		end
	end
	ShowRows()
	RefreshSelf()
end

local rebuildPending = false
ScheduleRebuild = function()
	if rebuildPending then return end
	rebuildPending = true
	M:After(0.2, function()
		rebuildPending = false
		Rebuild()
	end)
end

--------------------------------------------------------------------------------
-- Preview
--------------------------------------------------------------------------------
local PREVIEW = {
	{ label = "Xerion", class = "DEATHKNIGHT", spell = 47528, kicked = [[Interface\Icons\Spell_Shadow_ShadowBolt]] },
	{ label = "Brewnado", class = "MONK", spell = 116705, kicked = [[Interface\Icons\Spell_Frost_FrostBolt02]] },
	{ label = "Pyroclast", class = "MAGE", spell = 2139, kicked = [[Interface\Icons\Spell_Holy_FlashHeal]] },
	{ label = "Stormcall", class = "SHAMAN", spell = 57994, kicked = [[Interface\Icons\Spell_Fire_FlameBolt]] },
	{ label = "Nightblade", class = "ROGUE", spell = 1766, kicked = [[Interface\Icons\Spell_Nature_Lightning]] },
}

local function ReleaseAll()
	for unit, row in pairs(rows) do
		ReleaseRow(row)
		rows[unit] = nil
	end
	wipe(shown)
end

local function BuildPreview()
	ReleaseAll()
	local now = GetTime()
	for i, p in ipairs(PREVIEW) do
		local row = AcquireRow()
		rows["preview" .. i] = row
		row.unit, row.guid, row.class, row.order = nil, nil, p.class, i
		row.label, row.spell, row.poll = p.label, p.spell, nil
		row.cd = KICKS[p.spell].cd
		row.previewKicked = p.kicked
		StyleRow(row)
		row:Show()
		shown[#shown + 1] = row
		if i == 1 then
			row.bar:SetMinMaxValues(0, 1)
			row.bar:SetValue(1)
			row.previewRestart = now + 3
		else
			StartCooldown(row, now - (i - 1) * 2.5, row.cd)
			SetMark(row, 10 - i)
			SetKicked(row, p.kicked)
		end
	end
	ShowRows()
	StartTicker()
end

--------------------------------------------------------------------------------
-- Casts and interrupts
--------------------------------------------------------------------------------
local lastSelfKickAt, selfClaimKick = -10, -20
local lastObservedAt, lastObservedUnit = -10, nil
local lastGuessRow, lastGuessAt = nil, -10

local function MarkSelf(mark, tex)
	local row = rows.player
	if row then
		M:After(0, function()
			if row.cdStart then
				SetMark(row, mark)
				SetKicked(row, tex)
			end
		end)
	end
end

local function OnCast(unit, spellID)
	local owner = CAST_OWNER[unit]
	if not owner or IsSecret(spellID) then return end
	local kick = KICKS[spellID]
	if not kick then return end
	-- a guess handed back takes its marker and interrupted-spell icon along
	local handed, handMark, handTex
	if owner == "player" then
		lastSelfKickAt = GetTime()
		if lastGuessRow and GetTime() - lastGuessAt < 0.4 then
			handed, handMark, handTex = true, lastGuessRow.markIdx, lastGuessRow.kickedTex
			SetReady(lastGuessRow)
			obs.guessed = obs.guessed - 1
			obs.mine = obs.mine + 1
			lastGuessRow = nil
			selfClaimKick = lastSelfKickAt
		end
	end
	if M:IsPreview() then return end
	local row = rows[owner]
	if not row or row.class ~= kick.class then return end
	if owner == "player" then
		M:After(0, function() RefreshSelf(spellID) end)
		if handed then MarkSelf(handMark, handTex) end
		return
	end
	local iconSpell = kick.icon or spellID
	if row.spell ~= iconSpell then
		row.spell = iconSpell
		row.cd = KickCd(spellID, members[owner] and members[owner].heals)
		if members[owner] then members[owner].spell = iconSpell end
		StyleRow(row)
	end
	lastObservedAt, lastObservedUnit = GetTime(), owner
	StartCooldown(row, GetTime(), MemberCd(row))
end

local function OwnerOfGUID(guid)
	local owner = UnitForGUID(guid)
	if owner then return owner end
	for _, unit in ipairs(PARTY_UNITS) do
		if members[unit] and Read(UnitGUID, PET_OF[unit]) == guid then return unit end
	end
	if Read(UnitGUID, "pet") == guid then return "player" end
	return nil
end

-- The damage meter's Interrupts list (see the top of the file).
local SESSIONS = { "Current", "Overall" }
local meterSnap = {}
local specIconCache = {}

local function SpecIcon(specID)
	if not specID then return nil end
	local cached = specIconCache[specID]
	if cached ~= nil then return cached or nil end
	local CSI = C_SpecializationInfo
	local get = (CSI and CSI.GetSpecializationInfoByID) or _G.GetSpecializationInfoByID
	local ok, _, _, _, icon = pcall(get, specID)
	if not ok or IsSecret(icon) or type(icon) ~= "number" then icon = false end
	specIconCache[specID] = icon
	return icon or nil
end

local function ShortName(n)
	return (tostring(n):gsub("%-.*$", ""))
end

local function ReadMeterList(sessionType)
	local DM = C_DamageMeter
	if not (DM and DM.GetCombatSessionFromType and Enum.DamageMeterType and Enum.DamageMeterType.Interrupts) then return nil end
	local ok, session = pcall(DM.GetCombatSessionFromType, sessionType, Enum.DamageMeterType.Interrupts)
	if not ok or type(session) ~= "table" or type(session.combatSources) ~= "table" then return nil end
	local list, seen = {}, {}
	for _, src in ipairs(session.combatSources) do
		if type(src) == "table" then
			local class = src.classFilename
			if IsSecret(class) or type(class) ~= "string" or class == "" then class = nil end
			if class then
				local me = src.isLocalPlayer
				if IsSecret(me) then me = nil else me = me and true or false end
				local icon = src.specIconID
				if IsSecret(icon) or type(icon) ~= "number" then icon = nil end
				local name = src.name
				if IsSecret(name) or type(name) ~= "string" or name == "" then name = nil end
				local key = name and ShortName(name) or (class .. ":" .. tostring(icon) .. (me and ":me" or ""))
				seen[key] = (seen[key] or 0) + 1
				if seen[key] > 1 then key = key .. "#" .. seen[key] end
				list[#list + 1] = { key = key, class = class, icon = icon, me = me, name = name }
			end
		end
	end
	return list
end

local function MatchMember(e, out)
	local n = 0
	for _, unit in ipairs(UNITS) do
		local m = members[unit]
		local isMe = unit == "player"
		local okUnit = e.me ~= nil and e.me and isMe
		if not okUnit and m and m.class == e.class then
			okUnit = e.me == nil or (e.me == isMe)
			if okUnit and e.name and m.name and ShortName(e.name) ~= ShortName(m.name) then okUnit = false end
			if okUnit and e.icon and m.spec then
				local icon = SpecIcon(m.spec)
				if icon and icon ~= e.icon then okUnit = false end
			end
		end
		if okUnit and not out[unit] then
			out[unit] = true
			n = n + 1
		end
	end
	return n
end

local function DiffMeter(sessionType)
	local list = ReadMeterList(sessionType)
	if not list then return nil end
	local old = meterSnap[sessionType]
	meterSnap[sessionType] = list
	if #list == 1 then return list[1], list end
	if not old then return nil, list end
	local oldIdx = {}
	for i, e in ipairs(old) do oldIdx[e.key] = i end
	local newcomer, climber, nNew, nClimb = nil, nil, 0, 0
	for i, e in ipairs(list) do
		local o = oldIdx[e.key]
		if not o then
			newcomer, nNew = e, nNew + 1
		elseif i < o then
			climber, nClimb = e, nClimb + 1
		end
	end
	if nNew == 1 then return newcomer, list end
	if nNew == 0 and nClimb == 1 then return climber, list end
	return nil, list
end

local function MeterKicker()
	local ST = Enum and Enum.DamageMeterSessionType
	if not ST then return nil, nil end
	local cands, narrowed = {}, false
	for _, name in ipairs(SESSIONS) do
		local st = ST[name]
		if st then
			local e, list = DiffMeter(st)
			if e then
				local mine = {}
				if MatchMember(e, mine) == 1 then return next(mine), mine end
				if next(mine) and not narrowed then cands, narrowed = mine, true end
			elseif list and not narrowed then
				for _, entry in ipairs(list) do MatchMember(entry, cands) end
			end
		end
	end
	if not next(cands) then cands = nil end
	return nil, cands
end

local function GuessKicker(cands, allowBusy)
	local best
	for _, unit in ipairs(PARTY_UNITS) do
		local row = rows[unit]
		if row and (allowBusy or not row.cdStart) and (not cands or cands[unit]) and (not best or StackBefore(row, best)) then best = row end
	end
	return best
end

local pendings, meterHits = {}, {}

local function CloserToOwnKick(at)
	local d = abs(at - lastSelfKickAt)
	for _, q in ipairs(pendings) do
		if abs(q.at - lastSelfKickAt) < d then return true end
	end
	return false
end

local function Charge(at, owner, mark, cands, tex)
	if owner then
		if owner == "player" then RefreshSelf() MarkSelf(mark, tex) return end
		lastObservedAt, lastObservedUnit = at, owner
		local row = rows[owner]
		if row then
			StartCooldown(row, at, MemberCd(row))
			SetMark(row, mark)
			SetKicked(row, tex)
		end
		return
	end
	lastObservedAt = at
	-- one own kick claims exactly one interrupt
	if lastSelfKickAt ~= selfClaimKick and abs(at - lastSelfKickAt) < 0.8 and not CloserToOwnKick(at) then
		selfClaimKick = lastSelfKickAt
		obs.mine = obs.mine + 1
		lastObservedUnit = "player"
		MarkSelf(mark, tex)
		return
	end
	-- the meter's candidates beat our own ready/busy bookkeeping
	local row = GuessKicker(cands)
	if not row and cands then row = GuessKicker(cands, true) or GuessKicker(nil) end
	if not row then
		obs.unmatched = obs.unmatched + 1
		lastObservedUnit = nil
		return
	end
	obs.guessed = obs.guessed + 1
	lastObservedUnit = row.unit
	lastGuessRow, lastGuessAt = row, at
	StartCooldown(row, at, MemberCd(row))
	SetMark(row, mark)
	SetKicked(row, tex)
end

local lastEventAt = -10

local function Expire(list, now, onDrop)
	while list[1] and now - list[1].at > 1.5 do
		local e = table.remove(list, 1)
		if onDrop then onDrop(e) end
	end
end

local function DropUnconfirmed() obs.unconfirmed = obs.unconfirmed + 1 end

local function Pair(now)
	Expire(pendings, now, DropUnconfirmed)
	Expire(meterHits, now)
	while pendings[1] and meterHits[1] do
		local p, h = pendings[1], meterHits[1]
		local gap = p.at - h.at
		if gap > 1 then
			table.remove(meterHits, 1)
		elseif gap < -1 then
			table.remove(pendings, 1)
			DropUnconfirmed()
		else
			table.remove(pendings, 1)
			table.remove(meterHits, 1)
			obs.confirmed = obs.confirmed + 1
			local owner = p.owner
			if not owner and h.owner then
				owner = h.owner
				obs.named = obs.named + 1
			end
			Charge(p.at, owner, p.mark, h.cands, p.icon)
		end
	end
end

local function OnEnemyInterrupted(unit, spellID, interruptedBy)
	if type(unit) ~= "string" or IsSecret(unit) or CAST_OWNER[unit] then return end
	-- the event fires for every token a unit is seen through, friends
	-- included; only a unit we can attack can have been kicked
	if Ask(UnitCanAttack, "player", unit) == false then return end
	obs.total = obs.total + 1
	local db = M.db
	if not db.observe or M:IsPreview() then return end
	local now = GetTime()
	local owner
	if not IsSecret(interruptedBy) and interruptedBy ~= nil then
		obs.readable = obs.readable + 1
		owner = OwnerOfGUID(interruptedBy)
		if not owner then return end
	else
		obs.secret = obs.secret + 1
	end
	-- the same interrupt, seen through another token: same frame
	if now - lastEventAt < 0.02 then return end
	if owner and now - lastObservedAt < 0.5 and lastObservedUnit == owner then return end
	lastEventAt = now
	local mark
	if db.showMark and GetRaidTargetIndex then
		local ok, idx = pcall(GetRaidTargetIndex, unit)
		if ok then mark = idx end
	end
	local icon
	if db.showIcon or db.displayMode == "icon" then
		local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
		if ok then icon = tex end
	end
	if db.meterConfirm then
		pendings[#pendings + 1] = { at = now, owner = owner, mark = mark, icon = icon }
		Pair(now)
	else
		Charge(now, owner, mark, nil, icon)
	end
end

local lastMeterAt = -10
local METER_INTERRUPTS = Enum and Enum.DamageMeterType and Enum.DamageMeterType.Interrupts

local function OnMeterUpdate(dmType)
	if not METER_INTERRUPTS or IsSecret(dmType) or dmType ~= METER_INTERRUPTS then return end
	local now = GetTime()
	if now - lastMeterAt < 0.05 then return end
	lastMeterAt = now
	obs.meter = obs.meter + 1
	local owner, cands = MeterKicker()
	meterHits[#meterHits + 1] = { at = now, owner = owner, cands = cands }
	Pair(now)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
-- One frame per member and their pet (RegisterUnitEvent takes two units).
local castFrames = {}
local function CastFrames(on)
	if on and #castFrames == 0 then
		for unit, pet in pairs(PET_OF) do
			local f = CreateFrame("Frame")
			f.units = { unit, pet }
			f:SetScript("OnEvent", function(_, _, u, _, spellID) OnCast(u, spellID) end)
			castFrames[#castFrames + 1] = f
		end
	end
	for _, f in ipairs(castFrames) do
		if on then
			f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", f.units[1], f.units[2])
		else
			f:UnregisterAllEvents()
		end
	end
end

local QueueSelf = XUI.Coalesce(function() if M.running then RefreshSelf() end end)

function M:OnEnable()
	Holder()
	CastFrames(true)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", ScheduleRebuild)
	self:RegisterEvent("GROUP_ROSTER_UPDATE", ScheduleRebuild)
	self:RegisterEvent("SPELLS_CHANGED", ScheduleRebuild)
	self:RegisterEvent("UNIT_NAME_UPDATE", function(_, _, unit)
		if members[unit] then ScheduleRebuild() end
	end)
	self:RegisterUnitEvent("UNIT_PET", "player", ScheduleRebuild)
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, _, unit)
		if type(unit) == "string" and not IsSecret(unit) and unit ~= "player" then
			local m = members[unit]
			if m and m.guid then specByGUID[m.guid] = nil end
		end
		ScheduleRebuild()
	end)
	self:RegisterEvent("INSPECT_READY", function(_, _, guid) OnInspectReady(guid) end)
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", QueueSelf)
	self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED", function(_, _, unit, _, spellID, interruptedBy)
		OnEnemyInterrupted(unit, spellID, interruptedBy)
	end)
	self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP", function(_, _, unit, _, spellID, interruptedBy)
		if IsSecret(interruptedBy) or interruptedBy ~= nil then OnEnemyInterrupted(unit, spellID, interruptedBy) end
	end)
	self:RegisterEvent("DAMAGE_METER_RESET", function() wipe(meterSnap) end)
	if self.db.meterConfirm then
		wipe(meterSnap)
		self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", function(_, _, dmType) OnMeterUpdate(dmType) end)
	end
	-- EllesmereUI rebuilds its party unit map on roster changes; icons follow
	local RF = XUI.EUI and XUI.EUI.Module("EllesmereUIRaidFrames")
	if RF and type(RF._RebuildPartyUnitMap) == "function" then
		self:SecureHook(RF, "_RebuildPartyUnitMap", function() ScheduleRebuild() end)
	end
end

function M:OnDisable()
	CastFrames(false)
	StopInspects()
	inspectTicker = nil
	rebuildPending = false
	wipe(pendings)
	wipe(meterHits)
end

function M:OnSettingChanged(path)
	-- the meter event comes and goes with its switch
	if path == "meterConfirm" and self.running then
		if self.db.meterConfirm then
			wipe(meterSnap)
			self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", function(_, _, dmType) OnMeterUpdate(dmType) end)
		else
			self:UnregisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
		end
	end
	self:RefreshSoon()
end

function M:OnRefresh()
	if not (holder or self:IsPreview()) then return end
	local h = Holder()
	XUI.Movers:Apply(h)
	if self:IsPreview() then
		if not h.__previewing then
			h.__previewing = true
			BuildPreview()
		else
			for _, row in ipairs(shown) do
				row:Show() -- a sample row hidden for lack of a party frame comes back
				StyleRow(row)
			end
			ShowRows()
		end
		return
	end
	if h.__previewing then
		h.__previewing = nil
		ReleaseAll()
	end
	if not self.running then
		ReleaseAll()
		h:SetScript("OnUpdate", nil)
		h:Hide()
		return
	end
	for _, row in pairs(rows) do StyleRow(row) end
	Rebuild()
end

-- Diagnostics for the options page.
function M:PrintStatus()
	self:Print(format("%s, %s, secret restrictions %s", self.running and "running" or "off",
		IsInGroup() and (IsInRaid() and "in a raid" or "in a party") or "solo",
		tostring(C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions())))
	for _, unit in ipairs(UNITS) do
		local m = members[unit]
		if m then
			local row = rows[unit]
			local state = row and row.cdStart and format("%.1fs left", row.cdStart + row.cdDur - GetTime()) or "ready"
			print(format("  %s: %s %s spec=%s kick=%s %s", unit, tostring(m.name), m.class, tostring(m.spec),
				tostring(m.spell), m.spell and state or "no interrupt"))
		end
	end
	print(format("  interrupted casts %d (%d named the kicker, %d secret, %d unconfirmed); meter %d, confirmed %d: %d named, %d guessed, %d yours, %d unmatched",
		obs.total, obs.readable, obs.secret, obs.unconfirmed, obs.meter, obs.confirmed, obs.named, obs.guessed, obs.mine, obs.unmatched))
end
