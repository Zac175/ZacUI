-- AE_Load - when a display is loaded at all: its "load" table.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- A display that is not loaded has no triggers listening and no frames
-- doing anything; checking load first is what keeps fifteen hundred saved
-- displays cheap. The load table's shape (from the WeakAuras format) and
-- how each kind of field is read, the same way WeakAuras reads it on
-- Classic Era:
--   tristate X     use_X true: must hold, false: must not hold, nil: ignored
--   toggle never   use_never true: never loads
--   multiselect X  use_X true: X.single must match (no single: ignored);
--                  use_X false: one of X.multi must match (none ticked:
--                  never loads); nil: ignored
--   text X         use_X true and X set: X must match (lists are comma
--                  separated; "-" in front excludes)
--   number X       use_X true: every entry of X (with X_operator) holds
--   spell / item   use_X true: the spell is known / the item is worn
-- Fields WeakAuras switches off on Classic Era (spec, difficulty, instance
-- type, war mode, pet battles...) are ignored here too. L.FIELDS lists
-- every field this file reads, by kind; the editor builds from it.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local L = {}
E.Load = L
local floor = math.floor

-- ============================================================
-- THE FIELDS (WeakAuras' Classic Era load options)
-- ============================================================
L.FIELDS = {
    { "combat", "tristate" }, { "never", "toggle" }, { "alive", "tristate" }, { "encounter", "tristate" },
    { "pvpmode", "tristate" }, { "vehicle", "tristate" }, { "mounted", "tristate" }, { "hardcore", "tristate" },
    { "engraving", "tristate" },
    { "class", "multiselect" }, { "talent", "multiselect" }, { "talent2", "multiselect" }, { "talent3", "multiselect" },
    { "spellknown", "spell" }, { "not_spellknown", "spell" },
    { "namerealm", "string" }, { "ignoreNameRealm", "string" }, { "guildcheck", "string" },
    { "race", "multiselect" }, { "faction", "multiselect" }, { "level", "number" },
    { "role", "multiselect" }, { "raid_role", "multiselect" }, { "ingroup", "multiselect" },
    { "groupSize", "number" }, { "group_leader", "multiselect" },
    { "zone", "string" }, { "zoneIds", "string" }, { "encounterid", "string" }, { "size", "multiselect" },
    { "itemequiped", "item" }, { "not_itemequiped", "item" }, { "itemtypeequipped", "multiselect" },
    { "item_bonusid_equipped", "string" }, { "not_item_bonusid_equipped", "string" },
}

-- the values each multiselect offers on Classic Era
L.VALUES = {
    class = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true,
        WARLOCK = true, DRUID = true },
    race = { Human = true, Orc = true, Dwarf = true, NightElf = true, Scourge = true, Tauren = true, Gnome = true, Troll = true },
    faction = { Alliance = true, Horde = true, Neutral = true },
    role = { TANK = true, DAMAGER = true, HEALER = true },
    raid_role = { MAINTANK = true, MAINASSIST = true, NONE = true },
    ingroup = { solo = true, group = true, raid = true },
    group_leader = { LEADER = true, ASSIST = true, NONE = true },
    size = { none = true, party = true, ten = true, twenty = true, twentyfive = true, fortyman = true, pvp = true },
    talent_extraOption = { [1] = true, [3] = true },
    -- weapon kinds (class 2) and shields (class 4, sub 6), as class * 256 + subclass
    itemtypeequipped = { [512] = true, [513] = true, [514] = true, [515] = true, [516] = true, [517] = true,
        [518] = true, [519] = true, [520] = true, [522] = true, [525] = true, [527] = true, [528] = true,
        [530] = true, [531] = true, [532] = true, [1030] = true },
}
L.OPERATORS = { ["=="] = true, ["~="] = true, ["<"] = true, ["<="] = true, [">"] = true, [">="] = true }

-- ============================================================
-- WHAT IS TRUE NOW
-- ============================================================
local now = {}
L.now = now

-- instance size by the game's difficulty id (as the format keys them)
local SIZE_BY_DIFFICULTY = { [1] = "party", [2] = "party", [3] = "ten", [4] = "twentyfive", [5] = "ten",
    [6] = "twentyfive", [9] = "fortyman", [148] = "twenty", [173] = "party", [174] = "party", [175] = "ten",
    [176] = "twentyfive", [186] = "fortyman", [226] = "twenty" }

local function SizeKey()
    local inInstance, kind = false, nil
    if IsInInstance then inInstance, kind = IsInInstance() end
    local _, itype, difficulty, _, _, _, _, instanceId = GetInstanceInfo()
    if inInstance or (itype and itype ~= "none") then
        if kind == "arena" or kind == "pvp" then difficulty = 0 end
        return SIZE_BY_DIFFICULTY[difficulty] or kind or itype or "none", instanceId
    end
    return "none", nil
end

local function Role()
    local r = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if r and r ~= "NONE" then return r end
    -- ZacUI's own idea of the role (tank stance, a Readycheck role pick)
    if ns.PlayerRole then
        local ok, got = pcall(ns.PlayerRole)
        if ok and got then return got end
    end
    return r or "NONE"
end

local function RaidRole()
    if not (UnitInRaid and GetRaidRosterInfo) then return nil end
    local idx = UnitInRaid("player")
    if not idx then return nil end
    local ok, role = pcall(function() return select(10, GetRaidRosterInfo(idx)) end)
    return ok and role or nil
end

function L.Refresh()
    now.class = select(2, UnitClass("player"))
    now.race = select(2, UnitRace("player"))
    now.faction = UnitFactionGroup("player")
    now.level = UnitLevel("player")
    now.name = UnitName("player")
    now.realm = GetRealmName and GetRealmName()
    now.guild = GetGuildInfo and GetGuildInfo("player") or nil
    now.combat = UnitAffectingCombat("player") or (InCombatLockdown and InCombatLockdown()) or false
    now.zone = GetRealZoneText and GetRealZoneText() or ""
    now.subzone = GetSubZoneText and GetSubZoneText() or ""
    now.minimapZone = GetMinimapZoneText and GetMinimapZoneText() or now.subzone
    local _, itype, difficulty = GetInstanceInfo()
    now.instanceType = itype
    now.difficulty = difficulty
    now.size, now.instanceId = SizeKey()
    now.mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    now.mapGroupId = now.mapId and C_Map.GetMapGroupID and C_Map.GetMapGroupID(now.mapId) or nil
    now.role = Role()
    now.raidRole = RaidRole()
    now.inGroup = (IsInGroup and IsInGroup()) or false
    now.inRaid = (IsInRaid and IsInRaid()) or false
    now.group = now.inRaid and "raid" or (now.inGroup and "group" or "solo")
    now.groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
    local flags = 0
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then flags = flags + 1 end
    if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then flags = flags + 2 end
    now.leaderFlags = flags
    now.leader = flags % 2 == 1
    now.alive = not UnitIsDeadOrGhost("player")
    now.mounted = (IsMounted and IsMounted()) or false
    now.resting = (IsResting and IsResting()) or false
    now.pvp = (UnitIsPVPFreeForAll and UnitIsPVPFreeForAll("player")) or (UnitIsPVP and UnitIsPVP("player")) or false
    now.vehicle = (UnitInVehicle and UnitInVehicle("player")) or (UnitOnTaxi and UnitOnTaxi("player")) or false
    now.hardcore = (C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive()) or false
    now.engraving = (C_Engraving and C_Engraving.IsEngravingEnabled and C_Engraving.IsEngravingEnabled()) or false
    now.encounter = L.encounter
end

-- ============================================================
-- CHECKERS (built once per text, kept)
-- ============================================================
local cache = setmetatable({}, { __mode = "k" })
local strCache, nameCache, zoneCache = {}, {}, {}

local function Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

-- "a, b, -c": names that must (or, with "-", must not) be the value;
-- "\" escapes the next character
local function StringCheck(input)
    local c = strCache[input]
    if c then return c end
    local pos, neg = {}, {}
    local part, negate, escaped = "", false, false
    local function Flush()
        local v = Trim(part)
        if negate then neg[v] = true else pos[v] = true end
        part, negate = "", false
    end
    for i = 1, #input do
        local ch = input:sub(i, i)
        if escaped then
            part = part .. ch
            escaped = false
        elseif ch == "\\" then
            escaped = true
        elseif ch == "," then
            Flush()
        elseif ch == "-" and Trim(part) == "" then
            negate = true
            part = ""
        else
            part = part .. ch
        end
    end
    Flush()
    local hasPos, hasNeg = next(pos) ~= nil, next(neg) ~= nil
    c = function(v)
        if hasPos and hasNeg then return pos[v] and not neg[v] end
        if hasPos then return pos[v] and true or false end
        if hasNeg then return not neg[v] end
        return false
    end
    strCache[input] = c
    return c
end
L.StringCheck = StringCheck

-- "Name", "Name-Realm", "-Realm", comma separated ("\" escapes "-")
local function NameCheck(input)
    local c = nameCache[input]
    if c then return c end
    local names, realms, full = {}, {}, {}
    for entry in (input .. ","):gmatch("([^,]*),") do
        entry = Trim(entry)
        local name, realm, inRealm, esc = "", "", false, false
        for i = 1, #entry do
            local ch = entry:sub(i, i)
            if esc then
                if inRealm then realm = realm .. ch else name = name .. ch end
                esc = false
            elseif ch == "\\" then
                esc = true
            elseif ch == "-" and not inRealm then
                inRealm = true
            elseif inRealm then
                realm = realm .. ch
            else
                name = name .. ch
            end
        end
        if name == "" and realm ~= "" then realms[realm] = true
        elseif name ~= "" and realm == "" then names[name] = true
        elseif name ~= "" then full[name .. "-" .. realm] = true end
    end
    c = function(name, realm)
        if not name or not realm then return false end
        return (names[name] or realms[realm] or full[name .. "-" .. realm]) and true or false
    end
    nameCache[input] = c
    return c
end
L.NameCheck = NameCheck

-- location ids: plain = this zone (map id), g = map group, c = a map and
-- every map under it, a = an area name, i = an instance id; "-" excludes
local function ZoneCheck(input)
    local c = zoneCache[input]
    if c then return c end
    local pos = { zone = {}, group = {}, inst = {}, area = {} }
    local neg = { zone = {}, group = {}, inst = {}, area = {} }
    local anyPos, anyNeg = false, false
    for raw in input:gmatch("[^,]+") do
        local s = Trim(raw)
        local minus, kind, n = s:match("^(%-?)%s*(%a?)%s*(%d+)$")
        n = tonumber(n)
        if n then
            local t = minus == "-" and neg or pos
            if minus == "-" then anyNeg = true else anyPos = true end
            kind = (kind or ""):lower()
            if kind == "g" then t.group[n] = true
            elseif kind == "i" then t.inst[n] = true
            elseif kind == "a" then
                local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(n)
                if name then t.area[name] = true end
            elseif kind == "c" then
                t.zone[n] = true
                local kids = C_Map and C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(n, nil, true)
                if type(kids) == "table" then
                    for _, k in pairs(kids) do if k.mapID then t.zone[k.mapID] = true end end
                end
            else
                t.zone[n] = true
            end
        end
    end
    local function Hit(t, zone, group, inst, area)
        return (zone and t.zone[zone]) or (group and t.group[group]) or (inst and t.inst[inst]) or (area and t.area[area])
    end
    c = function(zone, group, inst, area)
        if anyPos and not Hit(pos, zone, group, inst, area) then return false end
        if anyNeg and Hit(neg, zone, group, inst, area) then return false end
        return anyPos or anyNeg
    end
    zoneCache[input] = c
    return c
end
L.ZoneCheck = ZoneCheck

-- an id in a list of ids, as a whole number (12 is not in "123")
local function NumericIdIn(list, id)
    if not list or not id then return false end
    list, id = tostring(list), tostring(id)
    local from = 1
    while true do
        local s, e = list:find(id, from, true)
        if not s then return false end
        local before = s == 1 or not tonumber(list:sub(s - 1, s - 1))
        local after = e == #list or not tonumber(list:sub(e + 1, e + 1))
        if before and after then return true end
        from = e + 1
    end
end
L.NumericIdIn = NumericIdIn

-- the old name for the same helper (custom code calls it)
E.WA.CheckNumericIds = function(ids, id) return NumericIdIn(ids, id) end

local function Compare(a, op, b)
    a, b = tonumber(a), tonumber(b)
    if not a or not b then return false end
    if op == "<" then return a < b elseif op == "<=" then return a <= b
    elseif op == ">" then return a > b elseif op == ">=" then return a >= b
    elseif op == "~=" or op == "!=" then return a ~= b end
    return a == b
end

-- every entry of a number field holds (a field may still be one plain
-- value from before the format kept them as lists)
local function Numbers(value, ops, current)
    if type(value) == "table" then
        if #value == 0 then return true end
        for i, v in ipairs(value) do
            if tonumber(v) then
                local op = type(ops) == "table" and ops[i] or (type(ops) == "string" and ops or nil)
                if not Compare(current, op or "==", v) then return false end
            end
        end
        return true
    end
    if tonumber(value) then
        local op = type(ops) == "table" and ops[1] or ops
        return Compare(current, op or "==", value)
    end
    return true
end

-- a spell the character (or its pet) knows; a name is looked up first
local function SpellKnown(spell, exact)
    local id = tonumber(spell)
    if not id and type(spell) == "string" and GetSpellInfo then id = select(7, GetSpellInfo(spell)) end
    if not id or id == 0 or id >= 2 ^ 31 then return false end
    local known = (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and (IsSpellKnown(id) or IsSpellKnown(id, true)))
    if known or exact then return known and true or false end
    -- another rank of the same spell counts
    local name = GetSpellInfo and GetSpellInfo(id)
    if name then
        local other = select(7, GetSpellInfo(name))
        if other and other ~= id then
            return ((IsPlayerSpell and IsPlayerSpell(other)) or (IsSpellKnown and IsSpellKnown(other))) and true or false
        end
    end
    return false
end
L.SpellKnown = SpellKnown

local function Equipped(item)
    if item == nil or item == "" then return false end
    local fn = (C_Item and C_Item.IsEquippedItem) or IsEquippedItem
    if not fn then return false end
    local ok, res = pcall(fn, tonumber(item) or item)
    return ok and res and true or false
end

local function EquippedType(key)
    key = tonumber(key)
    if not key then return false end
    local sub = key % 256
    local class = (key - sub) / 256
    local info = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    local isType = (C_Item and C_Item.IsEquippedItemType) or IsEquippedItemType
    if not (info and isType) then return false end
    local ok, name = pcall(info, class, sub)
    if not (ok and name) then return false end
    local ok2, res = pcall(isType, name)
    return ok2 and res and true or false
end

-- an id among the numbers in the links of what is worn
local function BonusId(ids)
    if not GetInventoryItemLink then return false end
    for id in tostring(ids):gmatch("[^,]+") do
        local find = ":" .. Trim(id)
        for slot = 0, 19 do
            local link = GetInventoryItemLink("player", slot)
            if link then
                local s = link:find(":", 1, true)
                s = s and link:find(":", s + 1, true)
                if s and (link:find(find .. ":", s, true) or link:find(find .. "|", s, true)) then return true end
            end
        end
    end
    return false
end

-- a talent by its index (tab - 1) * 20 + position: picked or not
local function TalentPicked(index)
    index = tonumber(index)
    if not (index and GetTalentInfo) then return nil end
    local tab = math.ceil(index / 20)
    local num = (index - 1) % 20 + 1
    local ok, name, _, _, _, rank = pcall(GetTalentInfo, tab, num)
    if not ok or name == nil then return nil end
    return (tonumber(rank) or 0) > 0
end
L.TalentPicked = TalentPicked

-- ============================================================
-- READING ONE LOAD TABLE
-- ============================================================
local function Tristate(use, value)
    if use == nil then return true end
    if use then return value and true or false end
    return not value
end

-- a multiselect: test(key) answers one choice
local function Multi(ld, key, test, inverse)
    local use = ld["use_" .. key]
    if use == nil then return true end
    local t = ld[key]
    if use == true then
        if type(t) ~= "table" or t.single == nil then return true end
        local r = test(t.single) and true or false
        if inverse then r = not r end
        return r
    end
    local any, hit = false, false
    if type(t) == "table" and type(t.multi) == "table" then
        for k, on in pairs(t.multi) do
            if on ~= nil then
                any = true
                if test(k, on) then hit = true break end
            end
        end
    end
    local r = any and hit
    if inverse then r = not r end
    return r
end

local function Eq(current) return function(k) return k == current or tonumber(k) ~= nil and tonumber(k) == current end end

local function TalentField(ld, key)
    local extra = tonumber(ld[key .. "_extraOption"])
    local inverse = extra == 2 or extra == 3
    return Multi(ld, key, function(k) return TalentPicked(k) end, inverse)
end

-- the text of a field when it is switched on (an empty text still counts,
-- as it does in the format)
local function On(ld, key)
    if ld["use_" .. key] and ld[key] ~= nil then return ld[key] end
    return nil
end

-- true when everything in `ld` holds right now
function L.Check(ld)
    if type(ld) ~= "table" then return true end
    if ld.use_never then return false end
    if not Tristate(ld.use_combat, now.combat) then return false end
    if not Tristate(ld.use_alive, now.alive) then return false end
    if not Tristate(ld.use_encounter, now.encounter ~= nil) then return false end
    if not Tristate(ld.use_pvpmode, now.pvp) then return false end
    if not Tristate(ld.use_vehicle, now.vehicle) then return false end
    if not Tristate(ld.use_mounted, now.mounted) then return false end
    if not Tristate(ld.use_hardcore, now.hardcore) then return false end
    if not Tristate(ld.use_engraving, now.engraving) then return false end
    -- not a WeakAuras field: an older ZacUI one, kept working
    if not Tristate(ld.use_resting, now.resting) then return false end
    if not Multi(ld, "class", Eq(now.class)) then return false end
    if ld.use_talent ~= nil and not TalentField(ld, "talent") then return false end
    if ld.use_talent2 ~= nil and not TalentField(ld, "talent2") then return false end
    if ld.use_talent3 ~= nil and not TalentField(ld, "talent3") then return false end
    local v = On(ld, "spellknown")
    if v ~= nil and not SpellKnown(v, ld.use_exact_spellknown) then return false end
    v = On(ld, "not_spellknown")
    if v ~= nil and SpellKnown(v, ld.use_exact_not_spellknown) then return false end
    v = On(ld, "namerealm")
    if v ~= nil and not NameCheck(tostring(v))(now.name, now.realm) then return false end
    v = On(ld, "ignoreNameRealm")
    if v ~= nil and NameCheck(tostring(v))(now.name, now.realm) then return false end
    v = On(ld, "guildcheck")
    if v ~= nil and not StringCheck(tostring(v))(now.guild) then return false end
    if not Multi(ld, "race", Eq(now.race)) then return false end
    if not Multi(ld, "faction", Eq(now.faction)) then return false end
    if ld.use_level and ld.level ~= nil and not Numbers(ld.level, ld.level_operator, now.level) then return false end
    if not Multi(ld, "role", Eq(now.role)) then return false end
    if not Multi(ld, "raid_role", Eq(now.raidRole)) then return false end
    if not Multi(ld, "ingroup", Eq(now.group)) then return false end
    if ld.use_groupSize and ld.groupSize ~= nil and not Numbers(ld.groupSize, ld.groupSize_operator, now.groupSize) then return false end
    if not Multi(ld, "group_leader", function(k)
        if k == "LEADER" then return now.leaderFlags % 2 == 1 end
        if k == "ASSIST" then return floor((now.leaderFlags or 0) / 2) % 2 == 1 end
        return now.leaderFlags == 0
    end) then return false end
    v = On(ld, "zone")
    if v ~= nil and not StringCheck(tostring(v))(now.zone) then return false end
    v = On(ld, "zoneIds")
    if v ~= nil and not ZoneCheck(tostring(v))(now.mapId, now.mapGroupId, now.instanceId, now.minimapZone) then return false end
    v = On(ld, "encounterid")
    if v ~= nil and not NumericIdIn(v, now.encounter or 0) then return false end
    if not Multi(ld, "size", Eq(now.size)) then return false end
    if ld.use_itemequiped and type(ld.itemequiped) == "table" and #ld.itemequiped > 0 then
        local any = false
        for _, item in ipairs(ld.itemequiped) do if Equipped(item) then any = true break end end
        if not any then return false end
    end
    if ld.use_not_itemequiped and type(ld.not_itemequiped) == "table" and #ld.not_itemequiped > 0 then
        local any = false
        for _, item in ipairs(ld.not_itemequiped) do if not Equipped(item) then any = true break end end
        if not any then return false end
    end
    if not Multi(ld, "itemtypeequipped", EquippedType) then return false end
    v = On(ld, "item_bonusid_equipped")
    if v ~= nil and not BonusId(v) then return false end
    v = On(ld, "not_item_bonusid_equipped")
    if v ~= nil and BonusId(v) then return false end
    return true
end

-- ============================================================
-- WHEN TO LOOK AGAIN
-- ============================================================
-- Every change below re-reads the state once, a moment later (several
-- usually arrive together), and tells the engine to re-check every
-- display.
local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        L.Refresh()
        if E.CheckLoads then E.CheckLoads() end
    end)
end
L.Soon = Soon

for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_LEVEL_UP", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ROLES_ASSIGNED",
    "PARTY_LEADER_CHANGED", "PLAYER_UPDATE_RESTING", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_FLAGS_CHANGED",
    "PLAYER_GUILD_UPDATE", "SPELLS_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_PET" }) do
    E.On(ev, "load.watch", Soon)
end
-- unit events: only the player's matter (they fire for everyone)
for _, ev in ipairs({ "UNIT_FLAGS", "UNIT_FACTION", "UNIT_INVENTORY_CHANGED" }) do
    E.On(ev, "load.watch", function(_, unit) if unit == "player" then Soon() end end)
end
-- combat changes need to be quick: auras that load in combat must be up
-- for the first second of it
E.On("PLAYER_REGEN_DISABLED", "load.combat", function()
    now.combat = true
    if E.CheckLoads then E.CheckLoads() end
end)
E.On("PLAYER_REGEN_ENABLED", "load.combatEnd", function()
    now.combat = false
    if E.CheckLoads then E.CheckLoads() end
end)
E.On("ENCOUNTER_START", "load.encounter", function(_, id)
    L.encounter = tonumber(id)
    now.encounter = L.encounter
    if E.CheckLoads then E.CheckLoads() end
end)
E.On("ENCOUNTER_END", "load.encounterEnd", function()
    L.encounter = nil
    now.encounter = nil
    if E.CheckLoads then E.CheckLoads() end
end)
E.AtLogin(function() L.Refresh() end)
