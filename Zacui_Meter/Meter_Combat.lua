-- Meter_Combat - the meter's data model: actors, spells, combat
-- segments, the activity-time clock, pet ownership and the death log.
-- Part of ZacUI; load order is set by the TOC.
--
-- HOW THIS MIRRORS DETAILS, DELIBERATELY. The numbers a meter shows are
-- the product of dozens of small policy decisions - when a combat
-- starts, when idle time stops counting, whether an absorbed hit is
-- damage - and two meters that decide differently will disagree in
-- front of the raid. So every policy here is the one Details ships on
-- Classic, with the same constants:
--   * actors are keyed by NAME, with a GUID hot-cache in the parser
--   * new actors seed their totals with a tiny random epsilon
--     (math.random(1000,9000)/1000000) so sorting never sees exact ties
--   * activity time is unix-second resolution, pauses after 10 idle
--     seconds (3 in pvp) and reads with a 10-second floor (3 pvp)
--   * a segment is kept if it lasted >= 5s (or was open-world / a boss)
--   * the overall segment's elapsed time is the SUM of its segments'
--   * boss detection is ENCOUNTER_START/END alone - Era has nothing else
--     (read through ZacUI's shared ns.Encounter tracker)
-- Performance: the 1-second ticker is the only timer this file owns; it
-- drives activity pause/unpause, combat-end detection and a 5-second
-- health resync. Everything else is event-driven. The group comes from
-- ZacUI's ns.Roster, "is anyone still fighting" from ns.Encounter; pet
-- ownership stays the meter's own.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Meter = ns.Meter
local Print = ns.Print

local time, GetTime, floor, max, random = time, GetTime, math.floor, math.max, math.random
local band = bit.band
local UnitHealthMax = UnitHealthMax
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers
local Roster = ns.Roster

-- ============================================================
-- TUNABLES (his profile's values are the defaults; config can move some)
-- ============================================================
local MIN_COMBAT_TIME = 5          -- seconds; shorter segments are discarded
local DEATHLOG_EVENTS = 32         -- ring buffer slots per player
local IDLE_PVE, IDLE_PVP = 10, 3   -- seconds without an event -> clock pauses
local FLOOR_PVE, FLOOR_PVP = 10, 3 -- activity time never reads below this

-- combat-log flag masks
local AFFILIATION_MINE_PARTY_RAID = 0x00000007
local REACTION_FRIENDLY = 0x00000010
local TYPE_PLAYER = 0x00000400
local TYPE_PETS = 0x00003000

Meter.inCombat = false
Meter.zoneType = "none"
Meter.inInstance = false
Meter.isPvpZone = false
Meter.playerName = nil
Meter.combatCounter = 0
Meter.segments = {}
Meter.segmentsRev = 0            -- bumped whenever the segment list changes; windows parked on a past fight refresh against it
Meter.HealthCache = {}
Meter.HealthMaxCache = {}

local _tempo = time()
Meter.now = function() return _tempo end

-- ============================================================
-- ACTORS
-- ============================================================
-- The epsilon seed: an "empty" actor totals ~0.001-0.009, never 0.
local function eps() return random(1000, 9000) / 1000000 end

local actorMeta = {}
actorMeta.__index = actorMeta

-- Activity clock, one per actor per attribute container. All unix time.
function actorMeta:OpenClock()
    if self.started then return end
    self.started = true
    if self.endAct then self.endAct = nil
    else self.startAct = _tempo end
end

function actorMeta:PauseClock()
    self.delay = floor(self.lastEvent)
    if self.delay < self.startAct then self.delay = self.startAct end
    self.onHold = true
end

function actorMeta:UnpauseClock()
    local diff = _tempo - self.delay - 1
    if diff > 0 then self.startAct = self.startAct + diff end
    self.onHold = false
end

function actorMeta:StopClock()
    if self.endAct then return end
    if self.onHold then self:UnpauseClock() end
    self.endAct = _tempo
end

-- Details:Tempo(), floors included. activityBonus carries merged overall
-- time (the original fakes it by rewinding start_time; a plain
-- accumulator reads better and adds the same number).
function actorMeta:ActivityTime()
    local fl = self.pvp and FLOOR_PVP or FLOOR_PVE
    local t
    if self.endAct then t = self.endAct - self.startAct
    elseif self.onHold then t = self.delay - self.startAct
    elseif self.startAct == 0 then t = 0
    else t = _tempo - self.startAct end
    t = t + (self.activityBonus or 0)
    if t < fl then
        if Meter.inCombat and Meter.current then
            local ct = Meter.current:GetCombatTime()
            if ct < fl then return ct end
        end
        return fl
    end
    return t
end

local function NewDamageActor(name)
    return setmetatable({
        name = name, tipo = 1,
        total = eps(), totalNoPet = eps(), damageTaken = eps(),
        friendlyFireTotal = 0,
        targets = {}, spells = {}, friendlyFire = nil, pets = nil,
        started = false, startAct = 0, endAct = nil,
        onHold = false, delay = 0, lastEvent = 0, lastDps = 0,
    }, actorMeta)
end

local function NewHealActor(name)
    return setmetatable({
        name = name, tipo = 2,
        total = eps(), totalOver = 0, totalAbsorb = 0, totalDenied = 0,
        healingTaken = eps(),
        targets = {}, targetsOverheal = {}, spells = {}, pets = nil,
        started = false, startAct = 0, endAct = nil,
        onHold = false, delay = 0, lastEvent = 0, lastDps = 0,
    }, actorMeta)
end

-- Misc actors are near-empty; counters appear on first use, like the
-- original's on-the-fly construction.
local function NewMiscActor(name)
    return setmetatable({ name = name, tipo = 4, lastEvent = 0 }, actorMeta)
end

-- Per-spell accumulator (damage). Field names shortened but 1:1:
-- n_* normal hits, c_* crits, g_* glancing; r/b/a track full amounts of
-- hits that were partially resisted/blocked/absorbed.
local function NewSpellTable(id)
    return {
        id = id, total = 0, counter = 0,
        n_amt = 0, n_total = 0, n_min = 0, n_max = 0,
        c_amt = 0, c_total = 0, c_min = 0, c_max = 0,
        g_amt = 0, g_dmg = 0, r_amt = 0, r_dmg = 0,
        b_amt = 0, b_dmg = 0, a_amt = 0, a_dmg = 0,
        targets = {},
    }
end

local function NewHealSpellTable(id)
    return {
        id = id, total = 0, counter = 0, overheal = 0, absorbed = 0,
        n_amt = 0, n_total = 0, n_min = 0, n_max = 0,
        c_amt = 0, c_total = 0, c_min = 0, c_max = 0,
        targets = {}, targets_overheal = {},
    }
end

Meter.NewSpellTable = NewSpellTable
Meter.NewHealSpellTable = NewHealSpellTable

-- ============================================================
-- ACTOR CONTAINERS - keyed by name; the array side keeps sort cheap.
-- ============================================================
local containerMeta = {}
containerMeta.__index = containerMeta

function containerMeta:Get(name)
    return self.index[name]
end

function containerMeta:GetOrCreate(name)
    local actor = self.index[name]
    if not actor then
        actor = self.create(name)
        actor.pvp = Meter.isPvpZone
        self.index[name] = actor
        self.actors[#self.actors + 1] = actor
    end
    return actor
end

local function NewContainer(create, combat)
    return setmetatable({ actors = {}, index = {}, create = create, combat = combat }, containerMeta)
end

-- ============================================================
-- COMBAT (SEGMENT) OBJECT
-- ============================================================
local combatMeta = {}
combatMeta.__index = combatMeta

function combatMeta:GetCombatTime()
    if self.fixedTime then return max(self.fixedTime, 0.1) end
    if self.endTime then return max(self.endTime - self.startTime, 0.1)
    elseif self.startTime and Meter.inCombat and self == Meter.current then
        return max(GetTime() - self.startTime, 0.1)
    end
    return 0.1
end

function combatMeta:Name()
    if self.overall then return "Overall" end
    if self.isBoss then return self.isBoss.name or "Boss" end
    if self.enemyName then return self.enemyName end
    return "Trash"
end

function combatMeta:LockActivityTime()
    for _, cont in ipairs({ self.damage, self.heal }) do
        for _, actor in ipairs(cont.actors) do
            if actor.started then
                actor:StopClock()
                actor.started = false
            else
                if actor.startAct == 0 then actor.startAct = _tempo end
                if not actor.endAct then actor.endAct = _tempo end
            end
        end
    end
end

local function NewCombat(overall)
    local c = setmetatable({
        overall = overall or nil,
        startTime = GetTime(), endTime = nil,
        timeStart = time(),
        totals = { damage = 0, heal = 0 },
        groupTotals = { damage = 0, heal = 0 },
        miscTotals = { dead = 0, interrupt = 0, dispell = 0, cc_break = 0, ress = 0 },
        deaths = {},
        ringBuffers = overall and nil or {},
        needRefresh = {},          -- attribute -> true, the window churn gate
        segmentsAdded = overall and 0 or nil,
    }, combatMeta)
    c.damage = NewContainer(NewDamageActor, c)
    c.heal = NewContainer(NewHealActor, c)
    c.misc = NewContainer(NewMiscActor, c)
    if overall then c.fixedTime = 0 end
    return c
end
Meter.NewCombat = NewCombat

Meter.overall = NewCombat(true)
Meter.current = NewCombat()

-- ============================================================
-- ACTIVITY TICKER - drives pause/unpause + combat-end + health resync.
-- One C_Timer ticker for the whole meter, running only while a combat
-- is open (started on combat start, stopped when the segment closes).
-- ============================================================
local activeDamage = setmetatable({}, { __mode = "k" })
local activeHeal = setmetatable({}, { __mode = "k" })
Meter.activeDamage = activeDamage
Meter.activeHeal = activeHeal

local ticker
local healthTickCount = 0

local GroupInCombat = ns.Encounter.GroupInCombat

local function HealthResync()
    -- keep the death-log HP estimate honest: real values every 5 ticks
    local hc, hm = Meter.HealthCache, Meter.HealthMaxCache
    local units = Roster.Units()
    for i = 1, #units do
        local unit = units[i]
        local guid = UnitGUID(unit)
        if guid then
            local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
            -- (WoW Forever: hidden in combat - keep the last real reading)
            if not (ns.IsSecret and (ns.IsSecret(cur) or ns.IsSecret(mx))) then
                hc[guid], hm[guid] = cur, mx
            end
        end
    end
end

local function Tick()
    _tempo = time()
    local idle = Meter.isPvpZone and IDLE_PVP or IDLE_PVE
    for actor in pairs(activeDamage) do
        if actor.lastEvent + idle > _tempo then
            if actor.onHold then actor:UnpauseClock() end
        elseif not actor.onHold then
            actor:PauseClock()
        end
    end
    for actor in pairs(activeHeal) do
        if actor.lastEvent + idle > _tempo then
            if actor.onHold then actor:UnpauseClock() end
        elseif not actor.onHold then
            actor:PauseClock()
        end
    end
    healthTickCount = healthTickCount + 1
    if healthTickCount >= 5 then
        healthTickCount = 0
        HealthResync()
    end
    -- combat-end: nobody in the group is fighting anymore
    if Meter.inCombat and not GroupInCombat() then
        Meter.EndCombat()
    end
end

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, Tick)
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

-- ============================================================
-- PETS - summon cache first, roster scan second, tooltip scan last.
-- ============================================================
local petCache = {}        -- petGUID -> {name, hashName, ownerName, ownerGuid, ownerFlags}
local petIgnored = {}      -- petGUID -> true after every resolver failed
Meter.petCache = petCache

local petTip = CreateFrame("GameTooltip", "ZacUIMeterPetTooltip", nil, "GameTooltipTemplate")
petTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local PET_PATTERNS = {}
for _, key in ipairs({ "UNITNAME_TITLE_PET", "UNITNAME_TITLE_COMPANION",
    "UNITNAME_TITLE_GUARDIAN", "UNITNAME_TITLE_MINION", "UNITNAME_TITLE_CHARM",
    "UNITNAME_TITLE_CREATION", "UNITNAME_TITLE_SQUIRE" }) do
    local s = _G[key]
    if s then
        PET_PATTERNS[#PET_PATTERNS + 1] = "^" .. s:gsub("%%s", "(.+)") .. "$"
    end
end

local function RegisterPet(petGuid, petName, ownerName, ownerGuid, ownerFlags)
    petCache[petGuid] = {
        name = petName,
        hashName = petName .. " <" .. ownerName .. ">",
        ownerName = ownerName,
        ownerGuid = ownerGuid,
        ownerFlags = ownerFlags or 0x514,
    }
    petIgnored[petGuid] = nil
    return petCache[petGuid]
end
Meter.RegisterPet = RegisterPet

local function ScanUnitPet(petUnit, ownerUnit)
    if not UnitExists(petUnit) then return end
    local petGuid = UnitGUID(petUnit)
    if petGuid and not petCache[petGuid] then
        local petName = UnitName(petUnit)
        local ownerName = UnitName(ownerUnit)
        local ownerGuid = UnitGUID(ownerUnit)
        if petName and ownerName and ownerGuid then
            RegisterPet(petGuid, petName, ownerName, ownerGuid, 0x514)
        end
    end
end

function Meter.PetScan()
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            ScanUnitPet("raidpet" .. i, "raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do
            ScanUnitPet("partypet" .. i, "party" .. i)
        end
        ScanUnitPet("pet", "player")
    else
        ScanUnitPet("pet", "player")
    end
end

-- Tooltip fallback: the hidden-tooltip trick. Returns owner name or nil.
local function TooltipPetOwner(petGuid)
    petTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    petTip:SetHyperlink("unit:" .. petGuid)
    local line = _G["ZacUIMeterPetTooltipTextLeft2"]
    local text = line and line:GetText()
    if not text then return nil end
    for _, pattern in ipairs(PET_PATTERNS) do
        local owner = text:match(pattern)
        if owner then return owner end
    end
    return nil
end

-- The parser's one call: resolve a pet GUID to its cache entry, trying
-- every mechanism once, then blacklisting for the rest of the combat. A
-- pet or guardian outside the group (an enemy's summons) can only be
-- found in the summon cache - the roster scan and the tooltip both look
-- for group owners - so those are not scanned for at all.
function Meter.ResolvePet(petGuid, petName, petFlags)
    local entry = petCache[petGuid]
    if entry then return entry end
    if petIgnored[petGuid] then return nil end
    if not (petFlags and band(petFlags, AFFILIATION_MINE_PARTY_RAID) ~= 0) then
        petIgnored[petGuid] = true
        return nil
    end
    Meter.PetScan()
    entry = petCache[petGuid]
    if entry then return entry end
    local ownerName = TooltipPetOwner(petGuid)
    if ownerName and Roster.UnitByName(ownerName) then
        return RegisterPet(petGuid, petName, ownerName, "", 0x514)
    end
    petIgnored[petGuid] = true
    return nil
end

function Meter.RemovePet(petGuid)
    petCache[petGuid] = nil
end

-- ============================================================
-- ROSTER - ns.Roster holds the group; the meter only re-reads the pets
-- after a change, once per burst (a raid forming, every hunter's pet
-- coming out at a pull).
-- ============================================================
local PetScanSoon = ns.Coalescer(function() Meter.PetScan() end, 0.2)
Roster.On("Meter", PetScanSoon)

-- ============================================================
-- DEATH LOG - recycling ring buffer per player, linearized on death.
-- Event record: {isDamage, spellId, amount, time, hpPct, source,
--                overkill, crit, school}
-- The buffers themselves are kept from fight to fight (the first hits of
-- a 40-player pull used to build 1300 small tables inside the combat
-- log handler); a buffer taken up by a new fight starts empty.
-- ============================================================
local rbPool, rbPooled = {}, 0
local RB_POOL_MAX = 80          -- a raid and its pets; strangers beyond that are not kept
local function GetRingBuffer(combat, playerName)
    local buffers = combat.ringBuffers
    if not buffers then return nil end
    local rb = buffers[playerName]
    if not rb then
        rb = rbPool[playerName]
        if rb then
            rb.n = 1
            for i = 1, DEATHLOG_EVENTS do rb[i][4] = nil end
        else
            rb = { n = 1 }
            for i = 1, DEATHLOG_EVENTS do rb[i] = {} end
            if rbPooled < RB_POOL_MAX then
                rbPool[playerName] = rb
                rbPooled = rbPooled + 1
            end
        end
        buffers[playerName] = rb
    end
    return rb
end

function Meter.DeathLogEvent(playerName, isDamage, spellId, amount, evTime,
                             sourceName, overkill, crit, school, targetSerial)
    local combat = Meter.current
    local rb = GetRingBuffer(combat, playerName)
    if not rb then return end
    local hp = 0
    local hmax = Meter.HealthMaxCache[targetSerial]
    if hmax and hmax > 0 then
        hp = (Meter.HealthCache[targetSerial] or hmax) / hmax
        if hp < 0 then hp = 0 elseif hp > 1 then hp = 1 end
    end
    local i = rb.n
    local ev = rb[i]
    ev[1], ev[2], ev[3], ev[4], ev[5] = isDamage, spellId, amount, evTime, hp
    ev[6], ev[7], ev[8], ev[9] = sourceName, overkill or -1, crit or false, school
    i = i + 1
    if i == DEATHLOG_EVENTS + 1 then rb.n = 1 else rb.n = i end
end

function Meter.BuildDeathTable(playerName, playerClass, deathTime, targetSerial)
    local combat = Meter.current
    local rb = combat.ringBuffers and combat.ringBuffers[playerName]
    local events = {}
    if rb then
        -- linearize from the write cursor; keep the trailing 32 seconds
        local windowStart = deathTime - DEATHLOG_EVENTS
        local function keep(ev)
            if ev[4] and ev[4] > windowStart then
                events[#events + 1] = { ev[1], ev[2], ev[3], ev[4], ev[5],
                                        ev[6], ev[7], ev[8], ev[9] }
            end
        end
        for i = rb.n, DEATHLOG_EVENTS do keep(rb[i]) end
        for i = 1, rb.n - 1 do keep(rb[i]) end
        combat.ringBuffers[playerName] = nil
    end
    local elapsed = GetTime() - combat.startTime
    local deathTable = {
        events = events,
        time = deathTime,
        name = playerName,
        class = playerClass,
        maxHealth = Meter.HealthMaxCache[targetSerial] or UnitHealthMax(playerName) or 0,
        timeString = floor(elapsed / 60) .. "m " .. floor(elapsed % 60) .. "s",
        deadAt = elapsed,
    }
    combat.deaths[#combat.deaths + 1] = deathTable
    return deathTable
end

-- Final 10-second trim, run when the segment closes.
local function CutDeathEvents(combat)
    for _, dt in ipairs(combat.deaths) do
        local kept = {}
        for _, ev in ipairs(dt.events) do
            if ev[4] + 10 >= dt.time then kept[#kept + 1] = ev end
        end
        dt.events = kept
    end
end

-- ============================================================
-- COMBAT LIFECYCLE
-- ============================================================
local encounterTable = nil     -- {id, name, diff, size, start}
local latestEncounterEnd = 0

function Meter.StartCombat()
    if Meter.inCombat then return end
    local past = Meter.current
    if past then past:LockActivityTime() end
    _tempo = time()
    Meter.combatCounter = Meter.combatCounter + 1
    local c = NewCombat()
    c.combatId = Meter.combatCounter
    Meter.current = c
    Meter.inCombat = true
    wipe(activeDamage); wipe(activeHeal)
    wipe(petIgnored)
    Meter.PetScan()
    if Meter.UpdateParserGears then Meter.UpdateParserGears() end
    StartTicker()
    -- an ENCOUNTER_START in the last 3 seconds claims this segment
    if encounterTable and encounterTable.start and encounterTable.start >= GetTime() - 3 then
        c.isBoss = { name = encounterTable.name, id = encounterTable.id,
                     diff = encounterTable.diff }
    end
    if Meter.OnCombatStart then Meter.OnCombatStart(c) end
end

-- Overall merge: containers fold actor-by-actor, activity accumulates
-- into activityBonus, elapsed time sums into fixedTime.
local function MergeSpell(into, from, isHeal)
    into.total = into.total + from.total
    into.counter = into.counter + from.counter
    into.n_amt = into.n_amt + from.n_amt
    into.n_total = into.n_total + from.n_total
    if from.n_max > into.n_max then into.n_max = from.n_max end
    into.c_amt = into.c_amt + from.c_amt
    into.c_total = into.c_total + from.c_total
    if from.c_max > into.c_max then into.c_max = from.c_max end
    if isHeal then
        into.overheal = into.overheal + from.overheal
        into.absorbed = into.absorbed + from.absorbed
        for t, v in pairs(from.targets_overheal) do
            into.targets_overheal[t] = (into.targets_overheal[t] or 0) + v
        end
    else
        into.g_amt = into.g_amt + from.g_amt; into.g_dmg = into.g_dmg + from.g_dmg
        into.r_amt = into.r_amt + from.r_amt; into.r_dmg = into.r_dmg + from.r_dmg
        into.b_amt = into.b_amt + from.b_amt; into.b_dmg = into.b_dmg + from.b_dmg
        into.a_amt = into.a_amt + from.a_amt; into.a_dmg = into.a_dmg + from.a_dmg
    end
    for t, v in pairs(from.targets) do
        into.targets[t] = (into.targets[t] or 0) + v
    end
end

local function MergeActorMeta(into, from)
    into.class = into.class or from.class
    into.spec = into.spec or from.spec
    into.serial = into.serial or from.serial
    into.flag = into.flag or from.flag
    into.grupo = into.grupo or from.grupo
    into.enemy = into.enemy or from.enemy
    into.ownerName = into.ownerName or from.ownerName
    into.isSelf = into.isSelf or from.isSelf
end

-- Folds `combat` into `overall`. Generic in both arguments so the same
-- code builds the LIVE overall below - an overall that is already a
-- merge can be merged again, which is what makes "overall including the
-- fight in progress" a snapshot rather than a second bookkeeping path.
local MISC_COUNTERS = { "interrupt", "dispell", "cc_break", "ress", "dead" }

local function MergeCombat(overall, combat)
    overall.fixedTime = (overall.fixedTime or 0) + combat:GetCombatTime()
    overall.segmentsAdded = (overall.segmentsAdded or 0) + (combat.segmentsAdded or 1)
    for _, pair in ipairs({ { combat.damage, overall.damage, false },
                            { combat.heal, overall.heal, true } }) do
        local src, dst, isHeal = pair[1], pair[2], pair[3]
        for _, actor in ipairs(src.actors) do
          -- only what a window can show (group members and pets): the
          -- enemies' own damage and healing were folded in, saved and
          -- re-merged all night for nothing
          if actor.grupo or actor.ownerName then
            local o = dst:GetOrCreate(actor.name)
            MergeActorMeta(o, actor)
            o.total = o.total + actor.total
            o.lastEvent = max(o.lastEvent or 0, actor.lastEvent or 0)
            local act = (actor.endAct or _tempo) - actor.startAct
            if act > 0 and actor.startAct > 0 then
                o.activityBonus = (o.activityBonus or 0) + act
            end
            -- An actor that is itself a merge carries its time here, not
            -- in a clock. Without this line an overall merged into a
            -- snapshot would report every fight's damage over only the
            -- current fight's time.
            if actor.activityBonus then
                o.activityBonus = (o.activityBonus or 0) + actor.activityBonus
            end
            if isHeal then
                o.totalOver = o.totalOver + actor.totalOver
                o.totalAbsorb = o.totalAbsorb + actor.totalAbsorb
                o.healingTaken = o.healingTaken + actor.healingTaken
            else
                o.totalNoPet = o.totalNoPet + actor.totalNoPet
                o.damageTaken = o.damageTaken + actor.damageTaken
                o.friendlyFireTotal = o.friendlyFireTotal + actor.friendlyFireTotal
            end
            for t, v in pairs(actor.targets) do
                o.targets[t] = (o.targets[t] or 0) + v
            end
            for id, sp in pairs(actor.spells) do
                local osp = o.spells[id]
                if not osp then
                    osp = isHeal and NewHealSpellTable(id) or NewSpellTable(id)
                    o.spells[id] = osp
                end
                MergeSpell(osp, sp, isHeal)
            end
          end
        end
    end
    -- misc: plain counter folds
    for _, actor in ipairs(combat.misc.actors) do
        if actor.grupo or actor.ownerName then
            local o = overall.misc:GetOrCreate(actor.name)
            MergeActorMeta(o, actor)
            for _, key in ipairs(MISC_COUNTERS) do
                if actor[key] then o[key] = (o[key] or 0) + actor[key] end
            end
        end
    end
    for k, v in pairs(combat.miscTotals) do
        overall.miscTotals[k] = (overall.miscTotals[k] or 0) + v
    end
    overall.totals.damage = overall.totals.damage + combat.totals.damage
    overall.totals.heal = overall.totals.heal + combat.totals.heal
    overall.groupTotals.damage = overall.groupTotals.damage + combat.groupTotals.damage
    overall.groupTotals.heal = overall.groupTotals.heal + combat.groupTotals.heal
    overall.needRefresh.all = true
end

local function MergeIntoOverall(combat)
    MergeCombat(Meter.overall, combat)
    -- the first fight of an overall inside a raid says which raid it is
    if Meter.StampRaid then Meter.StampRaid() end
end

-- ============================================================
-- THE LIVE OVERALL
-- ============================================================
-- Meter.overall only ever receives a fight when it CLOSES, so a window
-- set to Overall sat still for the whole pull and jumped when it ended -
-- the opposite of what a meter is for. This returns an overall that
-- includes the fight in progress, refreshed on demand and cached for
-- half a second so three windows on the same tick share one.
--
-- A view, not a mutation, on purpose. Folding the live fight into
-- Meter.overall as it happens would double-count it when EndCombat folds
-- it again.
--
-- A VIEW KEPT FOR THE FIGHT. It used to be a full fresh merge every
-- refresh - a new copy of every actor, spell and target of the whole
-- night, enemies included - which grew all evening. Now the view's
-- actors are made once per fight, only for what a window can show
-- (group members and pets), and a refresh only re-adds their totals in
-- place. Their spells and targets (the tooltip, the breakdown, the
-- report) are merged from the two sources the moment something reads
-- them, and again after the next refresh.
--
-- Out of combat there is nothing live, and the closed overall is the
-- answer as it always was.
local LAZY = { spells = true, targets = true, targetsOverheal = true, friendlyFire = true, pets = true,
    interruptTargets = true, interruptSpells = true, interruptedWhat = true,
    dispellTargets = true, dispellSpells = true, dispelledWhat = true }

local function SumMaps(a, b, key, always)
    local ma, mb = a and a[key], b and b[key]
    if not ma and not mb then return always and {} or nil end
    local out = {}
    if ma then for k, v in pairs(ma) do out[k] = v end end
    if mb then for k, v in pairs(mb) do out[k] = (out[k] or 0) + v end end
    return out
end

local function SumSpells(a, b, isHeal)
    local out = {}
    for pass = 1, 2 do
        local src = pass == 1 and a or b
        if src and src.spells then
            for id, sp in pairs(src.spells) do
                local o = out[id]
                if not o then
                    o = isHeal and NewHealSpellTable(id) or NewSpellTable(id)
                    o.name, o.school, o.isShield = sp.name, sp.school, sp.isShield
                    out[id] = o
                end
                MergeSpell(o, sp, isHeal)
            end
        end
    end
    return out
end

local liveMeta = {
    __index = function(t, k)
        if LAZY[k] then
            local a, b = rawget(t, "_ov"), rawget(t, "_cur")
            local v
            if k == "spells" then
                v = SumSpells(a, b, rawget(t, "tipo") == 2)
            elseif k == "pets" then
                local pa, pb = a and a.pets, b and b.pets
                if pa or pb then
                    v = {}
                    if pa then for n in pairs(pa) do v[n] = true end end
                    if pb then for n in pairs(pb) do v[n] = true end end
                end
            else
                v = SumMaps(a, b, k, k == "targets" or (k == "targetsOverheal" and rawget(t, "tipo") == 2))
            end
            if v ~= nil then rawset(t, k, v) end
            return v
        end
        return actorMeta[k]
    end,
}

local NUMS = {
    damage = { "total", "totalNoPet", "damageTaken", "friendlyFireTotal" },
    heal = { "total", "totalOver", "totalAbsorb", "healingTaken" },
}
local META_KEYS = { "class", "spec", "serial", "flag", "grupo", "enemy", "ownerName", "isSelf" }
local TIPO = { damage = 1, heal = 2, misc = 4 }
local CONTAINERS = { "damage", "heal", "misc" }

local function Shown(a) return a.grupo or a.ownerName end

-- an actor's time as a merge carries it: its clock plus what it merged
local function MergedAct(src)
    local t = src.activityBonus or 0
    local act = (src.endAct or _tempo) - src.startAct
    if act > 0 and src.startAct > 0 then t = t + act end
    return t
end

local function FillLive(a, ov, cur, key)
    for k in pairs(LAZY) do rawset(a, k, nil) end
    a._ov, a._cur = ov, cur
    for i = 1, #META_KEYS do
        local k = META_KEYS[i]
        a[k] = (ov and ov[k]) or (cur and cur[k]) or nil
    end
    if key == "misc" then
        for i = 1, #MISC_COUNTERS do
            local k = MISC_COUNTERS[i]
            local x, y = ov and ov[k], cur and cur[k]
            a[k] = (x or y) and ((x or 0) + (y or 0)) or nil
        end
        return
    end
    local nums = NUMS[key]
    for i = 1, #nums do
        local k = nums[i]
        a[k] = (ov and ov[k] or 0) + (cur and cur[k] or 0)
    end
    a.total = a.total + a._eps
    a.lastEvent = max(ov and ov.lastEvent or 0, cur and cur.lastEvent or 0)
    a.activityBonus = (ov and MergedAct(ov) or 0) + (cur and MergedAct(cur) or 0)
end

local function LiveActor(cont, name, key)
    local a = cont.index[name]
    if not a then
        a = setmetatable({ name = name, tipo = TIPO[key], pvp = Meter.isPvpZone, _eps = eps(),
            started = false, startAct = 0, onHold = false, delay = 0, lastEvent = 0, lastDps = 0 }, liveMeta)
        cont.index[name] = a
        cont.actors[#cont.actors + 1] = a
    end
    return a
end

local live, liveStamp = nil, -1

function Meter.LiveOverall()
    if not Meter.inCombat then return Meter.overall end
    local ov, cur = Meter.overall, Meter.current
    local now = GetTime()
    local same = live and live.base == ov and live.cur == cur
    if same and now - liveStamp < 0.5 then return live end
    if not same then
        live = NewCombat(true)
        live.base, live.cur, live.live = ov, cur, true
    end
    liveStamp = now
    for c = 1, #CONTAINERS do
        local key = CONTAINERS[c]
        local lc, oc, cc = live[key], ov[key], cur[key]
        local oIndex, cIndex = oc.index, cc.index
        for _, a in ipairs(oc.actors) do
            if Shown(a) then FillLive(LiveActor(lc, a.name, key), a, cIndex[a.name], key) end
        end
        for _, a in ipairs(cc.actors) do
            local o = oIndex[a.name]
            if Shown(a) and not (o and Shown(o)) then FillLive(LiveActor(lc, a.name, key), o, a, key) end
        end
    end
    live.fixedTime = ov:GetCombatTime() + cur:GetCombatTime()
    live.segmentsAdded = (ov.segmentsAdded or 0) + 1
    live.totals.damage = ov.totals.damage + cur.totals.damage
    live.totals.heal = ov.totals.heal + cur.totals.heal
    live.groupTotals.damage = ov.groupTotals.damage + cur.groupTotals.damage
    live.groupTotals.heal = ov.groupTotals.heal + cur.groupTotals.heal
    local mt = live.miscTotals
    for k in pairs(mt) do mt[k] = 0 end
    for k, v in pairs(ov.miscTotals) do mt[k] = (mt[k] or 0) + v end
    for k, v in pairs(cur.miscTotals) do mt[k] = (mt[k] or 0) + v end
    return live
end

-- the whole merge, every spell and target, for the logout save
local function FullLiveOverall()
    local snap = NewCombat(true)
    MergeCombat(snap, Meter.overall)
    MergeCombat(snap, Meter.current)
    snap.segmentsAdded = (Meter.overall.segmentsAdded or 0) + 1
    snap.live = true
    return snap
end

function Meter.ResetOverall()
    Meter.overall = NewCombat(true)
    live = nil
    Meter.segmentsRev = (Meter.segmentsRev or 0) + 1
    if Meter.Windows then Meter.Windows.DirtyAll() end
end

local lastBossName = nil

function Meter.EndCombat(bossKilled, fromEncounterEnd)
    if not Meter.inCombat then return end
    local d = Meter.DB and Meter.DB() or nil
    Meter.inCombat = false
    -- A clock on GetTime. _tempo is wall-clock seconds that only advance
    -- inside the combat ticker, so it stops the moment StopTicker runs on
    -- the next line - useless for measuring "how long ago did the last
    -- fight end", which is exactly what the parser's post-combat grace
    -- period needs.
    Meter.lastCombatEndTime = GetTime()
    StopTicker()
    local combat = Meter.current
    combat:LockActivityTime()
    combat.endTime = GetTime()
    combat.timeEnd = time()
    if fromEncounterEnd and encounterTable then
        -- the encounter's own timestamps are the honest fight length
        combat.startTime = encounterTable.start or combat.startTime
        combat.endTime = encounterTable.endTime or combat.endTime
        combat.isBoss = combat.isBoss or { name = encounterTable.name,
            id = encounterTable.id, diff = encounterTable.diff }
        combat.isBoss.killed = bossKilled and true or false
    end
    CutDeathEvents(combat)
    combat.ringBuffers = nil
    -- name trash pulls after their biggest enemy so the segment list reads
    for _, actor in ipairs(combat.damage.actors) do
        if not actor.grupo and not actor.ownerName and not combat.enemyName then
            combat.enemyName = actor.name
        end
    end
    combat.isTrash = Meter.inInstance and not combat.isBoss or false

    local elapsed = combat:GetCombatTime()
    local minTime = d and d.minCombatTime or MIN_COMBAT_TIME
    local kept = Meter.zoneType == "none" or elapsed >= minTime or #Meter.segments == 0
    if kept then
        table.insert(Meter.segments, 1, combat)
        local cap = d and d.segmentsAmount or 40
        while #Meter.segments > cap do
            table.remove(Meter.segments)
        end
        Meter.segmentsRev = (Meter.segmentsRev or 0) + 1
        -- OVERALL TAKES EVERY KEPT SEGMENT. Boss, trash, the ten-second
        -- pull between - if it was worth a segment it is part of the
        -- night. The old 10-second instance gate silently dropped short
        -- trash pulls from the overall, which is exactly the kind of gap
        -- that makes an overall not add up to the segments. The one
        -- remaining exception is the optional new-boss wipe, which is
        -- off by default now and lives on the config page.
        if combat.isBoss and Meter.zoneType == "raid" then
            if lastBossName and lastBossName ~= combat.isBoss.name
                and d and d.overallClearNewBoss == true then
                Meter.ResetOverall()
            end
            lastBossName = combat.isBoss.name
        end
        MergeIntoOverall(combat)
    else
        -- discarded; roll the counter back like the original
        Meter.combatCounter = Meter.combatCounter - 1
    end
    -- kept: false for a fight too short to keep (it is in no list)
    if Meter.OnCombatEnd then Meter.OnCombatEnd(combat, kept) end
end

-- ============================================================
-- EVENTS
-- ============================================================
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_PET")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("UNIT_MAXHEALTH")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_MAXHEALTH" then
        local guid = UnitGUID(arg1)
        if guid then
            Meter.HealthMaxCache[guid] = UnitHealthMax(arg1)
        end
    elseif event == "UNIT_PET" then
        PetScanSoon()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Meter.playerName = UnitName("player")
        local _, zoneType = IsInInstance()
        Meter.zoneType = zoneType or "none"
        Meter.inInstance = zoneType == "party" or zoneType == "raid"
        Meter.isPvpZone = zoneType == "pvp" or zoneType == "arena"
        Meter.PetScan()
        HealthResync()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- pvp zones fight in one long stream; a real combat starts now
        if Meter.isPvpZone and not Meter.inCombat then Meter.StartCombat() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- solo play ends the fight immediately; groups wait for the ticker
        if Meter.inCombat and not IsInGroup() and not IsInRaid() then
            Meter.EndCombat()
        end
    end
end)

-- Boss pulls come from ZacUI's encounter tracker (ns.Encounter), the
-- same one the raid mods load by. The 10 s / 15 s gates are the meter's
-- own segment policy (Details'): a pull right after an end, or a second
-- end, never cuts a new segment. A "reset" (no ENCOUNTER_END ever came)
-- needs nothing here - the ticker already closes the fight when the
-- group leaves combat.
ns.Encounter.On("Meter.combat", function(event, id, name, diff, size, success)
    if event == "start" then
        if latestEncounterEnd + 10 > GetTime() then return end
        encounterTable = { id = id, name = name, diff = diff, size = size,
                           start = GetTime() }
        if Meter.inCombat and Meter.current and not Meter.current.isBoss then
            -- combat opened on trash right before the pull; split it
            Meter.EndCombat()
        end
        if not Meter.inCombat then Meter.StartCombat() end
        if Meter.current then
            Meter.current.isBoss = { name = name, id = id, diff = diff }
        end
    elseif event == "end" then
        if latestEncounterEnd + 15 > GetTime() then return end
        latestEncounterEnd = GetTime()
        if encounterTable then encounterTable.endTime = GetTime() end
        if Meter.inCombat then
            Meter.EndCombat(success == 1, true)
        end
        encounterTable = nil
    end
end)


-- ============================================================
-- THE OVERALL ACROSS LOGOUT (2026-10-21, Zac: "can you make my overall
-- damage meter persist through logout?")
-- ============================================================
-- On logout (and /reload, which logs out first) the overall is written
-- to the per-character saved variables as plain numbers and names -
-- ZacUICharDB.meterOverall - and on the next login it is put back, so
-- an Overall window picks up where it left off. Logging out mid-fight
-- keeps that fight too (the live overall is saved). The single fights
-- (segments) still start empty each session. A reset (the meter's
-- reset button, or the optional new-boss wipe) clears what is saved.
--
-- A NEW RAID STARTS A NEW OVERALL (Zac: "keep overall through a logout
-- and reset on a new raid id/raid"). The overall remembers the raid it
-- was built in (instance, and the raid lockout once there is one), and
-- entering a raid checks it:
--   * a different raid, or a different lockout id        -> cleared
--   * the same raid, lockout not made yet (no boss down), the overall
--     under 12 hours old                                  -> kept
--   * an overall from outside any raid (dungeons, world)  -> cleared
-- So zoning out to repair, a disconnect, a logout or a /reload mid-raid
-- all come back to the same overall.
-- DUNGEONS TOO (Zac 2026-11-03: "my overall damage meter needs to reset
-- on dungions as well not just raids"). A dungeon has no lockout id, so
-- the same dungeon counts as the same run while its last fight is under
-- an hour old and it hasn't been reset since; a different dungeon, an
-- older run, a reset ("... has been reset.") or an overall from a raid or
-- the world starts fresh.
local SAVE_VERSION = 2
local SAME_RAID_HOURS = 12
local SAME_DUNGEON_MINUTES = 60
local dungeonResetAt = {}     -- dungeon name -> time() it was reset

-- the raid or dungeon you are in now: { map, name, lock, at, kind }, or
-- nil outside one
local function CurrentRaid()
    local name, itype, _, _, _, _, _, map = GetInstanceInfo()
    if itype == "party" then return { map = map, name = name, at = time(), kind = "party" } end
    if itype ~= "raid" then return nil end
    local lock
    if GetNumSavedInstances and GetSavedInstanceInfo then
        for i = 1, GetNumSavedInstances() do
            local sname, sid, reset, _, locked = GetSavedInstanceInfo(i)
            if sname == name and locked and (reset or 0) > 0 and sid then lock = tostring(sid) break end
        end
    end
    return { map = map, name = name, lock = lock, at = time() }
end

function Meter.StampRaid()
    local o = Meter.overall
    if not o then return end
    if Meter.zoneType ~= "raid" and Meter.zoneType ~= "party" then return end
    if o.raidKey then
        -- a run stays "the same run" counted from its last fight (a raid
        -- too: its "at" is how recent the overall is when the lockout
        -- list is slow to answer, below)
        local _, _, _, _, _, _, _, map = GetInstanceInfo()
        if map == o.raidKey.map then o.raidKey.at = time() end
        return
    end
    o.raidKey = CurrentRaid()
end

-- a copy of plain data only: string/number keys, no functions, no
-- metatables, nothing deeper than the meter ever nests
local function PlainCopy(v, depth)
    if type(v) ~= "table" then return v end
    depth = depth or 0
    if depth > 6 then return nil end
    local out = {}
    for k, x in pairs(v) do
        local tk, tx = type(k), type(x)
        if (tk == "string" or tk == "number") and tx ~= "function" and tx ~= "userdata" and tx ~= "thread" then
            if tx == "table" then
                out[k] = PlainCopy(x, depth + 1)
            else
                out[k] = x
            end
        end
    end
    return out
end

local function SaveOverall()
    if type(ZacUICharDB) ~= "table" then return end
    local o = Meter.inCombat and FullLiveOverall() or Meter.overall
    if not o or (o.segmentsAdded or 0) <= 0 then
        ZacUICharDB.meterOverall = nil
        return
    end
    local snap = {
        v = SAVE_VERSION, savedAt = time(), timeStart = o.timeStart,
        raidKey = PlainCopy(Meter.overall and Meter.overall.raidKey),
        fixedTime = o.fixedTime, segmentsAdded = o.segmentsAdded,
        totals = PlainCopy(o.totals), groupTotals = PlainCopy(o.groupTotals),
        miscTotals = PlainCopy(o.miscTotals),
        damage = {}, heal = {}, misc = {},
    }
    for _, key in ipairs({ "damage", "heal", "misc" }) do
        local list = snap[key]
        for _, actor in ipairs(o[key].actors) do
            local a = PlainCopy(actor)
            -- an overall actor's time lives in activityBonus; the clock
            -- fields mean nothing next session
            a.started, a.onHold, a.startAct, a.endAct, a.delay = nil, nil, nil, nil, nil
            list[#list + 1] = a
        end
    end
    ZacUICharDB.meterOverall = snap
end

local function LoadOverall()
    local snap = type(ZacUICharDB) == "table" and ZacUICharDB.meterOverall
    if type(snap) ~= "table" or (snap.v ~= SAVE_VERSION and snap.v ~= 1) or (snap.segmentsAdded or 0) <= 0 then return end
    local c = NewCombat(true)
    c.fixedTime = snap.fixedTime or 0
    c.segmentsAdded = snap.segmentsAdded or 0
    c.timeStart = snap.timeStart or c.timeStart
    c.restored = true
    c.savedAt = snap.savedAt
    c.raidKey = type(snap.raidKey) == "table" and PlainCopy(snap.raidKey) or nil
    -- saved before raids were remembered (the first version): treated as
    -- this raid when it is recent, so nobody loses tonight's numbers
    c.legacy = snap.v == 1 or nil
    for _, key in ipairs({ "totals", "groupTotals", "miscTotals" }) do
        for k, v in pairs(snap[key] or {}) do
            if type(v) == "number" then c[key][k] = v end
        end
    end
    for _, key in ipairs({ "damage", "heal", "misc" }) do
        local cont = c[key]
        for _, a in ipairs(snap[key] or {}) do
            if type(a) == "table" and type(a.name) == "string" and not cont.index[a.name] then
                local actor = setmetatable(PlainCopy(a), actorMeta)
                actor.started, actor.onHold, actor.startAct, actor.endAct = false, false, 0, nil
                actor.delay = 0
                actor.lastEvent = actor.lastEvent or 0
                actor.targets = actor.targets or {}
                actor.spells = actor.spells or {}
                cont.index[a.name] = actor
                cont.actors[#cont.actors + 1] = actor
            end
        end
    end
    -- anything already fought this session (normally nothing) stays in
    if Meter.overall and (Meter.overall.segmentsAdded or 0) > 0 then
        MergeCombat(c, Meter.overall)
    end
    c.needRefresh.all = true
    Meter.overall = c
    live = nil
    Meter.segmentsRev = (Meter.segmentsRev or 0) + 1
    if Meter.Windows and Meter.Windows.DirtyAll then Meter.Windows.DirtyAll() end
end
Meter.SaveOverall, Meter.LoadOverall = SaveOverall, LoadOverall

-- entering a raid: the same raid keeps the overall, a new one clears it
local function CheckRaid()
    local cur = CurrentRaid()
    if not cur then return end
    local o = Meter.overall
    if not o or (o.segmentsAdded or 0) <= 0 then
        if o then o.raidKey = cur end
        return
    end
    local k = o.raidKey
    local recent = function(at) return at and (time() - at) < SAME_RAID_HOURS * 3600 end
    local same
    if cur.kind == "party" or (k and k.kind == "party") then
        same = k ~= nil and k.kind == "party" and cur.kind == "party" and k.map == cur.map
            and k.at ~= nil and (time() - k.at) < SAME_DUNGEON_MINUTES * 60
            and not ((dungeonResetAt[cur.name or ""] or 0) >= k.at)
    elseif not k then
        same = o.legacy and recent(o.savedAt) or false
    elseif k.map ~= cur.map then
        same = false
    elseif k.lock and cur.lock then
        same = (k.lock == cur.lock)
    elseif k.lock and not cur.lock then
        -- no lockout in the list: the raid reset - or the list has not
        -- answered yet (a reload or a run back after a death, with the
        -- 4 s wait over). Zac 2026-11-04: "my overall damage meter on my
        -- warrior thanda not tracking overall". Fought here in the last
        -- 12 hours = the same raid; older = the lockout really is gone.
        same = recent(k.at) or false
    else
        same = recent(k.at) or false -- no boss down when it was stamped
    end
    if same then
        o.legacy = nil
        o.raidKey = o.raidKey or cur
        if cur.lock and not o.raidKey.lock then o.raidKey.lock = cur.lock end
        o.raidKey.at = cur.at
    else
        Meter.ResetOverall()
        Meter.overall.raidKey = cur
        if Print then
            Print(string.format("Meter: new %s (%s) - the overall starts fresh.",
                cur.kind == "party" and "dungeon" or "raid", cur.name or (cur.kind == "party" and "dungeon" or "raid")))
        end
    end
end

local checkPending = false
local persist = CreateFrame("Frame")
persist:RegisterEvent("PLAYER_LOGIN")
persist:RegisterEvent("PLAYER_LOGOUT")
persist:RegisterEvent("PLAYER_ENTERING_WORLD")
persist:RegisterEvent("UPDATE_INSTANCE_INFO")
persist:RegisterEvent("CHAT_MSG_SYSTEM")
-- "%s has been reset." -> a pattern that catches the dungeon's name
local RESET_PAT = type(INSTANCE_RESET_SUCCESS) == "string"
    and ("^" .. INSTANCE_RESET_SUCCESS:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$") or nil
persist:SetScript("OnEvent", function(self, event, msg)
    if event == "CHAT_MSG_SYSTEM" then
        local name = RESET_PAT and type(msg) == "string" and msg:match(RESET_PAT)
        if name then dungeonResetAt[name] = time() end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        local _, itype = GetInstanceInfo()
        if itype == "party" then
            -- no lockout to ask for in a dungeon: check now
            checkPending = false
            pcall(CheckRaid)
            return
        end
        if itype ~= "raid" then checkPending = false return end
        -- the lockout list has to be asked for; check when it answers,
        -- or after a few seconds whatever happens
        checkPending = true
        if RequestRaidInfo then RequestRaidInfo() end
        C_Timer.After(4, function()
            if checkPending then checkPending = false pcall(CheckRaid) end
        end)
    elseif event == "UPDATE_INSTANCE_INFO" then
        if checkPending then
            checkPending = false
            pcall(CheckRaid)
        else
            -- the first boss down makes the lockout: remember its id
            local o = Meter.overall
            local k = o and o.raidKey
            if k and not k.lock then
                local cur = CurrentRaid()
                if cur and cur.map == k.map and cur.lock then k.lock = cur.lock end
            end
        end
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        local ok, err = pcall(LoadOverall)
        if not ok and ns.Debug then ns.Debug("meter: restoring the overall failed: " .. tostring(err)) end
    else
        pcall(SaveOverall)
    end
end)

-- a kill in a raid: ask for the lockout list (every ENCOUNTER_END, from
-- the encounter tracker)
ns.Encounter.On("Meter.persist", function(event, _, _, _, _, success)
    if event == "end" and success == 1 and RequestRaidInfo then
        local _, itype = GetInstanceInfo()
        -- a Lua function, not RequestRaidInfo itself: this client's
        -- C_Timer.After refuses a C function as the callback
        if itype == "raid" then
            C_Timer.After(3, function() if RequestRaidInfo then RequestRaidInfo() end end)
        end
    end
end)
