-- QoL_Core - the quality-of-life module: ZacUI's native Leatrix Plus.
-- Settings, the cvar features, the sound mutes, and the module entry
-- point. The event automation lives in QoL_Automation.lua.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT THIS IS. Zac ran Leatrix Plus with 11 features actually enabled
-- (the other 220 keys in his SavedVariables were inert defaults under
-- parents that were off - audited against the source, not assumed).
-- Those 11 are rebuilt here natively, behavior-identical, and they now
-- run on BOTH clients - the Leatrix Era build refuses to load on 2.5
-- (`gametocversion > 19999` early return), so TBC gains them for free:
--   AutomateGossip, AutoSellJunk(+summary), AutoRepairGear(+summary),
--   InviteFromWhisper("inv"), FriendlyGuild, FasterLooting,
--   NoScreenGlow, NoScreenEffects, StandAndDismount(+3 children),
--   MuteGameSounds(7 children), MuteMountSounds(2 children)
-- CVAR HONESTY: ffxGlow/ffxDeath/ffxNether persist in the client
-- config. Toggling the option off here restores them to "1", the same
-- contract Leatrix kept.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Modules = ns.Modules
local Print = ns.Print
local QoL = ns.QoL

-- ============================================================
-- SETTINGS - seeded from his live Leatrix config.
-- ============================================================
local function DB()
    ZacUIDB.qol = ZacUIDB.qol or {}
    local d = ZacUIDB.qol
    if not d._rev or d._rev < 1 then
        wipe(d)
        d._rev = 1
        d.gossip = true                -- AutomateGossip
        d.sellJunk = true              -- AutoSellJunk
        d.sellSummary = true           -- AutoSellShowSummary
        d.sellExclude = ""             -- AutoSellExcludeList (his was empty)
        d.repair = true                -- AutoRepairGear
        d.repairSummary = true         -- AutoRepairShowSummary
        d.fasterLoot = true            -- FasterLooting
        d.invite = true                -- InviteFromWhisper
        d.inviteKey = "inv"            -- InvKey
        d.inviteFriendsOnly = false    -- InviteFriendsOnly (off = anyone)
        d.friendlyGuild = true         -- FriendlyGuild
        d.dismount = true              -- StandAndDismount
        d.dismountNoResource = true    -- DismountNoResource
        d.dismountNoMoving = true      -- DismountNoMoving
        d.dismountNoTaxi = true        -- DismountNoTaxi
        d.noScreenGlow = true          -- NoScreenGlow  (ffxGlow 0)
        d.noScreenEffects = true       -- NoScreenEffects (ffxDeath/ffxNether 0)
        d.muteGame = {                 -- MuteGameSounds + his children
            enabled = true,
            MuteChimes = true, MuteFizzle = true, MuteInterface = true,
            MuteLogin = true, MuteTrains = true, MuteScreech = true,
            MuteYawns = true, MuteReady = false, MutePiccolo = false,
        }
        d.muteMount = {                -- MuteMountSounds + his children
            enabled = true,
            MuteMechSteps = true, MuteStriders = true, MuteHorsesteps = false,
        }
    end
    return d
end
QoL.DB = DB

-- ============================================================
-- SCREEN CVARS - applied live, restored on toggle-off, exactly the
-- Leatrix contract. Guarded pcall: a build without one of these cvars
-- just skips it.
-- ============================================================
local function ApplyScreenCvars()
    local d = DB()
    -- SETUP2: through ns.CVar (recorded; put back when Quality of life is off)
    local function Set(name, value)
        if ns.CVar then ns.CVar.Set(name, value, "qol") else pcall(SetCVar, name, value) end
    end
    Set("ffxGlow", d.noScreenGlow and "0" or "1")
    Set("ffxDeath", d.noScreenEffects and "0" or "1")
    Set("ffxNether", d.noScreenEffects and "0" or "1")
end
QoL.ApplyScreenCvars = ApplyScreenCvars

-- Red error text in the middle of the screen ("You are too far away!",
-- "Not enough rage", "Spell is not ready yet"): the error frame stops
-- listening for it. Yellow info lines (quest progress and the like) come
-- on another event and stay. Only re-armed if this is what took it away,
-- so another addon that hides it too is left alone.
local errorsHidden = false
local function ApplyErrorText()
    local f = UIErrorsFrame
    if not f then return end
    if DB().noErrorText then
        if not errorsHidden then
            f:UnregisterEvent("UI_ERROR_MESSAGE")
            errorsHidden = true
        end
    elseif errorsHidden then
        f:RegisterEvent("UI_ERROR_MESSAGE")
        errorsHidden = false
    end
end

-- ============================================================
-- SOUND MUTES - MuteSoundFile per fileDataID. Re-run in full on any
-- toggle: enabled sets mute, everything else unmutes, so flipping a
-- child off is heard immediately.
-- ============================================================
local function ApplyMutes()
    if not MuteSoundFile then return end
    local d = DB()
    for key, list in pairs(QoL.MUTE_GAME) do
        local mute = d.muteGame.enabled and d.muteGame[key]
        for _, id in ipairs(list) do
            if mute then MuteSoundFile(id) else UnmuteSoundFile(id) end
        end
    end
    for key, list in pairs(QoL.MUTE_MOUNT) do
        local mute = d.muteMount.enabled and d.muteMount[key]
        for _, id in ipairs(list) do
            if mute then MuteSoundFile(id) else UnmuteSoundFile(id) end
        end
    end
    -- login music: muted at logout, unmuted right now - so the theme
    -- only dies between sessions (the Leatrix trick, ported)
    for _, id in ipairs(QoL.MUTE_LOGOUT) do
        UnmuteSoundFile(id)
    end
end
QoL.ApplyMutes = ApplyMutes

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    if not QoL.enabled then return end
    local d = DB()
    if d.muteGame.enabled and d.muteGame.MuteLogin and MuteSoundFile then
        for _, id in ipairs(QoL.MUTE_LOGOUT) do
            MuteSoundFile(id)
        end
    end
end)

-- Refresh everything after a config change; automation re-reads the DB
-- per event so it needs no re-arm.
function QoL.Refresh()
    if not QoL.enabled then return end
    ApplyScreenCvars()
    ApplyErrorText()
    ApplyMutes()
    -- raid performance re-decides on every config change, so toggling
    -- it mid-raid applies or restores immediately
    if QoL.RaidPerfRefresh then QoL.RaidPerfRefresh() end
    -- boss particles likewise, though it never interrupts a running boss
    if QoL.BossFXRefresh then QoL.BossFXRefresh() end
    -- the buff remover starts, stops or re-reads its ticks
    if QoL.BuffRemoverRefresh then QoL.BuffRemoverRefresh() end
    if QoL.RaidTimers then QoL.RaidTimers.Apply() end
    if QoL.SmartMount then QoL.SmartMount.Refresh() end
    if QoL.Snowball then QoL.Snowball.Apply() end
    if QoL.GCDTracker then QoL.GCDTracker.Apply() end
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.qol = function()
    if QoL.enabled then
        QoL.Refresh()
        return
    end
    -- the same feature running twice invites double sells and double
    -- invites; while Leatrix Plus is loaded, stand down.
    if ns.AddonLoaded("Leatrix_Plus") then
        local line = ("qol: Leatrix Plus is running, so ZacUI's quality-of-life "
            .. "module is standing down. Disable or delete Leatrix Plus "
            .. "to switch over - your setup is already ported.")
        -- after the login popups (Core_Popups), not under them
        if ns.Popups then ns.Popups.Say(line) else Print(line) end
        return
    end
    QoL.enabled = true
    ApplyScreenCvars()
    ApplyErrorText()
    ApplyMutes()
    if QoL.EnableAutomation then QoL.EnableAutomation() end
    if QoL.RaidTimers then QoL.RaidTimers.Apply() end
    if QoL.Snowball then QoL.Snowball.Apply() end
    if QoL.GCDTracker then QoL.GCDTracker.Apply() end
end
