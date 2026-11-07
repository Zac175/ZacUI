-- ML_Data - the facts ZacUI's own Magtheridon's Lair module is built from.
-- Data only; Own\ML.lua builds the pieces (Own\TBC_Kit.lua, T.Build).
-- Part of ZacUI (Zacui_RaidMods). Sources and conf: see KZ_Data.lua.
--
-- The encounter starts with the channelers; Magtheridon breaks free two
-- minutes later. The timings below are from that start (Wowhead's
-- numbers are "after activation": +120 s).
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on) then return end

T.facts.ML = {
    name = "Magtheridon's Lair", short = "Mag", zone = { 544 }, src = "DEI (instance 544)",
    bosses = {
        { short = "Magtheridon", name = "Magtheridon", enc = 651, npc = 17257,
          berserk = { secs = 1320, src = "WH-NPC (22 minutes from the start of the encounter)", conf = "medium" },
          timers = {
            { id = "FREE", name = "Magtheridon free", first = 120, prewarn = 10, heads = "Magtheridon free", headsSay = "Magtheridon free soon",
              phase = true, src = "WH-NPC (phase one lasts two minutes)", conf = "high" },
            { name = "Blast Nova", spells = { 30616 }, sub = "SPELL_CAST_START", first = 180, every = 60, prewarn = 10,
              heads = "Blast Nova", headsSay = "Cubes soon", gap = 10,
              src = "WH-NPC (first a minute after he is free, then every 60 s)", conf = "high" },
            { name = "Quake", spells = { 30571 }, first = 160, src = "WH-NPC (first 40 s after he is free; no repeat stated)", conf = "medium" },
          },
          alerts = {
            { name = "Blast Nova", spells = { 30616 }, gap = 10, text = "BLAST NOVA - CLICK THE CUBES", say = "Cubes", src = "WH-NPC" },
            { name = "Dark Mending", spells = { 30528 }, text = "INTERRUPT THE CHANNELER", src = "WH-NPC" },
          },
          health = { npc = 17257, src = "WH-NPC (the ceiling comes down at 30%)",
            marks = { { at = 30, text = "CAVE-INS", say = "Cave ins", soon = true } } },
        },
    },
}
