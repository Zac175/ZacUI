-- AE_Core - ZacUI's aura engine: the heart of it.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- The engine runs auras saved in the WeakAuras format: the same display
-- tables, the same import strings, the same names custom code calls
-- (WeakAuras.ScanEvents, aura_env, the trigger-state updater...). That
-- format is an interface many players and packs share; the engine that
-- reads it here is ZacUI's own.
--
-- What lives in this file:
--   * the engine table (ns.AuraEngine, E below) and the public table
--     custom code knows as WeakAuras
--   * the store: every saved display by id, its children, its region
--   * the event bus every other file subscribes to
--   * small shared helpers (copy, colours, time)
--
-- Saved variables: ZacUIAurasSaved.displays[id] = the display table,
-- exactly as imported. The engine never rewrites a display's fields in
-- place except through its own upgrade step (AE_Upgrade), so a display
-- exported again comes out as it went in.
local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local E = {}
ns.AuraEngine = E
E.addon = ADDON_NAME
-- Forever's rules for the combat log: that client, or ZacUI's game-version
-- override's Forever (Core_Flavor; only the combat log is switched off)
E.FOREVER = (_G.ZACUI_MODERN or (ns.NoCombatLog and ns.NoCombatLog())) and true or false

-- ============================================================
-- THE PUBLIC TABLE
-- ============================================================
-- Custom code in imported auras calls these by name. Only what auras
-- actually use is here; everything is ZacUI's implementation.
local WA = _G.WeakAuras
if type(WA) ~= "table" then
    WA = {}
    _G.WeakAuras = WA
end
E.WA = WA
WA.IsZacUIEngine = true

-- ============================================================
-- SMALL HELPERS
-- ============================================================
local function Copy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local t = {}
    seen[v] = t
    for k, x in pairs(v) do t[Copy(k, seen)] = Copy(x, seen) end
    return t
end
E.Copy = Copy

function E.Now() return GetTime() end

-- a WeakAuras colour is { r, g, b, a } by index
function E.Color(c, r, g, b, a)
    if type(c) == "table" then
        return c[1] or r or 1, c[2] or g or 1, c[3] or b or 1, c[4] or a or 1
    end
    return r or 1, g or 1, b or 1, a or 1
end

local errors = {}
E.errors = errors
-- an error in a display's own code: kept (latest few per display) and
-- said once, never thrown into the game's error frame twice a second
function E.Error(id, where, msg)
    local list = errors[id]
    if not list then
        list = {}
        errors[id] = list
    end
    local key = where .. ": " .. tostring(msg)
    for _, e in ipairs(list) do if e == key then return end end
    list[#list + 1] = key
    if #list > 5 then table.remove(list, 1) end
    if E.Debug then E.Debug("error in " .. tostring(id) .. " (" .. key .. ")") end
end

function E.Debug(msg)
    if E.verbose and ns.Print then ns.Print("|cff9999ffauras|r " .. tostring(msg)) end
end

-- ============================================================
-- THE STORE
-- ============================================================
E.data = {}          -- id -> display table (the saved one)
E.children = {}      -- id -> { child ids in order }
E.regions = {}       -- id -> region (the main one; clones live in E.clones)
E.clones = {}        -- id -> { cloneId -> region }
E.loaded = {}        -- id -> true while its load conditions hold

function E.Saved()
    if type(_G.ZacUIAurasSaved) ~= "table" then _G.ZacUIAurasSaved = {} end
    local sv = _G.ZacUIAurasSaved
    if type(sv.displays) ~= "table" then sv.displays = {} end
    return sv
end

function E.GetData(id)
    return E.data[id]
end
WA.GetData = function(id) return E.data[id] end

-- the display's top group, and every display under a group (depth first,
-- in the group's own order)
function E.Root(id)
    local d, guard = E.data[id], 0
    while d and d.parent and E.data[d.parent] and guard < 50 do
        id = d.parent
        d = E.data[id]
        guard = guard + 1
    end
    return id
end

function E.Descendants(id, out)
    out = out or {}
    for _, child in ipairs(E.children[id] or {}) do
        out[#out + 1] = child
        E.Descendants(child, out)
    end
    return out
end

function E.IsGroup(d)
    return d and (d.regionType == "group" or d.regionType == "dynamicgroup")
end

-- builds E.data / E.children from the saved table
function E.ReadSaved()
    local sv = E.Saved()
    wipe(E.data)
    wipe(E.children)
    for id, d in pairs(sv.displays) do
        if type(d) == "table" then
            d.id = d.id or id
            E.data[id] = d
        end
    end
    for id, d in pairs(E.data) do
        if E.IsGroup(d) and type(d.controlledChildren) == "table" then
            local list = {}
            for _, c in ipairs(d.controlledChildren) do
                if E.data[c] then list[#list + 1] = c end
            end
            E.children[id] = list
        end
    end
    -- a child whose parent forgot it is still shown under it
    for id, d in pairs(E.data) do
        local p = d.parent
        if p and E.data[p] then
            local list = E.children[p]
            if not list then
                list = {}
                E.children[p] = list
            end
            local found = false
            for _, c in ipairs(list) do if c == id then found = true break end end
            if not found then list[#list + 1] = id end
        end
    end
end

-- ============================================================
-- THE EVENT BUS
-- ============================================================
-- One frame for every game event the engine listens to. Subscribers
-- are functions; a key lets one owner (a trigger, a display) replace or
-- drop its own subscription without knowing the others.
local bus = CreateFrame("Frame")
local subs = {}          -- event -> { key -> fn }
local lists = {}         -- event -> { { key, fn }, ... } (rebuilt on change)
local counts = {}        -- event -> number of subscribers
local unitSubs = {}      -- "UNIT_AURA" etc. registered as plain events too

local CUSTOM_PREFIXES = { "WA_", "ZUI_", "ZACUI_" }
local function IsCustom(event)
    if type(event) ~= "string" then return true end
    for _, p in ipairs(CUSTOM_PREFIXES) do
        if event:sub(1, #p) == p then return true end
    end
    -- anything with a colon or lowercase letters is not a game event
    if event:find("[a-z:]") then return true end
    return false
end
E.IsCustomEvent = IsCustom

-- events the game would refuse (or that do not exist on this client)
local BLOCKED = {}
if E.FOREVER then BLOCKED.COMBAT_LOG_EVENT_UNFILTERED = true end

function E.On(event, key, fn)
    if not event or not key or not fn then return end
    local t = subs[event]
    if not t then
        t = {}
        subs[event] = t
        counts[event] = 0
    end
    if not t[key] then counts[event] = counts[event] + 1 end
    t[key] = fn
    lists[event] = nil
    if counts[event] == 1 and not IsCustom(event) and not BLOCKED[event] then
        pcall(bus.RegisterEvent, bus, event)
    end
end

function E.Off(event, key)
    local t = subs[event]
    if not t or not t[key] then return end
    t[key] = nil
    lists[event] = nil
    counts[event] = counts[event] - 1
    if counts[event] <= 0 then
        counts[event] = 0
        if not IsCustom(event) then pcall(bus.UnregisterEvent, bus, event) end
    end
end

-- each event's subscribers as a list, rebuilt only when they change, so a
-- handler that subscribes or unsubscribes (or raises another event) while
-- one is being delivered never disturbs the loop
local function List(event)
    local l = lists[event]
    if l then return l end
    l = {}
    for key, fn in pairs(subs[event] or {}) do l[#l + 1] = { key, fn } end
    lists[event] = l
    return l
end

local function Dispatch(event, ...)
    if not subs[event] then return end
    local l = List(event)
    for i = 1, #l do
        local e = l[i]
        local ok, err = pcall(e[2], event, ...)
        if not ok then E.Error(tostring(e[1]), event, err) end
    end
end
E.Dispatch = Dispatch

bus:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        Dispatch(event, CombatLogGetCurrentEventInfo())
    else
        Dispatch(event, ...)
    end
end)

-- WeakAuras.ScanEvents: custom code raising its own events for other
-- auras' custom triggers (and the engine's own "WA_" events)
WA.ScanEvents = function(event, ...)
    Dispatch(event, ...)
end

-- ============================================================
-- THE PLAYER
-- ============================================================
WA.me = UnitName and UnitName("player") or nil
WA.myGUID = UnitGUID and UnitGUID("player") or nil
E.On("PLAYER_LOGIN", "core.me", function()
    WA.me = UnitName("player")
    WA.myGUID = UnitGUID("player")
end)

-- the options window is ZacUI's config; custom code asks this to skip
-- work (or show samples) while it is open
WA.IsOptionsOpen = function()
    return E.optionsOpen and true or false
end

-- ============================================================
-- COLOURS: a colour part way between two, through hue (what packs use
-- to go green -> yellow -> red as something runs out)
-- ============================================================
local function RGBtoHSV(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local h, s, v = 0, 0, mx
    local d = mx - mn
    if mx > 0 then s = d / mx end
    if d > 0 then
        if mx == r then h = (g - b) / d % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, s, v
end

local function HSVtoRGB(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    end
    return v, p, q
end
E.RGBtoHSV, E.HSVtoRGB = RGBtoHSV, HSVtoRGB

WA.GetHSVTransition = function(perc, r1, g1, b1, a1, r2, g2, b2, a2)
    perc = math.max(0, math.min(1, tonumber(perc) or 0))
    local h1, s1, v1 = RGBtoHSV(r1 or 0, g1 or 0, b1 or 0)
    local h2, s2, v2 = RGBtoHSV(r2 or 0, g2 or 0, b2 or 0)
    -- the short way round the hue circle
    local dh = h2 - h1
    if dh > 0.5 then dh = dh - 1 elseif dh < -0.5 then dh = dh + 1 end
    local h = (h1 + dh * perc) % 1
    local r, g, b = HSVtoRGB(h, s1 + (s2 - s1) * perc, v1 + (v2 - v1) * perc)
    return r, g, b, (a1 or 1) + ((a2 or 1) - (a1 or 1)) * perc
end

-- ============================================================
-- RANGE (what the "In Range" style auras ask)
-- ============================================================
-- Classic Era answers distances only in bands: an item or a spell with
-- a known range either reaches the unit or does not. CheckInteractDistance
-- gives 10 (inspect/trade 11), 28 (follow) yards; beyond that only "out".
local function Bands(unit)
    if not (UnitExists and UnitExists(unit)) then return nil, nil end
    if CheckInteractDistance then
        local ok3 = select(2, pcall(CheckInteractDistance, unit, 3))
        if ok3 then return 0, 10 end
        local ok4 = select(2, pcall(CheckInteractDistance, unit, 4))
        if ok4 then return 10, 28 end
    end
    return 28, nil
end

WA.GetRange = function(unit)
    return Bands(unit)
end

-- op: "<=" (default) or ">="; true when the unit is within (or beyond)
-- `range` yards as far as the bands can tell
WA.CheckRange = function(unit, range, op)
    local minR, maxR = Bands(unit)
    if not minR then return false end
    range = tonumber(range) or 0
    if op == ">=" then return minR >= range end
    return (maxR or math.huge) <= range
end

-- ============================================================
-- GROUP AND AURA HELPERS custom code calls as globals
-- ============================================================
-- WA_IterateGroupMembers(reversed, forceParty): every unit in your group,
-- you included (raid1..raidN in a raid; player, party1..4 otherwise)
if _G.WA_IterateGroupMembers == nil then
    _G.WA_IterateGroupMembers = function(reversed, forceParty)
        local units = {}
        if IsInRaid and IsInRaid() and not forceParty then
            for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
        else
            units[1] = "player"
            for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or math.max(0, GetNumGroupMembers() - 1)) do
                units[#units + 1] = "party" .. i
            end
        end
        local i, step, last = 0, 1, #units
        if reversed then i, step, last = #units + 1, -1, 1 end
        return function()
            i = i + step
            if (step > 0 and i > #units) or (step < 0 and i < 1) then return nil end
            return units[i]
        end
    end
end

-- WA_GetUnitBuff(unit, spell, filter): the first aura on the unit whose
-- name or spell id is `spell`, with the same returns as UnitAura
local function FindAura(unit, spell, filter)
    if not (UnitAura and unit and spell) then return nil end
    for i = 1, 40 do
        local r = { UnitAura(unit, i, filter) }
        if not r[1] then return nil end
        if r[1] == spell or r[10] == spell then return unpack(r) end
    end
    return nil
end
if _G.WA_GetUnitAura == nil then _G.WA_GetUnitAura = FindAura end
if _G.WA_GetUnitBuff == nil then
    _G.WA_GetUnitBuff = function(unit, spell, filter)
        return FindAura(unit, spell, "HELPFUL" .. (filter and ("|" .. filter) or ""))
    end
end
if _G.WA_GetUnitDebuff == nil then
    _G.WA_GetUnitDebuff = function(unit, spell, filter)
        return FindAura(unit, spell, "HARMFUL" .. (filter and ("|" .. filter) or ""))
    end
end

-- ============================================================
-- STARTUP ORDER
-- ============================================================
-- Other files add themselves to these lists; PLAYER_LOGIN runs them in
-- order once the saved variables are there.
E.onLogin = {}
function E.AtLogin(fn) E.onLogin[#E.onLogin + 1] = fn end

E.On("PLAYER_LOGIN", "core.start", function()
    E.ReadSaved()
    for _, fn in ipairs(E.onLogin) do
        local ok, err = pcall(fn)
        if not ok then E.Error("engine", "startup", err) end
    end
    E.started = true
end)
