-- ZA_Data - the facts ZacUI's own Zul'Aman module is built from.
-- Data only; Own\ZA.lua builds the pieces (Own\TBC_Kit.lua, T.Build).
-- Part of ZacUI (Zacui_RaidMods). Sources and conf: see KZ_Data.lua.
--
-- No encounter ids: none of our sources lists TBC Zul'Aman's (the
-- DungeonEncounterID table stops short of them), so nothing is guessed.
-- The pieces load anywhere in Zul'Aman and wake on ENCOUNTER_START by
-- the boss's name (encNames). The "boss on you" alert's per-boss list
-- needs encounter ids, so Zul'Aman's bosses are not on it.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on) then return end

T.facts.ZA = {
    name = "Zul'Aman", short = "ZA", zone = { 568 }, src = "warcraft.wiki.gg InstanceID (568); encounter ids not confirmed",
    bosses = {
        { short = "Akil'zon", name = "Akil'zon", npc = 23574, encNames = { "Akil'zon" },
          timers = {
            { name = "Electrical Storm", spells = { 43648 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" },
              first = 50, gap = 15, prewarn = 5, headsSay = "Storm soon",
              restart = { { spells = { 43648 }, sub = "SPELL_AURA_REMOVED", secs = 40 } },
              src = "BW (50 s from the pull, 40 after one ends); WH-G says about once a minute", conf = "medium" },
          },
          berserk = { secs = 600, src = "BW (10 minutes)", conf = "medium" },
          casts = { { name = "Electrical Storm", spells = { 43648 }, sub = "SPELL_AURA_APPLIED", secs = 8, text = "Electrical Storm", src = "BW (8 s)" } },
          alerts = {
            { name = "Electrical Storm", spells = { 43648 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 15,
              text = "ELECTRICAL STORM - STACK UNDER", me = "STORM ON YOU", sayMe = "Storm on you", say = "Stack", src = "WH-G" },
          },
          raid = { { name = "Static Disruption", spells = { 44008 }, color = { 0.3, 0.6, 1, 0.6 }, list = true, src = "WH-G" } },
          marks = { { name = "Electrical Storm", spells = { 43648 }, marks = { 8 }, src = "WH-G" } },
        },
        { short = "Nalorakk", name = "Nalorakk", npc = 23576, encNames = { "Nalorakk" },
          berserk = { secs = 600, src = "BW (10 minutes)", conf = "medium" },
          tank = { { name = "Lacerating Slash", spells = { 42395 }, label = "Bleed", src = "WH-G" } },
          cycles = {
            { id = "FORMS", name = "Troll and bear", spells = { 42398 }, loop = true,
              src = "WH-G (troll 45 s, bear 30 s)", conf = "high",
              parts = {
                { id = "BEAR", bar = "Bear form", secs = 45, alert = "BEAR FORM", say = "Bear" },
                { id = "TROLL", bar = "Troll form", secs = 30, alert = "TROLL FORM", say = "Troll" },
              } },
          },
          alerts = {
            { name = "Surge", spells = { 42402 }, subs = { "SPELL_CAST_SUCCESS" }, target = true, gap = 3, text = "SURGE", src = "WH-G" },
            { name = "Deafening Roar", spells = { 42398 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5, text = "SILENCE", src = "WH-G" },
          },
          raid = { { name = "Lacerating Slash", spells = { 42395 }, src = "WH-G" } },
        },
        { short = "Jan'alai", name = "Jan'alai", npc = 23578, encNames = { "Jan'alai" },
          timers = {
            { id = "HATCHERS", name = "Hatchers", first = 12, src = "WH-G (about 12 s after the pull; the gap after is not stated)", conf = "medium" },
            { id = "ENRAGE", name = "Enrage", first = 300, phase = true, src = "BW (5 minutes)", conf = "medium" },
          },
          berserk = { secs = 600, src = "BW (10 minutes)", conf = "medium" },
          casts = { { name = "Fire Bombs", spells = { 42630 }, secs = 12, text = "Fire bombs", src = "BW (12 s)" } },
          alerts = {
            { name = "Fire Bomb", spells = { 42630 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 10,
              text = "FIRE BOMBS - MOVE", say = "Bombs", src = "WH-G" },
            { name = "Flame Breath", spells = { 43140 }, subs = { "SPELL_CAST_START" }, target = true, gap = 3, text = "FLAME BREATH", cast = true, src = "WH-G" },
          },
          health = { npc = 23578, src = "WH-G (all eggs at 35%, enrage at 20%)",
            marks = { { at = 35, text = "ALL EGGS HATCH", say = "Eggs", soon = true }, { at = 20, text = "ENRAGE", say = "Enrage", soon = true } } },
        },
        { short = "Halazzi", name = "Halazzi", npc = 23577, encNames = { "Halazzi" },
          alerts = {
            { name = "Lightning Totem", spells = { 43302 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_SUMMON" }, gap = 5,
              text = "TOTEM - KILL IT", say = "Totem", src = "WH-G" },
            { name = "Transfigure", spells = { 44054 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 10,
              text = "MERGE - AOE", src = "WH-G" },
            { name = "Frenzy", spells = { 43139 }, sub = "SPELL_AURA_APPLIED", gap = 5, text = "FRENZY - TRANQUILIZE", say = "Frenzy", src = "BW" },
          },
          raid = { { name = "Flame Shock", spells = { 43303 }, list = true, src = "WH-G; BW (12 s)" } },
        },
        { short = "Hex Lord", name = "Hex Lord Malacrass", npc = 24239, encNames = { "Hex Lord Malacrass" },
          timers = {
            { name = "Spirit Bolts", spells = { 43382, 43383 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, first = 30, every = 40, gap = 15,
              prewarn = 5, headsSay = "Bolts soon", src = "BW (30 s from the pull, 40 between); WH-G says about every 30", conf = "medium" },
            { name = "Siphon Soul", spells = { 43498, 43501 }, sub = "SPELL_AURA_APPLIED", every = 60, gap = 15, src = "BW (60 s between)", conf = "medium" },
          },
          casts = { { name = "Spirit Bolts", spells = { 43383 }, sub = "SPELL_CAST_SUCCESS", secs = 10, text = "Spirit Bolts", src = "WH-G (10 s channel)" } },
          alerts = {
            { name = "Spirit Bolts", spells = { 43382, 43383 }, gap = 15, text = "SPIRIT BOLTS", say = "Spirit bolts", src = "WH-G; BW (43383)" },
            { name = "Siphon Soul", spells = { 43498, 43501 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 10, text = "SIPHON SOUL", src = "WH-G; BW (43501)" },
            { name = "Heal", spells = { 43548, 43451, 43431 }, sub = "SPELL_CAST_START", gap = 2, text = "INTERRUPT THE HEAL", say = "Interrupt", cast = true, kick = true,
              src = "BW (Healing Wave, Holy Light, Flash Heal)" },
            { name = "Lifebloom", spells = { 43421 }, sub = "SPELL_AURA_APPLIED", gap = 5, text = "LIFEBLOOM - PURGE", src = "BW" },
            { name = "Fire Nova Totem", spells = { 43436 }, sub = "SPELL_SUMMON", gap = 5, text = "FIRE NOVA TOTEM - KILL IT", src = "BW" },
          },
        },
        { short = "Zul'jin", name = "Zul'jin", npc = 23863, encNames = { "Zul'jin" },
          alerts = {
            -- each form shows itself by its first spell
            { name = "Bear Form", spells = { 43095, 43456 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, once = true,
              text = "BEAR FORM - DISPEL PARALYSIS", say = "Bear", src = "WH-G (Creeping Paralysis, Overpower)" },
            { name = "Eagle Form", spells = { 43983, 43121 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED", "SPELL_SUMMON" }, once = true,
              text = "EAGLE FORM - DON'T CAST TOO MUCH", say = "Eagle", src = "WH-G (Energy Storm, Cyclone; at 60%)" },
            { name = "Lynx Form", spells = { 43153, 43150 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, once = true,
              text = "LYNX FORM", say = "Lynx", src = "WH-G (Lynx Rush, Claw Rage)" },
            { name = "Dragonhawk Form", spells = { 43213, 43215 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, once = true,
              text = "DRAGONHAWK FORM - FIRE", say = "Dragonhawk", src = "WH-G (Flame Whirl, Flame Breath)" },
            { name = "Claw Rage", spells = { 43150 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 3, text = "CLAW RAGE", src = "WH-G" },
          },
          timers = {
            { name = "Creeping Paralysis", bar = "Paralysis", spells = { 43095 }, sub = "SPELL_CAST_SUCCESS", every = 27, gap = 5,
              src = "BW (27 s between, bear form)", conf = "medium" },
          },
          casts = { { name = "Creeping Paralysis", spells = { 43095 }, sub = "SPELL_CAST_SUCCESS", secs = 6, text = "Paralysis - dispel", src = "BW (stuns after 6 s)" } },
          onYou = { { name = "Creeping Paralysis", spells = { 43095 }, label = "DISPEL", src = "WH-G" } },
          raid = {
            { name = "Creeping Paralysis", spells = { 43095 }, color = { 0.3, 0.6, 1, 0.6 }, src = "WH-G" },
            { name = "Grievous Throw", spells = { 43093 }, list = true, src = "WH-G" },
          },
        },
    },
}
