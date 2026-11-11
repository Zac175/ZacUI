-- Core_AuraFilter - ONE FILTER for every place ZacUI lists buffs or
-- debuffs (2026-11-10, Zac: "a filtering system ... crazy customization
-- without being over complicated"; the mock he approved).
-- Part of ZacUI; load order is set by the TOC (after Core_Flavor).
--
-- A PLACE is one list of auras on screen: the debuff strip over a
-- nameplate, a unit frame's debuffs, a HUD row. Each place has one saved
-- filter (ZacUIDB.auraFilters[place]) with the same four parts:
--
--   preset   what shows before your lists have a say
--              mine       only what you put there
--              important  yours, plus the raid debuffs that matter on this
--                         game version (AF.IMPORTANT)
--              dispel     what you could take off / what has a dispel type
--              all        everything
--              none       nothing but your Always list
--   always   names (or spell ids) that show whatever the preset says, and
--            are pinned in front
--   never    names (or spell ids) that never show; wins over everything
--   adv      onlyMine, minDur, maxDur (seconds, 0 = any), combatOnly,
--            bossOnly, minStacks (0 = any), sort, max (icons), pinnedFirst
--
-- A place registers itself once (AF.Register) with its label, its default
-- preset and how to refresh what it draws; a place that had settings of
-- its own before this file passes migrate(cfg), run the first time its
-- filter is read, so nobody's list changes on update.
--
-- THE AURA a place asks about is a plain table:
--   name, spellId, duration, expirationTime, count,
--   mine (true when you put it there), dispel (its dispel type or true),
--   hidden (WoW Forever / Retail in a fight: the game gives no name)
-- A hidden aura cannot be matched by name, so the lists and "important"
-- pass it by: it shows under every preset but "none" (and under "mine"
-- only when the game still says it is yours). The panel says so.
--
-- Nothing here runs on an event: a place calls AF.Pass / AF.Sorted from
-- its own (already throttled) update.

local ADDON_NAME, ns = ...
ns = ns or _G.ZacUI
if not ns then return end

local AF = {}
ns.AuraFilter = AF

AF.PRESETS = {
    { value = "mine", text = "Mine only", desc = "Only what you put there." },
    { value = "important", text = "Important",
      desc = "Yours, plus the raid debuffs that matter on this game version (Sunder, the curses, Faerie Fire ...)." },
    { value = "dispel", text = "Dispellable", desc = "Only what has a dispel type (magic, curse, poison, disease)." },
    { value = "all", text = "Everything", desc = "Every one of them, up to the icon limit." },
    { value = "none", text = "Nothing", desc = "Only what is on your Always show list." },
}
AF.SORTS = {
    { value = "game", text = "The game's order" },
    { value = "left", text = "Time left" },
    { value = "dur", text = "Duration" },
    { value = "name", text = "Name" },
}

-- ============================================================
-- THE RAID DEBUFFS THAT MATTER, per game version (names, lower case)
-- ============================================================
-- English names: on another client language "Important" still shows
-- yours, and the Always list takes any name or spell id.
local IMPORTANT_ERA = {
    "sunder armor", "expose armor", "faerie fire", "faerie fire (feral)", "curse of recklessness",
    "curse of the elements", "curse of shadow", "curse of weakness", "curse of tongues", "demoralizing shout",
    "demoralizing roar", "thunder clap", "hunter's mark", "winter's chill", "fire vulnerability",
    "shadow weaving", "shadow vulnerability", "mortal strike", "gift of arthas", "spell vulnerability",
    "stormstrike", "judgement of wisdom", "judgement of light", "judgement of the crusader", "screech",
    "scorpid sting", "armor shatter", "puncture armor", "thunderfury", "annihilator",
}
local IMPORTANT_TBC = {
    "sunder armor", "expose armor", "faerie fire", "faerie fire (feral)", "curse of recklessness",
    "curse of the elements", "curse of weakness", "curse of tongues", "demoralizing shout",
    "demoralizing roar", "thunder clap", "hunter's mark", "winter's chill", "fire vulnerability",
    "shadow weaving", "shadow vulnerability", "mortal strike", "gift of arthas", "stormstrike",
    "judgement of wisdom", "judgement of light", "judgement of the crusader", "misery", "blood frenzy",
    "expose weakness", "improved scorch", "mangle (bear)", "mangle (cat)", "insect swarm", "scorpid sting",
    "screech", "improved hunter's mark", "wound poison", "hemorrhage",
}
local function Set(list)
    local t = {}
    for _, n in ipairs(list) do t[n] = true end
    return t
end
AF.IMPORTANT = { era = Set(IMPORTANT_ERA), tbc = Set(IMPORTANT_TBC), forever = Set(IMPORTANT_ERA), retail = {} }

local function Flavor() return (ns.Flavor and ns.Flavor()) or "era" end

-- a game version that hides aura names from addons in a fight
function AF.HidesNames()
    local fl = Flavor()
    return fl == "forever" or fl == "retail"
end

-- ============================================================
-- PLACES AND THEIR SAVED FILTERS
-- ============================================================
local places, order = {}, {}
local ADV_DEF = { onlyMine = false, minDur = 0, maxDur = 0, combatOnly = false, bossOnly = false,
    minStacks = 0, sort = "game", max = 8, pinnedFirst = true }
AF.ADV_DEF = ADV_DEF

-- def: label (what the panel's picker calls it), kind ("debuff" | "buff"),
-- preset (default), max (default icon limit), refresh() (redraw the
-- place), migrate(cfg) (optional: fill a new filter from old settings),
-- noSort (the place draws in the game's order: no sort or pin-first
-- settings), noBoss (it has no "bosses and elites" to tell apart)
function AF.Register(place, def)
    if not places[place] then order[#order + 1] = place end
    places[place] = def or {}
end
function AF.Places()
    local out = {}
    for _, p in ipairs(order) do out[#out + 1] = { value = p, text = places[p].label or p } end
    return out
end
function AF.Def(place) return places[place] end

local function Store()
    if not ZacUIDB then return {} end
    ZacUIDB.auraFilters = ZacUIDB.auraFilters or {}
    return ZacUIDB.auraFilters
end

local stamp = 0          -- bumped on every change: places cache against it
function AF.Stamp() return stamp end

-- NOTHING IS SAVED BY LOOKING. A place that has never had its filter
-- changed keeps it here, not in the saved table: drawing a nameplate or
-- opening a settings page writes nothing. The first change (AF.Changed)
-- moves it into ZacUIDB.auraFilters.
local unsaved = {}
function AF.Forget() for k in pairs(unsaved) do unsaved[k] = nil end end

function AF.Get(place)
    local s = ZacUIDB and ZacUIDB.auraFilters
    local c = type(s) == "table" and s[place] or nil
    local def = places[place] or {}
    if type(c) ~= "table" then
        c = unsaved[place]
        if not c then
            c = {}
            unsaved[place] = c
        end
    end
    if c._v == nil then
        c._v = 1
        c.preset = c.preset or def.preset or "mine"
        c.always, c.never = c.always or {}, c.never or {}
        c.adv = c.adv or {}
        if def.max and c.adv.max == nil then c.adv.max = def.max end
        if def.migrate then pcall(def.migrate, c) end
    end
    c.always, c.never, c.adv = c.always or {}, c.never or {}, c.adv or {}
    for k, v in pairs(ADV_DEF) do if c.adv[k] == nil then c.adv[k] = v end end
    return c
end

function AF.Changed(place)
    stamp = stamp + 1
    -- the first change: the filter is saved from here on
    if unsaved[place] then
        local s = Store()
        if type(s[place]) ~= "table" then s[place] = unsaved[place] end
        unsaved[place] = nil
    end
    local def = places[place]
    if def and def.refresh then pcall(def.refresh) end
    if ns.SettingsChanged then pcall(ns.SettingsChanged, "aurafilter." .. tostring(place)) end
end

-- a list entry's key: a spell id as "#123", else the name in lower case
local function Key(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local id = tonumber(text)
    if id then
        local name
        if C_Spell and C_Spell.GetSpellName then
            local ok, n = pcall(C_Spell.GetSpellName, id)
            if ok and type(n) == "string" then name = n end
        elseif GetSpellInfo then
            local ok, n = pcall(GetSpellInfo, id)
            if ok and type(n) == "string" then name = n end
        end
        -- a known id is kept by its name too, so either spelling matches
        return "#" .. id, name or ("Spell " .. id), name and name:lower() or nil
    end
    return text:lower(), text
end
AF.Key = Key

-- which: "always" | "never". Returns true when it was added.
function AF.Add(place, which, text)
    local key, label, also = Key(text)
    if not key then return false end
    local c = AF.Get(place)
    local other = which == "always" and "never" or "always"
    c[which][key] = label
    c[other][key] = nil
    if also then c[other][also] = nil end
    AF.Changed(place)
    return true
end
function AF.Remove(place, which, key)
    local c = AF.Get(place)
    c[which][key] = nil
    AF.Changed(place)
end
-- the list's entries, sorted by what they show as: { key, label }
function AF.List(place, which)
    local out = {}
    for k, label in pairs(AF.Get(place)[which]) do out[#out + 1] = { key = k, label = label } end
    table.sort(out, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)
    return out
end

local function InList(list, a)
    if next(list) == nil then return false end
    if a.spellId and list["#" .. tostring(a.spellId)] then return true end
    local n = a.name
    if type(n) == "string" then
        local l = n:lower()
        if list[l] then return true end
        -- an entry added by id is kept under "#id" with its name as the label
        for k, label in pairs(list) do
            if k:sub(1, 1) == "#" and type(label) == "string" and label:lower() == l then return true end
        end
    end
    return false
end

-- ============================================================
-- THE VERDICT
-- ============================================================
-- ctx (optional): inCombat, boss (the unit is a boss or an elite).
-- Returns show, pinned.
-- SEEN LATELY: the names a place was asked about this session, newest
-- last (the panel offers them for the two lists, so nothing has to be
-- typed). In memory only; SEEN_MAX a place.
local SEEN_MAX = 40
local seen = {}
local function Note(place, a)
    local n = a.name
    if type(n) ~= "string" or n == "" then return end
    local s = seen[place]
    if not s then s = { order = {}, id = {} } seen[place] = s end
    if s.id[n] ~= nil then return end
    s.id[n] = a.spellId or false
    local o = s.order
    o[#o + 1] = n
    if #o > SEEN_MAX then s.id[table.remove(o, 1)] = nil end
end
-- newest first: { { name =, spellId = }, ... }, those on a list left out
function AF.Seen(place)
    local out = {}
    local s = seen[place]
    if not s then return out end
    local c = AF.Get(place)
    for i = #s.order, 1, -1 do
        local n = s.order[i]
        local id = s.id[n]
        local k = n:lower()
        local kid = id and ("#" .. tostring(id)) or nil
        if not (c.always[k] or c.never[k] or (kid and (c.always[kid] or c.never[kid]))) then
            out[#out + 1] = { name = n, spellId = id or nil }
        end
    end
    return out
end
function AF.ForgetSeen() for k in pairs(seen) do seen[k] = nil end end

function AF.Pass(place, a, ctx)
    local c = AF.Get(place)
    local adv = c.adv
    if not a.hidden and not (ctx and ctx.sample) then Note(place, a) end
    if a.hidden then
        -- no name to judge by: every preset but "none" lets it through
        if c.preset == "none" then return false end
        if (c.preset == "mine" or adv.onlyMine) and a.mine == false then return false end
    else
        if InList(c.never, a) then return false end
        -- (Advanced > Only mine is strict: it holds for the Always list too)
        if InList(c.always, a) and not (adv.onlyMine and not a.mine) then return true, true end
        local p = c.preset
        if p == "none" then return false
        elseif p == "mine" then if not a.mine then return false end
        elseif p == "important" then
            if not a.mine then
                local n = type(a.name) == "string" and a.name:lower()
                local set = AF.IMPORTANT[Flavor()] or AF.IMPORTANT.era
                if not (n and set[n]) then return false end
            end
        elseif p == "dispel" then if not a.dispel then return false end
        end
        if adv.onlyMine and not a.mine then return false end
        local dur = tonumber(a.duration) or 0
        if (adv.minDur or 0) > 0 and dur > 0 and dur < adv.minDur then return false end
        -- (no duration = it never runs out: longer than any limit)
        if (adv.maxDur or 0) > 0 and (dur <= 0 or dur > adv.maxDur) then return false end
        if (adv.minStacks or 0) > 1 and (tonumber(a.count) or 0) < adv.minStacks then return false end
    end
    if adv.combatOnly and ctx and ctx.inCombat == false then return false end
    if adv.bossOnly and ctx and ctx.boss == false then return false end
    return true, false
end

-- True when nothing but your own can show at this place (Mine only, or
-- Advanced > Only mine, with nobody else's on the Always list): the place
-- may then ask the game for yours alone, which is cheaper and is what the
-- game itself calls yours.
function AF.OnlyMine(place)
    local c = AF.Get(place)
    return c.adv.onlyMine or (c.preset == "mine" and next(c.always) == nil)
end

-- Orders `list` (aura tables that passed, each with .pinned set by the
-- caller from AF.Pass) in place and trims it to the icon limit.
function AF.Arrange(place, list)
    local adv = AF.Get(place).adv
    local sort = adv.sort or "game"
    for i, a in ipairs(list) do a._i = i end
    local now = GetTime and GetTime() or 0
    local function Left(a)
        local e = tonumber(a.expirationTime) or 0
        if e <= 0 or a.hidden then return math.huge end
        return e - now
    end
    table.sort(list, function(x, y)
        if adv.pinnedFirst ~= false and (x.pinned and true or false) ~= (y.pinned and true or false) then
            return x.pinned and true or false
        end
        if sort == "left" then
            local lx, ly = Left(x), Left(y)
            if lx ~= ly then return lx < ly end
        elseif sort == "dur" then
            local dx, dy = tonumber(x.duration) or 0, tonumber(y.duration) or 0
            if x.hidden then dx = 0 end
            if y.hidden then dy = 0 end
            if dx ~= dy then return dx < dy end
        elseif sort == "name" then
            local nx = (not x.hidden and type(x.name) == "string") and x.name:lower() or "~"
            local ny = (not y.hidden and type(y.name) == "string") and y.name:lower() or "~"
            if nx ~= ny then return nx < ny end
        end
        return x._i < y._i
    end)
    local max = math.max(1, tonumber(adv.max) or 8)
    for i = #list, max + 1, -1 do list[i] = nil end
    return list
end

-- copy one place's filter onto another (its lists and everything)
function AF.Copy(from, to)
    if from == to or not (places[from] and places[to]) then return false end
    local src = AF.Get(from)
    local dst = { _v = 1, preset = src.preset, always = {}, never = {}, adv = {} }
    for k, v in pairs(src.always) do dst.always[k] = v end
    for k, v in pairs(src.never) do dst.never[k] = v end
    for k, v in pairs(src.adv) do dst.adv[k] = v end
    unsaved[to] = nil
    Store()[to] = dst
    AF.Changed(to)
    return true
end

-- back to the place's own defaults (a fresh install's filter)
function AF.Reset(place)
    local def = places[place] or {}
    unsaved[place] = nil
    Store()[place] = { _v = 1, preset = def.preset or "mine", always = {}, never = {},
        adv = { max = def.max } }
    AF.Changed(place)
end
