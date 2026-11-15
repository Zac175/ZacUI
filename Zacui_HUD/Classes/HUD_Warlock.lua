-- HUD_Warlock - the Warlock HUD, built by HUD_ClassHUD from this
-- definition: cooldown grid (with healthstone and soulstone icons that
-- count what you carry), active buffs, your curses and DoTs on the
-- target, reminders (armor down, no pet, soul shards running out), mana
-- + five-second-rule bars and a wand swing bar.
-- Part of ZacUI; load order is set by the TOC.

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass then return end
if ns.HUD.RETAIL then return end   -- (Retail: its own class HUD, HUD_Retail.lua; this Classic one never loads there)

local SOUL_SHARD = 6265

ns.HUD.DefineClass({
    class = "WARLOCK", className = "Warlock", label = "Warlock HUD", store = "warlock",
    prefix = "wl", frameName = "Warlock",
    blurb = "Cooldown grid with healthstone and soulstone, active buffs, your curses and "
        .. "DoTs on the target, armor / pet / shard reminders, mana + five-second-rule bars and a wand bar.",
    keywords = "warlock hud class pack cooldown grid curse dot corruption immolate "
        .. "healthstone soulstone soul shards demon armor pet death coil wand bar trinkets racial",

    spells = {
        deathCoil = 17926, shadowburn = 18871, howl = 17928, conflagrate = 18930,
        felDom = 18708, amplify = 18288, curseDoom = 603, shadowWard = 28610,
        inferno = 1122, soulFire = 17924, demonArmor = 11735, demonSkin = 696,
        summonImp = 688, corruption = 25311, agony = 11713, immolate = 25309,
        siphon = 18881, fear = 6215, banish = 18647, drainSoul = 11675,
        drainLife = 11700, drainMana = 11704, enslave = 11726,
        lifeTap = 11689, darkPact = 18938, searingPain = 17923, rainOfFire = 11678, hellfire = 11684,
        curseElements = 11722, curseShadow = 17937, curseReck = 11717, curseTongues = 11719, curseWeakness = 11708,
        createHealthstone = 11730, createSoulstone = 20757, summonVoid = 697, summonSucc = 712, summonFel = 691, ritual = 698,
    },

    grid = {
        { key = "deathCoil",   kind = "spell", spell = "deathCoil",   label = "Death Coil" },
        { key = "shadowburn",  kind = "spell", spell = "shadowburn",  label = "Shadowburn" },
        { key = "howl",        kind = "spell", spell = "howl",        label = "Howl of Terror", noRange = true },
        { key = "conflagrate", kind = "spell", spell = "conflagrate", label = "Conflagrate" },
        { key = "felDom",      kind = "spell", spell = "felDom",      label = "Fel Domination", noRange = true },
        { key = "amplify",     kind = "spell", spell = "amplify",     label = "Amplify Curse", noRange = true },
        { key = "curseDoom",   kind = "spell", spell = "curseDoom",   label = "Curse of Doom" },
        { key = "shadowWard",  kind = "spell", spell = "shadowWard",  label = "Shadow Ward", noRange = true },
        { key = "inferno",     kind = "spell", spell = "inferno",     label = "Inferno", noRange = true },
        { key = "soulFire",    kind = "spell", spell = "soulFire",    label = "Soul Fire" },
        -- (22105 / 22104 / 22103 and 22116: TBC's Master stones; not on Era)
        { key = "healthstone", kind = "item", label = "Healthstone", items = {
            { id = 22105 }, { id = 22104 }, { id = 22103 },
            { id = 19013 }, { id = 19012 }, { id = 9421 }, { id = 19011 }, { id = 19010 }, { id = 5510 },
            { id = 19008 }, { id = 19007 }, { id = 5509 }, { id = 19006 }, { id = 19005 }, { id = 5512 } } },
        { key = "soulstone",   kind = "item", label = "Soulstone", items = {
            { id = 22116 }, { id = 16896 }, { id = 16895 }, { id = 16893 }, { id = 16892 }, { id = 5232 } } },
        { key = "potion",      kind = "itemPotion", label = "Potion" },
        { key = "rune",        kind = "itemRune",   label = "Rune" },
    },

    buffRow = {
        { key = "shadowTrance",  id = 17941, label = "Shadow Trance" },
        { key = "touchOfShadow", id = 18791, label = "Touch of Shadow" },
        { key = "burningWish",   id = 18789, label = "Burning Wish" },
        { key = "felStamina",    id = 18790, label = "Fel Stamina" },
        { key = "felEnergy",     id = 18792, label = "Fel Energy" },
        { key = "shadowWard",    id = 28610 },
        { key = "amplify",       id = 18288 },
        { key = "felDom",        id = 18708 },
        { key = "soulstoneRes",  id = 20765, label = "Soulstone Resurrection" },
        { key = "demonArmor",    id = 11735 },
        { key = "demonSkin",     id = 696 },
        { key = "zhc",           id = 24659, name = "Zandalarian Hero Charm", label = "Zandalarian Hero Charm" },
    },

    debuffRow = {
        { key = "corruption",   id = 25311, castsDot = true },
        { key = "agony",        id = 11713, castsDot = true },
        { key = "doom",         id = 603, castsDot = true },
        { key = "immolate",     id = 25309, castsDot = true },
        { key = "siphon",       id = 18881, castsDot = true },
        { key = "recklessness", id = 11717, label = "Curse of Recklessness", castsDot = true },
        { key = "curseShadow",  id = 17937, label = "Curse of Shadow", castsDot = true },
        { key = "elements",     id = 11722, label = "Curse of the Elements", castsDot = true },
        { key = "weakness",     id = 11708, label = "Curse of Weakness", castsDot = true },
        { key = "tongues",      id = 11719, label = "Curse of Tongues", castsDot = true },
        { key = "exhaustion",   id = 18223, label = "Curse of Exhaustion", castsDot = true },
        { key = "fear",         id = 6215 },
        { key = "deathCoil",    id = 17926 },
        { key = "banish",       id = 18647 },
        { key = "shadowVuln",   id = 17800, label = "Shadow Vulnerability" },
        { key = "shadowburn",   id = 18871 },
        { key = "drainSoul",    id = 11675 },
        { key = "drainLife",    id = 11700 },
        { key = "drainMana",    id = 11704 },
    },

    reminders = {
        { key = "armor", label = "Demon Armor / Skin down", spell = "demonArmor",
          check = function(H)
              if not (H.Known("demonArmor") or H.Known("demonSkin")) then return false end
              -- (TBC: Fel Armor counts; it does not exist on Era)
              return not (H.Buff("demonArmor") or H.Buff("demonSkin") or H.Buff("felArmor"))
          end },
        { key = "pet", label = "No demon out", spell = "summonImp",
          check = function(H)
              if not H.Known("summonImp") then return false end
              if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then return false end
              return not UnitIsDeadOrGhost("player")
          end },
        { key = "shards", label = "Soul shards running out", icon = 134075, previewCount = 3, item = SOUL_SHARD,
          check = function(H)
              local n = H.Count(SOUL_SHARD)
              if n >= 5 then return false end
              return true, 134075, n
          end },
    },


    -- Class HUD v2: the utility row, the roles, TBC's additions
    utility = {
        { key = "lifeTap",      kind = "spell", spell = "lifeTap",      label = "Life Tap", noRange = true },
        { key = "darkPact",     kind = "spell", spell = "darkPact",     label = "Dark Pact", noRange = true },
        { key = "fear",         kind = "spell", spell = "fear",         label = "Fear" },
        { key = "banish",       kind = "spell", spell = "banish",       label = "Banish" },
        { key = "enslave",      kind = "spell", spell = "enslave",      label = "Enslave Demon" },
        { key = "drainSoul",    kind = "spell", spell = "drainSoul",    label = "Drain Soul" },
        { key = "drainLife",    kind = "spell", spell = "drainLife",    label = "Drain Life" },
        { key = "drainMana",    kind = "spell", spell = "drainMana",    label = "Drain Mana" },
        { key = "searingPain",  kind = "spell", spell = "searingPain",  label = "Searing Pain" },
        { key = "rainOfFire",   kind = "spell", spell = "rainOfFire",   label = "Rain of Fire", noRange = true },
        { key = "hellfire",     kind = "spell", spell = "hellfire",     label = "Hellfire", noRange = true },
        { key = "curseElements", kind = "spell", spell = "curseElements", label = "Curse of the Elements" },
        { key = "curseShadow",  kind = "spell", spell = "curseShadow",  label = "Curse of Shadow" },
        { key = "curseReck",    kind = "spell", spell = "curseReck",    label = "Curse of Recklessness" },
        { key = "curseTongues", kind = "spell", spell = "curseTongues", label = "Curse of Tongues" },
        { key = "curseWeakness", kind = "spell", spell = "curseWeakness", label = "Curse of Weakness" },
        { key = "createHealthstone", kind = "spell", spell = "createHealthstone", label = "Create Healthstone", noRange = true },
        { key = "createSoulstone",   kind = "spell", spell = "createSoulstone",   label = "Create Soulstone", noRange = true },
        { key = "summonImp",    kind = "spell", spell = "summonImp",    label = "Summon Imp", noRange = true },
        { key = "summonVoid",   kind = "spell", spell = "summonVoid",   label = "Summon Voidwalker", noRange = true },
        { key = "summonSucc",   kind = "spell", spell = "summonSucc",   label = "Summon Succubus", noRange = true },
        { key = "summonFel",    kind = "spell", spell = "summonFel",    label = "Summon Felhunter", noRange = true },
        { key = "ritual",       kind = "spell", spell = "ritual",       label = "Ritual of Summoning", noRange = true },
    },
    -- Spec presets (HUD_V2_Specs): each spec's default HUD, from what top
    -- players press and track (sources in CLASSHUD_V2_DESIGN_1107.md
    -- section 13: Icy Veins' Classic warlock guide and its TBC Affliction /
    -- Destruction guides; WoW Forever: wowtbc.gg's Forever warlock guides
    -- and warcraft.wiki.gg's Forever ability list). The base lists are
    -- Classic Era's (in raids only Corruption and the assigned curse fit
    -- the debuff slots); a spec's tbc / forever block replaces the rows it
    -- names on that game. WoW Forever (1.60): Curse of Agony and Curse of
    -- Doom are Banes (same ids; one Bane and one Curse each on a target),
    -- Curse of Shadow and Dark Pact are gone, Affliction fills with Wrack,
    -- Demonology uses Soul Fire under Decimation, Destruction presses
    -- Conflagrate (it no longer eats Immolate) and Shadowburn.
    roles = {
        { key = "affliction", label = "Affliction", tab = 1, aux = true, res = { regen = true }, show = {
            main = { "amplify", "shadowburn", "healthstone", "soulstone", "potion", "rune" },
            utility = { "lifeTap", "darkPact", "curseElements", "curseShadow", "curseReck", "fear", "banish", "createHealthstone", "createSoulstone" },
            buffs = { "shadowTrance", "amplify", "touchOfShadow", "zhc" },
            debuffs = { "corruption", "elements", "curseShadow", "recklessness", "agony", "shadowVuln" } },
          glows = { ["buffs:shadowTrance"] = { { when = "active", style = "shine" } },
                    ["debuffs:corruption"] = { { when = "anticlip", style = "solid" } } },
          tbc = { show = {
              main = { "curseDoom", "amplify", "soulshatter", "healthstone", "soulstone", "potion", "rune" },
              buffs = { "shadowTrance", "amplify", "felArmorBuff", "zhc" },
              debuffs = { "corruption", "unstableAffliction", "siphon", "elements", "doom", "agony", "shadowVuln" } },
            glows = { ["buffs:shadowTrance"] = { { when = "active", style = "shine" } },
                      ["debuffs:corruption"] = { { when = "anticlip", style = "solid" } },
                      ["debuffs:unstableAffliction"] = { { when = "anticlip", style = "solid" } },
                      ["debuffs:siphon"] = { { when = "anticlip", style = "solid" } } } },
          forever = { show = {
              main = { "amplify", "curseDoom", "shadowburn", "healthstone", "soulstone", "potion", "rune" },
              debuffs = { "corruption", "siphon", "agony", "doom", "wrack", "elements", "recklessness", "shadowVuln" } },
            glows = { ["buffs:shadowTrance"] = { { when = "active", style = "shine" } },
                      ["debuffs:corruption"] = { { when = "anticlip", style = "solid" } },
                      ["debuffs:siphon"] = { { when = "anticlip", style = "solid" } } } } },
        { key = "demonology", label = "Demonology", tab = 2, aux = true, res = { regen = true }, show = {
            main = { "felDom", "shadowburn", "healthstone", "soulstone", "potion", "rune" },
            utility = { "lifeTap", "curseElements", "curseShadow", "curseReck", "fear", "banish", "summonImp", "summonVoid", "summonSucc", "summonFel", "createHealthstone", "createSoulstone" },
            buffs = { "touchOfShadow", "burningWish", "felDom", "zhc" },
            debuffs = { "corruption", "elements", "curseShadow", "recklessness", "agony", "shadowVuln" } },
          glows = { ["debuffs:corruption"] = { { when = "anticlip", style = "solid" } } },
          tbc = { show = {
              main = { "felDom", "curseDoom", "soulshatter", "healthstone", "soulstone", "potion", "rune" },
              buffs = { "felArmorBuff", "touchOfShadow", "burningWish", "zhc" },
              debuffs = { "corruption", "immolate", "elements", "doom", "agony", "shadowVuln" } },
            glows = { ["debuffs:corruption"] = { { when = "anticlip", style = "solid" } },
                      ["debuffs:immolate"] = { { when = "anticlip", style = "solid" } } } },
          forever = { show = {
              main = { "felDom", "soulFire", "curseDoom", "healthstone", "soulstone", "potion", "rune" },
              buffs = { "decimation", "touchOfShadow", "burningWish", "felDom", "zhc" },
              debuffs = { "immolate", "corruption", "agony", "doom", "elements", "recklessness", "shadowVuln" } },
            glows = { ["buffs:decimation"] = { { when = "active", style = "shine" } },
                      ["debuffs:immolate"] = { { when = "anticlip", style = "solid" } },
                      ["debuffs:corruption"] = { { when = "anticlip", style = "solid" } } } } },
        { key = "destruction", label = "Destruction", tab = 3, aux = true, res = { regen = true }, show = {
            main = { "shadowburn", "healthstone", "soulstone", "potion", "rune" },
            utility = { "lifeTap", "searingPain", "rainOfFire", "hellfire", "curseElements", "curseShadow", "curseReck", "fear", "banish", "createHealthstone", "createSoulstone" },
            buffs = { "touchOfShadow", "burningWish", "zhc" },
            debuffs = { "corruption", "elements", "curseShadow", "recklessness", "shadowVuln" } },
          glows = { ["debuffs:corruption"] = { { when = "anticlip", style = "solid" } } },
          tbc = { show = {
              main = { "shadowburn", "curseDoom", "soulshatter", "healthstone", "soulstone", "potion", "rune" },
              buffs = { "felArmorBuff", "touchOfShadow", "burningWish", "zhc" },
              debuffs = { "immolate", "corruption", "doom", "elements", "shadowVuln" } },
            glows = { ["debuffs:immolate"] = { { when = "anticlip", style = "solid" } } } },
          forever = { show = {
              main = { "conflagrate", "shadowburn", "curseDoom", "healthstone", "soulstone", "potion", "rune" },
              debuffs = { "immolate", "corruption", "agony", "doom", "elements", "recklessness", "shadowVuln" } },
            glows = { conflagrate = { { when = "ready", style = "edge", combatOnly = true } },
                      ["debuffs:immolate"] = { { when = "anticlip", style = "solid" } },
                      ["debuffs:corruption"] = { { when = "anticlip", style = "solid" } } } } },
    },
    flavors = {
        tbc = { add = {
            { key = "shadowfury",   kind = "spell", spell = "shadowfury",   spellId = 30283, label = "Shadowfury", noRange = true },
            { key = "soulshatter",  kind = "spell", spell = "soulshatter",  spellId = 29858, label = "Soulshatter", noRange = true },
            { key = "felArmorBuff", id = 28176, label = "Fel Armor", row = "buffs" },
            { key = "unstableAffliction", id = 30108, label = "Unstable Affliction", row = "debuffs", castsDot = true },
            { key = "seedOfCorruption",   id = 27243, label = "Seed of Corruption", row = "debuffs" },
        }, spells = { felArmor = 28176 } },
        -- WoW Forever's own talents (ids: warcraft.wiki.gg's Forever pages)
        forever = { add = {
            { key = "wrack",       id = 1316697, label = "Wrack", row = "debuffs" },
            { key = "baneOfHavoc", id = 1225228, label = "Bane of Havoc", row = "debuffs" },
            { key = "decimation",  id = 440870,  label = "Decimation", row = "buffs" },
        } },
    },
    buffBars = { "shadowTrance", "amplify" },
    bars = { "mana", "fsr", "wand" },
})
