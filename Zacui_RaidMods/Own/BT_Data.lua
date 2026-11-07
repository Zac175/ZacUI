-- BT_Data - the facts ZacUI's own Black Temple module is built from.
-- Data only; Own\BT.lua builds the pieces (Own\TBC_Kit.lua, T.Build).
-- Part of ZacUI (Zacui_RaidMods). Sources and conf: see KZ_Data.lua.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on) then return end

local COUNCIL = { 22949, 22950, 22951, 22952 }

T.facts.BT = {
    name = "Black Temple", short = "BT", zone = { 564 }, src = "DEI (instance 564)",
    bosses = {
        { short = "Naj'entus", name = "High Warlord Naj'entus", enc = 601, npc = 22887,
          berserk = { secs = 480, src = "WH-G (8 minutes)", conf = "high" },
          alerts = {
            { name = "Impaling Spine", spells = { 39837 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 2,
              text = "SPINE", me = "SPINE ON YOU", sayMe = "Spine", src = "WH-G" },
            { name = "Tidal Shield", spells = { 39872 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, gap = 10,
              text = "TIDAL SHIELD - THROW A SPINE", say = "Shield", src = "WH-G" },
          },
          onYou = { { name = "Impaling Spine", spells = { 39837 }, label = "SPINE", src = "WH-G" } },
          raid = { { name = "Impaling Spine", spells = { 39837 }, src = "WH-G" } },
        },
        { short = "Supremus", name = "Supremus", enc = 602, npc = 22898,
          cycles = {
            { id = "PHASES", name = "Tank and kite phases", spells = { 40265 }, loop = true,
              src = "WH-G (about a minute each way)", conf = "medium",
              parts = {
                { id = "KITE", bar = "Kite phase", secs = 60, alert = "KITE PHASE - SPREAD", say = "Kite" },
                { id = "TANK", bar = "Tank phase", secs = 60, alert = "TANK PHASE", say = "Tank phase" },
              } },
          },
        },
        { short = "Akama", name = "Shade of Akama", enc = 603, npc = 22841,
          alerts = {
            { name = "Chain Heal", spells = { 42027 }, text = "INTERRUPT THE SPIRITBINDER", src = "WH-G" },
          },
          raid = { { name = "Debilitating Poison", spells = { 41978 }, src = "WH-G" } },
        },
        { short = "Teron", name = "Teron Gorefiend", enc = 604, npc = 22871,
          timers = {
            { name = "Shadow of Death", spells = { 40251 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, every = 30, gap = 10,
              src = "WH-G (every 30 s)", conf = "high" },
          },
          alerts = {
            { name = "Shadow of Death", spells = { 40251 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 5,
              text = "SHADOW OF DEATH", me = "SHADOW OF DEATH ON YOU - 55 SECONDS", sayMe = "Shadow of death on you", src = "WH-G" },
          },
          onYou = { { name = "Shadow of Death", spells = { 40251 }, label = "SHADOW", chat = "Shadow of Death on me!", src = "WH-G (dies after 55 s)" } },
          raid = {
            { name = "Shadow of Death", spells = { 40251 }, color = { 0.6, 0.2, 0.9, 0.7 }, src = "WH-G" },
            { name = "Crushing Shadows", spells = { 40243 }, src = "WH-G" },
            { name = "Incinerate", spells = { 40239 }, src = "WH-G" },
          },
          marks = { { name = "Shadow of Death", spells = { 40251 }, marks = { 8, 7, 6 }, src = "WH-G" } },
        },
        { short = "Gurtogg", name = "Gurtogg Bloodboil", enc = 605, npc = 22948,
          berserk = { secs = 600, src = "WH-G (enrage at 10 minutes)", conf = "high" },
          timers = {
            { name = "Fel Rage", spells = { 40604 }, sub = "SPELL_AURA_APPLIED", every = 30, gap = 20, autoHide = true, bar = "Fel Rage ends",
              phase = true, src = "WH-G (lasts 30 s; the gap before it is given as 55 and as 90 s, so no bar to it)", conf = "high" },
          },
          alerts = {
            { name = "Fel Rage", spells = { 40604 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 20,
              text = "FEL RAGE", me = "FEL RAGE ON YOU", sayMe = "Fel rage on you", src = "WH-G" },
          },
          onYou = { { name = "Fel Rage", spells = { 40604 }, label = "FEL RAGE", src = "WH-G" } },
          raid = { { name = "Bloodboil", spells = { 42005 }, src = "WH-G" } },
          marks = { { name = "Fel Rage", spells = { 40604 }, marks = { 8 }, src = "WH-G" } },
        },
        { short = "Reliquary", name = "Reliquary of Souls", enc = 606, npc = 22856,
          timers = {
            { name = "Suffering Enrage", spells = { 41305 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, every = 45, gap = 10,
              prewarn = 5, headsSay = "Enrage soon", bar = "Enrage", src = "WH-G (roughly every 45 s, 15 s long; the first only in a comment, so the bar starts after the first)", conf = "medium" },
          },
          alerts = {
            { name = "Rune Shield", spells = { 41431 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, gap = 5,
              text = "RUNE SHIELD - PURGE", src = "WH-G" },
            { name = "Deaden", spells = { 41410 }, text = "DEADEN - INTERRUPT", say = "Interrupt", src = "WH-G" },
            { name = "Spirit Shock", spells = { 41426 }, text = "SPIRIT SHOCK - INTERRUPT", src = "WH-G" },
            { name = "Seethe", spells = { 41520 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, gap = 5,
              text = "SEETHE - STOP DPS", src = "WH-G" },
          },
          onYou = { { name = "Spite", spells = { 41377 }, label = "SPITE", src = "WH-G" } },
        },
        { short = "Shahraz", name = "Mother Shahraz", enc = 607, npc = 22947,
          alerts = {
            { name = "Fatal Attraction", spells = { 41001 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 5,
              text = "FATAL ATTRACTION", me = "FATAL ATTRACTION - RUN APART", sayMe = "Run apart", src = "WH-G" },
            { name = "Silencing Shriek", spells = { 40823 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "SILENCE", src = "WH-G" },
          },
          onYou = { { name = "Fatal Attraction", spells = { 41001 }, label = "RUN APART", src = "WH-G" } },
          raid = { { name = "Fatal Attraction", spells = { 41001 }, color = { 1, 0.3, 0.6, 0.7 }, src = "WH-G" } },
          marks = { { name = "Fatal Attraction", spells = { 41001 }, marks = { 8, 7, 6 }, src = "WH-G" } },
        },
        { short = "Council", name = "The Illidari Council", enc = 608, npc = 22951,
          timers = {
            { name = "Vanish", spells = { 41476 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, every = 60, gap = 10,
              src = "WH-G (about every 60 s)", conf = "medium" },
          },
          alerts = {
            { name = "Circle of Healing", spells = { 41455 }, text = "INTERRUPT CIRCLE OF HEALING", say = "Interrupt", src = "WH-G" },
            { name = "Divine Wrath", spells = { 41472 }, text = "INTERRUPT DIVINE WRATH", src = "WH-G" },
            { name = "Vanish", spells = { 41476 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, gap = 10,
              text = "VERAS VANISHED", src = "WH-G" },
          },
          raid = { { name = "Deadly Poison", spells = { 41485 }, color = { 0.3, 1, 0.3, 0.6 }, src = "WH-G" } },
          plates = {
            { name = "Blessing of Spell Warding", npcs = COUNCIL, spells = { 41451 }, dur = 15, src = "WH-G (15 s)" },
            { name = "Blessing of Protection", npcs = COUNCIL, spells = { 41450 }, dur = 15, src = "WH-G (15 s)" },
          },
        },
        { short = "Illidan", name = "Illidan Stormrage", enc = 609, npc = 22917,
          cycles = {
            { id = "DEMON", name = "Demon form", spells = { 41117 }, loop = true,
              startDeaths = { npcs = { 22997 }, count = 2 }, stopOn = { "WA_TBC_PHASE_BT_ILLIDAN" },
              src = "WH-G (a minute each way after the Flames fall, until 30%)", conf = "medium",
              parts = {
                { id = "TO_DEMON", bar = "Demon form", secs = 60, alert = "DEMON FORM - SPREAD", say = "Demon form" },
                { id = "TO_NORMAL", bar = "Normal form", secs = 60, alert = "ILLIDAN LANDS", say = "Normal form" },
              } },
          },
          alerts = {
            { name = "Shear", spells = { 41032 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 3, text = "SHEAR", src = "WH-G" },
            { name = "Parasitic Shadowfiend", spells = { 41917 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "PARASITE", me = "PARASITE ON YOU - STAY AWAY", sayMe = "Parasite", src = "WH-G" },
            { name = "Eye Blast", spells = { 40018 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 10,
              text = "EYE BLAST", say = "Eye blast", src = "WH-G" },
            { name = "Shadow Demons", spells = { 41117 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 10,
              text = "SHADOW DEMONS - KILL THEM", say = "Demons", src = "WH-G" },
            { name = "Dark Barrage", spells = { 40585 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 3, text = "DARK BARRAGE", src = "WH-G" },
          },
          health = { npc = 22917, src = "WH-G (phase two at 65%, Maiev at 30%)",
            marks = { { at = 65, text = "PHASE 2 - FLAMES", say = "Phase two", soon = true }, { at = 30, text = "MAIEV - TRAPS", say = "Maiev", soon = true } } },
          onYou = {
            { name = "Parasitic Shadowfiend", spells = { 41917 }, label = "PARASITE", src = "WH-G" },
            { name = "Agonizing Flames", spells = { 40932 }, label = "FLAMES", src = "WH-G" },
          },
          raid = {
            { name = "Parasitic Shadowfiend", spells = { 41917 }, color = { 0.6, 0.2, 0.9, 0.7 }, src = "WH-G" },
            { name = "Dark Barrage", spells = { 40585 }, src = "WH-G" },
          },
        },
    },
}
