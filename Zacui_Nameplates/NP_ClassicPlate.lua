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
        for i = 1, 3 do
            local t = bar:CreateTexture(nil, "OVERLAY", nil, 6)
            t._zui_own = true
            pieces[i] = t
        end
        rawset(bar, "_zClassicPlate", pieces)
    end
    -- the bar's own edge steps back; the art is the edge now
    local edge = rawget(bar, "_zui_edge")
    if edge and edge.SetAlpha then edge:SetAlpha(0) end
    local k = bar:GetHeight()
    if type(k) ~= "number" or k <= 0 then k = 12 end
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
    M:SetTexCoord(spec.c1, spec.c2, spec.t, spec.b)
    M:SetPoint("TOPLEFT", L, "TOPRIGHT", 0, 0)
    M:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT", 0, 0)
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
    local h = bar:GetHeight()
    if type(h) ~= "number" or h <= 0 then h = 10 end
    local top, bottom, ends = math.max(2, math.floor(h * 0.2)), math.max(1, math.floor(h * 0.1)), math.max(2, math.floor(h * 0.15))
    for i = 1, 4 do sh[i]:ClearAllPoints() sh[i]:Show() end
    sh[1]:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0) sh[1]:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0) sh[1]:SetHeight(top)
    sh[2]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0) sh[2]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0) sh[2]:SetHeight(bottom)
    sh[3]:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0) sh[3]:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0) sh[3]:SetWidth(ends)
    sh[4]:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0) sh[4]:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0) sh[4]:SetWidth(ends)
end

-- the modern art on a bar (`kind` "health" | "cast"), or put away (nil)
local function Modern(bar, kind, lookId)
    if not bar then return end
    local bg = rawget(bar, "_zModernBg")
    local want = kind and AtlasOK(kind == "cast" and CAST_BG or BAR_BG)
    if not want then
        if bg then bg:Hide() end
        Shade(bar, false)
        local m, fill = rawget(bar, "_zModernMask"), rawget(bar, "_zModernMasked")
        if m and fill and fill.RemoveMaskTexture then pcall(fill.RemoveMaskTexture, fill, m) end
        rawset(bar, "_zModernMasked", nil)
        if rawget(bar, "_zModernOn") then
            local edge = rawget(bar, "_zui_edge")
            if edge and edge.SetAlpha then edge:SetAlpha(1) end
            if bar.bg and bar.bg.SetAlpha then bar.bg:SetAlpha(1) end
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
    bg:Show()
    -- the bar's own dark backing goes (the art is the backing now)
    if bar.bg and bar.bg.SetAlpha then bar.bg:SetAlpha(0) end
    if kind == "health" then
        local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        if AtlasOK(BAR) and type(fill) == "table" and fill.AddMaskTexture and bar.CreateMaskTexture then
            local m = rawget(bar, "_zModernMask")
            if not m then
                m = bar:CreateMaskTexture()
                m:SetAtlas(BAR)
                rawset(bar, "_zModernMask", m)
            end
            m:ClearAllPoints()
            m:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            m:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, lookId == "forever" and 1 or 0)
            if rawget(bar, "_zModernMasked") ~= fill then
                pcall(fill.RemoveMaskTexture, fill, m)
                fill:AddMaskTexture(m)
                rawset(bar, "_zModernMasked", fill)
            end
        end
        Shade(bar, true)
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
function NP.StockTargetWash(f, on)
    local hb = f and f.health
    if not hb then return end
    local w = rawget(hb, "_zStockWash")
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
    local k = hb:GetHeight()
    if type(k) ~= "number" or k <= 0 then k = 12 end
    lv:ClearAllPoints()
    lv:SetPoint("CENTER", hb, "RIGHT", LEVEL_OFF * k, 0)
    if lv.SetJustifyH then lv:SetJustifyH("CENTER") end
    local face, _, flags = lv:GetFont()
    if face then pcall(lv.SetFont, lv, face, math.max(6, math.floor(LEVEL_FONT * k + 0.5)), flags) end
    local nm = f.name
    if nm and nm.GetNumPoints then
        for i = 1, nm:GetNumPoints() do
            local p, rel, rp, x, y = nm:GetPoint(i)
            if rel == lv then
                nm:ClearAllPoints()
                nm:SetPoint(p, hb, "LEFT", 3, y or 0)
                if f.percent then nm:SetPoint("RIGHT", f.percent, "LEFT", -3, 0) end
                break
            end
        end
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
    local h = hb:GetHeight()
    if type(h) ~= "number" or h <= 0 then h = 12 end
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
    local nm = f.name
    if nm and nm.GetNumPoints then
        for i = 1, nm:GetNumPoints() do
            local p, rel, rp, x, y = nm:GetPoint(i)
            if rel == lv then
                nm:ClearAllPoints()
                nm:SetPoint(p, hb, "LEFT", 3, y or 0)
                if f.percent then nm:SetPoint("RIGHT", f.percent, "LEFT", -3, 0) end
                break
            end
        end
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
