-- HUD_Warlock - the Warlock HUD, built by HUD_ClassHUD from this
-- definition: cooldown grid (with healthstone and soulstone icons that
-- count what you carry), active buffs, your curses and DoTs on the
-- target, reminders (armor down, no pet, soul shards running out), mana
-- + five-second-rule bars and a wand swing bar.
-- Part of ZacUI; load order is set by the TOC.

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.DefineClass then return end

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
        { key = "healthstone", kind = "item", label = "Healthstone", items = {
            { id = 19013 }, { id = 19012 }, { id = 9421 }, { id = 19011 }, { id = 19010 }, { id = 5510 },
            { id = 19008 }, { id = 19007 }, { id = 5509 }, { id = 19006 }, { id = 19005 }, { id = 5512 } } },
        { key = "soulstone",   kind = "item", label = "Soulstone", items = {
            { id = 16896 }, { id = 16895 }, { id = 16893 }, { id = 16892 }, { id = 5232 } } },
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
        { key = "corruption",   id = 25311 },
        { key = "agony",        id = 11713 },
        { key = "doom",         id = 603 },
        { key = "immolate",     id = 25309 },
        { key = "siphon",       id = 18881 },
        { key = "recklessness", id = 11717, label = "Curse of Recklessness" },
        { key = "curseShadow",  id = 17937, label = "Curse of Shadow" },
        { key = "elements",     id = 11722, label = "Curse of the Elements" },
        { key = "weakness",     id = 11708, label = "Curse of Weakness" },
        { key = "tongues",      id = 11719, label = "Curse of Tongues" },
        { key = "exhaustion",   id = 18223, label = "Curse of Exhaustion" },
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
              return not (H.Buff("demonArmor") or H.Buff("demonSkin"))
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

    bars = { "mana", "fsr", "wand" },
})
