-- ============================================================================
-- ZacUF - Heal.lua
-- One interface over every incoming-heal data source, so the renderer in
-- Elements.lua never talks to a library directly.
--
-- Adapters, in preference order:
--
--   1. LibHealPredict     - comms-free. Derives incoming heals locally from
--                           UnitGetIncomingHeals + aura scanning + combat log,
--                           so it sees EVERY healer in the raid regardless of
--                           what addons they run. Preferred when present.
--   2. LibHealComm-4.0    - peer-to-peer. Each caster's client broadcasts its
--                           own heals over the addon channel; exact amounts,
--                           but only for players also running an LHC addon.
--   3. native             - UnitGetIncomingHeals only. Direct casts, no caster
--                           attribution, no HoTs. Always available.
--
-- The renderer asks for one thing:
--
--     local list, n = ns.Heal:Query(targetGUID, unit, window, includeHots)
--     ... draw ...
--     ns.Heal:Release()
--
-- Each entry is { casterGUID, amount, endTime, isHot, generic }. `generic` marks
-- an unattributed lump (native adapter only) that should draw in the plain
-- incoming-heal color. Entries come back sorted by endTime - landing order.
--
-- Entry tables are pooled and handed back on Release(), so 40 raid frames
-- repainting on every health tick don't churn the garbage collector. Query() is
-- strictly synchronous and non-reentrant, so a single shared scratch list is safe.
-- ============================================================================
local ADDON, ns = ...

local Heal = {}
ns.Heal = Heal

-- ZacUI's shared services (the group roster); this part keeps a private
-- namespace, so they are reached through the global
local Z = _G.ZacUI

Heal.backend   = nil      -- human-readable label of the live adapter
Heal.perCaster = false    -- true when the backend attributes heals to casters
Heal.onChanged = nil      -- fn(targetGUID)   set by the renderer
Heal.onCaster  = nil      -- fn(casterGUID)   first time a caster is seen healing
Heal.onRoster  = nil      -- fn()             group composition changed; repaint all

local adapter              -- the live adapter table
local resolved = false
local playerGUID

local knownHealers = {}    -- casterGUID -> true, once seen healing (legend dots)
Heal.knownHealers = knownHealers

local spy = false          -- /zuf heal spy

-- ----------------------------------------------------------------------------
-- Entry pool + shared scratch
-- ----------------------------------------------------------------------------
local pool, scratch = {}, {}

local function acquire()
    local n = #pool
    if n > 0 then local e = pool[n]; pool[n] = nil; return e end
    return {}
end

local function push(casterGUID, amount, endTime, isHot, generic)
    local e = acquire()
    e.casterGUID, e.amount, e.endTime = casterGUID, amount, endTime
    e.isHot, e.generic = isHot or false, generic or false
    scratch[#scratch + 1] = e
    return e
end

function Heal:Release()
    for i = #scratch, 1, -1 do
        pool[#pool + 1] = scratch[i]
        scratch[i] = nil
    end
end

local function byEndTime(a, b) return a.endTime < b.endTime end

-- ----------------------------------------------------------------------------
-- Diagnostics helpers (shared by the /zuf heal subcommands)
-- ----------------------------------------------------------------------------
function Heal:CasterLabel(guid)
    if not guid then return "unattributed" end
    local _, class, _, _, _, name = GetPlayerInfoByGUID(guid)
    if name then return ("%s (%s)"):format(name, class or "?") end
    return "UNRESOLVED " .. tostring(guid)
end

function Heal:SpellLabel(spellID)
    if not spellID then return "spell ?" end
    if C_Spell and C_Spell.GetSpellInfo then
        local si = C_Spell.GetSpellInfo(spellID)
        if si and si.name then return si.name end
    end
    if GetSpellInfo then
        local n = GetSpellInfo(spellID)
        if n then return n end
    end
    return "spell " .. tostring(spellID)
end

function Heal:SetSpy(on)
    spy = on and true or false
    return spy
end

function Heal:GetSpy() return spy end

local function spyPrint(...)
    if spy then ns.Print(...) end
end

-- Fired by every adapter the first time a given caster is seen healing, so the
-- legend dot can appear on their frame.
local function noteCaster(casterGUID)
    if not casterGUID or knownHealers[casterGUID] then return end
    knownHealers[casterGUID] = true
    if Heal.onCaster then Heal.onCaster(casterGUID) end
end

local function changed(targetGUID)
    if targetGUID and Heal.onChanged then Heal.onChanged(targetGUID) end
end

-- ============================================================================
-- Adapter: LibHealComm-4.0
-- ============================================================================
local LHC = {}

-- Who is healing whom, per spell:  casterGUID -> targetGUID -> { [spellID] = endTime }
-- Keeping this keyed by SPELL matters: HealComm_HealStopped fires on successful
-- completion as well as interrupts, so dropping the whole (caster, target) pair
-- there is what makes a finished direct heal erase that healer's live HoTs.
local hc = {}
local lib
local ALL_FLAGS, NO_HOT_FLAGS

function LHC:Probe()
    lib = LibStub and LibStub("LibHealComm-4.0", true) or nil
    return lib ~= nil
end

function LHC:Start()
    ALL_FLAGS    = bit.bor(lib.DIRECT_HEALS, lib.HOT_HEALS, lib.CHANNEL_HEALS, lib.BOMB_HEALS)
    NO_HOT_FLAGS = bit.bor(lib.DIRECT_HEALS, lib.CHANNEL_HEALS, lib.BOMB_HEALS)

    local owner = {}

    -- Started / Updated / Delayed share a signature: targets are the varargs.
    local function apply(_, casterGUID, spellID, healType, endTime, ...)
        if spy then
            local t = {}
            for i = 1, select("#", ...) do t[#t + 1] = Heal:CasterLabel((select(i, ...))) end
            spyPrint(("spy: %s heals [%s] -> %s"):format(
                Heal:CasterLabel(casterGUID), Heal:SpellLabel(spellID), table.concat(t, ", ")))
        end
        -- On 1.15.9 the lib's aura-driven HoT path (unreachable before the
        -- Compat.lua shim) fires with a nil spellID. This map is only a trigger
        -- index - amounts are always re-queried from the lib - so folding those
        -- under a sentinel key is harmless, whereas erroring here shreds tracking.
        spellID = spellID or 0
        local ct = hc[casterGUID]
        if not ct then ct = {}; hc[casterGUID] = ct end
        for i = 1, select("#", ...) do
            local tg = select(i, ...)
            local spells = ct[tg]
            if not spells then spells = {}; ct[tg] = spells end
            spells[spellID] = endTime
            changed(tg)
        end
        noteCaster(casterGUID)
    end

    local function stop(_, casterGUID, spellID, healType, interrupted, ...)
        -- Guarded: the arguments are built before the call, so an unguarded
        -- spyPrint would run two API lookups and a string format on every heal
        -- that completes - which is every heal - with spy switched off.
        if spy then
            spyPrint(("spy: %s stopped [%s]%s"):format(
                Heal:CasterLabel(casterGUID), Heal:SpellLabel(spellID),
                interrupted and " (interrupted)" or ""))
        end
        spellID = spellID or 0
        local ct = hc[casterGUID]
        for i = 1, select("#", ...) do
            local tg = select(i, ...)
            if ct then
                local spells = ct[tg]
                if spells then
                    spells[spellID] = nil
                    if next(spells) == nil then ct[tg] = nil end
                end
            end
            changed(tg)
        end
        -- Drop the caster once nothing of theirs is pending anywhere. Without
        -- this, `hc` grows an empty table per healer seen this session, which
        -- Query then walks on every chip repaint of every frame.
        if ct and next(ct) == nil then hc[casterGUID] = nil end
    end

    lib.RegisterCallback(owner, "HealComm_HealStarted", apply)
    lib.RegisterCallback(owner, "HealComm_HealUpdated", apply)
    lib.RegisterCallback(owner, "HealComm_HealDelayed", apply)
    lib.RegisterCallback(owner, "HealComm_HealStopped", stop)
    lib.RegisterCallback(owner, "HealComm_ModifierChanged", function(_, guid) changed(guid) end)
    lib.RegisterCallback(owner, "HealComm_GUIDDisappeared", function(_, guid)
        -- Gone as a caster: forget their heals, repaint their former targets.
        local ct = hc[guid]
        if ct then
            hc[guid] = nil
            for tg in pairs(ct) do changed(tg) end
        end
        knownHealers[guid] = nil
        -- Gone as a target: drop them from every caster's book.
        for _, targets in pairs(hc) do targets[guid] = nil end
        changed(guid)
    end)
end

function LHC:Query(targetGUID, cutoff, includeHots)
    local flags = includeHots and ALL_FLAGS or NO_HOT_FLAGS
    local mod
    for casterGUID, targets in pairs(hc) do
        local spells = targets[targetGUID]
        if spells then
            local amount = lib:GetHealAmount(targetGUID, flags, cutoff, casterGUID)
            if amount and amount > 0 then
                mod = mod or lib:GetHealModifier(targetGUID) or 1
                -- Skip the HoT probe when HoTs are hidden: a pending-but-excluded
                -- HoT must not mis-flag (and dim) a pure direct heal as a HoT.
                local hotAmt = includeHots
                    and lib:GetHealAmount(targetGUID, lib.HOT_HEALS, cutoff, casterGUID) or nil
                -- Sort by this caster's earliest-landing pending heal on the target.
                local endTime
                for _, t in pairs(spells) do
                    if not endTime or t < endTime then endTime = t end
                end
                push(casterGUID, amount * mod, endTime or cutoff,
                     hotAmt ~= nil and hotAmt >= amount)
            elseif includeHots then
                -- HoTs were already included in the query above, so a zero here
                -- means nothing at all is pending: safe to prune.
                targets[targetGUID] = nil
            else
                -- HoTs were excluded, so re-ask for everything before pruning -
                -- otherwise hiding HoTs would also throw away the bookkeeping
                -- that makes them reappear when you switch them back on.
                local full = lib:GetHealAmount(targetGUID, ALL_FLAGS, cutoff, casterGUID)
                if not full or full <= 0 then targets[targetGUID] = nil end
            end
        end
    end
end

-- ============================================================================
-- Adapter: LibHealPredict-1.0
--
-- The library derives everything client-side, so it sees every healer in the
-- raid whether or not they run an addon. Its model differs from LibHealComm's
-- in three ways that this adapter reconciles:
--
--   1. It returns one entry per CAST SEGMENT (a direct heal, a channel, a single
--      upcoming HoT tick), not one per caster. ZacUF draws one chip per healer,
--      so segments are folded together by casterGUID here. That keeps the chip
--      cap, the overflow chip and the legend dot behaving identically no matter
--      which backend is live - which is the whole point of this file.
--   2. It has no look-ahead argument; the cutoff filter is applied here.
--   3. HoT tracking is a library-wide setting rather than a per-call flag, so
--      the "Show HoTs" option is pushed into the library when it changes.
--
-- AURA SCANNING IS OURS TO DRIVE. The library registers spellcast events,
-- UNIT_HEAL_PREDICTION and GROUP_ROSTER_UPDATE - but NOT UnitAura. Its
-- ScanAuras(unit) is a public method the consumer is expected to call, and
-- hotState (and therefore every "hot_tick" segment) stays empty until we do.
-- Without the driver below, HoTs silently do not exist on this backend. That is
-- the single biggest difference from LibHealComm, which tracked HoTs itself.
--
-- REENTRANCY: GetSegments() sweeps expired casts and fires
-- HealPredict_SegmentsChanged from inside itself, before returning. Since our
-- callback repaints frames, which calls GetSegments again, an unguarded adapter
-- recurses - and worse, the inner call wipes the shared segment table the outer
-- call is about to read. The inQuery guard below defers those notifications
-- until the current query has finished reading its results.
-- ============================================================================
local LHP = {}

local lhp
local inQuery = false
local deferred = {}          -- GUIDs whose repaint was postponed during a query
local deferAll = false       -- a roster-wide refresh was postponed during a query
local lastTrackHots, lastPreciseHots

function LHP:Probe()
    lhp = LibStub and LibStub("LibHealPredict-1.0", true) or nil
    if not lhp then return false end
    -- Only claim the backend if everything Query/Start needs is actually there,
    -- so a future breaking version of the library falls through to LibHealComm
    -- instead of erroring on every frame repaint.
    return type(lhp.GetSegments) == "function"
       and type(lhp.SetTrackHots) == "function"
       and type(lhp.SetPreciseHotTracking) == "function"
       and type(lhp.ScanAuras) == "function"
       and type(lhp.RegisterCallback) == "function"
end

-- The unit tokens whose auras are worth scanning: only units some frame
-- actually draws incoming heals for. The player frame (the default, and
-- often the only one) needs "player" alone - scanning all forty raid
-- members' buffs on every aura change, for one frame's HoT chips, was
-- the biggest cost in this file. A frame that can show anyone in the
-- group (target, target of target, party, raid) brings in the whole
-- group, from ZacUI's shared roster. A plain lookup table, rebuilt by
-- every full sweep and settings change, because the UNIT_AURA driver
-- below asks it for every aura change on every unit in view.
local rosterUnits = { player = true }

local function healOn(c) return c and c.enabled ~= false and c.healPrediction and true or false end

local function rebuildRoster()
    wipe(rosterUnits)
    local root = ns.db
    local fr = root and root.frames or {}
    if not root or healOn(fr.player) then rosterUnits.player = true end
    if root and (healOn(fr.target) or healOn(fr.targettarget)
            or healOn(root.party) or healOn(root.raid)) then
        rosterUnits.player = true
        local units = Z.Roster.Units()
        for i = 1, #units do rosterUnits[units[i]] = true end
    end
end

-- Whether the aura driver should run at all: the scan only feeds HoT ticks,
-- so with HoTs hidden, or no frame drawing incoming heals, it is wasted work.
-- Recomputed by Configure (start-up and every settings apply), never per event.
local scanOn = true

local function scanWanted(db)
    local root = ns.db
    if not root then return true end
    local heal = db or root.heal
    if heal and heal.hot and heal.hot.show == false then return false end
    if root.frames then
        for _, c in pairs(root.frames) do
            if c.enabled ~= false and c.healPrediction then return true end
        end
    end
    if root.party and root.party.enabled ~= false and root.party.healPrediction then return true end
    if root.raid and root.raid.enabled ~= false and root.raid.healPrediction then return true end
    return false
end

local function scanAll()
    if not lhp then return end
    rebuildRoster()
    for unit in pairs(rosterUnits) do lhp:ScanAuras(unit) end
end

-- Roster updates come in bursts (a raid forming is dozens in a row), and each
-- used to sweep the whole group twice - once from our event, once from the
-- library's callback. One short timer now collects them into a single sweep.
local scanAllArmed = false
local function requestScanAll()
    if scanAllArmed then return end
    scanAllArmed = true
    C_Timer.After(0.5, function()
        scanAllArmed = false
        scanAll()
    end)
end

function LHP:Start()
    local owner = {}

    local function segmentsChanged(_, destGUID)
        if not destGUID then return end
        if inQuery then
            deferred[destGUID] = true
            return
        end
        changed(destGUID)
    end

    lhp.RegisterCallback(owner, "HealPredict_SegmentsChanged", segmentsChanged)
    -- Roster changes can re-map every GUID, so repaint everything that is showing
    -- and re-scan auras for the new group. Deferred if it lands mid-query: a
    -- roster refresh repaints every frame, which would re-enter GetSegments and
    -- wipe the segment list the current query is still reading.
    lhp.RegisterCallback(owner, "HealPredict_RosterChanged", function()
        if inQuery then deferAll = true; return end
        if scanOn then requestScanAll() end
        if Heal.onRoster then Heal.onRoster() end
    end)

    -- The aura driver the library expects but does not provide. UNIT_AURA
    -- stays unfiltered (a raid is forty units; RegisterUnitEvent takes two),
    -- so the handler is one table lookup and the library call, nothing more.
    local auraFrame = CreateFrame("Frame")
    auraFrame:RegisterEvent("UNIT_AURA")
    auraFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    auraFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" then
            -- ScanAuras dedupes per unit per frame internally, so the raw event
            -- rate is fine; the unit filter is what keeps it off every mob.
            if scanOn and rosterUnits[unit] then lhp:ScanAuras(unit) end
        elseif scanOn then
            requestScanAll()
        end
    end)
    -- the group changed: a new set of tokens to sweep (shared roster,
    -- already coalesced)
    Z.Roster.On("ZacUF.HealScan", function()
        if scanOn then requestScanAll() end
    end)

    scanAll()
end

-- Push consumer-owned library settings. Called at start and from ApplySettings.
function LHP:Configure(db)
    if not lhp or not db then return end
    local precise = db.preciseHots and true or false
    if lastPreciseHots ~= precise then
        lhp:SetPreciseHotTracking(precise)
        lastPreciseHots = precise
    end
    -- the aura driver switches on with the first frame that draws heals and
    -- HoTs shown; coming back on takes a fresh sweep so running HoTs show
    local want = scanWanted(db) and true or false
    rebuildRoster()             -- which frames draw heals may have changed
    if want and not scanOn then requestScanAll() end
    scanOn = want
end

-- casterGUID -> folded entry for the query in progress. The entry tables are
-- pooled: this runs once per visible frame per repaint, and 40 raid frames
-- allocating a table per healer per health tick is exactly the kind of churn
-- this file exists to avoid.
local fold, foldPool = {}, {}

local function foldClear()
    for _, e in pairs(fold) do foldPool[#foldPool + 1] = e end
    wipe(fold)
end

local function foldGet()
    local n = #foldPool
    if n > 0 then local e = foldPool[n]; foldPool[n] = nil; return e end
    return {}
end

-- Deferred repaints are flushed on the NEXT frame, never inline. Flushing them
-- here would re-enter Heal:Query, whose stale-scratch guard would release the
-- entry list the current render is still holding.
local flushScheduled = false
local flushScratch = {}
local function scheduleFlush()
    if flushScheduled then return end
    if next(deferred) == nil and not deferAll then return end
    flushScheduled = true
    C_Timer.After(0, function()
        flushScheduled = false
        if deferAll then
            deferAll = false
            wipe(deferred)
            scanAll()
            if Heal.onRoster then Heal.onRoster() end
            return
        end
        local pending = flushScratch
        wipe(pending)
        for guid in pairs(deferred) do pending[#pending + 1] = guid end
        wipe(deferred)
        for i = 1, #pending do changed(pending[i]) end
    end)
end

-- casterGUID -> GetTime() when we last saw anything pending from them, on any
-- unit. Gives an honest "casters active right now" for the status line: folding
-- is per-unit, so foldCount alone would report whichever frame repainted last.
local seenAt = {}
local ACTIVE_WINDOW = 2

function LHP:Query(targetGUID, cutoff, includeHots, unit)
    if not unit then return end

    -- If a previous query threw between the guard being set and cleared, it would
    -- stay set forever and every repaint would silently drop into `deferred`.
    -- Clearing on entry makes that self-correcting on the next query.
    inQuery = false

    -- HoT tracking is a library-wide switch, not a per-call flag. Switching it
    -- OFF makes the next aura sweep discard all HoT state, so switching it back
    -- on needs a fresh scan - otherwise an already-ticking Renew stays invisible
    -- until somebody refreshes it.
    if lastTrackHots ~= includeHots then
        lhp:SetTrackHots(includeHots)
        local wasOff = (lastTrackHots == false)
        lastTrackHots = includeHots
        if includeHots and wasOff then scanAll() end
    end

    foldClear()
    local now = GetTime()

    -- GetSegments fires callbacks from inside itself and returns a table it
    -- reuses between calls, so guard against reentry and copy out immediately.
    inQuery = true
    local segs = lhp:GetSegments(targetGUID, unit)
    if segs then
        for i = 1, #segs do
            local s = segs[i]
            local cg, amt = s.casterGUID, s.amount
            local isHot = (s.kind == "hot_tick")
            local endTime = s.endTime or now
            -- A HoT tick's endTime is its next tick, which only advances on an
            -- aura scan or a combat-log tick. If either stalls it drifts into the
            -- past; clamping to now keeps an overdue tick sorting as "imminent"
            -- instead of ahead of everything real. Stale HoTs are removed by
            -- ScanAuras' mark-and-sweep, not by this filter.
            if endTime < now then endTime = now end
            if cg and amt and amt > 0
                and (includeHots or not isHot)
                and endTime <= cutoff then
                if spy then
                    spyPrint(("spy: %s %s %.0f -> %s"):format(
                        Heal:CasterLabel(cg), s.kind or "?", amt, Heal:CasterLabel(targetGUID)))
                end
                local e = fold[cg]
                if e then
                    e.amount = e.amount + amt
                    if endTime < e.endTime then e.endTime = endTime end
                    -- A caster reads as "HoT" only when everything pending from
                    -- them is a HoT; one direct heal makes the whole chip solid.
                    e.isHot = e.isHot and isHot
                else
                    e = foldGet()
                    e.amount, e.endTime, e.isHot = amt, endTime, isHot
                    fold[cg] = e

                end
            end
        end
    end
    inQuery = false

    for cg, e in pairs(fold) do
        push(cg, e.amount, e.endTime, e.isHot)
        noteCaster(cg)
        seenAt[cg] = now
    end

    scheduleFlush()
end

function LHP:ActiveCasters()
    local n, now = 0, GetTime()
    for cg, t in pairs(seenAt) do
        if now - t <= ACTIVE_WINDOW then n = n + 1 else seenAt[cg] = nil end
    end
    return n
end

-- ============================================================================
-- Adapter: native UnitGetIncomingHeals
-- Direct casts only, and the API reports totals rather than per-caster amounts,
-- so this yields at most two entries: yours, and one unattributed lump.
-- ============================================================================
local Native = {}

function Native:Probe() return UnitGetIncomingHeals ~= nil end
function Native:Start() end

function Native:QueryUnit(unit, now)
    local mine = UnitGetIncomingHeals(unit, "player") or 0
    local total = UnitGetIncomingHeals(unit) or 0
    -- hidden (WoW Forever): no maths on it, so no chips
    if issecretvalue ~= nil and (issecretvalue(mine) or issecretvalue(total)) then return end
    local others = total - mine
    if mine > 0 then push(playerGUID, mine, now, false, false) end
    if others > 0 then push(nil, others, now + 0.001, false, true) end
end

-- ----------------------------------------------------------------------------
-- Resolution
-- ----------------------------------------------------------------------------
local ORDER = {
    { LHP,    "LibHealPredict"   },
    { LHC,    "LibHealComm-4.0"  },
    { Native, "native"           },
}

-- LibHealComm-4.0 is only a fallback here, but it starts itself at login
-- and runs at full cost - combat log, every group member's auras, addon
-- comms - whoever reads it. On a class that can heal it stays on: that is
-- what broadcasts your heals to other players' heal addons. On any other
-- class, once LibHealPredict is the live backend, nothing needs it.
local HEALER_CLASS = { PALADIN = true, PRIEST = true, DRUID = true, SHAMAN = true }

local function silenceLibHealComm()
    local l = LibStub and LibStub("LibHealComm-4.0", true)
    if not l then return end
    -- the library is shared by every addon on the client: if any other
    -- addon (a heal-prediction raid frame, say) listens to it, leave it be
    local reg = l.callbacks and l.callbacks.events
    if reg then
        for _, subs in pairs(reg) do
            if next(subs) then return end
        end
    end
    if l.eventFrame then l.eventFrame:UnregisterAllEvents() end
    if l.bucketFrame then l.bucketFrame:Hide() end
    if l.hotMonitor then l.hotMonitor:Hide() end
end

function Heal:Resolve()
    if resolved then return end
    resolved = true
    playerGUID = UnitGUID("player")

    for _, def in ipairs(ORDER) do
        local a, label = def[1], def[2]
        if a:Probe() then
            adapter = a
            Heal.backend = label
            Heal.perCaster = (a ~= Native)
            a:Start()
            if a.Configure then a:Configure(ns.db and ns.db.heal) end
            break
        end
    end

    local _, class = UnitClass("player")
    if adapter == LHP and not HEALER_CLASS[class] then
        silenceLibHealComm()
        -- its own PLAYER_LOGIN start may land after ours; catch that too
        C_Timer.After(0, silenceLibHealComm)
    end

end

function Heal:Ready()
    if not resolved then self:Resolve() end
    return adapter ~= nil
end

-- Push consumer-owned settings into whichever library is live. Called from
-- ns.ApplySettings so an options change reaches the backend, not just the
-- renderer. A no-op for backends with nothing to configure.
function Heal:Configure()
    if adapter and adapter.Configure then adapter:Configure(ns.db and ns.db.heal) end
end

-- Collect every incoming heal landing on targetGUID within `window` seconds.
-- Returns the shared scratch list and its length, sorted by landing time.
-- The caller MUST call ns.Heal:Release() when finished with it.
function Heal:Query(targetGUID, unit, window, includeHots)
    if not resolved then self:Resolve() end
    -- Defensive: if a previous render errored out before Release(), stale entries
    -- would otherwise be drawn on top of this unit's real heals.
    if #scratch > 0 then self:Release() end
    if not adapter or not targetGUID then return scratch, 0 end
    local now = GetTime()
    if adapter == Native then
        Native:QueryUnit(unit, now)
    else
        adapter:Query(targetGUID, now + (window or 4), includeHots ~= false, unit)
    end
    local n = #scratch
    if n > 1 then table.sort(scratch, byEndTime) end
    return scratch, n
end

-- How many casters currently have heals in flight (status line). Each adapter
-- keeps its own bookkeeping, so ask whichever one is live.
function Heal:ActiveCasters()
    if adapter and adapter.ActiveCasters then return adapter:ActiveCasters() end
    local n = 0
    for _ in pairs(hc) do n = n + 1 end
    return n
end
