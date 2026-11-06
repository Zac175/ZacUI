-- Crosshair_Core - the crosshair itself, shared word for word between
-- ZacUI (Zacui_Nameplates/NP_Crosshair.lua is its host there) and the
-- standalone ZacCrosshair addon. It publishes one global factory,
-- ZacCrosshairCore.New(host), and nothing else; the host supplies the
-- settings table, printing, the flat texture, Edit Mode hooks and how to
-- read a nameplate (the health bar and what sticks out past it).
--
-- WHAT IT DRAWS. Lines from the screen edges in to your target's
-- nameplate, stopping at its edges and following it; and, new, a
-- reticle FRAME around the plate: a box, corner brackets, a ring, an
-- oval, a dotted ring or four ticks - with its own padding, thickness
-- and colour, or the lines' colour. Lines, frame or both. A centre dot
-- is optional. With no plate to follow (no target, target out of plate
-- range) it falls back to the screen centre when the show rule says it
-- should be up at all.
--
-- WHERE. On UIParent, anchored to the target plate's health bar - never
-- inside a nameplate (the DART_Crosshairs pattern): one anchor chain the
-- game allows, long lines the screen edge clips, nothing measured except
-- the frame box's own size (read in its OnSizeChanged, which fires only
-- when the plate it sits on changes shape).
--
-- WHEN. Events decide whether it is up (target, combat, zoning, plates);
-- the anchor does the following, so nothing is polled except the range
-- colour, 5 times a second, while that option is on.

local Core = _G.ZacCrosshairCore or {}
_G.ZacCrosshairCore = Core
Core.VERSION = 2

-- short mode geometry, in physical pixels
local ARM = 200
local GAP = 24
local LINE_LEN = 8192

Core.DEFAULTS = {
    enabled = false,
    color = { 1, 0.2, 0.2 },
    alpha = 0.6,
    thickness = 1,          -- lines, 1..8 physical pixels
    outline = true,         -- a 1px black edge along each line (and the dot), so a thin line reads on any ground
    -- always | target | combat | targetOrCombat
    mode = "target",
    length = "full",        -- full | short (200px arms) | none (frame only)
    follow = "target",      -- target | soft | center
    gap = 2,                -- air between the plate edge and the lines
    -- the reticle frame around the plate
    frame = "none",         -- none | box | corners | ring | oval | dots | ticks
    framePad = 4,           -- air between the plate edge and the frame
    frameThickness = 2,     -- 1..8 physical pixels
    frameOwnColor = false,  -- false: the frame takes the lines' colour
    frameColor = { 1, 1, 1 },
    centerDot = false,
    centerDotSize = 4,
    -- colour by melee range
    rangeColor = false,
    inColor = { 0.3, 1, 0.35 },
    outColor = { 1, 0.2, 0.2 },
    -- you are in front of the followed unit: it parried or blocked one of
    -- your attacks, or swung at you in melee
    posWarn = false,
    frontColor = { 1, 0.25, 1 },
    -- units treated differently, by lower-cased name: "warn" | "hide"
    skip = {},
}

Core.MODES   = { always = true, target = true, combat = true, targetOrCombat = true }
Core.LENGTHS = { full = true, short = true, none = true }
Core.FOLLOWS = { target = true, soft = true, center = true }
Core.FRAMES  = { none = true, box = true, corners = true, ring = true, oval = true, dots = true, ticks = true }

-- a parry or block proves you were in front at that instant; you stay
-- there until you move, so the warning holds a while after one
local PARRY_HOLD = 3.0
local OLD_FRONT = { 1, 0.15, 0.15 }

-- fills missing keys only
local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
Core.CopyDefaults = CopyDefaults

-- Brings a settings table up to date: defaults, the old red in-front
-- colour, retired keys, bad enum values.
function Core.Normalize(c)
    CopyDefaults(Core.DEFAULTS, c)
    if not c._front2 then
        c._front2 = true
        local f = c.frontColor
        if type(f) == "table" and f[1] == OLD_FRONT[1] and f[2] == OLD_FRONT[2] and f[3] == OLD_FRONT[3] then
            c.frontColor = { Core.DEFAULTS.frontColor[1], Core.DEFAULTS.frontColor[2], Core.DEFAULTS.frontColor[3] }
        end
    end
    if not c._front3 then
        c._front3 = true
        c.frontBlink = nil
        c.frontOnMe = nil
    end
    -- parries and blocks are the only tell now, so their switch went
    c.frontParry = nil
    if type(c.skip) ~= "table" then c.skip = {} end
    if not Core.MODES[c.mode] then c.mode = Core.DEFAULTS.mode end
    if not Core.LENGTHS[c.length] then c.length = Core.DEFAULTS.length end
    if not Core.FOLLOWS[c.follow] then c.follow = Core.DEFAULTS.follow end
    if not Core.FRAMES[c.frame] then c.frame = Core.DEFAULTS.frame end
    return c
end

-- ============================================================
-- host = {
--   name = "ZacUICrosshair",           -- global frame name
--   DB = function() return settings end,   (already normalized)
--   Print = function(msg) end,
--   FLAT = "Interface\\Buttons\\WHITE8X8",
--   IsEditMode = function() return bool end | nil,
--   WatchEditMode = function(fn) end | nil,
--   PlateInfo = function(plate) return bar, l, r, t, b end | nil
--       -- the plate's health bar and how far its extras reach past it
--       -- (left, right, top, bottom, in the bar's own units); nil to
--       -- use the Blizzard / Plater fallback
--   Misses = ZacUI's ns.Misses | nil
--       -- a shared dodge/parry/block feed; without one (the standalone
--       -- addon) the crosshair reads the combat log itself
--   CLEU = ZacUI's ns.CLEU | nil
--       -- a shared combat-log reader (for the followed unit's swings at
--       -- you); without one the crosshair reads the combat log itself
-- }
-- ============================================================
function Core.New(host)
    local CH = {}
    local FLAT = host.FLAT or "Interface\\Buttons\\WHITE8X8"
    -- the "arrows" reticle's arrowhead: the host's chevron art (a smooth,
    -- anti-aliased ">" pointing RIGHT, with its own soft edge), turned to
    -- face the plate from each side; without one, two bars at 45 degrees
    -- make each head
    local ARROW = host.ARROW
    local Print = host.Print or print
    local DB = host.DB
    local DEFAULTS = Core.DEFAULTS
    CH.DB = DB

    -- --------------------------------------------------------
    -- frames
    -- --------------------------------------------------------
    local root, boxH, boxV, boxF, segT, segB, segL, segR, dot
    local outT, outB, outL, outR, outDot     -- the dark edges behind them
    local farT, farB, farL, farR             -- a fainter pixel past those
    local framePool = {}        -- textures on boxF, reused
    local attached              -- plate the boxes are on (nil = none / centre)
    local hooked = setmetatable({}, { __mode = "k" })
    local queued = false
    local frameW, frameH = 0, 0 -- boxF's last known size (its own units)
    local lineAt                -- { bar, l, r, t, b } the lines stop at, in the boxes' units

    local function Box()
        local f = CreateFrame("Frame", nil, UIParent)
        if f.SetIgnoreParentScale then f:SetIgnoreParentScale(true) end
        if f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end
        f:SetFrameStrata("BACKGROUND")
        f:EnableMouse(false)
        f:SetSize(1, 1)
        f:Hide()
        return f
    end

    local LayoutFrame   -- forward: boxF's OnSizeChanged calls it
    local AnchorLines   -- forward: so does this (a ring reaches past the box)

    local function Build()
        if root then return end
        root = CreateFrame("Frame", host.name or "ZacCrosshair", UIParent)
        if root.SetIgnoreParentScale then root:SetIgnoreParentScale(true) end
        if root.SetIgnoreParentAlpha then root:SetIgnoreParentAlpha(true) end
        root:SetFrameStrata("BACKGROUND")
        root:EnableMouse(false)
        root:SetSize(1, 1)
        root:Hide()
        boxH, boxV, boxF = Box(), Box(), Box()
        local function Line(box)
            local t = box:CreateTexture(nil, "BACKGROUND")
            t._zui_own = true
            t:SetTexture(FLAT)
            return t
        end
        -- the outline: a soft dark shadow, not a black frame - a strip
        -- under each line one pixel wider on every side, and a fainter
        -- one a pixel wider again (anchored in Style, where the pixel
        -- size is known)
        local function Edge(box, sub)
            local t = box:CreateTexture(nil, "BACKGROUND", nil, sub or -1)
            t._zui_own = true
            t:SetTexture(FLAT)
            t:SetVertexColor(0, 0, 0, 1)
            t:Hide()
            return t
        end
        segT, segB = Line(boxV), Line(boxV)
        segL, segR = Line(boxH), Line(boxH)
        outT, outB = Edge(boxV), Edge(boxV)
        outL, outR = Edge(boxH), Edge(boxH)
        farT, farB = Edge(boxV, -2), Edge(boxV, -2)
        farL, farR = Edge(boxH, -2), Edge(boxH, -2)
        segT:SetPoint("BOTTOM", boxV, "TOP", 0, 0)
        segB:SetPoint("TOP", boxV, "BOTTOM", 0, 0)
        segL:SetPoint("RIGHT", boxH, "LEFT", 0, 0)
        segR:SetPoint("LEFT", boxH, "RIGHT", 0, 0)
        dot = Line(boxF)
        dot:SetPoint("CENTER", boxF, "CENTER", 0, 0)
        dot:Hide()
        outDot = Edge(boxF)
        outDot:SetPoint("CENTER", boxF, "CENTER", 0, 0)
        boxF:SetScript("OnSizeChanged", function(_, w, h)
            frameW, frameH = w or 0, h or 0
            local c = DB()
            if c then LayoutFrame(c); AnchorLines(c) end
        end)
    end

    local function SetUp(on)
        if on then root:Show(); boxH:Show(); boxV:Show(); boxF:Show()
        else root:Hide(); boxH:Hide(); boxV:Hide(); boxF:Hide() end
    end

    -- screen pixels -> root units
    local function Px(n)
        local f = (PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor()) or 1
        local s = root:GetEffectiveScale()
        if not s or s <= 0 then s = 1 end
        return n * f / s
    end

    local function Scale(frame)
        local ok, v = pcall(frame.GetEffectiveScale, frame)
        if ok and v and v > 0 then return v end
        return nil
    end

    local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, math.floor((v or lo) + 0.5))) end

    -- a texture from the pool, shown
    local used = 0
    local function Tex(art)
        used = used + 1
        local t = framePool[used]
        if not t then
            t = boxF:CreateTexture(nil, "BACKGROUND")
            t._zui_own = true
            framePool[used] = t
        end
        local want = art or FLAT
        if t._art ~= want then
            t._art = want
            t:SetTexture(want)
            if t.SetBlendMode then t:SetBlendMode("BLEND") end
        end
        t:ClearAllPoints()
        if t.SetRotation then t:SetRotation(0) end
        t:Show()
        return t
    end
    local function ReleaseRest()
        for i = used + 1, #framePool do framePool[i]:Hide() end
    end

    local painted            -- colour table last painted
    local paintedFrame       -- colour table last painted on the frame
    local function FrameColor(c, col)
        return c.frameOwnColor and (c.frameColor or DEFAULTS.frameColor) or col
    end

    -- the reticle: everything on boxF, laid out from its size
    LayoutFrame = function(c)
        if not boxF then return end
        used = 0
        local style = c.frame or "none"
        local w, h = frameW, frameH
        local t = Px(Clamp(c.frameThickness or 2, 1, 8))
        if style ~= "none" and w > 0 and h > 0 then
            if style == "box" then
                local e = Tex(); e:SetPoint("TOPLEFT", boxF, "TOPLEFT", 0, 0); e:SetPoint("TOPRIGHT", boxF, "TOPRIGHT", 0, 0); e:SetHeight(t)
                e = Tex(); e:SetPoint("BOTTOMLEFT", boxF, "BOTTOMLEFT", 0, 0); e:SetPoint("BOTTOMRIGHT", boxF, "BOTTOMRIGHT", 0, 0); e:SetHeight(t)
                e = Tex(); e:SetPoint("TOPLEFT", boxF, "TOPLEFT", 0, 0); e:SetPoint("BOTTOMLEFT", boxF, "BOTTOMLEFT", 0, 0); e:SetWidth(t)
                e = Tex(); e:SetPoint("TOPRIGHT", boxF, "TOPRIGHT", 0, 0); e:SetPoint("BOTTOMRIGHT", boxF, "BOTTOMRIGHT", 0, 0); e:SetWidth(t)
            elseif style == "corners" then
                local len = math.max(Px(8), math.min(Px(40), math.min(w, h) * 0.45))
                for _, cnr in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
                    local p, sx, sy = cnr[1], cnr[2], cnr[3]
                    local hz = Tex(); hz:SetSize(len, t); hz:SetPoint(p, boxF, p, 0, 0)
                    local vt = Tex(); vt:SetSize(t, len); vt:SetPoint(p, boxF, p, 0, 0)
                end
            elseif style == "ring" or style == "oval" or style == "dots" then
                local rx, ry
                if style == "ring" then
                    local r = math.max(w, h) / 2
                    rx, ry = r, r
                else
                    rx, ry = w / 2, h / 2
                end
                local n = (style == "dots") and 16 or 72
                -- a segment long enough to meet its neighbours on the
                -- longest arc (the ellipse's wide side)
                local step = (2 * math.pi) / n
                local seg = (style == "dots") and (t * 2) or (math.max(rx, ry) * step * 1.25)
                for i = 0, n - 1 do
                    local a = i * step
                    local x, y = rx * math.cos(a), ry * math.sin(a)
                    local tx = Tex()
                    if style == "dots" then
                        tx:SetSize(seg, seg)
                    else
                        tx:SetSize(seg, t)
                        -- tangent of the ellipse at this point
                        if tx.SetRotation then tx:SetRotation(math.atan2(ry * math.cos(a), -rx * math.sin(a))) end
                    end
                    tx:SetPoint("CENTER", boxF, "CENTER", x, y)
                end
            elseif style == "ticks" then
                local len = Px(10)
                local e = Tex(); e:SetSize(t, len); e:SetPoint("BOTTOM", boxF, "TOP", 0, 0)
                e = Tex(); e:SetSize(t, len); e:SetPoint("TOP", boxF, "BOTTOM", 0, 0)
                e = Tex(); e:SetSize(len, t); e:SetPoint("RIGHT", boxF, "LEFT", 0, 0)
                e = Tex(); e:SetSize(len, t); e:SetPoint("LEFT", boxF, "RIGHT", 0, 0)
            elseif style == "arrows" then
                -- four arrowheads pointing in at the plate: above, below,
                -- left, right. Sized from the frame thickness so the slider
                -- still means "bolder"; solid art when the host has it,
                -- else two bars at 45 degrees make each head.
                local len = math.max(Px(14), t * 7)
                if ARROW then
                    -- the art points RIGHT; turned to face the plate. Its
                    -- tip sits on the frame edge (where the lines end), so
                    -- a line runs in, becomes an arrowhead, and the plate
                    -- sits inside the four tips
                    local heads = { { "BOTTOM", "TOP", -math.pi / 2 }, { "TOP", "BOTTOM", math.pi / 2 },
                        { "RIGHT", "LEFT", 0 }, { "LEFT", "RIGHT", math.pi } }
                    for _, hd in ipairs(heads) do
                        local a = Tex(ARROW)
                        a:SetSize(len, len)
                        a:SetPoint(hd[1], boxF, hd[2], 0, 0)
                        if a.SetBlendMode then a:SetBlendMode("ADD") end
                        if a.SetRotation then a:SetRotation(hd[3]) end
                    end
                else
                    local arm = len * 0.85
                    local d = arm * 0.3536            -- a bar's centre, off the apex, at 45 degrees
                    -- apex on the plate's edge; two bars lean away from it
                    local function Head(relPoint, ax, ay)
                        for _, side in ipairs({ -1, 1 }) do
                            local b = Tex()
                            b:SetSize(arm, t)
                            local ang = (ax ~= 0) and (side * math.pi / 4) or (side * math.pi / 4 + math.pi / 2)
                            if b.SetRotation then b:SetRotation(ang) end
                            b:SetPoint("CENTER", boxF, relPoint,
                                -ax * d + ((ay ~= 0) and side * d or 0),
                                -ay * d + ((ax ~= 0) and side * d or 0))
                        end
                    end
                    Head("TOP", 0, -1)
                    Head("BOTTOM", 0, 1)
                    Head("LEFT", 1, 0)
                    Head("RIGHT", -1, 0)
                end
            end
        end
        ReleaseRest()
        if c.centerDot then
            local d = Px(Clamp(c.centerDotSize or 4, 2, 16))
            dot:SetSize(d, d)
            dot:Show()
            outDot:SetSize(d + 2 * Px(1), d + 2 * Px(1))
            outDot:SetShown(c.outline ~= false)
        else
            dot:Hide()
            outDot:Hide()
        end
        -- new textures take the current colour
        paintedFrame = nil
        if painted then
            local fc = FrameColor(c, painted)
            local a = c.alpha or DEFAULTS.alpha
            for i = 1, used do framePool[i]:SetVertexColor(fc[1], fc[2], fc[3], a) end
            dot:SetVertexColor(fc[1], fc[2], fc[3], a)
            paintedFrame = fc
        end
    end

    local function Style(c)
        Build()
        local t = Px(Clamp(c.thickness or 1, 1, 8))
        local mode = c.length or "full"
        local len = (mode == "short") and Px(ARM) or LINE_LEN
        segT:SetSize(t, len); segB:SetSize(t, len)
        segL:SetSize(len, t); segR:SetSize(len, t)
        for _, x in ipairs({ segT, segB, segL, segR }) do x:SetShown(mode ~= "none") end
        -- the black edge: a pixel out on both sides and past the inner end
        local on = c.outline ~= false and mode ~= "none"
        local p1 = Px(1)
        local ow, ol = t + 2 * p1, len + p1
        outT:ClearAllPoints() outT:SetPoint("BOTTOM", boxV, "TOP", 0, -p1) outT:SetSize(ow, ol)
        outB:ClearAllPoints() outB:SetPoint("TOP", boxV, "BOTTOM", 0, p1) outB:SetSize(ow, ol)
        outL:ClearAllPoints() outL:SetPoint("RIGHT", boxH, "LEFT", p1, 0) outL:SetSize(ol, ow)
        outR:ClearAllPoints() outR:SetPoint("LEFT", boxH, "RIGHT", -p1, 0) outR:SetSize(ol, ow)
        for _, x in ipairs({ outT, outB, outL, outR }) do x:SetShown(on) end
        local p2 = 2 * p1
        local fw, fl = t + 2 * p2, len + p2
        farT:ClearAllPoints() farT:SetPoint("BOTTOM", boxV, "TOP", 0, -p2) farT:SetSize(fw, fl)
        farB:ClearAllPoints() farB:SetPoint("TOP", boxV, "BOTTOM", 0, p2) farB:SetSize(fw, fl)
        farL:ClearAllPoints() farL:SetPoint("RIGHT", boxH, "LEFT", p2, 0) farL:SetSize(fl, fw)
        farR:ClearAllPoints() farR:SetPoint("LEFT", boxH, "RIGHT", -p2, 0) farR:SetSize(fl, fw)
        for _, x in ipairs({ farT, farB, farL, farR }) do x:SetShown(on) end
        LayoutFrame(c)
        -- the edges share the lines' see-through-ness
        local a = c.alpha or DEFAULTS.alpha
        -- a shadow that follows the lines' see-through-ness: dark enough
        -- to lift a thin line off snow or fire, light enough that it
        -- never reads as a black border
        for _, x in ipairs({ outT, outB, outL, outR, outDot }) do x:SetVertexColor(0, 0, 0, math.min(1, a * 0.5)) end
        for _, x in ipairs({ farT, farB, farL, farR }) do x:SetVertexColor(0, 0, 0, math.min(1, a * 0.2)) end
    end

    -- --------------------------------------------------------
    -- range colour (5-yard item, action bar, then the strikes by name)
    -- --------------------------------------------------------
    local MELEE_SPELLS = {
        WARRIOR = { 78, 1715, 772 },
        ROGUE   = { 1752, 1776, 53 },
        HUNTER  = { 2973, 2974 },
        DRUID   = { 6807, 1082 },
        PALADIN = { 20271 },
        SHAMAN  = { 17364, 8042 },
    }
    local ATTACK = 6603
    local followUnit
    local meleeNames
    local SpellInRange = IsSpellInRange or (C_Spell and C_Spell.IsSpellInRange)

    local function MeleeNames()
        if meleeNames then return meleeNames end
        meleeNames = {}
        local _, cls = UnitClass("player")
        local ids = {}
        local list = cls and MELEE_SPELLS[cls]
        if list then
            for _, id in ipairs(list) do ids[#ids + 1] = id end
        else
            ids[#ids + 1] = ATTACK
        end
        for _, id in ipairs(ids) do
            local n = GetSpellInfo(id)
            if n then meleeNames[#meleeNames + 1] = n end
        end
        return meleeNames
    end

    local function Ask(name, unit)
        local ok, r = pcall(SpellInRange, name, unit)
        if not ok then return nil end
        if r == 1 or r == true then return true end
        if r == 0 or r == false then return false end
        return nil
    end

    local meleeSlot
    local slotDirty = true

    local function IsMeleeName(n)
        if not n then return false end
        for _, m in ipairs(MeleeNames()) do
            if m == n then return true end
        end
        return false
    end

    local function FindMeleeSlot()
        slotDirty = false
        meleeSlot = nil
        if not GetActionInfo then return end
        for slot = 1, 120 do
            local kind, id = GetActionInfo(slot)
            local name
            if kind == "spell" and id then
                name = GetSpellInfo(id)
            elseif kind == "macro" and id and GetMacroSpell then
                local sid = GetMacroSpell(id)
                if sid then name = GetSpellInfo(sid) end
            end
            if IsMeleeName(name) then meleeSlot = slot return end
        end
    end

    local function AskBar()
        if slotDirty then FindMeleeSlot() end
        if not meleeSlot or not IsActionInRange then return nil end
        local ok, r = pcall(IsActionInRange, meleeSlot)
        if not ok then return nil end
        if r == 1 or r == true then return true end
        if r == 0 or r == false then return false end
        return nil
    end

    local MELEE_ITEMS = { 8149, 15826, 16308, 17117, 22259, 22432 }
    local ItemInRange = (C_Item and C_Item.IsItemInRange) or IsItemInRange
    local meleeItem
    local itemsRequested = false

    local function ItemCached(id)
        if C_Item and C_Item.IsItemDataCachedByID then
            return C_Item.IsItemDataCachedByID(id) and GetItemInfo(id) ~= nil
        end
        return GetItemInfo(id) ~= nil
    end

    local function MeleeItem()
        if meleeItem then return meleeItem end
        for _, id in ipairs(MELEE_ITEMS) do
            if ItemCached(id) then meleeItem = id return id end
        end
        if not itemsRequested then
            itemsRequested = true
            for _, id in ipairs(MELEE_ITEMS) do
                if C_Item and C_Item.RequestLoadItemDataByID then
                    pcall(C_Item.RequestLoadItemDataByID, id)
                else
                    GetItemInfo(id)
                end
            end
        end
        return nil
    end

    local function AskItem(unit)
        if not ItemInRange then return nil end
        local id = MeleeItem()
        if not id then return nil end
        local ok, r = pcall(ItemInRange, id, unit)
        if not ok then return nil end
        if r == 1 or r == true then return true end
        if r == 0 or r == false then return false end
        return nil
    end

    local function InMelee(unit)
        if not UnitExists(unit) then return nil end
        if not UnitCanAttack("player", unit) or UnitIsDead(unit) then return nil end
        local ir = AskItem(unit)
        if ir ~= nil then return ir end
        if UnitIsUnit(unit, "target") then
            local r = AskBar()
            if r ~= nil then return r end
        end
        if not SpellInRange then return nil end
        for _, n in ipairs(MeleeNames()) do
            local r = Ask(n, unit)
            if r ~= nil then return r end
        end
        return nil
    end

    function CH.RangeReport()
        local unit = "target"
        if not UnitExists(unit) then Print("crosshair range: no target.") return end
        Print(string.format("crosshair range: api %s, attackable %s, following %s, painted %s",
            IsSpellInRange and "IsSpellInRange" or (C_Spell and C_Spell.IsSpellInRange) and "C_Spell" or "none",
            tostring(UnitCanAttack("player", unit)), tostring(followUnit),
            painted and string.format("%.2f %.2f %.2f", painted[1], painted[2], painted[3]) or "-"))
        local id = MeleeItem()
        if id and ItemInRange then
            local ok, r = pcall(ItemInRange, id, unit)
            Print(string.format("  5yd item %d -> %s", id, ok and tostring(r) or "error"))
        else
            Print("  5yd item: none cached yet (asked the client for them)")
        end
        if slotDirty then FindMeleeSlot() end
        if meleeSlot then
            local ok, r = pcall(IsActionInRange, meleeSlot)
            Print(string.format("  action bar slot %d -> %s", meleeSlot, ok and tostring(r) or "error"))
        else
            Print("  action bar: no melee strike found on your bars")
        end
        for _, n in ipairs(MeleeNames()) do
            local ok, r = pcall(SpellInRange or function() end, n, unit)
            Print(string.format("  %s -> %s", n, ok and tostring(r) or "error"))
        end
        local m = InMelee(unit)
        if not UnitCanAttack("player", unit) then Print("  (target is not attackable - plain colour)") end
        Print("crosshair range: " .. (m == true and "IN melee" or m == false and "OUT of melee" or "unknown (plain colour)"))
    end

    local rangeTicker

    local function Paint(c, col)
        local a = c.alpha or DEFAULTS.alpha
        if painted ~= col then
            painted = col
            for _, x in ipairs({ segT, segB, segL, segR }) do
                x:SetVertexColor(col[1], col[2], col[3], a)
            end
            -- the host may colour other things to match (the plate arrows)
            if host.OnColor then host.OnColor(col) end
        end
        local fc = FrameColor(c, col)
        if paintedFrame ~= fc then
            paintedFrame = fc
            for i = 1, used do framePool[i]:SetVertexColor(fc[1], fc[2], fc[3], a) end
            dot:SetVertexColor(fc[1], fc[2], fc[3], a)
        end
    end

    local lastParry = 0
    local followGUID
    local skipWarn = false

    -- IN FRONT = ONE OF YOUR OWN ATTACKS WAS PARRIED OR BLOCKED. A mob can
    -- only parry or block from the front, so that is the first tell (Zac,
    -- 2026-10-25: "it should only happen when im actually hitting a mob
    -- from the front"). The combat log names who swung: only misses whose
    -- source is you and whose target is the followed unit count, auto-
    -- attacks included. The old tells went: "the unit targets you" fired
    -- from behind whenever a mob aimed a spell at you without turning,
    -- and a parry of anyone's attack within 0.06s of your strike caught
    -- the tank's. Listens only while the warning is armed.
    --
    -- The second tell (Zac, 2026-10-25: "detect that im hitting a mob from
    -- the front by actually getting hit by the mob"): the followed unit's
    -- own melee swing landing on you, hit or miss. A mob turns to face the
    -- one it swings at, so its swing at you means you stand in its front -
    -- the side its parries come from. Melee only: a spell or an area hit
    -- (a breath, a tail swipe, an explosion) says nothing about facing.
    local MISS_KEY = "Crosshair.front"
    local SWING_KEY = "Crosshair.swungAt"
    local playerGUID
    local function NoteSwing(src, dst)
        if src and src == followGUID and dst == playerGUID then lastParry = GetTime() end
    end
    local function NoteMiss(kind, dst, sub)
        if not dst or dst ~= followGUID then return end
        -- real misses only: a partial block rides a HIT line, and the old
        -- rule (and the "in front" meaning) never counted those
        if sub ~= "SWING_MISSED" and sub ~= "SPELL_MISSED" then return end
        if kind == "PARRY" or kind == "BLOCK" then lastParry = GetTime() end
    end
    local tells                 -- own combat-log frame, standalone only
    local cleuOn = false
    -- COST. A mob only swings at the unit it targets, so the swing tell
    -- listens only while the followed unit's target is you - for a DPS
    -- that is almost never, so the raid's melee swings cost nothing here.
    -- UNIT_TARGET (and the 0.2s range tick, as a net) re-checks it.
    local swingOn = false
    local function SyncSwing()
        local want = cleuOn and followUnit and UnitIsUnit(followUnit .. "target", "player") and true or false
        if want == swingOn then return end
        swingOn = want
        local bus = host.CLEU
        if not bus then return end    -- the own frame reads swingOn
        if want then
            bus.On(SWING_KEY, { "SWING_DAMAGE", "SWING_MISSED" }, function(_, _, _, src, _, _, _, dst)
                NoteSwing(src, dst)
            end)
        else
            bus.Off(SWING_KEY)
        end
    end
    CH.SyncSwing = SyncSwing
    local function WatchParries(on)
        if on == cleuOn then SyncSwing() return end
        cleuOn = on
        if on then playerGUID = UnitGUID("player") end
        local M, bus = host.Misses, host.CLEU
        SyncSwing()
        if M then
            if on then
                M.Want(MISS_KEY, true)
                M.On(MISS_KEY, function(kind, dst, _, sub) NoteMiss(kind, dst, sub) end)
            else
                M.On(MISS_KEY, nil)
                M.Want(MISS_KEY, false)
            end
        end
        if M and bus then return end
        -- an own combat-log frame for whatever the host did not supply
        if not tells then
            local CLEU = CombatLogGetCurrentEventInfo
            tells = CreateFrame("Frame")
            tells:SetScript("OnEvent", function()
                local _, sub, _, src, _, _, _, dst = CLEU()
                if src == playerGUID then
                    if host.Misses then return end
                    local miss
                    if sub == "SWING_MISSED" then miss = select(12, CLEU())
                    elseif sub == "SPELL_MISSED" then miss = select(15, CLEU()) end
                    if miss then NoteMiss(miss, dst, sub) end
                elseif swingOn and not host.CLEU and (sub == "SWING_DAMAGE" or sub == "SWING_MISSED") then
                    NoteSwing(src, dst)
                end
            end)
        end
        if _G.ZACUI_IS_FOREVER then return end   -- (no combat log on WoW Forever)
        if on then
            tells:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        else
            tells:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end
    end

    local function SkipMode(c, unit)
        if not unit or not next(c.skip) then return nil end
        local name = UnitName(unit)
        return name and c.skip[name:lower()] or nil
    end
    CH.SkipMode = SkipMode

    local function PaintNow(c)
        local col = c.color or DEFAULTS.color
        if c.rangeColor and followUnit then
            local r = InMelee(followUnit)
            if r == true then col = c.inColor or DEFAULTS.inColor
            elseif r == false then col = c.outColor or DEFAULTS.outColor end
        end
        if c.posWarn and followUnit and not skipWarn and GetTime() - lastParry < PARRY_HOLD then
            col = c.frontColor or DEFAULTS.frontColor
        end
        Paint(c, col)
    end

    local function StopRange()
        if rangeTicker then rangeTicker:Cancel(); rangeTicker = nil end
        WatchParries(false)
    end

    local function StartRange()
        local c = DB()
        WatchParries(c and c.posWarn and not skipWarn and followUnit
            and UnitCanAttack("player", followUnit) and true or false)
        if rangeTicker then return end
        rangeTicker = C_Timer.NewTicker(0.2, function()
            local c = DB()
            if not c or not (c.rangeColor or c.posWarn) or not followUnit or not (root and root:IsShown()) then
                StopRange()
                return
            end
            SyncSwing()
            PaintNow(c)
        end)
    end

    -- --------------------------------------------------------
    -- following the plate
    -- --------------------------------------------------------
    local function FollowTarget(c)
        local f = c.follow or "target"
        if f == "center" or not C_NamePlate then return nil end
        local plate
        -- enemies only: a friendly's plate (often just a name) gets no lines
        if UnitExists("target") and not UnitIsUnit("target", "player") and not UnitIsDead("target")
            and UnitCanAttack("player", "target") then
            plate = C_NamePlate.GetNamePlateForUnit("target")
            if plate then followUnit = "target" end
        end
        if not plate and f == "soft" and UnitExists("softenemy") then
            plate = C_NamePlate.GetNamePlateForUnit("softenemy")
            if plate then followUnit = "softenemy" end
        end
        return plate
    end

    -- The health bar to anchor to, plus how far the plate's visible extras
    -- reach past it (in the bar's own units). The host knows its own
    -- plates; Plater and Blizzard are read here.
    -- How far a visible region reaches past the bar's top or bottom, in
    -- the bar's own units (0 when it sits inside the bar, is hidden or
    -- is see-through). Read once per attach, never per frame: a name
    -- drawn INSIDE the bar (Plater's default) adds nothing, and a cast
    -- bar that is "shown" at zero alpha is not counted.
    local function Reach(bar, reg, side)
        if type(reg) ~= "table" or type(reg.IsVisible) ~= "function" or not reg:IsVisible() then return 0 end
        if reg.GetAlpha and (reg:GetAlpha() or 1) <= 0.01 then return 0 end
        if reg.GetText and (reg:GetText() or "") == "" then return 0 end
        local bs, rs = Scale(bar) or 1, Scale(reg) or 1
        local ok1, rv, ok2, bv
        if side == "top" then
            ok1, rv = pcall(reg.GetTop, reg); ok2, bv = pcall(bar.GetTop, bar)
            if ok1 and ok2 and rv and bv then return math.max(0, (rv * rs - bv * bs) / bs) end
        else
            ok1, rv = pcall(reg.GetBottom, reg); ok2, bv = pcall(bar.GetBottom, bar)
            if ok1 and ok2 and rv and bv then return math.max(0, (bv * bs - rv * rs) / bs) end
        end
        return 0
    end

    local function MostReach(bar, side, ...)
        local m = 0
        for i = 1, select("#", ...) do
            local v = Reach(bar, (select(i, ...)), side)
            if v > m then m = v end
        end
        return m
    end

    local function BarAndExtras(plate)
        if host.PlateInfo then
            local bar, l, r, t, b = host.PlateInfo(plate)
            if bar then return bar, l or 0, r or 0, t or 0, b or 0 end
        end
        local uf = plate.unitFrame     -- Plater
        local bar = uf and uf.healthBar
        if bar and bar:IsVisible() then
            local t = MostReach(bar, "top", uf.unitName, bar.unitName, uf.ActorNameSpecial, uf.ActorTitleSpecial)
            local b = MostReach(bar, "bottom", uf.castBar, uf.powerBar)
            return bar, 0, 0, t > 0 and (t + 2) or 0, b > 0 and (b + 2) or 0
        end
        uf = plate.UnitFrame           -- Blizzard
        bar = uf and uf.healthBar
        if bar and bar:IsVisible() then
            local t = MostReach(bar, "top", uf.name)
            local b = MostReach(bar, "bottom", uf.castBar or uf.CastBar)
            return bar, 0, 0, t > 0 and (t + 2) or 0, b > 0 and (b + 2) or 0
        end
        return nil
    end

    local function OnPlateShow(plate)
        if plate == attached and root then
            SetUp(true)
            local c = DB()
            if c and c.rangeColor and followUnit then StartRange() end
        end
    end
    local function OnPlateHide(plate) if plate == attached and root then SetUp(false) end end

    local function Detach()
        attached = nil
        lineAt = nil
        if root then SetUp(false); boxH:ClearAllPoints(); boxV:ClearAllPoints(); boxF:ClearAllPoints() end
    end

    -- What the lines stop at: the bar and its extras plus the gap - or,
    -- with a reticle frame up, the OUTSIDE of that frame plus the gap, so
    -- no line ever runs on through the frame to the plate (a ring is
    -- wider than its box on the short side; that comes from boxF's size).
    AnchorLines = function(c)
        if not (lineAt and boxH) then return end
        local gap = Px(Clamp(c.gap or 2, 0, 60))
        local gh, gv = gap, gap
        if (c.frame or "none") ~= "none" then
            local pad = Px(Clamp(c.framePad or 4, 0, 60))
            gh, gv = gap + pad, gap + pad
            if c.frame == "ring" and frameW > 0 and frameH > 0 then
                local rr = math.max(frameW, frameH) / 2
                gh = gh + math.max(0, rr - frameW / 2)
                gv = gv + math.max(0, rr - frameH / 2)
            end
        end
        local bar, l, r, t, b = lineAt[1], lineAt[2], lineAt[3], lineAt[4], lineAt[5]
        boxH:ClearAllPoints(); boxV:ClearAllPoints()
        boxH:SetPoint("TOPLEFT", bar, "TOPLEFT", -(gh + l), 0)
        boxH:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", gh + r, 0)
        boxV:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, gv + t)
        boxV:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -(gv + b))
    end

    local lineBuf = {}          -- lineAt's table, reused
    -- remeasure: true = leave everything where it is when nothing moved
    local function Attach(c, plate, remeasure)
        local pad = Px(Clamp(c.framePad or 4, 0, 60))
        local bar, l, r, t, b = BarAndExtras(plate)
        if bar then
            local k = (Scale(bar) or 1) / (boxH:GetEffectiveScale() or 1)
            l, r, t, b = l * k, r * k, t * k, b * k
            if remeasure and lineAt and attached == plate and lineAt[1] == bar and lineAt[2] == l
                and lineAt[3] == r and lineAt[4] == t and lineAt[5] == b and lineAt[6] == pad then
                return
            end
            boxH:ClearAllPoints(); boxV:ClearAllPoints(); boxF:ClearAllPoints()
            lineBuf[1], lineBuf[2], lineBuf[3], lineBuf[4], lineBuf[5], lineBuf[6] = bar, l, r, t, b, pad
            lineAt = lineBuf
            AnchorLines(c)
            boxF:SetPoint("TOPLEFT", bar, "TOPLEFT", -(pad + l), pad + t)
            boxF:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", pad + r, -(pad + b))
        else
            boxH:ClearAllPoints(); boxV:ClearAllPoints(); boxF:ClearAllPoints()
            lineAt = nil
            boxH:SetAllPoints(plate)
            boxV:SetAllPoints(plate)
            boxF:SetAllPoints(plate)
        end
        attached = plate
        if not hooked[plate] then
            hooked[plate] = true
            plate:HookScript("OnShow", OnPlateShow)
            plate:HookScript("OnHide", OnPlateHide)
        end
    end

    local function AttachCentre(c)
        lineAt = nil
        local g = Px(GAP)
        local p = Px(Clamp(c.framePad or 4, 0, 60))
        -- with a frame up the lines start outside it, as on a plate
        local lg = ((c.frame or "none") ~= "none") and (g + 2 * p) or g
        for _, f in ipairs({ boxH, boxV }) do
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            f:SetSize(lg, lg)
        end
        boxF:ClearAllPoints()
        boxF:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        boxF:SetSize(g + 2 * p, g + 2 * p)
        attached = nil
    end

    -- --------------------------------------------------------
    -- show / hide
    -- --------------------------------------------------------
    local function WantShown(c)
        if not c.enabled then return false end
        if host.IsEditMode and host.IsEditMode() then return true end
        local mode = c.mode
        if mode == "always" then return true end
        local hasTarget = UnitExists("target") and (UnitCanAttack("player", "target") or not UnitIsFriend("player", "target"))
        if mode == "target" then return hasTarget and true or false end
        local fighting = UnitAffectingCombat("player") and true or false
        if mode == "combat" then return fighting end
        return (hasTarget or fighting) and true or false
    end

    local restyleNext = true
    local function Refresh()
        queued = false
        local c = DB()
        if not c then return end
        Build()
        if restyleNext then restyleNext = false; painted = nil; paintedFrame = nil; Style(c) end
        followUnit = nil
        if not c.enabled or not WantShown(c) then Detach(); StopRange() return end
        if (c.follow or "target") == "center" then
            AttachCentre(c)
            if UnitExists("target") and not UnitIsDead("target") then followUnit = "target" end
            SetUp(true)
        else
            local plate = FollowTarget(c)
            if not plate then followUnit = nil; Detach(); StopRange() return end
            Attach(c, plate)
            SetUp(plate:IsVisible() and true or false)
        end
        local guid = followUnit and UnitGUID(followUnit) or nil
        if guid ~= followGUID then followGUID = guid; lastParry = 0 end
        local skip = SkipMode(c, followUnit)
        if skip == "hide" then
            followUnit = nil; followGUID = nil
            Detach(); StopRange()
            return
        end
        skipWarn = (skip == "warn")
        PaintNow(c)
        if (c.rangeColor or (c.posWarn and not skipWarn)) and followUnit then StartRange() else StopRange() end
    end

    local function Queue(restyle)
        if restyle then restyleNext = true end
        if queued then return end
        queued = true
        C_Timer.After(0, Refresh)
    end

    function CH.Refresh() Queue(true) end
    -- The plate's extras changed under the lines (an icon row came or
    -- went, a cast started): read the reach again and re-anchor the
    -- lines and frame - a handful of SetPoints, nothing rebuilt. The
    -- hosts call it from the moments that change what is visible.
    function CH.Remeasure()
        if not (attached and root and root:IsShown()) then return end
        local c = DB()
        if not c then return end
        Attach(c, attached, true)
    end
    -- is the crosshair following this plate right now? (hosts ask before
    -- calling Remeasure for a change on one plate)
    function CH.IsOn(plate)
        return plate ~= nil and plate == attached and root ~= nil and root:IsShown()
    end
    -- the colour the lines wear right now (range / in-front tints
    -- included), or the plain setting before anything was painted
    function CH.CurrentColor()
        if painted then return painted end
        local c = DB()
        return c and (c.color or DEFAULTS.color) or DEFAULTS.color
    end
    function CH.Enabled()
        local c = DB()
        return c and c.enabled and true or false
    end
    function CH.IsShown() return root ~= nil and root:IsShown() end
    -- for the mock tests: the frames and the reticle texture pool
    function CH._Frames() return root, boxH, boxV, boxF, framePool, used end

    function CH.Toggle()
        local c = DB()
        if not c then Print("crosshair: settings not ready.") return end
        c.enabled = not c.enabled
        restyleNext = true
        Refresh()
        local on = attached and "target plate" or (((c.follow or "target") == "center") and "screen centre" or "nothing")
        Print(string.format("crosshair %s (mode %s, follow %s, lines %s, frame %s, %dpx, alpha %.2f) - %s, on %s",
            c.enabled and "ON" or "OFF", tostring(c.mode), tostring(c.follow), tostring(c.length), tostring(c.frame),
            c.thickness or 1, c.alpha or 0.6, (root and root:IsShown()) and "shown" or "hidden", on))
    end

    -- --------------------------------------------------------
    -- events
    -- --------------------------------------------------------
    local driver = CreateFrame("Frame")
    local lastDead = false      -- the target's dead state at the last pass
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    driver:RegisterEvent("PLAYER_REGEN_ENABLED")
    driver:RegisterEvent("UI_SCALE_CHANGED")
    driver:RegisterEvent("DISPLAY_SIZE_CHANGED")
    driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    pcall(driver.RegisterEvent, driver, "PLAYER_SOFT_ENEMY_CHANGED")
    driver:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    driver:RegisterEvent("SPELLS_CHANGED")
    driver:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_TARGET" then
            -- the followed unit picked a new target: only the swing tell's
            -- listening state can change (a one-call check)
            SyncSwing()
            return
        end
        if event == "ACTIONBAR_SLOT_CHANGED" or event == "SPELLS_CHANGED" then
            slotDirty = true
            if event == "SPELLS_CHANGED" then meleeNames = nil end
            return
        end
        if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
            if not (unit and (UnitIsUnit(unit, "target") or UnitIsUnit(unit, "softenemy"))) then return end
        end
        if event == "UNIT_HEALTH" then
            -- only the target dying (or coming back) changes anything here;
            -- its health moves every frame in a boss fight
            local dead = UnitIsDead("target") and true or false
            if unit ~= "target" or dead == lastDead then return end
            lastDead = dead
        elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            lastDead = UnitIsDead("target") and true or false
        end
        local restyle = event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED"
            or event == "PLAYER_ENTERING_WORLD"
        Queue(restyle)
    end)
    driver:RegisterUnitEvent("UNIT_HEALTH", "target")
    -- a target turning hostile or friendly without a retarget (mind
    -- control, a duel starting) changes whether it should be up; rare
    driver:RegisterUnitEvent("UNIT_FACTION", "target")
    driver:RegisterUnitEvent("UNIT_FLAGS", "target")
    driver:RegisterUnitEvent("UNIT_TARGET", "target", "softenemy")

    if host.WatchEditMode then
        host.WatchEditMode(function() Queue(false) end)
    end

    return CH
end
