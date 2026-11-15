-- AE_TriggerGeneric - the built-in trigger kinds that are not buffs or
-- custom code: unit, spell, item, event, combat log and other-addon kinds.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- The format stores one of these as trigger.type ("unit", "spell"...)
-- plus trigger.event naming which one ("Health", "Cooldown Progress
-- (Spell)"...). What options a kind has, and how each is checked, is
-- data in AE_Protos (E.Protos). This file measures: for each kind a
-- Fetch fills a table of values (what the game says right now, or what
-- an event carried); E.Protos.Test checks the trigger's options against
-- it and E.Protos.Store copies the values texts and conditions read into
-- the state.
--
-- Events that fire many times a second (cooldown, bag, health, power
-- updates) only mark a kind as dirty (with the unit, when there is one);
-- one pass a frame re-checks the triggers of that kind.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local Tr = E.Triggers
local G = {}
E.Generic = G
local RUN = {}
G.RUN = RUN
G.PROTO = RUN

local GetTime = GetTime

local function P() return E.Protos end

-- ============================================================
-- SHARED PIECES
-- ============================================================
local function Num(v) return tonumber(v) end

local function Compare(a, op, b)
    if type(b) == "string" and not tonumber(b) then
        a = a and tostring(a) or ""
        if op == "find('%s')" then return a:find(b, 1, true) ~= nil end
        if op == "match('%s')" then return a:match(b) ~= nil end
        if op == "~=" or op == "!=" then return a ~= b end
        return a == b
    end
    a, b = tonumber(a), tonumber(b)
    if not a or not b then return a == nil and b == nil end
    if op == "<" then return a < b elseif op == "<=" then return a <= b
    elseif op == ">" then return a > b elseif op == ">=" then return a >= b
    elseif op == "~=" or op == "!=" then return a ~= b end
    return a == b
end
G.Compare = Compare

local function NpcId(guid)
    if type(guid) ~= "string" then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end   -- (hidden on WoW Forever)
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then return id end
    return nil
end
G.NpcId = function(guid) return tonumber(NpcId(guid)) end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k end
    return nil
end

-- spell name or id from an option (names in options may be ids)
local function SpellArg(v)
    if v == nil or v == "" then return nil end
    if type(v) == "table" then return nil end
    return tonumber(v) or v
end

local function SpellName(v)
    local s = SpellArg(v)
    if type(s) == "number" and GetSpellInfo then return (GetSpellInfo(s)) or tostring(s) end
    return s
end

local function SpellIcon(v)
    local s = SpellArg(v)
    if s == nil then return nil end
    local t = SafeCall(GetSpellTexture, s)
    return t
end

local function ItemArg(v)
    if v == nil or v == "" or type(v) == "table" then return nil end
    return tonumber(v) or v
end

local function ItemId(item)
    if type(item) == "number" then return item end
    if not item then return nil end
    if GetItemInfoInstant then
        local id = SafeCall(GetItemInfoInstant, item)
        if id then return id end
    end
    local link = GetItemInfo and select(2, SafeCall(GetItemInfo, item))
    return link and tonumber(link:match("item:(%d+)")) or nil
end

local function ItemIcon(item)
    if GetItemIcon then
        local t = SafeCall(GetItemIcon, item)
        if t then return t end
    end
    return nil
end

local function ItemName(item)
    return (GetItemInfo and SafeCall(GetItemInfo, item)) or (item and tostring(item))
end

-- the player's realm, for name / realm checks
local function NameRealm(unit)
    if not UnitName then return nil, nil end
    local name, realm = UnitName(unit)
    -- (WoW Forever hides an enemy's name in a fight: no name then)
    if issecretvalue and (issecretvalue(name) or issecretvalue(realm)) then return nil, nil end
    if name and (not realm or realm == "") then realm = GetRealmName and GetRealmName() or "" end
    return name, realm
end

local function Reaction(unit)
    local r = UnitReaction and UnitReaction("player", unit)
    if r then return r < 5 and "hostile" or "friendly" end
    if UnitCanAttack then return UnitCanAttack("player", unit) and "hostile" or "friendly" end
    return nil
end

local function RaidRole(unit)
    if GetPartyAssignment then
        if SafeCall(GetPartyAssignment, "MAINTANK", unit) then return "MAINTANK" end
        if SafeCall(GetPartyAssignment, "MAINASSIST", unit) then return "MAINASSIST" end
    end
    return "NONE"
end

-- instance size the way the format names it
local function InstanceType()
    local _, itype, _, _, maxPlayers = GetInstanceInfo()
    if itype == "pvp" or itype == "arena" then return "pvp" end
    if itype == "party" then return "party" end
    if itype == "raid" then
        if maxPlayers == 10 then return "ten" elseif maxPlayers == 20 then return "twenty"
        elseif maxPlayers == 25 then return "twentyfive" end
        return "fortyman"
    end
    return "none"
end
G.InstanceType = InstanceType

local function Difficulty()
    local _, itype, diff = GetInstanceInfo()
    if itype == "none" or not diff or diff == 0 then return "none" end
    if diff == 2 or diff == 174 then return "heroic" end
    return "normal"
end

local function GroupType()
    if IsInRaid and IsInRaid() then return "raid" end
    if IsInGroup and IsInGroup() then return "group" end
    return "solo"
end

-- the unit's characteristics many unit kinds share
local function UnitInfo(unit, v)
    v.name, v.realm = NameRealm(unit)
    v.npcId = NpcId(UnitGUID(unit))
    v.class = select(2, UnitClass(unit))
    v.role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
    v.raid_role = RaidRole(unit)
    v.raidMarkIndex = GetRaidTargetIndex and GetRaidTargetIndex(unit) or 0
    if issecretvalue and issecretvalue(v.raidMarkIndex) then v.raidMarkIndex = 0 end   -- (WoW Forever)
    v.raidMark = (v.raidMarkIndex or 0) > 0 and ("{rt" .. v.raidMarkIndex .. "}") or ""
    v.nameplateType = Reaction(unit)
    v.ignoreSelf = not UnitIsUnit("player", unit)
    v.ignoreDead = not UnitIsDeadOrGhost(unit)
    v.ignoreDisconnected = not UnitIsConnected or UnitIsConnected(unit)
end

-- the show/ready/always switch the cooldown kinds share
local function ShowOn(mode, startTime, gcd)
    mode = mode or "showOnCooldown"
    if mode == "showAlways" then return startTime ~= nil end
    if mode == "showOnReady" then return startTime ~= nil and (startTime == 0 or gcd) end
    return startTime ~= nil and startTime > 0 and not gcd
end

-- ============================================================
-- UNITS A TRIGGER LOOKS AT
-- ============================================================
local plates = {}
local function GroupList(kind, pets)
    local out = {}
    local function Add(u, pet)
        if pets ~= "PetsOnly" then out[#out + 1] = u end
        if pets and pet then out[#out + 1] = pet end
    end
    if kind ~= "party" and IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do Add("raid" .. i, "raidpet" .. i) end
    elseif kind ~= "raid" then
        Add("player", "pet")
        for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do Add("party" .. i, "partypet" .. i) end
    end
    return out
end

local function Units(tr, default)
    local u = tr.unit or default or "player"
    local pets = tr.use_includePets and tr.includePets or nil
    if u == "group" or u == "party" or u == "raid" then return GroupList(u, pets), true end
    if u == "nameplate" then
        local out = {}
        for unit in pairs(plates) do out[#out + 1] = unit end
        table.sort(out)
        return out, true
    end
    if u == "boss" then return { "boss1", "boss2", "boss3", "boss4", "boss5" }, true end
    if u == "member" then return { tr.specificUnit or "" }, false end
    return { u }, false
end
G.Units = Units

E.On("NAME_PLATE_UNIT_ADDED", "generic.plates", function(_, unit) if unit then plates[unit] = true end end)
E.On("NAME_PLATE_UNIT_REMOVED", "generic.plates", function(_, unit) if unit then plates[unit] = nil end end)

-- ============================================================
-- STATES
-- ============================================================
local function Done(ctx, changed)
    if changed then
        E.Changed(ctx.id)
        Tr.Notify(ctx.id, ctx.index)
    end
end

-- turns the values into a shown state (or hides it)
local function SetState(ctx, cid, show, v)
    local st = ctx.states[cid]
    if show then
        if not st then
            st = {}
            ctx.states[cid] = st
        end
        st.show, st.changed = true, true
        local proto = ctx.def
        if proto then P().Store(proto, ctx.trigger, v, st) end
        if ctx.run.State then ctx.run.State(ctx, st, v) end
        return true
    elseif st and st.show then
        st.show, st.changed = false, true
        return true
    end
    return false
end

-- checks the values and shows / hides one state
local function Judge(ctx, cid, v, ok)
    local tr = ctx.trigger
    local pass = ok and P().Test(ctx.def, tr, v) or false
    if ctx.run.Final then pass = ctx.run.Final(ctx, v, pass, ok) end
    return SetState(ctx, cid, pass and true or false, v), pass
end

-- an event kind shows for `duration` seconds after it fires
local function Pulse(ctx, v, cloneId)
    local tr = ctx.trigger
    local dur = tonumber(tr.duration or "1") or 1
    local cid = cloneId or ""
    local st = ctx.states[cid] or {}
    ctx.states[cid] = st
    st.show, st.changed = true, true
    st.progressType, st.duration, st.expirationTime, st.autoHide = "timed", dur, GetTime() + dur, true
    if ctx.def then P().Store(ctx.def, tr, v or {}, st) end
    if ctx.run.State then ctx.run.State(ctx, st, v or {}) end
    Done(ctx, true)
end

-- counting events ("show on the 2nd, 4th..."): "2", "1-3", "2/2"
local function Counter(pattern)
    local tests = {}
    for part in tostring(pattern or ""):gmatch("[^ ,]+") do
        local a, b, step = part:match("(%d*)-?(%d*)/?(%d*)")
        local s, e, st = tonumber(a) or 0, tonumber(b), tonumber(step)
        if not e then e = st and math.huge or s end
        tests[#tests + 1] = { s, e, st or 1 }
    end
    return function(n)
        if #tests == 0 then return true end
        for _, t in ipairs(tests) do
            if n >= t[1] and n <= t[2] and (n - t[1]) % t[3] == 0 then return true end
        end
        return false
    end
end
G.Counter = Counter

local uniqueClone = 0
-- an event that passed: count it, wait its delay, then show
local function Fire(ctx, v, cloneId)
    local tr = ctx.trigger
    local def = ctx.def
    if def.count then
        ctx.counted = (ctx.counted or 0) + 1
        v.count = ctx.counted
        if tr.use_count and type(tr.count) == "string" and tr.count ~= "" then
            ctx.countMatch = ctx.countMatch or Counter(tr.count)
            if not ctx.countMatch(ctx.counted) then return end
        end
    end
    if cloneId == true then
        uniqueClone = uniqueClone + 1
        cloneId = tostring(uniqueClone)
    end
    local delay = def.delay and tr.use_delay and tonumber(tr.delay) or 0
    if delay > 0 then
        C_Timer.After(delay, function() if ctx.alive then Pulse(ctx, v, cloneId) end end)
    else
        Pulse(ctx, v, cloneId)
    end
end

-- ============================================================
-- DIRTY KINDS, ONE PASS A FRAME
-- ============================================================
local byKind = {}         -- kind -> { ctx -> true }
local dirtyKinds = {}     -- kind -> true (all units) or { unit -> true }
local pass = CreateFrame("Frame")
pass:Hide()
pass:SetScript("OnUpdate", function(self)
    self:Hide()
    local d = dirtyKinds
    dirtyKinds = {}
    for kind, units in pairs(d) do
        for ctx in pairs(byKind[kind] or {}) do
            local r = ctx.run
            if r and r.Update and ctx.alive then
                local ok, err = pcall(r.Update, ctx, units ~= true and units or nil)
                if not ok then E.Error(ctx.id, "trigger " .. ctx.index, err) end
            end
        end
    end
end)
local function Dirty(kind, unit)
    local cur = dirtyKinds[kind]
    if cur == true then
        -- already everything
    elseif type(unit) == "string" and unit ~= "" then
        cur = cur or {}
        cur[unit] = true
        dirtyKinds[kind] = cur
    else
        dirtyKinds[kind] = true
    end
    pass:Show()
end
G.Dirty = Dirty

-- a re-check at a moment (when a cooldown ends, a "time left" check flips)
local function At(ctx, when)
    local delay = when - GetTime()
    if delay <= 0 or delay > 3600 then return end
    ctx.atToken = (ctx.atToken or 0) + 1
    local token = ctx.atToken
    C_Timer.After(delay + 0.02, function()
        if ctx.alive and ctx.atToken == token and ctx.run.Update then pcall(ctx.run.Update, ctx) end
    end)
end
G.At = At

-- events that carry a unit first: mark that unit; others mark all
local UNIT_EVENTS = { UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_HEALTH_FREQUENT = true, UNIT_POWER_UPDATE = true,
    UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true, UNIT_DISPLAYPOWER = true, UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_DELAYED = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true, UNIT_SPELLCAST_INTERRUPTIBLE = true, UNIT_SPELLCAST_NOT_INTERRUPTIBLE = true,
    UNIT_LEVEL = true, UNIT_FACTION = true, UNIT_NAME_UPDATE = true, UNIT_FLAGS = true, UNIT_THREAT_LIST_UPDATE = true,
    UNIT_CONNECTION = true, INCOMING_RESURRECT_CHANGED = true, UNIT_HEAL_PREDICTION = true,
    UNIT_TARGET = false, NAME_PLATE_UNIT_ADDED = true, NAME_PLATE_UNIT_REMOVED = false }

local function Join(ctx, kind, events)
    byKind[kind] = byKind[kind] or {}
    byKind[kind][ctx] = true
    ctx.kinds = ctx.kinds or {}
    ctx.kinds[#ctx.kinds + 1] = kind
    for _, ev in ipairs(events or {}) do
        local unitArg = UNIT_EVENTS[ev]
        E.On(ev, "generic." .. kind, function(_, a1)
            if unitArg then Dirty(kind, a1) else Dirty(kind) end
        end)
    end
end

-- ============================================================
-- THE TWO SHAPES OF UPDATE
-- ============================================================
-- per unit: one state per unit for group / nameplate units, one state
-- otherwise. `only` = the units whose events fired (nil: all)
local function UpdateUnits(ctx, only)
    local tr = ctx.trigger
    local r = ctx.run
    local units, multi = Units(tr, ctx.def.defaultUnit)
    local changed = false
    local seen = {}
    for _, unit in ipairs(units) do
        local cid = multi and unit or ""
        seen[cid] = true
        if not only or only[unit] or not multi then
            local v = { unit = unit }
            local exists = unit ~= "" and UnitExists(unit) and true or false
            local ok = exists and r.Fetch(ctx, unit, v)
            if r.Missing and not exists then ok = r.Missing(ctx, unit, v) end
            local c = Judge(ctx, cid, v, ok and true or false)
            changed = changed or c
        end
    end
    -- units no longer in the list (left the group, plate went away)
    for cid, st in pairs(ctx.states) do
        if not seen[cid] and st.show then
            st.show, st.changed = false, true
            changed = true
        end
    end
    Done(ctx, changed)
end

-- one state
local function UpdateOne(ctx)
    local v = {}
    local ok = ctx.run.Fetch(ctx, nil, v)
    if ok == nil then ok = true end
    local c = Judge(ctx, "", v, ok and true or false)
    Done(ctx, c)
end

local function Unit(t) t.Update = UpdateUnits return t end
local function One(t) t.Update = UpdateOne return t end

-- ============================================================
-- UNIT KINDS
-- ============================================================
local UNIT_CHANGE = { "PLAYER_TARGET_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED", "UNIT_PET",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "RAID_TARGET_UPDATE", "UNIT_CONNECTION" }
local function With(list, ...)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e end
    for _, e in ipairs({ ... }) do out[#out + 1] = e end
    return out
end

RUN["Unit Characteristics"] = Unit({ kind = "unitchar",
    events = With(UNIT_CHANGE, "UNIT_LEVEL", "UNIT_FACTION", "UNIT_NAME_UPDATE", "UNIT_FLAGS", "PLAYER_FLAGS_CHANGED",
        "INCOMING_RESURRECT_CHANGED", "UNIT_TARGET", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"),
    Fetch = function(ctx, unit, v)
        UnitInfo(unit, v)
        v.unitisunit = unit
        v.classification = UnitClassification and UnitClassification(unit) or nil
        v.dead = UnitIsDeadOrGhost(unit) and true or false
        v.resurrectPending = UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit) and true or false
        v.hostility = Reaction(unit)
        v.character = UnitIsPlayer(unit) and "player" or "npc"
        v.level = UnitLevel(unit)
        v.attackable = UnitCanAttack("player", unit) and true or false
        v.inCombat = UnitAffectingCombat(unit) and true or false
        v.afk = UnitIsAFK and UnitIsAFK(unit) and true or false
        v.dnd = UnitIsDND and UnitIsDND(unit) and true or false
        return true
    end,
    State = function(ctx, st, v)
        st.unit, st.name, st.unitName, st.GUID = v.unit, v.name, v.name, UnitGUID(v.unit)
    end })

local function Secret(a, b)
    return issecretvalue and ((a ~= nil and issecretvalue(a)) or (b ~= nil and issecretvalue(b)))
end

RUN["Health"] = Unit({ kind = "health",
    events = With(UNIT_CHANGE, "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_HEAL_PREDICTION",
        "UNIT_NAME_UPDATE", "UNIT_FACTION"),
    Fetch = function(ctx, unit, v)
        local cur, max = UnitHealth(unit), UnitHealthMax(unit)
        if Secret(cur, max) then return false end
        cur, max = cur or 0, max or 0
        UnitInfo(unit, v)
        v.health, v.value, v.total = cur, cur, max
        v.percenthealth = max ~= 0 and cur / max * 100 or nil
        v.deficit, v.maxhealth = max - cur, max
        v.healprediction = UnitGetIncomingHeals and UnitGetIncomingHeals(unit) or 0
        if Secret(v.healprediction) then v.healprediction = 0 end   -- (WoW Forever)
        return true
    end,
    State = function(ctx, st, v)
        st.progressType, st.value, st.total = "static", v.value, v.total
        st.unit, st.name, st.unitName, st.GUID = v.unit, v.name, v.name, UnitGUID(v.unit)
    end })

local POWER_NAMES = { [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY", [4] = "COMBO_POINTS" }
RUN["Power"] = Unit({ kind = "power",
    events = With(UNIT_CHANGE, "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
        "PLAYER_TARGET_CHANGED", "UNIT_POWER_POINT_CHARGE"),
    Fetch = function(ctx, unit, v)
        local tr = ctx.trigger
        local primary = UnitPowerType(unit)
        local pt = tr.use_powertype and tonumber(tr.powertype) or primary
        local cur, max
        if pt == 4 and GetComboPoints and unit == "player" then cur, max = GetComboPoints("player", "target"), 5
        else cur, max = UnitPower(unit, pt), UnitPowerMax(unit, pt) end
        if Secret(cur, max) then return false end
        cur, max = cur or 0, max or 0
        UnitInfo(unit, v)
        v.powertype = pt
        v.requirePowerType = primary == pt
        v.power, v.value, v.total, v.stacks = cur, cur, max, cur
        v.percentpower = max ~= 0 and cur / max * 100 or nil
        v.deficit, v.maxpower = max - cur, max
        return true
    end,
    State = function(ctx, st, v)
        st.progressType, st.value, st.total = "static", v.value, v.total
        st.powerType = POWER_NAMES[v.powertype]
        st.unit, st.name, st.unitName, st.GUID = v.unit, v.name, v.name, UnitGUID(v.unit)
    end })

RUN["Cast"] = Unit({ kind = "cast",
    events = With(UNIT_CHANGE, "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_TARGET"),
    Fetch = function(ctx, unit, v)
        local name, _, icon, startMS, endMS, _, _, notInt, spellId = nil
        if UnitCastingInfo then name, _, icon, startMS, endMS, _, _, notInt, spellId = UnitCastingInfo(unit) end
        -- (WoW Forever hides casts in combat: a hidden one reads as none)
        if Secret(name, startMS) or Secret(endMS) then return false end
        local channel = false
        if not name and UnitChannelInfo then
            name, _, icon, startMS, endMS, _, notInt, spellId = UnitChannelInfo(unit)
            if Secret(name, startMS) or Secret(endMS) then return false end
            channel = name ~= nil
        end
        if Secret(notInt) then notInt = nil end   -- (WoW Forever: unknown, so interruptible)
        UnitInfo(unit, v)
        v.spell, v.spellName, v.spellId, v.icon = name, name, spellId, icon
        v.castType = name and (channel and "channel" or "cast") or nil
        v.interruptible = name and not notInt or false
        v.startTime, v.endTime = startMS, endMS
        v.expirationTime = endMS and endMS / 1000 or nil
        v.duration = (endMS and startMS) and (endMS - startMS) / 1000 or 0
        v.remaining = v.expirationTime and (v.expirationTime - GetTime()) or nil
        v.sourceUnit = unit
        v.sourceName, v.sourceRealm = v.name, v.realm
        v.destUnit = unit .. "target"
        v.destName, v.destRealm = NameRealm(unit .. "target")
        local tr = ctx.trigger
        if tr.use_remaining and not tr.use_inverse and v.expirationTime then
            local want = tonumber(type(tr.remaining) == "table" and tr.remaining[1] or tr.remaining)
            if want then At(ctx, v.expirationTime - want) end
        end
        return true
    end,
    Final = function(ctx, v, pass, ok)
        if not ok then return false end
        if ctx.trigger.use_inverse then return pass and v.spell == nil end
        return pass and v.spell ~= nil
    end,
    State = function(ctx, st, v)
        local tr = ctx.trigger
        st.unit, st.unitName, st.GUID = v.unit, v.name, UnitGUID(v.unit)
        st.name, st.icon = v.spell, v.icon
        st.progressType = "timed"
        st.duration, st.expirationTime = v.duration, v.expirationTime
        st.inverse = v.castType == "cast"
        st.autoHide = v.spell ~= nil
        st.destUnit = v.destUnit
    end })

RUN["Threat Situation"] = Unit({ kind = "threat",
    events = With(UNIT_CHANGE, "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED"),
    Fetch = function(ctx, unit, v)
        v.name = UnitName(unit)
        v.npcId = NpcId(UnitGUID(unit))
        local aggro, status, pct, raw, value
        local fn = UnitDetailedThreatSituation
        if fn then aggro, status, pct, raw, value = fn("player", unit) end
        -- (WoW Forever hides threat in a fight: no reading)
        if ns.Hidden(aggro, status, pct, raw, value) then return false end
        v.aggro, v.status = aggro and true or false, status
        v.threatpct, v.rawthreatpct, v.threatvalue = pct or 0, raw or 0, value or 0
        v.value = value or 0
        v.total = (value or 0) * 100 / ((pct and pct ~= 0) and pct or 1)
        return status ~= nil
    end,
    Missing = function(ctx, unit, v)
        if ctx.trigger.unit ~= "none" then return false end
        local status = UnitThreatSituation and UnitThreatSituation("player")
        if ns.Hidden(status) then return false end   -- (WoW Forever)
        v.status = status
        v.aggro = status == 2 or status == 3
        v.threatpct, v.rawthreatpct, v.threatvalue, v.value, v.total = 100, 100, 0, 0, 100
        return status ~= nil
    end,
    State = function(ctx, st, v)
        st.progressType, st.value, st.total = "static", v.value, v.total
        st.unit = v.unit ~= "none" and v.unit or nil
    end })

RUN["Conditions"] = One({ kind = "conditions",
    events = { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_UPDATE_RESTING",
        "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_FLAGS_CHANGED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
        "UNIT_FLAGS", "UNIT_PET", "PET_UPDATE", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "UPDATE_INSTANCE_INFO",
        "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" },
    Fetch = function(ctx, _, v)
        v.alwaystrue = true
        v.incombat = (UnitAffectingCombat("player") or InCombatLockdown()) and true or false
        v.pvpflagged = (UnitIsPVP and UnitIsPVP("player")) or (UnitIsPVPFreeForAll and UnitIsPVPFreeForAll("player")) or false
        v.alive = not UnitIsDeadOrGhost("player")
        v.vehicle = (UnitOnTaxi and UnitOnTaxi("player")) or (UnitInVehicle and UnitInVehicle("player")) or false
        v.resting = IsResting and IsResting() or false
        v.mounted = IsMounted and IsMounted() or false
        v.HasPet = UnitExists("pet") and not (UnitIsDead and UnitIsDead("pet")) or false
        if IsPlayerMoving then v.ismoving = IsPlayerMoving() and true or false
        elseif GetUnitSpeed then v.ismoving = (GetUnitSpeed("player") or 0) > 0 end
        v.afk = UnitIsAFK and UnitIsAFK("player") or false
        v.ingroup = GroupType()
        v.instance_size = InstanceType()
        return true
    end })

RUN["Stance/Form/Aura"] = One({ kind = "form",
    events = { "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_ENTERING_WORLD" },
    Fetch = function(ctx, _, v)
        v.form = GetShapeshiftForm and GetShapeshiftForm() or 0
        return true
    end,
    Final = function(ctx, v, pass)
        local tr = ctx.trigger
        if tr.use_inverse and type(tr.use_form) == "boolean" then return not pass end
        return pass
    end,
    State = function(ctx, st, v)
        local icon, name
        if v.form and v.form > 0 and GetShapeshiftFormInfo then
            local tex, _, _, spellId = GetShapeshiftFormInfo(v.form)
            icon = tex
            name = spellId and GetSpellInfo and GetSpellInfo(spellId) or nil
        end
        st.icon, st.name = icon, name
    end })

local function SpellPower()
    if not GetSpellBonusDamage then return 0 end
    local best = 0
    for school = 2, 7 do
        local d = GetSpellBonusDamage(school) or 0
        if Secret(d) then d = 0 end   -- (hidden on WoW Forever)
        best = math.max(best, d)
    end
    return best
end

RUN["Character Stats"] = One({ kind = "stats",
    events = { "UNIT_ATTACK_POWER", "UNIT_STATS", "UNIT_RANGED_ATTACK_POWER", "UNIT_RESISTANCES", "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_AURA", "COMBAT_RATING_UPDATE", "PLAYER_DAMAGE_DONE_MODS", "SPELL_POWER_CHANGED", "UNIT_DAMAGE",
        "UNIT_ATTACK_SPEED", "PLAYER_ENTERING_WORLD" },
    Fetch = function(ctx, _, v)
        -- (WoW Forever can hand your stats back hidden: each reads as 0)
        local function P(x) if Secret(x) then return 0 end return x end
        local function Stat(i) return UnitStat and P(select(2, UnitStat("player", i))) or 0 end
        v.strength, v.agility, v.stamina, v.intellect, v.spirit = Stat(1), Stat(2), Stat(3), Stat(4), Stat(5)
        v.criticalpercent = GetCritChance and P(GetCritChance()) or 0
        v.hastepercent = GetHaste and P(GetHaste()) or 0
        local base, pos, neg = UnitAttackPower("player")
        base, pos, neg = P(base), P(pos), P(neg)
        v.attackpower = (base or 0) + (pos or 0) + (neg or 0)
        v.spellpower = SpellPower()
        if GetUnitSpeed then
            local cur, run = GetUnitSpeed("player")
            v.movespeedpercent, v.runspeedpercent = (cur or 0) / 7 * 100, (run or 0) / 7 * 100
        end
        v.dodgepercent = GetDodgeChance and P(GetDodgeChance()) or 0
        v.parrypercent = GetParryChance and P(GetParryChance()) or 0
        v.blockpercent = GetBlockChance and P(GetBlockChance()) or 0
        v.blockvalue = GetShieldBlock and P(GetShieldBlock()) or 0
        v.armorrating = UnitArmor and P(select(2, UnitArmor("player"))) or 0
        for i, k in ipairs({ "holy", "fire", "nature", "frost", "shadow", "arcane" }) do
            v["resistance" .. k] = UnitResistance and P(select(2, UnitResistance("player", i))) or 0
        end
        return true
    end,
    Tick = function(ctx) return ctx.trigger.use_moveSpeed and 0.2 or nil end })

RUN["Location"] = One({ kind = "location",
    events = { "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_ENTERING_WORLD", "UPDATE_INSTANCE_INFO" },
    Fetch = function(ctx, _, v)
        v.zoneId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
        v.zonegroupId = v.zoneId and C_Map.GetMapGroupID and C_Map.GetMapGroupID(v.zoneId) or nil
        v.zone = GetRealZoneText and GetRealZoneText() or nil
        v.subzone = (GetMinimapZoneText and GetMinimapZoneText()) or (GetSubZoneText and GetSubZoneText()) or nil
        local name, _, _, _, _, _, _, instanceId = GetInstanceInfo()
        v.instance, v.instanceId = name, instanceId
        v.instanceSize = InstanceType()
        return true
    end })

RUN["Range Check"] = One({ kind = "range", events = { "PLAYER_TARGET_CHANGED", "UNIT_PET" }, tick = 0.2,
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local unit = tr.unit == "member" and tr.specificUnit or tr.unit or "target"
        v.unit = unit
        if not UnitExists(unit) then return false end
        v.minRange, v.maxRange = E.WA.GetRange(unit)
        return true
    end,
    State = function(ctx, st, v) st.unit = v.unit st.range = ctx.trigger.range end })

-- the swing timer: started by your own swings in the combat log
local swing = { main = {}, off = {}, ranged = {} }
G.swing = swing
RUN["Swing Timer"] = One({ kind = "swing", events = { "PLAYER_ENTERING_WORLD" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local hand = (tr.hand == "off" and "off") or (tr.hand == "ranged" and "ranged") or "main"
        local s = swing[hand]
        local now = GetTime()
        local on = s.expirationTime and s.expirationTime > now
        v.duration = on and s.duration or 0
        v.expirationTime = on and s.expirationTime or 0
        v.remaining = on and (s.expirationTime - now) or 0
        local slot = hand == "off" and 17 or hand == "ranged" and 18 or 16
        v.icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slot) or nil
        local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
        v.name = link and link:match("%[(.-)%]") or hand
        v.on = on
        if on then
            At(ctx, s.expirationTime)
            if tr.use_remaining then
                local want = tonumber(type(tr.remaining) == "table" and tr.remaining[1] or tr.remaining)
                if want then At(ctx, s.expirationTime - want) end
            end
        end
        return true
    end,
    Final = function(ctx, v, pass)
        if ctx.trigger.use_inverse then return pass and not v.on end
        return pass and v.on and true or false
    end,
    State = function(ctx, st, v)
        st.progressType, st.autoHide = "timed", v.on and true or false
        if not v.on then st.duration, st.expirationTime = 0, math.huge end
    end })
local function SwingStart(hand)
    local ms, os_ = UnitAttackSpeed("player")
    local dur = (hand == "off") and (os_ or ms) or ms
    if hand == "ranged" and UnitRangedDamage then dur = (UnitRangedDamage("player")) end
    if Secret(dur) then return end   -- (hidden on WoW Forever)
    if not dur then return end
    swing[hand].duration = dur
    swing[hand].expirationTime = GetTime() + dur
    Dirty("swing")
end
G.SwingStart = SwingStart

RUN["Talent Known"] = One({ kind = "talent", events = { "CHARACTER_POINTS_CHANGED", "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_ENTERING_WORLD" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local function Has(index)
            index = tonumber(index)
            if not index or not GetTalentInfo then return false end
            local tab, col = math.ceil(index / 20), (index - 1) % 20 + 1
            local name, icon, _, _, rank = GetTalentInfo(tab, col)
            if rank and rank > 0 then return true, name, icon, rank end
            return false, name, icon, rank
        end
        local active = true
        local t = type(tr.talent) == "table" and tr.talent or {}
        if tr.use_talent == true then
            local on, name, icon, rank = Has(t.single)
            active = on
            if on then v.name, v.icon, v.stacks = name, icon, rank end
        elseif tr.use_talent == false then
            active = false
            for index, want in pairs(type(t.multi) == "table" and t.multi or {}) do
                if want and not active then
                    local on, name, icon, rank = Has(index)
                    if on then active = true v.name, v.icon, v.stacks = name, icon, rank end
                end
            end
        end
        v.active = active
        return true
    end,
    Final = function(ctx, v, pass)
        local active = v.active
        if ctx.trigger.use_inverse then active = not active end
        return active
    end })

RUN["Experience"] = One({ kind = "xp", events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_ENTERING_WORLD" },
    Fetch = function(ctx, _, v)
        v.level = UnitLevel("player")
        v.currentXP = UnitXP and UnitXP("player") or 0
        v.totalXP = UnitXPMax and UnitXPMax("player") or 0
        v.value, v.total = v.currentXP, v.totalXP
        v.percentXP = v.total ~= 0 and v.value / v.total * 100 or nil
        v.restedXP = GetXPExhaustion and GetXPExhaustion() or 0
        v.percentrested = v.total ~= 0 and v.restedXP / v.total * 100 or nil
        return true
    end,
    State = function(ctx, st, v) st.progressType, st.value, st.total = "static", v.value, v.total end })

RUN["Faction Reputation"] = One({ kind = "rep", events = { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD", "COMBAT_TEXT_UPDATE" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local name, standing, minV, maxV, cur, atWar, factionID
        if tr.use_watched then
            if GetWatchedFactionInfo then name, standing, minV, maxV, cur, factionID = GetWatchedFactionInfo() end
        elseif tr.factionID and GetFactionInfoByID then
            local _
            name, _, standing, minV, maxV, cur, atWar = GetFactionInfoByID(tonumber(tr.factionID) or tr.factionID)
            factionID = tr.factionID
        end
        if not name then return false end
        v.name, v.factionID = name, factionID
        v.value, v.total = (cur or 0) - (minV or 0), (maxV or 0) - (minV or 0)
        v.percentRep = v.total ~= 0 and v.value / v.total * 100 or nil
        v.standingId = standing
        v.standing = standing and _G["FACTION_STANDING_LABEL" .. standing] or nil
        v.capped = standing == 8 and v.value >= v.total
        v.atWar = atWar and true or false
        return true
    end,
    State = function(ctx, st, v) st.progressType = "static" end })

RUN["Money"] = One({ kind = "money", events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD" },
    Fetch = function(ctx, _, v)
        local m = GetMoney and GetMoney() or 0
        v.money = m
        v.gold, v.silver, v.copper = math.floor(m / 10000), math.floor(m / 100) % 100, m % 100
        v.icon = "Interface\\MoneyFrame\\UI-GoldIcon"
        return true
    end })

local PET_MODES = { PET_MODE_AGGRESSIVE = "aggressive", PET_MODE_DEFENSIVE = "defensive", PET_MODE_PASSIVE = "passive",
    PET_MODE_ASSIST = "aggressive" }
RUN["Pet Behavior"] = One({ kind = "pet", events = { "PET_BAR_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD", "PET_UPDATE" },
    Fetch = function(ctx, _, v)
        if not UnitExists("pet") then return false end
        if GetPetActionInfo then
            for i = 1, 10 do
                local name, tex, _, active = GetPetActionInfo(i)
                if active and name and PET_MODES[name] then v.behavior, v.icon = PET_MODES[name], tex break end
            end
        end
        return true
    end,
    Final = function(ctx, v, pass, ok)
        local tr = ctx.trigger
        if not ok then return false end
        if tr.use_behavior and tr.behavior then
            if tr.use_inverse then return v.behavior ~= tr.behavior end
            return v.behavior == tr.behavior
        end
        return true
    end })

RUN["Crowd Controlled"] = One({ kind = "cc", events = { "LOSS_OF_CONTROL_UPDATE", "LOSS_OF_CONTROL_ADDED", "PLAYER_ENTERING_WORLD" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local L = C_LossOfControl
        local found
        if L and L.GetActiveLossOfControlDataCount and L.GetActiveLossOfControlData then
            for i = 1, L.GetActiveLossOfControlDataCount() or 0 do
                local d = L.GetActiveLossOfControlData(i)
                if d then
                    local ok = true
                    if tr.use_controlType and tr.controlType and d.locType ~= tr.controlType then ok = false end
                    if ok and tr.controlType == "SCHOOL_INTERRUPT" and tr.use_interruptSchool and tr.interruptSchool and bit then
                        ok = bit.band(d.lockoutSchool or 0, tonumber(tr.interruptSchool) or 0) > 0
                    end
                    if ok then found = d break end
                end
            end
        end
        v.found = found ~= nil
        if found then
            v.controlType, v.interruptSchool = found.locType, found.lockoutSchool
            v.name, v.spellName, v.spellId = found.displayText, found.spellID and GetSpellInfo and GetSpellInfo(found.spellID), found.spellID
            v.icon = found.iconTexture
            v.duration = found.duration
            v.expirationTime = found.startTime and found.duration and (found.startTime + found.duration) or nil
            v.lockoutSchool = found.lockoutSchool
            if v.expirationTime then At(ctx, v.expirationTime) end
        end
        return true
    end,
    Final = function(ctx, v)
        local inv = ctx.trigger.use_inverse and true or false
        return inv ~= (v.found and true or false)
    end,
    State = function(ctx, st, v) st.progressType = "timed" st.autoHide = v.found end })

-- ============================================================
-- SPELL KINDS
-- ============================================================
local function GCDInfo()
    if not GetSpellCooldown then return 0, 0 end
    local ok, start, dur = pcall(GetSpellCooldown, ns.GCDSpell and ns.GCDSpell() or 61304)
    if ok and start then return start, dur end
    return 0, 0
end
G.GCDInfo = GCDInfo

-- the cooldown of a spell, with the global cooldown told apart
local function SpellCD(spell, showgcd)
    local ok, start, dur, enabled = pcall(GetSpellCooldown, spell)
    if not ok or start == nil then return nil end
    start, dur = start or 0, dur or 0
    local gStart, gDur = GCDInfo()
    local isGCD = dur > 0 and gDur > 0 and math.abs(start - gStart) < 0.01 and math.abs(dur - gDur) < 0.01
    local gcdCooldown = false
    if isGCD and not showgcd then start, dur, gcdCooldown = 0, 0, true end
    if dur > 0 and start + dur <= GetTime() then start, dur = 0, 0 end
    return start, dur, gcdCooldown, enabled
end
G.SpellCD = SpellCD

local function Charges(spell)
    if not GetSpellCharges then return nil end
    local c, m, s, d = SafeCall(GetSpellCharges, spell)
    return c, m, s, d
end

local function Known(spell)
    if spell == nil then return false end
    if type(spell) == "number" then
        if IsSpellKnown and IsSpellKnown(spell) then return true end
        if IsPlayerSpell and IsPlayerSpell(spell) then return true end
        if IsSpellKnown and IsSpellKnown(spell, true) then return true end
        return GetSpellInfo and GetSpellInfo(spell) ~= nil and (GetSpellCooldown and select(1, SafeCall(GetSpellCooldown, spell)) ~= nil) or false
    end
    return GetSpellInfo and GetSpellInfo(spell) ~= nil or false
end

local function ChosenSpell(tr, key)
    key = key or "spellName"
    local s = SpellArg(tr[key])
    if s == nil then return nil end
    if tr["use_exact_" .. key] then return tonumber(s) or s end
    -- a plain number in a non-exact option names the spell
    if type(s) == "number" and GetSpellInfo then return GetSpellInfo(s) or s end
    return s
end

RUN["Cooldown Progress (Spell)"] = One({ kind = "spellcd",
    events = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_USABLE",
        "UNIT_POWER_FREQUENT", "PLAYER_TARGET_CHANGED", "LOSS_OF_CONTROL_UPDATE", "LOSS_OF_CONTROL_ADDED" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local spell = ChosenSpell(tr)
        if not spell then return false end
        local name, _, icon = nil, nil, nil
        if GetSpellInfo then name, _, icon = GetSpellInfo(spell) end
        v.name, v.icon = name or SpellName(spell), icon or SpellIcon(spell)
        v.effectiveSpellId = name and select(7, GetSpellInfo(spell)) or nil
        local start, dur, gcd = SpellCD(spell, tr.use_showgcd)
        if not tr.use_ignoreSpellKnown and not Known(spell) then start = nil end
        if start == nil and tr.use_ignoreSpellKnown then start, dur, gcd = 0, 0, false end
        local charges, maxCharges, cStart, cDur = Charges(spell)
        local count = GetSpellCount and SafeCall(GetSpellCount, spell) or nil
        local track = tr.track or "auto"
        if track ~= "cooldown" and charges and maxCharges and maxCharges > 1 and charges < maxCharges and cStart then
            if track == "charges" or charges > 0 then start, dur = cStart, cDur end
        end
        if charges == nil then charges = ((dur or 0) == 0 or gcd) and 1 or 0 end
        v.charges, v.maxCharges, v.spellCount = charges, maxCharges, count
        v.stacks = (maxCharges and maxCharges ~= 1 and charges) or (count and count > 0 and count) or nil
        v.startTime, v.duration, v.gcdCooldown = start, dur or 0, gcd
        v.expirationTime = start and dur and start + dur or nil
        v.onCooldown = start ~= nil and start > 0 and not gcd
        local usable, noMana = SafeCall(IsUsableSpell, spell)
        v.spellUsable, v.insufficientResources = usable and true or false, noMana and true or false
        local inRange = IsSpellInRange and name and SafeCall(IsSpellInRange, name, "target")
        v.spellInRange = inRange == 1
        v.remaining = (v.expirationTime and v.expirationTime > 0) and (v.expirationTime - GetTime()) or 0
        if v.onCooldown then
            At(ctx, v.expirationTime)
            if tr.use_remaining and tr.genericShowOn ~= "showOnReady" then
                local want = tonumber(type(tr.remaining) == "table" and tr.remaining[1] or tr.remaining)
                if want then At(ctx, v.expirationTime - want) end
            end
        end
        return true
    end,
    Final = function(ctx, v, pass, ok)
        if not ok then return false end
        return pass and ShowOn(ctx.trigger.genericShowOn, v.startTime, v.gcdCooldown)
    end,
    State = function(ctx, st, v)
        st.spellName = v.name
        st.progressType = "timed"
        if v.onCooldown or (v.startTime and v.startTime > 0) then
            st.duration, st.expirationTime = v.duration, v.expirationTime
        else
            st.duration, st.expirationTime = 0, math.huge
        end
    end })

RUN["Cooldown Ready (Spell)"] = { kind = "spellready", event = true,
    events = { "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED" },
    Update = function(ctx)
        local spell = ChosenSpell(ctx.trigger)
        if not spell then return end
        local start, dur = SpellCD(spell, false)
        local onCD = (dur or 0) > 0
        if ctx.wasOnCD and not onCD then
            local name, _, icon = GetSpellInfo(spell)
            Fire(ctx, { name = name or SpellName(spell), icon = icon or SpellIcon(spell) })
        end
        ctx.wasOnCD = onCD
        if onCD then At(ctx, start + dur) end
    end }

RUN["Charges Changed"] = { kind = "spellcharges", event = true,
    events = { "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_COOLDOWN" },
    Update = function(ctx)
        local tr = ctx.trigger
        local spell = ChosenSpell(tr)
        if not spell then return end
        local c = Charges(spell)
        if c == nil then return end
        if ctx.lastCharges and c ~= ctx.lastCharges then
            local v = { direction = c - ctx.lastCharges, charges = c, name = SpellName(spell), icon = SpellIcon(spell) }
            if P().Test(ctx.def, tr, v) then Fire(ctx, v) end
        end
        ctx.lastCharges = c
    end }

RUN["Global Cooldown"] = One({ kind = "gcd", events = { "SPELL_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN", "UNIT_SPELLCAST_SENT" },
    Fetch = function(ctx, _, v)
        local start, dur = GCDInfo()
        local on = dur > 0 and start + dur > GetTime()
        v.duration = on and dur or 0
        v.expirationTime = on and start + dur or 0
        if on then At(ctx, start + dur) end
        return true
    end,
    Final = function(ctx, v)
        if ctx.trigger.use_inverse then return v.duration == 0 end
        return v.duration > 0
    end,
    State = function(ctx, st, v)
        st.progressType = "timed"
        if v.duration == 0 then st.duration, st.expirationTime = 0, math.huge end
    end })

RUN["Action Usable"] = One({ kind = "usable",
    events = { "SPELL_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "UNIT_POWER_FREQUENT", "PLAYER_TARGET_CHANGED",
        "UNIT_AURA", "SPELLS_CHANGED", "ACTIONBAR_UPDATE_USABLE" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local spell = ChosenSpell(tr)
        if not spell then return false end
        local name, _, icon = nil, nil, nil
        if GetSpellInfo then name, _, icon = GetSpellInfo(spell) end
        v.spellName = spell
        v.name, v.icon = name or SpellName(spell), icon or SpellIcon(spell)
        local usable = SafeCall(IsUsableSpell, spell)
        local start, dur = SpellCD(spell, false)
        local ready = (dur or 0) == 0
        if tr.use_ignoreSpellCooldown then ready = true end
        local charges, maxCharges = Charges(spell)
        v.charges = charges or (ready and 1 or 0)
        v.spellCount = GetSpellCount and SafeCall(GetSpellCount, spell) or nil
        v.stacks = (maxCharges and maxCharges ~= 1 and charges) or nil
        local inRange = IsSpellInRange and name and SafeCall(IsSpellInRange, name, "target")
        v.spellInRange = inRange == 1
        local active = usable and ready and true or false
        if tr.use_targetRequired then active = active and UnitExists("target") and inRange ~= 0 end
        v.active = active
        if (dur or 0) > 0 then At(ctx, start + dur) end
        return true
    end,
    Final = function(ctx, v, pass, ok)
        if not ok then return false end
        local active = v.active
        if ctx.trigger.use_inverse then active = not active end
        return pass and active
    end,
    State = function(ctx, st, v)
        st.progressType, st.duration, st.expirationTime = "timed", 0, math.huge
    end })

RUN["Spell Known"] = One({ kind = "known", events = { "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "LEARNED_SPELL_IN_TAB", "UNIT_PET" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local spell = ChosenSpell(tr)
        if spell == nil then return false end
        local known
        if type(spell) == "number" then
            known = (IsSpellKnown and IsSpellKnown(spell, tr.use_petspell and true or false))
                or (not tr.use_petspell and IsPlayerSpell and IsPlayerSpell(spell)) or false
        else
            known = GetSpellInfo and GetSpellInfo(spell) ~= nil or false
        end
        v.active = known and true or false
        v.name, v.icon = SpellName(spell), SpellIcon(spell)
        return true
    end,
    Final = function(ctx, v, pass, ok)
        if not ok then return false end
        local a = v.active
        if ctx.trigger.use_inverse then a = not a end
        return pass and a
    end })

RUN["Queued Action"] = One({ kind = "queued", events = { "CURRENT_SPELL_CAST_CHANGED", "ACTIONBAR_UPDATE_STATE", "UNIT_SPELLCAST_SUCCEEDED",
        "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED" },
    Fetch = function(ctx, _, v)
        local spell = ChosenSpell(ctx.trigger)
        if not spell then return false end
        v.active = SafeCall(IsCurrentSpell, spell) and true or false
        v.name, v.icon = SpellName(spell), SpellIcon(spell)
        return true
    end,
    Final = function(ctx, v, pass, ok) return ok and pass and v.active end,
    State = function(ctx, st, v) st.name, st.icon = v.name, v.icon end })

RUN["Totem"] = { kind = "totem", events = { "PLAYER_TOTEM_UPDATE", "PLAYER_ENTERING_WORLD" },
    Update = function(ctx)
        local tr = ctx.trigger
        local def = ctx.def
        local now = GetTime()
        local hits = {}
        local slots = {}
        if tr.use_totemType and tonumber(tr.totemType) then slots = { tonumber(tr.totemType) }
        else for i = 1, (MAX_TOTEMS or 4) do slots[#slots + 1] = i end end
        for _, slot in ipairs(slots) do
            local have, name, start, dur, icon = nil
            if GetTotemInfo then have, name, start, dur, icon = GetTotemInfo(slot) end
            if have and name and name ~= "" then
                local v = { totemType = slot, totemName = name, icon = icon, duration = dur,
                    expirationTime = (start or 0) + (dur or 0), remaining = (start or 0) + (dur or 0) - now }
                local ok = P().Test(def, tr, v)
                if ok then hits[#hits + 1] = v end
                if v.expirationTime > now then At(ctx, v.expirationTime) end
            end
        end
        local changed = false
        local keep = {}
        if tr.use_inverse then
            if #hits == 0 then
                keep[""] = true
                changed = SetState(ctx, "", true, { totemType = slots[1] }) or changed
                local st = ctx.states[""]
                st.progressType, st.duration, st.expirationTime, st.autoHide = "timed", 0, math.huge, false
                st.name = tr.totemName
            end
        elseif tr.use_clones and not tr.use_totemType and not tr.use_inverse then
            for _, v in ipairs(hits) do
                local cid = tostring(v.totemType)
                keep[cid] = true
                changed = SetState(ctx, cid, true, v) or changed
            end
        elseif hits[1] then
            keep[""] = true
            changed = SetState(ctx, "", true, hits[1]) or changed
        end
        for cid, st in pairs(ctx.states) do
            if not keep[cid] and st.show then st.show, st.changed = false, true changed = true end
        end
        Done(ctx, changed)
    end,
    State = function(ctx, st, v)
        if v.totemName then
            st.name, st.totemName, st.icon = v.totemName, v.totemName, v.icon
            st.progressType, st.duration, st.expirationTime, st.autoHide = "timed", v.duration, v.expirationTime, true
            st.totemType = v.totemType
        end
    end }

-- ============================================================
-- ITEM KINDS
-- ============================================================
local function ItemCooldown(item)
    local fn = (C_Container and C_Container.GetItemCooldown) or _G.GetItemCooldown
    if not fn then return 0, 0, 1 end
    local id = ItemId(item)
    if not id then return 0, 0, 1 end
    local ok, start, dur, enabled = pcall(fn, id)
    if not ok then return 0, 0, 1 end
    return start or 0, dur or 0, enabled
end

local function ChosenItem(tr)
    local item = ItemArg(tr.itemName)
    if item == nil then return nil end
    if tr.use_exact_itemName then return tonumber(item) or item end
    return item
end

RUN["Item Count"] = One({ kind = "itemcount", events = { "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "PLAYER_ENTERING_WORLD", "ITEM_PUSH" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local item = ChosenItem(tr)
        if not item then return false end
        local count = SafeCall(GetItemCount, item, tr.use_includeBank and true or false, tr.use_includeCharges and true or false) or 0
        v.count, v.stacks, v.value = count, count, count
        v.total = math.max(count, 1)
        v.itemId = ItemId(item)
        v.name = ItemName(item)
        v.icon = ItemIcon(item)
        return true
    end,
    State = function(ctx, st, v) st.progressType = "static" end })

local function ItemCD(slot)
    return One({ kind = slot and "slotcd" or "itemcd",
        events = { "BAG_UPDATE_COOLDOWN", "PLAYER_EQUIPMENT_CHANGED", "SPELL_UPDATE_COOLDOWN", "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED" },
        Fetch = function(ctx, _, v)
            local tr = ctx.trigger
            local start, dur, enabled
            if slot then
                local s = tonumber(tr.itemSlot) or 13
                start, dur, enabled = GetInventoryItemCooldown("player", s)
                if Secret(start, dur) or Secret(enabled) then start, dur, enabled = 0, 0, 1 end   -- (WoW Forever)
                v.icon = GetInventoryItemTexture("player", s)
                local link = GetInventoryItemLink("player", s)
                v.name = link and link:match("%[(.-)%]") or nil
                v.itemId = GetInventoryItemID and GetInventoryItemID("player", s) or (link and tonumber(link:match("item:(%d+)")))
                v.testForCooldown = enabled == 1
            else
                local item = ItemArg(tr.itemName)
                if not item then return false end
                start, dur, enabled = ItemCooldown(item)
                v.icon, v.name, v.itemId = ItemIcon(item), ItemName(item), ItemId(item)
            end
            start, dur = start or 0, dur or 0
            local gStart, gDur = GCDInfo()
            local gcd = false
            if dur > 0 and dur <= 1.5 and math.abs(start - gStart) < 0.01 and math.abs(dur - gDur) < 0.01 then
                if not tr.use_showgcd then start, dur, gcd = 0, 0, true end
            end
            if dur > 0 and start + dur <= GetTime() then start, dur = 0, 0 end
            v.startTime, v.duration, v.gcdCooldown, v.enabled = start, dur, gcd, enabled
            v.expirationTime = start + dur
            v.onCooldown = start > 0 and not gcd
            v.remaining = v.onCooldown and (v.expirationTime - GetTime()) or 0
            if v.onCooldown then
                At(ctx, v.expirationTime)
                if tr.use_remaining and tr.genericShowOn ~= "showOnReady" then
                    local want = tonumber(type(tr.remaining) == "table" and tr.remaining[1] or tr.remaining)
                    if want then At(ctx, v.expirationTime - want) end
                end
            end
            return true
        end,
        Final = function(ctx, v, pass, ok)
            if not ok then return false end
            local mode = ctx.trigger.genericShowOn or "showOnCooldown"
            local show
            if mode == "showAlways" then show = true
            elseif mode == "showOnReady" then show = (v.startTime == 0 and (slot or v.enabled ~= 0)) or v.gcdCooldown
            else show = v.startTime > 0 and not v.gcdCooldown end
            return pass and show and true or false
        end,
        State = function(ctx, st, v)
            st.progressType = "timed"
            if not v.onCooldown then st.duration, st.expirationTime = 0, math.huge end
        end })
end
RUN["Cooldown Progress (Item)"] = ItemCD(false)
RUN["Cooldown Progress (Equipment Slot)"] = ItemCD(true)

local function ReadyKind(slot)
    return { kind = slot and "slotready" or "itemready", event = true,
        events = { "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "PLAYER_EQUIPMENT_CHANGED" },
        Update = function(ctx)
            local tr = ctx.trigger
            local start, dur, icon, name, id
            if slot then
                local s = tonumber(tr.itemSlot) or 13
                start, dur = GetInventoryItemCooldown("player", s)
                if Secret(start, dur) then start, dur = 0, 0 end   -- (WoW Forever)
                icon = GetInventoryItemTexture("player", s)
                local link = GetInventoryItemLink("player", s)
                name = link and link:match("%[(.-)%]") or nil
                id = link and tonumber(link:match("item:(%d+)"))
            else
                local item = ItemArg(tr.itemName)
                if not item then return end
                start, dur = ItemCooldown(item)
                icon, name, id = ItemIcon(item), ItemName(item), ItemId(item)
            end
            start, dur = start or 0, dur or 0
            local onCD = dur > 1.5 and start + dur > GetTime()
            if ctx.wasOnCD and not onCD then Fire(ctx, { name = name, icon = icon, itemId = id }) end
            ctx.wasOnCD = onCD
            if onCD then At(ctx, start + dur) end
        end }
end
RUN["Cooldown Ready (Item)"] = ReadyKind(false)
RUN["Cooldown Ready (Equipment Slot)"] = ReadyKind(true)

RUN["Item Equipped"] = One({ kind = "equipped", events = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_INVENTORY_CHANGED" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local item = ItemArg(tr.itemName)
        if not item then return false end
        local id = ItemId(item)
        local on
        if tr.use_itemSlot and tr.itemSlot then
            local worn = GetInventoryItemID and GetInventoryItemID("player", tonumber(tr.itemSlot) or 0)
            on = worn ~= nil and (worn == id or ItemName(worn) == ItemName(item))
        else
            on = IsEquippedItem and SafeCall(IsEquippedItem, item) or false
        end
        v.equipped = on and true or false
        v.itemId, v.name, v.icon = id, ItemName(item), ItemIcon(item)
        return true
    end,
    Final = function(ctx, v, pass, ok)
        if not ok then return false end
        if ctx.trigger.use_inverse then return not v.equipped end
        return v.equipped
    end })

RUN["Item Type Equipped"] = One({ kind = "itemtype", events = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local slots = (tr.use_itemSlot and tonumber(tr.itemSlot)) and { tonumber(tr.itemSlot) } or { 16, 17, 18 }
        local types = {}
        for _, s in ipairs(slots) do
            local id = GetInventoryItemID and GetInventoryItemID("player", s)
            if id and GetItemInfoInstant then
                local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(id)
                if classID and subclassID then types[classID * 256 + subclassID] = true end
            end
        end
        v.types = types
        return true
    end })

-- bonus ids in an item link: item:id:enchant:g1:g2:g3:g4:suffix:unique:level:spec:upgrade:diff:numBonus:b1...
local function BonusIds(link)
    local out = {}
    local body = link and link:match("item:([%-%d:]+)")
    if not body then return out end
    local parts = {}
    for p in (body .. ":"):gmatch("([^:]*):") do parts[#parts + 1] = p end
    local n = tonumber(parts[13])
    if n then for i = 1, n do local b = tonumber(parts[13 + i]) if b then out[b] = true end end end
    return out
end
RUN["Item Bonus Id Equipped"] = One({ kind = "bonusid", events = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local want = {}
        for p in tostring(tr.itemBonusId or ""):gmatch("[^,%s]+") do if tonumber(p) then want[tonumber(p)] = true end end
        local slots = (tr.use_itemSlot and tonumber(tr.itemSlot)) and { tonumber(tr.itemSlot) } or { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
        for _, s in ipairs(slots) do
            local link = GetInventoryItemLink and GetInventoryItemLink("player", s)
            for b in pairs(BonusIds(link)) do
                if want[b] then
                    v.found, v.itemBonusId, v.itemSlot = true, b, s
                    v.name, v.itemId = link:match("%[(.-)%]"), tonumber(link:match("item:(%d+)"))
                    v.icon = GetInventoryItemTexture("player", s)
                    break
                end
            end
            if v.found then break end
        end
        return true
    end,
    Final = function(ctx, v)
        return (ctx.trigger.use_inverse and true or false) ~= (v.found and true or false)
    end })

RUN["Item Set"] = One({ kind = "itemset", events = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local setId = tonumber(tr.itemSetId)
        if not setId then return false end
        local n = 0
        for s = 1, 19 do
            local id = GetInventoryItemID and GetInventoryItemID("player", s)
            if id and GetItemInfo then
                local set = select(16, GetItemInfo(id))
                if set == setId then n = n + 1 end
            end
        end
        v.itemSetId = setId
        v.equipped, v.value = n, n
        ctx.setMax = math.max(ctx.setMax or 0, n)
        v.total = (GetNumItemSetItems and GetNumItemSetItems(setId)) or math.max(ctx.setMax, 1)
        v.name = GetItemSetInfo and GetItemSetInfo(setId) or nil
        return true
    end,
    State = function(ctx, st, v) st.progressType = "static" end })

-- the enchant of a weapon, by id or by the name in its tooltip
local enchantTip
local function EnchantName(slot)
    if not CreateFrame then return nil end
    if not enchantTip then
        enchantTip = CreateFrame("GameTooltip", "ZacUIAurasEnchantTip", nil, "GameTooltipTemplate")
    end
    if not (enchantTip and enchantTip.SetInventoryItem and enchantTip.SetOwner) then return nil end
    enchantTip:SetOwner(UIParent, "ANCHOR_NONE")
    enchantTip:ClearLines()
    enchantTip:SetInventoryItem("player", slot)
    for i = 1, (enchantTip.NumLines and enchantTip:NumLines() or 0) do
        local fs = _G["ZacUIAurasEnchantTipTextLeft" .. i]
        local text = fs and fs.GetText and fs:GetText()
        local name = text and text:match("^(.-) %(%d+ [^)]+%)$")
        if name then return name end
    end
    return nil
end

RUN["Weapon Enchant"] = One({ kind = "tench", tick = 1, events = { "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" },
    Fetch = function(ctx, _, v)
        local tr = ctx.trigger
        local weapon = tr.weapon or "main"
        local has, exp, charges, id
        if GetWeaponEnchantInfo then
            local a1, a2, a3, a4, b1, b2, b3, b4, c1, c2, c3, c4 = GetWeaponEnchantInfo()
            if weapon == "off" then has, exp, charges, id = b1, b2, b3, b4
            elseif weapon == "ranged" then has, exp, charges, id = c1, c2, c3, c4
            else has, exp, charges, id = a1, a2, a3, a4 end
        end
        local slot = weapon == "off" and 17 or weapon == "ranged" and 18 or 16
        local found = has and true or false
        local name
        if found then name = EnchantName(slot) end
        local want = tr.use_enchant and tr.enchant ~= nil and tr.enchant ~= "" and tostring(tr.enchant) or nil
        if found and want then
            found = (tonumber(want) and tonumber(want) == id) or (name ~= nil and name == want) or false
        end
        v.found, v.enchanted = found, found
        v.enchantID, v.name = id, name
        v.icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slot) or nil
        v.stacks = charges
        if found and exp then
            local rem = exp / 1000
            ctx.tenchMax = ctx.tenchMax or {}
            local key = tostring(id or name or weapon)
            if (ctx.tenchMax[key] or 0) < rem then ctx.tenchMax[key] = rem end
            v.duration, v.expirationTime, v.remaining = ctx.tenchMax[key], GetTime() + rem, rem
        else
            v.remaining = 0
        end
        return true
    end,
    Final = function(ctx, v, pass, ok)
        if not ok then return false end
        local mode = ctx.trigger.showOn or "showOnActive"
        if mode == "showAlways" then return true end
        if mode == "showOnMissing" then return not v.found end
        return pass and v.found
    end,
    State = function(ctx, st, v)
        if v.found and v.duration then st.progressType = "timed"
        else st.progressType, st.duration, st.expirationTime = "timed", 0, math.huge end
    end })

-- ============================================================
-- EVENT KINDS (they show for a moment when the event happens)
-- ============================================================
local ALL_CHAT = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE",
    "CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE", "CHAT_MSG_GUILD",
    "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_PARTY", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_MONSTER_YELL",
    "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_BOSS_EMOTE", "CHAT_MSG_RAID_BOSS_WHISPER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_SAY", "CHAT_MSG_WHISPER",
    "CHAT_MSG_YELL", "CHAT_MSG_SYSTEM", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_LOOT" }
local LEADER = { CHAT_MSG_INSTANCE_CHAT = "CHAT_MSG_INSTANCE_CHAT_LEADER", CHAT_MSG_PARTY = "CHAT_MSG_PARTY_LEADER",
    CHAT_MSG_RAID = "CHAT_MSG_RAID_LEADER" }
-- a leader's line counts as the channel it was said in
local FOLD = { CHAT_MSG_INSTANCE_CHAT_LEADER = "CHAT_MSG_INSTANCE_CHAT", CHAT_MSG_PARTY_LEADER = "CHAT_MSG_PARTY",
    CHAT_MSG_RAID_LEADER = "CHAT_MSG_RAID", CHAT_MSG_TEXT_EMOTE = "CHAT_MSG_EMOTE" }

local function Sub(ctx, events, fn)
    ctx.subs = ctx.subs or {}
    for _, ev in ipairs(events) do
        ctx.subs[#ctx.subs + 1] = ev
        E.On(ev, ctx.key, function(event, ...)
            if ctx.alive then fn(event, ...) end
        end)
    end
end

RUN["Chat Message"] = { event = true, Add = function(ctx)
    local tr = ctx.trigger
    local events
    if tr.use_messageType and tr.messageType then
        events = { tr.messageType }
        if LEADER[tr.messageType] then events[2] = LEADER[tr.messageType] end
        if tr.messageType == "CHAT_MSG_EMOTE" then events[#events + 1] = "CHAT_MSG_TEXT_EMOTE" end
    else
        events = ALL_CHAT
    end
    Sub(ctx, events, function(event, msg, sender, _, _, dest, ...)
        local guid = select(7, ...)
        local v = { messageType = FOLD[event] or event, message = msg, sourceName = sender, destName = dest, sourceGUID = guid }
        if not P().Test(ctx.def, tr, v) then return end
        Fire(ctx, v, tr.use_cloneId and true or nil)
    end)
end,
    State = function(ctx, st, v) st.messageType = v.messageType end }

RUN["Spell Cast Succeeded"] = { event = true, Add = function(ctx)
    local tr = ctx.trigger
    Sub(ctx, { "UNIT_SPELLCAST_SUCCEEDED" }, function(_, unit, castGUID, spellId)
        if not unit then return end
        local wantUnit = tr.unit
        if wantUnit and wantUnit ~= "" then
            local units, multi = Units(tr)
            local hit = false
            for _, u in ipairs(units) do if u == unit or (UnitIsUnit and SafeCall(UnitIsUnit, u, unit)) then hit = true break end end
            if not hit then return end
        end
        local name, _, icon = nil, nil, nil
        if spellId and GetSpellInfo then name, _, icon = GetSpellInfo(spellId) end
        local v = { unit = unit, spellId = spellId, spellName = name, name = name, icon = icon }
        if not P().Test(ctx.def, tr, v) then return end
        Fire(ctx, v, unit)
    end)
end,
    State = function(ctx, st, v) st.unit = v.unit end }

RUN["Ready Check"] = { event = true, Add = function(ctx)
    Sub(ctx, { "READY_CHECK" }, function() Fire(ctx, {}) end)
end }

RUN["Combat Events"] = { event = true, Add = function(ctx)
    local tr = ctx.trigger
    Sub(ctx, { "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }, function(event)
        if event ~= (tr.eventtype or "PLAYER_REGEN_DISABLED") then return end
        Fire(ctx, { eventtype = event })
    end)
end }

RUN["Encounter Events"] = { event = true, Add = function(ctx)
    local tr = ctx.trigger
    Sub(ctx, { "ENCOUNTER_START", "ENCOUNTER_END" }, function(event, encounterId, encounterName, difficultyId, size, success)
        if event ~= (tr.eventtype or "ENCOUNTER_START") then return end
        local v = { eventtype = event, encounterId = encounterId, encounterName = encounterName, difficulty = Difficulty(),
            success = success == 1, name = encounterName }
        if not P().Test(ctx.def, tr, v) then return end
        Fire(ctx, v)
    end)
end,
    State = function(ctx, st, v) st.name = v.encounterName end }

RUN["GTFO"] = { event = true, Add = function(ctx)
    local tr = ctx.trigger
    Sub(ctx, { "GTFO_DISPLAY" }, function(_, alertType)
        local v = { alertType = alertType }
        if not P().Test(ctx.def, tr, v) then return end
        Fire(ctx, v)
    end)
end }

-- ============================================================
-- THE COMBAT LOG (Classic Era only; absent on Forever)
-- ============================================================
-- what follows the eleven common values, by event
local PREFIX_ARGS = { SPELL = { "spellId", "spellName", "spellSchool" }, RANGE = { "spellId", "spellName", "spellSchool" },
    SPELL_PERIODIC = { "spellId", "spellName", "spellSchool" }, SPELL_BUILDING = { "spellId", "spellName", "spellSchool" },
    DAMAGE_SHIELD = { "spellId", "spellName", "spellSchool" }, DAMAGE_SPLIT = { "spellId", "spellName", "spellSchool" },
    DAMAGE_SHIELD_MISSED = { "spellId", "spellName", "spellSchool" }, ENVIRONMENTAL = { "environmentalType" }, SWING = {} }
local DAMAGE = { "amount", "overkill", "school", "resisted", "blocked", "absorbed", "critical", "glancing", "crushing", "isOffHand" }
local SUFFIX_ARGS = {
    _DAMAGE = DAMAGE,
    _MISSED = { "missType", "isOffHand", "amountMissed", "criticalMissed" },
    _HEAL = { "amount", "overhealing", "absorbed", "critical" },
    _ABSORBED = {},
    _ENERGIZE = { "amount", "overEnergize", "powerType" },
    _DRAIN = { "amount", "powerType", "extraAmount" },
    _LEECH = { "amount", "powerType", "extraAmount" },
    _INTERRUPT = { "extraSpellId", "extraSpellName", "extraSchool" },
    _DISPEL = { "extraSpellId", "extraSpellName", "extraSchool", "auraType" },
    _DISPEL_FAILED = { "extraSpellId", "extraSpellName", "extraSchool" },
    _STOLEN = { "extraSpellId", "extraSpellName", "extraSchool", "auraType" },
    _EXTRA_ATTACKS = { "number" },
    _AURA_APPLIED = { "auraType", "amount" }, _AURA_REMOVED = { "auraType", "amount" },
    _AURA_APPLIED_DOSE = { "auraType", "number" }, _AURA_REMOVED_DOSE = { "auraType", "number" },
    _AURA_REFRESH = { "auraType", "amount" }, _AURA_BROKEN = { "auraType" },
    _AURA_BROKEN_SPELL = { "extraSpellId", "extraSpellName", "extraSchool", "auraType" },
    _CAST_FAILED = { "failedType" },
}
local NO_SUFFIX_DAMAGE = { DAMAGE_SHIELD = DAMAGE, DAMAGE_SPLIT = DAMAGE,
    DAMAGE_SHIELD_MISSED = SUFFIX_ARGS._MISSED }
G.PREFIX_ARGS, G.SUFFIX_ARGS = PREFIX_ARGS, SUFFIX_ARGS

-- the values of one combat log event, by name
local function ReadLog(prefix, suffix, ...)
    local v = {}
    local ts, sub, hide, sGUID, sName, sFlags, sRaid, dGUID, dName, dFlags, dRaid = ...
    v.timestamp, v.subevent = ts, sub
    v.sourceGUID, v.sourceName, v.sourceFlags, v.sourceRaidFlags = sGUID, sName, sFlags, sRaid
    v.destGUID, v.destName, v.destFlags, v.destRaidFlags = dGUID, dName, dFlags, dRaid
    local i = 12
    for _, k in ipairs(PREFIX_ARGS[prefix] or {}) do v[k] = select(i, ...) i = i + 1 end
    local list = (suffix and suffix ~= "" and SUFFIX_ARGS[suffix]) or NO_SUFFIX_DAMAGE[prefix] or {}
    if suffix == "_ABSORBED" then
        -- either the attacker's spell (8 more values) or a swing (5)
        local n = select("#", ...)
        local base = i
        if n - base + 1 >= 12 then base = base + 3 end
        v.extraSpellId, v.extraSpellName = select(base + 4, ...), select(base + 5, ...)
        v.amount = select(base + 7, ...)
    else
        for _, k in ipairs(list) do v[k] = select(i, ...) i = i + 1 end
    end
    v.sourceNpcId, v.destNpcId = NpcId(sGUID), NpcId(dGUID)
    local band = _G.bit and _G.bit.band
    local function Mark(f)
        if not (band and f) then return 0 end
        for m = 1, 8 do if band(f, 2 ^ (m - 1)) ~= 0 then return m end end
        return 0
    end
    v.sourceRaidMarkIndex, v.destRaidMarkIndex = Mark(sRaid), Mark(dRaid)
    v.sourceRaidMark = v.sourceRaidMarkIndex > 0 and ("{rt" .. v.sourceRaidMarkIndex .. "}") or ""
    v.destRaidMark = v.destRaidMarkIndex > 0 and ("{rt" .. v.destRaidMarkIndex .. "}") or ""
    v.sourceUnitGUID, v.destUnitGUID = sGUID, dGUID
    return v
end
G.ReadLog = ReadLog

-- the combat log's affiliation / reaction / kind flags
local function Band(a, b) return _G.bit and _G.bit.band(a or 0, b) or 0 end
local function FlagsCheck(flags, want)
    if type(flags) ~= "number" then return false end
    if want == "Mine" then return Band(flags, 0x1) > 0
    elseif want == "InGroup" then return Band(flags, 0x8) == 0
    elseif want == "InParty" then return Band(flags, 0x2) > 0
    elseif want == "NotInGroup" then return Band(flags, 0x8) > 0 end
    return true
end
local function ReactionCheck(flags, want)
    if type(flags) ~= "number" then return false end
    if want == "Hostile" then return Band(flags, 64) ~= 0
    elseif want == "Neutral" then return Band(flags, 32) ~= 0
    elseif want == "Friendly" then return Band(flags, 16) ~= 0 end
    return true
end
local KIND_BITS = { Object = 16384, Guardian = 8192, Pet = 4096, NPC = 2048, Player = 1024 }
local function KindCheck(flags, want)
    if type(flags) ~= "number" or not KIND_BITS[want] then return false end
    return Band(flags, KIND_BITS[want]) ~= 0
end
local function RaidFlagCheck(flags, want)
    want = tonumber(want)
    if not want or not flags then return false end
    if want == 0 then return Band(flags, 0xFF) == 0 end
    if want == 9 then return Band(flags, 0xFF) > 0 end
    return Band(flags, 2 ^ (want - 1)) > 0
end
G.FlagsCheck, G.ReactionCheck, G.KindCheck, G.RaidFlagCheck = FlagsCheck, ReactionCheck, KindCheck, RaidFlagCheck

-- the combat log fields whose check is not a plain comparison
local function LogTests(def)
    if def.logTests then return end
    def.logTests = true
    for _, f in ipairs(def.fields) do
        local n = f.name
        if n == "sourceFlags" or n == "destFlags" then
            f.test = function(v, want) return FlagsCheck(v[n], want) end
        elseif n == "sourceFlags2" then f.test = function(v, want) return ReactionCheck(v.sourceFlags, want) end
        elseif n == "destFlags2" then f.test = function(v, want) return ReactionCheck(v.destFlags, want) end
        elseif n == "sourceFlags3" then f.test = function(v, want) return KindCheck(v.sourceFlags, want) end
        elseif n == "destFlags3" then f.test = function(v, want) return KindCheck(v.destFlags, want) end
        elseif n == "sourceRaidFlags" or n == "destRaidFlags" then
            f.test = function(v, want) return RaidFlagCheck(v[n], want) end
        end
    end
end

RUN["Combat Log"] = { event = true, Add = function(ctx)
    if E.FOREVER then return end
    local tr = ctx.trigger
    local def = ctx.def
    LogTests(def)
    local prefix = tr.subeventPrefix or ""
    local suffix = tr.subeventSuffix or ""
    if not P().values.subevent_actual_prefix_types[prefix] then suffix = "" end
    local want = prefix .. suffix
    Sub(ctx, { "COMBAT_LOG_EVENT_UNFILTERED" }, function(_, ...)
        local sub = select(2, ...)
        if sub ~= want then return end
        local v = ReadLog(prefix, suffix, ...)
        if not P().Test(def, tr, v) then return end
        v.icon = v.spellId and v.spellId ~= 0 and SpellIcon(v.spellId) or (v.spellName and SpellIcon(v.spellName)) or nil
        v.sourceUnit = tr.use_sourceUnit and tr.sourceUnit or nil
        v.destUnit = tr.use_destUnit and tr.destUnit or nil
        Fire(ctx, v, tr.use_cloneId and true or nil)
    end)
end,
    State = function(ctx, st, v)
        st.name = v.spellName or v.sourceName
        st.spellName = v.spellName
        st.sourceUnit, st.destUnit = v.sourceUnit, v.destUnit
        st.icon = v.icon
        st.count = v.count
    end }

-- your own swings start the swing timer
if not E.FOREVER then
    E.On("COMBAT_LOG_EVENT_UNFILTERED", "generic.swing", function(_, ...)
        local _, sub, _, sGUID = ...
        if sGUID ~= UnitGUID("player") then return end
        if sub == "SWING_DAMAGE" then
            local offhand = select(21, ...)
            SwingStart(offhand and "off" or "main")
        elseif sub == "SWING_MISSED" then
            local offhand = select(13, ...)
            SwingStart(offhand and "off" or "main")
        elseif sub == "SPELL_CAST_SUCCESS" or sub == "RANGE_DAMAGE" then
            local name = select(13, ...)
            if name == "Auto Shot" or name == "Shoot" then SwingStart("ranged") end
        end
    end)
end

-- ============================================================
-- THE HANDLERS (one per category, dispatching on trigger.event)
-- ============================================================
local function Handler()
    local h = {}
    function h.Add(ctx)
        local tr = ctx.trigger
        local protos = P()
        local event = tr.event
        local def = protos and protos.Get(event)
        local run = RUN[event]
        if not (def and run) then
            E.Error(ctx.id, "trigger " .. ctx.index, "'" .. tostring(event) .. "' is not supported yet")
            return
        end
        ctx.def, ctx.run = def, run
        ctx.alive = true
        ctx.counted = 0
        if run.kind then Join(ctx, run.kind, run.events) end
        local tick = run.tick or (run.Tick and run.Tick(ctx))
        if tick then
            ctx.ticker = C_Timer.NewTicker(tick, function() if ctx.alive and run.Update then pcall(run.Update, ctx) end end)
        end
        if run.Add then run.Add(ctx)
        elseif run.Update then
            if run.event then pcall(run.Update, ctx) else run.Update(ctx) end
        end
    end
    function h.Remove(ctx)
        ctx.alive = false
        for _, kind in ipairs(ctx.kinds or {}) do
            if byKind[kind] then byKind[kind][ctx] = nil end
        end
        if ctx.ticker then ctx.ticker:Cancel() ctx.ticker = nil end
    end
    return h
end

for _, t in ipairs({ "unit", "spell", "item", "event", "combatlog", "status", "addons" }) do
    E.TriggerTypes[t] = Handler()
end
