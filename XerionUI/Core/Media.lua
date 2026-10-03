--------------------------------------------------------------------------------
-- XerionUI - Core/Media.lua
-- One door to LibSharedMedia: registration of our own media, cached path
-- lookups with sane fallbacks, and sorted name lists for the options panel.
--------------------------------------------------------------------------------
local XUI = select(2, ...).XUI

local LSM = LibStub("LibSharedMedia-3.0")
local Media = { LSM = LSM }
XUI.Media = Media

local WHITE = [[Interface\Buttons\WHITE8X8]]

LSM:Register("statusbar", "Xerion Flat", WHITE)
LSM:Register("background", "Xerion Solid", WHITE)
LSM:Register("border", "Xerion Pixel", WHITE)
LSM:Register("sound", "Xerion: Stun", XUI.MEDIA_PATH .. [[Sounds\stun.mp3]])
LSM:Register("sound", "Xerion: External", XUI.MEDIA_PATH .. [[Sounds\external.ogg]])

local FALLBACK = {
	font = "Arial Narrow",
	statusbar = "Xerion Flat",
	background = "Xerion Solid",
	border = "Xerion Pixel",
}

local FALLBACK_PATH = {
	font = [[Fonts\ARIALN.TTF]],
	statusbar = WHITE,
	background = WHITE,
	border = WHITE,
}

-- [kind][name] = path. Cleared whenever LibSharedMedia registers something,
-- because a name that missed before (an addon registering late) may now hit.
local cache = { font = {}, statusbar = {}, background = {}, border = {}, sound = {} }

function Media:Fetch(kind, name)
	local bucket = cache[kind]
	local hit = bucket and name and bucket[name]
	if hit then return hit end
	local path = name and LSM:Fetch(kind, name, true)
	if not path then
		if kind == "sound" then return nil end
		path = LSM:Fetch(kind, FALLBACK[kind], true) or FALLBACK_PATH[kind]
	end
	if bucket and name then bucket[name] = path end
	return path
end

-- True when `name` is registered for `kind` (false when Fetch would fall back).
function Media:Has(kind, name)
	return name ~= nil and LSM:Fetch(kind, name, true) ~= nil
end

-- Sorted list of registered names for a media kind.
function Media:List(kind)
	local out = {}
	for _, name in ipairs(LSM:List(kind)) do out[#out + 1] = name end
	table.sort(out, function(a, b) return a:lower() < b:lower() end)
	return out
end

local announce = XUI.Coalesce(function() XUI:Fire("MediaChanged") end)

local function Invalidate()
	for _, bucket in pairs(cache) do wipe(bucket) end
	announce()
end

LSM.RegisterCallback(Media, "LibSharedMedia_Registered", Invalidate)
LSM.RegisterCallback(Media, "LibSharedMedia_SetGlobal", Invalidate)
