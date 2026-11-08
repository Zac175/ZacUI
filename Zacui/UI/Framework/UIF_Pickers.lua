-- UIF_Pickers - the settings pickers every module page is built from:
-- colour, font, bar texture and animation, plus the two small layout
-- helpers they share, and the functions that turn the saved setting
-- shapes into a real font / texture / colour on a real frame.
-- Part of ZacUI; load order is set by the TOC (after UIF_Controls).
--
-- THE STANDARD SETTING SHAPES. Save these, read them with the helpers
-- below, and every page, preview and profile string agrees on them:
--   colour     { r =, g =, b =, a = }                     (0..1)
--   font       { face =, size =, outline =, shadow =, shadowX =, shadowY = }
--              face: no longer drawn - every text wears ZacUI's font (an
--              old save's face is kept in the setting and ignored)
--              outline: "none" | "outline" | "thick" | "monochrome"
--   texture    a SharedMedia statusbar name; nil = ZacUI's texture
--   animation  { style =, duration =, delay =, easing =, dir =, distance =, loop = }
--              (see ns.Motion in UIF_Anim)
--
--   ns.ApplyFontSpec(fs, spec, defaults)   font + size + outline + shadow
--   ns.ResolveFontFace(face) -> path       nil = ZacUI's font
--   ns.ResolveBarTexture(name) -> path     nil = ZacUI's texture
--   ns.ColorOf(c, fallback) -> r, g, b, a
--
-- THE PICKERS (all on ns.UI, each returns a frame with a height, so a
-- page places one with L:Add(picker) or L:Row(picker, picker:GetHeight())):
--   UI.ColorPicker(parent, { label, get = fn() -> r,g,b,a, set = fn(r,g,b,a), alpha })
--   UI.FontPicker(parent, { label, get = fn() -> spec, set = fn(spec), defaults, width })
--   UI.FontFaceDropdown(parent, { get = fn() -> face, set = fn(face), defaultLabel, width })
--   UI.TexturePicker(parent, { label, get = fn() -> name, set = fn(name), defaultLabel, width })
--   UI.AnimationPicker(parent, { label, get = fn() -> spec, set = fn(spec), styles, width })
--   UI.Field(parent, label, function(host) return control end)  a small label over a control
--   UI.SetEnabled(widget, on)                dim a control and stop it taking clicks
--
-- get/set hand whole tables: set() always receives a NEW table (a copy
-- with the one change), never the table get() returned, so a module's
-- defaults table can never be written through by accident.
-- Every picker raises ns.SettingsChanged() after set(), like the plain
-- widgets, so previews follow without the page doing anything.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local FLAT = ns.FLAT
local UI = ns.UI

local M, F = UI.M, UI.F
local Changed = UI.Changed

local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

local function Copy(t)
    if ns.CopySetting then return ns.CopySetting(t) end
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

-- Room to the right edge of whatever the picker is placed in, capped at
-- `want`. A card that has not resolved its width yet reports 0 (truthy),
-- so the number is tested, not its existence.
local function DefaultWidth(parent, want)
    local w = parent and parent.GetWidth and parent:GetWidth()
    if type(w) == "number" and w >= 200 then
        return math.max(260, math.min(want, w - 2 * M.CONTROL_X))
    end
    return want
end

-- The width a picker draws at: the caller's (or the default), never more
-- than the room in its card - a picker wider than its card runs its right
-- column past the edge.
local function PickerWidth(parent, width)
    local room = UI.Room(parent)
    if room and width > room then return math.max(120, room) end
    return width
end

-- ============================================================
-- RESOLVING THE SHAPES
-- ============================================================
local OUTLINES = {
    { id = "none",       label = "None",          flags = "" },
    { id = "outline",    label = "Outline",       flags = "OUTLINE" },
    { id = "thick",      label = "Thick outline", flags = "THICKOUTLINE" },
    { id = "monochrome", label = "Monochrome",    flags = "MONOCHROME" },
}
local OUTLINE_BY_ID = {}
for _, o in ipairs(OUTLINES) do OUTLINE_BY_ID[o.id] = o end

-- the id for anything a setting might hold: one of ours, or the client's
-- own flag strings (older settings saved those)
local function NormOutline(v)
    if v == nil then return nil end
    if OUTLINE_BY_ID[v] then return v end
    local u = tostring(v):upper()
    if u == "" or u == "NONE" then return "none" end
    if u:find("MONOCHROME", 1, true) then return "monochrome" end
    if u:find("THICK", 1, true) then return "thick" end
    if u:find("OUTLINE", 1, true) then return "outline" end
    return nil
end

-- ZacUI's font: the one chosen on Appearance > Fonts & Textures, or the
-- game's own when none is.
local function HouseFontPath()
    local p = ns.Media and ns.Media.FontPath and ns.Media.FontPath()
    return p or ns.GAME_FONT or STANDARD_TEXT_FONT or FALLBACK_FONT
end

function ns.ResolveFontFace(face)
    if face == nil or face == "" then return HouseFontPath() end
    local p = ns.ResolveFontPath and ns.ResolveFontPath(face)
    if p then return p end
    -- without SharedMedia, ZacUI's own faces are still known by name
    for _, f in ipairs(ns.MEDIA_FONTS or {}) do
        if f.name == face then return f.path end
    end
    return HouseFontPath()
end

function ns.FontOutlineFlags(outline)
    local o = OUTLINE_BY_ID[NormOutline(outline) or "outline"]
    return o and o.flags or "OUTLINE"
end

-- Font, size, outline and shadow onto one FontString. `defaults` fills
-- whatever the spec leaves out (size 12, outlined, no shadow when that is
-- nil too). Size is absolute: the global size adjustment on the Fonts
-- page shifts Blizzard's font objects and ZacUI's windows, not a size a
-- module setting spells out.
-- defaults.fallbackFace: a text that follows ZacUI's font (no face of its
-- own, none in `defaults`) wears this face while ZacUI has none chosen -
-- the part's own look until a font is picked on Fonts & Textures. Such a
-- text is re-dressed when ZacUI's font changes; one with a face of its
-- own is not.
function ns.ApplyFontSpec(fs, spec, defaults)
    if not (fs and fs.SetFont) then return end
    local rawSpec, rawDefaults = spec, defaults
    spec = type(spec) == "table" and spec or {}
    defaults = type(defaults) == "table" and defaults or {}
    -- ONE FONT: the face is ZacUI's font whenever one is chosen, whatever
    -- the spec says. A face saved in a spec (from the per-text pickers of
    -- old) is ignored - kept in the settings, never drawn; with no font
    -- chosen the text wears its part's shipped face (defaults.face, else
    -- defaults.fallbackFace, else the game's).
    local face = defaults.face
    local follows = face == nil or face == ""
    local path = ns.OneFace and ns.OneFace()
    if not path then
        if follows and defaults.fallbackFace then
            path = ns.ResolveFontFace(ns.GameFace and ns.GameFace(defaults.fallbackFace) or defaults.fallbackFace)
        else
            path = ns.ResolveFontFace(face)
        end
    end
    local size = tonumber(spec.size) or tonumber(defaults.size) or 12
    local outline = spec.outline
    if outline == nil then outline = defaults.outline end
    local flags = ns.FontOutlineFlags(outline)
    -- pcall: a nil path throws; a font file that will not load returns
    -- false and leaves the string with no font
    local ok, set = pcall(fs.SetFont, fs, path, size, flags)
    if not (ok and set) then
        pcall(fs.SetFont, fs, FALLBACK_FONT, size, flags)
    end
    -- kept up: a change of ZacUI's font re-dresses it
    if ns.TrackHouseFont then
        ns.TrackHouseFont(fs, function(s) ns.ApplyFontSpec(s, rawSpec, rawDefaults) end)
    end
    local shadow = spec.shadow
    if shadow == nil then shadow = defaults.shadow end
    if fs.SetShadowOffset then
        if shadow then
            if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
            fs:SetShadowOffset(tonumber(spec.shadowX) or tonumber(defaults.shadowX) or 1,
                               tonumber(spec.shadowY) or tonumber(defaults.shadowY) or -1)
        else
            fs:SetShadowOffset(0, 0)
        end
    end
end

-- `part`: whose bar (a look part key); with nothing chosen the house
-- texture is the part's look's (ZacUI's gradient under the ZacUI look)
function ns.ResolveBarTexture(name, part)
    local house = (ns.Media and ns.Media.BarPath and ns.Media.BarPath(ns.Look and ns.Look.For(part).barTexture))
        or ns.TEX_NORM
    if name == nil or name == "" then return house end
    if ns.NewMediaName then name = ns.NewMediaName(name) or name end
    local lsm = LSM()
    if lsm then
        local p = lsm:Fetch("statusbar", name, true)
        if p then return p end
    end
    for _, b in ipairs(ns.MEDIA_BARS or {}) do
        if b.name == name then return b.path end
    end
    if name:find("\\", 1, true) or name:find("/", 1, true) then return name end
    return house
end

-- r, g, b, a from a colour setting in any of the shapes they turn up in
-- ({r=,g=,b=,a=} or {1, 0.5, 0, 1}), or from `fallback` when it is empty.
function ns.ColorOf(c, fallback)
    if type(c) ~= "table" then c = fallback end
    if type(c) ~= "table" then return 1, 1, 1, 1 end
    local r = c.r or c[1] or 1
    local g = c.g or c[2] or 1
    local b = c.b or c[3] or 1
    local a = c.a or c[4] or 1
    return r, g, b, a
end

-- ============================================================
-- LAYOUT HELPERS
-- ============================================================
-- A small grey label over a control - the shape every dropdown in a
-- picker uses, so a row of them reads like a form.
--   UI.Field(parent, "Outline", function(host) return UI.Dropdown(host, {...}) end, { width = 140 })
-- How far under a small label above it a control starts: 14 px at the
-- shipped font size, more when the font is bigger (the label never sits
-- on the control).
function UI.LabelGap(fs)
    local h = fs and fs.GetStringHeight and fs:GetStringHeight() or 0
    return math.max(14, math.ceil(h or 0) + 3)
end

-- (the label and its frame: pooled on a live page, see UIF_Pool; the
-- control is made by make() every time, so it binds to the build asking)
function UI.FieldHost(parent, label)
    local host = CreateFrame("Frame", nil, parent)
    local lab = UI.Font(host, F.SMALL, { text = label, cat = "text", key = "gray" })
    lab:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    host._zFieldLabel = lab
    return host
end

function UI.Field(parent, label, make, opts)
    opts = opts or {}
    local host = UI.FieldHost(parent, label)
    local lab = host._zFieldLabel
    local control = make(host)
    -- THE SETTINGS WINDOW (UI.S): a one-line control (a dropdown, an edit
    -- box, a button) goes on EllesmereUI's row - the label on the left at
    -- 14, the control on the right of a field at most half a row wide; a
    -- dropdown at their 170. A taller control keeps its label above.
    local S = UI.S
    -- (only a field that is a row of a section: inside a picker's own
    -- grid it keeps its label above, in the picker's column)
    if UI._zSettings and S and (control:GetHeight() or 99) <= 34 and rawget(parent, "_zAccent") then
        if control.Close and control._zSet then control:SetWidth(S.DD_W) end
        local cw = control:GetWidth() or S.DD_W
        local room = UI.Room(parent)
        local w = math.max(opts.width or 0, S.FIELD_W)
        if room and w > room then w = room end
        if cw > w - 60 then cw = math.max(60, w - 60) if control._zFit then control:_zFit(cw) else control:SetWidth(cw) end end
        UI._zFontDress(lab, S.F_LABEL)
        lab._zPaintCat, lab._zPaintKey = "text", "normal"
        lab:_zPaint()
        lab:ClearAllPoints()
        lab:SetPoint("LEFT", host, "LEFT", 0, 0)
        lab:SetJustifyH("LEFT")
        lab:SetWordWrap(false)
        UI.TruncTip(lab, host)
        control:ClearAllPoints()
        control:SetPoint("RIGHT", host, "RIGHT", 0, 0)
        local h = math.max(control:GetHeight() or S.DD_H, 20)
        local function Lay(width)
            host:SetSize(width, h)
            lab:SetWidth(math.max(20, width - (control:GetWidth() or cw) - 12))
        end
        Lay(w)
        function host:_zFit(fw) Lay(math.max(120, fw)) end
        host._zHalf = true
        host.control, host.label = control, lab
        host._zPaint = function() lab:_zPaint() end
        return host
    end
    if UI._zSettings and UI._zFontDress then
        -- (a pooled host may have been a one-line field before)
        UI._zFontDress(lab, UI.SettingsSize(F.SMALL))
        lab._zPaintCat, lab._zPaintKey = "text", "gray"
        lab:ClearAllPoints()
        lab:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        lab:SetWidth(0)
        lab:_zPaint()
    end
    local gap = UI.LabelGap(lab)
    control:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -gap)
    host:SetSize(PickerWidth(parent, opts.width or control:GetWidth() or 120), gap + (control:GetHeight() or M.DROPDOWN_H))
    if control._zFit and (control:GetWidth() or 0) > host:GetWidth() + 0.5 then control:_zFit(host:GetWidth()) end
    function host:_zFit(w)
        self:SetWidth(w)
        if control._zFit and (control:GetWidth() or 0) > w + 0.5 then control:_zFit(w) end
    end
    host.control, host.label = control, lab
    host._zPaint = function() lab:_zPaint() end
    return host
end

-- Dimmed, and deaf to the mouse. Only the parts that are interactive by
-- nature get their mouse switched (a plain host frame that was never
-- mouse-enabled must not become one, or it starts eating clicks).
local function Mouse(w, on)
    if w.slider and w.slider.EnableMouse then w.slider:EnableMouse(on) end
    if w.GetObjectType and w:GetObjectType() == "Button" and w.EnableMouse then
        w:EnableMouse(on)
    end
end

-- A labelled field (UI.Field, a picker with .control) is dimmed as a
-- whole - label and all - and only its control goes deaf.
--
-- A DIMMED OPTION SAYS WHY. UI.SetEnabled(w, false, why): it dims and goes
-- deaf as before, and a still, invisible cover over it answers the mouse
-- with a tooltip - the option's name, the reason in the warning colour
-- ("Needs X turned on", "Not on this game version", "Locked in combat"),
-- then what the option does. The cover swallows clicks (the option is off)
-- and is made the first time the option is dimmed; on again, it hides.
-- No reason given: UI.WHY_DEFAULT (the usual case, a child of the option
-- above it; L:Dependent).
UI.WHY_DEFAULT = "Needs the option above turned on."
UI.WHY_FLAVOR = "Not on this game version."
UI.WHY_COMBAT = "Locked in combat."

local function TextOf(fs)
    if fs and fs.GetText then
        local t = fs:GetText()
        if type(t) == "string" and t ~= "" then return t end
    end
end
local function LabelOf(w)
    if not w then return nil end
    return w._zTipTitle or TextOf(w.label) or TextOf(w._zFieldLabel) or TextOf(w._zLabelFS)
        or (w.GetObjectType and w:GetObjectType() == "Button" and TextOf(w._zText))
        or (w.control and LabelOf(w.control)) or nil
end

-- the tooltip for a reason: on any frame (the cover, a disabled button)
function UI.ShowWhy(owner, title, why, body)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local t = GetColor("tooltip", "title")
    if title then GameTooltip:AddLine(title, t.r, t.g, t.b) end
    local o = GetColor("text", "orange")
    GameTooltip:AddLine(why or UI.WHY_DEFAULT, o.r, o.g, o.b, true)
    if body then
        local c = GetColor("text", "gray")
        GameTooltip:AddLine(body, c.r, c.g, c.b, true)
    end
    GameTooltip:Show()
end

-- The covers are shared: one comes off a free list when an option is
-- dimmed and goes back when it is lit again or its widget goes back to the
-- settings pool (UIF_Pool calls UI.RecycleWhy), so browsing the pages
-- makes no new frames once a few exist.
local freeCovers = {}
function UI.RecycleWhy(hit)
    if not hit then return end
    local owner = hit._zOwner
    if owner and rawget(owner, "_zWhyHit") == hit then owner._zWhyHit = nil end
    hit._zOwner = nil
    hit:Hide()
    hit:ClearAllPoints()
    hit:SetParent(nil)
    freeCovers[#freeCovers + 1] = hit
end

local function WhyCover(w)
    local hit = w._zWhyHit
    if hit and hit._zOwner == w and hit:GetParent() == w then return hit end
    hit = table.remove(freeCovers)
    if hit then
        hit:SetParent(w)
    else
        hit = CreateFrame("Frame", nil, w)
        hit:EnableMouse(true)
        -- the settings pool hands it back here instead of letting it go
        hit._zPoolKeep = true
        hit:SetScript("OnEnter", function(self)
            local owner = self._zOwner
            if not owner then return end
            UI.ShowWhy(self, LabelOf(owner), self._zWhy,
                owner._zTipBody or (owner.control and owner.control._zTipBody) or nil)
        end)
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    hit:SetAllPoints(w)
    hit:SetFrameLevel((w:GetFrameLevel() or 0) + 20)
    hit._zOwner = w
    w._zWhyHit = hit
    return hit
end

function UI.SetEnabled(w, on, why)
    if not w then return end
    on = on and true or false
    w._zOff = not on
    -- (EllesmereUI's 0.3 in the settings window)
    w:SetAlpha(on and 1 or ((rawget(w, "_zSet") or rawget(w, "_zHalf")) and UI.S.OFF_A or 0.35))
    Mouse(w, on)
    if w.control then
        w.control._zOff = not on
        Mouse(w.control, on)
    end
    if on then
        if w._zWhyHit then UI.RecycleWhy(w._zWhyHit) end
    elseif w.CreateTexture then
        local hit = WhyCover(w)
        hit._zWhy = why or UI.WHY_DEFAULT
        hit:Show()
    end
end

-- ============================================================
-- COLOUR
-- ============================================================
-- A swatch for any RGBA setting. With alpha on, the right half of the
-- swatch is drawn over a light/dark split so how see-through the colour
-- is can be seen at a glance; the left half is always the solid colour.
--
-- "BLANK MEANS THE THEME'S COLOUR". A setting that is nil until picked
-- (the module then draws its theme or palette colour) passes:
--   opts.default = function() return r, g, b, a end   (or a colour table)
--                  what nil stands for: the swatch shows it, and the
--                  picker opens on it
--   opts.reset   = true: a small x after the label, shown only while a
--                  colour is picked, that calls set(nil) - back to the
--                  default - and raises the change signal; or a function
--                  to call instead of set(nil)
--   opts.resetTip = the x's tooltip (default "Back to the theme colour")
function UI.ColorPicker(parent, opts)
    opts = opts or {}
    local set = UI._zSettings and UI.S
    -- (settings window: EllesmereUI's 24 px swatch with a white edge)
    local SW, SH, HH = set and set.SWATCH or 30, set and set.SWATCH or 14, set and set.SWATCH or 16
    local host = CreateFrame("Button", nil, parent)
    host:SetHeight(HH)
    host._zSet = set and true or nil
    host._zHalf = set and true or nil

    local sw = CreateFrame("Frame", nil, host)
    sw:SetSize(SW, SH)
    sw:SetPoint("LEFT", host, "LEFT", 0, 0)
    local solid = sw:CreateTexture(nil, "ARTWORK", nil, 1)
    solid._zui_own = true
    solid:SetTexture(FLAT)
    solid:SetAllPoints()
    local light, dark, see
    if opts.alpha then
        solid:ClearAllPoints()
        solid:SetPoint("TOPLEFT")
        solid:SetPoint("BOTTOMRIGHT", sw, "BOTTOM", 0, 0)
        light = sw:CreateTexture(nil, "ARTWORK", nil, 0)
        light._zui_own = true
        light:SetTexture(FLAT)
        light:SetPoint("TOPLEFT", sw, "TOP", 0, 0)
        light:SetPoint("BOTTOMRIGHT", sw, "RIGHT", 0, 0)
        light:SetVertexColor(0.85, 0.85, 0.85, 1)
        dark = sw:CreateTexture(nil, "ARTWORK", nil, 0)
        dark._zui_own = true
        dark:SetTexture(FLAT)
        dark:SetPoint("TOPLEFT", sw, "CENTER", 0, 0)
        dark:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", 0, 0)
        dark:SetVertexColor(0.25, 0.25, 0.25, 1)
        see = sw:CreateTexture(nil, "ARTWORK", nil, 2)
        see._zui_own = true
        see:SetTexture(FLAT)
        see:SetPoint("TOPLEFT", sw, "TOP", 0, 0)
        see:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", 0, 0)
    end
    UI.Border(sw, "ui", "border")

    local label
    local width = 30
    if opts.label then
        label = UI.Font(host, F.LABEL, { text = opts.label })
        label:SetPoint("LEFT", sw, "RIGHT", set and 10 or 8, 0)
        width = SW + (set and 10 or 8) + math.max(10, label:GetStringWidth() or 0)
    end
    host:SetWidth(opts.width or width)

    -- nil from get() = "not picked": the default stands in (if given)
    local function Picked()
        if not opts.get then return false end
        return opts.get() ~= nil
    end
    local function Read()
        local r, g, b, a
        if opts.get then r, g, b, a = opts.get() end
        if r == nil and opts.default then
            if type(opts.default) == "function" then r, g, b, a = opts.default()
            else r = opts.default end
        end
        if type(r) == "table" then r, g, b, a = ns.ColorOf(r) end
        return r or 1, g or 1, b or 1, a or 1
    end

    local resetBtn
    if opts.reset then
        resetBtn = UI.CloseX(host, 14, function()
            if type(opts.reset) == "function" then opts.reset()
            elseif opts.set then opts.set(nil) end
            host:_zPaint()
            Changed("color")
        end)
        resetBtn:SetPoint("LEFT", label or sw, "RIGHT", label and 4 or 6, 0)
        UI.Tooltip(resetBtn, "Reset", opts.resetTip or "Back to the theme colour.")
        if not opts.width then host:SetWidth(width + 4 + 14) end
    end

    -- A label too long for the room wraps under itself (the swatch level
    -- with its first line) instead of running past the card.
    function host:_zFit(maxW)
        if (self:GetWidth() or 0) > maxW then self:SetWidth(maxW) end
        if not label then return end
        local roomL = math.floor(maxW - SW - 8 - (resetBtn and 18 or 0))
        if roomL < 40 or (label:GetStringWidth() or 0) <= roomL + 0.5 then return end
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", sw, "TOPRIGHT", 8, 1)
        label:SetWidth(roomL)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(true)
        sw:ClearAllPoints()
        sw:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -1)
        local h = math.max(HH, math.ceil(label:GetStringHeight() or HH) + 2)
        self:SetHeight(h)
        self:SetWidth(maxW)
        self._zExtraH = h - HH
    end
    -- (as built, before any fit: a pooled picker goes back to this)
    local w0 = host:GetWidth()
    local lj0 = label and label:GetJustifyH()
    local lw0 = label and label.CanWordWrap and label:CanWordWrap()
    function host:_zUnfit()
        if label then
            label:ClearAllPoints()
            label:SetPoint("LEFT", sw, "RIGHT", set and 10 or 8, 0)
            label:SetWidth(0)
            if lj0 then label:SetJustifyH(lj0) end
            if lw0 ~= nil then label:SetWordWrap(lw0) end
        end
        sw:ClearAllPoints()
        sw:SetPoint("LEFT", host, "LEFT", 0, 0)
        self:SetSize(w0, HH)
        self._zExtraH = nil
    end
    do
        local room = UI.Room(parent)
        if room then host:_zFit(room) end
    end
    host._zPoolRefit = function(self)
        local r = UI.Room(self:GetParent())
        if r then self:_zFit(r) end
    end

    host._zPaint = function(self)
        local r, g, b, a = Read()
        solid:SetVertexColor(r, g, b, 1)
        if see then see:SetVertexColor(r, g, b, a) end
        if set then
            for _, t in ipairs(sw._zBorder) do t:SetVertexColor(1, 1, 1, self._zHot and 1 or 0.85) end
        else
            local k = self._zHot and GetColor("ui", "accent") or GetColor("ui", "border")
            for _, t in ipairs(sw._zBorder) do t:SetVertexColor(k.r, k.g, k.b, 1) end
        end
        if label then label:_zPaint() end
        if resetBtn then resetBtn:SetShown(Picked()) end
    end
    host:HookScript("OnEnter", function(self) self._zHot = true self:_zPaint() end)
    host:HookScript("OnLeave", function(self) self._zHot = nil self:_zPaint() end)

    local function Put(r, g, b, a)
        if opts.set then opts.set(r, g, b, opts.alpha and a or nil) end
        host:_zPaint()
        Changed("color")
    end
    host:SetScript("OnClick", function()
        local r, g, b, a = Read()
        UI.OpenColorPicker({ r = r, g = g, b = b, a = a, alpha = opts.alpha,
            onChange = Put, onCancel = Put })
    end)
    if opts.tooltip then UI.Tooltip(host, opts.label or "Colour", opts.tooltip) end
    host.Refresh = function() host:_zPaint() end
    host.swatch = sw
    host.resetButton = resetBtn
    host:_zPaint()
    return host
end

-- ============================================================
-- FONT FACE (a dropdown that draws every font in itself)
-- ============================================================
local function FontItems(defaultLabel, only)
    local list = { { text = defaultLabel, value = "" } }
    local seen = { [""] = true }
    if only then
        for _, n in ipairs(only() or {}) do
            if not seen[n] then seen[n] = true list[#list + 1] = { text = n, value = n } end
        end
        return list
    end
    -- ZacUI's own faces first, then everything SharedMedia knows
    for _, f in ipairs(ns.MEDIA_FONTS or {}) do
        if not seen[f.name] then
            seen[f.name] = true
            list[#list + 1] = { text = f.name, value = f.name }
        end
    end
    local lsm = LSM()
    if lsm then
        for _, n in ipairs(lsm:List("font")) do
            if not seen[n] then
                seen[n] = true
                list[#list + 1] = { text = n, value = n }
            end
        end
    end
    return list
end

-- opts.defaultPath: the file the "default" entry stands for (the Fonts
-- page's "Blizzard default" is the game's font, not ZacUI's).
-- opts.list: a function returning the names to offer, instead of ZacUI's
-- faces plus every SharedMedia font (for a setting that can only resolve
-- SharedMedia names).
function UI.FontFaceDropdown(parent, opts)
    opts = opts or {}
    local defaultLabel = opts.defaultLabel or "ZacUI's font"
    local function PathOf(v)
        if v == "" or v == nil then
            return (opts.defaultPath and opts.defaultPath()) or ns.ResolveFontFace(nil)
        end
        return ns.ResolveFontFace(v)
    end
    local function Current()
        local v = opts.get and opts.get()
        if v == nil then v = "" end
        return v
    end
    local function LabelOf(v)
        if v == "" then return defaultLabel end
        return v
    end
    local dd
    local function Dress(fs, v, size)
        if not (fs and fs.SetFont) then return end
        -- each name in the list (and the one picked) is drawn in its own
        -- face, not ZacUI's: on purpose, and left alone on a font change
        rawset(fs, "_zOwnFace", "font list: each name in its own face")
        if ns.TrackHouseFont then ns.TrackHouseFont(fs, nil) end
        local path = PathOf(v)
        local ok, set = pcall(fs.SetFont, fs, path, size, "")
        if not (ok and set) then
            ok, set = pcall(fs.SetFont, fs, HouseFontPath(), size, "")
            if not (ok and set) then pcall(fs.SetFont, fs, FALLBACK_FONT, size, "") end
        end
    end
    dd = UI.Dropdown(parent, {
        width = opts.width or 200,
        items = function() return FontItems(defaultLabel, opts.list) end,
        selected = function() return LabelOf(Current()) end,
        selectedValue = function() return Current() end,
        onSelect = function(v)
            if opts.set then opts.set(v ~= "" and v or nil) end
            Dress(dd._zText, Current(), F.LABEL + 1)
        end,
        decorate = function(row, item, v) Dress(row.label, v, F.LABEL + 2) end,
    })
    Dress(dd._zText, Current(), F.LABEL + 1)
    dd._zPoolRefresh = function(self)
        self:SetText(LabelOf(Current()))
        Dress(self._zText, Current(), F.LABEL + 1)
    end
    return dd
end

-- ============================================================
-- TEXTURE
-- ============================================================
local function BarItems(defaultLabel, only)
    local list = { { text = defaultLabel, value = "" } }
    local seen = { [""] = true }
    if only then
        for _, n in ipairs(only() or {}) do
            if not seen[n] then seen[n] = true list[#list + 1] = { text = n, value = n } end
        end
        return list
    end
    for _, b in ipairs(ns.MEDIA_BARS or {}) do
        if not seen[b.name] then
            seen[b.name] = true
            list[#list + 1] = { text = b.name, value = b.name }
        end
    end
    local lsm = LSM()
    if lsm then
        for _, n in ipairs(lsm:List("statusbar")) do
            if not seen[n] then
                seen[n] = true
                list[#list + 1] = { text = n, value = n }
            end
        end
    end
    return list
end

-- A bar texture dropdown. Every row shows a stretch of its texture on the
-- right, and so does the closed box, in opts.color() (default: the accent).
-- opts.defaultPath: the file the "default" entry stands for; opts.list:
-- the names to offer instead of ZacUI's textures plus SharedMedia's.
function UI.TexturePicker(parent, opts)
    opts = opts or {}
    local defaultLabel = opts.defaultLabel or "ZacUI's texture"
    local width = PickerWidth(parent, opts.width or 240)
    local function Current()
        local v = opts.get and opts.get()
        if v == nil then v = "" end
        return v
    end
    local function PathOf(v)
        if v == "" then return (opts.defaultPath and opts.defaultPath()) or ns.ResolveBarTexture(nil) end
        return ns.ResolveBarTexture(v)
    end
    local function Tint(tex)
        local r, g, b
        if opts.color then r, g, b = opts.color() end
        if type(r) == "table" then r, g, b = ns.ColorOf(r) end
        if not r then
            local a = GetColor("ui", "accent")
            r, g, b = a.r, a.g, a.b
        end
        tex:SetVertexColor(r, g, b, 1)
    end
    local SAMPLE_W = math.max(50, math.floor(width * 0.38))
    local function Sample(owner, h, rightInset)
        local t = owner:CreateTexture(nil, "ARTWORK", nil, 1)
        t._zui_own = true
        t:SetSize(SAMPLE_W, h)
        t:SetPoint("RIGHT", owner, "RIGHT", -rightInset, 0)
        return t
    end

    local host = CreateFrame("Frame", nil, parent)
    local top = 0
    if opts.label then
        -- (a label longer than the picker wraps, and the box moves down)
        local lab = UI.Font(host, F.SMALL, { text = opts.label, cat = "text", key = "gray", width = width })
        lab:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        host.label = lab
        top = math.max(14, math.ceil(lab:GetStringHeight() or 12) + 2)
    end

    local dd
    dd = UI.Dropdown(host, {
        width = width,
        items = function() return BarItems(defaultLabel, opts.list) end,
        selected = function() local v = Current() return v == "" and defaultLabel or v end,
        selectedValue = function() return Current() end,
        onSelect = function(v)
            if opts.set then opts.set(v ~= "" and v or nil) end
            if dd._zSample then
                dd._zSample:SetTexture(PathOf(Current()))
                Tint(dd._zSample)
            end
        end,
        decorate = function(row, item, v)
            if not row._zSample then
                row._zSample = Sample(row, 13, 16)
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.label:SetPoint("RIGHT", row._zSample, "LEFT", -6, 0)
            end
            row._zSample:SetTexture(PathOf(v))
            Tint(row._zSample)
        end,
    })
    dd:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
    dd._zSample = Sample(dd, M.DROPDOWN_H - 10, 20)
    dd._zText:ClearAllPoints()
    dd._zText:SetPoint("LEFT", dd, "LEFT", 7, 0)
    dd._zText:SetPoint("RIGHT", dd._zSample, "LEFT", -6, 0)
    dd._zSample:SetTexture(PathOf(Current()))
    Tint(dd._zSample)
    local basePaint = dd._zPaint
    dd._zPaint = function(self)
        basePaint(self)
        if self._zSample then Tint(self._zSample) end
    end

    host:SetSize(width, top + M.DROPDOWN_H)
    host.dropdown = dd
    host.control = dd
    host._zPoolRefresh = function()
        local v = Current()
        dd:SetText(v == "" and defaultLabel or v)
        dd._zSample:SetTexture(PathOf(v))
        Tint(dd._zSample)
    end
    host._zPaint = function() if host.label then host.label:_zPaint() end end
    return host
end

-- ============================================================
-- ONE FONT: where a face used to be picked
-- ============================================================
-- Every text ZacUI draws wears ZacUI's font (Appearance > Fonts &
-- Textures), so a picker for one part or one text no longer offers a
-- face: this note stands where its face dropdown stood, the dropdown's
-- size, so the rows around it keep their places.
UI.ONE_FONT_NOTE = "Uses ZacUI's font (Fonts & Textures)"
function UI.OneFontNote(parent, width)
    width = width or 200
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(width, M.DROPDOWN_H)
    -- one line: cut short in a narrow column, the whole note on hover
    local fs = UI.Font(host, F.SMALL, { text = UI.ONE_FONT_NOTE, cat = "text", key = "gray", width = width })
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:SetPoint("LEFT", host, "LEFT", 0, 0)
    fs._zTruncTip = true      -- (cut short on purpose: the tooltip below says it all)
    host:EnableMouse(true)
    UI.Tooltip(host, UI.ONE_FONT_NOTE, "Every text ZacUI draws is in the one font chosen on Appearance > "
        .. "Fonts & Textures. Size, outline and shadow are set here.")
    host.text = fs
    host._zOneFontNote = true
    host._zPaint = function() if fs._zPaint then fs:_zPaint() end end
    function host:_zFit(w)
        self:SetWidth(w)
        fs:SetWidth(w)
    end
    return host
end

-- ============================================================
-- FONT (size, outline, shadow - one group; the face is ZacUI's)
-- ============================================================
--   opts.defaults  what the module uses when a field is nil
--                  ({ size = 12, outline = "outline", shadow = false })
--   opts.minSize / maxSize (6 / 32), opts.sample (the line drawn in it)
--   opts.defaultLabel / defaultPath / list   handed to the face dropdown
--                  (UI.FontFaceDropdown: what the default entry is called,
--                  the file it stands for, the names offered)
function UI.FontPicker(parent, opts)
    opts = opts or {}
    local W = PickerWidth(parent, opts.width or DefaultWidth(parent, 400))
    local GAP = 16
    local colW = math.floor((W - GAP) / 2)
    local x2 = colW + GAP
    local D = opts.defaults or {}
    local host = CreateFrame("Frame", nil, parent)

    local function Cur()
        local t = opts.get and opts.get()
        return type(t) == "table" and t or {}
    end
    local Sync
    local function Put(field, value)
        local new = Copy(Cur())
        new[field] = value
        if opts.set then opts.set(new) end
        Sync()
    end
    local function Val(field)
        local v = Cur()[field]
        if v == nil then v = D[field] end
        return v
    end

    local y = 0
    if opts.label then
        -- (a title longer than the picker wraps; the rows start under it)
        local t = UI.Font(host, F.LABEL, { text = opts.label, width = W })
        t:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        host.title = t
        y = -math.max(18, math.ceil(t:GetStringHeight() or 12) + 6)
    end

    -- row 1: face | size. The face is ZacUI's one font: a note, not a
    -- choice (a face an old save holds is kept, and ignored)
    local face = UI.Field(host, "Font", function(h) return UI.OneFontNote(h, colW) end, { width = colW })
    face:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
    local size = UI.Slider(host, { width = colW, label = "Size",
        min = opts.minSize or 6, max = opts.maxSize or 32, step = 1,
        value = tonumber(Val("size")) or 12,
        onChange = function(v) Put("size", v) end })
    size:SetPoint("TOPLEFT", host, "TOPLEFT", x2, y - 6)

    -- row 2: outline | shadow
    y = y - 44
    local outline = UI.Field(host, "Outline", function(h)
        return UI.Dropdown(h, { width = colW,
            items = function()
                local list = {}
                for _, o in ipairs(OUTLINES) do list[#list + 1] = { text = o.label, value = o.id } end
                return list
            end,
            selected = function()
                local o = OUTLINE_BY_ID[NormOutline(Val("outline")) or "outline"]
                return o and o.label or "Outline"
            end,
            selectedValue = function() return NormOutline(Val("outline")) or "outline" end,
            onSelect = function(v) Put("outline", v) end })
    end, { width = colW })
    outline:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
    local shadow = UI.Checkbox(host, "Shadow", Val("shadow") and true or false,
        function(on) Put("shadow", on) end, { width = colW })
    shadow:SetPoint("TOPLEFT", host, "TOPLEFT", x2, y - 19)

    -- row 3: sample | shadow offset
    y = y - 44
    local sample = host:CreateFontString(nil, "OVERLAY")
    sample:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y - 8)
    sample:SetWidth(colW)
    sample:SetJustifyH("LEFT")
    if sample.SetWordWrap then sample:SetWordWrap(false) end
    -- a big size cuts the sample line short: hovering it shows the whole line
    local sampleHit = CreateFrame("Frame", nil, host)
    sampleHit:SetAllPoints(sample)
    sampleHit:EnableMouse(true)
    UI.TruncTip(sample, sampleHit)
    -- the two offsets side by side, or one under the other when a half
    -- column is too narrow for their labels
    local half = math.floor((colW - 10) / 2)
    local probe = UI.Font(host, F.SMALL, { text = "Shadow X" })
    -- (the settings window's slider is one line - label, track, value
    -- box - so it wants more room: UI.S)
    local S = UI._zSettings and UI.S
    local needW = math.ceil(probe:GetStringWidth() or 0)
        + (S and (2 * S.TRACK_GAP + S.TRACK_MIN + S.VALUE_W + 4) or 36)
    local stack = half < needW
    probe:Hide()
    local sw = stack and colW or half
    local sx = UI.Slider(host, { width = sw, label = "Shadow X", min = -4, max = 4, step = 1,
        value = tonumber(Val("shadowX")) or 1, onChange = function(v) Put("shadowX", v) end })
    sx:SetPoint("TOPLEFT", host, "TOPLEFT", x2, y)
    local sy = UI.Slider(host, { width = sw, label = "Shadow Y", min = -4, max = 4, step = 1,
        value = tonumber(Val("shadowY")) or -1, onChange = function(v) Put("shadowY", v) end })
    local shH = math.max(32, (sx:GetHeight() or 30) + 2, (sy:GetHeight() or 30) + 2)
    if stack then
        y = y - math.max(44, shH + 10)
        sy:SetPoint("TOPLEFT", host, "TOPLEFT", x2, y)
    else
        sy:SetPoint("TOPLEFT", host, "TOPLEFT", x2 + half + 10, y)
    end
    host:SetSize(W, -(y - shH))

    Sync = function()
        ns.ApplyFontSpec(sample, Cur(), D)
        sample:SetText(opts.sample or "The quick brown fox 0123")
        local c = GetColor("text", "normal")
        sample:SetTextColor(c.r, c.g, c.b, 1)
        local on = Val("shadow") and true or false
        UI.SetEnabled(sx, on)
        UI.SetEnabled(sy, on)
    end
    host._zPaint = function()
        if host.title then host.title:_zPaint() end
        Sync()
    end
    host.face, host.size, host.outline, host.shadow = face, size, outline, shadow
    host.shadowX, host.shadowY, host.sample = sx, sy, sample
    host.Refresh = Sync
    -- every control from the settings again (a pooled picker handed back)
    host._zPoolRefresh = function()
        if face.control and face.control._zPoolRefresh then face.control:_zPoolRefresh() end
        if outline.control and outline.control._zPoolRefresh then outline.control:_zPoolRefresh() end
        size._zSetQuiet(tonumber(Val("size")) or 12)
        shadow:SetChecked(Val("shadow") and true or false)
        sx._zSetQuiet(tonumber(Val("shadowX")) or 1)
        sy._zSetQuiet(tonumber(Val("shadowY")) or -1)
        Sync()
    end
    Sync()
    return host
end

-- ============================================================
-- ANIMATION
-- ============================================================
-- Style, duration, delay, easing, direction + distance, loop - with a
-- small stage that plays the animation over and over while it is on
-- screen, so you see what you are choosing as you choose it. The loop is
-- a chain of timers that checks the stage is still visible at every
-- step: closing the window or changing page ends it, nothing ticks
-- unseen. Controls that do nothing for the chosen style are dimmed.
--   opts.styles  ids to offer (default: all of ns.Motion.STYLES)
function UI.AnimationPicker(parent, opts)
    opts = opts or {}
    local Motion = ns.Motion
    local W = PickerWidth(parent, opts.width or DefaultWidth(parent, 400))
    local GAP = 16
    local colW = math.floor((W - GAP) / 2)
    local x2 = colW + GAP
    local host = CreateFrame("Frame", nil, parent)

    local function Cur()
        local t = opts.get and opts.get()
        return type(t) == "table" and t or {}
    end
    local function Spec() return Motion.Normalize(Cur()) end
    local Sync
    local function Put(field, value)
        local new = Copy(Cur())
        if type(value) == "number" then value = math.floor(value * 100 + 0.5) / 100 end
        new[field] = value
        if opts.set then opts.set(new) end
        Sync()
    end
    local function LabelIn(list, id)
        for _, e in ipairs(list) do if e.id == id then return e.label end end
        return id
    end
    local styles = {}
    if opts.styles then
        local want = {}
        for _, id in ipairs(opts.styles) do want[id] = true end
        for _, s in ipairs(Motion.STYLES) do if want[s.id] then styles[#styles + 1] = s end end
    else
        styles = Motion.STYLES
    end
    local function Items(list)
        return function()
            local out = {}
            for _, e in ipairs(list) do out[#out + 1] = { text = e.label, value = e.id } end
            return out
        end
    end

    local y = 0
    if opts.label then
        -- (a title longer than the picker wraps; the rows start under it)
        local t = UI.Font(host, F.LABEL, { text = opts.label, width = W })
        t:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        host.title = t
        y = -math.max(18, math.ceil(t:GetStringHeight() or 12) + 6)
    end

    -- row 1: style | the stage
    local style = UI.Field(host, "Style", function(h)
        return UI.Dropdown(h, { width = colW, items = Items(styles),
            selected = function() return LabelIn(Motion.STYLES, Spec().style) end,
            selectedValue = function() return Spec().style end,
            onSelect = function(v) Put("style", v) end })
    end, { width = colW })
    style:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)

    local stage = UI.Box(host, "ui", "elementBg")
    stage:SetSize(colW, 38)
    stage:SetPoint("TOPLEFT", host, "TOPLEFT", x2, y)
    if stage.SetClipsChildren then stage:SetClipsChildren(true) end
    local square = UI.Box(stage, "ui", "accent")
    square:SetSize(14, 14)
    square:SetPoint("CENTER", stage, "CENTER", 0, 0)
    local note = UI.Font(stage, F.SMALL, { text = "Animations are off (Appearance > Motion)",
        cat = "text", key = "gray", justify = "CENTER" })
    note:SetPoint("BOTTOM", stage, "BOTTOM", 0, 2)
    note:SetWidth(colW - 8)
    note:Hide()

    -- row 2: duration | delay (each row as tall as what is in it: a
    -- bigger font makes the fields taller)
    y = y - math.max(44, (style:GetHeight() or 38) + 6)
    local dur = UI.Slider(host, { width = colW, label = "Duration", min = 0.05, max = 2, step = 0.05,
        value = Spec().duration, format = function(v) return string.format("%.2fs", v) end,
        onChange = function(v) Put("duration", v) end })
    dur:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y - 6)
    local delay = UI.Slider(host, { width = colW, label = "Delay", min = 0, max = 2, step = 0.05,
        value = Spec().delay, format = function(v) return string.format("%.2fs", v) end,
        onChange = function(v) Put("delay", v) end })
    delay:SetPoint("TOPLEFT", host, "TOPLEFT", x2, y - 6)

    -- row 3: easing | loop
    y = y - math.max(40, math.max(dur:GetHeight() or 30, delay:GetHeight() or 30) + 10)
    local easing = UI.Field(host, "Easing", function(h)
        return UI.Dropdown(h, { width = colW, items = Items(Motion.EASINGS),
            selected = function() return LabelIn(Motion.EASINGS, Spec().easing) end,
            selectedValue = function() return Spec().easing end,
            onSelect = function(v) Put("easing", v) end })
    end, { width = colW })
    easing:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
    local loop = UI.Checkbox(host, "Repeat until hidden", Spec().loop,
        function(on) Put("loop", on) end,
        { tooltip = "Pulse and Flash only: keep playing for as long as the frame is shown.", width = colW })
    -- (wrapped onto two lines it starts level with the field labels)
    loop:SetPoint("TOPLEFT", host, "TOPLEFT", x2, y - (((loop._zExtraH or 0) > 0) and 12 or 19))

    -- row 4: direction | distance
    y = y - math.max(44, (easing:GetHeight() or 38) + 6)
    local dir = UI.Field(host, "Comes from", function(h)
        return UI.Dropdown(h, { width = colW, items = Items(Motion.DIRS),
            selected = function() return LabelIn(Motion.DIRS, Spec().dir) end,
            selectedValue = function() return Spec().dir end,
            onSelect = function(v) Put("dir", v) end })
    end, { width = colW })
    dir:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
    local dist = UI.Slider(host, { width = colW, label = "Distance", min = 0, max = 200, step = 2,
        value = Spec().distance, format = function(v) return string.format("%d px", v) end,
        onChange = function(v) Put("distance", v) end })
    dist:SetPoint("TOPLEFT", host, "TOPLEFT", x2, y - 6)
    host:SetSize(W, -(y - math.max(40, (dir:GetHeight() or 38) + 2, (dist:GetHeight() or 30) + 6)))

    -- THE DEMO LOOP. In, a beat, out, a shorter beat, again - each step a
    -- timer that first checks this is still the current run (`serial`)
    -- and that the stage is still on screen.
    local serial = 0
    local function DemoSpec()
        local s = Spec()
        local vertical = (s.dir == "up" or s.dir == "down")
        local room = vertical and 12 or math.max(10, math.floor(colW / 2) - 12)
        s.distance = math.min(s.distance, room)
        return s
    end
    local function StopDemo()
        serial = serial + 1
        Motion.Stop(square)
        square:Show()
    end
    local function RunDemo()
        StopDemo()
        if not stage:IsVisible() then return end
        local s = DemoSpec()
        note:SetShown(not Motion.Enabled())
        if s.style == "none" or not Motion.Enabled() then return end
        local mine = serial
        local Step
        Step = function(phase)
            if mine ~= serial or not stage:IsVisible() then return end
            if phase == "in" then
                Motion.Play(square, s, "in", function()
                    C_Timer.After(0.6, function() Step("out") end)
                end)
            else
                Motion.Play(square, s, "out", function()
                    C_Timer.After(0.35, function() Step("in") end)
                end)
            end
        end
        Step("in")
    end
    stage:SetScript("OnShow", RunDemo)
    stage:SetScript("OnHide", StopDemo)

    Sync = function()
        local s = Spec()
        local live = s.style ~= "none"
        UI.SetEnabled(dur, live)
        UI.SetEnabled(delay, live)
        UI.SetEnabled(easing, live and not (s.style == "bounce" or s.style == "flash" or s.style == "pulse"))
        UI.SetEnabled(loop, live and Motion.LOOPS[s.style] and true or false)
        UI.SetEnabled(dir, live and Motion.MOVES[s.style] and true or false)
        UI.SetEnabled(dist, live and Motion.MOVES[s.style] and true or false)
        RunDemo()
    end
    host._zPaint = function() if host.title then host.title:_zPaint() end end
    host.style, host.duration, host.delay, host.easing = style, dur, delay, easing
    host.loop, host.dir, host.distance, host.stage, host.square = loop, dir, dist, stage, square
    host.Refresh = Sync
    host._zPoolRefresh = function()
        for _, f in ipairs({ style, easing, dir }) do
            if f.control and f.control._zPoolRefresh then f.control:_zPoolRefresh() end
        end
        local sp = Spec()
        dur._zSetQuiet(sp.duration)
        delay._zSetQuiet(sp.delay)
        dist._zSetQuiet(sp.distance)
        loop:SetChecked(sp.loop and true or false)
        Sync()
    end
    host.Replay = RunDemo
    Sync()
    return host
end

ns.FONT_OUTLINES = OUTLINES
ns.NormFontOutline = NormOutline
