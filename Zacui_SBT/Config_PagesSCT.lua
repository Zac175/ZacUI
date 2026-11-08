-- Config_PagesSCT - the Scrolling text page: the building blocks every
-- tab shares, the live preview, then the tabs in ZacUI's usual order -
-- General, Events, Alerts, Areas, Text, Animation, Advanced.
-- Part of ZacUI (Zacui_SBT). Written for ZacUI.
--
-- Every setting the scrolling text has is on this page. There is no
-- Save button: a control writes the setting the moment it changes, the
-- same as everywhere else in ZacUI, and the preview beside the window
-- follows on the next frame.
local ns = _G.ZacUI
if not ns then return end
local S = ns.SBT
if not S then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local RegisterPage = ns.RegisterPage
local UI = ns.UI
if not (RegisterPage and UI) then return end

local M, F = UI.M, UI.F

-- The page reads these from SCT_Settings; a settings file from before
-- they existed (a half-copied update) must not stop the page building.
S.OutlineId = S.OutlineId or function(v)
    if v == nil then return nil end
    local u = tostring(v):upper()
    if u == "" or u == "NONE" then return "none" end
    if u:find("MONO", 1, true) then return "monochrome" end
    if u:find("THICK", 1, true) then return "thick" end
    return "outline"
end
S.Flags = S.Flags or function(v)
    local map = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE", monochrome = "MONOCHROME" }
    return map[v] or (v == nil and "OUTLINE") or tostring(v)
end
S.MotionOn = S.MotionOn or function() return true end

-- What the page is looking at: which scroll area, which event category,
-- which row is open. Not saved - it is a view, not a setting.
S.view = S.view or {}
local view = S.view

-- Tabs register themselves here from their own files.
S.tabs = S.tabs or {}

local W = {}
S.W = W

-- The width every strip of controls is laid out for: what fits inside a
-- card at the config window's stock size.
local INNER = 500
W.INNER = INNER

function W.Refresh()
    if ns.RefreshConfig then ns.RefreshConfig() end
end

local function Say(msg)
    if Print then Print(msg) end
end
W.Say = Say

-- A hand-made control that changes a setting says so, so the preview
-- follows (every ZacUI widget does this on its own).
local function Changed(source)
    if ns.SettingsChanged then ns.SettingsChanged(source or "sbt") end
end
W.Changed = Changed

-- The framework's pickers, or an empty spot where an older framework has
-- none (the page then simply goes without that control).
local function Picker(name, parent, o)
    local fn = UI[name]
    if fn then return fn(parent, o) end
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(o and o.width or 30, 16)
    return f
end
W.Picker = Picker

-- L:Add where the layout has it (a row as tall as the widget says)
local function Add(L, w, gap)
    if L.Add then return L:Add(w, gap) end
    return L:Row(w, (w.GetHeight and w:GetHeight() or 20) + (gap or 8))
end
W.Add = Add

local function Enable(w, on, why)
    if UI.SetEnabled then UI.SetEnabled(w, on, why) end
end

-- ============================================================
-- ROWS
-- ============================================================
-- A bare strip in the current card that a tab lays several controls
-- out on, side by side.
--
-- The window can be resized. Wider than stock, a strip simply gets the
-- extra room (host.inner says how much, for things that sit at its
-- right-hand end). Narrower, the strip keeps its laid-out width and is
-- scaled down to fit instead: smaller, but every control still on the
-- page, where clipping would silently take the right-hand buttons away.
-- The width comes from the page itself, which has a set width; a card's
-- own width is not known until it has been drawn once.
local function Fit(L)
    local pw = L.parent and L.parent.GetWidth and L.parent:GetWidth() or 0
    if not pw or pw < 200 then return INNER, 1 end
    local inner = pw - 2 * M.MARGIN - 2 * M.CONTROL_X
    if inner >= INNER then return inner, 1 end
    return INNER, math.max(0.5, inner / INNER)
end

function W.Host(L, height)
    local card = L.current
    local y = card._y
    local width, scale = Fit(L)
    local host = UI.Holder(card)
    host:SetSize(width, height)
    host.inner = width
    L:Row(host, math.ceil(height * scale))
    -- a control on the strip that came out taller (a label that wrapped)
    -- makes the strip that much taller; only while it is the last row
    function host:Grow(extra)
        local add = extra - (self._zGrown or 0)
        if add <= 0 or L.current ~= card then return end
        self._zGrown = extra
        self:SetHeight(self:GetHeight() + add)
        card._y = card._y - math.ceil(add * scale)
    end
    if scale < 1 then
        -- a scaled frame reads its own offsets in its own scale
        host:SetScale(scale)
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT", card, "TOPLEFT", M.CONTROL_X / scale, y / scale)
    end
    return host
end

function W.Put(host, widget, x, y)
    widget:SetParent(host)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", host, "TOPLEFT", x or 0, y or 0)
    return widget
end

function W.Label(parent, text, key)
    return UI.Font(parent, F.LABEL, { text = text, cat = "text", key = key or "normal" })
end

function W.Small(parent, text, key)
    return UI.Font(parent, F.SMALL, { text = text, cat = "text", key = key or "gray" })
end

-- ============================================================
-- CONTROLS
-- ============================================================
function W.Check(L, label, value, onChange, desc)
    local w = UI.Checkbox(L.current, label, value and true or false, function(v)
        onChange(v and true or false)
    end)
    L:Row(w, 17)
    if desc then L:Desc(desc) end
    return w
end

function W.Slider(L, o)
    local w = UI.Slider(L.current, {
        width = o.width or 200, min = o.min, max = o.max, step = o.step or 1,
        value = o.value, label = o.label, format = o.format, onChange = o.set,
    })
    L:Row(w, 40)
    if o.desc then L:Desc(o.desc) end
    return w
end

local function TextFor(items, value, fallback)
    for _, item in ipairs(items) do
        if item.value == value then return item.text end
    end
    return fallback
end
W.TextFor = TextFor

-- o: label, width, items (table or function), get(), set(value),
-- missing(value) -> text for a value the list does not have.
function W.Dropdown(parent, o)
    local width = o.width or 180
    local host = UI.Holder(parent)
    host:SetSize(width, M.DROPDOWN_H)
    local y = 0
    if o.label then
        local fs = W.Small(host, o.label)
        fs:SetPoint("TOPLEFT", 0, 0)
        -- no wider than the control under it (cut short, whole in its tooltip)
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        if UI.TruncTip then host:EnableMouse(true) UI.TruncTip(fs, host) end
        -- under its label however big the font is
        y = -(UI.LabelGap and UI.LabelGap(fs) or 14)
        host:SetHeight(-y + M.DROPDOWN_H)
    end
    local function Items()
        if type(o.items) == "function" then return o.items() or {} end
        return o.items or {}
    end
    local dd = UI.Dropdown(host, {
        width = width,
        items = Items,
        selected = function()
            local v = o.get()
            local fallback = o.missing and o.missing(v) or (v ~= nil and tostring(v) or "")
            return TextFor(Items(), v, fallback)
        end,
        selectedValue = function() return o.get() end,
        onSelect = function(v) o.set(v) end,
    })
    dd:SetPoint("TOPLEFT", 0, y)
    host.dropdown = dd
    return host
end

-- A text box that writes as you type, like every other control here.
-- Clicking somewhere else does not take the cursor out of a text box in
-- this client, so "writes when you leave it" would mean "writes when you
-- remember to press Enter" - and a setting that silently did not save
-- is worse than one that saved a letter early.
-- o: label, width, text, set(text), hint, number (true: handed over as
-- a number; while what is typed is not one, nothing is written, and it
-- is put back to the last good value when you leave the box), valid
-- (optional: text -> true, or false and a reason; text that fails is
-- treated the same way, and the reason is said when you leave the box)
function W.Edit(parent, o)
    local width = o.width or 180
    local host = UI.Holder(parent)
    host:SetSize(width, M.EDIT_H)
    local y = 0
    if o.label then
        local fs = W.Small(host, o.label)
        fs:SetPoint("TOPLEFT", 0, 0)
        -- no wider than the control under it (cut short, whole in its tooltip)
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        if UI.TruncTip then host:EnableMouse(true) UI.TruncTip(fs, host) end
        y = -(UI.LabelGap and UI.LabelGap(fs) or 14)
        host:SetHeight(-y + M.EDIT_H)
    end
    local last = tostring(o.text == nil and "" or o.text)
    local box
    local function Commit(leaving)
        local text = box:GetText() or ""
        if text == last then return end
        if o.number then
            local n = tonumber(text)
            -- "1e999" and friends are numbers to tonumber; they are not
            -- something a position or a saved setting can hold
            if not n or n ~= n or n == math.huge or n == -math.huge then
                if leaving then box:SetText(last) end
                return
            end
            last = text
            o.set(n)
        else
            if o.valid then
                local good, why = o.valid(text)
                if not good then
                    if leaving then
                        box:SetText(last)
                        if why then Say(why) end
                    end
                    return
                end
            end
            last = text
            o.set(text)
        end
        -- typing is not one of the widget's own commits: say so here,
        -- so the preview follows what was typed
        Changed("sbt.edit")
    end
    box = UI.EditBox(host, { width = width, text = last, hint = o.hint, clear = false,
        onEnter = function() Commit(true) end,
        onChange = function() Commit(false) end })
    box:SetPoint("TOPLEFT", 0, y)
    box.editBox:HookScript("OnEditFocusLost", function() Commit(true) end)
    host.box = box
    function host:GetText() return box:GetText() end
    function host:SetText(t)
        last = tostring(t == nil and "" or t)
        box:SetText(last)
    end
    return host
end

-- A colour swatch over three numbers: ZacUI's colour picker. get()
-- returns r, g, b; set(r, g, b) stores them. Cancel puts back the colour
-- it opened with, and every change reaches the preview.
function W.Swatch(parent, get, set, opts)
    opts = opts or {}
    return Picker("ColorPicker", parent, {
        label = opts.label, tooltip = opts.tooltip,
        get = function() return get() end,
        set = function(r, g, b) set(r, g, b) end,
    })
end

-- Buttons left to right on one row. defs: { label, width, onClick,
-- tooltip, disabled }
function W.Buttons(L, defs)
    local host = W.Host(L, M.BUTTON_H + 6)
    local x = 0
    host.buttons = {}
    for _, d in ipairs(defs) do
        local w = d.width or 70
        local b = UI.Button(host, d.label, { width = w, onClick = d.onClick, tooltip = d.tooltip })
        b:SetPoint("TOPLEFT", host, "TOPLEFT", x, 0)
        if d.disabled then b:SetDisabled(true) end
        host.buttons[#host.buttons + 1] = b
        x = x + (b:GetWidth() or w) + 6     -- (a button is never narrower than its label)
    end
    return host
end

-- Greyed out and deaf to the mouse: a control showing a value it does
-- not own.
local function Dim(widget, off)
    widget:SetAlpha(off and 0.35 or 1)
    if widget.slider then widget.slider:EnableMouse(not off) end
    if widget.dropdown then widget.dropdown:EnableMouse(not off) end
    if widget._zCheck then widget:EnableMouse(not off) end
end
W.Dim = Dim


-- ============================================================
-- SHARED PIECES FOR THE TABS
-- ============================================================
local function Cfg() return S.Cfg() end

local function AreaItems()
    local items = {}
    for _, e in ipairs(S.Areas()) do items[#items + 1] = { text = e.name, value = e.key } end
    return items
end
W.AreaItems = AreaItems

local function SoundItems()
    local items = { { text = "No sound", value = false } }
    -- the game's own sounds first, under plain names
    if ns.Sounds and ns.Sounds.PickerItems then
        for _, it in ipairs(ns.Sounds.PickerItems()) do items[#items + 1] = it end
    end
    for _, name in ipairs(S.SoundNames()) do items[#items + 1] = { text = name, value = name } end
    return items
end

-- a slider placed on a strip rather than as its own row
local function SliderAt(host, x, y, o)
    local s = UI.Slider(host, { width = o.width or 150, min = o.min, max = o.max, step = o.step or 1,
        value = o.value, label = o.label, format = o.format, onChange = o.set })
    W.Put(host, s, x, y)
    if (s._zExtraH or 0) > 0 and host.Grow then host:Grow(s._zExtraH) end
    return s
end
W.SliderAt = SliderAt

local function Pct(v) return v .. "%" end
local function Secs(v) return string.format("%.2fs", v) end
local function Px(v) return v .. " px" end
local function Round2(v) return math.floor(v * 100 + 0.5) / 100 end

-- A button that needs a second click within a few seconds: for the
-- ones that throw settings away.
local function Careful(label, width, action)
    local armedUntil = 0
    return { label = label, width = width, onClick = function(self)
        local now = GetTime()
        if now > armedUntil then
            armedUntil = now + 4
            Say(label .. ": click again to confirm.")
            return
        end
        armedUntil = 0
        action()
    end }
end

-- the easings the motion layer knows ("Steady" is the old straight line)
local function EasingItems()
    local list = ns.Motion and ns.Motion.EASINGS or { { id = "linear", label = "Steady" } }
    local items = {}
    for _, e in ipairs(list) do items[#items + 1] = { text = e.label, value = e.id } end
    return items
end

-- ============================================================
-- THE PREVIEW
-- ============================================================
-- Sample lines flowing through the real engine (SCT_Display) on the
-- dock's canvas: the events below go through the Events tab's own rules
-- (on/off, area, colour, never-shown list) and its text builder (names,
-- initials, digits, partials, merges), the alerts through the Alerts
-- tab's. A feeder sends the next one every so often, only while the
-- canvas is on screen (an OnUpdate on a child of the canvas).
local FEED = {
    { ev = "out_hit",   f = { amount = 523 } },
    { ev = "in_hit",    f = { amount = 388 } },
    { ev = "out_spell", f = { amount = 1234, spell = "Bloodthirst", icon = 136012 } },
    { ev = "in_heal",   f = { amount = 1512, spell = "Greater Heal", icon = 135913 } },
    { ev = "out_spell", f = { amount = 4821, spell = "Bloodthirst", crit = true, icon = 136012 } },
    { ev = "in_miss",   f = { miss = "Dodge" } },
    { ev = "n_combat_in", f = {} },
    { ev = "out_spell", f = { amount = 400, spell = "Whirlwind", count = 4, icon = 132369 } },
    { ev = "in_spell",  f = { amount = 2210, spell = "Shadow Bolt", partial = "(120 resisted)", icon = 136197 } },
    { ev = "out_miss",  f = { miss = "Parry", spell = "Heroic Strike", icon = 132282 } },
    { alert = "lowHealth", amount = 1240 },
    { ev = "out_hit",   f = { amount = 12345, crit = true } },
    { ev = "n_kb",      f = { name = "Defias Pillager" } },
    { ev = "in_hot",    f = { amount = 310, spell = "Renew", icon = 135953 } },
    { aura = 1 },
    { ev = "n_combat_out", f = {} },
}
S.PREVIEW_FEED = FEED
local FEED_EVERY = 0.4
local BURST = 3

-- the next sample line that lands in `only` (any area when nil)
local function NextLine(st, only)
    for _ = 1, #FEED do
        st.idx = (st.idx or 0) % #FEED + 1
        local s = FEED[st.idx]
        local area, text, o
        -- Forever (Core_Flavor): only what you take shows there - your own
        -- hits and killing blows are only in the combat log it does not
        -- give addons - so the sample has none of them either
        if s.ev and S.FOREVER and (s.ev:find("^out_") or s.ev == "n_kb") then
            -- (skipped)
        elseif s.ev and S.EventLine then
            area, text, o = S.EventLine(s.ev, s.f)
        elseif s.alert and S.Alerts and S.Alerts.Line then
            if S.AlertOn(s.alert) then area, text, o = S.Alerts.Line(s.alert, s.amount) end
        elseif s.aura and S.Alerts and S.Alerts.AuraLine then
            local al = S.AuraAlerts()[s.aura]
            if type(al) == "table" and al.on ~= false then area, text, o = S.Alerts.AuraLine(al) end
        end
        if area and (only == nil or area == only) then return area, text, o end
    end
    -- nothing is sent there: the test lines, so the area still shows its look
    if only then
        st.tidx = (st.tidx or 0) % #S.TEST_LINES + 1
        local t = S.TEST_LINES[st.tidx]
        return only, t[1], t[2]
    end
end

local function Outline(st, key)
    local o = st.outlines[key]
    if o then return o end
    o = CreateFrame("Frame", nil, st.box)
    o.fill = o:CreateTexture(nil, "BACKGROUND")
    o.fill._zui_own = true
    o.fill:SetAllPoints()
    if UI.Border then UI.Border(o, "ui", "border") end
    o.label = UI.Font(o, F.SMALL, { cat = "text", key = "gray" })
    o.label:SetPoint("BOTTOMLEFT", o, "TOPLEFT", 0, 2)
    -- the pick hook: a click on an area's box opens its lines' layout
    if ns.TagElement then ns.TagElement(o, "sct.area." .. tostring(key)) end
    st.outlines[key] = o
    return o
end

-- Where the areas go in the box, at their real size: one area in the
-- middle, or every area exactly where it sits on screen around your
-- character (the dot in the middle). The canvas is the areas with room
-- for lines that run past their box, and the labels; the preview strip
-- shows it at the real size, or scaled down to fit.
local ROOM_X, ROOM_Y = 100, 34
local function PlaceAll(canvas, P, st, only)
    local c = S.Cfg()
    local cw, ch
    if only then
        local a = S.Area(only) or {}
        cw = (tonumber(a.w) or 40) + 2 * ROOM_X
        ch = (tonumber(a.h) or 75) + ROOM_Y
        st.layout = { single = only, cx = 0, cy = 0 }
    else
        -- every shown area side by side, left to right in their order on
        -- screen, each at its real size with room for its lines. At their
        -- screen spots the canvas was the whole screen and the strip drew
        -- it at a fifth of its size (Zac 2026-11-03: "so small i cant see
        -- it"); one area on its own still shows where it sits.
        local list = {}
        for _, e in ipairs(S.Areas()) do
            if e.area.on ~= false then list[#list + 1] = e end
        end
        table.sort(list, function(p, q)
            local px, qx = tonumber(p.area.x) or 0, tonumber(q.area.x) or 0
            if px ~= qx then return px < qx end
            return tostring(p.key) < tostring(q.key)
        end)
        local pos, cursor, hmax = {}, 0, 40
        for _, e in ipairs(list) do
            local w, h = tonumber(e.area.w) or 40, tonumber(e.area.h) or 40
            pos[e.key] = { x = cursor + ROOM_X, w = w, h = h }
            cursor = cursor + w + 2 * ROOM_X
            if h > hmax then hmax = h end
        end
        cw, ch = math.max(120, cursor), hmax + ROOM_Y
        for _, q in pairs(pos) do q.x = q.x - cw / 2 end
        st.layout = { cx = 0, cy = 0, all = true, pos = pos, hmax = hmax }
    end
    st.box:SetScale(1)
    st.box:SetSize(cw, ch)
    if P.Resize then P.Resize(cw, ch) end
    st.engine:Rebuild()
    local accent = ns.GetColor and ns.GetColor("ui", "accent") or { r = 1, g = 0.82, b = 0 }
    for key, ast in pairs(st.engine.areas) do
        local a = c.areas[key]
        local want = type(a) == "table" and (only == key or (only == nil and a.on ~= false))
        local o = Outline(st, key)
        if want then
            ast.frame:Show()
            o:ClearAllPoints()
            o:SetAllPoints(ast.frame)
            o.fill:SetColorTexture(accent.r, accent.g, accent.b, (a.on == false) and 0.04 or 0.10)
            o.label:SetText(a.name or key)
            o:Show()
        else
            ast.frame:Hide()
            o:Hide()
        end
    end
    for key, o in pairs(st.outlines) do
        if not st.engine.areas[key] then o:Hide() end
    end
    -- where your character stands, among every area
    st.you:ClearAllPoints()
    st.you:SetPoint("CENTER", st.box, "CENTER", -st.layout.cx, -st.layout.cy)
    st.you:SetShown((st.layout.all and not st.layout.pos) and true or false)
end

-- Builds the sample flow. fixed: the canvas always shows the area being
-- edited (the Areas tab); otherwise the mode picks (all, or one area).
local function FlowPreview(fixed)
    local function Only(P)
        if fixed then return view.area end
        local m = P.mode or "all"
        if m == "all" or m == "plates" then return nil end
        return m
    end

    local function Burst(P, n)
        local st = P.store
        if st.mode == "plates" then
            local PT = S.PlateText
            for _ = 1, n do
                st.pidx = (st.pidx or 0) % #PT.SAMPLES + 1
                PT.SampleHit(st.pidx, function(text, size, r, g, b, crit, icon)
                    st.cols:Add(st.holder, true, text, size, r, g, b, crit, icon)
                end)
            end
            return
        end
        local only = Only(P)
        for _ = 1, n do
            local area, text, o = NextLine(st, only)
            if area then st.engine:Display(area, text, o) end
        end
    end

    local function Build(canvas, P)
        local st = P.store
        st.outlines = {}
        st.box = CreateFrame("Frame", nil, canvas)
        st.box:SetPoint("CENTER", canvas, "CENTER", 0, 0)
        st.box:SetSize(canvas:GetWidth() or 300, canvas:GetHeight() or 200)
        st.engine = S.NewEngine(st.box, { preview = true, place = function(f, key, a)
            local lay = st.layout or { cx = 0, cy = 0 }
            local w, h = tonumber(a.w) or 40, tonumber(a.h) or 40
            if lay.single then
                f:SetPoint("BOTTOMLEFT", st.box, "CENTER", -w / 2, -h / 2 - ROOM_Y / 2 + 6)
            elseif lay.pos and lay.pos[key] then
                -- side by side, bottoms lined up (the labels' room on top)
                local q = lay.pos[key]
                f:SetPoint("BOTTOMLEFT", st.box, "CENTER", q.x, -(lay.hmax or h) / 2 - ROOM_Y / 2 + 6)
            else
                f:SetPoint("BOTTOMLEFT", st.box, "CENTER",
                    (tonumber(a.x) or 0) - lay.cx, (tonumber(a.y) or 0) - lay.cy)
            end
        end })
        -- where your character stands (the middle of the screen)
        st.you = st.box:CreateTexture(nil, "ARTWORK")
        st.you._zui_own = true
        st.you:SetSize(10, 10)
        st.you:SetColorTexture(1, 1, 1, 0.5)

        -- a nameplate, for your damage on the plate
        local plate = CreateFrame("Frame", nil, canvas)
        plate:SetSize(110, 10)
        plate:SetPoint("CENTER", canvas, "CENTER", -40, -26)
        local bar = CreateFrame("StatusBar", nil, plate)
        bar:SetAllPoints()
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.68)
        if UI.Border then UI.Border(bar, "ui", "border") end
        local name = UI.Font(plate, F.SMALL, { text = "Defias Pillager", cat = "text", key = "normal" })
        name:SetPoint("BOTTOM", plate, "TOP", 0, 3)
        local holder = CreateFrame("Frame", nil, plate)
        holder:SetAllPoints(plate)
        holder.nums, holder.anchor = {}, bar
        holder.ax, holder.ay = 110 / 2 + 8, 10 / 2 + 7
        st.plate, st.bar, st.holder = plate, bar, holder
        st.cols = S.PlateText and S.PlateText.NewColumns(canvas, true)

        st.note = UI.Font(canvas, F.SMALL, { cat = "text", key = "orange", justify = "CENTER" })
        st.note:SetPoint("BOTTOM", canvas, "BOTTOM", 0, 2)

        -- the feeder: the next sample every so often, while on screen
        local feed = CreateFrame("Frame", nil, canvas)
        feed.t = 0
        feed:SetScript("OnUpdate", function(self, elapsed)
            self.t = self.t + elapsed
            local every = FEED_EVERY / math.max(0.3, (tonumber(S.Cfg().speed) or 100) / 100)
            if self.t >= every then
                self.t = 0
                Burst(P, 1)
            end
        end)
        st.feed = feed
    end

    local function Restart(canvas, P)
        local st = P.store
        st.engine:ClearAll()
        if st.cols then st.cols:DropHolder(st.holder) end
        st.feed.t = 0
        Burst(P, BURST)
    end

    local function Update(canvas, P)
        local st = P.store
        local c = S.Cfg()
        local mode = fixed and "area" or (P.mode or "all")
        local plates = mode == "plates" and st.cols ~= nil
        st.mode = plates and "plates" or mode
        st.box:SetShown(not plates)
        st.plate:SetShown(plates)
        local note
        if plates then
            -- the plate low in a short canvas, the numbers rising over it
            if P.Resize then P.Resize(280, 80) end
            local tex = ns.ResolveBarTexture and ns.ResolveBarTexture(nil) or ns.FLAT
            st.bar:SetStatusBarTexture(tex)
            local red = ns.GetColor and ns.GetColor("text", "red") or { r = 0.8, g = 0.2, b = 0.2 }
            st.bar:SetStatusBarColor(red.r, red.g, red.b, 1)
            if not S.PlateText.Cfg().enabled then
                note = "Nameplate numbers are off (General tab)."
            end
        else
            local only = Only(P)
            if fixed and not (only and S.Area(only)) then only = "notification" end
            PlaceAll(canvas, P, st, only)
            if c.enabled == false then
                note = "Scrolling text is off (General tab)."
            elseif only and S.Area(only) and S.Area(only).on == false then
                note = "This area is off."
            end
        end
        if not note and not S.MotionOn() then note = "Animations are off: lines appear and go at once." end
        st.note:SetText(note or "")
        st.note:SetShown(note ~= nil)
        Restart(canvas, P)
    end

    return Build, Update, Restart
end

local textBuild, textUpdate, textReplay = FlowPreview(false)
local areaBuild, areaUpdate, areaReplay = FlowPreview(true)

local function TextPreview(L)
    if not L.Preview then return end
    L:Preview({
        key = "sbt.text",
        title = "Scrolling text",
        width = 560, height = 110,
        modes = (function()
            local m = { { id = "all", label = "All" }, { id = "incoming", label = "Incoming" } }
            -- (Forever shows only what you take, and has no nameplate
            -- numbers: Core_Flavor)
            if not S.FOREVER then m[#m + 1] = { id = "outgoing", label = "Outgoing" } end
            m[#m + 1] = { id = "notification", label = "Notices" }
            if S.PlateText then m[#m + 1] = { id = "plates", label = "Nameplate" } end
            return m
        end)(),
        modesLabel = "Show",
        build = textBuild, update = textUpdate, replay = textReplay,
    })
end

local function AreaPreview(L)
    if not L.Preview then return end
    local a = view.area and S.Area(view.area)
    local w = a and (tonumber(a.w) or 40) or 40
    local h = a and (tonumber(a.h) or 75) or 75
    L:Preview({
        key = "sbt.area",
        title = "Area: " .. (a and a.name or "?"),
        width = w + 2 * ROOM_X, height = h + ROOM_Y,
        build = areaBuild, update = areaUpdate, replay = areaReplay,
    })
end

-- ============================================================
-- TAB: GENERAL
-- ============================================================
local function Tab_general(L)
    local c = Cfg()
    TextPreview(L)

    L:Card("Scrolling text")
    W.Check(L, "Show scrolling combat text", S.IsOn(), function(v)
        S.SetOn(v)
        if S.ArmEvents then S.ArmEvents() end
        W.Refresh()
    end, "Hits and heals you take drift out of a box left of your character, the ones you deal "
        .. "out of one on the right, and notices stack above. Drag the boxes on the Areas tab.")
    if S.FOREVER then
        L:Desc("WoW Classic Forever has no combat log for addons: hits and heals you take still show, "
            .. "your own outgoing numbers do not.")
    end
    W.Buttons(L, {
        { label = "Show a test", width = 110, onClick = function() S.TestAll() end },
    })
    W.Check(L, "Blizzard's damage numbers over what you hit", S.BlizzardDamageOn(), function(v)
        S.SetBlizzardDamage(v)
    end, "The game's own numbers. Off is usual with this on, so nothing shows twice.")
    W.Check(L, "Blizzard's healing numbers", S.BlizzardHealingOn(), function(v)
        S.SetBlizzardHealing(v)
    end)
    L:EndCard()

    L:Card("What a line shows")
    W.Check(L, "The ability's icon", c.icons ~= false, function(v) Cfg().icons = v end)
    W.Check(L, "The ability's name", c.names and true or false, function(v) Cfg().names = v end)
    W.Check(L, "Names as initials (Heroic Strike: HS)", c.shortNames ~= false, function(v) Cfg().shortNames = v end)
    W.Check(L, "Thousands with a comma (12,345)", c.groupDigits ~= false, function(v) Cfg().groupDigits = v end)
    W.Check(L, "What was resisted, blocked or absorbed", c.partials ~= false, function(v) Cfg().partials = v end)
    W.Check(L, "One line for an ability that hits several at once", c.merge ~= false, function(v) Cfg().merge = v end,
        "Whirlwind on four mobs is one number with x4 after it.")
    W.Check(L, "Crits pop in place instead of moving", c.stickyCrits and true or false, function(v) Cfg().stickyCrits = v end,
        "How they pop is on the Animation tab.")
    L:EndCard()

    L:Card("Small numbers")
    local mins = W.Host(L, 40)
    SliderAt(mins, 0, 0, { label = "Hide hits under", min = 0, max = 2000, step = 10, width = 200,
        value = tonumber(c.damageMin) or 0, set = function(v) Cfg().damageMin = v end })
    SliderAt(mins, 230, 0, { label = "Hide heals under", min = 0, max = 3000, step = 10, width = 200,
        value = tonumber(c.healMin) or 0, set = function(v) Cfg().healMin = v end })
    W.Check(L, "Count overhealing in a heal", c.overheal and true or false, function(v) Cfg().overheal = v end,
        "Off: a heal shows only the part that landed.")
    L:EndCard()

    local PT = S.PlateText
    if PT then
        local pc = PT.Cfg()
        L:Card("Your damage on the nameplate")
        W.Check(L, "Show your hits on the mob's nameplate", pc.enabled and true or false, function(v)
            PT.Cfg().enabled = v
            W.Refresh()
        end, "Instead of the Outgoing area, for any mob whose nameplate is up. Kept clear of the "
            .. "ability row over the target's health bar. Its font and colours are on the Text tab, "
            .. "how it moves on the Animation tab.")
        if pc.enabled then
            W.Check(L, "Other mobs too (a size down)", pc.others ~= false, function(v) PT.Cfg().others = v end)
            W.Check(L, "Dodge, Parry, Miss", pc.misses ~= false, function(v) PT.Cfg().misses = v end)
            W.Check(L, "Damage over time", pc.dots ~= false, function(v) PT.Cfg().dots = v end)
            W.Check(L, "Icons", pc.icons ~= false, function(v) PT.Cfg().icons = v end)
            -- where the icon sits round the number (anchors.icon; nothing
            -- saved = in front of it, as always)
            local ig, is = ns.CustomAccess(PT.Cfg, "anchors", "icon")
            UI.FrameElement(L, { key = "sct.plateIcon", label = "Icon beside the number",
                anchorGet = ig, anchorSet = is,
                anchorDefaults = { point = "RIGHT", relPoint = "LEFT", x = -2, y = 0 },
                defaultTargetLabel = "The number", anchorMin = -40, anchorMax = 40 })
            local prow = W.Host(L, 40)
            SliderAt(prow, 0, 0, { label = "Numbers at once", min = 1, max = 8, value = tonumber(pc.lines) or 4,
                set = function(v) PT.Cfg().lines = v end })
            W.Buttons(L, { { label = "Test on target", width = 120, onClick = function()
                if not PT.Test() then Say("Target something with a nameplate showing first.") end
            end } })
        end
        L:EndCard()
    end

    L:Card("Never shown")
    L:Desc("Abilities whose numbers never show, by name.")
    local names = S.SortedKeys(c.hide)
    for _, name in ipairs(names) do
        local r = W.Host(L, 22)
        W.Label(r, name):SetPoint("LEFT", r, "LEFT", 0, 0)
        local b = UI.Button(r, "Remove", { width = 70, onClick = function()
            Cfg().hide[name] = nil
            Changed("sbt.hide")
            W.Refresh()
        end })
        b:SetPoint("LEFT", r, "LEFT", 260, 0)
    end
    local add = W.Host(L, M.EDIT_H + 6)
    local box = W.Put(add, UI.EditBox(add, { width = 250, hint = "Ability name", clear = false }), 0, 0)
    local btn = UI.Button(add, "Add", { width = 60, onClick = function()
        local t = (box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t == "" then return end
        Cfg().hide[t] = true
        Changed("sbt.hide")
        W.Refresh()
    end })
    btn:SetPoint("TOPLEFT", add, "TOPLEFT", 260, 0)
    L:EndCard()
end

-- ============================================================
-- TAB: AREAS
-- ============================================================
local DIRS = {
    horizontal = { { value = "left", text = "Left" }, { value = "right", text = "Right" }, { value = "alt", text = "Both, in turn" } },
    arc = { { value = "left", text = "Out to the left" }, { value = "right", text = "Out to the right" }, { value = "alt", text = "Both, in turn" } },
}
local GROWS = { { value = "up", text = "Upward" }, { value = "down", text = "Downward" } }
local ALIGNS = { { value = "LEFT", text = "Left" }, { value = "CENTER", text = "Middle" }, { value = "RIGHT", text = "Right" } }
local SIDES = { { value = "LEFT", text = "Icon on the left" }, { value = "RIGHT", text = "Icon on the right" } }

local function Tab_areas(L)
    local list = S.Areas()
    if not view.area or not S.Area(view.area) then view.area = list[1] and list[1].key end
    AreaPreview(L)

    L:Card("Scroll areas")
    W.Check(L, "Show the areas on screen to drag them", S.MoversShown and S.MoversShown() or false, function(v)
        if S.ShowMovers then S.ShowMovers(v) end
    end, "Click a box to edit it here. They are in Edit Mode too.")
    local pick = W.Host(L, 44)
    W.Put(pick, W.Dropdown(pick, { label = "Area", width = 200, items = AreaItems,
        get = function() return view.area end,
        set = function(v)
            view.area = v
            if S.RefreshMovers then S.RefreshMovers() end
            W.Refresh()
        end }), 0, 0)
    local b = UI.Button(pick, "Test all", { width = 90, onClick = function() S.TestAll() end })
    b:SetPoint("TOPLEFT", pick, "TOPLEFT", 216, -14)
    local add = W.Host(L, M.EDIT_H + 6)
    local box = W.Put(add, UI.EditBox(add, { width = 200, hint = "New area's name", clear = false }), 0, 0)
    local addBtn = UI.Button(add, "Add area", { width = 90, onClick = function()
        local key, why = S.AddArea(box:GetText())
        if not key then Say(why) return end
        view.area = key
        Changed("sbt.area")
        W.Refresh()
    end })
    addBtn:SetPoint("TOPLEFT", add, "TOPLEFT", 216, 0)
    L:EndCard()

    local key = view.area
    local a = key and S.Area(key)
    if not a then return end
    local c = Cfg()
    local function Changed_() S.Rebuild() end

    L:Card("Editing: " .. (a.name or key))
    W.Check(L, "Show text in this area", a.on ~= false, function(v) a.on = v; Changed_() end)
    if not S.IsBuiltInArea(key) then
        local nr = W.Host(L, 40)
        W.Put(nr, W.Edit(nr, { label = "Name", width = 200, text = a.name or "",
            set = function(t) if t ~= "" then a.name = t end end }), 0, 0)
    end
    local r1 = W.Host(L, 44)
    W.Put(r1, W.Dropdown(r1, { label = "Movement", width = 150, items = S.STYLES,
        get = function() return a.style end,
        set = function(v) a.style = v; Changed_(); W.Refresh() end }), 0, 0)
    if DIRS[a.style] then
        W.Put(r1, W.Dropdown(r1, { label = "Direction", width = 150, items = DIRS[a.style],
            get = function() return a.dir end,
            set = function(v) a.dir = v; Changed_() end }), 166, 0)
    end
    if a.style == "horizontal" or a.style == "static" then
        W.Put(r1, W.Dropdown(r1, { label = "New lines go", width = 150, items = GROWS,
            get = function() return a.grow or "up" end,
            set = function(v) a.grow = v; Changed_() end }), 332, 0)
    end
    local r2 = W.Host(L, 44)
    W.Put(r2, W.Dropdown(r2, { label = "Lines start", width = 150, items = ALIGNS,
        get = function() return a.align or "CENTER" end,
        set = function(v) a.align = v; Changed_() end }), 0, 0)
    W.Put(r2, W.Dropdown(r2, { label = "Icons", width = 150, items = SIDES,
        get = function() return a.iconSide or "LEFT" end,
        set = function(v) a.iconSide = v; Changed_() end }), 166, 0)
    local r6 = W.Host(L, 40)
    SliderAt(r6, 0, 0, { label = "Opacity", min = 10, max = 100, step = 5, value = tonumber(a.alpha) or 100,
        format = Pct, set = function(v) a.alpha = v end })
    SliderAt(r6, 170, 0, { label = "Crit opacity", min = 10, max = 100, step = 5, value = tonumber(a.critAlpha) or 100,
        format = Pct, set = function(v) a.critAlpha = v end })
    -- 0 means "the speed on the Animation tab"
    SliderAt(r6, 340, 0, { label = "Speed (0: all areas')", min = 0, max = 300, step = 5, value = tonumber(a.speed) or 0,
        format = function(v) return v > 0 and (v .. "%") or "Same" end,
        set = function(v) a.speed = (v > 0) and v or nil end })
    L:EndCard()

    L:Card("Font in this area")
    L:Desc("Starts as the font on the Text tab. Change anything here and this area keeps its own.")
    local fp = Picker("FontPicker", L.current, {
        defaultLabel = "Same as all areas",
        defaults = { size = tonumber(c.size) or 10, outline = S.OutlineId(c.outline) or "outline",
                     shadow = c.shadow ~= false, shadowX = tonumber(c.shadowX) or 1, shadowY = tonumber(c.shadowY) or -1 },
        minSize = 6, maxSize = 32, sample = "-1,234  4,821  Dodge",
        get = function()
            local shadow = a.shadow
            if shadow ~= nil then shadow = shadow and true or false end
            return { face = a.font or nil, size = tonumber(a.size), outline = S.OutlineId(a.outline), shadow = shadow }
        end,
        set = function(spec)
            a.font = spec.face or nil
            a.size = tonumber(spec.size)
            a.outline = (spec.outline ~= nil) and S.Flags(spec.outline) or nil
            if spec.shadow ~= nil then a.shadow = spec.shadow and true or false else a.shadow = nil end
            if spec.shadowX ~= nil then Cfg().shadowX = spec.shadowX end
            if spec.shadowY ~= nil then Cfg().shadowY = spec.shadowY end
        end })
    Add(L, fp, 4)
    local r5 = W.Host(L, 40)
    -- 0 on this means "the crit size set on the Text tab"
    SliderAt(r5, 0, 0, { label = "Crit size (0: all areas')", min = 0, max = 40, value = tonumber(a.critSize) or 0,
        format = function(v) return v > 0 and Px(v) or "Same" end,
        set = function(v) a.critSize = (v > 0) and v or nil end })
    W.Buttons(L, { { label = "Same font as all areas", width = 170, onClick = function()
        a.font, a.size, a.critSize, a.outline, a.shadow = nil, nil, nil, nil, nil
        Changed("sbt.areafont")
        W.Refresh()
    end } })
    L:EndCard()

    L:Card("Where it sits")
    local r3 = W.Host(L, 40)
    W.Put(r3, W.Edit(r3, { label = "Across (from the middle)", width = 150, text = a.x or 0, number = true,
        set = function(n) a.x = math.floor(n + 0.5); Changed_() end }), 0, 0)
    W.Put(r3, W.Edit(r3, { label = "Up (from the middle)", width = 150, text = a.y or 0, number = true,
        set = function(n) a.y = math.floor(n + 0.5); Changed_() end }), 166, 0)
    local r4 = W.Host(L, 40)
    SliderAt(r4, 0, 0, { label = "Width", min = 10, max = 600, step = 5, value = tonumber(a.w) or 40,
        format = Px, set = function(v) a.w = v; Changed_() end })
    SliderAt(r4, 170, 0, { label = "Height", min = 10, max = 500, step = 5, value = tonumber(a.h) or 75,
        format = Px, set = function(v) a.h = v; Changed_() end })
    local defs = {
        { label = "Test", width = 70, onClick = function() S.TestArea(key) end },
        { label = "Reset position", width = 120, onClick = function()
            S.ResetAreaPosition(key)
            Changed("sbt.area")
            W.Refresh()
        end },
    }
    if not S.IsBuiltInArea(key) then
        defs[#defs + 1] = Careful("Delete area", 110, function()
            S.DeleteArea(key)
            view.area = nil
            Changed("sbt.area")
            W.Refresh()
        end)
    end
    W.Buttons(L, defs)
    L:EndCard()

    -- the spell icon's spot round the number (a.anchors.icon, ZacUI's
    -- anchor shape; the Icons side above is where it starts)
    L:Card("Icon beside the numbers")
    local ig, is = ns.CustomAccess(a, "anchors", "icon", Changed_)
    UI.FrameElement(L, { key = "sct.icon", anchorGet = ig, anchorSet = is,
        anchorDefaults = function()
            if a.iconSide == "LEFT" then return { point = "BOTTOMRIGHT", relPoint = "BOTTOMLEFT", x = -3, y = 0 } end
            return { point = "BOTTOMLEFT", relPoint = "BOTTOMRIGHT", x = 3, y = 0 }
        end,
        anchorMin = -40, anchorMax = 40 })
    L:Desc("Any corner of the number: above it, under it, either side. Reset goes back to the side picked under Icons.")
    L:EndCard()

    -- the area's lines on ZacUI's layout shape (a.layout): which way rows
    -- are added, the gaps, how many at once; New lines go above is the default
    if UI.LayoutPicker and S.AreaLayoutDefaults then
        L:Card("Lines in this area")
        local lg, ls = ns.CustomAccess(a, "layout", nil, Changed_)
        local lp = UI.LayoutPicker(L.current, { width = UI.CardInnerWidth(L), get = lg, set = ls,
            fields = { grow = true, spacingX = true, spacingY = true, max = true },
            grows = { "UP", "DOWN" }, maxItems = 30,
            defaults = function() return S.AreaLayoutDefaults(a) end })
        Add(L, lp, 6)
        if ns.CustomPick then ns.CustomPick.RegisterGroup("sct.layout", lp) end
        L:Desc("Grows: where a sliding or stacked area adds its next row. Gap down: between stacked "
            .. "lines. Gap across: between two lines sliding on one row. Most shown: lines at once.")
        L:EndCard()
    end
end

-- ============================================================
-- TAB: EVENTS
-- ============================================================
local function Tab_events(L)
    TextPreview(L)
    L:Card("Events")
    L:Desc("Every kind of line, where it goes and in what colour. Untick to never show it.")
    W.Buttons(L, { Careful("Reset all events", 140, function()
        Cfg().events = {}
        Changed("sbt.events")
        W.Refresh()
    end) })
    L:EndCard()

    for _, cat in ipairs(S.EVENT_CATS) do
        L:Card(cat.label)
        for _, def in ipairs(S.EVENTS) do
            if def.cat == cat.key then
                local key = def.key
                -- (the label wraps before the area column; the row grows to fit)
                local cb = UI.Checkbox(L.current, def.label, S.EventOn(key), function(v)
                    S.SetEvent(key, "off", not v)
                end, { width = 244 })
                local row = W.Host(L, math.max(26, (cb:GetHeight() or 14) + 12))
                W.Put(row, cb, 0, -3)
                local dd = W.Dropdown(row, { width = 120, items = AreaItems,
                    get = function() return S.EventArea(key) end,
                    set = function(v)
                        S.SetEvent(key, "area", (v ~= def.area) and v or nil)
                    end })
                W.Put(row, dd, 250, 0)
                local sw = W.Swatch(row, function() return S.EventColor(key) end,
                    function(r, g, b) S.SetEvent(key, "color", r, g, b) end,
                    { tooltip = "The colour of this line." })
                W.Put(row, sw, 378, -4)
                local t = UI.Button(row, "Test", { width = 50, onClick = function() S.TestEvent(key) end })
                t:SetPoint("TOPLEFT", row, "TOPLEFT", 416, 0)
            end
        end
        L:EndCard()
    end

    -- crits and pops over every event's own colour (sct.states, ZacUI's
    -- state shape: text colour, opacity); nothing set = as they are
    if UI.StateEditor and S.LINE_STATES then
        L:Card("Crits and pops")
        local sg, ss = ns.CustomAccess(Cfg, "states", nil)
        view.stateMem = view.stateMem or {}
        local se = UI.StateEditor(L.current, { width = UI.CardInnerWidth(L), states = S.LINE_STATES,
            get = sg, set = ss, fields = { textColor = true, alpha = true }, remember = view.stateMem,
            defaults = { crit = {}, sticky = {} } })
        Add(L, se, 6)
        if ns.CustomPick then ns.CustomPick.RegisterGroup("sct.states", se) end
        L:Desc("A colour here wins over the event's own for that kind of line; the opacity over the area's.")
        L:EndCard()
    end
end

-- ============================================================
-- TAB: ALERTS
-- ============================================================
local UNITS = { { value = "target", text = "On your target" }, { value = "player", text = "On you" } }

local function Tab_alerts(L)
    local c = Cfg()
    TextPreview(L)
    L:Card("Warnings")
    W.Check(L, "Play alert sounds", c.sounds ~= false, function(v) Cfg().sounds = v end)
    for _, def in ipairs(S.ALERTS) do
        local key = def.key
        if not def.class or def.class == select(2, UnitClass("player")) then
            L:Gap(4)
            local cb = UI.Checkbox(L.current, def.label, S.AlertOn(key), function(v)
                S.SetAlert(key, "off", not v)
            end, { width = 370 })
            local head = W.Host(L, math.max(22, (cb:GetHeight() or 14) + 8))
            W.Put(head, cb, 0, -2)
            local sw = W.Swatch(head, function()
                return S.AlertValue(key, "r"), S.AlertValue(key, "g"), S.AlertValue(key, "b")
            end, function(r, g, b) S.SetAlert(key, "color", r, g, b) end)
            W.Put(head, sw, 378, -3)
            local t = UI.Button(head, "Test", { width = 50, onClick = function() S.TestAlert(key) end })
            t:SetPoint("TOPLEFT", head, "TOPLEFT", 416, 0)
            local row = W.Host(L, 44)
            local x = 22
            if def.pct then
                SliderAt(row, x, -4, { label = "Below", min = 5, max = 90, step = 5, width = 120,
                    value = tonumber(S.AlertValue(key, "pct")) or def.pct, format = Pct,
                    set = function(v) S.SetAlert(key, "pct", v) end })
                x = x + 136
            end
            W.Put(row, W.Dropdown(row, { label = "Area", width = 120, items = AreaItems,
                get = function() return S.AlertValue(key, "area") end,
                set = function(v) S.SetAlert(key, "area", v ~= "notification" and v or nil) end }), x, 0)
            W.Put(row, W.Dropdown(row, { label = "Sound", width = 150, items = SoundItems,
                get = function() return S.AlertValue(key, "sound") or false end,
                set = function(v)
                    S.SetAlert(key, "sound", v or nil)
                    if v then S.PlaySound(v) end
                end }), x + 136, 0)
        end
    end
    L:EndCard()

    -- one sound per line (sct.soundSpecs.<event or alert>, ZacUI's sound
    -- shape: sound, channel, not again within); the line's own sound is
    -- the default
    if UI.SoundSpecPicker then
        L:Card("Sound for each line")
        local function Items()
            local out = {}
            for _, d in ipairs(S.ALERTS) do out[#out + 1] = { text = "Alert: " .. d.label, value = d.key } end
            for _, d in ipairs(S.EVENTS) do out[#out + 1] = { text = d.label, value = d.key } end
            return out
        end
        local function Which()
            local v = view.soundKey
            if v and (S.EVENT_BY_KEY[v] or (S.ALERT_BY_KEY and S.ALERT_BY_KEY[v])) then return v end
            return S.ALERTS[1] and S.ALERTS[1].key or "n_combat_in"
        end
        local which = Which()
        local function Label(v)
            for _, it in ipairs(Items()) do if it.value == v then return it.text end end
            return tostring(v)
        end
        Add(L, UI.Field(L.current, "Line", function(h)
            return UI.Dropdown(h, { width = 260, items = Items,
                selected = function() return Label(Which()) end, selectedValue = Which,
                onSelect = function(v) view.soundKey = v W.Refresh() end })
        end, { width = 260 }), 8)
        local own = S.EVENT_BY_KEY[which] and S.EventSound(which) or S.AlertValue(which, "sound")
        local gg, gs = ns.CustomAccess(Cfg, "soundSpecs", which)
        local sp = UI.SoundSpecPicker(L.current, { width = UI.CardInnerWidth(L), get = gg, set = gs,
            defaults = { sound = own, channel = "Master" } })
        Add(L, sp, 6)
        if ns.CustomPick then ns.CustomPick.RegisterGroup("sct.sound", sp) end
        L:Desc("Only while Play alert sounds is on. Until you pick one, the line plays the sound "
            .. "chosen above (or under Events), if any.")
        L:EndCard()
    end

    L:Card("Your own alerts")
    L:Desc("A line when a buff or debuff goes up on you or your target, by its name.")
    for i, al in ipairs(S.AuraAlerts()) do
        local head = W.Host(L, 22)
        local cb = UI.Checkbox(head, al.name, al.on ~= false, function(v) al.on = v end)
        W.Put(head, cb, 0, -2)
        local sw = W.Swatch(head, function() return al.r or 1, al.g or 1, al.b or 0 end,
            function(r, g, b) al.r, al.g, al.b = r, g, b end)
        W.Put(head, sw, 300, -3)
        local rm = UI.Button(head, "Remove", { width = 70, onClick = function()
            S.RemoveAuraAlert(i)
            Changed("sbt.alerts")
            W.Refresh()
        end })
        rm:SetPoint("TOPLEFT", head, "TOPLEFT", 396, 0)
        local row = W.Host(L, 44)
        W.Put(row, W.Dropdown(row, { label = "Watch", width = 130, items = UNITS,
            get = function() return al.unit or "target" end,
            set = function(v) al.unit = v end }), 22, 0)
        W.Put(row, W.Edit(row, { label = "Text to show", width = 160, text = al.text or al.name,
            set = function(t) al.text = t end }), 166, 0)
        SliderAt(row, 340, -4, { label = "Size", min = 8, max = 40, width = 110, value = tonumber(al.size) or 20,
            format = Px, set = function(v) al.size = v end })
    end
    local add = W.Host(L, M.EDIT_H + 6)
    local box = W.Put(add, UI.EditBox(add, { width = 250, hint = "Buff or debuff name", clear = false }), 0, 0)
    local btn = UI.Button(add, "Add", { width = 60, onClick = function()
        local ok, why = S.AddAuraAlert(box:GetText())
        if not ok then Say(why) return end
        Changed("sbt.alerts")
        W.Refresh()
    end })
    btn:SetPoint("TOPLEFT", add, "TOPLEFT", 260, 0)
    L:EndCard()
end

-- ============================================================
-- TAB: TEXT
-- ============================================================
local function Tab_text(L)
    local c = Cfg()
    TextPreview(L)

    L:Card("Text in every area")
    local fp = Picker("FontPicker", L.current, {
        defaults = { size = 10, outline = "outline", shadow = true, shadowX = 1, shadowY = -1 },
        minSize = 6, maxSize = 32, sample = "-1,234  4,821  Dodge",
        get = function()
            local k = Cfg()
            return { face = k.font or nil, size = tonumber(k.size), outline = S.OutlineId(k.outline),
                     shadow = k.shadow ~= false, shadowX = tonumber(k.shadowX), shadowY = tonumber(k.shadowY) }
        end,
        set = function(spec)
            local k = Cfg()
            local faceChanged = (spec.face or false) ~= (k.font or false)
            k.font = spec.face or false
            if spec.size then k.size = spec.size end
            if spec.outline ~= nil then k.outline = S.Flags(spec.outline) end
            if spec.shadow ~= nil then k.shadow = spec.shadow and true or false end
            if spec.shadowX ~= nil then k.shadowX = spec.shadowX end
            if spec.shadowY ~= nil then k.shadowY = spec.shadowY end
            if faceChanged then S.Rebuild() end
        end })
    Add(L, fp, 4)
    local sizes = W.Host(L, 40)
    SliderAt(sizes, 0, 0, { label = "Crit size", min = 6, max = 40, value = tonumber(c.critSize) or 12,
        format = Px, set = function(v) Cfg().critSize = v end })
    L:Desc("An area can wear a font of its own: Areas tab. Alerts and some notices have their own size.")
    L:EndCard()

    -- how the numbers and ability names read (sct.formats.amount / .name,
    -- ZacUI's text format); "Thousands with a comma" and initials are the defaults
    if UI.TextElement and S.AmountFormatDefaults then
        L:Card("Number and name format")
        local ag, as = ns.CustomAccess(Cfg, "formats", "amount")
        UI.TextElement(L, { key = "sct.amount", label = "Numbers", formatGet = ag, formatSet = as,
            formatDefaults = S.AmountFormatDefaults, formatKinds = { number = true },
            formatTokens = { { token = "value", label = "the number" } },
            formatSample = function() return S.Digits(12345) .. "   " .. S.Digits(523) end })
        local ng, ns_ = ns.CustomAccess(Cfg, "formats", "name")
        UI.TextElement(L, { key = "sct.name", label = "Ability names", formatGet = ng, formatSet = ns_,
            formatDefaults = {}, formatKinds = { name = true },
            formatSample = function() return S.ShortName and S.ShortName("Heroic Strike") or "HS" end })
        L:Desc("Names are shortened to initials first when that is ticked on General.")
        L:EndCard()
    end

    local PT = S.PlateText
    if PT then
        local pc = PT.Cfg()
        L:Card("Your damage on the nameplate")
        local pp = Picker("FontPicker", L.current, {
            defaultLabel = "Same as scrolling text",
            defaults = { size = 13, outline = "outline", shadow = true, shadowX = 1, shadowY = -1 },
            minSize = 8, maxSize = 24, sample = "1.3k  4.1k  Dodge",
            get = function()
                local k = PT.Cfg()
                return { face = k.face, size = tonumber(k.size), outline = S.OutlineId(k.outline),
                         shadow = k.shadow ~= false }
            end,
            set = function(spec)
                local k = PT.Cfg()
                k.face = spec.face
                if spec.size then k.size = spec.size end
                if spec.outline ~= nil then k.outline = S.Flags(spec.outline) end
                if spec.shadow ~= nil then k.shadow = spec.shadow and true or false end
            end })
        Add(L, pp, 4)
        local row = W.Host(L, 40)
        SliderAt(row, 0, 0, { label = "Crit size", min = 100, max = 200, step = 5, value = tonumber(pc.critScale) or 130,
            format = Pct, set = function(v) PT.Cfg().critScale = v end })
        L:Desc("Against an ability hit's size. Swings, misses and damage over time are a size down.")
        L:Gap(4)
        for _, kind in ipairs(PT.KINDS or {}) do
            local cp = W.Swatch(L.current, function() return PT.KindColor(kind.key) end,
                function(r, g, b)
                    local k = PT.Cfg()
                    if type(k.colors) ~= "table" then k.colors = {} end
                    k.colors[kind.key] = { r = r, g = g, b = b }
                end, { label = kind.label })
            L:Row(cp, 22)
        end
        W.Buttons(L, { { label = "Back to the palette's colours", width = 200, onClick = function()
            PT.Cfg().colors = {}
            Changed("sbt.platecolors")
            W.Refresh()
        end } })
        L:EndCard()
    end
end

-- ============================================================
-- TAB: ANIMATION
-- ============================================================
local function Tab_anim(L)
    local c = Cfg()
    TextPreview(L)

    if not S.MotionOn() then
        L:Notice("warn", "Animations are off for all of ZacUI (Appearance > Motion): lines still move "
            .. "through their areas, but appear, pop and fade at once.")
    end

    L:Card("Moving lines")
    local r1 = W.Host(L, 44)
    SliderAt(r1, 0, 0, { label = "Speed", min = 30, max = 300, step = 5, value = tonumber(c.speed) or 100,
        format = Pct, set = function(v) Cfg().speed = v end })
    W.Put(r1, W.Dropdown(r1, { label = "How they travel", width = 170, items = EasingItems,
        get = function() return Cfg().ease or "linear" end,
        set = function(v) Cfg().ease = v end }), 170, 0)
    L:Desc("Speed is how fast every area runs; an area can have its own on the Areas tab.")
    local r2 = W.Host(L, 40)
    SliderAt(r2, 0, 0, { label = "Fade in", min = 0, max = 0.5, step = 0.01, value = tonumber(c.fadeIn) or 0.06,
        format = Secs, set = function(v) Cfg().fadeIn = Round2(v) end })
    SliderAt(r2, 170, 0, { label = "Fade out (moving)", min = 0, max = 60, step = 5, value = tonumber(c.fadeOut) or 20,
        format = Pct, set = function(v) Cfg().fadeOut = v end })
    SliderAt(r2, 340, 0, { label = "Fade out (stacked)", min = 0, max = 60, step = 5, value = tonumber(c.fadeOutStatic) or 25,
        format = Pct, set = function(v) Cfg().fadeOutStatic = v end })
    L:Desc("Fade out is the last part of a line's life it spends fading.")
    local r3 = W.Host(L, 40)
    SliderAt(r3, 0, 0, { label = "Stack slide speed", min = 2, max = 30, value = tonumber(c.stackSpeed) or 14,
        set = function(v) Cfg().stackSpeed = v end })
    L:Desc("How quickly a stack of lines slides along to make room for a new one.")
    L:EndCard()

    L:Card("Lines that pop in place")
    L:Desc("Alerts, your own alerts, and crits when they pop in place.")
    local ap = Picker("AnimationPicker", L.current, {
        label = "How they arrive", styles = { "none", "pop", "fade", "slide" },
        get = function() return Cfg().stickyIn end,
        set = function(spec) Cfg().stickyIn = spec end })
    Add(L, ap, 4)
    local r4 = W.Host(L, 40)
    SliderAt(r4, 0, 0, { label = "Pop starts at", min = 100, max = 250, step = 5, value = tonumber(c.stickyScale) or 160,
        format = Pct, set = function(v) Cfg().stickyScale = v end })
    SliderAt(r4, 170, 0, { label = "Stay for", min = 0.5, max = 5, step = 0.1, value = tonumber(c.stickyHold) or 1.6,
        format = function(v) return string.format("%.1fs", v) end, set = function(v) Cfg().stickyHold = Round2(v) end })
    SliderAt(r4, 340, 0, { label = "Fade out", min = 0, max = 2, step = 0.05, value = tonumber(c.stickyFade) or 0.4,
        format = Secs, set = function(v) Cfg().stickyFade = Round2(v) end })
    L:EndCard()

    local PT = S.PlateText
    if PT then
        local pc = PT.Cfg()
        L:Card("Your damage on the nameplate")
        local r5 = W.Host(L, 40)
        SliderAt(r5, 0, 0, { label = "On screen for", min = 0.5, max = 3, step = 0.05, value = tonumber(pc.life) or 1.1,
            format = Secs, set = function(v) PT.Cfg().life = Round2(v) end })
        SliderAt(r5, 170, 0, { label = "Fade in", min = 0, max = 0.5, step = 0.01, value = tonumber(pc.fadeIn) or 0.08,
            format = Secs, set = function(v) PT.Cfg().fadeIn = Round2(v) end })
        SliderAt(r5, 340, 0, { label = "Fade out", min = 0, max = 1.5, step = 0.05, value = tonumber(pc.fadeOut) or 0.35,
            format = Secs, set = function(v) PT.Cfg().fadeOut = Round2(v) end })
        local r6 = W.Host(L, 40)
        SliderAt(r6, 0, 0, { label = "Drift up", min = 0, max = 60, value = tonumber(pc.rise) or 14,
            format = Px, set = function(v) PT.Cfg().rise = v end })
        SliderAt(r6, 170, 0, { label = "Drift right", min = -30, max = 30, value = tonumber(pc.drift) or 5,
            format = Px, set = function(v) PT.Cfg().drift = v end })
        L:EndCard()
    end

    L:Card("Defaults")
    W.Buttons(L, { { label = "Put the timings back", width = 170, onClick = function()
        local k, D = Cfg(), S.DEFAULTS
        for _, f in ipairs({ "speed", "ease", "fadeIn", "fadeOut", "fadeOutStatic", "stackSpeed",
            "stickyHold", "stickyFade", "stickyScale" }) do
            k[f] = D[f]
        end
        k.stickyIn = S.Copy(D.stickyIn)
        if PT then
            local p, PD = PT.Cfg(), PT.DEFAULTS
            for _, f in ipairs({ "life", "fadeIn", "fadeOut", "rise", "drift" }) do p[f] = PD[f] end
        end
        Changed("sbt.anim")
        W.Refresh()
    end } })
    L:EndCard()
end

-- ============================================================
-- TAB: ADVANCED
-- ============================================================
local function Tab_adv(L)
    TextPreview(L)
    L:Card("Start again")
    L:Desc("Every scrolling text setting back to how ZacUI ships it: areas, events, alerts, "
        .. "fonts, colours and timings.")
    W.Buttons(L, {
        Careful("Restore defaults", 130, function()
            S.ResetAll()
            Say("Scrolling text is back to its defaults.")
            Changed("sbt.reset")
            W.Refresh()
        end),
    })
    L:EndCard()
end

S.tabs.general = Tab_general
S.tabs.events = Tab_events
S.tabs.alerts = Tab_alerts
S.tabs.areas = Tab_areas
S.tabs.text = Tab_text
S.tabs.anim = Tab_anim
S.tabs.adv = Tab_adv

-- ============================================================
-- THE PAGE
-- ============================================================
-- General, then the three things this module is made of (what shows,
-- the warnings, where it goes), then ZacUI's usual Text / Animation /
-- Advanced. The Areas tab keeps its id: its drag boxes go when you
-- leave it.
local TABS = {
    { id = "general", label = "General" },
    { id = "events", label = "Events" },
    { id = "alerts", label = "Alerts" },
    { id = "areas", label = "Areas" },
    { id = "text", label = "Text" },
    { id = "anim", label = "Animation" },
    { id = "adv", label = "Advanced" },
}

-- search words for what the page does not say in so many words
if ns.AddMenuKeywords then
    ns.AddMenuKeywords("sbt", "animation animations fade pop popup bounce easing "
        .. "speed outline shadow opacity preview msbt mik sct parrot layout gap spacing grow "
        .. "most lines states crit format abbreviate short thousands sound channel throttle")
end

-- "Customize this element": a sample line picked in a preview opens how
-- the numbers read (Text), an area's box its lines' layout (Areas)
local function OnPick(el)
    if type(el) ~= "string" then return end
    ZacUIDB.config = ZacUIDB.config or {}
    ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
    local area = el:match("^sct%.area%.(.+)$")
    if area and S.Area(area) then
        view.area = area
        ZacUIDB.config.tabs.sbt = "areas"
    elseif el == "sct.line" then
        ZacUIDB.config.tabs.sbt = "text"
    else
        return
    end
    W.Refresh()
end
S.OnPreviewPick = OnPick

RegisterPage("SBT", function(L)
    L:Header("Scrolling text",
        "Damage, healing and notices scrolling around your character.")
    if ns.CustomPick then
        ns.CustomPick.SetHandler("sbt.text", OnPick)
        ns.CustomPick.SetHandler("sbt.area", OnPick)
    end
    local tabs = {}
    for _, t in ipairs(TABS) do
        tabs[#tabs + 1] = { id = t.id, label = t.label, build = function(layout)
            local fn = S.tabs[t.id]
            if fn then fn(layout) end
        end }
    end
    L:Tabs(tabs)
end)
