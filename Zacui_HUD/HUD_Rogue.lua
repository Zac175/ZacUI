-- HUD_Rogue - the Rogue HUD, built by HUD_ClassHUD from this definition:
-- cooldown grid, active buffs (Slice and Dice first), your bleeds,
-- stuns and poisons on the target, poison reminders for each weapon,
-- an energy bar with the tick under it, combo points and a swing timer.
-- Part of ZacUI; load order is set by the TOC.

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass then return end

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
        hemo = 17348, sap = 11297,
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
        { key = "rupture",     id = 11275 },
        { key = "garrote",     id = 11290 },
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

    bars = { "power", "tick", "combo", "swing" },
})
