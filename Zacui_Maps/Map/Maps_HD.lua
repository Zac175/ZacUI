-- Maps_HD - the zone map drawn from the game's minimap tiles (2026-10-31,
-- Zac: "can we get hd version of the map ... currently the map just looks
-- like shit").
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT THE CLIENT HAS. The world map's art is one picture per zone, about
-- a thousand pixels across for a zone six thousand yards wide - a sixth
-- of a pixel to the yard, which is why it goes to mush the moment it is
-- zoomed. An addon cannot replace that art: it is loaded by file id from
-- the game's own archive, and nothing in Interface\AddOns is looked at
-- for it. What the client ALSO has is the minimap: one 256-pixel tile for
-- every 533.33-yard square of the world, half a pixel to the yard - three
-- times the detail - and those tiles can be shown anywhere a texture can,
-- by their file ids (Maps_HDTiles.lua, out of the community list of the
-- game's files). Carbonite drew its world map this way for years.
--
-- HOW A TILE FINDS ITS PLACE. The world is a 64 x 64 grid of tiles per
-- continent, column c and row r: a tile's west edge is at world Y
-- (32 - c) * 533.33 and its north edge at world X (32 - r) * 533.33 (the
-- game's X runs north, its Y west, both shrinking as you go south and
-- east). GetWorldPosFromMapPos gives the world coordinates of a zone
-- map's two corners, and with those every tile is a plain proportion of
-- the canvas - cropped to the map's edge with texture coordinates where
-- it overhangs. Zone-level maps only: a continent is two thousand tiles,
-- and its painted map is the better picture of it anyway.
--
-- WHERE IT SITS. One frame the size of the canvas, a level above the
-- exploration overlay and below every pin: your arrow, the group, the
-- flight paths and ZacUI's own markers all stay on top; unexplored fog
-- (and ZacUI's tinted reveal of it) is under the tiles, so the whole
-- zone shows. Textures come from a pool and are laid out again on every
-- map change - up to a few hundred for the biggest zones, eleven hundred
-- for a continent - from placements worked out once per map and kept,
-- so a map visited before costs no placement calls at all. Battleground maps (Alterac, Warsong, Arathi) have
-- tiles too and get them when their map is open as a zone.

local ADDON_NAME = ...
-- Zacui_Maps is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local Maps = ns.Maps
local GetColor = ns.GetColor
local DB, On = Maps.DB, Maps.On

local HD = {}
ns.MapsHD = HD
Maps.HD = HD

local TILE = 533.33333
local ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

-- ============================================================
-- THE TILE TABLE, parsed on first use per continent
-- ============================================================
local parsed = {}
local function Tiles(inst)
    local t = parsed[inst]
    if t ~= nil then return t or nil end
    local src = ns.MapHDTiles and ns.MapHDTiles[inst]
    if not src then parsed[inst] = false return nil end
    t = {}
    local n = 0
    for c, s in pairs(src) do
        local col = {}
        for r, id in s:gmatch("(%d+):(%d+)") do
            col[tonumber(r)] = tonumber(id)
            n = n + 1
        end
        t[c] = col
    end
    t.n = n
    parsed[inst] = t
    return t
end
HD.Tiles = Tiles

-- ============================================================
-- THE LAYER
-- ============================================================
local layer
local live, spare = {}, {}        -- tile key -> texture in use; textures off duty
local wanted = {}
local bad = {}                    -- file ids this client does not have
HD.drawn = 0
HD.missing = 0
-- the most tiles laid at once: a whole continent is 1,100-1,250 (Zac,
-- 2026-10-31 19:45, on the painted Eastern Kingdoms: "why is this still
-- the old one") - so a continent zoomed right out is drawn from tiles
-- too; the cap only guards against a map far bigger than any here
local MAX_TILES = 2000
local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

local function Texture()
    local t = table.remove(spare)
    if not t then
        t = layer:CreateTexture(nil, "ARTWORK")
        t._zui_own = true
    end
    return t
end

local function HideAll()
    for key, t in pairs(live) do
        t:Hide()
        spare[#spare + 1] = t
        live[key] = nil
    end
    HD.drawn = 0
end

-- the scaled, panned frame the map art lives in: what zooms is what the
-- tiles must be children of
local function Canvas(map)
    local sc = map.ScrollContainer
    if type(sc) == "table" and type(sc.Child) == "table" then return sc.Child end
    return map.GetCanvas and map:GetCanvas()
end
HD.Canvas = Canvas

-- a level just above the exploration overlay (unexplored fog), under
-- every pin
local function PlaceLevel(map, canvas)
    local lvl
    if map.EnumeratePinsByTemplate then
        for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
            lvl = pin:GetFrameLevel() + 1
            break
        end
    end
    layer:SetFrameLevel(lvl or (canvas:GetFrameLevel() + 2))
    HD.levelFrom = lvl and "exploration pin" or "canvas"
end

-- /zui maps: what the layer did, in numbers that can be checked
function HD.Report(Print)
    local map = _G.WorldMapFrame
    local canvas = map and Canvas(map)
    local sc = map and type(map.ScrollContainer) == "table" and map.ScrollContainer
    Print(string.format("sharper map: %d tile(s) drawn%s%s", HD.drawn or 0,
        (HD.missing or 0) > 0 and (", " .. HD.missing .. " skipped") or "",
        HD.why and (" - " .. HD.why) or ""))
    if not canvas then Print("  no canvas") return end
    Print(string.format("  canvas %s %.0fx%.0f scale %.2f (level %d); layer %s %.0fx%.0f, parent is canvas: %s, level %d from %s",
        canvas:GetName() or "?", canvas:GetWidth() or 0, canvas:GetHeight() or 0, canvas:GetScale() or 0, canvas:GetFrameLevel() or 0,
        layer and (layer:IsShown() and "shown" or "hidden") or "none", layer and layer:GetWidth() or 0, layer and layer:GetHeight() or 0,
        tostring(layer and layer:GetParent() == canvas), layer and layer:GetFrameLevel() or 0, tostring(HD.levelFrom)))
    if sc and type(sc.Child) == "table" then
        Print(string.format("  scroll container %.0fx%.0f; GetCanvas is the Child: %s",
            sc:GetWidth() or 0, sc:GetHeight() or 0, tostring(map.GetCanvas and map:GetCanvas() == sc.Child)))
    end
    if sc then
        local lv = {}
        for _, z in ipairs(type(sc.zoomLevels) == "table" and sc.zoomLevels or {}) do lv[#lv + 1] = string.format("%.2f", z.scale or 0) end
        Print(string.format("  zoom: scale %.2f, levels [%s], easing to %s, last step %s, target %s",
            sc.GetCanvasScale and sc:GetCanvasScale() or 0, table.concat(lv, " "), tostring(sc._zEaseTo), tostring(sc._zLastTarget), tostring(sc.targetScale)))
    end
    local L = HD.last
    if L and L.inst then
        Print(string.format("  map %s on continent %s: world X %.0f..%.0f, Y %.0f..%.0f (%.0f x %.0f yards = %.1f x %.1f tiles)",
            tostring(L.mapID), tostring(L.inst), L.xs, L.xn, L.ye, L.yw, L.yw - L.ye, L.xn - L.xs, (L.yw - L.ye) / TILE, (L.xn - L.xs) / TILE))
    end
    if L and L.first then
        local f = L.first
        Print(string.format("  first tile col %d row %d (id %d) at %.0f,%.0f size %.0fx%.0f", f.c, f.r, f.id, f.x, f.y, f.w, f.h))
    end
    local art = map and map.GetMapID and C_Map and C_Map.GetMapArtID and C_Map.GetMapArtID(map:GetMapID())
    local w, h = art and C_Map.GetMapArtLayers and (function() local layers = C_Map.GetMapArtLayers(map:GetMapID()) local l = layers and layers[1] return l and l.layerWidth, l and l.layerHeight end)()
    if w then Print(string.format("  map art %.0fx%.0f", w, h)) end
end

-- the zone's corners in world yards: north/west (top-left) and
-- south/east (bottom-right), and the continent they are on
local function Corners(mapID)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok1, inst, nw = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
    local ok2, inst2, se = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 1))
    if not (ok1 and ok2 and nw and se and nw.GetXY and inst == inst2) then return nil end
    local xn, yw = nw:GetXY()
    local xs, ye = se:GetXY()
    if not (xn and yw and xs and ye) or xn <= xs or yw <= ye then return nil end
    return inst, xn, yw, xs, ye
end
HD.Corners = Corners

-- Where a world point sits on a map, as fractions of it, from the game
-- itself (GetMapPosFromWorldPos with the map named): no assumption about
-- which way the map is drawn or how it is cut. Falls back to a plain
-- proportion of the map's corners where the client lacks the call.
local probe, vec
local function MapPos(inst, mapID, wx, wy, xn, yw, W, H)
    if probe == nil then
        vec = CreateVector2D and CreateVector2D(0, 0)
        probe = (C_Map and C_Map.GetMapPosFromWorldPos and vec and vec.SetXY) and true or false
    end
    if probe then
        vec:SetXY(wx, wy)
        local ok, onMap, pos = pcall(C_Map.GetMapPosFromWorldPos, inst, vec, mapID)
        -- the answer is good only when it is FOR the map asked: for a
        -- map it cannot place on (the Azeroth picture) the game answers
        -- with the zone under the point instead, and its fractions
        -- would put a zone's tiles across the whole picture (2026-10-31,
        -- Dun Morogh over all of Azeroth)
        if ok and pos and pos.GetXY and (onMap == nil or onMap == mapID) then
            local x, y = pos:GetXY()
            if x and y then return x, y end
        end
    end
    if not W then return nil end
    return (yw - wy) / W, (xn - wx) / H
end
HD.MapPos = MapPos

local function Hidden(why)
    HideAll()
    if layer then layer:Hide() end
    HD.why = why
    return 0
end

-- Where the land is on a continent or world map: the rectangles of its
-- child maps (zones on a continent, continents on the world). A tile
-- outside every one of them is open sea, or one of the flat filler tiles
-- the game keeps north of Kalimdor, and is not drawn (2026-10-31, Zac:
-- "what are the random texture squares").
local function LandRects(mapID)
    local out = {}
    if not (C_Map and C_Map.GetMapChildrenInfo and C_Map.GetMapRectOnMap) then return out end
    for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID) or {}) do
        if child.mapType and child.mapType >= CONTINENT then
            local l, r, t, bm = C_Map.GetMapRectOnMap(child.mapID, mapID)
            if l and r and t and bm and r > l and bm > t then
                out[#out + 1] = { l, r, t, bm }
            end
        end
    end
    return out
end
local function OnLand(rects, nx1, nx2, ny1, ny2)
    if #rects == 0 then return true end
    for i = 1, #rects do
        local q = rects[i]
        if nx2 > q[1] and nx1 < q[2] and ny2 > q[3] and ny1 < q[4] then return true end
    end
    return false
end

-- Where each tile of one continent sits on a map, worked out once per
-- map and kept (geo[mapID]): the game's placement calls are the slow
-- part, and a map's tiles never move. Appends to `items`.
local geo = {}
function HD.Forget(mapID) if mapID then geo[mapID] = nil else wipe(geo) end end
local function PlaceTiles(mapID, inst, T, rects, corners, items)
    local xn, yw, xs, ye, W, H
    if corners then xn, yw, xs, ye = corners[1], corners[2], corners[3], corners[4] W, H = yw - ye, xn - xs end
    -- the columns and rows to look at: around the map's corners when they
    -- are known, the whole grid when not
    local c0, c1, r0, r1 = 0, 63, 0, 63
    if W then
        c0, c1 = math.floor(32 - yw / TILE) - 2, math.floor(32 - ye / TILE) + 2
        r0, r1 = math.floor(32 - xn / TILE) - 2, math.floor(32 - xs / TILE) + 2
    end
    for c = c0, c1 do
        local col = T[c]
        if col then
            local yl = (32 - c) * TILE          -- west edge
            for r = r0, r1 do
                local id = col[r]
                if id then
                    local xt = (32 - r) * TILE  -- north edge
                    -- the tile's two corners, placed by the game
                    local ax, ay = MapPos(inst, mapID, xt, yl, xn, yw, W, H)
                    local bx, by = MapPos(inst, mapID, xt - TILE, yl - TILE, xn, yw, W, H)
                    if ax and bx then
                        local nx1, nx2 = math.min(ax, bx), math.max(ax, bx)
                        local ny1, ny2 = math.min(ay, by), math.max(ay, by)
                        -- on the map at all (a hair's overlap from rounding is
                        -- none: an edge on a tile edge must not pull in the next),
                        -- and on land
                        if nx2 > 1e-4 and nx1 < 1 - 1e-4 and ny2 > 1e-4 and ny1 < 1 - 1e-4
                            and nx2 - nx1 > 1e-6 and ny2 - ny1 > 1e-6
                            and OnLand(rects, nx1, nx2, ny1, ny2) then
                            items[#items + 1] = { inst = inst, c = c, r = r, id = id,
                                nx1 = nx1, nx2 = nx2, ny1 = ny1, ny2 = ny2 }
                        end
                    end
                end
            end
        end
    end
end

-- puts the placed tiles on the layer; returns drawn, missing
local function LayTiles(items, cw, ch, alpha)
    local L = HD.last
    local n, missing = 0, 0
    for i = 1, #items do
        local it = items[i]
        local id = it.id
        if not bad[id] then
            local key = it.inst * 10000 + it.c * 100 + it.r
            wanted[key] = true
            local t = live[key]
            if not t then t = Texture() live[key] = t end
            local nx1, nx2, ny1, ny2 = it.nx1, it.nx2, it.ny1, it.ny2
            local cx1, cx2 = math.max(nx1, 0), math.min(nx2, 1)
            local cy1, cy2 = math.max(ny1, 0), math.min(ny2, 1)
            if not L.first then L.first = { c = it.c, r = it.r, id = id, x = cx1 * cw, y = cy1 * ch, w = (cx2 - cx1) * cw, h = (cy2 - cy1) * ch } end
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", layer, "TOPLEFT", cx1 * cw, -cy1 * ch)
            t:SetSize(math.max(1, (cx2 - cx1) * cw), math.max(1, (cy2 - cy1) * ch))
            t:SetTexCoord((cx1 - nx1) / (nx2 - nx1), (cx2 - nx1) / (nx2 - nx1),
                (cy1 - ny1) / (ny2 - ny1), (cy2 - ny1) / (ny2 - ny1))
            t:SetAlpha(alpha)
            local ok = true
            if t._zId ~= id then
                -- smoothed between its pixels, and through its mip levels
                -- when shrunk to a continent's scale
                ok = t:SetTexture(id, "CLAMP", "CLAMP", "TRILINEAR")
                t._zId = id
            end
            if ok == false then
                bad[id] = true
                t._zId = nil
                t:Hide()
                spare[#spare + 1] = t
                live[key] = nil
                wanted[key] = nil
                missing = missing + 1
            else
                n = n + 1
                t:Show()
            end
        end
    end
    return n, missing
end

-- Lays the tiles for the map that is open. Returns how many it drew.
function HD.Refresh(map)
    map = map or _G.WorldMapFrame
    if not map then return 0 end
    local canvas = Canvas(map)
    if not canvas then return 0 end
    HD.last = { mapID = map.GetMapID and map:GetMapID() }
    if not layer then
        layer = CreateFrame("Frame", "ZacUIMapHD", canvas)
        layer:SetAllPoints(canvas)
        layer:EnableMouse(false)
        -- the sea: a solid colour under the tiles, so no painting shows
        -- through between or around them (2026-10-31, Zac: "why does it
        -- ever go to the blizzard maps")
        layer.sea = layer:CreateTexture(nil, "BACKGROUND")
        layer.sea._zui_own = true
        layer.sea:SetAllPoints(layer)
        layer.sea:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8x8")
    elseif layer:GetParent() ~= canvas then
        layer:SetParent(canvas)
        layer:SetAllPoints(canvas)
    end
    HD.why = nil
    if not On("hdMap") then return Hidden("off") end
    local mapID = map.GetMapID and map:GetMapID()
    local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    if not (info and info.mapType) then return Hidden("no map") end
    local zone = info.mapType >= ZONE
    local continent = info.mapType == CONTINENT
    local world = info.mapType < CONTINENT          -- the Azeroth map: both continents on one picture
    if not zone and DB().hdContinents == false then return Hidden("continents switched off") end
    local cw, ch = canvas:GetWidth() or 0, canvas:GetHeight() or 0
    if cw <= 0 or ch <= 0 then return Hidden("canvas not laid out") end
    local corners
    local inst, xn, yw, xs, ye = Corners(mapID)
    if inst then
        corners = { xn, yw, xs, ye }
        local L = HD.last
        L.inst, L.xn, L.yw, L.xs, L.ye, L.cw, L.ch = inst, xn, yw, xs, ye, cw, ch
    elseif not world then
        return Hidden("no world position for this map")
    end
    PlaceLevel(map, canvas)
    local alpha = tonumber(DB().hdAlpha) or 1
    -- every tile of this map, placed once and kept
    local items = geo[mapID]
    if not items then
        items = {}
        local rects = zone and {} or LandRects(mapID)
        if world then
            -- the Azeroth picture: each continent's tiles placed on the
            -- CONTINENT (where the game can place them), then moved into
            -- the continent's rectangle on the picture
            if C_Map.GetMapChildrenInfo and C_Map.GetMapRectOnMap then
                for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID) or {}) do
                    if child.mapType == CONTINENT then
                        local ci, cxn, cyw, cxs, cye = Corners(child.mapID)
                        local T = ci and Tiles(ci)
                        local l, r, t, b = C_Map.GetMapRectOnMap(child.mapID, mapID)
                        if T and l and r and t and b and r > l and b > t then
                            local sub = {}
                            PlaceTiles(child.mapID, ci, T, LandRects(child.mapID), { cxn, cyw, cxs, cye }, sub)
                            for _, it in ipairs(sub) do
                                it.nx1, it.nx2 = l + it.nx1 * (r - l), l + it.nx2 * (r - l)
                                it.ny1, it.ny2 = t + it.ny1 * (b - t), t + it.ny2 * (b - t)
                                items[#items + 1] = it
                            end
                        end
                    end
                end
            end
        else
            local T = Tiles(inst)
            if not T then return Hidden("no tiles for continent " .. tostring(inst)) end
            PlaceTiles(mapID, inst, T, rects, corners, items)
        end
        geo[mapID] = items
    end
    if #items > MAX_TILES then return Hidden("too many tiles (" .. #items .. ")") end
    wipe(wanted)
    local n, missing = LayTiles(items, cw, ch, alpha)
    -- tiles that left the view
    for key, t in pairs(live) do
        if not wanted[key] then
            t:Hide()
            spare[#spare + 1] = t
            live[key] = nil
        end
    end
    HD.drawn, HD.missing = n, missing
    if layer.sea then
        local c = GetColor and GetColor("map", "sea") or { r = 0.05, g = 0.1, b = 0.18 }
        layer.sea:SetVertexColor(c.r, c.g, c.b, 1)
        layer.sea:SetShown(DB().hdSolid ~= false)
    end
    layer:SetShown(n > 0)
    if n == 0 and not HD.why then HD.why = "no tiles under this map" end
    return n
end

-- ============================================================
-- THE DATA PROVIDER (the canvas calls it on every map change)
-- ============================================================
local Provider
local function BuildProvider()
    if not MapCanvasDataProviderMixin then return nil end
    local p = CreateFromMixins(MapCanvasDataProviderMixin)
    function p:RemoveAllData()
        if layer then HideAll() layer:Hide() end
    end
    function p:RefreshAllData()
        HD.Refresh(self:GetMap())
    end
    -- the exploration overlay is a pin acquired AFTER the providers run
    -- their refresh on a map change; the level is taken again a moment
    -- later so the tiles stay above it
    function p:OnMapChanged()
        C_Timer.After(0, function()
            local map = self:GetMap()
            if map and layer and layer:IsShown() then PlaceLevel(map, map:GetCanvas()) end
            -- (the header's name, which lagged a map behind after a wheel step)
            if ns.MapsSkin and ns.MapsSkin.UpdateTitle then ns.MapsSkin.UpdateTitle() end
        end)
    end
    return p
end

local installed = false
function HD.Apply()
    local map = _G.WorldMapFrame
    if not map then return end
    if not installed and map.AddDataProvider then
        Provider = BuildProvider()
        if Provider then
            installed = true
            map:AddDataProvider(Provider)
        end
    end
    if map:IsShown() then HD.Refresh(map) end
end
