-- Maps_Skin - make the world map look like the rest of ZacUI.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHY THIS IS A SEPARATE PASS FROM Modules.worldmap. The existing skin
-- module runs at login and strips the chrome the map is wearing AT THAT
-- MOMENT - which is the fullscreen map's chrome. Maps_Frame then flips
-- the client to the windowed map, and the windowed map wears a DIFFERENT
-- set of furniture: MiniBorderLeft, MiniBorderRight, its own title bar,
-- its own maximise toggle. None of that existed when the skin pass ran,
-- so none of it was ever touched, and the result is a flat dark addon
-- wrapped in a carved wooden picture frame.
--
-- So the skin has to run AFTER the switch, and it has to run again every
-- time Blizzard re-syncs the window, because a display-state sync
-- re-shows the lot.
--
-- THE SCROLL CONTAINER IS SACRED. It holds the map canvas, its pins and
-- the exploration overlays. A texture sweep anywhere inside it deletes
-- the map itself. Everything below walks around it by identity, never by
-- name - names change between builds, the object does not.

local ADDON_NAME = ...
-- Zacui_Maps is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local Col = ns.Col
local FLAT = ns.FLAT
local Maps = ns.Maps
local Print = ns.Print
local SkinBackdrop = ns.SkinBackdrop
local UI = ns.UI
local ZUI = ns.ZUI

local DB, On = Maps.DB, Maps.On

local S = {}

local HEADER_H = 22
local FOOTER_H = 18

local header, installed

-- ============================================================
-- OUR FURNITURE GOES ONE STRATA ABOVE THE MAP
-- ============================================================
-- Frame level is not enough here and that is not obvious. The map canvas
-- lays its pin layers out at PIN_FRAME_LEVEL_* offsets that run into the
-- hundreds, so a header at map-level-plus-thirty is comfortably UNDER
-- the canvas. The symptom is a title bar that looks right, does nothing
-- when you drag it, and lets the zone underneath light up as you pass
-- over it - because the canvas, not the header, is what the mouse is
-- actually on.
--
-- Going up a strata sidesteps the whole competition. It is safe for
-- exactly the reason it is not safe for the tray: nothing foreign is
-- ever parented to these frames, so the only thing they can cover is the
-- map, which is the intent.
local STRATA_UP = Maps.STRATA_UP

local function LiftAboveCanvas(frame, map, level)
    if not frame or not frame.SetFrameStrata then return end
    frame:SetFrameStrata(STRATA_UP[map:GetFrameStrata()] or "HIGH")
    frame:SetFrameLevel(level or 10)
end

-- ============================================================
-- STRIPPING
-- ============================================================
-- Recursive, because the windowed map's furniture is spread across
-- BorderFrame, MaximizeMinimizeFrame, the title bar and a couple of
-- loose textures on the frame itself. Two things are never descended
-- into: the scroll container, and anything ZacUI made.
local function IsOurs(frame)
    return frame._zui_own == true or frame._zMapOwn == true
end

-- ============================================================
-- ONLY BLIZZARD'S OWN FURNITURE IS SWEPT
-- ============================================================
-- (2026-10-31, Zac: "there are some like grey squares on the map and
-- the resize handlers are wrong".) The sweep below used to take every
-- frame under WorldMapFrame. The world-map part (Zacui_WorldMap) hangs
-- its own tabs, grips, title-bar handle and menu off the same frame,
-- and the sweep blanked their icons and SkinControls boxed them - the
-- grey squares down the right edge were its tab rail with the pictures
-- taken away. Blizzard's furniture all exists the moment the map frame
-- does (it is XML), so the set of frames under it is taken ONCE, as
-- early as this file loads, and only those are ever swept or skinned.
-- Anything that arrives later belongs to someone else and is theirs.
-- A frame whose global name starts with WorldMap is Blizzard's whenever
-- it turns up (its pools name them so), and is swept too.
local known = setmetatable({}, { __mode = "k" })
local snapped = false
local function Snapshot(frame, canvas, depth)
    if not frame or depth > 5 or frame == canvas then return end
    known[frame] = true
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do Snapshot(child, canvas, depth + 1) end
    end
end
local function TakeSnapshot()
    if snapped then return end
    local map = _G.WorldMapFrame
    if not map then return end
    snapped = true
    Snapshot(map, map.ScrollContainer, 0)
end
local function IsBlizzards(frame)
    if known[frame] then return true end
    local name = frame.GetName and frame:GetName()
    return type(name) == "string" and name:sub(1, 8) == "WorldMap"
end
TakeSnapshot()

-- ============================================================
-- FOREVER'S MAP KEEPS ITS OWN BUTTONS (2026-11-07)
-- ============================================================
-- (Zac on WoW Forever: "text overlap on the map and buttons that are
-- blank".) Forever's map is the modern one, and the modern map hangs
-- its controls over the canvas as "overlay frames" (map.overlayFrames:
-- the tracking filter and its reset X, the map pin button, the floor
-- picker, the quest panel toggle, Blizzard's own coordinates...). Their
-- pictures are the buttons - the sweep below blanked them and SkinControls
-- boxed them, which is what the empty dark squares were. So on a map
-- that has overlay frames they are left as Blizzard draws them; only the
-- zone breadcrumb (NavBar) keeps ZacUI's treatment, and Blizzard's
-- coordinates step aside for ZacUI's strip (S.SyncCoordsPanel). The
-- Classic Era and TBC maps have no overlay frames, so nothing changes
-- there.
local overlaySet = setmetatable({}, { __mode = "k" })
local function NoteOverlays(map)
    for _, f in ipairs(type(map.overlayFrames) == "table" and map.overlayFrames or {}) do
        if f ~= map.NavBar then overlaySet[f] = true end
    end
end

-- Blizzard's own coordinate readout (the modern map's bottom-left
-- "Player: x, y (zone)") sits right where ZacUI's strip writes; while
-- ZacUI's coordinates are on, it is put away (and back when they go).
function S.SyncCoordsPanel(map)
    map = map or _G.WorldMapFrame
    if not (map and type(map.overlayFrames) == "table") then return end
    local ours = On("coords") and true or false
    for _, f in ipairs(map.overlayFrames) do
        if f.PlayerCoords and f.CursorCoords then
            if ours then
                f._zui_coordsAway = true
                f:SetAlpha(0)
                f:Hide()
            elseif f._zui_coordsAway then
                f._zui_coordsAway = nil
                f:SetAlpha(1)
                f:Show()
            end
        end
    end
end

-- ============================================================
-- THE MODERN MAP'S OWN BUTTONS, IN ZACUI'S LOOK (2026-11-07)
-- ============================================================
-- (Zac on Forever: the tracking filter and the quest-panel toggle were
-- Blizzard's pictures on dark boxes.) Forever's map (Blizzard_WorldMap/
-- Camelot) keeps three buttons over the canvas: the tracking filter (a
-- dropdown arrow picture, its red reset X on top), the map pin button and
-- the quest-panel toggle (two arrow pictures). Each becomes the icon
-- button the minimap's corners wear: a dark flat backing with ZacUI's 1px
-- border, the picture cropped inside (the pin keeps its own; the filter
-- gets the tracking eye, the toggle ZacUI's arrows), hover and press as
-- flat washes. Their clicks and dropdowns are still Blizzard's. Found by
-- the map's own keys, so the Classic map (no such keys) is never touched.
local MAP_BTN = 22
local function Wash(tex, r, g, b, a, btn)
    if not tex then return end
    tex:SetColorTexture(r, g, b, a)
    if tex.SetBlendMode then tex:SetBlendMode("ADD") end
    tex:ClearAllPoints()
    tex:SetAllPoints(btn)
end
local function SkinMapButton(btn, icon, flip)
    if type(btn) ~= "table" or btn._zMapBtn or not btn.GetRegions then return end
    btn._zMapBtn = true
    local keep = (icon == true) and (rawget(btn, "Icon") or rawget(btn, "icon")) or nil
    if keep ~= nil and type(keep) ~= "table" then keep = nil end
    for _, r in ipairs({ btn:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") and not r._zui_own and r ~= keep then
            r:SetTexture(nil)
            if r.SetAtlas then r:SetAtlas(nil) end
            r:SetAlpha(0)
        end
    end
    btn:SetSize(MAP_BTN, MAP_BTN)
    local back = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
    back._zui_own = true
    back:SetAllPoints()
    back:SetTexture(FLAT)
    btn._zMapBack = back
    AddPixelBorder(btn)
    local pic = keep
    if not pic then
        pic = btn:CreateTexture(nil, "ARTWORK")
        pic._zui_own = true
        pic:SetTexture(icon)
        if flip then pic:SetTexCoord(1, 0, 0, 1) end
    else
        pic:SetDrawLayer("ARTWORK")
        pic:SetAlpha(1)
        if pic.SetTexCoord then pic:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end
    pic:ClearAllPoints()
    pic:SetPoint("TOPLEFT", btn, "TOPLEFT", 4, -4)
    pic:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, 4)
    btn._zMapPic = pic
    if btn.GetNormalTexture then
        local n = btn:GetNormalTexture()
        if n then n:SetTexture(nil) n:SetAlpha(0) end
    end
    if btn.GetPushedTexture then Wash(btn:GetPushedTexture(), 1, 1, 1, 0.18, btn) end
    if btn.GetHighlightTexture then Wash(btn:GetHighlightTexture(), 1, 1, 1, 0.12, btn) end
    btn._zPaint = function(self)
        local c = Col("windowBg")
        self._zMapBack:SetVertexColor(c.r, c.g, c.b, 0.85)
        if not keep then
            local x = Col("xNormal")
            self._zMapPic:SetVertexColor(x.r, x.g, x.b, 1)
        end
    end
    btn:_zPaint()
    if not keep then
        btn:HookScript("OnEnter", function(self)
            local a = Col("accent")
            self._zMapPic:SetVertexColor(a.r, a.g, a.b, 1)
        end)
        btn:HookScript("OnLeave", function(self) self:_zPaint() end)
    end
    return btn
end

local TEX_EYE = "Interface\\Minimap\\Tracking\\None"
function S.SkinModernButtons(map)
    local track = rawget(map, "WorldMapTrackingOptionsButton")
    if type(track) == "table" then
        SkinMapButton(track, TEX_EYE)
        -- its reset X (only up with filters changed): small, in the corner
        local reset = rawget(track, "ResetButton")
        if type(reset) == "table" and not reset._zMapReset then
            reset._zMapReset = true
            reset:SetSize(12, 12)
            reset:ClearAllPoints()
            reset:SetPoint("CENTER", track, "TOPRIGHT", -2, -2)
        end
    end
    local pin = rawget(map, "WorldMapTrackingPinButton")
    if type(pin) == "table" then SkinMapButton(pin, true) end
    local toggle = rawget(map, "SidePanelToggle")
    if type(toggle) == "table" then
        if toggle.SetSize and not toggle._zMapBtn then
            toggle._zMapBtn = true
            toggle:SetSize(MAP_BTN, MAP_BTN)
        end
        -- open = reveal the quest panel to the right; close = fold it away
        if type(rawget(toggle, "OpenButton")) == "table" then SkinMapButton(toggle.OpenButton, ns.TEX_ARROWL, true) end
        if type(rawget(toggle, "CloseButton")) == "table" then SkinMapButton(toggle.CloseButton, ns.TEX_ARROWL, false) end
    end
end

local function StripChrome(frame, canvas, depth)
    if not frame or depth > 4 then return end
    if overlaySet[frame] then return end
    if frame == canvas or IsOurs(frame) or not IsBlizzards(frame) then return end

    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture")
                and not region._zui_own then
                region:SetTexture(nil)
                region:SetAtlas(nil)
                region:Hide()
            end
        end
    end
    -- NineSlice is a frame of its own with nine textures inside it, so
    -- the sweep above does not reach them.
    if type(frame.NineSlice) == "table" then
        frame.NineSlice:SetAlpha(0)
        frame.NineSlice:Hide()
    end

    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            StripChrome(child, canvas, depth + 1)
        end
    end
end

-- ============================================================
-- HEADER
-- ============================================================
-- The map's own title bar goes, and this replaces it: a thin strip over
-- the top edge of the canvas carrying the zone name. Over the canvas
-- rather than above it, so the map can run edge to edge - the empty dark
-- band under the old layout was the frame being taller than the canvas
-- it contained.
-- THE HEADER'S PARTS AND LOOK (2026-11-01). The real header and the
-- settings preview's sample are made and painted by these two: a fill
-- (the window colour at 82%), a 1px rule along the bottom (the accent at
-- half strength) and the zone name in the middle. Each colour and the
-- title's font are settings; unset, they are the theme's as before.
function S.PaintHeader(bar)
    local db = DB()
    if bar._zFill then bar._zFill:SetVertexColor(Maps.Color("headerBg", "windowBg", nil, 0.82)) end
    -- (2026-11-10, Zac: "the map header still uses the old styling") the
    -- flat header every other ZacUI window wears: a white hairline under
    -- it, the title white at the left. A picked colour still wins.
    if bar._zRule then bar._zRule:SetVertexColor(Maps.Color("headerRule", "text", "normal", 0.10)) end
    if bar.title then
        Maps.StyleText(bar.title, db.titleFont, UI.F.NORMAL)
        bar.title:_zPaint()
    end
end

function S.MakeHeader(bar)
    local fill = bar:CreateTexture(nil, "BACKGROUND")
    fill._zui_own = true
    fill:SetAllPoints()
    fill:SetTexture(FLAT)
    bar._zFill = fill

    local rule = bar:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    bar._zRule = rule

    bar.title = UI.Font(bar, UI.F.NORMAL, { cat = "text", key = "normal",
        justify = "LEFT" })
    bar.title:SetPoint("LEFT", bar, "LEFT", 12, 0)
    -- white unless a colour is picked on the Maps page, whoever repaints it
    bar.title._zPaint = function(self) self:SetTextColor(Maps.Color("titleColor", "text", "normal")) end

    bar._zPaint = S.PaintHeader
    bar:_zPaint()
    return bar
end

-- The window's own background: the theme's window colour at 95%
-- (SkinBackdrop), or the colour picked on the Maps page. For any frame
-- that has been through SkinBackdrop - the map, or the preview's sample.
function S.PaintWindowBg(frame)
    local tex = frame and frame._zui_cbg
    if tex then tex:SetVertexColor(Maps.Color("windowBg", "windowBg", nil, 0.95)) end
end

local function BuildHeader(map)
    local bar = CreateFrame("Frame", "ZacUIMapHeader", map)
    bar._zMapOwn = true
    bar:SetHeight(HEADER_H)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    LiftAboveCanvas(bar, map, 10)

    -- ============================================================
    -- THE HEADER MEETS THE MAP, WITH NOTHING SHOWING BETWEEN
    -- ============================================================
    -- Blizzard leaves a margin above its canvas for the title bar ZacUI
    -- has removed. A fixed-height header sitting in that margin does not
    -- fill it, so a thin band of window background shows between the
    -- bottom of the header and the top of the map - which reads as the
    -- header and the border not lining up.
    --
    -- Stretching the header down to the canvas closes it exactly,
    -- whatever the margin is on a given build. This is the same fix as
    -- the coordinate strip at the other end, and for the same reason:
    -- the gaps around Blizzard's canvas are ours to fill, not to guess
    -- the size of.
    local sc = map.ScrollContainer
    if sc then
        bar:SetPoint("BOTTOM", sc, "TOP", 0, 0)
        -- ...unless that makes it silly. A build with no margin would
        -- collapse the header to nothing, and a header with no height is
        -- indistinguishable from a header that failed to build.
        bar._zFitHeader = function()
            if bar._zHeaderFitted then return end
            local h = bar:GetHeight() or 0
            if h <= 0 then return end
            bar._zHeaderFitted = true
            if h < 12 or h > 60 then
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", 1, -1)
                bar:SetPoint("TOPRIGHT", -1, -1)
                bar:SetHeight(HEADER_H)
            end
        end
        bar:SetScript("OnUpdate", function(self)
            self._zFitHeader()
            if self._zHeaderFitted then self:SetScript("OnUpdate", nil) end
        end)
    end

    -- the fill, the rule and the title (S.MakeHeader, shared with the
    -- settings preview)
    S.MakeHeader(bar)

    -- THE HEADER IS THE TITLE BAR, so it has to be what you drag the
    -- window by. The map frame does have drag handling of its own, but a
    -- mouse-enabled header sitting on top of it means the drag never
    -- reaches the map - the bar swallows the button press and does
    -- nothing with it. Forwarding is the fix; taking the mouse off the
    -- bar is not, because then the canvas gets the click and pans the
    -- map instead of moving the window.
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        if not On("unlock") then return end
        map:StartMoving()
    end)
    bar:SetScript("OnDragStop", function()
        map:StopMovingOrSizing()
        if map.SetUserPlaced then map:SetUserPlaced(false) end
        Maps.SavePoint(map, DB())
    end)
    -- Right-click for the options, the same gesture the tray bar uses.
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and ns.OpenConfig then ns.OpenConfig("maps") end
    end)

    return bar
end

function S.UpdateTitle()
    if not header then return end
    local map = _G.WorldMapFrame
    local mapID = map and map.mapID
    local name
    if mapID and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        name = info and info.name
    end
    header.title:SetText(name or "Map")
end

-- ============================================================
-- LAYOUT: DO NOT MOVE BLIZZARD'S CANVAS
-- ============================================================
-- The previous version of this stretched the ScrollContainer to fill the
-- whole frame, to close the dark margin left behind when the border art
-- was stripped. It closed the margin and broke every click on the map.
--
-- The container is not where the map's coordinate maths happens. Inside
-- it sits the CANVAS CHILD, and Blizzard computes "where on the map is
-- the cursor" from that child's rect - its left edge, its width, its
-- top. Re-anchoring the container moved the goalposts without the child
-- being re-laid-out against them, so every cursor reading came out
-- shifted: hovering the top of the map reported 73% of the way down it,
-- and reaching a spot meant putting the pointer well to its right.
--
-- The container's geometry is therefore Blizzard's, permanently. What
-- this does instead is REMEMBER where Blizzard put it and put it back on
-- every pass, because the sweep and the display-state re-syncs can
-- otherwise leave it somewhere else. The margin is dealt with by sizing
-- the frame to suit the canvas, not by dragging the canvas to suit the
-- frame - see ASPECT in Maps_Frame.
local originalAnchors

local function RestoreCanvas(map)
    local sc = map.ScrollContainer
    if not sc or not sc.GetNumPoints then return end

    -- Recorded once, the first time we see it, while it is still exactly
    -- as Blizzard laid it out.
    if not originalAnchors then
        originalAnchors = {}
        for i = 1, sc:GetNumPoints() do
            local point, rel, relPoint, x, y = sc:GetPoint(i)
            originalAnchors[i] = { point = point, rel = rel,
                relPoint = relPoint, x = x, y = y }
        end
        if #originalAnchors == 0 then originalAnchors = nil end
    end

    if originalAnchors then
        sc:ClearAllPoints()
        for _, a in ipairs(originalAnchors) do
            sc:SetPoint(a.point, a.rel or map, a.relPoint, a.x, a.y)
        end

        -- ============================================================
        -- THE SAME GAP ON BOTH SIDES
        -- ============================================================
        -- Blizzard insets its canvas twenty pixels on the left and ten on
        -- the right - room for furniture ZacUI has removed - so the map
        -- sits visibly off-centre in its own window. It reads as a
        -- crooked border, which is what "the map is not equal on left and
        -- right" is.
        --
        -- The narrower gap wins. Widening the canvas to match the small
        -- side gains ten pixels of map; shrinking to match the large side
        -- would lose ten for nothing. Only the horizontal offsets are
        -- touched - the vertical ones carry the title bar and the bottom
        -- margin the coordinate strip lives in, and are not ours to
        -- flatten.
        local left, right
        for i = 1, sc:GetNumPoints() do
            local point, _, _, x = sc:GetPoint(i)
            if point == "TOPLEFT" or point == "BOTTOMLEFT" then
                left = math.max(left or 0, x or 0)
            elseif point == "TOPRIGHT" or point == "BOTTOMRIGHT" then
                right = math.min(right or 0, x or 0)
            end
        end
        if left and right and math.abs(left + right) > 1 then
            local gap = math.min(math.abs(left), math.abs(right))
            local fixed = {}
            for i = 1, sc:GetNumPoints() do
                local point, rel, relPoint, x, y = sc:GetPoint(i)
                if point == "TOPLEFT" or point == "BOTTOMLEFT" then
                    x = gap
                elseif point == "TOPRIGHT" or point == "BOTTOMRIGHT" then
                    x = -gap
                end
                fixed[#fixed + 1] = { point, rel, relPoint, x, y }
            end
            sc:ClearAllPoints()
            for _, a in ipairs(fixed) do
                sc:SetPoint(a[1], a[2] or map, a[3], a[4], a[5])
            end
        end
    end

    -- THE CANVAS MUST OUT-RANK THE FRAME THAT HOLDS IT, and this asserts
    -- it rather than assuming it. A child does not follow its parent's
    -- level, so anything that raises the map frame - including a past
    -- version of this very file, trying to get above the minimap buttons
    -- - leaves the mouse-enabled map frame sitting on top of its own
    -- canvas, swallowing every click meant for a zone. The map still
    -- looks perfectly fine while that is true, which is what made it
    -- hard to see.
    if sc.GetFrameLevel and sc:GetFrameLevel() <= map:GetFrameLevel() then
        sc:SetFrameLevel(map:GetFrameLevel() + 1)
    end
end

-- ============================================================
-- APPLY
-- ============================================================
function S.Apply()
    local map = _G.WorldMapFrame
    if not map then return end
    local canvas = map.ScrollContainer

    -- RE-ENTRANCY. This function calls OnFrameSizeChanged, which can
    -- make the client re-sync display state, which is hooked to call
    -- this function. Without the guard that is an unbounded loop that
    -- runs inside a single frame - and while dragging the resize grip it
    -- runs on every one of them, which is the other half of the shaking.
    if S.applying then return end
    -- And nothing here needs doing mid-drag: the grip is already setting
    -- the size, and re-anchoring the canvas underneath it is what the
    -- drag is fighting.
    if ns.MapsFrame and ns.MapsFrame.resizing then return end
    S.applying = true

    if not installed then
        installed = true
        TakeSnapshot()                  -- (the map frame arrived after this file loaded)
        header = BuildHeader(map)

        -- Blizzard puts all of this back on a display-state sync, and a
        -- sync happens on every maximise/minimise round trip - so the
        -- skin is re-applied rather than done once.
        if map.SynchronizeDisplayState then
            hooksecurefunc(map, "SynchronizeDisplayState", function()
                if On("unlock") or ZacUIDB.modules.maps then S.Apply() end
            end)
        end
        map:HookScript("OnShow", function() S.Apply() end)
        if map.OnMapChanged then
            hooksecurefunc(map, "OnMapChanged", S.UpdateTitle)
        end
    end

    NoteOverlays(map)
    StripChrome(map, canvas, 0)

    -- The named furniture the windowed map brings with it. Listed as
    -- well as swept because some of these are parented outside the map
    -- frame entirely and the recursive walk never reaches them.
    for _, name in ipairs({
        "MiniBorderLeft", "MiniBorderRight", "MiniWorldMapTitle",
        "WorldMapFrameSizeUpButton", "WorldMapFrameSizeDownButton",
        "WorldMapFrameTitle", "WorldMapFrameTitleBg", "WorldMapFrameBg",
        "WorldMapFrameNavBar", "WorldMapFrameTutorialButton",
    }) do
        local piece = _G[name]
        if piece then
            if piece.SetAlpha then piece:SetAlpha(0) end
            if piece.Hide then piece:Hide() end
        end
    end

    -- The maximise toggle. ZacUI owns sizing now - a button that snaps
    -- the window back to fullscreen and undoes it is worse than no
    -- button.
    local mm = map.MaximizeMinimizeFrame
    if mm then
        if mm.Hide then mm:Hide() end
        if mm.SetAlpha then mm:SetAlpha(0) end
    end
    -- Forever's (modern) map keeps its title bar parts on BorderFrame
    -- instead: the maximise toggle, the help-plate button, the portrait
    -- and the title ("Map & Quest Log", printed over ZacUI's header
    -- title - the jumbled title). ZacUI's header carries the title and
    -- owns sizing, so they go. Classic's BorderFrame has none of them.
    local bf = map.BorderFrame
    if bf then
        for _, key in ipairs({ "MaximizeMinimizeFrame", "Tutorial", "TitleContainer", "PortraitContainer" }) do
            local piece = bf[key]
            if type(piece) == "table" then
                if piece.SetAlpha then piece:SetAlpha(0) end
                if piece.Hide then piece:Hide() end
            end
        end
    end
    -- And the fullscreen dimmer behind it.
    if map.BlackoutFrame then
        map.BlackoutFrame:SetAlpha(0)
        map.BlackoutFrame:Hide()
    end

    -- ============================================================
    -- BLIZZARD'S OWN MAP CONTROLS
    -- ============================================================
    -- The tracking toggles and quest buttons that live on the map frame.
    -- Found structurally rather than by name: 1.15 has been renaming
    -- these for several patches, and a list of names is a list that
    -- silently resolves to nil after the next one. Anything inside the
    -- canvas is off limits - those are pins, and SkinButton on a pin
    -- deletes the pin's artwork.
    -- A BAR IS NOT A BUTTON (2026-11-11, Zac: "the map looks weird the
    -- background/border looks like its built out of multiple different
    -- windows and stitched together"). Blizzard's windowed map has an
    -- invisible Button across its title bar - the handle the stock map
    -- is dragged by. It is a Button, so it was skinned as one, and since
    -- every skinned button wears the raised plate (2026-11-10) it became
    -- a lighter slab with its own edge and top highlight, most of the
    -- window wide, sitting behind ZacUI's header: a second, shorter
    -- header inside the first. Anything that wide and that flat is a
    -- handle, not a control, and gets no skin; one skinned before its
    -- size was known (the first pass can come before the layout) has
    -- what was drawn on it taken off again.
    local function IsBarNotButton(child)
        local name = child.GetName and child:GetName()
        if type(name) == "string" and name:find("TitleButton", 1, true) then return true end
        local l = child.GetLeft and child:GetLeft()
        local r = child.GetRight and child:GetRight()
        local w = (l and r) and (r - l) or (child.GetWidth and child:GetWidth()) or 0
        local h = child.GetHeight and child:GetHeight() or 0
        return w >= 240 and w > h * 4
    end
    local function Unskin(child)
        if child._zMapBar then return end
        child._zMapBar = true
        child._zPaint = function() end            -- (the plate repaints itself on hover)
        if child.GetRegions then
            for _, region in ipairs({ child:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("Texture") and region.SetAlpha then
                    region:SetAlpha(0)
                end
            end
        end
    end
    local function SkinControls(root, depth)
        if not root or depth > 2 or root == canvas or IsOurs(root) then return end
        if not root.GetChildren then return end
        for _, child in ipairs({ root:GetChildren() }) do
            if child ~= canvas and not IsOurs(child) and IsBlizzards(child) and not overlaySet[child] then
                local otype = child.GetObjectType and child:GetObjectType()
                if otype == "Button" or otype == "CheckButton" then
                    if IsBarNotButton(child) then
                        -- (whoever skinned it: this pass earlier, or the
                        -- general skinner at login)
                        local Z = ns.ZUI
                        if child._zMapCtl or rawget(child, "_zPlateLook") or rawget(child, "_zui_bg")
                            or (Z and Z.skinned and Z.skinned[child]) then
                            Unskin(child)
                        end
                        child._zMapCtl = true
                        if Z and Z.skinned then Z.skinned[child] = true end   -- and nobody skins it later
                    elseif not child._zMapCtl and ns.SkinButton then
                        child._zMapCtl = true
                        pcall(ns.SkinButton, child)
                    end
                end
                SkinControls(child, depth + 1)
            end
        end
    end
    SkinControls(map, 0)
    S.SkinModernButtons(map)
    S.SyncCoordsPanel(map)

    SkinBackdrop(map, "windowBg", 0.95)
    S.PaintWindowBg(map)
    if not map._zMapBorder then
        map._zMapBorder = true
        AddPixelBorder(map)
    end

    -- ============================================================
    -- NOTHING FLOATS OVER THE MAP - AND NOT BY RAISING THE MAP
    -- ============================================================
    -- The previous attempt here was `map:SetFrameLevel(120)`, to put the
    -- map above the tray's minimap buttons at MEDIUM/8. It does do that,
    -- and it breaks the map.
    --
    -- A child frame does not follow its parent's level. Raising
    -- WorldMapFrame to 120 left its own ScrollContainer down at 2, which
    -- means the map FRAME - mouse-enabled, because that is how you drag
    -- it - ended up on top of its own canvas and swallowed every click
    -- meant for a zone. The buttons were still visible too, because they
    -- were never above the frame, only above the canvas.
    --
    -- Fighting z-order here cannot work: the tray has to be at MEDIUM to
    -- be clickable at all (LibDBIcon pins its buttons there and wins),
    -- the canvas has to be above the map frame to be clickable, and the
    -- buttons cannot be below the canvas and above the frame at once.
    -- So the tray simply stands down while the map is open, which is
    -- what you wanted to see anyway - see Maps_Frame.
    --
    -- The map's own level is left exactly as Blizzard set it.

    RestoreCanvas(map)

    -- ============================================================
    -- THE CLOSE BUTTON
    -- ============================================================
    -- OURS, NOT BLIZZARD'S RESKINNED. The first version took Blizzard's
    -- close button and restyled it, which does not survive contact with
    -- this file: Modules.worldmap has ALREADY skinned that button at
    -- login, so the X drawn on it is a ZacUI texture - and the sweep
    -- above then blanks it, while SkinCloseButton refuses to redraw
    -- because the button is already marked skinned. The result is a
    -- close button that is present, clickable and completely invisible.
    --
    -- A button of our own has no such history. Blizzard's is hidden.
    local blizzClose = _G.WorldMapFrameCloseButton
        or (map.BorderFrame and map.BorderFrame.CloseButton)
        or map.CloseButton
    if blizzClose and blizzClose.Hide then
        blizzClose:Hide()
        if blizzClose.SetAlpha then blizzClose:SetAlpha(0) end
    end

    if not S.close and header then
        local x = UI.CloseX(header, 18, function()
            if map.Hide then map:Hide() end
        end)
        x._zui_own = true
        x._zMapOwn = true
        -- (the settings windows' X: white, dim at rest)
        x._zSet = true
        x:_zPaint()
        x:SetPoint("RIGHT", header, "RIGHT", -5, 0)
        LiftAboveCanvas(x, map, 20)
        UI.Tooltip(x, "Close", "Escape closes it too.")
        S.close = x
    end
    if S.close then
        S.close:Show()
        S.close:_zPaint()
    end

    -- The resize grip sits above the coordinate strip rather than in the
    -- very corner, where the strip would draw over it.
    local grip = _G.ZacUIMapGrip
    if grip then
        grip:ClearAllPoints()
        grip:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -2, FOOTER_H + 2)
        LiftAboveCanvas(grip, map, 20)
        grip:_zPaint()
    end

    if header then
        header:SetShown(true)
        LiftAboveCanvas(header, map, 10)
        header:_zPaint()
    end
    S.UpdateTitle()

    -- The coordinate strip is built by Maps_Frame and parented to the
    -- canvas; it is lifted above the pins here so a flight point cannot
    -- draw over the readout.
    local coords = _G.ZacUIMapCoords
    if coords then
        coords._zMapOwn = true
        coords:SetHeight(FOOTER_H)
        LiftAboveCanvas(coords, map, 10)
    end

    S.applying = nil
end

-- ============================================================
-- WHAT IS ON THE CANVAS
-- ============================================================
-- S.Dump below walks the map and deliberately STOPS at the canvas,
-- because its job is finding leftover Blizzard chrome and the canvas is
-- not chrome. That was a reasonable line to draw and it made the tool
-- useless for the next question, which was "there is a big pale circle
-- three quarters of the way across the map and it does not follow me".
-- Every pin, blip, arrow and marker in the game lives on the canvas, so
-- the one dump we had could not see a single one of them.
--
-- Positions are printed as a FRACTION of the canvas rather than in
-- pixels, because that is the coordinate anyone reading a screenshot can
-- check: "0.81, 0.75" is somewhere you can point at. Pixels depend on
-- the window size and tell you nothing on their own.
function S.CanvasDump()
    local map = _G.WorldMapFrame
    local sc = map and map.ScrollContainer
    local canvas = sc and (sc.Child or (sc.GetCanvas and sc:GetCanvas()))
    if not canvas then
        Print("no map canvas - is the map open?")
        return
    end

    local cw = canvas:GetWidth() or 0
    local ch = canvas:GetHeight() or 0
    Print("--- map canvas --- " .. math.floor(cw) .. "x" .. math.floor(ch)
        .. "  map " .. tostring(map.mapID))
    if cw <= 0 or ch <= 0 then
        Print("the canvas has no size yet; open the map first.")
        return
    end

    local cl, cb = canvas:GetLeft(), canvas:GetBottom()
    local function Where(frame)
        if not cl or not frame.GetCenter then return "?" end
        local x, y = frame:GetCenter()
        if not x then return "unplaced" end
        return string.format("%.2f, %.2f", (x - cl) / cw, 1 - ((y - cb) / ch))
    end

    local n = 0
    local function Describe(frame, kind)
        if frame.IsShown and not frame:IsShown() then return end
        if (frame.GetAlpha and frame:GetAlpha() or 1) <= 0 then return end
        local w = frame.GetWidth and frame:GetWidth() or 0
        local h = frame.GetHeight and frame:GetHeight() or 0
        -- Anything under two pixels is a shadow or a spacer, not a marker
        -- somebody is complaining about.
        if w < 2 and h < 2 then return end
        n = n + 1
        local tex = ""
        if frame.GetTexture then
            tex = "  " .. tostring(frame:GetTexture() or
                (frame.GetAtlas and frame:GetAtlas()) or "?"):sub(-40)
        end
        Print(string.format("|cffffd100%s|r %s  %dx%d at %s%s",
            kind,
            (frame.GetName and frame:GetName() or frame._zui_own and "ZacUI"
                or "unnamed"),
            math.floor(w), math.floor(h), Where(frame), tex))
    end

    if canvas.GetChildren then
        for _, child in ipairs({ canvas:GetChildren() }) do
            Describe(child, child._zui_own and "ours" or "pin ")
            -- One level down: a pin is usually a frame with its art on a
            -- texture inside it, and the art is what you can see.
            if child.GetRegions and child.IsShown and child:IsShown() then
                for _, r in ipairs({ child:GetRegions() }) do
                    if r.IsObjectType and r:IsObjectType("Texture") then
                        Describe(r, "  art")
                    end
                end
            end
        end
    end
    if canvas.GetRegions then
        for _, r in ipairs({ canvas:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then
                Describe(r, "tex ")
            end
        end
    end

    Print(n .. " visible thing" .. (n == 1 and "" or "s")
        .. " on the canvas. Your own marker should sit where you are;")
    Print("anything that does not move when you do is not tracking you.")
end

-- ============================================================
-- DIAGNOSTIC
-- ============================================================
-- WHAT IS STILL BLIZZARD. Four rounds went into the button tray guessing
-- at "there is still default art visible" from screenshots, and a
-- screenshot cannot tell you which frame owns a given pixel. This walks
-- the map and prints every child and every texture that is still shown,
-- so the answer takes one round instead of four.
function S.Dump()
    local map = _G.WorldMapFrame
    if not map then
        Print("no world map frame.")
        return
    end
    Print("--- world map tree ---")
    local shown = 0

    local function Walk(frame, depth, label)
        if depth > 3 then return end
        local pad = string.rep("  ", depth)
        if frame == map.ScrollContainer then
            Print(pad .. "|cff66ff66" .. label .. " (the canvas - left alone)|r")
            return
        end
        local ours = IsOurs(frame) and " |cff66ff66[ours]|r" or ""
        Print(string.format("%s%s%s shown=%s", pad, label,
            ours, tostring(frame.IsShown and frame:IsShown())))

        if frame.GetRegions then
            for _, r in ipairs({ frame:GetRegions() }) do
                if r.IsObjectType and r:IsObjectType("Texture")
                    and r.IsShown and r:IsShown()
                    and (r.GetAlpha and r:GetAlpha() or 1) > 0 then
                    local tex = (r.GetTexture and r:GetTexture())
                        or (r.GetAtlas and r:GetAtlas()) or "?"
                    if not r._zui_own then
                        shown = shown + 1
                        Print(string.format("%s  |cffff9900tex %s|r", pad,
                            tostring(tex):sub(1, 44)))
                    end
                end
            end
        end
        if frame.GetChildren then
            for i, child in ipairs({ frame:GetChildren() }) do
                local name = (child.GetName and child:GetName())
                    or ("<child " .. i .. ">")
                Walk(child, depth + 1, name)
            end
        end
    end

    Walk(map, 0, "WorldMapFrame")
    Print("Blizzard textures still visible: "
        .. (shown == 0 and "|cff66ff66none|r" or ("|cffff9900" .. shown .. "|r")))
    -- GEOMETRY, because "the click handler is off" is a geometry
    -- question and no screenshot can answer it. Blizzard works out where
    -- the cursor is on the map from the CANVAS CHILD's rect, so that is
    -- the rect worth printing - the container's own size is not what the
    -- maths uses, which is exactly the mistake that caused the offset.
    local sc = map.ScrollContainer
    if sc then
        Print(string.format("frame     %.0fx%.0f at %.0f,%.0f",
            map:GetWidth() or 0, map:GetHeight() or 0,
            map:GetLeft() or 0, map:GetBottom() or 0))
        Print(string.format("container %.0fx%.0f at %.0f,%.0f  (inset l%.0f r%.0f t%.0f b%.0f)",
            sc:GetWidth() or 0, sc:GetHeight() or 0,
            sc:GetLeft() or 0, sc:GetBottom() or 0,
            (sc:GetLeft() or 0) - (map:GetLeft() or 0),
            (map:GetRight() or 0) - (sc:GetRight() or 0),
            (map:GetTop() or 0) - (sc:GetTop() or 0),
            (sc:GetBottom() or 0) - (map:GetBottom() or 0)))
        local child = sc.Child or (sc.GetCanvas and sc:GetCanvas())
        if child and child.GetWidth then
            Print(string.format("canvas    %.0fx%.0f at %.0f,%.0f  |cffffd100<- the cursor maths uses this|r",
                child:GetWidth() or 0, child:GetHeight() or 0,
                child:GetLeft() or 0, child:GetBottom() or 0))
        else
            Print("canvas    |cffff9900not reachable|r")
        end
        if sc.GetNormalizedCursorPosition then
            local nx, ny = sc:GetNormalizedCursorPosition()
            if nx then
                Print(string.format("cursor reads %.1f, %.1f right now", nx * 100, ny * 100))
            end
        end
    end
end

-- A look setting changed on the Maps page: the header and the window
-- background repainted where they stand, nothing rebuilt.
function S.Repaint()
    if header and header._zPaint then header:_zPaint() end
    local map = _G.WorldMapFrame
    if map and map._zui_cbg then S.PaintWindowBg(map) end
end

S.HEADER_H = HEADER_H
S.FOOTER_H = FOOTER_H
S.RestoreCanvas = RestoreCanvas
S.StripChrome = StripChrome

-- shared with later ZacUI files
ns.MapsSkin = S
