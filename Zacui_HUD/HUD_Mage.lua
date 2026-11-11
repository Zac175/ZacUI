-- HUD_Mage - the Mage HUD, built by HUD_ClassHUD from this definition:
-- cooldown grid (with the mana gem), active buffs, your debuffs on the
-- target, Arcane Intellect and armor reminders, mana + five-second-rule
-- bars and a wand swing bar.
-- Part of ZacUI; load order is set by the TOC.

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass then return end
if ns.HUD.RETAIL then return end   -- (Retail: its own class HUD, HUD_Retail.lua; this Classic one never loads there)

local ARMORS = { "iceArmor", "frostArmor", "mageArmor", "moltenArmor" }

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
        removeCurse = 475, slowFall = 130, dampen = 10174, amplifyMagic = 10170, arcaneExplosion = 10202,
        blizzard = 10187, flamestrike = 10216, scorch = 10207, arcaneBrilliance = 23028, conjureGem = 10054,
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
          -- (22044: TBC's Mana Emerald; the item does not exist on Era)
          items = { { id = 22044 }, { id = 8008 }, { id = 8007 }, { id = 5513 }, { id = 5514 } } },
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


    -- Class HUD v2: the utility row, the roles, TBC's additions (and the
    -- ids TBC moved: Cold Snap, Ice Block, Icy Veins)
    utility = {
        { key = "manaShield",      kind = "spell", spell = "manaShield",      label = "Mana Shield", noRange = true },
        { key = "removeCurse",     kind = "spell", spell = "removeCurse",     label = "Remove Lesser Curse" },
        { key = "arcaneExplosion", kind = "spell", spell = "arcaneExplosion", label = "Arcane Explosion", noRange = true },
        { key = "blizzard",        kind = "spell", spell = "blizzard",        label = "Blizzard", noRange = true },
        { key = "flamestrike",     kind = "spell", spell = "flamestrike",     label = "Flamestrike", noRange = true },
        { key = "scorch",          kind = "spell", spell = "scorch",          label = "Scorch" },
        { key = "arcaneIntellect", kind = "spell", spell = "arcaneIntellect", label = "Arcane Intellect" },
        { key = "arcaneBrilliance", kind = "spell", spell = "arcaneBrilliance", label = "Arcane Brilliance" },
        { key = "conjureGem",      kind = "spell", spell = "conjureGem",      label = "Conjure Mana Gem", noRange = true },
        { key = "slowFall",        kind = "spell", spell = "slowFall",        label = "Slow Fall" },
        { key = "dampen",          kind = "spell", spell = "dampen",          label = "Dampen Magic" },
        { key = "amplifyMagic",    kind = "spell", spell = "amplifyMagic",    label = "Amplify Magic" },
    },
    -- Spec presets (HUD_V2_Specs): each spec's default HUD, from what top
    -- players press and track (sources in CLASSHUD_V2_DESIGN_1107.md
    -- section 13: Icy Veins' Classic mage guide, its TBC Arcane / Fire /
    -- Frost guides, Warcraft Tavern's Classic Fire guide; WoW Forever:
    -- wowtbc.gg's and Warcraft Tavern's Forever mage guides). The base lists are
    -- Classic Era's; a spec's tbc / forever block replaces the rows it
    -- names on that game. WoW Forever (1.60) reworked the trees: Arcane
    -- Blast stacks into Arcane Wrath / Missile Barrage, Fire's Heating Up
    -- into Pyroblast, Frost's Ice Lance on Fingers of Frost.
    roles = {
        { key = "arcane", label = "Arcane", tab = 1, aux = true, res = { regen = true }, show = {
            main = { "arcanePower", "pom", "evocation", "counterspell", "blink", "iceBlock", "gem", "potion", "rune" },
            utility = { "arcaneExplosion", "removeCurse", "arcaneIntellect", "arcaneBrilliance", "conjureGem" },
            buffs = { "arcanePower", "pom", "clearcasting", "evocation", "mqg", "zhc" },
            debuffs = {} },
          glows = { arcanePower = { { when = "ready", style = "edge", combatOnly = true } },
                    ["buffs:clearcasting"] = { { when = "active", style = "shine" } } },
          tbc = { show = {
              main = { "arcanePower", "icyVeins", "coldSnap", "pom", "evocation", "counterspell", "blink", "iceBlock", "gem", "potion", "rune" },
              utility = { "arcaneExplosion", "removeCurse", "arcaneIntellect", "arcaneBrilliance", "conjureGem", "spellsteal", "invisibility" },
              buffs = { "arcanePower", "icyVeinsBuff", "pom", "clearcasting", "evocation", "zhc" } },
            glows = { arcanePower = { { when = "ready", style = "edge", combatOnly = true } },
                      icyVeins = { { when = "ready", style = "edge", combatOnly = true } },
                      ["buffs:clearcasting"] = { { when = "active", style = "shine" } } } },
          forever = { show = {
              main = { "arcanePower", "pom", "arcaneWrath", "fireBlast", "evocation", "counterspell", "blink", "iceBlock", "gem", "potion", "rune" },
              buffs = { "arcaneBlastBuff", "missileBarrage", "heatingUp", "arcanePower", "pom", "clearcasting", "evocation", "mqg", "zhc" } },
            glows = { arcanePower = { { when = "ready", style = "edge", combatOnly = true } },
                      ["buffs:missileBarrage"] = { { when = "active", style = "shine" } },
                      ["buffs:heatingUp"] = { { when = "stacks", stacksOp = ">=", stacksN = 3, style = "shine" } },
                      ["buffs:clearcasting"] = { { when = "active", style = "shine" } } } } },
        { key = "fire", label = "Fire", tab = 2, aux = true, res = { regen = true }, show = {
            main = { "combustion", "fireBlast", "evocation", "counterspell", "blink", "iceBlock", "gem", "potion", "rune" },
            utility = { "scorch", "flamestrike", "removeCurse", "arcaneIntellect", "arcaneBrilliance", "conjureGem" },
            buffs = { "combustion", "clearcasting", "evocation", "mqg", "zhc" },
            debuffs = { "fireVuln", "ignite" } },
          glows = { combustion = { { when = "ready", style = "edge", combatOnly = true } },
                    ["debuffs:fireVuln"] = { { when = "expiring", style = "pulse" } },
                    ["buffs:clearcasting"] = { { when = "active", style = "shine" } } },
          tbc = { show = {
              main = { "combustion", "icyVeins", "coldSnap", "fireBlast", "evocation", "counterspell", "blink", "iceBlock", "gem", "potion", "rune" },
              utility = { "scorch", "flamestrike", "removeCurse", "arcaneIntellect", "arcaneBrilliance", "conjureGem", "spellsteal", "invisibility" },
              buffs = { "combustion", "icyVeinsBuff", "clearcasting", "evocation", "zhc" } },
            glows = { combustion = { { when = "ready", style = "edge", combatOnly = true } },
                      icyVeins = { { when = "ready", style = "edge", combatOnly = true } },
                      ["debuffs:fireVuln"] = { { when = "expiring", style = "pulse" } } } },
          forever = { show = {
              buffs = { "heatingUp", "combustion", "missileBarrage", "clearcasting", "evocation", "mqg", "zhc" } },
            glows = { combustion = { { when = "ready", style = "edge", combatOnly = true } },
                      ["debuffs:fireVuln"] = { { when = "expiring", style = "pulse" } },
                      ["buffs:heatingUp"] = { { when = "stacks", stacksOp = ">=", stacksN = 3, style = "shine" } },
                      ["buffs:clearcasting"] = { { when = "active", style = "shine" } } } } },
        { key = "frost", label = "Frost", tab = 3, aux = true, res = { regen = true }, show = {
            main = { "coldSnap", "iceBlock", "evocation", "counterspell", "blink", "gem", "potion", "rune" },
            utility = { "blizzard", "removeCurse", "arcaneIntellect", "arcaneBrilliance", "conjureGem" },
            buffs = { "clearcasting", "evocation", "mqg", "zhc" },
            debuffs = { "wintersChill" } },
          glows = { ["buffs:clearcasting"] = { { when = "active", style = "shine" } } },
          tbc = { show = {
              main = { "icyVeins", "waterElemental", "coldSnap", "iceBlock", "evocation", "counterspell", "blink", "gem", "potion", "rune" },
              utility = { "blizzard", "removeCurse", "arcaneIntellect", "arcaneBrilliance", "conjureGem", "spellsteal", "invisibility" },
              buffs = { "icyVeinsBuff", "clearcasting", "evocation", "zhc" } },
            glows = { icyVeins = { { when = "ready", style = "edge", combatOnly = true } },
                      waterElemental = { { when = "ready", style = "edge", combatOnly = true } } } },
          forever = { show = {
              main = { "coldSnap", "iceLance", "coneOfCold", "iceBarrier", "iceBlock", "evocation", "counterspell", "blink", "gem", "potion", "rune" },
              buffs = { "fingersOfFrost", "iceBarrier", "clearcasting", "evocation", "mqg", "zhc" } },
            glows = { ["buffs:fingersOfFrost"] = { { when = "active", style = "shine" } },
                      ["buffs:clearcasting"] = { { when = "active", style = "shine" } } } } },
    },
    flavors = {
        tbc = {
            -- (27101: Conjure Mana Emerald)
            spells = { coldSnap = 11958, iceBlock = 45438, moltenArmor = 30482, conjureGem = 27101 },
            add = {
                { key = "icyVeins",       kind = "spell", spell = "icyVeins",       spellId = 12472, label = "Icy Veins", noRange = true },
                { key = "dragonsBreath",  kind = "spell", spell = "dragonsBreath",  spellId = 31661, label = "Dragon's Breath", noRange = true },
                { key = "waterElemental", kind = "spell", spell = "waterElemental", spellId = 31687, label = "Summon Water Elemental", noRange = true },
                { key = "spellsteal",     kind = "spell", spell = "spellsteal",     spellId = 30449, label = "Spellsteal", row = "utility" },
                { key = "invisibility",   kind = "spell", spell = "invisibility",   spellId = 66,    label = "Invisibility", noRange = true, row = "utility" },
                { key = "icyVeinsBuff",   id = 12472, label = "Icy Veins", row = "buffs" },
            },
        },
        -- WoW Forever's own talents (ids: warcraft.wiki.gg's Forever pages).
        -- The Arcane Blast stack is matched by its name; its id only
        -- finds the icon.
        forever = {
            add = {
                { key = "arcaneWrath",     kind = "spell", spell = "arcaneWrath", spellId = 1326082, label = "Arcane Wrath" },
                { key = "iceLance",        kind = "spell", spell = "iceLance",    spellId = 1240047, label = "Ice Lance" },
                { key = "arcaneBlastBuff", id = 400574, name = "Arcane Blast", label = "Arcane Blast", row = "buffs" },
                { key = "missileBarrage",  id = 400589, label = "Missile Barrage", row = "buffs" },
                { key = "heatingUp",       id = 400624, label = "Heating Up", row = "buffs" },
                { key = "fingersOfFrost",  id = 400647, label = "Fingers of Frost", row = "buffs" },
            },
        },
    },
    buffBars = { "arcanePower", "pom", "iceBarrier", "clearcasting" },
    bars = { "mana", "fsr", "wand" },
})
