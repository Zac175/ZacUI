-- Win_Kit - the shared parts every rebuilt ZacUI window is made of.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHY A COVER AND NOT A NEW TOP-LEVEL WINDOW. The merchant, the spellbook
-- and the rest are Blizzard "UI panels": the client decides where they
-- sit (left / centre / right slots), pushes the others along when a
-- second one opens, and closes them with Escape. Some of them also end a
-- session when they hide (the merchant calls CloseMerchant on hide).
--
-- A cover is a ZacUI window PARENTED to the Blizzard panel and laid
-- exactly over its visible rectangle (the same inset the skin panel
-- uses). So it opens, closes, moves and makes room exactly when
-- Blizzard's window does - including from secure code in combat, which
-- matters for the spellbook - and nothing of Blizzard's shows through or
-- can be clicked, because the cover is opaque and takes the mouse.
--
-- Everything here is built from UIF_Controls, so it repaints with the
-- colour editor like the rest of ZacUI's own windows.

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Col = ns.Col
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local SharpenIcon = ns.SharpenIcon
local TEX_THUMB = ns.TEX_THUMB
local UI = ns.UI

local M, F = UI.M, UI.F

local Kit = {}

-- Layout numbers shared by every window built on the kit.
Kit.PAD      = 8     -- window edge -> content
Kit.GAP      = 6     -- between controls on one row
Kit.TAB_H    = 26
Kit.SEARCH_H = 22
Kit.FOOTER_H = 32
Kit.ROW_H    = 30

-- ============================================================
-- COLOUR HELPERS
-- ============================================================
-- Item quality and money are ns.QualityRGB / ns.Money (Core_Services),
-- shared with the bags and the auction house.

function Kit.TextRGB(key)
    local c = GetColor("text", key or "normal")
    return c.r, c.g, c.b
end

-- A class file's colour (ns.ClassColor: a class-colour addon's table
-- first, so every window and both maps agree), or the plain text colour
-- for no class / an unknown one.
function Kit.ClassRGB(file)
    if file and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[file])
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[file])) then
        return ns.ClassColor(file)
    end
    return Kit.TextRGB("normal")
end

-- "Warrior" wrapped in its class colour (plain when the class is unknown).
function Kit.ClassText(className, classFile)
    className = className or ""
    if not (classFile and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFile])
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]))) then
        return className
    end
    local r, g, b = ns.ClassColor(classFile)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255),
        math.floor(g * 255), math.floor(b * 255), className)
end

-- ============================================================
-- THE WINDOWS' LOOK (2026-11-01 settings pass)
-- ============================================================
-- One small table, ZacUIDB.windows, read by every cover: its scale, its
-- background and border colours, the title's font and colour, and how a
-- window opens. Every default is what the windows already looked like -
-- scale 1 (and a window whose scale was never changed is never touched),
-- the theme's colours (nil follows the theme), ZacUI's font, no opening
-- animation - so nothing changes until somebody picks something on the
-- Game windows page.
Kit.DEFAULTS = {
    scale = 1,
    openAnim = { style = "none", duration = 0.2, delay = 0, easing = "easeOutQuad",
                 dir = "down", distance = 16 },
}

local dbCached
local function Fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                local c = {}
                for k2, v2 in pairs(v) do c[k2] = v2 end
                dst[k] = c
            else
                dst[k] = v
            end
        end
    end
end

-- Filled once per table: a profile switch or a reset hands over a new one.
function Kit.DB()
    if type(ZacUIDB) ~= "table" then
        dbCached = dbCached or {}
        Fill(dbCached, Kit.DEFAULTS)
        return dbCached
    end
    local d = ZacUIDB.windows
    if d ~= nil and d == dbCached then return d end
    if type(d) ~= "table" then d = {} ZacUIDB.windows = d end
    if ns.FillDefaults then ns.FillDefaults(d, Kit.DEFAULTS) else Fill(d, Kit.DEFAULTS) end
    dbCached = d
    return d
end

-- A colour setting, or the theme's (cat, key) when it is unset.
function Kit.Color(key, cat, ckey, alpha)
    local c = Kit.DB()[key]
    if type(c) == "table" then
        if ns.ColorOf then return ns.ColorOf(c) end
        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
    end
    local t = GetColor(cat, ckey) or {}
    return t.r or 1, t.g or 1, t.b or 1, alpha or t.a or 1
end

-- What an unset title font means: what UI.Font gives it (ZacUI's font at
-- the title step plus the global size adjustment, outlined unless
-- outlines are off globally, the template's shadow).
function Kit.TitleFontDefaults()
    local cfg = ZacUIDB and ZacUIDB.font or {}
    return {
        size = (F.TITLE or 14) + (cfg.delta or 0),
        outline = (cfg.outline == "NONE") and "none" or "outline",
        shadow = true,
    }
end

-- WHERE THE TITLE AND ITS ICON SIT (ZacUI's anchor shape, windows.anchors.
-- <title|icon>, every window at once): the title from the icon (or the
-- bar's left edge) to the close button, the icon at the bar's left - the
-- spots they always had - with a saved anchor on top. Nothing saved =
-- never touched.
Kit.ANCHOR_TARGETS = { { value = "bar", text = "The title bar" }, { value = "icon", text = "The icon" },
    { value = "title", text = "The title" }, { value = "window", text = "The window" } }
function Kit.AnchorDefaults(key)
    if key == "icon" then return { point = "LEFT", relPoint = "LEFT", x = 8, y = 2 } end
    return { point = "LEFT", relPoint = "LEFT", x = 10, y = 2, justify = "LEFT" }
end
function Kit.PlaceTitle(f)
    local db = Kit.DB()
    local a = type(db.anchors) == "table" and db.anchors or nil
    local bar, title, icon = f.titleBar, f.titleText, f.titleIcon
    if not (bar and title and icon and ns.ApplyAnchor) then return end
    if not (a or f._zTitleMoved) then return end
    f._zTitleMoved = a and true or nil
    if not f._zAnchorTo then
        f._zAnchorTo = function(k)
            if k == "bar" then return bar elseif k == "icon" then return icon
            elseif k == "title" then return title elseif k == "window" then return f end
        end
        f._zTitleDefs = { icon = {}, title = {} }
    end
    local d = f._zTitleDefs.icon
    d.point, d.to, d.relPoint, d.x, d.y = "LEFT", bar, "LEFT", 8, 2
    ns.ApplyAnchor(icon, a and a.icon, d, f._zAnchorTo)
    d = f._zTitleDefs.title
    if icon:IsShown() then d.point, d.to, d.relPoint, d.x, d.y = "LEFT", icon, "RIGHT", 7, 2
    else d.point, d.to, d.relPoint, d.x, d.y = "LEFT", bar, "LEFT", 10, 2 end
    d.justify = "LEFT"
    d.point2, d.to2, d.relPoint2, d.x2, d.y2 = "RIGHT", bar, "RIGHT", -34, 2
    local _, two = ns.ApplyAnchor(title, a and a.title, d, f._zAnchorTo)
    if not two then title:SetWidth(math.max(60, (bar:GetWidth() or 300) - 60)) end
end

-- A cover's background, border, header cut and title, from the settings.
-- The colour editor's repaint comes through here as well (it is the
-- cover's _zPaint), so a picked colour survives it and an unset one
-- follows the theme.
function Kit.StyleCover(f)
    local db = Kit.DB()
    if f._zFill then f._zFill:SetVertexColor(Kit.Color("bg", "ui", "windowBg", 1)) end
    if f._zBorder then
        local r, g, b, a = Kit.Color("border", "ui", "border")
        for _, t in ipairs(f._zBorder) do t:SetVertexColor(r, g, b, a) end
    end
    local bar = f.titleBar
    -- the header art's step is cut from the window's own colour
    local art = bar and bar._zArt
    if art and type(db.bg) == "table" then
        local r, g, b = Kit.Color("bg", "ui", "windowBg", 1)
        if art.cutL then art.cutL:SetVertexColor(r, g, b, 1) end
        if art.cutD then art.cutD:SetVertexColor(r, g, b, 1) end
    end
    local t = f.titleText
    if t then
        if ns.ApplyFontSpec then ns.ApplyFontSpec(t, db.titleFont, Kit.TitleFontDefaults()) end
        t:SetTextColor(Kit.Color("titleColor", "text", "gold"))
    end
    Kit.PlaceTitle(f)
end

-- Every cover made (not the settings preview's), and the top-level
-- window each one sits in - the frame the game opens and closes, and
-- the one that is scaled and animated.
Kit.covers = {}
Kit.tops = {}

local function TopOf(host)
    local top = host
    while top and top.GetParent and top:GetParent() and top:GetParent() ~= UIParent do
        top = top:GetParent()
    end
    return top
end

local function Locked(frame)
    return InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected()
end

-- SCALE. A window nobody rescaled is never touched (1 and never set); a
-- protected window in combat waits for the fight to end.
local scaleWaiting = false
local function ScaleTop(top)
    local s = tonumber(Kit.DB().scale) or 1
    s = math.max(0.5, math.min(2, s))
    if s == 1 and not top._zWinScaled then return end
    if Locked(top) then scaleWaiting = true return end
    if ns.Motion and ns.Motion.IsPlaying(top) then ns.Motion.Stop(top) end
    if top:GetScale() ~= s then top:SetScale(s) end
    top._zWinScaled = true
end

function Kit.ApplyScale()
    scaleWaiting = false
    for top in pairs(Kit.tops) do ScaleTop(top) end
end

-- OPENING. The game shows these windows itself and puts them in their
-- place as it does (its own slots, or where you dragged them, a frame
-- later), so an animation starts one frame after the show - from where
-- the window really is - with the window held at nothing for that frame
-- so it is never seen at rest first. Closing stays instant: the game
-- hides these windows itself, and holding one open to animate it out
-- would mean taking its closing over. Plays through ns.Motion, so
-- Appearance > Motion's switch and speed apply.
local function Opening(top)
    local spec = Kit.DB().openAnim
    if not (ns.Motion and type(spec) == "table" and spec.style and spec.style ~= "none") then return end
    if not ns.Motion.Enabled() or Locked(top) then return end
    if top._zWinOpening == nil then top._zWinOpening = top:GetAlpha() or 1 end
    top:SetAlpha(0)
    C_Timer.After(0, function()
        local was = top._zWinOpening
        top._zWinOpening = nil
        if was then top:SetAlpha(was) end
        if not top:IsShown() or Locked(top) then return end
        ns.Motion.Play(top, Kit.DB().openAnim, "in")
    end)
end

local regenWatch
local function RegisterTop(host)
    local top = TopOf(host)
    if not top or Kit.tops[top] then return end
    Kit.tops[top] = true
    if top.HookScript then top:HookScript("OnShow", Opening) end
    ScaleTop(top)
    if not regenWatch then
        regenWatch = CreateFrame("Frame")
        regenWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
        regenWatch:SetScript("OnEvent", function()
            if scaleWaiting then Kit.ApplyScale() end
        end)
    end
end

-- Everything above, on every window open or not: called after a change
-- on the Game windows page (at most once a frame - the page coalesces).
function Kit.ApplyLook()
    for _, f in ipairs(Kit.covers) do
        Kit.StyleCover(f)
        if f.titleBar and f.titleBar._zPaint then f.titleBar:_zPaint() end
    end
    Kit.ApplyScale()
    -- the row texts' spots: every list on screen redraws (one that is
    -- not, on its next open); only once a row text was ever placed
    if Kit.rowTextsUsed or (Kit.RowSpecs and Kit.RowSpecs()) then
        Kit.rowTextsUsed = true
        for list in pairs(Kit.lists) do
            if list:IsVisible() then list:Refresh() end
        end
    end
end

-- ============================================================
-- COVER WINDOW
-- ============================================================
-- opts.preview  a sample for the settings preview: laid over `host`
--               exactly, no drag, never registered or scaled
-- opts.name     global name (for /fstack and so other code can find it)
-- opts.title    initial title text
-- opts.onClose  what the X does (close the Blizzard panel, normally)
-- opts.insetName which panel inset preset to read (defaults to host name)
-- opts.width/height  fixed size instead of the panel's own rectangle
function Kit.Cover(host, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", opts.name, host)
    f:SetFrameStrata(host:GetFrameStrata())
    -- Well above anything Blizzard parents to its own window (their rows
    -- and buttons sit a few levels up), so nothing pokes through.
    f:SetFrameLevel(math.min(host:GetFrameLevel() + 50, 9000))
    f:EnableMouse(true)
    -- Mouse wheel is claimed by the list inside; claiming it here too
    -- stops a wheel over the footer from zooming the camera.
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function() end)

    -- opts.width / opts.height: a window BIGGER than Blizzard's panel (the
    -- three-tree talent view, the profession window). It keeps the panel's
    -- top-left corner, so it still opens where the panel would, and just
    -- extends right / down from there.
    local hostName = opts.insetName or (host.GetName and host:GetName())
    local function Place()
        if opts.preview then
            f:ClearAllPoints()
            f:SetAllPoints(host)
            return
        end
        local ins = ns.GetPanelInset(hostName, host)
        if opts.width or opts.height then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", host, "TOPLEFT", ins.l or 0, -(ins.t or 0))
            f:SetSize(opts.width or (host:GetWidth() - (ins.l or 0) - (ins.r or 0)),
                      opts.height or (host:GetHeight() - (ins.t or 0) - (ins.b or 0)))
        else
            ns.AnchorPanel(f, host, ins)
        end
    end
    Place()
    f.Reanchor = Place

    -- Opaque, unlike a free window's 0.97: a cover that lets Blizzard's
    -- art ghost through is exactly the "stuff showing through" bug.
    UI.Fill(f, "ui", "windowBg", 1)
    UI.Border(f, "ui", "border")
    -- the theme's colours, or the ones picked on the Game windows page
    f._zPaint = Kit.StyleCover

    local bar = CreateFrame("Frame", nil, f)
    bar:SetHeight(M.TITLEBAR)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    UI.Fill(bar, "ui", "headerBg")
    -- the same header art as every ZacUI window (UIF_Controls)
    if UI.HeaderArt then UI.HeaderArt(bar, { stepX = opts.stepX or 150 }) end

    local icon = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    icon._zui_own = true
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 8, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    SharpenIcon(icon)
    icon:Hide()

    local title = UI.Font(bar, F.TITLE, { text = opts.title or "", cat = "text", key = "gold" })
    -- gold unless a colour is picked on the Game windows page
    title._zPaint = function(self) self:SetTextColor(Kit.Color("titleColor", "text", "gold")) end
    title:SetPoint("LEFT", 10, 2)
    title:SetPoint("RIGHT", bar, "RIGHT", -34, 2)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    bar._zPaint = function(self)
        if UI.PaintHeaderArt then UI.PaintHeaderArt(self)
        else
            local h = GetColor("ui", "headerBg")
            self._zFill:SetVertexColor(h.r, h.g, h.b, h.a or 1)
        end
        title:_zPaint()
        -- the step in the header art follows a picked window colour
        if self._zArt and type(Kit.DB().bg) == "table" then
            local r, g, b = Kit.Color("bg", "ui", "windowBg", 1)
            if self._zArt.cutL then self._zArt.cutL:SetVertexColor(r, g, b, 1) end
            if self._zArt.cutD then self._zArt.cutD:SetVertexColor(r, g, b, 1) end
        end
    end

    local close = UI.CloseX(bar, 22, function()
        if opts.onClose then opts.onClose() elseif not opts.preview then HideUIPanel(host) end
    end)
    close:SetPoint("RIGHT", -5, 0)

    -- Drag the window by its title bar (the position is remembered).
    if ns.AttachWindowDrag and not opts.preview then ns.AttachWindowDrag(bar, host) end

    function f:SetTitle(text) title:SetText(text or "") end
    function f:SetIcon(tex)
        if tex then
            icon:SetTexture(tex)
            icon:Show()
            if f._zTitleMoved then Kit.PlaceTitle(f) else title:SetPoint("LEFT", icon, "RIGHT", 7, 2) end
        else
            icon:Hide()
            if f._zTitleMoved then Kit.PlaceTitle(f) else title:SetPoint("LEFT", 10, 2) end
        end
    end

    f.titleBar, f.titleText, f.closeButton, f.titleIcon = bar, title, close, icon
    if opts.preview and ns.TagElement then
        -- the pick hook: the settings preview's title and icon
        ns.TagElement(title, "windows.title") ns.TagElement(icon, "windows.icon")
    end
    -- Content area: everything between the title bar and the bottom edge.
    f.top = -(M.TITLEBAR + Kit.PAD)
    f:_zPaint()
    bar:_zPaint()
    if not opts.preview then
        Kit.covers[#Kit.covers + 1] = f
        RegisterTop(host)
    end
    return f
end

-- ============================================================
-- TABS
-- ============================================================
-- A row of flat buttons, one active. Width follows the label, so a
-- localised "Buyback" never runs out of its box.
function Kit.Tabs(parent, specs, onSelect, opts)
    opts = opts or {}
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(Kit.TAB_H)
    strip.buttons, strip.active = {}, nil
    local prev
    for i, spec in ipairs(specs) do
        local b = UI.Button(strip, spec.label, { height = Kit.TAB_H, size = F.CARD })
        local w = math.max(opts.minWidth or 64, math.ceil(b._zText:GetStringWidth()) + 28)
        b:SetWidth(w)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 3, 0)
        else
            b:SetPoint("LEFT", strip, "LEFT", 0, 0)
        end
        b:SetScript("OnClick", function() strip:Select(spec.key, true) end)
        if spec.tooltip then UI.Tooltip(b, spec.label, spec.tooltip) end
        b._zKey = spec.key
        strip.buttons[i] = b
        prev = b
    end

    -- Paint only: light the tab without running the callback (used to
    -- snap back when a switch has to be refused, e.g. in combat).
    function strip:Paint(key)
        self.active = key
        for _, b in ipairs(self.buttons) do b:SetActive(b._zKey == key) end
    end
    function strip:Select(key, fromClick)
        self:Paint(key)
        if onSelect then onSelect(key, fromClick) end
    end
    function strip:SetShownKey(key, shown)
        for _, b in ipairs(self.buttons) do
            if b._zKey == key then b:SetShown(shown) end
        end
        -- Re-chain so a hidden tab leaves no hole.
        local last
        for _, b in ipairs(self.buttons) do
            if b:IsShown() then
                b:ClearAllPoints()
                if last then b:SetPoint("LEFT", last, "RIGHT", 3, 0)
                else b:SetPoint("LEFT", self, "LEFT", 0, 0) end
                last = b
            end
        end
    end
    function strip:SetLabel(key, text)
        for _, b in ipairs(self.buttons) do
            if b._zKey == key then
                b:SetLabel(text)
                b:SetWidth(math.max(opts.minWidth or 64, math.ceil(b._zText:GetStringWidth()) + 28))
            end
        end
    end
    return strip
end

-- ============================================================
-- SEARCH + CHIPS
-- ============================================================
-- The search box is UI.EditBox with a hint, which already brings the
-- clear X. Filtering runs on every keystroke - the lists here are a few
-- hundred rows at most, and a search that waits for Enter feels broken.
function Kit.Search(parent, width, onChange, hint)
    local box = UI.EditBox(parent, {
        width = width, height = Kit.SEARCH_H,
        hint = hint or (SEARCH or "Search"),
        onChange = onChange,
        onEnter = onChange,
    })
    return box
end

-- A toggle chip: a small button that stays lit while it is on.
function Kit.Chip(parent, label, initial, onToggle, tooltip)
    local b = UI.Button(parent, label, { height = Kit.SEARCH_H, size = F.SMALL })
    b:SetWidth(math.ceil(b._zText:GetStringWidth()) + 16)
    b._zOn = initial and true or false
    b:SetActive(b._zOn)
    b:SetScript("OnClick", function(self)
        self._zOn = not self._zOn
        self:SetActive(self._zOn)
        -- A callback that returns false refused the change (combat, most
        -- often): put the chip back the way it was.
        if onToggle and onToggle(self._zOn) == false then
            self._zOn = not self._zOn
            self:SetActive(self._zOn)
        end
    end)
    function b:IsOn() return self._zOn end
    function b:SetOn(on)
        self._zOn = on and true or false
        self:SetActive(self._zOn)
    end
    if tooltip then UI.Tooltip(b, label, tooltip) end
    return b
end

-- ============================================================
-- ICON
-- ============================================================
-- Square icon with a 1px border that carries item quality, a count in
-- the corner and an optional cooldown swipe. Plain textures on a plain
-- frame - no ItemButton template, so there is no Blizzard art to strip.
function Kit.Icon(parent, size, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex._zui_own = true
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    SharpenIcon(tex)
    f.texture = tex
    UI.Fill(f, "ui", "elementBg")
    UI.Border(f, "ui", "border")
    f._zPaint = UI.PaintBox
    f:_zPaint()

    local count = UI.Font(f, F.SMALL, { justify = "RIGHT" })
    count:SetPoint("BOTTOMRIGHT", -2, 2)
    f.count = count

    if opts.cooldown then
        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints(tex)
        if cd.SetDrawEdge then cd:SetDrawEdge(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        f.cooldown = cd
    end

    function f:SetIcon(t) self.texture:SetTexture(t) end
    function f:SetCount(n)
        if n and n > 1 then self.count:SetText(n) else self.count:SetText("") end
    end
    -- nil quality = the plain border.
    function f:SetQuality(q)
        local r, g, b, a
        if q and q >= 2 then
            r, g, b = ns.QualityRGB(q)
            a = 1
        else
            local c = GetColor("ui", "border")
            r, g, b, a = c.r, c.g, c.b, c.a or 1
        end
        for _, s in ipairs(self._zBorder) do s:SetVertexColor(r, g, b, a) end
    end
    -- Blizzard's own "can't use this" cue: the icon tinted red.
    function f:SetUsable(ok)
        if ok then self.texture:SetVertexColor(1, 1, 1)
        else self.texture:SetVertexColor(0.9, 0.2, 0.2) end
    end
    function f:SetDesaturated(on)
        self.texture:SetDesaturated(on and true or false)
    end
    return f
end

-- ============================================================
-- VIRTUAL LIST
-- ============================================================
-- A fixed pool of rows - only as many as fit - over a data array, with a
-- scroll offset. A merchant with sixty items or a spellbook with every
-- rank still builds a dozen frames, not a frame per entry.
--
-- opts.rowHeight   row height (Kit.ROW_H)
-- opts.template    row frame template (secure lists pass one)
-- opts.build(row)  add the row's widgets, once per pooled row
-- opts.update(row, item, index)  fill a row for one entry
-- opts.secure      rows are protected: never re-map them in combat
-- opts.empty       text shown when the data is empty
-- opts.fallbackRows rows to build before the list has been measured
-- EVERY LIST'S ROW TEXTS, placeable (windows.anchors.<rowName|rowSub|
-- rowRight>, ZacUI's anchor shape): a row's main text (nameText / name),
-- its second line (sub) and its right-hand column (priceText / right /
-- cost / money), in every window's list at once. Where the window put the
-- text is the default - read off the text itself after the window filled
-- the row (a window that re-anchors a text, an indent, is followed) - and
-- the saved anchor goes on top. Nothing saved = never touched.
Kit.ROW_TEXTS = { "rowName", "rowSub", "rowRight" }
Kit.ROW_TEXT_LABELS = { rowName = "Row names", rowSub = "Second lines", rowRight = "Right-hand column",
    row = "The row", icon = "The row's icon" }
Kit.ROW_TARGETS = { { value = "row", text = "The row" }, { value = "icon", text = "The row's icon" },
    { value = "rowName", text = "Row names" }, { value = "rowSub", text = "Second lines" },
    { value = "rowRight", text = "Right-hand column" } }
local function RowText(row, key)
    if key == "rowName" then return row.nameText or row.name end
    if key == "rowSub" then return row.sub end
    return row.priceText or row.right or row.cost or row.money
end
Kit.RowText = RowText
-- what the picker shows as "where each window put it" (the usual row:
-- name and second line beside the icon, the column on the right)
function Kit.RowTextDefaults(key)
    if key == "rowSub" then return { point = "BOTTOMLEFT", relPoint = "BOTTOMRIGHT", x = 7, y = 2, justify = "LEFT" } end
    if key == "rowRight" then return { point = "RIGHT", relPoint = "RIGHT", x = -4, y = 0, justify = "RIGHT" } end
    return { point = "TOPLEFT", relPoint = "TOPRIGHT", x = 7, y = -2, justify = "LEFT" }
end
local function RowSpecs()
    local db = Kit.DB()
    local a = type(db.anchors) == "table" and db.anchors or nil
    if not a then return nil end
    if a.rowName or a.rowSub or a.rowRight then return a end
    return nil
end
Kit.RowSpecs = RowSpecs
local function Capture(fs, d)
    local n = fs:GetNumPoints() or 0
    if n < 1 then return false end
    local p, rel, rp, x, y = fs:GetPoint(1)
    d.point, d.to, d.relPoint, d.x, d.y = p, rel, rp, x, y
    if n >= 2 then
        local p2, rel2, rp2, x2, y2 = fs:GetPoint(2)
        d.point2, d.to2, d.relPoint2, d.x2, d.y2 = p2, rel2, rp2, x2, y2
    else
        d.point2, d.to2, d.relPoint2, d.x2, d.y2 = nil, nil, nil, nil, nil
    end
    d.justify = fs.GetJustifyH and fs:GetJustifyH() or nil
    d.w = fs:GetWidth()
    return true
end
-- still where this file put it last (else the window re-placed it)
local function Ours(fs, m)
    if not m or (fs:GetNumPoints() or 0) ~= m.n then return false end
    local p, rel, rp, x, y = fs:GetPoint(1)
    return p == m[1] and rel == m[2] and rp == m[3] and x == m[4] and y == m[5]
end
function Kit.PlaceRowTexts(row, specs)
    if not ns.ApplyAnchor then return end
    if not row._zRowTo then
        row._zRowTo = function(k)
            if k == "row" then return row elseif k == "icon" then return row.icon end
            if k == "rowName" or k == "rowSub" or k == "rowRight" then return RowText(row, k) end
        end
    end
    for _, key in ipairs(Kit.ROW_TEXTS) do
        local fs = RowText(row, key)
        if fs and fs.SetPoint then
            local spec = specs and specs[key] or nil
            if type(spec) ~= "table" or next(spec) == nil then spec = nil end
            local m = fs._zRowMark
            if spec or m then
                local d = fs._zRowDef or {}
                fs._zRowDef = d
                local okDef = true
                if not Ours(fs, m) then okDef = Capture(fs, d) end
                if okDef then
                    local _, two = ns.ApplyAnchor(fs, spec, d, row._zRowTo)
                    if spec and not two and d.point2 then fs:SetWidth(math.max(40, tonumber(d.w) or 120)) end
                    if spec then
                        m = m or {}
                        m[1], m[2], m[3], m[4], m[5] = fs:GetPoint(1)
                        m.n = fs:GetNumPoints()
                        fs._zRowMark = m
                    else
                        fs._zRowMark = nil
                    end
                end
            end
        end
    end
end

Kit.lists = setmetatable({}, { __mode = "k" })
function Kit.List(parent, opts)
    opts = opts or {}
    local rh = opts.rowHeight or Kit.ROW_H
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.data, list.offset = {}, {}, 0
    Kit.lists[list] = true

    -- Scrollbar: the same look as UI.ScrollArea's, driven by the offset.
    local bar = CreateFrame("Slider", nil, list)
    bar:SetWidth(M.SCROLL_W - 4)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
    local track = CreateFrame("Frame", nil, bar)
    track:SetPoint("TOPLEFT", 2, 0)
    track:SetPoint("BOTTOMRIGHT", -2, 0)
    track:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
    UI.Fill(track, "scrollbar", "track")
    UI.Border(track, "ui", "border")
    track._zPaint = UI.PaintBox
    track:_zPaint()
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb._zui_own = true
    thumb:SetTexture(TEX_THUMB or FLAT)
    thumb:SetSize(M.SCROLL_W - 8, 30)
    bar:SetThumbTexture(thumb)
    bar._zPaint = function()
        local t = GetColor("scrollbar", "thumb")
        thumb:SetVertexColor(t.r, t.g, t.b, t.a or 0.9)
    end
    bar:_zPaint()
    list.bar = bar

    local body = CreateFrame("Frame", nil, list)
    body:SetPoint("TOPLEFT")
    body:SetPoint("BOTTOMRIGHT", -(M.SCROLL_W + 2), 0)
    list.body = body

    local empty = UI.Font(list, F.LABEL, { cat = "text", key = "gray", justify = "CENTER" })
    empty:SetPoint("TOP", body, "TOP", 0, -24)
    empty:SetText(opts.empty or "")
    empty:Hide()
    list.emptyText = empty

    -- opts.fallbackRows covers a list primed while its window is still
    -- hidden and unmeasured (the spellbook primes its secure rows at login
    -- so a first open in combat is not a one-row list).
    local function Visible()
        local h = body:GetHeight() or 0
        if h < rh and opts.fallbackRows then return opts.fallbackRows end
        return math.max(1, math.floor((h + 1) / rh))
    end

    local function MaxOffset()
        return math.max(0, #list.data - Visible())
    end

    local function EnsureRows()
        local need = Visible()
        for i = #list.rows + 1, need do
            local row = CreateFrame(opts.frameType or "Button", nil, body, opts.template)
            row:SetHeight(rh)
            row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(i - 1) * rh)
            row:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe._zui_own = true
            stripe:SetAllPoints()
            stripe:SetTexture(FLAT)
            row.stripe = stripe
            local sel = row:CreateTexture(nil, "BORDER")
            sel._zui_own = true
            sel:SetAllPoints()
            sel:SetTexture(FLAT)
            sel:Hide()
            row.sel = sel
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl._zui_own = true
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.07)
            row.list = list
            if opts.build then opts.build(row, i) end
            list.rows[i] = row
        end
        return need
    end

    function list:Refresh()
        -- A protected row cannot be re-pointed at another entry in combat;
        -- the redraw is queued for when the fight ends instead.
        if opts.secure and InCombatLockdown() then
            self._zPending = true
            return
        end
        self._zPending = nil
        local visible = EnsureRows()
        local maxOff = MaxOffset()
        if self.offset > maxOff then self.offset = maxOff end
        if self.offset < 0 then self.offset = 0 end
        local e = Col("elementBg")
        local rowSpecs = RowSpecs()
        -- Selected rows are green like every selected thing; gold is hover.
        local acc = GetColor("ui", "borderSelected")
        for i, row in ipairs(self.rows) do
            local idx = self.offset + i
            local item = (i <= visible) and self.data[idx] or nil
            if item then
                row.item, row.index = item, idx
                row.stripe:SetVertexColor(e.r, e.g, e.b, (idx % 2 == 0) and 0.30 or 0.10)
                row.sel:SetVertexColor(acc.r, acc.g, acc.b, 0.25)
                row.sel:SetShown(self.selected ~= nil and self.selected == item)
                if opts.update then opts.update(row, item, idx) end
                if rowSpecs or row._zRowPlaced then
                    Kit.PlaceRowTexts(row, rowSpecs)
                    row._zRowPlaced = rowSpecs and true or nil
                end
                row:Show()
            else
                row.item, row.index = nil, nil
                row:Hide()
            end
        end
        self.emptyText:SetShown(#self.data == 0 and (opts.empty or self._zEmptyText) ~= nil)
        self._zSettingBar = true
        bar:SetMinMaxValues(0, maxOff)
        bar:SetValue(self.offset)
        self._zSettingBar = nil
        bar:SetShown(maxOff > 0)
        if maxOff > 0 then
            local h = bar:GetHeight() or 100
            thumb:SetHeight(math.max(24, math.floor(h * visible / #self.data)))
        end
    end

    function list:SetData(data, keepOffset)
        self.data = data or {}
        if not keepOffset then self.offset = 0 end
        self:Refresh()
    end

    function list:SetEmptyText(t)
        self._zEmptyText = t
        self.emptyText:SetText(t or "")
    end

    function list:Scroll(delta)
        if opts.secure and InCombatLockdown() then return end
        self.offset = math.max(0, math.min(MaxOffset(), self.offset - delta))
        self:Refresh()
    end

    function list:Select(item)
        self.selected = item
        self:Refresh()
    end

    bar:SetScript("OnValueChanged", function(_, v)
        if list._zSettingBar then return end
        if opts.secure and InCombatLockdown() then
            list._zSettingBar = true
            bar:SetValue(list.offset)
            list._zSettingBar = nil
            return
        end
        v = math.floor(v + 0.5)
        if v ~= list.offset then
            list.offset = v
            list:Refresh()
        end
    end)

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        self:Scroll(delta * (opts.wheelStep or 3))
    end)

    -- New room means more rows fit; rebuild the pool once the size settles.
    list:SetScript("OnSizeChanged", function(self) self:Refresh() end)

    -- Drain the combat-queued redraw.
    if opts.secure then
        local watch = CreateFrame("Frame", nil, list)
        watch:RegisterEvent("PLAYER_REGEN_ENABLED")
        watch:SetScript("OnEvent", function()
            if list._zPending then list:Refresh() end
        end)
    end
    return list
end

-- ============================================================
-- FOOTER
-- ============================================================
-- A strip along the bottom edge for money and actions, on the header
-- colour so it reads as window chrome rather than as another list row.
function Kit.Footer(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or Kit.FOOTER_H)
    f:SetPoint("BOTTOMLEFT", 1, 1)
    f:SetPoint("BOTTOMRIGHT", -1, 1)
    UI.Fill(f, "ui", "headerBg")
    local rule = f:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT")
    f._zPaint = function(self)
        local h = GetColor("ui", "headerBg")
        self._zFill:SetVertexColor(h.r, h.g, h.b, h.a or 1)
        local b = GetColor("ui", "border")
        rule:SetVertexColor(b.r, b.g, b.b, b.a or 1)
    end
    f:_zPaint()
    return f
end

-- An icon-only square action button (repair, sell junk ...).
function Kit.IconButton(parent, size, texture, tooltipTitle, tooltipBody, onClick)
    local b = UI.Button(parent, "", { width = size, height = size })
    local t = b:CreateTexture(nil, "ARTWORK", nil, 1)
    t._zui_own = true
    t:SetPoint("TOPLEFT", 3, -3)
    t:SetPoint("BOTTOMRIGHT", -3, 3)
    t:SetTexture(texture)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    SharpenIcon(t)
    b.icon = t
    if onClick then b:SetScript("OnClick", onClick) end
    if tooltipTitle then
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local tc = GetColor("tooltip", "title")
            -- _zTitle lets a reused button (a school tab) change its name.
            GameTooltip:AddLine(self._zTitle or tooltipTitle, tc.r, tc.g, tc.b)
            local body = type(tooltipBody) == "function" and tooltipBody() or tooltipBody
            if body then
                local c = GetColor("tooltip", "body")
                GameTooltip:AddLine(body, c.r, c.g, c.b, true)
            end
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
    function b:SetUsable(ok)
        self:SetDisabled(not ok)
        self.icon:SetDesaturated(not ok)
        self.icon:SetAlpha(ok and 1 or 0.5)
    end
    return b
end

-- ============================================================
-- HIDING BLIZZARD'S LEFTOVERS
-- ============================================================
-- Pieces of a Blizzard panel that hang OUTSIDE its visible rectangle
-- (bottom tabs, mostly) and so are not under the cover. Faded and made
-- click-through rather than hidden: Blizzard re-shows them in its own
-- update code, and fighting that Show every time is how skins flicker.
--
-- The mouse state is REMEMBERED, not assumed. Unsilence used to switch
-- the mouse ON for everything it had silenced - including pieces that
-- never took the mouse to begin with. A window's NineSlice is one of
-- those: an invisible frame-level-500 sheet over the whole window. Left
-- mouse-enabled, it swallows every click on whatever Blizzard page is
-- showing underneath - which is exactly what happened to the Send Mail
-- page after a visit to the Inbox tab: you could type and attach, but
-- the Send button could not be clicked.
--
-- opts (optional, the same table for Silence and Unsilence):
--   opts.once        a piece that is already silenced is left alone by a
--                    repeat Silence (no re-fade, no mouse call)
--   opts.framesOnly  only Frames have their mouse switched off; textures
--                    and font strings just fade
-- Protected pieces always keep their mouse: it cannot be changed from
-- here in combat, and nothing of ours needs it off.
local function MouseOK(f, opts)
    return f.EnableMouse and not (f.IsProtected and f:IsProtected())
        and not (opts and opts.framesOnly
            and not (f.IsObjectType and f:IsObjectType("Frame")))
end

function Kit.Silence(frames, opts)
    local once = opts and opts.once
    for _, f in ipairs(frames) do
        if f and f.SetAlpha and not (once and f._zKitAlpha ~= nil) then
            if f._zKitAlpha == nil then f._zKitAlpha = f:GetAlpha() or 1 end
            f:SetAlpha(0)
            if MouseOK(f, opts) then
                -- Read once, the first time we are about to switch it off
                -- (a piece skipped in combat still has its own state then).
                if f._zKitMouse == nil then
                    f._zKitMouse = (f.IsMouseEnabled and f:IsMouseEnabled()) and true or false
                end
                f:EnableMouse(false)
            end
        end
    end
end

function Kit.Unsilence(frames, opts)
    for _, f in ipairs(frames) do
        if f and f._zKitAlpha ~= nil then
            f:SetAlpha(f._zKitAlpha)
            f._zKitAlpha = nil
            if MouseOK(f, opts) then
                -- Back to what it was; a piece silenced before this was
                -- tracked (nil) keeps the old behaviour.
                local was = f._zKitMouse
                f._zKitMouse = nil
                f:EnableMouse(was ~= false)
            end
        end
    end
end

-- ============================================================
-- ONE REDRAW PER FRAME, ONLY WHILE ON SCREEN
-- ============================================================
-- Every window here redraws from events that arrive in bursts (bags,
-- item info, rosters, money). Kit.Coalesce(fn, frame) returns a queue
-- function: any number of calls in a frame run fn once on the next, and
-- a call while the window is not VISIBLE schedules nothing at all.
-- IsVisible, not IsShown: a cover is a shown child of its Blizzard panel
-- all session, so IsShown is true with no vendor / trade / mailbox open -
-- the Trade window repainted on every item-info event that way.
-- frame may be a function returning the frame, for windows built later
-- than their queue. fn runs with the arguments given here (args).
function Kit.Coalesce(fn, frame, ...)
    local n, a1, a2 = select("#", ...), ...
    local get = type(frame) == "function" and frame or function() return frame end
    return ns.Coalescer(function()
        if n > 0 then fn(a1, a2) else fn() end
    end, 0, function()
        local f = get()
        return f ~= nil and f:IsVisible()
    end)
end

-- Case-insensitive plain substring match; an empty query matches all.
function Kit.Matches(query, ...)
    if not query or query == "" then return true end
    for i = 1, select("#", ...) do
        local s = select(i, ...)
        if s and string.find(string.lower(s), query, 1, true) then return true end
    end
    return false
end

function Kit.NormalizeQuery(text)
    text = text and strtrim(text) or ""
    return string.lower(text)
end

-- shared with later ZacUI files
ns.Kit = Kit
