-- NX - ZacUI's own Naxxramas boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Settings in Own\NX_Data.lua.
--
-- Every boss ability has an invisible controller piece that puts its
-- countdown on the bus (WA_NUMEN_TIMER key, seconds, count); the timer
-- bars, flashes, circles and speech elsewhere listen for it. Naxxramas
-- controllers all follow one pattern (written once below as Ability);
-- the bosses with phases - Noth's balcony, Heigan's dance, Sapphiron's
-- air phase, Thaddius, Kel'Thuzad - add their own steps to it. The raid
-- leader tools (Loatheb spore teams, Corrupted Mind healers, KT kick
-- teams, auto-marking) and the overview lists are written out per boss.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
if not (RM and RM.Own and RM.Own.on) then return end
local K = RM.Own.Kit
local WA = RM.WA

local B = {}

-- ============================================================
-- SHARED BITS
-- ============================================================
-- a boss's picture: the game's icon for its signature spell
local BOSS_ICON = {
    GOTHIK = "Interface\\Icons\\Spell_Shadow_RaiseDead",
    PATCHWERK = "Interface\\Icons\\Ability_Warrior_DecisiveStrike",
    KELTHUZAD = "Interface\\Icons\\Spell_Frost_FrostNova",
    SAPPHIRON = "Interface\\Icons\\Spell_Frost_FrostShock",
    THADDIUS = "Interface\\Icons\\Spell_Nature_Lightning",
}
-- the chat prefix the raid's leader tools print with
local SAY = "|cff0070ddRaid Mods|r |cffff8000Naxx|r: "

-- the two ways a fight ends: the game's own event, and the one the
-- engine sends when a wipe is called early
local FIGHT_OVER = { ENCOUNTER_END = true, WA_FJI_ENCOUNTER_END = true }

local function Npc(guid) return (select(6, strsplit("-", guid))) end

local function Speak(text) RM.Speak(text, 75, 1.2) end

-- ask the whole raid (other clients too) to run a bus event
local function Sync(event, ...)
    WA_SYNC_RESULT = (_G.SyncEvents or function() end)("RAID", nil, event, ...)
end

-- hide every state in a list piece
local function HideAll(allstates)
    for _, st in pairs(allstates) do
        st.show = false
        st.changed = true
    end
end

-- ============================================================
-- ABILITY CONTROLLERS
-- ============================================================
-- One piece per boss ability. The pull (pullOn, ENCOUNTER_START unless
-- told otherwise) starts the count at 1, shows the piece and starts the
-- first countdown; each time the ability lands the countdown says "went
-- off" (0), the count goes up and the next countdown starts. warn: the
-- seconds before each countdown ends to fire WA_<KEY>_PREWARN (seconds,
-- count) - nil for none. The end of the fight hides the piece.
--   key, first, every, warn
--   pullOn   event that starts it (false: nothing does)
--   quiet    the pull does not show the piece
--   spell / spells, sub (default SPELL_CAST_SUCCESS)
--   cast     fn(env, allstates, c) for a landing (default: Cycle);
--            c = { src, dst, dstName, spell, sub, extra }
--   casts    { [subEvent] = fn } in place of cast/sub
--   on       { [event] = fn(env, allstates, ...) }: other bus events; a
--            handler that answers nil lets the event carry on to the
--            spell check (the way the earlier code fell through)
--   onPull   fn(env) run on the pull after the piece shows
--   init     fn(env) extra set-up
--   finish   { tell = false (no stop call), also = fn(env) }
--   noEnd    the end of the fight is not this piece's business (it has no
--            state to hide)
local Ability, Step
do
    local Tell, Warn, Unwarn, Went, Next, Cycle

    function Tell(env, secs, count)
        RM.Fire("WA_NUMEN_TIMER", env.key, secs, count)
    end

    -- the heads-up for a countdown of secs, lead seconds before it ends
    function Warn(env, secs, lead)
        lead = lead or 3
        if env.preWarnTimer then
            env.preWarnTimer:Cancel()
            env.preWarnTimer = nil
        end
        local count = env.count
        env.preWarnTimer = C_Timer.NewTimer(secs - lead, function()
            RM.Fire("WA_" .. env.key .. "_PREWARN", lead, count)
            env.preWarnTimer = nil
        end)
    end

    function Unwarn(env)
        RM.Fire("WA_" .. env.key .. "_PREWARN_CANCEL")
        if env.preWarnTimer then
            env.preWarnTimer:Cancel()
            env.preWarnTimer = nil
        end
    end

    -- it went off: say so and count it
    function Went(env)
        Tell(env, 0, env.count)
        env.count = env.count + 1
    end

    -- the next countdown, with its heads-up when the piece has one
    function Next(env, secs, lead)
        if lead then Warn(env, secs, lead) end
        Tell(env, secs, env.count)
    end

    -- the usual landing: went off, next one in every
    function Cycle(env, s)
        Went(env)
        Next(env, s.every, s.warn)
        return true
    end

    local function Show(allstates) K.Put(allstates, "", {}) end

    function Ability(s)
        local spells = s.spells and K.Set(s.spells)
        local sub = s.sub or "SPELL_CAST_SUCCESS"
        local pullOn = s.pullOn
        if pullOn == nil then pullOn = "ENCOUNTER_START" end
        local fin = s.finish or {}
        local function Ours(spellId)
            if spells then return spells[spellId] == true end
            return spellId == s.spell
        end
        local map = {}
        map["init"] = function(env)
            env.key = s.key
            env.count = 1
            if s.init then s.init(env) end
        end
        map["triggers.1.trigger"] = function(env, allstates, event, ...)
            if FIGHT_OVER[event] then
                if s.noEnd then return end
                K.Drop(allstates, "")
                return true
            end
            if event == pullOn then
                env.count = 1
                if not s.quiet then Show(allstates) end
                if s.onPull then s.onPull(env, allstates) end
                if s.first then Next(env, s.first, s.warn) end
                return true
            end
            local on = s.on and s.on[event]
            if on then
                local r = on(env, allstates, ...)
                if r ~= nil then return r end
            end
            if not (s.spell or spells) then return end
            local _, subEvent, _, src, _, _, _, dst, dstName, _, _, spellId, _, _, extra = ...
            if not Ours(spellId) then return false end
            local c = { src = src, dst = dst, dstName = dstName, spell = spellId, sub = subEvent, extra = extra }
            if s.casts then
                local fn = s.casts[subEvent]
                if fn then return fn(env, allstates, c) end
                return
            end
            if subEvent ~= sub then return end
            if s.cast then return s.cast(env, allstates, c) end
            return Cycle(env, s)
        end
        map["actions.finish.custom"] = function(env)
            env.count = 1
            if fin.tell ~= false then Tell(env, nil) end
            if s.warn then Unwarn(env) end
            if fin.also then fin.also(env) end
        end
        return map
    end

    -- the steps, for the pieces that add their own
    Step = { Tell = Tell, Warn = Warn, Unwarn = Unwarn, Went = Went, Next = Next, Cycle = Cycle, Show = Show }
end
local A, T = Ability, Step

-- a timer that fires a bus event later; a new one does not stop an older
-- one still waiting (only the newest is kept to be cancelled)
local function Later(env, field, secs, event)
    env[field] = C_Timer.NewTimer(secs, function() RM.Fire(event) end)
end
local function CancelAll(env, ...)
    for i = 1, select("#", ...) do
        local t = env[select(i, ...)]
        if t then t:Cancel() end
    end
end

-- ---------------- Anub'Rekhan ----------------
-- the swarm's countdown stops while he casts and starts again when it ends
B["CT:[NX][Anub] Locust Swarm"] = A{ key = "ANUB_LOCUST_SWARM", first = 80, every = 69.2, warn = 3, spell = 28785, casts = {
    SPELL_CAST_START = function(env)
        T.Went(env)
        T.Tell(env, nil)
        return true
    end,
    SPELL_AURA_REMOVED = function(env)
        T.Next(env, 69.2, 3)
        return true
    end,
} }

-- ---------------- Grand Widow Faerlina ----------------
-- Enrage stops the clock; the next one counts from the first Widow's
-- Embrace on her after it (one per five seconds)
B["CT:[NX][Grand Widow] Enrage"] = A{ key = "WIDOW_ENRAGE", first = 55, every = 56, warn = 3, spells = { 28798, 28732 },
    init = function(env) env.throttle = 0 end,
    onPull = function(env)
        env.enraged = false
        env.throttle = 0
    end,
    casts = { SPELL_AURA_APPLIED = function(env, allstates, c)
        if c.spell == 28798 then
            env.enraged = true
            T.Went(env)
            T.Tell(env, nil)
        elseif Npc(c.dst) == "15953" then
            if GetTime() - (env.throttle or 0) < 5 then return false end
            env.throttle = GetTime()
            RM.Fire("WA_WIDOW_EMBRACE_SILENCED")
            if env.enraged then T.Next(env, 56, 3) end
            env.enraged = false
        end
        return true
    end } }

-- ---------------- Maexxna ----------------
B["CT:[NX][Maexxna] Necrotic Poison"] = A{ key = "MAEXXNA_NECROTIC_POISON", first = 10, every = 11, spell = 28776, sub = "SPELL_AURA_APPLIED",
    cast = function(env, allstates, c)
        RM.Fire("WA_ANUB_NECROTIC_APPLIED", env.count, c.dst, c.dstName)
        return T.Cycle(env, { every = 11 })
    end }
-- Enrage only says it happened
B["CT:[NX][Maexxna] Enrage"] = A{ key = "MAEXXNA_ENRAGE", quiet = true, spell = 28747, sub = "SPELL_AURA_APPLIED",
    cast = function(env)
        T.Tell(env, 0, env.count)
        return true
    end }
-- the spiders come with each Web Spray
B["CT:[NX][Maexxna] Spiders"] = A{ key = "MAEXXNA_SPIDERS", first = 30, every = 30, warn = 3,
    on = { WA_MAEXXNA_WEB_SPRAY = function(env) return T.Cycle(env, { every = 30, warn = 3 }) end } }
B["CT:[NX][Maexxna] Web Spray"] = A{ key = "MAEXXNA_WEB_SPRAY", first = 40.5, every = 40.4, warn = 6, spell = 29484,
    cast = function(env)
        RM.Fire("WA_MAEXXNA_WEB_SPRAY")
        return T.Cycle(env, { every = 40.4, warn = 6 })
    end }
-- every wrapped player is named; the countdown moves once per five seconds
B["CT:[NX][Maexxna] Web Wrap"] = A{ key = "MAEXXNA_WEB_WRAP", first = 20.1, every = 39.6, warn = 3, spell = 28622, sub = "SPELL_AURA_APPLIED",
    init = function(env) env.throttle = 0 end,
    cast = function(env, allstates, c)
        RM.Fire("WA_MAEXXNA_WRAP_TARGET", c.dst)
        if GetTime() - (env.throttle or 0) < 5 then return false end
        env.throttle = GetTime()
        return T.Cycle(env, { every = 39.6, warn = 3 })
    end }

-- ---------------- Noth ----------------
-- Noth goes up to the balcony and comes back on a fixed clock, a little
-- different each trip; this piece runs the clock and fires
-- WA_NOTH_BALCONY / WA_NOTH_BACK (and WA_NOTH_BACK_IN_ROOM with the time
-- he stays up).
do
    local UP = { 75, 97, 126 }      -- time on the balcony, per trip (then 55)
    local DOWN = { 109, 173, 93 }   -- time back in the room (then 35)
    B["CT:[NX][Noth] Teleport"] = A{ key = "NOTH_TELEPORT", first = 90.8, warn = 3,
        init = function(env) env.teleCount = 0 end,
        onPull = function(env)
            env.teleCount = 0
            Later(env, "scheduleBalcony", 90.8, "WA_NOTH_BALCONY")
        end,
        on = {
            WA_NOTH_BALCONY = function(env)
                T.Went(env)
                env.teleCount = env.teleCount + 1
                local up = UP[env.teleCount] or 55
                Later(env, "scheduleBack", up, "WA_NOTH_BACK")
                RM.Fire("WA_NOTH_BACK_IN_ROOM", up)
                return true
            end,
            WA_NOTH_BACK = function(env)
                local down = DOWN[env.teleCount] or 35
                Later(env, "scheduleBalcony", down, "WA_NOTH_BALCONY")
                T.Next(env, down, 3)
                return true
            end,
        },
        finish = { also = function(env) CancelAll(env, "scheduleBalcony", "scheduleBack") end } }
end
-- the time until he comes back down, from the balcony trip
B["CT:[NX][Noth] Teleport Back"] = A{ key = "NOTH_TELEPORT_BACK", pullOn = "WA_NOTH_BALCONY", first = 90.8, warn = 3,
    init = function(env) env.teleCount = 0 end,
    on = { WA_NOTH_BACK_IN_ROOM = function(env, allstates, secs)
        T.Went(env)
        T.Tell(env, secs, env.count)
        return true
    end },
    finish = { also = function(env) CancelAll(env, "scheduleBalcony", "scheduleBack") end } }
-- skeleton waves while he is up: soon after the first two trips start and
-- end; on the floor, every 30 seconds from his yell
B["CT:[NX][Noth] Adds"] = A{ key = "NOTH_ADDS", first = 12,
    init = function(env) env.teleCount = 0 end,
    onPull = function(env) env.teleCount = 0 end,
    on = {
        WA_NOTH_BACK_IN_ROOM = function(env)
            T.Tell(env, nil)
            if env.teleCount == 1 then
                T.Tell(env, 3, env.count)
            elseif env.teleCount == 2 then
                T.Tell(env, 17, env.count)
            end
            return true
        end,
        WA_NOTH_BALCONY = function(env)
            env.teleCount = env.teleCount + 1
            T.Tell(env, nil)
            T.Tell(env, 5, env.count)
            return true
        end,
        CHAT_MSG_MONSTER_YELL = function(env, allstates, msg)
            local line = "Rise, my soldiers! Rise and fight once more!"
            if msg and msg:find(line) or msg == line then
                T.Went(env)
                T.Tell(env, 30, env.count)
                return true
            end
        end,
    } }
B["CT:[NX][Noth] Blink"] = A{ key = "NOTH_BLINK", pullOn = false, spell = 29208,
    cast = function(env)
        T.Went(env)
        return true
    end }
-- the curse waits while he is on the balcony and comes nine seconds after
-- he is back
B["CT:[NX][Noth] Curse of the Plaguebringer"] = A{ key = "NOTH_CURSE", first = 9.5, every = 51, warn = 3, spell = 29213,
    on = {
        WA_NOTH_BACK_IN_ROOM = function(env)
            T.Next(env, 9, 3)
            return true
        end,
        WA_NOTH_BALCONY = function(env)
            T.Tell(env, nil)
            T.Unwarn(env)
            return true
        end,
    } }

-- ---------------- Heigan ----------------
B["CT:[NX][Heigan] Decrepit Fever"] = A{ key = "HEIGAN_DECREPIT_FEVER", first = 15, every = 21, warn = 3, spell = 29998 }
-- the dance itself: shows and counts down 47 seconds from its start
B["CT:[NX][Heigan] Dance"] = A{ key = "HEIGAN_DANCE", pullOn = false,
    on = {
        ENCOUNTER_START = function(env) env.count = 1 end,
        WA_HEIGAN_DANCE = function(env, allstates)
            T.Show(allstates)
            T.Tell(env, 47, env.count)
            env.count = env.count + 1
            return true
        end,
    } }
-- the clock behind it: 90 seconds on the floor, 47 on the platform;
-- fires WA_HEIGAN_DANCE / WA_HEIGAN_DANCE_END
B["CT:[NX][Heigan] Teleport"] = A{ key = "HEIGAN_TELEPORT", first = 90, warn = 3,
    onPull = function(env)
        env.teleCount = 0
        Later(env, "scheduleDance", 90, "WA_HEIGAN_DANCE")
    end,
    on = {
        WA_HEIGAN_DANCE = function(env)
            T.Went(env)
            Later(env, "scheduleDanceEnd", 47, "WA_HEIGAN_DANCE_END")
            return true
        end,
        WA_HEIGAN_DANCE_END = function(env)
            Later(env, "scheduleDance", 90, "WA_HEIGAN_DANCE")
            T.Next(env, 90, 3)
            return true
        end,
    },
    finish = { also = function(env) CancelAll(env, "scheduleDance", "scheduleDanceEnd") end } }

-- ---------------- Loatheb ----------------
-- Inevitable Doom speeds up: 29.1 / 32.4 alternating, then from the
-- seventh 9.7, and 19.4 / 11.3 after that. A Doom seen without the pull
-- (a reload mid-fight) only says it went off: where in the list it is,
-- is not known.
do
    local function Gap(n)
        if n >= 7 then
            if n == 7 then return 9.7 end
            return n % 2 == 0 and 19.4 or 11.3
        end
        return n % 2 == 0 and 32.4 or 29.1
    end
    B["CT:[NX][Loatheb] Doom"] = A{ key = "LOATHEB_DOOM", first = 121.4, warn = 3, spell = 29204,
        onPull = function(env) env.doomCount = 0 end,
        cast = function(env)
            if not env.doomCount then
                T.Went(env)
                return true
            end
            env.doomCount = env.doomCount + 1
            local gap = Gap(env.doomCount)
            T.Went(env)
            T.Next(env, gap, 3)
            return true
        end,
        finish = { also = function(env) env.doomCount = 0 end } }
end
B["CT:[NX][Loatheb] Remove Curse"] = A{ key = "LOATHEB_REMOVE_CURSE", first = 3, every = 30.8, warn = 3, spell = 30281 }
-- a spore spawning, and the Fungal Bloom it gives (the spore teams list
-- starts that player's 90 seconds on WA_SPORE_APPLIED)
B["CT:[NX][Loatheb] Spore"] = A{ key = "LOATHEB_SPORE", first = 11.3, every = 12.9, warn = 3, spells = { 29234, 29232 }, casts = (function()
    local function Bloom(env, allstates, c)
        if c.spell ~= 29232 then return end
        RM.Fire("WA_SPORE_APPLIED", c.dst)
        return true
    end
    return {
        SPELL_CAST_SUCCESS = function(env, allstates, c)
            if c.spell == 29234 then return T.Cycle(env, { every = 12.9, warn = 3 }) end
        end,
        SPELL_AURA_APPLIED = Bloom,
        SPELL_AURA_REFRESH = Bloom,
    }
end)() }

-- ---------------- Razuvious ----------------
B["CT:[NX][Razuvious] Disrupting Shout"] = A{ key = "RAZUVIOUS_DISRUPTING_SHOUT", first = 26.34, every = 25.8, warn = 3, spell = 29107 }

-- ---------------- Gothik ----------------
B["CT:[NX][Gothik] Phase 2"] = A{ key = "GOTHIK_PHASE_TWO", first = 270, warn = 6,
    on = { CHAT_MSG_MONSTER_YELL = function(env, allstates, msg)
        local line = "I have waited long enough"
        if msg:find(line) or msg == line then
            RM.Fire("WA_GOTHIK_P2_START")
            return true
        end
    end } }
-- the waves: each one schedules the next from the list; after the last
-- the countdown stops
do
    local WAVES = { [2] = 20, [3] = 20, [4] = 10, [5] = 10, [6] = 15, [7] = 5, [8] = 20, [9] = 10, [10] = 10,
        [11] = 5, [12] = 15, [13] = 10, [14] = 10, [15] = 10, [16] = 5, [17] = 5, [18] = 20 }
    B["CT:[NX][Gothik] Wave"] = A{ key = "GOTHIK_WAVE", first = 27,
        onPull = function(env) Later(env, "scheduleNext", 27, "WA_GOTHIK_WAVE") end,
        on = { WA_GOTHIK_WAVE = function(env)
            T.Went(env)
            local secs = WAVES[env.count]
            if secs then
                Later(env, "scheduleNext", secs, "WA_GOTHIK_WAVE")
                T.Tell(env, secs, env.count)
            else
                T.Tell(env, nil)
            end
            return true
        end },
        finish = { also = function(env) CancelAll(env, "scheduleNext") end } }
end

-- ---------------- Four Horsemen ----------------
B["CT:[NX][4HM] Holy Wrath"] = A{ key = "4HM_HOLY_WRATH", first = 20.9, every = 11.3, warn = 3, spell = 28883 }
-- any of the four marks; the four land together, so once per ten seconds
B["CT:[NX][4HM] Mark"] = A{ key = "4HM_MARK", first = 20.9, every = 12.9, warn = 3, spells = { 28832, 28833, 28834, 28835 },
    init = function(env) env.throttle = 0 end,
    cast = function(env)
        if GetTime() - (env.throttle or 0) < 10 then return false end
        env.throttle = GetTime()
        return T.Cycle(env, { every = 12.9, warn = 3 })
    end }
B["CT:[NX][4HM] Meteor"] = A{ key = "4HM_METEOR", first = 20.9, every = 12.9, warn = 3, spell = 28884 }
-- Shield Wall going up and down on a horseman, for its nameplate timer
B["CT:[NX][4HM] Shield Wall"] = A{ key = "4HM_SHIELD_WALL", pullOn = false, spell = 29061, casts = {
    SPELL_AURA_APPLIED = function(env, allstates, c)
        RM.Fire("WA_4HM_SHIELD_WALL_APPLIED", c.dst)
        return true
    end,
    SPELL_AURA_REMOVED = function(env, allstates, c)
        RM.Fire("WA_4HM_SHIELD_WALL_REMOVED", c.dst)
        return true
    end,
} }
B["CT:[NX][4HM] Void Zone"] = A{ key = "4HM_VOID_ZONE", first = 14.5, every = 11.6, warn = 3, spell = 28863,
    cast = function(env, allstates, c)
        RM.Fire("4HM_VOID_ZONE_CAST", c.dst, c.dstName)
        return T.Cycle(env, { every = 11.6, warn = 3 })
    end }

-- ---------------- Patchwerk / Grobbulus / Gluth ----------------
B["CT:[NX][Patchwerk] Berserk"] = A{ key = "PATCHWERK_BERSERK", first = 360, warn = 30 }
B["CT:[NX][Grobbulus] Poison Cloud"] = A{ key = "GROBBULUS_POISON_CLOUD", first = 5, every = 15, warn = 3, spell = 28240 }
B["CT:[NX][Grobbulus] Mutating Injection"] = A{ key = "GROBBULUS_MUTATING_INJECTION", first = 12, every = 10, warn = 3, spell = 28169, sub = "SPELL_AURA_APPLIED",
    cast = function(env, allstates, c)
        RM.Fire("WA_GROBBULUS_MUTATING_INJECTION_APPLIED", c.dst, c.dstName)
        return T.Cycle(env, { every = 10, warn = 3 })
    end }
B["CT:[NX][Grobbulus] Slime Spray"] = A{ key = "GROBBULUS_SLIME_SPRAY", first = 26, every = 28, warn = 3, spell = 28157 }
B["CT:[NX][Gluth] Terrifying Roar"] = A{ key = "GLUTH_TERRIFYING_ROAR", first = 19.4, every = 19.4, warn = 3, spell = 29685 }
B["CT:[NX][Gluth] Mortal Wound"] = A{ key = "GLUTH_MORTAL_WOUND", first = 11, every = 10, warn = 3, spell = 25646 }
B["CT:[NX][Gluth] Enrage"] = A{ key = "GLUTH_FRENZY", first = 9, every = 8.4, warn = 3, spell = 28371 }

-- ---------------- Thaddius ----------------
-- Phase two starts when both Tesla coils have overloaded (once a pull)
B["CT:[NX][Thaddius] Phase Controller"] = {
    ["init"] = function(env) env.downCount = 0 end,
    ["triggers.1.trigger"] = function(env, allstates, event, msg)
        if FIGHT_OVER[event] then
            K.Drop(allstates, "")
            return true
        end
        if event == "ENCOUNTER_START" then
            env.downCount = 0
            return true
        end
        if event == "CHAT_MSG_MONSTER_EMOTE" and (msg == "%s overloads!" or msg == "Tesla Coil overloads!") then
            env.downCount = env.downCount + 1
            if env.downCount == 2 then RM.Fire("WA_THADDIUS_P2_START") end
        end
    end,
    ["actions.finish.custom"] = function(env) env.downCount = 0 end,
}
B["CT:[NX][Thaddius] Berserk"] = A{ key = "THADDIUS_BERSERK", pullOn = "WA_THADDIUS_P2_START", first = 300, warn = 30 }
-- Magnetic Pull is a phase one ability: phase two stops it
B["CT:[NX][Thaddius] Magnetic Pull"] = A{ key = "THADDIUS_MAGNETIC_PULL", first = 20.6, every = 20.6, warn = 3, spell = 28338,
    init = function(env) env.throttle = 0 end,
    on = (function()
        local function Stop(env)
            T.Tell(env, nil)
            T.Unwarn(env)
            return true
        end
        return { WA_THADDIUS_P2_START = Stop, WA_ENCOUNTER_END = Stop }
    end)(),
    cast = function(env)
        if GetTime() - (env.throttle or 0) < 10 then return false end
        env.throttle = GetTime()
        return T.Cycle(env, { every = 20.6, warn = 3 })
    end }
-- the first shift has its own event (the side helper starts from it)
B["CT:[NX][Thaddius] Polarity Shift"] = A{ key = "THADDIUS_POLARITY_SHIFT", pullOn = "WA_THADDIUS_P2_START", first = 14, every = 25.9, warn = 3,
    spell = 28089, sub = "SPELL_CAST_START",
    cast = function(env)
        RM.Fire(env.count == 1 and "WA_THADDIUS_FIRST_POLARITY" or "WA_THADDIUS_POLARITY")
        return T.Cycle(env, { every = 25.9, warn = 3 })
    end }

-- ---------------- Sapphiron ----------------
-- There is no event for Sapphiron taking off. While the piece shows it
-- looks once a second (WA_FJI_SAPPH_TARGET_CHECK) at what the raid is
-- targeting: Sapphiron in combat with no target of his own for over half a
-- second means he is up. That fires WA_SAPPHIRON_AIR_PHASE, and
-- WA_SAPPHIRON_GROUND_PHASE 29.5 seconds later.
do
    local SAPPHIRON = "15989"
    local function Look(env)
        local found, target
        local now = GetTime()
        for unit in RM.IterateGroup() do
            local who = unit .. "target"
            local guid = UnitGUID(who)
            if guid and Npc(guid) == SAPPHIRON and UnitAffectingCombat(who) then
                target = UnitName(who .. "target")
                found = true
                break
            end
        end
        if found and not target then
            if not env.noTargetStart then env.noTargetStart = now end
        else
            env.noTargetStart = nil
        end
        if env.noTargetStart and now - env.noTargetStart > 0.5 and not env.airPhase then
            env.airPhase = true
            env.noTargetStart = nil
            RM.Fire("WA_SAPPHIRON_AIR_PHASE")
            env.scheduleLanding = C_Timer.NewTimer(29.5, function() RM.Fire("WA_SAPPHIRON_GROUND_PHASE") end)
        end
    end
    B["CT:[NX][Sapphiron] Air Phase"] = K.Merge(A{ key = "SAPPHIRON_AIR_PHASE", first = 33.5,
        init = function(env)
            env.airPhase = false
            env.noTargetStart = nil
            env.sapphiron = SAPPHIRON
        end,
        onPull = function(env)
            env.airPhase = false
            env.noTargetStart = nil
        end,
        on = {
            WA_FJI_SAPPH_TARGET_CHECK = function(env) Look(env) end,
            WA_SAPPHIRON_AIR_PHASE = function(env)
                T.Went(env)
                T.Tell(env, nil)
                return true
            end,
            WA_SAPPHIRON_GROUND_PHASE = function(env)
                -- he can only go up again 20 seconds after landing
                C_Timer.After(20, function() env.airPhase = false end)
                T.Tell(env, 66, env.count)
                return true
            end,
        } }, {
        ["actions.start.custom"] = function(env)
            if env.ticker then return end
            env.ticker = C_Timer.NewTicker(1, function() RM.Fire("WA_FJI_SAPPH_TARGET_CHECK") end)
        end,
        ["actions.finish.custom"] = function(env)
            env.count = 1
            if env.ticker then
                env.ticker:Cancel()
                env.ticker = nil
            end
            if env.scheduleLanding then
                env.scheduleLanding:Cancel()
                env.scheduleLanding = nil
            end
        end,
    })
end
-- the landing countdown, from take-off
B["CT:[NX][Sapphiron] Ground Phase"] = A{ key = "SAPPHIRON_GROUND_PHASE", quiet = true,
    on = {
        WA_SAPPHIRON_AIR_PHASE = function(env, allstates)
            T.Show(allstates)
            T.Tell(env, 28.5, env.count)
            return true
        end,
        WA_SAPPHIRON_GROUND_PHASE = function(env)
            T.Tell(env, nil)
            env.count = env.count + 1
            return true
        end,
    } }
-- Frost Breath (the bomb) starting to cast
do
    local map = A{ key = "SAPPHIRON_FROST_BOMB", pullOn = false, noEnd = true, spell = 28524, sub = "SPELL_CAST_START",
        on = { ENCOUNTER_START = function(env) env.count = 1 end },
        init = function(env) env.frostBreath = 28524 end,
        cast = function(env)
            RM.Fire("WA_SAPPHIRON_FROST_BOMB")
            T.Went(env)
            return true
        end }
    map["actions.finish.custom"] = nil
    B["CT:[NX][Sapphiron] Frost Bomb"] = map
end
-- Life Drain pauses in the air
B["CT:[NX][Sapphiron] Life Drain"] = A{ key = "SAPPHIRON_LIFE_DRAIN", first = 14, every = 22, warn = 3, spell = 28542,
    on = { WA_SAPPHIRON_AIR_PHASE = function(env)
        T.Tell(env, nil)
        return true
    end } }
-- each Icebolt in the air, numbered (the count starts again each flight)
B["CT:[NX][Sapphiron] Icebolt"] = A{ key = nil, pullOn = false, spell = 28522, sub = "SPELL_AURA_APPLIED",
    on = { WA_SAPPHIRON_AIR_PHASE = function(env) env.count = 1 end },
    cast = function(env, allstates, c)
        RM.Fire("WA_SAPPHIRON_ICEBOLT_TARGET", c.dst, env.count)
        env.count = env.count + 1
        return true
    end,
    finish = { tell = false } }

-- ---------------- Kel'Thuzad ----------------
-- Phase two: his first spell damage, or one of his phase two yells -
-- whichever comes first, once. Once known, a damage line costs one check
-- (the raid hits adds hundreds of times a second).
do
    local YELLS = { "Pray for mercy!", "Scream your dying breath!", "The end is upon you!" }
    B["CT:[NX][Kel'Thuzad] Phase Controller"] = {
        ["init"] = function() end,
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            -- (nothing to hide at the end of the fight)
            if FIGHT_OVER[event] then return end
            if event == "ENCOUNTER_START" then
                env.p2 = false
                return true
            end
            if event == "COMBAT_LOG_EVENT_UNFILTERED" then
                if env.p2 then return false end
                local _, subEvent, _, _, _, _, _, destGUID = ...
                if subEvent == "SPELL_DAMAGE" and destGUID and destGUID:find("-15990-", 1, true) and Npc(destGUID) == "15990" then
                    RM.Fire("WA_KT_P2_START")
                    env.p2 = true
                    return true
                end
            end
            if event == "CHAT_MSG_MONSTER_YELL" and not env.p2 then
                local msg = ...
                for _, line in ipairs(YELLS) do
                    if msg:find(line) or msg == line then
                        RM.Fire("WA_KT_P2_START")
                        env.p2 = true
                        break
                    end
                end
            end
        end,
    }
end
B["CT:[NX][Kel'Thuzad] Phase 2"] = A{ key = "KT_PHASE_TWO", first = 230,
    on = { WA_KT_P2_START = function(env)
        T.Tell(env, 0, env.count)
        return true
    end } }
-- one Chains puts the aura on up to five players: named each, counted once
B["CT:[NX][Kel'Thuzad] Chains of Kel'Thuzad"] = A{ key = "KT_MIND_CONTROL", pullOn = "WA_KT_P2_START", every = 63, warn = 3, spell = 28410,
    sub = "SPELL_AURA_APPLIED",
    cast = function(env, allstates, c)
        RM.Fire("WA_KT_MC_TARGET", c.dst)
        local now = GetTime()
        if env.lastChains and now - env.lastChains < 3 then return false end
        env.lastChains = now
        return T.Cycle(env, { every = 63, warn = 3 })
    end }
B["CT:[NX][Kel'Thuzad] Detonate Mana"] = A{ key = "KT_DETONATE_MANA", pullOn = "WA_KT_P2_START", every = 20, warn = 3, spell = 27819 }
-- Frostbolt casts for the kick rotation (no countdown of its own)
B["CT:[NX][Kel'Thuzad] Frostbolt"] = {
    ["init"] = function(env)
        env.frostbolt = 28478
        env.count = 1
    end,
    ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, _, _, _, _, _, _, _, spellId, _, _, extraSpellId, extraSpellName)
        -- (nothing to hide at the end of the fight)
        if FIGHT_OVER[event] then return end
        if event == "WA_KT_P2_START" then env.count = 1 end
        if subEvent == "SPELL_INTERRUPT" and (extraSpellId == 28478 or extraSpellName == "Frostbolt") then
            RM.Fire("KT_FROSTBOLT_INTERRUPT")
            env.count = env.count + 1
        end
        if spellId ~= 28478 then return false end
        if subEvent == "SPELL_CAST_START" then
            RM.Fire("KT_FROSTBOLT_CAST_START")
            return true
        elseif subEvent == "SPELL_CAST_SUCCESS" then
            RM.Fire("KT_FROSTBOLT_CAST_SUCCESS")
            env.count = env.count + 1
            return true
        end
    end,
    -- (no countdown of its own to stop)
    ["actions.finish.custom"] = function(env) env.count = 1 end,
}
B["CT:[NX][Kel'Thuzad] Frost Blast"] = A{ key = "KT_FROST_BLAST", pullOn = "WA_KT_P2_START", every = 30.5, warn = 3, spell = 27808 }
B["CT:[NX][Kel'Thuzad] Shadow Fissure"] = A{ key = "KT_SHADOW_FISSURE", pullOn = "WA_KT_P2_START", spell = 27810,
    cast = function(env, allstates, c)
        RM.Fire("KT_SHADOW_FISSURE_CAST", c.dst, c.dstName)
        env.count = env.count + 1
        return true
    end }

-- ============================================================
-- SMALL BUILDERS FOR THE DISPLAY PIECES
-- ============================================================
-- speech in the pack's sound-effect voice (its own volume and rate when
-- set)
local function SpeakSfx(text)
    RM.Speak(text, _G.FJITTS_SFX_VOLUME or 75, _G.FJITTS_SFX_RATE or 1.2)
end
local function SayOnShow(text)
    return { ["actions.start.custom"] = function() SpeakSfx(text) end }
end

-- the round "!" icon the warnings carry in their icon slot
local WARN_ICON = K.Always(135789)

-- the options-window preview most pieces use: a timed bar of dur
local function Preview(dur, fields)
    local st = { show = true, changed = true, progressType = "timed", duration = dur, expirationTime = GetTime() + dur, autoHide = true }
    if fields then for k, v in pairs(fields) do st[k] = v end end
    return st
end

-- A piece that shows one timed state when a bus event comes.
--   on       the event; when = fn(...) narrows it by the event's values
--   dur      how long it shows; fields: fixed state fields (icon, name)
--   args     fn(...) -> state fields taken from the event's values
--   keep     no autoHide
--   sample   fn(env) -> the preview state; sampleQuiet: the preview is
--            put up without answering true
local function Pop(s)
    return {
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "OPTIONS" and s.sample then
                allstates[""] = s.sample(env)
                if not s.sampleQuiet then return true end
            end
            if event ~= s.on then return end
            if s.when and not s.when(...) then return end
            local st = { show = true, changed = true, progressType = "timed", duration = s.dur, expirationTime = GetTime() + s.dur }
            if not s.keep then st.autoHide = true end
            if s.fields then for k, v in pairs(s.fields) do st[k] = v end end
            if s.args then for k, v in pairs(s.args(...)) do st[k] = v end end
            allstates[""] = st
            return true
        end,
    }
end

-- when = a countdown for key reaching 0
local function AtZero(key)
    return function(k, secs) return k == key and secs == 0 end
end
-- args = the countdown's count
local function TheCount(_, _, count) return { count = count } end

-- An ability went off: its icon (and count) for three seconds. The
-- preview shows the icon but does not count as a change.
local function WentOff(key, icon, noCount)
    return Pop{ on = "WA_NUMEN_TIMER", when = AtZero(key), dur = 3, fields = { icon = icon }, args = not noCount and TheCount or nil,
        sampleQuiet = true, sample = function()
            if noCount then return { show = true, icon = icon } end
            return { show = true, icon = icon, count = math.random(1, 3) }
        end }
end

-- The same, 3.5 seconds and a full preview (the vertical text column).
local function Burst(key, icon)
    return Pop{ on = "WA_NUMEN_TIMER", when = AtZero(key), dur = 3.5, fields = { icon = icon }, args = TheCount,
        sample = function() return Preview(3.5, { count = math.random(1, 3), icon = icon }) end }
end

-- A heads-up bar on the controller's PREWARN event (seconds, count); it
-- goes when the countdown for key goes off or stops, or on a cancel event.
--   key, on, icon, cancel = { events }, autoHide
local function Heads(s)
    local cancel = K.Set(s.cancel)
    return {
        ["triggers.1.icon"] = WARN_ICON,
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "OPTIONS" then
                allstates[""] = { show = true, changed = true, progressType = "timed", icon = s.icon, count = math.random(1, 3) }
                return true
            end
            if event == s.on then
                local duration, count = ...
                local st = { show = true, changed = true, duration = duration, expirationTime = GetTime() + duration, progressType = "timed", icon = s.icon, count = count }
                if s.autoHide then st.autoHide = true end
                allstates[""] = st
                return true
            elseif event == "WA_NUMEN_TIMER" then
                local key, secs = ...
                if key == s.key and (secs == 0 or secs == nil) then return K.Drop(allstates, "") end
            elseif cancel[event] then
                return K.Drop(allstates, "")
            end
        end,
    }
end

-- a check: the player's class, by its English display name
local function LocalClass(...)
    local names = K.Set({ ... })
    return function() return names[UnitClass("player")] == true end
end
local function LeaderOrHealer()
    return UnitIsGroupLeader("player") or _G.FJI_HEALER
end

-- the first trigger alone decides
local function FirstTrigger(env, t) return t[1] end

-- ============================================================
-- SETTINGS / AUTOMATION
-- ============================================================
local function Mute(frameName, ev)
    if frameName:IsEventRegistered(ev) then frameName:UnregisterEvent(ev) end
end
B["[NX] Disable Raid Emotes"] = {
    ["init"] = function() end,
    ["triggers.1.trigger"] = function(env, event)
        if event ~= "ZONE_CHANGED_NEW_AREA" or not env.config.option.disableEmoteEnable then return end
        for _, ev in ipairs({ "RAID_BOSS_EMOTE", "RAID_BOSS_WHISPER", "CLEAR_BOSS_EMOTES" }) do Mute(RaidBossEmoteFrame, ev) end
        return true
    end,
}

-- Kel'Thuzad: up to six groups of players, each with its own mark. While
-- the piece shows, the first player of each group (in the order typed)
-- who is here and not already wearing the group's mark gets it; when it
-- goes, every listed player wearing their group's mark loses it.
do
    local GROUPS = { "first", "second", "third", "fourth", "fifth", "sixth" }
    local function Each(env, fn)
        local opt = env.config.group.option
        for i, g in ipairs(GROUPS) do
            local mark = opt[g .. "Group"][g .. "Mark"]
            for _, name in ipairs(env.players[i]) do
                if UnitExists(name) and fn(name, mark) then break end
            end
        end
    end
    B["[RL][NX][Kel'Thuzad] AutoMark Players"] = {
        ["init"] = function(env)
            local opt = env.config.group.option
            env.players = {}
            env.marks = {}
            for i, g in ipairs(GROUPS) do
                local group = opt[g .. "Group"]
                local list = {}
                local typed = group[g .. "Player"]
                if typed and typed ~= "" then
                    for name in string.gmatch(typed, "([^,]+)") do list[#list + 1] = name end
                end
                env.players[i] = list
                env.marks[group[g .. "Mark"]] = true
            end
        end,
        ["actions.start.custom"] = function(env)
            if not (env.config.group.option.enable and env.state) then return end
            Each(env, function(name, mark)
                if GetRaidTargetIndex(name) == mark then return false end
                SetRaidTarget(name, mark)
                env.marks[mark] = false
                print(SAY .. "AutoMarked " .. name .. " with |TInterface/TargetingFrame/UI-RaidTargetingIcon_" .. mark .. ":14:14|t")
                return true
            end)
        end,
        ["actions.finish.custom"] = function(env)
            Each(env, function(name, mark)
                if GetRaidTargetIndex(name) == mark then
                    SetRaidTarget(name, 0)
                    env.marks[mark] = true
                end
                return false
            end)
        end,
    }
end

-- whoever has the debuff gets the next free mark, and their old one back
-- afterwards
local function MarkWhileDebuffed()
    return { ["init"] = K.MarkPool(), ["actions.start.custom"] = K.MarkOnShow(), ["actions.finish.custom"] = K.MarkClear() }
end
B["[RL][NX][Kel'Thuzad] AutoMark Detonate Mana"] = MarkWhileDebuffed()
B["[RL][NX][Kel'Thuzad] AutoMark Chains of Kel'Thuzad"] = MarkWhileDebuffed()
B["[RL][NX][Grobbulus] AutoMark Mutating Injection"] = MarkWhileDebuffed()

-- ============================================================
-- GRAND WIDOW FAERLINA: EMBRACE
-- ============================================================
-- thirty seconds of the boss being silenced (enrage cannot come)
B["[NX][Grand Widow] Embrace Timer"] = K.Merge(
    Pop{ on = "WA_WIDOW_EMBRACE_SILENCED", dur = 30, sample = function() return Preview(30) end },
    { ["conditions.1.changes.2.value"] = function() Speak("Embrace Ending") end })

-- ============================================================
-- LOATHEB: SPORE TEAMS
-- ============================================================
-- The raid leader's client builds six teams of five (typed by name in the
-- options, or pasted as "TEAM1-Name Name ... TEAM2-..."), and a second
-- after the pull sends them to the raid (WA_LOASPORE_ASSIGNMENT, a table
-- of GUID lists team1..team6). Every client's six team lists show their
-- team; a player's bar runs 90 seconds once they have the spore's buff.
do
    local function Header(icon)
        return {
            ["triggers.1.trigger"] = function(env, allstates, event, team)
                if FIGHT_OVER[event] then
                    if allstates[""] then return K.Drop(allstates, "") end
                end
                if event == "OPTIONS" then
                    K.Put(allstates, "", { team = math.random(1, 3), icon = icon })
                    return true
                end
                if event == "WA_LOASPORE_ASSIGNMENT" then
                    K.Put(allstates, "", { team = team, icon = icon })
                    return true
                end
            end,
        }
    end
    B["[NX][Loatheb] Header #1"] = Header(136112)
    for i = 2, 6 do B["[NX][Loatheb] Header #" .. i] = Header(nil) end

    -- a team list: one bar per player in team n
    local function TeamList(n)
        local teams = {}
        local function Forget() wipe(teams) end
        local HANDLERS = {
            WA_LOASPORE_ASSIGNMENT = function(allStates, data)
                Forget()
                teams = { data.team1 or {}, data.team2 or {}, data.team3 or {}, data.team4 or {}, data.team5 or {}, data.team6 or {} }
                -- everyone on the team shows; a newcomer starts with no
                -- timer, a bar kept from before keeps its own
                HideAll(allStates)
                for _, guid in ipairs(teams[n]) do
                    local st = allStates[guid]
                    if not st then
                        st = { progressType = "timed", duration = 0, expirationTime = GetTime() }
                        allStates[guid] = st
                    end
                    st.show = true
                    st.changed = true
                    st.guid = guid
                    st.isMe = (guid == WA.myGUID)
                end
                return true
            end,
            WA_SPORE_APPLIED = function(allStates, destGUID)
                local st = allStates[destGUID]
                if st then
                    st.duration = 90
                    st.expirationTime = GetTime() + 90
                    st.changed = true
                end
                return true
            end,
            ENCOUNTER_START = function() Forget() end,
            STATUS = function()
                Forget()
                return false
            end,
            OPTIONS = function(allStates)
                Forget()
                local me, now = WA.myGUID, GetTime()
                -- five sample bars: two of them mine, three with a spore up
                local looks = { { true, 90 }, { true, 0 }, { false, 0 }, { false, 90 }, { false, 90 } }
                for i, look in ipairs(looks) do
                    allStates[i] = { show = true, changed = true, guid = me, isMe = look[1], progressType = "timed",
                        duration = look[2], expirationTime = now + look[2] }
                end
                return true
            end,
        }
        local function Over(allStates)
            Forget()
            HideAll(allStates)
            return true
        end
        HANDLERS.ENCOUNTER_END, HANDLERS.WA_FJI_ENCOUNTER_END = Over, Over
        return {
            ["init"] = function(env) env.handlers = HANDLERS end,
            -- the time since the spore went up
            ["text"] = function(env)
                if env.state.expirationTime then
                    return GetTime() - (env.state.expirationTime - env.state.duration)
                end
                return 0
            end,
            ["triggers.1.trigger"] = function(env, states, event, ...)
                return env.handlers[event](states, ...)
            end,
        }
    end
    for i = 1, 6 do B["[NX][Loatheb] Team #" .. i] = TeamList(i) end
end

-- Roster helpers the three raid leader assigners share.
-- The group by lowercase name -> GUID (and GUID -> lowercase name).
local function Roster(strict)
    local byName, byGuid = {}, {}
    for unit in RM.IterateGroup() do
        local guid, name = UnitGUID(unit), UnitName(unit)
        if strict then
            if guid and name then
                byName[strlower(name)] = guid
                byGuid[guid] = strlower(name)
            end
        else
            byName[strlower(name)] = guid
        end
    end
    return byName, byGuid
end
-- every line of typed names that is in the group goes on list (once);
-- added(guid, name) for each, and stop once the list holds max
local function TypedLines(list, text, byName, max, added)
    for line in gmatch(text, "[^\r\n]+") do
        local name = strlower(strtrim(line))
        local guid = byName[name]
        if guid and not tContains(list, guid) then
            tinsert(list, guid)
            if added then added(guid, name) end
            if max and #list >= max then return end
        end
    end
end
-- "bob o'neil" -> "Bob O'neil" (both values gsub gives)
local function Capital(name)
    if not name then return "" end
    return name:gsub("(%a)([%w_']*)", function(first, rest) return string.upper(first) .. string.lower(rest) end)
end
local function Numbered(list, byGuid)
    for i, guid in ipairs(list) do
        SendChatMessage(string.format("%d. %s", i, Capital(byGuid[guid]) or "Unknown"), "RAID")
    end
end
local function Clear(lists)
    for _, l in ipairs(lists) do wipe(l) end
end

-- (each assigner keeps its lists for as long as the piece is loaded and
-- empties them in place: the assignment hands the same tables over)
do
    local function Build(env)
        local opt = env.config.option.spore
        local teams = env.teams
        wipe(env.guidToName)
        local byName = Roster(false)
        if opt.useManual then
            Clear(teams)
            for i = 1, 6 do
                TypedLines(teams[i], opt["priorityTeam" .. i], byName, 5, function(guid, name) env.guidToName[guid] = name end)
            end
        elseif opt.useImport then
            Clear(teams)
            -- "TEAM1-Ann Bob, Cat TEAM2-Dan ..." into words; a TEAMn- word
            -- starts that team with its first name
            local text = (opt.teams or ""):gsub("[\r\n\t]+", " "):gsub(",", " "):gsub("%s+", " "):gsub("TEAM", "|TEAM")
            local words = {}
            for _, part in ipairs({ strsplit(" ", text) }) do
                for _, word in ipairs({ strsplit("|", part) }) do
                    if word ~= "" then tinsert(words, word) end
                end
            end
            local team
            for _, word in ipairs(words) do
                local w = strtrim(word)
                local which, first = w:lower():match("^(team[1-6])%-(.+)$")
                if which then
                    team = teams[tonumber(which:sub(5))]
                    if team and #team < 5 then
                        local name = strlower(strtrim(first))
                        local guid = byName[name]
                        if guid and not tContains(team, guid) then
                            tinsert(team, guid)
                            env.guidToName[guid] = name
                        end
                    end
                elseif team and #team < 5 then
                    local name = strlower(w)
                    local guid = byName[name]
                    if guid and not tContains(team, guid) then
                        tinsert(team, guid)
                        env.guidToName[guid] = name
                    end
                end
            end
        end
        -- (with neither switch on nothing is built: guidToName stays empty,
        -- so nothing is sent - the old teams are never re-sent)
    end
    local function Over(env)
        Clear(env.teams)
        wipe(env.guidToName)
    end
    B["[NX][Loatheb][RL] Team Assigner"] = {
        ["init"] = function(env)
            env.guidToName = {}
            env.teams = { {}, {}, {}, {}, {}, {} }
            env.handlers = {
                ENCOUNTER_START = function() C_Timer.After(1, function() RM.Fire("WA_LOASPORE_POPULATE_LIST") end) end,
                ENCOUNTER_END = function() Over(env) end,
                WA_FJI_ENCOUNTER_END = function() Over(env) end,
                WA_LOASPORE_POPULATE_LIST = function()
                    Build(env)
                    if next(env.guidToName) == nil then
                        print("Raid Mods - [Loatheb Spores] No players in group - not sending assignment.")
                        return
                    end
                    print("Raid Mods - [Loatheb Spores] Players Found - sending assignment.")
                    local t = env.teams
                    Sync("WA_LOASPORE_ASSIGNMENT", { team1 = t[1], team2 = t[2], team3 = t[3], team4 = t[4], team5 = t[5], team6 = t[6] })
                end,
                OPTIONS = function() end,
                STATUS = function() end,
            }
        end,
        ["triggers.1.trigger"] = function(env, states, event, ...)
            if env.config.option.spore.disable then return false end
            return env.handlers[event](states, ...)
        end,
    }
end

-- ============================================================
-- LOATHEB: CORRUPTED MIND HEALING ORDER
-- ============================================================
do
    local function Build(env)
        local opt = env.config.option.mind
        local order = env.order
        local byName
        byName, env.byGuid = Roster(true)
        wipe(order)
        if opt.useManual then
            TypedLines(order, opt.manualOrder or "", byName)
        elseif opt.useImport then
            local text = (opt.order or ""):gsub("[\r\n\t]+", ","):gsub("%s+", "")
            for entry in gmatch(text, "[^,]+") do
                local guid = byName[strlower(strtrim(entry))]
                if guid and not tContains(order, guid) then tinsert(order, guid) end
            end
        end
    end
    B["[NX][Loatheb][RL] Corrupted Mind Assigner"] = {
        ["init"] = function(env)
            env.order = {}
            env.byGuid = {}
            local function Over() wipe(env.order) end
            env.handlers = {
                ENCOUNTER_START = function()
                    local opt = env.config.option.mind
                    if not opt.useManual and not opt.useImport then return false end
                    C_Timer.After(0.5, function() RM.Fire("WA_LOAMIND_POPULATE_LIST") end)
                end,
                ENCOUNTER_END = Over,
                WA_FJI_ENCOUNTER_END = Over,
                WA_LOAMIND_POPULATE_LIST = function()
                    Build(env)
                    if #env.order == 0 then
                        print("Raid Mods - [Loatheb Corrupted Mind] No players in group - not sending assignment.")
                        return
                    end
                    Sync("WA_LOAMIND_ASSIGNMENT", { order = env.order })
                    SendChatMessage("---- Raid Mods - Loatheb Healing Order ----", "RAID")
                    Numbered(env.order, env.byGuid)
                end,
                OPTIONS = function() end,
                STATUS = function() end,
            }
        end,
        ["triggers.1.trigger"] = function(env, states, event, ...)
            if env.config.option.mind.disable then return false end
            return env.handlers[event](states, ...)
        end,
    }
end

-- The healers' overview: every healer with their Corrupted Mind state
-- (Available / Debuffed for 60 s / Dead), in the order the raid leader
-- sent, else the typed order, else by class or name.
do
    local CLASS_RANK = { PALADIN = 1, SHAMAN = 2, PRIEST = 3, DRUID = 4 }
    local HEALERS = K.Set{ "DRUID", "PRIEST", "SHAMAN", "PALADIN" }
    local MIND = K.Set{ 29184, 29197, 29195, 29199 }

    local function ByName(a, b) return string.lower(a.name) < string.lower(b.name) end
    -- players with a place first, in that order; the rest by name
    local function ByPlace(place, keyOf)
        return function(a, b)
            local pa, pb = place[keyOf(a)], place[keyOf(b)]
            if pa and pb then return pa < pb end
            if pa then return true end
            if pb then return false end
            return ByName(a, b)
        end
    end
    local function Sort(env, players)
        local sent = env.receivedOrder
        if sent and #sent > 0 then
            local place = {}
            for i, guid in ipairs(sent) do place[guid] = i end
            table.sort(players, ByPlace(place, function(p) return p.guid end))
            return
        end
        local opt = env.config.option.mind
        if opt.useManual then
            local place, n = {}, 0
            for name in string.gmatch(opt.manualOrder or "", "([^,]+)") do
                local clean = strlower(strtrim(name))
                if clean ~= "" then
                    n = n + 1
                    -- (a name typed twice keeps its later place)
                    place[clean] = n
                end
            end
            if n > 0 then
                table.sort(players, ByPlace(place, function(p) return strlower(p.name) end))
                return
            end
        end
        if (opt.sorting or 1) == 2 then
            table.sort(players, function(a, b)
                local ra, rb = CLASS_RANK[a.class] or 99, CLASS_RANK[b.class] or 99
                if ra == rb then return ByName(a, b) end
                return ra < rb
            end)
        else
            table.sort(players, ByName)
        end
    end
    -- healers and tanks (by role flag), the leader and assists, and every
    -- healing class (by the English class token, so any client language)
    local function Sees()
        return _G.FJI_HEALER or _G.FJI_TANK or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
            or HEALERS[select(2, UnitClass("player"))] or false
    end
    local function Build(env, allStates)
        HideAll(allStates)
        if Sees() then
            local players = {}
            local sent = env.receivedOrder
            for unit in RM.IterateGroup() do
                local guid, name, class = UnitGUID(unit), UnitName(unit), UnitClassBase(unit)
                if guid and name and class then
                    local take
                    if not sent then
                        take = HEALERS[class]
                    else
                        take = tContains(sent, guid)
                    end
                    if take then tinsert(players, { name = name, guid = guid, class = class }) end
                end
            end
            Sort(env, players)
            for i, p in ipairs(players) do
                local st = allStates[p.guid] or {}
                st.show = true
                st.changed = true
                st.guid = p.guid
                st.isMe = (p.guid == WA.myGUID)
                st.progressType = "timed"
                st.duration = st.duration or 0
                st.expirationTime = st.expirationTime or GetTime()
                st.status = st.status or "Available"
                st.index = i
                allStates[p.guid] = st
            end
        end
        return true
    end
    local function Mind(allStates, destGUID, secs, status)
        local st = allStates[destGUID]
        if st then
            st.duration = secs
            st.expirationTime = GetTime() + secs
            st.changed = true
            st.status = status
        end
        return true
    end
    -- the preview: twelve bars, the same four looks three times
    local LOOKS = {
        { me = true, dur = 60, status = "Debuffed" },
        { me = false, dur = 0.1, status = "Available" },
        { me = false, dur = 0.1, status = "Dead" },
        { me = false, dur = 25, status = "Dead", offline = true },
    }
    local function Over(allStates)
        HideAll(allStates)
        return true
    end
    B["L:[NX][Loatheb] Corrupted Mind"] = {
        ["logic"] = FirstTrigger,
        ["init"] = function(env)
            env.spellIDs = MIND
            env.receivedOrder = nil
            env.handlers = {
                COMBAT_LOG_EVENT_UNFILTERED = function(allStates, _, subEvent, _, _, _, _, _, destGUID, _, _, _, spellId)
                    if not MIND[spellId] then return false end
                    if subEvent == "SPELL_AURA_APPLIED" then return Mind(allStates, destGUID, 60, "Debuffed") end
                    if subEvent == "SPELL_AURA_REMOVED" then return Mind(allStates, destGUID, 0, "Available") end
                end,
                UNIT_HEALTH = function(allStates, unit)
                    if not unit then return end
                    local guid = UnitGUID(unit)
                    if not guid then return end
                    local st = allStates[guid]
                    if not st then return end
                    local dead = UnitIsDead(unit) or UnitIsGhost(unit)
                    if dead and st.status ~= "Dead" then
                        st.status = "Dead"
                        st.changed = true
                        return true
                    elseif not dead and st.status == "Dead" then
                        st.status = "Available"
                        st.changed = true
                        return true
                    end
                end,
                UNIT_FLAGS = function(allStates, unit)
                    if not unit then return end
                    local guid = UnitGUID(unit)
                    if not guid then return end
                    local st = allStates[guid]
                    if not st then return end
                    local online = UnitIsConnected(unit)
                    if st.isConnected ~= online then
                        st.isConnected = online
                        st.changed = true
                        return true
                    end
                end,
                ENCOUNTER_END = Over,
                WA_FJI_ENCOUNTER_END = Over,
                ENCOUNTER_START = function(allStates)
                    env.receivedOrder = nil
                    return Build(env, allStates)
                end,
                WA_LOAMIND_ASSIGNMENT = function(allStates, data)
                    if env.timer then
                        env.timer:Cancel()
                        env.timer = nil
                    end
                    local order = data and data.order or nil
                    if order and #order > 0 then
                        env.receivedOrder = order
                        print("|cff00ff00Raid Mods|r |cff3399FFNaxx|r - Corrupted Mind Overview Assignment received with " .. #order .. " players.")
                    end
                    return Build(env, allStates)
                end,
                STATUS = function() end,
                OPTIONS = function(allStates)
                    local me, now = WA.myGUID, GetTime()
                    for i = 1, 12 do
                        local look = LOOKS[(i - 1) % 4 + 1]
                        local st = { show = true, changed = true, guid = me, isMe = look.me, progressType = "timed",
                            duration = look.dur, expirationTime = now + look.dur, status = look.status }
                        if look.offline then st.isConnected = false end
                        allStates[i] = st
                    end
                    return true
                end,
            }
        end,
        ["triggers.1.trigger"] = function(env, states, event, ...)
            return env.handlers[event](states, ...)
        end,
    }
end

-- ============================================================
-- KEL'THUZAD: FROSTBOLT KICK ROTATION
-- ============================================================
-- The raid leader types three kick teams; on the pull they go to the raid
-- (WA_KTKICK_ASSIGNMENT team1..team3) and to raid chat.
do
    local function Build(env)
        local opt = env.config.option.fb
        local byName
        byName, env.byGuid = Roster(true)
        Clear(env.teams)
        for i = 1, 3 do TypedLines(env.teams[i], opt["team" .. i], byName) end
    end
    B["[NX][Kel'Thuzad][RL] KT Frostbolt Kickers"] = {
        ["init"] = function(env)
            env.teams = { {}, {}, {} }
            env.byGuid = {}
            local teams = env.teams
            local function Over() Clear(teams) end
            env.handlers = {
                ENCOUNTER_START = function() C_Timer.After(0.5, function() RM.Fire("WA_KTKICK_POPULATE_LIST") end) end,
                ENCOUNTER_END = Over,
                WA_FJI_ENCOUNTER_END = Over,
                WA_KTKICK_POPULATE_LIST = function()
                    Build(env)
                    if #teams[1] == 0 and #teams[2] == 0 and #teams[3] == 0 then
                        print("Raid Mods - [KT Frostbolt Kickers] No players in group - not sending assignment.")
                        return
                    end
                    Sync("WA_KTKICK_ASSIGNMENT", { team1 = teams[1], team2 = teams[2], team3 = teams[3] })
                    SendChatMessage("---- Raid Mods - KT Frostbolt Kicks ----", "RAID")
                    for i = 1, 3 do
                        if #teams[i] > 0 then
                            SendChatMessage("Kick Frostbolt " .. i .. ":", "RAID")
                            Numbered(teams[i], env.byGuid)
                        end
                    end
                end,
                OPTIONS = function() end,
                STATUS = function() end,
            }
        end,
        ["triggers.1.trigger"] = function(env, states, event, ...)
            if env.config.option.fb.disable then return false end
            return env.handlers[event](states, ...)
        end,
    }
end

-- The rotation list: three rows, the one up next marked; a Frostbolt cast
-- runs its two seconds on that row, and a cast landing or being kicked
-- moves "next" on. Players get a ping when their team is up
-- (WA_FJI_FROSTBOLT_ROTATE_ALERT).
B["L:[NX][Kel'Thuzad] Frostbolt Interrupt"] = {
    ["triggers.1.trigger"] = function(env, a, e, ...)
        if e == "OPTIONS" then
            local me = WA.me
            for i = 1, 3 do
                a[i] = { show = true, changed = true, next = false, label = i, players = me .. "," .. me .. "," .. me }
            end
            return true
        end
        if e == "ENCOUNTER_START" then
            env.myKick = nil
            env.teamData = nil
            local opt = env.config.option
            if opt.alert and opt.kick ~= 4 then env.myKick = opt.kick end
            return
        end
        if e == "WA_KTKICK_ASSIGNMENT" then
            local data = ...
            if not data then return end
            env.teamData = data
            env.myKick = nil
            local names = {}
            for unit in RM.IterateGroup() do
                local guid, name = UnitGUID(unit), UnitName(unit)
                if guid and name then names[guid] = name end
            end
            for i = 1, 3 do
                local list = {}
                for _, guid in ipairs(data["team" .. i] or {}) do
                    if names[guid] then tinsert(list, names[guid]) end
                    if guid == WA.myGUID then env.myKick = i end
                end
                -- (the names go back onto the shared assignment table)
                data["team" .. i .. "_names"] = table.concat(list, ", ")
            end
            if env.myKick then print(string.format("[KT Kick] You are in team %d.", env.myKick)) end
            return
        end
        if FIGHT_OVER[e] then
            HideAll(a)
            env.myKick = nil
            env.teamData = nil
            return true
        end
        if e == "WA_KT_P2_START" then
            for i = 1, 3 do
                local who = ""
                local data = env.teamData
                if data and data["team" .. i .. "_names"] then
                    who = data["team" .. i .. "_names"]
                elseif env.myKick == i then
                    who = WA.me
                end
                a[i] = { show = true, changed = true, next = (i == 1), progressType = "timed", duration = 0, expirationTime = GetTime(),
                    label = i, isCasting = false, players = who ~= "" and who or nil }
            end
            return true
        end
        if e == "KT_FROSTBOLT_CAST_START" then
            for i = 1, 3 do
                local row = a[i]
                if row and row.next then
                    row.progressType = "timed"
                    row.duration = 2
                    row.expirationTime = GetTime() + 2
                    row.changed = true
                    row.isCasting = true
                    if env.config.option.alert and env.myKick == i then RM.Fire("WA_FJI_FROSTBOLT_ROTATE_ALERT", i) end
                    break
                end
            end
            return true
        end
        if e == "KT_FROSTBOLT_CAST_SUCCESS" or e == "KT_FROSTBOLT_INTERRUPT" then
            for _, row in pairs(a) do
                row.isCasting = false
                row.changed = true
                row.duration = 0
                row.expirationTime = 0
            end
            local up
            for i = 1, 3 do
                if a[i] and a[i].next then
                    up = i
                    break
                end
            end
            if up then
                a[up].next = false
                a[up].changed = true
                local after = up % 3 + 1
                a[after].next = true
                a[after].changed = true
            end
            return true
        end
    end,
}

-- ============================================================
-- TIMER BARS
-- ============================================================
-- colours are 0-255 RGB plus alpha; every Naxxramas bar is the same orange
do
    local ORANGE = { 255, 149, 87, 1 }
    local function Bar(name, icon, autoHide) return { name = name, icon = icon, color = ORANGE, autoHide = autoHide } end
    B["BT:[NX][All] Boss Timers"] = K.TimerBars{ sample = 3, hideAtZero = true,
        -- each key can be switched off in the options
        allow = function(env, key) return env.config.option.enabledGroup[key] end,
        bars = {
            ANUB_LOCUST_SWARM = Bar("Locust Swarm", 136045),
            WIDOW_ENRAGE = Bar("Enrage", 136224),
            MAEXXNA_WEB_WRAP = Bar("Web Wrap", 136113),
            MAEXXNA_WEB_SPRAY = Bar("Web Spray", 136113),
            MAEXXNA_NECROTIC_POISON = Bar("Necrotic Poison", 132105),
            MAEXXNA_SPIDERS = Bar("Spiders", 134321, true),
            NOTH_CURSE = Bar("Curse", 136119),
            NOTH_TELEPORT = Bar("Teleport", 237560),
            NOTH_TELEPORT_BACK = Bar("Teleports Back", 237560, true),
            NOTH_ADDS = Bar("Add Wave", 252996),
            HEIGAN_TELEPORT = Bar("Teleport", 135736, true),
            HEIGAN_DANCE = Bar("Dance", 135805, true),
            HEIGAN_DECREPIT_FEVER = Bar("Decrepit Fever", 132100),
            LOATHEB_REMOVE_CURSE = Bar("Remove Curse", 135952),
            LOATHEB_DOOM = Bar("Doom", 136179),
            LOATHEB_SPORE = Bar("Spore", 132371),
            RAZUVIOUS_DISRUPTING_SHOUT = Bar("Disrupting Shout", 132333),
            GOTHIK_WAVE = Bar("Next Wave", 237590),
            GOTHIK_PHASE_TWO = Bar("Gothik Phase Two", BOSS_ICON.GOTHIK),
            ["4HM_VOID_ZONE"] = Bar("Void Zone", 132886, true),
            ["4HM_METEOR"] = Bar("Meteor", 135808, true),
            ["4HM_HOLY_WRATH"] = Bar("Holy Wrath", 136208, true),
            ["4HM_MARK"] = Bar("Next Mark", 132212),
            PATCHWERK_BERSERK = Bar("Berserk", BOSS_ICON.PATCHWERK),
            GROBBULUS_SLIME_SPRAY = Bar("Slime Spray", 134437),
            GROBBULUS_MUTATING_INJECTION = Bar("Mutating Injection", 136127),
            GROBBULUS_POISON_CLOUD = Bar("Poison Cloud", 136006),
            GLUTH_MORTAL_WOUND = Bar("Mortal Wound", 132109),
            GLUTH_TERRIFYING_ROAR = Bar("Terrifying Roar", 132111),
            GLUTH_FRENZY = Bar("Frenzy", 132117),
            THADDIUS_MAGNETIC_PULL = Bar("Magnetic Pull", 136039),
            THADDIUS_BERSERK = Bar("Berserk", 136224),
            THADDIUS_POLARITY_SHIFT = Bar("Polarity Shift", 136048),
            SAPPHIRON_AIR_PHASE = Bar("Air Phase", 134155),
            SAPPHIRON_GROUND_PHASE = Bar("Landing", 134156),
            SAPPHIRON_LIFE_DRAIN = Bar("Life Drain", 136169),
            KT_PHASE_TWO = Bar("Phase 2", BOSS_ICON.KELTHUZAD, true),
            -- (Zac, 2026-10-23: Kel'Thuzad's Chains, Frost Blast and
            -- Detonate Mana stay off these bars - they have their own)
        } }
end

-- A wiped boss comes back after 30 seconds.
do
    local function Countdown(env, allstates)
        K.Put(allstates, "", { progressType = "timed", duration = env.eRespawnTimer - GetTime(), expirationTime = env.eRespawnTimer,
            autoHide = true, bossName = env.bossName })
        return true
    end
    B["BT:[NX][All] Boss Respawn"] = {
        ["triggers.1.trigger"] = function(env, allstates, event, encounterId, encounterName, _, _, success)
            if event == "ENCOUNTER_END" and success == 0 then
                -- (75 seconds and its own name for one encounter id the
                -- bar also knows from another raid)
                if encounterId == 1027 then
                    env.eRespawnTimer = GetTime() + 75
                    env.bossName = "Omnotron"
                else
                    env.bossName = encounterName
                    env.eRespawnTimer = GetTime() + 30
                end
                return Countdown(env, allstates)
            elseif event == "STATUS" and env.eRespawnTimer and env.eRespawnTimer - GetTime() > 0 then
                return Countdown(env, allstates)
            end
        end,
    }
end

-- The emphasized list (the last ten seconds of a bar)
B["BTE:[NX][All] Emphasized Timers"] = K.Emphasized{ sampleKey = "LaserAttack_" }

-- ============================================================
-- CHARACTER / CIRCLES
-- ============================================================
-- something that names the player
local function IsMe(env, event, guid) return guid == WA.myGUID end
B["CH:[NX][4HM] Void Zone Warn"] = { ["triggers.1.trigger"] = IsMe }
B["CH:[NX][Grobbulus] Mutating Injection"] = { ["triggers.1.trigger"] = IsMe }

-- Maexxna: a reminder to throw a snowball (11 and 51 seconds in)
B["C:[NX][Maexxna] Snowball Helper"] = {
    ["actions.start.custom"] = function() SpeakSfx("Snowball Soon") end,
    ["triggers.1.trigger"] = function(env, a, e)
        if e == "OPTIONS" then
            a[""] = Preview(5, { icon = 132387 })
            return true
        end
        if e == "ENCOUNTER_START" then
            for _, secs in ipairs({ 11, 51 }) do
                C_Timer.After(secs, function() RM.Fire("WA_FJI_SNOWBALL_HELPER") end)
            end
        end
        if e == "WA_FJI_SNOWBALL_HELPER" then
            a[""] = Preview(5)
            return true
        end
    end,
}
B["C:[NX][Thaddius] Polarity Shift"] = Pop{ on = "WA_NUMEN_TIMER", when = AtZero("THADDIUS_POLARITY_SHIFT"), dur = 3, fields = { icon = 136048 },
    sample = function() return Preview(3, { icon = 136048 }) end }
B["C:[NX][Sapphiron] Frost Bomb"] = Pop{ on = "WA_NUMEN_TIMER", when = AtZero("SAPPHIRON_FROST_BOMB"), dur = 7, fields = { icon = 135848 },
    sample = function() return Preview(7, { icon = 135848 }) end }
B["C:[NX][Kel'Thuzad] Detonate Mana"] = SayOnShow("Detonate Mana on You")

-- ============================================================
-- GTFO / ICONS
-- ============================================================
local function GtfoSound(env)
    if env.config.option.enable then RM.RaidSound(env.config.option.gtfoSound) end
end
B["GTFO:[NX][Grobbulus] Poison"] = { ["actions.start.custom"] = GtfoSound }
B["GTFO:[NX][Sapphiron] Chill"] = { ["actions.start.custom"] = GtfoSound }

B["I:[NX][Trash] Polymorph"] = SayOnShow("Baa")
B["I:[NX][Maexxna] Web Wrap"] = { ["actions.start.custom"] = function() Speak("Wrap") end }
-- what a stack costs: healing taken, or (Infected Wound) attack time
local function PerStack(sign, each)
    return function(env, expirationTime, duration, progress, formatedDuration, name, icon, stacks)
        return sign .. (tonumber(stacks) or 0) * each
    end
end
B["I:[NX][Gothik] Harvest Soul"] = { ["text"] = PerStack("-", 10) }
B["I:[NX][Gluth] Mortal Wound"] = { ["text"] = PerStack("-", 10) }
B["I:[NX][Gluth] Infected Wound"] = { ["text"] = PerStack("+", 100) }
-- Thaddius charge stacks: 10% damage each
B["I:[NX][Thaddius] Charge Damage"] = {
    ["text"] = function(env)
        if WA.IsOptionsOpen() then return math.random(1, 5) * 10 end
        local first = env.states[1]
        if first and first.stacks then return first.stacks * 10 end
    end,
}

-- ============================================================
-- LEADERBOARDS AND LISTS
-- ============================================================
-- Decurses during the fight, per player, with the raid total on top; the
-- raid leader posts the table to raid chat when the fight ends.
local function DecurseRanking(icon)
    local DECURSES = K.Set{ 475, 2782, 15729 }
    local function Total(value)
        return { show = true, changed = true, name = "Total", value = value, total = 10000, progressType = "static", player = false, index = 1, icon = icon }
    end
    -- the total first, then players by decurses (those with none last)
    local function Order(allstates)
        local some, none = {}, {}
        for key, st in pairs(allstates) do
            if key ~= "total" and st.player then
                if st.value > 0 then tinsert(some, st) else tinsert(none, st) end
            end
        end
        table.sort(some, function(a, b) return a.value > b.value end)
        local i = 2
        for _, list in ipairs({ some, none }) do
            for _, st in ipairs(list) do
                st.index = i
                st.changed = true
                i = i + 1
            end
        end
    end
    local function Count(env, allstates, who)
        local st = allstates[who] or { show = true, name = who, value = 0, total = 10000, progressType = "static", player = true, index = 2 }
        allstates[who] = st
        st.value = env.decurses[who] or 0
        st.changed = true
        local sum = 0
        for _, n in pairs(env.decurses) do sum = sum + n end
        local total = allstates.total or { show = true, name = "Total", value = 0, total = 10000, progressType = "static", player = false, index = 1 }
        allstates.total = total
        total.value = sum
        total.changed = true
        Order(allstates)
    end
    local function Post(env)
        if not env.decurses or next(env.decurses) == nil then return end
        local rows = {}
        for who, n in pairs(env.decurses) do tinsert(rows, { who = who, n = n }) end
        table.sort(rows, function(a, b) return a.n > b.n end)
        SendChatMessage("Decurse Leaderboard:", "RAID")
        for _, row in ipairs(rows) do SendChatMessage(row.who .. " - " .. row.n .. " Decurses", "RAID") end
    end
    return {
        ["init"] = function(env)
            env.spellIDs = DECURSES
            env.decurses = {}
            env.throttle = 0
        end,
        ["logic"] = FirstTrigger,
        ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, sourceName, _, _, _, _, _, _, spellId)
            if event == "OPTIONS" then
                for i = 1, 8 do
                    allstates["Player" .. i] = { show = true, name = WA.me, value = math.random(1, 75), total = 10000, progressType = "static",
                        player = true, index = i + 1 }
                end
                allstates.total = Total(math.random(10, 80))
                return true
            end
            if FIGHT_OVER[event] then
                local leader = UnitIsGroupLeader("player") and IsInRaid()
                if GetTime() - (env.throttle or 0) < 5 then return false end
                env.throttle = GetTime()
                if leader then Post(env) end
                return true
            end
            if event == "ENCOUNTER_START" then
                env.decurses = {}
                allstates.total = Total(0)
                return true
            end
            if not DECURSES[spellId] then return false end
            if subEvent == "SPELL_CAST_SUCCESS" then
                env.decurses[sourceName] = (env.decurses[sourceName] or 0) + 1
                Count(env, allstates, sourceName)
                return true
            end
        end,
    }
end
B["L:[NX][Noth] Decurse Ranking"] = DecurseRanking(136119)
B["L:[NX][Sapphiron] Decurse Ranking"] = DecurseRanking(136169)

-- Razuvious: who taunted (a priest's mind-controlled student, credited to
-- the priest), for the taunt's 20 seconds
do
    local TAUNT, CONTROL = 29060, 10912
    -- the player behind a pet's GUID
    local function Owner(guid)
        if not guid then return nil end
        if guid == UnitGUID("pet") then return UnitGUID("player") end
        for unit in RM.IterateGroup() do
            if UnitGUID(unit .. "pet") == guid then return UnitGUID(unit) end
        end
        return nil
    end
    local function Row(guid) return { show = true, changed = true, progressType = "timed", duration = 20, expirationTime = GetTime() + 20, autoHide = true, guid = guid } end
    B["L:[NX][Razuvious] Taunt List"] = {
        ["init"] = function(env)
            env.taunt = TAUNT
            env.MC = CONTROL
        end,
        ["triggers.1.trigger"] = function(env, a, e, _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId)
            if e == "OPTIONS" then
                for i = 1, 3 do a[i] = Row(WA.myGUID) end
                return true
            end
            if subEvent == "UNIT_DIED" and a[destGUID] then return K.Drop(a, destGUID) end
            if subEvent == "SPELL_AURA_REMOVED" and spellId == CONTROL and a[sourceGUID] then return K.Drop(a, sourceGUID) end
            if subEvent == "SPELL_CAST_SUCCESS" and spellId == TAUNT then
                local guid = Owner(sourceGUID) or sourceGUID
                a[guid] = Row(guid)
                RM.Fire("WA_RAZUVIOUS_TAUNT_CAST", guid, destGUID)
                return true
            end
        end,
    }
end

-- Boss health bars from what the raid is targeting, refreshed once a
-- second while the piece shows; a boss that dies goes grey at 0.
-- bosses = { [npcId] = { slot, name, icon } }
local function HealthBars(bosses)
    local B2 = {}
    -- creates the bar on first sight only: once hidden it stays hidden
    function B2.Set(allstates, slot, name, icon, pct, dead)
        if not allstates[slot] then
            allstates[slot] = { show = true, changed = true, progressType = "static", value = 1, total = 1, percent = "100%", name = name, icon = icon }
        end
        local st = allstates[slot]
        if pct then
            st.value = pct
            st.percent = math.floor(pct * 100) .. "%"
        end
        if dead then
            st.isDead = true
            st.percent = "0%"
            st.value = 0
        end
        st.changed = true
        return true
    end
    function B2.Scan(allstates)
        for unit in RM.IterateGroup() do
            local who = unit .. "target"
            local guid = UnitGUID(who)
            if guid then
                local boss = bosses[Npc(guid)]
                local pct = UnitHealth(who) / UnitHealthMax(who)
                if boss then B2.Set(allstates, boss[1], boss[2], boss[3], pct) end
            end
        end
        return true
    end
    function B2.Died(allstates, destGUID)
        local boss = bosses[Npc(destGUID)]
        if boss then B2.Set(allstates, boss[1], boss[2], boss[3], 0, true) end
        return true
    end
    function B2.Close(env, allstates)
        HideAll(allstates)
        if env.ticker then
            env.ticker:Cancel()
            env.ticker = nil
        end
        return true
    end
    function B2.Ticker(event, times)
        return {
            ["actions.start.custom"] = function(env)
                if env.ticker then return end
                env.ticker = C_Timer.NewTicker(1, function() RM.Fire(event) end, times)
            end,
            ["actions.finish.custom"] = function(env)
                if env.ticker then
                    env.ticker:Cancel()
                    env.ticker = nil
                end
            end,
        }
    end
    return B2
end

do
    local MOGRAINE, KORTHAZZ, ZELIEK, BLAUMEUX = { 1, "Mograine", 136192 }, { 2, "Korth'azz", 136172 }, { 3, "Zeliek", 136137 }, { 4, "Blaumeux", 135900 }
    local HB = HealthBars{ ["16062"] = MOGRAINE, ["16064"] = KORTHAZZ, ["16063"] = ZELIEK, ["16065"] = BLAUMEUX }
    local function AllFull(a)
        for _, h in ipairs({ MOGRAINE, KORTHAZZ, ZELIEK, BLAUMEUX }) do HB.Set(a, h[1], h[2], h[3], 1) end
        return true
    end
    B["L:[NX][4HM] HP Overview"] = K.Merge(HB.Ticker("WA_FJI_4HMHP_TICKER"), {
        ["init"] = function(env)
            env.mograine, env.korthazz, env.zeliek, env.blaumeux = "16062", "16064", "16063", "16065"
        end,
        ["triggers.1.trigger"] = function(env, a, e, _, subEvent, _, _, _, _, _, destGUID)
            if e == "OPTIONS" then return AllFull(a) end
            if e == "PLAYER_REGEN_ENABLED" or FIGHT_OVER[e] then return HB.Close(env, a) end
            if e == "ENCOUNTER_START" then return AllFull(a) end
            if e == "WA_FJI_4HMHP_TICKER" then return HB.Scan(a) end
            if e == "COMBAT_LOG_EVENT_UNFILTERED" and subEvent == "UNIT_DIED" then return HB.Died(a, destGUID) end
        end,
    })

    local THAD = HealthBars{ ["15929"] = { 1, "Stalagg" }, ["15930"] = { 2, "Feugen" } }
    B["[NX] Thaddius Healthbars"] = K.Merge(THAD.Ticker("WA_FJI_THADHP_TICKER", 120), {
        ["init"] = function(env)
            env.stalagg, env.feugen = "15929", "15930"
        end,
        ["triggers.1.trigger"] = function(env, a, e, _, subEvent, _, _, _, _, _, destGUID)
            if e == "OPTIONS" then
                THAD.Set(a, 1, "Stalagg", nil, 0, true)
                THAD.Set(a, 2, "Feugen", nil, math.random(0, 10) / 10)
                return true
            end
            if FIGHT_OVER[e] then return THAD.Close(env, a) end
            if e == "ENCOUNTER_START" then
                THAD.Set(a, 1, "Stalagg", nil, 1)
                THAD.Set(a, 2, "Feugen", nil, 1)
                return true
            end
            if e == "WA_FJI_THADHP_TICKER" then return THAD.Scan(a) end
            if e == "WA_THADDIUS_P2_START" then return THAD.Close(env, a) end
            if e == "COMBAT_LOG_EVENT_UNFILTERED" and subEvent == "UNIT_DIED" then return THAD.Died(a, destGUID) end
        end,
    })
end
-- the two adds' bars in the order the pieces give them, else as listed
B["group:[NX] Thaddius HP Overview"] = {
    ["customSort"] = function(a, b)
        local sa, sb = a.region.state.sort, b.region.state.sort
        if sa and sb then return sb > sa end
        return a.dataIndex < b.dataIndex
    end,
}

-- Four Horsemen, for healers: which horseman to stand under next. The
-- rotation (clockwise or back) moves on at the mark count set in the
-- options and every so many marks after; the bar shows the target, its
-- mark stacks on you, and "Safe Zone" once that horseman is dead.
do
    local function Mobs()
        return {
            { name = "Thane", npcID = "16064", markID = 28832 },
            { name = "Blaumeux", npcID = "16065", markID = 28833 },
            { name = "Zeliek", npcID = "16063", markID = 28835 },
            { name = "Mograine", npcID = "16062", markID = 28834 },
        }
    end
    local function NextMob(env, currentIndex)
        local rotation = env.config.option.rotation
        if rotation == 1 then
            return (currentIndex % 4) + 1
        elseif rotation == 2 then
            return ((currentIndex - 2) % 4) + 1
        end
    end
    local function Stacks(env, name)
        for _, mob in pairs(env.mobs) do
            if mob.name == name or mob.markID == name then return env.marks[mob.markID] or 0 end
        end
        return 0
    end
    local function MoveOn(env, count)
        env.currentMobIndex = NextMob(env, env.currentMobIndex)
        env.currentMob = env.mobs[env.currentMobIndex]
        env.lastMoveCount = count
        RM.Fire("WA_FJI_4HM_HEALER_NEXT_MOB", env.currentMob.name)
    end
    local function Bar(dur, mob, mark)
        return { show = true, changed = true, progressType = "timed", duration = dur, expirationTime = GetTime() + dur, mob = mob, mark = mark }
    end
    B["L:[NX][4HM] Healer Mark Helper"] = {
        ["init"] = function(env)
            env.deadMobs = {}
            env.mobs = Mobs()
            env.marks = { [28832] = 0, [28833] = 0, [28834] = 0, [28835] = 0 }
            env.mobsByMark = {}
            for _, mob in pairs(env.mobs) do env.mobsByMark[mob.markID] = mob.name end
        end,
        ["logic"] = FirstTrigger,
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "OPTIONS" then
                allstates[""] = Bar(20, "Mograine", math.random(1, 3))
                return true
            end
            if not _G.FJI_HEALER then return false end
            local opt = env.config.option
            if not opt.enable then return false end
            if event == "ENCOUNTER_START" then
                env.deadMobs = {}
                env.mobs = Mobs()
                env.currentMobIndex = opt.startMob
                env.currentMob = env.mobs[env.currentMobIndex]
                env.lastMoveCount = 0
                allstates[""] = Bar(20, env.currentMob.name, 0)
                return true
            end
            if event == "WA_NUMEN_TIMER" then
                local key, time, count = ...
                if key ~= "4HM_MARK" or not count or not env.currentMob then return end
                if time > 0 then
                    -- the countdown carries the coming mark's number
                    count = count - 1
                    if count == opt.firstMark then
                        MoveOn(env, count)
                    elseif count > opt.firstMark then
                        if count - env.lastMoveCount >= opt.everyMark then MoveOn(env, count) end
                    end
                    local mob = env.currentMob.name
                    if env.deadMobs and env.deadMobs[env.currentMob.npcID] then mob = "Safe Zone" end
                    allstates[""] = Bar(time, mob, Stacks(env, env.currentMob.name))
                    return true
                end
            end
            if event == "COMBAT_LOG_EVENT_UNFILTERED" then
                local _, subEvent, _, _, _, _, _, destGUID, _, _, _, spellId, _, _, _, amount = ...
                if subEvent == "UNIT_DIED" then
                    local npc = Npc(destGUID)
                    for _, mob in pairs(env.mobs) do
                        if mob.npcID == npc then
                            env.deadMobs[npc] = true
                            local st = allstates[""]
                            if st and st.mob == mob.name then
                                st.mob = "Safe Zone"
                                st.changed = true
                                return true
                            end
                            break
                        end
                    end
                    return
                end
                if not env.mobsByMark[spellId] then return end
                if destGUID ~= WA.myGUID then return end
                if subEvent == "SPELL_AURA_APPLIED" then
                    env.marks[spellId] = 1
                elseif subEvent == "SPELL_AURA_APPLIED_DOSE" then
                    env.marks[spellId] = amount or (env.marks[spellId] + 1)
                elseif subEvent == "SPELL_AURA_REMOVED" then
                    env.marks[spellId] = 0
                end
                if env.currentMob and spellId == env.currentMob.markID then
                    local stacks = Stacks(env, env.currentMob.name)
                    local st = allstates[""]
                    if st and st.mark ~= stacks then
                        st.mark = stacks
                        st.changed = true
                        return true
                    end
                end
            end
        end,
    }
end

-- ============================================================
-- NAMEPLATES
-- ============================================================
local function NoteTables(env)
    env.durations = {}
    env.expirationTimes = {}
    env.sourceGUIDs = {}
end
B["N:[NX][Trash] Disarm"] = { ["init"] = NoteTables }
B["N:[NX][Trash] Disarm Missing"] = { ["init"] = NoteTables }
B["N:[NX][Trash] Enrage"] = K.PlateBuff{ npcs = { "16447", "16244" }, spells = { 24318 }, dur = 60, spellIcon = true }

-- Plague-wing captains' Whirlwind: a six second bar on the captain's
-- plate, and ten times a second whether you are out of its reach (5 yards)
do
    local WHIRLWIND, LASTS = 28334, 6
    local function Follow(env, unit, guid, secs)
        if not unit or env.tickers[unit] then return end
        local ends = GetTime() + secs
        env.tickers[unit] = C_Timer.NewTicker(1 / 10, function()
            if GetTime() > ends then
                if env.tickers[unit] then
                    env.tickers[unit]:Cancel()
                    env.tickers[unit] = nil
                end
                return
            end
            if UnitExists(unit) then
                local range = WA.GetRange(unit)
                RM.Fire("WA_TRASH_CAPTAIN_WW_UPDATE", guid, range and range >= 5)
            end
        end)
    end
    local function Bar(secs, ends, unit)
        return { show = true, changed = true, progressType = "timed", duration = secs, expirationTime = ends, autoHide = true, unit = unit }
    end
    B["N:[NX][Trash] Captain Whirlwind"] = {
        ["init"] = function(env)
            env.tickers = {}
            env.expirationTime = {}
            env.duration = {}
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "OPTIONS" then
                allstates[""] = Preview(5)
                return true
            end
            if event == "NAME_PLATE_UNIT_ADDED" then
                local unit = ...
                local guid = UnitGUID(unit)
                if not guid then return end
                local ends = env.expirationTime and env.expirationTime[guid]
                local secs = env.duration and env.duration[guid]
                if ends and secs and ends > GetTime() then
                    allstates[unit] = Bar(secs, ends, unit)
                    return true
                end
            end
            if event == "NAME_PLATE_UNIT_REMOVED" then
                local unit = ...
                K.Drop(allstates, unit)
                return true
            end
            if event == "COMBAT_LOG_EVENT_UNFILTERED" then
                local _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId = ...
                if subEvent == "SPELL_AURA_APPLIED" then
                    if spellId ~= WHIRLWIND then return false end
                    local ends = GetTime() + LASTS
                    env.duration[sourceGUID] = LASTS
                    env.expirationTime[sourceGUID] = ends
                    for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                        local unit = plate.UnitFrame and plate.UnitFrame.displayedUnit
                        local guid = unit and UnitGUID(unit)
                        if guid == sourceGUID then
                            allstates[unit] = Bar(LASTS, ends, unit)
                            Follow(env, unit, guid, LASTS)
                            return true
                        end
                    end
                elseif subEvent == "UNIT_DIED" then
                    env.duration[destGUID] = nil
                    env.expirationTime[destGUID] = nil
                    for unit, st in pairs(allstates) do
                        if UnitGUID(unit) == destGUID then
                            if env.tickers[unit] then
                                env.tickers[unit]:Cancel()
                                env.tickers[unit] = nil
                            end
                            st.show = false
                            st.changed = true
                        end
                    end
                    return true
                end
            end
            if event == "WA_TRASH_CAPTAIN_WW_UPDATE" then
                local guid, safe = ...
                for unit, st in pairs(allstates) do
                    if UnitGUID(unit) == guid and st.safe ~= safe then
                        st.safe = safe
                        st.changed = true
                        return true
                    end
                end
            end
        end,
    }
end

-- Razuvious: each student's taunt on Razuvious' plate, 20 seconds, one per
-- taunting player
do
    local RAZUVIOUS = "16061"
    local function Row(env, source, dest, unit)
        return { show = true, changed = true, progressType = "timed", duration = env.durations[source], expirationTime = env.expirationTimes[source],
            unit = unit, autoHide = true, icon = 136080, guid = source, targetGUID = dest }
    end
    B["N:[NX][Razuvious] Taunt"] = {
        ["init"] = function(env)
            env.destBySource = {}
            env.durations = {}
            env.expirationTimes = {}
            env.guids = {}
            env.npcID = RAZUVIOUS
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "WA_RAZUVIOUS_TAUNT_CAST" then
                local source, dest = ...
                if Npc(dest) == RAZUVIOUS then
                    env.expirationTimes[source] = GetTime() + 20
                    env.durations[source] = 20
                    env.destBySource[source] = dest
                    local unit = K.PlateFor(dest)
                    if unit then
                        allstates[source] = Row(env, source, dest, unit)
                        return true
                    end
                end
            end
            if event == "NAME_PLATE_UNIT_REMOVED" then
                local gone = UnitGUID((...))
                for source, dest in pairs(env.destBySource) do
                    if dest == gone and allstates[source] then K.Drop(allstates, source) end
                end
                return true
            end
            if event == "NAME_PLATE_UNIT_ADDED" then
                local unit = ...
                local back = UnitGUID(unit)
                for source, dest in pairs(env.destBySource) do
                    local ends = env.expirationTimes[source]
                    if dest == back and ends and ends - GetTime() > 0 then
                        allstates[source] = Row(env, source, dest, unit)
                    end
                end
                return true
            end
        end,
    }
end

-- Four Horsemen: Shield Wall's 20 seconds on the horseman's plate
B["N:[NX][4HM] Shield Wall"] = {
    ["init"] = function(env)
        env.durations = {}
        env.expirationTimes = {}
        env.guids = {}
    end,
    ["triggers.1.trigger"] = function(env, allstates, event, ...)
        local function Wall(guid, unit)
            return { show = true, changed = true, progressType = "timed", duration = env.durations[guid], expirationTime = env.expirationTimes[guid],
                unit = unit, autoHide = true, icon = 132362 }
        end
        if event == "WA_4HM_SHIELD_WALL_APPLIED" then
            local guid = ...
            env.expirationTimes[guid] = GetTime() + 20
            env.durations[guid] = 20
            local unit = K.PlateFor(guid)
            if unit then
                allstates[guid] = Wall(guid, unit)
                return true
            end
        end
        if event == "NAME_PLATE_UNIT_REMOVED" then
            K.Drop(allstates, UnitGUID((...)))
            return true
        end
        if event == "NAME_PLATE_UNIT_ADDED" then
            local unit = ...
            local guid = UnitGUID(unit)
            local ends = env.expirationTimes[guid]
            if ends and ends - GetTime() > 0 then allstates[guid] = Wall(guid, unit) end
            return true
        end
    end,
}

-- ============================================================
-- PROGRESS BARS
-- ============================================================
B["PC:[NX][Thaddius] Activates"] = Pop{ on = "WA_THADDIUS_P2_START", dur = 4, fields = { icon = BOSS_ICON.THADDIUS },
    sample = function() return Preview(4, { icon = BOSS_ICON.THADDIUS }) end }
B["PC:[NX][Thaddius] Polarity Shift"] = K.Merge(
    Pop{ on = "WA_NUMEN_TIMER", when = AtZero("THADDIUS_POLARITY_SHIFT"), dur = 3, sample = function() return Preview(3) end },
    { ["text"] = K.Field("addColour") })
B["PC:[NX][Sapphiron] Frost Bomb"] = K.Merge(
    Pop{ on = "WA_NUMEN_TIMER", when = AtZero("SAPPHIRON_FROST_BOMB"), dur = 7, sample = function() return Preview(7) end },
    { ["text"] = K.Field("addColour") })
-- Kel'Thuzad's Frostbolt cast, until it lands or is kicked
B["PC:[NX][Kel'Thuzad] Frostbolt"] = {
    ["text"] = K.Field("addColour"),
    ["triggers.1.trigger"] = function(env, allstates, event)
        if event == "OPTIONS" or event == "KT_FROSTBOLT_CAST_START" then
            allstates[""] = Preview(2)
            return true
        elseif event == "KT_FROSTBOLT_CAST_SUCCESS" or event == "KT_FROSTBOLT_INTERRUPT" then
            if allstates[""] then return K.Drop(allstates, "") end
        end
    end,
}
-- Sapphiron's Icebolts in the air, out of five
B["PT:[NX][Sapphiron] Icebolt Count"] = {
    ["triggers.1.trigger"] = function(env, allstates, event, guid, count)
        local function Bar(value) return { show = true, changed = true, progressType = "static", value = value, total = 5, autoHide = true } end
        if event == "OPTIONS" then
            allstates[""] = Bar(math.random(1, 6))
            return true
        end
        if event == "WA_SAPPHIRON_AIR_PHASE" then
            allstates[""] = Bar(0)
            return true
        end
        local st = allstates[""]
        if event == "WA_SAPPHIRON_ICEBOLT_TARGET" and st then
            st.value = count
            st.changed = true
            return true
        end
        if event == "WA_SAPPHIRON_FROST_BOMB" and st then return K.Drop(allstates, "") end
    end,
}

-- ============================================================
-- RAID FRAMES
-- ============================================================
local dispelMagic = LocalClass("Paladin", "Priest")
local curePoison = LocalClass("Paladin", "Druid", "Shaman")
local cureDisease = LocalClass("Paladin", "Priest", "Shaman")
local removeCurse = LocalClass("Mage", "Druid")
for _, id in ipairs({ "RF:[NX][Trash] Cone of Cold", "RF:[NX][Trash] Fear", "RF:[NX][Trash] Frost Nova", "RF:[NX][Trash] Polymorph", "RF:[NX][Noth] Cripple" }) do
    B[id] = { ["conditions.1.check.fn"] = dispelMagic }
end
for _, id in ipairs({ "RF:[NX][Trash] Poison Charge", "RF:[NX][Grand Widow] Poison Bolt Volley", "RF:[NX]Maexxna] Necrotic Poison" }) do
    B[id] = { ["conditions.1.check.fn"] = curePoison }
end
for _, id in ipairs({ "RF:[NX][Trash] Retching Plague", "RF:[NX][Heigan] Decrepit Fever" }) do
    B[id] = { ["conditions.1.check.fn"] = cureDisease }
end
for _, id in ipairs({ "RF:[NX][Trash] Veil of Shadow", "RF:[NX][Noth] Curse of the Plaguebringer", "RF:[NX][Sapphiron] Life Drain" }) do
    B[id] = { ["conditions.1.check.fn"] = removeCurse }
end
B["RF:[NX][Kel'Thuzad] Frost Blast"] = { ["conditions.1.check.fn"] = LeaderOrHealer }
-- Sapphiron's Blizzard ticking on someone: a one-second glow
do
    local glow = K.HitGlow{ spells = { 28547 } }
    B["RF:[NX][Sapphiron] Chill"] = {
        ["conditions.1.check.fn"] = LeaderOrHealer,
        ["init"] = function(env)
            env.SpellList = { [28547] = true }
            env.glowTime = 1
        end,
        ["triggers.1.trigger"] = function(env, status, event, ts, subEvent, ...)
            if subEvent ~= "SPELL_PERIODIC_DAMAGE" then return end
            return glow["triggers.1.trigger"](env, status, event, ts, subEvent, ...)
        end,
    }
end

-- ============================================================
-- SPECIAL ALERTS AND WARNINGS
-- ============================================================
local function VoidZone()
    return Pop{ on = "4HM_VOID_ZONE_CAST", dur = 3, args = function(guid) return { guid = guid } end,
        sample = function() return Preview(3, { guid = WA.myGUID }) end }
end
B["SA:[NX][4HM] Void Zone [Target]"] = VoidZone()
B["SA:[NX][4HM] Void Zone [No Target]"] = K.Merge(VoidZone(), { ["logic"] = function(env, t) return t[1] and not t[2] end })

-- ten seconds left on a berserk: the thirty-second warning schedules it
local function BerserkIn10(boss)
    local thirty, ten = "WA_" .. boss .. "_BERSERK_IN_30", "WA_" .. boss .. "_BERSERK_IN_10"
    return {
        ["triggers.1.trigger"] = function(env, e)
            if e == thirty then C_Timer.After(20, function() RM.Fire(ten) end) end
            return e == ten
        end,
    }
end
B["SA:[NX][Patchwerk] Berserk in 10"] = BerserkIn10("PATCHWERK")
B["SA:[NX][Thaddius] Berserk in 10"] = BerserkIn10("THADDIUS")

-- Heigan: "Lip" (the limited invulnerability potion) before the teleport
B["SA:[NX][Heigan] LIP Teleport Timer"] = {
    ["conditions.2.changes.2.value"] = function() SpeakSfx("Lip") end,
    ["logic"] = function(env, t) return (t[1] or t[2]) and (t[3] and t[4]) end,
    ["triggers.2.trigger"] = function(env, e) return e == "ENCOUNTER_START" end,
}
B["SA:[NX][Grobbulus][T] Slime Spray PreWarn"] = Heads{ key = "GROBBULUS_SLIME_SPRAY", on = "WA_GROBBULUS_SLIME_SPRAY_PREWARN", icon = 134437 }
-- your kick team is up; any other event takes it down (it was meant to be
-- only the cast landing or being kicked)
B["SA:[NX][Kel'Thuzad] Frostbolt Interrupt Alert"] = {
    ["triggers.1.trigger"] = function(env, a, e)
        if e == "WA_FJI_FROSTBOLT_ROTATE_ALERT" then
            a[""] = Preview(2)
            return true
        end
        if a[""] then return K.Drop(a, "") end
    end,
}
B["SA:[NX][Kel'Thuzad] Shadow Fissure"] = Pop{ on = "KT_SHADOW_FISSURE_CAST", dur = 3,
    args = function(guid) return { guid = guid, isMe = guid == WA.myGUID } end,
    sample = function() return Preview(3, { guid = WA.myGUID }) end }

B["SW:[NX][Anub] Locust Swarm PreWarn"] = K.Merge(SayOnShow("Swarm Soon"),
    Heads{ key = "ANUB_LOCUST_SWARM", on = "WA_ANUB_LOCUST_SWARM_PREWARN", icon = 136045, cancel = { "WA_ANUB_LOCUST_SWARM_PREWARN_CANCEL" } })
B["SW:[NX][Maexxna] Web Spray PreWarn"] = K.Merge(SayOnShow("Spray Soon"),
    Heads{ key = "MAEXXNA_WEB_SPRAY", on = "WA_MAEXXNA_WEB_SPRAY_PREWARN", icon = 136113, cancel = { "WA_MAEXXNA_WEB_SPRAY_PREWARN_CANCEL" } })
B["SW:[NX][Heigan] Dance PreWarn"] = K.Merge(SayOnShow("Dance Soon"),
    Heads{ key = "HEIGAN_DANCE", on = "WA_HEIGAN_DANCE_PREWARN", icon = 133564, cancel = { "WA_HEIGAN_DANCE_PREWARN_CANCEL" } })
B["SW:[NX][Razuvious] Disrupting Shout PreWarn"] = K.Merge(SayOnShow("Shout Soon"),
    Heads{ key = "RAZUVIOUS_DISRUPTING_SHOUT", on = "WA_RAZUVIOUS_DISRUPTING_SHOUT_PREWARN", icon = 132333, cancel = { "WA_RAZUVIOUS_DISRUPTING_SHOUT_PREWARN_CANCEL" } })
B["SW:[NX][Gothik] Phase 2 PreWarn"] = K.Merge(SayOnShow("Gothik Soon"),
    Heads{ key = "GOTHIK_PHASE_TWO", on = "WA_GOTHIK_PHASE_TWO_PREWARN", icon = BOSS_ICON.GOTHIK,
        cancel = { "WA_GOTHIK_PHASE_TWO_PREWARN_CANCEL", "WA_GOTHIK_P2_START" } })
-- the berserk heads-ups also start the ten-second warning
local function BerserkIn30(boss)
    return K.Merge({ ["actions.start.custom"] = function() RM.Fire("WA_" .. boss .. "_BERSERK_IN_30") end },
        Heads{ key = boss .. "_BERSERK", on = "WA_" .. boss .. "_BERSERK_PREWARN", icon = 136224, autoHide = true,
            cancel = { "WA_" .. boss .. "_BERSERK_PREWARN_CANCEL" } })
end
B["SW:[NX][Patchwerk] Berserk in 30"] = BerserkIn30("PATCHWERK")
B["SW:[NX][Thaddius] Berserk in 30"] = BerserkIn30("THADDIUS")
B["SW:[NX][Patchwerk] Berserk Warn"] = WentOff("PATCHWERK_BERSERK", 136224, true)
B["SW:[NX][Thaddius] Berserk Warn"] = WentOff("THADDIUS_BERSERK", 136224, true)

-- Necrotic Poison on the tank: the preview is put up but not counted
B["SW:[NX][Maexxna] Necrotic Poison"] = Pop{ on = "WA_ANUB_NECROTIC_APPLIED", dur = 3, fields = { icon = 132105, stacks = 1 },
    args = function(count, destGUID) return { name = destGUID } end, sampleQuiet = true,
    sample = function() return { show = true, icon = 132105, stacks = math.random(1, 4), name = WA.myGUID } end }
B["SW:[NX][Noth] Curse of the Plaguebringer"] = K.Merge(SayOnShow("Curse"), {
    -- how many have it (3 in the preview)
    ["text"] = function(env)
        local n = env.state.matchCount
        if n then return "|cFFFFF000" .. string.format(n) .. "|r" end
        return "|cFFFFF000" .. string.format(3) .. "|r"
    end,
})
B["SW:[NX][Noth] Blink"] = WentOff("NOTH_BLINK", 135736)
B["SW:[NX][Grobbulus] Poison Cloud"] = WentOff("GROBBULUS_POISON_CLOUD", 136006)
B["SW:[NX][Gluth] Terrifying Roar"] = WentOff("GLUTH_TERRIFYING_ROAR", 132111)
B["SW:[NX][Razuvious] Disrupting Shout"] = K.Merge(SayOnShow("Shout"), WentOff("RAZUVIOUS_DISRUPTING_SHOUT", 132333))
B["SW:[NX][Kel'Thuzad] Frost Blast"] = K.Merge(SayOnShow("Frost Blast"), WentOff("KT_FROST_BLAST", 135840))
-- healers: the horseman to move to
B["SW:[NX][4HM] Healer Move Helper"] = {
    ["triggers.1.icon"] = WARN_ICON,
    ["triggers.1.trigger"] = function(env, allstates, event, mob)
        if event == "OPTIONS" then
            allstates[""] = { show = true, changed = true, progressType = "timed", mob = string.upper("Thane") }
            return true
        end
        if event == "WA_FJI_4HM_HEALER_NEXT_MOB" then
            allstates[""] = { show = true, changed = true, duration = 3, expirationTime = GetTime() + 3, progressType = "timed",
                mob = string.upper(mob), autoHide = true }
            SpeakSfx("Move to " .. mob)
            return true
        end
    end,
}

-- ============================================================
-- TEXTS
-- ============================================================
B["T:[NX][Anub] Locust Swarm"] = K.Merge(SayOnShow("Swarm"), Burst("ANUB_LOCUST_SWARM", 136045), { ["triggers.1.icon"] = WARN_ICON })
B["T:[NX][Grand Widow] Widow's Embrace"] = K.Merge(SayOnShow("Boss Embrace"),
    Pop{ on = "WA_WIDOW_EMBRACE_SILENCED", dur = 3, fields = { icon = 135736 }, sample = function() return Preview(3, { icon = 135736 }) end })
B["T:[NX][Maexxna] Enrage"] = K.Merge(Burst("MAEXXNA_ENRAGE", 136224), { ["triggers.1.icon"] = WARN_ICON })
B["T:[NX][4HM] Marks"] = K.Merge(Burst("4HM_MARK", 136172), { ["triggers.1.icon"] = WARN_ICON })
-- the next phase at a health line: "30% | 33.34%" (the boss's health
-- when known)
local function PhaseLine(at, fallback)
    return {
        ["init"] = function(env) env.phasePush = at end,
        ["text"] = function(env)
            local hp = string.format("%.2f", env.state.percenthealth or fallback)
            return "|cFFFFFF00" .. env.phasePush .. "%|r" .. " | |cFF00FF00" .. hp .. "%|r"
        end,
    }
end
B["T:[NX][Maexxna] P2 Warn"] = PhaseLine(30, 33.34)
B["T:[NX][Kel'Thuzad] Adds Warn"] = K.Merge(SayOnShow("Adds Soon"), PhaseLine(40, 43.34))
B["T:[NX][Noth] Adds"] = WentOff("NOTH_ADDS", 136187)
B["T:[NX][Heigan] Dance"] = K.Merge(SayOnShow("Dance Floor"), WentOff("HEIGAN_DANCE", 133564))
B["T:[NX][Heigan] Decrepit Fever"] = K.Merge(WentOff("HEIGAN_DECREPIT_FEVER", 132100), {
    ["actions.start.custom"] = function()
        if _G.FJI_HEAL or UnitIsGroupLeader("player") then SpeakSfx("Fever") end
    end,
})
B["T:[NX][Loatheb] Remove Curse"] = K.Merge(WentOff("LOATHEB_REMOVE_CURSE", 135952), {
    ["actions.start.custom"] = function()
        if UnitClassBase("player") == "WARLOCK" then SpeakSfx("Curse Removed") end
    end,
})
B["T:[NX][Loatheb] Doom"] = K.Merge(SayOnShow("Doom"), WentOff("LOATHEB_DOOM", 136179))
-- a boss becoming active: a big name for a moment
local function Active(event, name, icon, dur)
    return Pop{ on = event, dur = dur, fields = { name = name, icon = icon }, sample = function() return Preview(3, { name = name, icon = icon }) end }
end
B["T:[NX][Gothik] Phase Start"] = K.Merge(SayOnShow("Gothik"), Active("WA_GOTHIK_P2_START", "GOTHIK ACTIVE", BOSS_ICON.GOTHIK, 2))
B["T:[NX][Kel'Thuzad] Phase 2"] = K.Merge(SayOnShow("Phase 2"), Active("WA_KT_P2_START", "PHASE 2 - KT ACTIVE", BOSS_ICON.KELTHUZAD, 3))
-- the horsemen's spells, shown when you are near enough (the unit
-- triggers) to care
local function NearHorseman(map)
    return K.Merge(map, { ["logic"] = function(env, t) return t[1] and (t[2] or t[3]) end })
end
B["T:[NX][4HM] Meteor"] = NearHorseman(K.Merge(SayOnShow("Meteor"), Burst("4HM_METEOR", 135808)))
B["T:[NX][4HM] Holy Wrath"] = NearHorseman(Burst("4HM_HOLY_WRATH", 136208))
B["T:[NX][4HM] Void Zone"] = NearHorseman(Pop{ on = "4HM_VOID_ZONE_CAST", dur = 3, fields = { icon = 132886 }, args = function(guid) return { guid = guid } end,
    sample = function() return Preview(3, { guid = WA.myGUID, icon = 132886 }) end })
-- someone else got Mutating Injection
B["T:[NX][Grobbulus] Mutating Injection"] = Pop{ on = "WA_GROBBULUS_MUTATING_INJECTION_APPLIED", dur = 3, fields = { icon = 136127 },
    when = function(guid) return guid ~= WA.myGUID end, args = function(guid, name) return { guid = guid, name = name } end,
    sampleQuiet = true, sample = function() return { show = true, icon = 136127, guid = WA.myGUID } end }
B["T:[NX][Grobbulus] Slime Spray"] = K.Merge(SayOnShow("Frontal"), WentOff("GROBBULUS_SLIME_SPRAY", 134437))

-- a stacking debuff on someone else (the tank swap call): one row per
-- player, 3.5 seconds, with their stacks
local function StacksOnOthers(spell, icon)
    local function Row(guid, stacks)
        return { show = true, changed = true, duration = 3.5, expirationTime = GetTime() + 3.5, progressType = "timed", icon = icon,
            autoHide = true, stacks = stacks, name = guid }
    end
    return {
        ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, _, _, _, destGUID, _, _, _, spellId, _, _, _, amount)
            if event == "OPTIONS" then
                allstates[""] = { show = true, icon = icon, stacks = math.random(1, 4), name = WA.myGUID }
            end
            if spellId ~= spell then return false end
            if destGUID == WA.myGUID then return false end
            if subEvent == "SPELL_AURA_APPLIED" then
                allstates[destGUID] = Row(destGUID, 1)
                return true
            elseif subEvent == "SPELL_AURA_APPLIED_DOSE" then
                allstates[destGUID] = Row(destGUID, amount)
                return true
            end
        end,
    }
end
B["T:[NX][Gluth] Mortal Wound"] = StacksOnOthers(28467, 132109)
-- who else has Detonate Mana
B["T:[NX][Kel'Thuzad] Detonate Mana"] = StacksOnOthers(27819, 136116)

B["T:[NX][Sapphiron] Phase"] = {
    ["conditions.1.changes.1.value"] = function() SpeakSfx("Air Phase") end,
    ["triggers.1.trigger"] = function(env, allstates, event)
        local icon = BOSS_ICON.SAPPHIRON
        local name = (event == "OPTIONS" or event == "WA_SAPPHIRON_AIR_PHASE") and "AIR PHASE"
            or event == "WA_SAPPHIRON_GROUND_PHASE" and "GROUND PHASE" or nil
        if not name then return end
        allstates[""] = Preview(2, { name = name, icon = icon })
        return true
    end,
}
B["T:[NX][Sapphiron] Life Drain"] = K.Merge(SayOnShow("Curse"), WentOff("SAPPHIRON_LIFE_DRAIN", 136169))
B["T:[NX][Sapphiron] Icebolt"] = Pop{ on = "WA_SAPPHIRON_ICEBOLT_TARGET", dur = 3, fields = { icon = 135852 },
    args = function(guid, count) return { guid = guid, count = count } end,
    sampleQuiet = true, sample = function() return { show = true, icon = 135852, guid = WA.myGUID, count = math.random(1, 10) } end }
B["T:[NX][Kel'Thuzad] Shadow Fissure"] = Pop{ on = "KT_SHADOW_FISSURE_CAST", dur = 3, fields = { icon = 136134 }, args = function(guid) return { guid = guid } end,
    sample = function() return Preview(3, { guid = WA.myGUID, icon = 136134 }) end }

-- the countdown going off, for the "targets" heading
local function TargetsTitle(key, icon, say)
    return K.Merge(SayOnShow(say), Pop{ on = "WA_NUMEN_TIMER", when = AtZero(key), dur = 3.5, fields = { icon = icon }, args = TheCount,
        sample = function() return { show = true, changed = true, icon = icon, count = math.random(1, 3) } end })
end
B["T:[NX][Maexxna] Web Wrap Targets"] = TargetsTitle("MAEXXNA_WEB_WRAP", 136113, "Wrap")
B["T:[NX][Kel'Thuzad] Chains of Kel'Thuzad Targets"] = TargetsTitle("KT_MIND_CONTROL", 132507, "MC")
-- and the players under it: one row each (named by GUID), all restarting
-- their 3.5 seconds together
local function TargetPlayers(event)
    return {
        ["triggers.1.trigger"] = function(env, allstates, e, guid)
            if e == "OPTIONS" then
                for i = 1, 2 do allstates[i] = { show = true, changed = true, name = WA.myGUID, index = i } end
                return true
            end
            if e ~= event then return false end
            if allstates[guid] then return false end
            allstates[guid] = { show = true, changed = true, duration = 3.5, progressType = "timed", name = guid, autoHide = true }
            for _, st in pairs(allstates) do
                st.changed = true
                st.expirationTime = GetTime() + 3.5
            end
            return true
        end,
    }
end
B["T:[NX][Maexxna] Web Wrap Players"] = TargetPlayers("WA_MAEXXNA_WRAP_TARGET")
B["T:[NX][Kel'Thuzad] Chains of Kel'Thuzad Players"] = TargetPlayers("WA_KT_MC_TARGET")

-- ============================================================
-- WING LOCATIONS
-- ============================================================
-- after a wing's last boss (and on walking in) every wing's location
-- marker shows for a minute
B["CT:[NX] Map Location Trigger"] = {
    ["triggers.1.trigger"] = function(env, a, e, encounterId, _, _, _, success)
        if e == "ENCOUNTER_END" and success == 1 then
            if encounterId == 1116 or encounterId == 1115 or encounterId == 1121 or encounterId == 1120 then RM.Fire("WA_FJI_LOCATION_FIRE") end
        elseif e == "WA_DELAYED_PLAYER_ENTERING_WORLD" then
            -- (not after a /reload deep in a wing)
            if not RM.pewReload then RM.Fire("WA_FJI_LOCATION_FIRE") end
        end
    end,
}
for _, wing in ipairs({ "Abomination", "Spider", "Plague", "Death Knight" }) do
    B["[NX] " .. wing .. " Wing Location"] = {
        ["triggers.1.trigger"] = function(env, a, e)
            if e == "WA_FJI_LOCATION_FIRE" or e == "OPTIONS" then
                a[""] = Preview(60)
                return true
            end
        end,
    }
end

-- ============================================================
-- THADDIUS: WHICH SIDE TO GO
-- ============================================================
-- The polarity piece's conditions fire WA_THADDIUS_DIRECTION: on the first
-- charge, the side set for it ("left" / "right"); after that "swap" each
-- time the charge flips.
do
    local function Charge(mine, other, option)
        return function(env)
            if not env.charge then
                local side = env.config.option[option]
                if side == 1 then
                    RM.Fire("WA_THADDIUS_DIRECTION", "left")
                elseif side == 2 then
                    RM.Fire("WA_THADDIUS_DIRECTION", "right")
                end
                env.charge = mine
            elseif env.charge == other then
                RM.Fire("WA_THADDIUS_DIRECTION", "swap")
                env.charge = mine
            end
        end
    end
    local Text = K.Field("charge")
    B["CT:[NX] Thaddius Polarity Shift"] = {
        ["init"] = function(env) env.charge = nil end,
        ["logic"] = FirstTrigger,
        ["text"] = Text,
        ["conditions.1.changes.1.value"] = Charge("pos", "neg", "positive"),
        ["conditions.2.changes.1.value"] = Charge("neg", "pos", "negative"),
        ["triggers.2.trigger"] = function(env, a, e)
            if FIGHT_OVER[e] or e == "ENCOUNTER_START" then env.charge = nil end
        end,
    }
    local function Side(side, say)
        local map = { ["text"] = Text, ["triggers.1.trigger"] = function(env, e, arg) return arg == side end }
        if say then map = K.Merge(map, SayOnShow(say)) end
        return map
    end
    B["[NX] Thaddius Swap"] = Side("swap")
    B["[NX] Thaddius Right"] = Side("right", "Right")
    B["[NX] Thaddius Left"] = Side("left", "Left")
end

-- ============================================================
-- KEL'THUZAD: ABILITY COOLDOWNS (Zac's own tracker)
-- ============================================================
-- One bar per phase two ability, started by his phase two yell: first the
-- time until it can come, then (the text) the time until the latest it
-- has ever come. A cast restarts only its own bar.
do
    local YELLS = K.Set{ "Pray for mercy!", "The end is upon you!", "Scream your dying breath!" }
    local function Spells()
        return {
            { spell = GetSpellInfo(27819) or "Detonate Mana", icon = 136116, startCD = 15 + 20, cooldown = 20,
                latestStart = 15 + 46.5, latest = 50.9 },
            { spell = GetSpellInfo(27810) or "Shadow Fissure", icon = 136134, category = 1152, categoryCD = 5, startCD = 15 + 10, cooldown = 10,
                latestStart = 15 + 38.4, latest = 42.1 },
            -- (2026-10-24: Chains comes 63-145 s after the last one)
            { spell = GetSpellInfo(28408) or "Chains of Kel'Thuzad", name = "Chains", icon = 132507, category = 1152, categoryCD = 0,
                startCD = 15 + 20, cooldown = 63, latestStart = 15 + 103.4, latest = 145.4 },
            { spell = GetSpellInfo(27808) or "Frost Blast", icon = 135840, category = 1152, categoryCD = 5, startCD = 15 + 30, cooldown = 30,
                latestStart = 15 + 92.7, latest = 82.4 },
            -- the volley (28479), not the tank Frostbolt that shares its name
            { spell = GetSpellInfo(28479) or "Frostbolt", name = "AOE FB", icon = 135846, category = 1152, categoryCD = 8, startCD = 15 + 16,
                cooldown = 16, latestStart = 15 + 85.9, latest = 63.1,
                check = function(t, event, ...)
                    local id = select(12, ...)
                    if id and id ~= 0 then return id == 28479 end
                    return not select(9, ...)
                end },
        }
    end
    B["Naxx - KT"] = {
        ["init"] = function(env)
            env.spells = Spells()
            env.lookup = {}
            for _, d in ipairs(env.spells) do
                env.lookup[d.spell] = env.lookup[d.spell] or {}
                tinsert(env.lookup[d.spell], d)
            end
        end,
        ["text"] = function(env, expirationTime)
            local st = env.state
            local latestAt = st and st.latestAt
            if not latestAt or (expirationTime and expirationTime > GetTime()) then return "" end
            local left = latestAt - GetTime()
            if left < 1 then return "Ready" end
            return format("within %ds", left)
        end,
        ["triggers.1.trigger"] = function(env, state, event, ...)
            if event == "CHAT_MSG_MONSTER_YELL" and YELLS[(...)] then event = "OPTIONS" end
            if event == "OPTIONS" then
                local now = GetTime() + 0.01
                for _, d in ipairs(env.spells) do
                    local wait = d.startCD or d.cooldown
                    state[d.name or d.spell] = { show = true, changed = true, icon = d.icon, progressType = "timed", expirationTime = now + wait,
                        duration = wait, latestAt = d.latestStart and (now + d.latestStart) or nil, name = d.name or d.spell,
                        index = d.category or 0, stacks = 0 }
                end
                return true
            end
            if (event == "ENCOUNTER_END" and ... == 1114) or event == "PLAYER_ALIVE" then
                HideAll(state)
                return true
            end
            if event == "COMBAT_LOG_EVENT_UNFILTERED" or event == "DEBUG_WA" then
                -- a death is nothing to redraw
                if select(2, ...) == "UNIT_DIED" then return false end
                local source = select(4, ...)
                if not source or not strfind(source, "Creature-") then return end
                local now = GetTime()
                local changed = false
                for _, d in ipairs(env.lookup[select(13, ...)] or {}) do
                    local t = state[d.name or d.spell]
                    if t and (not d.check or d.check(t, event, ...)) then
                        local wait = d.cooldown or d.categoryCD
                        changed = true
                        t.changed = true
                        t.expirationTime = now + wait
                        t.duration = wait
                        t.latestAt = d.latest and (now + d.latest) or nil
                    end
                end
                return changed
            end
        end,
    }
end

RM.Own.Finish("NX", B)
