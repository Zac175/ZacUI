-- NP_FX - the plates' animations: the fade and the size change as the
-- target moves between plates, a plate's entrance, and the target marks'
-- entrance. Part of ZacUI; load order is set by the TOC.
--
-- WHY A DRIVER OF ITS OWN FOR ALPHA AND SCALE. ns.Motion plays a style
-- from a frame's rest and puts the rest back at the end; a plate's fade
-- and size cue are not a show/hide but a move from one resting value to
-- another (0.75 -> 1 as it becomes the target, 1 -> 1.15 as it grows),
-- and a pull can ask that of forty plates in one frame. So the plates
-- glide on ONE OnUpdate shared by every plate, shown only while something
-- is still moving - the pattern the smooth health fill already uses -
-- with the timing, easing and delay from the saved animation spec and the
-- global switches from Appearance > Motion (off = instant, speed divides
-- every duration). The target marks are one frame on one plate at a
-- time, so they play through ns.Motion itself.
--
-- Every animation is "none" by default: the plates change exactly as
-- they always did until a style is picked on Nameplates > Animation.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local NP = ns.Nameplates
if not NP then return end

local FX = {}
NP.FX = FX

local function Spec(key)
    local a = NP.DB().anim
    return a and a[key]
end
FX.Spec = Spec

-- the length (and delay) a spec plays for right now, or nil for "at once":
-- style none, Motion switched off, or no Motion at all
local function Timing(spec)
    if type(spec) ~= "table" or not spec.style or spec.style == "none" then return nil end
    local M = ns.Motion
    if not M then return nil end
    if M.Enabled and not M.Enabled() then return nil end
    local speed = (M.Speed and M.Speed()) or 1
    local dur = (tonumber(spec.duration) or 0.2) / speed
    if dur <= 0 then return nil end
    return dur, math.max(0, tonumber(spec.delay) or 0) / speed
end
FX.Timing = Timing

local function Ease(name)
    local E = ns.Motion and ns.Motion.EASE
    return (E and (E[name or ""] or E.easeOutQuad)) or function(t) return t end
end

-- ============================================================
-- THE GLIDE
-- ============================================================
-- moving[frame] = { alpha = channel, scale = channel }; a channel is
-- { on, from, to, start, dur, ease } and is reused, never rebuilt.
local moving = {}
local driver = CreateFrame("Frame")
driver:Hide()
FX._driver = driver          -- (for the tests: shown only while something glides)

local function Put(f, key, v)
    if key == "alpha" then
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        f:SetAlpha(v)
    else
        if v < 0.01 then v = 0.01 end
        f:SetScale(v)
    end
end

driver:SetScript("OnUpdate", function(self)
    local now = GetTime()
    local any = false
    for f, rec in pairs(moving) do
        local live = false
        for key, ch in pairs(rec) do
            if ch.on then
                local t = (now - ch.start) / ch.dur
                if t >= 1 or not f:IsVisible() then
                    ch.on = false
                    Put(f, key, ch.to)
                elseif t > 0 then
                    Put(f, key, ch.from + (ch.to - ch.from) * ch.ease(t))
                    live = true
                else
                    live = true          -- still in its delay
                end
            end
        end
        if live then any = true else moving[f] = nil end
    end
    if not any then self:Hide() end
end)

local function Channel(f, key)
    local rec = moving[f]
    return rec and rec[key]
end

local function Start(f, key, from, to, dur, delay, easing)
    local rec = moving[f]
    if not rec then rec = {} moving[f] = rec end
    local ch = rec[key]
    if not ch then ch = {} rec[key] = ch end
    ch.on, ch.from, ch.to = true, from, to
    ch.start, ch.dur, ch.ease = GetTime() + (delay or 0), dur, Ease(easing)
    Put(f, key, from)
    driver:Show()
end

local function Set(f, key, v, instant, specKey, get)
    local ch = Channel(f, key)
    if ch and ch.on then
        if ch.to == v and not instant then return end     -- already heading there
        ch.on = false
    end
    if not instant and f:IsVisible() then
        local spec = Spec(specKey)
        local dur, delay = Timing(spec)
        local cur = get(f) or 1
        if dur and math.abs(cur - v) > 0.001 then
            Start(f, key, cur, v, dur, delay, spec.easing)
            return
        end
    end
    Put(f, key, v)
end

local function GetA(f) return f:GetAlpha() end
local function GetS(f) return f:GetScale() end

-- the plate's opacity (the non-target fade): glides on Animation >
-- "Fading between plates", else set at once
function FX.Alpha(f, a, instant) Set(f, "alpha", a, instant, "fade", GetA) end
-- the plate's size (the target / priority size cue)
function FX.Scale(f, s, instant)
    local ch = Channel(f, "scale")
    if not (ch and ch.on) and f:GetScale() == s then return end
    Set(f, "scale", s, instant, "scale", GetS)
end

-- where a gliding plate is heading (or where it is, standing still)
function FX.Target(f, key)
    local ch = Channel(f, key)
    if ch and ch.on then return ch.to end
    if key == "alpha" then return f:GetAlpha() end
    return f:GetScale()
end

function FX.IsMoving(f) return moving[f] ~= nil end

-- A new plate's entrance: from nothing (fade), or nothing and small
-- (pop), to the alpha and scale the target pass just gave it.
function FX.Appear(f)
    local spec = Spec("appear")
    local dur, delay = Timing(spec)
    if not dur or not f:IsVisible() then return end
    local a = FX.Target(f, "alpha")
    Start(f, "alpha", 0, a, dur, delay, spec.easing)
    if spec.style == "pop" then
        local s = FX.Target(f, "scale")
        Start(f, "scale", s * 0.6, s, dur, delay, spec.easing)
    end
end

-- a plate going back to the pool: nothing of it keeps moving
function FX.Forget(f)
    moving[f] = nil
    f._fxTgt = nil
    if f.tgtCue and ns.Motion and f.tgtCue._zMotion then ns.Motion.Stop(f.tgtCue) end
end

-- ============================================================
-- THE TARGET MARKS' ENTRANCE
-- ============================================================
-- The neon, the box / arrows round the bar all ride f.tgtCue (NP_Health
-- makes it, one anchor on the bar's centre, the bar's size), so a style
-- played on it moves them together. Played when a plate becomes the
-- target; losing it puts the marks straight back at rest.
function FX.TargetMarks(f, on, instant)
    local was = f._fxTgt
    f._fxTgt = on
    local cue = f.tgtCue
    local M = ns.Motion
    if not (cue and M) then return end
    if on and not was and not instant then
        local spec = Spec("target")
        if spec and spec.style and spec.style ~= "none" and f:IsVisible() then
            M.Play(cue, spec, "in")
        end
    elseif not on and was and cue._zMotion then
        M.Stop(cue)
    end
end

-- Before anything re-lays out a plate's marks (a settings change, the
-- combat size swap): the marks must be at rest when they are moved.
function FX.Settle(f)
    local cue = f.tgtCue
    if cue and cue._zMotion and ns.Motion then ns.Motion.Stop(cue) end
end
