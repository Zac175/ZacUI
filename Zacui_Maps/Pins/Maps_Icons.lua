-- Maps_Icons - the map pins: flight points, dungeon entrances, spirit
-- healers and zone crossings, plus the player arrow and group icons.
-- Part of ZacUI; load order is set by the TOC.
--
-- PINS GO THROUGH THE CANVAS, NOT ON TOP OF IT. The tempting shortcut is
-- a frame per pin parented to the map and moved by hand, and it works
-- until you zoom - at which point every icon is in the wrong place,
-- because the canvas has scaled underneath frames that know nothing
-- about it. Registering a data provider means the canvas owns the
-- positioning, the scaling and the pooling, and pins simply are where
-- they should be.
--
-- ART. The addon this replaces ships its own texture file for boats,
-- zeppelins and the Ironforge tram, because Blizzard has no atlas for
-- them on this client. ZacUI does not borrow that file. Those pins use
-- Blizzard's own coloured markers instead - visibly not flight points,
-- which is the distinction that actually matters - and the tooltip says
-- what each one is. Every atlas named below is resolved through
-- Maps.Atlas, which checks the client actually has it before using it,
-- because an atlas that does not resolve draws nothing at all while
-- still taking your clicks.

local ADDON_NAME = ...
-- Zacui_Maps is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Col = ns.Col
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local MapData = ns.MapData
local Maps = ns.Maps
local Print = ns.Print

local DB, On = Maps.DB, Maps.On

local I = {}

-- Record layout, named once here so no other line in this file is
-- indexing a pin by a bare number.
local KIND, PX, PY, NAME = 1, 2, 3, 4

-- ============================================================
-- WHAT EACH KIND LOOKS LIKE, AND WHO ASKS FOR IT
-- ============================================================
-- The atlas used to be repeated on all 313 pin records even though it is
-- a pure function of the kind. It lives here once instead.
-- ============================================================
-- BLIZZARD'S OWN ICONS, MADE TO READ
-- ============================================================
-- A set of hand-drawn glyphs lived here for exactly one round. They were
-- consistent and they were wrong: a bespoke icon set has to be as good
-- as the art it replaces before it is worth anything, and mine was not.
-- The client's own taxi node, dungeon and arrow art is drawn for these
-- exact things and is already familiar.
--
-- The complaint the glyphs were meant to answer was never "wrong
-- pictures" - it was that they do not STAND OUT on busy map terrain. So
-- the art is Blizzard's and the emphasis is ours: each pin draws its own
-- icon a second time behind itself, in black and slightly larger, which
-- gives a dark halo in the shape of the icon. It is the outline effect a
-- square plate was reaching for two rounds ago, without the box.
--
-- The shadow takes the pin's rotation too. A crossing arrow that points
-- north with a shadow pointing north-east looks like a printing error.
local KINDS = {
    FlightA  = { atlas = { "TaxiNode_Alliance" },  size = 20, group = "flight", faction = "Alliance" },
    FlightH  = { atlas = { "TaxiNode_Horde" },     size = 20, group = "flight", faction = "Horde" },
    FlightN  = { atlas = { "TaxiNode_Neutral" },   size = 20, group = "flight" },
    TravelA  = { atlas = { "Vehicle-TempleofKotmogu-CyanBall" },   size = 20, group = "flight", faction = "Alliance" },
    TravelH  = { atlas = { "Vehicle-TempleofKotmogu-OrangeBall",
                           "Vehicle-TempleofKotmogu-PurpleBall" }, size = 20, group = "flight", faction = "Horde" },
    TravelN  = { atlas = { "Vehicle-TempleofKotmogu-PurpleBall",
                           "Vehicle-TempleofKotmogu-CyanBall" },   size = 20, group = "flight" },
    Dungeon  = { atlas = { "Dungeon" },            size = 20, group = "dungeons" },
    Raid     = { atlas = { "Raid", "Dungeon" },    size = 26, group = "dungeons" },
    Dunraid  = { atlas = { "Raid", "Dungeon" },    size = 26, group = "dungeons" },
    Spirit   = { atlas = { "Vehicle-TempleofKotmogu-GreenBall" },  size = 18, group = "spirit" },
    Arrow    = { atlas = { "Garr_LevelUpgradeArrow" }, size = 18, group = "crossing" },
}

-- Which setting decides whether a group is drawn. Faction is folded in
-- here rather than at the call site so there is one place to read.
local function Wanted(kind, playerFaction)
    local info = KINDS[kind]
    if not info then return false end
    local db = DB()
    -- the world-map part (OpenMap inside ZacUI) places flight masters and
    -- instance entrances itself: ZacUI's copies would sit on top of them
    if (info.group == "flight" or info.group == "dungeons") and Maps.OpenMapLoaded and Maps.OpenMapLoaded() then
        return false
    end

    if info.group == "flight" then
        if not info.faction then
            -- Neutral travel shows if EITHER travel setting is on: a
            -- neutral flight point is useful to both sides, and hiding
            -- it because you turned off "opposing" would be wrong.
            return db.flightPoints or db.flightOpposing
        end
        if info.faction == playerFaction then return db.flightPoints end
        return db.flightOpposing
    end
    if info.group == "dungeons" then return db.dungeons end
    if info.group == "spirit" then return db.spiritHealers end
    if info.group == "crossing" then return db.crossings end
    return false
end

-- ============================================================
-- A ZONE WITH NO DATA HERE, OFF CLASSIC ERA
-- ============================================================
-- The pin data above is Classic Era's Azeroth. On TBC (Outland, the new
-- elf zones) and on Forever (its own lands) a zone it does not cover gets
-- its flight masters from the game itself: C_TaxiMap.GetTaxiNodesForMap
-- (warcraft.wiki.gg lists it for TBC 2.5.6 and Forever 1.60.1), every
-- node on the zone with its side. Zones only (a continent keeps what it
-- shows). Built once per zone and kept; an empty answer is asked again.
-- Classic Era reads the data and nothing else, as before.
local runtimeOn = ns.Flavor and ns.Flavor() ~= "era"
local FLIGHT_KIND = { [0] = "FlightN", [1] = "FlightH", [2] = "FlightA" }
local runtimePins = {}
local function GamePins(mapID)
    local got = runtimePins[mapID]
    if got then return got end
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap and C_Map and C_Map.GetMapInfo) then return nil end
    local info = C_Map.GetMapInfo(mapID)
    local ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
    if not (info and info.mapType == ZONE) then return nil end
    local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
    if not ok or type(nodes) ~= "table" or #nodes == 0 then return nil end
    local out = {}
    for _, n in ipairs(nodes) do
        local pos = n.position
        local x, y
        if type(pos) == "table" then
            if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
        end
        local kind = FLIGHT_KIND[n.faction or 0] or "FlightN"
        if type(x) == "number" and type(y) == "number" and type(n.name) == "string" then
            out[#out + 1] = { kind, x * 100, y * 100, n.name }
        end
    end
    if #out == 0 then return nil end
    runtimePins[mapID] = out
    return out
end
-- the pins of a zone: the data, or (off Classic Era, where there is none)
-- the game's own flight masters
function Maps.PinsFor(mapID)
    local p = MapData.pins[mapID]
    if p or not runtimeOn or not mapID then return p end
    return GamePins(mapID)
end

-- ============================================================
-- HOW BIG, AND THE HALO (shared with the settings preview)
-- ============================================================
-- The setting that scales each group on its own (2026-11-01): 100% for
-- all four is the map as it always was.
local GROUP_SCALE = {
    flight = "pinScaleFlight", dungeons = "pinScaleDungeons",
    spirit = "pinScaleSpirit", crossing = "pinScaleCrossing",
}

-- SCALED, NOT REPLACED. Each kind has its own size for a reason - a
-- spirit healer is deliberately smaller than a dungeon portal - so the
-- setting moves them all together rather than flattening them to one
-- number and losing the distinction. Its group's own scale goes on top.
function I.PinSize(base, kind)
    local db = DB()
    local want = tonumber(db.pinSize) or 14
    local info = kind and KINDS[kind]
    local key = info and GROUP_SCALE[info.group]
    local k = key and tonumber(db[key]) or 1
    return math.max(8, math.floor((base or 20) * (want / 14) * k + 0.5))
end

-- The icon on a pin frame (pin.Texture), its halo (made once and kept,
-- as pool frames come back), its rotation and its size. The real canvas
-- pin and the preview's sample both come through here.
function I.Dress(pin, atlas, rotation, base, kind)
    rotation = rotation or 0
    local db = DB()
    if pin.CreateTexture then
        if not pin.zacHalo then
            pin.zacHalo = pin:CreateTexture(nil, "BACKGROUND")
            pin.zacHalo._zui_own = true
        end
        local halo = pin.zacHalo
        if atlas and halo.SetAtlas and db.pinHalo ~= false then
            halo:SetAtlas(atlas)
            -- black at 70% unless a colour is picked on the Maps page
            halo:SetVertexColor(Maps.Color("pinHaloColor", { 0, 0, 0, 0.7 }))
            -- Rotated with the icon. A north-pointing arrow with a
            -- north-east shadow reads as a printing error.
            if halo.SetRotation then halo:SetRotation(rotation) end
            halo:ClearAllPoints()
            halo:SetPoint("CENTER")
            halo:Show()
        else
            halo:Hide()
        end
    end

    if type(pin.Texture) == "table" then
        pin.Texture:ClearAllPoints()
        pin.Texture:SetAllPoints(pin)
    end

    if pin.SetSize then
        local size = I.PinSize(base, kind)
        pin:SetSize(size, size)
        if pin.zacHalo and pin.zacHalo:IsShown() then
            local h = tonumber(db.pinHaloSize) or 1.34
            pin.zacHalo:SetSize(size * h, size * h)
        end
        if type(pin.HighlightTexture) == "table" then
            pin.HighlightTexture:ClearAllPoints()
            pin.HighlightTexture:SetAllPoints(pin)
        end
    end
end

-- ============================================================
-- THE PIN
-- ============================================================
-- Set as a global because the XML template resolves `mixin` out of _G
-- when a pin frame is first created. Assigned at file scope so it is
-- there long before any map is drawn.
_G.ZacUIMapPinMixin = BaseMapPoiPinMixin
    and BaseMapPoiPinMixin:CreateSubPin("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE")
    or {}

local PinMixin = _G.ZacUIMapPinMixin

-- ============================================================
-- NO PLATES
-- ============================================================
-- There was a plate behind every pin here for exactly one round: a flat
-- square with a coloured border, on the theory that a uniform frame
-- would make a photo-real taxi node and a flat coloured ball read as one
-- set. It does make them consistent. It also puts a box round a spirit
-- healer, and a box is a destination marker - which is wrong for a
-- crossing arrow and, it turns out, wrong-looking for everything else
-- too.
--
-- So the pins are bare icons at one consistent size. Consistency of SIZE
-- was most of what the plate was buying; the box was the part nobody
-- wanted.
function PinMixin:OnAcquired(info)
    if BaseMapPoiPinMixin and BaseMapPoiPinMixin.OnAcquired then
        BaseMapPoiPinMixin.OnAcquired(self, info)
    end
    self.zacDest = info.zacDest
    self.zacRotation = info.zacRotation
    self.zacAtlas = info.atlasName

    -- POOLED FRAMES CARRY THEIR LAST LIFE WITH THEM. Rotation especially:
    -- a pin that was a zone-crossing arrow last map comes back rotated,
    -- and if the next thing it is used for is a flight point then the
    -- flight point is tilted. This was lost for one revision when the
    -- plate code around it was deleted, which is exactly the kind of
    -- thing that only a test notices.
    local rotation = self.zacRotation or 0
    for _, key in ipairs({ "Texture", "HighlightTexture" }) do
        local tex = self[key]
        if tex then
            if tex.SetRotation then tex:SetRotation(rotation) end
            if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end
        end
    end

    -- ============================================================
    -- THE HALO
    -- ============================================================
    -- The same icon again, behind, in black and a third larger. Because
    -- it is the same art it hugs the icon's own outline instead of
    -- boxing it, so a taxi node keeps its shape and a crossing arrow
    -- keeps its point - and both stop disappearing into forest green.
    --
    -- Created once per pin and reused: these frames come out of a pool,
    -- and a texture made per acquisition would leak one per pin per map
    -- change. Halo, size and placement: I.Dress, above.
    I.Dress(self, self.zacAtlas, rotation, info.zacSize or 20, info.zacKind)
end

function PinMixin:OnMouseUp(button)
    if button == "LeftButton" then
        -- Travelling by clicking is the point of a crossing arrow, and
        -- boats and zeppelins carry a destination too.
        if self.zacDest and WorldMapFrame and WorldMapFrame.SetMapID then
            WorldMapFrame:SetMapID(self.zacDest)
        end
    elseif button == "RightButton" then
        if WorldMapFrame and WorldMapFrame.NavigateToParentMap then
            WorldMapFrame:NavigateToParentMap()
        end
    end
end

-- ============================================================
-- THE DATA PROVIDER
-- ============================================================
local Provider

local function BuildProvider()
    if not MapCanvasDataProviderMixin then return nil end
    local p = CreateFromMixins(MapCanvasDataProviderMixin)

    function p:RemoveAllData()
        if self:GetMap() then
            self:GetMap():RemoveAllPinsByTemplate("ZacUIMapPinTemplate")
        end
    end

    function p:RefreshAllData()
        self:RemoveAllData()
        if not ZacUIDB.modules or not ZacUIDB.modules.maps then return end

        local map = self:GetMap()
        local mapID = map and map:GetMapID()
        if not mapID then return end

        local pins = Maps.PinsFor(mapID)
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        local levels = DB().zoneLevels

        -- DUNGEONS AND RAIDS ON THE CONTINENT TOO (2026-10-31, Zac: "can
        -- we get some like dungeon and raid icons on this new map"): a
        -- continent map carries every child zone's dungeon and raid pins,
        -- each moved from its zone's fractions into the continent's with
        -- the zone's rectangle on the continent
        local list = {}
        for _, rec in ipairs(pins or {}) do list[#list + 1] = rec end
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        local CONT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
        if info and info.mapType == CONT and DB().dungeonsContinent ~= false
            and not (Maps.OpenMapLoaded and Maps.OpenMapLoaded())
            and C_Map.GetMapChildrenInfo and C_Map.GetMapRectOnMap then
            for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID) or {}) do
                local cpins = MapData.pins[child.mapID]
                if cpins then
                    local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(child.mapID, mapID)
                    if minX and maxX and maxX > minX and maxY > minY then
                        for _, rec in ipairs(cpins) do
                            local k = KINDS[rec[KIND]]
                            if k and k.group == "dungeons" then
                                local moved = { rec[KIND], (minX + rec[PX] / 100 * (maxX - minX)) * 100,
                                    (minY + rec[PY] / 100 * (maxY - minY)) * 100, rec[NAME],
                                    desc = rec.desc, min = rec.min, max = rec.max, dest = child.mapID }
                                list[#list + 1] = moved
                            end
                        end
                    end
                end
            end
        end
        if #list == 0 then return end

        for _, rec in ipairs(list) do
            local kind = rec[KIND]
            if Wanted(kind, faction) then
                local info = KINDS[kind]
                local atlas = Maps.Atlas(unpack(info.atlas))
                -- AN ICON THAT DOES NOT RESOLVE DRAWS NOTHING, and the
                -- pin is skipped entirely below. That is the right
                -- behaviour - an invisible pin still takes your clicks -
                -- but it is completely silent, so a category the client
                -- has no art for looks exactly like a category with no
                -- data in it. Recorded so /zui maps can name it.
                if not atlas then
                    I.unresolved = I.unresolved or {}
                    I.unresolved[kind] = info.atlas[1] or "?"
                end
                if atlas then
                    -- The name a crossing arrow should show is the name
                    -- of the zone it leads to, and the client already
                    -- knows that in the player's own language. Falling
                    -- back to the stored English only if the lookup
                    -- fails means these localise for free.
                    local name = rec[NAME]
                    if rec.dest and C_Map and C_Map.GetMapInfo then
                        local dest = C_Map.GetMapInfo(rec.dest)
                        if dest and dest.name and kind == "Arrow" then
                            name = dest.name
                        end
                    end
                    if levels and rec.min and rec.max then
                        name = string.format("%s (%d-%d)", name or "", rec.min, rec.max)
                    end

                    map:AcquirePin("ZacUIMapPinTemplate", {
                        position = CreateVector2D(rec[PX] / 100, rec[PY] / 100),
                        name = name,
                        description = rec.desc,
                        atlasName = atlas,
                        zacDest = rec.dest,
                        zacRotation = rec.rot,
                        zacSize = info.size,
                        zacKind = kind,
                    })
                end
            end
        end
    end

    return p
end

function I.Refresh()
    if Provider and Provider.RefreshAllData then
        pcall(Provider.RefreshAllData, Provider)
    end
end

-- ============================================================
-- CLASS-CONDITIONAL PINS
-- ============================================================
-- Moonglade's druid flight points exist only for druids. Spliced in here
-- rather than shipped inside D.pins so the shared table is never mutated
-- - a list that grows on login is a list that doubles on the second
-- login you did not expect.
local splicedFor
local function SpliceClassPins()
    local _, class = UnitClass("player")
    if splicedFor == class then return end
    splicedFor = class
    for _, entry in ipairs(MapData.classPins or {}) do
        if entry.class == class then
            local list = MapData.pins[entry.map]
            if list then
                local already = false
                for _, rec in ipairs(list) do
                    if rec == entry.pin then already = true break end
                end
                if not already then list[#list + 1] = entry.pin end
            end
        end
    end
end

-- ============================================================
-- TOWN AND CITY ICONS
-- ============================================================
-- Blizzard's continent maps carry a town icon and a city icon for every
-- settlement, and on a map already carrying flight points and crossings
-- they are noise.
--
-- There is no clean handle for this. A POI pin does not expose what it
-- represents, so the only way to recognise one is by the sprite it
-- draws: the shared POI sheet, cropped to one of two exact rectangles.
-- That is fragile and it is the only option, so it is written down
-- rather than buried. Gated off by default.
local POI_SHEET = 136441
local TOWN = { 0.5, 0.625, 0, 0.125 }
local CITY = { 0.625, 0.75, 0, 0.125 }
local CONTINENTS = { [1414] = true, [1415] = true, [947] = true }

local function SameRect(a, b)
    for i = 1, 4 do
        if math.abs(a[i] - b[i]) > 0.001 then return false end
    end
    return true
end

local function InstallTownHider()
    if not BaseMapPoiPinMixin or not BaseMapPoiPinMixin.OnAcquired then return end
    hooksecurefunc(BaseMapPoiPinMixin, "OnAcquired", function(self)
        if not On("hideTownIcons") then return end
        local map = self.GetMap and self:GetMap()
        local mapID = map and map.GetMapID and map:GetMapID()
        if not mapID or not CONTINENTS[mapID] then return end
        local tex = self.Texture
        if not tex or not tex.GetTexture or tex:GetTexture() ~= POI_SHEET then return end
        local l, _, _, _, r, _, t, b = tex:GetTexCoord()
        local rect = { l, r, t, b }
        if SameRect(rect, TOWN) or SameRect(rect, CITY) then
            self:Hide()
        end
    end)
end

-- ============================================================
-- PLAYER ARROW AND GROUP ICONS
-- ============================================================
-- Both live on the same shared sizes table hanging off the group-members
-- data provider, so they are applied together.
local unitPin

-- Blizzard's own numbers, read once before anything is written over
-- them, so turning the option off puts the map back exactly.
local stockSizes

local function ApplyUnitSizes()
    if not unitPin or not unitPin.dataProvider then return end
    local sizes = unitPin.dataProvider.GetUnitPinSizesTable
        and unitPin.dataProvider:GetUnitPinSizesTable()
    if not sizes then return end
    local db = DB()

    if not stockSizes then
        stockSizes = { player = sizes.player, party = sizes.party,
                       raid = sizes.raid }
    end

    -- 16 is Blizzard's own player arrow size. Leaving it alone when the
    -- option is off matters: this table is SHARED, so writing to it is
    -- not something to do speculatively.
    sizes.player = db.bigArrow and db.arrowSize or (stockSizes.player or 16)

    -- ============================================================
    -- EVERY GROUP MEMBER WAS BEING DRAWN TWICE
    -- ============================================================
    -- This is the actual reason the group icons kept looking wrong, and
    -- it is not in the drawing code at all - it is here.
    --
    -- Maps_Group gave up on Blizzard's group pins and draws its own
    -- class-coloured dot per member, for the good reasons written at the
    -- top of that file. But this function went on sizing BLIZZARD's
    -- blips to classIconSize at the same time, so Blizzard's stock marker
    -- and ZacUI's dot both landed on the same spot at the same size. The
    -- result on screen is a smeared double marker that is neither one
    -- thing nor the other - which is exactly what it looked like, and no
    -- amount of work on the dot could ever have fixed it, because the
    -- thing spoiling the dot was not the dot.
    --
    -- The comment in Maps_Group claims these are "pushed down to a size
    -- that reads as a pinprick". They never were. That sentence described
    -- an intention nobody had implemented, and it is the reason three
    -- rounds of looking went past this line without stopping.
    --
    -- Blizzard's blips cannot be hidden - a UnitPositionFrame draws them
    -- internally - but they CAN be sized, and 0.01 is a blip too small to
    -- put a pixel on the screen. That is the switch-off this needs.
    if db.classIcons then
        sizes.party = 0.01
        sizes.raid = 0.01
    else
        sizes.party = stockSizes.party
        sizes.raid = stockSizes.raid
    end

    if unitPin.SynchronizePinSizes then
        pcall(unitPin.SynchronizePinSizes, unitPin)
    end
end

-- CLASS COLOUR, NOT A CLASS ICON SHEET.
--
-- The first version of this pointed the group pins at
-- Interface\WorldStateFrame\Icons-Classes, which is not an icon - it is
-- a 4x4 SHEET containing all sixteen class icons. SetPinTexture takes a
-- texture and applies it whole; there is nowhere in that call to say
-- which cell you meant. So every party member rendered as the complete
-- sheet: a little grid of sixteen tiny icons sitting on the map where a
-- person should be. Which is exactly what it looked like.
--
-- Cropping it would mean reaching past SetPinTexture to the pin's own
-- texture object and re-applying a texcoord after every appearance
-- update, racing Blizzard's own code for the same field. The useful
-- information here is WHICH CLASS, and useClassColor delivers that on
-- Blizzard's own correctly-sized dot with none of that. So the texture
-- is left alone and only the colour is asked for.
-- SOLID DOTS, COLOURED BY CLASS - and painted here rather than asked for.
--
-- The previous version set the appearance field `useClassColor` and left
-- it at that, which is the documented way and does nothing visible on
-- this client: the group pin still came out as Blizzard's stock marker.
-- Asking a system to do something and never checking whether it did is
-- how this has gone wrong repeatedly, so this stops asking.
--
-- A dot is a solid fill in the class's colour. That is two calls on a
-- texture, and the only real question is WHICH texture - so it is
-- resolved the same defensive way the tray resolves a button icon:
-- the named field first, then a sweep, and no destructive change if
-- neither finds anything.
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function ClassColourFor(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return nil end
    local _, class = UnitClass(unit)
    if class then return ns.ClassColor(class) end
    return nil
end

local function PaintDot(pin)
    local textures = {}
    if pin.Texture then textures[#textures + 1] = pin.Texture end
    if #textures == 0 and pin.GetRegions then
        for _, r in ipairs({ pin:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture")
                and r.GetDrawLayer and r:GetDrawLayer() ~= "HIGHLIGHT" then
                textures[#textures + 1] = r
            end
        end
    end
    if #textures == 0 then return false end

    local r, g, b = ClassColourFor(pin.unit or pin.unitToken)
    for _, tex in ipairs(textures) do
        if tex.SetTexture then tex:SetTexture(WHITE) end
        if tex.SetTexCoord then tex:SetTexCoord(0, 1, 0, 1) end
        if r and tex.SetVertexColor then
            tex:SetVertexColor(r, g, b, 1)
        elseif tex.SetVertexColor then
            -- No unit to read a class from - a neutral dot rather than
            -- a white square, which would read as a bug.
            local c = Col("accent")
            tex:SetVertexColor(c.r, c.g, c.b, 1)
        end
    end
    return true
end

local function ApplyClassIcons(pin)
    if not On("classIcons") then return end
    -- Kept as well, in case a future build honours it - it costs nothing
    -- and it is the documented route.
    if pin.SetAppearanceField then
        for _, which in ipairs({ "party", "raid" }) do
            pcall(pin.SetAppearanceField, pin, which, "useClassColor", true)
        end
    end
    pcall(PaintDot, pin)
end

local function HookUnitPin(pin)
    unitPin = pin
    ApplyClassIcons(pin)
    ApplyUnitSizes()
    -- Blizzard resets pin appearance whenever the group changes, so the
    -- texture has to go back on afterwards rather than once at setup.
    if pin.UpdateAppearanceData then
        hooksecurefunc(pin, "UpdateAppearanceData", function(self)
            ApplyClassIcons(self)
        end)
    end
end

-- ============================================================
-- APPLY
-- ============================================================
function I.Apply()
    local map = _G.WorldMapFrame
    if not map then return end

    SpliceClassPins()

    if not Provider then
        Provider = BuildProvider()
        if Provider and map.AddDataProvider then
            map:AddDataProvider(Provider)
        end
        InstallTownHider()
        Maps.ForEachPin("GroupMembersPinTemplate", HookUnitPin)
    end

    ApplyUnitSizes()
    I.Refresh()
end

I.KINDS = KINDS
I.Wanted = Wanted
-- Exposed so the suite can ask what happened to BLIZZARD's group blips,
-- not just to ZacUI's dots. Looking at only our own half of the map is
-- how a teammate came to be drawn twice for three rounds running.
I.ApplyUnitSizes = ApplyUnitSizes

-- shared with later ZacUI files
ns.MapsIcons = I
