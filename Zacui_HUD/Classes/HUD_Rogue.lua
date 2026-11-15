-- HUD_Rogue - the Rogue HUD, built by HUD_ClassHUD from this definition:
-- cooldown grid, active buffs (Slice and Dice first), your bleeds,
-- stuns and poisons on the target, poison reminders for each weapon,
-- an energy bar with the tick under it, combo points and a swing timer.
-- Part of ZacUI; load order is set by the TOC.

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass then return end
if ns.HUD.RETAIL then return end   -- (Retail: its own class HUD, HUD_Retail.lua; this Classic one never loads there)

ns.HUD.DefineClass({
    class = "ROGUE", className = "Rogue", label = "Rogue HUD", store = "rogue",
    prefix = "rg", frameName = "Rogue", powerLabel = "Energy", weaponEnchant = true,
    blurb = "Cooldown grid, active buffs, your bleeds and poisons on the target, "
        .. "poison reminders, energy + tick bars, combo points and a swing timer.",
    keywords = "rogue hud class pack cooldown grid energy combo points slice and dice "
        .. "poison vanish sprint evasion kick blind swing timer trinkets racial",

    spells = {
        sprint = 11305, evasion = 5277, vanish = 1857, kick = 1769, kidney = 8643,
        gouge = 1776, blind = 2094, coldBlood = 14177, adrenaline = 13750,
        bladeFlurry = 13877, prep = 14185, ghostly = 14278, riposte = 14251,
        distract = 1725, cheapShot = 1833, premeditation = 14183, sliceDice = 6774,
        stealth = 1784, rupture = 11275, garrote = 11290, exposeArmor = 11198,
        hemo = 17348, sap = 11297, feint = 25302,
    },

    grid = {
        { key = "sprint",        kind = "spell", spell = "sprint",        label = "Sprint", noRange = true },
        { key = "evasion",       kind = "spell", spell = "evasion",       label = "Evasion", noRange = true },
        { key = "vanish",        kind = "spell", spell = "vanish",        label = "Vanish", noRange = true },
        { key = "kick",          kind = "spell", spell = "kick",          label = "Kick" },
        { key = "kidney",        kind = "spell", spell = "kidney",        label = "Kidney Shot" },
        { key = "gouge",         kind = "spell", spell = "gouge",         label = "Gouge" },
        { key = "blind",         kind = "spell", spell = "blind",         label = "Blind" },
        { key = "coldBlood",     kind = "spell", spell = "coldBlood",     label = "Cold Blood", noRange = true },
        { key = "adrenaline",    kind = "spell", spell = "adrenaline",    label = "Adrenaline Rush", noRange = true },
        { key = "bladeFlurry",   kind = "spell", spell = "bladeFlurry",   label = "Blade Flurry", noRange = true },
        { key = "prep",          kind = "spell", spell = "prep",          label = "Preparation", noRange = true },
        { key = "ghostly",       kind = "spell", spell = "ghostly",       label = "Ghostly Strike" },
        { key = "riposte",       kind = "spell", spell = "riposte",       label = "Riposte" },
        { key = "premeditation", kind = "spell", spell = "premeditation", label = "Premeditation" },
        { key = "distract",      kind = "spell", spell = "distract",      label = "Distract", noRange = true },
        { key = "tea",           kind = "item", label = "Thistle Tea", items = { { id = 7676 } } },
        { key = "potion",        kind = "itemPotion", label = "Potion" },
        { key = "rune",          kind = "itemRune",   label = "Rune" },
    },

    buffRow = {
        { key = "sliceDice",   id = 6774 },
        { key = "evasion",     id = 5277 },
        { key = "sprint",      id = 11305 },
        { key = "bladeFlurry", id = 13877 },
        { key = "adrenaline",  id = 13750 },
        { key = "coldBlood",   id = 14177 },
        { key = "stealth",     id = 1784 },
        { key = "remorseless", id = 14149, label = "Remorseless Attacks" },
        { key = "ghostly",     id = 14278 },
        { key = "zhc",         id = 24659, name = "Zandalarian Hero Charm", label = "Zandalarian Hero Charm" },
    },

    debuffRow = {
        { key = "rupture",     id = 11275, castsDot = true },
        { key = "garrote",     id = 11290, castsDot = true },
        { key = "kidney",      id = 8643 },
        { key = "cheapShot",   id = 1833 },
        { key = "exposeArmor", id = 11198 },
        { key = "hemo",        id = 17348 },
        { key = "gouge",       id = 1776 },
        { key = "blind",       id = 2094 },
        { key = "sap",         id = 11297 },
        { key = "deadly",      id = 25349, label = "Deadly Poison" },
        { key = "crippling",   id = 11201, label = "Crippling Poison" },
        { key = "wound",       id = 13224, label = "Wound Poison" },
        { key = "mindNumbing", id = 11398, label = "Mind-numbing Poison" },
    },

    reminders = {
        { key = "mhPoison", label = "Main hand has no poison", icon = 132273,
          check = function(H, S)
              if S.mhEnchant then
                  if S.mhEnchantLeft > 0 and S.mhEnchantLeft < 300 then return true, 132273, nil, S.mhEnchantLeft end
                  return false
              end
              return true
          end },
        { key = "ohPoison", label = "Off hand has no poison", icon = 132274,
          check = function(H, S)
              if not S.hasOffhand then return false end
              if S.ohEnchant then
                  if S.ohEnchantLeft > 0 and S.ohEnchantLeft < 300 then return true, 132274, nil, S.ohEnchantLeft end
                  return false
              end
              return true
          end },
    },


    -- Class HUD v2: the utility row, the roles, TBC's additions
    utility = {
        { key = "sliceDice",   kind = "spell", spell = "sliceDice",   label = "Slice and Dice", noRange = true },
        { key = "rupture",     kind = "spell", spell = "rupture",     label = "Rupture" },
        { key = "garrote",     kind = "spell", spell = "garrote",     label = "Garrote" },
        { key = "cheapShot",   kind = "spell", spell = "cheapShot",   label = "Cheap Shot" },
        { key = "exposeArmor", kind = "spell", spell = "exposeArmor", label = "Expose Armor" },
        { key = "hemo",        kind = "spell", spell = "hemo",        label = "Hemorrhage" },
        { key = "feint",       kind = "spell", spell = "feint",       label = "Feint" },
        { key = "stealth",     kind = "spell", spell = "stealth",     label = "Stealth", noRange = true },
        { key = "sap",         kind = "spell", spell = "sap",         label = "Sap" },
    },
    -- Spec presets (HUD_V2_Specs): each spec's default HUD, from what top
    -- players press and track (sources in CLASSHUD_V2_DESIGN_1107.md
    -- section 13: Icy Veins' and Wowhead's Classic and TBC rogue guides).
    -- The base lists are Classic Era's (no Rupture / Expose Armor / poison
    -- debuffs there: debuff slots and the warrior's Sunder); a spec's tbc
    -- or forever block replaces the rows it names on that game version
    -- (WoW Forever: Shank, Venom and Death Mark are its own, and its bleeds
    -- and Deadly Poison are worth a slot there).
    roles = {
        { key = "assassination", label = "Assassination", tab = 1, aux = true, res = { rangeDim = true }, show = {
            main = { "kick", "coldBlood", "vanish", "tea", "potion", "rune" },
            utility = { "sliceDice", "feint", "stealth", "sap", "cheapShot", "garrote" },
            buffs = { "sliceDice", "coldBlood", "zhc" },
            debuffs = {} },
          glows = { ["buffs:sliceDice"] = { { when = "expiring", style = "pulse" } },
                    coldBlood = { { when = "ready", style = "edge", combatOnly = true } } },
          tbc = { show = {
              main = { "kick", "coldBlood", "vanish", "cloakOfShadows", "tea", "potion", "rune" },
              utility = { "sliceDice", "rupture", "exposeArmor", "feint", "shiv", "stealth", "sap" },
              buffs = { "sliceDice", "findWeakness", "coldBlood", "zhc" },
              debuffs = { "rupture", "exposeArmor", "deadly", "deadly7" } },
            glows = { ["buffs:sliceDice"] = { { when = "expiring", style = "pulse" } },
                      ["debuffs:rupture"] = { { when = "anticlip", style = "solid" } },
                      ["debuffs:exposeArmor"] = { { when = "expiring", style = "pulse" } } } },
          forever = { show = {
              main = { "kick", "shank", "coldBlood", "vanish", "tea", "potion", "rune" },
              buffs = { "sliceDice", "venom", "coldBlood", "zhc" },
              debuffs = { "rupture", "garrote", "deadly", "deadly4" } } } },
        { key = "combat", label = "Combat", tab = 2, aux = true, res = { rangeDim = true }, show = {
            main = { "kick", "adrenaline", "bladeFlurry", "vanish", "tea", "potion", "rune" },
            utility = { "sliceDice", "feint", "stealth", "sap", "cheapShot" },
            buffs = { "sliceDice", "adrenaline", "bladeFlurry", "zhc" },
            debuffs = {} },
          glows = { ["buffs:sliceDice"] = { { when = "expiring", style = "pulse" } },
                    adrenaline = { { when = "ready", style = "edge", combatOnly = true } },
                    bladeFlurry = { { when = "ready", style = "edge", combatOnly = true } } },
          tbc = { show = {
              main = { "kick", "adrenaline", "bladeFlurry", "vanish", "cloakOfShadows", "tea", "potion", "rune" },
              utility = { "sliceDice", "rupture", "exposeArmor", "feint", "shiv", "stealth", "sap" },
              debuffs = { "rupture", "exposeArmor", "deadly", "deadly7" } },
            glows = { ["buffs:sliceDice"] = { { when = "expiring", style = "pulse" } },
                      ["debuffs:rupture"] = { { when = "anticlip", style = "solid" } },
                      ["debuffs:exposeArmor"] = { { when = "expiring", style = "pulse" } },
                      adrenaline = { { when = "ready", style = "edge", combatOnly = true } },
                      bladeFlurry = { { when = "ready", style = "edge", combatOnly = true } } } },
          forever = { show = {
              main = { "kick", "shank", "adrenaline", "bladeFlurry", "vanish", "tea", "potion", "rune" },
              debuffs = { "rupture", "garrote", "deadly", "deadly4" } } } },
        { key = "subtlety", label = "Subtlety", tab = 3, aux = true, res = { rangeDim = true }, show = {
            main = { "kick", "prep", "ghostly", "vanish", "tea", "potion", "rune" },
            utility = { "sliceDice", "hemo", "feint", "stealth", "sap", "cheapShot", "garrote" },
            buffs = { "sliceDice", "ghostly", "zhc" },
            debuffs = {} },
          glows = { ["buffs:sliceDice"] = { { when = "expiring", style = "pulse" } } },
          tbc = { show = {
              main = { "kick", "prep", "shadowstep", "vanish", "cloakOfShadows", "tea", "potion", "rune" },
              utility = { "sliceDice", "hemo", "rupture", "exposeArmor", "feint", "shiv", "stealth", "sap" },
              debuffs = { "rupture", "hemo", "exposeArmor", "deadly", "deadly7" } },
            glows = { ["buffs:sliceDice"] = { { when = "expiring", style = "pulse" } },
                      ["debuffs:rupture"] = { { when = "anticlip", style = "solid" } } } },
          forever = { show = {
              main = { "kick", "shank", "deathMark", "prep", "ghostly", "vanish", "tea", "potion", "rune" },
              debuffs = { "rupture", "garrote", "hemo", "deathMarkDebuff", "deadly", "deadly4" } } } },
    },
    -- The poison debuffs are found by name, and Deadly Poison's carries
    -- its rank: V is Classic Era's top rank and VII is TBC's (the entry is
    -- swapped there); WoW Forever's trainers stop at IV, so it has both.
    flavors = {
        tbc = { add = {
            { key = "shadowstep",     kind = "spell", spell = "shadowstep",     spellId = 36554, label = "Shadowstep" },
            { key = "cloakOfShadows", kind = "spell", spell = "cloakOfShadows", spellId = 31224, label = "Cloak of Shadows", noRange = true },
            { key = "deadlyThrow",    kind = "spell", spell = "deadlyThrow",    spellId = 26679, label = "Deadly Throw", row = "utility" },
            { key = "shiv",           kind = "spell", spell = "shiv",           spellId = 5938,  label = "Shiv", row = "utility" },
            { key = "cloakBuff",      id = 31224, label = "Cloak of Shadows", row = "buffs" },
            { key = "findWeakness",   id = 31238, label = "Find Weakness", row = "buffs" },
            -- (level 70's rank has its own aura name; the base entry is rank V)
            { key = "deadly7",        id = 27187, label = "Deadly Poison VII", row = "debuffs" },
            { key = "anesthetic",     id = 26688, label = "Anesthetic Poison", row = "debuffs" },
        } },
        forever = { add = {
            { key = "shank",           kind = "spell", spell = "shank",     spellId = 1329283, label = "Shank" },
            { key = "deathMark",       kind = "spell", spell = "deathMark", spellId = 1316709, label = "Death Mark" },
            { key = "venom",           id = 1310703, label = "Venom", row = "buffs" },
            { key = "deadly4",         id = 11354,   label = "Deadly Poison IV", row = "debuffs" },
            { key = "deathMarkDebuff", id = 1316709, label = "Death Mark", row = "debuffs" },
        } },
    },
    buffBars = { "sliceDice", "adrenaline", "bladeFlurry" },
    bars = { "power", "tick", "combo", "swing" },
})
