-- SWP_Data - the facts ZacUI's own Sunwell Plateau module is built from.
-- Data only; Own\SWP.lua builds the pieces (Own\TBC_Kit.lua, T.Build).
-- Part of ZacUI (Zacui_RaidMods). Sources and conf: see KZ_Data.lua.
--
-- Spell ids and timings: BW (numbers only). A spell BW does not follow
-- has no id here and is matched by its English name (the combat log's
-- spell name) - true on an English client only; where both are given
-- either one matches.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
local T = RM and RM.Own and RM.Own.TBC
if not (T and T.on) then return end

T.facts.SWP = {
    name = "Sunwell Plateau", short = "Sunwell", zone = { 580 }, src = "DEI (instance 580)",
    bosses = {
        { short = "Kalecgos", name = "Kalecgos", enc = 724, npc = 24850,
          timers = {
            { name = "Frost Breath", spells = { 44799 }, sub = "SPELL_CAST_START", first = 15, every = 15, gap = 5,
              src = "BW (15 s from the pull, about 15 between)", conf = "medium" },
            { id = "PORTAL", name = "First portal", first = 20, phase = true, src = "BW (20 s from the pull)", conf = "medium" },
          },
          alerts = {
            { name = "Spectral Blast", names = { "Spectral Blast" }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 5,
              text = "SPECTRAL BLAST", me = "SPECTRAL BLAST - INTO THE REALM", sayMe = "Portal", src = "IV (name only)" },
            { name = "Frost Breath", spells = { 44799 }, sub = "SPELL_CAST_START", gap = 5, text = "FROST BREATH", cast = true, src = "BW" },
            { name = "Wild Magic: healing", spells = { 44978 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "WILD MAGIC", me = "WILD MAGIC - YOUR HEALING IS DOUBLED", sayMe = "Healing doubled", src = "BW" },
            { name = "Wild Magic: cast time", spells = { 45001 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "WILD MAGIC", me = "WILD MAGIC - YOUR CASTS ARE SLOW", sayMe = "Slow casts", src = "BW" },
            { name = "Wild Magic: hit chance", spells = { 45002 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "WILD MAGIC", me = "WILD MAGIC - YOU MISS MORE", sayMe = "Hit chance down", src = "BW" },
            { name = "Wild Magic: threat", spells = { 45006 }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "WILD MAGIC", me = "WILD MAGIC - YOUR THREAT IS UP", sayMe = "Threat up", src = "BW" },
            { name = "Crazed Rage", spells = { 44806 }, sub = "SPELL_AURA_APPLIED", gap = 10, text = "CRAZED RAGE", say = "Enrage", src = "BW" },
          },
          health = { unitName = "Kalecgos", src = "IV (both go mad at 10%)",
            marks = { { at = 10, text = "CRAZED RAGE", say = "Ten percent", soon = true } } },
          tank = { { name = "Corrupting Strike", spells = { 45029 }, label = "Strike", src = "BW" } },
          lists = { { name = "Spectral Exhaustion", names = { "Spectral Exhaustion" }, src = "IV (60 s, cannot take a portal; name only)" } },
          onYou = {
            { name = "Spectral Exhaustion", names = { "Spectral Exhaustion" }, label = "EXHAUSTED", src = "IV (60 s, name only)" },
            { name = "Curse of Boundless Agony", spells = { 45032, 45034 }, names = { "Curse of Boundless Agony" }, label = "CURSE", say = "Curse on you", src = "BW" },
          },
          raid = { { name = "Curse of Boundless Agony", spells = { 45032, 45034 }, names = { "Curse of Boundless Agony" }, color = { 0.7, 0.3, 1, 0.6 },
              list = true, src = "BW; IV" } },
        },
        { short = "Brutallus", name = "Brutallus", enc = 725, npc = 24882,
          berserk = { secs = 360, src = "IV (hard enrage at 6 minutes); BW", conf = "high" },
          timers = {
            { name = "Burn", spells = { 46394 }, sub = "SPELL_AURA_APPLIED", first = 20, every = 20, gap = 5, prewarn = 4, headsSay = "Burn soon",
              src = "BW (20 s from the pull, 20 between)", conf = "medium" },
            { name = "Stomp", spells = { 45185 }, sub = "SPELL_CAST_SUCCESS", first = 30, every = 30.5, gap = 5,
              src = "BW (30 s from the pull, 30.5 between)", conf = "medium" },
            { name = "Meteor Slash", spells = { 45150 }, sub = "SPELL_CAST_START", every = 12, gap = 5, src = "BW (12 s between)", conf = "medium" },
          },
          alerts = {
            { name = "Burn", spells = { 46394 }, names = { "Burn" }, sub = "SPELL_AURA_APPLIED", target = true, gap = 3,
              text = "BURN", me = "BURN ON YOU - GO OUT", sayMe = "Burn on you", src = "BW; IV" },
            { name = "Meteor Slash", spells = { 45150 }, sub = "SPELL_CAST_START", gap = 5, text = "METEOR SLASH", cast = true, src = "BW" },
            { name = "Stomp", spells = { 45185 }, sub = "SPELL_CAST_SUCCESS", target = true, gap = 5, text = "STOMP", src = "BW" },
          },
          tank = { { name = "Meteor Slash", spells = { 45150 }, label = "Slash", src = "BW" } },
          onYou = { { name = "Burn", spells = { 46394 }, names = { "Burn" }, label = "BURN", chat = "Burn on me!", src = "BW (60 s)" } },
          raid = { { name = "Burn", spells = { 46394 }, names = { "Burn" }, color = { 1, 0.4, 0.1, 0.7 }, list = true, src = "BW (60 s)" } },
        },
        { short = "Felmyst", name = "Felmyst", enc = 726, npc = 25038,
          berserk = { secs = 600, src = "BW (10 minutes)", conf = "medium" },
          cycles = {
            { id = "FLIGHT", name = "Ground and air", loop = true, spells = { 45661 },
              src = "BW (on the ground for 60 s, in the air for 100)", conf = "medium",
              parts = {
                { id = "TAKEOFF", bar = "Takes off", secs = 60, alert = "FELMYST TAKES OFF", say = "Air phase" },
                { id = "LANDING", bar = "Lands", secs = 100, alert = "FELMYST LANDS", say = "Landing" },
              } },
          },
          timers = {
            { name = "Encapsulate", spells = { 45661 }, names = { "Encapsulate" }, subs = { "SPELL_AURA_APPLIED", "SPELL_DAMAGE" },
              first = 30, every = 160, gap = 20, prewarn = 5, headsSay = "Encapsulate soon",
              src = "BW (30 s into each time on the ground)", conf = "medium" },
            { name = "Gas Nova", spells = { 45855 }, names = { "Gas Nova" }, sub = "SPELL_CAST_START", every = 20, gap = 5,
              src = "BW (about 20 s between, on the ground)", conf = "low" },
          },
          alerts = {
            { name = "Encapsulate", spells = { 45661 }, names = { "Encapsulate" }, subs = { "SPELL_AURA_APPLIED", "SPELL_DAMAGE" }, target = true, gap = 8,
              text = "ENCAPSULATE", me = "ENCAPSULATE ON YOU", sayMe = "Encapsulate", src = "BW; IV" },
            { name = "Gas Nova", spells = { 45855 }, names = { "Gas Nova" }, subs = { "SPELL_CAST_START" }, gap = 5,
              text = "GAS NOVA - DISPEL", say = "Gas nova", cast = true, src = "BW; IV" },
            { name = "Demonic Vapor", names = { "Demonic Vapor" }, sub = "SPELL_AURA_APPLIED", onlyMe = true, gap = 3,
              text = "DEMONIC VAPOR", me = "DEMONIC VAPOR - RUN", sayMe = "Run", src = "IV (name only)" },
            { name = "Demonic Vapor beam", spells = { 45392 }, sub = "SPELL_SUMMON", gap = 3, text = "DEMONIC VAPOR", src = "BW" },
          },
          tank = { { name = "Corrosion", spells = { 45866 }, label = "Corrosion", src = "BW (10 s)" } },
          raid = { { name = "Gas Nova", spells = { 45855 }, names = { "Gas Nova" }, color = { 0.3, 1, 0.3, 0.6 }, list = true, src = "BW; IV" } },
        },
        { short = "Twins", name = "Eredar Twins", enc = 727, npc = 25166,
          berserk = { secs = 360, src = "BW (6 minutes)", conf = "medium" },
          timers = {
            { name = "Confounding Blow", spells = { 45256 }, sub = "SPELL_CAST_SUCCESS", every = 20, gap = 5, src = "BW (about 20 s between)", conf = "low" },
            { name = "Shadow Blades", spells = { 45248 }, sub = "SPELL_CAST_START", every = 10, gap = 3, src = "BW (10 s between)", conf = "medium" },
          },
          alerts = {
            { name = "Conflagration", spells = { 45342 }, names = { "Conflagration" }, sub = "SPELL_AURA_APPLIED", target = true, gap = 3,
              text = "CONFLAGRATION", me = "CONFLAGRATION ON YOU - MOVE", sayMe = "Move", cast = true, src = "BW; IV" },
            { name = "Shadow Nova", spells = { 45329 }, names = { "Shadow Nova" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, target = true, gap = 3,
              text = "SHADOW NOVA", cast = true, src = "BW; IV" },
            { name = "Confounding Blow", spells = { 45256 }, sub = "SPELL_CAST_SUCCESS", target = true, gap = 5, text = "CONFOUNDING BLOW", src = "BW" },
            { name = "Pyrogenics", spells = { 45230 }, sub = "SPELL_AURA_APPLIED", gap = 5, text = "PYROGENICS - REMOVE IT", say = "Purge", src = "BW (15 s)" },
          },
          onYou = { { name = "Conflagration", spells = { 45342 }, names = { "Conflagration" }, label = "MOVE", src = "BW (10 s)" } },
          raid = {
            { name = "Flame Sear", names = { "Flame Sear" }, color = { 1, 0.4, 0.1, 0.6 }, src = "IV (name only)" },
            { name = "Conflagration", spells = { 45342 }, color = { 1, 0.6, 0.1, 0.7 }, list = true, src = "BW (10 s)" },
          },
        },
        { short = "M'uru", name = "M'uru", enc = 728, npc = 25741,
          berserk = { secs = 600, src = "BW (10 minutes)", conf = "medium" },
          timers = {
            { name = "Darkness", spells = { 45996 }, sub = "SPELL_AURA_APPLIED", first = 45, every = 45, gap = 30, prewarn = 5, headsSay = "Darkness soon",
              restart = { { spells = { 46177 }, sub = "SPELL_CAST_SUCCESS", stop = true } },
              src = "BW (45 s from the pull, 45 between; none after M'uru falls)", conf = "medium" },
            { id = "SENTINELS", name = "Void Sentinel", first = 30, every = 30, loop = true,
              restart = { { spells = { 46177 }, sub = "SPELL_CAST_SUCCESS", stop = true } },
              src = "BW (every 30 s from the pull)", conf = "medium" },
            { id = "HUMANOIDS", name = "Humanoids", first = 10, every = 60, loop = true,
              restart = { { spells = { 46177 }, sub = "SPELL_CAST_SUCCESS", stop = true } },
              src = "BW (10 s from the pull, then every 60); IV", conf = "medium" },
            { name = "Black Hole", spells = { 46282 }, sub = "SPELL_CAST_SUCCESS", every = 15, gap = 5,
              restart = { { spells = { 46177 }, sub = "SPELL_CAST_SUCCESS", secs = 27 } },
              src = "BW (27 s after M'uru falls, 15 between)", conf = "medium" },
          },
          casts = {
            { name = "Darkness", spells = { 45996 }, sub = "SPELL_AURA_APPLIED", secs = 20, text = "Darkness", src = "BW (20 s)" },
            { name = "Entropius", spells = { 46177 }, sub = "SPELL_CAST_SUCCESS", secs = 10, text = "Entropius arrives", src = "BW (10 s)" },
          },
          alerts = {
            { name = "Humanoids", seen = { names = { "Shadowsword Berserker", "Shadowsword Fury Mage" } }, gap = 15,
              text = "HUMANOIDS", say = "Adds", src = "IV" },
            { name = "Darkness", spells = { 45996 }, names = { "Darkness" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }, gap = 30,
              text = "DARKNESS", src = "BW; IV" },
            { name = "Dark Fiend", spells = { 45934 }, sub = "SPELL_CAST_SUCCESS", gap = 10, text = "DARK FIENDS", src = "BW" },
            { name = "Phase two", spells = { 46177 }, sub = "SPELL_CAST_SUCCESS", gap = 30, text = "PHASE 2 - ENTROPIUS IN 10", say = "Phase two", src = "BW" },
            { name = "Black Hole", spells = { 46282 }, sub = "SPELL_CAST_SUCCESS", gap = 5, text = "BLACK HOLE", say = "Black hole", src = "BW" },
          },
        },
        { short = "Kil'jaeden", name = "Kil'jaeden", enc = 729, npc = 25315,
          timers = {
            { name = "Darkness of a Thousand Souls", spells = { 46605 }, names = { "Darkness of a Thousand Souls" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" },
              every = 45, gap = 15, prewarn = 5, heads = "Darkness", headsSay = "Darkness soon", bar = "Darkness",
              src = "IV (every 45 s from phase three); BW has 46, and 25 in the last phase", conf = "medium" },
            { name = "Fire Bloom", spells = { 45641 }, sub = "SPELL_AURA_APPLIED", every = 20, gap = 10, src = "BW (20 s between)", conf = "medium" },
          },
          casts = {
            { name = "Darkness", spells = { 46605 }, names = { "Darkness of a Thousand Souls" }, sub = "SPELL_CAST_START", secs = 8,
              text = "Darkness of a Thousand Souls", src = "BW (8 s)" },
            { name = "Shadow Spikes", spells = { 46680 }, sub = "SPELL_CAST_START", secs = 28.7, text = "Shadow Spikes", src = "BW (28.7 s)" },
          },
          alerts = {
            { name = "Darkness", spells = { 46605 }, names = { "Darkness of a Thousand Souls" }, subs = { "SPELL_CAST_START" }, gap = 15,
              text = "DARKNESS - BLUE SHIELD", say = "Shield", src = "IV; BW" },
            { name = "Shadow Spike", spells = { 46680 }, names = { "Shadow Spike" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "SHADOW SPIKES", src = "BW; IV" },
            { name = "Sinister Reflection", spells = { 45892 }, names = { "Sinister Reflection" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS", "SPELL_SUMMON" }, gap = 10,
              text = "REFLECTIONS", say = "Reflections", src = "BW; IV" },
            { name = "Shield of the Blue", spells = { 45848 }, sub = "SPELL_CAST_SUCCESS", gap = 5, text = "BLUE SHIELD IS UP", src = "BW" },
            { name = "Armageddon", names = { "Armageddon" }, subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" }, gap = 5,
              text = "ARMAGEDDON", src = "IV (name only)" },
          },
          health = { unitName = "Kil'jaeden", src = "IV (phases at 85, 55 and 25%)",
            marks = { { at = 85, text = "PHASE 3", say = "Phase three", soon = true }, { at = 55, text = "PHASE 4", say = "Phase four", soon = true },
                      { at = 25, text = "PHASE 5", say = "Phase five", soon = true } } },
          onYou = { { name = "Fire Bloom", spells = { 45641 }, names = { "Fire Bloom" }, label = "SPREAD", say = "Spread", src = "BW (20 s)" } },
          raid = {
            { name = "Fire Bloom", spells = { 45641 }, color = { 1, 0.5, 0.1, 0.7 }, list = true, src = "BW (20 s)" },
            { name = "Shadow Spike", spells = { 45885 }, color = { 0.6, 0.3, 1, 0.6 }, list = true, src = "BW (10 s, healing taken cut)" },
          },
        },
    },
}
