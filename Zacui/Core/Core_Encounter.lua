-- Core_Encounter - the one boss pull/encounter tracker for every ZacUI part.
-- Part of ZacUI; load order is set by the TOC (after Core_Services, whose
-- ns.Roster it reads).
-- ============================================================
-- WHY. Five features each watched ENCOUNTER_START/END on their own (the
-- raid mods' load rules, the meter's boss segments, the Razuvious alert,
-- the hesitation log and the boss particle levels), and only the raid
-- mods knew what to do when ENCOUNTER_END never comes (a wipe the client
-- misses, a boss that resets): the meter's boss segment, the particle
-- level and the Razuvious watch could think a fight was still running
-- that the raid mods had already unloaded. One tracker now answers "is
-- a boss up" for all of them, and two different "is anyone in my group
-- still fighting" checks became one.
--
--   ns.Encounter.Active()         true while a boss encounter is running
--   ns.Encounter.Info()           id, name, difficulty, size, startTime
--                                 (GetTime) of that encounter, or nil
--   ns.Encounter.GroupInCombat()  true while the player or anyone in the
--                                 group (ns.Roster) is still in combat
--   ns.Encounter.On(key, fn)      fn(event, id, name, difficulty, size,
--                                 success); nil fn removes. Events:
--     "start"  ENCOUNTER_START
--     "end"    every ENCOUNTER_END, success 1 (kill) or 0 (wipe) - also
--              one with no start seen (after a /reload mid-fight)
--     "reset"  the encounter ended without an ENCOUNTER_END: after a
--              death, a resurrection or leaving combat the tracker waits
--              3 s, then looks every 2 s, up to five times, for the whole
--              group being out of combat (the raid packs' "Global
--              Encounter Bug Fix", which the raid mods always ran).
--              success is nil; treat it as a wipe.
-- The state is already updated when listeners run: during "end" and
-- "reset" Active() is false; the arguments still describe the fight.
-- PLAYER_ENTERING_WORLD (login, /reload, any loading screen) forgets a
-- running encounter quietly - nothing re-fires ENCOUNTER_START after a
-- reload, so each part re-baselines on that event itself as before.
-- Listeners run inside pcall, like the Core_Services listeners.
-- ============================================================

local ADDON_NAME, ns = ...

local pairs, pcall = pairs, pcall
local GetTime, UnitAffectingCombat, InCombatLockdown = GetTime, UnitAffectingCombat, InCombatLockdown
local C_Timer = C_Timer
local Roster = ns.Roster

local E = {}
ns.Encounter = E

local cur = nil          -- { id, name, difficulty, size, start } while a boss is up
local listeners = {}     -- key -> fn; replaced (never edited) on change

local function Notify(event, id, name, difficulty, size, success)
    for _, fn in pairs(listeners) do
        local ok, err = pcall(fn, event, id, name, difficulty, size, success)
        if not ok then
            local h = geterrorhandler and geterrorhandler()
            if h then h(err) end
        end
    end
end

function E.Active() return cur ~= nil end

function E.Info()
    if not cur then return nil end
    return cur.id, cur.name, cur.difficulty, cur.size, cur.start
end

function E.GroupInCombat()
    if UnitAffectingCombat("player") or InCombatLockdown() then return true end
    local units = Roster.Units()
    for i = 1, #units do
        if UnitAffectingCombat(units[i]) then return true end
    end
    return false
end

-- A new table on every change, so a listener may call On from inside a
-- dispatch safely.
function E.On(key, fn)
    local t = {}
    for k, f in pairs(listeners) do t[k] = f end
    t[key] = fn
    listeners = t
end

------------------------------------------------------------------------
-- The "did it really end" check
------------------------------------------------------------------------
local endTimer, endTicker
local function CancelEndCheck()
    if endTicker then endTicker:Cancel() endTicker = nil end
    if endTimer then endTimer:Cancel() endTimer = nil end
end

local function Reset()
    CancelEndCheck()
    local c = cur
    if not c then return end
    cur = nil
    Notify("reset", c.id, c.name, c.difficulty, c.size, nil)
end

local function ScheduleEndCheck()
    if endTicker or endTimer then return end
    endTimer = C_Timer.NewTimer(3, function()
        endTimer = nil
        local tries = 0
        endTicker = C_Timer.NewTicker(2, function()
            tries = tries + 1
            if not E.GroupInCombat() then
                Reset()
            elseif tries >= 5 then
                -- the ticker's last run: the next death, resurrection
                -- or combat drop may look again
                endTicker = nil
            end
        end, 5)
        ns.Profiler.TrackTicker(endTicker, "Encounter.endCheck")
    end)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- ENCOUNTER_START/END: encounterID, encounterName, difficultyID, groupSize[, success]
frame:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
    if event == "ENCOUNTER_START" then
        CancelEndCheck()
        cur = { id = a1, name = a2, difficulty = a3, size = a4, start = GetTime() }
        Notify("start", a1, a2, a3, a4, nil)
    elseif event == "ENCOUNTER_END" then
        CancelEndCheck()
        cur = nil
        Notify("end", a1, a2, a3, a4, a5)
    elseif event == "PLAYER_REGEN_DISABLED" then
        CancelEndCheck()
    elseif event == "PLAYER_ENTERING_WORLD" then
        CancelEndCheck()
        cur = nil
    elseif cur then
        -- PLAYER_REGEN_ENABLED, PLAYER_DEAD, PLAYER_ALIVE
        ScheduleEndCheck()
    end
end)
