-- Maps_Core - the map layer's settings, and the two primitives every
-- other Maps file is built on: waiting for a canvas pin to exist, and
-- resolving an atlas that might not.
-- Part of ZacUI; load order is set by the TOC.
--
-- ZACUI IS THE MAP ADDON. There is deliberately no check for Leatrix
-- Maps and no standing down if it is installed. Two addons both hooking
-- MapExplorationPin:RefreshOverlays and both rewriting CreateZoomLevels
-- will fight, and the honest fix is to turn one off - not for this
-- module to quietly do nothing and leave the player wondering why its
-- settings have no effect. That mistake cost four rounds on the button
-- tray and it is not being repeated here.
--
-- LIVE, NOT RELOAD-GATED. The addon this replaces marks eleven of its
-- options "requires reload", because it installs its hooks inside one
-- big init function and a hook cannot be uninstalled. The pattern here
-- is the opposite: hooks are installed once and permanently, and the
-- SETTING IS READ INSIDE THE HOOK. A permanent hook whose body starts
-- with `if not On("reveal") then return end` costs nothing when the
-- feature is off and makes every toggle immediate.

local ADDON_NAME = ...
-- Zacui_Maps is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print

local Maps = {}

-- ============================================================
-- SETTINGS
-- ============================================================
-- Bumped when a shipped default changes in a way a stored value would
-- otherwise hide forever - the same migration the tray needed after its
-- default position moved.
-- 2: pins forced off. 3: marker sizes brought down. 4: pins given back,
-- because switching them off was the wrong call - see the note beside
-- them below.
local MAPS_REV = 4

-- The defaults and migrations run once per settings TABLE, not per
-- read. DB() is asked from per-frame OnUpdates (centring, the coords
-- strip, the battlefield map that people leave open all session), and
-- the full pass below is fifty-odd checks and a write. A profile switch
-- or reset replaces ZacUIDB.maps with a new table, which is what makes
-- the next read rebuild.
local cached

local function Build()
    -- A BRAND-NEW PROFILE IS NOT AN OLD ONE TO BE MIGRATED, and telling
    -- the two apart has to happen before a single default is written.
    --
    -- Every migration below is of the form "if this value is X, it was my
    -- old default, so move it on". On a fresh table those values have
    -- just been written by the defaults in between - so the migrations
    -- fired against them and quietly overrode the shipped default. It
    -- worked by luck here because the two agreed, and a test that changed
    -- the default proved it: the default changed and the behaviour did
    -- not, because rev 4 was undoing it one screen further down.
    local brandNew = (ZacUIDB.maps == nil) or (next(ZacUIDB.maps) == nil)

    ZacUIDB.maps = ZacUIDB.maps or {}
    local d = ZacUIDB.maps

    -- Frame
    if d.unlock == nil then d.unlock = true end
    if d.scale == nil then d.scale = 0.9 end
    if d.fade == nil then d.fade = true end
    if d.movingAlpha == nil then d.movingAlpha = 0.5 end
    if d.stillAlpha == nil then d.stillAlpha = 1 end
    if d.noFadeUnderCursor == nil then d.noFadeUnderCursor = true end
    -- How much of the remaining distance the fade covers each tick.
    if d.fadeSpeed == nil then d.fadeSpeed = 0.35 end
    if d.rememberZoom == nil then d.rememberZoom = true end
    if d.extraZoom == nil then d.extraZoom = true end
    if d.zoomFactor == nil then d.zoomFactor = 2 end
    if d.zoomToCursor == nil then d.zoomToCursor = true end
    if d.scrollZones == nil then d.scrollZones = true end
    if d.scrollFade == nil then d.scrollFade = true end
    if d.smoothZoom == nil then d.smoothZoom = true end     -- the wheel's zoom eased over 0.15 s     -- the new map fades in over a zone change
    -- the zone map drawn from the game's minimap tiles (Maps_HD)
    if d.hdMap == nil then d.hdMap = true end
    if d.hdAlpha == nil then d.hdAlpha = 1 end
    if d.hdContinents == nil then d.hdContinents = true end
    if d.hdSolid == nil then d.hdSolid = true end           -- the sea colour under the tiles, no painting through
    if d.dungeonsContinent == nil then d.dungeonsContinent = true end   -- dungeon and raid pins on continent maps too
    if d.centreOnPlayer == nil then d.centreOnPlayer = false end
    if d.followZone == nil then d.followZone = true end

    -- Readouts
    if d.coords == nil then d.coords = true end
    if d.zoneLevels == nil then d.zoneLevels = true end
    if d.fishingLevels == nil then d.fishingLevels = true end

    -- Player and group
    if d.bigArrow == nil then d.bigArrow = true end
    -- 18, not 27. Blizzard's own is 16, and "enlarge the arrow" was read
    -- as licence to make it substantial - at 27 on a windowed map it is a
    -- blob you look past rather than a marker you read. The point of the
    -- option is that 16 disappears on a full-screen map, and 18 fixes
    -- that without becoming the biggest thing on screen.
    if d.arrowSize == nil then d.arrowSize = 18 end
    if d.classIcons == nil then d.classIcons = true end
    -- Small. These are dots marking where a person is, not badges - at
    -- 24 they crowd each other into a blob the moment a party stands
    -- together, which is the one time you are looking at them. Blizzard
    -- ships 12; 14 is a nudge up from that, not a redesign.
    -- 10, not 14. At 14 a party standing together is one blob, and a dot
    -- that is now actually round reads larger than the square did at the
    -- same number.
    if d.classIconSize == nil then d.classIconSize = 10 end
    -- Shape, outline and opacity of the group dots. Separated from the
    -- size because "too big" and "wrong shape" were reported as one
    -- complaint three times running, and they are not the same setting.
    if d.dotRound == nil then d.dotRound = true end
    if d.dotBorder == nil then d.dotBorder = true end
    if d.dotAlpha == nil then d.dotAlpha = 1 end
    -- Names under the group dots; ones that would overlap are left off.
    if d.dotNames == nil then d.dotNames = true end
    if d.dotNameSize == nil then d.dotNameSize = 9 end
    if d.dotNameDeclutter == nil then d.dotNameDeclutter = true end
    -- The size of ZacUI's OWN pins - flight points, dungeons, spirit
    -- healers, crossings. Blizzard's own POIs are not ours to resize.
    if d.pinSize == nil then d.pinSize = 14 end

    -- Reveal. The tint COLOUR is not stored here - it is a palette entry
    -- (map/reveal) so the colour editor, the theme and profile export all
    -- reach it like every other colour in the addon. Only the strength
    -- lives here, because it is a property of the effect rather than of
    -- the colour.
    if d.reveal == nil then d.reveal = true end
    if d.revealTint == nil then d.revealTint = true end
    if d.tintAlpha == nil then d.tintAlpha = 1 end

    -- PINS ARE ON. These were switched off in rev 2 on the strength of one
    -- complaint about how they LOOKED - there was a square plate behind
    -- every pin at the time, which put a box round a spirit healer - plus
    -- an argument that ElvUI ships no pins of its own. The first was a
    -- rendering bug and it is fixed; the second was never a reason,
    -- because the point of this layer is the things ElvUI does not do.
    -- Marked spirit healers, zone-crossing arrows and flight paths are
    -- most of why anyone installs a map addon.
    if d.flightPoints == nil then d.flightPoints = true end
    if d.dungeons == nil then d.dungeons = true end
    if d.spiritHealers == nil then d.spiritHealers = true end
    if d.crossings == nil then d.crossings = true end
    -- The exception, and it stays off: the other faction's flight points
    -- are useful for knowing where NOT to land, which is a narrower want.
    if d.flightOpposing == nil then d.flightOpposing = false end
    if d.hideTownIcons == nil then d.hideTownIcons = false end

    -- Battlefield map
    if d.battlefield == nil then d.battlefield = true end
    if d.bfUnlock == nil then d.bfUnlock = true end
    if d.bfSize == nil then d.bfSize = 380 end
    if d.bfAlpha == nil then d.bfAlpha = 1 end
    if d.bfZoom == nil then d.bfZoom = 1.5 end
    if d.bfCentre == nil then d.bfCentre = true end
    if d.bfArrowSize == nil then d.bfArrowSize = 30 end
    if d.bfIconSize == nil then d.bfIconSize = 18 end
    if d.bfShowPlayers == nil then d.bfShowPlayers = true end

    -- THE LOOK (2026-11-01 settings pass). Every one of these is what the
    -- map already drew, written down so it can be changed: nothing looks
    -- different until somebody moves a control. Colours and fonts that
    -- follow the theme (the header, the coordinate strip, the window) are
    -- deliberately NOT written here - nil is what keeps them following it,
    -- and Maps.Color / Maps.StyleText read nil as "the theme's".
    if d.pinHalo == nil then d.pinHalo = true end           -- the black outline behind each pin
    if d.pinHaloSize == nil then d.pinHaloSize = 1.34 end   -- a third larger than the icon
    if d.pinScaleFlight == nil then d.pinScaleFlight = 1 end
    if d.pinScaleDungeons == nil then d.pinScaleDungeons = 1 end
    if d.pinScaleSpirit == nil then d.pinScaleSpirit = 1 end
    if d.pinScaleCrossing == nil then d.pinScaleCrossing = 1 end
    if d.dotColorMode == nil then d.dotColorMode = "class" end
    if d.dotNameColorMode == nil then d.dotNameColorMode = "class" end
    if d.dotBorderSize == nil then d.dotBorderSize = 1 end
    if d.coordDecimals == nil then d.coordDecimals = 1 end
    if d.coordLabels == nil then d.coordLabels = true end
    -- the dip to dark over a zone change, and the wheel's glide
    if d.scrollFadeTime == nil then d.scrollFadeTime = 0.25 end
    if d.scrollFadeDepth == nil then d.scrollFadeDepth = 0.3 end
    if d.smoothZoomTime == nil then d.smoothZoomTime = 0.15 end
    -- the map has always just appeared; "none" keeps it that way
    if d.openAnim == nil then
        d.openAnim = { style = "none", duration = 0.25, delay = 0, easing = "easeOutQuad",
                       dir = "up", distance = 20 }
    end

    -- THE REV 2 MIGRATION IS DELIBERATELY GONE, not just superseded.
    -- It force-cleared these on every profile it touched, and leaving it
    -- in would mean an old profile got them switched off on the way past
    -- rev 2 and switched back on at rev 4 - a round trip that does
    -- nothing but risk clobbering a choice made in between.

    -- ============================================================
    -- A NEW DEFAULT DOES NOTHING FOR A PROFILE THAT ALREADY DECIDED
    -- ============================================================
    -- Every line above is `if d.x == nil then d.x = ... end`, which is
    -- correct - it is what stops the addon overwriting a setting you
    -- chose. It also means that lowering a default changes nothing at all
    -- for anyone already playing, because their value is not nil.
    --
    -- The markers were dropped from 27 to 18 and from 14 to 10 and stayed
    -- exactly the same size on screen, which read as the fix not working
    -- rather than as the fix not arriving. Two rounds of "still too big"
    -- came out of that.
    --
    -- So sizes nobody has deliberately changed are moved on. The guard is
    -- the old default: if the value is still what the addon shipped, it
    -- was never a decision and can be updated. Anything else is left
    -- alone, which is the whole point of storing it.
    -- Recorded when a migration actually runs. Two reasons, and neither
    -- is test plumbing: "which revision did this profile arrive from" is
    -- the first thing worth knowing when a setting looks wrong after an
    -- update, and without it the brand-new-profile guard above is
    -- invisible - it only matters when a default and a migration target
    -- disagree, which is precisely the case nobody notices until it bites.
    if not brandNew and (d.rev or 1) < MAPS_REV then
        d.migratedFrom = d.rev or 1
    end

    if not brandNew and (d.rev or 1) < 3 then
        if d.arrowSize == 27 then d.arrowSize = 18 end
        if d.classIconSize == 14 or d.classIconSize == 24 then
            d.classIconSize = 10
        end
    end

    -- Rev 4 gives the pins back to anyone rev 2 took them from. The guard
    -- is `== false`: a profile that has them off because rev 2 said so
    -- looks identical to one that has them off because somebody turned
    -- them off, so this is a judgement call rather than a deduction -
    -- and the judgement is that they were switched off by me, not by
    -- you. Every one of them is a checkbox on the Maps page.
    if not brandNew and (d.rev or 1) < 4 then
        if d.flightPoints == false then d.flightPoints = true end
        if d.dungeons == false then d.dungeons = true end
        if d.spiritHealers == false then d.spiritHealers = true end
        if d.crossings == false then d.crossings = true end
    end

    d.rev = MAPS_REV
    return d
end

local function DB()
    local d = ZacUIDB.maps
    if d ~= nil and d == cached then return d end
    cached = Build()
    return cached
end

-- The single question every hook body asks. Cheap enough to call from an
-- OnUpdate (DB() is a table compare once built), which is the point - the alternative is a hook that has to be
-- torn down, and there is no tearing down a hooksecurefunc.
-- OPENMAP (2026-10-31). OpenMap (MIT; OpenMap Classic is its Classic Era
-- port) replaces the map's zoom with one continuous stitched world: every
-- zone on one canvas, the wheel from the whole world to street level,
-- the map underneath following the view. With it loaded, ZacUI's own
-- zoom work stands down - the extra levels, the aim at the cursor, the
-- easing, the wheel step into and out of zones, the remembered zoom and
-- the minimap-tile layer - since each would fight it. The window, the
-- coordinates strip, the pins and the group dots stay ZacUI's.
function Maps.OpenMapLoaded()
    -- the part (Zacui_WorldMap) publishes ZacuiWorldMap; a stand-alone OpenMap, OpenMap
    if type(_G.ZacuiWorldMap) == "table" or type(_G.OpenMap) == "table" then return true end
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not loaded then return false end
    for _, name in ipairs({ "OpenMap", "OpenMap_Classic", "OpenMapClassic" }) do
        local ok, is = pcall(loaded, name)
        if ok and is then return true end
    end
    return false
end
-- ZACUI WORLD MAP (2026-10-31, Zac: "build it into zac ui i dont want to
-- use other addons"). OpenMap now ships INSIDE ZacUI as the part
-- Zacui_WorldMap (MIT, licence and credits kept), so on a stock install
-- OpenMapLoaded() is true and these all stand down for good; they come
-- back only when that part is switched off in the AddOns list. Besides
-- the zoom: the window's own place, scale grip and remembered point
-- (OpenMap's title bar, corner grips and size slider do that, and two
-- things putting the window back fight), the unexplored-area reveal
-- (OpenMap draws its own on the stitched art, above Blizzard's
-- exploration pin where ZacUI's would go), and the dungeon, raid and
-- flight pins (OpenMap places those too, with boss lists and routes;
-- ZacUI's spirit healers and crossings stay, it has none).
local ZOOM_KEYS = { extraZoom = true, zoomToCursor = true, smoothZoom = true, scrollZones = true,
    scrollFade = true, rememberZoom = true, hdMap = true, centreOnPlayer = true,
    unlock = true, reveal = true, revealTint = true, dungeonsContinent = true }
Maps.OPENMAP_KEYS = ZOOM_KEYS
local function On(key)
    if not ZacUIDB.modules or not ZacUIDB.modules.maps then return false end
    if ZOOM_KEYS[key] and Maps.OpenMapLoaded() then return false end
    return DB()[key] and true or false
end

-- ============================================================
-- WAITING FOR A PIN
-- ============================================================
-- Canvas pins are not frames that exist from login. They are acquired
-- from a pool when a map is drawn and released when it changes, so
-- `EnumeratePinsByTemplate` at PLAYER_LOGIN can perfectly well return
-- nothing at all - and the addon this replaces has no guard for that.
-- It reads `.dataProvider` off the first pin it finds, so on a login
-- where the pin has not been acquired yet it indexes nil and takes the
-- rest of its init down with it.
--
-- ForEachPin instead registers interest ONCE and applies the function
-- to every pin of that template, now and every time the map changes,
-- remembering which pin frames it has already handled. Pools recycle
-- frames, so `seen` is keyed by the frame itself and stays tiny.
local watchers, seen = {}, {}
local watching = false

local function SweepPins()
    local map = _G.WorldMapFrame
    if not map or not map.EnumeratePinsByTemplate then return end
    for template, list in pairs(watchers) do
        local ok, iter = pcall(map.EnumeratePinsByTemplate, map, template)
        if ok and iter then
            for pin in iter do
                for _, fn in ipairs(list) do
                    seen[fn] = seen[fn] or {}
                    if not seen[fn][pin] then
                        seen[fn][pin] = true
                        local ran, err = pcall(fn, pin)
                        if not ran then
                            Print("map pin setup failed: " .. tostring(err))
                        end
                    end
                end
            end
        end
    end
end

function Maps.ForEachPin(template, fn)
    watchers[template] = watchers[template] or {}
    local list = watchers[template]
    list[#list + 1] = fn

    if not watching then
        watching = true
        local map = _G.WorldMapFrame
        if map then
            if map.HookScript then map:HookScript("OnShow", SweepPins) end
            -- OnMapChanged is where a pool hands out new pins, so it is
            -- the moment a previously-unseen pin can appear.
            if map.OnMapChanged then
                hooksecurefunc(map, "OnMapChanged", SweepPins)
            end
        end
    end
    SweepPins()
end

-- ============================================================
-- ATLASES
-- ============================================================
-- Atlas names come and go between builds, and an atlas that does not
-- resolve renders as nothing at all - an invisible pin that still takes
-- clicks, which is worse than a wrong-looking one. So every icon names
-- several candidates and the first one this client actually has wins.
local atlasCache = {}

function Maps.Atlas(...)
    local candidates = { ... }
    local key = table.concat(candidates, "|")
    local hit = atlasCache[key]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    for _, name in ipairs(candidates) do
        local info
        if C_Texture and C_Texture.GetAtlasInfo then
            info = C_Texture.GetAtlasInfo(name)
        elseif GetAtlasInfo then
            info = GetAtlasInfo(name)
        end
        if info then
            atlasCache[key] = name
            return name
        end
    end
    atlasCache[key] = false
    return nil
end

-- ============================================================
-- TAINT
-- ============================================================
-- Some of what the battlefield map needs is a write to a Blizzard global
-- (BattlefieldMapOptions) or a call on a frame Blizzard's own code will
-- later act on. Doing either directly marks the value as addon-authored,
-- and the taint follows it into whatever secure path touches it next.
-- RunScript executes in a clean context, so the write comes back as
-- Blizzard's own. It is a string eval, which is why it is confined to
-- this one helper and only ever called with literals from our own files.
function Maps.Untainted(chunk)
    if RunScript then
        local ok, err = pcall(RunScript, chunk)
        if not ok then Print("map setup failed: " .. tostring(err)) end
    end
end

-- ============================================================
-- SMALL SHARED PIECES
-- ============================================================
-- Anchors are stored as point/x/y against UIParent. Stored with a nil
-- relativeTo on purpose: a saved reference to a frame is a saved
-- reference to a frame that might not exist next login.
function Maps.SavePoint(frame, store)
    if not frame or not frame.GetPoint then return end
    local point, _, _, x, y = frame:GetPoint(1)
    store.point, store.x, store.y = point, x, y
end

function Maps.RestorePoint(frame, store, defPoint, defX, defY)
    if not frame or not frame.ClearAllPoints then return end
    frame:ClearAllPoints()
    frame:SetPoint(store.point or defPoint, UIParent,
        store.point or defPoint, store.x or defX or 0, store.y or defY or 0)
end

-- ============================================================
-- ONE STRATA UP
-- ============================================================
-- Strata beats frame level unconditionally, so a frame of ours one
-- strata above the canvas cannot be out-ranked by a pin however high
-- Blizzard numbers its level. Shared by the skin's furniture and the
-- group dots.
Maps.STRATA_UP = {
    BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG",
    DIALOG = "FULLSCREEN", FULLSCREEN = "FULLSCREEN_DIALOG",
    FULLSCREEN_DIALOG = "TOOLTIP", TOOLTIP = "TOOLTIP",
}

-- ============================================================
-- EXTRA ZOOM AND CENTRING (world map and battlefield map)
-- ============================================================
-- EXTRA ZOOM, BY APPENDING. Blizzard builds zoomLevels from the map art's
-- own min/max scale and step count. Post-hooking and appending past the
-- top level keeps Blizzard's levels exactly as Blizzard computed them and
-- has nothing to keep in sync. factor() returns the multiplier (or
-- anything <= 1 / nil for "leave it alone").
function Maps.InstallExtraZoom(sc, factor)
    if not sc or not sc.CreateZoomLevels then return end
    hooksecurefunc(sc, "CreateZoomLevels", function(self)
        local f = factor() or 1
        if f <= 1 then return end
        local levels = self.zoomLevels
        if not levels or #levels == 0 then return end
        local top = levels[#levels]
        if not top or not top.scale then return end
        local steps = math.max(1, math.floor((f - 1) * 4 + 0.5))
        for i = 1, steps do
            levels[#levels + 1] = {
                scale = top.scale * (1 + (f - 1) * (i / steps)),
                layerIndex = top.layerIndex,
            }
        end
    end)
end

-- Keeps the player in the middle of a map canvas. opts:
--   enabled()     read every frame; off = nothing else runs
--   interval      seconds between re-centres
--   mapID()       the map on show
--   holdOff       seconds that holding shift suspends it for (nil: only
--                 while shift is held)
-- Returns a function that makes the next frame re-centre at once.
function Maps.InstallCentring(owner, sc, opts)
    if not sc then return nil end
    local driver = CreateFrame("Frame", nil, owner)
    local elapsed, suppressed = 0, 0
    local interval = opts.interval or 1
    driver:SetScript("OnUpdate", function(_, dt)
        if not opts.enabled() then return end
        if sc.IsPanning and sc:IsPanning() then return end

        -- Holding shift is the escape hatch: it suspends re-centring
        -- long enough to actually look somewhere else. Without it the
        -- feature fights every attempt to pan away.
        if IsShiftKeyDown() then
            suppressed = opts.holdOff or 0
            return
        end
        if suppressed > 0 then
            suppressed = suppressed - dt
            return
        end

        elapsed = elapsed + dt
        if elapsed < interval then return end
        elapsed = 0

        local mapID = opts.mapID()
        if not mapID or not C_Map or not C_Map.GetPlayerMapPosition then return end
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then return end
        local x, y = pos:GetXY()
        if not x then return end

        -- Clamped to what the canvas can actually scroll to, or the map
        -- lurches to a stop against its own edge every tick.
        if sc.CalculateScrollExtentsAtScale and sc.GetCanvasScale then
            local minX, maxX, minY, maxY =
                sc:CalculateScrollExtentsAtScale(sc:GetCanvasScale())
            if minX then
                x = math.max(minX, math.min(maxX, x))
                y = math.max(minY, math.min(maxY, y))
            end
        end
        if sc.SetPanTarget then sc:SetPanTarget(x, y) end
    end)
    return function() elapsed, suppressed = 99, 0 end
end

-- ============================================================
-- NAME LABELS (map dots and minimap names)
-- ============================================================
-- The ZacUI font at a size, outlined so a name reads on any terrain.
-- The path is resolved once per pass by the caller; the label only
-- touches SetFont when its size, path, outline or shadow actually
-- changed. flags / shadow (the group dots' name font, 2026-11-01) are
-- optional: left out, a name is outlined with no shadow, as it always was.
-- SetFont that says whether the face took: pcall catches a nil path, the
-- return value a font file that would not load - which leaves the string
-- with no font, so its next SetText errors ("Font not set")
local function TrySetFont(fs, path, size, flags)
    local ok, set = pcall(fs.SetFont, fs, path, size, flags)
    return (ok and set) and true or false
end
function Maps.LabelFont(fs, size, fpath, delta, flags, shadow, sx, sy)
    -- (no face of ZacUI's: the game's, not whatever the label wore last)
    local path = fpath or ns.GAME_FONT or select(1, fs:GetFont()) or STANDARD_TEXT_FONT
    flags = flags or "OUTLINE"
    local sh = shadow and ((sx or 1) .. "," .. (sy or -1)) or "0"
    if fs._zSize ~= size or fs._zPath ~= path or fs._zFlags ~= flags or fs._zShadow ~= sh then
        if TrySetFont(fs, path, size + (delta or 0), flags) then
            fs._zSize, fs._zPath, fs._zFlags = size, path, flags
        elseif not fs:GetFont() then
            -- the face did not load: the game's font, so the name still draws
            pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size + (delta or 0), flags)
        end
        if shadow ~= nil and fs.SetShadowOffset then
            if shadow then
                if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
                fs:SetShadowOffset(sx or 1, sy or -1)
            else
                fs:SetShadowOffset(0, 0)
            end
        end
        fs._zShadow = sh
    end
end

-- ============================================================
-- THE LOOK, READ ONE WAY BY THE MAP AND ITS PREVIEW
-- ============================================================
-- A colour setting, or the theme's colour when it is not set (nil). The
-- theme colour is read every time, so a palette change still reaches a
-- map whose colour nobody overrode.
function Maps.Color(key, cat, ckey, alpha)
    local c = DB()[key]
    if type(c) == "table" then
        if ns.ColorOf then return ns.ColorOf(c) end
        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
    end
    if type(cat) == "table" then          -- a fixed default ({ r, g, b, a })
        return cat[1], cat[2], cat[3], cat[4] or 1
    end
    -- (cat, key) is a palette entry; a lone name is one of ns.Col's
    -- shorthands ("windowBg", "accent"), as the map's own paint used
    local t
    if ckey == nil then
        t = ns.Col and ns.Col(cat)
    else
        t = ns.GetColor and ns.GetColor(cat, ckey)
    end
    t = t or {}
    return t.r or 1, t.g or 1, t.b or 1, alpha or t.a or 1
end

-- What an unset font field means on the map: exactly what UI.Font gives
-- its text (the ZacUI font, its size step plus the global size
-- adjustment, outlined unless outlines are off globally, and the shadow
-- of the template it is made from). A spec with nothing in it therefore
-- changes nothing at all.
function Maps.FontDefaults(baseSize)
    local cfg = ZacUIDB and ZacUIDB.font or {}
    return {
        size = (baseSize or 12) + (cfg.delta or 0),
        outline = (cfg.outline == "NONE") and "none" or "outline",
        shadow = true,
    }
end

function Maps.StyleText(fs, spec, baseSize)
    if not (fs and ns.ApplyFontSpec) then return end
    ns.ApplyFontSpec(fs, spec, Maps.FontDefaults(baseSize))
end

-- A length of time, through Appearance > Motion: 0 with animations off,
-- divided by the speed otherwise. Every eased or faded change on the map
-- goes through this, so the global switches reach it like everything else.
function Maps.Time(t)
    local M = ns.Motion
    if not M then return t end
    if M.Enabled and not M.Enabled() then return 0 end
    local s = M.Speed and M.Speed() or 1
    return (t or 0) / s
end

-- Leaves a name off when it would land on one already placed, so a
-- stacked group shows one readable name, not a smear. Boxes (centre x,
-- centre y, half width, half height) are kept between passes and
-- rewritten in place; Reset() starts a pass.
function Maps.NewDeclutter()
    local placed, n = {}, 0
    local d = {}
    function d.Reset() n = 0 end
    function d.Place(x, y, hw, hh)
        for i = 1, n do
            local o = placed[i]
            if math.abs(x - o[1]) < hw + o[3] and math.abs(y - o[2]) < hh + o[4] then
                return false
            end
        end
        n = n + 1
        local box = placed[n]
        if not box then box = {} placed[n] = box end
        box[1], box[2], box[3], box[4] = x, y, hw, hh
        return true
    end
    return d
end

Maps.DB = DB
Maps.On = On

-- shared with later ZacUI files
ns.Maps = Maps
