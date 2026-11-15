-- ============================================================================
-- ZacUF - Profiles.lua
-- Named profile storage plus import/export to a shareable text string.
--
-- A "profile" is just a snapshot of the live config (everything in ns.defaults).
-- Named profiles live in ZacUFDB._profiles; the active config stays at the top
-- level of ZacUFDB as usual. Saving copies the live config into the store;
-- loading/importing copies a snapshot back over the live config, backfills any
-- missing defaults, and the caller reloads so frames rebuild cleanly.
-- ============================================================================
local ADDON, ns = ...

-- Keys that belong to a profile: everything except the store + version stamp.
local function isProfileKey(k)
    return k ~= "_profiles" and k ~= "_cfgVersion"
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = deepCopy(val) end
    return t
end
ns.DeepCopy = deepCopy

-- Fresh deep copy of the live config (no _profiles / _cfgVersion).
local function snapshot()
    local out = {}
    for k, v in pairs(ns.db) do
        if isProfileKey(k) then out[k] = deepCopy(v) end
    end
    return out
end

-- Replace the live config with `data`, then backfill defaults for anything the
-- incoming data didn't carry (forward/backward compatibility).
local function adopt(data)
    for k in pairs(ns.db) do
        if isProfileKey(k) then ns.db[k] = nil end
    end
    for k, v in pairs(data) do
        if isProfileKey(k) then ns.db[k] = deepCopy(v) end
    end
    ns.DeepFill(ns.db, ns.defaults)
end

-- ----------------------------------------------------------------------------
-- Named profile store
-- ----------------------------------------------------------------------------
local function store()
    ns.db._profiles = ns.db._profiles or {}
    return ns.db._profiles
end

function ns.ListProfiles()
    local out = {}
    for name in pairs(store()) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function ns.SaveProfile(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
    if not name or name == "" then return false end
    store()[name] = snapshot()
    return true
end

function ns.LoadProfile(name)
    local p = store()[name]
    if not p then return false end
    adopt(p)
    return true
end

function ns.DeleteProfile(name)
    if store()[name] then store()[name] = nil; return true end
    return false
end

-- ----------------------------------------------------------------------------
-- Serialize / deserialize (plain Lua table literal, tagged + sandboxed on read)
-- ----------------------------------------------------------------------------
local function ser(v)
    local t = type(v)
    if t == "number" then
        return string.format("%.14g", v)
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            local key = (type(k) == "number") and ("[" .. k .. "]")
                                              or  ("[" .. string.format("%q", tostring(k)) .. "]")
            parts[#parts + 1] = key .. "=" .. ser(val)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

-- The current config as a shareable string.
function ns.ExportString()
    return "ZacUF1!" .. ser(snapshot())
end

-- Parse + adopt a string produced by ExportString. Returns ok, errMessage.
function ns.ImportString(str)
    if type(str) ~= "string" then return false, "no text" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    local body = str:match("^ZacUF1!(.+)$")
    if not body then return false, "that isn't a unit frame profile string" end
    local f = loadstring("return " .. body)
    if not f then return false, "couldn't parse the string" end
    setfenv(f, {})                              -- literal only: no globals, no function calls
    local ok, data = pcall(f)
    if not ok or type(data) ~= "table" then return false, "the string is corrupt" end
    adopt(data)
    return true
end
