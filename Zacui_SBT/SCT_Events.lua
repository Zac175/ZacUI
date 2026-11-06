-- SCT_Events - what happened, turned into lines of text.
-- Part of ZacUI (Zacui_SBT). Written for ZacUI.
--
-- The catalogue below is every kind of line the part can show: hits and
-- heals you take, the ones you deal, your pet's, and notices (combat,
-- killing blows, skill-ups, reputation...). Each has a default area,
-- colour and on/off; sct.events stores only what you changed.
--
-- Where the numbers come from:
--   Classic Era: the combat log, read once per event, nothing kept but
--     a short merge buffer.
--   WoW Classic Forever: there is no combat log there. Hits and heals
--     you take come from UNIT_COMBAT (the event the game's own floating
--     text uses); your own outgoing numbers are not available there yet.
--   Both: the notices that come from chat or from your own state
--     (combat, skill-ups, reputation, honor, money, loot).
local ns = _G.ZacUI
if not ns then return end
local S = ns.SBT
if not S then return end

local GetTime = GetTime
local UnitGUID = UnitGUID
local math_floor = math.floor
local string_format = string.format
local tostring, tonumber, type, pairs, ipairs = tostring, tonumber, type, pairs, ipairs

-- ============================================================
-- THE CATALOGUE
-- ============================================================
-- fmt: %a amount, %s ability, %n the other unit's name, %m miss word,
--      %x the spell interrupted/dispelled, %p power type
local EVENTS = {
    -- incoming
    { key = "in_hit",   cat = "in", label = "Melee hits you take",        area = "incoming", fmt = "-%a",  c = { 1, 0.25, 0.25 } },
    { key = "in_spell", cat = "in", label = "Ability hits you take",      area = "incoming", fmt = "-%a",  c = { 1, 0.25, 0.25 }, named = true },
    { key = "in_dot",   cat = "in", label = "Damage over time you take",  area = "incoming", fmt = "-%a",  c = { 1, 0.25, 0.25 }, named = true },
    { key = "in_env",   cat = "in", label = "Falling, fire, lava, drowning", area = "incoming", fmt = "-%a %s", c = { 1, 0.5, 0 } },
    { key = "in_miss",  cat = "in", label = "Attacks that miss you",      area = "incoming", fmt = "%m",   c = { 0.55, 0.6, 1 } },
    { key = "in_heal",  cat = "in", label = "Heals you get",              area = "incoming", fmt = "+%a",  c = { 0.1, 1, 0.1 },   named = true },
    { key = "in_hot",   cat = "in", label = "Heals over time you get",    area = "incoming", fmt = "+%a",  c = { 0.1, 1, 0.1 },   named = true },
    -- outgoing
    { key = "out_hit",   cat = "out", label = "Your melee and ranged swings", area = "outgoing", fmt = "%a", c = { 1, 1, 1 } },
    { key = "out_spell", cat = "out", label = "Your ability hits",          area = "outgoing", fmt = "%a",  c = { 1, 1, 0 },       named = true },
    { key = "out_dot",   cat = "out", label = "Your damage over time",      area = "outgoing", fmt = "%a",  c = { 1, 1, 0 },       named = true },
    { key = "out_miss",  cat = "out", label = "Your misses, dodges and parries", area = "outgoing", fmt = "%m", c = { 0.7, 0.7, 0.7 }, named = true },
    { key = "out_heal",  cat = "out", label = "Your heals on others",       area = "outgoing", fmt = "+%a", c = { 0.1, 1, 0.1 },   named = true },
    { key = "out_hot",   cat = "out", label = "Your heals over time on others", area = "outgoing", fmt = "+%a", c = { 0.1, 1, 0.1 }, named = true },
    { key = "out_interrupt", cat = "out", label = "Your interrupts",        area = "outgoing", fmt = "Interrupted %x", c = { 0.6, 0.8, 1 } },
    { key = "out_dispel",    cat = "out", label = "Your dispels",           area = "outgoing", fmt = "Dispelled %x",   c = { 0.6, 0.8, 1 } },
    -- pet
    { key = "pet_hit",  cat = "pet", label = "Your pet's hits",            area = "outgoing", fmt = "%a",   c = { 1, 0.6, 0.2 }, off = true, named = true },
    { key = "pet_miss", cat = "pet", label = "Your pet's misses",          area = "outgoing", fmt = "Pet %m", c = { 0.7, 0.7, 0.7 }, off = true },
    { key = "pet_in",   cat = "pet", label = "Hits your pet takes",        area = "incoming", fmt = "Pet -%a", c = { 1, 0.5, 0.2 }, off = true },
    { key = "pet_heal", cat = "pet", label = "Heals your pet gets",        area = "incoming", fmt = "Pet +%a", c = { 0.1, 0.8, 0.1 }, off = true },
    -- notices
    { key = "n_combat_in",  cat = "note", label = "Entering combat",       area = "notification", fmt = "+Combat", c = { 1, 1, 1 } },
    { key = "n_combat_out", cat = "note", label = "Leaving combat",        area = "notification", fmt = "-Combat", c = { 1, 1, 1 } },
    -- off unless ticked (Zac 2026-11-02: "why is there some killing blow text on my screen now")
    { key = "n_kb",         cat = "note", label = "Killing blows",         area = "notification", fmt = "Killing Blow: %n", c = { 1, 0.3, 0.3 }, size = 18, off = true },
    { key = "n_buff",       cat = "note", label = "Buffs you gain",        area = "notification", fmt = "[%s]",  c = { 0.7, 0.7, 1 }, off = true },
    { key = "n_buff_fade",  cat = "note", label = "Buffs that fade",       area = "notification", fmt = "-[%s]", c = { 0.7, 0.7, 1 }, off = true },
    { key = "n_debuff",     cat = "note", label = "Debuffs you get",       area = "notification", fmt = "[%s]",  c = { 1, 0.4, 0.4 }, off = true },
    { key = "n_debuff_fade", cat = "note", label = "Debuffs that fade",    area = "notification", fmt = "-[%s]", c = { 1, 0.4, 0.4 }, off = true },
    { key = "n_power",      cat = "note", label = "Rage, energy and mana gains", area = "notification", fmt = "+%a %p", c = { 0.4, 0.6, 1 }, off = true },
    { key = "n_extra",      cat = "note", label = "Extra attacks",         area = "notification", fmt = "+%a extra attack", c = { 1, 1, 1 }, off = true, size = 18 },
    { key = "n_cp_full",    cat = "note", label = "Combo points full",     area = "notification", fmt = "%a combo points", c = { 1, 0.8, 0.2 } },
    { key = "n_skill",      cat = "note", label = "Skill gains",           area = "notification", fmt = "%s: %a", c = { 0.4, 0.6, 1 } },
    { key = "n_rep",        cat = "note", label = "Reputation",            area = "notification", fmt = "%x %s", c = { 0.55, 0.55, 1 } },
    { key = "n_honor",      cat = "note", label = "Honor",                 area = "notification", fmt = "+%a Honor", c = { 0.9, 0.7, 0.2 } },
    { key = "n_xp",         cat = "note", label = "Experience",            area = "notification", fmt = "+%a XP", c = { 0.8, 0.5, 1 }, off = true },
    { key = "n_money",      cat = "note", label = "Money looted",          area = "notification", fmt = "+%s", c = { 1, 1, 0 }, off = true },
    { key = "n_loot",       cat = "note", label = "Items looted",          area = "notification", fmt = "+%s", c = { 1, 1, 1 }, off = true },
}
local BY_KEY = {}
for i, e in ipairs(EVENTS) do
    e.order = i
    BY_KEY[e.key] = e
end
S.EVENTS, S.EVENT_BY_KEY = EVENTS, BY_KEY
S.EVENT_CATS = {
    { key = "in",   label = "Hits and heals you take" },
    { key = "out",  label = "Hits and heals you deal" },
    { key = "pet",  label = "Your pet" },
    { key = "note", label = "Notices" },
}

-- ============================================================
-- AN EVENT'S SETTINGS: the catalogue with your changes over it
-- ============================================================
local function Own(key)
    local ev = S.Cfg().events[key]
    return type(ev) == "table" and ev or nil
end

function S.EventOn(key)
    local def, own = BY_KEY[key], Own(key)
    if not def then return false end
    if own and own.off ~= nil then return not own.off end
    return not def.off
end

function S.EventArea(key)
    local def, own = BY_KEY[key], Own(key)
    local area = own and own.area or (def and def.area) or "notification"
    if not S.Area(area) then area = def and def.area or "notification" end
    return area
end

function S.EventColor(key)
    local def, own = BY_KEY[key], Own(key)
    if own and own.r then return own.r, own.g, own.b end
    local c = def and def.c or { 1, 1, 1 }
    return c[1], c[2], c[3]
end

function S.EventSize(key)
    local def, own = BY_KEY[key], Own(key)
    return (own and tonumber(own.size)) or (def and def.size) or nil
end

function S.EventSound(key)
    local own = Own(key)
    return own and own.sound or nil
end

-- field = "off" | "area" | "color" | "size" | "sound"; value nil clears it
function S.SetEvent(key, field, value, g, b)
    if not BY_KEY[key] then return end
    local events = S.Cfg().events
    local own = events[key]
    if type(own) ~= "table" then
        own = {}
        events[key] = own
    end
    if field == "color" then
        if value == nil then own.r, own.g, own.b = nil, nil, nil
        else own.r, own.g, own.b = value, g, b end
    elseif field == "off" then
        local def = BY_KEY[key]
        if (value and true or false) == (def.off and true or false) then own.off = nil
        else own.off = value and true or false end
    else
        own[field] = value
    end
    if next(own) == nil then events[key] = nil end
end

function S.ResetEvent(key)
    S.Cfg().events[key] = nil
end

-- ============================================================
-- TEXT
-- ============================================================
-- THE NUMBERS' FORMAT (sct.formats.amount, ZacUI's text format: short /
-- comma / full, decimals, template over [value], before / after). Its
-- default is "Thousands with a comma"; nothing saved = the old fast path.
local NUM_DEF, NUM_V, NUM_K = { abbrev = "comma", decimals = 1 }, {}, { value = "number" }
local function Digits(n)
    local c = S.Cfg()
    local f = c.formats
    local spec = type(f) == "table" and f.amount or nil
    if type(spec) == "table" and ns.FormatText then
        NUM_DEF.abbrev = c.groupDigits and "comma" or "full"
        NUM_V.value = n
        return ns.FormatText(spec, NUM_DEF, NUM_V, NUM_K, "value")
    end
    local s = tostring(math_floor(n + 0.5))
    if not c.groupDigits or #s < 4 then return s end
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
S.Digits = Digits
function S.AmountFormatDefaults()
    return { abbrev = S.Cfg().groupDigits and "comma" or "full", decimals = 1 }
end

local initials = {}
local function ShortName(name)
    if type(name) ~= "string" then return "" end
    local c = S.Cfg()
    if not c.shortNames then return name end
    local done = initials[name]
    if done then return done end
    local out = {}
    for word in name:gmatch("[^%s%-]+") do
        local first = word:match("^[%z\1-\127\194-\244][\128-\191]*")
        if first then out[#out + 1] = first:upper() end
    end
    done = #out > 1 and table.concat(out) or name
    initials[name] = done
    return done
end

-- ABILITY NAMES' FORMAT (sct.formats.name, ZacUI's text format: longest,
-- cut mark, case, before / after) over the initials above; nothing saved =
-- the name as it was.
local NAME_DEF, NAME_V, NAME_K = {}, {}, { value = "name" }
local Initials = ShortName
ShortName = function(name)
    local done = Initials(name)
    local f = S.Cfg().formats
    local spec = type(f) == "table" and f.name or nil
    if type(spec) == "table" and ns.FormatText and done ~= "" then
        NAME_V.value = done
        return ns.FormatText(spec, NAME_DEF, NAME_V, NAME_K, "value")
    end
    return done
end
S.ShortName = ShortName

local MISS_WORD = {
    MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", DEFLECT = "Deflect",
    ABSORB = "Absorb", IMMUNE = "Immune", EVADE = "Evade", RESIST = "Resist", REFLECT = "Reflect",
}
S.MISS_WORD = MISS_WORD

local POWER_NAME = { [0] = "Mana", [1] = "Rage", [2] = "Focus", [3] = "Energy" }

-- lines whose %s is a name to show whole (an item, a faction, a skill,
-- an aura), not an ability to shorten
local PLAIN = { n_loot = true, n_money = true, n_skill = true, n_rep = true, n_buff = true,
    n_buff_fade = true, n_debuff = true, n_debuff_fade = true, in_env = true }

-- one event's line. f: amount, spell, name, miss, extra, power, partial
local function Build(def, f)
    local c = S.Cfg()
    local fmt = def.fmt
    local Name = PLAIN[def.key] and tostring or ShortName
    local text = fmt:gsub("%%(%a)", function(code)
        if code == "a" then return f.amount and Digits(f.amount) or "" end
        if code == "s" then return f.spell and Name(f.spell) or "" end
        if code == "n" then return f.name or "" end
        if code == "m" then return f.miss or "" end
        if code == "x" then return f.extra or "" end
        if code == "p" then return f.power or "" end
        return "%" .. code
    end)
    if def.named and c.names and f.spell and not fmt:find("%%s") then
        text = text .. " " .. Name(f.spell)
    end
    if f.count and f.count > 1 then
        text = text .. string_format(" |cffb0b0b0x%d|r", f.count)
    end
    if f.partial and c.partials then
        text = text .. " |cff9a9a9a" .. f.partial .. "|r"
    end
    return text
end
S.BuildText = Build

-- ============================================================
-- ICONS - the combat log on Classic Era carries no spell ids, so an
-- icon is looked up by name; that finds every spell you know.
-- ============================================================
local iconOf = {}
local function Icon(id, name)
    if id and id ~= 0 then
        local ok, t = pcall(GetSpellTexture, id)
        if ok and t then return t end
    end
    if type(name) ~= "string" then return nil end
    local t = iconOf[name]
    if t == nil then
        local ok, got = pcall(GetSpellTexture, name)
        t = ok and got or false
        iconOf[name] = t
    end
    return t or nil
end
S.Icon = Icon

-- ============================================================
-- SHOW
-- ============================================================
-- One event as a line: its area, its text and how it looks - or nil when
-- that event is off or the ability is on the never-shown list. The
-- settings preview draws its samples through this too.
local function Line(key, f)
    local def = BY_KEY[key]
    if not def or not S.EventOn(key) then return nil end
    local c = S.Cfg()
    if f.spell and c.hide[f.spell] then return nil end
    local r, g, b = S.EventColor(key)
    return S.EventArea(key), Build(def, f), {
        r = r, g = g, b = b,
        crit = f.crit,
        size = S.EventSize(key) or (f.small and math.max(8, (tonumber(c.size) or 10) - 1)) or nil,
        icon = f.icon,
        sound = S.EventSound(key), soundKey = key,
    }
end
S.EventLine = Line

local function Show(key, f)
    local area, text, o = Line(key, f)
    if area then S.Display(area, text, o) end
end
S.ShowEvent = Show

-- ============================================================
-- MERGING - one ability landing on several mobs at once (Whirlwind,
-- Cleave, a heal over time on the whole group) is one line with a count.
-- ============================================================
local MERGE_WINDOW = 0.3
local merge = {}          -- id -> pending
local mergeOrder = {}
local flushing = false

local function Flush()
    flushing = false
    local now = GetTime()
    local keep = {}
    for _, id in ipairs(mergeOrder) do
        local m = merge[id]
        if m then
            if now - m.t0 >= MERGE_WINDOW then
                merge[id] = nil
                Show(m.key, m)
            else
                keep[#keep + 1] = id
            end
        end
    end
    mergeOrder = keep
    if #mergeOrder > 0 then
        flushing = true
        C_Timer.After(0.1, Flush)
    end
end

local function Queue(key, f)
    if not S.Cfg().merge or not f.spell then
        Show(key, f)
        return
    end
    local id = key .. "\31" .. f.spell
    local m = merge[id]
    if m then
        m.amount = (m.amount or 0) + (f.amount or 0)
        m.count = m.count + 1
        if f.crit then m.crit = true end
        return
    end
    f.key, f.count, f.t0 = key, 1, GetTime()
    merge[id] = f
    mergeOrder[#mergeOrder + 1] = id
    if not flushing then
        flushing = true
        C_Timer.After(MERGE_WINDOW, Flush)
    end
end

-- ============================================================
-- WHO IS WHO
-- ============================================================
local me, pet

local function RefreshGUIDs()
    me = UnitGUID("player")
    pet = UnitGUID("pet")
end
S.RefreshGUIDs = RefreshGUIDs

local function Partial(resisted, blocked, absorbed, glancing, crushing)
    local bits
    local function add(s) bits = bits and (bits .. " " .. s) or s end
    if resisted and resisted > 0 then add("(" .. Digits(resisted) .. " resisted)") end
    if blocked and blocked > 0 then add("(" .. Digits(blocked) .. " blocked)") end
    if absorbed and absorbed > 0 then add("(" .. Digits(absorbed) .. " absorbed)") end
    if glancing then add("(glancing)") end
    if crushing then add("(crushing)") end
    return bits
end

-- ============================================================
-- THE COMBAT LOG (Classic Era)
-- ============================================================
local DAMAGE = { SPELL_DAMAGE = true, RANGE_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true,
    DAMAGE_SHIELD = true, DAMAGE_SPLIT = true }
local MISSED = { SPELL_MISSED = true, RANGE_MISSED = true, SPELL_PERIODIC_MISSED = true,
    DAMAGE_SHIELD_MISSED = true }
local HEALS = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }
local ENV_NAME = { FALLING = "Falling", DROWNING = "Drowning", FATIGUE = "Fatigue",
    FIRE = "Fire", LAVA = "Lava", SLIME = "Slime" }

local function Plate(kind, dGUID, amount, crit, icon)
    local PT = S.PlateText
    return PT and PT.Take and PT.Take(kind, dGUID, amount, crit, icon) or false
end

local function OnCombatLog()
    local _, sub, _, sGUID, sName, _, _, dGUID, dName, _, _, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 =
        CombatLogGetCurrentEventInfo()
    if not me then RefreshGUIDs() end
    local fromMe, toMe = sGUID == me, dGUID == me
    local fromPet, toPet = pet ~= nil and sGUID == pet, pet ~= nil and dGUID == pet

    local AL = S.Alerts
    if AL and AL.OnCombatLog and (fromMe or toMe or sub == "SPELL_AURA_APPLIED") then
        AL.OnCombatLog(sub, fromMe, toMe, sGUID, dGUID, dName, a1, a2, a3, a4, a5)
    end
    if not (fromMe or toMe or fromPet or toPet) then return end

    if sub == "SWING_DAMAGE" then
        -- amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing
        local amount = a1 or 0
        local f = { amount = amount, crit = a7, name = toMe and sName or dName,
            partial = Partial(a4, a5, a6, a8, a9) }
        if toMe then
            if amount >= (S.Cfg().damageMin or 0) then Show("in_hit", f) end
        elseif fromMe then
            if Plate("white", dGUID, amount, a7) then return end
            if amount >= (S.Cfg().damageMin or 0) then Show("out_hit", f) end
        elseif fromPet then
            Show("pet_hit", f)
        elseif toPet then
            Show("pet_in", f)
        end

    elseif DAMAGE[sub] then
        -- spellId, spellName, school, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing
        local amount = a4 or 0
        if amount < (S.Cfg().damageMin or 0) then return end
        local dot = sub == "SPELL_PERIODIC_DAMAGE"
        local icon = Icon(a1, a2)
        local f = { amount = amount, spell = a2, crit = a10, icon = icon, small = dot,
            name = toMe and sName or dName, partial = Partial(a7, a8, a9, a11, a12) }
        if toMe then
            Queue(dot and "in_dot" or "in_spell", f)
        elseif fromMe then
            if Plate(dot and "dot" or "hit", dGUID, amount, a10, icon) then return end
            Queue(dot and "out_dot" or "out_spell", f)
        elseif fromPet then
            Queue("pet_hit", f)
        elseif toPet then
            Show("pet_in", f)
        end

    elseif sub == "SWING_MISSED" then
        local word = MISS_WORD[a1] or a1
        if toMe then
            Show("in_miss", { miss = word })
        elseif fromMe then
            if Plate(word, dGUID) then return end
            Show("out_miss", { miss = word })
        elseif fromPet then
            Show("pet_miss", { miss = word })
        end

    elseif MISSED[sub] then
        -- spellId, spellName, school, missType
        local word = MISS_WORD[a4] or a4
        local icon = Icon(a1, a2)
        if toMe then
            Show("in_miss", { miss = word, spell = a2, icon = icon })
        elseif fromMe then
            if Plate(word, dGUID, nil, nil, icon) then return end
            Show("out_miss", { miss = word, spell = a2, icon = icon })
        elseif fromPet then
            Show("pet_miss", { miss = word, spell = a2, icon = icon })
        end

    elseif HEALS[sub] then
        -- spellId, spellName, school, amount, overhealing, absorbed, critical
        local c = S.Cfg()
        local amount = a4 or 0
        if not c.overheal then amount = amount - (a5 or 0) end
        if amount <= 0 or amount < (c.healMin or 0) then return end
        local hot = sub == "SPELL_PERIODIC_HEAL"
        local f = { amount = amount, spell = a2, crit = a7, icon = Icon(a1, a2), small = hot,
            name = toMe and sName or dName }
        if toMe then
            Queue(hot and "in_hot" or "in_heal", f)
        elseif fromMe then
            Queue(hot and "out_hot" or "out_heal", f)
        elseif toPet then
            Queue("pet_heal", f)
        end

    elseif sub == "ENVIRONMENTAL_DAMAGE" then
        if toMe then
            Show("in_env", { amount = a2 or 0, spell = ENV_NAME[a1] or tostring(a1) })
        end

    elseif sub == "SPELL_INTERRUPT" then
        if fromMe then Show("out_interrupt", { spell = a2, extra = a5, icon = Icon(a1, a2) }) end

    elseif sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN" then
        if fromMe then Show("out_dispel", { spell = a2, extra = a5, icon = Icon(a1, a2) }) end

    elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REMOVED" then
        if toMe then
            local applied = sub == "SPELL_AURA_APPLIED"
            local key
            if a4 == "BUFF" then key = applied and "n_buff" or "n_buff_fade"
            else key = applied and "n_debuff" or "n_debuff_fade" end
            Show(key, { spell = a2, icon = Icon(a1, a2) })
        end

    elseif sub == "SPELL_ENERGIZE" or sub == "SPELL_PERIODIC_ENERGIZE" then
        -- spellId, spellName, school, amount, overEnergize, powerType
        if toMe and (a4 or 0) > 0 then
            Show("n_power", { amount = a4, spell = a2, power = POWER_NAME[a6] or "", icon = Icon(a1, a2) })
        end

    elseif sub == "SPELL_EXTRA_ATTACKS" then
        if fromMe then Show("n_extra", { amount = a4 or 1, spell = a2, icon = Icon(a1, a2) }) end

    elseif sub == "PARTY_KILL" then
        if fromMe then Show("n_kb", { name = dName or "" }) end
    end
end

-- ============================================================
-- UNIT_COMBAT (WoW Classic Forever) - what you take
-- ============================================================
local secret = _G.issecretvalue
local UC_MISS = { DODGE = true, PARRY = true, MISS = true, BLOCK = true, ABSORB = true,
    RESIST = true, IMMUNE = true, EVADE = true, REFLECT = true, DEFLECT = true }

local function SecretLine(key, prefix, amount, crit)
    -- a number we may not read can still be shown: no sums, no
    -- thresholds, just the text
    if not S.EventOn(key) then return end
    local ok, text = pcall(function() return prefix .. amount end)
    if not ok then return end
    local r, g, b = S.EventColor(key)
    pcall(S.Display, S.EventArea(key), text, { r = r, g = g, b = b, crit = crit })
end

local function OnUnitCombat(unit, action, descriptor, amount)
    if unit ~= "player" then return end
    local crit = descriptor == "CRITICAL"
    local hidden = secret and (secret(amount) or secret(action))
    if hidden then
        if action == "WOUND" then SecretLine("in_hit", "-", amount, crit)
        elseif action == "HEAL" then SecretLine("in_heal", "+", amount, crit) end
        return
    end
    if action == "WOUND" then
        if (amount or 0) > 0 then Show("in_hit", { amount = amount, crit = crit }) end
    elseif action == "HEAL" then
        if (amount or 0) >= (S.Cfg().healMin or 0) then Show("in_heal", { amount = amount, crit = crit }) end
    elseif UC_MISS[action] then
        Show("in_miss", { miss = MISS_WORD[action] or action })
    elseif action == "ENERGIZE" then
        if (amount or 0) > 0 then Show("n_power", { amount = amount, power = "" }) end
    end
end

-- ============================================================
-- CHAT AND STATE
-- ============================================================
-- a game message like "Your skill in %s has increased to %d." as a
-- pattern that pulls out its pieces
local function Pattern(gs)
    if type(gs) ~= "string" then return nil end
    local p = gs:gsub("%%", "\1")
    p = p:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("\1%d?%$?s", "(.+)"):gsub("\1%d?%$?d", "(%%d+)"):gsub("\1", "%%%%")
    return "^" .. p .. "$"
end

local P = {}
local function Patterns()
    P.skill = Pattern(_G.SKILL_RANK_UP)
    P.repUp = Pattern(_G.FACTION_STANDING_INCREASED)
    P.repDown = Pattern(_G.FACTION_STANDING_DECREASED)
    P.loot = Pattern(_G.LOOT_ITEM_SELF)
    P.lootN = Pattern(_G.LOOT_ITEM_SELF_MULTIPLE)
end

local lastMoney
local function MoneyText(copper)
    local g, s, c = math_floor(copper / 10000), math_floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "|cffffd700g|r" end
    if s > 0 then out[#out + 1] = s .. "|cffc7c7cfs|r" end
    if c > 0 or #out == 0 then out[#out + 1] = c .. "|cffeda55fc|r" end
    return table.concat(out, " ")
end

local function FirstNumber(msg)
    local n = type(msg) == "string" and msg:match("(%d+)")
    return n and tonumber(n) or nil
end

local lastCP = 0
local function CheckCombo()
    if not (GetComboPoints and UnitExists("target")) then lastCP = 0 return end
    local ok, cp = pcall(GetComboPoints, "player", "target")
    cp = ok and tonumber(cp) or 0
    if cp >= 5 and lastCP < 5 then Show("n_cp_full", { amount = cp }) end
    lastCP = cp
end

-- ============================================================
-- EVENTS
-- ============================================================
local ev = CreateFrame("Frame")
local cleuOn = false

local function Arm()
    local on = S.IsOn()
    -- the combat log only exists on Classic Era; registering it on
    -- Forever is an error
    if not S.FOREVER then
        if on and not cleuOn then
            ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            cleuOn = true
        elseif not on and cleuOn then
            ev:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            cleuOn = false
        end
    else
        if on then ev:RegisterUnitEvent("UNIT_COMBAT", "player") else ev:UnregisterEvent("UNIT_COMBAT") end
    end
end
S.ArmEvents = Arm

ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "UNIT_COMBAT" then
        OnUnitCombat(...)
    elseif event == "PLAYER_REGEN_DISABLED" then
        Show("n_combat_in", {})
    elseif event == "PLAYER_REGEN_ENABLED" then
        Show("n_combat_out", {})
    elseif event == "UNIT_PET" then
        RefreshGUIDs()
    elseif event == "PLAYER_TARGET_CHANGED" then
        lastCP = 0
        CheckCombo()
    elseif event == "UNIT_POWER_UPDATE" then
        local unit, kind = ...
        if unit == "player" and kind == "COMBO_POINTS" then CheckCombo() end
    elseif event == "CHAT_MSG_SKILL" then
        local msg = ...
        local skill, rank
        if P.skill then skill, rank = msg:match(P.skill) end
        if skill then Show("n_skill", { spell = skill, amount = tonumber(rank) }) end
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        local msg = ...
        local faction, n
        if P.repUp then faction, n = msg:match(P.repUp) end
        local sign = "+"
        if not faction and P.repDown then
            faction, n = msg:match(P.repDown)
            sign = "-"
        end
        if faction and n then
            Show("n_rep", { extra = sign .. Digits(tonumber(n)), spell = faction })
        end
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        local n = FirstNumber(...)
        if n then Show("n_honor", { amount = n }) end
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        local n = FirstNumber(...)
        if n then Show("n_xp", { amount = n }) end
    elseif event == "PLAYER_MONEY" then
        local now = GetMoney()
        if lastMoney and now > lastMoney then
            Show("n_money", { spell = MoneyText(now - lastMoney) })
        end
        lastMoney = now
    elseif event == "CHAT_MSG_LOOT" then
        local msg = ...
        local item, n = nil, nil
        if P.lootN then item, n = msg:match(P.lootN) end
        if not item and P.loot then item = msg:match(P.loot) end
        if item then
            -- the item link keeps its own colour
            Show("n_loot", { spell = n and (item .. " x" .. n) or item })
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        RefreshGUIDs()
        Patterns()
        lastMoney = GetMoney and GetMoney() or nil
        for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_PET",
            "PLAYER_TARGET_CHANGED", "CHAT_MSG_SKILL", "CHAT_MSG_COMBAT_FACTION_CHANGE",
            "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_MONEY", "CHAT_MSG_LOOT" }) do
            pcall(self.RegisterEvent, self, e)
        end
        pcall(self.RegisterUnitEvent, self, "UNIT_POWER_UPDATE", "player")
        Arm()
        S.Rebuild()
    end
end)

-- A sample of one event, for the Events tab.
function S.TestEvent(key)
    local def = BY_KEY[key]
    if not def then return end
    local f = { amount = 1234, spell = "Heroic Strike", name = "Defias Bandit", miss = "Dodge",
        extra = "Fireball", power = "Rage", icon = 132282 }
    if def.cat == "note" then f.icon = nil end
    local r, g, b = S.EventColor(key)
    S.Display(S.EventArea(key), Build(def, f), { r = r, g = g, b = b, size = S.EventSize(key),
        icon = f.icon, sound = S.EventSound(key) })
end
