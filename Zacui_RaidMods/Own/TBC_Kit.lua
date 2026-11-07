-- TBC_Kit - how ZacUI builds its TBC Anniversary boss modules.
-- Part of ZacUI (Zacui_RaidMods); load order is set by the TOC.
--
-- The Classic Era raids came with a piece per display, each written out
-- in full. The TBC raids are written the other way round: each raid's
-- _Data file is a list of facts about its bosses (spell ids, timings
-- with their source, what to say), and T.Build turns those facts into
-- the same kind of pieces the Era raids have, on the same engine:
--
--   a controller per timed ability  WA_NUMEN_TIMER key, seconds, count
--   one boss-timer list             K.TimerBars (and the emphasized list)
--   one berserk bar                 K.Berserk
--   heads-up texts                  "BLAST NOVA 5.0", spoken once
--   call-outs                       a cast or a debuff, said out loud
--   "on you" icons                  a debuff on you, its time and a word
--   raid-frame marks                a debuff on someone, on their frame
--   nameplate timers                a buff on a mob, on its plate
--   phase calls                     the boss's health crossing a line
--   form / phase cycles             timed swaps (Nalorakk, Netherspite)
--   raid marks                      raid leader only, as on Era
--
-- A raid's behaviour file (Own\<RAID>.lua) hands T.Build anything that
-- raid needs on top. Only the facts in the _Data files are per raid; no
-- timing is made up here - an ability whose timing no source states
-- gets its call-out and no bar.
--
-- Loaded on every game, but only does anything when ZacUI runs as TBC
-- (RM.Own.flavor, the developer override included).
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
if not (RM and RM.Own and RM.Own.on and RM.Own.Kit) then return end
local O, K = RM.Own, RM.Own.Kit

local T = { facts = {}, order = {} }
O.TBC = T
T.on = O.flavor == "tbc"
if not T.on then return end

local C = O.CODE
local GetTime, pairs, ipairs, type, tostring, tonumber = GetTime, pairs, ipairs, type, tostring, tonumber

-- ============================================================
-- SMALL PIECES
-- ============================================================

-- Speech: short, at the speech volume the raid packs read, a touch fast.
function T.Say(text)
    if type(text) ~= "string" or text == "" then return end
    RM.Speak(text, _G.FJIDS_SFX_VOLUME or 75, 1.2)
end

-- The start action every call-out shares: say what its state carries.
local function SayState(env)
    local st = env.state
    if st and st.say then T.Say(st.say) end
end

-- "KZ" + "Shade of Aran" + "Flame Wreath" -> "KZ_SHADE_OF_ARAN_FLAME_WREATH"
local function Key(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local s = tostring((select(i, ...))):upper():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
        parts[#parts + 1] = s
    end
    return table.concat(parts, "_")
end
T.Key = Key

-- the icon of a spell, else the question mark the engine uses
local QUESTION = 134400
local function IconOf(spells, icon)
    if icon then return icon end
    if spells and spells[1] and GetSpellTexture then
        local tex = GetSpellTexture(spells[1])
        if tex then return tex end
    end
    return QUESTION
end
T.IconOf = IconOf

-- A creature's id from its GUID, as a number.
local function Npc(guid)
    if type(guid) ~= "string" then return nil end
    return tonumber((select(6, strsplit("-", guid))))
end
T.Npc = Npc

-- Is this ENCOUNTER_START our boss's? By encounter id when the raid has
-- them, else by the encounter's name (Zul'Aman: no encounter id we could
-- confirm, so its pieces load for the whole zone and wait for their name).
function T.IsBoss(boss, encId, encName)
    if boss.enc then return encId == boss.enc end
    if type(encName) ~= "string" then return false end
    local n = encName:lower()
    for _, want in ipairs(boss.encNames or { boss.name }) do
        if n == want:lower() then return true end
    end
    return false
end

-- A matcher for combat-log lines and plates. spec fields:
--   spells   spell ids                  names   spell names (English)
--   subs     sub-events (a set)         from    only these creatures' casts
--   onlyMe   only when it lands on you  seen    { npcs = {...}, names = {...} }:
--            the first sight of each new one of these mobs counts
--   deaths   { npcs = {...} }: each of them dying counts
local function Matcher(s)
    local ids, names = K.Set(s.spells), K.Set(s.names)
    local from = s.from and K.Set(s.from)
    local seenNpc = s.seen and K.Set(s.seen.npcs)
    local seenName = s.seen and K.Set(s.seen.names)
    local deaths = s.deaths and K.Set(s.deaths.npcs)
    local m = {}
    -- true, destGUID, destName when the line is one of ours
    function m.Line(env, sub, srcGUID, srcName, dstGUID, dstName, spellId, spellName)
        if deaths and sub == "UNIT_DIED" then
            if deaths[Npc(dstGUID)] then return true, dstGUID, dstName end
            return false
        end
        if seenNpc and srcGUID and not env.known[srcGUID] then
            if seenNpc[Npc(srcGUID)] or seenName[srcName] then
                env.known[srcGUID] = true
                return true, srcGUID, srcName
            end
        end
        if not (ids[spellId] or names[spellName]) then return false end
        if from and not from[Npc(srcGUID)] then return false end
        if s.onlyMe and dstGUID ~= RM.myGUID then return false end
        return true, dstGUID, dstName
    end
    -- a plate coming into view: a new one of the mobs we wait for?
    function m.Plate(env, unit)
        if not (seenNpc and unit) then return false end
        local guid = UnitGUID(unit)
        if not guid or env.known[guid] then return false end
        if seenNpc[Npc(guid)] or seenName[UnitName(unit) or ""] then
            env.known[guid] = true
            return true
        end
        return false
    end
    m.wantsPlates = seenNpc ~= nil
    return m
end

-- the sub-events a spec listens to
local function Subs(s, default)
    local subs = {}
    if s.spells or s.names then
        for _, sub in ipairs(s.subs or { s.sub or default }) do subs[#subs + 1] = sub end
    end
    if s.seen then
        local have = K.Set(subs)
        for _, sub in ipairs({ "SPELL_CAST_START", "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED" }) do
            if not have[sub] then subs[#subs + 1] = sub end
        end
    end
    if s.deaths then subs[#subs + 1] = "UNIT_DIED" end
    return subs
end

local ENDS = { "ENCOUNTER_END", "WA_FJI_ENCOUNTER_END" }

-- the events a piece's trigger listens to
local function Events(subs, extra, plates)
    local ev = { "ENCOUNTER_START", "ENCOUNTER_END", "WA_FJI_ENCOUNTER_END" }
    local have = K.Set(ev)
    for _, sub in ipairs(subs or {}) do
        local e = "CLEU:" .. sub
        if not have[e] then have[e] = true ev[#ev + 1] = e end
    end
    for _, e in ipairs(extra or {}) do
        if not have[e] then have[e] = true ev[#ev + 1] = e end
    end
    if plates and not have.NAME_PLATE_UNIT_ADDED then ev[#ev + 1] = "NAME_PLATE_UNIT_ADDED" end
    return ev
end

-- ============================================================
-- BEHAVIOURS
-- ============================================================

-- THE ABILITY CONTROLLER. An invisible piece per timed ability: puts its
-- countdown on the bus (WA_NUMEN_TIMER key, seconds, count), says when it
-- went off (key, 0, count) and starts the next. Spec (from the facts):
--   key, first (seconds from the pull), every (seconds between),
--   steps ({ s1, s2, ... }: the gap after the 1st, 2nd... cast; nothing
--   after the last), prewarn (seconds before each one: WA_<KEY>_PREWARN
--   lead, count), gap (two hits closer than this are one, default 2),
--   startOn / stopOn (bus events), plus the matcher's fields.
function T.Ability(boss, a)
    local key = a.key
    local m = Matcher(a)
    local gap = a.gap or 2
    local PREWARN = "WA_" .. key .. "_PREWARN"
    local stopOn = K.Set(a.stopOn)
    local function Countdown(secs, count, guid)
        RM.Fire("WA_NUMEN_TIMER", key, secs, count, guid)
    end
    local function Quiet(env)
        if env.headsTimer then env.headsTimer:Cancel() env.headsTimer = nil end
    end
    local function Schedule(env, secs)
        Quiet(env)
        if not secs or secs <= 0 then return end
        local count = env.count
        if a.prewarn then
            local lead = a.prewarn
            if secs <= lead then
                RM.Fire(PREWARN, secs, count)
            else
                env.headsTimer = C_Timer.NewTimer(secs - lead, function()
                    env.headsTimer = nil
                    RM.Fire(PREWARN, lead, count)
                end)
            end
        end
        Countdown(secs, count)
    end
    local function Stop(env)
        env.running = false
        Quiet(env)
        Countdown(nil)
        if a.prewarn then RM.Fire(PREWARN .. "_CANCEL") end
    end
    local function NextGap(env)
        if a.steps then return a.steps[env.count - 1] end
        return a.every
    end
    local function Went(env, guid)
        local now = GetTime()
        if now - (env.last or 0) < gap then return false end
        env.last = now
        Countdown(0, env.count, guid)
        env.count = env.count + 1
        Schedule(env, NextGap(env))
        return true
    end
    local map = {}
    map["init"] = function(env)
        env.key = key
        env.count = 1
        env.last = 0
        env.known = {}
        -- loaded for its encounter: the fight is on already
        env.running = boss.enc ~= nil and RM.encounterId == boss.enc
    end
    map["triggers.1.trigger"] = function(env, allstates, event, ...)
        if event == "ENCOUNTER_START" then
            local encId, encName = ...
            if not T.IsBoss(boss, encId, encName) then return false end
            env.count, env.last, env.running = 1, 0, true
            wipe(env.known)
            if a.first and not a.startOn then Schedule(env, a.first) end
            return false
        end
        if event == "ENCOUNTER_END" or event == "WA_FJI_ENCOUNTER_END" or stopOn[event] then
            Stop(env)
            return false
        end
        if a.startOn and event == a.startOn then
            env.running = true
            Schedule(env, a.first)
            return false
        end
        if not env.running then return false end
        if event == "NAME_PLATE_UNIT_ADDED" then
            if m.Plate(env, (...)) then Went(env) end
            return false
        end
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            local _, sub, _, srcGUID, srcName, _, _, dstGUID, dstName, _, _, spellId, spellName = ...
            local hit, guid = m.Line(env, sub, srcGUID, srcName, dstGUID, dstName, spellId, spellName)
            if hit then Went(env, guid) end
        end
        return false
    end
    map["actions.finish.custom"] = function(env) Stop(env) end
    return map, Subs(a, "SPELL_CAST_SUCCESS"), m.wantsPlates
end

-- A CYCLE: timed phases that follow each other (Netherspite's portals
-- and banish, Nalorakk's forms, Supremus' kiting). Starts on the pull,
-- or after a number of deaths (startDeaths = { npcs, count }), or on a
-- bus event (startOn); each part shows its countdown on the boss-timer
-- list and, when it comes, its call-out here. loop: go round again.
function T.Cycle(boss, c)
    local parts = c.parts
    local stopOn = K.Set(c.stopOn)
    local dead = c.startDeaths and K.Set(c.startDeaths.npcs)
    local function Off(env)
        if env.cycleTimer then env.cycleTimer:Cancel() env.cycleTimer = nil end
        for _, p in ipairs(parts) do RM.Fire("WA_NUMEN_TIMER", p.key, nil) end
        env.running = false
    end
    local Start
    Start = function(env, i)
        local p = parts[i]
        if not p then return end
        RM.Fire("WA_NUMEN_TIMER", p.key, p.secs, nil)
        env.cycleTimer = C_Timer.NewTimer(p.secs, function()
            env.cycleTimer = nil
            RM.Fire("WA_NUMEN_TIMER", p.key, 0, nil)
            RM.Fire("WA_TBC_CYCLE_" .. c.key, i, p.alert, p.say)
            local nexti = i + 1
            if not parts[nexti] and c.loop then nexti = 1 end
            if parts[nexti] then Start(env, nexti) else env.running = false end
        end)
    end
    local map = {}
    map["init"] = function(env)
        env.deaths = 0
        env.running, env.started = false, false
    end
    map["triggers.1.trigger"] = function(env, allstates, event, ...)
        if event == "OPTIONS" then
            K.Put(allstates, "", K.Timed(3, { name = parts[1].alert, icon = c.icon, autoHide = true }))
            return true
        end
        if event == "ENCOUNTER_START" then
            local encId, encName = ...
            if not T.IsBoss(boss, encId, encName) then return false end
            Off(env)
            env.deaths, env.started = 0, false
            if not (dead or c.startOn) then env.running, env.started = true, true Start(env, 1) end
            return false
        end
        if event == "ENCOUNTER_END" or event == "WA_FJI_ENCOUNTER_END" or stopOn[event] then
            Off(env)
            return K.Drop(allstates, "")
        end
        if c.startOn and event == c.startOn and not env.started then
            env.running, env.started = true, true
            Start(env, 1)
            return false
        end
        if event == "COMBAT_LOG_EVENT_UNFILTERED" and dead then
            local _, sub, _, _, _, _, _, dstGUID = ...
            if sub == "UNIT_DIED" and dead[Npc(dstGUID)] and not env.started then
                env.deaths = env.deaths + 1
                if env.deaths >= c.startDeaths.count then
                    env.running, env.started = true, true
                    Start(env, 1)
                end
            end
            return false
        end
        if event == "WA_TBC_CYCLE_" .. c.key then
            local _, alert, say = ...
            if not alert then return false end
            K.Put(allstates, "", K.Timed(3, { name = alert, say = say, icon = c.icon, autoHide = true }))
            return true
        end
    end
    map["actions.start.custom"] = SayState
    map["actions.finish.custom"] = function(env)
        if not RM.encounterId then Off(env) end
    end
    local subs = dead and { "UNIT_DIED" } or {}
    local extra = { "WA_TBC_CYCLE_" .. c.key }
    if c.startOn then extra[#extra + 1] = c.startOn end
    for _, e in ipairs(c.stopOn or {}) do extra[#extra + 1] = e end
    return map, subs, extra
end

-- A CALL-OUT: a cast, a debuff or an add, said on screen for a moment
-- (and out loud). Spec: the matcher's fields, text (what it says),
-- target (add "on <name>"), me / sayMe (what it says when it is you),
-- say (spoken for everyone), onlyMe, dur (default 3), gap (default 1),
-- once (once per pull: a phase that shows itself by its first spell).
function T.Alert(boss, s)
    local m = Matcher(s)
    -- a cast with no sub-event given: its start or, for an instant one,
    -- its success - one call-out for both
    local both = not (s.sub or s.subs)
    if both then s.subs = { "SPELL_CAST_START", "SPELL_CAST_SUCCESS" } end
    local dur, gap = s.dur or 3, s.gap or (both and 5) or 1
    local icon = IconOf(s.spells, s.icon)
    local map = {}
    map["init"] = function(env)
        env.last = 0
        env.known = {}
        env.running = boss.enc ~= nil and RM.encounterId == boss.enc
    end
    local function Show(allstates, text, say)
        K.Put(allstates, "", K.Timed(dur, { name = text, say = say, icon = icon, autoHide = true }))
        return true
    end
    map["triggers.1.trigger"] = function(env, allstates, event, ...)
        if event == "OPTIONS" then
            return Show(allstates, s.text)
        end
        if event == "ENCOUNTER_START" then
            local encId, encName = ...
            if T.IsBoss(boss, encId, encName) then env.running, env.last, env.done = true, 0, nil wipe(env.known) end
            return false
        end
        if event == "ENCOUNTER_END" or event == "WA_FJI_ENCOUNTER_END" then
            env.running = false
            return K.Drop(allstates, "")
        end
        if not env.running or env.done then return false end
        local hit, guid, who
        if event == "NAME_PLATE_UNIT_ADDED" then
            hit = m.Plate(env, (...))
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            local _, sub, _, srcGUID, srcName, _, _, dstGUID, dstName, _, _, spellId, spellName = ...
            hit, guid, who = m.Line(env, sub, srcGUID, srcName, dstGUID, dstName, spellId, spellName)
        end
        if not hit then return false end
        local now = GetTime()
        if now - env.last < gap then return false end
        env.last = now
        if s.once then env.done = true end
        local mine = guid ~= nil and guid == RM.myGUID
        if mine and s.me then return Show(allstates, s.me, s.sayMe or s.say) end
        local text = s.text
        if s.target and who then text = text .. " on " .. Ambiguate(who, "short") end
        return Show(allstates, text, s.say)
    end
    map["actions.start.custom"] = SayState
    return map, Subs(s, "SPELL_CAST_START"), m.wantsPlates
end

-- A HEADS-UP: "BLAST NOVA 5.0" for the last seconds before an ability,
-- told its length by the controller's PREWARN event, spoken once. It goes
-- when the ability goes off or its countdown stops - or a few seconds
-- after it was due, when the ability never came.
local GRACE = 4
function T.Heads(a)
    local key = a.key
    local on, cancel = "WA_" .. key .. "_PREWARN", "WA_" .. key .. "_PREWARN_CANCEL"
    local icon = IconOf(a.spells, a.icon)
    local map = {}
    map["triggers.1.trigger"] = function(env, allstates, event, k, secs)
        if event == "OPTIONS" then
            K.Put(allstates, "", K.Timed(a.prewarn, { icon = icon, say = nil }))
            return true
        end
        if event == on then
            local lead = k   -- PREWARN carries (seconds, count)
            if env.dropTimer then env.dropTimer:Cancel() end
            env.dropTimer = C_Timer.NewTimer(lead + GRACE, function()
                env.dropTimer = nil
                RM.Fire(cancel)
            end)
            K.Put(allstates, "", K.Timed(lead, { icon = icon, say = a.headsSay }))
            return true
        end
        if event == cancel or event == "ENCOUNTER_END" or event == "WA_FJI_ENCOUNTER_END"
            or (event == "WA_NUMEN_TIMER" and k == key and (secs == 0 or secs == nil)) then
            if env.dropTimer then env.dropTimer:Cancel() env.dropTimer = nil end
            return K.Drop(allstates, "")
        end
    end
    map["actions.start.custom"] = SayState
    return map, { on, cancel, "WA_NUMEN_TIMER", "ENCOUNTER_END", "WA_FJI_ENCOUNTER_END" }
end

-- PHASE CALLS: the boss's health, read twice a second while its fight
-- runs (never from an event), crossing the lines the facts give. A line
-- says "<text> soon" a few percent before (soon = true) and "<text>" when
-- it is crossed, and fires WA_TBC_PHASE_<BOSS> n for anything waiting on
-- that phase. The boss is found by its creature id or name among the
-- boss, target, focus and nameplate units.
local LOOK = { "boss1", "boss2", "boss3", "boss4", "boss5", "target", "focus" }
for i = 1, 40 do LOOK[#LOOK + 1] = "nameplate" .. i end
local function FindBoss(env, h)
    local u = env.bossUnit
    local function Is(unit)
        local guid = UnitGUID(unit)
        if not guid then return false end
        if h.npc and Npc(guid) == h.npc then return true end
        if h.unitName and UnitName(unit) == h.unitName then return true end
        return false
    end
    if u and Is(u) then return u end
    for i = 1, #LOOK do
        if Is(LOOK[i]) then env.bossUnit = LOOK[i] return LOOK[i] end
    end
    env.bossUnit = nil
end
local SOON = 3
function T.Health(boss, h)
    local event = "WA_TBC_HP_" .. h.key
    local phaseEvent = "WA_TBC_PHASE_" .. h.key
    local function Look(env)
        local unit = FindBoss(env, h)
        if not unit then return end
        local hp, mx
        if ns.SafeHealth then hp, mx = ns.SafeHealth(unit) else hp, mx = UnitHealth(unit), UnitHealthMax(unit) end
        if not (hp and mx and mx > 0) then return end
        RM.Fire(event, hp / mx * 100)
    end
    local function Stop(env)
        if env.ticker then env.ticker:Cancel() env.ticker = nil end
    end
    local function Go(env)
        Stop(env)
        env.ticker = C_Timer.NewTicker(0.5, function() Look(env) end)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(env.ticker, "rm.tbc.hp") end
    end
    local map = {}
    map["init"] = function(env)
        env.passed, env.warned = {}, {}
        if boss.enc and RM.encounterId == boss.enc then Go(env) end
    end
    local function Show(allstates, text, say)
        K.Put(allstates, "", K.Timed(4, { name = text, say = say, autoHide = true }))
        return true
    end
    map["triggers.1.trigger"] = function(env, allstates, ev, ...)
        if ev == "OPTIONS" then return Show(allstates, h.marks[1].text) end
        if ev == "ENCOUNTER_START" then
            local encId, encName = ...
            if not T.IsBoss(boss, encId, encName) then return false end
            env.passed, env.warned = {}, {}
            Go(env)
            return false
        end
        if ev == "ENCOUNTER_END" or ev == "WA_FJI_ENCOUNTER_END" then
            Stop(env)
            return K.Drop(allstates, "")
        end
        if ev ~= event then return false end
        local pct = ...
        local shown = false
        for i, mk in ipairs(h.marks) do
            if not env.passed[i] then
                if pct <= mk.at then
                    env.passed[i], env.warned[i] = true, true
                    RM.Fire(phaseEvent, i)
                    shown = Show(allstates, mk.text, mk.say)
                elseif mk.soon and not env.warned[i] and pct <= mk.at + SOON then
                    env.warned[i] = true
                    shown = Show(allstates, mk.text .. " SOON", mk.saySoon)
                end
            end
        end
        local all = true
        for i = 1, #h.marks do if not env.passed[i] then all = false break end end
        if all then Stop(env) end
        return shown
    end
    map["actions.start.custom"] = SayState
    map["actions.finish.custom"] = function(env) if not RM.encounterId then Stop(env) end end
    return map, { event }
end

-- RAID MARKS (raid leader or assist, like the Era pieces): whoever a
-- spell lands on gets the mark; it comes off again when the spell does.
-- Several at once take the marks in the order the options give.
function T.Mark(boss, s)
    local ids, names = K.Set(s.spells), K.Set(s.names)
    local map = {}
    map["init"] = function(env)
        env.given = {}
        env.free = {}
        local opt = env.config.group.option
        for _, k in ipairs({ "firstMark", "secondMark", "thirdMark" }) do
            if opt[k] and opt[k] ~= 9 then env.free[#env.free + 1] = opt[k] end
        end
    end
    local function UnitFor(guid)
        local u = ns.Roster and ns.Roster.UnitOf and ns.Roster.UnitOf(guid)
        if u then return u end
        for unit in RM.IterateGroup() do
            if UnitGUID(unit) == guid then return unit end
        end
    end
    map["triggers.1.trigger"] = function(env, allstates, event, ...)
        if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then return false end
        local opt = env.config.group.option
        if not opt.enable then return false end
        if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return false end
        local _, sub, _, _, _, _, _, dstGUID, _, _, _, spellId, spellName = ...
        if not (ids[spellId] or names[spellName]) then return false end
        local unit = UnitFor(dstGUID)
        if not unit then return false end
        if sub == "SPELL_AURA_APPLIED" then
            if env.given[dstGUID] then return false end
            for _, mark in ipairs(env.free) do
                local taken = false
                for _, g in pairs(env.given) do if g == mark then taken = true break end end
                if not taken then
                    SetRaidTarget(unit, mark)
                    env.given[dstGUID] = mark
                    break
                end
            end
        elseif sub == "SPELL_AURA_REMOVED" then
            local mark = env.given[dstGUID]
            if mark then
                env.given[dstGUID] = nil
                if GetRaidTargetIndex(unit) == mark then SetRaidTarget(unit, 0) end
            end
        end
        return false
    end
    return map, { "SPELL_AURA_APPLIED", "SPELL_AURA_REMOVED" }
end

-- The berserk warning: thirty seconds left, then berserk, on screen and
-- spoken.
local function BerserkWarn()
    local map = {}
    map["triggers.1.trigger"] = function(env, allstates, event)
        if event == "OPTIONS" then
            K.Put(allstates, "", K.Timed(4, { name = "BERSERK IN 30", autoHide = true }))
            return true
        end
        if event == "WA_FOJJI_BERSERK_30" then
            K.Put(allstates, "", K.Timed(4, { name = "BERSERK IN 30", say = "Berserk in thirty", autoHide = true }))
            return true
        end
        if event == "WA_FOJJI_BERSERK" then
            K.Put(allstates, "", K.Timed(4, { name = "BERSERK", say = "Berserk", autoHide = true }))
            return true
        end
        if event == "ENCOUNTER_END" or event == "WA_FJI_ENCOUNTER_END" then return K.Drop(allstates, "") end
    end
    map["actions.start.custom"] = SayState
    return map
end

-- ============================================================
-- HOW THE PIECES LOOK (settings, the house style of the Era raids)
-- ============================================================
local FONT = "Barlow Semi Condensed Black"
local P_FMT = { format = "timed", time_dynamic_threshold = 5, time_format = 0, time_legacy_floor = false, time_mod_rate = true, time_precision = 1 }
local function Sub(point, text, size, color, x, y)
    return { type = "subtext", anchor_point = point, text_text = text, text_font = FONT, text_fontSize = size or 12,
        text_fontType = "OUTLINE", text_color = color or { 1, 1, 1, 1 }, text_shadowColor = { 0, 0, 0, 1 },
        text_shadowXOffset = 1, text_shadowYOffset = -1, text_anchorXOffset = x or 0, text_anchorYOffset = y or 0,
        text_automaticWidth = "Auto", text_fixedWidth = 64, text_justify = "CENTER", text_selfPoint = "AUTO",
        text_visible = true, text_wordWrap = "WordWrap", rotateText = "NONE", fmt = { p = P_FMT, s = { format = "none" }, n = { format = "none" } } }
end
local function Border(area, color)
    return { type = "subborder", anchor_area = area, border_color = color or { 0, 0, 0, 1 }, border_edge = "Square Full White",
        border_offset = 0, border_size = 1, border_visible = true }
end
local FADE = { start = { type = "preset", preset = "fade", duration_type = "seconds", easeType = "none", easeStrength = 3 },
    finish = { type = "preset", preset = "fade", duration_type = "seconds", easeType = "none", easeStrength = 3 } }

-- a boss-timer bar: icon, name and count on the left, time on the right
local function BarD(w, h, color, subs)
    return { regionType = "aurabar", anchorFrameType = "SCREEN", anchorPoint = "CENTER", selfPoint = "CENTER",
        width = w, height = h, icon = true, iconSource = -1, icon_side = "LEFT", icon_color = { 1, 1, 1, 1 }, zoom = 0.32,
        texture = "ZacUI Flat", textureSource = "LSM", barColor = color, barColor2 = { 1, 1, 0, 1 },
        backgroundColor = { 0, 0, 0, 0.36 }, orientation = "HORIZONTAL", inverse = false, frameStrata = 1, alpha = 1,
        font = FONT, fontSize = 12, outline = "OUTLINE", customTextUpdate = "event", animation = FADE,
        xOffset = 0, yOffset = 0, subRegions = subs }
end
local D = {}
T.D = D
function D.Timers(color)
    return BarD(220, 20, color, { { type = "subbackground" }, { type = "subforeground" }, Border("bar"), Border("icon"),
        Sub("RIGHT", "%p"), Sub("LEFT", "%n %c", 12, nil, 5), Sub("CENTER", "%text", 12, nil, 8) })
end
function D.Berserk()
    return BarD(200, 18, { 1, 0.42, 0.44, 1 }, { { type = "subbackground" }, { type = "subforeground" }, Border("bar"),
        Sub("RIGHT", "%p"), Sub("CENTER", "Berserk") })
end
-- a big line of text: "%i BLAST NOVA 5.0"
function D.Text(text, size, color)
    return { regionType = "text", anchorFrameType = "SCREEN", anchorPoint = "CENTER", selfPoint = "BOTTOM",
        displayText = text, font = FONT, fontSize = size or 20, outline = "OUTLINE", color = color or { 1, 1, 1, 1 },
        justify = "CENTER", automaticWidth = "Auto", fixedWidth = 200, wordWrap = "WordWrap", customTextUpdate = "event",
        shadowColor = { 0, 0, 0, 1 }, shadowXOffset = 1, shadowYOffset = -1, frameStrata = 1, animation = FADE,
        fmt = { p = P_FMT, n = { format = "none" } }, subRegions = { { type = "subbackground" } }, xOffset = 0, yOffset = 0 }
end
-- nothing on screen (a controller)
function D.Silent()
    return { regionType = "text", anchorFrameType = "SCREEN", anchorPoint = "CENTER", selfPoint = "BOTTOM", displayText = "",
        font = FONT, fontSize = 12, outline = "OUTLINE", color = { 1, 1, 1, 1 }, justify = "LEFT", frameStrata = 1,
        subRegions = { { type = "subbackground" } }, xOffset = 0, yOffset = 0 }
end
-- the "on you" picture: the debuff's icon, its time, one word under it
function D.OnYou(label, color)
    return { regionType = "icon", anchorFrameType = "SCREEN", anchorPoint = "CENTER", selfPoint = "CENTER",
        width = 60, height = 60, icon = true, iconSource = -1, displayIcon = "", zoom = 0.24, keepAspectRatio = false,
        cooldown = true, cooldownSwipe = true, cooldownEdge = false, cooldownTextDisabled = true, color = { 1, 1, 1, 1 },
        frameStrata = 1, alpha = 1, animation = FADE, xOffset = 0, yOffset = 0,
        subRegions = { { type = "subbackground" }, Border(nil, color or { 1, 0.2, 0.2, 1 }), Sub("CENTER", "%p", 14),
            Sub("INNER_TOPRIGHT", "%s", 14, { 0, 1, 0.91, 1 }), Sub("OUTER_BOTTOM", label or "", 12, nil, 0, -6) } }
end
-- the small icon on a raid frame
function D.RaidFrame()
    return { regionType = "icon", anchorFrameType = "UNITFRAME", anchorPoint = "CENTER", selfPoint = "CENTER",
        width = 16, height = 16, icon = true, iconSource = 0, displayIcon = "", zoom = 0.3, cooldown = false,
        color = { 1, 1, 1, 1 }, frameStrata = 6, alpha = 1, xOffset = 0, yOffset = 0,
        subRegions = { { type = "subbackground" }, Border(nil), Sub("CENTER", "%p", 12, { 1, 0.94, 0, 1 }) } }
end
-- a timer on a mob's nameplate
function D.Plate()
    return { regionType = "icon", anchorFrameType = "NAMEPLATE", anchorPoint = "BOTTOM", selfPoint = "TOP",
        width = 32, height = 32, icon = true, iconSource = -1, displayIcon = "", zoom = 0.32, cooldown = true,
        cooldownSwipe = true, cooldownTextDisabled = true, color = { 1, 1, 1, 1 }, frameStrata = 1, alpha = 1,
        xOffset = 0, yOffset = -10,
        subRegions = { { type = "subbackground" }, Border(nil, { 1, 0.98, 0.66, 1 }), Sub("CENTER", "%p", 16, { 1, 0.84, 0, 1 }) } }
end

-- the colours of the boss-timer list (0-255, as K.TimerBars takes them)
local BAR_COLOR = { 78, 167, 255, 0.75 }
local TANK_COLOR = { 255, 150, 80, 0.75 }
local PHASE_COLOR = { 157, 223, 255, 0.75 }
local SELF_COLOR = { 255, 70, 85, 0.8 }

-- ============================================================
-- BUILD: facts -> groups, pieces and their behaviour
-- ============================================================
-- facts = { key, name, short, zone = { instanceID }, bosses = { ... } }
-- extras (from the raid's behaviour file) = { [pieceId] = slot map },
-- merged over what the facts make.
function T.Build(raidKey, extras)
    local R = T.facts[raidKey]
    if not R then return end
    local Dd = O.Data(raidKey)
    local B = {}
    local name = R.name
    local zone = R.zone
    local encounters, allEnc = {}, {}
    for _, boss in ipairs(R.bosses) do
        if boss.enc then
            encounters[boss.enc] = boss.name
            allEnc[#allEnc + 1] = boss.enc
        end
    end
    Dd.raid = { key = raidKey, name = name, short = R.short, zone = zone, encounters = encounters, tbc = true }

    -- groups
    local G = {}
    local function Group(def)
        def.raid = raidKey
        def.name = def.name or def.key
        def.scale, def.frameStrata = 1, 1
        def.selfPoint = def.selfPoint or "CENTER"
        def.anchorPoint = def.anchorPoint or "CENTER"
        def.xOffset, def.yOffset = def.xOffset or 0, def.yOffset or 0
        Dd.G(def)
        G[def.key] = def
        return def.key
    end
    local function List(key, anchor, point, grow, limit, sort)
        return Group({ key = key, kind = "dynamicgroup", anchor = anchor, anchorFrameType = "SELECTFRAME", anchorPoint = point,
            selfPoint = point, grow = grow, align = "CENTER", sort = sort or "none", space = (grow == "LEFT" and 2) or 0,
            limit = limit, useLimit = true, visible = true, gridType = "RD", gridWidth = 5, rowSpace = 1, columnSpace = 1, stagger = 0 })
    end
    local gTimers = List(name .. ": Boss Timers", "BossTimers", "BOTTOM", "UP", 6, "ascending")
    local gEmph = List(name .. ": Boss Timers Emphasize", "BossTimersEmphasize", "TOP", "DOWN", 3)
    local gBerserk = List(name .. ": Berserk Timers", "BerserkTimers", "BOTTOM", "UP", 6, "ascending")
    local gWarn = List(name .. ": Special Warnings", "SpecialWarnings", "TOP", "DOWN", 2)
    local gAlert = List(name .. ": Special Alerts", "SpecialAlerts", "TOP", "DOWN", 2)
    local gIcons = List(name .. ": Large Icons", "LargeIcons", "RIGHT", "LEFT", 3)
    local gCtl = Group({ key = name .. ": Controllers", kind = "group" })
    local gAuto = Group({ key = name .. ": Automation", kind = "group" })
    local gPlates = Group({ key = name .. ": Nameplates", kind = "group" })
    local gRFParent = Group({ key = name .. ": Raid Frames", kind = "group" })
    local gRF = Group({ key = "RF:" .. name .. " Debuffs", kind = "dynamicgroup", anchorPerUnit = "UNITFRAME", useAnchorPerUnit = true,
        grow = "HORIZONTAL", align = "CENTER", sort = "none", space = 0, limit = 5, useLimit = false, parent = gRFParent,
        gridType = "RD", gridWidth = 5, rowSpace = 1, columnSpace = 1, stagger = 0 })

    local order = 0
    local function Load(boss)
        if boss and boss.enc then return { zone = zone, enc = { boss.enc } } end
        if boss then return { zone = zone } end
        if #allEnc > 0 then return { zone = zone, enc = allEnc } end
        return { zone = zone }
    end
    local function Unit(def)
        order = order + 1
        def.raid, def.order, def.disjunctive = raidKey, order, def.disjunctive or "any"
        Dd.U(def)
        return def
    end
    -- a custom trigger with its behaviour in B
    local function Piece(id, kind, group, display, boss, events, map, extra)
        local def = { id = id, kind = kind, group = group, display = display, load = Load(boss),
            triggers = { { kind = "custom", ttype = "stateupdate", events = events, trigger = C } } }
        if map["init"] then def.init = C end
        if map["actions.start.custom"] or map["actions.finish.custom"] then
            def.actions = {}
            if map["actions.start.custom"] then def.actions.start = { custom = C } end
            if map["actions.finish.custom"] then def.actions.finish = { custom = C } end
        end
        if map["text"] then def.text = C end
        if extra then for k, v in pairs(extra) do def[k] = v end end
        Unit(def)
        B[id] = map
        return def
    end

    local bars, berserkKeys = {}, {}
    local hasTimers = false

    for _, boss in ipairs(R.bosses) do
        local tag = "[" .. boss.short .. "] "
        boss.key = boss.key or Key(raidKey, boss.short)

        -- berserk
        if boss.berserk then
            local bk = Key(boss.key, "BERSERK")
            berserkKeys[bk] = true
            local map, subs = T.Ability(boss, { key = bk, first = boss.berserk.secs })
            Piece("CT:" .. tag .. "Berserk", "text", gCtl, D.Silent(), boss, Events(subs), map)
        end

        -- timed abilities: a controller, a bar, a heads-up
        for _, a in ipairs(boss.timers or {}) do
            a.key = Key(boss.key, a.id or a.name)
            local map, subs, plates = T.Ability(boss, a)
            local extraEv = {}
            if a.startOn then extraEv[#extraEv + 1] = a.startOn end
            for _, e in ipairs(a.stopOn or {}) do extraEv[#extraEv + 1] = e end
            Piece("CT:" .. tag .. a.name, "text", gCtl, D.Silent(), boss, Events(subs, extraEv, plates), map)
            local color = (a.role == "TANK" and TANK_COLOR) or (a.phase and PHASE_COLOR) or (a.onlyMe and SELF_COLOR) or BAR_COLOR
            bars[a.key] = { name = a.bar or a.name, icon = IconOf(a.spells, a.icon), color = color, role = a.role,
                autoHide = (a.every == nil and a.steps == nil) or a.autoHide }
            hasTimers = true
            if a.prewarn then
                local hm, hev = T.Heads(a)
                local label = (a.heads or a.name):upper()
                Piece("SW:" .. tag .. a.name .. " PreWarn", "text", gWarn, D.Text("%i " .. label .. " %p", 20, { 1, 0.85, 0.2, 1 }),
                    boss, hev, hm)
            end
        end

        -- cycles (timed phases)
        for _, c in ipairs(boss.cycles or {}) do
            c.key = Key(boss.key, c.id)
            for _, p in ipairs(c.parts) do
                p.key = Key(c.key, p.id or p.bar)
                bars[p.key] = { name = p.bar, icon = IconOf(c.spells, c.icon), color = PHASE_COLOR, autoHide = true }
                hasTimers = true
            end
            c.icon = IconOf(c.spells, c.icon)
            local map, subs, extraEv = T.Cycle(boss, c)
            Piece("PH:" .. tag .. c.name, "text", gAlert, D.Text("%i %n", 22, { 0.62, 0.87, 1, 1 }), boss, Events(subs, extraEv), map)
        end

        -- call-outs
        for _, s in ipairs(boss.alerts or {}) do
            local map, subs, plates = T.Alert(boss, s)
            Piece("SA:" .. tag .. s.name, "text", gAlert, D.Text("%i %n", 22, s.color or { 1, 0.82, 0, 1 }), boss, Events(subs, nil, plates), map)
        end

        -- phase calls from the boss's health
        if boss.health then
            local h = boss.health
            h.key = boss.key
            local map, ev = T.Health(boss, h)
            Piece("HP:" .. tag .. "Phases", "text", gWarn, D.Text("%n", 22, { 0.62, 0.87, 1, 1 }), boss, Events(nil, ev), map)
        end

        -- debuffs on you
        for _, y in ipairs(boss.onYou or {}) do
            local names = {}
            for _, id in ipairs(y.spells or {}) do names[#names + 1] = tostring(id) end
            for _, n in ipairs(y.names or {}) do names[#names + 1] = n end
            local act = {}
            if y.say then act.sound = "tts:" .. y.say end
            if y.chat then act.message, act.message_type = y.chat, "SAY" end
            Unit({ id = "A:" .. tag .. y.name, kind = "icon", group = gIcons, display = D.OnYou(y.label), load = Load(boss),
                actions = { start = act },
                triggers = { { kind = "aura", filter = "HARMFUL", names = names, unit = "player" } } })
        end

        -- debuffs on raid frames
        for _, r in ipairs(boss.raid or {}) do
            local names = {}
            for _, id in ipairs(r.spells or {}) do names[#names + 1] = tostring(id) end
            for _, n in ipairs(r.names or {}) do names[#names + 1] = n end
            local c = r.color or { 1, 0.28, 0.17, 0.6 }
            Unit({ id = "RF:" .. tag .. r.name, kind = "icon", group = gRF, display = D.RaidFrame(), load = Load(boss), activeTrigger = 1,
                actions = { start = { glow = { glow_action = "show", glow_frame_type = "UNITFRAME", glow_type = "Pixel",
                    use_glow_color = true, glow_color = c, glow_frequency = 0.1, glow_length = 14, glow_lines = 14, glow_thickness = 2 } } },
                triggers = { { kind = "aura", filter = "HARMFUL", names = names, unit = "group", clones = true } } })
        end

        -- buffs on a mob's nameplate
        for _, p in ipairs(boss.plates or {}) do
            local npcs = {}
            for _, n in ipairs(p.npcs) do npcs[#npcs + 1] = tostring(n) end
            local map = K.PlateBuff({ npcs = npcs, spells = p.spells, dur = p.dur, spellIcon = true })
            Piece("N:" .. tag .. p.name, "icon", gPlates, D.Plate(), boss,
                { "CLEU:SPELL_AURA_APPLIED", "CLEU:SPELL_AURA_REMOVED", "NAME_PLATE_UNIT_REMOVED", "NAME_PLATE_UNIT_ADDED" }, map)
        end

        -- raid marks (raid leader / assist)
        for _, mk in ipairs(boss.marks or {}) do
            local map, subs = T.Mark(boss, mk)
            local def = Piece("[RAIDLEAD]" .. tag .. "Mark " .. mk.name, "text", gAuto, D.Silent(), boss, Events(subs), map,
                { config = { group = { option = { enable = true, firstMark = mk.marks and mk.marks[1] or 8,
                    secondMark = mk.marks and mk.marks[2] or 7, thirdMark = mk.marks and mk.marks[3] or 6 } } },
                  options = { { type = "group", key = "group", name = "Raid marks (raid leader)", subOptions = {
                    { type = "group", key = "option", name = mk.name, subOptions = {
                        { type = "toggle", key = "enable", name = "Mark whoever gets " .. mk.name, default = true } } } } } } })
            def.load.leader = { LEADER = true, ASSIST = true }
        end
    end

    -- the lists every boss shares
    local shared = "[" .. (R.short or name) .. "] "
    if hasTimers then
        local tb = K.TimerBars({ bars = bars })
        Piece("BT:" .. shared .. "Boss Timers", "aurabar", gTimers, D.Timers({ 0.31, 0.65, 1, 0.75 }), nil,
            { "WA_NUMEN_TIMER", "WA_NUMEN_EMPHASIZED_TIMER" }, tb,
            { config = { option = { colorOverride = false, color = { 0.31, 0.65, 1, 0.75 }, emphasizedTimers = false, emphasizeGroup = {} } },
              options = { { type = "group", key = "option", name = "Boss timers", subOptions = {
                { type = "toggle", key = "emphasizedTimers", name = "Last ten seconds move to the emphasized list", default = false },
                { type = "toggle", key = "colorOverride", name = "One colour for every bar", default = false },
                { type = "color", key = "color", name = "Bar colour", default = { 0.31, 0.65, 1, 0.75 } } } } } })
        local em = K.Emphasized({})
        Piece("BTE:" .. shared .. "Emphasized Timers", "aurabar", gEmph, D.Timers({ 1, 0.27, 0.33, 0.81 }), nil,
            { "WA_NUMEN_TIMER", "WA_NUMEN_EMPHASIZED_TIMER" }, em,
            { config = { option = { colorOverride = false, color = { 1, 1, 1, 1 } } } })
    end
    if next(berserkKeys) then
        local bm = K.Berserk({ keys = berserkKeys })
        Piece("BT:" .. shared .. "Berserk Timer", "aurabar", gBerserk, D.Berserk(), nil, { "WA_NUMEN_TIMER" }, bm,
            { activeTrigger = 1, conditions = {
                { check = { trigger = 1, variable = "expirationTime", op = "==", value = "30" }, changes = { { property = "customcode", value = C } } },
                { check = { trigger = 1, variable = "expirationTime", op = "<", value = "120" }, changes = { { property = "alpha", value = 1 } } } } })
        local wm = BerserkWarn()
        Piece("SW:" .. shared .. "Berserk Warning", "text", gWarn, D.Text("%n", 22, { 1, 0.3, 0.3, 1 }), nil,
            { "WA_FOJJI_BERSERK_30", "WA_FOJJI_BERSERK", "ENCOUNTER_END", "WA_FJI_ENCOUNTER_END" }, wm)
    end

    -- the raid file's own pieces and additions
    for id, map in pairs(extras or {}) do
        B[id] = K.Merge(B[id], map)
    end
    O.Finish(raidKey, B)
    T.order[#T.order + 1] = raidKey
end

-- ============================================================
-- THE SETTINGS PAGE'S SAMPLES, in TBC's words
-- ============================================================
-- The preview strip's modes name real pieces; on TBC they name TBC ones.
-- (RM_Config publishes the tables; a mode whose piece is missing simply
-- shows nothing, so only names that exist are handed over - after the
-- raids are built, from the PullTimers file's turn at the end.)
function T.Samples()
    local MP = RM.MODE_PIECES
    if not MP then return end
    local function Have(id) return RM.units[id] ~= nil end
    local function Pick(list)
        local out = {}
        for _, p in ipairs(list) do if Have(p.id) then out[#out + 1] = p end end
        return out
    end
    local want = {
        warnings = { { id = "SW:[Magtheridon] Blast Nova PreWarn", left = 7.5, dur = 10 },
            { id = "SW:[Akil'zon] Electrical Storm PreWarn", left = 3, dur = 5 } },
        callouts = { { id = "SA:[Shade of Aran] Flame Wreath", left = 2, dur = 3 },
            { id = "SA:[Prince] Shadow Nova", left = 2.4, dur = 3 } },
        icons = { { id = "A:[Teron] Shadow of Death", left = 41, dur = 55 },
            { id = "A:[Vashj] Static Charge", left = 6.2, dur = 20 },
            { id = "A:[Prince] Enfeeble", left = 3.1, dur = 7 } },
        bars = { { id = "BT:[Mag] Boss Timers", left = 18.5, dur = 60 } },
        onyou = { { id = "A:[Opera] Red Riding Hood", left = 12, dur = 20 } },
        raidframes = { { id = "RF:[Maulgar] Greater Polymorph", left = 5.2, dur = 8 },
            { id = "RF:[Teron] Shadow of Death", left = 30, dur = 55 },
            { id = "RF:[Archimonde] Grip of the Legion", left = 7.5, dur = 30 } },
        plates = { { id = "N:[Maulgar] Spell Shield", left = 20, dur = 30 },
            { id = "N:[Council] Blessing of Spell Warding", left = 8, dur = 15 } },
    }
    -- every mode names TBC pieces only (circles: TBC has none, so it
    -- shows nothing rather than an Era piece that is not there)
    for mode, m in pairs(MP) do
        m.pieces = Pick(want[mode] or m.pieces or {})
    end
    -- the overview strip's own samples
    local SB = RM.SAMPLE_BARS
    if SB then
        local names = { { "Blast Nova", 135735 }, { "Watery Grave", 135861 } }
        for i, n in ipairs(names) do
            if SB[i] then SB[i].name = n[1] SB[i].icon = (GetSpellTexture and GetSpellTexture(i == 1 and 30616 or 38049)) or n[2] end
        end
    end
    if RM.SAMPLE_ALERT then RM.SAMPLE_ALERT.displayText = "Static Charge on YOU!" end
end
