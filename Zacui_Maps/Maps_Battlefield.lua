-- Maps_Battlefield - the battleground map: bigger, movable, resizable,
-- and zoomable past Blizzard's ceiling.
-- Part of ZacUI; load order is set by the TOC.
--
-- A SEPARATE FRAME WITH A SEPARATE EVERYTHING. It shares no pins, no
-- pools and no data providers with the world map, so nothing in
-- Maps_Frame or Maps_Reveal reaches it - the two files look similar in
-- places and that similarity is a coincidence, not shared state.
--
-- IT IS ALSO LOAD ON DEMAND. Blizzard_BattlefieldMap is not present at
-- login, so everything here is arranged around "the frame may not exist
-- yet" rather than assuming it does.
--
-- TAINT. Two things this module needs are Blizzard's own globals -
-- BattlefieldMapOptions.opacity and .showPlayers - and one is a call
-- Blizzard's code will make decisions from afterwards. Writing them
-- directly stamps them as addon-authored and the mark follows the value
-- into whatever secure path reads it next. Maps.Untainted runs the write
-- in a clean context so it comes back as Blizzard's own.

local ADDON_NAME = ...
-- Zacui_Maps is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Col = ns.Col
local FLAT = ns.FLAT
local Maps = ns.Maps
local Print = ns.Print

local DB, On = Maps.DB, Maps.On

local B = {}

-- Blizzard's default is 300x200. Height is derived so the canvas never
-- letterboxes, exactly as on the world map.
local BF_ASPECT = 3 / 2
local BF_MIN, BF_MAX = 180, 1100

local installed = false
local grip

local function Frame()
    return _G.BattlefieldMapFrame
end

-- ============================================================
-- SIZE
-- ============================================================
function B.ApplySize(width)
    local f = Frame()
    if not f then return end
    local db = DB()
    width = math.max(BF_MIN, math.min(BF_MAX, tonumber(width) or db.bfSize))
    db.bfSize = width
    f:SetSize(width, math.floor(width / BF_ASPECT + 0.5))
    if f.OnFrameSizeChanged then pcall(f.OnFrameSizeChanged, f) end
end

-- ============================================================
-- OPACITY
-- ============================================================
function B.ApplyAlpha()
    local db = DB()
    -- NOTE THE INVERSION. Blizzard's field is TRANSPARENCY; the setting
    -- here is opacity, because "how visible is it" is the question a
    -- person actually has. Getting these the wrong way round produces a
    -- slider that works perfectly and backwards.
    local transparency = 1 - (db.bfAlpha or 1)
    Maps.Untainted(string.format(
        "if BattlefieldMapOptions then BattlefieldMapOptions.opacity = %.3f end",
        transparency))
    Maps.Untainted(
        "if BattlefieldMapFrame and BattlefieldMapFrame.RefreshAlpha then "
        .. "BattlefieldMapFrame:RefreshAlpha() end")
end

-- ============================================================
-- MOVING AND SIZING
-- ============================================================
local function MakeMovable(f)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    -- The frame keeps its own position rather than handing it to
    -- Blizzard's layout cache, which would restore it over ours.
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end

    -- THE DRAG TARGET IS A RING, NOT THE MAP. The canvas fills the whole
    -- frame and wants its own clicks, so a drag handle that covers the
    -- frame would make the map itself undraggable and unclickable. This
    -- is a frame BELOW the canvas whose hit rect sticks out past the
    -- edges: the ten pixels outside the map are ours, everything inside
    -- still belongs to the map.
    local ring = CreateFrame("Frame", "ZacUIBattlefieldDrag", f)
    ring:SetAllPoints(f)
    ring:SetFrameStrata(f:GetFrameStrata())
    ring:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    ring:SetHitRectInsets(-12, -12, -12, -12)
    ring:EnableMouse(true)

    ring:SetScript("OnMouseDown", function()
        if not On("bfUnlock") then return end
        f:StartMoving()
    end)
    ring:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        local db = DB()
        local point, _, _, x, y = f:GetPoint(1)
        db.bfPoint, db.bfX, db.bfY = point, x, y
        -- Re-anchored explicitly to UIParent: StopMovingOrSizing leaves
        -- the frame anchored to whatever it was dragged relative to, and
        -- that is not always something that exists next login.
        f:ClearAllPoints()
        f:SetPoint(point, UIParent, point, x, y)
    end)
    B.ring = ring

    grip = CreateFrame("Frame", "ZacUIBattlefieldGrip", f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:EnableMouse(true)
    grip:SetFrameStrata(f:GetFrameStrata())
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    for i = 1, 3 do
        local pip = grip:CreateTexture(nil, "OVERLAY")
        pip:SetTexture(FLAT)
        pip:SetSize(9 - (i - 1) * 3, 2)
        pip:SetPoint("BOTTOMRIGHT", -1, (i - 1) * 3.5 + 1)
        grip["_pip" .. i] = pip
    end
    grip._zPaint = function(self)
        local c = Col("accent")
        for i = 1, 3 do
            self["_pip" .. i]:SetVertexColor(c.r, c.g, c.b, self._hot and 1 or 0.45)
        end
    end
    grip:_zPaint()
    grip:SetScript("OnEnter", function(self) self._hot = true self:_zPaint() end)
    grip:SetScript("OnLeave", function(self) self._hot = nil self:_zPaint() end)

    grip:SetScript("OnMouseDown", function(self)
        if not On("bfUnlock") then return end
        local left = f:GetLeft()
        if not left then return end
        -- Throttled, because OnFrameSizeChanged makes the canvas
        -- recompute its zoom levels and that is not a per-frame cost.
        local wait = 0
        self:SetScript("OnUpdate", function(_, dt)
            wait = wait + dt
            if wait < 0.05 then return end
            wait = 0
            local cx = GetCursorPosition()
            B.ApplySize((cx / UIParent:GetEffectiveScale()) - left)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        if ns.RefreshConfig then ns.RefreshConfig() end
    end)
end

-- ============================================================
-- ZOOM
-- ============================================================
local function InstallZoom(f)
    Maps.InstallExtraZoom(f.ScrollContainer, function() return DB().bfZoom end)
end

function B.ApplyZoom()
    local f = Frame()
    local sc = f and f.ScrollContainer
    if not sc or not sc.CreateZoomLevels then return end
    pcall(sc.CreateZoomLevels, sc)
    if sc.GetScaleForMaxZoom and sc.SetZoomTarget then
        pcall(function() sc:SetZoomTarget(sc:GetScaleForMaxZoom()) end)
    end
end

-- ============================================================
-- CENTRING
-- ============================================================
local function InstallCentring(f)
    -- Every second; shift held pauses it (see Maps.InstallCentring).
    Maps.InstallCentring(f, f.ScrollContainer, {
        enabled = function() return On("bfCentre") end,
        interval = 1,
        mapID = function() return f.mapID or (f.GetMapID and f:GetMapID()) end,
    })
end

-- ============================================================
-- GROUP ICONS
-- ============================================================
local function ApplyUnitSizes(f)
    local db = DB()
    local provider = f.groupMembersDataProvider
    if provider and provider.SetUnitPinSize then
        pcall(provider.SetUnitPinSize, provider, "player", db.bfArrowSize)
        pcall(provider.SetUnitPinSize, provider, "party", db.bfIconSize)
        pcall(provider.SetUnitPinSize, provider, "raid", db.bfIconSize)
    end
    -- There is no EnumeratePinsByTemplate guarantee on this frame, so the
    -- unit pins are found by the method only they have.
    if f.EnumerateAllPins then
        for pin in f:EnumerateAllPins() do
            if pin.UpdateAppearanceData then
                if pin.SetAppearanceField then
                    for _, which in ipairs({ "party", "raid" }) do
                        -- Under the player arrow: your own position is
                        -- the one you look for first, and a raid of
                        -- forty icons will otherwise bury it.
                        pcall(pin.SetAppearanceField, pin, which, "sublevel", 0)
                        pcall(pin.SetAppearanceField, pin, which, "useClassColor", true)
                    end
                end
                if pin.SynchronizePinSizes then pcall(pin.SynchronizePinSizes, pin) end
            end
        end
    end
end

-- ============================================================
-- APPLY
-- ============================================================
function B.Apply()
    if not On("battlefield") then return end

    -- The map is load-on-demand and may not be here yet. Loading it
    -- through RunScript keeps the load out of our taint context.
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and not isLoaded("Blizzard_BattlefieldMap") then
        Maps.Untainted("UIParentLoadAddOn('Blizzard_BattlefieldMap')")
    end

    local f = Frame()
    if not f then return end

    if not installed then
        installed = true
        MakeMovable(f)
        InstallZoom(f)
        InstallCentring(f)

        -- Blizzard's tab is a second, separate widget for showing the
        -- map, and with a movable map it is redundant chrome that lands
        -- on top of the thing it opens.
        local tab = _G.BattlefieldMapTab
        if tab then
            tab:Hide()
            hooksecurefunc(tab, "Show", function(self)
                if On("battlefield") then self:Hide() end
            end)
        end

        Maps.Untainted(
            "if BattlefieldMapOptions then BattlefieldMapOptions.showPlayers = true end")
    end

    B.ApplySize(DB().bfSize)
    B.ApplyAlpha()
    B.ApplyZoom()
    ApplyUnitSizes(f)

    local db = DB()
    if db.bfPoint then
        f:ClearAllPoints()
        f:SetPoint(db.bfPoint, UIParent, db.bfPoint, db.bfX or 0, db.bfY or 0)
    end
    if grip then grip:SetShown(On("bfUnlock")) end
end

B.Frame = Frame

-- shared with later ZacUI files
ns.MapsBattlefield = B
