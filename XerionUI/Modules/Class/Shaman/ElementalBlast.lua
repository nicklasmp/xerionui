--------------------------------------------------------------------------------
-- Elemental Blast letters (Shaman)
-- Elemental Blast leaves one of three buffs - Critical Strike, Haste or
-- Mastery - and the Cooldown Manager tracks each as a buff of its own. This
-- puts a letter above each icon: C, H or M, with its own colour.
--
-- It adds no icons: the letter hangs off the Cooldown Manager's own icon frame
-- (BuffIconCooldownViewer), so it follows the icon wherever it is put and
-- shows and hides with it. The viewer hands its pooled frames a cooldownID in
-- RefreshData, so a hook there is the whole resync road. The match is made on
-- the cooldown info (plain layout data), never on the aura (secret in combat);
-- a cooldown that stands for two of the buffs gets no letter rather than a
-- wrong one. Pooled frames are used, not GetItemFrames(), which lists shown
-- frames only: a buff that is down is a hidden frame.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI
local T = XUI.Templates
local Style = XUI.Style

local VIEWER = "BuffIconCooldownViewer"
local LETTERS = {
	{ id = 118522, text = "C", color = "critColor" },
	{ id = 173183, text = "H", color = "hasteColor" },
	{ id = 173184, text = "M", color = "masteryColor" },
}

local M = XUI:NewModule("ElementalBlast", {
	name = "Elemental Blast Letters",
	desc = "A C, H or M above the Elemental Blast buff icons in the Cooldown Manager.",
	category = "class",
	icon = [[Interface\Icons\Spell_Nature_Lightning]],
	order = 30,
	classes = { "SHAMAN" },
	untested = true,
	defaults = {
		font = T.Font(14),
		offsetY = 2,
		critColor = { 1, 1, 1, 1 },
		hasteColor = { 1, 1, 1, 1 },
		masteryColor = { 1, 1, 1, 1 },
		position = T.Position(0, -150),
	},
})

local IsSecret = XUI.IsSecret
local GetInfo = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo

function M:CanLoad()
	if not GetInfo then return false, "Needs the Cooldown Manager." end
	return true
end

local function Plain(v, want) return not IsSecret(v) and v == want end

-- which letter a cooldownID stands for: its own spell first, then its linked
-- spells; nil, "ambiguous" when it stands for several
local function Identify(cdID)
	if IsSecret(cdID) or cdID == nil then return nil end
	local ok, info = pcall(GetInfo, cdID)
	if not ok or type(info) ~= "table" then return nil end
	for i = 1, #LETTERS do
		local id = LETTERS[i].id
		if Plain(info.spellID, id) or Plain(info.overrideSpellID, id) or Plain(info.overrideTooltipSpellID, id) then
			return LETTERS[i]
		end
	end
	local found
	local linked = info.linkedSpellIDs
	if type(linked) == "table" then
		for j = 1, #linked do
			for i = 1, #LETTERS do
				if Plain(linked[j], LETTERS[i].id) then
					if found and found ~= LETTERS[i] then return nil, "ambiguous" end
					found = LETTERS[i]
				end
			end
		end
	end
	return found
end

local function FrameLetter(f)
	if not f.GetCooldownID then return nil end
	local ok, id = pcall(f.GetCooldownID, f)
	if not ok then return nil end
	return Identify(id)
end

-- one label per pooled frame, made the first time it carries one of the buffs
local recs = {}

local function Look(fs, anchor, L)
	local db = M.db
	Style:ApplyFont(fs, db.font)
	fs:SetTextColor(XUI.UnpackColor(db[L.color]))
	fs:ClearAllPoints()
	fs:SetPoint("BOTTOM", anchor, "TOP", 0, db.offsetY)
	fs:SetText(L.text)
end

local function Paint(f, L)
	local rec = recs[f]
	if not rec then
		local holder = CreateFrame("Frame", nil, f)
		holder:SetAllPoints(f)
		rec = { holder = holder, fs = holder:CreateFontString(nil, "OVERLAY") }
		recs[f] = rec
	end
	local ok, lvl = pcall(f.GetFrameLevel, f)
	if ok and not IsSecret(lvl) and lvl then rec.holder:SetFrameLevel(lvl + 30) end
	Look(rec.fs, rec.holder, L)
	rec.holder:Show()
	rec.want = true
end

local function Sync()
	for _, rec in pairs(recs) do rec.want = nil end
	if M.running then
		local viewer = _G[VIEWER]
		local pool = viewer and viewer.itemFramePool
		if pool and pool.EnumerateActive then
			for f in pool:EnumerateActive() do
				local L = FrameLetter(f)
				if L then Paint(f, L) end
			end
		elseif viewer and viewer.GetItemFrames then
			local ok, frames = pcall(viewer.GetItemFrames, viewer)
			if ok and type(frames) == "table" then
				for i = 1, #frames do
					local L = FrameLetter(frames[i])
					if L then Paint(frames[i], L) end
				end
			end
		end
	end
	for _, rec in pairs(recs) do
		if not rec.want then rec.holder:Hide() end
	end
end

-- The preview: three Elemental Blast icons of our own, one per buff, so the
-- look can be tuned without casting.
local preview
local function Preview()
	if preview then return preview end
	preview = CreateFrame("Frame", "XUI_ElementalBlastPreview", UIParent)
	preview:SetSize(3 * 36 + 2 * 2, 36)
	preview:Hide()
	preview.icons = {}
	for i, L in ipairs(LETTERS) do
		local b = CreateFrame("Frame", nil, preview)
		b:SetSize(36, 36)
		b:SetPoint("LEFT", preview, "LEFT", (i - 1) * 38, 0)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.tex:SetTexture(XUI.GetSpellIcon(L.id, 136048))
		b.fs = b:CreateFontString(nil, "OVERLAY")
		preview.icons[i] = b
	end
	XUI.Movers:Register(preview, M, "position")
	return preview
end

function M:OnEnable()
	local function hook()
		local v = _G[VIEWER]
		if v and v.RefreshData then
			self:SecureHook(v, "RefreshData", Sync)
			return true
		end
	end
	-- the viewer may fill its frames before the hook existed, or late
	local function pass() hook() Sync() end
	pass()
	self:After(1, pass)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(self) self:After(1, pass) end)
	self:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player", function(self) self:After(1, pass) end)
end

function M:OnDisable() Sync() end

function M:OnRefresh()
	Sync()
	if not (preview or self:IsPreview()) then return end
	local p = Preview()
	XUI.Movers:Apply(p)
	for i, b in ipairs(p.icons) do Look(b.fs, b, LETTERS[i]) end
	p:SetShown(self:IsPreview())
end

function M:DebugInfo()
	local viewer = _G[VIEWER]
	local pool = viewer and viewer.itemFramePool
	local out = { ("viewer: %s, frame pool: %s"):format(tostring(viewer ~= nil), tostring(pool ~= nil)) }
	if pool and pool.EnumerateActive then
		for f in pool:EnumerateActive() do
			local ok, id = pcall(f.GetCooldownID, f)
			local L, why = Identify(ok and id or nil)
			out[#out + 1] = ("  cooldown %s -> %s"):format(IsSecret(id) and "<secret>" or tostring(id), L and L.text or (why or "-"))
		end
	end
	return out
end
