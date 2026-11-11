-- UIF_PreviewDrag - the preview strip as an editor: grab a piece of the
-- sample (a text, an icon, a bar) and drag it, nudge it, resize it, and
-- the same setting its slider writes changes.
-- Part of ZacUI; load order is set by the TOC (after UIF_EditMode: built
-- from UI.* and the customization standard's helpers).
--
-- A PAGE OPTS IN by wrapping its preview spec, nothing else changes:
--
--   L:Preview(ns.PreviewDrag.Attach(spec, {
--       pieces = function(canvas, P)          -- after every update
--           return {
--               { key = "name", label = "Name", region = sample.Name,
--                 anchor = { get = ag, set = as, defaults = function() return D end } },
--               { key = "combat", label = "Combat icon", region = sample.Combat,
--                 anchor = { ... },
--                 size = { get = function() return w, h end,        -- the setting's value
--                          set = function(w, h) end,                -- nil = that side not dragged
--                          square = true, min = 6, max = 40,
--                          reset = function() end } },             -- optional (menu Reset)
--               { key = "buffs", label = "Buffs", region = { icon1, icon2 },   -- a union
--                 move = { get = function() return x, y end, set = function(x, y) end,
--                          reset = function() end } },
--           }, sample                                -- the frame pieces snap to
--       end,
--   }))
--
-- piece.region: a region, or a list of regions (their union). Kinds:
--   anchor  ZacUI's anchor spec (UIF_Custom): a drag writes x / y through
--           `set` (a copy of the spec; a coordinate equal to what nil gives
--           is left out, so a piece dragged back home leaves no spec);
--           the menu's Anchor point writes `point`.
--   move    plain x / y keys: set(x + dx, y + dy). move.eff() names the
--           scale of one unit when it is not the region's (a HUD mover's
--           offsets are UIParent units); move.snapshot() / restore(v) put
--           an unset store back to unset on undo.
--   size    width / height (or one size: square); grips on the right edge,
--           the bottom edge and the corner. A value <= 0 or nil
--           ("automatic") starts from what the piece draws;
--           size.snapshot() / restore(v) when undo needs more than the
--           two values back (a bar's rows worked out from its width).
--           size.fit(w, h) -> w, h: the size the piece would really take
--           (a bar's grid: whole columns / rows), so the outline shows it.
--   reorder (phase 3) items of a row: PD.OrderPieces(group) makes them;
--           ns.OrderedList(list, saved, keyOf) is the features' side.
-- piece.pick: the element key the page's click-to-pick handler knows
-- (default piece.key), or piece.open = function() for a piece that handler
-- does not know; piece.noMove: resize only. piece.carry: the region(s) a
-- drag shifts for the eye when that is not the piece's regions (a HUD
-- piece: the sample anchor its icons hang off).
--
-- THE GESTURES: hover = outline (on the piece's drawn rect: a text's ink,
-- not its box) + tooltip; drag (after 3 px) = the piece and its outline
-- follow the cursor, its edges and centre snap (under 6 screen px) to the
-- frame's and to the ONE nearest other piece's (EllesmereUI's unlock mode
-- snaps to the closest element only: a crowded HUD does not fight the
-- cursor), a 1-physical-pixel guide at each snap, the piece it snaps to
-- outlined; whole real pixels always, Shift = no magnets; release = ONE
-- write and the piece stays selected; click = select; arrow keys nudge
-- the selected piece (else the hovered one) 1 px (Shift: 5); Escape puts
-- a drag back; right-click = menu (reset, anchor point, open its
-- settings, undo, reset layout); Ctrl+Z = undo while the window is open.
-- Nothing is written before a drag ends; a button let go where the client
-- never said so (outside the game window) ends it where the cursor was.
-- Combat: nothing moves, a one-line notice says why, a drag in progress
-- is put back.
-- HANDLES are pooled per piece key: after an update (an undo, a slider)
-- the handle under the cursor still carries the piece that is there.
--
-- UNITS: rects are read in screen pixels and the result is divided by the
-- region's own effective scale, so an offset is in the real frame's units
-- whatever the strip's fit, the game scale, the window's size or a sample
-- scale. Settings are never multiplied by a preview scale.
--
-- NOTHING IS MADE AT LOAD: the first page that attaches pieces makes its
-- layer; the keyboard frame and the combat watcher come with it. Handles
-- live on a layer beside the canvas (on the strip's sample box), so the
-- canvas's own measurements never see them, and it shows and hides with
-- its canvas. A handle has an OnUpdate only between mouse down and up.
-- Only the samples' geometry is read (mock data, never a live or protected
-- frame), every read pcall'd: secret-safe on Forever.

local ADDON_NAME, ns = ...

local UI = ns.UI
local GetColor = ns.GetColor
local Custom = ns.Custom

local type, pairs, ipairs, pcall, tonumber = type, pairs, ipairs, pcall, tonumber
local math_abs, math_floor, math_max, math_min = math.abs, math.floor, math.max, math.min

local FLAT = ns.FLAT or "Interface\\Buttons\\WHITE8X8"

local PD = { stats = { writes = 0, drags = 0, undos = 0 }, decls = {}, layers = {}, undo = {}, redo = {},
    stale = setmetatable({}, { __mode = "k" }) }

local DRAG_START = 3       -- screen px before a press becomes a drag
local SNAP = 6             -- screen px: the magnets' reach (a line nearer than this)
local GUIDE_ALPHA = 0.5    -- the snap guides (EllesmereUI's: accent, 0.5, one physical px)
local TARGET_ALPHA = 0.5   -- the outline on the piece a drag snaps to
local HOME = 3             -- screen px: dropped this close to where it started, it stays
local NUDGE, NUDGE_BIG = 1, 5
local UNDO_MAX = 40
local NUDGE_JOIN = 3       -- s: nudges of one piece this close are one undo step
local LAYER_LEVEL = 9200   -- above the samples (FitStrata keeps them at 9000 or below)
local GRIP = 6             -- layer units: the resize grips' thickness
local MIN_HANDLE = 8       -- layer units: the smallest handle
local NOTICE = "Dragging in the preview waits for combat to end."
local POINTS = ns.ANCHOR_POINTS or { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local POINT_LABEL = { TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right", LEFT = "Left", CENTER = "Centre",
    RIGHT = "Right", BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right" }
local ANCHOR_FIELDS = { "point", "relPoint", "x", "y", "to", "justify", "point2", "relPoint2", "x2", "y2", "to2", "fill" }

local hover, selected, drag, press
local PieceRectOf
local keyFrame, events, refreshSoon

-- ============================================================
-- SMALL THINGS
-- ============================================================
-- The two switches on the layer's Layout button, window state like the
-- strip's height (ZacUIDB.config.preview: dragOff, dragNoGuides; nil = on)
local function Prefs()
    local st = ns.ConfigState and ns.ConfigState()
    if type(st) ~= "table" then return {} end
    st.preview = st.preview or {}
    return st.preview
end
function PD.Enabled() return not Prefs().dragOff end
local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function Shift() local f = _G.IsShiftKeyDown return (f and f()) and true or false end
local function Ctrl() local f = _G.IsControlKeyDown return (f and f()) and true or false end
local function Alt() local f = _G.IsAltKeyDown return (f and f()) and true or false end
local function Cursor()
    local f = _G.GetCursorPosition
    if not f then return 0, 0 end
    local x, y = f()
    return tonumber(x) or 0, tonumber(y) or 0
end
local function Now() return GetTime and GetTime() or 0 end
local function Round(v) return math_floor(v + 0.5) end
local function Copy(t) return Custom and Custom.Copy and Custom.Copy(t) or t end
local function Clean(t) if Custom and Custom.Clean then return Custom.Clean(t) end return t end

local function IsRegion(r) return type(r) == "table" and type(r.GetLeft) == "function" end
local function Regions(piece)
    local r = piece and piece.region
    if IsRegion(r) then return { r } end
    if type(r) == "table" then return r end
    return {}
end

local function Eff(r)
    local ok, s = pcall(function()
        if r.GetEffectiveScale then return r:GetEffectiveScale() end
        local p = r.GetParent and r:GetParent()
        return p and p:GetEffectiveScale()
    end)
    if ok and type(s) == "number" and s > 0 then return s end
    return 1
end

-- one physical pixel in screen px (the cursor's units: 768 tall), and in
-- a frame's own units. The handles, outlines and guides are window chrome:
-- one physical pixel whatever the look, the fit or the UI scale (one UI
-- unit at a fit of 0.92 is 0.92 px and flickers between 0 and 1 rows).
local function Physical()
    local ok, v = pcall(function()
        local f = _G.GetPhysicalScreenSize
        if not f then return 1 end
        local _, ph = f()
        if type(ph) == "number" and ph > 0 then return 768 / ph end
        return 1
    end)
    return (ok and type(v) == "number") and v or 1
end
local function OnePx(f) return Physical() / Eff(f) end
-- a screen px position on the physical pixel grid
local function OnGrid(v)
    local p = Physical()
    return math_floor(v / p + 0.5) * p
end

-- the box a FontString's text really fills, inside its own rect (l, b, r,
-- t screen px): a name with room for 20 letters showing 6 is only those
-- 6 letters wide. Its justification places the ink. Any doubt (a secret
-- on Forever, no metrics): the whole rect.
local JH = { LEFT = 0, CENTER = 0.5, RIGHT = 1 }
local JV = { TOP = 1, MIDDLE = 0.5, BOTTOM = 0 }
local function Ink(r, s, l, b, rr, t)
    local ok, il, ib, ir, it = pcall(function()
        local tw, th = r:GetStringWidth(), r:GetStringHeight()
        if type(tw) ~= "number" or type(th) ~= "number" then return nil end
        tw, th = tw * s, th * s
        local w, h = rr - l, t - b
        local nl, nr, nb, nt = l, rr, b, t
        if tw > 0 and tw < w - 0.5 then
            local fx = JH[r.GetJustifyH and r:GetJustifyH() or "CENTER"] or 0.5
            nl = l + (w - tw) * fx
            nr = nl + tw
        end
        if th > 0 and th < h - 0.5 then
            local fy = JV[r.GetJustifyV and r:GetJustifyV() or "MIDDLE"] or 0.5
            nb = b + (h - th) * fy
            nt = nb + th
        end
        return nl, nb, nr, nt
    end)
    if ok and il then return il, ib, ir, it end
    return l, b, rr, t
end

-- l, b, r, t in screen pixels; nil for a region hidden, empty or unplaced
-- (a FontString: the ink of its text)
local function RegionRect(r)
    local ok, l, b, rr, t = pcall(function()
        if not r:IsVisible() then return nil end
        local fs = r.GetObjectType and r:GetObjectType() == "FontString"
        if fs then
            local s = r:GetText()
            if not s or s == "" then return nil end
        end
        local s = Eff(r)
        local l, b, rr, t = r:GetLeft(), r:GetBottom(), r:GetRight(), r:GetTop()
        if not (l and b and rr and t) then return nil end
        l, b, rr, t = l * s, b * s, rr * s, t * s
        if fs then return Ink(r, s, l, b, rr, t) end
        return l, b, rr, t
    end)
    if not ok or not l or rr - l <= 0 or t - b <= 0 then return nil end
    return l, b, rr, t
end
local function PieceRect(piece)
    local L, B, R, T
    for _, r in ipairs(Regions(piece)) do
        if IsRegion(r) then
            local l, b, rr, t = RegionRect(r)
            if l then
                L, B = math_min(L or l, l), math_min(B or b, b)
                R, T = math_max(R or rr, rr), math_max(T or t, t)
            end
        end
    end
    return L, B, R, T
end

-- does `other` hang off `region` (it moves with it: not a magnet)?
local function HangsOff(other, region)
    if other == region then return true end
    local dep = Custom and Custom.DependsOn
    if not dep then return false end
    local ok, hit = pcall(dep, other, region)
    return ok and hit or false
end

-- ============================================================
-- ORDER (a list the user may reorder; nil saved = the list as it is)
-- ============================================================
-- ns.OrderedList(list, saved, keyOf) -> the list in the saved order:
-- the items the saved list names in its order, every other item next to
-- the item it follows in `list` (a new or unsaved one keeps its place).
-- No saved order = `list` itself, untouched and not copied. Called on
-- layout only (it allocates).
local function KeyOfSelf(v) return v end
function ns.OrderedList(list, saved, keyOf)
    if type(list) ~= "table" or type(saved) ~= "table" or #saved == 0 then return list end
    keyOf = keyOf or KeyOfSelf
    local rank = {}
    for i, k in ipairs(saved) do if rank[k] == nil then rank[k] = i end end
    local out, at = {}, {}
    local named = {}
    for i, it in ipairs(list) do
        local k = keyOf(it)
        if k ~= nil and rank[k] then named[#named + 1] = { it = it, r = rank[k], i = i } end
    end
    table.sort(named, function(a, b) if a.r ~= b.r then return a.r < b.r end return a.i < b.i end)
    for _, e in ipairs(named) do out[#out + 1] = e.it end
    for i, it in ipairs(list) do
        local k = keyOf(it)
        if k == nil or not rank[k] then
            local pos = 0
            for j = i - 1, 1, -1 do
                local prev = list[j]
                for n = 1, #out do if out[n] == prev then pos = n break end end
                if pos > 0 then break end
            end
            table.insert(out, pos + 1, it)
        end
    end
    for i = 1, #out do at[i] = out[i] end
    return at
end

-- a reorder group's keys as shown now (its items' order)
local function ShownKeys(group)
    local out = {}
    for _, it in ipairs(group.items or {}) do out[#out + 1] = it.key end
    return out
end

-- the whole saved list for a new shown order: the old saved order (or the
-- default) with the shown keys' places refilled in their new order, so a
-- key not on show keeps its place. nil when that is the default order.
local function SavedFor(group, shown)
    local def = type(group.defaults) == "function" and group.defaults() or group.defaults or {}
    local full = {}
    for i, k in ipairs(ns.OrderedList(def, group.get(), KeyOfSelf)) do full[i] = k end
    local want, seen = {}, {}
    for _, k in ipairs(shown) do want[k] = true end
    local j = 1
    for i, k in ipairs(full) do
        if want[k] then full[i] = shown[j] seen[shown[j]] = true j = j + 1 end
    end
    for _, k in ipairs(shown) do if not seen[k] then full[#full + 1] = k end end
    local same = #full == #def
    if same then for i = 1, #def do if full[i] ~= def[i] then same = false break end end end
    if same then return nil end
    return full
end

local function WriteOrder(group, shown)
    local cur = ShownKeys(group)
    local changed = #cur ~= #shown
    if not changed then for i = 1, #cur do if cur[i] ~= shown[i] then changed = true break end end end
    if not changed then return nil end
    local old = Copy(group.get())
    local new = SavedFor(group, shown)
    local again = Copy(new)
    group.set(new)
    return function() group.set(Copy(old)) end, function() group.set(Copy(again)) end
end

-- A declaration's row of reorderable items as pieces: group = { key,
-- label, items = { { key, label, region }, ... } (in the order shown),
-- get (the saved list or nil), set (a list or nil), defaults (the keys in
-- today's order, or a function giving them), axis = "x" | "y" | "grid",
-- pick } ("-y": a stack that grows up, its first item at the bottom).
-- Every item is a handle of its own.
function PD.OrderPieces(group, out)
    out = out or {}
    for _, it in ipairs(group.items or {}) do
        out[#out + 1] = { key = tostring(group.key) .. ":" .. tostring(it.key), label = it.label or tostring(it.key),
            region = it.region, reorder = group, item = it.key, pick = group.pick }
    end
    return out
end

-- ============================================================
-- THE LAYER AND ITS HANDLES
-- ============================================================
local function Paint(h)
    if not h.edges then return end
    local mine = (h == hover) or (h == selected) or (drag and drag.h == h)
    local target = not mine and drag and drag.snapH == h
    local on = mine or target
    local c = GetColor("ui", "accent")
    local a = target and TARGET_ALPHA or ((h == selected and h ~= hover and not (drag and drag.h == h)) and 0.7 or 1)
    for _, t in ipairs(h.edges) do
        t:SetVertexColor(c.r, c.g, c.b, a)
        t:SetShown(on and true or false)
    end
    local grips = h.piece and h.piece.size and not drag and on
    for _, g in pairs(h.grips) do
        if g.dot then
            g.dot:SetVertexColor(c.r, c.g, c.b, 1)
            g.dot:SetShown(grips and true or false)
        end
    end
end

local function ShowKeys()
    if not keyFrame then return end
    local want = not InCombat() and (hover ~= nil or selected ~= nil or drag ~= nil or #PD.undo > 0 or #PD.redo > 0)
    if want and not keyFrame:IsShown() then
        if keyFrame.SetPropagateKeyboardInput then keyFrame:SetPropagateKeyboardInput(true) end
        keyFrame:Show()
    elseif not want and keyFrame:IsShown() then
        keyFrame:Hide()
    end
end

-- the hand the client shows over something it can pick up: over a piece
-- (not in combat, when nothing moves), back to the arrow off it
local HAND = "Interface\\CURSOR\\Pickup"
local handOn = false
local function Hand(on)
    on = on and not InCombat() and true or false
    -- (said again on every enter: the client may have put its own cursor
    -- up since - a menu, the tooltip's owner, another frame's)
    if on then
        handOn = true
        if _G.SetCursor then pcall(_G.SetCursor, HAND) end
        return
    end
    if not handOn then return end
    handOn = false
    if _G.ResetCursor then pcall(_G.ResetCursor) end
end
PD.HandShown = function() return handOn end

local function SetHover(h)
    -- (entered again - from its own grip, or a frame the client put over
    -- it and took away - the hand is said again all the same)
    if hover == h then
        if h then Hand(true) end
        return
    end
    local old = hover
    hover = h
    -- (a drag keeps the hand until it ends)
    if h then Hand(true) elseif not drag then Hand(false) end
    if old then Paint(old) end
    if h then Paint(h) end
    ShowKeys()
end
local function Select(h)
    local old = selected
    selected = h
    if old and old ~= h then Paint(old) end
    if h then Paint(h) end
    ShowKeys()
end

local function Notice(L, on)
    if on and not L.notice then
        L.notice = UI.Font(L, UI.F.SMALL, { text = NOTICE, cat = "text", key = "orange" })
        L.notice:SetPoint("BOTTOMLEFT", L, "BOTTOMLEFT", 3, 2)
        L.notice:SetWordWrap(false)
    end
    if L.notice then L.notice:SetShown(on and true or false) end
end

local function Guides(L)
    if L.gx then return L.gx, L.gy end
    local c = GetColor("ui", "accent")
    L.gx = L:CreateTexture(nil, "OVERLAY", nil, 6)
    L.gx:SetTexture(FLAT)
    L.gx:SetVertexColor(c.r, c.g, c.b, GUIDE_ALPHA)
    L.gx:SetWidth(1)
    L.gx:Hide()
    L.gy = L:CreateTexture(nil, "OVERLAY", nil, 6)
    L.gy:SetTexture(FLAT)
    L.gy:SetVertexColor(c.r, c.g, c.b, GUIDE_ALPHA)
    L.gy:SetHeight(1)
    L.gy:Hide()
    return L.gx, L.gy
end
-- a guide at screen x (vertical) / screen y (horizontal); nil hides it.
-- One physical pixel thick, on the pixel grid (it does not shimmer as the
-- piece moves). xr / yr = { from, to } (screen px): the guide spans only
-- that (a reorder's slot: the row it lands in), else the whole sample box.
local function ShowGuides(L, sx, sy, xr, yr)
    if Prefs().dragNoGuides then sx, sy = nil, nil end
    if not L.gx and not sx and not sy then return end
    local gx, gy = Guides(L)
    local le = Eff(L)
    local one = OnePx(L)
    local left, bottom = L:GetLeft() or 0, L:GetBottom() or 0
    -- (re-placed only when it moves: no per-frame anchor churn)
    local kx = sx and (OnGrid(sx) .. ":" .. (xr and (xr[1] .. "," .. xr[2]) or "")) or nil
    local ky = sy and (OnGrid(sy) .. ":" .. (yr and (yr[1] .. "," .. yr[2]) or "")) or nil
    if kx ~= L.gxAt then
        L.gxAt = kx
        gx:ClearAllPoints()
        if sx then
            local x = OnGrid(sx) / le - left
            -- (its left edge on the grid line: the strip covers one pixel column)
            if xr then
                gx:SetPoint("BOTTOMLEFT", L, "BOTTOMLEFT", x, xr[1] / le - bottom)
                gx:SetHeight(math_max(one, (xr[2] - xr[1]) / le))
            else
                gx:SetPoint("TOPLEFT", L, "TOPLEFT", x, 0)
                gx:SetPoint("BOTTOMLEFT", L, "BOTTOMLEFT", x, 0)
            end
            gx:SetWidth(one)
        end
    end
    gx:SetShown(sx ~= nil)
    if ky ~= L.gyAt then
        L.gyAt = ky
        gy:ClearAllPoints()
        if sy then
            local y = OnGrid(sy) / le - bottom
            if yr then
                gy:SetPoint("BOTTOMLEFT", L, "BOTTOMLEFT", yr[1] / le - left, y)
                gy:SetWidth(math_max(one, (yr[2] - yr[1]) / le))
            else
                gy:SetPoint("BOTTOMLEFT", L, "BOTTOMLEFT", 0, y)
                gy:SetPoint("BOTTOMRIGHT", L, "BOTTOMRIGHT", 0, y)
            end
            gy:SetHeight(one)
        end
    end
    gy:SetShown(sy ~= nil)
end

-- forward
local Press, Release, Menu, Tip

local function NewGrip(h, mode)
    local g = CreateFrame("Button", nil, h)
    g:EnableMouse(true)
    g.mode, g._zHandle = mode, h
    local dot = g:CreateTexture(nil, "OVERLAY", nil, 7)
    dot:SetTexture(FLAT)
    dot:SetSize(3, 3)
    dot:SetPoint("CENTER")
    dot:Hide()
    g.dot = dot
    g:SetScript("OnEnter", function(self) SetHover(self._zHandle) end)
    g:SetScript("OnLeave", function() SetHover(nil) end)
    g:SetScript("OnMouseDown", function(self, button) Press(self._zHandle, button, self.mode) end)
    g:SetScript("OnMouseUp", function(self, button) Release(self._zHandle, button) end)
    -- (on the piece's drawn edges - the box - not the handle, which may
    -- be bigger than a small piece)
    local box = h.box
    if mode == "right" then
        g:SetPoint("TOPLEFT", box, "TOPRIGHT", -GRIP / 2, -GRIP / 2)
        g:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", GRIP / 2, GRIP / 2)
    elseif mode == "bottom" then
        g:SetPoint("TOPLEFT", box, "BOTTOMLEFT", GRIP / 2, GRIP / 2)
        g:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -GRIP / 2, -GRIP / 2)
    else
        g:SetSize(GRIP, GRIP)
        g:SetPoint("CENTER", box, "BOTTOMRIGHT", 0, 0)
    end
    return g
end

local function NewHandle(L)
    local h = CreateFrame("Button", nil, L)
    h:EnableMouse(true)
    h._zLayer = L
    -- the piece's own rect (the handle itself is at least MIN_HANDLE, so a
    -- 4 px icon can still be grabbed): the outline and the grips sit on it
    local box = CreateFrame("Frame", nil, h)
    box:SetPoint("CENTER")
    box:SetSize(MIN_HANDLE, MIN_HANDLE)
    h.box = box
    h.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = box:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(FLAT)
        t._zSide = side
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT") t:SetPoint(side .. "RIGHT") t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side) t:SetPoint("BOTTOM" .. side) t:SetWidth(1)
        end
        t:Hide()
        h.edges[#h.edges + 1] = t
    end
    h.grips = { right = NewGrip(h, "right"), bottom = NewGrip(h, "bottom"), corner = NewGrip(h, "corner") }
    h:SetScript("OnEnter", function(self)
        SetHover(self)
        if not drag then Tip(self) end
    end)
    h:SetScript("OnLeave", function()
        SetHover(nil)
        if GameTooltip then GameTooltip:Hide() end
    end)
    h:SetScript("OnMouseDown", function(self, button) Press(self, button, "move") end)
    h:SetScript("OnMouseUp", function(self, button) Release(self, button) end)
    h:SetScript("OnHide", function(self)
        if (press and press.h == self) or (drag and drag.h == self) then PD.Cancel() end
        if hover == self then SetHover(nil) end
    end)
    return h
end

local function TopWindow(f)
    local p = f
    for _ = 1, 30 do
        local up = p and p.GetParent and p:GetParent()
        if not up or up == UIParent then return p end
        p = up
    end
    return p
end

local function EnsureWatch(L)
    if not events then
        events = CreateFrame("Frame")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:SetScript("OnEvent", function(_, ev)
            local fight = (ev == "PLAYER_REGEN_DISABLED")
            if fight then PD.Cancel() Hand(false) end
            for _, layer in pairs(PD.layers) do Notice(layer, fight and layer:IsVisible()) end
            ShowKeys()
        end)
    end
    if not keyFrame then
        local win = TopWindow(L)
        -- the window closing: no drag, hover, hand or selection outlives
        -- it, and the history goes (said on the window itself: the key
        -- frame is not always up to hear it)
        if win and win.HookScript and win ~= L then
            win:HookScript("OnHide", function()
                PD.Cancel()
                if hover then SetHover(nil) end
                Hand(false)
                if selected then Select(nil) end
                PD.undo, PD.redo = {}, {}
                ShowKeys()
            end)
        end
        keyFrame = CreateFrame("Frame", nil, win)
        keyFrame:EnableKeyboard(true)
        if keyFrame.SetPropagateKeyboardInput then keyFrame:SetPropagateKeyboardInput(true) end
        keyFrame:Hide()
        keyFrame:SetScript("OnKeyDown", function(self, key) PD.Key(key) end)
        -- the window closed: the history and the selection go with it
        keyFrame:SetScript("OnHide", function(self)
            local p = self:GetParent()
            if p and not p:IsShown() then
                PD.undo, PD.redo = {}, {}
                selected = nil
            end
        end)
        PD.keyFrame = keyFrame
    end
end

-- THE FIRST-USE HINTS (finish pass, Tutorial_Hints bookkeeping): a line
-- under every sample until the first drag or click on a piece, and an
-- accent dot on the Layout button until its menu is first opened.
-- (the drag hint is written down when the settings window closes, not in
-- the middle of a drag: a step and its undo leave the save as it was)
local learned = false
local function HintsSeen(id)
    local H = ns.Hints
    if id == "preview_drag" and learned then return true end
    return not H or H.Seen(id)
end
local function Learned()
    local H = ns.Hints
    if not H or HintsSeen("preview_drag") then return end
    learned = true
    local win = _G.ZacUIConfigFrame
    if win and win.HookScript and not PD._zHintHook then
        PD._zHintHook = true
        win:HookScript("OnHide", function()
            if learned and ns.Hints then ns.Hints.Mark("preview_drag") end
        end)
    elseif not win then
        H.Mark("preview_drag")
    end
    for _, L in pairs(PD.layers) do
        local t = L.hint
        if t and t:IsShown() then
            -- gone: its band at the sample box's foot goes with it (the
            -- strip is laid out again, the sample gets the room back)
            local function Gone()
                t:Hide()
                local PV = ns.ConfigPreview
                if PV and PV.Place then pcall(PV.Place) end
            end
            if ns.Motion and ns.Motion.FadeTo then
                pcall(ns.Motion.FadeTo, t, 0, { duration = 0.4 })
                if C_Timer and C_Timer.After then C_Timer.After(0.45, Gone) else Gone() end
            else
                Gone()
            end
        end
    end
end
PD.Learned = Learned
local function ShowHint(L)
    if not L.hint then return end
    L.hint:SetShown(PD.Enabled() and not HintsSeen("preview_drag"))
    if L.hint:IsShown() then L.hint:SetAlpha(1) end
end

-- THE HINT'S BAND (2026-11-08, Zac: "overlap here looks bad" - the line
-- ran across the Warrior HUD's sample): while the first-use hint shows,
-- the strip keeps a band that tall along the sample box's foot and fits
-- the sample above it (ConfigPreview.FootFor), so the line never covers a
-- piece. The hint goes after the first drag or click, and the band with it.
local HINT_FOOT = 15        -- before the hint is made: one small line
function PD.FootFor(key)
    if not (ns.Hints and PD.Enabled()) or HintsSeen("preview_drag") then return 0 end
    if not (PD.decls[key] or PD.Declared(key)) then return 0 end
    local L = PD.layers[key]
    local t = L and L.hint
    local h = t and t.GetStringHeight and tonumber(t:GetStringHeight()) or nil
    return (h and h > 0) and math_floor(h + 6.5) or HINT_FOOT
end
local function InstallFoot()
    local PV = ns.ConfigPreview
    if PV and PV.FootFor ~= PD.FootFor then PV.FootFor = PD.FootFor end
end
PD.InstallFoot = InstallFoot

local function Layer(key, canvas)
    local L = PD.layers[key]
    if L then return L end
    InstallFoot()
    local view = canvas:GetParent() or canvas
    L = CreateFrame("Frame", nil, view)
    L:SetAllPoints(view)
    L:SetFrameLevel(LAYER_LEVEL)
    L.key, L.canvas, L.handles = key, canvas, {}
    PD.layers[key] = L
    canvas:HookScript("OnShow", function() if PD.decls[key] then L:Show() end end)
    -- gone (the canvas, or the window over it): no hover, no hand. Said
    -- here, not left to the handles' own OnHide - the layer hides inside
    -- the window's hide, and its handles may never hear of it.
    local function Gone()
        if (drag and drag.h._zLayer == L) or (press and press.h._zLayer == L) then PD.Cancel() end
        if hover and hover._zLayer == L then SetHover(nil) end
    end
    canvas:HookScript("OnHide", function()
        Gone()
        L:Hide()
    end)
    L:SetScript("OnHide", Gone)
    L:SetShown(canvas:IsShown())
    EnsureWatch(L)
    PD.LayoutButton(L)
    if ns.Hints and UI.Font then
        L.hint = UI.Font(L, UI.F.SMALL, { cat = "text", key = "gray",
            text = "Drag a piece to move it. Click selects (arrow keys nudge), right-click for more." })
        L.hint:SetPoint("BOTTOMLEFT", L, "BOTTOMLEFT", 6, 3)
        L.hint:SetPoint("RIGHT", L, "RIGHT", -6, 0)
        L.hint:SetJustifyH("LEFT")
        L.hint:SetWordWrap(false)
        ShowHint(L)
    end
    return L
end

-- ============================================================
-- SYNC: the handles over this update's pieces
-- ============================================================
local function Area(piece)
    local l, b, r, t = PieceRect(piece)
    if not l then return -1 end
    return (r - l) * (t - b)
end

-- the handle (at least MIN_HANDLE) and its box (exactly the rect) over
-- l, b, r, t (screen px). `follow`: a single region the handle rides (a
-- castbar sliding in carries its handle), offset to the rect's centre.
local function PlaceRect(L, h, l, b, r, t, follow)
    local le = Eff(L)
    local w, hh = (r - l) / le, (t - b) / le
    h:ClearAllPoints()
    local cx, cy = (l + r) / 2, (b + t) / 2
    local placed = false
    if follow then
        local ok, fl, fb, fr, ft = pcall(function()
            local s = Eff(follow)
            return follow:GetLeft() * s, follow:GetBottom() * s, follow:GetRight() * s, follow:GetTop() * s
        end)
        if ok and fl then
            h:SetPoint("CENTER", follow, "CENTER", (cx - (fl + fr) / 2) / le, (cy - (fb + ft) / 2) / le)
            placed = true
        end
    end
    if not placed then
        h:SetPoint("CENTER", L, "BOTTOMLEFT", cx / le - (L:GetLeft() or 0), cy / le - (L:GetBottom() or 0))
    end
    h:SetSize(math_max(MIN_HANDLE, w), math_max(MIN_HANDLE, hh))
    h.box:SetSize(math_max(0.1, w), math_max(0.1, hh))
    -- the outline: one physical pixel
    local one = OnePx(h)
    if h._zOne ~= one then
        h._zOne = one
        for _, e in ipairs(h.edges) do
            if e._zSide == "TOP" or e._zSide == "BOTTOM" then e:SetHeight(one) else e:SetWidth(one) end
        end
    end
end

local function PlaceHandle(L, h, piece)
    local l, b, r, t = PieceRect(piece)
    if not l then h:Hide() return false end
    local regs = Regions(piece)
    PlaceRect(L, h, l, b, r, t, (#regs == 1 and IsRegion(regs[1])) and regs[1] or nil)
    local sized = piece.size ~= nil
    for mode, g in pairs(h.grips) do
        local on = sized and (mode == "corner" or mode == "right" or mode == "bottom")
        if sized and piece.size.axis == "x" then on = (mode == "right") end
        if sized and piece.size.axis == "y" then on = (mode == "bottom") end
        g:SetShown(on and true or false)
    end
    h:Show()
    return true
end

function PD.Sync(key, canvas, P)
    local decl = PD.decls[key]
    if not (decl and canvas) then return end
    local L = Layer(key, canvas)
    L.P = P
    ShowHint(L)
    local list, container
    if type(decl.pieces) == "function" then
        local ok, a, b = pcall(decl.pieces, canvas, P)
        if ok then list, container = a, b end
    end
    L.container = container
    L.pieces = type(list) == "table" and list or {}
    -- switched off on the Layout button: no handles (the button stays)
    if not PD.Enabled() then L.pieces = {} end
    -- the sample is drawn again: where its pieces sit is the truth again
    for r in pairs(PD.stale) do PD.stale[r] = nil end
    -- smaller pieces above bigger ones (a text over the bar it sits on)
    local order = {}
    for i, piece in ipairs(L.pieces) do order[i] = { piece = piece, area = Area(piece) } end
    -- (a tie: a reorder item above an anchored piece of the same size)
    table.sort(order, function(a, b)
        if a.area ~= b.area then return a.area > b.area end
        return (a.piece.reorder and 1 or 0) < (b.piece.reorder and 1 or 0)
    end)
    -- THE POOL, BY PIECE KEY: a piece gets the handle it had last time
    -- (the one under the cursor, hovered or selected, stays that piece's
    -- after an undo or a slider re-laid the sample); a new piece takes a
    -- free one. Frame levels by size: smaller above bigger, and a piece's
    -- grips just above its own handle (never over a smaller piece: a text
    -- near the frame's edge is the text's, not the frame's resize grip).
    local mine, taken = {}, {}
    for _, h in ipairs(L.handles) do
        local k = h._zKey
        if k ~= nil and mine[k] == nil then mine[k] = h end
    end
    local want = {}
    for _, it in ipairs(order) do
        if it.area > 0 then
            local h = mine[it.piece.key]
            if h and not taken[h] then taken[h] = true it.h = h end
            want[#want + 1] = it
        end
    end
    local free = {}
    for _, h in ipairs(L.handles) do if not taken[h] then free[#free + 1] = h end end
    local nextFree = 1
    for i, it in ipairs(want) do
        local h = it.h
        if not h then
            h = free[nextFree]
            nextFree = nextFree + 1
            if not h then
                h = NewHandle(L)
                L.handles[#L.handles + 1] = h
            end
            it.h = h
            taken[h] = true
        end
        h.piece, h._zKey = it.piece, it.piece.key
        h:SetFrameLevel(LAYER_LEVEL + 2 * i)
        for _, g in pairs(h.grips) do g:SetFrameLevel(LAYER_LEVEL + 2 * i + 1) end
        PlaceHandle(L, h, it.piece)
        Paint(h)
    end
    for _, h in ipairs(L.handles) do
        if not taken[h] then
            h.piece = nil
            h:Hide()
        end
    end
    -- an update while a piece is being dragged put it back: carry it again
    if drag and drag.h._zLayer == L then
        local again
        for _, it in ipairs(want) do
            if it.piece.key == drag.piece.key then again = it.h end
        end
        if again then
            drag.h, drag.piece = again, again.piece
            PD.CaptureBase(drag)
            PD.Lines(drag)
            PD.ApplyTemp(drag)
        else
            PD.Cancel()
        end
    end
    if selected and selected._zLayer == L and not selected.piece then Select(nil) end
    -- the hovered handle still under the cursor: its tooltip says what is
    -- there now (or it goes, with the piece)
    if hover and hover._zLayer == L then
        if not hover.piece then
            SetHover(nil)
            if GameTooltip then GameTooltip:Hide() end
        elseif not drag and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(hover) then
            Tip(hover)
        end
    end
    L:SetShown(canvas:IsShown())
    Notice(L, InCombat())
end

-- ============================================================
-- WRITES (always through the page's setters) AND UNDO
-- ============================================================
local function Def(a)
    local d = a and a.defaults
    if type(d) == "function" then d = d() end
    return type(d) == "table" and d or nil
end

local function Same(a, b) return math_abs((a or 0) - (b or 0)) < 1e-6 end

-- two snapshots alike (plain values and tables of them, a few levels)
local function SameValue(a, b, depth)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" or (depth or 0) > 6 then return false end
    for k, v in pairs(a) do if not SameValue(v, b[k], (depth or 0) + 1) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- a copy of `old` moved by (ux, uy), with a coordinate nil would give left out
-- `at`: the region's points as they really sit ({ point, relPoint, x, y }
-- each). When it is the point the spec resolves to, its offset is the
-- base (a piece some code placed off its default - a stacked minimap pill
-- - lands where it was dropped, not at the default plus the drag).
local function MovedSpec(old, def, ux, uy, at)
    local p, rp, cx, cy = ns.ResolveAnchor(old, def)
    -- (a relPoint the spec does not set is the live default's, whatever the
    -- page's defaults table says: the buff tracker's row name hangs off
    -- the row icon's RIGHT while one shows)
    -- (`at` lists every point the region has: the one named like the
    -- spec's point is the base, whatever order the client lists them in)
    if type(at) == "table" then
        local hit
        for _, q in ipairs(at) do if q[1] == p then hit = q end end
        at = hit
    end
    local relOk = at and (at[2] == rp or type(old) ~= "table" or old.relPoint == nil)
    if at and at[1] == p and relOk and tonumber(at[3]) and tonumber(at[4]) then
        cx, cy = at[3], at[4]
    end
    local new = Copy(old) or {}
    local nx, ny = cx + ux, cy + uy
    new.x, new.y = nil, nil
    local _, _, rx, ry = ns.ResolveAnchor(new, def)
    if not Same(rx, nx) then new.x = nx end
    if not Same(ry, ny) then new.y = ny end
    return Clean(new)
end

-- keep: a redo putting its step back (the redo history is kept); else a
-- new step, which drops the redo history
local function PushUndo(entry, keep)
    local u = PD.undo
    u[#u + 1] = entry
    while #u > UNDO_MAX do table.remove(u, 1) end
    if not keep then PD.redo = {} end
    ShowKeys()
end

local function Changed()
    PD.stats.writes = PD.stats.writes + 1
    if ns.SettingsChanged then ns.SettingsChanged("drag") end
    -- the page's sliders and pickers read the new value (the strip's
    -- update is already asked for: still one update)
    if ns.RefreshConfig then ns.RefreshConfig() end
end

-- -> the undo function, or nil when nothing changed
-- the first point of a piece's (single) region: { point, relPoint, x, y }
-- the points of a piece's (single) region: { { point, relPoint, x, y }, ... }
local function FirstPoint(piece, pts)
    local out = {}
    if pts then
        for i, q in ipairs(pts) do out[i] = { q[1], q[3], q[4], q[5] } end
        return out
    end
    local regs = Regions(piece)
    local r = regs[1]
    if #regs ~= 1 or not IsRegion(r) then return nil end
    -- written since the sample was last drawn: where it sits is stale
    -- (two arrow presses in one frame), the spec is the truth
    if PD.stale[r] then return nil end
    for i = 1, (r:GetNumPoints() or 0) do
        local pt, _, rp, x, y = r:GetPoint(i)
        out[i] = { pt, rp, x, y }
    end
    return out
end

local function WriteMove(piece, ux, uy, at)
    if ux == 0 and uy == 0 then return nil end
    for _, r in ipairs(Regions(piece)) do PD.stale[r] = true end
    if piece.anchor then
        local a = piece.anchor
        local old = Copy(a.get())
        local new = MovedSpec(old, Def(a), ux, uy, at)
        local again = Copy(new)
        a.set(new)
        return function() a.set(Copy(old)) end, function() a.set(Copy(again)) end
    elseif piece.move then
        local m = piece.move
        local ox, oy = m.get()
        ox, oy = tonumber(ox) or 0, tonumber(oy) or 0
        -- (a store that was unset - a mover never dragged - goes back to
        -- unset on undo: the piece's own snapshot / restore)
        local snap = m.snapshot and m.snapshot()
        m.set(ox + ux, oy + uy)
        local redo = function() m.set(ox + ux, oy + uy) end
        if m.snapshot and m.restore then return function() m.restore(snap) end, redo end
        return function() m.set(ox, oy) end, redo
    end
    return nil
end

local function WriteSize(piece, w, h)
    local s = piece.size
    if not s or (w == nil and h == nil) then return nil end
    local ow, oh = s.get()
    -- (a size kept in a shape of its own - a bar's rows from its width -
    -- snapshots and restores itself)
    local snap = s.snapshot and s.snapshot()
    s.set(w, h)
    local redo = function() s.set(w, h) end
    if s.snapshot and s.restore then
        -- (a width that works out to the rows it already had: no step)
        if SameValue(snap, s.snapshot()) then return nil end
        return function() s.restore(snap) end, redo
    end
    return function()
        -- a size that was unset (automatic) goes back to unset: the
        -- piece's reset, which clears it, rather than a value
        if s.reset and ((w ~= nil and ow == nil) or (h ~= nil and oh == nil)) then
            s.reset()
            return
        end
        s.set(w ~= nil and ow or nil, h ~= nil and oh or nil)
    end, redo
end

function PD.Undo()
    -- (not under a drag: the step would land under the piece in hand)
    if InCombat() or drag or press then return false end
    local e = table.remove(PD.undo)
    if not e then return false end
    local ok = pcall(e.fn)
    PD.stats.undos = PD.stats.undos + 1
    if e.redo then
        local r = PD.redo
        r[#r + 1] = e
        while #r > UNDO_MAX do table.remove(r, 1) end
    end
    Changed()
    ShowKeys()
    return ok
end

-- Ctrl+Y (or Ctrl+Shift+Z): the step undone last, done again
function PD.Redo()
    if InCombat() or drag or press then return false end
    local e = table.remove(PD.redo)
    if not (e and e.redo) then return false end
    local ok = pcall(e.redo)
    PushUndo(e, true)
    Changed()
    return ok
end

-- ============================================================
-- DRAG
-- ============================================================
-- the regions a drag shifts for the eye: piece.carry, else the piece's
-- own. One that hangs off another of them is left out: it moves with that
-- one, and shifting both would carry it twice as far as the cursor.
local function CarryOf(piece)
    local c = piece.carry
    local list
    if IsRegion(c) then list = { c }
    elseif type(c) == "table" and #c > 0 then list = c
    else list = Regions(piece) end
    if #list < 2 then return list end
    local out, seen = {}, {}
    for i, r in ipairs(list) do
        if IsRegion(r) and not seen[r] then
            seen[r] = true
            local under = false
            for j, o in ipairs(list) do
                if j ~= i and IsRegion(o) and o ~= r and HangsOff(r, o) then under = true break end
            end
            if not under then out[#out + 1] = r end
        end
    end
    return out
end

function PD.CaptureBase(d)
    d.base = {}
    local list = (d.mode == "move") and CarryOf(d.piece) or Regions(d.piece)
    for _, r in ipairs(list) do
        if IsRegion(r) then
            local pts = {}
            for i = 1, (r:GetNumPoints() or 0) do pts[i] = { r:GetPoint(i) } end
            d.base[#d.base + 1] = { r = r, pts = pts, w = r:GetWidth(), h = r:GetHeight(), eff = Eff(r) }
        end
    end
end

-- the dragged piece's outline where the piece is now (or, resizing a
-- piece of many regions - a bar's grid - the size it is being given)
local function Follow(d)
    local h = d.h
    if not (h and h.piece == d.piece and h.box) then return end
    local L = h._zLayer
    if d.mode ~= "move" and d.ghost then
        local l, t = d.rect[1], d.rect[4]
        PlaceRect(L, h, l, t - (d.vh or d.rh) * d.eff, l + (d.vw or d.rw) * d.eff, t, nil)
    elseif d.mode == "move" and d.ghostMove then
        local sx, sy = (d.ux or 0) * d.eff, (d.uy or 0) * d.eff
        PlaceRect(L, h, d.rect[1] + sx, d.rect[2] + sy, d.rect[3] + sx, d.rect[4] + sy, nil)
    else
        PlaceHandle(L, h, d.piece)
    end
end

-- the piece where the drag has it (for the eye only: nothing written).
-- The shift is the written offset in screen px, then each region's own
-- units: a region scaled apart from what the setting counts in (a HUD
-- sample at its own scale) still moves exactly with the cursor.
function PD.ApplyTemp(d)
    if d.mode == "move" and d.ghostMove then
        -- (only its outline goes: see Begin)
    elseif d.mode == "move" then
        local ux, uy = d.ux or 0, d.uy or 0
        for _, b in ipairs(d.base or {}) do
            local r, e = b.r, b.eff or d.eff
            local ox, oy = ux, uy
            if math_abs(e - d.eff) > 1e-9 then ox, oy = ux * d.eff / e, uy * d.eff / e end
            r:ClearAllPoints()
            for _, q in ipairs(b.pts) do r:SetPoint(q[1], q[2], q[3], (q[4] or 0) + ox, (q[5] or 0) + oy) end
        end
    elseif not d.ghost and (d.vw or d.vh) then
        for _, b in ipairs(d.base or {}) do b.r:SetSize(d.vw or b.w, d.vh or b.h) end
    end
    Follow(d)
end

local function PutBack(d)
    for _, b in ipairs(d.base or {}) do
        local r = b.r
        r:ClearAllPoints()
        for _, q in ipairs(b.pts) do r:SetPoint(q[1], q[2], q[3], q[4], q[5]) end
        if b.w and b.h and (d.vw or d.vh) and not d.ghost then r:SetSize(b.w, b.h) end
    end
end

-- What the dragged piece may snap to, read ONCE when the drag starts
-- (where things sit then; a piece that happens to move along is no moving
-- target): the frame it belongs to, and every other piece's rect (with
-- its handle, to outline the one it snaps to). Neither a piece hanging
-- off the dragged one nor one of its own regions counts.
function PD.Lines(d)
    local L = d.h._zLayer
    local mine = {}
    for _, r in ipairs(Regions(d.piece)) do mine[#mine + 1] = r end
    for _, b in ipairs(d.base or {}) do mine[#mine + 1] = b.r end
    local function Mine(r)
        for _, m in ipairs(mine) do if IsRegion(m) and HangsOff(r, m) then return true end end
        return false
    end
    d.cont = nil
    if IsRegion(L.container) and not Mine(L.container) then
        local l, b, r, t = RegionRect(L.container)
        if l then d.cont = { l, b, r, t } end
    end
    local hOf = {}
    for _, h in ipairs(L.handles or {}) do if h.piece and h:IsShown() then hOf[h.piece] = h end end
    d.others = {}
    for _, piece in ipairs(L.pieces or {}) do
        if piece ~= d.piece then
            local skip = false
            for _, r in ipairs(Regions(piece)) do if IsRegion(r) and Mine(r) then skip = true break end end
            if not skip then
                local l, b, r, t = PieceRect(piece)
                if l then d.others[#d.others + 1] = { l, b, r, t, h = hOf[piece] } end
            end
        end
    end
end

-- the other piece nearest the rect l, b, r, t: the smallest edge-to-edge
-- gap (0 when they overlap), then the nearest centre
local function Nearest(d, l, b, r, t)
    local best, bd, bc
    local cx, cy = (l + r) / 2, (b + t) / 2
    for _, o in ipairs(d.others or {}) do
        local gx, gy = 0, 0
        if r < o[1] then gx = o[1] - r elseif l > o[3] then gx = l - o[3] end
        if b > o[4] then gy = b - o[4] elseif t < o[2] then gy = o[2] - t end
        local dd = gx * gx + gy * gy
        local ox, oy = (o[1] + o[3]) / 2 - cx, (o[2] + o[4]) / 2 - cy
        local dc = ox * ox + oy * oy
        if not bd or dd < bd - 1e-9 or (math_abs(dd - bd) <= 1e-9 and dc < bc) then best, bd, bc = o, dd, dc end
    end
    return best
end

-- the lines on one axis (1: x, 2: y) of the frame and of `near`
local function AxisLines(d, near, axis)
    local out, owner = {}, {}
    local function Add(o, who)
        local lo, hi = o[axis], o[axis + 2]
        out[#out + 1], out[#out + 2], out[#out + 3] = lo, (lo + hi) / 2, hi
        owner[#owner + 1], owner[#owner + 2], owner[#owner + 3] = who, who, who
    end
    if d.cont then Add(d.cont, false) end
    if near then Add(near, near) end
    return out, owner
end

-- the smallest shift (under SNAP) putting one of `mine` on one of `lines`;
-- `moved` (the drag so far on this axis) within HOME of nothing goes home.
-- -> the shift, the line, whose line it is
local function Best(mine, lines, moved, owner)
    local best, at, who
    if moved and math_abs(moved) <= HOME then best = -moved end
    for _, m in ipairs(mine) do
        for i, t in ipairs(lines) do
            local dd = t - m
            if math_abs(dd) < SNAP and (not best or math_abs(dd) < math_abs(best)) then
                best, at, who = dd, t, owner and owner[i]
            end
        end
    end
    return best, at, who
end

-- the rect of a reorder item (its region)
function PieceRectOf(it)
    if not (it and IsRegion(it.region)) then return nil end
    return RegionRect(it.region)
end
-- ... where it sat when the drag began (a row chained off the dragged
-- item - the meter's header icons - would otherwise slide along with it
-- and never be passed)
local function ItemRect(d, it)
    local c = it and d.itemRect and d.itemRect[it.key]
    if c then return c[1], c[2], c[3], c[4] end
    return PieceRectOf(it)
end

-- the order the row would have with the dragged item dropped (dx, dy)
-- screen px from where it was picked up: every item by its centre (the
-- dragged one at its drop point - from where it WAS, not where the drag
-- has drawn it, or the distance counts twice), along the axis (y: top
-- first; grid: the rows the other items make, the dragged one in the row
-- its centre is nearest, then left to right in each).
-- -> keys, the item before it and the item after it (in its own row)
function PD.DropOrder(d, dx, dy)
    local group = d.piece.reorder
    local list, me = {}, nil
    for _, it in ipairs(group.items or {}) do
        local l, b, r, t
        if it.key == d.piece.item and d.rect then
            l, b, r, t = d.rect[1], d.rect[2], d.rect[3], d.rect[4]
        else
            l, b, r, t = ItemRect(d, it)
        end
        if l then
            local e = { it = it, x = (l + r) / 2, y = (b + t) / 2, h = t - b }
            if it.key == d.piece.item then
                e.x, e.y = e.x + dx, e.y + dy
                me = e
            end
            list[#list + 1] = e
        end
    end
    local ax = group.axis
    if ax == "grid" then
        -- rows: top down, a new row where an item sits more than half its
        -- row's height below the row's first one (rows of different icon
        -- sizes stay whole)
        local others = {}
        for _, e in ipairs(list) do if e ~= me then others[#others + 1] = e end end
        table.sort(others, function(a, b) return a.y > b.y end)
        local rows = {}
        for _, e in ipairs(others) do
            local row = rows[#rows]
            if not row or row.top - e.y > math_max(1, row.h) / 2 then
                row = { top = e.y, h = e.h, sum = 0, n = 0 }
                rows[#rows + 1] = row
            end
            row.sum, row.n = row.sum + e.y, row.n + 1
            e.row = #rows
        end
        if me then
            local bi, bd = 1, nil
            for i, row in ipairs(rows) do
                local dd = math_abs(row.sum / row.n - me.y)
                if not bd or dd < bd then bi, bd = i, dd end
            end
            me.row = bi
        end
        table.sort(list, function(a, b)
            if a.row ~= b.row then return a.row < b.row end
            if a.x ~= b.x then return a.x < b.x end
            return a == me and b ~= me
        end)
    else
        table.sort(list, function(a, b)
            if ax == "y" then return a.y > b.y end
            if ax == "-y" then return a.y < b.y end    -- (a stack growing up)
            return a.x < b.x
        end)
    end
    local keys, prev, nxt = {}, nil, nil
    for i, e in ipairs(list) do
        keys[i] = e.it.key
        if e == me then
            local p, n = list[i - 1], list[i + 1]
            if p and (p.row == me.row) then prev = p.it end
            if n and (n.row == me.row) then nxt = n.it end
        end
    end
    return keys, prev, nxt
end

local function SetSnapTarget(d, h)
    if d.snapH == h then return end
    local old = d.snapH
    d.snapH = h
    if old then Paint(old) end
    if h then Paint(h) end
end

local function Track(d, x, y)
    local L = d.h._zLayer
    local dx, dy = x - d.x0, y - d.y0
    local free = Shift()
    local gx, gy, gxr, gyr
    local l, b, r, t = d.rect[1], d.rect[2], d.rect[3], d.rect[4]
    if d.piece.reorder and d.mode == "move" then
        -- along the row: the piece follows, a guide shows where it lands
        -- (over the slot's own height: the row it lands in)
        d.ux, d.uy = Round(dx / d.eff), Round(dy / d.eff)
        PD.ApplyTemp(d)
        local order, prev, nxt = PD.DropOrder(d, dx, dy)
        d.order = order
        local ax = d.piece.reorder.axis
        if ax == "y" or ax == "-y" then
            local it, edge = prev, (ax == "y") and 2 or 4
            if not it then it, edge = nxt, (ax == "y") and 4 or 2 end
            if it then
                local rl, rb, rr, rt = ItemRect(d, it)
                if rl then gy, gyr = (edge == 2) and rb or rt, { rl, rr } end
            end
        else
            local it, right = prev, true
            if not it then it, right = nxt, false end
            if it then
                local rl, rb, rr, rt = ItemRect(d, it)
                if rl then gx, gxr = right and rr or rl, { rb, rt } end
            end
        end
        ShowGuides(L, gx, gy, gxr, gyr)
        return
    end
    local near
    if d.mode == "move" then
        if not free then
            near = Nearest(d, l + dx, b + dy, r + dx, t + dy)
            local xs, xo = AxisLines(d, near, 1)
            local ys, yo = AxisLines(d, near, 2)
            local sx, ax, wx = Best({ l + dx, (l + r) / 2 + dx, r + dx }, xs, dx, xo)
            local sy, ay, wy = Best({ b + dy, (b + t) / 2 + dy, t + dy }, ys, dy, yo)
            if sx then dx, gx = dx + sx, ax end
            if sy then dy, gy = dy + sy, ay end
            near = (wx and wx == near or wy and wy == near) and near or nil
        end
        d.ux, d.uy = Round(dx / d.eff), Round(dy / d.eff)
    else
        local s = d.piece.size
        if not free then
            -- (the edge being dragged, against the frame and the piece
            -- nearest the size it is being given)
            local nr = (d.mode ~= "bottom") and (r + dx) or r
            local nb = (d.mode ~= "right") and (b + dy) or b
            near = Nearest(d, l, nb, nr, t)
            local wx, wy
            if d.mode ~= "bottom" then
                local xs, xo = AxisLines(d, near, 1)
                local sx, ax
                sx, ax, wx = Best({ r + dx }, xs, dx, xo)
                if sx then dx, gx = dx + sx, ax end
            end
            if d.mode ~= "right" then
                local ys, yo = AxisLines(d, near, 2)
                local sy, ay
                sy, ay, wy = Best({ b + dy }, ys, dy, yo)
                if sy then dy, gy = dy + sy, ay end
            end
            near = (wx and wx == near or wy and wy == near) and near or nil
        end
        local dw = (d.mode ~= "bottom") and Round(dx / d.eff) or 0
        local dh = (d.mode ~= "right") and Round(-dy / d.eff) or 0
        local lo, hi = tonumber(s.min) or 1, tonumber(s.max) or 4000
        local loH, hiH = tonumber(s.minH) or lo, tonumber(s.maxH) or hi
        if s.square then
            local dsz = (d.mode == "bottom") and dh or ((d.mode == "right") and dw or ((math_abs(dw) >= math_abs(dh)) and dw or dh))
            local v = math_max(lo, math_min(hi, d.sw + dsz))
            d.nw, d.nh = v, nil
            d.vw, d.vh = d.rw + (v - d.sw), d.rh + (v - d.sw)
        else
            d.nw = (d.mode ~= "bottom") and math_max(lo, math_min(hi, d.sw + dw)) or nil
            d.nh = (d.mode ~= "right") and math_max(loH, math_min(hiH, d.sh + dh)) or nil
            d.vw = d.nw and (d.rw + (d.nw - d.sw)) or nil
            d.vh = d.nh and (d.rh + (d.nh - d.sh)) or nil
            -- (the size it would really take - a grid's whole columns and
            -- the rows they make - is what the outline shows)
            if type(s.fit) == "function" then
                local ok, fw, fh = pcall(s.fit, d.nw, d.nh)
                if ok then
                    fw, fh = tonumber(fw), tonumber(fh)
                    if fw then d.vw = d.rw + (fw - d.sw) end
                    if fh then d.vh = d.rh + (fh - d.sh) end
                    -- (a guide where the edge does not land would lie)
                    gx, gy = nil, nil
                end
            end
        end
    end
    SetSnapTarget(d, near and near.h or nil)
    PD.ApplyTemp(d)
    ShowGuides(L, gx, gy)
end

local function Begin(p)
    local h, piece = p.h, p.h.piece
    if not piece then return false end
    local L = h._zLayer
    local dh = h
    -- Alt on an item of a row that moves as a whole (a HUD row): the row,
    -- its own handle carrying the outline
    if piece.reorder and Alt() and p.mode == "move" and piece.reorder.rowPiece then
        piece = piece.reorder.rowPiece
        for _, x in ipairs(L.handles or {}) do
            if x.piece == piece and x:IsShown() then dh = x break end
        end
    end
    if p.mode == "move" and (piece.noMove or not (piece.anchor or piece.move or piece.reorder)) then return false end
    if p.mode ~= "move" and not piece.size then return false end
    local l, b, r, t = PieceRect(piece)
    if not l then return false end
    local regs = Regions(piece)
    local first = regs[1]
    -- (a move piece whose x / y are in another frame's units - a HUD
    -- mover's are UIParent's - names that scale: move.eff())
    local eff = (piece.move and type(piece.move.eff) == "function") and tonumber(piece.move.eff()) or nil
    local d = { h = dh, piece = piece, mode = p.mode, x0 = p.x0, y0 = p.y0, rect = { l, b, r, t },
        eff = (eff and eff > 0) and eff or (IsRegion(first) and Eff(first) or 1), ux = 0, uy = 0 }
    if d.mode ~= "move" then
        local s = piece.size
        local sw, sh = s.get()
        d.rw, d.rh = (r - l) / d.eff, (t - b) / d.eff
        sw, sh = tonumber(sw), tonumber(sh)
        d.sw = (sw and sw > 0) and sw or Round(d.rw)
        d.sh = (sh and sh > 0) and sh or Round(d.rh)
        if s.square then d.sh = d.sw end
        -- a piece of many regions (a bar's buttons) is not stretched: its
        -- outline shows the size it is being given
        d.ghost = (#regs > 1) or s.ghost and true or false
    end
    -- a reorder item: the row as it stands now, and whether the others
    -- hang off it (a row chained from one end): then the item stays put
    -- and only its outline follows the cursor, or it would drag them along
    if piece.reorder and d.mode == "move" then
        d.itemRect = {}
        local mineR = piece.region
        for _, it in ipairs(piece.reorder.items or {}) do
            local il, ib, ir, itp = PieceRectOf(it)
            if il then d.itemRect[it.key] = { il, ib, ir, itp } end
            if it.key ~= piece.item and IsRegion(it.region) and IsRegion(mineR) and HangsOff(it.region, mineR) then
                d.ghostMove = true
            end
        end
    end
    PD.CaptureBase(d)
    PD.Lines(d)
    drag = d
    PD.stats.drags = PD.stats.drags + 1
    Learned()
    if GameTooltip then GameTooltip:Hide() end
    if dh ~= h then Paint(h) end
    Paint(dh)
    Hand(true)
    ShowKeys()
    return true
end

local function Tick(self)
    local p = press
    if not p or p.h ~= self then self:SetScript("OnUpdate", nil) return end
    if InCombat() then PD.Cancel() return end
    -- the button let go where this handle never heard of it (outside the
    -- game window): it ends here, where the cursor was (EllesmereUI's
    -- unlock mode does the same)
    local down = _G.IsMouseButtonDown
    if down then
        local ok, isDown = pcall(down, "LeftButton")
        if ok and not isDown then Release(self, "LeftButton") return end
    end
    local x, y = Cursor()
    if not drag then
        if math_abs(x - p.x0) < DRAG_START and math_abs(y - p.y0) < DRAG_START then return end
        if not Begin(p) then return end
    end
    Track(drag, x, y)
end

Press = function(h, button, mode)
    if button ~= "LeftButton" then return end
    if InCombat() then Notice(h._zLayer, true) return end
    if press then PD.Cancel() end
    local x, y = Cursor()
    press = { h = h, mode = mode or "move", x0 = x, y0 = y }
    h:SetScript("OnUpdate", Tick)
end

local function Finish(commit)
    local d, p = drag, press
    drag, press = nil, nil
    if p and p.h then p.h:SetScript("OnUpdate", nil) end
    if not d then ShowKeys() return nil end
    local L = d.h._zLayer
    ShowGuides(L, nil, nil)
    local target = d.snapH
    d.snapH = nil
    if target then Paint(target) end
    local undo, redo
    if commit and not InCombat() then
        local ok, fn, rfn
        if d.piece.reorder and d.mode == "move" then
            ok, fn, rfn = pcall(WriteOrder, d.piece.reorder, d.order or ShownKeys(d.piece.reorder))
        elseif d.mode == "move" then
            local b1 = d.base and #d.base == 1 and d.base[1]
            ok, fn, rfn = pcall(WriteMove, d.piece, d.ux or 0, d.uy or 0, b1 and FirstPoint(d.piece, b1.pts) or nil)
        else
            local s = d.piece.size
            local w, hh = d.nw, d.nh
            local ow, oh = s.get()
            -- (a side dragged back to where it started, or to the value
            -- it already has, is not written)
            if w ~= nil and (tonumber(ow) == w or w == d.sw) then w = nil end
            if s.square then hh = nil
            elseif hh ~= nil and (tonumber(oh) == hh or hh == d.sh) then hh = nil end
            ok, fn, rfn = pcall(WriteSize, d.piece, w, hh)
        end
        if ok then undo, redo = fn, rfn end
    end
    -- written: the update puts it where the setting says (it already is
    -- there); not written: back where it was. A reordered item goes back
    -- too: the update lays the row out in its new order.
    if not undo or d.piece.reorder then
        PutBack(d)
        if d.h.piece == d.piece then pcall(PlaceHandle, L, d.h, d.piece) end
    end
    -- the piece stays selected: the arrow keys go on from where it landed
    if commit and d.h.piece then Select(d.h) end
    Paint(d.h)
    if not hover then Hand(false) end
    if undo then
        PushUndo({ label = d.piece.label or d.piece.key, fn = undo, redo = redo })
        Changed()
    end
    ShowKeys()
    return undo ~= nil
end

Release = function(h, button)
    if button == "RightButton" then
        if not drag then Menu(h) end
        return
    end
    if button ~= "LeftButton" then return end
    if not press then return end
    if drag then
        -- where the button came up is where it lands
        if not InCombat() then Track(drag, Cursor()) end
        Finish(true)
        return
    end
    press = nil
    h:SetScript("OnUpdate", nil)
    Select(h)
    Learned()
end

function PD.Cancel()
    if drag then Finish(false) end
    if press and press.h then press.h:SetScript("OnUpdate", nil) end
    press = nil
end

-- ============================================================
-- NUDGE, RESET, ANCHOR POINT, THE MENU
-- ============================================================
function PD.Nudge(h, ux, uy)
    if InCombat() or not (h and h.piece) then return false end
    local piece = h.piece
    if piece.reorder then
        -- an arrow moves it one place along its row
        local group = piece.reorder
        local step
        if group.axis == "y" then step = -(uy or 0)
        elseif group.axis == "-y" then step = uy or 0
        else step = (ux ~= 0) and ux or -(uy or 0) end
        if step == 0 then return false end
        local keys = ShownKeys(group)
        local at
        for i, k in ipairs(keys) do if k == piece.item then at = i end end
        local to = at and (at + (step > 0 and 1 or -1))
        if not (to and keys[to]) then return false end
        keys[at], keys[to] = keys[to], keys[at]
        local ok, fn, rfn = pcall(WriteOrder, group, keys)
        if not (ok and fn) then return false end
        PushUndo({ label = piece.label or piece.key, fn = fn, redo = rfn })
        Changed()
        return true
    end
    if piece.noMove or not (piece.anchor or piece.move) then return false end
    local top = PD.undo[#PD.undo]
    local join = top and top.nudge == piece.key and top.layer == h._zLayer and (Now() - top.t) <= NUDGE_JOIN
    local ok, fn, rfn = pcall(WriteMove, piece, ux, uy, FirstPoint(piece))
    if not (ok and fn) then return false end
    -- (a run of nudges: one step; its redo is the last of them)
    if join then top.t, top.redo = Now(), rfn PD.redo = {}
    else PushUndo({ label = piece.label or piece.key, fn = fn, redo = rfn, nudge = piece.key, layer = h._zLayer, t = Now() }) end
    Changed()
    return true
end

local function ResetPiece(piece)
    local fns = {}
    if piece.reorder then
        local g = piece.reorder
        local old = Copy(g.get())
        if old ~= nil then
            g.set(nil)
            fns[#fns + 1] = function() g.set(Copy(old)) end
        end
    end
    if piece.anchor then
        local a = piece.anchor
        local old = Copy(a.get())
        if old then
            local new = Copy(old)
            for _, k in ipairs(ANCHOR_FIELDS) do new[k] = nil end
            a.set(Clean(new))
            fns[#fns + 1] = function() a.set(Copy(old)) end
        end
    end
    -- (a store with a snapshot - a HUD mover that may be unset - goes back
    -- exactly as it was: undoing the reset of a mover never dragged leaves
    -- no mover behind)
    local m = piece.move
    if m and m.reset then
        if m.snapshot and m.restore then
            local snap = m.snapshot()
            m.reset()
            if SameValue(snap, m.snapshot()) then
                -- (already at its default: nothing to undo)
            else
                fns[#fns + 1] = function() m.restore(snap) end
            end
        else
            local ox, oy = m.get()
            m.reset()
            fns[#fns + 1] = function() m.set(ox, oy) end
        end
    end
    local s = piece.size
    if s and s.reset then
        if s.snapshot and s.restore then
            local snap = s.snapshot()
            s.reset()
            if not SameValue(snap, s.snapshot()) then fns[#fns + 1] = function() s.restore(snap) end end
        else
            local ow, oh = s.get()
            s.reset()
            local nw, nh = s.get()
            if not (ow == nw and oh == nh) then fns[#fns + 1] = function() s.set(ow, oh) end end
        end
    end
    if #fns == 0 then return nil end
    return function() for i = #fns, 1, -1 do fns[i]() end end, function() ResetPiece(piece) end
end

function PD.Reset(h)
    if InCombat() or not (h and h.piece) then return false end
    local ok, fn, rfn = pcall(ResetPiece, h.piece)
    if not (ok and fn) then return false end
    PushUndo({ label = h.piece.label or h.piece.key, fn = fn, redo = rfn })
    Changed()
    return true
end

-- every piece of this preview back to its default: one undo step
function PD.ResetLayout(key)
    if InCombat() then return false end
    local L = PD.layers[key]
    if not L then return false end
    local fns, again = {}, {}
    for _, piece in ipairs(L.pieces or {}) do
        local ok, fn, rfn = pcall(ResetPiece, piece)
        if ok and fn then fns[#fns + 1], again[#again + 1] = fn, rfn end
    end
    if #fns == 0 then return false end
    PushUndo({ label = "Reset layout", fn = function() for i = #fns, 1, -1 do fns[i]() end end,
        redo = function() for _, r in ipairs(again) do pcall(r) end end })
    Changed()
    return true
end

function PD.SetPoint(h, point)
    if InCombat() or not (h and h.piece and h.piece.anchor) then return false end
    local a = h.piece.anchor
    local def = Def(a) or {}
    local old = Copy(a.get())
    local new = Copy(old) or {}
    local dp = (Custom and Custom.VALID_POINT and Custom.VALID_POINT[def.point]) and def.point or "CENTER"
    new.point = (point ~= dp) and point or nil
    new.relPoint, new.x, new.y = nil, nil, nil
    new = Clean(new)
    local again = Copy(new)
    a.set(new)
    PushUndo({ label = h.piece.label or h.piece.key, fn = function() a.set(Copy(old)) end,
        redo = function() a.set(Copy(again)) end })
    Changed()
    return true
end

local function Changeable(piece)
    if piece.reorder and piece.reorder.get() ~= nil then return true end
    if piece.anchor then
        local s = piece.anchor.get()
        if type(s) == "table" then
            for _, k in ipairs(ANCHOR_FIELDS) do if s[k] ~= nil then return true end end
        end
    end
    return (piece.size and piece.size.reset) or (piece.move and piece.move.reset) and true or false
end

Menu = function(h)
    local piece = h and h.piece
    if not piece then return end
    local L = h._zLayer
    local fight = InCombat()
    local items = { { text = piece.label or piece.key, isTitle = true } }
    items[#items + 1] = { text = "Reset this piece", disabled = fight or not Changeable(piece),
        func = function() PD.Reset(h) end }
    if piece.anchor then
        local cur = ns.ResolveAnchor(piece.anchor.get(), Def(piece.anchor))
        local kids = {}
        for _, p in ipairs(POINTS) do
            kids[#kids + 1] = { text = POINT_LABEL[p] or p, checked = (p == cur), disabled = fight,
                func = function() PD.SetPoint(h, p) end }
        end
        items[#items + 1] = { text = "Anchor point", children = kids,
            tooltip = "Which corner of what it hangs from it sits on. Its offset starts again from there." }
    end
    items[#items + 1] = { text = "Open its settings", func = function()
        if type(piece.open) == "function" then pcall(piece.open)
        elseif ns.CustomPick then ns.CustomPick.Pick(L.key, piece.pick or piece.key) end
    end }
    items[#items + 1] = { separator = true }
    local top = PD.undo[#PD.undo]
    items[#items + 1] = { text = top and ("Undo: " .. tostring(top.label)) or "Undo", disabled = fight or not top,
        func = function() PD.Undo() end, tooltip = "Ctrl+Z does the same while this window is open." }
    local again = PD.redo[#PD.redo]
    items[#items + 1] = { text = again and ("Redo: " .. tostring(again.label)) or "Redo", disabled = fight or not again,
        func = function() PD.Redo() end, tooltip = "Ctrl+Y (or Ctrl+Shift+Z) does the same." }
    items[#items + 1] = { text = "Reset layout", disabled = fight,
        func = function() PD.ResetLayout(L.key) end,
        tooltip = "Every piece of this preview back where it sits by default (one undo step)." }
    Select(h)
    if UI.ContextMenu then PD.menu = UI.ContextMenu(items) end
    PD.lastMenu = items
end

-- THE LAYOUT BUTTON: a small button at the sample box's top right on a
-- page whose preview has pieces, with what is about the whole preview:
-- dragging on / off, the snap guides, Undo / Redo, Reset layout.
function PD.LayoutMenu(L)
    local fight = InCombat()
    local p = Prefs()
    local items = { { text = "Drag in the preview", isTitle = true } }
    items[#items + 1] = { text = "Drag pieces of the sample", checked = function() return not Prefs().dragOff end,
        tooltip = "Move, resize and reorder what the preview shows by dragging it. Off: the preview only shows.",
        func = function()
            local q = Prefs()
            q.dragOff = (not q.dragOff) and true or nil
            if q.dragOff then PD.Cancel() Select(nil) SetHover(nil) end
            if ns.ConfigPreview and ns.ConfigPreview.Request then ns.ConfigPreview.Request() end
            -- (the hint's band comes or goes with dragging)
            if ns.ConfigPreview and ns.ConfigPreview.Place then ns.ConfigPreview.Place() end
        end }
    items[#items + 1] = { text = "Show snap guides", checked = function() return not Prefs().dragNoGuides end,
        tooltip = "A thin line where a dragged piece lines up with an edge or a centre.",
        func = function() local q = Prefs() q.dragNoGuides = (not q.dragNoGuides) and true or nil end }
    items[#items + 1] = { separator = true }
    local top, again = PD.undo[#PD.undo], PD.redo[#PD.redo]
    items[#items + 1] = { text = top and ("Undo: " .. tostring(top.label)) or "Undo", disabled = fight or not top,
        func = function() PD.Undo() end, tooltip = "Ctrl+Z while this window is open." }
    items[#items + 1] = { text = again and ("Redo: " .. tostring(again.label)) or "Redo", disabled = fight or not again,
        func = function() PD.Redo() end, tooltip = "Ctrl+Y (or Ctrl+Shift+Z) while this window is open." }
    items[#items + 1] = { text = "Reset layout", disabled = fight or not p or (#(L.pieces or {}) == 0),
        func = function() PD.ResetLayout(L.key) end,
        tooltip = "Every piece of this preview back where it sits by default (one undo step)." }
    PD.lastMenu = items
    if UI.ContextMenu then PD.menu = UI.ContextMenu(items, { anchor = L.layoutButton }) end
    return items
end

function PD.LayoutButton(L)
    if L.layoutButton then return L.layoutButton end
    local b = UI.Button(L, "Layout", { width = 46, height = 14, size = UI.F.SMALL,
        tooltip = "Drag the preview's pieces to move, resize or reorder them. This menu: dragging on or off, "
            .. "snap guides, undo, redo, reset.",
        onClick = function()
            -- the menu opened once: the dots go, on every preview
            if ns.Hints and not ns.Hints.Seen("preview_layout") then
                ns.Hints.Mark("preview_layout")
                for _, other in pairs(PD.layers) do
                    if other.layoutButton and other.layoutButton._zDot then other.layoutButton._zDot:Hide() end
                end
            end
            PD.LayoutMenu(L)
        end })
    -- ON THE STRIP'S CONTROL LINE (2026-11-08), left of the background
    -- swatches - not over the sample box's corner, where a wide sample
    -- ran under it - shown while its layer is
    local PV = ns.ConfigPreview
    local slot = PV and PV.Slot and PV.Slot()
    if slot then
        b:SetParent(slot)
        b:ClearAllPoints()
        b:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
        b:SetFrameLevel(slot:GetFrameLevel() + 2)
        local function Fill()
            local any
            for _, o in pairs(PD.layers) do
                if o.layoutButton and o:IsShown() and o.layoutButton:IsShown() then any = o.layoutButton end
            end
            local w = any and math_max(1, any:GetWidth() or 46) or 1
            if math_abs((slot:GetWidth() or 1) - w) > 0.5 then
                slot:SetWidth(w)
                -- (laid out again once things settle: a page switch hides
                -- one layer and shows the next inside the strip's own layout)
                if PV.Place and not PD._zPlaceSoon then
                    PD._zPlaceSoon = true
                    local function Go() PD._zPlaceSoon = nil pcall(PV.Place) end
                    if C_Timer and C_Timer.After then C_Timer.After(0, Go) else Go() end
                end
            end
        end
        b:SetShown(L:IsShown())
        L:HookScript("OnShow", function() b:Show() Fill() end)
        L:HookScript("OnHide", function() b:Hide() Fill() end)
        -- (and when the button gets its real width - its label is fitted
        -- after it is made - so the slot never stays narrower than it)
        b:HookScript("OnSizeChanged", Fill)
        Fill()
    else
        b:SetPoint("TOPRIGHT", L, "TOPRIGHT", -2, -2)
        b:SetFrameLevel(LAYER_LEVEL + 400)
    end
    -- a menu not opened yet: a small accent dot on its corner
    if ns.Hints then
        local dot = b:CreateTexture(nil, "OVERLAY")
        dot._zui_own = true
        dot:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8X8")
        dot:SetSize(5, 5)
        dot:SetPoint("CENTER", b, "TOPRIGHT", -1, -1)
        local a = GetColor("ui", "accent")
        dot:SetVertexColor(a.r, a.g, a.b, 1)
        dot:SetShown(not HintsSeen("preview_layout"))
        b._zDot = dot
    end
    L.layoutButton = b
    return b
end

Tip = function(h)
    local piece = h.piece
    if not (piece and GameTooltip) then return end
    local t, c = GetColor("tooltip", "title"), GetColor("tooltip", "body")
    GameTooltip:SetOwner(h, "ANCHOR_TOP")
    GameTooltip:AddLine(piece.label or piece.key, t.r, t.g, t.b)
    local moves = not piece.noMove and (piece.anchor or piece.move)
    local body
    if piece.reorder then
        body = "Drag it along the row to change the order. Arrow keys move it one place."
        if piece.reorder.rowPiece then body = body .. " Alt-drag moves the whole row." end
    elseif moves then
        body = "Drag to move it (Shift: no snapping, Esc: put it back). Then the arrow keys nudge it 1 px, Shift 5."
    else
        body = "Drag its right or bottom edge to resize it."
    end
    if moves and piece.size then body = body .. " Its edges resize it." end
    if InCombat() then body = NOTICE end
    GameTooltip:AddLine(body .. " Right-click for more.", c.r, c.g, c.b, true)
    GameTooltip:Show()
end

-- ============================================================
-- KEYS (one keyboard frame on the settings window, up only while there is
-- something to nudge or undo, never in combat; it passes on every key it
-- does not use)
-- ============================================================
local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
function PD.Key(key)
    local used = false
    if not InCombat() then
        if (key == "Y" and Ctrl()) or (key == "Z" and Ctrl() and Shift()) then
            used = PD.Redo()
        elseif key == "Z" and Ctrl() then
            used = PD.Undo()
        elseif key == "ESCAPE" and (drag or press) then
            -- a drag put back where it started, nothing written
            PD.Cancel()
            used = true
        elseif ARROWS[key] and not (drag or press) then
            -- the selected piece (EllesmereUI nudges the selected element),
            -- else the one under the cursor
            local h = (selected and selected.piece and selected:IsVisible()) and selected or hover
            if h and h.piece and h:IsVisible() then
                local step = Shift() and NUDGE_BIG or NUDGE
                used = PD.Nudge(h, ARROWS[key][1] * step, ARROWS[key][2] * step)
            end
        end
    end
    if keyFrame and keyFrame.SetPropagateKeyboardInput and not InCombat() then
        keyFrame:SetPropagateKeyboardInput(not used)
    end
    return used
end

-- ============================================================
-- THE PAGE SIDE
-- ============================================================
function PD.Attach(spec, decl)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or type(decl) ~= "table" then return spec end
    local key = spec.key
    PD.decls[key] = decl
    InstallFoot()
    if spec._zDrag then return spec end
    spec._zDrag = true
    local update = spec.update
    spec.update = function(canvas, P)
        if update then update(canvas, P) end
        local ok, err = pcall(PD.Sync, key, canvas, P)
        if not ok and Custom and Custom.Note then Custom.Note(nil, "preview drag: " .. tostring(err)) end
    end
    return spec
end

-- A part declares a page's pieces from a file of its own, without touching
-- the page: PD.Register(previewKey, decl). The first registration wraps
-- the page builders' L:Preview (ConfigLayout, Config_Base) so a spec with
-- a registered key is attached as it is declared; every other spec goes
-- through untouched.
PD.registered = {}
local function Hook()
    local CL = ns.ConfigLayout
    if PD._hooked or not (CL and type(CL.Preview) == "function") then return end
    PD._hooked = true
    local declare = CL.Preview
    CL.Preview = function(self, spec)
        local d = type(spec) == "table" and PD.Declared(spec.key)
        if d then PD.Attach(spec, d) end
        return declare(self, spec)
    end
end
function PD.Register(key, decl)
    if type(key) ~= "string" or type(decl) ~= "table" then return end
    PD.registered[key] = decl
    Hook()
    InstallFoot()
end
-- a family of previews (every class HUD's "hud.<store>"): a Lua pattern
PD.matched = {}
function PD.RegisterMatch(pattern, decl)
    if type(pattern) ~= "string" or type(decl) ~= "table" then return end
    PD.matched[#PD.matched + 1] = { pattern = pattern, decl = decl }
    Hook()
    InstallFoot()
end
-- the declaration for a preview key: its own, else the first pattern's
function PD.Declared(key)
    if type(key) ~= "string" then return nil end
    local d = PD.registered[key]
    if d then return d end
    for _, m in ipairs(PD.matched) do
        if key:find(m.pattern) then return m.decl end
    end
    return nil
end

-- The first visible region under `root` tagged `key` (ns.TagElement: the
-- samples already carry their element keys for click-to-pick), or nil.
-- A declaration's lookup when the page keeps no handle on the region.
function PD.FindTagged(root, key)
    local found
    local function Visit(f, depth)
        if found or depth > 30 or not f then return end
        if rawget(f, "_zElement") == key and f.IsVisible and f:IsVisible() then found = f return end
        if f.GetRegions then
            for _, r in ipairs({ f:GetRegions() }) do
                if rawget(r, "_zElement") == key and r:IsVisible() then found = r return end
            end
        end
        if f.GetChildren then
            for _, k in ipairs({ f:GetChildren() }) do
                if k:IsVisible() then Visit(k, depth + 1) end
                if found then return end
            end
        end
    end
    Visit(root, 0)
    return found
end

-- for whoever is looking (and the tests)
function PD.Handles(key) local L = PD.layers[key] return L and L.handles or {} end
function PD.Handle(key, pieceKey)
    for _, h in ipairs(PD.Handles(key)) do
        if h.piece and h.piece.key == pieceKey and h:IsShown() then return h end
    end
    return nil
end
function PD.Hover() return hover end
function PD.Selected() return selected end
function PD.Dragging() return drag end

-- shared with later ZacUI files
ns.PreviewDrag = PD

-- the search finds the pages that can be dragged by these words (their
-- own labels say nothing about it): PD.Keywords(id, ...)
PD.WORDS = "drag dragging move reorder resize layout snap undo redo"
function PD.Keywords(...)
    if not ns.AddMenuKeywords then return end
    for i = 1, select("#", ...) do ns.AddMenuKeywords((select(i, ...)), PD.WORDS) end
end
