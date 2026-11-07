-- SSC_Data - the facts ZacUI's own Serpentshrine Cavern module is built from.
-- Data only; Own\SSC.lua builds the pieces (Own\TBC_Kit.lua, T.Build).
-- Part of ZacUI (Zacui_RaidMods). Sources and conf: see KZ_Data.lua.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on) then return end

-- Hydross' marks: Wowhead's NPC page and its guide link different ids
-- for the same marks (stacks of one debuff), so they are matched by name.
local MARKS = { "Mark of Hydross", "Mark of Corruption" }

T.facts.SSC = {
    name = "Serpentshrine Cavern", short = "SSC", zone = { 548 }, src = "DEI (instance 548)",
    bosses = {
        { short = "Hydross", name = "Hydross the Unstable", enc = 623, npc = 21216,
          berserk = { secs = 600, src = "WH-NPC (the raid wipes after 10 minutes)", conf = "medium" },
          timers = {
            { name = "Mark", names = MARKS, subs = { "SPELL_AURA_APPLIED", "SPELL_AURA_APPLIED_DOSE" }, every = 15, gap = 5,
              bar = "Next mark", src = "WH-G (a mark stacks every 15 s)", conf = "high" },
          },
          alerts = {
            { name = "Elementals", spells = { 36459 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_SUMMON" }, gap = 5,
              text = "FORM CHANGE - ADDS", say = "Adds", src = "WH-G (four elementals on each switch)" },
            { name = "Vile Sludge", spells = { 38246 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "VILE SLUDGE", me = "VILE SLUDGE ON YOU", sayMe = "Sludge", src = "WH-NPC" },
          },
          raid = {
            { name = "Water Tomb", spells = { 38235 }, color = { 0.3, 0.6, 1, 0.6 }, src = "WH-NPC" },
            { name = "Vile Sludge", spells = { 38246 }, color = { 0.3, 1, 0.3, 0.6 }, src = "WH-NPC" },
          },
        },
        { short = "Lurker", name = "The Lurker Below", enc = 624, npc = 21217,
          cycles = {
            { id = "DIVE", name = "Submerge", loop = true, spells = { 37433 },
              src = "WH-G, IV (up for two minutes, under for one)", conf = "high",
              parts = {
                { id = "SUBMERGE", bar = "Submerge", secs = 120, alert = "SUBMERGED - ADDS", say = "Adds" },
                { id = "EMERGE", bar = "Emerge", secs = 60, alert = "LURKER IS BACK", say = "Lurker up" },
              } },
          },
          alerts = {
            { name = "Spout", spells = { 37433 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 10,
              text = "SPOUT - JUMP IN THE WATER", say = "Spout", src = "WH-NPC" },
          },
        },
        { short = "Leotheras", name = "Leotheras the Blind", enc = 625, npc = 21215,
          alerts = {
            { name = "Whirlwind", spells = { 37641 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, gap = 5,
              text = "WHIRLWIND", say = "Whirlwind", src = "WH-G" },
            { name = "Demon Form", names = { "Metamorphosis" }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, gap = 10,
              text = "DEMON FORM", say = "Demon", src = "name only (no id confirmed)" },
            { name = "Insidious Whisper", spells = { 37676 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 5,
              text = "INNER DEMON", me = "KILL YOUR INNER DEMON", sayMe = "Kill your demon", src = "WH-G" },
          },
          health = { npc = 21215, src = "WH-G (splits at 15%)",
            marks = { { at = 15, text = "SPLIT - TWO BOSSES", say = "Split", soon = true } } },
          onYou = { { name = "Insidious Whisper", spells = { 37676 }, label = "DEMON", src = "WH-G" } },
        },
        { short = "Karathress", name = "Fathom-Lord Karathress", enc = 626, npc = 21214,
          berserk = { secs = 600, src = "WH-G (enrage at 10 minutes)", conf = "high" },
          timers = {
            { name = "Caribdis' Healing Wave", spells = { 38330 }, sub = "SPELL_CAST_START", every = 15, gap = 5, bar = "Healing Wave",
              src = "WH-G (every 15 s)", conf = "medium" },
          },
          alerts = {
            { name = "Healing Wave", spells = { 38330 }, text = "INTERRUPT CARIBDIS", say = "Interrupt", src = "WH-G" },
            { name = "Spitfire Totem", spells = { 38236 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_SUMMON" }, gap = 5,
              text = "SPITFIRE TOTEM - KILL IT", src = "WH-G" },
            { name = "Cataclysmic Bolt", spells = { 38441 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 3, target = true,
              text = "CATACLYSMIC BOLT", src = "WH-G" },
          },
          raid = { { name = "Leeching Throw", spells = { 29436 }, src = "WH-G" } },
        },
        { short = "Morogrim", name = "Morogrim Tidewalker", enc = 627, npc = 21213,
          timers = {
            { name = "Watery Grave", spells = { 38028, 38049 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, every = 30, gap = 10,
              prewarn = 5, headsSay = "Grave", src = "WH-NPC (every 30 s; ids from WH-NPC and WH-G)", conf = "medium" },
            { name = "Earthquake", spells = { 37764 }, every = 45, gap = 10, prewarn = 5, headsSay = "Murlocs soon",
              src = "WH-NPC (every 45 s)", conf = "medium" },
          },
          alerts = {
            { name = "Earthquake", spells = { 37764 }, gap = 10, sub = "SPELL_CAST_SUCCESS", text = "MURLOCS", say = "Murlocs", src = "WH-NPC" },
          },
          health = { npc = 21213, src = "WH-NPC (water globules from 25%)",
            marks = { { at = 25, text = "WATER GLOBULES", say = "Globules", soon = true } } },
          onYou = { { name = "Tidal Wave", spells = { 37730 }, label = "SLOWED", src = "WH-NPC" } },
        },
        { short = "Vashj", name = "Lady Vashj", enc = 628, npc = 21212,
          timers = {
            { id = "TAINTED", name = "Tainted Elemental", seen = { npcs = { 22009 } }, every = 50, gap = 10,
              src = "WH-NPC, WIKI (every 50 s; timed from the first sight of each)", conf = "medium" },
            { id = "STRIDER", name = "Coilfang Strider", seen = { npcs = { 22056 } }, every = 60, gap = 10,
              src = "WH-NPC, WIKI (every 60 s; timed from the first sight)", conf = "medium" },
            { id = "ELITE", name = "Coilfang Elite", seen = { npcs = { 22055 } }, every = 45, gap = 10,
              src = "WH-NPC, WIKI (every 45 s; timed from the first sight)", conf = "medium" },
          },
          alerts = {
            { name = "Tainted Elemental", seen = { npcs = { 22009 } }, gap = 10, text = "TAINTED ELEMENTAL", say = "Tainted", src = "WH-NPC" },
            { name = "Static Charge", spells = { 38280 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "STATIC CHARGE", me = "STATIC CHARGE - RUN OUT", sayMe = "Run out", src = "WH-NPC" },
            { name = "Persuasion", spells = { 38511 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 2,
              text = "MIND CONTROL", src = "WH-G" },
          },
          health = { npc = 21212, src = "WH-NPC (phase two at 70%)",
            marks = { { at = 70, text = "PHASE 2 - GENERATORS", say = "Phase two", soon = true } } },
          onYou = {
            { name = "Static Charge", spells = { 38280 }, label = "RUN OUT", chat = "Static Charge on me!", src = "WH-NPC" },
            { name = "Entangle", spells = { 38316 }, label = "ROOTED", src = "WH-NPC" },
          },
          raid = {
            { name = "Static Charge", spells = { 38280 }, color = { 0.3, 0.6, 1, 0.6 }, src = "WH-NPC" },
            { name = "Entangle", spells = { 38316 }, color = { 0.3, 1, 0.3, 0.6 }, src = "WH-NPC" },
            { name = "Persuasion", spells = { 38511 }, color = { 1, 0.3, 1, 0.7 }, src = "WH-G" },
          },
          marks = { { name = "Persuasion", spells = { 38511 }, marks = { 8, 7, 6 }, src = "WH-G" } },
        },
    },
}
