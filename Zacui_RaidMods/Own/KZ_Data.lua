-- KZ_Data - the facts ZacUI's own Karazhan module is built from: each
-- boss's encounter, the spells it watches, the timings it shows (with
-- where each one comes from) and what it says.
-- Data only; Own\KZ.lua builds the pieces (Own\TBC_Kit.lua, T.Build).
-- Part of ZacUI (Zacui_RaidMods).
--
-- Sources: WH-NPC = the boss's Wowhead TBC page, WH-G = Wowhead's
-- Burning Crusade Classic strategy guide, WIKI = warcraft.wiki.gg,
-- IV = Icy Veins' TBC Classic guide, DEI = warcraft.wiki.gg's
-- DungeonEncounterID table. conf: high (stated plainly by the source),
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
          raid = { { name = "Intangible Presence", spells = { 29833 }, color = { 0.7, 0.3, 1, 0.6 }, src = "WH-NPC" } },
        },
        { short = "Moroes", name = "Moroes", enc = 653, npc = 15687,
          timers = {
            { name = "Vanish", spells = { 29448 }, every = 30, prewarn = 5, headsSay = "Vanish", src = "WIKI (every 30 s); id WH-G", conf = "medium" },
          },
          health = { npc = 15687, src = "WH-G (enrage at 30%)",
            marks = { { at = 30, text = "ENRAGE", say = "Enrage", soon = true } } },
          raid = {
            { name = "Garrote", spells = { 37066 }, src = "WH-G" },
            { name = "Blind", spells = { 34694 }, src = "WH-G" },
          },
        },
        { short = "Maiden", name = "Maiden of Virtue", enc = 654, npc = 16457,
          alerts = {
            { name = "Repentance", spells = { 29511 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "REPENTANCE", say = "Repentance", src = "WH-NPC" },
          },
          raid = { { name = "Holy Fire", spells = { 29522 }, src = "WH-NPC" } },
        },
        -- the Opera: one encounter, three plays
        { short = "Opera", name = "Opera Hall", enc = 655,
          alerts = {
            { name = "Terrifying Howl", spells = { 30752 }, text = "FEAR", say = "Fear", src = "WH-G (Big Bad Wolf)" },
            { name = "Red Riding Hood", spells = { 30753 }, sub = "SPELL_AURA_APPLIED", target = true,
              text = "RED RIDING HOOD", me = "YOU ARE RED RIDING HOOD - RUN", sayMe = "Run", src = "WH-G" },
            { name = "Eternal Affection", spells = { 30878 }, text = "INTERRUPT JULIANNE'S HEAL", say = "Interrupt", src = "WH-G" },
            { name = "Undying Love", spells = { 30951 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "KILL BOTH TOGETHER", say = "Kill both together", src = "WH-G" },
            { name = "Frightened Scream", spells = { 31013 }, text = "FEAR", src = "WH-G (Dorothee)" },
          },
          onYou = {
            { name = "Red Riding Hood", spells = { 30753 }, label = "RUN", say = "Run", src = "WH-G" },
            { name = "Brain Wipe", spells = { 31069 }, label = "SILENCED", src = "WH-G (Strawman)" },
          },
          raid = { { name = "Blinding Passion", spells = { 30890 }, src = "WH-G (Julianne)" } },
        },
        { short = "Curator", name = "The Curator", enc = 656, npc = 15691,
          berserk = { secs = 720, src = "WH-NPC (12 minutes)", conf = "high" },
          timers = {
            { name = "Evocation", spells = { 30254 }, sub = "SPELL_CAST_SUCCESS", every = 20, bar = "Evocation ends", gap = 10, autoHide = true,
              src = "WH-NPC (channels 20 s)", conf = "high" },
          },
          alerts = {
            { name = "Evocation", spells = { 30254 }, sub = "SPELL_CAST_SUCCESS", gap = 10, text = "EVOCATION - BURN", say = "Burn", src = "WH-NPC" },
          },
          health = { npc = 15691, src = "WH-NPC (enrage at 15%)",
            marks = { { at = 15, text = "ENRAGE", say = "Enrage", soon = true } } },
        },
        { short = "Illhoof", name = "Terestian Illhoof", enc = 657, npc = 15688,
          berserk = { secs = 600, src = "WH-NPC (10 minutes)", conf = "high" },
          alerts = {
            { name = "Sacrifice", names = { "Sacrifice" }, sub = "SPELL_AURA_APPLIED", target = true,
              text = "SACRIFICE - KILL THE CHAINS", say = "Chains", src = "WH-NPC (name; its id is not confirmed)" },
            { name = "Broken Pact", spells = { 30065 }, sub = "SPELL_AURA_APPLIED", gap = 10,
              text = "KIL'REK DOWN - BURN THE BOSS", src = "WH-NPC" },
          },
          raid = { { name = "Sacrifice", names = { "Sacrifice" }, src = "WH-NPC" } },
        },
        { short = "Shade of Aran", name = "Shade of Aran", enc = 658, npc = 16524,
          berserk = { secs = 900, src = "WH-NPC (Shadows of Aran after 15 minutes; a comment says 10)", conf = "medium" },
          alerts = {
            { name = "Flame Wreath", spells = { 30004 }, text = "FLAME WREATH - DON'T MOVE", say = "Don't move", src = "WH-NPC" },
            { name = "Arcane Explosion", spells = { 29973 }, text = "ARCANE EXPLOSION - RUN OUT", say = "Run out", src = "WH-NPC" },
            { name = "Blizzard", spells = { 29952 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "BLIZZARD", say = "Blizzard", src = "WH-NPC" },
          },
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
            { name = "Netherbreath", spells = { 38524 }, text = "NETHERBREATH", src = "WH-NPC" },
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
          alerts = {
            { name = "Shadow Nova", spells = { 30852 }, text = "SHADOW NOVA - RUN OUT", say = "Nova", src = "WH-G" },
            { name = "Infernal", spells = { 37277 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_SUMMON" }, gap = 3,
              text = "INFERNAL INCOMING", src = "WH-G" },
            { name = "Enfeeble", spells = { 30843 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 5,
              text = "ENFEEBLE", me = "ENFEEBLED - STAY AWAY FROM NOVA", sayMe = "Enfeebled", src = "WH-G" },
          },
          health = { npc = 15690, src = "WH-G (phase two at 60%, three at 30%)",
            marks = { { at = 60, text = "PHASE 2", say = "Phase two", soon = true }, { at = 30, text = "PHASE 3 - AXES", say = "Phase three", soon = true } } },
          onYou = {
            { name = "Enfeeble", spells = { 30843 }, label = "ENFEEBLED", src = "WH-G" },
            { name = "Amplify Damage", spells = { 39095 }, label = "AMPLIFY", src = "WH-G" },
          },
          raid = { { name = "Shadow Word: Pain", spells = { 30854 }, color = { 0.6, 0.2, 0.9, 0.6 }, src = "WH-G" } },
        },
        { short = "Nightbane", name = "Nightbane", enc = 662, npc = 17225,
          alerts = {
            { name = "Bellowing Roar", spells = { 36922 }, text = "FEAR", say = "Fear", src = "WH-G" },
            { name = "Rain of Bones", spells = { 37098 }, text = "RAIN OF BONES - SKELETONS", say = "Skeletons", src = "WH-G" },
            { name = "Charred Earth", spells = { 30129 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "CHARRED EARTH", me = "CHARRED EARTH - MOVE", sayMe = "Move", src = "WH-G" },
          },
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
