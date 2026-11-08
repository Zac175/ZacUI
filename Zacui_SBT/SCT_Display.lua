-- SCT_Display - puts lines of text into the scroll areas and moves them.
-- Part of ZacUI (Zacui_SBT). Written for ZacUI.
--
-- One frame per area, sitting where the area's box is. A line is a small
-- pooled frame (number + icon) parented to its area; every line on screen
-- is moved by one OnUpdate that only runs while something is showing.
--
-- All of that is an ENGINE: its own areas, its own lines, its own driver.
-- The scrolling text you play with is one engine on UIParent; the
-- settings preview runs another on its canvas, through exactly the same
-- code, so what the preview shows is what a fight shows. The preview's
-- driver is a child of the canvas, so it stops when the dock hides.
--
-- S.Display(areaKey, text, o)
--   o.r, o.g, o.b  colour (default white)
--   o.crit         crit size and alpha; pops in place when sticky crits are on
--   o.sticky       pops in place whatever the setting
--   o.size         a size of its own (otherwise the area's, then the part's)
--   o.icon         a texture path or file id
--   o.sound        a sound name, played once
--   o.soundKey     the event / alert it comes from (its sound spec)
local ns = _G.ZacUI
if not ns then return end
local S = ns.SBT
if not S then return end

local GetTime = GetTime
local math_max, math_min, math_floor, math_abs = math.max, math.min, math.floor, math.abs

local MAX_LINES = 30          -- per area; past that the oldest goes
local GAP_V = 4               -- between stacked lines
local GAP_H = 10              -- between lines on one horizontal row
local DYING = 0.15            -- a line pushed out of its area fades this fast
local MAX_LIFE = 30           -- seconds; a longer (or NaN) life is a mistake
local HARD_EXTRA = 2          -- every line is gone this long after its life, whatever happens

-- seconds at speed 100
local LIFE = { up = 3.0, down = 3.0, arc = 3.0, horizontal = 1.5, static = 3.0 }

local DIR_VEC = { up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }
local IN_STYLES = { none = true, pop = true, fade = true, slide = true }

local Engine = {}
Engine.__index = Engine

-- ============================================================
-- AREA FRAMES
-- ============================================================
function Engine:AreaFrame(key)
    local st = self.areas[key]
    if not st then
        local f = CreateFrame("Frame", nil, self.root)
        if not self.preview then f:SetFrameStrata("HIGH") end
        f:SetFrameLevel(5)
        f:EnableMouse(false)
        st = { frame = f, lines = {}, sticky = {}, row = nil, alt = false }
        self.areas[key] = st
    end
    return st
end

function Engine:PlaceArea(key, a)
    local st = self:AreaFrame(key)
    local f = st.frame
    f:ClearAllPoints()
    if self.place then
        self.place(f, key, a)
    else
        f:SetPoint("BOTTOMLEFT", self.root, "CENTER", tonumber(a.x) or 0, tonumber(a.y) or 0)
    end
    f:SetSize(math_max(1, tonumber(a.w) or 40), math_max(1, tonumber(a.h) or 40))
    f:Show()
    return st
end

-- ============================================================
-- LINES
-- ============================================================
-- l.listed: on one of an area's lists (what the driver walks); l.pooled:
-- in the pool. self.live counts the listed ones; self.made holds every
-- line this engine ever made (one entry per frame, not per hit), so a
-- line that went astray can always be found and put away.
function Engine:NewLine(parent)
    local l = table.remove(self.pool)
    if l then
        l.pooled = nil
        return l
    end
    l = CreateFrame("Frame", nil, parent or self.root)
    -- a new frame is shown: hidden until it is on a list and placed
    l:Hide()
    l:SetSize(1, 1)
    l.fs = l:CreateFontString(nil, "OVERLAY")
    -- a font from the start: SetText on a font-less string errors
    l.fs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    l.fs:SetJustifyH("LEFT")
    l.ic = l:CreateTexture(nil, "OVERLAY")
    ZacUI.Look.CropIcon(l.ic)
    -- a sample line answers "customize this element" (the settings page)
    if self.preview and ns.TagElement then ns.TagElement(l, "sct.line") end
    self.made[#self.made + 1] = l
    return l
end

function Engine:Free(l)
    l:Hide()
    if l.pooled then return end         -- never into the pool twice
    l:ClearAllPoints()
    l:SetScale(1)
    l.st = nil
    if l.listed then
        l.listed = nil
        self.live = self.live - 1
    end
    l.pooled = true
    self.pool[#self.pool + 1] = l
end

-- Any line that is neither on a list nor in the pool (it errored half
-- way through being made), or is in the pool but still showing, is put
-- away. Runs when the engine goes idle and on ClearAll - never per hit.
function Engine:Sweep()
    local made = self.made
    for i = 1, #made do
        local l = made[i]
        if not l.listed then
            if l.pooled then
                if l:IsShown() then l:Hide() end
            else
                self:Free(l)
            end
        end
    end
end

-- An error inside the engine is reported once (the same one again is
-- only counted), never thrown at the caller: the caller is a combat event.
function Engine:Report(err)
    self.errors = self.errors + 1
    if err == self.lastError then return end
    self.lastError = err
    local h = geterrorhandler and geterrorhandler()
    if h then pcall(h, err) end
end

local function Remove(list, l)
    for i = #list, 1, -1 do
        if list[i] == l then
            table.remove(list, i)
            return
        end
    end
end

function Engine:Drop(st, l)
    Remove(st.lines, l)
    Remove(st.sticky, l)
    self:Free(l)
end

function Engine:ClearAll()
    for _, st in pairs(self.areas) do
        for i = #st.lines, 1, -1 do self:Free(st.lines[i]); st.lines[i] = nil end
        for i = #st.sticky, 1, -1 do self:Free(st.sticky[i]); st.sticky[i] = nil end
        st.row = nil
    end
    self:Sweep()
    self.live = 0
end

-- AN AREA'S LINES ON ZACUI'S LAYOUT SHAPE (areas.<key>.layout):
--   grow      "UP" / "DOWN": where a sliding or stacked area adds rows (over
--             its "New lines go")
--   spacingY  between stacked lines (4);  spacingX  between two lines on
--             one sliding row (10);  max  lines at once (30)
-- Read onto the area's state when a line starts; nothing saved = the
-- numbers above, exactly as always.
local function AreaLayout(st, a)
    local lay = a.layout
    if type(lay) ~= "table" or next(lay) == nil then
        st.gapV, st.gapH, st.maxLines, st.grow = GAP_V, GAP_H, MAX_LINES, nil
        return
    end
    st.gapV = tonumber(lay.spacingY) or GAP_V
    st.gapH = tonumber(lay.spacingX) or GAP_H
    local m = tonumber(lay.max)
    st.maxLines = (m and m >= 1) and math_floor(m) or MAX_LINES
    st.grow = (lay.grow == "UP" and "up") or (lay.grow == "DOWN" and "down") or nil
end
-- what the area's layout picker shows with nothing saved
function S.AreaLayoutDefaults(a)
    a = type(a) == "table" and a or {}
    local down = a.grow == "down" or (a.grow == nil and a.style == "static" and a.dir == "down")
    return { grow = down and "DOWN" or "UP", spacingY = GAP_V, spacingX = GAP_H, max = MAX_LINES }
end

-- Where a line of this width starts, across the area.
local function StartX(a, aw, lw)
    if a.align == "LEFT" then return 0 end
    if a.align == "RIGHT" then return aw - lw end
    return (aw - lw) / 2
end

-- Font, colour and icon onto one line. The area's own font, size,
-- outline and shadow win; nil there means the General settings.
local function Dress(l, a, c, text, o)
    local crit = o.crit and true or false
    local size = tonumber(o.size)
        or (crit and (tonumber(a.critSize) or tonumber(c.critSize)) or (tonumber(a.size) or tonumber(c.size)))
        or 12
    size = math_max(6, math_min(64, size))
    local fs = l.fs
    -- (a string whose font was lost to a font file that would not load
    -- has none to clear with; SetFont below gives it one again)
    if fs:GetFont() then fs:SetText("") end
    local outline = a.outline
    if outline == nil then outline = c.outline end
    local flags = S.Flags and S.Flags(outline) or (outline or "OUTLINE")
    -- SetFont returns false (no error) when the file can't be loaded
    local ok, set = pcall(fs.SetFont, fs, S.FontPath(a.font or c.font), size, flags)
    if not (ok and set) then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size, "OUTLINE") end
    local shadow = a.shadow
    if shadow == nil then shadow = c.shadow end
    if shadow ~= false then
        fs:SetShadowOffset(tonumber(c.shadowX) or 1, tonumber(c.shadowY) or -1)
        fs:SetShadowColor(0, 0, 0, 0.8)
    else
        fs:SetShadowOffset(0, 0)
    end
    fs:SetTextColor(o.r or 1, o.g or 1, o.b or 1, 1)
    fs:SetText(text)
    fs:ClearAllPoints()
    local tw = fs:GetStringWidth() or 0
    local icon = c.icons ~= false and o.icon or nil
    if icon then
        l.ic:SetTexture(icon)
        l.ic:SetSize(size, size)
        l.ic:ClearAllPoints()
        l.ic:Show()
        local spec = type(a.anchors) == "table" and a.anchors.icon or nil
        if spec then
            -- the area's saved icon spot (a.anchors.icon, ZacUI's anchor
            -- shape): the number holds the line's corner, the icon goes
            -- wherever the spot puts it round the number; its side
            -- setting is the default
            fs:SetPoint("BOTTOMLEFT", l, "BOTTOMLEFT", 0, 0)
            local d = l.icDef
            if not d then d = {} l.icDef = d end
            if a.iconSide == "LEFT" then
                d.point, d.relPoint, d.x = "BOTTOMRIGHT", "BOTTOMLEFT", -3
            else
                d.point, d.relPoint, d.x = "BOTTOMLEFT", "BOTTOMRIGHT", 3
            end
            d.y, d.to = 0, fs
            ns.ApplyAnchor(l.ic, spec, d)
        elseif a.iconSide == "LEFT" then
            l.ic:SetPoint("BOTTOMLEFT", l, "BOTTOMLEFT", 0, 0)
            fs:SetPoint("BOTTOMLEFT", l.ic, "BOTTOMRIGHT", 3, 0)
        else
            fs:SetPoint("BOTTOMLEFT", l, "BOTTOMLEFT", 0, 0)
            l.ic:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", 3, 0)
        end
        tw = tw + size + 3
    else
        l.ic:Hide()
        fs:SetPoint("BOTTOMLEFT", l, "BOTTOMLEFT", 0, 0)
    end
    l.w, l.h = math_max(1, tw), size
    l:SetSize(l.w, l.h)
    l.peak = ((crit and tonumber(a.critAlpha) or tonumber(a.alpha)) or 100) / 100
    l.crit = crit
end
S.DressLine = Dress

-- ============================================================
-- STYLES - each sets up a new line and, every frame, says where it is
-- ============================================================
-- l.x0, l.y0: start, relative to the area's bottom-left
-- l.p: 0..1 through its life (eased)

-- Vertical: a newer line keeps the older ones at least a line apart by
-- pushing them on ahead of it.
local function SpaceVertical(st, l, down)
    local newer = l
    for i = #st.lines, 1, -1 do
        local old = st.lines[i]
        if old ~= l and (old.style == "up" or old.style == "down" or old.style == "arc") then
            if down then
                local need = (newer.cy or newer.y0) - old.h - (st.gapV or GAP_V)
                if (old.cy or old.y0) > need then old.push = (old.push or 0) + ((old.cy or old.y0) - need) end
            else
                local need = (newer.cy or newer.y0) + newer.h + (st.gapV or GAP_V)
                if (old.cy or old.y0) < need then old.push = (old.push or 0) + (need - (old.cy or old.y0)) end
            end
            newer = old
        end
    end
end

local function InitUp(st, l, a, aw, ah)
    l.x0, l.y0 = StartX(a, aw, l.w), 0
    l.cy = 0
    SpaceVertical(st, l, false)
end
local function StepUp(l, ah)
    local y = l.y0 + l.p * math_max(ah - l.h, 1) + (l.push or 0)
    l.cy = y
    return l.x0, y
end

local function InitDown(st, l, a, aw, ah)
    l.x0, l.y0 = StartX(a, aw, l.w), math_max(ah - l.h, 0)
    l.cy = l.y0
    SpaceVertical(st, l, true)
end
local function StepDown(l, ah)
    local y = l.y0 - l.p * math_max(ah - l.h, 1) - (l.push or 0)
    l.cy = y
    return l.x0, y
end

local function InitArc(st, l, a, aw, ah)
    InitUp(st, l, a, aw, ah)
    local side
    if a.dir == "left" then side = -1
    elseif a.dir == "right" then side = 1
    else
        st.alt = not st.alt
        side = st.alt and 1 or -1
    end
    l.side = side
    l.reach = math_max(30, aw)
end
local function StepArc(l, ah)
    local x, y = StepUp(l, ah)
    -- out quickly, then mostly up: the classic fountain
    local p = l.p
    local out = 1 - (1 - p) * (1 - p)
    return x + l.side * l.reach * out, y
end

-- Horizontal: each line gets the next row; it slides the width of the
-- area. A line still near the start of the same row is moved on so the
-- two never print over each other.
local function InitHorizontal(st, l, a, aw, ah)
    local up = (st.grow or a.grow) ~= "down"
    local gapV = st.gapV or GAP_V
    local row = st.row
    if up then
        row = (row == nil) and 0 or (row + l.h + gapV)
        if row + l.h > ah then row = 0 end
    else
        local top = math_max(ah - l.h, 0)
        row = (row == nil) and top or (row - l.h - gapV)
        if row < 0 then row = top end
    end
    st.row = row
    local dir = a.dir
    if dir ~= "left" and dir ~= "right" then
        st.alt = not st.alt
        dir = st.alt and "right" or "left"
    end
    l.sign = (dir == "left") and -1 or 1
    l.x0, l.y0 = StartX(a, aw, l.w), row
    l.travel = math_max(aw, 20)
    for i = #st.lines, 1, -1 do
        local old = st.lines[i]
        if old ~= l and old.style == "horizontal" and old.sign == l.sign
            and math_abs(old.y0 - l.y0) < math_max(old.h, l.h) then
            -- how far the old line must already be along
            local need = (l.w + (st.gapH or GAP_H)) / old.travel
            if old.p < need then
                if need > 0.92 then
                    old.dying = true
                else
                    old.born = old.born - (need - old.p) * old.life
                end
            end
        end
    end
end
local function StepHorizontal(l)
    return l.x0 + l.sign * l.p * l.travel, l.y0
end

-- Static: a stack that holds still. The newest line takes the first
-- row; the older ones slide one row on (smoothly) and the one pushed
-- past the end of the area fades out.
local function InitStatic(st, l, a, aw, ah)
    l.x0 = StartX(a, aw, l.w)
    if st.grow then l.down = st.grow == "down"
    else l.down = a.grow == "down" or (a.grow == nil and a.dir == "down") end
    local base = l.down and math_max(ah - l.h, 0) or 0
    l.y0, l.cy, l.slot = base, base, 0
    for i = #st.lines, 1, -1 do
        local old = st.lines[i]
        if old ~= l and old.style == "static" then
            old.slot = (old.slot or 0) + l.h + (st.gapV or GAP_V)
            if old.slot + old.h > ah + 1 then old.dying = true end
        end
    end
end
local function StepStatic(l, ah, elapsed)
    local want = l.down and (l.y0 - l.slot) or (l.y0 + l.slot)
    l.cy = l.cy + (want - l.cy) * math_min(1, elapsed * l.stack)
    return l.x0, l.cy
end

local STYLES = {
    up = { InitUp, StepUp },
    down = { InitDown, StepDown },
    arc = { InitArc, StepArc },
    horizontal = { InitHorizontal, StepHorizontal },
    static = { InitStatic, StepStatic },
}
S.STYLES = {
    { value = "horizontal", text = "Slide sideways" },
    { value = "up",         text = "Scroll up" },
    { value = "down",       text = "Scroll down" },
    { value = "arc",        text = "Fountain" },
    { value = "static",     text = "Stack in place" },
}

-- Sticky: pops in the middle of the area, holds, fades. Several at once
-- stack upward from the middle.
local function InitSticky(st, l, a, aw, ah)
    l.x0 = StartX(a, aw, l.w)
    local mid = math_max(0, (ah - l.h) / 2)
    l.y0 = mid
    l.cy = mid
    l.slot = 0
    for i = #st.sticky, 1, -1 do
        local old = st.sticky[i]
        if old ~= l then old.slot = (old.slot or 0) + l.h + (st.gapV or GAP_V) end
    end
end

-- ============================================================
-- TIMING - the Animation tab's settings, read when a line starts
-- ============================================================
local function Speed(c, a)
    local k = tonumber(a and a.speed) or tonumber(c.speed) or 100
    if k <= 0 then k = tonumber(c.speed) or 100 end
    return math_max(0.2, k / 100)
end

-- Everything one line needs to know about how it moves, onto the line
-- itself (no table per line: this runs for every hit in a fight).
local function Time(l, c, sticky)
    local on, ms = S.MotionOn(), S.MotionSpeed()
    l.fadeIn = on and math_max(0, tonumber(c.fadeIn) or 0.06) / ms or 0
    l.dyingFor = on and DYING / ms or 0
    l.stack = on and (tonumber(c.stackSpeed) or 14) * ms or 1000
    if sticky then
        local spec = type(c.stickyIn) == "table" and c.stickyIn or {}
        local style = IN_STYLES[spec.style] and spec.style or "pop"
        local dur = math_max(0, tonumber(spec.duration) or 0.14)
        if not on or style == "none" or dur <= 0 then
            l.inStyle, l.inDur, l.inDelay = "none", 0, 0
        else
            l.inStyle = style
            l.inDur = dur / ms
            l.inDelay = math_max(0, tonumber(spec.delay) or 0) / ms
            l.inEase = S.Ease(spec.easing or "linear")
            local v = DIR_VEC[spec.dir or "up"] or DIR_VEC.up
            local dist = tonumber(spec.distance) or 20
            l.inDX, l.inDY = v[1] * dist, v[2] * dist
            l.inScale = math_max(0.1, (tonumber(c.stickyScale) or 160) / 100)
        end
        l.fadeFor = on and math_max(0, tonumber(c.stickyFade) or 0.4) / ms or 0
    else
        l.inStyle = "none"
        local pct = tonumber(l.style == "static" and c.fadeOutStatic or c.fadeOut)
        if pct == nil then pct = (l.style == "static") and 25 or 20 end
        l.fadePct = on and math_max(0, math_min(100, pct)) / 100 or 0
        l.ease = (c.ease and c.ease ~= "linear") and S.Ease(c.ease) or nil
    end
end

-- ============================================================
-- THE DRIVER
-- ============================================================
function Engine:UpdateList(st, list, now, elapsed, ah, sticky)
    local f = st.frame
    for i = #list, 1, -1 do
        local l = list[i]
        local age = now - l.born
        if l.dying and not l.dyingAt then
            l.dyingAt = now
        end
        -- written as "not (x < y)" so a NaN anywhere means gone; dieBy is
        -- the hard end every line has, whatever its timing says
        local gone = not (age < l.life) or not (now < (l.dieBy or 0))
            or (l.dyingAt and now - l.dyingAt > l.dyingFor)
        if gone then
            table.remove(list, i)
            self:Free(l)
        else
            local raw = math_min(1, age / l.life)
            l.p = l.ease and l.ease(raw) or raw
            local x, y
            local entering = 1
            if sticky then
                local want = l.y0 + l.slot
                l.cy = l.cy + (want - l.cy) * math_min(1, elapsed * l.stack)
                x, y = l.x0, l.cy
                local s = 1
                if l.inDur > 0 then
                    local t = (age - l.inDelay) / l.inDur
                    local style = l.inStyle
                    if t < 1 then
                        local e = (t <= 0) and 0 or l.inEase(t)
                        if t < 0 then entering = 0 end
                        if style == "pop" then
                            s = l.inScale + (1 - l.inScale) * e
                        elseif style == "fade" then
                            entering = entering * math_max(0, math_min(1, e))
                        elseif style == "slide" then
                            x = x + l.inDX * (1 - e)
                            y = y + l.inDY * (1 - e)
                            entering = entering * math_min(1, math_max(0, e * 1.4))
                        end
                    end
                end
                if s <= 0.01 then s = 0.01 end
                l:SetScale(s)
                -- a scaled frame reads its offsets in its own scale
                x, y = x / s, y / s
            else
                x, y = l.step(l, ah, elapsed)
            end
            l:ClearAllPoints()
            l:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, y)
            local a = l.peak * entering
            if l.fadeIn > 0 and age < l.fadeIn then
                a = a * (age / l.fadeIn)
            end
            if l.dyingAt then
                a = (l.dyingFor > 0) and a * math_max(0, 1 - (now - l.dyingAt) / l.dyingFor) or 0
            else
                local fadeFrom
                if sticky then fadeFrom = l.life - l.fadeFor
                else fadeFrom = l.life * (1 - l.fadePct) end
                if l.life > fadeFrom and age > fadeFrom then
                    a = a * math_max(0, (l.life - age) / (l.life - fadeFrom))
                end
            end
            l:SetAlpha(a)
        end
    end
end

function Engine:Walk(elapsed)
    local now = GetTime()
    for _, st in pairs(self.areas) do
        if #st.lines > 0 or #st.sticky > 0 then
            local ah = st.frame:GetHeight() or 40
            self:UpdateList(st, st.lines, now, elapsed, ah, false)
            self:UpdateList(st, st.sticky, now, elapsed, ah, true)
        end
    end
end

function Engine:Step(elapsed)
    -- one bad line must not stop every line after it, every frame: on an
    -- error what is showing goes, and the error is reported once
    local ok, err = pcall(self.Walk, self, elapsed)
    if not ok then
        self:ClearAll()
        self:Report(err)
    end
    -- what is showing is what is on the lists, not a count kept aside
    local n = 0
    for _, st in pairs(self.areas) do n = n + #st.lines + #st.sticky end
    self.live = n
    if n == 0 then
        self:Sweep()
        self.driver:Hide()
    end
end

-- ============================================================
-- A LINE'S STATE (sct.states.<crit|sticky>, ZacUI's state shape)
-- ============================================================
--   textColor  over the event's colour;  alpha  over the area's opacity
--   (0-1). A pop that is also a crit takes the crit's, then the pop's on
--   top. Painted once as the line is made; nothing saved = no work at all.
local function PaintState(l, states, name)
    local sc = states[name]
    if type(sc) ~= "table" then return end
    local tc = sc.textColor
    if type(tc) == "table" then
        local r, g, b
        if ns.ColorOf then r, g, b = ns.ColorOf(tc) else r, g, b = tc.r or tc[1], tc.g or tc[2], tc.b or tc[3] end
        if r then l.fs:SetTextColor(r, g, b, 1) end
    end
    local al = tonumber(sc.alpha)
    if al then l.peak = math_max(0, math_min(1, al)) end
end
local function LineStates(l, states, crit, sticky)
    if crit then PaintState(l, states, "crit") end
    if sticky then PaintState(l, states, "sticky") end
end
S.LINE_STATES = { { id = "crit", label = "A critical hit or heal" }, { id = "sticky", label = "A line that pops in place" } }

-- ============================================================
-- SHOW ONE LINE
-- ============================================================
-- Everything that can go wrong in making a line, run under one pcall
-- (no closure: the arguments go straight through).
local function Make(self, l, st, a, c, text, o, aw, ah)
    local f = st.frame
    l:SetParent(f)
    l:SetFrameLevel(f:GetFrameLevel() + 1)
    l.st = st
    l.push, l.dying, l.dyingAt, l.slot, l.cy = nil, nil, nil, nil, nil
    AreaLayout(st, a)
    Dress(l, a, c, text, o)
    local sticky = o.sticky or (o.crit and c.stickyCrits)
    if type(c.states) == "table" then LineStates(l, c.states, o.crit, sticky) end
    l.born = GetTime()
    l.p = 0
    local spd = Speed(c, a)
    local list
    if sticky then
        l.style = "sticky"
        l.ease = nil
        Time(l, c, true)
        l.life = (tonumber(c.stickyHold) or 1.6) / spd + l.fadeFor
        list = st.sticky
    else
        local style = STYLES[a.style] and a.style or "up"
        l.style = style
        Time(l, c, false)
        l.life = (LIFE[style] or 3) / spd
        l.step = STYLES[style][2]
        list = st.lines
    end
    -- a life that is not a sensible number (NaN, infinite) is the default
    if not (l.life > 0 and l.life <= MAX_LIFE) then l.life = 3 end
    l.dieBy = l.born + l.life + HARD_EXTRA
    list[#list + 1] = l
    l.listed = true
    self.live = self.live + 1
    if sticky then
        InitSticky(st, l, a, aw, ah)
        while #st.sticky > 6 do self:Drop(st, st.sticky[1]) end
    else
        STYLES[l.style][1](st, l, a, aw, ah)
        while #st.lines > (st.maxLines or MAX_LINES) do self:Drop(st, st.lines[1]) end
    end
    l:SetAlpha(0)
    l:SetScale(1)
    l:ClearAllPoints()
    l:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", l.x0 or 0, l.y0 or 0)
end

local SOUND_DEF = { channel = "Master" }
function Engine:Display(key, text, o)
    if text == nil or text == "" then return end
    local c = S.Cfg()
    if c.enabled == false and not self.preview then return end
    o = o or {}
    local a = c.areas[key]
    if type(a) ~= "table" then
        key = "notification"
        a = c.areas[key]
        if type(a) ~= "table" then return end
    end
    if a.on == false then return end
    local st = self.areas[key]
    if not st then st = self:PlaceArea(key, a) end
    local f = st.frame
    local aw, ah = f:GetWidth() or 40, f:GetHeight() or 40

    local l = self:NewLine(f)
    local ok, err = pcall(Make, self, l, st, a, c, text, o, aw, ah)
    if not ok then
        -- never left half made: off the lists, hidden, back in the pool
        Remove(st.lines, l)
        Remove(st.sticky, l)
        self:Free(l)
        self:Report(err)
        return nil
    end
    l:Show()
    -- the driver before anything else can go wrong
    if not self.driver:IsShown() then self.driver:Show() end
    if c.sounds ~= false and not self.preview then
        -- a line's own sound spec (sct.soundSpecs.<event or alert key>,
        -- ZacUI's sound shape: sound / channel / throttle; its own sound
        -- name is the default); none saved = its sound name, as always
        local specs = o.soundKey and c.soundSpecs
        local spec = type(specs) == "table" and specs[o.soundKey] or nil
        if type(spec) == "table" and ns.PlaySoundSpec then
            SOUND_DEF.sound = o.sound
            ns.PlaySoundSpec(spec, SOUND_DEF, o.soundKey)
        elseif o.sound then
            S.PlaySound(o.sound)
        end
    end
    return l
end

-- Every box back on its numbers, and what was showing cleared (a line
-- half way through a box that moved would jump).
function Engine:Rebuild()
    self:ClearAll()
    local c = S.Cfg()
    for key, st in pairs(self.areas) do
        if type(c.areas[key]) ~= "table" then st.frame:Hide() end
    end
    for key, a in pairs(c.areas) do
        if type(a) == "table" then self:PlaceArea(key, a) end
    end
end

function Engine:Lines()
    return self.live
end

-- root: the frame areas sit on and are measured from (its centre).
-- opts.preview: a sample engine - its driver is the root's child (it
--   stops when the root hides), it plays no sounds and shows even while
--   the scrolling text is switched off.
-- opts.place(frame, key, area): where an area's box goes, instead of
--   its x/y from the middle of the root.
function S.NewEngine(root, opts)
    opts = opts or {}
    local e = setmetatable({ root = root or UIParent, areas = {}, live = 0, pool = {}, made = {}, errors = 0,
        preview = opts.preview and true or false, place = opts.place }, Engine)
    local d = CreateFrame("Frame", nil, opts.preview and e.root or nil)
    d:Hide()
    d:SetScript("OnUpdate", function(_, elapsed) e:Step(elapsed) end)
    e.driver = d
    return e
end

-- ============================================================
-- THE LIVE ENGINE
-- ============================================================
local live = S.NewEngine(UIParent)
S.engine = live

function S.Display(key, text, o)
    return live:Display(key, text, o)
end

function S.ClearAll()
    live:ClearAll()
end

-- After any change to the areas.
function S.Rebuild()
    live:Rebuild()
    if S.RefreshMovers then S.RefreshMovers() end
end
S.AreasChanged = S.Rebuild

-- A profile switch put a new settings table in place.
function S.OnNewSettings()
    if next(live.areas) then
        C_Timer.After(0, S.Rebuild)
    end
end

-- A few made-up lines, so a change can be seen without a fight.
S.TEST_LINES = {
    { "1234", { r = 1, g = 1, b = 1, icon = 135358 } },
    { "4821", { r = 1, g = 1, b = 0, crit = true, icon = 136012 } },
    { "Dodge", { r = 0.7, g = 0.7, b = 0.7 } },
    { "+512", { r = 0.2, g = 1, b = 0.2, icon = 135907 } },
    { "-388", { r = 1, g = 0.25, b = 0.25 } },
}
function S.TestArea(key)
    local a = S.Area(key)
    if not a then return end
    for i, s in ipairs(S.TEST_LINES) do
        C_Timer.After((i - 1) * 0.3, function() S.Display(key, s[1], s[2]) end)
    end
end

function S.TestAll()
    for _, e in ipairs(S.Areas()) do
        if e.area.on ~= false then S.TestArea(e.key) end
    end
end
