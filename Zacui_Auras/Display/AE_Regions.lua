-- AE_Regions - the frames a display draws with: icon, bar, text,
-- texture, progress texture (linear and circular), stop motion, model and
-- the empty one. Groups are AE_Groups; what hangs off a region (texts,
-- borders, glows...) is AE_SubRegions.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- Every region has the same few entry points the rest of the engine calls:
--   R.New(id, cloneId)    build one for a display
--   R.Apply(f, st)        show what one state says (icon, name, timer...)
--   R.Tick(f, now)        a timer moved on (only while one is running)
--   R.Place(f, d, st)     put a top-level region where its display says
-- and the fields f.id, f.cloneId, f.d, f.state, f.ctx.
--
-- A region also answers the names the WeakAuras format's conditions and
-- animations use (SetRegionAlpha, Color, SetDesaturated, Scale,
-- SetOffsetAnim, SetAnimAlpha, SetAnimRotation, ColorAnim...), so a
-- condition or an animation is just a call on the region. Which of those
-- each region type offers to conditions is R.properties below.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local R = {}
E.Regions = R
R.types = {}

local Color = E.Color
local abs, floor, max, min = math.abs, math.floor, math.max, math.min

-- ============================================================
-- WHAT A FIELD MEANS WHEN A DISPLAY DOES NOT SAY
-- ============================================================
-- The WeakAuras format fills every missing field with its region type's
-- default when a display is added; these are those values, so a display
-- missing a field looks here exactly as it would there. The editor's new
-- displays start from the same tables.
local WHITE = { 1, 1, 1, 1 }
local MEDIA = "Interface\\AddOns\\" .. (E.addon or "Zacui_Auras") .. "\\"
local POWERAURA3 = MEDIA .. "PowerAurasMedia\\Auras\\Aura3"
R.MEDIA = MEDIA

local POSITION = { anchorFrameType = "SCREEN", anchorPoint = "CENTER", selfPoint = "CENTER",
    xOffset = 0, yOffset = 0, frameStrata = 1 }
local PROGRESS = { progressSource = { -1, "" }, useAdjustededMax = false, useAdjustededMin = false,
    adjustedMax = "", adjustedMin = "" }

local function With(...)
    local t = {}
    for i = 1, select("#", ...) do
        for k, v in pairs((select(i, ...))) do t[k] = v end
    end
    return t
end

R.defaults = {
    icon = With(POSITION, PROGRESS, { width = 64, height = 64, alpha = 1, icon = true, iconSource = -1,
        color = WHITE, desaturate = false, zoom = 0, keepAspectRatio = false, cooldown = true, inverse = false,
        cooldownSwipe = true, cooldownEdge = false, cooldownTextDisabled = false, useCooldownModRate = true }),
    aurabar = With(POSITION, PROGRESS, { width = 200, height = 15, alpha = 1, texture = "Melli",
        textureSource = "LSM", orientation = "HORIZONTAL", inverse = false, barColor = { 1, 0, 0, 1 },
        barColor2 = { 1, 1, 0, 1 }, enableGradient = false, gradientOrientation = "HORIZONTAL",
        backgroundColor = { 0, 0, 0, 0.5 }, icon = false, iconSource = -1, icon_side = "RIGHT",
        icon_color = WHITE, desaturate = false, zoom = 0, spark = false,
        sparkTexture = "Interface\\CastingBar\\UI-CastingBar-Spark", sparkColor = WHITE, sparkWidth = 10,
        sparkHeight = 30, sparkOffsetX = 0, sparkOffsetY = 0, sparkRotationMode = "AUTO", sparkRotation = 0,
        sparkHidden = "NEVER", sparkBlendMode = "ADD" }),
    text = With(POSITION, { selfPoint = "BOTTOM", displayText = "%p", font = "Friz Quadrata TT", fontSize = 12,
        outline = "OUTLINE", color = WHITE, justify = "LEFT", automaticWidth = "Auto", fixedWidth = 200,
        wordWrap = "WordWrap", shadowColor = { 0, 0, 0, 1 }, shadowXOffset = 1, shadowYOffset = -1,
        customTextUpdate = "event" }),
    texture = With(POSITION, { width = 200, height = 200, alpha = 1, texture = POWERAURA3, color = WHITE,
        blendMode = "BLEND", desaturate = false, mirror = false, rotate = false, rotation = 0,
        textureWrapMode = "CLAMPTOBLACKADDITIVE" }),
    progresstexture = With(POSITION, PROGRESS, { width = 200, height = 200, alpha = 1,
        foregroundTexture = POWERAURA3, backgroundTexture = POWERAURA3, sameTexture = true,
        desaturateForeground = false, desaturateBackground = false, foregroundColor = WHITE,
        backgroundColor = { 0.5, 0.5, 0.5, 0.5 }, blendMode = "BLEND", orientation = "VERTICAL",
        inverse = false, compress = false, mirror = false, rotation = 0, auraRotation = 0,
        startAngle = 0, endAngle = 360, crop_x = 0.41, crop_y = 0.41, user_x = 0, user_y = 0,
        backgroundOffset = 2, slantMode = "INSIDE", textureWrapMode = "CLAMPTOBLACKADDITIVE" }),
    stopmotion = With(POSITION, PROGRESS, { width = 128, height = 128,
        foregroundTexture = MEDIA .. "Media\\Textures\\stopmotion", backgroundTexture = MEDIA .. "Media\\Textures\\stopmotion",
        sameTexture = true, hideBackground = true, foregroundColor = WHITE, backgroundColor = { 0.5, 0.5, 0.5, 0.5 },
        desaturateForeground = false, desaturateBackground = false, blendMode = "BLEND", frameRate = 15,
        animationType = "loop", startPercent = 0, endPercent = 1, backgroundPercent = 1, inverse = false,
        mirror = false, customForegroundRows = 16, customForegroundColumns = 16, customForegroundFrames = 0,
        customForegroundFileWidth = 0, customForegroundFileHeight = 0, customForegroundFrameWidth = 0,
        customForegroundFrameHeight = 0, customBackgroundRows = 16, customBackgroundColumns = 16,
        customBackgroundFrames = 0 }),
    model = With(POSITION, { width = 200, height = 200, alpha = 1, model_fileId = "122968", modelIsUnit = false,
        api = false, model_x = 0, model_y = 0, model_z = 0, rotation = 0, model_st_tx = 40, model_st_ty = 0,
        model_st_tz = 0, model_st_rx = 90, model_st_ry = 0, model_st_rz = 90, model_st_us = 40, advance = false,
        sequence = 1, scale = 1, border = false, borderEdge = "None", borderBackdrop = "Blizzard Tooltip",
        borderColor = { 1, 1, 1, 0.5 }, backdropColor = { 1, 1, 1, 0.5 }, borderOffset = 5, borderInset = 11,
        borderSize = 16 }),
    empty = With(POSITION, { width = 200, height = 200, alpha = 1 }),
    group = With(POSITION, { alpha = 1, scale = 1, border = false, borderEdge = "Square Full White",
        borderBackdrop = "Blizzard Tooltip", borderColor = { 0, 0, 0, 1 }, backdropColor = { 1, 1, 1, 0.5 },
        borderOffset = 4, borderInset = 1, borderSize = 2 }),
    dynamicgroup = With(POSITION, { selfPoint = "TOP", alpha = 1, scale = 1, grow = "DOWN", align = "CENTER",
        space = 2, stagger = 0, sort = "none", animate = false, radius = 200, rotation = 0, stepAngle = 15,
        arcLength = 360, fullCircle = true, constantFactor = "RADIUS", gridType = "RD", gridWidth = 5,
        rowSpace = 1, columnSpace = 1, centerType = "LR", useLimit = false, limit = 5, border = false,
        borderEdge = "Square Full White", borderBackdrop = "Blizzard Tooltip", borderColor = { 0, 0, 0, 1 },
        backdropColor = { 1, 1, 1, 0.5 }, borderOffset = 4, borderInset = 1, borderSize = 2 }),
}

-- the display's value for a field, or its region type's default
local function V(d, key)
    local v = d[key]
    if v == nil then
        local def = R.defaults[d.regionType]
        if def then v = def[key] end
    end
    return v
end
R.Value = V
local function N(d, key, fallback) return tonumber(V(d, key)) or fallback or 0 end

-- ============================================================
-- WHAT CONDITIONS CAN CHANGE, PER REGION TYPE
-- ============================================================
-- property = { kind, region method }. Kinds: bool, number, color, list,
-- string, icon, texture, textureLSM, progressSource, and the one-off
-- actions (sound, chat, customcode, glowexternal) the conditions code
-- runs itself.
local ACTIONS = { sound = { "sound" }, chat = { "chat" }, customcode = { "customcode" },
    glowexternal = { "glowexternal" }, xOffsetRelative = { "number", "SetXOffsetRelative" },
    yOffsetRelative = { "number", "SetYOffsetRelative" } }
local ALPHA = { alpha = { "number", "SetRegionAlpha" } }
local SIZE = { width = { "number", "SetRegionWidth" }, height = { "number", "SetRegionHeight" } }
local PROGRESSPROPS = { progressSource = { "progressSource", "SetProgressSource" },
    adjustedMin = { "string", "SetAdjustedMin" }, adjustedMax = { "string", "SetAdjustedMax" } }

R.properties = {
    icon = With(ACTIONS, ALPHA, SIZE, PROGRESSPROPS, { desaturate = { "bool", "SetDesaturated" },
        color = { "color", "Color" }, displayIcon = { "icon", "SetIcon" }, iconSource = { "list", "SetIconSource" },
        zoom = { "number", "SetZoom" }, inverse = { "bool", "SetInverse" },
        cooldownSwipe = { "bool", "SetCooldownSwipe" }, cooldownEdge = { "bool", "SetCooldownEdge" },
        cooldownTextDisabled = { "bool", "SetHideCountdownNumbers" } }),
    aurabar = With(ACTIONS, ALPHA, SIZE, PROGRESSPROPS, { barColor = { "color", "Color" },
        barColor2 = { "color", "SetBarColor2" }, enableGradient = { "bool", "SetGradientEnabled" },
        gradientOrientation = { "list", "SetGradientOrientation" }, backgroundColor = { "color", "SetBackgroundColor" },
        icon = { "bool", "SetIconVisible" }, icon_color = { "color", "SetIconColor" },
        desaturate = { "bool", "SetIconDesaturated" }, displayIcon = { "icon", "SetIcon" },
        iconSource = { "list", "SetIconSource" }, inverse = { "bool", "SetInverse" },
        orientation = { "list", "SetOrientation" }, sparkColor = { "color", "SetSparkColor" },
        sparkWidth = { "number", "SetSparkWidth" }, sparkHeight = { "number", "SetSparkHeight" },
        texture = { "textureLSM", "SetStatusBarTextureLSM" }, textureInput = { "texture", "SetStatusBarTextureInput" },
        textureSource = { "list", "SetStatusBarTextureMode" } }),
    text = With(ACTIONS, { color = { "color", "Color" }, displayText = { "string", "ChangeText" },
        fontSize = { "number", "SetTextHeight" } }),
    texture = With(ACTIONS, ALPHA, SIZE, { color = { "color", "Color" }, desaturate = { "bool", "SetDesaturated" },
        mirror = { "bool", "SetMirror" }, rotation = { "number", "SetRotation" }, texture = { "texture", "SetTexture" } }),
    progresstexture = With(ACTIONS, ALPHA, SIZE, PROGRESSPROPS, { foregroundColor = { "color", "Color" },
        backgroundColor = { "color", "SetBackgroundColor" }, desaturateForeground = { "bool", "SetForegroundDesaturated" },
        desaturateBackground = { "bool", "SetBackgroundDesaturated" }, inverse = { "bool", "SetInverse" },
        mirror = { "bool", "SetMirror" }, orientation = { "list", "SetOrientation" }, rotation = { "number", "SetTexRotation" },
        auraRotation = { "number", "SetAuraRotation" }, crop_x = { "number", "SetCropX" }, crop_y = { "number", "SetCropY" } }),
    stopmotion = With(ACTIONS, SIZE, PROGRESSPROPS, { foregroundColor = { "color", "Color" },
        backgroundColor = { "color", "SetBackgroundColor" }, desaturateForeground = { "bool", "SetForegroundDesaturated" },
        desaturateBackground = { "bool", "SetBackgroundDesaturated" } }),
    model = With(ACTIONS, ALPHA, SIZE),
    empty = With(ACTIONS, ALPHA),
}

-- ============================================================
-- MEDIA, STRATA, FONTS
-- ============================================================
local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end
local function IsPath(name) return type(name) == "string" and (name:find("\\", 1, true) or name:find("/", 1, true)) end

function R.Font(name)
    local lib = LSM()
    local path = name and lib and lib:Fetch("font", name, true)
    if not path and ns.ResolveFontPath then path = ns.ResolveFontPath(name) end
    if not path and IsPath(name) then path = name end
    -- (no face of its own: the game's, not STANDARD_TEXT_FONT - that is
    -- ZacUI's font of the session's start once ZacUI has set it)
    return path or ns.GAME_FONT or STANDARD_TEXT_FONT
end

function R.Statusbar(name)
    local lib = LSM()
    local path = name and lib and lib:Fetch("statusbar", name, true)
    if path then return path end
    -- a name of one ZacUI (or the raid packs) used to carry -> its
    -- replacement (Core_MediaNames)
    local new = ns.NewMediaName and ns.NewMediaName(name)
    if new then
        path = (lib and lib:Fetch("statusbar", new, true)) or (ns.OwnMediaPath and ns.OwnMediaPath("statusbar", new))
        if path then return path end
    end
    if IsPath(name) or tonumber(name) then return name end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

function R.Border(name)
    if name == "None" then return nil end
    local lib = LSM()
    local path = name and lib and lib:Fetch("border", name, true)
    if path then return path end
    if IsPath(name) then return name end
    return "Interface\\Buttons\\WHITE8x8"
end

function R.Background(name)
    if name == nil or name == "None" then return nil end
    local lib = LSM()
    local path = lib and lib:Fetch("background", name, true)
    if path then return path end
    if IsPath(name) then return name end
    return "Interface\\Tooltips\\UI-Tooltip-Background"
end

-- font flags as the format stores them ("None", "OUTLINE", "MONOCHROME|OUTLINE"...)
function R.Outline(v)
    if v == nil then return "OUTLINE" end
    if v == "None" or v == "NONE" or v == "" then return "" end
    return (tostring(v):gsub("|SLUG", ""):gsub("SLUG|?", ""):gsub("|", ","))
end

local STRATA = { [2] = "BACKGROUND", [3] = "LOW", [4] = "MEDIUM", [5] = "HIGH",
    [6] = "DIALOG", [7] = "FULLSCREEN", [8] = "FULLSCREEN_DIALOG", [9] = "TOOLTIP" }
function R.Strata(v) return STRATA[tonumber(v) or 1] end

-- SetFont that says whether the face took: pcall catches a nil path, the
-- return value a font file that would not load - which leaves the string
-- with no font, so its next SetText errors ("Font not set")
local function TrySetFont(fs, path, size, flags)
    local ok, set = pcall(fs.SetFont, fs, path, size, flags)
    return (ok and set) and true or false
end
-- Every text of every display (saved, just imported, made or edited in
-- the editor, a sub-text added later, the import preview) is dressed
-- here, so this is where ZacUI's one font wins: the face is ZacUI's font
-- whenever one is chosen, and the aura's own face (kept untouched in its
-- data, so an export still carries it) only while none is. Size and
-- outline stay the aura's. The string is kept up by ZacUI's font keeper,
-- so a later change of ZacUI's font reaches it at once.
local function RedoAuraFont(fs)
    R.SetFont(fs, rawget(fs, "_zAeFont"), rawget(fs, "_zAeSize"), rawget(fs, "_zAeOutline"))
end
function R.SetFont(fs, font, size, outline)
    local path = (ns.OneFace and ns.OneFace()) or R.Font(font)
    if not TrySetFont(fs, path, tonumber(size) or 12, R.Outline(outline)) then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, tonumber(size) or 12, "OUTLINE") end
    rawset(fs, "_zAeFont", font)
    rawset(fs, "_zAeSize", size)
    rawset(fs, "_zAeOutline", outline)
    if ns.TrackHouseFont then ns.TrackHouseFont(fs, RedoAuraFont) end
end

-- a texture path, file id or atlas onto a texture. A path into the old
-- raid-pack media folder is replaced by what took its place (a game icon,
-- one of ZacUI's own shapes, or nothing - ns.LegacyTexture).
function R.SetTexture(tex, path, wrap)
    if type(path) == "string" and ns.LegacyTexture then
        local v = ns.LegacyTexture(path)
        if v ~= nil then path = v or nil end
    end
    if path == nil or path == "" then
        tex:SetTexture(nil)
        return
    end
    local atlasInfo = C_Texture and C_Texture.GetAtlasInfo
    if type(path) == "string" and not IsPath(path) and not tonumber(path) and atlasInfo and tex.SetAtlas then
        local ok, info = pcall(atlasInfo, path)
        if ok and info then
            tex:SetAtlas(path)
            return
        end
    end
    if wrap and wrap ~= "CLAMPTOBLACKADDITIVE" then
        tex:SetTexture(tonumber(path) or path, wrap, wrap)
    else
        tex:SetTexture(tonumber(path) or path)
    end
end

-- texture corners turned by `degrees` around the middle (ZacUI's own sum):
-- returns the eight SetTexCoord numbers (upper left, lower left, upper
-- right, lower right). zoomOut shows the whole picture while it turns;
-- otherwise the corners are cut so it always fills the frame.
local CORNERS = { { -0.5, 0.5 }, { -0.5, -0.5 }, { 0.5, 0.5 }, { 0.5, -0.5 } }
function R.TurnedCoords(degrees, zoomOut, mirrorH, mirrorV)
    local a = math.rad(tonumber(degrees) or 0)
    local c, s = math.cos(a), math.sin(a)
    local k = zoomOut and math.sqrt(2) or 1
    local out = {}
    for i, p in ipairs(CORNERS) do
        local x, y = p[1], p[2]
        if mirrorH then x = -x end
        if mirrorV then y = -y end
        -- screen y grows upwards, texture y grows downwards
        local rx, ry = (x * c - y * s) * k, (x * s + y * c) * k
        out[#out + 1] = 0.5 + rx
        out[#out + 1] = 0.5 - ry
    end
    return out[1], out[2], out[3], out[4], out[5], out[6], out[7], out[8]
end

-- ============================================================
-- WHERE A REGION HANGS
-- ============================================================
function R.AnchorFrame(region, d, state)
    local kind = d.anchorFrameType or "SCREEN"
    if kind == "SELECTFRAME" and type(d.anchorFrameFrame) == "string" then
        local name = d.anchorFrameFrame
        if name:sub(1, 10) == "WeakAuras:" then
            local other = E.regions[name:sub(11)] or (E.Groups and E.Groups.list[name:sub(11)] and E.Groups.list[name:sub(11)].frame)
            if other then return other end
        end
        local f = _G[name]
        if type(f) == "table" and f.GetObjectType then return f end
    elseif kind == "UNITFRAME" then
        local unit = state and state.unit
        if unit and E.UnitFrame then return E.UnitFrame(unit) end
        return nil
    elseif kind == "NAMEPLATE" then
        local unit = state and state.unit
        if unit and C_NamePlate then return C_NamePlate.GetNamePlateForUnit(unit) end
        return nil
    elseif kind == "MOUSE" then
        return UIParent, true
    elseif kind == "CUSTOM" and region and region.customAnchor then
        local f = E.Env.Run(region.id, region.customAnchor, state, E.states[region.id], region)
        if type(f) == "table" and f.GetObjectType then return f end
    end
    return UIParent
end

-- the one SetPoint every region goes through: its anchor plus its own
-- offset, the offset a condition added and the offset an animation adds
local function UpdatePosition(f)
    local a = f.anchor
    if not a then return end
    f:ClearAllPoints()
    local x = (a[4] or 0) + (f.relX or 0) + (f.animX or 0)
    local y = (a[5] or 0) + (f.relY or 0) + (f.animY or 0)
    pcall(f.SetPoint, f, a[1], a[2], a[3], x, y)
end
R.UpdatePosition = UpdatePosition

function R.SetAnchor(f, point, rel, relPoint, x, y)
    f.anchor = { point or "CENTER", rel or UIParent, relPoint or point or "CENTER", x or 0, y or 0 }
    UpdatePosition(f)
end

-- Where a display anchored to a unit's frame or plate waits while that unit
-- has none: out of sight, as WeakAuras does (its HiddenFrames), never on
-- the screen or its group's spot.
local hiddenAnchor = CreateFrame("Frame", nil, UIParent)
hiddenAnchor:Hide()
R.HiddenAnchor = hiddenAnchor

-- puts a top-level region where its display says (a child of a dynamic
-- group is placed by the group). A child of a plain group hangs from the
-- group while it is anchored to the screen ("SCREEN", the format's "the
-- parent group"); anchored to a unit frame, a plate, a named frame... it
-- hangs from that, as in WeakAuras.
function R.Place(region, d, state)
    local x, y = tonumber(d.xOffset) or 0, tonumber(d.yOffset) or 0
    local parent = region.groupFrame
    local kind = d.anchorFrameType or "SCREEN"
    if parent and kind == "SCREEN" then
        if region:GetParent() ~= parent then region:SetParent(parent) end
        R.SetAnchor(region, d.selfPoint or "CENTER", parent, d.anchorPoint or "CENTER", x, y)
        return true
    end
    local frame, mouse = R.AnchorFrame(region, d, state)
    if not frame then
        if kind == "UNITFRAME" or kind == "NAMEPLATE" then
            R.SetAnchor(region, d.selfPoint or "CENTER", hiddenAnchor, d.anchorPoint or "CENTER", x, y)
            region:SetParent(hiddenAnchor)
            return true
        end
        if parent then
            R.SetAnchor(region, d.selfPoint or "CENTER", parent, d.anchorPoint or "CENTER", x, y)
            return true
        end
        return false
    end
    region.followMouse = mouse or nil
    if region:GetParent() == hiddenAnchor then region:SetParent(parent or UIParent) end
    if mouse then
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        R.SetAnchor(region, d.selfPoint or "CENTER", UIParent, "BOTTOMLEFT", cx / s + x, cy / s + y)
    else
        R.SetAnchor(region, d.selfPoint or "CENTER", frame, d.anchorPoint or "CENTER", x, y)
        if d.anchorFrameParent ~= false and frame ~= UIParent and d.anchorFrameType ~= "SCREEN"
            and d.anchorFrameType ~= "UIPARENT" then
            region:SetParent(frame)
        end
    end
    return true
end

-- ============================================================
-- PROGRESS
-- ============================================================
-- the raw numbers of a state: value, total, and whether it is a running
-- timer (kept for code that asks for them)
function R.Progress(state, now)
    if not state then return 0, 1, false end
    if state.progressType == "timed" then
        local dur = tonumber(state.duration) or 0
        if state.paused then
            local rem = tonumber(state.remaining) or 0
            return rem, dur > 0 and dur or 1, false
        end
        local exp = tonumber(state.expirationTime)
        if dur <= 0 or not exp or exp == math.huge then return 1, 1, false end
        local mod = tonumber(state.modRate) or 1
        return math.max(0, (exp - now) / mod), dur, true
    end
    local total = tonumber(state.total) or 0
    local value = tonumber(state.value) or 0
    if total <= 0 then return 1, 1, false end
    return value, total, false
end

-- adjusted min/max ("useAdjustededMax" is how the format spells it);
-- "50%" means half the total
local function Bound(d, which, total)
    if not d["useAdjusteded" .. which] then return nil end
    local s = d["adjusted" .. which]
    if s == nil or s == "" then return nil end
    local pct = tostring(s):match("(%d+)%%")
    if pct then return tonumber(pct) / 100 * total end
    return tonumber(s)
end

-- the low and high end a value is measured between
function R.Bounds(d, total)
    return Bound(d, "Min", total) or 0, Bound(d, "Max", total) or total
end

function R.Adjust(d, value, total)
    local lo, hi = Bound(d, "Min", total) or 0, Bound(d, "Max", total) or total
    if hi - lo <= 0 then return value >= hi and 1 or 0 end
    return math.max(0, math.min(1, (value - lo) / (hi - lo)))
end

-- which state the region's progress comes from (progressSource: {-1}
-- the shown state, {n, "field"} trigger n, {0, kind, value, total} a
-- fixed number)
local function SourceState(f, st)
    local src = type(f.progressSource) == "table" and f.progressSource or nil
    local t = src and tonumber(src[1]) or -1
    if t == 0 then
        return { progressType = "static", value = tonumber(src[3]) or 0, total = tonumber(src[4]) or 100 }
    end
    if t and t > 0 then
        local ts = f.ctx and f.ctx.triggers and f.ctx.triggers[t]
        local prop = src[2]
        if ts and type(prop) == "string" and prop ~= "" and prop ~= "auto" then
            -- a named field: the trigger code may describe it; otherwise a
            -- time point counts as a timer and anything else as a number
            local meta = E.ProgressSourceMeta and E.ProgressSourceMeta(f.d, t, prop)
            if type(meta) == "table" then
                if meta.type == "timer" or meta.type == "elapsedTimer" then
                    local total = tonumber(meta.total and ts[meta.total]) or tonumber(ts.duration) or 0
                    local at = tonumber(ts[prop])
                    if meta.type == "elapsedTimer" and at then at = at + total end
                    return { progressType = "timed", expirationTime = at, duration = total,
                        modRate = meta.modRate and ts[meta.modRate], inverse = meta.type == "elapsedTimer" }
                end
                return { progressType = "static", value = tonumber(ts[prop]) or 0,
                    total = tonumber(meta.total and ts[meta.total]) or 0 }
            end
            if prop == "expirationTime" then return ts end
            return { progressType = "static", value = tonumber(ts[prop]) or 0,
                total = tonumber(ts[prop .. "Max"] or ts.total) or 100 }
        end
        return ts
    end
    return st
end
R.SourceState = SourceState

-- how full the region is, 0..1, the way the format draws it: a timer is
-- full when it starts and empties; `inverse` (the display's, flipped by a
-- state's own inverse) turns that round. Also returns whether the value
-- is a running timer.
function R.Fill(f, st, now)
    local s = SourceState(f, st)
    if not s then return 0, false end
    local d = f.d
    local p, running
    if s.progressType == "timed" then
        local dur = tonumber(s.duration) or 0
        local exp = tonumber(s.expirationTime)
        local rem
        if s.paused then
            rem = tonumber(s.remaining) or 0
        elseif exp and exp ~= math.huge then
            rem = (exp - now) / (tonumber(s.modRate) or 1)
            running = true
        end
        if dur <= 0 or not rem then
            p = (dur <= 0) and 1 or 0
            running = false
        else
            p = R.Adjust(d, rem, dur)
        end
    elseif s.progressType == "static" or s.value ~= nil then
        local total = tonumber(s.total) or 0
        p = R.Adjust(d, tonumber(s.value) or 0, total)
    else
        p = 1
    end
    local inv = (f.inverse and true or false) ~= (s.inverse and true or false)
    if inv then p = 1 - p end
    return math.max(0, math.min(1, p)), running and true or false, s
end

-- the icon a region shows: iconSource -1 the shown state's, 0 its own,
-- n trigger n's
function R.IconFor(d, state, f)
    local src = tonumber(f and f.iconSource or d.iconSource) or -1
    local icon
    if src == 0 then
        icon = f and f.displayIcon or d.displayIcon
    elseif src > 0 then
        local ts = f and f.ctx and f.ctx.triggers and f.ctx.triggers[src]
        icon = ts and ts.icon
    else
        icon = state and state.icon
    end
    if icon == nil or icon == "" then icon = f and f.displayIcon or d.displayIcon end
    if icon == "" then icon = nil end
    return icon
end

-- ============================================================
-- WHAT EVERY REGION ANSWERS
-- ============================================================
local Methods = {}
R.Methods = Methods

local function ApplyAlpha(f)
    local a = f.groupHidden and 0 or (f.animAlpha or f.baseAlpha or 1)
    f:SetAlpha(math.max(0, math.min(1, a)))
end
R.ApplyAlpha = ApplyAlpha

function Methods.SetRegionAlpha(f, a) f.baseAlpha = tonumber(a) or 1 ApplyAlpha(f) end
function Methods.GetRegionAlpha(f) return f.baseAlpha or 1 end
function Methods.SetAnimAlpha(f, a) f.animAlpha = tonumber(a) ApplyAlpha(f) end
function Methods.SetGroupHidden(f, on) f.groupHidden = on and true or nil ApplyAlpha(f) end

function Methods.SetOffsetAnim(f, x, y)
    f.animX, f.animY = tonumber(x) or 0, tonumber(y) or 0
    UpdatePosition(f)
end
function Methods.SetXOffsetRelative(f, x)
    f.relX = tonumber(x) or 0
    UpdatePosition(f)
    if f.group and f.group.dynamic then E.Groups.Changed(f) end
end
function Methods.SetYOffsetRelative(f, y)
    f.relY = tonumber(y) or 0
    UpdatePosition(f)
    if f.group and f.group.dynamic then E.Groups.Changed(f) end
end

-- size: the display's width/height times an animation's scale
local function ApplySize(f)
    local w = math.max(0.001, (f.width or 1) * abs(f.scalex or 1))
    local h = math.max(0.001, (f.height or 1) * abs(f.scaley or 1))
    if f.regionType ~= "text" then f:SetSize(w, h) end
    if f.kind.Resize then f.kind.Resize(f, w, h) end
end
R.ApplySize = ApplySize

function Methods.Scale(f, sx, sy)
    f.scalex, f.scaley = tonumber(sx) or 1, tonumber(sy) or 1
    ApplySize(f)
end
function Methods.SetRegionWidth(f, w)
    f.width = math.max(1, tonumber(w) or f.width or 1)
    ApplySize(f)
    if f.group then E.Groups.Changed(f) end
end
function Methods.SetRegionHeight(f, h)
    f.height = math.max(1, tonumber(h) or f.height or 1)
    ApplySize(f)
    if f.group then E.Groups.Changed(f) end
end

-- colour: what the display (or a condition) set, and an animation's on top
local function ApplyColor(f)
    if not f.kind.SetColor then return end
    local c, a = f.baseColor or WHITE, f.animColor
    if a then
        f.kind.SetColor(f, a[1] or c[1], a[2] or c[2], a[3] or c[3], a[4] or c[4] or 1)
    else
        f.kind.SetColor(f, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
end
function Methods.Color(f, r, g, b, a)
    f.baseColor = { r or 1, g or 1, b or 1, a or 1 }
    f.colorOverride = f.baseColor
    ApplyColor(f)
end
function Methods.ColorAnim(f, r, g, b, a)
    if r == nil and g == nil and b == nil then f.animColor = nil else f.animColor = { r, g, b, a } end
    ApplyColor(f)
end
function Methods.GetColor(f)
    local c = f.baseColor or WHITE
    return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
end

-- rotation an animation turns (for the types that can turn)
function Methods.SetAnimRotation(f, deg)
    f.animRotation = tonumber(deg)
    if f.kind.Rotate then f.kind.Rotate(f) end
end
function Methods.GetBaseRotation(f) return tonumber(f.rotation) or 0 end

function Methods.SetDesaturated(f, v)
    local t = f.icon or f.tex or f.fg
    if t and t.SetDesaturated then t:SetDesaturated(v and true or false) end
end

-- progress settings conditions change
function Methods.SetProgressSource(f, src) f.progressSource = src R.Refresh(f) end
function Methods.SetAdjustedMin(f, v)
    f.d = setmetatable({ adjustedMin = v, useAdjustededMin = v ~= nil and v ~= "" }, { __index = f.baseD or f.d })
    R.Refresh(f)
end
function Methods.SetAdjustedMax(f, v)
    f.d = setmetatable({ adjustedMax = v, useAdjustededMax = v ~= nil and v ~= "" }, { __index = f.baseD or f.d })
    R.Refresh(f)
end
function Methods.SetInverse(f, v) f.inverse = v and true or false R.Refresh(f) end
function Methods.SetIconSource(f, v) f.iconSource = tonumber(v) R.Refresh(f) end
function Methods.SetIcon(f, v) f.displayIcon = v R.Refresh(f) end

-- redraw what the current state says (after a setting changed)
function R.Refresh(f)
    if f.state or f.kind.SetState then
        if f.kind.SetState then f.kind.SetState(f, f.d, f.state) end
        if f.kind.Tick then f.kind.Tick(f, f.d, f.state, GetTime()) end
    end
end

-- frame strata / alpha / size every type starts from
local function Base(f, d)
    f.width = math.max(1, N(d, "width", 64))
    f.height = math.max(1, N(d, "height", 64))
    f.scalex, f.scaley = 1, 1
    local strata = R.Strata(d.frameStrata)
    if strata then f:SetFrameStrata(strata) end
    f.baseAlpha = N(d, "alpha", 1)
    f.animAlpha = nil
    ApplyAlpha(f)
    f.inverse = V(d, "inverse") and true or false
    f.iconSource = tonumber(V(d, "iconSource"))
    f.displayIcon = d.displayIcon
    f.progressSource = V(d, "progressSource")
    f.rotation = N(d, "rotation", 0)
    ApplySize(f)
end
R.Base = Base

-- ============================================================
-- ICON
-- ============================================================
local Icon = {}
R.types.icon = Icon

function Icon.Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints()
    if f.cooldown.SetDrawBling then f.cooldown:SetDrawBling(false) end
    return f
end

-- the part of the picture shown: zoomed in by `zoom`, cropped to keep its
-- shape when keepAspectRatio is on, flipped by a negative scale
local function IconCoords(f)
    local z = math.max(0, math.min(1, tonumber(f.zoom) or 0))
    local half = (1 - 0.5 * z) / 2
    local hw, hh = half, half
    if f.keepAspectRatio then
        local w, h = (f.width or 1) * abs(f.scalex or 1), (f.height or 1) * abs(f.scaley or 1)
        if w > 0 and h > 0 then
            local ratio = w / h
            if ratio > 1 then hh = half / ratio else hw = half * ratio end
        end
    end
    local l, r, t, b = 0.5 - hw, 0.5 + hw, 0.5 - hh, 0.5 + hh
    if (f.scalex or 1) < 0 then l, r = r, l end
    if (f.scaley or 1) < 0 then t, b = b, t end
    f.icon:SetTexCoord(l, r, t, b)
end

function Icon.Resize(f) IconCoords(f) end
function Icon.SetColor(f, r, g, b, a) f.icon:SetVertexColor(r, g, b, a) end

function Icon.Modify(f, d)
    f.zoom = N(d, "zoom", 0)
    f.keepAspectRatio = V(d, "keepAspectRatio") and true or false
    Base(f, d)
    f.icon:SetDesaturated(V(d, "desaturate") and true or false)
    local c = V(d, "color")
    f.baseColor = { Color(c) }
    ApplyColor(f)
    local cd = f.cooldown
    f.showCooldown = V(d, "cooldown") and true or false
    if cd.SetDrawEdge then cd:SetDrawEdge(V(d, "cooldownEdge") and true or false) end
    if cd.SetDrawSwipe then cd:SetDrawSwipe(V(d, "cooldownSwipe") ~= false) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(V(d, "cooldownTextDisabled") and true or false) end
    f.useModRate = V(d, "useCooldownModRate") ~= false
    IconCoords(f)
end

function Icon.SetZoom(f, z) f.zoom = tonumber(z) or 0 IconCoords(f) end

-- the swipe: a running timer sweeps; a value stands still where it is
local function IconCooldown(f, d, st, now)
    local cd = f.cooldown
    if not f.showCooldown then
        cd:Hide()
        return
    end
    local s = SourceState(f, st)
    if not s then cd:Hide() return end
    local inv = (f.inverse and true or false) == (s.inverse and true or false)
    if cd.SetReverse then cd:SetReverse(inv) end
    if s.progressType == "timed" then
        local dur = tonumber(s.duration) or 0
        local exp = tonumber(s.expirationTime)
        local lo, hi = Bound(f.d, "Min", dur) or 0, Bound(f.d, "Max", dur) or dur
        if s.paused then
            local rem = tonumber(s.remaining) or 0
            exp = now + rem
        end
        if dur > 0 and exp and exp ~= math.huge and exp > now then
            local span = hi - lo
            if span <= 0 then cd:Hide() return end
            local key = (exp - lo) .. ":" .. span
            if f.cdKey ~= key or not cd:IsShown() then
                f.cdKey = key
                cd:Show()
                local mod = f.useModRate and tonumber(s.modRate) or nil
                pcall(cd.SetCooldown, cd, exp - lo - span, span, mod)
            end
            if s.paused then pcall(cd.Pause, cd) elseif cd.Resume then pcall(cd.Resume, cd) end
        else
            f.cdKey = nil
            cd:Hide()
        end
    elseif s.value ~= nil then
        local total = tonumber(s.total) or 0
        local value = tonumber(s.value) or 0
        local lo, hi = Bound(f.d, "Min", total) or 0, Bound(f.d, "Max", total) or total
        value, total = value - lo, hi - lo
        if total > 0 and value >= 0 and value <= total then
            f.cdKey = nil
            cd:Show()
            pcall(cd.SetCooldown, cd, now - (total - value), total)
            pcall(cd.Pause, cd)
        else
            cd:Hide()
        end
    else
        cd:Hide()
    end
end

function Icon.SetState(f, d, st)
    R.SetTexture(f.icon, R.IconFor(d, st, f) or "Interface\\Icons\\INV_Misc_QuestionMark")
    IconCooldown(f, d, st, GetTime())
end

function Icon.SetCooldownSwipe(f, v) if f.cooldown.SetDrawSwipe then f.cooldown:SetDrawSwipe(v and true or false) end end
function Icon.SetCooldownEdge(f, v) if f.cooldown.SetDrawEdge then f.cooldown:SetDrawEdge(v and true or false) end end
function Icon.SetHideCountdownNumbers(f, v)
    if f.cooldown.SetHideCountdownNumbers then f.cooldown:SetHideCountdownNumbers(v and true or false) end
end

-- ============================================================
-- TEXT
-- ============================================================
local Text = {}
R.types.text = Text

function Text.Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER")
    return f
end

function Text.SetColor(f, r, g, b, a) f.text:SetTextColor(r, g, b, a) end

function Text.Modify(f, d)
    local strata = R.Strata(d.frameStrata)
    if strata then f:SetFrameStrata(strata) end
    f.baseAlpha, f.animAlpha = N(d, "alpha", 1), nil
    ApplyAlpha(f)
    f.scalex, f.scaley = 1, 1
    f.fontSize = N(d, "fontSize", 12)
    R.SetFont(f.text, V(d, "font"), f.fontSize, V(d, "outline"))
    f.baseColor = { Color(V(d, "color")) }
    ApplyColor(f)
    local just = V(d, "justify") or "LEFT"
    f.text:SetJustifyH(just)
    f.text:SetShadowColor(Color(V(d, "shadowColor"), 0, 0, 0, 1))
    f.text:SetShadowOffset(N(d, "shadowXOffset", 1), N(d, "shadowYOffset", -1))
    f.text:ClearAllPoints()
    if V(d, "automaticWidth") == "Fixed" then
        f.text:SetWidth(N(d, "fixedWidth", 200))
        f.text:SetWordWrap(V(d, "wordWrap") ~= "Elide")
        if f.text.SetNonSpaceWrap then f.text:SetNonSpaceWrap(V(d, "wordWrap") ~= "Elide") end
    else
        f.text:SetWidth(0)
        f.text:SetWordWrap(true)
    end
    local point = just == "LEFT" and "LEFT" or (just == "RIGHT" and "RIGHT" or "CENTER")
    f.text:SetPoint(point, f, point, 0, 0)
end

-- the size follows the text, so groups lay it out right
function Text.Fit(f)
    local w = f.text:GetStringWidth() or 1
    local h = f.text:GetStringHeight() or 1
    if f.d and V(f.d, "automaticWidth") == "Fixed" then w = N(f.d, "fixedWidth", w) end
    f.width, f.height = math.max(1, w), math.max(1, h)
    f:SetSize(f.width, f.height)
end

function Text.SetTextHeight(f, size)
    f.fontSize = tonumber(size) or f.fontSize
    R.SetFont(f.text, V(f.d, "font"), f.fontSize, V(f.d, "outline"))
    Text.Fit(f)
end

function Text.ChangeText(f, text)
    f.textOverride = text
    f.text:SetText(E.Text.Format(text or "", f.d, "displayText", f.ctx or { state = f.state }))
    f.timedText = E.Text.IsTimed(text)
    Text.Fit(f)
end

-- ============================================================
-- BAR
-- ============================================================
local Bar = {}
R.types.aurabar = Bar

function Bar.Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.bar = CreateFrame("Frame", nil, f)
    f.bg = f.bar:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f.bar)
    f.fg = f.bar:CreateTexture(nil, "ARTWORK")
    f.spark = f.bar:CreateTexture(nil, "OVERLAY")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    return f
end

local function Vertical(o) return o == "VERTICAL" or o == "VERTICAL_INVERSE" end

local function BarTexture(f, d)
    if V(d, "textureSource") == "Picker" and d.textureInput and d.textureInput ~= "" then return d.textureInput end
    return R.Statusbar(f.barTexture or V(d, "texture"))
end

local function BarColorize(f, r, g, b, a)
    f.barRGBA = { r, g, b, a }
    local tex = f.fg
    if f.gradient then
        local c2 = f.barColor2 or WHITE
        local o = f.gradientOrientation or "HORIZONTAL"
        tex:SetVertexColor(1, 1, 1, 1)
        local ok = CreateColor and pcall(tex.SetGradient, tex, o, CreateColor(r, g, b, a), CreateColor(c2[1], c2[2], c2[3], c2[4] or 1))
        if not ok and tex.SetGradientAlpha then
            ok = pcall(tex.SetGradientAlpha, tex, o, r, g, b, a, c2[1], c2[2], c2[3], c2[4] or 1)
        end
        if ok then return end
    end
    tex:SetVertexColor(r, g, b, a)
end
Bar.SetColor = BarColorize

-- lays out the icon and the bar inside the region's current size
function Bar.Resize(f, w, h)
    w, h = w or f:GetWidth(), h or f:GetHeight()
    local o = f.orientation or "HORIZONTAL"
    local vertical = Vertical(o)
    f.bar:ClearAllPoints()
    f.icon:ClearAllPoints()
    local size = vertical and w or h
    if f.iconVisible then
        f.icon:SetSize(size, size)
        f.icon:Show()
        local side = f.iconSide or "RIGHT"
        if vertical then
            if side == "LEFT" then
                f.icon:SetPoint("TOP", f, "TOP")
                f.bar:SetPoint("TOPLEFT", f.icon, "BOTTOMLEFT")
                f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
            else
                f.icon:SetPoint("BOTTOM", f, "BOTTOM")
                f.bar:SetPoint("TOPLEFT", f, "TOPLEFT")
                f.bar:SetPoint("BOTTOMRIGHT", f.icon, "TOPRIGHT")
            end
            f.barW, f.barH = w, math.max(0, h - size)
        else
            if side == "LEFT" then
                f.icon:SetPoint("LEFT", f, "LEFT")
                f.bar:SetPoint("TOPLEFT", f.icon, "TOPRIGHT")
                f.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
            else
                f.icon:SetPoint("RIGHT", f, "RIGHT")
                f.bar:SetPoint("TOPLEFT", f, "TOPLEFT")
                f.bar:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMLEFT")
            end
            f.barW, f.barH = math.max(0, w - size), h
        end
        local z = 0.5 * math.max(0, math.min(1, tonumber(f.zoom) or 0)) / 2
        f.icon:SetTexCoord(z, 1 - z, z, 1 - z)
    else
        f.icon:Hide()
        f.bar:SetAllPoints(f)
        f.barW, f.barH = w, h
    end
    f.bar:SetSize(f.barW, f.barH)
    -- the background: a whole bar texture, turned for a vertical bar
    if vertical then f.bg:SetTexCoord(0, 1, 0, 0, 1, 1, 1, 0) else f.bg:SetTexCoord(0, 1, 0, 1) end
    if f.state or f.shownOnce then Bar.Show(f, f.d, f.state, GetTime()) end
end

function Bar.Modify(f, d)
    f.orientation = V(d, "orientation") or "HORIZONTAL"
    f.iconVisible = V(d, "icon") and true or false
    f.iconSide = V(d, "icon_side")
    f.zoom = N(d, "zoom", 0)
    f.barTexture = nil
    f.gradient = V(d, "enableGradient") and true or false
    f.barColor2 = V(d, "barColor2")
    f.gradientOrientation = V(d, "gradientOrientation")
    Base(f, d)
    local tex = BarTexture(f, d)
    R.SetTexture(f.fg, tex)
    R.SetTexture(f.bg, tex)
    f.bg:SetVertexColor(Color(V(d, "backgroundColor"), 0, 0, 0, 0.5))
    f.baseColor = { Color(V(d, "barColor"), 1, 0, 0, 1) }
    ApplyColor(f)
    f.icon:SetDesaturated(V(d, "desaturate") and true or false)
    f.icon:SetVertexColor(Color(V(d, "icon_color")))
    f.sparkOn = V(d, "spark") and true or false
    local sp = f.spark
    if f.sparkOn then
        R.SetTexture(sp, V(d, "sparkTexture"))
        sp:SetVertexColor(Color(V(d, "sparkColor")))
        sp:SetBlendMode(V(d, "sparkBlendMode") or "ADD")
        f.sparkW, f.sparkH = N(d, "sparkWidth", 10), N(d, "sparkHeight", 30)
        f.sparkX, f.sparkY = N(d, "sparkOffsetX", 0), N(d, "sparkOffsetY", 0)
        f.sparkHidden = V(d, "sparkHidden") or "NEVER"
        if V(d, "sparkRotationMode") == "MANUAL" then
            sp:SetTexCoord(R.TurnedCoords(N(d, "sparkRotation", 0), false, d.sparkMirror, false))
        elseif Vertical(f.orientation) then
            sp:SetTexCoord(0, 1, 0, 0, 1, 1, 1, 0)
        else
            sp:SetTexCoord(0, 1, 0, 1)
        end
    else
        sp:Hide()
    end
    Bar.Resize(f, f.width, f.height)
end

-- the fill: the bar texture cut to the filled part, hanging from the
-- side the orientation starts from
function Bar.Show(f, d, st, now)
    local p = R.Fill(f, st, now)
    local o = f.orientation or "HORIZONTAL"
    local bw, bh = f.barW or 0, f.barH or 0
    local fg = f.fg
    fg:ClearAllPoints()
    if p <= 0.0001 then
        fg:Hide()
    else
        fg:Show()
        if o == "HORIZONTAL" then
            fg:SetPoint("TOPLEFT", f.bar, "TOPLEFT") fg:SetPoint("BOTTOMLEFT", f.bar, "BOTTOMLEFT")
            fg:SetWidth(bw * p) fg:SetTexCoord(0, p, 0, 1)
        elseif o == "HORIZONTAL_INVERSE" then
            fg:SetPoint("TOPRIGHT", f.bar, "TOPRIGHT") fg:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT")
            fg:SetWidth(bw * p) fg:SetTexCoord(1 - p, 1, 0, 1)
        elseif o == "VERTICAL" then
            fg:SetPoint("TOPLEFT", f.bar, "TOPLEFT") fg:SetPoint("TOPRIGHT", f.bar, "TOPRIGHT")
            fg:SetHeight(bh * p) fg:SetTexCoord(0, 1, p, 1, 0, 0, p, 0)
        else
            fg:SetPoint("BOTTOMLEFT", f.bar, "BOTTOMLEFT") fg:SetPoint("BOTTOMRIGHT", f.bar, "BOTTOMRIGHT")
            fg:SetHeight(bh * p) fg:SetTexCoord(1 - p, 1, 1, 1, 1 - p, 0, 1, 0)
        end
    end
    if f.sparkOn then
        local sp = f.spark
        local hidden = f.sparkHidden
        local visible = hidden == "NEVER" or (hidden == "FULL" and p < 1) or (hidden == "EMPTY" and p > 0)
            or (hidden == "BOTH" and p > 0 and p < 1)
        sp:ClearAllPoints()
        if Vertical(o) then sp:SetSize(f.sparkH, f.sparkW) else sp:SetSize(f.sparkW, f.sparkH) end
        local x, y = f.sparkX or 0, f.sparkY or 0
        if o == "HORIZONTAL" then sp:SetPoint("CENTER", f.bar, "LEFT", bw * p + x, y)
        elseif o == "HORIZONTAL_INVERSE" then sp:SetPoint("CENTER", f.bar, "RIGHT", -bw * p + x, y)
        elseif o == "VERTICAL" then sp:SetPoint("CENTER", f.bar, "TOP", x, -bh * p + y)
        else sp:SetPoint("CENTER", f.bar, "BOTTOM", x, bh * p + y) end
        sp:SetShown(visible)
    end
    f.fill = p
    if (st and st.additionalProgress) or f.extra then Overlays(f, d, st, p, now) end
end

-- extra stretches on the bar a trigger can hand (state.additionalProgress:
-- incoming heals, a cast's cost, latency...), coloured by d.overlays
local function Overlays(f, d, st, p, now)
    local list = st and type(st.additionalProgress) == "table" and st.additionalProgress or nil
    f.extra = f.extra or {}
    local used = 0
    if list then
        local s = R.SourceState(f, st)
        local total = s and (s.progressType == "timed" and tonumber(s.duration) or tonumber(s.total)) or 0
        local lo, hi = R.Bounds(f.d, total or 0)
        local width = hi - lo
        local inverse = (f.inverse and true or false) ~= (s and s.inverse and true or false)
        local o = f.orientation or "HORIZONTAL"
        local vertical = Vertical(o)
        local len = vertical and (f.barH or 0) or (f.barW or 0)
        for i, ov in ipairs(list) do
            local a, b
            if type(ov) == "table" and ov.min and ov.max and width ~= 0 then
                a, b = (ov.min - lo) / width, (ov.max - lo) / width
                if inverse then a, b = 1 - a, 1 - b end
            elseif type(ov) == "table" and ov.direction and width ~= 0 then
                local fwd = (ov.direction or "forward") == "forward"
                if inverse then fwd = not fwd end
                local w, off = (tonumber(ov.width) or 0) / width, (tonumber(ov.offset) or 0) / width
                if fwd then a, b = p + off, p + off + w else a, b = p - off - w, p - off end
            end
            if a and b then
                if d.overlayclip then a, b = math.max(0, math.min(1, a)), math.max(0, math.min(1, b)) end
                if a > b then a, b = b, a end
                if b - a > 0 then
                    used = used + 1
                    local t = f.extra[used]
                    if not t then
                        t = f.bar:CreateTexture(nil, "ARTWORK", nil, 2)
                        f.extra[used] = t
                    end
                    R.SetTexture(t, (type(d.overlaysTexture) == "table" and d.overlaysTexture[i]) or BarTexture(f, d))
                    t:SetVertexColor(Color(type(d.overlays) == "table" and d.overlays[i] or nil, 1, 1, 1, 0.6))
                    t:ClearAllPoints()
                    local from = ({ HORIZONTAL = "LEFT", HORIZONTAL_INVERSE = "RIGHT", VERTICAL = "TOP", VERTICAL_INVERSE = "BOTTOM" })[o]
                    local sign = (o == "HORIZONTAL_INVERSE" or o == "VERTICAL") and -1 or 1
                    if vertical then
                        t:SetSize(f.barW or 0, len * (b - a))
                        t:SetPoint(sign > 0 and "BOTTOM" or "TOP", f.bar, from, 0, sign * len * a)
                    else
                        t:SetSize(len * (b - a), f.barH or 0)
                        t:SetPoint(sign > 0 and "LEFT" or "RIGHT", f.bar, from, sign * len * a, 0)
                    end
                    t:Show()
                end
            end
        end
    end
    for i = used + 1, #f.extra do f.extra[i]:Hide() end
end

function Bar.SetState(f, d, st)
    if f.iconVisible then R.SetTexture(f.icon, R.IconFor(d, st, f) or "Interface\\Icons\\INV_Misc_QuestionMark") end
    f.shownOnce = true
    Bar.Show(f, d, st, GetTime())
end

function Bar.Tick(f, d, st, now) Bar.Show(f, d, st, now) end

function Bar.SetBarColor2(f, r, g, b, a) f.barColor2 = { r, g, b, a } ApplyColor(f) end
function Bar.SetGradientEnabled(f, v) f.gradient = v and true or false ApplyColor(f) end
function Bar.SetGradientOrientation(f, v) f.gradientOrientation = v ApplyColor(f) end
function Bar.SetBackgroundColor(f, r, g, b, a) f.bg:SetVertexColor(r or 0, g or 0, b or 0, a or 0.5) end
function Bar.SetIconVisible(f, v) f.iconVisible = v and true or false ApplySize(f) end
function Bar.SetIconColor(f, r, g, b, a) f.icon:SetVertexColor(r or 1, g or 1, b or 1, a or 1) end
function Bar.SetIconDesaturated(f, v) f.icon:SetDesaturated(v and true or false) end
function Bar.SetOrientation(f, v) f.orientation = v or "HORIZONTAL" ApplySize(f) end
function Bar.SetSparkColor(f, r, g, b, a) f.spark:SetVertexColor(r or 1, g or 1, b or 1, a or 1) end
function Bar.SetSparkWidth(f, v) f.sparkW = tonumber(v) or f.sparkW Bar.Show(f, f.d, f.state, GetTime()) end
function Bar.SetSparkHeight(f, v) f.sparkH = tonumber(v) or f.sparkH Bar.Show(f, f.d, f.state, GetTime()) end
function Bar.SetStatusBarTextureLSM(f, v)
    f.barTexture = v
    local tex = R.Statusbar(v)
    R.SetTexture(f.fg, tex)
    R.SetTexture(f.bg, tex)
end
function Bar.SetStatusBarTextureInput(f, v)
    if v and v ~= "" then R.SetTexture(f.fg, v) R.SetTexture(f.bg, v) end
end
function Bar.SetStatusBarTextureMode() end

-- ============================================================
-- TEXTURE
-- ============================================================
local Tex = {}
R.types.texture = Tex

function Tex.Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    return f
end

function Tex.SetColor(f, r, g, b, a) f.tex:SetVertexColor(r, g, b, a) end

-- the picture turned (rotation, or an animation's turn), mirrored by the
-- display or by a negative scale
function Tex.Rotate(f)
    local deg = f.animRotation or f.rotation or 0
    local mh = (f.mirror and true or false) ~= ((f.scalex or 1) < 0)
    local mv = (f.scaley or 1) < 0
    f.tex:SetTexCoord(R.TurnedCoords(deg, f.canRotate, mh, mv))
end

function Tex.Resize(f) Tex.Rotate(f) end

function Tex.Modify(f, d)
    f.mirror = V(d, "mirror") and true or false
    f.canRotate = V(d, "rotate") and true or false
    Base(f, d)
    f.wrap = V(d, "textureWrapMode")
    R.SetTexture(f.tex, V(d, "texture"), f.wrap)
    f.baseColor = { Color(V(d, "color")) }
    ApplyColor(f)
    f.tex:SetDesaturated(V(d, "desaturate") and true or false)
    f.tex:SetBlendMode(V(d, "blendMode") or "BLEND")
    Tex.Rotate(f)
end

function Tex.SetState(f, d, st)
    -- a trigger can hand a texture of its own
    if st and st.texture and st.texture ~= "" then R.SetTexture(f.tex, st.texture, f.wrap) end
end

function Tex.SetMirror(f, v) f.mirror = v and true or false Tex.Rotate(f) end
function Tex.SetRotation(f, v) f.rotation = tonumber(v) or 0 Tex.Rotate(f) end
function Tex.SetTexture(f, v) R.SetTexture(f.tex, v, f.wrap) end

-- ============================================================
-- PROGRESS TEXTURE (a texture that fills with the progress)
-- ============================================================
local PT = {}
R.types.progresstexture = PT

local function Circular(o) return o == "CLOCKWISE" or o == "ANTICLOCKWISE" end

function PT.Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.fg = f:CreateTexture(nil, "ARTWORK")
    return f
end

function PT.SetColor(f, r, g, b, a)
    f.fgRGBA = { r, g, b, a }
    f.fg:SetVertexColor(r, g, b, a)
    if f.sweep and f.sweep.SetSwipeColor then pcall(f.sweep.SetSwipeColor, f.sweep, r, g, b, a) end
end

function PT.Resize(f, w, h)
    local off = f.bgOffset or 0
    f.bg:ClearAllPoints()
    f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", -off, off)
    f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", off, -off)
    f.pw, f.ph = w or f:GetWidth(), h or f:GetHeight()
    if f.state or f.shownOnce then PT.Show(f, f.d, f.state, GetTime()) end
end

function PT.Rotate(f) PT.Show(f, f.d, f.state, GetTime()) end

function PT.Modify(f, d)
    f.orientation = V(d, "orientation") or "VERTICAL"
    f.mirror = V(d, "mirror") and true or false
    f.bgOffset = N(d, "backgroundOffset", 0)
    Base(f, d)
    local fgTex = V(d, "foregroundTexture") or d.texture
    R.SetTexture(f.fg, fgTex)
    R.SetTexture(f.bg, V(d, "sameTexture") and fgTex or V(d, "backgroundTexture"))
    f.bg:SetVertexColor(Color(V(d, "backgroundColor"), 0.5, 0.5, 0.5, 0.5))
    f.fg:SetDesaturated(V(d, "desaturateForeground") and true or false)
    f.bg:SetDesaturated(V(d, "desaturateBackground") and true or false)
    f.fg:SetBlendMode(V(d, "blendMode") or "BLEND")
    f.bg:SetBlendMode(V(d, "blendMode") or "BLEND")
    -- a circular fill is drawn as a cooldown sweep of the fill texture
    if Circular(f.orientation) then
        if not f.sweep then
            f.sweep = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
            f.sweep:SetAllPoints(f)
            if f.sweep.SetDrawBling then f.sweep:SetDrawBling(false) end
            if f.sweep.SetDrawEdge then f.sweep:SetDrawEdge(false) end
            if f.sweep.SetHideCountdownNumbers then f.sweep:SetHideCountdownNumbers(true) end
        end
        if f.sweep.SetSwipeTexture then pcall(f.sweep.SetSwipeTexture, f.sweep, tonumber(fgTex) or fgTex) end
        f.fg:Hide()
    elseif f.sweep then
        f.sweep:Hide()
    end
    f.baseColor = { Color(V(d, "foregroundColor")) }
    ApplyColor(f)
    PT.Resize(f, f.width, f.height)
end

function PT.Show(f, d, st, now)
    local p = R.Fill(f, st, now)
    local o = f.orientation or "VERTICAL"
    if Circular(o) then
        local sw = f.sweep
        if not sw then return end
        if p <= 0.0001 then sw:Hide() return end
        sw:Show()
        -- reverse: the swept part is the elapsed one, from twelve o'clock
        local clockwise = o == "CLOCKWISE"
        if f.mirror then clockwise = not clockwise end
        if sw.SetReverse then sw:SetReverse(clockwise) end
        local shown = clockwise and p or (1 - p)
        pcall(sw.SetCooldown, sw, now - shown * 100, 100)
        pcall(sw.Pause, sw)
        f.fill = p
        return
    end
    local w, h = f.pw or f.width or 1, f.ph or f.height or 1
    local fg = f.fg
    fg:ClearAllPoints()
    if p <= 0.0001 then fg:Hide() f.fill = p return end
    fg:Show()
    local l, r = 0, 1
    if f.mirror then l, r = 1, 0 end
    if o == "HORIZONTAL" then
        fg:SetPoint("TOPLEFT", f, "TOPLEFT") fg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
        fg:SetWidth(w * p) fg:SetTexCoord(l, l + (r - l) * p, 0, 1)
    elseif o == "HORIZONTAL_INVERSE" then
        fg:SetPoint("TOPRIGHT", f, "TOPRIGHT") fg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
        fg:SetWidth(w * p) fg:SetTexCoord(r - (r - l) * p, r, 0, 1)
    elseif o == "VERTICAL_INVERSE" then
        fg:SetPoint("TOPLEFT", f, "TOPLEFT") fg:SetPoint("TOPRIGHT", f, "TOPRIGHT")
        fg:SetHeight(h * p) fg:SetTexCoord(l, r, 0, p)
    else
        fg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT") fg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
        fg:SetHeight(h * p) fg:SetTexCoord(l, r, 1 - p, 1)
    end
    f.fill = p
end

function PT.SetState(f, d, st) f.shownOnce = true PT.Show(f, d, st, GetTime()) end
function PT.Tick(f, d, st, now) PT.Show(f, d, st, now) end
function PT.SetBackgroundColor(f, r, g, b, a) f.bg:SetVertexColor(r or 0.5, g or 0.5, b or 0.5, a or 0.5) end
function PT.SetForegroundDesaturated(f, v) f.fg:SetDesaturated(v and true or false) end
function PT.SetBackgroundDesaturated(f, v) f.bg:SetDesaturated(v and true or false) end
function PT.SetMirror(f, v) f.mirror = v and true or false PT.Show(f, f.d, f.state, GetTime()) end
function PT.SetOrientation(f, v)
    f.orientation = v
    f.d = setmetatable({ orientation = v }, { __index = f.baseD or f.d })
    PT.Modify(f, f.d)
end
function PT.SetTexRotation(f, v) f.rotation = tonumber(v) or 0 end
function PT.SetAuraRotation(f, v) f.auraRotation = tonumber(v) or 0 end
function PT.SetCropX(f, v) f.cropX = tonumber(v) end
function PT.SetCropY(f, v) f.cropY = tonumber(v) end

-- ============================================================
-- STOP MOTION (a flip-book texture: frames in a grid or numbered files)
-- ============================================================
local SM = {}
R.types.stopmotion = SM

-- the example flip book every install has
R.flipBooks = { [(MEDIA .. "Media\\Textures\\stopmotion"):lower()] = { count = 64, rows = 8, columns = 8 } }

-- what a flip-book file holds: rows, columns, frames (from the name, the
-- known list, or the display's own numbers)
function R.FlipBook(path, d, prefix)
    path = type(path) == "string" and path or tostring(path or "")
    local known = R.flipBooks[path:lower()]
    if known then
        return { rows = known.rows, columns = known.columns, frames = known.count, scaleW = 1, scaleH = 1 }
    end
    local rows, cols, frames = path:lower():match("%.x(%d+)y(%d+)f(%d+)%.[tb][gl][ap]")
    if rows then
        return { rows = tonumber(rows), columns = tonumber(cols), frames = tonumber(frames), scaleW = 1, scaleH = 1 }
    end
    local r2, c2, f2, fw, fh, W, H = path:match("%.x(%d+)y(%d+)f(%d+)w(%d+)h(%d+)W(%d+)H(%d+)%.[tb][gl][ap]")
    if r2 then
        r2, c2, fw, fh, W, H = tonumber(r2), tonumber(c2), tonumber(fw), tonumber(fh), tonumber(W), tonumber(H)
        return { rows = r2, columns = c2, frames = tonumber(f2),
            scaleW = (W > 0 and fw > 0) and (fw * c2 / W) or 1, scaleH = (H > 0 and fh > 0) and (fh * r2 / H) or 1 }
    end
    prefix = prefix or "customForeground"
    local cr, cc = tonumber(d[prefix .. "Rows"]), tonumber(d[prefix .. "Columns"])
    local cf = tonumber(d[prefix .. "Frames"]) or 0
    if cf <= 0 then cf = 256 end
    local fw2, fh2 = tonumber(d[prefix .. "FrameWidth"]) or 0, tonumber(d[prefix .. "FrameHeight"]) or 0
    local W2, H2 = tonumber(d[prefix .. "FileWidth"]) or 0, tonumber(d[prefix .. "FileHeight"]) or 0
    return { rows = cr, columns = cc, frames = cf,
        scaleW = (cr and cc and W2 > 0 and fw2 > 0) and (fw2 * cc / W2) or 1,
        scaleH = (cr and cc and H2 > 0 and fh2 > 0) and (fh2 * cr / H2) or 1 }
end

-- one frame of a flip book onto a texture
function R.FlipTo(tex, book, path, frame)
    if book.rows and book.columns and book.rows > 0 and book.columns > 0 then
        local i = frame - 1
        local row, col = floor(i / book.columns), i % book.columns
        local dx, dy = (book.scaleW or 1) / book.columns, (book.scaleH or 1) / book.rows
        tex:SetTexCoord(dx * col, dx * col + dx, dy * row, dy * row + dy)
    else
        tex:SetTexture(tostring(path) .. string.format("%03d", frame))
    end
end

-- which frame to show: by time (loop / bounce / once) or by progress
function R.FlipFrame(book, opts, elapsed, progress)
    local last = math.max(0, (book.frames or 1) - 1)
    local first = floor((opts.startPercent or 0) * last) + 1
    local final = floor((opts.endPercent or 1) * last) + 1
    local inverse = opts.inverse and true or false
    if final < first then first, final, inverse = final, first, not inverse end
    local count = final - first + 1
    local frame
    if progress then
        frame = floor((count - 1) * progress) + first
    else
        local n = floor(elapsed * (opts.frameRate or 15))
        local kind = opts.animationType
        if kind == "bounce" then
            if floor(n / count) % 2 == 0 then frame = n % count + first else frame = final - n % count end
        elseif kind == "once" then
            frame = math.min(final, n + first)
        else
            frame = n % count + first
        end
    end
    if inverse then frame = final - frame + first end
    return math.max(first, math.min(final, frame))
end

function SM.Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.fg = f:CreateTexture(nil, "ARTWORK")
    f.fg:SetAllPoints()
    return f
end

function SM.SetColor(f, r, g, b, a) f.fg:SetVertexColor(r, g, b, a) end

local function SMStep(f, now)
    if not f.book then return end
    local opts = f.flipOpts
    local frame
    if opts.animationType == "progress" then
        frame = R.FlipFrame(f.book, opts, 0, (R.Fill(f, f.state, now)))
    else
        frame = R.FlipFrame(f.book, opts, now - (f.startTime or now), nil)
    end
    if frame ~= f.frameNow then
        f.frameNow = frame
        R.FlipTo(f.fg, f.book, f.fgPath, frame)
    end
end

function SM.Modify(f, d)
    Base(f, d)
    f.fgPath = V(d, "foregroundTexture")
    f.book = R.FlipBook(f.fgPath, d, "customForeground")
    f.flipOpts = { startPercent = N(d, "startPercent", 0), endPercent = N(d, "endPercent", 1),
        frameRate = N(d, "frameRate", 15), animationType = V(d, "animationType"), inverse = V(d, "inverse") }
    R.SetTexture(f.fg, f.book.rows and f.fgPath or (tostring(f.fgPath) .. "000"))
    f.fg:SetBlendMode(V(d, "blendMode") or "BLEND")
    f.fg:SetDesaturated(V(d, "desaturateForeground") and true or false)
    f.baseColor = { Color(V(d, "foregroundColor")) }
    ApplyColor(f)
    -- the background: the same book (or its own), one fixed frame
    local hideBg = V(d, "hideBackground")
    if hideBg then
        f.bg:Hide()
    else
        f.bg:Show()
        local bgPath = V(d, "sameTexture") and f.fgPath or V(d, "backgroundTexture")
        local bgBook = R.FlipBook(bgPath, d, "customBackground")
        R.SetTexture(f.bg, bgBook.rows and bgPath or (tostring(bgPath) .. "000"))
        local last = math.max(0, (bgBook.frames or 1) - 1)
        R.FlipTo(f.bg, bgBook, bgPath, floor(N(d, "backgroundPercent", 1) * last) + 1)
        f.bg:SetVertexColor(Color(V(d, "backgroundColor"), 0.5, 0.5, 0.5, 0.5))
        f.bg:SetDesaturated(V(d, "desaturateBackground") and true or false)
        f.bg:SetBlendMode(V(d, "blendMode") or "BLEND")
    end
    f.frameNow = nil
    -- it animates by itself while it is shown
    f:SetScript("OnUpdate", function(self) SMStep(self, GetTime()) end)
end

function SM.SetState(f, d, st)
    if not f.startTime or not f:IsShown() then f.startTime = GetTime() end
    SMStep(f, GetTime())
end
function SM.Tick(f, d, st, now) SMStep(f, now) end
function SM.SetBackgroundColor(f, r, g, b, a) f.bg:SetVertexColor(r or 0.5, g or 0.5, b or 0.5, a or 0.5) end
function SM.SetForegroundDesaturated(f, v) f.fg:SetDesaturated(v and true or false) end
function SM.SetBackgroundDesaturated(f, v) f.bg:SetDesaturated(v and true or false) end

-- ============================================================
-- MODEL (a 3D model: a file id, a unit, or a creature display id)
-- ============================================================
local Model = {}
R.types.model = Model

function Model.Create(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.border = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    return f
end

local function LoadModel(m, d)
    local id = d.model_fileId
    if d.modelDisplayInfo then pcall(m.SetDisplayInfo, m, tonumber(id))
    elseif d.modelIsUnit then pcall(m.SetUnit, m, id)
    else pcall(m.SetModel, m, tonumber(id) or id) end
end
R.LoadModel = LoadModel

-- position and turn, by either of the two ways the format stores them
function R.PoseModel(m, d, rotation)
    if m.ClearTransform then pcall(m.ClearTransform, m) end
    if d.api and m.SetTransform then
        if m.MakeCurrentCameraCustom then pcall(m.MakeCurrentCameraCustom, m) end
        local t = function(k, def) return (tonumber(d[k]) or def or 0) end
        if CreateVector3D then
            pcall(m.SetTransform, m, CreateVector3D(t("model_st_tx") / 1000, t("model_st_ty") / 1000, t("model_st_tz") / 1000),
                CreateVector3D(math.rad(t("model_st_rx")), math.rad(t("model_st_ry")), math.rad(rotation or t("model_st_rz"))),
                -t("model_st_us", 40) / 1000)
        else
            pcall(m.SetTransform, m, t("model_st_tx") / 1000, t("model_st_ty") / 1000, t("model_st_tz") / 1000,
                math.rad(t("model_st_rx")), math.rad(t("model_st_ry")), math.rad(rotation or t("model_st_rz")), t("model_st_us", 40) / 1000)
        end
    else
        pcall(m.SetPosition, m, tonumber(d.model_z) or 0, tonumber(d.model_x) or 0, tonumber(d.model_y) or 0)
        pcall(m.SetFacing, m, math.rad(tonumber(rotation) or 0))
    end
end

function Model.Modify(f, d)
    Base(f, d)
    if not f.model then
        f.model = CreateFrame("PlayerModel", nil, f)
    end
    local m = f.model
    m:ClearAllPoints()
    m:SetAllPoints(f)
    if m.SetKeepModelOnHide then pcall(m.SetKeepModelOnHide, m, true) end
    LoadModel(m, d)
    if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, d.portraitZoom and 1 or 0) end
    R.PoseModel(m, d, N(d, "rotation", 0))
    pcall(m.SetAnimation, m, d.advance and (tonumber(d.sequence) or 0) or 0)
    -- a unit model follows the unit
    m:UnregisterAllEvents()
    m:SetScript("OnEvent", nil)
    if d.modelIsUnit then
        pcall(m.RegisterEvent, m, "UNIT_MODEL_CHANGED")
        if d.model_fileId == "target" then pcall(m.RegisterEvent, m, "PLAYER_TARGET_CHANGED") end
        m:SetScript("OnEvent", function(self, event, unit)
            if event ~= "UNIT_MODEL_CHANGED" or (unit and UnitIsUnit(unit, d.model_fileId)) then
                LoadModel(self, d)
                pcall(self.SetAnimation, self, d.advance and (tonumber(d.sequence) or 0) or 0)
            end
        end)
    end
    local b = f.border
    if V(d, "border") and b.SetBackdrop then
        local off = N(d, "borderOffset", 5)
        local inset = N(d, "borderInset", 11)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -off, -off)
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", off, off)
        b:SetBackdrop({ edgeFile = R.Border(V(d, "borderEdge")), edgeSize = N(d, "borderSize", 16),
            bgFile = R.Background(V(d, "borderBackdrop")), insets = { left = inset, right = inset, top = inset, bottom = inset } })
        b:SetBackdropBorderColor(Color(V(d, "borderColor")))
        b:SetBackdropColor(Color(V(d, "backdropColor")))
        b:Show()
    else
        b:Hide()
    end
end

function Model.SetState(f, d, st) if f.model then f.model:Show() end end

-- ============================================================
-- EMPTY (a display that only runs code or sends a message)
-- ============================================================
local Empty = {}
R.types.empty = Empty
function Empty.Create(parent) return CreateFrame("Frame", nil, parent) end
function Empty.Modify(f, d) Base(f, d) end
function Empty.SetState() end

-- ============================================================
-- BUILDING ONE
-- ============================================================
-- a region answers its type's own setters too (SetIcon on an icon, ...)
local function Bind(f, kind)
    for k, fn in pairs(Methods) do f[k] = fn end
    for k, fn in pairs(kind) do
        if type(fn) == "function" and (k:match("^Set") or k == "ChangeText") then
            f[k] = fn
        end
    end
    -- the common colour setter goes through base/animation colour
    f.Color, f.ColorAnim, f.GetColor = Methods.Color, Methods.ColorAnim, Methods.GetColor
    f.SetRegionAlpha, f.SetAnimAlpha = Methods.SetRegionAlpha, Methods.SetAnimAlpha
    f.SetRegionWidth, f.SetRegionHeight = Methods.SetRegionWidth, Methods.SetRegionHeight
    f.SetInverse, f.SetIcon, f.SetIconSource = Methods.SetInverse, Methods.SetIcon, Methods.SetIconSource
    f.SetProgressSource, f.SetAdjustedMin, f.SetAdjustedMax = Methods.SetProgressSource, Methods.SetAdjustedMin, Methods.SetAdjustedMax
    f.SetXOffsetRelative, f.SetYOffsetRelative = Methods.SetXOffsetRelative, Methods.SetYOffsetRelative
    if f.regionType == "aurabar" then f.SetDesaturated = Bar.SetIconDesaturated end
    f.SetState, f.SetColor = nil, nil
end

function R.New(id, cloneId)
    local d = E.data[id]
    if not d then return nil end
    local kind = R.types[d.regionType]
    if not kind then return nil end
    local f = kind.Create(UIParent)
    f.id, f.cloneId, f.d, f.baseD, f.kind = id, cloneId or "", d, d, kind
    f.regionType = d.regionType
    f.relX, f.relY, f.animX, f.animY = 0, 0, 0, 0
    Bind(f, kind)
    f:Hide()
    kind.Modify(f, d)
    if d.anchorFrameType == "CUSTOM" and type(d.customAnchor) == "string" and E.Env then
        f.customAnchor = E.Env.Function(id, d.customAnchor, "custom anchor")
    end
    if E.SubRegions then E.SubRegions.Build(f, d) end
    return f
end

-- one state onto a region: its own look, its texts, its timer
function R.Apply(f, st)
    f.state = st
    local d = f.d
    if f.kind.SetState then f.kind.SetState(f, d, st) end
    if f.regionType == "text" then
        local txt = E.Text.Format(f.textOverride or d.displayText or "", d, "displayText", f.ctx or { state = st })
        f.text:SetText(txt)
        Text.Fit(f)
    end
    if E.SubRegions then E.SubRegions.Apply(f, st) end
end

-- per frame while a timer runs on it
function R.Tick(f, now)
    local d, st = f.d, f.state
    if f.kind.Tick then f.kind.Tick(f, d, st, now) end
    if f.regionType == "text" and f.timedText then
        f.text:SetText(E.Text.Format(f.textOverride or d.displayText or "", d, "displayText", f.ctx or { state = st }))
        Text.Fit(f)
    end
    if E.SubRegions then E.SubRegions.Tick(f, now) end
    if f.followMouse then R.Place(f, f.baseD or d, st) end
end
