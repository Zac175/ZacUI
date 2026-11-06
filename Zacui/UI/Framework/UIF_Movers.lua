-- UIF_Movers - the mover registry and the one handle kit every ZacUI drag
-- handle is built with. Drag placeholders for HUD elements, with the Edit
-- Mode firewall that declines to fight client-managed frames.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE HANDLE KIT (ns.MoverKit). Every box you drag to place something -
-- the registry's own proxies, the action bar boxes, the scrolling text
-- areas, the raid mods plates, the tooltip anchor - is dressed by
-- Kit.Dress, so they all look and answer the same way:
--   * the house font and colours, a plain name on (or just outside) the box
--   * a live readout of where it is, in its owner's own numbers, outside
--     the box on hover and while dragging (never clipped by a small box)
--   * drag to move; arrow keys nudge one step (Shift: ten); the mouse wheel
--     nudges up / down (Ctrl: left / right; Shift: ten); right-click puts
--     it back to its default
--   * a frame holding secure buttons cannot move in a fight: its box turns
--     red, says so, and refuses the drag until combat ends
--   * smaller boxes sit above bigger ones, so a box inside another can
--     still be grabbed
-- The owner keeps its own storage: the kit only asks it for its numbers
-- (spec.coords), to move (spec.nudge / dragStart / dragStop) and to reset.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local Col = ns.Col
local Print = ns.Print
local ZUI = ns.ZUI
local UI = ns.UI

local math_floor, math_max, math_min, math_sqrt = math.floor, math.max, math.min, math.sqrt

-- ============================================================
-- THE HANDLE KIT
-- ============================================================
local Kit = {}
local STEP, BIG_STEP = 1, 10
local MIN_W, MIN_H = 24, 16
Kit.MIN_W, Kit.MIN_H = MIN_W, MIN_H
local dressed = {}      -- [handle] = true

-- a point's place on a box, as fractions from its bottom-left
local POINTS = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
Kit.POINTS = POINTS
local POINT_NAME = {
    TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
}
Kit.POINT_NAME = POINT_NAME

local function Round(v) return math_floor((tonumber(v) or 0) + 0.5) end
Kit.Round = Round

-- "Center  120, -45" (the point is left out when the owner has none)
function Kit.Format(point, x, y)
    local s = ("%d, %d"):format(Round(x), Round(y))
    if point then s = (POINT_NAME[point] or point) .. "  " .. s end
    return s
end

local function Spec(h) return rawget(h, "_zMover") end

local function Label(h)
    local spec = Spec(h)
    local l = spec and spec.label
    if type(l) == "function" then l = l(h) end
    return tostring(l or "")
end

local function IsLocked(h)
    local spec = Spec(h)
    if not (spec and InCombatLockdown and InCombatLockdown()) then return false end
    if spec.secure == true then return true end
    if type(spec.secure) == "function" then return spec.secure(h) and true or false end
    return false
end
Kit.Locked = IsLocked

local function Paint(h)
    local spec = Spec(h)
    if not spec then return end
    local locked = IsLocked(h)
    local hover = rawget(h, "_zHover") or rawget(h, "_zDragging")
    if spec.paint then
        spec.paint(h, { locked = locked, hover = hover and true or false })
    elseif h._zFill then
        local c
        if locked then c = ns.GetColor("text", "red")
        elseif spec.color then c = spec.color
        else c = Col("accent") end
        h._zFill:SetColorTexture(c.r or c[1], c.g or c[2], c.b or c[3], hover and 0.5 or 0.3)
    end
    if h._zLabel then
        h._zLabel._zPaintKey = locked and "red" or "normal"
        h._zLabel:_zPaint()
    end
end

-- name inside the box when it fits, else just outside it (above, or
-- below at the top of the screen); the readout on the other side
local function LayoutTexts(h)
    local lab, ro = h._zLabel, h._zReadout
    if not lab then return end
    local w, ht = h:GetWidth() or 0, h:GetHeight() or 0
    local top = h:GetTop()
    local bottom = h:GetBottom()
    local sh = UIParent:GetHeight() or 768
    local nearTop = top and (top + 18 > sh)
    local nearBottom = bottom and (bottom - 18 < 0)
    local tw = lab:GetStringWidth() or 0
    local inside = tw + 8 <= w and ht >= 14
    lab:ClearAllPoints()
    local labelSide
    if inside then
        lab:SetPoint("CENTER", h, "CENTER", 0, 0)
    elseif nearTop then
        lab:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -2)
        labelSide = "below"
    else
        lab:SetPoint("BOTTOMLEFT", h, "TOPLEFT", 0, 2)
        labelSide = "above"
    end
    if ro then
        ro:ClearAllPoints()
        local below = not nearBottom
        if labelSide == "below" then below = true end
        if labelSide == "above" and nearBottom then below = false end
        if below then
            if labelSide == "below" then ro:SetPoint("TOPLEFT", lab, "BOTTOMLEFT", 0, -1)
            else ro:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -2) end
        else
            if labelSide == "above" then ro:SetPoint("BOTTOMLEFT", lab, "TOPLEFT", 0, 1)
            else ro:SetPoint("BOTTOMLEFT", h, "TOPLEFT", 0, 2) end
        end
    end
    h._zLabelInside = inside
end

-- smaller boxes above bigger ones (a box inside another stays grabbable)
local function Restack(h)
    local w, ht = h:GetWidth() or 0, h:GetHeight() or 0
    local side = math_sqrt(math_max(1, w * ht))
    local base = Spec(h) and Spec(h).level or 20
    h:SetFrameLevel(base + math_max(1, math_min(600, 600 - math_floor(side))))
end

function Kit.Refresh(h)
    local spec = Spec(h)
    if not spec then return end
    if h._zLabel then
        local text = Label(h)
        if IsLocked(h) then text = text .. "  (locked in combat)" end
        h._zLabel:SetText(text)
    end
    Restack(h)
    LayoutTexts(h)
    Paint(h)
end

function Kit.UpdateReadout(h)
    local ro = h._zReadout
    local spec = Spec(h)
    if not (ro and spec) then return end
    local show = rawget(h, "_zHover") or rawget(h, "_zDragging")
    if not show then ro:Hide() return end
    local text = spec.coords and spec.coords(h)
    if not text or text == "" then ro:Hide() return end
    ro:SetText(text)
    ro:Show()
end
Kit.Readout = function(h) return h._zReadout and h._zReadout:IsShown() and h._zReadout:GetText() or nil end

local function SayLocked(h)
    local now = GetTime and GetTime() or 0
    if (rawget(h, "_zSaidLocked") or -10) + 3 > now then return end
    rawset(h, "_zSaidLocked", now)
    Print(Label(h) .. " holds secure buttons and cannot move in combat - it can once the fight ends.")
end
Kit.SayLocked = SayLocked

-- live work while hovered or dragged: the owner's follow, then the readout
local function Tick(self, elapsed)
    local spec = Spec(self)
    if rawget(self, "_zDragging") and spec and spec.onDrag then spec.onDrag(self) end
    self._zAcc = (self._zAcc or 1) + (elapsed or 0)
    if self._zAcc >= 0.05 then
        self._zAcc = 0
        Kit.UpdateReadout(self)
        if rawget(self, "_zDragging") then LayoutTexts(self) end
    end
end
local function Watch(h)
    if rawget(h, "_zHover") or rawget(h, "_zDragging") then
        h._zAcc = 1
        h:SetScript("OnUpdate", Tick)
    else
        h:SetScript("OnUpdate", nil)
    end
    Kit.UpdateReadout(h)
end

function Kit.Nudge(h, dx, dy)
    local spec = Spec(h)
    if not (spec and spec.nudge) then return false end
    if IsLocked(h) then SayLocked(h) return false end
    spec.nudge(dx, dy, h)
    Kit.Refresh(h)
    Kit.UpdateReadout(h)
    return true
end

function Kit.Reset(h)
    local spec = Spec(h)
    if not (spec and spec.reset) then return false end
    if IsLocked(h) then SayLocked(h) return false end
    spec.reset(h)
    Kit.Refresh(h)
    Kit.UpdateReadout(h)
    return true
end

-- arrow keys: one shared keyboard frame, up only while a box is hovered
-- (and never in combat, when its propagation cannot be changed)
local keyFrame = CreateFrame("Frame", "ZacUIMoverKeys", UIParent)
keyFrame:Hide()
keyFrame:EnableKeyboard(true)
if keyFrame.SetPropagateKeyboardInput then keyFrame:SetPropagateKeyboardInput(true) end
local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }
keyFrame:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end
    local h = self.target
    local dir = ARROWS[key]
    if not (h and dir and h:IsShown() and Spec(h) and Spec(h).nudge) then
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end
        return
    end
    local step = IsShiftKeyDown() and BIG_STEP or STEP
    Kit.Nudge(h, dir[1] * step, dir[2] * step)
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
end)
Kit.keyFrame = keyFrame

local function Hover(h, on)
    rawset(h, "_zHover", on and true or nil)
    if on then
        if not InCombatLockdown() then
            keyFrame.target = h
            if keyFrame.SetPropagateKeyboardInput then keyFrame:SetPropagateKeyboardInput(true) end
            keyFrame:Show()
        end
        if GameTooltip and not rawget(h, "_zDragging") then
            local spec = Spec(h)
            GameTooltip:SetOwner(h, "ANCHOR_TOP")
            GameTooltip:SetText(Label(h), 1, 1, 1)
            if IsLocked(h) then
                GameTooltip:AddLine("Holds secure buttons: it can move once combat ends.", 1, 0.3, 0.3, true)
            else
                GameTooltip:AddLine("Drag to move.", 0.8, 0.8, 0.8, true)
                if spec.nudge then
                    GameTooltip:AddLine("Arrow keys or mouse wheel nudge (Shift: 10, Ctrl + wheel: sideways).", 0.8, 0.8, 0.8, true)
                end
                if spec.reset then GameTooltip:AddLine("Right-click: back to its default spot.", 0.8, 0.8, 0.8, true) end
            end
            if spec.hint then GameTooltip:AddLine(spec.hint, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end
    else
        if keyFrame.target == h then
            keyFrame.target = nil
            keyFrame:Hide()
        end
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(h) then GameTooltip:Hide() end
    end
    Paint(h)
    Watch(h)
end
Kit.Hover = Hover

-- Dress a drag handle. spec:
--   label     string or function(h)  the plain name
--   coords    function(h) -> text    where it is, in the owner's numbers
--   dragStart function(h)            (default h:StartMoving())
--   onDrag    function(h)            every frame of a drag (live follow)
--   dragStop  function(h)            save (after StopMovingOrSizing)
--   nudge     function(dx, dy, h)    move by whole steps and save
--   reset     function(h)            back to the default spot
--   secure    true / function(h)     holds secure buttons: locked in combat
--   click     function(h, button)    a left click that was not a drag
--   paint     function(h, state)     own fill (state.locked / state.hover)
--   color     { r, g, b }            fill colour (default accent)
--   strata    (default FULLSCREEN), level (base, default 20)
--   clamp     false: not clamped to the screen (default clamped)
function Kit.Dress(h, spec)
    rawset(h, "_zMover", spec)
    dressed[h] = true
    h:SetFrameStrata(spec.strata or "FULLSCREEN")
    h:SetMovable(true)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    if h.EnableMouseWheel then h:EnableMouseWheel(true) end
    if h.SetClampedToScreen then h:SetClampedToScreen(spec.clamp ~= false) end
    if not spec.paint and not h._zFill then
        local bg = h:CreateTexture(nil, "BACKGROUND")
        bg._zui_own = true
        bg:SetAllPoints()
        h._zFill = bg
    end
    if not rawget(h, "_zBordered") and AddPixelBorder then
        rawset(h, "_zBordered", true)
        AddPixelBorder(h, "accent", 0.9)
    end
    local F = UI and UI.F or {}
    if not h._zLabel then
        h._zLabel = UI.Font(h, F.SMALL or 10, { cat = "text", key = "normal" })
        h._zReadout = UI.Font(h, F.SMALL or 10, { cat = "text", key = "gold" })
        h._zReadout:Hide()
    end
    h:SetScript("OnEnter", function(self) Hover(self, true) end)
    h:SetScript("OnLeave", function(self) Hover(self, false) end)
    h:SetScript("OnDragStart", function(self)
        local s = Spec(self)
        if IsLocked(self) then SayLocked(self) return end
        rawset(self, "_zDragging", true)
        rawset(self, "_zDragged", true)
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        if s.dragStart then s.dragStart(self) else self:StartMoving() end
        Paint(self)
        Watch(self)
    end)
    h:SetScript("OnDragStop", function(self)
        if not rawget(self, "_zDragging") then return end
        rawset(self, "_zDragging", nil)
        self:StopMovingOrSizing()
        local s = Spec(self)
        if s.onDrag then s.onDrag(self) end
        if s.dragStop then s.dragStop(self) end
        Kit.Refresh(self)
        Watch(self)
    end)
    h:SetScript("OnMouseDown", function(self) rawset(self, "_zDragged", nil) end)
    h:SetScript("OnMouseUp", function(self, button)
        local s = Spec(self)
        if button == "RightButton" then
            Kit.Reset(self)
        elseif s.click and not rawget(self, "_zDragged") then
            s.click(self, button)
        end
        rawset(self, "_zDragged", nil)
    end)
    h:SetScript("OnMouseWheel", function(self, delta)
        local step = (IsShiftKeyDown() and BIG_STEP or STEP) * ((delta or 0) > 0 and 1 or -1)
        if IsControlKeyDown() then Kit.Nudge(self, step, 0) else Kit.Nudge(self, 0, step) end
    end)
    h:SetScript("OnHide", function(self)
        if rawget(self, "_zDragging") then
            rawset(self, "_zDragging", nil)
            self:StopMovingOrSizing()
        end
        if rawget(self, "_zHover") then Hover(self, false) end
        self:SetScript("OnUpdate", nil)
    end)
    Kit.Refresh(h)
    return h
end

function Kit.IsDressed(h) return h ~= nil and dressed[h] == true end

-- combat: every shown box repaints (red + "locked" on the secure ones), a
-- drag in progress on a secure frame is dropped where it is, and the
-- keyboard frame steps aside
local kitEvents = CreateFrame("Frame")
kitEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
kitEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
kitEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        keyFrame.target = nil
        keyFrame:Hide()
    end
    for h in pairs(dressed) do
        if h:IsShown() then Kit.Refresh(h) end
    end
end)

-- ============================================================
-- THE REGISTRY
-- ============================================================
local MOVERS, moverProxies = {}, {}
local pending = {}      -- [key] = "apply" | "reset": waits for combat to end

-- reflow: Blizzard's own top-frame reflow moves this frame, so the saved
-- spot is put back after each one (the HUD anchors and ZacUI's own
-- frames are never moved by it and are left alone there)
-- opts (optional), for a frame that keeps its spot somewhere of its own:
--   get()            -> point, x, y   its saved spot (nil = none)
--   set(point, x, y)                  save (point nil = clear)
--   reset()                           put the frame at its own default
--   secure           true: holds secure buttons (locked in combat)
--   own              true: ours, never skipped as client-managed
-- Registering the same key again updates it in place (no second row).
local function RegisterMover(key, label, getFrame, defPoint, defX, defY, reflow, opts)
    local m = MOVERS[key]
    if not m then
        m = { key = key }
        MOVERS[#MOVERS + 1] = m
        MOVERS[key] = m
    end
    m.label, m.getFrame = label, getFrame
    m.defPoint, m.defX, m.defY = defPoint, defX, defY
    m.reflow = reflow and true or nil
    if opts then
        m.get, m.set, m.reset = opts.get, opts.set, opts.reset
        m.secure, m.own = opts.secure, opts.own
    end
    local p = moverProxies[key]
    if p and p:IsShown() then Kit.Refresh(p) end
    return m
end

local function SavedPos(m)
    if m.get then
        local point, x, y = m.get()
        if point then return { point = point, x = x or 0, y = y or 0 } end
        return nil
    end
    local pos = ZacUIDB and ZacUIDB.movers and ZacUIDB.movers[m.key]
    if type(pos) == "table" then return pos end
    return nil
end
local function WritePos(m, point, x, y)
    if m.set then m.set(point, x, y) return end
    if not ZacUIDB then return end
    ZacUIDB.movers = ZacUIDB.movers or {}
    if point then
        ZacUIDB.movers[m.key] = { point = point, x = x or 0, y = y or 0 }
    else
        ZacUIDB.movers[m.key] = nil
    end
end

-- 1.15.9 GUARD - Edit Mode owns whole HUD systems now: MinimapCluster,
-- BuffFrame/DebuffFrame, chat, action bars, micro menu, bags. Insecure
-- ClearAllPoints/SetPoint on a managed frame either taints its anchor
-- chain (protected frames) or just gets re-asserted over every layout
-- pass (Edit Mode systems) - fighting either buys nothing. TWO runtime
-- signals, no build sniffing:
--   * IsProtected()  - secure client management
--   * frame.system   - EditModeSystemMixin stamps every frame Edit Mode
--                      owns (the documented marker on 11509)
-- Saved positions stay in the DB untouched in case a later build (or a
-- different game flavor) releases the frame.
-- PERF: both are cheap queries; this runs inside the
-- UIParent_UpdateTopFramePositions reflow hook, so the guard stays flat.
local moverSkipNoted = {}
local function MoverBlocked(key, f)
    if not f then return false end
    local m = MOVERS[key]
    if m and m.own then return false end
    -- explicitly protected only: a frame of ours that a secure button is
    -- anchored to (the Snowball holder) reads as protected too, and that
    -- one is ours to move out of combat (2026-10-26, "Snowball button is
    -- client-managed (protected) on this build - mover skipped")
    local protected, explicit
    if f.IsProtected then protected, explicit = f:IsProtected() end
    protected = protected and explicit
    local editMode = f.system ~= nil
    if not (protected or editMode) then return false end
    if not moverSkipNoted[key] then
        moverSkipNoted[key] = true
        Print((m and m.label or key)
            .. (editMode and " is managed by Edit Mode on this build - move/scale it there (Esc > Edit Mode)."
                or " is client-managed (protected) on this build - mover skipped.")
            .. " Saved ZacUI position kept dormant.")
    end
    return true
end

-- holds secure buttons (or is told so): cannot be moved in a fight
local function IsSecure(m, f)
    if m.secure then return true end
    if f and f.IsProtected then return f:IsProtected() and true or false end
    return false
end

-- the frame's scale against UIParent's: its SetPoint offsets are in its
-- own units, so a saved x of 100 on a frame at 1.5 sits 150 UI units out
local function ScaleOf(f)
    if not (f and f.GetEffectiveScale) then return 1 end
    local us = UIParent:GetEffectiveScale() or 1
    local k = (f:GetEffectiveScale() or 1) / (us > 0 and us or 1)
    return k > 0 and k or 1
end

-- the frame's box in UIParent units (nil when it has none yet)
local function FrameRect(f)
    if not (f and f.GetRect) then return nil end
    local l, b, w, h = f:GetRect()
    if not (l and b and w and h) or w <= 0 or h <= 0 then return nil end
    local k = ScaleOf(f)
    return l * k, b * k, w * k, h * k
end

-- what is drawn there: the frame and its shown children (a HUD holder's
-- scaled anchor, a bar's box), one box round them all, in UIParent units
local function DrawnRect(f, l, b, w, h)
    local r, t = l + w, b + h
    if f.GetChildren then
        for _, c in ipairs({ f:GetChildren() }) do
            if c.IsShown and c:IsShown() then
                local cl, cb, cw, ch = FrameRect(c)
                if cl then
                    if cl < l then l = cl end
                    if cb < b then b = cb end
                    if cl + cw > r then r = cl + cw end
                    if cb + ch > t then t = cb + ch end
                end
            end
        end
    end
    return l, b, r - l, t - b
end

local function SetFramePos(f, point, x, y)
    f:ClearAllPoints()
    f:SetPoint(point or "CENTER", UIParent, point or "CENTER", x or 0, y or 0)
end

local function ApplyMover(key)
    local m = MOVERS[key]
    local pos = m and SavedPos(m)
    local f = m and m.getFrame()
    if not (pos and f) then return end
    if MoverBlocked(key, f) then return end
    if InCombatLockdown() and IsSecure(m, f) then
        pending[key] = pending[key] or "apply"
        return
    end
    SetFramePos(f, pos.point, pos.x, pos.y)
end

-- the frame back at its default spot, live
local function PlaceDefault(m)
    local f = m.getFrame()
    if not f or MoverBlocked(m.key, f) then return end
    if InCombatLockdown() and IsSecure(m, f) then
        pending[m.key] = "reset"
        return
    end
    if m.reset then
        m.reset()
    elseif m.defPoint then
        SetFramePos(f, m.defPoint, m.defX, m.defY)
    end
end

-- ------------------------------------------------------------
-- PROXIES: one box per registered frame, laid over the frame itself at
-- its real size and scale (a frame not drawn yet: its saved or default
-- spot, at its size). Dragging moves the frame live; dropping saves the
-- spot in the frame's own convention (its point on UIParent's same point,
-- in its own units) - the numbers the readout shows.
-- ------------------------------------------------------------
local function UIPoint(point)
    local pp = POINTS[point] or POINTS.CENTER
    return (UIParent:GetWidth() or 0) * pp[1], (UIParent:GetHeight() or 0) * pp[2]
end

local function FitProxy(p)
    local m = MOVERS[p.moverKey]
    if not m then return end
    local f = m.getFrame()
    local l, b, w, h = FrameRect(f)
    if not l then
        local pos = SavedPos(m)
        local point = (pos and pos.point) or m.defPoint or "CENTER"
        local x = pos and pos.x or m.defX or 0
        local y = pos and pos.y or m.defY or 0
        local k = ScaleOf(f)
        w = f and f.GetWidth and (f:GetWidth() or 0) * k or 0
        h = f and f.GetHeight and (f:GetHeight() or 0) * k or 0
        if w <= 0 or h <= 0 then w, h = 200, 26 end
        local ux, uy = UIPoint(point)
        local pp = POINTS[point] or POINTS.CENTER
        l = ux + x * k - w * pp[1]
        b = uy + y * k - h * pp[2]
    end
    -- the box covers what is drawn; the numbers follow the frame itself,
    -- so the gap between the two centres is kept for the drop
    local dl, db, dw, dh = l, b, w, h
    if f and FrameRect(f) then dl, db, dw, dh = DrawnRect(f, l, b, w, h) end
    p._fw, p._fh = w, h
    p._dw, p._dh = dw, dh
    p._ox, p._oy = (dl + dw / 2) - (l + w / 2), (db + dh / 2) - (b + h / 2)
    p:ClearAllPoints()
    p:SetPoint("CENTER", UIParent, "BOTTOMLEFT", dl + dw / 2, db + dh / 2)
    p:SetSize(math_max(dw, MIN_W), math_max(dh, MIN_H))
end

-- where the frame would sit with its centre on the proxy's centre, in its
-- own convention
local function PosFromProxy(p, m)
    local cx, cy = p:GetCenter()
    local saved = SavedPos(m)
    local point = (saved and saved.point) or m.defPoint or "CENTER"
    if not (cx and cy) then
        return point, saved and saved.x or m.defX or 0, saved and saved.y or m.defY or 0
    end
    cx, cy = cx - (p._ox or 0), cy - (p._oy or 0)
    local pp = POINTS[point] or POINTS.CENTER
    local fw, fh = p._fw or p:GetWidth() or 0, p._fh or p:GetHeight() or 0
    local px, py = cx + fw * (pp[1] - 0.5), cy + fh * (pp[2] - 0.5)
    local ux, uy = UIPoint(point)
    local k = ScaleOf(m.getFrame())
    return point, (px - ux) / k, (py - uy) / k
end

-- the spot the readout shows: the saved numbers, or (while dragging, or
-- with nothing saved) where the frame is now
local function CurrentPos(p, m)
    if not rawget(p, "_zDragging") then
        local saved = SavedPos(m)
        if saved then return saved.point or "CENTER", saved.x or 0, saved.y or 0 end
    end
    return PosFromProxy(p, m)
end

local refitTicker
local function RefitShown()
    local any = false
    for _, p in pairs(moverProxies) do
        if p:IsShown() then
            any = true
            if not rawget(p, "_zDragging") then
                FitProxy(p)
                Kit.Refresh(p)
            end
        end
    end
    if not any and refitTicker then
        refitTicker:Cancel()
        refitTicker = nil
    end
end
local function StartRefit()
    if refitTicker or not (C_Timer and C_Timer.NewTicker) then return end
    refitTicker = C_Timer.NewTicker(0.5, RefitShown)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(refitTicker, "movers.refit") end
end

local function HideMover(key)
    local p = moverProxies[key]
    if p then p:Hide() end
end

local function ResetMover(key, silent)
    local m = MOVERS[key]
    if not m then
        if ZacUIDB and ZacUIDB.movers then ZacUIDB.movers[key] = nil end
        return
    end
    WritePos(m, nil)
    PlaceDefault(m)
    local p = moverProxies[key]
    if p and p:IsShown() then
        FitProxy(p)
        Kit.Refresh(p)
        Kit.UpdateReadout(p)
    end
    if not silent then Print(m.label .. " back to its default spot.") end
end

local function NewProxy(key)
    local p = CreateFrame("Frame", "ZacUIMover_" .. key, UIParent)
    p.moverKey = key
    local function M() return MOVERS[key] end
    Kit.Dress(p, {
        label = function() local m = M() return m and m.label or key end,
        secure = function()
            local m = M()
            return m and IsSecure(m, m.getFrame()) or false
        end,
        coords = function(self)
            local m = M()
            if not m then return nil end
            local point, x, y = CurrentPos(self, m)
            return Kit.Format(point, x, y) .. ("   %d x %d"):format(Round(self._dw), Round(self._dh))
        end,
        -- the frame follows the box, live
        onDrag = function(self)
            local m = M()
            local f = m and m.getFrame()
            if not f or MoverBlocked(key, f) or (InCombatLockdown() and IsSecure(m, f)) then return end
            local point, x, y = PosFromProxy(self, m)
            SetFramePos(f, point, x, y)
        end,
        dragStop = function(self)
            local m = M()
            if not m then return end
            local point, x, y = PosFromProxy(self, m)
            WritePos(m, point, Round(x), Round(y))
            ApplyMover(key)
            FitProxy(self)
        end,
        nudge = function(dx, dy, self)
            local m = M()
            if not m then return end
            local point, x, y = CurrentPos(self, m)
            WritePos(m, point, Round(x) + dx, Round(y) + dy)
            ApplyMover(key)
            FitProxy(self)
        end,
        reset = function() ResetMover(key, true) end,
    })
    moverProxies[key] = p
    return p
end

local function ShowMover(key)
    local m = MOVERS[key]
    if not m then return end
    if MoverBlocked(key, m.getFrame()) then return end
    local p = moverProxies[key] or NewProxy(key)
    FitProxy(p)
    p:Show()
    Kit.Refresh(p)
    StartRefit()
end
local function ToggleMover(key)
    local p = moverProxies[key]
    if p and p:IsShown() then
        p:Hide()
        return
    end
    ShowMover(key)
end

local function ApplyAllMovers()
    for _, m in ipairs(MOVERS) do ApplyMover(m.key) end
    if not ZUI._moverHooked
        and type(UIParent_UpdateTopFramePositions) == "function" then
        ZUI._moverHooked = true
        hooksecurefunc("UIParent_UpdateTopFramePositions", function()
            for _, m in ipairs(MOVERS) do
                if m.reflow then ApplyMover(m.key) end
            end
        end)
    end
end

-- what waited for the fight to end
local regen = CreateFrame("Frame")
regen:RegisterEvent("PLAYER_REGEN_ENABLED")
regen:SetScript("OnEvent", function()
    local list = {}
    for key, what in pairs(pending) do list[#list + 1] = { key, what } end
    wipe(pending)
    for _, it in ipairs(list) do
        local m = MOVERS[it[1]]
        if m then
            if it[2] == "reset" then PlaceDefault(m) else ApplyMover(it[1]) end
        end
    end
end)

RegisterMover("lootroll", "Loot rolls",
    function() return ZacUI_LootRollHolder or GroupLootFrame1 end,
    "TOP", 0, -220, true)
RegisterMover("buffs", "Buffs",
    function() return BuffFrame end, "TOPRIGHT", -200, -13, true)
RegisterMover("minimap", "Minimap",
    function() return MinimapCluster end, "TOPRIGHT", 0, 0, true)

-- GROUP LOOT ROLLS - Blz_LootRoll builds its own bars under
-- ZacUI_LootRollHolder (the ElvUI rebuild); the mover drags that holder.
-- GroupLootFrame1 is only the fallback when the module is disabled.

-- is the frame's box off the screen (or not drawn at all)?
local function OffScreen(key)
    local m = MOVERS[key]
    local f = m and m.getFrame()
    local l, b, w, h = FrameRect(f)
    if not l then return false end
    local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    return l + w < 4 or b + h < 4 or l > sw - 4 or b > sh - 4
end

-- shared with later ZacUI files
ns.MoverKit = Kit
ns.ApplyAllMovers = ApplyAllMovers
ns.HideMover = HideMover
ns.MOVERS = MOVERS
ns.MoverBlocked = MoverBlocked
-- The class HUDs (and the drink ticker) register every one of their
-- anchors through this. It was never published, so HUD_Shared captured
-- nil, HUD.RegisterMover returned at its first line, and not one HUD
-- anchor ever reached the Movers page or Edit Mode - nor did the HUD
-- pages' own "Unlock / lock HUD anchors" button have anything to unlock.
ns.RegisterMover = RegisterMover
ns.ShowMover = ShowMover
ns.ResetMover = ResetMover
ns.ToggleMover = ToggleMover
ns.ApplyMover = ApplyMover
ns.MoverOffScreen = OffScreen
ns.MoverProxy = function(key) return moverProxies[key] end
-- unlocked = its drag proxy is up (the HUD handles' padlock reads this)
ns.IsMoverShown = function(key)
    local p = moverProxies[key]
    return p ~= nil and p:IsShown()
end
