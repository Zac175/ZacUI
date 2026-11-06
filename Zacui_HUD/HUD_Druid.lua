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
        { key = "moonfire",    id = 9835 },
        { key = "insectSwarm", id = 24977 },
        { key = "faerieFire",  id = 9907 },
        { key = "ffFeral",     id = 17392, label = "Faerie Fire (Feral)" },
        { key = "rake",        id = 9904 },
        { key = "rip",         id = 9896 },
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

    bars = { "mana", "fsr", "power", "tick", "combo", "swing" },
})
