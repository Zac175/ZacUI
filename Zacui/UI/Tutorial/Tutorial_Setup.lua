-- Tutorial_Setup - quick setup: a short window of a few screens that sets
-- the basics a new player wants first.
-- Part of ZacUI; load order is set by the TOC (after Tutorial_Core).
--
--   1. The look      interface scale, ZacUI's font, the accent colour
--   2. Parts         which installed parts of ZacUI are on
--   3. Frames        unit frame and nameplate basics (only when loaded)
--   4. Done          what changed, Reload when something needs it, and
--                    the ways on: settings, Edit Mode, the tour
--
-- EVERYTHING IS OPTIONAL and nothing is written until a control is used.
-- Each control writes through the very setter its settings page uses
-- (Media.SetFont, ns.SetColor / ns.ResetColor, EnableModuleLive, the
-- parts' own SetOn / SetEnabled / Start / Stop, the frame engines' own
-- refresh), so profiles, previews and live refresh behave exactly as they
-- do from the pages. Like the pages, a choice applies the moment it is
-- made; there is no separate commit, and closing the window keeps what was
-- already picked.
--
-- RELOADS are collected, not asked for one by one: a part turned off (or
-- one that only switches at a reload) is listed on the last screen with a
-- single Reload button. A part toggled and toggled back counts as nothing.
--
-- The one setting here that is not ZacUI's is the interface scale - the
-- game's own (the uiScale console variable), applied with its own button
-- and never in combat.
--
--   ns.TutorialSetup.Open()
--   ns.TutorialSetup.Close()
--   ns.TutorialSetup.IsShown()
--   ns.TutorialSetup.Parts()        the part rows this install would list
--   ns.TutorialSetup.ReloadNeeded() labels of what waits for a reload

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Print = ns.Print
local UI = ns.UI

local M, F = UI.M, UI.F

local Setup = {}

local W, H = 560, 480
local PAD = 20
local FOOT_H = 44

local function T() return ns.Tutorial end
local function InCombat() return T() and T().InCombat() or false end

-- ============================================================
-- SETTERS (the pages' own)
-- ============================================================
-- A module that already ran this session only needs its switch back on;
-- EnableModuleLive would say so in chat once per module, and the game
-- windows are thirty-odd modules.
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
            if on then ModuleOn(k) else ZacUIDB.modules[k] = false end
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
-- needs a reload, on applies live - every ZacUI module), "always" (either
-- way waits for a reload), nil (live both ways).
local function PartSpecs()
    local specs = {}
    local function Module(addon, label, desc, keys)
        specs[#specs + 1] = { id = "mod:" .. keys[1], addon = addon, label = label, desc = desc,
            get = ModulesGet(keys), set = ModulesSet(keys), reload = "off" }
    end
    Module("Zacui_Bars", "Action bars",
        "Ten bars plus pet, stance and bag bars, each placed, scaled and faded your way.", { "bars" })
    Module("Zacui_Nameplates", "Nameplates",
        "Health, cast bars, debuffs and threat colours on the plates over enemies.", { "nameplates" })
    Module("Zacui_Meter", "Damage meter", "Damage, healing and threat for you and your group.", { "meter" })
    Module("Zacui_Bags", "Combined bag", "One window for every bag, with search and sorting.", { "inventory" })
    Module("Zacui_Bags", "Auction house", "Search, sell and cancel tabs, with a memory of prices you have seen.",
        { "auctionhouse" })
    Module("Zacui_Maps", "Maps",
        "A movable world map with unexplored areas shown, flight points and dungeon entrances.", { "maps" })
    Module("Zacui_QoL", "Quality of life",
        "Sell junk, repair, skip gossip, faster looting and other small helpers.", { "qol" })
    local winKeys = WindowKeys()
    if #winKeys > 0 then
        Module("Zacui_Windows", "Game windows",
            "ZacUI's own character sheet, spellbook, talents, quest log, mail, social and more.", winKeys)
    end
    specs[#specs + 1] = { id = "sbt", addon = "Zacui_SBT", label = "Scrolling text",
        desc = "Damage, healing and alerts scrolling around your character.",
        ready = function() return ns.SBT and ns.SBT.IsOn and ns.SBT.SetOn end,
        get = function() return ns.SBT.IsOn() end,
        set = function(on) ns.SBT.SetOn(on) end }
    specs[#specs + 1] = { id = "blessings", addon = "Zacui_Blessings", label = "Blessings",
        desc = "Who blesses which class, shared with the paladins in your group.",
        ready = function() local BL = ns.Blessings return BL and BL.Cfg and BL.Cfg() end,
        get = function() return ns.Blessings.Cfg().enabled and true or false end,
        set = function(on)
            local BL = ns.Blessings
            BL.Cfg().enabled = on and true or false
            if on then BL.Start() else BL.Stop() end
            if BL.Bar and BL.Bar.Refresh then BL.Bar.Refresh() end
        end }
    specs[#specs + 1] = { id = "clickcast", addon = "Zacui_Clicks", label = "Click casting",
        desc = "Spells and macros on mouse buttons and keys over your unit frames.",
        ready = function() local CC = ns.ClickCast return CC and CC.Cfg and CC.Cfg() and CC.SetEnabled and not CC.standDown end,
        get = function() return ns.ClickCast.Cfg().enabled and true or false end,
        set = function(on) ns.ClickCast.SetEnabled(on) end }
    specs[#specs + 1] = { id = "raidmods", addon = "Zacui_RaidMods", label = "Raid mods",
        desc = "Timers, warnings and marks for the bosses of the classic raids.",
        ready = function() local RM = ns.RaidMods return RM and RM.DB and RM.DB() end,
        get = function() return ns.RaidMods.DB().enabled and true or false end,
        set = function(on)
            local RM = ns.RaidMods
            RM.DB().enabled = on and true or false
            if RM.UnloadAll then RM.UnloadAll() end
            if RM.ScanForLoads then RM.ScanForLoads() end
        end }
    specs[#specs + 1] = { id = "worldmap", addon = "Zacui_WorldMap", label = "Seamless world map",
        desc = "Every zone stitched into one map you can zoom across.", reload = "always",
        ready = function() return WorldMapDB() end,
        get = function() return WorldMapDB().enabled and true or false end,
        set = function(on) WorldMapDB().enabled = on and true or false end }
    specs[#specs + 1] = { id = "auras", addon = "Zacui_Auras", label = "Aura engine",
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

local function Loaded(addon)
    return ns.AddonLoaded and ns.AddonLoaded(addon) or false
end

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
-- FRAME BASICS
-- ============================================================
local function UF()
    local Z = _G.ZacUF
    if Z and type(Z.db) == "table" and Z.ApplySettings then return Z end
end
local function NP()
    local P = ns.Nameplates
    if P and P.DB and P.RefreshAll then return P end
end

local function FrameGroups()
    local groups = {}
    local Z = UF()
    if Z and Loaded("Zacui_UnitFrames") then
        local list = {}
        local function Frame(key, label)
            if type(Z.db.frames) == "table" and type(Z.db.frames[key]) == "table" then
                list[#list + 1] = { label = label,
                    get = function() return Z.db.frames[key].enabled end,
                    set = function(v) Z.db.frames[key].enabled = v end }
            end
        end
        Frame("player", "Player")
        Frame("target", "Target")
        Frame("targettarget", "Target of target")
        Frame("pet", "Pet")
        for _, g in ipairs({ { "party", "Party frames" }, { "raid", "Raid frames" } }) do
            if type(Z.db[g[1]]) == "table" then
                local key = g[1]
                list[#list + 1] = { label = g[2],
                    get = function() return Z.db[key].enabled end,
                    set = function(v) Z.db[key].enabled = v end }
            end
        end
        if #list > 0 then
            groups[#groups + 1] = { title = "Unit frames", desc = "Which of ZacUI's unit frames are shown.",
                list = list, apply = function() Z.ApplySettings() end }
        end
    end
    local P = NP()
    if P and Loaded("Zacui_Nameplates") then
        local ok, d = pcall(P.DB)
        if ok and type(d) == "table" then
            local list = {
                { label = "Friendly NPC plates", get = function() return P.DB().friendlyNpcPlates end,
                  set = function(v) P.DB().friendlyNpcPlates = v end },
                { label = "Stacking plates", get = function() return P.DB().stacking end,
                  set = function(v) P.DB().stacking = v end },
            }
            if type(d.enemy) == "table" then
                list[#list + 1] = { label = "Cast bars on enemy plates", get = function() return P.DB().enemy.castbar end,
                    set = function(v) P.DB().enemy.castbar = v end }
            end
            groups[#groups + 1] = { title = "Nameplates",
                desc = "Stacking pushes plates apart instead of letting them overlap.",
                list = list, apply = function() P.RefreshAll() end }
        end
    end
    return groups
end

-- ============================================================
-- THE GAME'S INTERFACE SCALE
-- ============================================================
local function GetCV(name)
    local f = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not f then return nil end
    local ok, v = pcall(f, name)
    return ok and v or nil
end
local function SetCV(name, value)
    local f = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not f then return false end
    return pcall(f, name, value)
end

local SCALE_MIN, SCALE_MAX = 0.65, 1.15
local function CurrentScale()
    local v
    if GetCV("useUiScale") == "1" then v = tonumber(GetCV("uiScale")) end
    if not v then v = UIParent and UIParent.GetScale and UIParent:GetScale() or 1 end
    v = math.max(SCALE_MIN, math.min(SCALE_MAX, v or 1))
    return math.floor(v * 20 + 0.5) / 20
end

-- ============================================================
-- THE WINDOW
-- ============================================================
local frame, body, pagesHost
local S   -- this opening's session: what changed, and the part rows

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

local function Title(host, title, sub)
    local t = UI.Font(host, F.HEADER, { text = title, cat = "text", key = "gold" })
    t:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -14)
    local s = UI.Font(host, F.DESC, { text = sub, cat = "text", key = "gray", width = W - 2 * PAD })
    s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -5)
    local rule = host:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -8)
    rule:SetWidth(W - 2 * PAD)
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

-- ------------------------------------------------------------
-- 1. THE LOOK
-- ------------------------------------------------------------
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

local function PageLook(host)
    local y = Title(host, "The look",
        "The size of the whole interface, the font ZacUI uses everywhere, and the accent colour. "
        .. "The sample on the right follows your choices.")
    local x, top = PAD, y

    -- interface scale (the game's)
    local cur = CurrentScale()
    local picked = cur
    local slider = UI.Slider(host, { width = 200, min = SCALE_MIN, max = SCALE_MAX, step = 0.05,
        value = cur, label = "Interface scale",
        format = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
        onChange = function(v) picked = v end })
    slider:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    local apply = UI.Button(host, "Apply", { width = 64,
        tooltip = "Sets the game's interface scale. The whole screen resizes.",
        onClick = function()
            if InCombat() then Print("The interface scale can change after combat.") return end
            local v = math.floor(picked * 100 + 0.5) / 100
            SetCV("useUiScale", "1")
            SetCV("uiScale", tostring(v))
            Note("scale", "Interface scale: " .. math.floor(v * 100 + 0.5) .. "%")
        end })
    apply:SetPoint("BOTTOMLEFT", slider, "BOTTOMRIGHT", 10, -6)
    host.scaleSlider, host.scaleApply = slider, apply
    y = y - 40
    local _, dh = Desc(host, "The game's own setting. Pick a size, then Apply.", x, y, 260)
    y = y - dh - 14

    -- font
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
            -- the Fonts & Textures page's setter
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

    -- accent colour
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
    -- any colour at all: the Colours page's own swatch
    local custom = UI.Swatch(chips, "ui", "accent", function()
        Note("accent", "Accent colour: your own")
        RepaintAll()
    end)
    custom:SetPoint("LEFT", prev, "RIGHT", 14, 0)
    UI.Tooltip(custom, "Any colour", "Opens the colour picker.")
    host.accentCustom = custom
    y = y - 26
    Desc(host, "Rules, hover and focus. Every colour has its own swatch under Appearance > Colours.", x, y, 260)

    -- the sample
    local box = UI.Box(host, "ui", "cardBg")
    box:SetSize(220, 170)
    box:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, top)
    host.sample = box
    BuildSample(box)
end

-- ------------------------------------------------------------
-- 2. PARTS
-- ------------------------------------------------------------
local function PageParts(host)
    local y = Title(host, "Parts",
        "Each part of ZacUI can be on or off. Only the parts you have installed and enabled are listed. "
        .. "Turning one on applies now; turning one off waits for a reload.")
    local scroll, child = UI.ScrollArea(host)
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(M.SCROLL_W + 4), 30)
    scroll.bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -4, y)
    scroll.bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -4, 30)
    child:SetWidth(W - M.SCROLL_W - 8)
    local cy = -2
    host.partChecks = {}
    if #S.parts == 0 then
        local _, dh = Desc(child, "No switchable parts are loaded. Parts are separate addons named ZacUI "
            .. "something in your AddOns list.", PAD, cy, W - 2 * PAD - M.SCROLL_W)
        cy = cy - dh - 6
    end
    for _, row in ipairs(S.parts) do
        local s = row.spec
        local cb = UI.Checkbox(child, s.label, s.get() and true or false, function(on)
            local ok, err = pcall(s.set, on)
            if not ok then Print("setup: " .. s.label .. ": " .. tostring(err)) end
        end)
        cb:SetPoint("TOPLEFT", child, "TOPLEFT", PAD, cy)
        host.partChecks[s.id] = cb
        cy = cy - 18
        local text = s.desc
        if s.reload == "always" then text = text .. " Switching it takes a reload." end
        local _, dh = Desc(child, text, PAD + 21, cy, W - 2 * PAD - M.SCROLL_W - 21)
        cy = cy - dh - 10
    end
    local h = -cy + 4
    child:SetHeight(h)
    if scroll.Recalculate then scroll:Recalculate(h) end
    local always = AlwaysOnLoaded()
    if #always > 0 then
        local fs = UI.Font(host, F.DESC, { cat = "text", key = "gray", width = W - 2 * PAD,
            text = "Always on while enabled in the AddOns list: " .. table.concat(always, ", ")
                .. ". Each has its own settings page." })
        fs:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", PAD, 8)
    end
end

-- ------------------------------------------------------------
-- 3. FRAMES
-- ------------------------------------------------------------
local function PageFrames(host)
    local y = Title(host, "Frames",
        "The basics of your frames. Everything else - sizes, text, colours - is on their pages.")
    host.frameChecks = {}
    for _, g in ipairs(S.frameGroups) do
        Label(host, g.title, PAD, y)
        y = y - 18
        local col = 0
        for i, e in ipairs(g.list) do
            local cb = UI.Checkbox(host, e.label, e.get() and true or false, function(v)
                e.set(v and true or false)
                pcall(g.apply)
                Note("frame:" .. g.title .. ":" .. e.label, g.title .. ": " .. e.label .. (v and " on" or " off"))
            end)
            cb:SetPoint("TOPLEFT", host, "TOPLEFT", PAD + col * 250, y)
            host.frameChecks[g.title .. ":" .. e.label] = cb
            col = col + 1
            if col == 2 or i == #g.list then
                col = 0
                y = y - 22
            end
        end
        if g.desc then
            local _, dh = Desc(host, g.desc, PAD, y, W - 2 * PAD)
            y = y - dh - 16
        end
    end
end

-- ------------------------------------------------------------
-- 4. DONE
-- ------------------------------------------------------------
-- Labels of what waits for a reload, from this opening's part rows.
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
    return out
end

local function PageDone(host)
    local y = Title(host, "All set",
        "Everything here can be changed again on the settings pages. Type /zui to open them.")
    local lines = {}
    for _, key in ipairs(S.noteOrder) do lines[#lines + 1] = S.notes[key] end
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
        local fs = UI.Font(host, F.LABEL, { text = l, width = W - 2 * PAD - 14 })
        fs:SetPoint("TOPLEFT", host, "TOPLEFT", PAD + 12, y)
        y = y - math.max(13, fs:GetStringHeight() or 12) - 5
    end
    y = y - 10

    local reload = Setup.ReloadNeeded()
    host.reloadButton = nil
    if #reload > 0 then
        local _, dh = Desc(host, "These take a reload to finish: " .. table.concat(reload, ", ") .. ".",
            PAD, y, W - 2 * PAD)
        y = y - dh - 8
        local rb = UI.Button(host, "Reload now", { width = 110,
            onClick = function()
                if type(ReloadUI) == "function" then ReloadUI()
                elseif C_UI and C_UI.Reload then C_UI.Reload() end
            end })
        rb:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, y)
        rb:SetActive(true)
        host.reloadButton = rb
        y = y - M.BUTTON_H - 16
    end

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

-- ------------------------------------------------------------
-- PAGING
-- ------------------------------------------------------------
local pages, index

local function ShowPage(i)
    index = math.max(1, math.min(#pages, i))
    Clear(pagesHost)
    local host = CreateFrame("Frame", nil, pagesHost)
    host:SetAllPoints(pagesHost)
    pages[index].build(host)
    frame.page = host
    frame.pageId = pages[index].id
    frame.counter:SetText(index .. " of " .. #pages)
    frame.back:SetShown(index > 1)
    frame.next:SetLabel(index == #pages and "Finish" or "Next")
    frame.next:SetActive(index == #pages)
end

local function Build()
    local f = UI.Window("ZacUISetupFrame", W, H, "Quick setup")
    f:SetPoint("CENTER", 0, 30)

    pagesHost = CreateFrame("Frame", nil, f)
    pagesHost:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -(f.headerHeight + 1))
    pagesHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, FOOT_H)
    pagesHost:SetSize(W - 2, H - f.headerHeight - FOOT_H - 1)

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
    f.next = UI.Button(foot, "Next", { width = 90, onClick = function()
        if index >= #pages then
            Setup.Close()
        else
            ShowPage(index + 1)
        end
    end })
    f.next:SetPoint("RIGHT", foot, "RIGHT", -PAD, 0)
    f.back = UI.Button(foot, "Back", { width = 70, onClick = function() ShowPage(index - 1) end })
    f.back:SetPoint("RIGHT", f.next, "LEFT", -8, 0)

    f:HookScript("OnHide", function()
        UI.CloseAllDropdowns()
        local st = T() and T().DB()
        if st and index == #pages then st.setupDone = true end
        -- the profile this character wears picks up what was picked
        if ns.Profiles and ns.Profiles.WriteBack then pcall(ns.Profiles.WriteBack) end
    end)
    frame = f
    return f
end

function Setup.Open()
    if frame and frame:IsShown() and not frame._zAnim then
        frame:Raise()
        return true
    end
    if not frame then Build() end
    S = { notes = {}, noteOrder = {}, parts = {}, frameGroups = FrameGroups() }
    for _, spec in ipairs(Setup.Parts()) do
        local okG, v = pcall(spec.get)
        S.parts[#S.parts + 1] = { spec = spec, initial = (okG and v) and true or false }
    end
    pages = { { id = "look", build = PageLook }, { id = "parts", build = PageParts } }
    if #S.frameGroups > 0 then pages[#pages + 1] = { id = "frames", build = PageFrames } end
    pages[#pages + 1] = { id = "done", build = PageDone }
    ShowPage(1)
    UI.OpenWindow(frame)
    return true
end

function Setup.Close()
    if frame and frame:IsShown() then UI.CloseWindow(frame) end
end

function Setup.IsShown()
    return frame ~= nil and frame:IsShown()
end

-- for the tests: the window, the page on screen and its id
function Setup.Frame() return frame end
function Setup.Page() return frame and frame.page, frame and frame.pageId end
function Setup.Go(i) if frame and pages then ShowPage(i) end end
function Setup.PageIds()
    local out = {}
    for _, p in ipairs(pages or {}) do out[#out + 1] = p.id end
    return out
end

-- shared with later ZacUI files
ns.TutorialSetup = Setup
