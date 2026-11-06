-- Core_Profiles - named setting snapshots, and copy-pasteable strings for
-- moving them between characters and between people.
-- Part of ZacUI; load order is set by the TOC.
--
-- SECURITY, because this is the one place it matters. An import string
-- arrives from outside the game - a Discord paste, a forum post, a
-- guildmate. The obvious implementation is to serialise as Lua and read it
-- back with loadstring, and that is a remote code execution hole: anything
-- inside the string runs with the addon's full permissions. So this file
-- ships its OWN format and its OWN recursive-descent parser. Nothing from
-- an import string is ever compiled or executed - it is only ever read as
-- data, and anything malformed is rejected with a message rather than a
-- half-applied profile.
--
-- The format is length-prefixed, which means no escaping rules and no way
-- for a crafted string to break out of a value:
--     N<number>;        a number
--     S<len>:<bytes>    a string, exactly <len> bytes
--     B0 / B1           a boolean
--     {<key><value>...} a table, keys are themselves values
--
-- That is then Base64'd so it survives a chat box, and prefixed with a
-- version and a checksum so a truncated paste fails loudly.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Print = ns.Print

local FORMAT_VERSION = 1

-- WHAT A PROFILE IS. Every setting ZacUI keeps, grouped into SECTIONS -
-- the one registry the Profiles page, export, import, copy-between-
-- profiles and reset all read. A section is one or more top-level
-- ZacUIDB keys. Anything NOT listed here is bookkeeping (which config
-- page was open, the defaults revision, the profile store itself) or
-- gathered data (auction prices, gold history) and stays account-wide,
-- outside every profile and every string.
--
-- MODEL (Readycheck's): a character WEARS a named profile. At login that
-- profile is copied into the live ZacUIDB tables every module reads; at
-- logout, reload and whenever the config window closes, the live tables
-- are written back into it. So two characters can wear two different
-- profiles and each keeps its own, and a change made on one character is
-- waiting for every other character wearing the same profile.
local SECTIONS = {
    { key = "modules",    label = "Module switches",   keys = { "modules" },
      desc = "Which ZacUI modules are on." },
    { key = "appearance", label = "Font and colours",  keys = { "font", "media", "colors", "palette" },
      desc = "The font, the bar texture, the palette and every colour override." },
    { key = "motion",     label = "Animations",        keys = { "motion" },
      desc = "Whether ZacUI animates, and how fast." },
    { key = "positions",  label = "Positions",         keys = { "movers", "tooltipPos", "windowPos", "positions", "moveSnap", "editMode" },
      desc = "Where movable frames, windows, the tooltip anchor and Edit Mode's own settings sit." },
    { key = "panels",     label = "Panel calibration", keys = { "insets", "lines" },
      desc = "Per-window inset and line calibration." },
    { key = "bars",       label = "Action bars",       keys = { "bars" },
      desc = "Every bar profile, which character wears which, and the profile for new characters." },
    { key = "loadouts",   label = "Bar loadouts",      keys = { "loadouts", "loadoutRules" },
      desc = "Saved loadouts (slots, macros, keys) and the login rules that apply them." },
    { key = "buffs",      label = "Buff layout",       keys = { "buffsPerRow", "buffsAlwaysExpanded", "auraStyle" },
      desc = "Buffs per row and the consolidation switch." },
    { key = "bags",       label = "Combined bag",      keys = { "bags" } },
    { key = "tray",       label = "Button tray",       keys = { "tray" } },
    { key = "minimap",    label = "Minimap",           keys = { "minimap", "minimapButton" } },
    { key = "chat",       label = "Chat",              keys = { "chat" },
      desc = "The chat bar, what it shows, and where the edit box opens." },
    { key = "maps",       label = "Maps",              keys = { "maps" } },
    { key = "windows",    label = "Game windows",      keys = { "windows" } },
    { key = "unitframes", label = "Unit frames",       keys = { "unitframes" },
      desc = "Every unit frame setting: frames, bars, text, auras, heals, party and raid layout." },
    { key = "nameplates", label = "Nameplates",        keys = { "nameplates", "npScripts" },
      desc = "The nameplate engine and its scripts." },
    { key = "meter",      label = "Damage meter",      keys = { "meter" } },
    { key = "blessings",  label = "Blessings bar",     keys = { "blessings" } },
    { key = "consbars",   label = "Consumable bars",   keys = { "consbars" },
      desc = "The consumables, potion and weapon bars: their items, order, options and look." },
    { key = "sct",        label = "Scrolling text",    keys = { "sct" },
      desc = "The scrolling combat text: its areas, events, alerts and look." },
    { key = "qol",        label = "Quality of life",   keys = { "qol" } },
    { key = "tooltip",    label = "Tooltips",          keys = { "tooltip", "tooltipHide" },
      desc = "Cursor anchoring, the unit-coloured border, health numbers, and when unit tooltips stay hidden." },
    { key = "lootroll",   label = "Loot rolls",        keys = { "lootRoll" },
      desc = "The group loot roll bars: their size, texts and where each part sits." },
    { key = "hud",        label = "Class HUDs",        keys = { "hud" } },
    { key = "auras",      label = "Aura engine",       keys = { "auraEngine" },
      desc = "The embedded aura engine's switches (not the auras themselves, which live in ZacUI_Auras)." },
    { key = "buffRem",    label = "Buff reminders",    keys = { "buffRem" },
      desc = "The group buff reminders and tracker: which buffs, when they show, their look and texts." },
}
local SECTION_BY_KEY = {}
for _, sec in ipairs(SECTIONS) do SECTION_BY_KEY[sec.key] = sec end

-- Flat list of every DB key a profile holds. Kept under the old name
-- because other files read it.
local PROFILE_KEYS = {}
for _, sec in ipairs(SECTIONS) do
    for _, k in ipairs(sec.keys) do PROFILE_KEYS[#PROFILE_KEYS + 1] = k end
end
local IS_PROFILE_KEY = {}
for _, k in ipairs(PROFILE_KEYS) do IS_PROFILE_KEY[k] = true end

local DEFAULT_NAME = "Default"

-- ============================================================
-- SERIALISE
-- ============================================================
local function Encode(value, out)
    local t = type(value)
    if t == "number" then
        -- %.14g round-trips a double without trailing float noise.
        out[#out + 1] = "N" .. string.format("%.14g", value) .. ";"
    elseif t == "string" then
        out[#out + 1] = "S" .. #value .. ":" .. value
    elseif t == "boolean" then
        out[#out + 1] = value and "B1" or "B0"
    elseif t == "table" then
        out[#out + 1] = "{"
        -- Sorted keys, so the same settings always produce the same string.
        -- Without this an export "changes" every time you open the window,
        -- and diffing two profiles is impossible.
        local numeric, textual = {}, {}
        for k in pairs(value) do
            if type(k) == "number" then numeric[#numeric + 1] = k
            elseif type(k) == "string" then textual[#textual + 1] = k end
        end
        table.sort(numeric)
        table.sort(textual)
        for _, k in ipairs(numeric) do
            Encode(k, out)
            Encode(value[k], out)
        end
        for _, k in ipairs(textual) do
            Encode(k, out)
            Encode(value[k], out)
        end
        out[#out + 1] = "}"
    else
        -- Functions and userdata cannot be in a settings table; if one
        -- turns up, write nil rather than corrupting the stream.
        out[#out + 1] = "B0"
    end
end

local function Serialize(tbl)
    local out = {}
    Encode(tbl, out)
    return table.concat(out)
end

-- ============================================================
-- PARSE
-- ============================================================
-- Hand-written, bounds-checked, and it never calls anything. Errors are
-- returned rather than thrown so the caller can report them.
local function Parse(str, pos, depth)
    if depth > 32 then return nil, pos, "nested too deeply" end
    local tag = str:sub(pos, pos)
    if tag == "" then return nil, pos, "unexpected end of data" end

    if tag == "N" then
        local stop = str:find(";", pos + 1, true)
        if not stop then return nil, pos, "unterminated number" end
        local n = tonumber(str:sub(pos + 1, stop - 1))
        if not n then return nil, pos, "malformed number" end
        return n, stop + 1

    elseif tag == "S" then
        local colon = str:find(":", pos + 1, true)
        if not colon then return nil, pos, "unterminated string header" end
        local len = tonumber(str:sub(pos + 1, colon - 1))
        if not len or len < 0 then return nil, pos, "malformed string length" end
        local from = colon + 1
        local to = from + len - 1
        if to > #str then return nil, pos, "string runs past end of data" end
        return str:sub(from, to), to + 1

    elseif tag == "B" then
        local v = str:sub(pos + 1, pos + 1)
        if v ~= "0" and v ~= "1" then return nil, pos, "malformed boolean" end
        return v == "1", pos + 2

    elseif tag == "{" then
        local tbl = {}
        pos = pos + 1
        local count = 0
        while true do
            if str:sub(pos, pos) == "}" then return tbl, pos + 1 end
            if pos > #str then return nil, pos, "unterminated table" end
            count = count + 1
            if count > 10000 then return nil, pos, "table too large" end
            local key, value, err
            key, pos, err = Parse(str, pos, depth + 1)
            if err then return nil, pos, err end
            if key == nil then return nil, pos, "table key is nil" end
            value, pos, err = Parse(str, pos, depth + 1)
            if err then return nil, pos, err end
            tbl[key] = value
        end
    end
    return nil, pos, "unknown tag '" .. tag .. "'"
end

local function Deserialize(str)
    local value, _, err = Parse(str, 1, 0)
    if err then return nil, err end
    if type(value) ~= "table" then return nil, "payload is not a table" end
    return value
end

-- ============================================================
-- TRANSPORT
-- ============================================================
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function Base64Encode(data)
    local out, n = {}, #data
    for i = 1, n, 3 do
        local a, b, c = data:byte(i, i + 2)
        local triple = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(triple / 262144) % 64
        local c2 = math.floor(triple / 4096) % 64
        local c3 = math.floor(triple / 64) % 64
        local c4 = triple % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=")
            .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local DECODE = {}
for i = 1, #B64 do DECODE[B64:sub(i, i)] = i - 1 end

local function Base64Decode(text)
    text = text:gsub("[^%w%+/=]", "")
    local out = {}
    for i = 1, #text, 4 do
        local c1 = DECODE[text:sub(i, i)]
        local c2 = DECODE[text:sub(i + 1, i + 1)]
        if not c1 or not c2 then return nil end
        local s3, s4 = text:sub(i + 2, i + 2), text:sub(i + 3, i + 3)
        local c3, c4 = DECODE[s3], DECODE[s4]
        local triple = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
        out[#out + 1] = string.char(math.floor(triple / 65536) % 256)
        if s3 ~= "=" and s3 ~= "" then
            out[#out + 1] = string.char(math.floor(triple / 256) % 256)
        end
        if s4 ~= "=" and s4 ~= "" then
            out[#out + 1] = string.char(triple % 256)
        end
    end
    return table.concat(out)
end

-- A cheap additive-rotating checksum. Not cryptography - its whole job is
-- to catch a paste that lost its last line, which is by far the most
-- common way an import string arrives broken.
local function Checksum(text)
    local sum = 5381
    for i = 1, #text do
        sum = (sum * 33 + text:byte(i)) % 4294967296
    end
    return string.format("%08x", sum)
end

-- ============================================================
-- SNAPSHOTS
-- ============================================================
local function DeepCopy(value, depth)
    if type(value) ~= "table" then return value end
    if (depth or 0) > 16 then return nil end
    local out = {}
    for k, v in pairs(value) do out[k] = DeepCopy(v, (depth or 0) + 1) end
    return out
end

-- The DB keys a list of section keys expands to; nil = every section.
local function KeysFor(sectionKeys)
    if not sectionKeys then return PROFILE_KEYS end
    local out = {}
    for _, sk in ipairs(sectionKeys) do
        local sec = SECTION_BY_KEY[sk]
        if sec then for _, k in ipairs(sec.keys) do out[#out + 1] = k end end
    end
    return out
end

-- Which sections a snapshot actually carries.
local function SectionsIn(snap)
    local out = {}
    for _, sec in ipairs(SECTIONS) do
        for _, k in ipairs(sec.keys) do
            if snap[k] ~= nil then out[#out + 1] = sec.key break end
        end
    end
    return out
end

local function Snapshot(sectionKeys)
    local snap = {}
    for _, key in ipairs(KeysFor(sectionKeys)) do
        if ZacUIDB[key] ~= nil then snap[key] = DeepCopy(ZacUIDB[key]) end
    end
    return snap
end

-- Applying REPLACES the chosen keys outright rather than merging. A merge
-- would leave a module you had turned off in the source profile still on
-- here, which is not what "load this profile" means to anyone. Keys the
-- snapshot does not carry are left as they are.
local function Apply(snap, sectionKeys)
    if type(snap) ~= "table" then return false, "not a profile" end
    for _, key in ipairs(KeysFor(sectionKeys)) do
        if snap[key] ~= nil then
            ZacUIDB[key] = DeepCopy(snap[key])
        end
    end
    -- Any module the source profile predates must not arrive missing.
    ZacUIDB.modules = ZacUIDB.modules or {}
    for m, v in pairs(ns.DEFAULT_MODULES or {}) do
        if ZacUIDB.modules[m] == nil then ZacUIDB.modules[m] = v end
    end
    return true
end

-- WEARING a profile is stricter than applying one: every profile key is
-- replaced, and a key the profile does not carry is cleared so the module
-- rebuilds it from shipped defaults. Otherwise a fresh "shipped defaults"
-- profile would silently inherit whatever the last profile left on screen
-- and write it back as its own. The few tables Boot_Events fills before
-- the DB is read are re-filled here because modules index them directly.
-- Keys that joined the profile sections after profiles already existed:
-- a profile saved before then has no word on them, so wearing it keeps
-- what is there instead of wiping it (the blessings bar's settings
-- predate their section by weeks).
local LATE_KEYS = { blessings = true, windows = true, motion = true, buffRem = true, consbars = true }
-- the same for the spots of frames newer than a profile: a profile with
-- no word on them leaves where they are (the consumable bars' and the buff
-- reminders' spots were wiped by wearing a profile saved before them)
local LATE_MOVER = { "^consbars_", "^buffRem" }
local function LateMover(k)
    if type(k) ~= "string" then return false end
    for _, pat in ipairs(LATE_MOVER) do if k:find(pat) then return true end end
    return false
end

local function Wear(snap)
    if type(snap) ~= "table" then return false, "not a profile" end
    local keepMovers
    if type(ZacUIDB.movers) == "table" then
        for k, v in pairs(ZacUIDB.movers) do
            if LateMover(k) and not (type(snap.movers) == "table" and snap.movers[k] ~= nil) then
                keepMovers = keepMovers or {}
                keepMovers[k] = DeepCopy(v)
            end
        end
    end
    for _, key in ipairs(PROFILE_KEYS) do
        if snap[key] ~= nil or not LATE_KEYS[key] then
            ZacUIDB[key] = DeepCopy(snap[key])
        end
    end
    if keepMovers then
        ZacUIDB.movers = ZacUIDB.movers or {}
        for k, v in pairs(keepMovers) do ZacUIDB.movers[k] = v end
    end
    ZacUIDB.modules = ZacUIDB.modules or {}
    for m, v in pairs(ns.DEFAULT_MODULES or {}) do
        if ZacUIDB.modules[m] == nil then ZacUIDB.modules[m] = v end
    end
    ZacUIDB.font    = ZacUIDB.font or { name = nil, delta = 0, outline = nil }
    ZacUIDB.insets  = ZacUIDB.insets or {}
    ZacUIDB.lines   = ZacUIDB.lines or {}
    ZacUIDB.colors  = ZacUIDB.colors or {}
    ZacUIDB.palette = ZacUIDB.palette or {}
    ZacUIDB.movers  = ZacUIDB.movers or {}
    return true
end

-- ============================================================
-- PROFILE STORE
-- ============================================================
local function Store()
    ZacUIDB.profiles = ZacUIDB.profiles or {}
    return ZacUIDB.profiles
end

local function CharKey()
    local name, realm = UnitName("player"), GetRealmName()
    return (name or "?") .. " - " .. (realm or "?")
end

-- The map of every character on the account to the profile it wears,
-- for the Profiles page. The authoritative per-character choice is in
-- ZacUICharDB.profile; this mirrors it so other characters can be shown.
local function CharMap()
    ZacUIDB.charProfiles = ZacUIDB.charProfiles or {}
    return ZacUIDB.charProfiles
end

local function DefaultName()
    if ZacUIDB.defaultProfile and Store()[ZacUIDB.defaultProfile] then return ZacUIDB.defaultProfile end
    return DEFAULT_NAME
end

local function Current()
    ZacUICharDB = ZacUICharDB or {}
    local name = ZacUICharDB.profile
    if name and Store()[name] then return name end
    return nil
end

local function List()
    local names = {}
    for name in pairs(Store()) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local function UsedBy(name)
    local out = {}
    for ck, pn in pairs(CharMap()) do
        if pn == name then out[#out + 1] = ck end
    end
    table.sort(out)
    return out
end

-- Live settings -> the profile this character wears. Called at logout and
-- reload, when the config window closes, and before anything reads the
-- store for export or copy, so the store never lags behind the screen.
local function WriteBack()
    local name = Current()
    if not name then return false end
    Store()[name] = Snapshot()
    return true
end

local function Save(name)
    if not name or name == "" then return false, "give the profile a name" end
    Store()[name] = Snapshot()
    return true
end

-- Puts a profile's settings on screen (callers reload afterwards).
local function Load(name)
    local snap = Store()[name]
    if not snap then return false, "no profile called '" .. tostring(name) .. "'" end
    return Apply(snap)
end

-- This character switches to another profile: what it had is written
-- back first so nothing is lost, then the new one is applied.
local function Use(name)
    if not Store()[name] then return false, "no profile called '" .. tostring(name) .. "'" end
    WriteBack()
    ZacUICharDB = ZacUICharDB or {}
    ZacUICharDB.profile = name
    CharMap()[CharKey()] = name
    return Wear(Store()[name])
end

local function New(name, fromDefaults)
    if not name or name == "" then return false, "give the profile a name" end
    if Store()[name] then return false, "'" .. name .. "' already exists" end
    if fromDefaults then
        Store()[name] = { modules = DeepCopy(ns.DEFAULT_MODULES or {}) }
    else
        Store()[name] = Snapshot()
    end
    return true
end

local function Delete(name)
    if not Store()[name] then return false, "no such profile" end
    local used = UsedBy(name)
    if Current() == name then return false, "this character is wearing it - switch first" end
    Store()[name] = nil
    for _, ck in ipairs(used) do CharMap()[ck] = nil end
    if ZacUIDB.defaultProfile == name then ZacUIDB.defaultProfile = nil end
    return true
end

local function Rename(from, to)
    local store = Store()
    if not store[from] then return false, "no such profile" end
    if not to or to == "" then return false, "give the profile a name" end
    if store[to] then return false, "'" .. to .. "' already exists" end
    store[to], store[from] = store[from], nil
    for ck, pn in pairs(CharMap()) do if pn == from then CharMap()[ck] = to end end
    if ZacUICharDB and ZacUICharDB.profile == from then ZacUICharDB.profile = to end
    if ZacUIDB.defaultProfile == from then ZacUIDB.defaultProfile = to end
    return true
end

-- Copy chosen sections from another profile onto the live settings (and
-- so into this character's profile at the next write-back).
local function CopyFrom(name, sectionKeys)
    local snap = Store()[name]
    if not snap then return false, "no such profile" end
    if name == Current() then return false, "that is this character's own profile" end
    return Apply(snap, sectionKeys)
end

-- Reset chosen sections to shipped defaults: the keys are dropped and the
-- modules fill them back in at the next reload.
local function ResetSections(sectionKeys)
    for _, key in ipairs(KeysFor(sectionKeys)) do ZacUIDB[key] = nil end
    ZacUIDB.modules = ZacUIDB.modules or {}
    for m, v in pairs(ns.DEFAULT_MODULES or {}) do
        if ZacUIDB.modules[m] == nil then ZacUIDB.modules[m] = v end
    end
    return true
end

-- ============================================================
-- LOGIN
-- ============================================================
-- Runs from ADDON_LOADED, before any module reads the DB. First time on
-- this build: the live settings become the "Default" profile and every
-- character that had no auto-profile is pointed at it, so nothing on
-- screen changes for anyone. Then this character's profile is applied.
local function Login()
    ZacUICharDB = ZacUICharDB or {}
    local store = Store()
    -- 1.x kept the choice under autoProfile
    if ZacUICharDB.autoProfile and not ZacUICharDB.profile then
        ZacUICharDB.profile = ZacUICharDB.autoProfile
    end
    ZacUICharDB.autoProfile = nil
    if not store[DEFAULT_NAME] and not next(store) then
        store[DEFAULT_NAME] = Snapshot()
    elseif not store[DEFAULT_NAME] and not store[DefaultName()] then
        store[DEFAULT_NAME] = Snapshot()
    end
    local name = Current()
    if not name then
        name = DefaultName()
        if not store[name] then
            store[name] = Snapshot()
        end
        ZacUICharDB.profile = name
    end
    CharMap()[CharKey()] = name
    local ok = Wear(store[name])
    ZacUIDB.profilesV2 = true
    return ok and name or nil
end

local logout = CreateFrame("Frame")
logout:RegisterEvent("PLAYER_LOGOUT")
logout:SetScript("OnEvent", function()
    if ZacUIDB and ZacUICharDB then pcall(WriteBack) end
end)

-- ============================================================
-- EXPORT / IMPORT
-- ============================================================
local function Export(name, sectionKeys)
    local snap
    if name then
        if name == Current() then WriteBack() end
        local src = Store()[name]
        if not src then return nil, "no such profile" end
        snap = {}
        for _, key in ipairs(KeysFor(sectionKeys)) do
            if src[key] ~= nil then snap[key] = DeepCopy(src[key]) end
        end
    else
        snap = Snapshot(sectionKeys)
    end
    local body = Base64Encode(Serialize(snap))
    return string.format("ZacUI:%d:%s:%s", FORMAT_VERSION, Checksum(body), body)
end

-- Generic transport for ZacUI's other stores (bar loadouts): the same
-- serializer, Base64 and checksum under a different prefix, so one
-- parser and one set of failure messages cover every string ZacUI emits.
local function PackString(prefix, tbl)
    local body = Base64Encode(Serialize(tbl))
    return string.format("%s:%d:%s:%s", prefix, FORMAT_VERSION, Checksum(body), body)
end

local function UnpackString(prefix, text)
    if type(text) ~= "string" then return nil, "nothing to import" end
    text = text:gsub("%s", "")
    if text == "" then return nil, "nothing to import" end
    local version, sum, body = text:match("^" .. prefix .. ":(%d+):(%x+):(.+)$")
    if not version then return nil, "this does not look like a " .. prefix .. " string" end
    version = tonumber(version)
    if version > FORMAT_VERSION then
        return nil, "made by a newer ZacUI (format " .. version .. ", this one reads " .. FORMAT_VERSION .. ")"
    end
    if Checksum(body) ~= sum then
        return nil, "the string is damaged or incomplete - copy it again, all of it"
    end
    local raw = Base64Decode(body)
    if not raw then return nil, "the string contains characters that are not valid" end
    return Deserialize(raw)
end

-- A profile string, any version: returns the snapshot (data only).
local function Import(text)
    local snap, err = UnpackString("ZacUI", text)
    if not snap then return nil, err end
    if type(snap) ~= "table" then return nil, "payload is not a table" end
    local known = false
    for _, key in ipairs(PROFILE_KEYS) do
        if snap[key] ~= nil then known = true end
    end
    if not known then return nil, "the profile contains no ZacUI settings" end
    return snap
end

-- shared with later ZacUI files
ns.Profiles = {
    PROFILE_KEYS = PROFILE_KEYS,
    SECTIONS = SECTIONS,
    DEFAULT_NAME = DEFAULT_NAME,
    Apply = Apply,
    CharKey = CharKey,
    CharMap = CharMap,
    CopyFrom = CopyFrom,
    Current = Current,
    DefaultName = DefaultName,
    Delete = Delete,
    Deserialize = Deserialize,
    Export = Export,
    Import = Import,
    List = List,
    Load = Load,
    Login = Login,
    New = New,
    PackString = PackString,
    UnpackString = UnpackString,
    Rename = Rename,
    ResetSections = ResetSections,
    Save = Save,
    SectionsIn = SectionsIn,
    Serialize = Serialize,
    Snapshot = Snapshot,
    Store = Store,
    Use = Use,
    UsedBy = UsedBy,
    WriteBack = WriteBack,
}

-- ============================================================
-- ANY STRING, ANY BOX
-- ============================================================
-- ZacUI writes three kinds of string and reads two more, and each had
-- its own box that refused the others: a bar loadout pasted on the
-- Profiles page was "not a ZacUI string", a profile pasted under Auras
-- was "invalid import data". Every one of them starts differently, so a
-- pasted string says what it is. Identify reads that and describes it;
-- Run hands it to the importer that owns it. The pages use both, so
-- whatever is pasted wherever, it is named and it works.
--
--   ZacUI:<v>:        a profile                 (here)
--   ZacUILoadout:<v>: a bar loadout             (Zacui_Bars)
--   a Myslot export   a bar loadout             (Zacui_Bars)
--   ZacUF1!           a unit frames profile     (Zacui_UnitFrames)
--   !WA:<v>!          a WeakAuras / Wago string (the auras part)
--   ZacUIBuffs:<v>:   a buff remover setup      (Zacui_QoL)
--   anything Readycheck exports                 (Readycheck, when loaded)
--
-- The importers that live in a part are looked up when called: a string
-- for a part that is switched off is still recognised and says which
-- part it needs. Nothing here changes what any importer does, and
-- nothing in a string is executed by this file - describing a profile
-- or a loadout goes through the same data-only parsers as importing it.
local P = ns.Profiles

-- Above this a paste is recognised by how it starts and is not decoded
-- just to describe it.
local DESCRIBE_LIMIT = 300000

-- Pasted text has usually been through a chat app, and what a chat app
-- leaves around a string is peeled off here: blank lines, a byte-order
-- mark, non-breaking and zero-width spaces, a code fence (with or
-- without a language word after it), inline-code backticks, a quote
-- marker on every line. Backticks at the END only go when one was
-- found at the start - text may end in a backtick of its own.
local function CleanPaste(text)
    if type(text) ~= "string" then return "" end
    -- how many backticks came off the front: that many, and no more,
    -- come off the back
    local ticks, quoted = 0, 0
    local n
    -- From the end, byte by byte: a pattern ending in "$" is tried at
    -- every blank in the text, which on a long run of blanks in the
    -- middle of a paste takes seconds.
    local function Trim()
        local e = #text
        while e > 0 do
            local b = text:byte(e)
            if b == 32 or (b >= 9 and b <= 13) then
                e = e - 1
            elseif b == 160 and e >= 2 and text:byte(e - 1) == 194 then
                e = e - 2
            elseif b == 139 and e >= 3 and text:byte(e - 1) == 128 and text:byte(e - 2) == 226 then
                e = e - 3
            else
                break
            end
        end
        if e < #text then text = text:sub(1, e) end
    end
    local again = true
    while again do
        again = false
        text, n = text:gsub("^%s+", "")                        if n > 0 then again = true end
        text, n = text:gsub("^\239\187\191", "")               if n > 0 then again = true end
        text, n = text:gsub("^\194\160", "")                   if n > 0 then again = true end
        text, n = text:gsub("^\226\128\139", "")               if n > 0 then again = true end
        local _, marks = text:find("^>+")
        if marks then
            text, again = text:sub(marks + 1), true
            if quoted == 0 then quoted = marks end
        end
        -- a fence's language word is lower case; WRN3 and WRROUTE1,
        -- which also sit alone on a first line, are not
        text, n = text:gsub("^```%l*[ \t]*\r?\n", "")          if n > 0 then again, ticks = true, ticks + 3 end
        local _, last = text:find("^`+")
        if last then
            text, ticks, again = text:sub(last + 1), ticks + last, true
        end
    end
    Trim()
    if ticks > 0 then
        local e, took = #text, 0
        while took < ticks and e > 0 and text:byte(e) == 96 do e, took = e - 1, took + 1 end
        if took > 0 then
            text = text:sub(1, e)
            Trim()
        end
    end
    -- A quote block marks every line, not only the first. The marks come
    -- off only when every line that has anything on it carries one: a
    -- single ">" before the first line says nothing about the others,
    -- and a line of the string itself may begin with ">".
    if quoted > 0 and text:find("\n", 1, true) then
        local all = true
        for line in text:gmatch("\n([^\n]*)") do
            if line:find("%S") and not line:find("^[ \t]*>") then all = false break end
        end
        if all then
            text = text:gsub("\n[ \t]*" .. (">"):rep(math.min(quoted, 8)) .. "[ \t]?", "\n")
            Trim()
        end
    end
    return text
end

-- True when `str` is nothing but a table of plain values: no function,
-- no call, no comment, no long string. Text that passes can be handed
-- to loadstring to be READ - there is nothing in it that can run, loop
-- or call - and that is the only kind this file ever loads to describe
-- a paste. Quoted strings are stepped over by their own closing quote,
-- so a string holding the word "function" is still only a string.
-- Returns true, or false and "cut" when a quoted string never closes
-- (the paste was cut short - damage, not code).
local function PureLiteral(str)
    local pos = 1
    while true do
        local s, _, ch = str:find("([\"'%(%[f%-])", pos)
        if not s then return true end
        if ch == '"' or ch == "'" then
            local p = s + 1
            while true do
                local q = str:find("[\\" .. ch .. "]", p)
                if not q then return false, "cut" end
                if str:sub(q, q) == "\\" then p = q + 2 else pos = q + 1 break end
            end
        elseif ch == "(" then
            return false
        elseif ch == "[" then
            local nx = str:sub(s + 1, s + 1)
            if nx == "[" or nx == "=" then return false end
            pos = s + 1
        elseif ch == "-" then
            if str:sub(s + 1, s + 1) == "-" then return false end
            pos = s + 1
        else
            if str:find("^function", s) and not str:sub(s - 1, s - 1):find("[%w_]")
               and not str:sub(s + 8, s + 8):find("[%w_]") then return false end
            pos = s + 1
        end
    end
end

local function TrimName(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function SectionNames(keys)
    local names = {}
    for _, k in ipairs(keys or {}) do
        local sec = SECTION_BY_KEY[k]
        if sec then names[#names + 1] = sec.label end
    end
    return table.concat(names, ", ")
end

local function Plural(n, one, many)
    return n .. " " .. (n == 1 and one or many)
end

-- Strings Readycheck writes, for naming them when Readycheck is not
-- there to do it itself.
local READYCHECK_STRINGS = {
    { "^RCS2:",   "Readycheck settings" },
    { "^WRS[12]:", "Readycheck settings" },
    { "^WR1:",    "a Readycheck raid profile" },
    { "^WRN[123]", "Readycheck boss and trash notes" },
    { "^WR_CR:",  "a Readycheck custom reminder" },
}

local function DetectPaste(text)
    if text == "" then return "empty" end
    if text:find("^ZacUI:%d+:") then return "profile" end
    if text:find("^ZacUILoadout:%d+:") then return "loadout" end
    if text:find("^ZacUIBuffs:%d+:") then return "buffs" end
    if text:find("^ZacUF1!") then return "unitframes" end
    if text:find("^!WA:%d+!") then return "weakauras" end
    -- the older WeakAuras form: "!" and then nothing but its alphabet
    if #text >= 40 and text:find("^![%w%(%)]+$") then return "weakauras" end
    -- A Myslot export opens with "#" comment lines that name it. The
    -- opening character is checked as well: plenty of other strings can
    -- mention Myslot somewhere in their first few hundred characters.
    local first = text:sub(1, 1)
    if (first == "#" or first == "@")
       and text:sub(1, 600):lower():find("myslot", 1, true) then return "myslot" end
    return nil
end

local function DescribeProfile(text, info, deep)
    info.title = "ZacUI profile"
    if not deep then
        info.ready = true
        info.lines[#info.lines + 1] = "A large string - " .. #text .. " characters."
    else
        local snap, err = P.Import(text)
        if not snap then
            info.problem = tostring(err)
            return
        end
        info.snap  = snap
        info.ready = true
        info.sections = P.SectionsIn(snap)
        info.lines[#info.lines + 1] = "Carries: " .. SectionNames(info.sections)
    end
    info.actions = {
        { id = "apply", label = "Apply to this character", reload = true,
          effect = "Those sections replace this character's; everything else stays. A reload follows." },
        { id = "save", label = "Save as new profile", needsName = true,
          effect = "Stores it as a profile nobody wears yet. Switch a character to it on the Profiles page." },
    }
end

local function DescribeLoadout(text, info, deep, kind)
    info.title = (kind == "myslot") and "Myslot export (bar loadout)" or "ZacUI bar loadout"
    local LO = ns.Loadouts
    if not LO then
        info.problem = "Needs ZacUI's action bars part (Zacui_Bars). Enable it in your AddOns list and reload."
        return
    end
    if deep then
        local lo, err
        if kind == "myslot" then lo, err = LO.DecodeMyslot(text) else lo, err = LO.Import(text) end
        if not lo then
            info.problem = tostring(err)
            return
        end
        info.loadout = lo
        local slots = 0
        for _ in pairs(lo.slots or {}) do slots = slots + 1 end
        local who = {}
        if lo.class then who[#who + 1] = tostring(lo.class):sub(1, 1) .. tostring(lo.class):sub(2):lower() end
        if lo.player then who[#who + 1] = tostring(lo.player) end
        info.lines[#info.lines + 1] = (#who > 0 and (table.concat(who, " - ") .. ": ") or "")
            .. Plural(slots, "slot", "slots") .. ", " .. Plural(#(lo.macros or {}), "macro", "macros")
            .. ", " .. Plural(#(lo.binds or {}), "key", "keys")
        info.defaultName = lo.name or lo.player or "Imported"
    else
        info.lines[#info.lines + 1] = "A large string - " .. #text .. " characters."
    end
    info.ready = true
    info.actions = {
        { id = "save", label = "Save as loadout", needsName = true,
          effect = "Saves it under Bars > Loadouts. Nothing on your bars changes until you apply it." },
        { id = "apply", label = "Apply to my bars now",
          effect = "Puts it on this character's bars now, without saving it." },
    }
end

local function DescribeUnitFrames(text, info, deep)
    info.title = "ZacUI unit frames profile"
    local UF = _G.ZacUF
    local loaded = type(UF) == "table" and UF.ImportString
    -- Its importer hands the text to loadstring. Whatever its size, a
    -- string with anything in it besides plain values is refused here -
    -- not described, and not passed on to be imported either.
    local body = text:sub(8)
    local pure, why = PureLiteral(body)
    if not pure then
        info.problem = (why == "cut") and "the string is damaged or incomplete - copy it again, all of it"
            or "this string has code in it where only settings belong, so it was not opened"
        return
    end
    if deep then
        -- Read the way its importer reads it - a table of plain values
        -- in an empty environment - so a cut-off string is caught here,
        -- before the importer has cleared the settings it was going to
        -- replace.
        local fn = loadstring("return " .. body)
        if fn and setfenv then setfenv(fn, {}) end
        local ok, data = pcall(fn or error)
        -- groups of settings the unit frames actually have; a table of
        -- anything else would replace every setting with nothing
        local known = loaded and type(UF.defaults) == "table" and UF.defaults or nil
        local groups = 0
        if ok and type(data) == "table" then
            for k in pairs(data) do
                if type(k) == "string" and (not known or known[k] ~= nil) then groups = groups + 1 end
            end
        end
        if groups == 0 then
            info.problem = "the string is damaged or incomplete - copy it again, all of it"
            return
        end
        info.lines[#info.lines + 1] = Plural(groups, "group of settings", "groups of settings")
    else
        info.lines[#info.lines + 1] = "A large string - " .. #text .. " characters."
    end
    if not loaded then
        info.problem = "Needs ZacUI's unit frames part (Zacui_UnitFrames). Enable it in your AddOns list and reload."
        return
    end
    info.ready = true
    info.actions = {
        { id = "apply", label = "Apply unit frames", reload = true,
          effect = "Replaces every unit frame setting this character has. A reload follows." },
    }
end

local function DescribeWeakAuras(text, info)
    info.title = "WeakAuras / Wago string"
    info.lines[#info.lines + 1] = #text .. " characters."
    if not (ns.Auras and ns.Auras.ImportString) then
        info.problem = "Needs ZacUI's auras part. Enable it in your AddOns list and reload."
        return
    end
    info.ready = true
    info.actions = {
        { id = "open", label = "Take it to Auras > Import",
          effect = "Opens the Auras page with this string in its import box. Import there shows what the pack contains before anything is added." },
    }
end

local function BuffRemover() return ns.QoL and ns.QoL.BuffRemover end

local function DescribeBuffs(text, info)
    info.title = "ZacUI buff remover setup"
    local BR = BuffRemover()
    if not (BR and BR.Describe) then
        info.problem = "Needs ZacUI's quality of life part (Zacui_QoL). Enable it in your AddOns list and reload."
        return
    end
    local d, lines = BR.Describe(text)
    if not d then
        info.problem = tostring(lines)
        return
    end
    for _, l in ipairs(lines) do info.lines[#info.lines + 1] = l end
    info.ready = true
    if #d.macros > 0 then
        info.actions[#info.actions + 1] = { id = "all", label = "Set it all up",
            effect = "Replaces that class's buff ticks with these and links the macros"
                .. (d.takeover and ", moving their /cancelaura lines into the remover (undo: Put my macros back)." or ".") }
    end
    info.actions[#info.actions + 1] = { id = "ticks", label = "Ticks only",
        effect = "Replaces that class's buff ticks with these. Your macros are not touched." }
end

-- What a pasted string is. Always returns a table that is safe to show:
--   kind     "empty", "profile", "loadout", "myslot", "unitframes", "buffs",
--            "weakauras", "readycheck" (Readycheck will take it),
--            "foreign" (somebody's, and they are not loaded), "unknown"
--   text     the string as the importers want it
--   title    what it is, in a few words
--   lines    what it carries, zero or more short lines
--   ready    true when Run can take it now; else problem says why not
--   actions  what can be done with it, most usual first:
--            { id, label, effect, reload, needsName }
--   effect / reload   those of the first action, for a caller that only
--            offers one
--   defaultName       a name to offer where an action needs one
-- opts.own: do not ask Readycheck (set by Readycheck when it is asking).
local function Identify(text, opts)
    opts = opts or {}
    local clean = CleanPaste(text)
    local info  = { text = clean, lines = {}, ready = false, actions = {} }
    local kind  = DetectPaste(clean)
    local deep  = #clean <= DESCRIBE_LIMIT

    -- No header, but it may still be a Myslot export pasted without its
    -- "#" lines: a block of base64 whose checksum only Myslot's reader
    -- can vouch for.
    if not kind and deep and ns.Loadouts and ns.Loadouts.DecodeMyslot
       and #clean >= 24 and not clean:find("[^%w%+/=%s]") then
        local ok, lo = pcall(ns.Loadouts.DecodeMyslot, clean)
        if ok and lo then kind = "myslot" end
    end
    info.kind = kind
    if kind == "empty" then return info end

    local describe
    if     kind == "profile"    then describe = DescribeProfile
    elseif kind == "loadout"    then describe = DescribeLoadout
    elseif kind == "myslot"     then describe = DescribeLoadout
    elseif kind == "unitframes" then describe = DescribeUnitFrames
    elseif kind == "weakauras"  then describe = DescribeWeakAuras
    elseif kind == "buffs"      then describe = DescribeBuffs
    end
    if describe then
        -- Describing reads untrusted text; whatever goes wrong in there,
        -- the box it was pasted into has to keep working.
        local ok, err = pcall(describe, clean, info, deep, kind)
        if not ok then
            info.ready, info.actions = false, {}
            info.problem = "the string is damaged or incomplete - copy it again, all of it"
        end
        local first = info.actions[1]
        if first then info.effect, info.reload = first.effect, first.reload and true or false end
        return info
    end

    if not opts.own then
        local RC = _G.Readycheck
        if type(RC) == "table" and RC.IdentifyImport and RC.ImportAny then
            local ok, ri = pcall(RC.IdentifyImport, RC, clean, { own = true })
            if ok and type(ri) == "table" and ri.kind and ri.kind ~= "unknown"
               and ri.kind ~= "empty" and ri.kind ~= "foreign" and ri.kind ~= "zacui" then
                info.kind    = "readycheck"
                info.foreign = ri
                -- say whose it is, unless its own name already does
                local title  = tostring(ri.title or ri.kind)
                info.title   = title:find("Readycheck", 1, true) and title or ("Readycheck: " .. title)
                info.lines   = type(ri.lines) == "table" and ri.lines or {}
                info.ready   = ri.ready and true or false
                info.problem = ri.problem
                info.effect  = ri.effect
                info.reload  = ri.reload and true or false
                info.defaultName = ri.suggestedName
                if info.ready then
                    info.actions = { { id = "import", label = "Import into Readycheck",
                        effect = ri.effect, reload = info.reload, needsName = ri.wantsName,
                        nameOptional = true } }
                end
                return info
            end
        end
        local named
        for _, r in ipairs(READYCHECK_STRINGS) do
            if clean:find(r[1]) then named = r[2] break end
        end
        if not named and clean:sub(1, 400):find("WRROUTE1", 1, true) then named = "a Readycheck raid route" end
        if named then
            info.kind    = "foreign"
            info.title   = "This is " .. named
            info.problem = "It belongs to Readycheck, which is not loaded on this character. Paste it into Readycheck's Import window."
            return info
        end
    end

    info.kind    = "unknown"
    info.title   = "Not recognised"
    info.problem = "This does not start like anything ZacUI can import. If it was copied from ZacUI, the beginning was probably cut off - copy it again, all of it."
    return info
end

-- Does one of a string's actions. actionId is one of info.actions' ids;
-- nil means the first. opts.info: Identify's result for this same text
-- (saves decoding it twice). opts.name: for an action that needs one.
-- Returns ok, message, result. result.kind is always set; result.reload
-- means the caller must reload the UI for the import to take hold - Run
-- never reloads by itself, so the caller can finish what it is doing.
local function RunUnguarded(text, actionId, opts)
    opts = opts or {}
    local info = opts.info
    if type(info) ~= "table" or info.text ~= CleanPaste(text) then info = Identify(text, opts) end
    local kind = info.kind
    local res = { kind = kind }
    if kind == "empty" then return false, "nothing to import", res end
    if not info.ready then return false, info.problem or "that string cannot be imported", res end

    local action
    if actionId == nil then
        action = info.actions[1]
    else
        for _, a in ipairs(info.actions) do
            if a.id == actionId then action = a end
        end
    end
    if not action then return false, "that string cannot be imported that way", res end
    res.action = action.id
    local name = TrimName(opts.name)

    if kind == "profile" then
        local snap = info.snap
        if not snap then
            local err
            snap, err = P.Import(info.text)
            if not snap then return false, tostring(err), res end
        end
        local carried = SectionNames(P.SectionsIn(snap))
        if action.id == "save" then
            if name == "" then return false, "give the new profile a name first", res end
            if P.Store()[name] then return false, "'" .. name .. "' already exists", res end
            P.Store()[name] = DeepCopy(snap)
            res.name = name
            return true, "Saved '" .. name .. "' (" .. carried .. "). Switch a character to it on the Profiles page.", res
        end
        local ok, err = P.Apply(snap)
        if not ok then return false, tostring(err), res end
        P.WriteBack()
        res.reload = true
        return true, "Imported " .. carried .. ".", res

    elseif kind == "loadout" or kind == "myslot" then
        local LO = ns.Loadouts
        local lo = info.loadout
        if not lo then
            local err
            if kind == "myslot" then lo, err = LO.DecodeMyslot(info.text) else lo, err = LO.Import(info.text) end
            if not lo then return false, tostring(err), res end
        end
        if action.id == "apply" then
            local rules = LO.Rules()
            LO.Report(LO.Apply(lo, { clearSlots = rules.clearSlots, clearBinds = rules.clearBinds }),
                lo.name or "pasted")
            return true, nil, res
        end
        if name == "" then name = lo.name or lo.player or "Imported" end
        -- A pasted loadout never replaces one that is already saved: a
        -- taken name gets a number, and the message says which.
        local wanted = name
        if LO.Get and LO.Get(name) then
            local i = 2
            while LO.Get(wanted .. " (" .. i .. ")") do i = i + 1 end
            name = wanted .. " (" .. i .. ")"
        end
        local ok, err = LO.Save(name, DeepCopy(lo))
        if not ok then return false, tostring(err), res end
        res.name = name
        return true, "Saved loadout '" .. name .. "'"
            .. (lo.source == "myslot" and " (from a Myslot string)" or "")
            .. (name ~= wanted and (" - '" .. wanted .. "' was already taken.") or "."), res

    elseif kind == "unitframes" then
        local ok, err = _G.ZacUF.ImportString(info.text)
        if not ok then return false, tostring(err or "the string could not be read"), res end
        res.reload = true
        return true, "Unit frames imported.", res

    elseif kind == "weakauras" then
        local ok, err = ns.Auras.ImportString(info.text)
        if not ok then return false, tostring(err or "the aura page could not take the string"), res end
        return true, "The string is in the Auras import box. Press Import there to see what the pack contains.", res

    elseif kind == "buffs" then
        local BR = BuffRemover()
        if not (BR and BR.ApplyImport) then return false, "Zacui_QoL is not loaded", res end
        local ok, msg = BR.ApplyImport(info.text, action.id)
        return ok and true or false, msg, res

    elseif kind == "readycheck" then
        local RC = _G.Readycheck
        if not (type(RC) == "table" and RC.ImportAny) then return false, "Readycheck is not loaded", res end
        local called, ok, msg, rres = pcall(RC.ImportAny, RC, info.text,
            { own = true, name = (name ~= "" and name or nil) })
        if not called then return false, tostring(ok), res end
        if type(rres) == "table" then
            res.reload = rres.reload and true or nil
            res.readycheck = rres
        end
        return ok and true or false, msg, res
    end

    return false, "that string cannot be imported", res
end

-- The importers belong to five different files and two addons. If one
-- of them throws, the box the string was pasted into must not go down
-- with it: the error comes back as the reason instead.
local function Run(text, actionId, opts)
    local called, ok, msg, res = pcall(RunUnguarded, text, actionId, opts)
    if not called then
        return false, "the import stopped on an error (" .. tostring(ok) .. ")", { kind = "error" }
    end
    -- Asked by Readycheck (opts.own), nobody else will redraw an open
    -- settings page to show what just arrived. The aura hand-over has
    -- already opened its own page.
    if ok and type(opts) == "table" and opts.own and type(res) == "table"
       and not res.reload and res.kind ~= "weakauras"
       and ns.ConfigIsOpen and ns.ConfigIsOpen() and ns.RefreshConfig then
        pcall(ns.RefreshConfig)
    end
    return ok, msg, res
end

-- shared with later ZacUI files, with the parts, and with Readycheck
-- (which reaches it as _G.ZacUI.Import)
ns.Import = {
    Clean = CleanPaste,
    PureLiteral = PureLiteral,
    Identify = Identify,
    Run = Run,
}
