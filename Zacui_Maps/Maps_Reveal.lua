-- Maps_Reveal - draw the parts of a zone you have not walked yet.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT THE CLIENT WILL AND WILL NOT TELL YOU. C_MapExplorationInfo has
-- exactly one function of use here, GetExploredMapTextures, and it
-- returns the tiles you have ALREADY uncovered. There is no call that
-- returns the full set, which is why revealing a map cannot be computed
-- and has to come from the table in Maps_Data.
--
-- HOW A ZONE IS BUILT. Blizzard's exploration pin is laid out one-to-one
-- with the zone's map art in pixels, and exploration is granted in
-- rectangular chunks. Each chunk is a width, a height, an offset from
-- the pin's top-left corner, and one or more texture files - more than
-- one when the chunk is bigger than a single art tile, in which case the
-- files run left to right and then top to bottom. The last column and
-- the last row are usually partial, and their files are padded up to a
-- power of two, so those need cropping with SetTexCoord or the tile
-- draws its own padding as a grey smear.
--
-- THE ONE THAT BITES. Overlay textures come from a pool that Blizzard
-- also uses for the EXPLORED overlays, and a pool hands back whatever
-- state the last user left. Tinting our textures and returning them
-- unreset means the next explored overlay comes out tinted - a bug that
-- appears one map change after the thing that caused it. The pool's
-- reset function is replaced below to put the colour back.

local ADDON_NAME = ...
-- Zacui_Maps is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local MapData = ns.MapData
local Maps = ns.Maps
local Print = ns.Print

local DB, On = Maps.DB, Maps.On

local R = {}

-- Every texture this file has created, so a tint change can repaint
-- without waiting for a map change.
local mine = {}

-- ============================================================
-- POOL HYGIENE
-- ============================================================
local function MakePoolSafe(pin)
    local pool = pin.overlayTexturePool
    if not pool or pool._zResetPatched then return end
    pool._zResetPatched = true

    local original = pool.resetterFunc
    pool.resetterFunc = function(p, texture)
        -- Undo anything WE did before the texture goes back on the shelf.
        if texture.SetVertexColor then texture:SetVertexColor(1, 1, 1, 1) end
        if texture.SetAlpha then texture:SetAlpha(1) end
        if texture.SetDrawLayer then texture:SetDrawLayer("ARTWORK", 0) end
        if original then
            original(p, texture)
        elseif TexturePool_HideAndClearAnchors then
            TexturePool_HideAndClearAnchors(p, texture)
        else
            texture:Hide()
            texture:ClearAllPoints()
        end
    end
end

-- ============================================================
-- TINT
-- ============================================================
-- Unexplored ground drawn at full colour is indistinguishable from
-- ground you have actually been to, which quietly turns the map into a
-- lie. The tint is what keeps "explored" a thing you can still see.
local function TintOf()
    local db = DB()
    if not db.revealTint then return 1, 1, 1, 1 end
    -- Read at paint time, never cached: that is what lets the colour
    -- editor recolour a map that is already open.
    local c = GetColor("map", "reveal")
    return c.r, c.g, c.b, db.tintAlpha or 1
end

function R.Repaint()
    local r, g, b, a = TintOf()
    for texture in pairs(mine) do
        if texture.SetVertexColor then
            texture:SetVertexColor(r, g, b, a)
            texture:SetShown(On("reveal"))
        end
    end
end

-- ============================================================
-- DRAWING
-- ============================================================
-- The next power of two at or above n, starting from 16. Art files are
-- padded to a power of two, so a 189-pixel-wide strip lives inside a
-- 256-wide file and has to be cropped back down.
local function PaddedTo(n)
    local size = 16
    while size < n do size = size * 2 end
    return size
end

local function DrawChunk(pin, layer, rec, r, g, b, a, fullUpdate)
    local width, height, offsetX, offsetY = rec[1], rec[2], rec[3], rec[4]
    local tileW = layer.tileWidth or 256
    local tileH = layer.tileHeight or 256

    local across = math.ceil(width / tileW)
    local down = math.ceil(height / tileH)

    for row = 1, down do
        for col = 1, across do
            -- Row-major: this index formula IS the encoding of the file
            -- list. Getting it wrong does not error, it just puts the
            -- wrong corner of the zone in the wrong place.
            local fileID = rec[4 + ((row - 1) * across) + col]
            if fileID then
                local texture = pin.overlayTexturePool:Acquire()

                -- Interior tiles are full size; the last column and row
                -- are whatever is left over, and a remainder of zero
                -- means it came out exactly even.
                local pxW = (col < across) and tileW or (width % tileW)
                local pxH = (row < down) and tileH or (height % tileH)
                if pxW == 0 then pxW = tileW end
                if pxH == 0 then pxH = tileH end

                texture:SetSize(pxW, pxH)
                texture:SetTexCoord(0, pxW / PaddedTo(pxW), 0, pxH / PaddedTo(pxH))
                texture:SetPoint("TOPLEFT", pin, "TOPLEFT",
                    offsetX + tileW * (col - 1),
                    -(offsetY + tileH * (row - 1)))
                texture:SetTexture(fileID, nil, nil, "TRILINEAR")
                -- Sublevel -1 puts unexplored art UNDER the explored
                -- overlays, so a tile you have half-uncovered still
                -- shows the real thing on top.
                texture:SetDrawLayer("ARTWORK", -1)
                texture:SetVertexColor(r, g, b, a)
                texture:Show()

                -- Joining Blizzard's load group means the whole map
                -- appears at once instead of tiles popping in one by one.
                if fullUpdate and pin.textureLoadGroup then
                    pin.textureLoadGroup:AddTexture(texture)
                end
                mine[texture] = true
            end
        end
    end
end

local function RefreshOverlays(pin, fullUpdate)
    -- Our textures went back to the pool when Blizzard released it at
    -- the top of its own refresh, so the record of them is stale.
    wipe(mine)
    if not On("reveal") then return end

    local map = pin.GetMap and pin:GetMap()
    local mapID = map and map.GetMapID and map:GetMapID()
    if not mapID then return end
    if not C_Map or not C_Map.GetMapArtID then return end

    -- Keyed by ART id, not map id: several maps can share one set of art.
    local zone = MapData.reveal[C_Map.GetMapArtID(mapID)]
    if not zone then return end

    local container = map.GetCanvasContainer and map:GetCanvasContainer()
    local layerIndex = container and container.GetCurrentLayerIndex
        and container:GetCurrentLayerIndex()
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[layerIndex or 1]
    if not layer then return end

    -- Anything already explored is drawn by Blizzard, and drawing it
    -- again on top would undo the tint that makes unexplored readable.
    -- The key format here is not arbitrary - it is byte-for-byte what
    -- the explored-texture records produce, which is the whole reason
    -- the data is stored as these four numbers.
    local explored = {}
    if C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures then
        local list = C_MapExplorationInfo.GetExploredMapTextures(mapID)
        if list then
            for _, info in ipairs(list) do
                explored[info.textureWidth .. ":" .. info.textureHeight
                    .. ":" .. info.offsetX .. ":" .. info.offsetY] = true
            end
        end
    end

    MakePoolSafe(pin)
    local r, g, b, a = TintOf()

    for _, rec in ipairs(zone) do
        local key = rec[1] .. ":" .. rec[2] .. ":" .. rec[3] .. ":" .. rec[4]
        if not explored[key] then
            local ok, err = pcall(DrawChunk, pin, layer, rec, r, g, b, a, fullUpdate)
            if not ok then
                Print("map reveal failed on " .. key .. ": " .. tostring(err))
                return
            end
        end
    end
end

-- ============================================================
-- APPLY
-- ============================================================
function R.Apply()
    Maps.ForEachPin("MapExplorationPinTemplate", function(pin)
        MakePoolSafe(pin)
        -- Post-hook, so Blizzard draws the explored overlays first and
        -- releases the pool first. Ours are appended to what is already
        -- there rather than replacing it.
        hooksecurefunc(pin, "RefreshOverlays", RefreshOverlays)
        if pin.RefreshOverlays then pcall(pin.RefreshOverlays, pin, true) end
    end)
end

R.RefreshOverlays = RefreshOverlays
-- the tint, for the settings preview's unexplored corner
R.TintOf = TintOf
R.mine = mine

-- shared with later ZacUI files
ns.MapsReveal = R
