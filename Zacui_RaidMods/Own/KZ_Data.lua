-- KZ_Data - the facts ZacUI's own Karazhan module is built from: each
-- boss's encounter, the spells it watches, the timings it shows (with
-- where each one comes from) and what it says.
-- Data only; Own\KZ.lua builds the pieces (Own\TBC_Kit.lua, T.Build).
-- Part of ZacUI (Zacui_RaidMods).
--
-- Sources: WH-NPC = the boss's Wowhead TBC page, WH-G = Wowhead's
-- Burning Crusade Classic strategy guide, WIKI = warcraft.wiki.gg,
-- IV = Icy Veins' TBC Classic guide, DEI = warcraft.wiki.gg's
-- DungeonEncounterID table, BW = the timings and spell ids the BigWigs
-- Burning Crusade module uses (numbers only, read 2026-11-10). conf: high (stated plainly by the source),
-- medium (stated as "about"/"roughly", or by one source against
-- another), low (player reports only). A timing no source states is
-- left out: the call-out ships, the bar does not.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on) then return end

T.facts.KZ = {
    name = "Karazhan", short = "Kara", zone = { 532 }, src = "DEI (instance 532)",
    bosses = {
        { short = "Attumen", name = "Attumen the Huntsman", enc = 652, npc = 15550,
          timers = {
            { name = "Intangible Presence", spells = { 29833 }, every = 30, bar = "Curse",
              src = "WH-NPC", conf = "medium" },
          },
          alerts = {
            { name = "Mount", spells = { 29770 }, sub = "SPELL_CAST_SUCCESS", text = "ATTUMEN MOUNTS - AGGRO RESET", say = "Mounted", src = "WH-NPC" },
          },
          health = { npc = 16151, src = "WH-NPC (Midnight 95%, mount at 25%)",
            marks = { { at = 95, text = "ATTUMEN JOINS" }, { at = 25, text = "MOUNT AT 25%", soon = true } } },
          raid = { { name = "Intangible Presence", spells = { 29833 }, color = { 0.7, 0.3, 1, 0.6 }, list = true, src = "WH-NPC" } },
        },
        { short = "Moroes", name = "Moroes", enc = 653, npc = 15687,
          timers = {
            { name = "Vanish", spells = { 29448 }, sub = "SPELL_AURA_APPLIED", first = 35, every = 35, prewarn = 5, headsSay = "Vanish",
              src = "BW (35 s from the pull and between); WIKI says 30", conf = "medium" },
          },
          alerts = {
            { name = "Gouge", spells = { 29425 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 3,
              text = "GOUGE", me = "GOUGED", say = "Gouge", src = "BW (6 s)" },
            { name = "Frenzy", spells = { 37023 }, sub = "SPELL_AURA_APPLIED", gap = 10, text = "MOROES ENRAGED", say = "Enrage", src = "BW" },
          },
          health = { npc = 15687, src = "WH-G (enrage at 30%)",
            marks = { { at = 30, text = "ENRAGE", say = "Enrage", soon = true } } },
          tank = { { name = "Gouge", spells = { 29425 }, label = "Gouged", src = "BW" } },
          raid = {
            { name = "Garrote", spells = { 37066 }, list = true, src = "WH-G" },
            { name = "Blind", spells = { 34694 }, src = "WH-G" },
          },
        },
        { short = "Maiden", name = "Maiden of Virtue", enc = 654, npc = 16457,
          timers = {
            { name = "Repentance", spells = { 29511 }, sub = "SPELL_CAST_START", first = 30, every = 33, prewarn = 5, headsSay = "Repentance",
              src = "BW (29.7 s from the pull, 33 between)", conf = "medium" },
          },
          alerts = {
            { name = "Repentance", spells = { 29511 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "REPENTANCE", say = "Repentance", src = "WH-NPC" },
          },
          raid = { { name = "Holy Fire", spells = { 29522 }, list = true, src = "WH-NPC" } },
        },
        -- the Opera: one encounter, three plays
        { short = "Opera", name = "Opera Hall", enc = 655,
          alerts = {
            { name = "Terrifying Howl", spells = { 30752 }, text = "FEAR", say = "Fear", src = "WH-G (Big Bad Wolf)" },
            { name = "Red Riding Hood", spells = { 30753 }, sub = "SPELL_AURA_APPLIED", target = true,
              text = "RED RIDING HOOD", me = "YOU ARE RED RIDING HOOD - RUN", sayMe = "Run", src = "WH-G" },
            { name = "Eternal Affection", spells = { 30878 }, text = "INTERRUPT JULIANNE'S HEAL", say = "Interrupt", cast = true, kick = true, src = "WH-G; BW" },
            { name = "Undying Love", spells = { 30951 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "KILL BOTH TOGETHER", say = "Kill both together", src = "WH-G" },
            { name = "Devotion", spells = { 30887 }, sub = "SPELL_AURA_APPLIED", gap = 5, text = "JULIANNE: DEVOTION - DISPEL", src = "BW (10 s)" },
            { name = "Daring", spells = { 30841 }, sub = "SPELL_AURA_APPLIED", gap = 5, text = "ROMULO: DARING - DISPEL", src = "BW (8 s)" },
            { name = "Frightened Scream", spells = { 31013 }, text = "FEAR", src = "WH-G (Dorothee)" },
            { name = "Chain Lightning", spells = { 32337 }, sub = "SPELL_CAST_START", gap = 2, text = "CRONE: CHAIN LIGHTNING", cast = 2, src = "BW (2 s cast)" },
          },
          onYou = {
            { name = "Red Riding Hood", spells = { 30753 }, label = "RUN", say = "Run", src = "WH-G" },
            { name = "Brain Wipe", spells = { 31069 }, label = "SILENCED", src = "WH-G (Strawman)" },
          },
          tank = { { name = "Poisoned Thrust", spells = { 30822 }, label = "Stats down", src = "BW (Romulo, stacks)" } },
          raid = { { name = "Blinding Passion", spells = { 30890 }, src = "WH-G (Julianne)" } },
        },
        { short = "Curator", name = "The Curator", enc = 656, npc = 15691,
          berserk = { secs = 600, src = "BW (10 minutes); WH-NPC says 12 - the earlier one is shown", conf = "medium" },
          timers = {
            { name = "Evocation", spells = { 30254 }, sub = "SPELL_CAST_SUCCESS", first = 114, every = 115, gap = 10, prewarn = 10, headsSay = "Evocation soon",
              src = "BW (114 s from the pull, 115 between)", conf = "medium" },
          },
          casts = {
            { name = "Evocation", spells = { 30254 }, sub = "SPELL_CAST_SUCCESS", secs = 20, text = "Evocation - burn", src = "WH-NPC (channels 20 s)" },
          },
          alerts = {
            { name = "Evocation", spells = { 30254 }, sub = "SPELL_CAST_SUCCESS", gap = 10, text = "EVOCATION - BURN", say = "Burn", src = "WH-NPC" },
            { name = "Arcane Infusion", spells = { 30403 }, sub = "SPELL_CAST_SUCCESS", gap = 10, text = "CURATOR ENRAGED", say = "Enrage", src = "BW" },
          },
          health = { npc = 15691, src = "WH-NPC (enrage at 15%)",
            marks = { { at = 15, text = "ENRAGE", say = "Enrage", soon = true } } },
        },
        { short = "Illhoof", name = "Terestian Illhoof", enc = 657, npc = 15688,
          berserk = { secs = 600, src = "WH-NPC (10 minutes)", conf = "high" },
          timers = {
            { name = "Sacrifice", spells = { 30115 }, sub = "SPELL_CAST_SUCCESS", first = 30, src = "BW (30.5 s from the pull; no interval stated)", conf = "medium" },
            { name = "Broken Pact", bar = "Kil'rek dead", restart = { { spells = { 30065 }, sub = "SPELL_AURA_APPLIED", secs = 41 } },
              src = "BW (41 s)", conf = "medium" },
          },
          alerts = {
            { name = "Sacrifice", spells = { 30115 }, names = { "Sacrifice" }, sub = "SPELL_AURA_APPLIED", target = true,
              text = "SACRIFICE - KILL THE CHAINS", say = "Chains", src = "WH-NPC; id BW" },
            { name = "Broken Pact", spells = { 30065 }, sub = "SPELL_AURA_APPLIED", gap = 10,
              text = "KIL'REK DOWN - BURN THE BOSS", src = "WH-NPC" },
          },
          raid = { { name = "Sacrifice", spells = { 30115 }, names = { "Sacrifice" }, list = true, src = "WH-NPC; id BW" } },
        },
        { short = "Shade of Aran", name = "Shade of Aran", enc = 658, npc = 16524,
          berserk = { secs = 900, src = "WH-NPC (Shadows of Aran after 15 minutes; a comment says 10)", conf = "medium" },
          alerts = {
            { name = "Flame Wreath", spells = { 30004 }, text = "FLAME WREATH - DON'T MOVE", say = "Don't move", cast = 5, src = "WH-NPC; BW (5 s cast)" },
            { name = "Arcane Explosion", spells = { 29973 }, text = "ARCANE EXPLOSION - RUN OUT", say = "Run out", cast = 10, src = "WH-NPC; BW (10 s cast)" },
            { name = "Blizzard", spells = { 29952, 29969 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "BLIZZARD", say = "Blizzard", src = "WH-NPC; BW (29969)" },
            { name = "Mass Polymorph", spells = { 29963 }, sub = "SPELL_CAST_START", gap = 10, text = "ARAN DRINKS - PYROBLAST AFTER", say = "Pyroblast soon", src = "BW" },
            { name = "Water Elementals", spells = { 29962 }, sub = "SPELL_CAST_SUCCESS", gap = 10, text = "WATER ELEMENTALS", src = "BW" },
            { name = "Magnetic Pull", spells = { 29979 }, sub = "SPELL_CAST_SUCCESS", gap = 5, text = "PULLED IN - RUN OUT", src = "BW" },
          },
          casts = {
            { name = "Blizzard", spells = { 29969 }, secs = 36, text = "Blizzard", src = "BW (36 s)" },
            { name = "Drinking", spells = { 29963 }, secs = 15, text = "Drinking - Pyroblast after", src = "BW (15 s)" },
          },
          gtfo = { { name = "Blizzard", spells = { 29951 }, src = "BW" } },
          health = { npc = 16524, src = "WH-NPC (water elementals at 40%)",
            marks = { { at = 40, text = "ELEMENTALS", say = "Elementals", soon = true } } },
          raid = { { name = "Chains of Ice", spells = { 29991 }, src = "WH-NPC" } },
        },
        { short = "Netherspite", name = "Netherspite", enc = 659, npc = 15689,
          berserk = { secs = 540, src = "WH-NPC (9 minutes)", conf = "high" },
          cycles = {
            { id = "PHASES", name = "Portals and banish", spells = { 30523 }, loop = true,
              src = "WH-NPC (portals 60 s, banish about 30 s, can run longer)", conf = "medium",
              parts = {
                { id = "BANISH", bar = "Banish phase", secs = 60, alert = "BANISH - NETHERBREATH", say = "Banish" },
                { id = "PORTAL", bar = "Portal phase", secs = 30, alert = "PORTALS - TAKE THE BEAMS", say = "Portals" },
              } },
          },
          alerts = {
            { name = "Netherbreath", spells = { 38523, 38524 }, text = "NETHERBREATH", cast = 2.5, src = "WH-NPC; BW (38523, 2.5 s cast)" },
            { name = "Void Zone", spells = { 37063 }, sub = "SPELL_CAST_SUCCESS", gap = 3, text = "VOID ZONE", src = "BW" },
          },
          -- the beams: who stands in which, and how many stacks
          lists = {
            { name = "Red beam", spells = { 30421 }, stacks = true, listColor = { 1, 0.3, 0.3, 1 }, src = "BW (Perseverence)" },
            { name = "Green beam", spells = { 30422 }, stacks = true, listColor = { 0.3, 1, 0.4, 1 }, src = "BW (Serenity)" },
            { name = "Blue beam", spells = { 30423 }, stacks = true, listColor = { 0.35, 0.6, 1, 1 }, src = "BW (Dominance)" },
          },
        },
        { short = "Chess", name = "Chess Event", enc = 660,
          alerts = {
            { name = "Fury of Medivh", spells = { 39343 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 3,
              text = "MEDIVH: FIRE ON THE BOARD", say = "Fire", src = "WH-G" },
            { name = "Hand of Medivh", spells = { 39339 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 3,
              text = "MEDIVH CHEATS", src = "WH-G" },
          },
        },
        { short = "Prince", name = "Prince Malchezaar", enc = 661, npc = 15690,
          timers = {
            { name = "Enfeeble", spells = { 30843 }, sub = "SPELL_CAST_SUCCESS", first = 30, every = 30, stopPhase = 2, prewarn = 5, headsSay = "Enfeeble",
              src = "BW (30 s from the pull, 30 between; none in phase three)", conf = "medium" },
            { name = "Shadow Nova", spells = { 30852 }, sub = "SPELL_CAST_SUCCESS", first = 33, every = 29, gap = 5,
              phases = { [2] = { secs = 17, every = 16 } },
              src = "BW (33.5 s from the pull, 29 after each; phase three: 17, then 16)", conf = "medium" },
          },
          alerts = {
            { name = "Shadow Nova", spells = { 30852 }, text = "SHADOW NOVA - RUN OUT", say = "Nova", cast = 2, src = "WH-G; BW (2 s cast)" },
            { name = "Infernal", spells = { 37277, 30834 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_SUMMON" }, gap = 3,
              text = "INFERNAL INCOMING", src = "WH-G; BW (30834)" },
            { name = "Enfeeble", spells = { 30843 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 5,
              text = "ENFEEBLE", me = "ENFEEBLED - STAY AWAY FROM NOVA", sayMe = "Enfeebled", src = "WH-G" },
          },
          health = { npc = 15690, src = "WH-G (phase two at 60%, three at 30%)",
            marks = { { at = 60, text = "PHASE 2", say = "Phase two", soon = true }, { at = 30, text = "PHASE 3 - AXES", say = "Phase three", soon = true } } },
          onYou = {
            { name = "Enfeeble", spells = { 30843 }, label = "ENFEEBLED", src = "WH-G" },
            { name = "Amplify Damage", spells = { 39095 }, label = "AMPLIFY", src = "WH-G" },
          },
          lists = { { name = "Enfeeble", spells = { 30843 }, src = "BW (9 s)" } },
          raid = { { name = "Shadow Word: Pain", spells = { 30854 }, color = { 0.6, 0.2, 0.9, 0.6 }, src = "WH-G" } },
        },
        { short = "Nightbane", name = "Nightbane", enc = 662, npc = 17225,
          timers = {
            { name = "Bellowing Roar", bar = "Fear", spells = { 36922 }, sub = "SPELL_CAST_START", every = 37, prewarn = 5, headsSay = "Fear soon",
              src = "BW (37 s between; none stated from the pull)", conf = "medium" },
          },
          alerts = {
            { name = "Bellowing Roar", spells = { 36922 }, text = "FEAR", say = "Fear", cast = 2.5, src = "WH-G; BW (2.5 s cast)" },
            { name = "Rain of Bones", spells = { 37098 }, text = "RAIN OF BONES - SKELETONS", say = "Skeletons", src = "WH-G" },
            { name = "Charred Earth", spells = { 30129 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "CHARRED EARTH", me = "CHARRED EARTH - MOVE", sayMe = "Move", src = "WH-G" },
          },
          casts = { { name = "Rain of Bones", spells = { 37098 }, sub = "SPELL_CAST_SUCCESS", secs = 11, text = "Rain of Bones", src = "BW (11 s)" } },
          gtfo = { { name = "Charred Earth", spells = { 30129 }, src = "BW" } },
          health = { npc = 17225, src = "WIKI, WH-G (air phases at 75, 50 and 25%)",
            marks = { { at = 75, text = "AIR PHASE", say = "Air phase", soon = true }, { at = 50, text = "AIR PHASE", say = "Air phase", soon = true },
                      { at = 25, text = "AIR PHASE", say = "Air phase", soon = true } } },
          onYou = { { name = "Charred Earth", spells = { 30129 }, label = "MOVE", src = "WH-G" } },
          raid = {
            { name = "Distracting Ash", spells = { 30130 }, src = "WH-G" },
            { name = "Smoking Blast", spells = { 30128 }, src = "WH-G" },
          },
        },
    },
}
