-- Tutorial_Setup2 - the setup: one window of short steps, a rail of steps
-- down the left, a preview on every step, that sets up ZacUI the way a new
-- player wants it. Replaces Tutorial_Setup (kept on disk, not loaded).
-- Part of ZacUI; load order is set by the TOC (after Tutorial_Hints and
-- Tutorial_Layouts, before Boot_Events).
--
--   1. Welcome        what is about to happen; skip everything
--   2. Game version   what this game runs, what is off here (Core_Flavor)
--   3. Parts          which installed parts are on, a miniature each
--   4. Look           ZacUI's look (ns.Look when the Look job has shipped,
--                     else the accent colour and the font)
--   5. Layout         a named layout for the frames (Tutorial_Layouts)
--   6. Scale          the game's interface scale, with the pixel-perfect
--                     recommendation for this screen
--   7. Screen         chat, minimap, tooltips: on / off and the basics
--   8. Profile        start fresh, copy a profile, import a string
--   9. All set        what changed, one Reload, the ways on
--
-- EVERYTHING IS OPTIONAL and nothing is written until a control is used:
-- Next without touching anything changes nothing, so "skip, I'll use the
-- defaults" is the natural state of every step. Each control writes
-- through the very setter its settings page uses, so profiles, previews
-- and live refresh behave exactly as they do from the pages. RELOADS are
-- collected, never asked for one by one: the last step lists what waits
-- for one, with a single Reload button.
--
-- WHO SEES IT. Whoever asks: the fresh-install welcome's Quick setup
-- button (Tutorial_Core), /zui setup, the General page. Nobody else.
--
-- BOOKKEEPING (account-wide, outside every profile):
--   ZacUIDB.setup = { version = 2, done, step }
--
--   ns.TutorialSetup.Open() / Close() / IsShown()
--   ns.TutorialSetup.Parts()          the part rows this install lists
--   ns.TutorialSetup.ReloadNeeded()   labels of what waits for a reload
--   ns.TutorialSetup.PageIds() / Page() / Go(i) / Frame()   (tests)
--   ns.SetupCard(L)                   the General page's Setup card

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Print = ns.Print
local UI = ns.UI

local M, F = UI.M, UI.F

local Setup = {}
Setup.VERSION = 2

local W, H = 680, 540
local RAIL_W = 156
local PAD = 16
local FOOT_H = 44

local function T() return ns.Tutorial end
local function InCombat()
    return (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

local function DB()
    if type(ZacUIDB) ~= "table" then return {} end
    if type(ZacUIDB.setup) ~= "table" then ZacUIDB.setup = { version = Setup.VERSION } end
    return ZacUIDB.setup
end
Setup.DB = DB

local function Loaded(addon)
    return ns.AddonLoaded and ns.AddonLoaded(addon) or false
end

-- ============================================================
-- SETTERS (the pages' own)
-- ============================================================
local function ModuleOn(k)
    local ran = ns.ZUI and ns.ZUI._ran
    if ran and ran[k] then
        ZacUIDB.modules[k] = true
    elseif ns.EnableModuleLive then
        ns.EnableModuleLive(k)
    else
        ZacUIDB.modules[k] = true
    end
end

local function ModuleOff(k)
    ZacUIDB.modules[k] = false
    if ns.CVar and ns.CVar.RestoreOwner then pcall(ns.CVar.RestoreOwner, k) end
end

local function ModulesGet(keys)
    return function()
        local mods = ZacUIDB and ZacUIDB.modules or {}
        for _, k in ipairs(keys) do
            if not mods[k] then return false end
        end
        return true
    end
end

local function ModulesSet(keys)
    return function(on)
        for _, k in ipairs(keys) do
            if on then ModuleOn(k) else ModuleOff(k) end
        end
    end
end

local function WindowKeys()
    local out = {}
    for k, addon in pairs(ns.MODULE_ADDON or {}) do
        if addon == "Zacui_Windows" then out[#out + 1] = k end
    end
    table.sort(out)
    return out
end

local function WorldMapDB()
    local WM = _G.ZacuiWorldMap
    local ok, mod = pcall(function() return WM and WM.GetModule and WM:GetModule("worldmap") end)
    return ok and mod and mod.db or nil
end

-- ============================================================
-- THE PARTS
-- ============================================================
-- One row per switch a loaded part has. reload: "off" (turning it off
-- needs a reload, on applies live), "always" (either way waits for a
-- reload), nil (live both ways). mini: the miniature drawn on its card.
local function PartSpecs()
    local specs = {}
    local function Module(addon, label, desc, keys, group, mini)
        specs[#specs + 1] = { id = "mod:" .. keys[1], addon = addon, label = label, desc = desc, group = group,
            mini = mini, get = ModulesGet(keys), set = ModulesSet(keys), reload = "off" }
    end
    Module("Zacui_Bars", "Action bars",
        "Ten bars plus pet, stance and bag bars, each placed, scaled and faded your way.", { "bars" }, "HUD", "bars")
    Module("Zacui_Nameplates", "Nameplates",
        "Health, cast bars, debuffs and threat colours on the plates over enemies.", { "nameplates" }, "HUD", "plates")
    Module("Zacui_Meter", "Damage meter", "Damage, healing and threat for you and your group.", { "meter" }, "Combat", "meter")
    Module("Zacui_Bags", "Combined bag", "One window for every bag, with search and sorting.", { "inventory" }, "Windows", "bag")
    Module("Zacui_Bags", "Auction house", "Search, sell and cancel tabs, with a memory of prices you have seen.",
        { "auctionhouse" }, "Windows", "list")
    Module("Zacui_Maps", "Maps",
        "A movable world map with unexplored areas shown, flight points and dungeon entrances.", { "maps" }, "Windows", "map")
    Module("Zacui_QoL", "Quality of life",
        "Sell junk, repair, skip gossip, faster looting and other small helpers.", { "qol" }, "Tools", "ticks")
    local winKeys = WindowKeys()
    if #winKeys > 0 then
        Module("Zacui_Windows", "Game windows",
            "ZacUI's own character sheet, spellbook, talents, quest log, mail, social and more.", winKeys, "Windows", "window")
    end
    specs[#specs + 1] = { id = "sbt", addon = "Zacui_SBT", label = "Scrolling text", group = "Combat", mini = "numbers",
        desc = "Damage, healing and alerts scrolling around your character.",
        ready = function() return ns.SBT and ns.SBT.IsOn and ns.SBT.SetOn end,
        get = function() return ns.SBT.IsOn() end,
        set = function(on) ns.SBT.SetOn(on) end }
    specs[#specs + 1] = { id = "blessings", addon = "Zacui_Blessings", label = "Blessings", group = "Combat", mini = "icons",
        desc = "Who blesses which class, shared with the paladins in your group.",
        ready = function() local BL = ns.Blessings return BL and BL.Cfg and BL.Cfg() end,
        get = function() return ns.Blessings.Cfg().enabled and true or false end,
        set = function(on)
            local BL = ns.Blessings
            BL.Cfg().enabled = on and true or false
            if on then BL.Start() else BL.Stop() end
            if BL.Bar and BL.Bar.Refresh then BL.Bar.Refresh() end
        end }
    specs[#specs + 1] = { id = "clickcast", addon = "Zacui_Clicks", label = "Click casting", group = "Tools", mini = "mouse",
        desc = "Spells and macros on mouse buttons and keys over your unit frames.",
        ready = function() local CC = ns.ClickCast return CC and CC.Cfg and CC.Cfg() and CC.SetEnabled and not CC.standDown end,
        get = function() return ns.ClickCast.Cfg().enabled and true or false end,
        set = function(on) ns.ClickCast.SetEnabled(on) end }
    specs[#specs + 1] = { id = "raidmods", addon = "Zacui_RaidMods", label = "Raid mods", group = "Combat", mini = "timer",
        desc = "Timers, warnings and marks for the bosses of the classic raids.",
        ready = function() local RM = ns.RaidMods return RM and RM.DB and RM.DB() end,
        get = function() return ns.RaidMods.DB().enabled and true or false end,
        set = function(on)
            local RM = ns.RaidMods
            RM.DB().enabled = on and true or false
            if RM.UnloadAll then RM.UnloadAll() end
            if RM.ScanForLoads then RM.ScanForLoads() end
        end }
    specs[#specs + 1] = { id = "worldmap", addon = "Zacui_WorldMap", label = "Seamless world map", group = "Windows", mini = "map",
        desc = "Every zone stitched into one map you can zoom across.", reload = "always",
        ready = function() return WorldMapDB() end,
        get = function() return WorldMapDB().enabled and true or false end,
        set = function(on) WorldMapDB().enabled = on and true or false end }
    specs[#specs + 1] = { id = "auras", addon = "Zacui_Auras", label = "Aura engine", group = "Combat", mini = "glow",
        desc = "Runs custom auras and imports aura strings.", reload = "always",
        ready = function() return ns.Auras and ns.Auras.Status and ns.Auras.SetEnabled end,
        get = function() return ns.Auras.Status().want end,
        set = function(on) ns.Auras.SetEnabled(on) end }
    return specs
end

-- Parts that have no switch inside ZacUI: on whenever the AddOns list
-- has them on.
local ALWAYS_ON = {
    { addon = "Zacui_UnitFrames", label = "Unit frames" },
    { addon = "Zacui_HUD", label = "Class HUDs" },
}

-- The rows this install lists: the part is loaded and its switch is there.
function Setup.Parts()
    local out = {}
    for _, s in ipairs(PartSpecs()) do
        local ok, ready = pcall(function() return (not s.ready) or s.ready() end)
        -- (a part this game version does not run is not offered: Core_Flavor)
        if Loaded(s.addon) and ok and ready and not (ns.PartOff and ns.PartOff(s.addon)) then out[#out + 1] = s end
    end
    return out
end

local function AlwaysOnLoaded()
    local out = {}
    for _, p in ipairs(ALWAYS_ON) do
        if Loaded(p.addon) then out[#out + 1] = p.label end
    end
    return out
end

-- ============================================================
-- THE GAME'S INTERFACE SCALE
-- ============================================================
local SCALE_MIN, SCALE_MAX = 0.64, 1.0

local function GetCV(name)
    if ns.CVar then return ns.CVar.Get(name) end
    return nil
end

local function CurrentScale()
    local v
    if GetCV("useUiScale") == "1" then v = tonumber(GetCV("uiScale")) end
    if not v then v = UIParent and UIParent.GetScale and UIParent:GetScale() or 1 end
    return math.max(SCALE_MIN, math.min(SCALE_MAX, v or 1))
end

-- The screen in physical pixels (nil when the client cannot say).
local function PhysicalHeight()
    if not GetPhysicalScreenSize then return nil end
    local ok, w, h = pcall(GetPhysicalScreenSize)
    if ok and type(h) == "number" and h > 0 then return h, w end
    return nil
end

-- The pixel-perfect scale for this screen: 768 over the physical height,
-- so one interface unit is one pixel; clamped to what the game allows.
-- Returns the scale, the exact value before clamping, and the height.
function Setup.RecommendedScale(physH)
    physH = physH or PhysicalHeight()
    if not physH then return nil end
    local exact = 768 / physH
    local v = math.max(SCALE_MIN, math.min(SCALE_MAX, exact))
    return v, exact, physH
end

local function ScaleText(v)
    return string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")
end

-- ============================================================
-- THE WINDOW
-- ============================================================
local frame, rail, pagesHost
local S   -- this opening's session: what changed, the part rows, the steps
local steps, index

local function Clear(f)
    for _, c in ipairs({ f:GetChildren() }) do
        c:Hide()
        c:ClearAllPoints()
        c:SetParent(nil)
    end
    for _, r in ipairs({ f:GetRegions() }) do
        r:Hide()
        r:ClearAllPoints()
    end
end

local function Note(key, text)
    if not S.notes[key] then S.noteOrder[#S.noteOrder + 1] = key end
    S.notes[key] = text
end
Setup.Note = Note

-- something other than a part that waits for a reload
local function NeedsReload(key, label)
    S.reloadExtra[key] = label
end

local PAGE_W = W - RAIL_W - 2
local function Title(host, title, sub)
    local t = UI.Font(host, F.HEADER, { text = title, cat = "text", key = "gold" })
    t:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -14)
    local s = UI.Font(host, F.DESC, { text = sub, cat = "text", key = "gray", width = PAGE_W - 2 * PAD })
    s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -5)
    local rule = host:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -8)
    rule:SetWidth(PAGE_W - 2 * PAD)
    host._zRule = rule
    host._zPaint = function(self)
        local a = GetColor("ui", "accent")
        self._zRule:SetVertexColor(a.r, a.g, a.b, 0.6)
    end
    host:_zPaint()
    return -14 - 15 - 5 - math.max(12, s:GetStringHeight() or 12) - 8 - 14
end

local function Label(host, text, x, y)
    local fs = UI.Font(host, F.LABEL, { text = text, cat = "text", key = "gold" })
    fs:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    return fs
end

local function Desc(host, text, x, y, width)
    local fs = UI.Font(host, F.DESC, { text = text, cat = "text", key = "gray", width = width })
    fs:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    return fs, math.max(12, fs:GetStringHeight() or 12)
end

local function RepaintAll()
    if frame then UI.Repaint(frame) end
    local win = _G.ZacUIConfigFrame
    if win and win:IsShown() then UI.Repaint(win) end
end

-- ============================================================
-- MINIATURES
-- ============================================================
-- Small inert drawings of what a part puts on screen, in ZacUI's own
-- colours: a stand-in, not the part's frames (those belong to the game
-- world, and a part that is off has none). Every drawing is a few flat
-- rectangles and a line of text; `Dim(canvas, on)` fades the whole
-- canvas when the part is off.
local Mini = {}

local function Rect(parent, x, y, w, h, cat, key, alpha)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t._zui_own = true
    t:SetTexture(FLAT)
    t:SetSize(w, h)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    local c = GetColor(cat or "ui", key or "accent")
    t:SetVertexColor(c.r, c.g, c.b, alpha or 1)
    t._zCat, t._zKey, t._zAlpha = cat or "ui", key or "accent", alpha or 1
    return t
end

local function Canvas(parent, w, h)
    local box = UI.Box(parent, "ui", "elementBg")
    box:SetSize(w, h)
    box.marks = {}
    box.Rect = function(self, x, y, rw, rh, cat, key, alpha)
        local t = Rect(self, x, y, rw, rh, cat, key, alpha)
        self.marks[#self.marks + 1] = t
        return t
    end
    box.Text = function(self, text, x, y, size, cat, key)
        local fs = UI.Font(self, size or F.SMALL, { text = text, cat = cat or "text", key = key or "normal" })
        fs:SetPoint("TOPLEFT", self, "TOPLEFT", x, -y)
        self.marks[#self.marks + 1] = fs
        return fs
    end
    box.Reset = function(self)
        for _, m in ipairs(self.marks) do m:Hide() m:ClearAllPoints() end
        self.marks = {}
    end
    local paint = box._zPaint
    box._zPaint = function(self)
        paint(self)
        for _, m in ipairs(self.marks) do
            if m._zCat then
                local c = GetColor(m._zCat, m._zKey)
                m:SetVertexColor(c.r, c.g, c.b, m._zAlpha)
            elseif m._zPaint then
                m:_zPaint()
            end
        end
    end
    return box
end
Setup.Canvas = Canvas

local function Dim(canvas, on)
    canvas:SetAlpha(on and 1 or 0.35)
end

-- the drawings, each on a 120x60 canvas
function Mini.bars(c)
    for i = 0, 5 do
        c:Rect(8 + i * 18, 20, 15, 15, "ui", "cardBg")
        c:Rect(8 + i * 18, 20, 15, 15, "ui", "border", 0.9)
        c:Rect(9 + i * 18, 21, 13, 13, "ui", "accent", 0.25 + (i % 3) * 0.2)
    end
    c:Rect(8, 40, 105, 4, "ui", "border", 0.6)
    c:Rect(8, 40, 70, 4, "text", "blue", 0.8)
end
function Mini.plates(c)
    c:Rect(20, 22, 80, 8, "ui", "cardBg")
    c:Rect(20, 22, 56, 8, "text", "red", 0.9)
    c:Text("Defias Pillager", 22, 8, F.SMALL)
    c:Rect(20, 33, 80, 4, "ui", "border", 0.6)
    c:Rect(20, 33, 30, 4, "text", "yellow", 0.9)
end
function Mini.meter(c)
    local names = { "Zaccw", "Thrall", "Jaina" }
    for i = 1, 3 do
        c:Rect(8, 6 + (i - 1) * 17, 104, 14, "ui", "cardBg")
        c:Rect(8, 6 + (i - 1) * 17, 104 - (i - 1) * 30, 14, "ui", "accent", 0.55)
        c:Text(names[i], 11, 7 + (i - 1) * 17, F.SMALL)
    end
end
function Mini.bag(c)
    for r = 0, 2 do
        for i = 0, 6 do
            c:Rect(8 + i * 15, 8 + r * 15, 13, 13, "ui", "cardBg")
            c:Rect(8 + i * 15, 8 + r * 15, 13, 13, "ui", "border", 0.8)
        end
    end
end
function Mini.list(c)
    for i = 0, 3 do
        c:Rect(8, 8 + i * 12, 104, 10, "ui", "cardBg")
        c:Rect(10, 10 + i * 12, 40 + (i % 2) * 20, 6, "ui", "border", 0.8)
    end
end
function Mini.map(c)
    c:Rect(8, 6, 104, 48, "ui", "cardBg")
    c:Rect(14, 12, 40, 22, "text", "green", 0.35)
    c:Rect(60, 20, 46, 28, "text", "yellow", 0.25)
    c:Rect(30, 30, 4, 4, "text", "red")
    c:Rect(70, 14, 4, 4, "text", "red")
    c:Rect(90, 36, 4, 4, "text", "blue")
end
function Mini.ticks(c)
    local rows = { "Sell junk", "Repair", "Skip gossip" }
    for i = 1, 3 do
        c:Rect(10, 8 + (i - 1) * 16, 10, 10, "ui", "cardBg")
        c:Rect(12, 10 + (i - 1) * 16, 6, 6, "text", "green")
        c:Text(rows[i], 26, 7 + (i - 1) * 16, F.SMALL)
    end
end
function Mini.window(c)
    c:Rect(8, 6, 104, 48, "ui", "cardBg")
    c:Rect(8, 6, 104, 10, "ui", "headerBg")
    c:Rect(8, 16, 104, 1, "ui", "accent", 0.6)
    c:Rect(14, 22, 30, 26, "ui", "border", 0.6)
    c:Rect(50, 22, 56, 6, "ui", "border", 0.6)
    c:Rect(50, 32, 40, 6, "ui", "border", 0.6)
end
function Mini.numbers(c)
    c:Text("1240", 20, 6, F.CARD, "text", "yellow")
    c:Text("+860", 70, 20, F.CARD, "text", "green")
    c:Text("Dodge", 36, 36, F.SMALL, "text", "gray")
end
function Mini.icons(c)
    for i = 0, 3 do
        c:Rect(14 + i * 24, 20, 20, 20, "ui", "cardBg")
        c:Rect(14 + i * 24, 20, 20, 20, "ui", "border", 0.9)
        c:Rect(16 + i * 24, 22, 16, 16, "text", "yellow", 0.3 + i * 0.15)
    end
end
function Mini.mouse(c)
    c:Rect(46, 8, 28, 44, "ui", "cardBg")
    c:Rect(46, 8, 28, 44, "ui", "border", 0.9)
    c:Rect(46, 8, 13, 16, "ui", "accent", 0.7)
    c:Rect(61, 8, 13, 16, "text", "blue", 0.5)
    c:Rect(58, 12, 4, 10, "ui", "border")
end
function Mini.timer(c)
    c:Rect(8, 14, 104, 12, "ui", "cardBg")
    c:Rect(8, 14, 70, 12, "text", "red", 0.7)
    c:Text("Flame Breath  12", 12, 14, F.SMALL)
    c:Rect(8, 34, 104, 12, "ui", "cardBg")
    c:Rect(8, 34, 40, 12, "text", "yellow", 0.7)
    c:Text("Whelps  31", 12, 34, F.SMALL)
end
function Mini.glow(c)
    c:Rect(44, 14, 32, 32, "ui", "cardBg")
    c:Rect(44, 14, 32, 32, "ui", "border", 0.9)
    c:Rect(40, 10, 40, 40, "ui", "accent", 0.18)
    c:Rect(48, 18, 24, 24, "text", "yellow", 0.6)
end
function Mini.chat(c)
    c:Rect(8, 6, 104, 48, "ui", "windowBg", 0.9)
    c:Rect(8, 6, 104, 8, "ui", "headerBg")
    c:Rect(10, 18, 60, 4, "text", "yellow", 0.7)
    c:Rect(10, 25, 80, 4, "text", "blue", 0.6)
    c:Rect(10, 32, 50, 4, "text", "green", 0.6)
    c:Rect(8, 44, 104, 10, "ui", "elementBg")
    c:Rect(8, 44, 104, 1, "ui", "accent", 0.6)
end
function Mini.minimap(c)
    c:Rect(30, 4, 60, 52, "ui", "cardBg")
    c:Rect(30, 4, 60, 10, "ui", "headerBg")
    c:Rect(32, 16, 56, 30, "text", "green", 0.3)
    c:Rect(58, 29, 4, 4, "text", "yellow")
    c:Rect(30, 46, 60, 10, "ui", "headerBg")
end
function Mini.tooltip(c)
    c:Rect(14, 8, 92, 44, "ui", "windowBg", 0.95)
    c:Rect(14, 8, 92, 44, "ui", "border", 0.9)
    c:Text("Zaccw", 20, 11, F.SMALL, "text", "yellow")
    c:Text("Level 60 Human Warrior", 20, 25, F.SMALL, "text", "gray")
    c:Rect(20, 42, 80, 5, "text", "green", 0.8)
end

local function DrawMini(canvas, kind)
    canvas:Reset()
    local fn = Mini[kind] or Mini.window
    fn(canvas)
    canvas:_zPaint()
end
Setup.DrawMini = DrawMini
Setup.Mini = Mini

-- ------------------------------------------------------------
-- 1. WELCOME
-- ------------------------------------------------------------
local function PageWelcome(host)
    local y = Title(host, "Welcome to ZacUI",
        "A few short steps set up the basics. Nothing changes until you choose it, every step can be "
        .. "skipped, and everything here can be changed again later on the settings pages.")
    local x = PAD
    Label(host, "What is about to happen", x, y)
    y = y - 18
    local lines = {}
    for i, st in ipairs(steps) do
        if st.id ~= "welcome" and st.id ~= "done" then lines[#lines + 1] = st.title .. " - " .. st.blurb end
    end
    for _, l in ipairs(lines) do
        local dash = UI.Font(host, F.LABEL, { text = "-", cat = "text", key = "gray" })
        dash:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
        local fs = UI.Font(host, F.LABEL, { text = l, width = PAGE_W - 2 * PAD - 14 })
        fs:SetPoint("TOPLEFT", host, "TOPLEFT", x + 12, y)
        y = y - math.max(13, fs:GetStringHeight() or 12) - 5
    end
    y = y - 12
    local _, dh = Desc(host, "In a hurry? Skip everything keeps ZacUI's defaults and closes this. "
        .. "The guided tour shows you around the settings window instead.", x, y, PAGE_W - 2 * PAD)
    y = y - dh - 10
    local skip = UI.Button(host, "Skip everything, use the defaults", { width = 220,
        tooltip = "Closes the setup. ZacUI keeps every default; /zui setup brings this back any time.",
        onClick = function()
            DB().done = true
            if T() then T().DB().setupDone = true end
            Setup.Close()
            Print("Setup skipped - ZacUI keeps its defaults. /zui setup brings it back any time.")
        end })
    skip:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    local tour = UI.Button(host, "Take the tour instead", { width = 150,
        tooltip = "Opens the settings window and shows you around it.",
        onClick = function()
            Setup.Close()
            if T() then T().StartTour() end
        end })
    tour:SetPoint("LEFT", skip, "RIGHT", 8, 0)
    host.skipButton, host.tourButton = skip, tour
end

-- ------------------------------------------------------------
-- 2. GAME VERSION
-- ------------------------------------------------------------
local function PageVersion(host)
    local flavor = ns.Flavor and ns.Flavor() or "era"
    local name = ns.FlavorName and ns.FlavorName(flavor) or flavor
    local y = Title(host, "This game: " .. name,
        "ZacUI runs on Classic Era, TBC, WoW Forever and Retail, and switches off the parts a game does not "
        .. "have. Nothing to set here - this is what " .. name .. " gets.")
    local x = PAD
    -- the badges: every game, this one lit
    local bx = x
    host.badges = {}
    for _, f in ipairs(ns.FLAVORS or { "era", "tbc", "forever", "retail" }) do
        local b = UI.Button(host, ns.FlavorName and ns.FlavorName(f) or f, { width = 96 })
        b:SetPoint("TOPLEFT", host, "TOPLEFT", bx, y)
        b:SetActive(f == flavor)
        b:SetScript("OnClick", nil)
        host.badges[f] = b
        bx = bx + 96 + 6
    end
    y = y - M.BUTTON_H - 10
    if ns.FlavorSimulated and ns.FlavorSimulated() then
        local _, dh = Desc(host, "(Running as " .. name .. " by the developer override on General > Game versions.)",
            x, y, PAGE_W - 2 * PAD)
        y = y - dh - 8
    end
    local off = ns.FeaturesOff and ns.FeaturesOff(flavor) or {}
    local scroll, child = UI.ScrollArea(host)
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(M.SCROLL_W + 4), 8)
    scroll.bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -4, y)
    scroll.bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -4, 8)
    child:SetWidth(PAGE_W - M.SCROLL_W - 8)
    local cy = -2
    local wide = PAGE_W - 2 * PAD - M.SCROLL_W
    if #off == 0 then
        local _, dh = Desc(child, "Everything ZacUI has runs on " .. name .. ".", x, cy, wide)
        cy = cy - dh - 6
    else
        local lbl = Label(child, "Off on " .. name .. " (" .. #off .. ")", x, cy)
        cy = cy - 18
        local KIND = ns.FLAVOR_KIND_NAMES or {}
        for _, f in ipairs(off) do
            local kind = KIND[f.kind] or f.kind or ""
            local fs = UI.Font(child, F.LABEL, { text = f.name .. (kind ~= "" and (" - " .. kind) or ""), width = wide })
            fs:SetPoint("TOPLEFT", child, "TOPLEFT", x, cy)
            cy = cy - math.max(13, fs:GetStringHeight() or 12) - 2
            local _, dh = Desc(child, f.reason, x + 12, cy, wide - 12)
            cy = cy - dh - 8
        end
    end
    local _, dh2 = Desc(child, "The full list, with what runs changed, is on General > Game versions.", x, cy, wide)
    cy = cy - dh2 - 6
    local h = -cy + 4
    child:SetHeight(h)
    if scroll.Recalculate then scroll:Recalculate(h) end
    host.offCount = #off
end

-- ------------------------------------------------------------
-- 3. PARTS
-- ------------------------------------------------------------
local GROUP_ORDER = { "HUD", "Combat", "Windows", "Tools" }

local function PageParts(host)
    local y = Title(host, "Parts",
        "Each part of ZacUI can be on or off. Only the parts you have installed and enabled are listed, "
        .. "each with a glimpse of what it puts on screen. Turning one on applies now; turning one off waits "
        .. "for the reload at the end.")
    local x = PAD
    -- all on / defaults links
    local allOn = UI.Button(host, "All on", { width = 70,
        tooltip = "Ticks every part.",
        onClick = function()
            for _, row in ipairs(S.parts) do
                if not row.spec.get() then
                    pcall(row.spec.set, true)
                    if host.partChecks[row.spec.id] then host.partChecks[row.spec.id]:SetChecked(true) end
                    if host.partMinis[row.spec.id] then Dim(host.partMinis[row.spec.id], true) end
                end
            end
        end })
    allOn:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    local asWas = UI.Button(host, "As they were", { width = 100,
        tooltip = "Puts every part back to the state it had when this window opened.",
        onClick = function()
            for _, row in ipairs(S.parts) do
                local okG, now = pcall(row.spec.get)
                if okG and (now and true or false) ~= row.initial then
                    pcall(row.spec.set, row.initial)
                    if host.partChecks[row.spec.id] then host.partChecks[row.spec.id]:SetChecked(row.initial) end
                    if host.partMinis[row.spec.id] then Dim(host.partMinis[row.spec.id], row.initial) end
                end
            end
        end })
    asWas:SetPoint("LEFT", allOn, "RIGHT", 8, 0)
    y = y - M.BUTTON_H - 10

    local scroll, child = UI.ScrollArea(host)
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(M.SCROLL_W + 4), 26)
    scroll.bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -4, y)
    scroll.bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -4, 26)
    local innerW = PAGE_W - M.SCROLL_W - 8
    child:SetWidth(innerW)
    local cy = -2
    host.partChecks, host.partMinis = {}, {}
    if #S.parts == 0 then
        local _, dh = Desc(child, "No switchable parts are loaded. Parts are separate addons named Zacui_"
            .. "something in your AddOns list.", x, cy, innerW - 2 * PAD)
        cy = cy - dh - 6
    end
    local CARD_H = 72
    for _, g in ipairs(GROUP_ORDER) do
        local rows = {}
        for _, row in ipairs(S.parts) do if (row.spec.group or "Tools") == g then rows[#rows + 1] = row end end
        if #rows > 0 then
            Label(child, g, x, cy)
            cy = cy - 18
            for _, row in ipairs(rows) do
                local s = row.spec
                local card = UI.Box(child, "ui", "cardBg")
                card:SetPoint("TOPLEFT", child, "TOPLEFT", x, cy)
                card:SetSize(innerW - 2 * PAD, CARD_H)
                local mini = Canvas(card, 120, 60)
                mini:SetPoint("LEFT", card, "LEFT", 6, 0)
                DrawMini(mini, s.mini)
                Dim(mini, s.get() and true or false)
                host.partMinis[s.id] = mini
                local cb = UI.Checkbox(card, s.label, s.get() and true or false, function(on)
                    local ok, err = pcall(s.set, on)
                    if not ok then Print("setup: " .. s.label .. ": " .. tostring(err)) end
                    Dim(mini, on)
                    if not on then
                        if ns.Hints then ns.Hints.Say("part_off_reload",
                            "A part turned off finishes at a reload: the last step of the setup has the button.") end
                    end
                end)
                cb:SetPoint("TOPLEFT", card, "TOPLEFT", 134, -10)
                host.partChecks[s.id] = cb
                local text = s.desc
                if s.reload == "always" then text = text .. " Switching it takes a reload." end
                local d = UI.Font(card, F.DESC, { text = text, cat = "text", key = "gray", width = innerW - 2 * PAD - 134 - 8 })
                d:SetPoint("TOPLEFT", card, "TOPLEFT", 134, -30)
                cy = cy - CARD_H - 8
            end
            cy = cy - 6
        end
    end
    local h = -cy + 4
    child:SetHeight(h)
    if scroll.Recalculate then scroll:Recalculate(h) end
    local always = AlwaysOnLoaded()
    if #always > 0 then
        local fs = UI.Font(host, F.DESC, { cat = "text", key = "gray", width = PAGE_W - 2 * PAD,
            text = "Always on while enabled in the AddOns list: " .. table.concat(always, ", ")
                .. ". Each has its own settings page." })
        fs:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", PAD, 6)
    end
end

-- ------------------------------------------------------------
-- 4. LOOK
-- ------------------------------------------------------------
-- The Look job publishes ns.Look (Choices(), Preview(canvas, id),
-- Set(id), Current()); until it has, the step offers the accent colour
-- and the font, as the old quick setup did.
local ACCENTS = {
    { name = "Gold (ZacUI's own)", default = true, r = 0.85, g = 0.65, b = 0.25 },
    { name = "Blue",   r = 0.30, g = 0.60, b = 0.95 },
    { name = "Green",  r = 0.40, g = 0.80, b = 0.45 },
    { name = "Purple", r = 0.66, g = 0.45, b = 0.95 },
    { name = "Red",    r = 0.90, g = 0.35, b = 0.35 },
    { name = "Silver", r = 0.80, g = 0.80, b = 0.82 },
}

local function BuildSample(box)
    Clear(box)
    local head = UI.Font(box, F.CARD, { text = "Sample card", cat = "text", key = "gold" })
    head:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)
    local bar = box:CreateTexture(nil, "ARTWORK")
    bar._zui_own = true
    bar:SetTexture(FLAT)
    bar:SetWidth(3)
    bar:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 1, 1)
    local rule = box:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -28)
    rule:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -28)
    local line = UI.Font(box, F.LABEL, { text = "The quick brown fox jumps over the lazy dog.", width = 196 })
    line:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -38)
    local muted = UI.Font(box, F.DESC, { text = "Descriptions look like this.", cat = "text", key = "gray" })
    muted:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -6)
    local hover = UI.Font(box, F.LABEL, { text = "Hover and focus use the accent.", cat = "ui", key = "accent", width = 196 })
    hover:SetPoint("TOPLEFT", muted, "BOTTOMLEFT", 0, -10)
    local btn = UI.Button(box, "A button", { width = 96 })
    btn:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 12)
    box._zPaint = function(self)
        UI.PaintBox(self)
        local a = GetColor("ui", "accent")
        bar:SetVertexColor(a.r, a.g, a.b, 1)
        rule:SetVertexColor(a.r, a.g, a.b, 0.6)
    end
    box:_zPaint()
end

local function LookReady()
    local L = ns.Look
    return type(L) == "table" and type(L.Choices) == "function" and type(L.Set) == "function"
end

local function PageLook(host)
    local x = PAD
    local y
    if LookReady() then
        -- the look cards: a miniature of each look drawn by the real code
        -- paths (Core_Look), the live one lit; a pick is STAGED (Look.Set)
        -- and written only by the reload at the end (Look.Commit)
        local L = ns.Look
        y = Title(host, "The look",
            "How ZacUI dresses the interface: its own flat dark look, or the game's. Every feature works "
            .. "with every look; a change applies at the reload on the last step. Then your accent colour and font.")
        local ok, choices = pcall(L.Choices)
        choices = ok and type(choices) == "table" and choices or {}
        local live = L.Active and L.Active() or "zacui"
        local pendingId = L.Pending and L.Pending() or nil
        -- the same card row as the Style page and the first-run popup
        -- (Config_Style), scaled to the page; the staged pick lit green
        if L.Cards then
            local n = #choices
            local rowW = n * (L.CARD_W or 188) + (n - 1) * (L.CARD_GAP or 12)
            local room = PAGE_W - 2 * PAD
            local row = L.Cards(host, {
                width = rowW,
                lit = function() return L.Pending and L.Pending() or nil end,
                button = function(id, isCur) return isCur and "Keep this look" or "Pick this look" end,
                onPick = function(id)
                    local name = id
                    for _, ch in ipairs(choices) do if ch.id == id then name = ch.name or id end end
                    if id == live then
                        if L.Discard then L.Discard() end
                        S.notes.look = nil
                    else
                        local okS = pcall(L.Set, id)
                        if not okS then return end
                        Note("look", "Look: " .. name .. " (at the reload)")
                    end
                    if host.lookRow then host.lookRow:Refresh() end
                end,
            })
            local sc = math.min(1, room / math.max(1, rowW))
            row:SetScale(sc)
            row:SetPoint("TOPLEFT", host, "TOPLEFT", x / sc, y / sc)
            host.lookRow, host.lookCards = row, row.cards
            y = y - math.ceil((row:GetHeight() or 0) * sc) - 14
        end
    else
        y = Title(host, "The look",
            "ZacUI's flat dark look, with your accent colour and font. More looks are on the way; "
            .. "the sample on the right follows your choices.")
    end
    local top = y
    Label(host, "Font", x, y)
    y = y - 16
    local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end
    local dd = UI.FontFaceDropdown(host, {
        width = 240,
        defaultLabel = "Blizzard default",
        defaultPath = function() return "Fonts\\FRIZQT__.TTF" end,
        list = function() local m = LSM() return m and m:List("font") or {} end,
        get = function()
            local n = ZacUIDB.font and ZacUIDB.font.name
            return (n and n ~= "") and n or nil
        end,
        set = function(value)
            if ns.Media and ns.Media.SetFont then
                ns.Media.SetFont(value)
            else
                ZacUIDB.font.name = value
                if ns.ApplyFonts then ns.ApplyFonts() end
            end
            if ns.RefreshConfig then ns.RefreshConfig() end
            Note("font", "Font: " .. (value or "Blizzard default"))
            if host.sample then BuildSample(host.sample) end
        end,
    })
    dd:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    host.fontDropdown = dd
    y = y - M.DROPDOWN_H - 14

    Label(host, "Accent colour", x, y)
    y = y - 18
    local chips = CreateFrame("Frame", nil, host)
    chips:SetSize(260, 18)
    chips:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    local prev
    host.accentChips = {}
    for _, a in ipairs(ACCENTS) do
        local chip = CreateFrame("Button", nil, chips)
        chip:SetSize(26, 16)
        local fill = chip:CreateTexture(nil, "BACKGROUND")
        fill._zui_own = true
        fill:SetAllPoints()
        fill:SetColorTexture(a.r, a.g, a.b, 1)
        UI.Border(chip, "ui", "border")
        chip._zPaint = UI.PaintBox
        chip:_zPaint()
        UI.Tooltip(chip, a.name, a.default and "Back to the shipped colour." or nil)
        chip:SetScript("OnClick", function()
            if a.default then
                ns.ResetColor("ui", "accent")
            else
                ns.SetColor("ui", "accent", a.r, a.g, a.b, 1)
            end
            UI.Changed("color")
            Note("accent", "Accent colour: " .. a.name)
            RepaintAll()
        end)
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0) else chip:SetPoint("LEFT") end
        prev = chip
        host.accentChips[#host.accentChips + 1] = chip
    end
    local custom = UI.Swatch(chips, "ui", "accent", function()
        Note("accent", "Accent colour: your own")
        RepaintAll()
    end)
    custom:SetPoint("LEFT", prev, "RIGHT", 14, 0)
    UI.Tooltip(custom, "Any colour", "Opens the colour picker.")
    host.accentCustom = custom
    y = y - 26
    Desc(host, "Rules, hover and focus. Every colour has its own swatch under Appearance > Colours.", x, y, 260)

    local box = UI.Box(host, "ui", "cardBg")
    box:SetSize(220, 170)
    box:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, top)
    host.sample = box
    BuildSample(box)
end

-- ------------------------------------------------------------
-- 5. LAYOUT (Tutorial_Layouts draws the step; this is its frame)
-- ------------------------------------------------------------
local function LayoutReady()
    local LP = ns.LayoutPresets
    return type(LP) == "table" and type(LP.BuildStep) == "function" and LP.Available and LP.Available()
end

local function PageLayout(host)
    local y = Title(host, "Layout",
        "A named arrangement of the frames, bars, meter and minimap for this screen. "
        .. "Preview it on screen first; nothing moves until you apply it.")
    ns.LayoutPresets.BuildStep(host, y, {
        note = Note, needsReload = NeedsReload, pageW = PAGE_W, pad = PAD, canvas = Canvas,
    })
end

-- ------------------------------------------------------------
-- 6. SCALE
-- ------------------------------------------------------------
local function PageScale(host)
    local y = Title(host, "Interface scale",
        "The game's own setting: how big the whole interface is. Pixel-perfect means one interface unit is "
        .. "one pixel of your screen, so every 1 px border stays exactly 1 px.")
    local x, top = PAD, y
    local cur = CurrentScale()
    local rec, exact, physH = Setup.RecommendedScale()
    local picked = cur

    if rec then
        local line = string.format("Recommended for this screen (%d px tall): %s", physH, ScaleText(rec))
        if exact < SCALE_MIN - 1e-6 then
            line = line .. string.format(" (the game's minimum; pixel-perfect would be %s)", ScaleText(exact))
        end
        Label(host, line, x, y)
        y = y - 18
    else
        Label(host, "This client does not say how tall the screen is.", x, y)
        y = y - 18
    end

    local slider = UI.Slider(host, { width = 260, min = SCALE_MIN, max = SCALE_MAX, step = 0.01,
        value = cur, label = "Interface scale",
        format = function(v) return ScaleText(v) .. "  (" .. math.floor(v * 100 + 0.5) .. "%)" end,
        onChange = function(v) picked = v if host.UpdateSample then host.UpdateSample(v) end end })
    slider:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    host.scaleSlider = slider
    y = y - 40

    local function Apply(v)
        if InCombat() then Print("The interface scale can change after combat.") return false end
        if not ns.CVar then return false end
        v = math.floor(v * 10000 + 0.5) / 10000
        ns.CVar.Set("useUiScale", "1", "setup")
        ns.CVar.Set("uiScale", ScaleText(v), "setup")
        Note("scale", "Interface scale: " .. ScaleText(v))
        picked = v
        if host.UpdateSample then host.UpdateSample(v) end
        return true
    end
    local apply = UI.Button(host, "Apply", { width = 70,
        tooltip = "Sets the game's interface scale. The whole screen resizes.",
        onClick = function() Apply(picked) end })
    apply:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    host.scaleApply = apply
    local useRec
    if rec then
        useRec = UI.Button(host, "Use recommended", { width = 130,
            tooltip = "Sets the pixel-perfect scale for this screen.",
            onClick = function()
                if slider.slider then slider.slider:SetValue(rec) end
                Apply(rec)
            end })
        useRec:SetPoint("LEFT", apply, "RIGHT", 8, 0)
        host.scaleRecommend = useRec
    end
    local keep = UI.Button(host, "Keep the game's", { width = 120,
        tooltip = "Leaves the scale exactly as the game has it. Anything this setup set is put back.",
        onClick = function()
            if ns.CVar then ns.CVar.RestoreOwner("setup") end
            S.notes.scale = nil
            picked = CurrentScale()
            if slider.slider then slider.slider:SetValue(picked) end
            if host.UpdateSample then host.UpdateSample(picked) end
        end })
    keep:SetPoint("LEFT", useRec or apply, "RIGHT", 8, 0)
    host.scaleKeep = keep
    y = y - M.BUTTON_H - 12
    Desc(host, "Bigger numbers make everything larger. The scale is the game's setting, so it is the one thing "
        .. "here that is not in a ZacUI profile; it goes back to the game's own if you uninstall ZacUI.",
        x, y, PAGE_W - 2 * PAD - 230)

    -- the sample: a bordered box and a line of text, drawn at the chosen scale
    local box = UI.Box(host, "ui", "cardBg")
    box:SetSize(210, 150)
    box:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, top)
    local inner = UI.Box(box, "ui", "elementBg")
    inner:SetPoint("CENTER", box, "CENTER", 0, 10)
    local txt = UI.Font(inner, F.LABEL, { text = "Zaccw  100%", justify = "CENTER" })
    txt:SetPoint("CENTER")
    local readout = UI.Font(box, F.SMALL, { cat = "text", key = "gray", justify = "CENTER", width = 190 })
    readout:SetPoint("BOTTOM", box, "BOTTOM", 0, 10)
    host.sample, host.sampleInner = box, inner
    host.UpdateSample = function(v)
        local k = v / math.max(0.01, cur)
        inner:SetSize(math.floor(120 * k + 0.5), math.floor(40 * k + 0.5))
        local px = physH and string.format("1 px border = %.2f screen px", (768 / v) / physH) or "sample"
        readout:SetText(string.format("%s at scale %s", px, ScaleText(v)))
    end
    host.UpdateSample(cur)
end

-- ------------------------------------------------------------
-- 7. SCREEN: chat, minimap, tooltips
-- ------------------------------------------------------------
local function PageScreen(host)
    local y = Title(host, "Chat, minimap and tooltips",
        "The three things always on screen. On or off, and the one or two basics each; the pages have the rest.")
    local x = PAD
    local colW = math.floor((PAGE_W - 2 * PAD - 16) / 3)
    host.screenChecks = {}
    local function Column(i, title, kind, items)
        local cx = x + (i - 1) * (colW + 8)
        local card = UI.Box(host, "ui", "cardBg")
        card:SetPoint("TOPLEFT", host, "TOPLEFT", cx, y)
        card:SetSize(colW, 300)
        local head = UI.Font(card, F.CARD, { text = title, cat = "text", key = "gold" })
        head:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
        local mini = Canvas(card, 120, 60)
        mini:SetPoint("TOP", card, "TOP", 0, -28)
        DrawMini(mini, kind)
        local cy = -96
        local onItem
        for _, it in ipairs(items) do
            local okG, v = pcall(it.get)
            local cb = UI.Checkbox(card, it.label, okG and v and true or false, function(on)
                local ok, err = pcall(it.set, on)
                if not ok then Print("setup: " .. it.label .. ": " .. tostring(err)) end
                Note("screen:" .. title .. ":" .. it.label, title .. ": " .. it.label .. (on and " on" or " off"))
                if it.master then Dim(mini, on) end
            end, { tooltip = it.tip })
            cb:SetPoint("TOPLEFT", card, "TOPLEFT", 10, cy)
            host.screenChecks[title .. ":" .. it.label] = cb
            if it.master then onItem = it Dim(mini, okG and v and true or false) end
            cy = cy - M.ROW
        end
        return card
    end

    local cols = 0
    -- chat
    -- (reads are from the raw saved table with the page's defaults, so a
    -- page build writes nothing; a change goes through the module's DB()
    -- and Refresh(), as the Chat page does)
    if ns.Chat and ns.Chat.DB then
        local C = ns.Chat
        local function Raw(key, default)
            local d = ZacUIDB.chat
            local v = type(d) == "table" and d[key] or nil
            if v == nil then return default end
            return v
        end
        local items = {
            { label = "ZacUI chat", master = true, get = ModulesGet({ "chat" }), set = ModulesSet({ "chat" }),
              tip = "Chat windows on dark panels with flat tabs and the bar under the chat. Off waits for the reload." },
            { label = "The bar under the chat", get = function() return Raw("bar", true) ~= false end,
              set = function(on) C.DB().bar = on and true or false C.Refresh() end },
            { label = "Type in the bar", get = function() return Raw("editBox", "bar") == "bar" end,
              set = function(on) C.DB().editBox = on and "bar" or "below" C.Refresh() end,
              tip = "The edit box opens in the bar; off, it opens below the chat." },
            { label = "Tab strip", get = function() return Raw("tabStrip", true) ~= false end,
              set = function(on) C.DB().tabStrip = on and true or false C.Refresh() end },
            { label = "Fade when idle", get = function() return Raw("fade", false) == true end,
              set = function(on) C.DB().fade = on and true or false C.Refresh() end },
        }
        cols = cols + 1
        Column(cols, "Chat", "chat", items)
    end
    -- minimap
    if ns.MinimapOptions and ns.MinimapOptions.DB then
        local MM = ns.MinimapOptions
        local function On(key)
            local d = ZacUIDB.minimap
            local v = type(d) == "table" and d[key] or nil
            return v == nil or v == true
        end
        local function Piece(key, on)
            MM.DB()[key] = on and true or false
            if MM.SetShown then pcall(MM.SetShown, key, on) end
        end
        local items = {
            { label = "ZacUI minimap", master = true, get = ModulesGet({ "minimap" }), set = ModulesSet({ "minimap" }),
              tip = "The square minimap in one ZacUI frame. Off waits for the reload." },
            { label = "Zone name", get = function() return On("zoneName") end, set = function(on) Piece("zoneName", on) end },
            { label = "Clock", get = function() return On("clock") end, set = function(on) Piece("clock", on) end },
            { label = "Coordinates", get = function() return On("coords") end, set = function(on) Piece("coords", on) end },
            { label = "Button tray", get = ModulesGet({ "tray" }), set = ModulesSet({ "tray" }),
              tip = "Sweeps every addon's minimap button into one bar with a flyout tray." },
        }
        cols = cols + 1
        Column(cols, "Minimap", "minimap", items)
    end
    -- tooltips
    if ns.TipCfg then
        local function Hide()
            if type(ZacUIDB.tooltipHide) ~= "table" then ZacUIDB.tooltipHide = { combat = true, raid = true } end
            return ZacUIDB.tooltipHide
        end
        local function RawTip(key, default)
            local d = ZacUIDB.tooltip
            local v = type(d) == "table" and d[key] or nil
            if v == nil then return default end
            return v
        end
        local function RawHide(key)
            local d = ZacUIDB.tooltipHide
            local v = type(d) == "table" and d[key] or nil
            return v ~= false
        end
        local items = {
            { label = "ZacUI tooltips", master = true, get = ModulesGet({ "tooltip" }), set = ModulesSet({ "tooltip" }),
              tip = "Every tooltip in the game in ZacUI's look, plus a movable anchor. Off waits for the reload." },
            { label = "Follow the cursor", get = function() return RawTip("cursor", false) and true or false end,
              set = function(on) ns.TipCfg().cursor = on and true or false end },
            { label = "Health as text", get = function() return RawTip("healthText", true) ~= false end,
              set = function(on) ns.TipCfg().healthText = on and true or false end },
            { label = "Hide unit tooltips in combat", get = function() return RawHide("combat") end,
              set = function(on) Hide().combat = on and true or false end },
            { label = "Hide unit tooltips in raids", get = function() return RawHide("raid") end,
              set = function(on) Hide().raid = on and true or false end },
        }
        cols = cols + 1
        Column(cols, "Tooltips", "tooltip", items)
    end
    host.screenColumns = cols
    if cols == 0 then
        Desc(host, "The chat, minimap and tooltip modules did not load.", x, y, PAGE_W - 2 * PAD)
    end
end

-- ------------------------------------------------------------
-- 8. PROFILE
-- ------------------------------------------------------------
local function PageProfile(host)
    local P = ns.Profiles
    local y = Title(host, "Profile",
        "Every ZacUI setting lives in a named profile, and each character wears one. Keep going with this "
        .. "character's, take over a profile another character wears, or paste a profile string.")
    local x = PAD
    if not P then
        Desc(host, "The profile system did not load.", x, y, PAGE_W - 2 * PAD)
        return
    end
    local cur = P.Current() or P.DefaultName()
    local summary = UI.Box(host, "ui", "cardBg")
    summary:SetSize(220, 150)
    summary:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, y)
    local sHead = UI.Font(summary, F.CARD, { cat = "text", key = "gold", width = 200 })
    sHead:SetPoint("TOPLEFT", summary, "TOPLEFT", 10, -8)
    local sBody = UI.Font(summary, F.DESC, { cat = "text", key = "gray", width = 200 })
    sBody:SetPoint("TOPLEFT", sHead, "BOTTOMLEFT", 0, -6)
    host.profileSummary = summary
    local function Refresh()
        local name = P.Current() or P.DefaultName()
        local worn = P.UsedBy(name)
        local store = P.Store()[name]
        local sections = store and P.SectionsIn(store) or {}
        sHead:SetText("This character wears: " .. name)
        local who = {}
        for _, ck in ipairs(worn) do who[#who + 1] = (ck:match("^(.-) %- ") or ck) end
        sBody:SetText((#sections > 0 and (#sections .. " sections of settings. ") or "")
            .. "Worn by " .. (#who > 0 and table.concat(who, ", ") or "nobody yet") .. ".")
    end
    host.RefreshProfile = Refresh
    Refresh()

    local wide = PAGE_W - 2 * PAD - 236
    Label(host, "Keep going", x, y)
    y = y - 16
    local _, dh = Desc(host, "Nothing to do: this character keeps the profile it wears (" .. cur .. ").", x, y, wide)
    y = y - dh - 12

    Label(host, "Take over a profile another character wears", x, y)
    y = y - 18
    local chosen
    local dd = UI.Dropdown(host, { width = 200,
        items = function()
            local out = {}
            for _, n in ipairs(P.List()) do
                local who = P.UsedBy(n)
                out[#out + 1] = { text = n .. (#who > 0 and ("  (" .. #who .. ")") or ""), value = n }
            end
            return out
        end,
        selected = function() return chosen or "Pick a profile" end,
        onSelect = function(v) chosen = v end })
    dd:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    dd:SetText(chosen or "Pick a profile")
    host.profileDropdown = dd
    local use = UI.Button(host, "Wear it", { width = 80,
        tooltip = "This character switches to that profile; what it had is written back to its old one first.",
        onClick = function()
            if not chosen then Print("Pick a profile first.") return end
            local ok, err = P.Use(chosen)
            if ok then
                Note("profile", "Profile: now wearing " .. chosen)
                NeedsReload("profile", "The profile switch")
                Refresh()
                RepaintAll()
            else
                Print("setup: " .. tostring(err))
            end
        end })
    use:SetPoint("LEFT", dd, "RIGHT", 8, 0)
    host.profileUse = use
    y = y - M.DROPDOWN_H - 6
    local own = UI.Button(host, "Give this character its own copy", { width = 220,
        tooltip = "Copies the profile this character wears into a new one named after the character, and wears that. "
            .. "Changes here then never reach your other characters.",
        onClick = function()
            local name = (UnitName and UnitName("player")) or "This character"
            local target = name
            local n = 2
            while P.Store()[target] do target = name .. " " .. n n = n + 1 end
            local ok, err = P.New(target, false)
            if ok then
                P.Use(target)
                Note("profile", "Profile: own copy '" .. target .. "'")
                Refresh()
            else
                Print("setup: " .. tostring(err))
            end
        end })
    own:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    host.profileOwn = own
    y = y - M.BUTTON_H - 14

    Label(host, "Paste a profile string", x, y)
    y = y - 18
    local box = UI.TextBox(host, { width = wide, height = 56 })
    box:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    host.importBox = box
    y = y - 56 - 6
    local imp = UI.Button(host, "Import", { width = 90,
        tooltip = "Reads the string (a ZacUI profile, bar loadout, unit frame or buff string) and applies it.",
        onClick = function()
            local text = box:GetText() or ""
            if text:match("^%s*$") then Print("Paste a string first.") return end
            if not ns.Import then Print("The importer did not load.") return end
            local ok, msg, res = ns.Import.Run(text, nil, {})
            if ok then
                Note("import", "Imported: " .. tostring(msg or "a string"))
                if type(res) == "table" and res.reload then NeedsReload("import", "The imported settings") end
                Refresh()
                RepaintAll()
            else
                Print("Import: " .. tostring(msg))
            end
        end })
    imp:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    host.importButton = imp
end

-- ------------------------------------------------------------
-- 9. DONE
-- ------------------------------------------------------------
function Setup.ReloadNeeded()
    local out = {}
    if not S then return out end
    for _, row in ipairs(S.parts) do
        local okG, now = pcall(row.spec.get)
        now = okG and now and true or false
        if now ~= row.initial then
            local r = row.spec.reload
            if r == "always" or (r == "off" and not now) then
                out[#out + 1] = row.spec.label .. (now and " (on)" or " (off)")
            end
        end
    end
    local keys = {}
    for k in pairs(S.reloadExtra) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do out[#out + 1] = S.reloadExtra[k] end
    -- a staged look (Core_Look): written by the reload, so it waits for one
    if LookReady() and ns.Look.Dirty and ns.Look.Dirty() then out[#out + 1] = "The look" end
    return out
end

-- The one reload: asked for FIRST, at the start of the click (WoW Forever
-- turns down a reload asked for after the click has saved things, build
-- 70425; UIF_Dialogs' ns.AskReload has the long note), then a staged look
-- is written (Look.Commit is its only writer) - still inside the click,
-- so it is what the reload saves.
local function ReloadNow()
    if ns.RequestReload then ns.RequestReload()
    elseif type(ReloadUI) == "function" then ReloadUI()
    elseif C_UI and C_UI.Reload then C_UI.Reload() end
    if LookReady() and ns.Look.Commit then pcall(ns.Look.Commit) end
end
Setup.ReloadNow = ReloadNow

local function PageDone(host)
    local y = Title(host, "All set",
        "Everything here can be changed again on the settings pages. Type /zui to open them, "
        .. "/zui setup to run this again.")
    local lines = {}
    for _, key in ipairs(S.noteOrder) do if S.notes[key] then lines[#lines + 1] = S.notes[key] end end
    local on, off = {}, {}
    for _, row in ipairs(S.parts) do
        local okG, now = pcall(row.spec.get)
        now = okG and now and true or false
        if now ~= row.initial then
            if now then on[#on + 1] = row.spec.label else off[#off + 1] = row.spec.label end
        end
    end
    if #on > 0 then lines[#lines + 1] = "Turned on: " .. table.concat(on, ", ") end
    if #off > 0 then lines[#lines + 1] = "Turned off: " .. table.concat(off, ", ") end
    if #lines == 0 then lines[1] = "Nothing was changed - ZacUI keeps its defaults." end
    for _, l in ipairs(lines) do
        local dash = UI.Font(host, F.LABEL, { text = "-", cat = "text", key = "gray" })
        dash:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, y)
        local fs = UI.Font(host, F.LABEL, { text = l, width = PAGE_W - 2 * PAD - 14 })
        fs:SetPoint("TOPLEFT", host, "TOPLEFT", PAD + 12, y)
        y = y - math.max(13, fs:GetStringHeight() or 12) - 5
    end
    y = y - 10

    local reload = Setup.ReloadNeeded()
    host.reloadButton = nil
    if #reload > 0 then
        local _, dh = Desc(host, "These take a reload to finish: " .. table.concat(reload, ", ") .. ".",
            PAD, y, PAGE_W - 2 * PAD)
        y = y - dh - 8
        local rb = UI.Button(host, "Reload now", { width = 110, onClick = ReloadNow })
        rb:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, y)
        rb:SetActive(true)
        host.reloadButton = rb
        y = y - M.BUTTON_H - 16
    end

    Label(host, "Commands", PAD, y)
    y = y - 16
    local _, ch = Desc(host, "/zui opens the settings. /zui setup runs this again. /zui tour shows you around the "
        .. "settings window. /zui edit arranges every frame over a grid. /zui hints reset brings every one-time "
        .. "tip back.", PAD, y, PAGE_W - 2 * PAD)
    y = y - ch - 14

    Label(host, "Where next", PAD, y)
    y = y - 20
    local open = UI.Button(host, "Open settings", { width = 120,
        tooltip = "Every setting, page by page.",
        onClick = function()
            Setup.Close()
            if ns.OpenConfig then ns.OpenConfig() end
        end })
    open:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, y)
    local unlock = UI.Button(host, "Unlock frames (Edit Mode)", { width = 190,
        tooltip = "Shows every movable ZacUI frame over a grid. Drag them into place, then lock.",
        onClick = function()
            Setup.Close()
            if ns.EnterEditMode then ns.EnterEditMode() end
        end })
    unlock:SetPoint("LEFT", open, "RIGHT", 8, 0)
    local tour = UI.Button(host, "Take the tour", { width = 120,
        tooltip = "Shows you around the settings window.",
        onClick = function()
            Setup.Close()
            if T() then T().StartTour() end
        end })
    tour:SetPoint("LEFT", unlock, "RIGHT", 8, 0)
    host.openButton, host.unlockButton, host.tourButton = open, unlock, tour
end

-- ============================================================
-- THE STEPS
-- ============================================================
local ALL_STEPS = {
    { id = "welcome", title = "Welcome", blurb = "what this does", build = PageWelcome },
    { id = "version", title = "Game version", blurb = "what this game runs and what is off here", build = PageVersion,
      available = function() return ns.Flavor ~= nil end },
    { id = "parts", title = "Parts", blurb = "which parts of ZacUI are on", build = PageParts },
    { id = "look", title = "Look", blurb = "the accent colour and font, or a whole look", build = PageLook },
    { id = "layout", title = "Layout", blurb = "a named arrangement of the frames for this screen", build = PageLayout,
      available = LayoutReady },
    { id = "scale", title = "Scale", blurb = "the interface scale, pixel-perfect for this screen", build = PageScale,
      available = function() return ns.CVar ~= nil end },
    { id = "screen", title = "Screen", blurb = "chat, minimap and tooltips", build = PageScreen,
      available = function() return (ns.Chat and ns.Chat.DB) or ns.MinimapOptions or ns.TipCfg end },
    { id = "profile", title = "Profile", blurb = "keep going, copy one, or paste a string", build = PageProfile,
      available = function() return ns.Profiles ~= nil end },
    { id = "done", title = "All set", blurb = "", build = PageDone },
}

local function BuildSteps()
    local out = {}
    for _, st in ipairs(ALL_STEPS) do
        local ok, avail = pcall(function() return (not st.available) or st.available() end)
        if ok and avail then out[#out + 1] = st end
    end
    return out
end

-- ============================================================
-- PAGING
-- ============================================================
local function PaintRail()
    for i, row in ipairs(rail.rows) do
        local st = steps[i]
        row.num:SetText(S.visited[st.id] and i < index and "+" or tostring(i))
        if i == index then
            row.title._zPaintCat, row.title._zPaintKey = "text", "gold"
            row.mark:Show()
        else
            row.title._zPaintCat, row.title._zPaintKey = "text", S.visited[st.id] and "normal" or "gray"
            row.mark:Hide()
        end
        row.title:_zPaint()
        row.num:_zPaint()
    end
end

local function ShowPage(i)
    index = math.max(1, math.min(#steps, i))
    S.visited[steps[index].id] = true
    DB().step = index
    Clear(pagesHost)
    local host = CreateFrame("Frame", nil, pagesHost)
    host:SetAllPoints(pagesHost)
    local ok, err = pcall(steps[index].build, host)
    if not ok then Print("setup: " .. steps[index].id .. ": " .. tostring(err)) end
    frame.page = host
    frame.pageId = steps[index].id
    frame.counter:SetText(index .. " of " .. #steps)
    frame.back:SetShown(index > 1)
    frame.skip:SetShown(index > 1 and index < #steps)
    frame.next:SetLabel(index == #steps and "Finish" or "Next")
    frame.next:SetActive(index == #steps)
    PaintRail()
end

local function BuildRail(f)
    rail = CreateFrame("Frame", nil, f)
    rail:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -(f.headerHeight + 1))
    rail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, FOOT_H)
    rail:SetWidth(RAIL_W)
    UI.Fill(rail, "ui", "headerBg", 0.6)
    local edge = rail:CreateTexture(nil, "ARTWORK")
    edge._zui_own = true
    edge:SetTexture(FLAT)
    edge:SetWidth(1)
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    rail._zPaint = function(self)
        UI.PaintBox(self)
        local b = GetColor("ui", "border")
        edge:SetVertexColor(b.r, b.g, b.b, 1)
    end
    rail:_zPaint()
    rail.rows = {}
end

local function FillRail()
    for _, row in ipairs(rail.rows) do row:Hide() end
    for i, st in ipairs(steps) do
        local row = rail.rows[i]
        if not row then
            row = CreateFrame("Button", nil, rail)
            row:SetHeight(M.ROW_H)
            row:SetPoint("TOPLEFT", rail, "TOPLEFT", 0, -8 - (i - 1) * M.ROW_H)
            row:SetPoint("RIGHT", rail, "RIGHT", -1, 0)
            row.mark = row:CreateTexture(nil, "ARTWORK")
            row.mark._zui_own = true
            row.mark:SetTexture(FLAT)
            row.mark:SetWidth(3)
            row.mark:SetPoint("TOPLEFT")
            row.mark:SetPoint("BOTTOMLEFT")
            row.num = UI.Font(row, F.SMALL, { cat = "text", key = "gray", width = 16, justify = "RIGHT" })
            row.num:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.title = UI.Font(row, F.NAV, { cat = "text", key = "gray" })
            row.title:SetPoint("LEFT", row.num, "RIGHT", 8, 0)
            row._zPaint = function(self)
                local a = GetColor("ui", "accent")
                self.mark:SetVertexColor(a.r, a.g, a.b, 1)
                self.title:_zPaint()
                self.num:_zPaint()
            end
            row:_zPaint()
            rail.rows[i] = row
        end
        row.title:SetText(st.title)
        row:SetScript("OnClick", function() ShowPage(i) end)
        row:Show()
    end
end

local function Build()
    local f = UI.Window("ZacUISetupFrame", W, H, "Setup")
    f:SetPoint("CENTER", 0, 30)
    BuildRail(f)

    pagesHost = CreateFrame("Frame", nil, f)
    pagesHost:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
    pagesHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, FOOT_H)
    pagesHost:SetSize(PAGE_W, H - f.headerHeight - FOOT_H - 1)

    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    foot:SetHeight(FOOT_H - 2)
    local rule = foot:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT")
    foot._zPaint = function()
        local b = GetColor("ui", "border")
        rule:SetVertexColor(b.r, b.g, b.b, 1)
    end
    foot:_zPaint()
    f.counter = UI.Font(foot, F.SMALL, { cat = "text", key = "gray" })
    f.counter:SetPoint("LEFT", foot, "LEFT", PAD, 0)
    f.skip = UI.Button(foot, "Skip this step", { width = 110,
        tooltip = "Leaves this step as it is and moves on.",
        onClick = function() if index < #steps then ShowPage(index + 1) end end })
    f.skip:SetPoint("LEFT", f.counter, "RIGHT", 14, 0)
    f.next = UI.Button(foot, "Next", { width = 90, onClick = function()
        if index >= #steps then
            DB().done = true
            Setup.Close()
        else
            ShowPage(index + 1)
        end
    end })
    f.next:SetPoint("RIGHT", foot, "RIGHT", -PAD, 0)
    f.back = UI.Button(foot, "Back", { width = 70, onClick = function() ShowPage(index - 1) end })
    f.back:SetPoint("RIGHT", f.next, "LEFT", -8, 0)

    f:HookScript("OnHide", function(self)
        UI.CloseAllDropdowns()
        if self._zCombatHide then return end
        local st = T() and T().DB()
        if st and index == #steps then st.setupDone = true end
        -- the profile this character wears picks up what was picked
        if ns.Profiles and ns.Profiles.WriteBack then pcall(ns.Profiles.WriteBack) end
    end)
    frame = f
    return f
end

-- ============================================================
-- OPEN / CLOSE, COMBAT
-- ============================================================
-- the combat watch is made on first use (an open, or an open refused in
-- combat): a closed setup has no frame and no event at all
local watch, OnWatch
local function Watch()
    if not watch then
        watch = CreateFrame("Frame")
        watch:SetScript("OnEvent", OnWatch)
    end
    return watch
end
local pendingReopen = false

function Setup.Open()
    if InCombat() then
        Print("The setup opens after combat.")
        pendingReopen = true
        Watch():RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    if frame and frame:IsShown() and not frame._zAnim then
        frame:Raise()
        return true
    end
    if not frame then Build() end
    local d = DB()
    d.version = Setup.VERSION
    S = { notes = {}, noteOrder = {}, parts = {}, visited = {}, reloadExtra = {} }
    for _, spec in ipairs(Setup.Parts()) do
        local okG, v = pcall(spec.get)
        S.parts[#S.parts + 1] = { spec = spec, initial = (okG and v) and true or false }
    end
    steps = BuildSteps()
    FillRail()
    ShowPage(1)
    Watch():RegisterEvent("PLAYER_REGEN_DISABLED")
    UI.OpenWindow(frame)
    return true
end

function Setup.Close()
    if watch then watch:UnregisterEvent("PLAYER_REGEN_DISABLED") end
    if frame and frame:IsShown() then UI.CloseWindow(frame) end
end

function Setup.IsShown()
    return frame ~= nil and frame:IsShown()
end

-- open, or put away for a fight and coming back after it: the login popup
-- queue (Core_Popups) waits while this is true
function Setup.Busy()
    return (frame ~= nil and frame:IsShown()) or pendingReopen or false
end

OnWatch = function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if frame and frame:IsShown() then
            frame._zCombatHide = true
            if ns.StopAnim then ns.StopAnim(frame) end
            frame:Hide()
            frame._zCombatHide = nil
            pendingReopen = true
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingReopen then
            pendingReopen = false
            C_Timer.After(1, function()
                if InCombat() then return end
                if frame and S then
                    UI.OpenWindow(frame)
                    self:RegisterEvent("PLAYER_REGEN_DISABLED")
                else
                    Setup.Open()
                end
            end)
        end
    end
end

-- for the tests: the window, the page on screen and its id
function Setup.Frame() return frame end
function Setup.Page() return frame and frame.page, frame and frame.pageId end
function Setup.Go(i) if frame and steps then ShowPage(i) end end
function Setup.PageIds()
    local out = {}
    for _, p in ipairs(steps or {}) do out[#out + 1] = p.id end
    return out
end
function Setup.Index() return index end

-- ============================================================
-- THE GENERAL PAGE'S CARD
-- ============================================================
-- Right under the Getting started card: the one-time hints and the way
-- out. Buttons only: a page build must not write anything.
function ns.SetupCard(L)
    local card = L:Card("Setup, hints and reset")
    L:Desc("The setup runs again any time with its current values. One-time hints are the tips ZacUI "
        .. "shows once; Reset hints brings them (and the welcome) back. Reset ZacUI starts over from a "
        .. "fresh install: every ZacUI setting is cleared and every game setting ZacUI changed goes back.")
    L:Gap(4)
    local run = UI.Button(card, "Run the setup", { width = 120,
        tooltip = "The step-by-step setup. /zui setup does the same.",
        onClick = function() Setup.Open() end })
    local hints = UI.Button(card, "Reset hints", { width = 100,
        tooltip = "Every one-time tip shows again, and the welcome comes back at your next login. /zui hints reset does the same.",
        onClick = function()
            if ns.Hints then ns.Hints.Reset() end
            Print("Hints reset - every one-time tip shows again, and the welcome at your next login.")
        end })
    local uninstall = UI.Button(card, "Reset ZacUI", { width = 130,
        tooltip = "Clears every ZacUI setting (account-wide and this character's: positions, colours, "
            .. "profiles, everything) and puts back every game setting ZacUI changed (interface scale, "
            .. "nameplate and screen effect settings and the rest), then reloads into a fresh install. "
            .. "ZacUI stays on. /zui reset all does the same.",
        onClick = function() Setup.Uninstall() end })
    L:Flow({ run, hints, uninstall })
    L:EndCard()
    return card
end

function Setup.Uninstall()
    if not (ns.CVar and ns.CVar.ResetAll) then Print("The reset helper did not load.") return end
    if InCombat() then Print("Reset cannot run in combat.") return end
    UI.Confirm({
        title = "Reset ZacUI",
        text = "Every ZacUI setting is cleared (account-wide and this character's), every game setting "
            .. "ZacUI changed goes back to what it was, and the interface reloads into a fresh install with "
            .. "the setup. ZacUI stays on. This cannot be undone; export a profile first if you want a copy.",
        acceptText = "Reset and reload",
        onAccept = function()
            -- the reset refuses in combat: say so before asking for anything
            if InCombat() then Print("Reset could not run right now (in combat). Try again after the fight.") return end
            -- the reload first, then the reset's writes (ReloadNow's note)
            if ns.RequestReload then ns.RequestReload()
            elseif type(ReloadUI) == "function" then ReloadUI()
            elseif C_UI and C_UI.Reload then C_UI.Reload() end
            local ok = ns.CVar.ResetAll()
            if not ok then Print("Reset could not run right now (in combat?). Try again after the fight.") end
        end,
    })
end

-- shared with later ZacUI files
ns.TutorialSetup = Setup
