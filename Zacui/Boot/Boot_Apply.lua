-- Boot_Apply - module defaults, the login apply pass and live enabling.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local MODULE_ORDER = ns.MODULE_ORDER
local Modules = ns.Modules
local Print = ns.Print
local ZUI = ns.ZUI

-- ============================================================
-- DEFAULTS + BOOT + SLASH
-- ============================================================
-- Every module defaults ON. The old split (core on, expansion set
-- opt-in) was a development-era safety posture for destructive panel
-- skins; at maturity it just meant fresh installs and old persisted
-- DBs silently missed features - the same invisibility class as the
-- per-character bug. Anything a user turns off STAYS off: migrations
-- below only force the modules they explicitly list.
local DEFAULT_MODULES = {}
for _, m in ipairs(MODULE_ORDER) do
    DEFAULT_MODULES[m] = true
end
-- THE ONE EXCEPTION: the button tray (2026-11-08, Zac: "why is the minimap
-- icon hider on by default?"). Sweeping every other addon's minimap
-- button off the minimap surprises a new user who has never asked for
-- it, so a fresh install starts with it off. The nil-fill at
-- ADDON_LOADED only writes keys a save has never seen, so a save that
-- already has the tray on keeps it; no FORCE_DEFAULT_AT entry, on purpose.
DEFAULT_MODULES.tray = false

-- HUD modules allocate textures on secure frames - action buttons, unit
-- frames, the main bar. Doing that from a keypress in the middle of a
-- fight is the one way this addon could actually cost someone something,
-- so those three wait for the fight to end. Everything else is ordinary
-- windows and can run whenever.
-- spellbookwin builds secure spell buttons, which must be set up out of
-- combat.
local COMBAT_SENSITIVE = {
    bars = true, actionbars = true, unitframes = true, castbar = true,
    spellbookwin = true, talentswin = true,
    tradeskillwin = true, craftwin = true, paperdollwin = true,
    skillswin = true, reputationwin = true, honorwin = true,
    petpaperdollwin = true, battlefieldwin = true, macroswin = true,
    chartabswin = true,
    friendtabswin = true,
    mailtabswin = true,
}

local pending = {}
local combatWatch

local function RunModule(m)
    ZUI._ran = ZUI._ran or {}
    -- a module whose part (Zacui_Nameplates, say) is not loaded has no
    -- entry here; that is a tick box in the AddOns list, not a failure
    if not Modules[m] then return false end
    -- a skin or cover of the game's own UI stands down while its part wears
    -- a game look (Core_Look's Look.STOCK: the windows, chat, tooltips,
    -- minimap and loot rolls stay Blizzard's own). Latched per session, so
    -- this never undoes a skin live: the look changes only at a reload.
    if ns.Look and ns.Look.StandsDown and ns.Look.StandsDown(m) then
        ZUI._stock = ZUI._stock or {}
        ZUI._stock[m] = true
        return false
    end
    local ok, err = pcall(Modules[m])
    if ok then
        ZUI._ran[m] = true
        return true
    end
    Print("Module '" .. m .. "' failed: " .. tostring(err))
    return false
end

local function DrainPending()
    for m in pairs(pending) do
        pending[m] = nil
        if ZacUIDB.modules[m] and not ZUI._ran[m] then
            if RunModule(m) then Print(m .. " applied now that combat has ended.") end
        end
    end
end

local function Defer(m)
    pending[m] = true
    if not combatWatch then
        combatWatch = CreateFrame("Frame")
        combatWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
        combatWatch:SetScript("OnEvent", DrainPending)
    end
    Print(m .. " on - will apply when you leave combat.")
end

local function ApplyAll()
    ZUI._ran = ZUI._ran or {}
    for _, m in ipairs(MODULE_ORDER) do
        if ZacUIDB.modules[m] and Modules[m] then
            if COMBAT_SENSITIVE[m] and InCombatLockdown and InCombatLockdown() then
                Defer(m)
            else
                RunModule(m)
            end
        end
    end
end

-- Live enable for the config UI and the slash path: run the module NOW
-- if it hasn't run this session. Modules that already ran are skipped -
-- hooks and tickers must never be installed twice; their skins are
-- already on and the fences hold the rest.
local function EnableModuleLive(m)
    ZacUIDB.modules[m] = true
    ZUI._ran = ZUI._ran or {}
    if ZUI._ran[m] then
        Print(m .. " on.")
        return
    end
    if not Modules[m] then
        local part = ns.MODULE_ADDON and ns.MODULE_ADDON[m]
        Print(m .. " on - it will apply once " .. (part or "its addon") .. " is enabled in the AddOns list.")
        return
    end
    if ns.Look and ns.Look.StandsDown and ns.Look.StandsDown(m) then
        Print(m .. " on - it stays the game's own while that part wears a game look (Style page).")
        return
    end
    if COMBAT_SENSITIVE[m] and InCombatLockdown and InCombatLockdown() then
        Defer(m)
        return
    end
    if RunModule(m) then
        Print(m .. " on - applied live.")
    else
        -- (the reload question: UIF_Dialogs, loaded by the time anything is switched on)
        if ns.AskReload then ns.AskReload(m .. " is on, but could not start right away. A reload starts it.")
        else Print(m .. " on, but live apply failed - /reload.") end
    end
end


-- shared with later ZacUI files
ns.ApplyAll = ApplyAll
ns.DEFAULT_MODULES = DEFAULT_MODULES
ns.EnableModuleLive = EnableModuleLive
