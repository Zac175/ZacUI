-- AE_Options - what the aura editor shows for one display: option tables
-- (the AceConfig shape ZacUI's Config_AceRender draws) built over the
-- display's own saved table.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- Every `set` writes the saved field and asks for a rebuild of that
-- display (E.Rebuild, coalesced to once a frame), so what is on screen
-- follows the form. The editor only ever writes the WeakAuras format's
-- own field names and values (the lists below are that format's, for
-- Classic Era), so whatever is built here imports into WeakAuras and
-- behaves the same there. Builders, one per editor tab:
--   O.Display(d)   size, place, look, per display type
--   O.Text(d)      what hangs on it: texts, borders, glows, ticks, textures,
--                  models, flip books (and a text display's own text)
--   O.Triggers(d)  each trigger, by type
--   O.Conditions(d), O.Actions(d), O.Animations(d), O.Load(d)
--   O.Config(d)    the custom options its author gave it
--   O.Group(d)     a group's layout
-- O.W holds the small control makers, for other editor files.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local O = {}
E.Options = O

-- ============================================================
-- BINDINGS
-- ============================================================
local function Path(t, path, create)
    local cur = t
    for i = 1, #path - 1 do
        local k = path[i]
        if type(cur[k]) ~= "table" then
            if not create then return nil, nil end
            cur[k] = {}
        end
        cur = cur[k]
    end
    return cur, path[#path]
end

local function Changed(d)
    if E.Rebuild then E.Rebuild(d.id) end
end
O.Changed = Changed

-- get/set bound to a field of `root` (a display, a sub-element, a
-- trigger...), `path` a key or a list of keys
local function Bind(d, root, path, conv)
    if type(path) ~= "table" then path = { path } end
    local get = function()
        local t, k = Path(root, path, false)
        if not t then return nil end
        local v = t[k]
        if conv and conv.get then return conv.get(v) end
        return v
    end
    local set = function(_, v)
        if conv and conv.set then v = conv.set(v) end
        local t, k = Path(root, path, true)
        t[k] = v
        Changed(d)
    end
    return get, set
end

local order = 0
local function N() order = order + 1 return order end

local function Extra(o, extra)
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end

local function Toggle(d, root, path, name, extra)
    local get, set = Bind(d, root, path)
    return Extra({ type = "toggle", name = name, order = N(), get = get, set = set }, extra)
end

local function Range(d, root, path, name, min, max, step, extra)
    local get, set = Bind(d, root, path, { get = function(v) return tonumber(v) end })
    return Extra({ type = "range", name = name, order = N(), min = min, max = max, step = step or 1, get = get, set = set }, extra)
end

local function Input(d, root, path, name, extra)
    local get, set = Bind(d, root, path, { get = function(v) return v ~= nil and tostring(v) or "" end })
    return Extra({ type = "input", name = name, order = N(), get = get, set = set }, extra)
end

local function NumInput(d, root, path, name, extra)
    local get, set = Bind(d, root, path, { get = function(v) return v ~= nil and tostring(v) or "" end,
        set = function(v) return tonumber(v) or 0 end })
    return Extra({ type = "input", name = name, order = N(), get = get, set = set }, extra)
end

-- a text field that keeps a number when one is typed (file ids, spell ids)
local function IdInput(d, root, path, name, extra)
    local get, set = Bind(d, root, path, { get = function(v) return v ~= nil and tostring(v) or "" end,
        set = function(v) if v == "" then return nil end return tonumber(v) or v end })
    return Extra({ type = "input", name = name, order = N(), get = get, set = set }, extra)
end

local function Select(d, root, path, name, values, extra)
    local get, set = Bind(d, root, path)
    return Extra({ type = "select", name = name, order = N(), values = values, get = get, set = set }, extra)
end

local function ColorOpt(d, root, path, name, extra)
    if type(path) ~= "table" then path = { path } end
    local o = { type = "color", name = name, order = N(), hasAlpha = true,
        get = function()
            local t, k = Path(root, path, false)
            local c = t and t[k]
            return E.Color(c)
        end,
        set = function(_, r, g, b, a)
            local t, k = Path(root, path, true)
            t[k] = { r, g, b, a or 1 }
            Changed(d)
        end }
    return Extra(o, extra)
end

local function Code(d, root, path, name, lines)
    return Input(d, root, path, name, { multiline = lines or 10, width = "full" })
end

local function Header(name) return { type = "header", name = name, order = N() } end
local function Desc(text) return { type = "description", name = text, order = N() } end
local ONE_FONT_NOTE = (ns.UI and ns.UI.ONE_FONT_NOTE) or "Uses ZacUI's font (Fonts & Textures)"
local function Button(name, func, extra) return Extra({ type = "execute", name = name, order = N(), func = func }, extra) end
local function Group(args, hidden) return { type = "group", inline = true, order = N(), args = args, hidden = hidden } end

O.W = { Bind = Bind, Toggle = Toggle, Range = Range, Input = Input, NumInput = NumInput, IdInput = IdInput,
    Select = Select, Color = ColorOpt, Code = Code, Header = Header, Desc = Desc, Button = Button, Group = Group,
    Order = N, ResetOrder = function() order = 0 end }

-- ============================================================
-- VALUE LISTS (the WeakAuras format's values, ZacUI's labels)
-- ============================================================
local POINTS = { CENTER = "Centre", TOP = "Top", BOTTOM = "Bottom", LEFT = "Left", RIGHT = "Right",
    TOPLEFT = "Top left", TOPRIGHT = "Top right", BOTTOMLEFT = "Bottom left", BOTTOMRIGHT = "Bottom right" }
local ANCHORS = { SCREEN = "Screen / parent group", UIPARENT = "Screen", MOUSE = "The mouse", SELECTFRAME = "A named frame",
    NAMEPLATE = "The unit's nameplate", UNITFRAME = "The unit's raid frame", CUSTOM = "Custom code" }
local GROUP_ANCHORS = { SCREEN = "Screen / parent group", UIPARENT = "Screen", MOUSE = "The mouse",
    SELECTFRAME = "A named frame", CUSTOM = "Custom code" }
local STRATA = { [1] = "Inherited", [2] = "Background", [3] = "Low", [4] = "Medium", [5] = "High",
    [6] = "Dialog", [7] = "Fullscreen", [8] = "Fullscreen dialog", [9] = "Tooltip" }
local OUTLINES = { None = "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline", MONOCHROME = "Monochrome",
    ["MONOCHROME|OUTLINE"] = "Monochrome outline", ["MONOCHROME|THICKOUTLINE"] = "Monochrome thick outline" }
local JUSTIFY = { LEFT = "Left", CENTER = "Centre", RIGHT = "Right" }
-- (the names say which way a timer empties)
local ORIENT = { HORIZONTAL = "Right to left", HORIZONTAL_INVERSE = "Left to right", VERTICAL = "Bottom to top",
    VERTICAL_INVERSE = "Top to bottom" }
local ORIENT_CIRCLE = { HORIZONTAL = "Right to left", HORIZONTAL_INVERSE = "Left to right", VERTICAL = "Bottom to top",
    VERTICAL_INVERSE = "Top to bottom", CLOCKWISE = "Clockwise", ANTICLOCKWISE = "Anticlockwise" }
local BLEND = { BLEND = "Normal", ADD = "Add (glow)" }
local WRAP = { CLAMP = "Clamp", CLAMPTOBLACKADDITIVE = "No extend", MIRROR = "Mirror", REPEAT = "Repeat" }
local AUTOWIDTH = { Auto = "Fits the text", Fixed = "Fixed" }
local WORDWRAP = { WordWrap = "Wrap", Elide = "Cut off" }
local SLANT = { INSIDE = "Keep inside", EXTEND = "Extend outside" }
local SPARK_ROTATION = { AUTO = "Turn with the bar", MANUAL = "My own angle" }
local SPARK_HIDE = { NEVER = "Never", FULL = "When full", EMPTY = "When empty", BOTH = "When full or empty" }
local GRADIENT = { HORIZONTAL = "Across", VERTICAL = "Up and down" }
local TEXTURE_SOURCE = { LSM = "Shared media list", Picker = "Path or file id" }
local STOPMOTION_ANIM = { loop = "Loop", bounce = "Forward, then back", once = "Forward once", progress = "Follow the progress" }
local GLOWS = { buttonOverlay = "Action button glow", Pixel = "Pixel lines", ACShine = "Autocast shine" }
local GLOW_FRAMES = { UNITFRAME = "The unit's raid frame", NAMEPLATE = "The unit's nameplate",
    FRAMESELECTOR = "A named frame", PARENTFRAME = "The frame it hangs on" }
local GLOW_ACTIONS = { show = "Show", hide = "Hide" }
local TICK_MODES = { AtValue = "At a value", AtMissingValue = "At a value missing", AtPercent = "At a percent",
    ValueOffset = "Offset from the progress" }
local ROTATE_TEXT = { NONE = "None", LEFT = "Left", RIGHT = "Right" }
local ANCHOR_MODE = { area = "Fill an area", point = "Attach to a point" }
local SOUND_CHANNELS = { Master = "Master", SFX = "Sound effects", Ambience = "Ambience", Music = "Music", Dialog = "Dialog" }
local MESSAGE_TYPES = { WHISPER = "Whisper", SAY = "Say", EMOTE = "Emote", YELL = "Yell", PARTY = "Party", GUILD = "Guild",
    OFFICER = "Officer", RAID = "Raid", SMARTRAID = "Battleground > raid > party > say", RAID_WARNING = "Raid warning",
    INSTANCE_CHAT = "Instance", COMBAT = "Scrolling combat text", PRINT = "Your chat window", ERROR = "Error text",
    TTS = "Read it out" }
local SOUND_KINDS = { Play = "Play", Loop = "Loop", Stop = "Stop" }
local OPERATORS = { ["=="] = "=", ["~="] = "not", ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=" }
local STRING_OPS = { ["=="] = "is exactly", ["find('%s')"] = "contains", ["match('%s')"] = "matches (pattern)" }
O.POINTS, O.STRATA = POINTS, STRATA
O.VALUES = { POINTS = POINTS, ANCHORS = ANCHORS, GROUP_ANCHORS = GROUP_ANCHORS, STRATA = STRATA, OUTLINES = OUTLINES,
    JUSTIFY = JUSTIFY, ORIENT = ORIENT, ORIENT_CIRCLE = ORIENT_CIRCLE, BLEND = BLEND, WRAP = WRAP, GLOWS = GLOWS,
    TICK_MODES = TICK_MODES, MESSAGE_TYPES = MESSAGE_TYPES, OPERATORS = OPERATORS, STRING_OPS = STRING_OPS }

local function Media(kind, extra)
    return function()
        local out = {}
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local ok, list = pcall(LSM.List, LSM, kind)
            if ok and type(list) == "table" then for _, n in ipairs(list) do out[n] = n end end
        end
        for k, v in pairs(extra or {}) do out[k] = v end
        return out
    end
end

-- the trigger numbers of a display ("Trigger 1"...), for icon sources etc.
local function TriggerChoices(d, base)
    local out = {}
    for k, v in pairs(base or {}) do out[k] = v end
    for i = 1, (E.TriggerCount and E.TriggerCount(d) or 0) do out[i] = "Trigger " .. i end
    return out
end

-- ============================================================
-- TEXT FORMATS (the %codes' options, for any text)
-- ============================================================
local FORMAT_KINDS = { none = "As it is", string = "Text", timed = "Time", Number = "Number", BigNumber = "Big number",
    Money = "Money", Unit = "Unit name", guid = "Name from a GUID", GCDTime = "In global cooldowns" }
local TIME_FORMATS = { [0] = "63:42  3:07  10  2.4", [1] = "2h  3m  10s  2.4", [2] = "1h 3m  3m 7s  10s  2.4" }
local TIME_PRECISION = { [1] = "12.3", [2] = "12.34", [3] = "12.345" }
local PRECISION = { [0] = "12", [1] = "12.3", [2] = "12.34", [3] = "12.345" }
local ROUND = { floor = "Down", ceil = "Up", round = "Nearest" }
local PAD = { left = "Left", right = "Right" }
local BIG = { AbbreviateNumbers = "Short (12.3K)", AbbreviateLargeNumbers = "Short, rounded", BreakUpLargeNumbers = "12,345" }
local BIG_OFF = { AbbreviateNumbers = "Short (12.3K)", AbbreviateLargeNumbers = "Short, rounded",
    BreakUpLargeNumbers = "12,345", disable = "Off" }
local COIN = { [1] = "Gold", [2] = "Gold and silver", [3] = "Gold, silver and copper" }
local UNIT_COLOR = { none = "None", class = "Class colour" }
local REALM = { never = "Never", star = "A * after the name", differentServer = "When not mine", always = "Always" }
O.FORMAT_KINDS = FORMAT_KINDS

-- the %codes a text uses ("p", "1.p", "unit", "c2"...)
function O.Symbols(text)
    local out, seen = {}, {}
    if type(text) ~= "string" then return out end
    local function Add(s)
        if s ~= "" and not seen[s] then
            seen[s] = true
            out[#out + 1] = s
        end
    end
    local plain = text:gsub("%%%%", "")
    for inner in plain:gmatch("%%(%b{})") do Add(inner:sub(2, -2)) end
    plain = plain:gsub("%%%b{}", "")
    for trig, sym in plain:gmatch("%%(%d*)%.?([%a_][%w_]*)") do
        Add(trig ~= "" and (trig .. "." .. sym) or sym)
    end
    return out
end

-- every option of one %code's format; prefix "displayText", "text_text"
-- or "message"
local function FormatArgs(d, owner, prefix, text, args, keyBase)
    for i, sym in ipairs(O.Symbols(text)) do
        local base = prefix .. "_format_" .. sym .. "_"
        local kind = function()
            local k = owner[base .. "format"]
            if k == nil then
                local s = sym:match("([%a_][%w_]*)$")
                if s == "p" or s == "t" then return "timed" end
                return "none"
            end
            return k
        end
        local kb = keyBase .. "f" .. i
        local g = {}
        g.k = Select(d, owner, base .. "format", "%" .. sym .. " shows as", FORMAT_KINDS,
            { get = function() return kind() end })
        local function When(...)
            local set = {}
            for _, v in ipairs({ ... }) do set[v] = true end
            return function() return not set[kind()] end
        end
        g.tf = Select(d, owner, base .. "time_format", "  format", TIME_FORMATS, { hidden = When("timed") })
        g.tt = Range(d, owner, base .. "time_dynamic_threshold", "  decimals below (seconds)", 0, 60, 1, { hidden = When("timed") })
        g.tp = Select(d, owner, base .. "time_precision", "  decimals", TIME_PRECISION, { hidden = When("timed") })
        g.tm = Toggle(d, owner, base .. "time_mod_rate", "  follow the game's cooldown rate", { hidden = When("timed") })
        g.tl = Toggle(d, owner, base .. "time_legacy_floor", "  round seconds down (old way)", { hidden = When("timed") })
        g.dp = Select(d, owner, base .. "decimal_precision", "  decimals", PRECISION, { hidden = When("Number", "GCDTime") })
        g.rt = Select(d, owner, base .. "round_type", "  round", ROUND, { hidden = When("Number", "GCDTime") })
        g.bn = Select(d, owner, base .. "big_number_format", "  style", BIG, { hidden = When("BigNumber") })
        g.mf = Select(d, owner, base .. "money_format", "  gold as", BIG_OFF, { hidden = When("Money") })
        g.mp = Select(d, owner, base .. "money_precision", "  coins", COIN, { hidden = When("Money") })
        g.uc = Select(d, owner, base .. "color", "  colour", UNIT_COLOR, { hidden = When("Unit", "guid") })
        g.ur = Select(d, owner, base .. "realm_name", "  realm", REALM, { hidden = When("Unit", "guid") })
        g.ab = Toggle(d, owner, base .. "abbreviate", "  shorten", { hidden = When("string", "Unit", "guid") })
        g.am = Range(d, owner, base .. "abbreviate_max", "    to letters", 1, 20, 1, { hidden = When("string", "Unit", "guid") })
        g.pd = Toggle(d, owner, base .. "pad", "  pad", { hidden = When("string", "Number", "BigNumber", "Unit", "guid") })
        g.pm = Select(d, owner, base .. "pad_mode", "    side", PAD, { hidden = When("string", "Number", "BigNumber", "Unit", "guid") })
        g.px = Range(d, owner, base .. "pad_max", "    to letters", 1, 20, 1, { hidden = When("string", "Number", "BigNumber", "Unit", "guid") })
        g.gg = Toggle(d, owner, base .. "gcd_gcd", "  count the global cooldown", { hidden = When("GCDTime") })
        g.gc = Toggle(d, owner, base .. "gcd_cast", "  count casts", { hidden = When("GCDTime") })
        g.gh = Toggle(d, owner, base .. "gcd_channel", "  count channels", { hidden = When("GCDTime") })
        g.gz = Toggle(d, owner, base .. "gcd_hide_zero", "  hide at zero", { hidden = When("GCDTime") })
        args[kb] = Group(g)
    end
end
O.FormatArgs = FormatArgs

-- ============================================================
-- DISPLAY
-- ============================================================
local function InDynamic(d)
    return d.parent and E.data[d.parent] and E.data[d.parent].regionType == "dynamicgroup"
end

local function Place(d, args)
    args.placeHeader = Header("Position")
    if not InDynamic(d) then
        local anchors = E.IsGroup(d) and GROUP_ANCHORS or ANCHORS
        args.anchorFrameType = Select(d, d, "anchorFrameType", "Attached to", anchors)
        args.anchorFrameFrame = Input(d, d, "anchorFrameFrame", "  frame name (or WeakAuras:<display>)",
            { hidden = function() return d.anchorFrameType ~= "SELECTFRAME" end })
        args.customAnchor = Code(d, d, "customAnchor", "  code (returns a frame)", 5)
        args.customAnchor.hidden = function() return d.anchorFrameType ~= "CUSTOM" end
        args.anchorFrameParent = Toggle(d, d, "anchorFrameParent", "  move with that frame (parent to it)",
            { hidden = function() local t = d.anchorFrameType or "SCREEN" return t == "SCREEN" or t == "UIPARENT" end,
              get = function() return d.anchorFrameParent ~= false end })
        args.selfPoint = Select(d, d, "selfPoint", "This point", POINTS,
            { hidden = function() return d.regionType == "group" or d.regionType == "dynamicgroup" end })
        args.anchorPoint = Select(d, d, "anchorPoint", "On that point", POINTS)
    else
        args.dynNote = Desc("Placed by its dynamic group (the Group tab of the group above it); these move it from its place.")
    end
    args.xOffset = Range(d, d, "xOffset", "Across", -2000, 2000, 1)
    args.yOffset = Range(d, d, "yOffset", "Up", -1200, 1200, 1)
    args.frameStrata = Select(d, d, "frameStrata", "Layer", STRATA)
end

-- the progress settings regions with a timer share
local function ProgressArgs(d, args)
    args.progHeader = Header("Progress")
    args.progressSource = { type = "select", name = "Comes from", order = N(),
        values = function()
            local out = { ["-1"] = "Automatic (the shown trigger)", ["0"] = "A fixed value" }
            if E.ProgressSources then
                for key, label in pairs(E.ProgressSources(d) or {}) do out[key] = label end
            end
            return out
        end,
        get = function()
            local s = d.progressSource
            if type(s) ~= "table" then return "-1" end
            if tonumber(s[1]) and tonumber(s[1]) > 0 then return tostring(s[1]) .. ":" .. tostring(s[2] or "") end
            return tostring(s[1] or -1)
        end,
        set = function(_, v)
            local t, p = tostring(v):match("^(%-?%d+):?(.*)$")
            t = tonumber(t) or -1
            if t == 0 then
                local old = type(d.progressSource) == "table" and d.progressSource or {}
                d.progressSource = { 0, "", tonumber(old[3]) or 0, tonumber(old[4]) or 100 }
            else
                d.progressSource = { t, p or "" }
            end
            Changed(d)
        end }
    local manual = function() return not (type(d.progressSource) == "table" and tonumber(d.progressSource[1]) == 0) end
    args.progValue = { type = "input", name = "  value", order = N(), hidden = manual,
        get = function() return tostring(type(d.progressSource) == "table" and d.progressSource[3] or 0) end,
        set = function(_, v) d.progressSource[3] = tonumber(v) or 0 Changed(d) end }
    args.progTotal = { type = "input", name = "  out of", order = N(), hidden = manual,
        get = function() return tostring(type(d.progressSource) == "table" and d.progressSource[4] or 100) end,
        set = function(_, v) d.progressSource[4] = tonumber(v) or 100 Changed(d) end }
    args.useAdjustededMin = Toggle(d, d, "useAdjustededMin", "Start the scale at")
    args.adjustedMin = Input(d, d, "adjustedMin", "  value (or 20%)", { hidden = function() return not d.useAdjustededMin end })
    args.useAdjustededMax = Toggle(d, d, "useAdjustededMax", "End the scale at")
    args.adjustedMax = Input(d, d, "adjustedMax", "  value (or 80%)", { hidden = function() return not d.useAdjustededMax end })
end

local function Size(d, args)
    args.width = Range(d, d, "width", "Width", 1, 2000, 1)
    args.height = Range(d, d, "height", "Height", 1, 2000, 1)
end

local DISPLAY = {}

function DISPLAY.icon(d, args)
    Size(d, args)
    args.alpha = Range(d, d, "alpha", "Opacity", 0, 1, 0.01)
    args.iconSource = Select(d, d, "iconSource", "Icon", function() return TriggerChoices(d, { [-1] = "Automatic", [0] = "This one" }) end)
    args.displayIcon = IdInput(d, d, "displayIcon", "  icon (texture path or file id)")
    args.desaturate = Toggle(d, d, "desaturate", "Grey")
    args.color = ColorOpt(d, d, "color", "Tint")
    args.zoom = Range(d, d, "zoom", "Zoom", 0, 1, 0.01)
    args.keepAspectRatio = Toggle(d, d, "keepAspectRatio", "Keep its shape (crop instead of stretch)")
    args.cdHeader = Header("Cooldown swipe")
    args.cooldown = Toggle(d, d, "cooldown", "Show the timer as a swipe")
    args.inverse = Toggle(d, d, "inverse", "  swipe the other way", { hidden = function() return not d.cooldown end })
    args.cooldownSwipe = Toggle(d, d, "cooldownSwipe", "  draw the swipe", { hidden = function() return not d.cooldown end })
    args.cooldownEdge = Toggle(d, d, "cooldownEdge", "  bright edge", { hidden = function() return not d.cooldown end })
    args.cooldownTextDisabled = Toggle(d, d, "cooldownTextDisabled", "  hide the game's countdown numbers",
        { hidden = function() return not d.cooldown end })
    args.useCooldownModRate = Toggle(d, d, "useCooldownModRate", "  follow the game's cooldown rate",
        { hidden = function() return not d.cooldown end })
    ProgressArgs(d, args)
end

function DISPLAY.aurabar(d, args)
    Size(d, args)
    args.alpha = Range(d, d, "alpha", "Opacity", 0, 1, 0.01)
    args.textureSource = Select(d, d, "textureSource", "Bar texture from", TEXTURE_SOURCE)
    args.texture = Select(d, d, "texture", "  texture", Media("statusbar"), { hidden = function() return d.textureSource == "Picker" end })
    args.textureInput = IdInput(d, d, "textureInput", "  texture (path or file id)", { hidden = function() return d.textureSource ~= "Picker" end })
    args.orientation = Select(d, d, "orientation", "Empties", ORIENT)
    args.inverse = Toggle(d, d, "inverse", "Fill instead of empty")
    args.barColor = ColorOpt(d, d, "barColor", "Bar colour")
    args.enableGradient = Toggle(d, d, "enableGradient", "Gradient")
    args.barColor2 = ColorOpt(d, d, "barColor2", "  to colour", { hidden = function() return not d.enableGradient end })
    args.gradientOrientation = Select(d, d, "gradientOrientation", "  direction", GRADIENT, { hidden = function() return not d.enableGradient end })
    args.backgroundColor = ColorOpt(d, d, "backgroundColor", "Background")
    args.iconHeader = Header("Icon")
    args.icon = Toggle(d, d, "icon", "Show an icon")
    local noIcon = function() return not d.icon end
    args.icon_side = Select(d, d, "icon_side", "  side", { LEFT = "Left / top", RIGHT = "Right / bottom" }, { hidden = noIcon })
    args.iconSource = Select(d, d, "iconSource", "  icon", function() return TriggerChoices(d, { [-1] = "Automatic", [0] = "This one" }) end, { hidden = noIcon })
    args.displayIcon = IdInput(d, d, "displayIcon", "  icon (path or file id)", { hidden = noIcon })
    args.icon_color = ColorOpt(d, d, "icon_color", "  tint", { hidden = noIcon })
    args.desaturate = Toggle(d, d, "desaturate", "  grey", { hidden = noIcon })
    args.zoom = Range(d, d, "zoom", "  zoom", 0, 1, 0.01, { hidden = noIcon })
    args.overlayHeader = Header("Overlays (stretches a trigger adds: heals coming, cast cost...)")
    args.overlayclip = Toggle(d, d, "overlayclip", "Keep overlays inside the bar")
    for i = 1, 3 do
        args["overlay" .. i] = { type = "color", name = "Overlay " .. i .. " colour", order = N(), hasAlpha = true,
            get = function() return E.Color(type(d.overlays) == "table" and d.overlays[i] or nil, 1, 1, 1, 0.6) end,
            set = function(_, r, g, b, a)
                d.overlays = type(d.overlays) == "table" and d.overlays or {}
                for j = 1, i - 1 do d.overlays[j] = d.overlays[j] or { 1, 1, 1, 0.6 } end
                d.overlays[i] = { r, g, b, a or 1 }
                Changed(d)
            end }
    end
    args.sparkHeader = Header("Spark")
    args.spark = Toggle(d, d, "spark", "Spark at the end of the fill")
    local noSpark = function() return not d.spark end
    args.sparkTexture = IdInput(d, d, "sparkTexture", "  texture", { hidden = noSpark })
    args.sparkColor = ColorOpt(d, d, "sparkColor", "  colour", { hidden = noSpark })
    args.sparkBlendMode = Select(d, d, "sparkBlendMode", "  blend", BLEND, { hidden = noSpark })
    args.sparkWidth = Range(d, d, "sparkWidth", "  width", 1, 100, 1, { hidden = noSpark })
    args.sparkHeight = Range(d, d, "sparkHeight", "  height", 1, 100, 1, { hidden = noSpark })
    args.sparkOffsetX = Range(d, d, "sparkOffsetX", "  across", -100, 100, 1, { hidden = noSpark })
    args.sparkOffsetY = Range(d, d, "sparkOffsetY", "  up", -100, 100, 1, { hidden = noSpark })
    args.sparkRotationMode = Select(d, d, "sparkRotationMode", "  turn", SPARK_ROTATION, { hidden = noSpark })
    args.sparkRotation = Range(d, d, "sparkRotation", "    angle", 0, 360, 1, { hidden = function() return not d.spark or d.sparkRotationMode ~= "MANUAL" end })
    args.sparkMirror = Toggle(d, d, "sparkMirror", "    mirror", { hidden = function() return not d.spark or d.sparkRotationMode ~= "MANUAL" end })
    args.sparkHidden = Select(d, d, "sparkHidden", "  hide", SPARK_HIDE, { hidden = noSpark })
    ProgressArgs(d, args)
end

function DISPLAY.text(d, args)
    args.displayText = Input(d, d, "displayText", "Text", { multiline = 3, width = "full",
        desc = "%p time left, %t total, %n name, %i icon, %s stacks, %c custom; %2.p for trigger 2" })
    args.customTextUpdate = Select(d, d, "customTextUpdate", "Custom text (%c) updates", { event = "When the trigger changes", update = "Every frame" })
    args.customText = Code(d, d, "customText", "Custom text code", 6)
    args.customText.hidden = function() return not (type(d.displayText) == "string" and d.displayText:find("%%c")) end
    -- one font: every aura text is in ZacUI's font; the aura's own face
    -- stays in its data (an export still carries it), not offered here
    args.font = Desc("Font: " .. ONE_FONT_NOTE)
    args.fontSize = Range(d, d, "fontSize", "Size", 6, 72, 1)
    args.outline = Select(d, d, "outline", "Outline", OUTLINES)
    args.color = ColorOpt(d, d, "color", "Colour")
    args.justify = Select(d, d, "justify", "Justify", JUSTIFY)
    args.automaticWidth = Select(d, d, "automaticWidth", "Width", AUTOWIDTH)
    args.fixedWidth = Range(d, d, "fixedWidth", "  width", 10, 1000, 1, { hidden = function() return d.automaticWidth ~= "Fixed" end })
    args.wordWrap = Select(d, d, "wordWrap", "  too long", WORDWRAP, { hidden = function() return d.automaticWidth ~= "Fixed" end })
    args.shadowColor = ColorOpt(d, d, "shadowColor", "Shadow")
    args.shadowXOffset = Range(d, d, "shadowXOffset", "  across", -10, 10, 1)
    args.shadowYOffset = Range(d, d, "shadowYOffset", "  up", -10, 10, 1)
    args.fmtHeader = Header("How the %codes show")
    FormatArgs(d, d, "displayText", d.displayText, args, "dt")
end

function DISPLAY.texture(d, args)
    Size(d, args)
    args.alpha = Range(d, d, "alpha", "Opacity", 0, 1, 0.01)
    args.texture = IdInput(d, d, "texture", "Texture (path, file id or atlas)", { width = "full" })
    args.color = ColorOpt(d, d, "color", "Colour")
    args.blendMode = Select(d, d, "blendMode", "Blend", BLEND)
    args.desaturate = Toggle(d, d, "desaturate", "Grey")
    args.mirror = Toggle(d, d, "mirror", "Mirror")
    args.rotate = Toggle(d, d, "rotate", "Turn freely (shows the whole picture)")
    args.rotation = Range(d, d, "rotation", "Rotation", 0, 360, 1)
    args.textureWrapMode = Select(d, d, "textureWrapMode", "Edges", WRAP)
end

function DISPLAY.progresstexture(d, args)
    Size(d, args)
    args.alpha = Range(d, d, "alpha", "Opacity", 0, 1, 0.01)
    args.foregroundTexture = IdInput(d, d, "foregroundTexture", "Fill texture", { width = "full" })
    args.sameTexture = Toggle(d, d, "sameTexture", "Background uses the fill texture")
    args.backgroundTexture = IdInput(d, d, "backgroundTexture", "  background texture", { width = "full", hidden = function() return d.sameTexture end })
    args.foregroundColor = ColorOpt(d, d, "foregroundColor", "Fill colour")
    args.backgroundColor = ColorOpt(d, d, "backgroundColor", "Background colour")
    args.desaturateForeground = Toggle(d, d, "desaturateForeground", "Grey fill")
    args.desaturateBackground = Toggle(d, d, "desaturateBackground", "Grey background")
    args.blendMode = Select(d, d, "blendMode", "Blend", BLEND)
    args.orientation = Select(d, d, "orientation", "Empties", ORIENT_CIRCLE)
    args.inverse = Toggle(d, d, "inverse", "Fill instead of empty")
    args.mirror = Toggle(d, d, "mirror", "Mirror")
    local circ = function() return d.orientation ~= "CLOCKWISE" and d.orientation ~= "ANTICLOCKWISE" end
    args.startAngle = Range(d, d, "startAngle", "  start angle", 0, 360, 1, { hidden = circ })
    args.endAngle = Range(d, d, "endAngle", "  end angle", 0, 360, 1, { hidden = circ })
    args.backgroundOffset = Range(d, d, "backgroundOffset", "Background bigger by", -50, 50, 1)
    args.rotation = Range(d, d, "rotation", "Texture rotation", 0, 360, 1)
    args.auraRotation = Range(d, d, "auraRotation", "Rotation", 0, 360, 1)
    args.compress = Toggle(d, d, "compress", "Squeeze instead of crop")
    args.crop_x = Range(d, d, "crop_x", "Crop across", 0, 2, 0.01)
    args.crop_y = Range(d, d, "crop_y", "Crop up", 0, 2, 0.01)
    args.user_x = Range(d, d, "user_x", "Shift across", -1, 1, 0.01)
    args.user_y = Range(d, d, "user_y", "Shift up", -1, 1, 0.01)
    args.slantMode = Select(d, d, "slantMode", "Slant", SLANT)
    args.textureWrapMode = Select(d, d, "textureWrapMode", "Edges", WRAP)
    ProgressArgs(d, args)
end

function DISPLAY.stopmotion(d, args)
    Size(d, args)
    args.foregroundTexture = IdInput(d, d, "foregroundTexture", "Flip book texture", { width = "full" })
    args.foregroundColor = ColorOpt(d, d, "foregroundColor", "Colour")
    args.desaturateForeground = Toggle(d, d, "desaturateForeground", "Grey")
    args.blendMode = Select(d, d, "blendMode", "Blend", BLEND)
    args.animationType = Select(d, d, "animationType", "Plays", STOPMOTION_ANIM)
    args.frameRate = Range(d, d, "frameRate", "Frames a second", 1, 120, 1, { hidden = function() return d.animationType == "progress" end })
    args.startPercent = Range(d, d, "startPercent", "First frame (share of the book)", 0, 1, 0.01)
    args.endPercent = Range(d, d, "endPercent", "Last frame", 0, 1, 0.01)
    args.inverse = Toggle(d, d, "inverse", "Backwards")
    args.mirror = Toggle(d, d, "mirror", "Mirror")
    args.customHeader = Header("A book whose name does not say its size")
    args.customForegroundRows = Range(d, d, "customForegroundRows", "Rows", 1, 64, 1)
    args.customForegroundColumns = Range(d, d, "customForegroundColumns", "Columns", 1, 64, 1)
    args.customForegroundFrames = Range(d, d, "customForegroundFrames", "Frames", 0, 4096, 1)
    args.customForegroundFileWidth = Range(d, d, "customForegroundFileWidth", "File width", 0, 4096, 1)
    args.customForegroundFileHeight = Range(d, d, "customForegroundFileHeight", "File height", 0, 4096, 1)
    args.customForegroundFrameWidth = Range(d, d, "customForegroundFrameWidth", "Frame width", 0, 4096, 1)
    args.customForegroundFrameHeight = Range(d, d, "customForegroundFrameHeight", "Frame height", 0, 4096, 1)
    args.bgHeader = Header("Background")
    args.hideBackground = Toggle(d, d, "hideBackground", "No background")
    local noBg = function() return d.hideBackground end
    args.sameTexture = Toggle(d, d, "sameTexture", "  same book", { hidden = noBg })
    args.backgroundTexture = IdInput(d, d, "backgroundTexture", "  texture", { width = "full", hidden = function() return d.hideBackground or d.sameTexture end })
    args.backgroundColor = ColorOpt(d, d, "backgroundColor", "  colour", { hidden = noBg })
    args.desaturateBackground = Toggle(d, d, "desaturateBackground", "  grey", { hidden = noBg })
    args.backgroundPercent = Range(d, d, "backgroundPercent", "  frame (share of the book)", 0, 1, 0.01, { hidden = noBg })
    args.customBackgroundRows = Range(d, d, "customBackgroundRows", "  rows", 1, 64, 1, { hidden = noBg })
    args.customBackgroundColumns = Range(d, d, "customBackgroundColumns", "  columns", 1, 64, 1, { hidden = noBg })
    args.customBackgroundFrames = Range(d, d, "customBackgroundFrames", "  frames", 0, 4096, 1, { hidden = noBg })
    ProgressArgs(d, args)
end

function DISPLAY.model(d, args)
    Size(d, args)
    args.alpha = Range(d, d, "alpha", "Opacity", 0, 1, 0.01)
    args.modelIsUnit = Toggle(d, d, "modelIsUnit", "Show a unit")
    args.modelDisplayInfo = Toggle(d, d, "modelDisplayInfo", "A creature display id")
    args.model_fileId = Input(d, d, "model_fileId", "Model (file id, unit, or display id)", { width = "full" })
    args.api = Toggle(d, d, "api", "Place with the transform numbers")
    local newApi = function() return not d.api end
    local oldApi = function() return d.api end
    args.model_z = Range(d, d, "model_z", "Distance", -20, 20, 0.05, { hidden = oldApi })
    args.model_x = Range(d, d, "model_x", "Across", -20, 20, 0.05, { hidden = oldApi })
    args.model_y = Range(d, d, "model_y", "Up", -20, 20, 0.05, { hidden = oldApi })
    args.rotation = Range(d, d, "rotation", "Facing", 0, 360, 1)
    args.model_st_tx = Range(d, d, "model_st_tx", "Move across", -1000, 1000, 1, { hidden = newApi })
    args.model_st_ty = Range(d, d, "model_st_ty", "Move up", -1000, 1000, 1, { hidden = newApi })
    args.model_st_tz = Range(d, d, "model_st_tz", "Move nearer", -1000, 1000, 1, { hidden = newApi })
    args.model_st_rx = Range(d, d, "model_st_rx", "Turn (x)", 0, 360, 1, { hidden = newApi })
    args.model_st_ry = Range(d, d, "model_st_ry", "Turn (y)", 0, 360, 1, { hidden = newApi })
    args.model_st_us = Range(d, d, "model_st_us", "Size", 5, 1000, 1, { hidden = newApi })
    args.portraitZoom = Toggle(d, d, "portraitZoom", "Portrait zoom")
    args.advance = Toggle(d, d, "advance", "Play an animation")
    args.sequence = Range(d, d, "sequence", "  animation number", 0, 1500, 1, { hidden = function() return not d.advance end })
    args.borderHeader = Header("Border")
    args.border = Toggle(d, d, "border", "Border")
    local noB = function() return not d.border end
    args.borderEdge = Select(d, d, "borderEdge", "  edge", Media("border", { None = "None" }), { hidden = noB })
    args.borderBackdrop = Select(d, d, "borderBackdrop", "  background", Media("background", { None = "None" }), { hidden = noB })
    args.borderColor = ColorOpt(d, d, "borderColor", "  edge colour", { hidden = noB })
    args.backdropColor = ColorOpt(d, d, "backdropColor", "  background colour", { hidden = noB })
    args.borderSize = Range(d, d, "borderSize", "  edge size", 1, 64, 1, { hidden = noB })
    args.borderOffset = Range(d, d, "borderOffset", "  outside by", -32, 32, 1, { hidden = noB })
    args.borderInset = Range(d, d, "borderInset", "  inset", 0, 32, 1, { hidden = noB })
end

function DISPLAY.empty(d, args)
    Size(d, args)
    args.alpha = Range(d, d, "alpha", "Opacity", 0, 1, 0.01)
end

local function GroupLook(d, args)
    args.alpha = Range(d, d, "alpha", "Opacity", 0, 1, 0.01)
    args.scale = Range(d, d, "scale", "Scale", 0.05, 10, 0.05)
    args.borderHeader = Header("Border round what shows")
    args.border = Toggle(d, d, "border", "Border")
    local noB = function() return not d.border end
    args.borderEdge = Select(d, d, "borderEdge", "  edge", Media("border", { None = "None" }), { hidden = noB })
    args.borderBackdrop = Select(d, d, "borderBackdrop", "  background", Media("background", { None = "None" }), { hidden = noB })
    args.borderColor = ColorOpt(d, d, "borderColor", "  edge colour", { hidden = noB })
    args.backdropColor = ColorOpt(d, d, "backdropColor", "  background colour", { hidden = noB })
    args.borderSize = Range(d, d, "borderSize", "  edge size", 1, 64, 1, { hidden = noB })
    args.borderOffset = Range(d, d, "borderOffset", "  outside by", -32, 32, 1, { hidden = noB })
    args.borderInset = Range(d, d, "borderInset", "  inset", 0, 32, 1, { hidden = noB })
end
DISPLAY.group = GroupLook
DISPLAY.dynamicgroup = GroupLook
O.DISPLAY = DISPLAY

function O.Display(d)
    order = 0
    local args = {}
    args.sizeHeader = Header("Size and look")
    local build = DISPLAY[d.regionType]
    if build then build(d, args) else args.unknown = Desc("This display type has no settings here.") end
    Place(d, args)
    return { type = "group", args = args }
end

-- ============================================================
-- WHAT HANGS ON IT (sub-elements)
-- ============================================================
local SUB_NAMES = { subtext = "Text", subborder = "Border", subglow = "Glow", subtick = "Tick mark",
    subtexture = "Texture", sublineartexture = "Linear fill texture", subcirculartexture = "Circular fill texture",
    submodel = "Model", substopmotion = "Flip book", subbackground = "(the display itself)", subforeground = "(the bar's fill)" }
O.SUB_NAMES = SUB_NAMES

local function ParentAnchors(rt)
    if rt == "icon" then
        local t = { CENTER = "Centre" }
        for p, label in pairs(POINTS) do
            if p ~= "CENTER" then
                t["INNER_" .. p] = "Inside " .. label:lower()
                t["OUTER_" .. p] = "Outside " .. label:lower()
            end
        end
        return t
    elseif rt == "aurabar" then
        local t = { SPARK = "The spark" }
        for p, label in pairs(POINTS) do
            t[p] = label
            t["ICON_" .. p] = "Icon " .. label:lower()
            if p ~= "CENTER" then t["INNER_" .. p] = "Inside " .. label:lower() end
        end
        return t
    end
    return POINTS
end
O.ParentAnchors = ParentAnchors

local AREAS = { bar = "The whole bar", icon = "The icon", fg = "The fill", bg = "The background" }

-- a new sub-element of a kind, with the format's starting values for
-- this display type
local MEDIA = (E.Regions and E.Regions.MEDIA) or "Interface\\AddOns\\Zacui_Auras\\"
function O.NewSub(kind, rt)
    local bar = rt == "aurabar"
    if kind == "subtext" then
        return { type = "subtext", text_text = bar and "%n" or "%p", text_visible = true, text_color = { 1, 1, 1, 1 },
            text_font = "Friz Quadrata TT", text_fontSize = 12, text_fontType = bar and "None" or "OUTLINE",
            text_justify = "CENTER", text_selfPoint = "AUTO", anchor_point = bar and "INNER_RIGHT" or "CENTER",
            anchorXOffset = 0, anchorYOffset = 0, rotateText = "NONE", text_automaticWidth = "Auto",
            text_fixedWidth = 64, text_wordWrap = "WordWrap", text_shadowColor = { 0, 0, 0, 1 },
            text_shadowXOffset = bar and 1 or 0, text_shadowYOffset = bar and -1 or 0 }
    elseif kind == "subborder" then
        local s = { type = "subborder", border_visible = true, border_edge = "Square Full White", border_size = 2,
            border_offset = 0, border_color = { 1, 1, 1, 1 } }
        if bar then s.anchor_area = "bar" end
        return s
    elseif kind == "subglow" then
        local s = { type = "subglow", glow = false, glowType = bar and "Pixel" or "buttonOverlay", useGlowColor = false,
            glowColor = { 1, 1, 1, 1 }, glowLines = 8, glowFrequency = 0.25, glowLength = 10, glowThickness = 1,
            glowScale = 1, glowBorder = false, glowXOffset = 0, glowYOffset = 0, glowDuration = 1 }
        if bar then s.anchor_area = "bar" end
        return s
    elseif kind == "subtick" then
        return { type = "subtick", tick_visible = true, tick_color = { 1, 1, 1, 1 }, tick_placement_mode = "AtValue",
            tick_placements = { 50 }, progressSources = { { -2, "" } }, automatic_length = true, tick_thickness = 2,
            tick_length = 30, use_texture = false, tick_texture = "Interface\\CastingBar\\UI-CastingBar-Spark",
            tick_blend_mode = "ADD", tick_desaturate = false, tick_rotation = 0, tick_mirror = false,
            tick_xOffset = 0, tick_yOffset = 0 }
    elseif kind == "subtexture" then
        return { type = "subtexture", textureTexture = MEDIA .. "PowerAurasMedia\\Auras\\Aura3", textureVisible = true,
            textureColor = { 1, 1, 1, 1 }, textureBlendMode = "BLEND", textureDesaturate = false, textureMirror = false,
            textureRotate = false, textureRotation = 0, anchor_mode = "area", anchor_area = bar and "bar" or "ALL",
            anchor_point = "CENTER", self_point = "CENTER", width = 32, height = 32, scale = 1, mirror = false, rotate = false }
    elseif kind == "sublineartexture" then
        return { type = "sublineartexture", linearTextureTexture = MEDIA .. "Media\\Textures\\Square_FullWhite",
            linearTextureVisible = true, linearTextureColor = { 1, 1, 1, 1 }, linearTextureBlendMode = "BLEND",
            linearTextureDesaturate = false, linearTextureMirror = false, linearTextureOrientation = "HORIZONTAL",
            linearTextureRotation = 0, linearTextureAuraRotation = 0, linearTextureCrop_x = 0.41, linearTextureCrop_y = 0.41,
            linearTextureUser_x = 0, linearTextureUser_y = 0, linearTextureWrapMode = "CLAMPTOBLACKADDITIVE",
            progressSource = { -2, "" }, anchor_mode = "area", anchor_area = bar and "bar" or "ALL", anchor_point = "CENTER",
            self_point = "CENTER", width = 32, height = 32, scale = 1 }
    elseif kind == "subcirculartexture" then
        return { type = "subcirculartexture", circularTextureTexture = MEDIA .. "Media\\Textures\\square_border_5px.tga",
            circularTextureVisible = true, circularTextureColor = { 1, 1, 1, 1 }, circularTextureBlendMode = "BLEND",
            circularTextureDesaturate = false, circularTextureMirror = false, circularTextureClockwise = true,
            circularTextureStartAngle = 0, circularTextureEndAngle = 360, circularTextureRotation = 0,
            circularTextureAuraRotation = 0, circularTextureCrop_x = 0.41, circularTextureCrop_y = 0.41,
            progressSource = { -2, "" }, anchor_mode = "area", anchor_area = bar and "bar" or "ALL", anchor_point = "CENTER",
            self_point = "CENTER", width = 32, height = 32, scale = 1 }
    elseif kind == "submodel" then
        return { type = "submodel", model_visible = true, model_alpha = 1, model_fileId = "235338", api = false,
            model_x = 0, model_y = 0, model_z = 0, rotation = 0, model_st_tx = 0, model_st_ty = 0, model_st_tz = 0,
            model_st_rx = 270, model_st_ry = 0, model_st_rz = 0, model_st_us = 40, bar_model_attach = true }
    elseif kind == "substopmotion" then
        return { type = "substopmotion", stopmotionTexture = MEDIA .. "Media\\Textures\\stopmotion", stopmotionVisible = true,
            stopmotionColor = { 1, 1, 1, 1 }, stopmotionBlendMode = "BLEND", stopmotionDesaturate = false,
            animationType = "loop", frameRate = 30, startPercent = 0, endPercent = 1, inverse = false,
            customRows = 16, customColumns = 16, customFrames = 0, customFileWidth = 0, customFileHeight = 0,
            customFrameWidth = 0, customFrameHeight = 0, barModelClip = true, progressSource = { -2, "" },
            anchor_mode = "area", anchor_area = bar and "bar" or "ALL", anchor_point = "CENTER", self_point = "CENTER",
            width = 32, height = 32, scale = 3 }
    end
    return { type = kind }
end

-- placement settings shared by the box-like sub-elements
local function SubBox(d, s, args, k)
    args[k .. "am"] = Select(d, s, "anchor_mode", "  placed", ANCHOR_MODE)
    local area = function() return s.anchor_mode == "point" end
    local point = function() return s.anchor_mode ~= "point" end
    if d.regionType == "aurabar" then
        args[k .. "aa"] = Select(d, s, "anchor_area", "  over", AREAS, { hidden = area })
    end
    args[k .. "ap"] = Select(d, s, "anchor_point", "  on its", ParentAnchors(d.regionType), { hidden = point })
    args[k .. "sp"] = Select(d, s, "self_point", "  by this point", POINTS, { hidden = point })
    args[k .. "w"] = Range(d, s, "width", "  width", 1, 1000, 1, { hidden = point })
    args[k .. "h"] = Range(d, s, "height", "  height", 1, 1000, 1, { hidden = point })
    args[k .. "x"] = Range(d, s, "xOffset", "  across", -500, 500, 1, { hidden = point })
    args[k .. "y"] = Range(d, s, "yOffset", "  up", -500, 500, 1, { hidden = point })
    args[k .. "sc"] = Range(d, s, "scale", "  scale", 0.05, 10, 0.05)
end

local SUBEDIT = {}
function SUBEDIT.subtext(d, s, args, k)
    args[k .. "v"] = Toggle(d, s, "text_visible", "Shown", { get = function() return s.text_visible ~= false end })
    args[k .. "t"] = Input(d, s, "text_text", "Text", { multiline = 2, width = "full" })
    args[k .. "a"] = Select(d, s, "anchor_point", "Where", ParentAnchors(d.regionType))
    args[k .. "sp"] = Select(d, s, "text_selfPoint", "  by this point", (function()
        local t = { AUTO = "Automatic" } for p, l in pairs(POINTS) do t[p] = l end return t end)())
    args[k .. "x"] = Range(d, s, "anchorXOffset", "  across", -200, 200, 1)
    args[k .. "y"] = Range(d, s, "anchorYOffset", "  up", -200, 200, 1)
    args[k .. "f"] = Desc("Font: " .. ONE_FONT_NOTE)
    args[k .. "s"] = Range(d, s, "text_fontSize", "Size", 6, 72, 1)
    args[k .. "o"] = Select(d, s, "text_fontType", "Outline", OUTLINES)
    args[k .. "c"] = ColorOpt(d, s, "text_color", "Colour")
    args[k .. "j"] = Select(d, s, "text_justify", "Justify", JUSTIFY)
    args[k .. "r"] = Select(d, s, "rotateText", "Turn", ROTATE_TEXT)
    args[k .. "aw"] = Select(d, s, "text_automaticWidth", "Width", AUTOWIDTH)
    args[k .. "fw"] = Range(d, s, "text_fixedWidth", "  width", 10, 1000, 1, { hidden = function() return s.text_automaticWidth ~= "Fixed" end })
    args[k .. "ww"] = Select(d, s, "text_wordWrap", "  too long", WORDWRAP, { hidden = function() return s.text_automaticWidth ~= "Fixed" end })
    args[k .. "sh"] = ColorOpt(d, s, "text_shadowColor", "Shadow")
    args[k .. "shx"] = Range(d, s, "text_shadowXOffset", "  across", -10, 10, 1)
    args[k .. "shy"] = Range(d, s, "text_shadowYOffset", "  up", -10, 10, 1)
    FormatArgs(d, s, "text_text", s.text_text, args, k)
end
function SUBEDIT.subborder(d, s, args, k)
    args[k .. "v"] = Toggle(d, s, "border_visible", "Shown", { get = function() return s.border_visible ~= false end })
    args[k .. "e"] = Select(d, s, "border_edge", "Edge", Media("border"))
    args[k .. "s"] = Range(d, s, "border_size", "Size", 1, 64, 1)
    args[k .. "o"] = Range(d, s, "border_offset", "Outside by", -32, 32, 1)
    args[k .. "c"] = ColorOpt(d, s, "border_color", "Colour")
    if d.regionType == "aurabar" then args[k .. "aa"] = Select(d, s, "anchor_area", "Round", AREAS) end
end
function SUBEDIT.subglow(d, s, args, k)
    args[k .. "g"] = Toggle(d, s, "glow", "Glowing")
    args[k .. "t"] = Select(d, s, "glowType", "Kind", GLOWS)
    args[k .. "u"] = Toggle(d, s, "useGlowColor", "Own colour")
    args[k .. "c"] = ColorOpt(d, s, "glowColor", "  colour", { hidden = function() return not s.useGlowColor end })
    local lines = function() return s.glowType ~= "Pixel" and s.glowType ~= "ACShine" end
    args[k .. "l"] = Range(d, s, "glowLines", "Lines", 1, 30, 1, { hidden = lines })
    args[k .. "f"] = Range(d, s, "glowFrequency", "Speed", -2, 2, 0.05, { hidden = lines })
    args[k .. "len"] = Range(d, s, "glowLength", "Length", 1, 50, 1, { hidden = function() return s.glowType ~= "Pixel" end })
    args[k .. "k"] = Range(d, s, "glowThickness", "Thickness", 0.5, 10, 0.5, { hidden = function() return s.glowType ~= "Pixel" end })
    args[k .. "b"] = Toggle(d, s, "glowBorder", "Border", { hidden = function() return s.glowType ~= "Pixel" end })
    args[k .. "sc"] = Range(d, s, "glowScale", "Scale", 0.05, 10, 0.05, { hidden = function() return s.glowType ~= "ACShine" end })
    args[k .. "x"] = Range(d, s, "glowXOffset", "Outside by (across)", -50, 50, 1, { hidden = function() return s.glowType == "buttonOverlay" end })
    args[k .. "y"] = Range(d, s, "glowYOffset", "Outside by (up)", -50, 50, 1, { hidden = function() return s.glowType == "buttonOverlay" end })
    if d.regionType == "aurabar" then args[k .. "aa"] = Select(d, s, "anchor_area", "Round", AREAS) end
end
function SUBEDIT.subtick(d, s, args, k)
    args[k .. "v"] = Toggle(d, s, "tick_visible", "Shown", { get = function() return s.tick_visible ~= false end })
    args[k .. "m"] = Select(d, s, "tick_placement_mode", "Placed", TICK_MODES)
    args[k .. "p"] = { type = "input", name = "  at (comma separated)", order = N(),
        get = function()
            local t = {}
            for _, v in ipairs(type(s.tick_placements) == "table" and s.tick_placements or {}) do t[#t + 1] = tostring(v) end
            return table.concat(t, ", ")
        end,
        set = function(_, v)
            local out, srcs = {}, {}
            for part in tostring(v):gmatch("[^,]+") do
                local n = tonumber((part:gsub("%s", "")))
                if n then out[#out + 1] = n srcs[#srcs + 1] = { -2, "" } end
            end
            s.tick_placements = out
            s.progressSources = srcs
            Changed(d)
        end }
    args[k .. "c"] = ColorOpt(d, s, "tick_color", "Colour")
    args[k .. "th"] = Range(d, s, "tick_thickness", "Thickness", 1, 50, 1)
    args[k .. "al"] = Toggle(d, s, "automatic_length", "As long as the bar is thick")
    args[k .. "ln"] = Range(d, s, "tick_length", "  length", 1, 200, 1, { hidden = function() return s.automatic_length ~= false end })
    args[k .. "x"] = Range(d, s, "tick_xOffset", "Across", -100, 100, 1)
    args[k .. "y"] = Range(d, s, "tick_yOffset", "Up", -100, 100, 1)
    args[k .. "ut"] = Toggle(d, s, "use_texture", "Use a texture")
    local noTex = function() return not s.use_texture end
    args[k .. "tx"] = IdInput(d, s, "tick_texture", "  texture", { hidden = noTex })
    args[k .. "bm"] = Select(d, s, "tick_blend_mode", "  blend", BLEND, { hidden = noTex })
    args[k .. "ds"] = Toggle(d, s, "tick_desaturate", "  grey", { hidden = noTex })
    args[k .. "ro"] = Range(d, s, "tick_rotation", "  rotation", 0, 360, 1, { hidden = noTex })
    args[k .. "mi"] = Toggle(d, s, "tick_mirror", "  mirror", { hidden = noTex })
end
function SUBEDIT.subtexture(d, s, args, k)
    args[k .. "v"] = Toggle(d, s, "textureVisible", "Shown", { get = function() return s.textureVisible ~= false end })
    args[k .. "t"] = IdInput(d, s, "textureTexture", "Texture", { width = "full" })
    args[k .. "c"] = ColorOpt(d, s, "textureColor", "Colour")
    args[k .. "bm"] = Select(d, s, "textureBlendMode", "Blend", BLEND)
    args[k .. "ds"] = Toggle(d, s, "textureDesaturate", "Grey")
    args[k .. "mi"] = Toggle(d, s, "textureMirror", "Mirror")
    args[k .. "rf"] = Toggle(d, s, "textureRotate", "Turn freely")
    args[k .. "ro"] = Range(d, s, "textureRotation", "Rotation", 0, 360, 1)
    SubBox(d, s, args, k)
end
local function FillTexture(pre)
    return function(d, s, args, k)
        args[k .. "v"] = Toggle(d, s, pre .. "Visible", "Shown", { get = function() return s[pre .. "Visible"] ~= false end })
        args[k .. "t"] = IdInput(d, s, pre .. "Texture", "Texture", { width = "full" })
        args[k .. "c"] = ColorOpt(d, s, pre .. "Color", "Colour")
        args[k .. "bm"] = Select(d, s, pre .. "BlendMode", "Blend", BLEND)
        args[k .. "ds"] = Toggle(d, s, pre .. "Desaturate", "Grey")
        args[k .. "mi"] = Toggle(d, s, pre .. "Mirror", "Mirror")
        args[k .. "in"] = Toggle(d, s, pre .. "Inverse", "Fill instead of empty")
        if pre == "linearTexture" then
            args[k .. "or"] = Select(d, s, "linearTextureOrientation", "Empties", ORIENT)
            args[k .. "wm"] = Select(d, s, "linearTextureWrapMode", "Edges", WRAP)
        else
            args[k .. "cw"] = Toggle(d, s, "circularTextureClockwise", "Clockwise", { get = function() return s.circularTextureClockwise ~= false end })
            args[k .. "sa"] = Range(d, s, "circularTextureStartAngle", "Start angle", 0, 360, 1)
            args[k .. "ea"] = Range(d, s, "circularTextureEndAngle", "End angle", 0, 360, 1)
        end
        args[k .. "ro"] = Range(d, s, pre .. "Rotation", "Texture rotation", 0, 360, 1)
        args[k .. "ar"] = Range(d, s, pre .. "AuraRotation", "Rotation", 0, 360, 1)
        args[k .. "cx"] = Range(d, s, pre .. "Crop_x", "Crop across", 0, 2, 0.01)
        args[k .. "cy"] = Range(d, s, pre .. "Crop_y", "Crop up", 0, 2, 0.01)
        SubBox(d, s, args, k)
    end
end
SUBEDIT.sublineartexture = FillTexture("linearTexture")
SUBEDIT.subcirculartexture = FillTexture("circularTexture")
function SUBEDIT.submodel(d, s, args, k)
    args[k .. "v"] = Toggle(d, s, "model_visible", "Shown", { get = function() return s.model_visible ~= false end })
    args[k .. "al"] = Range(d, s, "model_alpha", "Opacity", 0, 1, 0.01)
    args[k .. "id"] = Input(d, s, "model_fileId", "Model (file id)", { width = "full" })
    args[k .. "api"] = Toggle(d, s, "api", "Place with the transform numbers")
    args[k .. "mz"] = Range(d, s, "model_z", "Distance", -20, 20, 0.05, { hidden = function() return s.api end })
    args[k .. "mx"] = Range(d, s, "model_x", "Across", -20, 20, 0.05, { hidden = function() return s.api end })
    args[k .. "my"] = Range(d, s, "model_y", "Up", -20, 20, 0.05, { hidden = function() return s.api end })
    args[k .. "ro"] = Range(d, s, "rotation", "Facing", 0, 360, 1)
    for _, f in ipairs({ { "model_st_tx", "Move across" }, { "model_st_ty", "Move up" }, { "model_st_tz", "Move nearer" },
        { "model_st_rx", "Turn (x)" }, { "model_st_ry", "Turn (y)" }, { "model_st_rz", "Turn (z)" }, { "model_st_us", "Size" } }) do
        args[k .. f[1]] = Range(d, s, f[1], f[2], -1000, 1000, 1, { hidden = function() return not s.api end })
    end
    if d.regionType == "aurabar" then
        args[k .. "at"] = Toggle(d, s, "bar_model_attach", "Only over the fill", { get = function() return s.bar_model_attach ~= false end })
    end
end
function SUBEDIT.substopmotion(d, s, args, k)
    args[k .. "v"] = Toggle(d, s, "stopmotionVisible", "Shown", { get = function() return s.stopmotionVisible ~= false end })
    args[k .. "t"] = IdInput(d, s, "stopmotionTexture", "Flip book texture", { width = "full" })
    args[k .. "c"] = ColorOpt(d, s, "stopmotionColor", "Colour")
    args[k .. "bm"] = Select(d, s, "stopmotionBlendMode", "Blend", BLEND)
    args[k .. "ds"] = Toggle(d, s, "stopmotionDesaturate", "Grey")
    args[k .. "an"] = Select(d, s, "animationType", "Plays", STOPMOTION_ANIM)
    args[k .. "fr"] = Range(d, s, "frameRate", "Frames a second", 1, 120, 1)
    args[k .. "st"] = Range(d, s, "startPercent", "First frame", 0, 1, 0.01)
    args[k .. "en"] = Range(d, s, "endPercent", "Last frame", 0, 1, 0.01)
    args[k .. "in"] = Toggle(d, s, "inverse", "Backwards")
    args[k .. "cr"] = Range(d, s, "customRows", "Rows (unnamed book)", 1, 64, 1)
    args[k .. "cc"] = Range(d, s, "customColumns", "Columns", 1, 64, 1)
    args[k .. "cf"] = Range(d, s, "customFrames", "Frames", 0, 4096, 1)
    SubBox(d, s, args, k)
end
O.SUBEDIT = SUBEDIT

function O.Text(d)
    order = 0
    local args = {}
    if E.IsGroup(d) then
        args.none = Desc("Groups have nothing hanging on them; each display inside has its own.")
        return { type = "group", args = args }
    end
    d.subRegions = type(d.subRegions) == "table" and d.subRegions or {}
    local subs = d.subRegions
    local supports = E.SubRegions and E.SubRegions.supports or {}
    for i, s in ipairs(subs) do
        local key = "sub" .. i
        local name = SUB_NAMES[s.type] or tostring(s.type)
        args[key .. "hd"] = Header(name .. " (" .. i .. ")")
        local edit = SUBEDIT[s.type]
        if edit then
            local g = {}
            edit(d, s, g, key)
            args[key] = Group(g)
        end
        args[key .. "up"] = Button("Move up", function()
            subs[i], subs[i - 1] = subs[i - 1], subs[i]
            Changed(d)
        end, { hidden = function() return i == 1 end })
        args[key .. "dn"] = Button("Move down", function()
            subs[i], subs[i + 1] = subs[i + 1], subs[i]
            Changed(d)
        end, { hidden = function() return i == #subs end })
        if s.type ~= "subbackground" and s.type ~= "subforeground" then
            args[key .. "rm"] = Button("Remove this", function()
                table.remove(subs, i)
                Changed(d)
            end)
        end
    end
    args.addHeader = Header("Add")
    for _, kind in ipairs({ "subtext", "subborder", "subglow", "subtick", "subtexture", "sublineartexture",
        "subcirculartexture", "submodel", "substopmotion" }) do
        local ok = supports[kind] == nil or supports[kind][d.regionType]
        if ok then
            args["add_" .. kind] = Button("Add a " .. SUB_NAMES[kind]:lower(), function()
                table.insert(subs, O.NewSub(kind, d.regionType))
                Changed(d)
            end)
        end
    end
    return { type = "group", args = args }
end

-- ============================================================
-- TRIGGERS
-- ============================================================
local TYPES = { aura2 = "Buff / debuff", custom = "Custom code", unit = "Unit", spell = "Spell",
    item = "Item", event = "Event", combatlog = "Combat log" }
local UNITS = { player = "You", target = "Target", focus = "Focus", pet = "Pet", targettarget = "Target's target",
    group = "Your group", party = "Party", raid = "Raid", nameplate = "Nameplates", boss = "Bosses" }
local OPS = { ["=="] = "=", ["~="] = "not", ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=" }
local GENERIC = {
    unit = { "Health", "Power", "Conditions", "Unit Characteristics", "Stance/Form/Aura", "Cast", "Range Check",
        "Location", "Character Stats", "Swing Timer" },
    spell = { "Cooldown Progress (Spell)", "Global Cooldown", "Action Usable", "Queued Action", "Spell Known" },
    item = { "Item Count", "Cooldown Progress (Item)", "Cooldown Progress (Equipment Slot)", "Cooldown Ready (Item)", "Item Equipped" },
    event = { "Chat Message", "Combat Events", "Encounter Events" },
    combatlog = { "Combat Log" },
}
local function List(t) local o = {} for _, v in ipairs(t) do o[v] = v end return o end

-- a comma list stored as a table of strings
local function ListInput(d, tr, key, name)
    return { type = "input", name = name, order = N(), width = "full",
        get = function() return type(tr[key]) == "table" and table.concat(tr[key], ", ") or "" end,
        set = function(_, v)
            local out = {}
            for part in tostring(v):gmatch("[^,]+") do
                part = part:gsub("^%s+", ""):gsub("%s+$", "")
                if part ~= "" then out[#out + 1] = part end
            end
            tr[key] = out
            Changed(d)
        end }
end

-- a "use this check" + value + operator trio
local function Check(d, tr, args, key, field, name, withOp)
    args[key .. "u"] = Toggle(d, tr, "use_" .. field, name)
    if withOp then
        args[key .. "o"] = Select(d, tr, field .. "_operator", "  is", OPS, { hidden = function() return not tr["use_" .. field] end })
    end
    args[key .. "v"] = Input(d, tr, field, "  value", { hidden = function() return not tr["use_" .. field] end })
end

local function TriggerArgs(d, i, t, args)
    local tr = t.trigger
    local k = "t" .. i
    args[k .. "h"] = Header("Trigger " .. i)
    args[k .. "type"] = Select(d, tr, "type", "Kind", TYPES)
    local ty = tr.type
    if ty == "aura2" then
        args[k .. "unit"] = Select(d, tr, "unit", "On", UNITS)
        args[k .. "dt"] = Select(d, tr, "debuffType", "Kind of aura", { HELPFUL = "Buff", HARMFUL = "Debuff" })
        args[k .. "un"] = Toggle(d, tr, "useName", "Only these (names or spell ids)")
        args[k .. "names"] = ListInput(d, tr, "auranames", "  names")
        args[k .. "own"] = Select(d, tr, "ownOnly", "Cast by", { [1] = "Anyone", [2] = "Me", [3] = "Not me" }, {
            get = function() if tr.ownOnly == true then return 2 elseif tr.ownOnly == false then return 3 end return 1 end,
            set = function(_, v) tr.ownOnly = (v == 2) or (v == 3 and false) or nil Changed(d) end })
        args[k .. "show"] = Select(d, tr, "matchesShowOn", "Show", { showOnActive = "When it is there",
            showOnMissing = "When it is missing", showAlways = "Always" })
        args[k .. "clones"] = Toggle(d, tr, "showClones", "One display per match")
        args[k .. "stu"] = Toggle(d, tr, "useStacks", "Stack count")
        args[k .. "sto"] = Select(d, tr, "stacksOperator", "  is", OPS, { hidden = function() return not tr.useStacks end })
        args[k .. "stv"] = Input(d, tr, "stacks", "  value", { hidden = function() return not tr.useStacks end })
    elseif ty == "custom" then
        args[k .. "ct"] = Select(d, tr, "custom_type", "Style", { stateupdate = "Trigger state updater",
            event = "Event", status = "Status" })
        args[k .. "ev"] = Input(d, tr, "events", "Events", { width = "full",
            desc = "Comma separated: UNIT_AURA:player, CLEU:SPELL_CAST_SUCCESS, WA_MY_EVENT" })
        args[k .. "chk"] = Select(d, tr, "check", "Check", { event = "On those events", update = "Every frame" },
            { hidden = function() return tr.custom_type ~= "status" end })
        args[k .. "code"] = Code(d, tr, "custom", "Code", 14)
        args[k .. "hide"] = Select(d, tr, "custom_hide", "Hide", { timed = "After a time", custom = "With code" },
            { hidden = function() return tr.custom_type ~= "event" end })
        args[k .. "dur"] = Input(d, tr, "duration", "  seconds", { hidden = function() return tr.custom_type ~= "event" or tr.custom_hide ~= "timed" end })
        args[k .. "un"] = Code(d, t.untrigger, "custom", "Hide code", 6)
        args[k .. "un"].hidden = function() return tr.custom_type ~= "event" or tr.custom_hide ~= "custom" end
        args[k .. "cd"] = Code(d, tr, "customDuration", "Duration / progress (optional)", 4)
        args[k .. "cn"] = Code(d, tr, "customName", "Name (optional)", 3)
        args[k .. "ci"] = Code(d, tr, "customIcon", "Icon (optional)", 3)
        args[k .. "cs"] = Code(d, tr, "customStacks", "Stacks (optional)", 3)
        for _, key in ipairs({ "cd", "cn", "ci", "cs" }) do
            args[k .. key].hidden = function() return tr.custom_type == "stateupdate" end
        end
    elseif GENERIC[ty] then
        args[k .. "ev"] = Select(d, tr, "event", "Which", List(GENERIC[ty]))
        local e = tr.event
        if ty == "unit" and e ~= "Conditions" and e ~= "Location" and e ~= "Character Stats" and e ~= "Swing Timer" then
            args[k .. "unit"] = Select(d, tr, "unit", "Unit", UNITS)
        end
        if e == "Health" then
            Check(d, tr, args, k .. "h", "health", "Health", true)
            Check(d, tr, args, k .. "p", "percenthealth", "Health %", true)
            Check(d, tr, args, k .. "n", "npcId", "Npc ids", false)
        elseif e == "Power" then
            Check(d, tr, args, k .. "pt", "powertype", "Power type (0 mana, 1 rage, 3 energy, 4 combo)", false)
            Check(d, tr, args, k .. "p", "power", "Power", true)
            Check(d, tr, args, k .. "pp", "percentpower", "Power %", true)
        elseif e == "Conditions" then
            for _, f in ipairs({ { "incombat", "In combat" }, { "mounted", "Mounted" }, { "resting", "Resting" },
                { "alive", "Alive" }, { "ingroup", "In a group" } }) do
                args[k .. f[1]] = Select(d, tr, "use_" .. f[1], f[2], { [1] = "Either", [2] = "Yes", [3] = "No" }, {
                    get = function() local v = tr["use_" .. f[1]] if v == true then return 2 elseif v == false then return 3 end return 1 end,
                    set = function(_, v) tr["use_" .. f[1]] = (v == 2) or (v == 3 and false) or nil Changed(d) end })
            end
        elseif e == "Unit Characteristics" then
            args[k .. "att"] = Select(d, tr, "use_attackable", "Attackable", { [1] = "Either", [2] = "Yes", [3] = "No" }, {
                get = function() local v = tr.use_attackable if v == true then return 2 elseif v == false then return 3 end return 1 end,
                set = function(_, v) tr.use_attackable = (v == 2) or (v == 3 and false) or nil Changed(d) end })
            Check(d, tr, args, k .. "n", "npcId", "Npc ids", false)
            Check(d, tr, args, k .. "nm", "name", "Name", false)
        elseif e == "Cast" then
            Check(d, tr, args, k .. "sn", "spellName", "Spell", false)
        elseif e == "Range Check" then
            args[k .. "r"] = Input(d, tr, "range", "Yards")
            args[k .. "ro"] = Select(d, tr, "range_operator", "  is", { ["<="] = "within", [">="] = "beyond" })
        elseif e == "Location" then
            Check(d, tr, args, k .. "z", "zoneIds", "Zone ids", false)
        elseif e == "Swing Timer" then
            args[k .. "hand"] = Select(d, tr, "hand", "Hand", { main = "Main hand", off = "Off hand", ranged = "Ranged" })
        elseif ty == "spell" then
            args[k .. "sp"] = Input(d, tr, "spellName", "Spell (name or id)")
            if e == "Cooldown Progress (Spell)" then
                args[k .. "show"] = Select(d, tr, "genericShowOn", "Show", { showOnCooldown = "On cooldown",
                    showOnReady = "When ready", showAlways = "Always" })
                args[k .. "gcd"] = Toggle(d, tr, "use_showgcd", "Count the global cooldown")
            end
        elseif ty == "item" then
            if e == "Cooldown Progress (Equipment Slot)" then
                args[k .. "slot"] = Select(d, tr, "itemSlot", "Slot", { [13] = "Trinket 1", [14] = "Trinket 2",
                    [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" })
            else
                args[k .. "it"] = Input(d, tr, "itemName", "Item (name or id)")
            end
            if e == "Item Count" then Check(d, tr, args, k .. "c", "count", "Count", true) end
            if e:find("Cooldown Progress") then
                args[k .. "show"] = Select(d, tr, "genericShowOn", "Show", { showOnCooldown = "On cooldown",
                    showOnReady = "When ready", showAlways = "Always" })
            end
        elseif e == "Chat Message" then
            Check(d, tr, args, k .. "mt", "messageType", "Channel (CHAT_MSG_...)", false)
            args[k .. "msgu"] = Toggle(d, tr, "use_message", "Message")
            args[k .. "msgo"] = Select(d, tr, "message_operator", "  ", { ["=="] = "is", ["find('%s')"] = "contains",
                ["match('%s')"] = "matches" }, { hidden = function() return not tr.use_message end })
            args[k .. "msgv"] = Input(d, tr, "message", "  text", { hidden = function() return not tr.use_message end })
            args[k .. "dur"] = Input(d, tr, "duration", "Show for (seconds)")
        elseif e == "Combat Events" then
            args[k .. "et"] = Select(d, tr, "eventtype", "When", { PLAYER_REGEN_DISABLED = "Entering combat",
                PLAYER_REGEN_ENABLED = "Leaving combat" })
            args[k .. "dur"] = Input(d, tr, "duration", "Show for (seconds)")
        elseif e == "Encounter Events" then
            args[k .. "et"] = Select(d, tr, "eventtype", "When", { ENCOUNTER_START = "A boss is pulled", ENCOUNTER_END = "A boss fight ends" })
            Check(d, tr, args, k .. "enc", "encounterId", "Encounter ids", false)
            args[k .. "dur"] = Input(d, tr, "duration", "Show for (seconds)")
        elseif e == "Combat Log" then
            args[k .. "pre"] = Select(d, tr, "subeventPrefix", "Event", { SPELL = "Spell", SWING = "Swing", RANGE = "Ranged",
                SPELL_PERIODIC = "Periodic", ENVIRONMENTAL = "Environmental", UNIT_DIED = "Unit died" })
            args[k .. "suf"] = Select(d, tr, "subeventSuffix", "  what", { _DAMAGE = "Damage", _MISSED = "Missed",
                _HEAL = "Heal", _CAST_START = "Cast start", _CAST_SUCCESS = "Cast success", _AURA_APPLIED = "Aura applied",
                _AURA_REMOVED = "Aura removed", _AURA_REFRESH = "Aura refreshed", _INTERRUPT = "Interrupt", _ABSORBED = "Absorbed" })
            Check(d, tr, args, k .. "sid", "spellId", "Spell ids", false)
            Check(d, tr, args, k .. "snm", "spellName", "Spell name", false)
            Check(d, tr, args, k .. "su", "sourceUnit", "Source unit", false)
            Check(d, tr, args, k .. "du", "destUnit", "Destination unit", false)
            args[k .. "clone"] = Toggle(d, tr, "use_cloneId", "A display per event")
            args[k .. "dur"] = Input(d, tr, "duration", "Show for (seconds)")
        end
    end
    args[k .. "rm"] = { type = "execute", name = "Remove trigger " .. i, order = N(),
        hidden = function() return E.TriggerCount(d) <= 1 end,
        func = function() table.remove(d.triggers, i) Changed(d) end }
end

function O.Triggers(d)
    order = 0
    local args = {}
    d.triggers = type(d.triggers) == "table" and d.triggers or {}
    if E.IsGroup(d) then
        args.none = Desc("Groups have no triggers; each display inside has its own.")
        return { type = "group", args = args }
    end
    args.logic = Select(d, d.triggers, "disjunctive", "Shows when", { any = "Any trigger is active",
        all = "All triggers are active", custom = "Custom code decides" })
    do  -- missing reads as "all" (as WeakAuras); show that
        local get = args.logic.get
        if get then args.logic.get = function(...) return get(...) or "all" end end
    end
    args.logicCode = Code(d, d.triggers, "customTriggerLogic", "Logic code", 5)
    args.logicCode.hidden = function() return d.triggers.disjunctive ~= "custom" end
    for i, t in ipairs(d.triggers) do
        if type(t) == "table" then
            t.trigger = type(t.trigger) == "table" and t.trigger or {}
            t.untrigger = type(t.untrigger) == "table" and t.untrigger or {}
            TriggerArgs(d, i, t, args)
        end
    end
    args.add = { type = "execute", name = "Add a trigger", order = N(), func = function()
        table.insert(d.triggers, { trigger = { type = "aura2", unit = "player", debuffType = "HELPFUL" }, untrigger = {} })
        Changed(d)
    end }
    return { type = "group", args = args }
end

-- ============================================================
-- SHARED ACTION EDITORS (sound, chat, glow) for actions and conditions
-- ============================================================
local function SoundChoices()
    local out = { [" custom"] = "(a file path)", [" KitID"] = "(a sound kit id)" }
    -- the game's own sounds under plain names (ZacUI carries no sound files)
    if ns.Sounds and ns.Sounds.PickerItems then
        for _, it in ipairs(ns.Sounds.PickerItems()) do out[it.value] = it.text end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local ok, list = pcall(LSM.List, LSM, "sound")
        if ok and type(list) == "table" then for _, n in ipairs(list) do out[n] = n end end
    end
    return out
end

local function SoundArgs(d, a, args, k, withKind)
    if withKind then
        args[k .. "sk"] = Select(d, a, "sound_type", "  sound", SOUND_KINDS)
    end
    local stop = function() return withKind and a.sound_type == "Stop" end
    args[k .. "ss"] = Select(d, a, "sound", "  play", SoundChoices, { hidden = stop })
    args[k .. "sp"] = Input(d, a, "sound_path", "    file", { hidden = function() return stop() or a.sound ~= " custom" end })
    args[k .. "sid"] = Input(d, a, "sound_kit_id", "    kit id", { hidden = function() return stop() or a.sound ~= " KitID" end })
    args[k .. "sc"] = Select(d, a, "sound_channel", "  channel", SOUND_CHANNELS, { hidden = stop })
    if withKind then
        args[k .. "sr"] = Range(d, a, "sound_repeat", "  repeat every (seconds)", 0.1, 60, 0.1,
            { hidden = function() return a.sound_type ~= "Loop" end })
        args[k .. "sf"] = Range(d, a, "sound_fade", "  fade out (seconds)", 0, 10, 0.1,
            { hidden = function() return a.sound_type ~= "Stop" end })
    else
        args[k .. "lp"] = Toggle(d, a, "do_loop", "  repeat")
        args[k .. "sr"] = Range(d, a, "sound_repeat", "    every (seconds)", 0.1, 60, 0.1, { hidden = function() return not a.do_loop end })
    end
end

local function MessageArgs(d, a, args, k, colorKey)
    args[k .. "mt"] = Select(d, a, "message_type", "  to", MESSAGE_TYPES)
    args[k .. "mm"] = Input(d, a, "message", "  message", { width = "full", multiline = 2 })
    local notWhisper = function() return a.message_type ~= "WHISPER" end
    args[k .. "md"] = Input(d, a, "message_dest", "  whisper to", { hidden = notWhisper })
    args[k .. "mu"] = Toggle(d, a, "message_dest_isunit", "    that is a unit (target, focus...)", { hidden = notWhisper })
    local noColor = function() local t = a.message_type return t ~= "PRINT" and t ~= "ERROR" and t ~= "COMBAT" end
    if colorKey == "message_color" then
        args[k .. "mc"] = ColorOpt(d, a, "message_color", "  colour", { hidden = noColor })
    else
        args[k .. "mc"] = { type = "color", name = "  colour", order = N(), hasAlpha = false, hidden = noColor,
            get = function() return a.r or 1, a.g or 1, a.b or 1, 1 end,
            set = function(_, r, g, b) a.r, a.g, a.b = r, g, b Changed(d) end }
    end
    args[k .. "mcu"] = Code(d, a, "message_custom", "  custom code for %c (returns values)", 5)
    args[k .. "mcu"].hidden = function() return not (type(a.message) == "string" and a.message:find("%%c")) end
    FormatArgs(d, a, "message", a.message, args, k .. "mf")
end

local function GlowActionArgs(d, a, args, k)
    args[k .. "ga"] = Select(d, a, "glow_action", "  glow", GLOW_ACTIONS)
    args[k .. "gf"] = Select(d, a, "glow_frame_type", "  on", GLOW_FRAMES)
    args[k .. "gn"] = Input(d, a, "glow_frame", "    frame name (or WeakAuras:<display>)",
        { hidden = function() return a.glow_frame_type ~= "FRAMESELECTOR" end })
    local hide = function() return a.glow_action == "hide" end
    args[k .. "gt"] = Select(d, a, "glow_type", "  kind", GLOWS, { hidden = hide })
    args[k .. "gu"] = Toggle(d, a, "use_glow_color", "  own colour", { hidden = hide })
    args[k .. "gc"] = ColorOpt(d, a, "glow_color", "    colour", { hidden = function() return hide() or not a.use_glow_color end })
    local lines = function() return hide() or (a.glow_type ~= "Pixel" and a.glow_type ~= "ACShine") end
    args[k .. "gl"] = Range(d, a, "glow_lines", "  lines", 1, 30, 1, { hidden = lines })
    args[k .. "gq"] = Range(d, a, "glow_frequency", "  speed", -2, 2, 0.05, { hidden = lines })
    local pix = function() return hide() or a.glow_type ~= "Pixel" end
    args[k .. "glen"] = Range(d, a, "glow_length", "  length", 1, 50, 1, { hidden = pix })
    args[k .. "gk"] = Range(d, a, "glow_thickness", "  thickness", 0.5, 10, 0.5, { hidden = pix })
    args[k .. "gb"] = Toggle(d, a, "glow_border", "  border", { hidden = pix })
    args[k .. "gs"] = Range(d, a, "glow_scale", "  scale", 0.05, 10, 0.05, { hidden = function() return hide() or a.glow_type ~= "ACShine" end })
    local offs = function() return hide() or a.glow_type == "buttonOverlay" end
    args[k .. "gx"] = Range(d, a, "glow_XOffset", "  outside by (across)", -50, 50, 1, { hidden = offs })
    args[k .. "gy"] = Range(d, a, "glow_YOffset", "  outside by (up)", -50, 50, 1, { hidden = offs })
end

-- ============================================================
-- CONDITIONS
-- ============================================================
local GLOBAL_CHECKS = { incombat = "In combat", hastarget = "Have a target", attackabletarget = "Target can be attacked",
    rangecheck = "Units in range", customcheck = "Custom code", alwaystrue = "Always" }
local YESNO = { [1] = "Yes", [0] = "No" }
local RANGE_KIND = { group = "Group members", enemies = "Enemies (nameplates)" }
local RANGE_OP = { ["<="] = "within", [">="] = "beyond" }
-- the operator field offers both kinds; "(yes/no)" clears it
local CHECK_OPS = { ["=="] = "=", ["~="] = "not", ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=",
    ["find('%s')"] = "contains", ["match('%s')"] = "matches (pattern)", [""] = "(yes / no)" }
local PROP_NAMES = { alpha = "Opacity", desaturate = "Grey", color = "Colour", barColor = "Bar colour",
    barColor2 = "Gradient end colour", enableGradient = "Gradient", gradientOrientation = "Gradient direction",
    backgroundColor = "Background colour", foregroundColor = "Fill colour", glowexternal = "Glow on a frame",
    sound = "Play a sound", chat = "Chat message", customcode = "Run code", displayText = "Text", inverse = "Inverse",
    displayIcon = "Icon", iconSource = "Icon from", zoom = "Zoom", width = "Width", height = "Height",
    xOffsetRelative = "Move across", yOffsetRelative = "Move up", cooldownSwipe = "Swipe", cooldownEdge = "Swipe edge",
    cooldownTextDisabled = "Hide countdown numbers", icon = "Show the icon", icon_color = "Icon tint",
    orientation = "Orientation", sparkColor = "Spark colour", sparkWidth = "Spark width", sparkHeight = "Spark height",
    texture = "Texture", textureInput = "Texture (path)", textureSource = "Texture from", fontSize = "Text size",
    mirror = "Mirror", rotation = "Rotation", desaturateForeground = "Grey fill", desaturateBackground = "Grey background",
    auraRotation = "Turn", crop_x = "Crop across", crop_y = "Crop up", progressSource = "Progress from",
    adjustedMin = "Scale starts at", adjustedMax = "Scale ends at" }

-- what a condition can change on this display: name -> { kind, label }
function O.ConditionProperties(d)
    local out = {}
    for p, info in pairs(E.Regions.properties[d.regionType] or {}) do
        out[p] = { info[1], PROP_NAMES[p] or p }
    end
    for i, s in ipairs(type(d.subRegions) == "table" and d.subRegions or {}) do
        local props = E.SubRegions.PropertiesOf(s)
        for p, kind in pairs(props or {}) do
            out["sub." .. i .. "." .. p] = { kind, (SUB_NAMES[s.type] or s.type) .. " " .. i .. ": " .. p }
        end
    end
    return out
end

-- the values a "list" property offers
local function ListValues(d, prop)
    local p = prop:match("^sub%.%d+%.(.+)$") or prop
    if p == "iconSource" then return TriggerChoices(d, { [-1] = "Automatic", [0] = "This one" }) end
    if p == "orientation" then return d.regionType == "progresstexture" and ORIENT_CIRCLE or ORIENT end
    if p == "gradientOrientation" then return GRADIENT end
    if p == "textureSource" then return TEXTURE_SOURCE end
    if p == "glowType" then return GLOWS end
    if p == "tick_placement_mode" then return TICK_MODES end
    return {}
end

local function StartValue(d, prop, kind)
    if kind == "sound" then return { sound_type = "Play", sound_channel = "Master" } end
    if kind == "chat" then return { message_type = "PRINT", message = "" } end
    if kind == "customcode" then return { custom = "" } end
    if kind == "glowexternal" then return { glow_action = "show", glow_frame_type = "UNITFRAME", glow_type = "buttonOverlay" } end
    local v = E.Conditions.BaseValue({ d = d, baseD = d, regionType = d.regionType }, prop)
    return E.Copy(v)
end

local function ChangeValueArgs(d, ch, kind, args, k)
    local prop = ch.property
    if kind == "bool" then
        args[k .. "v"] = Toggle(d, ch, "value", "  on")
    elseif kind == "number" then
        if prop == "alpha" or prop:match("model_alpha$") then
            args[k .. "v"] = Range(d, ch, "value", "  to", 0, 1, 0.01)
        else
            args[k .. "v"] = NumInput(d, ch, "value", "  to")
        end
    elseif kind == "color" then
        args[k .. "v"] = ColorOpt(d, ch, "value", "  to")
    elseif kind == "list" then
        args[k .. "v"] = Select(d, ch, "value", "  to", function() return ListValues(d, prop) end)
    elseif kind == "icon" or kind == "texture" or kind == "textureLSM" then
        args[k .. "v"] = IdInput(d, ch, "value", "  to")
    elseif kind == "string" then
        args[k .. "v"] = Input(d, ch, "value", "  to", { multiline = prop == "displayText" and 2 or nil })
    elseif kind == "progressSource" then
        args[k .. "v"] = { type = "select", name = "  to", order = N(),
            values = function()
                local out = { ["-1"] = "Automatic" }
                if E.ProgressSources then for key, label in pairs(E.ProgressSources(d) or {}) do out[key] = label end end
                return out
            end,
            get = function()
                local s = ch.value
                if type(s) ~= "table" then return "-1" end
                if tonumber(s[1]) and tonumber(s[1]) > 0 then return s[1] .. ":" .. tostring(s[2] or "") end
                return tostring(s[1])
            end,
            set = function(_, v)
                local t, p = tostring(v):match("^(%-?%d+):?(.*)$")
                ch.value = { tonumber(t) or -1, p or "" }
                Changed(d)
            end }
    elseif kind == "sound" then
        ch.value = type(ch.value) == "table" and ch.value or {}
        SoundArgs(d, ch.value, args, k, true)
    elseif kind == "chat" then
        ch.value = type(ch.value) == "table" and ch.value or {}
        MessageArgs(d, ch.value, args, k, "message_color")
    elseif kind == "customcode" then
        ch.value = type(ch.value) == "table" and ch.value or {}
        args[k .. "v"] = Code(d, ch.value, "custom", "  code", 8)
    elseif kind == "glowexternal" then
        ch.value = type(ch.value) == "table" and ch.value or {}
        GlowActionArgs(d, ch.value, args, k)
    end
end

-- one check (and, for "all of" / "any of", the checks inside it)
local function CheckArgs(d, ck, args, k, depth)
    args[k .. "tr"] = { type = "select", name = depth > 0 and "  check" or "Check", order = N(),
        values = function() return TriggerChoices(d, { [-1] = "Global", [-2] = "All / any of several" }) end,
        get = function() return tonumber(ck.trigger) or 1 end,
        set = function(_, v)
            ck.trigger = v
            if v == -2 then
                ck.variable = "AND"
                ck.checks = type(ck.checks) == "table" and ck.checks or { {}, {} }
                ck.op, ck.value = nil, nil
            elseif ck.variable == "AND" or ck.variable == "OR" then
                ck.variable, ck.checks = v == -1 and "incombat" or "show", nil
                ck.value = 1
            end
            Changed(d)
        end }
    local t = function() return tonumber(ck.trigger) end
    -- combinations
    args[k .. "andor"] = Select(d, ck, "variable", "  when", { AND = "All of these hold", OR = "Any of these holds" },
        { hidden = function() return t() ~= -2 end })
    if tonumber(ck.trigger) == -2 then
        ck.checks = type(ck.checks) == "table" and ck.checks or {}
        for j, sub in ipairs(ck.checks) do
            local g = {}
            CheckArgs(d, sub, g, k .. "c" .. j, depth + 1)
            g[k .. "c" .. j .. "rm"] = Button("Remove this check", function() table.remove(ck.checks, j) Changed(d) end)
            args[k .. "c" .. j] = Group(g)
        end
        args[k .. "addc"] = Button("Add a check", function() table.insert(ck.checks, { trigger = 1, variable = "show", value = 1 }) Changed(d) end)
        return
    end
    -- global checks
    args[k .. "gv"] = Select(d, ck, "variable", "  which", GLOBAL_CHECKS, { hidden = function() return t() ~= -1 end })
    local g = function(...)
        local set = {}
        for _, v in ipairs({ ... }) do set[v] = true end
        return function() return t() ~= -1 or not set[ck.variable] end
    end
    args[k .. "gb"] = Select(d, ck, "value", "  is", YESNO, { hidden = g("incombat", "hastarget", "attackabletarget") })
    args[k .. "rk"] = Select(d, ck, "type", "  count", RANGE_KIND, { hidden = g("rangecheck") })
    args[k .. "ro"] = Select(d, ck, "op_range", "  that are", RANGE_OP, { hidden = g("rangecheck") })
    args[k .. "rr"] = Input(d, ck, "range", "  yards", { hidden = g("rangecheck") })
    args[k .. "rop"] = Select(d, ck, "op", "  and that count is", OPERATORS, { hidden = g("rangecheck") })
    args[k .. "rv"] = Input(d, ck, "value", "  number", { hidden = g("rangecheck") })
    args[k .. "cc"] = Code(d, ck, "value", "  code (function(trigger states) ... return true end)", 6)
    args[k .. "cc"].hidden = g("customcheck")
    args[k .. "ce"] = Input(d, ck, "op", "  check again on (events, comma separated)", { hidden = g("customcheck"), width = "full" })
    -- a trigger's field
    local notTrigger = function() return (t() or 1) < 1 end
    if E.ConditionVariables then
        args[k .. "tv"] = Select(d, ck, "variable", "  field", function() return E.ConditionVariables(d, tonumber(ck.trigger) or 1) or {} end,
            { hidden = notTrigger })
    else
        args[k .. "tv"] = Input(d, ck, "variable", "  field (show, stacks, expirationTime, name...)", { hidden = notTrigger })
    end
    local isBool = function() return ck.op == nil or ck.op == "" end
    args[k .. "top"] = { type = "select", name = "  compare", order = N(), values = CHECK_OPS, hidden = notTrigger,
        get = function() return ck.op or "" end,
        set = function(_, v) if v == "" then ck.op = nil else ck.op = v end Changed(d) end }
    args[k .. "tb"] = Select(d, ck, "value", "  is", YESNO, { hidden = function() return notTrigger() or not isBool() end })
    args[k .. "tval"] = Input(d, ck, "value", "  value", { hidden = function() return notTrigger() or isBool() end })
end
O.CheckArgs = CheckArgs

function O.Conditions(d)
    order = 0
    local args = {}
    if E.IsGroup(d) then
        args.none = Desc("Groups have no conditions; each display inside has its own.")
        return { type = "group", args = args }
    end
    d.conditions = type(d.conditions) == "table" and d.conditions or {}
    local conds = d.conditions
    local props = O.ConditionProperties(d)
    local propValues = {}
    for p, info in pairs(props) do propValues[p] = info[2] end
    for i, c in ipairs(conds) do
        c.check = type(c.check) == "table" and c.check or {}
        c.changes = type(c.changes) == "table" and c.changes or {}
        local k = "c" .. i
        args[k .. "h"] = Header((c.linked and i > 1) and ("Else if (" .. i .. ")") or ("Condition " .. i))
        if i > 1 then
            args[k .. "ln"] = Toggle(d, c, "linked", "Else if: only when the condition above did not hold")
        end
        local g = {}
        CheckArgs(d, c.check, g, k, 0)
        args[k .. "chk"] = Group(g)
        for j, ch in ipairs(c.changes) do
            local kj = k .. "ch" .. j
            local cg = {}
            cg[kj .. "p"] = { type = "select", name = "Then change", order = N(), values = propValues,
                get = function() return ch.property end,
                set = function(_, v)
                    ch.property = v
                    local info = v and props[v]
                    ch.value = v and StartValue(d, v, info and info[1]) or nil
                    Changed(d)
                end }
            local info = ch.property and props[ch.property]
            if info then ChangeValueArgs(d, ch, info[1], cg, kj) end
            cg[kj .. "rm"] = Button("Remove this change", function() table.remove(c.changes, j) Changed(d) end)
            args[kj] = Group(cg)
        end
        args[k .. "addch"] = Button("Add a change", function()
            table.insert(c.changes, { property = "alpha", value = d.alpha or 1 })
            Changed(d)
        end, { hidden = function() return props.alpha == nil end })
        args[k .. "addch2"] = Button("Add a change", function()
            table.insert(c.changes, { property = "customcode", value = { custom = "" } })
            Changed(d)
        end, { hidden = function() return props.alpha ~= nil end })
        args[k .. "up"] = Button("Move up", function() conds[i], conds[i - 1] = conds[i - 1], conds[i] Changed(d) end,
            { hidden = function() return i == 1 end })
        args[k .. "dn"] = Button("Move down", function() conds[i], conds[i + 1] = conds[i + 1], conds[i] Changed(d) end,
            { hidden = function() return i == #conds end })
        args[k .. "rm"] = Button("Remove condition " .. i, function() table.remove(conds, i) Changed(d) end)
    end
    args.add = Button("Add a condition", function()
        table.insert(conds, { check = { trigger = 1, variable = "show", value = 1 }, changes = {} })
        Changed(d)
    end)
    return { type = "group", args = args }
end

-- ============================================================
-- ACTIONS
-- ============================================================
function O.Actions(d)
    order = 0
    local args = {}
    d.actions = type(d.actions) == "table" and d.actions or {}
    for _, phase in ipairs({ "init", "start", "finish" }) do
        d.actions[phase] = type(d.actions[phase]) == "table" and d.actions[phase] or {}
        local a = d.actions[phase]
        local label = phase == "init" and "When it is set up" or (phase == "start" and "When it shows" or "When it hides")
        args[phase .. "h"] = Header(label)
        if phase == "init" then
            args.initc = Toggle(d, a, "do_custom", "Run code once (aura_env set up)")
            args.initcode = Code(d, a, "custom", "  code", 10)
            args.initcode.hidden = function() return not a.do_custom end
            args.initl = Toggle(d, a, "do_custom_load", "Run code each time it loads")
            args.initlc = Code(d, a, "customOnLoad", "  code", 6)
            args.initlc.hidden = function() return not a.do_custom_load end
            args.initu = Toggle(d, a, "do_custom_unload", "Run code each time it unloads")
            args.inituc = Code(d, a, "customOnUnload", "  code", 6)
            args.inituc.hidden = function() return not a.do_custom_unload end
        else
            args[phase .. "msg"] = Toggle(d, a, "do_message", "Send a chat message")
            local mg = {}
            MessageArgs(d, a, mg, phase, "rgb")
            args[phase .. "msgg"] = Group(mg, function() return not a.do_message end)
            args[phase .. "snd"] = Toggle(d, a, "do_sound", "Play a sound")
            local sg = {}
            SoundArgs(d, a, sg, phase, false)
            args[phase .. "sndg"] = Group(sg, function() return not a.do_sound end)
            args[phase .. "stop"] = Toggle(d, a, "stop_sound", "Stop its sound")
            args[phase .. "fade"] = Toggle(d, a, "do_sound_fade", "  fade it out", { hidden = function() return not a.stop_sound end })
            args[phase .. "fadet"] = Range(d, a, "stop_sound_fade", "    over (seconds)", 0, 10, 0.1,
                { hidden = function() return not (a.stop_sound and a.do_sound_fade) end })
            args[phase .. "glow"] = Toggle(d, a, "do_glow", "Glow (or unglow) a frame")
            local gg = {}
            GlowActionArgs(d, a, gg, phase)
            args[phase .. "glowg"] = Group(gg, function() return not a.do_glow end)
            if phase == "finish" then
                args.finishhide = Toggle(d, a, "hide_all_glows", "Take away every glow it made")
            end
            args[phase .. "cust"] = Toggle(d, a, "do_custom", "Run code")
            args[phase .. "code"] = Code(d, a, "custom", "  code", 10)
            args[phase .. "code"].hidden = function() return not a.do_custom end
        end
    end
    return { type = "group", args = args }
end

-- ============================================================
-- ANIMATIONS
-- ============================================================
local ANIM_TYPES = { none = "None", preset = "Preset", custom = "Custom" }
local DURATION_TYPES = { seconds = "Seconds", relative = "Share of its timer" }
local EASE = { none = "None", easeIn = "Ease in", easeOut = "Ease out", easeOutIn = "Ease in and out" }
local MOVE_TYPES = { straightTranslate = "Straight", circle = "Circle", spiral = "Spiral", spiralandpulse = "Spiral in and out",
    shake = "Shake", bounce = "Bounce", bounceDecay = "Bounce, dying away", custom = "Custom code" }
local SCALE_TYPES = { straightScale = "Straight", pulse = "Pulse", fauxspin = "Spin", fauxflip = "Flip", custom = "Custom code" }
local ALPHA_TYPES = { straight = "Straight", alphaPulse = "Pulse", hide = "Hide", custom = "Custom code" }
local ROTATE_TYPES = { straight = "Straight", backandforth = "Back and forth", wobble = "Wobble", custom = "Custom code" }
local COLOR_TYPES = { straightColor = "Straight (RGB)", straightHSV = "Gradient", pulseColor = "Pulse (RGB)",
    pulseHSV = "Gradient pulse", custom = "Custom code" }
local PRESET_NAMES = {
    start = { slidetop = "Slide from above", slideleft = "Slide from the left", slideright = "Slide from the right",
        slidebottom = "Slide from below", fade = "Fade in", shrink = "Grow", grow = "Shrink", spiral = "Spiral",
        bounceDecay = "Bounce", starShakeDecay = "Star shake" },
    main = { shake = "Shake", spin = "Spin", flip = "Flip", wobble = "Wobble", pulse = "Pulse", alphaPulse = "Flash",
        rotateClockwise = "Turn right", rotateCounterClockwise = "Turn left", spiralandpulse = "Spiral", orbit = "Orbit",
        bounce = "Bounce" },
    finish = { slidetop = "Slide up", slideleft = "Slide left", slideright = "Slide right", slidebottom = "Slide down",
        fade = "Fade out", shrink = "Shrink", grow = "Grow", spiral = "Spiral", bounceDecay = "Bounce",
        starShakeDecay = "Star shake" },
}
O.PRESET_NAMES = PRESET_NAMES

function O.Animations(d)
    order = 0
    local args = {}
    d.animation = type(d.animation) == "table" and d.animation or {}
    for _, phase in ipairs({ "start", "main", "finish" }) do
        d.animation[phase] = type(d.animation[phase]) == "table" and d.animation[phase] or { type = "none" }
        local an = d.animation[phase]
        local p = phase
        args[p .. "h"] = Header(phase == "start" and "Showing" or (phase == "main" and "While shown" or "Hiding"))
        args[p .. "t"] = Select(d, an, "type", "Animation", ANIM_TYPES)
        local off = function() return an.type == nil or an.type == "none" end
        local notCustom = function() return an.type ~= "custom" end
        args[p .. "p"] = Select(d, an, "preset", "  which", PRESET_NAMES[phase], { hidden = function() return an.type ~= "preset" end })
        args[p .. "dt"] = Select(d, an, "duration_type", "  length in", DURATION_TYPES, { hidden = off })
        args[p .. "d"] = Range(d, an, "duration", "  length", 0.01, 30, 0.01, { hidden = off })
        args[p .. "e"] = Select(d, an, "easeType", "  easing", EASE, { hidden = notCustom })
        args[p .. "es"] = Range(d, an, "easeStrength", "    strength", 1, 10, 0.5, { hidden = function() return notCustom() or (an.easeType or "none") == "none" end })
        local parts = {
            { "use_translate", "Move", "translateType", MOVE_TYPES, "translateFunc", function(g, k)
                g[k .. "x"] = Range(d, an, "x", "    across", -500, 500, 1)
                g[k .. "y"] = Range(d, an, "y", "    up", -500, 500, 1)
            end },
            { "use_alpha", "Fade", "alphaType", ALPHA_TYPES, "alphaFunc", function(g, k)
                g[k .. "a"] = Range(d, an, "alpha", "    to opacity", 0, 1, 0.01)
            end },
            { "use_scale", "Zoom", "scaleType", SCALE_TYPES, "scaleFunc", function(g, k)
                g[k .. "sx"] = Range(d, an, "scalex", "    width times", -5, 5, 0.05)
                g[k .. "sy"] = Range(d, an, "scaley", "    height times", -5, 5, 0.05)
            end },
            { "use_rotate", "Turn", "rotateType", ROTATE_TYPES, "rotateFunc", function(g, k)
                g[k .. "r"] = Range(d, an, "rotate", "    by degrees", -360, 360, 1)
            end },
            { "use_color", "Colour", "colorType", COLOR_TYPES, "colorFunc", function(g, k)
                g[k .. "c"] = { type = "color", name = "    to colour", order = N(), hasAlpha = true,
                    get = function() return an.colorR or 1, an.colorG or 1, an.colorB or 1, an.colorA or 1 end,
                    set = function(_, r, gg, b, a) an.colorR, an.colorG, an.colorB, an.colorA = r, gg, b, a or 1 Changed(d) end }
            end },
        }
        for i, part in ipairs(parts) do
            local k = p .. "c" .. i
            args[k .. "on"] = Toggle(d, an, part[1], "  " .. part[2], { hidden = notCustom })
            local g = {}
            g[k .. "ty"] = Select(d, an, part[3], "    curve", part[4])
            g[k .. "fn"] = Code(d, an, part[5], "    curve code", 6)
            g[k .. "fn"].hidden = function() return an[part[3]] ~= "custom" end
            part[6](g, k)
            args[k] = Group(g, function() return notCustom() or not an[part[1]] end)
        end
    end
    return { type = "group", args = args }
end

-- ============================================================
-- LOAD
-- ============================================================
local LOAD_NAMES = { combat = "In combat", never = "Never (switched off)", alive = "Alive", encounter = "In a boss fight",
    pvpmode = "PvP flagged", vehicle = "On a flight path", mounted = "Mounted", hardcore = "Hardcore realm",
    engraving = "Season of Discovery (runes)", class = "Class", talent = "Talent", talent2 = "And talent",
    talent3 = "And talent", spellknown = "Spell known", not_spellknown = "Spell not known",
    namerealm = "Only these characters (Name, Name-Realm, -Realm)", ignoreNameRealm = "Not these characters",
    guildcheck = "Guild", race = "Race", faction = "Faction", level = "Level", role = "Assigned role",
    raid_role = "Raid role", ingroup = "Group type", groupSize = "Group size", group_leader = "Leader / assist",
    zone = "Zone names", zoneIds = "Location ids (map ids; g group, c continent, a area, i instance, - not)",
    encounterid = "Boss fight ids", size = "Instance size", itemequiped = "Item equipped (ids or names)",
    not_itemequiped = "Item not equipped", itemtypeequipped = "Weapon kind equipped",
    item_bonusid_equipped = "Item bonus id equipped", not_item_bonusid_equipped = "Item bonus id not equipped" }
local VALUE_NAMES = {
    class = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
        SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" },
    race = { Human = "Human", Orc = "Orc", Dwarf = "Dwarf", NightElf = "Night Elf", Scourge = "Undead", Tauren = "Tauren",
        Gnome = "Gnome", Troll = "Troll" },
    faction = { Alliance = "Alliance", Horde = "Horde", Neutral = "Neutral" },
    role = { TANK = "Tank", DAMAGER = "Damage", HEALER = "Healer" },
    raid_role = { MAINTANK = "Main tank", MAINASSIST = "Main assist", NONE = "Other" },
    ingroup = { solo = "Not in a group", group = "In a party", raid = "In a raid" },
    group_leader = { LEADER = "Leader", ASSIST = "Assist", NONE = "Neither" },
    size = { none = "No instance", party = "5-man dungeon", ten = "10-man raid", twenty = "20-man raid",
        twentyfive = "25-man raid", fortyman = "40-man raid", pvp = "Battleground" },
}
O.LOAD_NAMES = LOAD_NAMES

local function TalentValues()
    local out = {}
    if GetTalentInfo then
        for tab = 1, (GetNumTalentTabs and GetNumTalentTabs() or 3) do
            for num = 1, (GetNumTalents and GetNumTalents(tab) or 20) do
                local ok, name = pcall(GetTalentInfo, tab, num)
                if ok and name then out[(tab - 1) * 20 + num] = name end
            end
        end
    end
    return out
end

local function WeaponValues()
    local out = {}
    local info = (C_Item and C_Item.GetItemSubClassInfo) or GetItemSubClassInfo
    for key in pairs(E.Load.VALUES.itemtypeequipped) do
        local sub = key % 256
        local ok, name = info and pcall(info, (key - sub) / 256, sub)
        out[key] = (ok and name) or ("Kind " .. key)
    end
    return out
end

local function Tri(d, ld, key, name)
    return Select(d, ld, "use_" .. key, name, { [1] = "Either", [2] = "Yes", [3] = "No" }, {
        get = function() local v = ld["use_" .. key] if v == true then return 2 elseif v == false then return 3 end return 1 end,
        set = function(_, v)
            if v == 2 then ld["use_" .. key] = true elseif v == 3 then ld["use_" .. key] = false else ld["use_" .. key] = nil end
            Changed(d)
        end })
end

-- a multiselect: ignored, one value, or any of several
local function Multi(d, ld, key, name, values, args, k)
    args[k .. "m"] = Select(d, ld, "use_" .. key, name, { [1] = "Any", [2] = "Exactly this", [3] = "One of these" }, {
        get = function() local v = ld["use_" .. key] if v == true then return 2 elseif v == false then return 3 end return 1 end,
        set = function(_, v)
            ld[key] = type(ld[key]) == "table" and ld[key] or {}
            if v == 2 then ld["use_" .. key] = true
            elseif v == 3 then
                ld["use_" .. key] = false
                ld[key].multi = type(ld[key].multi) == "table" and ld[key].multi or {}
            else ld["use_" .. key] = nil end
            Changed(d)
        end })
    args[k .. "s"] = { type = "select", name = "  value", order = N(), values = values,
        hidden = function() return ld["use_" .. key] ~= true end,
        get = function() return type(ld[key]) == "table" and ld[key].single or nil end,
        set = function(_, v) ld[key] = type(ld[key]) == "table" and ld[key] or {} ld[key].single = v Changed(d) end }
    args[k .. "v"] = { type = "multiselect", name = "  values", order = N(), values = values,
        hidden = function() return ld["use_" .. key] ~= false end,
        get = function(_, kk) local t = ld[key] return type(t) == "table" and type(t.multi) == "table" and t.multi[kk] or false end,
        set = function(_, kk, v)
            ld[key] = type(ld[key]) == "table" and ld[key] or {}
            ld[key].multi = type(ld[key].multi) == "table" and ld[key].multi or {}
            ld[key].multi[kk] = v and true or nil
            Changed(d)
        end }
end

-- text, number lists, spells, items
local function TextField(d, ld, key, name, args, k)
    args[k .. "u"] = Toggle(d, ld, "use_" .. key, name)
    args[k .. "v"] = Input(d, ld, key, "  value", { multiline = 2, width = "full", hidden = function() return not ld["use_" .. key] end })
end

local function NumberField(d, ld, key, name, args, k)
    args[k .. "u"] = Toggle(d, ld, "use_" .. key, name)
    for i = 1, 2 do
        local hidden = function() return not ld["use_" .. key] end
        args[k .. "o" .. i] = { type = "select", name = i == 1 and "  is" or "  and is", order = N(), values = OPERATORS, hidden = hidden,
            get = function() local t = ld[key .. "_operator"] return type(t) == "table" and t[i] or (i == 1 and t or nil) end,
            set = function(_, v)
                if type(ld[key .. "_operator"]) ~= "table" then ld[key .. "_operator"] = { ld[key .. "_operator"] } end
                ld[key .. "_operator"][i] = v
                Changed(d)
            end }
        args[k .. "v" .. i] = { type = "input", name = "  number", order = N(), hidden = hidden,
            get = function() local t = ld[key] return tostring((type(t) == "table" and t[i]) or (i == 1 and type(t) ~= "table" and t) or "") end,
            set = function(_, v)
                if type(ld[key]) ~= "table" then ld[key] = { ld[key] } end
                ld[key][i] = v ~= "" and v or nil
                -- keep it a plain list (the format's own clean-up does the same)
                local list, ops = {}, {}
                for j = 1, 2 do
                    if ld[key][j] ~= nil then
                        list[#list + 1] = ld[key][j]
                        ops[#ops + 1] = type(ld[key .. "_operator"]) == "table" and ld[key .. "_operator"][j] or "=="
                    end
                end
                ld[key], ld[key .. "_operator"] = list, ops
                Changed(d)
            end }
    end
end

local function SpellField(d, ld, key, name, args, k)
    args[k .. "u"] = Toggle(d, ld, "use_" .. key, name)
    args[k .. "v"] = IdInput(d, ld, key, "  spell id", { hidden = function() return not ld["use_" .. key] end })
    args[k .. "x"] = Toggle(d, ld, "use_exact_" .. key, "  only this rank", { hidden = function() return not ld["use_" .. key] end })
end

local function ItemField(d, ld, key, name, args, k)
    args[k .. "u"] = Toggle(d, ld, "use_" .. key, name)
    args[k .. "v"] = { type = "input", name = "  items (comma separated)", order = N(), width = "full",
        hidden = function() return not ld["use_" .. key] end,
        get = function()
            local t = {}
            for _, v in ipairs(type(ld[key]) == "table" and ld[key] or {}) do t[#t + 1] = tostring(v) end
            return table.concat(t, ", ")
        end,
        set = function(_, v)
            local out = {}
            for part in tostring(v):gmatch("[^,]+") do
                part = part:gsub("^%s+", ""):gsub("%s+$", "")
                if part ~= "" then out[#out + 1] = tonumber(part) or part end
            end
            ld[key] = out
            Changed(d)
        end }
end

function O.Load(d)
    order = 0
    local args = {}
    if E.IsGroup(d) then
        args.note = Desc("A group loads when anything inside it does. Never below switches off everything inside.")
        args.never = { type = "toggle", name = "Never (switch everything inside off)", order = N(),
            get = function()
                for _, c in ipairs(E.Descendants(d.id)) do
                    local cd = E.data[c]
                    if cd and not E.IsGroup(cd) and not (cd.load and cd.load.use_never) then return false end
                end
                return true
            end,
            set = function(_, v)
                for _, c in ipairs(E.Descendants(d.id)) do
                    local cd = E.data[c]
                    if cd and not E.IsGroup(cd) then
                        cd.load = type(cd.load) == "table" and cd.load or {}
                        cd.load.use_never = v or nil
                        if E.Rebuild then E.Rebuild(c) end
                    end
                end
            end }
        return { type = "group", args = args }
    end
    d.load = type(d.load) == "table" and d.load or {}
    local ld = d.load
    for _, f in ipairs(E.Load.FIELDS) do
        local key, kind = f[1], f[2]
        local name = LOAD_NAMES[key] or key
        local k = "l_" .. key
        if kind == "toggle" then
            args[k] = Toggle(d, ld, "use_" .. key, name)
        elseif kind == "tristate" then
            args[k] = Tri(d, ld, key, name)
        elseif kind == "multiselect" then
            local values
            if key:match("^talent") then values = TalentValues
            elseif key == "itemtypeequipped" then values = WeaponValues
            else values = VALUE_NAMES[key] end
            Multi(d, ld, key, name, values or {}, args, k)
            -- the second and third talent only count once the first is set
            if key == "talent2" or key == "talent3" then
                for _, suffix in ipairs({ "m", "s", "v" }) do
                    local o = args[k .. suffix]
                    local own = o.hidden
                    o.hidden = function(...)
                        local first = ld.use_talent ~= nil or (key == "talent3" and ld.use_talent2 ~= nil)
                        if not first then return true end
                        return own and own(...) or false
                    end
                end
            end
            if key:match("^talent") then
                args[k .. "x"] = Select(d, ld, key .. "_extraOption", "  when", { [1] = "Picked", [3] = "Not picked" },
                    { hidden = function() return ld["use_" .. key] == nil end })
            end
        elseif kind == "string" then
            TextField(d, ld, key, name, args, k)
        elseif kind == "number" then
            NumberField(d, ld, key, name, args, k)
        elseif kind == "spell" then
            SpellField(d, ld, key, name, args, k)
        elseif kind == "item" then
            ItemField(d, ld, key, name, args, k)
        end
    end
    return { type = "group", args = args }
end

-- ============================================================
-- CUSTOM OPTIONS (what a pack's author lets you set)
-- ============================================================
function O.Config(d)
    order = 0
    local args = {}
    local opts = type(d.authorOptions) == "table" and d.authorOptions or {}
    if #opts == 0 then
        args.none = Desc("This display has no settings of its own.")
        return { type = "group", args = args }
    end
    d.config = type(d.config) == "table" and d.config or {}
    local cfg = d.config
    local function After()
        if E.Env then E.Env.Reset(d.id) end
        Changed(d)
    end
    for i, opt in ipairs(opts) do
        local key = opt.key
        local k = "o" .. i
        local name = opt.name or key or ("Option " .. i)
        local ty = opt.type
        local function Get() local v = cfg[key] if v == nil then v = opt.default end return v end
        local function Set(_, v) cfg[key] = v After() end
        if ty == "header" then
            args[k] = Header(opt.text or name)
        elseif ty == "description" then
            args[k] = Desc(opt.text or "")
        elseif key then
            if ty == "toggle" then
                args[k] = { type = "toggle", name = name, desc = opt.desc, order = N(), get = Get, set = Set }
            elseif ty == "number" or ty == "range" then
                args[k] = { type = "range", name = name, desc = opt.desc, order = N(), min = tonumber(opt.min) or 0,
                    max = tonumber(opt.max) or math.max(100, (tonumber(Get()) or 0) * 2), step = tonumber(opt.step) or 1,
                    get = function() return tonumber(Get()) end, set = Set }
            elseif ty == "select" then
                local vals = {}
                for vi, v in ipairs(type(opt.values) == "table" and opt.values or {}) do vals[vi] = tostring(v) end
                args[k] = { type = "select", name = name, desc = opt.desc, order = N(), values = vals, get = Get, set = Set }
            elseif ty == "multiselect" then
                local vals = {}
                for vi, v in ipairs(type(opt.values) == "table" and opt.values or {}) do vals[vi] = tostring(v) end
                args[k] = { type = "multiselect", name = name, desc = opt.desc, order = N(), values = vals,
                    get = function(_, vk) local t = Get() return type(t) == "table" and t[vk] or false end,
                    set = function(_, vk, v)
                        local t = cfg[key]
                        if type(t) ~= "table" then t = E.Copy(opt.default) if type(t) ~= "table" then t = {} end cfg[key] = t end
                        t[vk] = v After()
                    end }
            elseif ty == "color" then
                args[k] = { type = "color", name = name, desc = opt.desc, order = N(), hasAlpha = true,
                    get = function() return E.Color(Get()) end,
                    set = function(_, r, g, b, a) cfg[key] = { r, g, b, a or 1 } After() end }
            else
                args[k] = { type = "input", name = name, desc = opt.desc, order = N(), multiline = opt.multiline and 4 or nil,
                    get = function() local v = Get() return v ~= nil and tostring(v) or "" end, set = Set }
            end
        end
    end
    args.reset = { type = "execute", name = "Back to the author's defaults", order = N(), func = function()
        d.config = {} After() end }
    return { type = "group", args = args }
end

-- ============================================================
-- GROUP LAYOUT
-- ============================================================
local GROW = { DOWN = "Down", UP = "Up", LEFT = "Left", RIGHT = "Right", HORIZONTAL = "Centred row",
    VERTICAL = "Centred column", CIRCLE = "Circle (anticlockwise)", COUNTERCIRCLE = "Circle (clockwise)",
    GRID = "Grid", CUSTOM = "Custom code" }
local SORT = { none = "In order", ascending = "Least time left first", descending = "Most time left first",
    hybrid = "Marked ones first or last, then by time", custom = "Custom code" }
local GRID = { RU = "Right, then up", UR = "Up, then right", LU = "Left, then up", UL = "Up, then left",
    RD = "Right, then down", DR = "Down, then right", LD = "Left, then down", DL = "Down, then left",
    HD = "Centred row, then down", HU = "Centred row, then up", VR = "Centred column, then right",
    VL = "Centred column, then left", DH = "Down, then centred row", UH = "Up, then centred row",
    LV = "Left, then centred column", RV = "Right, then centred column", HV = "Centred both ways (row first)",
    VH = "Centred both ways (column first)" }
local CENTER_H = { LR = "Left to right", RL = "Right to left", CLR = "From the middle, left first", CRL = "From the middle, right first" }
local CONSTANT = { RADIUS = "Keep the radius", SPACING = "Keep the spacing", ANGLE = "Keep the angle and radius" }
local PER_UNIT = { UNITFRAME = "Raid / unit frames", NAMEPLATE = "Nameplates", CUSTOM = "Custom code" }
local HYBRID_POS = { hybridFirst = "Marked first", hybridLast = "Marked last" }
local HYBRID_SORT = { ascending = "Least time left first", descending = "Most time left first" }

-- the point children line up by, from the grow direction and alignment
-- (the format keeps the group's selfPoint in step with these)
local SELF_POINT = {
    RIGHT = { LEFT = "TOPLEFT", RIGHT = "BOTTOMLEFT", CENTER = "LEFT" },
    LEFT = { LEFT = "TOPRIGHT", RIGHT = "BOTTOMRIGHT", CENTER = "RIGHT" },
    UP = { LEFT = "BOTTOMLEFT", RIGHT = "BOTTOMRIGHT", CENTER = "BOTTOM" },
    DOWN = { LEFT = "TOPLEFT", RIGHT = "TOPRIGHT", CENTER = "TOP" },
    HORIZONTAL = { LEFT = "TOP", RIGHT = "BOTTOM", CENTER = "CENTER" },
    VERTICAL = { LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER" },
}
function O.GroupSelfPoint(d)
    local t = SELF_POINT[d.grow or "DOWN"]
    if t then return t[d.align or "CENTER"] or t.CENTER end
    return d.selfPoint or "CENTER"
end

function O.Group(d)
    order = 0
    local args = {}
    if d.regionType ~= "dynamicgroup" then
        args.note = Desc("A plain group: its displays keep their own places relative to it. Move the group with the Display tab.")
        return { type = "group", args = args }
    end
    local function Re(fn)
        return function(...)
            fn(...)
            d.selfPoint = O.GroupSelfPoint(d)
            Changed(d)
        end
    end
    args.grow = Select(d, d, "grow", "Grow", GROW)
    args.grow.set = Re(function(_, v) d.grow = v end)
    local line = function() local g = d.grow or "DOWN" return g == "GRID" or g == "CIRCLE" or g == "COUNTERCIRCLE" or g == "CUSTOM" end
    local round = function() return d.grow ~= "CIRCLE" and d.grow ~= "COUNTERCIRCLE" end
    args.align = Select(d, d, "align", "Line up on", { LEFT = "Left / top", CENTER = "Centre", RIGHT = "Right / bottom" },
        { hidden = function() return line() end })
    args.align.set = Re(function(_, v) d.align = v end)
    args.centerType = Select(d, d, "centerType", "Fill order", CENTER_H,
        { hidden = function() return d.grow ~= "HORIZONTAL" and d.grow ~= "VERTICAL" end })
    args.space = Range(d, d, "space", "Space between", -50, 200, 1, { hidden = function() return d.grow == "GRID" or d.grow == "CUSTOM" end })
    args.stagger = Range(d, d, "stagger", "Stagger", -50, 50, 1, { hidden = line })
    args.gridType = Select(d, d, "gridType", "Fill", GRID, { hidden = function() return d.grow ~= "GRID" end })
    args.gridWidth = Range(d, d, "gridWidth", "Per line", 1, 40, 1, { hidden = function() return d.grow ~= "GRID" end })
    args.rowSpace = Range(d, d, "rowSpace", "Row space", -50, 200, 1, { hidden = function() return d.grow ~= "GRID" end })
    args.columnSpace = Range(d, d, "columnSpace", "Column space", -50, 200, 1, { hidden = function() return d.grow ~= "GRID" end })
    args.constantFactor = Select(d, d, "constantFactor", "As more show", CONSTANT, { hidden = round })
    args.radius = Range(d, d, "radius", "Radius", 0, 1000, 1, { hidden = function() return round() or d.constantFactor == "SPACING" end })
    args.rotation = Range(d, d, "rotation", "Start angle", 0, 360, 1, { hidden = round })
    args.stepAngle = Range(d, d, "stepAngle", "Angle between", 0, 360, 1, { hidden = function() return round() or d.constantFactor ~= "ANGLE" end })
    args.fullCircle = Toggle(d, d, "fullCircle", "Whole circle", { hidden = function() return round() or d.constantFactor == "ANGLE" end })
    args.arcLength = Range(d, d, "arcLength", "  arc (degrees)", 0, 360, 1, { hidden = function() return round() or d.fullCircle or d.constantFactor == "ANGLE" end })
    args.customGrow = Code(d, d, "customGrow", "Grow code: function(newPositions, activeRegions)", 8)
    args.customGrow.hidden = function() return d.grow ~= "CUSTOM" end
    args.growOn = Input(d, d, "growOn", "  run again on (events)", { hidden = function() return d.grow ~= "CUSTOM" end })
    args.sortHeader = Header("Order")
    args.sort = Select(d, d, "sort", "Order", SORT)
    args.hybridPosition = Select(d, d, "hybridPosition", "  marked ones", HYBRID_POS, { hidden = function() return d.sort ~= "hybrid" end })
    args.hybridSortMode = Select(d, d, "hybridSortMode", "  then", HYBRID_SORT, { hidden = function() return d.sort ~= "hybrid" end })
    args.sortHybrid = { type = "multiselect", name = "  marked", order = N(),
        hidden = function() return d.sort ~= "hybrid" end,
        values = function() local t = {} for _, c in ipairs(E.children[d.id] or {}) do t[c] = c end return t end,
        get = function(_, k) return type(d.sortHybridTable) == "table" and d.sortHybridTable[k] or false end,
        set = function(_, k, v)
            d.sortHybridTable = type(d.sortHybridTable) == "table" and d.sortHybridTable or {}
            d.sortHybridTable[k] = v and true or nil
            Changed(d)
        end }
    args.customSort = Code(d, d, "customSort", "Sort code: function(a, b) return true when a goes first end", 6)
    args.customSort.hidden = function() return d.sort ~= "custom" end
    args.sortOn = Input(d, d, "sortOn", "  run again on (events)", { hidden = function() return d.sort ~= "custom" end })
    args.useLimit = Toggle(d, d, "useLimit", "At most")
    args.limit = Range(d, d, "limit", "  this many", 1, 100, 1, { hidden = function() return not d.useLimit end })
    args.animate = Toggle(d, d, "animate", "Slide into new places")
    args.unitHeader = Header("Per unit")
    args.useAnchorPerUnit = Toggle(d, d, "useAnchorPerUnit", "One cluster on each unit")
    args.anchorPerUnit = Select(d, d, "anchorPerUnit", "  on their", PER_UNIT, { hidden = function() return not d.useAnchorPerUnit end })
    args.customAnchorPerUnit = Code(d, d, "customAnchorPerUnit", "  code: function(frames, activeRegions)", 6)
    args.customAnchorPerUnit.hidden = function() return not (d.useAnchorPerUnit and d.anchorPerUnit == "CUSTOM") end
    args.anchorOn = Input(d, d, "anchorOn", "  run again on (events)", { hidden = function() return not (d.useAnchorPerUnit and d.anchorPerUnit == "CUSTOM") end })
    return { type = "group", args = args }
end
