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
        chainLightning = 10605, searingTotem = 10438, stoneclaw = 10428, strengthOfEarth = 25361,
        manaSpring = 10497, healingStream = 10463, poisonCleansing = 8166, diseaseCleansing = 8170,
        curePoison = 526, cureDisease = 2870, astralRecall = 556,
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
        { key = "flameShock",  id = 10448, castsDot = true },
        { key = "frostShock",  id = 10473 },
        { key = "earthShock",  id = 10414 },
        { key = "stormstrike", id = 17364 },
        { key = "earthbind",   id = 3600, label = "Earthbind" },
    },

    reminders = {
        { key = "shield", label = "Lightning Shield down", spell = "lightningShield",
          -- (TBC: Water Shield or Earth Shield on yourself counts; neither exists on Era)
          check = function(H) return H.Known("lightningShield") and not (H.Buff("lightningShield") or H.Buff("waterShield") or H.Buff("earthShield")) end },
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


    -- Class HUD v2: the utility row, the roles, TBC's additions
    utility = {
        { key = "chainLightning",  kind = "spell", spell = "chainLightning",  label = "Chain Lightning" },
        { key = "lightningShield", kind = "spell", spell = "lightningShield", label = "Lightning Shield", noRange = true },
        { key = "ghostWolf",       kind = "spell", spell = "ghostWolf",       label = "Ghost Wolf", noRange = true },
        { key = "searingTotem",    kind = "spell", spell = "searingTotem",    label = "Searing Totem", noRange = true },
        { key = "stoneclaw",       kind = "spell", spell = "stoneclaw",       label = "Stoneclaw Totem", noRange = true },
        { key = "strengthOfEarth", kind = "spell", spell = "strengthOfEarth", label = "Strength of Earth Totem", noRange = true },
        { key = "manaSpring",      kind = "spell", spell = "manaSpring",      label = "Mana Spring Totem", noRange = true },
        { key = "healingStream",   kind = "spell", spell = "healingStream",   label = "Healing Stream Totem", noRange = true },
        { key = "poisonCleansing", kind = "spell", spell = "poisonCleansing", label = "Poison Cleansing Totem", noRange = true },
        { key = "diseaseCleansing", kind = "spell", spell = "diseaseCleansing", label = "Disease Cleansing Totem", noRange = true },
        { key = "curePoison",      kind = "spell", spell = "curePoison",      label = "Cure Poison" },
        { key = "cureDisease",     kind = "spell", spell = "cureDisease",     label = "Cure Disease" },
        { key = "astralRecall",    kind = "spell", spell = "astralRecall",    label = "Astral Recall", noRange = true },
    },
    -- Spec presets (HUD_V2_Specs): each spec's default HUD, from what top
    -- players press and track (sources in CLASSHUD_V2_DESIGN_1107.md
    -- section 13: Icy Veins' Classic / TBC shaman guides). The base lists
    -- are Classic Era's (WoW Forever plays them too); a spec's tbc block
    -- replaces the rows it names on TBC.
    roles = {
        { key = "elemental", label = "Elemental", tab = 1, aux = true, res = { regen = true }, show = {
            main = { "elemMastery", "ns", "earthShock", "manaTide", "reincarnation", "potion", "rune" },
            utility = { "chainLightning", "lightningShield", "manaSpring", "searingTotem", "ghostWolf", "poisonCleansing", "diseaseCleansing" },
            buffs = { "elemMastery", "clearcasting", "ns", "zhc" },
            debuffs = {} },
          glows = { elemMastery = { { when = "ready", style = "edge", combatOnly = true } },
                    ["buffs:clearcasting"] = { { when = "active", style = "shine" } } },
          tbc = { show = {
              main = { "elemMastery", "bloodlust", "heroism", "fireElemental", "earthShock", "flameShock", "reincarnation", "potion", "rune" },
              buffs = { "elemMastery", "clearcasting", "waterShieldBuff", "zhc" },
              debuffs = { "flameShock" } },
            glows = { elemMastery = { { when = "ready", style = "edge", combatOnly = true } },
                      ["debuffs:flameShock"] = { { when = "anticlip", style = "solid" } },
                      ["buffs:clearcasting"] = { { when = "active", style = "shine" } } } } },
        { key = "enhancement", label = "Enhancement", tab = 2, aux = true, res = { rangeDim = true }, show = {
            main = { "stormstrike", "earthShock", "reincarnation", "potion", "rune" },
            utility = { "lightningShield", "strengthOfEarth", "searingTotem", "ghostWolf", "poisonCleansing", "diseaseCleansing" },
            buffs = { "flurry", "windfury", "zhc" },
            debuffs = { "stormstrike" } },
          glows = { stormstrike = { { when = "ready", style = "edge", combatOnly = true } } },
          tbc = { show = {
              main = { "stormstrike", "earthShock", "flameShock", "shamanisticRage", "bloodlust", "heroism", "reincarnation", "potion", "rune" },
              buffs = { "flurry", "windfury", "shamRageBuff", "lightningShield", "zhc" },
              debuffs = { "stormstrike", "flameShock" } },
            glows = { stormstrike = { { when = "ready", style = "edge", combatOnly = true } },
                      shamanisticRage = { { when = "ready", style = "edge", combatOnly = true } } } } },
        { key = "restoration", label = "Restoration", tab = 3, aux = true, res = { regen = true }, show = {
            main = { "ns", "manaTide", "earthShock", "reincarnation", "potion", "rune" },
            utility = { "healingStream", "manaSpring", "poisonCleansing", "diseaseCleansing", "curePoison", "cureDisease", "ghostWolf" },
            buffs = { "ns", "manaTide", "zhc" },
            debuffs = {} },
          glows = { ns = { { when = "ready", style = "edge", combatOnly = true } },
                    manaTide = { { when = "ready", style = "edge", combatOnly = true } } },
          tbc = { show = {
              main = { "ns", "manaTide", "earthShield", "bloodlust", "heroism", "earthShock", "reincarnation", "potion", "rune" },
              buffs = { "ns", "manaTide", "waterShieldBuff", "zhc" } } } },
    },
    flavors = {
        tbc = { add = {
            { key = "shamanisticRage", kind = "spell", spell = "shamanisticRage", spellId = 30823, label = "Shamanistic Rage", noRange = true },
            { key = "bloodlust",       kind = "spell", spell = "bloodlust",       spellId = 2825,  label = "Bloodlust", noRange = true },
            { key = "heroism",         kind = "spell", spell = "heroism",         spellId = 32182, label = "Heroism", noRange = true },
            { key = "earthShield",     kind = "spell", spell = "earthShield",     spellId = 32594, label = "Earth Shield", noRange = true },
            { key = "earthElemental",  kind = "spell", spell = "earthElemental",  spellId = 2062,  label = "Earth Elemental Totem", noRange = true, row = "utility" },
            { key = "fireElemental",   kind = "spell", spell = "fireElemental",   spellId = 2894,  label = "Fire Elemental Totem", noRange = true },
            { key = "waterShield",     kind = "spell", spell = "waterShield",     spellId = 24398, label = "Water Shield", noRange = true, row = "utility" },
            { key = "waterShieldBuff", id = 24398, label = "Water Shield", row = "buffs" },
            { key = "earthShieldBuff", id = 32594, label = "Earth Shield", row = "buffs" },
            { key = "shamRageBuff",    id = 30823, label = "Shamanistic Rage", row = "buffs" },
        } },
    },
    buffBars = { "lightningShield", "flurry", "ns" },
    bars = { "mana", "fsr", "swing" },
})
