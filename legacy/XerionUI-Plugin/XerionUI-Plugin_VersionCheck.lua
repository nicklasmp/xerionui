local addonName, ns = ...
local hooksecurefunc, C_Timer = ns.Probe('VersionCheck', hooksecurefunc, C_Timer)
local _G = _G

local LATEST_KIRAUI = '2.10'

local KIRAUI_ADDON  = 'KiraUI'
local NOTICE_DELAY  = 6

-- Plugin update notice over the addon channel (see the block above PluginNotice).
local PREFIX        = 'XerionUIPlugin'
local HELLO_DELAY   = 10
local REPLY_MIN     = 2
local REPLY_SPREAD  = 6

local C_AddOns = _G.C_AddOns
local C_Timer = C_Timer
local C_ChatInfo = _G.C_ChatInfo
local CreateFrame = CreateFrame
local IsInGroup, IsInRaid, IsInGuild = IsInGroup, IsInRaid, IsInGuild
local GetNumGroupMembers = GetNumGroupMembers
local format, tonumber, tostring, type, pcall = format, tonumber, tostring, type, pcall
local random = math.random

local LE_HOME     = _G.LE_PARTY_CATEGORY_HOME or 1
local LE_INSTANCE = _G.LE_PARTY_CATEGORY_INSTANCE or 2
local CHAT_RESTRICTION     = (_G.Enum and _G.Enum.AddOnRestrictionType and _G.Enum.AddOnRestrictionType.Chat) or 5
local RESTRICTION_INACTIVE = (_G.Enum and _G.Enum.AddOnRestrictionState and _G.Enum.AddOnRestrictionState.Inactive) or 0

local Msg = ns.Msg
local secret = ns.IsSecret

local function ToParts(v)
	local t = {}
	for n in tostring(v):gmatch('%d+') do t[#t + 1] = tonumber(n) end
	return t
end

local function IsNewer(a, b)
	local pa, pb = ToParts(a), ToParts(b)
	local n = #pa > #pb and #pa or #pb
	for i = 1, n do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x > y end
	end
	return false
end

local MY_VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, 'Version')
if type(MY_VERSION) ~= 'string' or not MY_VERSION:match('^%d') then MY_VERSION = nil end

local function InstalledVersion()
	if not (C_AddOns and C_AddOns.GetAddOnInfo) then return nil end
	local name = C_AddOns.GetAddOnInfo(KIRAUI_ADDON)
	if not name then return nil end
	local v = C_AddOns.GetAddOnMetadata(KIRAUI_ADDON, 'Version')
	if type(v) ~= 'string' or v == '' then return nil end
	return v
end

function ns.XerionUIVersionInfo()
	local installed = InstalledVersion()
	return installed, LATEST_KIRAUI, (installed ~= nil) and IsNewer(LATEST_KIRAUI, installed) or false
end

local function NoticeSuppressed()
	local db = _G.XerionUIChangesDB
	return db and db.hideVersionNotice == true
end

function ns.SetVersionNotice(enabled)
	local db = _G.XerionUIChangesDB
	if not db then return end
	db.hideVersionNotice = not enabled
	Msg('out-of-date notice: ' .. (enabled and 'ON' or 'OFF'))
end

-- PLUGIN UPDATE NOTICE
-- The installer notice below works because every plugin build carries the installer's
-- latest number. Nothing carries the PLUGIN's own latest number to a player who has not
-- updated, and an addon cannot reach the internet to ask CurseForge. The only channel left
-- is other players: every copy says its version over the hidden addon channel (guild, and
-- the group it is in), and a copy that hears a higher number than its own prints one line.
-- Big UI addons spread their update notices the same way. It therefore only reaches people
-- who share a guild or a group with someone who already updated - in the first hours after
-- a release, few will see it.
--
-- WHAT IT SENDS: 'V:<version>' under PREFIX, 10 s after the first loading screen (guild and
-- group) and 10 s after the group grows (group only). A copy that hears an OLDER version
-- answers on the same channel after a random 2-8 s, and drops that answer when anyone says
-- our version or a newer one there first - so one outdated login in a big guild draws one or
-- two answers, not one per member.
--
-- CHAT LOCKDOWN: in a running key, a boss encounter or a rated match the client refuses addon
-- messages (SendAddonMessage answers AddOnMessageLockdown). We do not send then; a hello that
-- falls in lockdown waits for ADDON_RESTRICTION_STATE_CHANGED to report the Chat restriction
-- inactive, the way LibSpecialization does it.
--
-- The highest version heard is kept in db.__pluginLatest (a metadata key: it survives profile
-- switches and is never exported), so a player who heard it once is reminded at every login
-- until they update, and the key clears itself once they have. '/xui version off'
-- silences this notice together with the installer one; this copy still answers others.

local sessionLatest
local pluginNotified = false

-- The newest version heard that is ahead of ours, or nil.
local function LatestHeard()
	if not MY_VERSION then return nil end
	local db = _G.XerionUIChangesDB
	local v = db and db.__pluginLatest
	if type(v) ~= 'string' then v = nil end
	if sessionLatest and (not v or IsNewer(sessionLatest, v)) then v = sessionLatest end
	if v and IsNewer(v, MY_VERSION) then return v end
	return nil
end

-- The settings window prints it left of its version number.
ns.PluginLatestHeard = LatestHeard

local function Remember(v)
	if not sessionLatest or IsNewer(v, sessionLatest) then sessionLatest = v end
	local db = _G.XerionUIChangesDB
	if db and (type(db.__pluginLatest) ~= 'string' or IsNewer(v, db.__pluginLatest)) then
		db.__pluginLatest = v
	end
end

-- A number more than one major version ahead of ours is a typo or a prank, not a release,
-- and it would nag at every login until the plugin caught up with it.
local function Plausible(v)
	if #v > 12 then return false end
	local theirs, ours = ToParts(v)[1], ToParts(MY_VERSION)[1]
	return theirs ~= nil and ours ~= nil and theirs <= ours + 1
end

local function PluginNotice()
	local db = _G.XerionUIChangesDB
	if db and db.__pluginLatest ~= nil and MY_VERSION
		and (type(db.__pluginLatest) ~= 'string' or not IsNewer(db.__pluginLatest, MY_VERSION)) then
		db.__pluginLatest = nil
	end
	if pluginNotified or NoticeSuppressed() then return end
	local latest = LatestHeard()
	if not latest then return end
	pluginNotified = true
	Msg(format('|cffffffffXerionUI-Plugin|r |cff7fff7f%s|r is out on CurseForge - you have |cffff7f7f%s|r.',
		latest, MY_VERSION))
end

function ns.PrintVersionInfo()
	local installed, latest, outdated = ns.XerionUIVersionInfo()
	local heard = LatestHeard()
	if heard then
		Msg(format('Plugin |cffff7f7f%s|r - out of date, |cff7fff7f%s|r is on CurseForge', MY_VERSION, heard))
	else
		Msg(format('Plugin |cff7fff7f%s|r', MY_VERSION or '?'))
	end
	if not installed then
		Msg('KiraUI Installer: |cffaaaaaanot installed|r (latest is ' .. latest .. ')')
	elseif outdated then
		Msg(format('KiraUI Installer: |cffff7f7f%s|r - out of date, latest is |cff7fff7f%s|r', installed, latest))
	else
		Msg(format('KiraUI Installer: |cff7fff7f%s|r - up to date', installed))
	end
end

local comm = CreateFrame('Frame')

local function ChatLocked()
	return C_ChatInfo.InChatMessagingLockdown ~= nil and C_ChatInfo.InChatMessagingLockdown() == true
end

local function Send(channel)
	if not channel or ChatLocked() then return end
	pcall(C_ChatInfo.SendAddonMessage, PREFIX, 'V:' .. MY_VERSION, channel)
end

-- The home group first: a premade that queued into LFR is in both, and RAID reaches the
-- people the player actually plays with.
local function GroupChannel()
	if IsInRaid(LE_HOME) then return 'RAID' end
	if IsInGroup(LE_HOME) then return 'PARTY' end
	if IsInGroup(LE_INSTANCE) then return 'INSTANCE_CHAT' end
	return nil
end

local helloTimer, helloGuild = nil, false

local function Hello()
	if ChatLocked() then
		comm:RegisterEvent('ADDON_RESTRICTION_STATE_CHANGED')
		return
	end
	if helloGuild and IsInGuild() then Send('GUILD') end
	helloGuild = false
	Send(GroupChannel())
end

-- One timer at a time: a group filling up fires GROUP_ROSTER_UPDATE once per member.
local function HelloSoon(withGuild)
	helloGuild = helloGuild or withGuild
	if helloTimer then return end
	helloTimer = C_Timer.NewTimer(HELLO_DELAY, function()
		helloTimer = nil
		Hello()
	end)
end

local replyTimers = {}

local function CancelReply(channel)
	local t = replyTimers[channel]
	if t then
		t:Cancel()
		replyTimers[channel] = nil
	end
end

local function ReplySoon(channel)
	if replyTimers[channel] then return end
	replyTimers[channel] = C_Timer.NewTimer(REPLY_MIN + random() * REPLY_SPREAD, function()
		replyTimers[channel] = nil
		Send(channel)
	end)
end

local REPLY_CHANNEL = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- Our own messages come back to us too; they carry our version, so they land in the last
-- branch and need no sender check.
local function OnAddonMessage(prefix, text, channel)
	if secret(prefix) or prefix ~= PREFIX or secret(text) or secret(channel) then return end
	local v = type(text) == 'string' and text:match('^V:(%d[%d%.]*)$')
	if not v then return end
	if IsNewer(v, MY_VERSION) then
		if not Plausible(v) then return end
		Remember(v)
		CancelReply(channel)
		PluginNotice()
		-- Set by the settings window once it is built; nil until then.
		if ns.OnPluginLatest then ns.OnPluginLatest() end
	elseif IsNewer(MY_VERSION, v) then
		if REPLY_CHANNEL[channel] then ReplySoon(channel) end
	else
		CancelReply(channel)
	end
end

local groupSize = 0

comm:SetScript('OnEvent', function(self, event, a1, a2, a3)
	if event == 'CHAT_MSG_ADDON' then
		OnAddonMessage(a1, a2, a3)
	elseif event == 'GROUP_ROSTER_UPDATE' then
		local n = GetNumGroupMembers()
		if n > 1 and n > groupSize then HelloSoon(false) end
		groupSize = n
	elseif event == 'PLAYER_ENTERING_WORLD' then
		self:UnregisterEvent(event)
		groupSize = GetNumGroupMembers()
		HelloSoon(true)
	elseif event == 'ADDON_RESTRICTION_STATE_CHANGED' then
		if a1 == CHAT_RESTRICTION and a2 == RESTRICTION_INACTIVE then
			self:UnregisterEvent(event)
			-- helloGuild is still set from the refused try. The delay gives the rest of the
			-- group time to leave lockdown too, or they would not hear us.
			HelloSoon(false)
		end
	end
end)

if MY_VERSION and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage
	and C_Timer and C_Timer.NewTimer then
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	comm:RegisterEvent('CHAT_MSG_ADDON')
	comm:RegisterEvent('GROUP_ROSTER_UPDATE')
	comm:RegisterEvent('PLAYER_ENTERING_WORLD')
end

local announced = false

local function Announce()
	if announced or NoticeSuppressed() then return end
	local installed, latest, outdated = ns.XerionUIVersionInfo()
	if not outdated then return end
	announced = true

	Msg(format('Your |cffffffffKiraUI Installer|r is out of date - you have |cffff7f7f%s|r, latest is |cff7fff7f%s|r.',
		installed, latest))
	Msg('Please update the KiraUI Installer and check the changes on the website or Discord.')
end

local function LoginNotices()
	Announce()
	PluginNotice()
end

local watcher = CreateFrame('Frame')
watcher:RegisterEvent('PLAYER_ENTERING_WORLD')
watcher:SetScript('OnEvent', function(self)
	self:UnregisterEvent('PLAYER_ENTERING_WORLD')
	if C_Timer and C_Timer.After then
		C_Timer.After(NOTICE_DELAY, LoginNotices)
	else
		LoginNotices()
	end
end)
