-- Win_FlightTimes - how long each flight takes, and a countdown while you
-- fly.
-- Part of ZacUI; load order is set by the TOC (before Win_Taxi, which
-- shows the times in the flight master's list).
--
-- LEARNED FROM YOUR OWN FLIGHTS. Every flight you take is timed, from the
-- moment you are on the taxi to the moment you are off it: the whole trip
-- (where you were -> where you asked to go, stops and all) and, when it
-- can tell them apart, each leg - a direct flight is one leg, and on a
-- trip with stops the moment you pass over each stop's flight master
-- splits it. The last few times of each are kept and the middle one is
-- used, so one slow flight (a lag spike, a loading hitch) never sticks,
-- and a time that has changed is learned by the next flights. A flight
-- cut short - left early, died, logged out in the air, landed somewhere
-- else - teaches nothing.
--
-- ESTIMATED OTHERWISE, marked "~". A trip never flown is the sum of its
-- legs: a leg flown before at its own time, the rest at their straight
-- length over a speed learned from your own flights on that continent
-- (DEFAULT_SPEED until there is one). The world map part measured
-- direct flights already (Zacui_WorldMap/Map/Flights.lua); those times
-- are copied in once, read only, so nothing measured there is lost.
--
-- WHERE IT IS KEPT. ZacUIDB.flightTimes[game] - account-wide, one store
-- per game (Classic Era, TBC and Forever have their own networks), keyed
-- by the game's node id (C_TaxiMap) so two flight masters with one name
-- never mix. Gathered data: outside every profile. The settings are
-- ZacUIDB.windows.flight (the Game windows section of a profile).
--
-- THE COUNTDOWN. A bar (or just its text) with where you are going, the
-- time left and a fill, on a 0.1 s ticker that runs only between take-off
-- and landing. It disappears when you land.

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local Kit = ns.Kit
local UI = ns.UI

local math_floor, math_sqrt, math_max, math_min = math.floor, math.sqrt, math.max, math.min

local FT = {}
ns.FlightTimes = FT
-- this copy is the one in use (a file run twice leaves its old hooks
-- behind: they stand down)
local function Live() return ns.FlightTimes == FT end

local KEEP = 5               -- times kept per trip and per leg (the middle one is used)
local KEEP_SPEED = 9         -- speeds kept per continent
local DEFAULT_SPEED = 26     -- yards a second along the straight line between flight masters
                             -- (the paths bend; your own flights replace it)
local NOMINAL = 35000        -- yards across a flight map, when the game gives no world size
local ASPECT = 352 / 316     -- the flight map's height over its width (TaxiFrame's picture)
local MIN_SECS = 5           -- shorter than this was no flight
local SHORT = 0.6            -- under this share of a measured time = cut short
local TICK = 0.1             -- the countdown: ten times a second at most
local TAKEOFF_WAIT = 10      -- seconds from the click to being on the taxi
local LANDED_NEAR = 400      -- yards from the destination's flight master at landing
local PASS_NEAR = 150        -- yards: passing over a stop
local WARN_AT = 5            -- "Landing in 5 seconds"

-- ============================================================
-- SETTINGS (ZacUIDB.windows.flight)
-- ============================================================
FT.DEFAULTS = {
    listTimes = true,        -- times in the flight master's list and tooltips
    sortTime = false,        -- the list quickest first
    enabled = true,          -- the countdown while flying
    style = "bar",           -- "bar" | "text"
    width = 240, height = 20,
    icon = true, spark = true,
    voice = false,           -- "Landing in 5 seconds"
    -- nil: ZacUI's bar texture, the accent fill, a dark track, the
    -- palette's text colour, ZacUI's font at a size from the bar's height
    texture = nil, fillColor = nil, bgColor = nil, textColor = nil,
    labelFont = nil, timeFont = nil,
    showAnim = { style = "fade", duration = 0.25, delay = 0, easing = "linear", dir = "up", distance = 12 },
    hideAnim = { style = "fade", duration = 0.4, delay = 0, easing = "linear", dir = "up", distance = 12 },
}

local scratchCfg
function FT.DB()
    local w = Kit and Kit.DB and Kit.DB()
    if type(w) ~= "table" then
        scratchCfg = scratchCfg or {}
        w = { flight = scratchCfg }
    end
    local d = w.flight
    if type(d) ~= "table" then d = {} w.flight = d end
    if ns.FillDefaults then ns.FillDefaults(d, FT.DEFAULTS)
    else for k, v in pairs(FT.DEFAULTS) do if d[k] == nil then d[k] = v end end end
    return d
end

-- ============================================================
-- THE STORE (ZacUIDB.flightTimes[game])
-- ============================================================
local function Prep(s)
    if type(s.trips) ~= "table" then s.trips = {} end    -- "from>to" -> { seconds, ... }
    if type(s.legs) ~= "table" then s.legs = {} end      -- "a>b" -> { seconds, ... } (one hop)
    if type(s.speed) ~= "table" then s.speed = {} end    -- continent -> { yards a second, ... }
    return s
end

local function Game()
    return (ns.RealFlavor and ns.RealFlavor()) or (ns.Flavor and ns.Flavor()) or "era"
end

local scratchStore
local function Store()
    if type(ZacUIDB) ~= "table" then
        scratchStore = scratchStore or {}
        return Prep(scratchStore)
    end
    local all = ZacUIDB.flightTimes
    if type(all) ~= "table" then all = {} ZacUIDB.flightTimes = all end
    local g = Game()
    if type(all[g]) ~= "table" then all[g] = {} end
    return Prep(all[g])
end
FT.Store = Store

local function Median(list)
    if type(list) ~= "table" then return nil end
    local n = #list
    if n == 0 then return nil end
    local t = {}
    for i = 1, n do t[i] = list[i] end
    table.sort(t)
    if n % 2 == 1 then return t[(n + 1) / 2] end
    return (t[n / 2] + t[n / 2 + 1]) / 2
end
FT.Median = Median

local function Add(tbl, key, v, keep)
    local list = tbl[key]
    if type(list) ~= "table" then list = {} tbl[key] = list end
    list[#list + 1] = v
    while #list > (keep or KEEP) do table.remove(list, 1) end
end

-- the world map's direct flights ("from|to" by the flight masters' full
-- names, seconds), copied in once; theirs is never touched
local function Imported(st, aName, bName)
    local imp = st.imported
    if type(imp) ~= "table" or not (aName and bName) then return nil end
    local v = imp[aName .. "|" .. bName]
    return type(v) == "number" and v > 0 and v or nil
end

function FT.ImportWorldMap()
    if type(ZacUIDB) ~= "table" then return false end
    local all = ZacUIDB.flightTimes
    local done = type(all) == "table" and type(all[Game()]) == "table" and all[Game()].importedWorldMap
    if done then return false end
    local wm = rawget(_G, "ZacuiWorldMapDB")
    local src = type(wm) == "table" and type(wm.worldmap) == "table" and wm.worldmap.flightTimes
    if type(src) ~= "table" then return false end   -- (the world map is off: try at the next login)
    local st = Store()
    local imp = type(st.imported) == "table" and st.imported or {}
    local n = 0
    for k, v in pairs(src) do
        if type(k) == "string" and k:find("|", 1, true) and type(v) == "number" and v >= MIN_SECS and imp[k] == nil then
            imp[k] = v
            n = n + 1
        end
    end
    if next(imp) then st.imported = imp end
    st.importedWorldMap = true
    return true, n
end

-- ============================================================
-- THE FLIGHT MASTER: NODES, HOPS AND TIMES
-- ============================================================
local function XY(v)
    if type(v) ~= "table" then return nil end
    if v.GetXY then
        local ok, x, y = pcall(v.GetXY, v)
        if ok and type(x) == "number" then return x, y end
    end
    if type(v.x) == "number" then return v.x, v.y end
    return nil
end

local function ToWorld(mapID, pos)
    if not (mapID and pos and C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
    local ok, _, wp = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
    if not ok then return nil end
    return XY(wp)
end

-- where you are, in the yards the nodes are measured in (nil when the
-- game will not say: an instance, or no map)
local function PlayerWorld(mapID)
    if not (mapID and C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not (ok and pos) then return nil end
    return ToWorld(mapID, pos)
end

-- "Ironforge, Dun Morogh" -> "Ironforge"
local function Place(full)
    local p = tostring(full or ""):match("^(.-),%s*.+$")
    if p and p ~= "" then return p end
    return tostring(full or "?")
end
FT.Place = Place

-- Every flight master on the open flight map, once per frame however
-- many rows ask: its key, name, kind and where it is.
local snap, snapAt
local function ReadNodes()
    local n = (NumTaxiNodes and NumTaxiNodes()) or 0
    local now = GetTime()
    if snap and snapAt == now and snap.n == n then return snap end
    local s = { n = n, nodes = {} }
    local okID, mapID = false, nil
    if GetTaxiMapID then okID, mapID = pcall(GetTaxiMapID) end
    if not okID or type(mapID) ~= "number" then mapID = nil end
    s.mapID = mapID
    local bySlot = {}
    if mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
        local ok, list = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
        if ok and type(list) == "table" then
            for _, info in ipairs(list) do
                if type(info) == "table" and info.slotIndex then bySlot[info.slotIndex] = info end
            end
        end
    end
    local world, x0, y0, spread = true, nil, nil, 0
    for i = 1, n do
        local info = bySlot[i]
        local node = { slot = i, name = (TaxiNodeName and TaxiNodeName(i)) or "?",
            kind = TaxiNodeGetType and TaxiNodeGetType(i) or nil }
        if TaxiNodePosition then node.tx, node.ty = TaxiNodePosition(i) end
        if info then
            node.id = info.nodeID
            if info.position then
                node.mx, node.my = XY(info.position)
                node.wx, node.wy = ToWorld(mapID, info.position)
            end
        end
        if node.wx then
            x0, y0 = x0 or node.wx, y0 or node.wy
            spread = math_max(spread, math.abs(node.wx - x0) + math.abs(node.wy - y0))
        else
            world = false
        end
        -- the game's node id; else the name where it sits (two flight
        -- masters with one name are never in the same spot)
        node.key = node.id and ("n" .. node.id)
            or (node.name .. "@" .. math_floor((node.tx or 0) * 1000 + 0.5) .. "," .. math_floor((node.ty or 0) * 1000 + 0.5))
        if node.kind == "CURRENT" then s.current = i end
        s.nodes[i] = node
    end
    -- distances in yards when the game places every node in the world,
    -- else on the flight map at a continent's rough size
    s.yards = world and n > 0 and spread > 1
    for _, node in pairs(s.nodes) do
        if s.yards then
            node.dx, node.dy = node.wx, node.wy
        else
            node.dx = (node.mx or node.tx or 0) * NOMINAL
            node.dy = (node.my or node.ty or 0) * NOMINAL * ASPECT
        end
    end
    s.mapKey = tostring(mapID or "taxi") .. (s.yards and "" or "~")
    snap, snapAt = s, now
    return s
end
FT.ReadNodes = ReadNodes

local function Dist(a, b)
    if not (a and b and a.dx and b.dx) then return 0 end
    local dx, dy = a.dx - b.dx, a.dy - b.dy
    return math_sqrt(dx * dx + dy * dy)
end

-- the route to slot: { { fromSlot, toSlot }, ... } and how many hops the
-- game says it has; `real` = every hop is a real pair of flight masters
-- (else one straight line stands in for the whole route)
local function Hops(s, slot)
    local count = GetNumRoutes and GetNumRoutes(slot)
    if type(count) ~= "number" or count < 1 then count = 1 end
    if TaxiGetNodeSlot and s.current then
        local out, prev = {}, s.current
        for h = 1, count do
            local a, b = TaxiGetNodeSlot(slot, h, true), TaxiGetNodeSlot(slot, h, false)
            if a ~= prev or not s.nodes[b] then out = nil break end
            out[h] = { a, b }
            prev = b
        end
        if out and prev == slot then return out, count, true end
    end
    return { { s.current, slot } }, count, count == 1
end

function FT.Speed(mapKey)
    local st = Store()
    local m = Median(st.speed[mapKey])
    if m and m > 0 then return m end
    -- another continent's, measured the same way
    local yards = not tostring(mapKey):find("~", 1, true)
    local all = {}
    for k, list in pairs(st.speed) do
        if (not tostring(k):find("~", 1, true)) == yards and type(list) == "table" then
            for _, v in ipairs(list) do all[#all + 1] = v end
        end
    end
    m = Median(all)
    return (m and m > 0) and m or DEFAULT_SPEED
end

-- Everything known about flying from here to `slot` while the flight map
-- is open: nil for here, or an unknown slot.
--   secs, est    the time, and whether it is an estimate ("~")
--   from, to     node keys; fromName, toName; stops
--   hops         { { a, b, aName, bName, d, wx, wy }, ... }
--   dist         the hops' straight length; mapKey, mapID
function FT.Plan(slot)
    local s = ReadNodes()
    local cur = s.current
    local from, to = cur and s.nodes[cur], s.nodes[slot]
    if not (from and to) or slot == cur then return nil end
    local list, count, real = Hops(s, slot)
    local st = Store()
    local p = { from = from.key, to = to.key, fromName = from.name, toName = to.name,
        stops = math_max(0, count - 1), real = real, mapKey = s.mapKey, mapID = s.mapID, hops = {} }
    -- (where the destination and the stops are in the world: only when the
    -- game places every node, for the landing check and the stop splits)
    if s.yards then p.destX, p.destY = to.wx, to.wy end
    local speed = FT.Speed(s.mapKey)
    local dist, sum, known = 0, 0, true
    for i, h in ipairs(list) do
        local a, b = s.nodes[h[1]], s.nodes[h[2]]
        local d = Dist(a, b)
        dist = dist + d
        local leg = real and a and b and (Median(st.legs[a.key .. ">" .. b.key]) or Imported(st, a.name, b.name)) or nil
        if leg then sum = sum + leg else known = false sum = sum + d / speed end
        p.hops[i] = { a = a and a.key, b = b and b.key, aName = a and a.name, bName = b and b.name,
            d = d, wx = s.yards and b and b.wx or nil, wy = s.yards and b and b.wy or nil }
    end
    p.dist = dist
    local trip = Median(st.trips[from.key .. ">" .. to.key])
    if trip then
        p.secs, p.est = trip, false
    else
        -- a direct flight flown before (or measured by the world map) is
        -- its own time; legs added up, or anything worked out, is "~"
        p.secs, p.est = sum, not (known and #list == 1 and real)
    end
    return p
end

-- seconds, est for the flight to `slot` (nil, nil for none)
function FT.TripTime(slot)
    local p = FT.Plan(slot)
    if not p then return nil, nil end
    return p.secs, p.est
end

local function Clock(sec)
    sec = math_max(0, math_floor((tonumber(sec) or 0) + 0.5))
    if sec >= 3600 then
        return string.format("%d:%02d:%02d", math_floor(sec / 3600), math_floor(sec % 3600 / 60), sec % 60)
    end
    return string.format("%d:%02d", math_floor(sec / 60), sec % 60)
end
FT.Clock = Clock

-- "1:42", or "~2:10" for an estimate
function FT.Format(secs, est)
    if not secs then return "" end
    return (est and "~" or "") .. Clock(secs)
end

-- The flight time as a line on a flight master's tooltip (Blizzard's,
-- or the one ZacUI's window shows), for a destination slot.
function FT.AddTooltipLine(tt, slot)
    tt = tt or GameTooltip
    if not (tt and slot) or FT.DB().listTimes == false then return false end
    if TaxiNodeGetType and TaxiNodeGetType(slot) ~= "REACHABLE" then return false end
    local p = FT.Plan(slot)
    if not (p and p.secs) then return false end
    local g, n = GetColor("text", "gray"), GetColor("text", "normal")
    if tt.AddDoubleLine then
        tt:AddDoubleLine("Flight time", FT.Format(p.secs, p.est), g.r, g.g, g.b, n.r, n.g, n.b)
    else
        tt:AddLine("Flight time  " .. FT.Format(p.secs, p.est), n.r, n.g, n.b)
    end
    if p.est and tt.AddLine then
        tt:AddLine("~ estimated until you have flown it", g.r, g.g, g.b)
    end
    tt:Show()
    return true
end

-- ============================================================
-- LEARNING
-- ============================================================
local function R1(v) return math_floor(v * 10 + 0.5) / 10 end

local function Learn(f, secs)
    local st = Store()
    secs = R1(secs)
    Add(st.trips, f.from .. ">" .. f.to, secs)
    local hops = f.hops or {}
    if #hops == 1 and f.real and hops[1].a and hops[1].b then
        Add(st.legs, hops[1].a .. ">" .. hops[1].b, secs)
    elseif #hops > 1 and f.real and type(f.passed) == "table" then
        -- each leg whose both ends were seen: take-off, a stop passed, landing
        for k = 1, #hops do
            local t0 = (k == 1) and 0 or f.passed[k - 1]
            local t1 = (k == #hops) and secs or f.passed[k]
            local h = hops[k]
            if t0 and t1 and t1 - t0 >= 1 and h.a and h.b then Add(st.legs, h.a .. ">" .. h.b, R1(t1 - t0)) end
        end
    end
    if (tonumber(f.dist) or 0) > 0 then
        Add(st.speed, f.mapKey or "taxi", math_floor(f.dist / secs * 100 + 0.5) / 100, KEEP_SPEED)
    end
end

-- ============================================================
-- THE COUNTDOWN BAR
-- ============================================================
local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"

-- One bar: an icon, a fill with a glowing edge, where you are going on the
-- left and the time on the right. NewBar makes one anywhere (the settings
-- preview makes its own), StyleBar dresses it from the settings, FillBar
-- draws one moment of the countdown. The live bar and the preview's go
-- through all three.
function FT.NewBar(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(240, 20)
    UI.Border(f, "ui", "border")
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    icon:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    icon:SetTexture(ICON)
    ZacUI.Look.CropIcon(icon)
    f.icon = icon
    local div = f:CreateTexture(nil, "ARTWORK", nil, 1)
    div:SetTexture(ns.FLAT)
    div:SetWidth(1)
    div:SetPoint("TOPLEFT", icon, "TOPRIGHT", 0, 0)
    div:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 0, 0)
    f.div = div
    local sb = CreateFrame("StatusBar", nil, f)
    sb:SetPoint("TOPLEFT", div, "TOPRIGHT", 0, 0)
    sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(1)
    f.sb = sb
    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg._zui_own = true
    bg:SetAllPoints()
    bg:SetTexture(ns.FLAT)
    f.bg = bg
    -- above the fill: the spark at its edge and the texts
    local over = CreateFrame("Frame", nil, f)
    over:SetAllPoints(sb)
    over:SetFrameLevel(sb:GetFrameLevel() + 2)
    f.over = over
    local spark = over:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(SPARK)
    spark:SetBlendMode("ADD")
    f.spark = spark
    f.label = over:CreateFontString(nil, "OVERLAY")
    f.label:SetPoint("LEFT", sb, "LEFT", 6, 0)
    f.label:SetJustifyH("LEFT")
    f.time = over:CreateFontString(nil, "OVERLAY")
    f.time:SetPoint("RIGHT", sb, "RIGHT", -6, 0)
    f.time:SetJustifyH("RIGHT")
    f.label:SetPoint("RIGHT", f.time, "LEFT", -6, 0)
    f.label:SetWordWrap(false)
    if ns.TagElement then ns.TagElement(f.label, "flight.label") ns.TagElement(f.time, "flight.time") end
    f._zPaint = function(self) FT.PaintBar(self, FT.DB()) end
    f:Hide()
    return f
end

local function Col(c, fallback)
    if type(c) == "table" and ns.ColorOf then return ns.ColorOf(c) end
    return fallback.r, fallback.g, fallback.b, fallback.a or 1
end

function FT.PaintBar(b, d)
    UI.PaintBox(b)
    local r, g, bl = Col(d.fillColor, GetColor("ui", "accent"))
    b.sb:SetStatusBarColor(r, g, bl, 1)
    if type(d.bgColor) == "table" then
        b.bg:SetVertexColor(Col(d.bgColor, GetColor("ui", "windowBg")))
    else
        -- the empty part of the track: dark, with a hint of the fill
        local w = GetColor("ui", "windowBg")
        b.bg:SetVertexColor(w.r * 0.45 + r * 0.12, w.g * 0.45 + g * 0.12, w.b * 0.45 + bl * 0.12, 0.9)
    end
    local bd = GetColor("ui", "border")
    b.div:SetVertexColor(bd.r, bd.g, bd.b, 1)
    local tr, tg, tb = Col(d.textColor, GetColor("text", "normal"))
    b.label:SetTextColor(tr, tg, tb, 1)
    b.time:SetTextColor(tr, tg, tb, 1)
end

FT.LabelSize = function(d) return math_max(8, math_floor((tonumber(d.height) or 20) * 0.55)) end
FT.TimeSize = function(d) return math_max(8, math_floor((tonumber(d.height) or 20) * 0.6)) end

local function BarFont(fs, spec, autoSize)
    if type(spec) == "table" and next(spec) and ns.ApplyFontSpec then
        ns.ApplyFontSpec(fs, spec, { size = autoSize, outline = "outline" })
    elseif ns.HouseFont then
        ns.HouseFont(fs, autoSize, "OUTLINE", STANDARD_TEXT_FONT)
    end
end

-- WHERE THE TEXTS SIT (windows.flight.anchors.<label|time>, ZacUI's anchor
-- shape): the label from the left edge to the time, the time at the right
-- edge, with a saved anchor on top. Nothing saved = never touched.
FT.ANCHOR_LABELS = { bar = "The bar", fill = "The fill", icon = "The icon", label = "Destination", time = "Time left" }
function FT.AnchorDefaults(key)
    if key == "time" then return { point = "RIGHT", relPoint = "RIGHT", x = -6, y = 0, justify = "RIGHT" } end
    return { point = "LEFT", relPoint = "LEFT", x = 6, y = 0, justify = "LEFT" }
end
local function PlaceTexts(b, d)
    local a = type(d.anchors) == "table" and d.anchors or nil
    if not (a or b._zMoved) then return end
    b._zMoved = a and true or nil
    if not b._zAnchorTo then
        b._zAnchorTo = function(k)
            if k == "bar" then return b elseif k == "fill" then return b.sb elseif k == "icon" then return b.icon
            elseif k == "label" then return b.label elseif k == "time" then return b.time end
        end
        b._zDefs = { time = {}, label = {} }
    end
    local t = b._zDefs.time
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = "RIGHT", b.sb, "RIGHT", -6, 0, "RIGHT"
    ns.ApplyAnchor(b.time, a and a.time, t, b._zAnchorTo)
    t = b._zDefs.label
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = "LEFT", b.sb, "LEFT", 6, 0, "LEFT"
    t.point2, t.to2, t.relPoint2, t.x2, t.y2 = "RIGHT", b.time, "LEFT", -6, 0
    local _, two = ns.ApplyAnchor(b.label, a and a.label, t, b._zAnchorTo)
    if not two then b.label:SetWidth(math_max(20, (tonumber(d.width) or 240) * 0.6)) end
end

-- the time as text: m:ss, or the saved format (windows.flight.formats.time)
FT.TIME_DEFAULTS = { time = "mmss" }
function FT.TimeText(left, est, d)
    local spec = d and type(d.formats) == "table" and d.formats.time
    local txt
    if spec and ns.FormatTime then txt = ns.FormatTime(math_max(0, left), spec, FT.TIME_DEFAULTS)
    else txt = Clock(math.ceil(math_max(0, left))) end
    return (est and "~" or "") .. txt
end

-- size, texture, fonts, the optional pieces, and bar or text only
function FT.StyleBar(b, d)
    local textOnly = d.style == "text"
    local tex = (ns.ResolveBarTexture and ns.ResolveBarTexture(d.texture)) or ns.FLAT
    b.sb:SetStatusBarTexture(tex)
    local ft = b.sb.GetStatusBarTexture and b.sb:GetStatusBarTexture()
    if ft and type(ft) == "table" and ft ~= b._zFT and ft.GetObjectType then
        b._zFT = ft
        b.spark:ClearAllPoints()
        b.spark:SetPoint("CENTER", ft, "RIGHT", 0, 0)
    end
    local w, h = tonumber(d.width) or 240, tonumber(d.height) or 20
    b:SetSize(w, h)
    local iconOn = d.icon ~= false and not textOnly
    b.icon:SetShown(iconOn)
    b.div:SetShown(iconOn)
    b.icon:SetWidth(iconOn and h or 0.001)
    b.div:SetWidth(iconOn and 1 or 0.001)
    b.sb:SetShown(not textOnly)
    for _, strip in ipairs(b._zBorder or {}) do strip:SetShown(not textOnly) end
    b.spark:SetSize(math_max(8, h * 0.55), h * 1.8)
    b._zNoSpark = d.spark == false or textOnly
    if b._zNoSpark then b.spark:Hide() end
    BarFont(b.label, d.labelFont, FT.LabelSize(d))
    BarFont(b.time, d.timeFont, FT.TimeSize(d))
    if ns.ApplyAnchor then PlaceTexts(b, d) end
    FT.PaintBar(b, d)
    if textOnly then for _, strip in ipairs(b._zBorder or {}) do strip:Hide() end end
    b._zTxt = nil
end

-- one moment: `left` seconds of `total`, `est` = "~"
function FT.FillBar(b, left, total, est, d)
    local v = (total and total > 0) and math_min(1, math_max(0, left / total)) or 0
    b.sb:SetValue(v)
    b.spark:SetShown(not b._zNoSpark and v > 0.004 and v < 0.996)
    local txt = FT.TimeText(left, est, d)
    if b._zTxt ~= txt then b._zTxt = txt b.time:SetText(txt) end
end

local holder, bar
local function Holder()
    if holder then return holder end
    holder = CreateFrame("Frame", "ZacUIFlightTimer", UIParent)
    holder:SetSize(240, 20)
    holder:SetFrameStrata("MEDIUM")
    holder:SetClampedToScreen(true)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -120)
    bar = FT.NewBar(holder)
    bar:SetPoint("CENTER", holder, "CENTER", 0, 0)
    if ns.RegisterMover then
        ns.RegisterMover("flighttimer", "Flight timer", function() return holder end, "TOP", 0, -120)
        if ns.ApplyMover then ns.ApplyMover("flighttimer") end
    end
    return holder
end
FT.Holder = Holder
function FT.Bar() Holder() return bar end

local shownFor            -- what the live bar is showing: the flight, or the test
local function ShowBar(what, name)
    local d = FT.DB()
    if not d.enabled then return end
    Holder()
    FT.StyleBar(bar, d)
    holder:SetSize(bar:GetWidth(), bar:GetHeight())
    bar.label:SetText(Place(name))
    shownFor = what
    bar._zOut = nil
    if ns.Motion then
        ns.Motion.Stop(bar)
        bar:Hide()
        ns.Motion.Show(bar, d.showAnim)
    else
        bar:Show()
    end
end

local function HideBar(what)
    if not bar or (what and shownFor ~= what) then return end
    shownFor = nil
    if not bar:IsShown() or bar._zOut then return end
    bar._zOut = true
    local function Gone() bar._zOut = nil end
    if ns.Motion then ns.Motion.Hide(bar, FT.DB().hideAnim, Gone) else bar:Hide() Gone() end
    if not bar:IsShown() then Gone() end
end

function FT.Restyle()
    if holder and bar and not bar:IsShown() then
        local d = FT.DB()
        holder:SetSize(tonumber(d.width) or 240, tonumber(d.height) or 20)
    end
    if bar and bar:IsShown() and not bar._zOut then
        local d = FT.DB()
        if not d.enabled then HideBar() return end
        FT.StyleBar(bar, d)
        holder:SetSize(bar:GetWidth(), bar:GetHeight())
    end
end

-- ============================================================
-- THE FLIGHT: TAKE-OFF, IN THE AIR, LANDING
-- ============================================================
local pending, flight, test
local ticker

local function SaveFlight()
    if type(ZacUICharDB) ~= "table" then return end
    ZacUICharDB.flightNow = flight
end

local function Say(words)
    if ns.PlaySoundRef then
        ns.PlaySoundRef("tts:" .. words)
    elseif ns.Speak then
        pcall(ns.Speak, words, true)
    end
end

-- landed where it was going? (true when the game will not say)
local function AtDestination(f)
    if not (f.destX and f.mapID) then return true end
    local px, py = PlayerWorld(f.mapID)
    if not px then return true end
    local dx, dy = px - f.destX, py - f.destY
    return math_sqrt(dx * dx + dy * dy) <= LANDED_NEAR
end

-- a trip with stops: the moment you pass over each stop's flight master
-- splits it into legs (only where the game places you and the nodes)
local function WatchStops(f, elapsed)
    local k = f.nextStop
    local h = k and f.hops[k]
    if not (h and h.wx) or elapsed < MIN_SECS then return end
    local px, py = PlayerWorld(f.mapID)
    if not px then return end
    local dx, dy = px - h.wx, py - h.wy
    local dist = math_sqrt(dx * dx + dy * dy)
    if dist <= PASS_NEAR then
        if not f.nearD or dist < f.nearD then f.nearD, f.nearT = dist, elapsed end
    elseif f.nearD then
        f.passed[k] = R1(f.nearT)
        f.nearD, f.nearT = nil, nil
        f.nextStop = (k < #f.hops - 1) and k + 1 or nil
    end
end

local StopTicker

local function Begin(plan, startedAgo)
    flight = plan
    flight.start = GetTime() - (startedAgo or 0)
    flight.startServer = (GetServerTime and GetServerTime() or 0) - math_floor(startedAgo or 0)
    if flight.learn == nil then flight.learn = true end
    flight.passed = flight.passed or {}
    if #flight.hops > 1 and flight.real and flight.nextStop == nil and not next(flight.passed) then
        flight.nextStop = 1
    end
    SaveFlight()
    if test then test = nil end
    ShowBar("flight", flight.toName)
end

local function Land()
    local f = flight
    flight = nil
    if type(ZacUICharDB) == "table" then ZacUICharDB.flightNow = nil end
    HideBar("flight")
    if not (f and f.learn) then return false end
    local secs = GetTime() - (f.start or GetTime())
    if secs < MIN_SECS then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
    if not f.est and f.secs and secs < f.secs * SHORT then return false end
    if not AtDestination(f) then return false end
    Learn(f, secs)
    return true
end
FT._Land = Land

local function Tick()
    if not Live() then StopTicker() return end
    local now = GetTime()
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    if pending and not flight then
        if onTaxi then
            local p = pending
            pending = nil
            Begin(p)
        elseif now - (pending.asked or now) > TAKEOFF_WAIT then
            pending = nil              -- never took off
        end
    end
    if flight then
        if not onTaxi then
            Land()
        else
            local elapsed = now - flight.start
            local left = (flight.secs or 0) - elapsed
            if bar and shownFor == "flight" and bar:IsShown() and not bar._zOut then
                FT.FillBar(bar, left, flight.secs, flight.est, FT.DB())
            end
            if flight.learn and flight.nextStop then WatchStops(flight, elapsed) end
            if not flight.spoke and left <= WARN_AT and left > WARN_AT - 1.5 and (flight.secs or 0) > WARN_AT + 2 then
                flight.spoke = true
                if FT.DB().voice then Say("Landing in " .. WARN_AT .. " seconds") end
            end
        end
    end
    if test and not flight then
        local left = test.secs - (now - test.start)
        if left <= 0 then
            test = nil
            HideBar("test")
        elseif bar and shownFor == "test" and bar:IsShown() and not bar._zOut then
            FT.FillBar(bar, left, test.secs, test.est, FT.DB())
        end
    end
    if not (pending or flight or test) then StopTicker() end
end

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK, Tick)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "windows.flighttimer") end
end
StopTicker = function()
    if ticker then ticker:Cancel() ticker = nil end
end
FT.Running = function() return ticker ~= nil end

-- the click on a destination (Blizzard's map, ZacUI's list or anything
-- else that calls TakeTaxiNode): what is about to be flown
local function OnTakeTaxi(slot)
    if not Live() then return end
    local ok, p = pcall(FT.Plan, slot)
    if not (ok and p) then return end
    p.asked = GetTime()
    pending = p
    StartTicker()
end

-- A sample flight on the live bar, to see it and place it (Position tab).
function FT.Test(secs)
    if flight then return end
    test = { secs = secs or 20, start = GetTime(), est = false }
    ShowBar("test", "Ironforge, Dun Morogh")
    if bar and shownFor == "test" then FT.FillBar(bar, test.secs, test.secs, false, FT.DB()) end
    StartTicker()
end

-- for the tests and the settings page
function FT.Current() return flight, pending end
function FT.Forget()
    if type(ZacUIDB) == "table" and type(ZacUIDB.flightTimes) == "table" then
        local g = Game()
        local s = ZacUIDB.flightTimes[g]
        if type(s) == "table" then
            -- the world map's times stay copied: they are not this page's to drop
            ZacUIDB.flightTimes[g] = { imported = s.imported, importedWorldMap = s.importedWorldMap }
        end
    end
end
function FT.Counts()
    local st = (type(ZacUIDB) == "table" and type(ZacUIDB.flightTimes) == "table" and ZacUIDB.flightTimes[Game()]) or {}
    local n = { trips = 0, legs = 0, imported = 0 }
    for _ in pairs(type(st.trips) == "table" and st.trips or {}) do n.trips = n.trips + 1 end
    for _ in pairs(type(st.legs) == "table" and st.legs or {}) do n.legs = n.legs + 1 end
    for _ in pairs(type(st.imported) == "table" and st.imported or {}) do n.imported = n.imported + 1 end
    return n
end

-- ============================================================
-- WIRING
-- ============================================================
local function HookFlightMap()
    -- the newer flight map (Blizzard_FlightMap): its points' tooltips
    local mix = rawget(_G, "FlightMap_FlightPointPinMixin")
    if type(mix) ~= "table" or FT._mapHooked or type(mix.OnMouseEnter) ~= "function" then return end
    FT._mapHooked = true
    hooksecurefunc(mix, "OnMouseEnter", function(pin)
        local data = pin and pin.taxiNodeData
        if Live() and type(data) == "table" and data.slotIndex then pcall(FT.AddTooltipLine, GameTooltip, data.slotIndex) end
    end)
end

local function Init()
    if FT._init then return end
    FT._init = true
    if ns.FeatureOn and not ns.FeatureOn("flight_times") then return end

    if type(TakeTaxiNode) == "function" then hooksecurefunc("TakeTaxiNode", OnTakeTaxi) end
    -- left early: the flight teaches nothing
    if type(TaxiRequestEarlyLanding) == "function" then
        hooksecurefunc("TaxiRequestEarlyLanding", function()
            if Live() and flight then flight.learn = false SaveFlight() end
        end)
    end
    -- Blizzard's flight map: the time on each destination's tooltip (ZacUI's
    -- window shows the same tooltip on its rows)
    if type(TaxiNodeOnButtonEnter) == "function" then
        hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
            local slot = button and button.GetID and button:GetID()
            if slot and Live() then pcall(FT.AddTooltipLine, GameTooltip, slot) end
        end)
    end
    HookFlightMap()

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_DEAD")
    ev:RegisterEvent("ADDON_LOADED")
    ev:SetScript("OnEvent", function(_, event, a1, a2)
        if not Live() then return end
        if event == "ADDON_LOADED" then
            if a1 == "Blizzard_FlightMap" then HookFlightMap() end
        elseif event == "PLAYER_DEAD" then
            if flight then flight.learn = false SaveFlight() end
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- still in the air after a /reload: the countdown carries on
            -- (and still learns); after a login it carries on but learns
            -- nothing (the time offline is not the flight's)
            local saved = type(ZacUICharDB) == "table" and ZacUICharDB.flightNow
            if flight or type(saved) ~= "table" then return end
            if UnitOnTaxi and UnitOnTaxi("player") and saved.startServer and saved.secs then
                local ago = math_max(0, (GetServerTime and GetServerTime() or 0) - saved.startServer)
                if a2 ~= true then saved.learn = false end
                Begin(saved, ago)
                StartTicker()
            else
                ZacUICharDB.flightNow = nil
            end
        end
    end)

    Holder()
    FT.ImportWorldMap()
    if ns.OnSettingsChanged then
        local soon = ns.Coalesce and ns.Coalesce(FT.Restyle) or FT.Restyle
        ns.OnSettingsChanged(function() soon() end)
    end
end
FT.Init = Init

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        Init()
    end)
    if IsLoggedIn and IsLoggedIn() then Init() end
end
