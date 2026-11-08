-- Tutorial_Core - the first-run welcome, its bookkeeping, the "Getting
-- started" card on General > Overview, and the front doors to the quick
-- setup (Tutorial_Setup) and the guided tour (Tutorial_Tour).
-- Part of ZacUI; load order is set by the TOC (after the config pages and
-- the changelog, before Boot_Events).
--
-- FIRST RUN (2026-11-08). A fresh install (and the load after "Reset
-- ZacUI") now opens the combined first-time setup (Tutorial_Setup2: look,
-- parts, one reload) in the login queue instead of the welcome; the
-- welcome below is kept for a client where the setup did not load.
--
-- WHO SEES THE WELCOME. A fresh install only. Boot_Events notes at
-- ADDON_LOADED whether the client handed over any saved variables at all
-- (ns.freshInstall); this file reads that at PLAYER_LOGIN and writes the
-- answer down once, in ZacUIDB.tutorial:
--   fresh install    { fresh = true }               the welcome is offered
--   existing install { seen = true, existing = true } it never is
-- so an account that ran any earlier ZacUI never gets a popup, and the
-- decision is never made twice.
--
-- WHEN. A few seconds after login, never in combat, and in its turn in the
-- login popup queue (Core_Popups: the import offer and the look picker
-- first, what's new after it): a show that comes due in combat waits for
-- the fight to end, and a fight that starts while the welcome is up closes
-- it until the fight is over (not counted as an answer). "Take the tour" and "Quick setup" end it for good; "Not now"
-- (or the X, or Escape) asks again at the next login, at most MAX_SHOWS
-- logins in all; ticking "Don't show this again" ends it at once.
--
-- BOOKKEEPING, account-wide, outside every profile (Core_Profiles lists
-- what a profile holds; this key is not in it):
--   ZacUIDB.tutorial = { fresh, existing, seen, shows, step, tourDone, setupDone }
--
--   ns.Tutorial.StartTour()     open the settings window and walk it
--   ns.Tutorial.OpenSetup()     the quick setup window
--   ns.Tutorial.ShowWelcome()   the welcome, now
--   ns.Tutorial.Reset()         offer the welcome again at the next login
--   ns.TutorialCard(L)          the card General > Overview draws

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Print = ns.Print
local UI = ns.UI

local M, F = UI.M, UI.F

local T = {}
T.WELCOME_DELAY = 4    -- seconds after login
T.CALM_DELAY = 2       -- seconds after a fight ends
T.MAX_SHOWS = 3        -- logins the welcome is offered on, at most
T.live = setmetatable({}, { __mode = "v" })   -- frames of the page on screen

-- ============================================================
-- BOOKKEEPING
-- ============================================================
function T.DB()
    if type(ZacUIDB) ~= "table" then return {} end
    if type(ZacUIDB.tutorial) ~= "table" then ZacUIDB.tutorial = {} end
    return ZacUIDB.tutorial
end

local function InCombat()
    return (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end
T.InCombat = InCombat

-- The two other halves, looked up when used (they load after this file).
function T.StartTour()
    local Tour = ns.TutorialTour
    if not Tour then Print("The tour did not load.") return false end
    return Tour.Start()
end

function T.TourActive()
    local Tour = ns.TutorialTour
    return Tour and Tour.IsActive() or false
end

function T.OpenSetup()
    local Setup = ns.TutorialSetup
    if not Setup then Print("Quick setup did not load.") return false end
    return Setup.Open()
end

local function SetupShown()
    local Setup = ns.TutorialSetup
    return Setup and Setup.IsShown() or false
end

-- ============================================================
-- THE WELCOME
-- ============================================================
local welcome
local pending = false          -- a show is waiting (for the delay, or for calm)
local shownThisSession = false

local watch = CreateFrame("Frame")

local function Answer(how)
    local st = T.DB()
    st.seen = true
    welcome._zAnswered = how
    UI.CloseWindow(welcome)
end

local function BuildWelcome()
    local f = UI.Window("ZacUIWelcomeFrame", 460, 214, "Welcome to ZacUI")
    f:SetPoint("CENTER", 0, 90)

    local textW = 460 - 40
    local intro = UI.Font(f, F.LABEL, { width = textW,
        text = "ZacUI is one flat, dark look for the whole Classic interface: "
            .. "unit frames, bars, nameplates, bags, maps and more, each a part you can switch on or off." })
    intro:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -(f.headerHeight + 16))
    local more = UI.Font(f, F.DESC, { width = textW, cat = "text", key = "gray",
        text = "Take a short tour of the settings window, or pick a few basics now. "
            .. "Nothing changes unless you choose it." })
    more:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -8)

    f.dontShow = UI.Checkbox(f, "Don't show this again", false)
    f.dontShow:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 50)

    local notNow = UI.Button(f, "Not now", { width = 90,
        tooltip = "Closes this. It asks again at your next login.",
        onClick = function() UI.CloseWindow(f) end })
    notNow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
    local setup = UI.Button(f, "Quick setup", { width = 110,
        tooltip = "A few screens: the look, which parts are on, and the basics of your frames.",
        onClick = function()
            Answer("setup")
            T.OpenSetup()
        end })
    setup:SetPoint("RIGHT", notNow, "LEFT", -8, 0)
    local tour = UI.Button(f, "Take the tour", { width = 120,
        tooltip = "Opens the settings window and shows you around it.",
        onClick = function()
            Answer("tour")
            T.StartTour()
        end })
    tour:SetPoint("RIGHT", setup, "LEFT", -8, 0)
    tour:SetActive(true)
    f.tourButton, f.setupButton, f.notNowButton = tour, setup, notNow

    -- Closed any way at all. A fight hiding it is not an answer; an
    -- unanswered close is "not now", unless the box says never.
    f:HookScript("OnHide", function(self)
        watch:UnregisterEvent("PLAYER_REGEN_DISABLED")
        if self._zCombatHide then
            self._zCombatHide = nil
            return
        end
        if not self._zAnswered and self.dontShow:GetChecked() then
            T.DB().seen = true
        end
        self._zAnswered = nil
    end)
    welcome = f
    return f
end

-- Shows it now, whatever the bookkeeping says (the login path checks
-- that first). Returns true when it went up.
function T.ShowWelcome()
    if T.TourActive() or SetupShown() then return false end
    if InCombat() then
        pending = true
        watch:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    pending = false
    if not welcome then BuildWelcome() end
    welcome._zAnswered = nil
    welcome.dontShow:SetChecked(false)
    local st = T.DB()
    if not shownThisSession then
        shownThisSession = true
        st.shows = (tonumber(st.shows) or 0) + 1
        -- the last offer: whatever happens to it, it does not come back
        if st.shows >= T.MAX_SHOWS then st.seen = true end
    end
    watch:RegisterEvent("PLAYER_REGEN_DISABLED")
    UI.OpenWindow(welcome)
    return true
end

function T.HideWelcome()
    if welcome and welcome:IsShown() then UI.CloseWindow(welcome) end
end

function T.WelcomeFrame() return welcome end

-- the queue's show (Core_Popups): the welcome when it is still owed
local function QueueShow()
    if not pending then return nil end
    if welcome and welcome:IsShown() then return welcome end
    if T.ShowWelcome() then return welcome end
    return nil
end

local function TryShow()
    if not pending then return end
    -- the login queue orders it (after the import offer and the look
    -- picker, never in combat, never on top of another popup)
    if ns.Popups then
        ns.Popups.Want("welcome", QueueShow)
        return
    end
    if InCombat() then
        watch:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    -- a fresh install picks its look first (Config_Style's first-run
    -- popup): the welcome waits for it to close (T.ResumeWelcome), never
    -- stacks on it
    if ns.Look and ns.Look.HoldWelcome and ns.Look.HoldWelcome() then return end
    T.ShowWelcome()
end

-- the look popup closed without a reload: the welcome now, once it is calm
function T.ResumeWelcome()
    if pending then C_Timer.After(T.CALM_DELAY or 1, TryShow) end
end

watch:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- a fight started under it: out of the way now, back after
        if welcome and welcome:IsShown() then
            -- back in the queue first, at its place, for after the fight
            if ns.Popups then ns.Popups.Again("welcome") end
            welcome._zCombatHide = true
            if ns.StopAnim then ns.StopAnim(welcome) end
            welcome:Hide()
            pending = true
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pending then C_Timer.After(T.CALM_DELAY, TryShow) end
    end
end)

-- ============================================================
-- LOGIN
-- ============================================================
-- Stamps the bookkeeping the first time this build sees the DB, then
-- schedules the welcome when it is still owed. Returns true when it was
-- scheduled (for the tests).
T.SET_LINE = "You're set. /zui opens the settings, /zui setup runs the setup again."

function T.CheckOnLogin()
    if type(ZacUIDB) ~= "table" then return false end
    -- the load after the setup's "Apply and reload": one short line, said
    -- once the login popups are done (Core_Popups.Say), and nothing else
    local su = ZacUIDB.setup
    if type(su) == "table" and su.applied then
        su.applied = nil
        if ns.Popups then ns.Popups.Say(T.SET_LINE) elseif Print then Print(T.SET_LINE) end
    end
    local st = ZacUIDB.tutorial
    if type(st) ~= "table" then
        if ns.freshInstall then
            st = { fresh = true }
        else
            st = { seen = true, existing = true }
        end
        ZacUIDB.tutorial = st
    end
    if st.seen then return false end
    -- A fresh install, and the load after "Reset ZacUI" (ns.openSetupAfterReset):
    -- the first-time setup (Tutorial_Setup2: the look, the parts, one
    -- reload) opens by itself, in the welcome's place in the login queue.
    -- It has its own Skip and a tour pointer, so the welcome and the look
    -- popup are not shown as well. Marked seen when it actually opens, so
    -- a logout before then still owes it.
    if ns.TutorialSetup and ns.TutorialSetup.Open then
        local function Show()
            local ok = T.OpenSetup()
            if ok then T.DB().seen = true end
            return ok
        end
        if ns.Popups then
            -- while it is open the queue waits (Core_Popups asks Setup.Busy)
            ns.Popups.Want("setup", Show, { delay = T.WELCOME_DELAY })
            return true
        end
        local function Go()
            if InCombat() then C_Timer.After(2, Go) return end
            Show()
        end
        C_Timer.After(T.WELCOME_DELAY, Go)
        return true
    end
    -- (no setup loaded: the welcome, as before)
    pending = true
    if ns.Popups then
        ns.Popups.Want("welcome", QueueShow, { delay = T.WELCOME_DELAY })
    else
        C_Timer.After(T.WELCOME_DELAY, TryShow)
    end
    return true
end

-- Offer the welcome again at the next login (the General page and
-- /zui tour reset). The tour and setup flags go too.
function T.Reset()
    if type(ZacUIDB) ~= "table" then return end
    ZacUIDB.tutorial = { fresh = true }
    shownThisSession = false
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    local ok, err = pcall(T.CheckOnLogin)
    if not ok and Print then Print("tutorial: " .. tostring(err)) end
end)

-- ============================================================
-- THE CARD (General > Overview)
-- ============================================================
-- Drawn by the General page right under its header. Buttons only: a page
-- build must not write anything.
function ns.TutorialCard(L)
    local card = L:Card("Getting started")
    L:Desc("New here? The tour shows you around this window. Quick setup picks "
        .. "your look and the parts you want, then reloads once.")
    L:Gap(4)
    local tour = UI.Button(card, "Take the tour", { width = 120,
        tooltip = "Walks you around this window, one part at a time. /zui tour does the same.",
        onClick = function() T.StartTour() end })
    local setup = UI.Button(card, "Quick setup", { width = 110,
        tooltip = "Your look and which parts are on, in three steps, with one reload. /zui setup does the same.",
        onClick = function() T.OpenSetup() end })
    local again = UI.Button(card, "Show the setup at login", { width = 170,
        tooltip = "The first-time setup opens by itself at your next login.",
        onClick = function()
            T.Reset()
            Print("The setup will open at your next login.")
        end })
    L:Flow({ tour, setup, again })
    L:EndCard()
    -- the tour's last stop points at this card (weak: a rebuilt page's
    -- old card is garbage, not something to keep alive)
    if L.live then T.live.card = card end
    return card
end

-- shared with later ZacUI files
ns.Tutorial = T
