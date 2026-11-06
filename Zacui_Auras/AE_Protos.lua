-- AE_Protos - the built-in (non-aura, non-custom) trigger kinds as data.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- One table per kind, named as the format names it (trigger.event:
-- "Health", "Cooldown Progress (Spell)"...), listing the options a
-- trigger of that kind has. The same table is read twice:
--   * by the engine (AE_TriggerGeneric) to check a trigger against the
--     values it measured, and to copy the measured values into the state
--     that texts and conditions read;
--   * by the editor (AE_OptionsTriggers) to draw the options.
-- The option keys are the format's own: use_<name>, <name>,
-- <name>_operator, use_exact_<name>, <name>_caseInsensitive, so what is
-- built here reads the same in WeakAuras and the other way round.
--
-- A field:
--   name    the option / state key
--   kind    number      use_x, x, x_operator (x and x_operator are lists
--                       when `multi` is set: up to two checks, all must hold)
--           string      use_x, x: equal to
--           longstring  use_x, x, x_operator (==, find, match),
--                       x_caseInsensitive when `caseless`
--           select      use_x, x: one value of `values`
--           multiselect use_x (true: x.single, false: any of x.multi)
--           tristate    use_x: true yes, false no, nil either
--           toggle      use_x: a switch (a check when `check` is set)
--           spell/item  use_x, x (+ use_exact_x when `exact`); read by the
--                       kind's own code unless `check` is set
--           spells      use_x, x = list; names (or ids standing for their
--                       names) unless `exact`; matched against spellId /
--                       spellName of the event
--           unit        x is the unit key; a typed unit id goes in x with
--                       use_specific_x set (the format's "Specific Unit")
--           strlist     use_x, x: comma list, "-" in front to exclude
--           namerealm   use_x, x: "Name", "Name-Realm", "-Realm" list
--           zones       use_x, x: map ids (g group, c continent+children,
--                       a area, i instance) comma list, "-" excludes
--           header / description   the editor only
--   label   what the editor calls it
--   values  key into P.values (or a function returning a list)
--   ops     "all" (default for numbers), "noeq" (<= >= only),
--           "eq" (== only), "string"
--   multi   number checks may be given twice (a range)
--   req     checked whenever it has a value (no use_ switch)
--   on      function(trigger) -> false when the field does not apply
--   state   the measured value is copied into the state
--   hidden  state only: no option
--   test    function(values, want, trigger) for checks that are not a
--           plain comparison
--   own     checked by the kind's own code in AE_TriggerGeneric
--   default the value a new trigger starts with
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local P = {}
E.Protos = P

-- ============================================================
-- VALUE LISTS (the format's keys; the words are ZacUI's)
-- ============================================================
local V = {}
P.values = V

V.operator_types = { ["=="] = "=", ["~="] = "not", ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=" }
V.operator_types_without_equal = { ["<="] = "<=", [">="] = ">=" }
V.equality_operator_types = { ["=="] = "=", ["~="] = "not" }
V.string_operator_types = { ["=="] = "is", ["find('%s')"] = "contains", ["match('%s')"] = "matches (pattern)" }

V.actual_unit_types_cast = { player = "You", target = "Target", softenemy = "Soft target (enemy)",
    softfriend = "Soft target (friend)", pet = "Pet", group = "Your group (smart)", party = "Party",
    raid = "Raid", nameplate = "Nameplates", member = "A unit you name" }
V.actual_unit_types = { player = "You", target = "Target", softenemy = "Soft target (enemy)",
    softfriend = "Soft target (friend)", pet = "Pet" }
V.actual_unit_types_with_specific = { player = "You", target = "Target", softenemy = "Soft target (enemy)",
    softfriend = "Soft target (friend)", pet = "Pet", member = "A unit you name" }
V.threat_unit_types = { target = "Target", softenemy = "Soft target (enemy)", softfriend = "Soft target (friend)",
    nameplate = "Nameplates", boss = "Bosses", member = "A unit you name", none = "Any enemy" }
V.unit_types_range_check = { target = "Target", softenemy = "Soft target (enemy)", softfriend = "Soft target (friend)",
    pet = "Pet", member = "A unit you name" }
V.unit_types_bufftrigger_2 = { player = "You", target = "Target", softenemy = "Soft target (enemy)",
    softfriend = "Soft target (friend)", pet = "Pet", group = "Your group (smart)", party = "Party",
    raid = "Raid", nameplate = "Nameplates", member = "A unit you name", multi = "Many targets (combat log)" }

V.hostility_types = { hostile = "Hostile", friendly = "Friendly" }
V.character_types = { player = "A player", npc = "A non-player" }
V.include_pets_types = { PlayersAndPets = "Players and pets", PetsOnly = "Pets only" }
V.role_types = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
V.raid_role_types = { MAINTANK = "Main tank", MAINASSIST = "Main assist", NONE = "Neither" }
V.class_types = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
V.classification_types = { worldboss = "World boss", rareelite = "Rare elite", elite = "Elite", rare = "Rare",
    normal = "Normal", trivial = "Trivial", minus = "Minor" }
V.raid_mark_check_type = { [0] = "No mark", [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square", [7] = "Cross", [8] = "Skull" }
V.combatlog_raid_mark_check_type = { [0] = "No mark", [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon", [6] = "Square", [7] = "Cross", [8] = "Skull", [9] = "Any mark" }
V.power_types = { [0] = "Mana", [1] = "Rage", [2] = "Focus", [3] = "Energy", [4] = "Combo points", [6] = "Runic power",
    [7] = "Soul shards", [8] = "Astral power", [9] = "Holy power", [11] = "Maelstrom", [12] = "Chi",
    [13] = "Insanity", [16] = "Arcane charges", [17] = "Fury", [18] = "Pain" }
V.unit_threat_situation_types = { [-1] = "Not on the threat list", [0] = "Below the tank", [1] = "Above the tank",
    [2] = "Tanking, not highest", [3] = "Tanking, highest" }
V.cast_types = { cast = "Cast", channel = "Channel" }
V.swing_types = { main = "Main hand", off = "Off hand", ranged = "Ranged" }
V.weapon_types = { main = "Main hand", off = "Off hand", ranged = "Ranged" }
V.weapon_enchant_types = { showOnActive = "Enchant there", showOnMissing = "Enchant missing", showAlways = "Always" }
V.cooldown_progress_behavior_types = { showOnCooldown = "On cooldown", showOnReady = "Not on cooldown", showAlways = "Always" }
V.cooldown_types = { auto = "Automatic", charges = "Charges", cooldown = "Cooldown" }
V.item_slot_types = { [0] = "Ammo", [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist",
    [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Finger 1", [12] = "Finger 2",
    [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main hand", [17] = "Off hand",
    [18] = "Ranged", [19] = "Tabard" }
V.charges_change_type = { GAINED = "Gained", LOST = "Lost", CHANGED = "Either" }
V.combat_event_type = { PLAYER_REGEN_DISABLED = "Entering combat", PLAYER_REGEN_ENABLED = "Leaving combat" }
V.encounter_event_type = { ENCOUNTER_START = "Boss pulled", ENCOUNTER_END = "Boss fight over" }
V.difficulty_types = { none = "None", normal = "Normal", heroic = "Heroic" }
V.instance_types = { none = "Not in an instance", party = "5-man dungeon", ten = "10-man raid", twenty = "20-man raid",
    twentyfive = "25-man raid", fortyman = "40-man raid", pvp = "Battleground" }
V.group_types = { solo = "Not in a group", group = "In a party", raid = "In a raid" }
V.chat_message_types = { CHAT_MSG_INSTANCE_CHAT = "Instance", CHAT_MSG_BG_SYSTEM_NEUTRAL = "Battleground (neutral)",
    CHAT_MSG_BG_SYSTEM_ALLIANCE = "Battleground (Alliance)", CHAT_MSG_BG_SYSTEM_HORDE = "Battleground (Horde)",
    CHAT_MSG_BN_WHISPER = "Battle.net whisper", CHAT_MSG_CHANNEL = "Channel", CHAT_MSG_COMMUNITIES_CHANNEL = "Communities",
    CHAT_MSG_EMOTE = "Emote", CHAT_MSG_GUILD = "Guild", CHAT_MSG_LOOT = "Loot", CHAT_MSG_MONSTER_EMOTE = "Monster emote",
    CHAT_MSG_MONSTER_PARTY = "Monster party", CHAT_MSG_MONSTER_SAY = "Monster say", CHAT_MSG_MONSTER_WHISPER = "Monster whisper",
    CHAT_MSG_MONSTER_YELL = "Monster yell", CHAT_MSG_OFFICER = "Officer", CHAT_MSG_PARTY = "Party", CHAT_MSG_RAID = "Raid",
    CHAT_MSG_RAID_BOSS_EMOTE = "Boss emote", CHAT_MSG_RAID_BOSS_WHISPER = "Boss whisper", CHAT_MSG_RAID_WARNING = "Raid warning",
    CHAT_MSG_SAY = "Say", CHAT_MSG_SYSTEM = "System", CHAT_MSG_WHISPER = "Whisper", CHAT_MSG_YELL = "Yell" }
V.subevent_prefix_types = { SWING = "Swing", RANGE = "Ranged", SPELL = "Spell", SPELL_PERIODIC = "Periodic spell",
    SPELL_BUILDING = "Spell (building)", ENVIRONMENTAL = "Environment", DAMAGE_SHIELD = "Damage shield",
    DAMAGE_SHIELD_MISSED = "Damage shield missed", DAMAGE_SPLIT = "Damage split", ENCHANT_APPLIED = "Enchant applied",
    ENCHANT_REMOVED = "Enchant removed", PARTY_KILL = "Party kill", UNIT_DIED = "Unit died",
    UNIT_DESTROYED = "Unit destroyed", UNIT_DISSIPATES = "Unit dissipates" }
V.subevent_actual_prefix_types = { SWING = true, RANGE = true, SPELL = true, SPELL_PERIODIC = true,
    SPELL_BUILDING = true, ENVIRONMENTAL = true }
V.subevent_suffix_types = { _DAMAGE = "Damage", _MISSED = "Missed", _HEAL = "Heal", _HEAL_ABSORBED = "Heal absorbed",
    _ABSORBED = "Absorbed", _ENERGIZE = "Energize", _DRAIN = "Drain", _LEECH = "Leech", _INTERRUPT = "Interrupt",
    _DISPEL = "Dispel", _DISPEL_FAILED = "Dispel failed", _STOLEN = "Stolen", _EXTRA_ATTACKS = "Extra attacks",
    _AURA_APPLIED = "Aura applied", _AURA_REMOVED = "Aura removed", _AURA_APPLIED_DOSE = "Aura stack gained",
    _AURA_REMOVED_DOSE = "Aura stack lost", _AURA_REFRESH = "Aura refreshed", _AURA_BROKEN = "Aura broken",
    _AURA_BROKEN_SPELL = "Aura broken by a spell", _CAST_START = "Cast start", _CAST_SUCCESS = "Cast success",
    _CAST_FAILED = "Cast failed", _INSTAKILL = "Instant kill", _DURABILITY_DAMAGE = "Durability damage",
    _DURABILITY_DAMAGE_ALL = "Durability damage (all)", _CREATE = "Create", _SUMMON = "Summon", _RESURRECT = "Resurrect",
    _EMPOWER_START = "Empower start", _EMPOWER_END = "Empower end", _EMPOWER_INTERRUPT = "Empower interrupted" }
V.miss_types = { ABSORB = "Absorb", BLOCK = "Block", DEFLECT = "Deflect", DODGE = "Dodge", EVADE = "Evade",
    IMMUNE = "Immune", MISS = "Miss", PARRY = "Parry", REFLECT = "Reflect", RESIST = "Resist" }
V.environmental_types = { Drowning = "Drowning", Falling = "Falling", Fatigue = "Fatigue", Fire = "Fire",
    Lava = "Lava", Slime = "Slime" }
V.aura_types = { BUFF = "Buff", DEBUFF = "Debuff" }
V.combatlog_flags_check_type = { Mine = "Mine", InParty = "In your party", InGroup = "In your group",
    NotInGroup = "Not in your group" }
V.combatlog_flags_check_reaction = { Hostile = "Hostile", Neutral = "Neutral", Friendly = "Friendly" }
V.combatlog_flags_check_object_type = { Object = "Object", Guardian = "Guardian", Pet = "Pet", NPC = "NPC", Player = "Player" }
V.combatlog_spell_school_types_for_ui = { [1] = "001 - Physical", [2] = "002 - Holy", [4] = "004 - Fire",
    [8] = "008 - Nature", [16] = "016 - Frost", [32] = "032 - Shadow", [64] = "064 - Arcane",
    [3] = "003 - Holystrike", [5] = "005 - Flamestrike", [6] = "006 - Radiant", [9] = "009 - Stormstrike",
    [10] = "010 - Holystorm", [12] = "012 - Firestorm", [17] = "017 - Froststrike", [18] = "018 - Holyfrost",
    [20] = "020 - Frostfire", [24] = "024 - Froststorm", [33] = "033 - Shadowstrike", [34] = "034 - Twilight",
    [36] = "036 - Shadowflame", [40] = "040 - Plague", [48] = "048 - Shadowfrost", [65] = "065 - Spellstrike",
    [66] = "066 - Divine", [68] = "068 - Spellfire", [72] = "072 - Astral", [80] = "080 - Spellfrost",
    [96] = "096 - Spellshadow", [28] = "028 - Elemental", [62] = "062 - Chromatic", [106] = "106 - Cosmic",
    [124] = "124 - Chaos", [126] = "126 - Magic", [127] = "127 - Chaos" }
V.loss_of_control_types = { NONE = "None", CHARM = "Charm", CONFUSE = "Confuse", DISARM = "Disarm", FEAR = "Fear",
    FEAR_MECHANIC = "Fear (mechanic)", PACIFY = "Pacify", SILENCE = "Silence", PACIFYSILENCE = "Pacify and silence",
    POSSESS = "Possess", ROOT = "Root", SCHOOL_INTERRUPT = "Interrupted", STUN = "Stun", STUN_MECHANIC = "Stun (mechanic)" }
V.main_spell_schools = { [1] = "Physical", [2] = "Holy", [4] = "Fire", [8] = "Nature", [16] = "Frost",
    [32] = "Shadow", [64] = "Arcane" }
V.totem_types = { [1] = "Totem 1 (fire)", [2] = "Totem 2 (earth)", [3] = "Totem 3 (water)", [4] = "Totem 4 (air)",
    [5] = "Totem 5" }
V.pet_behavior_types = { passive = "Passive", defensive = "Defensive", aggressive = "Aggressive" }
V.pet_spec_types = {}
V.gtfo_types = { [1] = "High damage", [2] = "Low damage", [3] = "Fail alert", [4] = "Friendly fire" }
V.form_types = function()
    local out = { [0] = "No form" }
    if GetNumShapeshiftForms and GetShapeshiftFormInfo then
        for i = 1, GetNumShapeshiftForms() or 0 do
            local _, active, _, spellId = GetShapeshiftFormInfo(i)
            local name = spellId and GetSpellInfo and GetSpellInfo(spellId)
            out[i] = name or ("Form " .. i)
        end
    end
    return out
end
V.talent_types = function()
    local out = {}
    for tab = 1, 3 do
        local n = GetNumTalents and GetNumTalents(tab) or 20
        for i = 1, n do
            local name = GetTalentInfo and GetTalentInfo(tab, i)
            out[(tab - 1) * 20 + i] = name or ("Tree " .. tab .. " - " .. i)
        end
    end
    return out
end
-- item class * 256 + subclass, the weapon and shield kinds
V.item_weapon_types = { [512] = "One-handed axe", [513] = "Two-handed axe", [514] = "Bow", [515] = "Gun",
    [516] = "One-handed mace", [517] = "Two-handed mace", [518] = "Polearm", [519] = "One-handed sword",
    [520] = "Two-handed sword", [522] = "Staff", [525] = "Fist weapon", [527] = "Dagger", [528] = "Thrown",
    [530] = "Crossbow", [531] = "Wand", [532] = "Fishing pole", [1030] = "Shield" }
V.faction_types = function()
    local out = {}
    if GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() or 0 do
            local name, _, _, _, _, _, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
            if factionID and not isHeader then out[factionID] = name end
        end
    end
    return out
end
V.standing_types = { [1] = "Hated", [2] = "Hostile", [3] = "Unfriendly", [4] = "Neutral", [5] = "Friendly",
    [6] = "Honored", [7] = "Revered", [8] = "Exalted" }

-- aura (buff / debuff) trigger lists
V.debuff_types = { HELPFUL = "Buff", HARMFUL = "Debuff", BOTH = "Either" }
V.debuff_class_types = { magic = "Magic", curse = "Curse", disease = "Disease", poison = "Poison",
    enrage = "Enrage", none = "None" }
V.bufftrigger_2_progress_behavior_types = { showOnActive = "When found", showOnMissing = "When missing",
    showOnMatches = "On the match count", showAlways = "Always" }
V.bufftrigger_2_preferred_match_types = { showLowest = "Least time left", showHighest = "Most time left",
    showLowestSpellId = "Lowest spell id", showHighestSpellId = "Highest spell id" }
V.bufftrigger_2_per_unit_mode = { affected = "Units with it", unaffected = "Units without it", all = "Every unit" }
V.tooltip_count = { [1] = "First", [2] = "Second", [3] = "Third" }

-- custom trigger lists
V.custom_trigger_types = { event = "Event", status = "Status", stateupdate = "Trigger state updater" }
V.eventend_types = { timed = "After a time", custom = "With code" }
V.check_types = { event = "On its events", update = "Every frame" }

-- the trigger kinds by category (trigger.type)
V.trigger_types = { aura2 = "Buff / debuff", custom = "Custom code", unit = "Player / unit info",
    spell = "Spell", item = "Item", event = "Event", combatlog = "Combat log", addons = "Other addons" }

-- ============================================================
-- FIELD BUILDERS (short hands for the tables below)
-- ============================================================
local function F(name, kind, label, opts)
    local f = { name = name, kind = kind, label = label }
    for k, v in pairs(opts or {}) do f[k] = v end
    return f
end
local function N(name, label, o) return F(name, "number", label, o) end
local function S(name, label, o) return F(name, "string", label, o) end
local function LS(name, label, o) return F(name, "longstring", label, o) end
local function SEL(name, label, values, o) o = o or {} o.values = values return F(name, "select", label, o) end
local function MS(name, label, values, o) o = o or {} o.values = values return F(name, "multiselect", label, o) end
local function TRI(name, label, o) return F(name, "tristate", label, o) end
local function TOG(name, label, o) return F(name, "toggle", label, o) end
local function SP(name, label, o) return F(name, "spell", label, o) end
local function IT(name, label, o) return F(name, "item", label, o) end
local function SPS(name, label, o) return F(name, "spells", label, o) end
local function U(values, o) o = o or {} o.values = values o.req = true o.state = true return F("unit", "unit", "Unit", o) end
local function SL(name, label, o) return F(name, "strlist", label, o) end
local function NR(name, label, o) return F(name, "namerealm", label, o) end
local function H(name, label, o) return F(name, "header", label, o) end
local function ST(name, o) o = o or {} o.hidden = true o.state = true return F(name, "state", name, o) end

local Same
local function Group(t) local u = t.unit return u == "group" or u == "raid" or u == "party" end
local function GroupOrPlate(t) return Group(t) or t.unit == "nameplate" end
local function NotInverse(t) return not t.use_inverse end
P.IsGroupUnit = Group

-- the unit characteristic fields several unit kinds share
local function UnitChar(list, withRole)
    list[#list + 1] = H("unitCharacteristicsHeader", "Unit")
    list[#list + 1] = NR("namerealm", "Unit name / realm", { from = { "name", "realm" } })
    list[#list + 1] = SL("npcId", "Npc id(s)", { state = true })
    list[#list + 1] = SEL("class", "Class", "class_types", { state = true })
    if withRole then
        list[#list + 1] = SEL("role", "Assigned role", "role_types", { state = true, on = Group })
    end
    list[#list + 1] = SEL("raid_role", "Raid role", "raid_role_types", { state = true, on = Group })
    list[#list + 1] = MS("raidMarkIndex", "Raid mark", "raid_mark_check_type", { state = true })
    list[#list + 1] = ST("raidMark")
end
local function Misc(list, opts)
    list[#list + 1] = H("miscellaneousHeader", "More", { on = GroupOrPlate })
    list[#list + 1] = SEL("includePets", "Include pets", "include_pets_types", { on = Group })
    list[#list + 1] = TOG("ignoreSelf", "Leave yourself out", { on = GroupOrPlate, check = true })
    if not (opts and opts.noDead) then
        list[#list + 1] = TOG("ignoreDead", "Leave the dead out", { on = Group, check = true })
    end
    list[#list + 1] = TOG("ignoreDisconnected", "Leave the offline out", { on = Group, check = true })
end

-- ============================================================
-- THE KINDS
-- ============================================================
local L = {}
P.list = L

local function Def(name, t) t.event = name L[name] = t return t end

-- ---------- unit ----------
do
    local f = {
        U("actual_unit_types_cast"),
        F("unitisunit", "unit", "Is the same unit as", { values = function(t)
            if Group(t) or t.unit == "nameplate" then return V.actual_unit_types end
            return V.actual_unit_types_with_specific end, check = true,
            test = function(v, want) return UnitIsUnit and UnitIsUnit(v.unit, want) and true or false end }),
        ST("name"), ST("realm"),
        NR("namerealm", "Unit name / realm", { from = { "name", "realm" } }),
        SEL("class", "Class", "class_types", { state = true }),
        MS("classification", "Classification", "classification_types", { state = true }),
        SEL("role", "Assigned role", "role_types", { state = true }),
        SEL("raid_role", "Raid role", "raid_role_types", { state = true, on = Group }),
        MS("raidMarkIndex", "Raid mark", "raid_mark_check_type", { state = true }),
        ST("raidMark"),
        TRI("dead", "Dead", { state = true }),
        TRI("resurrectPending", "Being resurrected", { state = true }),
        TOG("ignoreSelf", "Leave yourself out", { on = GroupOrPlate, check = true }),
        TOG("ignoreDisconnected", "Leave the offline out", { on = Group, check = true }),
        SEL("hostility", "Hostility", "hostility_types", { state = true }),
        SEL("character", "Player or not", "character_types", { state = true }),
        N("level", "Level", { state = true, multi = true }),
        SL("npcId", "Npc id(s)", { state = true }),
        TRI("attackable", "Attackable", { state = true }),
        TRI("inCombat", "In combat", { state = true }),
        TRI("afk", "Away", { state = true }),
        TRI("dnd", "Busy", { state = true }),
    }
    Def("Unit Characteristics", { type = "unit", label = "Unit characteristics", perUnit = true, progress = "none", fields = f,
        defaultUnit = "target" })
end

do
    local f = {
        U("actual_unit_types_cast"),
        N("health", "Health", { state = true, multi = true }),
        ST("value"), ST("total"),
        N("percenthealth", "Health %", { state = true, multi = true }),
        N("deficit", "Missing health", { state = true, multi = true }),
        N("maxhealth", "Max health", { state = true, multi = true }),
        H("absorbAndHealingHeader", "Healing"),
        TOG("showIncomingHeal", "Show incoming heals"),
        N("healprediction", "Incoming heals", { state = true, multi = true, on = function(t) return t.use_showIncomingHeal end }),
        ST("name"), ST("realm"),
    }
    UnitChar(f, true)
    Misc(f)
    f[#f + 1] = SEL("nameplateType", "Hostility", "hostility_types", { state = true })
    Def("Health", { type = "unit", label = "Health", perUnit = true, progress = "static", fields = f })
end

do
    local f = {
        U("actual_unit_types_cast"),
        SEL("powertype", "Power type", "power_types", { state = true }),
        TOG("requirePowerType", "Only if it is their main power", { on = function(t) return t.use_powertype end, check = true }),
        TOG("showCost", "Show the cost of casts", { on = function(t) return (not t.use_powertype or t.powertype ~= 99) and t.unit == "player" end }),
        N("power", "Power", { state = true, multi = true }),
        ST("value"), ST("total"), ST("stacks"),
        N("percentpower", "Power %", { state = true, multi = true }),
        N("deficit", "Missing power", { state = true, multi = true }),
        N("maxpower", "Max power", { state = true, multi = true }),
        ST("name"), ST("realm"),
    }
    UnitChar(f, true)
    Misc(f)
    f[#f + 1] = SEL("nameplateType", "Hostility", "hostility_types", { state = true })
    Def("Power", { type = "unit", label = "Power", perUnit = true, progress = "static", fields = f })
end

do
    local f = {
        U("actual_unit_types_cast"),
        SPS("spellNames", "Spell name(s)", { on = NotInverse, group = "spell" }),
        SPS("spellIds", "Exact spell id(s)", { on = NotInverse, exact = true, group = "spell" }),
        ST("spellId"), ST("spell"),
        SEL("castType", "Cast or channel", "cast_types", { state = true, on = NotInverse }),
        TRI("interruptible", "Can be interrupted", { state = true, on = NotInverse }),
        N("remaining", "Time left", { on = NotInverse }),
        H("unitCharacteristicsHeader", "Unit"),
        SL("npcId", "Npc id(s)", { state = true, on = NotInverse }),
        SEL("class", "Class", "class_types", { state = true, on = NotInverse }),
        SEL("role", "Assigned role", "role_types", { state = true, on = function(t) return t.unit == "group" or t.unit == "raid" or (t.unit == "party" and not t.use_inverse) end }),
        SEL("raid_role", "Raid role", "raid_role_types", { state = true, on = function(t) return Group(t) and not t.use_inverse end }),
        MS("raidMarkIndex", "Raid mark", "raid_mark_check_type", { state = true }),
        ST("raidMark"),
        SEL("nameplateType", "Hostility", "hostility_types", { state = true }),
        ST("sourceUnit", { on = NotInverse }), ST("sourceName", { on = NotInverse }), ST("sourceRealm", { on = NotInverse }),
        NR("sourceNameRealm", "Caster name / realm", { on = NotInverse, from = { "sourceName", "sourceRealm" } }),
        F("destUnit", "unit", "Caster's target is", { values = "actual_unit_types_with_specific", on = NotInverse, check = true, state = true }),
        ST("destName", { on = NotInverse }), ST("destRealm", { on = NotInverse }),
        NR("destNameRealm", "Caster's target name / realm", { on = NotInverse, from = { "destName", "destRealm" } }),
        H("miscellaneousHeader", "More"),
        TOG("showLatency", "Show your latency", { on = function(t) return t.unit == "player" and not t.use_inverse end }),
        SEL("includePets", "Include pets", "include_pets_types", { on = Group }),
        TOG("ignoreSelf", "Leave yourself out", { on = GroupOrPlate, check = true }),
        TOG("onUpdateUnitTarget", "Re-check the caster's target", { on = function(t) return t.unit == "nameplate" end }),
        TOG("inverse", "Show when not casting"),
        ST("stagesData"),
    }
    Def("Cast", { type = "unit", label = "Cast", perUnit = true, progress = "timed", fields = f })
end

do
    local f = {
        F("unit", "unit", "Unit", { values = "threat_unit_types", req = true, state = true, default = "target" }),
        SEL("status", "Status", "unit_threat_situation_types", { state = true }),
        TRI("aggro", "Has aggro", { state = true }),
        N("threatpct", "Threat %", { state = true, multi = true, on = function(t) return t.unit ~= "none" end }),
        N("rawthreatpct", "Raw threat %", { state = true, multi = true, on = function(t) return t.unit ~= "none" end }),
        N("threatvalue", "Threat", { state = true, multi = true, on = function(t) return t.unit ~= "none" end }),
        H("unitCharacteristicsHeader", "Unit"),
        SL("name", "Unit name(s)", { state = true }),
        SL("npcId", "Npc id(s)", { state = true }),
        ST("value"), ST("total"),
    }
    Def("Threat Situation", { type = "unit", label = "Threat", perUnit = true, progress = "static", fields = f,
        defaultUnit = "target" })
end

Def("Conditions", { type = "unit", label = "Conditions", progress = "none", fields = {
    TRI("alwaystrue", "Always on"),
    TRI("incombat", "In combat"),
    TRI("pvpflagged", "PvP flagged"),
    TRI("alive", "Alive"),
    TRI("vehicle", "On a taxi"),
    TRI("resting", "Resting"),
    TRI("mounted", "Mounted"),
    TRI("HasPet", "Has a pet"),
    TRI("ismoving", "Moving"),
    TRI("afk", "Away"),
    MS("ingroup", "Group", "group_types"),
    MS("instance_size", "Instance size (old; use Location)", "instance_types"),
} })

Def("Stance/Form/Aura", { type = "unit", label = "Stance / form / aura", progress = "none", fields = {
    MS("form", "Form", "form_types", { state = true }),
    TOG("inverse", "Inverse", { on = function(t) return type(t.use_form) == "boolean" end }),
} })

Def("Character Stats", { type = "unit", label = "Character stats", progress = "none", fields = {
    H("primaryStatsHeader", "Main stats"),
    N("strength", "Strength", { state = true, multi = true }),
    N("agility", "Agility", { state = true, multi = true }),
    N("intellect", "Intellect", { state = true, multi = true }),
    N("spirit", "Spirit", { state = true, multi = true }),
    N("stamina", "Stamina", { state = true, multi = true }),
    H("secondaryStatsHeader", "Other stats"),
    N("criticalpercent", "Crit %", { state = true, multi = true }),
    N("hastepercent", "Haste %", { state = true, multi = true }),
    N("attackpower", "Attack power", { state = true, multi = true }),
    N("spellpower", "Spell power", { state = true, multi = true }),
    H("tertiaryStatsHeader", "Movement"),
    TOG("moveSpeed", "Keep checking movement speed"),
    N("movespeedpercent", "Movement speed %", { state = true, multi = true }),
    N("runspeedpercent", "Run speed %", { state = true, multi = true }),
    H("defensiveStatsHeader", "Defence"),
    N("dodgepercent", "Dodge %", { state = true, multi = true }),
    N("parrypercent", "Parry %", { state = true, multi = true }),
    N("blockpercent", "Block %", { state = true, multi = true }),
    N("blockvalue", "Block value", { state = true, multi = true }),
    N("armorrating", "Armour", { state = true, multi = true }),
    H("resistanceHeader", "Resistances"),
    N("resistanceholy", "Holy resistance", { state = true, multi = true }),
    N("resistancefire", "Fire resistance", { state = true, multi = true }),
    N("resistancenature", "Nature resistance", { state = true, multi = true }),
    N("resistancefrost", "Frost resistance", { state = true, multi = true }),
    N("resistanceshadow", "Shadow resistance", { state = true, multi = true }),
    N("resistancearcane", "Arcane resistance", { state = true, multi = true }),
} })

Def("Location", { type = "unit", label = "Location", progress = "none", fields = {
    F("zoneIds", "zones", "Zone id(s)"),
    ST("zoneId"), ST("zonegroupId"),
    S("zone", "Zone name", { state = true, list = true }),
    S("subzone", "Sub-zone name", { state = true, list = true }),
    H("instanceHeader", "Instance"),
    ST("instanceId"), ST("instance"),
    MS("instanceSize", "Instance size", "instance_types", { state = true }),
} })

Def("Range Check", { type = "unit", label = "Range", progress = "none", fields = {
    F("note", "description", "Classic only knows ranges in steps (10, 28 yards and beyond)."),
    F("unit", "unit", "Unit", { values = "unit_types_range_check", req = true, state = true }),
    ST("minRange"), ST("maxRange"),
    N("range", "Distance", { ops = "noeq", test = function(v, want, t)
        return E.WA.CheckRange(v.unit, tonumber(want) or 0, t.range_operator)
    end }),
} })

Def("Swing Timer", { type = "unit", label = "Swing timer", progress = "timed", fields = {
    F("note", "description", "Your own swings, from the combat log."),
    SEL("hand", "Weapon", "swing_types", { req = true, own = true }),
    ST("duration"), ST("expirationTime"), ST("name"), ST("icon"),
    N("remaining", "Time left", { on = NotInverse }),
    TOG("inverse", "Show while not swinging"),
} })

Def("Talent Known", { type = "unit", label = "Talent", progress = "none", fields = {
    MS("talent", "Talent", "talent_types", { noSingle = false, own = true }),
    TOG("inverse", "Inverse"),
    ST("icon"), ST("name"),
} })

Def("Experience", { type = "unit", label = "Experience", progress = "static", fields = {
    N("level", "Level", { state = true, multi = true }),
    N("currentXP", "Experience", { state = true, multi = true }),
    N("totalXP", "Experience needed", { state = true, multi = true }),
    ST("value"), ST("total"),
    N("percentXP", "Experience %", { state = true, multi = true }),
    H("restedExperienceHeader", "Rested"),
    TOG("showRested", "Show rested experience"),
    N("restedXP", "Rested experience", { state = true, multi = true }),
    N("percentrested", "Rested %", { state = true, multi = true }),
} })

Def("Faction Reputation", { type = "unit", label = "Reputation", progress = "static", fields = {
    TOG("watched", "The faction you watch"),
    SEL("factionID", "Faction", "faction_types", { on = function(t) return not t.use_watched end, req = true }),
    ST("name"),
    N("value", "Reputation", { state = true, multi = true }),
    N("total", "Reputation needed", { state = true, multi = true }),
    N("percentRep", "Reputation %", { state = true, multi = true }),
    ST("standing"),
    SEL("standingId", "Standing", "standing_types", { state = true }),
    TRI("capped", "At the top", { state = true }),
    TRI("atWar", "At war", { state = true }),
} })

Def("Money", { type = "unit", label = "Money", progress = "none", fields = {
    ST("money"),
    N("gold", "Gold", { state = true }),
    ST("silver"), ST("copper"), ST("icon"),
} })

Def("Pet Behavior", { type = "unit", label = "Pet mode", progress = "none", fields = {
    SEL("behavior", "Pet mode", "pet_behavior_types", { own = true }),
    TOG("inverse", "Inverse", { on = function(t) return t.use_behavior end }),
    SEL("petspec", "Pet kind", "pet_spec_types"),
    ST("icon"),
} })

Def("Crowd Controlled", { type = "unit", label = "Crowd controlled", progress = "timed", fields = {
    SEL("controlType", "Kind", "loss_of_control_types", { state = true, default = "STUN", own = true }),
    SEL("interruptSchool", "School locked", "main_spell_schools", { state = true, default = 1, own = true,
        on = function(t) return t.controlType == "SCHOOL_INTERRUPT" end }),
    TOG("inverse", "Inverse"),
    ST("name"), ST("spellName"), ST("spellId"), ST("lockoutSchool"), ST("icon"), ST("duration"), ST("expirationTime"),
} })

-- ---------- spell ----------
Def("Cooldown Progress (Spell)", { type = "spell", label = "Cooldown / charges / count", progress = "timed", fields = {
    SP("spellName", "Spell", { req = true, exact = true }),
    F("extra Cooldown Progress (Spell)", "header", "Options"),
    SEL("track", "Track", "cooldown_types", { req = true, default = "auto", own = true }),
    TOG("showgcd", "Count the global cooldown"),
    TOG("ignoreoverride", "Ignore spell overrides"),
    TOG("showlossofcontrol", "Show loss of control"),
    TOG("matchedRune", "Ignore rune cooldowns"),
    TOG("ignoreSpellKnown", "Even if not known"),
    N("trackcharge", "Cooldown of charge", { noOperator = true,
        on = function(t) return t.genericShowOn ~= "showOnReady" and t.track ~= "cooldown" end }),
    N("remaining", "Time left", { on = function(t) return t.genericShowOn ~= "showOnReady" end }),
    N("charges", "Charges", { state = true }),
    N("spellCount", "Count", { state = true }),
    ST("stacks"), ST("maxCharges"), ST("readyTime"), ST("chargeGainTime"), ST("chargeLostTime"), ST("effectiveSpellId"),
    SEL("genericShowOn", "Show", "cooldown_progress_behavior_types", { req = true, default = "showOnCooldown", own = true }),
    ST("onCooldown"), ST("gcdCooldown"), ST("spellUsable"), ST("insufficientResources"), ST("spellInRange"),
    ST("name"), ST("icon"),
} })

Def("Cooldown Ready (Spell)", { type = "spell", label = "Cooldown ready", progress = "timed", timed = true, fields = {
    SP("spellName", "Spell", { req = true, exact = true }),
    TOG("ignoreoverride", "Ignore spell overrides"),
    ST("name"), ST("icon"),
} })

Def("Charges Changed", { type = "spell", label = "Charges changed", progress = "timed", timed = true, fields = {
    SP("spellName", "Spell", { req = true, exact = true }),
    TOG("ignoreoverride", "Ignore spell overrides"),
    SEL("direction", "Charge gained / lost", "charges_change_type", { req = true, state = true,
        test = function(v, want) return want == "CHANGED" or (want == "GAINED" and (v.direction or 0) > 0)
            or (want == "LOST" and (v.direction or 0) < 0) end }),
    N("charges", "Charges", { state = true }),
    ST("name"), ST("icon"),
} })

Def("Global Cooldown", { type = "spell", label = "Global cooldown", progress = "timed", fields = {
    TOG("inverse", "Show when it is not running"),
    ST("name"), ST("icon"), ST("duration"), ST("expirationTime"),
} })

Def("Action Usable", { type = "spell", label = "Spell usable", progress = "none", fields = {
    SP("spellName", "Spell", { req = true, exact = true, state = true }),
    TOG("ignoreoverride", "Ignore spell overrides"),
    TOG("targetRequired", "Needs a valid target"),
    TOG("ignoreSpellCooldown", "Ignore its cooldown / charges"),
    N("charges", "Charges", { state = true, on = function(t) return not t.use_inverse and not t.use_ignoreSpellCooldown end }),
    N("spellCount", "Count", { state = true, on = function(t) return not t.use_ignoreSpellCooldown end }),
    ST("readyTime"), ST("chargeGainTime"), ST("chargeLostTime"),
    TOG("inverse", "Show when not usable"),
    ST("spellInRange"), ST("name"), ST("icon"), ST("stacks"),
} })

Def("Spell Known", { type = "spell", label = "Spell known", progress = "none", fields = {
    SP("spellName", "Spell", { req = true, exact = true }),
    TOG("petspell", "A pet spell"),
    TOG("inverse", "Show when not known"),
    ST("name"), ST("icon"),
} })

Def("Queued Action", { type = "spell", label = "Queued spell", progress = "none", fields = {
    SP("spellName", "Spell", { req = true, exact = true }),
} })

Def("Totem", { type = "spell", label = "Totem", progress = "timed", fields = {
    SEL("totemType", "Totem slot", "totem_types"),
    S("totemName", "Totem name (or spell id)", { state = true, test = function(v, want)
        if Same(v.totemName, want) then return true end
        local id = tonumber(want)
        return id ~= nil and GetSpellInfo ~= nil and GetSpellInfo(id) == v.totemName
    end }),
    LS("totemNamePattern", "Totem name pattern"),
    TOG("ignoreoverride", "Ignore spell overrides", { on = function() return false end }),
    N("icon", "Totem icon", { ops = "eq", state = true }),
    TOG("inverse", "Show when missing"),
    TOG("clones", "A display per totem", { on = function(t) return not (t.use_totemType or t.use_inverse) end }),
    N("remaining", "Time left", { on = NotInverse }),
} })

-- ---------- item ----------
Def("Item Count", { type = "item", label = "Item count", progress = "static", fields = {
    IT("itemName", "Item", { req = true, exact = true }),
    ST("itemId"), ST("name"),
    TOG("includeBank", "Count the bank too"),
    TOG("includeCharges", "Count charges"),
    N("count", "Count"),
    ST("stacks"), ST("value"), ST("total"), ST("icon"),
} })

Def("Cooldown Progress (Item)", { type = "item", label = "Item cooldown", progress = "timed", fields = {
    IT("itemName", "Item", { req = true }),
    ST("itemId"),
    N("remaining", "Time left", { on = function(t) return t.genericShowOn ~= "showOnReady" end }),
    F("extra Cooldown Progress (Item)", "header", "Options"),
    TOG("showgcd", "Count the global cooldown"),
    SEL("genericShowOn", "Show", "cooldown_progress_behavior_types", { req = true, default = "showOnCooldown", own = true }),
    ST("enabled"), ST("onCooldown"), ST("gcdCooldown"), ST("name"), ST("icon"), ST("duration"), ST("expirationTime"),
} })

Def("Cooldown Progress (Equipment Slot)", { type = "item", label = "Equipment slot cooldown", progress = "timed", fields = {
    ST("itemId"),
    SEL("itemSlot", "Slot", "item_slot_types", { req = true, own = true }),
    F("extra Cooldown Progress (Equipment Slot)", "header", "Options"),
    TOG("showgcd", "Count the global cooldown"),
    N("remaining", "Time left", { on = function(t) return t.genericShowOn ~= "showOnReady" end }),
    TOG("testForCooldown", "Has a use", { check = true }),
    SEL("genericShowOn", "Show", "cooldown_progress_behavior_types", { req = true, default = "showOnCooldown", own = true }),
    ST("duration"), ST("expirationTime"), ST("name"), ST("icon"), ST("stacks"), ST("onCooldown"), ST("gcdCooldown"),
} })

Def("Cooldown Ready (Item)", { type = "item", label = "Item cooldown ready", progress = "timed", timed = true, fields = {
    IT("itemName", "Item", { req = true }),
    ST("itemId"), ST("name"), ST("icon"),
} })

Def("Cooldown Ready (Equipment Slot)", { type = "item", label = "Equipment slot cooldown ready", progress = "timed", timed = true, fields = {
    SEL("itemSlot", "Slot", "item_slot_types", { req = true, own = true }),
    ST("itemId"), ST("name"), ST("icon"),
} })

Def("Item Equipped", { type = "item", label = "Item equipped", progress = "none", fields = {
    IT("itemName", "Item", { req = true }),
    ST("itemId"),
    SEL("itemSlot", "Slot", "item_slot_types", { own = true }),
    TOG("inverse", "Show when not equipped"),
    ST("name"), ST("icon"),
} })

Def("Item Type Equipped", { type = "item", label = "Weapon type equipped", progress = "none", fields = {
    SEL("itemSlot", "Slot", "item_slot_types", { own = true }),
    MS("itemTypeName", "Weapon type", "item_weapon_types", { req = true, noSingle = true,
        test = function(v, key) return v.types ~= nil and v.types[tonumber(key)] ~= nil end }),
} })

Def("Item Bonus Id Equipped", { type = "item", label = "Item bonus id equipped", progress = "none", fields = {
    S("itemBonusId", "Bonus id(s)", { req = true, state = true, own = true }),
    ST("name"), ST("icon"), ST("itemId"),
    SEL("itemSlot", "Slot", "item_slot_types", { state = true, own = true }),
    TOG("inverse", "Inverse"),
    ST("itemSlotString"),
} })

Def("Item Set", { type = "item", label = "Item set", progress = "static", fields = {
    S("itemSetId", "Item set id", { req = true, state = true }),
    N("equipped", "Pieces worn", { req = true, state = true }),
    ST("value"), ST("total"), ST("name"),
} })

Def("Weapon Enchant", { type = "item", label = "Weapon enchant", progress = "timed", fields = {
    SEL("weapon", "Weapon", "weapon_types", { req = true, default = "main", own = true }),
    S("enchant", "Enchant (name or id)", { own = true }),
    ST("enchantID"),
    N("stacks", "Charges", { state = true, on = function(t) return not t.showOn or t.showOn == "showOnActive" end }),
    ST("duration"), ST("expirationTime"), ST("name"), ST("icon"), ST("enchanted"),
    N("remaining", "Time left", { on = function(t) return not t.showOn or t.showOn == "showOnActive" end }),
    SEL("showOn", "Show", "weapon_enchant_types", { req = true, default = "showOnActive", own = true }),
} })

-- ---------- event (they show for a moment) ----------
Def("Chat Message", { type = "event", label = "Chat message", progress = "timed", timed = true, count = true, delay = true, fields = {
    SEL("messageType", "Channel", "chat_message_types"),
    LS("message", "Message", { state = true, caseless = true }),
    S("sourceName", "From", { state = true }),
    S("destName", "To", { state = true }),
    ST("sourceGUID"),
    TOG("cloneId", "A display per message"),
} })

Def("Spell Cast Succeeded", { type = "event", label = "Spell cast succeeded", progress = "timed", timed = true, count = true, delay = true,
    perUnit = true, fields = {
    F("unit", "unit", "Caster", { values = "actual_unit_types_cast", state = true }),
    SPS("spellNames", "Spell name(s)", { group = "spell" }),
    SPS("spellId", "Exact spell id(s)", { exact = true, group = "spell", state = true }),
    ST("icon"), ST("name"),
} })

Def("Ready Check", { type = "event", label = "Ready check", progress = "timed", timed = true, delay = true, fields = {} })

Def("Combat Events", { type = "event", label = "Entering / leaving combat", progress = "timed", timed = true, count = true, delay = true, fields = {
    SEL("eventtype", "When", "combat_event_type", { req = true }),
} })

Def("Encounter Events", { type = "event", label = "Boss fight start / end", progress = "timed", timed = true, count = true, delay = true, fields = {
    SEL("eventtype", "When", "encounter_event_type", { req = true }),
    S("encounterId", "Encounter id", { state = true }),
    S("encounterName", "Encounter name", { state = true }),
    SEL("difficulty", "Difficulty", "difficulty_types", { state = true }),
    TOG("success", "Won", { on = function(t) return t.eventtype == "ENCOUNTER_END" end, check = true, state = true }),
} })

-- ---------- combat log ----------
do
    local function Pre(t) return t.subeventPrefix or "" end
    local function Suf(t) return t.subeventSuffix or "" end
    local function NotCastStart(t) return not (Pre(t) == "SPELL" and Suf(t) == "_CAST_START") end
    local function SpellLike(t) local p = t.subeventPrefix return p and (p:find("SPELL") or p == "RANGE" or p:find("DAMAGE")) and true or false end
    local function DamageLike(t) local p, s = Pre(t), Suf(t) return t.subeventSuffix ~= nil and t.subeventPrefix ~= nil and (s == "_DAMAGE" or p == "DAMAGE_SHIELD" or p == "DAMAGE_SPLIT") end
    local function Sfx(...) local set = {} for _, s in ipairs({ ... }) do set[s] = true end
        return function(t) return t.subeventSuffix ~= nil and set[t.subeventSuffix] or false end end
    local Extra = Sfx("_ABSORBED", "_INTERRUPT", "_DISPEL", "_DISPEL_FAILED", "_STOLEN", "_AURA_BROKEN_SPELL")
    local f = {
        H("sourceHeader", "Source"),
        ST("sourceGUID"),
        F("sourceUnit", "unit", "Source unit", { values = "actual_unit_types_with_specific", state = true, check = true,
            on = function(t) return Pre(t) ~= "ENVIRONMENTAL" end }),
        SL("sourceName", "Source name(s)", { state = true }),
        SL("sourceNpcId", "Source npc id(s)", { state = true, on = function(t) return Pre(t) ~= "ENVIRONMENTAL" end }),
        SEL("sourceFlags", "Source is", "combatlog_flags_check_type", { state = true }),
        SEL("sourceFlags2", "Source reaction", "combatlog_flags_check_reaction"),
        SEL("sourceFlags3", "Source kind", "combatlog_flags_check_object_type"),
        SEL("sourceRaidFlags", "Source raid mark", "combatlog_raid_mark_check_type", { state = true }),
        ST("sourceRaidMarkIndex"), ST("sourceRaidMark"),
        H("destHeader", "Destination", { on = NotCastStart }),
        ST("destGUID"),
        F("destUnit", "unit", "Destination unit", { values = "actual_unit_types_with_specific", state = true, check = true, on = NotCastStart }),
        SL("destName", "Destination name(s)", { state = true, on = NotCastStart }),
        SL("destNpcId", "Destination npc id(s)", { state = true, on = NotCastStart }),
        SEL("destFlags", "Destination is", "combatlog_flags_check_type", { state = true, on = NotCastStart }),
        SEL("destFlags2", "Destination reaction", "combatlog_flags_check_reaction", { on = NotCastStart }),
        SEL("destFlags3", "Destination kind", "combatlog_flags_check_object_type", { on = NotCastStart }),
        SEL("destRaidFlags", "Destination raid mark", "combatlog_raid_mark_check_type", { state = true, on = NotCastStart }),
        ST("destRaidMarkIndex", { on = NotCastStart }), ST("destRaidMark", { on = NotCastStart }),
        H("subeventHeader", "Event details"),
        SPS("spellId", "Spell id(s)", { exact = true, state = true, group = "spell", on = SpellLike }),
        SPS("spellName", "Spell name(s)", { state = true, group = "spell", on = SpellLike }),
        SEL("spellSchool", "Spell school", "combatlog_spell_school_types_for_ui", { state = true, on = SpellLike }),
        SEL("environmentalType", "Environment", "environmental_types", { state = true, on = function(t) return Pre(t) == "ENVIRONMENTAL" end }),
        SEL("missType", "Miss type", "miss_types", { state = true, on = function(t) return t.subeventSuffix ~= nil and t.subeventPrefix ~= nil and (Suf(t) == "_MISSED" or Pre(t) == "DAMAGE_SHIELD_MISSED") end }),
        SP("extraSpellId", "Extra spell id", { state = true, check = true, on = Extra }),
        SP("extraSpellName", "Extra spell name", { state = true, check = true, on = Extra }),
        SEL("auraType", "Aura type", "aura_types", { state = true, on = function(t) local s = t.subeventSuffix return s ~= nil and (s:find("AURA") or s == "_DISPEL" or s == "_STOLEN") and true or false end }),
        N("amount", "Amount", { state = true, on = function(t) local p, s = Pre(t), Suf(t)
            return t.subeventSuffix ~= nil and t.subeventPrefix ~= nil and (s == "_ABSORBED" or s == "_DAMAGE" or s == "_HEAL"
                or s == "_ENERGIZE" or s == "_DRAIN" or s == "_LEECH" or p:find("DAMAGE") or s:find("DOSE")) and true or false end }),
        N("overkill", "Overkill", { state = true, on = DamageLike }),
        N("overhealing", "Overhealing", { state = true, on = Sfx("_HEAL") }),
        N("resisted", "Resisted", { state = true, on = DamageLike }),
        N("blocked", "Blocked", { state = true, on = DamageLike }),
        N("absorbed", "Absorbed", { state = true, on = function(t) return DamageLike(t) or Suf(t) == "_HEAL" end }),
        TRI("critical", "Critical", { state = true, on = function(t) return DamageLike(t) or Suf(t) == "_HEAL" end }),
        TRI("glancing", "Glancing", { state = true, on = DamageLike }),
        TRI("crushing", "Crushing", { state = true, on = DamageLike }),
        TRI("isOffHand", "Off hand", { state = true, on = function(t) return DamageLike(t) or Suf(t) == "_MISSED" end }),
        N("number", "Number", { state = true, on = function(t) local s = t.subeventSuffix return s ~= nil and (s == "_EXTRA_ATTACKS" or s:find("DOSE")) and true or false end }),
        N("overEnergize", "Over-energize", { state = true, on = Sfx("_ENERGIZE") }),
        SEL("powerType", "Power type", "power_types", { state = true, on = Sfx("_ENERGIZE", "_DRAIN", "_LEECH") }),
        N("extraAmount", "Extra amount", { state = true, on = Sfx("_DRAIN", "_LEECH") }),
        H("miscellaneousHeader", "More"),
        TOG("cloneId", "A display per event"),
        ST("icon"),
    }
    Def("Combat Log", { type = "combatlog", label = "Combat log", progress = "timed", timed = true, count = true, delay = true,
        fields = f, pre = Pre, suf = Suf })
end

-- ---------- other addons ----------
Def("GTFO", { type = "addons", label = "GTFO alert", progress = "timed", timed = true, fields = {
    SEL("alertType", "Alert", "gtfo_types", { state = true }),
} })

-- ============================================================
-- LOOK-UPS
-- ============================================================
-- kinds by category, sorted by label, for the editor's list
function P.Category(cat)
    local out = {}
    for name, t in pairs(L) do
        if t.type == cat then out[name] = t.label end
    end
    return out
end

function P.Get(event) return L[event] end

function P.Values(f, tr)
    local v = f.values
    if type(v) == "function" then v = v(tr or {}) end
    if type(v) == "string" then v = V[v] end
    if type(v) == "function" then v = v(tr or {}) end
    return type(v) == "table" and v or {}
end

function P.Enabled(f, tr)
    if f.on then
        local ok, res = pcall(f.on, tr or {})
        return ok and res and true or false
    end
    return true
end

-- ============================================================
-- CHECKING A TRIGGER AGAINST MEASURED VALUES
-- ============================================================
local function Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

local function CompareNum(a, op, b)
    a, b = tonumber(a), tonumber(b)
    if a == nil or b == nil then return false end
    if op == "<" then return a < b elseif op == "<=" then return a <= b
    elseif op == ">" then return a > b elseif op == ">=" then return a >= b
    elseif op == "~=" or op == "!=" then return a ~= b end
    return a == b
end
P.CompareNum = CompareNum

function Same(a, b)
    if a == nil or b == nil then return false end
    if a == b then return true end
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then return na == nb end
    return tostring(a) == tostring(b)
end
P.Same = Same

-- "a, b, -c": entries and excluded entries (backslash escapes)
local listCache = setmetatable({}, { __mode = "k" })
local function ParseList(input)
    if type(input) ~= "string" then input = input ~= nil and tostring(input) or "" end
    local cached = listCache[input]
    if cached then return cached end
    local yes, no = {}, {}
    local cur, neg, esc, started = "", false, false, false
    local function Add()
        local s = Trim(cur)
        if s ~= "" then if neg then no[s] = true else yes[s] = true end end
        cur, neg, started = "", false, false
    end
    for i = 1, #input do
        local c = input:sub(i, i)
        if esc then cur = cur .. c esc = false started = true
        elseif c == "\\" then esc = true
        elseif c == "," then Add()
        elseif c == "-" and not started and Trim(cur) == "" then neg = true
        else
            cur = cur .. c
            if not c:find("%s") then started = true end
        end
    end
    Add()
    local m = { yes = yes, no = no, any = next(yes) ~= nil }
    listCache[input] = m
    return m
end
P.ParseList = ParseList

local function ListCheck(input, value)
    local m = ParseList(input)
    local s = value ~= nil and tostring(value) or nil
    if m.any and not (s and m.yes[s]) then return false end
    if s and m.no[s] then return false end
    return true
end
P.ListCheck = ListCheck

-- "Name", "Name-Realm", "-Realm"
local function NameRealmCheck(input, name, realm)
    if not name then return false end
    realm = realm or ""
    for part in tostring(input or ""):gmatch("[^,]+") do
        part = Trim(part)
        local n, r = "", ""
        local inRealm, esc = false, false
        for i = 1, #part do
            local c = part:sub(i, i)
            if esc then
                if inRealm then r = r .. c else n = n .. c end
                esc = false
            elseif c == "\\" then esc = true
            elseif c == "-" and not inRealm then inRealm = true
            elseif inRealm then r = r .. c
            else n = n .. c end
        end
        if n ~= "" and r == "" and n == name then return true end
        if n == "" and r ~= "" and r == realm then return true end
        if n ~= "" and r ~= "" and n == name and r == realm then return true end
    end
    return false
end
P.NameRealmCheck = NameRealmCheck

-- map ids: plain = map, g = map group, c = map and its children,
-- a = area name, i = instance id; "-" excludes
local function ZoneCheck(input, v)
    local yes, no = false, false
    local any = false
    for token in tostring(input or ""):gmatch("[^,]+") do
        token = Trim(token)
        local neg = token:sub(1, 1) == "-"
        if neg then token = token:sub(2) end
        local kind, id = token:match("^([gGcCaAiI]?)(%d+)$")
        id = tonumber(id)
        if id then
            kind = kind:lower()
            local hit = false
            if kind == "g" then hit = v.zonegroupId == id
            elseif kind == "i" then hit = v.instanceId == id
            elseif kind == "a" then
                local nm = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
                hit = nm ~= nil and nm == v.subzone
            elseif kind == "c" then
                local m = v.zoneId
                local guard = 0
                while m and guard < 10 do
                    if m == id then hit = true break end
                    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
                    m = info and info.parentMapID
                    guard = guard + 1
                end
            else
                hit = v.zoneId == id
            end
            if neg then if hit then no = true end
            else any = true if hit then yes = true end end
        end
    end
    if no then return false end
    if any then return yes end
    return true
end
P.ZoneCheck = ZoneCheck

-- a spell list option: names (ids stand for their names) or exact ids
local function SpellSet(list, exact, into)
    into = into or { names = {}, ids = {} }
    if type(list) == "string" then list = { list } end
    if type(list) ~= "table" then return into end
    for _, s in ipairs(list) do
        if s ~= nil and s ~= "" then
            local id = tonumber(s)
            if exact then
                if id then into.ids[id] = true end
            elseif id then
                into.idNames = into.idNames or {}
                into.idNames[id] = true
                local nm = GetSpellInfo and GetSpellInfo(id)
                if nm then into.names[nm] = true end
            else
                into.names[tostring(s)] = true
            end
            into.any = true
        end
    end
    return into
end
P.SpellSet = SpellSet

local function SpellSetCheck(set, spellId, spellName)
    if not set.any then return true end
    if spellId and set.ids[spellId] then return true end
    local nm = spellName
    if not nm and spellId and GetSpellInfo then nm = GetSpellInfo(spellId) end
    if nm and set.names[nm] then return true end
    -- the Classic Era combat log may give 0 for the id: an exact id still
    -- matches when its name is the event's spell
    if (not spellId or spellId == 0) and spellName and GetSpellInfo then
        for id in pairs(set.ids) do
            if GetSpellInfo(id) == spellName then return true end
        end
    end
    return false
end
P.SpellSetCheck = SpellSetCheck

local function LongString(have, op, want, caseless)
    if have == nil or want == nil then return false end
    have, want = tostring(have), tostring(want)
    if caseless then have, want = have:lower(), want:lower() end
    if op == "find('%s')" then return have:find(want, 1, true) ~= nil end
    if op == "match('%s')" then
        local ok, res = pcall(string.match, have, want)
        return ok and res ~= nil
    end
    return have == want
end
P.LongString = LongString

local function MultiHas(set, value)
    if type(set) ~= "table" or value == nil then return false end
    if set[value] then return true end
    local n = tonumber(value)
    if n and set[n] then return true end
    return set[tostring(value)] and true or false
end

-- one field: true when the trigger's check holds for the values
local function FieldOK(f, tr, v, groups)
    if f.own then return true end
    local name, kind = f.name, f.kind
    local use = tr["use_" .. name]
    local want = tr[name]
    if kind == "tristate" then
        if use == nil then return true end
        local have = v[name] and true or false
        if f.test then have = f.test(v, want, tr) and true or false end
        return have == (use and true or false)
    elseif kind == "toggle" then
        if not f.check or not use then return true end
        if f.test then return f.test(v, want, tr) and true or false end
        return v[name] and true or false
    elseif kind == "multiselect" then
        if use == nil then return true end
        local t = type(want) == "table" and want or {}
        if use == true and not f.noSingle then
            if t.single == nil then return false end
            if f.test then return f.test(v, t.single, tr) and true or false end
            return Same(v[name], t.single)
        end
        local any = false
        for key, on in pairs(type(t.multi) == "table" and t.multi or {}) do
            if on then
                any = true
                if f.test then
                    if f.test(v, key, tr) then return true end
                elseif Same(v[name], key) then return true end
            end
        end
        if not any then return false end
        return false
    end
    if not (use or f.req) then return true end
    if want == nil or want == "" then return true end
    if kind == "number" then
        if f.noOperator then return true end
        if f.test then return f.test(v, want, tr) and true or false end
        if type(want) == "table" then
            local ops = tr[name .. "_operator"]
            for i, w in ipairs(want) do
                if w ~= nil and w ~= "" then
                    local op = type(ops) == "table" and ops[i] or (type(ops) == "string" and ops) or "=="
                    if not CompareNum(v[name], op, w) then return false end
                end
            end
            return true
        end
        local op = tr[name .. "_operator"]
        if type(op) == "table" then op = op[1] end
        return CompareNum(v[name], op or "==", want)
    elseif kind == "string" then
        if f.test then return f.test(v, want, tr) and true or false end
        if f.list or type(want) == "table" then
            local list = type(want) == "table" and want or { want }
            for _, w in ipairs(list) do if Same(v[name], w) then return true end end
            return false
        end
        return Same(v[name], want)
    elseif kind == "longstring" then
        return LongString(v[name], tr[name .. "_operator"] or "==", want, f.caseless and tr[name .. "_caseInsensitive"])
    elseif kind == "select" then
        if f.test then return f.test(v, want, tr) and true or false end
        return Same(v[name], want)
    elseif kind == "unit" then
        if not f.check then return true end
        if f.test then return f.test(v, want, tr) and true or false end
        local target = want == "member" and tr.specificUnit or want
        -- a GUID measured (the combat log): compare GUIDs
        local guid = v[name .. "GUID"]
        if guid ~= nil then
            local g = UnitGUID and UnitGUID(target)
            return g ~= nil and g == guid
        end
        local have = v[name]
        if not have then return false end
        if have == target then return true end
        if UnitIsUnit then
            local ok, same = pcall(UnitIsUnit, have, target)
            if ok and same then return true end
        end
        return false
    elseif kind == "strlist" then
        return ListCheck(want, v[name])
    elseif kind == "namerealm" then
        local from = f.from or { "name", "realm" }
        return NameRealmCheck(want, v[from[1]], v[from[2]])
    elseif kind == "zones" then
        return ZoneCheck(want, v)
    elseif kind == "spells" then
        -- fields sharing a group form one set: either may match
        if f.group and groups then
            local g = groups[f.group]
            if not g then
                g = { names = {}, ids = {} }
                groups[f.group] = g
                for _, o in ipairs(groups.fields) do
                    if o.kind == "spells" and o.group == f.group and P.Enabled(o, tr) and tr["use_" .. o.name] then
                        SpellSet(tr[o.name], o.exact, g)
                    end
                end
                g.result = SpellSetCheck(g, v.spellId, v.spellName or v.spell)
            end
            return g.result
        end
        return SpellSetCheck(SpellSet(want, f.exact), v.spellId, v.spellName or v.spell)
    elseif kind == "spell" or kind == "item" then
        if not f.check then return true end
        if f.test then return f.test(v, want, tr) and true or false end
        local have = v[name]
        if Same(have, want) then return true end
        if kind == "spell" and GetSpellInfo then
            local n = tonumber(want) and GetSpellInfo(tonumber(want))
            return n ~= nil and n == (v[name:gsub("Id$", "Name")] or have)
        end
        return false
    end
    return true
end
P.FieldOK = FieldOK

-- every enabled field of the kind holds
function P.Test(proto, tr, v)
    local groups = { fields = proto.fields }
    for _, f in ipairs(proto.fields) do
        if f.kind ~= "header" and f.kind ~= "description" and f.kind ~= "state" and P.Enabled(f, tr) then
            if not FieldOK(f, tr, v, groups) then return false, f.name end
        end
    end
    return true
end

-- the measured values the format keeps in the state
function P.Store(proto, tr, v, st)
    for _, f in ipairs(proto.fields) do
        if f.state and P.Enabled(f, tr) then
            local val = v[f.name]
            if st[f.name] ~= val then st[f.name] = val end
        end
    end
end

-- the option keys a field may write (for the editor and the tests)
function P.Keys(f)
    local n, k = f.name, f.kind
    if k == "header" or k == "description" or k == "state" then return {} end
    if k == "unit" then
        if n == "unit" then return { "unit", "use_specific_unit" } end
        return { "use_" .. n, n, "use_specific_" .. n }
    end
    local out = { "use_" .. n, n }
    if k == "number" and not f.noOperator then out[#out + 1] = n .. "_operator" end
    if k == "longstring" then out[#out + 1] = n .. "_operator" end
    if f.caseless then out[#out + 1] = n .. "_caseInsensitive" end
    if f.exact and (k == "spell" or k == "item") then out[#out + 1] = "use_exact_" .. n end
    return out
end
