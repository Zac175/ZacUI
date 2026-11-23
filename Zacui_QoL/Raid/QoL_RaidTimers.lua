-- QoL_RaidTimers - pull and break timers as bars that survive a reload,
-- a relog or a character swap.
-- Part of ZacUI; load order is set by the TOC.
--
-- Sources: DBM and BigWigs pull / break messages, the raid packs' break
-- call, and Blizzard's own /countdown. ZacUI's own /pull and /break
-- (Zacui_RaidTools) send all of those at once. Each running timer is saved by its end in server time, so
-- after a reload or a relog the bar comes back with the right time left.
-- A TIMER THAT STARTED WITHOUT YOU (2026-11-22, Zac: "break pull timers
-- etc. dont show if i join the group late or im logged out when its
-- started needs to work from ingame timer dbm bigwigs etc."). Logging in,
-- reloading or joining a group, ZacUI asks for what is running:
--   * the group, in ZacUI's own words: any ZacUI client with a timer
--     running answers, whatever started it (DBM, BigWigs, /countdown);
--   * the group's DBM clients, in DBM's words: DBM answers a group
--     member's whispered timer request with the time left on its break
--     bar (and a break BigWigs called is on every DBM client's bar too,
--     since BigWigs sends its break in DBM's words as well). Nobody says
--     who runs DBM, so the leader, the assistants and anyone seen sending
--     DBM messages are asked first, a few at a time, until one answers;
--   * the raid packs' break status lines, when another raider's sends one;
--   * the game's own countdown says how much is left of how much when it
--     reaches a client partway (START_PLAYER_COUNTDOWN's time left and
--     total), and the bar starts there.
-- BigWigs itself has nothing to ask: it keeps its break through its own
-- relog and tells nobody who joins. A break called in a group with only
-- BigWigs users and no ZacUI client cannot be recovered by anyone.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local QoL = ns.QoL
local UI = ns.UI

local RT = {}
local SYNC = "ZUITimers"
-- DBM's prefix differs by client flavour and version; the body is the
-- same tab-separated line with "PT" / "BT" and the seconds in it (see
-- FromDBM), so every one Zacui_RaidTools listens on is read here too.
local DBM_PREFIXES = { D4 = true, D4C = true, D5 = true, D5C = true, D5WC = true, D5WCC = true, D5WCWC = true }
local GROUP_CHANNELS = { RAID = true, PARTY = true, INSTANCE_CHAT = true }
local KINDS = { "brk", "pull" }        -- top to bottom
local LABEL = { brk = "Break", pull = "Pull" }

-- WHAT WAS ASKED AND WHAT CAME BACK (2026-11-22, Zac: "the pull timer
-- stuff still not working"). The last sixty things this file asked, was
-- told or refused, each with the second it happened: `/zui timers` prints
-- them, so what the game and the other clients really did can be read
-- instead of guessed. Written only on those rare moments (never per DBM
-- message), kept for the session.
local trace, TRACE_MAX = {}, 60
local function Trace(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then line = tostring(fmt) end
    trace[#trace + 1] = string.format("%.1f  %s", GetTime(), line)
    if #trace > TRACE_MAX then table.remove(trace, 1) end
end
RT.Trace = Trace
function RT.TraceLines() return trace end
local function Vis(msg) return (tostring(msg):gsub("\t", "<tab>")) end

local COLOUR = { brk = "blue", pull = "red" }

-- ============================================================
-- SETTINGS
-- ============================================================
-- Look and motion. nil in a colour, font or the texture means "as it has
-- always been": the palette's red and blue, ZacUI's bar texture, ZacUI's
-- font at a size that follows the bar's height.
RT.DEFAULTS = {
    texture = nil,
    pullColor = nil, breakColor = nil,   -- nil: the palette's red / blue
    bgColor = nil,                       -- nil: dark, with a hint of the bar's colour
    textColor = nil,                     -- nil: the palette's text colour
    warnColor = nil,                     -- nil: the palette's gold
    labelFont = nil,                     -- nil: ZacUI's font, 55% of the bar's height
    timeFont = nil,                      -- nil: ZacUI's font, 60% of the bar's height
    icon = true, spark = true, sheen = true, sender = true,
    gap = 4,                             -- between the two bars
    grow = "down",                       -- the break bar on top, the pull under it
    warnAt = 5,                          -- the last seconds of a pull: gold time ...
    warnPulse = true,                    -- ... and the bar breathes
    showAnim = { style = "fade", duration = 0.2, delay = 0, easing = "linear", dir = "up", distance = 12 },
    hideAnim = { style = "fade", duration = 0.35, delay = 0, easing = "linear", dir = "up", distance = 12 },
    glide = 25,                          -- percent of the way per frame when a bar moves up
}

local function DB()
    local q = QoL.DB()
    q.raidTimers = q.raidTimers or {}
    local d = q.raidTimers
    if d.enabled == nil then d.enabled = true end
    if d.pull == nil then d.pull = true end
    if d.brk == nil then d.brk = true end
    if d.sync == nil then d.sync = true end
    -- (ask the group's DBM clients for a running break as well)
    if d.askMods == nil then d.askMods = true end
    if d.width == nil then d.width = 240 end
    if d.height == nil then d.height = 20 end
    -- Blizzard's own countdown (the ornate bar /countdown shows and the
    -- big numbers at its end) is hidden while ours runs - one pull timer
    if d.hideBlizz == nil then d.hideBlizz = true end
    d.active = d.active or {}          -- [kind] = { endAt = server time, dur, sender }
    if ns.FillDefaults then ns.FillDefaults(d, RT.DEFAULTS)
    else for k, v in pairs(RT.DEFAULTS) do if d[k] == nil then d[k] = v end end end
    return d
end
RT.DB = DB

-- ============================================================
-- THE BARS
-- ============================================================
local holder
local bars = {}

local function BarTexture()
    local M = ns.Media
    return (M and M.BarPath and M.BarPath()) or ns.FLAT
end

local function SetFont(fs, size)
    ns.HouseFont(fs, size, "OUTLINE", STANDARD_TEXT_FONT)
end

local function Holder()
    if holder then return holder end
    holder = CreateFrame("Frame", "ZacUIRaidTimers", UIParent)
    holder:SetSize(240, 44)
    holder:SetFrameStrata("MEDIUM")
    holder:SetClampedToScreen(true)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -180)
    if ns.RegisterMover then
        ns.RegisterMover("raidtimers", "Pull & break timers", function() return holder end, "TOP", 0, -180, nil, {
            -- (its bars' width and height in Edit Mode: the page's own two settings)
            sizes = function()
                local function E(label, key, lo, hi, step, def)
                    return { label = label, unit = "px", min = lo, max = hi, step = step, fine = 1, def = def,
                        get = function() return tonumber(DB()[key]) or def end,
                        set = function(v) DB()[key] = v if RT.Layout then RT.Layout() end end }
                end
                return { E("Width", "width", 120, 400, 10, 240), E("Height", "height", 12, 36, 1, 20) }
            end })
        if ns.ApplyMover then ns.ApplyMover("raidtimers") end
    end
    return holder
end

local ICON = {
    brk = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    pull = "Interface\\Icons\\Ability_Warrior_Charge",
}
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local GAP = 4                        -- between the two bars

-- a vertical white fade (top -> bottom alpha), on any client
local function Sheen(tex, topA, botA)
    tex:SetTexture(ns.FLAT)
    tex:SetBlendMode("ADD")
    if tex.SetGradient and CreateColor
        and pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(1, 1, 1, botA), CreateColor(1, 1, 1, topA)) then
        return
    end
    tex:SetVertexColor(1, 1, 1, (topA + botA) / 2)
end

-- One bar: an icon square on the left, a fill with a sheen and a glowing
-- leading edge, the caller's name in grey after the label, the time on
-- the right. NewBar makes one anywhere (the settings preview makes its
-- own); StyleBar dresses it from the settings; FillBar draws a moment of
-- a countdown on it. The live bars and the preview's go through all three.
function RT.NewBar(kind, parent)
    local f = CreateFrame("Frame", nil, parent)
    f._zKind = kind
    f:SetSize(240, 20)
    UI.Border(f, "ui", "border")

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    icon:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    icon:SetTexture(ICON[kind])
    ZacUI.Look.CropIcon(icon)
    f.icon = icon
    local div = f:CreateTexture(nil, "ARTWORK", nil, 1)
    div:SetTexture(ns.FLAT)
    div:SetWidth(1)
    -- (2026-11-19: one screen pixel under ZacUI's look, Core_Pixel; one unit everywhere else, as before)
    if ns.Pixel and ns.Pixel.Edge then ns.Pixel.Edge(div, "LEFT", f) end
    div:SetPoint("TOPLEFT", icon, "TOPRIGHT", 0, 0)
    div:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 0, 0)
    f.div = div

    local sb = CreateFrame("StatusBar", nil, f)
    sb:SetPoint("TOPLEFT", div, "TOPRIGHT", 0, 0)
    sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    sb:SetMinMaxValues(0, 1)
    f.sb = sb
    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg._zui_own = true
    bg:SetAllPoints()
    bg:SetTexture(ns.FLAT)
    f.bg = bg

    -- above the fill: sheen on the filled part, spark at its edge, texts
    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints(sb)
    over:SetFrameLevel(sb:GetFrameLevel() + 2)
    f.over = over
    local sheen = over:CreateTexture(nil, "ARTWORK")
    f.sheen = sheen
    local spark = over:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(SPARK)
    spark:SetBlendMode("ADD")
    f.spark = spark
    f.label = over:CreateFontString(nil, "OVERLAY")
    f.label:SetPoint("LEFT", sb, "LEFT", 6, 0)
    f.label:SetJustifyH("LEFT")
    f.time = over:CreateFontString(nil, "OVERLAY")
    f.time:SetPoint("RIGHT", sb, "RIGHT", -6, 0)
    f.time:SetJustifyH("RIGHT")
    f.label:SetPoint("RIGHT", f.time, "LEFT", -6, 0)
    f.label:SetWordWrap(false)
    -- the pick hook (the settings preview's bars are made here too)
    if ns.TagElement then ns.TagElement(f.label, "timers.label") ns.TagElement(f.time, "timers.time") end

    -- fill texture for the sheen / spark anchors (set with the texture)
    f.SetFillTexture = function(self, tex)
        self.sb:SetStatusBarTexture(tex)
        local ft = self.sb.GetStatusBarTexture and self.sb:GetStatusBarTexture()
        if ft and ft ~= self._ft then
            self._ft = ft
            self.sheen:ClearAllPoints()
            self.sheen:SetPoint("TOPLEFT", ft, "TOPLEFT", 0, 0)
            self.sheen:SetPoint("BOTTOMRIGHT", ft, "RIGHT", 0, 0)
            Sheen(self.sheen, 0.25, 0.03)
            self.spark:ClearAllPoints()
            self.spark:SetPoint("CENTER", ft, "RIGHT", 0, 0)
        end
    end

    f._zPaint = function(self)
        RT.PaintBar(self, self._zKind, DB())
    end
    f:Hide()
    return f
end

local function Col(c, fallback)
    if type(c) == "table" and ns.ColorOf then return ns.ColorOf(c) end
    return fallback.r, fallback.g, fallback.b, fallback.a or 1
end

-- the colours, from the settings or the palette
function RT.PaintBar(self, kind, d)
    UI.PaintBox(self)
    local own = kind == "pull" and d.pullColor or d.breakColor
    local pal = GetColor("text", COLOUR[kind])
    local r, g, b = Col(own, pal)
    self.sb:SetStatusBarColor(r, g, b, 1)
    if type(d.bgColor) == "table" then
        self.bg:SetVertexColor(Col(d.bgColor))
    else
        local w = GetColor("ui", "windowBg")
        -- the empty part of the track: dark, with a hint of the bar colour
        self.bg:SetVertexColor(w.r * 0.45 + r * 0.12, w.g * 0.45 + g * 0.12, w.b * 0.45 + b * 0.12, 0.9)
    end
    local bd = GetColor("ui", "border")
    self.div:SetVertexColor(bd.r, bd.g, bd.b, 1)
    local tr, tg, tb = Col(d.textColor, GetColor("text", "normal"))
    self.label:SetTextColor(tr, tg, tb, 1)
    if not self._zHot then self.time:SetTextColor(tr, tg, tb, 1) end
    self._zTxtCol = { r = tr, g = tg, b = tb }
end

-- a font setting, or ZacUI's font at a size from the bar's height (how
-- the bars have always sized their text)
local function BarFont(fs, spec, autoSize)
    if type(spec) == "table" and next(spec) and ns.ApplyFontSpec then
        ns.ApplyFontSpec(fs, spec, { size = autoSize, outline = "outline" })
    else
        SetFont(fs, autoSize)
    end
end
RT.LabelSize = function(d) return math.max(8, math.floor(d.height * 0.55)) end
RT.TimeSize = function(d) return math.max(8, math.floor(d.height * 0.6)) end

-- WHERE THE TEXTS SIT (ZacUI's anchor shape, raidTimers.anchors.<label|
-- time>): the label from the bar's left edge to the time, the time at the
-- right edge - the spots they always had - with a saved anchor on top.
-- Nothing saved = never touched.
RT.ANCHOR_LABELS = { bar = "The bar", fill = "The fill", icon = "The icon", label = "Label", time = "Time" }
function RT.AnchorDefaults(key)
    if key == "time" then return { point = "RIGHT", relPoint = "RIGHT", x = -6, y = 0, justify = "RIGHT" } end
    return { point = "LEFT", relPoint = "LEFT", x = 6, y = 0, justify = "LEFT" }
end
local function PlaceTexts(b, d)
    local a = type(d.anchors) == "table" and d.anchors or nil
    if not (a or b._zMoved) then return end
    b._zMoved = a and true or nil
    if not b._zAnchorTo then
        b._zAnchorTo = function(k)
            if k == "bar" then return b elseif k == "fill" then return b.sb elseif k == "icon" then return b.icon
            elseif k == "label" then return b.label elseif k == "time" then return b.time end
        end
        b._zDefs = { time = {}, label = {} }
    end
    local t = b._zDefs.time
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = "RIGHT", b.sb, "RIGHT", -6, 0, "RIGHT"
    ns.ApplyAnchor(b.time, a and a.time, t, b._zAnchorTo)
    t = b._zDefs.label
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = "LEFT", b.sb, "LEFT", 6, 0, "LEFT"
    t.point2, t.to2, t.relPoint2, t.x2, t.y2 = "RIGHT", b.time, "LEFT", -6, 0
    local _, two = ns.ApplyAnchor(b.label, a and a.label, t, b._zAnchorTo)
    if not two then b.label:SetWidth(math.max(20, (tonumber(d.width) or 240) * 0.6)) end
end

-- the time as text: the bars' own clock, or the saved format
-- (raidTimers.formats.time, ZacUI's text format shape)
RT.TIME_DEFAULTS = { time = "mmss", timeDecimalsUnder = 10 }
function RT.TimeText(left, d)
    local spec = d and type(d.formats) == "table" and d.formats.time
    if spec and ns.FormatTime then return ns.FormatTime(math.max(0, left), spec, RT.TIME_DEFAULTS) end
    return RT.Clock(left)
end

-- size, texture, fonts and the optional pieces
function RT.StyleBar(b, kind, d)
    b:SetFillTexture(d.texture and ns.ResolveBarTexture and ns.ResolveBarTexture(d.texture) or BarTexture())
    b:SetSize(d.width, d.height)
    local iconOn = d.icon ~= false
    b.icon:SetShown(iconOn)
    b.div:SetShown(iconOn)
    b.icon:SetWidth(iconOn and d.height or 0.001)
    b.div:SetWidth(iconOn and 1 or 0.001)
    b.spark:SetSize(math.max(8, d.height * 0.55), d.height * 1.8)
    b.sheen:SetShown(d.sheen ~= false)
    b._zNoSpark = d.spark == false
    if b._zNoSpark then b.spark:Hide() end
    BarFont(b.label, d.labelFont, RT.LabelSize(d))
    BarFont(b.time, d.timeFont, RT.TimeSize(d))
    if ns.ApplyAnchor then PlaceTexts(b, d) end
    RT.PaintBar(b, kind, d)
    -- (2026-11-15) under a game look: the look's edge round the bar, no
    -- pixel edge or divider (Core_Look, Look.TimerBar; nothing under ZacUI's)
    if ns.Look and ns.Look.TimerBar then ns.Look.TimerBar(b) end
    b._zUnit = nil       -- (a new format reads at the next moment drawn)
end

-- One moment of a countdown: left seconds of dur, precise = GetTime().
function RT.FillBar(b, kind, left, dur, d, precise)
    local v = dur > 0 and math.min(1, left / dur) or 0
    b.sb:SetValue(v)
    b.spark:SetShown(not b._zNoSpark and v > 0.004 and v < 0.996)
    -- the text moves in tenths under ten seconds and in whole seconds
    -- above, so it is only formatted when that unit ticks over - not
    -- every frame
    local unit = left < 10 and math.floor(math.max(0, left) * 10) or math.ceil(left)
    if b._zUnit ~= unit then
        b._zUnit = unit
        local txt = RT.TimeText(left, d)
        if b._zTxt ~= txt then b._zTxt = txt b.time:SetText(txt) end
    end
    -- the last seconds of a pull: the time turns gold and the bar breathes
    local warnAt = tonumber(d.warnAt) or 5
    if kind == "pull" and warnAt > 0 and left <= warnAt then
        local gr, gg, gb = Col(d.warnColor, GetColor("text", "gold"))
        b.time:SetTextColor(gr, gg, gb, 1)
        local breathe = d.warnPulse ~= false and not (ns.Motion and not ns.Motion.Enabled())
        b.sheen:SetAlpha(breathe and (0.6 + 0.4 * math.sin(precise * 9)) or 1)
        b._zHot = true
    elseif b._zHot then
        b._zHot = nil
        local c = b._zTxtCol or GetColor("text", "normal")
        b.time:SetTextColor(c.r, c.g, c.b, 1)
        b.sheen:SetAlpha(1)
    end
end

local function Bar(kind)
    local b = bars[kind]
    if b then return b end
    b = RT.NewBar(kind, Holder())
    bars[kind] = b
    return b
end
RT.Bar = Bar

-- whole seconds count down like DBM's (10 shows until 9 is reached);
-- the last ten show tenths so the end runs smooth
local function Clock(sec)
    if sec < 10 then return string.format("%.1f", math.max(0, sec)) end
    sec = math.ceil(sec)
    if sec >= 60 then return string.format("%d:%02d", math.floor(sec / 60), sec % 60) end
    return tostring(sec)
end
RT.Clock = Clock

-- The caller's class, by name, from the group (or yourself): for the
-- class-coloured name on the bar. nil when they are not in the group.
local function ClassOf(name)
    if not name or name == "" then return nil end
    if UnitName("player") == name then return select(2, UnitClass("player")) end
    return ns.Roster.Class(name)
end

function RT.Who(t)
    if not (t.sender and t.sender ~= "") then return "" end
    if DB().sender == false then return "" end
    t.class = t.class or ClassOf(t.sender)
    local cc = t.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[t.class]
    if cc then
        return string.format("  |cff%02x%02x%02x%s|r", math.floor(cc.r * 255 + 0.5),
            math.floor(cc.g * 255 + 0.5), math.floor(cc.b * 255 + 0.5), t.sender)
    end
    return "  |cff999999" .. t.sender .. "|r"
end

-- the local clock's end of each bar (GetTime-based, never saved: server
-- time is whole seconds, this is what makes the fill smooth)
local localEnd = {}
local running

local StartTicker            -- below; Layout starts it for a glide

local Motion = ns.Motion
local function Playing(b) return Motion and Motion.IsPlaying(b) end

-- where bar number `y` (pixels from the first) sits: from the top going
-- down, or from the bottom going up
local function Put(b, h, d, y)
    b:ClearAllPoints()
    if d.grow == "up" then
        b:SetPoint("BOTTOM", h, "BOTTOM", 0, -y)
    else
        b:SetPoint("TOP", h, "TOP", 0, y)
    end
end

-- Lays the running bars out top to bottom and fills them in. A bar that
-- starts plays its entrance where it belongs; one that stops plays its
-- exit where it is, and the one below glides up into its place.
local function Layout()
    local d = DB()
    local h = Holder()
    local y, any = 0, false
    local now = GetServerTime()
    local gap = tonumber(d.gap) or GAP
    for _, kind in ipairs(KINDS) do
        local t = d.active[kind]
        local b = Bar(kind)
        if t and d[kind] and t.endAt > now then
            any = true
            if b._zOut then
                -- back before it had gone: stop the exit, it stays
                b._zOut = nil
                if Motion then Motion.Stop(b) end
            end
            -- size, texture and colours only: safe while it animates
            RT.StyleBar(b, kind, d)
            b.label:SetText(LABEL[kind] .. RT.Who(t))
            b._zTY = -y
            if not b:IsShown() then
                b._zY = -y
                Put(b, h, d, b._zY)
                if Motion then Motion.Show(b, d.showAnim) else b:Show() end
            else
                if b._zY == nil then b._zY = -y end
                if not Playing(b) then Put(b, h, d, b._zY) end
            end
            y = y + d.height + gap
        elseif b:IsShown() and not b._zOut then
            b._zOut = true
            local function Gone()
                b._zOut = nil
                b._zY = nil
            end
            if Motion then Motion.Hide(b, d.hideAnim, Gone) else b:Hide() Gone() end
            if not b:IsShown() then Gone() end
        end
    end
    h:SetSize(d.width, math.max(d.height, y - gap))
    if any and StartTicker then StartTicker() end
    return any
end

-- every frame while a bar is up: the fill, the spark, the glide; the
-- text only changes when what it says changes
local function Tick()
    local d = DB()
    local now = GetServerTime()
    local precise = GetTime()
    local any, relayout = false, false
    local h = holder
    for _, kind in ipairs(KINDS) do
        local t = d.active[kind]
        local b = bars[kind]
        if t then
            -- server time is whole seconds; the local clock smooths it
            if not localEnd[kind] then localEnd[kind] = precise + (t.endAt - now) end
            local left = localEnd[kind] - precise
            if left <= 0 or t.endAt <= now - 1 then
                d.active[kind] = nil
                localEnd[kind] = nil
                relayout = true
            else
                any = true
                if b and b:IsShown() and not b._zOut then
                    RT.FillBar(b, kind, left, t.dur, d, precise)
                end
            end
        else
            localEnd[kind] = nil
        end
    end
    if relayout then Layout() end
    -- the glide up into a place that came free (after its entrance: a
    -- frame is not moved while it animates)
    local k = math.max(0.02, math.min(1, (tonumber(d.glide) or 25) / 100))
    if Motion and not Motion.Enabled() then k = 1 end
    for _, kind in ipairs(KINDS) do
        local b = bars[kind]
        if b and b:IsShown() and not b._zOut and not Playing(b) then
            if b._zTY and b._zY and b._zY ~= b._zTY then
                local ny = b._zY + (b._zTY - b._zY) * k
                if math.abs(ny - b._zTY) < 0.3 then ny = b._zTY else any = true end
                b._zY = ny
                Put(b, h, d, ny)
            end
        elseif b and Playing(b) and b._zTY ~= b._zY then
            any = true
        end
    end
    if not any and running then
        running = nil
        Holder():SetScript("OnUpdate", nil)
    end
end

StartTicker = function()
    if running then return end
    running = true
    Holder():SetScript("OnUpdate", Tick)
end

-- ============================================================
-- STARTING AND STOPPING
-- ============================================================
-- seconds: the time left. total: the timer's whole length when the
-- source says so and it is more than what is left (the game's countdown
-- reaching a client partway); the bar then starts part empty.
function RT.Set(kind, seconds, sender, total)
    local d = DB()
    if not d.enabled then return end
    seconds = tonumber(seconds)
    if not seconds then return end
    if seconds <= 0 then
        d.active[kind] = nil
        localEnd[kind] = nil
    else
        seconds = math.min(seconds, 3600)
        total = tonumber(total)
        local dur = (total and total > seconds) and math.min(total, 3600) or seconds
        -- one pull reaches us several ways (countdown, DBM, BigWigs) a
        -- moment apart; the same timer again must not nudge the bar
        local cur, le = d.active[kind], localEnd[kind]
        if cur and le and cur.dur == dur and math.abs((le - GetTime()) - seconds) < 1.5 then
            if not cur.sender and sender then cur.sender = sender cur.class = nil Layout() end
            return
        end
        d.active[kind] = { endAt = GetServerTime() + seconds, dur = dur, sender = sender }
        localEnd[kind] = GetTime() + seconds
    end
    Layout()
    StartTicker()
    Tick()
end

-- A timer this client missed the start of, told by someone who has it:
-- seconds left, of dur when known, started by who when known. Only fills
-- in what this client does not already have (the same timer within three
-- seconds is left alone, so its bar never jumps).
function RT.Fill(kind, left, dur, who)
    local d = DB()
    if not (d.enabled and LABEL[kind]) then return false end
    left, dur = tonumber(left), tonumber(dur)
    if not left or left <= 0 or left > 3600 then return false end
    local mine = d.active[kind]
    local now = GetServerTime()
    if mine and math.abs((mine.endAt - now) - left) < 3 then return false end
    d.active[kind] = { endAt = now + left, dur = (dur and dur >= left and dur <= 3600) and dur or left,
        sender = (who and who ~= "") and who or nil }
    localEnd[kind] = GetTime() + left
    if Layout() then StartTicker() end
    Tick()
    return true
end

local Short = ns.ShortName

-- DBM: tab-separated, with "PT" (pull) or "BT" (break) followed by the
-- seconds somewhere in it (the fields before it vary by DBM version).
local function FromDBM(msg, sender)
    local parts = { strsplit("\t", msg) }
    for i = 1, #parts - 1 do
        local tag = parts[i]
        if tag == "PT" or tag == "BT" then
            local sec = tonumber(parts[i + 1])
            if sec then
                Trace("DBM %s %s from %s", tag, tostring(sec), tostring(sender))
                RT.Set(tag == "PT" and "pull" or "brk", sec, Short(sender))
                return
            end
        end
    end
end

-- BigWigs: "P^Pull^10" / "P^Break^300" (older builds used a tab).
local function FromBigWigs(msg, sender)
    local a, b, c = strsplit("^", msg)
    if a ~= "P" then a, b, c = strsplit("\t", msg) end
    local sec = tonumber(c)
    if not sec then return end
    if b == "Pull" or b == "BWPull" or b == "Break" or b == "BWBreak" then
        Trace("BigWigs %s %s from %s", tostring(b), tostring(sec), tostring(sender))
    end
    if b == "Pull" or b == "BWPull" then RT.Set("pull", sec, Short(sender))
    elseif b == "Break" or b == "BWBreak" then RT.Set("brk", sec, Short(sender)) end
end

-- The raid packs' own break call: "BREAK:<seconds>:<who>", on the prefix
-- other raiders' clients send it under (PACK_PREFIX).
local PACK_PREFIX = "FojjiTimerAddon"
-- "BREAK_STATUS" / "BREAK_SYNC" carry the seconds LEFT of a break already
-- running (what a raider's client tells one that missed the start).
local function FromPackBreak(msg)
    local cmd, value, who = strsplit(":", msg)
    if cmd and cmd:find("^BREAK") then Trace("raid pack: %s", tostring(msg)) end
    if cmd == "BREAK" then RT.Set("brk", tonumber(value), (who ~= "" and who) or nil)
    elseif cmd == "BREAK_STATUS" or cmd == "BREAK_SYNC" then
        local secs = tonumber(value)
        if secs == 0 then RT.Set("brk", 0)
        elseif secs then RT.Fill("brk", secs, nil, (who and who ~= "" and who) or nil) end
    elseif cmd == "BREAK_CANCEL" then RT.Set("brk", 0) end
end

-- ============================================================
-- SYNC BETWEEN ZACUI CLIENTS
-- ============================================================
-- -> true when the client took the message (its own answer where it gives one)
local function Send(msg, channel, target, prefix)
    -- WoW Forever delivers no addon messages inside an instance (Core_Flavor)
    if ns.AddonMessagesBlocked and ns.AddonMessagesBlocked() then
        Trace("NOT SENT (addon messages are blocked here) %s %s -> %s", prefix or SYNC, Vis(msg), tostring(target or channel))
        return false
    end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local ok, res = pcall(C_ChatInfo.SendAddonMessage, prefix or SYNC, msg, channel, target)
        -- (true or 0 = taken; any other number is the client's refusal code)
        local taken = ok and (res == nil or res == true or res == 0)
        Trace("%s %s %s -> %s (client: %s)", taken and "sent" or "REFUSED", prefix or SYNC, Vis(msg),
            tostring(target or channel), tostring(res))
        return taken and true or false
    end
    return false
end

function RT.RequestSync()
    local d = DB()
    if not (d.enabled and d.sync) then return false end
    local ch = ns.GroupChannel()
    if not ch then Trace("ZacUI request not sent: no group channel yet") return false end
    return Send("REQ", ch)
end

-- ============================================================
-- ASKING THE GROUP'S DBM CLIENTS FOR A RUNNING BREAK
-- ============================================================
-- DBM's own way for a client that missed the start (facts from DBM's
-- source, 2026-11: prefix "D5", every message "<tab>1<tab>TAG<tab>value"):
-- a group member whispers the request "RT"; a DBM client that is not in a
-- boss fight and has a break bar up whispers back "BTR3" with the seconds
-- left, and says nothing otherwise. It answers one request a second from
-- the same sender. A client without DBM never sees the whisper.
local MOD_PREFIX = "D5"
local MOD_REQUEST = "\t1\tRT\t"
local ASK_EACH, ASK_ROUNDS, ASK_GAP, ASK_TRUST = 3, 3, 2.5, 10
local modUsers = {}          -- [short name] = true: seen sending DBM messages this session
local askedAt = {}           -- [short name] = GetTime() of our request
local askSeq = 0

-- group members worth asking, best first: seen using DBM, the leader,
-- the assistants, then everyone else; online, not asked in the last ten
-- seconds. A member from another realm of the cluster is whispered as
-- Name-Realm (2026-11-22: they were left out, and on a realm cluster that
-- is most of a raid, the leader often among them). `key` is the name as
-- an answer's sender comes back shortened, so the two can be matched.
local function ModCandidates()
    local list = {}
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n <= 0 then return list end
    local raid = IsInRaid and IsInRaid()
    local now = GetTime()
    for i = 1, n do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) and not UnitIsUnit(unit, "player") and UnitIsConnected(unit) then
            local name, realm = UnitName(unit)
            if name and name ~= "" and name ~= UNKNOWNOBJECT then
                local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
                local key = Short(full) or full
                if not (askedAt[key] and now - askedAt[key] < ASK_TRUST) then
                    local score = (modUsers[key] and 4 or 0)
                        + ((UnitIsGroupLeader and UnitIsGroupLeader(unit)) and 2 or 0)
                        + ((UnitIsGroupAssistant and UnitIsGroupAssistant(unit)) and 1 or 0)
                    list[#list + 1] = { name = full, key = key, score = score, order = i }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.order < b.order
    end)
    return list
end

local function AskModsRound(seq, round, rounds)
    if seq ~= askSeq then return end
    local d = DB()
    if not (d.enabled and d.brk and d.askMods) then return end
    -- a break bar is up (one answered, or it was never missing): done
    if d.active.brk then return end
    local grouped = IsInGroup and IsInGroup()
    local list = grouped and ModCandidates() or {}
    Trace("DBM round %d of %d: in a group %s, %d members, %d to ask", round, rounds, tostring(grouped and true or false),
        (GetNumGroupMembers and GetNumGroupMembers()) or 0, #list)
    for i = 1, math.min(ASK_EACH, #list) do
        if Send(MOD_REQUEST, "WHISPER", list[i].name, MOD_PREFIX) then
            askedAt[list[i].key] = GetTime()
        end
    end
    -- (the next round even when nobody could be asked in this one: right
    -- after a login the roster is still filling)
    if round < rounds then
        C_Timer.After(ASK_GAP, function() AskModsRound(seq, round + 1, rounds) end)
    end
end

-- rounds: how many times a few more are asked (nil: the full three)
function RT.AskMods(rounds)
    askSeq = askSeq + 1
    AskModsRound(askSeq, 1, tonumber(rounds) or ASK_ROUNDS)
end
function RT.ModsAsked() return askedAt end

-- one ask for everything, a moment from now (a login, a reload, joining a
-- group); a second call inside that moment is the same ask
local askToken = 0
function RT.AskSoon(delay, rounds)
    askToken = askToken + 1
    local token = askToken
    C_Timer.After(delay or 3, function()
        if token ~= askToken then return end
        Trace("asking (group %s, raid %s, %d members)", tostring(IsInGroup and IsInGroup() and true or false),
            tostring(IsInRaid and IsInRaid() and true or false), (GetNumGroupMembers and GetNumGroupMembers()) or 0)
        -- (no group channel yet - a login still loading its roster: once more in five seconds)
        if not RT.RequestSync() and DB().sync then
            C_Timer.After(5, function() if token == askToken then RT.RequestSync() end end)
        end
        RT.AskMods(rounds)
    end)
end

-- a DBM client's whispered answer: taken only from someone this client
-- asked, in the last ten seconds, who is in the group
local function FromDBMWhisper(msg, sender)
    local who = Short(sender)
    local at = who and askedAt[who]
    if not (at and GetTime() - at <= ASK_TRUST) then
        if msg:find("BTR3", 1, true) then Trace("DBM answer from %s NOT taken (not asked in the last %d s): %s", tostring(sender), ASK_TRUST, Vis(msg)) end
        return
    end
    if not (UnitInRaid and UnitInRaid(who) or UnitInParty and UnitInParty(who)) then
        Trace("DBM whisper from %s NOT taken (not in the group): %s", tostring(sender), Vis(msg))
        return
    end
    Trace("DBM whisper from %s: %s", tostring(sender), Vis(msg))
    local parts = { strsplit("\t", msg) }
    for i = 1, #parts - 1 do
        if parts[i] == "BTR3" then
            local sec = tonumber(parts[i + 1])
            if sec and sec > 0 and sec <= 3600 then
                modUsers[who] = true
                local took = RT.Fill("brk", sec)
                Trace("break: %d s left from %s (%s)", sec, who, took and "bar started" or "already had it")
            end
            return
        end
    end
end

local function AnswerSync(sender)
    local d = DB()
    if not (d.enabled and d.sync) then return end
    local now = GetServerTime()
    for _, kind in ipairs(KINDS) do
        local t = d.active[kind]
        if t and t.endAt > now + 1 then
            Send(string.format("T\t%s\t%d\t%d\t%s", kind, t.endAt - now, t.dur or 0, t.sender or ""),
                "WHISPER", sender)
        end
    end
end

local function FromSync(msg, sender)
    if msg == "REQ" then
        if sender and Short(sender) ~= UnitName("player") then
            Trace("%s asks what is running (ZacUI)", tostring(sender))
            AnswerSync(sender)
        end
        return
    end
    local tag, kind, left, dur, who = strsplit("\t", msg)
    if tag ~= "T" or not LABEL[kind] then return end
    dur = tonumber(dur)
    -- only fill in what this client does not already have
    local took = RT.Fill(kind, left, (dur and dur > 0) and dur or nil, who)
    Trace("ZacUI answer from %s: %s %s s left (%s)", tostring(sender), tostring(kind), tostring(left), took and "bar started" or "already had it or not usable")
end

-- ============================================================
-- BLIZZARD'S COUNTDOWN BAR
-- ============================================================
-- /countdown (and ZacUI's /pull, which sends one) also starts Blizzard's
-- own countdown - the ornate bar and the big golden numbers at the end -
-- on top of ours. While ours is on, each Blizzard timer frame is made
-- see-through rather than hidden: it keeps running and frees itself when
-- done exactly as Blizzard means it to, it just never shows. Only the
-- timer frames TimerTracker made are touched, never TimerTracker itself.
local function WantBlizzHidden()
    local d = DB()
    return d.enabled and d.pull and d.hideBlizz and true or false
end
local blizzHooked = false
local function HideBlizzBars(tracker)
    local hide = WantBlizzHidden()
    for _, tm in ipairs(tracker.timerList or {}) do
        if tm.SetAlpha then
            if not tm._zuiHooked then
                tm._zuiHooked = true
                -- Blizzard fades its own pieces in: keep the whole frame clear
                tm:HookScript("OnShow", function(t) if WantBlizzHidden() then t:SetAlpha(0) end end)
            end
            tm:SetAlpha(hide and 0 or 1)
        end
    end
end
local function HookBlizzard()
    if blizzHooked then return end
    local tt = _G.TimerTracker
    if not (tt and tt.HookScript) then return end
    blizzHooked = true
    tt:HookScript("OnEvent", function(self) HideBlizzBars(self) end)
end

-- ============================================================
-- EVENTS
-- ============================================================
local ev = CreateFrame("Frame")
local inGroup = false
local function OnEvent(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        -- every addon message in the raid comes here: the prefix and the
        -- channel are looked at before anything else
        local prefix, msg, channel, sender = ...
        if not msg then return end
        local mine = prefix == SYNC or prefix == PACK_PREFIX
        local dbm = DBM_PREFIXES[prefix]
        if not mine and not ((dbm or prefix == "BigWigs") and GROUP_CHANNELS[channel])
            and not (dbm and channel == "WHISPER") then
            return
        end
        if not DB().enabled then return end
        if prefix == SYNC then
            FromSync(msg, sender)
        elseif prefix == PACK_PREFIX then
            FromPackBreak(msg)
        elseif GROUP_CHANNELS[channel] then
            if dbm then
                -- (who runs DBM here: the first to ask next time)
                local who = Short(sender)
                if who then modUsers[who] = true end
                FromDBM(msg, sender)
            elseif prefix == "BigWigs" then FromBigWigs(msg, sender) end
        elseif dbm and channel == "WHISPER" then
            FromDBMWhisper(msg, sender)
        end
        return
    end
    local d = DB()
    if not d.enabled then return end
    if event == "START_PLAYER_COUNTDOWN" then
        -- (initiatedBy, timeRemaining, totalTime, informChat, initiatedByName)
        local guid, seconds, total, _, byName = ...
        Trace("the game's countdown: %s s left of %s, by %s", tostring(seconds), tostring(total), tostring(byName))
        local who = (type(byName) == "string" and byName ~= "") and Short(byName) or nil
        if not who and guid and GetPlayerInfoByGUID then who = select(6, GetPlayerInfoByGUID(guid)) end
        RT.Set("pull", seconds, who, total)
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        Trace("the game's countdown was cancelled")
        RT.Set("pull", 0)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- saved timers come back with their time left; then ask the group
        local login, reload = ...
        Trace("entering the world (login %s, reload %s)", tostring(login), tostring(reload))
        for kind, t in pairs(d.active) do t._localEnd = nil localEnd[kind] = nil end
        if Layout() then StartTicker() end
        Tick()
        inGroup = (IsInGroup and IsInGroup()) and true or false
        -- (a login or a reload asks all the way round; a loading screen in
        -- between - messages sent during one are lost - asks once)
        local rounds
        if not (login or reload) then rounds = 1 end
        RT.AskSoon(3, rounds)
    elseif event == "GROUP_JOINED" or event == "GROUP_ROSTER_UPDATE" then
        -- joined a group whose timer is already running: ask
        local now = (IsInGroup and IsInGroup()) and true or false
        if now and not inGroup then
            Trace("joined a group (%s)", event)
            RT.AskSoon(2)
        end
        inGroup = now
    end
end

function RT.Apply()
    local d = DB()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        for _, p in ipairs({ SYNC, "BigWigs", PACK_PREFIX }) do
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, p)
        end
        for p in pairs(DBM_PREFIXES) do pcall(C_ChatInfo.RegisterAddonMessagePrefix, p) end
    end
    if d.enabled then
        HookBlizzard()
        ev:RegisterEvent("CHAT_MSG_ADDON")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        pcall(ev.RegisterEvent, ev, "START_PLAYER_COUNTDOWN")
        pcall(ev.RegisterEvent, ev, "CANCEL_PLAYER_COUNTDOWN")
        pcall(ev.RegisterEvent, ev, "GROUP_JOINED")
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")
        ev:SetScript("OnEvent", OnEvent)
        if Layout() then StartTicker() end
    else
        ev:UnregisterAllEvents()
        if holder then
            for _, b in pairs(bars) do
                if Motion then Motion.Stop(b) end
                b._zOut, b._zY = nil, nil
                b:Hide()
            end
        end
    end
end

-- `/zui timers`: the settings that decide it, what is running, and the
-- trace above, into the chat window.
function RT.Report()
    local d = DB()
    local function P(line) if ns.Print then ns.Print(line) else print("ZacUI: " .. line) end end
    P(string.format("Timers: bars %s, break %s, pull %s, ask ZacUI users %s, ask DBM users %s. Client %s. Group %s, raid %s, %d members.",
        d.enabled and "on" or "OFF", d.brk and "on" or "OFF", d.pull and "on" or "OFF", d.sync and "on" or "OFF",
        d.askMods and "on" or "OFF", tostring((GetBuildInfo and (GetBuildInfo())) or "?"),
        tostring(IsInGroup and IsInGroup() and true or false), tostring(IsInRaid and IsInRaid() and true or false),
        (GetNumGroupMembers and GetNumGroupMembers()) or 0))
    local now = GetServerTime()
    for _, kind in ipairs(KINDS) do
        local t = d.active[kind]
        P(string.format("  %s: %s", LABEL[kind] or kind, t and string.format("%d s left of %d, by %s", t.endAt - now, t.dur or 0, tostring(t.sender or "?")) or "none running"))
    end
    if #trace == 0 then P("  Nothing asked or heard yet this session.") end
    for _, line in ipairs(trace) do P("  " .. line) end
    P(string.format("  (now %.1f)", GetTime()))
end
ns.SlashCommands = ns.SlashCommands or {}
ns.SlashCommands.timers = function() RT.Report() end

-- A sample of both bars for 15 seconds, to see and place them.
function RT.Test()
    RT.Set("brk", 15, UnitName("player"))
    RT.Set("pull", 10, UnitName("player"))
end

RT.Layout = Layout
RT.bars = bars

-- the look changed (the settings page): bars on screen follow
function RT.Restyle()
    for _, b in pairs(bars) do
        if b:IsShown() and not b._zOut then Layout() return end
    end
end

-- shared with later ZacUI files
QoL.RaidTimers = RT
