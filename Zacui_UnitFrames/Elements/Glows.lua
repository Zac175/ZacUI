-- ============================================================================
-- Zacui_UnitFrames - Glows.lua
-- The glows round a unit frame, one family for both alerts:
--
--   DISPEL GLOW   a frame whose unit has a debuff YOU can remove right now
--                 (your class's spells, the Felhunter's Devour Magic while it
--                 is out) glows in the debuff's colour - Magic blue, Curse
--                 purple, Poison green, Disease brown - or one colour of your
--                 own. Out of range (with "only in range", on by default) it
--                 is NOT shown: the frame's own range fade already says "too
--                 far", and a glow you cannot act on is noise.
--                 Settings: ns.db.dispelGlow.
--   AOE TAUNT     the same glow, brighter, plus a countdown, for the six
--                 seconds of a Challenging Shout / Roar (ShoutAlert.lua,
--                 settings ns.db.shoutAlert). While it shows, the taunt WINS:
--                 the dispel glow on that frame steps aside and comes back
--                 when the taunt ends.
--
-- Both default to the warrior HUD's buff-bar glow (a soft light just
-- outside the edge, breathing in and out), and each has its own full set of
-- look settings - style, strength, reach, wide halo, pulse speed and depth,
-- pixel-line count / length / speed, offset (see "The drawing" below).
-- Built lazily: a frame that never glows never pays for it.
--
-- Cost: nothing per UNIT_AURA. The aura walk the frames already run (one
-- per dirty frame, coalesced: Elements.lua ns.AuraDirty) hands over the type
-- it found; that is compared with what the frame shows and nothing else
-- happens when it is the same. The range check is one small OnUpdate that
-- only runs while some frame has a cleansable debuff, every 0.3 s, over
-- just those frames.
--
-- Part of ZacUI. Loaded after Elements.lua (TOC).
-- ============================================================================
local ADDON, ns = ...

local G = {}
ns.Glow = G

local WHITE = "Interface\\Buttons\\WHITE8X8"
local RANGE_EVERY = 0.3

local function Motion() local Z = _G.ZacUI return Z and Z.Motion end
local isSecret = issecretvalue
local function secret(v) return isSecret ~= nil and isSecret(v) and true or false end

-- ----------------------------------------------------------------------------
-- The drawing: ns.Glow, one helper for every glow on a unit frame
-- ----------------------------------------------------------------------------
--   g = G.New(frame, level, key)     a host over `frame`, `level` frame levels
--                                    up; `key` is the click-to-pick element
--   G.Configure(g, spec, r, gg, b, a) style and look (spec: below), colour
--   G.Start(g [, motionSpec])         show + pulse; G.Stop(g) hide
--
-- spec (a glow's settings table; every field optional, G.DEFAULTS fills in):
--   style      "edge"     soft light just outside the edge - the warrior
--                         HUD's buff-bar glow (HUD_Warrior_Widgets
--                         CreateBorderGlow), the same Zacui\Media\EdgeGlow /
--                         EdgeGlowWide art. The HUD draws one texture at
--                         twice the icon so its 128 px hole lands on the
--                         edge; a unit frame is not square, so here the same
--                         texture is cut into nine (corners, edges, the hole
--                         left out) round the frame. On a square frame with
--                         size = half its width it is the HUD's glow exactly.
--              "pixel"    lines running round the edge
--              "autocast" little sparkles running round the edge
--              "solid"    a plain border
--              "tint"     a wash over the whole frame (the shout alert's
--                         old look)
--   alpha      strength 0..1 (times the colour's own alpha)
--   size       how far the edge glow / sparkles reach, px
--   thickness  the pixel lines' and the solid border's thickness, px
--   wide       the wide soft halo (EdgeGlowWide) under the edge glow
--   pulse, pulseSpeed (s per beat, eased in and out), pulseDepth (0..0.9:
--              how far the alpha dips) - like the HUD's breathing
--   lines, length, speed   pixel lines / sparkles: count, length px, laps/s
--   offset     px out from the frame's edge (negative = inward)
local GLOW_TEX  = "Interface\\AddOns\\Zacui\\Media\\EdgeGlow"
local GLOW_WIDE = "Interface\\AddOns\\Zacui\\Media\\EdgeGlowWide"
local WASH_TEX  = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local STAR_TEX  = "Interface\\Cooldown\\star4"
local EDGE_ALPHA, WIDE_ALPHA = 0.65, 0.6    -- the HUD's own strengths

G.STYLES = {
    { value = "edge",     text = "Edge glow" },
    { value = "pixel",    text = "Pixel lines" },
    { value = "autocast", text = "Autocast sparkles" },
    { value = "solid",    text = "Solid border" },
    { value = "tint",     text = "Tint only" },
}
local STYLE_OK = { edge = true, pixel = true, autocast = true, solid = true, tint = true }
G.DEFAULTS = { style = "edge", alpha = 1, size = 8, thickness = 2, wide = false,
    pulse = true, pulseSpeed = 0.6, pulseDepth = 0.55, lines = 8, length = 8, speed = 0.25, offset = 0 }

local function num(v, def, lo, hi)
    v = tonumber(v) or def
    if v < lo then v = lo elseif v > hi then v = hi end
    return v
end
-- a spec with every field read and clamped (into `out`, reused per glow)
local function resolve(spec, out)
    spec = type(spec) == "table" and spec or {}
    local D = G.DEFAULTS
    out.style = STYLE_OK[spec.style] and spec.style or D.style
    out.alpha = num(spec.alpha, D.alpha, 0.05, 1)
    out.size = num(spec.size, D.size, 1, 40)
    out.thickness = math.floor(num(spec.thickness, D.thickness, 1, 8) + 0.5)
    out.wide = spec.wide == nil and D.wide or (spec.wide and true or false)
    out.pulse = spec.pulse == nil and D.pulse or (spec.pulse and true or false)
    out.pulseSpeed = num(spec.pulseSpeed, D.pulseSpeed, 0.1, 3)
    out.pulseDepth = num(spec.pulseDepth, D.pulseDepth, 0, 0.9)
    out.lines = math.floor(num(spec.lines, D.lines, 1, 24) + 0.5)
    out.length = num(spec.length, D.length, 1, 60)
    out.speed = num(spec.speed, D.speed, 0.02, 2)
    out.offset = num(spec.offset, D.offset, -10, 20)
    return out
end
G.Resolve = function(spec) return resolve(spec, {}) end

function G.New(frame, level, key)
    local host = CreateFrame("Frame", nil, frame)
    host:SetAllPoints(frame)
    host:SetFrameLevel((frame:GetFrameLevel() or 1) + level)
    host:Hide()
    host._zElement = key
    local pulser = CreateFrame("Frame", nil, host)
    pulser:SetAllPoints(host)
    host.pulser = pulser
    host.parts = {}
    host.spec = {}
    -- the breathing: a client animation (no Lua per frame), eased both ways
    local ag = pulser:CreateAnimationGroup()
    if ag then
        ag:SetLooping("BOUNCE")
        local an = ag:CreateAnimation("Alpha")
        if an then
            if an.SetSmoothing then an:SetSmoothing("IN_OUT") end
            host.beat = an
        end
        host.anim = ag
    end
    host:SetScript("OnShow", function(self) G.Repulse(self) end)
    host:SetScript("OnHide", function(self)
        if self.anim then self.anim:Stop() end
        self._pulsing = nil
    end)
    return host
end

local function texList(g, kind, n, path, blend, layer, sub)
    local list = g.parts[kind]
    if not list then list = {} g.parts[kind] = list end
    for i = #list + 1, n do
        local t = g.pulser:CreateTexture(nil, layer or "ARTWORK", nil, sub)
        t:SetTexture(path)
        if blend then t:SetBlendMode(blend) end
        list[i] = t
    end
    return list
end

-- the nine-slice of the edge art, minus its middle: TL T TR L R BL B BR,
-- texture coordinates round the 0.25..0.75 hole
local SLICE = {
    { 0, 0.25, 0, 0.25 }, { 0.25, 0.75, 0, 0.25 }, { 0.75, 1, 0, 0.25 },
    { 0, 0.25, 0.25, 0.75 }, { 0.75, 1, 0.25, 0.75 },
    { 0, 0.25, 0.75, 1 }, { 0.25, 0.75, 0.75, 1 }, { 0.75, 1, 0.75, 1 },
}
local function layEdge(g, list, R, o)
    for i = 1, 8 do
        local t = list[i]
        t:ClearAllPoints()
        local c = SLICE[i]
        t:SetTexCoord(c[1], c[2], c[3], c[4])
    end
    local tl, tt, tr, l, r, bl, bb, br = list[1], list[2], list[3], list[4], list[5], list[6], list[7], list[8]
    tl:SetPoint("BOTTOMRIGHT", g, "TOPLEFT", -o, o)        tl:SetSize(R, R)
    tt:SetPoint("BOTTOMLEFT", g, "TOPLEFT", -o, o)
    tt:SetPoint("BOTTOMRIGHT", g, "TOPRIGHT", o, o)        tt:SetHeight(R)
    tr:SetPoint("BOTTOMLEFT", g, "TOPRIGHT", o, o)         tr:SetSize(R, R)
    l:SetPoint("TOPRIGHT", g, "TOPLEFT", -o, o)
    l:SetPoint("BOTTOMRIGHT", g, "BOTTOMLEFT", -o, -o)     l:SetWidth(R)
    r:SetPoint("TOPLEFT", g, "TOPRIGHT", o, o)
    r:SetPoint("BOTTOMLEFT", g, "BOTTOMRIGHT", o, -o)      r:SetWidth(R)
    bl:SetPoint("TOPRIGHT", g, "BOTTOMLEFT", -o, -o)       bl:SetSize(R, R)
    bb:SetPoint("TOPLEFT", g, "BOTTOMLEFT", -o, -o)
    bb:SetPoint("TOPRIGHT", g, "BOTTOMRIGHT", o, -o)       bb:SetHeight(R)
    br:SetPoint("TOPLEFT", g, "BOTTOMRIGHT", o, -o)        br:SetSize(R, R)
end

-- four strips just inside the (offset) edge
local function laySolid(g, list, th, o)
    local top, bottom, left, right = list[1], list[2], list[3], list[4]
    for i = 1, 4 do list[i]:ClearAllPoints() end
    top:SetPoint("TOPLEFT", g, "TOPLEFT", -o, o)
    top:SetPoint("TOPRIGHT", g, "TOPRIGHT", o, o)
    top:SetHeight(th)
    bottom:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", -o, -o)
    bottom:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", o, -o)
    bottom:SetHeight(th)
    left:SetPoint("TOPLEFT", g, "TOPLEFT", -o, o - th)
    left:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", -o, -o + th)
    left:SetWidth(th)
    right:SetPoint("TOPRIGHT", g, "TOPRIGHT", o, o - th)
    right:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", o, -o + th)
    right:SetWidth(th)
end

local function hideAll(g)
    for _, list in pairs(g.parts) do
        for i = 1, #list do list[i]:Hide() end
    end
end

-- the moving styles (pixel, autocast): one driver over the glows on screen
local moving = {}
local mover = CreateFrame("Frame")
mover:Hide()

local function perimeterPoint(w, h, pos)
    if pos < w then return pos, 0
    elseif pos < w + h then return w, -(pos - w)
    elseif pos < 2 * w + h then return w - (pos - w - h), -h end
    return 0, -(h - (pos - 2 * w - h))
end

local function stepPixel(g, now)
    local sp = g.spec
    local o = sp.offset
    local w, h = (g:GetWidth() or 0) + 2 * o, (g:GetHeight() or 0) + 2 * o
    local per = 2 * (w + h)
    if per <= 0 then return end
    local list, n, th = g.parts.pixel, sp.lines, sp.thickness
    local len = math.min(sp.length, per / n)
    local phase = (now * sp.speed) % 1
    for i = 1, n do
        local t = list[i]
        local pos = ((i - 1) / n + phase) % 1 * per
        t:ClearAllPoints()
        if pos < w then
            t:SetPoint("TOPLEFT", g, "TOPLEFT", pos - o, o)
            t:SetSize(math.max(1, math.min(len, w - pos)), th)
        elseif pos < w + h then
            t:SetPoint("TOPRIGHT", g, "TOPRIGHT", o, -(pos - w) + o)
            t:SetSize(th, math.max(1, math.min(len, w + h - pos)))
        elseif pos < 2 * w + h then
            t:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -(pos - w - h) + o, -o)
            t:SetSize(math.max(1, math.min(len, 2 * w + h - pos)), th)
        else
            t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", -o, pos - 2 * w - h - o)
            t:SetSize(th, math.max(1, math.min(len, per - pos)))
        end
    end
end

local function stepSparkle(g, now)
    local sp = g.spec
    local o = sp.offset
    local w, h = (g:GetWidth() or 0) + 2 * o, (g:GetHeight() or 0) + 2 * o
    local per = 2 * (w + h)
    if per <= 0 then return end
    local list, n = g.parts.autocast, sp.lines
    local phase = (now * sp.speed) % 1
    local s = math.max(2, sp.size)
    for i = 1, n do
        local t = list[i]
        local x, y = perimeterPoint(w, h, ((i - 1) / n + phase) % 1 * per)
        t:ClearAllPoints()
        t:SetPoint("CENTER", g, "TOPLEFT", x - o, y + o)
        t:SetSize(s, s)
    end
end

mover:SetScript("OnUpdate", function(self)
    local now = GetTime()
    local any = false
    for g in pairs(moving) do
        any = true
        if g:IsVisible() then
            if g.spec.style == "pixel" then stepPixel(g, now) else stepSparkle(g, now) end
        end
    end
    if not any then self:Hide() end
end)
G._moving = moving   -- (tests)

-- Style, look and colour onto a glow. Called when the colour or a
-- setting changes, never per aura event.
function G.Configure(g, spec, r, gg, b, a)
    local sp = resolve(spec, g.spec)
    local A = (a or 1) * sp.alpha
    hideAll(g)
    local st = sp.style
    if st == "edge" then
        local edge = texList(g, "edge", 8, GLOW_TEX, "ADD", "OVERLAY", 2)
        layEdge(g, edge, sp.size, sp.offset)
        for i = 1, 8 do edge[i]:SetVertexColor(r, gg, b, A * EDGE_ALPHA) edge[i]:Show() end
        if sp.wide then
            local soft = texList(g, "wide", 8, GLOW_WIDE, "ADD", "OVERLAY", 1)
            layEdge(g, soft, sp.size, sp.offset)
            for i = 1, 8 do soft[i]:SetVertexColor(r, gg, b, A * WIDE_ALPHA) soft[i]:Show() end
        end
    elseif st == "solid" then
        local list = texList(g, "solid", 4, WHITE, nil, "OVERLAY")
        laySolid(g, list, sp.thickness, sp.offset)
        for i = 1, 4 do list[i]:SetVertexColor(r, gg, b, A) list[i]:Show() end
    elseif st == "tint" then
        local list = texList(g, "tint", 1, WASH_TEX, "ADD", "ARTWORK")
        local t = list[1]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", g, "TOPLEFT", -sp.offset, sp.offset)
        t:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", sp.offset, -sp.offset)
        t:SetVertexColor(r, gg, b, A)
        t:Show()
    elseif st == "pixel" then
        local list = texList(g, "pixel", sp.lines, WHITE, nil, "OVERLAY")
        for i = 1, sp.lines do list[i]:SetVertexColor(r, gg, b, A) list[i]:Show() end
        stepPixel(g, GetTime())
    else -- autocast
        local list = texList(g, "autocast", sp.lines, STAR_TEX, "ADD", "OVERLAY")
        for i = 1, sp.lines do list[i]:SetVertexColor(r, gg, b, A) list[i]:Show() end
        stepSparkle(g, GetTime())
    end
    if g.beat then
        local Mo = Motion()
        local speed = (Mo and Mo.Speed and Mo.Speed()) or 1
        g.beat:SetFromAlpha(1)
        g.beat:SetToAlpha(1 - sp.pulseDepth)
        g.beat:SetDuration(sp.pulseSpeed / speed)
    end
    if g:IsShown() then G.Repulse(g) end
    if (st == "pixel" or st == "autocast") and g:IsShown() then
        moving[g] = true
        mover:Show()
    else
        moving[g] = nil
    end
end

-- (re)start the breathing for the current settings: the client
-- animation, or a ZacUI motion spec when the owner gave one (the shout
-- alert's "How it throbs", for its Tint only style). Motion off
-- (Appearance > Motion) = steady.
function G.Repulse(g)
    local Mo = Motion()
    if g.anim then g.anim:Stop() end
    if Mo then Mo.Stop(g.pulser) end
    g._pulsing = nil
    g.pulser:SetAlpha(1)
    if not g:IsShown() then return end
    local ms = g.motionSpec
    if ms then
        if Mo and type(ms) == "table" and ms.style and ms.style ~= "none" then
            Mo.Play(g.pulser, ms, "update")
            g._pulsing = "motion"
        end
        return
    end
    local enabled = not (Mo and Mo.Enabled and not Mo.Enabled())
    if g.spec.pulse and g.spec.pulseDepth > 0 and enabled and g.anim then
        g.anim:Play()
        g._pulsing = "beat"
    end
end

function G.Start(g, motionSpec)
    g.motionSpec = motionSpec
    g:Show()
    G.Repulse(g)
    local st = g.spec.style
    if st == "pixel" or st == "autocast" then
        moving[g] = true
        mover:Show()
    end
end

function G.Stop(g)
    moving[g] = nil
    if g.anim then g.anim:Stop() end
    local Mo = Motion()
    if Mo then Mo.Stop(g.pulser) end
    g._pulsing = nil
    g:Hide()
end

-- ----------------------------------------------------------------------------
-- The dispel glow
-- ----------------------------------------------------------------------------
local function dcfg() return ns.db and ns.db.dispelGlow end

local function dispelColor(dtype)
    local d = dcfg()
    if d and d.byType == false then
        local c = d.color
        if type(c) == "table" then return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 end
        return 1, 1, 1, 1
    end
    local c = ns.DISPEL_COLORS and ns.DISPEL_COLORS[dtype]
    if c then return c[1], c[2], c[3], 1 end
    return 1, 1, 1, 1
end

local function tauntShown(frame)
    local s = rawget(frame, "ShoutGlow")
    return s ~= nil and s:IsShown()
end

-- Show or hide one frame's dispel glow from what is known about it: the
-- type found, whether it is in range, whether a taunt glow owns the frame.
local function decide(frame)
    local g = rawget(frame, "DispelGlow")
    local dtype = frame.dispelGlowType
    if dtype ~= nil and frame._dgInRange ~= false and not tauntShown(frame) then
        if not g then
            g = G.New(frame, 9, "dispelGlow")
            frame.DispelGlow = g
        end
        if g._ptype ~= dtype then
            g._ptype = dtype
            G.Configure(g, dcfg(), dispelColor(dtype))
        end
        if not g:IsShown() then G.Start(g) end
    elseif g and g:IsShown() then
        G.Stop(g)
    end
end
ns.DispelGlowDecide = decide

-- In range to remove `dtype` from `unit`? The spell that removes it says,
-- when the game will tell; else the ~40 yd group check; else yes (a glow
-- that cannot be judged is shown). Forever: a secret answer counts as
-- "cannot judge".
function ns.DispelInRange(unit, dtype)
    if not unit then return true end
    if UnitIsUnit then
        local ok, me = pcall(UnitIsUnit, unit, "player")
        if ok and me == true then return true end
    end
    local name = ns.DispelRangeSpell and ns.DispelRangeSpell(dtype)
    if name and IsSpellInRange then
        local ok, r = pcall(IsSpellInRange, name, unit)
        if ok and not secret(r) then
            if r == 1 or r == true then return true end
            if r == 0 or r == false then return false end
        end
    end
    if UnitInRange then
        local ok, r, checked = pcall(UnitInRange, unit)
        if ok and not secret(r) and not secret(checked) and checked then return r and true or false end
    end
    return true
end

-- frames with a cleansable debuff whose range is being watched
local candidates = {}
local ranger = CreateFrame("Frame")
ranger:Hide()
local rangeAcc = 0
ranger:SetScript("OnUpdate", function(self, e)
    rangeAcc = rangeAcc + (e or 0)
    if rangeAcc < RANGE_EVERY then return end
    rangeAcc = 0
    local d = dcfg()
    local watching = d and d.enabled and d.onlyInRange
    local any = false
    for f in pairs(candidates) do
        if not (watching and f.dispelGlowType and f.unit) then
            candidates[f] = nil
        else
            any = true
            if f:IsVisible() then
                local r = ns.DispelInRange(f.unit, f.dispelGlowType)
                if r ~= f._dgInRange then
                    f._dgInRange = r
                    decide(f)
                end
            end
        end
    end
    if not any then self:Hide() end
end)
G._candidates, G._ranger = candidates, ranger   -- (tests)

-- The aura walk's answer for one frame: the cleansable type it found (nil
-- = none). `preview`: a settings sample or a move-mode mock - never range
-- gated. The same answer as last time touches nothing (decide finds the
-- glow already painted and shown).
function ns.DispelGlowSet(frame, dtype, preview)
    local d = dcfg()
    if not (d and d.enabled) then dtype = nil end
    local had = frame.dispelGlowType
    if dtype == nil then
        if had == nil then return end
        frame.dispelGlowType, frame._dgInRange = nil, nil
        candidates[frame] = nil
        decide(frame)
        return
    end
    frame.dispelGlowType = dtype
    if preview or not frame.unit or not d.onlyInRange then
        candidates[frame] = nil
        frame._dgInRange = nil
    else
        if dtype ~= had or frame._dgInRange == nil then
            frame._dgInRange = ns.DispelInRange(frame.unit, dtype)
        end
        if not candidates[frame] then
            candidates[frame] = true
            ranger:Show()
        end
    end
    decide(frame)
end

-- A restyle (any setting changed): a glow already built takes the new
-- colour, thickness and pulse. Frames that never glowed: nothing.
function ns.GlowRestyle(frame)
    local g = rawget(frame, "DispelGlow")
    if g then
        local d = dcfg()
        if not (d and d.enabled) then
            ns.DispelGlowSet(frame, nil)
        else
            g._ptype = nil      -- repainted (style, look, colour) by decide
            decide(frame)
        end
    end
    if rawget(frame, "ShoutGlow") and ns.ShoutGlowRestyle then ns.ShoutGlowRestyle(frame) end
end

-- ----------------------------------------------------------------------------
-- What works where (Era / TBC / Forever). Read by ZacUI's "Game versions"
-- table; plain English, one entry per feature.
-- ----------------------------------------------------------------------------
ns.UF_FLAVOR_NOTES = {
    dispelGlow = {
        era = "Works. Glows for what your spells remove: priest Magic and Disease, paladin Poison and Disease with Purify (Magic too once Cleanse is learned), druid Curse and Poison, mage Curse, shaman Poison and Disease, warlock Magic while the Felhunter is out.",
        tbc = "Works the same: the same spell IDs, plus Mass Dispel and the Felhunter's higher Devour Magic ranks when known; the shaman's Poison and Disease Cleansing Totems count.",
        forever = "Works out of combat. In combat the game hides other players' aura details from addons; the frames read those as no aura, so the glow goes quiet until combat ends. No errors.",
        why = "It reads auras and known spells (IsPlayerSpell / IsSpellKnown), which every version has; only Forever's secret aura values in combat stop it.",
    },
    dispelRange = {
        era = "Works: the removing spell's own range (IsSpellInRange), else the ~40 yd group check.",
        tbc = "Works the same.",
        forever = "Works where the game answers; a secret answer counts as in range (the glow shows).",
        why = "Out of range the glow is hidden; the frame's range fade already dims it.",
    },
    tauntGlow = {
        era = "Works: seen in the combat log (Challenging Shout and Challenging Roar, by spell ID or by name).",
        tbc = "Works the same: the same spells and IDs in the combat log.",
        forever = "No combat log for addons: seen through UNIT_SPELLCAST_SUCCEEDED on you and your group, when the game lets addons read the spell ID. When it is hidden (secret) nothing happens - no glow, no errors.",
        why = "Forever gives addons no combat log, so the cast event on group units is the only other signal.",
    },
    tauntCountdown = {
        era = "Works.", tbc = "Works.",
        forever = "Works whenever the taunt glow does.",
        why = "It is the taunt glow's own six-second timer.",
    },
    tauntVoice = {
        era = "Works.", tbc = "Works.",
        forever = "Works whenever the taunt glow does (the game's text-to-speech).",
        why = "Same detection as the glow.",
    },
}
-- ZacUI's own namespace can read them too (this part's ns is private)
do
    local Zg = _G.ZacUI
    if type(Zg) == "table" then
        Zg.FlavorNotes = Zg.FlavorNotes or {}
        Zg.FlavorNotes.unitframes = ns.UF_FLAVOR_NOTES
    end
end
