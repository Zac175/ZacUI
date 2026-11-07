-- Meter_GameMeter - the damage meter on a game that gives addons no
-- combat log (WoW Forever, or the game-version override's Forever).
-- Part of ZacUI; load order is set by the TOC (after Meter_Parser).
--
-- WHERE THE NUMBERS COME FROM. Forever keeps its own damage meter and
-- lets addons read it (C_DamageMeter: warcraft.wiki.gg lists it for
-- Forever 1.60.1, and for Classic Era 1.15.9 and TBC 2.5.6 too). In a
-- fight its numbers are secret values, which an addon may show but never
-- add, compare or sort; out of combat they are plain. So here each fight
-- is still a meter segment, opened and closed the way the meter always
-- does it (the pull, the encounter, the group leaving combat), and when it
-- closes - out of combat - it is filled from the game's own sessions:
--   damage done (with each ability), healing done (with each ability),
--   damage taken, interrupts and dispels; deaths when the game counts them.
-- What the combat log alone gave stays empty: hit counts and crits, who
-- hit whom, overhealing, death logs. Nothing shows DURING a fight.
--
-- WHICH SESSIONS. The game opens a session per fight. The newest session
-- id is noted when a segment opens; the segment takes every session newer
-- than that, up to the newest one when it closes (a fight the player left
-- and rejoined is two sessions, added up).
--
-- A FIGHT THAT ENDS IN COMBAT (an encounter's end while you are still
-- fighting) waits: the segment closes when you leave combat, so it is
-- filled with plain numbers before it goes into the list and the overall.
--
-- Classic Era and TBC: the combat log parser runs and this file does
-- nothing at all.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local Meter = ns.Meter
if not Meter then return end

-- only where there is no combat log (the flavor is fixed by now), and
-- only on a client that has the game's meter to read
if not (_G.ZACUI_IS_FOREVER or (ns.NoCombatLog and ns.NoCombatLog())) then return end
if not (C_DamageMeter and (C_DamageMeter.GetCombatSessionFromID or C_DamageMeter.GetCombatSessionFromType)) then return end

local GM = {}
Meter.GameMeter = GM

local floor, max, type, pairs, ipairs, pcall = math.floor, math.max, type, pairs, ipairs, pcall
local Roster = ns.Roster

-- Enum.DamageMeterType, with the numbers from warcraft.wiki.gg where the
-- client has no Enum (Deaths only where the client names it)
local function Types()
    local E = Enum and Enum.DamageMeterType
    return {
        damage    = E and E.DamageDone or 0,
        heal      = E and E.HealingDone or 2,
        interrupt = E and E.Interrupts or 5,
        dispel    = E and E.Dispels or 6,
        taken     = E and E.DamageTaken or 7,
        deaths    = E and E.Deaths or nil,
    }
end

local function API() return C_DamageMeter end

-- the game's meter is not secret right now (out of combat)
local function Readable()
    if InCombatLockdown and InCombatLockdown() then return false end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return false end
    return true
end
GM.Readable = Readable

local function Secret(v) return ns.IsSecret and ns.IsSecret(v) end

-- the newest session id the game has, or 0
local function NewestSession()
    local DM = API()
    if not (DM and DM.GetAvailableCombatSessions) then return 0 end
    local ok, list = pcall(DM.GetAvailableCombatSessions)
    if not ok or type(list) ~= "table" then return 0 end
    local top = 0
    for _, s in ipairs(list) do
        local id = s and s.sessionID
        if type(id) == "number" and not Secret(id) and id > top then top = id end
    end
    return top
end
GM.NewestSession = NewestSession

-- the sessions a segment covers: ids in (from, to]; with no session list
-- on this client, the "current" one
local function SessionsFor(c)
    local DM = API()
    local out = {}
    if DM.GetAvailableCombatSessions and DM.GetCombatSessionFromID then
        local ok, list = pcall(DM.GetAvailableCombatSessions)
        if ok and type(list) == "table" then
            local from, to = c._gmFrom or 0, c._gmTo or math.huge
            for _, s in ipairs(list) do
                local id = s and s.sessionID
                if type(id) == "number" and not Secret(id) and id > from and id <= to then
                    out[#out + 1] = id
                end
            end
        end
        return out, "id"
    end
    out[1] = 1                                  -- Enum.DamageMeterSessionType.Current
    return out, "type"
end

local function Session(DM, how, id, kind)
    local ok, s
    if how == "id" then ok, s = pcall(DM.GetCombatSessionFromID, id, kind)
    else ok, s = pcall(DM.GetCombatSessionFromType, id, kind) end
    if not ok or type(s) ~= "table" or type(s.combatSources) ~= "table" then return nil end
    return s
end

local function Spells(DM, how, id, kind, guid)
    if not guid then return nil end
    local fn = (how == "id") and DM.GetCombatSessionSourceFromID or DM.GetCombatSessionSourceFromType
    if not fn then return nil end
    local ok, s = pcall(fn, id, kind, guid)
    if not ok or type(s) ~= "table" or type(s.combatSpells) ~= "table" then return nil end
    return s.combatSpells
end

-- a source we can use: plain name and amount (never a secret)
local function Plain(src)
    if type(src) ~= "table" then return false end
    if Secret(src.name) or Secret(src.totalAmount) or Secret(src.sourceGUID) then return false end
    return type(src.name) == "string" and src.name ~= "" and type(src.totalAmount) == "number"
end

local function InGroup(src)
    if src.isLocalPlayer then return true end
    if src.sourceGUID and Roster.UnitOf(src.sourceGUID) then return true end
    return Roster.UnitByName(src.name) ~= nil
end

local function Actor(cont, src)
    local a = cont:GetOrCreate(src.name)
    if not a.class and type(src.classFilename) == "string" and src.classFilename ~= "" then
        a.class = src.classFilename
    end
    a.serial = a.serial or src.sourceGUID
    if InGroup(src) then a.grupo = true end
    if src.isLocalPlayer then a.isSelf = true end
    return a
end

-- the active seconds the game's own per-second figure implies for this
-- session's amount (the fight's length where it gives none), added to
-- what earlier sessions of the same segment gave
local function SetActivity(a, c, amt, aps)
    local secs
    if type(aps) == "number" and not Secret(aps) and aps > 0 then secs = amt / aps end
    if not secs then secs = GetTime() - (c.startTime or GetTime()) end
    secs = floor(secs + 0.5)
    local start = c.timeStart or time()
    local had = (a.endAct and (a.startAct or 0) > 0) and (a.endAct - a.startAct) or 0
    a.startAct = start
    a.endAct = start + had + secs
    a.started = false
end

local function AddSpells(a, list, heal)
    for _, sp in ipairs(list or {}) do
        local id, amt = sp.spellID, sp.totalAmount
        if type(id) == "number" and type(amt) == "number" and not Secret(id) and not Secret(amt) then
            local t = a.spells[id]
            if not t then
                t = heal and Meter.NewHealSpellTable(id) or Meter.NewSpellTable(id)
                t.name = GetSpellInfo and GetSpellInfo(id) or nil
                a.spells[id] = t
            end
            t.total = t.total + amt
        end
    end
end

-- Fill one segment from the game's sessions. False when the game's
-- numbers cannot be read now (in combat) - the caller waits.
function GM.Fill(c)
    if not c or c._gmFilled then return true end
    if not Readable() then return false end
    local DM = API()
    local T = Types()
    local ids, how = SessionsFor(c)
    local any = false
    for _, sid in ipairs(ids) do
        -- damage done, each ability under it
        local s = Session(DM, how, sid, T.damage)
        for _, src in ipairs(s and s.combatSources or {}) do
            if Plain(src) and src.totalAmount > 0 then
                local a = Actor(c.damage, src)
                a.total = a.total + src.totalAmount
                a.totalNoPet = a.totalNoPet + src.totalAmount
                c.totals.damage = c.totals.damage + src.totalAmount
                if a.grupo then c.groupTotals.damage = c.groupTotals.damage + src.totalAmount end
                SetActivity(a, c, src.totalAmount, src.amountPerSecond)
                AddSpells(a, Spells(DM, how, sid, T.damage, src.sourceGUID), false)
                any = true
            end
        end
        -- healing done
        s = Session(DM, how, sid, T.heal)
        for _, src in ipairs(s and s.combatSources or {}) do
            if Plain(src) and src.totalAmount > 0 then
                local a = Actor(c.heal, src)
                a.total = a.total + src.totalAmount
                c.totals.heal = c.totals.heal + src.totalAmount
                if a.grupo then c.groupTotals.heal = c.groupTotals.heal + src.totalAmount end
                SetActivity(a, c, src.totalAmount, src.amountPerSecond)
                AddSpells(a, Spells(DM, how, sid, T.heal, src.sourceGUID), true)
                any = true
            end
        end
        -- damage taken (on the damage actors, as the parser keeps it)
        s = Session(DM, how, sid, T.taken)
        for _, src in ipairs(s and s.combatSources or {}) do
            if Plain(src) and src.totalAmount > 0 then
                local a = Actor(c.damage, src)
                a.damageTaken = a.damageTaken + src.totalAmount
                any = true
            end
        end
        -- interrupts and dispels: counts
        for _, pair in ipairs({ { T.interrupt, "interrupt", "interrupt" }, { T.dispel, "dispell", "dispell" } }) do
            s = Session(DM, how, sid, pair[1])
            for _, src in ipairs(s and s.combatSources or {}) do
                if Plain(src) and src.totalAmount > 0 then
                    local a = Actor(c.misc, src)
                    local n = floor(src.totalAmount + 0.5)
                    a[pair[2]] = (a[pair[2]] or 0) + n
                    c.miscTotals[pair[3]] = c.miscTotals[pair[3]] + n
                    any = true
                end
            end
        end
        -- deaths, where the client counts them
        if T.deaths then
            s = Session(DM, how, sid, T.deaths)
            for _, src in ipairs(s and s.combatSources or {}) do
                if Plain(src) and src.totalAmount > 0 and InGroup(src) then
                    local a = Actor(c.misc, src)
                    local n = floor(src.totalAmount + 0.5)
                    a.dead = (a.dead or 0) + n
                    c.miscTotals.dead = c.miscTotals.dead + n
                    any = true
                end
            end
        end
    end
    c._gmFilled = true
    c.fromGameMeter = true
    if any then
        c.needRefresh.damage, c.needRefresh.heal, c.needRefresh.misc = true, true, true
    end
    return true
end

-- ============================================================
-- HOOKS - the segment's open and close
-- ============================================================
local origStart, origEnd = Meter.StartCombat, Meter.EndCombat
local held          -- { killed, fromEncounterEnd, at }: a close waiting for the end of combat

Meter.StartCombat = function(...)
    local was = Meter.inCombat
    origStart(...)
    if not was and Meter.inCombat and Meter.current then
        Meter.current._gmFrom = NewestSession()
    end
end

Meter.EndCombat = function(bossKilled, fromEncounterEnd)
    if not Meter.inCombat then return origEnd(bossKilled, fromEncounterEnd) end
    local c = Meter.current
    if not Readable() then
        -- still fighting: hold the close until combat ends (the boss's
        -- kill is kept on the segment, the end time is now)
        if not held then held = { at = GetTime() } end
        if fromEncounterEnd then
            held.killed, held.fromEncounterEnd = bossKilled, true
            if c and c.isBoss then c.isBoss.killed = bossKilled and true or false end
        end
        GM.Wait()
        return
    end
    local h = held
    held = nil
    c._gmTo = NewestSession()
    GM.Fill(c)
    if h then
        origEnd(h.killed, false)
        if h.at and c.startTime and h.at > c.startTime then c.endTime = h.at end
        if c.isBoss and h.fromEncounterEnd then c.isBoss.killed = h.killed and true or false end
    else
        origEnd(bossKilled, fromEncounterEnd)
    end
    if Meter.Windows and Meter.Windows.DirtyAll then Meter.Windows.DirtyAll() end
end

-- the held close, once out of combat
local waitFrame = CreateFrame("Frame")
waitFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if held and Meter.inCombat then Meter.EndCombat() end
end)
function GM.Wait() waitFrame:RegisterEvent("PLAYER_REGEN_ENABLED") end
function GM.Held() return held end

-- No combat log means no damage line to open a fight on: entering combat
-- opens it (an encounter's start opens it as before)
local openFrame = CreateFrame("Frame")
openFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
openFrame:SetScript("OnEvent", function()
    if not Meter.inCombat then Meter.StartCombat() end
end)
