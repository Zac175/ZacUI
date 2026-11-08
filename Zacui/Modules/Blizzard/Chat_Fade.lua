-- Chat_Fade - the whole chat, dimmed or hidden (Chat > General):
--   * idle fade: after a while with no chat from players, no typing and
--     no mouse over it, the WHOLE chat - text, panel, tabs, their strip,
--     the bar - dims to a strength you set; at 100% it is gone and the
--     mouse passes through. It wakes on a player's line (not an NPC's), a
--     whisper, the edit box opening or the cursor coming over it;
--   * a visibility rule: always / in combat / out of combat / in a group
--     ... / never, with an opacity (and one in combat) - ZacUI's standard
--     visibility picker.
-- Both off by default; nothing saved = the chat exactly as before. The
-- two meet as the lower of the two.
-- Part of ZacUI; load order is set by the TOC (after Blz_Chat).
--
-- WHAT MOVES. Each chat window's alpha (the windows the raid mode hides
-- are left to it), its panel's, the bar's, and the tabs and their strip
-- through Blz_Chat's own tab alpha (Chat.fadeScale, so the mouseover tabs
-- and the raid mode keep working on top). Nothing is shown or hidden and
-- nothing secure is touched, so it works in a fight.
--
-- WoW FOREVER: the wake events are only counted - their arguments (which
-- can be hidden values in a fight) are never read.
--
-- COST: while the idle fade is on, a quarter-second check (the mouse, the
-- edit boxes, the clock) and a time stamp per player chat line; a short
-- OnUpdate only while the alpha is moving. Off: nothing.

local ADDON_NAME, ns = ...

local Chat = ns.Chat

local FD = {}
ns.ChatFade = FD

local IDLE_ID, VIS_ID = "chat_idle_fade", "chat_visibility"
local DEFAULT_DELAY, DEFAULT_STRENGTH = 15, 40
FD.DEFAULT_DELAY, FD.DEFAULT_STRENGTH = DEFAULT_DELAY, DEFAULT_STRENGTH

-- ============================================================
-- SETTINGS (ZacUIDB.chat: idleFade, idleDelay, idleStrength, idleWorld,
-- visibility = { show, alpha, combatAlpha }; nothing saved = off)
-- ============================================================
local function DB()
    if Chat and Chat.DB then return Chat.DB() end
    ZacUIDB.chat = ZacUIDB.chat or {}
    return ZacUIDB.chat
end
FD.DB = DB
local function Allowed(id) return not (ns.FeatureOn and not ns.FeatureOn(id)) end
function FD.IdleOn() return Allowed(IDLE_ID) and DB().idleFade == true end
function FD.Delay()
    local v = tonumber(DB().idleDelay)
    if not v then return DEFAULT_DELAY end
    return math.max(3, math.min(300, v))
end
function FD.Strength()
    local v = tonumber(DB().idleStrength)
    if not v then return DEFAULT_STRENGTH end
    return math.max(10, math.min(100, v))
end
function FD.VisSpec()
    if not Allowed(VIS_ID) then return nil end
    local v = DB().visibility
    if type(v) == "table" and next(v) ~= nil then return v end
    return nil
end

-- ============================================================
-- THE STATE
-- ============================================================
local cur, idleT, visT = 1, 1, 1
local lastActive = 0
local mouseOff = setmetatable({}, { __mode = "k" })   -- frames we let the mouse through
local animator, ticker, events, visDriver
local FADE_OUT, FADE_IN = 0.6, 0.15

local function Now() return (GetTime and GetTime()) or 0 end
function FD.Alpha() return cur end
function FD.Target() return math.min(idleT, visT) end

-- every frame of the chat this file dims
local function EachPart(fn)
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local cf = _G[name]
        if cf and cf.IsShown and cf:IsShown() then
            if not cf._zRMHid then fn(cf, true) end
            local bg = cf._zui_chatbg
            if bg then fn(bg, false) end
        end
    end
    local bar = _G.ZacUIChatBar
    if bar then fn(bar, true) end
    -- the icon rail beside the panel (Chat_Panel), with the rest
    local rail = _G.ZacUIChatRail
    if rail then fn(rail, true) end
end

local function Paint(a)
    a = math.max(0, math.min(1, a))
    EachPart(function(f, mouse)
        if f.SetAlpha then f:SetAlpha(a) end
        if mouse then
            if a <= 0.001 then
                if not mouseOff[f] and f.IsMouseEnabled and f:IsMouseEnabled() then
                    mouseOff[f] = true
                    f:EnableMouse(false)
                    if f.EnableMouseWheel then f:EnableMouseWheel(false) end
                end
            elseif mouseOff[f] then
                mouseOff[f] = nil
                f:EnableMouse(true)
                if f.EnableMouseWheel then f:EnableMouseWheel(true) end
            end
        end
    end)
    if Chat then
        local scale = (a < 0.999) and a or nil
        if Chat.fadeScale ~= scale then
            Chat.fadeScale = scale
            if Chat.RepaintTabs then pcall(Chat.RepaintTabs) end
        end
    end
end
FD.Paint = Paint

local function Step(self, dt)
    local tgt = FD.Target()
    if math.abs(cur - tgt) < 0.002 then
        cur = tgt
        Paint(cur)
        self:Hide()
        return
    end
    local m = ns.Motion
    local on = not m or not m.Enabled or m.Enabled()
    local sp = (m and m.Speed and m.Speed()) or 1
    local dur = (tgt < cur) and FADE_OUT or FADE_IN
    if not on or dur <= 0 then
        cur = tgt
    else
        local step = dt * sp / dur
        if tgt < cur then cur = math.max(tgt, cur - step) else cur = math.min(tgt, cur + step) end
    end
    Paint(cur)
end

local function Kick(instant)
    local tgt = FD.Target()
    if instant then
        cur = tgt
        Paint(cur)
        if animator then animator:Hide() end
        return
    end
    if math.abs(cur - tgt) < 0.002 then return end
    if not animator then
        animator = CreateFrame("Frame")
        animator:Hide()
        animator:SetScript("OnUpdate", Step)
    end
    animator:Show()
end
FD.Kick = Kick

-- ============================================================
-- IDLE
-- ============================================================
local function Typing()
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local cf = _G[name]
        local eb = cf and (cf.editBox or _G[name .. "EditBox"])
        if eb and eb.HasFocus and eb:HasFocus() then return true end
    end
    return false
end
local function MouseOver()
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local cf = _G[name]
        if cf and cf.IsVisible and cf:IsVisible() and cf.IsMouseOver and cf:IsMouseOver(60, -40, -8, 8) then
            return true
        end
    end
    local bar = _G.ZacUIChatBar
    if bar and bar.IsVisible and bar:IsVisible() and bar.IsMouseOver and bar:IsMouseOver(2, -2, -2, 2) then return true end
    local rail = _G.ZacUIChatRail
    if rail and rail.IsVisible and rail:IsVisible() and rail.IsMouseOver and rail:IsMouseOver(2, -2, -2, 2) then return true end
    return false
end

function FD.Wake()
    lastActive = Now()
    if idleT ~= 1 then
        idleT = 1
        Kick()
    end
end

local function Check()
    if not FD.IdleOn() then return end
    if Typing() or MouseOver() then
        FD.Wake()
        return
    end
    if Now() - lastActive >= FD.Delay() then
        local want = 1 - FD.Strength() / 100
        if idleT ~= want then
            idleT = want
            Kick()
        end
    end
end
FD.Check = Check

-- the lines that wake it: players talking (never an NPC's), whispers both
-- ways; world channels only when asked
FD.WAKE_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local function StartIdle()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function() FD.Wake() end)
    end
    events:UnregisterAllEvents()
    for _, e in ipairs(FD.WAKE_EVENTS) do pcall(events.RegisterEvent, events, e) end
    if DB().idleWorld then pcall(events.RegisterEvent, events, "CHAT_MSG_CHANNEL") end
    if not ticker then
        lastActive = Now()
        ticker = C_Timer.NewTicker(0.25, Check)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "chat.idleFade") end
    end
end
local function StopIdle()
    if events then events:UnregisterAllEvents() end
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    idleT = 1
end

-- ============================================================
-- THE VISIBILITY RULE (ns.Visibility drives a stand-in; we take its answer)
-- ============================================================
local function ApplyVis()
    local spec = FD.VisSpec()
    if spec and not visDriver and ns.Visibility and ns.Visibility.Register then
        visDriver = CreateFrame("Frame")
        ns.Visibility.Register(visDriver, FD.VisSpec, { control = "gate",
            onChange = function(_, allowed, a)
                local want
                if not allowed then want = 0 else want = tonumber(a) or 1 end
                want = math.max(0, math.min(1, want))
                if want ~= visT then
                    visT = want
                    Kick()
                end
            end })
    elseif visDriver and ns.Visibility then
        ns.Visibility.Refresh(visDriver)
    end
    if not spec and visT ~= 1 then
        visT = 1
        Kick()
    end
end
FD.ApplyVis = ApplyVis

function FD.Apply()
    if FD.IdleOn() then StartIdle() else StopIdle() end
    ApplyVis()
    Kick()
end

-- Test: fade now, as if the delay had run out (the next mouse over the
-- chat, line or key wakes it)
function FD.Test()
    if not FD.IdleOn() then return false end
    lastActive = -1e9
    idleT = 1 - FD.Strength() / 100
    Kick()
    return true
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if FD.IdleOn() or FD.VisSpec() then FD.Apply() end
    -- the raid mode puts the windows back at full: ours goes on top again
    local RM = Chat and Chat.RaidMode
    if RM and type(RM.Apply) == "function" then
        hooksecurefunc(RM, "Apply", function() if cur < 1 then Paint(cur) end end)
    end
end)

-- ============================================================
-- THE CHAT PAGE: a card on General
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

AddTab("chat", "general", "General", function(L)
    local idle, vis = Allowed(IDLE_ID), Allowed(VIS_ID)
    if not (idle or vis) then return end
    local UI = ns.UI
    local d = DB()
    L:Card("When the chat shows")
    if idle then
        local on = UI.Checkbox(L.current, "Fade the whole chat when it is idle", FD.IdleOn(), function(v)
            d.idleFade = v and true or nil
            FD.Apply()
            if ns.RefreshConfig then ns.RefreshConfig() end
        end, { tooltip = "After the time below with nobody talking, no typing and no mouse over it, the chat - "
            .. "text, panel, tabs and bar - dims. It comes back the moment a player says something, a whisper "
            .. "arrives, you start typing or the mouse comes over it. NPC lines do not wake it." })
        L:Row(on, 17)
        local kids = {}
        kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 3, max = 120, step = 1, value = FD.Delay(),
            label = "Idle for", format = function(v) return v .. " sec" end,
            onChange = function(v) d.idleDelay = (v ~= DEFAULT_DELAY) and v or nil end })
        kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 10, max = 100, step = 5, value = FD.Strength(),
            label = "Fade by", format = function(v) return v == 100 and "100% (gone)" or (v .. "%") end,
            onChange = function(v) d.idleStrength = (v ~= DEFAULT_STRENGTH) and v or nil end })
        kids[#kids + 1] = UI.Checkbox(L.current, "Trade and world channels wake it too", d.idleWorld == true, function(v)
            d.idleWorld = v and true or nil
            FD.Apply()
        end, { tooltip = "Off: General, Trade and the other numbered channels keep it asleep, so a busy city does "
            .. "not hold the chat up." })
        kids[#kids + 1] = UI.Button(L.current, "Test", { width = 80,
            tooltip = "Fades the chat now, as if it had been idle; move the mouse over it to wake it.",
            onClick = function() FD.Test() end })
        L:Dependent(kids, FD.IdleOn(), 2, nil, "Fade the whole chat when it is idle")
        L:Desc("At 100% the chat is gone and the mouse passes through it to what is underneath.")
    end
    if vis and UI.VisibilityPicker and ns.CustomAccess then
        local get, set = ns.CustomAccess(DB, "visibility", nil, function() ApplyVis() end)
        local picker = UI.VisibilityPicker(L.current, {
            label = "Show the chat",
            get = get,
            set = function(spec) set(spec) ApplyVis() end,
            defaults = { show = "always", alpha = 1 },
            shows = { "always", "combat", "nocombat", "group", "raid", "instance", "resting", "never" },
            fields = { show = true, alpha = true, combatAlpha = true },
            width = UI.CardInnerWidth and UI.CardInnerWidth(L) or nil })
        L:Add(picker, 8)
        L:Desc("Default is always, at full. \"Never\" hides it completely and the mouse passes through; "
            .. "the idle fade, when on, dims it further still.")
    end
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("chat", "idle fade dim hide inactive opacity transparent visibility combat show when never")
end
