-- NP_Health - the health bar, texts and every color decision a plate
-- makes: reaction, class, tap, and the threat palette.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local Col = ns.Col
local NP = ns.Nameplates

local DB = NP.DB
local SetNPFont = NP.SetNPFont

-- ============================================================
-- WHERE EVERY TEXT AND PART SITS
-- ============================================================
-- Each text and part on a plate has its built-in spot - exactly the
-- SetPoint it always had, worked out from the plate's own settings (name
-- inside / above, the marker's place...) - written into a defaults table
-- the plate keeps and reuses, and ZacUI's ApplyAnchor puts it there with
-- the side's saved spec on top (d.enemy.anchors.<key> /
-- d.friendly.anchors.<key>, ZacUI's anchor shape). Nothing saved = the
-- old point, to the pixel. Placement runs on layout only (and when the
-- marker comes or goes, the cast bar shows or hides) - never per frame.
NP.ANCHOR_TEXTS = { "name", "level", "percent", "castText", "threatText", "targetName", "quest" }
NP.ANCHOR_PARTS = { "castbar", "castIcon", "raidMarker", "threatBar", "auras" }
NP.ANCHOR_LABELS = {
    plate = "The plate", health = "Health bar", name = "Name", level = "Level",
    percent = "Health percent", castbar = "Cast bar", castText = "Spell name",
    castIcon = "Cast icon", raidMarker = "Raid marker", threatBar = "Threat bar",
    threatText = "Threat percent", targetName = "Mob's target", quest = "Quest mark",
    auras = "Aura row",
}
NP.ANCHOR_TARGETS = { "plate", "health", "name", "level", "percent", "castbar", "castText", "castIcon",
    "raidMarker", "threatBar", "threatText", "targetName", "quest", "auras" }

-- the region an element key names on one plate (the `to` resolver)
function NP.ElementTarget(f, key)
    if not f then return nil end
    local cb, tb = f.cast, f.threat
    if key == "plate" then return f
    elseif key == "health" then return f.health
    elseif key == "name" then return f.name
    elseif key == "level" then return f.level
    elseif key == "percent" then return f.percent
    elseif key == "castbar" then return cb
    elseif key == "castText" then return cb and cb.spell
    elseif key == "castIcon" then return cb and cb.iconFrame
    elseif key == "raidMarker" then return f.raidIconFrame
    elseif key == "threatBar" then return tb
    elseif key == "threatText" then return tb and tb.text
    elseif key == "targetName" then return f.targetName
    elseif key == "quest" then return f.quest
    elseif key == "auras" then return f.auras end
    return nil
end

-- One element's built-in spot into the plate's reused defaults table.
function NP.SetDef(f, key, p, to, rp, x, y, j, p2, to2, rp2, x2, y2)
    local D = f._npDef
    if not D then D = {} f._npDef = D end
    local t = D[key]
    if not t then t = {} D[key] = t end
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = p, to, rp, x, y, j
    t.point2, t.to2, t.relPoint2, t.x2, t.y2 = p2, to2, rp2, x2, y2
    -- the page's pickers show the effective default of the side last laid out
    local side = f.isFriend and "friendly" or "enemy"
    NP._lastDef = NP._lastDef or {}
    NP._lastDef[side] = D
    return t
end

-- the side's saved spec for one element (nil: none)
function NP.AnchorSpec(f, key)
    local d = DB()
    local cfg = f.isFriend and d.friendly or d.enemy
    local a = cfg and cfg.anchors
    return type(a) == "table" and a[key] or nil
end

-- Put one element where its spec says, on top of its built-in spot
-- (NP.SetDef just before). -> twoPoint
function NP.Place(f, region, key, def)
    if not f._anchorTo then f._anchorTo = function(k) return NP.ElementTarget(f, k) end end
    local _, two = ns.ApplyAnchor(region, NP.AnchorSpec(f, key), def, f._anchorTo)
    return two
end

-- What an element's built-in spot is, for the settings page's pickers:
-- the defaults of the last plate of that side to be laid out (live or a
-- preview sample), else where a fresh plate puts it.
local FALLBACK_DEF = {
    name = { point = "BOTTOM", relPoint = "TOP", x = 0, y = 2, justify = "CENTER" },
    level = { point = "LEFT", relPoint = "LEFT", x = 1, y = 0 },
    percent = { point = "RIGHT", relPoint = "RIGHT", x = -1, y = 0 },
    castText = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
    threatText = { point = "RIGHT", relPoint = "BOTTOMRIGHT", x = -1, y = 0, justify = "RIGHT" },
    targetName = { point = "TOPRIGHT", relPoint = "BOTTOMRIGHT", x = 0, y = -2, justify = "RIGHT" },
    quest = { point = "RIGHT", relPoint = "LEFT", x = -2, y = 0 },
    castbar = { point = "TOP", relPoint = "BOTTOM", x = 0, y = -2 },
    castIcon = { point = "RIGHT", relPoint = "LEFT", x = -2, y = 0 },
    raidMarker = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
    threatBar = { point = "TOPRIGHT", relPoint = "BOTTOMRIGHT", x = 0, y = -2 },
    auras = { point = "BOTTOM", relPoint = "TOP", x = 0, y = 14 },
}
function NP.AnchorDefaults(side, key)
    local D = NP._lastDef and NP._lastDef[side]
    return (D and D[key]) or FALLBACK_DEF[key]
end

-- the simple aura row's stack number on its icon (d.auras.anchors.count)
NP.AURA_COUNT_DEF = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = 1, y = -1 }

-- The health percent's format (cfg.formats.percent, ZacUI's text format
-- shape): what it always read, as a template. Nothing saved = the old
-- integer fast path.
NP.PCT_FORMAT_DEFAULTS = { template = "[pct]%", decimals = 0 }
NP.PCT_FORMAT_KINDS = { cur = "number", max = "number", deficit = "number", pct = "percent" }
NP.PCT_FORMAT_TOKENS = { { token = "pct", label = "Percent" }, { token = "cur", label = "Current" },
    { token = "max", label = "Most" }, { token = "deficit", label = "Missing" } }

-- ============================================================
-- BUILD
-- ============================================================
function NP.BuildHealth(f)
    local hb = CreateFrame("StatusBar", nil, f)
    hb:SetStatusBarTexture(NP.BarTexture("healthTexture"))
    hb:SetMinMaxValues(0, 1)
    f.health = hb

    local bg = hb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local w = Col("windowBg")
    bg:SetColorTexture(w.r, w.g, w.b, 0.85)
    hb.bg = bg
    AddPixelBorder(hb, nil, nil, "nameplates")

    -- mouseover glow, the profile's hover_highlight (additive white)
    local hover = hb:CreateTexture(nil, "OVERLAY", nil, 2)
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 1)
    hover:SetBlendMode("ADD")
    hover:SetAlpha(0)
    hb.hover = hover

    -- THE TARGET MARKS' HOST: the neon strips (below) and the box or
    -- arrows round the bar (NP_Extras) live on this one frame, hung by a
    -- single anchor from the bar's centre at the bar's size (LayoutFrame),
    -- so the target animation (NP_FX) can play them as one piece -
    -- popping from the middle, sliding, flashing - without touching the
    -- bar or anything else on the plate.
    local cue = CreateFrame("Frame", nil, f)
    cue:SetPoint("CENTER", hb, "CENTER", 0, 0)
    cue:SetSize(1, 1)
    cue:SetFrameLevel(hb:GetFrameLevel())
    f.tgtCue = cue

    -- name above the bar, level inside-left, percent inside-right:
    -- where the Naowh profile anchored each of them. Every FontString
    -- gets a font AT BIRTH - one with no font errors on its first
    -- SetText, and layout re-sizing later must never be load-bearing.
    f.name = f:CreateFontString(nil, "OVERLAY")
    SetNPFont(f.name, 10)
    f.name:SetPoint("BOTTOM", hb, "TOP", 0, 2)
    f.name:SetWordWrap(false)

    -- ============================================================
    -- RAID MARKER - A REAL TEXTURE, NOT AN INLINE ESCAPE
    -- ============================================================
    -- This used to ride the name string as |TUI-RaidTargetingIcon_N:0|t.
    -- A :0 inline texture is sized to the FONT, so the skull came out at
    -- roughly ten pixels, jammed against the first letter of the name and
    -- competing with it for the same fixed width - and the name is
    -- SetWordWrap(false) with an explicit width, so a long name could
    -- push on it too. Marks you cannot pick out at a glance are marks you
    -- do not have; calling a target in a raid is the entire job.
    --
    -- Blizzard's own plate icon is not a fallback either: HideBlizzardArt
    -- hides base.UnitFrame outright, which takes its RaidTargetFrame with
    -- it. So this is the only marker on the plate and it has to be seen.
    --
    -- EVERY EDGE OF THIS PLATE IS SPOKEN FOR, so the marker goes INSIDE
    -- the bar, flush left. The survey that settled it:
    --   above centre  - Readycheck's soft-target arrows, 24x24, pinned
    --                   4px over the name and enabled
    --   above +20..58 - Readycheck aura groups (armorextra, overpower,
    --                   execute)
    --   left  x=-78   - Readycheck's taunt icon
    --   right x=+75   - Readycheck's sunder counter, 25pt text, so it
    --                   spreads back to roughly +62 against a bar whose
    --                   right edge is +60
    --   below         - ZacUI's own cast bar and target-name text
    --   INSIDE        - nothing, from either addon
    --
    -- Flush LEFT specifically, because that is the end of the bar that is
    -- filled for as long as the mob is alive. The information in a health
    -- bar lives at its moving right edge; the left end is constant, so an
    -- icon there costs the least and always has coloured bar behind it.
    --
    -- Its own frame, above the health bar AND the cast bar, so nothing
    -- can ever draw over it. A texture on the plate's own OVERLAY layer
    -- loses to both, because both are child frames.
    local rif = CreateFrame("Frame", nil, f)
    rif:SetPoint("CENTER", hb, "CENTER", 0, 0)
    rif:SetSize(1, 1)                  -- anchor only; textures overflow it
    rif:SetFrameLevel(hb:GetFrameLevel() + 10)
    f.raidIconFrame = rif

    -- Dark copy 1px down-right at 60%, so the symbol has an edge against
    -- a full green bar, a red bar and open ground alike. "Never hard to
    -- read" has to survive every background it can land on.
    f.raidIconShadow = rif:CreateTexture(nil, "OVERLAY", nil, 6)
    f.raidIconShadow:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
    f.raidIconShadow:SetVertexColor(0, 0, 0, 0.6)
    f.raidIconShadow:SetPoint("CENTER", rif, "CENTER", 1, -1)
    f.raidIconShadow:Hide()

    f.raidIcon = rif:CreateTexture(nil, "OVERLAY", nil, 7)
    f.raidIcon:SetTexture([[Interface\TargetingFrame\UI-RaidTargetingIcons]])
    f.raidIcon:SetPoint("CENTER", rif, "CENTER", 0, 0)
    f.raidIcon:Hide()

    f.raidIcon:SetSize(24, 24)
    f.raidIconShadow:SetSize(24, 24)

    f.level = hb:CreateFontString(nil, "OVERLAY")
    SetNPFont(f.level, 10)
    f.level:SetPoint("LEFT", hb, "LEFT", 1, 0)

    f.percent = hb:CreateFontString(nil, "OVERLAY")
    SetNPFont(f.percent, 9)
    f.percent:SetPoint("RIGHT", hb, "RIGHT", -1, 0)
end

-- Re-fit sizes, textures and fonts to the current settings; runs on
-- plate assign, on config change and on combat transitions (the profile
-- grows friendly plates in combat), so it must be idempotent.
function NP.LayoutFrame(f)
    local d = DB()
    local cfg = f.isFriend and d.friendly or d.enemy
    local w, h = NP.FrameDims(f)

    f:SetSize(w, h)
    f.health:ClearAllPoints()
    f.health:SetAllPoints(f)
    f.health:SetStatusBarTexture(NP.BarTexture("healthTexture"))
    NP.BarChrome(f.health.bg, f.health)
    local hc = d.target.hoverColor
    if hc then f.health.hover:SetColorTexture(hc[1] or 1, hc[2] or 1, hc[3] or 1, 1) end
    -- the target marks' host follows the bar (at rest: a playing target
    -- animation is stopped first, so it never ends on the old spot)
    if f.tgtCue then
        if NP.FX then NP.FX.Settle(f) end
        f.tgtCue:ClearAllPoints()
        f.tgtCue:SetPoint("CENTER", f.health, "CENTER", 0, 0)
        f.tgtCue:SetSize(w, h)
    end

    -- Marker size first, because the NAME has to be placed around it.
    -- markerSize 0 = a shade taller than the bar. Only a marker sitting
    -- ON the bar (centre) overflows into the space above it, so only then
    -- does a name above the bar shift up by the overhang - once, at
    -- layout time: a constant gap, so nothing jumps when a mark comes or
    -- goes.
    local mpos = cfg.markerPos or "centre"
    local ri = tonumber(cfg.markerSize) or 0
    if ri <= 0 then ri = math.max(12, math.floor(h * 1.3 + 0.5)) end
    local overhang = 0
    if mpos == "centre" then
        overhang = math.max(0, math.floor((ri - h) / 2 + 0.5))
    end
    f._iconOverhang = overhang

    -- only_thename: friendlies are a floating class-colored name, no
    -- bar at all - the profile's whole friendly look
    f.nameOnly = (f.isFriend and cfg.nameOnly) and true or false
    -- NAME INSIDE (namePos "inside"): the name sits in the bar between
    -- the level (left) and the health percent (right). It has to ride the
    -- bar frame, or the bar draws over it.
    local npos = cfg.namePos or (cfg.nameInside and "inside") or "above"
    -- match pass (ZacUI's look): a name above the bar would sit under an
    -- icon row over the plate (Readycheck's nameplate auras, or a centre
    -- group of ZacUI's own debuff groups that reach above the bar), so it
    -- goes inside the bar while such a row is on
    f._npIconRow = nil
    if npos == "above" and not f.isFriend and NP.MatchOn and NP.MatchOn() and NP.IconRowOver() then
        npos = "inside"
        f._npIconRow = true
    end
    f._nameInside = (npos == "inside" and not f.nameOnly) and true or false
    f.name:SetParent(f._nameInside and f.health or f)
    f.name:SetDrawLayer("OVERLAY", 7)
    -- (placed below, once the fonts are on: the spot carries the justify)
    local SetDef = NP.SetDef
    local nameDef
    if f.nameOnly then
        f.health:Hide()
        nameDef = SetDef(f, "name", "CENTER", f, "CENTER", 0, 0, "CENTER")
    elseif f._nameInside then
        f.health:Show()
        nameDef = SetDef(f, "name", "LEFT", f.level, "RIGHT", 3, 0,
            cfg.nameJustify == "CENTER" and "CENTER" or "LEFT",
            "RIGHT", f.percent, "LEFT", -3, 0)
    else
        f.health:Show()
        -- (match pass: 7 px over the bar, the reference's 4 + 3)
        nameDef = SetDef(f, "name", "BOTTOM", f.health, "TOP", 0, ((NP.MatchOn and NP.MatchOn()) and 7 or 2) + overhang, "CENTER")
    end

    local ApplyNPFont = NP.ApplyNPFont
    ApplyNPFont(f.name, cfg.nameFont, cfg.nameSize)
    ApplyNPFont(f.level, cfg.levelFont, (cfg.levelSize or cfg.nameSize))
    ApplyNPFont(f.percent, cfg.percentFont, cfg.percentSize or cfg.nameSize)
    local pc = cfg.percentColor
    if pc then f.percent:SetTextColor(pc[1] or 1, pc[2] or 1, pc[3] or 1, pc[4] or 1) end
    -- the health percent inside the bar's right end, the level's spot is
    -- NP.MarkerLevel's (it moves while a marker sits at the left end)
    NP.Place(f, f.percent, "percent", SetDef(f, "percent", "RIGHT", f.health, "RIGHT", (NP.MatchOn and NP.MatchOn()) and -2 or -1, 0))
    f._levelX = nil
    local twoName = NP.Place(f, f.name, "name", nameDef)
    if not f._nameInside or not twoName then
        -- one point: as wide as the plate and a bit, as above the bar
        f.name:SetWidth(w + 40)
    end

    -- WHERE THE MARKER GOES. Readycheck's aura groups all carry an offset
    -- off centre (taunts -78, armorextra -59, execute +35, overpower +52,
    -- armor +75) on a row 20px over the plate's centre, and ZacUI's own
    -- level and health % sit hard against the bar's inside edges, so:
    --   above   centred markerY px over the bar's top edge - with the
    --           16-tall bar that is +20 from the centre, the empty middle
    --           of that icon row. Over a name that is above the bar, it
    --           sits on the name instead.
    --   centre  on the bar, a shade taller than it (the old look)
    --   left    just outside the bar's left end
    f.raidIcon:SetSize(ri, ri)
    f.raidIconShadow:SetSize(ri, ri)
    local mx, my = tonumber(cfg.markerX) or 0, tonumber(cfg.markerY) or 12
    local rdef
    if f.nameOnly then
        -- No bar to sit on, and centring would bury the name under the
        -- icon - on a name-only plate the name IS the plate. Sits beside
        -- it instead, still at full size.
        rdef = SetDef(f, "raidMarker", "RIGHT", f.name, "LEFT", -2, 0)
    elseif mpos == "above" and not f._nameInside then
        rdef = SetDef(f, "raidMarker", "CENTER", f.name, "TOP", mx, math.floor(ri / 2 + 0.5) + 1)
    elseif mpos == "above" then
        rdef = SetDef(f, "raidMarker", "CENTER", f.health, "TOP", mx, my)
    elseif mpos == "left" then
        rdef = SetDef(f, "raidMarker", "CENTER", f.health, "LEFT", mx - math.floor(ri / 2 + 0.5) - 2, 0)
    elseif mpos == "level" then
        -- in the level number's place at the bar's left end (2026-10-24,
        -- Zac: the BT/WW row covers a marker above the bar, and centred
        -- it sits on the name); the level steps aside while a mark is up
        -- and the name starts after the marker (NP.UpdateName)
        rdef = SetDef(f, "raidMarker", "CENTER", f.health, "LEFT", math.floor(ri / 2 + 0.5) + 1 + mx, 0)
    else
        rdef = SetDef(f, "raidMarker", "CENTER", f.health, "CENTER", mx, 0)
    end
    NP.Place(f, f.raidIconFrame, "raidMarker", rdef)

    -- The top of what sits over the bar (the name, or a marker above
    -- it). The soft-target arrows stand on this, so with the name inside
    -- the bar they clear the marker instead of covering it.
    if not f.markTop then
        f.markTop = CreateFrame("Frame", nil, f)
        f.markTop:SetSize(1, 1)
    end
    f._markerLevel = (mpos == "level" and not f.nameOnly) and ri or nil
    f.markTop:ClearAllPoints()
    local half = math.ceil(ri / 2)
    if f.nameOnly then
        f.markTop:SetPoint("BOTTOM", f.name, "TOP", 0, 0)
    elseif f._nameInside then
        f.markTop:SetPoint("BOTTOM", f.health, "TOP", 0, (mpos == "above") and (my + half) or 0)
    else
        f.markTop:SetPoint("BOTTOM", f.name, "TOP", 0, (mpos == "above") and (ri + 1) or 0)
    end

    NP.MarkerLevel(f)

    -- threat strip before extras: it settles f._threatOn, which decides
    -- where the target name hangs
    if NP.LayoutThreat then NP.LayoutThreat(f) end
    NP.LayoutCast(f)
    NP.LayoutAuras(f)
    NP.LayoutExtras(f)
end

-- ============================================================
-- TARGET NEON + HOVER GLOW
-- ============================================================
-- Plater's target highlight verbatim: two additive strips wearing the
-- selection_indicator3 texture (bundled), one sitting on the bar's top
-- edge, one hanging off the bottom flipped vertically.
local TEX_NEON = [[Interface\AddOns\ZacUI\Media\Nameplates\targetNeon]]

function NP.SetTargetNeon(f, on)
    local hb = f.health
    -- a name-only plate has no bar to frame
    if f.nameOnly then on = false end
    if on then
        local d = DB()
        -- on the marks' host, which sits exactly over the bar
        local host = f.tgtCue or hb
        if not hb.neonUp then
            local up = host:CreateTexture(nil, "OVERLAY", nil, 7)
            up:SetTexture(TEX_NEON)
            up:SetBlendMode("ADD")
            local down = host:CreateTexture(nil, "OVERLAY", nil, 7)
            down:SetTexture(TEX_NEON)
            down:SetBlendMode("ADD")
            down:SetTexCoord(0, 1, 1, 0)
            hb.neonUp, hb.neonDown = up, down
        end
        local c, h = d.target.color, d.target.neonHeight or 12
        for i = 1, 2 do
            local tex = (i == 1) and hb.neonUp or hb.neonDown
            tex:SetVertexColor(c[1], c[2], c[3])
            tex:SetAlpha(d.target.alpha or 0.8)
            tex:SetHeight(h)
        end
        hb.neonUp:ClearAllPoints()
        hb.neonUp:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 0)
        hb.neonUp:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", 0, 0)
        hb.neonDown:ClearAllPoints()
        hb.neonDown:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, 0)
        hb.neonDown:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, 0)
        hb.neonUp:Show()
        hb.neonDown:Show()
    elseif hb.neonUp then
        hb.neonUp:Hide()
        hb.neonDown:Hide()
    end
end

-- Is there an icon row over the plate's middle? Readycheck's nameplate
-- auras (only while Readycheck is loaded and they are on) or a centre
-- group of ZacUI's own debuff groups, read from their saved settings like
-- the soft-target arrows do (NP_SoftTarget's AuraClearance): an enabled
-- centre group whose icons reach above the bar's top (half a 20 px bar).
-- Asked at layout time only.
function NP.IconRowOver()
    local function reaches(c)
        if not (type(c) == "table" and c.enabled and type(c.groups) == "table") then return false end
        for _, g in ipairs(c.groups) do
            if g.enabled ~= false and (g.attach or "center") == "center" then
                local half = ((tonumber(g.fontSize) or 11) + 2) / 2
                if (tonumber(g.offsetY) or 0) + half > 10 then return true end
            end
        end
        return false
    end
    local NPD = NP.Debuffs
    local mine = NPD and NPD.Cfg and NPD.Cfg()
    if reaches(mine) then return true end
    local RC = _G.Readycheck
    local NA = RC and RC.nameplateAuras
    local c = NA and NA.cfg and NA.cfg()
    return reaches(c)
end

-- The match pass's target cue (ZacUI's look, d.target.glow): a soft glow
-- reaching d.target.glowSize (6) px out round the bar in glowColor (the
-- reference's blue), drawn as ZacUI's own gradient strips - four sides
-- fading outward and four corners - additive, made on the first target.
local GLOW_DEF = { 0.41, 0.67, 1.0 }
local function GlowGradient(t, orient, r, g, b, a, outerFirst)
    local c0 = outerFirst and 0 or a
    local c1 = outerFirst and a or 0
    if CreateColor and t.SetGradient
       and pcall(t.SetGradient, t, orient, CreateColor(r, g, b, c0), CreateColor(r, g, b, c1)) then
        t:SetVertexColor(1, 1, 1, 1)
        return
    end
    if t.SetGradientAlpha and pcall(t.SetGradientAlpha, t, orient, r, g, b, c0, r, g, b, c1) then return end
    t:SetVertexColor(r, g, b, a * 0.5)
end
function NP.SetTargetGlow(f, on)
    local hb = f.health
    if f.nameOnly then on = false end
    local gl = hb and hb.matchGlow
    if not on then
        if gl then for _, t in ipairs(gl) do t:Hide() end end
        return
    end
    local d = DB()
    local n = tonumber(d.target.glowSize) or 6
    local c = d.target.glowColor or GLOW_DEF
    local r, g, b, a = c[1] or c.r or 0.41, c[2] or c.g or 0.67, c[3] or c.b or 1, c[4] or c.a or 1
    if not gl then
        gl = {}
        local host = f.tgtCue or hb
        for i = 1, 8 do
            local t = host:CreateTexture(nil, "BACKGROUND", nil, -7)
            t:SetTexture([[Interface\Buttons\WHITE8X8]])
            t:SetBlendMode("ADD")
            gl[i] = t
        end
        hb.matchGlow = gl
    end
    local host = f.tgtCue or hb
    local T, B, L, R, TL, TR, BL, BR = gl[1], gl[2], gl[3], gl[4], gl[5], gl[6], gl[7], gl[8]
    for _, t in ipairs(gl) do t:ClearAllPoints() end
    T:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 0); T:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", 0, 0); T:SetHeight(n)
    B:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, 0); B:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, 0); B:SetHeight(n)
    L:SetPoint("TOPRIGHT", host, "TOPLEFT", 0, 0); L:SetPoint("BOTTOMRIGHT", host, "BOTTOMLEFT", 0, 0); L:SetWidth(n)
    R:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, 0); R:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", 0, 0); R:SetWidth(n)
    TL:SetPoint("BOTTOMRIGHT", host, "TOPLEFT", 0, 0); TR:SetPoint("BOTTOMLEFT", host, "TOPRIGHT", 0, 0)
    BL:SetPoint("TOPRIGHT", host, "BOTTOMLEFT", 0, 0); BR:SetPoint("TOPLEFT", host, "BOTTOMRIGHT", 0, 0)
    for i = 5, 8 do gl[i]:SetSize(n, n) end
    -- sides fade outward; corners at half strength fading the same way
    GlowGradient(T, "VERTICAL", r, g, b, a, false)
    GlowGradient(B, "VERTICAL", r, g, b, a, true)
    GlowGradient(L, "HORIZONTAL", r, g, b, a, true)
    GlowGradient(R, "HORIZONTAL", r, g, b, a, false)
    GlowGradient(TL, "VERTICAL", r, g, b, a * 0.5, false)
    GlowGradient(TR, "VERTICAL", r, g, b, a * 0.5, false)
    GlowGradient(BL, "VERTICAL", r, g, b, a * 0.5, true)
    GlowGradient(BR, "VERTICAL", r, g, b, a * 0.5, true)
    for _, t in ipairs(gl) do t:Show() end
end

function NP.SetHoverGlow(f, alpha)
    if f.health and f.health.hover then
        f.health.hover:SetAlpha(alpha or 0)
    end
end

-- ============================================================
-- HEALTH
-- ============================================================
-- The health fill glides to a new value (about 0.15 s) instead of
-- jumping; one driver for every plate, running only while one is still
-- moving. A plate that now shows a different unit snaps. DB().smooth =
-- false puts back the plain jump.
local gliding = {}
local glider = CreateFrame("Frame")
glider:Hide()
glider:SetScript("OnUpdate", function(self, elapsed)
    local k = math.min(1, (elapsed or 0.016) * (tonumber(DB().smoothRate) or 18))
    local any = false
    for bar, target in pairs(gliding) do
        local cur = bar._zsv or target
        local _, mx = bar:GetMinMaxValues()
        local nxt = cur + (target - cur) * k
        if math.abs(target - nxt) <= (mx or 1) * 0.002 or not bar:IsVisible() then
            nxt = target
            gliding[bar] = nil
        else
            any = true
        end
        bar._zsv = nxt
        bar:SetValue(nxt)
    end
    if not any then self:Hide() end
end)

local function GlideHealth(bar, value, max, guid)
    local smooth = DB().smooth ~= false
    if not smooth or bar._zsv == nil or bar._zsg ~= guid or bar._zsm ~= max then
        gliding[bar] = nil
        bar._zsv, bar._zsg, bar._zsm = value, guid, max
        bar:SetValue(value)
        return
    end
    if value == bar._zsv then gliding[bar] = nil return end
    gliding[bar] = value
    glider:Show()
end

-- WoW Forever hides an enemy's health in combat (secret values: no
-- compare, no arithmetic). The bar and the percent still take them as
-- they are (ZacUI's display helpers, Core_Flavor): the bar straight from
-- the two values (no glide: a glide is maths), the percent the game's
-- own (UnitHealthPercent through a 0-100 curve). "Hide the percent at
-- full health" is the game's answer too, as the text's alpha (a curve:
-- 0 at full). A saved percent format can't be filled from hidden values,
-- so the plain "N%" shows meanwhile. The priority count's "at zero"
-- check is maths on the health: it waits until the health reads again.
-- The remembered values the plain path compares against are cleared,
-- so it picks up cleanly afterwards.
local function FillHiddenHealth(f, hp, hpMax)
    local bar = f.health
    gliding[bar] = nil
    bar._zsv, bar._zsg, bar._zsm, bar._max = nil, nil, nil, nil
    f._pctShown = nil
    if not ns.ShowBar(bar, hp, hpMax) then return end
    local cfg = f.isFriend and DB().friendly or DB().enemy
    local pct = cfg.percent and not f.nameOnly and ns.HealthPercent(f.unit) or nil
    if pct ~= nil and ns.ShowText(f.percent, "%.0f%%", pct) then
        local a = ns.HealthAlpha(f.unit, 0.9995)
        if a ~= nil then
            f.percent:SetAlpha(a)
            f.percent._zHiddenA = true
        end
    else
        f.percent:SetText("")
    end
end

function NP.UpdateHealth(f)
    if not f.unit then return end
    local hp = UnitHealth(f.unit)
    local hpMax = UnitHealthMax(f.unit)
    -- (WoW Forever: hidden in combat - shown as it is, FillHiddenHealth)
    if ns.IsSecret and (ns.IsSecret(hp) or ns.IsSecret(hpMax)) then
        if ns.ShowBar then FillHiddenHealth(f, hp, hpMax) end
        return
    end
    if f.percent._zHiddenA then f.percent._zHiddenA = nil f.percent:SetAlpha(1) end
    -- a priority mob at zero drops out of the mid-screen count at once,
    -- before its plate goes (priority plates only: one compare each)
    if f._priority and (hp <= 0) ~= (f._prioDead or false) then
        f._prioDead = hp <= 0
        if NP.PriorityCount then NP.PriorityCount() end
    end
    NP.FillHealth(f, hp, hpMax, NP.SafeGUID(f.unit))
end

-- The bar and the percent from the numbers alone - the live plate above
-- and the settings preview's samples both paint through here.
function NP.FillHealth(f, hp, hpMax, guid)
    if hpMax <= 0 then hpMax = 1 end
    if f.health._max ~= hpMax then f.health._max = hpMax f.health:SetMinMaxValues(0, hpMax) end
    GlideHealth(f.health, hp, hpMax, guid)

    -- The text is only rewritten when the number on it changes: under
    -- raid AoE health moves many times a second and the whole percent
    -- usually does not. false = "showing nothing", so the first pass on
    -- a new frame (nil) always writes.
    local cfg = f.isFriend and DB().friendly or DB().enemy
    local pct = false
    if cfg.percent and hp < hpMax and not f.nameOnly then
        local fmt = cfg.formats and cfg.formats.percent
        if fmt then
            -- a saved format: the whole line through ZacUI's formatter
            -- (a string per change; nothing saved keeps the number path)
            local v = f._pctVals
            if not v then v = {} f._pctVals = v end
            v.pct, v.cur, v.max, v.deficit = hp / hpMax * 100, hp, hpMax, hpMax - hp
            pct = ns.FormatText(fmt, NP.PCT_FORMAT_DEFAULTS, v, NP.PCT_FORMAT_KINDS)
        else
            pct = math.floor(hp / hpMax * 100 + 0.5)
        end
    end
    if pct ~= f._pctShown then
        f._pctShown = pct
        if type(pct) == "string" then
            f.percent:SetText(pct)
        elseif pct then
            f.percent:SetFormattedText("%d%%", pct)
        else
            f.percent:SetText("")
        end
    end
end

-- ============================================================
-- NAME + LEVEL
-- ============================================================
-- Marker at the bar's left end (markerPos "level"): while a mark is up
-- the level steps right to make room for it (Zac, 07:28: "i still want
-- to see mob lvl"), and the name inside the bar - anchored to the level -
-- follows. Unmarked, the level is back at the left edge. From LayoutFrame
-- and UpdateName, so a re-layout never puts anything under the marker.
function NP.MarkerLevel(f)
    if not (f and f.level and f.raidIcon) then return end
    local marked = f.raidIcon:IsShown()
    local x = (f._markerLevel and marked) and (f._markerLevel + 3) or ((NP.MatchOn and NP.MatchOn()) and 4 or 1)
    if f._levelX ~= x then
        f._levelX = x
        NP.Place(f, f.level, "level", NP.SetDef(f, "level", "LEFT", f.health, "LEFT", x, 0))
    end
    if f.level:GetAlpha() < 1 then f.level:SetAlpha(1) end
end

-- The raid marker, from the 4x4 icon sheet by hand: SetRaidTargetIconTexture
-- left the texture empty on this client (see the unit frames' setRaidMarker),
-- so both draw it the same way. Runs from UpdateName and, on its own, from
-- RAID_TARGET_UPDATE - marks churn all fight and nothing else needs re-reading.
local RT_SHEET = [[Interface\TargetingFrame\UI-RaidTargetingIcons]]
function NP.UpdateRaidMark(f)
    if not f.unit then return end
    NP.FillRaidMark(f, GetRaidTargetIndex and GetRaidTargetIndex(f.unit))
end

-- mark 1..8 (skull is 8), or nil for none; the raid-marker switch is
-- read here, so the samples obey it too
function NP.FillRaidMark(f, mark)
    if not DB().extras.raidMark then mark = nil end
    if ns.IsSecret(mark) then mark = nil end   -- (WoW Forever can hide it: no mark)
    if mark and mark >= 1 and mark <= 8 then
        if f._markIdx ~= mark then
            f._markIdx = mark
            local col, row = (mark - 1) % 4, math.floor((mark - 1) / 4)
            local l, r2 = col * 0.25, col * 0.25 + 0.25
            local t, b = row * 0.25, row * 0.25 + 0.25
            f.raidIcon:SetTexture(RT_SHEET)
            f.raidIcon:SetTexCoord(l, r2, t, b)
            f.raidIconShadow:SetTexture(RT_SHEET)
            f.raidIconShadow:SetTexCoord(l, r2, t, b)
            f.raidIconShadow:SetVertexColor(0, 0, 0, 0.6)
        end
        f.raidIconShadow:Show()
        f.raidIcon:Show()
    else
        f.raidIcon:Hide()
        f.raidIconShadow:Hide()
    end
    NP.MarkerLevel(f)
end

function NP.UpdateName(f)
    if not f.unit then return end
    local unit = f.unit
    -- (WoW Forever: the surname as Core_Names says; elsewhere UnitName)
    f.name:SetText((ns.UnitDisplayName and ns.UnitDisplayName(unit) or UnitName(unit)) or "")
    if NP.CheckPriority then NP.CheckPriority(f) end

    -- The marker is a full-size texture centred on the bar, sized in
    -- LayoutFrame - nothing here depends on the name or its font.
    NP.UpdateRaidMark(f)

    local isPlayer = UnitIsPlayer(unit)
    local class
    if isPlayer then
        local _
        _, class = UnitClass(unit)
    end
    NP.FillName(f, nil, isPlayer, class, (not isPlayer) and UnitLevel(unit) or nil)
end

-- The name's colour and the level from the facts (name text: nil keeps
-- what is there) - live plates above, the preview's samples directly.
function NP.FillName(f, name, isPlayer, class, lvl)
    local d = DB()
    local cfg = f.isFriend and d.friendly or d.enemy
    if name then f.name:SetText(name) end

    -- the profile class-colored friendly NAMES but not enemy names
    local nc = cfg.nameColor
    local r, g, b = 1, 1, 1
    local a = (nc and nc[4]) or 0.95
    if nc then r, g, b = nc[1] or 1, nc[2] or 1, nc[3] or 1 end
    if cfg.nameClassColor and isPlayer then
        local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if cc then r, g, b = cc.r, cc.g, cc.b end
    end
    -- kept, so the important state's name colour (d.states) can be taken
    -- back off without working the colour out again
    local nc0 = f._npNameRGBA or {}
    f._npNameRGBA = nc0
    nc0[1], nc0[2], nc0[3], nc0[4] = r, g, b, a
    f.name:SetTextColor(r, g, b, a)
    if f.health._npStT then NP.PaintState(f.health, f.name, f._npImportant and "important" or nil, 1, NP.RestoreNameColor and NP.RestoreNameColor(f)) end

    -- level, difficulty-colored; the profile only showed it on NPCs
    if cfg.levelShow and not isPlayer then
        local txt = (lvl and lvl > 0) and tostring(lvl) or "??"
        local qc = (lvl and lvl > 0) and GetQuestDifficultyColor
            and GetQuestDifficultyColor(lvl)
        f.level:SetText(txt)
        if qc then
            f.level:SetTextColor(qc.r, qc.g, qc.b, 1)
        else
            f.level:SetTextColor(1, 0.2, 0.2, 1) -- skull
        end
    else
        f.level:SetText("")
    end
end

-- ============================================================
-- THREAT + REACTION - the bar color
-- ============================================================
-- Plater's full model on the era threat API. UnitDetailedThreatSituation
-- gives isTanking + status + your raw threat as a percentage of the
-- current tank's, and the percentage is what makes the warning colors
-- EARLY instead of after the mob already turned:
--   TANK:  secure (status 3) = calm; INSECURE (status 2, someone past
--          100% closing on the swap point) = pulling warning; lost =
--          alarm, unless another tank in the group is holding it.
--   DPS:   tanking it = alarm; past 90% of the tank's threat = pulling
--          warning; otherwise calm - and when you are solo, "you have
--          aggro" is the normal state, so it wears the solo color
--          instead of screaming red at every quest mob.
local function AnotherTankHasIt(unit)
    local t = unit .. "target"
    if not UnitExists(t) or UnitIsUnit(t, "player") then return false end
    return UnitIsPlayer(t)
        and (UnitInParty(t) or UnitInRaid(t)) and true or false
end

-- alarm means "this plate is the one to look at": drives the aggro glow
--
-- The threat read is left in threatRead/threatTank/threatStatus/threatPct
-- for the strip, which wants the very same answer a few lines later in
-- the same pass (NP.UpdateThreat) - one API call per plate, not two.
local threatRead, threatTank, threatStatus, threatPct = false

-- fk: made-up facts for a settings-preview sample ({ combat, tanking,
-- status, pct, grouped, otherTank }), read instead of the unit; nil for
-- a live plate. Same decisions either way.
local function ThreatColor(f, d, fk)
    local unit = f.unit
    if fk then
        if not fk.combat then return nil, false end
    elseif not UnitAffectingCombat(unit) then
        return nil, false
    end
    local isTank = NP.PlayerIsTank()

    local isTanking, status
    threatPct = nil
    if fk then
        isTanking, status, threatPct = fk.tanking, fk.status, fk.pct
        threatRead, threatTank, threatStatus = true, isTanking, status
    elseif UnitDetailedThreatSituation then
        isTanking, status, threatPct =
            UnitDetailedThreatSituation("player", unit)
        -- WoW Forever hides threat in combat (secret values): nothing to
        -- compare, so no threat colour - the plate keeps its normal one
        if (issecretvalue ~= nil and (issecretvalue(isTanking) or issecretvalue(status) or issecretvalue(threatPct))) then
            threatPct, threatRead, threatTank, threatStatus = nil, false, nil, nil
            return nil, false
        end
        threatRead, threatTank, threatStatus = true, isTanking, status
    elseif UnitThreatSituation then
        status = UnitThreatSituation("player", unit)
        if issecretvalue ~= nil and issecretvalue(status) then return nil, false end
        isTanking = status and status >= 2
    end

    if status == nil then
        -- fighting, but we are not on its threat table at all
        return isTank and d.threat.tankNoAggro or d.threat.dpsNoAggro,
            isTank
    end

    if isTank then
        if isTanking then
            if status == 2 then
                -- tanking INSECURELY: someone is over the pull
                -- threshold - the warning that matters most
                return d.threat.pulling, true
            end
            return d.threat.tankAggro, false
        end
        local other
        if fk then other = fk.otherTank else other = AnotherTankHasIt(unit) end
        if other then
            return d.threat.tankOther, false
        end
        return d.threat.tankNoAggro, true -- lost it: alarm
    end

    -- dps / healer
    if isTanking then
        local grouped
        if fk then grouped = fk.grouped else grouped = IsInGroup() or IsInRaid() end
        if not grouped then
            return d.threat.solo, false -- solo: aggro is just Tuesday
        end
        return d.threat.dpsAggro, true -- ripped it: alarm
    end
    if threatPct and threatPct >= 90 then
        return d.threat.pulling, false -- about to rip: warning
    end
    if status == 1 then
        return d.threat.pulling, false
    end
    return d.threat.dpsNoAggro, false
end

-- fk: made-up facts for a settings-preview sample, read instead of the
-- unit (see ThreatColor; plus isPlayer, class, tapped, reaction) - the
-- sample's bar takes its colour through every rule a live plate does.
-- the name's own colour back (after an important state's text colour)
local restorers = setmetatable({}, { __mode = "k" })
function NP.RestoreNameColor(f)
    local fn = restorers[f]
    if not fn then
        fn = function()
            local c = f._npNameRGBA
            if c then f.name:SetTextColor(c[1], c[2], c[3], c[4]) end
        end
        restorers[f] = fn
    end
    return fn
end

function NP.UpdateColor(f, fk)
    if not (f.unit or fk) then return end
    local d = DB()
    local unit = f.unit
    local r, g, b
    local glowOn = false
    threatRead = false

    -- The npc id was read once when the plate was assigned (NP_Core's
    -- OnUnitAdded); nil only for a frame that got here some other way.
    local npcId = f.npcId
    if npcId == nil and not fk then
        npcId = not UnitIsPlayer(unit) and NP.NpcIdFromUnit(unit)
    end
    local isPlayer
    if fk then isPlayer = fk.isPlayer else isPlayer = UnitIsPlayer(unit) end
    -- the ported npc-color database outranks everything else, exactly
    -- like Plater's npc_colors did
    local override = npcId and d.npcColors[npcId]
    -- IMPORTANT PLATES (2026-10-28, Zac picked "A"): the priority mobs,
    -- the never-fade list and bosses wear the important colour on the
    -- bar, and the threat colour they would have had moves to a thick
    -- border round it - you see the mob first, then whose it is.
    local imp = d.priority and d.priority.enabled and d.priority.recolor and d.priority.color
    local important = imp and not f.isFriend and (f._priority or f._noFade
        or (f.isBoss and not (d.target and d.target.bossNoFade == false)))
    local edge
    local tapped
    if not important and not override then
        if fk then tapped = fk.tapped else tapped = UnitIsTapDenied and UnitIsTapDenied(unit) end
    end
    if important then
        r, g, b = imp[1], imp[2], imp[3]
        if d.threat.enabled and not isPlayer then
            local tc, isAlarm = ThreatColor(f, d, fk)
            if tc then
                edge = tc
                glowOn = d.threat.glow and isAlarm or false
            end
        end
    elseif override then
        r, g, b = override[1], override[2], override[3]
    elseif tapped then
        local t = d.tapped
        r, g, b = t[1], t[2], t[3]
    elseif isPlayer then
        -- the profile class-colored PLAYER BARS on both sides
        local cfg = f.isFriend and d.friendly or d.enemy
        if cfg.barClassColor then
            local class
            if fk then class = fk.class else local _ _, class = UnitClass(unit) end
            local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if cc then r, g, b = cc.r, cc.g, cc.b end
        end
        if not r then
            local pal = f.isFriend and d.reaction.friendly or d.reaction.hostile
            r, g, b = pal[1], pal[2], pal[3]
        end
    else
        if not f.isFriend and d.threat.enabled then
            local tc, isAlarm = ThreatColor(f, d, fk)
            if tc then
                r, g, b = tc[1], tc[2], tc[3]
                glowOn = d.threat.glow and isAlarm or false
            end
        end
        if not r then
            local reaction
            if fk then reaction = fk.reaction or 4 else reaction = UnitReaction(unit, "player") or 4 end
            local pal = (reaction <= 3 and d.reaction.hostile)
                or (reaction == 4 and d.reaction.neutral)
                or d.reaction.friendly
            r, g, b = pal[1], pal[2], pal[3]
        end
    end

    -- always driven, so a recycled frame never keeps a stale glow / edge
    NP.SetAggroGlow(f, glowOn)
    NP.SetThreatEdge(f, edge)
    f.health:SetStatusBarColor(r, g, b, 1)
    -- the important state's own look (d.states.important), over the usual
    f._npImportant = important and true or nil
    if d.states or f.health._npSt then
        NP.PaintState(f.health, f.name, important and "important" or nil, 1, NP.RestoreNameColor(f))
    end
    -- the threat strip reads the same API on the same events, so it
    -- rides this pass rather than registering its own (a sample fills its
    -- strip itself)
    if fk then return end
    if NP.UpdateThreat then
        if threatRead then
            NP.UpdateThreat(f, true, threatTank, threatStatus, threatPct)
        else
            NP.UpdateThreat(f)
        end
    end
end

-- ============================================================
-- AGGRO GLOW - optional, OFF by default, and STEADY. The first version
-- pulsed, which in a group of alt boxes meant every plate you touched
-- strobed red on each hit. A constant sheen carries the same
-- information without demanding attention for it.
-- ============================================================
-- the threat border of an important plate: four strips just outside
-- the bar, made on first use; nil hides them
-- the border's thickness (Nameplates > Look, priority.edgeSize; 2 px);
-- the strips are only re-anchored when it changes
function NP.SetThreatEdge(f, c)
    local hb = f.health
    local e = hb.threatEdge
    if not c then
        if e then for i = 1, 4 do e[i]:Hide() end end
        return
    end
    if not e then
        e = {}
        for i = 1, 4 do e[i] = hb:CreateTexture(nil, "OVERLAY", nil, 6) end
        hb.threatEdge = e
    end
    local EDGE = tonumber(DB().priority.edgeSize) or 2
    if e._sz ~= EDGE then
        e._sz = EDGE
        for i = 1, 4 do e[i]:ClearAllPoints() end
        e[1]:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", -EDGE, 0)  e[1]:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", EDGE, 0)  e[1]:SetHeight(EDGE)
        e[2]:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", -EDGE, 0)  e[2]:SetPoint("TOPRIGHT", hb, "BOTTOMRIGHT", EDGE, 0)  e[2]:SetHeight(EDGE)
        e[3]:SetPoint("TOPRIGHT", hb, "TOPLEFT", 0, 0)        e[3]:SetPoint("BOTTOMRIGHT", hb, "BOTTOMLEFT", 0, 0)   e[3]:SetWidth(EDGE)
        e[4]:SetPoint("TOPLEFT", hb, "TOPRIGHT", 0, 0)        e[4]:SetPoint("BOTTOMLEFT", hb, "BOTTOMRIGHT", 0, 0)   e[4]:SetWidth(EDGE)
    end
    for i = 1, 4 do
        e[i]:SetColorTexture(c[1], c[2], c[3], 1)
        e[i]:Show()
    end
end

function NP.SetAggroGlow(f, on)
    local hb = f.health
    if on then
        if not hb.aggroGlow then
            local glow = hb:CreateTexture(nil, "OVERLAY", nil, 3)
            glow:SetAllPoints()
            glow:SetColorTexture(1, 0.25, 0.25, 1)
            glow:SetBlendMode("ADD")
            hb.aggroGlow = glow
        end
        local gc = DB().threat.glowColor
        if gc then hb.aggroGlow:SetColorTexture(gc[1] or 1, gc[2] or 0.25, gc[3] or 0.25, 1) end
        hb.aggroGlow:SetAlpha(0.25)
        hb.aggroGlow:Show()
    elseif hb.aggroGlow then
        hb.aggroGlow:Hide()
    end
end
