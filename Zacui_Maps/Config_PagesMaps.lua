-- Config_PagesMaps - the Maps page.
-- Part of ZacUI; load order is set by the TOC.
--
-- EVERY CONTROL HERE IS LIVE. Not one of them asks for a reload, which
-- is the whole reason the map layer installs its hooks once and reads
-- its settings from inside them. The addon this replaces marks eleven
-- of these same options "requires reload" because it does its setup in
-- one pass at login and a hook cannot be uninstalled afterwards.
--
-- THE PAGE (2026-11-01 settings pass): the standard tabs - General, Look,
-- Text, Animation, Position - then the battleground map and the seamless
-- world map (each a map of its own), then Advanced. Every setting kept
-- its saved key; the new look settings (fonts, colours, pin and dot
-- details, fade and glide timings, the opening animation) default to
-- exactly what the map drew before. The preview dock shows a sample map
-- built by the map's own pieces: the header (MapsSkin), the coordinate
-- strip and the dip over a zone change (MapsFrame), pins (MapsIcons) and
-- group dots (MapsGroup), with made-up places and people.

local ADDON_NAME = ...
-- Zacui_Maps is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local EnableModuleLive = ns.EnableModuleLive
local Print = ns.Print
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local UI = ns.UI

local M, F = UI.M, UI.F

-- ============================================================
-- SEARCH WORDS THE PAGE DOES NOT SAY
-- ============================================================
-- The menu row is Config_Base's; the words for what this pass added are
-- appended to it here, once, when the part loads.
if ns.AddMenuKeywords then
    ns.AddMenuKeywords("maps", "font fonts typeface outline shadow colour color colours colors"
        .. " halo glow pin pins icon icons size sizes dot dots name names"
        .. " header title strip decimals background window animation animate"
        .. " open opening appear dip blink glide ease smooth preview test")
end

-- A look setting changed: repaint the map once on the next frame, however
-- many changes landed in this one (a colour wheel drag is dozens).
local LookSoon
do
    local function Run() if ns.Maps and ns.Maps.ApplyLook then ns.Maps.ApplyLook() end end
    LookSoon = ns.Coalesce and ns.Coalesce(Run) or Run
end

-- One helper for the whole page. Every setting is a key in ZacUIDB.maps
-- and every change wants the same thing afterwards, so the alternative
-- is thirty copies of the same three lines. opts.look: a look setting
-- (repaint, see LookSoon) rather than one that re-applies the map.
local function Bind(L, kind, key, label, desc, opts)
    local Maps = ns.Maps
    if not Maps then return end
    local db = Maps.DB()
    opts = opts or {}

    local function changed(v)
        db[key] = v
        if opts.onChange then opts.onChange(v) end
        if opts.look then
            LookSoon()
        elseif Maps.Refresh then
            Maps.Refresh()
        end
        if opts.rebuild then RefreshConfig() end
    end

    local widget
    if kind == "check" then
        widget = UI.Checkbox(L.current, label, db[key] and true or false, changed)
        L:Row(widget, 17)
    else
        widget = UI.Slider(L.current, {
            width = opts.width or 200, min = opts.min, max = opts.max, step = opts.step,
            value = opts.get and opts.get(db[key]) or db[key],
            label = label, format = opts.format,
            onChange = function(v) changed(opts.set and opts.set(v) or v) end,
        })
        L:Row(widget, 40)
    end
    if opts.enabled ~= nil then UI.SetEnabled(widget, opts.enabled, opts.why) end
    if desc then L:Desc(desc) end
    return widget
end

-- Percent sliders over a 0..1 setting.
local function Pct(default)
    return {
        get = function(v) return math.floor((v or default or 1) * 100 + 0.5) end,
        set = function(v) return v / 100 end,
        format = function(v) return v .. "%" end,
    }
end
local function With(t, extra)
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

-- A colour setting. theme: what nil means - { cat, key, alpha } for a
-- palette colour (a lone name is one of ns.Col's), or { r, g, b, a } fixed.
local function BindColor(L, key, label, desc, theme, opts)
    local Maps = ns.Maps
    local db = Maps.DB()
    opts = opts or {}
    local function Read()
        if theme.fixed then return Maps.Color(key, theme.fixed) end
        return Maps.Color(key, theme[1], theme[2], theme[3])
    end
    local p = UI.ColorPicker(L.current, { label = label, alpha = opts.alpha ~= false,
        tooltip = opts.tooltip,
        get = Read,
        set = function(r, g, b, a)
            db[key] = { r = r, g = g, b = b, a = a or 1 }
            LookSoon()
        end })
    L:Add(p, 6)
    if opts.enabled ~= nil then UI.SetEnabled(p, opts.enabled, opts.why) end
    if desc then L:Desc(desc) end
    return p
end

-- A font setting (face, size, outline, shadow). base: the size step it
-- uses today (UI.F.*), which with the global size adjustment is what an
-- unset size means.
local function BindFont(L, key, label, desc, base, sample)
    local Maps = ns.Maps
    local db = Maps.DB()
    local p = UI.FontPicker(L.current, { label = label, width = 400,
        get = function() return db[key] end,
        set = function(spec) db[key] = spec LookSoon() end,
        defaults = Maps.FontDefaults(base), sample = sample })
    L:Add(p, 8)
    if desc then L:Desc(desc) end
    return p
end

local function ModeDropdown(L, key, label, onLabel, rebuild)
    local Maps = ns.Maps
    local db = Maps.DB()
    local ITEMS = { { text = "Class colour", value = "class" }, { text = onLabel, value = "custom" } }
    local f = UI.Field(L.current, label, function(h)
        return UI.Dropdown(h, { width = 180,
            items = function() return ITEMS end,
            selected = function() return db[key] == "custom" and onLabel or "Class colour" end,
            selectedValue = function() return db[key] == "custom" and "custom" or "class" end,
            onSelect = function(v)
                db[key] = v
                LookSoon()
                if rebuild then RefreshConfig() end
            end })
    end, { width = 180 })
    L:Add(f, 8)
    return f
end

-- ============================================================
-- THE PREVIEW: A SMALL MAP
-- ============================================================
-- A window like the map's - background, header, a patch of Durotar's map
-- art with one corner unexplored, a few pins, your arrow, five group dots
-- and the coordinate strip - every part made and styled by the map's own
-- functions. Modes: the world map standing still, the world map while
-- you move (its opacity), and the battleground map. Replay plays the
-- opening animation (or, while moving, the fade); "Zone change" plays the
-- dip over a map change.
-- The map exactly as it opens: the whole window (the zone's art at its
-- full 1002 x 668, the header and the coordinate strip) at the map's own
-- scale, and the battleground map at its width. The preview strip shows
-- them at their real size, or scaled down to fit (and says so). The
-- canvas is whichever is up, with room for the note beside it when
-- there is one.
local ART_W, ART_H = 1002, 668
local WIN_W = ART_W + 2
local PV_W, PV_H = 920, 640
local NOTE_W = 150
local ART = "Interface\\WorldMap\\Durotar\\Durotar"
-- the art is 1002 x 668 in 4 x 3 tiles of 256 (the last column and row
-- partial)
local ART_COLS = { 256, 256, 256, 234 }
local ART_ROWS = { 256, 256, 156 }

local FAKE_GROUP = {
    { 0.62, 0.50, "WARRIOR", "Zaccw" },
    { 0.632, 0.508, "PRIEST", "Lumi" },     -- close enough to show the declutter (at the real size)
    { 0.33, 0.36, "MAGE", "Brask" },
    { 0.44, 0.74, "ROGUE", "Kel" },
    { 0.80, 0.40, "HUNTER", "Tamsin" },
}
local FALLBACK_CLASS = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PRIEST = { 1, 1, 1 }, MAGE = { 0.41, 0.8, 0.94 },
    ROGUE = { 1, 0.96, 0.41 }, HUNTER = { 0.67, 0.83, 0.45 },
}
local function ClassRGB(class)
    if ns.ClassColor then
        local r, g, b = ns.ClassColor(class)
        if r then return r, g, b end
    end
    local c = FALLBACK_CLASS[class] or { 1, 1, 1 }
    return c[1], c[2], c[3]
end

-- a texture laid over a fraction of `area`
local function Place(tex, area, x1, y1, x2, y2)
    local w, h = area:GetWidth(), area:GetHeight()
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", area, "TOPLEFT", x1 * w, -y1 * h)
    tex:SetPoint("BOTTOMRIGHT", area, "TOPLEFT", x2 * w, -y2 * h)
end

local function BuildArt(area, w, h)
    local tiles = {}
    local totalW, totalH = 1002, 668
    local y = 0
    local n = 0
    for r, rh in ipairs(ART_ROWS) do
        local x = 0
        for c, cw in ipairs(ART_COLS) do
            n = n + 1
            local t = area:CreateTexture(nil, "BACKGROUND", nil, 1)
            t:SetTexture(ART .. n)
            t:SetTexCoord(0, cw / 256, 0, rh / 256)
            t:SetPoint("TOPLEFT", area, "TOPLEFT", x / totalW * w, -y / totalH * h)
            t:SetSize(cw / totalW * w, rh / totalH * h)
            tiles[n] = t
            x = x + cw
        end
        y = y + rh
    end
    return tiles
end

-- the sample pins: kind, x, y, rotation
local function SamplePins()
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Horde"
    local mine = (faction == "Alliance") and "FlightA" or "FlightH"
    local theirs = (faction == "Alliance") and "FlightH" or "FlightA"
    return {
        { mine, 0.55, 0.28, 0 },
        { theirs, 0.86, 0.66, 0 },
        { "Dungeon", 0.40, 0.56, 0 },
        { "Raid", 0.72, 0.18, 0 },
        { "Spirit", 0.24, 0.66, 0 },
        { "Arrow", 0.05, 0.45, math.pi / 2 },
    }
end

local function NewPin(parent)
    local pin = CreateFrame("Frame", nil, parent)
    pin.Texture = pin:CreateTexture(nil, "ARTWORK")
    pin.Texture:SetAllPoints(pin)
    return pin
end

local function BuildMapPreview(canvas, P)
    local st = P.store
    local S, Fr = ns.MapsSkin, ns.MapsFrame

    -- the world map window
    local headH = (S and S.HEADER_H) or 22
    local footH = (S and S.FOOTER_H) or 18
    local win = CreateFrame("Frame", nil, canvas)
    win:SetSize(WIN_W, ART_H + 2 + headH + footH)
    win:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    if ns.SkinBackdrop then ns.SkinBackdrop(win, "windowBg", 0.95) end
    st.win = win

    local bar = CreateFrame("Frame", nil, win)
    bar:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -1)
    bar:SetHeight(headH)
    bar:SetFrameLevel(win:GetFrameLevel() + 5)
    if S and S.MakeHeader then S.MakeHeader(bar) end
    if bar.title then bar.title:SetText("Durotar") end
    st.header = bar

    local area = CreateFrame("Frame", nil, win)
    area:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -(1 + headH))
    area:SetSize(ART_W, ART_H)
    if area.SetClipsChildren then area:SetClipsChildren(true) end
    st.area = area
    st.tiles = BuildArt(area, ART_W, ART_H)

    -- the unexplored corner: the same art again over the top-left tile,
    -- tinted the way the reveal tints it (or dark, with the reveal off)
    local fog = area:CreateTexture(nil, "BACKGROUND", nil, 3)
    fog:SetTexture(ART .. 1)
    fog:SetTexCoord(0, 1, 0, 1)
    fog:SetAllPoints(st.tiles[1])
    st.fog = fog

    -- pins
    st.pins = {}
    for i, rec in ipairs(SamplePins()) do
        local pin = NewPin(area)
        pin:SetPoint("CENTER", area, "TOPLEFT", rec[2] * area:GetWidth(), -rec[3] * area:GetHeight())
        pin:SetFrameLevel(area:GetFrameLevel() + 2)
        pin.rec = rec
        st.pins[i] = pin
    end

    -- your arrow
    local arrowHost = CreateFrame("Frame", nil, area)
    arrowHost:SetFrameLevel(area:GetFrameLevel() + 6)
    arrowHost:SetAllPoints(area)
    local arrow = arrowHost:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow:SetPoint("CENTER", area, "TOPLEFT", 0.5 * area:GetWidth(), -0.44 * area:GetHeight())
    if arrow.SetRotation then arrow:SetRotation(-0.6) end
    st.arrow = arrow

    -- the group
    st.dots = {}
    if ns.MapsGroup and ns.MapsGroup.NewDot then
        for i, m in ipairs(FAKE_GROUP) do
            local dot = ns.MapsGroup.NewDot(area)
            dot:SetFrameLevel(area:GetFrameLevel() + 4)
            dot:SetPoint("CENTER", area, "TOPLEFT", m[1] * area:GetWidth(), -m[2] * area:GetHeight())
            st.dots[i] = dot
        end
    end
    st.declutter = ns.Maps.NewDeclutter and ns.Maps.NewDeclutter()

    -- the coordinate strip
    local strip = CreateFrame("Frame", nil, win)
    strip:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 1, 1)
    strip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, 1)
    strip:SetHeight(footH)
    strip:SetFrameLevel(win:GetFrameLevel() + 5)
    if Fr and Fr.MakeStrip then Fr.MakeStrip(strip) end
    st.strip = strip

    -- the dip over a zone change, on the sample window
    if Fr and Fr.NewBlink then st.blink, st.blinkFrame = Fr.NewBlink(win) end

    -- the battleground map
    local bf = CreateFrame("Frame", nil, canvas)
    bf:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    bf:SetSize(300, 200)
    if ns.SkinBackdrop then ns.SkinBackdrop(bf, "windowBg", 0.95) end
    local bfArea = CreateFrame("Frame", nil, bf)
    bfArea:SetPoint("TOPLEFT", bf, "TOPLEFT", 1, -1)
    bfArea:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1, 1)
    bfArea:SetSize(298, 198)
    st.bfArea = bfArea
    st.bfTiles = BuildArt(bfArea, 298, 198)
    local bfArrowHost = CreateFrame("Frame", nil, bfArea)
    bfArrowHost:SetAllPoints(bfArea)
    bfArrowHost:SetFrameLevel(bfArea:GetFrameLevel() + 6)
    st.bfArrow = bfArrowHost:CreateTexture(nil, "OVERLAY")
    st.bfArrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    if st.bfArrow.SetRotation then st.bfArrow:SetRotation(-0.6) end
    st.bfDots = {}
    if ns.MapsGroup and ns.MapsGroup.NewDot then
        for i = 1, 3 do
            local d = ns.MapsGroup.NewDot(bfArea)
            d:SetFrameLevel(bfArea:GetFrameLevel() + 4)
            if d.label then d.label:Hide() end
            st.bfDots[i] = d
        end
    end
    st.bf = bf

    local note = UI.Font(canvas, F.SMALL, { text = "", cat = "text", key = "gray", justify = "LEFT",
        width = NOTE_W, wrap = true })
    note:SetPoint("LEFT", win, "RIGHT", 8, 0)
    st.note = note
end

-- the canvas: the window (or battleground map) up, and the note beside
-- it when it says something (the frame stays centred: room both sides)
local function FitMapCanvas(P, frame)
    if not P.Resize then return end
    local st = P.store
    st.note:ClearAllPoints()
    st.note:SetPoint("LEFT", frame, "RIGHT", 8, 0)
    local hasNote = (st.note:GetText() or "") ~= ""
    -- (the window at the map's own scale, as it opens in game)
    local k = frame:GetScale() or 1
    local w, h = (frame:GetWidth() or WIN_W) * k, (frame:GetHeight() or ART_H) * k
    P.Resize(w + (hasNote and 2 * (NOTE_W + 8) or 0) + 8, h + 8)
end

-- what the map's fade aims for in this mode (Maps_Frame's TargetAlpha,
-- without the cursor test - the sample is never under it)
local function SampleAlpha(db, mode)
    if not db.fade then return 1 end
    if mode == "moving" then return db.movingAlpha or 0.5 end
    return db.stillAlpha or 1
end

local function SampleBusy(st)
    if st.fading then return true end
    if st.blinkFrame and st.blinkFrame:IsShown() then return true end
    return ns.Motion and ns.Motion.IsPlaying(st.win) or false
end

local function UpdateMapPreview(canvas, P)
    local st = P.store
    local Maps = ns.Maps
    local db = Maps.DB()
    local mode = P.mode or "still"
    local S, Fr, I, G, R = ns.MapsSkin, ns.MapsFrame, ns.MapsIcons, ns.MapsGroup, ns.MapsReveal
    local openMap = Maps.OpenMapLoaded and Maps.OpenMapLoaded()

    local bfMode = (mode == "bg")
    st.win:SetShown(not bfMode)
    st.bf:SetShown(bfMode)

    if bfMode then
        -- the battleground map: its width, opacity, your arrow and the
        -- group's icons
        local w = tonumber(db.bfSize) or 380
        local h = math.floor(w / 1.5 + 0.5)
        st.bf:SetSize(w, h)
        st.bfArea:SetSize(w - 2, h - 2)
        local idx = 0
        local yy = 0
        for _, rh in ipairs(ART_ROWS) do
            local xx = 0
            for _, colw in ipairs(ART_COLS) do
                idx = idx + 1
                local t = st.bfTiles[idx]
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", st.bfArea, "TOPLEFT", xx / 1002 * (w - 2), -yy / 668 * (h - 2))
                t:SetSize(colw / 1002 * (w - 2), rh / 668 * (h - 2))
                xx = xx + colw
            end
            yy = yy + rh
        end
        st.bf:SetAlpha(db.battlefield and (db.bfAlpha or 1) or 0.25)
        local as = tonumber(db.bfArrowSize) or 30
        st.bfArrow:SetSize(as, as)
        st.bfArrow:ClearAllPoints()
        st.bfArrow:SetPoint("CENTER", st.bfArea, "TOPLEFT", 0.5 * (w - 2), -0.5 * (h - 2))
        local is = tonumber(db.bfIconSize) or 18
        local spots = { { 0.35, 0.4, "WARRIOR" }, { 0.62, 0.62, "PRIEST" }, { 0.7, 0.3, "MAGE" } }
        for i, d in ipairs(st.bfDots) do
            local sp = spots[i]
            d:SetSize(is, is)
            d:ClearAllPoints()
            d:SetPoint("CENTER", st.bfArea, "TOPLEFT", sp[1] * (w - 2), -sp[2] * (h - 2))
            local r, g, b = ClassRGB(sp[3])
            d.tex:SetVertexColor(r, g, b)
            if d.edge then d.edge:Hide() end
        end
        st.note:SetText(db.battlefield and "" or "The battleground map is Blizzard's own while this is off.")
        FitMapCanvas(P, st.bf)
        return
    end

    -- the window at the map's scale, its background, header and opacity
    if not SampleBusy(st) then
        local sc = tonumber(db.scale) or 0.9
        if math.abs((st.win:GetScale() or 1) - sc) > 1e-4 then st.win:SetScale(sc) end
    end
    if S and S.PaintWindowBg then S.PaintWindowBg(st.win) end
    if S and S.PaintHeader then S.PaintHeader(st.header) end
    if not SampleBusy(st) then st.win:SetAlpha(SampleAlpha(db, mode)) end

    -- the unexplored corner
    -- (a game version where the map's data does not run - Retail: no
    -- unexplored-area drawing and no pins there, so none in the sample)
    local dataOn = not (Maps.DataOn and not Maps.DataOn())
    local revealOn = db.reveal and not openMap and dataOn
    if revealOn then
        st.fog:SetTexture(ART .. 1)
        local r, g, b, a = 1, 1, 1, 1
        if R and R.TintOf then r, g, b, a = R.TintOf() end
        st.fog:SetVertexColor(r, g, b, a)
        st.fog:Show()
    elseif openMap or not dataOn then
        st.fog:Hide()
    else
        st.fog:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8X8")
        st.fog:SetVertexColor(0, 0, 0, 0.88)
        st.fog:Show()
    end

    -- pins, through the same "is this wanted" and dressing as the map's
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    for _, pin in ipairs(st.pins) do
        local kind, rot = pin.rec[1], pin.rec[4]
        local info = I and I.KINDS and I.KINDS[kind]
        local want = dataOn and info and I.Wanted and I.Wanted(kind, faction)
        if want then
            local atlas = Maps.Atlas and Maps.Atlas(unpack(info.atlas))
            if atlas and pin.Texture.SetAtlas then
                pin.Texture:SetAtlas(atlas)
                pin.Texture:SetVertexColor(1, 1, 1, 1)
            else
                pin.Texture:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8X8")
                pin.Texture:SetVertexColor(1, 0.82, 0, 1)
            end
            if pin.Texture.SetRotation then pin.Texture:SetRotation(rot) end
            I.Dress(pin, atlas, rot, info.size, kind)
            pin:Show()
        else
            pin:Hide()
        end
    end

    -- your arrow: Blizzard's 16, or the enlarged size
    local asz = db.bigArrow and (tonumber(db.arrowSize) or 18) or 16
    st.arrow:SetSize(asz, asz)

    -- the group, dressed and decluttered by the map's own code
    if G and G.Look and db.classIcons then
        local L = G.Look(1)
        if st.declutter then st.declutter.Reset() end
        local w, h = st.area:GetWidth(), st.area:GetHeight()
        for i, dot in ipairs(st.dots) do
            local m = FAKE_GROUP[i]
            local r, g, b = ClassRGB(m[3])
            G.Paint(dot, L, r, g, b, m[4], nil)
            G.PlaceName(dot, L, m[1] * w, -m[2] * h, st.declutter)
            dot:Show()
        end
    else
        for _, dot in ipairs(st.dots) do dot:Hide() end
    end

    -- the coordinate strip
    local strip = st.strip
    if Fr and Fr.StyleStrip and strip.player then
        Fr.StyleStrip(strip)
        strip.player:SetText(Fr.CoordText("Player", 0.524, 0.381))
        -- the zone keeps clear of a wide position text, as on the map
        if Fr.KeepZoneClear then Fr.KeepZoneClear(strip) end
        strip.cursor:SetText(Fr.CoordText("Cursor", 0.61, 0.442))
        local zone = ""
        if db.zoneLevels then
            zone = "10-20"
            if db.fishingLevels then zone = zone .. "   fishing 25" end
        end
        strip.zone:SetText(zone)
    end
    strip:SetShown(db.coords and true or false)

    if not (ZacUIDB.modules and ZacUIDB.modules.maps) then
        st.note:SetText("The map layer is off - this is how it would look.")
    elseif mode == "moving" and not db.fade then
        st.note:SetText("Fading while moving is off.")
    else
        st.note:SetText("")
    end
    FitMapCanvas(P, st.win)
end

local function ReplayMapPreview(canvas, P)
    local st = P.store
    local db = ns.Maps.DB()
    local mode = P.mode or "still"
    local win = st.win
    if ns.Motion then ns.Motion.Stop(win) end
    win:SetScript("OnUpdate", nil)
    st.fading = nil
    if mode == "moving" then
        -- standing still, then off you go: the fade, at its own pace
        if not db.fade then return end
        local fr = ns.MapsFrame
        win:SetAlpha(SampleAlpha(db, "still"))
        st.fading = true
        local wait = 0
        win:SetScript("OnUpdate", function(self, el)
            wait = wait + el
            if wait < 0.1 then return end
            wait = 0
            local a, done = fr.FadeStep(self:GetAlpha() or 1, SampleAlpha(db, "moving"), db.fadeSpeed)
            self:SetAlpha(a)
            if done then
                st.fading = nil
                self:SetScript("OnUpdate", nil)
            end
        end)
    elseif mode == "still" then
        win:SetAlpha(SampleAlpha(db, "still"))
        local spec = db.openAnim
        if ns.Motion and type(spec) == "table" and spec.style ~= "none" then
            win:Hide()
            ns.Motion.Play(win, spec, "in")
        end
    end
end

local function MapPreviewControls(row, P)
    local b = UI.Button(row, "Zone change", { width = 92, height = 18,
        tooltip = "Plays the dip to dark and back that covers a change of map.",
        onClick = function()
            local st = P.store
            if (P.mode or "still") == "bg" or not st.blink then return end
            if not ns.Maps.DB().scrollFade then return end
            st.blink(st.win:GetAlpha())
        end })
    b:SetPoint("LEFT", row, "LEFT", 0, 0)
end

-- ============================================================
-- RESET THE LOOK
-- ============================================================
-- What the look settings were before anyone touched them: values for the
-- ones with a value, and the list of ones whose shipped value is "unset"
-- (the theme's colour, ZacUI's font).
local LOOK_VALUES = {
    pinHalo = true, pinHaloSize = 1.34, pinScaleFlight = 1, pinScaleDungeons = 1,
    pinScaleSpirit = 1, pinScaleCrossing = 1, dotColorMode = "class",
    dotNameColorMode = "class", dotBorderSize = 1, coordDecimals = 1, coordLabels = true,
    scrollFadeTime = 0.25, scrollFadeDepth = 0.3, smoothZoomTime = 0.15, fadeSpeed = 0.35,
}
local LOOK_UNSET = {
    "pinHaloColor", "dotColor", "dotNameColor", "dotBorderColor", "dotNameFont",
    "coordFont", "coordPlayerColor", "coordCursorColor", "coordZoneColor", "coordBg",
    "titleFont", "titleColor", "headerBg", "headerRule", "windowBg",
}

-- fadeSpeed (a fraction of the way each tenth of a second) as the time it
-- takes to get there, near enough (within 5%), and back
local function FadeSecs(f)
    f = math.max(0.05, math.min(0.99, tonumber(f) or 0.35))
    return 0.1 * math.log(0.05) / math.log(1 - f)
end
local function FadeFrac(secs)
    secs = math.max(0.1, tonumber(secs) or 0.7)
    return 1 - 0.05 ^ (0.1 / secs)
end

-- ============================================================
-- THE PAGE
-- ============================================================
RegisterPage("Maps", function(L)
    local Maps = ns.Maps
    L:Header("Maps",
        "The world map as a window you can move, size and see through, "
        .. "with the parts of the world you have not walked yet drawn in.")

    if not Maps then
        L:Notice("missing", "The map layer did not load. /zui maps says why.")
        return
    end

    local db = Maps.DB()
    local openMap = ns.Maps.OpenMapLoaded and ns.Maps.OpenMapLoaded()
    -- (options audit 2026-11-09) the pins, the unexplored areas, the zone
    -- and fishing levels, the sharper map and your own arrow are Classic
    -- Era's Azeroth data (Core_Flavor's "maps_data" row): where that does
    -- not run (Retail) their options are not shown; saved values stay
    local dataOn = not (Maps.DataOn and not Maps.DataOn())

    -- a strip text picked in the preview: its group on the Text tab
    if ns.CustomPick then
        ns.CustomPick.SetHandler("maps.map", function(el)
            if el ~= "maps.player" and el ~= "maps.cursor" and el ~= "maps.zone" then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            ZacUIDB.config.tabs.maps = "text"
            ns.RefreshConfig()
        end)
    end

    L:Preview({
        key = "maps.map",
        title = "Map",
        width = PV_W, height = PV_H,
        modes = {
            { id = "still", label = "Still" },
            { id = "moving", label = "Moving" },
            { id = "bg", label = "Battleground" },
        },
        modesLabel = "Show",
        build = BuildMapPreview,
        update = UpdateMapPreview,
        replay = ReplayMapPreview,
        controls = MapPreviewControls,
    })

    -- ================================================================
    -- GENERAL: on/off, and what the map shows
    -- ================================================================
    local function Tab_general(L)
        L:Card("The map layer")
        local cb = UI.Checkbox(L.current, "Use ZacUI's map",
            ZacUIDB.modules.maps and true or false,
            function(checked)
                if checked then
                    EnableModuleLive("maps")
                else
                    ZacUIDB.modules.maps = false
                    Print("Maps off - reload to give the map back to Blizzard.")
                end
            end)
        L:Row(cb, 17)
        L:Desc("Replaces Leatrix Maps entirely. Run both and they will fight "
            .. "over the same hooks, so turn that one off.")
        L:EndCard()

        -- THE WORLD MAP PART (2026-10-31). OpenMap rides inside ZacUI as
        -- Zacui_WorldMap: one stitched world, the wheel from the whole
        -- world to street level, its own window with a title bar and
        -- grips, its own pins. What it owns, ZacUI's settings let go of
        -- (Maps.OPENMAP_KEYS); its own settings are on the World map tab.
        if openMap then
            L:Card("The seamless world map")
            L:Desc("Every zone stitched into one map; scroll out of a zone into its "
                .. "neighbours and the whole world, left-click to dive in, right-click "
                .. "to come back out, Ctrl-click to drop a pin. It brings its own window "
                .. "(drag its title bar, pull a corner), its own dungeon, raid, flight, "
                .. "boat and zeppelin icons and its own unexplored-area drawing, so those "
                .. "ZacUI settings stand down while it is loaded. Built on OpenMap (MIT).")
            local omRow = UI.Holder(L.current)
            omRow:SetSize(300, M.BUTTON_H)
            local om = UI.Button(omRow, "World map settings", { width = 150,
                tooltip = "Opens the seamless map's own settings window (/openmap).",
                onClick = function()
                    local OM = _G.OpenMap
                    if OM and OM.OpenOptions then OM.OpenOptions() end
                end })
            om:SetPoint("LEFT")
            L:Row(omRow, M.BUTTON_H + 4)
            L:EndCard()
        end

        if dataOn then
        L:Card("What to show on the map")
        L:Desc("Spirit healers, zone-crossing arrows and flight paths are on "
            .. "by default - they are most of the reason to run a map addon "
            .. "at all. If a category is on and you see nothing, /zui maps "
            .. "says whether this client actually has the art for it.")
        Bind(L, "check", "flightPoints", "Flight points, boats and zeppelins",
            "Yours. Boats and zeppelins are coloured markers rather than flight "
            .. "icons - the tooltip says where each one goes.")
        Bind(L, "check", "flightOpposing", "...and the other faction's",
            "Useful for knowing where not to land. Neutral points show either "
            .. "way.")
        Bind(L, "check", "dungeons", "Dungeon and raid entrances",
            "With the level range in the tooltip.")
        Bind(L, "check", "dungeonsContinent", "Dungeon and raid icons on continent maps too",
            "Every zone's dungeon and raid entrances on the continent map; click one to open its zone.")
        Bind(L, "check", "spiritHealers", "Spirit healers")
        Bind(L, "check", "crossings", "Zone crossings",
            "Arrows at the zone borders. Left-click one to jump the map to that "
            .. "zone; right-click anywhere on the map to go up a level.")
        Bind(L, "check", "hideTownIcons", "Hide Blizzard's town and city icons",
            "Only on the continent maps, where they collide with everything "
            .. "above. Recognised by the sprite they draw, which is the only "
            .. "handle Blizzard gives - so if a patch changes that art, this "
            .. "option quietly stops working rather than breaking anything.")
        L:EndCard()
        end

        L:Card("Readouts")
        Bind(L, "check", "coords", "Coordinates",
            "Your position and the cursor's, along the bottom of the map.")
        if dataOn then
        Bind(L, "check", "zoneLevels", "Zone level ranges",
            "Shown in the same strip. Hover a zone on a continent map to read "
            .. "its range without opening it.")
        Bind(L, "check", "fishingLevels", "Fishing skill required",
            "A second number in brackets is the skill for the deep water.")
        end
        L:EndCard()

        if dataOn then
        L:Card("Unexplored areas")
        Bind(L, "check", "reveal", "Draw the parts you have not explored")
        Bind(L, "check", "revealTint", "Tint them",
            "Untinted, unexplored ground is indistinguishable from ground you "
            .. "have actually walked, which quietly turns the map into a lie. "
            .. "The colour and strength are on the Look tab.")
        L:EndCard()
        end

        L:Card("You and your group")
        if dataOn then
        Bind(L, "check", "bigArrow", "Enlarge your own arrow",
            "Blizzard's is 16 pixels, which on a full-screen map is a speck.")
        end
        Bind(L, "check", "classIcons", "Show your group as class-coloured dots",
            "ZacUI draws these itself and pushes Blizzard's own group blips "
            .. "out of the way - otherwise each teammate is drawn twice, in "
            .. "the same place, which reads as a smear rather than a marker.")
        Bind(L, "check", "dotNames", "Names under the dots",
            "Each teammate's name in their class colour.")
        Bind(L, "check", "dotNameDeclutter", "Leave off names that would overlap",
            "A group standing together shows one name instead of a pile of them. "
            .. "Zoom in and the rest appear as they spread apart.")
        L:EndCard()

        if openMap then
            L:Notice("warn", "The seamless world map owns the zoom (one stitched world, wheel from the whole "
                .. "world to street level), so the zoom settings below and the sharper-map tiles stand down "
                .. "while the ZacUI World map part is loaded.")
        end
        L:Card("Zoom and panning")
        Bind(L, "check", "zoomToCursor", "Zoom towards the cursor",
            "Blizzard zooms about the centre, which makes finding a spot a "
            .. "cycle of zoom, pan, zoom, pan.")
        Bind(L, "check", "scrollZones", "Scroll on into zones and back out",
            "One more wheel step past the top zoom level opens the zone under "
            .. "the cursor; one past the bottom level goes back up to the map "
            .. "above, zoomed onto where you were.")
        Bind(L, "check", "extraZoom", "Allow zooming in further")
        Bind(L, "slider", "zoomFactor", "How much further", nil, {
            min = 1, max = 5, step = 0.5,
            format = function(v) return v .. "x" end,
        })
        Bind(L, "check", "rememberZoom", "Remember where you were",
            "Reopening the same map returns to the same place at the same zoom. "
            .. "A different map always opens fresh.")
        Bind(L, "check", "centreOnPlayer", "Keep the map centred on you",
            "Hold shift to look somewhere else without it dragging you back.")
        Bind(L, "check", "followZone", "Follow you between zones",
            "Only when the map is already showing the zone you were in - if you "
            .. "have gone to look at somewhere else, it leaves you there.")
        L:EndCard()

        if dataOn then
        L:Card("Sharper map")
        Bind(L, "check", "hdMap", "Draw zone maps from the game's minimap tiles",
            "Three times the detail of the painted map art, which an addon cannot "
            .. "replace. It is the minimap's picture of the ground - roads, water and "
            .. "buildings as they are - over the whole zone, explored or not.")
        Bind(L, "check", "hdSolid", "  ... with a solid sea under them, no painting through",
            "Off, the painted map shows where there are no tiles and under see-through tiles. "
            .. "The sea colour is in the colour editor under Map.")
        Bind(L, "check", "hdContinents", "  ... on continents too",
            "A whole continent is over a thousand tiles; untick this if opening "
            .. "the continent map stutters on your machine.")
        L:EndCard()
        end
    end

    -- ================================================================
    -- LOOK: opacity, the window, pins, your arrow, the group's dots
    -- ================================================================
    local function Tab_look(L)
        L:Card("Seeing through it")
        Bind(L, "check", "fade", "Fade while you are moving",
            "So the map can stay open while you ride somewhere.", { rebuild = true })
        Bind(L, "slider", "movingAlpha", "Opacity while moving", nil,
            With(Pct(0.5), { min = 10, max = 100, step = 5, enabled = db.fade and true or false }))
        Bind(L, "slider", "stillAlpha", "Opacity while standing still", nil,
            With(Pct(1), { min = 10, max = 100, step = 5 }))
        Bind(L, "check", "noFadeUnderCursor", "Stay solid under the cursor",
            "Hovering the map while running is the one time you are definitely "
            .. "reading it.")
        L:Desc("The preview's Moving button shows the map as it is while you move.")
        L:EndCard()

        L:Card("The window")
        BindColor(L, "windowBg", "Background", nil, { "windowBg", nil, 0.95 })
        BindColor(L, "headerBg", "Header", nil, { "windowBg", nil, 0.82 })
        BindColor(L, "headerRule", "Line under the header", nil, { "accent", nil, 0.5 })
        BindColor(L, "coordBg", "Coordinate strip", nil, { "windowBg", nil, 0.72 })
        L:Desc("Unchanged, each follows the theme on the Colours page. Advanced > Reset puts them back.")
        L:EndCard()

        if dataOn then
        L:Card("Pins")
        Bind(L, "slider", "pinSize", "Icon size", nil,
            { min = 8, max = 28, step = 1, look = true })
        L:Desc("Scales these icons together rather than flattening them to "
            .. "one number - a spirit healer is meant to read smaller than a "
            .. "dungeon portal.")
        local function Scale(key, label)
            Bind(L, "slider", key, label, nil,
                With(Pct(1), { min = 50, max = 200, step = 5, look = true }))
        end
        Scale("pinScaleFlight", "Flight points, boats and zeppelins")
        Scale("pinScaleDungeons", "Dungeons and raids")
        Scale("pinScaleSpirit", "Spirit healers")
        Scale("pinScaleCrossing", "Zone crossings")
        L:Desc("Each group on top of the icon size, for when one kind wants to stand out.")
        Bind(L, "check", "pinHalo", "Outline each icon",
            "Each one is drawn a second time behind itself, so it keeps its own "
            .. "shape and still stands out on busy terrain.", { look = true, rebuild = true })
        local haloOn = db.pinHalo ~= false
        BindColor(L, "pinHaloColor", "Outline colour", nil, { fixed = { 0, 0, 0, 0.7 } },
            { enabled = haloOn })
        Bind(L, "slider", "pinHaloSize", "Outline size", nil, {
            min = 100, max = 200, step = 2, look = true, enabled = haloOn,
            get = function(v) return math.floor((v or 1.34) * 100 + 0.5) end,
            set = function(v) return v / 100 end,
            format = function(v) return v .. "%" end,
        })
        L:EndCard()

        L:Card("Your arrow")
        Bind(L, "slider", "arrowSize", "Arrow size", nil,
            { min = 16, max = 64, step = 1, enabled = db.bigArrow and true or false })
        L:Desc("Used when \"Enlarge your own arrow\" is on (General).")
        L:EndCard()
        end

        L:Card("Group dots")
        Bind(L, "slider", "classIconSize", "Dot size", nil,
            { min = 6, max = 30, step = 1, look = true })
        L:Desc("Small on purpose - a party standing together at 24 is one blob.")
        ModeDropdown(L, "dotColorMode", "Dot colour", "One colour", true)
        BindColor(L, "dotColor", "The one colour", nil, { "accent" },
            { alpha = false, enabled = db.dotColorMode == "custom" })
        Bind(L, "check", "dotRound", "Round",
            "Cut from a mask rather than drawn from art, because there is no "
            .. "filled-circle texture that can be relied on across builds. If "
            .. "your client has no mask support the dots stay square and "
            .. "/zui maps says so.", { look = true })
        Bind(L, "check", "dotBorder", "Outline",
            "Keeps a dot readable over pale terrain and snow.", { look = true, rebuild = true })
        local borderOn = db.dotBorder ~= false
        BindColor(L, "dotBorderColor", "Outline colour", nil, { fixed = { 0, 0, 0, 1 } },
            { enabled = borderOn })
        Bind(L, "slider", "dotBorderSize", "Outline width", nil, {
            min = 1, max = 3, step = 1, look = true, enabled = borderOn,
            format = function(v) return v .. " px" end })
        Bind(L, "slider", "dotAlpha", "Dot opacity", nil,
            With(Pct(1), { min = 20, max = 100, step = 5, look = true }))
        L:EndCard()

        if dataOn then
        L:Card("Unexplored areas")
        local swatchRow = UI.Holder(L.current)
        swatchRow:SetSize(300, 22)
        local label = UI.Font(swatchRow, F.SMALL,
            { text = "Tint colour", cat = "text", key = "text" })
        label:SetPoint("LEFT")
        -- An ordinary palette swatch, because the tint IS an ordinary palette
        -- colour (map/reveal). It repaints the textures already on screen, so
        -- the map recolours while you are looking at it.
        local sw = UI.Swatch(swatchRow, "map", "reveal", function()
            if ns.MapsReveal then ns.MapsReveal.Repaint() end
        end)
        -- (clear of its label at any type size)
        sw:SetPoint("LEFT", math.max(100, math.ceil(label:GetStringWidth() or 0) + 10), 0)
        L:Row(swatchRow, 26)
        L:Desc("Also on the Colours page, and it travels with your profile.")
        Bind(L, "slider", "tintAlpha", "Tint strength", nil, With(Pct(1), {
            min = 20, max = 100, step = 5,
            onChange = function() if ns.MapsReveal then ns.MapsReveal.Repaint() end end,
        }))
        L:EndCard()

        L:Card("Sharper map")
        Bind(L, "slider", "hdAlpha", "Tile opacity", nil,
            With(Pct(1), { min = 20, max = 100, step = 5 }))
        L:Desc("Below 100% the painted map shows through, which keeps its zone "
            .. "names and borders readable.")
        L:EndCard()
        end
    end

    -- ================================================================
    -- TEXT: the zone name, the coordinate strip, the names under dots
    -- ================================================================
    local function Tab_text(L)
        L:Card("Zone name")
        BindFont(L, "titleFont", "Font", nil, UI.F.NORMAL, "Durotar")
        BindColor(L, "titleColor", "Colour", nil, { "text", "gold" }, { alpha = false })
        L:EndCard()

        L:Card("Coordinates")
        BindFont(L, "coordFont", "Font", "One font for the whole strip: your position, the zone's levels and the cursor's.",
            UI.F.SMALL, "Player  52.4, 38.1")
        BindColor(L, "coordPlayerColor", "Your position", nil, { "text", "gold" }, { alpha = false })
        BindColor(L, "coordZoneColor", "Zone level range", nil, { "text", "text" }, { alpha = false })
        BindColor(L, "coordCursorColor", "Cursor position", nil, { "text", "gray" }, { alpha = false })
        Bind(L, "slider", "coordDecimals", "Decimal places", nil, {
            min = 0, max = 2, step = 1, look = true,
            format = function(v) return v == 0 and "52, 38" or (v == 1 and "52.4, 38.1" or "52.43, 38.12") end })
        Bind(L, "check", "coordLabels", "Say which is which",
            "\"Player\" and \"Cursor\" in front of the numbers.", { look = true })
        -- the whole line as a template, and where each text sits on the
        -- strip (maps.formats.coords / maps.anchors.<key>; nothing saved =
        -- the settings above and the spots they always had)
        local Fr = ns.MapsFrame
        if Fr and Fr.STRIP_TARGETS then
            local function Others(key)
                local out = {}
                for _, e in ipairs(Fr.STRIP_TARGETS) do if e.value ~= key then out[#out + 1] = e end end
                return out
            end
            local function Spot(key, label, extra)
                local ag, as = ns.CustomAccess(Maps.DB, "anchors", key)
                local o = { key = "maps." .. key, label = label, anchorGet = ag, anchorSet = as, targets = Others(key),
                    defaultTargetLabel = "Where it sits now", anchorMin = -200, anchorMax = 200,
                    anchorDefaults = function() return Fr.StripDefaults(key) end }
                if extra then for k, v in pairs(extra) do o[k] = v end end
                return UI.TextElement(L, o)
            end
            local fg, fs = ns.CustomAccess(Maps.DB, "formats", "coords")
            Spot("player", "Your position", { formatGet = fg, formatSet = fs, formatKinds = { percent = true },
                formatDefaults = function() return Fr.CoordDefaults() end,
                formatTokens = { { token = "label", label = "Player / Cursor" }, { token = "x", label = "across" },
                    { token = "y", label = "down" } },
                formatSample = function() return Fr.CoordText("Player", 0.524, 0.381) end })
            Spot("cursor", "Cursor position")
            Spot("zone", "Zone level range")
        end
        L:EndCard()

        L:Card("Names under the group dots")
        local nameOn = db.dotNames ~= false
        local nf = UI.FontPicker(L.current, { label = "Font", width = 400,
            -- the size stays in dotNameSize, where it always was
            get = function()
                local s = {}
                for k, v in pairs(type(db.dotNameFont) == "table" and db.dotNameFont or {}) do s[k] = v end
                s.size = db.dotNameSize
                return s
            end,
            set = function(spec)
                db.dotNameSize = tonumber(spec.size) or db.dotNameSize
                spec.size = nil
                db.dotNameFont = spec
                LookSoon()
            end,
            defaults = { size = 9, outline = "outline", shadow = false },
            minSize = 6, maxSize = 20, sample = "Zaccw  Lumi" })
        L:Add(nf, 8)
        UI.SetEnabled(nf, nameOn, 'Needs "Names under the dots" turned on.')
        ModeDropdown(L, "dotNameColorMode", "Colour", "One colour", true)
        BindColor(L, "dotNameColor", "The one colour", nil, { "text", "normal" },
            { alpha = false, enabled = nameOn and db.dotNameColorMode == "custom" })
        if not nameOn then L:Desc("Names are off (General > You and your group).") end
        L:EndCard()
    end

    -- ================================================================
    -- ANIMATION: opening, the fade, the dip over a zone change, the glide
    -- ================================================================
    local function Tab_anim(L)
        L:Card("When the map opens")
        local ap = UI.AnimationPicker(L.current, {
            styles = { "none", "fade", "slide", "pop" },
            get = function() return db.openAnim end,
            set = function(spec) db.openAnim = spec end,
        })
        L:Add(ap, 6)
        L:Desc("None is the map simply appearing, as it always has. Replay in the preview plays it. "
            .. "Closing is always instant: Escape closes the map straight away.")
        L:EndCard()

        L:Card("Fading while you move")
        Bind(L, "slider", "fadeSpeed", "Fade time", nil, {
            min = 0.1, max = 3, step = 0.1, enabled = db.fade and true or false,
            get = function(v) return math.floor(FadeSecs(v) * 10 + 0.5) / 10 end,
            set = function(v) return math.floor(FadeFrac(v) * 1000 + 0.5) / 1000 end,
            format = function(v) return string.format("%.1fs", v) end,
        })
        L:Desc("How long the map takes to reach its new opacity when you start or stop moving. "
            .. "The preview's Moving button, then Replay, plays it.")
        L:EndCard()

        L:Card("A change of map")
        Bind(L, "check", "scrollFade", "Fade the new map in",
            "A short dip to dark and back over the change, so the map does not snap. "
            .. "The preview's Zone change button plays it.", { rebuild = true })
        local dipOn = db.scrollFade ~= false
        Bind(L, "slider", "scrollFadeTime", "Length", nil, {
            min = 0.05, max = 1, step = 0.05, look = true, enabled = dipOn,
            format = function(v) return string.format("%.2fs", v) end })
        Bind(L, "slider", "scrollFadeDepth", "Dips to", nil,
            With(Pct(0.3), { min = 0, max = 90, step = 5, look = true, enabled = dipOn }))
        L:Desc("Lower is darker.")
        L:EndCard()

        L:Card("The wheel's zoom")
        Bind(L, "check", "smoothZoom", "Ease the wheel's zoom",
            "Each wheel step glides to the next level instead of snapping.", { rebuild = true })
        Bind(L, "slider", "smoothZoomTime", "Glide time", nil, {
            min = 0.05, max = 0.6, step = 0.05, look = true,
            enabled = db.smoothZoom ~= false,
            format = function(v) return string.format("%.2fs", v) end })
        L:Desc("A wheel step into a new zone glides a little longer.")
        L:EndCard()
        if ns.Motion and not ns.Motion.Enabled() then
            L:Notice("warn", "Animations are off (Appearance > Motion), so all of these are instant.")
        end
    end

    -- ================================================================
    -- POSITION: moving and sizing the window
    -- ================================================================
    local function Tab_pos(L)
        L:Card("The window")
        if openMap then
            L:Desc("|cff999999The seamless map's own window is in charge while it is loaded: "
                .. "drag its title bar and pull its corners instead. These apply when "
                .. "the ZacUI World map part is switched off.|r")
        end
        Bind(L, "check", "unlock", "Unlocked",
            "Drag the header to move the map, and the grip in the bottom right "
            .. "corner to size it. The map frame itself never takes the mouse, "
            .. "so clicks always reach the map underneath.")

        Bind(L, "slider", "scale", "Size", nil, {
            min = 35, max = 160, step = 5,
            get = function(v) return math.floor((v or 0.9) * 100 + 0.5) end,
            set = function(v) return v / 100 end,
            format = function(v) return v .. "%" end,
        })
        L:Desc("Scales the whole window, the way ElvUI does. The grip in the "
            .. "bottom right corner does the same thing by hand.")

        local row = UI.Holder(L.current)
        row:SetSize(300, M.BUTTON_H)
        local reset = UI.Button(row, "Reset position", { width = 110,
            tooltip = "Puts the map back in the middle of the screen at its "
                .. "default size.",
            onClick = function()
                db.point, db.x, db.y = nil, nil, nil
                db.scale = 0.9
                if Maps.Refresh then Maps.Refresh() end
                RefreshConfig()
                Print("map reset.")
            end })
        reset:SetPoint("LEFT")
        L:Row(row, M.BUTTON_H + 4)
        L:EndCard()
    end

    -- ================================================================
    -- BATTLEGROUND: the small map in a battleground
    -- ================================================================
    local function Tab_bg(L)
        L:Card("Battleground map")
        Bind(L, "check", "battlefield", "Take over the battleground map",
            "The small map that appears in a battleground. Blizzard's tab for it "
            .. "is hidden, since a movable map does not need one.")
        Bind(L, "check", "bfUnlock", "Unlocked",
            "Drag just outside its edge to move it; the corner grip sizes it.")
        Bind(L, "slider", "bfSize", "Width", nil,
            { min = 180, max = 1100, step = 10,
              format = function(v) return v .. "px" end })
        Bind(L, "slider", "bfAlpha", "Opacity", nil,
            With(Pct(1), { min = 20, max = 100, step = 5 }))
        Bind(L, "slider", "bfZoom", "Allow zooming in further", nil,
            { min = 1, max = 4, step = 0.5,
              format = function(v) return v .. "x" end })
        Bind(L, "check", "bfCentre", "Keep it centred on you",
            "Hold shift to pan away.")
        Bind(L, "slider", "bfArrowSize", "Your arrow", nil,
            { min = 16, max = 60, step = 1 })
        Bind(L, "slider", "bfIconSize", "Group icons", nil,
            { min = 10, max = 40, step = 1 })
        L:Desc("The preview's Battleground button shows it.")
        L:EndCard()
    end

    -- ============================================================
    -- THE SEAMLESS MAP'S OWN SETTINGS, DRAWN HERE (2026-10-31, Zac: "i
    -- want a full restyle ... i want it all mine"). The engine inside
    -- Zacui_WorldMap describes its settings as an AceConfig table
    -- (mod:Options()); ZacUI's own renderer draws that with ZacUI's
    -- widgets, the same one the aura editor uses, so every toggle, slider
    -- and list is a ZacUI control on a ZacUI card and the engine's own
    -- menu never has to open. The actions the engine's menu offered
    -- (find me, pins, the quill, report) are buttons at the top.
    local function Tab_worldmap(L)
        local OM = _G.ZacuiWorldMap
        local mod = OM and OM.GetModule and OM:GetModule("worldmap")
        if not mod then
            L:Notice("missing", "The ZacUI World map part is not loaded (the AddOns list, Zacui_WorldMap).")
            return
        end
        local function OnMap(fn)
            return function()
                if _G.WorldMapFrame and not _G.WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
                C_Timer.After(0, function() pcall(fn) end)
            end
        end
        L:Card("On the map")
        local acts = {
            { "Find me", "Glide the map to where you stand.", function() mod:FindMe() end },
            { "Drop a pin", "Then click the map to place a pin, with a note if you like. Ctrl-click the map does it any time.",
                function() if mod.SetPinMode then mod.SetPinMode(true) end end },
            { "Pins", "Every map pin: go to one, share them, import a code.", function() mod:TogglePins() end },
            { "Draw", "Ink on the map: lines, arrows, rings and raid marks, kept for you.",
                function() if mod.ToggleSketch then mod:ToggleSketch() end end },
            { "Report a spot", "Draw on the map where something looks wrong and copy the report.",
                function() mod:ToggleReport() end },
            { "Credits", "Who made the map engine.", function() mod:ToggleNews() end },
        }
        local row = UI.Holder(L.current)
        row:SetSize(560, M.BUTTON_H * 2 + 6)
        local x, y, n = 0, 0, 0
        for _, a in ipairs(acts) do
            local b = UI.Button(row, a[1], { width = 104, tooltip = a[2], onClick = OnMap(a[3]) })
            b:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
            n = n + 1
            if n % 5 == 0 then x, y = 0, y - M.BUTTON_H - 6 else x = x + 110 end
        end
        L:Row(row, M.BUTTON_H * 2 + 10)
        L:EndCard()

        -- the engine's options, through ZacUI's AceConfig renderer; the
        -- stack it draws on is this page's cards: a header opens a card
        local cardW = 440
        local S = {}
        local function Open(title)
            if L.current then L:EndCard() end
            L:Card(title)
            S.p = L.current
        end
        function S:Add(widget, h) L:Row(widget, h) return widget end
        function S:Label(text) return L:Desc(text) end
        function S:Section(text) Open(text) end
        function S:Gap(h) if L.current then L.current._y = L.current._y - (h or 8) end end
        Open("Seamless map")
        local ok, opts = pcall(mod.Options, mod)
        if ok and type(opts) == "table" then
            opts.enabled = { type = "toggle", name = "The seamless map", order = 0, width = "full",
                desc = "Off: Blizzard's own map comes back after a /reload.",
                get = function() return mod.db.enabled end,
                set = function(_, v)
                    mod.db.enabled = v
                    ns.AskReload("The seamless map is " .. (v and "on" or "off") .. " after a reload.")
                end }
            if ns.RenderAceOptions then
                local stats = ns.RenderAceOptions(S, { type = "group", args = opts }, cardW, RefreshConfig)
                if stats.skipped > 0 then L:Desc(stats.skipped .. " setting(s) this page cannot draw yet.") end
            end
        else
            L:Desc("Could not read the map engine's settings: " .. tostring(opts))
        end
        if L.current then L:EndCard() end
    end

    -- ================================================================
    -- ADVANCED: diagnosing, and putting the look back
    -- ================================================================
    local function Tab_adv(L)
        L:Card("When something looks wrong")
        local diagRow = UI.Holder(L.current)
        diagRow:SetSize(300, M.BUTTON_H)
        local diag = UI.Button(diagRow, "Diagnose", { width = 90,
            tooltip = "Prints what loaded, what did not, and how much reveal "
                .. "data exists for the zone you are looking at.",
            onClick = function() if Maps.Diagnose then Maps.Diagnose() end end })
        diag:SetPoint("LEFT")
        L:Row(diagRow, M.BUTTON_H + 4)
        L:Desc("The same as /zui maps: what loaded, what did not, and why a category of pins shows nothing.")
        L:EndCard()

        L:Card("Reset")
        local resetRow = UI.Holder(L.current)
        resetRow:SetSize(300, M.BUTTON_H)
        local rl = UI.Button(resetRow, "Reset the look", { width = 120,
            tooltip = "Every colour, font, pin and dot detail and timing on this page back to how ZacUI ships it. "
                .. "What shows, where the map sits and the battleground map are left alone.",
            onClick = function()
                for k, v in pairs(LOOK_VALUES) do db[k] = v end
                for _, k in ipairs(LOOK_UNSET) do db[k] = nil end
                db.openAnim = { style = "none", duration = 0.25, delay = 0, easing = "easeOutQuad",
                                dir = "up", distance = 20 }
                db.dotNameSize, db.classIconSize, db.pinSize, db.arrowSize = 9, 10, 14, 18
                db.dotRound, db.dotBorder, db.dotAlpha = true, true, 1
                LookSoon()
                if Maps.Refresh then Maps.Refresh() end
                if ns.SettingsChanged then ns.SettingsChanged("reset") end
                RefreshConfig()
                Print("map look reset.")
            end })
        rl:SetPoint("LEFT")
        L:Row(resetRow, M.BUTTON_H + 4)
        L:Desc("Colours go back to following the theme, fonts to ZacUI's font.")
        L:EndCard()
    end

    local tabs = {
        { id = "general", label = "General", build = Tab_general },
        { id = "look", label = "Look", build = Tab_look },
        { id = "text", label = "Text", build = Tab_text },
        { id = "anim", label = "Animation", build = Tab_anim },
        { id = "pos", label = "Position", build = Tab_pos },
        { id = "bg", label = "Battleground", build = Tab_bg },
    }
    if _G.ZacuiWorldMap then
        tabs[#tabs + 1] = { id = "worldmap", label = "World map", build = Tab_worldmap }
    end
    tabs[#tabs + 1] = { id = "adv", label = "Advanced", build = Tab_adv }
    L:Tabs(tabs)
end)
