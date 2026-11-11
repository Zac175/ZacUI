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
          timers = {
            { name = "Whirlwind", spells = { 33238 }, sub = "SPELL_AURA_APPLIED", first = 59, gap = 10, prewarn = 5, headsSay = "Whirlwind soon",
              src = "BW (59 s from the pull; no interval stated)", conf = "medium" },
            { name = "Arcing Smash", spells = { 39144 }, sub = "SPELL_CAST_SUCCESS", every = 10, role = "TANK", src = "BW (10 s between)", conf = "medium" },
            { name = "Wild Felhunter", bar = "Next felhunter", spells = { 33131 }, sub = "SPELL_CAST_START", every = 50, gap = 10,
              src = "BW (50 s between Olm's summons)", conf = "medium" },
          },
          alerts = {
            { name = "Felhunter", spells = { 33131 }, sub = "SPELL_CAST_START", gap = 10, text = "OLM SUMMONS A FELHUNTER", cast = true, src = "BW" },
            { name = "Power Word: Shield", spells = { 33147 }, sub = "SPELL_AURA_APPLIED", gap = 5,
              text = "BLINDEYE SHIELDED - BREAK IT, THEN INTERRUPT", src = "BW" },
            { name = "Flurry", spells = { 33232 }, sub = "SPELL_CAST_SUCCESS", gap = 20, text = "MAULGAR FLURRY", say = "Flurry", src = "BW (below half health)" },
            { name = "Whirlwind", spells = { 33239 }, subs = { "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, gap = 5,
              text = "WHIRLWIND - MELEE OUT", say = "Whirlwind", src = "WH-G" },
            { name = "Prayer of Healing", spells = { 33152 }, text = "INTERRUPT BLINDEYE", say = "Interrupt", cast = true, kick = true, src = "WH-G" },
            { name = "Heal", spells = { 33144 }, from = { 18836 }, text = "INTERRUPT BLINDEYE'S HEAL", say = "Interrupt", cast = true, kick = true, src = "WH-G" },
          },
          health = { npc = 18831, src = "WH-G (phase two at 50%)",
            marks = { { at = 50, text = "PHASE 2 - CHARGE AND FEAR", say = "Phase two", soon = true } } },
          raid = {
            { name = "Greater Polymorph", spells = { 33173 }, color = { 0.3, 0.6, 1, 0.6 }, list = true, src = "WH-G" },
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
              first = 30, every = 30, gap = 5, src = "WH-NPC, WH-G (every 30 s)", conf = "high" },
            { name = "Ground Slam", spells = { 33525 }, sub = "SPELL_CAST_START", first = 33, gap = 5, prewarn = 5, headsSay = "Ground Slam soon",
              restart = { { spells = { 33654 }, sub = "SPELL_CAST_START", secs = 62 } },
              src = "BW (33 s from the pull, 62 after each Shatter)", conf = "medium" },
            { name = "Shatter", spells = { 33654 }, sub = "SPELL_CAST_START", gap = 5,
              restart = { { spells = { 33525 }, sub = "SPELL_CAST_START", secs = 10 } },
              src = "BW (10 s after a Ground Slam)", conf = "high" },
            { name = "Reverberation", bar = "Silence", spells = { 36297 }, sub = "SPELL_CAST_SUCCESS", first = 102, every = 31, gap = 5,
              src = "BW (102 s from the pull, 31 between)", conf = "medium" },
          },
          alerts = {
            { name = "Growth stacks", spells = { 36300 }, subs = { "SPELL_AURA_APPLIED_DOSE" }, stacks = 7, gap = 5, text = "GROWTH", src = "BW (from 7 stacks)" },
            { name = "Reverberation", spells = { 36297 }, sub = "SPELL_CAST_SUCCESS", gap = 5, text = "SILENCE", say = "Silence", src = "BW" },
            { name = "Ground Slam", spells = { 33525 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "GROUND SLAM - SPREAD", say = "Spread", src = "WH-G" },
            { name = "Shatter", spells = { 33654 }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "SHATTER", src = "WH-G" },
            { name = "Cave In", spells = { 36240 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "CAVE IN", me = "CAVE IN - MOVE", sayMe = "Move", src = "WH-G" },
          },
          onYou = {
            { name = "Cave In", spells = { 36240 }, label = "MOVE", src = "WH-G" },
            { name = "Stoned", spells = { 33652 }, label = "STONED", src = "BW (5 s)" },
          },
          gtfo = { { name = "Cave In", spells = { 36240 }, aura = true, src = "BW" } },
        },
    },
}
