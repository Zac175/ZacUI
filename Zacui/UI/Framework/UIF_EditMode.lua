-- UIF_EditMode - one button that puts EVERY ZacUI placeholder on screen
-- at once over a dimmed, gridded world, with a floating control box to
-- park elements, reset them and lock when done. The Movers page still
-- works one element at a time; this is the "arrange the whole HUD"
-- pass, the way Driev's Essentials' Edit Mode button did it.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT IT MOVES. Everything with a ZacUI-owned position:
--   * the mover registry: loot rolls, buffs, minimap (each skipped, with
--     the usual one-line notice, when Edit Mode or the client owns it)
--     and every class HUD anchor and the drink ticker
--   * the tooltip anchor (Blz_Tooltip's, shown silently)
--   * whatever the parts contribute through ns.EditModeProviders: the
--     action bars, and the unit frames (player, target, party, raid -
--     their own move mode, with the party and raid previews)
--   Readycheck's frames are NOT part of this: it has an Edit Mode of its
--   own, and the two on screen at once was one pile of boxes too many.
--   * the open meter windows, unlocked for the duration and put back to
--     whatever lock state they had
--
-- HIDING. Untick an element (or Hide all) and it is out of the way for
-- the pass: its box goes and, where the movable names them through an
-- optional `content` function, the real frames are faded to nothing, so
-- what is left is easy to reach. Locking fades them all back in. The
-- ticks are remembered (editMode.parked) for the next pass.
-- Blizzard's own Edit Mode systems are NOT fought here, for the reasons
-- in UIF_Movers: on 11509 they win every layout pass.
--
-- THE OVERLAY is BACKGROUND strata: it dims the world and draws the
-- grid UNDER every UI frame, so the things you are placing stay at full
-- brightness instead of being dimmed with everything else. Mouse stays
-- off on it, so the camera still turns.
--
-- THE CONTROL BOX is a ZacUI window: draggable by its title, closes on
-- Escape, remembers where you left it. Closing it by any route (Lock,
-- the X, Escape) is the exit - one path, so nothing can be left on
-- screen half-dressed.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local FLAT = ns.FLAT
local HideMover = ns.HideMover
local MOVERS = ns.MOVERS
local MoverBlocked = ns.MoverBlocked
local Print = ns.Print
local ResetMover = ns.ResetMover
local ShowMover = ns.ShowMover
local UI = ns.UI

local M, F = UI.M, UI.F

-- ============================================================
-- SETTINGS
-- ============================================================
local function DB()
    ZacUIDB.editMode = ZacUIDB.editMode or {}
    local d = ZacUIDB.editMode
    if d.dim == nil then d.dim = 55 end       -- overlay darkness, percent
    if d.grid == nil then d.grid = true end
    d.parked = d.parked or {}                 -- [key] = true: hidden in edit mode
    return d
end

-- ============================================================
-- MOVABLES - gathered fresh on every entry: which meter windows are
-- open changes, and a mover the client took over since login should
-- drop out rather than error.
-- ============================================================
ns.EditModeProviders = ns.EditModeProviders or {}
local function Movables()
    local list = {}
    for _, m in ipairs(MOVERS) do
        local key = m.key
        list[#list + 1] = {
            key = key, label = m.label,
            blocked = function() return MoverBlocked(key, m.getFrame()) end,
            show = function() ShowMover(key) end,
            hide = function() HideMover(key) end,
            reset = function(silent) ResetMover(key, silent) end,
            offscreen = function() return ns.MoverOffScreen and ns.MoverOffScreen(key) end,
            frames = function() local p = _G["ZacUIMover_" .. key] return p and { p } or nil end,
            content = function()
                local f = m.getFrame()
                if not f or MoverBlocked(key, f) then return nil end
                return { f }
            end,
        }
    end
    if ns.SetTipMover then
        list[#list + 1] = {
            key = "tooltip", label = "Tooltip anchor",
            show = function() ns.SetTipMover(true, true) end,
            hide = function() ns.SetTipMover(false) end,
            frames = function() local p = _G.ZacUITooltipMover return p and { p } or nil end,
            reset = function(silent)
                if ns.ResetTipPos then ns.ResetTipPos() else ZacUIDB.tooltipPos = nil end
                if not silent then Print("Tooltip position reset to Blizzard default.") end
            end,
        }
    end
    -- other systems (the action bars) contribute their own movables
    for _, provider in ipairs(ns.EditModeProviders or {}) do
        local ok, extra = pcall(provider)
        if ok and type(extra) == "table" then
            for _, e in ipairs(extra) do list[#list + 1] = e end
        end
    end
    local Meter = ns.Meter
    local md = Meter and Meter.DB and Meter.DB()
    for i, w in ipairs(md and md.windows or {}) do
        if w.open then
            list[#list + 1] = {
                key = "meter" .. i,
                label = "Meter window " .. i
                    .. (w.display == "threat" and " (threat)" or ""),
                -- unlock for the pass, restore the exact flag after -
                -- both ship locked, and an unlocked window eats drags
                -- meant for the world
                show = function()
                    if w._zEditWasLocked == nil then w._zEditWasLocked = w.locked end
                    w.locked = false
                end,
                hide = function()
                    if w._zEditWasLocked ~= nil then
                        w.locked = w._zEditWasLocked
                        w._zEditWasLocked = nil
                    end
                end,
                frames = function() local p = _G["ZacUIMeterWindow" .. i] return p and { p } or nil end,
                content = function() local p = _G["ZacUIMeterWindow" .. i] return p and { p } or nil end,
            }
        end
    end
    return list
end

-- ============================================================
-- OVERLAY
-- ============================================================
local overlay
local GRID = 50

local function BuildGrid()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if overlay._gridW == w and overlay._gridH == h then return end
    overlay._gridW, overlay._gridH = w, h
    overlay.lines = overlay.lines or {}
    local n = 0
    local function line()
        n = n + 1
        local t = overlay.lines[n]
        if not t then
            t = overlay:CreateTexture(nil, "ARTWORK")
            t._zui_own = true
            t:SetTexture(FLAT)
            overlay.lines[n] = t
        end
        t:ClearAllPoints()
        return t
    end
    for i = 0, math.ceil(w / GRID) do
        local t = line()
        t:SetPoint("TOPLEFT", overlay, "TOPLEFT", i * GRID, 0)
        t:SetSize(1, h)
    end
    for i = 0, math.ceil(h / GRID) do
        local t = line()
        t:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, -(i * GRID))
        t:SetSize(w, 1)
    end
    for i = n + 1, #overlay.lines do overlay.lines[i]:Hide() end
end

local function PaintOverlay()
    if not overlay then return end
    local d = DB()
    overlay.bg:SetVertexColor(0, 0, 0, (d.dim or 55) / 100)
    -- the centre lines a touch brighter, so the middle of the screen is
    -- findable at a glance
    local cx = math.floor(overlay._gridW / 2 / GRID)
    local cy = math.floor(overlay._gridH / 2 / GRID)
    local cols = math.ceil(overlay._gridW / GRID) + 1
    for i, t in ipairs(overlay.lines) do
        local centre = (i - 1 == cx) or (i - 1 - cols == cy)
        t:SetVertexColor(1, 1, 1, centre and 0.18 or 0.07)
        t:SetShown(d.grid and true or false)
    end
end

local function ShowOverlay()
    if not overlay then
        overlay = CreateFrame("Frame", "ZacUIEditOverlay", UIParent)
        overlay:SetAllPoints(UIParent)
        overlay:SetFrameStrata("BACKGROUND")
        overlay:EnableMouse(false)
        local bg = overlay:CreateTexture(nil, "BACKGROUND")
        bg._zui_own = true
        bg:SetAllPoints()
        bg:SetTexture(FLAT)
        overlay.bg = bg
    end
    BuildGrid()
    PaintOverlay()
    overlay:Show()
end

-- ============================================================
-- STATE
-- ============================================================
local active = false
local current = {}          -- the movables of this pass
local reopenConfig = false
local bar

local function IsParked(key) return DB().parked[key] == true end

local function ShowMovable(m)
    if m.blocked and m.blocked() then return end
    m.show()
end

-- FADING. A hidden element's real frames go to alpha 0 for the pass (not
-- Hide: their owners show and hide them, some are secure). Owners that
-- fade their own frames would bring them back, so the guide tick, which
-- runs every frame while Edit Mode is open, puts the fade back.
local faded = {}             -- [frame] = the alpha it had before

local function ContentOf(m)
    if not m.content then return {} end
    local ok, list = pcall(m.content)
    if not (ok and type(list) == "table") then return {} end
    local out = {}
    for _, item in ipairs(list) do
        if type(item) == "table" and rawget(item, "union") then
            for _, f in ipairs(item.union) do out[#out + 1] = f end
        elseif item then
            out[#out + 1] = item
        end
    end
    return out
end

local function FadeContent(m)
    for _, f in ipairs(ContentOf(m)) do
        if f.SetAlpha and f.GetAlpha then
            if faded[f] == nil then faded[f] = f:GetAlpha() or 1 end
            f:SetAlpha(0)
        end
    end
end

local function UnfadeFrame(f)
    local a = faded[f]
    if a == nil then return end
    faded[f] = nil
    f:SetAlpha(a)
end

local function UnfadeContent(m)
    for _, f in ipairs(ContentOf(m)) do UnfadeFrame(f) end
end

local function UnfadeAll()
    local list = {}
    for f in pairs(faded) do list[#list + 1] = f end
    for _, f in ipairs(list) do UnfadeFrame(f) end
end

local function KeepFaded()
    for f in pairs(faded) do
        if f:GetAlpha() ~= 0 then f:SetAlpha(0) end
    end
end

-- One element out of the way, or back. Remembered for the next pass.
local function SetParked(m, park)
    local d = DB()
    if park then
        d.parked[m.key] = true
        m.hide()
        FadeContent(m)
    else
        d.parked[m.key] = nil
        UnfadeContent(m)
        ShowMovable(m)
    end
end

local Exit  -- forward: the bar's OnHide calls it
local FillBar  -- forward: Show all / Hide all refill the list

-- ============================================================
-- OUTLINES AND GUIDES
-- ============================================================
-- Two things to line elements up with, both drawn here so every element
-- gets them the same way whatever system owns it:
--
--   OUTLINES  a one-pixel box round everything that can be moved, with a
--             tick at the middle of each side. A party or raid block gets
--             ONE box round the whole block.
--   GUIDES    point at an element (or drag it) and six lines run the width
--             and height of the screen from its left edge, centre and
--             right edge, and its top, centre and bottom. A line turns
--             green the moment it lies on the same edge or centre of any
--             other element, or on the centre of the screen. A small
--             readout gives the element's offset from screen centre and
--             its size.
--
-- A movable says what to outline with an optional `frames` function: a
-- list of frames, or { union = { frames } } for one box round several.
-- Nothing is anchored to anybody's frame - the boxes are placed from each
-- frame's rect, read every frame while Edit Mode is open (it cannot be
-- open in combat). The guides do not snap; they tell you when you are on.
local guides, lines, readout
local outlines, targets = {}, {}
local activeId
local GOOD = { 0.3, 1, 0.4 }

-- UI units in one physical pixel, so the lines are one pixel on any scale
local function Px()
    local _, ph = GetPhysicalScreenSize()
    local uh = UIParent:GetHeight()
    if ph and ph > 0 and uh and uh > 0 then return uh / ph end
    return 1
end

-- left, right, top, bottom of a frame in UIParent units; nil when it is
-- not on screen
local function RectOf(f)
    if not (f and f.IsVisible and f:IsVisible() and f.GetRect) then return nil end
    local l, b, w, h = f:GetRect()
    if not (l and b and w and h) or w <= 0 or h <= 0 then return nil end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, (l + w) * s, (b + h) * s, b * s
end

local function RectOfTarget(t)
    if not t.union then return RectOf(t.frame) end
    local l, r, top, b
    for _, f in ipairs(t.union) do
        local fl, fr, ft, fb = RectOf(f)
        if fl then
            if not l or fl < l then l = fl end
            if not r or fr > r then r = fr end
            if not top or ft > top then top = ft end
            if not b or fb < b then b = fb end
        end
    end
    return l, r, top, b
end

local function CollectTargets()
    wipe(targets)
    for _, m in ipairs(current) do
        if m.frames and not IsParked(m.key) and not (m.blocked and m.blocked()) then
            local ok, list = pcall(m.frames)
            if ok and type(list) == "table" then
                for _, item in ipairs(list) do
                    if type(item) == "table" and rawget(item, "union") then
                        -- a union is known by its first frame, so it is
                        -- the same target from one collection to the next
                        targets[#targets + 1] = { union = item.union, id = item.union[1] }
                    elseif item then
                        targets[#targets + 1] = { frame = item, id = item }
                    end
                end
            end
        end
    end
end

local function Outline(i)
    local o = outlines[i]
    if o then return o end
    o = CreateFrame("Frame", nil, guides)
    o.edges, o.ticks = {}, {}
    for n = 1, 4 do
        local e = o:CreateTexture(nil, "OVERLAY")
        e._zui_own = true
        e:SetTexture(FLAT)
        o.edges[n] = e
        local t = o:CreateTexture(nil, "OVERLAY")
        t._zui_own = true
        t:SetTexture(FLAT)
        o.ticks[n] = t
    end
    function o:Dress(px, r, g, b, a)
        local top, bottom, left, right = self.edges[1], self.edges[2], self.edges[3], self.edges[4]
        top:ClearAllPoints() top:SetPoint("TOPLEFT") top:SetPoint("TOPRIGHT") top:SetHeight(px)
        bottom:ClearAllPoints() bottom:SetPoint("BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT") bottom:SetHeight(px)
        left:ClearAllPoints() left:SetPoint("TOPLEFT") left:SetPoint("BOTTOMLEFT") left:SetWidth(px)
        right:ClearAllPoints() right:SetPoint("TOPRIGHT") right:SetPoint("BOTTOMRIGHT") right:SetWidth(px)
        -- the middle of each side, as a short stroke across the edge
        local len = px * 7
        local tt, tb, tl, tr = self.ticks[1], self.ticks[2], self.ticks[3], self.ticks[4]
        tt:ClearAllPoints() tt:SetPoint("CENTER", self, "TOP", 0, 0) tt:SetSize(px, len)
        tb:ClearAllPoints() tb:SetPoint("CENTER", self, "BOTTOM", 0, 0) tb:SetSize(px, len)
        tl:ClearAllPoints() tl:SetPoint("CENTER", self, "LEFT", 0, 0) tl:SetSize(len, px)
        tr:ClearAllPoints() tr:SetPoint("CENTER", self, "RIGHT", 0, 0) tr:SetSize(len, px)
        for n = 1, 4 do
            self.edges[n]:SetVertexColor(r, g, b, a)
            self.ticks[n]:SetVertexColor(r, g, b, a)
        end
    end
    outlines[i] = o
    return o
end

local function Near(a, b, tol) return a and b and math.abs(a - b) <= tol end

local function GuideTick(_, dt)
    if next(faded) then KeepFaded() end
    guides._acc = (guides._acc or 1) + dt
    if guides._acc >= 0.5 then
        guides._acc = 0
        CollectTargets()
    end
    local px = Px()
    -- "on" means on the same pixel: half a pixel either way, so green is
    -- exact and one pixel out is not
    local tol = px * 0.55
    local us = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx, my = mx / us, my / us
    local a = Col("accent")

    -- place every box; find what the cursor is on (the smallest, so an
    -- element inside a bigger one can still be picked)
    local under, underArea, held
    for i, t in ipairs(targets) do
        local l, r, top, b = RectOfTarget(t)
        t.l, t.r, t.t, t.b = l, r, top, b
        local o = Outline(i)
        if l then
            o:ClearAllPoints()
            o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
            o:SetSize(r - l, top - b)
            o:Show()
            if t.id == activeId then held = t end
            if mx >= l and mx <= r and my >= b and my <= top then
                local area = (r - l) * (top - b)
                if not underArea or area < underArea then under, underArea = t, area end
            end
        else
            o:Hide()
        end
    end
    for i = #targets + 1, #outlines do outlines[i]:Hide() end

    -- while the button is down the element being dragged keeps the guides,
    -- even if the cursor crosses something else on the way
    local active = (held and IsMouseButtonDown("LeftButton")) and held or under
    activeId = active and active.id or nil

    for i, t in ipairs(targets) do
        if t.l then
            if t == active then outlines[i]:Dress(px, 1, 1, 1, 1)
            else outlines[i]:Dress(px, a.r, a.g, a.b, 0.9) end
        end
    end

    if not active then
        for n = 1, 6 do lines[n]:Hide() end
        readout:Hide()
        return
    end

    local l, r, top, b = active.l, active.r, active.t, active.b
    local cx, cy = (l + r) / 2, (top + b) / 2
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local vx = { l, cx, r }          -- the three vertical lines
    local hy = { top, cy, b }        -- the three horizontal lines
    local vOn, hOn = {}, {}
    for n = 1, 3 do
        if Near(vx[n], sw / 2, tol) then vOn[n] = true end
        if Near(hy[n], sh / 2, tol) then hOn[n] = true end
    end
    for _, t in ipairs(targets) do
        if t ~= active and t.l then
            local ox = { t.l, (t.l + t.r) / 2, t.r }
            local oy = { t.t, (t.t + t.b) / 2, t.b }
            for n = 1, 3 do
                for k = 1, 3 do
                    if Near(vx[n], ox[k], tol) then vOn[n] = true end
                    if Near(hy[n], oy[k], tol) then hOn[n] = true end
                end
            end
        end
    end
    for n = 1, 3 do
        local v, h = lines[n], lines[n + 3]
        v:ClearAllPoints()
        v:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", vx[n] - px / 2, 0)
        v:SetSize(px, sh)
        if vOn[n] then v:SetVertexColor(GOOD[1], GOOD[2], GOOD[3], 1)
        else v:SetVertexColor(a.r, a.g, a.b, 0.45) end
        v:Show()
        h:ClearAllPoints()
        h:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, hy[n] - px / 2)
        h:SetSize(sw, px)
        if hOn[n] then h:SetVertexColor(GOOD[1], GOOD[2], GOOD[3], 1)
        else h:SetVertexColor(a.r, a.g, a.b, 0.45) end
        h:Show()
    end

    -- a ZacUI handle shows its own readout (its spot in its own numbers,
    -- the same ones its settings show); this one is for everything else
    if active.frame and ns.MoverKit and ns.MoverKit.IsDressed(active.frame) then
        readout:Hide()
        return
    end
    -- offset of the element's centre from the centre of the screen, and
    -- its size, just above its top-left corner (below it at the screen top)
    readout:SetText(("%+d, %+d    %d x %d"):format(
        math.floor(cx - sw / 2 + 0.5), math.floor(cy - sh / 2 + 0.5),
        math.floor(r - l + 0.5), math.floor(top - b + 0.5)))
    readout:ClearAllPoints()
    if top + 16 < sh then
        readout:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, top + 3)
    else
        readout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, b - 3)
    end
    readout:Show()
end

local function ShowGuides()
    if not guides then
        guides = CreateFrame("Frame", "ZacUIEditGuides", UIParent)
        guides:SetAllPoints(UIParent)
        -- above every element being placed, below the control box
        guides:SetFrameStrata("FULLSCREEN_DIALOG")
        guides:EnableMouse(false)
        lines = {}
        for n = 1, 6 do
            local t = guides:CreateTexture(nil, "BACKGROUND")
            t._zui_own = true
            t:SetTexture(FLAT)
            t:Hide()
            lines[n] = t
        end
        readout = UI.Font(guides, F.SMALL, { text = "", cat = "text", key = "normal" })
        readout:Hide()
        guides:SetScript("OnUpdate", GuideTick)
    end
    guides._acc = 1          -- collect on the first tick
    activeId = nil
    guides:Show()
end

local function HideGuides()
    if guides then guides:Hide() end
    wipe(targets)
    activeId = nil
end

-- ============================================================
-- CONTROL BOX
-- ============================================================
local ROW = 24

local function BuildBar()
    bar = UI.Window("ZacUIEditModeBar", 300, 200, "Edit Mode")
    bar:SetFrameStrata("TOOLTIP")
    bar:SetClampedToScreen(true)
    bar._zOnMoved = function()
        local point, _, _, x, y = bar:GetPoint(1)
        local d = DB()
        d.barPoint, d.barX, d.barY = point, x, y
    end

    local desc = UI.Font(bar, F.DESC, {
        text = "Drag the outlined elements into place. Point at one for guide "
            .. "lines - a line turns green when it lines up with another "
            .. "element or the screen centre. Untick an element to hide it "
            .. "while you place the rest; Lock brings it back.",
        cat = "text", key = "gray", width = 300 - 2 * M.CARD_PAD })
    desc:SetPoint("TOPLEFT", bar, "TOPLEFT", M.CARD_PAD, -(M.TITLEBAR + 8))
    bar.desc = desc

    local d = DB()
    bar.dim = UI.Slider(bar, { width = 300 - 2 * M.CARD_PAD, min = 0, max = 90,
        step = 5, value = d.dim, label = "Dim the world",
        format = function(v) return v .. "%" end,
        onChange = function(v)
            DB().dim = v
            PaintOverlay()
        end })
    bar.dim:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)

    bar.grid = UI.Checkbox(bar, "Grid", d.grid, function(v)
        DB().grid = v and true or false
        PaintOverlay()
    end)
    bar.grid:SetPoint("TOPLEFT", bar.dim, "BOTTOMLEFT", 0, -8)

    -- every element out of the way at once, or all back
    local half = math.floor((300 - 2 * M.CARD_PAD - 6) / 2)
    bar.showAll = UI.Button(bar, "Show all", { width = half, height = 20, size = F.SMALL,
        onClick = function()
            for _, m in ipairs(current) do
                if IsParked(m.key) and not (m.blocked and m.blocked()) then SetParked(m, false) end
            end
            FillBar()
        end })
    bar.showAll:SetPoint("TOPLEFT", bar.grid, "BOTTOMLEFT", 0, -6)
    bar.hideAll = UI.Button(bar, "Hide all", { width = half, height = 20, size = F.SMALL,
        onClick = function()
            for _, m in ipairs(current) do
                if not IsParked(m.key) and not (m.blocked and m.blocked()) then SetParked(m, true) end
            end
            FillBar()
        end })
    bar.hideAll:SetPoint("LEFT", bar.showAll, "RIGHT", 6, 0)

    -- The element list scrolls. A class HUD alone is seven rows and the
    -- bars, meter windows and tooltip add more; squeezing rows to fit
    -- the screen made the long list unreadable, so the box has a
    -- ceiling and the list scrolls inside it.
    bar.rows = {}
    bar.scroll, bar.list, bar.scrollBar = UI.ScrollArea(bar)
    bar.scroll:SetPoint("TOPLEFT", bar.showAll, "BOTTOMLEFT", 0, -6)
    bar.scrollBar:SetPoint("TOPLEFT", bar.scroll, "TOPRIGHT", 4, 0)
    bar.scrollBar:SetPoint("BOTTOMLEFT", bar.scroll, "BOTTOMRIGHT", 4, 0)
    bar.lock = UI.Button(bar, "Lock", { width = 120,
        tooltip = "Hide the placeholders and keep everything where it is.",
        onClick = function() Exit() end })
    bar.resetAll = UI.Button(bar, "Reset all", { width = 90,
        tooltip = "Every element back to its default spot.",
        onClick = function()
            for _, m in ipairs(current) do
                if m.reset and not (m.blocked and m.blocked()) then m.reset(true) end
            end
            Print("every element back to its default spot.")
        end })
    bar.lock:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", M.CARD_PAD, M.CARD_PAD)
    bar.resetAll:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -M.CARD_PAD, M.CARD_PAD)

    -- the X, Escape and Lock all land here; Exit is idempotent
    bar:HookScript("OnHide", function() if active then Exit() end end)
end

FillBar = function()
    local d = DB()
    local y = 0
    local descH = math.max(30, (bar.desc and bar.desc:GetStringHeight()) or 30)
    local fixed = M.TITLEBAR + 8 + descH + 8 + 30 + 8 + M.CHECK + 6 + 20 + 6 + 12 + M.BUTTON_H + M.CARD_PAD
    local innerW = 300 - 2 * M.CARD_PAD
    for i, m in ipairs(current) do
        local row = bar.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, bar.list)
            row:SetHeight(ROW)
            row.reset = UI.Button(row, "Reset", { width = 60, height = 18, size = F.SMALL })
            row.reset:SetPoint("RIGHT")
            bar.rows[i] = row
        end
        -- the checkbox binds its callback at build, and the movable it
        -- refers to changes per pass, so it is rebuilt each time
        if row.check then row.check:Hide(); row.check:SetParent(nil) end
        local blocked = m.blocked and m.blocked()
        -- a frame pushed off the screen says so (its Reset brings it back)
        local off = not blocked and m.offscreen and m.offscreen()
        local label = m.label .. (blocked and " |cffff9933(Edit Mode)|r" or "")
            .. (off and " |cffff9933(off screen)|r" or "")
        row.check = UI.Checkbox(row, label, not blocked and not IsParked(m.key),
            function(v) SetParked(m, not v) end)
        row.check:SetPoint("LEFT")
        if blocked then row.check:Disable() end
        row.reset:SetScript("OnClick", m.reset)
        row.reset:SetShown(m.reset ~= nil and not blocked)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", bar.list, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", bar.list, "RIGHT", 0, 0)
        y = y + ROW
        row:Show()
    end
    for i = #current + 1, #bar.rows do bar.rows[i]:Hide() end

    -- the list gets what the screen allows, up to a ceiling; past that
    -- it scrolls, and the scrollbar takes its width from the rows
    local room = (UIParent:GetHeight() or 768) - 80 - fixed
    local listH = math.max(ROW, math.min(y, room, 14 * ROW))
    local scrolls = y > listH + 1
    local listW = innerW - (scrolls and (M.SCROLL_W + 4) or 0)
    bar.scroll:SetSize(listW, listH)
    bar.list:SetSize(listW, math.max(1, y))
    bar.scroll:Recalculate(y)
    if not scrolls then bar.scrollBar:SetValue(0) end

    bar:SetHeight(fixed + listH)

    bar:ClearAllPoints()
    if d.barPoint then
        bar:SetPoint(d.barPoint, UIParent, d.barPoint, d.barX or 0, d.barY or 0)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -40)
    end
end

-- ============================================================
-- ENTER / EXIT
-- ============================================================
-- PREVIEW WATCHERS: things with nothing to move but something to show
-- while the HUD is being arranged (the crosshair) register a function
-- here and are told on every enter (true) and exit (false).
local watchers = {}
local function WatchEditMode(fn)
    watchers[#watchers + 1] = fn
end
local function NotifyWatchers(on)
    for _, fn in ipairs(watchers) do pcall(fn, on) end
end

local function Enter()
    if active then return end
    if InCombatLockdown and InCombatLockdown() then
        Print("edit mode waits for combat to end.")
        return
    end
    active = true

    -- the config window gets out of the way and comes back on Lock
    reopenConfig = ns.ConfigIsOpen and ns.ConfigIsOpen() or false
    if reopenConfig and ZacUIConfigFrame then UI.CloseWindow(ZacUIConfigFrame) end

    current = Movables()
    ShowOverlay()
    for _, m in ipairs(current) do
        if IsParked(m.key) then FadeContent(m) else ShowMovable(m) end
    end
    ShowGuides()

    if not bar then BuildBar() end
    FillBar()
    bar.dim:SetValue(DB().dim)
    bar.grid:SetChecked(DB().grid)
    UI.OpenWindow(bar)
    NotifyWatchers(true)
end

Exit = function()
    if not active then return end
    active = false
    HideGuides()
    for _, m in ipairs(current) do m.hide() end
    UnfadeAll()
    current = {}
    if overlay then overlay:Hide() end
    if bar and bar:IsShown() then bar:Hide() end
    if reopenConfig and ns.OpenConfig then
        reopenConfig = false
        ns.OpenConfig()
    end
    NotifyWatchers(false)
end

local function Toggle()
    if active then Exit() else Enter() end
end

-- combat: the mover proxies are plain frames and stay draggable, but the
-- meter unlock and the config reopen are not worth the lockdown errors -
-- a pull ends the pass
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:SetScript("OnEvent", function() if active then Exit() end end)

-- shared with later ZacUI files
ns.EnterEditMode = Enter
ns.ExitEditMode = Exit
ns.ToggleEditMode = Toggle
ns.IsEditMode = function() return active end
ns.WatchEditMode = WatchEditMode
