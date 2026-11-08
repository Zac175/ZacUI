-- BL_Data - the game facts the blessings module works from: the class
-- slots, the blessings and their Greater versions, the auras, and the
-- shape of the wire format other paladins' addons speak. Nothing here
-- runs; it is tables.
-- Part of ZacUI; load order is set by the TOC.
--
-- COMPATIBILITY. Paladins in a group coordinate over the addon channel
-- "PLPWR" - the channel the PallyPower addon uses - so a paladin running
-- PallyPower and one running ZacUI see and set each other's assignments.
-- The numbering below (class slots 1-9, blessings 1-6, auras 1-7) IS that
-- shared numbering: it must never be reordered.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
-- Not on every game version (Core_Flavor's feature table): where the
-- part is off the whole part stands down here, before it publishes
-- anything. Every later file of the part needs ns.BlessingsData and returns
-- at once without it, so no frame, event or ticker is ever made there.
if ns.PartOff and ns.PartOff("Zacui_Blessings") then return end

local D = {}
ns.BlessingsData = D

D.PREFIX = "PLPWR"

-- class slots, in the shared order (9 = hunter / warlock pets)
D.CLASSES = { "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "PET" }
D.CLASS_SLOT = {}
for i, c in ipairs(D.CLASSES) do D.CLASS_SLOT[c] = i end
D.NUM_CLASSES = #D.CLASSES

-- class colours for labels come from RAID_CLASS_COLORS; pets get this
D.PET_COLOR = { r = 0.55, g = 0.8, b = 0.45 }
D.CLASS_ICON = {
    WARRIOR = "Interface\\Icons\\ClassIcon_Warrior",
    ROGUE   = "Interface\\Icons\\ClassIcon_Rogue",
    PRIEST  = "Interface\\Icons\\ClassIcon_Priest",
    DRUID   = "Interface\\Icons\\ClassIcon_Druid",
    PALADIN = "Interface\\Icons\\ClassIcon_Paladin",
    HUNTER  = "Interface\\Icons\\ClassIcon_Hunter",
    MAGE    = "Interface\\Icons\\ClassIcon_Mage",
    WARLOCK = "Interface\\Icons\\ClassIcon_Warlock",
    PET     = "Interface\\Icons\\Ability_Hunter_BeastCall",
}
-- the class icon atlas Classic ships (used when the single icons above
-- are missing on a client)
D.CLASS_COORDS = CLASS_ICON_TCOORDS

-- the blessings, by shared number. normal = the base spell id (any rank:
-- the name is what is cast); greater = the Greater Blessing, nil when
-- there is none. talentIcon: improved by a talent drawn with the same
-- icon (Improved Blessing of Wisdom / Might).
D.BLESSINGS = {
    [1] = { key = "wisdom",    normal = 19742, greater = 25894, improved = true },
    [2] = { key = "might",     normal = 19740, greater = 25782, improved = true },
    [3] = { key = "kings",     normal = 20217, greater = 25898 },
    [4] = { key = "salvation", normal = 1038,  greater = 25895 },
    [5] = { key = "light",     normal = 19977, greater = 25890 },
    [6] = { key = "sanctuary", normal = 20911, greater = 25899 },
}
D.NUM_BLESSINGS = 6
-- per-player assignments may also name Blessing of Sacrifice (normal only)
D.SACRIFICE = 7
D.NORMAL_ONLY = { [7] = 6940 }

-- auras, by shared number
D.AURAS = {
    [1] = { key = "devotion",      id = 465,   improved = true },
    [2] = { key = "retribution",   id = 7294,  improved = true },
    [3] = { key = "concentration", id = 19746, improved = true },
    [4] = { key = "shadow",        id = 19876 },
    [5] = { key = "frost",         id = 19888 },
    [6] = { key = "fire",          id = 19891 },
    [7] = { key = "sanctity",      id = 20218, improved = true },
}
D.NUM_AURAS = 7

-- Symbol of Kings (the Greater Blessing reagent)
D.SYMBOL_OF_KINGS = 21177
-- cooldowns reported to the others: Lay on Hands (any rank), Divine
-- Intervention
D.COOLDOWNS = {
    [1] = { 633, 2800, 10310 },
    [2] = { 19752 },
}

-- Who wants what first, per class, for the automatic split. Game
-- knowledge, not a copy of anyone's table: casters want Wisdom, melee
-- Might, everyone Kings, everyone but tanks Salvation, then Light.
-- Warriors are assumed to be tanks or tank-adjacent: no Salvation.
D.PRIORITY = {
    WARRIOR = { 3, 2, 5, 6 },
    ROGUE   = { 3, 2, 4, 5 },
    PRIEST  = { 3, 1, 4, 5 },
    DRUID   = { 3, 1, 4, 2, 5 },
    PALADIN = { 3, 1, 4, 2, 5 },
    HUNTER  = { 3, 2, 4, 1, 5 },
    MAGE    = { 3, 1, 4, 5 },
    WARLOCK = { 3, 1, 4, 5 },
    PET     = { 3, 2, 5 },
}
-- auras for the automatic split, in order
D.AURA_PRIORITY = { 1, 2, 3, 6, 5, 4, 7 }

D.GREATER_DURATION = 900   -- 15 minutes
