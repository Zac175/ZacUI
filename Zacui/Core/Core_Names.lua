-- Core_Names - player names the way WoW Forever writes them, and the key a
-- character's saved data goes under there.
-- Part of ZacUI; load order is set by the TOC (after Core_Flavor: it asks
-- ns.IsSecret; before everything that shows a name or keys by character).
--
-- SURNAMES. A WoW Forever character carries a surname, which UnitName
-- hands back as its second value (on Retail that second value is the
-- realm, on Classic Era and TBC a realm for players from elsewhere, so
-- this only ever runs on the real Forever client: _G.ZACUI_IS_FOREVER from
-- Core_Forever, not the game-version override). The game's own frames show
-- "First Last"; your own surname follows the game's show-surname choice
-- (C_PlayerInfo.ShouldDisplaySurname). ZacUI's unit frames, nameplates and
-- tooltip target line do the same through ns.UnitDisplayName(unit), with
-- one setting over it (Tooltips > General, "Names on WoW Forever"):
-- follow the game (nothing saved), always, or never (first names only).
-- A name or surname the client hides (secret, in a fight) comes back as
-- it is, first name only: it cannot be looked at or joined.
--
-- KEYS. Forever has no realms you pick: characters are grouped by ruleset
-- (C_GameRules.IsGameRuleActive with Enum.GameRule HardcoreRuleset /
-- PvPRuleset / RPRuleset). ns.CharKey(sep, name, realm, store) is
-- "Name<sep>Realm" everywhere else, byte for byte, and "Name<sep>Ruleset"
-- on Forever ("Normal", "PvP", "RP", "PvP-RP", "Hardcore": plain words,
-- the same on every client language); given the table the key indexes, an
-- entry saved under the old Name-Realm key moves to the new one the first
-- time it is asked for. Everything is feature-detected: a client without
-- the rules API keeps the realm.
--
--   ns.UnitDisplayName(unit)          the name to show for a unit
--   ns.Names.Join(name, surname)      "First Last" (cached)
--   ns.Names.Mode()                   "follow" / "always" / "never"
--   ns.Names.Active()                 this client has surnames
--   ns.Names.RealmGroup()             the ruleset word on Forever, else nil
--   ns.CharKey(sep, name, realm, store)

local ADDON_NAME, ns = ...

local type, tostring, pcall = type, tostring, pcall

local N = {}
ns.Names = N

local function Hidden(v)
    local f = ns.IsSecret
    if f then return f(v) end
    if issecretvalue ~= nil then return issecretvalue(v) and true or false end
    return false
end

-- the real Forever client (not the override: on Era the second value of
-- UnitName is a realm)
function N.Active()
    return _G.ZACUI_IS_FOREVER == true
end

-- ============================================================
-- SURNAMES
-- ============================================================
local MODES = { always = true, never = true }
function N.Mode()
    local d = ZacUIDB and ZacUIDB.names
    local m = type(d) == "table" and d.surnames or nil
    return MODES[m] and m or "follow"
end
N.MODES = {
    { value = "follow", text = "As the game shows them" },
    { value = "always", text = "Always, mine too" },
    { value = "never", text = "First names only" },
}

local function Separator()
    local C = _G.Constants
    local S = C and C.CharacterNameSeparatorConsts
    local s = S and S.CHARACTERNAME_SURNAME_SEPARATOR
    return type(s) == "string" and s or " "
end

local joined = {}   -- [name][surname] = "First Last"
function N.Join(name, surname)
    if Hidden(name) or Hidden(surname) then return name end
    if type(name) ~= "string" or type(surname) ~= "string" or surname == "" then return name end
    local row = joined[name]
    if not row then row = {} joined[name] = row end
    local full = row[surname]
    if not full then
        local tail = Separator() .. surname
        -- (a unit can already carry it in the first value)
        full = (name:sub(-#tail) == tail) and name or (name .. tail)
        row[surname] = full
    end
    return full
end

-- the game's choice for your own surname
local function ShowMine()
    local PI = _G.C_PlayerInfo
    if not (PI and PI.ShouldDisplaySurname) then return true end
    local ok, v = pcall(PI.ShouldDisplaySurname)
    if not ok or Hidden(v) then return true end
    return v and true or false
end

local function IsMine(name, surname)
    local fn = _G.UnitNameUnmodified or _G.UnitName
    if not fn then return false end
    local ok, myName, mySurname = pcall(fn, "player")
    if not ok or Hidden(myName) or Hidden(mySurname) then return false end
    return name == myName and surname == mySurname
end

-- the name to show for a unit: UnitName's first value everywhere but
-- Forever, where the surname joins it as the setting says
function N.Unit(unit)
    if not UnitName then return nil end
    local name, second = UnitName(unit)
    if not N.Active() then return name end
    if Hidden(name) or Hidden(second) then return name end
    if type(name) ~= "string" or type(second) ~= "string" or second == "" then return name end
    local mode = N.Mode()
    if mode == "never" then return name end
    if mode == "follow" and not ShowMine() and IsMine(name, second) then return name end
    return N.Join(name, second)
end
ns.UnitDisplayName = N.Unit

-- ============================================================
-- CHARACTER KEYS
-- ============================================================
local function RuleOn(rule)
    if rule == nil then return false end
    local ok, v = pcall(C_GameRules.IsGameRuleActive, rule)
    if not ok or Hidden(v) then return false end
    return v == true
end

-- the ruleset word on Forever; nil anywhere else (keys keep the realm)
function N.RealmGroup()
    if not N.Active() then return nil end
    local GR, E = _G.C_GameRules, _G.Enum
    if not (GR and type(GR.IsGameRuleActive) == "function" and E and type(E.GameRule) == "table") then return nil end
    local R = E.GameRule
    if RuleOn(R.HardcoreRuleset) then return "Hardcore" end
    local pvp, rp = RuleOn(R.PvPRuleset), RuleOn(R.RPRuleset)
    if pvp and rp then return "PvP-RP" end
    if pvp then return "PvP" end
    if rp then return "RP" end
    return "Normal"
end

function ns.CharKey(sep, name, realm, store)
    sep = sep or "-"
    if name == nil then name = (UnitName and UnitName("player")) or "?" end
    if realm == nil then realm = (GetRealmName and GetRealmName()) or "" end
    local old = tostring(name) .. sep .. tostring(realm)
    local group = N.RealmGroup()
    if not group then return old end
    local key = tostring(name) .. sep .. group
    -- the entry saved under the realm key before moves over once
    if type(store) == "table" and old ~= key and store[old] ~= nil then
        if store[key] == nil then store[key] = store[old] end
        store[old] = nil
    end
    return key
end

-- ============================================================
-- THE SETTING: Tooltips > General (Forever only)
-- ============================================================
-- (Config_Base loads after the core: the tab goes on the list it reads)
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

AddTab("tooltips", "general", "General", function(L)
    if not N.Active() then return end
    local UI = ns.UI
    L:Card("Names on WoW Forever")
    local function Text(v)
        for _, m in ipairs(N.MODES) do if m.value == v then return m.text end end
        return N.MODES[1].text
    end
    local dd = UI.Field(L.current, "Surnames", function(h)
        return UI.Dropdown(h, { width = 220,
            items = function() return N.MODES end,
            selectedValue = function() return N.Mode() end,
            selected = function() return Text(N.Mode()) end,
            onSelect = function(v)
                if v == "follow" then
                    if type(ZacUIDB.names) == "table" then ZacUIDB.names.surnames = nil end
                else
                    ZacUIDB.names = type(ZacUIDB.names) == "table" and ZacUIDB.names or {}
                    ZacUIDB.names.surnames = v
                end
                if ns.ApplyAll then pcall(ns.ApplyAll) end
            end })
    end, { width = 220 })
    L:Row(dd, 46)
    L:Desc("On unit frames, nameplates and the tooltip's target line. \"As the game shows them\": "
        .. "everyone's surname, yours as the game's own setting says.")
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("tooltips", "surname surnames names forever first last")
end
