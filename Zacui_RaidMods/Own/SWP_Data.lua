-- SWP_Data - the facts ZacUI's own Sunwell Plateau module is built from.
-- Data only; Own\SWP.lua builds the pieces (Own\TBC_Kit.lua, T.Build).
-- Part of ZacUI (Zacui_RaidMods). Sources and conf: see KZ_Data.lua.
--
-- None of our sources linked the Sunwell's spell ids or creature ids
-- (the Wowhead pages did not load and the guides that did name spells
-- without links), so its spells and adds are matched by their English
-- names (the combat log's spell name, the mob's name) - true on an
-- English client only - and the bosses' health by their names.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on) then return end

T.facts.SWP = {
    name = "Sunwell Plateau", short = "Sunwell", zone = { 580 }, src = "DEI (instance 580)",
    bosses = {
        { short = "Kalecgos", name = "Kalecgos", enc = 724,
          alerts = {
            { name = "Spectral Blast", names = { "Spectral Blast" }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 5,
              text = "SPECTRAL BLAST", me = "SPECTRAL BLAST - INTO THE REALM", sayMe = "Portal", src = "IV (name only)" },
          },
          health = { unitName = "Kalecgos", src = "IV (both go mad at 10%)",
            marks = { { at = 10, text = "CRAZED RAGE", say = "Ten percent", soon = true } } },
          onYou = { { name = "Spectral Exhaustion", names = { "Spectral Exhaustion" }, label = "EXHAUSTED", src = "IV (60 s, name only)" } },
          raid = { { name = "Curse of Boundless Agony", names = { "Curse of Boundless Agony" }, color = { 0.7, 0.3, 1, 0.6 }, src = "IV (name only)" } },
        },
        { short = "Brutallus", name = "Brutallus", enc = 725,
          berserk = { secs = 360, src = "IV (hard enrage at 6 minutes)", conf = "high" },
          alerts = {
            { name = "Burn", names = { "Burn" }, sub = "SPELL_AURA_APPLIED", target = true, gap = 3,
              text = "BURN", me = "BURN ON YOU - GO OUT", sayMe = "Burn on you", src = "IV (name only)" },
          },
          onYou = { { name = "Burn", names = { "Burn" }, label = "BURN", chat = "Burn on me!", src = "IV (60 s, name only)" } },
          raid = { { name = "Burn", names = { "Burn" }, color = { 1, 0.4, 0.1, 0.7 }, src = "IV (name only)" } },
        },
        { short = "Felmyst", name = "Felmyst", enc = 726,
          alerts = {
            { name = "Encapsulate", names = { "Encapsulate" }, sub = "SPELL_AURA_APPLIED", target = true, gap = 3,
              text = "ENCAPSULATE", me = "ENCAPSULATE ON YOU", sayMe = "Encapsulate", src = "IV (name only)" },
            { name = "Gas Nova", names = { "Gas Nova" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "GAS NOVA - DISPEL", say = "Gas nova", src = "IV (name only)" },
            { name = "Demonic Vapor", names = { "Demonic Vapor" }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "DEMONIC VAPOR", me = "DEMONIC VAPOR - RUN", sayMe = "Run", src = "IV (name only)" },
          },
          raid = { { name = "Gas Nova", names = { "Gas Nova" }, color = { 0.3, 1, 0.3, 0.6 }, src = "IV (name only)" } },
        },
        { short = "Twins", name = "Eredar Twins", enc = 727,
          alerts = {
            { name = "Conflagration", names = { "Conflagration" }, sub = "SPELL_AURA_APPLIED", target = true, gap = 3,
              text = "CONFLAGRATION", me = "CONFLAGRATION ON YOU - MOVE", sayMe = "Move", src = "IV (name only)" },
            { name = "Shadow Nova", names = { "Shadow Nova" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, target = true, gap = 3,
              text = "SHADOW NOVA", src = "IV (name only)" },
          },
          onYou = { { name = "Conflagration", names = { "Conflagration" }, label = "MOVE", src = "IV (name only)" } },
          raid = { { name = "Flame Sear", names = { "Flame Sear" }, color = { 1, 0.4, 0.1, 0.6 }, src = "IV (name only)" } },
        },
        { short = "M'uru", name = "M'uru", enc = 728,
          timers = {
            { id = "HUMANOIDS", name = "Humanoids", seen = { names = { "Shadowsword Berserker", "Shadowsword Fury Mage" } }, every = 60, gap = 15,
              src = "IV (berserkers and mages every 60 s; timed from the first sight)", conf = "medium" },
          },
          alerts = {
            { name = "Humanoids", seen = { names = { "Shadowsword Berserker", "Shadowsword Fury Mage" } }, gap = 15,
              text = "HUMANOIDS", say = "Adds", src = "IV" },
            { name = "Darkness", names = { "Darkness" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "DARKNESS", src = "IV (name only)" },
            { name = "Entropius", seen = { names = { "Entropius" } }, once = true,
              text = "PHASE 2 - ENTROPIUS", say = "Phase two", src = "IV" },
          },
        },
        { short = "Kil'jaeden", name = "Kil'jaeden", enc = 729,
          timers = {
            { name = "Darkness of a Thousand Souls", names = { "Darkness of a Thousand Souls" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" },
              every = 45, gap = 15, prewarn = 5, heads = "Darkness", headsSay = "Darkness soon", bar = "Darkness",
              src = "IV (every 45 s from phase three)", conf = "medium" },
          },
          alerts = {
            { name = "Darkness", names = { "Darkness of a Thousand Souls" }, subs = { "SPELL_CAST_START" }, gap = 15,
              text = "DARKNESS - BLUE SHIELD", say = "Shield", src = "IV" },
            { name = "Shadow Spike", names = { "Shadow Spike" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "SHADOW SPIKES", src = "IV (name only)" },
            { name = "Sinister Reflection", names = { "Sinister Reflection" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS", "SPELL_SUMMON" }, gap = 10,
              text = "REFLECTIONS", say = "Reflections", src = "IV (name only)" },
            { name = "Armageddon", names = { "Armageddon" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "ARMAGEDDON", src = "IV (name only)" },
          },
          health = { unitName = "Kil'jaeden", src = "IV (phases at 85, 55 and 25%)",
            marks = { { at = 85, text = "PHASE 3", say = "Phase three", soon = true }, { at = 55, text = "PHASE 4", say = "Phase four", soon = true },
                      { at = 25, text = "PHASE 5", say = "Phase five", soon = true } } },
          onYou = { { name = "Fire Bloom", names = { "Fire Bloom" }, label = "SPREAD", say = "Spread", src = "IV (name only)" } },
        },
    },
}
