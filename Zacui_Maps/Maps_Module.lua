-- Maps_Module - the one entry point that turns the map layer on, and the
-- diagnostic that says what it actually did.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHY THE DIAGNOSTIC EXISTS AT ALL. The map layer touches five separate
-- Blizzard systems - the panel manager, the canvas, three pin templates,
-- a load-on-demand addon and a pool of shared textures - and when one of
-- them is not there yet the symptom is always the same: nothing visibly
-- happens. Four rounds went into the button tray guessing at exactly
-- that class of failure from screenshots. /zui maps answers it directly.

local ADDON_NAME = ...
-- Zacui_Maps is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Maps = ns.Maps
local MapsBattlefield = ns.MapsBattlefield
local MapsFrame = ns.MapsFrame
local MapsGroup = ns.MapsGroup
local MapsHD = ns.MapsHD
local MapsIcons = ns.MapsIcons
local MapsReveal = ns.MapsReveal
local MapsSkin = ns.MapsSkin
local Modules = ns.Modules
local Print = ns.Print
local RegisterLoD = ns.RegisterLoD

local applied = {}

-- THE ORDER THE PIECES RAN IN, recorded rather than merely intended.
-- Ordering here is load-bearing and invisible: skinning before the frame
-- switch strips the fullscreen map's furniture and never sees the
-- windowed map's, which looks exactly like "the skin does not work".
-- Nothing about the resulting frame says which order it happened in, so
-- the order is kept and printed.
local order = {}

-- Each piece is applied on its own so one missing Blizzard frame cannot
-- take the other four down with it - the failure this module is most
-- likely to hit is "that system is not loaded yet", and that must degrade
-- to "four of five worked" rather than to nothing.
local function Step(name, fn)
    order[#order + 1] = name
    local ok, err = pcall(fn)
    applied[name] = ok and true or tostring(err)
    if not ok then Print("map " .. name .. " failed: " .. tostring(err)) end
    return ok
end

-- SKIN AFTER FRAME, ALWAYS. Maps_Frame flips the client to the windowed
-- map, and the windowed map wears different furniture from the
-- fullscreen one. Skinning first strips chrome that is about to be
-- replaced by chrome nobody then touches - which is exactly how the map
-- ended up flat dark inside a carved wooden picture frame.
local function ApplyAll()
    wipe(order)
    Step("frame", MapsFrame.Apply)
    Step("skin", MapsSkin.Apply)
    Step("reveal", MapsReveal.Apply)
    Step("hd", MapsHD.Apply)
    Step("pins", MapsIcons.Apply)
    Step("group", MapsGroup.Apply)
    Step("battlefield", MapsBattlefield.Apply)
end

-- Called by every config toggle. Cheap because the install work is all
-- behind `if not installed` guards - this is the re-apply pass, not the
-- setup pass.
function Maps.Refresh()
    if not ZacUIDB.modules or not ZacUIDB.modules.maps then return end
    ApplyAll()
    if MapsReveal.Repaint then MapsReveal.Repaint() end
    if MapsIcons.Refresh then MapsIcons.Refresh() end
end

-- A LOOK setting changed (a colour, a font, a pin size): repaint what is
-- on the map where it stands. Lighter than Refresh - no frame is moved,
-- nothing is installed - and asked at most once a frame (the Maps page
-- coalesces it), so dragging a colour wheel stays smooth.
function Maps.ApplyLook()
    if not ZacUIDB.modules or not ZacUIDB.modules.maps then return end
    if MapsSkin.Repaint then pcall(MapsSkin.Repaint) end
    if MapsFrame.ApplyCoords then pcall(MapsFrame.ApplyCoords) end
    if MapsIcons.Refresh then pcall(MapsIcons.Refresh) end
    if MapsGroup.Update then pcall(MapsGroup.Update) end
    if MapsReveal.Repaint then pcall(MapsReveal.Repaint) end
end

function Maps.Diagnose()
    Print("--- maps ---")
    Print("module: " .. (ZacUIDB.modules and ZacUIDB.modules.maps
        and "|cff66ff66enabled|r" or "|cffff6666disabled|r"))

    -- EVERYTHING ABOUT THE DOTS, IN ONE LINE EACH. "gone or in the wrong
    -- spot" has now cost more rounds than any other symptom in this
    -- addon, every one of them spent guessing which of several changes
    -- did it. Shape, size, count, stacking and the actual position of
    -- the first dot are all cheap to read and between them there is
    -- nowhere left for the answer to hide.
    local G = ns.MapsGroup
    if G then
        local r = G.rounded
        Print("group dots: " .. (r == true and "round"
            or r == false and "|cffff9900square - this client has no mask API|r"
            or "not drawn yet - open the map in a group"))
        Print("  drawn: " .. tostring(G.shown or 0)
            .. "   size: " .. tostring(ns.Maps.DB().classIconSize)
            .. "   in group: " .. tostring(math.max(0, ns.Roster.Size() - 1)))
        local first = G.dots and G.dots[1]
        if first then
            local map = _G.WorldMapFrame
            local sc = map and map.ScrollContainer
            local canvas = sc and (sc.Child or (sc.GetCanvas and sc:GetCanvas()))
            Print("  first dot: strata " .. tostring(first:GetFrameStrata())
                .. " vs canvas " .. tostring(canvas and canvas:GetFrameStrata())
                .. "   shown=" .. tostring(first:IsShown())
                .. "   alpha=" .. tostring(first:GetAlpha()))
            if canvas and canvas:GetWidth() and canvas:GetWidth() > 0
                and first:GetCenter() and canvas:GetLeft() then
                local cx, cy = first:GetCenter()
                Print(string.format("  first dot sits at %.2f, %.2f of the map",
                    (cx - canvas:GetLeft()) / canvas:GetWidth(),
                    1 - ((cy - canvas:GetBottom()) / canvas:GetHeight())))
            end
        end
    end

    -- WHICH PIN CATEGORIES ARE ON, AND WHETHER THEY CAN DRAW. A category
    -- switched on whose art this client does not have shows nothing at
    -- all, which is indistinguishable from having no data for the zone.
    local db = ns.Maps.DB()
    local on = {}
    for _, key in ipairs({ "flightPoints", "flightOpposing", "dungeons",
                           "spiritHealers", "crossings" }) do
        if db[key] then on[#on + 1] = key end
    end
    if db.migratedFrom then
        Print("settings migrated from revision " .. tostring(db.migratedFrom)
            .. " to " .. tostring(db.rev))
    end
    Print("pins on: " .. (#on > 0 and table.concat(on, ", ") or "none"))
    local bad = ns.MapsIcons and ns.MapsIcons.unresolved
    if bad and next(bad) then
        for kind, wanted in pairs(bad) do
            Print("  |cffff9900" .. kind .. " has no art on this client|r"
                .. " (wanted " .. tostring(wanted) .. ")")
        end
    end

    local map = _G.WorldMapFrame
    Print("world map frame: " .. (map and "present" or "|cffff9900missing|r"))
    if map then
        Print(string.format("  size %.0fx%.0f  scale setting %.2f  mapID %s",
            map:GetWidth() or 0, map:GetHeight() or 0,
            Maps.DB().scale or 0, tostring(map.mapID)))
    end

    for _, name in ipairs({ "frame", "skin", "reveal", "hd", "pins", "group", "battlefield" }) do
        local state = applied[name]
        if state == true then
            Print("  " .. name .. ": |cff66ff66ok|r")
        elseif state then
            Print("  " .. name .. ": |cffff6666" .. state .. "|r")
        else
            Print("  " .. name .. ": |cffff9900not applied|r")
        end
    end

    -- The three questions that explain almost every "it does nothing".
    local pinCount = 0
    if map and map.EnumeratePinsByTemplate then
        local ok, iter = pcall(map.EnumeratePinsByTemplate, map, "ZacUIMapPinTemplate")
        if ok and iter then for _ in iter do pinCount = pinCount + 1 end end
    end
    Print("pins on the current map: " .. pinCount)

    local mapID = map and map.mapID
    local art = mapID and C_Map and C_Map.GetMapArtID and C_Map.GetMapArtID(mapID)
    local zone = art and ns.MapData.reveal[art]
    Print("reveal data for this zone: "
        .. (zone and (#zone .. " chunks") or "|cffff9900none - not a zone with art|r")
        .. (art and ("  (art " .. art .. ")") or ""))

    local revealed = 0
    for _ in pairs(MapsReveal.mine or {}) do revealed = revealed + 1 end
    Print("unexplored tiles drawn: " .. revealed)
    if MapsHD.Report then pcall(MapsHD.Report, Print) end
    Print("group dots drawn: " .. tostring(ns.MapsGroup.shown or 0))

    Print("battlefield map: "
        .. (_G.BattlefieldMapFrame and "loaded" or "not loaded (enter a battleground)"))
    Print("applied in order: " .. (#order > 0 and table.concat(order, " -> ")
        or "|cffff9900nothing yet|r"))
    Print("run |cffffd100/zui mapdump|r to list every frame and texture on")
    Print("the map that is still Blizzard's.")
end

-- Exposed because the ORDER is an invariant, not an implementation
-- detail: the skin has to come after the frame switch or it strips the
-- wrong map's furniture.
Maps.ApplyOrder = order

-- ============================================================
-- MODULE
-- ============================================================
Modules.maps = function()
    ApplyAll()

    -- The battlefield map arrives whenever the player first zones into a
    -- battleground, which is long after login. Registering rather than
    -- polling means it is set up the moment it exists.
    RegisterLoD("Blizzard_BattlefieldMap", function()
        Step("battlefield", MapsBattlefield.Apply)
    end)
end

-- shared with later ZacUI files
ns.MapsDiagnose = Maps.Diagnose
ns.MapsDump = MapsSkin.Dump
ns.MapsCanvasDump = MapsSkin.CanvasDump
