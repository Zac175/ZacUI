-- ============================================================================
-- ZacUF - UI.lua
-- A small, self-contained widget toolkit that mirrors the Readycheck look
-- (dark flat panels, 1px black borders, gold accents, green "active" state,
-- outlined fonts) without depending on any Readycheck media. Flat fills use
-- the always-present "Interface\Buttons\WHITE8X8" texture.
-- ============================================================================
local ADDON, ns = ...

ns.UI = {}
local UI = ns.UI

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Palette (matches Readycheck defaults)
local C = {
    window     = { 0.06, 0.06, 0.06, 0.97 },
    panel      = { 0.12, 0.12, 0.12, 0.98 },
    card       = { 0.08, 0.08, 0.08, 1 },
    header     = { 0.12, 0.12, 0.12, 1 },
    border     = { 0, 0, 0, 1 },
    accent     = { 0.85, 0.65, 0.25, 1 },
    headerText = { 1, 0.82, 0, 1 },
    btn        = { 0.15, 0.15, 0.15, 1 },
    btnHover   = { 0.22, 0.22, 0.22, 1 },
    btnPress   = { 0.10, 0.10, 0.10, 1 },
    active     = { 0.12, 0.16, 0.12, 1 },
    activeHover= { 0.15, 0.20, 0.15, 1 },
    checkBg    = { 0.10, 0.10, 0.10, 1 },
    checkMark  = { 0.40, 0.70, 0.40, 1 },
    txt        = { 0.85, 0.85, 0.85, 1 },
    txtDim     = { 0.55, 0.55, 0.55, 1 },
    txtSel     = { 1, 0.82, 0, 1 },
    closeX     = { 1, 1, 1, 1 },
    closeHover = { 1, 0.30, 0.30, 1 },
    whiteHint  = { 1, 1, 1, 0.05 },
}
UI.C = C

local function unpackc(t) return t[1], t[2], t[3], t[4] or 1 end

-- Current UI font (respects config)
local function uiFont()
    return ns.Media:Font(ns.db and ns.db.media.font or "Friz Quadrata TT")
end

-- FontString with the configured font + outline
function UI:FS(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    -- a face whose file will not load returns false and leaves the string
    -- with no font (its next SetText errors): the game's font then
    local ok, set = pcall(fs.SetFont, fs, uiFont(), size or 12, "OUTLINE")
    if not (ok and set) then fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, "OUTLINE") end
    fs:SetTextColor(unpackc(C.txt))
    return fs
end

-- Apply a flat WHITE8X8 backdrop with 1px black border to a frame.
function UI:Backdrop(frame, bg, border)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(unpackc(bg or C.panel))
    frame:SetBackdropBorderColor(unpackc(border or C.border))
end

-- ----------------------------------------------------------------------------
-- Button
-- ----------------------------------------------------------------------------
function UI:Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 100, h or 22)
    self:Backdrop(b, C.btn, C.border)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(unpackc(C.whiteHint))
    hl:SetBlendMode("ADD")

    b.text = self:FS(b, 12)
    b.text:SetPoint("CENTER")
    b.text:SetText(text)

    b._active = false
    function b:SetActive(on)
        self._active = on and true or false
        self:SetBackdropColor(unpackc(self._active and C.active or C.btn))
    end

    b:SetScript("OnEnter", function(s) s:SetBackdropColor(unpackc(s._active and C.activeHover or C.btnHover)) end)
    b:SetScript("OnLeave", function(s) s:SetBackdropColor(unpackc(s._active and C.active or C.btn)) end)
    b:SetScript("OnMouseDown", function(s) s:SetBackdropColor(unpackc(C.btnPress)) end)
    b:SetScript("OnMouseUp", function(s) s:SetBackdropColor(unpackc(s._active and C.activeHover or C.btnHover)) end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- ----------------------------------------------------------------------------
-- Close (X) button
-- ----------------------------------------------------------------------------
function UI:CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b.x = self:FS(b, 16)
    b.x:SetPoint("CENTER")
    b.x:SetText("x")
    b.x:SetTextColor(unpackc(C.closeX))
    b:SetScript("OnEnter", function(s) s.x:SetTextColor(unpackc(C.closeHover)) end)
    b:SetScript("OnLeave", function(s) s.x:SetTextColor(unpackc(C.closeX)) end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- ----------------------------------------------------------------------------
-- Checkbox
-- ----------------------------------------------------------------------------
function UI:Checkbox(parent, label, checked, onToggle)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(20, 20)

    local box = CreateFrame("Button", nil, f)
    box:SetSize(18, 18)
    box:SetPoint("LEFT")

    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpackc(C.checkBg))

    -- 1px border drawn as four lines so the corners always meet. A 1px
    -- SetBackdrop edge leaves tiny corner gaps that read as a cut-off border.
    local eT = box:CreateTexture(nil, "BORDER"); eT:SetPoint("TOPLEFT"); eT:SetPoint("TOPRIGHT"); eT:SetHeight(1)
    local eB = box:CreateTexture(nil, "BORDER"); eB:SetPoint("BOTTOMLEFT"); eB:SetPoint("BOTTOMRIGHT"); eB:SetHeight(1)
    local eL = box:CreateTexture(nil, "BORDER"); eL:SetPoint("TOPLEFT"); eL:SetPoint("BOTTOMLEFT"); eL:SetWidth(1)
    local eR = box:CreateTexture(nil, "BORDER"); eR:SetPoint("TOPRIGHT"); eR:SetPoint("BOTTOMRIGHT"); eR:SetWidth(1)
    local function setBorder(col)
        eT:SetColorTexture(unpackc(col)); eB:SetColorTexture(unpackc(col))
        eL:SetColorTexture(unpackc(col)); eR:SetColorTexture(unpackc(col))
    end
    setBorder(C.border)

    local mark = box:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:SetTexture("Interface\\AddOns\\Zacui_UnitFrames\\Media\\Checkmark")
    mark:SetVertexColor(unpackc(C.checkMark))
    mark:SetShown(checked and true or false)

    local txt = self:FS(f, 12)
    txt:SetPoint("LEFT", box, "RIGHT", 8, 0)
    txt:SetText(label)
    f:SetWidth(18 + 8 + txt:GetStringWidth() + 4)

    f._checked = checked and true or false
    function f:GetChecked() return self._checked end
    function f:SetChecked(v) self._checked = v and true or false; mark:SetShown(self._checked) end

    box:SetScript("OnEnter", function() setBorder(C.accent) end)
    box:SetScript("OnLeave", function() setBorder(C.border) end)
    box:SetScript("OnClick", function()
        f:SetChecked(not f._checked)
        if onToggle then onToggle(f._checked) end
    end)
    f.box = box
    return f
end

-- ----------------------------------------------------------------------------
-- Color swatch: a bordered square that opens the Blizzard color picker.
-- getColor() -> {r,g,b,a}; setColor(r,g,b,a) writes back. Handles both the
-- modern SetupColorPickerAndShow API and the legacy ColorPickerFrame fields.
-- ----------------------------------------------------------------------------
function UI:ColorSwatch(parent, label, getColor, setColor, hasAlpha)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(20, 20)

    local sw = CreateFrame("Button", nil, f, "BackdropTemplate")
    sw:SetSize(16, 16)
    sw:SetPoint("LEFT")
    self:Backdrop(sw, C.checkBg, C.border)

    local tex = sw:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    local function refresh()
        local c = getColor()
        tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
    refresh()

    local txt = self:FS(f, 11)
    txt:SetPoint("LEFT", sw, "RIGHT", 8, 0)
    txt:SetText(label)
    f:SetWidth(16 + 8 + txt:GetStringWidth() + 4)

    sw:SetScript("OnEnter", function() sw:SetBackdropBorderColor(unpackc(C.accent)) end)
    sw:SetScript("OnLeave", function() sw:SetBackdropBorderColor(unpackc(C.border)) end)
    sw:SetScript("OnClick", function()
        local c = getColor()
        local r, g, b, a = c[1], c[2], c[3], c[4] or 1

        local function commit()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            local na = a
            if hasAlpha then
                if ColorPickerFrame.GetColorAlpha then
                    na = ColorPickerFrame:GetColorAlpha()
                elseif OpacitySliderFrame then
                    na = 1 - OpacitySliderFrame:GetValue()
                end
            end
            setColor(nr, ng, nb, na)
            refresh()
            if ns.ApplySettings then ns.ApplySettings() end
        end
        local function cancel()
            setColor(r, g, b, a); refresh()
            if ns.ApplySettings then ns.ApplySettings() end
        end

        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = b, opacity = a, hasOpacity = hasAlpha and true or false,
                swatchFunc = commit, opacityFunc = commit, cancelFunc = cancel,
            })
        else
            ColorPickerFrame.func        = commit
            ColorPickerFrame.opacityFunc = commit
            ColorPickerFrame.cancelFunc  = cancel
            ColorPickerFrame.hasOpacity  = hasAlpha and true or false
            ColorPickerFrame.opacity     = 1 - a
            ColorPickerFrame.previousValues = { r = r, g = g, b = b, opacity = a }
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end)

    f.swatch = sw
    f.Refresh = refresh
    return f
end

-- ----------------------------------------------------------------------------
-- Slider
-- ----------------------------------------------------------------------------
function UI:Slider(parent, label, min, max, value, step, w, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w or 180, 40)

    local title = self:FS(f, 11)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)

    -- editable value box (click to type an exact number)
    local val = CreateFrame("EditBox", nil, f)
    val:SetSize(44, 16)
    val:SetPoint("TOPRIGHT", 2, 2)
    val:SetAutoFocus(false)
    val:SetFont(uiFont(), 11, "OUTLINE")
    val:SetJustifyH("RIGHT")
    val:SetTextColor(unpackc(C.txtSel))

    local s = CreateFrame("Slider", nil, f, "BackdropTemplate")
    s:SetPoint("TOPLEFT", 0, -16)
    s:SetSize((w or 180), 14)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step or 1)
    s:SetObeyStepOnDrag(true)
    s:SetValue(value)
    self:Backdrop(s, C.checkBg, C.border)

    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(unpackc(C.accent))
    thumb:SetSize(8, 14)
    s:SetThumbTexture(thumb)

    local function norm(v) if step and step >= 1 then v = math.floor(v + 0.5) end return v end
    local typing = false
    local function refresh(v) if not typing then val:SetText(tostring(norm(v))) end end
    refresh(value)

    s:SetScript("OnValueChanged", function(_, v)
        refresh(norm(v))
        if not f._silent and onChange then onChange(norm(v)) end
    end)
    val:SetScript("OnEditFocusGained", function(self) typing = true; self:HighlightText() end)
    val:SetScript("OnEditFocusLost", function(self) typing = false; self:SetText(tostring(norm(s:GetValue()))) end)
    val:SetScript("OnEscapePressed", function(self) typing = false; self:SetText(tostring(norm(s:GetValue()))); self:ClearFocus() end)
    val:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        typing = false
        if v then s:SetValue(math.max(min, math.min(max, v))) end
        self:SetText(tostring(norm(s:GetValue())))
        self:ClearFocus()
    end)

    -- Re-seed the slider to a stored value WITHOUT firing onChange (used when one
    -- slider is reused to edit different keys). Out-of-range values clamp the
    -- thumb but the underlying stored value is left untouched.
    function f:SetValueSilent(v)
        self._silent = true
        s:SetValue(math.max(min, math.min(max, v or 0)))
        val:SetText(tostring(norm(v or 0)))
        self._silent = false
    end

    f.slider = s
    return f
end

-- Compact one-row slider: just a bar + a small editable value box, ~18px tall
-- (the caller supplies any label to its left). getf seeds it and Refresh re-reads
-- it; SetValueSilent re-seeds without firing setf. Used by the element mover so a
-- single row of X / Y (and castbar W / H) sliders stays tidy instead of bloating.
function UI:MiniSlider(parent, w, min, max, step, getf, setf)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w or 150, 18)

    local val = CreateFrame("EditBox", nil, f)
    val:SetSize(38, 16); val:SetPoint("RIGHT", 0, 0); val:SetAutoFocus(false)
    val:SetFont(uiFont(), 11, "OUTLINE"); val:SetJustifyH("RIGHT"); val:SetTextColor(unpackc(C.txtSel))

    local s = CreateFrame("Slider", nil, f, "BackdropTemplate")
    s:SetPoint("LEFT", 0, 0); s:SetPoint("RIGHT", val, "LEFT", -6, 0); s:SetHeight(12)
    s:SetOrientation("HORIZONTAL"); s:SetMinMaxValues(min, max)
    s:SetValueStep(step or 1); s:SetObeyStepOnDrag(true)
    self:Backdrop(s, C.checkBg, C.border)
    local thumb = s:CreateTexture(nil, "OVERLAY"); thumb:SetColorTexture(unpackc(C.accent)); thumb:SetSize(8, 12)
    s:SetThumbTexture(thumb)

    local function norm(v) if step and step >= 1 then v = math.floor(v + 0.5) end return v end
    local typing = false
    s:SetValue(getf() or 0); val:SetText(tostring(norm(getf() or 0)))

    s:SetScript("OnValueChanged", function(_, v)
        if not typing then val:SetText(tostring(norm(v))) end
        if not f._silent then setf(norm(v)) end
    end)
    val:SetScript("OnEditFocusGained", function(self) typing = true; self:HighlightText() end)
    val:SetScript("OnEditFocusLost", function(self) typing = false; self:SetText(tostring(norm(s:GetValue()))) end)
    val:SetScript("OnEscapePressed", function(self) typing = false; self:SetText(tostring(norm(s:GetValue()))); self:ClearFocus() end)
    val:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText()); typing = false
        if v then s:SetValue(math.max(min, math.min(max, v))) end
        self:SetText(tostring(norm(s:GetValue()))); self:ClearFocus()
    end)

    function f:SetValueSilent(v)
        self._silent = true
        s:SetValue(math.max(min, math.min(max, v or 0)))
        val:SetText(tostring(norm(v or 0)))
        self._silent = false
    end
    function f:Refresh() self:SetValueSilent(getf() or 0) end
    f.slider = s
    return f
end
-- items: array of strings (values == labels). onSelect(value).
-- ----------------------------------------------------------------------------
local openDrop
function UI:Dropdown(parent, w, items, current, onSelect)
    w = w or 160
    local d = CreateFrame("Button", nil, parent, "BackdropTemplate")
    d:SetSize(w, 22)
    self:Backdrop(d, C.btn, C.border)

    d.text = self:FS(d, 12)
    d.text:SetPoint("LEFT", 6, 0)
    d.text:SetPoint("RIGHT", -18, 0)
    d.text:SetJustifyH("LEFT")
    d.text:SetText(current or "")

    local arrow = d:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\AddOns\\Zacui_UnitFrames\\Media\\arrow")
    arrow:SetVertexColor(unpackc(C.accent))

    d.items = items or {}
    d.value = current

    -- list panel
    local list = CreateFrame("Frame", nil, d, "BackdropTemplate")
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
    list:SetWidth(w)
    self:Backdrop(list, C.panel, C.border)
    list:EnableMouseWheel(true)
    list:Hide()

    local ROW, MAXVIS, SEARCH_H = 20, 10, 22
    local rows, offset = {}, 0
    d.filter = ""

    -- Search box, shown only for long lists that need scrolling
    local sc = CreateFrame("Frame", nil, list, "BackdropTemplate")
    sc:SetPoint("TOPLEFT", 3, -3); sc:SetPoint("TOPRIGHT", -3, -3); sc:SetHeight(18)
    UI:Backdrop(sc, C.checkBg, C.border)
    local sb = CreateFrame("EditBox", nil, sc)
    sb:SetPoint("TOPLEFT", 5, 0); sb:SetPoint("BOTTOMRIGHT", -5, 0)
    sb:SetAutoFocus(false)
    sb:SetFont(uiFont(), 12, "OUTLINE")
    sb:SetTextColor(unpackc(C.txt))
    sb:SetJustifyH("LEFT")
    local sbHint = UI:FS(sc, 11)
    sbHint:SetPoint("LEFT", 6, 0)
    sbHint:SetText("search...")
    sbHint:SetTextColor(unpackc(C.txtDim))

    local function source()
        if d.filter == "" then return d.items end
        local out, q = {}, d.filter:lower()
        for _, it in ipairs(d.items) do
            if tostring(it):lower():find(q, 1, true) then out[#out + 1] = it end
        end
        return out
    end
    local function hasSearch() return #d.items > MAXVIS end
    local function topPad() return hasSearch() and SEARCH_H or 0 end

    local function layout()
        local vis = math.min(#source(), MAXVIS)
        sc:SetShown(hasSearch())
        list:SetHeight(topPad() + vis * ROW + 6)
        for i = 1, vis do
            local r = rows[i]
            if not r then
                r = CreateFrame("Button", nil, list)
                r.hl = r:CreateTexture(nil, "BACKGROUND")
                r.hl:SetAllPoints()
                r.hl:SetColorTexture(unpackc(C.activeHover))
                r.hl:Hide()
                r.label = UI:FS(r, 12)
                r.label:SetPoint("LEFT", 5, 0)
                r.label:SetPoint("RIGHT", -5, 0)
                r.label:SetJustifyH("LEFT")
                r.label:SetWordWrap(false)
                r:SetScript("OnEnter", function(self) self.hl:Show() end)
                r:SetScript("OnLeave", function(self) self.hl:Hide() end)
                r:SetScript("OnClick", function(self)
                    d.value = self.value
                    d.text:SetText(self.value)
                    list:Hide(); openDrop = nil
                    if onSelect then onSelect(self.value) end
                end)
                rows[i] = r
            end
            r:SetSize(w - 6, ROW)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 3, -3 - topPad() - (i - 1) * ROW)
            r:Show()
        end
        for i = vis + 1, #rows do rows[i]:Hide() end
    end

    local function paint()
        local items = source()
        local n = #items
        local vis = math.min(n, MAXVIS)
        offset = math.max(0, math.min(offset, n - vis))
        for i = 1, vis do
            local item = items[i + offset]
            local r = rows[i]
            r.value = item
            r.label:SetText(item)
            if item == d.value then r.label:SetTextColor(unpackc(C.txtSel))
            else r.label:SetTextColor(unpackc(C.txt)) end
        end
    end

    sb:SetScript("OnTextChanged", function(self)
        d.filter = self:GetText() or ""
        sbHint:SetShown(d.filter == "")
        offset = 0; layout(); paint()
    end)
    sb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    list:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta
        paint()
    end)

    local function toggle()
        if list:IsShown() then list:Hide(); openDrop = nil; return end
        if openDrop and openDrop ~= list then openDrop:Hide() end
        d.filter = ""; sb:SetText(""); sbHint:Show()
        offset = 0; layout(); paint()
        list:ClearAllPoints()
        local below = d:GetBottom()
        if below and below - list:GetHeight() < 40 then
            list:SetPoint("BOTTOMLEFT", d, "TOPLEFT", 0, 2)    -- not enough room below -> open upward
        else
            list:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
        end
        list:Show(); openDrop = list
    end

    d:SetScript("OnClick", toggle)
    d:SetScript("OnEnter", function(s) s:SetBackdropBorderColor(unpackc(C.accent)) end)
    d:SetScript("OnLeave", function(s) s:SetBackdropBorderColor(unpackc(C.border)) end)

    function d:SetItems(t) self.items = t or {} end
    function d:SetValue(v) self.value = v; self.text:SetText(v or "") end
    function d:GetValue() return self.value end
    return d
end

-- ----------------------------------------------------------------------------
-- Tab bar.  tabs = array of strings.  onSelect(index, text).
-- ----------------------------------------------------------------------------
function UI:TabBar(parent, tabs, onSelect, fill)
    local bar = CreateFrame("Frame", nil, parent)
    bar.buttons = {}
    local GAP = 4
    local x = 0
    for i, label in ipairs(tabs) do
        local b = CreateFrame("Button", nil, bar, "BackdropTemplate")
        b.text = self:FS(b, 12)
        b.text:SetText(label)
        local tw = b.text:GetStringWidth() + 24
        b:SetSize(tw, 26)
        b:SetPoint("LEFT", x, 0)
        b.text:SetPoint("CENTER")
        self:Backdrop(b, C.btn, C.border)
        x = x + tw + GAP

        b._i = i
        function b:Select(on)
            self._sel = on
            self:SetBackdropColor(unpackc(on and C.active or C.btn))
            self.text:SetTextColor(unpackc(on and C.txtSel or C.txt))
        end
        b:SetScript("OnEnter", function(s) if not s._sel then s:SetBackdropColor(unpackc(C.btnHover)) end end)
        b:SetScript("OnLeave", function(s) if not s._sel then s:SetBackdropColor(unpackc(C.btn)) end end)
        b:SetScript("OnClick", function(s)
            for _, other in ipairs(bar.buttons) do other:Select(false) end
            s:Select(true)
            if onSelect then onSelect(s._i, label) end
        end)
        bar.buttons[i] = b
    end
    bar:SetSize(x, 26)
    function bar:SelectTab(i)
        local b = self.buttons[i]; if b then b:GetScript("OnClick")(b) end
    end

    -- Fill mode: the caller anchors the bar to BOTH sides of its parent and the
    -- tabs share the width equally, so the row spans the window at any size
    -- instead of stopping short on a wide one. Re-laid out on every size
    -- change (cheap: n SetWidth calls).
    if fill then
        local n = #bar.buttons
        local function relayout()
            local w = bar:GetWidth()
            if not w or w <= 0 or n == 0 then return end
            local bw = math.max(40, (w - GAP * (n - 1)) / n)
            local xx = 0
            for _, b in ipairs(bar.buttons) do
                b:SetWidth(bw)
                b:ClearAllPoints()
                b:SetPoint("LEFT", xx, 0)
                xx = xx + bw + GAP
            end
        end
        bar:SetScript("OnSizeChanged", relayout)
        bar.Relayout = relayout
    end
    return bar
end

-- ----------------------------------------------------------------------------
-- Resize grip: six dots in the bottom-right corner - the same handle ZacUI and
-- Readycheck use, deliberately, so the gesture transfers between the three.
-- Drawn (2px squares) rather than textured so it scales honestly at any UI
-- scale. Dots light gold on hover; a corner nobody discovers is a window
-- nobody resizes. opts: minW/minH/maxW/maxH, onResizeStopped(frame) - fired
-- AFTER the drag, never per-frame (relaying out a page that often is a freeze).
-- ----------------------------------------------------------------------------
local RESIZE_DOTS = { {2,2}, {6,2}, {10,2}, {6,6}, {10,6}, {10,10} }

function UI:AttachResizeGrip(frame, opts)
    opts = opts or {}
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(opts.minW or 200, opts.minH or 120, opts.maxW or 1400, opts.maxH or 1000)
    elseif frame.SetMinResize then
        frame:SetMinResize(opts.minW or 200, opts.minH or 120)
        if frame.SetMaxResize then frame:SetMaxResize(opts.maxW or 1400, opts.maxH or 1000) end
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", 0, 0)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip.dots = {}

    local function rest()
        for _, d in ipairs(grip.dots) do
            d:SetColorTexture(C.txtDim[1] * 0.7, C.txtDim[2] * 0.7, C.txtDim[3] * 0.7, 0.85)
        end
    end
    for i, pos in ipairs(RESIZE_DOTS) do
        local dot = grip:CreateTexture(nil, "ARTWORK")
        dot:SetSize(2, 2)
        dot:SetPoint("BOTTOMLEFT", grip, "BOTTOMLEFT", pos[1], pos[2])
        grip.dots[i] = dot
    end
    rest()

    grip:SetScript("OnEnter", function()
        for _, d in ipairs(grip.dots) do d:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1) end
    end)
    grip:SetScript("OnLeave", rest)
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        if opts.onResizeStopped then opts.onResizeStopped(frame) end
    end)
    frame.grip = grip
    return grip
end

-- ----------------------------------------------------------------------------
-- Section label
-- ----------------------------------------------------------------------------
function UI:Section(parent, text)
    local fs = self:FS(parent, 13)
    fs:SetText(text)
    fs:SetTextColor(unpackc(C.headerText))
    return fs
end

-- ----------------------------------------------------------------------------
-- EditBox: small bordered numeric input. getf() seeds it; setf(number) fires on
-- Enter / focus-loss with the parsed value (non-numeric input is reverted).
-- ----------------------------------------------------------------------------
function UI:EditBox(parent, w, getf, setf)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w or 56, 20)
    eb:SetAutoFocus(false)
    eb:SetFont(uiFont(), 12, "OUTLINE")
    eb:SetTextColor(unpackc(C.txt))
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetJustifyH("LEFT")
    self:Backdrop(eb, C.checkBg, C.border)
    eb:SetText(tostring(getf()))

    local function commit()
        local val = tonumber(eb:GetText())
        if val then setf(val) end
        eb:SetText(tostring(getf()))
    end
    eb:SetScript("OnEnterPressed", function(self) commit(); self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(tostring(getf())); self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpackc(C.accent)); self:HighlightText() end)
    eb:SetScript("OnEditFocusLost", function(self) commit(); self:SetBackdropBorderColor(unpackc(C.border)) end)
    eb.Refresh = function() eb:SetText(tostring(getf())) end
    return eb
end

-- Free-text single-line input (aura names or spell IDs). Caller wires OnEnterPressed.
function UI:TextBox(parent, w)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w or 160, 20)
    eb:SetAutoFocus(false)
    eb:SetFont(uiFont(), 12, "OUTLINE")
    eb:SetTextColor(unpackc(C.txt))
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetJustifyH("LEFT")
    self:Backdrop(eb, C.checkBg, C.border)
    eb:SetScript("OnEditFocusGained", function(s) s:SetBackdropBorderColor(unpackc(C.accent)); s:HighlightText() end)
    eb:SetScript("OnEditFocusLost", function(s) s:SetBackdropBorderColor(unpackc(C.border)) end)
    eb:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus() end)
    return eb
end

-- Multi-line, scrollable text box (for the long import/export profile string).
-- Returns the scroll frame; the editbox is frame.editBox. SelectAll() highlights
-- everything for an easy Ctrl+C.
function UI:MultiLineBox(parent, w, h)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(w, h)
    self:Backdrop(frame, C.checkBg, C.border)

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 5, -5)
    scroll:SetPoint("BOTTOMRIGHT", -5, 5)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(uiFont(), 11, "")
    eb:SetTextColor(unpackc(C.txt))
    eb:SetWidth(w - 12)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function(s) frame:SetBackdropBorderColor(unpackc(C.accent)) end)
    eb:SetScript("OnEditFocusLost", function(s) frame:SetBackdropBorderColor(unpackc(C.border)) end)
    -- keep the caret/typed line in view as it grows
    eb:SetScript("OnCursorChanged", function(_, _, y, _, hgt)
        local top = scroll:GetVerticalScroll()
        local view = scroll:GetHeight()
        if -y < top then scroll:SetVerticalScroll(-y)
        elseif -y + hgt > top + view then scroll:SetVerticalScroll(-y + hgt - view) end
    end)
    scroll:SetScrollChild(eb)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, d)
        self:SetVerticalScroll(math.max(0, self:GetVerticalScroll() - d * 24))
    end)

    frame.editBox = eb
    function frame:GetText() return eb:GetText() end
    function frame:SetText(t) eb:SetText(t or "") end
    function frame:SelectAll() eb:SetFocus(); eb:HighlightText() end
    return frame
end

-- ----------------------------------------------------------------------------
-- Card: dark panel, 1px black border, 3px gold left accent, gold title.
-- Matches the Readycheck settings-card look. Caller sizes/positions it and
-- places controls inside relative to the card.
-- ----------------------------------------------------------------------------
function UI:Card(parent, title)
    local c = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self:Backdrop(c, C.card, C.border)

    local accent = c:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
    accent:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
    c.accent = accent

    if title then
        c.title = self:FS(c, 12)
        c.title:SetPoint("TOPLEFT", 10, -8)
        c.title:SetText(title)
        c.title:SetTextColor(unpackc(C.headerText))
    end
    return c
end

-- ----------------------------------------------------------------------------
-- Window: movable, titled panel with a close button and accent underline.
-- Returns the frame; put content inside frame.content.
-- ----------------------------------------------------------------------------
function UI:Window(name, title, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    -- Never taller than the screen. A window taller than the usable height gets
    -- pinned to the top by SetClampedToScreen and refuses to drag down (shows up
    -- at higher UI scales, where UIParent is shorter than this window).
    local maxH = (UIParent:GetHeight() or 768) - 40
    if h > maxH then h = maxH end
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)        -- clicking a window raises it above the other one
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    self:Backdrop(f, C.window, C.border)

    local function startDrag() f:StartMoving() end
    local function stopDrag()
        f:StopMovingOrSizing()
        -- Re-anchor to an absolute corner so the next drag starts from a clean
        -- single point (a leftover CENTER anchor can make it jump on re-drag).
        local l, b = f:GetLeft(), f:GetBottom()
        if l and b then
            f:ClearAllPoints()
            f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
        end
    end

    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1); header:SetPoint("TOPRIGHT", -1, -1); header:SetHeight(30)
    -- the header art every ZacUI window wears, when ZacUI's framework is up
    local ZUI = ns.ZUI or _G.ZacUI
    local art = ZUI and ZUI.UI and ZUI.UI.HeaderArt
    if art then
        art(header, { stepX = 150 })
    else
        self:Backdrop(header, C.header, C.border)
    end
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", startDrag)
    header:SetScript("OnDragStop", stopDrag)

    local titleFS = self:FS(header, 14)
    titleFS:SetPoint("LEFT", 10, art and 2 or 0)
    titleFS:SetText(title)
    titleFS:SetTextColor(unpackc(C.headerText))

    if not art then
        local underline = header:CreateTexture(nil, "OVERLAY")
        underline:SetPoint("BOTTOMLEFT", 0, 0); underline:SetPoint("BOTTOMRIGHT", 0, 0)
        underline:SetHeight(1)
        underline:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
    end

    local close = self:CloseButton(header, function() f:Hide() end)
    close:SetPoint("RIGHT", -6, 0)

    f:SetScript("OnDragStart", startDrag)
    f:SetScript("OnDragStop", stopDrag)

    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", 10, -38)
    f.content:SetPoint("BOTTOMRIGHT", -10, 10)

    tinsert(UISpecialFrames, name) -- close on Escape
    return f
end
