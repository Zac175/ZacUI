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
--
-- EDIT MODE (Kit.edit, set by UIF_EditMode only while it is open; nil the
-- rest of the time, and then every handle behaves exactly as above):
--   * a drag is followed from the cursor by the kit itself instead of the
--     engine's StartMoving, so it can be snapped (edit.snap) and held to
--     one axis (Shift) live; an owner's own dragStart still runs, and its
--     StartMoving call starts the kit's follow
--   * right-click asks edit.menu first (the mover's menu), a click or a
--     drag selects the box (edit.select), and every move, nudge and reset
--     is reported (edit.changed) so it can be undone or cancelled
--   * the keyboard frame stays up for the whole pass: arrow keys nudge
--     the hovered box, else the selected one; edit.key sees keys first

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
Kit.edit = nil          -- Edit Mode's hooks while it is open (header above)
Kit.selected = nil      -- the box picked in Edit Mode (arrow keys move it)
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
local function Hundredths(v) return math_floor((tonumber(v) or 0) * 100 + 0.5) / 100 end

-- "Center  120, -45" (the point is left out when the owner has none)
function Kit.Format(point, x, y)
    local s = ("%d, %d"):format(Round(x), Round(y))
    if point then s = (POINT_NAME[point] or point) .. "  " .. s end
    return s
end

local function Spec(h) return rawget(h, "_zMover") end

-- the colour of a box that follows another (Edit Mode)
Kit.LINK = { 0.47, 0.75, 1 }

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
    local hover = rawget(h, "_zHover") or rawget(h, "_zDragging") or (Kit.edit and Kit.selected == h)
    if spec.paint then
        spec.paint(h, { locked = locked, hover = hover and true or false })
    elseif h._zFill then
        local edit = Kit.edit
        local a = Col("accent")
        local strips = rawget(h, "_zui_borderTex")
        if edit and not locked then
            -- EDIT MODE (2026-11-09 redesign): a dark box with a thin accent
            -- edge, so the screen behind stays readable. The picked box is
            -- lit; a box that follows another wears the link colour.
            local sel = Kit.selected == h
            local follows = edit.follows and edit.follows(h) or nil
            local bg = ns.GetColor("ui", "windowBg")
            if spec.clear then
                -- a box over something that is drawn while Edit Mode is
                -- open (a class HUD's row): the real thing shows through
                h._zFill:SetColorTexture(bg.r + a.r * 0.14, bg.g + a.g * 0.14, bg.b + a.b * 0.14,
                    sel and 0.30 or hover and 0.22 or 0.10)
            elseif sel then
                h._zFill:SetColorTexture(bg.r + a.r * 0.14, bg.g + a.g * 0.14, bg.b + a.b * 0.14, 0.86)
            else
                h._zFill:SetColorTexture(bg.r, bg.g, bg.b, hover and 0.82 or 0.70)
            end
            local er, eg, eb, ea = a.r, a.g, a.b, hover and 0.9 or 0.55
            if follows then er, eg, eb, ea = Kit.LINK[1], Kit.LINK[2], Kit.LINK[3], 0.85
            elseif sel then er, eg, eb, ea = math.min(1, a.r * 1.15), math.min(1, a.g * 1.15), math.min(1, a.b * 1.15), 1 end
            if strips then for _, t in ipairs(strips) do t:SetColorTexture(er, eg, eb, ea) end end
            rawset(h, "_zFollows", follows)
        else
            local c
            if locked then c = ns.GetColor("text", "red")
            elseif spec.color then c = spec.color
            else c = a end
            h._zFill:SetColorTexture(c.r or c[1], c.g or c[2], c.b or c[3], hover and 0.5 or 0.3)
            if strips then for _, t in ipairs(strips) do t:SetColorTexture(a.r, a.g, a.b, 0.9) end end
            rawset(h, "_zFollows", nil)
        end
    end
    if h._zLabel then
        h._zLabel._zPaintKey = locked and "red" or "normal"
        h._zLabel:_zPaint()
        -- a box that follows another: its name in the link colour and
        -- what it follows written under it
        local follows = rawget(h, "_zFollows")
        local sub = rawget(h, "_zSub")
        if follows and not locked then
            h._zLabel:SetTextColor(Kit.LINK[1], Kit.LINK[2], Kit.LINK[3], 1)
            if not sub then
                sub = UI.Font(h, (UI.F and UI.F.SMALL) or 10, { cat = "text", key = "gray" })
                rawset(h, "_zSub", sub)
            end
            sub:SetText("follows " .. tostring(follows))
            sub:ClearAllPoints()
            sub:SetPoint("TOP", h._zLabel, "BOTTOM", 0, -1)
            sub:SetShown(rawget(h, "_zLabelInside") == true and (h:GetHeight() or 0) >= 30)
        elseif sub then
            sub:Hide()
        end
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
    -- (Edit Mode: the picked box keeps its numbers up)
    local show = rawget(h, "_zHover") or rawget(h, "_zDragging") or (Kit.edit and Kit.selected == h)
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

-- ------------------------------------------------------------
-- THE KIT'S OWN DRAG (Edit Mode only): the box follows the cursor from
-- where it was picked up, in UIParent units; Shift keeps it on the axis
-- it has moved furthest along, and Edit Mode's snap gets the last word.
-- Nothing happens until the cursor has actually moved, so picking a box
-- up and putting it down again leaves it exactly where it was.
-- ------------------------------------------------------------
local function HandleScale(h)
    local us = UIParent:GetEffectiveScale() or 1
    local k = (h.GetEffectiveScale and h:GetEffectiveScale() or us) / (us > 0 and us or 1)
    return k > 0 and k or 1
end

local function CursorUI()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale() or 1
    if s <= 0 then s = 1 end
    return (x or 0) / s, (y or 0) / s
end

local WOBBLE = 6        -- UI units a drag must travel before the box moves (Edit Mode)
local function ManualStart(h)
    local l, b, w, ht = h:GetRect()
    if not (l and b and w and ht) then return end
    local k = HandleScale(h)
    local cx, cy = CursorUI()
    rawset(h, "_zManual", { cx = cx, cy = cy, l = l * k, b = b * k, w = w * k, h = ht * k, k = k })
    h:ClearAllPoints()
    h:SetSize(w, ht)
    h:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
end

local function ManualStep(h)
    local st = rawget(h, "_zManual")
    if not st then return end
    local cx, cy = CursorUI()
    local dx, dy = cx - st.cx, cy - st.cy
    if not st.moved then
        -- (2026-11-10, Zac: "my target frame moved and is in the wrong spot")
        -- A press that wobbles a few pixels is a click, not a move: until
        -- the cursor has gone WOBBLE from where the drag began the box
        -- stays put - before, half a pixel was enough, and snapping then
        -- pulled the box up to 8 onto the nearest edge.
        if math.abs(dx) < WOBBLE and math.abs(dy) < WOBBLE then return end
        st.moved = true
    end
    if IsShiftKeyDown() then
        if math.abs(dx) >= math.abs(dy) then dy = 0 else dx = 0 end
    end
    local l, b = st.l + dx, st.b + dy
    local edit = Kit.edit
    if edit and edit.snap then l, b = edit.snap(h, l, b, st.w, st.h) end
    h:ClearAllPoints()
    h:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l / st.k, b / st.k)
end
Kit.ManualStep = ManualStep

local function Changed(h)
    local edit = Kit.edit
    if edit and edit.changed then edit.changed(h) end
end

-- live work while hovered or dragged: the owner's follow, then the readout
local function Tick(self, elapsed)
    local spec = Spec(self)
    if rawget(self, "_zDragging") and rawget(self, "_zManual") then ManualStep(self) end
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
    Changed(h)
    return true
end

function Kit.Reset(h)
    local spec = Spec(h)
    if not (spec and spec.reset) then return false end
    if IsLocked(h) then SayLocked(h) return false end
    spec.reset(h)
    Kit.Refresh(h)
    Kit.UpdateReadout(h)
    Changed(h)
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
    local edit = Kit.edit
    if edit and edit.key and edit.key(key) then
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        return
    end
    local h = self.target
    if not h and edit and Kit.selected and Kit.selected:IsShown() then h = Kit.selected end
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

-- Edit Mode keeps the keyboard frame up for its whole pass (arrow keys for
-- the selected box, its own keys through edit.key); off puts it back to
-- "only while a box is hovered"
function Kit.EditKeys(on)
    if InCombatLockdown() then return end
    if keyFrame.SetPropagateKeyboardInput then keyFrame:SetPropagateKeyboardInput(true) end
    if on then
        keyFrame:Show()
    else
        keyFrame.target = nil
        keyFrame:Hide()
    end
end

-- the box picked in Edit Mode (nil clears); repaints the old and the new
function Kit.Select(h)
    local old = Kit.selected
    Kit.selected = h
    if old and old ~= h and Spec(old) then Paint(old) Kit.UpdateReadout(old) end
    if h and Spec(h) then Paint(h) Kit.UpdateReadout(h) end
end

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
                if Kit.edit then
                    GameTooltip:AddLine("Shift keeps one direction; Alt places it without snapping.", 0.8, 0.8, 0.8, true)
                end
                if spec.nudge then
                    GameTooltip:AddLine("Arrow keys or mouse wheel nudge (Shift: 10, Ctrl + wheel: sideways).", 0.8, 0.8, 0.8, true)
                end
                if Kit.edit and Kit.edit.menu then
                    GameTooltip:AddLine("Click it for its actions (attach, match size, reset, settings); right-click for the same as a menu.", 0.8, 0.8, 0.8, true)
                elseif spec.reset then
                    GameTooltip:AddLine("Right-click: back to its default spot.", 0.8, 0.8, 0.8, true)
                end
            end
            if spec.hint then GameTooltip:AddLine(spec.hint, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end
    else
        if keyFrame.target == h then
            keyFrame.target = nil
            if not Kit.edit then keyFrame:Hide() end
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
        -- an editing overlay never changes look: the pixel strips, always
        AddPixelBorder(h, "accent", 0.9, "pixel")
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
        local edit = Kit.edit
        if edit then
            -- the kit follows the cursor itself; an owner's dragStart still
            -- runs, and the StartMoving it calls starts that follow
            if edit.select then edit.select(self) end
            if s.dragStart then
                rawset(self, "StartMoving", ManualStart)
                local ok, err = pcall(s.dragStart, self)
                rawset(self, "StartMoving", nil)
                if not ok and geterrorhandler then geterrorhandler()(err) end
            else
                ManualStart(self)
            end
        elseif s.dragStart then s.dragStart(self) else self:StartMoving() end
        Paint(self)
        Watch(self)
    end)
    h:SetScript("OnDragStop", function(self)
        if not rawget(self, "_zDragging") then return end
        rawset(self, "_zDragging", nil)
        self:StopMovingOrSizing()
        if rawget(self, "_zManual") then
            ManualStep(self)
            local st = rawget(self, "_zManual")
            local went = st.moved
            if not went then
                -- (moved by its owner rather than by the cursor: it did go)
                local l, b = self:GetRect()
                went = l and b and (math.abs(l * st.k - st.l) > 0.5 or math.abs(b * st.k - st.b) > 0.5) or false
            end
            rawset(self, "_zManual", nil)
            if not went then
                -- it never left its spot: nothing to save, nothing changed -
                -- the box goes back onto its frame and the press was a click
                Kit.Refresh(self)
                Watch(self)
                local edit = Kit.edit
                if edit and edit.select then edit.select(self) end
                return
            end
            local edit = Kit.edit
            if edit and edit.dropped then edit.dropped(self) end
        end
        local s = Spec(self)
        if s.onDrag then s.onDrag(self) end
        if s.dragStop then s.dragStop(self) end
        Kit.Refresh(self)
        Watch(self)
        Changed(self)
    end)
    h:SetScript("OnMouseDown", function(self) rawset(self, "_zDragged", nil) end)
    h:SetScript("OnMouseUp", function(self, button)
        local s = Spec(self)
        local edit = Kit.edit
        if button == "RightButton" then
            if not (edit and edit.menu and edit.menu(self)) then Kit.Reset(self) end
        elseif not rawget(self, "_zDragged") then
            if edit and edit.select then edit.select(self) end
            if s.click then s.click(self, button) end
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
        rawset(self, "_zManual", nil)
        if Kit.selected == self then Kit.selected = nil end
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
--   size = { get = fn() -> w, h, set = fn(w, h) }   its size can be set
--                    (Edit Mode's Match width / height; either may be nil)
--   page, tab        the settings page (menu id) and tab that style it
--                    (Edit Mode's "Open its settings"; else guessed by key)
--   off              fn() -> reason string when it is switched off, nil on
--   screen           true: follows the pieces' one scale (ns.Screen, below);
--                    false: never; nil: by its key (SCREEN_KEYS)
--   scale            its own size in Edit Mode (A SIZE OF ITS OWN FOR EACH
--                    PIECE, below). { get = fn() -> k, set = fn(k), keep }
--                    when its part already has a scale setting (keep = true:
--                    the scale is set on this frame itself, so its saved
--                    spot is rewritten to stay put); false: none; nil: the
--                    registry's own (ZacUIDB.moverScale)
--   sizes            its other sizes, for Edit Mode's size rows (width,
--                    height, icon size, spacing ...): a list, or a function
--                    returning one, of { label, unit, min, max, step, fine,
--                    def, get = fn() -> v, set = fn(v) } - each reads and
--                    writes the setting the piece's own page has
-- Registering the same key again updates it in place (no second row).
-- ============================================================
-- NEW DEFAULT SPOTS (2026-11-10, Zac: "i dont want someone to turn a
-- feature on and go wtf is this position")
-- ============================================================
-- Only an install made from now on gets them (ZacUIDB.defaultsGen = 2,
-- stamped by Boot_Events on a fresh install or a full reset): a frame an
-- existing player never moved stays exactly where it was. Each spot was
-- checked against Blizzard's default layout on a 1920 x 1080 screen (the
-- chat, the bars, the party frames, the quest tracker, the buffs) and
-- against the other parts' default spots; where Zac's own Classic Era
-- screen has the frame, his spot is the one taken.
--   lootroll        was TOP 0,-220: under the scrolling text and the pull
--                   timers. Zac's: left of centre, over the chat.
--   snowball        was CENTER 776,254: on the quest tracker.
--   qoldistance     was CENTER 0,-110: on the class HUD's debuff row.
--   buffRemIcon     was CENTER 200,0: in the outgoing damage text.
--   talentreminder  was TOPRIGHT -230,-12: on the buffs.
--   qolalerts       was CENTER 0,169: on the raid warnings and the
--                   hesitation alert.
--   qolreminders    was CENTER 0,230: on the raid mods' text alerts.
--   qolstats        was BOTTOMLEFT 300,220: on the chat's top corner.
local GEN2 = {
    lootroll       = { "LEFT", 405, 122 },
    snowball       = { "BOTTOM", 330, 190 },
    qoldistance    = { "CENTER", 0, -75 },
    -- (right of the character, clear of the raid mods' alert text and
    -- the range circle that share the centre column)
    buffRemIcon    = { "CENTER", 150, 40 },
    -- (above the flight timer and the scrolling text, under the top bars)
    talentreminder = { "TOP", 0, -89 },
    -- (off the class HUD: with the other reminders on the left)
    qoljunk        = { "CENTER", -330, 208 },
    qolalerts      = { "CENTER", 0, 132 },
    qolreminders   = { "CENTER", -330, 170 },
    qolstats       = { "BOTTOMLEFT", 30, 290 },
}
function ns.NewDefaults()
    return type(ZacUIDB) == "table" and (tonumber(ZacUIDB.defaultsGen) or 1) >= 2
end
local function Gen2(m)
    local g = GEN2[m.key]
    if g and ns.NewDefaults() then
        m.defPoint, m.defX, m.defY = g[1], g[2], g[3]
        m._gen2 = true
    end
end
-- the movers registered before the saved settings were there (Boot calls
-- this once they are)
function ns.MoversNewDefaults()
    for _, m in ipairs(MOVERS) do Gen2(m) end
end

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
        m.size, m.page, m.tab, m.off = opts.size, opts.page, opts.tab, opts.off
        m.clear = opts.clear
        m.exact = opts.exact
        m.screen = opts.screen
        m.scale = opts.scale
        m.sizes = opts.sizes
    end
    Gen2(m)
    -- (a part that put its frame on the old spot before registering: onto
    -- the new one now, unless the player has a spot saved)
    if m._gen2 and ns.ApplyMover then pcall(ns.ApplyMover, key) end
    local p = moverProxies[key]
    if p and p:IsShown() then Kit.Refresh(p) end
    -- (the pieces' one scale, below: a piece registered while it is in use)
    if ns.Screen and ns.Screen.Scale() ~= 1 then pcall(ns.Screen.Apply) end
    -- (and its own size, when one is saved)
    if ns.MoverScaleApply and type(ZacUIDB) == "table" and type(ZacUIDB.moverScale) == "table"
        and ZacUIDB.moverScale[key] ~= nil then
        pcall(ns.MoverScaleApply, key)
    end
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
local function MoverBlocked(key, f, quiet)
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
    if not quiet and not moverSkipNoted[key] then
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
    -- (2026-11-10, Zac: "move ui for huds ... needs to reflect the actual
    -- thing") a HUD holder holds one small anchor and the icons hang off
    -- that, so one level saw a 26 px square. Three levels down takes in
    -- the icons and bars themselves.
    local function Take(frame, depth)
        if not frame.GetChildren then return end
        for _, c in ipairs({ frame:GetChildren() }) do
            if c.IsShown and c:IsShown() then
                local cl, cb, cw, ch = FrameRect(c)
                if cl then
                    if cl < l then l = cl end
                    if cb < b then b = cb end
                    if cl + cw > r then r = cl + cw end
                    if cb + ch > t then t = cb + ch end
                end
                if depth < 3 then Take(c, depth + 1) end
            end
        end
    end
    Take(f, 1)
    return l, b, r - l, t - b
end

local function SetFramePos(f, point, x, y)
    f:ClearAllPoints()
    f:SetPoint(point or "CENTER", UIParent, point or "CENTER", x or 0, y or 0)
end

local PieceApply   -- forward: the piece's own size (below)
local function ApplyMover(key)
    local m = MOVERS[key]
    local pos = m and SavedPos(m)
    local f = m and m.getFrame()
    if m and f and PieceApply then PieceApply(m, f) end
    -- never moved, on an install with the new default spots: the part put
    -- the frame on its old spot just before this call
    if m and f and not pos and m._gen2 and m.defPoint and not m.reset then
        if MoverBlocked(key, f) then return end
        if InCombatLockdown() and IsSecure(m, f) then
            pending[key] = pending[key] or "reset"
            return
        end
        SetFramePos(f, m.defPoint, m.defX, m.defY)
        return
    end
    if not (pos and f) then return end
    if MoverBlocked(key, f) then return end
    if InCombatLockdown() and IsSecure(m, f) then
        pending[key] = pending[key] or "apply"
        return
    end
    SetFramePos(f, pos.point, pos.x, pos.y)
    -- frames attached to this one follow it (UIF_EditSession; one table
    -- read when nothing is attached)
    if ns.MoverMoved then ns.MoverMoved(key) end
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
    if f and FrameRect(f) and not m.exact then dl, db, dw, dh = DrawnRect(f, l, b, w, h) end
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
    -- (its own size goes back with it: the default spot is a spot at 100 %)
    if ns.MoverScaleClear then ns.MoverScaleClear(key) end
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
        clear = (M() and M().clear) or nil,
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
            -- snapped onto another frame's edge in Edit Mode: kept to the
            -- hundredth, so it stays exactly on it; else whole units
            local R = rawget(self, "_zSnapped") and Hundredths or Round
            rawset(self, "_zSnapped", nil)
            WritePos(m, point, R(x), R(y))
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

-- ============================================================
-- ONE SCALE FOR THE PIECES ON THE SCREEN (2026-11-19, Zac: "so many things
-- in both addons need proper ui scaling ... someone on 1080p or 1440p")
-- ============================================================
-- Every piece listed on the Movers page - the class HUDs' rows and bars,
-- the trackers, timers, alerts, reminders, the raid mods' bars, the
-- consumables bar - has a size of its own, and a player on a smaller
-- screen had to go through them one by one. ZacUIDB.config.pieceScale
-- (0.5 to 1.5, nil = 1) sizes them all at once.
--   HOW. The pieces that sit on the screen itself (their parent is
--   UIParent) are moved under one plain frame, ZacUIScreen, that covers
--   the screen and carries the scale. A frame's size and its offsets are
--   both in its own units, so a piece gets smaller or bigger AND keeps
--   its place in the layout: 208 under the centre becomes 166 under it at
--   80%, a bar at the left edge stays at the left edge. Nothing saved is
--   rewritten; back at 100% everything is exactly where it was.
--   WHO IS LEFT ALONE. At 100% - every install until its owner moves the
--   slider - no frame is touched at all: not one is reparented, so
--   nothing can differ. Only a piece that says so is taken (opts.screen
--   at registration, which every HUD.RegisterMover piece gets, or its key
--   in SCREEN_KEYS): one whose whole drawing hangs under the registered
--   frame and whose spot is kept in that frame's own units. NOT taken:
--   the game's own frames (minimap, buffs, loot rolls), and the pieces
--   with a scale setting and drag code of their own - the raid mods' bars,
--   the blessings bar, the buff tracker (its click layer lies on the
--   screen), the Snowball button (its secure button sits beside its
--   holder). The unit frames, action bars, meter windows and nameplates
--   follow the same number without being moved (Screen.OnChange, below).
--   A piece that holds secure buttons is taken, and the scale changed,
--   only outside a fight (the rest waits for the fight to end).
local Screen = {}
ns.Screen = Screen
Screen.MIN, Screen.MAX = 0.5, 1.5
local SCREEN_KEYS = {
    flighttimer = true, raidtimers = true, buffRemIcon = true,
    qoljunk = true, qolreminders = true, gcdtracker = true, talentreminder = true,
    qolstats = true, qolalerts = true, lootfeed = true, qoldistance = true,
}
function Screen.Covers(key)
    local m = MOVERS[key]
    return (m ~= nil and (m.screen == true or (m.screen == nil and SCREEN_KEYS[key] == true))) or false
end
local screenHolder
local screenTaken = setmetatable({}, { __mode = "k" })
local screenWait, screenTicker = false, nil

function Screen.Scale()
    local c = type(ZacUIDB) == "table" and ZacUIDB.config
    local v = type(c) == "table" and tonumber(c.pieceScale) or 1
    if v ~= v then v = 1 end
    if v < Screen.MIN then v = Screen.MIN elseif v > Screen.MAX then v = Screen.MAX end
    if math.abs(v - 1) < 0.005 then v = 1 end
    return v
end
function Screen.Holder() return screenHolder end
function Screen.Has(f) return f ~= nil and screenTaken[f] == true end

local function ScreenHolder()
    if not screenHolder then
        screenHolder = CreateFrame("Frame", "ZacUIScreen", UIParent)
        screenHolder:SetAllPoints(UIParent)
    end
    return screenHolder
end

-- one piece under the holder; false when it has to wait for the fight to end
local function ScreenTake(f)
    if type(f) ~= "table" or screenTaken[f] or f == screenHolder then return true end
    if not f.GetParent or f:GetParent() ~= UIParent then return true end
    if InCombatLockdown() and f.IsProtected and f:IsProtected() then return false end
    local strata = f.GetFrameStrata and f:GetFrameStrata()
    local level = f.GetFrameLevel and f:GetFrameLevel()
    f:SetParent(ScreenHolder())
    -- (a new parent hands the frame its own strata and a level under it)
    if strata and f.SetFrameStrata then f:SetFrameStrata(strata) end
    if level and f.SetFrameLevel then f:SetFrameLevel(level) end
    screenTaken[f] = true
    return true
end

local function ScreenSweep()
    local all = true
    for _, m in ipairs(MOVERS) do
        if m.getFrame and Screen.Covers(m.key) then
            local ok, f = pcall(m.getFrame)
            if ok and f and not screenTaken[f] and not MoverBlocked(m.key, f, true) then
                if not ScreenTake(f) then all = false end
            end
        end
    end
    return all
end

-- The scale as saved, onto the screen. Safe to call at any time.
function Screen.Apply()
    local k = Screen.Scale()
    if k == 1 and not screenHolder then return true end   -- never used: nothing exists, nothing to do
    if InCombatLockdown() then
        screenWait = true
        return false
    end
    ScreenHolder():SetScale(k)
    local all = true
    if k ~= 1 then
        all = ScreenSweep()
        -- pieces are made as they are first needed (a HUD row, a raid's
        -- bars): looked for again every two seconds while the scale is in use
        if not screenTicker and C_Timer and C_Timer.NewTicker then
            screenTicker = C_Timer.NewTicker(2, function()
                if Screen.Scale() == 1 then
                    screenTicker:Cancel()
                    screenTicker = nil
                    return
                end
                if not ScreenSweep() then screenWait = true end
            end)
            if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(screenTicker, "movers.screen") end
        end
    end
    if not all then screenWait = true end
    return all
end

-- (2026-11-20) THE PIECES THAT KEEP THEIR OWN PARENT. The unit frames, the
-- action bars, the meter's windows and the nameplates place and drag
-- themselves, so they are not moved under the screen frame: each
-- multiplies its own scale by Screen.Scale() where it already sets it,
-- and asks here to be told when the number changes.
--   Screen.OnChange(fn)   fn() after every Screen.Set (and a wait for the
--                         fight to end is the listener's own business)
local screenHooks = {}
function Screen.OnChange(fn)
    if type(fn) == "function" then screenHooks[#screenHooks + 1] = fn end
end
function Screen.Notify()
    for i = 1, #screenHooks do pcall(screenHooks[i]) end
end

function Screen.Set(v)
    if type(ZacUIDB) ~= "table" then return end
    ZacUIDB.config = ZacUIDB.config or {}
    v = tonumber(v) or 1
    if v < Screen.MIN then v = Screen.MIN elseif v > Screen.MAX then v = Screen.MAX end
    ZacUIDB.config.pieceScale = (math.abs(v - 1) >= 0.005) and v or nil
    Screen.Apply()
    Screen.Notify()
    if ns.SettingsChanged then ns.SettingsChanged("screen.scale") end
end

do
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if screenWait then
                screenWait = false
                Screen.Apply()
            end
        elseif Screen.Scale() ~= 1 then
            Screen.Apply()
        end
    end)
end

local function ApplyAllMovers()
    Screen.Apply()
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
    "TOP", 0, -220, true,
    -- (2026-11-20) the bars' width and height on their box in Edit Mode:
    -- the Loot rolls page's own two sliders (ZacUI's bars only)
    { sizes = function()
        local LR = ns.LootRoll
        if not (LR and LR.V and _G.ZacUI_LootRollHolder) then return nil end
        local function Row(label, key, lo, hi, step)
            return { label = label, unit = "px", min = lo, max = hi, step = step, fine = 1,
                def = LR.Defaults(LR.Cfg())[key],
                get = function() return LR.V(LR.Cfg(), key) end,
                set = function(v)
                    if type(ZacUIDB.lootRoll) ~= "table" then ZacUIDB.lootRoll = {} end
                    local d = LR.Defaults(ZacUIDB.lootRoll)[key]
                    ZacUIDB.lootRoll[key] = (v ~= d) and v or nil
                    if next(ZacUIDB.lootRoll) == nil then ZacUIDB.lootRoll = nil end
                    if LR.ApplyLive then LR.ApplyLive() end
                end }
        end
        return { Row("Width", "width", 120, 400, 10), Row("Height", "height", 12, 40, 2) }
    end })
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

-- ------------------------------------------------------------
-- FOR EDIT MODE'S SESSION (UIF_EditSession): a mover's spot of record as a
-- copy, put back from one, and moved by a whole-screen delta. The record
-- stays exactly what it always was (ZacUIDB.movers[key] = { point, x, y },
-- or the owner's own get / set), so everything else that reads it - the
-- preview drags, the HUDs, profiles - reads the same numbers.
-- ------------------------------------------------------------
local function CopyPos(p)
    if type(p) ~= "table" then return false end
    return { point = p.point, x = p.x, y = p.y }
end

-- where the frame is now, in its own convention (the saved spot, else
-- read off the frame)
local function FrameSpot(m)
    local saved = SavedPos(m)
    if saved then return saved.point or "CENTER", saved.x or 0, saved.y or 0 end
    local f = m.getFrame()
    local point = m.defPoint or "CENTER"
    local l, b, w, h = FrameRect(f)
    if not l then return point, m.defX or 0, m.defY or 0 end
    local pp = POINTS[point] or POINTS.CENTER
    local ux, uy = UIPoint(point)
    local k = ScaleOf(f)
    return point, (l + w * pp[1] - ux) / k, (b + h * pp[2] - uy) / k
end

local function RefitProxy(key)
    local p = moverProxies[key]
    if p and p:IsShown() and not rawget(p, "_zDragging") then
        FitProxy(p)
        Kit.Refresh(p)
    end
end

-- ============================================================
-- A SIZE OF ITS OWN FOR EACH PIECE (2026-11-19, Zac: "it all needs to be
-- customizable literally everything")
-- ============================================================
-- Edit Mode's picked box has Smaller / Bigger: the piece's own scale, 50
-- to 200 %.
--   * a piece whose part already has a scale setting says so when it
--     registers (opts.scale = { get, set }): Edit Mode then changes that
--     one number, the same its settings page shows;
--   * every other piece: ZacUIDB.moverScale[key] (nothing saved = 100 %),
--     set on the piece's frame. It multiplies with the pieces' one scale
--     (ns.Screen), which sits on the frame above;
--   * opts.scale == false, a "move all" handle (exact) and the client's
--     own frames (reflow: the buffs, the minimap, the loot rolls) have
--     none.
-- THE PIECE STAYS WHERE IT IS. A SetPoint offset is in the frame's own
-- units, so a bare SetScale would slide it; the saved spot is rewritten
-- for the new scale (the same spot on the screen, as a drag writes it).
-- Reset puts the size back with the spot. Frames that hold secure buttons
-- wait for the fight to end.
local PIECE_MIN, PIECE_MAX = 0.5, 2
local function PieceCan(m)
    if not m or m.scale == false or m.exact or m.reflow then return false end
    return true
end
local function PieceOwn(m) return type(m.scale) == "table" and type(m.scale.set) == "function" end
local function PieceSaved(key)
    local t = type(ZacUIDB) == "table" and ZacUIDB.moverScale
    local v = type(t) == "table" and tonumber(t[key]) or nil
    if not v or v ~= v then return 1 end
    return math.max(PIECE_MIN, math.min(PIECE_MAX, v))
end
-- the piece's size now (nil: it has none of its own)
local function PieceScale(key)
    local m = MOVERS[key]
    if not PieceCan(m) then return nil end
    if PieceOwn(m) then
        local ok, v = pcall(m.scale.get)
        v = ok and tonumber(v) or 1
        return (v and v > 0) and v or 1
    end
    return PieceSaved(key)
end
-- The saved size onto the frame (the registry's own only). A frame that
-- never had one is never touched.
PieceApply = function(m, f)
    if not PieceCan(m) or PieceOwn(m) then return end
    f = f or m.getFrame()
    if not (f and f.SetScale) then return end
    local k = PieceSaved(m.key)
    if k == 1 and m._zPiece ~= f then return end
    if m._zPiece == f and math.abs((m._zPieceK or 1) - k) < 0.0005 then return end
    if MoverBlocked(m.key, f, true) then return end
    if InCombatLockdown() and IsSecure(m, f) then
        pending[m.key] = pending[m.key] or "apply"
        return
    end
    -- (a show animation holds the frame under its scale for a moment: it
    -- is left to finish, the watch below comes back)
    if ns.Motion and ns.Motion.IsPlaying and ns.Motion.IsPlaying(f) then return end
    f:SetScale(k)
    if k == 1 then m._zPiece, m._zPieceK = nil, nil else m._zPiece, m._zPieceK = f, k end
end
-- pieces made after login, a profile worn: looked at every two seconds
-- while any piece has a size saved
local pieceTicker
local function PieceWatch()
    if pieceTicker or not (C_Timer and C_Timer.NewTicker) then return end
    if not (type(ZacUIDB) == "table" and type(ZacUIDB.moverScale) == "table" and next(ZacUIDB.moverScale)) then return end
    pieceTicker = C_Timer.NewTicker(2, function()
        local t = type(ZacUIDB) == "table" and ZacUIDB.moverScale
        local any = false
        for _, m in ipairs(MOVERS) do
            if m._zPiece or (type(t) == "table" and t[m.key] ~= nil) then
                any = true
                PieceApply(m)
            end
        end
        if not any and pieceTicker then
            pieceTicker:Cancel()
            pieceTicker = nil
        end
    end)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(pieceTicker, "movers.pieces") end
end
local function PieceStore(key, v)
    if type(ZacUIDB) ~= "table" then return end
    if v and math.abs(v - 1) >= 0.005 then
        ZacUIDB.moverScale = ZacUIDB.moverScale or {}
        ZacUIDB.moverScale[key] = v
    elseif type(ZacUIDB.moverScale) == "table" then
        ZacUIDB.moverScale[key] = nil
        if not next(ZacUIDB.moverScale) then ZacUIDB.moverScale = nil end
    end
end
-- The size, with no word on the spot (a put-back writes the spot itself).
local function PieceRaw(m, v)
    if PieceOwn(m) then
        local cur = PieceScale(m.key) or 1
        if math.abs(cur - v) >= 0.0005 then pcall(m.scale.set, v) end
        return
    end
    PieceStore(m.key, v)
    PieceApply(m)
    PieceWatch()
end
-- -> true, or false + why
local function SetPieceScale(key, v)
    local m = MOVERS[key]
    if not PieceCan(m) then return false, "It has no size of its own." end
    v = tonumber(v)
    if not v or v ~= v then return false, "not a number" end
    local lo = (PieceOwn(m) and tonumber(m.scale.min)) or PIECE_MIN
    local hi = (PieceOwn(m) and tonumber(m.scale.max)) or PIECE_MAX
    v = math.max(lo, math.min(hi, math_floor(v * 100 + 0.5) / 100))
    local f = m.getFrame()
    if f and MoverBlocked(key, f, true) then return false, "The game places this one." end
    if f and InCombatLockdown() and IsSecure(m, f) then return false, "It holds buttons: after the fight." end
    local old = PieceScale(key) or 1
    if math.abs(old - v) < 0.0005 then return true end
    -- where it is now, in its own numbers
    local keep = f ~= nil and (not PieceOwn(m) or m.scale.keep == true)
    local point, x, y, k1
    if keep then
        point, x, y = FrameSpot(m)
        k1 = ScaleOf(f)
    end
    if PieceOwn(m) then
        local ok, err = pcall(m.scale.set, v)
        if not ok then return false, tostring(err) end
    else
        PieceStore(key, v)
        PieceApply(m, f)
    end
    if keep then
        local k2 = ScaleOf(f)
        if k1 and k2 > 0 and math.abs(k1 - k2) > 0.00005 then
            WritePos(m, point, Hundredths(x * k1 / k2), Hundredths(y * k1 / k2))
            ApplyMover(key)
        end
    end
    RefitProxy(key)
    PieceWatch()
    if ns.SettingsChanged then ns.SettingsChanged("mover.scale") end
    return true
end
ns.MoverScale = PieceScale
ns.SetMoverScale = SetPieceScale
ns.MoverScaleLimits = function(key)
    local m = MOVERS[key]
    if not PieceCan(m) then return nil end
    if PieceOwn(m) then return tonumber(m.scale.min) or PIECE_MIN, tonumber(m.scale.max) or PIECE_MAX end
    return PIECE_MIN, PIECE_MAX
end
ns.MoverScaleApply = function(key)
    local m = MOVERS[key]
    if m then PieceApply(m) PieceWatch() end
end
-- the registry's own size back to 100 % (Reset; the spot is the caller's)
ns.MoverScaleClear = function(key)
    local m = MOVERS[key]
    if not (m and PieceCan(m)) or PieceOwn(m) then return end
    if PieceSaved(key) == 1 and not m._zPiece then return end
    local f = m.getFrame()
    if f and InCombatLockdown() and IsSecure(m, f) then return end
    PieceStore(key, nil)
    PieceApply(m, f)
end

-- ============================================================
-- A PIECE'S OTHER SIZES (2026-11-19, Zac: "everything needs full sizing
-- width height and scaling/overall scaling of the entire thing")
-- ============================================================
-- Beside its scale a piece has the sizes its settings page has - a bar's
-- width and height, a row's icon size and spacing. A piece says them when
-- it registers (opts.sizes); Edit Mode shows a row for each under the
-- picked box. Nothing new is saved here: an entry's get / set are the
-- page's own setting.
local function PieceSizes(key)
    local m = MOVERS[key]
    local s = m and m.sizes
    if type(s) == "function" then
        local ok, list = pcall(s)
        s = ok and list or nil
    end
    return (type(s) == "table" and #s > 0) and s or nil
end
local function SizeClamp(size, v)
    local lo, hi = tonumber(size.min), tonumber(size.max)
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    if size.unit == "%" then return math_floor(v * 100 + 0.5) / 100 end
    return math_floor(v + 0.5)
end
-- -> true, or false + why
local function SetPieceSize(key, index, v)
    local m = MOVERS[key]
    local sizes = PieceSizes(key)
    local size = sizes and sizes[index or 1]
    v = tonumber(v)
    if not (size and v and v == v) then return false, "It has no such size." end
    local f = m.getFrame()
    if f and InCombatLockdown() and IsSecure(m, f) then return false, "It holds buttons: after the fight." end
    v = SizeClamp(size, v)
    local ok, cur = pcall(size.get)
    if ok and tonumber(cur) and math.abs(cur - v) < 0.0005 then return true end
    local done, err = pcall(size.set, v)
    if not done then return false, tostring(err) end
    RefitProxy(key)
    if ns.SettingsChanged then ns.SettingsChanged("mover.size") end
    return true
end
ns.MoverSizes = PieceSizes
ns.SetMoverSize = SetPieceSize
ns.MoverSizeClamp = SizeClamp

local function MoverSnapshot(key)
    local m = MOVERS[key]
    if not m then return nil end
    local snap = CopyPos(SavedPos(m))
    -- (its other sizes ride along, so Undo and Cancel put them back)
    local sizes = PieceSizes(key)
    if sizes then
        snap = snap or {}
        snap.sizes = {}
        for i, size in ipairs(sizes) do
            local ok, v = pcall(size.get)
            snap.sizes[i] = ok and tonumber(v) or false
        end
    end
    -- (its size rides along when it is not 100 %, so Undo and Cancel put
    -- both back; at 100 % the record is exactly what it always was)
    local k = PieceScale(key)
    if k and math.abs(k - 1) >= 0.005 then
        snap = snap or {}
        snap.scale = math_floor(k * 100 + 0.5) / 100
    end
    return snap
end

-- false / nil = nothing saved: the frame goes back to its default
local function MoverRestore(key, snap)
    local m = MOVERS[key]
    if not m then return end
    if PieceCan(m) then
        local f = m.getFrame()
        if not (f and InCombatLockdown() and IsSecure(m, f)) then
            PieceRaw(m, (type(snap) == "table" and tonumber(snap.scale)) or 1)
        end
    end
    if type(snap) == "table" and type(snap.sizes) == "table" then
        local sizes = PieceSizes(key)
        local f = m.getFrame()
        if sizes and not (f and InCombatLockdown() and IsSecure(m, f)) then
            for i, size in ipairs(sizes) do
                local want = tonumber(snap.sizes[i])
                local ok, cur = pcall(size.get)
                if want and ok and tonumber(cur) and math.abs(cur - want) >= 0.0005 then pcall(size.set, want) end
            end
        end
    end
    if type(snap) == "table" and snap.point then
        WritePos(m, snap.point, snap.x, snap.y)
        ApplyMover(key)
    else
        WritePos(m, nil)
        PlaceDefault(m)
    end
    RefitProxy(key)
end

-- moved by dx, dy UIParent units (a frame it is attached to moved); kept
-- to the hundredth so a follow never drifts
local function MoverShift(key, dx, dy)
    local m = MOVERS[key]
    local f = m and m.getFrame()
    if not f or MoverBlocked(key, f) then return false end
    if InCombatLockdown() and IsSecure(m, f) then return false end
    local point, x, y = FrameSpot(m)
    local k = ScaleOf(f)
    WritePos(m, point, Hundredths(x + dx / k), Hundredths(y + dy / k))
    ApplyMover(key)
    RefitProxy(key)
    return true
end

-- the frame's box in UIParent units, whether or not it is shown
local function MoverRect(key)
    local m = MOVERS[key]
    return FrameRect(m and m.getFrame())
end

-- shared with later ZacUI files
ns.MoverSnapshot = MoverSnapshot
ns.MoverRestore = MoverRestore
ns.MoverShift = MoverShift
ns.MoverRect = MoverRect
ns.MoverKit = Kit
-- every box that is up, fitted to its piece again now (the pieces' one
-- size changed while Edit Mode is open)
ns.MoverRefitAll = RefitShown
ns.ApplyAllMovers = ApplyAllMovers
ns.HideMover = HideMover
ns.MOVERS = MOVERS
ns.MoverBlocked = MoverBlocked
-- The class HUDs (and the drink ticker) register every one of their
-- anchors through this. It was never published, so HUD_Shared captured
-- nil, HUD.RegisterMover returned at its first line, and not one HUD
-- anchor ever reached the Movers page or Edit Mode - nor did the HUD
-- pages' own "Unlock / lock HUD anchors" button have anything to unlock.
-- EVERY MOVER, PLEASE. A part whose frames are only all there once
-- something of its own has been read in (the raid mods' five Classic raids
-- load on demand) hears here that the whole list is about to be shown or
-- walked for the player - the Movers page, Edit Mode, a layout, /zui
-- movers - and registers what is missing first.
--   ns.OnMoversAsk(fn)   fn() runs at every such moment
--   ns.MoversAsk()       the moment (called by whoever is about to walk ns.MOVERS for the player)
local askers = {}
function ns.OnMoversAsk(fn)
    if type(fn) == "function" then askers[#askers + 1] = fn end
end
function ns.MoversAsk()
    for i = 1, #askers do pcall(askers[i]) end
end

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

-- ============================================================
-- UNDER THE MAP (2026-11-20, Zac, with pictures of a reminder icon, bar
-- icons, a button's name and timer texts drawn over the open world map:
-- "can you fix things like this" ... "i know i pointed out 1 thing but it
-- needs to be fixed for all")
-- ============================================================
-- WHY THEY WERE ON TOP. The game's map as a window is on the MEDIUM layer
-- and is not a "top level" window, so its frame level stays low: every
-- piece on MEDIUM with a higher level, and every piece on HIGH or above,
-- is drawn over it. Raising the map instead is not on the table: it would
-- also go over bags, the character window and every popup (Maps_Skin:
-- NOTHING FLOATS OVER THE MAP - AND NOT BY RAISING THE MAP).
--
-- WHAT HAPPENS. While the map window is open every on-screen piece of
-- ZacUI's whose box overlaps the map's is put one layer under the map, and
-- put back the moment the map closes, the piece hides or the two no longer
-- overlap. Nothing saved is touched; a piece beside the map is not
-- touched; full screen the map is on a layer above every piece already.
--   ALL OF THEM, NOT A LIST OF THE ONES SEEN IN A PICTURE:
--     1. every registered mover's frame;
--     2. what the parts add (ns.UnderMap.Add(fn(each)): the unit frames,
--        the action bars, the meter's windows, the raid mods' widgets, the
--        aura displays). each(frame, "piece") names a piece that stands on
--        a window's layer (the soft-target arrows are on the dialog
--        layer); each(frame, "always") one with no box of its own;
--     3. THE NET: every frame on the screen (a child of UIParent or of
--        the pieces' holder) that ZacUI's code made, whoever forgot to
--        list it - the hesitation plate, the raid chat toasts, the loot
--        roll bars. Whose it is comes from the client itself
--        (issecurevariable names the addon that made a global or wrote a
--        field), so no other addon's frame and nothing of the game's is
--        ever touched - a game window ZacUI only skinned is the game's.
--   INSIDE A PIECE. A child that was put on a layer of its own (a text
--   layer on HIGH) does not follow its parent down on this client: each is
--   put under by itself and its own layer is noted first, so it goes back
--   to exactly that - also where the parent's change does carry it along.
--   BESIDE A PIECE. Frames in frame._zSatellites go with it.
--   AT ONCE. A piece that shows, or sets its own layer again, while the
--   map is open is looked at in that same moment (its OnShow and
--   SetFrameStrata are hooked once), not at the next quarter second.
--   NEVER a window: a top-level frame, one on the dialog layers that is
--   not named a piece (PIECE_NAMES, or by its part), the few windows on
--   lower layers (WINDOW_NAMES), anything the two map parts made;
--   and never a frame that fills the screen (a holder, not a piece).
--   IN A FIGHT a secure frame cannot change layer: it is left as it is and
--   looked at again when the fight ends (its texts still go under).
--   OFF: ZacUIDB.config.underMap = false (Maps page: "Pieces on screen go
--   behind the open map").
-- COST: nothing while the map is closed (two script hooks, and one early
-- return in each hooked piece's show). Open: one walk of the pieces four
-- times a second, their children every other time.
do
    local Under = {}
    ns.UnderMap = Under
    local RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
        FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
    local BY_RANK = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
    -- windows that are not top level and sit on a piece's layer
    local WINDOW_NAMES = { ZacUIJunkItems = true, ZacUIMeterBreakdown = true, ZacUITooltipMover = true }
    -- pieces that stand on a window's layer (the target arrows over the nameplates are on the
    -- dialog layer, to be over Readycheck's nameplate icons)
    local PIECE_NAMES = { ZacUI_SoftTargetMarker = true, ZacUI_CurrentTargetMarker = true }
    local KID_DEPTH = 3
    local weak = { __mode = "k" }
    local lowered = setmetatable({}, weak)   -- piece -> { had, put, moved, kids = { [frame] = its own layer } }
    local hooks = setmetatable({}, weak)     -- piece -> true: its show / layer change is looked at at once
    local owned = setmetatable({}, weak)     -- frame -> true | false: made by ZacUI (the net)
    local pieces = setmetatable({}, weak)    -- frame -> true: a piece whatever its layer (a part said so)
    local always = setmetatable({}, weak)    -- frame -> true: no box of its own, under whenever the map is open
    local providers = {}
    local seen = {}
    local netList, netCount = {}, -1
    local ticker, hooked
    local waiting = false          -- a secure frame could not be touched in a fight
    local working = false          -- our own layer change: the hooks stay quiet
    local active = false           -- the map is open as a window and the switch is on
    local deep = true              -- this look also walks the pieces' children
    local tick = 0
    local map, ml, mb, mr, mt, mapRank, below, screenW, screenH

    function Under.On()
        local c = type(ZacUIDB) == "table" and ZacUIDB.config
        return not (type(c) == "table" and c.underMap == false)
    end
    -- fn(each): calls each(frame [, "piece" | "always"]) for every frame of a part that stands on the screen
    function Under.Add(fn)
        if type(fn) == "function" then providers[#providers + 1] = fn end
    end
    function Under.Lowered(f)
        local rec = lowered[f]
        return rec ~= nil and rec.moved == true
    end

    local function Map() return _G.WorldMapFrame end
    local function Rank(st) return RANK[st or ""] or 3 end
    -- l, b, r, t in real screen pixels (nil when the frame has no box yet)
    local function Rect(f)
        if not (f.GetRect and f.GetEffectiveScale) then return nil end
        local ok, l, b, w, h = pcall(f.GetRect, f)
        if not ok or type(l) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then return nil end
        local sc = f:GetEffectiveScale() or 1
        return l * sc, b * sc, (l + w) * sc, (b + h) * sc
    end
    -- the piece's box; a holder with no size of its own is as big as what it holds
    local function Box(f)
        local l, b, r, t = Rect(f)
        if l and (r - l) > 2 and (t - b) > 2 then return l, b, r, t end
        local L, B, R, T
        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do
                local c = kids[i]
                if type(c) == "table" and c.IsShown and c:IsShown() then
                    local cl, cb, cr, ct = Rect(c)
                    if cl and (cr - cl) > 0 and (ct - cb) > 0 then
                        if not L or cl < L then L = cl end
                        if not B or cb < B then B = cb end
                        if not R or cr > R then R = cr end
                        if not T or ct > T then T = ct end
                    end
                end
            end
        end
        return L, B, R, T
    end
    -- a window, not a piece: it keeps its layer
    local function IsWindow(f)
        if pieces[f] or always[f] then return false end
        local name = f.GetName and f:GetName()
        if name then
            if PIECE_NAMES[name] then return false end
            if WINDOW_NAMES[name] then return true end
        end
        if f.IsToplevel and f:IsToplevel() then return true end
        return Rank(f:GetFrameStrata()) >= RANK.DIALOG
    end
    local function Protected(f)
        return (f.IsProtected and f:IsProtected()) and true or false
    end
    local function Set(f, strata)
        working = true
        pcall(f.SetFrameStrata, f, strata)
        working = false
    end
    local function EachKid(f, depth, fn)
        if depth <= 0 or not f.GetChildren then return end
        local kids = { f:GetChildren() }
        for i = 1, #kids do
            local c = kids[i]
            if type(c) == "table" and c.GetFrameStrata and not (c.IsForbidden and c:IsForbidden()) then
                fn(c)
                EachKid(c, depth - 1, fn)
            end
        end
    end

    local function Restore(f)
        local rec = lowered[f]
        if not rec then return end
        local combat = InCombatLockdown and InCombatLockdown()
        local left = false
        if rec.put then
            if combat and Protected(f) then
                left = true
            else
                -- (only while it is still where it was put: a piece that took a layer of its own since keeps that)
                if f.GetFrameStrata and f:GetFrameStrata() == rec.put then Set(f, rec.had) end
                rec.put, rec.had = nil, nil
            end
        end
        -- (after the parent: where a parent's change carries its children, this is what puts
        -- them right. A parent that has to wait for the fight to end: its children go back now
        -- and stay on record, to be put right once more after it)
        local parentWaits = left
        for k, ks in pairs(rec.kids) do
            if combat and Protected(k) then
                left = true
            else
                if k.GetFrameStrata and k:GetFrameStrata() ~= ks then Set(k, ks) end
                if not parentWaits then rec.kids[k] = nil end
            end
        end
        if left then waiting = true else lowered[f] = nil end
    end
    local function RestoreAll()
        for f in pairs(lowered) do pcall(Restore, f) end
    end

    local function Lower(f, walk)
        local rec = lowered[f]
        local combat = InCombatLockdown and InCombatLockdown()
        if not rec then
            rec = { kids = {} }
            lowered[f] = rec
            -- noted BEFORE the piece moves: every child on a layer of its own
            EachKid(f, KID_DEPTH, function(k)
                local p = k:GetParent()
                local ks = k:GetFrameStrata()
                if p and p.GetFrameStrata and ks ~= p:GetFrameStrata() then rec.kids[k] = ks end
            end)
            walk = true
        end
        local st = f:GetFrameStrata()
        if Rank(st) >= mapRank then
            if combat and Protected(f) then
                waiting = true
            else
                rec.had, rec.put, rec.moved = st, below, true
                Set(f, below)
            end
        end
        if walk then
            EachKid(f, KID_DEPTH, function(k)
                local ks = k:GetFrameStrata()
                if Rank(ks) >= mapRank then
                    if combat and Protected(k) then
                        waiting = true
                    else
                        rec.kids[k] = ks
                        rec.moved = true
                        Set(k, below)
                    end
                end
            end)
        end
    end

    local Look
    -- a piece that shows, or sets its own layer, while the map is open
    local function Nudge(f)
        if working or not active or type(f) ~= "table" then return end
        seen[f] = nil
        local was = deep
        deep = true
        pcall(Look, f)
        deep = was
    end
    local function Hook(f)
        if hooks[f] then return end
        hooks[f] = true
        if f.HookScript then pcall(f.HookScript, f, "OnShow", Nudge) end
        -- (never a method hook on a secure frame: the game's own code calling that method
        -- would run through our hook; its show script is enough there)
        if not Protected(f) and type(f.SetFrameStrata) == "function" and hooksecurefunc then
            pcall(hooksecurefunc, f, "SetFrameStrata", Nudge)
        end
    end
    -- with: nil = by its own box, true / false = as the frame it hangs beside
    Look = function(f, with)
        if type(f) ~= "table" or not f.GetFrameStrata or f == map or seen[f] then return end
        if f.IsForbidden and f:IsForbidden() then return end
        seen[f] = true
        Hook(f)
        local under = false
        if f.IsShown and f:IsShown() and not IsWindow(f) then
            if with ~= nil then
                under = with
            elseif always[f] then
                under = true
            else
                local l, b, r, t = Box(f)
                if l and r > ml + 1 and l < mr - 1 and t > mb + 1 and b < mt - 1
                   -- (a frame that fills the screen holds pieces; it is not one)
                   and not ((r - l) >= screenW * 0.9 and (t - b) >= screenH * 0.9) then
                    under = true
                end
            end
        end
        if under then Lower(f, deep) else Restore(f) end
        local sats = rawget(f, "_zSatellites")
        if type(sats) == "table" then
            for i = 1, #sats do Look(sats[i], under) end
        end
    end
    local function LookSafe(f, how)
        if type(f) == "table" then
            if how == "piece" then pieces[f] = true elseif how == "always" then always[f] = true end
        end
        pcall(Look, f)
    end

    -- THE NET. true when ZacUI's code made this frame: the client names the
    -- addon that created a global, or that wrote a field. A frame with a
    -- global name is judged by that name alone, so a window of the game's
    -- that ZacUI skinned (and so wrote fields on) stays the game's.
    -- (never the two map parts' own frames: what belongs to the map stays on the map)
    local function Ours(who)
        return type(who) == "string" and who:find("^Zacui") ~= nil
            and who ~= "Zacui_WorldMap" and who ~= "Zacui_Maps"
    end
    local function Owned(f)
        local v = owned[f]
        if v ~= nil then return v end
        v = false
        if issecurevariable then
            pcall(function()
                local name = f.GetName and f:GetName()
                if name and _G[name] == f then
                    local secure, who = issecurevariable(_G, name)
                    if not secure and Ours(who) then v = true end
                    return
                end
                -- no name: its fields. Ours when every field on it was written by our code and none by
                -- the game or another addon (a frame of theirs that we only dressed carries both)
                local n, mine = 0, 0
                for k in pairs(f) do
                    if type(k) == "string" then
                        n = n + 1
                        local secure, who = issecurevariable(f, k)
                        if secure or not Ours(who) then return end
                        mine = mine + 1
                        if n >= 12 then break end
                    end
                end
                if mine > 0 then v = true end
            end)
        end
        owned[f] = v
        return v
    end
    local function Net()
        local holder = Screen.Holder and Screen.Holder()
        local n = (UIParent.GetNumChildren and UIParent:GetNumChildren() or 0)
            + (holder and holder.GetNumChildren and holder:GetNumChildren() or 0) * 10000
        if n ~= netCount then      -- (something was made, or changed parent, since)
            netCount = n
            wipe(netList)
            local kids = { UIParent:GetChildren() }
            for i = 1, #kids do
                local f = kids[i]
                -- (one frame that cannot be asked never stops the scan)
                local ok, mine = pcall(function()
                    return type(f) == "table" and f ~= holder and not (f.IsForbidden and f:IsForbidden()) and Owned(f)
                end)
                if ok and mine then netList[#netList + 1] = f end
            end
            if holder and holder.GetChildren then
                kids = { holder:GetChildren() }
                for i = 1, #kids do
                    if type(kids[i]) == "table" then netList[#netList + 1] = kids[i] end
                end
            end
        end
        return netList
    end

    local Sweep
    -- (a look that fails says so once in the debug log and is tried again at the next)
    function Under.Sweep()
        local ok, err = pcall(Sweep)
        if not ok then
            active = false
            -- (told once, so it is seen and not repeated four times a second)
        if not Under._erred then Under._erred = true if geterrorhandler then geterrorhandler()("ZacUI, under the map: " .. tostring(err)) end end
        end
    end
    Sweep = function()
        map = Map()
        active = Under.On() and map ~= nil and map:IsShown()
        if active then
            mapRank = Rank(map:GetFrameStrata())
            -- (full screen it is over every piece by itself; on the lowest layers there is no "under")
            if mapRank >= RANK.FULLSCREEN or mapRank <= 1 then
                active = false
            else
                ml, mb, mr, mt = Rect(map)
                active = ml ~= nil and (mr - ml) > 0 and (mt - mb) > 0
            end
        end
        if not active then RestoreAll() return end
        below = BY_RANK[mapRank - 1]
        local us = UIParent:GetEffectiveScale() or 1
        screenW, screenH = (UIParent:GetWidth() or 0) * us, (UIParent:GetHeight() or 0) * us
        waiting = false
        tick = tick + 1
        deep = (tick % 2 == 1)
        wipe(seen)
        for _, m in ipairs(MOVERS) do
            if m.getFrame then
                local ok, f = pcall(m.getFrame)
                if ok and type(f) == "table" then LookSafe(f) end
            end
        end
        for i = 1, #providers do pcall(providers[i], LookSafe) end
        for name in pairs(PIECE_NAMES) do LookSafe(_G[name]) end
        local okNet, list = pcall(Net)
        if okNet and list then
            for i = 1, #list do LookSafe(list[i]) end
        end
        -- a piece that is gone from every list (its part let go of it)
        for f in pairs(lowered) do
            if not seen[f] then pcall(Restore, f) end
        end
    end

    local function Stop()
        if ticker then ticker:Cancel() ticker = nil end
        active = false
        RestoreAll()
    end
    local function Start()
        if not Under.On() then return end
        -- (a frame looked at before its fields were written is asked again)
        for f, v in pairs(owned) do if v == false then owned[f] = nil end end
        netCount = -1
        tick = 0
        Under.Sweep()
        if not ticker and C_Timer and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(0.25, function()
                local m = Map()
                if not (m and m:IsShown()) then Stop() return end
                Under.Sweep()
            end)
            if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "movers.undermap") end
        end
    end
    -- the switch (the Maps page): at once
    function Under.Set(on)
        if type(ZacUIDB) ~= "table" then return end
        ZacUIDB.config = ZacUIDB.config or {}
        if on then ZacUIDB.config.underMap = nil else ZacUIDB.config.underMap = false end
        local m = Map()
        if on and m and m:IsShown() then Start() else Stop() end
    end

    local function HookMap()
        local m = Map()
        if hooked or not (m and m.HookScript) then return end
        hooked = true
        m:HookScript("OnShow", Start)
        m:HookScript("OnHide", Stop)
        if m:IsShown() then Start() end
    end
    Under.Hook = HookMap
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("ADDON_LOADED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(self, event, name)
        if event == "PLAYER_REGEN_ENABLED" then
            -- what a fight kept on the wrong layer, either way
            if waiting or next(lowered) then
                waiting = false
                local m = Map()
                if m and m:IsShown() and Under.On() then Under.Sweep() else RestoreAll() end
            end
            return
        end
        if event == "ADDON_LOADED" and name ~= "Blizzard_WorldMap" then return end
        HookMap()
        if hooked then self:UnregisterEvent("ADDON_LOADED") end
    end)
end
