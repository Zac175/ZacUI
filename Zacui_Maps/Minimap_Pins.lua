-- Minimap_Pins - flight paths, graveyards, dungeon entrances and zone
-- crossings drawn on the minimap, using the same glyphs as the world map,
-- and your group's names over their minimap dots.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE SAME ART ON BOTH MAPS, DELIBERATELY. The glyph table is imported
-- from Maps_Icons rather than copied, so a marker cannot mean one thing
-- on the world map and another on the minimap - and redrawing a glyph
-- changes both.
--
-- WHAT MAKES THIS HARDER THAN THE WORLD MAP. A world map pin is placed
-- as a fraction of the canvas and the canvas does the rest. A minimap
-- blip has to be placed in YARDS, because the minimap is a fixed circle
-- showing a variable radius of ground. That means three conversions -
-- map position to world position, world offset to yards, yards to
-- pixels - and a rotation if the player has a rotating minimap. Every
-- one of them is a place to be silently wrong, so the count of what was
-- drawn and the reason for a zero are both reported by /zui minimapinfo.

local ADDON_NAME = ...
-- Zacui_Maps is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local MapData = ns.MapData
local Maps = ns.Maps
local MapsIcons = ns.MapsIcons
local Print = ns.Print

local MP = {}

local KIND, PX, PY, NAME = 1, 2, 3, 4

-- The ground the minimap shows ACROSS ITS WIDTH, in yards, per zoom
-- level - outdoors and indoors differ (HereBeDragons' table, the one
-- every minimap pin addon uses). These are widths, not radii: the edge of
-- the map is half of this from the middle. The old table here was used as
-- a radius, which put every marker at half its distance.
local MAP_YARDS = {
    outdoor = { [0] = 466 + 2/3, 400, 333 + 1/3, 266 + 2/3, 200, 133 + 1/3 },
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
}

-- Is the minimap in its indoor mode? Not the same question as IsIndoors:
-- city streets can be indoor minimap and still mountable. The client
-- keeps each mode's zoom in its own cvar, so whichever one matches the
-- current zoom is the mode in use; only when both match is it a guess.
local function MinimapIndoor()
    local z = Minimap and Minimap:GetZoom()
    local out = tonumber(GetCVar and GetCVar("minimapZoom"))
    local ins = tonumber(GetCVar and GetCVar("minimapInsideZoom"))
    if z and out and ins and out ~= ins then
        if z == ins then return true end
        if z == out then return false end
    end
    return (IsIndoors and IsIndoors()) and true or false
end

-- Yards from the middle of the map to its edge, right now.
local function HalfYards()
    local z = (Minimap and Minimap:GetZoom()) or 0
    local t = MinimapIndoor() and MAP_YARDS.indoor or MAP_YARDS.outdoor
    return (t[z] or t[0]) / 2
end

-- One pass's view of the minimap: half its width in pixels, the yards from
-- its middle to its edge, and the turn if it rotates. Read ONCE per pass
-- and handed to ToPixels, not read per marker: GetZoom, three GetCVars
-- and GetPlayerFacing are C calls, and the names pass makes a ToPixels
-- call for every raid member several times a second.
local view = {}
local function ReadView()
    view.half = ((Minimap and Minimap:GetWidth()) or 140) / 2
    view.hy = HalfYards()
    if GetCVar and GetCVar("rotateMinimap") == "1" and GetPlayerFacing then
        local f = GetPlayerFacing() or 0
        view.cos, view.sin = math.cos(f), math.sin(f)
    else
        view.cos, view.sin = nil, nil
    end
    return view
end

-- East / north yards from you -> pixels from the minimap's middle. A
-- rotating minimap turns the ground, so the offset turns with it.
local function ToPixels(east, north, v)
    if v.cos then
        local c, sn = v.cos, v.sin
        local south = -north
        east, south = east * c - south * sn, east * sn + south * c
        north = -south
    end
    return east / v.hy * v.half, north / v.hy * v.half, v.half
end

local blips = {}
local driver
MP.drawn = 0
MP.reason = "not run yet"
-- What the last pass computed, per marker. Kept so the numbers can be
-- read back rather than inferred from pixels.
MP.last = {}

-- ============================================================
-- SETTINGS
-- ============================================================
local function DB()
    ZacUIDB.minimap = ZacUIDB.minimap or {}
    local d = ZacUIDB.minimap
    -- ============================================================
    -- OFF BY DEFAULT, AND THAT IS A RETREAT
    -- ============================================================
    -- This shipped on. It was wrong on screen - markers sitting in fixed
    -- places rather than where the things are - and it went out that way
    -- because none of the arithmetic underneath it can be checked from
    -- outside the game.
    --
    -- Three conversions, three unverifiable assumptions: that
    -- GetWorldPosFromMapPos returns north-on-x and west-on-y, that the
    -- zoom-to-yards table below is still the client's, and that a square
    -- minimap shows the same ground at its corners as at its edges - it
    -- does not, it shows more. The harness cannot test any of the three,
    -- because the harness is where those numbers came from.
    --
    -- A feature that cannot be verified should not be on by default. It
    -- stays, it is one checkbox away, and /zui minimapinfo now prints
    -- every marker's computed distance and offset so it can be checked
    -- against what is actually on screen. When those line up it can come
    -- back on.
    if d.pins == nil then d.pins = false end
    -- ON (2026-10-31, Zac: "do all this shit for the minimap as well" -
    -- the dungeon and raid icons of the new map, on the minimap too).
    -- The world-to-yards arithmetic above was checked against the
    -- minimap's own zone dots meanwhile; once, so a later "off" sticks.
    if not d._pinsV2 then d._pinsV2 = true d.pins = true end
    if d.pinFlight == nil then d.pinFlight = true end
    if d.pinGrave == nil then d.pinGrave = true end
    if d.pinDungeon == nil then d.pinDungeon = true end
    if d.pinCrossing == nil then d.pinCrossing = true end
    if d.pinSize == nil then d.pinSize = 14 end
    -- Names over your group's minimap dots.
    if d.groupNames == nil then d.groupNames = true end
    if d.groupNameSize == nil then d.groupNameSize = 9 end
    if d.groupNameDeclutter == nil then d.groupNameDeclutter = true end
    return d
end

-- The world map's own group names, so one setting cannot mean two things.
local GROUP_SETTING = {
    flight = "pinFlight", spirit = "pinGrave",
    dungeons = "pinDungeon", crossing = "pinCrossing",
}

-- ============================================================
-- WHERE THINGS ARE
-- ============================================================
-- A map position is a fraction of a zone; a minimap offset is a distance
-- in yards. GetWorldPosFromMapPos is the only bridge between the two, and
-- a client without it cannot do this at all - which is a thing to say
-- out loud rather than to fail quietly at.
local function WorldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
        return nil
    end
    local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID,
        CreateVector2D(x, y))
    if not ok or not pos or not pos.GetXY then return nil end
    -- World coordinates run NORTH on x and WEST on y, which is why the
    -- signs below look backwards and are not.
    return pos:GetXY()
end

local function Blip(index)
    local b = blips[index]
    if not b then
        b = Minimap:CreateTexture(nil, "OVERLAY")
        b._zui_own = true
        blips[index] = b
    end
    return b
end

-- ============================================================
-- DRAW
-- ============================================================
-- A record's place in the world never changes, so it is converted once
-- per zone and kept, not converted again ten times a second. Two
-- parallel arrays per map, indexed like the record list; false marks a
-- record the client could not place.
local worldCache = {}
local function WorldCache(mapID, records)
    local c = worldCache[mapID]
    if c and c.records == records then return c end
    c = { records = records, x = {}, y = {} }
    for i, rec in ipairs(records) do
        local wx, wy = WorldPos(mapID, rec[PX] / 100, rec[PY] / 100)
        c.x[i], c.y[i] = wx or false, wy or false
    end
    worldCache[mapID] = c
    return c
end

-- The same atlas the world map uses, resolved the same way. The glyph
-- files this used to point at are gone; sharing Blizzard's art keeps the
-- two maps identical for free, which was the whole point of importing
-- KINDS rather than copying it. Resolved once per kind: Maps.Atlas
-- builds a table and a key string on every call, even on a hit.
local atlasByKind = {}
local function KindAtlas(kind, info)
    local a = atlasByKind[kind]
    if a == nil then
        a = Maps.Atlas(unpack(info.atlas)) or false
        atlasByKind[kind] = a
    end
    return a or nil
end

function MP.Update()
    local shown = 0
    local d = DB()

    local function stop(why)
        MP.reason = why
        for i = shown + 1, #blips do blips[i]:Hide() end
        for i = #MP.last, shown + 1, -1 do MP.last[i] = nil end
        MP.drawn = shown
    end

    if not Minimap or not Minimap.GetZoom then return stop("no minimap") end
    if not d.pins then return stop("turned off") end

    local mapID = C_Map and C_Map.GetBestMapForUnit
        and C_Map.GetBestMapForUnit("player")
    if not mapID then return stop("the client will not say what zone you are in") end

    local records = (Maps.PinsFor and Maps.PinsFor(mapID)) or MapData.pins[mapID]
    if not records then return stop("no data for this zone") end

    local ppos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    if not ppos then return stop("no player position") end
    local px, py = ppos:GetXY()
    local pwx, pwy = WorldPos(mapID, px, py)
    if not pwx then
        return stop("this client has no GetWorldPosFromMapPos, so a map "
            .. "position cannot be turned into a distance")
    end

    -- Ten times a second with the player's position the only thing that
    -- moves: the zoom, cvars and width are read once here, the records'
    -- world positions come from the per-zone cache.
    local v = ReadView()
    local radius = v.hy
    local size = tonumber(d.pinSize) or 14
    local world = WorldCache(mapID, records)
    local KINDS = MapsIcons.KINDS

    local faction = UnitFactionGroup and UnitFactionGroup("player")

    for i, rec in ipairs(records) do
        local info = KINDS[rec[KIND]]
        local setting = info and GROUP_SETTING[info.group]
        local wanted = setting and d[setting]
            and (not info.faction or info.faction == faction)
        local atlas = wanted and KindAtlas(rec[KIND], info) or nil
        if wanted and atlas then
            local wx, wy = world.x[i], world.y[i]
            if wx then
                -- East is a DECREASE in world y; north is an increase in
                -- world x. Screen x is east, screen y is north.
                local east  = pwy - wy
                local north = wx - pwx
                local dist = math.sqrt(east * east + north * north)
                local x, y, half = ToPixels(east, north, v)
                -- inside the square, corners included
                if math.abs(x) <= half and math.abs(y) <= half then
                    shown = shown + 1
                    -- Recorded so the numbers can be read against what is
                    -- on screen. "The icons are in the wrong place" is
                    -- unanswerable without them: a marker drawn at the
                    -- right pixel for the wrong distance and one drawn at
                    -- the wrong pixel look identical. The entry tables
                    -- are kept and rewritten, not made fresh each pass.
                    local m = MP.last[shown]
                    if not m then m = {} MP.last[shown] = m end
                    m.name, m.kind = rec[NAME], rec[KIND]
                    m.yards, m.east, m.north = dist, east, north
                    m.x, m.y = x, y
                    local b = Blip(shown)
                    if b._zAtlas ~= atlas and b.SetAtlas then
                        b._zAtlas = atlas
                        b:SetAtlas(atlas)
                    end
                    b:SetVertexColor(1, 1, 1, 1)
                    -- the world map's proportions: a raid bigger than a dungeon
                    local k = (info.size or 20) / 20
                    b:SetSize(size * k, size * k)
                    b:ClearAllPoints()
                    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
                    b:Show()
                end
            end
        end
    end

    stop(shown > 0 and "ok" or "nothing of yours is within "
        .. math.floor(radius) .. " yards")
end

-- ============================================================
-- GROUP NAMES
-- ============================================================
-- A name over each group member's minimap dot. The game draws the dots
-- and says nothing about where; the names are placed from each member's
-- spot on the zone map, turned into yards. Inside dungeons and
-- raids the game gives addons no positions at all, so there are no names
-- there - only the dots.
local tags = {}
local namesDriver
MP.namesDrawn = 0
MP.lastNames = {}

-- A zone's width and height in yards, from where its corners sit in the
-- world. Distances only, so it does not matter which way the world axes
-- run. Cached per map.
local zoneYards = {}
local function ZoneYards(mapID)
    local c = zoneYards[mapID]
    if c == nil then
        c = false
        local ax, ay = WorldPos(mapID, 0, 0)
        local bx, by = WorldPos(mapID, 1, 0)
        local cx, cy = WorldPos(mapID, 0, 1)
        if ax and bx and cx then
            local w = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
            local h = math.sqrt((cx - ax) ^ 2 + (cy - ay) ^ 2)
            if w > 0 and h > 0 then c = { w, h } end
        end
        zoneYards[mapID] = c
    end
    if c then return c[1], c[2] end
end

local function Tag(i)
    local t = tags[i]
    if not t then
        t = Minimap:CreateFontString(nil, "OVERLAY")
        t._zui_own = true
        t:SetWordWrap(false)
        tags[i] = t
    end
    return t
end

-- Names that would overlap one already placed are left off (Maps_Core).
local declutter = Maps.NewDeclutter()

-- MP.lastNames is only filled while MP.diagnosing is set (Diagnose sets
-- it around one pass), so the ordinary tick writes no record tables.
MP.diagnosing = nil

function MP.UpdateNames()
    local d = DB()
    local shown = 0
    local function stop(why)
        MP.namesReason = why
        for i = shown + 1, #tags do tags[i]:Hide() end
        MP.namesDrawn = shown
    end
    if not Minimap or not Minimap:IsVisible() then return stop("minimap hidden") end
    if d.groupNames == false then return stop("turned off") end
    if not (IsInGroup and IsInGroup()) then return stop("not in a group") end
    local G = ns.MapsGroup
    if not (G and G.Positions) then return stop("no group list") end
    -- Positions as map fractions (x runs east, y runs south - no axis to
    -- guess), turned into yards by the zone's size in yards.
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local ppos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    local px, py
    if ppos then px, py = ppos:GetXY() end
    if not (px and (px > 0 or py > 0)) then
        return stop("the game gives no positions here (dungeons and raids)")
    end
    local yw, yh = ZoneYards(mapID)
    if not yw then return stop("this zone's size in yards is unknown") end
    local diag = MP.diagnosing
    if diag then wipe(MP.lastNames) end

    -- Everything that is the same for every member is read once here:
    -- the minimap's zoom, width and rotation, the font path and size.
    local size = tonumber(d.groupNameSize) or 9
    local dodge = d.groupNameDeclutter ~= false
    local v = ReadView()
    local cfg = ZacUIDB and ZacUIDB.font or {}
    local fpath = ns.ResolveFontPath and ns.ResolveFontPath(cfg.name)
    local fdelta = cfg.delta or 0
    local ClassColour = G.ClassColour
    declutter.Reset()
    -- The same per-member reads the world-map dots use (one read per
    -- member per tick between the two maps).
    local snapshot = G.Positions(mapID)
    for i = 1, snapshot.n do
        local unit, ux, uy = snapshot.unit[i], snapshot.x[i], snapshot.y[i]
        if not UnitIsConnected or UnitIsConnected(unit) then
            local east, north = (ux - px) * yw, (py - uy) * yh
            local x, y, half = ToPixels(east, north, v)
            if diag then
                MP.lastNames[#MP.lastNames + 1] = { name = UnitName(unit), east = east, north = north, x = x, y = y }
            end
            if math.abs(x) <= half - 2 and math.abs(y) <= half - 2 then
                local t = Tag(shown + 1)
                Maps.LabelFont(t, size, fpath, fdelta)
                t:SetText((UnitName(unit)))
                if ClassColour then t:SetTextColor(ClassColour(unit)) end
                -- just above the dot, so the dot stays visible
                local ty = y + 4 + size / 2
                local ok = true
                if dodge then
                    ok = declutter.Place(x, ty, (t:GetStringWidth() or 0) / 2 + 1, size / 2 + 1)
                end
                if ok then
                    shown = shown + 1
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", Minimap, "CENTER", x, ty)
                    t:Show()
                end
            end
        end
    end
    stop(shown > 0 and "ok" or "nobody in range")
end

-- ============================================================
-- APPLY
-- ============================================================
function MP.Apply()
    if not Minimap then return end
    -- Names: their own driver, only running while they are on.
    if not namesDriver then
        namesDriver = CreateFrame("Frame", nil, Minimap)
        namesDriver._elapsed = 0
    end
    if DB().groupNames ~= false then
        namesDriver:SetScript("OnUpdate", function(self, dt)
            self._elapsed = self._elapsed + dt
            -- Five times a second. Each pass is a GetPlayerMapPosition
            -- per raid member, outdoors, all the time; at 20 Hz that was
            -- 800 position reads a second in a 40-man for labels that
            -- sit on dots the game itself only nudges.
            if self._elapsed < 0.2 then return end
            self._elapsed = 0
            MP.UpdateNames()
        end)
    else
        namesDriver:SetScript("OnUpdate", nil)
    end
    MP.UpdateNames()
    -- Markers: their own driver too, and only while they are on (they
    -- ship off). One pass either way, so turning them off clears them.
    if not driver then
        driver = CreateFrame("Frame", nil, Minimap)
        driver._elapsed = 0
    end
    if DB().pins then
        driver:SetScript("OnUpdate", function(self, dt)
            self._elapsed = self._elapsed + dt
            -- Ten times a second. These move only when the player does,
            -- and every tick is three coordinate conversions per pin.
            if self._elapsed < 0.1 then return end
            self._elapsed = 0
            MP.Update()
        end)
    else
        driver:SetScript("OnUpdate", nil)
    end
    MP.Update()
end

function MP.Diagnose()
    Print("minimap markers: " .. tostring(MP.drawn) .. " drawn"
        .. (MP.reason and ("  (" .. MP.reason .. ")") or ""))
    if not DB().pins then
        Print("  off by default - the yard maths could not be verified "
            .. "outside the game. Turn it on from /zui minimap and compare "
            .. "the numbers below against what you can see.")
    end

    local mapID = C_Map and C_Map.GetBestMapForUnit
        and C_Map.GetBestMapForUnit("player")
    Print("  zone " .. tostring(mapID)
        .. "   zoom " .. tostring(Minimap and Minimap:GetZoom())
        .. " = " .. string.format("%.0f", HalfYards())
        .. " yards to the edge   minimap " .. tostring(Minimap and Minimap:GetWidth())
        .. "px wide")
    Print("  GetWorldPosFromMapPos: "
        .. tostring(C_Map and C_Map.GetWorldPosFromMapPos ~= nil))

    -- One pass with the record switched on, so the per-name numbers
    -- below are current without the ordinary tick paying to keep them.
    MP.diagnosing = true
    pcall(MP.UpdateNames)
    MP.diagnosing = nil
    Print("  group names: " .. tostring(MP.namesDrawn or 0) .. " drawn"
        .. (MP.namesReason and ("  (" .. MP.namesReason .. ")") or "")
        .. "   minimap mode: " .. (MinimapIndoor() and "indoor" or "outdoor"))
    for i = 1, math.min(#MP.lastNames, 8) do
        local m = MP.lastNames[i]
        Print(string.format("  %-14s %+5.0f yd east %+5.0f yd north  ->  %+.0f, %+.0f px",
            tostring(m.name), m.east, m.north, m.x, m.y))
    end
    wipe(MP.lastNames)

    for i = 1, math.min(#MP.last, 8) do
        local m = MP.last[i]
        Print(string.format("  %-22s %-9s %4.0f yards  ->  %+.0f, %+.0f px",
            tostring(m.name):sub(1, 22), tostring(m.kind),
            m.yards, m.x, m.y))
    end
    if #MP.last > 8 then Print("  ...and " .. (#MP.last - 8) .. " more") end
end

MP.DB = DB

-- shared with later ZacUI files
ns.MinimapPins = MP
