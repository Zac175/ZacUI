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
-- Not on every game version (Core_Flavor's feature table): where the
-- part is off the whole part stands down here, before it publishes
-- anything. Every later file of the part needs ns.BuffRemData and returns
-- at once without it, so no frame, event or ticker is ever made there.
if ns.PartOff and ns.PartOff("Zacui_BuffReminders") then return end

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
    [22148] = "Wild Quillvine",
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

    -- Fear Ward: a dwarf priest's own spell on Classic Era (10 minutes),
    -- every priest's from level 20 on TBC (3 minutes, set below). Shown
    -- only to a priest who knows it.
    { key = "fearward", class = "PRIEST", label = "Fear Ward",
      icon = "Interface\\Icons\\Spell_Holy_Excorcism",
      ids = { 6346 }, duration = 600,
      reach = "chosen", tanks = true, on = false, threshold = 0 },

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
-- (2026-11-10) TBC'S RANKS, added on a TBC client only (Classic Era's
-- lists stay exactly as they were). Each id was checked by name against
-- the TBC spell database: Battle Shout 8 (2048), Trueshot Aura 4 (27066),
-- Arcane Intellect 6 (27126), Arcane Brilliance 2 (27127, Arcane Powder),
-- Power Word: Fortitude 7 (25389), Prayer of Fortitude 3 (25392), Divine
-- Spirit 5 (25312), Prayer of Spirit 2 (32999), Shadow Protection 4
-- (25433), Prayer of Shadow Protection 2 (39374), Mark of the Wild 8
-- (26990), Gift of the Wild 3 (26991, Wild Quillvine 22148), Thorns 7
-- (26992). Buffs are found by name, so the ranks only matter for the icon,
-- "do I know it" and which reagent the best group rank takes.
-- Soulstone: the Master Soulstone (item 22116) and the buff it leaves
-- (Soulstone Resurrection, 27239). Fear Ward lasts 3 minutes there.
D.TBC_RANKS = {
    battleshout = { ids = { 2048 } },
    trueshot = { ids = { 27066 } },
    intellect = { ids = { 27126 }, group = { 27127 }, reagents = { 17020 } },
    fortitude = { ids = { 25389 }, group = { 25392 }, reagents = { 17029 } },
    spirit = { ids = { 25312 }, group = { 32999 }, reagents = { 17029 } },
    shadowprot = { ids = { 25433 }, group = { 39374 }, reagents = { 17029 } },
    motw = { ids = { 26990 }, group = { 26991 }, reagents = { 22148 } },
    thorns = { ids = { 26992 } },
    soulstone = { ids = { 27239 }, item = { 22116 } },
    fearward = { ids = {}, duration = 180 },
}
-- THE BUFFS ONLY TBC HAS, added on a TBC client only (ids checked by name
-- against the TBC spell database).
--   Commanding Shout (469, level 68): the warrior's other shout - 1080
--   health for the party, 2 minutes. A warrior keeps one shout up, so it
--   is off until chosen; it matters to everyone, not just melee.
--   Earth Shield (974, 32593, 32594; a Restoration talent): on one
--   person of the shaman's choosing, 10 minutes or 6 charges.
-- after = the entry it follows in the list.
D.TBC_BUFFS = {
    { after = "battleshout", key = "commandingshout", class = "WARRIOR", label = "Commanding Shout",
      icon = "Interface\\Icons\\Ability_Warrior_RallyingCry",
      ids = { 469 }, duration = 120,
      reach = "party", on = false, threshold = 0 },
    { after = "thorns", key = "earthshield", class = "SHAMAN", label = "Earth Shield",
      icon = "Interface\\Icons\\Spell_Nature_SkinofEarth",
      ids = { 974, 32593, 32594 }, duration = 600,
      reach = "chosen", tanks = true, on = false, threshold = 0 },
}
if ns.Flavor and ns.Flavor() == "tbc" then
    for _, b in ipairs(D.BUFFS) do
        local add = D.TBC_RANKS[b.key]
        if add then
            for _, id in ipairs(add.ids) do b.ids[#b.ids + 1] = id end
            if add.duration then b.duration = add.duration end
            if add.item and b.item then
                for _, id in ipairs(add.item) do b.item[#b.item + 1] = id end
            end
            if add.group and b.group then
                -- (a reagent for every rank already listed, then the new one's)
                local g = b.group
                if g.reagents then
                    for i = #g.reagents + 1, #g.ids do g.reagents[i] = g.reagents[#g.reagents] end
                end
                for i, id in ipairs(add.group) do
                    g.ids[#g.ids + 1] = id
                    if g.reagents then g.reagents[#g.ids] = add.reagents[i] end
                end
            end
        end
    end
end
if ns.Flavor and ns.Flavor() == "tbc" then
    for _, nb in ipairs(D.TBC_BUFFS) do
        local at = #D.BUFFS
        for i, b in ipairs(D.BUFFS) do if b.key == nb.after then at = i break end end
        table.insert(D.BUFFS, at + 1, nb)
    end
end

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
    fearward = { "Fear Ward" },
    commandingshout = { "Commanding Shout" },
    earthshield = { "Earth Shield" },
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
-- (2026-11-10) PER GAME VERSION. TBC keeps Classic's raids and adds its
-- own; WoW Forever's raids are not known yet, so it lists none and the
-- filter is not applied there (every raid counts). A tick is kept by the
-- raid's English name, as it always was, and matched by the instance id
-- too (GetInstanceInfo's 8th value), so another client language or
-- another spelling of the instance's name still counts.
D.RAIDS_TBC = { "Karazhan", "Gruul's Lair", "Magtheridon's Lair", "Serpentshrine Cavern", "Tempest Keep",
    "Hyjal Summit", "Black Temple", "Zul'Aman", "Sunwell Plateau" }
D.RAID_IDS = {
    ["Molten Core"] = 409, ["Onyxia's Lair"] = 249, ["Blackwing Lair"] = 469, ["Zul'Gurub"] = 309,
    ["Ruins of Ahn'Qiraj"] = 509, ["Temple of Ahn'Qiraj"] = 531, ["Naxxramas"] = 533,
    ["Karazhan"] = 532, ["Gruul's Lair"] = 565, ["Magtheridon's Lair"] = 544, ["Serpentshrine Cavern"] = 548,
    ["Tempest Keep"] = 550, ["Hyjal Summit"] = 534, ["Black Temple"] = 564, ["Zul'Aman"] = 568,
    ["Sunwell Plateau"] = 580,
}
function D.Raids()
    local fl = (ns.Flavor and ns.Flavor()) or "era"
    if fl == "era" then return D.RAIDS end
    if fl == "tbc" then
        local out = {}
        for _, n in ipairs(D.RAIDS) do out[#out + 1] = n end
        for _, n in ipairs(D.RAIDS_TBC) do out[#out + 1] = n end
        return out
    end
    return {}
end
