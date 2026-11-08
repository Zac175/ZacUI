-- ============================================================================
-- ZacUF - Elements.lua
-- Builds and updates the pieces of a unit frame: health bar, power bar, the
-- styled name, a basic aura row, and a castbar.
--
-- All elements are ALWAYS built; their per-frame toggles (frame.cfg.power /
-- name / auras / castbar) control visibility LIVE via show/hide, the events
-- that drive them are (un)registered to match, and the update functions early-
-- out when their element is disabled - so a disabled element is hidden AND does
-- no work, and toggling it back on takes effect immediately (no /reload).
--
-- Layering: health/power are child StatusBars (above their parent button), so
-- the name strip + text live on a dedicated Overlay frame placed ABOVE the bars
-- - that is what makes names visible.
-- ============================================================================
local ADDON, ns = ...
-- ZacUI's shared services (roster); reached through the global because
-- this part keeps its own private namespace
local Z = _G.ZacUI

local WHITE = "Interface\\Buttons\\WHITE8X8"
local function u(t) return t[1], t[2], t[3], t[4] or 1 end
-- a colour setting that may be missing on an old save: its default instead
local function uc(t, r, g, b, a)
    if type(t) ~= "table" then return r, g, b, a end
    return t[1] or t.r or r, t[2] or t.g or g, t[3] or t.b or b, t[4] or t.a or a
end
ns.ColorOr = uc

-- ZacUI's motion layer (show / hide / highlight animations). Looked up
-- when used: the part loads after ZacUI, but the unit-frame tests run
-- these files without it, and then everything simply happens at once.
local function Motion() local Zm = _G.ZacUI return Zm and Zm.Motion end

-- Show / hide a frame through a saved animation spec. Style "none" (the
-- default for everything the frames did instantly before) skips the
-- motion layer entirely, so the common case costs nothing extra.
local function motionShow(f, spec)
    local Mo = Motion()
    if Mo and type(spec) == "table" and spec.style and spec.style ~= "none" then
        Mo.Show(f, spec)
        return
    end
    if Mo and f._zMotion then Mo.Stop(f) end
    f:Show()
end
local function motionHide(f, spec, onDone)
    local Mo = Motion()
    if Mo and type(spec) == "table" and spec.style and spec.style ~= "none" then
        Mo.Hide(f, spec, onDone)
        return
    end
    if Mo and f._zMotion then Mo.Stop(f) end
    f:Hide()
    if onDone then onDone() end
end
ns.MotionShow, ns.MotionHide = motionShow, motionHide

-- ----------------------------------------------------------------------------
-- Text styles. Every text the frames draw goes through ns.ApplyFont with
-- its kind ("name", "health", "castbar", "auraCount", "healTotal"): the
-- saved font setting (ZacUI's font shape) over that text's own defaults,
-- which are exactly what each text always used - the unit frames' font,
-- outlined, no shadow, its old size.
-- ----------------------------------------------------------------------------
local FONT_DEFAULT_SIZE = { name = 12, health = 11, castbar = 11, auraCount = 10, healTotal = 11,
    tauntCount = 16 }   -- the AoE-taunt countdown (ShoutAlert.lua)
-- the match pass (Config.lua, ZacUI's look): the reference UI's sizes where
-- a text has none saved (health 12, the stack number 14)
local FONT_MATCH_SIZE = { health = 12, auraCount = 14 }
local OUTLINE_FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE", monochrome = "MONOCHROME" }
local function outlineFlags(v)
    if v == nil then return "OUTLINE" end
    local f = OUTLINE_FLAGS[v]
    if f then return f end
    local up = tostring(v):upper()   -- a client flag string saved as it was
    if up == "" or up == "NONE" then return "" end
    if up:find("MONOCHROME", 1, true) then return "MONOCHROME" end
    if up:find("THICK", 1, true) then return "THICKOUTLINE" end
    return "OUTLINE"
end

-- the font setting for one kind of text, with the two sizes that have
-- always lived elsewhere folded in
function ns.FontSpec(kind)
    local db = ns.db
    local spec = db and db.fonts and db.fonts[kind]
    if type(spec) ~= "table" then spec = nil end
    local size = spec and tonumber(spec.size)
    if kind == "name" then size = db and db.name and db.name.size or size
    elseif kind == "healTotal" then size = db and db.heal and db.heal.total and db.heal.total.size or size end
    return spec, size or (ns._matchApplied and FONT_MATCH_SIZE[kind]) or FONT_DEFAULT_SIZE[kind] or 11
end

-- the file for a text's face: ZacUI's one font (else the frames' font). A
-- face saved for one text (the per-text pickers of old) is ignored - kept
-- in the settings, never drawn.
function ns.FontPath(face)
    return ns.Media:Font(ns.db and ns.db.media and ns.db.media.font)
end

-- sizeOverride: a size the caller works out itself (the PvP text's per-frame one)
-- SetFont that says whether the face took: pcall catches a nil path, the
-- return value a font file that would not load - which leaves the string
-- with no font, so its next SetText errors ("Font not set")
local function TrySetFont(fs, path, size, flags)
    local ok, set = pcall(fs.SetFont, fs, path, size, flags)
    return (ok and set) and true or false
end
function ns.ApplyFont(fs, kind, sizeOverride)
    local spec, size = ns.FontSpec(kind)
    size = math.max(4, sizeOverride or size)
    -- (match pass, ZacUI's look: a text with no outline saved wears none and
    -- a black shadow 1 px down-right instead, the reference's body text)
    -- (2026-11-08, Zac: "what happened to the black border on text" - the
    -- shadow-only text is gone: every text keeps its outline, as before)
    local plain = false
    local flags = plain and "" or outlineFlags(spec and spec.outline)
    local path = ns.FontPath(spec and spec.face)
    if not TrySetFont(fs, path, size, flags)
       and not TrySetFont(fs, ns.Media:Font(ns.db and ns.db.media and ns.db.media.font), size, flags) then
        pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags)
    end
    -- every text in ZacUI's font, kept up when it changes
    local Z = ns.ZUI or _G.ZacUI
    if Z and Z.TrackHouseFont then
        Z.TrackHouseFont(fs, function(s) ns.ApplyFont(s, kind, sizeOverride) end)
    end
    if fs.SetShadowOffset then
        if (spec and spec.shadow) or (plain and not (spec and spec.shadow == false)) then
            if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
            fs:SetShadowOffset(tonumber(spec.shadowX) or 1, tonumber(spec.shadowY) or -1)
        else
            fs:SetShadowOffset(0, 0)
        end
    end
end

-- what the player's class can cleanse; set next to CLASS_DISPELS below, and
-- read here by the event registration so a class with no dispel does not
-- listen to UNIT_AURA on forty raid frames for a highlight it can never show
local playerDispels
-- either look a cleansable debuff can wear: the border tint
-- (auras.dispelHighlight) or the glow round the frame (dispelGlow.enabled)
local function glowOn()
    local g = ns.db and ns.db.dispelGlow
    return (g and g.enabled) and true or false
end
local function dispelLooks()
    return (ns.db.auras.dispelHighlight or glowOn()) and true or false
end

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
}

-- 9-point name anchor -> SetPoint point, horizontal justify, inset, strip band.
local NAME_ANCHOR = {
    ABOVE       = { p = "BOTTOM",      rp = "TOP",         j = "CENTER", x = 0,  y = 3,  vert = "OUT" },
    TOPLEFT     = { p = "TOPLEFT",     rp = "TOPLEFT",     j = "LEFT",   x = 4,  y = -3, vert = "TOP" },
    TOP         = { p = "TOP",         rp = "TOP",         j = "CENTER", x = 0,  y = -3, vert = "TOP" },
    TOPRIGHT    = { p = "TOPRIGHT",    rp = "TOPRIGHT",    j = "RIGHT",  x = -4, y = -3, vert = "TOP" },
    LEFT        = { p = "LEFT",        rp = "LEFT",        j = "LEFT",   x = 4,  y = 0,  vert = "CENTER" },
    CENTER      = { p = "CENTER",      rp = "CENTER",      j = "CENTER", x = 0,  y = 0,  vert = "CENTER" },
    RIGHT       = { p = "RIGHT",       rp = "RIGHT",       j = "RIGHT",  x = -4, y = 0,  vert = "CENTER" },
    BOTTOMLEFT  = { p = "BOTTOMLEFT",  rp = "BOTTOMLEFT",  j = "LEFT",   x = 4,  y = 2,  vert = "BOTTOM" },
    BOTTOM      = { p = "BOTTOM",      rp = "BOTTOM",      j = "CENTER", x = 0,  y = 2,  vert = "BOTTOM" },
    BOTTOMRIGHT = { p = "BOTTOMRIGHT", rp = "BOTTOMRIGHT", j = "RIGHT",  x = -4, y = 2,  vert = "BOTTOM" },
    BELOW       = { p = "TOP",         rp = "BOTTOM",      j = "CENTER", x = 0,  y = -3, vert = "OUT" },
}
-- the match pass (ZacUI's look): the reference's insets - 5 px in from
-- the left / right ends, 2 px in from a corner or the top / bottom edge
local NAME_ANCHOR_MATCH = {}
for k, v in pairs(NAME_ANCHOR) do
    local c = {}
    for f, x in pairs(v) do c[f] = x end
    NAME_ANCHOR_MATCH[k] = c
end
NAME_ANCHOR_MATCH.LEFT.x, NAME_ANCHOR_MATCH.RIGHT.x = 5, -5
for _, k in ipairs({ "TOPLEFT", "TOP", "TOPRIGHT" }) do NAME_ANCHOR_MATCH[k].y = -2 end
for _, k in ipairs({ "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }) do NAME_ANCHOR_MATCH[k].y = 2 end
for _, k in ipairs({ "TOPLEFT", "BOTTOMLEFT" }) do NAME_ANCHOR_MATCH[k].x = 2 end
for _, k in ipairs({ "TOPRIGHT", "BOTTOMRIGHT" }) do NAME_ANCHOR_MATCH[k].x = -2 end
local function NA() return ns._matchApplied and NAME_ANCHOR_MATCH or NAME_ANCHOR end

-- Aura-grid placement: where a buff/debuff block attaches to the frame and which
-- way the icons grow (gx = +1 right / -1 left, gy = +1 up / -1 down). bx/by are
-- small default gaps; the user's per-frame X/Y offset is added on top of these.
local AG = 2
local AURA_ANCHOR = {
    ABOVE       = { p = "BOTTOMLEFT",  rp = "TOPLEFT",     gx = 1,  gy = 1,  bx = 0,   by = AG  },
    TOPLEFT     = { p = "TOPLEFT",     rp = "TOPLEFT",     gx = 1,  gy = -1, bx = AG,  by = -AG },
    TOP         = { p = "TOP",         rp = "TOP",         gx = 1,  gy = -1, bx = 0,   by = -AG },
    TOPRIGHT    = { p = "TOPRIGHT",    rp = "TOPRIGHT",    gx = -1, gy = -1, bx = -AG, by = -AG },
    LEFT        = { p = "TOPRIGHT",    rp = "TOPLEFT",     gx = -1, gy = -1, bx = -AG, by = 0   },
    CENTER      = { p = "CENTER",      rp = "CENTER",      gx = 1,  gy = -1, bx = 0,   by = 0   },
    RIGHT       = { p = "TOPLEFT",     rp = "TOPRIGHT",    gx = 1,  gy = -1, bx = AG,  by = 0   },
    BOTTOMLEFT  = { p = "BOTTOMLEFT",  rp = "BOTTOMLEFT",  gx = 1,  gy = 1,  bx = AG,  by = AG  },
    BOTTOM      = { p = "BOTTOM",      rp = "BOTTOM",      gx = 1,  gy = 1,  bx = 0,   by = AG  },
    BOTTOMRIGHT = { p = "BOTTOMRIGHT", rp = "BOTTOMRIGHT", gx = -1, gy = 1,  bx = -AG, by = AG  },
    BELOW       = { p = "TOPLEFT",     rp = "BOTTOMLEFT",  gx = 1,  gy = -1, bx = 0,   by = -AG, below = true },
}

-- Status-icon placement (point/relpoint per icon). A *corner* anchor centers the
-- icon ON that corner, so it straddles the two edge lines -- half inside, half
-- outside (a badge sitting on the corner). TOP / BOTTOM / CENTER sit inside the
-- frame; LEFT / RIGHT / ABOVE / BELOW hang fully outside it. The lead/assist/tank
-- cluster defaults to TOPLEFT, sitting right on the top-left corner.
local IND_ANCHOR = {
    TOPLEFT     = { p = "CENTER", rp = "TOPLEFT"     },  -- on the corner (straddles top + left)
    TOP         = { p = "TOP",    rp = "TOP"         },
    TOPRIGHT    = { p = "CENTER", rp = "TOPRIGHT"    },  -- on the corner
    LEFT        = { p = "TOPRIGHT", rp = "TOPLEFT"   },  -- outside left edge, top-aligned
    CENTER      = { p = "CENTER", rp = "CENTER"      },
    RIGHT       = { p = "TOPLEFT", rp = "TOPRIGHT"   },  -- outside right edge, top-aligned
    BOTTOMLEFT  = { p = "CENTER", rp = "BOTTOMLEFT"  },  -- on the corner
    BOTTOM      = { p = "BOTTOM", rp = "BOTTOM"      },
    BOTTOMRIGHT = { p = "CENTER", rp = "BOTTOMRIGHT" },  -- on the corner
    ABOVE       = { p = "BOTTOM", rp = "TOP"         },
    BELOW       = { p = "TOP",    rp = "BOTTOM"      },
}

-- ----------------------------------------------------------------------------
-- Where every text and part sits. Each element's built-in placement - exactly
-- the SetPoint it always had, worked out from the frame's anchor presets above
-- - goes into a reused defaults table (ns.AnchorDefaults), and ZacUI's
-- ApplyAnchor places it with the frame's own saved spec on top
-- (cfg.anchors.<element>, ZacUI's anchor shape). Nothing saved = the old
-- point, exactly. Element keys (also what `to` can name):
-- ----------------------------------------------------------------------------
ns.ANCHOR_TEXTS = { "name", "healthText", "healTotal", "castText", "castTime", "pvpText" }
ns.ANCHOR_PARTS = { "castbar", "castIcon", "power", "nameStrip", "combat", "leader", "role", "raid", "rez" }
ns.ANCHOR_LABELS = {
    frame = "The frame", health = "Health bar", power = "Power bar", castbar = "Castbar",
    name = "Name", healthText = "Health text", healTotal = "Incoming heal number",
    castText = "Castbar spell name", castTime = "Castbar time", pvpText = "PvP text",
    castIcon = "Castbar icon", nameStrip = "Name strip", combat = "Combat icon",
    leader = "Leader icon", role = "Role icon", raid = "Raid marker", rez = "Resurrection icon",
}
ns.ANCHOR_TARGETS = { "frame", "health", "power", "castbar", "name", "healthText", "healTotal",
    "castText", "castTime", "castIcon", "pvpText", "combat", "leader", "role", "raid", "rez" }

-- the region an element key names on one frame (the `to` resolver)
function ns.ElementTarget(frame, key)
    if not frame then return nil end
    local cb, ind = frame.Castbar, frame.Indicators
    if key == "frame" then return frame
    elseif key == "overlay" then return frame.Overlay
    elseif key == "health" then return frame.Health
    elseif key == "power" then return frame.Power
    elseif key == "castbar" then return cb
    elseif key == "name" then return frame.Name
    elseif key == "healthText" then return frame.Health and frame.Health.text
    elseif key == "healTotal" then return frame.HealTotal
    elseif key == "nameStrip" then return frame.NameStrip
    elseif key == "castText" then return cb and cb.spell
    elseif key == "castTime" then return cb and cb.timer
    elseif key == "castIcon" then return cb and cb.icon
    elseif key == "pvpText" then return ind and ind.pvpText
    elseif ind and ind[key] then return ind[key] end
    return nil
end

local function setDef(D, key, p, to, rp, x, y, j, p2, to2, rp2, x2, y2)
    local t = D[key]
    if not t then t = {} D[key] = t end
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = p, to, rp, x, y, j
    t.point2, t.to2, t.relPoint2, t.x2, t.y2 = p2, to2, rp2, x2, y2
    return t
end

-- Every element's built-in placement for frame cfg `cfg`, into D (reused).
-- `frame` gives the targets; nil (the settings page asking what the default
-- is) leaves them out - only points and offsets matter there.
local function fillAnchorDefaults(frame, cfg, D)
    local db = ns.db
    cfg = cfg or {}
    local powerOn = cfg.power and true or false
    local nameOn  = cfg.name and true or false
    local powerH  = (powerOn and db.power.height) or 0
    local stripOn = nameOn and db.name.showStrip
    local hb = frame and frame.Health
    local ov = frame and frame.Overlay
    local cb = frame and frame.Castbar
    -- health text
    local ht = NA()[cfg.hpAnchor] or NA().RIGHT
    setDef(D, "healthText", ht.p, hb, ht.rp, ht.x + (cfg.hpX or 0), ht.y + (cfg.hpY or 0), ht.j)
    -- incoming-heal number (pinned to the health text, or a spot on the frame)
    local tc = db.heal and db.heal.total
    local tax = tc and tc.anchor
    if tax == "LEFT_OF_HP" or tax == "RIGHT_OF_HP" then
        local left = (tax == "LEFT_OF_HP")
        setDef(D, "healTotal", left and "RIGHT" or "LEFT", hb and hb.text, left and "LEFT" or "RIGHT",
            (left and -5 or 5) + ((tc and tc.x) or 0), (tc and tc.y) or 0, left and "RIGHT" or "LEFT")
    else
        local ta = NA()[tax] or NA().TOPRIGHT
        setDef(D, "healTotal", ta.p, ov, ta.rp, ta.x + ((tc and tc.x) or 0), ta.y + ((tc and tc.y) or 0), ta.j)
    end
    -- power bar: the bottom strip
    -- (inside the edge: one physical pixel under ZacUI's look, HD polish)
    local Zp = _G.ZacUI
    local px = Zp and Zp.Pixel and frame and Zp.Pixel.One(frame) or 1
    setDef(D, "power", "BOTTOMLEFT", frame, "BOTTOMLEFT", px, px, nil, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", -px, px)
    -- name strip + name
    local a = NA()[cfg.nameAnchor] or NA().LEFT
    local vy = a.y
    if a.vert == "BOTTOM" then vy = a.y + powerH end
    if a.vert == "BOTTOM" then
        setDef(D, "nameStrip", "BOTTOMLEFT", ov, "BOTTOMLEFT", 1, powerH + 1, nil, "BOTTOMRIGHT", ov, "BOTTOMRIGHT", -1, powerH + 1)
    elseif a.vert == "CENTER" then
        setDef(D, "nameStrip", "LEFT", ov, "LEFT", 1, 0, nil, "RIGHT", ov, "RIGHT", -1, 0)
    else
        setDef(D, "nameStrip", "TOPLEFT", ov, "TOPLEFT", 1, -1, nil, "TOPRIGHT", ov, "TOPRIGHT", -1, -1)
    end
    if stripOn then
        setDef(D, "name", "LEFT", frame and frame.NameStrip, "LEFT", 5, 0, "LEFT")
    else
        -- (2026-11-08, ZacUI's look: a name on the middle row sits on the
        -- health bar's middle, level with the health text there, as the
        -- reference's do - not the whole frame's, half the power bar low)
        local to = ov
        if ns._matchApplied and a.vert == "CENTER" and hb then to = hb end
        setDef(D, "name", a.p, to, a.rp, a.x + (cfg.nameX or 0), vy + (cfg.nameY or 0), a.j)
    end
    -- castbar and its pieces
    local cbA = NA()[cfg.cbAnchor] or NA().BELOW
    local cbH = (cfg.cbHeight and cfg.cbHeight > 0) and cfg.cbHeight or db.castbar.height
    if ns._matchApplied and db.castbar.showIcon then
        -- match pass: the icon is a square of its own at the bar's left end
        -- and the fill starts after it, the two together as wide as the
        -- castbar's width (StyleElements narrows the bar by the icon)
        local p = cbA.p
        local shift = p:find("LEFT", 1, true) and cbH or (p:find("RIGHT", 1, true) and 0 or cbH / 2)
        setDef(D, "castbar", p, frame, cbA.rp, (cfg.cbX or 0) + shift, cfg.cbY or 0)
        setDef(D, "castIcon", "TOPRIGHT", cb, "TOPLEFT", 0, 0, nil, "BOTTOMRIGHT", cb, "BOTTOMLEFT", 0, 0)
        setDef(D, "castText", "LEFT", cb, "LEFT", 5, 0, nil, "RIGHT", cb, "RIGHT", -34, 0)
        setDef(D, "castTime", "RIGHT", cb, "RIGHT", -3, 0)
    else
        setDef(D, "castbar", cbA.p, frame, cbA.rp, cfg.cbX or 0, cfg.cbY or 0)
        local iconPad = (db.castbar.showIcon and (cbH + 2)) or 4
        setDef(D, "castIcon", "TOPLEFT", cb, "TOPLEFT", 1, -1, nil, "BOTTOMLEFT", cb, "BOTTOMLEFT", 1, 1)
        setDef(D, "castText", "LEFT", cb, "LEFT", iconPad, 0, nil, "RIGHT", cb, "RIGHT", -34, 0)
        setDef(D, "castTime", "RIGHT", cb, "RIGHT", -4, 0)
    end
    -- status icons + PvP text
    for _, k in ipairs({ "combat", "leader", "role", "raid", "rez" }) do
        local A = IND_ANCHOR[cfg[k .. "Anchor"]] or IND_ANCHOR.CENTER
        setDef(D, k, A.p, ov, A.rp, cfg[k .. "X"] or 0, cfg[k .. "Y"] or 0)
    end
    local pa = IND_ANCHOR[cfg.pvpAnchor] or IND_ANCHOR.BOTTOM
    setDef(D, "pvpText", pa.p, ov, pa.rp, cfg.pvpX or 0, cfg.pvpY or 0)
    return D
end

-- what an element's default placement is for a frame cfg (the settings
-- page's anchor pickers show it); a scratch table, reused
local pageDefaults = {}
function ns.AnchorDefaults(cfg, key)
    fillAnchorDefaults(nil, cfg, pageDefaults)
    return pageDefaults[key]
end

-- place one element: its saved spec over its default. -> twoPoint
local function place(frame, region, key, d)
    local cfg = frame.cfg
    local a = cfg and cfg.anchors
    local spec = type(a) == "table" and a[key] or nil
    local Z = _G.ZacUI
    if Z and Z.ApplyAnchor then
        local _, two = Z.ApplyAnchor(region, spec, d, frame._anchorTo)
        return two
    end
    region:ClearAllPoints()
    region:SetPoint(d.point, d.to or region:GetParent(), d.relPoint, d.x, d.y)
    if d.point2 then region:SetPoint(d.point2, d.to2 or d.to or region:GetParent(), d.relPoint2, d.x2, d.y2) end
    if d.justify then region:SetJustifyH(d.justify) end
    return d.point2 ~= nil
end

-- the stack number's place on an aura icon (db.auras.anchors.count)
local AURA_COUNT_DEF = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = 1, y = -1 }
ns.AURA_COUNT_DEF = AURA_COUNT_DEF
-- (HD polish, ZacUI's look: one pixel inside the ring instead of over it)
local AURA_COUNT_DEF_HD = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -1, y = 1 }

-- Place aura icon `b` at 0-based slot `idx` within its group: lays out in a grid
-- of `perRow` columns, stepping (size+2) px along the anchor's gx/gy directions,
-- with ox/oy added as the user's manual offset. File-local = no per-call closure.
-- `step` is the icon size plus the gap between icons.
local function placeAura(frame, b, a, idx, perRow, step, ox, oy)
    local col = idx % perRow
    local row = math.floor(idx / perRow)
    b:ClearAllPoints()
    b:SetPoint(a.p, frame, a.rp,
        a.bx + ox + col * step * a.gx,
        a.by + oy + row * step * a.gy)
    b:Show()
end

-- 1px black border made of four textures (works on any frame/bar).
local function addBorder(frame)
    local b = {}
    local sides = {
        top    = { "TOPLEFT", "TOPRIGHT", nil, 1 },
        bottom = { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        left   = { "TOPLEFT", "BOTTOMLEFT", 1, nil },
        right  = { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }
    local Z = _G.ZacUI
    local P = Z and Z.Pixel
    for name, s in pairs(sides) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 1)
        t:SetPoint(s[1]); t:SetPoint(s[2])
        -- HD polish: one physical pixel under ZacUI's look (Core_Pixel);
        -- exactly 1 everywhere else
        if P then
            P.Edge(t, s[3] and (name == "left" and "LEFT" or "RIGHT") or (name == "top" and "TOP" or "BOTTOM"), frame)
        else
            if s[3] then t:SetWidth(s[3]) end
            if s[4] then t:SetHeight(s[4]) end
        end
        b[name] = t
    end
    return b
end

-- ----------------------------------------------------------------------------
-- Builders (called once per frame; every element is always created)
-- ----------------------------------------------------------------------------
local function buildOverlay(frame)
    local o = CreateFrame("Frame", nil, frame)
    o:SetAllPoints()
    o:SetFrameLevel(frame:GetFrameLevel() + 5)
    frame.Overlay = o

    -- Topmost host for status icons (rez, raid marker, combat, leader, role, PvP).
    -- A SEPARATE frame above the text overlay (+5) and castbar (+6) because WoW
    -- renders fontstrings above sibling textures in the same frame regardless of
    -- draw layer - icons sharing the Overlay always lose to the name text.
    local io = CreateFrame("Frame", nil, frame)
    io:SetAllPoints()
    io:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.IconOverlay = io
end

local function buildHealth(frame)
    local hb = CreateFrame("StatusBar", nil, frame)
    hb:SetFrameLevel(frame:GetFrameLevel() + 1)
    hb.bg = hb:CreateTexture(nil, "BACKGROUND")
    hb.bg:SetAllPoints()
    -- No own border: the bar sits 1px inside the frame's backdrop border, which is
    -- the single 1px edge. (A border here too produced a doubled ~2px black edge.)
    -- The health text lives on the Overlay, NOT on the bar itself. A chip frame
    -- parented to the health bar always draws after the bar's own regions, no
    -- matter what frame level it is given - so a FontString created here would
    -- sit under every incoming-heal chip and become unreadable the moment
    -- somebody starts healing. On the Overlay it is above the chips by
    -- construction. It stays anchored to the bar, so positioning is unchanged.
    hb.text = ns.UI:FS(frame.Overlay, 11)
    hb.text:SetPoint("CENTER", hb, "CENTER", 0, 0)
    frame.Health = hb
end

-- Incoming heals. Every frame that can show them is tracked in healPredFrames so
-- the heal provider's callbacks can find whichever frames currently display a
-- given GUID. The chips themselves are built lazily per frame in the renderer
-- below (they need per-segment labels and dot markers, so each is a small frame
-- rather than a bare texture); this only registers the frame and creates the
-- healer legend dot. Frames are created once and never destroyed.
local healPredFrames = {}

-- A white square + circular mask = a round, accurately tintable dot. Falls back
-- to a plain square where mask textures are unavailable. Created hidden.
local function maskedCircle(parent, sublevel)
    local t = parent:CreateTexture(nil, "OVERLAY", nil, sublevel)
    t:SetTexture(WHITE)
    if parent.CreateMaskTexture then
        local m = parent:CreateMaskTexture()
        m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
    end
    t:Hide()
    return t
end

local function buildHealPrediction(frame)
    -- Legend dot: lives on the icon overlay so it is never buried by the name
    -- strip or the heal chips themselves.
    frame.HealerDot = maskedCircle(frame.IconOverlay, 7)

    -- Total incoming healing, as a number. On the Overlay for the same reason the
    -- health text is: a fontstring on the health bar draws UNDER every chip frame
    -- parented to that bar, which would bury this exactly when it has something
    -- to say. Created hidden; the renderer shows it only while heals are inbound.
    local ht = ns.UI:FS(frame.Overlay, 11)
    ht:SetWordWrap(false)
    ht:Hide()
    frame.HealTotal = ht

    healPredFrames[frame] = true
end

local function buildPower(frame)
    local pb = CreateFrame("StatusBar", nil, frame)
    pb:SetFrameLevel(frame:GetFrameLevel() + 2)
    pb.bg = pb:CreateTexture(nil, "BACKGROUND")
    pb.bg:SetAllPoints()
    pb.bg:SetColorTexture(0, 0, 0, 0.6)
    frame.Power = pb
end

local function buildName(frame)
    local strip = frame.Overlay:CreateTexture(nil, "ARTWORK")
    frame.NameStrip = strip
    local name = ns.UI:FS(frame.Overlay, 12)
    name:SetWordWrap(false)
    frame.Name = name
end

local function buildCastbar(frame)
    local cb = CreateFrame("StatusBar", nil, frame)
    cb:SetFrameLevel(frame:GetFrameLevel() + 6)
    cb.bg = cb:CreateTexture(nil, "BACKGROUND")
    cb.bg:SetAllPoints()
    cb.bg:SetColorTexture(0, 0, 0, 0.7)
    cb.border = addBorder(cb)

    -- Sublevel 1: the statusbar fill texture lives on ARTWORK sublevel 0 and is
    -- created later (SetStatusBarTexture in styling), so at the same sublevel it
    -- would draw over the icon as the bar fills past it.
    cb.icon = cb:CreateTexture(nil, "ARTWORK", nil, 1)
    -- (match pass: the icon sits beside the fill in a 1 px frame of its own)
    ZacUI.Look.CropIcon(cb.icon, nil, nil, ns._matchApplied and { border = true } or nil)

    cb.spell = ns.UI:FS(cb, 11)
    cb.spell:SetJustifyH("LEFT")
    cb.spell:SetWordWrap(false)
    cb.timer = ns.UI:FS(cb, 11)
    cb.timer:SetJustifyH("RIGHT")

    cb:Hide()
    cb:SetScript("OnUpdate", function(self)
        if self.preview then return end          -- move-mode preview holds it static
        if self._ending then return end          -- playing its "cast over" animation
        local hid = self._zHidden
        if hid then
            -- WoW Forever, a hidden cast: the game's own timer drives the
            -- bar (ns.CastbarHidden); the time left as the game hands it
            -- over, straight onto the text
            if self.timerOn and hid.GetRemainingDuration then
                local ok, left = pcall(hid.GetRemainingDuration, hid)
                local Z = _G.ZacUI
                if ok and left ~= nil and Z and Z.ShowText then Z.ShowText(self.timer, "%.1f", left) end
            end
            return
        end
        if not self.endT then ns.CastbarEnd(self); return end
        local now = GetTime()
        if now >= self.endT then ns.CastbarEnd(self); return end
        -- seconds into the cast, not the clock itself (2026-10-31, a friend:
        -- "the cast bar wasnt smooth"): GetTime() counts from when the PC
        -- was switched on, and a status bar keeps its numbers in single
        -- precision - after a week or two of uptime a clock-sized value only
        -- moves in 1/16 to 1/8 s steps, so the fill went in jerks
        if self.channel then
            self:SetValue(self.endT - now)
        else
            self:SetValue(now - self.startT)
        end
        if self.timerOn then
            -- the text shows tenths, so it is only rebuilt when the
            -- tenth changes - not every frame
            local tenths = math.floor((self.endT - now) * 10)
            if self._tenths ~= tenths then
                self._tenths = tenths
                self.timer:SetText(string.format("%.1f", tenths / 10))
            end
        end
    end)
    frame.Castbar = cb
end

-- Status icons live on the IconOverlay, the frame's topmost layer - above the
-- bars, the name text, and the castbar - so rez / skull etc. are never hidden
-- behind other elements. Five textures (combat/leader/role/marker/rez, each
-- freely anchored per frame) plus a red "PvP" text with the flag countdown.
local function buildIndicators(frame)
    local o = frame.IconOverlay
    local ind = {}
    for _, k in ipairs({ "combat", "leader", "role", "raid", "rez" }) do
        local t = o:CreateTexture(nil, "OVERLAY")
        t:SetDrawLayer("OVERLAY", 7)
        t:Hide()
        ind[k] = t
    end
    -- Incoming-resurrection icon is a fixed texture (Blizzard's raid-frame rez
    -- symbol); set it once here and just show/hide it per state later.
    ind.rez:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
    local pt = ns.UI:FS(o, 10)
    pt:SetJustifyH("CENTER")
    pt:SetTextColor(0.95, 0.25, 0.25)   -- red PvP text
    pt:Hide()
    ind.pvpText = pt
    frame.Indicators = ind
end

-- One shared ticker drives the player's PvP flag countdown. It runs only while
-- the player is flagged with a finite timer and self-hides otherwise, so there
-- is no idle OnUpdate cost.
local function pvpTimeText(ms)
    local s = math.floor(ms / 1000)
    if s >= 60 then return string.format("%d:%02d", math.floor(s / 60), s % 60) end
    return tostring(s)
end

local pvpTicker = CreateFrame("Frame")
pvpTicker:Hide()
pvpTicker.t = 0
pvpTicker:SetScript("OnUpdate", function(self, e)
    self.t = self.t + e
    if self.t < 0.5 then return end
    self.t = 0
    local f = ns.frames and ns.frames.player
    local ind = f and f.Indicators
    if not ind then self:Hide(); return end
    if not f.hovered then ind.pvpText:Hide(); self:Hide(); return end   -- mouseover-only
    local ms = GetPVPTimer()
    if not UnitIsPVP("player") or not ms or ms <= 0 or ms == 301000 then
        if not UnitIsPVP("player") then ind.pvpText:Hide() end
        if UnitIsPVP("player") and f.cfg and f.cfg.pvpIcon then ind.pvpText:SetText("PvP") end
        self:Hide(); return
    end
    ind.pvpText:SetText("PvP " .. pvpTimeText(ms))
    ind.pvpText:Show()
end)

-- Every built frame (singles + header children). The move-mode previews
-- (isMock) are built the same way but kept out of this set and out of
-- healPredFrames: they never carry a unit, and every GUID sweep over these
-- sets would only walk past them.
ns.unitButtons = ns.unitButtons or {}

function ns.BuildElements(frame, isMock)
    frame._anchorTo = function(k) return ns.ElementTarget(frame, k) end
    frame._anchorDef = {}
    buildOverlay(frame)
    buildHealth(frame)
    buildHealPrediction(frame)
    if isMock then healPredFrames[frame] = nil end
    buildPower(frame)
    buildName(frame)
    frame.auraIcons = {}
    buildCastbar(frame)
    buildIndicators(frame)
    -- every element knows its key: the settings preview can say which one
    -- was clicked (ZacUI's "customize this element" hook)
    for _, list in ipairs({ ns.ANCHOR_TEXTS, ns.ANCHOR_PARTS }) do
        for _, k in ipairs(list) do
            local r = ns.ElementTarget(frame, k)
            if r then r._zElement = k end
        end
    end
    ns.StyleElements(frame)
    if not isMock then ns.unitButtons[frame] = true end
end

-- ----------------------------------------------------------------------------
-- Public frame lookup - WeakAuras / external anchoring
-- ----------------------------------------------------------------------------
-- Every ZacUF frame has a global name that matches LibGetFrame's generic oUF
-- patterns (oUF_ZacUFPlayer, oUF_ZacUFRaidG1UnitButton1, ...) and carries the
-- secure "unit" attribute, so WeakAuras' "Anchored To: Unit Frames" resolves
-- them deterministically on its own: raid / party children win the priority
-- pass, and the player / target / ToT singles sit in its ignore lists. This
-- lookup additionally serves WA custom anchor code and other addons, with the
-- same preference order: the group slot showing the unit wins (so "player" in
-- a raid resolves to your raid frame), then an exact-token single, then any
-- visible single showing the same unit.
function ns.GetUnitFrame(unit)
    if not unit or not ns.unitButtons then return nil end
    local single, alias
    for f in pairs(ns.unitButtons) do
        if f.unit and f:IsVisible() then
            if f.isGroupUnit then
                if UnitIsUnit(f.unit, unit) then return f end
            elseif f.unit == unit then
                single = single or f
            elseif not alias and UnitIsUnit(f.unit, unit) then
                alias = f
            end
        end
    end
    return single or alias
end
_G.ZacUF_GetUnitFrame = function(unit) return ns.GetUnitFrame(unit) end

-- ----------------------------------------------------------------------------
-- Event registration keyed off the per-frame toggles. Re-callable: registers
-- the events for enabled elements and unregisters those for disabled ones, so
-- toggling an element off also stops its events.
-- ----------------------------------------------------------------------------
function ns.RegisterFrameEvents(frame)
    local unit = frame.unit
    if not unit then return end
    local cfg = frame.cfg or {}

    frame:RegisterUnitEvent("UNIT_HEALTH", unit)
    frame:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
    frame:RegisterUnitEvent("UNIT_CONNECTION", unit)

    if cfg.power then
        frame:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
        frame:RegisterUnitEvent("UNIT_MAXPOWER", unit)
        frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit)
    else
        frame:UnregisterEvent("UNIT_POWER_UPDATE")
        frame:UnregisterEvent("UNIT_MAXPOWER")
        frame:UnregisterEvent("UNIT_DISPLAYPOWER")
    end

    if cfg.name then frame:RegisterUnitEvent("UNIT_NAME_UPDATE", unit)
    else frame:UnregisterEvent("UNIT_NAME_UPDATE") end

    -- UNIT_AURA is the busiest event a raid frame sees. Only a frame that
    -- shows aura icons, or can tint or glow for a dispel this character
    -- actually has, listens; a toggle re-runs this via LeanRestyle /
    -- bindUnit, a dispel learned or a Felhunter summoned via
    -- refreshPlayerDispels below. The event itself only marks the frame
    -- (ns.AuraDirty); the walk runs a moment later, once per burst.
    if cfg.showBuffs or cfg.showDebuffs or (dispelLooks() and playerDispels) then frame:RegisterUnitEvent("UNIT_AURA", unit)
    else frame:UnregisterEvent("UNIT_AURA") end

    if cfg.castbar then
        for _, ev in ipairs(CAST_EVENTS) do frame:RegisterUnitEvent(ev, unit) end
    else
        for _, ev in ipairs(CAST_EVENTS) do frame:UnregisterEvent(ev) end
    end

    -- UNIT_HEAL_PREDICTION is the native totals; only the native backend
    -- reads them. A per-healer library repaints through ns.Heal.onChanged
    -- (LibHealPredict listens to this event itself).
    if cfg.healPrediction and not (ns.Heal:Ready() and ns.Heal.perCaster) then
        frame:RegisterUnitEvent("UNIT_HEAL_PREDICTION", unit)
    else
        frame:UnregisterEvent("UNIT_HEAL_PREDICTION")
    end

    -- Status icons. These events are infrequent (combat enter/leave, roster /
    -- leader / marker / pvp-flag changes), so global registration even across 40
    -- raid children is fine. Unit events stay unit-filtered (O(1)).
    if cfg.combatIcon then
        frame:RegisterUnitEvent("UNIT_FLAGS", unit)
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        frame:UnregisterEvent("UNIT_FLAGS")
        frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end

    -- Leader / assist / main-tank icons follow the roster through ONE
    -- module-level sweep (bottom of this file), not forty frames each
    -- answering every GROUP_ROSTER_UPDATE.

    if cfg.raidIcon then frame:RegisterEvent("RAID_TARGET_UPDATE")
    else frame:UnregisterEvent("RAID_TARGET_UPDATE") end

    -- Incoming-res is registered UNFILTERED (plain RegisterEvent), like the roster
    -- and marker events above, not RegisterUnitEvent. The secure header can hand a
    -- child a unit token that doesn't match the token the event fires with, so a
    -- unit-filtered registration silently drops the res on raid frames - which is
    -- exactly why no icon ever showed. It's cheap: it only fires during an actual
    -- res cast, and each frame re-checks its OWN unit in UpdateIndicators.
    if cfg.rezIcon then frame:RegisterEvent("INCOMING_RESURRECT_CHANGED")
    else frame:UnregisterEvent("INCOMING_RESURRECT_CHANGED") end

    if cfg.pvpIcon then
        frame:RegisterUnitEvent("UNIT_FACTION", unit)
        frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
    else
        frame:UnregisterEvent("UNIT_FACTION")
        frame:UnregisterEvent("PLAYER_FLAGS_CHANGED")
    end
end

-- ----------------------------------------------------------------------------
-- Styling (re-applies media/colors/sizes AND show/hide per toggle; re-callable)
-- ----------------------------------------------------------------------------
function ns.StyleElements(frame)
    local db   = ns.db
    local cfg  = frame.cfg or {}
    local barT = ns.Media:Statusbar(db.media.bar)
    local font = ns.Media:Font(db.media.font)

    local powerOn = cfg.power and true or false
    local nameOn  = cfg.name and true or false
    local powerH  = (powerOn and db.power.height) or 0
    local stripOn = nameOn and db.name.showStrip
    local D = fillAnchorDefaults(frame, cfg, frame._anchorDef or {})
    frame._anchorDef = D

    -- Health (fills the frame minus the power strip)
    local hb = frame.Health
    hb:ClearAllPoints()
    -- (HD polish: inside an edge one physical pixel wide under ZacUI's
    -- look, Core_Pixel; one unit everywhere else)
    local Z = _G.ZacUI
    local px = Z and Z.Pixel and Z.Pixel.One(frame) or 1
    hb:SetPoint("TOPLEFT", px, -px)
    hb:SetPoint("TOPRIGHT", -px, -px)
    hb:SetPoint("BOTTOM", frame, "BOTTOM", 0, powerH + px)
    hb:SetStatusBarTexture(barT)
    hb.bg:SetTexture(barT)
    hb.bg:SetVertexColor(u(db.colors.healthBg))
    if ns._matchApplied then
        -- match pass (ZacUI's look): the fill at 90% (db.health.fillAlpha)
        -- and the background behind the missing part only, riding the
        -- fill's moving edge (anchors: nothing to redo per health tick)
        local fill = hb:GetStatusBarTexture()
        if type(fill) == "table" and fill.SetAlpha then
            fill:SetAlpha(tonumber(db.health and db.health.fillAlpha) or 0.9)
            hb.bg:ClearAllPoints()
            hb.bg:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
            hb.bg:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 0, 0)
        end
    end
    ns.ApplyFont(hb.text, "health")
    hb.text:SetTextColor(uc(db.colors.healthText, 0.85, 0.85, 0.85, 1))
    place(frame, hb.text, "healthText", D.healthText)

    -- Per-healer heal chips are created lazily by UpdateHealPrediction and get
    -- their texture from the heal config ("flat" or "glossy"), not the bar
    -- texture, so a matte chip reads as a different material than the health
    -- fill. Only their size/color/anchor is per-render, so nothing to do here
    -- beyond clearing stale ones and re-placing the legend dot.
    if frame.healSegs then
        for _, seg in ipairs(frame.healSegs) do seg:Hide() end
    end
    if ns.UpdateHealerDot then ns.UpdateHealerDot(frame) end

    -- Incoming-heal total: font, anchor and offset from the shared heal config.
    -- Hidden here on every restyle; the renderer brings it back on the next
    -- repaint if anything is actually inbound, so a settings change can never
    -- leave a stale number pinned to the frame.
    local ht = frame.HealTotal
    if ht then
        local _, htSize = ns.FontSpec("healTotal")
        ns.ApplyFont(ht, "healTotal", math.max(6, htSize))
        -- Pinned to the health TEXT, so the pair reads as one line wherever that
        -- text is anchored. Both live on the Overlay, so this is a plain sibling
        -- anchor. Note the health string changes width as the value does ("9%"
        -- vs "100%"), which walks this number a few px with it - the cost of
        -- staying glued to the text instead of to a fixed point on the frame.
        -- With health text off the string is empty and zero-width, so this
        -- collapses to its anchor point, which is still a sane place to sit.
        -- (worked out in fillAnchorDefaults: LEFT_OF_HP / RIGHT_OF_HP or a
        -- 9-point spot on the frame)
        place(frame, ht, "healTotal", D.healTotal)
        ht:Hide()
        -- Drop the render cache: color, format and the "+" prefix are all baked
        -- into the cached string, so a settings change has to invalidate it.
        frame._htVal, frame._htState, frame._htProj = nil, nil, nil
    end

    -- Power (bottom strip) - shown only when enabled
    local pb = frame.Power
    if not place(frame, pb, "power", D.power) then pb:SetWidth(math.max(1, (cfg.width or 100) - 2)) end
    pb:SetHeight(math.max(1, powerH))
    pb:SetStatusBarTexture(barT)
    pb.bg:SetColorTexture(uc(db.colors.powerBg, 0, 0, 0, 0.6))
    pb:SetShown(powerOn)

    -- Name strip + text (on the overlay, above the bars)
    local strip, nm = frame.NameStrip, frame.Name
    local a = NA()[cfg.nameAnchor] or NA().LEFT
    local vy = a.y
    if a.vert == "BOTTOM" then vy = a.y + powerH end

    strip:SetTexture(ns.Media:Statusbar(db.media.nameBar))
    strip:SetVertexColor(u(db.colors.nameBg))
    strip:SetHeight(db.name.height)
    strip:SetShown(stripOn)
    if not place(frame, strip, "nameStrip", D.nameStrip) then strip:SetWidth(math.max(1, (cfg.width or 100) - 2)) end

    -- (cfg.nameSize: this frame's own name size, the match pass's 10 on
    -- party and raid; nil = the one name size)
    ns.ApplyFont(nm, "name", tonumber(cfg.nameSize))
    nm:SetWordWrap(false)
    -- The name uses the full interior width; the lead/assist/tank icons sit in
    -- the top-left corner and simply overlay it (small icons over the first
    -- character or two) rather than shrinking the name field -- a wide field that
    -- shows most of a long name beats one trimmed down to a bare "...". Only the
    -- HP value still claims room, and only when it shares the name's row.
    -- A floor keeps a name from ever collapsing to nothing on a tiny frame.
    local nameFloor = math.min((cfg.width or 100) - 8, 32)
    if stripOn then
        nm:SetWidth(math.max(nameFloor, (cfg.width or 100) - 10))
    else
        local avail = (cfg.width or 100) - 8
        if nameOn and cfg.healthText and cfg.healthText ~= "none" and a.vert ~= "OUT" then
            local hpv = (NA()[cfg.hpAnchor] or NA().RIGHT).vert
            if hpv == a.vert then avail = avail - 32 end  -- HP on the same row -> leave room for it
        end
        if avail < nameFloor then avail = nameFloor end
        nm:SetWidth(avail)
    end
    place(frame, nm, "name", D.name)
    nm:SetShown(nameOn)

    -- Castbar: per-frame anchor + offset + size. cbWidth 0 = match the frame width,
    -- cbHeight 0 = use the global castbar height. Hidden unless enabled + casting.
    local cb = frame.Castbar
    local cbc = db.castbar
    local cbA = NA()[cfg.cbAnchor] or NA().BELOW
    local cbW = (cfg.cbWidth and cfg.cbWidth > 0) and cfg.cbWidth or (cfg.width or 100)
    local cbH = (cfg.cbHeight and cfg.cbHeight > 0) and cfg.cbHeight or db.castbar.height
    ns.CastbarStopMotion(cb)   -- never re-anchor a bar mid-animation
    place(frame, cb, "castbar", D.castbar)
    local matchIcon = ns._matchApplied and db.castbar.showIcon
    -- (match pass: the icon's square comes off the bar's width)
    cb:SetSize(matchIcon and math.max(1, cbW - cbH) or cbW, cbH)
    cb:SetStatusBarTexture(cbc.texture and ns.Media:Statusbar(cbc.texture) or barT)
    cb.bg:SetColorTexture(uc(cbc.bgColor, 0, 0, 0, 0.7))
    if cb.border then
        local br, bgc, bb, ba = uc(cbc.borderColor, 0, 0, 0, 1)
        for _, t in pairs(cb.border) do t:SetColorTexture(br, bgc, bb, ba) end
    end
    if cb.icon then
        local isz = matchIcon and cbH or math.max(1, cbH - 2)
        if not place(frame, cb.icon, "castIcon", D.castIcon) then cb.icon:SetHeight(isz) end
        cb.icon:SetWidth(isz)
        cb.icon:SetShown(db.castbar.showIcon)
    end
    local iconPad = (db.castbar.showIcon and (cbH + 2)) or 4
    if not place(frame, cb.spell, "castText", D.castText) then cb.spell:SetWidth(math.max(1, cbW - iconPad - 34)) end
    ns.ApplyFont(cb.spell, "castbar")
    place(frame, cb.timer, "castTime", D.castTime)
    -- (match pass: the time a size under the spell name, 10, unless one is saved)
    local cbSpec = ns._matchApplied and ns.FontSpec("castbar")
    ns.ApplyFont(cb.timer, "castbar", (ns._matchApplied and not (cbSpec and cbSpec.size)) and 10 or nil)
    local tr, tg, tb, ta = uc(cbc.textColor, 0.85, 0.85, 0.85, 1)
    cb.spell:SetTextColor(tr, tg, tb, ta)
    cb.timer:SetTextColor(tr, tg, tb, ta)
    cb.timerOn = db.castbar.showTime
    cb.timer:SetShown(db.castbar.showTime)
    if not cfg.castbar then cb:Hide() end

    -- Auras
    for _, b in ipairs(frame.auraIcons) do ns.StyleAuraIcon(b) end
    if not (cfg.showBuffs or cfg.showDebuffs) then
        for _, b in ipairs(frame.auraIcons) do b:Hide() end
    end

    -- Status icons: size + per-frame anchor placement (combat/leader/role/marker).
    -- PvP is laid out as red text at its anchor with the faction crest to its left.
    -- Actual show/hide is driven per-unit by UpdateIndicators; here we only hide
    -- ones whose per-frame toggle is off so they never linger after being disabled.
    local ind = frame.Indicators
    if ind then
        -- Each icon type has its own size (cfg.combatSize / leaderSize / roleSize /
        -- raidSize); fall back to a legacy shared size then a sane constant.
        local fallbackSz = cfg.iconSize or (db.indicators and db.indicators.size) or 14
        for _, k in ipairs({ "combat", "leader", "role", "raid", "rez" }) do
            local t = ind[k]
            local ksz = cfg[k .. "Size"] or fallbackSz
            t:SetSize(ksz, ksz)
            place(frame, t, k, D[k])
            if not cfg[k .. "Icon"] then t:Hide() end
        end
        -- PvP: red text at its anchor, with its own size.
        local psz = math.max(8, cfg.pvpSize or (fallbackSz - 4))
        if not TrySetFont(ind.pvpText, font, psz, "OUTLINE") then
            ind.pvpText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", psz, "OUTLINE")
        end
        place(frame, ind.pvpText, "pvpText", D.pvpText)
        if not cfg.pvpIcon then ind.pvpText:Hide() end
    end

    -- the dispel and AoE-taunt glows (Glows.lua) take a new colour,
    -- thickness or pulse; nothing to do on a frame that never glowed
    if ns.GlowRestyle then ns.GlowRestyle(frame) end
end

-- ----------------------------------------------------------------------------
-- Smooth bars: health and power glide to a new value instead of jumping.
-- One driver for every frame, running only while some bar is still moving
-- (most of the time nothing is). A bar snaps when it starts showing a
-- different unit (target swap, raid shuffle) so it never slides from the
-- last one's health. Settles in about ns.db.smoothTime (0.15 s); the
-- global Motion speed divides that, Motion off or ns.db.smoothBars = false
-- puts back the plain jump.
-- ----------------------------------------------------------------------------
local smoothing = {}
local smoother = CreateFrame("Frame")
smoother:Hide()

-- the approach rate for a glide of `smoothTime` seconds (0.15 s -> 18, the
-- rate it always had)
local function smoothRate()
    local t = tonumber(ns.db and ns.db.smoothTime) or 0.15
    if t < 0.02 then t = 0.02 end
    local Mo = Motion()
    if Mo and Mo.Speed then t = t / Mo.Speed() end
    return 2.7 / t
end

local function smoothOff()
    if ns.db and ns.db.smoothBars == false then return true end
    local Mo = Motion()
    return Mo ~= nil and Mo.Enabled ~= nil and not Mo.Enabled()
end

smoother:SetScript("OnUpdate", function(self, elapsed)
    local k = math.min(1, (elapsed or 0.016) * smoothRate())
    local any = false
    for bar, target in pairs(smoothing) do
        local cur = bar._zsv or target
        local mn, mx = bar:GetMinMaxValues()
        local nxt = cur + (target - cur) * k
        if math.abs(target - nxt) <= ((mx or 1) - (mn or 0)) * 0.002 then
            nxt = target
            smoothing[bar] = nil
        else
            any = true
        end
        bar._zsv = nxt
        bar:SetValue(nxt)
    end
    if not any then self:Hide() end
end)

local function SmoothValue(bar, value, guid)
    if bar._zsv == nil or bar._zsg ~= guid or smoothOff() then
        smoothing[bar] = nil
        bar._zsv, bar._zsg = value, guid
        bar:SetValue(value)
        return
    end
    if value == bar._zsv then
        smoothing[bar] = nil
        return
    end
    smoothing[bar] = value
    smoother:Show()
end

-- ----------------------------------------------------------------------------
-- Updates (per-unit; each early-outs when its element is disabled)
-- ----------------------------------------------------------------------------
-- WoW Forever hides health in combat (secret values: no compare, no
-- arithmetic). The bar and its text still take them as they are: the bar
-- straight from the two values (no glide: a glide is maths), the text
-- from the number and the game's own percent (ZacUI's display helpers,
-- Core_Flavor). A saved text format can't be filled from hidden values,
-- so the frame's text mode is drawn the plain way while they are hidden;
-- abbreviating (12.3k) is the game's AbbreviateNumbers when it takes the
-- value, else the whole number. The remembered values the plain path
-- compares against are cleared, so it picks up cleanly afterwards.
local function hiddenNumber(v)
    if AbbreviateNumbers then
        local ok, s = pcall(AbbreviateNumbers, v)
        if ok and s ~= nil then return "%s", s end
    end
    return "%d", v
end
local function PaintHiddenHealth(frame, unit, cur, max, online, status, r, g, b)
    local hb = frame.Health
    local Z = _G.ZacUI
    if not (Z and Z.ShowBar) then return end
    smoothing[hb] = nil
    hb._zsv, hb._zsg, hb._pct, frame._maxhp = nil, nil, nil, nil
    if not Z.ShowBar(hb, cur, max) then return end
    if r ~= frame._cr or g ~= frame._cg or b ~= frame._cb then
        hb:SetStatusBarColor(r, g, b)
        frame._cr, frame._cg, frame._cb = r, g, b
    end
    local a = online and 1 or 0.55
    if a ~= frame._alpha then frame:SetAlpha(a * (frame._visAlpha or 1)); frame._alpha = a end
    local mode = (frame.cfg and frame.cfg.healthText) or "percent"
    if status then
        hb.text:SetText(status)
    elseif mode == "none" then
        hb.text:SetText("")
    elseif mode == "current" then
        local f, v = hiddenNumber(cur)
        Z.ShowText(hb.text, f, v)
    else
        local pct = Z.HealthPercent(unit)
        if mode == "both" then
            local f, v = hiddenNumber(cur)
            if pct ~= nil then Z.ShowText(hb.text, f .. "  %.0f%%", v, pct) else Z.ShowText(hb.text, f, v) end
        elseif pct ~= nil then
            Z.ShowText(hb.text, "%.0f%%", pct)
        else
            hb.text:SetText("")
        end
    end
end

function ns.UpdateHealth(frame)
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    -- (WoW Forever: hidden in combat - shown as it is, PaintHiddenHealth)
    local hidden = issecretvalue ~= nil and (issecretvalue(cur) or issecretvalue(max))
    local online = UnitIsConnected(unit)
    local r, g, b
    if online then r, g, b = ns.UnitColor(unit, frame) else r, g, b = 0.45, 0.45, 0.45 end
    -- Offline / feign / dead override the chosen text mode so they're always
    -- visible. Feign Death is checked before dead because a feigning hunter
    -- reads as dead to the rest of the group.
    local status
    if not online then status = "Offline"
    elseif UnitIsFeignDeath and UnitIsFeignDeath(unit) then status = "FD"
    elseif UnitIsDead(unit) or UnitIsGhost(unit) then status = "Dead" end
    if hidden then
        -- (no incoming-heal chips while the health is hidden: they are
        -- placed by maths on it)
        PaintHiddenHealth(frame, unit, cur, max, online, status, r, g, b)
        return
    end
    ns.PaintHealth(frame, cur, max, UnitGUID(unit), online, status, r, g, b)
    if frame.cfg and frame.cfg.healPrediction then ns.UpdateHealPrediction(frame) end
end

-- The health bar from plain values - the live update above and the
-- settings preview's sample frames both paint through this.
-- The health text's format defaults, per health-text mode: what each mode
-- always showed, as a template (cfg.formats.healthText overrides).
local HP_FORMAT_DEFAULTS
local HP_FORMAT_DEFAULTS_T = {
    current = { template = "[cur]" },
    both    = { template = "[cur]  [pct]%" },
    percent = { template = "[pct]%" },
}
HP_FORMAT_DEFAULTS = HP_FORMAT_DEFAULTS_T
ns.HP_FORMAT_DEFAULTS = HP_FORMAT_DEFAULTS_T
ns.HP_FORMAT_KINDS = { cur = "number", max = "number", deficit = "number", pct = "percent" }
ns.HP_FORMAT_TOKENS = { { token = "cur", label = "Current" }, { token = "max", label = "Most" },
    { token = "deficit", label = "Missing" }, { token = "pct", label = "Percent" } }

-- The frame's visibility rule (ZacUI's visibility shape, cfg.visibility),
-- composed with its own offline dim: the evaluator says what it wants, this
-- moves the alpha. Alpha only - safe on the secure frames in combat.
local VIS_FADE = { style = "fade", duration = 0.2, easing = "linear" }
function ns.VisibilityApply(frame, allowed, a)
    frame._visAlpha = a
    local target = (frame._alpha or 1) * (a or 1)
    local cur = frame:GetAlpha() or 1
    local v = frame.cfg and frame.cfg.visibility
    local dur = type(v) == "table" and tonumber(target > cur and v.fadeIn or v.fadeOut) or nil
    if dur == nil then dur = (target > cur) and 0.2 or 0.3 end
    local Z = _G.ZacUI
    if Z and Z.Motion and Z.Motion.FadeTo and dur > 0 and a ~= nil then
        VIS_FADE.duration = dur
        Z.Motion.FadeTo(frame, target, VIS_FADE)
    else
        frame:SetAlpha(target)
    end
end

function ns.PaintHealth(frame, cur, max, guid, online, status, r, g, b)
    local hb = frame.Health

    -- max only changes on UNIT_MAXHEALTH, so skip the SetMinMaxValues churn otherwise
    if max ~= frame._maxhp then
        hb:SetMinMaxValues(0, max > 0 and max or 1)
        frame._maxhp = max
        hb._zsv = nil                     -- a new scale: snap to it
    end
    SmoothValue(hb, cur, guid)

    -- Bar colour: grey when offline, else class/reaction. Only push to the texture
    -- when it actually changed - the class colour is constant for a raid member, so
    -- this skips a SetStatusBarColor on every single damage tick.
    if r ~= frame._cr or g ~= frame._cg or b ~= frame._cb then
        hb:SetStatusBarColor(r, g, b)
        frame._cr, frame._cg, frame._cb = r, g, b
    end

    -- Dim the whole frame when offline; again only on transition.
    local a = online and 1 or 0.55
    if a ~= frame._alpha then frame:SetAlpha(a * (frame._visAlpha or 1)); frame._alpha = a end

    -- Text (skipped cheaply for raid frames, which default to "none"). Offline /
    -- feign / dead override the chosen mode so they're always visible, even on
    -- raid frames with text off. Feign Death is checked before dead because a
    -- feigning hunter reads as dead to the rest of the group.
    local mode = (frame.cfg and frame.cfg.healthText) or "percent"
    local fmts = frame.cfg and frame.cfg.formats
    local fmt = type(fmts) == "table" and fmts.healthText or nil
    if fmt and not status and mode ~= "none" then
        -- the frame's own text format (ZacUI's text format shape): only with
        -- one saved, so the plain paths below stay exactly as they were
        local v = frame._hpVals
        if not v then v = {} frame._hpVals = v end
        v.cur, v.max, v.deficit = cur, max, max - cur
        v.pct = max > 0 and (cur / max * 100) or 0
        hb._pct = nil
        local Z = _G.ZacUI
        if Z and Z.FormatText then
            hb.text:SetText(Z.FormatText(fmt, HP_FORMAT_DEFAULTS[mode] or HP_FORMAT_DEFAULTS.percent, v, ns.HP_FORMAT_KINDS))
        end
    elseif status then
        hb._pct = nil
        hb.text:SetText(status)
    elseif mode == "none" then
        hb._pct = nil
        hb.text:SetText("")
    elseif mode == "current" then
        hb._pct = nil
        hb.text:SetText(ns.Short(cur))
    elseif mode == "both" then
        hb._pct = nil
        hb.text:SetText(("%s  %d%%"):format(ns.Short(cur), max > 0 and math.floor(cur / max * 100) or 0))
    else
        -- UNIT_HEALTH is the hot one; the percent string is only rebuilt
        -- when the whole number changes
        local pct = max > 0 and math.floor(cur / max * 100) or 0
        if hb._pct ~= pct then
            hb._pct = pct
            hb.text:SetText(("%d%%"):format(pct))
        end
    end
end

-- ----------------------------------------------------------------------------
-- Incoming-heal display.
--
-- One colored chip per healer, stacked rightward from the health fill in landing
-- order: your own heals in the own-heal color, every other healer in their class
-- color (or a stable per-healer slot color), anything past the visible cap merged
-- into one grey "+N" chip. HoTs are dimmed, or flattened to one uniform color, or
-- hidden entirely. Optional per-chip markers name the healer - a colored dot, or
-- their initials - and a matching legend dot sits on that healer's own frame.
--
-- All data comes from ns.Heal (Heal.lua), which normalizes LibHealPredict,
-- LibHealComm-4.0 and the built-in UnitGetIncomingHeals behind one call. Colors
-- come from ns.HealColors (HealColors.lua). Nothing here knows which library is
-- in use. Everything is gated per frame by the Heal toggle (cfg.healPrediction).
--
-- This is the HealVision display, absorbed into ZacUF's own frames.
-- ----------------------------------------------------------------------------
local OVERFLOW_COLOR = { 0.55, 0.55, 0.55, 0.9 }   -- neutral grey for the merged "+N" chip
local LABEL_SIZES = { 9, 8, 7 }

local function healCfg() return ns.db.heal end
local renderHeals            -- defined after UpdateHealPrediction, which calls it
local chipList = {}          -- the preview's filtered heal list, reused

-- Repaint every visible frame showing a GUID whose heals changed. Heal
-- events come in bursts (a raid's worth of casts starting and landing),
-- so the GUIDs are only noted here and every frame is checked once, on
-- the next frame, against the whole set.
local healPending = {}
local healFlushArmed = false
local function flushHealRepaints()
    healFlushArmed = false
    for f in pairs(healPredFrames) do
        local unit = f.unit
        if unit and f.cfg and f.cfg.healPrediction and f:IsVisible() then
            local g = UnitGUID(unit)
            if g and healPending[g] then ns.UpdateHealPrediction(f) end
        end
    end
    wipe(healPending)
end

local function refreshFramesForGUID(guid)
    if not guid then return end
    healPending[guid] = true
    if not healFlushArmed then
        healFlushArmed = true
        C_Timer.After(0, flushHealRepaints)
    end
end

-- A caster was seen healing for the first time: light up their legend dot.
local function refreshDotForGUID(guid)
    if not guid then return end
    for f in pairs(healPredFrames) do
        local unit = f.unit
        if unit and f:IsVisible() and UnitGUID(unit) == guid then
            ns.UpdateHealerDot(f)
        end
    end
end

-- Heals appear, change and vanish without any health change, so UNIT_HEALTH
-- alone cannot drive the display: the provider calls these on every heal event.
ns.Heal.onChanged = refreshFramesForGUID
ns.Heal.onCaster  = refreshDotForGUID

-- A roster change can re-map every GUID in the group, so repaint everything that
-- is currently on screen rather than trying to work out who moved.
ns.Heal.onRoster = function()
    for f in pairs(healPredFrames) do
        if f.unit and f.cfg and f.cfg.healPrediction and f:IsVisible() then
            ns.UpdateHealPrediction(f)
        end
        ns.UpdateHealerDot(f)
    end
end

-- ----------------------------------------------------------------------------
-- Chip pool
-- ----------------------------------------------------------------------------
-- Each chip is a small frame rather than a bare texture because it carries a
-- fill, a left divider, top/bottom edges, a centered label and a dot marker.
-- Created lazily per frame and reused; never destroyed.
local function getHealSeg(frame, i)
    local segs = frame.healSegs
    if not segs then segs = {}; frame.healSegs = segs end
    local seg = segs[i]
    if seg then return seg end

    seg = CreateFrame("Frame", nil, frame.Health)
    seg:Hide()

    seg.fill = seg:CreateTexture(nil, "ARTWORK")
    seg.fill:SetAllPoints()

    -- Left edge: a bright spark at the health -> heal boundary on the first chip,
    -- a thin dark separator between adjacent chips otherwise. Without it two
    -- same-colored healers side by side read as one long chip.
    local div = seg:CreateTexture(nil, "OVERLAY")
    div:SetPoint("TOPLEFT"); div:SetPoint("BOTTOMLEFT")
    div:SetWidth(1)
    div:Hide()
    seg.divider = div

    -- Dark outline framing each chip. Top and bottom only: a right edge would
    -- overlap the next chip's separator and read as a doubled, too-loud line.
    local function edge(anchorA, anchorB, h)
        local t = seg:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 0.7)
        t:SetPoint(anchorA); t:SetPoint(anchorB)
        t:SetHeight(h)
        t:Hide()
        return t
    end
    seg.edgeTop    = edge("TOPLEFT", "TOPRIGHT", 1)
    seg.edgeBottom = edge("BOTTOMLEFT", "BOTTOMRIGHT", 1)

    seg.count = ns.UI:FS(seg, 9)
    seg.count:SetPoint("CENTER")
    seg.count:Hide()

    -- Dot marker: dark backing ring + colored dot, so it stays legible even when
    -- the chip fill happens to be the same color.
    seg.dotBG = maskedCircle(seg, 6)
    seg.dotBG:SetVertexColor(0, 0, 0, 0.8)
    seg.dotBG:SetPoint("CENTER")
    seg.dot = maskedCircle(seg, 7)
    seg.dot:SetPoint("CENTER")

    segs[i] = seg
    return seg
end

local function hideHealSegs(frame, fromIndex)
    local segs = frame.healSegs
    if not segs then return end
    for i = fromIndex or 1, #segs do segs[i]:Hide() end
end

-- ----------------------------------------------------------------------------
-- Incoming-heal total (the number)
-- ----------------------------------------------------------------------------
-- Exact under 10k, abbreviated above. Classic health pools are small enough that
-- rounding a 2,450 heal to "2.5k" throws away the precision you are reading the
-- number FOR; six-digit numbers, on the other hand, do not fit on a raid frame.
-- "full" and "short" force one or the other.
local function healNumber(n, fmt)
    n = math.floor(n + 0.5)
    if fmt == "full" then return tostring(n) end
    if fmt == "short" then return ns.Short(n) end
    if n >= 10000 then return ns.Short(n) end
    return tostring(n)
end

local function hideHealTotal(frame)
    if frame.HealTotal then frame.HealTotal:Hide() end
end

-- The number is never clamped to missing health. A clamped number reads as
-- "exactly enough" at the very moment that stopped being true, which is the one
-- thing this display must not do. The COLOR carries the judgment instead.
--
-- Coverage mode answers the dps question - back out, or commit? - by projecting
-- where the inbound heals land you and coloring that: green = they top you off,
-- yellow = they help but you are still exposed, red = what is coming will not
-- save you. Note this is deliberately the OPPOSITE reading from a healer's:
-- "more incoming than missing health" is wasted mana to them and a green light
-- to you, which is why overheal is a mode rather than the default.
--
-- Returns the color plus a small integer state, so the caller can cache on it.
local function totalColor(tc, total, cur, max)
    local mode = tc.colorMode or "coverage"
    if mode == "flat" then return tc.color, 0 end
    if mode == "overheal" then
        if total > (max - cur) then return tc.overhealColor, 1 end
        return tc.color, 0
    end
    -- coverage
    if max <= 0 then return tc.color, 0 end
    local projected = cur + total
    if projected > max then projected = max end
    local pct = projected / max * 100
    if pct >= (tc.safePct or 90) then return tc.safeColor, 3 end
    if pct >= (tc.partialPct or 55) then return tc.partialColor, 2 end
    return tc.lowColor, 1
end

local function showHealTotal(frame, total, cur, max)
    local fs = frame.HealTotal
    if not fs then return end
    local cfg = healCfg()
    local tc = cfg and cfg.total
    if not tc or not tc.enabled then fs:Hide(); return end

    total = math.floor((total or 0) + 0.5)
    if total < 1 then fs:Hide(); return end

    local c, state = totalColor(tc, total, cur, max)
    -- Projected health is the same figure the coverage color is derived from,
    -- spelled out for when the color alone is not precise enough.
    local proj
    if tc.showProjected and max > 0 then
        local p = cur + total
        if p > max then p = max end
        proj = math.floor(p / max * 100)
    end

    -- Rebuild the string only when the rounded amount, the color state or the
    -- projected percent actually changed. This runs for every visible frame on
    -- every health tick, and a concatenation plus a string.format per frame per
    -- tick is exactly the churn Heal.lua's entry pooling exists to avoid. The
    -- cache is cleared in StyleElements so an options change is not swallowed.
    if total ~= frame._htVal or state ~= frame._htState or proj ~= frame._htProj then
        frame._htVal, frame._htState, frame._htProj = total, state, proj
        fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        local txt = ((tc.prefix ~= false) and "+" or "") .. healNumber(total, tc.format)
        if proj then txt = txt .. ("  %d%%"):format(proj) end
        fs:SetText(txt)
    end
    fs:Show()
end

-- Fit a centered label ("+N" or initials) into width w: shrink the font a couple
-- of steps, then as a last resort drop trailing letters, so something shows on a
-- narrow chip instead of nothing. Returns true if it fit.
local function fitLabel(fs, text, w)
    local font = ns.Media:Font(ns.db.media.font)
    for _, size in ipairs(LABEL_SIZES) do
        if not TrySetFont(fs, font, size, "OUTLINE") then
            fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
        end
        fs:SetText(text)
        if fs:GetStringWidth() + 1 <= w then return true end
    end
    for chars = #text - 1, 1, -1 do   -- smallest size already set; trim letters
        fs:SetText(text:sub(1, chars))
        if fs:GetStringWidth() + 1 <= w then return true end
    end
    return false
end

-- ----------------------------------------------------------------------------
-- Chip colors
-- ----------------------------------------------------------------------------
-- Category color: own heals, or a uniform HoT color. These outrank per-healer
-- coloring and survive even in uniform-fill mode. Returns nil for a normal heal.
-- Resolved lazily: UnitGUID("player") is nil at file-load time, and this is hot
-- enough (once per chip, per frame, per repaint) to not want a call per chip.
local myGUID
local function playerGUID()
    if not myGUID then myGUID = UnitGUID("player") end
    return myGUID
end

local function categoryColor(e)
    local db = healCfg()
    if e.generic then return nil end
    if db.ownHeal.enabled and (e.own or (e.casterGUID and e.casterGUID == playerGUID())) then
        local c = db.ownHeal.color
        return c[1], c[2], c[3], (e.isHot and 0.6 or 1)
    end
    if e.isHot and db.hot.uniform then
        local c = db.hot.color
        return c[1], c[2], c[3], 1
    end
    return nil
end

-- The healer's own identifying color, HoTs dimmed. Also the dot-marker color, so
-- the dot keeps its meaning when the fill is flattened to uniform.
local function sourceColor(e)
    local db = healCfg()
    local r, g, b, a = categoryColor(e)
    if r then return r, g, b, a end
    if e.generic then
        local c = ns.db.colors.incomingHeal
        return c[1], c[2], c[3], c[4] or 1
    end
    if e.previewClass then   -- a settings-preview healer: no GUID to look up
        r, g, b = ns.HealColors:PreviewColor(e.previewClass, e.previewSlot)
    else
        r, g, b = ns.HealColors:GetColor(e.casterGUID)
    end
    a = db.segment.alpha or 0.85
    if e.isHot then a = a * 0.6 end
    return r, g, b, a
end

-- The chip FILL. "uniform" replaces only the per-healer color with one flat
-- color (HoTs still dimmed); own-heal and uniform-HoT keep their colors either way.
local function fillColor(e)
    local db = healCfg()
    if db.segment.fill == "uniform" then
        local r, g, b, a = categoryColor(e)
        if r then return r, g, b, a end
        local c = db.segment.uniformColor
        return c[1], c[2], c[3], (e.isHot and 0.6 or 1) * (db.segment.alpha or 0.85)
    end
    return sourceColor(e)
end

-- ----------------------------------------------------------------------------
-- Healer legend dot
-- ----------------------------------------------------------------------------
local function positionDot(frame, dot, cfg)
    dot:ClearAllPoints()
    dot:SetSize(cfg.size, cfg.size)
    local p = cfg.position
    -- IsShown, not just existence: the name FontString is always built and merely
    -- hidden when the frame's Name toggle is off, so anchoring to it would park
    -- the dot on a zero-width invisible region.
    if p == "LEFT_OF_NAME" and frame.Name and frame.Name:IsShown() then
        dot:SetPoint("RIGHT", frame.Name, "LEFT", -2, 0)
    elseif p == "TOPLEFT" then
        dot:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    elseif p == "TOPRIGHT" then
        dot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    elseif p == "BOTTOMRIGHT" then
        dot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    else   -- BOTTOMLEFT, and the fallback when the name is hidden
        dot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)
    end
end

-- A persistent dot on a healer's OWN frame, in the color their incoming-heal
-- chips use. Shown only for units we have actually seen heal AND that are a
-- healing class, so off-spec heals and not-yet-cached units don't leave a stray
-- grey dot. Follows the frame's heal toggle: no chips shown, no legend needed.
function ns.UpdateHealerDot(frame)
    local dot = frame.HealerDot
    if not dot then return end
    local cfg = healCfg() and healCfg().dot
    if not cfg or not cfg.enabled
        or not (frame.cfg and frame.cfg.healPrediction)
        or (cfg.hideInCombat and UnitAffectingCombat("player")) then
        dot:Hide(); return
    end
    local unit = frame.unit
    if not unit or not UnitExists(unit) then dot:Hide(); return end
    local guid = UnitGUID(unit)
    if not guid or not ns.Heal.knownHealers[guid] or not ns.HealColors:IsHealer(guid) then
        dot:Hide(); return
    end
    dot:SetVertexColor(ns.HealColors:GetColor(guid))
    positionDot(frame, dot, cfg)
    dot:Show()
end

-- The legend dot for a settings-preview healer (class + slot instead of a
-- GUID), placed and gated exactly like the live one.
function ns.PaintHealerDot(frame, class, slot)
    local dot = frame.HealerDot
    if not dot then return end
    local cfg = healCfg() and healCfg().dot
    if not class or not cfg or not cfg.enabled or not (frame.cfg and frame.cfg.healPrediction) then
        dot:Hide(); return
    end
    dot:SetVertexColor(ns.HealColors:PreviewColor(class, slot))
    positionDot(frame, dot, cfg)
    dot:Show()
end

function ns.RefreshHealerDots()
    for f in pairs(healPredFrames) do ns.UpdateHealerDot(f) end
end

-- Combat state changes re-evaluate every dot (for the hide-in-combat option).
local healCombatWatcher = CreateFrame("Frame")
healCombatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
healCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
healCombatWatcher:SetScript("OnEvent", function() ns.RefreshHealerDots() end)

-- ----------------------------------------------------------------------------
-- Render
-- ----------------------------------------------------------------------------
-- Draw one chip of the render in progress (its state is in `chip`).
-- Returns false only when the bar has no room left. File-level, not a
-- closure per render: this runs for every frame on every health tick.
local chip = {}
local function drawChip(amount, r, g, b, a, labelText, dotR, dotG, dotB)
    local st = chip
    if st.room <= 0 then return false end
    if amount > st.room then amount = st.room end
    st.room = st.room - amount
    local w = st.barW * (amount / st.max)
    if w < 1 then return true end   -- too thin to see, but keep walking the list

    st.shown = st.shown + 1
    local s = getHealSeg(st.frame, st.shown)
    if s.__tex ~= st.texPath then       -- only swap the texture when it changes
        s.fill:SetTexture(st.texPath)
        s.__tex = st.texPath
    end
    s.fill:SetVertexColor(r, g, b, a or 1)
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", st.fillTex, "TOPRIGHT", st.offset, 0)
    s:SetSize(w, st.barH)
    s:SetFrameLevel(st.level)

    if st.shown == 1 then
        if st.seg.spark then
            s.divider:SetColorTexture(1, 1, 1, 0.95)
            s.divider:SetWidth(2)
            s.divider:Show()
        else
            s.divider:Hide()
        end
    else
        s.divider:SetColorTexture(0, 0, 0, 0.45)   -- quiet separator between healers
        s.divider:SetWidth(1)
        s.divider:Show()
    end

    if st.seg.outline then s.edgeTop:Show(); s.edgeBottom:Show()
    else s.edgeTop:Hide(); s.edgeBottom:Hide() end

    if dotR then
        local ds = st.barH - 2
        if ds > 12 then ds = 12 elseif ds < 4 then ds = 4 end
        if w >= ds + 2 then
            s.dot:SetSize(ds, ds); s.dotBG:SetSize(ds + 2, ds + 2)
            s.dot:SetVertexColor(dotR, dotG, dotB, 1)
            s.dotBG:Show(); s.dot:Show()
        else
            s.dotBG:Hide(); s.dot:Hide()
        end
        s.count:Hide()
    elseif labelText and labelText ~= "" then
        if fitLabel(s.count, labelText, w) then s.count:Show() else s.count:Hide() end
        s.dotBG:Hide(); s.dot:Hide()
    else
        s.count:Hide(); s.dotBG:Hide(); s.dot:Hide()
    end

    s:Show()
    st.offset = st.offset + w
    return true
end

function ns.UpdateHealPrediction(frame)
    local db = healCfg()
    if not db then return end

    if frame.cfg and not frame.cfg.healPrediction then
        hideHealSegs(frame)
        hideHealTotal(frame)
        if frame.HealerDot then frame.HealerDot:Hide() end
        return
    end

    local unit = frame.unit
    if not unit or not UnitExists(unit) then hideHealSegs(frame); hideHealTotal(frame); return end
    local guid = UnitGUID(unit)
    if not guid then hideHealSegs(frame); hideHealTotal(frame); return end

    local list, n = ns.Heal:Query(guid, unit, db.window, db.hot.show)
    if n == 0 then hideHealSegs(frame); hideHealTotal(frame); ns.Heal:Release(); return end

    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    -- (Forever: hidden health in combat - no chips until it reads again)
    if issecretvalue ~= nil and (issecretvalue(cur) or issecretvalue(max)) then
        hideHealSegs(frame); hideHealTotal(frame); ns.Heal:Release(); return
    end
    if max <= 0 then hideHealSegs(frame); hideHealTotal(frame); ns.Heal:Release(); return end
    renderHeals(frame, list, n, cur, max)
    ns.Heal:Release()
end

-- The chips and the number for a list of incoming heals (landing order) on a
-- unit at cur / max health. The live path above and the settings preview's
-- samples (ns.PaintHeals) both draw through this.
function renderHeals(frame, list, n, cur, max)
    local db = healCfg()

    -- The number is summed from the FULL query result, before the chip cap and
    -- before anything is clamped to the bar: it has to account for the healers
    -- who merged into the "+N" chip and for the part running past full, or it
    -- would disagree with itself the moment a fifth healer joined in.
    -- Set here rather than after the chip loop so it still shows on a unit that
    -- is already topped off - "3 heals inbound, all of it wasted" is the case
    -- where seeing the number matters most.
    local incoming = 0
    for i = 1, n do incoming = incoming + (list[i].amount or 0) end
    showHealTotal(frame, incoming, cur, max)

    local hb = frame.Health
    local barW, barH = hb:GetWidth(), hb:GetHeight()
    local fillTex = hb:GetStatusBarTexture()

    -- Room on the bar. `overheal` lets chips run past full by a percentage of the
    -- bar, which is how you see that a heal is going to be wasted; 0 clamps at full.
    local room = max - cur
    local overPct = (db.overheal or 0) / 100
    if overPct > 0 then room = room + max * overPct end
    if room <= 0 then hideHealSegs(frame); return end

    local seg = db.segment
    local texPath = (seg.texture == "glossy") and "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" or WHITE
    -- Chips always draw over the health FILL - a child frame cannot render below
    -- its parent's regions - so this option is really "over or under the text".
    --   behind (default): level +2, above the bar but below the Overlay at +5,
    --                     so the name and health text stay readable through a
    --                     heal. This is the HealBars look.
    --   front:            level +7, above the Overlay - chips dominate and will
    --                     cover the name and health text while heals are inbound.
    local level = (seg.layer == "front")
        and (frame:GetFrameLevel() + 7)   -- above the name overlay (+5), below status icons (+10)
        or (frame:GetFrameLevel() + 3)    -- above health (+1) and power (+2), below the overlay (+5)
    local marker = seg.marker or "none"

    local st = chip
    st.frame, st.room, st.barW, st.barH, st.max = frame, room, barW, barH, max
    st.texPath, st.fillTex, st.level, st.seg = texPath, fillTex, level, seg
    st.offset, st.shown = 0, 0

    -- With more healers than the cap, the last visible slot merges the rest.
    local cap = db.maxSegments or 4
    local individual = (n > cap) and (cap - 1) or n

    for i = 1, individual do
        local e = list[i]
        local r, g, b, a = fillColor(e)
        local ok
        if marker == "dot" and not e.generic then
            local dr, dg, dbl = sourceColor(e)
            ok = drawChip(e.amount, r, g, b, a, nil, dr, dg, dbl)
        elseif marker == "initials" and not e.generic then
            ok = drawChip(e.amount, r, g, b, a,
                e.previewName and e.previewName:sub(1, 3) or ns.HealColors:GetInitials(e.casterGUID))
        else
            ok = drawChip(e.amount, r, g, b, a)
        end
        if not ok then break end
    end

    if individual < n and st.room > 0 then
        local sum, cnt = 0, 0
        for i = individual + 1, n do sum = sum + list[i].amount; cnt = cnt + 1 end
        if sum > 0 then
            drawChip(sum, OVERFLOW_COLOR[1], OVERFLOW_COLOR[2], OVERFLOW_COLOR[3], OVERFLOW_COLOR[4], "+" .. cnt)
        end
    end

    hideHealSegs(frame, st.shown + 1)
    st.frame = nil
end

-- Heals on a sample frame, from a list of entries the preview made up:
-- { amount =, isHot =, own =, previewClass =, previewSlot =, previewName =, generic = }.
-- Follows the frame's Incoming heals toggle like the live frames do.
function ns.PaintHeals(frame, list, cur, max)
    local db = healCfg()
    if not db or not frame.Health then return end
    if not (frame.cfg and frame.cfg.healPrediction) or not list or #list == 0 or (max or 0) <= 0 then
        hideHealSegs(frame); hideHealTotal(frame); return
    end
    local n = 0
    for i = 1, #list do
        local e = list[i]
        if db.hot.show or not e.isHot then
            n = n + 1
            chipList[n] = e
        end
    end
    for i = n + 1, #chipList do chipList[i] = nil end
    if n == 0 then hideHealSegs(frame); hideHealTotal(frame); return end
    renderHeals(frame, chipList, n, cur, max)
end

-- Preview chips for the mock frames in move mode. Mocks carry no unit, so the
-- real renderer can't run on them; this paints two representative chips - a
-- direct heal from another healer and a dimmed HoT - through the same pool and
-- the same appearance settings, so what you position is what you get.
function ns.MockHealChips(frame, hp)
    local db = healCfg()
    if not db or not frame.Health then return end
    if not (frame.cfg and frame.cfg.healPrediction) or hp >= 0.98 then
        hideHealSegs(frame); hideHealTotal(frame); return
    end

    local hb = frame.Health
    local barW, barH = hb:GetWidth(), hb:GetHeight()
    local fillTex = hb:GetStatusBarTexture()
    if barW <= 0 then hideHealSegs(frame); hideHealTotal(frame); return end

    -- Sample number for the preview. Mocks carry no unit, so the two sample chips
    -- are scaled against the player's own max health - a real number on the right
    -- order of magnitude, so what you position is the width you will actually get.
    local sampleMax = (UnitHealthMax("player") or 0)
    if (issecretvalue ~= nil and issecretvalue(sampleMax)) or sampleMax <= 0 then sampleMax = 4200 end
    showHealTotal(frame, (1 - hp) * sampleMax, hp * sampleMax, sampleMax)

    local seg = db.segment
    local texPath = (seg.texture == "glossy") and "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" or WHITE
    local level = (seg.layer == "front") and (frame:GetFrameLevel() + 7) or (frame:GetFrameLevel() + 3)
    local room = (1 - hp) * barW

    -- Sample: your own direct heal, then someone else's HoT.
    local samples = {
        { frac = 0.55, color = db.ownHeal.color, hot = false },
        { frac = 0.45, color = nil,              hot = true  },
    }

    local offset, shown = 0, 0
    for _, s in ipairs(samples) do
        local w = room * s.frac
        if w >= 1 then
            shown = shown + 1
            local chip = getHealSeg(frame, shown)
            if chip.__tex ~= texPath then chip.fill:SetTexture(texPath); chip.__tex = texPath end
            local r, g, b
            if s.color then
                r, g, b = s.color[1], s.color[2], s.color[3]
            else
                r, g, b = 0.30, 0.55, 0.95   -- stand-in healer color (no real GUID here)
            end
            local a = (seg.alpha or 0.85) * (s.hot and 0.6 or 1)
            chip.fill:SetVertexColor(r, g, b, a)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", offset, 0)
            chip:SetSize(w, barH)
            chip:SetFrameLevel(level)
            if shown == 1 and seg.spark then
                chip.divider:SetColorTexture(1, 1, 1, 0.95); chip.divider:SetWidth(2); chip.divider:Show()
            elseif shown > 1 then
                chip.divider:SetColorTexture(0, 0, 0, 0.45); chip.divider:SetWidth(1); chip.divider:Show()
            else
                chip.divider:Hide()
            end
            if seg.outline then chip.edgeTop:Show(); chip.edgeBottom:Show()
            else chip.edgeTop:Hide(); chip.edgeBottom:Hide() end
            chip.count:Hide(); chip.dot:Hide(); chip.dotBG:Hide()
            chip:Show()
            offset = offset + w
        end
    end
    hideHealSegs(frame, shown + 1)
end

-- ----------------------------------------------------------------------------
-- Diagnostics (/zuf heal why)
-- ----------------------------------------------------------------------------
-- Explain, for the moused-over or targeted unit, exactly what is tracked and why
-- each chip is the color it is. The empty case is the important one: a visible
-- chip with nothing tracked here is not ZacUF's rendering.
function ns.HealWhy()
    local unit = (UnitExists("mouseover") and "mouseover")
        or (UnitExists("target") and "target") or "player"
    local guid = UnitGUID(unit)
    local db = healCfg()
    ns.Print(("heal: %s - backend %s, colors %s, window %ds"):format(
        UnitName(unit) or unit, tostring(ns.Heal.backend), ns.HealColors:GetMode(), db.window))

    if not guid then ns.Print("heal: no GUID for that unit.") return end
    local list, n = ns.Heal:Query(guid, unit, db.window, db.hot.show)
    if n == 0 then
        ns.Print("heal: NO incoming heals tracked for this unit. If a heal chip is visible on this frame right now, it is NOT drawn by ZacUF.")
        ns.Heal:Release()
        return
    end
    for i = 1, n do
        local e = list[i]
        local r, g, b = sourceColor(e)
        local hex = ("|cff%02x%02x%02x#%02x%02x%02x|r"):format(
            r * 255, g * 255, b * 255, r * 255, g * 255, b * 255)
        local src
        if e.generic then
            src = "unattributed (native API reports totals only)"
        elseif db.ownHeal.enabled and e.casterGUID == playerGUID() then
            src = "own-heal color"
        else
            local _, class = GetPlayerInfoByGUID(e.casterGUID)
            if not class then src = "unresolved GUID -> neutral grey"
            elseif ns.HealColors:GetMode() == "class" then src = "class color for " .. class
            else src = "slot color" end
        end
        ns.Print(("heal: #%d %.0f from %s -> %s (%s)%s"):format(
            i, e.amount or 0, ns.Heal:CasterLabel(e.casterGUID), hex, src,
            e.isHot and " [HoT]" or ""))
    end

    -- The same sum the on-frame number shows, with the projection its color is
    -- derived from, so a number that looks wrong can be checked against inputs.
    local total = 0
    for i = 1, n do total = total + (list[i].amount or 0) end
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if issecretvalue ~= nil and (issecretvalue(cur) or issecretvalue(max)) then
        ns.Print("heal: health is hidden right now (in combat on this game version).")
        return
    end
    local proj = cur + total
    if proj > max then proj = max end
    ns.Print(("heal: total incoming %s vs %d missing - lands you at %d%%%s"):format(
        healNumber(total, db.total and db.total.format),
        max - cur,
        max > 0 and math.floor(proj / max * 100) or 0,
        (total > (max - cur)) and (" (%.0f overheal)"):format(total - (max - cur)) or ""))

    ns.Heal:Release()
end

-- Status line for /zuf heal.
function ns.HealStatus()
    local db = healCfg()
    -- How HoTs are tracked depends on the backend, and the answer has to be
    -- backend-specific: reporting the LibHealComm aura path as healthy while
    -- LibHealPredict is live would hide a total loss of HoT tracking.
    local hotPath
    if ns.Heal.backend == "LibHealPredict" then
        hotPath = ("aura scan driven by ZacUF, precise timing %s"):format(
            db.preciseHots and "ON" or "off")
    elseif ns.Heal.backend == "LibHealComm-4.0" then
        hotPath = ("AuraUtil.FindAuraByName %s"):format(
            (AuraUtil and AuraUtil.FindAuraByName) and "ok" or "|cffff5555MISSING|r")
    else
        hotPath = "|cffff5555none - this backend has no HoT support|r"
    end
    local on = {}
    for _, k in ipairs({ "player", "target", "targettarget", "pet" }) do
        if ns.db.frames[k] and ns.db.frames[k].healPrediction then on[#on + 1] = k end
    end
    if ns.db.party.healPrediction then on[#on + 1] = "party" end
    if ns.db.raid.healPrediction  then on[#on + 1] = "raid"  end
    ns.Print(("heal: backend %s (%s), colors %s, %d caster(s) active."):format(
        tostring(ns.Heal.backend),
        ns.Heal.perCaster and "per-healer" or "totals only",
        ns.HealColors:GetMode(), ns.Heal:ActiveCasters()))
    ns.Print(("heal: HoTs %s - %s"):format(db.hot.show and "on" or "off", hotPath))
    ns.Print(("heal: shown on %s.  /zuf heal why | spy | class | slot"):format(
        #on > 0 and table.concat(on, ", ") or "|cffff8888no frames - enable Heal per frame in /zuf|r"))
    if not ns.Heal.perCaster then
        ns.Print("|cffffcc00heal: this source cannot say WHO is healing, so per-healer colors, markers and the legend dot are inactive. Both bundled libraries failed to load - check for Lua errors.|r")
    end
end

local POWER_FALLBACK = { r = 0.4, g = 0.4, b = 0.8 }   -- reused, never per-call allocated
-- The power colour: the client's PowerBarColor, or under the match pass
-- (ZacUI's look) the reference's palette for the four Classic powers.
local MATCH_POWER = {
    MANA = { r = 0.000, g = 0.550, b = 1.000 }, RAGE = { r = 0.900, g = 0.150, b = 0.150 },
    FOCUS = { r = 0.867, g = 0.573, b = 0.216 }, ENERGY = { r = 1.000, g = 0.960, b = 0.410 },
    RUNIC_POWER = { r = 0.769, g = 0.122, b = 0.231 },
}
local MATCH_POWER_IDX = { [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY", [6] = "RUNIC_POWER" }
function ns.PowerColor(ptoken, ptype)
    if ns._matchApplied then
        local m = (ptoken and MATCH_POWER[ptoken]) or (ptype and MATCH_POWER[MATCH_POWER_IDX[ptype] or ""])
        if m then return m end
    end
    local PBC = PowerBarColor
    return PBC and ((ptoken and PBC[ptoken]) or (ptype and PBC[ptype])) or POWER_FALLBACK
end

function ns.UpdatePower(frame)
    if not frame.Power or (frame.cfg and not frame.cfg.power) then return end
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    local ptype, ptoken = UnitPowerType(unit)
    local cur, max = UnitPower(unit), UnitPowerMax(unit)
    if issecretvalue ~= nil and (issecretvalue(cur) or issecretvalue(max)) then
        -- WoW Forever may hide power too: the bar straight from the values
        local Z, pb = _G.ZacUI, frame.Power
        if Z and Z.ShowBar then
            smoothing[pb] = nil
            pb._zsv, pb._zsg, frame._maxpp = nil, nil, nil
            Z.ShowBar(pb, cur, max)
        end
        local c = ns.PowerColor(ptoken, ptype)
        if c.r ~= frame._pcr or c.g ~= frame._pcg or c.b ~= frame._pcb then
            pb:SetStatusBarColor(c.r, c.g, c.b)
            frame._pcr, frame._pcg, frame._pcb = c.r, c.g, c.b
        end
        return
    end
    ns.PaintPower(frame, cur, max, UnitGUID(unit), ptoken, ptype)
end

-- The power bar from plain values (live update and preview samples).
-- ptoken / ptype: the power token ("RAGE") and index, looked up in the
-- client's colours (the token first).
function ns.PaintPower(frame, cur, max, guid, ptoken, ptype)
    local pb = frame.Power
    -- max changes only on UNIT_MAXPOWER, so skip the SetMinMaxValues churn on the
    -- frequent rage/energy ticks (Bloodrage fires a burst of these).
    if max ~= frame._maxpp then
        pb:SetMinMaxValues(0, max > 0 and max or 1)
        frame._maxpp = max
        pb._zsv = nil
    end
    SmoothValue(pb, cur, guid)

    -- The bar colour is constant for a given power type (rage stays rage), so only
    -- push it to the texture when it actually changes - not on every rage tick.
    local c = ns.PowerColor(ptoken, ptype)
    if c.r ~= frame._pcr or c.g ~= frame._pcg or c.b ~= frame._pcb then
        pb:SetStatusBarColor(c.r, c.g, c.b)
        frame._pcr, frame._pcg, frame._pcb = c.r, c.g, c.b
    end
end

function ns.UpdateName(frame)
    if not frame.Name or (frame.cfg and not frame.cfg.name) then return end
    local unit = frame.unit
    -- (WoW Forever: the surname as Core_Names says; elsewhere UnitName)
    local Z = _G.ZacUI
    local n = unit and ((Z and Z.UnitDisplayName) and Z.UnitDisplayName(unit) or UnitName(unit)) or ""
    ns.PaintName(frame, n, ns.NameColor(unit, frame))
end

local nameVals = {}
local NAME_KINDS = { name = "name" }
function ns.PaintName(frame, text, r, g, b)
    local fmts = frame.cfg and frame.cfg.formats
    local fmt = type(fmts) == "table" and fmts.name or nil
    local Z = fmt and _G.ZacUI
    if Z and Z.FormatText then
        nameVals.name = text or ""
        text = Z.FormatText(fmt, nil, nameVals, NAME_KINDS, "name")
        nameVals.name = nil
    end
    -- match pass (ZacUI's look): a party / raid name is cut to its first 15
    -- letters (cfg.nameMax; 0 = no cut) before the width trims it
    local cfg = frame.cfg
    local cap = cfg and (cfg.nameMax or (ns._matchApplied and ns.db and (cfg == ns.db.party or cfg == ns.db.raid) and 15))
    if cap and cap > 0 and type(text) == "string" and not (issecretvalue ~= nil and issecretvalue(text))
       and #text > cap then
        local n, cut = 0, #text
        for pos in text:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
            n = n + 1
            if n > cap then cut = pos - 1 break end
        end
        text = text:sub(1, cut)
    end
    frame.Name:SetText(text or "")
    frame.Name:SetTextColor(r, g, b)
end

-- size, edge colour and stack-number text of one aura icon (new icons and
-- every restyle)
function ns.StyleAuraIcon(b)
    local ac = ns.db.auras
    b:SetSize(ac.size, ac.size)
    local r, g, bl, a = uc(ac.borderColor, 0, 0, 0, 1)
    if b.border then
        for _, t in pairs(b.border) do t:SetColorTexture(r, g, bl, a) end
    end
    ns.ApplyFont(b.count, "auraCount")
    b.count:SetTextColor(uc(ac.countColor, 0.85, 0.85, 0.85, 1))
    local Z = _G.ZacUI
    if Z and Z.ApplyAnchor then
        Z.ApplyAnchor(b.count, type(ac.anchors) == "table" and ac.anchors.count or nil,
            (b.swipe and AURA_COUNT_DEF_HD) or AURA_COUNT_DEF)
    end
end

-- HD POLISH (2026-11-07, ZacUI's look only; zui_tests/HD_POLISH_STANDARD_1107.md):
-- the 1px ring sits OVER the icon's edge (it was on the BORDER layer, under
-- the icon, so it never showed), the crop is the lighter 0.07 that ring
-- allows (unless an icon zoom is set by hand), a debuff's ring takes the HD
-- dispel colour, and auras of 5 minutes or less get a reversed dark sweep.
local HD_CROP, HD_SWIPE_MAX = 0.07, 300
local HD_DISPEL = {
    Magic   = { 0.35, 0.48, 1.00 },
    Curse   = { 0.64, 0.00, 0.64 },
    Disease = { 0.67, 0.38, 0.10 },
    Poison  = { 0.00, 0.71, 0.29 },
}
local HD_UNTYPED = { 0.80, 0.10, 0.10 }
local function hdLook()
    local Z = _G.ZacUI
    return Z and Z.Look and Z.Look.Active and Z.Look.Active() == "zacui" or false
end
ns.AuraHD = hdLook

local function getAuraIcon(frame, i)
    local b = frame.auraIcons[i]
    if not b then
        b = CreateFrame("Frame", nil, frame)
        b:SetFrameLevel(frame:GetFrameLevel() + 7)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        local hd = hdLook()
        -- (2026-11-08) one crop for every icon: ZacUI's own, which hides
        -- the game's icon border (the lighter 0.07 let it show)
        ZacUI.Look.CropIcon(b.icon)
        b.border = addBorder(b)
        if hd then
            for _, t in pairs(b.border) do t:SetDrawLayer("OVERLAY", 6) end
            local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
            if ok and cd then
                local Z = _G.ZacUI
                local one = (Z and Z.Pixel and Z.Pixel.One(b)) or 1
                cd:SetPoint("TOPLEFT", b, "TOPLEFT", one, -one)
                cd:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -one, one)
                if cd.SetReverse then cd:SetReverse(true) end
                if cd.SetDrawEdge then cd:SetDrawEdge(false) end
                if cd.SetDrawBling then cd:SetDrawBling(false) end
                if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.6) end
                if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
                cd.noCooldownCount = true
                cd:Hide()
                b.swipe = cd
                -- the stack number above the sweep
                b.textHost = CreateFrame("Frame", nil, b)
                b.textHost:SetAllPoints(b)
                b.textHost:SetFrameLevel(b:GetFrameLevel() + 2)
            end
        end
        b.count = ns.UI:FS(b.textHost or b, 10)
        b.count:SetPoint("BOTTOMRIGHT", 1, -1)
        ns.StyleAuraIcon(b)
        frame.auraIcons[i] = b
    end
    return b
end

-- One icon's HD dress for the aura it now shows: the ring's colour (a
-- debuff's dispel type; `debuff` false = a buff) and the sweep. Under any
-- other look it returns at once.
local function hdAura(b, debuff, dispelType, duration, expires)
    if not b.swipe then return end
    local ac = ns.db.auras
    local c
    if debuff then
        c = (type(dispelType) == "string" and not (issecretvalue and issecretvalue(dispelType)) and HD_DISPEL[dispelType]) or HD_UNTYPED
    end
    if c then
        for _, t in pairs(b.border) do t:SetColorTexture(c[1], c[2], c[3], 1) end
        b._hdTint = true
    elseif b._hdTint then
        b._hdTint = nil
        local r, g, bl, a = uc(ac.borderColor, 0, 0, 0, 1)
        for _, t in pairs(b.border) do t:SetColorTexture(r, g, bl, a) end
    end
    if type(duration) == "number" and type(expires) == "number"
        and not (issecretvalue and (issecretvalue(duration) or issecretvalue(expires)))
        and duration > 0 and duration <= HD_SWIPE_MAX then
        if b._hdExp ~= expires then
            b._hdExp = expires
            b.swipe:SetCooldown(expires - duration, duration)
        end
        b.swipe:Show()
    else
        b._hdExp = nil
        b.swipe:Hide()
    end
end

-- Whitelist match: an entry matches by spell ID (exact) or by localized name
-- (case-insensitive, matches every rank). Empty list -> nothing matches.
local function auraListMatch(list, name, spellID)
    if not list then return false end
    local lname = name and string.lower(name)
    for _, e in ipairs(list) do
        if e.id and spellID and e.id == spellID then return true end
        if e.name and lname and e.name == lname then return true end
    end
    return false
end

-- Aura scanning compat. 1.15.7 exposes the classic UnitAura(unit, index,
-- filter) multi-return; the 1.15.9 client (2.5.6-era shared UI code) removes
-- it in favor of C_UnitAuras.GetAuraDataByIndex, which returns a table. Both
-- paths are normalized to the six values the renderer needs. The modern path
-- is preferred whenever it exists so the exact code that will run on 1.15.9
-- is the code being exercised today.
--
-- WoW Forever hands addons "secret" aura values in combat, which may not be
-- compared or used as a table key. An aura with a secret name, type or ID
-- reads as "no aura" here (the same answer ZacUI's Core_Forever stand-ins
-- give), so on Forever the icons, the tint and the dispel glow go quiet in
-- combat instead of throwing. issecretvalue does not exist on Era or TBC.
--
-- On the Forever client itself an aura like that is no longer dropped:
-- scanAura answers false plus the aura's table, and the icon grid shows
-- its icon and stacks straight from it (the game takes hidden values as
-- they are; see showHiddenAura). A read the game refuses answers false
-- with no table and the walk goes past it. The filters that need its
-- name, caster or type can't see it; "only mine" asks the game's
-- never-hidden "from you" flag.
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local isSecret = issecretvalue
local hiddenClient = _G.ZACUI_MODERN and true or false
local scanAura
if GetAuraDataByIndex then
    scanAura = function(unit, index, filter)
        local a
        if hiddenClient then
            local ok, r = pcall(GetAuraDataByIndex, unit, index, filter)
            if not ok then return false, nil end
            a = r
        else
            a = GetAuraDataByIndex(unit, index, filter)
        end
        if not a then return nil end
        if isSecret and (isSecret(a.name) or isSecret(a.dispelName) or isSecret(a.spellId)
            or (hiddenClient and (isSecret(a.applications) or isSecret(a.sourceUnit)))) then
            if hiddenClient then return false, a end
            return nil
        end
        return a.name, a.icon, a.applications, a.sourceUnit, a.spellId, a.dispelName, a.duration, a.expirationTime
    end
elseif UnitAura then
    scanAura = function(unit, index, filter)
        local name, icon, count, dispelType, duration, expires, source, _, _, spellID = UnitAura(unit, index, filter)
        return name, icon, count, source, spellID, dispelType, duration, expires
    end
end

-- ----------------------------------------------------------------------------
-- Dispellable debuffs (what this character can remove right now)
-- ----------------------------------------------------------------------------
-- The class kit, used only on a client with no spell-known check at all.
-- Warlock's Devour Magic belongs to the Felhunter, so it is not here; the
-- spell list below covers it while that pet is out.
local CLASS_DISPELS = {
    PRIEST  = { Magic = true, Disease = true },
    PALADIN = { Magic = true, Poison = true, Disease = true },
    DRUID   = { Curse = true, Poison = true },
    SHAMAN  = { Poison = true, Disease = true },
    MAGE    = { Curse = true },
}

-- Spell by spell, every rank: what removes what. The IDs are the same on
-- Era and TBC (TBC adds Mass Dispel and the Felhunter's ranks 5 and 6,
-- which simply are not known on Era). `pet`: a pet spell (known only while
-- that pet is out); `noRange`: never used for the range check (a totem has
-- no target, Mass Dispel is aimed at the ground).
local DISPEL_SPELLS = {
    PRIEST  = { { ids = { 527, 988 }, types = { Magic = true } },                  -- Dispel Magic
                { ids = { 528, 552 }, types = { Disease = true } },                -- Cure / Abolish Disease
                { ids = { 32375 }, types = { Magic = true }, noRange = true } },    -- Mass Dispel (TBC)
    PALADIN = { { ids = { 4987 }, types = { Magic = true, Poison = true, Disease = true } },  -- Cleanse
                { ids = { 1152 }, types = { Poison = true, Disease = true } } },   -- Purify
    DRUID   = { { ids = { 2782 }, types = { Curse = true } },                      -- Remove Curse
                { ids = { 8946, 2893 }, types = { Poison = true } } },             -- Cure / Abolish Poison
    MAGE    = { { ids = { 475 }, types = { Curse = true } } },                     -- Remove Lesser Curse
    SHAMAN  = { { ids = { 526 }, types = { Poison = true } },                      -- Cure Poison
                { ids = { 2870 }, types = { Disease = true } },                    -- Cure Disease
                { ids = { 8166 }, types = { Poison = true }, noRange = true },     -- Poison Cleansing Totem
                { ids = { 8170 }, types = { Disease = true }, noRange = true } },  -- Disease Cleansing Totem
    WARLOCK = { { ids = { 19505, 19731, 19734, 19736, 27276, 27277 }, types = { Magic = true }, pet = true } }, -- Devour Magic
}
ns.DISPEL_SPELLS = DISPEL_SPELLS

local function knows(id, pet)
    if pet then
        if IsSpellKnown then
            local ok, r = pcall(IsSpellKnown, id, true)
            if ok and r then return true end
        end
        return false
    end
    if IsPlayerSpell then
        local ok, r = pcall(IsPlayerSpell, id)
        if ok and r then return true end
    end
    if IsSpellKnown then
        local ok, r = pcall(IsSpellKnown, id)
        if ok and r then return true end
    end
    return false
end

-- the Felhunter by its family name, for when its spell is not readable
-- (English only: UnitCreatureFamily is localised; IsSpellKnown(id, true)
-- is the real check)
local function felhunterOut()
    if not (UnitExists and UnitExists("pet")) then return false end
    local fam = UnitCreatureFamily and UnitCreatureFamily("pet")
    return fam == "Felhunter"
end

-- What `class` can remove right now: { Magic = true, ... } or nil, and for
-- each type the name of a spell that removes it, for the range check.
local dispelRange = {}
function ns.ComputeDispels(class)
    local list = DISPEL_SPELLS[class]
    if not list then return nil, {} end
    local range = {}
    if not (IsPlayerSpell or IsSpellKnown) then
        -- no spell API on this client: the class kit
        local kit = CLASS_DISPELS[class]
        if class == "WARLOCK" and felhunterOut() then kit = { Magic = true } end
        return kit, range
    end
    local out, any = {}, false
    for _, e in ipairs(list) do
        local known
        for _, id in ipairs(e.ids) do
            if knows(id, e.pet) then known = id break end
        end
        if not known and e.pet and felhunterOut() then known = e.ids[1] end
        if known then
            for t in pairs(e.types) do
                out[t], any = true, true
                if not range[t] and not e.pet and not e.noRange and GetSpellInfo then
                    range[t] = GetSpellInfo(known)
                end
            end
        end
    end
    return any and out or nil, range
end

-- the spell to range-check a debuff type with (nil: no such spell)
function ns.DispelRangeSpell(dtype) return dispelRange[dtype] end
-- what the player can remove right now (nil = nothing)
function ns.PlayerDispels() return playerDispels end

local function dispelKey(t)
    if not t then return "" end
    return (t.Magic and "M" or "") .. (t.Curse and "C" or "") .. (t.Poison and "P" or "") .. (t.Disease and "D" or "")
end

-- Work it out again (a dispel learned, a Felhunter summoned or sent
-- away): a change re-registers UNIT_AURA on every frame (a class that can
-- now dispel starts listening) and repaints their auras.
local function refreshPlayerDispels()
    local _, class = UnitClass("player")
    local was = dispelKey(playerDispels)
    playerDispels, dispelRange = ns.ComputeDispels(class)   -- playerDispels: declared at the top of the file
    dispelRange = dispelRange or {}
    if dispelKey(playerDispels) == was or not ns.db then return end
    for f in pairs(ns.unitButtons or {}) do
        if f.unit then
            ns.RegisterFrameEvents(f)
            if ns.AuraDirty then ns.AuraDirty(f) end
        end
    end
end
ns.RefreshPlayerDispels = refreshPlayerDispels
refreshPlayerDispels()
do
    -- spells and pets change rarely; a burst (login, a talent reset) is
    -- worked out once, a moment later
    local w = CreateFrame("Frame")
    local armed = false
    local function run() armed = false refreshPlayerDispels() end
    for _, ev in ipairs({ "PLAYER_LOGIN", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_ENTERING_WORLD" }) do
        pcall(w.RegisterEvent, w, ev)
    end
    pcall(w.RegisterUnitEvent, w, "UNIT_PET", "player")
    w:SetScript("OnEvent", function()
        if armed then return end
        armed = true
        C_Timer.After(0.2, run)
    end)
end

-- Blizzard's DebuffTypeColor values, kept locally: that global is removed on
-- the 2.5.6-era client.
local DISPEL_COLORS = {
    Magic   = { 0.2, 0.6, 1.0 },
    Curse   = { 0.6, 0.0, 1.0 },
    Disease = { 0.6, 0.4, 0.0 },
    Poison  = { 0.0, 0.6, 0.0 },
}
ns.DISPEL_COLORS = DISPEL_COLORS   -- the dispel glow (Glows.lua) wears them too

-- Tint the frame's backdrop border by dispel type; restore the configured
-- border when clear. Applied unconditionally when a type is present because
-- restyles (LeanRestyle -> UI:Backdrop) reset the border underneath us; the
-- nil -> nil early-out keeps the no-debuff raid common case free.
local function setDispelHighlight(frame, dispelType)
    if dispelType == nil and frame.dispelType == nil then return end
    frame.dispelType = dispelType
    if frame.moverTex and frame.moverTex:IsShown() then return end   -- move mode owns the border
    if not frame.SetBackdropBorderColor then return end
    if dispelType then
        local c = DISPEL_COLORS[dispelType]
        if c then frame:SetBackdropBorderColor(c[1], c[2], c[3], 1) end
    elseif frame.isGroupUnit and ns._matchApplied then
        ns.GroupBorder(frame)
    else
        local bc = frame.cfg and frame.cfg.borderColor
        if frame._zuiEdge then frame:SetBackdropBorderColor(ns.UI:FrameBorderColor(frame, bc))
        elseif bc then frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
        else frame:SetBackdropBorderColor(0, 0, 0, 1) end
    end
end

-- Match pass (ZacUI's look): a party / raid frame's border goes white while
-- it is moused over or is your target, as the reference's group frames do;
-- a dispel tint and move mode win. Runs on hover, on a target change (one
-- event frame, made only under the match pass) and on a unit reassignment.
function ns.GroupBorder(frame)
    if not (ns._matchApplied and frame and frame.isGroupUnit and frame.SetBackdropBorderColor) then return end
    if frame.dispelType or (frame.moverTex and frame.moverTex:IsShown()) then return end
    local lit = frame.hovered
    if not lit and frame.unit and UnitExists(frame.unit) then lit = UnitIsUnit(frame.unit, "target") end
    if lit then
        frame:SetBackdropBorderColor(1, 1, 1, 1)
    else
        local bc = frame.cfg and frame.cfg.borderColor
        if frame._zuiEdge then frame:SetBackdropBorderColor(ns.UI:FrameBorderColor(frame, bc))
        elseif bc then frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
        else frame:SetBackdropBorderColor(0, 0, 0, 1) end
    end
end
local groupTargetWatch
function ns.GroupBorderWatch()
    if groupTargetWatch or not ns._matchApplied then return end
    groupTargetWatch = CreateFrame("Frame")
    groupTargetWatch:RegisterEvent("PLAYER_TARGET_CHANGED")
    groupTargetWatch:SetScript("OnEvent", function()
        for f in pairs(ns.unitButtons) do
            if f.isGroupUnit and f:IsShown() then ns.GroupBorder(f) end
        end
    end)
end

-- Which auras an icon row keeps: the same tests for live frames and the
-- settings preview's made-up auras. `dispels` is what the player can remove.
local function debuffShown(cfg, name, spellID, source, dispelType, dispels)
    return ((not cfg.onlyMine) or source == "player")
       and ((not cfg.dispellableOnly) or (dispels and dispelType and dispels[dispelType]))
       and ((not cfg.filterEnabled) or auraListMatch(cfg.debuffList, name, spellID))
end
local function buffShown(cfg, name, spellID)
    return (not cfg.filterEnabled) or auraListMatch(cfg.buffList, name, spellID)
end
-- WoW Forever: a debuff the game hides passes only the filters that don't
-- need its name or type ("only mine": the never-hidden "from you" flag)
local function hiddenDebuffShown(cfg, a)
    if a == nil or cfg.dispellableOnly or cfg.filterEnabled then return false end
    if not cfg.onlyMine then return true end
    local Z = _G.ZacUI
    return (Z and Z.AuraIsMine and Z.AuraIsMine(a)) and true or false
end
-- its icon and stacks straight onto the icon (hidden values as they are)
local function showHiddenAura(b, unit, a)
    pcall(b.icon.SetTexture, b.icon, a.icon)
    local Z = _G.ZacUI
    if not (Z and Z.ShowAuraCount and Z.ShowAuraCount(b.count, unit, a)) then b.count:SetText("") end
end

-- The icon grid for a frame: the step between icons, icons per row, the
-- debuff and buff anchors, and the room a castbar below the frame takes.
-- A castbar anchored below the frame pushes an aura block anchored BELOW past
-- it; only matters when the castbar is enabled AND placed below. Uses the
-- per-frame castbar height (0 = global default).
local function auraGrid(fcfg)
    local cfg = ns.db.auras
    local cbBelow = fcfg.castbar and ((fcfg.cbAnchor or "BELOW") == "BELOW" or fcfg.cbAnchor == "BOTTOM")
    local cbH     = (fcfg.cbHeight and fcfg.cbHeight > 0) and fcfg.cbHeight or ns.db.castbar.height
    local cbGap   = cbBelow and (cbH + 4) or 0
    local step    = cfg.size + (tonumber(cfg.spacing) or 2)
    return step, cfg.perRow,
        AURA_ANCHOR[fcfg.debuffAnchor] or AURA_ANCHOR.BELOW,
        AURA_ANCHOR[fcfg.buffAnchor]   or AURA_ANCHOR.ABOVE,
        cbGap
end

-- Does a UNIT_AURA payload touch anything this frame draws? A full update
-- or a missing payload (older client, or a call from UpdateAll) always
-- counts. A removal or a stack change could be either kind, so both count
-- for both; only the added list says which side it is on.
local function auraPayloadMatters(updateInfo, wantHarmful, wantHelpful)
    if type(updateInfo) ~= "table" or updateInfo.isFullUpdate then return true end
    if not wantHarmful and not wantHelpful then return false end
    local rem, upd = updateInfo.removedAuraInstanceIDs, updateInfo.updatedAuraInstanceIDs
    if (rem and rem[1] ~= nil) or (upd and upd[1] ~= nil) then return true end
    local added = updateInfo.addedAuras
    if added then
        for i = 1, #added do
            local a = added[i]
            if (wantHarmful and a.isHarmful) or (wantHelpful and a.isHelpful) then return true end
        end
    end
    return false
end

-- UNIT_AURA only marks the frame (the frames' OnEvent calls this): a
-- payload that touches nothing the frame draws is dropped here, anything
-- else puts the frame on the dirty list, and one walk per dirty frame runs
-- a moment later - ten aura changes on one raider in a burst cost one
-- walk, and nothing ever sweeps every frame on one event.
local AURA_FLUSH = 0.05
local auraDirty, auraSpare, auraArmed = {}, {}, false
local function flushAuras()
    auraArmed = false
    local list = auraDirty
    auraDirty, auraSpare = auraSpare, list
    for f in pairs(list) do
        list[f] = nil
        ns.UpdateAuras(f)
    end
end
function ns.AuraDirty(frame, updateInfo)
    if auraDirty[frame] or not frame.auraIcons then return end
    local fcfg = frame.cfg
    local wantBuffs = fcfg and fcfg.showBuffs
    local wantHarmful = (fcfg and fcfg.showDebuffs) or (dispelLooks() and playerDispels)
    if not auraPayloadMatters(updateInfo, wantHarmful, wantBuffs) then return end
    auraDirty[frame] = true
    if not auraArmed then
        auraArmed = true
        C_Timer.After(AURA_FLUSH, flushAuras)
    end
end

-- updateInfo is UNIT_AURA's second argument when the event is the caller;
-- a buff ticking on a raid frame that only draws debuffs then costs nothing.
function ns.UpdateAuras(frame, updateInfo)
    if not frame.auraIcons then return end
    local cfg = ns.db.auras          -- shared appearance (size / max / perRow / onlyMine)
    local fcfg = frame.cfg
    local wantBuffs   = fcfg and fcfg.showBuffs
    local wantDebuffs = fcfg and fcfg.showDebuffs
    local unit = frame.unit
    if not unit or not UnitExists(unit) or not scanAura then
        for _, b in ipairs(frame.auraIcons) do b:Hide() end
        setDispelHighlight(frame, nil)
        if ns.DispelGlowSet then ns.DispelGlowSet(frame, nil) end
        return
    end

    -- the tint and the glow share one search for a type this character
    -- can remove; each then shows it only if it is switched on
    local tintOn, glowWanted = cfg.dispelHighlight, glowOn()
    local dispelWanted = (tintOn or glowWanted) and playerDispels
    if not auraPayloadMatters(updateInfo, wantDebuffs or dispelWanted, wantBuffs) then return end

    -- Dispellable-debuff border highlight. Friendly units only; first
    -- dispellable type found wins. It rides the same HARMFUL walk as the
    -- debuff icons below (UNIT_AURA fires far too often for two walks),
    -- and keeps going past the icon cap until a type is found, so it still
    -- works on frames that show no debuff icons at all.
    local foundDispel
    local checkDispel = dispelWanted and UnitCanAssist("player", unit)

    if not wantBuffs and not wantDebuffs then
        if checkDispel then
            for index = 1, 40 do
                local name, _, _, _, _, dispelType = scanAura(unit, index, "HARMFUL")
                if name == nil then break end
                if name and dispelType and playerDispels[dispelType] then foundDispel = dispelType; break end
            end
        end
        setDispelHighlight(frame, tintOn and foundDispel or nil)
        if ns.DispelGlowSet then ns.DispelGlowSet(frame, glowWanted and foundDispel or nil) end
        for _, b in ipairs(frame.auraIcons) do b:Hide() end
        return
    end

    local step, perRow, da, ba, cbGap = auraGrid(fcfg)
    local pool   = 0   -- running index into the shared icon pool

    -- Debuffs: their own grid at debuffAnchor + (debuffX, debuffY), capped at
    -- max. The dispel check shares this walk: once the icons are full (or not
    -- wanted) it carries on alone until a dispellable type turns up.
    if wantDebuffs or checkDispel then
        local n  = 0
        local iconsDone = not wantDebuffs
        local oy = (fcfg.debuffY or 0) - (da.below and cbGap or 0)
        for index = 1, 40 do
            local name, icon, count, source, spellID, dispelType, duration, expires = scanAura(unit, index, "HARMFUL")
            if name == nil then break end
            if name == false then
                -- (WoW Forever: a debuff the game hides; icon = its table)
                if not iconsDone and hiddenDebuffShown(cfg, icon) then
                    pool = pool + 1
                    local b = getAuraIcon(frame, pool)
                    showHiddenAura(b, unit, icon)
                    if b.swipe then hdAura(b, true, nil, nil, nil) end
                    placeAura(frame, b, da, n, perRow, step, fcfg.debuffX or 0, oy)
                    n = n + 1
                    if n >= cfg.max then iconsDone = true end
                end
            elseif checkDispel and not foundDispel and dispelType and playerDispels[dispelType] then
                foundDispel = dispelType
            end
            if name and not iconsDone and debuffShown(cfg, name, spellID, source, dispelType, playerDispels) then
                pool = pool + 1
                local b = getAuraIcon(frame, pool)
                b.icon:SetTexture(icon)
                b.count:SetText((count and count > 1) and count or "")
                if b.swipe then hdAura(b, true, dispelType, duration, expires) end
                placeAura(frame, b, da, n, perRow, step, fcfg.debuffX or 0, oy)
                n = n + 1
                if n >= cfg.max then iconsDone = true end
            end
            if iconsDone and (foundDispel or not checkDispel) then break end
        end
    end
    setDispelHighlight(frame, tintOn and foundDispel or nil)
    if ns.DispelGlowSet then ns.DispelGlowSet(frame, glowWanted and foundDispel or nil) end

    -- Buffs: independent grid at buffAnchor + (buffX, buffY), capped at max.
    if wantBuffs then
        local n  = 0
        local oy = (fcfg.buffY or 0) - (ba.below and cbGap or 0)
        for index = 1, 40 do
            local name, icon, count, _, spellID, _, duration, expires = scanAura(unit, index, "HELPFUL")
            if name == nil then break end
            if name == false then
                -- (WoW Forever: a buff the game hides; icon = its table)
                if icon and not cfg.filterEnabled then
                    pool = pool + 1
                    local b = getAuraIcon(frame, pool)
                    showHiddenAura(b, unit, icon)
                    if b.swipe then hdAura(b, false, nil, nil, nil) end
                    placeAura(frame, b, ba, n, perRow, step, fcfg.buffX or 0, oy)
                    n = n + 1
                    if n >= cfg.max then break end
                end
            elseif buffShown(cfg, name, spellID) then
                pool = pool + 1
                local b = getAuraIcon(frame, pool)
                b.icon:SetTexture(icon)
                b.count:SetText((count and count > 1) and count or "")
                if b.swipe then hdAura(b, false, nil, duration, expires) end
                placeAura(frame, b, ba, n, perRow, step, fcfg.buffX or 0, oy)
                n = n + 1
                if n >= cfg.max then break end
            end
        end
    end

    for j = pool + 1, #frame.auraIcons do frame.auraIcons[j]:Hide() end
end

-- Auras on a settings-preview sample, from made-up lists:
-- { name =, icon =, count =, spellID =, source =, dispelType = }. The same
-- filters, grid and dispel tint as a live frame; the preview lets you see
-- the tint whatever your class can remove (a class with no dispel would
-- otherwise never show it).
local PREVIEW_DISPELS = { Magic = true, Curse = true, Disease = true, Poison = true }
local NO_AURAS = {}
function ns.PaintAuras(frame, debuffs, buffs, friendly)
    if not frame.auraIcons then return end
    local cfg, fcfg = ns.db.auras, frame.cfg or {}
    debuffs, buffs = debuffs or NO_AURAS, buffs or NO_AURAS
    local dispels = playerDispels or PREVIEW_DISPELS
    local found
    local tintOn, glowWanted = cfg.dispelHighlight, glowOn()
    if (tintOn or glowWanted) and friendly then
        for _, a in ipairs(debuffs) do
            if a.dispelType and dispels[a.dispelType] then found = a.dispelType break end
        end
    end
    setDispelHighlight(frame, tintOn and found or nil)
    -- a sample: never range-gated
    if ns.DispelGlowSet then ns.DispelGlowSet(frame, glowWanted and found or nil, true) end
    local pool = 0
    if fcfg.showBuffs or fcfg.showDebuffs then
        local step, perRow, da, ba, cbGap = auraGrid(fcfg)
        local function row(list, a, want, ox, oy, test, block)
            if not want then return end
            local n = 0
            for _, e in ipairs(list) do
                if n >= cfg.max then break end
                if test(e) then
                    pool = pool + 1
                    local b = getAuraIcon(frame, pool)
                    -- (which block it is in: the preview drags the block)
                    b._zBlock = block
                    b.icon:SetTexture(e.icon)
                    b.count:SetText((e.count and e.count > 1) and e.count or "")
                    -- the HD ring colour (and a made-up sweep for short ones)
                    if b.swipe then
                        local d = tonumber(e.duration) or 20
                        hdAura(b, block == "debuffs", e.dispelType, d, GetTime() + d * 0.6)
                    end
                    placeAura(frame, b, a, n, perRow, step, ox, oy)
                    n = n + 1
                end
            end
        end
        row(debuffs, da, fcfg.showDebuffs, fcfg.debuffX or 0, (fcfg.debuffY or 0) - (da.below and cbGap or 0),
            function(e) return debuffShown(cfg, e.name, e.spellID, e.source, e.dispelType, dispels) end, "debuffs")
        row(buffs, ba, fcfg.showBuffs, fcfg.buffX or 0, (fcfg.buffY or 0) - (ba.below and cbGap or 0),
            function(e) return buffShown(cfg, e.name, e.spellID) end, "buffs")
    end
    for j = pool + 1, #frame.auraIcons do frame.auraIcons[j]:Hide() end
end

-- ----------------------------------------------------------------------------
-- Castbar (per-unit)
-- ----------------------------------------------------------------------------
-- Put a castbar back at rest and hidden-or-shown as it should be: the
-- motion layer restores a frame's anchors when stopped, and a bar caught
-- half way through its "cast over" animation must still end up hidden.
function ns.CastbarStopMotion(cb)
    if not cb then return end
    local Mo = Motion()
    if Mo and cb._zMotion then Mo.Stop(cb) end
    if cb._ending then
        cb._ending = nil
        cb:Hide()
    end
end

-- Show a cast on a frame's castbar from plain values (times in seconds on
-- GetTime's clock). The live path below and the settings preview both
-- start casts through this; a bar that was not already showing plays the
-- castbar's "appears" animation.
function ns.CastbarStart(frame, text, texture, startT, endT, channel, notInterruptible)
    local cb = frame.Castbar
    if not cb then return end
    local appearing = (not cb:IsShown()) or cb._ending
    cb._ending = nil
    cb._zHidden = nil
    cb.channel = channel
    cb.startT  = startT
    cb.endT    = endT
    cb._tenths = nil
    cb:SetMinMaxValues(0, math.max(cb.endT - cb.startT, 0.001))
    local c = notInterruptible and ns.db.colors.castbarNoInt or ns.db.colors.castbar
    cb:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    if cb.icon then cb.icon:SetTexture(texture) end
    if cb.spell then cb.spell:SetText(text or "") end
    if appearing then
        motionShow(cb, ns.db.castbar.showAnim)
    end
end

-- The cast is over (finished, stopped, interrupted): the castbar plays its
-- "ends" animation and hides. Anything else that hides a castbar (the
-- frame's castbar switched off, the unit gone) still hides it at once.
function ns.CastbarEnd(cb)
    if not cb or cb._ending then return end
    cb.endT = nil
    cb._zHidden = nil
    if not cb:IsShown() then return end
    cb._ending = true
    motionHide(cb, ns.db.castbar.hideAnim, function() cb._ending = nil end)
end

-- WoW Forever hides a cast in combat (secret values: no compare, no
-- arithmetic). The bar still shows it: the game's own duration object for
-- the cast drives the fill (UnitCastingDuration / UnitChannelDuration ->
-- StatusBar:SetTimerDuration), and the spell's name and icon go onto the
-- text and the icon as they are. Whether it can be interrupted is hidden
-- too, so it wears the normal cast colour. false when this client can't
-- (the bar then goes, as before).
function ns.CastbarHidden(frame, name, text, texture, channel)
    local cb = frame.Castbar
    local Z = _G.ZacUI
    if not (cb and Z and Z.CastDuration and Z.ShowCastTimer) then return false end
    local dur = Z.CastDuration(frame.unit, channel)
    if not dur then return false end
    if not Z.ShowCastTimer(cb, dur, channel) then return false end
    local appearing = (not cb:IsShown()) or cb._ending
    cb._ending = nil
    cb.channel, cb.startT, cb.endT, cb._tenths = channel, nil, nil, nil
    cb._zHidden = dur
    local c = ns.db.colors.castbar
    cb:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    if cb.icon then pcall(cb.icon.SetTexture, cb.icon, texture) end
    if cb.spell then pcall(cb.spell.SetText, cb.spell, text or name) end
    if cb.timer then cb.timer:SetText("") end
    if appearing then
        motionShow(cb, ns.db.castbar.showAnim)
    end
    return true
end

-- fromEvent: a cast event asked (a cast that just stopped animates out);
-- otherwise (a new unit on the frame) a bar with nothing to show just goes.
function ns.CastbarUpdate(frame, fromEvent)
    local cb = frame.Castbar
    if not cb then return end
    if cb.preview then return end                -- move-mode preview owns the bar
    if frame.cfg and not frame.cfg.castbar then ns.CastbarStopMotion(cb) cb:Hide(); return end
    local unit = frame.unit
    if not unit or not UnitExists(unit) then ns.CastbarStopMotion(cb) cb:Hide(); return end

    local name, text, texture, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unit)
    -- WoW Forever hides a cast in combat (secret values: no compare, no
    -- arithmetic): shown as it is (ns.CastbarHidden), else the bar goes
    -- until it reads again
    local sec = issecretvalue
    if sec ~= nil and (sec(name) or sec(startMS) or sec(endMS)) then
        if ns.CastbarHidden(frame, name, text, texture, false) then return end
        ns.CastbarStopMotion(cb) cb:Hide() return
    end
    local channel = false
    if not name then
        name, text, texture, startMS, endMS, _, notInterruptible = UnitChannelInfo(unit)
        channel = true
        if sec ~= nil and (sec(name) or sec(startMS) or sec(endMS)) then
            if ns.CastbarHidden(frame, name, text, texture, true) then return end
            ns.CastbarStopMotion(cb) cb:Hide() return
        end
    end
    if not name then
        if fromEvent then ns.CastbarEnd(cb) else ns.CastbarStopMotion(cb) cb:Hide() end
        return
    end
    -- (a hidden "can't be interrupted" flag is a secret boolean: never tested)
    if issecretvalue ~= nil and issecretvalue(notInterruptible) then notInterruptible = false end
    ns.CastbarStart(frame, text or name, texture, startMS / 1000, endMS / 1000, channel, notInterruptible)
end

-- Screen-space coords of a named anchor point ("TOP","BOTTOMLEFT","CENTER",...)
-- on a frame, used to turn a dragged castbar's position back into an offset.
local function pointXY(f, point)
    local l, b, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
    if not l then return nil end
    local x = l + (point:find("RIGHT") and w or (point:find("LEFT") and 0 or w * 0.5))
    local y = b + (point:find("TOP") and h or (point:find("BOTTOM") and 0 or h * 0.5))
    return x, y
end

-- Make a frame's castbar click-and-drag movable while in move mode. Dragging it
-- updates that frame's cbX / cbY offset (within its current cbAnchor), so it
-- persists exactly like typing a value - and clicking it selects the frame in the
-- position dialog. Wired once per castbar; mouse is only enabled during preview.
local function setupCastbarDrag(frame)
    local cb = frame.Castbar
    if not cb or cb.__dragInit then return end
    cb.__dragInit = true
    cb:SetMovable(true)
    cb:RegisterForDrag("LeftButton")
    cb:SetScript("OnMouseDown", function()
        if not ns.db.locked and ns.SelectMoveFrame and frame.unit then
            ns.SelectMoveFrame(frame.unit)
        end
    end)
    cb:SetScript("OnDragStart", function(self)
        if ns.db.locked or InCombatLockdown() then return end
        self:StartMoving()
    end)
    cb:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cfg = frame.cfg
        if cfg then
            local cbA = NA()[cfg.cbAnchor] or NA().BELOW
            local cx, cy = pointXY(self, cbA.p)
            local fx, fy = pointXY(frame, cbA.rp)
            if cx and fx then
                cfg.cbX = math.floor(cx - fx + 0.5)
                cfg.cbY = math.floor(cy - fy + 0.5)
            end
            self:ClearAllPoints()
            self:SetPoint(cbA.p, frame, cbA.rp, cfg.cbX or 0, cfg.cbY or 0)
        end
        if ns.RefreshOptions then ns.RefreshOptions() end
    end)
end

-- Move-mode preview: fill the castbar with sample content and hold it on screen
-- (the OnUpdate / CastbarUpdate both yield to `preview`), so its position and
-- size can be seen and tuned without actually casting. Off => restore normal
-- cast-only behavior without disturbing a real cast in progress.
function ns.CastbarPreview(frame, on)
    local cb = frame.Castbar
    if not cb then return end
    if on and frame.cfg and frame.cfg.castbar then
        setupCastbarDrag(frame)
        cb:EnableMouse(true)
        ns.CastbarStopMotion(cb)
        cb._ending = nil
        cb.preview = true
        cb:SetMinMaxValues(0, 1)
        cb:SetValue(0.66)
        local c = ns.db.colors.castbar
        cb:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
        if cb.icon then cb.icon:SetTexture("Interface\\Icons\\Spell_Holy_FlashHeal") end
        if cb.spell then cb.spell:SetText("Castbar - drag me") end
        if cb.timer and cb.timerOn then cb.timer:SetText("1.5") end
        cb:Show()
    else
        cb:EnableMouse(false)
        if cb.preview then cb:Hide() end          -- only clear the preview, not a real cast
        cb.preview = false
    end
end

function ns.CastbarEvent(frame, event, evUnit, castGUID)
    local cb = frame.Castbar
    if not cb then return end
    if cb.preview then return end                         -- move-mode preview owns the bar
    if frame.cfg and not frame.cfg.castbar then ns.CastbarStopMotion(cb) cb:Hide(); return end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        ns.CastbarUpdate(frame, true)
        cb.castGUID = castGUID                            -- remember which cast we're showing
    elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        ns.CastbarUpdate(frame, true)                     -- pushback / channel tick: refresh times
    else
        -- STOP / FAILED / INTERRUPTED / CHANNEL_STOP. A stale stop/fail from a queued
        -- or double-pressed spell would otherwise hide a cast that's still going (the
        -- "flash then vanish"), so ignore it when its GUID isn't the cast we're showing.
        if castGUID and cb.castGUID and castGUID ~= cb.castGUID then return end
        cb.castGUID = nil
        ns.CastbarUpdate(frame, true)                     -- hides if truly idle, else shows the live cast
    end
end

-- ----------------------------------------------------------------------------
-- Status icons (per-unit). Each icon is gated by its per-frame toggle and the
-- unit's live state; hidden otherwise. Cheap to call on the (infrequent) events
-- that drive it. PvP is split out because it also owns the player countdown.
-- ----------------------------------------------------------------------------
function ns.UpdatePvP(frame)
    local ind = frame.Indicators
    if not ind then return end
    local pt = ind.pvpText
    local cfg, unit = frame.cfg, frame.unit
    -- Mouseover-only: the PvP text is hidden unless the cursor is over this frame.
    if not cfg or not cfg.pvpIcon or not frame.hovered
       or not unit or not UnitExists(unit) or not UnitIsPVP(unit) then
        pt:Hide()
        if unit == "player" then pvpTicker:Hide() end
        return
    end
    pt:Show()
    -- only the player has a queryable flag timer; everyone else just reads "PvP"
    if unit == "player" then
        local ms = GetPVPTimer()
        if ms and ms > 0 and ms ~= 301000 then
            pt:SetText("PvP " .. pvpTimeText(ms))
            pvpTicker.t = 0
            pvpTicker:Show()
        else
            pt:SetText("PvP"); pvpTicker:Hide()   -- perma-flagged: no countdown
        end
    else
        pt:SetText("PvP")
    end
end

-- Raid target markers: set the icon texture ourselves from the 4x4 atlas rather
-- than via SetRaidTargetIconTexture, which on this client is a no-op - it left
-- the texture empty, so the marker was "shown" but invisible (GetTexture == nil).
local RT_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local function setRaidMarker(tex, index)
    tex:SetTexture(RT_ICONS)
    local col = (index - 1) % 4
    local row = math.floor((index - 1) / 4)
    tex:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25)
end

-- RAID_TARGET_UPDATE reaches every frame at once and marks churn all
-- fight, so it only re-reads the marker; the full indicator pass stays
-- with the roster / flags events.
function ns.UpdateRaidMarker(frame)
    local ind = frame.Indicators
    if not ind then return end
    local cfg, unit = frame.cfg, frame.unit
    local idx = cfg and unit and cfg.raidIcon and UnitExists(unit) and GetRaidTargetIndex(unit)
    -- (WoW Forever can hand the marker back hidden: no marker then)
    if issecretvalue ~= nil and issecretvalue(idx) then idx = nil end
    if idx then
        if ind.raid._idx ~= idx then ind.raid._idx = idx setRaidMarker(ind.raid, idx) end
        ind.raid:Show()
    else
        ind.raid:Hide()
    end
end

function ns.UpdateIndicators(frame)
    local ind = frame.Indicators
    if not ind then return end
    local cfg, unit = frame.cfg, frame.unit
    if not cfg or not unit or not UnitExists(unit) then
        ind.leader:Hide(); ind.combat:Hide(); ind.role:Hide(); ind.raid:Hide(); ind.rez:Hide()
        ind.pvpText:Hide()
        return
    end

    -- what this unit wears; each icon is asked about only when its toggle is on
    local leader
    if cfg.leaderIcon then
        if UnitIsGroupLeader(unit) then leader = "leader"
        elseif UnitIsGroupAssistant and UnitIsGroupAssistant(unit) then leader = "assist" end
    end
    local role
    if cfg.roleIcon then
        if GetPartyAssignment("MAINTANK", unit) then role = "MAINTANK"
        elseif GetPartyAssignment("MAINASSIST", unit) then role = "MAINASSIST" end
    end
    local marker = cfg.raidIcon and GetRaidTargetIndex(unit)
    if issecretvalue ~= nil and issecretvalue(marker) then marker = nil end   -- (WoW Forever)
    ns.PaintIndicators(frame, leader,
        cfg.combatIcon and UnitAffectingCombat(unit),
        role,
        marker,
        cfg.rezIcon and UnitHasIncomingResurrection and UnitHasIncomingResurrection(unit))
    ns.UpdatePvP(frame)
end

-- The status icons from plain values (live update and preview samples):
-- leader "leader" | "assist" | nil, combat true/false, role "MAINTANK" |
-- "MAINASSIST" | nil, marker 1..8 | nil, rez true/false. Each still obeys
-- its per-frame toggle.
function ns.PaintIndicators(frame, leader, combat, role, marker, rez)
    local ind = frame.Indicators
    if not ind then return end
    local cfg = frame.cfg or {}

    -- leader crown / assistant flag (one slot; leader wins)
    local li = ind.leader
    if cfg.leaderIcon and leader == "leader" then
        li:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon"); li:Show()
    elseif cfg.leaderIcon and leader == "assist" then
        li:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon"); li:Show()
    else
        li:Hide()
    end

    -- combat (crossed swords) - matches the Blizzard player-frame icon
    local ci = ind.combat
    if cfg.combatIcon and combat then
        ci:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
        ci:SetTexCoord(0.5625, 0.9375, 0.0625, 0.4375)
        ci:Show()
    else
        ci:Hide()
    end

    -- raid role (main tank / main assist)
    local ri = ind.role
    if cfg.roleIcon and role == "MAINTANK" then
        ri:SetTexture("Interface\\GroupFrame\\UI-Group-MainTankIcon"); ri:Show()
    elseif cfg.roleIcon and role == "MAINASSIST" then
        ri:SetTexture("Interface\\GroupFrame\\UI-Group-MainAssistIcon"); ri:Show()
    else
        ri:Hide()
    end

    -- raid target marker (skull, cross, ...) centered over the bar
    local ti = ind.raid
    local idx = cfg.raidIcon and marker
    if idx then
        if ti._idx ~= idx then ti._idx = idx setRaidMarker(ti, idx) end
        ti:Show()
    else
        ti:Hide()
    end

    -- incoming resurrection (a res spell is mid-cast on this unit)
    local rz = ind.rez
    if cfg.rezIcon and rez then rz:Show() else rz:Hide() end
end

-- The PvP text on a preview sample: shown whenever the frame wears it
-- (live frames show it only under the mouse).
function ns.PaintPvP(frame, on)
    local ind = frame.Indicators
    if not ind then return end
    if on and frame.cfg and frame.cfg.pvpIcon then
        ind.pvpText:SetText("PvP")
        ind.pvpText:Show()
    else
        ind.pvpText:Hide()
    end
end

-- Leader / assist / main-tank icons follow the group: ONE coalesced
-- sweep of the visible frames that show a unit and wear one of those
-- icons, on ZacUI's shared roster notice (already 0.1s after the burst)
-- and on PARTY_LEADER_CHANGED. Frames that are hidden now catch up in
-- their OnShow (UpdateAll).
local function sweepGroupIcons()
    for f in pairs(ns.unitButtons) do
        local cfg = f.cfg
        if f.unit and cfg and (cfg.leaderIcon or cfg.roleIcon) and f:IsVisible() then
            ns.UpdateIndicators(f)
        end
    end
end
Z.Roster.On("ZacUF.groupIcons", sweepGroupIcons)
do
    local leaderWatch = CreateFrame("Frame")
    local leaderArmed = false
    local function run() leaderArmed = false sweepGroupIcons() end
    leaderWatch:RegisterEvent("PARTY_LEADER_CHANGED")
    leaderWatch:SetScript("OnEvent", function()
        if leaderArmed then return end
        leaderArmed = true
        C_Timer.After(0.1, run)
    end)
end

-- Full refresh for a frame.
function ns.UpdateAll(frame)
    if not frame.unit or not UnitExists(frame.unit) then return end
    ns.UpdateHealth(frame)
    ns.UpdatePower(frame)
    ns.UpdateName(frame)
    ns.UpdateAuras(frame)
    ns.UpdateIndicators(frame)
    ns.CastbarUpdate(frame)
    -- The legend dot is keyed to the unit's GUID, so it has to be re-evaluated
    -- whenever a frame changes which unit it shows - raid header children get
    -- reassigned constantly as the roster shifts.
    ns.UpdateHealerDot(frame)
    if frame.isGroupUnit and ns._matchApplied then ns.GroupBorder(frame) end
end
