--------------------------------------------------------------------------------
-- Bone Shield (Blood)
-- Glows the Bone Shield icon in the Cooldown Manager when it is about to
-- drop or its stacks fall under 5, and plays a sound.
--
-- THE CLOCK
-- In a key the aura's expiration is hidden, so the module keeps its own: a
-- cast that refreshes Bone Shield restarts it at the configured duration, and
-- the real expiration takes over whenever it is readable. Spells that refresh
-- it beyond the built-in list are LEARNED: a cast followed by a jump in the
-- readable expiration marks the spell, and it carries into keys; a learned
-- spell that stops refreshing three times is dropped again.
--
-- THE STACKS
-- The stack count is hidden in keys too. Ossuary (219786) needs 5 stacks, so
-- an Ossuary icon on a Cooldown Manager buff bar answers "under 5" when it
-- goes out. Add Ossuary to a buff bar for the stack warning to work in keys.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local BONE_SHIELD, OSSUARY, OSSUARY_AT = 195181, 219786, 5
local REFRESH_IDS = { [195182] = true, [195292] = true, [108199] = true, [49028] = true, [439843] = true, [49576] = true }
local LEARN_JUMP, UNLEARN_AFTER, RE_OBSERVE = 1.0, 3, 30

local M = XUI:NewModule("BoneShield", {
	name = "Bone Shield",
	desc = "Glows Bone Shield in the Cooldown Manager when it is about to drop or under 5 stacks.",
	category = "class",
	icon = [[Interface\Icons\Ability_DeathKnight_BoneShield]],
	order = 10,
	classes = { "DEATHKNIGHT" },
	specs = { 250 },
	defaults = {
		glow = T.Glow(true, { useGlobal = false, type = "PULSE", color = { 1, 0.16, 0.16, 1 } }),
		glowThreshold = 8,
		stackWarn = true,
		alert = T.Alert("SOUND", { sound = "Xerion: External" }),
		soundThreshold = 5,
		soundInCombatOnly = true,
		duration = 30,
		learnedRefresh = {},
		customArt = false,
	},
})

local IsSecret = XUI.IsSecret
local GPA = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID

--------------------------------------------------------------------------------
-- The icons
--------------------------------------------------------------------------------
local targets, ossuaryFrames = {}, {}
local sawCdmFrame = false
local lastScan = 0
local overlays = setmetatable({}, { __mode = "k" })
local ossIdentID = setmetatable({}, { __mode = "k" })
local ossIdentIs = setmetatable({}, { __mode = "k" })
local ossuaryProven = setmetatable({}, { __mode = "k" })

local function FrameIsOssuary(f)
	if not f then return false end
	if f.GetCooldownID then
		local ok, id = pcall(f.GetCooldownID, f)
		if ok and not IsSecret(id) and id then
			-- the answer only changes when the frame is handed another cooldown
			local match
			if ossIdentID[f] == id then
				match = ossIdentIs[f]
			else
				match = XUI.CooldownMatches(id, OSSUARY)
				ossIdentID[f], ossIdentIs[f] = id, match
			end
			if match then return true end
		end
	end
	if f.GetSpellID then
		local ok, sid = pcall(f.GetSpellID, f)
		if ok and sid and not IsSecret(sid) and sid == OSSUARY then return true end
	end
	return false
end

local function AddUnique(list, f)
	for i = 1, #list do if list[i] == f then return end end
	list[#list + 1] = f
end

local function ScanOssuary()
	for _, name in ipairs(XUI.CDM_BUFF_VIEWERS) do
		local viewer = _G[name]
		if viewer and viewer.GetChildren then
			for _, f in ipairs({ viewer:GetChildren() }) do
				if FrameIsOssuary(f) then AddUnique(ossuaryFrames, f) end
			end
		end
	end
end

local function StopGlowOn(ov)
	if not ov then return end
	Style:HideGlow(ov)
	ov:Hide()
end

local function Rescan()
	wipe(ossIdentID)
	wipe(ossIdentIs)
	ScanOssuary()
	targets = XUI.FindCDMFrames(BONE_SHIELD)
	lastScan = GetTime()
	if #targets > 0 then sawCdmFrame = true end
	-- a pooled frame handed another buff loses its glow
	for f, ov in pairs(overlays) do
		local keep = f == M.previewFrame
		for i = 1, #targets do if targets[i] == f then keep = true break end end
		if not keep then StopGlowOn(ov) end
	end
	return targets
end

local function OssuaryUp()
	local known, up = false, false
	for i = #ossuaryFrames, 1, -1 do
		local f = ossuaryFrames[i]
		if not FrameIsOssuary(f) then
			table.remove(ossuaryFrames, i)
			ossuaryProven[f] = nil
		else
			local flag = f.IsActive and XUI.Probe(f.IsActive, f)
			if type(flag) == "boolean" then
				known = true
				if flag then up = true ossuaryProven[f] = true end
			elseif XUI.FrameActive(f) then
				ossuaryProven[f] = true
				known, up = true, true
			elseif ossuaryProven[f] then
				known = true
			end
		end
	end
	if not known then return nil end
	return up
end

-- true / false, or nil when nothing can tell
local function StacksLow()
	if not M.db.stackWarn then return false end
	local o = OssuaryUp()
	if GPA then
		local ok, aura = pcall(GPA, BONE_SHIELD)
		if ok and aura then
			local n = aura.applications
			if not IsSecret(n) and type(n) == "number" then return n < OSSUARY_AT end
		end
	end
	if o ~= nil then return not o end
	return nil
end

local function Overlay(f)
	local ov = overlays[f]
	if not ov or ov:GetParent() ~= f then
		ov = CreateFrame("Frame", nil, f)
		ov:EnableMouse(false)
		overlays[f] = ov
	end
	ov:SetAllPoints(f)
	local lvl = XUI.Probe(f.GetFrameLevel, f)
	if type(lvl) == "number" then ov:SetFrameLevel(lvl) end
	ov:Show()
	return ov
end

local glowing = false
local function SetGlow(on)
	if on then
		if #targets == 0 and GetTime() - lastScan > 1 then Rescan() end
		local any = false
		for _, f in ipairs(targets) do
			if XUI.FrameActive(f) then
				Style:ShowGlow(Overlay(f), M.db.glow, true)
				any = true
			elseif overlays[f] then
				StopGlowOn(overlays[f])
			end
		end
		glowing = any
	else
		for f, ov in pairs(overlays) do
			if f ~= M.previewFrame then StopGlowOn(ov) end
		end
		glowing = false
	end
end

--------------------------------------------------------------------------------
-- The clock
--------------------------------------------------------------------------------
local expire, soundArmed, lowRang, downSince = 0, false, nil, 0
local ticker

local function ReadRealExpire()
	if not GPA then return nil end
	local ok, aura = pcall(GPA, BONE_SHIELD)
	if not ok or not aura then return nil end
	local exp = aura.expirationTime
	if IsSecret(exp) or type(exp) ~= "number" or exp <= 0 then return nil end
	return exp
end

local function TrySync()
	local exp = ReadRealExpire()
	if not exp then return false, false end
	local moved = math.abs(exp - expire) > 0.15
	expire = exp
	return true, moved
end

local Tick, SyncTicker

Tick = function()
	if M:IsPreview() or not M.running then return end
	local db = M.db
	local rem = expire - GetTime()
	local up
	if sawCdmFrame then
		up = false
		for _, f in ipairs(targets) do if XUI.FrameActive(f) then up = true break end end
	else
		up = rem > 0
	end
	if not up then
		SetGlow(false)
		if downSince == 0 then downSince = GetTime() end
		if GetTime() - downSince < 0.5 then return end
		expire, soundArmed, lowRang = 0, false, nil
		M:After(0, SyncTicker)
		return
	end
	downSince = 0
	if rem <= 0 then
		SetGlow(false)
		expire, soundArmed, lowRang = 0, false, nil
		M:After(0, SyncTicker)
		return
	end
	if rem > db.soundThreshold + 0.5 then soundArmed = true end
	local lowNow = StacksLow()
	SetGlow(db.glow.enabled ~= false and (lowNow == true or rem <= db.glowThreshold))

	local mayRing = not db.soundInCombatOnly or InCombatLockdown() or XUI.Ask(UnitAffectingCombat, "player")
	local rang = false
	if lowNow == false then
		lowRang = false
	elseif lowNow == true and lowRang == false and mayRing then
		lowRang, rang = true, true
		XUI.Audio:Play(db.alert, "Bone Shield")
	end
	if soundArmed and rem <= db.soundThreshold and mayRing then
		soundArmed = false
		if not rang then XUI.Audio:Play(db.alert, "Bone Shield") end
	end
end

-- 10 times a second, only while a Bone Shield window runs
SyncTicker = function()
	local want = M.running and not M:IsPreview() and expire > 0
	if want and not ticker then
		ticker = M:NewTicker(0.1, Tick)
	elseif not want and ticker then
		M:CancelTicker(ticker)
		ticker = nil
		if not M:IsPreview() then SetGlow(false) end
	end
end

local function Restart()
	expire = GetTime() + M.db.duration
	soundArmed, downSince = true, 0
	M:After(0, function() if TrySync() then SyncTicker() end end)
	SyncTicker()
end

--------------------------------------------------------------------------------
-- Learning which casts refresh it
--------------------------------------------------------------------------------
local misses, lastObserved = {}, {}

local function IsRefresher(id)
	return REFRESH_IDS[id] or M.db.learnedRefresh[id] == true
end

local function ObserveCast(spellID)
	if not GPA or REFRESH_IDS[spellID] then return end
	local learned = M.db.learnedRefresh
	local now = GetTime()
	if learned[spellID] and now - (lastObserved[spellID] or 0) < RE_OBSERVE then return end
	lastObserved[spellID] = now
	local before = ReadRealExpire()
	M:After(0, function()
		local after = ReadRealExpire()
		if after == nil or before == nil then return end
		if after - before > LEARN_JUMP then
			learned[spellID] = true
			misses[spellID] = nil
			expire, soundArmed, downSince = after, true, 0
			SyncTicker()
			Tick()
			return
		end
		if learned[spellID] then
			local n = (misses[spellID] or 0) + 1
			if n >= UNLEARN_AFTER then
				learned[spellID], misses[spellID] = nil, nil
			else
				misses[spellID] = n
			end
		end
	end)
end

function M:ForgetLearned()
	wipe(self.db.learnedRefresh)
	wipe(misses)
	wipe(lastObserved)
	self:Print("forgot the learned refresh spells.")
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------
local hooked = {}
local QueueRescan = XUI.Coalesce(function()
	if not M.running then return end
	Rescan()
	if glowing then SetGlow(true) end
	M:ScanArt()
end)

-- the Cooldown Manager refreshes its viewers on full aura updates; the icon
-- can move to another pooled frame then
local function HookViewers()
	for _, name in ipairs(XUI.CDM_BUFF_VIEWERS) do
		local v = _G[name]
		if v and v.RefreshData and not hooked[v] then
			hooked[v] = true
			M:SecureHook(v, "RefreshData", QueueRescan)
		end
	end
	if type(_G._ECME_Apply) == "function" and not hooked.ecme then
		hooked.ecme = true
		M:SecureHook("_ECME_Apply", QueueRescan)
	end
end

function M:OnEnable()
	HookViewers()
	Rescan()
	TrySync()
	SyncTicker()
	self:NewTicker(5, function()
		HookViewers()
		Rescan()
		self:ScanArt()
	end)
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, _, spellID)
		if IsSecret(spellID) or self:IsPreview() then return end
		if IsRefresher(spellID) then Restart() end
		ObserveCast(spellID)
	end)
	self:RegisterUnitEvent("UNIT_AURA", "player", function()
		if expire > 0 then
			local _, moved = TrySync()
			if moved then Tick() end
		elseif TrySync() then
			soundArmed = true
			SyncTicker()
		end
	end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() Tick() end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() Tick() end)
	self:RegisterEvent("TRAIT_CONFIG_UPDATED", function()
		wipe(ossIdentID)
		wipe(ossIdentIs)
	end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self)
		self:After(3, function() HookViewers() Rescan() end)
	end)
end

function M:OnDisable()
	ticker = nil
	expire, soundArmed, lowRang = 0, false, nil
	SetGlow(false)
end

function M:OnRefresh()
	-- glow settings changed: start the glows afresh
	for f, ov in pairs(overlays) do
		if f ~= self.previewFrame then StopGlowOn(ov) end
	end
	glowing = false
	if self:IsPreview() then
		local f = self.previewFrame
		if not f then
			f = XUI.Widgets:CreateIcon("XUI_BoneShieldPreview")
			f:SetIcon(XUI.GetSpellIcon(BONE_SHIELD))
			f:SetFrameStrata("HIGH")
			f:SetPoint("CENTER")
			self.previewFrame = f
		end
		f:ApplyLayout({ width = 48, height = 48 }, nil)
		f:Show()
		Style:ShowGlow(Overlay(f), self.db.glow, true)
		return
	end
	if self.previewFrame then
		StopGlowOn(overlays[self.previewFrame])
		self.previewFrame:Hide()
	end
	if self.running then
		Rescan()
		Tick()
	end
end

function M:PrintStatus()
	Rescan()
	local rem = expire > 0 and (expire - GetTime()) or nil
	self:Print(("Cooldown Manager icons: %d | Ossuary icons: %d | clock: %s | real expiration readable: %s"):format(
		#targets, #ossuaryFrames, rem and ("%.1fs"):format(rem) or "not running", ReadRealExpire() and "yes" or "no"))
	local low = StacksLow()
	print("  stacks under 5:", low == nil and "unknown (add Ossuary to a Cooldown Manager buff bar)" or tostring(low))
	local learned = {}
	for id in pairs(self.db.learnedRefresh) do learned[#learned + 1] = id end
	table.sort(learned)
	print("  learned refresh spells:", #learned > 0 and table.concat(learned, ", ") or "none")
	if #targets == 0 then print("  Bone Shield is not on a Cooldown Manager buff bar, so there is nothing to glow; the sound still works.") end
end

--------------------------------------------------------------------------------
-- Custom icon art: paints our own Bone Shield picture over the Cooldown
-- Manager's icon. The viewer rewrites the art on every refresh, so its
-- RefreshSpellTexture is hooked per frame (answers remembered per frame and
-- cooldownID), plus a pass after each whole-viewer refresh.
--------------------------------------------------------------------------------
local ART = XUI.MEDIA_PATH .. "boneshield-face.png"
local artHooked = setmetatable({}, { __mode = "k" })
local painted = setmetatable({}, { __mode = "k" })
local artID = setmetatable({}, { __mode = "k" })
local artIs = setmetatable({}, { __mode = "k" })

local function ArtOn() return M.running and M.db.customArt end

local function IsBoneShieldFrame(f)
	local id = f.GetCooldownID and XUI.Probe(f.GetCooldownID, f)
	if type(id) == "number" then
		if artID[f] == id then return artIs[f] end
		local is = XUI.CooldownMatches(id, BONE_SHIELD)
		artID[f], artIs[f] = id, is
		return is
	end
	local sid = f.GetSpellID and XUI.Probe(f.GetSpellID, f)
	return sid == BONE_SHIELD
end

local function IconTexture(f)
	local ok, tex = pcall(f.GetIconTexture, f)
	if ok and tex and tex.SetTexture then return tex end
end

local function PaintArt(f)
	local tex = IconTexture(f)
	if tex then
		pcall(tex.SetTexture, tex, ART)
		painted[f] = true
	end
end

local function Unpaint(f)
	painted[f] = nil
	if f.RefreshSpellTexture then pcall(f.RefreshSpellTexture, f) end
end

local function OnRefreshTexture(f)
	if ArtOn() and IsBoneShieldFrame(f) then PaintArt(f) else painted[f] = nil end
end

function M:ScanArt()
	local on = ArtOn()
	for _, name in ipairs(XUI.CDM_BUFF_VIEWERS) do
		local viewer = _G[name]
		if viewer and viewer.GetChildren then
			for _, f in ipairs({ viewer:GetChildren() }) do
				if f and f.GetIconTexture then
					if on then
						if not artHooked[f] and f.RefreshSpellTexture then
							artHooked[f] = true
							hooksecurefunc(f, "RefreshSpellTexture", OnRefreshTexture)
						end
						if IsBoneShieldFrame(f) then PaintArt(f) elseif painted[f] then Unpaint(f) end
					elseif painted[f] then
						Unpaint(f)
					end
				end
			end
		end
	end
end

local baseRefresh = M.OnRefresh
function M:OnRefresh()
	baseRefresh(self)
	wipe(artID)
	wipe(artIs)
	self:ScanArt()
end
