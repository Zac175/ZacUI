-- UIF_Pool - settings pages that build again without making new frames.
-- Part of ZacUI; load order is set by the TOC (after every UIF_* file that
-- defines a widget, before the config window).
--
-- WHY. The client never frees a frame. A settings page is built again on
-- every tab switch, toggle, profile change and resize, and every build
-- used to make all its widgets new: the old ones were hidden and dropped,
-- and stayed in memory until /reload. A page with the customization
-- groups on it (a font, a format and a position per text) made a few
-- hundred frames per click, and memory climbed for as long as you
-- browsed.
--
-- HOW. Every widget a live page build asks for (a checkbox, a slider, a
-- card, a font picker, a text's whole group...) goes back to a pool when
-- the page is cleared, and the next build that asks for one of the same
-- shape on the same page gets it back: reparented, put back the way it
-- was built, re-bound and refreshed. No new frames.
--   * The shape is the widget's name, the page, every plain value it was
--     asked with (label, widths, choices, defaults tables), the room its
--     parent has and the font. The current value (a checkbox's tick, a
--     slider's number, an edit box's text, a card's y) is NOT part of it:
--     it is handed to the reused widget instead.
--   * The functions it was asked with (get / set / onChange / items...)
--     are bound through small forwarders that always call the LATEST
--     build's functions, so a reused picker reads and writes exactly what
--     the new build asked for (a profile switch writes the right table).
--   * "Put back the way it was built": the fields the page or the Layout
--     wrote on it afterwards are taken off again (a card's "?" help, a
--     wrapped label's extra height, a dimmed control's flag), anything the
--     page parented to it afterwards is let go, hooks the page added go
--     with the page that added them, and its size, alpha, shown state,
--     mouse and the scripts set on it are as they were.
--   * Same order in, same order out: a page asking for its controls in
--     the same order gets each one back in the same place.
-- Only widgets parented under the live page (the config window's content)
-- are pooled. The search index's unseen builds, the preview dock and
-- anything built at run time are made as they always were.

local _, ns = ...
local UI = ns.UI
local M = UI.M

local Pool = {
    free = {},          -- key -> { widget, ... } (oldest first)
    live = {},          -- what the current page build took, in order
    depth = 0,          -- > 0 while a pooled widget is being built
    scope = nil,        -- the page id of the live build
    root = nil,         -- the frame the live build fills
    off = false,        -- true: everything built new, as before
    stats = { built = 0, reused = 0, released = 0, orphaned = 0 },
}
ns.UIPool = Pool

local type, pairs, ipairs, tostring, pcall, select = type, pairs, ipairs, tostring, pcall, select
local table_concat, table_sort, table_remove = table.concat, table.sort, table.remove
local unpack = unpack

-- The test client keeps its own state in the frame tables; the game keeps
-- it inside the frame. Those keys are not ours to put back.
local NOT_OURS = rawget(_G, "__stubFieldKeys") or {}
-- What the motion driver keeps on a frame while it moves it is its own
-- (a widget handed back is stopped first, see Release).
local MOTION_KEYS = { _zAnim = true, _zFadeSerial = true, _zFadeTo = true, _zFadeWait = true,
    _zMotion = true, _zMotionProtected = true, _zPopBase = true }
-- What the font keeper (Core_Fonts) notes on a string is about the face
-- it wears now, which a change of ZacUI's font moves while it waits here.
local HOUSE_KEYS = { _zHouseFace = true, _zHouseOrig = true }
-- A dimmed widget's reason cover (UIF_Pickers' UI.SetEnabled) has a free
-- list of its own: the pool neither keeps nor puts back the widget's link
-- to one (the cover itself goes back through UI.RecycleWhy, below).
local COVER_KEYS = { _zWhyHit = true }
local function Skip(k) return k == 0 or NOT_OURS[k] or MOTION_KEYS[k] or HOUSE_KEYS[k] or COVER_KEYS[k] or k == "_zPoolSnap" end

local SCRIPTS = { "OnClick", "OnEnter", "OnLeave", "OnShow", "OnHide", "OnValueChanged", "OnTextChanged",
    "OnEnterPressed", "OnEscapePressed", "OnEditFocusGained", "OnEditFocusLost", "OnMouseDown",
    "OnMouseUp", "OnMouseWheel", "OnSizeChanged", "OnUpdate", "OnDragStart", "OnDragStop", "OnReceiveDrag" }

local function IsObj(v) return type(v) == "table" and type(v.GetObjectType) == "function" end
local function IsRegion(o)
    local t = o.GetObjectType and o:GetObjectType()
    return t == "FontString" or t == "Texture" or t == "MaskTexture" or t == "Line"
end

local function Under(f, root)
    local d = 0
    while f and d < 40 do
        if f == root then return true end
        f = f.GetParent and f:GetParent()
        d = d + 1
    end
    return false
end

-- ============================================================
-- SHAPE + FORWARDERS
-- ============================================================
-- functions whose result shapes the widget (an "Anchor to" list)
local EVAL = { targets = true }
-- tables kept by identity (the page owns them and writes into them)
local KEEP = { remember = true }

local function SigOf(v, depth, buf, key)
    local t = type(v)
    if t == "function" then
        if key and EVAL[key] then
            local ok, r = pcall(v)
            if ok then return SigOf(r, depth, buf) end
        end
        buf[#buf + 1] = "f"
    elseif t == "table" then
        if IsObj(v) or (key and KEEP[key]) or depth > 4 then buf[#buf + 1] = "@" .. tostring(v) return end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table_sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        buf[#buf + 1] = "{"
        for _, k in ipairs(keys) do
            buf[#buf + 1] = tostring(k) .. "="
            SigOf(v[k], depth + 1, buf, k)
            buf[#buf + 1] = ";"
        end
        buf[#buf + 1] = "}"
    else
        buf[#buf + 1] = t:sub(1, 1) .. tostring(v)
    end
end

local function Forwarder(live, path)
    local n = #path
    return function(...)
        local v = live.cur
        for i = 1, n do
            if type(v) ~= "table" then return nil end
            v = v[path[i]]
        end
        if type(v) == "function" then return v(...) end
        return nil
    end
end

local function ShadowOf(v, live, path, key)
    local t = type(v)
    if t == "function" then return Forwarder(live, path) end
    if t ~= "table" or IsObj(v) or (key and KEEP[key]) or #path > 6 then return v end
    local o = {}
    for k, x in pairs(v) do
        local p = {}
        for i = 1, #path do p[i] = path[i] end
        p[#p + 1] = k
        o[k] = ShadowOf(x, live, p, k)
    end
    return setmetatable(o, getmetatable(v))
end

local function FontEpoch()
    local f = ZacUIDB and ZacUIDB.font
    if type(f) ~= "table" then return "-" end
    return tostring(f.name) .. "/" .. tostring(f.delta) .. "/" .. tostring(f.outline)
end

-- ============================================================
-- AS BUILT: what a widget looked like the moment it was made
-- ============================================================
-- Hooks the page adds after the widget was built go through one hook per
-- script that calls the page's own list, and the list is emptied when the
-- widget goes back to the pool (the client cannot take a hook off).
local function PooledHookScript(self, script, fn)
    local lists = rawget(self, "_zPH")
    if not lists then return self._zRealHook(self, script, fn) end
    local l = lists[script]
    if not l then
        l = {}
        lists[script] = l
        if not self._zPHI[script] then
            self._zPHI[script] = true
            self._zRealHook(self, script, function(...)
                local cur = rawget(self, "_zPH")
                local list = cur and cur[script]
                if list then
                    for i = 1, #list do list[i](...) end
                end
            end)
            -- (the hook changes what GetScript answers on some clients:
            -- that is the script as built now)
            local snap = rawget(self, "_zPoolSnap")
            if snap and snap.scripts and self.GetScript then
                local ok, cur = pcall(self.GetScript, self, script)
                if ok then snap.scripts[script] = cur or false end
            end
        end
    end
    l[#l + 1] = fn
end

local function Collect(o, out, depth)
    out[#out + 1] = o
    if depth > 8 or IsRegion(o) then return end
    if o.GetRegions then
        for _, r in ipairs({ o:GetRegions() }) do out[#out + 1] = r end
    end
    if o.GetChildren then
        for _, c in ipairs({ o:GetChildren() }) do Collect(c, out, depth + 1) end
    end
end

local function SnapOne(o)
    local s = { fields = {}, arrays = {} }
    -- hooks first, so they are part of the widget as built
    if not IsRegion(o) and o.HookScript and rawget(o, "HookScript") ~= PooledHookScript then
        o._zRealHook = o.HookScript
        o._zPHI = {}
        o._zPH = {}
        o.HookScript = PooledHookScript
    end
    for k, v in pairs(o) do
        if not Skip(k) then
            s.fields[k] = v
            if type(v) == "table" and not IsObj(v) and not getmetatable(v) and #v > 0 and k ~= "_zPH" and k ~= "_zPHI" then
                s.arrays[k] = #v
            end
        end
    end
    s.shown = o.IsShown and o:IsShown() or false
    s.alpha = o.GetAlpha and o:GetAlpha() or 1
    if o.IsMouseEnabled and not IsRegion(o) then s.mouse = o:IsMouseEnabled() and true or false end
    if o.IsEnabled and o.Enable and not IsRegion(o) then
        local ok, e = pcall(o.IsEnabled, o)
        if ok then s.enabled = e and true or false end
    end
    if not IsRegion(o) then
        s.kids, s.regs = {}, {}
        if o.GetChildren then for _, c in ipairs({ o:GetChildren() }) do s.kids[c] = true end end
        if o.GetRegions then for _, r in ipairs({ o:GetRegions() }) do s.regs[r] = true end end
        if o.GetScript then
            s.scripts = {}
            for _, h in ipairs(SCRIPTS) do
                if not o.HasScript or o:HasScript(h) then
                    local ok, fn = pcall(o.GetScript, o, h)
                    if ok then s.scripts[h] = fn or false end
                end
            end
        end
    end
    rawset(o, "_zPoolSnap", s)
end

local function Snapshot(w)
    local all = {}
    Collect(w, all, 0)
    -- parts that hang off the parent but belong to it (a scroll area's bar)
    for _, x in ipairs(w._zPoolAlso or {}) do Collect(x, all, 1) end
    for _, o in ipairs(all) do SnapOne(o) end
    w._zPoolTree = all
    w._zPoolW, w._zPoolH = w:GetWidth(), w:GetHeight()
    -- the snapshot holds _zPoolTree etc. too (taken before them: put them in)
    local s = rawget(w, "_zPoolSnap")
    s.fields._zPoolTree, s.fields._zPoolW, s.fields._zPoolH = all, w._zPoolW, w._zPoolH
end

-- A fresh FontString as the client hands it out, for UI.Font's reuse.
local function SnapFont(fs)
    local f = {}
    f.font = { fs:GetFont() }
    f.shadow = { fs:GetShadowOffset() }
    f.shadowColor = { fs:GetShadowColor() }
    f.spacing = fs.GetSpacing and fs:GetSpacing() or nil
    f.wrap = fs.CanWordWrap and fs:CanWordWrap()
    f.nsWrap = fs.CanNonSpaceWrap and fs:CanNonSpaceWrap()
    f.justifyH = fs.GetJustifyH and fs:GetJustifyH()
    f.justifyV = fs.GetJustifyV and fs:GetJustifyV()
    f.maxLines = fs.GetMaxLines and fs:GetMaxLines()
    f.layer = { fs:GetDrawLayer() }
    fs._zPoolFont = f
end

local function ResetFont(fs)
    local f = fs._zPoolFont
    if not f then return end
    fs:ClearAllPoints()
    fs:SetWidth(0)
    fs:SetHeight(0)
    fs:SetText("")
    if f.font[1] then pcall(fs.SetFont, fs, f.font[1], f.font[2] or 12, f.font[3] or "") end
    if f.shadow[1] then fs:SetShadowOffset(f.shadow[1], f.shadow[2] or 0) end
    if f.shadowColor[1] then fs:SetShadowColor(f.shadowColor[1], f.shadowColor[2], f.shadowColor[3], f.shadowColor[4] or 1) end
    if f.spacing and fs.SetSpacing then fs:SetSpacing(f.spacing) end
    if f.wrap ~= nil and fs.SetWordWrap then fs:SetWordWrap(f.wrap) end
    if f.nsWrap ~= nil and fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(f.nsWrap) end
    if f.justifyH and fs.SetJustifyH then fs:SetJustifyH(f.justifyH) end
    if f.justifyV and fs.SetJustifyV then fs:SetJustifyV(f.justifyV) end
    if f.maxLines and fs.SetMaxLines then fs:SetMaxLines(f.maxLines) end
    if f.layer[1] and fs.SetDrawLayer then fs:SetDrawLayer(f.layer[1], f.layer[2] or 0) end
end

local holder
local function Holder()
    if not holder then
        holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
    end
    return holder
end

local function Orphan(o)
    if o.Hide then o:Hide() end
    if o.ClearAllPoints then o:ClearAllPoints() end
    if not IsRegion(o) and o.SetParent then o:SetParent(nil) end
    Pool.stats.orphaned = Pool.stats.orphaned + 1
end

local function RestoreOne(o, isRoot, pooledSet)
    local s = rawget(o, "_zPoolSnap")
    if not s then return end
    -- what the page parented to it afterwards: pooled things go home on
    -- their own, the rest is let go (as every page part was before)
    if s.kids and o.GetChildren then
        for _, c in ipairs({ o:GetChildren() }) do
            -- a dimmed widget's reason cover (UIF_Pickers) goes back to its
            -- own free list, not let go
            if rawget(c, "_zPoolKeep") then
                if ns.UI and ns.UI.RecycleWhy then ns.UI.RecycleWhy(c) else c:Hide() end
            elseif not s.kids[c] and not pooledSet[c] then
                Orphan(c)
            end
        end
    end
    if s.regs and o.GetRegions then
        for _, r in ipairs({ o:GetRegions() }) do
            if not s.regs[r] and not pooledSet[r] then Orphan(r) end
        end
    end
    -- fields: what was added goes, what was changed comes back
    local drop
    for k in pairs(o) do
        if not Skip(k) and s.fields[k] == nil then
            drop = drop or {}
            drop[#drop + 1] = k
        end
    end
    if drop then for _, k in ipairs(drop) do o[k] = nil end end
    for k, v in pairs(s.fields) do
        if rawget(o, k) ~= v then o[k] = v end
    end
    for k, n in pairs(s.arrays) do
        local t = rawget(o, k)
        if type(t) == "table" then for i = #t, n + 1, -1 do t[i] = nil end end
    end
    local hooks = rawget(o, "_zPH")
    if hooks then for k in pairs(hooks) do hooks[k] = nil end end
    if s.scripts then
        for h, fn in pairs(s.scripts) do
            local ok, cur = pcall(o.GetScript, o, h)
            if ok and (cur or false) ~= fn then o:SetScript(h, fn or nil) end
        end
    end
    if s.mouse ~= nil and o:IsMouseEnabled() ~= s.mouse then o:EnableMouse(s.mouse) end
    if s.enabled ~= nil then
        local ok, e = pcall(o.IsEnabled, o)
        if ok and (e and true or false) ~= s.enabled then
            if s.enabled then o:Enable() else o:Disable() end
        end
    end
    if not isRoot then
        if o.SetAlpha and o:GetAlpha() ~= s.alpha then o:SetAlpha(s.alpha) end
        if o.SetShown and (o:IsShown() and true or false) ~= s.shown then o:SetShown(s.shown) end
    end
end

-- ============================================================
-- TAKE / GIVE BACK
-- ============================================================
-- What went wrong handing a widget back (kept, never in chat: the widget
-- still works, it just may not look refreshed; /zui debug and the tests
-- read Pool.notes).
Pool.notes = {}
function Pool.Note(msg)
    if #Pool.notes < 50 then Pool.notes[#Pool.notes + 1] = msg end
end

local function Pack(...) return { n = select("#", ...), ... } end

local function Track(w)
    Pool.live[#Pool.live + 1] = w
end

local function Quiet(fn, ...)
    local was = UI._zQuiet
    UI._zQuiet = true
    Pool.depth = Pool.depth + 1
    local ok, err = pcall(fn, ...)
    Pool.depth = Pool.depth - 1
    UI._zQuiet = was
    if not ok then Pool.Note("refresh: " .. tostring(err)) end
    return ok
end

-- RefreshTree: a reused widget reads its settings again (its own
-- _zPoolRefresh, else its Refresh), then repaints in today's colours.
local function RefreshWidget(w)
    if w._zPoolRefresh then w._zPoolRefresh(w)
    elseif type(w.Refresh) == "function" then w.Refresh(w) end
end
Pool.RefreshWidget = RefreshWidget

-- Acquire(name, raw, spec, ...): raw(...) built new, or the same shape
-- given back. spec: parent (arg index, 1), values (arg indexes that are
-- the current value, not the shape), optValues (keys of the opts table
-- at spec.opts that are values), rebind(w, ...) (hand the values over),
-- ret(w, args) (a second return value), region (a FontString).
local function Acquire(name, raw, spec, ...)
    local plain = spec.plain or raw
    if Pool.off or Pool.depth > 0 or not Pool.scope then return plain(...) end
    local n = select("#", ...)
    local args = { n = n, ... }
    local parent = args[spec.parent or 1]
    if type(parent) ~= "table" or not Under(parent, Pool.root) then return plain(...) end
    local buf = { Pool.scope, "|", name, "|", FontEpoch(), "|", tostring(UI.Room(parent)), "|" }
    if spec.sig then
        buf[#buf + 1] = spec.sig(args)
    else
        for i = 1, n do
            if i ~= (spec.parent or 1) and not (spec.values and spec.values[i]) then
                local v = args[i]
                if spec.optValues and i == (spec.opts or 2) and type(v) == "table" then
                    local trimmed = {}
                    for k, x in pairs(v) do if not spec.optValues[k] then trimmed[k] = x end end
                    v = trimmed
                end
                SigOf(v, 0, buf)
                buf[#buf + 1] = "|"
            end
        end
    end
    local key = table_concat(buf)
    local list = Pool.free[key]
    local w = list and list[1]
    if w then
        table_remove(list, 1)
        if w._zPoolLive then w._zPoolLive.cur = args end
        w:SetParent(parent)
        w:Show()
        for _, x in ipairs(w._zPoolAlso or {}) do x:SetParent(parent) x:Show() end
        Track(w)
        Pool.stats.reused = Pool.stats.reused + 1
        Quiet(function()
            if w._zPoolRefit then w:_zPoolRefit() end
            if spec.rebind then spec.rebind(w, unpack(args, 1, n)) end
            RefreshWidget(w)
            if UI.RepaintTree then UI.RepaintTree(w) elseif w._zPaint then w:_zPaint() end
        end)
        if spec.ret then return w, spec.ret(w, args) end
        return w
    end
    -- built new: through forwarders, so a later build's functions are the
    -- ones it calls
    local live = { cur = args }
    local shadow = {}
    for i = 1, n do
        local v = args[i]
        if i ~= (spec.parent or 1) and type(v) == "function" then
            shadow[i] = Forwarder(live, { i })
        elseif i ~= (spec.parent or 1) and type(v) == "table" and not IsObj(v) then
            shadow[i] = ShadowOf(v, live, { i })
        else
            shadow[i] = v
        end
    end
    Pool.depth = Pool.depth + 1
    local res = Pack(pcall(raw, unpack(shadow, 1, n)))
    Pool.depth = Pool.depth - 1
    if not res[1] then error(res[2], 0) end
    w = res[2]
    if IsObj(w) then
        w._zPoolKey, w._zPoolLive = key, live
        if spec.region and not w._zPoolFont then SnapFont(w) end
        Snapshot(w)
        Track(w)
        Pool.stats.built = Pool.stats.built + 1
    end
    return unpack(res, 2, res.n)
end
Pool.Acquire = Acquire

-- Pool.Make(name, fn, parent, ...): any page part built by fn(parent, ...)
-- pooled like a widget (fn must make the same thing every time).
function Pool.Make(name, fn, ...)
    return Acquire(name, fn, { parent = 1 }, ...)
end

-- Begin / End: the live page build (Config_Window).
function Pool.Begin(root, scope)
    Pool.root, Pool.scope = root, scope
end
function Pool.End()
    Pool.root, Pool.scope = nil, nil
end

-- Everything the last build took goes back. Returns how many.
function Pool.Release()
    local list = Pool.live
    if #list == 0 then return 0 end
    Pool.live = {}
    local set = {}
    for _, w in ipairs(list) do
        set[w] = true
        for _, x in ipairs(w._zPoolAlso or {}) do set[x] = true end
    end
    local h = Holder()
    -- everything stops moving first (put at rest by the motion driver),
    -- then each widget is put back the way it was built
    if ns.Motion and ns.Motion.StopTree then
        for _, w in ipairs(list) do
            if not w._zPoolFont then pcall(ns.Motion.StopTree, w) end
        end
    end
    for _, w in ipairs(list) do
        Pool.depth = Pool.depth + 1
        local ok, err = pcall(function()
            for _, o in ipairs(w._zPoolTree or { w }) do RestoreOne(o, o == w, set) end
            if w._zUnfit then w:_zUnfit() end
            if w._zPoolFont then
                ResetFont(w)
            elseif w._zPoolW then
                w:SetSize(w._zPoolW, w._zPoolH)
            end
            w:SetAlpha(1)
            w:ClearAllPoints()
            w:Hide()
            w:SetParent(h)
            for _, x in ipairs(w._zPoolAlso or {}) do
                RestoreOne(x, true, set)
                x:ClearAllPoints()
                x:SetParent(h)
            end
        end)
        Pool.depth = Pool.depth - 1
        if ok then
            local key = w._zPoolKey
            local l = Pool.free[key]
            if not l then l = {} Pool.free[key] = l end
            l[#l + 1] = w
            Pool.stats.released = Pool.stats.released + 1
        else
            Pool.Note("release: " .. tostring(err))
            pcall(Orphan, w)
        end
    end
    return #list
end

-- How many widgets wait in the pool (for the tests and /zui debug).
function Pool.Count()
    local n = 0
    for _, l in pairs(Pool.free) do n = n + #l end
    return n
end

-- Drop everything waiting (a font change makes every pooled widget the
-- wrong shape anyway; they are simply never handed out again).
function Pool.Flush() Pool.free = {} end

-- ============================================================
-- THE WIDGETS
-- ============================================================
UI._zRawScrollAreaPlain = UI.ScrollArea
local function Wrap(name, spec)
    local plain = UI[name]
    local raw = spec.raw or plain
    if type(raw) ~= "function" then return end
    local own = {}
    for k, v in pairs(spec) do own[k] = v end
    own.plain = plain
    spec = own
    UI["_zRaw" .. name] = plain
    UI[name] = function(...) return Acquire(name, raw, spec, ...) end
end

-- UI.Holder(parent, kind): a plain frame a page lays its controls out in
-- (a row of buttons, a strip). Pooled like the widgets on a live page.
function UI.Holder(parent, kind)
    return CreateFrame(kind or "Frame", nil, parent)
end

local P1 = { parent = 1 }
Wrap("Holder", P1)
Wrap("Button", P1)
Wrap("CloseX", P1)
Wrap("Box", P1)
Wrap("Swatch", P1)
Wrap("Checkbox", { parent = 1, values = { [3] = true },
    rebind = function(w, _, _, checked) w:SetChecked(checked) end })
Wrap("Slider", { parent = 1, opts = 2, optValues = { value = true },
    rebind = function(w, _, o)
        o = o or {}
        if w._zSetQuiet then w._zSetQuiet(o.value) end
    end })
Wrap("Dropdown", P1)
-- (its bar is the parent's child: it travels with it)
Wrap("ScrollArea", { parent = 1,
    raw = function(parent, opts)
        local scroll, child, bar = UI._zRawScrollAreaPlain(parent, opts)
        scroll._zPoolAlso = { bar }
        return scroll, child, bar
    end,
    rebind = function(w)
        w.bar:SetMinMaxValues(0, 0)
        w.bar:SetValue(0)
        w:SetVerticalScroll(0)
    end,
    ret = function(w) return w.child, w.bar end })
Wrap("EditBox", { parent = 1, opts = 2, optValues = { text = true },
    rebind = function(w, _, o) w:SetText((o and o.text) or "") end })
Wrap("TextBox", { parent = 1, opts = 2, optValues = { text = true },
    rebind = function(w, _, o) w:SetText((o and o.text) or "") end })
Wrap("Card", { parent = 1, values = { [3] = true },
    rebind = function(w, parent, _, y)
        -- (a settings section sits at the window's 45 px pad, UI.S)
        local m = rawget(w, "_zSet") and UI.S.PAD or M.MARGIN
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", m, y)
        w:SetPoint("RIGHT", parent, "RIGHT", -m, 0)
    end })
Wrap("PageHeader", { parent = 1, values = { [4] = true },
    rebind = function(w, parent, _, _, y)
        local m = rawget(w, "_zSet") and 0 or M.MARGIN
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", m, y)
        w:SetPoint("RIGHT", parent, "RIGHT", -m, 0)
    end,
    ret = function(w, args) return args[4] - w:GetHeight() - (rawget(w, "_zSet") and 0 or 12) end })
-- text: everything is set again on reuse, so only the layer / template
-- make its shape
-- (built here rather than through UI.Font, so the string's look is read
-- the moment the client hands it out, before anything is set on it)
UI._zRawFontFresh = function(parent, size, opts)
    local o = type(opts) == "table" and opts or {}
    local fs = parent:CreateFontString(nil, o.layer or "OVERLAY", o.template or "GameFontNormal")
    SnapFont(fs)
    return UI._zFontApply(fs, size, opts)
end
Wrap("Font", { parent = 1, region = true, raw = UI._zRawFontFresh,
    sig = function(args)
        local o = args[3]
        return tostring(type(o) == "table" and o.layer or "") .. "/" .. tostring(type(o) == "table" and o.template or "")
    end,
    rebind = function(w, _, size, opts) if UI._zFontApply then UI._zFontApply(w, size, opts) end end })
for _, name in ipairs({ "ColorPicker", "FontFaceDropdown", "TexturePicker", "FontPicker", "AnimationPicker",
    "AnchorPicker", "FramePositionPicker", "FrameLayerPicker", "LayoutPicker", "VisibilityPicker", "ChromePicker",
    "StateEditor", "TextFormatPicker", "SoundPicker", "SoundSpecPicker", "FieldHost",
    "TextElementGroup", "FrameElementGroup" }) do
    Wrap(name, P1)
end
-- (the note where a face picker was: its column's width again on reuse)
Wrap("OneFontNote", { parent = 1, rebind = function(w, _, width) if w._zFit then w:_zFit(width or 200) end end })
