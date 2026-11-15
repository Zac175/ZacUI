-- NP_ClassicPlate - the game looks on ZacUI's own nameplates
-- (2026-11-08): the vanilla nameplate's border art round the health bar and
-- the cast bar, as the game drew its plates - Interface\Tooltips\
-- Nameplate-Border and Nameplate-Border-Castbar, each a long window in the
-- art with a plate at one end, drawn in three pieces so the plates keep
-- their shape at any bar width while the window stretches. The reference
-- UI measured both sheets (EllesmereUINameplates/EUI_Nameplates_Styles.lua
-- ns.NP_CLASSIC; the numbers reused here, in units of the bar's height;
-- zui_tests/GAMELOOK_STUDY_1108.md). Both files ship on Era, TBC, Forever
-- and Retail.
-- Blizzard style and WoW Forever: the modern plate art (below).
-- Under the Classic look this art replaces the bars' edge (the tooltip
-- border scaled down, which read as a thick grey box on a 17 px bar); the
-- bars, fills, texts, auras and every plate feature are as they were. Under
-- ZacUI's look (and the modern looks) nothing here is made: one look read
-- per layout pass. Part of ZacUI; load order is set by the TOC (after
-- NP_Cast: it wraps NP.LayoutFrame and NP.LayoutCast).

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
local NP = ns.Nameplates
if not (NP and NP.LayoutFrame and NP.LayoutCast) then return end

-- art texcoords (its opaque extent), c1 / c2 the window's two ends; capL /
-- capR the end pieces' widths and reachL / reachR how far the art reaches
-- past the bar, all times the bar's height; top / bottom the art's reach
-- above and below the bar
local ART = {
    health = { file = "Interface\\Tooltips\\Nameplate-Border",
               l = 0.0049, r = 0.5261, t = 0.5065, b = 0.9610, c1 = 0.0195, c2 = 0.4137,
               capL = 0.187, capR = 1.440, reachL = 0.137, reachR = 1.310 },
    cast   = { file = "Interface\\Tooltips\\Nameplate-Border-Castbar",
               l = 0.0081, r = 0.9919, t = 0.5065, b = 0.9610, c1 = 0.1710, c2 = 0.9609,
               capL = 2.086, capR = 0.390, reachL = 1.956, reachR = 0.260 },
}
local TOP, BOTTOM = 0.230, 0.229

-- (2026-11-08) a plate's bar height read safely: on the modern clients a
-- nameplate's regions can't always be measured (an error, or a hidden value)
local function SafeHeight(r, d)
    local ok, h = pcall(r.GetHeight, r)
    if not ok or type(h) ~= "number" then return d end
    if issecretvalue and issecretvalue(h) then return d end
    local ok2, pos = pcall(function() return h > 0 end)
    if ok2 and pos then return h end
    return d
end
local function Classic()
    local L = ns.Look
    return L and L.Is and L.Is("nameplates", "classic") or false
end
NP.ClassicPlateOn = Classic

-- the three pieces round `bar` (made the first time), or put away
local function Plate(bar, spec)
    if not bar then return end
    local pieces = rawget(bar, "_zClassicPlate")
    if not spec then
        if pieces then
            for _, t in ipairs(pieces) do t:Hide() end
            local edge = rawget(bar, "_zui_edge")
            if edge and edge.SetAlpha then edge:SetAlpha(1) end
        end
        return
    end
    if not pieces then
        pieces = {}
        for i = 1, 4 do
            local t = bar:CreateTexture(nil, "OVERLAY", nil, 6)
            t._zui_own = true
            pieces[i] = t
        end
        rawset(bar, "_zClassicPlate", pieces)
    end
    -- the bar's own edge steps back; the art is the edge now
    local edge = rawget(bar, "_zui_edge")
    if edge and edge.SetAlpha then edge:SetAlpha(0) end
    local k = SafeHeight(bar, 12)
    local top, bot = TOP * k, BOTTOM * k
    local L, M, R = pieces[1], pieces[2], pieces[3]
    for _, t in ipairs(pieces) do
        t:SetTexture(spec.file)
        t:ClearAllPoints()
        t:Show()
    end
    L:SetTexCoord(spec.l, spec.c1, spec.t, spec.b)
    L:SetWidth(spec.capL * k)
    L:SetPoint("TOPLEFT", bar, "TOPLEFT", -spec.reachL * k, top)
    L:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -spec.reachL * k, -bot)
    R:SetTexCoord(spec.c2, spec.r, spec.t, spec.b)
    R:SetWidth(spec.capR * k)
    R:SetPoint("TOPRIGHT", bar, "TOPRIGHT", spec.reachR * k, top)
    R:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", spec.reachR * k, -bot)
    local M2 = pieces[4]
    if spec == ART.health and M2 then
        -- (2026-11-08, Zac: "there needs to be nothing behind the health
        -- bars") the art's middle is cut in two: its rim above the bar and
        -- its rim below it. The art's grey inside, over the bar, is left out.
        local span = 1 + TOP + BOTTOM
        local tt = spec.t + (spec.b - spec.t) * TOP / span
        local bb = spec.b - (spec.b - spec.t) * BOTTOM / span
        M:SetTexCoord(spec.c1, spec.c2, spec.t, tt)
        M:SetPoint("TOPLEFT", L, "TOPRIGHT", 0, 0)
        M:SetPoint("BOTTOMRIGHT", R, "TOPLEFT", 0, -top)
        M2:SetTexCoord(spec.c1, spec.c2, bb, spec.b)
        M2:SetPoint("TOPLEFT", L, "BOTTOMRIGHT", 0, bot)
        M2:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT", 0, 0)
    else
        if M2 then M2:Hide() end
        M:SetTexCoord(spec.c1, spec.c2, spec.t, spec.b)
        M:SetPoint("TOPLEFT", L, "TOPRIGHT", 0, 0)
        M:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT", 0, 0)
    end
end
NP.ClassicPlate = Plate

-- ============================================================
-- BLIZZARD STYLE / WOW FOREVER: the modern client's plate art, where it
-- has it (C_Texture.GetAtlasInfo): the stock bar background hugging the
-- bar (2 left / 3 above, 6 right / 6 below), the fill shaped by the stock
-- bar's own footprint (a mask; on Forever its rim reaches 1 unit up over
-- the bar's bottom, so the mask stops there) and the soft inner shadow the
-- stock fill bakes in (black, from the top 0.55 / bottom 0.30 / ends 0.35)
-- - the reference's composition; the fill keeps ZacUI's colours. The cast
-- bar sits on the client's cast bar background. The edge steps back.
-- ============================================================
local BAR, BAR_BG, CAST_BG = "UI-HUD-CoolDownManager-Bar", "UI-HUD-CoolDownManager-Bar-BG", "ui-castingbar-background"
local function AtlasOK(n)
    local CT = _G.C_Texture
    if not (n and CT and CT.GetAtlasInfo) then return false end
    local ok, info = pcall(CT.GetAtlasInfo, n)
    return ok and info and true or false
end
local function ModernLook()
    local L = ns.Look
    local lk = L and L.For and L.For("nameplates")
    if lk and (lk.id == "blizzard" or lk.id == "forever") then return lk.id end
    return nil
end
NP.ModernPlateLook = ModernLook

local SHADE = { top = 0.55, bottom = 0.30, ends = 0.35 }
local function Shade(bar, on)
    local sh = rawget(bar, "_zModernShade")
    if not on then
        if sh then for i = 1, 4 do sh[i]:Hide() end end
        return
    end
    if not sh then
        sh = {}
        for i = 1, 4 do
            local t = bar:CreateTexture(nil, "OVERLAY", nil, -3)
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            t._zui_own = true
            sh[i] = t
        end
        local clear = CreateColor and CreateColor(0, 0, 0, 0)
        local function Grad(t, dir, a, b)
            if t.SetGradient and clear then pcall(t.SetGradient, t, dir, a, b)
            else t:SetVertexColor(0, 0, 0, 0.3) end
        end
        if CreateColor then
            Grad(sh[1], "VERTICAL", clear, CreateColor(0, 0, 0, SHADE.top))
            Grad(sh[2], "VERTICAL", CreateColor(0, 0, 0, SHADE.bottom), clear)
            Grad(sh[3], "HORIZONTAL", CreateColor(0, 0, 0, SHADE.ends), clear)
            Grad(sh[4], "HORIZONTAL", clear, CreateColor(0, 0, 0, SHADE.ends))
        end
        rawset(bar, "_zModernShade", sh)
    end
    local h = SafeHeight(bar, 10)
    local top, bottom, ends = math.max(2, math.floor(h * 0.2)), math.max(1, math.floor(h * 0.1)), math.max(2, math.floor(h * 0.15))
    for i = 1, 4 do sh[i]:ClearAllPoints() sh[i]:Show() end
    -- (2026-11-08) on the fill only: the missing part shows nothing
    local fl = bar.GetStatusBarTexture and bar:GetStatusBarTexture() or bar
    if type(fl) ~= "table" then fl = bar end
    sh[1]:SetPoint("TOPLEFT", fl, "TOPLEFT", 0, 0) sh[1]:SetPoint("TOPRIGHT", fl, "TOPRIGHT", 0, 0) sh[1]:SetHeight(top)
    sh[2]:SetPoint("BOTTOMLEFT", fl, "BOTTOMLEFT", 0, 0) sh[2]:SetPoint("BOTTOMRIGHT", fl, "BOTTOMRIGHT", 0, 0) sh[2]:SetHeight(bottom)
    sh[3]:SetPoint("TOPLEFT", fl, "TOPLEFT", 0, 0) sh[3]:SetPoint("BOTTOMLEFT", fl, "BOTTOMLEFT", 0, 0) sh[3]:SetWidth(ends)
    sh[4]:SetPoint("TOPRIGHT", fl, "TOPRIGHT", 0, 0) sh[4]:SetPoint("BOTTOMRIGHT", fl, "BOTTOMRIGHT", 0, 0) sh[4]:SetWidth(ends)
end

-- (2026-11-08) the stock bar background's RIM only, round the health: the
-- atlas cut into four edge slices from its own sheet coordinates, so its
-- grey inside never sits behind the bar. Reach: 2 left, 3 up, 6 right,
-- 6 down - where the whole art was hung.
local RIM = { l = 2, t = 3, r = 6, b = 6 }
function NP.ModernRim(bar, on)
    local rim = rawget(bar, "_zModernRim")
    if not on then
        if rim then for i = 1, #rim do rim[i]:Hide() end end
        return
    end
    -- (2026-11-09, Zac: "doesnt fully connect and the health still goes
    -- outside the border") the stock art cut into slices never met at the
    -- corners. Drawn instead, exact: a light rim line ON the bar's outer
    -- pixel all round (over the fill, so the fill can never show past it)
    -- and a dark line just outside it - closed at every corner.
    if not rim then
        rim = {}
        for i = 1, 8 do
            local t = bar:CreateTexture(nil, "OVERLAY", nil, i <= 4 and 5 or 4)
            t._zui_own = true
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            rim[i] = t
        end
        rawset(bar, "_zModernRim", rim)
    end
    for i = 1, 8 do rim[i]:ClearAllPoints() rim[i]:Show() end
    for i = 1, 4 do rim[i]:SetVertexColor(0.80, 0.75, 0.60, 1) end
    for i = 5, 8 do rim[i]:SetVertexColor(0, 0, 0, 0.9) end
    local function Box(t, r, o)
        -- r = the four textures from index t; o = 0 on the bar's edge, 1 outside
        local top, bot, lf, rt = rim[t], rim[t + 1], rim[t + 2], rim[t + 3]
        top:SetPoint("TOPLEFT", bar, "TOPLEFT", -o, o)
        top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", o, o)
        top:SetHeight(1)
        bot:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -o, -o)
        bot:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", o, -o)
        bot:SetHeight(1)
        lf:SetPoint("TOPLEFT", bar, "TOPLEFT", -o, o)
        lf:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -o, -o)
        lf:SetWidth(1)
        rt:SetPoint("TOPRIGHT", bar, "TOPRIGHT", o, o)
        rt:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", o, -o)
        rt:SetWidth(1)
    end
    Box(1, nil, 0)
    Box(5, nil, 1)
end

-- the modern art on a bar (`kind` "health" | "cast"), or put away (nil)
local function Modern(bar, kind, lookId)
    if not bar then return end
    local bg = rawget(bar, "_zModernBg")
    local want = kind and AtlasOK(kind == "cast" and CAST_BG or BAR_BG)
    if not want or kind ~= "health" then NP.ModernRim(bar, false) end
    if not want then
        if bg then bg:Hide() end
        Shade(bar, false)
        local m, fill = rawget(bar, "_zModernMask"), rawget(bar, "_zModernMasked")
        if m and fill and fill.RemoveMaskTexture then pcall(fill.RemoveMaskTexture, fill, m) end
        rawset(bar, "_zModernMasked", nil)
        if rawget(bar, "_zModernOn") then
            local edge = rawget(bar, "_zui_edge")
            if edge and edge.SetAlpha then edge:SetAlpha(1) end
            if bar.bg and bar.bg.SetAlpha then bar.bg:SetAlpha((kind == nil and NP.StockLook and NP.StockLook()) and 0 or 1) end
            rawset(bar, "_zModernOn", nil)
        end
        return
    end
    rawset(bar, "_zModernOn", true)
    local edge = rawget(bar, "_zui_edge")
    if edge and edge.SetAlpha then edge:SetAlpha(0) end
    if not bg then
        bg = bar:CreateTexture(nil, "BACKGROUND", nil, -6)
        bg._zui_own = true
        rawset(bar, "_zModernBg", bg)
    end
    bg:SetAtlas(kind == "cast" and CAST_BG or BAR_BG)
    bg:SetVertexColor(1, 1, 1, 1)
    bg:ClearAllPoints()
    if kind == "cast" then
        bg:SetAllPoints(bar)
    else
        bg:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
        bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -6)
    end
    -- (2026-11-08, Zac: "there needs to be nothing behind the health
    -- bars") the health keeps no backing art - its grey fill read as a
    -- background; the look's plain edge rims the bar instead. The cast
    -- bar keeps the client's cast background.
    -- (2026-11-09) the client's own art, exactly as its plate hangs it
    -- (Blizzard_NamePlateUnitFrame UpdateAnchors: the bar background at
    -- -2,3 / 6,-6). The grey that read over it was ZacUI's box edge, gone
    -- now (NP_Health); the drawn rim is put away.
    NP.ModernRim(bar, false)
    bg:Show()
    -- the bar's own dark backing goes (the art is the backing now)
    if bar.bg and bar.bg.SetAlpha then bar.bg:SetAlpha(0) end
    if kind == "health" then
        -- (2026-11-09, Zac: "the health bar still goes in front of the
        -- border art") the client's own fill, as its plate draws it
        -- (BarTexture atlas UI-HUD-CoolDownManager-Bar, all points): made to
        -- sit inside the background's rim, its shading baked in. No flat
        -- fill cut by a mask, no extra shade.
        local m, fill0 = rawget(bar, "_zModernMask"), rawget(bar, "_zModernMasked")
        if m and fill0 and fill0.RemoveMaskTexture then pcall(fill0.RemoveMaskTexture, fill0, m) end
        rawset(bar, "_zModernMasked", nil)
        Shade(bar, false)
        if AtlasOK(BAR) then
            pcall(bar.SetStatusBarTexture, bar, BAR)
            local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
            if type(fill) == "table" and fill.SetAtlas then
                local ok, cur = pcall(fill.GetAtlas, fill)
                if not (ok and cur and cur:lower() == BAR:lower()) then pcall(fill.SetAtlas, fill, BAR) end
            end
        end
    end
end
NP.ModernPlate = Modern

-- ============================================================
-- THE STOCK TARGET CUE (every game look): a white wash at 0.20 over the
-- health bar of the plate you target - the reference's stock-style cue
-- (EllesmereUINameplates: targetHighlightColor white, alpha 0.20) - in
-- place of ZacUI's box / arrows / glow, which NP_Core and NP_Extras keep
-- off under a game look. Shaped like the fill under the modern looks.
-- ============================================================
-- the client's own target border on a modern look (UI-HUD-Nameplates-
-- Selected round the bar background: -1,1 / -3,3 from it, as the stock
-- plate hangs it)
local SELECTED = "UI-HUD-Nameplates-Selected"
function NP.StockSelected(f, on)
    local hb = f and f.health
    if not hb then return end
    local sel = rawget(hb, "_zStockSel")
    local bg = rawget(hb, "_zModernBg")
    if not (on and bg and bg:IsShown() and AtlasOK(SELECTED)) then
        if sel then sel:Hide() end
        return
    end
    if not sel then
        sel = hb:CreateTexture(nil, "OVERLAY", nil, 1)
        sel._zui_own = true
        sel:SetAtlas(SELECTED)
        rawset(hb, "_zStockSel", sel)
    end
    sel:ClearAllPoints()
    sel:SetPoint("TOPLEFT", bg, "TOPLEFT", -1, 1)
    sel:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -3, 3)
    sel:SetVertexColor(1, 1, 1, 1)
    sel:Show()
end

function NP.StockTargetWash(f, on)
    -- (2026-11-09, Zac: "why is there a white border when targeting mobs")
    -- no target border either: the target reads by the plate's full alpha
    NP.StockSelected(f, false)
    local hb = f and f.health
    if not hb then return end
    local w = rawget(hb, "_zStockWash")
    -- (2026-11-08, Zac: the white wash read as a light background over the
    -- bar; the stock plates keep their own colours on the target) never on
    on = false
    if not on then
        if w then w:Hide() end
        return
    end
    if not w then
        w = hb:CreateTexture(nil, "ARTWORK", nil, 3)
        w._zui_own = true
        w:SetAllPoints(hb)
        w:SetColorTexture(1, 1, 1, 0.20)
        rawset(hb, "_zStockWash", w)
    end
    local m = rawget(hb, "_zModernMask")
    if m and w.AddMaskTexture and not rawget(w, "_zMasked") then
        pcall(w.AddMaskTexture, w, m)
        rawset(w, "_zMasked", true)
    end
    w:Show()
end

-- ============================================================
-- THE LEVEL IN THE CLASSIC BORDER'S LEVEL BOX: centred 0.584 x the bar's
-- height right of the bar's right edge, at 0.75 x the height (the
-- reference's measurements of the vanilla sheet), as the stock Classic
-- plate shows it - not at the bar's left. A name hung off the level
-- (the name inside the bar) is hung off the bar's left instead, where the
-- level stood.
-- ============================================================
local LEVEL_OFF, LEVEL_FONT = 0.584, 0.75
local function ClassicLevel(f)
    local lv, hb = f and f.level, f and f.health
    if not (lv and hb) then return end
    local k = SafeHeight(hb, 12)
    lv:ClearAllPoints()
    lv:SetPoint("CENTER", hb, "RIGHT", LEVEL_OFF * k, 0)
    if lv.SetJustifyH then lv:SetJustifyH("CENTER") end
    local face, _, flags = lv:GetFont()
    if face then pcall(lv.SetFont, lv, face, math.max(6, math.floor(LEVEL_FONT * k + 0.5)), flags) end
    -- a name inside the bar hangs off the level (NP_Health): it goes back
    -- to the bar's left end. Read from our own flag, never the name's
    -- points: a plate's regions can't be measured on the modern clients.
    local nm = f.name
    if nm and f._nameInside and not f.nameOnly then
        nm:ClearAllPoints()
        nm:SetPoint("LEFT", hb, "LEFT", 3, 0)
        if f.percent then nm:SetPoint("RIGHT", f.percent, "LEFT", -3, 0) end
    end
    rawset(f, "_zClassicLevel", true)
end
NP.ClassicLevel = ClassicLevel
local markerLevel = NP.MarkerLevel
if markerLevel then
    NP.MarkerLevel = function(f, ...)
        markerLevel(f, ...)
        if f and Classic() then ClassicLevel(f) end
    end
end

-- Blizzard style / WoW Forever: the level right of the bar, 5 units out,
-- in WoW Forever's level box (ui-hud-nameplates-levelindicator, 28 wide,
-- 5 taller than the bar, the number at 10 - Blizzard's own nameplate
-- constants as the reference reads them); the plain number where the
-- client has no box art. A name hung off the level goes back to the bar.
local LVL = { w = 28, gap = 5, pad = 5, font = 10, atlas = "ui-hud-nameplates-levelindicator" }
local function ModernLevel(f)
    local lv, hb = f and f.level, f and f.health
    if not (lv and hb) then return end
    local box = rawget(hb, "_zLevelBox")
    local h = SafeHeight(hb, 12)
    if AtlasOK(LVL.atlas) then
        if not box then
            box = hb:CreateTexture(nil, "OVERLAY", nil, 1)
            box._zui_own = true
            rawset(hb, "_zLevelBox", box)
        end
        box:SetAtlas(LVL.atlas)
        box:ClearAllPoints()
        box:SetPoint("LEFT", hb, "RIGHT", LVL.gap, 0)
        box:SetSize(LVL.w, h + LVL.pad)
        box:Show()
    elseif box then
        box:Hide()
    end
    lv:ClearAllPoints()
    lv:SetPoint("CENTER", hb, "RIGHT", LVL.gap + LVL.w / 2, 0)
    if lv.SetJustifyH then lv:SetJustifyH("CENTER") end
    local face, _, flags = lv:GetFont()
    if face then pcall(lv.SetFont, lv, face, LVL.font, flags) end
    -- a name inside the bar hangs off the level (NP_Health): it goes back
    -- to the bar's left end. Read from our own flag, never the name's
    -- points: a plate's regions can't be measured on the modern clients.
    local nm = f.name
    if nm and f._nameInside and not f.nameOnly then
        nm:ClearAllPoints()
        nm:SetPoint("LEFT", hb, "LEFT", 3, 0)
        if f.percent then nm:SetPoint("RIGHT", f.percent, "LEFT", -3, 0) end
    end
end
local function LevelBoxOff(f)
    local box = f and f.health and rawget(f.health, "_zLevelBox")
    if box then box:Hide() end
end
local function GameLevel(f)
    if Classic() then LevelBoxOff(f) ClassicLevel(f)
    elseif ModernLook() then ModernLevel(f)
    else LevelBoxOff(f) end
end
do
    local inner = NP.MarkerLevel
    if inner then
        NP.MarkerLevel = function(f, ...)
            inner(f, ...)
            if f and (ModernLook()) then ModernLevel(f) end
        end
    end
end

local layoutFrame, layoutCast = NP.LayoutFrame, NP.LayoutCast
NP.LayoutFrame = function(f, ...)
    layoutFrame(f, ...)
    if f and f.health then
        local modern = ModernLook()
        Plate(f.health, Classic() and ART.health or nil)
        Modern(f.health, modern and "health" or nil, modern)
        GameLevel(f)
    end
end
NP.LayoutCast = function(f, ...)
    layoutCast(f, ...)
    if f and f.cast then
        local modern = ModernLook()
        Plate(f.cast, Classic() and ART.cast or nil)
        Modern(f.cast, modern and "cast" or nil, modern)
    end
end
NP.CLASSIC_PLATE = ART
