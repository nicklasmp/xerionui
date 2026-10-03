-- Loads an addon's files in TOC order, the way the client does: each file
-- gets (addonName, namespace) as its varargs.

local function Parse(addon)
	local toc = readfile(addon .. "/" .. addon .. ".toc")
	assert(toc, "no toc for " .. addon)
	local files = {}
	for line in toc:gmatch("[^\r\n]+") do
		line = line:gsub("%s*%[.-%]%s*$", "")
		if not line:match("^%s*#") and line:match("%S") then
			files[#files + 1] = (line:gsub("^%s+", ""):gsub("%s+$", ""))
		end
	end
	return files
end

local function LoadXML(addon, dir, file, ns)
	local xml = readfile(addon .. "/" .. dir .. file)
	assert(xml, "missing xml " .. dir .. file)
	local base = (dir .. file):match("^(.*[/\\])") or ""
	for tag, f in xml:gmatch("<(%a+)%s+file=\"([^\"]+)\"") do
		if tag == "Script" then
			MOCK.LoadLua(addon, base .. f, ns)
		elseif tag == "Include" then
			LoadXML(addon, base, f, ns)
		end
	end
end

function MOCK.LoadLua(addon, file, ns)
	local path = addon .. "/" .. file:gsub("\\", "/")
	local src = readfile(path)
	assert(src, "missing file " .. path)
	local chunk, err = load(src, "@" .. path)
	if not chunk then
		MOCK.errors[#MOCK.errors + 1] = "syntax: " .. err
		return
	end
	local ok, rerr = xpcall(chunk, debug.traceback, addon, ns)
	if not ok then MOCK.errors[#MOCK.errors + 1] = "load " .. path .. ": " .. tostring(rerr) end
end

function MOCK.LoadTOC(addon)
	local ns = {}
	for _, file in ipairs(Parse(addon)) do
		if file:match("%.xml$") then
			LoadXML(addon, "", file:gsub("\\", "/"), ns)
		else
			MOCK.LoadLua(addon, file, ns)
		end
	end
	MOCK.loaded[addon] = true
	MOCK.Fire("ADDON_LOADED", addon)
	return ns
end

MOCK.LoadAddOn = function(name)
	if not readfile(name .. "/" .. name .. ".toc") then return false, "MISSING" end
	MOCK.LoadTOC(name)
	return true
end
