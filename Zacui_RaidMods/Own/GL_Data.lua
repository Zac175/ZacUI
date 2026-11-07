-- GL_Data - the facts ZacUI's own Gruul's Lair module is built from.
-- Data only; Own\GL.lua builds the pieces (Own\TBC_Kit.lua, T.Build).
-- Part of ZacUI (Zacui_RaidMods). Sources and conf: see KZ_Data.lua.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on) then return end

T.facts.GL = {
    name = "Gruul's Lair", short = "Gruul's", zone = { 565 }, src = "DEI (instance 565)",
    bosses = {
        { short = "Maulgar", name = "High King Maulgar", enc = 649, npc = 18831,
          alerts = {
            { name = "Whirlwind", spells = { 33239 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, gap = 5,
              text = "WHIRLWIND - MELEE OUT", say = "Whirlwind", src = "WH-G" },
            { name = "Prayer of Healing", spells = { 33152 }, text = "INTERRUPT BLINDEYE", say = "Interrupt", src = "WH-G" },
            { name = "Heal", spells = { 33144 }, from = { 18836 }, text = "INTERRUPT BLINDEYE'S HEAL", say = "Interrupt", src = "WH-G" },
          },
          health = { npc = 18831, src = "WH-G (phase two at 50%)",
            marks = { { at = 50, text = "PHASE 2 - CHARGE AND FEAR", say = "Phase two", soon = true } } },
          raid = {
            { name = "Greater Polymorph", spells = { 33173 }, color = { 0.3, 0.6, 1, 0.6 }, src = "WH-G" },
            { name = "Death Coil", spells = { 33130 }, src = "WH-G" },
            { name = "Dark Decay", spells = { 33129 }, src = "WH-G" },
          },
          plates = {
            { name = "Spell Shield", npcs = { 18832 }, spells = { 33054 }, dur = 30, src = "WH-G (30 s)" },
          },
        },
        { short = "Gruul", name = "Gruul the Dragonkiller", enc = 650, npc = 19044,
          timers = {
            { name = "Growth", spells = { 36300 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED", "SPELL_AURA_APPLIED_DOSE" },
              every = 30, gap = 5, src = "WH-NPC, WH-G (every 30 s)", conf = "high" },
          },
          alerts = {
            { name = "Ground Slam", spells = { 33525 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "GROUND SLAM - SPREAD", say = "Spread", src = "WH-G" },
            { name = "Shatter", spells = { 33654 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "SHATTER", src = "WH-G" },
            { name = "Cave In", spells = { 36240 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "CAVE IN", me = "CAVE IN - MOVE", sayMe = "Move", src = "WH-G" },
          },
          onYou = { { name = "Cave In", spells = { 36240 }, label = "MOVE", src = "WH-G" } },
        },
    },
}
