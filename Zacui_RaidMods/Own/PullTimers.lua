-- PullTimers - ZacUI's own pull and break timers: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Settings in Own\PullTimers_Data.lua.
--
-- A pull bar (the game's own countdown, plus a catch-up for anyone who
-- reloads or zones in partway), a break bar (ours and DBM's addon
-- messages), a line saying who started which, and automatic combat
-- logging in instances.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
if not (RM and RM.Own and RM.Own.on) then return end
local K = RM.Own.Kit

local B = {}

-- the addon-message channels the timers listen on: the raid packs' own
-- (the name other raiders' clients send under), and DBM's
local OURS = "FojjiTimerAddon"
local DBM = { D5WC = true, D5C = true, D5 = true }
-- how long a break may be (seconds, exclusive) and how stale a pull may be
local MAX_BREAK, MAX_PULL = 6000, 600

-- The end times live in a shared saved table when there is one, so a
-- /reload picks the bar back up; without it they go nowhere.
local function Saved()
    return _G.FTSavedVars or {}
end

local function AskRaid(...)
    WA_SYNC_RESULT = (_G.SyncEvents or function() end)("RAID", ...)
end

-- a bar running for duration seconds
local function Bar(allstates, duration)
    K.Put(allstates, "", { progressType = "timed", duration = duration, expirationTime = GetTime() + duration, autoHide = true })
end

-- a bar's duration slot: the env's pullTime, if anything ever sets one
local function BarDuration(env)
    local secs = env.pullTime or 0
    if secs > 0 then return secs, GetTime() + secs end
    return secs, 0
end

-- ============================================================
-- WHO STARTED WHAT
-- ============================================================
do
    local KINDS = {
        WA_FOJJI_PULL_TIMER = { "Pull timer" },
        WA_FOJJI_DBM_PULL_TIMER = { "Pull timer", true },
        WA_FOJJI_BREAK_TIMER = { "Break timer" },
        WA_FOJJI_DBM_BREAK_TIMER = { "Break timer", true },
    }
    local function Line(allstates, secs, kind, who)
        K.Put(allstates, "", { duration = 2.5, expirationTime = GetTime() + 2.5, timerText = secs, timerType = kind,
            autoHide = true, icon = 132349, sender = who })
        return true
    end
    B["[TEXT] Fojji - Timer Text"] = {
        ["triggers.1.trigger"] = function(env, allstates, event, secs, who)
            if event == "OPTIONS" then return Line(allstates, 20, "Pull timer", UnitName("player")) end
            local kind = KINDS[event]
            if not kind then return end
            -- DBM sends full names; ours are short already
            if kind[2] then who = Ambiguate(who, "short") end
            return Line(allstates, secs, kind[1], who)
        end,
    }
end

-- ============================================================
-- BREAK BAR
-- ============================================================
do
    local function Show(allstates, duration)
        Bar(allstates, duration)
        Saved().breakEndTime = GetTime() + duration
        return true
    end
    local function Hide(allstates)
        allstates[""] = { show = false, changed = true }
        Saved().breakEndTime = nil
        return true
    end
    local function Fits(secs) return secs and secs > 0 and secs < MAX_BREAK end

    B["[BAR] Fojji Break Timer"] = {
        ["init"] = function()
            local prefixes, known = { OURS, "D5WC", "D5" }, {}
            for i, prefix in ipairs(prefixes) do known[i] = C_ChatInfo.IsAddonMessagePrefixRegistered(prefix) end
            for i, prefix in ipairs(prefixes) do
                if known[i] == false then C_ChatInfo.RegisterAddonMessagePrefix(prefix) end
            end
        end,
        ["triggers.1.duration"] = BarDuration,
        ["triggers.1.trigger"] = function(env, allstates, event, prefix, msg)
            if event == "STATUS" then
                local ends = Saved().breakEndTime
                if not (ends and ends > GetTime()) then return Hide(allstates) end
                local left = ends - GetTime()
                if left < MAX_BREAK then return Show(allstates, left) end
            end
            if event ~= "CHAT_MSG_ADDON" then return end
            if prefix == OURS then
                local cmd, value, who = strsplit(":", msg)
                local secs = tonumber(value)
                if cmd == "BREAK" or cmd == "BREAK_STATUS" or cmd == "BREAK_SYNC" then
                    if Fits(secs) then
                        -- only a fresh break says who started it
                        if cmd == "BREAK" then RM.WA.ScanEvents("WA_FOJJI_BREAK_TIMER", secs, who) end
                        return Show(allstates, secs)
                    elseif secs == 0 then
                        return Hide(allstates)
                    end
                elseif cmd == "BREAK_CANCEL" then
                    return Hide(allstates)
                end
            elseif DBM[prefix] then
                local who, _, cmd, value = strsplit("\t", msg)
                local secs = tonumber(value)
                if cmd ~= "BT" then return end
                if Fits(secs) then
                    RM.WA.ScanEvents("WA_FOJJI_DBM_BREAK_TIMER", secs, who)
                    return Show(allstates, secs)
                elseif secs == 0 then
                    return Hide(allstates)
                end
            end
        end,
    }
end

-- ============================================================
-- PULL BAR
-- ============================================================
-- The end time is kept in server time so it survives a relog; anyone
-- whose bar is missing asks the raid, and whoever has one answers with
-- the seconds left (at most one answer taken every three seconds).
do
    local function Show(allstates, duration)
        Bar(allstates, duration)
        Saved().pullEndTime = GetServerTime() + duration
        return true
    end
    local function Hide(allstates)
        allstates[""] = { show = false, changed = true }
        Saved().pullEndTime = nil
        return true
    end
    -- seconds left on the saved pull, when it is a sensible number
    local function Left()
        local ends = Saved().pullEndTime
        if not ends then return end
        local left = ends - GetServerTime()
        if left > 0 and left < MAX_PULL then return left end
        return false
    end

    B["[BAR] Fojji Pull Timer"] = {
        ["init"] = function(env)
            env.throttle = 0
            C_ChatInfo.IsAddonMessagePrefixRegistered(OURS)
        end,
        ["triggers.1.duration"] = BarDuration,
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "WA_DELAYED_PLAYER_ENTERING_WORLD" then
                -- a pull saved more than ten minutes either side of now is junk
                local ends = Saved().pullEndTime
                if ends and math.abs(ends - GetServerTime()) > MAX_PULL then
                    Saved().pullEndTime = nil
                end
            end
            if event == "STATUS" then
                if env.config.textEnable then TimerTracker:Show() else TimerTracker:Hide() end
                if not allstates[""] then AskRaid(nil, "WA_FOJJI_PULL_TIMER_CHECK") end
                local left = Left()
                if left then return Show(allstates, left) end
                return Hide(allstates)
            end
            if event == "WA_FOJJI_PULL_TIMER_CHECK" then
                local left = Left()
                if left then
                    AskRaid(nil, "WA_FOJJI_PULL_TIMER_SEND", left)
                elseif left == false then
                    Saved().pullEndTime = nil
                end
            end
            if event == "WA_FOJJI_PULL_TIMER_SEND" then
                if GetTime() - (env.throttle or 0) < 3 then return false end
                env.throttle = GetTime()
                if allstates[""] then return false end
                local secs = tonumber((...)) or 0
                if secs <= 0 or secs > MAX_PULL then return false end
                Show(allstates, secs)
                return true
            end
            if event == "START_PLAYER_COUNTDOWN" then
                local guid, secs = ...
                local name = select(6, GetPlayerInfoByGUID(guid))
                RM.WA.ScanEvents("WA_FOJJI_PULL_TIMER", secs, name)
                Show(allstates, secs)
                return true
            elseif event == "CANCEL_PLAYER_COUNTDOWN" then
                Hide(allstates)
                return true
            end
        end,
    }
end

-- ============================================================
-- COMBAT LOG
-- ============================================================
-- with the option on, the log runs while the piece is showing (inside a
-- dungeon or raid) and stops when it goes
local function LogWhile(on)
    return function(env)
        if env.config.combatLogEnable then LoggingCombat(on) end
    end
end
B["Fojji - AutoCombatLog"] = {
    ["actions.start.custom"] = LogWhile(true),
    ["actions.finish.custom"] = LogWhile(false),
}

RM.Own.Finish("PullTimers", B)
