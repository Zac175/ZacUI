-- RM_Triggers - the declarative triggers of the Raid Mods engine: buff
-- and debuff watches, combat log filters, chat messages, items, and unit
-- checks (health, power, casts, "is my target this mob").
-- Part of ZacUI; load order is set by the TOC.
--
-- The custom-code triggers live in RM_Core (they are just functions the
-- event bus calls). Everything here is data: a trigger says what it
-- wants and this file turns game events into STATES in the unit's
-- trigger table, then asks the core to update.
--
-- PERF. UNIT_AURA never scans inline: it marks the unit dirty and a
-- 0.2 s ticker does the work: one read of each dirty unit's aura list,
-- matched against every trigger that means that unit, and only that
-- unit - the other 39 keep the answer they had. A state table is built
-- only when a unit's answer changed. The same ticker serves the
-- item-count and unit-health checks, woken only by events about a unit
-- a live check actually watches. Nothing here allocates per event. The
-- group comes from ns.Roster; combat log filters are indexed by
-- sub-event and fed by the core (one ns.CLEU reader).

local ns = _G.ZacUI
if not ns then return end
local RM = ns.RaidMods
if not RM then return end

local T = {}
RM.Triggers = T

local UnitAura_C = RM.UnitAura
local GetSpellInfo_C = RM.GetSpellInfo
local GetTime = GetTime
local Roster = ns.Roster
local strfind = string.find

-- ============================================================
-- REGISTRY OF LIVE DECLARATIVE TRIGGERS
-- ============================================================
-- live[kind] = { {inst, tindex, trig}, ... }
local live = { aura = {}, combatlog = {}, chat = {}, item = {}, unit = {} }
local function Add(kind, e) local l = live[kind] l[#l + 1] = e end
local function RemoveInst(inst)
    for _, l in pairs(live) do
        for i = #l, 1, -1 do if l[i].inst == inst then table.remove(l, i) end end
    end
end

local function Op(op, a, b)
    if a == nil or b == nil then return false end
    if op == "==" then return a == b end
    if op == "~=" then return a ~= b end
    if op == ">=" then return a >= b end
    if op == "<=" then return a <= b end
    if op == ">" then return a > b end
    if op == "<" then return a < b end
    return false
end

local function Changed(inst)
    RM.Update(inst)
end

-- ============================================================
-- AURA WATCH
-- ============================================================
-- which units a trigger means
local function UnitsOf(trig)
    local u = trig.unit
    if u == "group" then return "group" end
    if u == "nameplate" then return "nameplate" end
    return u   -- player, target, pet, focus, ...
end

local dirty = {}          -- [unitToken] = true
local dirtyAll = false
local ticker
local RescanTrigger       -- forward

local function NpcIdOf(unit)
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local id = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    return id and tonumber(id) or nil
end

-- match table per trigger: names -> true, ids -> true (resolved once)
local function Matcher(trig)
    if trig._m then return trig._m end
    local m = { names = {}, ids = {}, any = trig.any }
    for _, n in ipairs(trig.names or {}) do
        local num = tonumber(n)
        if num then
            m.ids[num] = true
            local nm = GetSpellInfo_C and GetSpellInfo_C(num)
            if nm then m.names[nm] = true end
        else
            m.names[n] = true
        end
    end
    for _, id in ipairs(trig.ids or {}) do m.ids[tonumber(id) or id] = true end
    trig._m = m
    return m
end

-- ONE PASS PER UNIT. A unit's buff list is read once per tick and
-- served to every trigger that looks at that unit (a raid of 40 with a
-- hundred group watches live would otherwise read the same list a
-- hundred times). The stamp is bumped wherever a scan starts from
-- outside the tick, so nothing is ever read from an older frame.
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
local scanStamp = 0
local caches = {}      -- [filter] = { unit, stamp, n, name = {}, icon = {}, ... }
local function Auras(unit, filter)
    local c = caches[filter]
    if not c then
        c = { n = 0, name = {}, icon = {}, stacks = {}, dispel = {}, dur = {}, exp = {}, caster = {}, id = {} }
        caches[filter] = c
    end
    if c.unit ~= unit or c.stamp ~= scanStamp then
        c.unit, c.stamp = unit, scanStamp
        local n = 0
        local cn, ci, cs, cd, cdu, ce, cc, cid = c.name, c.icon, c.stacks, c.dispel, c.dur, c.exp, c.caster, c.id
        for i = 1, 60 do
            local name, icon, stacks, dispel, duration, expires, caster, _, _, spellId = UnitAura_C(unit, i, filter)
            if not name then break end
            n = i
            cn[i], ci[i], cs[i], cd[i], cdu[i], ce[i], cc[i], cid[i] = name, icon, stacks, dispel, duration, expires, caster, spellId
        end
        c.n = n
    end
    return c
end

-- scan one unit's auras for one trigger: how many matched, and the
-- fields of the best match. Nothing is allocated here; the caller
-- builds a state table only when the answer differs from the last look.
local function ScanUnit(unit, trig)
    local m = Matcher(trig)
    local c = Auras(unit, trig.filter or "HELPFUL")
    local now = GetTime()
    local combine = trig.combine
    local cn, ci, cs, cd, cdu, ce, cc, cid = c.name, c.icon, c.stacks, c.dispel, c.dur, c.exp, c.caster, c.id
    local bName, bIcon, bStacks, bDispel, bDur, bExp, bCaster, bId, bRem
    local count = 0
    for i = 1, c.n do
        local name, stacks, dispel, expires, caster, spellId = cn[i], cs[i], cd[i], ce[i], cc[i], cid[i]
        local hit = m.any or m.names[name] or (spellId and m.ids[spellId])
        if hit and trig.ownOnly and caster ~= "player" then hit = false end
        if hit and trig.stacks and not Op(trig.stacks[1], stacks or 0, trig.stacks[2]) then hit = false end
        local rem
        if hit then
            rem = (expires and expires > 0) and (expires - now) or math.huge
            if trig.rem and not Op(trig.rem[1], rem, trig.rem[2]) then hit = false end
        end
        if hit and trig.debuffClass and dispel ~= trig.debuffClass then hit = false end
        if hit then
            count = count + 1
            local take = bName == nil
            if not take and combine == "showLowest" then take = rem < bRem end
            if not take and combine == "showHighest" then take = rem > bRem end
            if take then
                bName, bIcon, bStacks, bDispel, bDur, bExp, bCaster, bId, bRem = name, ci[i], stacks, dispel, cdu[i], expires, caster, spellId, rem
            end
        end
    end
    return count, bName, bIcon, bStacks, bDispel, bDur, bExp, bCaster, bId
end

local function Fill(st, unit, trig)
    st.show = true
    st.changed = true
    st.unit = unit
    st.GUID = UnitGUID(unit)
    st.unitName = UnitName(unit)
    st.progressType = "timed"
    if not (st.duration and st.duration > 0 and st.expirationTime and st.expirationTime > 0) then
        st.duration = 0
        st.expirationTime = math.huge
    end
    st.autoHide = false
    if trig.raidMark then st.raidMark = GetRaidTargetIndex(unit) end
    return st
end

local function GroupUnitOk(unit, trig)
    if trig.ignoreSelf and UnitIsUnit(unit, "player") then return false end
    if trig.ignoreDead and UnitIsDeadOrGhost(unit) then return false end
    if trig.ignoreDisconnected and not UnitIsConnected(unit) then return false end
    if trig.class then
        local _, c = UnitClass(unit)
        if not trig.class[c or ""] then return false end
    end
    if trig.npcId then
        if NpcIdOf(unit) ~= tonumber(trig.npcId) then return false end
    end
    return true
end

-- WHAT A TRIGGER REMEMBERS PER UNIT. On the live entry e: e.cnt[unit] =
-- how many auras matched, e.cand[unit] = the state that unit would show
-- (false for none), and the raw guid / name / expiry / stacks of the
-- best match (e.gd, e.nm, e.ex, e.sk). With that, a UNIT_AURA on raid7
-- costs one look at raid7: the other 39 units keep their answers, and
-- no table is built unless raid7's answer actually changed.
local function Forget(e, unit)
    e.cnt[unit], e.cand[unit], e.gd[unit], e.nm[unit], e.ex[unit], e.sk[unit] = nil, nil, nil, nil, nil, nil
end

-- one unit, one trigger: returns true when that unit's answer changed
local function ScanInto(e, unit)
    local trig, kind = e.trig, e.kind
    local cnt = e.cnt
    local had = cnt[unit] ~= nil
    local consider = UnitExists(unit)
    if consider and kind == "group" and not GroupUnitOk(unit, trig) then consider = false end
    if consider and kind == "nameplate" and trig.npcId and NpcIdOf(unit) ~= tonumber(trig.npcId) then consider = false end
    if not consider then
        if not had then return false end
        Forget(e, unit)
        return true
    end
    local count, name, icon, stacks, dispel, duration, expires, caster, spellId = ScanUnit(unit, trig)
    local guid = UnitGUID(unit)
    if had and cnt[unit] == count and e.gd[unit] == guid and e.nm[unit] == (name or false) and e.ex[unit] == expires and e.sk[unit] == stacks then
        return false
    end
    cnt[unit], e.gd[unit], e.nm[unit], e.ex[unit], e.sk[unit] = count, guid, name or false, expires, stacks
    local st
    if trig.perUnit then
        local mode = trig.perUnitMode or "affected"
        if (mode == "all") or (mode == "affected" and count > 0) or (mode == "unaffected" and count == 0) then
            st = {}
            if name then
                st.name, st.icon, st.stacks, st.dispelType, st.duration, st.expirationTime, st.unitCaster, st.spellId =
                    name, icon, stacks, dispel, duration, expires, caster, spellId
            end
            Fill(st, unit, trig)
            st.affected = count > 0
            st.matchCount = count
        end
    elseif name then
        st = { name = name, icon = icon, stacks = stacks, dispelType = dispel, duration = duration, expirationTime = expires,
            unitCaster = caster, spellId = spellId, unit = unit }
        Fill(st, unit, trig)
        st.matchCount = count
    end
    e.cand[unit] = st or false
    return true
end

-- the trigger's remembered answers -> its states table (the counting
-- conditions, "show on missing", hiding what went). Scratch tables are
-- shared: Settle is never re-entered before it is done with them.
local seen = {}
local function Put(e, states, unit, cid, st)
    seen[cid] = true
    local old = states[cid]
    if old == st then
        if st.show then return false end
    elseif old and old.show and not old.preview and old.name == st.name and old.expirationTime == st.expirationTime
        and old.stacks == st.stacks and old.unit == st.unit and old.GUID == st.GUID then
        -- the same thing is already on show: keep its table, and from
        -- now on compare against what is actually shown
        e.cand[unit] = old
        return false
    end
    st.show, st.changed, st._gone = true, true, nil
    states[cid] = st
    return true
end

local function Settle(e)
    local inst, trig = e.inst, e.trig
    local states = inst.tstates[e.t]
    local changed = false
    wipe(seen)
    local matchCount, unitCount = 0, 0
    for _, c in pairs(e.cnt) do
        unitCount = unitCount + 1
        if c > 0 then matchCount = matchCount + 1 end
    end
    local pass = true
    if trig.groupCount and not Op(trig.groupCount[1], matchCount, trig.groupCount[2]) then pass = false end
    if trig.matchCount and not Op(trig.matchCount[1], matchCount, trig.matchCount[2]) then pass = false end
    local showOn = trig.showOn or "showOnActive"
    if showOn == "showOnMissing" then
        if matchCount == 0 and pass then
            local st = states[""]
            if not (st and st.show and st.missing) then
                states[""] = { show = true, changed = true, missing = true, progressType = "timed", duration = 0, expirationTime = math.huge,
                    unit = trig.unit, matchCount = 0, unitCount = unitCount }
                changed = true
            end
            seen[""] = true
        end
    elseif showOn == "showAlways" and (matchCount == 0 or not pass) then
        local st = states[""]
        if not (st and st.show and st.always) then
            states[""] = { show = true, changed = true, always = true, progressType = "timed", duration = 0, expirationTime = math.huge,
                unit = trig.unit, matchCount = matchCount, unitCount = unitCount }
            changed = true
        end
        seen[""] = true
    elseif pass then
        local perUnit = e.perUnitCid
        for unit, st in pairs(e.cand) do
            if st and Put(e, states, unit, perUnit and unit or "", st) then changed = true end
        end
    end
    for cid, st in pairs(states) do
        if not seen[cid] and st.show then
            st.show = false
            st.changed = true
            changed = true
        end
    end
    for _, st in pairs(states) do st.matchCount = st.matchCount or matchCount st.unitCount = unitCount end
    if changed then Changed(inst) end
    -- remaining-time filters need a look again when the aura crosses the line
    if trig.rem then
        local soonest
        for _, st in pairs(states) do
            if st.show and st.expirationTime and st.expirationTime < math.huge then
                local at = st.expirationTime - trig.rem[2]
                if at > GetTime() and (not soonest or at < soonest) then soonest = at end
            end
        end
        if soonest then
            C_Timer.After(soonest - GetTime() + 0.05, function()
                if RM.loaded[inst.id] == inst then scanStamp = scanStamp + 1 RescanTrigger(e) end
            end)
        end
    end
end

-- every unit the trigger means, looked at again (load, roster change,
-- test mode ending): units that left the set are forgotten, the rest
-- keep their tables when nothing about them changed
local visited = {}
RescanTrigger = function(e)
    local trig, kind = e.trig, e.kind
    wipe(visited)
    if kind == "group" then
        local units = Roster.Units()
        for i = 1, #units do
            local unit = units[i]
            visited[unit] = true
            ScanInto(e, unit)
        end
    elseif kind == "nameplate" then
        local plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
        for _, p in ipairs(plates) do
            local unit = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
            if unit then visited[unit] = true ScanInto(e, unit) end
        end
    else
        visited[trig.unit] = true
        ScanInto(e, trig.unit)
    end
    for unit in pairs(e.cnt) do
        if not visited[unit] then Forget(e, unit) end
    end
    Settle(e)
end

-- is this unit token one of the group's (ns.Roster) right now?
local groupSet, groupSetVersion = {}, -1
local function InGroupSet(unit)
    local v = Roster.Version()
    if v ~= groupSetVersion then
        groupSetVersion = v
        wipe(groupSet)
        local units = Roster.Units()
        for i = 1, #units do groupSet[units[i]] = true end
    end
    return groupSet[unit] == true
end
-- the player's own raid token (UNIT_AURA for "player" means that one too)
local function PlayerRaidUnit()
    return Roster.UnitOf(UnitGUID("player"))
end

-- THE TICK. Dirty units are sorted once (group unit, nameplate, other),
-- then each is scanned for every trigger that means it, unit-outer so
-- the aura cache serves all of them; triggers whose answer moved are
-- settled afterwards. A roster change (dirtyAll) is a full rescan of
-- every trigger. Nothing here allocates: the dirty set is one of two
-- tables swapped each tick, wiped when done.
local spare = {}
local ukind = {}          -- scratch: dirty unit -> 1 group, 2 nameplate, 0 other
local touched = {}        -- scratch: triggers whose answers changed this tick
local pollDue = false
local function ScanDirty()
    scanStamp = scanStamp + 1
    local all = dirtyAll
    dirtyAll = false
    local units = dirty
    dirty, spare = spare, units
    if all or next(units) ~= nil then
        local list = live.aura
        if all then
            for i = 1, #list do
                local e = list[i]
                if RM.loaded[e.inst.id] == e.inst then RescanTrigger(e) end
            end
        else
            if units.player and IsInRaid() then
                local u = PlayerRaidUnit()
                if u then units[u] = true end
            end
            wipe(ukind)
            for unit in pairs(units) do
                if unit:sub(1, 9) == "nameplate" then ukind[unit] = 2
                elseif InGroupSet(unit) then ukind[unit] = 1
                else ukind[unit] = 0 end
            end
            wipe(touched)
            for unit in pairs(units) do
                local uk = ukind[unit]
                for i = 1, #list do
                    local e = list[i]
                    if RM.loaded[e.inst.id] == e.inst then
                        local kind = e.kind
                        if kind == "group" or kind == "nameplate" then
                            if uk == (kind == "group" and 1 or 2) and ScanInto(e, unit) then touched[e] = 1 end
                        elseif not touched[e] and (unit == e.trig.unit or UnitIsUnit(unit, e.trig.unit)) then
                            touched[e] = 2
                        end
                    end
                end
            end
            for e, how in pairs(touched) do
                if RM.loaded[e.inst.id] == e.inst then
                    if how == 1 then Settle(e) else RescanTrigger(e) end
                end
            end
            wipe(touched)
        end
    end
    wipe(units)
    -- an event asked for a fresh look at the items or unit checks
    if pollDue then
        pollDue = false
        T.PollItems()
        T.PollUnits()
    end
    if not next(dirty) and not dirtyAll and not pollDue then
        if ticker then ticker:Cancel() ticker = nil end
    end
end

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.2, ScanDirty)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "RaidMods aura scan") end
end
local function MarkDirty(unit)
    if unit then dirty[unit] = true else dirtyAll = true end
    StartTicker()
end
local function PollSoon()
    pollDue = true
    StartTicker()
end

-- ============================================================
-- COMBAT LOG
-- ============================================================
local function UnitMatches(spec, guid, name)
    if not spec then return true end
    if spec == "player" then return guid == RM.myGUID end
    if spec == "group" then
        if guid == RM.myGUID then return true end
        return Roster.UnitOf(guid) ~= nil
    end
    if spec == "target" then return guid == UnitGUID("target") end
    if spec == "pet" then return guid == UnitGUID("pet") end
    return true
end

-- the live filters by sub-event (rebuilt when a unit loads or unloads)
local clBySub = {}
function T.CombatLogSubs() return clBySub end

function T.CLEU(sub, ts, _, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, a12, a13, a14, a15, a16, a17)
    local list = clBySub[sub]
    if not list then return end
    for i = 1, #list do
        local e = list[i]
        local trig = e.trig
        if RM.loaded[e.inst.id] == e.inst then
            local ok = true
            local spellId, spellName
            if trig.prefix == "SPELL" or trig.prefix == "SPELL_PERIODIC" or trig.prefix == "SPELL_BUILDING" or trig.prefix == "RANGE" or trig.prefix == "DAMAGE_SHIELD" then
                spellId, spellName = a12, a13
            end
            if trig.spellId then
                ok = false
                for _, id in ipairs(trig.spellId) do if id == spellId then ok = true break end end
            end
            if ok and trig.spellName and spellName ~= trig.spellName then ok = false end
            if ok and trig.sourceName and srcName ~= trig.sourceName then ok = false end
            if ok and trig.destName and dstName ~= trig.destName then ok = false end
            if ok and trig.environmentalType and a12 ~= trig.environmentalType then ok = false end
            if ok and not UnitMatches(trig.sourceUnit, srcGUID, srcName) then ok = false end
            if ok and not UnitMatches(trig.destUnit, dstGUID, dstName) then ok = false end
            if ok then
                local states = e.inst.tstates[e.t]
                local cid = trig.clones and (dstGUID or "") or ""
                local st = states[cid] or {}
                st.show = true
                st.changed = true
                st.spellId, st.spellName = spellId, spellName
                st.sourceGUID, st.sourceName, st.destGUID, st.destName = srcGUID, srcName, dstGUID, dstName
                st.sourceFlags, st.destFlags, st.destRaidFlags = srcFlags, dstFlags, dstRaidFlags
                st.name = spellName or srcName
                st.icon = spellId and GetSpellInfo_C and select(3, GetSpellInfo_C(spellId)) or nil
                st.raidTargetIndex = dstRaidFlags and dstRaidFlags > 0 and (math.floor(math.log(dstRaidFlags) / math.log(2)) + 1) or nil
                if trig.duration and trig.duration > 0 then
                    st.progressType = "timed"
                    st.duration = trig.duration
                    st.expirationTime = GetTime() + trig.duration
                    st.autoHide = true
                else
                    st.progressType = "timed"
                    st.duration = 0
                    st.expirationTime = math.huge
                end
                states[cid] = st
                Changed(e.inst)
            end
        end
    end
end

-- ============================================================
-- CHAT
-- ============================================================
local function ChatMatch(trig, text)
    if not trig.message then return true end
    if trig.op == "find('%s')" then return text:find(trig.message, 1, true) ~= nil end
    if trig.op == "match('%s')" then return text:match(trig.message) ~= nil end
    return text == trig.message
end
local function OnChat(event, text, sender, ...)
    local list = live.chat
    for i = 1, #list do
        local e = list[i]
        local trig = e.trig
        if RM.loaded[e.inst.id] == e.inst and trig.event == event and ChatMatch(trig, text or "") then
            if not trig.sourceName or (sender and (trig.sourceOp == "find('%s')" and sender:find(trig.sourceName, 1, true) or sender == trig.sourceName)) then
                local states = e.inst.tstates[e.t]
                local cid = trig.clones and (sender or "") or ""
                local st = states[cid] or {}
                st.show = true
                st.changed = true
                st.message, st.sender, st.name = text, sender, sender
                if trig.duration and trig.duration > 0 then
                    st.progressType = "timed"
                    st.duration = trig.duration
                    st.expirationTime = GetTime() + trig.duration
                    st.autoHide = true
                else
                    st.progressType = "timed"
                    st.duration = 0
                    st.expirationTime = math.huge
                end
                states[cid] = st
                Changed(e.inst)
            end
        end
    end
end

-- ============================================================
-- ITEMS
-- ============================================================
-- Where each watched item was last seen (an equipment slot, or a bag
-- and slot). The 0.5 s poll checks that spot first and only walks the
-- 18 slots and the five bags again when the item moved or the bags
-- changed (BAG_UPDATE_DELAYED / PLAYER_EQUIPMENT_CHANGED wipe this).
local itemLoc = {}
local function ItemCooldown(item)
    local GetNum = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    local GetId = C_Container and C_Container.GetContainerItemID or GetContainerItemID
    local GetCd = C_Container and C_Container.GetContainerItemCooldown or GetContainerItemCooldown
    local loc = itemLoc[item]
    if loc then
        if loc.bag then
            if GetId(loc.bag, loc.slot) == item then return GetCd(loc.bag, loc.slot) end
        elseif GetInventoryItemID("player", loc.slot) == item then
            return GetInventoryItemCooldown("player", loc.slot)
        end
        itemLoc[item] = nil
    end
    -- equipped first, then the bags (no GetItemCooldown on this client)
    for slot = 1, 18 do
        if GetInventoryItemID("player", slot) == item then
            itemLoc[item] = { slot = slot }
            local start, duration, enable = GetInventoryItemCooldown("player", slot)
            return start, duration, enable
        end
    end
    for bag = 0, 4 do
        for slot = 1, (GetNum(bag) or 0) do
            if GetId(bag, slot) == item then
                itemLoc[item] = { bag = bag, slot = slot }
                return GetCd(bag, slot)
            end
        end
    end
    return 0, 0, 1
end

local function EvalItem(e)
    local trig = e.trig
    local states = e.inst.tstates[e.t]
    local st = states[""]
    local show = false
    local timedAt, timedDur
    if trig.what == "count" then
        local n = GetItemCount(trig.item, false, trig.charges and true or false) or 0
        show = Op((trig.count or { ">", 0 })[1], n, (trig.count or { ">", 0 })[2])
        if show then
            st = st or {}
            st.count, st.stacks = n, n
        end
    elseif trig.what == "equipped" then
        show = IsEquippedItem(trig.item) and true or false
    elseif trig.what == "cooldown" then
        local start, duration = ItemCooldown(trig.item)
        local onCd = start and start > 0 and duration and duration > 1.5
        if trig.showOn == "showOnReady" then show = not onCd
        elseif trig.showOn == "showAlways" then show = true
        else show = onCd and true or false end
        if show and onCd then timedAt, timedDur = start + duration, duration end
    end
    local changed = false
    if show then
        if not st or not st.show then
            st = st or {}
            st.show = true
            st.changed = true
            changed = true
        end
        local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(trig.item)
        st.name, st.icon, st.itemId = name, icon, trig.item
        if timedAt then
            if st.expirationTime ~= timedAt then changed = true end
            st.progressType, st.expirationTime, st.duration = "timed", timedAt, timedDur
        else
            st.progressType, st.duration, st.expirationTime = "timed", 0, math.huge
        end
        states[""] = st
    elseif st and st.show then
        st.show = false
        st.changed = true
        changed = true
    end
    if changed then Changed(e.inst) end
end

function T.PollItems()
    local list = live.item
    for i = 1, #list do
        local e = list[i]
        if RM.loaded[e.inst.id] == e.inst then EvalItem(e) end
    end
end

-- ============================================================
-- UNIT CHECKS
-- ============================================================
local function PercentOk(list, v)
    if not list then return true end
    for _, c in ipairs(list) do if not Op(c[1], v, c[2]) then return false end end
    return true
end

-- the nameplate list is asked for once per poll and shared by every
-- nameplate trigger (GetNamePlates builds a new table on every call)
local pollPlates

local function UnitState(unit)
    local st = { unit = unit, GUID = UnitGUID(unit), unitName = UnitName(unit), name = UnitName(unit) }
    local _, class = UnitClass(unit)
    st.class = class
    st.health, st.maxhealth = UnitHealth(unit), UnitHealthMax(unit)
    st.percenthealth = st.maxhealth > 0 and (st.health / st.maxhealth * 100) or 0
    st.power, st.maxpower = UnitPower(unit), UnitPowerMax(unit)
    st.percentpower = st.maxpower > 0 and (st.power / st.maxpower * 100) or 0
    st.npcId = NpcIdOf(unit)
    st.raidMark = GetRaidTargetIndex(unit)
    st.progressType = "static"
    st.value, st.total = st.health, st.maxhealth
    return st
end

local function UnitOk(trig, unit)
    if not UnitExists(unit) then return false end
    if trig.npcId then
        local id = NpcIdOf(unit)
        local ok = false
        for _, n in ipairs(trig.npcId) do if n == id then ok = true break end end
        if not ok then return false end
    end
    if trig.attackable ~= nil then
        if (UnitCanAttack("player", unit) and true or false) ~= (trig.attackable and true or false) then return false end
    end
    if trig.what == "health" then
        local hp, max = UnitHealth(unit), UnitHealthMax(unit)
        if not PercentOk(trig.percent, max > 0 and hp / max * 100 or 0) then return false end
        if not PercentOk(trig.health, hp) then return false end
    elseif trig.what == "power" then
        local p, max = UnitPower(unit, trig.powerType), UnitPowerMax(unit, trig.powerType)
        if not PercentOk(trig.percent, max > 0 and p / max * 100 or 0) then return false end
    end
    return true
end

local function CastState(unit, trig)
    local name, _, icon, startMS, endMS, _, _, _, spellId = UnitCastingInfo(unit)
    local channel = false
    if not name then
        name, _, icon, startMS, endMS, _, _, spellId = UnitChannelInfo(unit)
        channel = name and true or false
    end
    if not name then return nil end
    if trig.spellIds then
        local ok = false
        for _, id in ipairs(trig.spellIds) do if id == spellId or id == name then ok = true break end end
        if not ok then return nil end
    end
    local st = UnitState(unit)
    st.name, st.icon, st.spellId = name, icon, spellId
    st.progressType = "timed"
    st.duration = (endMS - startMS) / 1000
    st.expirationTime = endMS / 1000
    st.inverse = not channel
    st.castType = channel and "channel" or "cast"
    return st
end

-- one EvalUnit at a time: its scratch lives here instead of a new table
-- and closure per call (the polls run several times a second)
local evSeen, evStates, evChanged = {}, nil, false
local function Put(cid, st)
    evSeen[cid] = true
    local old = evStates[cid]
    st.show = true
    st.changed = true
    if old and old.show and old.GUID == st.GUID and old.name == st.name and old.expirationTime == st.expirationTime
        and old.percenthealth == st.percenthealth and old.percentpower == st.percentpower then
        return
    end
    evStates[cid] = st
    evChanged = true
end

local function EvalUnit(e)
    local trig = e.trig
    local states = e.inst.tstates[e.t]
    wipe(evSeen)
    evStates, evChanged = states, false
    if trig.unit == "nameplate" then
        local plates = pollPlates
        if not plates then
            plates = C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}
            pollPlates = plates
        end
        for _, p in ipairs(plates) do
            local unit = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
            if unit and UnitOk(trig, unit) then
                if trig.what == "cast" then
                    local st = CastState(unit, trig)
                    if st then Put(unit, st) end
                else
                    Put(unit, UnitState(unit))
                end
            end
        end
    elseif trig.what == "conditions" and trig.always then
        Put("", UnitState(trig.unit))
    else
        local unit = trig.unit
        if UnitOk(trig, unit) then
            if trig.what == "cast" then
                local st = CastState(unit, trig)
                if st then Put("", st) end
            else
                local st = UnitState(unit)
                if trig.duration and trig.duration > 0 then
                    local old = states[""]
                    if old and old.show then
                        st.progressType, st.duration, st.expirationTime, st.autoHide = old.progressType, old.duration, old.expirationTime, old.autoHide
                    else
                        st.progressType, st.duration, st.expirationTime, st.autoHide = "timed", trig.duration, GetTime() + trig.duration, true
                    end
                end
                Put("", st)
            end
        end
    end
    local changed = evChanged
    for cid, st in pairs(states) do
        if not evSeen[cid] and st.show then
            st.show = false
            st.changed = true
            changed = true
        end
    end
    evStates = nil
    if changed then Changed(e.inst) end
end

-- static entries (an "always" check on a unit that draws nothing - the
-- packs' way of keeping a controller loaded) are answered once, on load
function T.PollUnits()
    local list = live.unit
    pollPlates = nil
    for i = 1, #list do
        local e = list[i]
        if not e.static and RM.loaded[e.inst.id] == e.inst then EvalUnit(e) end
    end
    pollPlates = nil
end

-- ============================================================
-- GAME EVENTS THE DECLARATIVE TRIGGERS NEED
-- ============================================================
local frame = CreateFrame("Frame")
local registered = {}
local function Reg(ev)
    if registered[ev] then return end
    registered[ev] = true
    pcall(frame.RegisterEvent, frame, ev)
end
local function Unreg(ev)
    if not registered[ev] then return end
    registered[ev] = nil
    pcall(frame.UnregisterEvent, frame, ev)
end

-- the unit tokens the live (polled) unit checks look at: a unit event
-- about anyone else (39 raid members' mana ticks) wakes nothing
local unitWatch = {}
local function Watched(unit)
    if not unit then return false end
    if unitWatch[unit] then return true end
    return unitWatch.nameplate == true and strfind(unit, "nameplate", 1, true) == 1
end

local function AnyLive() return #live.aura > 0 or #live.unit > 0 or #live.item > 0 end

frame:SetScript("OnEvent", function(_, event, a1, a2, ...)
    if event == "UNIT_AURA" then
        if #live.aura > 0 then MarkDirty(a1) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if #live.aura > 0 then MarkDirty("target") end
        if unitWatch.target then PollSoon() end
    elseif event == "UNIT_PET" then
        if unitWatch.pet and a1 == "player" then PollSoon() end
    elseif event == "UNIT_HEALTH" or event == "UNIT_POWER_UPDATE" or event == "UNIT_FLAGS"
        or event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        if Watched(a1) then PollSoon() end
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        if #live.aura > 0 then MarkDirty(a1) end
        if unitWatch.nameplate then PollSoon() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if #live.aura > 0 then MarkDirty(nil) end
        if #live.unit > 0 or #live.item > 0 then PollSoon() end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        wipe(itemLoc)
        if #live.item > 0 then PollSoon() end
    elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        if #live.item > 0 then PollSoon() end
    elseif event:match("^CHAT_MSG_") then
        OnChat(event, a1, a2, ...)
    end
end)

-- the group changed (ns.Roster, once per burst): group watches look at
-- every member again, the polled checks look again
Roster.On("RaidMods.triggers", function()
    if #live.aura > 0 then MarkDirty(nil) end
    if #live.unit > 0 or #live.item > 0 then PollSoon() end
end)

-- the unit polls keep going while a polled check is live; the aura
-- scanner only while something is dirty
local pollTicker
local AURA_EVENTS = { "UNIT_AURA", "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }
local UNIT_EVENTS = { "UNIT_PET", "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_FLAGS", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED" }
local chatWant = {}
local function RefreshEvents()
    local wantAura = #live.aura > 0
    local wantItem = #live.item > 0
    -- which units the polled checks watch; which item checks need the
    -- cooldown events (counts and "equipped" only need the bag/gear ones)
    wipe(unitWatch)
    local wantUnit, wantItemCd = false, false
    for _, e in ipairs(live.unit) do
        if not e.static then
            wantUnit = true
            unitWatch[e.trig.unit or "player"] = true
        end
    end
    for _, e in ipairs(live.item) do
        if e.trig.what == "cooldown" then wantItemCd = true end
    end
    for _, ev in ipairs(AURA_EVENTS) do
        if wantAura or wantUnit then Reg(ev) else Unreg(ev) end
    end
    if AnyLive() then Reg("PLAYER_ENTERING_WORLD") else Unreg("PLAYER_ENTERING_WORLD") end
    for _, ev in ipairs(UNIT_EVENTS) do
        if wantUnit then Reg(ev) else Unreg(ev) end
    end
    if wantItem then Reg("BAG_UPDATE_DELAYED") Reg("PLAYER_EQUIPMENT_CHANGED")
    else Unreg("BAG_UPDATE_DELAYED") Unreg("PLAYER_EQUIPMENT_CHANGED") end
    if wantItemCd then Reg("BAG_UPDATE_COOLDOWN") Reg("SPELL_UPDATE_COOLDOWN")
    else Unreg("BAG_UPDATE_COOLDOWN") Unreg("SPELL_UPDATE_COOLDOWN") end
    wipe(chatWant)
    for _, e in ipairs(live.chat) do chatWant[e.trig.event] = true end
    for ev in pairs(registered) do
        if ev:match("^CHAT_MSG_") and not chatWant[ev] then Unreg(ev) end
    end
    for ev in pairs(chatWant) do Reg(ev) end
    -- the combat log filters by sub-event (the core asks ns.CLEU for them)
    wipe(clBySub)
    for _, e in ipairs(live.combatlog) do
        local sub = e.sub
        local l = clBySub[sub]
        if not l then l = {} clBySub[sub] = l end
        l[#l + 1] = e
    end
    -- health / power / cast checks and item cooldowns are polled: a
    -- steady 0.5 s look while any is live (their events only wake the
    -- fast scan)
    local wantPoll = wantUnit or wantItemCd
    if wantPoll and not pollTicker then
        pollTicker = C_Timer.NewTicker(0.5, function()
            T.PollUnits()
            T.PollItems()
        end)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(pollTicker, "RaidMods unit poll") end
    elseif not wantPoll and pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end
end

-- ============================================================
-- HOOKS THE CORE CALLS
-- ============================================================
function T.Attach(inst)
    local any = false
    for i, trig in ipairs(inst.def.triggers) do
        if trig.kind ~= "custom" and live[trig.kind] then
            local e = { inst = inst, t = i, trig = trig }
            if trig.kind == "aura" then
                e.kind = UnitsOf(trig)
                -- one clone per unit, or the single "" state
                e.perUnitCid = (trig.perUnit or trig.clones or e.kind == "group" or e.kind == "nameplate") and true or false
                e.cnt, e.cand, e.gd, e.nm, e.ex, e.sk = {}, {}, {}, {}, {}, {}
            elseif trig.kind == "combatlog" then
                e.sub = (trig.prefix or "") .. (trig.suffix or "")
            elseif trig.kind == "unit" then
                -- an "always" check on a unit that draws nothing only has
                -- to say "shown" once; it is not polled
                e.static = (trig.what == "conditions" and trig.always and RM.IsSilent and RM.IsSilent(inst.def)) and true or nil
            end
            Add(trig.kind, e)
            any = true
        end
    end
    if not any then return end
    RefreshEvents()
    T.Rescan(inst)
end

-- a fresh look at everything declarative on one unit (after loading, and
-- when test mode ends)
function T.Rescan(inst)
    scanStamp = scanStamp + 1
    for _, e in ipairs(live.aura) do if e.inst == inst then RescanTrigger(e) end end
    for _, e in ipairs(live.item) do if e.inst == inst then EvalItem(e) end end
    for _, e in ipairs(live.unit) do if e.inst == inst then EvalUnit(e) end end
end

function T.Detach(inst)
    RemoveInst(inst)
    RefreshEvents()
end

-- test mode: every declarative trigger shows one sample state
function T.Preview(inst)
    local changed = false
    for i, trig in ipairs(inst.def.triggers) do
        if trig.kind ~= "custom" then
            local states = inst.tstates[i]
            local st = states[""] or {}
            st.show = true
            st.changed = true
            st.preview = true
            st.name = st.name or "Test"
            st.icon = st.icon or 134400
            st.unit = st.unit or "player"
            st.unitName = UnitName("player")
            st.GUID = RM.myGUID
            st.stacks = st.stacks or 3
            st.count = st.count or 3
            st.progressType = "timed"
            st.duration = 10
            st.expirationTime = GetTime() + 10
            st.autoHide = false
            states[""] = st
            changed = true
        end
    end
    if changed then Changed(inst) end
end
