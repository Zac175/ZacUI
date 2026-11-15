-- QoL_CombatLog - combat logging switches itself on when you enter a
-- raid instance (dungeons too, if asked) and off when you leave, with a
-- line in chat each way. Off by default (Quality of life > Automation).
-- Part of ZacUI; load order is set by the TOC.
--
-- RESPECTS /combatlog. The log is only ever turned on by this file when
-- it was off, and only turned off again when this file was the one that
-- turned it on and it is still on: a log you started yourself is left
-- running, and one you stopped yourself inside the instance stays stopped.
--
-- ONE LOGGER AT A TIME. The raid mods' pull-timer pack carries an
-- "AutoCombatLog" switch of its own (Zacui_RaidMods, "Enable
-- AutoCombatLogging in Dungeons/Raids"), and Readycheck may grow one. When
-- another logger is on, this one stands down and its card says so, so the
-- log is never flipped twice.
--
-- WoW FOREVER: its raids open on 9 December. Until there is a raid to
-- enter, this runs on Forever only with "dungeons too" ticked; otherwise
-- it stands down (Zac: most quality-of-life things aren't needed there).
--
-- COST: two zone events; no tickers.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local Print = ns.Print
local QoL = ns.QoL

local CL = {}
QoL.CombatLog = CL

local OWN_ID = "auto_combatlog"
local RM_AURA = "Fojji - AutoCombatLog"

-- ============================================================
-- SETTINGS (qol.combatLog; nothing saved = off, raids only, chat lines on)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.combatLog) ~= "table" then q.combatLog = {} end
    return q.combatLog
end
CL.DB = DB
function CL.On() return DB().enabled == true end
function CL.Dungeons() return DB().dungeons == true end
function CL.Chat() return DB().chat ~= false end

-- this client can switch the log file at all
function CL.Available() return type(LoggingCombat) == "function" end

-- the other logger that is on, by name, or nil
function CL.OtherLogger()
    -- Readycheck: a feature it may carry (none today); asked, never assumed
    local RC = _G.Readycheck
    if type(RC) == "table" then
        local f = RC.AutoCombatLogOn
        if type(f) == "function" then
            local ok, on = pcall(f, RC)
            if ok and on then return "Readycheck" end
        end
    end
    -- the raid mods' pull-timer pack switch
    local rm = type(ZacUIDB) == "table" and ZacUIDB.raidmods
    if type(rm) == "table" and rm.enabled ~= false then
        local c = type(rm.config) == "table" and rm.config[RM_AURA]
        local unitOff = type(rm.units) == "table" and rm.units[RM_AURA] == false
        if type(c) == "table" and c.combatLogEnable == true and not unitOff
            and (not ns.FeatureOn or ns.FeatureOn("raidmods"))
            and (not ns.AddonLoaded or ns.AddonLoaded("Zacui_RaidMods")) then
            return "the raid mods' pull-timer pack (its AutoCombatLog switch)"
        end
    end
    return nil
end

-- on Forever, only with dungeons ticked (no raid to enter until 9 December)
function CL.ForeverHeld()
    return ns.Flavor and ns.Flavor() == "forever" and not CL.Dungeons()
end

-- what the feature is doing: "off" | "other" | "held" | "on"
function CL.Status()
    if not CL.Available() then return "none" end
    if not CL.On() then return "off" end
    if CL.OtherLogger() then return "other" end
    if CL.ForeverHeld() then return "held" end
    return "on"
end

-- ============================================================
-- THE SWITCH
-- ============================================================
local ours = false        -- this file turned the log on

local function Logging()
    local ok, on = pcall(LoggingCombat)
    return ok and on and true or false
end

local function Where()
    local inInst, kind = IsInInstance()
    if not inInst then return nil end
    return kind
end

local function Say(text)
    if CL.Chat() then Print(text) end
end

-- called on each zone change; the current place decides
function CL.Check()
    if CL.Status() ~= "on" then
        -- switched off, held or standing down: a log we started is left
        -- as it is (the player can /combatlog it off)
        return
    end
    local kind = Where()
    local want = kind == "raid" or (kind == "party" and CL.Dungeons())
    local on = Logging()
    if want then
        if on then
            -- already running: either ours from before, or the player's
            return
        end
        if pcall(LoggingCombat, true) then
            ours = true
            local name = GetInstanceInfo and GetInstanceInfo() or nil
            Say("combat logging ON" .. (name and (" - " .. tostring(name)) or "") .. ".")
        end
    else
        if ours then
            if on then
                pcall(LoggingCombat, false)
                Say("combat logging off.")
            end
            ours = false
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function()
    -- a beat after the zone, so the instance info is settled
    C_Timer.After(1, function() pcall(CL.Check) end)
end)

function CL.Apply() pcall(CL.Check) end

-- ============================================================
-- THE PAGE: a card on Quality of life > Automation
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

AddTab("qol", "auto", "Automation", function(L)
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return end
    if not CL.Available() then return end
    local UI = ns.UI
    local d = DB()
    L:Card("Combat log")
    local on = UI.Checkbox(L.current, "Log combat on its own in raids", CL.On(), function(v)
        d.enabled = v or nil
        CL.Apply()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "The same as typing /combatlog when you enter a raid instance and again when you leave, "
        .. "with a line in chat each way. A log you started yourself is never stopped." })
    L:Row(on, 17)
    local dg = UI.Checkbox(L.current, "Dungeons too", CL.Dungeons(), function(v)
        d.dungeons = v or nil
        CL.Apply()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end)
    local ch = UI.Checkbox(L.current, "Say so in chat", CL.Chat(), function(v)
        if v then d.chat = nil else d.chat = false end
    end)
    L:Dependent({ dg, ch }, CL.On(), 2, nil, "Log combat on its own in raids")
    local st = CL.Status()
    if st == "other" then
        L:Notice("warn", "Standing down: " .. CL.OtherLogger() .. " already logs combat on its own. "
            .. "Turn that one off to use this.")
    elseif st == "held" then
        L:Notice("warn", "Forever's raids open on 9 December: until then this only runs with \"Dungeons too\" ticked.")
    elseif ns.Flavor and ns.Flavor() == "forever" then
        L:Desc("On Forever there is no raid to enter yet (9 December); dungeons are logged while \"Dungeons too\" is ticked.")
    end
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "combat log logging combatlog warcraftlogs wcl logs raid dungeon auto")
end
