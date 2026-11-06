-- HUD_Mage - the Mage HUD, built by HUD_ClassHUD from this definition:
-- cooldown grid (with the mana gem), active buffs, your debuffs on the
-- target, Arcane Intellect and armor reminders, mana + five-second-rule
-- bars and a wand swing bar.
-- Part of ZacUI; load order is set by the TOC.

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass then return end

local ARMORS = { "iceArmor", "frostArmor", "mageArmor" }

ns.HUD.DefineClass({
    class = "MAGE", className = "Mage", label = "Mage HUD", store = "mage",
    prefix = "mg", frameName = "Mage",
    blurb = "Cooldown grid with the mana gem, active buffs, your debuffs on the target, "
        .. "Arcane Intellect and armor reminders, mana + five-second-rule bars and a wand bar.",
    keywords = "mage hud class pack cooldown grid counterspell blink ice block evocation "
        .. "mana gem arcane intellect armor polymorph wand bar mana bar trinkets racial",

    spells = {
        counterspell = 2139, blink = 1953, frostNova = 10230, iceBlock = 11958,
        coldSnap = 12472, iceBarrier = 13033, pom = 12043, arcanePower = 12042,
        combustion = 11129, blastWave = 13021, coneOfCold = 10161, evocation = 12051,
        polymorph = 12826, fireBlast = 10199, manaShield = 10193,
        arcaneIntellect = 10157, iceArmor = 10220, frostArmor = 7301, mageArmor = 22783,
        fireWard = 10225, frostWard = 10177,
    },

    grid = {
        { key = "counterspell", kind = "spell", spell = "counterspell", label = "Counterspell" },
        { key = "blink",        kind = "spell", spell = "blink",        label = "Blink", noRange = true },
        { key = "frostNova",    kind = "spell", spell = "frostNova",    label = "Frost Nova", noRange = true },
        { key = "iceBlock",     kind = "spell", spell = "iceBlock",     label = "Ice Block", noRange = true },
        { key = "coldSnap",     kind = "spell", spell = "coldSnap",     label = "Cold Snap", noRange = true },
        { key = "iceBarrier",   kind = "spell", spell = "iceBarrier",   label = "Ice Barrier", noRange = true },
        { key = "pom",          kind = "spell", spell = "pom",          label = "Presence of Mind", noRange = true },
        { key = "arcanePower",  kind = "spell", spell = "arcanePower",  label = "Arcane Power", noRange = true },
        { key = "combustion",   kind = "spell", spell = "combustion",   label = "Combustion", noRange = true },
        { key = "blastWave",    kind = "spell", spell = "blastWave",    label = "Blast Wave", noRange = true },
        { key = "coneOfCold",   kind = "spell", spell = "coneOfCold",   label = "Cone of Cold", noRange = true },
        { key = "evocation",    kind = "spell", spell = "evocation",    label = "Evocation", noRange = true },
        { key = "fireBlast",    kind = "spell", spell = "fireBlast",    label = "Fire Blast" },
        { key = "fireWard",     kind = "spell", spell = "fireWard",     label = "Fire Ward", noRange = true },
        { key = "frostWard",    kind = "spell", spell = "frostWard",    label = "Frost Ward", noRange = true },
        { key = "gem",          kind = "item", label = "Mana Gem",
          items = { { id = 8008 }, { id = 8007 }, { id = 5513 }, { id = 5514 } } },
        { key = "potion",       kind = "itemPotion", label = "Potion" },
        { key = "rune",         kind = "itemRune",   label = "Rune" },
    },

    buffRow = {
        { key = "arcanePower",  id = 12042 },
        { key = "pom",          id = 12043 },
        { key = "iceBarrier",   id = 13033 },
        { key = "manaShield",   id = 10193 },
        { key = "fireWard",     id = 10225 },
        { key = "frostWard",    id = 10177 },
        { key = "combustion",   id = 28682, label = "Combustion" },
        { key = "clearcasting", id = 12536, label = "Clearcasting" },
        { key = "iceBlock",     id = 11958 },
        { key = "evocation",    id = 12051 },
        { key = "mqg",          id = 23723, label = "Mind Quickening" },
        { key = "zhc",          id = 24659, name = "Zandalarian Hero Charm", label = "Zandalarian Hero Charm" },
    },

    debuffRow = {
        { key = "polymorph",    id = 12826 },
        { key = "frostNova",    id = 10230 },
        { key = "coneOfCold",   id = 10161 },
        { key = "frostbolt",    id = 25304, label = "Frostbolt (slow)" },
        { key = "fireball",     id = 10151, label = "Fireball (burn)" },
        { key = "pyroblast",    id = 18809, label = "Pyroblast (burn)" },
        { key = "ignite",       id = 12654, label = "Ignite" },
        { key = "wintersChill", id = 12579, label = "Winter's Chill" },
        { key = "fireVuln",     id = 22959, label = "Fire Vulnerability" },
        { key = "frostbite",    id = 12494, label = "Frostbite" },
    },

    reminders = {
        { key = "intellect", label = "Arcane Intellect down", spell = "arcaneIntellect",
          check = function(H)
              if not H.Known("arcaneIntellect") then return false end
              return not (H.Buff("arcaneIntellect") or H.Buff("Arcane Brilliance"))
          end },
        { key = "armor", label = "No armor spell", spell = "iceArmor",
          check = function(H)
              if not (H.Known("iceArmor") or H.Known("frostArmor") or H.Known("mageArmor")) then return false end
              return not H.AnyBuff(ARMORS)
          end },
    },

    bars = { "mana", "fsr", "wand" },
})
