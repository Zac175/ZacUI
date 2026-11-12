-- HUD_Warrior_Widgets - rendering primitives for the Warrior HUD: WA-style
-- icon regions, glows, status bars and dynamic row layouts (customGrow
-- port). Colours/sizes are DATA lifted verbatim from the decoded
-- WeakAura; fonts go through HUD.ApplyFont.
-- Part of ZacUI; load order is set by the TOC.
local ADDON_NAME = ...
-- Zacui_HUD is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
if not ns.HUD then return end   -- (the part stands down on this game version: HUD_Shared, Core_Flavor)
local HUD = ns.HUD
local UI = ns.UI
local Print = ns.Print

local WH = ns.WarriorHUD
WH.Widgets = WH.Widgets or {}
local W = WH.Widgets

local WHITE_TEX = "Interface\\Buttons\\WHITE8X8"
local BAR_TEX = ns.TEX_NORM                                   -- Melli stand-in
local SPARK_TEX = "Interface\\CastingBar\\UI-CastingBar-Spark"

-- ============================================================
-- POLISH AND MOTION (every class HUD and the Drink Ticker draw with
-- these widgets, so they all get it). One switch, on by default:
-- ZacUIDB.hud.smooth = false puts back the plain look and the snapping.
--   * icons slide to their new place when one joins or leaves a row,
--     and fade in when they appear (HUD > Animation: "When a row moves
--     along", "When an icon appears", "When an icon goes")
--   * a soft flash when a cooldown comes back ("Ready flash")
--   * a light sheen on icons and bar fills, a glowing leading edge on
--     bars, greyed-out icons sit a little darker (HUD > Look)
--   * the glow pulse eases in and out instead of blinking
-- The animations play through ns.Motion, so ZacUI's own Play animations
-- switch and speed apply too. Colours, borders, the bar texture, the
-- crop and the strengths come from the shared look (HUD.Look).
-- ============================================================
local function Smooth() return HUD.Smooth() end
local function Look() return HUD.Look() end
local function MotionCfg() return HUD.Motion() end
local function Mo() return ns.Motion end

-- a vertical white fade (top -> bottom alpha), on any client
local function Sheen(tex, topA, botA)
    tex:SetTexture(WHITE_TEX)
    tex:SetBlendMode("ADD")
    if tex.SetGradient and CreateColor then
        if pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(1, 1, 1, botA), CreateColor(1, 1, 1, topA)) then
            return
        end
    end
    if tex.SetGradientAlpha then
        pcall(tex.SetGradientAlpha, tex, "VERTICAL", 1, 1, 1, botA, 1, 1, 1, topA)
        return
    end
    tex:SetVertexColor(1, 1, 1, (topA + botA) / 2)
end

-- Tweened placement. Frames glide from where they are to their target
-- CENTER offset from the anchor over the "When a row moves along" time,
-- on its easing; one driver runs only while something is still moving.
-- A new target mid-glide starts a fresh glide from wherever the frame is.
local moving = {}
local glide = CreateFrame("Frame")
glide:Hide()

local function GlideSpec()
    local M = Mo()
    local spec = MotionCfg().glide
    if not (M and Smooth() and M.Enabled()) then return nil end
    local s = M.Normalize(spec)
    if s.style == "none" then return nil end
    local speed = M.Speed()
    local dur = s.duration / speed
    if dur <= 0 then return nil end
    return dur, s.delay / speed, (M.EASE and M.EASE[s.easing]) or function(t) return t end
end

glide:SetScript("OnUpdate", function(self)
    local now = GetTime()
    local any = false
    for f in pairs(moving) do
        if not f:IsShown() then
            moving[f] = nil
        else
            local t = (now - f._zG0 - (f._zGDelay or 0)) / (f._zGDur or 0.3)
            local cx, cy
            if t >= 1 then
                cx, cy = f._zTX, f._zTY
                moving[f] = nil
            else
                if t < 0 then t = 0 end
                local e = (f._zGEase or function(v) return v end)(t)
                cx = f._zFX + (f._zTX - f._zFX) * e
                cy = f._zFY + (f._zTY - f._zFY) * e
                any = true
            end
            f._zCX, f._zCY = cx, cy
            f:ClearAllPoints()
            local k2 = f._popCur or 1
            f:SetPoint("CENTER", f._zAnchor, "CENTER", cx / k2, cy / k2)
        end
    end
    if not any and not next(moving) then self:Hide() end
end)
W.glideDriver = glide

-- The entrance ("When an icon appears"), played on the icon itself.
local function Appear(f)
    local M = Mo()
    if not (M and Smooth()) then return end
    if f._zLeaving then f._zLeaving = nil end
    M.Play(f, MotionCfg().appear, "in")
end

local function NoteShown(f)
    f._zShownAt = GetTime()
end

-- Puts f's CENTER at (x, y) from anchor's CENTER: snaps the first time,
-- after an anchor change or right after the frame was shown (and plays
-- its entrance); otherwise glides there.
function W.Place(f, anchor, x, y)
    if not f._zHooked and f.HookScript then
        f._zHooked = true
        f:HookScript("OnShow", NoteShown)
    end
    local fresh = f._zShownAt and (GetTime() - f._zShownAt) < 0.5
    if fresh then f._zShownAt = nil end
    local moved = f._zAnchor ~= anchor or f._zTX ~= x or f._zTY ~= y
    -- an entrance or exit in flight owns the anchors until it ends: stop
    -- it (the frame back at rest) before it is moved
    local M = Mo()
    if moved and M and M.IsPlaying(f) and not fresh then M.Stop(f) end
    local dur, delay, ease = GlideSpec()
    if not dur or fresh or f._zAnchor ~= anchor or f._zCX == nil or not f:IsShown() then
        moving[f] = nil
        f._zAnchor, f._zCX, f._zCY, f._zTX, f._zTY = anchor, x, y, x, y
        f:ClearAllPoints()
        local k2 = f._popCur or 1
        f:SetPoint("CENTER", anchor, "CENTER", x / k2, y / k2)
        if fresh then Appear(f) end
        return
    end
    if f._zTX == x and f._zTY == y and (moving[f] or (f._zCX == x and f._zCY == y)) then return end
    f._zTX, f._zTY = x, y
    if f._zCX ~= x or f._zCY ~= y then
        f._zFX, f._zFY = f._zCX, f._zCY
        f._zG0, f._zGDur, f._zGDelay, f._zGEase = GetTime(), dur, delay, ease
        moving[f] = true
        glide:Show()
    end
end

-- Grows (or shrinks back) an icon around its own centre: the scale
-- would also scale its offsets from the row's anchor, so they are
-- divided back out and the icon stays exactly where the row put it.
-- (2026-11-11, Zac: "i want the hud to be smoother as well ... less
-- jittery but still responsive and dont nuke my fps") THE SIZE IS EASED:
-- the button to press first, the NOOB and a dumped Heroic Strike used to
-- jump a size up and back in one frame, every time the call moved
-- between Bloodthirst and Whirlwind. f._pop is where it is going,
-- f._popCur where it is; one driver eases every icon on its way (about
-- nine tenths there in 0.1 s) and hides itself the frame the last one
-- arrives, so nothing runs while the icons sit still. An entrance or
-- exit playing on the icon owns its scale until it ends; a hidden icon,
-- and all of it with "Smooth motion and polish" off, is one step as before.
local POP_TAU = 0.045
local popping = {}
local popDriver = CreateFrame("Frame")
popDriver:Hide()

local function ApplyPop(f, s)
    f._popCur = s
    f:SetScale(s)
    if f._zAnchor and f._zCX then
        f:ClearAllPoints()
        f:SetPoint("CENTER", f._zAnchor, "CENTER", f._zCX / s, f._zCY / s)
    end
end

popDriver:SetScript("OnUpdate", function(self, elapsed)
    local k = 1 - math.exp(-(elapsed or 0) / POP_TAU)
    local M = Mo()
    for f in pairs(popping) do
        local target = f._pop or 1
        if not f:IsShown() then
            popping[f] = nil
            ApplyPop(f, target)
        elseif not (M and M.IsPlaying(f)) then
            local cur = f._popCur or 1
            cur = cur + (target - cur) * k
            if math.abs(target - cur) < 0.004 then
                cur = target
                popping[f] = nil
            end
            ApplyPop(f, cur)
        end
    end
    if not next(popping) then self:Hide() end
end)
W.popDriver = popDriver

function W.SetPop(f, scale)
    scale = scale or 1
    if (f._pop or 1) == scale then return end
    local M = Mo()
    if M and M.IsPlaying(f) then
        M.Stop(f)
        -- an icon on its way out is simply gone
        if f._zLeaving then f._zLeaving = nil f:Hide() end
    end
    f._pop = scale
    if Smooth() and f:IsShown() then
        popping[f] = true
        popDriver:Show()
    else
        popping[f] = nil
        ApplyPop(f, scale)
    end
end

-- A ROW HOLDS ITS SHAPE FOR A MOMENT (2026-11-11, the same ask). The rows
-- are centred, so every icon that comes or goes slides all the others
-- half a place - and some come and go all fight: a queued Heroic Strike
-- with every swing, Flurry, Enrage. An icon that leaves now keeps its
-- place for HOLD seconds (it is hidden at once: what the row SAYS is
-- never late); back inside that time, nothing moved at all. Only then
-- does the row close up. Anything ARRIVING lays the row out at once and
-- drops every held place with it, so a stance change is still one move.
--   active  the icons showing now, in row order
--   last    the list the row was last laid out with (RememberList's)
--   st      this row's { gone = {}, seen = {}, was = {}, out = {} }
-- Returns the list to lay out (active itself in the steady state: no
-- table is filled when nothing came or went) and whether a place is
-- being held.
local HOLD = 0.4
W.HOLD = HOLD
function W.HeldList(active, last, st, now)
    local n = last.n
    local na = #active
    if not n or not Smooth() then
        if st.any then st.any = false wipe(st.gone) end
        return active, false
    end
    if not st.any and n == na then
        local same = true
        for i = 1, n do if last[i] ~= active[i] then same = false break end end
        if same then return active, false end
    end
    local seen, was, out, gone = st.seen, st.was, st.out, st.gone
    wipe(seen) wipe(was) wipe(out)
    for i = 1, na do seen[active[i]] = true end
    for i = 1, n do was[last[i]] = true end
    local plain = false
    for i = 1, na do if not was[active[i]] then plain = true break end end
    local held = false
    if not plain then
        local j = 0
        for i = 1, n do
            local ic = last[i]
            if seen[ic] then
                j = j + 1
                -- (the same icons in another order: a plain layout)
                if active[j] ~= ic then plain = true break end
                out[#out + 1] = ic
                gone[ic] = nil
            else
                local t = gone[ic]
                if not t then t = now gone[ic] = t end
                if now - t < HOLD then
                    out[#out + 1] = ic
                    held = true
                else
                    gone[ic] = nil
                end
            end
        end
    end
    if plain then
        st.any = false
        wipe(gone)
        return active, false
    end
    st.any = held
    return out, held
end
function W.NewHold() return { gone = {}, seen = {}, was = {}, out = {} } end

-- Shows or hides an icon the way the HUD animates them: a hidden one
-- comes in through W.Place (which plays the entrance once the row puts
-- it somewhere); a shown one leaves with "When an icon goes". Called
-- from the 5 Hz refreshes with the same answer most of the time, so the
-- unchanged case returns straight away.
function W.SetShownAnimated(f, on)
    if on then
        if f._zLeaving then
            f._zLeaving = nil
            local M = Mo()
            if M then M.Stop(f) end
            f:Show()
        elseif not f:IsShown() then
            f:Show()
        end
        return
    end
    local M = Mo()
    if f._zLeaving then
        -- its exit was stopped from outside (a window closing stops every
        -- animation on it): finish the job
        if f:IsShown() and not (M and M.IsPlaying(f)) then
            f._zLeaving = nil
            f:Hide()
        end
        return
    end
    if not f:IsShown() then return end
    local spec = MotionCfg().disappear
    if M and Smooth() and spec and spec.style and spec.style ~= "none" then
        f._zLeaving = true
        moving[f] = nil
        M.Play(f, spec, "out", function() f._zLeaving = nil end)
        -- a play that could not start (Motion off) has already hidden it
        if not f:IsShown() then f._zLeaving = nil end
    else
        f:Hide()
    end
end

-- Time formatting (WA subtext "timed" format). threshold: show one
-- decimal below this remaining time (0 = never).
function W.FormatTime(remaining, threshold)
    if not remaining or remaining <= 0 then return "" end
    if threshold and threshold > 0 and remaining < threshold then
        return string.format("%.1f", remaining)
    end
    if remaining >= 60 then
        return string.format("%dm", math.ceil(remaining / 60))
    end
    return tostring(math.floor(remaining))            -- WA legacy floor
end

-- Icon texture zoom (WA "zoom"): crop zoom/2 per side; keepAspect crops
-- the larger axis to the frame's aspect (WA keepAspectRatio).
local function ApplyZoom(tex, w, h, zoom, keepAspect)
    -- ZacUI's look crop (ns.Look.CropIcon) when it crops at least as far
    -- as the HUD's own; else the HUD's own, as always (let go of first)
    local L = ns.Look
    local c = L and L.CropIcon and L.IconCrop and L.IconCrop("hud")
    if type(c) == "number" and c > 0 and c + 0.0001 >= (zoom or 0) / 2 then
        L.CropIcon(tex, w, h, { border = false, part = "hud", minCrop = (zoom or 0) / 2 })
        return
    end
    if L and L.ForgetIcon then L.ForgetIcon(tex) end
    local inset = (zoom or 0) / 2
    local l, r, t, b = inset, 1 - inset, inset, 1 - inset
    if keepAspect and w and h and w > 0 and h > 0 and w ~= h then
        local span = 1 - 2 * inset
        if w > h then
            local crop = span * (1 - h / w) / 2
            t, b = t + crop, b - crop
        else
            local crop = span * (1 - w / h) / 2
            l, r = l + crop, r - crop
        end
    end
    tex:SetTexCoord(l, r, t, b)
end

-- Glow: a soft light just OUTSIDE the icon's edge, in the glow's own
-- colour, nothing drawn over the icon's face. ZacUI's own art
-- (Media\EdgeGlow / EdgeGlowWide: pure white, a 128px-square hole in a
-- 256px texture, falling off outward), so a colour really is that colour
-- - the old proc-glow art (SpellActivationOverlay\IconAlert) was gold
-- underneath whatever it was tinted. Drawn at 2x the icon, the hole sits
-- exactly on the icon's edge at any size.
-- Colorable per use: white (proc), gold (melee / ready), peach (sapper),
-- red (alert, crusader double), cyan (Whirlwind mobs). opts: color,
-- freq (0.1 fast .. 0.3 slow; the pulse's half period), size (1 = the
-- usual reach; more adds the wide falloff, for the NOOB alarm), static
-- (a steady glow, no breathing).
-- (2026-10-21; both files are new - the game needs one full restart.)
local GLOW_TEX = "Interface\\AddOns\\Zacui\\Media\\EdgeGlow"
local GLOW_WIDE = "Interface\\AddOns\\Zacui\\Media\\EdgeGlowWide"
local GLOW_SPAN = 2       -- the texture is twice the hole it leaves for the icon
local GLOW_ALPHA = 0.65   -- the tight glow at full colour alpha
local WIDE_ALPHA = 0.6    -- the wide falloff at size 1.35
local function CreateBorderGlow(parent, opts)
    opts = opts or {}
    local g = CreateFrame("Frame", nil, parent)
    g:SetAllPoints(parent)
    g:SetFrameLevel(parent:GetFrameLevel() + 8)
    local c = opts.color or { 1, 1, 1, 1 }
    g.color = c
    local ca = c[4] or 1

    local function Layer(tex, sub, alpha)
        local t = g:CreateTexture(nil, "OVERLAY", nil, sub)
        t:SetTexture(tex)
        t:SetBlendMode("ADD")
        t:SetVertexColor(c[1], c[2], c[3], alpha)
        t:SetPoint("CENTER", g, "CENTER", 0, 0)
        return t
    end
    local k = tonumber(opts.size) or 1
    local edge = Layer(GLOW_TEX, 2, ca * GLOW_ALPHA)
    local soft
    if k > 1.001 then
        soft = Layer(GLOW_WIDE, 1, ca * math.min(1, WIDE_ALPHA * (k - 1) / 0.35))
    end
    g.edge, g.soft = edge, soft
    g.softA = math.min(1, WIDE_ALPHA * (k - 1) / 0.35)

    local function Fit()
        local w, h = parent:GetWidth() or 30, parent:GetHeight() or 30
        edge:SetSize(w * GLOW_SPAN, h * GLOW_SPAN)
        if soft then soft:SetSize(w * GLOW_SPAN, h * GLOW_SPAN) end
    end
    Fit()
    g:SetScript("OnSizeChanged", Fit)

    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(opts.freq and math.max(0.25, opts.freq * 3) or 0.6)
    if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
    g.anim = ag
    if opts.static then
        g:SetScript("OnShow", nil)
        g:SetScript("OnHide", nil)
        g:Hide()
        return g
    end
    g:SetScript("OnShow", function(self) self.anim:Play() end)
    g:SetScript("OnHide", function(self) self.anim:Stop() end)
    g:Hide()
    return g
end

-- the same glow for icons that are not the HUD's own (ZacLayout puts it
-- on Readycheck's reminder icons, so they match the HUD)
W.CreateBorderGlow = CreateBorderGlow

-- A glow in a new colour (the pages' glow colour settings).
function W.SetGlowColor(g, r, gg, b, a)
    if not g then return end
    a = a or 1
    g.color = { r, gg, b, a }
    if g.edge then g.edge:SetVertexColor(r, gg, b, a * GLOW_ALPHA) end
    if g.soft then g.soft:SetVertexColor(r, gg, b, a * (g.softA or WIDE_ALPHA)) end
end

-- every icon and bar made, so a look change restyles them all at once
W.allIcons = setmetatable({}, { __mode = "k" })
W.allBars = setmetatable({}, { __mode = "k" })
function W.ApplyLookAll()
    for f in pairs(W.allIcons) do f:ApplyLook() end
    for b in pairs(W.allBars) do if b.ApplyLook then b:ApplyLook() end end
end
W.ApplyPolishAll = W.ApplyLookAll

-- Icon region factory. opts: width, height, zoom, keepAspect,
-- inverse (reversed swipe), noCooldown (no swipe at all).
local IconProto = {}

-- How much of a spell icon's edge is cropped away, shared by every HUD
-- (warrior, the class HUDs, hesitation). The old 0.3 cut a third of
-- every icon and read as zoomed-in and busy at 26-30px; this trims just
-- the baked-in dark rim (6% a side) and keeps the art recognisable.
W.ICON_ZOOM = 0.12

function W.CreateIcon(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(opts.width or 30, opts.height or 30)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)
    f.icon = icon
    f.zoom = opts.zoom or 0
    -- the HUD crop (W.ICON_ZOOM) follows the "Icon crop" setting
    f.followZoom = opts.zoom ~= nil and math.abs(opts.zoom - W.ICON_ZOOM) < 0.001
    f.keepAspect = opts.keepAspect

    -- Background behind the icon (WA subbackground)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(WHITE_TEX)
    bg:SetVertexColor(0, 0, 0, 0.5)
    f.bg = bg

    -- Black square border (WA subborder); thickness via SetBorderSize.
    local border = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetTexture(WHITE_TEX)
        t:SetVertexColor(0, 0, 0, 1)
        border[i] = t
    end
    f.border = border

    if not opts.noCooldown then
        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetDrawEdge(false)
        cd:SetDrawBling(false)
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        cd:SetReverse(opts.inverse and true or false)
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.75) end
        cd:SetFrameLevel(f:GetFrameLevel() + 1)
        f.cd = cd
        f.cdStart, f.cdDuration = 0, 0
    end

    -- Text overlay: subtexts must render ABOVE the cooldown swipe - the
    -- Cooldown child frame draws over the parent's own regions, so
    -- fontstrings go on a higher overlay frame (as the WA does).
    local textOverlay = CreateFrame("Frame", nil, f)
    textOverlay:SetAllPoints(f)
    textOverlay:SetFrameLevel(f:GetFrameLevel() + 5)
    f.textOverlay = textOverlay

    -- a light sheen over the top of the icon
    local sheen = f:CreateTexture(nil, "ARTWORK", nil, 2)
    sheen:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    sheen:SetPoint("BOTTOMRIGHT", icon, "RIGHT", 0, 0)
    Sheen(sheen, 0.14, 0)
    f.sheen = sheen
    f._sheenA = 0.14

    -- the "ready" flash, above the swipe: a frame of its own so the
    -- "Ready flash" animation can play on it through ns.Motion (its
    -- alpha at rest is the flash colour's alpha; hidden between flashes)
    local flashF = CreateFrame("Frame", nil, textOverlay)
    flashF:SetAllPoints(icon)
    flashF:SetFrameLevel(textOverlay:GetFrameLevel())
    flashF:Hide()
    local flash = flashF:CreateTexture(nil, "BACKGROUND")
    flash:SetAllPoints(flashF)
    flash:SetTexture(WHITE_TEX)
    flash:SetBlendMode("ADD")
    f.flash = flash
    f.flashF = flashF

    f.texts = {}
    f.glows = {}
    f.curTexture = nil
    f.curDesat = false
    f.colR, f.colG, f.colB, f.colA = 1, 1, 1, 1

    -- Frames must not be given a Lua metatable; mix the methods in.
    for k, v in pairs(IconProto) do f[k] = v end
    f:ApplyLook()
    W.allIcons[f] = true
    -- remember when it was last shown, so the row that places it next
    -- plays its entrance (W.Place) - from its very first appearance on
    if f.HookScript then
        f._zHooked = true
        f:HookScript("OnShow", NoteShown)
    end
    return f
end

-- Reposition the 4 border strips just outside the icon rect (WA subborder).
local function PlaceBorder(self, px)
    if self.borderSize == px then return end
    self.borderSize = px
    local b = self.border
    for i = 1, 4 do
        b[i]:ClearAllPoints()
        b[i]:SetShown(px > 0)
    end
    if px <= 0 then return end
    b[1]:SetPoint("TOPLEFT", self, "TOPLEFT", -px, px)           -- top
    b[1]:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", px, 0)
    b[2]:SetPoint("TOPLEFT", self, "BOTTOMLEFT", -px, 0)         -- bottom
    b[2]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", px, -px)
    b[3]:SetPoint("TOPLEFT", self, "TOPLEFT", -px, px)           -- left
    b[3]:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", 0, -px)
    b[4]:SetPoint("TOPLEFT", self, "TOPRIGHT", 0, px)            -- right
    b[4]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", px, -px)
end

-- A HUD that sets its own thickness (the Warrior HUD's setting) keeps it;
-- every other icon follows the shared "Icon border thickness".
function IconProto:SetBorderSize(px)
    self._borderPx = px or 1
    PlaceBorder(self, self._borderPx)
end

function IconProto:SetIconTexture(tex)
    if tex ~= self.curTexture then
        self.curTexture = tex
        self.icon:SetTexture(tex)
    end
    -- called for every icon every 0.2 s: the crop only moves with the
    -- size or the zoom, so it is re-applied only then
    local w, h, z, k = self:GetWidth(), self:GetHeight(), self.zoom, self.keepAspect
    if w ~= self._zw or h ~= self._zh or z ~= self._zz or k ~= self._zk then
        self._zw, self._zh, self._zz, self._zk = w, h, z, k
        ApplyZoom(self.icon, w, h, z, k)
    end
end

-- the colour the caller asked for, a little darker while greyed out
local function PaintIcon(self)
    local m = 1
    if self.curDesat and Smooth() then
        m = 1 - math.max(0, math.min(1, tonumber(Look().desatDim) or 0.28))
    end
    self.icon:SetVertexColor(self.colR * m, self.colG * m, self.colB * m, self.colA)
end

function IconProto:SetDesat(desat)
    desat = desat and true or false
    if desat ~= self.curDesat then
        self.curDesat = desat
        self.icon:SetDesaturated(desat)
        PaintIcon(self)
    end
end

function IconProto:SetIconColor(r, g, b, a)
    r, g, b, a = r or 1, g or 1, b or 1, a or 1
    if r == self.colR and g == self.colG and b == self.colB and a == self.colA then return end
    self.colR, self.colG, self.colB, self.colA = r, g, b, a
    PaintIcon(self)
end

-- The shared look onto this icon: backing, border, swipe, crop, sheen,
-- flash colour and the greyed-out dimming. Called on build and whenever
-- the look or the polish switch changes (W.ApplyLookAll).
function IconProto:ApplyLook()
    local look = Look()
    local on = Smooth()
    local d = HUD.LOOK_DEFAULTS
    self.bg:SetVertexColor(HUD.Col(look.iconBg, d.iconBg))
    local br, bgc, bb, ba = HUD.Col(look.iconBorder, d.iconBorder)
    for i = 1, 4 do self.border[i]:SetVertexColor(br, bgc, bb, ba) end
    PlaceBorder(self, self._borderPx or tonumber(look.iconBorderSize) or 1)
    if self.cd and self.cd.SetSwipeColor then self.cd:SetSwipeColor(HUD.Col(look.swipe, d.swipe)) end
    if self.followZoom then
        local z = tonumber(look.zoom) or W.ICON_ZOOM
        if z ~= self.zoom then
            self.zoom = z
            if self.curTexture then self._zz = nil self:SetIconTexture(self.curTexture) end
        end
    end
    if self.sheen then
        local a = tonumber(look.iconSheen) or 0.14
        if a ~= self._sheenA then
            self._sheenA = a
            Sheen(self.sheen, a, 0)
        end
        self.sheen:SetShown(on and a > 0)
    end
    if self.flash then
        local r, g, b = HUD.Col(look.flash, d.flash)
        self.flash:SetVertexColor(r, g, b, 1)
    end
    PaintIcon(self)
end
IconProto.ApplyPolish = IconProto.ApplyLook

-- a short flash: the cooldown is back ("Ready flash"; force = a preview
-- replay, which plays it on a sample that is not on screen-time yet)
function IconProto:Flash(force)
    local f = self.flashF
    local M = Mo()
    if not (f and M and Smooth() and (force or self:IsVisible())) then return end
    local _, _, _, a = HUD.Col(Look().flash, HUD.LOOK_DEFAULTS.flash)
    if a <= 0 then return end
    M.Stop(f)
    f:SetAlpha(a)
    f:Show()
    -- the flash is a white sheet over the icon: it may never be left up.
    -- A play that fails or doesn't start hides it at once, and a check a
    -- moment later puts away one nothing is fading any more (Zac
    -- 2026-11-02: the plate row's icons stuck white after a failed play)
    local ok, played = pcall(M.Play, f, MotionCfg().ready, "out")
    if not ok or not played then
        f:Hide()
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            if f:IsShown() and not (M.IsPlaying and M.IsPlaying(f)) then f:Hide() end
        end)
    end
end

function IconProto:SetSwipe(start, duration, durObj)
    if not self.cd then return end
    -- WoW Forever: a cooldown the game hides draws from its duration object
    -- (the game runs the swipe); a plain reading afterwards draws again
    if durObj and self.cd.SetCooldownFromDurationObject then
        if self.cdObj ~= durObj and pcall(self.cd.SetCooldownFromDurationObject, self.cd, durObj) then
            self.cdObj = durObj
            self.cdStart, self.cdDuration = nil, nil
        end
        if self.cdObj == durObj then return end
    end
    if self.cdObj then self.cdObj, self.cdStart, self.cdDuration = nil, -1, -1 end
    start, duration = start or 0, duration or 0
    if math.abs((self.cdStart or 0) - start) > 0.05
        or math.abs((self.cdDuration or 0) - duration) > 0.05 then
        -- a real cooldown (not the global one) that just ran out: flash
        local oldDur = self.cdDuration or 0
        if oldDur > 2 and duration <= 1.6
            and (self.cdStart or 0) + oldDur - GetTime() < 0.6 then
            self:Flash()
        end
        self.cdStart, self.cdDuration = start, duration
        self.cd:SetCooldown(start, duration)
    end
end

function IconProto:ClearSwipe()
    self:SetSwipe(0, 0)
end

-- Subtext. anchorMode: "CENTER", "BELOW"/"ABOVE" (WA anchor BOTTOM/TOP),
-- "INNER_BOTTOM", "INNER_BOTTOMRIGHT", "INNER_BOTTOMLEFT", "INNER_TOPRIGHT".
function IconProto:AddText(key, anchorMode, size, color, xOff, yOff, flags)
    local fs = HUD.Text(self.textOverlay or self, size or 14, flags or "OUTLINE", "OVERLAY", "text")
    local c = color or { 1, 1, 1, 1 }
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    -- a soft drop shadow under the outline: numbers stay readable over a
    -- bright icon without going to a thick outline that eats the glyphs
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
    -- that shadow is this text's own; the HUD text setting may replace it
    fs._hudSX, fs._hudSY = 1, -1
    HUD.ApplyFont(fs, size or 14, flags or "OUTLINE", "text")
    xOff, yOff = xOff or 0, yOff or 0
    -- the built-in spot (the WA anchor this text always had), kept on the
    -- text as its defaults; HUD.PlaceIconText puts the shared saved spot
    -- for this kind of text on top (nothing saved = this exact point)
    local p, rp
    if anchorMode == "BELOW" then
        -- WA BOTTOM + AUTO selfPoint: text CENTER sits on the edge, not below it.
        p, rp = "CENTER", "BOTTOM"
    elseif anchorMode == "ABOVE" then
        p, rp = "CENTER", "TOP"
    elseif anchorMode == "INNER_BOTTOM" then
        p, rp = "BOTTOM", "BOTTOM"
    elseif anchorMode == "INNER_TOPLEFT" then
        p, rp = "TOPLEFT", "TOPLEFT"
    elseif anchorMode == "INNER_BOTTOMRIGHT" then
        p, rp = "BOTTOMRIGHT", "BOTTOMRIGHT"
    elseif anchorMode == "INNER_BOTTOMLEFT" then
        p, rp = "BOTTOMLEFT", "BOTTOMLEFT"
    elseif anchorMode == "INNER_TOPRIGHT" then
        p, rp = "TOPRIGHT", "TOPRIGHT"
    elseif anchorMode == "OUTSIDE_LEFT" then
        -- beside the icon, on its left (a list of names, right-aligned)
        p, rp = "RIGHT", "LEFT"
        if fs.SetJustifyH then fs:SetJustifyH("RIGHT") end
    else
        p, rp = "CENTER", "CENTER"
    end
    fs._hudKey = key
    fs._hudIcon = self
    fs._hudDef = { point = p, relPoint = rp, x = xOff, y = yOff, to = self,
        justify = fs.GetJustifyH and fs:GetJustifyH() or nil }
    fs:SetPoint(p, self, rp, xOff, yOff)
    self.texts[key] = fs
    if HUD.PlaceIconText then HUD.PlaceIconText(fs) end
    return fs
end

function IconProto:SetText(key, text)
    local fs = self.texts[key]
    if fs and fs.lastText ~= text then
        fs.lastText = text
        fs:SetText(text)
    end
end

-- WoW Forever: an aura whose details the game hides in combat. Its icon,
-- timer and stacks go straight to the widgets (ns.ShowAuraTimer and the
-- rest of Core_Flavor's display helpers) with no maths on them. The
-- remembered values the plain setters above compare against are
-- cleared, so the next plain value always lands.
function IconProto:SetHiddenTexture(tex)
    self.curTexture = nil
    pcall(self.icon.SetTexture, self.icon, tex)
    local w, h = self:GetWidth(), self:GetHeight()
    self._zw, self._zh, self._zz, self._zk = w, h, self.zoom, self.keepAspect
    ApplyZoom(self.icon, w, h, self.zoom, self.keepAspect)
end

function IconProto:SetHiddenSwipe(unit, aura)
    if not self.cd then return false end
    self.cdStart, self.cdDuration = -1, -1
    return ns.ShowAuraTimer(self.cd, unit, aura)
end

-- a text from hidden values (SetFormattedText takes them as they are)
function IconProto:SetHiddenText(key, fmt, ...)
    local fs = self.texts[key]
    if not fs then return end
    fs.lastText = nil
    if not ns.ShowText(fs, fmt, ...) then fs:SetText("") end
end

-- the aura's stacks as the game words them ("" under two)
function IconProto:SetHiddenCount(key, unit, aura)
    local fs = self.texts[key]
    if not fs then return end
    fs.lastText = nil
    if not ns.ShowAuraCount(fs, unit, aura) then fs:SetText("") end
end

-- All glow styles render as the pulsing border (style arg kept for WA call sites).
function IconProto:AddGlow(key, style, opts)
    local g = CreateBorderGlow(self, opts)
    self.glows[key] = g
    return g
end

function IconProto:SetGlow(key, on)
    local g = self.glows[key]
    if not g then return end
    if on and not g:IsShown() then
        g:Show()                 -- OnShow starts the flare (or the stand-in's pulse)
    elseif not on and g:IsShown() then
        g:Hide()
    end
end

-- Status bar factory (WA aurabar: bg, fill, 1px border, optional spark)
function W.CreateBar(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(opts.width or 229, opts.height or 4)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetTexture(WHITE_TEX)
    local bgc = opts.bgColor or { 0, 0, 0, 0.6 }
    bg:SetVertexColor(bgc[1], bgc[2], bgc[3], bgc[4])
    f.bg = bg

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetAllPoints(f)
    bar:SetStatusBarTexture(ns.ResolveBarTexture and ns.ResolveBarTexture(Look().barTexture)
        or (ns.Media and ns.Media.BarPath(BAR_TEX)) or BAR_TEX)
    -- ZacUI's texture follows the Fonts & Textures page at once; a bar
    -- texture of the HUDs' own is put back right after (see below)
    if ns.Media then ns.Media.TrackBar(bar) end
    local bc = opts.barColor or { 1, 1, 1, 1 }
    bar:SetStatusBarColor(bc[1], bc[2], bc[3], bc[4] or 1)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    f.bar = bar

    -- sheen on the filled part only, and a soft glowing leading edge
    -- (bars with their own spark keep just that)
    local fillTex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if fillTex then
        local fs = bar:CreateTexture(nil, "ARTWORK", nil, 3)
        fs:SetPoint("TOPLEFT", fillTex, "TOPLEFT", 0, 0)
        fs:SetPoint("BOTTOMRIGHT", fillTex, "RIGHT", 0, 0)
        Sheen(fs, 0.22, 0.02)
        f.fillSheen = fs
        if not opts.spark then
            local edge = bar:CreateTexture(nil, "OVERLAY")
            edge:SetTexture(SPARK_TEX)
            edge:SetBlendMode("ADD")
            edge:SetSize(math.max(6, (opts.height or 4) * 1.6), math.max(8, (opts.height or 4) * 2.6))
            edge:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
            edge:SetAlpha(0.7)
            edge:Hide()
            f.edge = edge
        end
        local function Edge(self2, v)
            local on = Smooth()
            -- a hidden value (WoW Forever) on the bar: no maths on it, so
            -- the sheen and the edge sit out
            if issecretvalue ~= nil and v ~= nil and issecretvalue(v) then
                f._v = 0
                if f.fillSheen then f.fillSheen:Hide() end
                if f.edge then f.edge:Hide() end
                return
            end
            f._v = v or 0
            if f.fillSheen then f.fillSheen:SetShown(on and (f._sheenA or 0.22) > 0 and (v or 0) > 0.002) end
            if f.edge then f.edge:SetShown(on and (f._edgeA or 0.7) > 0 and (v or 0) > 0.01 and (v or 0) < 0.995) end
        end
        f._Edge = Edge
        if bar.HookScript then bar:HookScript("OnValueChanged", Edge) end
        Edge(bar, 0)
    end

    local border = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetTexture(WHITE_TEX)
        t:SetVertexColor(0, 0, 0, 1)
        border[i] = t
    end
    f.border = border
    f._bgDefault = opts.bgColor   -- a bar that asked for its own backing keeps it

    -- The shared look onto this bar: texture, backing, border, sheen and
    -- the glowing edge (W.ApplyLookAll calls it on every bar).
    function f:ApplyLook()
        local look = Look()
        local d = HUD.LOOK_DEFAULTS
        local path = ns.ResolveBarTexture and ns.ResolveBarTexture(look.barTexture)
        if path and path ~= self._tex then
            self._tex = path
            self.bar:SetStatusBarTexture(path)
        end
        if self._bgDefault then
            local c = self._bgDefault
            self.bg:SetVertexColor(c[1], c[2], c[3], c[4])
        else
            self.bg:SetVertexColor(HUD.Col(look.barBg, d.barBg))
        end
        local r, g, b, a = HUD.Col(look.barBorder, d.barBorder)
        local px = tonumber(look.barBorderSize) or 1
        local bd = self.border
        for i = 1, 4 do
            bd[i]:SetVertexColor(r, g, b, a)
            bd[i]:ClearAllPoints()
            bd[i]:SetShown(px > 0)
        end
        if px > 0 then
            bd[1]:SetPoint("TOPLEFT", self, "TOPLEFT", -px, px)
            bd[1]:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", px, 0)
            bd[2]:SetPoint("TOPLEFT", self, "BOTTOMLEFT", -px, 0)
            bd[2]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", px, -px)
            bd[3]:SetPoint("TOPLEFT", self, "TOPLEFT", -px, px)
            bd[3]:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", 0, -px)
            bd[4]:SetPoint("TOPLEFT", self, "TOPRIGHT", 0, px)
            bd[4]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", px, -px)
        end
        local sa = tonumber(look.barSheen) or 0.22
        if self.fillSheen and sa ~= self._sheenA then
            self._sheenA = sa
            Sheen(self.fillSheen, sa, sa * 0.02 / 0.22)
        end
        self._edgeA = tonumber(look.barEdge) or 0.7
        if self.edge then self.edge:SetAlpha(self._edgeA) end
        if self._Edge then self._Edge(self.bar, self._v or 0) end
    end
    f._sheenA = 0.22
    W.allBars[f] = true

    if opts.spark then
        local spark = bar:CreateTexture(nil, "OVERLAY")
        spark:SetTexture(SPARK_TEX)
        spark:SetBlendMode("ADD")
        spark:SetSize(opts.sparkWidth or 10, (opts.height or 4) * 2.5)
        f.spark = spark
        f.UpdateSpark = function(self, fraction)
            if fraction and fraction > 0 and fraction < 1 then
                self.spark:Show()
                self.spark:ClearAllPoints()
                self.spark:SetPoint("CENTER", self, "LEFT",
                    fraction * self:GetWidth(), 0)
            else
                self.spark:Hide()
            end
        end
    end

    f.SetBarColor = function(self, r, g, b, a)
        a = a or 1
        if self.lastR ~= r or self.lastG ~= g or self.lastB ~= b or self.lastA ~= a then
            self.lastR, self.lastG, self.lastB, self.lastA = r, g, b, a
            self.bar:SetStatusBarColor(r, g, b, a)
        end
    end

    f:ApplyLook()
    return f
end

-- ZacUI's texture changing (Fonts & Textures) retextures every tracked
-- bar to it; a bar on a texture of the HUDs' own gets that back at once.
if ns.Media and type(ns.Media.RetextureTracked) == "function" and hooksecurefunc then
    hooksecurefunc(ns.Media, "RetextureTracked", function()
        for b in pairs(W.allBars) do
            b._tex = nil
            if b.ApplyLook then b:ApplyLook() end
        end
    end)
end

-- Dynamic row layouts: port of the "Warrior Main" customGrow. rowsCfg =
-- array of { limit, w, h } (WA: 8/9/8 at 26/24/26); overflow fills the
-- last row. Positions are CENTER offsets from the row anchor; the WA's
-- -1px y correction below row 1 is kept.
local CORRECTION_Y = -1
local DEFAULT_ROWS = { { limit = 8, w = 26, h = 26 },
                       { limit = 9, w = 24, h = 24 },
                       { limit = 8, w = 26, h = 26 } }

function W.LayoutMainRow(anchor, frames, rowsCfg, spacing)
    rowsCfg = (rowsCfg and #rowsCfg > 0) and rowsCfg or DEFAULT_ROWS
    spacing = spacing or 3
    local total = #frames
    local nRows = #rowsCfg

    local rowOf, rowTotals = {}, {}
    do
        local row, used = 1, 0
        for i = 1, total do
            local limit = rowsCfg[row].limit or 8
            if used >= limit and row < nRows then
                row = row + 1
                used = 0
            end
            rowOf[i] = row
            used = used + 1
            rowTotals[row] = (rowTotals[row] or 0) + 1
        end
    end

    -- y offset of each row: cumulative prior heights + spacing + correction
    local rowY = { [1] = 0 }
    do
        local acc = 0
        for r = 2, nRows do
            acc = acc + (rowsCfg[r - 1].h or 26)
            rowY[r] = -(acc + spacing * (r - 1)) - CORRECTION_Y
        end
    end

    local xCount, lastRow = 0, nil
    for i, f in ipairs(frames) do
        local r = rowOf[i]
        local rc = rowsCfg[r]
        local w, h = rc.w or 26, rc.h or 26
        if r ~= lastRow then
            lastRow = r
            xCount = 0
        end
        f:SetSize(w, h)
        local rowTotal = rowTotals[r] or 1
        local x = -(w + spacing) / 2 * (rowTotal - 1) + xCount * (w + spacing)
        xCount = xCount + 1
        W.Place(f, anchor, x, rowY[r] or 0)
        if f.SetIconTexture and f.curTexture then
            f:SetIconTexture(f.curTexture)   -- re-crop for the new size
        end
    end
end

-- Centered horizontal row (WA "Warrior Aura Bar": 30px icons, space 4).
function W.LayoutHRow(anchor, frames, w, h, space)
    w, h, space = w or 30, h or 30, space or 4
    local n = #frames
    if n == 0 then return end
    local totalW = n * w + (n - 1) * space
    for i, f in ipairs(frames) do
        f:SetSize(w, h)
        W.Place(f, anchor, -totalW / 2 + w / 2 + (i - 1) * (w + space), 0)
        if f.SetIconTexture and f.curTexture then
            f:SetIconTexture(f.curTexture)   -- re-crop for the new size
        end
    end
end
