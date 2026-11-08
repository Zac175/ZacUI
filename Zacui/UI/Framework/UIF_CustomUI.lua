-- UIF_CustomUI - the pickers for the customization standard (UIF_Custom):
-- one compact control per family, each built from ZacUI's own widgets,
-- each raising ns.SettingsChanged() after its set() (so the preview dock
-- follows at once, sliders live while dragging), each get/set with set()
-- always handed a NEW table (or nil = back to the default).
-- Part of ZacUI; load order is set by the TOC (after UIF_Custom).
--
--   UI.AnchorPicker(parent, opts)        point grid, "of the target" grid,
--                                        anchor-to, X / Y, text align (a dropdown), Reset
--   UI.FramePositionPicker(parent, opts) the anchor picker + strata, level,
--                                        scale, keep on screen
--   UI.LayoutPicker(parent, opts)        grow, wrap, per line, spacing,
--                                        padding, item size, sort, reverse, max
--   UI.VisibilityPicker(parent, opts)    show when, opacity, combat opacity,
--                                        mouseover fade
--   UI.ChromePicker(parent, opts)        background, border, shadow, glow
--   UI.StateEditor(parent, opts)         a state dropdown + its overrides
--   UI.TextFormatPicker(parent, opts)    numbers, times, names, template
--   UI.SoundPicker(parent, opts)         a SharedMedia sound + play
--   UI.SoundSpecPicker(parent, opts)     sound, channel, throttle
--   UI.TextElement(L, opts)              one text: font + colour + format +
--                                        position as a tidy group (L:Add-ed)
--   UI.FrameElement(L, opts)             one part (icon, bar, badge):
--                                        position + size (+ look)
-- Common opts: label, width, get, set, defaults (a table, or a function
-- returning one: what nil means - today's look), fields (a set of the
-- field names to offer; default all).

local ADDON_NAME, ns = ...

local UI = ns.UI
local GetColor = ns.GetColor
local M, F = UI.M, UI.F
local Changed = UI.Changed
local Custom = ns.Custom
local EMPTY = Custom.EMPTY
local Copy, Clean = Custom.Copy, Custom.Clean

local math_floor, math_max, math_min = math.floor, math.max, math.min

local function DefaultWidth(parent, want)
    local w = parent and parent.GetWidth and parent:GetWidth()
    if type(w) == "number" and w >= 200 then
        return math_max(220, math_min(want, w - 2 * M.CONTROL_X))
    end
    return want
end
local function Def(opts)
    local d = opts.defaults
    if type(d) == "function" then d = d() end
    return type(d) == "table" and d or EMPTY
end
local function Cur(opts)
    local t = opts.get and opts.get()
    return type(t) == "table" and t or nil
end
local function Want(opts, field)
    return not opts.fields or opts.fields[field] and true or false
end
local function PX(v) return string.format("%d px", v) end
local function PCT(v) return string.format("%d%%", v) end
local function SEC(v) return string.format("%.2fs", v) end

-- ============================================================
-- FORM: a two-column flow of bound controls
-- ============================================================
-- bind = { cur = fn() -> table, put = fn(field, value, quiet), def = fn(field) }
-- Every control shows the field's value, or what nil stands for. Sliders
-- carry a small x that puts the field back to nil (the default).
local function Form(host, W, bind)
    local f = { W = W, y = 0, n = 0, rowH = 0, sync = {}, two = W >= 300 }
    f.colW = f.two and math_floor((W - 16) / 2) or W
    function f:EndRow()
        if self.n % 2 == 1 then
            self.y = self.y - self.rowH - 8
            self.n = self.n + 1
        end
    end
    function f:Cell(w, h, full)
        if full or not self.two then
            self:EndRow()
            w:SetPoint("TOPLEFT", host, "TOPLEFT", 0, self.y)
            self.y = self.y - h - 8
            return
        end
        if self.n % 2 == 0 then
            w:SetPoint("TOPLEFT", host, "TOPLEFT", 0, self.y)
            self.rowH = h
        else
            w:SetPoint("TOPLEFT", host, "TOPLEFT", self.colW + 16, self.y)
            self.rowH = math_max(self.rowH, h)
            self.y = self.y - self.rowH - 8
        end
        self.n = self.n + 1
    end
    function f:Height() self:EndRow() return -self.y end
    function f:Sync()
        self.syncing = true
        for _, fn in ipairs(self.sync) do pcall(fn) end
        self.syncing = false
    end
    local function Eff(field, fb)
        local v = bind.cur()[field]
        if v == nil then v = bind.def(field) end
        if v == nil then v = fb end
        return v
    end
    f.Eff = Eff
    -- o: { toStore = fn(v), fromStore = fn(v), full = bool }
    function f:Slider(field, label, lo, hi, step, fmt, fb, o)
        o = o or EMPTY
        local w = (o.full or not self.two) and self.W or self.colW
        local holder = CreateFrame("Frame", nil, host)
        holder:SetSize(w, 30)
        local function Shown()
            local v = tonumber(Eff(field, fb)) or lo
            if o.fromStore then v = o.fromStore(v) end
            return v
        end
        local s = UI.Slider(holder, { label = label, min = lo, max = hi, step = step or 1, value = Shown(),
            width = w - 18, format = fmt,
            onChange = function(v)
                if f.syncing then return end
                if o.toStore then v = o.toStore(v) end
                bind.put(field, v, true)
            end })
        s:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        local x = UI.CloseX(holder, 14, function() bind.put(field, nil) end)
        x:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 3)
        UI.Tooltip(x, "Reset", "Back to the default.")
        self.sync[#self.sync + 1] = function()
            local v = Shown()
            local mn, mx = s.slider:GetMinMaxValues()
            if v < mn or v > mx then s.slider:SetMinMaxValues(math_min(lo, v), math_max(hi, v)) end
            s.slider:SetValue(v)
            s.valueText:SetText(fmt and fmt(v) or tostring(v))
            x:SetShown(bind.cur()[field] ~= nil)
        end
        holder.control, holder.reset = s, x
        -- a label longer than the slider wraps and the slider grows taller
        local h = math_max(30, s:GetHeight() or 30)
        holder:SetHeight(h)
        self:Cell(holder, h, o.full)
        return holder
    end
    -- items: list (or fn) of { text, value }. "Default" (nil) comes first.
    function f:Drop(field, label, items, o)
        o = o or EMPTY
        local w = (o.full or not self.two) and self.W or self.colW
        local function List()
            local l = type(items) == "function" and items() or items
            local out = {}
            if not o.noDefault then out[1] = { text = o.defaultText or "Default", value = "__d" } end
            for _, it in ipairs(l) do out[#out + 1] = it end
            return out
        end
        local function TextOf(v)
            for _, it in ipairs(type(items) == "function" and items() or items) do
                if it.value == v then return it.text end
            end
            return v ~= nil and tostring(v) or nil
        end
        local function Selected()
            local v = bind.cur()[field]
            if v == nil and not o.noDefault then
                local d = bind.def(field)
                local t = d ~= nil and TextOf(d)
                return t and ((o.defaultText or "Default") .. " (" .. t .. ")") or (o.defaultText or "Default")
            end
            return TextOf(v ~= nil and v or bind.def(field)) or ""
        end
        local dd
        local fld = UI.Field(host, label, function(h)
            dd = UI.Dropdown(h, { width = w, items = List, selected = Selected,
                selectedValue = function() local v = bind.cur()[field] if v == nil and not o.noDefault then return "__d" end return v end,
                onSelect = function(v) bind.put(field, v ~= "__d" and v or nil, true) end })
            return dd
        end, { width = w })
        self.sync[#self.sync + 1] = function() dd:SetText(Selected()) end
        self:Cell(fld, fld:GetHeight(), o.full)
        return fld
    end
    function f:Check(field, label, fb, tip)
        -- the label wraps inside its column (width =), never past it
        local cb = UI.Checkbox(host, label, Eff(field, fb) and true or false,
            function(on) if f.syncing then return end bind.put(field, on, true) end,
            { width = self.colW, tooltip = tip })
        self.sync[#self.sync + 1] = function() cb:SetChecked(Eff(field, fb) and true or false) end
        local wrap = CreateFrame("Frame", nil, host)
        local h = math_max(30, (cb:GetHeight() or M.CHECK) + 30 - M.CHECK)
        wrap:SetSize(self.colW, h)
        cb:SetParent(wrap)
        cb:ClearAllPoints()
        cb:SetPoint("LEFT", wrap, "LEFT", 0, -4)
        wrap.control = cb
        self:Cell(wrap, h)
        return wrap
    end
    function f:Color(field, label, fb)
        local cp = UI.ColorPicker(host, { label = label, alpha = true, width = self.colW,
            get = function() return bind.cur()[field] end,
            set = function(r, g, b, a) bind.put(field, r and { r = r, g = g, b = b, a = a or 1 } or nil, true) end,
            default = function()
                local d = bind.def(field)
                if d == nil then d = fb end
                if type(d) == "table" then return ns.ColorOf(d) end
                return 1, 1, 1, 1
            end,
            reset = true, resetTip = "Back to the default." })
        self.sync[#self.sync + 1] = function() cp.Refresh() end
        -- a label too long for the column wraps under itself
        if cp._zFit then cp:_zFit(self.colW) end
        local wrap = CreateFrame("Frame", nil, host)
        local h = math_max(22, (cp:GetHeight() or 16) + 6)
        wrap:SetSize(self.colW, h)
        cp:SetParent(wrap)
        cp:ClearAllPoints()
        cp:SetPoint("LEFT", wrap, "LEFT", 0, 0)
        wrap.control = cp
        self:Cell(wrap, h)
        return wrap
    end
    function f:Texture(field, label)
        local tp = UI.TexturePicker(host, { label = label, width = self.colW,
            get = function() return bind.cur()[field] end,
            set = function(v) bind.put(field, v, true) end })
        self:Cell(tp, tp:GetHeight())
        return tp
    end
    function f:Edit(field, label, hint, o)
        o = o or EMPTY
        local w = (o.full or not self.two) and self.W or self.colW
        local eb
        local fld = UI.Field(host, label, function(h)
            eb = UI.EditBox(h, { width = w, text = bind.cur()[field] or "", clear = false,
                onEnter = function(t)
                    if f.syncing then return end
                    bind.put(field, (t and t ~= "") and t or nil, true)
                end })
            return eb
        end, { width = w })
        if hint then UI.Tooltip(eb.editBox, label, hint) end
        self.sync[#self.sync + 1] = function()
            if not (eb.editBox.HasFocus and eb.editBox:HasFocus()) then eb:SetText(bind.cur()[field] or "") end
        end
        self:Cell(fld, fld:GetHeight(), o.full)
        return fld
    end
    return f
end
UI.CustomForm = Form

-- A spec-editing host: get/set over one spec table, the Form bound to it.
-- put() copies, changes one field, drops empties, hands set() a new
-- table (or nil) and re-syncs every control.
local function SpecHost(parent, opts, want)
    local W = opts.width or DefaultWidth(parent, want or 420)
    local host = CreateFrame("Frame", nil, parent)
    local form
    local bind = {
        cur = function() return Cur(opts) or EMPTY end,
        def = function(field) return Def(opts)[field] end,
        put = function(field, value, quiet)
            local new = Copy(Cur(opts) or {})
            new[field] = value
            if opts.set then opts.set(Clean(new)) end
            if form then form:Sync() end
            if host.OnPut then host.OnPut() end
            if not quiet then Changed("custom") end
        end,
    }
    local top = 0
    if opts.label then
        local t = UI.Font(host, F.LABEL, { text = opts.label })
        t:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        host.title = t
        -- (as tall as the title: the settings window's type is larger)
        top = math.max(18, math.ceil(t:GetStringHeight() or 14) + 4)
    end
    local body = CreateFrame("Frame", nil, host)
    body:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
    body:SetSize(W, 10)
    form = Form(body, W, bind)
    host.form, host.bind, host.body, host.top, host.W = form, bind, body, top, W
    function host:Finish()
        local h = form:Height()
        body:SetHeight(math_max(1, h))
        self:SetSize(W, top + h)
        form:Sync()
        return self
    end
    host.Refresh = function() form:Sync() end
    host._zPaint = function() if host.title then host.title:_zPaint() end end
    return host
end
UI.CustomSpecHost = SpecHost

-- ============================================================
-- POINT GRID (3 x 3 dots)
-- ============================================================
local POINT_LABEL = {
    TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
}
ns.ANCHOR_POINT_LABELS = POINT_LABEL

local function Grid(parent, title, onPick)
    local DOT, GAP, PAD = 12, 5, 4
    local side = PAD * 2 + DOT * 3 + GAP * 2
    local g = CreateFrame("Frame", nil, parent)
    local lab = UI.Font(g, F.SMALL, { text = title, cat = "text", key = "gray" })
    lab:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
    local box = UI.Box(g, "ui", "elementBg")
    box:SetSize(side, side)
    local lg = UI.LabelGap(lab)
    box:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -lg)
    g:SetSize(math_max(side, (lab:GetStringWidth() or 0) + 2), side + lg)
    g.dots, g.sel = {}, nil
    local function PaintDot(b)
        local on = b._zPoint == g.sel
        local fill = on and GetColor("button", "active") or GetColor("button", b._zHot and "hover" or "bg")
        b._zFill:SetVertexColor(fill.r, fill.g, fill.b, 1)
        local k = on and GetColor("ui", "borderSelected") or (b._zHot and GetColor("ui", "accent")) or GetColor("ui", "border")
        for _, t in ipairs(b._zBorder) do t:SetVertexColor(k.r, k.g, k.b, 1) end
    end
    for i, p in ipairs(ns.ANCHOR_POINTS) do
        local b = CreateFrame("Button", nil, box)
        b:SetSize(DOT, DOT)
        local col, row = (i - 1) % 3, math_floor((i - 1) / 3)
        b:SetPoint("TOPLEFT", box, "TOPLEFT", PAD + col * (DOT + GAP), -PAD - row * (DOT + GAP))
        UI.Fill(b, "button", "bg")
        UI.Border(b, "ui", "border")
        b._zPoint = p
        b._zPaint = PaintDot
        b:HookScript("OnEnter", function(self) self._zHot = true PaintDot(self) end)
        b:HookScript("OnLeave", function(self) self._zHot = nil PaintDot(self) end)
        b:SetScript("OnClick", function() onPick(p) end)
        UI.Tooltip(b, POINT_LABEL[p], nil)
        g.dots[p] = b
    end
    function g:Select(p)
        self.sel = p
        for _, b in pairs(self.dots) do PaintDot(b) end
    end
    g._zPaint = function() lab:_zPaint() g:Select(g.sel) end
    g.label = lab
    return g
end
UI.AnchorGrid = Grid

-- ============================================================
-- ANCHOR
-- ============================================================
local ANCHOR_FIELDS = { "point", "relPoint", "x", "y", "to", "justify", "point2", "relPoint2", "x2", "y2", "to2", "fill" }
--   opts.targets   { { value = "<key>", text = "Name text" }, ... } (or a fn)
--                  adds an "Anchor to" dropdown; its first row is the default
--   opts.defaultTargetLabel  what that first row says ("Default")
--   opts.text      true for a FontString: adds Text align (Left / Center / Right)
--   opts.relPoint  false hides the "Of the target" grid
--   opts.min / max / step   offset range (-100 / 100 / 1)
--   opts.defaults  the element's built-in anchor (a table or a fn)
function UI.AnchorPicker(parent, opts)
    opts = opts or {}
    -- a title row always: the Reset sits on it
    local host = SpecHost(parent, setmetatable({ label = opts.label or "" }, { __index = opts }), 420)
    local W, form, bind, body = host.W, host.form, host.bind, host.body
    local function Resolved() return ns.ResolveAnchor(Cur(opts), Def(opts)) end
    local function AnchorSet()
        local c = Cur(opts)
        if not c then return false end
        for _, k in ipairs(ANCHOR_FIELDS) do if c[k] ~= nil then return true end end
        return false
    end

    -- the Reset at the top right (or the grid row when there is no title)
    local reset = UI.Button(host, "Reset", { width = 56, height = 18,
        tooltip = "Back to where it sits by default.",
        onClick = function()
            -- only the anchor's own fields: a frame position keeps its strata etc.
            local new = Copy(Cur(opts) or {})
            for _, k in ipairs(ANCHOR_FIELDS) do new[k] = nil end
            if opts.set then opts.set(Clean(new)) end
            form:Sync()
            if host.OnPut then host.OnPut() end
            Changed("anchor")
        end })
    reset:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    host.resetButton = reset

    local function PickPoint(field, p)
        local s = Cur(opts) or {}
        local d = Def(opts)
        local new = Copy(s)
        if field == "point" then
            -- the default's own point again = back to following the default
            local dp = Custom.VALID_POINT[d.point] and d.point or "CENTER"
            new.point = (p ~= dp) and p or nil
        else
            -- relPoint: stored only when it differs from what nil would give
            new.relPoint = nil
            local _, rp = ns.ResolveAnchor(new, d)
            new.relPoint = (p ~= rp) and p or nil
        end
        if opts.set then opts.set(Clean(new)) end
        form:Sync()
        if host.OnPut then host.OnPut() end
        Changed("anchor")
    end
    local row = CreateFrame("Frame", nil, body)
    local g1 = Grid(row, "Point", function(p) PickPoint("point", p) end)
    g1:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    local x0 = g1:GetWidth() + 16
    local g2
    if opts.relPoint ~= false then
        g2 = Grid(row, "Of the target", function(p) PickPoint("relPoint", p) end)
        g2:SetPoint("TOPLEFT", row, "TOPLEFT", x0, 0)
        x0 = x0 + g2:GetWidth() + 16
    end
    local rowH = g1:GetHeight()
    row:SetSize(W, rowH)
    local targets = opts.targets
    local dd
    if targets then
        local inRow = (W - x0) >= 150
        local dw = inRow and math_min(220, W - x0) or math_min(W, 260)
        local function Items()
            local l = type(targets) == "function" and targets() or targets
            local out = { { text = opts.defaultTargetLabel or "Default", value = "__d" } }
            for _, t in ipairs(l) do out[#out + 1] = t end
            return out
        end
        local function Selected()
            local v = (Cur(opts) or EMPTY).to
            for _, it in ipairs(Items()) do if it.value == v then return it.text end end
            return opts.defaultTargetLabel or "Default"
        end
        local fld = UI.Field(row, "Anchor to", function(h)
            dd = UI.Dropdown(h, { width = dw, items = Items, selected = Selected,
                selectedValue = function() return (Cur(opts) or EMPTY).to or "__d" end,
                onSelect = function(v) bind.put("to", v ~= "__d" and v or nil, true) end })
            return dd
        end, { width = dw })
        if inRow then
            fld:SetPoint("TOPLEFT", row, "TOPLEFT", x0, 0)
        else
            fld:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(rowH + 8))
            rowH = rowH + 8 + fld:GetHeight()
            row:SetHeight(rowH)
        end
        form.sync[#form.sync + 1] = function() dd:SetText(Selected()) end
        host.target = dd
    end
    row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    form.y = -(rowH + 8)
    bind.def = function(field)
        local p, rp, x, y = Resolved()
        if field == "x" then return x elseif field == "y" then return y end
        return Def(opts)[field]
    end
    local lo, hi, st = opts.min or -100, opts.max or 100, opts.step or 1
    host.x = form:Slider("x", "X offset", lo, hi, st, PX, 0)
    host.y = form:Slider("y", "Y offset", lo, hi, st, PX, 0)

    -- text align: a dropdown (Automatic follows the point; Left / Center /
    -- Right pin it). Picking a value is a setting, so it is a dropdown,
    -- not a row of buttons (Zac, 2026-11-02).
    if opts.text then
        form:EndRow()
        local JLABEL = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
        local AUTO = "Automatic"
        local jw = math_min(W, 200)
        local jdd
        local function JSelected()
            local cur = (Cur(opts) or EMPTY).justify
            if JLABEL[cur] then return JLABEL[cur] end
            local _, _, _, _, _, j = Resolved()
            return JLABEL[j] and (AUTO .. " (" .. JLABEL[j]:lower() .. ")") or AUTO
        end
        local fld = UI.Field(body, "Text align", function(h)
            jdd = UI.Dropdown(h, { width = jw,
                items = function()
                    return { { text = AUTO, value = "__d" }, { text = "Left", value = "LEFT" },
                        { text = "Center", value = "CENTER" }, { text = "Right", value = "RIGHT" } }
                end,
                selected = JSelected,
                selectedValue = function() return (Cur(opts) or EMPTY).justify or "__d" end,
                -- (the dropdown raises the change signal itself)
                onSelect = function(v) bind.put("justify", v ~= "__d" and v or nil, true) end })
            return jdd
        end, { width = jw })
        -- (the choices in its tooltip, so the search finds them too)
        UI.Tooltip(jdd, "Text align", "Automatic, left, center or right. Automatic lines the text up with the point it hangs from.")
        form:Cell(fld, fld:GetHeight(), true)
        form.sync[#form.sync + 1] = function() jdd:SetText(JSelected()) end
        host.justify = jdd
        host.justifyField = fld
    end
    form.sync[#form.sync + 1] = function()
        local p, rp = Resolved()
        g1:Select(p)
        if g2 then g2:Select(rp) end
        reset:SetDisabled(not AnchorSet())
    end
    host.point, host.relPoint = g1, g2
    return host:Finish()
end

-- ============================================================
-- FRAME POSITION
-- ============================================================
--   opts like AnchorPicker (targets default to the screen), plus
--   opts.fields: any of strata, level, scale, clamp (default all)
function UI.FramePositionPicker(parent, opts)
    opts = opts or {}
    local W = opts.width or DefaultWidth(parent, 420)
    local host = CreateFrame("Frame", nil, parent)
    local a = UI.AnchorPicker(host, { label = opts.label, width = W, get = opts.get, set = opts.set,
        defaults = opts.defaults, targets = opts.targets, defaultTargetLabel = opts.defaultTargetLabel or "The screen",
        min = opts.min or -1200, max = opts.max or 1200, step = opts.step or 1 })
    a:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    local rest = SpecHost(host, { width = W, get = opts.get, set = opts.set, defaults = opts.defaults })
    rest:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 0, -8)
    local f = rest.form
    if Want(opts, "strata") then
        local items = {}
        for _, s in ipairs(ns.STRATAS) do items[#items + 1] = { text = s:sub(1, 1) .. s:sub(2):lower(), value = s } end
        f:Drop("strata", "Layer", items)
    end
    if Want(opts, "level") then f:Slider("level", "Level (above / below)", -20, 20, 1, function(v) return (v > 0 and "+" or "") .. v end, 0) end
    if Want(opts, "scale") then
        f:Slider("scale", "Scale", 50, 200, 5, PCT, 1,
            { toStore = function(v) return v / 100 end, fromStore = function(v) return math_floor(v * 100 + 0.5) end })
    end
    if Want(opts, "clamp") then f:Check("clamp", "Keep it on the screen", false) end
    rest:Finish()
    -- the two halves share one spec: either one changing re-syncs the other
    rest.OnPut = function() a.Refresh() end
    a.OnPut = function() rest.Refresh() end
    host:SetSize(W, a:GetHeight() + 8 + rest:GetHeight())
    host.anchor, host.rest = a, rest
    host.Refresh = function() a.Refresh() rest.Refresh() end
    return host
end

-- The frame half without the spot: Layer, Level, Scale, Keep on screen
-- for a frame whose mover keeps the position (opts.fields picks; same
-- spec as FramePositionPicker).
function UI.FrameLayerPicker(parent, opts)
    opts = opts or {}
    local host = SpecHost(parent, opts, 420)
    local f = host.form
    if Want(opts, "strata") then
        local items = {}
        for _, s in ipairs(ns.STRATAS) do items[#items + 1] = { text = s:sub(1, 1) .. s:sub(2):lower(), value = s } end
        f:Drop("strata", "Layer", items)
    end
    if Want(opts, "level") then f:Slider("level", "Level (above / below)", -20, 20, 1, function(v) return (v > 0 and "+" or "") .. v end, 0) end
    if Want(opts, "scale") then
        f:Slider("scale", "Scale", 50, 200, 5, PCT, 1,
            { toStore = function(v) return v / 100 end, fromStore = function(v) return math_floor(v * 100 + 0.5) end })
    end
    if Want(opts, "clamp") then f:Check("clamp", "Keep it on the screen", false) end
    return host:Finish()
end

-- ============================================================
-- LAYOUT
-- ============================================================
--   opts.sorts   { { value = "name", text = "Name" }, ... } the orders the
--                feature can do (no sort control without it)
--   opts.grows   ids to offer (default all of ns.LAYOUT_GROWS)
--   opts.maxItems  the "Most shown" slider's top (40); opts.sizeMax (128)
local GROW_LABEL = { RIGHT = "Right", LEFT = "Left", DOWN = "Down", UP = "Up", CENTER = "From the middle" }
function UI.LayoutPicker(parent, opts)
    opts = opts or {}
    local host = SpecHost(parent, opts, 420)
    local f = host.form
    local function Items(list)
        local out = {}
        for _, id in ipairs(list) do out[#out + 1] = { text = GROW_LABEL[id] or id, value = id } end
        return out
    end
    if Want(opts, "grow") then f:Drop("grow", "Grows", Items(opts.grows or ns.LAYOUT_GROWS)) end
    if Want(opts, "wrap") then f:Drop("wrap", "New lines go", Items({ "DOWN", "UP", "RIGHT", "LEFT" })) end
    if Want(opts, "perLine") then f:Slider("perLine", "Per line (0 = one line)", 0, 20, 1, nil, 0) end
    if Want(opts, "max") then f:Slider("max", "Most shown", 1, opts.maxItems or 40, 1, nil, opts.maxItems or 40) end
    if Want(opts, "spacingX") then f:Slider("spacingX", "Gap across", -10, 40, 1, PX, 0) end
    if Want(opts, "spacingY") then f:Slider("spacingY", "Gap down", -10, 40, 1, PX, 0) end
    if Want(opts, "padding") then f:Slider("padding", "Padding", 0, 30, 1, PX, 0) end
    if Want(opts, "itemW") then f:Slider("itemW", "Item width", 8, opts.sizeMax or 128, 1, PX, 20) end
    if Want(opts, "itemH") then f:Slider("itemH", "Item height", 8, opts.sizeMax or 128, 1, PX, 20) end
    if opts.sorts and Want(opts, "sort") then f:Drop("sort", "Order by", opts.sorts) end
    if Want(opts, "reverse") then f:Check("reverse", "Reverse the order", false) end
    return host:Finish()
end

-- ============================================================
-- VISIBILITY
-- ============================================================
--   opts.shows  ids from ns.VIS_SHOW to offer (default all)
local SHOW_LABEL = { always = "Always", combat = "In combat", nocombat = "Out of combat", group = "In a group",
    raid = "In a raid group", instance = "In a dungeon or raid", target = "With a target", resting = "While resting",
    mouseover = "On mouseover", never = "Never" }
ns.VIS_SHOW_LABELS = SHOW_LABEL
local function Pct() return { toStore = function(v) return v / 100 end, fromStore = function(v) return math_floor(v * 100 + 0.5) end } end
function UI.VisibilityPicker(parent, opts)
    opts = opts or {}
    local host = SpecHost(parent, opts, 420)
    local f = host.form
    if Want(opts, "show") then
        local items = {}
        for _, id in ipairs(opts.shows or ns.VIS_SHOW) do items[#items + 1] = { text = SHOW_LABEL[id] or id, value = id } end
        f:Drop("show", "Show", items, { defaultText = "Default" })
    end
    if Want(opts, "alpha") then f:Slider("alpha", "Opacity", 0, 100, 5, PCT, 1, Pct()) end
    if Want(opts, "combatAlpha") then f:Slider("combatAlpha", "Opacity in combat", 0, 100, 5, PCT, 1, Pct()) end
    if Want(opts, "mouseover") then f:Check("mouseover", "Brighten on mouseover", false) end
    if Want(opts, "hoverAlpha") then f:Slider("hoverAlpha", "Opacity on mouseover", 0, 100, 5, PCT, 1, Pct()) end
    if Want(opts, "fadeIn") then f:Slider("fadeIn", "Fade in", 0, 2, 0.05, SEC, 0.2) end
    if Want(opts, "fadeOut") then f:Slider("fadeOut", "Fade out", 0, 2, 0.05, SEC, 0.3) end
    return host:Finish()
end

-- ============================================================
-- CHROME
-- ============================================================
function UI.ChromePicker(parent, opts)
    opts = opts or {}
    local host = SpecHost(parent, opts, 420)
    local f = host.form
    if Want(opts, "bgTexture") then f:Texture("bgTexture", "Background texture") end
    if Want(opts, "bgColor") then f:Color("bgColor", "Background colour") end
    if Want(opts, "bgInset") then f:Slider("bgInset", "Background inset", 0, 10, 1, PX, 0) end
    if Want(opts, "borderSize") then f:Slider("borderSize", "Border size", 0, 6, 1, PX, 1) end
    if Want(opts, "borderColor") then f:Color("borderColor", "Border colour") end
    if Want(opts, "shadowSize") then f:Slider("shadowSize", "Shadow", 0, 12, 1, PX, 0) end
    if Want(opts, "shadowColor") then f:Color("shadowColor", "Shadow colour", { r = 0, g = 0, b = 0, a = 0.6 }) end
    if Want(opts, "glowSize") then f:Slider("glowSize", "Glow", 0, 12, 1, PX, 0) end
    if Want(opts, "glowColor") then f:Color("glowColor", "Glow colour", { r = 1, g = 0.82, b = 0, a = 0.8 }) end
    return host:Finish()
end

-- ============================================================
-- PER-STATE STYLES
-- ============================================================
--   opts.states  { { id = "missing", label = "Someone missing" }, ... }
--   opts.get / set   the WHOLE states table (nil = every state its default)
--   opts.defaults    { [id] = { color =, ... } } (or a fn) - today's look
--   opts.fields      set of: color desat alpha border glow textColor anim
--   opts.remember    a table to keep the chosen state in across rebuilds
local STATE_FIELDS = { "color", "desat", "alpha", "border", "glow", "textColor", "anim" }
function UI.StateEditor(parent, opts)
    opts = opts or {}
    local W = opts.width or DefaultWidth(parent, 420)
    local host = CreateFrame("Frame", nil, parent)
    local states = opts.states or {}
    local mem = opts.remember or {}
    local sel = mem.state
    local okSel = false
    for _, s in ipairs(states) do if s.id == sel then okSel = true end end
    if not okSel then sel = states[1] and states[1].id end
    local top = 0
    if opts.label then
        local t = UI.Font(host, F.LABEL, { text = opts.label })
        t:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        host.title = t
        -- (as tall as the title: the settings window's type is larger)
        top = math.max(18, math.ceil(t:GetStringHeight() or 14) + 4)
    end
    local function All() local t = opts.get and opts.get() return type(t) == "table" and t or nil end
    local function DefOf(field)
        local d = opts.defaults
        if type(d) == "function" then d = d() end
        local s = type(d) == "table" and d[sel]
        return type(s) == "table" and s[field] or nil
    end
    local sub
    local dd
    local fld = UI.Field(host, "State", function(h)
        dd = UI.Dropdown(h, { width = math_min(W, 220),
            items = function()
                local out = {}
                for _, s in ipairs(states) do out[#out + 1] = { text = s.label or s.id, value = s.id } end
                return out
            end,
            selected = function()
                for _, s in ipairs(states) do if s.id == sel then return s.label or s.id end end
                return ""
            end,
            selectedValue = function() return sel end,
            onSelect = function(v) sel = v mem.state = v if sub then sub.Refresh() end end })
        return dd
    end, { width = math_min(W, 220) })
    fld:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
    sub = SpecHost(host, { width = W,
        get = function() local a = All() return a and a[sel] end,
        set = function(spec)
            local a = Copy(All() or {})
            a[sel] = spec
            if opts.set then opts.set(Clean(a)) end
        end,
        defaults = function()
            local d = opts.defaults
            if type(d) == "function" then d = d() end
            return type(d) == "table" and d[sel] or EMPTY
        end })
    sub:SetPoint("TOPLEFT", fld, "BOTTOMLEFT", 0, -8)
    local f = sub.form
    local want = opts.fields
    local function W_(k) return not want or want[k] end
    if W_("color") then f:Color("color", "Colour") end
    if W_("textColor") then f:Color("textColor", "Text colour") end
    if W_("border") then f:Color("border", "Border colour") end
    if W_("glow") then f:Color("glow", "Glow colour") end
    if W_("desat") then
        f:Drop("desat", "Grey it out", { { text = "Yes", value = true }, { text = "No", value = false } })
    end
    if W_("alpha") then f:Slider("alpha", "Opacity", 0, 100, 5, PCT, 1, Pct()) end
    if W_("anim") then
        f:EndRow()
        local ap = UI.AnimationPicker(sub.body, { label = "When it starts", width = W,
            get = function() local s = sub.bind.cur() return s.anim end,
            set = function(spec) sub.bind.put("anim", spec, true) end })
        f:Cell(ap, ap:GetHeight(), true)
        f.sync[#f.sync + 1] = function() ap.Refresh() end
    end
    sub:Finish()
    host:SetSize(W, top + fld:GetHeight() + 8 + sub:GetHeight())
    host.Refresh = function() dd:SetText((function() for _, s in ipairs(states) do if s.id == sel then return s.label or s.id end end return "" end)()) sub.Refresh() end
    host.state, host.editor = dd, sub
    host.Selected = function() return sel end
    host._zPaint = function() if host.title then host.title:_zPaint() end end
    return host
end

-- ============================================================
-- TEXT FORMAT
-- ============================================================
--   opts.kinds   set of what the text holds: number, percent, time, name
--   opts.tokens  { { token = "cur", label = "Current" }, ... } adds a template box
--   opts.sample  fn(spec) -> the text as it would read (a live sample line)
function UI.TextFormatPicker(parent, opts)
    opts = opts or {}
    local host = SpecHost(parent, opts, 420)
    local f = host.form
    local k = opts.kinds or { number = true }
    if k.number then
        f:Drop("abbrev", "Big numbers", { { text = "Short (12.3k)", value = "short" },
            { text = "Commas (12,345)", value = "comma" }, { text = "In full (12345)", value = "full" } })
    end
    if k.number or k.percent then f:Slider("decimals", "Decimals", 0, 3, 1, nil, 1) end
    if k.time then
        f:Drop("time", "Times", { { text = "1:05", value = "mmss" }, { text = "1:05 / 45s", value = "clock" }, { text = "1m / 45s", value = "short" },
            { text = "65s", value = "seconds" } })
        f:Slider("timeDecimalsUnder", "Tenths below (0 = never)", 0, 10, 1, function(v) return v == 0 and "never" or (v .. "s") end, 0)
    end
    if k.name then
        f:Slider("maxLen", "Longest (0 = no limit)", 0, 30, 1, function(v) return v == 0 and "no limit" or (v .. " letters") end, 0)
        f:Edit("mark", "Cut mark", "What ends a shortened name.")
    end
    f:Drop("case", "Letters", { { text = "As they are", value = "none" }, { text = "UPPER CASE", value = "upper" },
        { text = "lower case", value = "lower" } })
    f:Edit("prefix", "Before it")
    f:Edit("suffix", "After it")
    if opts.tokens then
        local names = {}
        for _, t in ipairs(opts.tokens) do names[#names + 1] = "[" .. t.token .. "] " .. (t.label or t.token) end
        f:Edit("template", "Template", "Words and these, in any order: " .. table.concat(names, ", "), { full = true })
    end
    if opts.sample then
        f:EndRow()
        local fs = UI.Font(host.body, F.LABEL, { text = "" })
        local wrap = CreateFrame("Frame", nil, host.body)
        wrap:SetSize(host.W, 16)
        fs:SetParent(wrap)
        fs:SetPoint("LEFT", wrap, "LEFT", 0, 0)
        f:Cell(wrap, 16, true)
        f.sync[#f.sync + 1] = function()
            local ok, s = pcall(opts.sample, Cur(opts) or EMPTY)
            fs:SetText(ok and ("Reads: " .. tostring(s)) or "")
        end
        host.sampleText = fs
    end
    return host:Finish()
end

-- ============================================================
-- SOUND
-- ============================================================
local function SoundItems(noneLabel, defaultLabel)
    local out = {}
    if defaultLabel then out[#out + 1] = { text = defaultLabel, value = "__d" } end
    out[#out + 1] = { text = noneLabel or "None", value = "none" }
    -- the game's own sounds first, under plain names
    if ns.Sounds and ns.Sounds.PickerItems then
        for _, it in ipairs(ns.Sounds.PickerItems()) do out[#out + 1] = it end
    end
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if lsm then
        local list = lsm:List("sound") or {}
        for _, n in ipairs(list) do
            if n ~= "None" then out[#out + 1] = { text = n, value = n } end
        end
    end
    return out
end
-- opts: get = fn() -> name | nil, set = fn(name | nil), width, label, defaultLabel
function UI.SoundPicker(parent, opts)
    opts = opts or {}
    local W = opts.width or 240
    local host = CreateFrame("Frame", nil, parent)
    local dd
    local fld = UI.Field(host, opts.label or "Sound", function(h)
        dd = UI.Dropdown(h, { width = W - 30, items = function() return SoundItems(nil, opts.defaultLabel or "Default") end,
            selected = function()
                local v = opts.get and opts.get()
                if v == nil then return opts.defaultLabel or "Default" end
                if v == "none" then return "None" end
                return (type(v) == "string" and v:match("^ui:(.+)$")) or v
            end,
            selectedValue = function() local v = opts.get and opts.get() return v == nil and "__d" or v end,
            onSelect = function(v) if opts.set then opts.set(v ~= "__d" and v or nil) end end })
        return dd
    end, { width = W - 30 })
    fld:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    local play = UI.Button(host, ">", { width = 24, height = M.DROPDOWN_H, tooltip = "Play it",
        onClick = function()
            local v = opts.get and opts.get()
            if v == nil and opts.preview then v = opts.preview() end
            ns.PlaySoundSpec({ sound = v, channel = opts.channel and opts.channel() or "Master" })
        end })
    play:SetPoint("TOPLEFT", host, "TOPLEFT", W - 24, -UI.LabelGap(fld.label))
    host:SetSize(W, fld:GetHeight())
    host.dropdown, host.control, host.play = dd, dd, play
    host.Refresh = function() if dd and dd._zPoolRefresh then dd:_zPoolRefresh() end end
    return host
end

-- per-event sound: { sound, channel, throttle }
function UI.SoundSpecPicker(parent, opts)
    opts = opts or {}
    local host = SpecHost(parent, opts, 420)
    local f = host.form
    local sp = UI.SoundPicker(host.body, { width = f.colW, label = "Sound",
        get = function() return host.bind.cur().sound end,
        set = function(v) host.bind.put("sound", v, true) end,
        preview = function() return Def(opts).sound end,
        channel = function() return host.form.Eff("channel", "Master") end })
    f:Cell(sp, sp:GetHeight())
    local ch = {}
    for _, c in ipairs(ns.SOUND_CHANNELS) do ch[#ch + 1] = { text = c, value = c } end
    f:Drop("channel", "Channel", ch)
    f:Slider("throttle", "Not again within", 0, 30, 1, function(v) return v == 0 and "no limit" or (v .. "s") end, 0)
    f.sync[#f.sync + 1] = function() sp.Refresh() end
    host.sound = sp
    return host:Finish()
end

-- ============================================================
-- BUNDLES for module pages
-- ============================================================
local function Pool_Refresh(w)
    if not w then return end
    if w._zPoolRefresh then w._zPoolRefresh(w) elseif type(w.Refresh) == "function" then w.Refresh(w) end
end
local function Flash(g)
    if not g._zFlashTex then
        local t = g:CreateTexture(nil, "BACKGROUND")
        t._zui_own = true
        t:SetTexture(ns.FLAT)
        t:SetPoint("TOPLEFT", g, "TOPLEFT", -6, 4)
        t:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 6, -4)
        g._zFlashTex = t
    end
    local a = GetColor("ui", "accent")
    g._zFlashTex:SetVertexColor(a.r, a.g, a.b, 0.18)
    g._zFlashTex:Show()
    C_Timer.After(0.8, function() if g._zFlashTex then g._zFlashTex:Hide() end end)
end

-- The room a control in the card being built may use: the card less the
-- control inset on both sides; while the card has not resolved its width
-- yet, the page's width less the card margins. Pass it as `width` to any
-- picker placed straight into a card so nothing can run past its edge.
function UI.CardInnerWidth(L)
    local card = L and L.current
    local w = card and card.GetWidth and card:GetWidth()
    if type(w) ~= "number" or w < 200 then
        local p = L and L.parent and L.parent.GetWidth and L.parent:GetWidth()
        if type(p) == "number" and p >= 240 then w = p - 2 * M.MARGIN else w = 460 + 2 * M.CONTROL_X end
    end
    return math_max(120, math_floor(w - 2 * M.CONTROL_X))
end

local function GroupHost(card, o, W)
    local g = CreateFrame("Frame", nil, card)
    local y = 0
    if o.label then
        local t = UI.Font(g, F.CARD, { text = o.label })
        t:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
        g.title = t
        y = -20
    end
    g._zFlash = Flash
    g._zPaint = function() if g.title then g.title:_zPaint() end end
    local lastGap = 0
    local function Add(w, gap)
        w:SetPoint("TOPLEFT", g, "TOPLEFT", 0, y)
        lastGap = gap or 10
        y = y - w:GetHeight() - lastGap
    end
    local function Done()
        -- (the group ends at its last part: the gap after it is the card's)
        g:SetSize(W, math_max(1, -y - lastGap))
        -- a pooled group reads every part's settings again
        g._zPoolRefresh = function()
            -- (each by name: a group without a font has a nil first part)
            Pool_Refresh(g.font)
            Pool_Refresh(g.format)
            Pool_Refresh(g.anchor)
            Pool_Refresh(g.chrome)
            for _, cp in ipairs(g.colors or {}) do Pool_Refresh(cp) end
            if g._zSliders then for _, fn in ipairs(g._zSliders) do fn() end end
        end
        return g
    end
    return g, W, Add, Done
end
-- (the group's frame and parts; UIF_Pool hands it back on a live page)
local function Place(L, o, g)
    if o.key then ns.CustomPick.RegisterGroup(o.key, g) end
    L:Add(g, o.gap or 10)
    return g
end

-- UI.TextElement(L, {
--     label = "Name", key = "name",                       -- key: the pick hook
--     fontGet, fontSet, fontDefaults, sample, minSize, maxSize,
--     colorGet, colorSet, colorDefault, colorLabel, colorAlpha,
--     colors = { { label, get, set, default }, ... },    -- several state colours
--     formatGet, formatSet, formatDefaults, formatKinds, formatTokens, formatSample,
--     anchorGet, anchorSet, anchorDefaults, targets, defaultTargetLabel,
--     anchorMin, anchorMax })
-- Any part whose get is missing is left out. Returns the group frame with
-- .font .color .colors .format .anchor.
function UI.TextElement(L, o)
    o = o or {}
    return Place(L, o, UI.TextElementGroup(L.current, o, o.width or UI.CardInnerWidth(L)))
end
function UI.TextElementGroup(card, o, W)
    local g, _, Add, Done = GroupHost(card, o, W)
    if o.fontGet then
        g.font = UI.FontPicker(g, { width = W, get = o.fontGet, set = o.fontSet, defaults = o.fontDefaults,
            sample = o.sample, minSize = o.minSize, maxSize = o.maxSize, defaultLabel = o.fontDefaultLabel,
            defaultPath = o.fontDefaultPath, list = o.fontList })
        Add(g.font)
    end
    local colors = o.colors
    if o.colorGet then
        colors = { { label = o.colorLabel or "Colour", get = o.colorGet, set = o.colorSet, default = o.colorDefault, alpha = o.colorAlpha, reset = o.colorReset } }
    end
    if colors then
        g.colors = {}
        for _, c in ipairs(colors) do
            local cp = UI.ColorPicker(g, { label = c.label, alpha = c.alpha ~= false, get = c.get, set = c.set,
                default = c.default, reset = c.reset })
            Add(cp, 8)
            g.colors[#g.colors + 1] = cp
        end
        g.color = g.colors[1]
    end
    if o.formatGet then
        g.format = UI.TextFormatPicker(g, { label = "Format", width = W, get = o.formatGet, set = o.formatSet,
            defaults = o.formatDefaults, kinds = o.formatKinds, tokens = o.formatTokens, sample = o.formatSample })
        Add(g.format)
    end
    if o.anchorGet then
        g.anchor = UI.AnchorPicker(g, { label = "Position", width = W, get = o.anchorGet, set = o.anchorSet,
            defaults = o.anchorDefaults, targets = o.targets, defaultTargetLabel = o.defaultTargetLabel,
            text = true, min = o.anchorMin, max = o.anchorMax })
        Add(g.anchor)
    end
    return Done()
end

-- UI.FrameElement(L, {
--     label = "Castbar icon", key = "castIcon",
--     anchorGet, anchorSet, anchorDefaults, targets, defaultTargetLabel, anchorMin, anchorMax,
--     sizeGet, sizeSet, sizeMin, sizeMax, sizeLabel,       -- one "Size" (square)
--     widthGet, widthSet, heightGet, heightSet,             -- or width + height
--     chromeGet, chromeSet, chromeDefaults, chromeFields }) -- optional look
function UI.FrameElement(L, o)
    o = o or {}
    return Place(L, o, UI.FrameElementGroup(L.current, o, o.width or UI.CardInnerWidth(L)))
end
function UI.FrameElementGroup(card, o, W)
    local g, _, Add, Done = GroupHost(card, o, W)
    if o.anchorGet then
        g.anchor = UI.AnchorPicker(g, { label = "Position", width = W, get = o.anchorGet, set = o.anchorSet,
            defaults = o.anchorDefaults, targets = o.targets, defaultTargetLabel = o.defaultTargetLabel,
            min = o.anchorMin, max = o.anchorMax })
        Add(g.anchor)
    end
    local lo, hi = o.sizeMin or 4, o.sizeMax or 128
    local function Sl(label, get, set)
        local s = UI.Slider(g, { label = label, min = lo, max = hi, step = 1, width = math_min(W, 260),
            value = tonumber(get()) or lo, format = PX, onChange = function(v) set(v) end })
        Add(s, 8)
        g._zSliders = g._zSliders or {}
        g._zSliders[#g._zSliders + 1] = function() s._zSetQuiet(tonumber(get()) or lo) end
        return s
    end
    if o.sizeGet then g.sizeSlider = Sl(o.sizeLabel or "Size", o.sizeGet, o.sizeSet) end
    if o.widthGet then g.widthSlider = Sl("Width", o.widthGet, o.widthSet) end
    if o.heightGet then g.heightSlider = Sl("Height", o.heightGet, o.heightSet) end
    if o.chromeGet then
        g.chrome = UI.ChromePicker(g, { label = "Look", width = W, get = o.chromeGet, set = o.chromeSet,
            defaults = o.chromeDefaults, fields = o.chromeFields })
        Add(g.chrome)
    end
    return Done()
end

-- ============================================================
-- APPLY TO ALL (finish pass)
-- ============================================================
-- One bar's / one frame's / one plate side's settings onto the others,
-- a section at a time: a button whose menu lists the sections, then a
-- confirm, then ONE write (each key deep-copied), then opts.onDone (the
-- page re-applies and rebuilds). What a thing is and where it sits never
-- travels: the caller's sections name only look keys. A target takes a
-- key only when it has that setting (accepts, or a value there already).
--   UI.ApplyToAll(parent, {
--       text = "Apply to all bars...", width = 130,
--       what = function() return "Bar 1" end,          -- the source's name
--       source = function() return tbl end,
--       targets = function() return { { label, tbl, accepts = fn(key) | nil }, ... } end,
--       sections = { { label = "Look", hint = "size, border...", keys = { ... } }, ... },
--       allLabel = "All four",                          -- nil: no "everything" row
--       onto = function(n) return "the other " .. n .. " bars" end,
--       onDone = function() end })
-- Returns the button (UI.Button).
function UI.ApplyToAll(parent, o)
    o = o or {}
    local Copy = ns.CopySetting or function(v) return v end
    local function Run(keys, label)
        local src = o.source and o.source()
        if type(src) ~= "table" then return 0 end
        local n = 0
        for _, t in ipairs(o.targets and o.targets() or {}) do
            local dst = t.tbl
            if type(dst) == "table" and dst ~= src then
                local took = false
                for _, k in ipairs(keys) do
                    local ok = (t.accepts and t.accepts(k)) or (not t.accepts and dst[k] ~= nil)
                    if ok then
                        dst[k] = Copy(src[k])
                        took = true
                    end
                end
                if took then n = n + 1 end
            end
        end
        if ns.SettingsChanged then pcall(ns.SettingsChanged, "applyToAll") end
        if o.onDone then o.onDone(n, label) end
        return n
    end
    local function Ask(keys, label)
        local targets = o.targets and o.targets() or {}
        local names = {}
        for _, t in ipairs(targets) do names[#names + 1] = t.label end
        local who = o.what and o.what() or "This one"
        local onto = o.onto and o.onto(#targets) or (#names <= 4 and table.concat(names, ", ") or (#names .. " others"))
        UI.Confirm({
            title = o.title or "Apply to all",
            text = who .. "'s " .. label:lower() .. " goes onto " .. onto .. ". Their own "
                .. label:lower() .. " is replaced; where they sit and when they show stay theirs.",
            acceptText = "Apply",
            onAccept = function() Run(keys, label) end,
        })
    end
    local b
    b = UI.Button(parent, o.text or "Apply to all...", { width = o.width or 130,
        tooltip = o.tooltip or "Copies a part of these settings onto the others, after you confirm.",
        onClick = function()
            local who = o.what and o.what() or "This one"
            local items = { { text = "Copy " .. who .. "'s ...", isTitle = true } }
            local all = {}
            for _, s in ipairs(o.sections or {}) do
                for _, k in ipairs(s.keys) do all[#all + 1] = k end
                local sec = s
                items[#items + 1] = { text = sec.label .. (sec.hint and (" (" .. sec.hint .. ")") or ""),
                    func = function() Ask(sec.keys, sec.label) end }
            end
            if o.allLabel then
                items[#items + 1] = { text = o.allLabel, func = function() Ask(all, o.allWord or "settings") end }
            end
            b._zItems = items
            if UI.ContextMenu then UI.ContextMenu(items, { anchor = b }) end
        end })
    b._zRun = Run
    return b
end
