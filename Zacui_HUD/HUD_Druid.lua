-- HUD_Druid - the Druid HUD, built by HUD_ClassHUD from this definition:
-- cooldown grid across every form, active buffs, your DoTs, bleeds and
-- roots on the target, Mark of the Wild and Thorns reminders, a mana +
-- five-second-rule pair while in caster form, an energy / rage bar with
-- the energy tick, combo points in cat and a swing timer in the feral
-- forms. The bars follow whichever power the current form runs on.
-- Part of ZacUI; load order is set by the TOC.

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass then return end

ns.HUD.DefineClass({
    class = "DRUID", className = "Druid", label = "Druid HUD", store = "druid",
    prefix = "dr", frameName = "Druid", powerLabel = "Energy / Rage",
    blurb = "Cooldown grid, active buffs, your DoTs and bleeds on the target, Mark of the Wild "
        .. "and Thorns reminders, mana or energy / rage bars for the current form, combo points and a swing timer.",
    keywords = "druid hud class pack cooldown grid cat bear moonkin form energy rage combo points "
        .. "innervate rebirth nature's swiftness barkskin mark of the wild thorns swing timer trinkets racial",

    spells = {
        ns = 17116, barkskin = 22812, innervate = 29166, rebirth = 20484,
        feralCharge = 16979, bash = 8983, enrage = 5229, frenzied = 22842,
        dash = 9821, tigersFury = 9846, hibernate = 18658, naturesGrasp = 17329,
        hurricane = 17402, challengingRoar = 5209, tranquility = 9863, cower = 9892,
        motw = 9885, gotw = 21850, thorns = 9910, moonfire = 9835, insectSwarm = 24977,
        faerieFire = 9907, ffFeral = 17392, rake = 9904, rip = 9896, pounce = 9827,
        roots = 9853, demoRoar = 9898, rejuv = 25299, regrowth = 9858,
        maul = 9881, swipe = 9908, growl = 6795, ravage = 9867, removeCurse = 2782, abolishPoison = 2893,
        swiftmend = 18562,
    },

    grid = {
        { key = "ns",              kind = "spell", spell = "ns",              label = "Nature's Swiftness", noRange = true },
        { key = "barkskin",        kind = "spell", spell = "barkskin",        label = "Barkskin", noRange = true },
        { key = "innervate",       kind = "spell", spell = "innervate",       label = "Innervate", noRange = true },
        { key = "rebirth",         kind = "spell", spell = "rebirth",         label = "Rebirth", noRange = true },
        { key = "feralCharge",     kind = "spell", spell = "feralCharge",     label = "Feral Charge" },
        { key = "bash",            kind = "spell", spell = "bash",            label = "Bash" },
        { key = "enrage",          kind = "spell", spell = "enrage",          label = "Enrage", noRange = true },
        { key = "frenzied",        kind = "spell", spell = "frenzied",        label = "Frenzied Regeneration", noRange = true },
        { key = "dash",            kind = "spell", spell = "dash",            label = "Dash", noRange = true },
        { key = "tigersFury",      kind = "spell", spell = "tigersFury",      label = "Tiger's Fury", noRange = true },
        { key = "cower",           kind = "spell", spell = "cower",           label = "Cower", noRange = true },
        { key = "hibernate",       kind = "spell", spell = "hibernate",       label = "Hibernate" },
        { key = "naturesGrasp",    kind = "spell", spell = "naturesGrasp",    label = "Nature's Grasp", noRange = true },
        { key = "hurricane",       kind = "spell", spell = "hurricane",       label = "Hurricane", noRange = true },
        { key = "challengingRoar", kind = "spell", spell = "challengingRoar", label = "Challenging Roar", noRange = true },
        { key = "tranquility",     kind = "spell", spell = "tranquility",     label = "Tranquility", noRange = true },
        { key = "potion",          kind = "itemPotion", label = "Potion" },
        { key = "rune",            kind = "itemRune",   label = "Rune" },
    },

    buffRow = {
        { key = "ns",           id = 17116 },
        { key = "barkskin",     id = 22812 },
        { key = "enrage",       id = 5229 },
        { key = "frenzied",     id = 22842 },
        { key = "dash",         id = 9821 },
        { key = "tigersFury",   id = 9846 },
        { key = "naturesGrace", id = 16886, label = "Nature's Grace" },
        { key = "clearcasting", id = 16870, label = "Clearcasting" },
        { key = "innervate",    id = 29166 },
        { key = "naturesGrasp", id = 17329 },
        { key = "thorns",       id = 9910 },
        { key = "rejuv",        id = 25299, label = "Rejuvenation (self)" },
        { key = "regrowth",     id = 9858,  label = "Regrowth (self)" },
        { key = "zhc",          id = 24659, name = "Zandalarian Hero Charm", label = "Zandalarian Hero Charm" },
    },

    debuffRow = {
        { key = "moonfire",    id = 9835, castsDot = true },
        { key = "insectSwarm", id = 24977, castsDot = true },
        { key = "faerieFire",  id = 9907 },
        { key = "ffFeral",     id = 17392, label = "Faerie Fire (Feral)" },
        { key = "rake",        id = 9904, castsDot = true },
        { key = "rip",         id = 9896, castsDot = true },
        { key = "pounce",      id = 9827, label = "Pounce Bleed" },
        { key = "roots",       id = 9853 },
        { key = "hibernate",   id = 18658 },
        { key = "demoRoar",    id = 9898 },
        { key = "bash",        id = 8983 },
        { key = "feralCharge", id = 16979, label = "Feral Charge (root)" },
    },

    reminders = {
        { key = "motw", label = "Mark of the Wild down", spell = "motw",
          check = function(H)
              if not H.Known("motw") then return false end
              return not (H.Buff("motw") or H.Buff("gotw"))
          end },
        { key = "thorns", label = "Thorns down", spell = "thorns", default = false,
          check = function(H) return H.Known("thorns") and not H.Buff("thorns") end },
    },


    -- Class HUD v2: the utility row, the roles, TBC's additions
    utility = {
        { key = "maul",          kind = "spell", spell = "maul",          label = "Maul", nextSwing = true },
        { key = "swipe",         kind = "spell", spell = "swipe",         label = "Swipe", noRange = true },
        { key = "growl",         kind = "spell", spell = "growl",         label = "Growl" },
        { key = "faerieFire",    kind = "spell", spell = "faerieFire",    label = "Faerie Fire" },
        { key = "ffFeral",       kind = "spell", spell = "ffFeral",       label = "Faerie Fire (Feral)" },
        { key = "rake",          kind = "spell", spell = "rake",          label = "Rake" },
        { key = "rip",           kind = "spell", spell = "rip",           label = "Rip" },
        { key = "ravage",        kind = "spell", spell = "ravage",        label = "Ravage" },
        { key = "pounce",        kind = "spell", spell = "pounce",        label = "Pounce" },
        { key = "moonfire",      kind = "spell", spell = "moonfire",      label = "Moonfire" },
        { key = "insectSwarm",   kind = "spell", spell = "insectSwarm",   label = "Insect Swarm" },
        { key = "roots",         kind = "spell", spell = "roots",         label = "Entangling Roots" },
        { key = "removeCurse",   kind = "spell", spell = "removeCurse",   label = "Remove Curse" },
        { key = "abolishPoison", kind = "spell", spell = "abolishPoison", label = "Abolish Poison" },
        { key = "swiftmend",     kind = "spell", spell = "swiftmend",     label = "Swiftmend" },
        { key = "rejuv",         kind = "spell", spell = "rejuv",         label = "Rejuvenation" },
        { key = "regrowth",      kind = "spell", spell = "regrowth",      label = "Regrowth" },
    },
    -- Spec presets (HUD_V2_Specs): each spec's default HUD, from what top
    -- players press and track (sources in CLASSHUD_V2_DESIGN_1107.md
    -- section 13: Icy Veins' Classic and TBC feral cat / bear, restoration
    -- and balance guides). The base lists are Classic Era's (WoW Forever
    -- plays them too: Era cats skip Rake / Rip in raids, debuff slots); a
    -- spec's tbc block replaces the rows it names on TBC. Feral Combat holds
    -- two presets: cat (energy) and bear (rage), by the form you fight in.
    roles = {
        { key = "balance", label = "Balance", tab = 1, aux = true, res = { regen = true }, show = {
            main = { "innervate", "ns", "rebirth", "potion", "rune" },
            utility = { "moonfire", "insectSwarm", "faerieFire", "roots", "removeCurse", "abolishPoison", "rejuv", "regrowth" },
            buffs = { "naturesGrace", "clearcasting", "innervate", "zhc" },
            debuffs = { "moonfire", "insectSwarm", "faerieFire" } },
          glows = { ["debuffs:moonfire"] = { { when = "anticlip", style = "solid" } },
                    ["debuffs:insectSwarm"] = { { when = "anticlip", style = "solid" } },
                    ["buffs:clearcasting"] = { { when = "active", style = "shine" } } },
          tbc = { show = {
              main = { "innervate", "forceOfNature", "rebirth", "potion", "rune" } } } },
        { key = "cat", label = "Feral (cat)", tab = 2, form = "cat", aux = true, res = { druidMana = true, rangeDim = true }, show = {
            main = { "innervate", "cower", "rebirth", "potion", "rune" },
            utility = { "ffFeral", "removeCurse", "abolishPoison" },
            buffs = { "clearcasting", "tigersFury", "innervate", "zhc" },
            debuffs = { "ffFeral" } },
          glows = { ["buffs:clearcasting"] = { { when = "active", style = "shine" } } },
          tbc = { show = {
              main = { "mangleCat", "innervate", "cower", "rebirth", "potion", "rune" },
              utility = { "rip", "ffFeral", "removeCurse", "abolishPoison" },
              debuffs = { "rip", "mangleDebuff", "ffFeral" } },
            glows = { ["buffs:clearcasting"] = { { when = "active", style = "shine" } },
                      ["debuffs:rip"] = { { when = "anticlip", style = "solid" } },
                      ["debuffs:mangleDebuff"] = { { when = "expiring", style = "pulse" } } } } },
        { key = "bear", label = "Feral (bear)", tab = 2, form = "bear", aux = true, res = { druidMana = true, queued = true, rangeDim = true }, show = {
            main = { "frenzied", "enrage", "barkskin", "challengingRoar", "innervate", "rebirth", "potion", "rune" },
            utility = { "maul", "swipe", "growl", "ffFeral", "removeCurse", "abolishPoison" },
            buffs = { "frenzied", "enrage", "barkskin", "clearcasting", "zhc" },
            debuffs = { "demoRoar", "ffFeral" } },
          glows = { ["debuffs:demoRoar"] = { { when = "expiring", style = "pulse" } },
                    ["buffs:clearcasting"] = { { when = "active", style = "shine" } } },
          tbc = { show = {
              main = { "mangleBear", "frenzied", "enrage", "challengingRoar", "innervate", "rebirth", "potion", "rune" },
              utility = { "maul", "swipe", "growl", "lacerate", "ffFeral", "removeCurse", "abolishPoison" },
              buffs = { "frenzied", "enrage", "clearcasting", "zhc" },
              debuffs = { "lacerateDebuff", "mangleDebuff", "demoRoar", "ffFeral" } },
            glows = { ["debuffs:demoRoar"] = { { when = "expiring", style = "pulse" } },
                      ["debuffs:lacerateDebuff"] = { { when = "expiring", style = "pulse" } },
                      mangleBear = { { when = "ready", style = "edge", combatOnly = true } } } } },
        { key = "restoration", label = "Restoration", tab = 3, aux = true, res = { regen = true }, show = {
            main = { "ns", "innervate", "tranquility", "rebirth", "potion", "rune" },
            utility = { "swiftmend", "rejuv", "regrowth", "removeCurse", "abolishPoison" },
            buffs = { "ns", "clearcasting", "innervate", "zhc" },
            debuffs = {} },
          glows = { ns = { { when = "ready", style = "edge", combatOnly = true } },
                    ["buffs:clearcasting"] = { { when = "active", style = "shine" } } },
          tbc = { show = {
              utility = { "swiftmend", "lifebloom", "rejuv", "regrowth", "removeCurse", "abolishPoison" } } } },
    },
    flavors = {
        tbc = { add = {
            { key = "mangleCat",     kind = "spell", spell = "mangleCat",     spellId = 33876, label = "Mangle (Cat)" },
            { key = "mangleBear",    kind = "spell", spell = "mangleBear",    spellId = 33878, label = "Mangle (Bear)" },
            { key = "maim",          kind = "spell", spell = "maim",          spellId = 22570, label = "Maim" },
            { key = "cyclone",       kind = "spell", spell = "cyclone",       spellId = 33786, label = "Cyclone" },
            { key = "forceOfNature", kind = "spell", spell = "forceOfNature", spellId = 33831, label = "Force of Nature", noRange = true },
            { key = "lacerate",      kind = "spell", spell = "lacerate",      spellId = 33745, label = "Lacerate", row = "utility" },
            { key = "lifebloom",     kind = "spell", spell = "lifebloom",     spellId = 33763, label = "Lifebloom", row = "utility" },
            { key = "lifebloomBuff", id = 33763, label = "Lifebloom (self)", row = "buffs" },
            { key = "lacerateDebuff", id = 33745, label = "Lacerate", row = "debuffs" },
            { key = "mangleDebuff",   id = 33876, label = "Mangle", row = "debuffs" },
        } },
    },
    buffBars = { "tigersFury", "naturesGrace", "clearcasting", "enrage" },
    bars = { "mana", "fsr", "power", "tick", "combo", "swing" },
})
