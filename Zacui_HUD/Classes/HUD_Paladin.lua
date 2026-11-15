-- HUD_Paladin - the Paladin HUD on the class HUD engine (HUD_ClassHUD) and
-- its spec defaults (HUD_V2_Specs): a definition - the cooldown grid, the
-- active buffs, your judgements on the target, the utility row, a preset
-- per spec (Holy / Protection / Retribution) for Classic Era, TBC and WoW
-- Forever - plus the parts this HUD always drew by hand, kept as they
-- were: the mana bar with the MP5 / five-second-rule bar under it, the
-- swing timer, the "Righteous Fury" and "Blessing" reminder texts, the
-- active seal icon by the mana bar, the trinket and racial row.
--
-- It began as a port of the "Paladin Class Pack - Classic Era" WeakAura
-- and its saved settings keep that shape (ZacUIDB.hud.paladin: the bars'
-- switches and spots under resources.swingTimer / manaBar / mp5Bar /
-- swing / mana / texts, the MP5 colour under colors.mp5): nothing is
-- moved, the engine's parts that read a save are written here to read
-- this one.
--
-- A save from before the spec defaults is KEPT as it was: the first time
-- it loads, what it showed is written down as the player's own ticks
-- (cfg._specs = "kept"), so nothing appears, disappears or moves. A save
-- that never existed starts on the spec defaults (cfg._specs = "on"), and
-- "Reset to spec defaults" takes a kept one there.
-- Part of ZacUI; load order is set by the TOC (with the class definitions,
-- after HUD_ClassHUD and the HUD_V2_* files).
-- Perf rules: events set dirty flags / record timestamps only; scans
-- run in the 0.2s core ticker; countdown texts on a 0.1s text ticker.
local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass or not ns.HUD.ClassEngine then return end
if ns.HUD.RETAIL then return end   -- (Retail: its own class HUD, HUD_Retail.lua; this Classic one never loads there)

-- a value WoW Forever hands back hidden (a secret value: no maths on it)
local function Hidden(v) return ns.IsSecret ~= nil and ns.IsSecret(v) or false end
local HUD = ns.HUD
local Engine = HUD.ClassEngine
local V2 = HUD.V2          -- (nil on a tree without Class HUD v2)

-- API compat shims come from HUD_Shared.
local GetSpellInfo = HUD.GetSpellInfo

local RED_OOR = { 1, 0.2431, 0.2275 }          -- WA out-of-range tint
local GOLD_COUNT = { 1, 0.82, 0, 1 }
local PINK_TEXT = { 0.9569, 0.5490, 0.7294, 1 } -- WA reminder text color
local MANA_BLUE = { 0, 0.44, 0.87 }
local MP5_BLUE  = { 0, 0.24, 1 }
local TICK_GREY = { 0.8, 0.8, 0.8, 1 }          -- (the regen ticks' colour, Class HUD v2)
local HUD_STRATA = "MEDIUM"

-- The colours the HUD draws with, as settings (Look tab); the defaults
-- are the WeakAura's.
local COLOR_DEFAULTS = {
    oor = HUD.RGBA(RED_OOR), count = HUD.RGBA(GOLD_COUNT),
    timer = { r = 1, g = 1, b = 1, a = 1 }, text = HUD.RGBA(PINK_TEXT),
    barText = { r = 1, g = 1, b = 1, a = 1 },
    mana = HUD.RGBA(MANA_BLUE), mp5 = HUD.RGBA(MP5_BLUE), swing = { r = 1, g = 1, b = 1, a = 1 },
}

-- Storage: ZacUIDB.hud.paladin
local DEFAULTS = {
    enabled = false,
    mainRow = {
        x = 0, y = -208, scale = 1,
        -- The WA's custom grid overrides child sizes per row.
        rows = {
            { limit = 7, w = 30, h = 30 },
            { limit = 9, w = 25, h = 25 },
            { limit = 8, w = 25, h = 25 },
        },
        spacing = 4,
        hidden = {},                 -- key -> true (off) / false (on, yours)
        potionChoice = 13,           -- his export config: Major Mana Potion
    },
    auraRow = {
        x = 0, y = -150, scale = 1,
        iconSize = 25, spacing = 4,
        hidden = {},
    },
    debuffRow = { enabled = true, x = 0, y = -120, iconSize = 26, spacing = 4, hidden = {} },
    resources = {
        swingTimer = true,
        manaBar    = true,
        mp5Bar     = true,
        -- rfText / blessingText: nil = the spec decides (Protection warns
        -- about Righteous Fury), true / false = yours
        swing = { x = 0, y = -183, w = 316, h = 2 },
        mana  = { x = 0, y = -188, w = 234, h = 4 },
        texts = { x = 0, y = 180, size = 20 },
    },
    aux = {
        enabled = false,             -- WA "Paladin Aux" is use_never
        x = 0, y = -400, iconSize = 30, spacing = 4,
        trinket1 = true, trinket2 = true, racial = true,
    },
    colors = COLOR_DEFAULTS,
}

-- Any of these buffs counts as "blessed" (WA "Text - Blessing" list).
local BLESSING_IDS = {
    25291, 1044, 10278, 25916, 25290, 25899, 25895, 25894, 1038,
    20911, 19977, 25898, 20217, 25890, 425600,
}

-- One spell id per race; only the id matching the player's own race
-- resolves a name, so the first hit is the only hit.
-- (TBC's paladin races last: Gift of the Naaru, Arcane Torrent)
local RACIAL_IDS = { 20594, 20589, 20600, 20580, 7744, 20572, 20549, 20554, 28880, 28730 }

-- The seals the seal icon knows, in the order it looks for them: Classic
-- Era's, then TBC's (Blood / the Martyr, Vengeance / Corruption) and WoW
-- Forever's Seal of Fury - each only where the buff row carries it.
local SEAL_KEYS = { "sealCommand", "sealRight", "sealWisdom", "sealLight", "sealJustice", "sealCrusader",
    "sealBlood", "sealMartyr", "sealVengeance", "sealCorruption", "sealFury" }
local SEAL_SIZE = 24

-- Reminder texts a spec turns on by default (HUD_V2_Specs' roles carry
-- rows, glows and bar extras; these two are this HUD's own)
local ROLE_TEXTS = { protection = { rfText = true } }

-- ============================================================
-- THE DEFINITION
-- ============================================================
-- Spell ids: the WeakAura's for the first thirteen; the rest verified at
-- nether.wowhead.com/<classic|tbc>/tooltip/spell/<id> and, WoW Forever's
-- own, on warcraft.wiki.gg's "Paladin abilities (Forever)" pages. Name
-- lookups pick up the player's rank.
-- The lists keep the WeakAura's entries first and in its order (a save
-- from before draws exactly as it did); what came with the spec defaults
-- follows, unticked at the class baseline. A spec's own order is its
-- show list's (V2Ordered below).
local DEF = {
    class = "PALADIN", className = "Paladin", label = "Paladin HUD", store = "paladin",
    prefix = "ph", frameName = "Paladin", potionChoice = 13,
    blurb = "Cooldown grid, active buffs, your judgements on the target, swing timer, mana "
        .. "+ MP5 tick bars, the active seal and reminder texts, set up for your spec.",
    keywords = "paladin hud pally class pack weakaura cooldown grid seals seal judgement "
        .. "blessing swing timer mana bar mp5 righteous fury trinkets racial "
        .. "active buffs potion rune holy protection retribution spec holy shock holy shield "
        .. "crusader strike avenger's shield hammer of wrath vengeance target debuffs",

    spells = {
        loh          = 10310, divineShield = 1020,  hoj         = 853,
        freedom      = 1044,  bop          = 10278, judgement   = 20271,
        divineFavor  = 20216, consecration = 26573, intervention = 19752,
        divineProt   = 5573,  exorcism     = 10314, holyWrath   = 10318,
        righteousFury = 25780,
        holyShock = 20473, holyShield = 20925, hammerOfWrath = 24275, repentance = 20066,
        sacrifice = 6940, cleanse = 4987,
    },

    -- Main grid (order = WA child order, then the spec defaults' additions)
    grid = {
        { key = "loh",          kind = "spell", spell = "loh",          label = "Lay on Hands" },
        { key = "divineShield", kind = "spell", spell = "divineShield", label = "Divine Shield", noRange = true },
        { key = "hoj",          kind = "spell", spell = "hoj",          label = "Hammer of Justice" },
        { key = "freedom",      kind = "spell", spell = "freedom",      label = "Blessing of Freedom", noRange = true },
        { key = "bop",          kind = "spell", spell = "bop",          label = "Blessing of Protection" },
        { key = "judgement",    kind = "spell", spell = "judgement",    label = "Judgement" },
        { key = "divineFavor",  kind = "spell", spell = "divineFavor",  label = "Divine Favor", noRange = true },
        { key = "consecration", kind = "spell", spell = "consecration", label = "Consecration", noRange = true },
        { key = "intervention", kind = "spell", spell = "intervention", label = "Divine Intervention" },
        { key = "divineProt",   kind = "spell", spell = "divineProt",   label = "Divine Protection", noRange = true },
        { key = "exorcism",     kind = "spell", spell = "exorcism",     label = "Exorcism" },
        { key = "holyWrath",    kind = "spell", spell = "holyWrath",    label = "Holy Wrath" },
        { key = "potion",       kind = "itemPotion", label = "Potion" },
        { key = "rune",         kind = "itemRune",   label = "Rune" },
        -- (what a spec presses; off at the class baseline)
        { key = "holyShock",     kind = "spell", spell = "holyShock",     label = "Holy Shock", defaultHidden = true },
        { key = "holyShield",    kind = "spell", spell = "holyShield",    label = "Holy Shield", noRange = true, defaultHidden = true },
        { key = "hammerOfWrath", kind = "spell", spell = "hammerOfWrath", label = "Hammer of Wrath", defaultHidden = true },
        { key = "repentance",    kind = "spell", spell = "repentance",    label = "Repentance", defaultHidden = true },
        { key = "sacrifice",     kind = "spell", spell = "sacrifice",     label = "Blessing of Sacrifice", defaultHidden = true },
    },

    -- Active-buff row (WA "Paladin Aura Bar" order), then the additions
    buffRow = {
        { key = "divineFavor",  id = 20216 },
        { key = "sealCrusader", id = 20306 },
        { key = "divineShield", id = 1020 },
        { key = "zhc",          id = 24659, label = "Zandalarian Hero Charm" },
        { key = "eyeOfDead",    id = 28780, label = "Eye of the Dead" },
        { key = "blindingLight", id = 23733, label = "Blinding Light" },
        { key = "divineProt",   id = 498 },
        { key = "holyShield",   id = 20925 },
        { key = "sealWisdom",   id = 20351 },
        { key = "sealRight",    id = 20438 },
        { key = "sealLight",    id = 20456 },
        { key = "sealJustice",  id = 20164 },
        { key = "sealCommand",  id = 20944 },
        { key = "vengeance",    id = 20055, label = "Vengeance", defaultHidden = true },
    },

    -- Your own debuffs on the target: the judgements, the stuns
    debuffRow = {
        { key = "judgeCrusader",    id = 21183, label = "Judgement of the Crusader", defaultHidden = true },
        { key = "judgeWisdom",      id = 20186, label = "Judgement of Wisdom", defaultHidden = true },
        { key = "judgeLight",       id = 20185, label = "Judgement of Light", defaultHidden = true },
        { key = "judgeJustice",     id = 20184, label = "Judgement of Justice", defaultHidden = true },
        { key = "hojStun",          id = 853,   label = "Hammer of Justice", defaultHidden = true },
        { key = "repentanceDebuff", id = 20066, label = "Repentance", defaultHidden = true },
    },

    -- Class HUD v2: the utility row (off until turned on)
    utility = {
        { key = "righteousFury", kind = "spell", spell = "righteousFury", label = "Righteous Fury", noRange = true },
        { key = "cleanse",       kind = "spell", spell = "cleanse",       label = "Cleanse" },
    },

    -- Spec presets (HUD_V2_Specs): each spec's default HUD, from what its
    -- players press and track (the audit of 2026-11-09; Icy Veins' and
    -- Wowhead's Classic / TBC paladin guides; WoW Forever: wowtbc.gg's
    -- Forever paladin guides). The base lists are Classic Era's; a spec's
    -- tbc / forever block replaces the rows it names on that game.
    --   Holy        Holy Shock, Divine Favor, the utility blessings; the
    --               judgement kept up (Light / Wisdom); no Exorcism, Holy
    --               Wrath or Consecration. TBC: Divine Illumination, Light's
    --               Grace, Blessing of Sacrifice. Forever: Light's Vigil,
    --               Holy Strike, the Infusion of Light proc.
    --   Protection  Holy Shield as a cooldown, Consecration, the "Righteous
    --               Fury" warning on. TBC: Avenger's Shield, Righteous
    --               Defense, Avenging Wrath, Holy Vengeance on the target.
    --               Forever: Seal of Fury, Swift Judgement, Holy Strike,
    --               Templar's Bulwark.
    --   Retribution Judgement, Hammer of Wrath (lit when usable), Vengeance,
    --               Judgement of the Crusader. TBC: Crusader Strike, Avenging
    --               Wrath, Seal of Blood / the Martyr. Forever: Holy Strike.
    roles = {
        { key = "holy", label = "Holy", tab = 1, aux = true, res = { regen = true }, show = {
            main = { "holyShock", "divineFavor", "judgement", "bop", "freedom", "loh", "divineShield", "hoj", "intervention", "potion", "rune" },
            utility = { "cleanse" },
            buffs = { "divineFavor", "divineShield", "sealWisdom", "sealLight", "zhc", "eyeOfDead", "blindingLight" },
            debuffs = { "judgeLight", "judgeWisdom" } },
          glows = { divineFavor = { { when = "ready", style = "edge", combatOnly = true } } },
          tbc = { show = {
              main = { "holyShock", "divineFavor", "divineIllumination", "judgement", "sacrifice", "bop", "freedom", "loh", "divineShield", "hoj", "intervention", "potion", "rune" },
              buffs = { "divineFavor", "divineIllumBuff", "lightsGrace", "divineShield", "sealWisdom", "sealLight" } },
            glows = { divineFavor = { { when = "ready", style = "edge", combatOnly = true } },
                      divineIllumination = { { when = "ready", style = "edge", combatOnly = true } },
                      ["buffs:lightsGrace"] = { { when = "expiring", style = "pulse" } } } },
          forever = { show = {
              main = { "holyShock", "lightsVigil", "divineFavor", "judgement", "holyStrike", "bop", "freedom", "loh", "divineShield", "hoj", "intervention", "potion", "rune" },
              utility = { "oathOfLight", "cleanse" },
              buffs = { "infusionOfLight", "divineFavor", "divineShield", "sealWisdom", "sealLight", "zhc", "eyeOfDead", "blindingLight" } },
            glows = { divineFavor = { { when = "ready", style = "edge", combatOnly = true } },
                      ["buffs:infusionOfLight"] = { { when = "active", style = "shine" } } } } },
        { key = "protection", label = "Protection", tab = 2, aux = true, res = { rangeDim = true }, show = {
            main = { "holyShield", "judgement", "consecration", "exorcism", "holyWrath", "hoj", "loh", "divineShield", "bop", "freedom", "intervention", "potion", "rune" },
            utility = { "righteousFury", "cleanse" },
            buffs = { "holyShield", "sealRight", "sealWisdom", "sealLight", "divineShield", "zhc" },
            debuffs = { "judgeWisdom", "judgeLight", "judgeCrusader", "hojStun" } },
          glows = { holyShield = { { when = "ready", style = "edge", combatOnly = true } } },
          tbc = { show = {
              main = { "holyShield", "avengersShield", "judgement", "consecration", "righteousDefense", "avengingWrath", "exorcism", "holyWrath", "hoj", "loh", "divineShield", "bop", "freedom", "intervention", "potion", "rune" },
              buffs = { "holyShield", "avengingWrathBuff", "sealRight", "sealVengeance", "sealCorruption", "sealWisdom", "sealLight", "divineShield" },
              debuffs = { "holyVengeance", "judgeWisdom", "judgeLight", "judgeCrusader", "hojStun" } },
            glows = { holyShield = { { when = "ready", style = "edge", combatOnly = true } },
                      avengersShield = { { when = "ready", style = "edge", combatOnly = true } },
                      ["debuffs:holyVengeance"] = { { when = "expiring", style = "pulse" } } } },
          forever = { show = {
              main = { "holyShield", "judgement", "swiftJudgement", "holyStrike", "consecration", "templarsBulwark", "exorcism", "holyWrath", "hoj", "loh", "divineShield", "bop", "freedom", "intervention", "potion", "rune" },
              buffs = { "holyShield", "templarsBulwarkBuff", "sealFury", "sealRight", "sealWisdom", "sealLight", "divineShield", "zhc" } },
            glows = { holyShield = { { when = "ready", style = "edge", combatOnly = true } },
                      holyStrike = { { when = "ready", style = "edge", combatOnly = true } } } } },
        { key = "retribution", label = "Retribution", tab = 3, aux = true, res = { rangeDim = true }, show = {
            main = { "judgement", "hammerOfWrath", "consecration", "exorcism", "holyWrath", "hoj", "repentance", "loh", "divineShield", "bop", "freedom", "potion", "rune" },
            utility = { "cleanse" },
            buffs = { "vengeance", "sealCommand", "sealRight", "sealCrusader", "divineShield", "zhc" },
            debuffs = { "judgeCrusader", "judgeWisdom", "judgeLight", "hojStun", "repentanceDebuff" } },
          glows = { hammerOfWrath = { { when = "usable", style = "edge", combatOnly = true } } },
          tbc = { show = {
              main = { "crusaderStrike", "judgement", "consecration", "exorcism", "hammerOfWrath", "avengingWrath", "hoj", "repentance", "loh", "divineShield", "bop", "freedom", "potion", "rune" },
              buffs = { "vengeance", "avengingWrathBuff", "sealBlood", "sealMartyr", "sealCommand", "sealCrusader", "divineShield" } },
            glows = { crusaderStrike = { { when = "ready", style = "edge", combatOnly = true } },
                      avengingWrath = { { when = "ready", style = "edge", combatOnly = true } },
                      hammerOfWrath = { { when = "usable", style = "edge", combatOnly = true } } } },
          forever = { show = {
              main = { "holyStrike", "judgement", "hammerOfWrath", "consecration", "exorcism", "holyWrath", "hoj", "repentance", "loh", "divineShield", "bop", "freedom", "potion", "rune" } },
            glows = { holyStrike = { { when = "ready", style = "edge", combatOnly = true } },
                      hammerOfWrath = { { when = "usable", style = "edge", combatOnly = true } } } } },
    },
    flavors = {
        tbc = { add = {
            { key = "crusaderStrike",     kind = "spell", spell = "crusaderStrike",     spellId = 35395, label = "Crusader Strike" },
            { key = "avengersShield",     kind = "spell", spell = "avengersShield",     spellId = 31935, label = "Avenger's Shield" },
            { key = "avengingWrath",      kind = "spell", spell = "avengingWrath",      spellId = 31884, label = "Avenging Wrath", noRange = true },
            { key = "divineIllumination", kind = "spell", spell = "divineIllumination", spellId = 31842, label = "Divine Illumination", noRange = true },
            { key = "righteousDefense",   kind = "spell", spell = "righteousDefense",   spellId = 31789, label = "Righteous Defense" },
            { key = "avengingWrathBuff", id = 31884,  label = "Avenging Wrath", row = "buffs" },
            { key = "divineIllumBuff",   id = 31842,  label = "Divine Illumination", row = "buffs" },
            { key = "lightsGrace",       id = 31834,  label = "Light's Grace", row = "buffs" },
            { key = "sealBlood",         id = 31892,  label = "Seal of Blood", row = "buffs" },
            { key = "sealMartyr",        id = 348700, label = "Seal of the Martyr", row = "buffs" },
            { key = "sealVengeance",     id = 31801,  label = "Seal of Vengeance", row = "buffs" },
            { key = "sealCorruption",    id = 348704, label = "Seal of Corruption", row = "buffs" },
            { key = "holyVengeance",     id = 31803,  label = "Holy Vengeance", row = "debuffs" },
        } },
        -- WoW Forever's own (1.60.1; ids: warcraft.wiki.gg's Forever pages)
        forever = { add = {
            { key = "holyStrike",      kind = "spell", spell = "holyStrike",      spellId = 679,     label = "Holy Strike" },
            { key = "lightsVigil",     kind = "spell", spell = "lightsVigil",     spellId = 1310911, label = "Light's Vigil" },
            { key = "swiftJudgement",  kind = "spell", spell = "swiftJudgement",  spellId = 1310994, label = "Swift Judgement" },
            { key = "templarsBulwark", kind = "spell", spell = "templarsBulwark", spellId = 1311015, label = "Templar's Bulwark", noRange = true },
            { key = "oathOfLight",     kind = "spell", spell = "oathOfLight",     spellId = 1328548, label = "Oath of Light", row = "utility" },
            { key = "sealFury",            id = 1311649, label = "Seal of Fury", row = "buffs" },
            { key = "infusionOfLight",     id = 426065,  label = "Infusion of Light", row = "buffs" },
            { key = "templarsBulwarkBuff", id = 1311015, label = "Templar's Bulwark", row = "buffs" },
        } },
    },
    buffBars = { "holyShield", "vengeance", "divineFavor" },
    bars = { "mana", "fsr", "swing" },
}

-- a spec's own icon order: its show lists, as written above (the engine
-- keeps them as sets), for the game version this client runs
local SHOW_ORDER = {}
do
    local fl = ns.Flavor and ns.Flavor() or "era"
    for _, r in ipairs(DEF.roles) do
        local rows = {}
        for row, keys in pairs(r.show or {}) do rows[row] = keys end
        local over = type(r[fl]) == "table" and r[fl].show or nil
        for row, keys in pairs(over or {}) do rows[row] = keys end
        SHOW_ORDER[r.key] = rows
    end
end

-- ============================================================
-- THE SAVE: its old shape, its old migrations, kept as it was
-- ============================================================
-- A save from before the spec defaults: every entry's state written down
-- as the player's own tick (on stays on, what is new stays off) and the
-- reminder texts as they were. While it is kept no spec is in force on it
-- (Pal:V2SpecRole below): no spec glow, bar extra, trinket row or order.
local function Keep(db)
    local function Rows(hidden, list)
        if type(hidden) ~= "table" then return end
        for _, e in ipairs(list or {}) do
            if hidden[e.key] == nil then hidden[e.key] = e.defaultHidden and true or false end
        end
    end
    Rows(db.mainRow.hidden, DEF.grid)
    Rows(db.auraRow.hidden, DEF.buffRow)
    Rows(db.debuffRow.hidden, DEF.debuffRow)
    local r = db.resources
    if r.rfText == nil then r.rfText = false end
    if r.blessingText == nil then r.blessingText = false end
end

local checked   -- the saved table these checks last ran on (a profile switch puts a new one)
local function PalStore()
    local root = type(ZacUIDB) == "table" and ZacUIDB.hud or nil
    local raw = type(root) == "table" and root.paladin or nil
    if raw ~= nil and raw == checked then return raw end
    local existed = type(raw) == "table" and next(raw) ~= nil
    local db = HUD.Store("paladin", DEFAULTS)
    if not db then return nil end
    checked = db
    -- Migration: drop the first cut's dead flat iconW/iconH/perRow keys.
    local m = db.mainRow
    if m and m.iconW then
        m.iconW, m.iconH, m.perRow = nil, nil, nil
    end
    -- Migration: rfText briefly shipped default-ON; one-time flip to off
    -- (a save that never existed has nothing to flip: its spec decides).
    if not db._rfDefaultFlipped then
        db._rfDefaultFlipped = true
        if existed and db.resources then db.resources.rfText = false end
    end
    -- the spec defaults: a save from before them is kept as it was (one
    -- that already carries Class HUD v2 settings is not from before)
    if db._specs == nil then
        if existed and type(db.v2) ~= "table" then
            Keep(db)
            db._specs = "kept"
        else
            db._specs = "on"
        end
    end
    return db
end

-- ============================================================
-- THE ENGINE, WITH THIS HUD'S OWN PARTS
-- ============================================================
local Pal = setmetatable({}, { __index = Engine })
Pal.__index = Pal

function Pal:Store() return PalStore() end

-- an entry off its row / the trinket row on (the engine's own rules)
local function Off(eng, row, hidden, def)
    if eng.V2Off then return eng:V2Off(row, hidden, def) end
    local v = hidden and hidden[def.key]
    if v ~= nil then return v and true or false end
    return def.defaultHidden and true or false
end
local function AuxOn(eng, cfg)
    if eng.V2AuxOn then return eng:V2AuxOn(cfg) end
    return cfg.aux.enabled and true or false
end

-- a reminder text on: your switch, else the spec's
local function TextOn(eng, r, key)
    local v = r[key]
    if v ~= nil then return v and true or false end
    local role = eng.V2SpecRole and eng:V2SpecRole() or nil
    local t = role and ROLE_TEXTS[role.key]
    return (t and t[key]) and true or false
end

local function AnyDebuffOn(eng, cfg)
    local d = cfg.debuffRow
    if not d or d.enabled == false then return false end
    for _, e in ipairs(eng.def.debuffRow or {}) do
        if not Off(eng, "debuffs", d.hidden, e) then return true end
    end
    return false
end

-- Anchors and movers: the same keys and labels as before, the save's own paths
function Pal:Elements()
    local list = {
        { key = "Main",      mover = "phMainRow",   label = "Cooldown Grid",  cfg = function(c) return c.mainRow end },
        { key = "AuraRow",   mover = "phAuraRow",   label = "Active Buffs",   cfg = function(c) return c.auraRow end },
        { key = "DebuffRow", mover = "phDebuffRow", label = "Target Debuffs", cfg = function(c) return c.debuffRow end },
    }
    if self.V2Elements then self:V2Elements(list) end
    list[#list + 1] = { key = "Swing", mover = "phSwing", label = "Swing Timer",    cfg = function(c) return c.resources.swing end }
    list[#list + 1] = { key = "Mana",  mover = "phMana",  label = "Mana + MP5",     cfg = function(c) return c.resources.mana end }
    list[#list + 1] = { key = "Texts", mover = "phTexts", label = "Reminder Texts", cfg = function(c) return c.resources.texts end }
    list[#list + 1] = { key = "Aux",   mover = "phAux",   label = "Trinkets/Racial", cfg = function(c) return c.aux end }
    return list
end

-- Icons: the WeakAura's own entries always have theirs (as they always
-- did, ticked or not); an entry the spec defaults brought (unticked at the
-- class baseline: defaultHidden) gets its icon the first time it is on. A
-- save from before thus holds exactly the frames it always held, and a
-- HUD carries no frames for additions it does not show.
local function MakeIcon(eng, row, def)
    local W = eng.W
    local cfg = eng:Store()
    if row == "main" then
        -- (as the engine's BuildMainIcons makes one)
        local icon = W.CreateIcon(eng.anchors.Main, { width = 30, height = 30, zoom = W.ICON_ZOOM, keepAspect = true, inverse = true })
        icon:SetFrameStrata(HUD_STRATA)
        icon:Hide()
        icon.def = def
        icon:AddText("p", "CENTER", 14, { 1, 1, 1, 1 })
        icon:SetText("p", "")
        if def.kind ~= "spell" then
            icon:AddText("count", "INNER_BOTTOMRIGHT", 12, GOLD_COUNT, 0, 0)
        end
        eng.mainIcons[def.key] = icon
    elseif row == "debuffs" then
        Engine.BuildRowIcons(eng, { def }, eng.anchors.DebuffRow, (cfg and cfg.debuffRow.iconSize) or 26, eng.debuffIcons)
    else
        Engine.BuildRowIcons(eng, { def }, eng.anchors.AuraRow, (cfg and cfg.auraRow.iconSize) or 25, eng.auraIcons)
    end
end

function Pal:BuildMainIcons()
    local cfg = self:Store()
    for _, def in ipairs(self.def.grid) do
        if not def.defaultHidden or not Off(self, "main", cfg.mainRow.hidden, def) then MakeIcon(self, "main", def) end
    end
end

function Pal:BuildRowIcons(list, anchor, size, store)
    local cfg = self:Store()
    local row = (store == self.debuffIcons) and "debuffs" or "buffs"
    local hidden = (row == "debuffs") and cfg.debuffRow.hidden or cfg.auraRow.hidden
    for _, def in ipairs(list) do
        if not def.defaultHidden or not Off(self, row, hidden, def) then MakeIcon(self, row, def) end
    end
end

-- A row's entries that have an icon, in the row's order (the list the
-- engine's refresh walks); an entry that is on and has none gets one now.
-- The list is kept and rewritten in place: nothing is allocated per tick.
local function LiveList(eng, row, list, icons, hidden)
    local c = eng._liveLists
    if not c then c = {} eng._liveLists = c end
    local out = c[row]
    if not out then out = {} c[row] = out end
    local n, made = 0, false
    for _, def in ipairs(list) do
        local icon = icons[def.key]
        if not icon and not Off(eng, row, hidden, def) then
            MakeIcon(eng, row, def)
            made = true
            icon = icons[def.key]
        end
        if icon then
            n = n + 1
            if out[n] ~= def then out[n] = def end
        end
    end
    for i = #out, n + 1, -1 do out[i] = nil end
    if made then eng:ApplyColors() end
    return out
end

function Pal:RefreshMainRow(cfg)
    -- the engine walks the definition's grid: for the walk, the entries with an icon
    local def = self.def
    local full = def.grid
    def.grid = LiveList(self, "main", full, self.mainIcons, cfg.mainRow.hidden)
    local good, err = pcall(Engine.RefreshMainRow, self, cfg)
    def.grid = full
    if not good then error(err, 0) end
end

function Pal:RefreshAuraList(cfg, list, icons, active, rowCfg, anchor, source, memo)
    local row = (icons == self.debuffIcons) and "debuffs" or "buffs"
    return Engine.RefreshAuraList(self, cfg, LiveList(self, row, list, icons, rowCfg.hidden), icons, active, rowCfg, anchor, source, memo)
end

-- Colours: this HUD's own set (the MP5 bar's under colors.mp5)
function Pal:ApplyColors()
    local cfg = self:Store()
    local src = (cfg and cfg.colors) or COLOR_DEFAULTS
    local col = {}
    for k, d in pairs(COLOR_DEFAULTS) do
        local r, g, b, a = HUD.Col(src[k], d)
        col[k] = { r, g, b, a }
    end
    col.fsr, col.tick = col.mp5, TICK_GREY   -- (the engine's names for the bar under the mana bar)
    self.col = col
    self._serial = HUD.serial
    if not self.built then return end
    local function bar(b, c) if b then b:SetBarColor(c[1], c[2], c[3], c[4]) end end
    bar(self.swingBar, col.swing)
    bar(self.manaBar, col.mana)
    bar(self.mp5Bar, col.mp5)
    if self.mp5Bar then self.mp5Bar._v2col = nil end
    if self.manaBar then self.manaBar.text:SetTextColor(unpack(col.barText)) end
    for _, set in ipairs({ self.mainIcons, self.auraIcons, self.debuffIcons, self.auxIcons }) do
        for _, icon in pairs(set) do
            local t = icon.texts
            if t.p then t.p:SetTextColor(unpack(col.timer)) end
            if t.s then t.s:SetTextColor(unpack(col.timer)) end
            if t.count then t.count:SetTextColor(unpack(col.count)) end
        end
    end
    if self.rfText then self.rfText:SetTextColor(unpack(col.text)) end
    if self.blessText then self.blessText:SetTextColor(unpack(col.text)) end
end

-- Spell / buff resolution: the engine's, with the paladin's racials, the
-- blessing names and the trinket buff's literal name
function Pal:ResolveSpells()
    Engine.ResolveSpells(self)
    local S = self.S
    -- (each buff's own icon, for the "show every element" state and the seal icon's)
    if GetSpellInfo then
        for _, list in ipairs({ self.def.buffRow or {}, self.def.debuffRow or {} }) do
            for _, e in ipairs(list) do
                local _, _, icon = GetSpellInfo(e.id)
                S.auraIcons[e.key] = e.icon or icon
            end
        end
    end
    -- Trinket buffs come from items; keep the WA's literal names.
    S.auraNames.zhc = S.auraNames.zhc or "Zandalarian Hero Charm"
    S.blessingNames = S.blessingNames or {}
    wipe(S.blessingNames)
    for _, id in ipairs(BLESSING_IDS) do
        local name = GetSpellInfo and GetSpellInfo(id) or nil
        if name then S.blessingNames[name:lower()] = true end
    end
    S.racial = nil
    for _, id in ipairs(RACIAL_IDS) do
        local name = GetSpellInfo and GetSpellInfo(id) or nil
        if name then
            local n2, _, tex = GetSpellInfo(name)
            if n2 then
                S.racial = { name = name, icon = tex }
                break
            end
        end
    end
end

-- Bars and texts: the swing timer, the mana bar with the MP5 bar under
-- it, the two reminder texts
function Pal:BuildBars()
    local V, W = self, self.W
    local cfg = self:Store()
    local r = cfg and cfg.resources or DEFAULTS.resources
    local VS = self.S
    local A = self.anchors

    local swingBar = W.CreateBar(A.Swing, { width = r.swing.w, height = r.swing.h,
        spark = true, barColor = self:Col("swing") })
    swingBar:SetFrameStrata(HUD_STRATA)
    swingBar:SetPoint("CENTER", A.Swing, "CENTER", 0, 0)
    swingBar:Hide()
    self.swingBar = swingBar

    local manaBar = W.CreateBar(A.Mana, { width = r.mana.w, height = r.mana.h,
        barColor = self:Col("mana") })
    manaBar:SetFrameStrata(HUD_STRATA)
    manaBar:SetPoint("CENTER", A.Mana, "CENTER", 0, 2)
    -- Created on the StatusBar so it draws above the fill texture.
    local mt = HUD.Text(manaBar.bar, 10, "OUTLINE", "OVERLAY", "text")
    mt:SetPoint("CENTER", manaBar, "CENTER", 0, 0)
    mt:SetTextColor(1, 1, 1)
    manaBar.text = mt
    if HUD.BarText then HUD.BarText(mt, manaBar) end
    -- the raw mana value on the bar, not a percent (WA)
    if self.sample then manaBar.readMana = function() return VS.mana or 0, VS.manaMax or 1 end end
    manaBar:SetScript("OnUpdate", HUD.ManaBarOnUpdate)
    manaBar:Hide()
    self.manaBar = manaBar

    -- MP5 bar: drains over the current tick / five-second-rule window.
    -- MP5 rules (reworked from the WA, which restarted on every mana event
    -- and jumped between 2s and 6.45s while chain-casting; the engine's
    -- power events keep the window, S.fsr):
    --  * Spending mana on a cast -> one clean 5s five-second-rule drain.
    --  * Mana gains start a 2s tick window only once the 5s rule elapsed and
    --    nothing is hardcast, so JoW/Wisdom/seal procs can't hijack the bar.
    local mp5Bar = W.CreateBar(A.Mana, { width = r.mana.w, height = r.mana.h,
        barColor = self:Col("mp5") })
    mp5Bar:SetFrameStrata(HUD_STRATA)
    mp5Bar:SetPoint("CENTER", A.Mana, "CENTER", 0, -3)
    mp5Bar:SetScript("OnUpdate", function(b)
        local w = VS.fsr
        local dur = w.duration or 0
        if V.preview then
            b.bar:SetValue(0.65)
            return
        end
        if dur <= 0 then
            b.bar:SetValue(0)
            return
        end
        local remaining = w.start + dur - GetTime()
        -- the preview's sample runs its made-up window round and round
        if V.sample and remaining <= 0 then
            w.start = GetTime()
            remaining = dur
        end
        if remaining <= 0 then
            b.bar:SetValue(0)
        else
            b.bar:SetValue(remaining / dur)
        end
    end)
    mp5Bar:Hide()
    self.mp5Bar = mp5Bar
    self.fsrBar = mp5Bar   -- (the engine's name for it: its regen ticks, HideAll)

    -- Reminder texts (WA pink; sized down from the WA's 32px per feedback).
    local pc = self:Col("text")
    local rfText = HUD.Text(A.Texts, r.texts.size or 20, "OUTLINE", "OVERLAY", "alert")
    rfText:SetPoint("CENTER", A.Texts, "CENTER", 0, 8)
    rfText:SetTextColor(unpack(pc))
    rfText:SetText("Righteous Fury")
    rfText:Hide()
    self.rfText = rfText

    local blessText = HUD.Text(A.Texts, r.texts.size or 20, "OUTLINE", "OVERLAY", "alert")
    blessText:SetPoint("CENTER", A.Texts, "CENTER", 0, -14)
    blessText:SetTextColor(unpack(pc))
    blessText:SetText("Blessing")
    blessText:Hide()
    self.blessText = blessText
    self.textFS = { rfText = rfText, blessingText = blessText }   -- (the engine hides these with the HUD)

    -- Swing driver (only while the swing bar is shown)
    local driver = CreateFrame("Frame", nil, self.sample and A.Swing or nil)
    driver:Hide()
    driver:SetScript("OnUpdate", function()
        if not swingBar:IsShown() then driver:Hide() return end
        if V.preview then
            swingBar.bar:SetValue(0.65)
            if swingBar.UpdateSpark then swingBar:UpdateSpark(0.65) end
            return
        end
        local dur = VS.swing.duration or 0
        local remaining = dur > 0 and (VS.swing.start + dur - GetTime()) or 0
        if V.sample and dur > 0 and remaining <= 0 then
            VS.swing.start = GetTime()
            remaining = dur
        end
        -- (WoW Forever: a hidden swing time runs on the game's clock)
        if not V.sample and HUD.TimedSwing(swingBar, VS.swing.durObj) then return end
        HUD.UntimedSwing(swingBar)
        local frac = (remaining > 0 and dur > 0) and (remaining / dur) or 0
        swingBar.bar:SetValue(frac)
        if swingBar.UpdateSpark then swingBar:UpdateSpark(frac) end
    end)
    self.swingDriver = driver
end

-- The active seal as an icon by the mana bar (off until turned on:
-- cfg.resources.sealIcon; the icon is made only then). Classic Era / TBC
-- read the seal from your buffs by name; WoW Forever, which hides your
-- buffs in a fight, asks for each seal by the rank you know
-- (C_UnitAuras.GetPlayerAuraBySpellID) and keeps the last state when the
-- game answers nothing there; its time runs on the game's clock.
local function SealIcon(V, cfg)
    local icon = V.sealIcon
    local W = V.W
    local size = cfg.resources.sealIconSize or SEAL_SIZE
    if not icon then
        icon = W.CreateIcon(V.anchors.Mana, { width = size, height = size, zoom = W.ICON_ZOOM, keepAspect = true, inverse = true })
        icon:SetFrameStrata(HUD_STRATA)
        icon:SetPoint("RIGHT", V.manaBar, "LEFT", -4, 0)
        icon:AddText("p", "CENTER", 11, { 1, 1, 1, 1 })
        icon:Hide()
        icon._size = size
        V.sealIcon = icon
    elseif icon._size ~= size then
        icon._size = size
        icon:SetSize(size, size)
    end
    return icon
end

local function ForeverSeal(VS)
    local UA = C_UnitAuras
    local get = UA and UA.GetPlayerAuraBySpellID
    if not (get and ns.ModernClient and ns.ModernClient()) then return nil end
    for _, key in ipairs(SEAL_KEYS) do
        local name = VS.auraNames[key]
        local id = name and GetSpellInfo and select(7, GetSpellInfo(name))
        if type(id) == "number" and not Hidden(id) then
            local ok, a = pcall(get, id)
            if ok and type(a) == "table" then return a end
        end
    end
    return nil
end

local function RefreshSeal(V, cfg)
    local r = cfg.resources
    if not (r.sealIcon and V.manaBar) then
        if V.sealIcon then V.sealIcon:Hide() end
        return
    end
    local icon = SealIcon(V, cfg)
    local VS = V.S
    local shown = false
    if V:On(cfg) then
        local b
        for _, key in ipairs(SEAL_KEYS) do
            local name = VS.auraNames[key]
            b = name and VS.buffs[name:lower()]
            if b then break end
        end
        if b then
            V.sealHidden = nil
            V.sealRef = b
            icon:SetIconTexture(b.icon or 134400)
            if (b.duration or 0) > 0 then icon:SetSwipe(b.expirationTime - b.duration, b.duration) else icon:ClearSwipe() end
            shown = true
        elseif not V.sample then
            local a = ForeverSeal(VS)
            if a then
                V.sealHidden, V.sealRef = a, nil
                icon:SetHiddenTexture(a.icon)
                icon:SetHiddenSwipe("player", a)
                shown = true
            elseif V.sealHidden and VS.inCombat then
                shown = true   -- (nothing answered in a fight: as it was)
            else
                V.sealHidden, V.sealRef = nil, nil
            end
        end
        if not shown and V.preview then
            V.sealRef = nil
            icon:SetIconTexture(VS.auraIcons.sealRight or 134400)
            icon:ClearSwipe()
            shown = true
        end
    end
    icon:SetShown(shown)
end

local function SealText(V)
    local icon = V.sealIcon
    if not (icon and icon:IsShown()) then return end
    local b = V.sealRef
    if b and (b.expirationTime or 0) > 0 then
        icon:SetText("p", V.W.FormatTime(math.max(0, b.expirationTime - GetTime()), 0))
    elseif V.sealHidden then
        local left = ns.AuraTimeLeft and ns.AuraTimeLeft("player", V.sealHidden)
        if left ~= nil then icon:SetHiddenText("p", "%.0f", left) else icon:SetText("p", "") end
    else
        icon:SetText("p", "")
    end
end

function Pal:RefreshResources(cfg)
    local VS = self.S
    local r = cfg.resources
    local show = self:On(cfg)

    local now = GetTime()
    local swingActive = VS.swing.duration > 0 and (VS.swing.start + VS.swing.duration) > now
    local swingShow = show and r.swingTimer and (self.preview or (VS.inCombat and (swingActive or self.sample)))
    self.swingBar:SetShown(swingShow or false)
    if swingShow and not self.swingDriver:IsShown() then self.swingDriver:Show() end

    self.manaBar:SetShown(show and r.manaBar or false)
    self.mp5Bar:SetShown(show and r.mp5Bar or false)

    -- Righteous Fury missing (only when RF is known - prot toggle)
    local rfShow = false
    if show and TextOn(self, r, "rfText") then
        if self.preview or self.sample then
            rfShow = true
        else
            local rf = VS.spells.righteousFury
            local name = rf and rf.name
            rfShow = (rf and rf.known and name and not VS.buffs[name:lower()]) and true or false
        end
    end
    self.rfText:SetShown(rfShow)

    local blessShow = false
    if show and TextOn(self, r, "blessingText") then
        if self.preview or self.sample then
            blessShow = true
        else
            local found = false
            for lname in pairs(VS.buffs) do
                if VS.blessingNames and VS.blessingNames[lname] then found = true break end
            end
            blessShow = not found
        end
    end
    self.blessText:SetShown(blessShow)
    RefreshSeal(self, cfg)
end

function Pal:HideAll()
    Engine.HideAll(self)
    if self.sealIcon then self.sealIcon:Hide() end
end

-- Sizes after settings changes (frames persist; only sizes move).
function Pal:ApplySizes()
    if not self.built then return end
    local cfg = self:Store()
    if not cfg then return end
    local a = cfg.auraRow
    for _, icon in pairs(self.auraIcons) do icon:SetSize(a.iconSize or 25, a.iconSize or 25) end
    local r = cfg.resources
    local A, H = self.anchors, self.holders
    -- Holders follow the bar size too: the mover proxy is sized from them.
    if self.swingBar then
        self.swingBar:SetSize(r.swing.w or 316, r.swing.h or 2)
        A.Swing:SetSize(r.swing.w or 316, r.swing.h or 2)
        H.Swing:SetSize(r.swing.w or 316, r.swing.h or 2)
    end
    if self.manaBar then
        self.manaBar:SetSize(r.mana.w or 234, r.mana.h or 4)
        self.mp5Bar:SetSize(r.mana.w or 234, r.mana.h or 4)
        A.Mana:SetSize(r.mana.w or 234, (r.mana.h or 4) * 2 + 2)
        H.Mana:SetSize(r.mana.w or 234, (r.mana.h or 4) * 2 + 2)
    end
    if self.rfText then
        HUD.ApplyFont(self.rfText, r.texts.size or 20, "OUTLINE", "alert")
        HUD.ApplyFont(self.blessText, r.texts.size or 20, "OUTLINE", "alert")
    end
    if self.V2ApplySizes then self:V2ApplySizes(cfg) end
    self:ApplyAnchorPositions()
    self:Refresh()
end

function Pal:TextTick()
    if not (self.sample or self:IsActive()) then return end
    Engine.TextTick(self)
    SealText(self)
end

-- ------------------------------------------------------------
-- the spec defaults on this HUD
-- ------------------------------------------------------------
-- (each only where Class HUD v2 is loaded: the engine asks "is there a hook")
-- A kept save has no spec in force: its rows are the player's own ticks,
-- and nothing a spec turns on by itself (glows, bar extras, the trinket
-- row, the Righteous Fury warning, the icon order) reaches it.
if Engine.V2SpecRole then
function Pal:V2SpecRole()
    local cfg = self:Store()
    if cfg and cfg._specs == "kept" then return nil end
    return Engine.V2SpecRole(self)
end
end

-- A spec's icons in the order its show list names them (the lists above
-- keep the WeakAura's order first, for the saves from before): only where
-- you dragged no order of your own, and never on a kept save.
local function IconKey(icon) return icon and icon.def and icon.def.key end
if Engine.V2Ordered then
function Pal:V2Ordered(row, memo, list)
    local cfg = self:Store()
    local v = cfg and cfg.v2
    local saved = v and type(v.order) == "table" and v.order[row]
    local ord
    if cfg and cfg._specs ~= "kept" and ns.OrderedList and not (type(saved) == "table" and #saved > 0) then
        local role = self.V2SpecRole and self:V2SpecRole() or nil
        ord = role and SHOW_ORDER[role.key] and SHOW_ORDER[role.key][row] or nil
    end
    if not ord then
        memo.palOrd = nil
        return Engine.V2Ordered(self, row, memo, list)
    end
    local c = memo.palOrd
    if c and c.ord == ord and c.n == #list then
        local same = true
        for i = 1, #list do if c.src[i] ~= list[i] then same = false break end end
        if same then return c.out end
    end
    c = c or { src = {} }
    memo.palOrd = c
    c.ord, c.n = ord, #list
    for i = 1, #list do c.src[i] = list[i] end
    for i = #list + 1, #c.src do c.src[i] = nil end
    c.out = ns.OrderedList(list, ord, IconKey)
    return c.out
end
end

-- "Reset to spec defaults": a kept save joins the spec defaults, the
-- reminder texts follow the spec again
if Engine.V2ResetToSpec then
function Pal:V2ResetToSpec()
    local cfg = self:Store()
    if cfg then
        cfg._specs = "on"
        cfg.resources.rfText, cfg.resources.blessingText = nil, nil
    end
    return Engine.V2ResetToSpec(self)
end
end

-- WoW Forever: a spell the game's own list adds stays off a kept save
if Engine.V2MergeCatalogue then
function Pal:V2MergeCatalogue()
    local added = Engine.V2MergeCatalogue(self)
    local cfg = added and self:Store() or nil
    if cfg and cfg._specs == "kept" then
        for _, pair in ipairs({ { cfg.mainRow.hidden, self.def.grid }, { cfg.auraRow.hidden, self.def.buffRow } }) do
            for _, e in ipairs(pair[2] or {}) do
                if e.fromGame and pair[1][e.key] == nil then pair[1][e.key] = true end
            end
        end
    end
    return added
end
end

-- ------------------------------------------------------------
-- the settings preview's sample
-- ------------------------------------------------------------
local SAMPLE_SIZES = { DebuffRow = { 26, 26 }, Swing = { 316, 2 }, Mana = { 234, 10 }, Texts = { 240, 30 }, Aux = { 30, 30 } }
function Pal:NewSample(canvas)
    local s = Engine.NewSample(self, canvas)
    setmetatable(s, Pal)
    -- (the anchors this HUD's own element list names)
    for _, e in ipairs(s:Elements()) do
        if not s.anchors[e.key] then
            local sz = SAMPLE_SIZES[e.key] or { 26, 26 }
            local a = HUD.SampleAnchor(canvas, sz[1], sz[2])
            s.anchors[e.key], s.holders[e.key] = a, a
        end
    end
    s.S.blessingNames = {}
    return s
end

function Pal:FillSample(mode)
    Engine.FillSample(self, mode)
    -- the potion this HUD tracks by default, in the bags
    local WH = ns.WarriorHUD
    local cfg = self:Store()
    local sel = WH and WH.POTION_DROPDOWN and cfg and WH.POTION_DROPDOWN[cfg.mainRow.potionChoice or 1]
    if sel and sel.id then self.S.items[sel.id] = 5 end
end

-- the pieces exactly where the HUD puts them on screen (HUD.RealSample)
function Pal:LayoutSample(cfg)
    local r = cfg.resources
    local on = {
        Main = true,
        AuraRow = cfg.auraRow.enabled ~= false,
        DebuffRow = AnyDebuffOn(self, cfg),
        Swing = r.swingTimer, Mana = r.manaBar or r.mp5Bar,
        Texts = TextOn(self, r, "rfText") or TextOn(self, r, "blessingText"),
        Aux = AuxOn(self, cfg),
    }
    local scale = { Main = cfg.mainRow.scale or 1, AuraRow = cfg.auraRow.scale or 1 }
    if self.V2SampleOn then self:V2SampleOn(on, scale, cfg) end
    local pieces = {}
    for _, e in ipairs(self:Elements()) do
        local a = self.anchors[e.key]
        if a then
            pieces[#pieces + 1] = { a = a, mover = e.mover, store = e.cfg(cfg), scale = scale[e.key] or 1,
                on = on[e.key] and true or false }
        end
    end
    HUD.RealSample(self.canvas, pieces)
end

function Pal:PreviewSpec()
    local spec = Engine.PreviewSpec(self)
    local build = spec.build
    spec.build = function(canvas, P)
        build(canvas, P)
        P.store.view = P.store.sample   -- (the name this page's preview always had)
    end
    return spec
end

-- ------------------------------------------------------------
-- Settings page: General | Look | Text | Animation | Position | Advanced,
-- with the HUD drawn in the preview dock beside it.
-- ------------------------------------------------------------
local Check, SliderPair, CheckGrid = HUD.CheckIndent, HUD.SliderPair, HUD.CheckGrid
local function Px(v) return v .. " px" end

function Pal:Tab_General(L, cfg)
    local def, eng, S = self.def, self, self.S
    local function Refresh() eng:Refresh() end
    L:Card("Paladin HUD")
    L:Desc(def.blurb .. " Paladin characters only.")
    Check(L, "Enable Paladin HUD", cfg.enabled, function(v) eng:SetEnabled(v) end)
    Check(L, "Show every element on screen (test)", eng.preview and true or false, function(v)
        eng.preview = v
        Refresh()
    end, nil, "Forces every enabled piece visible where it sits, to line things up. Not saved.")
    if cfg._specs == "kept" and eng.V2ResetToSpec then
        L:Desc("This HUD is kept exactly as you had it. \"Reset to spec defaults\" (Spec defaults, below) sets it up "
            .. "for your spec: its icons, buffs, your judgements on the target, glows and the trinket row.")
    end
    L:EndCard()

    L:Card("Cooldown grid")
    L:Desc("Untick an icon to remove it from the grid, tick one to add it.")
    CheckGrid(L, def.grid,
        function(g) return g.label end,
        function(g) return not Off(eng, "main", cfg.mainRow.hidden, g) end,
        function(g, v) cfg.mainRow.hidden[g.key] = not v Refresh() end)
    HUD.Label(L, "Potion icon")
    HUD.Dropdown(L, 220, HUD.PotionItems(),
        function() return HUD.PotionLabel(cfg.mainRow.potionChoice) end,
        function(value)
            cfg.mainRow.potionChoice = value
            Refresh()
        end, "Which potion the grid's potion icon tracks. Automatic shows the first one in your "
            .. "bags, in the standard priority order.")
    L:EndCard()

    L:Card("Active buff row")
    Check(L, "Show the active buff row", cfg.auraRow.enabled ~= false, function(v)
        cfg.auraRow.enabled = v
        Refresh()
    end)
    CheckGrid(L, def.buffRow,
        function(b) return b.label or S.auraNames[b.key] or b.key end,
        function(b) return not Off(eng, "buffs", cfg.auraRow.hidden, b) end,
        function(b, v) cfg.auraRow.hidden[b.key] = not v Refresh() end)
    L:EndCard()

    L:Card("Target debuff row")
    L:Desc("Your own judgements and stuns on the current target, with time left.")
    Check(L, "Show the target debuff row", cfg.debuffRow.enabled ~= false, function(v)
        cfg.debuffRow.enabled = v
        Refresh()
    end)
    CheckGrid(L, def.debuffRow,
        function(b) return b.label or S.auraNames[b.key] or b.key end,
        function(b) return not Off(eng, "debuffs", cfg.debuffRow.hidden, b) end,
        function(b, v) cfg.debuffRow.hidden[b.key] = not v Refresh() end)
    L:EndCard()

    L:Card("Bars and reminders")
    local r = cfg.resources
    Check(L, "Swing timer bar (combat only)", r.swingTimer, function(v) r.swingTimer = v Refresh() end)
    Check(L, "Mana bar", r.manaBar, function(v) r.manaBar = v Refresh() end)
    Check(L, "MP5 tick bar (drink / five-second rule)", r.mp5Bar, function(v) r.mp5Bar = v Refresh() end)
    Check(L, "\"Righteous Fury\" missing text", TextOn(eng, r, "rfText"), function(v) r.rfText = v and true or false Refresh() end)
    Check(L, "\"Blessing\" missing text", TextOn(eng, r, "blessingText"), function(v) r.blessingText = v and true or false Refresh() end)
    Check(L, "Active seal icon by the mana bar", r.sealIcon or false, function(v)
        r.sealIcon = v or nil
        Refresh()
        HUD.RefreshPage()
    end, nil, "Your seal and its time left, next to the mana bar.")
    if r.sealIcon then
        HUD.Slider(L, "Seal icon size", 14, 48, r.sealIconSize or SEAL_SIZE, function(v)
            r.sealIconSize = (v ~= SEAL_SIZE) and v or nil
            Refresh()
        end, { width = 240, format = Px })
    end
    L:EndCard()

    L:Card("Trinkets and racial")
    Check(L, "Show the trinket and racial row", AuxOn(eng, cfg), function(v)
        cfg.aux.enabled = v
        if eng.V2AuxOn and V2 then V2.Cfg(cfg, true).aux = v and true or false end
        Refresh()
    end)
    Check(L, "Trinket slot 1", cfg.aux.trinket1, function(v) cfg.aux.trinket1 = v Refresh() end, 16)
    Check(L, "Trinket slot 2", cfg.aux.trinket2, function(v) cfg.aux.trinket2 = v Refresh() end, 16)
    Check(L, "Racial ability", cfg.aux.racial, function(v) cfg.aux.racial = v Refresh() end, 16)
    L:EndCard()
    if self.V2Tab_General then self:V2Tab_General(L, cfg) end
end

local COLOR_LABELS = {
    { "oor", "Out of range tint" }, { "timer", "Timer text" }, { "count", "Count text" },
    { "text", "Reminder text" }, { "barText", "Mana value text" },
    { "mana", "Mana bar" }, { "mp5", "MP5 tick bar" }, { "swing", "Swing timer" },
}

function Pal:Tab_Look(L, cfg)
    local eng = self
    local function Refresh() eng:Refresh() end
    local function Sizes() eng:ApplySizes() end
    local r = cfg.resources
    L:Card("Cooldown grid")
    local rows = cfg.mainRow.rows
    SliderPair(L,
        { "Row 1 icon size", 16, 48, rows[1].w, function(v) rows[1].w, rows[1].h = v, v Refresh() end, Px },
        { "Row 1 icon count", 4, 14, rows[1].limit, function(v) rows[1].limit = v Refresh() end })
    SliderPair(L,
        { "Row 2+ icon size", 16, 48, rows[2].w, function(v)
            rows[2].w, rows[2].h = v, v
            rows[3].w, rows[3].h = v, v
            Refresh()
        end, Px },
        { "Spacing", 0, 12, cfg.mainRow.spacing, function(v) cfg.mainRow.spacing = v Refresh() end, Px })
    L:EndCard()

    L:Card("Rows and bars")
    SliderPair(L,
        { "Active buff icon size", 14, 48, cfg.auraRow.iconSize, function(v) cfg.auraRow.iconSize = v Sizes() end, Px },
        { "Active buff spacing", 0, 12, cfg.auraRow.spacing, function(v) cfg.auraRow.spacing = v Refresh() end, Px })
    SliderPair(L,
        { "Target debuff icon size", 14, 48, cfg.debuffRow.iconSize, function(v) cfg.debuffRow.iconSize = v Sizes() end, Px },
        { "Target debuff spacing", 0, 12, cfg.debuffRow.spacing, function(v) cfg.debuffRow.spacing = v Refresh() end, Px })
    SliderPair(L,
        { "Mana bar width", 100, 500, r.mana.w, function(v) r.mana.w = v Sizes() end, Px },
        { "Mana bar height", 2, 16, r.mana.h, function(v) r.mana.h = v Sizes() end, Px })
    SliderPair(L,
        { "Swing bar width", 100, 500, r.swing.w, function(v) r.swing.w = v Sizes() end, Px },
        { "Swing bar height", 1, 12, r.swing.h or 2, function(v) r.swing.h = v Sizes() end, Px })
    SliderPair(L,
        { "Trinket icon size", 16, 56, cfg.aux.iconSize or 30, function(v) cfg.aux.iconSize = v Refresh() end, Px },
        { "Trinket spacing", 0, 12, cfg.aux.spacing or 4, function(v) cfg.aux.spacing = v Refresh() end, Px })
    L:EndCard()

    L:Card("Colours")
    local entries = {}
    for _, c in ipairs(COLOR_LABELS) do
        local key = c[1]
        entries[#entries + 1] = { c[2],
            get = function() return HUD.Col(cfg.colors[key], COLOR_DEFAULTS[key]) end,
            set = function(rr, g, b, a)
                cfg.colors[key] = { r = rr, g = g, b = b, a = a or 1 }
                eng:ApplyColors()
            end }
    end
    HUD.ColorGrid(L, entries)
    L:EndCard()

    if self.V2Tab_Look then self:V2Tab_Look(L, cfg) end
    HUD.SharedLookCards(L)
end

function Pal:Tab_Text(L, cfg)
    local eng = self
    local r = cfg.resources
    HUD.SharedTextCards(L, { label = "Reminder text", defaultSize = 20, sample = "Righteous Fury",
        getSize = function() return r.texts.size or 20 end,
        setSize = function(v) r.texts.size = v eng:ApplySizes() end })
    if self.V2Tab_Text then self:V2Tab_Text(L, cfg) end
end

function Pal:Tab_Advanced(L, cfg)
    local eng = self
    L:Card("Reset")
    HUD.Button(L, "Reset colours", 150, function()
        cfg.colors = ns.CopySetting(COLOR_DEFAULTS)
        eng:ApplyColors()
        ns.SettingsChanged("reset")
        HUD.RefreshPage()
    end, "Puts this HUD's colours back to the defaults.")
    HUD.ResetLookButton(L)
    L:EndCard()
    if self.V2Tab_Advanced then self:V2Tab_Advanced(L, cfg) end
end

-- ============================================================
-- DEFINE
-- ============================================================
-- The engine reads a save while it defines a class (the utility row's
-- anchor): this HUD's own store answers for that moment too, so the
-- engine's default shape never lands in the paladin's save.
local baseStore = Engine.Store
Engine.Store = function(self)
    if self.def == DEF then return PalStore() end
    return baseStore(self)
end
local eng = HUD.DefineClass(DEF)
Engine.Store = baseStore
setmetatable(eng, Pal)
eng.defaults = DEFAULTS
eng.S.mp5 = eng.S.fsr            -- (the MP5 window's old name)
-- the anchors this HUD's own element list names (frames exist only for paladins)
if select(2, UnitClass("player")) == "PALADIN" then eng:CreateAnchors() end

-- The module as it always was reached (other parts, the tests)
ns.PaladinHUD = ns.PaladinHUD or {}
local PH = ns.PaladinHUD
PH.Engine, PH.LIVE, PH.State = eng, eng, eng.S
PH.MainIconList = DEF.grid
function PH.Store() return PalStore() end
function PH:SetEnabled(on) eng:SetEnabled(on) end
function PH:IsActive() return eng:IsActive() end
PH.Display = {}
function PH.Display:Refresh() eng:Refresh() end
function PH.Display:HideAll() eng:HideAll() end
function PH.Display:ApplySizes() eng:ApplySizes() end
