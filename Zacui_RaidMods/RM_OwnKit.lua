-- RM_OwnKit - the behaviours ZacUI's own boss modules are built from.
-- Part of ZacUI; load order is set by the TOC.
--
-- Every builder takes a small table of facts about one piece (a key, a
-- spell, a timing, an icon) and hands back a slot map: the functions that
-- go in that piece's C places, keyed by their dotted path ("init",
-- "triggers.1.trigger", "actions.finish.custom" ...). A raid file reads
-- like a list of facts:
--
--   B[id] = K.Controller{ key = "LUCIFRON_DOOM", spell = 19702, first = 7, every = 20 }
--   B[id] = K.Merge(K.Flash{ key = "LUCIFRON_CURSE", icon = 136123 }, K.Speak{ say = "Decurse" })
--
-- Shapes that turn up once stay in the raid file. Everything here works
-- the way the engine calls it: init(env), trigger(env, allstates, event,
-- ...) for state triggers, trigger(env, event, ...) for plain ones,
-- actions(env), text(env, ...), logic(env, t), check(env).
--
-- A few things the raids share and other people's clients listen for:
--   WA_NUMEN_TIMER key, seconds, count          a boss ability's countdown
--                                               (seconds 0 = it just went
--                                               off, nil = stop the timer)
--   WA_NUMEN_EMPHASIZED_TIMER key, seconds, ... the last ten seconds of one
--   WA_<KEY>_PREWARN seconds / _PREWARN_CANCEL  a heads-up shortly before
local ADDON_NAME = ...
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
if not (RM and RM.Own) then return end
local O = RM.Own
local K = {}
O.Kit = K

-- ============================================================
-- SMALL PIECES
-- ============================================================

-- One slot map out of several; a later map wins a path both fill.
function K.Merge(...)
    local out = {}
    for i = 1, select("#", ...) do
        local map = select(i, ...)
        if map then
            for path, fn in pairs(map) do out[path] = fn end
        end
    end
    return out
end

-- The creature id inside a GUID, as text ("Creature-0-1-409-1-12118-..."
-- gives "12118").
function K.NpcId(guid)
    return (select(6, strsplit("-", guid)))
end

-- A set from a list: { 1, 2 } -> { [1] = true, [2] = true }.
function K.Set(list)
    local set = {}
    for _, v in ipairs(list or {}) do set[v] = true end
    return set
end

-- Shows a state under key, built from fields; show and changed are set.
function K.Put(allstates, key, fields)
    local st = { show = true, changed = true }
    for k, v in pairs(fields) do st[k] = v end
    allstates[key] = st
    return st
end

-- Fields for a timed state that runs for dur seconds from now.
function K.Timed(dur, fields)
    local t = { progressType = "timed", duration = dur, expirationTime = GetTime() + dur }
    if fields then for k, v in pairs(fields) do t[k] = v end end
    return t
end

-- Hides the state under key if there is one; true when it did.
function K.Drop(allstates, key)
    local st = allstates[key]
    if st then
        st.show = false
        st.changed = true
        return true
    end
end

-- A preview state (what the options window shows): fields as given, plus
-- show. Copied, so a piece's sample table is never shared with the engine.
local function Sample(allstates, fields, env)
    if type(fields) == "function" then fields = fields(env) end
    local st = { show = true }
    for k, v in pairs(fields) do st[k] = v end
    allstates[""] = st
end

-- A function that always answers v (a fixed icon, a status trigger).
function K.Always(v)
    return function() return v end
end

-- A text that shows env[name] (the bars that print a colour code someone
-- else set).
function K.Field(name)
    return function(env) return env[name] end
end

-- "(3)": the count of the state being shown, or nothing.
function K.CountText()
    return function(env)
        if env.state.count then
            return "(" .. env.state.count .. ")"
        end
    end
end

-- A check that is the value of one shared global (role flags such as
-- FJI_TANK); with several, the first that is set.
function K.Flag(...)
    local names = { ... }
    return function()
        local v
        for i = 1, #names do
            v = _G[names[i]]
            if v then return v end
        end
        return v
    end
end

-- A check: the raid leader, or a player of one of these classes.
function K.LeaderOrClass(...)
    local classes = K.Set({ ... })
    return function()
        local leader = UnitIsGroupLeader("player")
        local class = UnitClassBase("player")
        return leader or classes[class] == true
    end
end

-- A check: a player of one of these classes (and, when lead is set, the
-- raid leader too).
function K.IsClass(classes, lead)
    local set = K.Set(classes)
    return function()
        if lead and UnitIsGroupLeader("player") then return true end
        return set[UnitClassBase("player")] == true
    end
end

-- Logic: a piece option must be on, and the first trigger active.
function K.OptionAnd(option)
    return function(env, t)
        return env.config.option[option] and t[1]
    end
end

-- Start action: tint the bar with the colour the player picked, when
-- they asked for one.
function K.ColorOverride()
    return function(env)
        local opt = env.config.option
        if not opt.colorOverride then return end
        local c = opt.color
        if c then env.region:Color(c[1], c[2], c[3], c[4]) end
    end
end

-- ============================================================
-- CONTROLLERS - one boss ability's countdown on the bus
-- ============================================================
-- An invisible piece per ability. On the pull it starts the countdown
-- (WA_NUMEN_TIMER key, first, 1); each time the ability lands it says so
-- (key, 0, count), counts up and starts the next one (key, every, count).
-- Timer bars, flashes and speech elsewhere listen for those.
--   key      the ability's bus key
--   spell    spell id that marks a cast (spells = { ... } for several)
--   sub      the combat log event for it (default SPELL_CAST_SUCCESS)
--   first    seconds to the first one after the pull (nil: no countdown)
--   every    seconds between them (nil: only the "went off" call, though
--            the count still goes up)
--   count    the count to start from (default 1; false: no count)
--   show     whether the pull shows the piece's state (default true)
--   pull     false: the pull is not this piece's business
--   pullOn   events that count as a pull (default ENCOUNTER_START)
--   stopOn   events that stop the countdown (a phase it skips)
--   recount  the encounter start puts the count back to the start
--   hideOn   events that hide the piece's state (and carry on)
--   prewarn  seconds before each one to fire WA_<KEY>_PREWARN
--   prewarnCount  the PREWARN event carries the coming count too
--   guid     the call carries the target's GUID as a fourth value
--   tell     { [spellId] = "WA_EVENT" }: a bus event to fire for that spell
--   onCast   fn(env, allstates, sourceGUID, destGUID, spellId): extra work
--            when it lands, before the calls go out
--   finish   false: the finish action only stops the countdown;
--            "prewarn": it also cancels a pending heads-up
--   ready    a bus event to fire when a countdown runs out (the moment
--            the ability is due again)
function K.Controller(s)
    local key = s.key
    local sub = s.sub or "SPELL_CAST_SUCCESS"
    local start = s.count
    if start == nil then start = 1 elseif start == false then start = nil end
    local spells = s.spells and K.Set(s.spells)
    local pullOn = K.Set(s.pullOn or { "ENCOUNTER_START" })
    if s.pull == false then pullOn = {} end
    local stopOn = K.Set(s.stopOn)
    local hideOn = K.Set(s.hideOn)
    local prewarnEvent = "WA_" .. key .. "_PREWARN"

    local function Countdown(secs, count, guid)
        if s.guid then
            RM.Fire("WA_NUMEN_TIMER", key, secs, count, guid)
        else
            RM.Fire("WA_NUMEN_TIMER", key, secs, count)
        end
    end

    local function Prewarn(env, secs)
        if env.prewarnTimer then env.prewarnTimer:Cancel() end
        local lead, count = s.prewarn, env.count
        env.prewarnTimer = C_Timer.NewTimer(secs - lead, function()
            if s.prewarnCount then
                RM.Fire(prewarnEvent, lead, count)
            else
                RM.Fire(prewarnEvent, lead)
            end
            env.prewarnTimer = nil
        end)
    end

    local function StopPrewarn(env)
        RM.Fire(prewarnEvent .. "_CANCEL")
        if env.prewarnTimer then
            env.prewarnTimer:Cancel()
            env.prewarnTimer = nil
        end
    end

    -- the "due again" event: one pending at a time; secs nil only cancels
    local function Ready(env, secs)
        if not s.ready then return end
        if env.readyTimer then
            env.readyTimer:Cancel()
            env.readyTimer = nil
        end
        if not secs then return end
        env.readyTimer = C_Timer.NewTimer(secs, function()
            env.readyTimer = nil
            RM.Fire(s.ready)
        end)
    end

    local function IsOurs(spellId)
        if spells then return spells[spellId] == true end
        return spellId == s.spell
    end

    local map = {}
    map["init"] = function(env)
        env.key = key
        env.count = start
    end
    map["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId)
        if hideOn[event] then K.Drop(allstates, "") end
        if pullOn[event] then
            if s.recount and event == "ENCOUNTER_START" then env.count = start end
            if s.show ~= false then K.Put(allstates, "", {}) end
            if s.first then
                if s.prewarn then Prewarn(env, s.first) end
                Ready(env, s.first)
                Countdown(s.first, env.count)
            end
            return true
        end
        if stopOn[event] then
            Ready(env, nil)
            Countdown(nil)
            if s.prewarn then StopPrewarn(env) end
            return true
        end
        if not IsOurs(spellId) then return false end
        if subEvent ~= sub then return end
        local say = s.tell and s.tell[spellId]
        if say then RM.Fire(say) end
        if s.onCast then s.onCast(env, allstates, sourceGUID, destGUID, spellId) end
        Countdown(0, env.count, destGUID)
        if env.count then env.count = env.count + 1 end
        Ready(env, s.every)
        if s.every then
            if s.prewarn then Prewarn(env, s.every) end
            Countdown(s.every, env.count)
        end
        return true
    end
    map["actions.finish.custom"] = function(env)
        if s.finish ~= false then env.count = start end
        Ready(env, nil)
        Countdown(nil)
        if s.finish == "prewarn" then StopPrewarn(env) end
    end
    return map
end

-- ============================================================
-- TIMER BARS - the boss-timer list
-- ============================================================
-- One bar per ability key in bars, fed by WA_NUMEN_TIMER. With
-- "emphasize" on (all of them, or this key), the last ten seconds move to
-- the emphasized list: the bar hands over by firing
-- WA_NUMEN_EMPHASIZED_TIMER and steps aside.
--   bars       { KEY = { name, icon, color = {r, g, b, a} (0-255),
--              role = "TANK"/"HEALER", useText, autoHide } }
--   sample     how many preview bars the options window shows
--   allow      fn(env, key): false keeps a key off the list for now
--   hideAtZero a "went off" (0) also takes the bar down
local ROLE_ICON = {
    TANK = "|A:groupfinder-icon-role-large-tank:16:16|a ",
    HEALER = "|A:groupfinder-icon-role-large-heal:16:16|a ",
}
local EMPHASIS = 10

-- the state a timer bar shows
local function BarState(allstates, key, secs, count, name, icon, color, autoHide, text)
    local r, g, b, a = unpack(color)
    K.Put(allstates, key, {
        duration = secs,
        expirationTime = GetTime() + secs,
        progressType = "timed",
        count = count,
        color = { r / 255, g / 255, b / 255, a },
        icon = icon,
        name = name,
        autoHide = autoHide,
        text = text or "",
    })
end

function K.TimerBars(s)
    local bars = s.bars
    local map = {}
    map["init"] = function(env)
        env.region.bar:SetVertexColor(1, 1, 1, 1)
        env.spellKeys = bars
        env.timers = {}
    end
    map["text"] = K.CountText()
    map["actions.start.custom"] = K.ColorOverride()
    map["triggers.1.trigger"] = function(env, allstates, event, key, secs, count, text)
        local timers = env.timers
        if event == "OPTIONS" then
            for i = 1, s.sample or 6 do
                allstates[i] = K.Timed(6, { show = true, name = "Deep Breath " .. i })
            end
        end
        if event == "STATUS" or event == "OPTIONS" then
            for _, t in pairs(timers) do
                if t then t:Cancel() end
            end
        end
        local bar = bars[key]
        if event == "WA_NUMEN_TIMER" and bar then
            if s.allow and not s.allow(env, key) then return false end
            if secs == nil or (s.hideAtZero and secs == 0) then
                if timers[key] then timers[key]:Cancel() timers[key] = nil end
                K.Drop(allstates, key)
                return true
            end
            local name = (ROLE_ICON[bar.role] or "") .. bar.name
            local autoHide = bar.autoHide or false
            local extra = bar.useText and (text or "") or nil
            local opt = env.config.option
            local group = opt.emphasizeGroup
            if not (opt.emphasizedTimers or (group and group[key])) then
                BarState(allstates, key, secs, count, name, bar.icon, bar.color, autoHide, extra)
                return true
            end
            if secs <= EMPHASIS then
                RM.Fire("WA_NUMEN_EMPHASIZED_TIMER", key, secs, count, name, bar.icon, bar.color, autoHide, extra)
                return
            end
            BarState(allstates, key, secs, count, name, bar.icon, bar.color, autoHide, extra)
            if timers[key] then timers[key]:Cancel() end
            timers[key] = C_Timer.NewTimer(secs - EMPHASIS, function()
                RM.Fire("WA_NUMEN_EMPHASIZED_TIMER", key, EMPHASIS, count, name, bar.icon, bar.color, autoHide, extra or "")
            end)
            return true
        elseif event == "WA_NUMEN_EMPHASIZED_TIMER" and bar then
            K.Drop(allstates, key)
            return true
        end
    end
    return map
end

-- The emphasized list: takes the bars the timer list hands over and
-- drops them when their countdown is stopped or goes off.
--   sample     how many preview bars (default 3)
--   sampleKey  the preview bars' keys: this text plus the number (nil:
--              the number alone)
function K.Emphasized(s)
    s = s or {}
    local map = {}
    map["init"] = function() end
    map["text"] = K.CountText()
    map["actions.start.custom"] = K.ColorOverride()
    map["triggers.1.trigger"] = function(env, allstates, event, key, secs, count, name, icon, color, autoHide)
        if event == "OPTIONS" then
            for i = 1, s.sample or 3 do
                allstates[s.sampleKey and (s.sampleKey .. i) or i] = K.Timed(6, { show = true, name = "Laser Attack " .. i, index = i })
            end
        end
        if event == "WA_NUMEN_EMPHASIZED_TIMER" and secs ~= nil and secs ~= 0 then
            BarState(allstates, key, secs, count, name, icon, color, autoHide, "")
            return true
        end
        if secs == 0 or (event == "WA_NUMEN_TIMER" and secs == nil) then
            K.Drop(allstates, key)
            return true
        end
    end
    return map
end

-- The berserk bar: a countdown for the keys in keys; when it ends it
-- fires WA_FOJJI_BERSERK, and its "30 seconds left" condition fires
-- WA_FOJJI_BERSERK_30 (the warnings listen for both).
function K.Berserk(s)
    local keys = s.keys or {}
    local map = {}
    map["init"] = function() end
    map["triggers.1.trigger"] = function(env, allstates, event, key, secs)
        if keys[key] and secs ~= nil and secs > 0 then
            K.Put(allstates, "", K.Timed(secs, { autoHide = true }))
            return true
        end
    end
    map["actions.finish.custom"] = function() RM.Fire("WA_FOJJI_BERSERK") end
    map["conditions.1.changes.1.value"] = function() RM.Fire("WA_FOJJI_BERSERK_30") end
    return map
end

-- ============================================================
-- FLASHES - something on screen for a moment
-- ============================================================
-- Shows a short timed state when a countdown reaches 0 (key) or when a
-- bus event arrives (event).
--   key / event  what sets it off (key: WA_NUMEN_TIMER key at 0)
--   dur          how long it stays (default 3)
--   icon         its icon (nil: none)
--   guid         carry the countdown's GUID (the 7th value) as state.guid
--   sample       the options-window preview: a table of fields, or
--                fn(env) returning one
--   sampleShows  the preview counts as a change (the trigger answers true)
--   also         fn(env) run just before it shows (a follow-up event)
function K.Flash(s)
    local dur = s.dur or 3
    local map = {}
    map["triggers.1.trigger"] = function(env, allstates, event, key, secs, count, guid)
        if event == "OPTIONS" and s.sample then
            Sample(allstates, s.sample, env)
            if s.sampleShows then return true end
        end
        local fire
        if s.event then
            fire = event == s.event
        else
            fire = event == "WA_NUMEN_TIMER" and key == s.key and secs == 0
        end
        if not fire then return end
        if s.also then s.also(env) end
        local st = K.Put(allstates, "", K.Timed(dur, { icon = s.icon, autoHide = true }))
        if s.guid then st.guid = guid end
        return true
    end
    return map
end

-- The preview most flashes show: their icon.
function K.IconSample(icon)
    return { icon = icon }
end

-- A heads-up bar: shows for dur on its PREWARN event, goes when one of
-- the cancel events comes or the countdown for key goes off or stops.
--   key, on (the PREWARN event), cancel = { events }, dur, icon,
--   sampleDur (preview length)
function K.Prewarn(s)
    local cancel = K.Set(s.cancel)
    local map = {}
    map["triggers.1.trigger"] = function(env, allstates, event, key, secs)
        if event == "OPTIONS" then
            K.Put(allstates, "", K.Timed(s.sampleDur, { icon = s.icon }))
            return true
        end
        if event == s.on then
            K.Put(allstates, "", K.Timed(s.dur, { icon = s.icon }))
            return true
        end
        if cancel[event] or (event == "WA_NUMEN_TIMER" and key == s.key and (secs == 0 or secs == nil)) then
            return K.Drop(allstates, "")
        end
    end
    return map
end

-- A bar for a spell cast seen through UNIT_SPELLCAST_START (who is
-- dousing a rune, who is opening a chest), named after the caster.
--   spell, dur
function K.CastBar(s)
    local map = {}
    map["triggers.1.trigger"] = function(env, allstates, event, unit, castId, spellId)
        if event == "OPTIONS" then
            K.Put(allstates, "", K.Timed(s.dur, { autoHide = true, name = "player" }))
            return true
        end
        if event == "UNIT_SPELLCAST_START" then
            if spellId ~= s.spell then return false end
            K.Put(allstates, "", K.Timed(s.dur, { autoHide = true, name = unit }))
            return true
        end
    end
    return map
end

-- The "disable raid emotes" piece every raid has: with its option on,
-- the big boss-emote text in the middle of the screen stops listening.
-- flat: the option sits straight on config rather than config.option.
local EMOTE_EVENTS = { "RAID_BOSS_EMOTE", "RAID_BOSS_WHISPER", "CLEAR_BOSS_EMOTES" }
function K.MuteBossEmotes(s)
    s = s or {}
    return {
        ["init"] = function() end,
        ["triggers.1.trigger"] = function(env)
            local cfg = s.flat and env.config or env.config.option
            if not cfg.disableEmoteEnable then return end
            for _, ev in ipairs(EMOTE_EVENTS) do
                if RaidBossEmoteFrame:IsEventRegistered(ev) then
                    RaidBossEmoteFrame:UnregisterEvent(ev)
                end
            end
            return true
        end,
    }
end

-- ============================================================
-- SPEECH AND SOUND
-- ============================================================

-- Start action: say something (through the engine's speech, at the
-- packs' usual 75 volume, 1.2 rate). who = fn() limits it to some players.
function K.Speak(s)
    return {
        ["actions.start.custom"] = function()
            if s.who and not s.who() then return end
            RM.Speak(s.say, s.volume or 75, s.rate or 1.2)
        end,
    }
end

-- ============================================================
-- NAMEPLATES
-- ============================================================
-- Nameplate pieces keep two tables on env: seen[guid] (this mob is being
-- followed) and ends[guid] (when its timer runs out), so a plate that
-- scrolls off screen and back picks its timer up again.

-- The nameplate unit currently showing guid, if any.
function K.PlateFor(guid)
    for _, plate in pairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.UnitFrame.displayedUnit
        if UnitGUID(unit) == guid then return unit end
    end
end

-- Starts following guid for secs: shows it on its plate when the plate is
-- up. Answers true when it showed. fields: extra state fields.
function K.PlateStart(env, allstates, guid, secs, fields)
    env.seen[guid] = true
    env.ends[guid] = secs + GetTime()
    local unit = K.PlateFor(guid)
    if not unit then return false end
    local st = { progressType = "timed", duration = secs, expirationTime = env.ends[guid], unit = unit }
    if fields then for k, v in pairs(fields) do st[k] = v end end
    K.Put(allstates, guid, st)
    return true
end

-- Plates coming and going: hides a followed mob's state with its plate
-- and brings it back, with the time left, when the plate returns.
-- fields: extra state fields (or fn() returning them).
function K.PlateFollow(env, allstates, event, unit, fields)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        local guid = UnitGUID(unit)
        if allstates[guid] then
            K.Drop(allstates, guid)
            return true
        end
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        local guid = UnitGUID(unit)
        if env.seen[guid] and env.ends[guid] then
            local left = env.ends[guid] - GetTime()
            if left > 0 then
                local extra = type(fields) == "function" and fields() or fields
                local st = { progressType = "timed", duration = left, expirationTime = env.ends[guid], unit = unit }
                if extra then for k, v in pairs(extra) do st[k] = v end end
                K.Put(allstates, guid, st)
                return true
            end
        end
    end
end

local function PlateInit(env)
    env.seen = {}
    env.ends = {}
end

-- A cooldown on a mob's nameplate after it casts (or summons).
--   npcs = { "id", ... }, spell, sub (default SPELL_CAST_SUCCESS),
--   cd (seconds), keep (true: the icon stays at 0 rather than hiding)
function K.PlateCooldown(s)
    local npcs = K.Set(s.npcs)
    local sub = s.sub or "SPELL_CAST_SUCCESS"
    local fields = (not s.keep) and { autoHide = true } or nil
    local map = {}
    map["init"] = PlateInit
    map["triggers.1.trigger"] = function(env, allstates, event, unit, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId)
        if subEvent == sub and spellId == s.spell and npcs[K.NpcId(sourceGUID)] then
            if K.PlateStart(env, allstates, sourceGUID, s.cd, fields) then return true end
        end
        return K.PlateFollow(env, allstates, event, unit, fields)
    end
    return map
end

-- A buff timer on a mob's nameplate while one of spells is on it.
--   npcs = { "id", ... }, spells = { id, ... }, dur, spellIcon (true: the
--   state carries the buff's icon)
-- (a plate coming back carries no spell, so it never gets the icon)
local PLATE_BACK = { autoHide = true }
function K.PlateBuff(s)
    local npcs = K.Set(s.npcs)
    local spells = K.Set(s.spells)
    local map = {}
    map["init"] = PlateInit
    map["triggers.1.trigger"] = function(env, allstates, event, unit, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId)
        if subEvent == "SPELL_AURA_APPLIED" and spells[spellId] then
            if npcs[K.NpcId(destGUID)] then
                env.seen[destGUID] = true
                env.ends[destGUID] = s.dur + GetTime()
                local plate = K.PlateFor(destGUID)
                if plate then
                    local st = { autoHide = true }
                    if s.spellIcon then st.icon = GetSpellTexture(spellId) end
                    st.progressType, st.duration, st.unit = "timed", s.dur, plate
                    st.expirationTime = env.ends[destGUID]
                    K.Put(allstates, destGUID, st)
                    return true
                end
            end
        elseif subEvent == "SPELL_AURA_REMOVED" and spells[spellId] then
            if env.seen[destGUID] then
                env.seen[destGUID] = false
                if allstates[destGUID] then
                    K.Drop(allstates, destGUID)
                    env.ends[destGUID] = nil
                    return true
                end
            end
        end
        return K.PlateFollow(env, allstates, event, unit, PLATE_BACK)
    end
    return map
end

-- ============================================================
-- WHO GOT IT
-- ============================================================

-- A list of the players a spell landed on, each shown for dur; the first
-- of a wave (no closer than gap seconds to the last) fires the title
-- event so the heading above the list shows too.
--   spell, title (bus event), dur (default 2.5), gap (default 8)
function K.PlayerList(s)
    local dur, gap = s.dur or 2.5, s.gap or 8
    local map = {}
    map["init"] = function(env) env.throttle = 0 end
    map["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, _, _, _, destGUID, destName, _, _, spellId)
        if event == "OPTIONS" then
            for i = 1, 5 do
                K.Put(allstates, i, { name = UnitName("player"), index = i })
            end
            return true
        end
        if spellId ~= s.spell then return false end
        if GetTime() - (env.throttle or 0) >= gap then
            RM.Fire(s.title)
            env.throttle = GetTime()
        end
        if allstates[destName] then return false end
        K.Put(allstates, destName, { duration = dur, progressType = "timed", name = destName, autoHide = true })
        -- everyone on the list restarts together
        for _, st in pairs(allstates) do
            st.changed = true
            st.expirationTime = GetTime() + dur
        end
        return true
    end
    return map
end

-- A short glow on the raid frame of whoever a spell ticks on.
--   spells = { id, ... }, dur (default 1)
function K.HitGlow(s)
    local spells = K.Set(s.spells)
    local dur = s.dur or 1
    local map = {}
    map["init"] = function() end
    map["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, _, _, _, _, destName, _, _, spellId)
        if spellId and spells[spellId] and destName then
            K.Put(allstates, destName, K.Timed(dur, { autoHide = true, unit = Ambiguate(destName, "short") }))
            return true
        end
    end
    return map
end

-- ============================================================
-- RAID MARKS (raid leader pieces)
-- ============================================================
-- The pieces' options hold marks under keys with "Mark" in them
-- (firstMark = 8, ...; 9 means "none"). env.marks[mark] is true while that
-- mark is free to hand out.

-- Init: the pool of marks from the options. skipNone leaves out 9.
function K.MarkPool(s)
    s = s or {}
    return function(env)
        env.marks = {}
        env.originalMarks = {}
        local opt = env.config.group.option
        if not opt.enable then return end
        for k, mark in pairs(opt) do
            if k:find("Mark") and mark and not (s.skipNone and mark == 9) then
                env.marks[mark] = true
            end
        end
    end
end

-- Start action: mark the unit the piece is showing with the first free
-- mark in the options' order, remembering any mark it had. say: the chat
-- prefix to announce it with (nil: quiet).
function K.MarkOnShow(s)
    s = s or {}
    return function(env)
        local opt = env.config.group.option
        if not (opt.enable and env.state and env.state.unit) then return end
        local unit = env.state.unit
        local had = GetRaidTargetIndex(unit)
        if had and had > 0 then env.originalMarks[unit] = had end
        local order = {}
        for k, mark in pairs(opt) do
            if k:find("Mark") and mark then order[#order + 1] = mark end
        end
        for _, mark in ipairs(order) do
            if env.marks[mark] then
                SetRaidTarget(unit, mark)
                if s.say then
                    print(s.say .. "AutoMarked" .. UnitName(unit) .. " with |TInterface/TargetingFrame/UI-RaidTargetingIcon_" .. mark .. ":14:14|t")
                end
                env.marks[mark] = false
                return
            end
        end
    end
end

-- Finish action: take the mark back off and give back the one it had.
function K.MarkClear()
    return function(env)
        if not (env.state and env.state.unit) then return end
        local unit = env.state.unit
        local mark = GetRaidTargetIndex(unit)
        if mark then
            SetRaidTarget(unit, 0)
            env.marks[mark] = true
        end
        local had = env.originalMarks[unit]
        if had then
            SetRaidTarget(unit, had)
            env.originalMarks[unit] = nil
        end
    end
end

-- Mouse-over marking: hold Shift over an unmarked add to give it the
-- next free mark.
--   npcs   { ["npcId"] = "option" }: which adds, and the option that
--          must be on for each
--   what   what the chat line calls them ("Firesworn")
--   say    the chat prefix
--   other  what the trigger answers for a mob that is not one of them
function K.AutoMark(s)
    local function Next(env, unit)
        local mark = GetRaidTargetIndex(unit)
        if mark and env.marks[mark] ~= nil then return end
        for m, free in pairs(env.marks) do
            if free then
                SetRaidTarget(unit, m)
                env.marks[m] = false
                print(s.say .. "AutoMarked " .. s.what .. " with |TInterface/TargetingFrame/UI-RaidTargetingIcon_" .. m .. ":14:14|t")
                return
            end
        end
    end
    local map = {}
    map["init"] = K.MarkPool{ skipNone = true }
    map["triggers.1.trigger"] = function(env, event)
        if event ~= "UPDATE_MOUSEOVER_UNIT" then return end
        local unit = "mouseover"
        local opt = env.config.group.option
        if not opt.enable then return false end
        if not UnitExists(unit) then return false end
        if UnitIsDead(unit) then return false end
        local need = s.npcs[K.NpcId(UnitGUID(unit))]
        if not (need and opt[need]) then return s.other end
        if GetRaidTargetIndex(unit) then return false end
        if not IsShiftKeyDown() then
            -- remind at most every three minutes
            if not env.lastReminder or env.lastReminder < GetTime() - 180 then
                print(s.say .. "Hold LSHIFT to AutoMark")
                env.lastReminder = GetTime()
            end
            return false
        end
        Next(env, unit)
        return true
    end
    return map
end
