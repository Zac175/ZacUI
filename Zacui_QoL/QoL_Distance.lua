-- QoL_Distance - how far your target is, as a small text on the screen:
-- "8-10" yards, coloured: in melee reach, a hunter's dead zone (5-8, too
-- close to shoot, too far to hit), in casting range, out of range.
-- Off by default (Quality of life > On screen).
-- Part of ZacUI; load order is set by the TOC.
--
-- WHERE THE NUMBER COMES FROM. The game never says a distance; addons
-- learn it by asking "is the target within N yards" for the N it can ask
-- about. With LibRangeCheck-3.0 loaded (ZacUI's raid mods part ships it;
-- other addons do too) that gives brackets like 5-8, 8-10, 28-30. Without
-- it, the game's own interaction distances: within 10, within 11, within
-- 28, or past 28. A check the game refuses (WoW Forever / Retail hide some
-- range checks on enemies in a fight) shows "?".
--
-- COST: nothing while off; on, one 0.2 s ticker only while you have a
-- target (and, if set, only in combat).

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local QoL = ns.QoL
if not QoL then return end

local DI = {}
QoL.Distance = DI

local OWN_ID = "qol_distance"
local MOVER = "qoldistance"
local TICK = 0.2
DI.FONT_DEFAULTS = { size = 16, outline = "outline", shadow = false }
-- the colours (ZacUI's own): melee, dead zone, in range, far
DI.COLORS = {
    melee = { 0.35, 0.9, 0.35 }, dead = { 1, 0.55, 0.15 }, range = { 1, 0.85, 0.3 }, far = { 1, 0.3, 0.3 },
}
DI.MELEE, DI.RANGE = 5, 30

local function Hidden(v) return ns.IsSecret and ns.IsSecret(v) or false end

-- ============================================================
-- SETTINGS (qol.distance; nothing saved = off)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.distance) ~= "table" then q.distance = {} end
    return q.distance
end
DI.DB = DB
local function Allowed() return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) end
function DI.On() return Allowed() and QoL.enabled == true and DB().enabled == true end
function DI.CombatOnly() return DB().combatOnly == true end
function DI.Range() return math.max(5, math.min(45, tonumber(DB().range) or DI.RANGE)) end

-- ============================================================
-- THE DISTANCE
-- ============================================================
local function RC()
    local LS = rawget(_G, "LibStub")
    if LS == nil then return nil end
    local ok, lib = pcall(LS, "LibRangeCheck-3.0", true)
    if ok and type(lib) == "table" and type(lib.GetRange) == "function" then return lib end
    return nil
end
DI.Library = RC

-- min, max yards (max nil = farther than anything checked); nil when unknown
function DI.Range_(unit)
    unit = unit or "target"
    if not (UnitExists and UnitExists(unit)) then return nil end
    local lib = RC()
    if lib then
        local ok, lo, hi = pcall(lib.GetRange, lib, unit)
        if ok and lo ~= nil and not Hidden(lo) and not Hidden(hi) then return lo, hi end
        if ok and lo == nil then return nil end
    end
    if type(CheckInteractDistance) ~= "function" then return nil end
    local function Within(i)
        local ok, v = pcall(CheckInteractDistance, unit, i)
        if not ok or Hidden(v) then return nil end
        return v and true or false
    end
    local d3 = Within(3)
    if d3 == nil then return nil end
    if d3 then return 0, 10 end
    local d2 = Within(2)
    if d2 then return 10, 11 end
    local d4 = Within(4)
    if d4 then return 11, 28 end
    if d4 == nil then return nil end
    return 28, nil
end

-- the text and its colour key for a bracket
function DI.Text(lo, hi)
    if lo == nil then return "?", "far" end
    local t = hi and string.format("%d-%d", lo, hi) or string.format("%d+", lo)
    local key
    local hunter = UnitClass and select(2, UnitClass("player")) == "HUNTER"
    if hi and hi <= DI.MELEE then key = "melee"
    elseif hunter and hi and lo >= 5 and hi <= 8 then key = "dead"
    elseif hi and hi <= DI.Range() then key = "range"
    else key = "far" end
    return t, key
end
function DI.Color(key)
    local c = DB()["c_" .. key]
    if type(c) == "table" and ns.ColorOf then return ns.ColorOf(c) end
    local d = DI.COLORS[key] or DI.COLORS.far
    return d[1], d[2], d[3]
end

-- ============================================================
-- THE TEXT ON SCREEN
-- ============================================================
local frame, ticker
local function Frame()
    if frame then return frame end
    frame = CreateFrame("Frame", "ZacUIDistance", UIParent)
    frame:SetSize(80, 24)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(false)
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    frame.text = fs
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -110)
    if ns.ApplyMover then ns.ApplyMover(MOVER) end
    return frame
end
DI.Frame = function() return frame end

local function Style()
    if not frame then return end
    if ns.ApplyFontSpec then ns.ApplyFontSpec(frame.text, DB().font, DI.FONT_DEFAULTS)
    elseif ns.HouseFont then ns.HouseFont(frame.text, 16, "OUTLINE")
    else frame.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 16, "OUTLINE") end
end

function DI.Paint(test)
    if not frame then return end
    local lo, hi
    if test then lo, hi = 8, 10 else lo, hi = DI.Range_("target") end
    local t, key = DI.Text(lo, hi)
    frame.text:SetText(t .. (DB().noYards and "" or " yd"))
    frame.text:SetTextColor(DI.Color(key))
    return t, key
end

local function StopTick() if ticker then ticker:Cancel() ticker = nil end end
function DI.Ticking() return ticker ~= nil end

function DI.Update()
    local want = DI.On() and UnitExists and UnitExists("target")
    if want and DI.CombatOnly() and not (InCombatLockdown and InCombatLockdown()) then want = false end
    if not want then
        StopTick()
        if frame then frame:Hide() end
        return false
    end
    Frame()
    Style()
    DI.Paint()
    frame:Show()
    if not ticker then
        ticker = C_Timer.NewTicker(TICK, function() DI.Paint() end)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "qol.distance") end
    end
    return true
end
function DI.Test()
    Frame() Style()
    DI.Paint(true)
    frame:Show()
    C_Timer.After(5, DI.Update)
end

local ev
function DI.Apply()
    if not DI.On() then
        if ev then ev:UnregisterAllEvents() end
        DI.Update()
        return
    end
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then C_Timer.After(0, DI.Update) else DI.Update() end
        end)
    end
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    DI.Update()
end
function DI.Registered(e) return ev ~= nil and ev:IsEventRegistered(e) or false end

local function Live() if QoL.enabled then DI.Apply() end end
DI.Live = Live
if Allowed() then
    if ns.RegisterMover then
        ns.RegisterMover(MOVER, "Target distance", function() return frame end, "CENTER", 0, -110, nil, { own = true })
    end
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        pcall(DI.Apply)
    end
end

-- ============================================================
-- THE PAGE: Quality of life > On screen
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local l = ns.PageTabs[page] or {}
    ns.PageTabs[page] = l
    l[#l + 1] = { tab = tab, label = label, build = build }
end

local view = setmetatable({}, {
    __index = function(_, k) return DB()[k] end,
    __newindex = function(_, k, v) DB()[k] = v end,
})

AddTab("qol", "onscreen", "On screen", function(L)
    if not Allowed() then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    local d = DB()
    local function Changed()
        Live()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end
    L:Card("Target distance")
    local on = UI.Checkbox(L.current, "Show how far my target is", d.enabled == true, function(v)
        d.enabled = v and true or nil
        Changed()
    end, { tooltip = "A small text, \"8-10 yd\", coloured: in melee reach, a hunter's dead zone, in range, too far." })
    L:Row(on, 17)
    local kids = {}
    kids[#kids + 1] = UI.Checkbox(L.current, "Only in combat", DI.CombatOnly(), function(v)
        d.combatOnly = v and true or nil
        Changed()
    end)
    kids[#kids + 1] = UI.Checkbox(L.current, "Leave off \"yd\"", d.noYards == true, function(v)
        d.noYards = v and true or nil
        Live()
    end)
    kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 5, max = 45, step = 1,
        value = DI.Range(), label = "In range up to",
        format = function(v) return v .. " yd" end,
        onChange = function(v) d.range = (v ~= DI.RANGE) and v or nil end })
    for _, k in ipairs({ { "melee", "In melee reach" }, { "dead", "Dead zone (hunters)" }, { "range", "In range" }, { "far", "Too far" } }) do
        kids[#kids + 1] = UI.ColorPicker(L.current, { label = k[2],
            get = function() local r, g, b = DI.Color(k[1]) return r, g, b, 1 end,
            set = function(r, g, b) d["c_" .. k[1]] = { r = r, g = g, b = b, a = 1 } Live() end })
    end
    kids[#kids + 1] = UI.Button(L.current, "Test", { width = 80,
        tooltip = "Shows the text with a made-up distance for a few seconds.", onClick = function() DI.Test() end })
    L:Dependent(kids, d.enabled == true, 1, nil, "Show how far my target is")
    if Kit then
        Kit.Font(L, "Text", function() return view end, "font", DI.FONT_DEFAULTS,
            { sample = "8-10 yd", after = function() Live() end })
        if Kit.Mover and ns.MOVERS and ns.MOVERS[MOVER] then Kit.Mover(L, MOVER, "the text") end
    end
    if not DI.Library() then
        L:Desc("Finer brackets need LibRangeCheck-3.0 (ZacUI's raid mods part ships it); without it: within 10, 11, 28 yards, or farther.")
    end
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "distance range yards target how far dead zone melee caster range check")
end
