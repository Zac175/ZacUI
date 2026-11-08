-- UIF_Controls - ZacUI's OWN widgets, for ZacUI's own windows.
-- Part of ZacUI; load order is set by the TOC.
--
-- The distinction that matters in this addon: UIF_Base and UIF_Widgets
-- RESKIN frames Blizzard built. This file BUILDS frames. They share a
-- palette and a look and nothing else - a skinner has to work around
-- whatever art it finds, a builder gets to be exact.
--
-- HOUSE RULES, applied without exception:
--   * Flat fills, 1px black borders, square corners. No gradients on
--     furniture (normTex is a bar texture, reserved for fills that want
--     a slight vertical lift), no rounded art, no drop shadows.
--   * A single gold accent - a 1px rule under a title, a 3px bar down a
--     card's left edge, hover text. Never a gold fill.
--   * Hover is instant. Nothing here tweens on OnEnter.
--   * Every widget stores a _zPaint closure. Repaint(root) walks a tree
--     and calls them, which is what lets the colour editor show its work
--     without a reload.
--   * Colours are read INSIDE _zPaint, never captured at build time.
--   * Every control that changes a value raises ns.SettingsChanged()
--     (UIF_Settings) AFTER the page's own callback has run - that is how
--     the preview dock and anything else listening hear about it without
--     a page doing anything.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local PopOut = ns.PopOut
local ResolveFontPath = ns.ResolveFontPath
local SharpenIcon = ns.SharpenIcon
local TEX_ARROW = ns.TEX_ARROW
local TEX_ARROWL = ns.TEX_ARROWL
local TEX_CHECK = ns.TEX_CHECK
local TEX_NORM = ns.TEX_NORM
local TEX_THUMB = ns.TEX_THUMB

local UI = {}

-- The "a setting changed" signal (UIF_Settings), looked up when raised so
-- a widget never fails because a listener file is missing.
local function Changed(source)
    -- (quiet while a pooled widget is handed back and re-reads its
    -- settings: nothing changed, see UIF_Pool)
    if UI._zQuiet then return end
    if ns.SettingsChanged then ns.SettingsChanged(source) end
end
UI.Changed = Changed

-- Every dropdown menu ever built. They are parented to UIParent (they have
-- to be - a menu clipped to its card is useless), which means clearing a
-- page cannot reach them. This list is how the config window closes any
-- that are still open when it switches page or hides.
local openMenus = {}

-- ============================================================
-- GRID
-- ============================================================
-- One table of numbers, so "make everything 2px tighter" is one edit and
-- not an afternoon. Anything that hardcodes a spacing below is a bug.
local M = {
    BORDER      = 1,
    MARGIN      = 18,   -- page edge -> card edge
    CARD_PAD    = 12,   -- card edge -> card title
    CARD_GAP    = 14,   -- card -> card
    CONTROL_X   = 14,   -- card edge -> control
    DESC_X      = 30,   -- card edge -> description text
    CONTENT_Y   = -32,  -- card top -> first control
    ROW         = 23,   -- checkbox / plain row stride
    ROW_LOOSE   = 27,
    BLOCK       = 44,   -- slider or dropdown block stride
    BUTTON_H    = 22,
    BUTTON_W    = 110,
    CHECK       = 14,
    DROPDOWN_H  = 24,
    EDIT_H      = 22,
    SLIDER_W    = 190,
    TRACK_H     = 6,
    THUMB       = 14,
    SCROLL_W    = 16,
    WHEEL       = 24,   -- a wheel notch in a scroll area (eased: ScrollArea)
    TITLEBAR    = 30,
    ROW_H       = 28,   -- sidebar nav row
    SIDEBAR_W   = 186,
}

local F = {  -- font sizes by role
    TITLE  = 15,
    HEADER = 15,
    SUB    = 11,
    CARD   = 12,
    LABEL  = 11,
    DESC   = 10,
    SMALL  = 10,
    NAV    = 12,
    NAVSUB = 11,
}

-- ============================================================
-- THE SETTINGS WINDOW'S LOOK (match pass, 2026-11-07)
-- ============================================================
-- The /zui window is built to EllesmereUI's options window, number for
-- number (zui_tests/MATCH_OPTIONS_1107.md has every value with the line
-- it was read from; ours is our own code, theirs is all rights reserved).
-- Everything built while UI._zSettings is on (Config_Window's page builds,
-- Config_Search's index builds) reads these instead of M / F; ZacUI's
-- other windows keep M / F and look as they did. Colours: white at a
-- stepped alpha over a warm near-black, the accent the only hue (ZacUI's
-- gold, from the palette). A colour picked in the palette editor still
-- wins over the shipped value (UI.SCol).
local S = {
    -- the window
    W = 1300, H = 946, MIN_W = 1000, MIN_H = 640, MAX_W = 1600, MAX_H = 1100,
    SIDEBAR = 295, HEADER = 138, TABS = 40, FOOTER = 82,
    PAD = 45, TOP_PAD = 10, SIDE = 20, CARD_GAP = 10, SECTION = 40,
    -- the sidebar
    NAV_TOP = 114, NAV_ROW = 40, NAV_ICON_W = 45, NAV_ICON_H = 32, NAV_LEFT = 20, NAV_GAP = 10,
    GROUP_ROW = 28, CHILD_ROW = 28, GROUP_GAP = 10, CHILD_X = 36,
    SB_TOP = 13, SB_H = 28, SB_BOT = 6, SB_INSET = 20,
    -- rows
    ROW = 36, ROW_CTL = 50, ROW_V = 9,
    -- controls
    CHECK = 18, CHECK_PAD = 2, CHECK_GAP = 10,
    TOGGLE_W = 40, TOGGLE_H = 20, KNOB_PAD = 2, TOGGLE_DUR = 0.075,
    TRACK_W = 160, TRACK_MIN = 80, TRACK_H = 4, THUMB = 14, VALUE_W = 40, VALUE_H = 26, TRACK_GAP = 12,
    SLIDER_W = 400, FIELD_W = 400, DD_W = 170, DD_H = 30, DD_ROW = 26, DD_ROWS = 18,
    BTN_H = 32, BTN_W = 180, EDIT_H = 28, SWATCH = 24, SWATCH_GAP = 8,
    FOOT_BTN_W = 180, FOOT_BTN_H = 36, FOOT_CLOSE_W = 160, FOOT_PAD = 24, FADE = 0.10,
    WHEEL = 60, LERP = 12,
    -- type (physical px at a pixel-perfect scale)
    F_TITLE = 36, F_DESC = 14, F_TAB = 16, F_NAV = 14, F_GROUP = 15, F_SECTION = 12,
    F_LABEL = 14, F_VALUE = 13, F_HINT = 12,
    -- colours and alphas
    BG = { r = 0.069, g = 0.058, b = 0.047 },
    BORDER_A = 0.05, DIM_A = 0.53, SECTION_A = 0.41, OFF_A = 0.3,
    ROW_ODD = 0.10, ROW_EVEN = 0.20, SIDEBAR_A = 0.20, HEAD_BAND_A = 0.10, HEAD_DIV_A = 0.06,
    SECTION_RULE_A = 0.02,
    NAV_EN = 0.60, NAV_HOVER = 0.86, NAV_OFF = 0.11, NAV_OFF_HOVER = 0.39, NAV_HL = 0.06,
    NAV_GLOW = 0.15, NAV_HOVER_GLOW = 0.03, NAV_HOVER_IND = 0.25, NAV_EDGE = 0.5,
    HOVER_TINT = { r = 0.85, g = 0.95, b = 0.90 }, EDGE_TINT = { r = 0.7, g = 0.7, b = 0.7 },
    INPUT = { r = 0.030, g = 0.023, b = 0.018 }, INPUT_A = 0.35, INPUT_BRD_A = 0.10,
    SL_TRACK_A = 0.22, SL_FILL_A = 0.75, SL_INPUT_A = 0.40, SL_INPUT_BRD_A = 0.12,
    TG_OFF = { r = 0.267, g = 0.267, b = 0.267 }, TG_OFF_A = 0.65, TG_ON_A = 0.75, KNOB_OFF_A = 0.5,
    CB_BOX = { r = 0.112, g = 0.105, b = 0.098 }, CB_BRD_A = 0.05, CB_ACT_BRD_A = 0.15, CB_REST = 0.8,
    BTN_BG = { r = 0.089, g = 0.080, b = 0.072 }, BTN_BG_A = 0.6, BTN_BG_HA = 0.65,
    BTN_BRD_A = 0.30, BTN_BRD_HA = 0.45, BTN_TXT_A = 0.55, BTN_TXT_HA = 0.70,
    FOOT_BG_A = 0.92, FOOT_BRD_A = 0.4, FOOT_BRD_HA = 0.6, FOOT_TXT_A = 0.5, FOOT_TXT_HA = 0.7, CLOSE_A = 0.7,
    DD_BG = { r = 0.103, g = 0.095, b = 0.088 }, DD_BG_A = 0.9, DD_BG_HA = 0.98,
    DD_BRD_A = 0.20, DD_BRD_HA = 0.30, DD_TXT_A = 0.50, DD_TXT_HA = 0.60, DD_HL_A = 0.08, DD_SEL_A = 0.04,
    SCROLL_TRACK_A = 0.02, SCROLL_THUMB_A = 0.27, NAV_TRACK_A = 0.03, NAV_THUMB_A = 0.25,
    -- the window follows ZacUI's one font option; true locks it to the HD face
    FONT_LOCK = false,
}
UI.S = S

-- Inside a settings build? (a count, so a build inside a build is fine)
UI._zSettingsDepth = 0
function UI.InSettings() return UI._zSettings == true end
-- Runs fn(...) with the settings look on, then puts back what was there.
function UI.SettingsBuild(fn, ...)
    local was = UI._zSettings
    UI._zSettings = true
    local ok, a, b, c = pcall(fn, ...)
    UI._zSettings = was
    if not ok then error(a, 0) end
    return a, b, c
end

-- Type in the settings window: ZacUI's 9-13 px sizes are three larger
-- (labels 11 -> 14, descriptions 10 -> 13, as EllesmereUI's 14 / 13).
local function SZ(size)
    if UI._zSettings and type(size) == "number" and size >= 9 and size <= 13 then return size + 3 end
    return size
end
UI.SettingsSize = SZ

local WHITE = { r = 1, g = 1, b = 1, a = 1 }
local SET_TEXT = {
    text = { normal = 1, gray = S.DIM_A, disabled = S.OFF_A },
    ui = { text = 1 },
}
-- A colour in the settings window: the palette editor's pick if there is
-- one, else the window's own (white at its alpha for text), else the
-- palette's shipped value.
function UI.SCol(cat, key)
    local p = ZacUIDB and ZacUIDB.palette and ZacUIDB.palette[cat]
    if p and p[key] then return p[key] end
    local a = SET_TEXT[cat] and SET_TEXT[cat][key]
    if a then return { r = 1, g = 1, b = 1, a = a } end
    return GetColor(cat, key)
end
local SCol = UI.SCol
local function Accent() return GetColor("ui", "accent") end

-- ROUND ART (2026-11-08): EllesmereUI draws its toggles and slider tracks
-- as pills and its knobs and thumbs as circles. Ours: plain white
-- anti-aliased discs (Media/Icons/disc<n>, zui_tests/icons/make_icons.py
-- "discs"), each in a power-of-two canvas; a pill is a disc's two halves
-- for its ends with a flat middle between them. Tinted by vertex colour.
local DISC_SIZES = { 4, 6, 8, 10, 12, 14, 16, 20, 24, 32 }
local DISC_PATH = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\disc"
local function DiscOf(n)
    n = math.floor((n or 16) + 0.5)
    for _, s in ipairs(DISC_SIZES) do if s >= n then return s end end
    return 32
end
local function Canvas(s) local c = 1 while c < s do c = c * 2 end return c end
-- part: nil (the whole disc), "left" or "right" (its half)
function UI.DiscArt(tex, n, part)
    local s = DiscOf(n)
    local c = Canvas(s)
    local o = (c - s) / 2
    local l, r, t, b = o / c, (o + s) / c, o / c, (o + s) / c
    if part == "left" then r = (o + s / 2) / c elseif part == "right" then l = (o + s / 2) / c end
    tex:SetTexture(DISC_PATH .. s)
    tex:SetTexCoord(l, r, t, b)
end
-- A pill on `host` (filling it: h = the host's height): three textures,
-- the ends half a height wide. pill:Color(r, g, b, a); pill:Show(on).
function UI.Pill(host, layer, sub, h)
    local p = {}
    local function T(part)
        local t = host:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
        t._zui_own = true
        return t
    end
    p.l, p.m, p.r = T(), T(), T()
    p.m:SetTexture(FLAT)
    function p:Size(hh)
        hh = math.max(2, hh or host:GetHeight() or 4)
        local half = hh / 2
        UI.DiscArt(self.l, hh, "left")
        UI.DiscArt(self.r, hh, "right")
        self.l:ClearAllPoints()
        self.l:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        self.l:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
        self.l:SetWidth(half)
        self.r:ClearAllPoints()
        self.r:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
        self.r:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
        self.r:SetWidth(half)
        self.m:ClearAllPoints()
        self.m:SetPoint("TOPLEFT", self.l, "TOPRIGHT", 0, 0)
        self.m:SetPoint("BOTTOMRIGHT", self.r, "BOTTOMLEFT", 0, 0)
    end
    function p:Color(r, g, b, a)
        self.l:SetVertexColor(r, g, b, a) self.m:SetVertexColor(r, g, b, a) self.r:SetVertexColor(r, g, b, a)
    end
    function p:Show(on)
        self.l:SetShown(on) self.m:SetShown(on) self.r:SetShown(on)
    end
    p:Size(h)
    return p
end
UI.SWhite = WHITE

-- ============================================================
-- PAINT
-- ============================================================
-- Widgets register a repaint closure on themselves. Repaint walks a whole
-- tree and fires every one it finds. Bounded by construction: the walk
-- only sees frames that are still parented, so a rebuilt page's old
-- widgets fall out of scope instead of leaking into a global list.
local function Repaint(root, depth)
    if not root or (depth or 0) > 8 then return end
    if root._zPaint then pcall(root._zPaint, root) end
    if root.GetChildren then
        for _, child in ipairs({ root:GetChildren() }) do
            Repaint(child, (depth or 0) + 1)
        end
    end
end

-- ============================================================
-- PRIMITIVES
-- ============================================================

-- Text. Everything typographic in a ZacUI window comes through here, so
-- the font system reaches our own UI and not just Blizzard's.
-- (FontApply sets everything a string's look depends on; a pooled string
-- is handed back through it too)
-- (the face, size and outline alone: what a change of ZacUI's font redoes)
local function FontDress(fs, size, outline, fixedSize)
    local cfg = ZacUIDB and ZacUIDB.font or {}
    local delta = fixedSize and 0 or (cfg.delta or 0)
    local path = ResolveFontPath(cfg.name)
    if rawget(fs, "_zSet") and S.FONT_LOCK and ns.MEDIA_FONT_HD then path = ns.MEDIA_FONT_HD end
    local flags = outline
    if flags == nil then
        flags = (cfg.outline == "NONE") and "" or "OUTLINE"
    end
    -- the face the string was handed out with: "Blizzard default" puts it back
    local curPath = ns.HouseOrig and ns.HouseOrig(fs) or select(1, fs:GetFont())
    -- pcall: a registered font whose file is missing throws (see HUD.ApplyFont)
    -- and one that will not load returns false, leaving the string with no font
    local ok, set = pcall(fs.SetFont, fs, path or curPath or "Fonts\\FRIZQT__.TTF", (size or F.LABEL) + delta, flags)
    if not (ok and set) then
        pcall(fs.SetFont, fs, curPath or "Fonts\\FRIZQT__.TTF", (size or F.LABEL) + delta, flags)
    end
    if ns.TrackHouseFont then
        ns.TrackHouseFont(fs, function(s) FontDress(s, size, outline, fixedSize) end)
    end
end
UI._zFontDress = FontDress

local function FontApply(fs, size, opts)
    opts = opts or {}
    -- in the settings window: three larger, white at its alpha (UI.SCol);
    -- outlined as ZacUI's font option says (Zac likes the black edge on
    -- text, 2026-11-08); fixed for the string's life, so a font change
    -- redressing it later keeps them
    local outline = opts.outline
    if UI._zSettings then
        size = SZ(size or F.LABEL)
        fs._zSet = true
    else
        fs._zSet = nil
    end
    FontDress(fs, size, outline)
    if opts.justify then fs:SetJustifyH(opts.justify) end
    if opts.width then
        fs:SetWidth(opts.width)
        fs:SetJustifyH(opts.justify or "LEFT")
        if opts.wrap ~= false then fs:SetWordWrap(true) end
    end
    if opts.text then fs:SetText(opts.text) end

    fs._zPaintCat, fs._zPaintKey = opts.cat or "text", opts.key or "normal"
    fs._zPaint = function(self)
        local c = (rawget(self, "_zSet") and SCol or GetColor)(self._zPaintCat, self._zPaintKey)
        self:SetTextColor(c.r, c.g, c.b, c.a or 1)
    end
    fs:_zPaint()
    return fs
end
UI._zFontApply = FontApply

-- A string made in the settings window at an exact size (the window's
-- own type scale: 36 titles, 16 tabs...), no mapping.
function UI.SFont(parent, size, opts)
    local was = UI._zSettings
    UI._zSettings = false
    opts = opts or {}
    local fs = UI.Font(parent, size, opts)
    UI._zSettings = was
    fs._zSet = true
    if S.FONT_LOCK then FontDress(fs, size, opts.outline) end
    fs:_zPaint()
    return fs
end

function UI.Font(parent, size, opts)
    opts = opts or {}
    local layer = opts.layer or "OVERLAY"
    local fs = parent:CreateFontString(nil, layer, opts.template or "GameFontNormal")
    return FontApply(fs, size, opts)
end
UI.RepaintTree = function(root) Repaint(root) end

-- ROOM. The width a widget has inside `parent`, from x (default the
-- card's control inset) to the parent's right edge less the same inset;
-- nil while the parent has no width yet. A card is stretched across the
-- page, so before its rect resolves it is read as the page's width less
-- the margins. Widgets built in a card cap themselves to this, so nothing
-- they draw can run past the card's edge.
function UI.Room(parent, x)
    if not (parent and parent.GetWidth) then return nil end
    local w = parent:GetWidth()
    if (type(w) ~= "number" or w < 60) and parent._zAccent and parent.GetParent then
        local page = parent:GetParent()
        local pw = page and page.GetWidth and page:GetWidth()
        if type(pw) == "number" and pw > 60 then w = pw - 2 * M.MARGIN end
    end
    if type(w) ~= "number" or w < 60 then return nil end
    return math.floor(w - (x or M.CONTROL_X) - M.CONTROL_X)
end

-- FLOW. Widgets left to right from (x, y) in parent, a new line whenever
-- the next one would pass `room` (the width from x). A widget wider than a
-- whole line is fitted to it first (_zFit). Returns the height used.
function UI.Flow(parent, widgets, x, y, room, gap, rowGap)
    gap, rowGap = gap or 8, rowGap or 6
    local cx, cy, lineH = 0, y, 0
    for _, w in ipairs(widgets) do
        local ww = w:GetWidth() or 0
        if w._zFit and ww > room + 0.5 then w:_zFit(room) ww = w:GetWidth() or 0 end
        if cx > 0 and cx + ww > room + 0.5 then
            cy, cx, lineH = cy - lineH - rowGap, 0, 0
        end
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", x + cx, cy)
        cx = cx + ww + gap
        lineH = math.max(lineH, w:GetHeight() or 0)
    end
    return (y - cy) + lineH
end

-- A string cut short on purpose (a dropdown's choice, a fixed cell) shows
-- its whole text in a tooltip while it does not fit. `owner` is the frame
-- that takes the hover (default: the string's parent).
function UI.TruncTip(fs, owner)
    fs._zTruncTip = true
    owner = owner or fs:GetParent()
    if not (owner and owner.HookScript) then return fs end
    local list = owner._zTruncTips
    if list then
        for _, t in ipairs(list) do if t == fs then return fs end end
        list[#list + 1] = fs
        return fs
    end
    owner._zTruncTips = { fs }
    owner:HookScript("OnEnter", function(self)
        local any = false
        for _, t in ipairs(self._zTruncTips) do
            local w = t:GetWidth() or 0
            local cut
            if t.IsTruncated then cut = t:IsTruncated() else cut = (t:GetStringWidth() or 0) > w + 0.5 end
            if t:IsVisible() and w > 0 and cut then
                if not any and not (GameTooltip:IsShown() and GameTooltip:GetOwner() == self) then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                end
                any = true
                local c = GetColor("tooltip", "body")
                GameTooltip:AddLine(t:GetText() or "", c.r, c.g, c.b, true)
            end
        end
        if any then GameTooltip:Show() end
    end)
    owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return fs
end

-- Flat fill. Owned by us, so it is always the same texture at the same
-- sublevel - no guessing which of Blizzard's layers won.
function UI.Fill(frame, cat, key, alpha)
    local tex = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    tex._zui_own = true
    tex:SetAllPoints()
    tex:SetTexture(alpha == "bar" and TEX_NORM or FLAT)
    tex._zCat, tex._zKey, tex._zAlpha = cat, key, (alpha ~= "bar") and alpha or nil
    frame._zFill = tex
    return tex
end

-- 1px border as four strips, handles kept so it can be retinted. The
-- strips live at OVERLAY sublevel 7 - above our fills, above almost
-- everything Blizzard draws, below tooltips.
function UI.Border(frame, cat, key, alpha)
    if frame._zBorder then return frame._zBorder end
    local strips = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        t._zui_own = true
        t:SetTexture(FLAT)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT")
            t:SetPoint(side .. "RIGHT")
        else
            t:SetPoint("TOP" .. side)
            t:SetPoint("BOTTOM" .. side)
        end
        -- M.BORDER physical pixels under the ZacUI look (Core_Pixel),
        -- M.BORDER units otherwise, as before
        if ns.Pixel then
            ns.Pixel.Edge(t, side, frame, M.BORDER)
        elseif side == "TOP" or side == "BOTTOM" then
            t:SetHeight(M.BORDER)
        else
            t:SetWidth(M.BORDER)
        end
        strips[#strips + 1] = t
    end
    frame._zBorder = strips
    frame._zBorderCat, frame._zBorderKey = cat or "ui", key or "border"
    frame._zBorderAlpha = alpha
    return strips
end

local function PaintBox(self)
    if self._zFill then
        local c = GetColor(self._zFill._zCat, self._zFill._zKey)
        self._zFill:SetVertexColor(c.r, c.g, c.b, self._zFill._zAlpha or c.a or 1)
    end
    if self._zBorder then
        local b = GetColor(self._zBorderCat, self._zBorderKey)
        for _, t in ipairs(self._zBorder) do
            t:SetVertexColor(b.r, b.g, b.b, self._zBorderAlpha or b.a or 1)
        end
    end
end

-- A filled, bordered box - the shape everything else is built from.
function UI.Box(parent, cat, key, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    UI.Fill(f, cat or "ui", key or "elementBg", opts.alpha)
    if opts.border ~= false then
        UI.Border(f, opts.borderCat or "ui", opts.borderKey or "border", opts.borderAlpha)
    end
    f._zPaint = PaintBox
    f:_zPaint()
    return f
end

-- Hover wiring. Takes the two colour keys rather than two closures: every
-- hover in this file is "swap the fill, maybe swap the text", and passing
-- keys keeps the swap inside the paint system where the colour editor
-- can still reach it.
function UI.Hover(frame, normalKey, hoverKey, cat)
    cat = cat or "button"
    frame._zNormalKey, frame._zHoverKey, frame._zHoverCat = normalKey, hoverKey, cat
    frame:HookScript("OnEnter", function(self)
        -- the settings window's widgets paint their own hover (_zSet)
        if rawget(self, "_zSet") then return end
        if self._zDisabled or self._zActive then return end
        local c = GetColor(self._zHoverCat, self._zHoverKey)
        if self._zFill then self._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
        if self._zText then
            local a = GetColor("ui", "accent")
            self._zText:SetTextColor(a.r, a.g, a.b, 1)
        end
    end)
    frame:HookScript("OnLeave", function(self)
        if rawget(self, "_zSet") then return end
        if self._zDisabled or self._zActive then return end
        -- a tab's resting label is grey, not the text default
        if self._zTab then return self:_zPaint() end
        local c = GetColor(self._zHoverCat, self._zNormalKey)
        if self._zFill then self._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
        if self._zText then self._zText:_zPaint() end
    end)
end

-- ============================================================
-- BUTTON
-- ============================================================
-- A PAGE TAB (opts.tab) has its own look, with no green in it: the
-- tabs sit right under gold titles, and a green ring plus a gold line on
-- one button read as two themes fighting (Zac 2026-11-02). Closed tabs
-- are quiet (grey label); the open one lifts a shade, its label goes
-- white and a gold line runs along its foot. Hover is the usual gold
-- label, so hover and open never look alike.
local function PaintTab(self)
    local c = GetColor("button", self._zActive and "hover" or "bg")
    if self._zFill then self._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
    local b = GetColor("ui", "border")
    if self._zBorder then
        for _, t in ipairs(self._zBorder) do
            t:SetVertexColor(b.r, b.g, b.b, b.a or 1)
        end
    end
    if self._zUnderline then
        local a = GetColor("ui", "accent")
        self._zUnderline:SetVertexColor(a.r, a.g, a.b, 1)
        self._zUnderline:SetShown(self._zActive and true or false)
    end
    if self._zText then
        local t = self._zDisabled and GetColor("text", "disabled")
            or self._zActive and GetColor("text", "normal")
            or GetColor("text", "gray")
        self._zText:SetTextColor(t.r, t.g, t.b, 1)
    end
end

-- THE SETTINGS WINDOW'S BUTTONS (UI.S): rest and hover a 0.1 s fade
-- apart (self._zP, 0..1), as EllesmereUI's. Plain: the button colours;
-- "footer": the dark footer button; "close": the accent one. A tab: no
-- box, a 16 px label at three alphas and a 2 px accent line text + 14
-- wide under the open one.
local function Lerp(a, b, t) return a + (b - a) * t end
local function Strips(self, r, g, b, a)
    if self._zBorder then for _, t in ipairs(self._zBorder) do t:SetVertexColor(r, g, b, a) end end
end
local function PaintSetButton(self)
    local t = self._zDisabled and 0 or (self._zP or 0)
    local fs = self._zText
    if self._zTab then
        if self._zFill then self._zFill:SetVertexColor(0, 0, 0, 0) end
        Strips(self, 0, 0, 0, 0)
        local u = self._zUnderline
        if u then
            local a = Accent()
            u:SetVertexColor(a.r, a.g, a.b, 1)
            u:SetShown(self._zActive and true or false)
            local tw = fs and math.ceil(fs:GetStringWidth() or 0) or 0
            u:ClearAllPoints()
            u:SetPoint("BOTTOM", self, "BOTTOM", 0, 0)
            u:SetWidth(tw + 14)
        end
        if fs then
            local ta = self._zDisabled and S.OFF_A or self._zActive and 1 or Lerp(S.DIM_A, S.NAV_HOVER, t)
            fs:SetTextColor(1, 1, 1, ta)
        end
        return
    end
    local st, a = self._zStyle, Accent()
    local k = self._zDisabled and 0.5 or 1
    local bg, ba, br, bgc, bb, tr, tc
    if st == "footer" or st == "close" then
        bgc, ba = S.BG, S.FOOT_BG_A
    else
        bgc, ba = S.BTN_BG, Lerp(S.BTN_BG_A, S.BTN_BG_HA, t)
    end
    if st == "close" or (self._zActive and st ~= "footer") then
        br, tr = a, a
        bb, tc = Lerp(S.CLOSE_A, 1, t), Lerp(S.CLOSE_A, 1, t)
    elseif st == "footer" then
        br, tr = WHITE, WHITE
        bb, tc = Lerp(S.FOOT_BRD_A, S.FOOT_BRD_HA, t), Lerp(S.FOOT_TXT_A, S.FOOT_TXT_HA, t)
    else
        br, tr = WHITE, WHITE
        bb, tc = Lerp(S.BTN_BRD_A, S.BTN_BRD_HA, t), Lerp(S.BTN_TXT_A, S.BTN_TXT_HA, t)
    end
    if self._zFill then self._zFill:SetVertexColor(bgc.r, bgc.g, bgc.b, ba) end
    Strips(self, br.r, br.g, br.b, bb * k)
    if fs then fs:SetTextColor(tr.r, tr.g, tr.b, tc * k) end
end
UI.PaintSetButton = PaintSetButton

-- The 0.1 s hover fade: an OnUpdate only while it moves.
local function FadeStep(self, dt)
    local want = self._zHot and 1 or 0
    local p = self._zP or 0
    local step = (dt or 0.016) / S.FADE
    if p < want then p = math.min(want, p + step) else p = math.max(want, p - step) end
    self._zP = p
    self:_zPaint()
    if p == want then self:SetScript("OnUpdate", nil) end
end
function UI.FadeHover(f)
    f:HookScript("OnEnter", function(self)
        self._zHot = true
        if not self._zDisabled then self:SetScript("OnUpdate", FadeStep) end
    end)
    f:HookScript("OnLeave", function(self)
        self._zHot = nil
        self:SetScript("OnUpdate", FadeStep)
    end)
    f:HookScript("OnHide", function(self)
        self._zHot, self._zP = nil, 0
        self:SetScript("OnUpdate", nil)
    end)
end

local function PaintButton(self)
    if rawget(self, "_zSet") then return PaintSetButton(self) end
    if self._zTab then return PaintTab(self) end
    local key = self._zNormalKey
    if self._zDisabled then
        key = "disabled"
    elseif self._zActive then
        key = "active"
    end
    local c = GetColor("button", key)
    if self._zFill then self._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
    -- Selected = green fill + green ring. Gold stays for hover/focus.
    local b = GetColor("ui", self._zActive and "borderSelected" or "border")
    if self._zBorder then
        for _, t in ipairs(self._zBorder) do
            t:SetVertexColor(b.r, b.g, b.b, b.a or 1)
        end
    end
    if self._zText then
        local t = self._zDisabled and GetColor("text", "disabled")
            or self._zActive and GetColor("text", "green")
            or GetColor("text", "normal")
        self._zText:SetTextColor(t.r, t.g, t.b, 1)
    end
end

function UI.Button(parent, text, opts)
    opts = opts or {}
    local set = UI._zSettings
    local b = CreateFrame("Button", nil, parent)
    local defH = set and (opts.tab and S.TABS or S.BTN_H) or M.BUTTON_H
    b:SetSize(opts.width or M.BUTTON_W, opts.height or defH)
    UI.Fill(b, "button", "bg")
    UI.Border(b, "ui", "border")
    if set then
        b._zSet = true
        b._zStyle = opts.style
        b._zText = UI.SFont(b, opts.tab and S.F_TAB or (opts.size and SZ(opts.size)) or S.F_VALUE, { text = text })
    else
        b._zText = UI.Font(b, opts.size or F.LABEL, { text = text })
    end
    b._zText:SetPoint("CENTER", 0, 0)
    b._zNormalKey = "bg"
    b._zPaint = PaintButton
    -- NEVER NARROWER THAN ITS LABEL. A bigger font or a longer word widens
    -- the button instead of running its text past both edges. (A caller
    -- that re-anchors the label across the button owns its width.)
    local function FitLabel(self)
        local fs = self._zText
        if fs:GetNumPoints() ~= 1 or self._zWrapped then return end
        local need = math.ceil(fs:GetStringWidth() or 0) + (set and 24 or 16)
        if need > (self:GetWidth() or 0) then self:SetWidth(need) end
    end
    FitLabel(b)
    -- Narrower than its label (a line with no room for it): the label
    -- wraps onto two lines and the button grows taller.
    function b:_zFit(w)
        local fs = self._zText
        if fs:GetNumPoints() ~= 1 then return end
        w = math.max(40, math.floor(w))
        fs:SetWidth(w - 12)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(true)
        self._zWrapped = true
        self:SetWidth(w)
        local h = math.max(opts.height or defH, math.ceil(fs:GetStringHeight() or 0) + 8)
        self:SetHeight(h)
        self._zExtraH = h - (opts.height or defH)
    end
    -- back to one line (a pooled button handed to a page with more room)
    local bj0 = b._zText:GetJustifyH()
    local bw0 = b._zText.CanWordWrap and b._zText:CanWordWrap()
    function b:_zUnfit()
        local fs = self._zText
        fs:SetWidth(0)
        if bw0 ~= nil then fs:SetWordWrap(bw0) end
        if bj0 then fs:SetJustifyH(bj0) end
    end
    UI.Hover(b, "bg", "hover")

    -- Additive white lift on hover, and a real pushed texture underneath
    -- it. A flat fill gives no depth cue, so without the pushed state a
    -- click on a dark button reads as a missed click. (The settings
    -- window's buttons fade between two looks instead, as EllesmereUI's
    -- do, and have no pushed state.)
    if set then
        UI.FadeHover(b)
    else
        local hover = b:CreateTexture(nil, "HIGHLIGHT")
        hover._zui_own = true
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.05)
        hover:SetBlendMode("ADD")

        local pushed = b:CreateTexture(nil, "ARTWORK")
        pushed._zui_own = true
        pushed:SetAllPoints()
        pushed:SetColorTexture(0, 0, 0, 0.35)
        b:SetPushedTexture(pushed)
    end

    if opts.tab then
        b._zTab = true
        local u = b:CreateTexture(nil, "OVERLAY", nil, 7)
        u._zui_own = true
        u:SetTexture(FLAT)
        if ns.Pixel then ns.Pixel.Edge(u, "BOTTOM", b, 2) else u:SetHeight(2) end
        u:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
        u:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        u:Hide()
        b._zUnderline = u
    end

    function b:SetActive(on)
        self._zActive = on and true or nil
        self:_zPaint()
    end
    -- why: what the player has to do first ("Needs X turned on", UIF_Pickers'
    -- UI.WHY_*), shown on hover while it is greyed
    function b:SetDisabled(on, why)
        self._zDisabled = on and true or nil
        self._zWhy = on and why or nil
        if on then self:Disable() else self:Enable() end
        if self._zWhy and not self._zTipHooked then UI.Tooltip(self, self._zText:GetText(), nil) end
        self:_zPaint()
    end
    function b:SetLabel(t) self._zText:SetText(t) FitLabel(self) end

    if opts.onClick then b:SetScript("OnClick", opts.onClick) end
    if opts.tooltip then UI.Tooltip(b, opts.tooltipTitle or text, opts.tooltip) end
    b:_zPaint()
    return b
end

-- Chromeless X: ZacUI's own close icon (Media/Icons/close, drawn for
-- ZacUI, 2026-11-07 - it replaced two rotated bars), tinted by the
-- palette. The one piece of ZacUI furniture that deliberately has no box
-- around it. The icon's glyph spans 12/32 of it, so at 0.95 of the button
-- it is as wide as the bars were.
ns.ICON_CLOSE = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\close"
function UI.CloseX(parent, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    size = size or 22
    b:SetSize(size, size)
    local function Bar()
        local t = b:CreateTexture(nil, "ARTWORK")
        -- MARKED AS OURS, and this is not bookkeeping for its own sake.
        -- Two things read this flag: the skin sweep, which blanks every
        -- texture it does not recognise - an unmarked X eventually
        -- disappears, which has already happened once on the map - and
        -- the map dump, which counts unmarked textures as leftover
        -- Blizzard art. The dump duly reported "Blizzard textures still
        -- visible: 2" pointing at ZacUI's own close button, sending the
        -- next round of investigation after art that was never there.
        -- A diagnostic that miscounts is worse than no diagnostic.
        t._zui_own = true
        local s = math.floor(size * 0.95 + 0.5)
        t:SetSize(s, s)
        t:SetPoint("CENTER")
        t:SetTexture(ns.ICON_CLOSE)
        return t
    end
    -- (one icon; _zB is the same texture so callers that paint both work)
    b._zA = Bar()
    b._zB = b._zA
    b._zSet = UI._zSettings or nil
    b._zPaint = function(self)
        if rawget(self, "_zSet") then
            -- the settings window: white, 0.53 at rest, full under the mouse
            local a = self._zHot and 1 or S.DIM_A
            self._zA:SetVertexColor(1, 1, 1, a)
            return
        end
        local c = GetColor("button", self._zHot and "xHover" or "xNormal")
        self._zA:SetVertexColor(c.r, c.g, c.b, 1)
        self._zB:SetVertexColor(c.r, c.g, c.b, 1)
    end
    b:HookScript("OnEnter", function(self) self._zHot = true; self:_zPaint() end)
    b:HookScript("OnLeave", function(self) self._zHot = nil; self:_zPaint() end)
    if onClick then b:SetScript("OnClick", onClick) end
    b:_zPaint()
    return b
end

-- ============================================================
-- CHECKBOX
-- ============================================================
-- Two looks, both from the palette: resting (the box's own fill, a crisp
-- 1px border, the tick on top when ticked) and under the mouse (the hover
-- fill and border). Ticked or not, the BOX stays neutral - only the tick
-- wears the tick colour. Zac 2026-11-02: a box washed and ringed in the
-- tick colour read as a solid green block next to the gold UI.
-- A dimmed checkbox (UI.SetEnabled) keeps its look at a third strength.
-- A tick colour somebody picked: stored, and not the shipped gold or the
-- green shipped before 2026-11-02 (a profile copy of it). Unpicked, the
-- tick is the gold Checkmark art as drawn; picked, the white tick in
-- exactly that colour.
local function PickedCheck()
    local p = ZacUIDB and ZacUIDB.palette and ZacUIDB.palette.checkbox
    local c = p and p.check
    if type(c) ~= "table" then return nil end
    local function Same(r, g, b)
        return math.abs((c.r or 0) - r) < 0.005 and math.abs((c.g or 0) - g) < 0.005
            and math.abs((c.b or 0) - b) < 0.005
    end
    local d = ns.PALETTE and ns.PALETTE.checkbox and ns.PALETTE.checkbox.check
    if (d and Same(d.r, d.g, d.b)) or Same(0.45, 0.75, 0.45) then return nil end
    return c
end
UI.PickedCheck = PickedCheck

-- Any tick texture in ZacUI (our checkboxes, skinned Blizzard ones, list
-- rows): the gold art as drawn, or the white tick in a picked colour.
-- Returns the colour the tick reads as (for a partial-state square etc).
function UI.PaintTick(t)
    local ck = PickedCheck()
    local tex = ck and (ns.TEX_CHECK_WHITE or TEX_CHECK) or TEX_CHECK
    if t then
        if t._zCheckTex ~= tex then
            t:SetTexture(tex)
            t._zCheckTex = tex
        end
        if ck then t:SetVertexColor(ck.r or 1, ck.g or 1, ck.b or 1, 1)
        else t:SetVertexColor(1, 1, 1, 1) end
    end
    return ck or GetColor("checkbox", "check")
end

-- the settings window's checkbox (UI.S): an 18 px box, the tick an accent
-- square 2 px in; unticked and not hovered the box is at 0.8
local function PaintSetCheck(self)
    local on, hot = self._zChecked, self._zHot and not self._zOff
    local k = (on or hot) and 1 or S.CB_REST
    local c = S.CB_BOX
    self._zFill:SetVertexColor(c.r, c.g, c.b, k)
    local a = Accent()
    if on then
        for _, t in ipairs(self._zBorder) do t:SetVertexColor(a.r, a.g, a.b, S.CB_ACT_BRD_A) end
    else
        for _, t in ipairs(self._zBorder) do t:SetVertexColor(1, 1, 1, S.CB_BRD_A * k) end
    end
    local ck = PickedCheck() or a
    self._zCheck:SetVertexColor(ck.r, ck.g, ck.b, 1)
    if self._zText then self._zText:SetTextColor(1, 1, 1, k) end
end

local function PaintCheck(self)
    if rawget(self, "_zSet") then return PaintSetCheck(self) end
    local bg, bk
    if self._zHot and not self._zOff then
        bg, bk = GetColor("button", "hover"), GetColor("checkbox", "hoverBorder")
    else
        bg, bk = GetColor("checkbox", "bg"), GetColor("checkbox", "border")
    end
    self._zFill:SetVertexColor(bg.r, bg.g, bg.b, bg.a or 1)
    for _, t in ipairs(self._zBorder) do
        t:SetVertexColor(bk.r, bk.g, bk.b, 1)
    end
    UI.PaintTick(self._zCheck)
    if self._zText then self._zText:_zPaint() end
end

function UI.Checkbox(parent, label, checked, onToggle, opts)
    opts = opts or {}
    local set = UI._zSettings
    local CK, GAP = set and S.CHECK or M.CHECK, set and S.CHECK_GAP or 7
    local host = CreateFrame("Button", nil, parent)
    host:SetHeight(CK)

    local box = CreateFrame("Frame", nil, host)
    box:SetSize(CK, CK)
    box:SetPoint("LEFT")
    UI.Fill(box, "checkbox", "bg")
    UI.Border(box, "checkbox", "border")

    local check = box:CreateTexture(nil, "ARTWORK")
    check._zui_own = true
    if set then
        -- EllesmereUI's tick: a solid square, CHECK_PAD in from the edge
        check:SetTexture(FLAT)
        check:SetPoint("TOPLEFT", box, "TOPLEFT", S.CHECK_PAD, -S.CHECK_PAD)
        check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -S.CHECK_PAD, S.CHECK_PAD)
    else
        check:SetSize(M.CHECK - 4, M.CHECK - 4)
        check:SetPoint("CENTER")
        check:SetTexture(TEX_CHECK)
    end
    check:SetShown(checked and true or false)

    host._zFill, host._zBorder = box._zFill, box._zBorder
    host._zCheck = check
    host._zSet = set or nil
    -- (a whole box-and-label: two of them can share a settings row)
    host._zHalf = set or nil
    host._zText = UI.Font(host, opts.size or F.LABEL, { text = label })
    host._zText:SetPoint("LEFT", box, "RIGHT", GAP, 0)
    host._zPaint = PaintCheck
    host:SetWidth(CK + GAP + math.max(10, host._zText:GetStringWidth()))
    -- A label too long for its room wraps under itself, the box at its
    -- first line, instead of running past the card. _zExtraH is the height
    -- the wrap added (the Layout adds it to the row).
    function host:_zFit(maxW)
        local fs = self._zText
        local room = math.floor(maxW - CK - GAP)
        if room < 30 or (fs:GetStringWidth() or 0) <= room + 0.5 then return end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", box, "TOPRIGHT", GAP, 1)
        fs:SetWidth(room)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT")
        local h = math.max(CK, math.ceil(fs:GetStringHeight() or CK) - 1)
        self:SetHeight(h)
        self:SetWidth(CK + GAP + room)
        self._zExtraH = h - CK
    end
    local justify0 = host._zText:GetJustifyH()
    local wrap0 = host._zText.CanWordWrap and host._zText:CanWordWrap()
    function host:_zUnfit()
        local fs = self._zText
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", box, "RIGHT", GAP, 0)
        fs:SetWidth(0)
        if justify0 then fs:SetJustifyH(justify0) end
        if wrap0 ~= nil then fs:SetWordWrap(wrap0) end
        box:ClearAllPoints()
        box:SetPoint("LEFT")
        self:SetHeight(CK)
        self:SetWidth(CK + GAP + math.max(10, fs:GetStringWidth()))
    end
    local room = opts.width or UI.Room(parent)
    if room then host:_zFit(room) end
    host._zPoolRefit = function(self)
        local r = opts.width or UI.Room(self:GetParent())
        if r then self:_zFit(r) end
    end

    host:HookScript("OnEnter", function(self) self._zHot = true; self:_zPaint() end)
    host:HookScript("OnLeave", function(self) self._zHot = nil; self:_zPaint() end)
    host:SetScript("OnClick", function(self)
        local now = not self._zChecked
        self:SetChecked(now)
        if onToggle then onToggle(now) end
        Changed("checkbox")
    end)

    function host:SetChecked(v)
        self._zChecked = v and true or false
        self._zCheck:SetShown(self._zChecked)
        if self._zFill then self:_zPaint() end
    end
    function host:GetChecked() return self._zChecked end
    host:SetChecked(checked)
    host:_zPaint()
    if opts.tooltip then UI.Tooltip(host, label, opts.tooltip) end
    return host
end

-- ============================================================
-- TOGGLE (match pass 2026-11-07, UI.S)
-- ============================================================
-- EllesmereUI's switch, on a row: the label on the left, a 40 x 20 track
-- on the right (off #444 at 0.65, on the accent at 0.75) with a 16 px knob
-- two in from its end (white 0.5 off, 1.0 on), sliding over 0.075 s.
--   UI.Toggle(parent, label, on, onToggle, { width, tooltip })
-- Same calls as a checkbox (SetChecked / GetChecked / Click).
function UI.Toggle(parent, label, on, onToggle, opts)
    opts = opts or {}
    local width = math.max(opts.width or 0, S.FIELD_W)
    local room = UI.Room(parent)
    if room and width > room then width = room end
    local host = CreateFrame("Button", nil, parent)
    host:SetSize(width, S.TOGGLE_H + 4)
    host._zSet, host._zHalf = true, true
    local track = CreateFrame("Frame", nil, host)
    track:SetSize(S.TOGGLE_W, S.TOGGLE_H)
    track:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    -- EllesmereUI's pill track and round knob (our disc art, UI.Pill)
    local pill = UI.Pill(track, "ARTWORK", 0, S.TOGGLE_H)
    local knob = track:CreateTexture(nil, "ARTWORK", nil, 2)
    knob._zui_own = true
    local d = S.TOGGLE_H - 2 * S.KNOB_PAD
    UI.DiscArt(knob, d)
    knob:SetSize(d, d)
    host._zText = UI.Font(host, F.LABEL, { text = label })
    host._zText:SetPoint("LEFT", host, "LEFT", 0, 0)
    host._zText:SetPoint("RIGHT", track, "LEFT", -12, 0)
    host._zText:SetJustifyH("LEFT")
    host._zText:SetWordWrap(false)
    UI.TruncTip(host._zText, host)
    local p = on and 1 or 0
    local function Apply()
        local a = Accent()
        local off = S.TG_OFF
        pill:Color(Lerp(off.r, a.r, p), Lerp(off.g, a.g, p), Lerp(off.b, a.b, p), Lerp(S.TG_OFF_A, S.TG_ON_A, p))
        knob:ClearAllPoints()
        knob:SetPoint("TOPLEFT", track, "TOPLEFT",
            math.floor(Lerp(S.KNOB_PAD, S.TOGGLE_W - S.KNOB_PAD - d, p) + 0.5), -S.KNOB_PAD)
        knob:SetVertexColor(1, 1, 1, Lerp(S.KNOB_OFF_A, 1, p))
        host._zText:SetTextColor(1, 1, 1, 1)
    end
    local function Slide(self, dt)
        local want = self._zChecked and 1 or 0
        local step = (dt or 0.016) / S.TOGGLE_DUR
        if p < want then p = math.min(want, p + step) else p = math.max(want, p - step) end
        Apply()
        if p == want then self:SetScript("OnUpdate", nil) end
    end
    host._zPaint = function() Apply() end
    function host:SetChecked(v)
        self._zChecked = v and true or false
        p = self._zChecked and 1 or 0
        self:SetScript("OnUpdate", nil)
        Apply()
    end
    function host:GetChecked() return self._zChecked end
    function host:_zFit(w) self:SetWidth(math.max(120, w)) end
    host:SetScript("OnClick", function(self)
        self._zChecked = not self._zChecked
        if onToggle then onToggle(self._zChecked) end
        Changed("toggle")
        local M2 = ns.Motion
        if M2 and M2.Enabled and not M2.Enabled() then
            p = self._zChecked and 1 or 0
            Apply()
        else
            self:SetScript("OnUpdate", Slide)
        end
    end)
    host:SetChecked(on)
    if opts.tooltip then UI.Tooltip(host, label, opts.tooltip) end
    return host
end

-- ============================================================
-- SLIDER
-- ============================================================
-- The track is OUR texture, not the slider's: Blizzard's slider art on
-- this client draws a bevelled groove that cannot be flattened, only
-- hidden. The Slider widget survives purely as the drag handler.
-- THE SETTINGS WINDOW'S SLIDER (UI.S): one line, EllesmereUI's row - the
-- label on the left, a 4 px track (fill in the accent, a 14 px accent grip
-- on a block of the window colour), and a box on the right you can type the
-- value into. Same API as the plain one (slider, valueText, SetValue,
-- _zSetQuiet, _zFit...).
local function NumberIn(text)
    local n = tonumber(((text or ""):gsub(",", ".")):match("%-?%d+%.?%d*"))
    return n
end
local function SetSlider(parent, opts)
    local lo, hi = opts.min or 0, opts.max or 1
    -- the width it was given (a page that places it by hand counts on
    -- it); a row of the layout widens it to half a row (Config_Base)
    local width = opts.width or S.SLIDER_W
    local room = UI.Room(parent)
    if room and width > room then width = room end
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(width, S.VALUE_H + 4)
    host._zSet, host._zHalf = true, true

    local step = opts.step or 1
    local decimals = 0
    do
        local sstr = string.format("%.6f", step):gsub("0+$", "")
        local dot = sstr:find("%.")
        if dot then decimals = #sstr - dot end
    end
    local function Snap(v)
        v = lo + math.floor((v - lo) / step + 0.5) * step
        v = math.max(lo, math.min(hi, v))
        if decimals > 0 then v = tonumber(string.format("%." .. decimals .. "f", v)) or v end
        return v
    end
    local fmt = opts.format or function(v)
        if decimals > 0 then return string.format("%." .. decimals .. "f", v) end
        return tostring(math.floor(v + 0.5))
    end

    -- the value box, on the right
    local box = CreateFrame("Frame", nil, host)
    UI.Fill(box, "ui", "elementBg")
    UI.Border(box, "ui", "border")
    box._zSet = true
    box:SetSize(S.VALUE_W, S.VALUE_H)
    box:SetPoint("RIGHT", host, "RIGHT", 0, 0)
    local value = CreateFrame("EditBox", nil, box)
    value:SetAllPoints(box)
    value:SetAutoFocus(false)
    value:SetJustifyH("CENTER")
    value:SetMaxLetters(12)
    value:SetFontObject("GameFontHighlightSmall")
    value._zSet = true
    FontDress(value, S.F_VALUE, "")
    if value.SetTextInsets then value:SetTextInsets(3, 3, 0, 0) end

    -- the track, left of the box
    -- (EllesmereUI's: a 4 px pill, the filled part a pill in the accent up
    -- to the thumb's middle, a round thumb on a disc of the window colour)
    local track = CreateFrame("Frame", nil, host)
    track:SetHeight(S.TRACK_H)
    local trackPill = UI.Pill(track, "BACKGROUND", 1, S.TRACK_H)
    local fill = CreateFrame("Frame", nil, track)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 0, 0)
    fill:SetWidth(S.TRACK_H)
    local fillPill = UI.Pill(fill, "ARTWORK", 0, S.TRACK_H)
    host._zFillBar = fill

    local slider = CreateFrame("Slider", nil, host)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 8)
    slider:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, -8)
    slider:SetFrameLevel(track:GetFrameLevel() + 2)
    slider:SetMinMaxValues(lo, hi)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(opts.value or lo)
    local thumb = slider:CreateTexture(nil, "OVERLAY", nil, 2)
    thumb._zui_own = true
    thumb:SetSize(S.THUMB, S.THUMB)
    slider:SetThumbTexture(thumb)
    UI.DiscArt(thumb, S.THUMB)
    -- the disc of window colour under the grip: hides the fill's end
    local block = slider:CreateTexture(nil, "OVERLAY", nil, 1)
    block._zui_own = true
    UI.DiscArt(block, S.THUMB)
    block:SetAllPoints(thumb)

    local label
    if opts.label then
        label = UI.Font(host, F.LABEL, { text = opts.label })
        label:SetPoint("LEFT", host, "LEFT", 0, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        UI.TruncTip(label, host)
        host._zLabelFS = label
    end

    local function PlaceFill(v)
        local w = track:GetWidth() or 0
        local k = (hi > lo) and math.max(0, math.min(1, ((v or lo) - lo) / (hi - lo))) or 0
        -- to the thumb's middle (the client keeps the thumb inside the
        -- track: its middle runs from half a thumb in to half a thumb short)
        local fw = S.THUMB / 2 + k * math.max(0, w - S.THUMB)
        fill:SetWidth(math.max(S.TRACK_H, math.floor(fw + 0.5)))
        fill:SetShown(k > 0)
    end
    track:SetScript("OnSizeChanged", function() PlaceFill(slider:GetValue()) end)

    -- the parts across the width: box, gap, track (160, less when tight),
    -- gap, the label in what is left (cut short with a tooltip)
    local BASE_H = S.VALUE_H + 4
    local function Lay(w)
        local bw = S.VALUE_W
        local txt = value:GetText() or ""
        local need = math.ceil((txt ~= "" and (#txt * S.F_VALUE * 0.55)) or 0) + 10
        if need > bw then bw = math.min(90, need) end
        box:SetWidth(bw)
        local lw = label and math.ceil(label:GetStringWidth() or 0) or 0
        local left = w - bw - S.TRACK_GAP
        local tw = S.TRACK_W
        box:ClearAllPoints()
        track:ClearAllPoints()
        if label and lw + S.TRACK_GAP + S.TRACK_MIN > left then
            -- too narrow for one line (a picker's column): the label on a
            -- line of its own, the track and the box under it
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
            label:SetWidth(math.max(20, w))
            local lh = math.ceil(label:GetStringHeight() or S.F_LABEL)
            local h = lh + 4 + S.VALUE_H
            host:SetHeight(h)
            host._zExtraH = h - BASE_H
            box:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
            track:SetPoint("RIGHT", box, "LEFT", -S.TRACK_GAP, 0)
            track:SetWidth(math.max(20, left))
        else
            if label then
                label:ClearAllPoints()
                label:SetPoint("LEFT", host, "LEFT", 0, 0)
                local spare = left - lw - S.TRACK_GAP - tw
                if spare < 0 then tw = math.max(S.TRACK_MIN, tw + spare) end
                label:SetWidth(math.max(20, left - tw - S.TRACK_GAP))
            else
                tw = math.max(S.TRACK_MIN, left)
            end
            host:SetHeight(BASE_H)
            host._zExtraH = nil
            box:SetPoint("RIGHT", host, "RIGHT", 0, 0)
            track:SetPoint("RIGHT", box, "LEFT", -S.TRACK_GAP, 0)
            track:SetWidth(tw)
        end
        PlaceFill(slider:GetValue())
    end
    local function Show(v) value:SetText(fmt(v)) PlaceFill(v) end
    Show(opts.value or lo)
    Lay(width)
    function host:_zFit(w)
        w = math.max(140, w)
        self:SetWidth(w)
        Lay(w)
    end
    host._zFitLabel = function(w) Lay(w) end
    function host:_zUnfit()
        self:SetSize(width, BASE_H)
        self._zExtraH = nil
        Lay(width)
    end

    local last = opts.value
    slider:SetScript("OnValueChanged", function(self, v)
        v = Snap(v)
        if not value:HasFocus() then Show(v) else PlaceFill(v) end
        if v ~= last then
            last = v
            if opts.onChange then opts.onChange(v) end
            Changed("slider")
        end
    end)
    -- typed: Enter (or leaving the box) sets it, Escape puts it back
    local function Commit(self)
        local n = NumberIn(self:GetText())
        if n then slider:SetValue(Snap(n)) end
        Show(Snap(slider:GetValue() or lo))
    end
    value:SetScript("OnEnterPressed", function(self) Commit(self) self:ClearFocus() end)
    value:SetScript("OnEscapePressed", function(self) Show(Snap(slider:GetValue() or lo)) self:ClearFocus() end)
    value:SetScript("OnEditFocusGained", function(self)
        self:SetTextColor(1, 1, 1, 1)
        if self.HighlightText then self:HighlightText() end
    end)
    value:SetScript("OnEditFocusLost", function(self)
        Commit(self)
        host:_zPaint()
    end)

    host._zPaint = function(self)
        local a = Accent()
        local off = self._zOff
        trackPill:Color(1, 1, 1, S.SL_TRACK_A)
        fillPill:Color(a.r, a.g, a.b, S.SL_FILL_A)
        -- (the thumb stays the accent, hovered or not, as EllesmereUI's)
        thumb:SetVertexColor(a.r, a.g, a.b, 1)
        block:SetVertexColor(S.BG.r, S.BG.g, S.BG.b, 1)
        local c = S.INPUT
        box._zFill:SetVertexColor(c.r, c.g, c.b, S.SL_INPUT_A)
        for _, s in ipairs(box._zBorder or {}) do s:SetVertexColor(1, 1, 1, S.SL_INPUT_BRD_A) end
        if not value:HasFocus() then value:SetTextColor(1, 1, 1, S.DIM_A) end
        if label then label:SetTextColor(1, 1, 1, 1) end
        local _ = off
    end
    box._zPaint = function() host:_zPaint() end
    slider:HookScript("OnEnter", function() host._zHot = true host:_zPaint() end)
    slider:HookScript("OnLeave", function() host._zHot = nil host:_zPaint() end)
    slider:HookScript("OnMouseDown", function() host._zDrag = true host:_zPaint() end)
    slider:HookScript("OnMouseUp", function() host._zDrag = nil host:_zPaint() end)
    if slider.EnableMouseWheel then
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            if IsShiftKeyDown and IsShiftKeyDown() then
                self:SetValue(Snap((self:GetValue() or lo) + delta * step))
                return
            end
            local p = host:GetParent()
            for _ = 1, 20 do
                if not p then break end
                local fn = p.GetScript and p:GetScript("OnMouseWheel")
                if fn and p.IsMouseWheelEnabled and p:IsMouseWheelEnabled() then fn(p, delta) return end
                p = p.GetParent and p:GetParent()
            end
        end)
    end
    host.slider, host.valueText, host.valueBox = slider, value, box
    function host:SetValue(v) slider:SetValue(v) end
    host._zSetQuiet = function(v)
        local x = v or lo
        local fn = slider:GetScript("OnValueChanged")
        slider:SetScript("OnValueChanged", nil)
        slider:SetValue(x)
        slider:SetScript("OnValueChanged", fn)
        last = v
        Show(x)
    end
    host._zPoolRefit = function(self) Lay(self:GetWidth() or width) end
    host:_zPaint()
    return host
end

function UI.Slider(parent, opts)
    opts = opts or {}
    if UI._zSettings then return SetSlider(parent, opts) end
    local width = opts.width or M.SLIDER_W
    local room = UI.Room(parent)
    if room and width > room then width = room end
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(width, 30)
    function host:_zFit(w)
        self:SetWidth(math.max(60, w))
        if self._zFitLabel then self._zFitLabel(math.max(60, w)) end
    end

    -- Label and value ride ABOVE the track (bottom-anchored), so the
    -- thumb never slides through a line of text.
    local track = CreateFrame("Frame", nil, host)
    track:SetHeight(M.TRACK_H)
    track:SetPoint("BOTTOMLEFT", 0, 5)
    track:SetPoint("BOTTOMRIGHT", 0, 5)
    UI.Fill(track, "ui", "elementBg")
    UI.Border(track, "ui", "border")

    local slider = CreateFrame("Slider", nil, host)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 2)
    slider:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, -2)
    -- ABOVE THE TRACK, and this is not a nicety.
    -- The track's border is four strips at OVERLAY sublevel 7; the thumb
    -- is a texture at OVERLAY sublevel 0. Both frames sat at the same
    -- frame level, so the strips won the tie and drew straight through the
    -- thumb - two dark lines across a pale block, on every slider in the
    -- addon. Sublevel only orders textures WITHIN a frame level, so the
    -- fix has to be at the frame level, not the sublevel.
    slider:SetFrameLevel(track:GetFrameLevel() + 2)
    slider:SetMinMaxValues(opts.min or 0, opts.max or 1)
    slider:SetValueStep(opts.step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(opts.value or opts.min or 0)

    -- A narrow flat grab riding ON the track - 2px proud of it, not the
    -- old square hanging 4px into whatever text sat underneath.
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb._zui_own = true
    thumb:SetTexture(FLAT)
    thumb:SetSize(10, M.TRACK_H + 6)
    slider:SetThumbTexture(thumb)

    -- THE FILLED PART: the track in the accent colour from its left end up
    -- to the thumb, so where the value sits reads at a glance.
    local fill = track:CreateTexture(nil, "ARTWORK")
    fill._zui_own = true
    fill:SetTexture(FLAT)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT", 1, 1)
    fill:SetWidth(1)
    host._zFillBar = fill
    local function PlaceFill(v)
        local lo, hi = slider:GetMinMaxValues()
        local w = (track:GetWidth() or 0) - 2
        local k = (hi and lo and hi > lo) and math.max(0, math.min(1, ((v or lo) - lo) / (hi - lo))) or 0
        fill:SetWidth(math.max(1, w * k))
        fill:SetShown(k > 0)
    end
    track:SetScript("OnSizeChanged", function() PlaceFill(slider:GetValue()) end)

    -- The thumb needs its own outline; a plain pale block on a dark track
    -- has no edge and reads as a smear while dragging.
    local ring = CreateFrame("Frame", nil, slider)
    ring:SetAllPoints(thumb)
    ring:SetFrameLevel(slider:GetFrameLevel() + 2)
    UI.Border(ring, "ui", "border")

    local value = UI.Font(host, F.SMALL, { justify = "RIGHT" })
    value:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    local label
    if opts.label then
        label = UI.Font(host, F.SMALL, { text = opts.label, cat = "text", key = "gray" })
        label:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        host._zLabelFS = label   -- (the name a dimmed slider's reason shows under)
    end
    -- A label longer than the slider (less room for the value) wraps over
    -- more lines and the slider grows taller; the track stays at the bottom.
    -- _zExtraH is what that added (the Layout adds it to the row).
    local function FitLabel(w)
        if not label then return end
        local valueW = math.max(30, math.ceil(value:GetStringWidth() or 0) + 6)
        local room = math.floor(w - valueW)
        if label._zWrapped or (label:GetStringWidth() or 0) > room + 0.5 then
            label:SetWordWrap(false)
            label:SetWidth(0)
            local one = math.ceil(label:GetStringHeight() or F.SMALL)
            label:SetWidth(math.max(40, room))
            label:SetJustifyH("LEFT")
            label:SetWordWrap(true)
            label._zWrapped = true
            local extra = math.max(0, math.ceil(label:GetStringHeight() or one) - one)
            host:SetHeight(30 + extra)
            host._zExtraH = extra
        end
    end

    -- Values on a step land exactly on it: 0.1 + 0.2 reads 0.3, never
    -- 0.30000000000000004, in the value shown and in what is saved.
    local step = opts.step or 1
    local decimals = 0
    do
        local sstr = string.format("%.6f", step):gsub("0+$", "")
        local dot = sstr:find("%.")
        if dot then decimals = #sstr - dot end
    end
    local function Snap(v)
        v = math.floor(v / step + 0.5) * step
        if decimals > 0 then v = tonumber(string.format("%." .. decimals .. "f", v)) or v end
        return v
    end
    local fmt = opts.format or function(v)
        if decimals > 0 then return string.format("%." .. decimals .. "f", v) end
        return tostring(math.floor(v + 0.5))
    end
    local function Show(v) value:SetText(fmt(v)) PlaceFill(v) end
    Show(opts.value or opts.min or 0)
    host._zFitLabel = FitLabel
    FitLabel(width)
    -- back to the width it was built at, its label on one line
    function host:_zUnfit()
        if label and label._zWrapped then
            label:SetWordWrap(false)
            label:SetWidth(0)
        end
        if label then label._zWrapped = nil end
        self:SetSize(width, 30)
        self._zExtraH = nil
    end

    -- Drag fires OnValueChanged many times per second. The callback here
    -- can be expensive (ApplyFonts walks ~60 font objects), so it only
    -- runs when the STEPPED value actually changes.
    local last = opts.value
    slider:SetScript("OnValueChanged", function(self, v)
        v = Snap(v)
        Show(v)
        if v ~= last then
            last = v
            if opts.onChange then opts.onChange(v) end
            Changed("slider")
        end
    end)

    -- The strips alone are not enough: PaintBox needs to know WHICH colour
    -- to paint them, and without the cat/key pair it resolves a nil lookup
    -- to the near-white text default - a pale border on every slider.
    host._zFill, host._zBorder = track._zFill, track._zBorder
    host._zBorderCat, host._zBorderKey = track._zBorderCat, track._zBorderKey
    host._zBorderAlpha = track._zBorderAlpha
    -- the thumb: the scroll thumb's colour, the accent under the mouse,
    -- the hover border's colour while it is dragged
    host._zPaint = function(self)
        PaintBox(self)
        local t = GetColor("scrollbar", "thumb")
        if self._zDrag then t = GetColor("ui", "borderHover")
        elseif self._zHot then t = GetColor("ui", "accent") end
        thumb:SetVertexColor(t.r, t.g, t.b, 1)
        local a = GetColor("ui", "accent")
        fill:SetVertexColor(a.r, a.g, a.b, 0.55)
        local b = GetColor("ui", "border")
        for _, s in ipairs(ring._zBorder) do s:SetVertexColor(b.r, b.g, b.b, 1) end
        value:_zPaint()
        if label then label:_zPaint() end
    end
    slider:HookScript("OnEnter", function() host._zHot = true host:_zPaint() end)
    slider:HookScript("OnLeave", function() host._zHot = nil host:_zPaint() end)
    slider:HookScript("OnMouseDown", function() host._zDrag = true host:_zPaint() end)
    slider:HookScript("OnMouseUp", function() host._zDrag = nil host:_zPaint() end)
    -- THE WHEEL, ONE RULE EVERYWHERE: with Shift held it moves the slider
    -- a step; without, it scrolls the page as if the slider were not there
    -- (a page full of sliders must never trap the wheel).
    if slider.EnableMouseWheel then
        slider:EnableMouseWheel(true)
        slider:SetScript("OnMouseWheel", function(self, delta)
            if IsShiftKeyDown and IsShiftKeyDown() then
                local lo, hi = self:GetMinMaxValues()
                self:SetValue(math.max(lo, math.min(hi, Snap((self:GetValue() or lo) + delta * step))))
                return
            end
            local p = host:GetParent()
            for _ = 1, 20 do
                if not p then break end
                local fn = p.GetScript and p:GetScript("OnMouseWheel")
                if fn and p.IsMouseWheelEnabled and p:IsMouseWheelEnabled() then fn(p, delta) return end
                p = p.GetParent and p:GetParent()
            end
        end)
    end
    host.slider, host.valueText = slider, value
    function host:SetValue(v) slider:SetValue(v) end
    -- a value from the settings, not from the user: no onChange, no signal
    -- (exactly what building it with this value does: the value as given,
    -- not snapped, and no OnValueChanged on the way)
    host._zSetQuiet = function(v)
        local x = v or opts.min or 0
        local fn = slider:GetScript("OnValueChanged")
        slider:SetScript("OnValueChanged", nil)
        slider:SetValue(x)
        slider:SetScript("OnValueChanged", fn)
        last = v
        Show(x)
    end
    host._zPoolRefit = function(self) FitLabel(self:GetWidth() or width) end
    host:_zPaint()
    return host
end

-- ============================================================
-- DROPDOWN
-- ============================================================
-- A self-contained menu, not Blizzard's UIDropDownMenu. Two reasons:
-- UIDropDownMenu is a taint magnet on this client, and its list frames
-- are global singletons - a second dropdown open anywhere in the UI
-- steals the list out from under ours.
function UI.Dropdown(parent, opts)
    opts = opts or {}
    local width = opts.width or 200
    local room = UI.Room(parent)
    if room and width > room then width = math.max(60, room) end
    local set = UI._zSettings
    local dd = CreateFrame("Button", nil, parent)
    dd:SetSize(width, set and S.DD_H or M.DROPDOWN_H)
    function dd:_zFit(w) self:SetWidth(math.max(60, w)) end
    UI.Fill(dd, "button", "bg")
    UI.Border(dd, "ui", "border")
    dd._zNormalKey = "bg"
    dd._zSet = set or nil

    -- (settings window: the value at 13 px, 12 in; the arrow 17 from the right)
    dd._zText = set and UI.SFont(dd, S.F_VALUE, { justify = "LEFT" }) or UI.Font(dd, F.LABEL, { justify = "LEFT" })
    dd._zText:SetPoint("LEFT", set and 12 or 7, 0)
    dd._zText:SetPoint("RIGHT", set and -27 or -20, 0)
    dd._zText:SetWordWrap(false)
    UI.TruncTip(dd._zText, dd)      -- a long choice shows whole on hover

    local arrow = dd:CreateTexture(nil, "ARTWORK")
    arrow._zui_own = true
    arrow:SetSize(set and 10 or 9, set and 10 or 9)
    arrow:SetPoint("RIGHT", set and -12 or -6, 0)
    arrow:SetTexture(TEX_ARROW)

    local menu = CreateFrame("Frame", nil, UIParent)
    openMenus[#openMenus + 1] = menu
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:Hide()
    UI.Fill(menu, "dropdown", "bg")
    UI.Border(menu, "ui", "border")
    menu._zPaint = PaintBox
    menu:_zPaint()

    local ROW = set and S.DD_ROW or 19
    -- A long list scrolls instead of running off the screen: only this
    -- many rows exist, the wheel slides an offset through the items, and
    -- a thin rail on the right shows where you are. LibSharedMedia's
    -- texture list was the menu that finally forced this.
    -- (settings window: EllesmereUI's 26 px rows; up to 18 of them, as
    -- ZacUI's lists always showed, rather than their 200 px cap)
    local MAX_ROWS = set and S.DD_ROWS or 18
    local rows = {}
    local open = false
    local offset = 0

    local rail = menu:CreateTexture(nil, "ARTWORK")
    rail._zui_own = true
    rail:SetTexture(FLAT)
    rail:SetWidth(3)
    rail:SetPoint("TOPRIGHT", -2, -2)
    rail:Hide()

    local function Close()
        open = false
        menu:Hide()
        arrow:SetTexCoord(0, 1, 0, 1)
        if dd._zSet and dd._zPaint then dd:_zPaint() end
        if UI._openDropdown == dd then UI._openDropdown = nil end
    end
    dd.Close = Close
    menu._zClose = Close

    local function Build()
        local items = opts.items and opts.items() or {}
        local total = #items
        local shown = math.min(total, MAX_ROWS)
        offset = math.max(0, math.min(offset, total - shown))
        -- selected() returns the DISPLAY text (it is what the closed box
        -- shows). Comparing a row's value against it only ever matched
        -- when label and value happened to be identical, so entries like
        -- "Blizzard default" (value "") never showed their tick.
        local selected = opts.selectedValue and opts.selectedValue()
            or (opts.selected and opts.selected())
        for i = 1, shown do
            local item = items[offset + i]
            local text = type(item) == "table" and item.text or tostring(item)
            local val  = type(item) == "table" and item.value or item
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, menu)
                row:SetHeight(ROW)
                row:SetPoint("LEFT", 2, 0)
                row:SetPoint("RIGHT", -2, 0)
                row.hl = row:CreateTexture(nil, "BACKGROUND")
                row.hl._zui_own = true
                row.hl:SetAllPoints()
                row.hl:SetTexture(FLAT)
                row.hl:Hide()
                if set then
                    row.label = UI.SFont(row, S.F_VALUE, { justify = "LEFT" })
                    row.label:SetPoint("LEFT", 8, 0)
                else
                    row.label = UI.Font(row, F.LABEL, { justify = "LEFT" })
                    row.label:SetPoint("LEFT", 6, 0)
                end
                row.label:SetPoint("RIGHT", -16, 0)
                row.label:SetWordWrap(false)
                row.tick = UI.Font(row, F.SMALL, { text = "*", cat = "dropdown", key = "selected" })
                row.tick:SetPoint("RIGHT", -5, 0)
                row:SetScript("OnEnter", function(self)
                    if set then
                        -- white 0.08 under the mouse, the label full white
                        self.hl:SetVertexColor(1, 1, 1, S.DD_HL_A)
                        self.hl:Show()
                        self.label:SetTextColor(1, 1, 1, 1)
                        return
                    end
                    local c = GetColor("dropdown", "itemHover")
                    self.hl:SetVertexColor(c.r, c.g, c.b, c.a or 1)
                    self.hl:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    if set then
                        self.hl:SetVertexColor(1, 1, 1, S.DD_SEL_A)
                        self.hl:SetShown(self._zSel and true or false)
                        self.label:SetTextColor(1, 1, 1, S.DIM_A)
                        return
                    end
                    self.hl:Hide()
                end)
                rows[i] = row
            end
            row:SetPoint("TOPLEFT", menu, "TOPLEFT", set and 1 or 2, (set and -4 or -2) - (i - 1) * ROW)
            row.label:SetText(text)
            row.label._zPaintCat, row.label._zPaintKey = "dropdown", "itemText"
            row.label:_zPaint()
            row.tick:SetShown(selected ~= nil and val == selected)
            if set then
                -- the chosen one: white 0.04 behind it, no tick
                row._zSel = (selected ~= nil and val == selected) or nil
                row.tick:Hide()
                row.label:SetTextColor(1, 1, 1, S.DIM_A)
                row.hl:SetVertexColor(1, 1, 1, S.DD_SEL_A)
                row.hl:SetShown(row._zSel and true or false)
            end
            -- opts.decorate(row, item, value, text): a picker dresses its
            -- rows (each font in its own face, a sample of each texture).
            -- Rows are reused as the list scrolls, so it runs every build.
            if opts.decorate then pcall(opts.decorate, row, item, val, text) end
            row:SetScript("OnClick", function()
                Close()
                if opts.onSelect then opts.onSelect(val, text) end
                if opts.selected then dd:SetText(opts.selected()) end
                Changed("dropdown")
            end)
            row:Show()
        end
        for i = shown + 1, #rows do rows[i]:Hide() end
        menu:SetSize(dd:GetWidth() or width, math.max(shown, 1) * ROW + (set and 7 or 4))

        -- position rail: thumb-length proportional, slid by offset
        if total > shown then
            local h = menu:GetHeight() - 4
            local len = math.max(12, h * shown / total)
            local range = h - len
            local frac = (total - shown) > 0 and offset / (total - shown) or 0
            rail:SetHeight(len)
            rail:ClearAllPoints()
            rail:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2,
                -2 - math.floor(range * frac + 0.5))
            local rc = GetColor("scrollbar", "thumb")
            rail:SetVertexColor(rc.r, rc.g, rc.b, 0.8)
            rail:Show()
        else
            rail:Hide()
        end
        return total, shown, items, selected
    end

    menu:EnableMouseWheel(true)
    menu:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Build()
    end)

    dd:SetScript("OnClick", function(self)
        if open then Close() return end
        if UI._openDropdown and UI._openDropdown ~= self then UI._openDropdown.Close() end
        -- open with the current selection in view, not page one
        offset = 0
        local n, shown, items, selected = Build()
        if n == 0 then return end
        if n > shown and selected ~= nil then
            for i, item in ipairs(items) do
                local val = type(item) == "table" and item.value or item
                if val == selected then
                    offset = math.max(0, math.min(i - math.floor(shown / 2),
                        n - shown))
                    Build()
                    break
                end
            end
        end
        menu:ClearAllPoints()
        -- Flip upward near the bottom of the screen; a menu that opens off
        -- the bottom is the classic "the list is empty" bug report.
        local below = (self:GetBottom() or 0) - menu:GetHeight()
        if below < 20 then
            menu:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 2)
        else
            menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        end
        menu:Show()
        arrow:SetTexCoord(0, 1, 1, 0)
        open = true
        UI._openDropdown = self
    end)
    menu:SetScript("OnHide", function() open = false end)

    UI.Hover(dd, "bg", "hover")
    if set then
        -- the menu: the dropdown's fill at 0.98, a white 0.20 edge
        menu._zPaint = function(self)
            local c = S.DD_BG
            self._zFill:SetVertexColor(c.r, c.g, c.b, S.DD_BG_HA)
            for _, t in ipairs(self._zBorder) do t:SetVertexColor(1, 1, 1, S.DD_BRD_A) end
        end
        menu:_zPaint()
        dd:HookScript("OnEnter", function(self) self._zHot = true self:_zPaint() end)
        dd:HookScript("OnLeave", function(self) self._zHot = nil self:_zPaint() end)
    end
    dd._zPaint = function(self)
        if set then
            local hot = (self._zHot or open) and not self._zOff
            local c = S.DD_BG
            self._zFill:SetVertexColor(c.r, c.g, c.b, hot and S.DD_BG_HA or S.DD_BG_A)
            for _, t in ipairs(self._zBorder) do t:SetVertexColor(1, 1, 1, hot and S.DD_BRD_HA or S.DD_BRD_A) end
            local ta = hot and S.DD_TXT_HA or S.DD_TXT_A
            self._zText:SetTextColor(1, 1, 1, ta)
            arrow:SetVertexColor(1, 1, 1, ta)
            return
        end
        PaintBox(self)
        local a = GetColor("dropdown", "arrow")
        arrow:SetVertexColor(a.r, a.g, a.b, 1)
        self._zText:_zPaint()
    end
    function dd:SetText(t) self._zText:SetText(t or "") end
    dd._zPoolRefresh = function(self) self:SetText(opts.selected and opts.selected() or opts.text) end
    dd:SetText(opts.selected and opts.selected() or opts.text)
    dd:_zPaint()
    return dd
end

function UI.CloseAllDropdowns()
    for _, menu in ipairs(openMenus) do
        if menu:IsShown() and menu._zClose then pcall(menu._zClose) end
    end
    UI._openDropdown = nil
end

-- ============================================================
-- CONTEXT MENU
-- ============================================================
-- A right-click menu in the house style, for anything that wants one
-- (the minimap button, bars, windows). Not Blizzard's UIDropDownMenu: that
-- one is a taint magnet on this client and its list frames are global
-- singletons another addon's menu can steal mid-use.
--
--   UI.ContextMenu(items, opts)
--   item = { text = "..", func = function() end,
--            checked = true | function() -> bool,   -- draws a tick
--            isTitle = true,                        -- gold, not clickable
--            separator = true,                      -- a thin rule
--            disabled = true,                       -- greyed, not clickable
--            tooltip = "..",                        -- shown on hover
--            keepOpen = true,                       -- click leaves the menu up (toggles)
--            children = { items } | function() -> items }  -- a submenu, opens on hover
--   opts.anchor: a frame to hang from (default: the cursor)
--
-- The levels are pooled and reused, so a menu is only ever a table of
-- items. Any click outside the chain closes all of it.
local ctxLevels = {}
local ctxCatcher
local CTX_ROW, CTX_SEP, CTX_PAD = 18, 7, 4

local function CtxCloseFrom(level)
    for i = level, #ctxLevels do
        if ctxLevels[i] then ctxLevels[i]:Hide() end
    end
    if level <= 1 and ctxCatcher then ctxCatcher:Hide() end
end

local function CtxCatcher()
    if ctxCatcher then return ctxCatcher end
    -- everything under the menu: one click anywhere on it closes the chain
    ctxCatcher = CreateFrame("Frame", nil, UIParent)
    ctxCatcher:SetAllPoints(UIParent)
    ctxCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
    ctxCatcher:SetFrameLevel(1)
    ctxCatcher:EnableMouse(true)
    ctxCatcher:SetScript("OnMouseDown", function() CtxCloseFrom(1) end)
    -- no keyboard: a key-eating frame needs SetPropagateKeyboardInput,
    -- which is protected in combat, and a menu that opens mid-fight must
    -- never be the thing that throws
    ctxCatcher:Hide()
    return ctxCatcher
end

local function CtxAnyHovered()
    for _, m in ipairs(ctxLevels) do
        if m:IsShown() and m:IsMouseOver(8, -8, -8, 8) then return true end
    end
    return false
end

local function CtxLevel(i)
    local m = ctxLevels[i]
    if m then return m end
    m = CreateFrame("Frame", nil, UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(10 + i * 5)
    m:SetClampedToScreen(true)
    -- the mouse wandering off the whole chain closes it after a beat, the
    -- way a tooltip goes: only level 1 runs the clock, for the chain
    if i == 1 then
        m.away = 0
        m:SetScript("OnUpdate", function(self, elapsed)
            if CtxAnyHovered() then self.away = 0 return end
            self.away = self.away + elapsed
            if self.away > 1.5 then self.away = 0 CtxCloseFrom(1) end
        end)
        m:HookScript("OnShow", function(self) self.away = 0 end)
    end
    UI.Fill(m, "dropdown", "bg")
    UI.Border(m, "ui", "border")
    m._zPaint = PaintBox
    m:_zPaint()
    m.rows = {}
    m.rules = {}
    m:Hide()
    ctxLevels[i] = m
    openMenus[#openMenus + 1] = m
    m._zClose = function() CtxCloseFrom(1) end
    return m
end

local function CtxRow(m, i)
    local row = m.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, m)
    row:SetHeight(CTX_ROW)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl._zui_own = true
    row.hl:SetAllPoints()
    row.hl:SetTexture(FLAT)
    row.hl:Hide()
    row.label = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.label:SetPoint("LEFT", 18, 0)
    row.label:SetPoint("RIGHT", -16, 0)
    row.label:SetWordWrap(false)
    row.tick = row:CreateTexture(nil, "ARTWORK")
    row.tick._zui_own = true
    row.tick:SetSize(10, 10)
    row.tick:SetPoint("LEFT", 4, 0)
    row.tick:SetTexture(TEX_CHECK)
    row.tick:Hide()
    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow._zui_own = true
    row.arrow:SetSize(8, 8)
    row.arrow:SetPoint("RIGHT", -5, 0)
    row.arrow:SetTexture(TEX_ARROW)
    if row.arrow.SetRotation then row.arrow:SetRotation(math.rad(90)) end
    row.arrow:Hide()
    m.rows[i] = row
    return row
end

local CtxShow -- forward: rows open submenus through it

local function CtxBuild(m, level, items)
    local y, n, width, sep = -CTX_PAD, 0, 110, 0
    for _, item in ipairs(items) do
        if item.separator then
            sep = sep + 1
            local rule = m.rules[sep]
            if not rule then
                rule = m:CreateTexture(nil, "ARTWORK")
                rule._zui_own = true
                rule:SetTexture(FLAT)
                if ns.Pixel then ns.Pixel.Edge(rule, "TOP", m) else rule:SetHeight(1) end
                m.rules[sep] = rule
            end
            rule:ClearAllPoints()
            rule:SetPoint("TOPLEFT", m, "TOPLEFT", 8, y - 3)
            rule:SetPoint("RIGHT", m, "RIGHT", -8, 0)
            local c = GetColor("ui", "border")
            rule:SetVertexColor(c.r, c.g, c.b, 0.6)
            rule:Show()
            y = y - CTX_SEP
        else
            n = n + 1
            local row = CtxRow(m, n)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", m, "TOPLEFT", 2, y)
            row:SetPoint("RIGHT", m, "RIGHT", -2, 0)
            row.label:SetText(item.text or "")
            local key = item.isTitle and "gold" or (item.disabled and "disabled") or "normal"
            row.label._zPaintCat, row.label._zPaintKey = "text", key
            row.label:_zPaint()
            local checked = item.checked
            if type(checked) == "function" then checked = checked() end
            row.tick:SetShown(checked and true or false)
            if checked then
                local c = GetColor("dropdown", "selected")
                row.tick:SetVertexColor(c.r, c.g, c.b, 1)
            end
            row.arrow:SetShown(item.children ~= nil)
            if item.children then
                local a = GetColor("dropdown", "arrow")
                row.arrow:SetVertexColor(a.r, a.g, a.b, 1)
            end
            row.item = item
            row.level = level
            row:SetScript("OnEnter", function(self)
                local it = self.item
                if not it.isTitle and not it.disabled then
                    local c = GetColor("dropdown", "itemHover")
                    self.hl:SetVertexColor(c.r, c.g, c.b, c.a or 1)
                    self.hl:Show()
                end
                if it.children then
                    local kids = type(it.children) == "function" and it.children() or it.children
                    CtxShow(kids, { anchor = self, level = self.level + 1 })
                else
                    CtxCloseFrom(self.level + 1)
                end
                if it.tooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(it.text or "", 1, 1, 1)
                    GameTooltip:AddLine(it.tooltip, nil, nil, nil, true)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(self)
                self.hl:Hide()
                GameTooltip:Hide()
            end)
            row:SetScript("OnClick", function(self)
                local it = self.item
                if it.isTitle or it.disabled or it.children then return end
                if it.func then it.func() end
                if it.keepOpen then
                    CtxBuild(m, level, items)
                else
                    CtxCloseFrom(1)
                end
            end)
            row:Show()
            local w = row.label:GetStringWidth() + 40
            if w > width then width = w end
            y = y - CTX_ROW
        end
    end
    for i = n + 1, #m.rows do m.rows[i]:Hide() end
    for i = sep + 1, #m.rules do m.rules[i]:Hide() end
    m:SetSize(math.min(280, math.max(120, width)), -y + CTX_PAD)
end

CtxShow = function(items, opts)
    opts = opts or {}
    local level = opts.level or 1
    -- close what was up FIRST: CtxCloseFrom(1) hides the catcher, so the
    -- catcher is shown after it, never before (a menu with no catcher
    -- cannot be clicked away and sits there until an item is picked)
    if level == 1 then UI.CloseAllDropdowns() end
    CtxCloseFrom(level)
    if level == 1 then CtxCatcher():Show() end
    local m = CtxLevel(level)
    CtxBuild(m, level, items or {})
    m:ClearAllPoints()
    if opts.anchor and level > 1 then
        m:SetPoint("TOPLEFT", opts.anchor, "TOPRIGHT", 2, CTX_PAD)
    elseif opts.anchor then
        m:SetPoint("TOPLEFT", opts.anchor, "BOTTOMLEFT", 0, -2)
    else
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 4, y / scale + 4)
    end
    m:Show()
    return m
end
UI.ContextMenu = CtxShow

-- A menu drawn as a sample (a settings preview: the consumable bars'
-- clash picker): the same rows UI.ContextMenu draws, on a frame of the
-- caller's (not the pooled levels, no click-away catcher, no timer), and
-- nothing on it takes the mouse. m:Fill(items) draws a list.
function UI.ContextMenuSample(parent)
    local m = CreateFrame("Frame", nil, parent)
    UI.Fill(m, "dropdown", "bg")
    UI.Border(m, "ui", "border")
    m._zPaint = PaintBox
    m:_zPaint()
    m.rows, m.rules = {}, {}
    function m:Fill(items)
        CtxBuild(self, 0, items or {})
        for _, r in ipairs(self.rows) do r:EnableMouse(false) end
    end
    return m
end

-- ============================================================
-- EDIT BOX
-- ============================================================
function UI.EditBox(parent, opts)
    opts = opts or {}
    local set = UI._zSettings
    local host = UI.Box(parent, "ui", "elementBg")
    local width = opts.width or 180
    local room = UI.Room(parent)
    if room and width > room then width = math.max(60, room) end
    -- (settings window: EllesmereUI's search field - 28 high, the input
    -- colour at 0.35, a white 0.10 edge, the accent while typing, 13 px
    -- text 10 in)
    host:SetSize(width, set and math.max(opts.height or 0, S.EDIT_H) or (opts.height or M.EDIT_H))
    function host:_zFit(w) self:SetWidth(math.max(60, w)) end
    local INSET = set and 10 or 6

    local eb = CreateFrame("EditBox", nil, host)
    eb:SetPoint("TOPLEFT", INSET, -2)
    eb:SetPoint("BOTTOMRIGHT", -INSET, 2)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    if set then
        host._zSet, eb._zSet = true, true
        FontDress(eb, S.F_VALUE, "")
        host._zPaint = function(self)
            local c = S.INPUT
            self._zFill:SetVertexColor(c.r, c.g, c.b, S.INPUT_A)
            local focus = self._zBorderKey == "accent"
            local a = focus and Accent() or WHITE
            for _, t in ipairs(self._zBorder) do t:SetVertexColor(a.r, a.g, a.b, focus and 0.8 or S.INPUT_BRD_A) end
            eb:SetTextColor(1, 1, 1, 0.9)
        end
        host:_zPaint()
    else
        FontDress(eb, F.LABEL, "")
    end
    eb:SetText(opts.text or "")
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if opts.onEnter then
            opts.onEnter(self:GetText())
            Changed("editbox")
        end
    end)
    if opts.onChange then
        eb:SetScript("OnTextChanged", function(self, user)
            if user then opts.onChange(self:GetText()) end
        end)
    end

    -- Focus lights the border gold. It is the only focus affordance a
    -- flat box gets, and losing it makes a form feel dead.
    eb:SetScript("OnEditFocusGained", function()
        host._zBorderCat, host._zBorderKey = "ui", "accent"
        host:_zPaint()
    end)
    eb:SetScript("OnEditFocusLost", function()
        host._zBorderCat, host._zBorderKey = "ui", "border"
        host:_zPaint()
    end)

    local hint
    if opts.hint then
        if set then
            hint = UI.SFont(host, S.F_HINT, { text = opts.hint, justify = "LEFT" })
            hint:SetTextColor(1, 1, 1, 0.30)
            hint._zPaint = function(self) self:SetTextColor(1, 1, 1, 0.30) end
        else
            hint = UI.Font(host, F.LABEL, { text = opts.hint, cat = "text", key = "gray", justify = "LEFT" })
        end
        hint:SetPoint("LEFT", INSET + 1, 0)
        -- held inside the box: a hint longer than the box is cut short
        -- (its tooltip shows the whole of it), never drawn past the edge
        hint:SetPoint("RIGHT", host, "RIGHT", -(INSET + 1), 0)
        hint:SetWordWrap(false)
        UI.TruncTip(hint, eb)
        if not set then hint:SetAlpha(0.7) end
        local function Sync()
            hint:SetShown((eb:GetText() or "") == "")
        end
        eb:HookScript("OnTextChanged", Sync)
        eb:HookScript("OnEditFocusGained", Sync)
        eb:HookScript("OnEditFocusLost", Sync)
        Sync()
    end

    -- THE CLEAR BUTTON. A hint means the box is a filter - search, a
    -- spell id - and a filter is something you empty a hundred times a
    -- session, which is a lot of held backspace. So every hinted box gets
    -- an X on its right that appears the moment there is text, wipes it,
    -- and fires the same callbacks typing an empty string would, so the
    -- list behind it resets rather than sitting on a stale filter until
    -- the next keystroke. opts.clear forces it either way.
    local wantClear = opts.clear
    if wantClear == nil then wantClear = opts.hint ~= nil end
    if wantClear then
        local x = UI.CloseX(host, set and 20 or 14, function()
            eb:SetText("")
            if opts.onChange then opts.onChange("") end
            if opts.onEnter then opts.onEnter("") end
            eb:ClearFocus()
            if opts.onEnter then Changed("editbox") end
        end)
        x:SetPoint("RIGHT", host, "RIGHT", -3, 0)
        x:SetFrameLevel(eb:GetFrameLevel() + 2)
        host.clearButton = x
        local function SyncClear()
            local has = (eb:GetText() or "") ~= ""
            x:SetShown(has)
            -- Make room for it only while it is there; an always-narrow
            -- box wastes its last twenty pixels on nothing.
            eb:SetPoint("BOTTOMRIGHT", has and -24 or -INSET, 2)
        end
        eb:HookScript("OnTextChanged", SyncClear)
        SyncClear()
    end

    host.editBox = eb
    function host:GetText() return eb:GetText() end
    function host:SetText(t) eb:SetText(t or "") end
    return host
end

-- ============================================================
-- TEXT BOX (multi-line)
-- ============================================================
-- For export and import strings. Two things make this different from a
-- normal edit box and both matter:
--
--   * It has to be SELECTABLE even when it is really an output field.
--     WoW has no clipboard API, so "copy this" means "put it in an edit
--     box the player can ctrl-A, ctrl-C out of". A read-only display
--     would be useless.
--   * A profile string is long. It needs to wrap and scroll rather than
--     run off the side of the window.
function UI.TextBox(parent, opts)
    opts = opts or {}
    local host = UI.Box(parent, "ui", "elementBg")
    local width = opts.width or 380
    local room = UI.Room(parent)
    if room and width > room then width = math.max(120, room) end
    host:SetSize(width, opts.height or 90)

    local scroll = CreateFrame("ScrollFrame", nil, host)
    scroll:SetPoint("TOPLEFT", 6, -5)
    scroll:SetPoint("BOTTOMRIGHT", -6, 5)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetWidth(width - 14)
    function host:_zFit(w)
        w = math.max(120, w)
        self:SetWidth(w)
        eb:SetWidth(w - 14)
    end
    eb:SetFontObject("GameFontHighlightSmall")
    -- (no size adjustment here, as before: the box is a fixed size)
    FontDress(eb, F.SMALL, "", true)
    eb:SetText(opts.text or "")
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Selecting everything on focus is the whole interaction for an
    -- export box: click it, ctrl-C, done.
    if opts.selectOnFocus then
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    end
    if opts.onChange then
        eb:SetScript("OnTextChanged", function(self, user)
            if user then opts.onChange(self:GetText()) end
        end)
    end
    scroll:SetScrollChild(eb)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, (eb:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.max(0,
            math.min(max, self:GetVerticalScroll() - delta * 20)))
    end)

    host.editBox = eb
    function host:GetText() return eb:GetText() end
    function host:SetText(t)
        eb:SetText(t or "")
        scroll:SetVerticalScroll(0)
    end
    function host:Focus() eb:SetFocus() end
    function host:_zUnfit() eb:SetWidth(width - 14) end
    return host
end

-- ============================================================
-- SCROLL AREA
-- ============================================================
-- Classic ScrollFrame + our own Slider. The modern ScrollBox stack is not
-- reliably present on 11509 and brings a template dependency we do not
-- need for a settings list.
-- opts.style "settings" / "nav" (the settings window, UI.S): EllesmereUI's
-- thin bar - a 4 px white 0.02 track and a 4 px white 0.27 thumb (nav:
-- 3 px, 0.03 / 0.25), at least 30 tall, in a 16 px hit strip; 60 per wheel
-- notch, eased `cur + diff * min(1, 12 * dt)` to whole pixels.
function UI.ScrollArea(parent, opts)
    local style = type(opts) == "table" and opts.style or nil
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetWidth(M.SCROLL_W)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)

    -- SLIM: a narrow, faint rail and a thin thumb that rests half lit and
    -- comes up full while the mouse is on it, while it is dragged and for
    -- a moment after every scroll - the same in every scroll area.
    local track = CreateFrame("Frame", nil, bar)
    local thin = style and (style == "nav" and 3 or 4) or nil
    if thin then
        track:SetWidth(thin)
        track:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -(M.SCROLL_W - thin) / 2, 0)
        track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -(M.SCROLL_W - thin) / 2, 0)
    else
        track:SetPoint("TOPLEFT", 5, 0)
        track:SetPoint("BOTTOMRIGHT", -5, 0)
    end
    track:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
    UI.Fill(track, "scrollbar", "track")
    if not thin then UI.Border(track, "ui", "border", 0.4) end
    track._zPaint = PaintBox
    track:_zPaint()

    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb._zui_own = true
    thumb:SetTexture(thin and FLAT or TEX_THUMB)
    thumb:SetSize(thin or (M.SCROLL_W - 10), thin and 60 or 42)
    bar:SetThumbTexture(thumb)
    local REST, LIT = 0.5, 1
    local lit, serial = false, 0
    local function PaintThumb()
        if thin then
            local ta, ka = S.SCROLL_TRACK_A, S.SCROLL_THUMB_A
            if style == "nav" then ta, ka = S.NAV_TRACK_A, S.NAV_THUMB_A end
            track._zFill:SetVertexColor(1, 1, 1, ta)
            thumb:SetVertexColor(1, 1, 1, (lit or bar._zHot or bar._zDrag) and math.min(1, ka + 0.2) or ka)
            return
        end
        local tc = GetColor("scrollbar", "thumb")
        local on = lit or bar._zHot or bar._zDrag
        thumb:SetVertexColor(tc.r, tc.g, tc.b, (tc.a or 1) * (on and LIT or REST))
    end
    -- lit for a moment after a scroll (one timer, checked when it fires)
    local function Flash()
        lit = true
        PaintThumb()
        serial = serial + 1
        local mine = serial
        C_Timer.After(1.2, function()
            if mine ~= serial then return end
            lit = false
            if bar:IsVisible() then PaintThumb() end
        end)
    end
    bar:EnableMouse(true)
    bar:HookScript("OnEnter", function() bar._zHot = true PaintThumb() end)
    bar:HookScript("OnLeave", function() bar._zHot = nil PaintThumb() end)
    bar:HookScript("OnMouseDown", function() bar._zDrag = true PaintThumb() end)
    bar:HookScript("OnMouseUp", function() bar._zDrag = nil PaintThumb() end)

    -- SMOOTH WHEEL (finish pass). A notch is M.WHEEL units (24, was 34),
    -- eased out over about 0.15 s, every step on a whole physical pixel
    -- under the ZacUI look (ns.Pixel) so text never shimmers between two.
    -- The OnUpdate is set only while it glides and taken off on arrival;
    -- a drag of the bar or a jump (search, a page change) cancels it.
    -- With animations off (Appearance > Motion) a notch jumps, as before.
    local target, gliding, own, lastSet = nil, false, false, nil
    local function Snap(v)
        local P = ns.Pixel
        if P and P.On and P.On() and P.Snap then return P.Snap(v, child) end
        return v
    end
    local function Stop()
        target = nil
        if gliding then gliding = false scroll:SetScript("OnUpdate", nil) end
    end
    local function Glide(_, dt)
        if not target then Stop() return end
        local v = bar:GetValue()
        -- moved by someone else since the last step (a drag, a jump - a page
        -- may own the bar's OnValueChanged): that wins
        if lastSet and math.abs(v - lastSet) > 0.01 then Stop() return end
        -- the page may have grown or shrunk under it
        local minV, maxV = bar:GetMinMaxValues()
        target = math.max(minV, math.min(maxV, target))
        local nv
        if thin then
            nv = v + (target - v) * math.min(1, S.LERP * (dt or 0.016))
        else
            nv = v + (target - v) * (1 - math.exp(-(dt or 0.016) * 18))
        end
        own = true
        if math.abs(target - nv) < (thin and 0.3 or 0.5) then
            bar:SetValue(target)
            own = false
            Stop()
            return
        end
        nv = Snap(nv)
        -- (a snap that lands back where it was still moves one pixel on)
        if nv == v then nv = v + ((target > v) and 1 or -1) * math.min(math.abs(target - v), (ns.Pixel and ns.Pixel.One and ns.Pixel.One(child)) or 1) end
        bar:SetValue(nv)
        lastSet = bar:GetValue()
        own = false
    end
    bar:SetScript("OnValueChanged", function(self, v)
        if not own and target then Stop() end
        scroll:SetVerticalScroll(v)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        local minV, maxV = bar:GetMinMaxValues()
        local from = target or bar:GetValue()
        local v = math.max(minV, math.min(maxV, from - delta * (thin and S.WHEEL or M.WHEEL or 24)))
        local Motion = ns.Motion
        if (Motion and Motion.Enabled and not Motion.Enabled()) or not scroll:IsVisible() then
            Stop()
            bar:SetValue(v)
        else
            target = v
            if not gliding then
                gliding = true
                lastSet = bar:GetValue()
                scroll:SetScript("OnUpdate", Glide)
            end
        end
        if maxV > 0 then Flash() end
    end)
    scroll:HookScript("OnHide", function()
        -- put away mid-glide: land where it was going
        if target then
            local t = target
            Stop()
            bar:SetValue(t)
        end
    end)
    function scroll:Gliding() return gliding end

    -- Range is recomputed from the measured content, not from a running
    -- total kept by the caller: pages build at different rates and a
    -- stale total is how a list ends up unable to reach its last row.
    function scroll:Recalculate(contentHeight)
        local h = contentHeight or child:GetHeight() or 0
        local view = scroll:GetHeight() or 1
        local maxScroll = math.max(0, h - view)
        bar:SetMinMaxValues(0, maxScroll)
        if bar:GetValue() > maxScroll then bar:SetValue(maxScroll) end
        bar:SetShown(maxScroll > 1)
        if maxScroll > 1 then
            local frac = view / h
            thumb:SetHeight(math.max(thin and 30 or 28, math.floor(view * frac)))
        end
    end

    scroll.bar, scroll.child = bar, child
    scroll._zPaint = function() PaintThumb() end
    scroll:_zPaint()
    return scroll, child, bar
end

-- ============================================================
-- CARD + PAGE HEADER
-- ============================================================
-- A card is a titled section. Its border is deliberately softer than a
-- widget's - a page of eight hard black rectangles reads as a grid, and
-- the eye stops finding the headings.
-- In the settings window (UI.S) a card is EllesmereUI's section: no box,
-- a 40 px head with the title at 12 px, white 0.41 and a white
-- 0.02 rule under it, then rows (Config_Base lays their alternating bands).
local function SetCard(parent, title, y, opts)
    local card = CreateFrame("Frame", nil, parent)
    card._zSet = true
    card:SetPoint("TOPLEFT", S.PAD, y)
    card:SetPoint("RIGHT", parent, "RIGHT", -S.PAD, 0)
    card:SetHeight(opts.height or 50)
    UI.Fill(card, "ui", "cardBg")
    -- (kept, see-through: the settings tests and search know a card by it)
    local accent = card:CreateTexture(nil, "ARTWORK")
    accent._zui_own = true
    accent:SetTexture(FLAT)
    accent:SetWidth(1)
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    card._zAccent = accent
    local rule
    if title then
        card._zTitleText = title
        -- (as written: other code and the suites read a card by its title)
        card._zTitle = UI.SFont(card, S.F_SECTION, { text = title, justify = "LEFT" })
        card._zTitle._zPaint = function(self) self:SetTextColor(1, 1, 1, S.SECTION_A) end
        card._zTitle:SetPoint("BOTTOMLEFT", card, "TOPLEFT", 1, -S.SECTION + 8)
        rule = card:CreateTexture(nil, "ARTWORK")
        rule._zui_own = true
        rule:SetTexture(FLAT)
        if ns.Pixel then ns.Pixel.Edge(rule, "TOP", card) else rule:SetHeight(1) end
        rule:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -(S.SECTION - 1))
        rule:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -(S.SECTION - 1))
        card._zRule = rule
        local room = UI.Room(card, 0)
        if room and (card._zTitle:GetStringWidth() or 0) > room + 0.5 then
            local one = card._zTitle:GetStringHeight() or S.F_SECTION
            card._zTitle:SetWidth(room)
            card._zTitle:SetWordWrap(true)
            card._zTitleExtra = math.max(0, math.ceil((card._zTitle:GetStringHeight() or one) - one))
            card._zTitle:ClearAllPoints()
            card._zTitle:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -(S.SECTION - 8 - one))
            rule:ClearAllPoints()
            rule:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -(S.SECTION - 1 + card._zTitleExtra))
            rule:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -(S.SECTION - 1 + card._zTitleExtra))
        end
        local t = card._zTitle
        -- (back to how it was built - wrapped or not - on reuse)
        local bw, bx = card._zTitleExtra and room or 0, card._zTitleExtra
        local bwrap = t.CanWordWrap and t:CanWordWrap()
        local tp = { t:GetPoint(1) }
        local rp1, rp2 = { rule:GetPoint(1) }, { rule:GetPoint(2) }
        function card:_zUnfit()
            t:SetWidth(bw)
            if bwrap ~= nil then t:SetWordWrap(bwrap) end
            t:ClearAllPoints()
            t:SetPoint(tp[1], tp[2], tp[3], tp[4], tp[5])
            rule:ClearAllPoints()
            rule:SetPoint(rp1[1], rp1[2], rp1[3], rp1[4], rp1[5])
            rule:SetPoint(rp2[1], rp2[2], rp2[3], rp2[4], rp2[5])
            self._zTitleExtra = bx
        end
    end
    card._zPaint = function(self)
        self._zFill:SetVertexColor(0, 0, 0, 0)
        self._zAccent:SetVertexColor(0, 0, 0, 0)
        if rule then rule:SetVertexColor(1, 1, 1, S.SECTION_RULE_A) end
        if self._zTitle then self._zTitle:_zPaint() end
    end
    -- rows meet the section's foot: no padding of its own
    function card:SetContentHeight(h)
        self:SetHeight(math.max(1, h))
        return self:GetHeight()
    end
    card:_zPaint()
    return card
end

function UI.Card(parent, title, y, opts)
    opts = opts or {}
    if UI._zSettings then return SetCard(parent, title, y, opts) end
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", M.MARGIN, y)
    card:SetPoint("RIGHT", parent, "RIGHT", -M.MARGIN, 0)
    card:SetHeight(opts.height or 50)
    UI.Fill(card, "ui", "cardBg")
    UI.Border(card, "ui", "border", 0.55)
    card._zPaint = function(self)
        PaintBox(self)
        local a = GetColor("ui", "accent")
        self._zAccent:SetVertexColor(a.r, a.g, a.b, 0.8)
        if self._zTitle then self._zTitle:_zPaint() end
    end

    local accent = card:CreateTexture(nil, "ARTWORK")
    accent._zui_own = true
    accent:SetTexture(FLAT)
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    card._zAccent = accent

    if title then
        card._zTitle = UI.Font(card, F.CARD, { text = title, cat = "text", key = "gold" })
        card._zTitle:SetPoint("TOPLEFT", M.CARD_PAD, -9)
        -- A title wider than the card wraps; _zTitleExtra is the height the
        -- extra lines take (the Layout starts the card's rows that much lower).
        local room = UI.Room(card, M.CARD_PAD)
        if room and (card._zTitle:GetStringWidth() or 0) > room + 0.5 then
            local one = card._zTitle:GetStringHeight() or F.CARD
            card._zTitle:SetWidth(room)
            card._zTitle:SetJustifyH("LEFT")
            card._zTitle:SetWordWrap(true)
            card._zTitleExtra = math.max(0, math.ceil((card._zTitle:GetStringHeight() or one) - one))
        end
        -- (what the title looked like built; the card's "?" may narrow it)
        local t = card._zTitle
        local tw0 = card._zTitleExtra and room or 0
        local tj0, twr0 = t:GetJustifyH(), t.CanWordWrap and t:CanWordWrap()
        function card:_zUnfit()
            t:SetWidth(tw0)
            if tj0 then t:SetJustifyH(tj0) end
            if twr0 ~= nil then t:SetWordWrap(twr0) end
        end
    end

    -- Cards grow as their content is added; the caller reports the lowest
    -- y it used and the card adds its own bottom padding. Keeps every
    -- page's layout arithmetic to one running number.
    function card:SetContentHeight(h)
        self:SetHeight(math.max(36, h + 14))
        return self:GetHeight()
    end
    card:_zPaint()
    return card
end

-- In the settings window the page's title is EllesmereUI's header: the
-- name at 36, white, 45 in and 35 down, the line under it at 14 / 0.53
-- (two lines at most), 138 tall (Config_Window pins it above the tabs).
local function SetPageHeader(parent, title, subtitle, y)
    local f = CreateFrame("Frame", nil, parent)
    f._zSet = true
    f:SetPoint("TOPLEFT", 0, y)
    f:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    local t = UI.SFont(f, S.F_TITLE, { text = title })
    t:SetPoint("TOPLEFT", f, "TOPLEFT", S.PAD, -35)
    t._zPaint = function(self) self:SetTextColor(1, 1, 1, 1) end
    local s
    local h = S.HEADER
    if subtitle then
        s = UI.SFont(f, S.F_DESC, { text = subtitle })
        s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 2, -12)
        s:SetPoint("RIGHT", f, "RIGHT", -S.PAD, 0)
        s:SetJustifyH("LEFT")
        s:SetWordWrap(true)
        if s.SetMaxLines then s:SetMaxLines(2) end
        s._zPaint = function(self) self:SetTextColor(1, 1, 1, S.DIM_A) end
        local need = 35 + math.ceil(t:GetStringHeight() or S.F_TITLE) + 12 + math.ceil(s:GetStringHeight() or S.F_DESC) + 16
        h = math.max(h, need)
    end
    f:SetHeight(h)
    f._zPaint = function(self)
        t:_zPaint()
        if s then s:_zPaint() end
    end
    f:_zPaint()
    f._zTitleFS, f._zSubFS = t, s
    return f, y - f:GetHeight()
end

function UI.PageHeader(parent, title, subtitle, y)
    if UI._zSettings then return SetPageHeader(parent, title, subtitle, y) end
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", M.MARGIN, y)
    f:SetPoint("RIGHT", parent, "RIGHT", -M.MARGIN, 0)
    f:SetHeight(30)

    local t = UI.Font(f, F.HEADER, { text = title, cat = "text", key = "gold" })
    t:SetPoint("TOPLEFT", 0, -2)

    local s
    if subtitle then
        s = UI.Font(f, F.SUB, { text = subtitle, cat = "text", key = "gray" })
        s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
        s:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        s:SetJustifyH("LEFT")
        s:SetWordWrap(true)
        -- MEASURED, not assumed. Every subtitle on these pages is a
        -- sentence, and at this width most of them wrap to two lines - a
        -- fixed 44 puts the gold rule through the second one.
        f:SetHeight(26 + math.max(12, s:GetStringHeight()) + 6)
    end

    local rule = f:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    if ns.Pixel then ns.Pixel.Edge(rule, "BOTTOM", f) else rule:SetHeight(1) end
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    f._zRule = rule
    f._zPaint = function(self)
        local a = GetColor("ui", "accent")
        self._zRule:SetVertexColor(a.r, a.g, a.b, 0.6)
        t:_zPaint()
        if s then s:_zPaint() end
    end
    f:_zPaint()
    return f, y - f:GetHeight() - 12
end

-- ============================================================
-- COLOUR PICKER (the game's dialog)
-- ============================================================
-- UI.OpenColorPicker({ r, g, b, a, alpha = true,
--     onChange = function(r, g, b, a) end,   -- every move while dragging
--     onCancel = function(r, g, b, a) end }) -- the values it opened with
-- The one place ZacUI talks to ColorPickerFrame. Two client generations
-- of the same dialog: the modern one takes an options table and reports
-- alpha as alpha; the classic one wants fields poked onto the frame
-- before Show and keeps OPACITY (1 - alpha) on its own slider. Neither is
-- optional to support on 11509. Cancel hands back the values captured
-- here rather than trusting the dialog's previousValues, whose shape
-- differs between the two.
function UI.OpenColorPicker(o)
    local CPF = ColorPickerFrame
    if not CPF then return false end
    local r0, g0, b0 = o.r or 1, o.g or 1, o.b or 1
    local a0 = o.a or 1
    local withAlpha = o.alpha and true or false
    local function Alpha()
        if not withAlpha then return a0 end
        if CPF.GetColorAlpha then
            local ok, a = pcall(CPF.GetColorAlpha, CPF)
            if ok and type(a) == "number" then return a end
        end
        if OpacitySliderFrame and OpacitySliderFrame.GetValue then
            return 1 - (OpacitySliderFrame:GetValue() or 0)
        end
        return a0
    end
    local function Commit()
        local r, g, b = CPF:GetColorRGB()
        if o.onChange then o.onChange(r, g, b, Alpha()) end
    end
    local function Cancel()
        if o.onCancel then o.onCancel(r0, g0, b0, a0) end
    end
    if CPF.SetupColorPickerAndShow then
        CPF:SetupColorPickerAndShow({
            r = r0, g = g0, b = b0,
            hasOpacity = withAlpha, opacity = a0,
            swatchFunc = Commit, opacityFunc = Commit, cancelFunc = Cancel,
        })
    else
        -- Hide first: the classic dialog wires itself up in OnShow, and
        -- clicking a second swatch while it is already open would keep
        -- the previous swatch's callbacks.
        CPF:Hide()
        CPF.func = Commit
        CPF.opacityFunc = Commit
        CPF.cancelFunc = Cancel
        CPF.hasOpacity = withAlpha
        CPF.opacity = 1 - a0
        CPF.previousValues = { r = r0, g = g0, b = b0, opacity = 1 - a0 }
        CPF:SetColorRGB(r0, g0, b0)
        CPF:Show()
    end
    return true
end

-- ============================================================
-- COLOUR SWATCH (a palette colour)
-- ============================================================
-- For any other colour - a setting of a module's own - use UI.ColorPicker
-- (UIF_Pickers), which takes get/set and an alpha.
function UI.Swatch(parent, cat, key, onChange)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(30, 14)
    UI.Fill(sw, cat, key)
    UI.Border(sw, "ui", "border")
    sw._zPaint = PaintBox
    if UI._zSettings then
        -- EllesmereUI's swatch: 24 square, a white 1 px edge
        sw:SetSize(S.SWATCH, S.SWATCH)
        sw._zBorderCat, sw._zBorderKey, sw._zBorderAlpha = "text", "normal", 1
        sw._zPaint = function(self)
            PaintBox(self)
            for _, t in ipairs(self._zBorder) do t:SetVertexColor(1, 1, 1, self._zHot and 1 or 0.85) end
        end
        sw:HookScript("OnEnter", function(self) self._zHot = true self:_zPaint() end)
        sw:HookScript("OnLeave", function(self) self._zHot = nil self:_zPaint() end)
    end

    sw:SetScript("OnClick", function(self)
        local cur = GetColor(cat, key)
        local function Put(r, g, b)
            ns.SetColor(cat, key, r, g, b, cur.a)
            self:_zPaint()
            if onChange then onChange() end
            Changed("color")
        end
        UI.OpenColorPicker({ r = cur.r, g = cur.g, b = cur.b, a = cur.a,
            onChange = Put, onCancel = Put })
    end)
    sw:_zPaint()
    return sw
end

-- ============================================================
-- TOOLTIP
-- ============================================================
function UI.Tooltip(frame, title, body)
    -- kept on the frame for the settings search: what a tooltip says is
    -- found like any label on the page
    -- One hook per frame, reading what the last call set: a tooltip set
    -- again (a rebuilt page, a description moved into it) replaces the
    -- text instead of stacking a second one under it.
    frame._zTipTitle, frame._zTipBody = title, body
    if frame._zTipHooked then return end
    frame._zTipHooked = true
    frame:HookScript("OnEnter", function(self)
        -- greyed with a reason: the reason first (UIF_Pickers UI.ShowWhy)
        if self._zDisabled and self._zWhy and UI.ShowWhy then
            UI.ShowWhy(self, self._zTipTitle, self._zWhy, self._zTipBody)
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local t = GetColor("tooltip", "title")
        GameTooltip:AddLine(self._zTipTitle, t.r, t.g, t.b)
        if self._zTipBody then
            local c = GetColor("tooltip", "body")
            GameTooltip:AddLine(self._zTipBody, c.r, c.g, c.b, true)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ============================================================
-- WINDOW SHELL
-- ============================================================
-- Every ZacUI window - the config panel, both dialogs - is this shape:
-- flat fill, 1px border, 30px title bar with a gold hairline under it,
-- chromeless X on the right, drag by the bar, Escape closes.
-- ============================================================
-- RESIZE GRIP
-- ============================================================
-- Six dots in the bottom-right corner, the same handle Readycheck uses -
-- deliberately, so the two addons resize the same way and the gesture
-- transfers. It is drawn rather than textured because six 2px squares
-- scale honestly at any UI scale and a corner .tga does not.
--
-- The dots light up on hover. Without that they read as decoration:
-- a resize corner nobody discovers is a window nobody resizes.
local RESIZE_DOTS = { {2,2}, {6,2}, {10,2}, {6,6}, {10,6}, {10,10} }

-- ============================================================
-- HUD HANDLE
-- The controls a self-sizing on-screen frame gets: a strip just outside
-- one top corner, invisible until hovered, with a padlock that locks and
-- unlocks the frame and, while unlocked, a dotted grip that drags
-- sideways to resize it by SCALE (these frames lay themselves out, so a
-- width would be overwritten on the next refresh).
--   UI.HudHandle(frame, { getLocked, setLocked, getScale, setScale (live),
--       onScaleEnd (persist), minScale, maxScale, corner = "TOPRIGHT"|"TOPLEFT",
--       idleAlpha })
-- Returns the strip; strip.Refresh() repaints after a setting change.
-- ============================================================

function UI.HudHandle(frame, opts)
    opts = opts or {}
    local corner = opts.corner or "TOPRIGHT"
    local strip = CreateFrame("Frame", nil, UIParent)
    strip:SetSize(30, 12)
    strip:SetFrameStrata(frame:GetFrameStrata())
    strip:SetFrameLevel(frame:GetFrameLevel() + 5)
    strip:EnableMouse(true)
    frame:HookScript("OnShow", function() strip:Show() end)
    frame:HookScript("OnHide", function() strip:Hide() end)
    strip:SetShown(frame:IsShown())
    strip.idleAlpha = opts.idleAlpha or 0
    strip:SetAlpha(strip.idleAlpha)

    -- the padlock is drawn flat, in the same language as the dot grip: an
    -- 8x5 body with a shackle of three bars; unlocked, the shackle swings
    -- open (left leg gone, the rest shifted right)
    local lock = CreateFrame("Button", nil, strip)
    lock:SetSize(12, 12)
    local function Part(w, h)
        local t = lock:CreateTexture(nil, "ARTWORK")
        t._zui_own = true
        t:SetTexture(FLAT)
        t:SetSize(w, h)
        return t
    end
    local body, shL, shT, shR = Part(8, 5), Part(1.5, 4), Part(6, 1.5), Part(1.5, 4)
    body:SetPoint("BOTTOM", lock, "BOTTOM", 0, 1)
    lock.parts = { body, shL, shT, shR }
    local function Shape(locked)
        shL:ClearAllPoints() shT:ClearAllPoints() shR:ClearAllPoints()
        shL:SetShown(locked)
        shT:SetPoint("BOTTOM", body, "TOP", locked and 0 or 2, 2.5)
        shL:SetPoint("BOTTOMLEFT", shT, "BOTTOMLEFT", 0, -3)
        shR:SetPoint("BOTTOMRIGHT", shT, "BOTTOMRIGHT", 0, -3)
    end

    local grip = CreateFrame("Button", nil, strip)
    grip:SetSize(12, 12)
    grip.dots = {}
    for i, pos in ipairs({ { 1, 1 }, { 5, 1 }, { 9, 1 }, { 5, 5 }, { 9, 5 }, { 9, 9 } }) do
        local dot = grip:CreateTexture(nil, "ARTWORK")
        dot._zui_own = true
        dot:SetSize(2, 2)
        dot:SetPoint("BOTTOMLEFT", grip, "BOTTOMLEFT", pos[1], pos[2])
        grip.dots[i] = dot
    end

    local function Place()
        strip:ClearAllPoints()
        lock:ClearAllPoints()
        grip:ClearAllPoints()
        if corner == "TOPLEFT" then
            strip:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 1)
            lock:SetPoint("LEFT", strip, "LEFT", 0, 0)
            grip:SetPoint("LEFT", lock, "RIGHT", 3, 0)
        else
            strip:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 1)
            lock:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
            grip:SetPoint("RIGHT", lock, "LEFT", -3, 0)
        end
        strip:SetScale(frame:GetScale())
    end
    local function Paint()
        local locked = opts.getLocked and opts.getLocked() or false
        Shape(locked)
        local c = locked and GetColor("text", "gray") or GetColor("ui", "accent")
        for _, t in ipairs(lock.parts) do t:SetVertexColor(c.r, c.g, c.b, 1) end
        grip:SetShown(not locked and opts.setScale ~= nil)
        local g = GetColor("text", "gray")
        for _, d in ipairs(grip.dots) do d:SetColorTexture(g.r * 0.8, g.g * 0.8, g.b * 0.8, 0.9) end
        if not strip.hot then strip:SetAlpha(strip.idleAlpha) end
    end
    -- The handle shows while the mouse is over the frame or the strip and
    -- is gone otherwise. A locked frame has its mouse off, so OnEnter never
    -- fires for it: a light poll while the frame is shown reads IsMouseOver.
    local function Hover(on)
        if strip.hot == on then return end
        strip.hot = on
        strip:SetAlpha(on and 1 or strip.idleAlpha)
    end
    local poll, combatWait
    local Poll
    -- A locked frame in a fight has nothing to show on hover: the poll
    -- stops for the fight and comes back when it ends.
    local function WaitOutCombat()
        if not combatWait then
            combatWait = CreateFrame("Frame")
            combatWait:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if frame:IsShown() then Poll() end
            end)
        end
        combatWait:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    Poll = function()
        if poll then return end
        poll = C_Timer.NewTicker(0.15, function()
            if not frame:IsShown() then
                if poll then poll:Cancel() poll = nil end
                Hover(false)
                return
            end
            if InCombatLockdown() and grip.dragX == nil and opts.getLocked and opts.getLocked() then
                poll:Cancel() poll = nil
                Hover(false)
                WaitOutCombat()
                return
            end
            Hover(frame:IsMouseOver(4, -4, -4, 4) or strip:IsMouseOver(4, -4, -4, 4) or grip.dragX ~= nil)
        end)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(poll, "ui.hudhandle") end
    end
    frame:HookScript("OnShow", Poll)
    frame:HookScript("OnHide", function() if poll then poll:Cancel() poll = nil end Hover(false) end)
    if frame:IsShown() then Poll() end
    lock:SetScript("OnClick", function()
        local locked = not (opts.getLocked and opts.getLocked() or false)
        if opts.setLocked then opts.setLocked(locked) end
        Paint()
    end)
    lock:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local locked = opts.getLocked and opts.getLocked() or false
        GameTooltip:SetText(locked and "Locked" or "Unlocked", 1, 1, 1)
        GameTooltip:AddLine(locked and "Click to unlock: then drag the frame to move it, the dots to resize it."
            or "Drag the frame to move it, the dots to resize it. Click to lock.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    lock:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local minS, maxS = opts.minScale or 0.6, opts.maxScale or 1.6
    grip:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        local x = GetCursorPosition()
        self.dragX, self.dragScale = x, (opts.getScale and opts.getScale()) or frame:GetScale() or 1
        local a = GetColor("ui", "accent")
        for _, d in ipairs(self.dots) do d:SetColorTexture(a.r, a.g, a.b, 1) end
        self:SetScript("OnUpdate", function(g)
            local cx = GetCursorPosition()
            local dx = (cx - g.dragX) / (UIParent:GetEffectiveScale() or 1)
            if corner == "TOPLEFT" then dx = -dx end
            local sc = g.dragScale + dx / 160
            if sc < minS then sc = minS elseif sc > maxS then sc = maxS end
            sc = math.floor(sc * 100 + 0.5) / 100
            if sc ~= g.lastScale then
                g.lastScale = sc
                if opts.setScale then opts.setScale(sc) end
                strip:SetScale(frame:GetScale())
            end
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        self.dragX = nil
        if self.lastScale and opts.onScaleEnd then opts.onScaleEnd(self.lastScale) end
        self.lastScale = nil
        Paint()
    end)
    grip:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Resize", 1, 1, 1)
        GameTooltip:AddLine("Drag sideways.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    grip:HookScript("OnLeave", function() GameTooltip:Hide() end)

    strip.lock, strip.grip = lock, grip
    strip.Refresh = function() Place() Paint() end
    strip._zPaint = Paint
    strip.Refresh()
    return strip
end

function UI.AttachResizeGrip(frame, opts)
    opts = opts or {}
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(opts.minW or 200, opts.minH or 120,
                              opts.maxW or 1400, opts.maxH or 1000)
    elseif frame.SetMinResize then
        frame:SetMinResize(opts.minW or 200, opts.minH or 120)
        if frame.SetMaxResize then
            frame:SetMaxResize(opts.maxW or 1400, opts.maxH or 1000)
        end
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", 0, 0)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip.dots = {}

    local function Rest()
        local c = GetColor("text", "gray")
        for _, d in ipairs(grip.dots) do
            d:SetColorTexture(c.r * 0.7, c.g * 0.7, c.b * 0.7, 0.85)
        end
    end

    for i, pos in ipairs(RESIZE_DOTS) do
        local dot = grip:CreateTexture(nil, "ARTWORK")
        dot._zui_own = true
        dot:SetSize(2, 2)
        dot:SetPoint("BOTTOMLEFT", grip, "BOTTOMLEFT", pos[1], pos[2])
        grip.dots[i] = dot
    end
    Rest()

    grip:SetScript("OnEnter", function()
        local a = GetColor("ui", "accent")
        for _, d in ipairs(grip.dots) do d:SetColorTexture(a.r, a.g, a.b, 1) end
    end)
    grip:SetScript("OnLeave", Rest)
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        -- Reported AFTER the drag, not during. OnSizeChanged fires every
        -- frame of a resize, and rebuilding a page that often is a freeze.
        if opts.onResizeStopped then opts.onResizeStopped(frame) end
    end)

    grip._zPaint = Rest
    frame._zGrip = grip
    return grip
end

-- ============================================================
-- HEADER ART
-- ============================================================
-- The look every ZacUI title bar wears, applied to a bar frame of ANY
-- height (UI.Window, Kit.Cover, the Options chrome): a fill that runs
-- from the header colour into a dark wash of the accent, and a 2px
-- accent rule along the bottom that is raised under the title block,
-- drops through a short diagonal and runs flat to the right edge. The
-- fill is cut off at the rule - the strip under the raised part is
-- painted in the colour of whatever sits below it (the sidebar column on
-- the config window, the window itself elsewhere) and the wedge under the
-- diagonal in the window colour - so the gradient never shows below the
-- line. Colours are read in UI.PaintHeaderArt, so the editor restyles it.
--   opts.stepX   where the rule steps down (default 150)
--   opts.stepY   how far the left part is raised (default 5; the hero uses 5)
--   opts.left    palette {cat,key} under the raised part (default ui/windowBg)
-- The main-window header is one 38px line - the two-line 54px version
-- read as a banner rather than a title bar.
local HERO_H = 38
UI.HERO_H = HERO_H

local function Mix(a, b, t)
    return a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t
end

function UI.HeaderArt(bar, opts)
    opts = opts or {}
    local STEP_Y, STEP_W = opts.stepY or 4, 10
    local stepX = opts.stepX or 150
    if not bar._zFill then UI.Fill(bar, "ui", "headerBg") end
    local function Tex(layer, sub)
        local t = bar:CreateTexture(nil, layer or "ARTWORK", nil, sub or 4)
        t._zui_own = true
        t:SetTexture(FLAT)
        return t
    end
    -- the cut: what sits below the raised rule, painted over the fill
    local cutL = Tex("BACKGROUND", -6)
    cutL:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    cutL:SetPoint("TOPRIGHT", bar, "BOTTOMLEFT", stepX, STEP_Y)
    local cutD = Tex("BACKGROUND", -6)
    cutD:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", stepX, 0)
    cutD:SetPoint("TOPRIGHT", bar, "BOTTOMLEFT", stepX + STEP_W, STEP_Y)
    -- a quad with its top-right corner pulled down onto the bottom-right
    -- is the triangle under the diagonal
    if cutD.SetVertexOffset then cutD:SetVertexOffset(3, 0, -STEP_Y) end
    -- the rule
    -- 1px, like every other rule in the UI; the diagonal is the same strip
    -- turned, a hair longer so its ends meet the flat parts
    local ruleL, ruleR, ruleD = Tex(), Tex(), Tex()
    ruleL:SetHeight(1)
    ruleL:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, STEP_Y)
    ruleL:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", stepX, STEP_Y)
    ruleR:SetHeight(1)
    ruleR:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", stepX + STEP_W, 0)
    ruleR:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    ruleD:SetHeight(1)
    ruleD:SetWidth(math.sqrt(STEP_W * STEP_W + STEP_Y * STEP_Y) + 1)
    ruleD:SetPoint("CENTER", bar, "BOTTOMLEFT", stepX + STEP_W / 2, STEP_Y / 2 + 0.5)
    ruleD:SetRotation(-math.atan2(STEP_Y, STEP_W))
    bar._zArt = { cutL = cutL, cutD = cutD, rules = { ruleL, ruleR, ruleD },
                  left = opts.left or { "ui", "windowBg" } }
    UI.PaintHeaderArt(bar)
    -- every bar that wears this art gets the opening sheen; a header with
    -- a mark hands it to UI.AnimateMark (both are further down this file)
    if opts.anim ~= false and UI.AnimateBar then UI.AnimateBar(bar, { inset = STEP_Y + 1 }) end
end

function UI.PaintHeaderArt(bar)
    local art = bar._zArt
    if not art then return end
    local h = GetColor("ui", "headerBg")
    local a = GetColor("ui", "accent")
    local fill = bar._zFill
    -- the gradient's far end: the user's colour when they set one (the
    -- palette editor, ui > headerGradient), otherwise derived from the
    -- header colour and the accent so it follows an accent change
    local r2, g2, b2
    local own = ZacUIDB and ZacUIDB.palette and ZacUIDB.palette.ui and ZacUIDB.palette.ui.headerGradient
    if own then r2, g2, b2 = own.r, own.g, own.b else r2, g2, b2 = Mix(h, a, 0.4) end
    if CreateColor and fill.SetGradient then
        fill:SetVertexColor(1, 1, 1, 1)
        fill:SetGradient("HORIZONTAL", CreateColor(h.r, h.g, h.b, h.a or 1), CreateColor(r2, g2, b2, h.a or 1))
    elseif fill.SetGradientAlpha then
        fill:SetVertexColor(1, 1, 1, 1)
        fill:SetGradientAlpha("HORIZONTAL", h.r, h.g, h.b, h.a or 1, r2, g2, b2, h.a or 1)
    else
        fill:SetVertexColor(h.r, h.g, h.b, h.a or 1)
    end
    for _, t in ipairs(art.rules) do t:SetVertexColor(a.r, a.g, a.b, 0.8) end
    local l = GetColor(art.left[1], art.left[2])
    art.cutL:SetVertexColor(l.r, l.g, l.b, 1)
    local w = GetColor("ui", "windowBg")
    art.cutD:SetVertexColor(w.r, w.g, w.b, 1)
end

-- ============================================================
-- HERO HEADER
-- ============================================================
-- The tall title bar for an addon's MAIN window: the header art above at
-- 54px, the addon icon, the name in two tones (the second word in the
-- accent) with the version under it, and the plain X.
--   opts: first, second, version, icon, stepX, left, onClose

-- THE LIVING MARK. The addon mark in a main window's title bar is
-- animated, all of it with AnimationGroups - nothing runs in Lua per
-- frame, and nothing plays while the window is closed.
--
--   OPENING   once the window is really on screen the mark drops in from
--             double size; as it lands it does what it does on hover (the
--             turn, the ring, the four-point flare) and a slanted sheen
--             sweeps the bar
--   IDLE      every few seconds a small twinkle pops somewhere on the mark
--             (a different spot, size and wait each time),
--             and now and then the sheen crosses the bar again
--   HOVER     the mark makes one full turn, with the ring and the flare
--
-- UI.AnimateMark(icon, bar, opts)
--   icon       the mark's texture, already placed on `bar`
--   opts.inset pixels of the bar's bottom edge the sheen stays clear of
--   opts.idle  false = the opening and the hover only (pop-ups); the
--              sparkle and the returning sheen are left to main windows
--   opts.lead  seconds the drop waits once frames are flowing - set it to
--              the length of the window's own fade-in, if it has one
--
-- The scripts sit on a frame of this function's own. A window's OnShow
-- belongs to whoever builds the window - the config window SetScript()s
-- its own after the header exists, which silently dropped the hook the
-- first version of this put there, and the opening animation with it.
-- A child frame gets OnShow when its window appears, and nobody else
-- writes to this one.
local MARK_FLARE = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "markFlare"
local MARK_RING  = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "markRing"
local SHEEN_W, SHEEN_SLANT = 70, 14

-- HOW STRONG AND HOW OFTEN. One place to turn the whole thing up or down.
-- Every header gets the whole show every time it opens - main window or
-- pop-up, however soon after the last time. What must never happen is any
-- of it being left lit: see Light() and Sweep().
local FX = {
    sheen    = 0.26,    -- the band of light across the bar, at its brightest
    -- The light behind the mark is a burst: it comes up to these and fades
    -- out over half a second. Nothing is lit behind the mark at rest.
    flareIn  = 0.45,    -- as the mark lands: the four-point flare
    ringIn   = 0.55,    --   ...and the ring
    flareHit = 0.36,    -- under the mouse
    ringHit  = 0.46,
    spark    = 0.70,    -- the twinkle, on every header that has a mark
    -- THE BACKLIGHT: the ring and the four-point flare that sit behind the
    -- mark for as long as the window is open. Not a fixed glow - each
    -- breathes slowly between its two values, one way in `breath` seconds.
    ringRest  = { 0.50, 0.85 },
    flareRest = { 0.30, 0.60 },
    breath    = 2.4,
    pop      = 1,       -- a pop-up's share of the above (1 = same as a main window)
    lap      = 14,      -- seconds between returns of the sheen on a main window
    hitch    = 0.09,    -- a frame longer than this many seconds is a stall
    calm     = 3,       -- ordinary frames in a row before anything starts...
    wait     = 1.5,     -- ...but it starts anyway after this many seconds
}

-- Runs `go` once frames are flowing: FX.calm ordinary frames in a row.
-- The frame a window is shown in is a long one, and an auction house or a
-- mailbox opening behind a pop-up is several; anything started then has
-- run its course before it is drawn, or stands still half-way. `host` is
-- a frame of the caller's own - its OnUpdate is used and then taken off.
-- Frames that will not settle only delay it: after FX.wait seconds it
-- goes anyway. The show is never skipped.
local function WhenCalm(host, go)
    local calm, waited, ticks = 0, 0, 0
    host:SetScript("OnUpdate", function(self, dt)
        ticks = ticks + 1
        if ticks < 2 then return end      -- the first tick carries the show itself
        waited = waited + dt
        if dt <= FX.hitch then calm = calm + 1 else calm = 0 end
        if calm >= FX.calm or waited >= FX.wait or ticks >= 240 then
            self:SetScript("OnUpdate", nil)
            go()
        end
    end)
end

local function AnimScale(group, order, from, to, dur, smooth, delay)
    local a = group:CreateAnimation("Scale")
    a:SetOrder(order)
    -- the setters were renamed between client generations
    if a.SetScaleFrom then a:SetScaleFrom(from, from) a:SetScaleTo(to, to)
    elseif a.SetFromScale then a:SetFromScale(from, from) a:SetToScale(to, to)
    else a:SetScale(to / from, to / from) end
    a:SetDuration(dur)
    if smooth then a:SetSmoothing(smooth) end
    if delay then a:SetStartDelay(delay) end
    return a
end
local function AnimAlpha(group, order, from, to, dur, smooth, delay)
    local a = group:CreateAnimation("Alpha")
    a:SetOrder(order)
    a:SetFromAlpha(from) a:SetToAlpha(to)
    a:SetDuration(dur)
    if smooth then a:SetSmoothing(smooth) end
    if delay then a:SetStartDelay(delay) end
    return a
end
local function AnimTurn(group, order, degrees, dur, smooth, delay)
    local a = group:CreateAnimation("Rotation")
    a:SetOrder(order)
    a:SetDegrees(degrees)
    a:SetDuration(dur)
    if smooth then a:SetSmoothing(smooth) end
    if delay then a:SetStartDelay(delay) end
    return a
end

-- THE SHEEN, on its own: a soft slanted band of light that crosses a bar.
-- One per bar, made on first ask and shared by whoever animates that bar.
-- It is a frame inside a clipping frame the size of the bar, so it shows
-- only while it is over the bar.
local function Sheen(bar, inset)
    if bar._zSheen then return bar._zSheen end
    local clip = CreateFrame("Frame", nil, bar)
    clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, inset or 6)
    clip:SetFrameLevel(bar:GetFrameLevel() + 6)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    local band = CreateFrame("Frame", nil, clip)
    band:SetPoint("TOPLEFT", clip, "TOPLEFT", -(SHEEN_W + SHEEN_SLANT), 0)
    band:SetPoint("BOTTOMLEFT", clip, "BOTTOMLEFT", -(SHEEN_W + SHEEN_SLANT), 0)
    band:SetWidth(SHEEN_W)
    band:SetAlpha(0)
    local halves = {}
    local function Half(fromA, toA, p1, p2)
        local t = band:CreateTexture(nil, "OVERLAY")
        t._zui_own = true
        t:SetTexture(FLAT)
        t:SetBlendMode("ADD")
        t:SetPoint("TOPLEFT", band, p1, 0, 0)
        t:SetPoint("BOTTOMRIGHT", band, p2, 0, 0)
        -- lean it: both top corners pushed right
        if t.SetVertexOffset then
            t:SetVertexOffset(1, SHEEN_SLANT, 0)
            t:SetVertexOffset(3, SHEEN_SLANT, 0)
        end
        halves[#halves + 1] = { tex = t, from = fromA, to = toA }
    end
    Half(0, 1, "TOPLEFT", "BOTTOM")
    Half(1, 0, "TOP", "BOTTOMRIGHT")
    -- 1 on a main window, FX.pop on a pop-up (SetLevel, below)
    local level = 1

    -- ONE group with ONE animation on the band: the slide. The band is
    -- switched on for the length of a sweep and off again after it; its
    -- alpha is never animated, nothing else ever plays on it, and a sweep
    -- is never started from inside another animation's callback. (The
    -- first build ran an entrance group and a looping idle group on the
    -- band at once, each with an alpha step, and the sweep on opening
    -- came and went with whichever the client applied last.)
    local sweep = band:CreateAnimationGroup()
    local slide = sweep:CreateAnimation("Translation")
    slide:SetOrder(1) slide:SetDuration(0.8) slide:SetSmoothing("IN_OUT")
    -- `turn` counts sweeps, so the watchdog in Sweep only ever acts on
    -- the sweep that set it
    local turn = 0
    local function Off()
        turn = turn + 1
        band:SetAlpha(0)
        band:SetScript("OnUpdate", nil)
    end
    sweep:SetScript("OnFinished", Off)
    sweep:SetScript("OnStop", Off)

    -- the band travels the bar's width, whatever that is right now
    local function Span()
        local w = bar:GetWidth()
        if not w or w < 50 then w = 600 end
        slide:SetOffset(w + SHEEN_W + SHEEN_SLANT * 2, 0)
    end
    clip:SetScript("OnSizeChanged", Span)

    -- the light's colour, re-read on every sweep so a palette change shows
    local function Tint()
        local w = { r = 1, g = 1, b = 1 }
        local k = FX.sheen * level
        for _, h in ipairs(halves) do
            if CreateColor and h.tex.SetGradient then
                h.tex:SetGradient("HORIZONTAL", CreateColor(w.r, w.g, w.b, h.from * k), CreateColor(w.r, w.g, w.b, h.to * k))
            else
                h.tex:SetVertexColor(w.r, w.g, w.b, k * 0.5)
            end
        end
    end
    Tint()

    -- A sweep is 0.8s of smooth motion or it is nothing. A stalled frame
    -- in the middle of one (something heavy loading behind the window)
    -- leaves the band standing still on the bar - so while it is lit the
    -- band watches its own frames and goes dark on the first long one,
    -- and whatever else happens it is dark a moment after a sweep should
    -- have ended.
    local function Sweep()
        Tint()
        Span()
        sweep:Stop()
        Off()
        local mine, ticks = turn, 0
        band:SetAlpha(1)
        band:SetScript("OnUpdate", function(_, dt)
            ticks = ticks + 1
            if ticks > 1 and dt > FX.hitch then
                sweep:Stop()
                Off()
            end
        end)
        sweep:Play()
        C_Timer.After(1.3, function()
            if turn == mine then
                sweep:Stop()
                Off()
            end
        end)
    end

    -- THE RETURN, for a main window: a clock on the clipping frame (an
    -- alpha step from 1 to 1 - nothing to see) that sweeps on every lap.
    local clock = clip:CreateAnimationGroup()
    clock:SetLooping("REPEAT")
    local lap = clock:CreateAnimation("Alpha")
    lap:SetFromAlpha(1) lap:SetToAlpha(1) lap:SetDuration(FX.lap)
    clock:SetScript("OnLoop", function() Sweep() end)

    local s = { clip = clip, band = band, sweep = sweep, clock = clock, Span = Span, Tint = Tint, Sweep = Sweep }
    function s.StartIdle() clock:Stop() clock:Play() end
    function s.SetLevel(k) level = k end
    function s.Stop()
        clock:Stop()
        sweep:Stop()
        Off()
    end
    bar._zSheen = s
    return s
end

-- THE OPENING SHEEN FOR ANY BAR. Every window and dialog that wears the
-- header art gets this (the header-art helper calls it): when the window
-- appears, the sheen crosses its title bar once. No idle loop - that is
-- for the main window - and nothing plays while the window is closed.
-- A header that also has a mark hands its sheen to AnimateMark, which
-- times it to the mark's landing; `auto` goes false and this stands down.
-- Like the mark, it waits for the first ordinary frame: the frame a
-- window is shown in is a long one and would swallow the sweep.
function UI.AnimateBar(bar, opts)
    if not (bar and bar.CreateTexture) then return end
    opts = opts or {}
    local sheen = Sheen(bar, opts.inset)
    if sheen.wired then return sheen end
    sheen.wired = true
    if sheen.auto == nil then sheen.auto = true end
    sheen.SetLevel(FX.pop)      -- a bar on its own is a pop-up's
    local clip = sheen.clip
    local function Stop()
        clip:SetScript("OnUpdate", nil)
        sheen.Stop()
    end
    local function Play()
        if not sheen.auto then return end
        Stop()
        WhenCalm(clip, function()
            if sheen.auto then sheen.Sweep() end
        end)
    end
    clip:SetScript("OnShow", Play)
    clip:SetScript("OnHide", function() if sheen.auto then Stop() end end)
    if clip:IsVisible() then Play() end
    return sheen
end

function UI.AnimateMark(icon, bar, opts)
    if not (icon and bar and icon.CreateAnimationGroup) or icon._zMark then return end
    opts = opts or {}
    local size = icon:GetWidth()
    if not size or size < 8 then size = 20 end

    -- everything drawn here lives on one frame above the bar's own art
    local fx = CreateFrame("Frame", nil, bar)
    fx:SetAllPoints(icon)
    fx:SetFrameLevel(bar:GetFrameLevel() + 10)
    -- ...and the mark itself moves onto a frame one above that, so the
    -- light is BEHIND the mark and never across it. (It used to be drawn
    -- over the mark, and no amount of turning it down kept the mark clear.)
    local front = CreateFrame("Frame", nil, bar)
    front:SetAllPoints(bar)
    front:SetFrameLevel(bar:GetFrameLevel() + 11)
    icon:SetParent(front)

    local function Glow(tex, scale, point, x, y)
        local t = fx:CreateTexture(nil, "OVERLAY", nil, 7)
        t._zui_own = true
        t:SetTexture(tex)
        t:SetBlendMode("ADD")
        t:SetSize(size * scale, size * scale)
        t:SetPoint("CENTER", icon, point or "CENTER", x or 0, y or 0)
        t:SetAlpha(0)
        return t
    end
    -- the backlight (made first, so the bursts draw over it)
    local flareRest = Glow(MARK_FLARE, 3.0)
    local ringRest = Glow(MARK_RING, 1.4)
    -- the bursts
    local flare = Glow(MARK_FLARE, 3.0)
    local ring = Glow(MARK_RING, 1.4)
    local spark = Glow(MARK_FLARE, 1.5, "TOPRIGHT", -2, -2)

    -- one burst = the texture appears at full strength, then grows, turns
    -- and fades together. Every animation in a burst runs the same length,
    -- so none of them is left holding a finished value.
    -- `peak` is how strong the light is at its brightest - kept low: it
    -- is an accent behind the mark, not a flashbulb. It fades evenly from
    -- the first frame rather than lingering at peak.
    --
    -- LIT ONLY WHILE IT PLAYS. An alpha animation does not leave a texture
    -- at its last value: when it ends the texture is back at its OWN alpha.
    -- So each of these textures is held at 0, raised to 1 by Light() for
    -- the length of one animation, and put back to 0 the moment that
    -- animation ends or is stopped. `lit` remembers which animation holds a
    -- texture, so the end of an older one cannot darken a newer one.
    -- (They used to be left at 1: every burst was followed by the flare and
    -- the ring standing behind the mark at full strength until the window
    -- closed, and on a pop-up the twinkle sat still at the corner. Then
    -- they were held at 0 and never raised, and nothing showed at all.)
    local lit = {}
    local function Dark(tex, g)
        if g and lit[tex] ~= g then return end
        lit[tex] = nil
        tex:SetAlpha(0)
    end
    local function Light(tex, g)
        lit[tex] = g
        tex:SetAlpha(1)
        g:Play()
    end
    local function Burst(tex, peak, fromS, toS, dur, degrees)
        local g = tex:CreateAnimationGroup()
        AnimAlpha(g, 1, peak, 0, dur)
        AnimScale(g, 1, fromS, toS, dur, "OUT")
        if degrees then AnimTurn(g, 1, degrees, dur, "OUT") end
        g:SetScript("OnFinished", function() Dark(tex, g) end)
        g:SetScript("OnStop", function() Dark(tex, g) end)
        return g
    end
    -- the landing bursts (the bigger pair) and the hover bursts
    -- THE BACKLIGHT behind the mark while the window is open: the same
    -- ring and flare, at rest size, breathing. A bounce between two alphas
    -- that never ends, so it is never a still picture and never "over" -
    -- there is no last value for it to be left at. Lit by Light() like the
    -- bursts, dark the moment the window closes.
    local function Breath(tex, range)
        local g = tex:CreateAnimationGroup()
        g:SetLooping("BOUNCE")
        AnimAlpha(g, 1, range[1], range[2], FX.breath, "IN_OUT")
        g:SetScript("OnStop", function() Dark(tex, g) end)
        return g
    end
    local ringBreath = Breath(ringRest, FX.ringRest)
    local flareBreath = Breath(flareRest, FX.flareRest)

    -- strengths from FX; a pop-up's mark gets FX.pop of them
    local K = (opts.idle ~= false) and 1 or FX.pop
    local flareIn  = Burst(flare, FX.flareIn * K,  0.25, 1.25, 0.65, 110)
    local ringIn   = Burst(ring,  FX.ringIn * K,   0.6,  2.8,  0.50)
    local flareHit = Burst(flare, FX.flareHit * K, 0.25, 1.0,  0.50, 90)
    local ringHit  = Burst(ring,  FX.ringHit * K,  0.6,  2.4,  0.45)

    -- the drop: held unseen for the lead (a window that fades in gets a
    -- longer one), then down from double size onto its place. One group,
    -- two steps, so no frame falls between them; the mark's own alpha is
    -- 0 for the whole of it and the landing puts it back.
    local LEAD = opts.lead or 0.04
    -- the idle sparkle and the returning sheen are for a main window; a
    -- pop-up passes idle = false and gets the opening only
    local IDLE = opts.idle ~= false
    local markIn = icon:CreateAnimationGroup()
    AnimAlpha(markIn, 1, 0, 0, LEAD)
    AnimAlpha(markIn, 2, 0, 1, 0.26, "OUT")
    AnimScale(markIn, 2, 2.2, 1, 0.26, "IN")

    -- hover, and the landing: one full turn. There was a second choice, a
    -- "pop" (grow, then shrink, as two scale steps in a row); Readycheck's
    -- mark wore it, it looked wrong in game beside this one, and it is
    -- gone. One animation, one step.
    local markHit = icon:CreateAnimationGroup()
    AnimTurn(markHit, 1, -360, 0.5, "IN_OUT")

    -- THE IDLE TWINKLE: a wait, then a small burst - and each one somewhere
    -- else. Not a looping group (a loop would twinkle on the same spot at
    -- the same beat for ever): one pass, and its finish picks a new place
    -- on the mark, a new size and a new wait, and plays it again.
    local sparkOn = false
    local sparkIdle = spark:CreateAnimationGroup()
    local sparkWait = AnimAlpha(sparkIdle, 1, 0, 0, 6.5)
    AnimAlpha(sparkIdle, 2, FX.spark, 0, 0.7, "IN")
    AnimScale(sparkIdle, 2, 0.2, 1, 0.7, "OUT")
    AnimTurn(sparkIdle, 2, 90, 0.7, "OUT")
    local function PlaceSpark()
        -- anywhere on the mark from near its middle out to just past its
        -- edge, at any angle
        local angle = math.random() * 2 * math.pi
        local reach = size * (0.15 + math.random() * 0.50)
        local s = size * (1.0 + math.random() * 0.8)
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", icon, "CENTER", math.cos(angle) * reach, math.sin(angle) * reach)
        spark:SetSize(s, s)
        sparkWait:SetDuration(3.5 + math.random() * 5)
    end
    sparkIdle:SetScript("OnFinished", function()
        if not sparkOn then
            Dark(spark, sparkIdle)
            return
        end
        PlaceSpark()
        Light(spark, sparkIdle)
    end)
    sparkIdle:SetScript("OnStop", function() Dark(spark, sparkIdle) end)

    -- the bar's sheen is shared with AnimateBar; from here the mark runs
    -- it, timed to the landing
    local sheen = Sheen(bar, opts.inset)
    sheen.auto = false
    sheen.clip:SetScript("OnUpdate", nil)
    sheen.SetLevel(K)

    -- COLOUR ONLY. A texture's vertex colour carries its alpha, so after
    -- tinting each is put straight back to what Light()/Dark() last said.
    local function Paint(tex, r, g, b)
        tex:SetVertexColor(r, g, b, 1)
        tex:SetAlpha(lit[tex] and 1 or 0)
    end
    local function Tint()
        local a = GetColor("ui", "accent")
        Paint(flare, a.r, a.g, a.b)
        Paint(ring, a.r, a.g, a.b)
        Paint(flareRest, a.r, a.g, a.b)
        Paint(ringRest, a.r, a.g, a.b)
        Paint(spark, 1, 1, 1)
        sheen.Tint()
    end

    -- the twinkle runs on every header that has a mark - main window or
    -- pop-up - for as long as it is open
    local function StartTwinkle()
        if not fx:IsVisible() then return end
        sparkOn = true
        PlaceSpark()
        Light(spark, sparkIdle)
    end

    local groups = { flareIn, ringIn, flareHit, ringHit, markIn, markHit, sparkIdle, ringBreath, flareBreath }
    local waiting, armed, run = false, false, 0
    local function StopAll()
        waiting, armed = false, false
        sparkOn = false
        run = run + 1
        fx:SetScript("OnUpdate", nil)
        for _, g in ipairs(groups) do g:Stop() end
        -- whatever the stops did or did not report, nothing stays lit
        Dark(flare) Dark(ring) Dark(spark) Dark(flareRest) Dark(ringRest)
        sheen.Stop()
        icon:SetAlpha(1)
    end

    -- THE LANDING: exactly what the mouse gets on hover - the turn, with
    -- the ring and the flare - plus the sheen across the bar.
    -- The idle loops start counting from here.
    local function Land()
        if not armed then return end
        armed = false
        icon:SetAlpha(1)
        if not fx:IsVisible() then return end
        markHit:Play()
        Light(ring, ringIn)
        Light(flare, flareIn)
        -- the backlight comes up under the burst and stays
        Light(ringRest, ringBreath)
        Light(flareRest, flareBreath)
        StartTwinkle()
        -- the sheen goes a beat later, and from a timer rather than
        -- from inside the drop's own finish callback
        local mine = run
        C_Timer.After(0.05, function()
            if run ~= mine or not fx:IsVisible() then return end
            sheen.Sweep()
            if IDLE then sheen.StartIdle() end
        end)
    end
    markIn:SetScript("OnFinished", Land)

    -- THE OPENING. It must not start the moment the window is shown. The
    -- frame a window is built or shown in is a long one, the next frame's
    -- clock carries that whole pause, and an animation started here has
    -- run its course before anything is drawn. So the mark is held unseen
    -- and the drop waits for the first ordinary frame: a few frames of
    -- OnUpdate, then the script takes itself off.
    local function PlayIn()
        StopAll()
        Tint()
        icon:SetAlpha(0)
        waiting = true
        local mine = run
        WhenCalm(fx, function()
            waiting = false
            armed = true
            markIn:Play()
            -- the mark must never be left unseen: if the drop's finish
            -- does not arrive, land anyway
            C_Timer.After(LEAD + 1, function()
                if run == mine and armed then Land() end
            end)
        end)
    end
    local function PlayHit()
        if waiting or armed or markHit:IsPlaying() or markIn:IsPlaying() then return end
        flareIn:Stop() ringIn:Stop() flareHit:Stop() ringHit:Stop()
        Tint()
        markHit:Play()
        Light(ring, ringHit)
        Light(flare, flareHit)
    end

    fx:SetScript("OnShow", PlayIn)
    fx:SetScript("OnHide", StopAll)
    fx:SetScript("OnEnter", PlayHit)
    -- the mark listens for the mouse crossing it and lets clicks through,
    -- so dragging the bar from the mark is still the bar's own drag
    if fx.SetMouseMotionEnabled and fx.SetMouseClickEnabled then
        fx:SetMouseMotionEnabled(true)
        fx:SetMouseClickEnabled(false)
    else
        fx:EnableMouse(true)
        fx:RegisterForDrag("LeftButton")
        fx:SetScript("OnDragStart", function()
            local h = bar:GetScript("OnDragStart")
            if h then h(bar) end
        end)
        fx:SetScript("OnDragStop", function()
            local h = bar:GetScript("OnDragStop")
            if h then h(bar) end
        end)
    end

    icon._zMark = { PlayIn = PlayIn, PlayHit = PlayHit, StopAll = StopAll, fx = fx }
    -- a window built already on screen never fires OnShow for this
    if fx:IsVisible() then PlayIn() end
    return icon._zMark
end

function UI.HeroHeader(parent, opts)
    opts = opts or {}
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(HERO_H)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    UI.Fill(bar, "ui", "headerBg")
    UI.HeaderArt(bar, { stepX = opts.stepX or 250, stepY = 5, left = opts.left })

    local icon = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    icon._zui_own = true
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 12, 2)
    icon:SetTexture(opts.icon or ns.TEX_ICON)
    SharpenIcon(icon)
    UI.AnimateMark(icon, bar, { inset = 6 })

    local first = UI.Font(bar, 16, { text = opts.first or "", cat = "text", key = "normal" })
    first:SetPoint("LEFT", icon, "RIGHT", 8, 1)
    local second = UI.Font(bar, 16, { text = opts.second or "", cat = "ui", key = "accent" })
    second:SetPoint("LEFT", first, "RIGHT", -1, 0)
    -- the version hugs the name on the same line, a step down to share a baseline
    local version = UI.Font(bar, F.SMALL, { text = opts.version or "", cat = "text", key = "gray" })
    version:SetPoint("LEFT", second, "RIGHT", 4, -2)

    local close = UI.CloseX(bar, 20, opts.onClose)
    close:SetPoint("RIGHT", -8, 1)

    bar._zPaint = function(self)
        UI.PaintHeaderArt(self)
        first:_zPaint() second:_zPaint() version:_zPaint()
        close:_zPaint()
    end
    bar:_zPaint()

    bar.icon, bar.first, bar.second, bar.version, bar.closeButton = icon, first, second, version, close
    return bar
end

function UI.Window(name, width, height, title, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:Hide()
    -- 0.97, matching the skinned Blizzard panels - windows built by
    -- ZacUI and windows ZacUI skins must not read as two families.
    UI.Fill(f, "ui", "windowBg", 0.97)
    UI.Border(f, "ui", "border")
    f._zPaint = PaintBox
    f:_zPaint()
    if name then tinsert(UISpecialFrames, name) end
    f:SetScript("OnMouseDown", function(self) self:Raise() end)

    -- THE SETTINGS WINDOW (opts.bare, UI.S): EllesmereUI's shell - no
    -- title bar; the window's colour, a white 0.05 edge, the whole window
    -- a drag surface (f.titleBar spans it: the caller's chrome sits on
    -- it), a 40 px close box 14 in and 11 down.
    if opts.bare then
        f._zSet = true
        f._zPaint = function(self)
            local c = S.BG
            self._zFill:SetVertexColor(c.r, c.g, c.b, 1)
            for _, t in ipairs(self._zBorder) do t:SetVertexColor(1, 1, 1, S.BORDER_A) end
        end
        f:_zPaint()
        local bar = CreateFrame("Frame", nil, f)
        bar:SetAllPoints(f)
        bar:SetFrameLevel(f:GetFrameLevel() + 1)
        bar:EnableMouse(true)
        bar:RegisterForDrag("LeftButton")
        bar:SetScript("OnDragStart", function() f:StartMoving() end)
        bar:SetScript("OnDragStop", function()
            f:StopMovingOrSizing()
            if f._zOnMoved then f._zOnMoved() end
        end)
        local close = UI.CloseX(bar, 40, function() UI.CloseWindow(f) end)
        close._zSet = true
        close._zA:SetSize(38, 38)
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -11)
        close:SetFrameLevel(f:GetFrameLevel() + 30)
        close:_zPaint()
        f.titleBar, f.titleText, f.closeButton, f.headerHeight = bar, nil, close, 0
        return f
    end

    -- A main window asks for the hero header (opts.hero); everything else
    -- gets the plain 30px bar. Either way f.headerHeight says how tall.
    if opts.hero then
        local hero = opts.hero
        hero.onClose = function() UI.CloseWindow(f) end
        local bar = UI.HeroHeader(f, hero)
        bar:EnableMouse(true)
        bar:RegisterForDrag("LeftButton")
        bar:SetScript("OnDragStart", function() f:StartMoving() end)
        bar:SetScript("OnDragStop", function()
            f:StopMovingOrSizing()
            if f._zOnMoved then f._zOnMoved() end
        end)
        f.titleBar, f.titleText, f.closeButton, f.headerHeight = bar, bar.first, bar.closeButton, HERO_H
        return f
    end
    f.headerHeight = M.TITLEBAR

    local bar = CreateFrame("Frame", nil, f)
    bar:SetHeight(M.TITLEBAR)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    -- FLAT header, like every other surface. The old "bar" fill put the
    -- statusbar gradient texture here, which made ZacUI's own windows
    -- the only textured headers in the whole UI.
    UI.Fill(bar, "ui", "headerBg")
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if f._zOnMoved then f._zOnMoved() end
    end)

    -- the same header art as the main window, at bar height
    UI.HeaderArt(bar, { stepX = opts.stepX or 150, left = opts.left })

    local icon = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    icon._zui_own = true
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 9, 2)
    icon:SetTexture(ns.TEX_ICON)
    SharpenIcon(icon)
    -- pop-ups get the opening (drop, turn, ring, flare, sheen) and the
    -- hover; the idle sparkle and returning sheen stay on the main window
    UI.AnimateMark(icon, bar, { idle = false })

    local label = UI.Font(bar, F.TITLE, { text = title, cat = "text", key = "gold" })
    label:SetPoint("LEFT", icon, "RIGHT", 8, 2)

    bar._zPaint = function(self)
        UI.PaintHeaderArt(self)
        label:_zPaint()
    end
    bar:_zPaint()

    local close = UI.CloseX(bar, 22, function() UI.CloseWindow(f) end)
    close:SetPoint("RIGHT", -5, 0)

    f.titleBar, f.titleText, f.closeButton = bar, label, close
    return f
end

function UI.OpenWindow(f)
    -- PopOut leaves the frame SHOWN for its whole duration and hides it in
    -- the completion callback, so a bare IsShown() check swallows a reopen
    -- that lands mid-close - click the X, type /zui, and nothing happens.
    -- An in-flight animation means "not settled", not "already open".
    if f:IsShown() and not f._zAnim then return end
    ns.StopAnim(f)
    ns.PopIn(f, 0.15)
end

function UI.CloseWindow(f)
    PopOut(f, 0.1)
end

UI.M, UI.F = M, F
UI.Repaint = Repaint
UI.PaintBox = PaintBox

-- shared with later ZacUI files
ns.UI = UI
