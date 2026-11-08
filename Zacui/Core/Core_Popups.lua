-- Core_Popups - one login popup at a time.
-- Part of ZacUI; load order is set by the TOC (after Core_Boot, before
-- everything that puts a popup up at login).
--
-- THE PROBLEM. At login several things want the screen: the offer to
-- adopt another addon's settings, the look picker, the welcome (or the
-- setup after "Reset ZacUI"), what's new after an update, the parts that
-- are older than the core. Each used to pick its own moment, so two could
-- be up within seconds of each other on the very first screen.
--
-- THE RULE. Each one asks the queue instead. The queue shows them in a
-- fixed order, one at a time: the next waits until the one before has
-- closed (and a breath after). None goes up in combat; one due in a fight
-- waits for the fight to end. While the setup or the tour is open (from
-- the welcome, or after a reset) the queue waits for that too. Chat lines a part wants to
-- say at login wait until the popups are done, so they are not lost
-- under one.
--
--   ns.Popups.Want(key, show, opts)
--        show() puts the popup up and returns its frame (the queue waits
--        for that frame to hide), true (up, and something else - the setup,
--        the tour - holds the queue while it is open), or nil (nothing to
--        show after all: the next one goes). opts.delay = seconds after
--        the ask before it may show; opts.order overrides ORDER[key].
--        Asking again for a key already waiting only updates it.
--   ns.Popups.Again(key)   the popup is being put away for a fight: show it
--                          again once it is calm (call before hiding it)
--   ns.Popups.Hold(frame)  something the player opened from a popup (the
--                          reload question): the queue waits for it too
--   ns.Popups.Busy()       a popup is up, held or waiting
--   ns.Popups.Say(text)    a login chat line: now, or after the popups
--   ns.Popups.Cancel(key)  drop one that has not shown yet
--
-- Nothing is made at load: the one event frame (the wait for the end of a
-- fight) is made the first time a popup comes due in combat.

local ADDON_NAME, ns = ...

local pairs, next, type, pcall = pairs, next, type, pcall

local Q = {}
Q.GAP = 1        -- seconds between one closing and the next showing
Q.CALM = 2       -- seconds after a fight ends
Q.BLOCKED = 1    -- seconds between two looks while something holds the queue

-- the order, lowest first. The welcome and the setup after a reset are
-- never both owed (Tutorial_Core).
Q.ORDER = {
    reload    = 0,    -- a reload question raised by one of these
    import    = 10,   -- adopt another addon's settings (Config_Import)
    look      = 20,   -- the look picker, fresh installs (Config_Style)
    welcome   = 30,   -- the welcome (Tutorial_Core)
    setup     = 30,   -- the setup, after "Reset ZacUI" (Tutorial_Core)
    changelog = 40,   -- what's new after an update (Changelog)
    parts     = 50,   -- parts older than the core (Core_VersionCheck)
}

local items = {}                                   -- key -> waiting item
local current                                      -- the item up now
local held = setmetatable({}, { __mode = "k" })    -- frames that hold it
local hooked = setmetatable({}, { __mode = "k" })  -- frames with our OnHide
local lines = {}                                   -- chat lines waiting
local seq = 0
local pumpAt
local calmFrame

local function Now() return (GetTime and GetTime()) or 0 end

local function InCombat()
    return (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

-- something the player is in the middle of: the queue does not talk over it
local function Blocked()
    local Setup = ns.TutorialSetup
    if Setup then
        if Setup.Busy then
            if Setup.Busy() then return true end
        elseif Setup.IsShown and Setup.IsShown() then
            return true
        end
    end
    local Tour = ns.TutorialTour
    if Tour and Tour.IsActive and Tour.IsActive() then return true end
    return false
end
Q.Blocked = Blocked

local Pump

local function Schedule(d)
    d = d or 0
    local at = Now() + d
    -- an earlier pump already on its way covers this one
    if pumpAt and pumpAt <= at + 0.001 and pumpAt >= Now() - 0.001 then return end
    pumpAt = at
    if C_Timer and C_Timer.After then
        C_Timer.After(d, function()
            if pumpAt == at then
                pumpAt = nil
                Pump()
            end
        end)
    end
end

local function WaitForCalm()
    if not calmFrame then
        calmFrame = CreateFrame("Frame")
        calmFrame:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            pumpAt = nil
            Schedule(Q.CALM)
        end)
    end
    calmFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function Flush()
    if #lines == 0 then return end
    local Print = ns.Print
    local out = lines
    lines = {}
    for _, text in ipairs(out) do
        if Print then Print(text) elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(text) end
    end
end

local function OnHidden(f)
    if current and current.frame == f then
        local it = current
        current = nil
        if it.again then
            -- put away for a fight: back in line, first, once it is calm
            it.again, it.frame = nil, nil
            it.readyAt = Now()
            items[it.key] = it
        end
        Schedule(Q.GAP)
    end
    if held[f] then
        held[f] = nil
        Schedule(Q.GAP)
    end
end

local function Hook(f)
    if hooked[f] or not (f and f.HookScript) then return end
    hooked[f] = true
    f:HookScript("OnHide", OnHidden)
end

local function Next()
    local best
    for _, it in pairs(items) do
        if not best or it.order < best.order or (it.order == best.order and it.seq < best.seq) then
            best = it
        end
    end
    return best
end

Pump = function()
    if current then
        -- a popup that went away without its OnHide (torn down, reparented)
        local f = current.frame
        if f and f.IsShown and f:IsShown() then return end
        current = nil
    end
    for f in pairs(held) do
        if f.IsShown and f:IsShown() then return end
        held[f] = nil
    end
    local it = Next()
    if not it then Flush() return end
    local wait = it.readyAt - Now()
    if wait > 0.001 then Schedule(wait) return end
    if InCombat() then WaitForCalm() return end
    if Blocked() then Schedule(Q.BLOCKED) return end
    items[it.key] = nil
    local ok, res = pcall(it.show)
    if ok and type(res) == "table" and res.IsShown and res:IsShown() then
        current = it
        it.frame = res
        Hook(res)
        return
    end
    if not ok and ns.Print then ns.Print("popup " .. tostring(it.key) .. ": " .. tostring(res)) end
    -- nothing went up (or something else holds the queue now): the next
    -- one, after a breath; Blocked() keeps it waiting while that is open
    Schedule(Q.GAP)
end

function Q.Want(key, show, opts)
    if type(show) ~= "function" then return false end
    opts = opts or {}
    local it = items[key]
    if not it then
        seq = seq + 1
        it = { key = key, seq = seq }
        items[key] = it
    end
    it.show = show
    it.order = opts.order or Q.ORDER[key] or 100
    it.readyAt = Now() + (opts.delay or 0)
    Schedule(opts.delay or 0)
    return true
end

function Q.Cancel(key)
    items[key] = nil
end

function Q.Again(key)
    if current and current.key == key then current.again = true end
end

function Q.Hold(f)
    if not (f and f.IsShown) then return end
    held[f] = true
    Hook(f)
end

function Q.Busy()
    if current or next(items) ~= nil then return true end
    for f in pairs(held) do
        if f.IsShown and f:IsShown() then return true end
    end
    return false
end

-- the key of the popup up now (nil when none): for the tests and /zui debug
function Q.Current() return current and current.key or nil end
function Q.Waiting(key) return items[key] ~= nil end

function Q.Say(text)
    if type(text) ~= "string" then return end
    if Q.Busy() then
        lines[#lines + 1] = text
        return
    end
    if ns.Print then ns.Print(text) end
end

-- shared with later ZacUI files and the parts
ns.Popups = Q
