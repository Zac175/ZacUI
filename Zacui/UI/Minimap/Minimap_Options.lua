-- Minimap_Options - what the minimap actually shows, and how big it is.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHY THIS IS A SEPARATE FILE FROM Blz_Minimap.
--
-- Blz_Minimap is a SKINNER: it decides what the minimap looks like -
-- square mask, no scrollwork, zone name in a header above it, clock and
-- friends / guild in a footer below it. Those are house-style decisions and
-- they belong in one place, applied the same way every time.
--
-- What it is NOT is a place for preferences. Every one of those elements
-- was shown unconditionally, so wanting the minimap without a clock
-- meant editing the addon. This file is the preferences layer, and it
-- sits on top rather than inside because the two answer different
-- questions: the skinner answers "what does a ZacUI minimap look like",
-- this answers "which of those parts do you want".
--
-- HIDING HERE IS PERSISTENT, AND IT HAS TO BE. Blizzard re-shows several
-- of these on its own - the mail envelope on new mail, the clock when
-- the time manager loads, the zone strip on a zone change - so a plain
-- Hide is undone within seconds and reads as the option not working.
-- Every hide is therefore backed by an OnShow guard that re-hides while
-- the setting is off, and steps aside the moment it is back on.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Print = ns.Print

local MM = {}

-- ============================================================
-- SETTINGS
-- ============================================================
-- DEFAULTS MATCH WHAT THE ADDON ALREADY DID, without exception. Adding
-- options to something people are already using must not change it under
-- them: the first time this loads, every answer is "carry on".
-- THE BACKING BEHIND THE PIECES (2026-11-18, Zac: "give the users the
-- option to pick or do something custom"; "i personally like 2 as
-- default"). What the zone name, clock, coordinates, friends and guild
-- sit on is drawn by Blz_Minimap from nine values of this table
-- (BACKING_KEYS). A preset is nothing but values for those nine: picking
-- one writes them, changing any of them by hand is "your own", and the
-- page names the preset the nine match (BackingNow).
--   box      the flat box the pieces always had (nothing but the darkness)
--   shadow   a soft dark shadow that fades to nothing
--   outline  no backing; the text outlined
--   glass    a see-through box with a thin light edge
--   fade     no backing; the map's top and bottom edges darken
-- A minimap that was already in use keeps what it had: the nine as saved
-- are the box (or its owner's own colours). A first install starts on the
-- soft shadow.
local BACKING_KEYS = { "pillShape", "pillColor", "pillAlpha", "pillBorder", "pillBorderColor",
    "pillOutline", "pillFade", "pillFadeAlpha", "pillCorners" }
local BACKINGS = {
    { id = "box", label = "Solid box", set = { pillAlpha = 0.82 } },
    { id = "shadow", label = "Soft shadow",
      set = { pillShape = "glow", pillColor = { r = 0, g = 0, b = 0, a = 1 }, pillAlpha = 0.8, pillCorners = true } },
    { id = "outline", label = "Outline only",
      set = { pillShape = "none", pillAlpha = 0.82, pillOutline = true, pillCorners = true } },
    { id = "glass", label = "Glass plate",
      set = { pillColor = { r = 0.078, g = 0.078, b = 0.078, a = 1 }, pillAlpha = 0.55, pillBorder = true,
              pillBorderColor = { r = 1, g = 1, b = 1, a = 0.16 }, pillCorners = true } },
    { id = "fade", label = "Edge fade",
      set = { pillShape = "none", pillAlpha = 0.82, pillFade = true, pillCorners = true } },
}
local BACKING_DEFAULT = "shadow"
local FADE_ALPHA = 0.82

local function CopyValue(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = x end
    return t
end

-- the nine, written as a preset has them (what it leaves out is unset)
local function WriteBacking(d, id)
    for _, b in ipairs(BACKINGS) do
        if b.id == id then
            for _, key in ipairs(BACKING_KEYS) do d[key] = CopyValue(b.set[key]) end
            return true
        end
    end
    return false
end

local function DB()
    local fresh = ZacUIDB.minimap == nil
    ZacUIDB.minimap = ZacUIDB.minimap or {}
    local d = ZacUIDB.minimap

    if d.zoneName == nil then d.zoneName = true end
    if d.clock == nil then d.clock = true end
    -- Retired: Classic Era's GameTimeFrame is the sun / moon dial, which
    -- the square minimap hides; the clock in the footer tells the time.
    d.calendar = nil
    if d.mail == nil then d.mail = true end
    if d.tracking == nil then d.tracking = true end
    if d.wheelZoom == nil then d.wheelZoom = true end
    if d.coords == nil then d.coords = true end
    if d.infoBar == nil then d.infoBar = true end
    if d.autoZoom == nil then d.autoZoom = false end
    if d.smoothZoom == nil then d.smoothZoom = true end
    -- past the widest level, on into the painted map: OFF (2026-11-01, Zac: "still happens with the
    -- minimap" - the painted map came out magnified and the zone's own map did not draw; switched
    -- off for everyone, once, until it is rebuilt on the new world map's stitching)
    if not d._farZoomOff then d._farZoomOff = true d.farZoom = false end
    if d.farZoom == nil then d.farZoom = false end
    if d.scale == nil then d.scale = 1 end

    -- THE LOOK: the map-only overlay, its pieces where
    -- the old panel had them; the header-and-footer panel is a choice.
    -- LOOK REV 3 settles the defaults after two first cuts (overlay at
    -- 200 px, then the panel) - only those seeded values ever existed.
    if d.lookRev ~= 3 and d.lookRev ~= 4 and d.lookRev ~= 5 then
        d.lookRev = 3
        d.layout = "overlay"
        d.size = nil
    end
    if d.layout ~= "panel" and d.layout ~= "overlay" then d.layout = "overlay" end
    if d.mapSize == nil then d.mapSize = 185 end    -- the map's side in px, 0 = Blizzard's (140)
    -- LOOK REV 4: a little bigger than Blizzard's by default. REV 5: the
    -- map moved flush into the corner, and grew into the space that freed
    -- (its left edge stays where the 170 one had it).
    if d.lookRev == 3 then
        d.lookRev = 4
        if d.mapSize == 0 then d.mapSize = 170 end
    end
    if d.lookRev == 4 then
        d.lookRev = 5
        if d.mapSize == 170 then d.mapSize = 185 end
    end
    -- Overlay spots (TOPLEFT, TOP, TOPRIGHT, BOTTOMLEFT, BOTTOM,
    -- BOTTOMRIGHT): where the panel look had each piece.
    if d.zonePos == nil then d.zonePos = "TOP" end
    if d.clockPos == nil then d.clockPos = "BOTTOM" end
    if d.coordsPos == nil then d.coordsPos = "BOTTOM" end
    if d.friendsPos == nil then d.friendsPos = "BOTTOMLEFT" end
    if d.guildPos == nil then d.guildPos = "BOTTOMRIGHT" end
    if d.textSize == nil then d.textSize = 12 end
    if d.pillAlpha == nil then d.pillAlpha = 0.82 end
    if d.fadeTime == nil then d.fadeTime = 0.2 end  -- seconds
    -- Which overlay pills wait for the mouse (the rest stay up).
    if d.zoneHover == nil then d.zoneHover = true end
    if d.coordsHover == nil then d.coordsHover = true end
    if d.socialHover == nil then d.socialHover = true end
    if d.clockHover == nil then d.clockHover = false end
    if d.hoverEdge == nil then d.hoverEdge = true end
    if d.zoneColor ~= "pvp" and d.zoneColor ~= "accent" then d.zoneColor = "pvp" end
    -- (a first install, or the page's Reset: the default backing)
    if fresh then WriteBacking(d, BACKING_DEFAULT) end

    return d
end

-- ============================================================
-- THE BACKING: WHICH PRESET, AND PICKING ONE
-- ============================================================
local function SameNumber(a, b) return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) < 0.005 end
local function SameColour(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == nil and b == nil end
    local ar, ag, ab, aa = ns.ColorOf(a)
    local br, bg, bb, ba = ns.ColorOf(b)
    return SameNumber(ar, br) and SameNumber(ag, bg) and SameNumber(ab, bb) and SameNumber(aa or 1, ba or 1)
end
local function Shape(v) return (v == "glow" or v == "none") and v or "box" end

-- do a table's nine read as this preset's? Only what the shape draws is
-- compared: a colour means nothing without a backing, an edge only on a box.
local function Reads(d, set)
    local shape = Shape(d.pillShape)
    if shape ~= Shape(set.pillShape) then return false end
    if (d.pillOutline and true or false) ~= (set.pillOutline and true or false) then return false end
    if (d.pillFade and true or false) ~= (set.pillFade and true or false) then return false end
    if (d.pillCorners and true or false) ~= (set.pillCorners and true or false) then return false end
    if d.pillFade and not SameNumber(d.pillFadeAlpha or FADE_ALPHA, set.pillFadeAlpha or FADE_ALPHA) then return false end
    if shape == "none" then return true end
    if not SameNumber(d.pillAlpha or 0.82, set.pillAlpha or 0.82) then return false end
    if not SameColour(d.pillColor, set.pillColor) then return false end
    if shape ~= "box" then return true end
    if (d.pillBorder and true or false) ~= (set.pillBorder and true or false) then return false end
    if d.pillBorder and not SameColour(d.pillBorderColor, set.pillBorderColor) then return false end
    return true
end

-- the preset the saved values read as: its id and label, or "custom"
function MM.BackingNow(d)
    d = d or DB()
    for _, b in ipairs(BACKINGS) do
        if Reads(d, b.set) then return b.id, b.label end
    end
    return "custom", "Custom"
end

-- pick a preset: its values are written over the nine
function MM.SetBacking(id)
    return WriteBacking(DB(), id)
end

MM.BACKINGS, MM.BACKING_KEYS, MM.BACKING_DEFAULT, MM.FADE_ALPHA = BACKINGS, BACKING_KEYS, BACKING_DEFAULT, FADE_ALPHA

local function On(key)
    local v = DB()[key]
    return v == nil or v == true
end

-- ============================================================
-- FINDING THE PIECES
-- ============================================================
-- EVERY ONE OF THESE IS RESOLVED TWO WAYS, and that is not paranoia -
-- 11509 moved several of these from globals onto MinimapCluster keys,
-- and Blz_Minimap has a comment describing eight rounds lost to exactly
-- that. A nil here is silent: the option appears in the config, does
-- nothing, and looks like a bug in the setting rather than a name that
-- moved.
--
-- Returned as functions rather than values because the load-on-demand
-- pieces - the clock lives in Blizzard_TimeManager - do not exist yet
-- when this file loads.
local PARTS = {
    zoneName = function()
        return MinimapZoneTextButton
            or (MinimapCluster and MinimapCluster.ZoneTextButton)
    end,
    clock = function()
        return TimeManagerClockButton
    end,
    mail = function()
        return MiniMapMailFrame
            or (MinimapCluster and MinimapCluster.IndicatorFrame
                and MinimapCluster.IndicatorFrame.MailFrame)
    end,
    tracking = function()
        return MiniMapTracking
            or (MinimapCluster and MinimapCluster.Tracking)
            or MiniMapTrackingFrame
    end,
}

-- ============================================================
-- SHOW OR HIDE, AND MAKE IT STICK
-- ============================================================
-- ============================================================
-- SOME OF THESE ARE NOT ALWAYS SUPPOSED TO BE VISIBLE
-- ============================================================
-- The mail envelope appears when you have mail and is hidden the rest of
-- the time - that is Blizzard's job, not a setting. Ticking "New mail
-- envelope" means "let it appear when there is mail", and the code read
-- it as "show it now": every option that was on called Show() on its
-- frame, so the envelope was permanently lit and the checkbox's own
-- description - "only ever visible when you have mail waiting" - was a
-- promise the code broke on the line below it.
--
-- For anything Blizzard drives, ON means STAND ASIDE. Off still hides it
-- and keeps it hidden, because that is the part the player is asking for.
local BLIZZARD_DRIVEN = {
    mail = true,        -- shown on new mail, hidden when read
    -- Classic Era's tracking icon is shown only while a tracking spell is
    -- on (Find Herbs, a hunter track); forcing it up drew an empty box.
    tracking = true,
}

local function SetShown(key, wanted)
    local frame = PARTS[key] and PARTS[key]()
    if not frame or not frame.Hide then return false end

    frame._zMinimapWant = wanted

    -- Installed once, and it reads the CURRENT preference every time it
    -- fires rather than closing over the value it was built with. A hook
    -- cannot be removed, so one that captured "hidden" would keep hiding
    -- the frame forever after the option was turned back on - which is
    -- the trap this whole file exists to avoid.
    if not frame._zMinimapGuard then
        frame._zMinimapGuard = true
        frame:HookScript("OnShow", function(self)
            if self._zMinimapWant == false then self:Hide() end
        end)
    end

    if not wanted then
        frame:Hide()
    elseif not BLIZZARD_DRIVEN[key] then
        frame:Show()
    end
    -- ...and for a Blizzard-driven part, ON does nothing at all. The
    -- guard above has already been told to stop hiding it, so the next
    -- time the client wants it up, it goes up.
    return true
end

-- ============================================================
-- APPLY
-- ============================================================
function MM.Apply()
    if not Minimap then return end
    local d = DB()

    -- SAY SO WHEN A SETTING CANNOT BE HONOURED. Several of these frames
    -- changed names in 11509, and a name that moved fails the same way a
    -- working option does: silently. "Didn't customize the minimap" is
    -- indistinguishable from "the option did nothing" unless the addon
    -- admits which parts it could not find, so it does - once, not every
    -- time the settings are re-applied.
    local missing = {}
    for key in pairs(PARTS) do
        if not SetShown(key, On(key)) then
            missing[#missing + 1] = key
        end
    end
    if #missing > 0 and not MM._warned then
        MM._warned = true
        table.sort(missing)
        Print("|cffff9900minimap:|r this client does not have "
            .. table.concat(missing, ", ")
            .. " under the name ZacUI looks for, so "
            .. (#missing == 1 and "that option does" or "those options do")
            .. " nothing. /zui minimapinfo has the detail.")
    end

    -- Wheel zoom. Blz_Minimap hides Blizzard's + and - buttons outright
    -- because the wheel replaces them, so turning the wheel off leaves no
    -- way to zoom at all - which is a choice somebody might make, but not
    -- one to make silently.
    if Minimap.EnableMouseWheel then
        Minimap:EnableMouseWheel(d.wheelZoom and true or false)
    end

    -- SCALED ON THE CLUSTER, not the map. The zone strip, clock, mail and
    -- day number are all anchored to Minimap but parented around the
    -- cluster, so scaling the map alone leaves them the old size in the
    -- wrong places.
    local host = MinimapCluster or Minimap
    if host and host.SetScale then
        host:SetScale(math.max(0.5, math.min(2, tonumber(d.scale) or 1)))
    end

    -- The panel's header and footer follow what is shown.
    if ns.MinimapLayout then ns.MinimapLayout() end
end

-- Called by the config page after any change, and by the module on load.
function MM.Refresh()
    MM.Apply()
    -- The markers read the same settings table, so anything that changes
    -- it has to give them a chance to redraw.
    if ns.MinimapPins then ns.MinimapPins.Apply() end
end

function MM.Diagnose()
    Print("--- minimap ---")
    local d = DB()
    for key in pairs(PARTS) do
        local frame = PARTS[key]()
        Print(string.format("%-10s want=%-5s frame=%s%s", key,
            tostring(On(key)),
            frame and "found" or "|cffff9900not found on this build|r",
            frame and ("  shown=" .. tostring(frame:IsShown())) or ""))
    end
    if ns.MinimapPins then ns.MinimapPins.Diagnose() end
    Print("wheel zoom: " .. tostring(d.wheelZoom)
        .. "   reset zoom: " .. tostring(d.autoZoom)
        .. "   coordinates: " .. tostring(d.coords)
        .. "   friends / guild: " .. tostring(d.infoBar))
    Print("scale: " .. tostring(d.scale) .. "   map size: " .. tostring(d.mapSize)
        .. "   map: " .. tostring(Minimap and Minimap:GetWidth()))
    Print("look: " .. tostring(d.layout) .. "   text: " .. tostring(d.textSize)
        .. "   on mouseover: zone " .. tostring(d.zoneHover)
        .. ", coords " .. tostring(d.coordsHover)
        .. ", friends / guild " .. tostring(d.socialHover)
        .. ", clock " .. tostring(d.clockHover))
end

MM.DB = DB
MM.On = On
MM.PARTS = PARTS
MM.SetShown = SetShown

-- shared with later ZacUI files
ns.MinimapOptions = MM
