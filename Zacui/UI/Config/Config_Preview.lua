-- Config_Preview - the preview strip: a short band pinned under the page's
-- header that shows a live sample of what the current page sets up.
-- Part of ZacUI; load order is set by the TOC (after Config_Base, before
-- Config_Window, which hosts it).
--
-- A PAGE ASKS FOR ONE inside its builder:
--
--   L:Preview({
--       key = "unitframes.player",    -- unique; one canvas per key, kept
--       title = "Player frame",
--       width = 260, height = 60,     -- the canvas at the real size (update may P.Resize it)
--       build = function(canvas, P) end,   -- ONCE per key: make the samples
--       update = function(canvas, P) end,  -- read the settings, restyle them
--       replay = function(canvas, P) end,  -- optional: play the animations again
--       modes = { { id = "player", label = "Player" }, ... },  -- optional; P.mode
--       controls = function(row, P) end,   -- optional: extra controls, built once
--   })
--
-- and that is all it does. The strip shows while the page on screen asked
-- for one and is not there on any page that did not. It sits under the
-- page's title, the full width of the page, and stays put while the page
-- scrolls under it; the window never changes size for it.
--
-- THE SAMPLE IS THE REAL THING, AT ITS REAL SIZE: the canvas is drawn at
-- the game's scale (UIParent's over the window's, times spec.gameScale(P)
-- for a feature scale the sample does not apply itself), and the strip
-- grows to fit it: the controls line, the sample, a small margin, at
-- least 56 px and at most a cap - Compact / Normal / Tall = 15% / 22% /
-- 34% of the content pane's height (Normal unless picked; Zac 2026-11-02:
-- the old 30/45/65 ate too much of the page). Only a sample
-- bigger than the cap, or wider than the strip, is scaled down, uniformly,
-- and the control line then says "Scaled to 72%". spec.overflow = "clip"
-- (or a function(P) per mode) keeps a long sample at its real size and
-- shows its top part instead. Folded, the strip is a slim 18 px bar.
--
-- The controls run along the strip's top edge so the sample keeps the
-- middle: the mode pills on the left (squeezed, then a small menu when
-- they do not fit), the page's own controls after them (or behind a
-- "More" button), and on the right the background swatches, Replay, the
-- strip's height and the fold.
--
-- EVERY CHANGE SHOWS UP ON ITS OWN. Every ZacUI widget raises
-- ns.SettingsChanged() (UIF_Settings) after its callback, a slider on
-- every step of a drag; the strip listens and runs the current page's
-- update once on the next frame, no matter how many changes landed in
-- this one. A page rebuild asks the same way, so a checkbox that both
-- changes a value and rebuilds the page still costs ONE update, and the
-- canvas is never rebuilt - build runs once per key per session.
--
-- P, handed to every callback, belongs to the key and outlives rebuilds:
--   P.key, P.mode (the chosen mode id, or nil), P.bg, P.scale (the
--   canvas's scale), P.real (the game's scale it is drawn at), P.fit (the
--   share of that it shows at: 1 = real size), P.clipped (only its top
--   part shows), P.store (a table for the page's own things), P.Update()
--   (ask for an update), P.Replay().
-- build runs once, so it must not read settings into upvalues it keeps:
-- whatever depends on a setting is done in update.
--
-- HELPERS FOR LAYING THE SAMPLE OUT AT ITS REAL SIZE:
--   P.boxW, P.boxH   the room under the cap, in canvas units at the real
--                    size (nil in the very first build)
--   P.Resize(w, h)   the canvas is the sample's box: the strip re-lays at
--                    once (kept for the key across rebuilds)
--   P.Row(parts, o)  places frames left to right, centred in the canvas,
--                    o.gap apart (default 10), at o.y; parts may be
--                    { frame =, w =, h =, dy = } to give a size. With
--                    o.fit the canvas becomes the row's box plus o.pad
--                    (default 4), at least o.minW x o.minH. Hidden parts
--                    are skipped; a part mid-animation is stopped before
--                    it moves. Returns the row's width and height.
--   P.Measure(root)  the box of everything visible under root: its centre
--                    relative to root's centre, and its size, in root's
--                    units (nil while the game has not placed it yet; the
--                    strip then updates once more on the next frame).
--                    For samples whose extent the settings decide.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local ConfigLayout = ns.ConfigLayout
local ConfigState = ns.ConfigState
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Print = ns.Print
local UI = ns.UI

local M, F = UI.M, UI.F

local Preview = {}
-- the mouse wheel over the sample zooms it (Zac, 2026-11-08): a factor on
-- the fitted scale, for this session; back to 100% by wheeling back
Preview.zoom = 1
-- and a drag on the sample's empty space (left or middle button) moves it
-- about, in the box's own units; back at 100% it re-centres
Preview.panX, Preview.panY = 0, 0
Preview.stats = { updates = 0, builds = 0, replays = 0 }

-- THE STRIP GROWS TO FIT ITS SAMPLE, up to a cap: a share of the
-- content pane's height. Compact / Normal / Tall pick the cap (the saved
-- key is the one the old Small / Normal / Tall used; "small" reads as
-- Compact). Under the cap the sample shows at its real, in-game size;
-- only a sample bigger than the cap (or wider than the strip) is scaled
-- down, and the strip says so.
local CAPS = { compact = 0.15, normal = 0.22, tall = 0.34 }
local HEIGHT_ORDER = { "compact", "normal", "tall" }
local HEIGHT_NAME = { compact = "Compact", normal = "Normal", tall = "Tall" }
local OLD_HEIGHT = { small = "compact" }
local MIN_H = 56              -- the shortest open strip
local SLIM_H = 18             -- folded
local EDGE = 4                -- strip edge -> its contents
local BAR_Y, BTN_H = 3, 16    -- the control line along the top edge
local VIEW_Y = BAR_Y + BTN_H + 3
local BOX_PAD = 4             -- the sample box -> the sample (2 a side)
-- STEADY, NOT TWITCHY (2026-11-03, Zac: "some of the previews flash/
-- flicker"). A sample that measures itself can come out a pixel bigger,
-- then a pixel smaller, then bigger again (rounding, a scale applied in
-- between); every such step used to re-lay the strip - a new height, a
-- new scale for the canvas - and re-place the samples, stopping whatever
-- they were playing. Now:
--   * the strip only gets shorter when it is more than SHRINK_SLACK px
--     shorter (taller always applies, and never past the cap), and a
--     width that moved by less than a pixel is the same width;
--   * a canvas asked to be a pixel smaller keeps its size (bigger always
--     applies);
--   * samples are only re-placed (and stopped) when they move by more
--     than PLACE_SLACK px;
--   * an update does not stop an animation the replay started unless it
--     really moves, resizes, rescales or re-fades that frame.
local SHRINK_SLACK = 2
local PLACE_SLACK = 0.5
local ICON = 16               -- Replay / height / fold
local SW = 11                 -- a background swatch
local GAP = 3
local RIGHT_W = 3 * ICON + 2 * 2 + 8 + 3 * SW + 2 * GAP   -- the right-hand cluster
local CELL = 8                -- the checker background's square

local window, host, dock, bar, view, label, slim, sizeNote, labelHit
-- slot: a place on the control line, left of the swatches, for what a
-- page's sample adds there (the drag layer's Layout button); clusterLeft:
-- the leftmost swatch (the cluster's real left edge)
local slot, clusterLeft
local foldBtn, foldArrow, heightBtn, replayBtn
local swatches, rightItems = {}, {}
local entries = {}        -- key -> { key, spec, canvas, P, built, row }
local current             -- the entry on show
local declared, collecting = nil, false
local shownKey            -- what has been on show since the strip last hid
local pending = false
local complained = {}

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- THE REAL SIZE. A sample is drawn at the scale the live frame would
-- have in game: UIParent's effective scale over the settings window's
-- (the window has its own scale, 100% and up), times the feature's own
-- scale when the page asks for it (spec.gameScale(P), for a scale the
-- sample does not apply itself). A 36 px button looks 36 px on screen,
-- next to the real one.
local function RealScale(e)
    local ref = view or window
    local vs = ref and ref.GetEffectiveScale and ref:GetEffectiveScale() or 1
    local us = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not (vs and vs > 0) then vs = 1 end
    -- the window's resting scale, not where its opening pop is right now
    local ws = window and window.GetScale and window:GetScale()
    if ws and ws > 0 and window._zPopBase then vs = vs / ws * window._zPopBase end
    local k = 1
    if e and e.spec and type(e.spec.gameScale) == "function" then
        local ok, v = pcall(e.spec.gameScale, e.P)
        if ok and type(v) == "number" and v > 0 then k = v end
    end
    return (us or 1) / vs * k
end
Preview.RealScale = RealScale

local function CanvasSize(e)
    local spec = e.spec or {}
    return math.max(1, spec.width or 240), math.max(1, spec.height or 120)
end

-- Account-wide window state (ZacUIDB.config). The column-era keys (the
-- sample size and the dragged width) mean nothing to the strip.
local function Store()
    local s = ConfigState()
    s.preview = s.preview or {}
    local p = s.preview
    p.modes = p.modes or {}
    p.size, p.w = nil, nil
    return p
end

-- (an old "small" reads as Compact; nothing is rewritten until a pick)
local function HeightId()
    local id = Store().height
    id = OLD_HEIGHT[id] or id
    return CAPS[id] and id or "normal"
end

local function Fail(e, what, err)
    local k = (e and e.key or "?") .. "/" .. what
    if complained[k] then return end
    complained[k] = true
    Print("preview '" .. tostring(e and e.key) .. "' " .. what .. " failed: " .. tostring(err))
end

local function ModeOf(e)
    local modes = e.spec and e.spec.modes
    if type(modes) ~= "table" or #modes == 0 then return nil end
    local saved = Store().modes[e.key]
    for _, m in ipairs(modes) do
        if m.id == saved then return saved end
    end
    return modes[1].id
end

-- ============================================================
-- SAMPLES IN THE WINDOW'S STRATA
-- ============================================================
-- Module constructors put their real frames in MEDIUM or HIGH, and a
-- sample made by the same constructor brings that along - but the
-- settings window is DIALOG, so such a piece draws BEHIND the strip's
-- own background and the preview comes up empty. After every build,
-- update and replay, anything under the canvas in a lower strata is
-- lifted to the canvas's, and anything at or below the canvas's level
-- is lifted above it, keeping the order the pieces had among themselves.
local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local function FitStrata(e)
    local c = e and e.canvas
    if not (c and c:IsVisible()) then return end
    local strata = c:GetFrameStrata()
    local rank = STRATA_RANK[strata]
    if not rank then return end
    local base = c:GetFrameLevel() or 0
    -- every piece (parents before their children) with its level as it is
    local list, lvls, low = {}, {}, nil
    local function Walk(f, depth)
        if depth > 16 then return end
        for _, k in ipairs({ f:GetChildren() }) do
            local r = STRATA_RANK[k:GetFrameStrata()]
            if r and r < rank then k:SetFrameStrata(strata) end
            local lvl = k:GetFrameLevel() or 0
            list[#list + 1], lvls[#list + 1] = k, lvl
            if not low or lvl < low then low = lvl end
            Walk(k, depth + 1)
        end
    end
    Walk(c, 0)
    -- one lift for all of them, so a piece's own backdrop (a level below
    -- it, the tooltip's panel) stays under it: lifting only the ones at or
    -- below the canvas put the tooltip's panel over its text
    if low and low <= base then
        local d = base + 1 - low
        for i = 1, #list do list[i]:SetFrameLevel(math.min(9000, lvls[i] + d)) end
    end
end
Preview.FitStrata = FitStrata

-- ============================================================
-- UPDATE / REPLAY
-- ============================================================
local function Live()
    return current and dock and dock:IsVisible() and not Store().collapsed
end

-- What a frame looks like right now: its anchors, size, scale, alpha,
-- shown (to tell whether an update really changed it).
local function Look(f)
    local t = { n = f:GetNumPoints(), w = f:GetWidth(), h = f:GetHeight(), s = f:GetScale(),
        a = f:GetAlpha(), v = f:IsShown() and true or false }
    for i = 1, t.n do t[i] = { f:GetPoint(i) } end
    return t
end
local function SameLook(a, b)
    if a.n ~= b.n or a.v ~= b.v then return false end
    for _, k in ipairs({ "w", "h", "s", "a" }) do
        if math.abs((a[k] or 0) - (b[k] or 0)) > 0.01 then return false end
    end
    for i = 1, a.n do
        local p, q = a[i], b[i]
        if p[1] ~= q[1] or p[2] ~= q[2] or p[3] ~= q[3]
            or math.abs((p[4] or 0) - (q[4] or 0)) > 0.01 or math.abs((p[5] or 0) - (q[5] or 0)) > 0.01 then
            return false
        end
    end
    return true
end
-- what the update changed (only that: the rest is the frame at rest,
-- where the stop just put it - not where the animation had it)
local function PutLook(f, before, t)
    local moved = t.n ~= before.n
    for i = 1, t.n do
        local p, q = before[i], t[i]
        if not p or p[1] ~= q[1] or p[2] ~= q[2] or p[3] ~= q[3]
            or math.abs((p[4] or 0) - (q[4] or 0)) > 0.01 or math.abs((p[5] or 0) - (q[5] or 0)) > 0.01 then
            moved = true
        end
    end
    if moved then
        f:ClearAllPoints()
        for i = 1, t.n do
            local q = t[i]
            f:SetPoint(q[1], q[2], q[3], q[4], q[5])
        end
    end
    if math.abs((t.w or 0) - (before.w or 0)) > 0.01 or math.abs((t.h or 0) - (before.h or 0)) > 0.01 then
        f:SetSize(t.w, t.h)
    end
    if math.abs((t.s or 1) - (before.s or 1)) > 0.001 then f:SetScale(t.s) end
    if math.abs((t.a or 1) - (before.a or 1)) > 0.001 then f:SetAlpha(t.a) end
    if t.v ~= before.v then f:SetShown(t.v) end
end

-- An update of the page's sample. A Stop on a frame the replay set moving
-- waits until the update is done: if the update left that frame exactly
-- as it was, the animation simply plays on (a colour changed somewhere
-- else does not restart the entrance); if it moved it, the frame is
-- stopped then (back at rest) and given the update's place again.
local function GuardedUpdate(e)
    local Motion = ns.Motion
    local moving = e.moving
    if not (Motion and moving and next(moving)) then
        return pcall(e.spec.update, e.canvas, e.P)
    end
    local realStop, rawPlay, rawShow, rawHide = Motion.Stop, Motion.Play, Motion.Show, Motion.Hide
    local held = {}
    Motion.Stop = function(f, ...)
        if f and moving[f] and Motion.IsPlaying(f) then
            if not held[f] then held[f] = Look(f) end
            return
        end
        return realStop(f, ...)
    end
    -- (a page that stops a frame to play something new on it gets its
    -- stop first, as it asked)
    local function Release(f)
        if f and held[f] then
            held[f] = nil
            moving[f] = nil
            realStop(f)
        end
    end
    Motion.Play = function(f, ...) Release(f) return rawPlay(f, ...) end
    Motion.Show = function(f, ...) Release(f) return rawShow(f, ...) end
    Motion.Hide = function(f, ...) Release(f) return rawHide(f, ...) end
    local ok, err = pcall(e.spec.update, e.canvas, e.P)
    Motion.Stop, Motion.Play, Motion.Show, Motion.Hide = realStop, rawPlay, rawShow, rawHide
    for f, before in pairs(held) do
        local now = Look(f)
        if not SameLook(before, now) then
            realStop(f)
            PutLook(f, before, now)
            moving[f] = nil
        end
    end
    return ok, err
end
Preview.GuardedUpdate = GuardedUpdate

-- NOTHING CUT OFF (2026-11-08, Zac's Warrior HUD with its last row under
-- the box's edge): after an update, everything the sample shows must lie
-- inside its canvas, which the strip fits into the box. A page that sized
-- its canvas from a box that missed something (a row laid out late, a
-- text under the icons) gets a canvas that holds it all, about the same
-- centre - only ever bigger, and never for a sample that is shown "top
-- part" on purpose (spec.overflow).
local MeasureBox     -- (Measure, below)
function Preview.Contain(e)
    e = e or current
    if not (e and e.canvas and e.spec and MeasureBox) or e.spec.overflow ~= nil then return false end
    if not e.canvas:IsVisible() then return false end
    local ok, cx, cy, w, h = pcall(MeasureBox, e.canvas)
    if not (ok and cx and w and h) then return false end
    local cw, ch = CanvasSize(e)
    local needW = 2 * math.max(math.abs(cx - w / 2), math.abs(cx + w / 2)) + 2
    local needH = 2 * math.max(math.abs(cy - h / 2), math.abs(cy + h / 2)) + 2
    if needW <= cw + 1 and needH <= ch + 1 then return false end
    if e.containOff then return false end
    e.P.Resize(math.max(cw, math.ceil(needW)), math.max(ch, math.ceil(needH)))
    Preview.stats.contains = (Preview.stats.contains or 0) + 1
    -- (something that hangs off the canvas's edge moves out with it: a
    -- bigger canvas never holds it. Put back, and not tried again for
    -- this preview - no strip that grows on every update)
    local ok2, cx2, cy2, w2, h2 = pcall(MeasureBox, e.canvas)
    if ok2 and cx2 then
        local nw, nh = CanvasSize(e)
        local n2W = 2 * math.max(math.abs(cx2 - w2 / 2), math.abs(cx2 + w2 / 2)) + 2
        local n2H = 2 * math.max(math.abs(cy2 - h2 / 2), math.abs(cy2 + h2 / 2)) + 2
        if n2W > nw + 1 or n2H > nh + 1 then
            e.containOff = true
            e.P.Resize(cw, ch)
            return false
        end
    end
    return true
end

local function RunUpdate()
    local e = current
    if not (e and dock and dock:IsVisible()) then return end
    -- folded: nothing to draw into; the unfold catches it up
    if Store().collapsed then e.stale = true return end
    e.stale = nil
    e.relays = 0
    e.P.mode = ModeOf(e)
    e.P.bg = Store().bg or "dark"
    if e.spec.update then
        local ok, err = GuardedUpdate(e)
        if not ok then Fail(e, "update", err) end
    end
    FitStrata(e)
    Preview.stats.updates = Preview.stats.updates + 1
    Preview.Contain(e)
    -- (and once more next frame: the game lays new frames out lazily, so
    -- a row just made may only now have its place)
    if not e.containWait and C_Timer and C_Timer.After then
        e.containWait = true
        C_Timer.After(0, function()
            e.containWait = nil
            if current == e and dock and dock:IsVisible() then Preview.Contain(e) end
        end)
    end
end

local function RunReplay()
    if not Live() then return end
    local e = current
    if not e.spec.replay then return end
    e.P.mode = ModeOf(e)
    -- (what the replay sets moving, so an update can leave it playing)
    local Motion = ns.Motion
    e.moving = setmetatable({}, { __mode = "k" })
    local rawPlay, rawShow, rawHide
    if Motion then
        rawPlay, rawShow, rawHide = Motion.Play, Motion.Show, Motion.Hide
        Motion.Play = function(f, ...) if f then e.moving[f] = true end return rawPlay(f, ...) end
        Motion.Show = function(f, ...) if f then e.moving[f] = true end return rawShow(f, ...) end
        Motion.Hide = function(f, ...) if f then e.moving[f] = true end return rawHide(f, ...) end
    end
    local ok, err = pcall(e.spec.replay, e.canvas, e.P)
    if Motion then Motion.Play, Motion.Show, Motion.Hide = rawPlay, rawShow, rawHide end
    if not ok then Fail(e, "replay", err) end
    FitStrata(e)
    Preview.stats.replays = Preview.stats.replays + 1
end

local function Flush()
    if not pending then return end
    pending = false
    RunUpdate()
end

-- One update on the next frame, however many times this is called first.
function Preview.Request()
    if pending or not current then return end
    pending = true
    C_Timer.After(0, Flush)
end

ns.OnSettingsChanged(function()
    if current and dock and dock:IsShown() then Preview.Request() end
end)

-- ============================================================
-- BACKGROUND
-- ============================================================
-- Neutral backdrops to judge a sample against - deliberately not palette
-- colours: a frame is checked against a dark world, a bright one, and a
-- pattern that shows what is see-through, whatever the theme is.
-- The checker is two sets of stripes (columns, then rows) laid over a mid
-- grey, a few dozen textures however wide the strip is.
local BG = {
    dark  = { 0.05, 0.05, 0.05 },
    light = { 0.78, 0.78, 0.78 },
    checker = { 0.30, 0.30, 0.30 },
}
local BG_ORDER = { { "dark", "Dark" }, { "light", "Light" }, { "checker", "Checker" } }

local function PaintSwatches()
    local mode = Store().bg or "dark"
    for id, s in pairs(swatches) do
        local c = GetColor("ui", id == mode and "borderSelected" or "border")
        for _, t in ipairs(s._zBorder) do t:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
        s._zActive = (id == mode) or nil
    end
end

local function PaintBackground()
    if not view then return end
    local mode = Store().bg or "dark"
    local c = BG[mode] or BG.dark
    view.base:SetVertexColor(c[1], c[2], c[3], 1)
    local stripes = view.stripes
    local used = 0
    if mode == "checker" then
        local w, h = view:GetWidth() or 0, view:GetHeight() or 0
        local function Stripe()
            used = used + 1
            local t = stripes[used]
            if not t then
                t = view:CreateTexture(nil, "BACKGROUND", nil, -6)
                t._zui_own = true
                t:SetTexture(FLAT)
                stripes[used] = t
            end
            t:ClearAllPoints()
            t:SetVertexColor(1, 1, 1, 0.09)
            t:Show()
            return t
        end
        local x = CELL
        while x < w do
            local t = Stripe()
            t:SetPoint("TOPLEFT", view, "TOPLEFT", x, 0)
            t:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", x, 0)
            t:SetWidth(math.min(CELL, w - x))
            x = x + CELL * 2
        end
        local y = CELL
        while y < h do
            local t = Stripe()
            t:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -y)
            t:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, -y)
            t:SetHeight(math.min(CELL, h - y))
            y = y + CELL * 2
        end
    end
    for i = used + 1, #stripes do stripes[i]:Hide() end
    PaintSwatches()
end

-- ============================================================
-- LAYOUT
-- ============================================================
-- Widths for a run of buttons sharing `space`: their natural widths when
-- they fit, else all shrunk by the same share towards their minimum.
local function Squeeze(items, space)
    local nat, min = 0, 0
    for _, it in ipairs(items) do nat, min = nat + it.nat, min + it.min end
    local widths = {}
    if #items > 0 and nat > space and min < nat then
        local k = Clamp((space - min) / (nat - min), 0, 1)
        for i, it in ipairs(items) do widths[i] = math.floor(it.min + (it.nat - it.min) * k) end
    else
        for i, it in ipairs(items) do widths[i] = it.nat end
    end
    return widths
end

local function HideMenus(e)
    local row = e and e.row
    if not row then return end
    if row.menu then row.menu:Hide() end
    if row.pop then row.pop:Hide() end
end

-- THE MODE PILLS FIT THE LINE. At their natural width when there is room,
-- shrunk together (never below their text) when there is not, and when
-- even that does not fit, one small button with the chosen mode that
-- opens a menu. The page's own controls go after them on the line when
-- they fit, else behind a "More" button that opens them in a popover.
-- The mode buttons' natural widths, measured again after a change of
-- ZacUI's font (their text is re-dressed in the new face; the row stays).
local function FontEpochNow()
    local f = ZacUIDB and ZacUIDB.font or {}
    return tostring(f.name) .. "/" .. tostring(f.delta) .. "/" .. tostring(f.outline)
end
local function MeasureRow(row)
    local epoch = FontEpochNow()
    if row._zMeasured == epoch then return end
    row._zMeasured = epoch
    local widest = 0
    for _, it in ipairs(row.items or {}) do
        local fs = it.frame._zText
        local tw = math.ceil((fs and fs:GetStringWidth()) or 0)
        it.nat, it.min = tw + 14, tw + 8
        widest = math.max(widest, tw)
    end
    if row.pick then row.pickNat = widest + 26 end
    if row.menu and row.menuButtons then
        local n = 0
        for _, mb in pairs(row.menuButtons) do mb:SetWidth(widest + 20) n = n + 1 end
        row.menu:SetWidth(widest + 28)
    end
end

local function LayoutRow(e, avail)
    local row = e.row
    if not row then return end
    MeasureRow(row)
    local items, n = row.items, #row.items
    local function Need(list)
        local s = 0
        for _, it in ipairs(list) do s = s + it.min end
        return s + GAP * math.max(0, #list - 1)
    end
    local pillsMin = Need(items)
    local ctrlInline = row.holder and (8 + row.ctrlW) or 0
    local ctrlMore = row.holder and (8 + row.moreW) or 0
    local pills, inline
    if pillsMin + ctrlInline <= avail then
        pills, inline = true, true
    elseif pillsMin + ctrlMore <= avail then
        pills, inline = true, false
    else
        pills, inline = (n == 0), false
    end
    if not row.holder then inline = nil end
    row.mode = (n == 0) and "none" or (pills and "pills" or "pick")
    row.ctrlMode = row.holder and (inline and "inline" or "popover") or nil

    local x = 0
    for _, it in ipairs(items) do it.frame:SetShown(pills) end
    if row.pick then row.pick:SetShown(not pills) end
    if pills and n > 0 then
        local space = avail - GAP * (n - 1) - (row.holder and (inline and ctrlInline or ctrlMore) or 0)
        local widths = Squeeze(items, space)
        for i, it in ipairs(items) do
            it.frame:SetWidth(widths[i])
            it.frame:ClearAllPoints()
            it.frame:SetPoint("LEFT", row, "LEFT", x, 0)
            x = x + widths[i] + GAP
        end
        x = x - GAP
        if row.menu then row.menu:Hide() end
    elseif row.pick then
        local w = Clamp(avail - (row.holder and ctrlMore or 0), 40, row.pickNat)
        row.pick:SetWidth(w)
        -- a face wider than the room left (a font picked on Fonts &
        -- Textures): the label steps down a size or two rather than spill
        local fs = row.pick._zText
        if fs and fs.GetFont then
            local path, size, flags = fs:GetFont()
            if path and size then
                -- (from the size the button's text is made at, each time)
                local fd = ZacUIDB and ZacUIDB.font
                local base = F.SMALL + ((fd and fd.delta) or 0)
                if size ~= base then size = base pcall(fs.SetFont, fs, path, size, flags) end
                while size > 8 and (fs:GetStringWidth() or 0) + 6 > w do
                    size = size - 1
                    pcall(fs.SetFont, fs, path, size, flags)
                end
            end
        end
        row.pick:ClearAllPoints()
        row.pick:SetPoint("LEFT", row, "LEFT", 0, 0)
        x = w
    end
    if row.holder then
        local cx = (x > 0) and (x + 8) or 0
        if inline then
            if row.holder:GetParent() ~= row then row.holder:SetParent(row) end
            row.holder:ClearAllPoints()
            row.holder:SetPoint("LEFT", row, "LEFT", cx, 0)
            row.holder:SetSize(math.max(1, row.ctrlW), BTN_H)
            row.holder:Show()
            row.more:Hide()
            row.pop:Hide()
        else
            if row.holder:GetParent() ~= row.pop then row.holder:SetParent(row.pop) end
            row.holder:ClearAllPoints()
            row.holder:SetPoint("TOPLEFT", row.pop, "TOPLEFT", 6, -5)
            row.holder:SetSize(math.max(1, row.ctrlW), BTN_H)
            row.more:ClearAllPoints()
            row.more:SetPoint("LEFT", row, "LEFT", cx, 0)
            row.more:Show()
            row.pop:SetSize(math.max(40, row.ctrlW + 12), BTN_H + 10)
        end
    end
    row:SetSize(math.max(1, avail), BTN_H)
end

-- The cap for the chosen height: its share of the content pane.
local function CapHeight()
    local ph = host and host.PaneHeight and host.PaneHeight() or 0
    if not (ph and ph > 0) then ph = 520 end
    return math.max(MIN_H, math.floor(CAPS[HeightId()] * ph))
end
Preview.CapHeight = CapHeight

-- How the sample fits a strip w wide and (at most) capH high: its scale
-- against the real one (1 = real size), the strip's height, and whether
-- only its top part shows (spec.overflow = "clip", or a function(P)
-- answering it per mode: a long list keeps its real size and shows its
-- top rather than shrinking to unreadable).
-- The band along the sample box's foot that a page's sample keeps for a
-- line of its own (the drag layer's first-use hint): the sample is fitted
-- above it, never under it. Preview.FootFor(key) -> px (nil = none).
local function Foot(e)
    local f = Preview.FootFor
    if type(f) ~= "function" or not e then return 0 end
    local ok, v = pcall(f, e.key)
    v = ok and tonumber(v) or 0
    return (v and v > 0) and math.ceil(v) or 0
end

local function Fit(e, w, capH)
    local cw, ch = CanvasSize(e)
    local R = RealScale(e)
    local foot = Foot(e)
    local vw = math.max(10, w - 2 * EDGE)
    local fitW = math.min(1, (vw - BOX_PAD) / (cw * R))
    local want = math.ceil(VIEW_Y + EDGE + BOX_PAD + foot + ch * R * fitW)
    local h = Clamp(want, MIN_H, math.max(MIN_H, capH))
    local vh = math.max(10, h - VIEW_Y - EDGE - foot)
    local fitH = (vh - BOX_PAD) / (ch * R)
    local ov = e.spec and e.spec.overflow
    if type(ov) == "function" then
        local ok, v = pcall(ov, e.P)
        ov = ok and v or nil
    end
    local clip = ov == "clip"
    local fit = clip and fitW or math.min(fitW, fitH)
    return Clamp(fit, 0.05, 1) * Preview.zoom, h, R, (clip and fitH < fitW - 1e-6) or false
end

local function StripHeight(e, w)
    if Store().collapsed then return SLIM_H end
    local _, h = Fit(e, w, CapHeight())
    return h
end

-- The small grey note on the control line: nothing at real size,
-- "Scaled to 72%" when the sample had to shrink to fit.
local function NoteText(e)
    if not e or not e.P then return nil end
    -- (the wheel's zoom over the sample, 2026-11-08)
    if math.abs(Preview.zoom - 1) > 0.001 then
        return "Zoom " .. math.floor(Preview.zoom * 100 + 0.5) .. "% - drag to move"
    end
    local pct = math.floor((e.P.fit or 1) * 100 + 0.5)
    local scaled = pct < 100
    if e.P.clipped then return scaled and ("Scaled to " .. pct .. "%, top part") or "Top part shown" end
    return scaled and ("Scaled to " .. pct .. "%") or nil
end

-- Lays the strip out at w x h; the host has already placed it.
local function LayoutInside(e, w, h)
    local collapsed = Store().collapsed and true or false
    dock:SetSize(w, h)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", dock, "TOPLEFT", EDGE, collapsed and -1 or -BAR_Y)
    local bw = math.max(1, w - 2 * EDGE)
    bar:SetSize(bw, BTN_H)
    for _, other in pairs(entries) do
        if other.row then
            other.row:SetShown(other == e and not collapsed)
            if other ~= e or collapsed then HideMenus(other) end
        end
    end
    for _, it in ipairs(rightItems) do it:SetShown(not collapsed) end
    view:SetShown(not collapsed)
    slim:SetShown(collapsed)
    -- up folds it away, down opens it again
    foldArrow:SetTexCoord(0, 1, collapsed and 0 or 1, collapsed and 1 or 0)
    if collapsed then sizeNote:Hide() return end
    local vw, vh = bw, math.max(10, h - VIEW_Y - EDGE)
    view:ClearAllPoints()
    view:SetPoint("TOPLEFT", dock, "TOPLEFT", EDGE, -VIEW_Y)
    view:SetSize(vw, vh)
    -- the real size, cut down uniformly only when it does not fit
    local capH = CapHeight()
    local fit, _, R, clipped = Fit(e, w, h)
    local cw, ch = CanvasSize(e)
    e.canvas:SetScale(R * fit)
    e.canvas:ClearAllPoints()
    -- (centred in the box above the foot band, when a page keeps one)
    local foot = Foot(e)
    if clipped then
        -- the top of a long list, at its size
        e.canvas:SetPoint("TOP", view, "TOP", Preview.panX / (R * fit), (Preview.panY - BOX_PAD / 2) / (R * fit))
    else
        e.canvas:SetPoint("CENTER", view, "CENTER", Preview.panX / (R * fit), (Preview.panY + foot / 2) / (R * fit))
    end
    e.foot = foot
    e.P.scale, e.P.fit, e.P.real, e.P.clipped = R * fit, fit, R, clipped
    -- the room under the cap, in canvas units at the real size
    e.P.boxW = (vw - BOX_PAD) / R
    e.P.boxH = (math.max(10, capH - VIEW_Y - EDGE) - BOX_PAD) / R
    e.fitW, e.fitH = cw, ch
    -- the note, right of the page's controls and left of the cluster
    local note = NoteText(e)
    sizeNote:SetText(note or "")
    sizeNote:SetShown(note ~= nil)
    local noteW = note and (math.ceil(sizeNote:GetStringWidth() or 60) + 8) or 0
    local labW = math.ceil(label:GetStringWidth() or 40)
    -- (the right-hand cluster as it really is: the settings window's
    -- buttons are bigger than RIGHT_W counts, and the slot may hold a
    -- button; the note sits left of both, never under them)
    local rightW = RIGHT_W
    if clusterLeft and bar then
        local br, cl = bar:GetRight(), clusterLeft:GetLeft()
        if br and cl and br > cl then rightW = math.max(RIGHT_W, br - cl) end
    end
    -- (the slot as wide as what is shown in it now)
    if slot then
        local sw = 1
        for _, k in ipairs({ slot:GetChildren() }) do
            if k:IsShown() then sw = math.max(sw, k:GetWidth() or 0) end
        end
        slot:SetWidth(sw)
    end
    local slotW = (slot and (slot:GetWidth() or 0) > 1) and (slot:GetWidth() + 6) or 0
    -- (hung on the slot's left edge whatever is in it - 2026-11-10: a
    -- button that reached the slot, or got its width, after this ran sat
    -- on top of the note; anchored here the note moves with the slot)
    sizeNote:ClearAllPoints()
    if slot then sizeNote:SetPoint("RIGHT", slot, "LEFT", slotW > 0 and -6 or 0, 0)
    elseif clusterLeft then sizeNote:SetPoint("RIGHT", clusterLeft, "LEFT", -8, 0)
    else sizeNote:SetPoint("RIGHT", bar, "RIGHT", -(RIGHT_W + 6), 0) end
    if e.row then
        e.row:ClearAllPoints()
        e.row:SetPoint("LEFT", bar, "LEFT", labW + 8, 0)
        LayoutRow(e, bw - labW - 8 - rightW - 8 - slotW - noteW)
    end
    PaintBackground()
end

local function Layout()
    local e = current
    if not (dock and e) then return end
    local w = (host and host.Width and host.Width()) or dock:GetWidth() or 0
    if e.layW and math.abs(w - e.layW) < 1 then w = e.layW end
    local h = StripHeight(e, w)
    local folded = Store().collapsed and true or false
    if not folded and e.layH and e.layFolded == false and e.layCap == CapHeight()
        and h < e.layH and e.layH - h <= SHRINK_SLACK and dock:IsShown() then
        h = e.layH
    end
    e.layW, e.layH, e.layFolded, e.layCap = w, h, folded, CapHeight()
    if host and host.Place then w = host.Place(h) or w end
    LayoutInside(e, w, h)
end
-- (a new height, a fold, a new page: the strip is laid out from scratch)
local function Relayout()
    if current then current.layH = nil end
    Layout()
end

-- Lays the strip out again: after the window was resized or rescaled.
function Preview.Place()
    if current and dock and dock:IsShown() then Relayout() end
end

function Preview.SetCollapsed(on)
    Store().collapsed = on and true or nil
    Relayout()
    if not on and current and current.stale then
        pending = false
        RunUpdate()
        RunReplay()
    end
end

function Preview.SetBackground(id)
    if not BG[id] then return end
    Store().bg = id
    PaintBackground()
    -- a page can draw differently on a light background (P.bg)
    Preview.Request()
end

-- Compact / Normal / Tall: the cap moves, the strip follows, the sample
-- redraws once.
function Preview.SetHeight(id)
    id = OLD_HEIGHT[id] or id
    if not CAPS[id] then return end
    Store().height = (id ~= "normal") and id or nil
    if current and dock and dock:IsShown() then
        Relayout()
        Preview.Request()
    end
end

function Preview.HeightId() return HeightId(), CapHeight() end

-- ============================================================
-- THE STRIP
-- ============================================================
local function SmallButton(parent, text, width, onClick, tip, tipTitle)
    local b = UI.Button(parent, text, { width = width, height = BTN_H, size = F.SMALL,
        onClick = onClick, tooltip = tip, tooltipTitle = tipTitle })
    if b._zText.SetWordWrap then b._zText:SetWordWrap(false) end
    return b
end

-- An arrow on a button: the ZacUI art points down; texcoords turn it.
local function Arrow(parent, w, h)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t._zui_own = true
    t:SetTexture(ns.TEX_ARROW)
    t:SetSize(w, h)
    return t
end

local function PaintArrows(list)
    local c = GetColor("dropdown", "arrow")
    for _, t in ipairs(list) do t:SetVertexColor(c.r, c.g, c.b, 1) end
end

local function NextHeight()
    local id = HeightId()
    for i, k in ipairs(HEIGHT_ORDER) do
        if k == id then return HEIGHT_ORDER[i % #HEIGHT_ORDER + 1] end
    end
    return "normal"
end

local function EnsureDock()
    if dock or not window then return dock end
    local parent = (host and host.holder) or window
    -- The strip: an inset panel like the page's cards (the card fill, a
    -- soft 1px border), placed by the host under the page's title.
    dock = CreateFrame("Frame", nil, parent)
    dock._zSet = UI._zSettings or nil
    dock:SetSize(400, MIN_H)
    UI.Fill(dock, "ui", "cardBg")
    UI.Border(dock, "ui", "border", 0.55)
    dock:EnableMouse(true)
    dock:Hide()

    -- THE CONTROL LINE along the top edge
    bar = CreateFrame("Frame", nil, dock)
    bar:SetSize(392, BTN_H)
    label = UI.Font(bar, F.SMALL, { text = "Preview", cat = "text", key = "gray" })
    label:SetPoint("LEFT", bar, "LEFT", 1, 0)
    label:SetWordWrap(false)
    -- "Scaled to 72%": only when the sample had to shrink
    sizeNote = UI.Font(bar, F.SMALL, { text = "", cat = "text", key = "gray" })
    sizeNote:SetPoint("RIGHT", bar, "RIGHT", -(RIGHT_W + 6), 0)
    sizeNote:SetWordWrap(false)
    sizeNote:Hide()
    -- hovering the label says how big the sample is drawn
    labelHit = CreateFrame("Frame", nil, bar)
    labelHit:SetPoint("TOPLEFT", label, "TOPLEFT", -1, 2)
    labelHit:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 1, -2)
    labelHit:EnableMouse(true)
    labelHit:SetScript("OnEnter", function(self)
        local t, c = GetColor("tooltip", "title"), GetColor("tooltip", "body")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Preview", t.r, t.g, t.b)
        local note = NoteText(current)
        GameTooltip:AddLine(note and (note .. " to fit. A taller preview height shows more of it.")
            or "Actual size: drawn as big as it will be in game.", c.r, c.g, c.b, true)
        GameTooltip:Show()
    end)
    labelHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- the right-hand cluster, right to left: fold, height, Replay, swatches
    foldBtn = SmallButton(bar, "", ICON, function() Preview.SetCollapsed(not Store().collapsed) end,
        "Folds the preview down to a slim bar, or opens it again.", "Fold")
    foldBtn._zFold = true
    foldBtn:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    foldArrow = Arrow(foldBtn, 9, 9)
    foldArrow:SetPoint("CENTER")

    heightBtn = SmallButton(bar, "", ICON, function() Preview.SetHeight(NextHeight()) end)
    heightBtn._zHeight = true
    heightBtn:SetPoint("RIGHT", foldBtn, "LEFT", -2, 0)
    local up = Arrow(heightBtn, 7, 5)
    up:SetTexCoord(0, 1, 1, 0)
    up:SetPoint("BOTTOM", heightBtn, "CENTER", 0, 1)
    local down = Arrow(heightBtn, 7, 5)
    down:SetPoint("TOP", heightBtn, "CENTER", 0, -1)
    heightBtn:HookScript("OnEnter", function(self)
        local t, c = GetColor("tooltip", "title"), GetColor("tooltip", "body")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Preview height: " .. HEIGHT_NAME[HeightId()], t.r, t.g, t.b)
        GameTooltip:AddLine("The preview grows to fit its sample, up to " .. math.floor(CAPS[HeightId()] * 100 + 0.5)
            .. "% of the page's height. Click for " .. HEIGHT_NAME[NextHeight()] .. " (up to "
            .. math.floor(CAPS[NextHeight()] * 100 + 0.5) .. "%).", c.r, c.g, c.b, true)
        GameTooltip:Show()
    end)
    heightBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Replay: a play arrow (the left arrow, mirrored)
    replayBtn = SmallButton(bar, "", ICON, function() RunReplay() end,
        "Plays the preview's animations again.", "Replay")
    replayBtn._zReplay = true
    replayBtn:SetPoint("RIGHT", heightBtn, "LEFT", -2, 0)
    local play = replayBtn:CreateTexture(nil, "OVERLAY")
    play._zui_own = true
    play:SetTexture(ns.TEX_ARROWL)
    play:SetTexCoord(1, 0, 0, 1)
    play:SetSize(8, 8)
    play:SetPoint("CENTER", 1, 0)

    -- the background: three swatches, picked like a tab
    local prev = replayBtn
    for i = #BG_ORDER, 1, -1 do
        local id, name = BG_ORDER[i][1], BG_ORDER[i][2]
        local s = CreateFrame("Button", nil, bar)
        s:SetSize(SW, SW)
        s:SetPoint("RIGHT", prev, "LEFT", prev == replayBtn and -8 or -GAP, 0)
        local c = BG[id]
        local base = s:CreateTexture(nil, "ARTWORK")
        base._zui_own = true
        base:SetTexture(FLAT)
        base:SetPoint("TOPLEFT", 1, -1)
        base:SetPoint("BOTTOMRIGHT", -1, 1)
        base:SetVertexColor(c[1], c[2], c[3], 1)
        if id == "checker" then
            for _, q in ipairs({ "TOPLEFT", "BOTTOMRIGHT" }) do
                local sq = s:CreateTexture(nil, "ARTWORK", nil, 1)
                sq._zui_own = true
                sq:SetTexture(FLAT)
                sq:SetSize(math.floor(SW / 2) - 1, math.floor(SW / 2) - 1)
                sq:SetPoint(q, base, q, 0, 0)
                sq:SetVertexColor(0.62, 0.62, 0.62, 1)
            end
        end
        UI.Border(s, "ui", "border")
        local hl = s:CreateTexture(nil, "HIGHLIGHT")
        hl._zui_own = true
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.12)
        hl:SetBlendMode("ADD")
        s:SetScript("OnClick", function() Preview.SetBackground(id) end)
        UI.Tooltip(s, "Background: " .. name, "Judge the sample against a " .. (id == "checker" and "pattern that shows what is see-through" or (name:lower() .. " backdrop")) .. ".")
        s._zBg = id
        swatches[id] = s
        rightItems[#rightItems + 1] = s
        prev = s
    end
    rightItems[#rightItems + 1] = replayBtn
    rightItems[#rightItems + 1] = heightBtn
    clusterLeft = prev
    -- the slot: left of the swatches; empty (no width) until a page's
    -- sample puts something there
    slot = CreateFrame("Frame", nil, bar)
    slot:SetPoint("RIGHT", clusterLeft, "LEFT", -8, 0)
    slot:SetSize(1, BTN_H)

    -- THE SAMPLE BOX: the backdrop and the canvases, clipped to the box.
    view = CreateFrame("Frame", nil, dock)
    view.base = view:CreateTexture(nil, "BACKGROUND", nil, -6)
    view.base._zui_own = true
    view.base:SetTexture(FLAT)
    view.base:SetAllPoints()
    view.stripes = {}
    UI.Border(view, "ui", "border", 0.55)
    view._zPaint = function(self)
        UI.PaintBox(self)
        if dock and rawget(dock, "_zSet") then
            for _, t in ipairs(self._zBorder or {}) do t:SetVertexColor(1, 1, 1, UI.S.BORDER_A) end
        end
    end
    if view.SetClipsChildren then view:SetClipsChildren(true) end
    if view.EnableMouseWheel then view:EnableMouseWheel(true) end
    view:SetScript("OnMouseWheel", function(_, delta)
        local z = Preview.zoom * ((delta or 0) > 0 and 1.15 or 1 / 1.15)
        z = Clamp(z, 0.5, 3)
        if math.abs(z - 1) < 0.05 then z = 1 end
        if z == Preview.zoom then return end
        Preview.zoom = z
        if z == 1 then Preview.panX, Preview.panY = 0, 0 end
        Layout()
    end)
    -- the pan: press on the box (not on a piece - those drag themselves),
    -- move, let go; one re-lay per frame while it moves
    view:EnableMouse(true)
    local panFrom
    view:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" and button ~= "MiddleButton" then return end
        local x, y = GetCursorPosition()
        local s = self:GetEffectiveScale() or 1
        panFrom = { x / s, y / s, Preview.panX, Preview.panY }
        self:SetScript("OnUpdate", function()
            if not panFrom then self:SetScript("OnUpdate", nil) return end
            local cx, cy = GetCursorPosition()
            local nx = panFrom[3] + (cx / s - panFrom[1])
            local ny = panFrom[4] + (cy / s - panFrom[2])
            if nx ~= Preview.panX or ny ~= Preview.panY then
                Preview.panX, Preview.panY = nx, ny
                Layout()
            end
        end)
    end)
    local function StopPan(self)
        panFrom = nil
        self:SetScript("OnUpdate", nil)
    end
    view:SetScript("OnMouseUp", StopPan)
    view:HookScript("OnHide", StopPan)

    -- FOLDED: the whole slim bar opens it again, lit on hover.
    slim = CreateFrame("Button", nil, dock)
    slim._zFold = true
    slim:SetAllPoints(dock)
    slim:SetFrameLevel(dock:GetFrameLevel() + 1)
    local shl = slim:CreateTexture(nil, "HIGHLIGHT")
    shl._zui_own = true
    shl:SetAllPoints()
    shl:SetColorTexture(1, 1, 1, 0.05)
    shl:SetBlendMode("ADD")
    slim:SetScript("OnClick", function() Preview.SetCollapsed(false) end)
    UI.Tooltip(slim, "Preview", "Opens the preview again.")
    slim:Hide()
    -- the fold button stays clickable above the slim bar
    foldBtn:SetFrameLevel(slim:GetFrameLevel() + 2)

    dock._zPaint = function(self)
        UI.PaintBox(self)
        if UI.S and rawget(self, "_zSet") then
            -- the settings window: the strip sits on the window's preview
            -- band (Config_Window), so it draws no box of its own
            self._zFill:SetVertexColor(0, 0, 0, 0)
            for _, t in ipairs(self._zBorder) do t:SetVertexColor(0, 0, 0, 0) end
            for _, t in ipairs(view._zBorder or {}) do t:SetVertexColor(1, 1, 1, UI.S.BORDER_A) end
        end
        label:_zPaint()
        sizeNote:_zPaint()
        PaintArrows({ foldArrow, up, down, play })
        PaintSwatches()
    end
    dock:_zPaint()

    -- Hidden with the window or by a page without a preview: nothing of
    -- the samples may keep moving unseen, and the next showing counts as
    -- a fresh arrival (it updates at once and plays its animations).
    dock:SetScript("OnHide", function()
        shownKey = nil
        pending = false
        for _, e in pairs(entries) do HideMenus(e) end
        if current and current.canvas and ns.Motion then ns.Motion.StopTree(current.canvas) end
    end)
    return dock
end

-- A small box over the page (the mode menu, the controls popover).
local function Popup(e)
    local p = CreateFrame("Frame", nil, dock)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    UI.Fill(p, "ui", "cardBg")
    UI.Border(p, "ui", "border")
    p._zPaint = UI.PaintBox
    p:_zPaint()
    p:EnableMouse(true)
    p:Hide()
    return p
end

local function SelectMode(e, id)
    Store().modes[e.key] = id
    local row = e.row
    for mid, other in pairs(row.buttons) do other:SetActive(mid == id) end
    if row.pick then
        for _, m in ipairs(e.spec.modes) do
            if m.id == id then row.pick:SetLabel(m.label or m.id) end
        end
    end
    if row.menu then
        for mid, mb in pairs(row.menuButtons) do mb:SetActive(mid == id) end
        row.menu:Hide()
    end
    if current == e then
        pending = false
        RunUpdate()
        RunReplay()
    end
end

-- The per-key row on the control line: the mode pills (and the menu they
-- fold into), then whatever the page's own controls() builds. Made once,
-- with the key's canvas; placed by LayoutRow.
local function BuildRow(e)
    local row = CreateFrame("Frame", nil, bar)
    row:SetSize(200, BTN_H)
    row.buttons, row.items = {}, {}
    local modes = type(e.spec.modes) == "table" and e.spec.modes or {}
    if #modes > 0 then
        local widest = 0
        for _, m in ipairs(modes) do
            local id = m.id
            local text = m.label or id
            local b = SmallButton(row, text, 40, function() SelectMode(e, id) end)
            local tw = math.ceil(b._zText:GetStringWidth() or (#text * 6))
            local nat = tw + 14
            b:SetWidth(nat)
            row.items[#row.items + 1] = { frame = b, nat = nat, min = tw + 8 }
            row.buttons[id] = b
            widest = math.max(widest, tw)
        end
        -- folded pills: one button with the chosen mode and an arrow
        row.pick = SmallButton(row, modes[1].label or modes[1].id, 60, function()
            if row.menu:IsShown() then row.menu:Hide() return end
            row.menu:ClearAllPoints()
            row.menu:SetPoint("TOPLEFT", row.pick, "BOTTOMLEFT", 0, -2)
            row.menu:Show()
        end, "Shows the sample as one of these.", e.spec.modesLabel or "Show as")
        row.pick._zModePick = true
        row.pick._zText:ClearAllPoints()
        row.pick._zText:SetPoint("LEFT", 5, 0)
        row.pick._zText:SetPoint("RIGHT", -14, 0)
        row.pick._zText:SetJustifyH("LEFT")
        local pa = Arrow(row.pick, 8, 8)
        pa:SetPoint("RIGHT", -4, 0)
        PaintArrows({ pa })
        row.pickNat = widest + 26
        row._zMeasured = FontEpochNow()
        row.pick:Hide()
        row.menu = Popup(e)
        row.menuButtons = {}
        local mw = widest + 20
        for i, m in ipairs(modes) do
            local id = m.id
            local mb = SmallButton(row.menu, m.label or id, mw, function() SelectMode(e, id) end)
            mb:SetPoint("TOPLEFT", row.menu, "TOPLEFT", 4, -4 - (i - 1) * (BTN_H + 2))
            row.menuButtons[id] = mb
        end
        row.menu:SetSize(mw + 8, #modes * (BTN_H + 2) + 6)
    end
    if type(e.spec.controls) == "function" then
        local holder = CreateFrame("Frame", nil, row)
        holder:SetSize(200, BTN_H)
        local ok, err = pcall(e.spec.controls, holder, e.P)
        if not ok then Fail(e, "controls", err) end
        -- how much room the page's controls take: they sit side by side
        local cw, kids = 0, { holder:GetChildren() }
        for i, k in ipairs(kids) do cw = cw + (k:GetWidth() or 0) + (i > 1 and 8 or 0) end
        row.holder, row.ctrlW = holder, cw
        row.pop = Popup(e)
        row.more = SmallButton(row, "More", 40, function()
            if row.pop:IsShown() then row.pop:Hide() return end
            row.pop:ClearAllPoints()
            row.pop:SetPoint("TOPLEFT", row.more, "BOTTOMLEFT", 0, -2)
            row.pop:Show()
        end, "The preview's other options.", "More")
        row.moreW = math.ceil(row.more._zText:GetStringWidth() or 24) + 14
        row.more:SetWidth(row.moreW)
        row.more:Hide()
    end
    e.row = row
end

local function ModeSig(spec)
    local m = type(spec.modes) == "table" and spec.modes or {}
    local t = {}
    for i, x in ipairs(m) do t[i] = tostring(x.id) .. "=" .. tostring(x.label) end
    return table.concat(t, "|")
end

local function PaintModes(e)
    if not (e.row and e.row.buttons) then return end
    local mode = ModeOf(e)
    for id, b in pairs(e.row.buttons) do b:SetActive(id == mode) end
    if e.row.pick then
        for _, m in ipairs(e.spec.modes) do
            if m.id == mode then e.row.pick:SetLabel(m.label or m.id) end
        end
        for id, mb in pairs(e.row.menuButtons) do mb:SetActive(id == mode) end
    end
end

-- P.Place(frame, point, rel, relPoint, x, y): a sample put there only
-- when it is not there already (within PLACE_SLACK px), and only then
-- stopped first - a sample re-measured by a hair keeps what it plays.
local function PlaceSample(f, point, rel, relPoint, x, y)
    x, y = x or 0, y or 0
    local p1, r1, rp1, px, py = f:GetPoint(1)
    if f:GetNumPoints() == 1 and p1 == point and r1 == rel and rp1 == (relPoint or point)
        and math.abs((px or 0) - x) <= PLACE_SLACK and math.abs((py or 0) - y) <= PLACE_SLACK then
        return false
    end
    if ns.Motion and ns.Motion.IsPlaying(f) then ns.Motion.Stop(f) end
    f:ClearAllPoints()
    f:SetPoint(point, rel, relPoint or point, x, y)
    return true
end
Preview.PlaceSample = PlaceSample

-- A row of sample parts, left to right and centred in the canvas.
local function Row(e, parts, o)
    o = o or {}
    local gap = o.gap or 10
    local list, total, tall = {}, 0, 0
    for _, p in ipairs(parts) do
        local f = type(p) == "table" and p.frame or p
        if f and (f.IsShown == nil or f:IsShown()) then
            local k = (f.GetScale and f:GetScale()) or 1
            local w = ((type(p) == "table" and p.frame and p.w) or f:GetWidth() or 0) * k
            local h = ((type(p) == "table" and p.frame and p.h) or f:GetHeight() or 0) * k
            list[#list + 1] = { f = f, w = w, h = h, k = k, dy = type(p) == "table" and p.frame and p.dy or 0 }
            total = total + w
            tall = math.max(tall, h)
        end
    end
    total = total + gap * math.max(0, #list - 1)
    local canvas = e.canvas
    local x = -total / 2
    for _, it in ipairs(list) do
        local ox, oy = (x + it.w / 2) / it.k, ((o.y or 0) + it.dy) / it.k
        PlaceSample(it.f, "CENTER", canvas, "CENTER", ox, oy)
        x = x + it.w + gap
    end
    if o.fit and e.P.Resize then
        local pad = o.pad or 4
        e.P.Resize(math.max(o.minW or 1, math.ceil(total + 2 * pad)),
            math.max(o.minH or 1, math.ceil(tall + 2 * math.abs(o.y or 0) + 2 * pad)))
    end
    return total, tall
end

-- The box of everything visible under root, relative to root's centre.
local function Measure(root)
    if not (root and root.GetCenter) then return nil end
    local rs = root:GetEffectiveScale() or 1
    local rcx, rcy = root:GetCenter()
    if not rcx then return nil end
    local l, b, r, t
    local function Add(x)
        if x.GetObjectType and x:GetObjectType() == "FontString" then
            local s = x:GetText()
            if not s or s == "" then return end
        end
        local xl, xb, xr0, xt0 = x:GetLeft(), x:GetBottom(), x:GetRight(), x:GetTop()
        if not (xl and xb and xr0 and xt0) then return end
        local w, h = xr0 - xl, xt0 - xb
        if w <= 0 or h <= 0 then return end
        local k = (x:GetEffectiveScale() or 1) / rs
        xl, xb = xl * k, xb * k
        local xr, xt = xl + w * k, xb + h * k
        l, b = math.min(l or xl, xl), math.min(b or xb, xb)
        r, t = math.max(r or xr, xr), math.max(t or xt, xt)
    end
    local function Visit(f, depth)
        if depth > 12 then return end
        for _, x in ipairs({ f:GetRegions() }) do
            if x:IsVisible() then Add(x) end
        end
        for _, x in ipairs({ f:GetChildren() }) do
            if x:IsVisible() then
                Add(x)
                Visit(x, depth + 1)
            end
        end
    end
    Visit(root, 0)
    if not l then return nil end
    return (l + r) / 2 - rcx, (b + t) / 2 - rcy, r - l, t - b
end

-- What the sample DRAWS (its textures and texts; a frame itself draws
-- nothing - a stage or holder frame bigger than what it shows must not
-- count), relative to root's centre, in root's units.
MeasureBox = function(root)
    if not (root and root.GetCenter) then return nil end
    local rs = root:GetEffectiveScale() or 1
    local rcx, rcy = root:GetCenter()
    if not rcx then return nil end
    local l, b, r, t
    local function Add(x)
        if (x.GetAlpha and (x:GetAlpha() or 1) <= 0) then return end
        if x.GetObjectType and x:GetObjectType() == "FontString" then
            local s = x:GetText()
            if not s or s == "" then return end
        end
        local xl, xb, xr0, xt0 = x:GetLeft(), x:GetBottom(), x:GetRight(), x:GetTop()
        if not (xl and xb and xr0 and xt0) then return end
        local w, h = xr0 - xl, xt0 - xb
        if w <= 0 or h <= 0 then return end
        local k = (x:GetEffectiveScale() or 1) / rs
        xl, xb = xl * k, xb * k
        local xr, xt = xl + w * k, xb + h * k
        l, b = math.min(l or xl, xl), math.min(b or xb, xb)
        r, t = math.max(r or xr, xr), math.max(t or xt, xt)
    end
    local function Visit(f, depth)
        if depth > 12 then return end
        for _, x in ipairs({ f:GetRegions() }) do
            if x:IsVisible() then Add(x) end
        end
        for _, x in ipairs({ f:GetChildren() }) do
            if x:IsVisible() and (x:GetAlpha() or 1) > 0 then Visit(x, depth + 1) end
        end
    end
    Visit(root, 0)
    if not l then return nil end
    return (l + r) / 2 - rcx, (b + t) / 2 - rcy, r - l, t - b
end

local function Entry(key)
    local e = entries[key]
    if e then return e end
    e = { key = key }
    e.P = {
        key = key, store = {}, scale = 1,
        Update = function() if current == e then Preview.Request() end end,
        Replay = function() if current == e then RunReplay() end end,
    }
    -- the page wants another canvas: kept for the key, the scale follows
    e.P.Resize = function(w, h)
        w, h = math.max(1, math.floor(w + 0.5)), math.max(1, math.floor(h + 0.5))
        -- a pixel smaller is not worth a re-lay (bigger always is)
        local cw, ch = e.spec and e.spec.width, e.spec and e.spec.height
        if cw and ch and w <= cw and h <= ch and cw - w <= 1 and ch - h <= 1 then return end
        e.size = { w, h }
        if not (e.spec and e.canvas) then return end
        if e.spec.width == w and e.spec.height == h then return end
        e.spec.width, e.spec.height = w, h
        e.canvas:SetSize(w, h)
        if current == e and dock and dock:IsShown() then
            -- the strip grows or shrinks with the sample; a page that keeps
            -- resizing inside one update is held to a few re-lays
            local guard = e.relays or 0
            if guard < 6 then
                e.relays = guard + 1
                Layout()
            else
                local fit, _, R = Fit(e, dock:GetWidth() or 0, dock:GetHeight() or MIN_H)
                e.canvas:SetScale(R * fit)
                e.P.scale, e.P.fit = R * fit, fit
            end
        end
    end
    e.P.Row = function(parts, o) return Row(e, parts, o) end
    e.P.Place = PlaceSample
    -- not placed yet (the game lays new frames out lazily): one more
    -- update next frame, a few times at most
    e.P.Measure = function(root)
        local cx, cy, w, h = Measure(root)
        if cx then e.measureTries = nil
        elseif (e.measureTries or 0) < 5 and not e.measureWait then
            e.measureTries, e.measureWait = (e.measureTries or 0) + 1, true
            C_Timer.After(0, function() e.measureWait = nil e.P.Update() end)
        end
        return cx, cy, w, h
    end
    entries[key] = e
    return e
end

-- ============================================================
-- THE PAGE SIDE (Config_Window calls these around every build)
-- ============================================================
-- host.holder is the frame the strip lives on (the page's pinned top);
-- host.Place(h) puts a strip h high under the page's title (0 takes it
-- away), moves the page's scroll area to start below it, and returns
-- the strip's width.
function Preview.Attach(win, h)
    window = win
    host = h
end

function Preview.BeginPage()
    declared, collecting = nil, true
end

-- Called from the page builder through L:Preview. Ignored for anything
-- but the live build: the search index builds every page unseen, and a
-- page built for the index must not take the strip over.
function Preview.Declare(layout, spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" then
        Print("L:Preview needs a table with a key")
        return nil
    end
    if not (collecting and layout and layout.live) then return nil end
    declared = spec
    return Entry(spec.key).P
end

-- What the live build asked for so far (the window pins the page's title
-- above the strip before EndPage places it).
function Preview.Declared() return collecting and declared or nil end

function Preview.EndPage()
    collecting = false
    local spec = declared
    declared = nil
    if not spec or not window then
        Preview.HideDock()
        return
    end
    EnsureDock()
    local e = Entry(spec.key)
    e.spec = spec
    -- a size the page asked for since (P.Resize) stays for the key
    if e.size then spec.width, spec.height = e.size[1], e.size[2] end
    if not e.canvas then
        e.canvas = CreateFrame("Frame", nil, view)
        e.canvas:SetPoint("CENTER", view, "CENTER", 0, 0)
        -- a sample piece that runs past the canvas is cut off at its edge
        if e.canvas.SetClipsChildren then e.canvas:SetClipsChildren(true) end
    end
    e.canvas:SetSize(spec.width or 240, spec.height or 120)
    e.relays = 0
    if not e.built then
        e.built = true
        Preview.stats.builds = Preview.stats.builds + 1
        if spec.build then
            local ok, err = pcall(spec.build, e.canvas, e.P)
            if not ok then Fail(e, "build", err) end
        end
    end
    -- the page's modes changed since the row was made (a setting adds or
    -- takes one away, as the warrior HUD's Battle Shout states): a new row
    local sig = ModeSig(spec)
    if e.row and e.rowSig ~= sig then
        HideMenus(e)
        e.row:Hide()
        e.row = nil
    end
    if not e.row and (spec.modes or spec.controls) then
        BuildRow(e)
        e.rowSig = sig
    end
    PaintModes(e)
    for _, other in pairs(entries) do
        if other ~= e and other.canvas then
            if ns.Motion then ns.Motion.StopTree(other.canvas) end
            other.canvas:Hide()
        end
    end
    e.canvas:Show()

    local arrived = (current ~= e) or (shownKey ~= e.key) or not dock:IsShown()
    current = e
    replayBtn:SetDisabled(spec.replay == nil)
    dock:Show()
    if arrived then Relayout() else Layout() end
    if arrived then
        -- a new page (or the window reopened): draw it now rather than a
        -- frame late, and play its animations once
        shownKey = e.key
        pending = false
        RunUpdate()
        RunReplay()
    else
        -- a rebuild of the same page: one coalesced update
        Preview.Request()
    end
end

function Preview.HideDock()
    if dock then dock:Hide() end
    current = nil
    pending = false
    if host and host.Place then host.Place(0) end
end

function Preview.IsShown()
    return dock ~= nil and dock:IsVisible() and current ~= nil
end

function Preview.Current()
    return current and current.key, current and current.canvas, current and current.P
end

-- The mode ids the strip offers right now, in order (the per-game-version
-- tests read them: a mode for something that does not load there is not
-- offered).
function Preview.CurrentModes()
    local out = {}
    local spec = current and current.spec
    for _, m in ipairs(type(spec and spec.modes) == "table" and spec.modes or {}) do out[#out + 1] = m.id end
    return out
end

-- How tall the strip is right now (0 when there is none).
function Preview.Height()
    if not (dock and dock:IsShown() and current) then return 0 end
    return dock:GetHeight() or 0
end

Preview.Replay = RunReplay

-- A page control that is about one of the modes (the meter's "Preview
-- at" slider is about its Threat glow) picks that mode without drawing:
-- the change signal the control raises next draws it, so it is still one
-- update. Remembered like a click on the mode's button.
function Preview.UseMode(key, id)
    if not (key and id) then return end
    local st = Store()
    if st.modes[key] == id then return end
    st.modes[key] = id
    if current and current.key == key then PaintModes(current) end
end
Preview.Frame = function() return dock end
Preview.View = function() return view end
-- the control line's slot for a page's sample (left of the swatches)
Preview.Slot = function() EnsureDock() return slot end

-- The page builders' way in.
function ConfigLayout:Preview(spec)
    return Preview.Declare(self, spec)
end

-- shared with later ZacUI files
ns.ConfigPreview = Preview
