-- Win_Taxi - ZacUI's flight master window.
-- Part of ZacUI; load order is set by the TOC.
--
-- A cover over TaxiFrame, like the merchant or the trade window, with the
-- flight map on the left and every place you can fly to on the right.
--
-- THE MAP IS BLIZZARD'S, MOVED IN. The map picture (TaxiMap, a texture on
-- TaxiFrame) and the frame the flight points and route lines live on
-- (TaxiRouteMap) are re-parented into the window and drawn a size larger.
-- Blizzard's own code keeps placing the points and drawing the routes
-- exactly as before - it places them by name, relative to TaxiMap and
-- TaxiRouteMap - so every point, hover, tooltip and route is still the
-- game's own. Turning the window off puts both back where they came from.
--
--   Destination list   every flight point you can reach from here, with
--                      its zone, the cost, how many stops and how long
--                      it takes (Win_FlightTimes: "1:42" flown before,
--                      "~2:10" estimated). Hover to see the route on the
--                      map, click to fly.
--   Search             by place or zone
--   Cheapest first     sort by cost instead of by name
--   Quickest first     sort by flight time
--   Map                hovering a point lights its row in the list

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local UI = ns.UI

local M, F = UI.M, UI.F

-- Blizzard's geometry (Classic TaxiFrame.xml / TaxiFrame.lua).
local MAP_W  = _G.TAXI_MAP_WIDTH or 316
local MAP_H  = _G.TAXI_MAP_HEIGHT or 352
local SCALE  = 1.2
local LIST_W = 250
local ROW_H  = 36
-- Where the window's corner sits on TaxiFrame. The flight map's panel slot
-- is shifted (-16, +12) against every other left-side window, to make up
-- for its art; this puts the window where the character window would be.
local OFF_X, OFF_Y = 27, -24

local win, mapBox, list, search, cheapChip, quickChip, fromText, moneyText, emptyNote
local ring
local items, query, hovered = {}, "", nil
local moved = false

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.taxiwin ~= false
end

-- the flight times (Win_FlightTimes), when that file is there and they are on
local function Times()
    local FT = ns.FlightTimes
    if FT and FT.DB().listTimes ~= false then return FT end
    return nil
end

local function Str(name, fallback)
    local v = _G[name]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

-- "Ironforge, Dun Morogh" -> "Ironforge", "Dun Morogh"
local function Split(full)
    local place, zone = tostring(full or ""):match("^(.-),%s*(.+)$")
    if place and place ~= "" then return place, zone end
    return tostring(full or "?"), ""
end

-- ============================================================
-- THE MAP: MOVE BLIZZARD'S IN, AND BACK OUT
-- ============================================================
local function MoveMapIn()
    if moved or not (TaxiMap and TaxiRouteMap and mapBox) then return end
    moved = true
    TaxiMap:SetParent(mapBox)
    TaxiMap:SetDrawLayer("ARTWORK")
    TaxiMap:ClearAllPoints()
    TaxiMap:SetPoint("TOPLEFT", mapBox, "TOPLEFT", 1, -1)
    TaxiMap:SetSize(MAP_W * SCALE, MAP_H * SCALE)
    TaxiRouteMap:SetParent(mapBox)
    TaxiRouteMap:SetScale(SCALE)
    TaxiRouteMap:ClearAllPoints()
    TaxiRouteMap:SetPoint("BOTTOMLEFT", TaxiMap, "BOTTOMLEFT", 0, 0)
    TaxiRouteMap:SetFrameLevel(mapBox:GetFrameLevel() + 2)
end

local function MoveMapOut()
    if not moved or not (TaxiMap and TaxiRouteMap and TaxiFrame) then return end
    moved = false
    TaxiMap:SetParent(TaxiFrame)
    TaxiMap:SetDrawLayer("OVERLAY")
    TaxiMap:ClearAllPoints()
    TaxiMap:SetPoint("TOP", TaxiFrame, "TOP", -13, -75)
    TaxiMap:SetSize(MAP_W, MAP_H)
    TaxiRouteMap:SetParent(TaxiFrame)
    TaxiRouteMap:SetScale(1)
    TaxiRouteMap:ClearAllPoints()
    TaxiRouteMap:SetPoint("TOP", TaxiFrame, "TOP", -13, -75)
end

-- The flight points are created lazily by Blizzard, one per node, the
-- first time a map with that many nodes opens. Keep every one above the
-- map picture.
--
-- AND ON THE SAME SCALE AS THE ROUTES. Blizzard places each point with an
-- offset in map pixels (0..316 across), and the routes are drawn the same
-- way on TaxiRouteMap, which is enlarged here. But the points are NOT
-- TaxiRouteMap's children: the button template names TaxiFrame as their
-- parent, so they stayed at normal size and every offset landed at 1/1.2
-- of the distance - points pulled toward the bottom-left, off the ends of
-- their route lines and out into the sea. Each point is moved onto
-- TaxiRouteMap and anchored to its corner (the picture's corner) with the
-- same offset, so it scales exactly as its lines do. Blizzard sets the
-- anchor again each time the map opens, so this runs every open.
local fix = 1   -- measured correction on top of Blizzard's offsets

local function Place(b)
    local base = b._zTaxiBase
    b:ClearAllPoints()
    b:SetPoint(base[1], TaxiRouteMap, base[2], base[3] * fix, base[4] * fix)
end

-- Checked on screen, not assumed: where one point actually is, against
-- where the map says it should be (its offset in map pixels, times the
-- size the picture is drawn at). Any difference - however the client
-- composes scales - is taken out of every point.
local function Calibrate()
    local mapL, mapB = TaxiMap:GetLeft(), TaxiMap:GetBottom()
    if not (mapL and mapB) then return end
    local mEff = mapBox:GetEffectiveScale()
    local perPx = (TaxiMap:GetWidth() * mEff) / MAP_W
    for i = 1, (_G.NUM_TAXI_BUTTONS or 0) do
        local b = _G["TaxiButton" .. i]
        local base = b and b._zTaxiBase
        if base and b:IsShown() and math.abs(base[3]) + math.abs(base[4]) > 40 then
            local cx, cy = b:GetCenter()
            if cx and cy then
                local bEff = b:GetEffectiveScale()
                local ax, ay = cx * bEff - mapL * mEff, cy * bEff - mapB * mEff
                local dx, dy = base[3] * perPx, base[4] * perPx
                local actual = math.sqrt(ax * ax + ay * ay)
                local wanted = math.sqrt(dx * dx + dy * dy)
                if actual > 1 and math.abs(actual - wanted) > 1 then
                    fix = fix * wanted / actual
                    for j = 1, (_G.NUM_TAXI_BUTTONS or 0) do
                        local o = _G["TaxiButton" .. j]
                        if o and o._zTaxiBase then Place(o) end
                    end
                end
                return
            end
        end
    end
end

local function FixButtons()
    if not (moved and TaxiRouteMap) then return end
    local lvl = TaxiRouteMap:GetFrameLevel() + 1
    for i = 1, (_G.NUM_TAXI_BUTTONS or 0) do
        local b = _G["TaxiButton" .. i]
        if b then
            if b:GetParent() ~= TaxiRouteMap then b:SetParent(TaxiRouteMap) end
            local point, rel, relPoint, x, y = b:GetPoint(1)
            -- Anchored anywhere but our frame means Blizzard has just placed
            -- it (every open): its offset is the fresh map position.
            if point and rel ~= TaxiRouteMap then
                b._zTaxiBase = { point, relPoint or "BOTTOMLEFT", x or 0, y or 0 }
            end
            if b._zTaxiBase then Place(b) end
            if b:GetFrameLevel() < lvl then b:SetFrameLevel(lvl) end
        end
    end
    if ring then ring:SetFrameLevel(lvl + 2) end
    Calibrate()
end
local LiftButtons = FixButtons

local function Ring(index)
    if not ring then return end
    local b = index and _G["TaxiButton" .. index]
    if b and b:IsShown() then
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", b, "CENTER", 0, 0)
        ring:Show()
    else
        ring:Hide()
    end
end

-- ============================================================
-- DATA
-- ============================================================
local function Collect()
    local out, current = {}, nil
    local n = NumTaxiNodes and NumTaxiNodes() or 0
    local FT = Times()
    for i = 1, n do
        local kind = TaxiNodeGetType(i)
        if kind == "REACHABLE" or kind == "CURRENT" then
            local full = TaxiNodeName(i)
            local place, zone = Split(full)
            if kind == "CURRENT" then
                current = { index = i, name = place, zone = zone }
            else
                local hops = GetNumRoutes and GetNumRoutes(i) or 1
                out[#out + 1] = {
                    index = i, name = place, zone = zone, full = full,
                    cost = TaxiNodeCost(i) or 0,
                    hops = hops or 1,
                    direct = TaxiIsDirectFlight and TaxiIsDirectFlight(i) or (hops or 1) <= 1,
                }
                if FT then
                    local ok, secs, est = pcall(FT.TripTime, i)
                    if ok and secs then out[#out].secs, out[#out].est = secs, est end
                end
            end
        end
    end
    return out, current
end

local function Sorted()
    local q = query
    local cheap = cheapChip and cheapChip:IsOn()
    local quick = quickChip and quickChip:IsOn()
    local t = {}
    for _, it in ipairs(items) do
        if Kit.Matches(q, it.name, it.zone) then t[#t + 1] = it end
    end
    table.sort(t, function(a, b)
        if quick and (a.secs or math.huge) ~= (b.secs or math.huge) then
            return (a.secs or math.huge) < (b.secs or math.huge)
        end
        if cheap and a.cost ~= b.cost then return a.cost < b.cost end
        if a.name ~= b.name then return a.name < b.name end
        return a.index < b.index
    end)
    return t
end

local function Refresh()
    if not win or not TaxiFrame:IsShown() then return end
    -- the times on or off, the list's sort as it was saved
    if quickChip then
        local FT = Times()
        quickChip:SetShown(FT ~= nil)
        local want = FT and FT.DB().sortTime == true or false
        if quickChip:IsOn() ~= want then quickChip:SetOn(want) end
        if want and cheapChip:IsOn() then cheapChip:SetOn(false) end
    end
    local current
    items, current = Collect()
    local shown = Sorted()
    list:SetData(shown, true)
    local sel
    if hovered then
        for _, it in ipairs(shown) do
            if it.index == hovered then sel = it end
        end
    end
    list.selected = sel
    list:Refresh()
    if #items == 0 then
        list:SetEmptyText(Str("ERR_TAXINOPATHS", "You don't know any flight locations connected to this one."))
    else
        list:SetEmptyText("No destination matches the search.")
    end
    local npc = UnitName("npc")
    win:SetTitle((Str("FLIGHT_MAP", "Flight Map")) .. ((npc and npc ~= "") and ("  -  " .. npc) or ""))
    if current then
        local green, gray = ns.Hex(GetColor("text", "green")), ns.Hex(GetColor("text", "gray"))
        fromText:SetText("|cff" .. green .. current.name .. "|r"
            .. (current.zone ~= "" and ("  |cff" .. gray .. current.zone .. "|r") or ""))
    else
        fromText:SetText("")
    end
    moneyText:SetText(ns.Money(GetMoney()))
    LiftButtons()
end

local Queue = Kit.Coalesce(Refresh, function() return win end)

-- ============================================================
-- ROWS
-- ============================================================
local function BuildRow(row)
    row.name = UI.Font(row, F.CARD, { justify = "LEFT" })
    row.name:SetPoint("TOPLEFT", 8, -4)
    row.name:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    row.name:SetWordWrap(false)
    row.zone = UI.Font(row, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    row.zone:SetPoint("BOTTOMLEFT", 8, 5)
    row.zone:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    row.zone:SetWordWrap(false)
    row.cost = UI.Font(row, F.LABEL, { justify = "RIGHT" })
    row.cost:SetPoint("TOPRIGHT", -8, -5)
    row.stops = UI.Font(row, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    row.stops:SetPoint("BOTTOMRIGHT", -8, 5)
    -- the flight time, under the cost; the stops move to its left
    row.time = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.time:SetPoint("BOTTOMRIGHT", -8, 5)
    row.time:Hide()
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function(self)
        if self.item and TakeTaxiNode then TakeTaxiNode(self.item.index) end
    end)
    row:SetScript("OnEnter", function(self)
        local it = self.item
        if not it then return end
        local b = _G["TaxiButton" .. it.index]
        -- Blizzard's own hover: the route on the map and the tooltip at
        -- the flight point.
        if b and b:IsShown() and TaxiNodeOnButtonEnter then
            TaxiNodeOnButtonEnter(b)
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(it.full or it.name)
            if GameTooltip_AddMoneyLine then GameTooltip_AddMoneyLine(GameTooltip, it.cost) end
            if Times() then pcall(ns.FlightTimes.AddTooltipLine, GameTooltip, it.index) end
            GameTooltip:Show()
        end
        Ring(it.index)
    end)
    row:SetScript("OnLeave", function(self)
        local it = self.item
        local b = it and _G["TaxiButton" .. it.index]
        if b and TaxiNodeOnButtonLeave then TaxiNodeOnButtonLeave(b) end
        GameTooltip:Hide()
        Ring(nil)
        -- Back to Blizzard's resting view: the direct routes from here.
        if DrawOneHopLines and TaxiFrame:IsShown() then DrawOneHopLines() end
    end)
end

local function UpdateRow(row, it)
    row.name:SetText(it.name)
    row.zone:SetText(it.zone)
    local afford = (GetMoney() or 0) >= (it.cost or 0)
    row.cost:SetText(ns.Money(it.cost))
    if afford then row.cost:_zPaint() else
        local r = GetColor("text", "red")
        row.cost:SetTextColor(r.r, r.g, r.b, 1)
    end
    local stops = math.max(0, (it.hops or 1) - 1)
    row.stops:ClearAllPoints()
    if it.secs then
        row.time:SetText(ns.FlightTimes.Format(it.secs, it.est))
        if it.est then
            local g = GetColor("text", "gray")
            row.time:SetTextColor(g.r, g.g, g.b, 1)
        else
            row.time:_zPaint()
        end
        row.time:Show()
        row.stops:SetPoint("BOTTOMRIGHT", row.time, "BOTTOMLEFT", -6, 0)
    else
        row.time:Hide()
        row.stops:SetPoint("BOTTOMRIGHT", -8, 5)
    end
    if it.direct or stops == 0 then
        row.stops:SetText("Direct")
    elseif stops == 1 then
        row.stops:SetText("1 stop")
    else
        row.stops:SetText(stops .. " stops")
    end
end

-- ============================================================
-- BUILD
-- ============================================================
local function Build()
    if win then return end
    local mapW, mapH = math.floor(MAP_W * SCALE + 0.5) + 2, math.floor(MAP_H * SCALE + 0.5) + 2
    local width = Kit.PAD + mapW + Kit.PAD + LIST_W + Kit.PAD
    local height = M.TITLEBAR + Kit.PAD + mapH + Kit.PAD + Kit.FOOTER_H + 1
    win = Kit.Cover(TaxiFrame, {
        name = "ZacUITaxiWindow",
        title = Str("FLIGHT_MAP", "Flight Map"),
        width = width, height = height,
    })
    local function Place()
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", TaxiFrame, "TOPLEFT", OFF_X, OFF_Y)
        win:SetSize(width, height)
    end
    Place()
    win.Reanchor = Place

    mapBox = CreateFrame("Frame", nil, win)
    mapBox:SetSize(mapW, mapH)
    mapBox:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, win.top)
    UI.Fill(mapBox, "ui", "elementBg")
    UI.Border(mapBox, "ui", "border")
    mapBox._zPaint = UI.PaintBox
    mapBox:_zPaint()

    -- The hover marker on the map: Blizzard's own flight-point glow.
    ring = CreateFrame("Frame", nil, mapBox)
    ring:SetSize(30, 30)
    local rt = ring:CreateTexture(nil, "OVERLAY")
    rt._zui_own = true
    rt:SetAllPoints()
    rt:SetTexture("Interface\\TaxiFrame\\UI-Taxi-Icon-Highlight")
    rt:SetBlendMode("ADD")
    ring:Hide()

    local right = CreateFrame("Frame", nil, win)
    right:SetPoint("TOPLEFT", mapBox, "TOPRIGHT", Kit.PAD, 0)
    right:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -Kit.PAD, Kit.FOOTER_H + Kit.PAD)

    -- the two sorts take turns: cost, or flight time (remembered)
    local FT = ns.FlightTimes
    cheapChip = Kit.Chip(right, "Cheapest", false, function(on)
        if on and quickChip then
            quickChip:SetOn(false)
            if FT then FT.DB().sortTime = false end
        end
        Queue()
    end, "Sort by cost instead of by name.")
    cheapChip:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, 0)
    local chipsW = cheapChip:GetWidth()
    if FT then
        quickChip = Kit.Chip(right, "Quickest", FT.DB().sortTime == true, function(on)
            if on then cheapChip:SetOn(false) end
            FT.DB().sortTime = on and true or false
            Queue()
        end, "Sort by flight time: the shortest flights first.")
        quickChip:SetPoint("RIGHT", cheapChip, "LEFT", -4, 0)
        chipsW = chipsW + 4 + quickChip:GetWidth()
    end
    search = Kit.Search(right, LIST_W - chipsW - Kit.GAP, function(text)
        query = Kit.NormalizeQuery(text)
        Queue()
    end, "Search destinations")
    search:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)

    local box = CreateFrame("Frame", nil, right)
    box:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -(Kit.SEARCH_H + Kit.GAP))
    box:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
    UI.Fill(box, "ui", "elementBg", 0.35)
    UI.Border(box, "ui", "border")
    box._zPaint = UI.PaintBox
    box:_zPaint()

    list = Kit.List(box, {
        rowHeight = ROW_H,
        build = BuildRow,
        update = UpdateRow,
        empty = "",
        fallbackRows = 10,
    })
    list:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
    list:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)

    local foot = Kit.Footer(win)
    local fromLabel = UI.Font(foot, F.SMALL, { cat = "text", key = "gray", text = "You are at" })
    fromLabel:SetPoint("LEFT", foot, "LEFT", Kit.PAD + 2, 0)
    fromText = UI.Font(foot, F.LABEL, { justify = "LEFT" })
    fromText:SetPoint("LEFT", fromLabel, "RIGHT", 6, 0)
    fromText:SetPoint("RIGHT", foot, "RIGHT", -150, 0)
    fromText:SetWordWrap(false)
    moneyText = UI.Font(foot, F.LABEL, { justify = "RIGHT" })
    moneyText:SetPoint("RIGHT", foot, "RIGHT", -Kit.PAD - 2, 0)

    win:HookScript("OnShow", Queue)
end

-- ============================================================
-- LEFTOVERS
-- ============================================================
-- TaxiFrame's own pieces that would poke out past the window's corner:
-- the NPC portrait, the name above the map and the close button.
local function Leftovers()
    local t = {}
    for _, x in ipairs({ _G.TaxiPortrait, _G.TaxiMerchant, _G.TaxiCloseButton }) do
        if x then t[#t + 1] = x end
    end
    return t
end

local function Apply()
    if not TaxiFrame then return end
    if Enabled() then
        Build()
        win.Reanchor()
        MoveMapIn()
        FixButtons()
        win:Show()
        Kit.Silence(Leftovers())
        Queue()
    elseif win then
        win:Hide()
        MoveMapOut()
        Kit.Unsilence(Leftovers())
    end
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.taxiwin = function()
    if not (TaxiFrame and TaxiMap and TaxiRouteMap) or ns._zTaxiWin then return end
    ns._zTaxiWin = true

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_MONEY")
    ev:SetScript("OnEvent", function()
        if win and win:IsVisible() then Queue() end
    end)

    -- A flight point hovered on the map lights its row.
    if type(TaxiNodeOnButtonEnter) == "function" then
        hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
            if not (win and win:IsVisible()) then return end
            hovered = button and button.GetID and button:GetID() or nil
            Queue()
        end)
    end
    if type(TaxiNodeOnButtonLeave) == "function" then
        hooksecurefunc("TaxiNodeOnButtonLeave", function()
            if not (win and win:IsVisible()) then return end
            hovered = nil
            Queue()
        end)
    end

    -- Blizzard's OnShow places the points and draws the routes; ours runs
    -- straight after it. The /zui toggle is read on every open.
    TaxiFrame:HookScript("OnShow", Apply)
    TaxiFrame:HookScript("OnHide", function()
        hovered = nil
        if ring then ring:Hide() end
    end)
    Apply()
end
