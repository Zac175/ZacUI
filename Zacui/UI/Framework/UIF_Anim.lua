-- UIF_Anim - the motion layer: the four window helpers and ns.Motion,
-- the show / hide / highlight animations every part of ZacUI plays.
-- Part of ZacUI; load order is set by the TOC.
--
-- Deliberately NOT AnimationGroups. Groups are cheaper, but they own the
-- frame's alpha and scale for the duration, which fights every other
-- thing in this addon that writes alpha (the classifier, the hide-forever
-- hooks, the mover proxies). A ticker that interpolates and then stops
-- leaves the frame in a plain, writable state the moment it finishes.
--
-- HOUSE TIMINGS - short. This is a config window, not a cutscene:
--   fade   0.20s   pop in 0.15s   pop out 0.10s
-- Hover states are NOT animated anywhere in ZacUI. A tween on hover makes
-- a dense settings list feel laggy; every OnEnter/OnLeave is an immediate
-- colour swap.
--
-- THE GLOBAL SWITCHES (Appearance > Motion, ZacUIDB.motion):
--   enabled  false = every animation here is an instant change
--   speed    a multiplier on every duration and delay (2 = twice as fast)
-- Both are read at the moment an animation starts, never cached.

local ADDON_NAME, ns = ...

local STEP = 0.016 -- ~60fps; matches the client's own frame cadence

-- Every curve takes 0..1 and returns 0..1 at the ends (the overshooting
-- ones pass beyond 1 on the way).
local EASE = {
    linear       = function(t) return t end,
    easeOutQuad  = function(t) return 1 - (1 - t) * (1 - t) end,
    easeInQuad   = function(t) return t * t end,
    easeOutCubic = function(t) return 1 - (1 - t) ^ 3 end,
    easeInOutQuad = function(t)
        if t < 0.5 then return 2 * t * t end
        return 1 - ((-2 * t + 2) ^ 2) / 2
    end,
    easeOutBack  = function(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
    end,
    easeInBack   = function(t)
        local c1 = 1.70158
        return (c1 + 1) * t * t * t - c1 * t * t
    end,
    easeOutBounce = function(t)
        local n1, d1 = 7.5625, 2.75
        if t < 1 / d1 then
            return n1 * t * t
        elseif t < 2 / d1 then
            t = t - 1.5 / d1
            return n1 * t * t + 0.75
        elseif t < 2.5 / d1 then
            t = t - 2.25 / d1
            return n1 * t * t + 0.9375
        end
        t = t - 2.625 / d1
        return n1 * t * t + 0.984375
    end,
}

-- ============================================================
-- GLOBAL SETTINGS
-- ============================================================
-- nil-tolerant on purpose: a profile saved before this setting existed
-- arrives without ZacUIDB.motion, and that must read as "on, normal speed".
local function MotionEnabled()
    local m = ZacUIDB and ZacUIDB.motion
    return not (m and m.enabled == false)
end

local function MotionSpeed()
    local m = ZacUIDB and ZacUIDB.motion
    local s = m and tonumber(m.speed)
    if not s or s <= 0 then return 1 end
    return math.max(0.1, math.min(5, s))
end

-- ============================================================
-- THE TICKER
-- ============================================================
-- One ticker per frame, cancelled on replacement: starting a second
-- animation on a frame mid-flight must not leave two tickers fighting
-- over the same alpha (the classic "it flickers when you spam Escape").
local function Stop(frame)
    if frame._zAnim then
        frame._zAnim:Cancel()
        frame._zAnim = nil
    end
end

local function Animate(frame, dur, easing, apply, onDone)
    if not frame then return end
    Stop(frame)
    local ease = EASE[easing or "easeOutQuad"] or EASE.easeOutQuad
    if not dur or dur <= 0 then
        apply(1)
        if onDone then onDone() end
        return
    end
    -- REAL TIME, not tick count. Accumulating STEP assumes the ticker
    -- fires at exactly 60fps; at 30fps a "0.2s" fade takes 0.4s, and
    -- through a loading spike it visibly stalls. GetTime is the clock the
    -- client itself uses.
    local started = GetTime()
    local ticker
    ticker = C_Timer.NewTicker(STEP, function(self)
        local t = (GetTime() - started) / dur
        if t >= 1 then
            t = 1
            self:Cancel()
            -- only clear the slot if it is still ours: onDone below may
            -- already have started the next animation on this frame
            if frame._zAnim == self or frame._zAnim == ticker then frame._zAnim = nil end
        end
        apply(ease(t))
        if t >= 1 and onDone then onDone() end
    end)
    frame._zAnim = ticker
end

-- PopIn/PopOut scale as well as fade, and finish on the frame's OWN
-- scale - the one it had before the pop began - exactly. Not 1: the
-- config window carries a scale of its own (its +/- buttons), and every
-- open used to put it back to 100%. Not the interpolated value either: a
-- frame parked at 0.9999 scale renders its 1px borders blurry. The base
-- is kept on the frame until a pop completes, so a reopen that lands
-- mid-close starts from the true scale, not the half-shrunk one.
local function PopBase(frame)
    local base = frame._zPopBase or frame:GetScale() or 1
    frame._zPopBase = base
    return base
end

local function PopDur(dur)
    if not MotionEnabled() then return 0 end
    return dur / MotionSpeed()
end

local function PopIn(frame, dur)
    if not frame then return end
    local base = PopBase(frame)
    frame:SetAlpha(0)
    frame:SetScale(base * 0.94)
    frame:Show()
    Animate(frame, PopDur(dur or 0.15), "easeOutCubic", function(p)
        frame:SetAlpha(p)
        frame:SetScale(base * (0.94 + 0.06 * p))
    end, function()
        frame:SetAlpha(1)
        frame:SetScale(base)
        frame._zPopBase = nil
    end)
end

local function PopOut(frame, dur, onDone)
    if not frame or not frame:IsShown() then
        if onDone then onDone() end
        return
    end
    local base = PopBase(frame)
    Animate(frame, PopDur(dur or 0.1), "easeInOutQuad", function(p)
        frame:SetAlpha(1 - p)
        frame:SetScale(base * (1 - 0.06 * p))
    end, function()
        frame:Hide()
        frame:SetAlpha(1)
        frame:SetScale(base)
        frame._zPopBase = nil
        if onDone then onDone() end
    end)
end

-- ============================================================
-- MOTION - show, hide and highlight animations for any frame
-- ============================================================
--   ns.Motion.Play(frame, spec, "in" | "out" | "update", onDone) -> bool
--   ns.Motion.Show(frame, spec, onDone)    = Play(frame, spec, "in", ...)
--   ns.Motion.Hide(frame, spec, onDone)    = Play(frame, spec, "out", ...)
--   ns.Motion.Stop(frame)                  stop, put the frame back at rest
--   ns.Motion.StopTree(root)               Stop on root and everything under it
--   ns.Motion.IsPlaying(frame)
--   ns.Motion.Normalize(spec)              a full copy with defaults filled
--   ns.Motion.Enabled() / Speed()          the global switches
--
-- THE SPEC (the standard animation setting every module saves):
--   { style    = "none"|"fade"|"slide"|"pop"|"pulse"|"bounce"|"flash",
--     duration = seconds, delay = seconds, easing = an EASE key,
--     dir      = "left"|"right"|"up"|"down"  the side it comes in from
--                                             and leaves to (slide, bounce),
--     distance = pixels (slide, bounce),
--     loop     = true: pulse / flash repeat until stopped or hidden }
--
-- "in" shows the frame and animates it into place, "out" animates it
-- away and hides it, "update" plays the style as a highlight without
-- changing whether it is shown (a value changed, a proc fired).
--
-- AT REST, EXACTLY. When a play starts, the frame's anchors, alpha and
-- scale are taken as its rest; when it ends - finished, stopped or
-- replaced - every one of them is put back exactly, and an "out" hides
-- the frame first so the next Show is already at rest. A play that
-- replaces one in flight keeps the first rest, so spamming show/hide
-- never ratchets a frame off its spot. onDone runs only when a play
-- finishes on its own, never when it is stopped or replaced.
--
-- Don't move or rescale a frame while it animates: the end puts back the
-- anchors it started from. Call Motion.Stop(frame) first, then move it.
-- A protected frame in combat is never touched (the client would refuse
-- the Show/Hide and the anchors anyway): Play returns false and onDone
-- runs straight away - the caller still owns that frame's visibility.
--
-- PROTECTED means the client calls the frame protected (a bar holding
-- secure action buttons is, implicitly) or the caller said so with
-- ns.Motion.SetProtected(frame). A play already running on one when
-- combat starts is finished on PLAYER_REGEN_DISABLED, while the client
-- still allows it: back on its anchor and scale, shown or hidden as the
-- play would have left it, onDone called. MoveTo / SizeTo glides on one
-- jump to their target then. A play started during that event ends at
-- once. If the lock still lands mid-play, the ticks write alpha only and
-- the anchors, scale and a pending hide are put back when combat ends.
local Motion = {}

Motion.STYLES = {
    { id = "none",   label = "None" },
    { id = "fade",   label = "Fade" },
    { id = "slide",  label = "Slide" },
    { id = "pop",    label = "Pop" },
    { id = "pulse",  label = "Pulse" },
    { id = "bounce", label = "Bounce" },
    { id = "flash",  label = "Flash" },
}
Motion.EASINGS = {
    { id = "easeOutQuad",   label = "Smooth" },
    { id = "easeOutCubic",  label = "Quick start" },
    { id = "easeInOutQuad", label = "Smooth both ends" },
    { id = "easeInQuad",    label = "Speed up" },
    { id = "linear",        label = "Steady" },
    { id = "easeOutBack",   label = "Overshoot" },
    { id = "easeOutBounce", label = "Bounce" },
}
Motion.DIRS = {
    { id = "up",    label = "Above" },
    { id = "down",  label = "Below" },
    { id = "left",  label = "Left" },
    { id = "right", label = "Right" },
}
-- the styles that use direction + distance, and the ones that can loop
Motion.MOVES = { slide = true, bounce = true }
Motion.LOOPS = { pulse = true, flash = true }

Motion.DEFAULT = { style = "fade", duration = 0.25, delay = 0, easing = "easeOutQuad",
                   dir = "up", distance = 20, loop = false }

local VALID_STYLE = {}
for _, s in ipairs(Motion.STYLES) do VALID_STYLE[s.id] = true end
local DIR_VEC = { up = { 0, 1 }, down = { 0, -1 }, left = { -1, 0 }, right = { 1, 0 } }

function Motion.Normalize(spec)
    local d, out = Motion.DEFAULT, {}
    spec = type(spec) == "table" and spec or {}
    out.style = VALID_STYLE[spec.style] and spec.style or d.style
    out.duration = math.max(0, tonumber(spec.duration) or d.duration)
    out.delay = math.max(0, tonumber(spec.delay) or d.delay)
    out.easing = EASE[spec.easing or ""] and spec.easing or d.easing
    out.dir = DIR_VEC[spec.dir or ""] and spec.dir or d.dir
    out.distance = tonumber(spec.distance) or d.distance
    out.loop = spec.loop and true or false
    return out
end

Motion.Enabled = MotionEnabled
Motion.Speed = MotionSpeed
Motion.EASE = EASE

-- the vector from an anchor point on a frame to the frame's centre, in
-- the frame's own units
local CENTRE = {
    CENTER = { 0, 0 }, TOP = { 0, -0.5 }, BOTTOM = { 0, 0.5 },
    LEFT = { 0.5, 0 }, RIGHT = { -0.5, 0 },
    TOPLEFT = { 0.5, -0.5 }, TOPRIGHT = { -0.5, -0.5 },
    BOTTOMLEFT = { 0.5, 0.5 }, BOTTOMRIGHT = { -0.5, 0.5 },
}

local function Capture(frame)
    local rest = {
        alpha = frame:GetAlpha() or 1,
        scale = frame:GetScale() or 1,
        points = {},
    }
    local n = frame.GetNumPoints and frame:GetNumPoints() or 0
    -- A frame hung from a nameplate (the Hesitation plate row) can't be
    -- measured: the client refuses GetPoint on anything anchored to a
    -- restricted region and throws (Zac 2026-11-02, 61x per fight). Then
    -- the frame keeps its points untouched and only fades / scales - an
    -- empty points list is exactly that in Pose.
    for i = 1, n do
        local ok, p, rel, rp, x, y = pcall(frame.GetPoint, frame, i)
        if not ok then
            rest.points = {}
            rest.restricted = true
            break
        end
        if p then rest.points[#rest.points + 1] = { p, rel, rp or p, x or 0, y or 0 } end
    end
    return rest
end

-- Put the frame at (alpha a, scale s, offset dx/dy) relative to its rest.
-- A frame hung from ONE point keeps its centre still while it scales (a
-- pop grows from the middle, not from whichever corner it is anchored
-- by); a frame stretched between several points slides and scales as-is.
-- alphaOnly: a protected frame in combat, nothing but the alpha.
local function Pose(frame, rest, a, s, dx, dy, moves, alphaOnly)
    frame:SetAlpha(math.max(0, math.min(1, rest.alpha * a)))
    if alphaOnly then return end
    if s ~= 1 or frame:GetScale() ~= rest.scale then
        frame:SetScale(math.max(0.01, rest.scale * s))
    end
    if not moves then return end
    local pts = rest.points
    if #pts == 0 then return end
    frame:ClearAllPoints()
    if #pts == 1 then
        local p = pts[1]
        local c = CENTRE[p[1]] or CENTRE.CENTER
        local cx, cy = c[1] * (frame:GetWidth() or 0), c[2] * (frame:GetHeight() or 0)
        frame:SetPoint(p[1], p[2], p[3], (p[4] + dx + cx) / s - cx, (p[5] + dy + cy) / s - cy)
    else
        for _, p in ipairs(pts) do
            frame:SetPoint(p[1], p[2], p[3], (p[4] + dx) / s, (p[5] + dy) / s)
        end
    end
end

local function RestoreGeometry(frame, rest)
    frame:SetScale(rest.scale)
    if #rest.points > 0 then
        frame:ClearAllPoints()
        for _, p in ipairs(rest.points) do frame:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    end
end

local function Restore(frame, rest)
    frame:SetAlpha(rest.alpha)
    RestoreGeometry(frame, rest)
end

-- COMBAT. running: frames with a play (weak, pruned as it goes). owed:
-- frame -> { rest, how } whose anchors, scale or hide the lock kept back,
-- put right on PLAYER_REGEN_ENABLED. lockPending: inside
-- PLAYER_REGEN_DISABLED, until the lock itself starts.
local running = setmetatable({}, { __mode = "k" })
local owed = setmetatable({}, { __mode = "k" })
local lockPending = false

-- looked up at call time: Interface 16001 may not have it
local function InLockdown()
    local f = _G.InCombatLockdown
    return f ~= nil and f() and true or false
end

-- the client's word (a frame holding secure buttons is implicitly
-- protected) or the caller's flag; cheap enough for every tick
local function Secure(frame)
    if frame._zMotionProtected then return true end
    return (frame.IsProtected and frame:IsProtected()) and true or false
end

-- the first rest owed is the true one; a later ending only updates
-- whether the frame still has to be hidden
local function Owe(frame, rest, how)
    local d = owed[frame]
    if d then d.how = how else owed[frame] = { rest = rest, how = how } end
end

-- One state per animating frame. `token` changes on every new play or
-- stop, so a delay timer or a loop that outlived its play does nothing.
local function Halt(frame, keepState)
    local st = frame._zMotion
    if not st then return nil end
    st.token = st.token + 1
    Stop(frame)
    if not keepState then
        if st.secure and InLockdown() then
            Owe(frame, st.rest, nil)
            frame:SetAlpha(st.rest.alpha)
        else
            Restore(frame, st.rest)
        end
        frame._zMotion = nil
    end
    return st
end

-- Caller flag for a frame the client does not call protected but that
-- must be treated as one (on = false clears it).
function Motion.SetProtected(frame, on)
    if frame then frame._zMotionProtected = (on ~= false) or nil end
end

function Motion.Stop(frame)
    if frame then Halt(frame) end
end

function Motion.IsPlaying(frame)
    return frame ~= nil and frame._zMotion ~= nil
end

function Motion.StopTree(root, depth)
    if not root or (depth or 0) > 10 then return end
    if root._zMotion then Halt(root) end
    if root.GetChildren then
        for _, c in ipairs({ root:GetChildren() }) do Motion.StopTree(c, (depth or 0) + 1) end
    end
end

-- THE CURVES. Each returns alpha, scale, dx, dy for time t (0..1) and the
-- eased value e, for one direction. D is the distance, (vx, vy) the unit
-- vector of the side the frame comes in from.
local function Bump(t) return math.sin(math.pi * t) end
local function Blink(t) return 1 - 0.8 * (0.5 - 0.5 * math.cos(2 * math.pi * 2 * t)) end

local CURVES = {
    fade = {
        ["in"]  = function(t, e) return e, 1, 0, 0 end,
        ["out"] = function(t, e) return 1 - e, 1, 0, 0 end,
        update  = function(t) return 1 - 0.6 * Bump(t), 1, 0, 0 end,
    },
    slide = {
        ["in"]  = function(t, e, D, vx, vy) local k = (1 - e) * D return math.min(1, e * 1.4), 1, vx * k, vy * k end,
        ["out"] = function(t, e, D, vx, vy) local k = e * D return 1 - e, 1, vx * k, vy * k end,
        update  = function(t, e, D, vx, vy) local k = Bump(t) * D * 0.3 return 1, 1, vx * k, vy * k end,
    },
    pop = {
        ["in"]  = function(t, e) return math.min(1, t * 2.5), 0.5 + 0.5 * e, 0, 0 end,
        ["out"] = function(t, e) return 1 - e, 1 - 0.5 * e, 0, 0 end,
        update  = function(t) return 1, 1 + 0.18 * Bump(t), 0, 0 end,
    },
    pulse = {
        ["in"]  = function(t) return math.min(1, t * 3), 1 + 0.15 * Bump(t), 0, 0 end,
        ["out"] = function(t, e) return 1 - e, 1 + 0.15 * e, 0, 0 end,
        update  = function(t) return 1, 1 + 0.15 * Bump(t), 0, 0 end,
        loop    = function(t) return 1, 1 + 0.15 * Bump(t), 0, 0 end,
    },
    bounce = {
        ["in"]  = function(t, e, D, vx, vy) local k = (1 - EASE.easeOutBounce(t)) * D return math.min(1, t * 4), 1, vx * k, vy * k end,
        ["out"] = function(t, e, D, vx, vy) local k = EASE.easeInBack(t) * D return 1 - t, 1, vx * k, vy * k end,
        update  = function(t, e, D, vx, vy) local k = math.abs(math.sin(math.pi * 2 * t)) * (1 - t) * D * 0.4 return 1, 1, vx * k, vy * k end,
    },
    flash = {
        ["in"]  = function(t) return Blink(t), 1, 0, 0 end,
        ["out"] = function(t) return Blink(t) * (1 - t), 1, 0, 0 end,
        update  = function(t) return Blink(t), 1, 0, 0 end,
        loop    = function(t) return Blink(t), 1, 0, 0 end,
    },
}
-- the bounce and flash curves shape themselves; their easing is ignored
local OWN_TIMING = { bounce = true, flash = true, pulse = true }

local function Protected(frame)
    return Secure(frame) and InLockdown()
end

local function Finish(frame, how, onDone)
    if how == "in" then frame:Show() elseif how == "out" then frame:Hide() end
    if onDone then onDone() end
end

function Motion.Play(frame, spec, how, onDone)
    if not frame then return false end
    how = (how == "out" or how == "update") and how or "in"
    local secure = Secure(frame)
    if secure and InLockdown() then
        if onDone then onDone() end
        return false
    end
    local s = Motion.Normalize(spec)
    -- The rest is the frame before the FIRST play of a chain: a play that
    -- replaces one in flight takes over its rest instead of the half-way
    -- pose the frame is in right now. Anchors the lock kept back come
    -- first of all.
    local prev = Halt(frame, true)
    local debt = owed[frame]
    owed[frame] = nil
    local rest = prev and prev.rest or (debt and debt.rest) or Capture(frame)

    local speed = MotionSpeed()
    local dur = s.duration / speed
    local curve = CURVES[s.style]
    -- PLAYER_REGEN_DISABLED is the last moment a protected frame can
    -- move: no time to animate, end it now
    if secure and lockPending then dur = 0 end
    if not MotionEnabled() or s.style == "none" or not curve or dur <= 0 then
        Restore(frame, rest)
        frame._zMotion = nil
        Finish(frame, how, onDone)
        return false
    end
    -- "update" on a hidden frame has nothing to show, and "out" on one
    -- has nothing to take away
    if how ~= "in" and not frame:IsShown() then
        Restore(frame, rest)
        frame._zMotion = nil
        if onDone then onDone() end
        return false
    end

    local st = { rest = rest, token = (prev and prev.token or 0) + 1, how = how, secure = secure }
    frame._zMotion = st
    running[frame] = true
    local token = st.token
    local vec = DIR_VEC[s.dir]
    local D = s.distance
    local moves = Motion.MOVES[s.style] or s.style == "pop" or s.style == "pulse"
    local ease = OWN_TIMING[s.style] and "linear" or s.easing
    local fn = curve[how]
    local looping = s.loop and Motion.LOOPS[s.style] and how ~= "out"

    -- a protected frame the lock reached mid-play: alpha only
    local function Held() return secure and InLockdown() end

    local function Apply(eased, raw)
        local a, sc, dx, dy = fn(raw, eased, D, vec[1], vec[2])
        Pose(frame, rest, a, sc, dx, dy, moves, Held())
    end

    local function End()
        frame._zMotion = nil
        if Held() then
            Owe(frame, rest, how)
            frame:SetAlpha(how == "out" and 0 or rest.alpha)
        else
            if how == "out" then frame:Hide() end
            Restore(frame, rest)
        end
        if onDone then onDone() end
    end

    local function Done()
        if frame._zMotion ~= st or st.token ~= token then return end
        End()
    end

    -- combat is starting: the end state now. An entrance its owner hid
    -- on the way stays hidden.
    st.finish = function()
        if frame._zMotion ~= st or st.token ~= token then return end
        st.token = st.token + 1
        Stop(frame)
        if how == "in" and not frame:IsShown() then
            frame._zMotion = nil
            Restore(frame, rest)
            if onDone then onDone() end
            return
        end
        End()
    end

    local Cycle
    -- One pass of the loop curve, again and again while the frame is on
    -- screen. A hidden frame (its window closed, its page changed) ends
    -- the loop and is put back at rest: nothing keeps ticking unseen.
    Cycle = function()
        if frame._zMotion ~= st or st.token ~= token then return end
        if not frame:IsVisible() then
            frame._zMotion = nil
            if Held() then
                Owe(frame, rest, nil)
                frame:SetAlpha(rest.alpha)
            else
                Restore(frame, rest)
            end
            return
        end
        local lf = curve.loop or fn
        Animate(frame, dur, "linear", function(p)
            local a, sc, dx, dy = lf(p, p, D, vec[1], vec[2])
            Pose(frame, rest, a, sc, dx, dy, moves, Held())
        end, Cycle)
    end

    local function Begin()
        if frame._zMotion ~= st or st.token ~= token then return end
        if how == "in" and not Held() then frame:Show() end
        -- the first pass needs the per-tick raw time as well as the eased
        -- value (the bounce shapes itself), so it wraps Animate's apply
        local started = GetTime()
        Animate(frame, dur, ease, function(e)
            Apply(e, math.min(1, (GetTime() - started) / dur))
        end, looping and Cycle or Done)
    end

    -- the start pose straight away, so an "in" with a delay is not seen
    -- at rest for the length of the delay
    if how == "in" then
        Apply(EASE[ease](0), 0)
        frame:Show()
    end
    local delay = s.delay / speed
    if delay > 0 then
        C_Timer.After(delay, Begin)
    else
        Begin()
    end
    return true
end

function Motion.Show(frame, spec, onDone) return Motion.Play(frame, spec, "in", onDone) end
function Motion.Hide(frame, spec, onDone) return Motion.Play(frame, spec, "out", onDone) end

-- ============================================================
-- FADE TO - an alpha move from wherever the frame is to a new value
-- ============================================================
--   ns.Motion.FadeTo(frame, alpha, spec, delay) -> true if it animates
--   ns.Motion.FadeBusy(frame)   waiting out its delay or mid-fade
--
-- Not a show/hide: the frame stays shown and only its alpha moves, from
-- what it is now to `alpha`, over the spec's duration and easing (its
-- style only matters as "none" = at once). spec nil, style "none",
-- Motion switched off or a zero duration set the alpha at once. `delay`
-- (seconds) overrides the spec's own; the global speed divides both.
-- A new FadeTo replaces one in flight (or still waiting) and starts from
-- where the frame is.
--
-- SAFE ON PROTECTED FRAMES IN COMBAT: alpha is the one thing an addon
-- may always write, and nothing else is touched - a secure bar header
-- that fades on mouseover (Zacui_Bars) uses this. Don't mix it with a
-- Motion.Play on the same frame (both own the alpha).
function Motion.FadeTo(frame, target, spec, delay)
    if not frame then return false end
    target = tonumber(target) or 1
    frame._zFadeTo = target
    frame._zFadeSerial = (frame._zFadeSerial or 0) + 1
    local serial = frame._zFadeSerial
    frame._zFadeWait = nil
    local s = spec and Motion.Normalize(spec) or nil
    if not (s and MotionEnabled() and s.style ~= "none" and s.duration > 0) then
        Stop(frame)
        frame:SetAlpha(target)
        return false
    end
    local speed = MotionSpeed()
    local dur = s.duration / speed
    local wait = ((delay ~= nil) and delay or s.delay or 0) / speed
    local function Begin()
        if frame._zFadeSerial ~= serial then return end
        frame._zFadeWait = nil
        local from = frame:GetAlpha() or target
        if math.abs(from - target) < 0.005 then
            Stop(frame)
            frame:SetAlpha(target)
            return
        end
        Animate(frame, dur, s.easing, function(p)
            frame:SetAlpha(from + (target - from) * p)
        end)
    end
    if wait > 0 then
        frame._zFadeWait = true
        C_Timer.After(wait, Begin)
    else
        Begin()
    end
    return true
end

function Motion.FadeBusy(frame)
    return (frame and (frame._zFadeWait or frame._zAnim ~= nil)) and true or false
end

-- ============================================================
-- TWEEN - a value glided from where it is to a new one
-- ============================================================
--   ns.Motion.Tween(frame, key, to, spec, get, set) -> true if it animates
--   ns.Motion.MoveTo(frame, x, y, spec)     the offsets of its (one) anchor
--   ns.Motion.SizeTo(frame, w, h, spec)
--   ns.Motion.TweenStop(frame, key)         stop now, at the target
--   ns.Motion.IsTweening(frame, key)
--
-- For a frame moving between two RESTING values - a row sliding to its
-- new place, a box growing as its content does, an icon drifting along a
-- bar - which Play (show/hide from a rest it puts back) is not. `key`
-- names the channel ("x", "w", or anything of your own: one frame can
-- move several at once); get(frame) reads the value now, set(frame, v)
-- writes one. A new target for a channel in flight starts a fresh glide
-- from where it is; the same target again is left alone.
--
-- ONE DRIVER for every tween in ZacUI, an OnUpdate shown only while
-- something moves (forty plates gliding cost one script, and nothing runs
-- at rest). A frame that is hidden mid-glide jumps to its target and its
-- channel ends: nothing ticks unseen. spec nil / "none" / Motion off /
-- a hidden frame = set at once (the spec's duration, delay and easing are
-- used; its style only matters as "none"). Positions and sizes are
-- protected on secure frames in combat: MoveTo/SizeTo on one then do
-- nothing at all and return false - the caller decides what happens
-- after combat (alpha has FadeTo, which is always allowed).
local tweens = {}            -- frame -> { key -> channel }
local driver
-- the setters that move or size a frame (MoveTo / SizeTo), filled below;
-- a channel using one on a protected frame is marked `secure`
local GEO_SET = {}
-- frame -> { key -> { set, to } }: glides the lock cut short, set on
-- PLAYER_REGEN_ENABLED
local owedTween = setmetatable({}, { __mode = "k" })
local function Drive()
    local now = GetTime()
    local any = false
    for f, rec in pairs(tweens) do
        local live = false
        for key, ch in pairs(rec) do
            if ch.on and ch.secure and InLockdown() then
                -- the lock landed mid-glide: stop here, finish after combat
                ch.on = false
                owedTween[f] = owedTween[f] or {}
                owedTween[f][key] = { set = ch.set, to = ch.to }
            elseif ch.on then
                local t = (now - ch.start) / ch.dur
                if t >= 1 or not f:IsVisible() then
                    ch.on = false
                    ch.set(f, ch.to)
                elseif t > 0 then
                    ch.set(f, ch.from + (ch.to - ch.from) * ch.ease(t))
                    live = true
                else
                    live = true          -- still in its delay
                end
            end
        end
        if live then any = true else tweens[f] = nil end
    end
    if not any and driver then driver:Hide() end
end

function Motion.Tween(frame, key, to, spec, get, set)
    if not (frame and key and type(set) == "function") then return false end
    to = tonumber(to)
    if not to then return false end
    local rec = tweens[frame]
    local ch = rec and rec[key]
    if ch and ch.on then
        if ch.to == to then return true end
        ch.on = false
    end
    local s = spec and Motion.Normalize(spec) or nil
    local speed = MotionSpeed()
    local dur = s and (s.duration / speed) or 0
    local cur = get and tonumber(get(frame)) or nil
    local secure = GEO_SET[set] and Secure(frame) or false
    if not (s and s.style ~= "none" and MotionEnabled() and dur > 0 and cur and frame:IsVisible())
        or math.abs(cur - to) < 0.0005 or (secure and lockPending) then
        set(frame, to)
        return false
    end
    if owedTween[frame] then owedTween[frame][key] = nil end
    if not rec then rec = {} tweens[frame] = rec end
    ch = rec[key] or {}
    rec[key] = ch
    ch.on, ch.from, ch.to, ch.set, ch.secure = true, cur, to, set, secure
    ch.start, ch.dur = GetTime() + s.delay / speed, dur
    ch.ease = EASE[s.easing] or EASE.easeOutQuad
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", Drive)
    end
    driver:Show()
    return true
end

function Motion.TweenStop(frame, key)
    local rec = frame and tweens[frame]
    if not rec then return end
    for k, ch in pairs(rec) do
        if (key == nil or k == key) and ch.on then
            ch.on = false
            ch.set(frame, ch.to)
        end
    end
end

function Motion.IsTweening(frame, key)
    local rec = frame and tweens[frame]
    if not rec then return false end
    for k, ch in pairs(rec) do
        if ch.on and (key == nil or k == key) then return true end
    end
    return false
end

-- the offsets of a frame's first anchor; the anchor itself stays
-- (pcall: a frame hung from a nameplate can't be measured - the client
-- throws - and then the tween simply has nothing to move)
local function AnchorOffset(i)
    return function(f)
        local ok, _, _, _, x, y = pcall(f.GetPoint, f, 1)
        if not ok then return 0 end
        if i == 1 then return x or 0 end
        return y or 0
    end
end
local function SetAnchorOffset(i)
    return function(f, v)
        local ok, p, rel, rp, x, y = pcall(f.GetPoint, f, 1)
        if not ok or not p then return end
        if i == 1 then x = v else y = v end
        f:SetPoint(p, rel, rp, x or 0, y or 0)
    end
end
local getX, getY, setX, setY = AnchorOffset(1), AnchorOffset(2), SetAnchorOffset(1), SetAnchorOffset(2)
local function getW(f) local ok, v = pcall(f.GetWidth, f) return ok and v or 0 end
local function getH(f) local ok, v = pcall(f.GetHeight, f) return ok and v or 0 end
local function setW(f, v) f:SetWidth(math.max(0, v)) end
local function setH(f, v) f:SetHeight(math.max(0, v)) end
GEO_SET[setX], GEO_SET[setY], GEO_SET[setW], GEO_SET[setH] = true, true, true, true

function Motion.MoveTo(frame, x, y, spec)
    if not frame or Protected(frame) then return false end
    local a = x ~= nil and Motion.Tween(frame, "x", x, spec, getX, setX)
    local b = y ~= nil and Motion.Tween(frame, "y", y, spec, getY, setY)
    return (a or b) and true or false
end

function Motion.SizeTo(frame, w, h, spec)
    if not frame or Protected(frame) then return false end
    local a = w ~= nil and Motion.Tween(frame, "w", w, spec, getW, setW)
    local b = h ~= nil and Motion.Tween(frame, "h", h, spec, getH, setH)
    return (a or b) and true or false
end

-- ============================================================
-- COMBAT START AND END
-- ============================================================
-- PLAYER_REGEN_DISABLED fires just before the lock, while a protected
-- frame can still be moved, shown and hidden: every play on one ends at
-- its end state and every MoveTo / SizeTo glide on one jumps to its
-- target. PLAYER_REGEN_ENABLED puts back whatever the lock kept back.
local function FinishProtected()
    local list = {}
    for f in pairs(running) do
        local st = f._zMotion
        if not st then
            running[f] = nil
        elseif st.finish and (st.secure or Secure(f)) then
            list[#list + 1] = f
        end
    end
    for _, f in ipairs(list) do
        local st = f._zMotion
        if st and st.finish then st.finish() end
    end
    for f, rec in pairs(tweens) do
        for _, ch in pairs(rec) do
            if ch.on and (ch.secure or (GEO_SET[ch.set] and Secure(f))) then
                ch.on = false
                ch.set(f, ch.to)
            end
        end
    end
end

local function SettleOwed()
    if InLockdown() then return end
    local list = {}
    for f in pairs(owed) do list[#list + 1] = f end
    for _, f in ipairs(list) do
        local d = owed[f]
        owed[f] = nil
        if d and not f._zMotion then
            if d.how == "out" then f:Hide() end
            Restore(f, d.rest)
        end
    end
    local tl = {}
    for f in pairs(owedTween) do tl[#tl + 1] = f end
    for _, f in ipairs(tl) do
        local keys = owedTween[f]
        owedTween[f] = nil
        local rec = tweens[f]
        for key, o in pairs(keys) do
            -- a newer glide on the channel owns it now
            if not (rec and rec[key] and rec[key].on) then o.set(f, o.to) end
        end
    end
end

if CreateFrame then
    local ev = CreateFrame("Frame")
    if ev and ev.RegisterEvent and ev.SetScript then
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        ev:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                lockPending = true
                FinishProtected()
                -- the lock is on by the next frame
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function() lockPending = false end)
                end
            else
                lockPending = false
                SettleOwed()
            end
        end)
    end
end

-- shared with later ZacUI files
ns.Animate = Animate
ns.PopIn = PopIn
ns.PopOut = PopOut
ns.StopAnim = Stop
ns.Motion = Motion
ns.EASE = EASE
