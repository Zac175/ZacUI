-- Core_FlavorRaids - each game version's raids, as far as more than one
-- part of ZacUI needs them: which kill ends a raid (the raid clear timer
-- on the raid chat strip, the raid summary after the last boss), and
-- whether the game's own lockout says every boss in this raid is down.
-- Part of ZacUI; load order is set by the TOC (after Core_Flavor and
-- Core_Encounter).
--
--   ns.RaidLastBoss(id, name)  true when this kill ends a raid of THIS
--                              game version beyond Classic Era's (the
--                              callers keep their own Classic Era lists,
--                              which stay as they were: Molten Core and
--                              the rest are still there on TBC)
--   ns.RaidEndsByLockout()     true on a game whose raids are not listed
--                              (Forever): a raid is over when the lockout
--                              says every boss is down
--   ns.RaidCleared()           the lockout of the raid you are in: true
--                              when every boss is down
--   ns.WhenRaidCleared(key, fn)  asks the game for the lockout once and
--                              calls fn() if it then says every boss is
--                              down (one answer, then it lets go)
--
-- Classic Era: nothing here answers yes, so the timer and the summary run
-- exactly as before.

local ADDON_NAME, ns = ...

-- ============================================================
-- THE LAST BOSSES, PER GAME VERSION
-- ============================================================
-- TBC Anniversary. Encounter ids are ENCOUNTER_END's first argument, from
-- warcraft.wiki.gg's DungeonEncounterID list (the same ids Readycheck's
-- TBC raid configs carry; see zui_tests/raids/TBC_RAIDS.md). Zul'jin's
-- TBC encounter id is not on that list (null), so Zul'Aman ends by the
-- boss's name. Names are the fallback for a client that reports another
-- id. Karazhan ends at Prince Malchezaar: Nightbane is the optional one.
local LAST = {
    tbc = {
        ids = {
            [661] = true,   -- Prince Malchezaar (Karazhan)
            [650] = true,   -- Gruul the Dragonkiller (Gruul's Lair)
            [651] = true,   -- Magtheridon (Magtheridon's Lair)
            [628] = true,   -- Lady Vashj (Serpentshrine Cavern)
            [733] = true,   -- Kael'thas Sunstrider (Tempest Keep)
            [622] = true,   -- Archimonde (Hyjal Summit)
            [609] = true,   -- Illidan Stormrage (Black Temple)
            [729] = true,   -- Kil'jaeden (Sunwell Plateau)
        },
        names = {
            ["Prince Malchezaar"] = true, ["Gruul the Dragonkiller"] = true, ["Magtheridon"] = true,
            ["Lady Vashj"] = true, ["Kael'thas Sunstrider"] = true, ["Archimonde"] = true,
            ["Illidan Stormrage"] = true, ["Zul'jin"] = true, ["Kil'jaeden"] = true,
        },
    },
    -- Forever: its raids (Barrow Deeps, its own Hyjal Summit, Onyxia's
    -- Lair) are not out yet and their last bosses are not known; it ends
    -- a raid by the lockout instead (BY_LOCKOUT below)
}
ns.RAID_LAST_BOSSES = LAST

local BY_LOCKOUT = { forever = true }

function ns.RaidLastBoss(id, name)
    local t = LAST[ns.Flavor and ns.Flavor() or "era"]
    if not t then return false end
    if id and t.ids[id] then return true end
    if name and t.names[name] then return true end
    return false
end

function ns.RaidEndsByLockout()
    return BY_LOCKOUT[ns.Flavor and ns.Flavor() or "era"] == true
end

-- ============================================================
-- THE LOCKOUT
-- ============================================================
-- GetInstanceLockTimeRemaining: the lock of the instance you are in, with
-- how many of its bosses there are and how many are down. A client that
-- lacks it (or a raid with no lock yet) answers no, and the callers fall
-- back to what they did before (the timer's four hours).
function ns.RaidCleared()
    if not GetInstanceLockTimeRemaining then return false end
    local _, kind = IsInInstance()
    if kind ~= "raid" then return false end
    local ok, _, _, total, done = pcall(GetInstanceLockTimeRemaining)
    if not ok or type(total) ~= "number" or type(done) ~= "number" then return false end
    return total > 0 and done >= total
end

-- The lockout counts are the server's and come a moment after a kill:
-- ask (RequestRaidInfo) and read on the answer (UPDATE_INSTANCE_INFO),
-- once. Nothing listens while nobody is waiting.
local waiting = {}
local lockFrame = CreateFrame("Frame")
local giveUp
-- an answer that still has a boss up keeps waiting (another addon's
-- request can answer first, before the kill counts); the last chance is
-- when the wait runs out
local function Settle(final)
    local cleared = ns.RaidCleared()
    if not (cleared or final) then return end
    lockFrame:UnregisterEvent("UPDATE_INSTANCE_INFO")
    if giveUp then giveUp:Cancel() giveUp = nil end
    local fns = waiting
    waiting = {}
    if not cleared then return end
    for _, fn in pairs(fns) do pcall(fn) end
end
lockFrame:SetScript("OnEvent", function() Settle(false) end)

function ns.WhenRaidCleared(key, fn)
    if type(fn) ~= "function" then return end
    if not (RequestRaidInfo and GetInstanceLockTimeRemaining) then return end
    waiting[key or fn] = fn
    lockFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
    if giveUp then giveUp:Cancel() end
    giveUp = C_Timer.NewTimer(15, function() giveUp = nil Settle(true) end)
    -- a Lua function, not RequestRaidInfo itself: C_Timer.After refuses a
    -- C function as the callback on this client
    C_Timer.After(2, function() if RequestRaidInfo then RequestRaidInfo() end end)
end
