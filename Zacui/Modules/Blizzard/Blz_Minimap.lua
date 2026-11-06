-- Blz_Minimap - the ZacUI minimap: a square map in one of two looks.
--   overlay (the default): just the map, with the zone name, coordinates
--     and friends / guild in small pills on top that fade in on mouseover,
--     and the clock in the bottom-right corner.
--   panel: the zone name in a header above the map, a footer below it
--     (friends, clock, guild) and coordinates along its bottom edge.
-- Either way Blizzard's mail, tracking and battleground icons are tucked
-- into its corners.
-- Part of ZacUI; load order is set by the TOC.
--
-- ONE PANEL, NOT PIECES. The old skin hung a zone strip, a clock, a day
-- number and a friends / guild bar around the map one at a time, each with
-- its own backdrop and its own idea of width - so the pieces never lined up
-- and the ring-shaped Blizzard icons floated off the square's edges. Now the
-- header, the map and the footer share one outer border and one width, the
-- icons sit inside the corners at one size, and the whole thing follows the
-- palette like every other ZacUI window.
--
-- Everything here is anchored to Minimap, so Edit Mode moving or scaling
-- the map carries the panel with it. Nothing in it is secure; nothing it
-- touches is protected.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local GetColor = ns.GetColor
local Hex = ns.Hex
local MEDIA = ns.MEDIA
local Modules = ns.Modules
local RegisterLoD = ns.RegisterLoD
local SharpenIcon = ns.SharpenIcon
local SkinBackdrop = ns.SkinBackdrop
local SkinButton = ns.SkinButton
local StripFrameChrome = ns.StripFrameChrome
local StripTextures = ns.StripTextures
local ZUI = ns.ZUI

local HEAD_H  = 20    -- zone name header
local FOOT_H  = 20    -- friends / clock / guild footer
local CLOCK_W = 58    -- the clock's share of the footer
local ICON    = 22    -- corner icons (mail, tracking)
local ZOOM_RESET = 15 -- seconds after the last wheel turn

local mm = {}         -- the panel's pieces, once built

local function RemoveClose(btn)
    if not btn or ZUI.skinned[btn] then return end
    ZUI.skinned[btn] = true
    btn:Hide()
    btn:HookScript("OnShow", function(self) self:Hide() end)
end

-- The options layer loads after this file; read it at call time.
local function Want(key)
    local MM = ns.MinimapOptions
    if MM and MM.On then return MM.On(key) end
    return true
end

local function Setting(key)
    local MM = ns.MinimapOptions
    return MM and MM.DB and MM.DB()[key]
end

-- "42.1, 65.3" - or the saved coordinate format (minimap.formats.coords,
-- ZacUI's text format: a template over [x] [y], decimals)
local COORD_V, COORD_K = {}, { x = "percent", y = "percent" }
local COORD_DEFAULTS = { template = "[x], [y]", decimals = 1 }
local function CoordsText(x, y)
    local f = Setting("formats")
    local spec = type(f) == "table" and f.coords or nil
    if spec and ns.FormatText then
        COORD_V.x, COORD_V.y = x * 100, y * 100
        return ns.FormatText(spec, COORD_DEFAULTS, COORD_V, COORD_K, "x")
    end
    return string.format("%.1f, %.1f", x * 100, y * 100)
end

-- THE LOOK (Screen > Minimap, in the same ZacUIDB.minimap the options
-- layer keeps): every default is what this file drew before the setting
-- existed, and a colour or font left unset is "as before".
--   pillFont        face / outline / shadow of the map's text (the size
--                   stays the Text size setting, or the panel's own sizes)
--   pillColor       the pills' backing (pillAlpha is its darkness)
--   pillBorder      a 1px edge round each pill, in pillBorderColor
--   pillPad/pillGap the pills' gap from the map's edge / between pills
--   borderColor / borderSize   the map's outline
--   edgeColor       the ring that lights up under the mouse
local LOOK = { pillPad = 4, pillGap = 2, borderSize = 1, pillBorder = false }
local function Look(key)
    local v = Setting(key)
    if v == nil then return LOOK[key] end
    return v
end
local function Empty(spec) return type(spec) ~= "table" or next(spec) == nil end

-- Blizzard's own strings, in the ZacUI font at a given size (their
-- templates are the stock font, which reads out of place in the panel).
-- With a map font chosen: its face, outline and shadow at the same size.
local function StyleFS(fs, size)
    if not fs or not fs.GetFont then return end
    local spec = Setting("pillFont")
    if Empty(spec) or not ns.ApplyFontSpec then
        ns.HouseFont(fs, size)
        return
    end
    local f = ZacUIDB and ZacUIDB.font
    ns.ApplyFontSpec(fs, { face = spec.face, outline = spec.outline, shadow = spec.shadow,
        shadowX = spec.shadowX, shadowY = spec.shadowY },
        { size = size + ((f and f.delta) or 0),
          outline = (f and f.outline == "NONE") and "none" or "outline", shadow = true })
end

local function ZoneButton()
    return MinimapZoneTextButton or (MinimapCluster and MinimapCluster.ZoneTextButton)
end

local function ZoneText()
    local b = ZoneButton()
    return MinimapZoneText or (b and b.Text)
end

-- The width the text WANTS: a string anchored at both ends reports its
-- clipped width from GetStringWidth.
local function TextWidth(fs)
    if fs.GetUnboundedStringWidth then return fs:GetUnboundedStringWidth() end
    return fs:GetStringWidth()
end

-- How wide a sample string is in the font another string uses, so a cell
-- can be sized for its widest content and not twitch as the text changes.
local function MeasureLike(fs, sample)
    if not (mm.measure and fs and fs.GetFont) then return 0 end
    local font, size, flags = fs:GetFont()
    if not font then return 0 end
    mm.measure:SetFont(font, size, flags)
    mm.measure:SetText(sample)
    return math.ceil(TextWidth(mm.measure) or 0)
end

-- ============================================================
-- OVERLAY LOOK (map only, details in pills on top of it)
-- ============================================================
-- The other look: no header or footer, just the map. The zone name,
-- coordinates, clock, friends and guild sit on the map in small dark pills,
-- each at the edge spot its setting names; the ones set to wait for the
-- mouse fade in while it is over the map.
local PILL_PAD = 4    -- pills' gap from the map's edge (pillPad)
local PILL_GAP = 2    -- between pills stacked at the same spot (pillGap)
local Pill, PillEdge  -- the pill builder (below, with the panel)

local SPOTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true,
                BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }

local function Overlay()
    return Setting("layout") ~= "panel"
end

local function TextSize()
    local v = tonumber(Setting("textSize")) or 12
    return math.max(8, math.min(20, math.floor(v + 0.5)))
end

local function PillAlpha()
    local v = tonumber(Setting("pillAlpha")) or 0.82
    return math.max(0, math.min(1, v))
end

local function PillRGB()
    local c = Setting("pillColor")
    if type(c) == "table" then
        local r, g, b = ns.ColorOf(c)
        return r, g, b
    end
    c = GetColor("ui", "windowBg")
    return c.r, c.g, c.b
end

local function PaintPill(t)
    local r, g, b = PillRGB()
    t:SetVertexColor(r, g, b, PillAlpha())
    -- the optional edge (Pill gives every pill one, hidden unless asked)
    local strips = t._zEdge
    if strips then
        local on = Look("pillBorder") and true or false
        local c = Setting("pillBorderColor")
        local er, eg, eb, ea
        if type(c) == "table" then er, eg, eb, ea = ns.ColorOf(c)
        else
            local p = GetColor("ui", "border")
            er, eg, eb, ea = p.r, p.g, p.b, p.a or 1
        end
        for _, e in ipairs(strips) do
            e:SetShown(on)
            e:SetVertexColor(er, eg, eb, ea)
        end
    end
end

-- The map's outline and the hover ring: UI.Border boxes, in the palette
-- unless a colour is set, at the chosen thickness (UI.Border makes its
-- strips top, bottom, left, right).
local function PaintOutline(frame, key, size)
    if not frame then return end
    ns.UI.PaintBox(frame)
    local strips = frame._zBorder
    if not strips then return end
    local c = Setting(key)
    local r, g, b, a
    if type(c) == "table" then r, g, b, a = ns.ColorOf(c) end
    for i, t in ipairs(strips) do
        if r then t:SetVertexColor(r, g, b, a) end
        if size then
            local w = math.max(0, math.min(4, size))
            t:SetShown(w > 0)
            if w > 0 then
                if i <= 2 then t:SetHeight(w) else t:SetWidth(w) end
            end
        end
    end
end

-- The zone pill is as wide as the name, but never wider than the room
-- between the corner icons.
local function SizeZone()
    local zt = ZoneText()
    if not (mm.zonePill and zt) then return end
    local maxW = (Minimap:GetWidth() or 140) - 2 * (ICON + 8)
    local w = (TextWidth(zt) or 0) + 16
    mm.zonePill:SetWidth(math.max(40, math.min(w, maxW)))
end

-- Placing order: the first piece at a spot sits on the edge, the next
-- stacks inward from it.
local function PillList()
    return {
        { frame = mm.clockPill,   key = "clockPos",   def = "BOTTOM" },
        { frame = mm.friendsPill, key = "friendsPos", def = "BOTTOMLEFT" },
        { frame = mm.guildPill,   key = "guildPos",   def = "BOTTOMRIGHT" },
        { frame = mm.coords,      key = "coordsPos",  def = "BOTTOM" },
        { frame = mm.zonePill,    key = "zonePos",    def = "TOP" },
    }
end

-- A corner taken by one of Blizzard's icons (mail, tracking, the group
-- finder eye, the battleground crest) pushes its pills along the edge,
-- only while that icon is showing.
local function CornerBusy(point)
    local f = mm.cornerIcons and mm.cornerIcons[point]
    -- an icon placed somewhere else (anchors.<icon>) has left its corner
    return f and f:IsShown() and f._zMinimapWant ~= false and not f._zIconPlaced
end

-- The stacking itself, for any map: the real one, or the Minimap page's
-- sample. `list` is PillList's shape; `busy(point)` says whether a corner
-- icon is in the way.
-- A piece's FINE PLACEMENT (ZacUIDB.minimap.anchors.<zone|clock|coords|
-- friends|guild>, ZacUI's anchor shape): its spot above as the default,
-- the saved anchor on top - any point of the map or of another piece. A
-- placed piece leaves the stack; nothing saved = the stacking as always.
local PIECE_OF = { zonePos = "zone", clockPos = "clock", coordsPos = "coords", friendsPos = "friends", guildPos = "guild" }
local function PillAnchor(key)
    local a = Setting("anchors")
    local k = PIECE_OF[key]
    return k and type(a) == "table" and a[k] or nil
end
local pillDef = {}
local function PlacePillsOn(map, list, busy)
    local pad = tonumber(Look("pillPad")) or PILL_PAD
    local gap = tonumber(Look("pillGap")) or PILL_GAP
    local stack = {}
    local function To(k)
        if k == "map" then return map end
        for _, pc in ipairs(list) do if PIECE_OF[pc.key] == k then return pc.frame end end
    end
    for _, pc in ipairs(list) do
        local f = pc.frame
        if f and f:IsShown() then
            local point = Setting(pc.key)
            if not SPOTS[point] then point = pc.def end
            local top = point:find("TOP") ~= nil
            local x = 0
            if point:find("LEFT") then
                x = pad + ((busy and busy(point)) and (ICON + 4) or 0)
            elseif point:find("RIGHT") then
                x = -pad - ((busy and busy(point)) and (ICON + 4) or 0)
            end
            local spec = PillAnchor(pc.key)
            if spec then
                local t = pillDef[pc.key] or {}
                pillDef[pc.key] = t
                t.point, t.relPoint, t.to, t.x, t.y = point, point, map, x, top and -pad or pad
                ns.ApplyAnchor(f, spec, t, To)
            else
                local y = pad + (stack[point] or 0)
                f:ClearAllPoints()
                f:SetPoint(point, map, point, x, top and -y or y)
                stack[point] = (stack[point] or 0) + (f:GetHeight() or 0) + gap
            end
        end
    end
end
-- what a piece's fine placement starts from (the settings page)
local function PillDefault(key)
    local point = Setting(key)
    local pad = tonumber(Look("pillPad")) or PILL_PAD
    local def = ({ clockPos = "BOTTOM", friendsPos = "BOTTOMLEFT", guildPos = "BOTTOMRIGHT", coordsPos = "BOTTOM", zonePos = "TOP" })[key]
    if not SPOTS[point] then point = def or "CENTER" end
    local x = point:find("LEFT") and pad or (point:find("RIGHT") and -pad or 0)
    return { point = point, relPoint = point, x = x, y = point:find("TOP") and -pad or pad }
end

-- THE PANEL LOOK'S TEXTS AND THE CORNER ICONS, placeable too
-- (ZacUIDB.minimap.anchors.<panelZone|panelClock|panelFriends|panelGuild|
-- panelCoords> and .<mail|tracking|battlefield|lfg>, ZacUI's anchor shape).
-- Where this file always put each one is the default and the saved anchor
-- goes on top: any point of the map, the header, the footer or another
-- piece. Nothing saved = never touched. `parts` names the pieces, so the
-- real map and the Minimap page's sample go through the same code:
--   map, header, footer, coords (frames); zone / clock / friends / guild
--   (the texts) with zoneHost / clockHost / friendsHost / guildHost (what
--   each sits in: the zone button, the clock, the footer cells); icons
--   { mail =, tracking =, battlefield =, lfg = } (frames)
local PANEL_TEXTS = { "panelZone", "panelClock", "panelFriends", "panelGuild", "panelCoords" }
local PANEL_FIELD = { panelZone = "zone", panelClock = "clock", panelFriends = "friends",
    panelGuild = "guild", panelCoords = "coords" }
local ICON_KEYS = { "mail", "tracking", "battlefield", "lfg" }
-- each icon's corner (CornerIcon's / the module's own SetPoint)
local ICON_SPOT = {
    mail = { "TOPLEFT", 3, -3 }, tracking = { "BOTTOMLEFT", 3, 3 },
    battlefield = { "BOTTOMRIGHT", 0, 0 }, lfg = { "TOPRIGHT", 1, 1 },
}
local function AnchorSpec(key)
    local a = Setting("anchors")
    local s = type(a) == "table" and a[key] or nil
    if type(s) ~= "table" or next(s) == nil then return nil end
    return s
end

-- What each one starts from, with its host frame as `to` (the page asks
-- with no parts: the same points, nothing to hang them on).
local function FillPanelDefault(d, key, parts)
    d.point2, d.relPoint2, d.x2, d.y2, d.justify = nil, nil, nil, nil, nil
    if key == "panelZone" then
        d.point, d.relPoint, d.x, d.y, d.to = "LEFT", "LEFT", 0, 0, parts and parts.zoneHost
        d.point2, d.relPoint2, d.x2, d.y2, d.justify = "RIGHT", "RIGHT", 0, 0, "CENTER"
    elseif key == "panelClock" then
        d.point, d.relPoint, d.x, d.y, d.to = "CENTER", "CENTER", 0, 0, parts and parts.clockHost
    elseif key == "panelFriends" or key == "panelGuild" then
        d.point, d.relPoint, d.x, d.y = "LEFT", "LEFT", 4, 0
        d.to = parts and parts[key == "panelFriends" and "friendsHost" or "guildHost"]
        d.point2, d.relPoint2, d.x2, d.y2, d.justify = "RIGHT", "RIGHT", -4, 0, "CENTER"
    else -- panelCoords: along the map's bottom edge
        d.point, d.relPoint, d.x, d.y, d.to = "BOTTOM", "BOTTOM", 0, 3, parts and parts.map
    end
    return d
end
local function PanelDefault(key) return FillPanelDefault({}, key, nil) end
local function IconDefault(key, map)
    local s = ICON_SPOT[key] or ICON_SPOT.mail
    return { point = s[1], relPoint = s[1], x = s[2], y = s[3], to = map }
end

-- "map" / "header" / "footer", a panel text's key or an icon's key -> its frame
local function Resolver(parts)
    local r = parts._resolve
    if not r then
        r = function(k)
            if k == "map" or k == "header" or k == "footer" then return parts[k] end
            local f = PANEL_FIELD[k]
            if f then return parts[f] end
            return parts.icons and parts.icons[k]
        end
        parts._resolve = r
    end
    return r
end

-- A two-point text moved off its span needs a width: its host's, less the
-- span's insets (or the map's when the host has none yet).
local function SpanWidth(parts, key, inset)
    local host = parts[PANEL_FIELD[key] .. "Host"]
    local w = host and host.GetWidth and host:GetWidth() or 0
    if not w or w <= 0 then w = (parts.map and parts.map:GetWidth()) or 140 end
    return math.max(20, w - inset)
end

-- panel = true on the panel look; on the map-only look a text the panel
-- moved goes back to its default (the clock's and the footer cells' texts
-- are not placed again by anything else), the zone name and coordinates
-- being placed by the pills there.
local function PlacePanelTexts(parts, panel)
    local defs = parts._def or {}
    parts._def = defs
    for _, key in ipairs(PANEL_TEXTS) do
        local region = parts[PANEL_FIELD[key]]
        if region and region.SetPoint then
            local spec = panel and AnchorSpec(key) or nil
            local restore = key == "panelClock" or key == "panelFriends" or key == "panelGuild"
            if spec or (region._zPanelPlaced and (panel or restore)) then
                local d = FillPanelDefault(defs[key] or {}, key, parts)
                defs[key] = d
                local _, two = ns.ApplyAnchor(region, spec, d, Resolver(parts))
                if spec and not two and d.point2 then
                    region:SetWidth(SpanWidth(parts, key, key == "panelZone" and 0 or 8))
                end
            end
            region._zPanelPlaced = spec and true or nil
        end
    end
end

-- The corner icons: any point of the map or of another icon. Only an icon
-- with a saved anchor (or one that had one) is touched.
local function PlaceIcons(parts)
    local icons = parts.icons
    if not icons then return end
    local defs = parts._idef or {}
    parts._idef = defs
    for _, key in ipairs(ICON_KEYS) do
        local f = icons[key]
        -- never one the button tray holds (the eye can end up there)
        if f and f.SetPoint and not f._zCell and not (f.IsProtected and f:IsProtected() and InCombatLockdown()) then
            local spec = AnchorSpec(key)
            if spec or f._zIconPlaced then
                local d = defs[key] or IconDefault(key, parts.map)
                d.to = parts.map
                defs[key] = d
                ns.ApplyAnchor(f, spec, d, Resolver(parts))
            end
            f._zIconPlaced = spec and true or nil
        end
    end
end

-- the live map's parts (one table, refreshed: the clock arrives late)
local liveParts = { icons = {} }
local function LiveParts()
    local p = liveParts
    p.map, p.header, p.footer, p.coords = Minimap, mm.header, mm.footer, mm.coords
    p.zone, p.zoneHost = ZoneText(), ZoneButton()
    p.clock, p.clockHost = TimeManagerClockTicker, TimeManagerClockButton
    p.friends, p.friendsHost = mm.friends and mm.friends._zText, mm.friends
    p.guild, p.guildHost = mm.guild and mm.guild._zText, mm.guild
    local icons = mm.iconFrames
    p.icons.mail = icons and icons.mail
    p.icons.tracking = icons and icons.tracking
    p.icons.battlefield = icons and icons.battlefield
    p.icons.lfg = icons and icons.lfg
    return p
end

local function PlacePills()
    if not mm.zonePill then return end
    PlacePillsOn(Minimap, PillList(), CornerBusy)
end

-- Coordinates: on the panel look along the map's bottom edge; on the
-- overlay look wherever the pills put them.
local function PlaceCoords()
    local co = mm.coords
    if not co then return end
    if Overlay() then
        PlacePills()
    else
        co:ClearAllPoints()
        co:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 3)
        if AnchorSpec("panelCoords") then PlacePanelTexts(LiveParts(), true) end
    end
end

-- Zone name colour: Blizzard's PvP colouring, or the accent. Blizzard
-- re-colours the string on every zone update, so the accent rides a hook.
local function ApplyZoneColour()
    local zt = ZoneText()
    if not zt then return end
    if not zt._zColourHook then
        zt._zColourHook = true
        hooksecurefunc(zt, "SetTextColor", function(self)
            if self._zRecolour or Setting("zoneColor") ~= "accent" then return end
            self._zRecolour = true
            local c = GetColor("ui", "accent")
            self:SetTextColor(c.r, c.g, c.b, 1)
            self._zRecolour = false
        end)
    end
    if Setting("zoneColor") == "accent" then
        zt:SetTextColor(1, 1, 1, 1)   -- the hook swaps in the accent
    elseif zt._zAccented and Minimap_Update then
        pcall(Minimap_Update)         -- hand the colour back to Blizzard
    end
    zt._zAccented = Setting("zoneColor") == "accent"
end

-- What fades, and which setting lets it. ApplyReveal runs every frame
-- during the hover fade, so the list is built once and the frames it
-- names are re-read on each pass (they can come into being late).
local REVEAL_PARTS = {
    { key = "zoneHover",   frames = {} },
    { key = "coordsHover", frames = {} },
    { key = "socialHover", frames = {} },
    { key = "clockHover",  frames = {} },
}
local function RevealParts()
    local P = REVEAL_PARTS
    P[1].frames[1], P[1].frames[2] = mm.zonePill, ZoneButton()
    P[2].frames[1] = mm.coords
    P[3].frames[1], P[3].frames[2] = mm.friendsPill, mm.guildPill
    P[4].frames[1], P[4].frames[2] = mm.clockPill, TimeManagerClockButton
    return P
end

local function ApplyReveal(a)
    local overlay = Overlay()
    for _, part in ipairs(RevealParts()) do
        local alpha = (overlay and Setting(part.key)) and a or 1
        for _, f in ipairs(part.frames) do
            if f and f.SetAlpha then f:SetAlpha(alpha) end
        end
    end
    if mm.edge then
        mm.edge:SetAlpha((overlay and Setting("hoverEdge")) and a or 0)
    end
end

-- Runs only while the minimap is on screen (OnUpdate stops with it).
-- MouseIsOver is a rect test, so the pills, the corner icons and the
-- secure friends / guild buttons on top of the map all count as "over".
-- Settled (nothing fading) it looks twenty times a second rather than
-- every frame; a fade, once started, runs every frame until it is done.
local hoverIdle = 0
local function HoverTick(_, dt)
    local a = mm.revealA or 0
    if a == 0 or a == 1 then
        hoverIdle = hoverIdle + dt
        if hoverIdle < 0.05 then return end
        dt = math.min(hoverIdle, 0.05)
        hoverIdle = 0
    end
    local target = MouseIsOver(Minimap) and 1 or 0
    if a == target then return end
    local fade = tonumber(Setting("fadeTime")) or 0.2
    -- Appearance > Motion: off makes the fade instant, speed scales it
    local m = ns.Motion
    if m then fade = m.Enabled() and fade / m.Speed() or 0 end
    if fade <= 0 then
        a = target
    elseif target > a then
        a = math.min(target, a + dt / fade)
    else
        a = math.max(target, a - dt / fade)
    end
    mm.revealA = a
    ApplyReveal(a)
end

-- ============================================================
-- SIZE
-- ============================================================
-- The map's own size (0 = Blizzard's), separate from the cluster scale,
-- which grows the text with it. Left exactly where Blizzard put it unless
-- something asks otherwise: a custom size, or the overlay look. Then it is
-- pinned by its top-right corner to the cluster's, so it grows down and to
-- the left and stays on screen under a top-right mover.
local EDGE_IN = 2     -- map's gap from the cluster's corner when ZacUI places it

local function ApplySize()
    local c = MinimapCluster
    if not (c and Minimap) then return end
    if not mm.stock then
        local pts = {}
        for i = 1, (Minimap:GetNumPoints() or 0) do pts[i] = { Minimap:GetPoint(i) } end
        local w, h = Minimap:GetWidth(), Minimap:GetHeight()
        if not (w and w > 0) then return end
        mm.stock = { w = w, h = h, points = pts }
    end
    local want = tonumber(Setting("mapSize")) or 0
    local custom = want > 0
    if custom then
        want = math.max(100, math.min(400, math.floor(want + 0.5)))
    end
    if mm.FarLeave then mm.FarLeave() end    -- (the minimap back out of the zoom clip before it is re-anchored)
    local moved = custom or Overlay()
    if moved then
        -- Flush with the cluster's top-right corner (Blizzard's own spot
        -- leaves ~17px on the right), 2px in so the border and the hover
        -- ring still show; the panel look leaves room for its header.
        local top = Overlay() and EDGE_IN or (HEAD_H + EDGE_IN)
        Minimap:ClearAllPoints()
        Minimap:SetPoint("TOPRIGHT", c, "TOPRIGHT", -EDGE_IN, -top)
    elseif mm.moved then
        Minimap:ClearAllPoints()
        for _, pt in ipairs(mm.stock.points) do Minimap:SetPoint(unpack(pt)) end
    end
    mm.moved = moved
    local tw, th = mm.stock.w, mm.stock.h
    if custom then tw, th = want, want end
    if math.abs((Minimap:GetWidth() or 0) - tw) >= 0.5 or math.abs((Minimap:GetHeight() or 0) - th) >= 0.5 then
        Minimap:SetSize(tw, th)
        -- The map texture only redraws at the new size on a zoom change.
        local z = Minimap:GetZoom() or 0
        Minimap:SetZoom(z > 0 and z - 1 or z + 1)
        C_Timer.After(0, function() Minimap:SetZoom(z) end)
    end
end

local function ClockWidth(pad, minW)
    local tick = TimeManagerClockTicker
    if not (tick and tick.GetFont) then return minW end
    local cur = tick:GetText() or ""
    local w = MeasureLike(tick, cur:find("%a") and "88:88 PM" or "88:88")
    if w > 0 then return math.max(minW, w + pad) end
    return minW
end

local function OverlayLayout()
    local p = mm.panel
    local size = TextSize()
    local pillH = size + 7
    local zoneBtn = ZoneButton()
    local clock = TimeManagerClockButton
    local zoneOn = Want("zoneName") and zoneBtn ~= nil
    local clockOn = Want("clock") and clock ~= nil and clock:IsShown()
    local infoOn = Want("infoBar")
    mm.wasOverlay = true

    mm.header:Hide()
    mm.footer:Hide()
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1, 1)
    p:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 1, -1)
    for _, pill in ipairs({ mm.zonePill, mm.clockPill, mm.friendsPill, mm.guildPill }) do
        pill:SetHeight(pillH)
        pill:_zPaint()
    end

    -- Zone name.
    mm.zonePill:SetShown(zoneOn)
    if zoneOn then
        zoneBtn:ClearAllPoints()
        zoneBtn:SetAllPoints(mm.zonePill)
        zoneBtn:SetFrameLevel(mm.zonePill:GetFrameLevel() + 2)
        local zt = ZoneText()
        if zt then
            StyleFS(zt, size)
            zt:ClearAllPoints()
            zt:SetPoint("LEFT", mm.zonePill, "LEFT", 7, 0)
            zt:SetPoint("RIGHT", mm.zonePill, "RIGHT", -7, 0)
            zt:SetJustifyH("CENTER")
            if zt.SetWordWrap then zt:SetWordWrap(false) end
            if not zt._zSizeHook then
                zt._zSizeHook = true
                hooksecurefunc(zt, "SetText", function()
                    if Overlay() then SizeZone() end
                end)
            end
        end
        SizeZone()
    end

    -- Clock.
    mm.clockPill:SetShown(clockOn)
    if clockOn then
        if TimeManagerClockTicker then StyleFS(TimeManagerClockTicker, size) end
        mm.clockPill:SetWidth(ClockWidth(14, 34))
        clock:ClearAllPoints()
        clock:SetAllPoints(mm.clockPill)
        clock:SetFrameLevel(mm.clockPill:GetFrameLevel() + 2)
    end
    -- Friends and guild, a pill each. Sized for a two-digit count so they
    -- hold still as people log on and off.
    mm.divL:Hide()
    mm.divR:Hide()
    local fl = (FRIENDS or "Friends"):sub(1, 2)
    local gl = (GUILD or "Guild"):sub(1, 1)
    for _, pair in ipairs({ { mm.friends, mm.friendsPill, fl }, { mm.guild, mm.guildPill, gl } }) do
        local seg, pill, label = pair[1], pair[2], pair[3]
        pill:SetShown(infoOn)
        if infoOn then
            seg:SetParent(pill)
            seg:SetFrameLevel(pill:GetFrameLevel() + 1)
            seg._zOverlay = true
            seg:_zPaint()
            StyleFS(seg._zText, size - 1)
            seg:ClearAllPoints()
            seg:SetAllPoints(pill)
            seg:Show()
            pill:SetWidth(MeasureLike(seg._zText, label .. " 88") + 12)
        end
    end

    -- Coordinates.
    mm.coords:SetShown(Want("coords"))
    mm.coords:SetHeight(pillH)
    if mm.coordsText then StyleFS(mm.coordsText, size - 1) end
    if mm.coordsReset then mm.coordsReset() end
    mm.coords:_zPaint()
    PlacePills()
    -- texts the panel look placed go home (nothing saved: nothing to do)
    PlacePanelTexts(LiveParts(), false)

    mm.edge:Show()
    mm.edge:_zPaint()
    mm.revealA = MouseIsOver(Minimap) and 1 or 0
    ApplyReveal(mm.revealA)
    mm.hover:SetScript("OnUpdate", HoverTick)
end

-- Back from the overlay look: pieces home, sizes and alphas as they were.
local function UndoOverlay()
    if not mm.wasOverlay then return end
    mm.wasOverlay = false
    mm.hover:SetScript("OnUpdate", nil)
    mm.revealA = 1
    ApplyReveal(1)
    mm.edge:Hide()
    mm.zonePill:Hide()
    mm.clockPill:Hide()
    mm.friendsPill:Hide()
    mm.guildPill:Hide()
    for _, seg in ipairs({ mm.friends, mm.guild }) do
        seg:SetParent(mm.footer)
        seg:ClearAllPoints()
        seg:SetSize(0, 0)   -- the footer's anchors size it again
        seg:SetFrameLevel(mm.footer:GetFrameLevel() + 1)
        seg._zOverlay = false
        seg:_zPaint()
        StyleFS(seg._zText, ns.UI.F.SMALL)
    end
    local zt = ZoneText()
    if zt then StyleFS(zt, 12) end
    if TimeManagerClockTicker then StyleFS(TimeManagerClockTicker, 11) end
    if mm.coordsText then StyleFS(mm.coordsText, ns.UI.F.SMALL) end
    mm.coords:SetHeight(14)
    if mm.coordsReset then mm.coordsReset() end
    mm.coords:_zPaint()
end

-- ============================================================
-- LAYOUT
-- ============================================================
-- Which of header / footer / clock / info are on decides the panel's
-- outline, so every option change ends here.
local function Layout()
    local p = mm.panel
    if not p then return end
    ApplySize()
    ApplyZoneColour()
    -- corner icons first: a placed one no longer pushes the pills along
    PlaceIcons(LiveParts())
    p:_zPaint()
    if mm.edge then mm.edge:_zPaint() end
    if Overlay() then
        OverlayLayout()
        if mm.PlaceSecure then mm.PlaceSecure() end
        if mm.RefreshInfo then C_Timer.After(0, mm.RefreshInfo) end
        return
    end
    UndoOverlay()
    local zoneBtn = ZoneButton()
    local clock = TimeManagerClockButton
    local headOn = Want("zoneName") and zoneBtn ~= nil
    local clockOn = Want("clock") and clock ~= nil and clock:IsShown()
    local infoOn = Want("infoBar")
    local footOn = clockOn or infoOn

    mm.header:SetShown(headOn)
    mm.footer:SetShown(footOn)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", headOn and mm.header or Minimap, "TOPLEFT", -1, 1)
    p:SetPoint("BOTTOMRIGHT", footOn and mm.footer or Minimap, "BOTTOMRIGHT", 1, -1)

    if headOn then
        zoneBtn:ClearAllPoints()
        zoneBtn:SetPoint("TOPLEFT", mm.header, "TOPLEFT", 4, 0)
        zoneBtn:SetPoint("BOTTOMRIGHT", mm.header, "BOTTOMRIGHT", -4, 1)
        zoneBtn:SetFrameLevel(mm.header:GetFrameLevel() + 2)
        local zt = ZoneText()
        if zt then
            zt:ClearAllPoints()
            zt:SetPoint("LEFT", zoneBtn, "LEFT", 0, 0)
            zt:SetPoint("RIGHT", zoneBtn, "RIGHT", 0, 0)
            zt:SetJustifyH("CENTER")
            if zt.SetWordWrap then zt:SetWordWrap(false) end
        end
    end

    local f, c = mm.footer, mm.clockSeg
    -- The clock cell is as wide as the time needs and no wider, so the
    -- friends and guild cells get the rest (a fixed 58 px squeezed them
    -- to "Fr 4" / "G 2" on a normal-size map). Measured on a stand-in of
    -- the widest digits, so the footer does not twitch as the time changes.
    local clockW = clockOn and ClockWidth(12, 34) or CLOCK_W
    mm.divL:Hide()
    mm.divR:Hide()
    mm.friends:SetShown(infoOn)
    mm.guild:SetShown(infoOn)
    c:ClearAllPoints()
    mm.friends:ClearAllPoints()
    mm.guild:ClearAllPoints()
    if clockOn and infoOn then
        c:SetPoint("TOP", f, "TOP", 0, -1)
        c:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
        c:SetWidth(clockW)
        mm.friends:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -1)
        mm.friends:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT", -1, 0)
        mm.guild:SetPoint("TOPLEFT", c, "TOPRIGHT", 1, 0)
        mm.guild:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        mm.divL:ClearAllPoints()
        mm.divL:SetPoint("TOPRIGHT", c, "TOPLEFT", 0, 0)
        mm.divL:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT", 0, 0)
        mm.divR:ClearAllPoints()
        mm.divR:SetPoint("TOPLEFT", c, "TOPRIGHT", 0, 0)
        mm.divR:SetPoint("BOTTOMLEFT", c, "BOTTOMRIGHT", 0, 0)
        mm.divL:Show()
        mm.divR:Show()
    elseif infoOn then
        c:SetPoint("TOP", f, "TOP", 0, -1)
        c:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
        c:SetWidth(1)
        mm.friends:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -1)
        mm.friends:SetPoint("BOTTOMRIGHT", c, "BOTTOMLEFT", 0, 0)
        mm.guild:SetPoint("TOPLEFT", c, "TOPRIGHT", 0, 0)
        mm.guild:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        mm.divL:ClearAllPoints()
        mm.divL:SetAllPoints(c)
        mm.divL:Show()
    else
        c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -1)
        c:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    end
    if clockOn then
        clock:ClearAllPoints()
        clock:SetAllPoints(c)
        clock:SetFrameLevel(f:GetFrameLevel() + 3)
    end

    mm.coords:SetShown(Want("coords"))
    PlaceCoords()
    PlacePanelTexts(LiveParts(), true)
    if mm.PlaceSecure then mm.PlaceSecure() end
    if mm.RefreshInfo then C_Timer.After(0, mm.RefreshInfo) end
end

-- ============================================================
-- TIME MANAGER BITS (clock, clock popout, stopwatch)
-- ============================================================
-- Blizzard_TimeManager is LOAD-ON-DEMAND, and on some characters it has
-- NOT loaded yet when the minimap module runs at login. Routed through
-- RegisterLoD: runs immediately when it is already loaded, or the moment
-- its ADDON_LOADED fires. Idempotent either way.
local function SkinTimeBits()
    local clock = TimeManagerClockButton
    if clock and Minimap and not clock._zMinimap then
        clock._zMinimap = true
        for _, region in ipairs({ clock:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture") then
                region:SetTexture(nil)
                region:SetAlpha(0)
            end
        end
        -- Blizzard's hit rect is inset for its round-ended art; the whole
        -- footer cell is the button now.
        if clock.SetHitRectInsets then clock:SetHitRectInsets(0, 0, 0, 0) end
        local hl = clock:CreateTexture(nil, "HIGHLIGHT")
        hl._zui_own = true
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        -- The footer changes shape with the clock (the "Show clock"
        -- interface option shows and hides it).
        clock:HookScript("OnShow", Layout)
        clock:HookScript("OnHide", Layout)
    end
    if TimeManagerClockTicker then
        StyleFS(TimeManagerClockTicker, 11)
        local tc = Col("text")
        TimeManagerClockTicker:SetTextColor(tc.r, tc.g, tc.b, 1)
        TimeManagerClockTicker:ClearAllPoints()
        TimeManagerClockTicker:SetPoint("CENTER", clock, "CENTER", 0, 0)
    end
    -- Clock popouts: dark panels, close buttons removed (they toggle
    -- from the clock; close names vary by build so all variants are
    -- handled)
    if TimeManagerFrame then
        StripTextures(TimeManagerFrame)
        StripFrameChrome(TimeManagerFrame)
        SkinBackdrop(TimeManagerFrame, "windowBg", 0.97)
        RemoveClose(TimeManagerCloseButton)
        RemoveClose(TimeManagerFrameCloseButton)
        RemoveClose(TimeManagerFrame.CloseButton)
        if TimeManagerAlarmEnabledButton then SkinButton(TimeManagerAlarmEnabledButton) end
    end
    if StopwatchFrame then
        StripTextures(StopwatchFrame)
        SkinBackdrop(StopwatchFrame, "windowBg", 0.9)
        RemoveClose(StopwatchCloseButton)
        RemoveClose(StopwatchFrameCloseButton)
        RemoveClose(StopwatchFrame.CloseButton)
    end
    Layout()
end

-- ============================================================
-- PANEL
-- ============================================================
-- A 1px strip in a palette colour, repainted with the rest.
local function Rule(parent, cat, key, alpha, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, 5)
    t._zui_own = true
    t:SetTexture(ns.FLAT)
    t._zCat, t._zKey, t._zAlpha = cat, key, alpha
    return t
end

local function PaintRule(t)
    local c = GetColor(t._zCat, t._zKey)
    t:SetVertexColor(c.r, c.g, c.b, t._zAlpha or c.a or 1)
end

-- A footer cell: flat, the header colour, lighter under the mouse.
local function Segment(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ns.UI.Fill(b, "ui", "headerBg")
    b._zText = ns.UI.Font(b, ns.UI.F.SMALL, { cat = "text", key = "normal" })
    b._zText:SetPoint("LEFT", 4, 0)
    b._zText:SetPoint("RIGHT", -4, 0)
    b._zText:SetJustifyH("CENTER")
    b._zText:SetWordWrap(false)
    b._zPaint = function(self)
        -- On the overlay pill the cell is see-through: the pill is the fill.
        local c = GetColor("ui", "headerBg")
        self._zFill:SetVertexColor(c.r, c.g, c.b, self._zOverlay and 0 or (c.a or 1))
        self._zText:_zPaint()
    end
    b:HookScript("OnEnter", function(self)
        local c = GetColor("button", "hover")
        self._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1)
    end)
    b:HookScript("OnLeave", function(self) self:_zPaint() end)
    b:_zPaint()
    return b
end

local function TooltipTitle(owner, text)
    -- below the footer by default; the chat bar borrows these tooltips
    -- from the bottom of the screen and asks for them above instead
    GameTooltip:SetOwner(owner, owner._zTipAnchor or "ANCHOR_BOTTOM")
    local t = GetColor("tooltip", "title")
    GameTooltip:SetText(text, t.r, t.g, t.b)
end

local function TooltipHint(text)
    local g = GetColor("text", "gray")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(text, g.r, g.g, g.b)
end

-- Only reached if the secure overlays below could not be made. FriendsFrame
-- is a protected panel (the raid page, ZacUI's secure tabs), so an addon
-- cannot open it in combat; and ToggleFriendsFrame(tab) from addon code
-- would write FriendsFrame.selectedTab tainted, which then poisons every
-- later Friends-page update Blizzard makes in combat. So: no tab, and not
-- in combat.
local function OpenSocial()
    if InCombatLockdown() then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "You can't do that while in combat.", 1, 0.1, 0.1)
        end
        return
    end
    if ToggleFriendsFrame then ToggleFriendsFrame() end
end

local function BNetOnline()
    if not BNGetNumFriends then return 0 end
    local ok, _, online = pcall(BNGetNumFriends)
    return (ok and online) or 0
end

local function FriendsTooltip(self)
    TooltipTitle(self, FRIENDS or "Friends")
    local g = GetColor("text", "gray")
    local shown, online = 0, 0
    local total = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
    for i = 1, total do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected then
            online = online + 1
            if shown < 20 then
                shown = shown + 1
                local line = info.name or "?"
                if info.level and info.level > 0 then line = line .. "  |cff888888" .. info.level .. "|r" end
                if info.area and info.area ~= "" then line = line .. "  |cff666666" .. info.area .. "|r" end
                GameTooltip:AddLine(line, 0.9, 0.9, 0.9)
            end
        end
    end
    -- Battle.net friends, by account name, with the character when they
    -- are in a game.
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        local bnTotal = select(1, BNGetNumFriends()) or 0
        for i = 1, bnTotal do
            local ok, acc = pcall(C_BattleNet.GetFriendAccountInfo, i)
            local game = ok and acc and acc.gameAccountInfo
            if game and game.isOnline then
                online = online + 1
                if shown < 25 then
                    shown = shown + 1
                    local line = "|cff82c5ff" .. (acc.accountName or "?") .. "|r"
                    if game.characterName and game.characterName ~= "" then
                        line = line .. "  " .. game.characterName
                    end
                    if game.areaName and game.areaName ~= "" then
                        line = line .. "  |cff666666" .. game.areaName .. "|r"
                    end
                    GameTooltip:AddLine(line, 0.9, 0.9, 0.9)
                end
            end
        end
    end
    if online == 0 then
        GameTooltip:AddLine("No friends online", g.r, g.g, g.b)
    elseif online > shown then
        GameTooltip:AddLine("...and " .. (online - shown) .. " more", g.r, g.g, g.b)
    end
    TooltipHint("Click to open your friends list")
    GameTooltip:Show()
end

local function GuildTooltip(self)
    if not (IsInGuild and IsInGuild()) then
        TooltipTitle(self, GUILD or "Guild")
        local g = GetColor("text", "gray")
        GameTooltip:AddLine("You are not in a guild", g.r, g.g, g.b)
        GameTooltip:Show()
        return
    end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
    TooltipTitle(self, (GetGuildInfo and GetGuildInfo("player")) or GUILD or "Guild")
    local g = GetColor("text", "gray")
    local total = GetNumGuildMembers() or 0
    local shown, online = 0, 0
    for i = 1, total do
        local name, _, _, level, _, zone, _, _, isOnline, _, classFile = GetGuildRosterInfo(i)
        if isOnline then
            online = online + 1
            if shown < 25 then
                shown = shown + 1
                local short = name and name:match("^([^%-]+)") or "?"
                local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                local line = cc and string.format("|cff%02x%02x%02x%s|r",
                    cc.r * 255, cc.g * 255, cc.b * 255, short) or short
                if level then line = line .. "  |cff888888" .. level .. "|r" end
                if zone and zone ~= "" then line = line .. "  |cff666666" .. zone .. "|r" end
                GameTooltip:AddLine(line, 0.9, 0.9, 0.9)
            end
        end
    end
    if online == 0 then
        GameTooltip:AddLine("Nobody online", g.r, g.g, g.b)
    elseif online > shown then
        GameTooltip:AddLine("...and " .. (online - shown) .. " more", g.r, g.g, g.b)
    end
    TooltipHint("Click to open the guild roster")
    GameTooltip:Show()
end

-- The longest label that fits the cell: "Friends 3", then "Fr 3", then
-- just the number. A small or scaled-down minimap leaves each footer
-- cell only a few dozen pixels, and a clipped "Frie..." says nothing.
-- (TextWidth, the width the text wants, is defined near the top.)
local function FitLabel(seg, long, short, count, accent)
    local fs = seg._zText
    local room = (seg:GetWidth() or 0) - 8
    local n = "|cff" .. accent .. count .. "|r"
    fs:SetText(long .. " " .. n)
    if room > 0 and TextWidth(fs) > room then
        fs:SetText(short .. " " .. n)
        if TextWidth(fs) > room then fs:SetText(n) end
    end
end

local function RefreshInfo()
    if not mm.friends then return end
    local accent = Hex(Col("accent"))
    local fOnline = 0
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
        fOnline = C_FriendList.GetNumOnlineFriends() or 0
    end
    fOnline = fOnline + BNetOnline()
    local fl = FRIENDS or "Friends"
    -- The overlay pill: short labels in gray, counts in the accent.
    if mm.wasOverlay then
        local g = Hex(GetColor("text", "gray"))
        mm.friends._zText:SetText("|cff" .. g .. fl:sub(1, 2) .. "|r |cff" .. accent .. fOnline .. "|r")
        local gl = (GUILD or "Guild"):sub(1, 1)
        local n = "|cff" .. g .. "-|r"
        if IsInGuild and IsInGuild() then
            local _, gOnline = GetNumGuildMembers()
            n = "|cff" .. accent .. (gOnline or 0) .. "|r"
        end
        mm.guild._zText:SetText("|cff" .. g .. gl .. "|r " .. n)
        return
    end
    FitLabel(mm.friends, fl, fl:sub(1, 2), fOnline, accent)
    if IsInGuild and IsInGuild() then
        local _, gOnline = GetNumGuildMembers()
        local gl = GUILD or "Guild"
        FitLabel(mm.guild, gl, gl:sub(1, 1), gOnline or 0, accent)
    else
        local g = Hex(GetColor("text", "gray"))
        mm.guild._zText:SetText("|cff" .. g .. "No guild|r")
        if (mm.guild:GetWidth() or 0) > 0 and TextWidth(mm.guild._zText) > mm.guild:GetWidth() - 8 then
            mm.guild._zText:SetText("|cff" .. g .. "-|r")
        end
    end
end

-- ============================================================
-- SECURE CLICKS FOR FRIENDS / GUILD
-- ============================================================
-- Opening the social window on a given tab has to run with Blizzard's
-- credentials (see OpenSocial). Each footer cell gets a SecureActionButton
-- over it whose macro clicks Blizzard's own Social micro button and tab:
--   window closed -> open it, then its Friends (or Guild) tab
--   window open   -> close it
-- The overlays are parented to UIParent and placed by absolute position,
-- NOT anchored to the footer: a secure frame's parent and anchor both
-- become protected, and that would lock the whole minimap in combat.
-- Placed out of combat only; they only move when the minimap does.
local secureHeader
local function PlaceSecure()
    if not mm.secure then return end
    if InCombatLockdown() then
        mm.securePending = true
        return
    end
    mm.securePending = false
    local us = UIParent:GetEffectiveScale()
    for _, o in ipairs(mm.secure) do
        local seg = o._zSeg
        local l, b, w, h = seg:GetRect()
        if l and w and w > 0 and seg:IsVisible() then
            local k = seg:GetEffectiveScale() / us
            o:ClearAllPoints()
            o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * k, b * k)
            o:SetSize(w * k, h * k)
            o:Show()
        else
            o:Hide()
        end
    end
end

local function QueuePlaceSecure()
    if mm.secure then C_Timer.After(0, PlaceSecure) end
end

local function BuildSecure()
    if mm.secure or InCombatLockdown() then return end
    if not (SecureHandlerWrapScript and SecureHandlerSetFrameRef
        and FriendsFrame and SocialsMicroButton) then return end
    secureHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    mm.secure = {}
    local specs = {
        { seg = mm.friends, tab = 1, tip = function(o) FriendsTooltip(o) end },
        { seg = mm.guild,   tab = 3, tip = function(o) GuildTooltip(o) end },
    }
    for _, spec in ipairs(specs) do
        local seg = spec.seg
        local o = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
        o:SetFrameStrata(Minimap:GetFrameStrata())
        o:SetFrameLevel(math.min(Minimap:GetFrameLevel() + 20, 9000))
        o:SetAttribute("useOnKeyDown", false)
        o:RegisterForClicks("AnyUp")
        o:SetAttribute("type", "macro")
        o:SetAttribute("zOpen", "/click SocialsMicroButton\n/click FriendsFrameTab" .. spec.tab)
        o:SetAttribute("macrotext", o:GetAttribute("zOpen"))
        SecureHandlerSetFrameRef(o, "ff", FriendsFrame)
        SecureHandlerWrapScript(o, "OnClick", secureHeader, [[
            if self:GetFrameRef("ff"):IsShown() then
                self:SetAttribute("macrotext", "/click SocialsMicroButton")
            else
                self:SetAttribute("macrotext", self:GetAttribute("zOpen"))
            end
        ]])
        -- The look stays on the footer cell; the overlay forwards hover.
        o:SetScript("OnEnter", function(self)
            local c = GetColor("button", "hover")
            seg._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1)
            spec.tip(self)
        end)
        o:SetScript("OnLeave", function()
            seg:_zPaint()
            GameTooltip:Hide()
        end)
        o._zSeg = seg
        o:Hide()
        mm.secure[#mm.secure + 1] = o
    end
    QueuePlaceSecure()
end

-- A pill's optional 1px edge: four strips, hidden unless asked for.
function PillEdge(frame)
    local strips = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local e = frame:CreateTexture(nil, "BORDER")
        e._zui_own = true
        e:SetTexture(ns.FLAT)
        if side == "TOP" or side == "BOTTOM" then
            e:SetPoint(side .. "LEFT")
            e:SetPoint(side .. "RIGHT")
            e:SetHeight(1)
        else
            e:SetPoint("TOP" .. side)
            e:SetPoint("BOTTOM" .. side)
            e:SetWidth(1)
        end
        e:Hide()
        strips[#strips + 1] = e
    end
    return strips
end

-- One overlay pill: a backing (and its edge) that text sits on. The real
-- ones hang on Minimap; the Minimap page's samples on its preview.
function Pill(parent, name)
    local pf = CreateFrame("Frame", name, parent)
    pf:SetFrameLevel((parent:GetFrameLevel() or 1) + 6)
    local t = pf:CreateTexture(nil, "BACKGROUND")
    t._zui_own = true
    t:SetTexture(ns.FLAT)
    t:SetAllPoints()
    t._zEdge = PillEdge(pf)
    pf._zBack = t
    pf._zPaint = function() PaintPill(t) end
    pf:Hide()
    return pf
end

local function BuildPanel()
    local UI = ns.UI

    -- The outline around header + map + footer. No fill: the map shows
    -- through the middle, and the header and footer bring their own.
    local p = CreateFrame("Frame", "ZacUIMinimapPanel", Minimap)
    p:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    UI.Border(p, "ui", "border")
    p._zPaint = function(self)
        PaintOutline(self, "borderColor", tonumber(Look("borderSize")) or 1)
    end
    mm.panel = p

    local h = CreateFrame("Frame", "ZacUIMinimapHeader", p)
    h:SetHeight(HEAD_H)
    h:SetPoint("BOTTOMLEFT", Minimap, "TOPLEFT", 0, 0)
    h:SetPoint("BOTTOMRIGHT", Minimap, "TOPRIGHT", 0, 0)
    UI.Fill(h, "ui", "headerBg")
    -- The house hairline under a title: accent, at 60%.
    local rule = Rule(h, "ui", "accent", 0.6)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    h._zPaint = function(self)
        UI.PaintBox(self)
        PaintRule(rule)
    end
    mm.header = h

    local f = CreateFrame("Frame", "ZacUIMinimapFooter", p)
    f:SetHeight(FOOT_H)
    f:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", 0, 0)
    f:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, 0)
    UI.Fill(f, "ui", "headerBg")
    local top = Rule(f, "ui", "border")
    top:SetHeight(1)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    mm.clockSeg = CreateFrame("Frame", nil, f)
    -- On the panel, not the footer: the overlay look hides the footer and
    -- still needs to measure.
    mm.measure = p:CreateFontString(nil, "BACKGROUND")
    mm.measure:SetFont(STANDARD_TEXT_FONT, 11, "")
    mm.measure:SetAlpha(0)
    mm.measure:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    mm.divL = Rule(f, "ui", "border", nil, "OVERLAY")
    mm.divL:SetWidth(1)
    mm.divR = Rule(f, "ui", "border", nil, "OVERLAY")
    mm.divR:SetWidth(1)
    f._zPaint = function(self)
        UI.PaintBox(self)
        PaintRule(top)
        PaintRule(mm.divL)
        PaintRule(mm.divR)
    end
    mm.footer = f

    mm.friends = Segment(f)
    mm.friends:SetScript("OnClick", OpenSocial)
    mm.friends:HookScript("OnEnter", FriendsTooltip)
    mm.friends:HookScript("OnLeave", function() GameTooltip:Hide() end)

    mm.guild = Segment(f)
    mm.guild:SetScript("OnClick", OpenSocial)
    mm.guild:HookScript("OnEnter", GuildTooltip)
    mm.guild:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Coordinates along the map's bottom edge. Five times a second, and
    -- only while the minimap is on screen (OnUpdate stops with it).
    local co = CreateFrame("Frame", "ZacUIMinimapCoords", Minimap)
    co:SetFrameLevel(Minimap:GetFrameLevel() + 4)
    co:SetSize(80, 14)
    co:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 3)
    -- On a dark pill: bare text vanished against snow, sand and water.
    local pill = co:CreateTexture(nil, "BACKGROUND")
    pill._zui_own = true
    pill:SetTexture(ns.FLAT)
    pill:SetAllPoints()
    pill._zEdge = PillEdge(co)
    local ct = UI.Font(co, UI.F.SMALL, { cat = "text", key = "normal" })
    ct:SetPoint("CENTER")
    co._zPaint = function()
        ct:_zPaint()
        if Overlay() then
            PaintPill(pill)
        else
            local c = GetColor("ui", "windowBg")
            pill:SetVertexColor(c.r, c.g, c.b, 0.65)
            for _, e in ipairs(pill._zEdge or {}) do e:Hide() end
        end
    end
    mm.coordsText = ct
    local lastText
    local elapsed = 1
    co:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.2 then return end
        elapsed = 0
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
        local x, y
        if pos then x, y = pos:GetXY() end
        local text = ""
        if x and y and (x > 0 or y > 0) then
            text = CoordsText(x, y)
        end
        -- Instances report no position: no text, no pill.
        if text ~= lastText then
            lastText = text
            ct:SetText(text)
            if text == "" then
                pill:Hide()
            else
                pill:Show()
                co:SetWidth(math.ceil(ct:GetStringWidth()) + (Overlay() and 14 or 10))
            end
        end
    end)
    -- A font change re-measures on the next tick.
    mm.coordsReset = function() lastText = nil end
    mm.coords = co

    -- The overlay look's pills: zone name, clock, friends and guild.
    mm.zonePill = Pill(Minimap, "ZacUIMinimapZonePill")
    mm.clockPill = Pill(Minimap, "ZacUIMinimapClockPill")
    mm.friendsPill = Pill(Minimap, "ZacUIMinimapFriendsPill")
    mm.guildPill = Pill(Minimap, "ZacUIMinimapGuildPill")

    -- The accent ring just outside the border, shown while hovered.
    local edge = CreateFrame("Frame", "ZacUIMinimapEdge", p)
    edge:SetPoint("TOPLEFT", p, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 1, -1)
    UI.Border(edge, "ui", "accent")
    edge._zPaint = function(self) PaintOutline(self, "edgeColor") end
    edge:SetAlpha(0)
    edge:Hide()
    mm.edge = edge

    -- Drives the fades. Its OnUpdate is only set in the overlay look.
    mm.hover = CreateFrame("Frame", nil, Minimap)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("FRIENDLIST_UPDATE")
    ev:RegisterEvent("GUILD_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_GUILD_UPDATE")
    pcall(ev.RegisterEvent, ev, "BN_FRIEND_ACCOUNT_ONLINE")
    pcall(ev.RegisterEvent, ev, "BN_FRIEND_ACCOUNT_OFFLINE")
    pcall(ev.RegisterEvent, ev, "BN_CONNECTED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("UI_SCALE_CHANGED")
    ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if not mm.secure then BuildSecure() end
            if mm.securePending then PlaceSecure() end
            return
        elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
            QueuePlaceSecure()
            return
        end
        if event == "PLAYER_ENTERING_WORLD" then
            if C_FriendList and C_FriendList.ShowFriends then C_FriendList.ShowFriends() end
            if C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            elseif GuildRoster then
                GuildRoster()
            end
        end
        RefreshInfo()
    end)
    mm.events = ev

    for _, x in ipairs({ p, h, f, co, edge, mm.zonePill, mm.clockPill, mm.friendsPill, mm.guildPill }) do x:_zPaint() end
    mm.RefreshInfo = RefreshInfo
    RefreshInfo()

    mm.PlaceSecure = QueuePlaceSecure
    BuildSecure()
    -- The overlays hide and show with the map (out of combat).
    Minimap:HookScript("OnShow", QueuePlaceSecure)
    Minimap:HookScript("OnHide", QueuePlaceSecure)
end

-- A corner icon: Blizzard's frame, square, with a 1px ZacUI ring. (`map`:
-- the Minimap page's sample map; the real one is Minimap.)
local function CornerIcon(frame, icon, point, x, y, name, map)
    if not frame then return end
    map = map or Minimap
    frame:ClearAllPoints()
    frame:SetPoint(point, map, point, x, y)
    frame:SetSize(ICON, ICON)
    frame:SetFrameLevel(map:GetFrameLevel() + 5)
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        SharpenIcon(icon)
    end
    if not frame._zRing then
        -- The dark backing is a texture on Blizzard's own frame, BELOW its
        -- icon layer; a child frame's fill would draw over the icon. The
        -- ring is a child frame (edges only, nothing over the middle).
        local back = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        back._zui_own = true
        back:SetAllPoints()
        back:SetTexture(ns.FLAT)
        local ring = CreateFrame("Frame", name, frame)
        ring:SetAllPoints()
        ring:SetFrameLevel(frame:GetFrameLevel() + 1)
        ns.UI.Border(ring, "ui", "border")
        ring._zPaint = function(self)
            ns.UI.PaintBox(self)
            local c = GetColor("ui", "windowBg")
            back:SetVertexColor(c.r, c.g, c.b, 0.8)
        end
        ring:_zPaint()
        frame._zRing = ring
    end
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.minimap = function()
    if not Minimap then return end

    -- Persistent hide: Blizzard RE-SHOWS several minimap elements after a
    -- plain Hide (hover and cvar paths). Anything hidden in this module
    -- that Blizzard manages goes through here.
    local function HideForever(f)
        if not f or f._zui_hidden then return end
        f._zui_hidden = true
        f:Hide()
        f:HookScript("OnShow", function(fh) fh:Hide() end)
        if f.UnregisterAllEvents then f:UnregisterAllEvents() end
    end
    Minimap:SetMaskTexture("Interface\\ChatFrame\\ChatFrameBackground")
    -- The shape addons ask about before placing their icons (LibDBIcon
    -- buttons, and the HereBeDragons pins Questie, GatherMate and TomTom
    -- draw). Without it they assume a circle and drop every icon that
    -- falls in the square's corners.
    GetMinimapShape = function() return "SQUARE" end

    if MinimapBackdrop then StripTextures(MinimapBackdrop) end
    -- Explicit appends, not a table literal: a nil global in a literal
    -- makes ipairs stop at the hole and silently skips every entry after.
    -- A named function so the Edit Mode reassert can re-run it.
    local function HideMinimapChrome()
        local chrome = {}
        local function AddChrome(r)
            if r and r.Hide then chrome[#chrome + 1] = r end
        end
        AddChrome(MinimapBorder)
        AddChrome((MinimapCluster and MinimapCluster.BorderTop) or MinimapBorderTop)
        AddChrome(MinimapNorthTag)
        AddChrome(MinimapCompassTexture)
        AddChrome(MiniMapTrackingBorder)
        AddChrome(MinimapCluster and MinimapCluster.Tracking
            and MinimapCluster.Tracking.Background)
        AddChrome(MiniMapMailBorder)
        AddChrome(MiniMapBattlefieldBorder)
        for _, region in ipairs(chrome) do region:Hide() end
    end
    HideMinimapChrome()
    HideForever(MiniMapWorldMapButton)
    HideForever(MinimapToggleButton)
    -- Classic Era's GameTimeFrame is the sun / moon dial, half-ring art
    -- that has no place in a square; the clock in the footer tells the
    -- time (and its tooltip carries the server time).
    HideForever(GameTimeFrame)

    -- Zoom buttons: the wheel replaces them.
    HideForever(MinimapZoomIn or (Minimap and Minimap.ZoomIn))
    HideForever(MinimapZoomOut or (Minimap and Minimap.ZoomOut))
    local zoomTimer
    Minimap:EnableMouseWheel(true)
    -- SMOOTH ZOOM (2026-10-31, Zac: "the transition on the minimap is
    -- still laggy and bad its clunky make it smoother"). The minimap has
    -- six fixed zoom levels and SetZoom snaps between them; there is no
    -- fractional zoom. What can be done is to grow or shrink the
    -- minimap's own picture across the step: zooming in, the frame is
    -- scaled up about its centre over 0.15 s inside a clipping frame the
    -- size of the map, then the real zoom is set and the scale dropped
    -- back - the new picture covers the same ground the magnified old one
    -- just did; zooming out, the real zoom is set first with the frame
    -- scaled up to match the old picture, then eased down. The levels'
    -- widths in yards are HereBeDragons' table (466.7 400 333.3 266.7
    -- 200 133.3 outdoors), so each step's ratio is known.
    local YARDS = {
        outdoor = { [0] = 466 + 2/3, 400, 333 + 1/3, 266 + 2/3, 200, 133 + 1/3 },
        indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
    }
    local clip = CreateFrame("Frame", "ZacUIMinimapZoomClip", MinimapCluster or UIParent)
    clip:SetClipsChildren(true)
    clip:Hide()
    local tween = { on = false }
    local function Indoor()
        local z = Minimap:GetZoom()
        local out = tonumber(GetCVar and GetCVar("minimapZoom"))
        local ins = tonumber(GetCVar and GetCVar("minimapInsideZoom"))
        if z and out and ins and out ~= ins then
            if z == ins then return true end
            if z == out then return false end
        end
        return (IsIndoors and IsIndoors()) and true or false
    end
    local function Restore()
        if not tween.on then return end
        tween.on = false
        Minimap:SetScale(tween.base or 1)
        Minimap:SetParent(tween.parent)
        if tween.level then Minimap:SetFrameLevel(tween.level) end
        Minimap:ClearAllPoints()
        for _, pt in ipairs(tween.points) do Minimap:SetPoint(unpack(pt)) end
        clip:Hide()
    end
    -- the minimap into the clip frame, anchored at its centre, so a scale
    -- grows it evenly and the overflow is cut at its own edge
    local function Hold()
        local parent = Minimap:GetParent()
        local pts = {}
        for i = 1, (Minimap:GetNumPoints() or 0) do pts[i] = { Minimap:GetPoint(i) } end
        if #pts == 0 then return false end
        local w, h = Minimap:GetWidth(), Minimap:GetHeight()
        local cx, cy = Minimap:GetCenter()
        if not (w and h and cx and cy and w > 0) then return false end
        local ps = (parent and parent:GetEffectiveScale() or 1)
        local mscale = Minimap:GetEffectiveScale() or 1
        clip:SetParent(parent)
        clip:SetFrameStrata(Minimap:GetFrameStrata())
        clip:SetFrameLevel(math.max(0, (Minimap:GetFrameLevel() or 1) - 1))
        clip:SetSize(w * mscale / ps, h * mscale / ps)
        clip:ClearAllPoints()
        clip:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * mscale / ps, cy * mscale / ps)
        clip:Show()
        tween.parent, tween.points, tween.base = parent, pts, Minimap:GetScale() or 1
        tween.level = Minimap:GetFrameLevel()
        Minimap:SetParent(clip)
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", clip, "CENTER", 0, 0)
        tween.on = true
        return true
    end
    -- ============================================================
    -- FAR ZOOM: THE MINIMAP KEEPS GOING (2026-10-31, Zac: "do the same
    -- kinda thing to the ingame minimap as well make it seemless")
    -- ============================================================
    -- The game's minimap stops at 466 yards across. One more wheel notch
    -- past that and this keeps shrinking the live minimap inside the
    -- clip frame, and paints the world around it from the map art: the
    -- zone's own map, and under that the continent's, each laid in
    -- yards about where you stand (the map's corners in world yards from
    -- C_Map.GetWorldPosFromMapPos, you from UnitPosition), at the same
    -- yards-per-pixel the shrunken minimap has. So the live picture of
    -- the ground sits in the middle of the painted map that continues
    -- it, and scrolling in brings the ground back the same way - one
    -- continuous zoom from the whole continent to the street, as the
    -- world map now does. Not with the rotating minimap (the art would
    -- have to turn with it), not in instances (no world position), and
    -- never in combat (the minimap is reparented).
    -- (2026-11-01, Zac: "i shouldnt be able to scroll my minimap out this far" - at x48 the
    -- live minimap was a postage stamp in a sea of magnified continent art. Three times the
    -- game's widest view is as far as it goes: about 1,400 yards across outdoors, still mostly
    -- inside the zone's own map, which is sharp at that scale.)
    local FAR_STEP, FAR_MAX = 1.25, 3
    local far = { k = 1, to = 1, maps = {}, mapID = nil, check = 0 }
    local art
    local function Rotating() return GetCVar and GetCVar("rotateMinimap") == "1" end
    local function FarOn() return Setting("farZoom") == true and not Rotating() end
    -- the zone you stand in (a micro map's parent until a zone or city)
    local function PlayerMap()
        local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local info = id and C_Map.GetMapInfo(id)
        local guard = 0
        while info and info.mapType and info.mapType > 3 and info.parentMapID and info.parentMapID > 0 and guard < 6 do
            info = C_Map.GetMapInfo(info.parentMapID)
            guard = guard + 1
        end
        return info
    end
    -- a map's corners in world yards and its art layer, once
    local geo = {}
    local function Geo(mapID)
        local g = geo[mapID]
        if g ~= nil then return g or nil end
        g = false
        local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
        local layer = layers and layers[1]
        if layer and layer.layerWidth and layer.layerWidth > 0 and CreateVector2D then
            local ok1, inst, v0 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
            local ok2, _, v1 = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
            if ok1 and ok2 and v0 and v1 and v0.GetXY then
                local x0, y0 = v0:GetXY()
                local x1, y1 = v1:GetXY()
                if x0 ~= x1 and y0 ~= y1 then
                    -- (a map's across runs along the world's y; its down along the world's x)
                    g = { inst = inst, x0 = x0, y0 = y0, x1 = x1, y1 = y1, layer = layer,
                          yardsW = math.abs(y1 - y0), textures = C_Map.GetMapArtLayerTextures(mapID, 1) }
                end
            end
        end
        geo[mapID] = g
        return g or nil
    end
    -- a map's art as tiles in a container frame (cropped at the art's edge)
    local function Build(c, g)
        local layer, tex = g.layer, g.textures or {}
        local tw, th, lw, lh = layer.tileWidth, layer.tileHeight, layer.layerWidth, layer.layerHeight
        local cols, rows = math.ceil(lw / tw), math.ceil(lh / th)
        c.tiles = c.tiles or {}
        local n = 0
        for r = 0, rows - 1 do
            for col = 0, cols - 1 do
                n = n + 1
                local id = tex[n]
                local t = c.tiles[n]
                if not t then t = c:CreateTexture(nil, "ARTWORK") c.tiles[n] = t end
                if id then
                    t:SetTexture(id)
                    local w, h = math.min(tw, lw - col * tw), math.min(th, lh - r * th)
                    t:SetTexCoord(0, w / tw, 0, h / th)
                    t.col, t.row, t.w, t.h, t.tw, t.th = col, r, w, h, tw, th
                    t:Show()
                else
                    t:Hide()
                end
            end
        end
        for i = n + 1, #c.tiles do c.tiles[i]:Hide() end
        c.lw, c.lh, c.n = lw, lh, n
    end
    local function Lay(c, scale)
        c:SetSize(c.lw * scale, c.lh * scale)
        for i = 1, c.n do
            local t = c.tiles[i]
            if t:IsShown() then
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", c, "TOPLEFT", t.col * t.tw * scale, -t.row * t.th * scale)
                t:SetSize(t.w * scale, t.h * scale)
            end
        end
        c.scale = scale
    end
    -- the maps painted round the minimap: the continent under the zone
    local function Containers(zoneInfo)
        local list = {}
        local cont = zoneInfo.parentMapID and C_Map.GetMapInfo(zoneInfo.parentMapID)
        if cont and cont.mapType == 2 then list[#list + 1] = cont.mapID end
        list[#list + 1] = zoneInfo.mapID
        return list
    end
    local function FarLeave()
        far.k, far.to = 1, 1
        if art then art:Hide() end
        if tween.on and not tween.anim then Restore() end
    end
    local function EnsureArt()
        if art then return art end
        art = CreateFrame("Frame", "ZacUIMinimapFarArt", clip)
        art:SetAllPoints(clip)
        art.maps = {}
        art:Hide()
        return art
    end
    local function FarUpdate(el)
        -- ease toward the asked zoom
        local k = far.k
        if math.abs(far.to - k) > 0.002 then
            k = k + (far.to - k) * math.min(1, el * 12)
        else
            k = far.to
        end
        far.k = k
        if k <= 1 then
            FarLeave()
            return
        end
        Minimap:SetScale((tween.base or 1) / k)
        if not art then EnsureArt() end
        -- where you are: UnitPosition gives the world's y (west) then x (north)
        local wy, wx, _, inst = UnitPosition("player")
        if not (wy and wx) then far.to = 1 return end
        far.check = far.check + el
        local info = far.info
        if not info or far.check > 0.5 then
            far.check = 0
            info = PlayerMap()
            far.info = info
            if not info or not info.mapType or info.mapType > 3 then far.to = 1 return end
            if info.mapID ~= far.mapID then
                far.mapID = info.mapID
                for _, c in pairs(art.maps) do c:Hide() end
                far.list = Containers(info)
                for i, mapID in ipairs(far.list) do
                    local g = Geo(mapID)
                    if g and (g.inst == nil or inst == nil or g.inst == inst) then
                        local c = art.maps[mapID]
                        if not c then
                            c = CreateFrame("Frame", nil, art)
                            art.maps[mapID] = c
                            Build(c, g)
                        end
                        c:SetFrameLevel(art:GetFrameLevel() + i)
                        c.g = g
                        c:Show()
                    end
                end
            end
        end
        -- yards per pixel: the minimap's at its widest, over the far zoom
        local w = clip:GetWidth() or 0
        local yards = (Indoor() and YARDS.indoor or YARDS.outdoor)[0]
        if w <= 0 or not yards then return end
        local ppy = (w / yards) / k
        for _, mapID in ipairs(far.list or {}) do
            local c = art.maps[mapID]
            if c and c:IsShown() and c.g then
                local g = c.g
                local scale = ppy * g.yardsW / c.lw
                if math.abs((c.scale or 0) - scale) > scale * 0.002 then Lay(c, scale) end
                -- (a map's across is the world's y, its down the world's x)
                local fx = (wy - g.y0) / (g.y1 - g.y0)
                local fy = (wx - g.x0) / (g.x1 - g.x0)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", clip, "CENTER", -fx * c.lw * scale, fy * c.lh * scale)
            end
        end
        if not art:IsShown() then art:Show() end
        if (Minimap:GetFrameLevel() or 0) <= (art:GetFrameLevel() or 0) then
            Minimap:SetFrameLevel(art:GetFrameLevel() + 8)
        end
    end
    mm.FarLeave = FarLeave

    clip:SetScript("OnUpdate", function(self, el)
        if not tween.on then self:Hide() return end
        if tween.anim then
            tween.t = tween.t + el
            local k = math.min(1, tween.t / 0.15)
            k = 1 - (1 - k) * (1 - k)                 -- ease out
            Minimap:SetScale((tween.base or 1) * (tween.from + (tween.to - tween.from) * k))
            if k >= 1 then
                tween.anim = false
                if tween.after then Minimap:SetZoom(tween.after) end
                if far.to <= 1 and far.k <= 1 then Restore() end
            end
        end
        if far.to > 1 or far.k > 1 then FarUpdate(el) end
    end)
    local function Step(z, nz)
        local t = Indoor() and YARDS.indoor or YARDS.outdoor
        local ratio = (t[z] and t[nz] and t[nz] > 0) and (t[z] / t[nz]) or nil
        if not ratio or not Setting("smoothZoom") or InCombatLockdown() then
            Minimap:SetZoom(nz)
            return
        end
        if tween.on then
            -- a second step before the first has settled: finish it now
            tween.anim = false
            if tween.after then Minimap:SetZoom(tween.after) end
            Restore()
            z = Minimap:GetZoom()
            if z == nz then return end
            ratio = (t[z] / t[nz])
        end
        if not Hold() then Minimap:SetZoom(nz) return end
        tween.t = 0
        tween.anim = true
        if nz > z then
            -- in: magnify the old picture, then switch under it
            tween.from, tween.to, tween.after = 1, ratio, nz
        else
            -- out: switch first, magnified to match, then ease down
            Minimap:SetZoom(nz)
            tween.from, tween.to, tween.after = 1 / ratio, 1, nil
            Minimap:SetScale((tween.base or 1) * tween.from)
        end
    end
    Minimap:SetScript("OnMouseWheel", function(self, delta)
        local z = tween.on and (tween.after or self:GetZoom()) or self:GetZoom()
        if delta < 0 and (z == 0 or far.to > 1) and FarOn() and not InCombatLockdown() then
            -- past the game's widest: on into the painted map
            if far.to >= FAR_MAX then return end
            if not tween.on and not Hold() then return end
            far.to = math.min(FAR_MAX, far.to * FAR_STEP)
            EnsureArt()
            clip:Show()
        elseif delta > 0 and far.to > 1 then
            far.to = far.to / FAR_STEP
            if far.to < 1.001 then far.to = 1 end
        elseif delta > 0 then
            Step(z, math.min(z + 1, self:GetZoomLevels() - 1))
        else
            Step(z, math.max(z - 1, 0))
        end
        -- Optional: drift back to fully zoomed out after a while.
        if zoomTimer then zoomTimer:Cancel() zoomTimer = nil end
        if Setting("autoZoom") and (self:GetZoom() > 0 or far.to > 1) then
            zoomTimer = C_Timer.NewTimer(ZOOM_RESET, function()
                zoomTimer = nil
                if far.to > 1 then far.to = 1 end
                if Minimap:GetZoom() > 0 then Minimap:SetZoom(0) end
            end)
        end
    end)

    BuildPanel()

    -- Zone name: Blizzard's button and string, in the header. Blizzard
    -- keeps colouring it by the zone's PvP status, which is the point.
    local zoneText = ZoneText()
    if zoneText then StyleFS(zoneText, 12) end

    -- Corner icons. Mail top-left, tracking bottom-left (Classic Era's
    -- tracking is the one active tracking spell's icon; right-click still
    -- cancels it), battleground queue bottom-right.
    local mailFrame = MiniMapMailFrame
        or (MinimapCluster and MinimapCluster.IndicatorFrame
            and MinimapCluster.IndicatorFrame.MailFrame)
    local mailIcon = MiniMapMailIcon or (mailFrame and mailFrame.MailIcon)
    if mailFrame then
        -- HD envelope, shipped inside ZacUI's Media: the stock envelope is
        -- 64px vanilla art and reads mushy at this size. Re-asserted on
        -- show in case a mail update repaints the stock texture.
        if mailIcon and mailIcon.SetTexture then
            mailIcon:SetTexture(MEDIA .. "mail")
            mailFrame:HookScript("OnShow", function()
                mailIcon:SetTexture(MEDIA .. "mail")
            end)
        end
        CornerIcon(mailFrame, mailIcon, "TOPLEFT", 3, -3, "ZacUIMinimapMailRing")
    end
    local tracking = MiniMapTracking or MiniMapTrackingFrame
    CornerIcon(tracking, MiniMapTrackingIcon, "BOTTOMLEFT", 3, 3, "ZacUIMinimapTrackingRing")

    -- The battleground crest is round art that Blizzard re-sizes itself
    -- on every queue update, so only the frame is moved; no ring.
    if MiniMapBattlefieldFrame then
        MiniMapBattlefieldFrame:ClearAllPoints()
        MiniMapBattlefieldFrame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 0, 0)
        MiniMapBattlefieldFrame:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    end

    -- The group finder eye (Classic Era 1.15) sits on the ring's top-left
    -- by default, right over the mail corner. Top-right inside the square
    -- instead - unless the button tray has already taken it.
    local eye = _G.LFGMinimapFrame
    if eye and eye:GetParent() == MinimapBackdrop then
        eye:ClearAllPoints()
        eye:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 1, 1)
        eye:SetSize(28, 28)
        if eye.eye then
            eye.eye:ClearAllPoints()
            eye.eye:SetPoint("CENTER")
            eye.eye:SetSize(26, 26)
        end
        local b = _G.LFGMinimapFrameBorder
        if b then b:Hide() end
        eye:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    end

    -- The overlay's pills step aside for whichever corner icon is up.
    mm.cornerIcons = {
        TOPLEFT = mailFrame, BOTTOMLEFT = tracking,
        TOPRIGHT = eye, BOTTOMRIGHT = MiniMapBattlefieldFrame,
    }
    -- the same four by name, for their fine placement (anchors.<icon>);
    -- the eye only when it is the one this file moved
    mm.iconFrames = {
        mail = mailFrame, tracking = tracking, battlefield = MiniMapBattlefieldFrame,
        lfg = (eye and eye:GetParent() == MinimapBackdrop) and eye or nil,
    }
    for point, icon in pairs(mm.cornerIcons) do
        if not (icon and icon.HookScript) then
            mm.cornerIcons[point] = nil
        else
            icon:HookScript("OnShow", function() if Overlay() then PlacePills() end end)
        icon:HookScript("OnHide", function() if Overlay() then PlacePills() end end)
        end
    end

    -- Clock + clock popout + stopwatch live in Blizzard_TimeManager (LoD).
    RegisterLoD("Blizzard_TimeManager", SkinTimeBits)

    -- Targeted X kill: name- or close-art-identified buttons only
    local function IsCloseLike(btn)
        local n = btn.GetName and btn:GetName()
        if n and n:find("Close") then return true end
        if btn.GetNormalTexture then
            local nt = btn:GetNormalTexture()
            local tex = nt and nt.GetTexture and nt:GetTexture()
            if type(tex) == "string"
                and (tex:find("CloseButton") or tex:find("MinimizeButton")) then
                return true
            end
        end
        return false
    end
    local function SweepCloseButtons(root, depth)
        if not root or depth > 4 or not root.GetChildren then return end
        for _, child in ipairs({ root:GetChildren() }) do
            if child.IsObjectType and child:IsObjectType("Button")
                and IsCloseLike(child) then
                RemoveClose(child)
            end
            SweepCloseButtons(child, depth + 1)
        end
    end
    local sweepRoots = {}
    local function AddRoot(h) if h then sweepRoots[#sweepRoots + 1] = h end end
    AddRoot(Minimap)
    AddRoot(MinimapCluster)
    AddRoot(MinimapBackdrop)
    for _, holder in ipairs(sweepRoots) do
        SweepCloseButtons(holder, 1)
    end

    -- EDIT MODE REASSERT: applying a layout re-runs the cluster's own
    -- layout code, which can re-show chrome and reset the square mask.
    -- Re-hide after every Edit Mode exit and once after zoning. Pure
    -- re-hides of insecure art; no EditMode* frame is ever touched.
    local function ReassertMinimap()
        if not Minimap then return end
        Minimap:SetMaskTexture("Interface\\ChatFrame\\ChatFrameBackground")
        HideMinimapChrome()
        Layout()
    end
    -- Owner must be UNIQUE per registration: CallbackRegistry keys
    -- callbacks by (event, owner).
    if EventRegistry and EventRegistry.RegisterCallback then
        pcall(EventRegistry.RegisterCallback, EventRegistry,
            "EditMode.Exit", ReassertMinimap, { zacui = "minimap" })
    end
    mm.events:HookScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(1, ReassertMinimap)
        end
    end)

    Layout()

    -- ============================================================
    -- WHAT THE PLAYER ASKED FOR, LAST
    -- ============================================================
    -- The preference layer shows and hides pieces this module has just
    -- positioned, so it runs after them; it ends by calling Layout again.
    if ns.MinimapPins then ns.MinimapPins.Apply() end
    if ns.MinimapOptions then
        ns.MinimapOptions.Apply()
        -- Once more after the world settles, for the pieces that arrive
        -- late: the clock lives in a load-on-demand addon and the mail
        -- envelope only appears when there is mail.
        C_Timer.After(2, ns.MinimapOptions.Apply)
    end
end

-- ============================================================
-- THE BUTTON TRAY'S LOOK (ZacUIDB.tray, Screen > Minimap > Button tray)
-- ============================================================
-- The tray (UI/Tray) builds, fills and lays itself out; its colours and
-- the way it opens are added here, on top of the frames it publishes:
--   bgColor      the tray's background (palette window colour at 95%)
--   borderColor  its 1px edge (palette)
--   barColor     the bar you hover to open it (accent)
--   openAnim     how it appears (none = at once, as it always has)
-- Each wraps the tray's own repaint, so a palette change keeps a chosen
-- colour; nothing here moves, sizes or reparents a collected button.
local TrayLook = {}

local function TrayDB() return (ZacUIDB and ZacUIDB.tray) or {} end

function TrayLook.PaintTray(frame)
    if not frame then return end
    local db = TrayDB()
    if frame._zFill then
        if type(db.bgColor) == "table" then
            frame._zFill:SetVertexColor(ns.ColorOf(db.bgColor))
        else
            local w = Col("windowBg")
            frame._zFill:SetVertexColor(w.r, w.g, w.b, 0.95)
        end
    end
    if ns.TintBorder then
        if type(db.borderColor) == "table" then
            ns.TintBorder(frame, ns.ColorOf(db.borderColor))
        else
            ns.TintBorder(frame)
        end
    end
end

function TrayLook.PaintBar(bar)
    if not (bar and bar._zFill) then return end
    local db = TrayDB()
    if type(db.barColor) == "table" then
        bar._zFill:SetVertexColor(ns.ColorOf(db.barColor))
    else
        local a = Col("accent")
        bar._zFill:SetVertexColor(a.r, a.g, a.b, 1)
    end
end

function TrayLook.OpenSpec()
    local spec = TrayDB().openAnim
    if type(spec) == "table" and spec.style and spec.style ~= "none" then return spec end
end

-- Once the tray exists (it is built by its own module, which may run
-- after this one or be switched on later): wrap its repaints and play
-- the open animation as it shows. Safe to call any number of times.
function TrayLook.Install()
    local T = ns.Tray
    local tray = T and T.GetTray and T.GetTray()
    local bar = T and T.GetBar and T.GetBar()
    if tray and not tray._zLook then
        tray._zLook = true
        local own = tray._zPaint
        tray._zPaint = function(self)
            if own then own(self) end
            TrayLook.PaintTray(self)
        end
        tray:HookScript("OnShow", function(self)
            local spec = TrayLook.OpenSpec()
            if spec and ns.Motion then ns.Motion.Play(self, spec, "in") end
        end)
    end
    if bar and not bar._zLook then
        bar._zLook = true
        local own = bar._zPaint
        bar._zPaint = function(self)
            if own then own(self) end
            TrayLook.PaintBar(self)
        end
    end
    if tray then tray:_zPaint() end
    if bar then bar:_zPaint() end
end

do
    local tev = CreateFrame("Frame")
    tev:RegisterEvent("PLAYER_ENTERING_WORLD")
    tev:SetScript("OnEvent", function() C_Timer.After(0.5, TrayLook.Install) end)
    if ns.OnSettingsChanged and ns.Coalesce then
        ns.OnSettingsChanged(ns.Coalesce(TrayLook.Install))
    end
end

-- The pieces the Minimap page's preview is built from: the same pill,
-- outline, segment and rule builders and painters the real map uses.
ns.MinimapLook = {
    LOOK = LOOK,
    Look = Look,
    Setting = Setting,
    Overlay = Overlay,
    TextSize = TextSize,
    PillAlpha = PillAlpha,
    Pill = Pill,
    PaintPill = PaintPill,
    StyleFS = StyleFS,
    PlacePillsOn = PlacePillsOn,
    PillDefault = PillDefault,
    CoordsText = CoordsText,
    COORD_DEFAULTS = COORD_DEFAULTS,
    PIECES = { "zone", "clock", "coords", "friends", "guild" },
    PIECE_KEYS = { zone = "zonePos", clock = "clockPos", coords = "coordsPos", friends = "friendsPos", guild = "guildPos" },
    PIECE_LABELS = { map = "The map", zone = "Zone name", clock = "Clock", coords = "Coordinates", friends = "Friends", guild = "Guild" },
    -- the panel look's texts and the corner icons (anchors.<key>)
    PANEL_TEXTS = PANEL_TEXTS,
    PANEL_LABELS = { panelZone = "Zone name", panelClock = "Clock", panelFriends = "Friends",
        panelGuild = "Guild", panelCoords = "Coordinates", map = "The map", header = "The header",
        footer = "The footer" },
    PANEL_HOST_LABELS = { panelZone = "The zone strip", panelClock = "Its footer cell",
        panelFriends = "Its footer cell", panelGuild = "Its footer cell", panelCoords = "The map" },
    PanelDefault = PanelDefault,
    PlacePanelTexts = PlacePanelTexts,
    ICONS = ICON_KEYS,
    ICON_LABELS = { mail = "New mail", tracking = "Tracking", battlefield = "Battleground queue",
        lfg = "Group finder eye", map = "The map" },
    IconDefault = IconDefault,
    PlaceIcons = PlaceIcons,
    CornerIcon = CornerIcon,
    PaintOutline = PaintOutline,
    Segment = Segment,
    Rule = Rule,
    PaintRule = PaintRule,
    ICON = ICON, HEAD_H = HEAD_H, FOOT_H = FOOT_H,
    Tray = TrayLook,
}

-- shared with later ZacUI files
ns.MinimapLayout = Layout
-- the friends and guild tooltips and click, for the chat bar's own counts
ns.MinimapTips = { Friends = FriendsTooltip, Guild = GuildTooltip, OpenSocial = OpenSocial }
