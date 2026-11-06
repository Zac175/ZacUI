-- CB_Data - what the consumable bars know about the items: every raid
-- consumable by category, which go on the potion bar, which clash with
-- each other, the stones / oils / poisons a weapon button can put on,
-- and the short names the voice says.
-- Part of ZacUI; load order is set by the TOC.
--
-- Item fields: name, buffId (the buff it gives; nil = none to track),
-- selfCastOnly (a juju: cast on yourself), slot / baseItemId (a weapon
-- stone variant), enchantId (an oil: the enchant it puts on), class (only
-- that class carries it), noBar (never a bar button), minAbsorb /
-- maxAbsorb / school (a protection potion's shield).

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local D = {}
ns.ConsData = D

-- ============================================================
-- THE CATALOGUE, in the bars' category order
-- ============================================================
D.CATEGORY_KEYS = { "flasks", "elixirs", "potions", "protectionPotions", "food", "drinks", "buffs",
    "utilities", "classItems", "chronoboon", "special" }

D.CATEGORY_NAMES = {
    flasks = "Flasks", elixirs = "Battle elixirs", potions = "Combat potions",
    protectionPotions = "Protection potions", food = "Food", drinks = "Drinks and desserts",
    buffs = "Jujus and buffs", utilities = "Utilities and tools", classItems = "Class consumables",
    chronoboon = "Chronoboon displacers", special = "Special items", custom = "Custom",
}

-- sort weight per category; the rest (chronoboon, special, custom) after
D.CATEGORY_ORDER = { flasks = 1, elixirs = 2, potions = 3, protectionPotions = 4, food = 5,
    drinks = 6, buffs = 7, utilities = 8, classItems = 9 }

D.ITEMS = {
    flasks = {
        [13510] = { name = "Flask of the Titans", buffId = 17626 },
        [13506] = { name = "Flask of Petrification", buffId = 17624 },
        [13512] = { name = "Flask of Supreme Power", buffId = 17628 },
        [13511] = { name = "Flask of Distilled Wisdom", buffId = 17627 },
        [13513] = { name = "Flask of Chromatic Resistance", buffId = 17629 },
    },
    elixirs = {
        [3825] = { name = "Elixir of Fortitude", buffId = 3593 },
        [13452] = { name = "Elixir of the Mongoose", buffId = 17538 },
        [13454] = { name = "Greater Arcane Elixir", buffId = 17539 },
        [20004] = { name = "Major Troll's Blood Potion", buffId = 24361 },
        [13445] = { name = "Elixir of Superior Defense", buffId = 11348 },
        [21546] = { name = "Elixir of Greater Firepower", buffId = 26276 },
        [9206] = { name = "Elixir of Giants", buffId = 11405 },
        [3386] = { name = "Elixir of Poison Resistance", buffId = 26677 },
        [17708] = { name = "Elixir of Frost Power", buffId = 21920 },
        [6373] = { name = "Elixir of Firepower", buffId = 7844 },
        [20007] = { name = "Mageblood Potion", buffId = 24363 },
        [9264] = { name = "Elixir of Shadow Power", buffId = 11474 },
    },
    potions = {
        [13442] = { name = "Mighty Rage Potion", buffId = 17528 },
        [13446] = { name = "Major Healing Potion" },
        [13455] = { name = "Greater Stoneshield Potion", buffId = 17540, minAbsorb = 1750, maxAbsorb = 2900 },
        [3387] = { name = "Limited Invulnerability Potion", buffId = 3169 },
        [5634] = { name = "Free Action Potion", buffId = 6615 },
        [9030] = { name = "Restorative Potion" },
        [2459] = { name = "Swiftness Potion", buffId = 2379 },
        [13444] = { name = "Major Mana Potion", buffId = 17531 },
    },
    protectionPotions = {
        [13457] = { name = "Greater Fire Protection Potion", buffId = 17543, school = 4, minAbsorb = 1950, maxAbsorb = 3250 },
        [13456] = { name = "Greater Frost Protection Potion", buffId = 17544, school = 16, minAbsorb = 1950, maxAbsorb = 3250 },
        [13458] = { name = "Greater Nature Protection Potion", buffId = 17546, school = 8, minAbsorb = 1950, maxAbsorb = 3250 },
        [13459] = { name = "Greater Shadow Protection Potion", buffId = 17548, school = 32, minAbsorb = 1950, maxAbsorb = 3250 },
        [13461] = { name = "Greater Arcane Protection Potion", buffId = 17549, school = 64, minAbsorb = 1950, maxAbsorb = 3250 },
        [22682] = { name = "Frozen Rune", buffId = 29432, school = 4, minAbsorb = 1500, maxAbsorb = 2500 },
    },
    food = {
        [13810] = { name = "Blessed Sunfruit", buffId = 18125 },
        [20452] = { name = "Smoked Desert Dumplings", buffId = 24799 },
        [21023] = { name = "Dirge's Kickin' Chimaerok Chops", buffId = 25661 },
        [12217] = { name = "Dragonbreath Chili", buffId = 15852 },
        [23326] = { name = "Midsummer Sausage", buffId = 29333 },
        [23211] = { name = "Toasted Smorc", buffId = 29334 },
        [13931] = { name = "Nightfin Soup", buffId = 18194 },
    },
    drinks = {
        [21151] = { name = "Rumsey Rum Black Label", buffId = 25804 },
        [18269] = { name = "Gordok Green Grog", buffId = 22789 },
        [21171] = { name = "Filled Festive Mug", buffId = 25851 },
        [23327] = { name = "Fire-toasted Bun", buffId = 29332 },
        [22236] = { name = "Buttermilk Delight", buffId = 27720 },
        [22237] = { name = "Dark Desire", buffId = 27723 },
        [22238] = { name = "Very Berry Cream", buffId = 27721 },
        [22239] = { name = "Sweet Surprise", buffId = 27722 },
    },
    buffs = {
        [12460] = { name = "Juju Might", buffId = 16329, selfCastOnly = true },
        [12451] = { name = "Juju Power", buffId = 16323, selfCastOnly = true },
        [12457] = { name = "Juju Chill", buffId = 16325, selfCastOnly = true },
        [12455] = { name = "Juju Ember", buffId = 16326, selfCastOnly = true },
        [12458] = { name = "Juju Guile", buffId = 16327, selfCastOnly = true },
        [19183] = { name = "Hourglass Sand", buffId = 23736 },
        [20081] = { name = "Swiftness of Zanza", buffId = 24383 },
        [20079] = { name = "Spirit of Zanza", buffId = 24382 },
        [20080] = { name = "Sheen of Zanza", buffId = 24417 },
        [8410] = { name = "R.O.I.D.S.", displayName = "R.O.I.D.S", buffId = 10667 },
        [8412] = { name = "Ground Scorpok Assay", buffId = 10669 },
        [226365] = { name = "Darnassus Gift Collection", faction = "Alliance" },
        [226370] = { name = "Orgrimmar Gift Collection", faction = "Horde" },
        [5206] = { name = "Bogling Root", buffId = 5665 },
        [9088] = { name = "Gift of Arthas", buffId = 11371 },
        [12820] = { name = "Winterfall Firewater", buffId = 17038 },
        [23196] = { name = "Greater Mark of the Dawn", buffId = 30090 },
        [1322] = { name = "Fisherliver Oil", buffId = 7396 },
        [5951] = { name = "Moist Towelette", buffId = 7108 },
        [8423] = { name = "Cerebral Cortex Compound", buffId = 10692 },
        [12662] = { name = "Demonic Rune" },
        [20520] = { name = "Dark Rune" },
    },
    utilities = {
        [8956] = { name = "Oil of Immolation", buffId = 11350 },
        [18262] = { name = "Elemental Sharpening Stone", buffId = 22756 },
        [23122] = { name = "Consecrated Sharpening Stone", buffId = 28891 },
        [12404] = { name = "Dense Sharpening Stone", buffId = 16138 },
        [182621] = { name = "Elemental Sharpening Stone (MH)", slot = "mainhand", baseItemId = 18262, buffId = 22756 },
        [182622] = { name = "Elemental Sharpening Stone (OH)", slot = "offhand", baseItemId = 18262, buffId = 22756 },
        [231221] = { name = "Consecrated Sharpening Stone (MH)", slot = "mainhand", baseItemId = 23122, buffId = 28891 },
        [231222] = { name = "Consecrated Sharpening Stone (OH)", slot = "offhand", baseItemId = 23122, buffId = 28891 },
        [3829] = { name = "Frost Oil", buffId = 3595 },
        [20749] = { name = "Brilliant Wizard Oil", buffId = 25122, enchantId = 2628 },
        [20748] = { name = "Brilliant Mana Oil", buffId = 25123, enchantId = 2629 },
        [10646] = { name = "Goblin Sapper Charge" },
        [18641] = { name = "Dense Dynamite" },
        [13180] = { name = "Stratholme Holy Water" },
        [14530] = { name = "Heavy Runecloth Bandage" },
        [11951] = { name = "Whipper Root Tuber" },
        [2091] = { name = "Magic Dust" },
        [17202] = { name = "Snowball" },
        [16023] = { name = "Masterwork Target Dummy" },
        [23123] = { name = "Blessed Wizard Oil", buffId = 28898, enchantId = 2685 },
    },
    classItems = {
        [8928] = { name = "Instant Poison", class = "ROGUE" },
        [20844] = { name = "Deadly Poison", class = "ROGUE" },
        [10922] = { name = "Wound Poison", class = "ROGUE" },
        [3776] = { name = "Crippling Poison", class = "ROGUE" },
        [9186] = { name = "Mind-numbing Poison", class = "ROGUE" },
        [7676] = { name = "Thistle Tea", class = "ROGUE" },
        [8008] = { name = "Mana Gem", class = "MAGE" },
        [18042] = { name = "Ammo", class = "HUNTER", noBar = true },
    },
    chronoboon = {
        [184938] = { name = "Supercharged Chronoboon Displacer" },
        [184937] = { name = "Chronoboon Displacer" },
    },
    special = {
        [15138] = { name = "Onyxia Scale Cloak" },
        [21218] = { name = "Blue Qiraji Resonating Crystal" },
        [21324] = { name = "Yellow Qiraji Resonating Crystal" },
        [21323] = { name = "Green Qiraji Resonating Crystal" },
        [21321] = { name = "Red Qiraji Resonating Crystal" },
        [22754] = { name = "Eternal Quintessence" },
        [2820] = { name = "Nifty Stopwatch" },
        [810] = { name = "Hammer of the Northern Wind" },
        [10761] = { name = "Coldrage Dagger" },
        [7189] = { name = "Goblin Rocket Boots" },
        [4984] = { name = "Skull of Impending Doom" },
    },
}

-- a class's own rows go to that class only (read once at load; when the
-- class is not known yet nothing is dropped)
do
    local myClass
    if UnitClass then myClass = select(2, UnitClass("player")) end
    if myClass then
        for _, items in pairs(D.ITEMS) do
            for id, it in pairs(items) do
                if it.class and it.class ~= myClass then items[id] = nil end
            end
        end
    end
end

-- Chronoboon displacers are Classic Era's: on TBC and Forever (or the
-- game-version override's) the bars do not know them (Core_Flavor)
if ns.FeatureOn and not ns.FeatureOn("chronoboon") then
    for id in pairs(D.ITEMS.chronoboon) do D.ITEMS.chronoboon[id] = nil end
end

-- id -> item, id -> category key, buff id -> item ids
D.BY_ID, D.CATEGORY_OF, D.BY_BUFF = {}, {}, {}
for _, cat in ipairs(D.CATEGORY_KEYS) do
    for id, it in pairs(D.ITEMS[cat]) do
        D.BY_ID[id], D.CATEGORY_OF[id] = it, cat
        if it.buffId then
            D.BY_BUFF[it.buffId] = D.BY_BUFF[it.buffId] or {}
            table.insert(D.BY_BUFF[it.buffId], id)
        end
    end
end

-- the items the potion bar claims (they leave the consumables bar unless
-- they are on both)
D.POTION_BAR = { [13442] = true, [13446] = true, [13455] = true, [3387] = true, [13506] = true, [5634] = true,
    [9030] = true, [2459] = true, [13457] = true, [13456] = true, [13458] = true, [13459] = true, [13461] = true,
    [22682] = true, [1322] = true, [5951] = true, [13444] = true, [12662] = true, [20520] = true, [21171] = true,
    [13810] = true, [20452] = true, [21023] = true, [12217] = true, [23326] = true, [23211] = true, [13931] = true,
    [14530] = true }
D.BOTH_BARS = { [13810] = true, [20452] = true, [21023] = true, [12217] = true, [23326] = true, [23211] = true,
    [13931] = true, [14530] = true, [21171] = true, [13506] = true }
-- the food and drink a fresh potion bar keeps hidden (they sit on the
-- consumables bar already)
D.POTION_BAR_HIDDEN = { [21171] = true, [13810] = true, [20452] = true, [21023] = true, [12217] = true,
    [23326] = true, [23211] = true, [13931] = true, [14530] = true }

-- instant items (no eating countdown on them)
D.INSTANT = { [13442] = true, [13446] = true, [13455] = true, [3387] = true, [5634] = true, [2459] = true,
    [13457] = true, [13456] = true, [13458] = true, [13459] = true, [13461] = true, [13444] = true,
    [12662] = true, [20520] = true, [12460] = true, [12451] = true, [12457] = true, [12455] = true,
    [12458] = true, [21151] = true, [18269] = true, [21171] = true, [23327] = true, [22236] = true,
    [22237] = true, [22238] = true, [22239] = true }

-- ============================================================
-- ITEMS THAT CLASH: one buff wipes the other (or a shared cooldown)
-- ============================================================
D.CONFLICT = {
    zanza = { [20081] = true, [20079] = true, [20080] = true, [8410] = true, [8412] = true, [8423] = true },
    strengthElixir = { [12451] = true, [9206] = true },
    apStrength = { [12460] = true, [12820] = true },
    wellFed = { [13810] = true, [20452] = true, [21023] = true },
    hitFood = { [23327] = true, [22237] = true },
    sharpeningStone = { [18262] = true, [23122] = true },
    wizardOil = { [20749] = true, [20748] = true, [23123] = true },
    engineeringExplosives = { [10646] = true, [18641] = true, [4390] = true, [4852] = true, [10577] = true,
        [15993] = true, [16040] = true, [13180] = true },
}
-- which one a grouped button uses, best first
D.PRIORITY = {
    strengthElixir = { 12451, 9206 },
    apStrength = { 12460, 12820 },
    zanza = { 20081, 20079, 20080, 8410, 8412, 8423 },
    wellFed = { 21023, 20452, 13810 },
    hitFood = { 23327, 22237 },
    sharpeningStone = { 18262, 23122 },
    wizardOil = { 20749, 23123, 20748 },
    engineeringExplosives = { 10646, 18641, 15993, 16040, 10577, 4390, 4852 },
}
D.GROUP_ORDER = { zanza = 1, apStrength = 2, wellFed = 3, sharpeningStone = 4 }
D.GROUP_LABELS = {
    { key = "apStrength", label = "Attack power buffs" },
    { key = "zanza", label = "Zanza and Blasted Lands" },
    { key = "wellFed", label = "Well fed" },
    { key = "hitFood", label = "Hit food" },
    { key = "strengthElixir", label = "Strength elixirs" },
    { key = "sharpeningStone", label = "Sharpening stones" },
    { key = "wizardOil", label = "Wizard oils" },
    { key = "engineeringExplosives", label = "Explosives" },
}
D.GROUP_OF = {}
for g, set in pairs(D.CONFLICT) do for id in pairs(set) do D.GROUP_OF[id] = g end end
-- Holy Water groups with the explosives but keeps its own cooldown
D.OWN_TIMER = { [13180] = true }

-- the shared potion cooldown (2 minutes) starts on these
D.POTION_CD_CATS = { potions = true, protectionPotions = true }
D.POTION_CD = 120

-- the stone / oil items a weapon button applies: never a button of their own
D.ENHANCE_RAW = { [18262] = true, [23122] = true, [12404] = true, [3829] = true }
D.STONE_VARIANT = { [182621] = true, [182622] = true, [231221] = true, [231222] = true,
    [124041] = true, [124042] = true, [38291] = true, [38292] = true }

-- ============================================================
-- WEAPON STONES, OILS AND POISONS
-- ============================================================
-- the picker's order (and the fallback when the pick is not carried):
-- the best first
D.STONES = {
    { id = 18262, name = "Elemental", color = { 1, 0.82, 0 } },
    { id = 23122, name = "Consecrated", color = { 1, 0.9, 0.6 } },
    { id = 12404, name = "Dense", color = { 0.6, 0.6, 0.65 } },
    { id = 3829, name = "Frost Oil", color = { 0.4, 0.8, 1 } },
    { id = 20749, name = "Wizard", color = { 0.64, 0.4, 1 } },
    { id = 20748, name = "Mana", color = { 0.3, 0.6, 1 } },
    { id = 23123, name = "Blessed", color = { 1, 0.85, 0.4 } },
    { id = 8928, name = "Instant VI", color = { 0.45, 0.9, 0.45 }, poison = "instant" },
    { id = 8927, name = "Instant V", color = { 0.45, 0.9, 0.45 }, poison = "instant" },
    { id = 8926, name = "Instant IV", color = { 0.45, 0.9, 0.45 }, poison = "instant" },
    { id = 6950, name = "Instant III", color = { 0.45, 0.9, 0.45 }, poison = "instant" },
    { id = 6949, name = "Instant II", color = { 0.45, 0.9, 0.45 }, poison = "instant" },
    { id = 6947, name = "Instant", color = { 0.45, 0.9, 0.45 }, poison = "instant" },
    { id = 20844, name = "Deadly V", color = { 0.6, 0.85, 0.25 }, poison = "deadly" },
    { id = 8985, name = "Deadly IV", color = { 0.6, 0.85, 0.25 }, poison = "deadly" },
    { id = 8984, name = "Deadly III", color = { 0.6, 0.85, 0.25 }, poison = "deadly" },
    { id = 2893, name = "Deadly II", color = { 0.6, 0.85, 0.25 }, poison = "deadly" },
    { id = 2892, name = "Deadly", color = { 0.6, 0.85, 0.25 }, poison = "deadly" },
    { id = 10922, name = "Wound IV", color = { 0.95, 0.45, 0.4 }, poison = "wound" },
    { id = 10921, name = "Wound III", color = { 0.95, 0.45, 0.4 }, poison = "wound" },
    { id = 10920, name = "Wound II", color = { 0.95, 0.45, 0.4 }, poison = "wound" },
    { id = 10918, name = "Wound", color = { 0.95, 0.45, 0.4 }, poison = "wound" },
    { id = 3776, name = "Crippling II", color = { 0.55, 0.65, 0.95 }, poison = "crippling" },
    { id = 3775, name = "Crippling", color = { 0.55, 0.65, 0.95 }, poison = "crippling" },
    { id = 9186, name = "Mind-numbing III", color = { 0.8, 0.5, 0.95 }, poison = "mind" },
    { id = 6951, name = "Mind-numbing II", color = { 0.8, 0.5, 0.95 }, poison = "mind" },
    { id = 5237, name = "Mind-numbing", color = { 0.8, 0.5, 0.95 }, poison = "mind" },
}
D.STONE_BY_ID, D.POISON_KIND = {}, {}
for _, s in ipairs(D.STONES) do
    D.STONE_BY_ID[s.id] = s
    if s.poison then D.POISON_KIND[s.id] = s.poison end
end
-- a rogue's hands with no pick yet take the first poison carried, in this order
D.SLOT_POISON_ORDER = {
    mainhand = { "instant", "wound", "mind", "crippling", "deadly" },
    offhand = { "deadly", "instant", "crippling", "wound", "mind" },
}
D.STONE_NAMES = {
    [18262] = "Elemental Sharpening Stone", [23122] = "Consecrated Sharpening Stone",
    [12404] = "Dense Sharpening Stone", [3829] = "Frost Oil", [20749] = "Brilliant Wizard Oil",
    [20748] = "Brilliant Mana Oil", [23123] = "Blessed Wizard Oil",
}
D.STONE_SHORT = {
    [18262] = "Elemental", [23122] = "Consecrated", [12404] = "Dense", [3829] = "Frost Oil",
    [20749] = "Wizard Oil", [20748] = "Mana Oil", [23123] = "Blessed Oil",
}
-- the enchant a weapon wears -> the stone that put it on (the border's colour)
D.ENCHANT_TO_STONE = { [2506] = 18262, [2684] = 23122, [1643] = 12404, [26] = 3829 }
-- every temporary weapon enchant the bars can name (oils by enchant id)
D.OILS = { [20749] = true, [20750] = true, [20746] = true, [20744] = true, [23123] = true,
    [20748] = true, [20747] = true, [20745] = true, [3829] = true, [3824] = true }
D.POISON_LOW_CHARGES = 10

-- the colour of a protection potion's shield, by school
D.SCHOOL_COLORS = {
    [2] = { r = 1, g = 0.9, b = 0.5 }, [4] = { r = 1, g = 0.5, b = 0 }, [8] = { r = 0.3, g = 1, b = 0.3 },
    [16] = { r = 0.5, g = 1, b = 1 }, [32] = { r = 0.5, g = 0.5, b = 1 }, [64] = { r = 1, g = 0.5, b = 1 },
}

-- weapon item subtypes a stone goes on (main hand also takes staves and
-- polearms)
D.SHARPEN_MH = { "sword", "axe", "mace", "dagger", "polearm", "fist", "staff" }
D.SHARPEN_OH = { "sword", "axe", "mace", "dagger", "fist" }
D.SHARPEN_BAG = { "sword", "axe", "mace", "dagger", "polearm", "fist" }
D.WEAPON_SLOTS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_2HWEAPON = true }

-- ============================================================
-- WHAT THE VOICE SAYS
-- ============================================================
D.SPOKEN = {
    ["Dragonbreath Chili"] = "Chili", ["Smoked Desert Dumplings"] = "Dumplings",
    ["Dirge's Kickin' Chimaerok Chops"] = "Chops", ["Blessed Sunfruit"] = "Sunfruit",
    ["Filled Festive Mug"] = "Mug", ["Rumsey Rum Black Label"] = "Rum", ["Gordok Green Grog"] = "Grog",
    ["Juju Might"] = "Juju", ["Juju Power"] = "Juju", ["Juju Chill"] = "Juju", ["Juju Ember"] = "Juju",
    ["Juju Guile"] = "Juju", ["Swiftness of Zanza"] = "Zanza", ["Spirit of Zanza"] = "Zanza",
    ["Sheen of Zanza"] = "Zanza", ["R.O.I.D.S."] = "Roids", ["Winterfall Firewater"] = "Firewater",
    ["Mageblood Potion"] = "Mageblood", ["Flask of the Titans"] = "Titans",
    ["Flask of Supreme Power"] = "Supreme Power", ["Flask of Distilled Wisdom"] = "Wisdom",
    ["Flask of Chromatic Resistance"] = "Chromatic", ["Flask of Petrification"] = "Petrification",
    ["Elixir of the Mongoose"] = "Mongoose", ["Elixir of Giants"] = "Giants",
    ["Elixir of Fortitude"] = "Fortitude", ["Elixir of Superior Defense"] = "Defense",
    ["Elixir of Greater Firepower"] = "Firepower", ["Elixir of Firepower"] = "Firepower",
    ["Elixir of Frost Power"] = "Frost Power", ["Elixir of Shadow Power"] = "Shadow Power",
    ["Elixir of Poison Resistance"] = "Poison Resist", ["Greater Arcane Elixir"] = "Arcane",
    ["Mighty Rage Potion"] = "Rage", ["Major Troll's Blood Potion"] = "Troll's Blood",
    ["Swiftness Potion"] = "Swiftness", ["Free Action Potion"] = "Free Action",
    ["Limited Invulnerability Potion"] = "Invulnerability", ["Greater Stoneshield Potion"] = "Stoneshield",
    ["Major Healing Potion"] = "Healing", ["Major Mana Potion"] = "Mana", ["Restorative Potion"] = "Restorative",
    ["Greater Fire Protection Potion"] = "Fire Protection", ["Greater Frost Protection Potion"] = "Frost Protection",
    ["Greater Nature Protection Potion"] = "Nature Protection",
    ["Greater Shadow Protection Potion"] = "Shadow Protection",
    ["Greater Arcane Protection Potion"] = "Arcane Protection", ["Demonic Rune"] = "Rune", ["Dark Rune"] = "Rune",
    ["Elemental Sharpening Stone"] = "Stone", ["Consecrated Sharpening Stone"] = "Stone",
    ["Dense Sharpening Stone"] = "Stone", ["Frost Oil"] = "Frost Oil", ["Brilliant Wizard Oil"] = "Wizard Oil",
    ["Brilliant Mana Oil"] = "Mana Oil", ["Blessed Wizard Oil"] = "Blessed Oil",
}
-- quiet unless picked (a warrior's burst potion is not worth a call)
D.SPOKEN_OFF = { [13442] = true }
local STRIP = { "flask of the ", "flask of ", "elixir of the ", "elixir of ", "potion of ", "greater arcane ",
    "greater ", "lesser ", "major ", "minor ", "superior ", "improved ", "filled ", "empty ", "bottled " }
function D.SpokenName(name)
    if not name or name == "" then return name end
    if D.SPOKEN[name] then return D.SPOKEN[name] end
    local out, lower = name, name:lower()
    for _, p in ipairs(STRIP) do
        if lower:sub(1, #p) == p then out = name:sub(#p + 1) break end
    end
    for _, pat in ipairs({ "[Pp]otion$", "[Ee]lixir$", "[Ff]lask$", "[Dd]raught$", "[Tt]onic$", "[Bb]rew$" }) do
        out = out:gsub(" " .. pat, "")
    end
    local words = {}
    for w in out:gmatch("%S+") do words[#words + 1] = w end
    if #words > 2 then out = words[#words] end
    return out
end

-- a name squeezed onto a button (the label across its top)
function D.ShortName(full)
    if not full then return "" end
    local s = full
    s = s:gsub("^Greater%s+", ""):gsub("^Lesser%s+", ""):gsub("^Elixir%s+of%s+the%s+", "")
    s = s:gsub("^Elixir%s+of%s+", ""):gsub("^Flask%s+of%s+", ""):gsub("^Juju%s+", "")
    s = s:gsub("^Spirit%s+of%s+", ""):gsub("^Scroll%s+of%s+", ""):gsub("^Potion%s+of%s+", "")
    s = s:gsub("%s+Potion$", ""):gsub("%s+Elixir$", ""):gsub("%s+Protection$", "Prot")
    if #s > 7 then
        local first = s:match("^(%S+)")
        if first and #first >= 3 then s = first end
    end
    if #s > 7 then s = s:sub(1, 6) .. "." end
    return s
end
