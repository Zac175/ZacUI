-- AQ40 - ZacUI's own Temple of Ahn'Qiraj boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Settings in Own\AQ40_Data.lua.
--
-- One invisible controller per boss ability watches the combat log and
-- puts its countdown on the bus (WA_NUMEN_TIMER key, seconds, count);
-- the timer bars, flashes, heads-up bars and speech listen for it. AQ40's
-- countdowns differ from Molten Core's in small ways (a fourth value for
-- the caster's GUID, heads-ups that carry the coming count, phases that
-- pause and resume a timer), so this file has its own ability builder at
-- the top. The one-offs - Viscidus' freeze counter, the Anubisath ability
-- icons, the Flesh Tentacle health list - are written out further down.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
if not (RM and RM.Own and RM.Own.on) then return end
local K = RM.Own.Kit

local B = {}

local NUMEN = "WA_NUMEN_TIMER"
local EMPHASIZED = "WA_NUMEN_EMPHASIZED_TIMER"
-- the chat prefix the raid-lead marking prints with
local SAY = "|cff3399ffRaid Mods|r |cff9955ffAQ40|r"
-- the "soon" icon every heads-up bar shows
local SOON_ICON = 135789

-- ============================================================
-- SMALL PIECES
-- ============================================================

-- Speech at the volume and rate the player set for the raid mods (the
-- engine picks the voice). who = fn() limits it to some players.
local function Voice(text, who)
    return function()
        if who and not who() then return end
        RM.Speak(text, _G.FJITTS_SFX_VOLUME or 75, _G.FJITTS_SFX_RATE or 1.2)
    end
end
-- the same as a start action
local function Talk(text, who)
    return { ["actions.start.custom"] = Voice(text, who) }
end

-- who hears or sees a piece
local function HealerOrLead()
    return _G.FJI_HEALER or UnitIsGroupLeader("player")
end
local function LeadHealerOrTank()
    return UnitIsGroupLeader("player") or _G.FJI_HEALER or _G.FJI_TANK
end
-- a player of one of these classes (true), else whether they lead
local function ClassOrLead(...)
    local set = K.Set({ ... })
    return function()
        return set[UnitClassBase("player")] or UnitIsGroupLeader("player")
    end
end

-- the logic pieces' shapes: t is the list of trigger results
local function First(env, t) return t[1] end
local function NotTank(env, t) return t[1] and not _G.FJI_TANK end
local function TankOnly(env, t) return t[1] and _G.FJI_TANK end

-- icon texts that turn a debuff's stacks into what they cost:
-- "-240" armour a stack, "+100" damage a stack ...
local function PerStack(each, sign)
    return function(env, expirationTime, duration, progress, formatedDuration, name, icon, stacks)
        local total = (tonumber(stacks) or 0) * each
        if sign then return sign .. total end
        return total
    end
end

-- The "split / enrage soon" texts: how far the boss's health is above
-- the next mark, read from the health triggers (one per mark, in order).
local function HealthToGo(word, marks)
    return function(env)
        if RM.WA.IsOptionsOpen() then
            return word, string.format("|cFFFFFF00%.2f%%|r", math.random() * 5)
        end
        local left, phase
        local states = env.states
        if states then
            for i, mark in ipairs(marks) do
                local st = states[i]
                if st and st.percenthealth ~= nil then
                    left, phase = st.percenthealth - mark, word
                    break
                end
            end
        end
        return phase, string.format("|cFFFFFF00%.2f%%|r", left or 0)
    end
end

-- A preview that looks like the real thing: dur seconds, icon.
local function Same(dur, icon)
    return function() return K.Timed(dur, { changed = true, autoHide = true, icon = icon }) end
end

-- Wraps a slot map's trigger so event takes its state down.
local function DropOn(map, event)
    local inner = map["triggers.1.trigger"]
    map["triggers.1.trigger"] = function(env, allstates, ev, ...)
        if ev == event then return K.Drop(allstates, "") end
        return inner(env, allstates, ev, ...)
    end
    return map
end

-- The group member whose GUID is guid, if any.
local function MemberWith(guid)
    for unit in RM.IterateGroup() do
        if UnitGUID(unit) == guid then return unit end
    end
end

-- Posts an event to the rest of the raid (when the sync addon is there).
local function Share(...)
    local send = _G.SyncEvents
    if send then
        WA_SYNC_RESULT = send(...)
    else
        WA_SYNC_RESULT = nil
    end
end

-- The finish of a piece with no countdown of its own (a few relays and
-- watchers): nothing to stop; resets puts the count back.
local function Quiet(resets)
    return function(env)
        if resets then env.count = 1 end
    end
end

-- ============================================================
-- ABILITIES - one boss ability's countdown on the bus
-- ============================================================
-- On the pull (startOn, default ENCOUNTER_START) the count goes back to 1,
-- the piece shows and the first countdown starts. Each time the ability
-- lands: (key, 0, count) says it went off, the count goes up and the next
-- countdown starts.
--   key       the bus key
--   spells    spell ids that count (none: the piece only reacts to events)
--   subs      combat log events that count (default SPELL_CAST_SUCCESS)
--   npc       only this creature's casts count
--   throttle  seconds in which a second landing is ignored
--   first     seconds to the first one after the pull
--   every     seconds between them
--   prewarn   seconds of heads-up before each countdown ends: fires
--             WA_<KEY>_PREWARN (seconds, coming count)
--   loop      an event fired when each countdown runs out (an ability
--             with no combat log line of its own counts on that event)
--   castOn    an event that counts as a landing
--   wide      the calls carry two more values (caster GUID, name); guid:
--             the "went off" call fills in the caster
--   start     false: the pull is not this piece's business; recount
--             false: the pull keeps the count; show false: nothing shows
--   on        { [event] = steps }: "stop", "hide", "unwarn", "unloop", or a
--             number (start a countdown of that many seconds)
--   diesWith  { npc, steps }: when that creature dies, run the steps
--   relay     { [subEvent] = event }: also tell the bus who it landed on
--   after     fn(env, subEvent, destGUID, amount): extra work after the
--             "went off" call
--   finish    "all": the finish also cancels a heads-up and a pending event
local function Ability(s)
    local key = s.key
    local startOn = s.startOn or "ENCOUNTER_START"
    local spells = s.spells and K.Set(s.spells)
    local subs = K.Set(s.subs or { "SPELL_CAST_SUCCESS" })
    local lead = s.prewarn
    local warnEvent = "WA_" .. key .. "_PREWARN"

    local function Call(secs, count, guid)
        if s.wide then
            RM.Fire(NUMEN, key, secs, count, guid, nil)
        else
            RM.Fire(NUMEN, key, secs, count)
        end
    end
    local function Warn(env, secs)
        if env.warnTimer then env.warnTimer:Cancel() end
        local count = env.count
        env.warnTimer = C_Timer.NewTimer(secs - lead, function()
            RM.Fire(warnEvent, lead, count)
            env.warnTimer = nil
        end)
    end
    local function Unwarn(env)
        RM.Fire(warnEvent .. "_CANCEL")
        if env.warnTimer then
            env.warnTimer:Cancel()
            env.warnTimer = nil
        end
    end
    local function Unloop(env)
        if env.timer then
            env.timer:Cancel()
            env.timer = nil
        end
    end
    local function Countdown(env, secs)
        if lead then Warn(env, secs) end
        Call(secs, env.count)
        if s.loop then
            Unloop(env)
            env.timer = C_Timer.NewTimer(secs, function() RM.Fire(s.loop) end)
        end
    end
    local function Steps(env, allstates, steps)
        for _, step in ipairs(steps) do
            if type(step) == "number" then Countdown(env, step)
            elseif step == "stop" then Call(nil, nil)
            elseif step == "hide" then K.Drop(allstates, "")
            elseif step == "unwarn" then Unwarn(env)
            elseif step == "unloop" then Unloop(env)
            end
        end
        return true
    end
    local function WentOff(env, subEvent, sourceGUID, destGUID, amount)
        Call(0, env.count, s.guid and sourceGUID or nil)
        if s.after then s.after(env, subEvent, destGUID, amount) end
        env.count = env.count + 1
        if s.every then Countdown(env, s.every) end
        return true
    end

    local map = {}
    map["init"] = function(env)
        env.key = key
        env.count = 1
        if s.throttle then env.throttle = 0 end
    end
    map["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, sourceGUID, _, _, _, destGUID, destName, _, _, spellId, _, _, _, amount)
        if event == startOn and s.start ~= false then
            if s.recount ~= false then env.count = 1 end
            if s.show ~= false then K.Put(allstates, "", {}) end
            if s.first then Countdown(env, s.first) end
            return true
        end
        local steps = s.on and s.on[event]
        if steps then return Steps(env, allstates, steps) end
        if s.diesWith and subEvent == "UNIT_DIED" and K.NpcId(destGUID) == s.diesWith[1] then
            return Steps(env, allstates, s.diesWith[2])
        end
        if s.castOn and event == s.castOn then return WentOff(env) end
        if not spells then return end
        if not spells[spellId] then return false end
        if s.npc and K.NpcId(sourceGUID) ~= s.npc then return false end
        local tell = s.relay and s.relay[subEvent]
        if tell then RM.Fire(tell, destGUID, destName) end
        if not subs[subEvent] then return end
        if s.throttle then
            if GetTime() - env.throttle < s.throttle then return false end
            env.throttle = GetTime()
        end
        return WentOff(env, subEvent, sourceGUID, destGUID, amount)
    end
    map["actions.finish.custom"] = function(env)
        if s.finish == "all" then
            Unwarn(env)
            Unloop(env)
        end
        env.count = 1
        Call(nil, nil)
    end
    return map
end

-- A relay: one spell landing becomes one bus event other pieces show.
--   spell, sub (default SPELL_AURA_APPLIED), event, pass(sourceGUID,
--   sourceName, destGUID, destName) -> the event's values, answer (what
--   the trigger says after telling), stop (the finish stops this
--   countdown key; without it the finish only puts the count back)
local function Relay(s)
    local sub = s.sub or "SPELL_AURA_APPLIED"
    local map = {}
    map["init"] = function(env)
        env.spell = s.spell
        if s.stop then env.key = s.stop end
    end
    map["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, spellId)
        if spellId ~= s.spell then return false end
        if subEvent ~= sub then return end
        if s.pass then
            RM.Fire(s.event, s.pass(sourceGUID, sourceName, destGUID, destName))
        else
            RM.Fire(s.event)
        end
        return s.answer
    end
    if s.stop then
        map["actions.finish.custom"] = function(env)
            env.count = 1
            RM.Fire(NUMEN, s.stop, nil, nil)
        end
    else
        map["actions.finish.custom"] = Quiet(true)
    end
    return map
end
local function Dest(_, _, destGUID) return destGUID end
local function DestAndName(_, _, destGUID, destName) return destGUID, destName end

-- ============================================================
-- BARS AND BANNERS
-- ============================================================

-- A heads-up bar on a PREWARN event (seconds, coming count).
local function Soon(event, icon)
    return {
        ["triggers.1.icon"] = K.Always(SOON_ICON),
        ["triggers.1.trigger"] = function(env, allstates, ev, duration, count)
            if ev == "OPTIONS" then
                K.Put(allstates, "", { progressType = "timed", icon = icon, count = math.random(1, 3) })
                return true
            end
            if ev == event then
                K.Put(allstates, "", { progressType = "timed", duration = duration, expirationTime = GetTime() + duration,
                    icon = icon, count = count, autoHide = true })
                return true
            end
        end,
    }
end

-- Someone else got it: a banner carrying their GUID (never for you).
local function SomeoneElse(event, icon, dur)
    return {
        ["triggers.1.trigger"] = function(env, allstates, ev, guid)
            if ev == "OPTIONS" then
                allstates[""] = { show = true, icon = icon, guid = RM.WA.myGUID }
            end
            if ev == event and guid ~= RM.WA.myGUID then
                K.Put(allstates, "", K.Timed(dur, { icon = icon, autoHide = true, guid = guid }))
                return true
            end
        end,
    }
end

-- A named banner: events = { EVENT = "NAME" } (true: the event's first
-- value is the name). sample = { dur, name } for the preview.
local function Called(s)
    return {
        ["triggers.1.trigger"] = function(env, allstates, ev, value)
            if ev == "OPTIONS" then
                K.Put(allstates, "", K.Timed(s.sample[1], { name = s.sample[2], autoHide = true, icon = s.icon }))
                return true
            end
            local name = s.events[ev]
            if name == nil then return end
            if name == true then name = value end
            K.Put(allstates, "", K.Timed(s.dur or 3, { name = name, autoHide = true, icon = s.icon }))
            return true
        end,
    }
end

-- The countdown flashes: an icon when the ability goes off. sampleDur:
-- the preview's length (nil: no preview).
local function GoneOff(key, dur, icon, sampleDur)
    local s = { key = key, dur = dur, icon = icon }
    if sampleDur then
        s.sample, s.sampleShows = Same(sampleDur, icon), true
    end
    return K.Flash(s)
end

-- A bar that names a mob (text = the colour code the bar sets) for a
-- moment after its countdown goes off, keyed by the caster; an interrupt
-- takes it down.
local function CastingMob(key, dur)
    return {
        ["text"] = K.Field("addColour"),
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == NUMEN then
                local k, secs, _, guid = ...
                if k == key and secs == 0 then
                    K.Put(allstates, guid, K.Timed(dur, { autoHide = true }))
                    return true
                end
            end
            if event == "COMBAT_LOG_EVENT_UNFILTERED" then
                local _, subEvent, _, _, _, _, _, destGUID = ...
                if subEvent == "SPELL_INTERRUPT" and allstates[destGUID] then
                    return K.Drop(allstates, destGUID)
                end
            end
        end,
    }
end

-- ============================================================
-- RAID LEADER: MARKING
-- ============================================================
-- Start action: mark the player the piece shows with the first free mark
-- (in the options' order), remembering any mark they had.
local function MarkShown(env)
    local opt = env.config.group.option
    local st = env.state
    if not (opt.enable and st and st.unit) then return end
    local unit = st.unit
    local had = GetRaidTargetIndex(unit)
    if had and had > 0 then env.originalMarks[unit] = had end
    local order = {}
    for k, mark in pairs(opt) do
        if k:find("Mark") and mark then order[#order + 1] = mark end
    end
    for _, mark in ipairs(order) do
        if env.marks[mark] then
            SetRaidTarget(unit, mark)
            print(SAY .. " - Marked " .. (UnitName(unit)) .. " with |TInterface/TargetingFrame/UI-RaidTargetingIcon_" .. mark .. ":14:14|t")
            env.marks[mark] = false
            return
        end
    end
end

B["[RAIDLEAD][AQ40][Trash] AutoMark Plague"] = {
    ["init"] = K.MarkPool(),
    ["actions.start.custom"] = MarkShown,
    ["actions.finish.custom"] = K.MarkClear(),
}
B["[RAIDLEAD][AQ40][Huhuran] AutoMark Wyvern Sting"] = {
    ["init"] = K.MarkPool(),
    ["actions.start.custom"] = MarkShown,
    ["actions.finish.custom"] = K.MarkClear(),
}

-- C'Thun's Eye Beam: mark its target for two seconds, then give the mark
-- back (and theirs, if they had one).
B["[RAIDLEAD][AQ40][C'thun] AutoMark Eye Beam Target"] = {
    ["init"] = K.MarkPool(),
    ["triggers.1.trigger"] = function(env, allstates, event, destGUID)
        if event == "WA_CTHUN_EYE_BEAM_TARGET" then
            env.unitMarkedGUID = destGUID
            local unit = MemberWith(destGUID)
            if unit then
                local had = GetRaidTargetIndex(unit)
                if had and had > 0 then env.originalMarks[destGUID] = had end
            end
            C_Timer.After(2.1, function() RM.Fire("WA_CTHUN_REMOVE_MARK") end)
            K.Put(allstates, "", K.Timed(2, { autoHide = true }))
            return true
        elseif event == "WA_CTHUN_REMOVE_MARK" then
            local guid = env.unitMarkedGUID
            local unit = guid and MemberWith(guid)
            if unit then
                local mark = GetRaidTargetIndex(unit)
                if mark then
                    SetRaidTarget(unit, 0)
                    env.marks[mark] = true
                end
                local had = env.originalMarks[guid]
                if had then
                    SetRaidTarget(unit, had)
                    env.originalMarks[guid] = nil
                end
            end
            env.unitMarkedGUID = nil
        end
    end,
    ["actions.start.custom"] = function(env)
        if not (env.config.group.option.enable and env.state and env.unitMarkedGUID) then return end
        local unit = MemberWith(env.unitMarkedGUID)
        if not unit then return end
        local free = {}
        for mark, open in pairs(env.marks) do
            if open then free[#free + 1] = mark end
        end
        local mark = free[1]
        if mark then
            SetRaidTarget(unit, mark)
            print(SAY .. " - Marked " .. (UnitName(unit)) .. " with |TInterface/TargetingFrame/UI-RaidTargetingIcon_" .. mark .. ":14:14|t")
            env.marks[mark] = false
        end
    end,
}

-- ============================================================
-- TIMER BARS
-- ============================================================
-- The boss-timer list. A countdown can carry the caster's GUID (fourth
-- value) and then gets a bar of its own; the bar text is the fifth. With
-- "emphasize" on, the last ten seconds move to the emphasized list.
do
    local ORANGE = { 255, 149, 87, 1 }   -- 0-255 RGB plus alpha
    local function Bar(name, icon) return { name = name, icon = icon, color = ORANGE } end
    local BARS = {
        BUGTRIO_FEAR = Bar("Fear", 136183),
        SARTURA_CURSE = Bar("Curse of Despair", 132095),
        SARTURA_WHIRLWIND = Bar("Boss Whirlwind", 132369),
        FANKRISS_SUMMON_WORM = Bar("Summon Worms", 236197),
        VISCIDUS_POISON_VOLLEY = Bar("Poison Bolt Volley", 136006),
        VISCIDUS_NOXIOUS_BURST = Bar("Noxious Burst", 132108),
        HUHURAN_CURSE = Bar("Curse of Despair", 132095),
        HUHURAN_POISON_BOLT = Bar("Poison Bolt Volley", 136016),
        HUHURAN_WYVERN_STING = Bar("Wyvern Sting", 135125),
        HUHURAN_FRENZY = Bar("Frenzy", 132117),
        TWINS_CURSE = Bar("Curse of Despair", 132095),
        TWINS_MUTATE_BUG = Bar("Mutate Bug", 132195),
        TWINS_TELEPORT = Bar("Teleport", 135736),
        OURO_SAND_BLAST = Bar("Sand Blast", 136018),
        OURO_SUBMERGE = Bar("Submerge", 236197),
        OURO_SWEEP = Bar("Sweep", 136104),
        OURO_BLINDING_ADMIRATION = Bar("Blinding Admiration", 136206),
        CTHUN_EYE_TENTACLES = Bar("Eye Tentacles", 237298),
        CTHUN_GIANT_EYE_TENTACLE = Bar("Giant Eye Tentacle", 133884),
        CTHUN_CLAW_TENTACLE = Bar("Claw Tentacle", 134296),
        CTHUN_GIANT_CLAW_TENTACLE = Bar("Giant Claw Tentacle", 135664),
        CTHUN_DARK_GLARE = Bar("Dark Glare", 136197),
    }
    local ROLE = {
        TANK = "|A:groupfinder-icon-role-large-tank:16:16|a ",
        HEALER = "|A:groupfinder-icon-role-large-heal:16:16|a ",
    }
    local LAST = 10

    local function Id(key, guid)
        if guid then return key .. "_" .. guid end
        return key
    end
    local function Show(allstates, id, secs, count, name, icon, color, autoHide, text)
        local r, g, b, a = unpack(color)
        K.Put(allstates, id, {
            duration = secs, expirationTime = GetTime() + secs, progressType = "timed",
            count = count, color = { r / 255, g / 255, b / 255, a },
            icon = icon, name = name, autoHide = autoHide, text = text or "",
        })
    end
    local function Stop(timers, id)
        if timers[id] then
            timers[id]:Cancel()
            timers[id] = nil
        end
    end

    B["BT:[AQ40][All] Boss Timers"] = {
        ["init"] = function(env)
            env.region.bar:SetVertexColor(1, 1, 1, 1)
            env.spellKeys = BARS
            env.timers = {}
        end,
        ["text"] = K.CountText(),
        ["actions.start.custom"] = K.ColorOverride(),
        ["triggers.1.trigger"] = function(env, allstates, event, key, secs, count, guid, text)
            local timers = env.timers
            if event == "OPTIONS" then
                for i = 1, 5 do
                    allstates[i] = K.Timed(6, { show = true, name = "Deep Breath " .. i })
                end
            end
            if event == "STATUS" or event == "OPTIONS" then
                for _, t in pairs(timers) do
                    if t then t:Cancel() end
                end
            end
            local bar = BARS[key]
            if not bar then return end
            local id = Id(key, guid)
            if event == NUMEN then
                if secs == nil or secs == 0 then
                    Stop(timers, id)
                    K.Drop(allstates, id)
                    return true
                end
                local name = (ROLE[bar.role] or "") .. bar.name
                local autoHide = bar.autoHide or false
                local extra = bar.useText and (text or "") or nil
                local opt = env.config.option
                if not (opt.emphasizedTimers or (opt.emphasizeGroup and opt.emphasizeGroup[key])) then
                    Show(allstates, id, secs, count, name, bar.icon, bar.color, autoHide, extra)
                    return true
                end
                if secs <= LAST then
                    RM.Fire(EMPHASIZED, key, secs, count, name, bar.icon, bar.color, autoHide, extra, guid)
                    return
                end
                Show(allstates, id, secs, count, name, bar.icon, bar.color, autoHide, extra)
                Stop(timers, id)
                timers[id] = C_Timer.NewTimer(secs - LAST, function()
                    RM.Fire(EMPHASIZED, key, LAST, count, name, bar.icon, bar.color, autoHide, extra, guid)
                end)
                return true
            elseif event == EMPHASIZED then
                K.Drop(allstates, id)
                return true
            end
        end,
    }

    -- the emphasized list: takes the bars handed over, drops them when
    -- their countdown goes off or stops (a countdown call carries the
    -- caster's GUID fourth, where a hand-over carries the name)
    B["BTE:[AQ40][All] Emphasized Timers"] = {
        ["init"] = function() end,
        ["text"] = K.CountText(),
        ["actions.start.custom"] = K.ColorOverride(),
        ["triggers.1.trigger"] = function(env, allstates, event, key, secs, count, name, icon, color, autoHide, text, guid)
            if event == "OPTIONS" then
                for i = 1, 3 do
                    allstates["LaserAttack_" .. i] = K.Timed(6, { show = true, name = "Laser Attack " .. i, index = i })
                end
            end
            if event == EMPHASIZED and secs ~= nil and secs ~= 0 then
                Show(allstates, Id(key, guid), secs, count, name, icon, color, autoHide, text or "")
                return true
            elseif event == NUMEN and (secs == nil or secs == 0) then
                K.Drop(allstates, Id(key, name))
                return true
            end
        end,
    }
end

-- The Twin Emperors' berserk bar. Its state carries the key; the 30 and
-- 10 second conditions tell the warnings.
do
    local KEYS = { TWINS_BERSERK = true }
    B["BT:[AQ40][Twin Emperors] Berserk Timer"] = {
        ["init"] = function(env) env.berserkKeys = KEYS end,
        ["triggers.1.trigger"] = function(env, allstates, event, key, secs)
            if KEYS[key] and secs ~= nil and secs > 0 then
                K.Put(allstates, "", K.Timed(secs, { autoHide = true, key = key }))
                return true
            end
        end,
        ["actions.finish.custom"] = function() RM.Fire("WA_FOJJI_BERSERK") end,
        ["conditions.1.changes.1.value"] = function(env) RM.Fire("WA_FOJJI_BERSERK_30", env.state.key) end,
        ["conditions.2.changes.1.value"] = function() RM.Fire("WA_FOJJI_BERSERK_10") end,
    }
end

-- a wipe: thirty seconds until the boss is back
do
    local function Respawn(allstates, env)
        K.Put(allstates, "", { progressType = "timed", duration = env.eRespawnTimer - GetTime(),
            expirationTime = env.eRespawnTimer, autoHide = true, bossName = env.bossName })
        return true
    end
    B["BT:[AQ40][All] Boss Respawn"] = {
        ["triggers.1.trigger"] = function(env, allstates, event, encounterID, encounterName, difficultyID, groupSize, success)
            if event == "ENCOUNTER_END" and success == 0 then
                env.bossName = encounterName
                env.eRespawnTimer = GetTime() + 30
                return Respawn(allstates, env)
            elseif event == "STATUS" and env.eRespawnTimer and env.eRespawnTimer - GetTime() > 0 then
                return Respawn(allstates, env)
            end
        end,
    }
end

-- ============================================================
-- CONTROLLERS - trash
-- ============================================================
B["CT:[AQ40][Trash] Cause Insanity"] = Relay{ spell = 26079, event = "WA_AQ40_TRASH_MC_TARGET", pass = DestAndName }
B["CT:[AQ40][Trash] Explode"] = Relay{ spell = 25698, event = "WA_AQ40_TRASH_EXPLODE", pass = function(sourceGUID) return sourceGUID end }
B["CT:[AQ40][Trash] Frenzy"] = Relay{ spell = 26041, event = "WA_AQ40_SLAYER_FRENZY", pass = Dest }
B["CT:[AQ40][Trash] Plague"] = Relay{ spell = 26556, event = "WA_AQ40_PLAGUE_APPLIED", pass = Dest }
B["CT:[AQ40][Trash] Vengeance"] = Relay{ spell = 25164, event = "WA_AQ40_CHAMPION_VENGEANCE", pass = Dest }

-- ============================================================
-- CONTROLLERS - bosses
-- ============================================================
-- Skeram: no timers, only "it went off" (the explosion and the heal-style
-- casts carry the caster so the cast bars can follow each image)
B["CT:[AQ40][Skeram] Arcane Explosion"] = Ability{ key = "SKERAM_ARCANE_EXPLOSION", spells = { 26192 }, subs = { "SPELL_CAST_START" },
    recount = false, wide = true, guid = true }
B["CT:[AQ40][Skeram] True Fulfillment"] = Ability{ key = "SKERAM_TRUE_FULFILLMENT", spells = { 785 }, subs = { "SPELL_CAST_START" },
    recount = false, wide = true, relay = { SPELL_AURA_APPLIED = "WA_SKERAM_MC_TARGET" } }
B["CT:[AQ40][Skeram] Summon Images"] = Ability{ key = "SKERAM_SUMMON_IMAGES", spells = { 747 }, subs = { "SPELL_SUMMON" },
    recount = false, wide = true }

-- Bug Trio: the fear timer ends with Lord Kri
B["CT:[AQ40][Bug Trio] Fear"] = Ability{ key = "BUGTRIO_FEAR", spells = { 26580 }, first = 10, every = 20.5,
    diesWith = { "15543", { "stop", "hide" } } }
B["CT:[AQ40][Bug Trio] Heal"] = Ability{ key = "BUGTRIO_HEAL", spells = { 25807 }, subs = { "SPELL_CAST_START" },
    recount = false, wide = true, guid = true }
B["CT:[AQ40][Bug Trio] Toxic Volley"] = Ability{ key = "BUGTRIO_TOXIC_VOLLEY", spells = { 25812 }, start = false }

-- Sartura: only her own whirlwinds count, not her guards'
B["CT:[AQ40][Sartura] Whirlwind"] = Ability{ key = "SARTURA_WHIRLWIND", spells = { 26083 }, npc = "15516", first = 16, every = 25, prewarn = 3 }

-- Fankriss: every Mortal Wound stack goes on the bus; the worms come in
-- threes, so one summon in ten seconds counts
B["CT:[AQ40][Fankriss] Mortal Wound"] = Ability{ key = "FANKRISS_MORTAL_WOUND", spells = { 25646 },
    subs = { "SPELL_AURA_APPLIED", "SPELL_AURA_APPLIED_DOSE" }, show = false,
    after = function(env, subEvent, destGUID, amount)
        if subEvent == "SPELL_AURA_APPLIED_DOSE" then
            RM.Fire("WA_FANKRISS_MORTAL_WOUND_STACK", destGUID, amount)
        end
    end }
B["CT:[AQ40][Fankriss] Summon Worm"] = Ability{ key = "FANKRISS_SUMMON_WORM", spells = { 518, 25832, 25831 }, subs = { "SPELL_SUMMON" },
    throttle = 10, first = 20, every = 30, prewarn = 3 }

B["CT:[AQ40][Viscidus] Poison Volley"] = Ability{ key = "VISCIDUS_POISON_VOLLEY", spells = { 25991 }, first = 12.9, every = 11 }

-- Huhuran: berserk (phase 2) stops her frenzy, volley and sting timers
B["CT:[AQ40][Huhuran] Phase Controller"] = Relay{ spell = 26068, event = "WA_HUHURAN_P2_START", answer = true, stop = "HUHURAN_BERSERK" }
do
    local P2 = { WA_HUHURAN_P2_START = { "stop", "hide" } }
    B["CT:[AQ40][Huhuran] Frenzy"] = Ability{ key = "HUHURAN_FRENZY", spells = { 26051 }, subs = { "SPELL_AURA_APPLIED" },
        first = 9.6, every = 11.8, on = P2 }
    B["CT:[AQ40][Huhuran] Poison Bolt"] = Ability{ key = "HUHURAN_POISON_BOLT", spells = { 26053 }, show = false, every = 11, on = P2 }
    B["CT:[AQ40][Huhuran] Wyvern Sting"] = Ability{ key = "HUHURAN_WYVERN_STING", spells = { 26180 }, subs = { "SPELL_AURA_APPLIED" },
        throttle = 6, first = 20, every = 25, on = P2 }
end

-- Twin Emperors
B["CT:[AQ40][Twin Emperors] Berserk"] = Ability{ key = "TWINS_BERSERK", first = 900 }
B["CT:[AQ40][Twin Emperors][HM] Curse of Despair"] = Ability{ key = "TWINS_CURSE", spells = { 1213254 }, subs = { "SPELL_AURA_APPLIED" },
    throttle = 3.5, every = 30, prewarn = 3 }
-- Heal Brother (7393): an emperor healing the other, by the healer's name
B["CT:[AQ40][Twin Emperors] Heal Brother"] = Relay{ spell = 7393, sub = "SPELL_CAST_SUCCESS", event = "WA_TWINS_HEAL_BROTHER_CAST",
    pass = function(_, sourceName) return sourceName end }
B["CT:[AQ40][Twin Emperors] Mutate Bug"] = Ability{ key = "TWINS_MUTATE_BUG", spells = { 802 }, show = false, every = 11 }
B["CT:[AQ40][Twin Emperors] Teleport"] = Ability{ key = "TWINS_TELEPORT", spells = { 799, 800, 1217333 }, subs = { "SPELL_AURA_APPLIED" },
    throttle = 6, first = 29.2, every = 34, prewarn = 3 }

-- Ouro: three minutes up, then he submerges (WA_OURO_SUBMERGE) for thirty
-- seconds (WA_OURO_EMERGE); his blast and sweep pause while he is under
B["CT:[AQ40][Ouro] Phase Controller"] = Ability{ key = "OURO_SUBMERGE", spells = { 26058 }, first = 184, prewarn = 3,
    on = { WA_OURO_EMERGE = { 30 } }, finish = "all",
    after = function(env)
        RM.Fire("WA_OURO_SUBMERGE")
        if env.timer then env.timer:Cancel() end
        env.timer = C_Timer.NewTimer(30, function() RM.Fire("WA_OURO_EMERGE") end)
    end }
B["CT:[AQ40][Ouro] Sand Blast"] = Ability{ key = "OURO_SAND_BLAST", spells = { 26102 }, subs = { "SPELL_CAST_START" },
    first = 20, every = 23, prewarn = 3, on = { WA_OURO_EMERGE = { 24 }, WA_OURO_SUBMERGE = { "unwarn", "stop" } } }
B["CT:[AQ40][Ouro] Sweep"] = Ability{ key = "OURO_SWEEP", spells = { 26103 }, subs = { "SPELL_CAST_START" },
    first = 22, every = 29, prewarn = 3, on = { WA_OURO_EMERGE = { 23 }, WA_OURO_SUBMERGE = { "unwarn", "stop" } } }

-- C'Thun: the Eye's death starts phase 2
B["CT:[AQ40][C'thun] Phase Controller"] = {
    ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, _, _, _, destGUID)
        if subEvent == "UNIT_DIED" and K.NpcId(destGUID) == "15589" then
            RM.Fire("WA_CTHUN_P2_START")
        end
    end,
    ["actions.finish.custom"] = Quiet(),
}
-- Dark Glare has no combat log line: each countdown fires the glare event
-- when it runs out, and that counts as the glare
B["CT:[AQ40][C'thun] Dark Glare"] = Ability{ key = "CTHUN_DARK_GLARE", first = 48, every = 86, prewarn = 5,
    loop = "WA_CTHUN_DARK_GLARE_START", castOn = "WA_CTHUN_DARK_GLARE_START",
    on = { WA_CTHUN_P2_START = { "unloop", "unwarn", "stop" } } }
-- the tentacles: Birth (26586) from the right creature, one in five seconds
B["CT:[AQ40][C'thun] Claw Tentacles"] = Ability{ key = "CTHUN_CLAW_TENTACLE", spells = { 26586 }, npc = "15725",
    throttle = 5, first = 9, every = 8, prewarn = 3, on = { WA_CTHUN_P2_START = { "stop", "unwarn" } } }
B["CT:[AQ40][C'thun] Eye Tentacles"] = Ability{ key = "CTHUN_EYE_TENTACLES", spells = { 26586 }, npc = "15726",
    throttle = 5, first = 45, every = 45, prewarn = 3, on = { WA_CTHUN_P2_START = { "stop", "unwarn", 41.3 } } }
B["CT:[AQ40][C'thun] Giant Claw Tentacle"] = Ability{ key = "CTHUN_GIANT_CLAW_TENTACLE", spells = { 26586 }, npc = "15728",
    startOn = "WA_CTHUN_P2_START", throttle = 5, first = 11, every = 45, prewarn = 3 }
B["CT:[AQ40][C'thun] Giant Eye Tentacle"] = Ability{ key = "CTHUN_GIANT_EYE_TENTACLE", spells = { 26586 }, npc = "15334",
    startOn = "WA_CTHUN_P2_START", throttle = 5, first = 32, every = 35, prewarn = 3 }

-- Eye Beam: a moment after the cast starts, whoever the eye is looking at
-- is the target (looked for on your target, then on the nameplates)
do
    local function Showing(guid)
        if UnitExists("target") and UnitGUID("target") == guid then return "target" end
        for i = 1, 40 do
            local unit = "nameplate" .. i
            if UnitExists(unit) and UnitGUID(unit) == guid then return unit end
        end
    end
    B["CT:[AQ40][C'thun] Eye Beam"] = {
        ["init"] = function(env) env.eyeBeam = 26134 end,
        ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, sourceGUID, _, _, _, _, _, _, _, spellId)
            if spellId ~= 26134 then return false end
            if subEvent ~= "SPELL_CAST_START" then return end
            C_Timer.After(0.1, function()
                local unit = Showing(sourceGUID)
                if not unit then return end
                local looking = unit .. "target"
                if UnitExists(looking) then
                    RM.Fire("WA_CTHUN_EYE_BEAM_TARGET", UnitGUID(looking), looking)
                end
            end)
            return true
        end,
        ["actions.finish.custom"] = Quiet(true),
    }
end

-- "C'Thun is weakened" (the emote, per game language)
do
    local WEAKENED = {
        enUS = "weaken", deDE = "C'Thun ist geschwächt!", esES = "está débil!", esMX = "está débil!",
        frFR = "est affaibli !", koKR = "약해집니다!", ptBR = "enfraquece!", ruRU = "weaken",
        zhCN = "削弱了", zhTW = "變弱了",
    }
    B["CT:[AQ40][C'thun] Weakened"] = {
        ["init"] = function(env)
            env.currentLocale = { Weakened = WEAKENED[GetLocale()] or WEAKENED.enUS }
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, msg)
            if event == "CHAT_MSG_MONSTER_EMOTE" and msg and msg:find(env.currentLocale.Weakened) then
                RM.Fire("WA_CTHUN_WEAKENED")
            end
        end,
    }
end

-- ============================================================
-- VISCIDUS: FREEZE AND SHATTER
-- ============================================================
-- Reads his emotes into WA_VISCIDUS_STATUS (Slow, Freezing, Frozen,
-- Cracking, Shattering, Explode) and counts what gets him there: frost
-- hits and wand shots (WA_VISCIDUS_FROST_ATTACK n) until he freezes,
-- melee swings while frozen (WA_VISCIDUS_SHATTER_ATTACK n). Eleven
-- seconds after he bursts the count starts over (WA_VISCIDUS_RESET).
do
    local VISCIDUS, GLOB, WAND = "15299", "15667", 5019
    -- what each emote says, per game language, and the status it means
    local EMOTES = {
        enUS = { "begins to slow", "is freezing up", "is frozen solid", "begins to crack", "looks ready to shatter", "Explodes." },
        deDE = { "wird langsamer", "friert ein", "ist tiefgefroren", "geht die Puste aus", "ist kurz davor, zu zerspringen", "Explodes." },
        esES = { "comienza a ir más despacio!", "se está congelando!", "no se puede mover!", "comienza a desmoronarse!", "parece a punto de hacerse añicos!", "explota!" },
        esMX = { "comienza a ir más despacio!", "se está congelando!", "no se puede mover!", "comienza a desmoronarse!", "parece a punto de hacerse añicos!", "explota!" },
        frFR = { "commence à ralentir !", "est gelé !", "est congelé !", "commence à se briser !", "semble prêt à se briser !", "explose !" },
        koKR = { "느려지기 시작했습니다!", "얼어붙고 있습니다!", "단단하게 얼었습니다!", "분해되기 시작합니다!", "부서질 것 같습니다!", "폭발" },
        ptBR = { "começa a ficar lento!", "está congelando!", "está totalmente congelado!", "começa a rachar!", "parece estar a ponto de se estilhaçar!", "explode!" },
        ruRU = { "начинает замедляться", "замерзает", "заморожен", "начинает трескаться", "выглядит готовым разлететься вдребезги", "Взрывается." },
        zhCN = { "开始减速!", "冻住了", "变成冰冻的固体!", "开始爆裂!", "看來准备好毁灭了!", "爆炸。" },
        zhTW = { "開始減速!", "凍住了", "變成冰凍的固體!", "開始爆裂!", "看來準備好毀滅了!", "Explodes." },
    }
    local STATUS = { "Slow", "Freezing", "Frozen", "Cracking", "Shattering", "Explode" }

    local function Fresh(env)
        env.allow = true
        env.frozen = false
        env.count = 0
        env.swingCount = 0
    end
    local function Status(s) RM.Fire("WA_VISCIDUS_STATUS", s) end

    local function Emote(env, msg)
        for i, text in ipairs(env.emotes) do
            if msg:find(text) then
                local s = STATUS[i]
                Status(s)
                if s == "Frozen" then
                    env.allow = false
                    env.swingCount = 0
                    env.frozen = true
                elseif s == "Explode" then
                    env.frozen = false
                    env.swingCount = 0
                    env.emoteTriggered = true
                    C_Timer.After(11, function()
                        RM.Fire("WA_VISCIDUS_RESET")
                        env.emoteTriggered = false
                    end)
                end
                return
            end
        end
    end

    local function FrostHit(env)
        env.count = env.count + 1
        RM.Fire("WA_VISCIDUS_FROST_ATTACK", env.count)
    end

    B["CT:[AQ40][Viscidus] Phase Controller"] = {
        ["init"] = function(env)
            Fresh(env)
            env.npcID = VISCIDUS
            env.shoot = WAND
            env.emoteTriggered = false
            env.throttle = 0
            env.emotes = EMOTES[GetLocale()] or EMOTES.enUS
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, msg, subEvent, _, _, _, _, _, destGUID, _, _, _, spellId, _, spellSchool)
            if event == "ENCOUNTER_START" or event == "WA_VISCIDUS_RESET" then Fresh(env) end
            if event == "CHAT_MSG_MONSTER_EMOTE" and msg then Emote(env, msg) end
            -- a glob reaching him: he burst, if the emote did not say so
            if subEvent == "SPELL_AURA_APPLIED" and K.NpcId(destGUID) == GLOB then
                if GetTime() - env.throttle < 30 then return false end
                env.throttle = GetTime()
                if env.emoteTriggered then return false end
                Status("Explode")
            end
            if subEvent == "SWING_DAMAGE" then
                if not env.frozen then return false end
                if K.NpcId(destGUID) ~= VISCIDUS then return false end
                env.swingCount = env.swingCount + 1
                RM.Fire("WA_VISCIDUS_SHATTER_ATTACK", env.swingCount)
            end
            if not env.allow then return false end
            if subEvent == "SPELL_DAMAGE" then
                if K.NpcId(destGUID) ~= VISCIDUS then return false end
                if bit.band(spellSchool, 16) == 0 then return false end
                FrostHit(env)
            end
            if subEvent == "RANGE_DAMAGE" then
                if spellId ~= WAND then return false end
                if K.NpcId(destGUID) ~= VISCIDUS then return false end
                FrostHit(env)
            end
        end,
        ["actions.finish.custom"] = Quiet(true),
    }

    -- how frozen he is: 3 frozen solid, down to 0 when he bursts
    local DEPTH = { Slow = 1, Freezing = 2, Frozen = 3, Cracking = 2, Shattering = 1, Explode = 0 }
    B["PT:[AQ40][Viscidus] Frozen Tracker"] = {
        ["init"] = function(env) env.statusValues = DEPTH end,
        ["triggers.1.trigger"] = function(env, allstates, event, status)
            if event == "OPTIONS" then
                K.Put(allstates, "", { progressType = "static", value = math.random(0, 3), total = 3, status = "Frozen" })
                return true
            end
            local depth = event == "WA_VISCIDUS_STATUS" and DEPTH[status]
            if depth then
                K.Put(allstates, "", { progressType = "static", value = depth, total = 3, status = status })
                return true
            end
        end,
        ["conditions.2.changes.3.value"] = Voice("Frozen"),
        ["conditions.3.changes.2.value"] = Voice("Freezing"),
    }

    -- the hit counter: 200 frost hits to freeze, then 100 swings to shatter
    local function Counter(allstates, total, status)
        K.Put(allstates, "", { progressType = "static", value = 0, total = total, status = status })
        return true
    end
    B["PT:[AQ40][Viscidus] Frost Tracker"] = {
        ["init"] = function() end,
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "OPTIONS" then
                K.Put(allstates, "", { progressType = "static", value = math.random(0, 100), total = 100, status = "Frozen" })
                return true
            end
            if event == "WA_VISCIDUS_FROST_ATTACK" or event == "WA_VISCIDUS_SHATTER_ATTACK" then
                if env.allow then
                    local st = allstates[""]
                    if st then
                        st.value = (...)
                        st.changed = true
                    end
                    return true
                end
            end
            if event == "ENCOUNTER_START" or event == "WA_VISCIDUS_RESET" then
                env.allow = true
                return Counter(allstates, 200, "Slow")
            end
            if event == "WA_VISCIDUS_STATUS" then
                local status = ...
                if status == "Explode" then
                    env.allow = false
                    K.Drop(allstates, "")
                    return true
                elseif status == "Frozen" then
                    return Counter(allstates, 100, status)
                end
            end
        end,
    }

    local SAYS = {
        Slow = { "begins to Slow!", 135846 },
        Freezing = { "is freezing up", 135856 },
        Frozen = { "is frozen solid", 135859 },
        Cracking = { "begins to crack", 135858 },
        Shattering = { "looks ready to shatter!", 135857 },
        Explode = { "explodes!", 134538 },
    }
    B["SW:[AQ40][Viscidus] Status"] = {
        ["init"] = function(env) env.statusData = SAYS end,
        ["text"] = K.Always("|cFF6bfff1Viscidus|r"),
        ["triggers.1.trigger"] = function(env, allstates, event, status)
            if event == "OPTIONS" then
                K.Put(allstates, "", K.Timed(4, { autoHide = true, text = "begins to slow!", icon = 135840 }))
                return true
            end
            local says = event == "WA_VISCIDUS_STATUS" and SAYS[status]
            if says then
                K.Put(allstates, "", K.Timed(3.5, { autoHide = true, text = says[1], icon = says[2] }))
                return true
            end
        end,
    }

    -- Engineers: how many mobs a sapper would hit (checked five times a
    -- second while he is about to shatter)
    B["SA:[AQ40][Viscidus] Engi Sapper"] = {
        ["logic"] = function(env, t) return t[1] and t[2] and t[4] end,
        ["actions.start.custom"] = function(env)
            if env.ticker then return end
            env.ticker = C_Timer.NewTicker(0.2, function() RM.Fire("WA_VISCIDUS_SAPPER_RANGE_CHECK") end)
        end,
        ["actions.finish.custom"] = function(env)
            if env.ticker then
                env.ticker:Cancel()
                env.ticker = nil
            end
        end,
        ["triggers.3.trigger"] = function(env, allstates, event)
            if event == "OPTIONS" then
                K.Put(allstates, "", { count = math.random(1, 10) })
                return true
            end
            local near = 0
            for i = 1, 40 do
                local unit = "nameplate" .. i
                if UnitExists(unit) and RM.WA.CheckRange(unit, 10, "<=") then near = near + 1 end
            end
            allstates[""] = { show = near > 0, changed = true, count = near }
            return true
        end,
        ["triggers.4.trigger"] = function(env, allstates, event, status)
            if event == "OPTIONS" then
                K.Put(allstates, "", K.Timed(10, { autoHide = true }))
                return true
            end
            if event == "WA_VISCIDUS_STATUS" and status == "Shattering" then
                K.Put(allstates, "", K.Timed(24, { autoHide = true }))
                return true
            end
        end,
    }
end

-- ============================================================
-- C'THUN: FLESH TENTACLES AND EYE BEAM DEATHS
-- ============================================================
-- Each Flesh Tentacle's health, shared with the raid so everyone sees
-- both; every death goes out too (WA_FJI_TENTACLE_DIED 1 or 2).
do
    local FLESH = "15802"
    local function Health(allstates, guid, pct)
        local st = allstates[guid]
        if st then
            st.value = pct
            st.changed = true
        else
            K.Put(allstates, guid, { progressType = "static", total = 100, value = pct })
        end
    end
    B["L:[AQ40][C'thun] Flesh Tentacle Health"] = {
        ["init"] = function(env)
            env.deadCount = 0
            env.units = {}
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "OPTIONS" then
                Health(allstates, "preview1", math.random(1, 99))
                Health(allstates, "preview2", math.random(1, 99))
                return true
            end
            if event == "UNIT_HEALTH" then
                -- (every raider's health change comes through here: turn
                -- the rest away before reading anything)
                local unit = ...
                local guid = UnitGUID(unit)
                if not (guid and guid:find("-15802-", 1, true) and K.NpcId(guid) == FLESH) then return end
                local now, most = UnitHealth(unit), UnitHealthMax(unit)
                local pct = math.floor(now / most * 100)
                if now > 0 then Share("WA_FJI_TENTACLE_HEALTH_SYNC", guid, pct) end
                Health(allstates, guid, pct)
                return true
            elseif event == "WA_FJI_TENTACLE_HEALTH_SYNC" then
                local guid, pct = ...
                Health(allstates, guid, pct)
                return true
            elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
                local _, subEvent, _, _, _, _, _, destGUID = ...
                if subEvent ~= "UNIT_DIED" then return end
                if K.NpcId(destGUID) ~= FLESH then return end
                env.deadCount = env.deadCount + 1
                Share("WA_FJI_TENTACLE_DIED", env.deadCount)
                if env.deadCount == 2 then env.deadCount = 0 end
                if allstates[destGUID] then K.Drop(allstates, destGUID) end
                return true
            end
        end,
    }
end

-- ============================================================
-- ICONS AND LARGE ICONS
-- ============================================================
B["I:[AQ40][Trash] Fear Ward"] = { ["logic"] = function(env, t) return t[1] and t[2] and _G.FJI_TANK end }
do
    local CASTERS = K.Set{ "PALADIN", "PRIEST", "DRUID", "MAGE", "WARLOCK", "SHAMAN" }
    B["I:[AQ40][Trash] Silence"] = {
        ["init"] = function(env) env.classes = CASTERS end,
        ["conditions.1.check.fn"] = function() return CASTERS[UnitClassBase("player")] end,
        ["conditions.1.changes.1.value"] = Voice("Silenced"),
    }
end

-- Skeram's images: is the one you target the real one (more than 400k
-- health) or an image, and its mark
do
    local SKERAM = "15263"
    local function MarkText()
        local mark = GetRaidTargetIndex("target")
        return mark and ICON_LIST[mark] .. "0|t"
    end
    local function TargetIsSkeram()
        return UnitExists("target") and K.NpcId(UnitGUID("target")) == SKERAM
    end
    B["I:[AQ40][Skeram] Real or Fake"] = {
        ["text"] = function() return MarkText() or "" end,
        ["triggers.1.name"] = function(env) return env.skeram end,
        ["triggers.1.trigger"] = function(env, allstates, event)
            local st = allstates[""]
            if event == "OPTIONS" then
                K.Put(allstates, "", { status = "REAL", mark = ICON_LIST[8] .. "0|t" })
                return true
            end
            if event == "RAID_TARGET_UPDATE" and st and TargetIsSkeram() then
                st.mark = MarkText()
                st.changed = true
                return true
            end
            if event ~= "PLAYER_TARGET_CHANGED" then return end
            if st then
                st.mark = ""
                st.changed = true
            end
            if not UnitExists("target") then
                if st then return K.Drop(allstates, "") end
                return
            end
            if TargetIsSkeram() then
                K.Put(allstates, "", { mark = MarkText(), status = UnitHealthMax("target") > 400000 and "REAL" or "FAKE" })
            elseif st then
                K.Drop(allstates, "")
            end
            return true
        end,
    }
end

B["I:[AQ40][Bug Trio] Fear"] = Talk("Fear")
B["I:[AQ40][Bug Trio] Knockdown"] = Talk("Stunned")
B["I:[AQ40][Bug Trio] Ravage"] = Talk("Stunned")
-- each Sundering Cleave stack costs 240 armour
B["I:[AQ40][Sartura] Sundering Cleave"] = { ["text"] = PerStack(240, "-") }
B["I:[AQ40][Fankriss] Entangle"] = Talk("Entangled")
-- each Mortal Wound stack: 10% less healing
B["I:[AQ40][Fankriss] Mortal Wound"] = { ["logic"] = NotTank, ["text"] = PerStack(10, "-") }
B["I:[AQ40][Viscidus] Toxin"] = Talk("Entangled")
-- each Acid Spit stack: 200 more damage taken
B["I:[AQ40][Huhuran] Acid Spit"] = { ["logic"] = NotTank, ["text"] = PerStack(200) }
B["I:[AQ40][Ouro] Sand Blast"] = Talk("Stunned")

B["IL:[AQ40][Trash] Itch"] = K.Merge(Talk("Itchy"), {
    ["conditions.1.changes.1.value"] = Voice("1"),
    ["conditions.2.changes.1.value"] = Voice("2"),
})
B["IL:[AQ40][Trash] Vekniss Catalyst"] = Talk("Poisoned")
B["IL:[AQ40][Trash] Cause Insanity"] = Talk("Mind Controlled")
B["IL:[AQ40][Skeram] True Fulfillment"] = Talk("Mind Controlled")
B["IL:[AQ40][Twin Emperors] Unbalancing Strike"] = Talk("Reduced Defense")
-- each Acid Spray stack: 100 more damage taken
B["IL:[AQ40][C'thun] Acid Spray"] = { ["text"] = PerStack(100, "+") }

-- ============================================================
-- ANUBISATH HELPER: WHAT EACH SENTINEL CAN DO
-- ============================================================
-- An Anubisath Sentinel or Defender gets a row once Detect Magic lands on
-- it, it reflects a spell or it uses an ability. Its buff is read from
-- your target or mouseover (after Detect Magic, on a target or mouseover
-- change) and shared with the raid over the AQ40AH addon channel
-- ("guid+icon+prio+message[+true]"), so one look fills everyone's list.
-- The rows sort by the kill order picked in the options (prio). When one
-- of the two reflecting Anubisaths dies, the other one reflects all.
--
-- It sits on a busy event list, so the combat log and the addon channel
-- are filtered before any work, and nothing is looked up on every line.
do
    local PREFIX = "AQ40AH"
    local ANUB = K.Set{ "15264", "15277" }   -- Sentinel, Defender
    local REFLECT_ALL = 135820
    -- abilities seen in the combat log, by spell: icon, option for the
    -- kill order, the name shown
    local CASTS = {
        { 2147, 136085, "mendingPrio", "Mending" },
        { 15548, 132326, "thunderClapPrio", "Thunder Clap" },
        { 24573, 132355, "mortalStrikePrio", "Mortal Strike" },
        { 26546, 136163, "shadowStormPrio", "Shadow Storm" },
        { 18670, 132330, "knockAwayPrio", "Knock Away" },
        { 25777, 136104, "thornsPrio", "Thorns" },
        { 26046, 136170, "manaBurnPrio", "Mana Burn" },
    }
    -- the buffs that tell which one it is, in the order they are looked for
    local LOOKS = {
        { "mending", 2147, 136085, "mendingPrio", "Mending" },
        { "shadowFrost", 19595, 136141, "shadowReflectPrio", "Shadow/Frost Reflect" },
        { "mortalStrike", 9347, 132355, "mortalStrikePrio", "Mortal Strike" },
        { "shadowStorm", 2148, 136163, "shadowStormPrio", "Shadow Storm" },
        { "thunderClap", 2834, 132326, "thunderClapPrio", "Thunder Clap" },
        { "knockAway", 21737, 132330, "knockAwayPrio", "Knock Away" },
        { "thorns", 25777, 136104, "thornsPrio", "Thorns" },
        { "manaBurn", 812, 136170, "manaBurnPrio", "Mana Burn" },
        { "fireArcane", 13022, 136115, "fireReflectPrio", "Fire/Arcane Reflect" },
    }
    local SAMPLES = {
        { 136085, "Mending", 7 },
        { 136141, "Shadow/Frost Reflect", 8, purple = true, targeted = true },
        { 132355, "Mortal Strike", 6 },
        { 136115, "Fire/Arcane Reflect", 5 },
    }

    local function IsAnub(guid) return ANUB[K.NpcId(guid)] end
    local function Targeted(env, guid)
        return UnitGUID("target") == guid and env.config.option.currentTarget
    end
    -- a new row
    local function Row(env, allstates, guid, fields)
        local st = { show = true, progressType = "static", value = 1, total = 1, abilityText = env.config.option.abilityText,
            targeted = Targeted(env, guid) }
        for k, v in pairs(fields) do st[k] = v end
        allstates[guid] = st
        return true
    end

    -- Every listed Anubisath shows its raid mark, read from the nameplates
    -- when a mark changes or a plate appears.
    local function Marks(allstates)
        local any = false
        for i = 1, 40 do
            local unit = "nameplate" .. i
            local guid = UnitExists(unit) and UnitGUID(unit)
            local st = guid and allstates[guid]
            if st then
                local mark = GetRaidTargetIndex(unit)
                local text = mark and format("{rt%d}", mark) or ""
                if st.newMark ~= text or (st.RaidFlags or 0) ~= 0 then
                    st.newMark = text
                    st.RaidFlags = 0
                    st.changed = true
                    any = true
                end
            end
        end
        return any
    end

    -- Reads unit's buffs into its row and tells the raid. Answers true
    -- when the row had nothing yet (the read is the trigger's answer).
    local function Look(env, st, unit, isTarget)
        st.RaidFlags = 0
        local mark = GetRaidTargetIndex(unit)
        if mark then
            if not isTarget then st.changed = true end
            st.newMark = format("{rt%s}", mark)
        else
            st.newMark = ""
        end
        if st.texture then return false end
        for _, look in ipairs(LOOKS) do
            local b = env.buffs[look[1]]
            if RM.GetUnitBuff(unit, b.id) then
                local tail = ""
                if look[1] == "shadowFrost" then
                    if isTarget then env.frostR = UnitGUID("target") end
                    st.purple = true
                    tail = "+true"
                end
                st.texture, st.prio, st.message = b.icon, b.prio, b.message
                C_ChatInfo.SendAddonMessage(PREFIX, UnitGUID(unit) .. "+" .. st.texture .. "+" .. st.prio .. "+" .. st.message .. tail, "RAID")
                break
            end
        end
        if st.texture then st.changed = true end
        return true
    end

    -- An ability from an Anubisath: fill in its row, or make one.
    local function Used(env, allstates, cast, sourceGUID, sourceRaidFlags)
        if not (cast and sourceGUID and IsAnub(sourceGUID)) then return end
        local st = allstates[sourceGUID]
        if st and not st.texture then
            st.changed = true
            st.prio, st.texture, st.message = cast.prio, cast.icon, cast.message
            return true
        elseif not st then
            return Row(env, allstates, sourceGUID, { RaidFlags = sourceRaidFlags, message = cast.message, texture = cast.icon,
                purple = false, prio = cast.prio })
        end
    end

    -- One of the reflecting pair died: the other reflects everything.
    local function ReflectAll(env, allstates)
        local fire, frost = allstates[env.fireR], allstates[env.frostR]
        local function Gone(st) return st == nil or st == "" end
        local st
        if fire and Gone(frost) then
            st = fire
        elseif frost and Gone(fire) then
            st = frost
            st.purple = false
        else
            return
        end
        st.changed = true
        st.texture = REFLECT_ALL
        st.message = "Reflect All"
        return true
    end

    local function Retarget(env, allstates)
        for guid, st in pairs(allstates) do
            st.targeted = Targeted(env, guid)
            st.changed = true
        end
        return true
    end

    B["group:[AQ40]: Anubisath Helper [Oron]"] = {
        -- the kill order picked in the options
        ["customSort"] = function(a, b)
            local x, y = a.region.state.prio, b.region.state.prio
            if x and y then return x < y end
        end,
    }

    B["L:[AQ40][Trash] Ability Icons"] = {
        ["init"] = function(env)
            local opt = env.config.option
            env.detectMagic = GetSpellInfo(2855)
            env.spells = {}
            for _, c in ipairs(CASTS) do
                env.spells[GetSpellInfo(c[1])] = { icon = c[2], prio = opt[c[3]], message = c[4] }
            end
            env.buffs = {}
            for _, l in ipairs(LOOKS) do
                env.buffs[l[1]] = { id = l[2], icon = l[3], prio = opt[l[4]], message = l[5] }
            end
            env.anubIDs = ANUB
            env.fireR = false
            env.frostR = false
            env.prefix = PREFIX
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end,
        -- a raid mark straight from the combat log flags
        ["text"] = function(env)
            local flag = env.state and env.state.RaidFlags
            if not (flag and flag > 0) then return "" end
            local mark = 0
            while flag >= 1 do
                flag = flag / 2
                mark = mark + 1
            end
            return ("{rt%d}"):format(mark)
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, prefix, subEvent, _, sourceGUID, _, _, sourceRaidFlags, destGUID, destName, _, destRaidFlags, _, spellName, spellSchool, missType)
            if event == "RAID_TARGET_UPDATE" or event == "NAME_PLATE_UNIT_ADDED" then
                return Marks(allstates)
            end
            local fromLog = event == "COMBAT_LOG_EVENT_UNFILTERED"
            local reflected = subEvent == "SPELL_MISSED" and missType == "REFLECT"
            if fromLog then
                if subEvent ~= "UNIT_DIED" and spellName ~= env.detectMagic and not env.spells[spellName] and not reflected then
                    return false
                end
            elseif event == "CHAT_MSG_ADDON" and prefix ~= PREFIX then
                return false
            end
            local cast = env.spells[spellName]
            local d = allstates[destGUID]

            -- someone else read a buff: copy it onto our row
            if event == "CHAT_MSG_ADDON" then
                local guid, texture, prio, message, purple = strsplit("+", subEvent)
                local st = allstates[guid]
                if st then
                    st.changed = true
                    st.texture = tonumber(texture)
                    st.prio = tonumber(prio)
                    st.message = message
                    if purple == "true" then st.purple = true end
                    return true
                end
            end

            -- a new row: a reflect (fire/arcane or shadow/frost), or Detect
            -- Magic on it (its buff is read a moment later)
            if reflected and (spellSchool == 4 or spellSchool == 64) and destGUID and not d then
                if IsAnub(destGUID) then
                    env.fireR = destGUID
                    local b = env.buffs.fireArcane
                    return Row(env, allstates, destGUID, { changed = true, RaidFlags = destRaidFlags, destName = destName,
                        texture = b.icon, prio = b.prio, message = b.message })
                end
            elseif reflected and (spellSchool == 16 or spellSchool == 32) and destGUID and not d then
                if IsAnub(destGUID) then
                    env.frostR = destGUID
                    local b = env.buffs.shadowFrost
                    return Row(env, allstates, destGUID, { changed = true, RaidFlags = destRaidFlags, destName = destName,
                        texture = b.icon, prio = b.prio, message = b.message })
                end
            elseif spellName == env.detectMagic and destGUID and not d then
                if IsAnub(destGUID) and (subEvent == "SPELL_AURA_APPLIED" or (subEvent == "SPELL_MISSED" and missType == "RESIST")) then
                    C_Timer.After(0.3, function() RM.Fire("WA_AQ40_AH_REFRESH") end)
                    return Row(env, allstates, destGUID, { RaidFlags = destRaidFlags, destName = destName, message = "", prio = 999 })
                end
            end

            -- your target, else your mouseover: read its buffs (never on a
            -- combat log line)
            if not fromLog then
                local target = allstates[UnitGUID("target")]
                if target then
                    if Look(env, target, "target", true) then return true end
                else
                    local over = allstates[UnitGUID("mouseover")]
                    if over and Look(env, over, "mouseover", false) then return true end
                end
            end

            if event == "PLAYER_TARGET_CHANGED" then return Retarget(env, allstates) end
            local used = Used(env, allstates, cast, sourceGUID, sourceRaidFlags)
            if used then return true end
            if env.frostR and env.fireR and subEvent == "UNIT_DIED" and ReflectAll(env, allstates) then return true end
            if d and subEvent == "UNIT_DIED" then
                d.changed = true
                d.show = false
                return true
            end
            -- out of combat: start over
            if event == "PLAYER_REGEN_ENABLED" then
                env.fireR = false
                env.frostR = false
                for _, st in pairs(allstates) do
                    st.show = false
                    st.changed = true
                end
                return true
            end
            -- the options window: four sample rows to place the list by
            if RM.WA.IsOptionsOpen() then
                for i, s in ipairs(SAMPLES) do
                    allstates[i] = { show = true, changed = true, progressType = "static", value = 1, total = 1,
                        texture = s[1], message = s[2], prio = i, newMark = format("{rt%s}", s[3]), optionsText = "",
                        abilityText = env.config.option.abilityText, purple = s.purple,
                        targeted = s.targeted and env.config.option.currentTarget }
                end
                return true
            end
        end,
    }
end

-- ============================================================
-- MISC
-- ============================================================
-- Hold Shift when talking to an NPC to pick its first option.
B["[AQ40]: AutoGossip"] = {
    ["triggers.1.trigger"] = function(env, event)
        if event ~= "GOSSIP_SHOW" then return end
        if not IsShiftKeyDown() then return false end
        if not env.config.option.enable then return false end
        local options = C_GossipInfo.GetOptions()
        if options and #options > 0 then
            local id = options[1].gossipOptionID
            if C_GossipInfo.SelectOption then C_GossipInfo.SelectOption(id) else SelectGossipOption(id) end
        end
    end,
}
B["[AQ40]: Auto Skip Cinematic"] = {
    ["triggers.1.trigger"] = function(env, event)
        if not env.config.option.enable then return false end
        if event == "CINEMATIC_START" then
            CinematicFrame_CancelCinematic()
            return true
        elseif event == "PLAY_MOVIE" then
            MovieFrame:Hide()
            return true
        end
    end,
}
-- With its option on, the big boss-emote text in the middle of the screen
-- stops listening.
B["[AQ40]: Disable Raid Emotes"] = K.MuteBossEmotes()

-- standing in something: the alarm, when it is switched on
do
    local function Alarm(env)
        local opt = env.config.option
        if opt.enable then RM.RaidSound(opt.gtfoSound) end
    end
    B["GTFO:[AQ40][Twin Emperors] GTFO"] = { ["actions.start.custom"] = Alarm }
    B["GTFO:[AQ40][Viscidus] GTFO"] = { ["actions.start.custom"] = Alarm }
    B["GTFO:[AQ40][Bug Trio] GTFO"] = { ["actions.start.custom"] = Alarm }
end

-- ============================================================
-- NAMEPLATES
-- ============================================================
B["N:[AQ40][Trash] Whirlwind"] = { ["text"] = K.Field("addColour") }
B["N:[AQ40][Trash] Champion Vengeance"] = K.Merge(K.PlateBuff{ npcs = { "15252" }, spells = { 25164 }, dur = 10 }, { ["text"] = K.Field("addColour") })
B["N:[AQ40][Trash] Frenzy"] = K.Merge(K.PlateBuff{ npcs = { "15250" }, spells = { 26041 }, dur = 10 }, { ["text"] = K.Field("addColour") })
B["N:[AQ40][Trash] WW"] = K.Merge(K.PlateBuff{ npcs = { "15250" }, spells = { 26038 }, dur = 2 }, { ["text"] = K.Field("addColour") })
B["N:[AQ40][Bug Trio] Cleave"] = { ["init"] = function(env) env.guidData = {} end }
B["N:[AQ40][Sartura] WW"] = K.Merge(K.PlateBuff{ npcs = { "15516" }, spells = { 26083 }, dur = 15 }, { ["text"] = K.Field("addColour") })
B["N:[AQ40][Twin Emperors] Explode Bug"] = { ["text"] = K.Field("addColour") }

-- ============================================================
-- PROGRESS BARS
-- ============================================================
-- a Qiraji Scarab about to explode, until it dies
B["PC:[AQ40][Trash] Explode"] = K.Merge(Talk("Exploding"), {
    ["text"] = K.Field("addColour"),
    ["triggers.1.trigger"] = function(env, allstates, event, ...)
        if event == "WA_AQ40_TRASH_EXPLODE" then
            local guid = ...
            K.Put(allstates, guid, K.Timed(6, { autoHide = true, icon = 135826 }))
            return true
        end
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            local _, subEvent, _, _, _, _, _, destGUID = ...
            if subEvent == "UNIT_DIED" and allstates[destGUID] then return K.Drop(allstates, destGUID) end
        end
    end,
})
B["PC:[AQ40][Skeram] Arcane Explosion"] = CastingMob("SKERAM_ARCANE_EXPLOSION", 1)
B["PC:[AQ40][Bug Trio] Heal"] = K.Merge(CastingMob("BUGTRIO_HEAL", 2), Talk("Kick Heal"))
B["PC:[AQ40][Ouro] Sand Blast"] = K.Merge(GoneOff("OURO_SAND_BLAST", 2), Talk("Blast"), { ["text"] = K.Field("addColour") })
B["PC:[AQ40][C'thun] Dark Glare"] = K.Merge(
    DropOn(K.Flash{ event = "WA_CTHUN_DARK_GLARE_START", dur = 37, sample = Same(37), sampleShows = true }, "WA_CTHUN_P2_START"),
    Talk("Dark Glare"), { ["text"] = K.Field("addColour") })
B["PC:[AQ40][C'thun] Weakened"] = K.Merge(
    K.Flash{ event = "WA_CTHUN_WEAKENED", dur = 45, icon = 134399, sample = Same(45, 134399), sampleShows = true },
    { ["text"] = K.Field("addColour") })

-- Your raid role on entering the temple, from the role flags (Melee when
-- none is set).
do
    local function ReadRole(env)
        if _G.FJI_HEALER then env.role = "Healer"
        elseif _G.FJI_RANGED then env.role = "Ranged"
        elseif _G.FJI_TANK then env.role = "Tank"
        elseif _G.FJI_MELEE then env.role = "Melee"
        end
    end
    local LOOK = {
        Melee = { "DAMAGE", "|cFFFF0000" },
        Ranged = { "DAMAGE", "|cFFFF0000" },
        Healer = { nil, "|cFF00FF00" },
        Tank = { "TANK", "|cFFADD8E6" },
    }
    B["PT:[AQ40] Raid Role on Zone-In"] = {
        ["init"] = function(env)
            env.role = "Melee"
            env.getRole = function()
                ReadRole(env)
                return env.role
            end
        end,
        ["logic"] = function(env, t) return t[1] and not (t[2] or t[3]) end,
        ["conditions.1.check.fn"] = function() return not RM.WA.IsOptionsOpen() end,
        ["text"] = function(env)
            if RM.WA.IsOptionsOpen() then env.role = "Melee" end
            local look = LOOK[env.role]
            local roleText = look and look[1] or env.role
            return (look and look[2] or "|cFFFFFFFF") .. roleText .. "|r"
        end,
        ["triggers.1.trigger"] = function(env, event)
            local zone = select(8, GetInstanceInfo())
            if event == "OPTIONS" then env.role = env.getRole() end
            if zone == 531 then
                env.role = env.getRole()
                return env.role
            end
        end,
        ["triggers.2.trigger"] = K.Always(true),
        ["actions.finish.custom"] = function(env) env.difficulty = nil end,
    }
end

-- Anubisath Warder casts: which one is coming
B["SA:[AQ40][Trash] Warder Casts"] = {
    ["conditions.1.changes.1.value"] = Voice("Dust Cloud"),
    ["conditions.2.changes.2.value"] = Voice("Roots"),
    ["conditions.3.changes.2.value"] = Voice("Fear"),
}
-- Obsidian Nullifier mana: 35% and 15% warnings
B["PT:[AQ40][Trash] Nullifier Mana"] = { ["conditions.1.changes.1.value"] = function() RM.Fire("WA_AQ40_NULLIFIER_MANA_35") end }
B["SA:[AQ40][Trash] Nullifier Mana < 10%"] = { ["actions.start.custom"] = function() RM.Fire("WA_AQ40_NULLIFIER_MANA_15") end }
B["SA:[AQ40][Trash] Mana Burn"] = { ["logic"] = function(env, t) return t[1] and not t[2] end }

-- Ouro under: thirty seconds to his return
B["PT:[AQ40][Ouro] Emerge Timer"] = {
    ["actions.start.custom"] = function() RM.Speak("Submerge", 75, 1.2) end,
    ["conditions.1.changes.1.value"] = Voice("Emerge in 3"),
    ["triggers.1.icon"] = K.Always(236197),
    ["triggers.1.trigger"] = K.Always(true),
}

-- ============================================================
-- RAID FRAMES
-- ============================================================
do
    local dispelMagic = ClassOrLead("PALADIN", "PRIEST")
    B["RF:[AQ40][Trash] Dust Cloud"] = { ["conditions.1.check.fn"] = dispelMagic }
    B["RF:[AQ40][Trash] Vekniss Catalyst"] = { ["conditions.1.check.fn"] = ClassOrLead("PALADIN", "DRUID", "SHAMAN") }
    B["RF:[AQ40][Bug Trio] Fear"] = { ["conditions.1.check.fn"] = ClassOrLead("PALADIN", "PRIEST", "SHAMAN") }
    B["RF:[AQ40][Bug Trio] Toxic Spore"] = { ["conditions.1.check.fn"] = HealerOrLead }
    B["RF:[AQ40][Sartura] Whirlwind Damage"] = K.HitGlow{ spells = { 26686 } }
    B["RF:[AQ40][Fankriss] Toxic Pool Damage"] = K.Merge(K.HitGlow{ spells = { 1215421 } }, { ["conditions.1.check.fn"] = HealerOrLead })
    B["RF:[AQ40][Viscidus] Poison Volley"] = { ["conditions.1.check.fn"] = HealerOrLead }
    B["RF:[AQ40][Viscidus] Toxin"] = { ["conditions.1.check.fn"] = HealerOrLead }
    B["RF:[AQ40][Twin Emperors] Shadow Bolt"] = K.Merge(K.HitGlow{ spells = { 26006 } }, { ["conditions.1.check.fn"] = HealerOrLead })
    B["RF:[AQ40][Twin Emperors] Blizzard"] = { ["conditions.1.check.fn"] = HealerOrLead }
    B["RF:[AQ40][Twin Emperors] Unbalancing Strike"] = { ["conditions.1.check.fn"] = HealerOrLead }
    B["RF:[AQ40][Ouro] Sweep"] = K.Merge(K.HitGlow{ spells = { 26103 } }, { ["conditions.1.check.fn"] = HealerOrLead })
    B["RF:[AQ40][C'thun] Eye Beam"] = K.Merge(K.HitGlow{ spells = { 26134 } }, { ["conditions.1.check.fn"] = HealerOrLead })
end

-- ============================================================
-- SPECIAL ALERTS AND WARNINGS
-- ============================================================
-- Plague on you: yell the cross mark every two seconds until it ends
B["SA:[AQ40][Trash] Plague"] = {
    ["actions.start.custom"] = function(env)
        if env.ticker then return end
        env.ticker = C_Timer.NewTicker(2, function() SendChatMessage("{rt7}", "YELL") end)
    end,
    ["actions.finish.custom"] = function(env)
        if env.ticker then
            env.ticker:Cancel()
            env.ticker = nil
        end
    end,
}
B["SA:[AQ40][Bug Trio] Summon Poison Cloud"] = Talk("Watch Cloud")
B["SA:[AQ40][Sartura] Whirlwind"] = K.Merge(GoneOff("SARTURA_WHIRLWIND", 15), Talk("Whirlwind"))
-- the Eye Beam is on you
B["SA:[AQ40][C'thun] Eye Beam"] = K.Merge(Talk("Targeted"), {
    ["triggers.1.trigger"] = function(env, allstates, event, guid)
        if event == "WA_CTHUN_EYE_BEAM_TARGET" then
            allstates[""] = K.Timed(2, { show = guid == RM.WA.myGUID, changed = true, autoHide = true })
            return true
        end
    end,
})

B["SW:[AQ40][Trash] Nullifier Mana 15% Warn"] = K.Flash{ event = "WA_AQ40_NULLIFIER_MANA_15", dur = 3.5, icon = 136208, sample = K.IconSample(136208) }
B["SW:[AQ40][Trash] Nullifer Mana 35% Warn"] = DropOn(
    K.Flash{ event = "WA_AQ40_NULLIFIER_MANA_35", icon = 136208, sample = K.IconSample(136208) }, "WA_AQ40_NULLIFIER_MANA_15")
B["SW:[AQ40][Trash] Cause Insanity"] = K.Merge(SomeoneElse("WA_AQ40_TRASH_MC_TARGET", 136206, 3), K.Speak{ say = "MC" })
B["SW:[AQ40][Trash] Plague"] = K.Merge(SomeoneElse("WA_AQ40_PLAGUE_APPLIED", 136140, 3), K.Speak{ say = "Plague" })
B["SW:[AQ40][Trash] Champion Vengeance"] = K.Merge(
    K.Flash{ event = "WA_AQ40_CHAMPION_VENGEANCE", icon = 132275, sample = K.IconSample(132275) }, K.Speak{ say = "Vengeance" })
B["SW:[AQ40][Trash] Slayer Frenzy"] = K.Flash{ event = "WA_AQ40_SLAYER_FRENZY", icon = 132117, sample = K.IconSample(132117) }
B["SW:[AQ40][Skeram] Summon Images"] = GoneOff("SKERAM_SUMMON_IMAGES", 2, 236414, 2)
B["SW:[AQ40][Skeram] True Fulfillment"] = SomeoneElse("WA_SKERAM_MC_TARGET", 136129, 3)
B["SW:[AQ40][Sartura] Whirlwind PreWarn"] = K.Merge(Soon("WA_SARTURA_WHIRLWIND_PREWARN"), Talk("Whirlwind Soon"))
B["SW:[AQ40][Fankriss] Worms PreWarn"] = Soon("WA_FANKRISS_SUMMON_WORM_PREWARN", 236197)
-- five or more Mortal Wound stacks on someone
B["SW:[AQ40][Fankriss] Mortal Wound High Stacks"] = {
    ["triggers.1.trigger"] = function(env, allstates, event, guid, amount)
        if event == "OPTIONS" then
            allstates[""] = { show = true, icon = 132109, guid = RM.WA.myGUID, stacks = math.random(5, 10) }
        end
        if event == "WA_FANKRISS_MORTAL_WOUND_STACK" and type(amount) == "number" and amount >= 5 then
            K.Put(allstates, "", K.Timed(3, { icon = 132109, autoHide = true, guid = guid, stacks = amount }))
            return true
        end
    end,
}
B["SW:[AQ40][Twin Emperors] Teleport"] = K.Merge(GoneOff("TWINS_TELEPORT", 2, 135736, 2), Talk("TP"))
B["SW:[AQ40][Twin Emperors] Unbalancing Strike"] = { ["logic"] = function(env, t) return t[1] and HealerOrLead() end }
B["SW:[AQ40][Ouro] Sand Blast PreWarn"] = K.Merge(Soon("WA_OURO_SAND_BLAST_PREWARN", 136018), Talk("Blast Soon", LeadHealerOrTank))
B["SW:[AQ40][C'thun] Dark Glare PreWarn"] = K.Merge(Soon("WA_CTHUN_DARK_GLARE_PREWARN", 136197), Talk("Glare Soon"))
B["SW:[AQ40][C'thun] Dark Glare"] = K.Flash{ event = "WA_CTHUN_DARK_GLARE_START", icon = 136197, sample = Same(3, 136197), sampleShows = true }
-- a Flesh Tentacle died (1 or 2)
B["SW:[AQ40][C'thun] Flesh Tentacle Death"] = {
    ["init"] = function(env) env.throttle = 0 end,
    ["triggers.1.trigger"] = function(env, allstates, event, count)
        if event == "OPTIONS" then
            K.Put(allstates, "", K.Timed(3, { autoHide = true, icon = 134899, count = math.random(1, 2) }))
            return true
        end
        if event == "WA_FJI_TENTACLE_DIED" then
            if GetTime() - env.throttle < 0.1 then return false end
            env.throttle = GetTime()
            K.Put(allstates, "", K.Timed(3, { autoHide = true, icon = 134899, count = count }))
            return true
        end
    end,
}
B["SW:[AQ40][C'thun] Weakened"] = K.Flash{ event = "WA_CTHUN_WEAKENED", icon = 134399, sample = Same(3, 134399), sampleShows = true }

-- the heads-up circles
B["C:[AQ40][Skeram] True Fulfillment"] = GoneOff("SKERAM_TRUE_FULFILLMENT", 0.5, 136129, 0.5)
B["C:[AQ40][Ouro] Sweep PreWarn"] = K.Merge(Soon("WA_OURO_SWEEP_PREWARN", 136104), Talk("Sweep Soon"))
B["C:[AQ40][Ouro] Sweep Cast"] = K.Merge(GoneOff("OURO_SWEEP", 1.5, 136104, 1.5), Talk("Sweep"), { ["triggers.1.icon"] = K.Always(SOON_ICON) })

-- ============================================================
-- TEXTS
-- ============================================================
-- how far each boss is from its next health phase
B["T:[AQ40][Skeram] Split Warn"] = K.Merge(Talk("Split Soon"), {
    ["logic"] = function(env, t) return t[1] or t[2] or t[3] end,
    ["text"] = HealthToGo("SPLIT", { 75, 50, 25 }),
    ["triggers.4.icon"] = K.Always(236414),
    ["triggers.4.trigger"] = K.Always(true),
})
B["T:[AQ40][Sartura] Enrage"] = {
    ["logic"] = First,
    ["text"] = HealthToGo("ENRAGE", { 25 }),
    ["triggers.2.icon"] = K.Always(132117),
    ["triggers.2.trigger"] = K.Always(true),
}
B["T:[AQ40][Huhuran] Berserk"] = {
    ["logic"] = First,
    ["text"] = HealthToGo("BERSERK", { 30 }),
    ["triggers.2.icon"] = K.Always(132117),
    ["triggers.2.trigger"] = K.Always(true),
}

B["T:[AQ40][Bug Trio] Toxic Volley"] = GoneOff("BUGTRIO_TOXIC_VOLLEY", 3, 136016, 2)
B["T:[AQ40][Fankriss] Summon Worm"] = K.Merge(GoneOff("FANKRISS_SUMMON_WORM", 3, 236197, 2), Talk("Worms"))
B["T:[AQ40][Huhuran] Phase"] = K.Merge(Called{ events = { WA_HUHURAN_P2_START = "PHASE 2" }, icon = 132117, sample = { 3, "PHASE 2" } },
    { ["conditions.1.changes.1.value"] = Voice("Phase 2") })
-- frenzy: hunters (tranq shot), the leader, tanks and healers hear it
B["T:[AQ40][Huhuran] Frenzy"] = K.Merge(GoneOff("HUHURAN_FRENZY", 3, 132117, 2), {
    ["text"] = K.Always("|cFF48ff6fPrincess Huhuran|r"),
    ["actions.start.custom"] = Voice("Frenzy", function()
        return UnitClass("player") == "Hunter" or UnitIsGroupLeader("player") or _G.FJI_TANK or _G.FJI_HEALER
    end),
})
B["T:[AQ40][Twin Emperors] Heal Brother"] = K.Merge(
    Called{ events = { WA_TWINS_HEAL_BROTHER_CAST = true }, icon = 136042, sample = { 2, "Emperor Vek'lor" } }, Talk("Heal"))
B["T:[AQ40][Ouro] Submerge / Emerge"] = K.Merge(
    Called{ events = { WA_OURO_SUBMERGE = "SUBMERGE", WA_OURO_EMERGE = "EMERGE" }, icon = 236197, sample = { 3, "EMERGE" } }, {
        ["conditions.1.changes.1.value"] = Voice("Submerge"),
        ["conditions.2.changes.1.value"] = Voice("Emerge"),
    })
B["T:[AQ40][C'thun] Phase"] = K.Merge(Called{ events = { WA_CTHUN_P2_START = "PHASE 2" }, icon = 134397, sample = { 3, "PHASE 2" } },
    { ["conditions.1.changes.1.value"] = Voice("Phase 2") })
B["T:[AQ40][C'thun] Eye Beam"] = SomeoneElse("WA_CTHUN_EYE_BEAM_TARGET", 136014, 2)
B["T:[AQ40][C'thun] Giant Claw Tentacle"] = K.Merge(GoneOff("CTHUN_GIANT_CLAW_TENTACLE", 3, 135664, 2), Talk("Giant Claw"))
B["T:[AQ40][C'thun] Giant Eye Tentacle"] = K.Merge(GoneOff("CTHUN_GIANT_EYE_TENTACLE", 3, 133884, 2), Talk("Giant Eye"))

-- ============================================================
-- TANK ICONS
-- ============================================================
B["TI:[AQ40][Fankriss] Mortal Wound"] = { ["logic"] = TankOnly, ["text"] = PerStack(10, "-") }
B["TI:[AQ40][Huhuran] Acid Spit"] = { ["logic"] = TankOnly, ["text"] = PerStack(200) }
B["CTI:[AQ40][Fankriss] Mortal Wound"] = { ["logic"] = TankOnly, ["text"] = PerStack(10, "-") }
B["CTI:[AQ40][Huhuran] Acid Spit"] = { ["logic"] = TankOnly, ["text"] = PerStack(200) }

RM.Own.Finish("AQ40", B)
