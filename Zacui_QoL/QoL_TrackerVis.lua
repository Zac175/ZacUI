-- QoL_TrackerVis - the quest tracker out of the way when you do not need
-- it: hidden in raids (and, if you tick them, in dungeons, battlegrounds
-- and arenas, or in any fight). Back as soon as you leave. Off by default
-- (Quality of life > Quests, "Quest tracker").
-- Part of ZacUI; load order is set by the TOC.
--
-- HOW IT HIDES, per client:
--   Classic Era / TBC   the tracker is QuestWatchFrame, lines of text with
--                       nothing to click; the game shows it again on every
--                       quest change, so it is faded (alpha 0) rather than
--                       hidden, and faded back.
--   Forever / Retail    the modern tracker has buttons (quest items) that
--                       must not stay clickable unseen, so it is collapsed
--                       the game's own way (its collapse call) and opened
--                       again; never touched in combat (a rule change there
--                       waits for the fight to end).
-- Nothing is done unless a rule says hide; a tracker you collapsed
-- yourself is left collapsed.
--
-- COST: nothing while off; on, a few rare events (zone, combat).

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local QoL = ns.QoL
if not QoL then return end

local TV = {}
QoL.TrackerVis = TV

local OWN_ID = "tracker_vis"

-- ============================================================
-- SETTINGS (qol.trackerVis; nothing saved = off; on = raids)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.trackerVis) ~= "table" then q.trackerVis = {} end
    return q.trackerVis
end
TV.DB = DB
local function Allowed() return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) end
function TV.On() return Allowed() and QoL.enabled == true and DB().enabled == true end
function TV.Rule(key)
    local d = DB()
    if key == "raid" then return d.raid ~= false end
    return d[key] == true
end

-- whether the rules say hide right now
function TV.Want()
    if not TV.On() then return false end
    if TV.Rule("combat") and InCombatLockdown and InCombatLockdown() then return true end
    local inside, kind
    if IsInInstance then inside, kind = IsInInstance() end
    if not inside then return false end
    if kind == "raid" then return TV.Rule("raid") end
    if kind == "party" then return TV.Rule("dungeon") end
    if kind == "pvp" or kind == "arena" then return TV.Rule("pvp") end
    return false
end

-- ============================================================
-- THE TRACKER, per client
-- ============================================================
local function Old() return _G.QuestWatchFrame end
local function Modern() return _G.ObjectiveTrackerFrame end
local hiddenByUs = false
local pendingAfterFight = false

local function Collapse(f, on)
    if f.SetCollapsed then return pcall(f.SetCollapsed, f, on) end
    if on and type(_G.ObjectiveTracker_Collapse) == "function" then return pcall(ObjectiveTracker_Collapse) end
    if not on and type(_G.ObjectiveTracker_Expand) == "function" then return pcall(ObjectiveTracker_Expand) end
    return false
end
local function IsCollapsed(f)
    if f.IsCollapsed then local ok, v = pcall(f.IsCollapsed, f) if ok then return v and true or false end end
    return f.collapsed and true or false
end

function TV.Set(hide)
    local old = Old()
    if old then
        if hide then old:SetAlpha(0) hiddenByUs = true
        elseif hiddenByUs then old:SetAlpha(1) hiddenByUs = false end
        return true
    end
    local mod = Modern()
    if not mod then return false end
    if InCombatLockdown and InCombatLockdown() then
        pendingAfterFight = true
        return false
    end
    if hide then
        if not IsCollapsed(mod) then
            Collapse(mod, true)
            hiddenByUs = true
        end
    elseif hiddenByUs then
        Collapse(mod, false)
        hiddenByUs = false
    end
    return true
end
function TV.HiddenByUs() return hiddenByUs end

function TV.Update()
    return TV.Set(TV.Want())
end

-- the old tracker shows itself again on every quest change: kept faded
local hooked = false
local function Hook()
    if hooked then return end
    hooked = true
    if type(QuestWatch_Update) == "function" then
        hooksecurefunc("QuestWatch_Update", function()
            if hiddenByUs and Old() then Old():SetAlpha(0) end
        end)
    end
end

local ev
function TV.Apply()
    if not TV.On() then
        if ev then ev:UnregisterAllEvents() end
        TV.Set(false)
        return
    end
    Hook()
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" and pendingAfterFight then pendingAfterFight = false end
            if event == "PLAYER_REGEN_DISABLED" then C_Timer.After(0, TV.Update) else TV.Update() end
        end)
    end
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    TV.Update()
end
function TV.Registered(e) return ev ~= nil and ev:IsEventRegistered(e) or false end

local function Live() if QoL.enabled then TV.Apply() end end
TV.Live = Live
if Allowed() then
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        pcall(TV.Apply)
    end
end

-- ============================================================
-- THE CARD: Quality of life > Quests
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local l = ns.PageTabs[page] or {}
    ns.PageTabs[page] = l
    l[#l + 1] = { tab = tab, label = label, build = build }
end

AddTab("qol", "quests", "Quests", function(L)
    if not Allowed() then return end
    local UI = ns.UI
    local d = DB()
    L:Card("Quest tracker")
    local on = UI.Checkbox(L.current, "Hide the quest tracker where I do not need it", d.enabled == true, function(v)
        d.enabled = v and true or nil
        Live()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "The quest tracker goes away in the places ticked below and comes back as you leave them." })
    L:Row(on, 17)
    local kids = {}
    for _, k in ipairs({ { "raid", "In raids" }, { "dungeon", "In dungeons" }, { "pvp", "In battlegrounds and arenas" },
        { "combat", "In any fight" } }) do
        kids[#kids + 1] = UI.Checkbox(L.current, k[2], TV.Rule(k[1]), function(v)
            if k[1] == "raid" then if v then d.raid = nil else d.raid = false end else d[k[1]] = v and true or nil end
            Live()
        end)
    end
    L:Dependent(kids, d.enabled == true, 1, nil, "Hide the quest tracker where I do not need it")
    if not QoL.enabled then L:Desc("The Quality of life part is not running, so this is not either.") end
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "quest tracker objective tracker hide raid dungeon battleground arena combat watch frame")
end
