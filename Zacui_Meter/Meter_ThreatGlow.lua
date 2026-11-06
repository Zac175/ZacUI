-- Meter_ThreatGlow - the screen-edge threat glow, the weak tank opener
-- alert and the pull warning (2026-11-03).
-- Part of ZacUI; load order is set by the TOC (after Meter_Threat, whose
-- shared reader ns.Threat it reads, pull prediction included).
--
-- Zac, after dying to threat he talked over: "i want something other
-- than tts its not helpful or its too late to matter", then "can we
-- somehow detect the tanks horrible opener? ... and somehow alert me if
-- the opener is horrible?" So:
--
-- THE GLOW. The edges of the screen tell him, in the corner of his eye:
--   * from threat.glowStart (75% of a pull), or when the reader says he
--     would pull within threat.openerAt seconds (6): a faint orange glow
--     round all four edges, stronger as it gets closer;
--   * from threat.glowRed (90%), or a pull 3 s away: red and pulsing, the
--     pulse quicker the closer it gets;
--   * pulled it (the mob is on you and you are not tanking it on
--     purpose) or 100%: solid red, flashing fast.
-- THE WEAK OPENER (threat.opener; nil = on for warriors). In the first
-- seconds of a pull (up to 5 s in; the first check comes as soon as the
-- reader has half a second of both threats, so within about a second) on
-- an elite or a boss, in a group, not tanking it: the first pass where at
-- the rates you and the tank are going you would pull within
-- threat.openerAt seconds, "WEAK TANK OPENER" in the middle of the
-- screen (the raid-warning frame and its sound), "Weak opener, hold" said
-- once, and the glow orange for a few seconds. Once per pull; the next
-- pull (the next time combat starts) arms it again.
-- THE PULL WARNING (threat.pullWarn; nil = on for warriors). Later in the
-- fight, while you would pull within 3 s: "PULLING IN 3s" in the middle of
-- the screen (again every 3 s while it holds) and the red glow. The voice
-- has its own "Stop" call (Meter_Threat).
--
-- Same rules as the voice: quiet in the first seconds of a pull (the
-- opener aside - that is its whole point), never while you tank on
-- purpose. A WARRIOR GETS NONE OF IT IN DEFENSIVE STANCE: that is where a
-- warrior holds threat on purpose; Battle and Berserker are where a fury
-- or arms warrior rips it. Other classes: never while tanking in their
-- tanking form (bear form, Righteous Fury).
--
-- The glow is on by default for warriors, off for everyone else
-- (threat.glow; nil = that class default, so nothing is written until it
-- is ticked). Options: Damage meter page, General tab, Threat card.
--
-- COST (Zac: "make sure this stuff is performant and wont nuke my fps",
-- 40-man raids; "a bad tank opener can be life or death in the matter of
-- a split second"): no ticker and no query here at all - it runs inside
-- the reader's pass, which runs the moment the game hands over new threat
-- for your mob (at most ten times a second, every 0.5 s without events,
-- combat only) and asks at most two threat queries (you and the cached
-- tank). An alert goes out in that same call: the line and its sound
-- first, then the glow, the voice last (text-to-speech has a delay of its
-- own). Nothing is built per pass: the alert lines are fixed strings. THE FRAME is one full-screen,
-- click-through frame on UIParent in the LOW strata (over the world,
-- under the action bars and unit frames) holding four edge gradients.
-- Hidden while it is not warning, so it costs nothing then. How strong it
-- is goes on the frame's alpha, in 5% steps, eased with Motion.FadeTo only
-- when that step changes; the pulse is a looping flash on an inner frame
-- through ZacUI's motion layer (restarted only when its speed moves a
-- half step). No OnUpdate of its own. The settings preview builds its
-- sample with this same G.Create / G.Apply on a screen-sized stand-in
-- (showing its corner), and the alert lines with G.AlertLine below.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local Meter = ns.Meter
local max, min, floor, ceil = math.max, math.min, math.floor, math.ceil

local G = {}
ns.ThreatGlow = G

local _, myClass = UnitClass("player")
G.isWarrior = myClass == "WARRIOR"

-- what nil means for each option (nothing is written by reading them)
G.DEFAULTS = {
    glowStart = 75,         -- % of a pull where the faint orange starts
    glowRed = 90,           -- % where it turns red and pulses
    glowStrength = 0.8,     -- how strong it gets at its strongest (0.2 .. 1)
    glowWidth = 90,         -- how far in from each edge it reaches, px
    glowColor = { r = 1, g = 0.55, b = 0.1, a = 1 },      -- the warning
    glowRedColor = { r = 1, g = 0.08, b = 0.05, a = 1 },  -- the danger
    openerAt = 6,           -- a weak opener: you would pull within this many seconds
}
G.PULL_WARN_AT = 3          -- the pull warning (and the red glow): a pull this close
G.OPENER_FROM, G.OPENER_TO = 0, 5   -- the opener is judged this many seconds into a pull
G.OPENER_GLOW = 3           -- how long the opener keeps the glow orange
G.PULL_WARN_EVERY = 3       -- the pull warning again while it holds
G.OPENER_TEXT = "WEAK TANK OPENER"
G.OPENER_VOICE = "Weak opener, hold"
local PULL_TEXT = { "PULLING IN 1s", "PULLING IN 2s", "PULLING IN 3s" }
G.PULL_TEXT = PULL_TEXT

local function ColorOf(c, d)
    if ns.ColorOf then return ns.ColorOf(c, d) end
    c = type(c) == "table" and c or d
    return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
end

local function T()
    local db = Meter and Meter.DB and Meter.DB()
    return db and db.threat or nil
end

-- the glow's options, every one filled in (one reused table)
local cfg = {}
function G.Cfg()
    local t = T() or {}
    local D = G.DEFAULTS
    cfg.start = tonumber(t.glowStart) or D.glowStart
    cfg.red = tonumber(t.glowRed) or D.glowRed
    if cfg.red <= cfg.start then cfg.red = min(100, cfg.start + 1) end
    cfg.strength = tonumber(t.glowStrength) or D.glowStrength
    cfg.width = tonumber(t.glowWidth) or D.glowWidth
    cfg.r, cfg.g, cfg.b = ColorOf(t.glowColor, D.glowColor)
    cfg.rr, cfg.rg, cfg.rb = ColorOf(t.glowRedColor, D.glowRedColor)
    cfg.pullRed = G.PULL_WARN_AT
    cfg.pullOrange = max(G.PULL_WARN_AT + 1, tonumber(t.openerAt) or D.openerAt)
    return cfg
end

-- on: ticked, or (never touched) a warrior
local function ClassDefault(key)
    local t = T()
    if not t then return false end
    if t[key] == nil then return G.isWarrior end
    return t[key] and true or false
end
function G.On() return ClassDefault("glow") end
function G.OpenerOn() return ClassDefault("opener") end
function G.PullWarnOn() return ClassDefault("pullWarn") end
function G.OpenerAt()
    local t = T()
    return (t and tonumber(t.openerAt)) or G.DEFAULTS.openerAt
end

-- ============================================================
-- THE LEVELS
-- ============================================================
-- What the glow does for your scaled threat `pct` (100 = pull), `pulled`
-- (the mob is on you by accident), `pullIn` (seconds until you would pull,
-- from the reader's prediction; nil = never) and `opener` (a weak opener
-- was just called):
--   state      "off" | "orange" | "red" | "pulled"
--   intensity  0..1 of the strength setting
--   r, g, b    its colour
--   hz         pulses a second (0 = steady)
-- The worse of what the % says and what the prediction says. Pure: the
-- live glow, the preview and the tests all ask this.
local RANK = { off = 0, orange = 1, red = 2, pulled = 3 }
local function ByPct(pct, c)
    if pct >= c.red then
        local k = (pct - c.red) / max(1, 100 - c.red)
        -- once a second at the red line, four times a second at 100
        return "red", 0.7 + 0.3 * k, 1 + 3 * k
    end
    if pct >= c.start then
        return "orange", 0.25 + 0.4 * (pct - c.start) / max(1, c.red - c.start), 0
    end
    return "off", 0, 0
end
local function ByPull(pullIn, c)
    if not pullIn then return "off", 0, 0 end
    if pullIn <= c.pullRed then
        local k = 1 - max(0, pullIn) / c.pullRed
        return "red", 0.7 + 0.3 * k, 1 + 3 * k
    end
    if pullIn <= c.pullOrange then
        return "orange", 0.25 + 0.4 * (1 - (pullIn - c.pullRed) / max(1, c.pullOrange - c.pullRed)), 0
    end
    return "off", 0, 0
end
function G.Level(pct, pulled, c, pullIn, opener)
    c = c or G.Cfg()
    pct = tonumber(pct) or 0
    if pulled or pct >= 100 then
        return "pulled", 1, c.rr, c.rg, c.rb, 3
    end
    local s, k, hz = ByPct(pct, c)
    local s2, k2, hz2 = ByPull(pullIn, c)
    if RANK[s2] > RANK[s] or (s2 == s and k2 > k) then s, k, hz = s2, k2, hz2 end
    if opener and RANK[s] < RANK.red then
        s, k, hz = "orange", max(k, 0.65), 0
    end
    if s == "red" then return s, k, c.rr, c.rg, c.rb, hz end
    return s, k, c.r, c.g, c.b, hz
end

-- the pulse speed in half-pulse steps, so it is not started over on
-- every reading (a looping flash blinks twice per pass)
local function PulseStep(hz)
    if not hz or hz <= 0 then return 0 end
    return floor(hz * 2 + 0.5) / 2
end
G.PulseStep = PulseStep

-- ============================================================
-- THE FRAME (live and preview)
-- ============================================================
local EDGES = {
    -- key, its anchors, which way the gradient runs, and which end is the
    -- edge (the coloured end)
    { "top",    "TOPLEFT", "TOPRIGHT",       "VERTICAL",   "max" },
    { "bottom", "BOTTOMLEFT", "BOTTOMRIGHT", "VERTICAL",   "min" },
    { "left",   "TOPLEFT", "BOTTOMLEFT",     "HORIZONTAL", "min" },
    { "right",  "TOPRIGHT", "BOTTOMRIGHT",   "HORIZONTAL", "max" },
}

-- The glow on `parent`, filling it: a host (its alpha = how strong) and
-- an inner pulser (the motion layer's flash) holding the four edges.
function G.Create(parent)
    local host = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    if host.EnableMouse then host:EnableMouse(false) end
    host:Hide()
    local pulser = CreateFrame("Frame", nil, host)
    pulser:SetAllPoints(host)
    host.pulser = pulser
    host.edges = {}
    for _, e in ipairs(EDGES) do
        local t = pulser:CreateTexture(nil, "ARTWORK")
        t:SetPoint(e[2], pulser, e[2], 0, 0)
        t:SetPoint(e[3], pulser, e[3], 0, 0)
        host.edges[e[1]] = t
    end
    host.state = "off"
    host.pulse = 0
    return host
end

-- one edge's gradient: solid at the screen edge, clear inwards (the
-- 1.15 ColorMixin signature, the old SetGradientAlpha, or a flat tint)
local function PaintEdge(t, e, r, g, b)
    t:SetColorTexture(1, 1, 1, 1)
    local edgeMax = e[5] == "max"
    local a1, a2 = edgeMax and 0 or 1, edgeMax and 1 or 0
    if CreateColor and t.SetGradient then
        if pcall(t.SetGradient, t, e[4], CreateColor(r, g, b, a1), CreateColor(r, g, b, a2)) then return true end
    end
    if t.SetGradientAlpha then
        if pcall(t.SetGradientAlpha, t, e[4], r, g, b, a1, r, g, b, a2) then return true end
    end
    t:SetColorTexture(r, g, b, 0.5)
    return false
end

-- painted again only when the colour or the width changed
local function Paint(host, r, g, b, width)
    if host._r == r and host._g == g and host._b == b and host._w == width then return end
    host._r, host._g, host._b, host._w = r, g, b, width
    local soft = true
    for _, e in ipairs(EDGES) do
        local t = host.edges[e[1]]
        if e[4] == "VERTICAL" then t:SetHeight(width) else t:SetWidth(width) end
        if not PaintEdge(t, e, r, g, b) then soft = false end
    end
    host.flat = not soft
end

local FADE = { style = "fade", duration = 0.25, delay = 0, easing = "easeOutQuad" }
local PULSE = { style = "flash", duration = 1, delay = 0, easing = "linear", loop = true }

-- Shows `host` at `pct` / `pulled` with options `c`; o.pullIn / o.opener
-- as for G.Level, o.instant sets the alpha at once (the preview).
-- Returns the state.
function G.Apply(host, pct, pulled, c, o)
    c = c or G.Cfg()
    local Motion = ns.Motion
    local state, k, r, g, b, hz = G.Level(pct, pulled, c, o and o.pullIn, o and o.opener)
    host.state, host.intensity, host.hz = state, k, hz
    if state == "off" then
        G.Off(host, o and o.instant)
        return state
    end
    Paint(host, r, g, b, c.width)
    -- in 5% steps: a reading that moves it less changes nothing
    local alpha = max(0.05, min(1, k * c.strength * (host.flat and 0.6 or 1)))
    alpha = floor(alpha * 20 + 0.5) / 20
    local fresh = not host:IsShown()
    if fresh then
        host:SetAlpha((o and o.instant) and alpha or 0)
        host:Show()
    end
    host._off = nil
    if fresh or alpha ~= host.alpha or (o and o.instant) then
        host.alpha = alpha
        if not (Motion and Motion.FadeTo) then
            host:SetAlpha(alpha)
        elseif o and o.instant then
            Motion.FadeTo(host, alpha, nil)     -- at once, and any fade in flight dropped
        else
            Motion.FadeTo(host, alpha, FADE)
        end
    end
    -- the pulse: started when its speed step changes, stopped when steady
    local step = PulseStep(hz)
    if step ~= host.pulse or (step > 0 and Motion and not Motion.IsPlaying(host.pulser)) then
        host.pulse = step
        if Motion then
            Motion.Stop(host.pulser)
            if step > 0 then
                PULSE.duration = 2 / step
                Motion.Play(host.pulser, PULSE, "update")
            end
        end
    end
    return state
end

-- Off: the pulse stopped and the frame hidden (faded first when it was
-- up, unless instant).
function G.Off(host, instant)
    local Motion = ns.Motion
    host.state, host.intensity, host.hz = "off", 0, 0
    if host.pulse and host.pulse > 0 and Motion then Motion.Stop(host.pulser) end
    host.pulse = 0
    host.alpha = nil
    if not host:IsShown() then return end
    if instant or not (Motion and Motion.FadeTo) or not Motion.FadeTo(host, 0, FADE) then
        host._off = nil
        host:Hide()
        if Motion and Motion.FadeTo then Motion.FadeTo(host, 1, nil) else host:SetAlpha(1) end
        return
    end
    -- hidden once the fade is done (and nothing brought it back)
    host._off = true
    C_Timer.After(FADE.duration / ((Motion.Speed and Motion.Speed()) or 1) + 0.05, function()
        if host._off and host.state == "off" then
            host._off = nil
            host:Hide()
            Motion.FadeTo(host, 1, nil)
        end
    end)
end

-- ============================================================
-- THE LINE IN THE MIDDLE (the settings preview's copy)
-- ============================================================
-- In game every alert line goes through the game's raid-warning frame
-- (Meter_Threat's Center). The preview cannot use that frame (it sits on
-- the screen, and a test line there would be a real warning), so it
-- draws a faithful copy: the frame's own font (its first slot's, or the
-- font object it inherits, or the game font at 20), the alerts' red, the
-- frame's arrival (the text grows from 20 to 30 in 0.2 s and settles
-- back in 0.4 s: RaidWarning.lua's RAID_NOTICE_MIN_HEIGHT / MAX_HEIGHT /
-- SCALE_UP_TIME / SCALE_DOWN_TIME).
G.ALERT_MIN, G.ALERT_MAX, G.ALERT_UP, G.ALERT_DOWN = 20, 30, 0.2, 0.4
local OUTLINE_OF = { OUTLINE = "outline", THICKOUTLINE = "thick", MONOCHROME = "monochrome" }

local function SetHeightOf(line, h)
    line.textH = h
    if line.text.SetTextHeight then line.text:SetTextHeight(h) end
end

function G.AlertLine(parent)
    local line = CreateFrame("Frame", nil, parent)
    line:SetSize(10, G.ALERT_MAX + 6)
    line.text = line:CreateFontString(nil, "OVERLAY")
    line.text:SetPoint("CENTER", line, "CENTER", 0, 0)
    line.text:SetJustifyH("CENTER")
    if line.text.SetWordWrap then line.text:SetWordWrap(false) end
    line:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        SetHeightOf(self, G.ALERT_MIN)
    end)
    return line
end

-- the line's look and text; returns its width at rest and at its biggest
function G.StyleAlert(line, text)
    local src = _G.RaidWarningFrameSlot1 or _G.GameFontNormalHuge
    local face, _, flags
    if src and src.GetFont then face, _, flags = src:GetFont() end
    local spec = { face = face or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size = G.ALERT_MIN,
        outline = OUTLINE_OF[flags or ""] or "none", shadow = true, shadowX = 1, shadowY = -1 }
    if ns.ApplyFontSpec then ns.ApplyFontSpec(line.text, spec) end
    local T2 = Meter and Meter.Threat
    local c = (T2 and T2.CENTER_COLOR) or { r = 1, g = 0.15, b = 0.1 }
    line.text:SetTextColor(c.r, c.g, c.b, 1)
    line.text:SetText(text or "")
    SetHeightOf(line, line.textH or G.ALERT_MIN)
    local w = (line.text.GetStringWidth and line.text:GetStringWidth() or 0) * G.ALERT_MIN / (line.textH or G.ALERT_MIN)
    line:SetSize(math.max(10, math.ceil(w * G.ALERT_MAX / G.ALERT_MIN)), G.ALERT_MAX + 6)
    return w, w * G.ALERT_MAX / G.ALERT_MIN
end

-- the frame's arrival again (an OnUpdate on the line itself: it only
-- runs while the line is seen, and takes itself off when done)
function G.PlayAlert(line)
    line.elapsed = 0
    SetHeightOf(line, G.ALERT_MIN)
    line:SetScript("OnUpdate", function(self, el)
        self.elapsed = self.elapsed + (el or 0)
        local t = self.elapsed
        if t < G.ALERT_UP then
            SetHeightOf(self, floor(G.ALERT_MIN + (G.ALERT_MAX - G.ALERT_MIN) * t / G.ALERT_UP))
        elseif t < G.ALERT_UP + G.ALERT_DOWN then
            SetHeightOf(self, floor(G.ALERT_MAX - (G.ALERT_MAX - G.ALERT_MIN) * (t - G.ALERT_UP) / G.ALERT_DOWN))
        else
            SetHeightOf(self, G.ALERT_MIN)
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- ============================================================
-- LIVE
-- ============================================================
local live
local function Live()
    if not live then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:SetAllPoints(UIParent)
        holder:SetFrameStrata("LOW")
        if holder.EnableMouse then holder:EnableMouse(false) end
        live = G.Create(holder)
        G.frame = live
    end
    return live
end
G.Live = Live

-- Is this reading one we warn about at all? A mob with you on its list,
-- you not tanking it on purpose, a warrior not in Defensive Stance.
-- Only in a group (Zac 2026-11-04: "the screen flashing for threat was
-- going off when i was killing mobs in berserker stance in the open
-- world" - solo, every mob you fight is on you).
-- And only where the warnings run: a raid, or a party / dungeon with
-- "Also in dungeons" ticked (Zac 2026-11-04: annoying in dungeons where
-- he kills mobs on purpose in Berserker Stance).
local function Here(r)
    local T2 = Meter and Meter.Threat
    if T2 and T2.WarnHere then return T2.WarnHere(r) end
    return IsInRaid() and true or false
end
G.Here = Here
local function Eligible(r)
    if not (r and r.active) or r.onPurpose then return false end
    if G.isWarrior and r.tankForm then return false end
    if not Here(r) then return false end
    return true
end
-- the glow's own rule on top: past the quiet start
function G.Warns(r)
    return Eligible(r) and r.settled and true or false
end

local function Say(text)
    local T2 = Meter and Meter.Threat
    if T2 and T2.Say then T2.Say(text) end
end
local function Center(text)
    local T2 = Meter and Meter.Threat
    if T2 and T2.Center then T2.Center(text) end
end

-- the alerts' state: one per pull (reset when combat ends)
local warn = { fired = false, lastPull = -100 }
G.openerUntil = 0
G.stat = { openers = 0, pullWarns = 0 }

local voiceDue = nil
local function Alerts(r, now)
    if not Eligible(r) or r.tanking then return end
    local pullIn = r.pullIn
    if not pullIn then return end
    -- the weak opener: once a pull, judged 1 to 5 s in
    if not warn.fired and r.worth and G.OpenerOn() and r.since and r.since >= G.OPENER_FROM
        and r.since <= G.OPENER_TO and pullIn <= G.OpenerAt() then
        warn.fired = true
        G.openerUntil = now + G.OPENER_GLOW
        G.stat.openers = G.stat.openers + 1
        G.lastOpenerAt = now
        Center(G.OPENER_TEXT)              -- the line and its sound, now
        voiceDue = G.OPENER_VOICE          -- said after the glow is up
    end
    -- the pull warning: later, a pull a few seconds away
    if r.settled and pullIn <= G.PULL_WARN_AT and G.PullWarnOn() and now - warn.lastPull >= G.PULL_WARN_EVERY then
        warn.lastPull = now
        G.stat.pullWarns = G.stat.pullWarns + 1
        Center(PULL_TEXT[min(3, max(1, ceil(pullIn)))])
    end
end

local applyOpts = { pullIn = nil, opener = false }
local function Glow(r, now)
    if not G.On() then
        if live and live:IsShown() then G.Off(live, true) end
        return
    end
    local opener = now < G.openerUntil
    if not Eligible(r) or not (r.settled or opener) then
        if live and live:IsShown() then G.Off(live) end
        return
    end
    applyOpts.pullIn = r.settled and r.pullIn or nil
    applyOpts.opener = opener
    local c = G.Cfg()
    -- the "it turned on you" flash: an elite or a boss only (a normal mob
    -- on you in a group is no emergency)
    local pulled = r.pulled and r.worth
    local state = G.Level(r.pct, pulled, c, applyOpts.pullIn, opener)
    if state == "off" and not (live and live:IsShown()) then return end   -- off and hidden: nothing to do
    G.Apply(Live(), r.pct, pulled, c, applyOpts)
end

local function Update(r, now, stopped)
    if stopped then
        warn.fired, warn.lastPull, G.openerUntil = false, -100, 0
        if live then G.Off(live, true) end
        return
    end
    Alerts(r, now)
    Glow(r, now)
    if voiceDue then
        local v = voiceDue
        voiceDue = nil
        Say(v)
    end
end

ns.ThreatConsumers = ns.ThreatConsumers or {}
ns.ThreatConsumers.glow = {
    wants = function() return G.On() or G.OpenerOn() or G.PullWarnOn() end,
    update = Update,
}

-- the page changed an option: the reader starts / stops, and a glow that
-- is up repaints at once
function G.ApplyOptions()
    if live then
        live._r = nil
        if not G.On() then G.Off(live, true) end
    end
    if ns.Threat and ns.Threat.Refresh then ns.Threat.Refresh() end
end
