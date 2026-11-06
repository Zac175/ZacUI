-- HUD_Shaman - the Shaman HUD, built by HUD_ClassHUD from this
-- definition: cooldown grid (shocks, the totems with a cooldown, the
-- talent cooldowns), active buffs, your shocks on the target, reminders
-- for Lightning Shield and the weapon enchant, mana + five-second-rule
-- bars and a swing timer.
-- Part of ZacUI; load order is set by the TOC.

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass then return end

ns.HUD.DefineClass({
    class = "SHAMAN", className = "Shaman", label = "Shaman HUD", store = "shaman",
    prefix = "sh", frameName = "Shaman", weaponEnchant = true,
    blurb = "Cooldown grid, active buffs, your shocks on the target, Lightning Shield "
        .. "and weapon enchant reminders, mana + five-second-rule bars and a swing timer.",
    keywords = "shaman hud class pack cooldown grid shock totem windfury rockbiter "
        .. "lightning shield mana tide nature's swiftness swing timer trinkets racial",

    spells = {
        earthShock = 10414, frostShock = 10473, flameShock = 10448, grounding = 8177,
        windfuryTotem = 10614, tremor = 8143, manaTide = 16190, ns = 16188,
        elemMastery = 16166, stormstrike = 17364, purge = 8012, earthbind = 2484,
        fireNova = 11315, reincarnation = 20608, lightningShield = 10432,
        ghostWolf = 2645, rockbiter = 16316, flametongue = 16342,
        windfuryWeapon = 16362, frostbrand = 16356,
    },

    grid = {
        { key = "earthShock",    kind = "spell", spell = "earthShock",    label = "Earth Shock" },
        { key = "frostShock",    kind = "spell", spell = "frostShock",    label = "Frost Shock" },
        { key = "flameShock",    kind = "spell", spell = "flameShock",    label = "Flame Shock" },
        { key = "grounding",     kind = "spell", spell = "grounding",     label = "Grounding Totem", noRange = true },
        { key = "windfuryTotem", kind = "spell", spell = "windfuryTotem", label = "Windfury Totem", noRange = true },
        { key = "tremor",        kind = "spell", spell = "tremor",        label = "Tremor Totem", noRange = true },
        { key = "manaTide",      kind = "spell", spell = "manaTide",      label = "Mana Tide Totem", noRange = true },
        { key = "ns",            kind = "spell", spell = "ns",            label = "Nature's Swiftness", noRange = true },
        { key = "elemMastery",   kind = "spell", spell = "elemMastery",   label = "Elemental Mastery", noRange = true },
        { key = "stormstrike",   kind = "spell", spell = "stormstrike",   label = "Stormstrike" },
        { key = "purge",         kind = "spell", spell = "purge",         label = "Purge" },
        { key = "earthbind",     kind = "spell", spell = "earthbind",     label = "Earthbind Totem", noRange = true },
        { key = "fireNova",      kind = "spell", spell = "fireNova",      label = "Fire Nova Totem", noRange = true },
        { key = "reincarnation", kind = "spell", spell = "reincarnation", label = "Reincarnation", noRange = true },
        { key = "potion",        kind = "itemPotion", label = "Potion" },
        { key = "rune",          kind = "itemRune",   label = "Rune" },
    },

    buffRow = {
        { key = "ns",              id = 16188 },
        { key = "elemMastery",     id = 16166 },
        { key = "lightningShield", id = 10432 },
        { key = "manaTide",        id = 16191, label = "Mana Tide" },
        { key = "windfury",        id = 10614, label = "Windfury Totem" },
        { key = "flurry",          id = 16280, label = "Flurry" },
        { key = "clearcasting",    id = 16246, label = "Clearcasting" },
        { key = "ghostWolf",       id = 2645 },
        { key = "zhc",             id = 24659, name = "Zandalarian Hero Charm", label = "Zandalarian Hero Charm" },
    },

    debuffRow = {
        { key = "flameShock",  id = 10448 },
        { key = "frostShock",  id = 10473 },
        { key = "earthShock",  id = 10414 },
        { key = "stormstrike", id = 17364 },
        { key = "earthbind",   id = 3600, label = "Earthbind" },
    },

    reminders = {
        { key = "shield", label = "Lightning Shield down", spell = "lightningShield",
          check = function(H) return H.Known("lightningShield") and not H.Buff("lightningShield") end },
        { key = "weapon", label = "No weapon enchant", icon = 136241,
          check = function(H, S)
              if not H.Known("rockbiter") then return false end
              if S.mhEnchant then
                  if S.mhEnchantLeft > 0 and S.mhEnchantLeft < 120 then return true, 136241, nil, S.mhEnchantLeft end
                  return false
              end
              return true
          end },
    },

    bars = { "mana", "fsr", "swing" },
})
