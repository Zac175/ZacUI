-- ============================================================================
-- Zacui_UnitFrames - Options.lua
-- The unit frames' settings, as a page of ZacUI's own config (/zui > Unit
-- frames), in ZacUI's standard page shape:
--   General    what shows, per frame; auras, the shout alert, low health
--   Look       sizes, colours, textures, bars, aura icons, the castbar
--   Text       the font, and one font setting per kind of text
--   Animation  the castbar, the shout glow, the low-health pulse, smooth bars
--   Position   moving the frames, group layout, every element's anchor
--   Heals      incoming heals (a feature big enough for a tab of its own)
--   Advanced   import / export and saved profiles
-- with a live preview in ZacUI's dock (Preview.lua): the frame you are
-- setting up, drawn by the frames' own code, on every tab; the Animation and
-- Heals tabs show their own samples. "Settings for" on the page and the
-- dock's mode buttons are the same choice, kept in step both ways.
-- /zuf opens this page. Part of ZacUI; load order is set by the TOC.
-- ============================================================================
local ADDON, ns = ...

local NINE_OPT = { "ABOVE", "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT", "BELOW" }

-- Every positionable element + its per-frame anchor / X / Y keys, for the
-- "pick an element, then set its anchor + offset" picker (mirrors the
-- Position dialog so the same fine-tuning lives on the page too).
local POS_ELEMS = { "Name", "Health", "Buffs", "Debuffs", "Castbar", "Combat", "Leader", "Role", "Marker", "PvP", "Rez" }
local POS_LABEL = {
    Name = "Name", Health = "Health text", Buffs = "Buffs", Debuffs = "Debuffs", Castbar = "Castbar",
    Combat = "Combat icon", Leader = "Leader icon", Role = "Role icon", Marker = "Raid marker",
    PvP = "PvP text", Rez = "Resurrection icon",
}
local POS_KEY = {
    Name    = { a = "nameAnchor",   x = "nameX",   y = "nameY"   },
    Health  = { a = "hpAnchor",     x = "hpX",     y = "hpY"     },
    Buffs   = { a = "buffAnchor",   x = "buffX",   y = "buffY"   },
    Debuffs = { a = "debuffAnchor", x = "debuffX", y = "debuffY" },
    Castbar = { a = "cbAnchor",     x = "cbX",     y = "cbY"     },
    Combat  = { a = "combatAnchor", x = "combatX", y = "combatY", s = "combatSize" },
    Leader  = { a = "leaderAnchor", x = "leaderX", y = "leaderY", s = "leaderSize" },
    Role    = { a = "roleAnchor",   x = "roleX",   y = "roleY",   s = "roleSize"   },
    Marker  = { a = "raidAnchor",   x = "raidX",   y = "raidY",   s = "raidSize"   },
    PvP     = { a = "pvpAnchor",    x = "pvpX",    y = "pvpY",    s = "pvpSize"    },
    Rez     = { a = "rezAnchor",    x = "rezX",    y = "rezY",    s = "rezSize"    },
}

local FRAME_KEYS   = { "player", "target", "targettarget", "pet", "party", "raid" }
local FRAME_LABELS = { player = "Player", target = "Target", targettarget = "Target of target",
                       pet = "Pet", party = "Party", raid = "Raid" }

local PREVIEW_FRAMES = "unitframes.frames"

-- the element picked in each frame's element picker, kept across rebuilds
local pick = { elem = {}, part = {} }
-- the parts with a size of their own (the status icons)
local POS_SIZE = { combat = "combatSize", leader = "leaderSize", role = "roleSize", raid = "raidSize", rez = "rezSize" }

-- Reposition a secure group header live (out of combat only).
local function setHeaderPos(kind, axis, v)
    local cfg = ns.db[kind]
    cfg[axis] = v
    local h = ns.frames[kind]
    if h and not InCombatLockdown() then
        h:ClearAllPoints()
        h:SetPoint(cfg.point, UIParent, cfg.point, cfg.x, cfg.y)
        if h.mover then
            h.mover:ClearAllPoints()
            h.mover:SetPoint("BOTTOMLEFT", h, "TOPLEFT", 0, 2)
        end
    end
    if ns.UpdateMocks then ns.UpdateMocks() end
end

-- Reposition a single unit frame live (CENTER-relative; out of combat only).
local function setFramePos(key, axis, v)
    local cfg = ns.db.frames[key]
    cfg[axis] = v
    local f = ns.frames[key]
    if f and not InCombatLockdown() then
        f:ClearAllPoints()
        f:SetPoint(cfg.point or "CENTER", UIParent, cfg.point or "CENTER", cfg.x, cfg.y)
    end
end

local function ZUI() return ns.ZUI or _G.ZacUI end
local function PageOpen()
    local Z = ZUI()
    return Z and Z.ConfigIsOpen and Z.ConfigIsOpen()
        and Z.ConfigState and Z.ConfigState().selected == "unitframes"
end
local function Refresh()
    local Z = ZUI()
    if Z and Z.RefreshConfig then Z.RefreshConfig() end
end

-- A castbar dragged on screen moves its offsets: the open page shows them.
function ns.RefreshOptions()
    if PageOpen() then Refresh() end
end

-- /zuf and the position dialog's "All settings": the page, or closed when
-- it is already the one up.
function ns.ToggleConfig()
    local Z = ZUI()
    if not (Z and Z.OpenConfig) then return end
    if PageOpen() and Z.ToggleConfig then Z.ToggleConfig() return end
    Z.OpenConfig("unitframes")
end

-- ----------------------------------------------------------------------------
-- Which frame the page is set up for. It IS the frames preview's mode (kept
-- in ZacUI's window state with the dock's other choices), so picking on the
-- page moves the dock and clicking a mode in the dock moves the page.
-- ----------------------------------------------------------------------------
local function PreviewModes()
    local Z = ZUI()
    local s = Z and Z.ConfigState and Z.ConfigState()
    if not s then return nil end
    s.preview = s.preview or {}
    s.preview.modes = s.preview.modes or {}
    return s.preview.modes
end
local function CurrentFrame()
    local m = PreviewModes()
    local v = m and m[PREVIEW_FRAMES]
    if FRAME_LABELS[v] then return v end
    return "player"
end
local function SetCurrentFrame(v)
    local m = PreviewModes()
    if m and FRAME_LABELS[v] then m[PREVIEW_FRAMES] = v end
end
local function IsGroup(key) return key == "party" or key == "raid" end
local function CfgOf(key)
    if IsGroup(key) then return ns.db[key] end
    return ns.db.frames[key]
end
-- what the page on screen was built for (the preview compares, see below)
local builtFor

-- ============================================================================
-- CONTROLS - ZacUI's widgets, each one writing to ns.db and re-applying.
-- Two to a row where they are short, one card per subject.
-- ============================================================================
local UI, M, F
local ROW_W, COL2 = 460, 230

local function Apply() if ns.ApplySettings then ns.ApplySettings() end end

local function PX(v) return string.format("%d px", v) end
local function SEC(v) return string.format("%.2fs", v) end
local function PCT(v) return string.format("%d%%", v) end
local function TIMES(v) return string.format("%dx", v) end

-- ----------------------------------------------------------------------------
-- EVERY ROW FITS ITS CARD (ZacUI's layout rule: nothing past its card, at
-- any window width and font size). A row of several controls takes as many
-- columns as the widest one fits (4 -> 3 -> 2 -> 1), each cell an equal
-- share of the card's room; a control still wider than its cell is fitted
-- into it - its label wraps onto more lines and the row grows taller,
-- nothing is cut short. Buttons sit side by side and wrap onto a new line
-- (L:Flow), each as wide as its label. Widths are read at build: the page
-- is built again after every resize.
-- ----------------------------------------------------------------------------
local function InnerWidth(L)
    local card = L.current
    local w = card and card.GetWidth and card:GetWidth()
    if type(w) ~= "number" or w < 200 then
        local p = L.parent and L.parent.GetWidth and L.parent:GetWidth()
        if type(p) == "number" and p >= 240 then w = p - 2 * M.MARGIN else w = ROW_W + 2 * M.CONTROL_X end
    end
    return math.max(120, math.floor(w - 2 * M.CONTROL_X))
end

local function NewRow(L, h)
    local row = UI.Holder(L.current)
    row:SetSize(InnerWidth(L), h)
    return row
end

-- A list row's name held to `w` px on one line: cut short ON PURPOSE, the
-- whole text in a tooltip while it does not fit (UI.TruncTip).
local function ClampText(owner, fs, w)
    if not fs then return end
    if (fs:GetStringWidth() or 0) > w + 0.5 then
        fs:SetWidth(math.max(10, w))
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        if owner.EnableMouse then owner:EnableMouse(true) end
        UI.TruncTip(fs, owner)
    end
end

-- Lay `widgets` (children of the open card) out in a grid of up to `per`
-- columns. Rows are `rowH` apart, plus whatever a wrapped control grew past
-- `cellH`; `gap` goes under the last row. fit(widget, cellW) fits one
-- widget into its cell.
local GRID_GAP = 8
local function Grid(L, widgets, per, rowH, gap, cellH, fit)
    local card = L.current
    local room = L:Room()
    local widest = 0
    for _, w in ipairs(widgets) do widest = math.max(widest, w._zNatW or w:GetWidth() or 0) end
    local cols = math.max(1, math.min(per, #widgets))
    while cols > 1 and math.floor((room - GRID_GAP * (cols - 1)) / cols) < widest do cols = cols - 1 end
    local cell = math.floor((room - GRID_GAP * (cols - 1)) / cols)
    local y = card._y
    local i = 1
    while i <= #widgets do
        local tall = cellH
        for c = 0, cols - 1 do
            local w = widgets[i + c]
            if not w then break end
            fit(w, cell)
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", card, "TOPLEFT", M.CONTROL_X + c * (cell + GRID_GAP), y)
            tall = math.max(tall, w:GetHeight() or cellH)
        end
        i = i + cols
        y = y - (tall - cellH) - ((i > #widgets) and (cellH + gap) or rowH)
    end
    card._y = y
    -- a description written under the grid hangs its long text on the
    -- grid's first control (ZacUI's Layout:Desc)
    card._zLastRow, card._zSlack, card._zSlackY = widgets[1], gap, y
end

-- a control wider than its cell fits itself into it (_zFit: a label wraps)
local function FitInto(w, cellW)
    if w._zFit and (w:GetWidth() or 0) > cellW + 0.5 then w:_zFit(cellW) end
end

local function Check(parent, label, get, set, tip)
    return UI.Checkbox(parent, label, get() and true or false,
        function(v) set(v and true or false) Apply() end, tip and { tooltip = tip } or nil)
end

-- checkboxes across rows: list of { label, get, set [, tooltip] }; `per`
-- is the most columns, fewer when the card is narrower
local function Checks(L, list, per)
    local ws = {}
    for i, e in ipairs(list) do ws[i] = Check(L.current, e[1], e[2], e[3], e[4]) end
    Grid(L, ws, per or 4, M.ROW, M.ROW - M.CHECK, M.CHECK, FitInto)
end

local function Slider(parent, s)
    local v = s.get()
    if type(v) ~= "number" then v = s.min end
    return UI.Slider(parent, { width = 200, min = s.min, max = s.max, step = s.step or 1,
        value = v, label = s.label, format = s.format,
        onChange = function(nv) s.set(nv) if not s.noApply then Apply() end end })
end

-- one or two sliders on a row: { label =, min =, max =, step =, get =, set =, format = }
local function Sliders(L, a, b)
    local ws = { Slider(L.current, a) }
    if b then ws[2] = Slider(L.current, b) end
    Grid(L, ws, 2, 40, 10, 30, FitInto)
end

local function TextOf(items, v)
    for _, it in ipairs(items) do
        if type(it) == "table" then
            if it.value == v then return it.text end
        elseif it == v then
            return tostring(it)
        end
    end
    return v ~= nil and tostring(v) or ""
end

-- A labelled dropdown. _zFit(w) narrows it to a cell; a label longer than
-- the cell wraps and the dropdown moves down under it.
local function Drop(parent, d)
    local w = d.width or 200
    local host = UI.Holder(parent)
    host:SetSize(w, 16 + M.DROPDOWN_H)
    local t = UI.Font(host, F.SMALL, { text = d.label, cat = "text", key = "gray" })
    t:SetPoint("TOPLEFT")
    local one = math.ceil(t:GetStringHeight() or F.SMALL)
    local function Items() return type(d.items) == "function" and d.items() or d.items end
    local dd = UI.Dropdown(host, { width = w,
        items = Items,
        selectedValue = function() return d.get() end,
        selected = function() return TextOf(Items(), d.get()) end,
        onSelect = function(v)
            d.set(v)
            if not d.noApply then Apply() end
        end })
    -- under its label however big the font is
    local lg = math.max(15, UI.LabelGap and UI.LabelGap(t) or 15)
    host:SetHeight(lg + 1 + M.DROPDOWN_H)
    dd:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -lg)
    host.dropdown, host.label = dd, t
    host._zNatW = w
    function host:_zFit(cw)
        cw = math.max(60, math.floor(cw))
        self:SetWidth(cw)
        dd:SetWidth(cw)
        local extra = 0
        if (t:GetStringWidth() or 0) > cw + 0.5 then
            t:SetWidth(cw)
            t:SetJustifyH("LEFT")
            t:SetWordWrap(true)
            extra = math.max(0, math.ceil(t:GetStringHeight() or one) - one)
        end
        dd:ClearAllPoints()
        dd:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -lg - extra)
        self:SetHeight(lg + 1 + M.DROPDOWN_H + extra)
        self._zExtraH = extra
    end
    return host
end

-- one or two dropdowns on a row: { label =, items =, get =, set = }
local function FitDrop(w, cellW) w:_zFit(math.min(w._zNatW, cellW)) end
local function Drops(L, a, b)
    local ws = { Drop(L.current, a) }
    if b then ws[2] = Drop(L.current, b) end
    -- (the row ends 8 under the boxes, like every other row, so a
    -- description after it starts under the box, not inside it)
    Grid(L, ws, 2, 16 + M.DROPDOWN_H + 8, 8, 16 + M.DROPDOWN_H, FitDrop)
end

-- Colour settings through ZacUI's colour picker. Our colours are saved as
-- { r, g, b [, a] } arrays (what the frames read), so the getter hands the
-- picker plain numbers and the setter writes the array IN PLACE - heal
-- colour references must survive a reset. list: { label, get, set, alpha }
-- where get returns r, g, b, a and set takes them.
local function Colours(L, list)
    local ws = {}
    for i, e in ipairs(list) do
        local get, set = e[2], e[3]
        local cp = UI.ColorPicker(L.current, { label = e[1], alpha = e[4] and true or false,
            get = get,
            set = function(r, g, b, a) set(r, g, b, a) Apply() end })
        cp._zNatW = math.max(120, cp:GetWidth() or 0)
        ws[i] = cp
    end
    Grid(L, ws, 2, M.ROW, M.ROW - 16, 16, FitInto)
end

-- getter / setter pair over a { r, g, b [, a] } array at tbl[key]
local function Arr(tbl, key, dr, dg, db, da)
    return function()
            local c = tbl[key]
            if type(c) ~= "table" then return dr or 1, dg or 1, db or 1, da or 1 end
            return c[1] or dr or 1, c[2] or dg or 1, c[3] or db or 1, c[4] or da or 1
        end,
        function(r, g, b, a)
            local c = tbl[key]
            if type(c) ~= "table" then c = {} tbl[key] = c end
            c[1], c[2], c[3] = r, g, b
            if a ~= nil then c[4] = a end
        end
end

local function Button(L, label, width, onClick, tip)
    local b = UI.Button(L.current, label, { width = width or 160, tooltip = tip, onClick = onClick })
    L:Row(b, M.BUTTON_H + 6)
    return b
end

-- buttons side by side, each at least as wide as its label, wrapping onto
-- a new line when the card runs out: list of { label, width, onClick [, tooltip] }
local function Buttons(L, list)
    local ws = {}
    for i, e in ipairs(list) do
        ws[i] = UI.Button(L.current, e[1], { width = e[2] or 140, tooltip = e[4], onClick = e[3] })
    end
    L:Flow(ws, 8, 6)
end

local HEALTH_TEXT = {
    { text = "None", value = "none" }, { text = "Current", value = "current" },
    { text = "Percent", value = "percent" }, { text = "Current and percent", value = "both" },
}

-- ----------------------------------------------------------------------------
-- The "Settings for" card at the top of the per-frame tabs
-- ----------------------------------------------------------------------------
local function FramePicker(L)
    local key = CurrentFrame()
    L:Card("Frame")
    local items = {}
    for _, k in ipairs(FRAME_KEYS) do items[#items + 1] = { text = FRAME_LABELS[k], value = k } end
    Drops(L, { label = "Settings for", items = items, noApply = true,
        get = function() return key end,
        set = function(v)
            SetCurrentFrame(v)
            Refresh()
        end })
    L:Desc("The settings marked \"this frame\" below are for the frame picked here, and the preview shows it.")
    L:EndCard()
    return key, CfgOf(key)
end

-- the element picker for one frame cfg (pickKey remembers the element)
local function PosPicker(L, cfg, pickKey)
    local sel = pick.elem[pickKey] or "Name"
    if not POS_KEY[sel] then sel = "Name" end
    local K = POS_KEY[sel]
    -- the preview's samples wear the icon being placed (Preview.lua)
    if ns.UFPreview then ns.UFPreview.focus = sel end
    local items = {}
    for _, e in ipairs(POS_ELEMS) do items[#items + 1] = { text = POS_LABEL[e], value = e } end
    Drops(L,
        { label = "Element", items = items, noApply = true,
          get = function() return sel end,
          set = function(v)
              pick.elem[pickKey] = v
              Refresh()
          end },
        { label = "Anchor", items = NINE_OPT,
          get = function() return cfg[K.a] end, set = function(v) cfg[K.a] = v end })
    Sliders(L,
        { label = "X offset", min = -250, max = 250, format = PX, get = function() return cfg[K.x] or 0 end, set = function(v) cfg[K.x] = v end },
        { label = "Y offset", min = -250, max = 250, format = PX, get = function() return cfg[K.y] or 0 end, set = function(v) cfg[K.y] = v end })
    if sel == "Castbar" then
        Sliders(L,
            { label = "Width (0 = frame width)", min = 0, max = 400, format = PX, get = function() return cfg.cbWidth or 0 end, set = function(v) cfg.cbWidth = v end },
            { label = "Height (0 = castbar height)", min = 0, max = 60, format = PX, get = function() return cfg.cbHeight or 0 end, set = function(v) cfg.cbHeight = v end })
    elseif K.s then
        Sliders(L, { label = "Size", min = 6, max = 40, format = PX, get = function() return cfg[K.s] or 0 end, set = function(v) cfg[K.s] = v end })
    end
end

local function spellTexture(q)
    if not q then return nil end
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(q) end
    if GetSpellTexture then return GetSpellTexture(q) end
    if GetSpellInfo then return select(3, GetSpellInfo(q)) end
    return nil
end

-- one aura filter list: the entries with a remove X, then a box to add one
local function AuraList(L, title, list)
    local hdr = UI.Font(L.current, F.SMALL, { text = title, cat = "text", key = "gray" })
    L:Row(hdr, 16)
    for idx, e in ipairs(list) do
        local row = NewRow(L, 18)
        local x = UI.CloseX(row, 14, function()
            table.remove(list, idx)
            Apply()
            local Z = ZUI()
            if Z and Z.SettingsChanged then Z.SettingsChanged("unitframes.aurafilter") end
            Refresh()
        end)
        x:SetPoint("LEFT")
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon._zui_own = true
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 22, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:SetTexture(spellTexture(e.id) or spellTexture(e.label) or "Interface\\Icons\\INV_Misc_QuestionMark")
        local t = UI.Font(row, F.LABEL, { text = e.label or (e.id and tostring(e.id)) or e.name or "?" })
        t:SetPoint("LEFT", 44, 0)
        ClampText(row, t, InnerWidth(L) - 44)
        L:Row(row, 20)
    end
    local function Add(text)
        local txt = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if txt == "" then return end
        local id = tonumber(txt)
        local entry = id and { label = tostring(id), id = id } or { label = txt, name = string.lower(txt) }
        for _, e in ipairs(list) do
            if (entry.id and e.id == entry.id) or (entry.name and e.name == entry.name) then return end
        end
        list[#list + 1] = entry
        Apply()
        Refresh()
    end
    local box = UI.EditBox(L.current, { width = 260, hint = "Name or spell ID, then Enter", onEnter = Add })
    L:Row(box, (M.EDIT_H or 20) + 8)
end

-- get / set / defaults for one kind of text's font setting (the size of the
-- name and of the heal number live where saves always kept them)
local function FontBinding(kind, defSize, sizeGet, sizeSet)
    local db = ns.db
    db.fonts = db.fonts or {}
    return function()
            local t = {}
            for k, v in pairs(db.fonts[kind] or {}) do t[k] = v end
            if sizeGet then t.size = sizeGet() end
            return t
        end,
        function(t)
            if sizeSet then
                if t.size then sizeSet(t.size) end
                t.size = nil
            end
            db.fonts[kind] = t
            Apply()
        end,
        { face = db.media.font, size = defSize, outline = "outline", shadow = false }
end

-- ZacUI's customization standard, bound to this addon's settings:
-- cfg.anchors.<element>, cfg.formats.<element>, cfg.visibility
local function ZC() return ns.ZUI or _G.ZacUI end
local function Access(tbl, family, key)
    return ZC().CustomAccess(tbl, family, key, Apply)
end
-- what an element of a frame can hang off: every other element
local function TargetsFor(self)
    local out = {}
    for _, k in ipairs(ns.ANCHOR_TARGETS or {}) do
        if k ~= self then out[#out + 1] = { value = k, text = ns.ANCHOR_LABELS[k] or k } end
    end
    return out
end
local function AnchorDef(cfg, el) return function() return ns.AnchorDefaults(cfg, el) end end
-- a { r, g, b [, a] } array colour as a picker get / set (Apply after)
local function ArrColor(tbl, key, dr, dg, db, da)
    local g, s = Arr(tbl, key, dr, dg, db, da)
    return g, function(r, gg, b, a) s(r, gg, b, a) Apply() end
end

-- One font setting (ZacUI's font picker). kind: the db.fonts key; the size
-- of the name and of the heal number live where saves always kept them.
local function FontPick(L, label, kind, defSize, sample, sizeGet, sizeSet)
    local db = ns.db
    db.fonts = db.fonts or {}
    local p = UI.FontPicker(L.current, { label = label, width = InnerWidth(L),
        get = function()
            local t = {}
            for k, v in pairs(db.fonts[kind] or {}) do t[k] = v end
            if sizeGet then t.size = sizeGet() end
            return t
        end,
        set = function(t)
            if sizeSet then
                if t.size then sizeSet(t.size) end
                t.size = nil
            end
            db.fonts[kind] = t
            Apply()
        end,
        defaults = { face = db.media.font, size = defSize, outline = "outline", shadow = false },
        defaultLabel = "Unit frames font", minSize = 6, maxSize = 32, sample = sample })
    L:Add(p, 10)
    return p
end

-- the SharedMedia bar textures the frames can draw (their own list)
local function BarList(skip)
    return function()
        local out = {}
        for _, n in ipairs(ns.Media:ListStatusbars()) do
            if n ~= skip then out[#out + 1] = n end
        end
        return out
    end
end

-- One glow's look (Glows.lua's shape) on a settings table `t` - the dispel
-- glow's or the shout glow's own set: style, colour, strength, reach,
-- thickness, offset, the wide halo, the pulse, and the moving styles' lines.
-- Controls a style does not use are dimmed. o: colourLabel, byType (the
-- dispel glow's colour-by-debuff-type switch), defColor { r, g, b, a }.
local function GlowLook(L, t, o)
    local D = ns.Glow and ns.Glow.DEFAULTS or {}
    local function val(k) local v = t[k] if v == nil then v = D[k] end return v end
    local style = val("style") or "edge"
    local edge, moving = style == "edge", (style == "pixel" or style == "autocast")
    Drops(L, { label = "Style", items = ns.Glow and ns.Glow.STYLES or {},
        get = function() return val("style") end, set = function(v) t.style = v Refresh() end })
    if o.byType then
        Checks(L, { { "Colour by debuff type (Magic blue, Curse purple, Poison green, Disease brown)",
            function() return t.byType ~= false end, function(v) t.byType = v Refresh() end } }, 1)
    end
    local dc = o.defColor or { 1, 1, 1, 1 }
    local cg, cs = Arr(t, "color", dc[1], dc[2], dc[3], dc[4])
    local cp = UI.ColorPicker(L.current, { label = o.colourLabel or "Colour", alpha = true, get = cg,
        set = function(r, g, b, a) cs(r, g, b, a) Apply() end })
    cp._zNatW = math.max(120, cp:GetWidth() or 0)
    Grid(L, { cp }, 2, M.ROW, M.ROW - 16, 16, FitInto)
    if o.byType then UI.SetEnabled(cp, t.byType == false) end
    local function S(label, k, lo, hi, step, fmt)
        return Slider(L.current, { label = label, min = lo, max = hi, step = step, format = fmt,
            get = function() return val(k) end, set = function(v) t[k] = v end })
    end
    local function Row(ws) Grid(L, ws, 2, 40, 10, 30, FitInto) end
    local PCT1 = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
    local str, reach = S("Strength", "alpha", 0.1, 1, 0.05, PCT1), S("Reach", "size", 1, 30, 1, PX)
    Row({ str, reach })
    UI.SetEnabled(reach, edge or style == "autocast")
    local thick, off = S("Thickness", "thickness", 1, 8, 1, PX), S("Offset from the edge", "offset", -6, 12, 1, PX)
    Row({ thick, off })
    UI.SetEnabled(thick, style == "pixel" or style == "solid")
    local wide = Check(L.current, "Wide soft halo", function() return val("wide") end, function(v) t.wide = v end)
    local pulse = Check(L.current, "Pulse", function() return val("pulse") end, function(v) t.pulse = v Refresh() end)
    Grid(L, { wide, pulse }, 2, M.ROW, M.ROW - M.CHECK, M.CHECK, FitInto)
    UI.SetEnabled(wide, edge)
    local sp = S("Pulse speed (one beat)", "pulseSpeed", 0.1, 2, 0.05, SEC)
    local dp = S("Pulse depth", "pulseDepth", 0, 0.9, 0.05, PCT1)
    Row({ sp, dp })
    UI.SetEnabled(sp, val("pulse"))
    UI.SetEnabled(dp, val("pulse"))
    local n = S(style == "autocast" and "Sparkles" or "Lines", "lines", 1, 20, 1)
    local len = S("Line length", "length", 2, 30, 1, PX)
    Row({ n, len })
    local spd = S("Speed (laps a second)", "speed", 0.05, 1.5, 0.05, function(v) return string.format("%.2f", v) end)
    Row({ spd })
    UI.SetEnabled(n, moving)
    UI.SetEnabled(len, style == "pixel")
    UI.SetEnabled(spd, moving)
end

-- ============================================================================
-- TABS
-- ============================================================================
local function TabGeneral(L)
    local db = ns.db
    local key, cfg = FramePicker(L)
    local group = IsGroup(key)

    L:Card("Show on this frame")
    if key == "party" then
        Checks(L, {
            { "Show party frames", function() return cfg.enabled end, function(v) cfg.enabled = v end },
            { "Include yourself", function() return cfg.showPlayer end, function(v) cfg.showPlayer = v end },
            { "Show them in a raid too", function() return cfg.showInRaid end, function(v) cfg.showInRaid = v end },
        }, 3)
    elseif key == "raid" then
        Checks(L, {
            { "Show raid frames", function() return cfg.enabled end, function(v) cfg.enabled = v end },
            { "Include yourself", function() return cfg.showPlayer end, function(v) cfg.showPlayer = v end },
        }, 2)
    else
        Checks(L, { { "Show this frame", function() return cfg.enabled end, function(v) cfg.enabled = v end } }, 1)
    end
    local show = {
        { "Power bar", function() return cfg.power end, function(v) cfg.power = v end },
        { "Name",      function() return cfg.name end, function(v) cfg.name = v end },
        { "Buffs",     function() return cfg.showBuffs end, function(v) cfg.showBuffs = v end },
        { "Debuffs",   function() return cfg.showDebuffs end, function(v) cfg.showDebuffs = v end },
        { "Castbar",   function() return cfg.castbar end, function(v) cfg.castbar = v end },
        { "Incoming heals", function() return cfg.healPrediction end, function(v) cfg.healPrediction = v end },
    }
    if group then
        show[#show + 1] = { "Fade out of range", function() return cfg.rangeFade end, function(v) cfg.rangeFade = v end }
    end
    Checks(L, show, 4)
    Drops(L, { label = "Health text", items = HEALTH_TEXT,
        get = function() return cfg.healthText end, set = function(v) cfg.healthText = v end })
    L:Desc("Switching a frame on or off, and the party and raid layout, take a reload; everything else changes at once.")
    Button(L, "Reload UI", 100, function() if not InCombatLockdown() then ReloadUI() end end)
    L:EndCard()

    if not group and key ~= "softtarget" then
        L:Card("When this frame shows")
        local vg, vs = Access(cfg, "visibility", nil)
        L:Add(UI.VisibilityPicker(L.current, { width = InnerWidth(L), get = vg, set = vs }), 8)
        L:Desc("Fades the frame by the rule: it still takes clicks while faded out, so it can never lock you out of targeting in combat.")
        L:EndCard()
    end

    L:Card("Status icons on this frame")
    Checks(L, {
        { "Combat",      function() return cfg.combatIcon end, function(v) cfg.combatIcon = v end },
        { "Leader",      function() return cfg.leaderIcon end, function(v) cfg.leaderIcon = v end },
        { "Role",        function() return cfg.roleIcon end,   function(v) cfg.roleIcon = v end },
        { "Raid marker", function() return cfg.raidIcon end,   function(v) cfg.raidIcon = v end },
        { "PvP",         function() return cfg.pvpIcon end,    function(v) cfg.pvpIcon = v end },
        { "Resurrection", function() return cfg.rezIcon end,   function(v) cfg.rezIcon = v end },
    }, 4)
    L:Desc("Place and size each one on the Position tab. PvP shows while the mouse is over the frame.")
    L:EndCard()

    local ac = db.auras
    ac.buffList = ac.buffList or {}
    ac.debuffList = ac.debuffList or {}
    L:Card("Auras (all frames)")
    L:Desc("Turn buffs and debuffs on per frame above.")
    Checks(L, {
        { "Only my debuffs", function() return ac.onlyMine end, function(v) ac.onlyMine = v end },
        { "Only debuffs I can remove", function() return ac.dispellableOnly end, function(v) ac.dispellableOnly = v end },
    }, 2)
    Checks(L, { { "Colour the border by debuff type when I can remove it",
        function() return ac.dispelHighlight end, function(v) ac.dispelHighlight = v end } }, 1)
    L:Desc("The preview shows the border colour whatever your class can remove.")
    L:EndCard()

    local dg = db.dispelGlow
    if dg then
        L:Card("Dispel glow (all frames)")
        Checks(L, {
            { "Glow round a frame when I can remove its debuff", function() return dg.enabled end, function(v) dg.enabled = v end },
            { "Only when I'm in range", function() return dg.onlyInRange end, function(v) dg.onlyInRange = v end },
        }, 2)
        local can = ns.PlayerDispels and ns.PlayerDispels()
        local list = {}
        for _, k in ipairs({ "Magic", "Curse", "Poison", "Disease" }) do if can and can[k] then list[#list + 1] = k end end
        L:Desc(#list > 0 and ("Right now you can remove: " .. table.concat(list, ", ") .. ".")
            or "Right now you can't remove any debuffs (a warlock's Felhunter counts while it is out).")
        L:Desc("Out of range the glow is hidden; the frame's range fade already dims it. While a Challenging Shout glows on a frame, the shout wins for its six seconds. Its look is on the Look tab.")
        L:EndCard()
    end

    L:Card("Aura filter")
    Checks(L, { { "Only show the buffs and debuffs listed below",
        function() return ac.filterEnabled end, function(v) ac.filterEnabled = v end } }, 1)
    AuraList(L, "Buffs to show", ac.buffList)
    L:Gap(6)
    AuraList(L, "Debuffs to show", ac.debuffList)
    L:EndCard()

    L:Card("Shout alert")
    Checks(L, {
        { "Glow on a Challenging Shout or Roar", function() return db.shoutAlert.enabled end,
          function(v) db.shoutAlert.enabled = v if ns.ShoutAlertApply then ns.ShoutAlertApply() end end },
        { "Say it out loud", function() return db.shoutAlert.tts end, function(v) db.shoutAlert.tts = v end },
        { "Countdown on the frame", function() return db.shoutAlert.countdown ~= false end, function(v) db.shoutAlert.countdown = v end },
    }, 3)
    Buttons(L, {
        { "Test on my frames", 140, function() if ns.ShoutAlertTest then ns.ShoutAlertTest() end end },
        { "Test voice", 100, function() if ns.Speak then ns.Speak("Testing voice", true) end end },
    })
    L:Desc("Lights every frame showing the group member who taunted, with the seconds left of the six. The voice is ZacUI's one voice, picked on the General page. The glow's look is on the Look tab, the countdown's font and spot on Text.")
    L:EndCard()

    local lh = db.lowHealth
    if lh then
        L:Card("Low-health warning (your frame)")
        Checks(L, {
            { "On",    function() return lh.enabled end, function(v) lh.enabled = v end },
            { "Speak", function() return lh.tts end,     function(v) lh.tts = v end },
            { "Wash",  function() return lh.glow end,    function(v) lh.glow = v end },
            { "Pulse", function() return lh.pulse end,   function(v) lh.pulse = v end },
        }, 4)
        Sliders(L,
            { label = "Below this health", min = 5, max = 90, format = PCT, get = function() return lh.threshold end, set = function(v) lh.threshold = v end },
            { label = "Say it again every (0 = once)", min = 0, max = 20, format = function(v) return v == 0 and "once" or (v .. "s") end,
              get = function() return lh.ttsRepeat end, set = function(v) lh.ttsRepeat = v end })
        local says = UI.Font(L.current, F.SMALL, { text = "Says", cat = "text", key = "gray" })
        L:Row(says, 15)
        local box = UI.EditBox(L.current, { width = 260, text = lh.ttsText or "",
            onChange = function(t) lh.ttsText = t or "" end,
            onEnter = function(t) lh.ttsText = t or "" end })
        L:Row(box, M.EDIT_H and (M.EDIT_H + 6) or 26)
        Button(L, "Test", 80, function() if ns.LowHealthTest then ns.LowHealthTest() end end)
        L:Desc("A wash over your frame that grows from nothing at the threshold to full at 0% health. It repeats only in combat, and only once you've dropped lower than the last callout. Colour and strength are on the Look tab, the pulse on Animation.")
        L:EndCard()
    end
end

local function TabLook(L)
    local db = ns.db
    local key, cfg = FramePicker(L)
    local group = IsGroup(key)

    L:Card("Size of this frame")
    if key == "raid" then
        Sliders(L,
            { label = "Width", min = 50, max = 200, format = PX, get = function() return cfg.width end, set = function(v) cfg.width = v end },
            { label = "Height", min = 20, max = 80, format = PX, get = function() return cfg.height end, set = function(v) cfg.height = v end })
    elseif key == "party" then
        Sliders(L,
            { label = "Width", min = 80, max = 320, format = PX, get = function() return cfg.width end, set = function(v) cfg.width = v end },
            { label = "Height", min = 20, max = 80, format = PX, get = function() return cfg.height end, set = function(v) cfg.height = v end })
    else
        Sliders(L,
            { label = "Width", min = 60, max = 320, format = PX, get = function() return cfg.width end, set = function(v) cfg.width = v end },
            { label = "Height", min = 16, max = 80, format = PX, get = function() return cfg.height end, set = function(v) cfg.height = v end })
    end
    L:EndCard()

    L:Card("Colours of this frame")
    Checks(L, {
        { "Class colour health", function() return cfg.healthClassColor end, function(v) cfg.healthClassColor = v end },
        { "Class colour name", function() return cfg.nameClassColor end, function(v) cfg.nameClassColor = v end },
    }, 2)
    local hg, hs = Arr(cfg, "healthColor", 0.2, 0.2, 0.2, 1)
    local ng, nset = Arr(cfg, "nameColor", 1, 1, 1, 1)
    local bg, bset = Arr(cfg, "bgColor", 0.06, 0.06, 0.06, 0.85)
    local brg, brs = Arr(cfg, "borderColor", 0, 0, 0, 1)
    Colours(L, {
        { "Health colour", hg, hs, true }, { "Name colour", ng, nset, true },
        { "Background", bg, bset, true }, { "Border", brg, brs, false },
    })
    L:Desc("Class colour gives players their class colour and creatures their reaction colour; with it off, the flat colours are used.")
    if group then
        Sliders(L, { label = "Out of range opacity", min = 0, max = 100, step = 5, format = PCT,
            get = function() return math.floor((ns.RangeAlpha and ns.RangeAlpha(cfg) or 0.4) * 100 + 0.5) end,
            set = function(v) cfg.rangeAlpha = v / 100 end })
        L:Desc("How see-through a member out of range is, with Fade out of range on.")
    end
    L:EndCard()

    L:Card("Bars (all frames)")
    local bar = UI.TexturePicker(L.current, { label = "Bar texture", width = 260, defaultLabel = "Blizzard",
        list = BarList("Blizzard"),
        defaultPath = function() return ns.Media:Statusbar("Blizzard") end,
        get = function() return db.media.bar ~= "Blizzard" and db.media.bar or nil end,
        set = function(v) db.media.bar = v or "Blizzard" Apply() end,
        color = function() return ns.HealthColorFor(ns.db.frames.player, true, select(2, UnitClass("player"))) end })
    L:Add(bar, 8)
    local hbg, hbs = Arr(db.colors, "healthBg", 0.08, 0.08, 0.08, 0.9)
    local htg, hts = Arr(db.colors, "healthText", 0.85, 0.85, 0.85, 1)
    Colours(L, { { "Health background", hbg, hbs, true }, { "Health text", htg, hts, true } })
    Sliders(L, { label = "Power bar height", min = 1, max = 16, format = PX, get = function() return db.power.height end, set = function(v) db.power.height = v end })
    local pbg, pbs = Arr(db.colors, "powerBg", 0, 0, 0, 0.6)
    Colours(L, { { "Power background", pbg, pbs, true } })
    L:Desc("ZacUI > Fonts & Textures can set the bar texture for everything at once.")
    L:EndCard()

    L:Card("Name strip (all frames)")
    Checks(L, { { "Show a strip behind the name", function() return db.name.showStrip end, function(v) db.name.showStrip = v end } }, 1)
    local strip = UI.TexturePicker(L.current, { label = "Strip texture", width = 260, defaultLabel = "Blizzard",
        list = BarList("Blizzard"),
        defaultPath = function() return ns.Media:Statusbar("Blizzard") end,
        get = function() return db.media.nameBar ~= "Blizzard" and db.media.nameBar or nil end,
        set = function(v) db.media.nameBar = v or "Blizzard" Apply() end,
        color = function() local c = db.colors.nameBg return c[1], c[2], c[3] end })
    L:Add(strip, 8)
    Sliders(L, { label = "Strip height", min = 8, max = 28, format = PX, get = function() return db.name.height end, set = function(v) db.name.height = v end })
    local sg, ss = Arr(db.colors, "nameBg", 0.1, 0.1, 0.1, 0.85)
    Colours(L, { { "Strip tint", sg, ss, true } })
    L:EndCard()

    local ac = db.auras
    L:Card("Aura icons (all frames)")
    Sliders(L,
        { label = "Icon size", min = 10, max = 36, format = PX, get = function() return ac.size end, set = function(v) ac.size = v end },
        { label = "Most icons", min = 1, max = 12, get = function() return ac.max end, set = function(v) ac.max = v end })
    Sliders(L,
        { label = "Icons per row", min = 1, max = 12, get = function() return ac.perRow end, set = function(v) ac.perRow = v end },
        { label = "Gap between icons", min = 0, max = 10, format = PX, get = function() return ac.spacing or 2 end, set = function(v) ac.spacing = v end })
    local abg, abs = Arr(ac, "borderColor", 0, 0, 0, 1)
    local acg, acs = Arr(ac, "countColor", 0.85, 0.85, 0.85, 1)
    Colours(L, { { "Icon border", abg, abs, true }, { "Stack number", acg, acs, true } })
    L:EndCard()

    local cc = db.castbar
    L:Card("Castbar (all frames)")
    L:Desc("Turn it on per frame on the General tab; place and size it per frame on Position.")
    Checks(L, {
        { "Show the spell icon", function() return cc.showIcon end, function(v) cc.showIcon = v end },
        { "Show the time left", function() return cc.showTime end, function(v) cc.showTime = v end },
    }, 2)
    Sliders(L, { label = "Height", min = 8, max = 32, format = PX, get = function() return cc.height end, set = function(v) cc.height = v end })
    local ctex = UI.TexturePicker(L.current, { label = "Castbar texture", width = 260, defaultLabel = "Same as the bars",
        list = BarList(),
        defaultPath = function() return ns.Media:Statusbar(db.media.bar) end,
        get = function() return cc.texture end,
        set = function(v) cc.texture = v Apply() end,
        color = function() local c = db.colors.castbar return c[1], c[2], c[3] end })
    L:Add(ctex, 8)
    local cg, cs = Arr(db.colors, "castbar", 0.25, 0.45, 0.8, 1)
    local nig, nis = Arr(db.colors, "castbarNoInt", 0.7, 0.3, 0.3, 1)
    local cbg, cbs = Arr(cc, "bgColor", 0, 0, 0, 0.7)
    local cbrg, cbrs = Arr(cc, "borderColor", 0, 0, 0, 1)
    local ctg, cts = Arr(cc, "textColor", 0.85, 0.85, 0.85, 1)
    Colours(L, {
        { "Cast colour", cg, cs, true }, { "Can't be interrupted", nig, nis, true },
        { "Background", cbg, cbs, true }, { "Border", cbrg, cbrs, true },
        { "Text", ctg, cts, true },
    })
    L:EndCard()

    if db.dispelGlow then
        L:Card("Dispel glow look (all frames)")
        GlowLook(L, db.dispelGlow, { byType = true, colourLabel = "Colour (when not by type)" })
        L:Desc("Edge glow is the warrior HUD's buff-bar glow. The preview's player, party and raid samples carry a debuff you could remove.")
        L:EndCard()
    end

    L:Card("Shout glow look (all frames)")
    GlowLook(L, db.shoutAlert, { colourLabel = "Colour", defColor = { 1, 0.45, 0.05, 0.9 } })
    L:Desc("The party and raid previews and the Animation tab show it, with its countdown. Tint only is the old wash; its throb is on the Animation tab.")
    L:EndCard()

    L:Card("Alerts (all frames)")
    local lh = db.lowHealth
    local wg, ws = Arr(lh, "glowColor", 1, 0.1, 0.1, 1)
    Colours(L, { { "Low-health wash", wg, ws, false } })
    Sliders(L, { label = "Wash strength at 0% health", min = 0.1, max = 1, step = 0.05,
        format = function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
        get = function() return lh.glowMax end, set = function(v) lh.glowMax = v end })
    L:Desc("The Animation tab's preview shows both alerts.")
    L:EndCard()
end

local function TabText(L)
    local db = ns.db
    local Z = ZC()
    local key, cfg = FramePicker(L)
    L:Card("Font")
    -- one font: every frame text wears ZacUI's font (a face an old save
    -- picked here is kept in media.font, and ignored)
    local face = UI.Field(L.current, "Unit frames font", function(h)
        return UI.OneFontNote(h, 260)
    end, { width = 260 })
    L:Add(face, 8)
    L:Desc("Every text on the frames is in ZacUI's font (Fonts & Textures). Each text below keeps its own size, outline and shadow.")
    if not ns.Media:HasLSM() then
        L:Desc("SharedMedia isn't loaded - the game's own fonts and textures still work.")
    end
    L:EndCard()

    -- one group per text: its font (all frames), then its format and its
    -- position on the frame picked above
    local function Text(title, o)
        L:Card(title)
        local ag, as = Access(cfg, "anchors", o.key)
        o.anchorGet, o.anchorSet = ag, as
        o.anchorDefaults = o.anchorDefaults or AnchorDef(cfg, o.key)
        o.targets = o.targets or TargetsFor(o.key)
        o.defaultTargetLabel = "Where it sits now"
        o.fontDefaultLabel = "Unit frames font"
        UI.TextElement(L, o)
        if o.desc then L:Desc(o.desc) end
        L:EndCard()
    end

    local fg, fs, fd = FontBinding("name", 12, function() return db.name.size end, function(v) db.name.size = v end)
    local ng, nset = Access(cfg, "formats", "name")
    Text("Name", { key = "name", fontGet = fg, fontSet = fs, fontDefaults = fd, sample = "Zaccw  Holyclone",
        formatGet = ng, formatSet = nset, formatKinds = { name = true },
        formatSample = function(spec) return Z.FormatText(spec, nil, { name = "Zaccwarrior" }, { name = "name" }, "name") end,
        desc = "The font is for every frame; the format and the position are for this frame. Its colour is per frame, on the Look tab." })

    fg, fs, fd = FontBinding("health", 11)
    local hg, hset = Access(cfg, "formats", "healthText")
    local cg, cset = ArrColor(db.colors, "healthText", 0.85, 0.85, 0.85, 1)
    Text("Health text", { key = "healthText", fontGet = fg, fontSet = fs, fontDefaults = fd, sample = "72%  3.0k  Dead",
        colorGet = cg, colorSet = cset, colorLabel = "Colour (all frames)",
        formatGet = hg, formatSet = hset, formatKinds = { number = true, percent = true }, formatTokens = ns.HP_FORMAT_TOKENS,
        formatSample = function(spec)
            return Z.FormatText(spec, ns.HP_FORMAT_DEFAULTS[cfg.healthText] or ns.HP_FORMAT_DEFAULTS.percent,
                { cur = 30500, max = 42000, deficit = 11500, pct = 72.6 }, ns.HP_FORMAT_KINDS)
        end,
        desc = "What it shows is the Health text choice on the General tab; the format changes how it reads." })

    fg, fs, fd = FontBinding("castbar", 11)
    local tg, tset = ArrColor(db.castbar, "textColor", 0.85, 0.85, 0.85, 1)
    Text("Castbar spell name", { key = "castText", fontGet = fg, fontSet = fs, fontDefaults = fd, sample = "Hearthstone  1.5",
        colorGet = tg, colorSet = tset, colorLabel = "Colour (all frames)" })
    Text("Castbar time", { key = "castTime", desc = "It shares the spell name's font and colour." })

    fg, fs, fd = FontBinding("auraCount", 10)
    local acg, acs = ArrColor(db.auras, "countColor", 0.85, 0.85, 0.85, 1)
    local cag, cas = Access(db.auras, "anchors", "count")
    L:Card("Aura stack number")
    UI.TextElement(L, { key = "auraCount", fontGet = fg, fontSet = fs, fontDefaults = fd, sample = "5  3  2",
        fontDefaultLabel = "Unit frames font",
        colorGet = acg, colorSet = acs, colorLabel = "Colour",
        anchorGet = cag, anchorSet = cas, anchorDefaults = ns.AURA_COUNT_DEF, min = -20, max = 20 })
    L:Desc("For every frame: where the number sits on each aura icon.")
    L:EndCard()

    local sa = db.shoutAlert
    L:Card("Shout countdown")
    FontPick(L, "Font", "tauntCount", 16, "6  5  4  3")
    Drops(L, { label = "Where it sits", items = ns.COUNT_POINTS or {},
        get = function() return sa.countPoint or "CENTER" end, set = function(v) sa.countPoint = v end })
    local ccg, ccs = Arr(sa, "countColor", 1, 1, 1, 1)
    Colours(L, { { "Colour", ccg, ccs, true } })
    Checks(L, { { "Show tenths of a second", function() return sa.countTenths end, function(v) sa.countTenths = v end } }, 1)
    L:Desc("The seconds left of a Challenging Shout or Roar, on the frames it lights. The Animation tab's Shout alert preview shows it ticking.")
    L:EndCard()

    Text("PvP text", { key = "pvpText" })
    Text("Incoming heal number", { key = "healTotal",
        desc = "Its font, size and colours are on the Heals tab." })
end

local function TabAnimation(L)
    local db = ns.db
    local PV = ns.UFPreview
    L:Preview({
        key = "unitframes.motion",
        title = "Animations",
        width = 400, height = 70,
        modes = PV.MOTION_MODES, modesLabel = "Show",
        build = PV.BuildMotion, update = PV.UpdateMotion, replay = PV.ReplayMotion,
    })

    local cc = db.castbar
    L:Card("Castbar")
    L:Add(UI.AnimationPicker(L.current, { width = InnerWidth(L), label = "When a cast starts",
        styles = { "none", "fade", "slide", "pop", "bounce" },
        get = function() return cc.showAnim end,
        set = function(s) cc.showAnim = s end }), 10)
    L:Add(UI.AnimationPicker(L.current, { width = InnerWidth(L), label = "When a cast ends",
        styles = { "none", "fade", "slide", "pop", "bounce", "flash" },
        get = function() return cc.hideAnim end,
        set = function(s) cc.hideAnim = s end }), 6)
    L:Desc("None is instant, as castbars have always been.")
    L:EndCard()

    L:Card("Shout alert glow")
    L:Add(UI.AnimationPicker(L.current, { width = InnerWidth(L), label = "How it throbs",
        styles = { "none", "flash", "pulse" },
        get = function() return db.shoutAlert.anim end,
        set = function(s) db.shoutAlert.anim = s end }), 6)
    L:Desc("For the Tint only style (the old wash). Turn Repeat off for a single beat when it lights; None glows steadily. The other styles breathe by the pulse settings on the Look tab, as does the dispel glow.")
    L:EndCard()

    local lh = db.lowHealth
    L:Card("Low-health wash")
    Checks(L, { { "Pulse the wash", function() return lh.pulse end, function(v) lh.pulse = v Refresh() end } }, 1)
    local pp = UI.AnimationPicker(L.current, { width = InnerWidth(L), label = "How it pulses",
        styles = { "none", "flash", "pulse" },
        get = function() return lh.pulseAnim end,
        set = function(s) lh.pulseAnim = s Apply() end })
    L:Add(pp, 6)
    UI.SetEnabled(pp, lh.pulse)
    L:EndCard()

    L:Card("Health and power bars")
    Checks(L, { { "Smooth bars - glide to a new value instead of jumping",
        function() return db.smoothBars ~= false end, function(v) db.smoothBars = v Refresh() end } }, 1)
    local glide = UI.Slider(L.current, { width = 220, min = 0.05, max = 0.6, step = 0.01,
        value = tonumber(db.smoothTime) or 0.15, label = "Glide time", format = SEC,
        onChange = function(v) db.smoothTime = math.floor(v * 100 + 0.5) / 100 end })
    L:Row(glide, 40)
    UI.SetEnabled(glide, db.smoothBars ~= false)
    L:EndCard()

    L:Card("Everywhere")
    L:Desc("Appearance > Motion turns every ZacUI animation off or speeds them all up; these follow it.")
    L:EndCard()
end

local function TabPosition(L)
    local db = ns.db
    local key, cfg = FramePicker(L)

    L:Card("Move the frames")
    Buttons(L, {
        { (db.locked == false) and "Lock frames" or "Move frames", 130, function()
            if ns.ToggleMoveMode then ns.ToggleMoveMode() end
            Refresh()
        end, "Unlocks the frames to drag (snapping to a grid) and opens the position dialog. Click again to lock (/zmove)." },
        { "Position dialog", 130, function() if ns.ToggleMoveDialog then ns.ToggleMoveDialog() end end,
          "Exact coordinates for every frame, and raid groups per row." },
        { "Reload UI", 100, function() if not InCombatLockdown() then ReloadUI() end end },
    })
    L:Desc("In move mode party and raid placeholders show when you're not in a group, so the layout can be seen.")
    L:EndCard()

    if key == "party" then
        L:Card("Party layout")
        Sliders(L, { label = "Spacing", min = 0, max = 24, format = PX, get = function() return cfg.spacing end, set = function(v) cfg.spacing = v end })
        Drops(L,
            { label = "Grow", items = { { text = "Down", value = "DOWN" }, { text = "Up", value = "UP" } },
              get = function() return cfg.growth end, set = function(v) cfg.growth = v end },
            { label = "Sort by", items = { { text = "Group order", value = "Index" }, { text = "Name", value = "Name" } },
              get = function() return cfg.sortMethod end, set = function(v) cfg.sortMethod = v end })
        Drops(L, { label = "Order", items = { "Ascending", "Descending" }, get = function() return cfg.sortDir end, set = function(v) cfg.sortDir = v end })
        L:EndCard()
        L:Card("Party position")
        L:Desc("Or drag the handle in move mode.")
        Sliders(L,
            { label = "X", min = -1200, max = 1200, step = 2, format = PX, get = function() return cfg.x end, set = function(v) setHeaderPos("party", "x", v) end },
            { label = "Y", min = -1200, max = 1200, step = 2, format = PX, get = function() return cfg.y end, set = function(v) setHeaderPos("party", "y", v) end })
        L:EndCard()
    elseif key == "raid" then
        L:Card("Raid layout")
        Sliders(L,
            { label = "Units per column", min = 1, max = 40, get = function() return cfg.unitsPerColumn end, set = function(v) cfg.unitsPerColumn = v end },
            { label = "Groups per row", min = 1, max = 8, get = function() return cfg.maxColumns end, set = function(v) cfg.maxColumns = v end })
        Sliders(L,
            { label = "Row spacing", min = 0, max = 20, format = PX, get = function() return cfg.spacing end, set = function(v) cfg.spacing = v end },
            { label = "Column spacing", min = 0, max = 20, format = PX, get = function() return cfg.columnSpacing end, set = function(v) cfg.columnSpacing = v end })
        Drops(L,
            { label = "Grow", items = { { text = "Down", value = "DOWN" }, { text = "Up", value = "UP" } },
              get = function() return cfg.growth end, set = function(v) cfg.growth = v end },
            { label = "Columns grow", items = { { text = "Right", value = "RIGHT" }, { text = "Left", value = "LEFT" } },
              get = function() return cfg.columnGrowth end, set = function(v) cfg.columnGrowth = v end })
        Drops(L,
            { label = "Sort by", items = { { text = "Group order", value = "Index" }, { text = "Name", value = "Name" } },
              get = function() return cfg.sortMethod end, set = function(v) cfg.sortMethod = v end },
            { label = "Order", items = { "Ascending", "Descending" }, get = function() return cfg.sortDir end, set = function(v) cfg.sortDir = v end })
        Checks(L, { { "Group by subgroup - each group its own column (reload to switch)",
            function() return cfg.groupBy end, function(v) cfg.groupBy = v end } }, 1)
        L:EndCard()

        L:Card("Line up with chat")
        Checks(L, { { "Left and right edges on the chat window's (sets width and position; height stays)",
            function() return cfg.fitChat end,
            function(v) cfg.fitChat = v if v and ns.FitRaidToChat then ns.FitRaidToChat() end end } }, 1)
        Sliders(L, { label = "Gap above chat", min = 0, max = 40, format = PX, get = function() return cfg.fitGap or 4 end,
            set = function(v) cfg.fitGap = v if ns.FitRaidToChat then ns.FitRaidToChat() end end })
        L:EndCard()

        L:Card("Raid position")
        L:Desc("Or drag the handle in move mode; Line up with chat overrides it.")
        Sliders(L,
            { label = "X", min = -1200, max = 1200, step = 2, format = PX, get = function() return cfg.x end, set = function(v) setHeaderPos("raid", "x", v) end },
            { label = "Y", min = -1200, max = 1200, step = 2, format = PX, get = function() return cfg.y end, set = function(v) setHeaderPos("raid", "y", v) end })
        L:EndCard()
    else
        L:Card("Position of this frame")
        L:Desc("From the middle of the screen. Or drag it in move mode.")
        Sliders(L,
            { label = "X", min = -1000, max = 1000, step = 2, format = PX, get = function() return cfg.x end, set = function(v) setFramePos(key, "x", v) end },
            { label = "Y", min = -1000, max = 1000, step = 2, format = PX, get = function() return cfg.y end, set = function(v) setFramePos(key, "y", v) end })
        L:EndCard()
    end

    L:Card("Place and size an element on this frame")
    L:Desc("Pick the element, then set its anchor, offset and size.")
    PosPicker(L, cfg, key)
    L:EndCard()

    -- every part, freely: any corner of anything on the frame, on top of
    -- the preset above (the texts are on the Text tab)
    L:Card("Fine placement of this frame's parts")
    local sel = pick.part[key] or "castbar"
    local items = {}
    for _, k in ipairs(ns.ANCHOR_PARTS) do items[#items + 1] = { text = ns.ANCHOR_LABELS[k] or k, value = k } end
    Drops(L, { label = "Part", items = items, noApply = true,
        get = function() return sel end,
        set = function(v) pick.part[key] = v Refresh() end })
    local ag, as = Access(cfg, "anchors", sel)
    local o = { key = sel, anchorGet = ag, anchorSet = as, anchorDefaults = AnchorDef(cfg, sel),
        targets = TargetsFor(sel), defaultTargetLabel = "Where it sits now", anchorMin = -250, anchorMax = 250 }
    if POS_SIZE[sel] then
        local sk = POS_SIZE[sel]
        o.sizeGet = function() return cfg[sk] or 14 end
        o.sizeSet = function(v) cfg[sk] = v Apply() end
        o.sizeMin, o.sizeMax = 6, 40
    end
    UI.FrameElement(L, o)
    L:Desc("Reset puts the part back where the preset above places it.")
    L:EndCard()
end

local function TabHeals(L)
    local cfg = ns.db.heal
    local HC = ns.HealColors
    local PV = ns.UFPreview
    local hw, hh = PV.HealCanvasSize()
    L:Preview({
        key = "unitframes.heals",
        title = "Incoming heals",
        width = hw, height = hh,
        build = PV.BuildHeals, update = PV.UpdateHeals,
    })

    L:Card("Incoming heals")
    L:Desc(("Data source: %s.  %s"):format(
        tostring(ns.Heal and ns.Heal.backend or "none"),
        (ns.Heal and ns.Heal.backend == "LibHealPredict")
            and "Comms-free: every healer in the raid is tracked, whether or not they run an addon."
            or ((ns.Heal and ns.Heal.perCaster)
                and "Peer-to-peer: only shows heals from players also running a LibHealComm addon."
                or "This source reports totals only - chips cannot be split per healer.")))
    L:Desc("Turn heals on per frame on the General tab. The preview shows four frames: covered, exposed, not enough (with more healers than chips), and a healer wearing their legend dot.")
    Drops(L,
        { label = "Colour mode", items = { { text = "Class", value = "class" }, { text = "Slot", value = "slot" } },
          get = function() return HC:GetMode() end, set = function(v) HC:SetMode(v) end },
        { label = "Chip fill", items = { { text = "Healer's colour", value = "class" }, { text = "One colour", value = "uniform" } },
          get = function() return cfg.segment.fill end, set = function(v) cfg.segment.fill = v end })
    Drops(L, { label = "Marker", items = { { text = "None", value = "none" }, { text = "Dot", value = "dot" }, { text = "Initials", value = "initials" } },
        get = function() return cfg.segment.marker end, set = function(v) cfg.segment.marker = v end })
    L:Desc("Class mode gives every healer their class colour - the same on everyone's screen; tell same-class healers apart with a marker. Slot mode gives each healer their own colour instead.")
    Sliders(L,
        { label = "Look ahead", min = 1, max = 12, format = function(v) return v .. "s" end, get = function() return cfg.window end, set = function(v) cfg.window = v end },
        { label = "Most chips", min = 1, max = 8, get = function() return cfg.maxSegments end, set = function(v) cfg.maxSegments = v end })
    Sliders(L,
        { label = "Overheal past full", min = 0, max = 50, step = 5, format = PCT, get = function() return cfg.overheal end, set = function(v) cfg.overheal = v end },
        { label = "Chip opacity", min = 20, max = 100, step = 5, format = PCT,
          get = function() return math.floor((cfg.segment.alpha or 0.85) * 100 + 0.5) end,
          set = function(v) cfg.segment.alpha = v / 100 end })
    L:EndCard()

    L:Card("Your heals and heals over time")
    Checks(L, {
        { "Highlight my own heals", function() return cfg.ownHeal.enabled end, function(v) cfg.ownHeal.enabled = v HC:Flush() end },
        { "Show heals over time", function() return cfg.hot.show end, function(v) cfg.hot.show = v end },
        { "One colour for every heal over time", function() return cfg.hot.uniform end, function(v) cfg.hot.uniform = v end },
    }, 2)
    Checks(L, { { "Precise heal-over-time timing (reads the combat log)",
        function() return cfg.preciseHots end, function(v) cfg.preciseHots = v end } }, 1)
    local og, oset = Arr(cfg.ownHeal, "color")
    local hg, hs = Arr(cfg.hot, "color")
    Colours(L, { { "My heal colour", og, oset, false }, { "Heal over time colour", hg, hs, false } })
    L:Desc("Heals over time are dimmed against direct heals either way. Precise timing takes tick times from the combat log instead of aura refreshes - more accurate, a little more work per event.")
    L:EndCard()

    L:Card("Chip appearance")
    Checks(L, {
        { "White spark at the health edge", function() return cfg.segment.spark end, function(v) cfg.segment.spark = v end },
        { "Outline each chip", function() return cfg.segment.outline end, function(v) cfg.segment.outline = v end },
    }, 2)
    Drops(L,
        { label = "Texture", items = { { text = "Flat", value = "flat" }, { text = "Glossy", value = "glossy" } },
          get = function() return cfg.segment.texture end, set = function(v) cfg.segment.texture = v end },
        { label = "Layer", items = { { text = "Behind the text", value = "behind" }, { text = "Over the text", value = "front" } },
          get = function() return cfg.segment.layer end, set = function(v) cfg.segment.layer = v end })
    local ug, us = Arr(cfg.segment, "uniformColor")
    local ig, is = Arr(ns.db.colors, "incomingHeal", 0.3, 0.78, 0.42, 0.55)
    Colours(L, { { "One-colour fill", ug, us, false }, { "Unknown healer", ig, is, true } })
    L:Desc("Behind the text keeps the name and health readable on top of the chips. Unknown healer colours a heal when the data source can't say who cast it.")
    L:EndCard()

    local tc = cfg.total
    L:Card("Incoming heal number")
    Checks(L, {
        { "Show the total as a number", function() return tc.enabled end, function(v) tc.enabled = v end },
        { "Leading \"+\"", function() return tc.prefix end, function(v) tc.prefix = v end },
        { "Add the health % it lands you at", function() return tc.showProjected end, function(v) tc.showProjected = v end },
    }, 2)
    local anchors = { { text = "Left of the health text", value = "LEFT_OF_HP" }, { text = "Right of the health text", value = "RIGHT_OF_HP" } }
    for _, v in ipairs(NINE_OPT) do anchors[#anchors + 1] = { text = v, value = v } end
    Drops(L,
        { label = "Anchor", items = anchors, get = function() return tc.anchor end, set = function(v) tc.anchor = v end },
        { label = "Number format", items = { { text = "Auto", value = "auto" }, { text = "Full", value = "full" }, { text = "Short (12.3k)", value = "short" } },
          get = function() return tc.format end, set = function(v) tc.format = v end })
    Sliders(L,
        { label = "X offset", min = -100, max = 100, format = PX, get = function() return tc.x end, set = function(v) tc.x = v end },
        { label = "Y offset", min = -100, max = 100, format = PX, get = function() return tc.y end, set = function(v) tc.y = v end })
    FontPick(L, "Font", "healTotal", 11, "+2400  98%",
        function() return tc.size end, function(v) tc.size = math.max(6, v) end)
    L:EndCard()

    L:Card("Number colour - what it tells you")
    Drops(L, { label = "Colour by", items = { { text = "Coverage", value = "coverage" }, { text = "Overheal", value = "overheal" }, { text = "One colour", value = "flat" } },
        get = function() return tc.colorMode end, set = function(v) tc.colorMode = v end })
    L:Desc("Coverage: where the incoming heals land you - green tops you off, yellow helps but you are still exposed, red will not save you. Overheal: amber once incoming is more than missing health. One colour: always the same.")
    Sliders(L,
        { label = "Safe at health", min = 50, max = 100, step = 5, format = PCT, get = function() return tc.safePct end, set = function(v) tc.safePct = v end },
        { label = "Exposed below", min = 10, max = 90, step = 5, format = PCT, get = function() return tc.partialPct end, set = function(v) tc.partialPct = v end })
    local sg, ss = Arr(tc, "safeColor")
    local pg, ps = Arr(tc, "partialColor")
    local lg, ls = Arr(tc, "lowColor")
    local fg, fs = Arr(tc, "color")
    local vg, vs = Arr(tc, "overhealColor")
    Colours(L, {
        { "Covered (send)", sg, ss, false }, { "Exposed", pg, ps, false },
        { "Not enough", lg, ls, false }, { "One colour / neutral", fg, fs, false },
        { "Overheal", vg, vs, false },
    })
    L:EndCard()

    L:Card("Healer legend dot")
    Checks(L, {
        { "Show the legend dot", function() return cfg.dot.enabled end, function(v) cfg.dot.enabled = v ns.RefreshHealerDots() end },
        { "Hide it in combat", function() return cfg.dot.hideInCombat end, function(v) cfg.dot.hideInCombat = v ns.RefreshHealerDots() end },
    }, 2)
    Drops(L, { label = "Position", items = {
            { text = "Left of the name", value = "LEFT_OF_NAME" }, { text = "Top left", value = "TOPLEFT" },
            { text = "Top right", value = "TOPRIGHT" }, { text = "Bottom left", value = "BOTTOMLEFT" },
            { text = "Bottom right", value = "BOTTOMRIGHT" } },
        get = function() return cfg.dot.position end, set = function(v) cfg.dot.position = v ns.RefreshHealerDots() end })
    Sliders(L, { label = "Dot size", min = 4, max = 20, format = PX,
        get = function() return cfg.dot.size end, set = function(v) cfg.dot.size = v ns.RefreshHealerDots() end })
    L:Desc("A dot on a healer's own frame in the colour their chips use, so you can read the chips at a glance.")
    L:EndCard()

    L:Card("Healer colours")
    L:Desc("Class mode - one colour per healing class:")
    local list = {}
    for _, class in ipairs(HC.CLASSES) do
        local k = class
        list[#list + 1] = { k:sub(1, 1) .. k:sub(2):lower(),
            function() local r, g, b = HC:ClassColor(k) return r, g, b, 1 end,
            function(r, g, b) HC:SetClassColor(k, r, g, b) end, false }
    end
    Colours(L, list)
    L:Desc("Slot mode - raid healers get a palette of their own; tank and support healers share one colour each:")
    list = {}
    for i = 0, 7 do
        local slot = i
        list[#list + 1] = { "Raid healer " .. (i + 1),
            function() local r, g, b = HC:RoleColor("raid", slot) return r, g, b, 1 end,
            function(r, g, b) HC:SetRoleColor("raid", slot, r, g, b) end, false }
    end
    for _, role in ipairs({ "tank", "support" }) do
        local r0 = role
        local label = (r0 == "tank" and "Tank healer" or "Support healer")
        local klass = HC:RoleClass(r0)
        if klass then label = label .. " (" .. klass:sub(1, 1) .. klass:sub(2):lower() .. ")" end
        list[#list + 1] = { label,
            function() local r, g, b = HC:RoleColor(r0, 0) return r, g, b, 1 end,
            function(r, g, b) HC:SetRoleColor(r0, 0, r, g, b) end, false }
    end
    Colours(L, list)
    Buttons(L, {
        { "Reset all heal colours", 170, function()
            HC:ResetAll()
            Apply()
            ns.Print("heal: colours reset to defaults.")
            local Z = ZUI()
            if Z and Z.SettingsChanged then Z.SettingsChanged("unitframes.healcolours") end
            Refresh()
        end },
        { "Forget slot assignments", 170, function()
            HC:ResetAssignments()
            Apply()
            ns.Print("heal: slot assignments cleared - healers claim colours again in the order they next heal.")
        end },
    })
    L:EndCard()
end

local function TabAdvanced(L)
    L:Card("Import / export a unit frames string")
    local status
    local box = UI.TextBox(L.current, { width = math.min(440, InnerWidth(L)), height = 90, selectOnFocus = true })
    L:Row(box, 98)
    local ZI = (ZUI() or {}).Import
    Buttons(L, {
        { "Export current", 130, function()
            box:SetText(ns.ExportString())
            box:Focus()
            if status then status:SetText("Ready to copy: Ctrl+A, Ctrl+C.") end
        end },
        { "Import from box", 130, function()
            if ZI and ZI.Redirect then
                local ok, taken = pcall(ZI.Redirect, box:GetText(), "unitframes")
                if ok and taken then return end
            end
            local text = box:GetText()
            if ZI and ZI.Clean then text = ZI.Clean(text) end
            if ZI and ZI.Identify then
                local fine, info = pcall(ZI.Identify, text)
                if fine and type(info) == "table" and info.kind == "unitframes" and not info.ready then
                    if status then status:SetText("Import failed: " .. tostring(info.problem or "the string could not be read") .. ".") end
                    return
                end
            end
            local ok, err = ns.ImportString(text)
            if ok then
                if not InCombatLockdown() then ReloadUI()
                elseif status then status:SetText("Imported - type /reload to apply (in combat).") end
            elseif status then
                status:SetText("Import failed: " .. (err or "unknown") .. ".")
            end
        end },
    })
    status = L:Desc("Export fills the box - Ctrl+A, Ctrl+C to copy. Paste a string and Import to apply it (reloads). Any other ZacUI or Readycheck string pasted here is sent where it belongs.")
    L:EndCard()

    L:Card("Saved unit frame profiles")
    local name = ""
    local row = NewRow(L, M.EDIT_H or 20)
    local eb = UI.EditBox(row, { width = 200, hint = "Profile name",
        onChange = function(t) name = t or "" end,
        onEnter = function(t)
            if ns.SaveProfile(t) then Refresh() end
        end })
    eb:SetPoint("LEFT")
    local save = UI.Button(row, "Save current", { width = 110, onClick = function()
        if ns.SaveProfile(name) then Refresh() end
    end })
    save:SetPoint("LEFT", eb, "RIGHT", 8, 0)
    L:Row(row, (M.EDIT_H or 20) + 8)
    local names = ns.ListProfiles()
    if #names == 0 then L:Desc("None saved yet.") end
    for _, nm in ipairs(names) do
        local r = NewRow(L, M.BUTTON_H)
        local t = UI.Font(r, F.LABEL, { text = nm })
        t:SetPoint("LEFT", 4, 0)
        local load = UI.Button(r, "Load", { width = 60, onClick = function()
            if ns.LoadProfile(nm) and not InCombatLockdown() then ReloadUI() end
        end })
        local del = UI.Button(r, "Delete", { width = 60, onClick = function()
            ns.DeleteProfile(nm)
            Refresh()
        end })
        -- the two buttons (as wide as their labels) sit at the right of what
        -- the card has room for; the name is cut short in what is left
        local bw = (load:GetWidth() or 60) + 6 + (del:GetWidth() or 60)
        local bx = math.max(40, math.min(230, InnerWidth(L) - bw))
        ClampText(r, t, bx - 10)
        load:SetPoint("LEFT", r, "LEFT", bx, 0)
        del:SetPoint("LEFT", load, "RIGHT", 6, 0)
        L:Row(r, M.BUTTON_H + 4)
    end
    L:Desc("These are the unit frames' own profiles; ZacUI > Profiles saves everything at once, these included.")
    L:EndCard()
end

local TABS = {
    { id = "general",  label = "General",   build = TabGeneral },
    { id = "look",     label = "Look",      build = TabLook },
    { id = "text",     label = "Text",      build = TabText },
    { id = "anim",     label = "Animation", build = TabAnimation },
    { id = "pos",      label = "Position",  build = TabPosition },
    { id = "heals",    label = "Heals",     build = TabHeals },
    { id = "adv",      label = "Advanced",  build = TabAdvanced },
}

-- The frames preview. Its mode is the page's frame; a mode clicked in the
-- dock (which only redraws the preview) rebuilds the page on the next frame
-- so the settings below follow it.
local function FramesPreviewSpec()
    local PV = ns.UFPreview
    local w, h = PV.FrameCanvasSize(CurrentFrame())
    return {
        key = PREVIEW_FRAMES,
        title = "Unit frames",
        width = w, height = h,
        modes = PV.FRAME_MODES, modesLabel = "Frame",
        build = PV.BuildFrames,
        update = function(canvas, P)
            PV.UpdateFrames(canvas, P)
            if P.mode and builtFor and P.mode ~= builtFor and PageOpen() then
                builtFor = P.mode
                C_Timer.After(0, function() if PageOpen() then Refresh() end end)
            end
        end,
        replay = PV.ReplayFrames,
    }
end

-- ============================================================================
-- THE ZACUI SIDE: the global font/texture target, Edit Mode, the page.
-- ============================================================================
do
    local ZUI = ns.ZUI or _G.ZacUI
    -- the global font and bar texture (ZacUI > Fonts & Textures) land in
    -- the unit frames' font, bar texture and name-strip texture
    if ZUI and ZUI.Media and ZUI.Media.RegisterTarget then
        ZUI.Media.RegisterTarget("unitframes", {
            label = "Unit frames",
            desc = "Frame font, bar texture and name-strip texture.",
            order = 10,
            -- still on its shipped font
            untouched = function()
                local f = ns.db and ns.db.media and ns.db.media.font
                return f == nil or f == "" or f == "Friz Quadrata TT"
            end,
            apply = function(font, bar, cleared)
                if not (ns.db and ns.db.media) then return end
                if font then ns.db.media.font = font
                elseif cleared then ns.db.media.font = "Friz Quadrata TT" end
                if bar then ns.db.media.bar = bar; ns.db.media.nameBar = bar end
                if ns.ApplySettings then ns.ApplySettings() end
            end,
        })
    end
    -- ZACUI'S EDIT MODE. The unit frames join the pass as one element:
    -- entering unlocks them through their own move mode (every frame
    -- shown and draggable, the party and raid previews up when you are
    -- not in one), leaving locks them again. ZacUI's grid is already on
    -- screen, so this one's grid and position dialog are not opened; the
    -- dialog (exact coordinates, raid groups per row) comes up when a
    -- frame is clicked - see ns.SelectMoveFrame. Only what was unlocked
    -- here is locked on the way out, so frames you unlocked yourself with
    -- /zmove before entering are left as you had them.
    if ZUI then
        ZUI.EditModeProviders = ZUI.EditModeProviders or {}
        -- what Edit Mode outlines and lines its guides up on: each single
        -- frame, and ONE box round a whole party or raid block (its handle,
        -- its real members and its previews). The same frames are what
        -- Edit Mode fades while the unit frames are hidden there.
        local function EditFrames()
            local list = {}
            for key, f in pairs(ns.frames) do
                if key == "party" or key == "raid" then
                    local u = {}
                    if f.mover then u[#u + 1] = f.mover end
                    for _, h in ipairs(f.headers or {}) do
                        for _, child in ipairs({ h:GetChildren() }) do u[#u + 1] = child end
                    end
                    local mf, n = nil, 0
                    if ns.MockFrames then mf, n = ns.MockFrames(key) end
                    for i = 1, n do u[#u + 1] = mf[i] end
                    if #u > 0 then list[#list + 1] = { union = u } end
                else
                    list[#list + 1] = f
                end
            end
            return list
        end
        ZUI.EditModeProviders[#ZUI.EditModeProviders + 1] = function()
            if not (ns.db and ns.frames and ns.ApplySettings) then return nil end
            return { {
                key = "unitframes",
                label = "Unit frames (player, target, party, raid)",
                show = function()
                    if ns.db.locked == false then return end
                    ns._zuiEdit = true
                    ns.db.locked = false
                    ns.ApplySettings()
                end,
                hide = function()
                    if not ns._zuiEdit then return end
                    ns._zuiEdit = nil
                    if ns.HideMoveDialog then ns.HideMoveDialog() end
                    ns.db.locked = true
                    ns.ApplySettings()
                end,
                frames = EditFrames,
                content = EditFrames,
            } }
        end
    end
    -- Search words that are not on the page itself (the labels and
    -- descriptions are indexed on their own). The sidebar entry is ZacUI's;
    -- this only adds to its keywords.
    if ZUI and ZUI.AddMenuKeywords then
        ZUI.AddMenuKeywords("unitframes", "colour color font fonts text outline shadow texture animation animate fade slide"
            .. " smooth glide range opacity dispel debuff buff aura filter shout taunt low health wash"
            .. " cleanse decurse cure glow edge pixel autocast sparkle countdown timer challenging roar"
            .. " pulse flash preview test tot pet focus marker skull leader assist tank rez resurrection"
            .. " pvp heal prediction healcomm chips legend profile import export zacuf")
    end
    if ZUI and ZUI.RegisterPage and ZUI.UI then
        UI, M, F = ZUI.UI, ZUI.UI.M, ZUI.UI.F
        ZUI.RegisterPage("UnitFrames", function(L)
            L:Header("Unit frames",
                "Player, target, target of target, pet, party and raid frames, with incoming heals. "
                .. "/zuf opens this page, /zmove toggles move mode, /zuf reset puts everything back.")
            if not ns.db then
                L:Notice("missing", "The unit frames have not loaded yet.")
                return
            end
            builtFor = CurrentFrame()
            -- a sample element picked in the preview: its controls
            local Zc = ZC()
            if Zc and Zc.CustomPick then
                Zc.CustomPick.SetHandler(PREVIEW_FRAMES, function(el)
                    local st = Zc.ConfigState and Zc.ConfigState()
                    if not st then return end
                    st.tabs = st.tabs or {}
                    local isText = false
                    for _, k in ipairs(ns.ANCHOR_TEXTS or {}) do if k == el then isText = true end end
                    -- the glows: their look; the countdown: its font and spot
                    if el == "dispelGlow" or el == "tauntGlow" then st.tabs.unitframes = "look"
                    elseif el == "tauntCount" then st.tabs.unitframes = "text"
                    elseif isText then st.tabs.unitframes = "text"
                    else
                        st.tabs.unitframes = "pos"
                        pick.part[CurrentFrame()] = el
                    end
                    Refresh()
                end)
            end
            if ns.UFPreview then
                ns.UFPreview.focus = nil   -- set again by the Position tab's element picker
                L:Preview(FramesPreviewSpec())
            end
            L:Tabs(TABS)
        end)
    end
end
