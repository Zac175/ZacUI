-- Core_Finish - the surface finish of ZacUI's own style.
-- Part of ZacUI; load order is set by the TOC.
--
-- (2026-11-16, Zac: "the solid blobs on no like texturing in some of the
-- zui menus just makes it look worse than the games normal version zui is
-- suppose to imporove the ui not make it look more ammiter". He picked from
-- mocks: soft depth, a brushed-metal ground - "dont overdo it" - and no
-- gradient across a title bar.)
--
-- A surface in ZacUI's style was one flat colour. It keeps that colour;
-- this lays four quiet things over it:
--   the grain   a brushed-metal tile (Media/Textures/brushed, made for
--               ZacUI by tools/make_brushed.py), light and dark streaks at
--               a few percent
--   the lift    white, strongest at the top, fading down
--   the sink    black, strongest at the foot, fading up
--   the lit edge  one pixel of pale light along the inside of the top
-- and, on a title bar or a section band, a dark line along its foot with a
-- pale one under it, so the bar reads as a raised piece and the page under
-- it as cut in.
--
-- ONE PLACE. The framework's builders call Finish.Dress on the fill they
-- have just made (a window, a cover, a card, a title bar, a skinned game
-- window's backdrop); nothing dresses a surface by hand. The pieces FOLLOW
-- THEIR FILL: hidden while it is hidden, faded with its alpha, gone when a
-- game look puts the fill away (Look.Back) - so a surface that is not
-- drawn in ZacUI's style never shows a finish.
--
-- ZacUIDB.finish: nil = 1 (as shipped), 0 = off (the flat surfaces of
-- before), up to 2. The Style page's "Surface finish" slider; live.
--
-- This file is NEW in 3.0.13 and so is its texture: the game only finds new
-- files after a restart. Every caller asks `ns.Finish and ...`, so a client
-- that was only reloaded keeps the flat surfaces instead of drawing a
-- texture it cannot find.

local ADDON_NAME, ns = ...

local FLAT = ns.FLAT or "Interface\\Buttons\\WHITE8X8"
local TEX = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Textures\\brushed"

local Finish = {}
ns.Finish = Finish
Finish.TEX = TEX

-- How much of each piece a kind of surface takes. Alphas, over the fill.
--   grain   share of GRAIN
--   lift    { at the top, at the foot }    white
--   sink    { at the top, at the foot }    black
--   lit     the pale line inside the top
--   foot    the dark line along the foot (a bar, a band)
--   step    the pale line under that foot
-- (2026-11-16 07:13, Zac, after seeing it in the game: "its too much with the
-- texturing i don't like it".) The grain is OFF: no brushed tile is drawn.
-- The soft depth stays until he has picked what replaces it.
local GRAIN = 0
local ROLES = {
    window = { grain = 1.00, lift = { 0.028, 0 },     sink = { 0, 0.14 }, lit = 0.055 },
    card   = { grain = 0.80, lift = { 0.030, 0 },     sink = { 0, 0.08 }, lit = 0.050 },
    bar    = { grain = 0.85, lift = { 0.070, 0.022 }, lit = 0.10, foot = 0.70, step = 0.05 },
    band   = { grain = 0.60, lift = { 0.090, 0.030 }, lit = 0.09, foot = 0.60 },
    -- a strip of chrome along a window's foot (money, actions): raised
    -- like a bar, with nothing under it to step down to
    strip  = { grain = 0.85, lift = { 0.045, 0.010 }, lit = 0.07 },
    -- a field cut into the surface: dark under its top lip, light caught
    -- under its foot. No grain: it is a hole, not a plate.
    well   = { shade = 0.30, shadeH = 5, catch = 0.05 },
}
Finish.ROLES = ROLES
Finish.GRAIN = GRAIN

local IsSecret = function(v) return issecretvalue ~= nil and issecretvalue(v) end

-- 0 (off) .. 2; nil in the saved settings is 1
function Finish.Strength()
    local v = type(ZacUIDB) == "table" and tonumber(ZacUIDB.finish) or nil
    if v == nil then return 1 end
    if v ~= v or v < 0 then return 0 end
    if v > 2 then return 2 end
    return v
end

-- fill -> what was laid over it. Weak: a fill that is gone takes it along.
local dressed = setmetatable({}, { __mode = "k" })
Finish.dressed = dressed

local function Part(host, layer, sub)
    local t = host:CreateTexture(nil, layer, nil, math.max(-8, math.min(7, sub)))
    t._zui_own = true
    t._zFinish = true
    t:SetTexture(FLAT)
    return t
end
function Finish.Is(tex) return type(tex) == "table" and rawget(tex, "_zFinish") == true end

-- white (or black) from one alpha at the top to another at the foot
local function Ramp(tex, v, top, bot)
    if CreateColor and tex.SetGradient then
        tex:SetVertexColor(1, 1, 1, 1)
        local ok = pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(v, v, v, bot), CreateColor(v, v, v, top))
        if ok then return end
    end
    if tex.SetGradientAlpha then
        tex:SetVertexColor(1, 1, 1, 1)
        local ok = pcall(tex.SetGradientAlpha, tex, "VERTICAL", v, v, v, bot, v, v, v, top)
        if ok then return end
    end
    tex:SetVertexColor(v, v, v, (top + bot) / 2)
end

local function Line(tex, host, side)
    if ns.Pixel then ns.Pixel.Edge(tex, side, host) else tex:SetHeight(1) end
end

local function ShowAll(d, on)
    for _, t in ipairs(d.parts) do t:SetShown(on) end
    d.on = on
end

-- Paints what lies over one fill from the fill as it is now.
local function Sync(d)
    if d.busy then return end
    d.busy = true
    local fill, r = d.fill, d.role
    local k = Finish.Strength()
    local a = 1
    if not d.always then
        a = fill.GetAlpha and fill:GetAlpha() or 1
        if IsSecret(a) or type(a) ~= "number" then a = 1 end
    end
    local shown = fill.IsShown == nil or fill:IsShown()
    if IsSecret(shown) then shown = true end
    if not shown or a <= 0.01 or k <= 0 then
        if d.on ~= false then ShowAll(d, false) end
        d.busy = nil
        return
    end
    if d.on ~= true then ShowAll(d, true) end
    local depth = math.min(1, k) * a
    if d.grain then d.grain:SetVertexColor(1, 1, 1, GRAIN * r.grain * k * a) end
    if d.lift then Ramp(d.lift, 1, r.lift[1] * depth, r.lift[2] * depth) end
    if d.sink then Ramp(d.sink, 0, r.sink[1] * depth, r.sink[2] * depth) end
    if d.lit then d.lit:SetVertexColor(1, 1, 1, r.lit * depth) end
    if d.foot then d.foot:SetVertexColor(0, 0, 0, r.foot * depth) end
    if d.step then d.step:SetVertexColor(1, 1, 1, r.step * depth) end
    if d.accent then
        local c = ns.Col and ns.Col("accent") or nil
        d.accent:SetVertexColor(c and c.r or 1, c and c.g or 1, c and c.b or 1, r.accent * depth)
    end
    if d.shade then Ramp(d.shade, 0, r.shade * depth, 0) end
    if d.catch then d.catch:SetVertexColor(1, 1, 1, r.catch * depth) end
    d.busy = nil
end

-- Lays the finish over `fill` (a texture ZacUI made: a window's colour, a
-- card's, a title bar's). role: "window", "card", "bar", "band", "strip",
-- "well".
--   opts.always  the pieces do not fade with the fill's alpha (a band whose
--                own colour is not drawn: the finish is all there is of it)
--   opts.step    false: no pale line under a bar's foot (the caller has one)
--   opts.inset   the lit edge sits this far in from the fill's sides and
--                top (default 1: inside a one-pixel border)
-- Safe to call twice; returns the record (or nil).
function Finish.Dress(fill, role, opts)
    if type(fill) ~= "table" or not fill.GetParent then return nil end
    if dressed[fill] then return dressed[fill] end
    local r = ROLES[role]
    if not r then return nil end
    opts = opts or {}
    local host = opts.host or fill:GetParent()
    if type(host) ~= "table" or not host.CreateTexture then return nil end
    local layer, sub = "BACKGROUND", -8
    if fill.GetDrawLayer then
        local ok, l, s = pcall(fill.GetDrawLayer, fill)
        if ok and type(l) == "string" then layer, sub = l, tonumber(s) or 0 end
    end
    local d = { fill = fill, role = r, always = opts.always and true or nil, parts = {} }
    local function Add(key, n)
        local t = Part(host, layer, sub + n)
        d[key] = t
        d.parts[#d.parts + 1] = t
        return t
    end
    local inset = opts.inset or 1
    if r.grain then
        local t = Add("grain", 1)
        t:SetTexture(TEX, "REPEAT", "REPEAT")
        if t.SetHorizTile then t:SetHorizTile(true) end
        if t.SetVertTile then t:SetVertTile(true) end
        t:SetAllPoints(fill)
    end
    if r.lift then Add("lift", 2):SetAllPoints(fill) end
    if r.sink then Add("sink", 3):SetAllPoints(fill) end
    if r.lit then
        local t = Add("lit", 4)
        Line(t, host, "TOP")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", fill, "TOPLEFT", inset, -inset)
        t:SetPoint("TOPRIGHT", fill, "TOPRIGHT", -inset, -inset)
    end
    if r.foot then
        local t = Add("foot", 4)
        Line(t, host, "BOTTOM")
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
        t:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    end
    if r.accent then
        -- a line in the accent colour along the foot (a title bar's rule)
        local t = Add("accent", 5)
        Line(t, host, "BOTTOM")
        if r.accentH then t:SetHeight(r.accentH) end
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
        t:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    end
    if r.step and opts.step ~= false then
        local t = Add("step", 4)
        Line(t, host, "TOP")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    end
    if r.shade then
        local t = Add("shade", 1)
        t:SetPoint("TOPLEFT", fill, "TOPLEFT", inset, -inset)
        t:SetPoint("TOPRIGHT", fill, "TOPRIGHT", -inset, -inset)
        t:SetHeight(r.shadeH or 5)
    end
    if r.catch then
        local t = Add("catch", 1)
        Line(t, host, "TOP")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    end
    dressed[fill] = d
    -- the pieces follow the fill from here on
    if hooksecurefunc then
        local function Follow() Sync(d) end
        for _, m in ipairs({ "SetVertexColor", "SetAlpha", "Show", "Hide", "SetShown" }) do
            if type(fill[m]) == "function" then pcall(hooksecurefunc, fill, m, Follow) end
        end
    end
    Sync(d)
    return d
end

-- The record over a fill, if it has one.
function Finish.Of(fill) return fill and dressed[fill] or nil end
-- Repaint one (after its fill changed in a way no hook sees).
function Finish.Sync(fill)
    local d = fill and dressed[fill]
    if d then Sync(d) end
end
-- Repaint everything (the Style page's slider).
function Finish.Refresh()
    for _, d in pairs(dressed) do Sync(d) end
end
