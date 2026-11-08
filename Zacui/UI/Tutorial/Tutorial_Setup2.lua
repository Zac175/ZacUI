-- Tutorial_Setup2 - ZacUI's first-time setup: one window, three steps, in
-- the settings window's own look (UI.S: its shell, type, rows, round
-- switches and footer buttons; the gold accent; ZacUI's mark and name).
-- Part of ZacUI; load order is set by the TOC (after Tutorial_Hints and
-- Tutorial_Layouts, before Boot_Events). Tutorial_Setup.lua, the first
-- version, stays on disk, not loaded.
--
--   1. Look     the looks this game version can draw (Core_Look), each a
--               tile with its live miniature (Look.Preview); the pick is
--               staged. Left out when there is only one look to offer.
--   2. Parts    every ZacUI part installed here, in four groups, each with
--               a line on what it does and a switch; Select all / None.
--               The switches start where they are now (the AddOns list and
--               the module switches), so nothing new is on unless picked.
--   3. Finish   what changes, the slash commands, and one "Apply and
--               reload" button (just "Finish" when nothing changes).
--
-- NOTHING IS WRITTEN until "Apply and reload": the look is staged in
-- Core_Look (Look.StageEverywhere), the parts in this window. The apply
-- asks for the reload FIRST, inside the click (WoW Forever turns down a
-- reload asked for after the click has saved things, build 70425;
-- UIF_Dialogs' ns.AskReload has the note), then writes: Look.Commit, the
-- AddOns list (ns.SetPartEnabled, the sidebar switches' own setter) and
-- the module switches. Closing the window any other way drops the picks.
--
-- WHO SEES IT. A fresh install, after "Reset ZacUI" (both through the
-- login popup queue, Tutorial_Core), /zui setup, the General page.
--
-- COMBAT. Opening in combat waits for the fight to end; a fight that
-- starts while it is open puts it away and brings it back afterwards, on
-- the same step with the same picks.
--
-- BOOKKEEPING (account-wide, outside every profile):
--   ZacUIDB.setup = { version = 3, done, step, applied }   (applied: the
--   "you're set" line is owed at the next login; Tutorial_Core says it)
--
--   ns.TutorialSetup.Open() / Close() / IsShown() / Busy() / Skip()
--   ns.TutorialSetup.Parts()          the part rows this install lists
--   ns.TutorialSetup.Want(id) / SetWant(id, on)   a part's staged switch
--   ns.TutorialSetup.PickLook(id) / PickedLook()  the staged look
--   ns.TutorialSetup.Changes()        { look, on = {labels}, off = {labels} }
--   ns.TutorialSetup.ReloadNeeded()   labels of what waits for the reload
--   ns.TutorialSetup.Apply()          the button's work
--   ns.TutorialSetup.PageIds() / Page() / Go(i) / Index() / Frame()   (tests)
--   ns.SetupCard(L)                   the General page's Setup card
--   ns.TutorialSetup.Uninstall()      "Reset ZacUI"

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Print = ns.Print
local UI = ns.UI

local S = UI.S

local Setup = {}
Setup.VERSION = 3
-- the first-run look popup (Config_Style) stands down: the look is step 1
Setup.OWNS_FIRST_RUN = true

-- THE NUMBERS (settings units; the window takes the settings window's
-- scale, so one unit is what it is in /zui)
local W, H = 1000, 660
local HEAD_H, FOOT_H, PAD = 104, 72, 45
local TITLE_Y, TITLE_PT, SUB_PT = -124, 26, 14
local BODY_Y = -196
local BODY_FOOT = 16                       -- room above the footer line
local DISC, STEP_GAP = 26, 120             -- the step tracker
local TILE_GAP, TILE_MAX, TILE_H = 16, 280, 286
local STAGE_H = 150
local ROW_H, COL_GAP, SECTION_H = 46, 20, 32
local FOOT_BTN_H, NEXT_W, BACK_W, SKIP_W = 36, 180, 120, 140
local SECTION_A, RULE_A = 0.41, 0.02
local TILE_BG_A, TILE_HOVER_A = 0.20, 0.30
local LIT_EDGE_A, HOVER_EDGE_A = 0.6, 0.15

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

-- ============================================================
-- THE PARTS
-- ============================================================
-- kind "addon": a part addon, on = it loads next time (the AddOns list,
-- the sidebar's switch); kind "module": a switch inside ZacUI itself
-- (ZacUIDB.modules). Both wait for the reload. needs: a part this one
-- cannot load without (switched on with it, and it goes off with that).
local GROUPS = {
    { key = "screen",  label = "On screen" },
    { key = "combat",  label = "Combat" },
    { key = "windows", label = "Bags, maps and windows" },
    { key = "helpers", label = "Helpers" },
}

local PARTS = {
    { id = "bars", addon = "Zacui_Bars", group = "screen", label = "Action bars",
      desc = "Ten bars plus pet, stance and bag bars, placed your way." },
    { id = "unitframes", addon = "Zacui_UnitFrames", group = "screen", label = "Unit frames",
      desc = "Player, target, party and raid frames with incoming heals." },
    { id = "nameplates", addon = "Zacui_Nameplates", group = "screen", label = "Nameplates",
      desc = "Health, casts, debuffs and threat colours over enemies." },
    { id = "hud", addon = "Zacui_HUD", group = "screen", label = "Class HUDs",
      desc = "A HUD for your class, and the drink ticker." },
    { id = "minimap", module = { "minimap" }, group = "screen", label = "Minimap",
      desc = "A square minimap with the zone, clock and coordinates." },
    { id = "chat", module = { "chat" }, group = "screen", label = "Chat",
      desc = "Dark chat panels and the bar under the chat." },
    { id = "tooltip", module = { "tooltip" }, group = "screen", label = "Tooltips",
      desc = "Every tooltip in ZacUI's look, with a movable anchor." },
    { id = "buffs", module = { "auras" }, group = "screen", label = "Buffs",
      desc = "Your buff, debuff and weapon-enchant buttons." },

    { id = "meter", addon = "Zacui_Meter", group = "combat", label = "Damage meter",
      desc = "Damage, healing and threat for you and your group." },
    { id = "sbt", addon = "Zacui_SBT", group = "combat", label = "Scrolling text",
      desc = "Damage, healing and alerts around your character." },
    { id = "raidmods", addon = "Zacui_RaidMods", group = "combat", label = "Raid mods", needs = "raidtools",
      desc = "Timers, warnings and marks for the raid bosses." },
    { id = "raidtools", addon = "Zacui_RaidTools", group = "combat", label = "Raid tools",
      desc = "/pull, /break, /range and the raid sync." },
    { id = "buffrem", addon = "Zacui_BuffReminders", group = "combat", label = "Buff reminders",
      desc = "A nudge when you or the group miss your class buff." },
    { id = "consumables", addon = "Zacui_Consumables", group = "combat", label = "Consumables",
      desc = "Flasks, food, potions and oils on one-click bars." },
    { id = "blessings", addon = "Zacui_Blessings", group = "combat", label = "Blessings",
      desc = "Who blesses which class, shared with your paladins." },
    { id = "clicks", addon = "Zacui_Clicks", group = "combat", label = "Click casting",
      desc = "Spells and macros on mouse buttons over your frames." },
    { id = "auras", addon = "Zacui_Auras", group = "combat", label = "Aura engine",
      desc = "Runs custom auras and imports aura strings." },

    { id = "bags", addon = "Zacui_Bags", group = "windows", label = "Bags and auction house",
      desc = "One bag window with search, and auction house tabs." },
    { id = "maps", addon = "Zacui_Maps", group = "windows", label = "Maps",
      desc = "A movable map with flight points and dungeon entrances." },
    { id = "worldmap", addon = "Zacui_WorldMap", group = "windows", label = "Seamless world map",
      desc = "Every zone stitched into one map you can zoom across." },
    { id = "windows", addon = "Zacui_Windows", group = "windows", label = "Game windows",
      desc = "ZacUI's character sheet, spellbook, quest log, mail and more." },
    { id = "lootroll", module = { "lootroll" }, group = "windows", label = "Loot rolls",
      desc = "Group loot rolls as compact bars with live roll counts." },

    { id = "qol", addon = "Zacui_QoL", group = "helpers", label = "Quality of life",
      desc = "Sell junk, repair, skip gossip, faster looting and more." },
    { id = "tray", module = { "tray" }, group = "helpers", label = "Button tray",
      desc = "Every addon's minimap button in one bar with a flyout." },
}
Setup.PART_LIST, Setup.GROUPS = PARTS, GROUPS

-- on now (what the next load does), for one part
local function NowOn(p)
    if p.addon then
        local state, pending = ns.PartState(p.addon)
        return ((state == "on") ~= (pending and true or false)) and true or false
    end
    local mods = type(ZacUIDB) == "table" and ZacUIDB.modules or {}
    for _, k in ipairs(p.module) do
        if not mods[k] then return false end
    end
    return true
end

-- The rows this install lists: the part addon is in the AddOns folder and
-- this game version runs it (Core_Flavor); a module switch ZacUI has.
function Setup.Parts()
    local out = {}
    for _, p in ipairs(PARTS) do
        local show
        if p.addon then
            show = ns.PartState and ns.PartState(p.addon) ~= "missing"
                and not (ns.PartOff and ns.PartOff(p.addon))
        else
            show = true
            for _, k in ipairs(p.module) do
                if not (ns.MODULE_INFO and ns.MODULE_INFO[k]) then show = false end
            end
        end
        if show then out[#out + 1] = p end
    end
    return out
end

-- ============================================================
-- THE SESSION: what this opening has picked
-- ============================================================
local frame, root, pagesHost, stepper
local watch, OnWatch   -- the combat watch (made on first use, below)
local Sx            -- { parts = { rows }, byId, want, look, live, applied }
local steps, index

local function LookReady()
    local L = ns.Look
    return type(L) == "table" and type(L.Choices) == "function" and type(L.StageEverywhere) == "function"
        and type(L.Commit) == "function"
end

local function LookChoices()
    if not LookReady() then return {} end
    local ok, ch = pcall(ns.Look.Choices)
    return ok and type(ch) == "table" and ch or {}
end

local function LookName(id)
    for _, c in ipairs(LookChoices()) do if c.id == id then return c.name or id end end
    return id
end

local function LiveLook()
    local L = ns.Look
    return (L.LiveUniform and L.LiveUniform()) or (L.Active and L.Active()) or "zacui"
end

local function NewSession()
    Sx = { parts = {}, byId = {}, want = {}, applied = false }
    for _, p in ipairs(Setup.Parts()) do
        local on = NowOn(p)
        local row = { spec = p, initial = on }
        Sx.parts[#Sx.parts + 1] = row
        Sx.byId[p.id] = row
        Sx.want[p.id] = on
    end
    if LookReady() then
        Sx.live = LiveLook()
        Sx.look = (ns.Look.Pending and ns.Look.Pending()) or Sx.live
    end
end

function Setup.Want(id)
    return Sx and Sx.want[id]
end

local Refresh   -- repaints the page on screen (set by the builders)

function Setup.SetWant(id, on)
    if not (Sx and Sx.byId[id]) then return false end
    on = on and true or false
    Sx.want[id] = on
    -- what a part needs comes on with it; what needs a part goes off with it
    local p = Sx.byId[id].spec
    if on and p.needs and Sx.byId[p.needs] then Sx.want[p.needs] = true end
    if not on then
        for _, row in ipairs(Sx.parts) do
            if row.spec.needs == id then Sx.want[row.spec.id] = false end
        end
    end
    if Refresh then Refresh() end
    return true
end

-- the look: staged in Core_Look; the live look's tile drops the stage
function Setup.PickLook(id)
    if not (Sx and LookReady()) then return false end
    local L = ns.Look
    if id == Sx.live then
        if L.Discard then L.Discard() end
    elseif not L.StageEverywhere(id) then
        return false
    end
    Sx.look = id
    if Refresh then Refresh() end
    return true
end
function Setup.PickedLook() return Sx and Sx.look end

function Setup.Changes()
    local out = { on = {}, off = {} }
    if not Sx then return out end
    if LookReady() and Sx.look and Sx.look ~= Sx.live then out.look = Sx.look end
    for _, row in ipairs(Sx.parts) do
        local want = Sx.want[row.spec.id]
        if want ~= row.initial then
            local list = want and out.on or out.off
            list[#list + 1] = row.spec.label
        end
    end
    return out
end

local function AnyChange(ch)
    return ch.look ~= nil or #ch.on > 0 or #ch.off > 0
end

function Setup.ReloadNeeded()
    local ch = Setup.Changes()
    local out = {}
    if ch.look then out[#out + 1] = "The look" end
    for _, l in ipairs(ch.on) do out[#out + 1] = l .. " (on)" end
    for _, l in ipairs(ch.off) do out[#out + 1] = l .. " (off)" end
    return out
end

local function MarkDone()
    DB().done = true
    if T() then T().DB().setupDone = true end
end

-- THE APPLY. The reload is asked for first, inside the click; then the
-- writes, still inside it, so the reload saves them.
function Setup.Apply()
    if not Sx then return false end
    if InCombat() then Print("The setup applies after combat.") return false end
    local ch = Setup.Changes()
    MarkDone()
    if not AnyChange(ch) then
        Sx.applied = true
        Setup.Close()
        Print("Setup done - nothing to change. /zui setup brings it back any time.")
        return false
    end
    Sx.applied = true
    if ns.RequestReload then ns.RequestReload()
    elseif type(ReloadUI) == "function" then ReloadUI()
    elseif C_UI and C_UI.Reload then C_UI.Reload() end
    if ch.look and LookReady() then pcall(ns.Look.Commit) end
    for _, row in ipairs(Sx.parts) do
        local p, want = row.spec, Sx.want[row.spec.id]
        if want ~= row.initial then
            if p.addon then
                if ns.SetPartEnabled then pcall(ns.SetPartEnabled, p.addon, want) end
            else
                ZacUIDB.modules = ZacUIDB.modules or {}
                for _, k in ipairs(p.module) do
                    ZacUIDB.modules[k] = want
                    if not want and ns.CVar and ns.CVar.RestoreOwner then pcall(ns.CVar.RestoreOwner, k) end
                end
            end
        end
    end
    -- the one line after the reload (Tutorial_Core's login check says it)
    DB().applied = true
    if ns.Profiles and ns.Profiles.WriteBack then pcall(ns.Profiles.WriteBack) end
    return true
end
-- (the name the first versions had)
Setup.ReloadNow = function() return Setup.Apply() end

-- ============================================================
-- DRAWING HELPERS (the settings window's idioms)
-- ============================================================
local function Tex(parent, layer, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    t._zui_own = true
    t:SetTexture(FLAT)
    return t
end

-- four pixel-exact strips round a frame (ns.Pixel), tinted by the caller
local function Edge(f)
    if ns.Pixel and ns.Pixel.Border then
        local list = ns.Pixel.Border(f, 1, 1, 1, S.BORDER_A, "OVERLAY", 6)
        if list then return list end
    end
    UI.Border(f, "ui", "border")
    return f._zBorder or {}
end
local function TintEdge(list, r, g, b, a)
    for _, t in ipairs(list) do
        if t.SetColorTexture then t:SetColorTexture(r, g, b, a) else t:SetVertexColor(r, g, b, a) end
    end
end

-- an accent wash fading to the right (the sidebar's selected row)
local function Grad(tex, c, a0)
    if CreateColor and tex.SetGradient then
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradient("HORIZONTAL", CreateColor(c.r, c.g, c.b, a0), CreateColor(c.r, c.g, c.b, 0))
    elseif tex.SetGradientAlpha then
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradientAlpha("HORIZONTAL", c.r, c.g, c.b, a0, c.r, c.g, c.b, 0)
    else
        tex:SetVertexColor(c.r, c.g, c.b, a0 / 2)
    end
end

-- text at an exact size, white at alpha `a` (or a painter of its own);
-- outlined as ZacUI's font option says
local function Text(parent, size, text, a, opts)
    opts = opts or {}
    opts.text = text
    local fs = UI.SFont(parent, size, opts)
    if type(a) == "function" then
        fs._zPaint = a
    else
        fs._zPaint = function(self) self:SetTextColor(1, 1, 1, a or 1) end
    end
    fs:_zPaint()
    return fs
end
local function AccentText(self, alpha)
    local c = GetColor("ui", "accent")
    self:SetTextColor(c.r, c.g, c.b, alpha or 1)
end

-- a round disc of n units (UI.DiscArt, our own art)
local function Disc(parent, n, layer, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
    t._zui_own = true
    UI.DiscArt(t, n)
    t:SetSize(n, n)
    return t
end

-- a section title and its hairline, as the settings pages draw them
local function Section(parent, label, x, y, width)
    local t = Text(parent, S.F_SECTION, label, SECTION_A)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 1, y - 10)
    local r = Tex(parent, "ARTWORK")
    if ns.Pixel and ns.Pixel.Edge then ns.Pixel.Edge(r, "TOP", parent) else r:SetHeight(1) end
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - (SECTION_H - 5))
    r:SetWidth(width)
    r:SetVertexColor(1, 1, 1, RULE_A)
    return t, r
end

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

local function PageTitle(host, title, sub)
    local t = Text(host, TITLE_PT, title, 1)
    t:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, TITLE_Y)
    local s = Text(host, SUB_PT, sub, S.DIM_A, { width = W - 2 * PAD - 240 })
    s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 1, -10)
    host.titleText, host.subText = t, s
end

-- ============================================================
-- 1. THE LOOK
-- ============================================================
local function LookTile(parent, choice, w)
    local id = choice.id
    local tile = CreateFrame("Button", nil, parent)
    tile:SetSize(w, TILE_H)
    tile._zLookId = id
    local bg = Tex(tile, "BACKGROUND", -7)
    bg:SetAllPoints()
    local wash = Tex(tile, "BACKGROUND", -6)
    wash:SetAllPoints()
    local bar = Tex(tile, "OVERLAY", 7)
    bar:SetWidth(3)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    local edge = Edge(tile)

    -- the stage and the look's live miniature (the real primitives)
    local stage = CreateFrame("Frame", nil, tile)
    stage:SetPoint("TOPLEFT", tile, "TOPLEFT", 10, -10)
    stage:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -10, -10)
    stage:SetHeight(STAGE_H)
    local sbg = Tex(stage, "BACKGROUND", -8)
    sbg:SetAllPoints()
    sbg:SetVertexColor(0, 0, 0, 0.45)
    TintEdge(Edge(stage), 1, 1, 1, 0.08)
    local sw = math.min(200, w - 36)
    local ok, mini = pcall(ns.Look.Preview, stage, id, sw, math.floor(sw * 104 / 168 + 0.5))
    if ok and mini then
        mini:SetPoint("CENTER", stage, "CENTER", 0, 0)
        if mini.EnableMouse then mini:EnableMouse(false) end
        tile.preview = mini
    end

    -- the radio, the name, the tag and the words
    local ring = Disc(tile, 16, "ARTWORK", 1)
    ring:SetPoint("TOPLEFT", stage, "BOTTOMLEFT", 2, -16)
    local hole = Disc(tile, 12, "ARTWORK", 2)
    hole:SetPoint("CENTER", ring, "CENTER")
    local dot = Disc(tile, 6, "ARTWORK", 3)
    dot:SetPoint("CENTER", ring, "CENTER")
    local name = Text(tile, 16, choice.name or id, 1)
    name:SetPoint("LEFT", ring, "RIGHT", 10, 0)
    local tag = Text(tile, 11, (choice.tag or ""):upper(), function(self) AccentText(self, 0.8) end)
    tag:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)
    local desc = Text(tile, 13, choice.desc or "", S.DIM_A, { width = w - 30 })
    desc:SetPoint("TOPLEFT", ring, "BOTTOMLEFT", -4, -32)
    if desc.SetMaxLines then desc:SetMaxLines(3) end
    local inUse = Text(tile, 11, "IN USE", function(self)
        local c = GetColor("text", "green")
        self:SetTextColor(c.r, c.g, c.b, 1)
    end)
    inUse:SetPoint("RIGHT", tile, "RIGHT", -12, 0)
    inUse:SetPoint("TOP", name, "TOP", 0, 0)
    tile.name, tile.tag, tile.desc, tile.inUse, tile.dot = name, tag, desc, inUse, dot

    tile._zPaint = function(self)
        local a = GetColor("ui", "accent")
        local sel = Sx and Sx.look == id
        local hot = self._zHot
        bg:SetVertexColor(0, 0, 0, hot and TILE_HOVER_A or TILE_BG_A)
        wash:SetShown(sel and true or false)
        if sel then Grad(wash, a, S.NAV_GLOW) end
        bar:SetShown(sel and true or false)
        bar:SetVertexColor(a.r, a.g, a.b, 1)
        if sel then TintEdge(edge, a.r, a.g, a.b, LIT_EDGE_A)
        elseif hot then TintEdge(edge, 1, 1, 1, HOVER_EDGE_A)
        else TintEdge(edge, 1, 1, 1, S.BORDER_A) end
        if sel then
            ring:SetVertexColor(a.r, a.g, a.b, 1)
            hole:SetVertexColor(a.r, a.g, a.b, 1)
        else
            ring:SetVertexColor(1, 1, 1, hot and 0.45 or 0.24)
            local b = S.BG
            hole:SetVertexColor(b.r, b.g, b.b, 1)
        end
        dot:SetShown(sel and true or false)
        dot:SetVertexColor(1, 1, 1, 1)
        inUse:SetShown(Sx ~= nil and Sx.live == id)
        name:_zPaint() tag:_zPaint() desc:_zPaint() inUse:_zPaint()
        if self.preview and self.preview._zPaint then pcall(self.preview._zPaint, self.preview) end
    end
    tile:SetScript("OnEnter", function(self) self._zHot = true self:_zPaint() end)
    tile:SetScript("OnLeave", function(self) self._zHot = nil self:_zPaint() end)
    tile:SetScript("OnClick", function() Setup.PickLook(id) end)
    UI.Tooltip(tile, choice.name or id, choice.desc)
    tile:_zPaint()
    return tile
end

local function PageLook(host)
    PageTitle(host, "Pick your look",
        "How the game's frames are drawn. Every ZacUI feature works in every look.")
    local choices = LookChoices()
    local n = #choices
    local tw = math.min(TILE_MAX, math.floor((W - 2 * PAD - (n - 1) * TILE_GAP) / math.max(1, n)))
    local rowW = n * tw + (n - 1) * TILE_GAP
    local x = math.floor((W - rowW) / 2)
    host.lookTiles = {}
    for _, c in ipairs(choices) do
        local tile = LookTile(host, c, tw)
        tile:SetPoint("TOPLEFT", host, "TOPLEFT", x, BODY_Y - 8)
        host.lookTiles[c.id] = tile
        x = x + tw + TILE_GAP
    end
    local note = Text(host, 13, "Mix looks part by part any time on Appearance > Style. A new look applies "
        .. "at the reload on the last step.", SECTION_A, { width = W - 2 * PAD, justify = "CENTER" })
    note:SetPoint("TOP", host, "TOP", 0, BODY_Y - 8 - TILE_H - 20)
    function host:Refresh()
        for _, t in pairs(self.lookTiles) do t:_zPaint() end
    end
end

-- ============================================================
-- 2. THE PARTS
-- ============================================================
local function PartRow(parent, row, w, stripe)
    local p = row.spec
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(w, ROW_H)
    local bg = Tex(r, "BACKGROUND", -7)
    bg:SetAllPoints()
    bg:SetVertexColor(0, 0, 0, stripe and S.ROW_EVEN or S.ROW_ODD)
    local hl = Tex(r, "BACKGROUND", -6)
    hl:SetAllPoints()
    hl:SetVertexColor(1, 1, 1, S.NAV_HL)
    hl:Hide()
    local name = Text(r, S.F_LABEL, p.label, 1)
    name:SetPoint("TOPLEFT", r, "TOPLEFT", 14, -8)
    local desc = Text(r, S.F_HINT, p.desc, S.DIM_A, { width = w - 14 - S.TOGGLE_W - 26 })
    desc:SetPoint("TOPLEFT", r, "TOPLEFT", 14, -26)
    desc:SetWordWrap(false)
    UI.TruncTip(desc, r)
    local tg = UI.SettingsBuild(UI.Toggle, r, "", Sx.want[p.id], function(on)
        Setup.SetWant(p.id, on)
    end)
    tg:SetWidth(S.TOGGLE_W)
    tg:ClearAllPoints()
    tg:SetPoint("RIGHT", r, "RIGHT", -14, 0)
    r.toggle, r.name, r.desc = tg, name, desc
    r._zPaint = function(self)
        local on = Sx.want[p.id]
        if self.toggle:GetChecked() ~= on then self.toggle:SetChecked(on) end
        name:SetTextColor(1, 1, 1, on and 1 or S.NAV_EN)
        desc:_zPaint()
    end
    r:SetScript("OnEnter", function(self) hl:Show() end)
    r:SetScript("OnLeave", function(self) hl:Hide() end)
    r:SetScript("OnClick", function(self) self.toggle:Click() end)
    local tip = p.desc
    if p.needs and Sx.byId[p.needs] then tip = tip .. " Needs " .. Sx.byId[p.needs].spec.label .. " (switched on with it)." end
    UI.Tooltip(r, p.label, tip)
    r:_zPaint()
    return r
end

local function PageParts(host)
    PageTitle(host, "Pick your parts",
        "Each part is its own addon or switch. Off means it does not load; its settings are kept.")
    local function All(on)
        for _, row in ipairs(Sx.parts) do Sx.want[row.spec.id] = on end
        if Refresh then Refresh() end
    end
    local none = UI.SettingsBuild(UI.Button, host, "None", { width = 70, height = 28,
        tooltip = "Switches every part off. Nothing changes until Apply and reload.",
        onClick = function() All(false) end })
    none:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, TITLE_Y - 2)
    local all = UI.SettingsBuild(UI.Button, host, "Select all", { width = 96, height = 28,
        tooltip = "Switches every part on. Nothing changes until Apply and reload.",
        onClick = function() All(true) end })
    all:SetPoint("RIGHT", none, "LEFT", -8, 0)
    host.allButton, host.noneButton = all, none

    local scroll, child = UI.ScrollArea(host, { style = "settings" })
    local bottom = FOOT_H + BODY_FOOT
    scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 0, BODY_Y)
    scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(PAD - 20), bottom)
    scroll.bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", -10, BODY_Y)
    scroll.bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -10, bottom)
    child:SetWidth(W - PAD + 20)
    local inner = W - 2 * PAD
    local colW = math.floor((inner - COL_GAP) / 2)
    local y = 0
    host.partRows = {}
    if #Sx.parts == 0 then
        local d = Text(child, SUB_PT, "No ZacUI parts are installed. Parts are the addons named Zacui_"
            .. "something in your AddOns list.", S.DIM_A, { width = inner })
        d:SetPoint("TOPLEFT", child, "TOPLEFT", PAD, -8)
        y = -40
    end
    for _, g in ipairs(GROUPS) do
        local rows = {}
        for _, row in ipairs(Sx.parts) do if row.spec.group == g.key then rows[#rows + 1] = row end end
        if #rows > 0 then
            Section(child, g.label, PAD, y, inner)
            y = y - SECTION_H
            for i, row in ipairs(rows) do
                local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
                local r = PartRow(child, row, colW, line % 2 == 1)
                r:SetPoint("TOPLEFT", child, "TOPLEFT", PAD + col * (colW + COL_GAP), y - line * ROW_H)
                host.partRows[row.spec.id] = r
            end
            y = y - math.ceil(#rows / 2) * ROW_H - 14
        end
    end
    local h = -y + 4
    child:SetHeight(h)
    if scroll.Recalculate then scroll:Recalculate(h) end
    host.scroll = scroll
    function host:Refresh()
        for _, r in pairs(self.partRows) do r:_zPaint() end
    end
end

-- ============================================================
-- 3. FINISH
-- ============================================================
local function PageFinish(host)
    local ch = Setup.Changes()
    local any = AnyChange(ch)
    PageTitle(host, any and "Apply and reload" or "All set",
        any and "Nothing is written until you press the button. The interface reloads once."
            or "Nothing to change: ZacUI keeps what it ships. Every choice here is on the settings pages too.")
    local inner = W - 2 * PAD
    local colW = math.floor((inner - 40) / 2)
    local x1, x2 = PAD, PAD + colW + 40

    Section(host, "What changes", x1, BODY_Y, colW)
    local lines = {}
    if ch.look then
        lines[#lines + 1] = { "Look", LookName(ch.look) .. " (was " .. LookName(Sx.live) .. ")", "ui", "accent" }
    end
    if #ch.on > 0 then lines[#lines + 1] = { "Turned on", table.concat(ch.on, ", "), "text", "green" } end
    if #ch.off > 0 then lines[#lines + 1] = { "Turned off", table.concat(ch.off, ", "), "text", "orange" } end
    if #lines == 0 then lines[1] = { "Nothing", "ZacUI keeps its look and parts.", "text", "gray" } end
    host.changeLines = {}
    local y = BODY_Y - SECTION_H
    for i, l in ipairs(lines) do
        local rowF = CreateFrame("Frame", nil, host)
        rowF:SetPoint("TOPLEFT", host, "TOPLEFT", x1, y)
        rowF:SetWidth(colW)
        local bg = Tex(rowF, "BACKGROUND", -7)
        bg:SetAllPoints()
        bg:SetVertexColor(0, 0, 0, i % 2 == 0 and S.ROW_EVEN or S.ROW_ODD)
        local dot = Disc(rowF, 8)
        dot:SetPoint("TOPLEFT", rowF, "TOPLEFT", 12, -16)
        local c = GetColor(l[3], l[4])
        dot:SetVertexColor(c.r, c.g, c.b, 1)
        local k = Text(rowF, S.F_LABEL, l[1], 1)
        k:SetPoint("TOPLEFT", rowF, "TOPLEFT", 28, -12)
        local v = Text(rowF, 13, l[2], S.DIM_A, { width = colW - 130 - 10 })
        v:SetPoint("TOPLEFT", rowF, "TOPLEFT", 130, -13)
        local hh = math.max(40, math.ceil(v:GetStringHeight() or 13) + 26)
        rowF:SetHeight(hh)
        host.changeLines[#host.changeLines + 1] = l[1] .. ": " .. l[2]
        y = y - hh
    end

    Section(host, "After the reload", x2, BODY_Y, colW)
    local cmds = {
        { "/zui", "every setting, page by page" },
        { "/zui edit", "move any frame over a grid" },
        { "/zui setup", "this setup again, any time" },
        { "/zui tour", "a walk round the settings window" },
    }
    y = BODY_Y - SECTION_H
    for i, c in ipairs(cmds) do
        local rowF = CreateFrame("Frame", nil, host)
        rowF:SetPoint("TOPLEFT", host, "TOPLEFT", x2, y)
        rowF:SetSize(colW, 40)
        local bg = Tex(rowF, "BACKGROUND", -7)
        bg:SetAllPoints()
        bg:SetVertexColor(0, 0, 0, i % 2 == 0 and S.ROW_EVEN or S.ROW_ODD)
        local k = Text(rowF, S.F_LABEL, c[1], function(self) AccentText(self, 1) end)
        k:SetPoint("LEFT", rowF, "LEFT", 14, 0)
        local v = Text(rowF, 13, c[2], S.DIM_A)
        v:SetPoint("LEFT", rowF, "LEFT", 110, 0)
        y = y - 40
    end
    host.anyChange = any
end

-- ============================================================
-- THE STEPS
-- ============================================================
local ALL_STEPS = {
    { id = "look", title = "Look", build = PageLook,
      available = function() return #LookChoices() > 1 end },
    { id = "parts", title = "Parts", build = PageParts },
    { id = "finish", title = "Finish", build = PageFinish },
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
-- THE WINDOW
-- ============================================================
local function PaintStepper()
    if not stepper then return end
    local a = GetColor("ui", "accent")
    local off = S.TG_OFF
    for i, s in ipairs(stepper.items) do
        local st = steps[i]
        s:SetShown(st ~= nil)
        if st then
            s.label:SetText(st.title)
            local done, cur = i < index, i == index
            s.halo:SetShown(cur)
            s.halo:SetVertexColor(a.r, a.g, a.b, 0.25)
            if cur then s.disc:SetVertexColor(a.r, a.g, a.b, 1)
            elseif done then s.disc:SetVertexColor(a.r, a.g, a.b, 0.45)
            else s.disc:SetVertexColor(off.r, off.g, off.b, S.TG_OFF_A) end
            s.num:SetText(done and "+" or tostring(i))
            if cur then s.num:SetTextColor(S.BG.r, S.BG.g, S.BG.b, 1)
            else s.num:SetTextColor(1, 1, 1, done and 1 or 0.5) end
            s.label:SetTextColor(1, 1, 1, cur and 1 or S.DIM_A)
        end
    end
    for i, line in ipairs(stepper.lines) do
        line:SetShown(steps[i + 1] ~= nil)
        if i < index then line:SetVertexColor(a.r, a.g, a.b, S.TG_ON_A)
        else line:SetVertexColor(off.r, off.g, off.b, S.TG_OFF_A) end
    end
    -- the row sits right of centre, its last disc clear of the close box
    local n = #steps
    local right = W - 130
    for i, s in ipairs(stepper.items) do
        s:ClearAllPoints()
        s:SetPoint("CENTER", root, "TOPLEFT", right - (n - i) * STEP_GAP, -44)
    end
end

local function ShowPage(i)
    index = math.max(1, math.min(#steps, i))
    DB().step = index
    Refresh = nil
    Clear(pagesHost)
    local host = CreateFrame("Frame", nil, pagesHost)
    host:SetAllPoints(pagesHost)
    local ok, err = pcall(UI.SettingsBuild, steps[index].build, host)
    if not ok then Print("setup: " .. steps[index].id .. ": " .. tostring(err)) end
    if host.Refresh then Refresh = function() host:Refresh() end end
    frame.page = host
    frame.pageId = steps[index].id
    frame.back:SetShown(index > 1)
    local last = index == #steps
    local label = "Next"
    if last then label = AnyChange(Setup.Changes()) and "Apply and reload" or "Finish" end
    frame.next:SetLabel(label)
    PaintStepper()
end

local function BuildStepper()
    stepper = { items = {}, lines = {} }
    for i = 1, 3 do
        local s = CreateFrame("Button", nil, root)
        s:SetSize(STEP_GAP - 20, 60)
        s.halo = Disc(s, DISC + 6, "ARTWORK", 0)
        s.halo:SetPoint("CENTER", s, "TOP", 0, -14)
        s.disc = Disc(s, DISC, "ARTWORK", 1)
        s.disc:SetPoint("CENTER", s, "TOP", 0, -14)
        s.num = UI.SFont(s, S.F_LABEL, { text = tostring(i), justify = "CENTER" })
        s.num:SetPoint("CENTER", s.disc, "CENTER", 0, 0)
        s.label = UI.SFont(s, 13, { text = "", justify = "CENTER" })
        s.label:SetPoint("TOP", s.disc, "BOTTOM", 0, -6)
        s:SetScript("OnClick", function() if steps[i] then ShowPage(i) end end)
        stepper.items[i] = s
    end
    for i = 1, 2 do
        local line = Tex(root, "ARTWORK", 0)
        line:SetHeight(2)
        line:SetPoint("LEFT", stepper.items[i].disc, "RIGHT", 6, 0)
        line:SetPoint("RIGHT", stepper.items[i + 1].disc, "LEFT", -6, 0)
        stepper.lines[i] = line
    end
end

local function FitScale()
    local user = (ZacUIDB and ZacUIDB.config and ZacUIDB.config.scale) or 1
    local sc = ns.ConfigExactScale and ns.ConfigExactScale(user) or user
    local sw = UIParent and UIParent:GetWidth() or 0
    local sh = UIParent and UIParent:GetHeight() or 0
    if sw > 0 and sh > 0 then sc = math.min(sc, sw * 0.94 / W, sh * 0.94 / H) end
    return sc
end

local function Build()
    local f = UI.Window("ZacUISetupFrame", W, H, "Setup", { bare = true })
    f:SetPoint("CENTER", 0, 20)
    -- everything lives on the window's drag surface (as the settings
    -- window's buttons do), so it takes the mouse over the drag
    root = f.titleBar
    f.closeButton:SetFrameLevel(root:GetFrameLevel() + 30)

    -- the header: ZacUI's mark and name, what this is, the steps
    local mark = root:CreateTexture(nil, "ARTWORK", nil, 3)
    mark._zui_own = true
    mark:SetSize(40, 40)
    mark:SetPoint("TOPLEFT", root, "TOPLEFT", 28, -30)
    mark:SetTexture(ns.TEX_ICON)
    if ns.SharpenIcon then ns.SharpenIcon(mark) end
    local first = Text(root, 26, "Zac", 1)
    first:SetPoint("TOPLEFT", mark, "TOPRIGHT", 10, 2)
    local second = Text(root, 26, "UI", function(self) AccentText(self, 1) end)
    second:SetPoint("LEFT", first, "RIGHT", 0, 0)
    local what = Text(root, 13, "First-time setup", S.DIM_A)
    what:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 1, -4)
    if UI.AnimateMark then pcall(UI.AnimateMark, mark, root, { inset = 0, idle = false }) end
    BuildStepper()
    local rule = Tex(root, "ARTWORK")
    if ns.Pixel and ns.Pixel.Edge then ns.Pixel.Edge(rule, "TOP", root) else rule:SetHeight(1) end
    rule:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -HEAD_H)
    rule:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -HEAD_H)
    rule:SetVertexColor(1, 1, 1, S.BORDER_A)

    pagesHost = CreateFrame("Frame", nil, root)
    pagesHost:SetAllPoints(root)
    pagesHost:SetFrameLevel(root:GetFrameLevel() + 2)

    -- the footer: a band, its line, Skip on the left, Back and Next right
    local foot = CreateFrame("Frame", nil, root)
    foot:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    foot:SetHeight(FOOT_H)
    foot:SetFrameLevel(root:GetFrameLevel() + 10)
    local band = Tex(foot, "BACKGROUND", -7)
    band:SetAllPoints()
    band:SetVertexColor(0, 0, 0, S.ROW_EVEN)
    local fr = Tex(foot, "ARTWORK")
    if ns.Pixel and ns.Pixel.Edge then ns.Pixel.Edge(fr, "TOP", foot) else fr:SetHeight(1) end
    fr:SetPoint("TOPLEFT")
    fr:SetPoint("TOPRIGHT")
    fr:SetVertexColor(1, 1, 1, S.BORDER_A)
    UI.SettingsBuild(function()
        f.skip = UI.Button(foot, "Skip setup", { width = SKIP_W, height = FOOT_BTN_H, style = "footer",
            tooltip = "Closes the setup and keeps everything as it is. /zui setup brings it back any time.",
            onClick = function() Setup.Skip() end })
        f.skip:SetPoint("LEFT", foot, "LEFT", PAD, 0)
        f.next = UI.Button(foot, "Next", { width = NEXT_W, height = FOOT_BTN_H, style = "close",
            onClick = function()
                if index >= #steps then Setup.Apply() else ShowPage(index + 1) end
            end })
        f.next:SetPoint("RIGHT", foot, "RIGHT", -PAD, 0)
        f.back = UI.Button(foot, "Back", { width = BACK_W, height = FOOT_BTN_H, style = "footer",
            onClick = function() ShowPage(index - 1) end })
        f.back:SetPoint("RIGHT", f.next, "LEFT", -12, 0)
    end)

    f:HookScript("OnHide", function(self)
        UI.CloseAllDropdowns()
        if self._zCombatHide then return end
        if watch then watch:UnregisterEvent("PLAYER_REGEN_DISABLED") end
        -- closed without the apply: the staged look goes too
        if Sx and not Sx.applied and LookReady() and Sx.look ~= Sx.live and ns.Look.Discard then
            ns.Look.Discard()
        end
    end)
    frame = f
    return f
end

-- ============================================================
-- OPEN / CLOSE, COMBAT
-- ============================================================
-- the combat watch is made on first use (an open, or an open refused in
-- combat): a closed setup has no frame and no event at all
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
    frame:SetScale(FitScale())
    local d = DB()
    d.version = Setup.VERSION
    NewSession()
    steps = BuildSteps()
    ShowPage(1)
    Watch():RegisterEvent("PLAYER_REGEN_DISABLED")
    UI.OpenWindow(frame)
    return true
end

function Setup.Close()
    if watch then watch:UnregisterEvent("PLAYER_REGEN_DISABLED") end
    if frame and frame:IsShown() then UI.CloseWindow(frame) end
end

-- "Skip setup": keeps everything as it is, counts as done
function Setup.Skip()
    MarkDone()
    Setup.Close()
    Print("Setup skipped - ZacUI keeps what it ships. /zui setup brings it back any time.")
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
            C_Timer.After(1, function()
                if InCombat() then
                    self:RegisterEvent("PLAYER_REGEN_ENABLED")
                    return
                end
                pendingReopen = false
                if frame and Sx and not Sx.applied then
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
    L:Desc("The setup runs again any time with your current look and parts. One-time hints are the tips ZacUI "
        .. "shows once; Reset hints brings them (and the setup at login) back. Reset ZacUI starts over from a "
        .. "fresh install: every ZacUI setting is cleared and every game setting ZacUI changed goes back.")
    L:Gap(4)
    local run = UI.Button(card, "Run the setup", { width = 120,
        tooltip = "Your look and parts, in three steps. /zui setup does the same.",
        onClick = function() Setup.Open() end })
    local hints = UI.Button(card, "Reset hints", { width = 100,
        tooltip = "Every one-time tip shows again, and the setup comes back at your next login. /zui hints reset does the same.",
        onClick = function()
            if ns.Hints then ns.Hints.Reset() end
            Print("Hints reset - every one-time tip shows again, and the setup at your next login.")
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
            -- the reload first, then the reset's writes (the apply's note)
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
