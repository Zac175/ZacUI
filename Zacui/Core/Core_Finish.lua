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
-- before), up to 2. The Style page's "Depth" slider; live.
--
-- THE FINISH IS A CHOICE (2026-11-18, Zac, of looks he had picked from
-- mocks: "users should be able to pick just use my choice as default").
-- Everything that was mocked on 2026-11-16 can be had; what ships is the
-- soft depth he picked, and a save with none of these set is that:
--   ZacUIDB.finish       how much of the shading is drawn (above)
--   ZacUIDB.finishKind   nil / "depth"  shaded surfaces, raised bars
--                        "bands"  no shading: title bars, strips, cards
--                                 and bands are flat DARKER pieces
--                        "plain"  flat: strips and bands a step lighter
--   ZacUIDB.finishRule   true: a line in the accent colour under a title bar
--   ZacUIDB.finishEdge   "soft": outlines are soft grey where no border
--                        colour was picked (Core_Colors reads SoftEdge)
--   ZacUIDB.finishGrain  how much of a ground texture is drawn, 0 .. 2
--                        (nil = none; 1 = the first build's brushed metal)
--   ZacUIDB.finishTex    which texture (Finish.TEXTURES; nil = brushed)
-- Finish.PRESETS names the mocked looks as values for the first five; the
-- Style page shows the preset the values match, or "Custom".
--
-- This file is NEW in 3.0.13 and so is its texture: the game only finds new
-- files after a restart. Every caller asks `ns.Finish and ...`, so a client
-- that was only reloaded keeps the flat surfaces instead of drawing a
-- texture it cannot find.

local ADDON_NAME, ns = ...

local FLAT = ns.FLAT or "Interface\\Buttons\\WHITE8X8"
local TEXDIR = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Textures\\"
local TEX = TEXDIR .. "brushed"

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
-- texturing i don't like it".) No texture is drawn unless one is asked for
-- (ZacUIDB.finishGrain); GRAIN is the tile's alpha at 100%, the first
-- build's.
local GRAIN = 0.055
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

-- The other two kinds of surface (the 2026-11-16 emphasis sheet's B and
-- C; D is B with the accent line). A role with nothing listed is the bare
-- fill. The texture's share per role is the depth table's, whatever the kind.
local KINDS = {
    depth = ROLES,
    bands = {
        window = {}, well = {},
        bar   = { sink = { 0.42, 0.42 } },
        strip = { sink = { 0.42, 0.42 } },
        card  = { sink = { 0.50, 0.50 } },
        band  = { sink = { 0.30, 0.30 } },
    },
    plain = {
        window = {}, well = {}, bar = {}, card = {},
        strip = { lift = { 0.035, 0.035 } },
        band  = { lift = { 0.05, 0.05 } },
    },
}
Finish.KINDS = KINDS
local RULE = 0.9                                    -- the accent line under a title bar
local SOFT = { r = 0.20, g = 0.20, b = 0.20, a = 1 }   -- the soft outline
Finish.SOFT_EDGE = SOFT

-- The ground textures: brushed metal (the first build's, tools/make_brushed.py)
-- and the other eight of the texture sheet (tools/make_grounds.py).
local TEXTURES = {
    { id = "brushed", label = "Brushed metal",  file = "brushed" },
    { id = "stone",   label = "Stone grain",    file = "ground_stone" },
    { id = "fine",    label = "Fine grain",     file = "ground_fine" },
    { id = "leather", label = "Leather",        file = "ground_leather" },
    { id = "iron",    label = "Hammered iron",  file = "ground_iron" },
    { id = "linen",   label = "Linen",          file = "ground_linen" },
    { id = "slate",   label = "Slate",          file = "ground_slate" },
    { id = "veined",  label = "Veined stone",   file = "ground_veined" },
    { id = "fibre",   label = "Paper fibre",    file = "ground_fibre" },
}
Finish.TEXTURES = TEXTURES
local TEX_FILE = {}
for _, t in ipairs(TEXTURES) do TEX_FILE[t.id] = t.file end

local function Saved(key)
    if type(ZacUIDB) ~= "table" then return nil end
    return ZacUIDB[key]
end
function Finish.Kind()
    local v = Saved("finishKind")
    return (v and KINDS[v]) and v or "depth"
end
function Finish.Rule() return Saved("finishRule") == true end
function Finish.SoftEdge() return Saved("finishEdge") == "soft" end
-- 0 (none) .. 2
function Finish.Grain()
    local v = tonumber(Saved("finishGrain"))
    if not v or v ~= v or v <= 0 then return 0 end
    return (v > 2) and 2 or v
end
function Finish.Texture()
    local v = Saved("finishTex")
    return (v and TEX_FILE[v]) and v or "brushed"
end
function Finish.TexturePath(id)
    return TEXDIR .. (TEX_FILE[id or Finish.Texture()] or "brushed")
end

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

-- One piece over a fill, made the first time it is wanted. Sublevels over
-- the fill: texture 1, lift 2, sink 3, the lines 4, the accent line 5.
local function Make(d, key)
    local fill, host, inset = d.fill, d.host, d.inset
    local function Add(n)
        local t = Part(host, d.layer, d.sub + n)
        d[key] = t
        d.parts[#d.parts + 1] = t
        return t
    end
    local t
    if key == "grain" then
        t = Add(1)
        d.grainTex = Finish.TexturePath()
        t:SetTexture(d.grainTex, "REPEAT", "REPEAT")
        if t.SetHorizTile then t:SetHorizTile(true) end
        if t.SetVertTile then t:SetVertTile(true) end
        t:SetAllPoints(fill)
    elseif key == "lift" then
        t = Add(2)
        t:SetAllPoints(fill)
    elseif key == "sink" then
        t = Add(3)
        t:SetAllPoints(fill)
    elseif key == "lit" then
        t = Add(4)
        Line(t, host, "TOP")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", fill, "TOPLEFT", inset, -inset)
        t:SetPoint("TOPRIGHT", fill, "TOPRIGHT", -inset, -inset)
    elseif key == "foot" then
        t = Add(4)
        Line(t, host, "BOTTOM")
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
        t:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    elseif key == "accent" then
        -- a line in the accent colour along the foot (a title bar's rule)
        t = Add(5)
        Line(t, host, "BOTTOM")
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", 0, 0)
        t:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    elseif key == "step" then
        t = Add(4)
        Line(t, host, "TOP")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    elseif key == "shade" then
        t = Add(1)
        t:SetPoint("TOPLEFT", fill, "TOPLEFT", inset, -inset)
        t:SetPoint("TOPRIGHT", fill, "TOPRIGHT", -inset, -inset)
        t:SetHeight(ROLES[d.name].shadeH or 5)
    elseif key == "catch" then
        t = Add(1)
        Line(t, host, "TOP")
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", fill, "BOTTOMLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    end
    return t
end

-- (the order pieces are made in when a fill is dressed)
local ORDER = { "grain", "lift", "sink", "lit", "foot", "step", "shade", "catch" }

local function HideAll(d)
    for _, t in ipairs(d.parts) do t:SetShown(false) end
    d.on = false
end

-- Paints what lies over one fill from the fill as it is now and from the
-- finish that is picked. A piece the picked finish does not have is hidden;
-- one it has and the fill never needed before is made here.
local function Sync(d)
    if d.busy then return end
    d.busy = true
    local fill = d.fill
    local k, g, rule = Finish.Strength(), Finish.Grain(), Finish.Rule() and d.name == "bar"
    local a = 1
    if not d.always then
        a = fill.GetAlpha and fill:GetAlpha() or 1
        if IsSecret(a) or type(a) ~= "number" then a = 1 end
    end
    local shown = fill.IsShown == nil or fill:IsShown()
    if IsSecret(shown) then shown = true end
    local share = ROLES[d.name].grain
    if not shown or a <= 0.01 or (k <= 0 and not rule and not (share and g > 0)) then
        if d.on ~= false then HideAll(d) end
        d.busy = nil
        return
    end
    d.on = true
    local r = KINDS[Finish.Kind()][d.name] or ROLES[d.name]
    local depth = math.min(1, k) * a
    -- the texture (a fill dressed while none was asked for keeps its piece
    -- at nothing, as it always had)
    if share and (d.grain or g > 0) then
        local t = d.grain or Make(d, "grain")
        local path = Finish.TexturePath()
        if d.grainTex ~= path then
            d.grainTex = path
            t:SetTexture(path, "REPEAT", "REPEAT")
        end
        t:SetShown(true)
        t:SetVertexColor(1, 1, 1, GRAIN * share * g * a)
    end
    local function Piece(key)
        local want = r[key] ~= nil and depth > 0 and not (key == "step" and d.noStep)
        local t = d[key]
        if want and not t then t = Make(d, key) end
        if t then t:SetShown(want) end
        return want and t or nil
    end
    local t = Piece("lift")
    if t then Ramp(t, 1, r.lift[1] * depth, r.lift[2] * depth) end
    t = Piece("sink")
    if t then Ramp(t, 0, r.sink[1] * depth, r.sink[2] * depth) end
    t = Piece("lit")
    if t then t:SetVertexColor(1, 1, 1, r.lit * depth) end
    t = Piece("foot")
    if t then t:SetVertexColor(0, 0, 0, r.foot * depth) end
    t = Piece("step")
    if t then t:SetVertexColor(1, 1, 1, r.step * depth) end
    t = Piece("shade")
    if t then Ramp(t, 0, r.shade * depth, 0) end
    t = Piece("catch")
    if t then t:SetVertexColor(1, 1, 1, r.catch * depth) end
    -- the accent line under a title bar
    if rule or d.accent then
        local line = d.accent or Make(d, "accent")
        line:SetShown(rule)
        if rule then
            local c = ns.Col and ns.Col("accent") or nil
            line:SetVertexColor(c and c.r or 1, c and c.g or 1, c and c.b or 1, RULE * a)
        end
    end
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
    local d = { fill = fill, role = r, name = role, host = host, layer = layer, sub = sub,
                inset = opts.inset or 1, noStep = (opts.step == false) or nil,
                always = opts.always and true or nil, parts = {} }
    -- the shipped finish's pieces, as before; another finish's are made
    -- when it is first painted
    for _, key in ipairs(ORDER) do
        if r[key] ~= nil and not (key == "step" and d.noStep) then Make(d, key) end
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
-- Repaint everything (the Style page's settings).
function Finish.Refresh()
    for _, d in pairs(dressed) do Sync(d) end
end

-- ============================================================
-- THE MOCKED LOOKS, AS PRESETS
-- ============================================================
-- A preset is values for the five keys; one it does not name is unset.
Finish.KEYS = { "finish", "finishKind", "finishRule", "finishEdge", "finishGrain" }
Finish.PRESETS = {
    { id = "depth",     label = "Soft depth",                       set = {} },
    { id = "flat",      label = "Flat",                             set = { finish = 0 } },
    { id = "bands",     label = "Dark bands",                       set = { finishKind = "bands", finishEdge = "soft" } },
    { id = "rule",      label = "Flat with an accent line",         set = { finishKind = "plain", finishRule = true, finishEdge = "soft" } },
    { id = "bandsrule", label = "Dark bands with an accent line",   set = { finishKind = "bands", finishRule = true, finishEdge = "soft" } },
    { id = "textured",  label = "Soft depth, textured",             set = { finishGrain = 1 } },
}
Finish.PRESET_DEFAULT = "depth"

-- The preset the saved values match: id, label - or "custom", "Custom".
function Finish.PresetNow()
    local k = math.min(1, Finish.Strength())
    local kind, rule, soft, g = Finish.Kind(), Finish.Rule(), Finish.SoftEdge(), Finish.Grain()
    for _, p in ipairs(Finish.PRESETS) do
        local set = p.set
        if math.abs((set.finish or 1) - k) < 0.001
            and (set.finishKind or "depth") == kind
            and (set.finishRule == true) == rule
            and (set.finishEdge == "soft") == soft
            and math.abs((set.finishGrain or 0) - g) < 0.001 then
            return p.id, p.label
        end
    end
    return "custom", "Custom"
end

-- After a finish setting changed: the surfaces, then Readycheck's windows
-- (a third of a second after the last change). outlines: the outline
-- colour changed too, so everything that paints from the border colour is
-- told as for a colour picked on the Colours page.
function Finish.Changed(outlines)
    Finish.Refresh()
    if outlines and ns.UI and ns.UI.Changed then ns.UI.Changed("color") end
    if ns.StyleChanged then ns.StyleChanged() end
end

function Finish.SetPreset(id)
    if type(ZacUIDB) ~= "table" then return false end
    for _, p in ipairs(Finish.PRESETS) do
        if p.id == id then
            local soft = Finish.SoftEdge()
            for _, key in ipairs(Finish.KEYS) do ZacUIDB[key] = p.set[key] end
            Finish.Changed(soft ~= Finish.SoftEdge())
            return true
        end
    end
    return false
end

-- Everything of the look another addon may follow (Readycheck's windows
-- do): the finish, and the button and wheel settings of UIF_Controls.
-- (one table, refilled on every call: read it, do not keep it)
local lookOut = {}
function Finish.Look()
    local L = lookOut
    L.depth, L.kind, L.rule, L.soft = Finish.Strength(), Finish.Kind(), Finish.Rule(), Finish.SoftEdge()
    L.grain, L.texture = Finish.Grain(), Finish.Texture()
    L.buttons, L.mainPlain = tonumber(Saved("buttonDepth")) or 1, Saved("mainButton") == "plain"
    L.wheel, L.smooth = tonumber(Saved("wheelSpeed")) or 1, Saved("wheelSmooth") ~= false
    return L
end
