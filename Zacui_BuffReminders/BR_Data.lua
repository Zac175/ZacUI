-- BR_Data - the group buffs each class gives, for Classic Era 1.15.
-- Part of ZacUI; load order is set by the TOC.
--
-- One entry per buff a class hands out to others. Spell ids are every
-- rank, lowest first (the highest one the player knows is the one cast;
-- casting by name does the same). The buff is found on a unit by its
-- name - the localised name of any rank, of the group version, plus the
-- English name - the way Readycheck's Battle Shout reminder always did.
--
-- WHO IT REACHES (reach):
--   "party"   your own party only (raid subgroup), cast on yourself:
--             Battle Shout (20 yd round the warrior, 2 min), Trueshot Aura
--             (the hunter's party, 30 min). Readycheck's port lists
--             player + party1-4, exactly as before.
--   "raid"    anyone in the raid, one at a time (the single rank, cast on
--             them, range 30 yd) - or the target's whole party at once with
--             the group version (Arcane Brilliance, Prayer of Fortitude /
--             Spirit / Shadow Protection, Gift of the Wild: the target's
--             party within 100 yd of the target, cast on someone in range,
--             a reagent each cast, twice the single rank's duration).
--   "chosen"  only the people you name (Thorns on the tanks: the raid's
--             main tanks plus anyone on the list; a Soulstone on whoever
--             you pick).
-- classes: who the buff matters to (nil = everyone). Battle Shout keeps
-- Readycheck's list (warriors and rogues).

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local D = {}
ns.BuffRemData = D

local MANA = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, PALADIN = true, SHAMAN = true, HUNTER = true }
local PHYSICAL = { WARRIOR = true, ROGUE = true, HUNTER = true, PALADIN = true, SHAMAN = true, DRUID = true }
D.MANA, D.PHYSICAL = MANA, PHYSICAL

-- the reagents (item ids)
D.REAGENTS = {
    [17020] = "Arcane Powder",
    [17028] = "Holy Candle",
    [17029] = "Sacred Candle",
    [17021] = "Wild Berries",
    [17026] = "Wild Thornroot",
}

-- key, class, label, icon, ids (ranks), duration (s), reach, classes,
-- group = { label, ids, duration, reagents (item id per rank) },
-- on (default: on for the class), threshold (warn at, s; 0 = missing only),
-- item (cast by using an item: { item ids, best last }), port (Readycheck's own)
D.BUFFS = {
    { key = "battleshout", class = "WARRIOR", label = "Battle Shout",
      icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
      ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, duration = 120,
      reach = "party", classes = { WARRIOR = true, ROGUE = true }, on = true, threshold = 0, port = true },

    { key = "trueshot", class = "HUNTER", label = "Trueshot Aura",
      icon = "Interface\\Icons\\Ability_TrueShot",
      ids = { 19506, 20905, 20906 }, duration = 1800,
      reach = "party", classes = PHYSICAL, on = true, threshold = 60 },

    { key = "intellect", class = "MAGE", label = "Arcane Intellect",
      icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
      ids = { 1459, 1460, 1461, 10156, 10157 }, duration = 1800,
      reach = "raid", classes = MANA, on = true, threshold = 120,
      group = { label = "Arcane Brilliance", icon = "Interface\\Icons\\Spell_Holy_ArcaneIntellect",
                ids = { 23028 }, duration = 3600, reagents = { 17020 } } },

    { key = "fortitude", class = "PRIEST", label = "Power Word: Fortitude",
      icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
      ids = { 1243, 1244, 1245, 2791, 10937, 10938 }, duration = 1800,
      reach = "raid", on = true, threshold = 120,
      group = { label = "Prayer of Fortitude", icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude",
                ids = { 21562, 21564 }, duration = 3600, reagents = { 17028, 17029 } } },

    { key = "spirit", class = "PRIEST", label = "Divine Spirit",
      icon = "Interface\\Icons\\Spell_Holy_DivineSpirit",
      ids = { 14752, 14818, 14819, 27841 }, duration = 1800,
      reach = "raid", classes = MANA, on = true, threshold = 120,
      group = { label = "Prayer of Spirit", icon = "Interface\\Icons\\Spell_Holy_PrayerofSpirit",
                ids = { 27681 }, duration = 3600, reagents = { 17029 } } },

    { key = "shadowprot", class = "PRIEST", label = "Shadow Protection",
      icon = "Interface\\Icons\\Spell_Shadow_AntiShadow",
      ids = { 976, 10957, 10958 }, duration = 600,
      reach = "raid", on = false, threshold = 60,
      group = { label = "Prayer of Shadow Protection", icon = "Interface\\Icons\\Spell_Holy_PrayerofShadowProtection",
                ids = { 27683 }, duration = 1200, reagents = { 17029 } } },

    { key = "motw", class = "DRUID", label = "Mark of the Wild",
      icon = "Interface\\Icons\\Spell_Nature_Regeneration",
      ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, duration = 1800,
      reach = "raid", on = true, threshold = 120,
      group = { label = "Gift of the Wild", icon = "Interface\\Icons\\Spell_Nature_Regeneration",
                ids = { 21849, 21850 }, duration = 3600, reagents = { 17021, 17026 } } },

    { key = "thorns", class = "DRUID", label = "Thorns",
      icon = "Interface\\Icons\\Spell_Nature_Thorns",
      ids = { 467, 782, 1075, 8914, 9756, 9910 }, duration = 600,
      reach = "chosen", tanks = true, on = false, threshold = 60 },

    { key = "soulstone", class = "WARLOCK", label = "Soulstone",
      icon = "Interface\\Icons\\Spell_Shadow_SoulGem",
      -- the buff a Soulstone leaves on its target (Soulstone Resurrection)
      ids = { 20707, 20762, 20763, 20764, 20765 }, duration = 1800,
      reach = "chosen", on = false, threshold = 60,
      -- Minor, Lesser, (plain), Greater, Major Soulstone
      item = { 5232, 16892, 16893, 16895, 16896 } },
}
D.BY_KEY = {}
for i, b in ipairs(D.BUFFS) do
    b.order = i
    D.BY_KEY[b.key] = b
end

-- the English names every match also accepts (a client in another
-- language reads the localised ones from the spell ids)
D.ENGLISH = {
    battleshout = { "Battle Shout" },
    trueshot = { "Trueshot Aura" },
    intellect = { "Arcane Intellect", "Arcane Brilliance" },
    fortitude = { "Power Word: Fortitude", "Prayer of Fortitude" },
    spirit = { "Divine Spirit", "Prayer of Spirit" },
    shadowprot = { "Shadow Protection", "Prayer of Shadow Protection" },
    motw = { "Mark of the Wild", "Gift of the Wild" },
    thorns = { "Thorns" },
    soulstone = { "Soulstone Resurrection" },
}

-- the buffs one class gives, in catalogue order
function D.ForClass(class)
    local out = {}
    for _, b in ipairs(D.BUFFS) do if b.class == class then out[#out + 1] = b end end
    return out
end

-- the raid instances the "Inside raids" filter can be narrowed to
D.RAIDS = { "Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub", "Ruins of Ahn'Qiraj",
    "Temple of Ahn'Qiraj", "Naxxramas" }
