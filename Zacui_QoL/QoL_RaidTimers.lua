-- QoL_RaidTimers - pull and break timers as bars that survive a reload,
-- a relog or a character swap.
-- Part of ZacUI; load order is set by the TOC.
--
-- Sources: DBM and BigWigs pull / break messages, the raid packs' break
-- call, and Blizzard's own /countdown. ZacUI's own /pull and /break
-- (Zacui_RaidTools) send all of those at once. Each running timer is saved by its end in server time, so
-- after a reload or a relog the bar comes back with the right time left.
-- On login in a group, ZacUI also asks the group: any other ZacUI client
-- with a timer running (your other characters) answers, so a break that
-- started while this character was logged out still shows up.

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
        ns.RegisterMover("raidtimers", "Pull & break timers", function() return holder end, "TOP", 0, -180)
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
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon
    local div = f:CreateTexture(nil, "ARTWORK", nil, 1)
    div:SetTexture(ns.FLAT)
    div:SetWidth(1)
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
function RT.Set(kind, seconds, sender)
    local d = DB()
    if not d.enabled then return end
    seconds = tonumber(seconds)
    if not seconds then return end
    if seconds <= 0 then
        d.active[kind] = nil
        localEnd[kind] = nil
    else
        seconds = math.min(seconds, 3600)
        -- one pull reaches us several ways (countdown, DBM, BigWigs) a
        -- moment apart; the same timer again must not nudge the bar
        local cur, le = d.active[kind], localEnd[kind]
        if cur and le and cur.dur == seconds and math.abs((le - GetTime()) - seconds) < 1.5 then
            if not cur.sender and sender then cur.sender = sender cur.class = nil Layout() end
            return
        end
        d.active[kind] = { endAt = GetServerTime() + seconds, dur = seconds, sender = sender }
        localEnd[kind] = GetTime() + seconds
    end
    Layout()
    StartTicker()
    Tick()
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
    if b == "Pull" or b == "BWPull" then RT.Set("pull", sec, Short(sender))
    elseif b == "Break" or b == "BWBreak" then RT.Set("brk", sec, Short(sender)) end
end

-- The raid packs' own break call: "BREAK:<seconds>:<who>", on the prefix
-- other raiders' clients send it under (PACK_PREFIX).
local PACK_PREFIX = "FojjiTimerAddon"
local function FromPackBreak(msg)
    local cmd, value, who = strsplit(":", msg)
    if cmd == "BREAK" then RT.Set("brk", tonumber(value), (who ~= "" and who) or nil)
    elseif cmd == "BREAK_CANCEL" then RT.Set("brk", 0) end
end

-- ============================================================
-- SYNC BETWEEN ZACUI CLIENTS
-- ============================================================
local function Send(msg, channel, target)
    -- WoW Forever delivers no addon messages inside an instance (Core_Flavor)
    if ns.AddonMessagesBlocked and ns.AddonMessagesBlocked() then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, SYNC, msg, channel, target)
    end
end

function RT.RequestSync()
    local d = DB()
    if not (d.enabled and d.sync) then return end
    local ch = ns.GroupChannel()
    if ch then Send("REQ", ch) end
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
        if sender and Short(sender) ~= UnitName("player") then AnswerSync(sender) end
        return
    end
    local tag, kind, left, dur, who = strsplit("\t", msg)
    if tag ~= "T" or not LABEL[kind] then return end
    left, dur = tonumber(left), tonumber(dur)
    if not left or left <= 0 then return end
    local d = DB()
    local mine = d.active[kind]
    local now = GetServerTime()
    -- only fill in what this client does not already have
    if mine and math.abs((mine.endAt - now) - left) < 3 then return end
    d.active[kind] = { endAt = now + left, dur = (dur and dur > 0) and dur or left,
        sender = (who ~= "" and who) or nil }
    localEnd[kind] = GetTime() + left
    if Layout() then StartTicker() end
    Tick()
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
local function OnEvent(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        -- every addon message in the raid comes here: the prefix and the
        -- channel are looked at before anything else
        local prefix, msg, channel, sender = ...
        if not msg then return end
        local mine = prefix == SYNC or prefix == PACK_PREFIX
        if not mine and not ((DBM_PREFIXES[prefix] or prefix == "BigWigs") and GROUP_CHANNELS[channel]) then
            return
        end
        if not DB().enabled then return end
        if prefix == SYNC then
            FromSync(msg, sender)
        elseif prefix == PACK_PREFIX then
            FromPackBreak(msg)
        elseif GROUP_CHANNELS[channel] then
            if DBM_PREFIXES[prefix] then FromDBM(msg, sender)
            elseif prefix == "BigWigs" then FromBigWigs(msg, sender) end
        end
        return
    end
    local d = DB()
    if not d.enabled then return end
    if event == "START_PLAYER_COUNTDOWN" then
        local guid, seconds = ...
        local who
        if guid and GetPlayerInfoByGUID then who = select(6, GetPlayerInfoByGUID(guid)) end
        RT.Set("pull", seconds, who)
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        RT.Set("pull", 0)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- saved timers come back with their time left; then ask the group
        for kind, t in pairs(d.active) do t._localEnd = nil localEnd[kind] = nil end
        if Layout() then StartTicker() end
        Tick()
        C_Timer.After(3, RT.RequestSync)
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
