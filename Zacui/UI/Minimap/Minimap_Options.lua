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
local function DB()
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

    return d
end

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
