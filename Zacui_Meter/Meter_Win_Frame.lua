-- Meter_Win_Frame - a meter window: its frame, the header (the mode and
-- the fight clock, the icons), the body the rows live in, the lock and
-- the resize grip, drag and snap, adding and closing windows, the
-- preview window the settings page draws, and the restyle that pushes
-- every setting onto what is on screen.
-- Part of ZacUI; load order is set by the TOC (after Meter_Windows,
-- which keeps the settings, the rows and the refresh; after
-- Meter_Win_Menus, which has the menus the header opens).
--
-- METER V2 (2026-11-07). Zac: "his damage meters and stuff are so much
-- better than mine mine need a lot of cleanup and redoing." The window
-- is redone; the numbers behind it are not. What a window is now:
--   * a HEADER BAR across the top (look.headerMode = "bar", the default
--     since v2): the mode and the fight clock, "Damage Done (2:13)", and
--     six small icons at the right - + or x (window 1 adds a window,
--     the others close), reset, mode, segment, report, settings - each
--     with a tooltip, faint until the mouse is on them. "hover" is the
--     old look (no bar, the icons float above the window while the
--     mouse is on it); "none" is no bar and no icons at all. Right-click
--     anywhere for the mode menu.
--   * the BODY under it: the rows, as many as fit, the wheel scrolling
--     them; your own row pinned at the edge when it scrolls away (look.
--     pinSelf = "pin"), or claiming the last row (the old "follow").
--   * a LOCK and a RESIZE GRIP at the bottom-right corner, faint while
--     the mouse is on the window, hidden otherwise; locked, nothing
--     drags or resizes (the menus still work). Dragging and resizing
--     snap to the nearest other meter window within 6 px.
--   * up to five windows (Meter.Win.MAX). The + opens one next to window
--     1, the x parks one (its frame is kept for the next +); the saved
--     list stays dense and the windows after it move up one. No reload.
-- The header sits INSIDE the window's height (the old title bar sat on
-- top of it): the rev-8 migration in Meter_Windows grew every window by
-- the header's height once, so nobody lost a row.
-- Nothing here reads a setting in an OnUpdate: the window is styled
-- when a setting changes (Meter.RestyleAll) and painted by the refresh
-- tick; the clock is a 1 s ticker that runs only in combat.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local Meter = ns.Meter
if not (Meter and Meter.winMeta) then return end
local Print = ns.Print
local UI = ns.UI

local floor, max, format = math.floor, math.max, string.format

local winMeta = Meter.winMeta
local windows = Meter.windowFrames
local Look, DB = Meter.Look, Meter.DB
local ColorOf, PlaceEdges, Pixels = Meter.ColorOf, Meter.PlaceEdges, Meter.Pixels
local FLAT_TEX = ns.FLAT or "Interface\\Buttons\\WHITE8X8"

local Win = {}
Meter.Win = Win
Win.MAX = 5
Meter.MAX_WINDOWS = Win.MAX

local SNAP = 6             -- px: dragging and resizing line up with another window this close
local GAP = 6              -- px between a new window and the one it came from
local ICON_ALPHA = 0.4     -- the header icons at rest (match pass: 0.55 -> 0.4)
local ICON_HOVER_A = 0.9   -- ...and under the mouse (1 -> 0.9)
local HOVER_ALPHA = 0.92   -- the floating toolbar while the mouse is on the window

-- Blizzard's own art for the corner (every client ships these)
local TEX_GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
-- ZacUI's own icons (Zacui/Media/Icons: drawn for ZacUI, white with a
-- soft dark rim, tinted by SetVertexColor)
local ICONS = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\"
Meter.ICONS = ICONS
local TEX_LOCKED = ICONS .. "lock"
local TEX_UNLOCKED = ICONS .. "unlock"
-- the header's spacing (the mockup was drawn from these)
-- (match pass: the icons 22 and 2 apart less, i.e. overlapping by 2, the
-- first flush with the right edge, as the reference meter lays them; ZacUI's
-- glyphs sit inside their square, so they still read apart)
local HEADER_PAD_L, HEADER_PAD_R, ICON_GAP, CLOCK_GAP = 6, 0, -2, 4
-- (2026-11-08 polish) the room kept between the title and the icons
local TITLE_ICON_GAP = 6

-- ============================================================
-- THE CLASSIC LOOK'S METER (2026-11-08, Zac: give the meter the reference
-- meter's "classic mode" under the Classic look). Facts reused from the
-- reference (zui_tests/MATCH_SPEC_1108 table in the report), our own code;
-- every file below is the game's own art, by its path:
--   the window: the tooltip background tiled and tinted near-black inside
--   the vanilla chat tab's rim (cut into eight 5-unit pieces), the header
--   and rows 5 in from the edge; the header a lighter band of the same
--   tile (the window's tint x1.6 + 0.05) over a rim-grey hairline; the
--   bars the game's own status bar fill over a quarter-black track, no
--   row borders; the header buttons in vanilla button and spell art drawn
--   at 85% with 2 between them, a step brighter under the mouse.
-- ============================================================
local CLASSIC = {
    tile = "Interface\\Tooltips\\UI-Tooltip-Background",
    rim = "Interface\\ChatFrame\\ChatFrameTab",
    rimSize = 5,            -- one rim piece: shadow 2, rim 1, bevel 2
    body = 3,               -- the tile starts this far in (under the bevel)
    inset = 5,              -- the header and rows this far in (past the bevel)
    hdrShade = 1.6, hdrLift = 0.05,
    winTint = 16 / 255, winAlpha = 0.75,    -- #101010 at 75%, unless a window colour is picked
    line = 0.41,            -- the header's hairline: the rim's own grey
    iconScale = 0.85, iconGap = 2, idle = 0.85, hover = 1,
    gold = { 1, 0.82, 0 },  -- the game's own heading gold for the title
    -- the rim pieces: point, then the texcoords on the 64x32 sheet
    -- (measured on the sheet: corners at columns 2..6 / 57..61, rows 9..13;
    -- the top edge from columns 24..31; the sides from rows 20..23; the
    -- bottom pieces are the top ones flipped)
    uv = {
        { "TOPLEFT",     0.03125,  0.109375, 0.28125, 0.4375  },
        { "TOPRIGHT",    0.890625, 0.96875,  0.28125, 0.4375  },
        { "BOTTOMLEFT",  0.03125,  0.109375, 0.4375,  0.28125 },
        { "BOTTOMRIGHT", 0.890625, 0.96875,  0.4375,  0.28125 },
        { "TOP",         0.375,    0.5,      0.28125, 0.4375  },
        { "BOTTOM",      0.375,    0.5,      0.4375,  0.28125 },
        { "LEFT",        0.03125,  0.109375, 0.625,   0.75    },
        { "RIGHT",       0.890625, 0.96875,  0.625,   0.75    },
    },
}
Meter.CLASSIC = CLASSIC
-- the header buttons' vanilla art under the Classic look (crop: an icon's
-- bevel cut; l/r/t/b: a sheet's visible button; scale: inset in its box)
local CLASSIC_ART = {
    settings = { file = "Interface\\Icons\\Trade_Engineering", crop = 0.08, scale = 0.9 },
    segment  = { file = "Interface\\QuestFrame\\UI-QuestLog-BookIcon", l = 0.015625, r = 0.96875, t = 0.03125, b = 0.96875 },
    reset    = { file = "Interface\\Buttons\\UI-RefreshButton", scale = 0.9 },
    report   = { file = "Interface\\Icons\\INV_Misc_Note_01", crop = 0.08, scale = 0.9 },
    add      = { file = "Interface\\Buttons\\UI-PlusButton-Up" },
    close    = { file = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", l = 0.1875, r = 0.78125, t = 0.21875, b = 0.78125 },
    lock     = { file = "Interface\\Buttons\\LockButton-Locked-Up",   l = 0.1875, r = 0.78125, t = 0.21875, b = 0.78125 },
    unlock   = { file = "Interface\\Buttons\\LockButton-Unlocked-Up", l = 0.1875, r = 0.78125, t = 0.21875, b = 0.78125 },
}
-- each mode's vanilla spell icon (the classic header's mode button)
local CLASSIC_MODE = {
    damage_done = "INV_Sword_04", dps = "INV_Sword_04", damage_taken = "Ability_Warrior_ShieldWall",
    friendly_fire = "Spell_Fire_Fire", enemy_taken = "INV_Sword_27", heal_done = "Spell_Holy_Heal",
    hps = "Spell_Holy_Heal", overheal = "Spell_Holy_GreaterHeal", absorbs = "Spell_Holy_PowerWordShield",
    heal_taken = "Spell_Holy_Renew", deaths = "INV_Misc_Bone_HumanSkull_01", interrupts = "Ability_Kick",
    dispels = "Spell_Holy_DispelMagic", cc_breaks = "Spell_Nature_Polymorph", ress = "Spell_Holy_Resurrection",
    threat = "Ability_Warrior_DefensiveStance",
}
Meter.CLASSIC_ART, Meter.CLASSIC_MODE = CLASSIC_ART, CLASSIC_MODE

-- the look the meter wears now (a preview's Look.With answers too)
local function LookId()
    local L = ns.Look
    if not (L and L.For) then return "zacui" end
    local ok, l = pcall(L.For, "meter")
    return (ok and type(l) == "table" and l.id) or "zacui"
end
Meter.LookId = LookId
local function IsClassic() return LookId() == "classic" end
Meter.IsClassicLook = IsClassic

-- a whole-pixel size where the core can snap (crisp art at Era's scale)
local function Snap(v, frame)
    if ns.Snap and frame then
        local ok, s = pcall(ns.Snap, v, frame)
        if ok and type(s) == "number" and s > 0 then return s end
    end
    return v
end

-- ============================================================
-- SETTINGS READ HERE
-- ============================================================
-- the header mode: the saved one, else what the old pair of settings
-- said (a title bar switched on = the bar; otherwise the hover toolbar)
local function HeaderMode(d)
    d = d or Look()
    local m = d.headerMode
    if m == "bar" or m == "hover" or m == "none" then return m end
    if d.titleBar then return "bar" end
    return "hover"
end
Meter.HeaderMode = HeaderMode

local function HeaderHeight(d)
    return math.max(8, tonumber((d or Look()).titleHeight) or 18)
end
Meter.HeaderHeight = HeaderHeight

local function GrowUp(d) return (d or Look()).grow == "up" end

local function Snapping(win)
    local s = win.settings
    if s.snap == false then return false end
    return Look().snapWindows ~= false
end

-- ============================================================
-- THE HEADER ICONS - the toolbar sheet (five 32 px icons in a row) and
-- two glyphs drawn from plain strips (+ and x)
-- ============================================================
local TOOLBAR_ICON = { settings = "settings", segment = "segment", mode = "mode", report = "report", reset = "reset" }
-- the two the bar always keeps (2026-11-08: the others are there too when
-- the width allows, at rest and under the mouse alike - Win.FitTitle); the
-- reset lives in the window's settings menu (and on its key) - the
-- floating "hover" header keeps every icon as it was
local REST = { mode = true, settings = true }
local BAR_HIDDEN = { reset = true }
Meter.HEADER_REST = REST
local TOOLBAR_ORDER = { "winaction", "reset", "mode", "segment", "report", "settings" }
local TOOLBAR_TIPS = {
    winaction = { "New window", "Opens another meter window next to this one (five at most). Each window has its own mode and fight." },
    close     = { "Close window", "Parks this window. Window 1 keeps the + to open one again." },
    reset     = { "Reset data", "Wipes every fight and the overall." },
    mode      = { "Mode", "What this window shows: damage, healing, deaths, interrupts... or the threat list. "
        .. "Click for the mode tiles, right-click for the list." },
    segment   = { "Fight", "The fight in progress, the whole night, or any past fight by name." },
    report    = { "Report", "Pastes the rows to a chat channel." },
    settings  = { "This window", "Lock, click-through, the clock, scale, the header - and the Meter settings." },
}
Meter.TOOLBAR_ORDER = TOOLBAR_ORDER

-- A header button's picture. ZacUI's look: the white glyph, 40% at rest.
-- Classic look: the vanilla art (CLASSIC_ART), whole, at 85% brightness.
-- `name` is the glyph's file name (Zacui/Media/Icons); `art` the classic
-- entry, nil = keep the glyph. Re-run on every restyle (cheap).
local function PaintIcon(b, name, art)
    local t = b.icon
    if art then
        t:SetTexture(art.file)
        if art.crop then t:SetTexCoord(art.crop, 1 - art.crop, art.crop, 1 - art.crop)
        else t:SetTexCoord(art.l or 0, art.r or 1, art.t or 0, art.b or 1) end
        local w = b:GetWidth() or 0
        local inset = (art.scale and art.scale < 1) and (w * (1 - art.scale) / 2) or 0
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
        t:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)
        t:SetVertexColor(CLASSIC.idle, CLASSIC.idle, CLASSIC.idle, 1)
        t:SetAlpha(1)
        b.art = art
    else
        t:SetTexture(ICONS .. name)
        t:SetTexCoord(0, 1, 0, 1)
        t:ClearAllPoints()
        t:SetAllPoints(b)
        t:SetVertexColor(1, 1, 1, 1)
        t:SetAlpha(ICON_ALPHA)
        b.art = nil
    end
    b.paintedAs = name
end
Win.PaintIcon = PaintIcon

-- the mouse on a header button: the glyph brightens (0.4 -> 0.9), the
-- classic art steps up (0.85 -> 1). Nothing is drawn round the button
-- (2026-11-08: Zac's "weird bigger highlighting" was a square 2 px bigger
-- than the button on every side; the reference meter has none).
local function IconHover(b, on)
    if b.art then
        local k = on and CLASSIC.hover or CLASSIC.idle
        b.icon:SetVertexColor(k, k, k, 1)
    else
        b.icon:SetAlpha(on and ICON_HOVER_A or ICON_ALPHA)
    end
end
Win.IconHover = IconHover

-- the + / x button: ZacUI's add and close icons (or the vanilla ones)
local function Glyph(b, kind)
    local name = kind == "x" and "close" or "add"
    PaintIcon(b, name, IsClassic() and CLASSIC_ART[name] or nil)
    b.glyphKind = kind
end

local function CreateToolbar(win)
    local holder = CreateFrame("Frame", nil, win.frame)
    holder:SetSize(16 * #TOOLBAR_ORDER, 16)
    holder:SetAlpha(0)
    win.toolbar = holder
    win.toolbarButtons = {}
    for _, key in ipairs(TOOLBAR_ORDER) do
        local b = CreateFrame("Button", nil, holder)
        b:SetSize(16, 16)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        b.icon = t
        if TOOLBAR_ICON[key] then
            PaintIcon(b, TOOLBAR_ICON[key], nil)
        else
            Glyph(b, win.id == 1 and "+" or "x")
        end
        b:SetScript("OnEnter", function(self)
            IconHover(self, true)
            win:ShowToolbar(true)
            local tip = TOOLBAR_TIPS[(key == "winaction" and win.id ~= 1) and "close" or key]
            if tip and not win.preview then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                local tc, bc = ns.GetColor("tooltip", "title"), ns.GetColor("tooltip", "body")
                GameTooltip:AddLine(tip[1], tc.r, tc.g, tc.b)
                GameTooltip:AddLine(tip[2], bc.r, bc.g, bc.b, true)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function(self)
            IconHover(self, false)
            GameTooltip:Hide()
            win:ShowToolbar(false)
        end)
        b:SetScript("OnClick", function(_, button) win:ToolbarClick(key, button) end)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        win.toolbarButtons[key] = b
    end
end

-- THE HEADER'S ICONS (2026-11-08). Zac on Era: the title read "Dam..."
-- because five icons crowded the header the moment the mouse came, and the
-- icons sat in "weird bigger" hover squares. Now the bar's icons are a
-- fixed set, there at rest and under the mouse alike, chosen by the
-- window's WIDTH so the mode's name always reads whole: the settings cog
-- and the mode always; then, as room allows, the fight, the clock in the
-- title, the report and the + / x (Win.FitTitle decides, DROP_ORDER says
-- what goes first). An icon that has no room is in the cog's menu instead.
-- Order on screen, right to left: the two that always stay, then the
-- others (look.toolbarOrder, dragged in the preview, orders each group;
-- nil = TOOLBAR_ORDER). The floating "hover" header is unchanged: every
-- icon, overlapping by 3 px.
local DROP_ORDER = { "winaction", "report", "clock", "segment" }
Win.DROP_ORDER = DROP_ORDER

-- the bar's icons in `set`, right to left in win.barSeq, `gap` apart
local function PlaceBar(win, set)
    local tb = win.toolbar
    local size, gap = win.iconSize or 22, win.iconGap or ICON_GAP
    local last, n, sig = nil, 0, ""
    for _, key in ipairs(win.barSeq or {}) do
        local b = win.toolbarButtons[key]
        if set[key] then
            b:ClearAllPoints()
            if not last then b:SetPoint("RIGHT", tb, "RIGHT", 0, 0)
            else b:SetPoint("RIGHT", last, "LEFT", -gap, 0) end
            b.rest = true
            b:Show()
            b:SetAlpha(1)
            b:EnableMouse(true)
            n = n + 1
            sig = sig .. key .. ","
            last = b
        else
            b.rest = false
            b:Hide()
        end
    end
    local width = n > 0 and (n * size + (n - 1) * gap) or 0
    win.toolbarRestWidth, win.toolbarFullWidth = width, width
    win.barShown = set
    tb:SetSize(math.max(1, width), size)
    return width
end

local function LayoutToolbar(win, mode)
    local d = Look()
    local size = math.max(8, tonumber(d.headerIconSize) or 14)
    local bar = mode == "bar"
    local classic = IsClassic()
    local gap = ICON_GAP
    if bar and classic then
        size = math.floor(size * CLASSIC.iconScale + 0.5)
        gap = CLASSIC.iconGap
    end
    size = Snap(size, win.frame)
    win.iconSize, win.iconGap = size, gap
    local tb = win.toolbar
    local order = ns.OrderedList and ns.OrderedList(TOOLBAR_ORDER, d.toolbarOrder) or TOOLBAR_ORDER
    local seq = {}
    if bar then
        for i = #order, 1, -1 do if REST[order[i]] then seq[#seq + 1] = order[i] end end
        for i = #order, 1, -1 do
            local k = order[i]
            if not REST[k] and not BAR_HIDDEN[k] then seq[#seq + 1] = k end
        end
    else
        for i = #order, 1, -1 do seq[#seq + 1] = order[i] end
    end
    local inSeq = {}
    for _, k in ipairs(seq) do inSeq[k] = true end
    -- the pictures: the vanilla art under the Classic look, else the glyphs
    for _, key in ipairs(seq) do
        local b = win.toolbarButtons[key]
        b:SetSize(size, size)
        if key == "winaction" then
            -- the + / x follows the window's number (a parked window comes
            -- back under another)
            Glyph(b, win.id == 1 and "+" or "x")
        elseif key == "mode" then
            b.glyphPath = nil         -- (ModeGlyph paints it for the mode on show)
        elseif TOOLBAR_ICON[key] then
            PaintIcon(b, TOOLBAR_ICON[key], classic and CLASSIC_ART[key] or nil)
        end
    end
    for key, b in pairs(win.toolbarButtons) do
        if not inSeq[key] then b:Hide() b.rest = false end
    end
    if bar then
        win.barSeq = seq
        PlaceBar(win, inSeq)       -- every icon until FitTitle has measured the title
        if win.title then win.title.fitKey = nil end
    else
        win.barSeq = nil
        local last, width = nil, 0
        for _, key in ipairs(seq) do
            local b = win.toolbarButtons[key]
            b:ClearAllPoints()
            if not last then b:SetPoint("RIGHT", tb, "RIGHT", 0, 0)
            else b:SetPoint("RIGHT", last, "LEFT", 3, 0) end
            b.rest = true
            b:Show()
            width = width + (last and -3 or 0) + size
            last = b
        end
        win.toolbarRestWidth, win.toolbarFullWidth = width, width
        tb:SetSize(math.max(1, width), size)
    end
    tb:ClearAllPoints()
    if bar then
        tb:SetPoint("RIGHT", win.title, "RIGHT", -HEADER_PAD_R, 0)
        tb:SetFrameLevel(win.title:GetFrameLevel() + 2)
    elseif GrowUp(d) then
        tb:SetPoint("TOPRIGHT", win.frame, "BOTTOMRIGHT", 0, -2)
    else
        tb:SetPoint("BOTTOMRIGHT", win.frame, "TOPRIGHT", 0, 2)
    end
    tb:SetShown(mode ~= "none")
    tb:EnableMouse(mode ~= "none")
end
Win.ToolbarWidth = function(win)
    return win.toolbarFullWidth or 0
end

-- ============================================================
-- HOVER - the floating toolbar, the header icons (when they only show on
-- hover), the lock and the grip come and go with the mouse
-- ============================================================
-- LOCKED AS THE WINDOW BEHAVES NOW: its saved lock, except while Edit
-- Mode (ZacUI's mover mode) is open - every window is unlocked for the
-- pass, its lock glyph open and its grip up, and back to the saved lock
-- when the pass ends. Read only: the saved value is never written here.
local function Locked(win)
    if Win.editing then return false end
    return win.settings.locked and true or false
end
Win.Locked = Locked
function winMeta:IsLocked() return Locked(self) end

function winMeta:HoverAlphas(on)
    local d = Look()
    local mode = HeaderMode(d)
    local tb = self.toolbar
    if mode == "hover" then
        tb:SetAlpha((on or d.toolbarMode == "always") and HOVER_ALPHA or 0)
    elseif mode == "bar" then
        -- (2026-11-08) the bar's icons are the same at rest and under the
        -- mouse; only "icons only on hover" fades the whole set
        tb:SetAlpha((on or not d.headerIconsOnHover) and 1 or 0)
        self.hoverOn = on and true or false
    else
        tb:SetAlpha(0)
    end
    local a = on and 0.3 or 0
    if Win.editing then a = 0.7 end            -- Edit Mode: the corner in sight
    if self.grip then self.grip:SetAlpha(Locked(self) and 0 or a) end
    if self.lockBtn then self.lockBtn:SetAlpha(a) end
end

function winMeta:ShowToolbar(entering)
    self.hoverCount = (self.hoverCount or 0) + (entering and 1 or -1)
    if entering then
        self:HoverAlphas(true)
    else
        C_Timer.After(0.6, function()
            local f = self.frame
            if f:IsMouseOver() or self.toolbar:IsMouseOver()
                or (self.title and self.title:IsShown() and self.title:IsMouseOver()) then return end
            self:HoverAlphas(false)
        end)
    end
end

-- ============================================================
-- THE HEADER
-- ============================================================
local function EnsureTitle(win)
    if win.title then return win.title end
    local f = win.frame
    local t = CreateFrame("Frame", nil, f)
    t:SetFrameLevel(f:GetFrameLevel() + 3)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.text = t:CreateFontString(nil, "OVERLAY")
    t.text:SetPoint("LEFT", t, "LEFT", 4, 0)
    t.text:SetPoint("RIGHT", t, "RIGHT", -4, 0)
    t.text:SetJustifyH("LEFT")
    t.text:SetWordWrap(false)
    -- the fight clock, dimmer, just after the title (its own text)
    t.clock = t:CreateFontString(nil, "OVERLAY")
    t.clock:SetPoint("LEFT", t.text, "RIGHT", CLOCK_GAP, 0)
    t.clock:SetJustifyH("LEFT")
    t.clock:SetWordWrap(false)
    -- the hairline between the header and the rows
    t.line = t:CreateTexture(nil, "BORDER")
    t.line:Hide()
    t:Hide()
    if not win.preview then
        -- drag by the header, right-click for the mode menu
        t:EnableMouse(true)
        t:RegisterForDrag("LeftButton")
        t:SetScript("OnDragStart", function() t._zDragged = true win:BeginDrag() end)
        t:SetScript("OnDragStop", function() win:StopDrag() end)
        t:SetScript("OnMouseDown", function() t._zDragged = nil end)
        t:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then win:OpenDisplayMenu()
            -- a click on the title (not the end of a drag): the mode tiles
            elseif button == "LeftButton" and not t._zDragged and Meter.Tiles then Meter.Tiles.Toggle(win) end
            t._zDragged = nil
        end)
        t:SetScript("OnEnter", function() win:ShowToolbar(true) end)
        t:SetScript("OnLeave", function() win:ShowToolbar(false) end)
        if win.Scroll then
            t:EnableMouseWheel(true)
            t:SetScript("OnMouseWheel", function(_, delta) win:Scroll(delta) end)
        end
    end
    win.title = t
    return t
end

-- "Damage Done", "Overall Damage Done", "Damage Done  -  #3 Ragnaros"
-- and, dimmer after it, the fight's length "(2:13)" (the one in progress
-- ticking, the last one standing) unless the window hides it. t.full is
-- the whole line as one string ("Damage Done (2:13)").
-- the header's mode icon wears the glyph of the mode on show (the sword
-- for damage, the heart for healing...; Meter.Tiles.GLYPH)
local function ModeGlyph(win)
    local b = win.toolbarButtons and win.toolbarButtons.mode
    local T = Meter.Tiles
    if not (b and T and T.Glyph) then return end
    local key = win.settings.display
    local classic = IsClassic()
    local want = (classic and CLASSIC_MODE[key]) and ("C:" .. CLASSIC_MODE[key]) or T.Glyph(key)
    if b.glyphPath ~= want then
        b.glyphPath = want
        if classic and CLASSIC_MODE[key] then
            PaintIcon(b, "mode", { file = "Interface\\Icons\\" .. CLASSIC_MODE[key], crop = 0.08, scale = 0.85 })
        else
            PaintIcon(b, (T.GLYPH and T.GLYPH[key]) or "mode", nil)
        end
    end
end
Win.ModeGlyph = ModeGlyph

function Meter.UpdateTitle(win)
    ModeGlyph(win)
    local t = win.title
    if not (t and t:IsShown()) then return end
    local s = win.settings
    local text, clock
    if s.display == "threat" then
        text = "Threat"
    else
        local d = Look()
        local disp = Meter.DISPLAYS[s.display]
        text = disp and disp.label or ""
        local seg = s.segment or 0
        if d.titleSegment ~= false then
            if seg == -1 then
                text = "Overall " .. text .. (Meter.inCombat and " (live)" or "")
            elseif seg > 0 then
                text = text .. "  -  " .. win:SegmentLabel()
            elseif win.sampleSegment then
                -- the settings preview's Header mode names a past fight
                text = text .. "  -  " .. win.sampleSegment
            end
        end
        if seg ~= -1 and not s.hideClock and d.headerClock ~= false then
            local c = Meter.CombatForWindow(win)
            if c and c.GetCombatTime then clock = "(" .. Meter.Clock(c:GetCombatTime()) .. ")" end
        end
    end
    local full = clock and (text .. " " .. clock) or text
    if full ~= t.full or text ~= t.main or clock ~= t.clockText then
        t.full, t.main, t.clockText = full, text, clock
        t.fitKey = nil
    end
    Win.FitTitle(win)
end

-- THE TITLE AND THE ICONS SHARE THE BAR (2026-11-08). The mode's name is
-- never cut while an icon could make room for it: with every icon the
-- title and clock do not fit, the icons go in DROP_ORDER (+ / x, report,
-- then the clock, then the fight icon) down to the cog and the mode; only
-- then is the title cut with "...". Measured on a settings change, a
-- resize or a new title - never per frame, never on hover.
local function Measure(fs)
    local ok, w = pcall(fs.GetStringWidth, fs)
    if ok and type(w) == "number" then return w end
    return nil
end
function Win.FitTitle(win)
    local t = win.title
    local fs = t and t.text
    if not (fs and t:IsShown()) then return end
    local main, clock = t.main or t.full or "", t.clockText
    local room = (t:GetWidth() or 0) - HEADER_PAD_L - HEADER_PAD_R
    local bar = win.toolbar and win.toolbar:IsShown() and win.barSeq ~= nil and not win.iconsHidden
    if room <= 10 then return end
    local key = main .. "\1" .. tostring(clock) .. "\1" .. room .. "\1" .. tostring(bar)
        .. "\1" .. tostring(win.iconSize) .. "\1" .. tostring(win.barSeq and #win.barSeq)
    if t.fitKey == key then return end
    t.fitKey = key
    t.fitFull = t.full
    fs:SetText(main)
    -- the clock measured with every digit a 0: its width holds still while
    -- it ticks, so no icon blinks in and out at a width on the edge
    t.clock:SetText(clock and (clock:gsub("%d", "0")) or "")
    local measured = Measure(fs)
    local w = measured or 0
    local cw = clock and (Measure(t.clock) or 0) + CLOCK_GAP or 0
    t.clock:SetText(clock or "")
    local showClock = clock ~= nil
    local iconsW = 0
    if bar then
        local set, n = {}, 0
        for _, k in ipairs(win.barSeq) do set[k] = true n = n + 1 end
        local size, gap = win.iconSize or 22, win.iconGap or ICON_GAP
        local function IconsW(count)
            if count <= 0 then return 0 end
            return count * size + (count - 1) * gap + TITLE_ICON_GAP
        end
        if measured then
            for _, step in ipairs(DROP_ORDER) do
                if w + (showClock and cw or 0) + IconsW(n) <= room then break end
                if step == "clock" then
                    showClock = false
                elseif set[step] then
                    set[step] = nil
                    n = n - 1
                end
            end
        end
        iconsW = IconsW(n)
        PlaceBar(win, set)
        local dropped = {}
        for _, k in ipairs(win.barSeq) do if not set[k] then dropped[k] = true end end
        win.droppedIcons = dropped
    else
        win.droppedIcons = nil
    end
    local avail = room - iconsW
    if showClock and w + cw <= avail then
        fs:SetWidth(math.max(1, w + 1))
        t.clock:SetShown(true)
        return
    end
    -- no room for the clock: it goes; the title alone, cut if it must
    t.clock:SetText("")
    t.clock:Hide()
    if w <= avail then fs:SetWidth(math.max(1, w + 1)) return end
    local s = main
    while #s > 1 do
        s = s:sub(1, #s - 1)
        fs:SetText(s .. "...")
        local w2 = Measure(fs)
        if not w2 or w2 <= avail then break end
    end
    fs:SetWidth(math.max(1, avail))
end
-- the icons the bar had no room for (the cog's menu offers them)
function Win.Dropped(win, key)
    return win.droppedIcons ~= nil and win.droppedIcons[key] == true
end

-- the clock ticks once a second in combat; the refresh tick repaints the
-- title anyway, this keeps "(2:13)" moving between those
local clockTicker
local function ClockTick()
    if not Meter.inCombat then
        if clockTicker then clockTicker:Cancel() clockTicker = nil end
        return
    end
    for _, win in ipairs(windows) do
        if win.title and win.title:IsShown() and win.frame:IsVisible() then Meter.UpdateTitle(win) end
    end
end
function Win.ClockStart()
    if clockTicker then return end
    local any = false
    for _, win in ipairs(windows) do
        if win.title and win.title:IsShown() then any = true break end
    end
    if not any then return end
    clockTicker = C_Timer.NewTicker(1, ClockTick)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(clockTicker, "meter.clock") end
end
function Win.ClockStop()
    if clockTicker then clockTicker:Cancel() clockTicker = nil end
end

-- ============================================================
-- THE LOCK AND THE GRIP
-- ============================================================
function winMeta:UpdateLock()
    local locked = Locked(self)
    if self.lockTex then
        local art = IsClassic() and CLASSIC_ART[locked and "lock" or "unlock"] or nil
        if art then
            self.lockTex:SetTexture(art.file)
            self.lockTex:SetTexCoord(art.l or 0, art.r or 1, art.t or 0, art.b or 1)
        else
            self.lockTex:SetTexture(locked and TEX_LOCKED or TEX_UNLOCKED)
            self.lockTex:SetTexCoord(0, 1, 0, 1)
        end
    end
    if self.grip then
        self.grip:EnableMouse(not locked)
        if locked then self.grip:SetAlpha(0) end
    end
end

local function CreateCorner(win)
    local f = win.frame
    -- the grip: the game's own corner grabber, bottom-right
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    local gt = grip:CreateTexture(nil, "ARTWORK")
    gt:SetAllPoints()
    gt:SetTexture(TEX_GRIP)
    grip:SetAlpha(0)
    win.grip = grip
    -- the lock, left of it
    local lock = CreateFrame("Button", nil, f)
    lock:SetSize(14, 14)
    lock:SetPoint("RIGHT", grip, "LEFT", -1, 0)
    lock:SetFrameLevel(f:GetFrameLevel() + 10)
    local lt = lock:CreateTexture(nil, "ARTWORK")
    lt:SetAllPoints()
    lt:SetTexCoord(0, 1, 0, 1)      -- (ZacUI's own lock icons, whole)
    lock:SetAlpha(0)
    win.lockBtn, win.lockTex = lock, lt
    win:UpdateLock()
    if win.preview then return end
    grip:SetScript("OnEnter", function(self) self:SetAlpha(0.7) win:ShowToolbar(true) end)
    grip:SetScript("OnLeave", function(self) self:SetAlpha(Locked(win) and 0 or (Win.editing and 0.7 or 0.3)) win:ShowToolbar(false) end)
    grip:SetScript("OnMouseDown", function()
        if not Locked(win) then win.sizing = true f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function() win:StopDrag() end)
    lock:SetScript("OnEnter", function(self)
        self:SetAlpha(0.7)
        win:ShowToolbar(true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local tc, bc = ns.GetColor("tooltip", "title"), ns.GetColor("tooltip", "body")
        GameTooltip:AddLine(Locked(win) and "Locked" or "Unlocked", tc.r, tc.g, tc.b)
        if Win.editing then
            GameTooltip:AddLine("Edit Mode has every window unlocked; each goes back to its own lock when it ends.",
                bc.r, bc.g, bc.b, true)
        else
            GameTooltip:AddLine(Locked(win) and "Click to unlock: drag the window and resize it from this corner."
                or "Click to lock the window's place and size.", bc.r, bc.g, bc.b, true)
        end
        GameTooltip:Show()
    end)
    lock:SetScript("OnLeave", function(self) self:SetAlpha(Win.editing and 0.7 or 0.3) GameTooltip:Hide() win:ShowToolbar(false) end)
    lock:SetScript("OnClick", function()
        -- (Edit Mode puts every lock back when it ends: a click now would not stick)
        if Win.editing then return end
        win.settings.locked = not win.settings.locked
        win:UpdateLock()
        GameTooltip:Hide()
        if ns.SettingsChanged then ns.SettingsChanged("meter.lock") end
    end)
end

-- Edit Mode tells the windows when it opens and closes (ns.WatchEditMode,
-- after it has unlocked / restored each window's saved flag)
function Win.EditMode(on)
    Win.editing = on and true or false
    for _, win in ipairs(windows) do
        win:UpdateLock()
        win:HoverAlphas(false)
    end
end
if ns.WatchEditMode then ns.WatchEditMode(Win.EditMode) end

-- ============================================================
-- DRAG, RESIZE, SNAP
-- ============================================================
function winMeta:BeginDrag()
    local T = Meter.Threat
    if Locked(self) then return end
    if T and T.IsDocked and T.IsDocked(self) then return end
    self.frame:StartMoving()
    self.dragging = true
end

-- the nearest other window's edges and size, for the snap
local function Others(win)
    local out = {}
    for _, w in ipairs(windows) do
        if w ~= win and w.frame:IsShown() then out[#out + 1] = w.frame end
    end
    return out
end

local function SnapNear(value, targets)
    local best, dist = nil, SNAP + 1
    for _, t in ipairs(targets) do
        local dd = math.abs(value - t)
        if dd < dist then best, dist = t, dd end
    end
    return best
end

-- lines the window up with the nearest other window: its left or right
-- edge to theirs, its top or bottom to theirs
local function SnapPosition(win)
    local f = win.frame
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and r and t and b) then return false end
    local xs, ys = {}, {}
    for _, o in ipairs(Others(win)) do
        local ol, orr, ot, ob = o:GetLeft(), o:GetRight(), o:GetTop(), o:GetBottom()
        if ol and orr and ot and ob then
            xs[#xs + 1] = ol xs[#xs + 1] = orr
            ys[#ys + 1] = ot ys[#ys + 1] = ob
        end
    end
    if #xs == 0 then return false end
    local w, h = r - l, t - b
    local nl = SnapNear(l, xs)
    local nr = SnapNear(r, xs)
    local newL = nl or (nr and nr - w) or l
    local nt = SnapNear(t, ys)
    local nb = SnapNear(b, ys)
    local newT = nt or (nb and nb + h) or t
    if newL == l and newT == t then return false end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newL, newT)
    return true
end

local function SnapSize(win)
    local f = win.frame
    local w, h = f:GetWidth(), f:GetHeight()
    local ws, hs = {}, {}
    for _, o in ipairs(Others(win)) do
        ws[#ws + 1] = o:GetWidth()
        hs[#hs + 1] = o:GetHeight()
    end
    if #ws == 0 then return end
    local nw, nh = SnapNear(w, ws), SnapNear(h, hs)
    if nw or nh then f:SetSize(nw or w, nh or h) end
end

function winMeta:StopDrag()
    local f = self.frame
    f:StopMovingOrSizing()
    local wasSizing = self.sizing
    self.sizing, self.dragging = nil, nil
    local s = self.settings
    local T = Meter.Threat
    if wasSizing and Snapping(self) then SnapSize(self) end
    if T and T.IsDocked and T.IsDocked(self) then
        -- docked under the target frame: a resize keeps its size, and
        -- the window goes back under the frame (its own spot is kept)
        T.ApplyDock()
    else
        if not wasSizing and Snapping(self) then SnapPosition(self) end
        local point, _, _, x, y = f:GetPoint(1)
        s.point, s.x, s.y = point, x, y
    end
    s.w, s.h = f:GetWidth(), f:GetHeight()
    Meter.LayoutRows(self)
    if s.display == "threat" and T then T.SizeChanged(self) end
    Meter.RefreshWindow(self, true)
    Meter.UpdateTitle(self)
    if ns.SettingsChanged then ns.SettingsChanged("meter.drag") end
end

function winMeta:ApplyClickthrough()
    local through = self.settings.clickthrough and Meter.inCombat
    self.frame:EnableMouse(not through)
    if self.title then self.title:EnableMouse(not through) end
    for _, row in ipairs(self.rows) do
        row:EnableMouse(not through)
    end
end

-- ============================================================
-- MODE AND SEGMENT (the window's state, the label that says so)
-- ============================================================
function winMeta:SetDisplay(key)
    self.scroll = 0
    local settings = self.settings
    if settings.display == key then return end
    -- (the game's own meter is the damage window this session: a ZacUI
    -- window stays the threat window)
    if key ~= "threat" and not self.preview and Meter.UsesGameMeter and Meter.UsesGameMeter() then
        Print("Meter: the game's own damage meter is in use, so this window stays on threat. "
            .. "The Meter page's \"Damage windows\" switches back to ZacUI's.")
        return
    end
    if settings.display ~= "threat" and Meter.DISPLAYS[settings.display] then
        settings.lastMeterDisplay = settings.display
    end
    settings.display = key
    if key == "threat" then
        if Meter.Threat then Meter.Threat.Attach(self) end
    else
        if Meter.Threat then Meter.Threat.Detach(self) end
        Meter.RefreshWindow(self, true)
    end
    Meter.UpdateTitle(self)
    Meter.FlashLabel(self, key == "threat" and "Threat" or Meter.DISPLAYS[key].label)
end

function winMeta:SegmentLabel()
    local seg = self.settings.segment or 0
    if seg == 0 then return "Current fight" end
    if seg == -1 then return Meter.inCombat and "Overall (live)" or "Overall" end
    local combat = Meter.segments[seg]
    return "#" .. seg .. (combat and (" " .. combat:Name()) or "")
end

function winMeta:SetSegment(seg, fromSync)
    self.settings.segment = seg
    self.scroll = 0
    Meter.RefreshWindow(self, true)
    Meter.UpdateTitle(self)
    Meter.FlashLabel(self, self:SegmentLabel())
    -- every window that syncs its fight follows
    if not fromSync and self.settings.syncSegments then
        for _, w in ipairs(windows) do
            if w ~= self and w.settings.syncSegments and w.settings.display ~= "threat"
                and (w.settings.segment or 0) ~= seg then
                w:SetSegment(seg, true)
            end
        end
    end
end

function winMeta:ToolbarClick(key, button)
    if self.preview then return end
    local Menu = Meter.Menu
    local anchor = self.toolbarButtons and self.toolbarButtons[key] or self.toolbar
    if key == "winaction" then
        if self.id == 1 then Win.Add(self) else self:Close() end
    elseif key == "mode" or key == "attribute" then
        -- (match pass) a click: the mode tiles in the window; right-click:
        -- the list menu as before
        if button ~= "RightButton" and Meter.Tiles then
            Meter.Tiles.Toggle(self)
        elseif Menu then
            Menu.Mode(self, anchor)
        end
    elseif key == "segment" then
        if button == "MiddleButton" then
            self:SetSegment(0)
        elseif Menu then
            Menu.Segment(self, anchor)
        end
    elseif key == "report" then
        if Meter.OpenReport then Meter.OpenReport(self) end
    elseif key == "reset" then
        Win.Reset()
    elseif key == "settings" then
        if Menu then Menu.Settings(self, anchor) end
    end
end

-- the reset icon and the "Reset meter data" key: asks first when told to
function Win.Reset()
    if Look().confirmReset and UI and UI.Confirm then
        UI.Confirm({ title = "Reset the meter", text = "Every fight and the overall are wiped.",
            acceptText = "Reset", destructive = true, onAccept = function() Meter.ResetData() end })
    else
        Meter.ResetData()
    end
end

function winMeta:OpenDisplayMenu()
    if self.preview then return end
    if Meter.Menu then Meter.Menu.Mode(self, self.toolbarButtons and self.toolbarButtons.mode or self.toolbar) end
end

-- the wheel over the header's segment icon steps through the fights
local function WheelSegment(win, delta)
    local used = #Meter.segments
    local seg = win.settings.segment or 0
    if delta < 0 then
        seg = seg + 1
        if seg > used then seg = -1 end
    else
        seg = seg - 1
        if seg < -1 then seg = used end
    end
    win:SetSegment(seg)
end

-- ============================================================
-- STYLE - background, border, header, body, toolbar, corner: every
-- setting onto a window in place (live and preview alike)
-- ============================================================
-- a texture as the tooltip background tiled, in a colour (the file is near
-- white: the vertex colour is the tone); tiling set up once per texture
local function ClassicTile(tex, r, g, b, a)
    if not tex._zTiled then
        tex._zTiled = true
        tex:SetTexture(CLASSIC.tile, "REPEAT", "REPEAT")
        if tex.SetHorizTile then tex:SetHorizTile(true) end
        if tex.SetVertTile then tex:SetVertTile(true) end
    end
    tex:SetVertexColor(r, g, b, a)
end
local function UntileTex(tex)
    if not tex._zTiled then return end
    tex._zTiled = nil
    if tex.SetHorizTile then tex:SetHorizTile(false) end
    if tex.SetVertTile then tex:SetVertTile(false) end
end
Meter.ClassicTile = ClassicTile

-- the window's tint under the Classic look: its picked colour when the
-- background is on, else #101010 at 75%
local function ClassicWinTint(d)
    if d.bgShown then return Meter.WinBgColor(d) end
    return CLASSIC.winTint, CLASSIC.winTint, CLASSIC.winTint, CLASSIC.winAlpha
end
Meter.ClassicWinTint = ClassicWinTint

-- the classic box: the tinted tile and the chat tab's rim, built the first
-- time a window wears it, shown or hidden after that (a preview flips
-- between looks)
local function ClassicBox(win, on, d)
    local f = win.frame
    if on and not win.cTile then
        local tile = f:CreateTexture(nil, "BACKGROUND", nil, -7)
        tile:SetPoint("TOPLEFT", f, "TOPLEFT", CLASSIC.body, -CLASSIC.body)
        tile:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -CLASSIC.body, CLASSIC.body)
        win.cTile = tile
        local p = {}
        local e = CLASSIC.rimSize
        for i, spec in ipairs(CLASSIC.uv) do
            local t = f:CreateTexture(nil, "BORDER")
            t:SetTexture(CLASSIC.rim)
            t:SetTexCoord(spec[2], spec[3], spec[4], spec[5])
            if i <= 4 then t:SetSize(e, e) end
            p[spec[1]] = t
            p[#p + 1] = t
        end
        p.TOPLEFT:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        p.TOPRIGHT:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        p.BOTTOMLEFT:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        p.BOTTOMRIGHT:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        p.TOP:SetPoint("TOPLEFT", p.TOPLEFT, "TOPRIGHT", 0, 0)
        p.TOP:SetPoint("BOTTOMRIGHT", p.TOPRIGHT, "BOTTOMLEFT", 0, 0)
        p.BOTTOM:SetPoint("TOPLEFT", p.BOTTOMLEFT, "TOPRIGHT", 0, 0)
        p.BOTTOM:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "BOTTOMLEFT", 0, 0)
        p.LEFT:SetPoint("TOPLEFT", p.TOPLEFT, "BOTTOMLEFT", 0, 0)
        p.LEFT:SetPoint("BOTTOMRIGHT", p.BOTTOMLEFT, "TOPRIGHT", 0, 0)
        p.RIGHT:SetPoint("TOPLEFT", p.TOPRIGHT, "BOTTOMLEFT", 0, 0)
        p.RIGHT:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "TOPRIGHT", 0, 0)
        win.cRim = p
    end
    if not win.cTile then return end
    win.cTile:SetShown(on)
    for _, t in ipairs(win.cRim) do t:SetShown(on) end
    if on then ClassicTile(win.cTile, ClassicWinTint(d)) end
end
Win.ClassicBox = ClassicBox

function Meter.StyleWindow(win)
    local d = Look()
    local f = win.frame
    local classic = IsClassic()
    if d.bgShown and not classic then
        win.bg:SetColorTexture(Meter.WinBgColor(d))
    else
        win.bg:SetColorTexture(0, 0, 0, 0)
    end
    ClassicBox(win, classic, d)
    local on = (d.winBorder and not classic) and true or false
    local r, g, b, a = ColorOf(d.winBorderColor, 0, 0, 0, 1)
    for i = 1, 4 do
        win.edges[i]:SetColorTexture(r, g, b, a)
        win.edges[i]:SetShown(on)
    end
    PlaceEdges(win.edges, f, Pixels(d.winBorderSize))

    local mode = HeaderMode(d)
    local up = GrowUp(d)
    local t = EnsureTitle(win)
    -- under the Classic look the header and the rows sit inside the rim
    local ci = classic and CLASSIC.inset or 0
    win.bodyInset = ci
    t:ClearAllPoints()
    if mode == "bar" then
        t:SetHeight(HeaderHeight(d))
        if up then
            t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ci, ci)
            t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ci, ci)
        else
            t:SetPoint("TOPLEFT", f, "TOPLEFT", ci, -ci)
            t:SetPoint("TOPRIGHT", f, "TOPRIGHT", -ci, -ci)
        end
        if classic and not d.titleTexture then
            -- the window's own tile again, lighter: the band the stock
            -- meter's header makes (its opacity is the header colour's)
            local wr, wg, wb = ClassicWinTint(d)
            local _, _, _, ha = ColorOf(d.titleColor, 0, 0, 0, 1)
            ClassicTile(t.bg, math.min(1, wr * CLASSIC.hdrShade + CLASSIC.hdrLift),
                math.min(1, wg * CLASSIC.hdrShade + CLASSIC.hdrLift),
                math.min(1, wb * CLASSIC.hdrShade + CLASSIC.hdrLift), ha)
        else
            UntileTex(t.bg)
            t.bg:SetTexture(Meter.TexPath(d.titleTexture, FLAT_TEX))
            t.bg:SetVertexColor(ColorOf(d.titleColor, 0, 0, 0, 0.69))
        end
        ns.ApplyFontSpec(t.text, d.titleFont, Meter.TitleFontDefaults(d))
        ns.ApplyFontSpec(t.clock, d.titleFont, Meter.TitleFontDefaults(d))
        -- (match pass) the mode's name in the accent colour and the clock
        -- white at 70% after it (look.titleAccent; off: the title as the
        -- font left it and the clock its colour at 55%, as before)
        if classic and d.titleAccent ~= false then
            -- (Classic look) the game's own heading gold
            t.text:SetTextColor(CLASSIC.gold[1], CLASSIC.gold[2], CLASSIC.gold[3], 1)
            t.clock:SetTextColor(1, 1, 1, 0.7)
        elseif d.titleAccent ~= false then
            local ac = ns.GetColor("ui", "accent")
            t.text:SetTextColor(ac.r, ac.g, ac.b, 1)
            t.clock:SetTextColor(1, 1, 1, 0.7)
        else
            t.text:SetTextColor(1, 1, 1, 1)
            local tr, tg, tbb = 1, 1, 1
            if t.text.GetTextColor then
                local ok, r1, g1, b1 = pcall(t.text.GetTextColor, t.text)
                if ok and type(r1) == "number" then tr, tg, tbb = r1, g1, b1 end
            end
            t.clock:SetTextColor(tr, tg, tbb, 0.55)
        end
        -- the line under the header (over it when the list grows up)
        local ln = t.line
        ln:ClearAllPoints()
        ln:SetHeight(Pixels(1))
        if up then
            ln:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
            ln:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, 0)
        else
            ln:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
            ln:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
        end
        -- one physical pixel through UI scale changes (ns.Pixel, Core_Pixel, where the core has it)
        -- (under ZacUI's own look only: other looks keep Meter.Pixels' line)
        if ns.Pixel and ns.Pixel.Edge and not (ns.Look and ns.Look.Active and ns.Look.Active() ~= "zacui") then
            pcall(ns.Pixel.Edge, ln, up and "TOP" or "BOTTOM", t, 1)
        end
        if classic then
            -- (Classic look) one hairline in the rim's own grey, always
            ln:SetColorTexture(CLASSIC.line, CLASSIC.line, CLASSIC.line, 1)
            ln:Show()
        else
            ln:SetColorTexture(ColorOf(d.headerLineColor, 1, 1, 1, 0.1))
            ln:SetShown(d.headerLine ~= false)
        end
        -- its spot: the bar's left edge, sized to its text (the clock
        -- follows it), or the saved one
        local td = t.anchorDef or {}
        t.anchorDef = td
        td.point, td.to, td.relPoint, td.x, td.y, td.justify = "LEFT", t, "LEFT", HEADER_PAD_L, 0, "LEFT"
        td.point2, td.relPoint2, td.x2, td.y2 = nil, nil, nil, nil
        if not t.anchorTo then
            t.anchorTo = function(k) if k == "titlebar" then return t end end
        end
        local A = type(d.anchors) == "table" and d.anchors.title or nil
        ns.ApplyAnchor(t.text, A, td, t.anchorTo)
        t.fitKey = nil
        t:Show()
    else
        t:Hide()
    end

    -- the body: under the header, or the whole window
    local body = win.rowframe
    body:ClearAllPoints()
    if mode == "bar" then
        if up then
            body:SetPoint("TOPLEFT", f, "TOPLEFT", ci, -ci)
            body:SetPoint("BOTTOMRIGHT", t, "TOPRIGHT", 0, 0)
        else
            body:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, 0)
            body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ci, ci)
        end
    elseif ci > 0 then
        body:SetPoint("TOPLEFT", f, "TOPLEFT", ci, -ci)
        body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ci, ci)
    else
        body:SetAllPoints(f)
    end

    LayoutToolbar(win, mode)
    win.iconsHidden = (mode == "bar" and d.headerIconsOnHover) and true or false
    win:HoverAlphas(f:IsMouseOver() or win.toolbar:IsMouseOver())
    if mode == "bar" then Meter.UpdateTitle(win) end
    if win.flash then ns.ApplyFontSpec(win.flash.text, d.titleFont, Meter.TitleFontDefaults(d)) end
    win:UpdateLock()
    if ns.Look and ns.Look.Dress then ns.Look.Dress(f, "meterWindow", "meter") end
end

-- ============================================================
-- THE FRAME - the parts every window has, live or preview
-- ============================================================
local function BuildWindowFrame(win, parent, name)
    local settings = win.settings
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(settings.w, settings.h)
    win.frame = f
    rawset(f, "_zMeterWin", win)        -- (the Look's dresser finds its window)

    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    win.bg = bg
    win.edges = {}
    for i = 1, 4 do
        local e = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        e:Hide()
        win.edges[i] = e
    end

    -- the body: the rows' parent, under the header when there is one
    win.rowframe = CreateFrame("Frame", nil, f)
    win.rowframe:SetAllPoints()
    EnsureTitle(win)
    CreateToolbar(win)
    CreateCorner(win)
    return f
end

-- a live window's own scripts: hover, drag, wheel, right-click, mover
local function WireWindow(win)
    local f, settings = win.frame, win.settings
    f:SetFrameStrata("LOW")
    f:SetPoint(settings.point, UIParent, settings.point, settings.x, settings.y)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(100, 50)
    elseif f.SetMinResize then f:SetMinResize(100, 50) end
    f:SetClampedToScreen(true)
    f:SetScale(tonumber(settings.scale) or 1)

    -- window-level mouse: hover reveals the icons, drag moves when
    -- unlocked (the gaps between rows and the empty bottom are the frame)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() win:BeginDrag() end)
    f:SetScript("OnDragStop", function() win:StopDrag() end)
    f:SetScript("OnEnter", function() win:ShowToolbar(true) end)
    f:SetScript("OnLeave", function() win:ShowToolbar(false) end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not win.dragging then win:OpenDisplayMenu() end
    end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) win:Scroll(delta) end)
    local segBtn = win.toolbarButtons.segment
    segBtn:EnableMouseWheel(true)
    segBtn:SetScript("OnMouseWheel", function(_, delta) WheelSegment(win, delta) end)

    -- when the windows show (look.visibility, ZacUI's visibility shape:
    -- in combat, in a group, opacity, mouseover...). Alpha only; nothing
    -- saved = the window is never touched. A window's own rule wins.
    if ns.Visibility and ns.Visibility.Register then
        ns.Visibility.Register(f, function()
            local own = win.settings.visibility
            if type(own) == "table" and next(own) then return own end
            return Look().visibility
        end, { control = "alpha" })
    end
end

local parked = {}      -- closed windows, their frames kept for the next +
Win.parked = parked

local function Alias(win)
    _G["ZacUIMeterWindow" .. win.id] = win.frame
end

-- ============================================================
-- THE GAME'S OWN METER (WoW Forever and Retail, 2026-11-08). Zac: "in
-- forever and retail isnt there a blizzard made damage meter? for those
-- settings in the options make sure the damage meters use those options
-- by default". Those clients ship Blizzard's damage meter (the
-- Blizzard_DamageMeter window over C_DamageMeter, switched by the CVar
-- damageMeterEnabled, set up in the game's own Edit Mode). So:
--   * under the game looks (WoW Forever, Blizzard style) the damage
--     windows are the GAME'S by default: ZacUI builds no damage window,
--     the game's meter is switched on (once: ZacUI notes that it did),
--     and its look and options are the game's (Edit Mode). The threat
--     window is ZacUI's own feature and stays.
--   * under ZacUI's look (and Classic) ZacUI's windows stay; they read the
--     game's meter for their numbers (Meter_GameMeter / Meter_Win_Live)
--     because these clients give addons no combat log. A game meter ZacUI
--     switched on is switched back off, so two meters never double up.
--   * look.gameMeter overrides the look either way (the Meter page's
--     "Damage windows" choice); nil = the look decides.
-- Era and TBC: no such meter, none of this runs (Available() is false).
-- ============================================================
local GM_CVAR = "damageMeterEnabled"
local function GetCV(name)
    local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    if not get then return nil end
    local ok, v = pcall(get, name)
    if ok then return v end
    return nil
end
local function SetCV(name, v)
    local set = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
    if not set then return false end
    return (pcall(set, name, v))
end
-- this client has the game's own meter window
function Win.GameMeterAvailable()
    if not (_G.ZACUI_MODERN or (ns.ModernClient and ns.ModernClient())) then return false end
    if not C_DamageMeter then return false end
    return GetCV(GM_CVAR) ~= nil
end
-- the look alone would pick the game's meter
function Win.LookPrefersGameMeter()
    local id = LookId()
    return id == "forever" or id == "blizzard"
end
-- the damage windows are the game's this session
function Meter.UsesGameMeter()
    if not Win.GameMeterAvailable() then return false end
    local v = Look().gameMeter
    if v == nil then return Win.LookPrefersGameMeter() end
    return v and true or false
end
-- (2026-11-08, Zac: "why is the blizzard damage meter on when i went to
-- zui style?") ZacUI's damage windows are the meter under ZacUI's own
-- look, or by the page's "ZacUI's meter" choice: the game's meter window
-- is then OFF, whoever switched it on (the game's default, a game look
-- before, the player in Edit Mode). Its numbers still reach ZacUI's
-- windows: C_DamageMeter keeps counting with the window off. Only the
-- page's "The game's own meter" choice keeps it (then UsesGameMeter).
function Win.GameMeterKeptOff()
    if Meter.UsesGameMeter() then return false end
    local v = Look().gameMeter
    if v == false then return true end
    return v == nil and LookId() == "zacui"
end
-- the game's meter switched on when it is the one in use, off under
-- ZacUI's own meter (above), and otherwise back off only when ZacUI
-- switched it on and ZacUI's windows are back (under Classic a player's
-- own choice in the game's options is never undone)
function Win.SyncGameMeter()
    if not Win.GameMeterAvailable() then return end
    local d = Look()
    local cur = tostring(GetCV(GM_CVAR) or "")
    if Meter.UsesGameMeter() then
        if cur == "0" and SetCV(GM_CVAR, "1") then d.gameMeterSwitchedOn = true end
    elseif Win.GameMeterKeptOff() then
        if cur ~= "0" then SetCV(GM_CVAR, "0") end
        d.gameMeterSwitchedOn = nil
    elseif d.gameMeterSwitchedOn then
        if cur == "1" then SetCV(GM_CVAR, "0") end
        d.gameMeterSwitchedOn = nil
    end
end
-- the game's meter is set up in its own Edit Mode (the page's button)
function Win.OpenGameMeterOptions()
    if InCombatLockdown and InCombatLockdown() then
        Print("Meter: the game's Edit Mode opens out of combat.")
        return false
    end
    local em = _G.EditModeManagerFrame
    if em and ShowUIPanel then
        local ok = pcall(ShowUIPanel, em)
        if ok then return true end
    end
    Print("Meter: the game's damage meter is set up in its Edit Mode (Game menu > Edit Mode).")
    return false
end

-- a window slot ZacUI does not build while the game's meter is in use
local function GameOwns(settings)
    return settings.display ~= "threat" and Meter.UsesGameMeter()
end
Win.GameOwns = GameOwns

-- a live window for slot `id` of the saved list: a parked one brought
-- back, else a new one
function Win.Create(id)
    local d = Look()
    local settings = d.windows[id]
    if not settings then return nil end
    if not Win.gmSynced then Win.gmSynced = true Win.SyncGameMeter() end
    -- (the game's meter is the damage window this session)
    if GameOwns(settings) then return nil end
    local win = table.remove(parked)
    if win then
        win.id, win.settings = id, settings
        win.rows = win.rows or {}
        local f = win.frame
        f:ClearAllPoints()
        f:SetSize(settings.w, settings.h)
        f:SetPoint(settings.point, UIParent, settings.point, settings.x, settings.y)
        f:SetScale(tonumber(settings.scale) or 1)
        f:Show()
        win.scroll = 0
        win.parkedAt = nil
    else
        win = setmetatable({ id = id, settings = settings, rows = {} }, winMeta)
        BuildWindowFrame(win, UIParent, "ZacUIMeterWindow" .. id)
        WireWindow(win)
    end
    Alias(win)
    if Win.keyHidden then win.frame:Hide() end
    Meter.StyleWindow(win)
    for _, row in ipairs(win.rows) do Meter.StyleRow(row) end
    Meter.LayoutRows(win)
    if settings.display == "threat" and Meter.Threat then
        Meter.Threat.Attach(win)
    end
    win:ApplyClickthrough()
    if ns.Visibility and ns.Visibility.Refresh then ns.Visibility.Refresh(win.frame) end
    -- dense append: ipairs walks this everywhere, and a closed window 1
    -- must never hide window 2 behind a nil hole (the ipairs lesson)
    windows[#windows + 1] = win
    Meter.RefreshWindow(win, true)
    return win
end

-- where a new window goes: above the one it came from, or below it when
-- the top of the screen is in the way
local function PlaceNext(from, new)
    local f = from.frame
    local l, t, b = f:GetLeft(), f:GetTop(), f:GetBottom()
    local h = new.h
    if l and t and b and UIParent.GetTop then
        local top = UIParent:GetTop() or 0
        local newBottom = t + GAP
        if top > 0 and newBottom + h > top then newBottom = b - GAP - h end
        new.point, new.x, new.y = "BOTTOMLEFT", l, newBottom
        return
    end
    new.point, new.x = from.settings.point, from.settings.x
    new.y = (from.settings.y or 0) + h + GAP
end

-- the + : another window next to `from` (window 1), looking like it
function Win.Add(from)
    local d = Look()
    if Meter.UsesGameMeter() then
        Print("Meter: the game's own damage meter is in use; its windows are set up in Edit Mode. "
            .. "The Meter page's \"Damage windows\" switches back to ZacUI's.")
        return nil
    end
    if #d.windows >= Win.MAX then
        Print(format("Meter: %d windows is the most it opens.", Win.MAX))
        return nil
    end
    from = from or windows[1]
    local src = from and from.settings or {}
    local display = src.display
    if display == "threat" or not Meter.DISPLAYS[display or ""] then display = src.lastMeterDisplay or "damage_done" end
    local new = {
        open = true, display = display, lastMeterDisplay = display,
        point = src.point or "BOTTOMRIGHT", x = src.x or 0, y = src.y or 0,
        w = src.w or 225, h = src.h or 200,
        locked = false, clickthrough = src.clickthrough or false, segment = 0,
    }
    if from then PlaceNext(from, new) end
    d.windows[#d.windows + 1] = new
    local win = Win.Create(#d.windows)
    if ns.SettingsChanged then ns.SettingsChanged("meter.windows") end
    return win
end

-- out of the live list and into the parked ones, its frame kept
local function Park(win)
    if Meter.Tiles and Meter.Tiles.Hide then Meter.Tiles.Hide(win) end
    if win.settings.display == "threat" and Meter.Threat then Meter.Threat.Detach(win) end
    for i, w in ipairs(windows) do
        if w == win then table.remove(windows, i) break end
    end
    win.frame:Hide()
    win.parkedAt = win.id
    parked[#parked + 1] = win
end

-- the x : this window is parked and the saved list closes up behind it
-- (window 1 only closes: its entry stays, the page's "Show window 1"
-- brings it back)
function winMeta:Close()
    if self.preview or self.parkedAt then return end
    if self.id == 1 then
        Win.SetOpen(1, false)
        return
    end
    local d = Look()
    local idx = self.id
    Park(self)
    table.remove(d.windows, idx)
    _G["ZacUIMeterWindow" .. (#d.windows + 1)] = nil
    -- the windows after it move up one, keeping their saved tables
    for _, w in ipairs(windows) do
        if w.id > idx then
            w.id = w.id - 1
            w.settings = d.windows[w.id]
            Alias(w)
            LayoutToolbar(w, HeaderMode(d))
        end
    end
    if ns.SettingsChanged then ns.SettingsChanged("meter.windows") end
end

-- the page's "Show window i": a live open or close
function Win.SetOpen(id, open)
    local d = Look()
    local s = d.windows[id]
    if not s then return end
    s.open = open and true or false
    local live
    for _, w in ipairs(windows) do if w.settings == s then live = w break end end
    if open and not live then
        Win.Create(id)
    elseif not open and live then
        -- the entry stays (the page lists it); only the header's x on
        -- windows 2-5 takes the entry away
        Park(live)
    end
    if ns.SettingsChanged then ns.SettingsChanged("meter.windows") end
end

-- ============================================================
-- PREVIEW WINDOW - a window for the settings page's preview: the same
-- frame, rows, header and styling as a live one, parented to the
-- preview canvas, never in the window list (no refresh tick, no combat
-- hooks, no movers), with no tooltips, menus or dragging, fed a made-up
-- fight instead of a segment.
-- ============================================================
function Meter.NewPreviewWindow(parent, w, h)
    local settings = { display = "damage_done", segment = 0, locked = true, w = w or 226, h = h or 200 }
    local win = setmetatable({ id = 0, settings = settings, rows = {}, preview = true }, winMeta)
    BuildWindowFrame(win, parent, nil)
    -- the pick hook: a click on the sample's title or icons opens their settings
    if ns.TagElement then
        ns.TagElement(win.title.text, "meter.title")
        ns.TagElement(win.toolbar, "meter.headerIcons")
    end
    win.frame:SetScript("OnEnter", function() win:ShowToolbar(true) end)
    win.frame:SetScript("OnLeave", function() win:ShowToolbar(false) end)
    Meter.StyleWindow(win)
    Meter.LayoutRows(win)
    return win
end

-- restyle a preview window and refill it from `combat` showing `display`
function Meter.FillPreviewWindow(win, combat, display)
    win.fakeCombat = combat
    win.settings.display = display
    Meter.StyleWindow(win)
    for _, row in ipairs(win.rows) do Meter.StyleRow(row) end
    Meter.LayoutRows(win)
    Meter.RefreshMeterWindow(win, true)
    Meter.UpdateTitle(win)
end

-- ============================================================
-- RESTYLE - every setting onto what is already on screen
-- ============================================================
-- Size and place a window from its settings (the Position tab), unless
-- the threat dock places it.
local function ApplyGeometry(win)
    local f, s = win.frame, win.settings
    if s.w and s.h then f:SetSize(s.w, s.h) end
    f:SetScale(tonumber(s.scale) or 1)
    local T = Meter.Threat
    if T and T.IsDocked and T.IsDocked(win) then
        T.ApplyDock()
    elseif s.point then
        f:ClearAllPoints()
        f:SetPoint(s.point, UIParent, s.point, s.x or 0, s.y or 0)
    end
end

-- the live windows follow the saved list: an entry shown and not built is
-- built, a built one hidden is parked (a profile, the page's undo, the
-- Show checkboxes all land here)
local function Reconcile()
    local d = Look()
    for _, win in ipairs(windows) do
        local listed = false
        for _, s in ipairs(d.windows) do if s == win.settings then listed = true break end end
        if not (listed and win.settings.open) or GameOwns(win.settings) then Park(win) return Reconcile() end
    end
    for id, s in ipairs(d.windows) do
        if s.open then
            local live = false
            for _, win in ipairs(windows) do if win.settings == s then live = true break end end
            if not live then Win.Create(id) end
        end
    end
    -- a window's number follows its place in the saved list
    for _, win in ipairs(windows) do
        for id, s in ipairs(d.windows) do
            if win.settings == s and win.id ~= id then win.id = id Alias(win) end
        end
    end
end
Win.Reconcile = Reconcile

function Meter.RestyleAll()
    if Win.gmSynced then Win.SyncGameMeter() end
    Reconcile()
    for _, win in ipairs(windows) do
        ApplyGeometry(win)
        Meter.StyleWindow(win)
        for _, row in ipairs(win.rows) do Meter.StyleRow(row) end
        Meter.LayoutRows(win)
        local T = Meter.Threat
        if win.threatRows and T then
            for _, row in ipairs(win.threatRows) do T.StyleRow(row) end
            T.SizeChanged(win)
        end
        Meter.RefreshWindow(win, true)
        if ns.Visibility and ns.Visibility.Refresh then ns.Visibility.Refresh(win.frame) end
    end
end
Meter.RestyleMedia = Meter.RestyleAll

-- "Rebuild the windows" (the page's Advanced tab): every window parked and
-- built again from the saved list, so a new look or a lost window is
-- back without a reload
function Win.Rebuild()
    -- parked highest number first, so each comes back on its own frame
    local list = {}
    for _, w in ipairs(windows) do list[#list + 1] = w end
    table.sort(list, function(a, b) return a.id > b.id end)
    for _, w in ipairs(list) do Park(w) end
    Reconcile()
    Meter.RestyleAll()
end

-- ============================================================
-- THE KEYS (Zacui/Bindings.xml, header ZACUIMETER): show / hide every
-- meter window - a flag for this session only, never saved, that wins
-- over the windows' visibility rules - and reset the data (asking first
-- when "Ask before reset" is on).
-- ============================================================
_G.BINDING_HEADER_ZACUIMETER = "ZacUI damage meter"
_G.BINDING_NAME_ZACUI_METER_TOGGLE = "Meter: show / hide the windows"
_G.BINDING_NAME_ZACUI_METER_RESET = "Meter: reset the data"
function Win.ToggleShown()
    Win.keyHidden = not Win.keyHidden
    for _, win in ipairs(windows) do win.frame:SetShown(not Win.keyHidden) end
    if Win.keyHidden and not Win.saidKey then
        Win.saidKey = true
        Print("Meter: windows hidden until you press the Toggle meter windows key again.")
    end
end
_G.ZacUI_MeterToggle = function() Win.ToggleShown() end
_G.ZacUI_MeterReset = function() Win.Reset() end

-- ============================================================
-- THE LOOK (Core_Look): under "Classic WoW UI" a meter window wears the
-- look's small-box edge round it and the tooltip's band behind its header.
-- Under ZacUI's own look Look.Dress returns before reaching this, so the
-- window is drawn exactly as above.
-- ============================================================
if ns.Look and type(ns.Look.dressers) == "table" then
    ns.Look.dressers.meterWindow = function(frame, look)
        local win = rawget(frame, "_zMeterWin")
        if not (win and look) then return end
        -- (2026-11-08) the Classic look's box is StyleWindow's own (the
        -- tooltip tile in the chat tab's rim); nothing more to lay on
        if look.id == "classic" then return end
        local d = Look()
        local spec = look.border
        if type(spec) == "table" and spec.style == "edge" and ns.Look.AddEdge then
            for i = 1, 4 do win.edges[i]:Hide() end
            ns.Look.AddEdge(frame, spec, 1, 1, 1, 1)
        end
        local t = win.title
        if t and t:IsShown() and not d.titleTexture and look.bgSmall then
            t.bg:SetTexture(look.bgSmall)
        end
    end
end

-- the clock runs while a fight does
local origStart, origEnd = Meter.OnCombatStart, Meter.OnCombatEnd
Meter.OnCombatStart = function(...)
    if origStart then origStart(...) end
    for _, win in ipairs(windows) do
        -- a window on a past fight comes back to the one starting, unless told not to
        if (win.settings.segment or 0) > 0 and win.settings.autoCurrent ~= false then
            win.settings.segment = 0
        end
        Meter.UpdateTitle(win)
    end
    Win.ClockStart()
end
Meter.OnCombatEnd = function(...)
    if origEnd then origEnd(...) end
    Win.ClockStop()
    for _, win in ipairs(windows) do Meter.UpdateTitle(win) end
end
