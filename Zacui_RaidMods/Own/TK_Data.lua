-- TK_Data - the facts ZacUI's own Tempest Keep (The Eye) module is built from.
-- Data only; Own\TK.lua builds the pieces (Own\TBC_Kit.lua, T.Build).
-- Part of ZacUI (Zacui_RaidMods). Sources and conf: see KZ_Data.lua.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on) then return end

-- Kael'thas' four advisors
local ADVISORS = { 20064, 20060, 20062, 20063 }

T.facts.TK = {
    name = "Tempest Keep: The Eye", short = "TK", zone = { 550 }, src = "DEI (instance 550)",
    bosses = {
        { short = "Al'ar", name = "Al'ar", enc = 730, npc = 19514,
          timers = {
            { name = "Melt Armor", spells = { 35410 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, every = 60, gap = 10,
              role = "TANK", prewarn = 5, headsSay = "Taunt soon", src = "WH-NPC (60 s cooldown)", conf = "high" },
            { name = "Dive Bomb", spells = { 35367 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, every = 30, gap = 10,
              src = "WH-NPC (30 s cooldown, phase two)", conf = "high" },
          },
          alerts = {
            { name = "Melt Armor", spells = { 35410 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 5,
              text = "MELT ARMOR - TAUNT", say = "Taunt", src = "WH-NPC" },
            { name = "Flame Quills", spells = { 34229 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 10,
              text = "FLAME QUILLS - JUMP OFF", say = "Jump off", src = "WH-NPC" },
            { name = "Dive Bomb", spells = { 35367 }, gap = 10, text = "DIVE BOMB - PHOENIXES", src = "WH-NPC" },
          },
          onYou = { { name = "Flame Patch", spells = { 35383 }, label = "MOVE", say = "Move", src = "WH-NPC" } },
        },
        { short = "Void Reaver", name = "Void Reaver", enc = 731, npc = 19516,
          alerts = {
            { name = "Pounding", names = { "Pounding" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "POUNDING", src = "IV (name only; no id or timing confirmed)" },
            { name = "Arcane Orb", names = { "Arcane Orb" }, sub = "SPELL_CAST_SUCCESS", gap = 2,
              text = "ARCANE ORB", src = "IV (name only)" },
          },
        },
        { short = "Solarian", name = "High Astromancer Solarian", enc = 732, npc = 18805,
          timers = {
            { id = "SPLIT", name = "Split", first = 50, every = 50, seen = { npcs = { 18925 } }, gap = 20, prewarn = 5, headsSay = "Split soon",
              src = "WH-NPC (every 50 s; set again when her agents appear)", conf = "medium" },
            { id = "PRIESTS", name = "Solarium Priests", seen = { npcs = { 18925 } }, every = 15, gap = 20, autoHide = true,
              src = "WH-NPC (she returns with two priests after 15 s)", conf = "high" },
          },
          alerts = {
            { name = "Wrath of the Astromancer", spells = { 42783 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 2,
              text = "WRATH", me = "WRATH ON YOU - RUN OUT", sayMe = "Run out", src = "WH-NPC" },
            { name = "Agents", seen = { npcs = { 18925 } }, gap = 20, text = "AGENTS - AOE", say = "Agents", src = "WH-NPC" },
          },
          health = { npc = 18805, src = "WH-NPC (voidwalker form at 20%)",
            marks = { { at = 20, text = "VOIDWALKER - FEAR", say = "Voidwalker", soon = true } } },
          onYou = { { name = "Wrath of the Astromancer", spells = { 42783 }, label = "RUN OUT", chat = "Wrath on me!", src = "WH-NPC" } },
          raid = { { name = "Wrath of the Astromancer", spells = { 42783 }, color = { 0.6, 0.3, 1, 0.6 }, src = "WH-NPC" } },
          marks = { { name = "Wrath of the Astromancer", spells = { 42783 }, marks = { 8, 7, 6 }, src = "WH-NPC" } },
        },
        { short = "Kael'thas", name = "Kael'thas Sunstrider", enc = 733, npc = 19622,
          cycles = {
            { id = "WEAPONS", name = "Weapons and advisors", startDeaths = { npcs = ADVISORS, count = 4 },
              src = "IV (weapons two minutes, revived advisors three)", conf = "medium",
              parts = {
                { id = "REVIVE", bar = "Advisors revive", secs = 120, alert = "ADVISORS ARE BACK", say = "Advisors" },
                { id = "ACTIVE", bar = "Kael'thas joins", secs = 180, alert = "KAEL'THAS JOINS", say = "Kael'thas" },
              } },
          },
          timers = {
            { name = "Shock Barrier", spells = { 36815 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, every = 60, gap = 10,
              src = "WH-NPC (every minute)", conf = "high" },
            { name = "Mind Control", spells = { 36797 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, every = 30, gap = 10,
              prewarn = 5, headsSay = "Mind control soon", src = "WH-NPC (two targets every 30 s)", conf = "high" },
            { name = "Gravity Lapse", spells = { 35966 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, every = 30, gap = 20,
              autoHide = true, bar = "Gravity Lapse ends", src = "IV (flight for 30 s)", conf = "medium" },
          },
          alerts = {
            { name = "Pyroblast", spells = { 36819 }, text = "PYROBLAST", say = "Pyro", src = "WH-NPC" },
            { name = "Mind Control", spells = { 36797 }, sub = "SPELL_AURA_APPLIED", target = true, gap = 1,
              text = "MIND CONTROL", src = "WH-NPC" },
            { name = "Gravity Lapse", spells = { 35966 }, gap = 20, text = "GRAVITY LAPSE", say = "Gravity lapse", src = "WH-NPC" },
            { name = "Arcane Disruption", spells = { 36834 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "ARCANE DISRUPTION", src = "WH-NPC" },
          },
          health = { npc = 19622, src = "IV (phase five below 50%)",
            marks = { { at = 50, text = "PHASE 5 - GRAVITY LAPSE", say = "Phase five", soon = true } } },
          raid = { { name = "Mind Control", spells = { 36797 }, color = { 1, 0.3, 1, 0.7 }, src = "WH-NPC" } },
          marks = { { name = "Mind Control", spells = { 36797 }, marks = { 8, 7, 6 }, src = "WH-NPC" } },
        },
    },
}
