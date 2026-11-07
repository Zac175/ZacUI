-- Meter_Data - constants and pure functions for the damage meter: class
-- and spec icons, the spec-from-spell table, number formatting and the
-- threat gradient. No frames, no state - everything here is data.
-- Part of ZacUI; load order is set by the TOC.
--
-- The icons are the game's own: class icons from the client's class
-- circle sheet (CLASS_ICON_TCOORDS), spec icons from the icon of each
-- spec's defining talent, so nothing here ships an icon sheet.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local MEDIA = ns.MEDIA

local Meter = {}

Meter.TEX_CLASSES = "Interface\\TargetingFrame\\UI-Classes-Circles"
Meter.TEX_TOOLBAR = MEDIA .. "Textures\\toolbar"
Meter.TEX_BAR     = "Interface\\AddOns\\ZacUI\\Media\\Textures\\bar_fade_left"
Meter.TEX_BAR_BG  = "Interface\\AddOns\\ZacUI\\Media\\Textures\\bar_flat"
Meter.FONT        = "Interface\\AddOns\\ZacUI\\Media\\Fonts\\RedHatDisplay-SemiBold.ttf"

-- The meter's own font and texture, as SharedMedia names in
-- ZacUIDB.meter.font / .bar, written by the Fonts & Textures page's push.
-- Unset, the profile's files above are used - the look he imported.
local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end
function Meter.FontPath()
    -- one font: ZacUI's, whenever one is chosen (the meter's own counts
    -- only while ZacUI has none)
    local one = ns.OneFace and ns.OneFace()
    if one then return one end
    local d = ZacUIDB and ZacUIDB.meter
    local n = d and d.font
    n = ns.NewMediaName and ns.NewMediaName(n) or n
    local lsm = LSM()
    if n and n ~= "" and lsm then
        local p = lsm:Fetch("font", n, true)
        if p then return p end
    end
    return Meter.FONT
end
-- Any statusbar name the meter saves (bar, row background, title bar):
-- SharedMedia first, then ZacUI's own list, then a file path as-is;
-- unset or unknown, `default`.
function Meter.TexPath(n, default)
    if n and n ~= "" then
        n = ns.NewMediaName and ns.NewMediaName(n) or n
        local lsm = LSM()
        if lsm then
            local p = lsm:Fetch("statusbar", n, true)
            if p then return p end
        end
        for _, b in ipairs(ns.MEDIA_BARS or {}) do
            if b.name == n then return b.path end
        end
        if n:find("\\", 1, true) or n:find("/", 1, true) then return n end
    end
    return default
end
function Meter.BarPath()
    local d = ZacUIDB and ZacUIDB.meter
    return Meter.TexPath(d and d.bar, Meter.TEX_BAR)
end

-- ============================================================
-- CLASS COLORS - the profile's table, not RAID_CLASS_COLORS.
-- SELF is the deep red his own bar wears (use_self_color = true).
-- ============================================================
Meter.CLASS_COLORS = {
    WARRIOR = { 0.78, 0.61, 0.43 },
    ROGUE   = { 1.00, 0.96, 0.41 },
    MAGE    = { 0.41, 0.80, 0.94 },
    PRIEST  = { 1.00, 1.00, 1.00 },
    WARLOCK = { 0.58, 0.51, 0.79 },
    HUNTER  = { 0.67, 0.83, 0.45 },
    DRUID   = { 1.00, 0.49, 0.04 },
    SHAMAN  = { 0.00, 0.44, 0.87 },
    PALADIN = { 0.96, 0.55, 0.73 },
    SELF    = { 0.8901961445808411, 0.02352941408753395, 0 },
    PET     = { 0.30, 0.40, 0.50 },
    NEUTRAL = { 1.00, 1.00, 0.00 },
    ENEMY   = { 0.94117, 0, 0.0196 },
    UNKNOW  = { 0.20, 0.20, 0.20 },
    UNGROUPPLAYER = { 0.40, 0.40, 0.40 },
}

-- ============================================================
-- CLASS ICONS - the client's class circles; a pet, an enemy and anyone
-- unknown get a game icon of their own.
-- ============================================================
local OTHER_ICONS = {
    PET           = "Interface\\Icons\\Ability_Hunter_BeastCall",
    ENEMY         = "Interface\\Icons\\Ability_Creature_Cursed_02",
    UNKNOW        = "Interface\\Icons\\INV_Misc_QuestionMark",
    UNGROUPPLAYER = "Interface\\Icons\\INV_Misc_QuestionMark",
}
-- texture, left, right, top, bottom for a class token (or one of the above)
function Meter.ClassIcon(class)
    local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if c then return Meter.TEX_CLASSES, c[1], c[2], c[3], c[4] end
    return OTHER_ICONS[class] or OTHER_ICONS.UNKNOW, 0.08, 0.92, 0.08, 0.92
end

-- ============================================================
-- SPEC ICONS - each spec shown by the icon of its defining talent,
-- read from the game (so the client's own art, at any resolution).
-- The keys are the usual spec numbers, kept so a saved actor's spec
-- still means the same thing.
-- ============================================================
local SPEC_ICON_SPELL = {
    [71] = 12294,  [72] = 23881,  [73] = 23922,    -- warrior: mortal strike, bloodthirst, shield slam
    [259] = 14177, [260] = 13750, [261] = 14185,   -- rogue: cold blood, adrenaline rush, preparation
    [62] = 12042,  [63] = 11129,  [64] = 11426,    -- mage: arcane power, combustion, ice barrier
    [256] = 10060, [257] = 724,   [258] = 15473,   -- priest: power infusion, lightwell, shadowform
    [102] = 24858, [103] = 16857, [104] = 16857, [105] = 18562, -- druid: moonkin, feral faerie fire, swiftmend
    [253] = 19574, [254] = 19506, [255] = 19386,   -- hunter: bestial wrath, trueshot aura, wyvern sting
    [262] = 16166, [263] = 17364, [264] = 16190,   -- shaman: elemental mastery, stormstrike, mana tide
    [265] = 18220, [266] = 19028, [267] = 17962,   -- warlock: dark pact, soul link, conflagrate
    [65] = 20473,  [66] = 20925,  [70] = 20066,    -- paladin: holy shock, holy shield, repentance
}
-- texture, left, right, top, bottom for a spec, or nil when the game has no icon for it
function Meter.SpecIcon(spec)
    local id = spec and SPEC_ICON_SPELL[spec]
    local tex = id and GetSpellTexture and GetSpellTexture(id)
    if not tex then return nil end
    return tex, 0.08, 0.92, 0.08, 0.92
end

-- ============================================================
-- SPEC FROM SPELL - a cast of one of these tells the meter the caster's
-- spec: the deep talents of each tree, every rank this client has. An
-- id a client does not have simply never fires.
-- ============================================================
local SPEC_BY_SPELL = {
    [71]  = { 12294, 21551, 21552, 21553, 12292 },          -- mortal strike, sweeping strikes
    [72]  = { 23881, 23892, 23893, 23894, 12328 },          -- bloodthirst, death wish
    [73]  = { 23922, 23923, 23924, 23925, 12809 },          -- shield slam, concussion blow
    [259] = { 14177 },                                      -- cold blood
    [260] = { 13750, 13877 },                               -- adrenaline rush, blade flurry
    [261] = { 14185, 14183, 16511, 17347, 17348 },          -- preparation, premeditation, hemorrhage
    [62]  = { 12042, 12043 },                               -- arcane power, presence of mind
    [63]  = { 11129, 11113, 13018, 13019, 13020, 13021 },   -- combustion, blast wave
    [64]  = { 11426, 13031, 13032, 13033, 12472 },          -- ice barrier, cold snap
    [256] = { 10060, 14751 },                               -- power infusion, inner focus
    [257] = { 724, 27870, 27871 },                          -- lightwell
    [258] = { 15473, 15286, 15487 },                        -- shadowform, vampiric embrace, silence
    [102] = { 24858, 5570, 24974, 24975, 24976, 24977 },    -- moonkin form, insect swarm
    [103] = { 16857, 17390, 17391, 17392 },                 -- faerie fire (feral)
    [105] = { 18562, 17116 },                               -- swiftmend, nature's swiftness
    [253] = { 19574, 19577 },                               -- bestial wrath, intimidation
    [254] = { 19506, 20905, 20906, 19434, 20900, 20901, 20902, 20903, 20904 }, -- trueshot aura, aimed shot
    [255] = { 19386, 24132, 24133, 19306, 20909, 20910 },   -- wyvern sting, counterattack
    [262] = { 16166 },                                      -- elemental mastery
    [263] = { 17364 },                                      -- stormstrike
    [264] = { 16190, 17354, 17359 },                        -- mana tide totem
    [265] = { 18265, 18879, 18880, 18881, 18220, 18937, 18938, 18288 }, -- siphon life, dark pact, amplify curse
    [266] = { 19028, 18788 },                               -- soul link, demonic sacrifice
    [267] = { 17962, 18930, 18931, 18932, 18933, 17877, 18867, 18868, 18869, 18870, 18871 }, -- conflagrate, shadowburn
    [65]  = { 20473, 20929, 20930, 20216 },                 -- holy shock, divine favor
    [66]  = { 20925, 20927, 20928 },                        -- holy shield
    [70]  = { 20066, 20375 },                               -- repentance, seal of command
}
Meter.SPEC_SPELLS = {}
for spec, ids in pairs(SPEC_BY_SPELL) do
    for _, id in ipairs(ids) do Meter.SPEC_SPELLS[id] = spec end
end

-- ============================================================
-- NUMBER FORMATTING - the ToK family, indexed the way the profile
-- indexes them (ps_abbreviation). His profile: 2.
-- ============================================================
local format, floor = string.format, math.floor

local function NoToK(n) return format("%.1f", n) end

-- ps_abbreviation = 2. Boundaries use > (not >=) exactly like the
-- original - 1000000 renders as "1000.0K" there and so it does here.
local function ToK(n)
    if n > 999999999 then return format("%.2f", n / 1000000000) .. "B"
    elseif n > 1000000 then return format("%.2f", n / 1000000) .. "M"
    elseif n > 999 then return format("%.1f", n / 1000) .. "K" end
    return format("%.0f", n)
end

-- ps_abbreviation = 3 (kept selectable in config).
local function ToK2(n)
    if n > 999999999 then return format("%.2f", n / 1000000000) .. "B"
    elseif n > 999999 then return format("%.2f", n / 1000000) .. "M"
    elseif n > 99999 then return floor(n / 1000) .. "K"
    elseif n > 999 then return format("%.1f", n / 1000) .. "K" end
    return format("%.0f", n)
end

-- ps_abbreviation = 4.
local function ToK0(n)
    if n > 999999999 then return format("%.1f", n / 1000000000) .. "B"
    elseif n > 999999 then return format("%.1f", n / 1000000) .. "M"
    elseif n > 999 then return floor(n / 1000) .. "K" end
    return format("%.0f", n)
end

Meter.ToKList = { NoToK, ToK, ToK2, ToK0 }
Meter.ToK = ToK
Meter.ToK2 = ToK2

-- ============================================================
-- THREAT GRADIENT - green at 0%, yellow at 50%, red at 100%. This is
-- Details:percent_color(value, inverted), evaluated the same way.
-- ============================================================
function Meter.PercentColor(value)
    local r, g
    if value < 50 then r = 255 else r = floor(255 - (value * 2 - 100) * 255 / 100) end
    if value > 50 then g = 255 else g = floor(value * 2 * 255 / 100) end
    -- inverted return: green channel first
    return g / 255, r / 255, 0
end

-- Role icon texcoords on Interface\LFGFrame\UI-LFG-Icon-PortraitRoles,
-- the sheet TinyThreat reads.
Meter.ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-Icon-PortraitRoles"
Meter.ROLE_COORDS = {
    TANK    = { 0, 0.28125, 0.328125, 0.625 },
    HEALER  = { 0.3125, 0.59375, 0, 0.296875 },
    DAMAGER = { 0.3125, 0.59375, 0.328125, 0.625 },
    NONE    = { 0.3125, 0.59375, 0.328125, 0.625 },
}

-- Synthetic spell ids for events that carry no spell, matching the
-- originals so tooltips and breakdowns label them the same way: melee
-- is 1 and auto shot 2 (the parser and Meter_Info use them as numbers),
-- environmental damage 3-8.
Meter.ENVIRONMENT_IDS = {
    Falling = 3, FALLING = 3,
    Drowning = 4, DROWNING = 4,
    Fatigue = 5, FATIGUE = 5,
    Fire = 6, FIRE = 6,
    Lava = 7, LAVA = 7,
    Slime = 8, SLIME = 8,
}
Meter.ENVIRONMENT_NAMES = {
    [3] = "Falling", [4] = "Drowning", [5] = "Fatigue",
    [6] = "Fire", [7] = "Lava", [8] = "Slime",
}

-- ============================================================
-- DEATHS IN PLAIN WORDS - what a death log says, as the numbers and the
-- sentence a raider reads. The meter's tooltip, its death recap, the
-- recap's report to chat and the raid summary all word a death through
-- these, so the four never disagree. Pure, and only ever run on a hover,
-- a click or a closed fight - never inside the combat log.
--
-- A death table (Meter_Combat's BuildDeathTable) keeps events oldest
-- first as { isDamage, spellId, amount, time, health after (0-1),
-- source, overkill, crit, school }; its time is the death's.
-- ============================================================
Meter.DEATH_WINDOW = 10         -- seconds before a death the recap shows

-- 4210 -> "4,210": a single hit reads better whole than as "4.2K"
function Meter.Comma(n)
    n = floor((tonumber(n) or 0) + 0.5)
    local neg = n < 0
    local s = tostring(neg and -n or n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return (neg and "-" or "") .. out
end

-- 133 -> "2:13"
function Meter.Clock(sec)
    sec = floor((tonumber(sec) or 0) + 0.5)
    if sec < 0 then sec = 0 end
    return floor(sec / 60) .. ":" .. format("%02d", sec % 60)
end

-- a spell id as the meter names it (melee, auto shot and the
-- environment have ids of their own)
function Meter.SpellLabel(id, fallback)
    if id == 1 then return _G.MELEE or "Melee" end
    if id == 2 then return "Auto Shot" end
    if Meter.ENVIRONMENT_NAMES[id] then return Meter.ENVIRONMENT_NAMES[id] end
    local name = type(id) == "number" and GetSpellInfo and GetSpellInfo(id)
    return name or fallback or ("Spell " .. tostring(id))
end

-- a death log's source: nil for a sourceless hit (falling, lava, the
-- parser files those under "[*] <name>")
local function CleanSource(name)
    if type(name) ~= "string" or name == "" or name:sub(1, 4) == "[*] " then return nil end
    return name
end
Meter.CleanSource = CleanSource

-- The events of the last `window` seconds before a death, NEWEST FIRST,
-- each as { dmg, spell, amt, ago (seconds before the death), hp (0-1),
-- src, over, crit, school }.
function Meter.DeathEvents(dt, window)
    local out = {}
    local evs = type(dt) == "table" and dt.events
    if type(evs) ~= "table" then return out end
    window = window or Meter.DEATH_WINDOW
    local t0 = tonumber(dt.time) or 0
    for i = #evs, 1, -1 do
        local ev = evs[i]
        if type(ev) == "table" and ev[4] then
            local ago = t0 - ev[4]
            if ago < 0 then ago = 0 end
            if ago <= window + 0.05 then
                out[#out + 1] = { dmg = ev[1] and true or false, spell = ev[2], amt = tonumber(ev[3]) or 0,
                    ago = ago, hp = ev[5], src = CleanSource(ev[6]),
                    over = (type(ev[7]) == "number" and ev[7] > 0) and ev[7] or 0,
                    crit = ev[8] and true or false, school = ev[9] }
            end
        end
    end
    return out
end

-- One death boiled down to plain numbers (also what the raid summary
-- keeps): the killing blow (spell, src, amt, over, crit; sure = it took
-- them to 0, else it is only the last hit the meter saw), up to nBefore
-- earlier hits and heals (newest first), the damage taken and healing
-- received in the last 5 seconds, and whether anything was seen at all.
function Meter.DeathSummary(dt, nBefore)
    local evs = Meter.DeathEvents(dt)
    local s = { seen = #evs > 0, took5 = 0, healed5 = 0, before = {},
        hpKnown = type(dt) == "table" and (tonumber(dt.maxHealth) or 0) > 0 or false }
    local kb
    for i = 1, #evs do
        if evs[i].dmg then kb = i break end
    end
    if kb then
        local k = evs[kb]
        s.spell, s.src, s.amt, s.over, s.crit = k.spell, k.src, k.amt, k.over, k.crit
        s.sure = k.over > 0 or (s.hpKnown and type(k.hp) == "number" and k.hp <= 0.01) or false
    end
    for i, e in ipairs(evs) do
        if e.ago <= 5 then
            if e.dmg then s.took5 = s.took5 + e.amt else s.healed5 = s.healed5 + e.amt end
        end
        if i ~= kb and #s.before < (nBefore or 3) then
            s.before[#s.before + 1] = { dmg = e.dmg, spell = e.spell, src = e.src, amt = e.amt,
                ago = e.ago, crit = e.crit }
        end
    end
    return s
end

-- "Shadow Flame from Ebonroc"
local function Named(spell, src, nameOf)
    local t = nameOf(spell)
    if src then t = t .. " from " .. src end
    return t
end
-- the killing blow alone: "Shadow Flame from Ebonroc (4,210, 1,350 overkill)"
function Meter.KillingBlowText(s, nameOf)
    nameOf = nameOf or Meter.SpellLabel
    if not (s and s.spell) then return nil end
    local t = Named(s.spell, s.src, nameOf)
    if s.amt then
        local nums = Meter.Comma(s.amt)
        if (s.over or 0) > 0 then nums = nums .. ", " .. Meter.Comma(s.over) .. " overkill" end
        t = t .. " (" .. nums .. ")"
    end
    return t
end

-- The sentence: "Zac died to Shadow Flame from Ebonroc (4,210, 1,350
-- overkill); before that: Melee from Ebonroc 1,200, Flash Heal from Pria
-- +1,800." withBefore adds the earlier hits while the line stays under
-- maxLen (chat takes 255). Plain text: no colours, no icons.
function Meter.DeathSentence(s, who, nameOf, withBefore, maxLen)
    nameOf = nameOf or Meter.SpellLabel
    who = who or "They"
    if type(s) ~= "table" or s.seen == false then
        return who .. " died, but the meter saw none of the hits before it (out of range, or joined late)."
    end
    local kb = Meter.KillingBlowText(s, nameOf)
    if not kb then return who .. " died; the meter saw no hit that did it." end
    local out = (s.sure == false) and (who .. " died; the last hit the meter saw was " .. kb)
        or (who .. " died to " .. kb)
    if withBefore and type(s.before) == "table" and #s.before > 0 then
        maxLen = maxLen or 250
        local parts = {}
        for _, e in ipairs(s.before) do
            local item = Named(e.spell, e.src, nameOf) .. " " .. (e.dmg and "" or "+") .. Meter.Comma(e.amt)
            local try = out .. "; before that: " .. table.concat(parts, ", ") .. (#parts > 0 and ", " or "") .. item .. "."
            if #try > maxLen then break end
            parts[#parts + 1] = item
        end
        if #parts > 0 then out = out .. "; before that: " .. table.concat(parts, ", ") end
    end
    return out .. "."
end

-- shared with later ZacUI files
ns.Meter = Meter
