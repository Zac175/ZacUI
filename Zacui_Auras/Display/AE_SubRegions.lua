-- AE_SubRegions - what hangs off a region: its texts, border, glow, tick
-- marks, extra textures (plain, linear fill, circular fill), models and
-- flip books.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- A display's subRegions list, in order: subtext, subborder, subglow,
-- subtick, subtexture, sublineartexture, subcirculartexture, submodel,
-- substopmotion, and the two markers subbackground / subforeground (they
-- only say which layer the others sit above). Conditions address them as
-- "sub.<index>.<property>"; what each kind lets a condition change is
-- S.properties.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local S = {}
E.SubRegions = S
local R = E.Regions
local Color = E.Color
local floor = math.floor

-- ============================================================
-- WHICH KINDS GO ON WHICH REGION TYPES, WHAT CONDITIONS CHANGE
-- ============================================================
local ALL = { icon = true, aurabar = true, text = true, texture = true, progresstexture = true, empty = true }
local FRAMED = { icon = true, aurabar = true, texture = true, progresstexture = true, empty = true }
S.supports = {
    subbackground = { icon = true, aurabar = true, text = true, texture = true, progresstexture = true, empty = true,
        model = true, stopmotion = true },
    subforeground = { aurabar = true },
    subtext = FRAMED, subborder = FRAMED, subglow = FRAMED,
    subtick = { aurabar = true },
    subtexture = ALL, sublineartexture = ALL, subcirculartexture = ALL, submodel = ALL, substopmotion = ALL,
}

S.properties = {
    subtext = { text_visible = "bool", text_color = "color", text_text = "string", text_fontSize = "number",
        text_anchorXOffset = "number", text_anchorYOffset = "number" },
    subborder = { border_color = "color", border_visible = "bool" },
    subglow = { glow = "bool", glowType = "list", useGlowColor = "bool", glowColor = "color", glowLines = "number",
        glowFrequency = "number", glowLength = "number", glowThickness = "number", glowScale = "number",
        glowBorder = "bool", glowXOffset = "number", glowYOffset = "number", glowDuration = "number",
        glowStartAnim = "bool" },
    subtick = { tick_visible = "bool", tick_color = "color", tick_placement_mode = "list", automatic_length = "bool",
        tick_length = "number", tick_thickness = "number", tick_use_texture = "bool", tick_texture = "texture",
        tick_desaturate = "bool", tick_rotation = "number", tick_mirror = "bool" },
    subtexture = { textureColor = "color", textureDesaturate = "bool", textureMirror = "bool",
        textureRotation = "number", textureVisible = "bool" },
    sublineartexture = { linearTextureColor = "color", linearTextureDesaturate = "bool", linearTextureMirror = "bool",
        linearTextureVisible = "bool", linearTextureInverse = "bool", linearTextureAuraRotation = "number",
        linearTextureCrop_x = "number", linearTextureCrop_y = "number" },
    subcirculartexture = { circularTextureColor = "color", circularTextureDesaturate = "bool",
        circularTextureMirror = "bool", circularTextureVisible = "bool", circularTextureInverse = "bool",
        circularTextureClockwise = "bool", circularTextureAuraRotation = "number", circularTextureCrop_x = "number",
        circularTextureCrop_y = "number" },
    submodel = { model_alpha = "number", model_visible = "bool" },
    substopmotion = { stopmotionColor = "color", stopmotionDesaturate = "bool", stopmotionVisible = "bool" },
}

-- the properties of one sub-element as conditions see them (a tick has
-- one per placement)
function S.PropertiesOf(s)
    local base = S.properties[s and s.type]
    if not base then return nil end
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    if s.type == "subtick" then
        for i in ipairs(type(s.tick_placements) == "table" and s.tick_placements or { 50 }) do
            out["tick_placements." .. i] = "number"
        end
    end
    return out
end

-- ============================================================
-- ANCHORING (the way the format hangs a sub-element on each type)
-- ============================================================
local POINTS = { CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true, TOPLEFT = true,
    TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
local OPPOSITE = { CENTER = "CENTER", TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT",
    TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT", BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT" }
S.OPPOSITE = OPPOSITE

-- an icon's inner (80%) and outer (110%) boxes texts sit in
local function IconBox(f, which)
    local key = which == "inner" and "innerBox" or "outerBox"
    local box = f[key]
    if not box then
        box = CreateFrame("Frame", nil, f)
        f[key] = box
    end
    local w = (f.width or f:GetWidth() or 1) * math.abs(f.scalex or 1)
    local h = (f.height or f:GetHeight() or 1) * math.abs(f.scaley or 1)
    local k = which == "inner" and -0.1 or 0.05
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", f, "TOPLEFT", -k * w, k * h)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", k * w, -k * h)
    return box
end

-- the frame an "area" hangs over
local function AreaFrame(f, area)
    if f.regionType == "aurabar" then
        if area == "icon" then return f.icon end
        if area == "fg" then return f.fg end
        if area == "bg" then return f.bg end
        return f
    end
    if f.regionType == "icon" then return f.icon end
    return f
end
S.AreaFrame = AreaFrame

local function FillArea(obj, f, area, x, y)
    local target = AreaFrame(f, area)
    x, y = tonumber(x) or 0, tonumber(y) or 0
    obj:ClearAllPoints()
    obj:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -x, -y)
    obj:SetPoint("TOPRIGHT", target, "TOPRIGHT", x, y)
end

-- one point of the region (with the icon / inner / outer / spark extras)
local function AtPoint(obj, f, anchor, selfPoint, x, y)
    anchor = anchor or "CENTER"
    x, y = tonumber(x) or 0, tonumber(y) or 0
    local target = f
    local rt = f.regionType
    if rt == "icon" then
        target = f.icon
        if anchor:sub(1, 6) == "INNER_" then
            target, anchor = IconBox(f, "inner"), anchor:sub(7)
        elseif anchor:sub(1, 6) == "OUTER_" then
            target, anchor = IconBox(f, "outer"), anchor:sub(7)
        end
    elseif rt == "aurabar" then
        target = f.bar
        if anchor:sub(1, 5) == "ICON_" then
            target, anchor = f.icon, anchor:sub(6)
        elseif anchor:sub(1, 6) == "INNER_" then
            anchor = anchor:sub(7)
            if anchor:find("LEFT", 1, true) then x = x + 2 elseif anchor:find("RIGHT", 1, true) then x = x - 2 end
            if anchor:find("TOP", 1, true) then y = y - 2 elseif anchor:find("BOTTOM", 1, true) then y = y + 2 end
        elseif anchor == "SPARK" then
            target, anchor = f.spark, "CENTER"
        end
    end
    if not POINTS[anchor] then anchor = "CENTER" end
    if not POINTS[selfPoint] then selfPoint = "CENTER" end
    obj:ClearAllPoints()
    obj:SetPoint(selfPoint, target, anchor, x, y)
end

-- a sub-element with an anchor_mode ("area" fills, "point" attaches)
local function PlaceBox(obj, f, s)
    if s.anchor_mode == "point" then
        obj:SetSize(tonumber(s.width) or 32, tonumber(s.height) or 32)
        AtPoint(obj, f, s.anchor_point, s.self_point or "CENTER", s.xOffset, s.yOffset)
    else
        FillArea(obj, f, s.anchor_area, 0, 0)
    end
end

-- how full a sub-element's own progress is (progressSource {-2} is
-- the region's own)
local function SubFill(f, src, inverse, now)
    local p
    if type(src) ~= "table" or tonumber(src[1]) == -2 or src[1] == nil then
        p = R.Fill(f, f.state, now)
    else
        local tmp = { progressSource = src, ctx = f.ctx, d = f.d, inverse = false }
        p = R.Fill(tmp, f.state, now)
    end
    if inverse then p = 1 - p end
    return p
end

-- ============================================================
-- TEXT
-- ============================================================
local function TextSelfPoint(f, s)
    local sp = s.text_selfPoint
    if sp and sp ~= "AUTO" then return sp end
    local ap = s.anchor_point or "CENTER"
    if f.regionType == "icon" then
        if ap:sub(1, 6) == "INNER_" then return ap:sub(7) end
        if ap:sub(1, 6) == "OUTER_" then return OPPOSITE[ap:sub(7)] or "CENTER" end
        return "CENTER"
    elseif f.regionType == "aurabar" then
        if ap:sub(1, 5) == "ICON_" then ap = ap:sub(6) elseif ap:sub(1, 6) == "INNER_" then ap = ap:sub(7) end
        return POINTS[ap] and ap or "CENTER"
    end
    return OPPOSITE[ap] or "CENTER"
end

local function PlaceText(f, o)
    local s = o.s
    local x = tonumber(o.offX) or tonumber(s.text_anchorXOffset) or tonumber(s.anchorXOffset) or 0
    local y = tonumber(o.offY) or tonumber(s.text_anchorYOffset) or tonumber(s.anchorYOffset) or 0
    AtPoint(o.fs, f, s.anchor_point, TextSelfPoint(f, s), x, y)
end

local function TextLayer(f)
    local holder = f.textLayer
    if not holder then
        holder = CreateFrame("Frame", nil, f)
        holder:SetAllPoints(f)
        holder:SetFrameLevel(f:GetFrameLevel() + 6)
        f.textLayer = holder
    end
    return holder
end

local function StyleText(o)
    local s, fs = o.s, o.fs
    R.SetFont(fs, s.text_font, o.fontSize or s.text_fontSize, s.text_fontType)
    local c = o.color or s.text_color
    fs:SetTextColor(Color(c))
    fs:SetJustifyH(s.text_justify or "CENTER")
    fs:SetShadowColor(Color(s.text_shadowColor, 0, 0, 0, 1))
    fs:SetShadowOffset(tonumber(s.text_shadowXOffset) or 0, tonumber(s.text_shadowYOffset) or 0)
    if s.text_automaticWidth == "Fixed" then
        fs:SetWidth(tonumber(s.text_fixedWidth) or 64)
        fs:SetWordWrap(s.text_wordWrap ~= "Elide")
    else
        fs:SetWidth(0)
    end
    local deg = s.rotateText == "LEFT" and 90 or (s.rotateText == "RIGHT" and -90 or 0)
    if fs.SetRotation then pcall(fs.SetRotation, fs, math.rad(deg)) end
end

local function MakeText(f, s)
    local fs = TextLayer(f):CreateFontString(nil, "OVERLAY")
    local o = { kind = "text", s = s, fs = fs, timed = E.Text.IsTimed(s.text_text) }
    o.visible = s.text_visible ~= false
    o.text = s.text_text
    StyleText(o)
    PlaceText(f, o)
    fs:SetShown(o.visible)
    return o
end

local function TextOf(f, o)
    return E.Text.Format(o.text or "", o.s, "text_text", f.ctx or { state = f.state })
end

-- ============================================================
-- BORDER
-- ============================================================
local function MakeBorder(f, s)
    local b = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    local off = tonumber(s.border_offset) or 0
    FillArea(b, f, f.regionType == "aurabar" and s.anchor_area or nil, off, off)
    b:SetFrameLevel(f:GetFrameLevel() + 4)
    if b.SetBackdrop then
        local edge = R.Border(s.border_edge or "Square Full White")
        b:SetBackdrop({ edgeFile = edge, edgeSize = math.max(1, tonumber(s.border_size) or 2) })
        b:SetBackdropBorderColor(Color(s.border_color, 1, 1, 1, 1))
    end
    b:SetShown(s.border_visible ~= false)
    return { kind = "border", s = s, frame = b }
end

-- ============================================================
-- GLOW
-- ============================================================
local function GlowOpts(o)
    local s = o.s
    return { type = s.glowType, color = s.useGlowColor and s.glowColor or nil, lines = s.glowLines,
        frequency = s.glowFrequency, length = s.glowLength, thickness = s.glowThickness,
        xOffset = s.glowXOffset, yOffset = s.glowYOffset, scale = s.glowScale, border = s.glowBorder,
        duration = s.glowDuration, startAnim = s.glowStartAnim }
end

local function GlowArea(f, s)
    if f.regionType == "aurabar" then return AreaFrame(f, s.anchor_area) end
    if s.glowType == "buttonOverlay" then return f end
    return AreaFrame(f, nil)
end

local function MakeGlow(f, s, index)
    return { kind = "glow", s = s, index = index, area = GlowArea(f, s), on = s.glow and true or false }
end

-- ============================================================
-- TICK MARKS (on bars)
-- ============================================================
local SIDE = { HORIZONTAL = "LEFT", HORIZONTAL_INVERSE = "RIGHT", VERTICAL = "TOP", VERTICAL_INVERSE = "BOTTOM" }
local SIDE_INV = { HORIZONTAL = "RIGHT", HORIZONTAL_INVERSE = "LEFT", VERTICAL = "BOTTOM", VERTICAL_INVERSE = "TOP" }

local function StyleTick(o, t)
    local s = o.s
    local c = o.color or s.tick_color or { 1, 1, 1, 1 }
    if o.useTexture then
        R.SetTexture(t, o.texture or s.tick_texture)
        t:SetBlendMode(s.tick_blend_mode or "ADD")
        t:SetDesaturated(o.desaturate and true or false)
        t:SetTexCoord(R.TurnedCoords(o.rotation or 0, false, o.mirror, false))
        t:SetVertexColor(Color(c))
    else
        if t.SetColorTexture then t:SetColorTexture(Color(c)) else t:SetTexture("Interface\\Buttons\\WHITE8x8") end
        t:SetVertexColor(Color(c))
    end
end

local function MakeTick(f, s)
    local o = { kind = "tick", s = s, tex = {} }
    o.list = {}
    for i, v in ipairs(type(s.tick_placements) == "table" and s.tick_placements or { s.tick_placement or 50 }) do
        o.list[i] = tonumber(v)
    end
    o.mode = s.tick_placement_mode or "AtValue"
    o.visible = s.tick_visible ~= false
    o.useTexture = s.use_texture and true or false
    o.desaturate, o.rotation, o.mirror = s.tick_desaturate, tonumber(s.tick_rotation) or 0, s.tick_mirror
    o.thickness, o.length, o.auto = tonumber(s.tick_thickness) or 2, tonumber(s.tick_length) or 30, s.automatic_length ~= false
    for i = 1, #o.list do
        local t = f.bar:CreateTexture(nil, "OVERLAY")
        StyleTick(o, t)
        o.tex[i] = t
    end
    return o
end

local function PlaceTicks(f, o)
    local s = o.s
    local now = GetTime()
    local src = R.SourceState(f, f.state)
    local maxV
    if src then
        if src.progressType == "timed" then maxV = tonumber(src.duration) or 0 else maxV = tonumber(src.total) or 0 end
    else
        maxV = 0
    end
    local minV, hiV = R.Bounds(f.d, maxV)
    local range = hiV - minV
    local o2 = f.orientation or "HORIZONTAL"
    local vertical = o2 == "VERTICAL" or o2 == "VERTICAL_INVERSE"
    local inverse = (f.inverse and true or false) ~= (src and src.inverse and true or false)
    local major = vertical and (f.barH or 0) or (f.barW or 0)
    local minor = vertical and (f.barW or 0) or (f.barH or 0)
    for i, t in ipairs(o.tex) do
        local v = o.list[i]
        local at
        if v then
            if o.mode == "AtValue" then at = v
            elseif o.mode == "AtMissingValue" then at = hiV - v
            elseif o.mode == "AtPercent" then if v >= 0 and v <= 100 then at = minV + v * range / 100 end
            elseif o.mode == "ValueOffset" and src and hiV ~= 0 then
                if src.progressType == "timed" then
                    if src.paused then at = (tonumber(src.remaining) or 0) + v
                    elseif src.expirationTime then at = src.expirationTime - now + v end
                elseif src.value then
                    at = (tonumber(src.value) or 0) + v
                end
            end
        end
        local pct = range ~= 0 and at and (at - minV) / range
        local has = pct and pct >= 0 and pct <= 1
        local off = has and pct * major or 0
        if o2 == "HORIZONTAL_INVERSE" or o2 == "VERTICAL" then off = -off end
        if inverse then off = -off end
        local th = o.thickness
        local len = o.auto and minor or o.length
        if vertical then t:SetSize(len, th) else t:SetSize(th, len) end
        local side = (inverse and SIDE_INV or SIDE)[o2] or "LEFT"
        t:ClearAllPoints()
        t:SetPoint("CENTER", f.bar, side, (vertical and 0 or off) + (tonumber(s.tick_xOffset) or 0),
            (vertical and off or 0) + (tonumber(s.tick_yOffset) or 0))
        t:SetShown(o.visible and has and true or false)
    end
    o.running = o.mode == "ValueOffset" and src and src.progressType == "timed" and not src.paused
end

-- ============================================================
-- EXTRA TEXTURE
-- ============================================================
local function StyleTexture(o)
    local s, t = o.s, o.tex
    t:SetVertexColor(Color(o.color or s.textureColor))
    t:SetDesaturated(o.desaturate and true or false)
    t:SetTexCoord(R.TurnedCoords(o.rotation or 0, s.textureRotate and true or false, o.mirror, false))
end

local function MakeTexture(f, s)
    local t = f:CreateTexture(nil, "OVERLAY")
    local o = { kind = "texture", s = s, tex = t }
    R.SetTexture(t, s.textureTexture)
    t:SetBlendMode(s.textureBlendMode or "BLEND")
    o.desaturate, o.mirror, o.rotation = s.textureDesaturate, s.textureMirror, tonumber(s.textureRotation) or 0
    StyleTexture(o)
    PlaceBox(t, f, s)
    t:SetShown(s.textureVisible ~= false)
    return o
end

-- ============================================================
-- LINEAR / CIRCULAR FILL TEXTURES
-- ============================================================
local function MakeLinear(f, s)
    local holder = CreateFrame("Frame", nil, f)
    PlaceBox(holder, f, s)
    holder:SetFrameLevel(f:GetFrameLevel() + 3)
    local t = holder:CreateTexture(nil, "ARTWORK")
    R.SetTexture(t, s.linearTextureTexture)
    t:SetBlendMode(s.linearTextureBlendMode or "BLEND")
    local o = { kind = "linear", s = s, frame = holder, tex = t, visible = s.linearTextureVisible ~= false,
        inverse = s.linearTextureInverse, mirror = s.linearTextureMirror, color = s.linearTextureColor,
        orientation = s.linearTextureOrientation or "HORIZONTAL" }
    t:SetDesaturated(s.linearTextureDesaturate and true or false)
    t:SetVertexColor(Color(o.color))
    holder:SetShown(o.visible)
    return o
end

local function DrawLinear(f, o, now)
    local p = SubFill(f, o.s.progressSource, o.inverse, now)
    local t, h = o.tex, o.frame
    local w, ht = h:GetWidth() or 1, h:GetHeight() or 1
    if o.s.anchor_mode == "point" then w, ht = tonumber(o.s.width) or 32, tonumber(o.s.height) or 32 end
    t:ClearAllPoints()
    if p <= 0.0001 then t:Hide() return end
    t:Show()
    local l, r = 0, 1
    if o.mirror then l, r = 1, 0 end
    local ori = o.orientation
    if ori == "HORIZONTAL" then
        t:SetPoint("TOPLEFT", h, "TOPLEFT") t:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT")
        t:SetWidth(w * p) t:SetTexCoord(l, l + (r - l) * p, 0, 1)
    elseif ori == "HORIZONTAL_INVERSE" then
        t:SetPoint("TOPRIGHT", h, "TOPRIGHT") t:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT")
        t:SetWidth(w * p) t:SetTexCoord(r - (r - l) * p, r, 0, 1)
    elseif ori == "VERTICAL_INVERSE" then
        t:SetPoint("TOPLEFT", h, "TOPLEFT") t:SetPoint("TOPRIGHT", h, "TOPRIGHT")
        t:SetHeight(ht * p) t:SetTexCoord(l, r, 0, p)
    else
        t:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT") t:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT")
        t:SetHeight(ht * p) t:SetTexCoord(l, r, 1 - p, 1)
    end
end

local function MakeCircular(f, s)
    local holder = CreateFrame("Frame", nil, f)
    PlaceBox(holder, f, s)
    holder:SetFrameLevel(f:GetFrameLevel() + 3)
    local sw = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    sw:SetAllPoints(holder)
    if sw.SetDrawBling then sw:SetDrawBling(false) end
    if sw.SetDrawEdge then sw:SetDrawEdge(false) end
    if sw.SetHideCountdownNumbers then sw:SetHideCountdownNumbers(true) end
    if sw.SetSwipeTexture then pcall(sw.SetSwipeTexture, sw, tonumber(s.circularTextureTexture) or s.circularTextureTexture) end
    local o = { kind = "circular", s = s, frame = holder, sweep = sw, visible = s.circularTextureVisible ~= false,
        inverse = s.circularTextureInverse, clockwise = s.circularTextureClockwise ~= false,
        mirror = s.circularTextureMirror, color = s.circularTextureColor }
    if sw.SetSwipeColor then pcall(sw.SetSwipeColor, sw, Color(o.color)) end
    holder:SetShown(o.visible)
    return o
end

local function DrawCircular(f, o, now)
    local p = SubFill(f, o.s.progressSource, o.inverse, now)
    local sw = o.sweep
    if p <= 0.0001 then sw:Hide() return end
    sw:Show()
    local cw = o.clockwise
    if o.mirror then cw = not cw end
    if sw.SetReverse then sw:SetReverse(cw) end
    pcall(sw.SetCooldown, sw, now - (cw and p or (1 - p)) * 100, 100)
    pcall(sw.Pause, sw)
end

-- ============================================================
-- MODEL
-- ============================================================
local function MakeModel(f, s)
    local m = CreateFrame("PlayerModel", nil, f)
    if f.regionType == "aurabar" and s.bar_model_attach ~= false then
        m:SetAllPoints(f.bar)
    else
        m:SetAllPoints(f)
    end
    R.LoadModel(m, s)
    R.PoseModel(m, s, tonumber(s.rotation) or 0)
    m:SetAlpha(tonumber(s.model_alpha) or 1)
    m:SetShown(s.model_visible ~= false)
    return { kind = "model", s = s, model = m }
end

-- ============================================================
-- FLIP BOOK
-- ============================================================
local function MakeStopMotion(f, s)
    local holder = CreateFrame("Frame", nil, f)
    PlaceBox(holder, f, s)
    holder:SetFrameLevel(f:GetFrameLevel() + 3)
    local t = holder:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(holder)
    local path = s.stopmotionTexture
    local book = R.FlipBook(path, s, "custom")
    R.SetTexture(t, book.rows and path or (tostring(path) .. "000"))
    t:SetBlendMode(s.stopmotionBlendMode or "BLEND")
    t:SetDesaturated(s.stopmotionDesaturate and true or false)
    t:SetVertexColor(Color(s.stopmotionColor))
    local o = { kind = "stopmotion", s = s, frame = holder, tex = t, book = book, path = path,
        opts = { startPercent = tonumber(s.startPercent) or 0, endPercent = tonumber(s.endPercent) or 1,
            frameRate = tonumber(s.frameRate) or 30, animationType = s.animationType, inverse = s.inverse } }
    holder:SetShown(s.stopmotionVisible ~= false)
    holder:SetScript("OnUpdate", function()
        local now = GetTime()
        local frame
        if o.opts.animationType == "progress" then
            frame = R.FlipFrame(book, o.opts, 0, SubFill(f, s.progressSource, false, now))
        else
            frame = R.FlipFrame(book, o.opts, now - (o.start or now), nil)
        end
        if frame ~= o.now then
            o.now = frame
            R.FlipTo(t, book, path, frame)
        end
    end)
    return o
end

-- ============================================================
-- BUILD / APPLY / TICK
-- ============================================================
local MAKERS = { subtext = MakeText, subborder = MakeBorder, subglow = MakeGlow, subtick = MakeTick,
    subtexture = MakeTexture, sublineartexture = MakeLinear, subcirculartexture = MakeCircular,
    submodel = MakeModel, substopmotion = MakeStopMotion }

function S.Build(f, d)
    f.subs = {}
    f.timedSubs = nil
    for i, s in ipairs(type(d.subRegions) == "table" and d.subRegions or {}) do
        local make = type(s) == "table" and MAKERS[s.type]
        local okType = make and (not S.supports[s.type] or S.supports[s.type][d.regionType])
        if okType then
            local ok, o = pcall(make, f, s, i)
            if ok and o then
                o.index = i
                f.subs[i] = o
                if o.timed or o.kind == "linear" or o.kind == "circular" or o.kind == "tick" then f.timedSubs = true end
            elseif not ok then
                E.Error(f.id, "sub-element " .. i, o)
            end
        end
    end
end

function S.Apply(f, st)
    local now = GetTime()
    for _, o in pairs(f.subs or {}) do
        local k = o.kind
        if k == "text" then
            if o.fs:IsShown() then o.fs:SetText(TextOf(f, o)) end
        elseif k == "glow" then
            S.SetGlow(f, o, o.on)
        elseif k == "tick" then
            PlaceTicks(f, o)
        elseif k == "linear" then
            DrawLinear(f, o, now)
        elseif k == "circular" then
            DrawCircular(f, o, now)
        elseif k == "stopmotion" then
            if not o.start or not f:IsShown() then o.start = now end
        end
    end
end

function S.Tick(f, now)
    if not f.timedSubs then return end
    for _, o in pairs(f.subs) do
        local k = o.kind
        if k == "text" then
            if o.timed and o.fs:IsShown() then o.fs:SetText(TextOf(f, o)) end
        elseif k == "linear" then
            DrawLinear(f, o, now)
        elseif k == "circular" then
            DrawCircular(f, o, now)
        elseif k == "tick" and o.running then
            PlaceTicks(f, o)
        end
    end
end

function S.SetGlow(f, o, on)
    o.on = on and true or false
    local key = "sub" .. o.index
    if o.on and (f:IsShown() or f.showing) then
        E.Glow.Show(o.area, GlowOpts(o), key)
    else
        E.Glow.Hide(o.area, key)
    end
end

-- a value a condition sets on top of the sub-element's own table
local function Over(o, key, value)
    o.s = setmetatable({ [key] = value }, { __index = o.s })
end

-- a property a condition changed: "sub.3.text_color" etc.
function S.Set(f, index, prop, value)
    local o = f.subs and f.subs[index]
    if not o then return end
    local k = o.kind
    if k == "text" then
        if prop == "text_visible" then
            o.visible = value and true or false
            o.fs:SetShown(o.visible)
            if o.visible then o.fs:SetText(TextOf(f, o)) end
        elseif prop == "text_color" then
            o.color = value
            o.fs:SetTextColor(Color(value))
        elseif prop == "text_text" then
            o.text = value
            o.timed = E.Text.IsTimed(value)
            if o.timed then f.timedSubs = true end
            o.fs:SetText(TextOf(f, o))
        elseif prop == "text_fontSize" then
            o.fontSize = tonumber(value)
            R.SetFont(o.fs, o.s.text_font, o.fontSize, o.s.text_fontType)
        elseif prop == "text_anchorXOffset" then
            o.offX = tonumber(value)
            PlaceText(f, o)
        elseif prop == "text_anchorYOffset" then
            o.offY = tonumber(value)
            PlaceText(f, o)
        end
    elseif k == "border" then
        if prop == "border_color" and o.frame.SetBackdropBorderColor then o.frame:SetBackdropBorderColor(Color(value))
        elseif prop == "border_visible" then o.frame:SetShown(value and true or false) end
    elseif k == "glow" then
        if prop == "glow" then
            S.SetGlow(f, o, value)
        elseif S.properties.subglow[prop] then
            Over(o, prop, value)
            if prop == "glowColor" then Over(o, "useGlowColor", true) end
            if prop == "glowType" then o.area = GlowArea(f, o.s) end
            if o.on then S.SetGlow(f, o, true) end
        end
    elseif k == "tick" then
        local n = prop:match("^tick_placements%.(%d+)$")
        if n then
            o.list[tonumber(n)] = tonumber(value)
        elseif prop == "tick_visible" then o.visible = value and true or false
        elseif prop == "tick_color" then o.color = value
        elseif prop == "tick_placement_mode" then o.mode = value or "AtValue"
        elseif prop == "automatic_length" then o.auto = value and true or false
        elseif prop == "tick_length" then o.length = tonumber(value) or o.length
        elseif prop == "tick_thickness" then o.thickness = tonumber(value) or o.thickness
        elseif prop == "tick_use_texture" then o.useTexture = value and true or false
        elseif prop == "tick_texture" then o.texture = value
        elseif prop == "tick_desaturate" then o.desaturate = value
        elseif prop == "tick_rotation" then o.rotation = tonumber(value) or 0
        elseif prop == "tick_mirror" then o.mirror = value end
        for _, t in ipairs(o.tex) do StyleTick(o, t) end
        PlaceTicks(f, o)
    elseif k == "texture" then
        if prop == "textureColor" then o.color = value
        elseif prop == "textureDesaturate" then o.desaturate = value
        elseif prop == "textureMirror" then o.mirror = value
        elseif prop == "textureRotation" then o.rotation = tonumber(value) or 0
        elseif prop == "textureVisible" then o.tex:SetShown(value and true or false) end
        StyleTexture(o)
    elseif k == "linear" or k == "circular" then
        local pre = k == "linear" and "linearTexture" or "circularTexture"
        local what = prop:sub(#pre + 1)
        if what == "Color" then
            o.color = value
            if k == "linear" then o.tex:SetVertexColor(Color(value))
            elseif o.sweep.SetSwipeColor then pcall(o.sweep.SetSwipeColor, o.sweep, Color(value)) end
        elseif what == "Desaturate" then
            if o.tex then o.tex:SetDesaturated(value and true or false) end
        elseif what == "Visible" then
            o.visible = value and true or false
            o.frame:SetShown(o.visible)
        elseif what == "Inverse" then o.inverse = value
        elseif what == "Mirror" then o.mirror = value
        elseif what == "Clockwise" then o.clockwise = value and true or false end
        if k == "linear" then DrawLinear(f, o, GetTime()) else DrawCircular(f, o, GetTime()) end
    elseif k == "model" then
        if prop == "model_alpha" then o.model:SetAlpha(tonumber(value) or 1)
        elseif prop == "model_visible" then o.model:SetShown(value and true or false) end
    elseif k == "stopmotion" then
        if prop == "stopmotionColor" then o.tex:SetVertexColor(Color(value))
        elseif prop == "stopmotionDesaturate" then o.tex:SetDesaturated(value and true or false)
        elseif prop == "stopmotionVisible" then o.frame:SetShown(value and true or false) end
    end
end

-- glows go when the region hides (they are drawn on their own frames)
function S.Hide(f)
    for _, o in pairs(f.subs or {}) do
        if o.kind == "glow" then E.Glow.Hide(o.area, "sub" .. o.index) end
    end
end
