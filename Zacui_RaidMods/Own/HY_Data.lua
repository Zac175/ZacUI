-- HY_Data - the facts ZacUI's own Battle for Mount Hyjal module is built from.
-- Data only; Own\HY.lua builds the pieces (Own\TBC_Kit.lua, T.Build).
-- Part of ZacUI (Zacui_RaidMods). Sources and conf: see KZ_Data.lua.
-- The trash waves before each boss are not covered.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on) then return end

T.facts.HY = {
    name = "Battle for Mount Hyjal", short = "Hyjal", zone = { 534 }, src = "DEI (instance 534)",
    bosses = {
        { short = "Winterchill", name = "Rage Winterchill", enc = 618, npc = 17767,
          berserk = { secs = 600, src = "BW (10 minutes)", conf = "medium" },
          gtfo = { { name = "Death and Decay", spells = { 31258 }, src = "BW" } },
          alerts = {
            { name = "Icebolt", spells = { 31249 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 2,
              text = "ICEBOLT", src = "WH-G" },
            { name = "Death and Decay", spells = { 31258 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "DEATH AND DECAY", me = "DEATH AND DECAY - MOVE", sayMe = "Move", src = "WH-G" },
          },
          onYou = { { name = "Death and Decay", spells = { 31258 }, label = "MOVE", src = "WH-G" } },
          raid = { { name = "Icebolt", spells = { 31249 }, color = { 0.3, 0.6, 1, 0.6 }, list = true, src = "WH-G" } },
        },
        { short = "Anetheron", name = "Anetheron", enc = 619, npc = 17808,
          berserk = { secs = 600, src = "WH-NPC (after 10 minutes)", conf = "high" },
          timers = {
            { name = "Inferno", spells = { 31299 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, every = 60, gap = 10,
              prewarn = 5, headsSay = "Inferno soon", src = "WH-G (about once a minute)", conf = "medium" },
            { name = "Carrion Swarm", spells = { 31306 }, sub = "SPELL_CAST_SUCCESS", every = 11, gap = 3, src = "BW (11 s between)", conf = "medium" },
            { name = "Sleep", spells = { 31298 }, sub = "SPELL_CAST_SUCCESS", every = 19.5, gap = 5, src = "BW (19.5 s between)", conf = "medium" },
          },
          alerts = {
            { name = "Carrion Swarm", spells = { 31306 }, sub = "SPELL_CAST_SUCCESS", gap = 3, text = "CARRION SWARM", src = "BW" },
            { name = "Sleep", spells = { 31298 }, sub = "SPELL_CAST_SUCCESS", gap = 5, text = "SLEEP", src = "BW" },
            { name = "Inferno", spells = { 31299 }, sub = "SPELL_CAST_START", target = true, gap = 10,
              text = "INFERNO", me = "INFERNO ON YOU - TO THE TANK", sayMe = "Inferno on you", src = "WH-G" },
          },
          raid = { { name = "Sleep", spells = { 20669, 31298 }, list = true, src = "WH-G; BW (31298)" } },
        },
        { short = "Kaz'rogal", name = "Kaz'rogal", enc = 620, npc = 17888,
          timers = {
            { name = "Mark of Kaz'rogal", bar = "Mark", spells = { 31447 }, sub = "SPELL_CAST_START", first = 45, gap = 5, prewarn = 5, headsSay = "Mark soon",
              steps = { 40, 35, 30, 25, 20, 15, 10, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5 },
              src = "BW (45 s from the pull, then 5 s sooner each time down to 5)", conf = "medium" },
          },
          alerts = {
            { name = "Mark of Kaz'rogal", spells = { 31447 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, gap = 10,
              text = "MARK - WATCH YOUR MANA", say = "Mark", src = "WH-G (timing only in player comments, which disagree: no bar)" },
          },
          raid = { { name = "Cripple", spells = { 31477 }, src = "WH-G" } },
          lists = { { name = "Mark of Kaz'rogal", spells = { 31447 }, src = "BW" } },
        },
        { short = "Azgalor", name = "Azgalor", enc = 621, npc = 17842,
          berserk = { secs = 600, src = "BW (10 minutes)", conf = "medium" },
          gtfo = { { name = "Rain of Fire", spells = { 31340 }, src = "BW" } },
          timers = {
            { name = "Howl of Azgalor", bar = "Silence", spells = { 31344 }, sub = "SPELL_CAST_SUCCESS", every = 16, gap = 5,
              src = "BW (16 s between)", conf = "medium" },
            { name = "Doom", spells = { 31347 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, every = 50, gap = 10,
              src = "WH-G (roughly every 50 s)", conf = "medium" },
          },
          alerts = {
            { name = "Doom", spells = { 31347 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 5,
              text = "DOOM", me = "DOOM ON YOU - TO THE TANKS", sayMe = "Doom on you", src = "WH-G" },
            { name = "Howl of Azgalor", spells = { 31344 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "SILENCE", src = "WH-G" },
          },
          onYou = {
            { name = "Doom", spells = { 31347 }, label = "DOOM", chat = "Doom on me!", src = "WH-G" },
            { name = "Rain of Fire", spells = { 31340 }, label = "MOVE", say = "Move", src = "WH-G" },
          },
          raid = { { name = "Doom", spells = { 31347 }, color = { 1, 0.2, 0.2, 0.7 }, list = true, src = "WH-G; BW (19 s)" } },
        },
        { short = "Archimonde", name = "Archimonde", enc = 622, npc = 17968,
          berserk = { secs = 540, src = "WH-G (9 minutes; a comment on the NPC page says 10)", conf = "medium" },
          timers = {
            { name = "Fear", spells = { 31970 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, first = 40, every = 41.5, gap = 10,
              prewarn = 5, headsSay = "Fear soon", src = "WH-G (roughly every 40 s); BW (40 s from the pull, 41.5 between)", conf = "medium" },
          },
          alerts = {
            { name = "Air Burst", spells = { 32014 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, target = true, gap = 3,
              text = "AIR BURST", me = "AIR BURST ON YOU - TEARS", sayMe = "Air burst", src = "WH-G" },
            { name = "Fear", spells = { 31970 }, gap = 10, text = "FEAR", say = "Fear", cast = true, src = "WH-G" },
            { name = "Grip of the Legion", spells = { 31972 }, sub = "SPELL_CAST_SUCCESS", target = true, gap = 2, text = "GRIP - DECURSE", src = "BW" },
            { name = "Protection of Elune", spells = { 38528 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, gap = 30,
              text = "TYRANDE'S SHIELD - ALL IN", src = "WH-G (at 10%)" },
          },
          onYou = {
            { name = "Doomfire", spells = { 31944 }, label = "MOVE", say = "Move", src = "WH-G" },
            { name = "Air Burst", spells = { 32014 }, label = "TEARS", src = "WH-G" },
          },
          raid = { { name = "Grip of the Legion", spells = { 31972 }, color = { 0.7, 0.3, 1, 0.6 }, list = true, src = "WH-G" } },
          gtfo = { { name = "Doomfire", spells = { 31944 }, aura = true, src = "WH-G" } },
        },
    },
}
