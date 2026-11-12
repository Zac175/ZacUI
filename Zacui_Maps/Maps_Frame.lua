-- Maps_Frame - the world map window itself: detaching it from the panel
-- manager, scaling it, fading it, zooming it, and the coordinate readout.
-- Part of ZacUI; load order is set by the TOC.
--
-- SCALE, NOT SIZE - and this is a reversal, so the reasoning is kept.
--
-- The first version resized the frame, on the theory that the canvas
-- recomputes its base scale from the frame's dimensions and would
-- therefore just work. It does recompute, and it does work, and it costs
-- more than it saves: a fixed-shape window letterboxes zone art of a
-- different shape, so the window had to follow each zone's aspect ratio,
-- which meant re-shaping on every map change and a pile of arithmetic
-- around minimizedWidth.
--
-- Both of the addons that solve this problem well - ElvUI and Leatrix -
-- scale the frame instead, and both fix the one thing scaling breaks in
-- the same place: the scroll container's own cursor getter. That is the
-- root. Everything downstream of it - panning, zoom-to-cursor, clicking
-- a zone, pin hit-testing and the coordinate readout - is computed from
-- that one function, so correcting it there fixes all of them at once,
-- and no other geometry has to be touched at all.
--
-- THE MAP FRAME TAKES NO MOUSE. ElvUI turns it off outright and lets the
-- scroll container inside keep its own. That is what makes it impossible
-- for the frame to sit on top of its own canvas and swallow clicks - a
-- bug this file has now shipped twice. Dragging moves to the header,
-- which is a frame we own and can reason about.

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
local UI = ns.UI

local DB, On = Maps.DB, Maps.On

local F = {}

-- Blizzard's own windowed map is 1024 wide; the scale slider is
-- expressed against it so "90%" means something you can picture.
local BASE_W = 1024
local MIN_SCALE, MAX_SCALE = 0.35, 1.6

local installed = false
local coordsFrame

-- ============================================================
-- DETACH
-- ============================================================
-- Blizzard's UIPanel manager owns the world map: it decides where the
-- map sits, and it closes the map when another panel wants the space.
-- Both have to go before the window can be a window.
local function Detach(map)
    -- Taking it out of the layout system is what stops the manager from
    -- re-anchoring it and from closing it for the character sheet.
    map:SetAttribute("UIPanelLayout-area", nil)
    map:SetAttribute("UIPanelLayout-enabled", false)

    -- ...but leaving the panel system also means losing Escape, which is
    -- how everyone closes this window. UISpecialFrames puts that back.
    local found = false
    for _, name in ipairs(UISpecialFrames) do
        if name == "WorldMapFrame" then found = true break end
    end
    if not found then table.insert(UISpecialFrames, "WorldMapFrame") end

    -- The windowed map rather than the fullscreen one. pcall because a
    -- CVar that does not exist on a given build throws rather than
    -- returning nil, and this is not worth taking the module down for.
    -- SETUP2: through ns.CVar (recorded; put back when Maps is off)
    local function Set(name, value)
        if ns.CVar then ns.CVar.Set(name, value, "maps") else pcall(SetCVar, name, value) end
    end
    Set("miniWorldMap", 1)

    -- Blizzard has its own map opacity system driven by a CVar. Ours
    -- would multiply with it, so it is zeroed once and left alone.
    Set("worldMapOpacity", 0)
    if WorldMapFrame_SetOpacity then pcall(WorldMapFrame_SetOpacity, 0) end

    -- SetIgnoreParentScale IS DELIBERATELY NOT TOUCHED, and that matters
    -- more than it looks. The cursor correction below divides by the map
    -- frame's scale, on the assumption that the scroll container's own
    -- effective scale does NOT already include it. Forcing the container
    -- to inherit parent scale would put the frame's scale into that
    -- number as well, and the correction would then divide by it twice -
    -- an error that grows with distance from the top-left corner, which
    -- is exactly the shape of the "I have to put my mouse way over to
    -- the right" symptom. ElvUI leaves both alone for the same reason.
    map:SetClampedToScreen(true)
end

-- ============================================================
-- WHERE IS THE CURSOR ON THE MAP
-- ============================================================
-- Wrong three times, three different ways, and every one was the same
-- root: scaling the frame breaks the container's own cursor getter, and
-- everything else asks that getter.
--
-- Previous attempts patched further downstream each time - first the
-- coordinate readout, then GetNormalizedCursorPosition - which fixes
-- whatever you happened to be looking at and leaves the rest wrong. The
-- container's GetCursorPosition is the bottom of the stack: panning,
-- zoom-to-cursor, clicking a zone, pin hit-testing and the readout all
-- come through it. Correct it there and there is nothing left to correct.
--
-- The correction itself is one divide. Blizzard's version already
-- divides the raw cursor by the container's effective scale; a scale on
-- the FRAME is not in that number, so it goes in here.
local function InstallCursorMath(map)
    local sc = map.ScrollContainer
    if not sc or sc._zCursorMath then return end
    sc._zCursorMath = true

    local original = sc.GetCursorPosition
    if type(original) ~= "function" then return end
    sc.GetCursorPosition = function(self, ...)
        local x, y = original(self, ...)
        if not x then return x, y end
        local scale = map:GetScale() or 1
        if scale == 0 then scale = 1 end
        return x / scale, y / scale
    end
end

-- ============================================================
-- SCALE
-- ============================================================
-- One call. Everything that used to be here - the aspect ratio, the
-- per-zone reshaping, minimizedWidth, OnFrameSizeChanged - existed to
-- serve resizing, and resizing is gone.
function F.ApplySize(value)
    local map = _G.WorldMapFrame
    if not map then return end
    local db = DB()
    value = math.max(MIN_SCALE, math.min(MAX_SCALE, tonumber(value) or db.scale))
    db.scale = value
    -- never rescaled mid-animation: the end of an opening animation puts
    -- back the scale it started from
    if ns.Motion and ns.Motion.IsPlaying(map) then ns.Motion.Stop(map) end
    map:SetScale(value)
end

-- The corner grip. A slider in the options is fine for a one-off, but
-- sizing a window is something you want to do by looking at it.
--
-- THE GRIP: ZacUI's solid corner (UI.GripArt), muted at rest and the
-- accent, a little larger, under the mouse or while it is being pulled.
-- (It was six dots in a triangle until 2026-11-11.)
local function BuildGrip(map)
    local grip = CreateFrame("Button", "ZacUIMapGrip", map)
    -- Marked as ours BEFORE anything else touches it: the skin pass
    -- sweeps every texture on this frame's children, and an unmarked
    -- grip comes out invisible.
    grip._zui_own = true
    grip._zMapOwn = true
    grip:SetSize(16, 16)
    grip:EnableMouse(true)

    UI.GripArt(grip, { layer = "OVERLAY", inset = 1,
        rest = function()
            local c = GetColor("text", "disabled")
            return c.r, c.g, c.b, 0.8
        end,
        hot = function()
            local c = Col("accent")
            return c.r, c.g, c.b, 1
        end })
    grip._zPaint = UI.GripPaint
    grip:_zPaint()
    grip:SetScript("OnEnter", function(self) UI.GripLit(self, true) end)
    grip:SetScript("OnLeave", function(self) UI.GripLit(self, false) end)

    -- Sizing by hand rather than through StartSizing. StartSizing needs
    -- SetResizable plus resize bounds whose API has moved twice, and it
    -- sizes both axes independently - which for this frame means the
    -- canvas letterboxes the moment the aspect drifts. Driving it from
    -- the cursor keeps one axis derived from the other by construction.
    -- ============================================================
    -- RESIZING WITHOUT THE JITTER
    -- ============================================================
    -- The first version re-anchored the frame on EVERY OnUpdate, right
    -- after resizing it. Three things then fight each other sixty times
    -- a second: the resize moves the bottom-right corner, the re-anchor
    -- moves the whole frame back, and SetClampedToScreen shoves it in
    -- from the edge - and the window shakes.
    --
    -- None of the re-anchoring is necessary. A frame anchored by its
    -- TOP-LEFT already grows right and down when it is resized. So the
    -- anchor is converted to TOPLEFT exactly once, on mouse-down, and
    -- after that the drag only ever sets a size.
    --
    -- Clamping is off for the duration too. Its whole job is to shove a
    -- frame back on screen, which during a resize means shoving it away
    -- from the corner the maths is measuring against.
    -- DRAGS SCALE, IN ONE COORDINATE SPACE.
    --
    -- The first version mixed two. GetCursorPosition returns SCREEN
    -- pixels; GetLeft returns the frame's edge in the frame's OWN scaled
    -- space. Subtracting one from the other produces a distance in no
    -- units at all, and the ratio built from it lands outside the scale
    -- clamp on the first update - so the map jumped to its smallest or
    -- largest size the instant the grip was touched, which is why it
    -- appeared to vanish.
    --
    -- Everything below is screen pixels: the frame's edge is multiplied
    -- by its effective scale to get there, and the cursor is already
    -- there. Nothing is divided by anything.
    -- ============================================================
    -- THE DIAGONAL, NOT THE WIDTH
    -- ============================================================
    -- This measured the cursor's X ONLY - `local cx = GetCursorPosition()`
    -- throws the second return away - so dragging the grip downwards did
    -- nothing at all and the map could only be sized by moving sideways.
    -- On a corner grip that is exactly backwards: the gesture everyone
    -- makes is diagonal.
    --
    -- Distance from the map's TOP-LEFT corner to the cursor is the right
    -- measure for a bottom-right grip: it grows whichever way you pull,
    -- it is the corner that stays still while the window grows, and
    -- because scale is one number the result is proportional for free.
    local function CornerDistance(map, cx, cy)
        local eff = map:GetEffectiveScale() or 1
        local left, top = map:GetLeft(), map:GetTop()
        if not left or not top or eff == 0 then return nil end
        local dx = cx - left * eff
        local dy = top * eff - cy
        return math.sqrt(dx * dx + dy * dy)
    end

    grip:SetScript("OnMouseDown", function(self)
        if not On("unlock") then return end
        local startDist = CornerDistance(map, GetCursorPosition())
        -- Grabbing the grip while the map is a sliver would make every
        -- pixel of movement an enormous multiplier.
        if not startDist or startDist < 40 then return end

        local startScale = map:GetScale() or 1
        map:SetClampedToScreen(false)
        F.resizing = true
        UI.GripHold(self)

        local wait = 0
        self:SetScript("OnUpdate", function(_, dt)
            -- THE BUTTON IS NOT WHERE THE DRAG ENDS. A grip is a 16px
            -- square and the cursor leaves it immediately; if the button
            -- comes up anywhere else, OnMouseUp never fires on the grip
            -- and this handler keeps scaling the map for the rest of the
            -- session, following the cursor to whichever clamp it reaches
            -- first. That is what "my map disappears" was.
            --
            -- Asking the client whether the button is still down needs no
            -- cooperation from whatever frame the release landed on.
            if not IsMouseButtonDown("LeftButton") then
                F.StopResize()
                return
            end

            wait = wait + dt
            if wait < 0.03 then return end
            wait = 0
            local dist = CornerDistance(map, GetCursorPosition())
            if not dist or dist < 40 then return end
            F.ApplySize(startScale * (dist / startDist))
        end)
    end)

    function F.StopResize()
        grip:SetScript("OnUpdate", nil)
        if not F.resizing then return end
        F.resizing = nil
        map:SetClampedToScreen(true)
        Maps.SavePoint(map, DB())
        if ns.RefreshConfig then ns.RefreshConfig() end
    end

    grip:SetScript("OnMouseUp", function() F.StopResize() end)
    -- Closing the map mid-drag is the other way to strand it.
    map:HookScript("OnHide", function() F.StopResize() end)
    return grip
end

-- ============================================================
-- MOVING
-- ============================================================
-- THE MAP FRAME TAKES NO MOUSE AT ALL.
--
-- It used to be mouse-enabled so it could be dragged, and that is what
-- made it possible for the frame to end up over its own canvas and eat
-- every click meant for a zone - twice. ElvUI turns it off outright and
-- lets the scroll container inside keep its own handling, which makes
-- the whole failure mode unreachable rather than merely fixed.
--
-- Dragging moves to the header, which is a frame ZacUI made and can
-- reason about. See Maps_Skin.
local function MakeMovable(map)
    map:SetMovable(true)
    map:EnableMouse(false)
    if map.EnableKeyboard then map:EnableKeyboard(false) end

    -- Blizzard's fullscreen dimmer sits behind the windowed map and takes
    -- clicks that should reach the world behind it.
    if map.BlackoutFrame then
        if map.BlackoutFrame.Blackout and map.BlackoutFrame.Blackout.SetTexture then
            map.BlackoutFrame.Blackout:SetTexture(nil)
        end
        map.BlackoutFrame:EnableMouse(false)
    end

    if map.SynchronizeDisplayState then
        hooksecurefunc(map, "SynchronizeDisplayState", function()
            if not On("unlock") then return end
            local db = DB()
            if db.point then Maps.RestorePoint(map, db, "CENTER", 0, 0) end
        end)
    end
end

-- ============================================================
-- FITTING THE WINDOW TO THE ART - REMOVED, AND WHY
-- ============================================================
-- A version of this file reshaped the window to each map's aspect ratio
-- to get rid of the empty bands Blizzard leaves down the sides of a
-- continent map. It made things worse and it is worth writing down why
-- rather than leaving a gap where it was.
--
-- The arithmetic was right and the assumption underneath it was not: it
-- set the window's height and expected the scroll container to follow.
-- It does not follow far enough, so the extra height became a black slab
-- under the map with the window's fill, the container's own background
-- and the coordinate strip all ending at different places inside it -
-- which is what "why is the map background multiple parts" was looking
-- at. Trading symmetrical side bands for an asymmetric black gap and
-- three visible seams is not a fix.
--
-- The side bands are Blizzard fitting the art inside the canvas without
-- distorting it. ElvUI lives with them. Making them go away means
-- resizing the container as well, which means owning its layout, which
-- is the thing Maps_Skin's RestoreCanvas exists to avoid - it restores
-- Blizzard's anchors precisely because stretching the canvas by hand
-- broke the map twice before. Not worth it for some empty space at the
-- edges.
--
-- The scale grip changes the whole window and the art scales with it, so
-- the bands scale too and never grow. That is the honest answer.

-- ============================================================
-- FADE
-- ============================================================
-- Two alphas: one while you are running, one while you are standing
-- still, so the map can be left open without blinding you.
-- OUR OWN FADER, not Blizzard's.
--
-- PlayerMovementFrameFader looks like exactly the right tool and it is
-- half-finished: its duration argument was never wired up, so the fade
-- is whatever Blizzard's internals feel like. ElvUI removes the map from
-- it deliberately, with a comment to that effect, and runs its own
-- ticker instead. Having tried the Blizzard one here first and got a
-- fade that ignored the duration setting, that judgement is worth
-- borrowing.
--
-- The whole thing is one throttled tick. Ten times a second is far more
-- than enough for an opacity ramp and costs nothing measurable.
local fadeDriver

local function TargetAlpha()
    local db = DB()
    if not On("fade") then return 1 end
    -- Hovering the map while running is the one moment you are certainly
    -- reading it, so that outranks the movement state.
    if db.noFadeUnderCursor and _G.WorldMapFrame:IsMouseOver() then
        return db.stillAlpha
    end
    if IsPlayerMoving and IsPlayerMoving() then return db.movingAlpha end
    return db.stillAlpha
end

-- One tick of the fade: a fraction of the remaining distance each tenth
-- of a second (fadeSpeed, 0.35 - about 0.7 s to settle). Shared with the
-- settings preview, which fades its sample map the same way.
function F.FadeStep(current, target, speed)
    local diff = target - current
    if math.abs(diff) < 0.01 then return target, true end
    -- Move a fraction of the remaining distance each tick: it settles
    -- quickly, never overshoots, and needs no timer bookkeeping.
    local step = math.max(0.05, math.min(1, speed or 0.35))
    return current + diff * step, false
end

-- The other things that write the map's alpha for a moment - the opening
-- animation and the dip over a zone change - have it to themselves while
-- they run; the fade picks up from wherever they leave it.
local function Busy(map)
    if F.openPending then return true end
    if F.blinkFrame and F.blinkFrame:IsShown() then return true end
    return ns.Motion and ns.Motion.IsPlaying(map) or false
end

local function FadeTick(_, elapsed)
    local map = _G.WorldMapFrame
    if not map or not map:IsShown() then return end
    fadeDriver.wait = (fadeDriver.wait or 0) + elapsed
    if fadeDriver.wait < 0.1 then return end
    fadeDriver.wait = 0
    if Busy(map) then return end

    local target = TargetAlpha()
    local current = map:GetAlpha() or 1
    local nextA, settled = F.FadeStep(current, target, DB().fadeSpeed)
    if settled then
        if current ~= target then map:SetAlpha(target) end
        return
    end
    map:SetAlpha(nextA)
end
F.TargetAlpha = TargetAlpha

function F.ApplyFade()
    local map = _G.WorldMapFrame
    if not map then return end

    if not fadeDriver then
        fadeDriver = CreateFrame("Frame", nil, map)
        fadeDriver:SetScript("OnUpdate", FadeTick)
    end

    -- Applied immediately as well as on the tick. Without this the
    -- setting appears to do nothing until you move, which reads as a
    -- broken option - the same complaint the Blizzard fader produced.
    if not Busy(map) then map:SetAlpha(TargetAlpha()) end
end

-- ============================================================
-- OPENING
-- ============================================================
-- The map has always simply appeared, and with the shipped "none" it
-- still does. Any other style plays through ns.Motion (Appearance >
-- Motion's switch and speed apply) one frame after the map shows: the
-- window is put in its place on show (the remembered point, the
-- world-map part's own window), and an animation started before that
-- would put back the place it started from. The map is held at nothing
-- for that one frame, so it is never seen at rest before it animates.
local function InstallOpening(map)
    map:HookScript("OnShow", function(self)
        local spec = DB().openAnim
        if not (ns.Motion and type(spec) == "table" and spec.style and spec.style ~= "none") then return end
        if not ns.Motion.Enabled() then return end
        F.openPending = true
        self:SetAlpha(0)
        local function go()
            F.openPending = nil
            self:SetAlpha(TargetAlpha())
            if not self:IsShown() then return end
            ns.Motion.Play(self, DB().openAnim, "in")
        end
        if RunNextFrame then RunNextFrame(go) else C_Timer.After(0, go) end
    end)
end

-- ============================================================
-- THE DIP OVER A ZONE CHANGE
-- ============================================================
-- A short dip to dark and back, so a new map fades in rather than
-- snapping: down to scrollFadeDepth of where it was, back over
-- scrollFadeTime (0.3 and 0.25 s, as it always was). Made per frame, so
-- the settings preview dips its sample map with this same code.
-- Returns the blink function and its driver frame.
function F.NewBlink(frame)
    local blink = CreateFrame("Frame", nil, frame)
    blink:Hide()
    blink:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        local k = (self.secs and self.secs > 0) and math.min(1, self.t / self.secs) or 1
        frame:SetAlpha(self.from + (self.to - self.from) * k)
        if k >= 1 then self:Hide() end
    end)
    local function Blink(to)
        local db = DB()
        -- a dip already on its way back keeps the alpha it is going back to
        if blink:IsShown() and blink.to then to = blink.to end
        to = to or frame:GetAlpha() or 1
        local secs = Maps.Time(tonumber(db.scrollFadeTime) or 0.25)
        if secs <= 0 then
            blink:Hide()
            frame:SetAlpha(to)
            return
        end
        blink.to = to
        blink.from = to * math.max(0, math.min(1, tonumber(db.scrollFadeDepth) or 0.3))
        blink.t, blink.secs = 0, secs
        frame:SetAlpha(blink.from)
        blink:Show()
    end
    return Blink, blink
end


-- ============================================================
-- ZOOM
-- ============================================================
-- THE ZOOM IS EASED HERE, NOT BY THE CANVAS (2026-10-31, Zac: "still
-- fucked with scrollwheel"). The windowed map on this client never moves
-- toward a zoom target on its own - SetZoomTarget sets a number nothing
-- reads - so the only zoom that ever worked was the instant one. This
-- driver does the easing: a few frames of InstantPanAndZoom from where
-- the canvas is to the level asked for, aimed at a spot, eased out. A
-- new ask mid-way carries on from where it is.
local easer
local function Ease(sc, toScale, toX, toY, secs)
    if not (sc and sc.InstantPanAndZoom and sc.GetCanvasScale) then return end
    if not easer then
        easer = CreateFrame("Frame")
        easer:Hide()
        easer:SetScript("OnUpdate", function(self, el)
            local e = self.e
            if not e then self:Hide() return end
            e.t = e.t + el
            local k = math.min(1, e.t / e.secs)
            k = 1 - (1 - k) * (1 - k)
            local scale = e.fromScale + (e.toScale - e.fromScale) * k
            local x = e.fromX + (e.toX - e.fromX) * k
            local y = e.fromY + (e.toY - e.fromY) * k
            e.sc:InstantPanAndZoom(scale, x, y)
            if k >= 1 then
                if e.sc.SetPanTarget then e.sc:SetPanTarget(e.toX, e.toY) end
                e.sc._zEaseTo = nil
                self.e = nil
                self:Hide()
            end
        end)
    end
    -- animations off (Appearance > Motion): straight there
    if secs ~= nil and secs <= 0 then
        if easer.e then easer.e = nil easer:Hide() end
        sc._zEaseTo = nil
        sc:InstantPanAndZoom(toScale, toX, toY)
        if sc.SetPanTarget then sc:SetPanTarget(toX, toY) end
        return
    end
    local fromX = sc.GetNormalizedHorizontalScroll and sc:GetNormalizedHorizontalScroll() or toX
    local fromY = sc.GetNormalizedVerticalScroll and sc:GetNormalizedVerticalScroll() or toY
    easer.e = { sc = sc, t = 0, secs = secs or 0.15, fromScale = sc:GetCanvasScale() or toScale, toScale = toScale,
        fromX = fromX or 0.5, fromY = fromY or 0.5, toX = toX or fromX or 0.5, toY = toY or fromY or 0.5 }
    sc._zEaseTo = toScale
    easer:Show()
end
local function EaseStop(sc)
    if easer and easer.e then easer.e = nil easer:Hide() end
    if sc then sc._zEaseTo = nil end
end
F.Ease, F.EaseStop = Ease, EaseStop

-- The wheel's glide (smoothZoomTime, 0.15 s) and the longer one that
-- carries a zone change (five thirds of it: 0.25 s), through the global
-- motion switch and speed.
local function ZoomSecs(long)
    local t = tonumber(DB().smoothZoomTime) or 0.15
    if long then t = t * 5 / 3 end
    return Maps.Time(t)
end

local function InstallZoom(map)
    local sc = map.ScrollContainer
    if not sc then return end

    -- Extra zoom levels past Blizzard's top one (shared with the
    -- battlefield map - see Maps.InstallExtraZoom).
    Maps.InstallExtraZoom(sc, function()
        if not On("extraZoom") then return nil end
        return DB().zoomFactor or 2
    end)

    -- SCROLL ON INTO THE ZONE, AND BACK OUT OF IT (2026-10-31, Zac:
    -- "seamless map scroll in and out instead of clicking into the zone").
    -- The wheel stops at the top zoom level of a continent, and the zone
    -- under the cursor still had to be clicked; the other way, the zone's
    -- own map stops at its bottom level and the continent needed the
    -- back arrow. Now one more wheel step past either end goes through:
    --   * in, at the top level: the zone under the cursor opens (the next
    --     map down, so Azeroth -> Kalimdor -> Durotar one step at a time);
    --   * out, at the bottom level: the map above opens, zoomed and
    --     centred so the zone you came from fills the view - what a
    --     continuous zoom would show.
    -- The step only fires when the map was ALREADY at the limit before
    -- this wheel step (the zoom asked for by the last step, or the canvas
    -- itself, at the end level), so the step that reaches the top level
    -- never falls through into the zone by itself; the next one does.
    -- Hooked BEFORE the zoom-towards-the-cursor hook below, which moves
    -- the canvas to the new level at once: this one must see the canvas
    -- as it was before the step.
    -- Battlefield and instance maps (no art, no parent with art) are
    -- left alone.
    local function AtLimit(self, delta)
        if not (self.GetCanvasScale and self.GetScaleForMaxZoom and self.GetScaleForMinZoom) then return false end
        local edge = (delta > 0) and self:GetScaleForMaxZoom() or self:GetScaleForMinZoom()
        if not (edge and edge > 0) then return false end
        local scale = self:GetCanvasScale()
        if scale and math.abs(scale - edge) <= edge * 0.01 then return true end
        -- the zoom still on its way there from the last step
        local last = self._zEaseTo or self._zLastTarget
        return last ~= nil and math.abs(last - edge) <= edge * 0.01
    end
    local function HasArt(id)
        return id and (not C_Map.MapHasArt or C_Map.MapHasArt(id))
    end
    -- the map one step below `top` that holds the point (nx, ny) on it
    local function ChildAt(top, nx, ny)
        if not (C_Map and C_Map.GetMapInfoAtPosition and C_Map.GetMapInfo) then return nil end
        local under = C_Map.GetMapInfoAtPosition(top, nx, ny)
        local id = under and under.mapID
        local guard = 0
        while id and id ~= top and guard < 12 do
            local info = C_Map.GetMapInfo(id)
            if not info then return nil end
            if info.parentMapID == top then return id end
            id = info.parentMapID
            guard = guard + 1
        end
        return nil
    end
    local function ZoomOntoChild(self, parent, child)
        if not (C_Map.GetMapRectOnMap and self.InstantPanAndZoom and self.Child) then return end
        local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(child, parent)
        if not (minX and maxX and maxX > minX and maxY > minY) then return end
        local cx, cy = (minX + maxX) / 2, (minY + maxY) / 2
        local cw, ch = self.Child:GetWidth() or 0, self.Child:GetHeight() or 0
        local vw, vh = self:GetWidth() or 0, self:GetHeight() or 0
        if cw <= 0 or ch <= 0 or vw <= 0 or vh <= 0 then return end
        -- the scale at which the zone just fits the view, taken down to a
        -- real zoom level so the wheel carries on from a level it knows
        local fit = math.min(vw / ((maxX - minX) * cw), vh / ((maxY - minY) * ch))
        local lo, hi = self:GetScaleForMinZoom(), self:GetScaleForMaxZoom()
        local scale = math.max(lo or fit, math.min(hi or fit, fit))
        local levels = self.zoomLevels
        if type(levels) == "table" then
            local best
            for _, lv in ipairs(levels) do
                if lv.scale and lv.scale <= scale * 1.001 and (not best or lv.scale > best) then best = lv.scale end
            end
            if best then scale = best end
        end
        -- from close on the zone, easing out to where it fits: the same
        -- motion the wheel had been making, carried across the map change
        if hi and hi > scale then
            self:InstantPanAndZoom(math.min(hi, scale * 2), cx, cy)
            Ease(self, scale, cx, cy, ZoomSecs(true))
        else
            self:InstantPanAndZoom(scale, cx, cy)
            if self.SetPanTarget then self:SetPanTarget(cx, cy) end
        end
    end
    -- a short dip to dark and back over the map change, so the new map
    -- fades in rather than snapping (F.NewBlink: 0.25 s, down to 30%)
    local dip, dipFrame = F.NewBlink(map)
    F.blinkFrame = dipFrame
    local function Blink()
        if not On("scrollFade") then return end
        dip()
    end
    F.Blink = Blink
    sc:HookScript("OnMouseWheel", function(self, delta)
        if not On("scrollZones") or not C_Map then return end
        local here = map.mapID
        local limit = AtLimit(self, delta)
        self._zLastTarget = self._zEaseTo or (self.GetCanvasScale and self:GetCanvasScale())
        if not here or not limit then return end
        self._zLastTarget = nil             -- a new map starts fresh
        if delta > 0 then
            local x, y = self:GetNormalizedCursorPosition()
            if not x then return end
            local child = ChildAt(here, x, y)
            if child and HasArt(child) then
                EaseStop(self)
                map:SetMapID(child)
                Blink()
            end
        else
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(here)
            local parent = info and info.parentMapID
            if not (parent and parent > 0 and HasArt(parent)) then return end
            -- the way out stops at the Azeroth map (both continents from
            -- the game's tiles, Maps_HD): the cosmic picture above it is
            -- not a map (2026-10-31, Zac: "need to cap the scroll out" -
            -- at the continent while Azeroth was still the old drawing)
            local pinfo = C_Map.GetMapInfo(parent)
            local worldType = Enum and Enum.UIMapType and Enum.UIMapType.World or 1
            if pinfo and pinfo.mapType and pinfo.mapType < worldType then return end
            EaseStop(self)
            map:SetMapID(parent)
            Blink()
            -- after the canvas has laid the new map out
            local function go() if map.mapID == parent then ZoomOntoChild(self, parent, here) end end
            if RunNextFrame then RunNextFrame(go) else C_Timer.After(0, go) end
        end
    end)

    -- ZOOM TOWARDS THE CURSOR. Blizzard zooms about the centre, which
    -- means finding somewhere on the map is zoom, pan, zoom, pan.
    -- (2026-10-31: GetCurrentZoomRange gives the zoom-OUT level first,
    -- then the zoom-in one - this had them the other way round, so every
    -- wheel step in put the map one level back OUT at once, and the top
    -- level could never be reached by wheel; Zac: "i still have to click
    -- to go in and out of zones". At either end the missing side comes
    -- back as the current level: nothing to do then.)
    sc:HookScript("OnMouseWheel", function(self, delta)
        if not self.GetCurrentZoomRange then return end
        -- the world-map part takes the wheel itself (its own zoom, from
        -- the whole world to street level); stepping Blizzard's levels
        -- under it as well would pull the canvas two ways
        if Maps.OpenMapLoaded and Maps.OpenMapLoaded() then return end
        local cur = self.GetCanvasScale and self:GetCanvasScale()
        -- the next level past the one being eased to, so a quick run of
        -- steps counts every one (the canvas's own range is read from
        -- where it is, which mid-ease is the level it is leaving)
        local going = self._zEaseTo
        local base = going or cur
        local target
        local levels = self.zoomLevels
        if type(levels) == "table" and base then
            for _, lv in ipairs(levels) do
                local sc = lv.scale
                if sc then
                    if delta > 0 and sc > base * 1.001 and (not target or sc < target) then target = sc end
                    if delta < 0 and sc < base * 0.999 and (not target or sc > target) then target = sc end
                end
            end
            if not target then return end
        else
            local zoomOut, zoomIn = self:GetCurrentZoomRange()
            target = (delta > 0) and zoomIn or zoomOut
            if not target then return end
            if going and math.abs(target - going) <= going * 0.001 then return end
            if not going and cur and math.abs(target - cur) <= cur * 0.001 then return end
        end
        -- the level asked for here, eased to over a few frames (the
        -- canvas does not do that itself on this client); aimed at the
        -- cursor when that is on, clamped to what the level can show so
        -- it never lurches off an edge
        local x, y
        if On("zoomToCursor") then x, y = self:GetNormalizedCursorPosition() end
        if not x then
            x = self.GetNormalizedHorizontalScroll and self:GetNormalizedHorizontalScroll() or 0.5
            y = self.GetNormalizedVerticalScroll and self:GetNormalizedVerticalScroll() or 0.5
        end
        if self.CalculateScrollExtentsAtScale then
            local minX, maxX, minY, maxY = self:CalculateScrollExtentsAtScale(target)
            if minX then
                x = math.max(minX, math.min(maxX, x))
                y = math.max(minY, math.min(maxY, y))
            end
        end
        if On("smoothZoom") then
            Ease(self, target, x, y, ZoomSecs(false))
        else
            self:InstantPanAndZoom(target, x, y)
            if self.SetPanTarget then self:SetPanTarget(x, y) end
        end
    end)

    -- REMEMBER WHERE YOU WERE, but only for the same map - restoring a
    -- pan position from Durotar onto Ironforge puts you in a wall.
    local saved
    map:HookScript("OnHide", function()
        if not On("rememberZoom") then return end
        if not sc.GetCanvasScale then return end
        saved = {
            mapID = map.mapID,
            scale = sc:GetCanvasScale(),
            x = sc:GetNormalizedHorizontalScroll(),
            y = sc:GetNormalizedVerticalScroll(),
        }
    end)
    map:HookScript("OnShow", function()
        if not On("rememberZoom") or not saved then return end
        if saved.mapID ~= map.mapID then return end
        local s = saved
        -- Deferred by a frame on purpose: the canvas lays itself out
        -- during OnShow, and anything set here is overwritten by that.
        local function restore()
            if not sc.InstantPanAndZoom then return end
            sc:InstantPanAndZoom(s.scale, s.x, s.y)
            sc:SetPanTarget(s.x, s.y)
        end
        if RunNextFrame then RunNextFrame(restore) else C_Timer.After(0, restore) end
    end)
end

-- ============================================================
-- CENTRING AND ZONE FOLLOWING
-- ============================================================
local function InstallCentring(map)
    local sc = map.ScrollContainer
    if not sc then return end

    -- Re-centred every 1.5s; holding shift suspends it for 3s.
    local centreNow = Maps.InstallCentring(map, sc, {
        enabled = function() return On("centreOnPlayer") end,
        interval = 1.5,
        holdOff = 3,
        mapID = function() return map.mapID end,
    })

    -- Opening the map should centre immediately rather than up to a tick
    -- and a half later.
    map:HookScript("OnShow", centreNow)

    -- THE TRAY STANDS DOWN WHILE THE MAP IS OPEN. It cannot be pushed
    -- behind the map by z-order - see the long note in Maps_Skin - and a
    -- row of addon icons across a near-fullscreen map is covering the
    -- party dots you opened it to look at. Hiding is the honest answer.
    map:HookScript("OnShow", function()
        if ns.Tray then ns.Tray.SetSuppressed(true) end
    end)
    map:HookScript("OnHide", function()
        if ns.Tray then ns.Tray.SetSuppressed(false) end
    end)

    -- FOLLOW THE PLAYER'S ZONE. Only when the map is already showing the
    -- zone you were in - if you have deliberately gone to look at
    -- Silithus, walking through a zone border should not yank you back.
    --
    -- WHICH TWO THINGS GET COMPARED MATTERS. The first version of this
    -- remembered both the displayed map AND the player's zone at the
    -- last OnMapChanged, and compared those two remembered values. That
    -- is wrong the moment the map is navigated by any path that does not
    -- fire OnMapChanged: the remembered "displayed map" is stale, the
    -- test still passes, and the map yanks you away from whatever you
    -- had gone to look at. Only ONE value can safely be remembered - the
    -- zone the player was in - and the displayed map is read live.
    local lastPlayerZone
    local function PlayerZone()
        return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    end
    if map.OnMapChanged then
        hooksecurefunc(map, "OnMapChanged", function()
            lastPlayerZone = PlayerZone()
        end)
    end

    local zoneWatch = CreateFrame("Frame")
    zoneWatch:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    zoneWatch:RegisterEvent("ZONE_CHANGED")
    zoneWatch:RegisterEvent("ZONE_CHANGED_INDOORS")
    zoneWatch:SetScript("OnEvent", function()
        local now = PlayerZone()
        if not now then return end
        -- Recorded whatever happens, so that going back to your own zone
        -- re-arms the following rather than staying stuck off.
        local was = lastPlayerZone
        lastPlayerZone = now

        if not On("followZone") then return end
        if map.mapID ~= was then return end     -- you are looking elsewhere
        if now == map.mapID then return end
        -- MapHasArt is not optional: SetMapID on a map with no art
        -- throws, and instance maps in this client have none.
        if C_Map.MapHasArt and not C_Map.MapHasArt(now) then return end
        map:SetMapID(now)
    end)
end

-- ============================================================
-- COORDINATES
-- ============================================================
-- THE STRIP'S PARTS AND ITS LOOK (2026-11-01). The real strip and the
-- sample in the settings preview are both made by MakeStrip and styled
-- by StyleStrip, so the two cannot drift apart: a background, then the
-- player's position on the left, the zone's level range a fixed step
-- after it, and the cursor's position on the right. Every font and
-- colour is a setting; unset, each is the theme's, as it always was.
local STRIP_TEXT = {
    -- field, theme colour, setting
    { "player", "gold", "coordPlayerColor" },
    { "cursor", "gray", "coordCursorColor" },
    { "zone",   "text", "coordZoneColor" },
}

-- WHERE THE STRIP'S TEXTS SIT (ZacUI's anchor shape, maps.anchors.<player|
-- cursor|zone>): any point of the strip or of the other two texts.
F.STRIP_TARGETS = { { value = "strip", text = "The strip" }, { value = "player", text = "Your position" },
    { value = "cursor", text = "Cursor position" }, { value = "zone", text = "Zone level range" } }
function F.StripAnchor(db, key)
    local a = db and db.anchors
    return type(a) == "table" and a[key] or nil
end
function F.StripResolver(strip)
    if not strip._zResolve then
        strip._zResolve = function(k)
            if k == "strip" then return strip elseif k == "player" then return strip.player
            elseif k == "cursor" then return strip.cursor elseif k == "zone" then return strip.zone end
        end
    end
    return strip._zResolve
end
function F.StripDefaults(key)
    if key == "cursor" then return { point = "RIGHT", relPoint = "RIGHT", x = -10, y = 0, justify = "RIGHT" }
    elseif key == "zone" then return { point = "LEFT", relPoint = "LEFT", x = 150, y = 0, justify = "LEFT" } end
    return { point = "LEFT", relPoint = "LEFT", x = 10, y = 0 }
end

function F.StyleStrip(strip)
    local db = DB()
    if strip._zFill then
        strip._zFill:SetVertexColor(Maps.Color("coordBg", "windowBg", nil, 0.72))
    end
    local base = UI.F and UI.F.SMALL or 10
    for _, t in ipairs(STRIP_TEXT) do
        local fs = strip[t[1]]
        if fs then
            Maps.StyleText(fs, db.coordFont, base)
            if fs._zPaint then fs:_zPaint() end
        end
    end
    -- the zone sits a fixed step after "Player  x, y", which grows with
    -- the font (and with each decimal place)
    if strip.zone then
        local def = Maps.FontDefaults(base)
        local size = tonumber(type(db.coordFont) == "table" and db.coordFont.size) or def.size
        local dec = math.max(0, (tonumber(db.coordDecimals) or 1) - 1)
        local step = math.floor((150 + dec * 14) * size / math.max(1, def.size) + 0.5)
        if db.coordLabels == false then step = step - math.floor(42 * size / math.max(1, def.size)) end
        local za = F.StripAnchor(db, "zone")
        if za and ns.ApplyAnchor then
            local d = strip._zDefZone or {}
            strip._zDefZone = d
            d.point, d.to, d.relPoint, d.x, d.y, d.justify = "LEFT", strip, "LEFT", step, 0, "LEFT"
            ns.ApplyAnchor(strip.zone, za, d, F.StripResolver(strip))
        else
            strip.zone:ClearAllPoints()
            strip.zone:SetPoint("LEFT", step, 0)
        end
        -- the step is where the zone sits unless "Player  x, y" is wider
        -- than it (F.KeepZoneClear); a saved spot is the player's own
        strip._zZoneStep = (not za) and step or nil
        strip._zZoneX = strip._zZoneStep
    end
    -- your position and the cursor's: their spots, or the saved anchor on
    -- top (maps.anchors.<player|cursor>; nothing saved = never touched)
    local pa, ca = F.StripAnchor(db, "player"), F.StripAnchor(db, "cursor")
    if (pa or ca or strip._zMoved) and ns.ApplyAnchor and strip.player then
        strip._zMoved = (pa or ca) and true or nil
        local D = strip._zDefs or { player = {}, cursor = {} }
        strip._zDefs = D
        local d = D.player
        d.point, d.to, d.relPoint, d.x, d.y = "LEFT", strip, "LEFT", 10, 0
        ns.ApplyAnchor(strip.player, pa, d, F.StripResolver(strip))
        d = D.cursor
        d.point, d.to, d.relPoint, d.x, d.y, d.justify = "RIGHT", strip, "RIGHT", -10, 0, "RIGHT"
        ns.ApplyAnchor(strip.cursor, ca, d, F.StripResolver(strip))
    end
end

-- THE ZONE NEVER SITS ON YOUR POSITION (2026-11-07, Zac on Forever:
-- "text overlap on the map"). The zone's fixed step after "Player  x, y"
-- is a guess at that text's width; a bigger font, a wider face or a
-- longer label can run past it. Measured after each position update
-- (five times a second while the map is open) and the zone moved right
-- only when the text actually reaches it, so the usual layout is exactly
-- as before.
function F.KeepZoneClear(strip)
    local step, zone, player = strip._zZoneStep, strip.zone, strip.player
    if not (step and zone and player and player.GetStringWidth) or strip._zMoved then return end
    local w = (player:GetText() or "") ~= "" and (player:GetStringWidth() or 0) or 0
    local x = math.max(step, math.ceil(10 + w + 14))
    if x ~= strip._zZoneX then
        strip._zZoneX = x
        zone:ClearAllPoints()
        zone:SetPoint("LEFT", x, 0)
    end
end

function F.MakeStrip(strip)
    local bg = strip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(FLAT)
    strip._zFill = bg
    for _, t in ipairs(STRIP_TEXT) do
        local field, themeKey, setting = t[1], t[2], t[3]
        local fs = UI.Font(strip, UI.F.SMALL, { cat = "text", key = themeKey,
            justify = (field == "cursor") and "RIGHT" or (field == "zone" and "LEFT" or nil) })
        -- the colour editor's repaint comes through here too, so an
        -- overridden colour survives it and an unset one follows the theme
        fs._zPaint = function(self) self:SetTextColor(Maps.Color(setting, "text", themeKey)) end
        strip[field] = fs
    end
    strip.player:SetPoint("LEFT", 10, 0)
    strip.cursor:SetPoint("RIGHT", -10, 0)
    strip.zone:SetPoint("LEFT", 150, 0)
    if ns.TagElement then
        -- the pick hook (the settings preview's strip is made here too)
        ns.TagElement(strip.player, "maps.player") ns.TagElement(strip.cursor, "maps.cursor")
        ns.TagElement(strip.zone, "maps.zone")
    end
    strip._zPaint = F.StyleStrip
    F.StyleStrip(strip)
    return strip
end

-- "Player  52.4, 38.1": the decimals (coordDecimals) and the word in
-- front (coordLabels) are settings.
local COORD_FMT = { [0] = "%.0f, %.0f", "%.1f, %.1f", "%.2f, %.2f" }
-- or the saved coordinate format (maps.formats.coords, ZacUI's text
-- format: a template over [label] [x] [y], decimals for the numbers)
local COORD_VALUES, COORD_KINDS = {}, { label = "text", x = "percent", y = "percent" }
-- what a field left out means: the old keys (coordLabels, coordDecimals)
local COORD_DEF = {}
function F.CoordDefaults(db)
    db = db or DB()
    COORD_DEF.template = (db.coordLabels ~= false) and "[label]  [x], [y]" or "[x], [y]"
    COORD_DEF.decimals = math.max(0, math.min(2, math.floor(tonumber(db.coordDecimals) or 1)))
    return COORD_DEF
end
function F.CoordText(label, x, y)
    local db = DB()
    local spec = type(db.formats) == "table" and db.formats.coords
    if spec and ns.FormatText then
        local v = COORD_VALUES
        v.label, v.x, v.y = label, x * 100, y * 100
        return ns.FormatText(spec, F.CoordDefaults(db), v, COORD_KINDS, "x")
    end
    local n = math.max(0, math.min(2, math.floor(tonumber(db.coordDecimals) or 1)))
    local s = string.format(COORD_FMT[n], x * 100, y * 100)
    if db.coordLabels ~= false then s = label .. "  " .. s end
    return s
end

local function BuildCoords(map)
    local sc = map.ScrollContainer
    if not sc then return end

    -- ============================================================
    -- THE STRIP FILLS THE DEAD BAND INSTEAD OF COVERING THE MAP
    -- ============================================================
    -- Blizzard's window is taller than its canvas: there is a margin
    -- below the scroll container that belongs to the frame and holds
    -- nothing. The coordinate strip used to be parented to the CANVAS and
    -- anchored to the canvas's bottom, so it sat on top of the bottom of
    -- the map art - covering it - while that margin stayed empty and
    -- black underneath. Two problems from one anchor: the map lost its
    -- bottom edge and the window looked padded.
    --
    -- Anchored to the FRAME's bottom and stretched up to the canvas's
    -- bottom, the strip is exactly the size of the gap, whatever the gap
    -- happens to be on a given build. Nothing covers the map and nothing
    -- is left over.
    --
    -- Deliberately NOT done by resizing the window. That was tried, and
    -- the canvas does not follow far enough, so it turned symmetrical
    -- side bands into an asymmetric black slab. Filling a gap is safe;
    -- changing the geometry that produces it is not.
    local strip = CreateFrame("Frame", "ZacUIMapCoords", map)
    strip:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", 1, 1)
    strip:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -1, 1)
    strip:SetPoint("TOP", sc, "BOTTOM", 0, 0)
    strip:SetFrameStrata(sc:GetFrameStrata())
    strip:SetFrameLevel(sc:GetFrameLevel() + 20)

    -- A BUILD WITH NO GAP WOULD COLLAPSE THIS TO NOTHING, and a strip of
    -- zero height is indistinguishable from the coordinates being
    -- broken. If the margin turns out not to exist, fall back to the old
    -- behaviour - over the canvas, fixed height - which is worse looking
    -- and definitely visible. Checked once, when there is a real size to
    -- check, rather than trusted at build time when there is not.
    local function FitStrip()
        if strip._zFitted then return end
        local h = strip:GetHeight() or 0
        if h <= 0 then return end          -- not laid out yet; ask again
        strip._zFitted = true
        if h < 12 then
            strip:ClearAllPoints()
            strip:SetParent(sc)
            strip:SetHeight(18)
            strip:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 0, 0)
            strip:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 0, 0)
        end
    end
    strip._zFit = FitStrip

    -- background, player, cursor and zone texts (F.MakeStrip, above)
    F.MakeStrip(strip)
    local player, cursor = strip.player, strip.cursor

    -- ZONE LEVEL RANGE, AND WHY IT LIVES HERE.
    --
    -- The obvious place for it is Blizzard's own zone label, which is
    -- what the addon this replaces does - it finds the area-label data
    -- provider by duck-typing (no provider exposes a name), saves its
    -- Label's OnUpdate script, and replaces it with a reimplementation
    -- of Blizzard's labelling logic with the range appended. That is a
    -- raw SetScript on someone else's frame plus a private copy of
    -- Blizzard's label rules to keep in sync forever, in exchange for
    -- putting six characters in a particular place.
    --
    -- This strip already exists, already updates on a timer, and is
    -- already the place your eye goes for map facts. Nothing of
    -- Blizzard's is touched at all.
    -- Left of centre, a fixed step after "Player  x, y" (not anchored to
    -- that text, which changes width as the numbers do): the right half
    -- of the strip is where other readouts dock - Readycheck's world-buff
    -- timers (2026-11-01, Zac: "text overlap here", the zone sat under
    -- them in the middle). Exposed as strip.zone so a docked readout can
    -- keep clear of it.
    local zone = strip.zone

    local function ZoneText(mapID, nx, ny)
        -- On a continent, the useful zone is the one under the cursor.
        -- On a zone map it is the map itself.
        local target = mapID
        if nx and C_Map and C_Map.GetMapInfoAtPosition then
            local under = C_Map.GetMapInfoAtPosition(mapID, nx, ny)
            if under and under.mapID then target = under.mapID end
        end
        local rec = MapData and MapData.zones and MapData.zones[target]
        if not rec then return "" end

        local name
        if C_Map and C_Map.GetMapInfo then
            local info = C_Map.GetMapInfo(target)
            name = info and info.name
        end
        local parts = {}
        if name and target ~= mapID then parts[#parts + 1] = name end
        if rec[1] and rec[2] then
            parts[#parts + 1] = (rec[1] == rec[2])
                and tostring(rec[1]) or (rec[1] .. "-" .. rec[2])
        end
        if rec[3] and DB().fishingLevels then
            parts[#parts + 1] = "fishing " .. rec[3]
        end
        return table.concat(parts, "   ")
    end

    -- Two cadences, because they change at different rates and both used
    -- to run every frame. The player moves continuously; the cursor only
    -- matters while it is over the map at all.
    local tPlayer, tCursor = 0, 0
    strip:SetScript("OnUpdate", function(self, dt)
        -- Cheap and self-disarming: the first frame with a real height
        -- decides whether the stretched anchor worked, then never runs
        -- again.
        FitStrip()
        if not On("coords") then
            self:Hide()
            return
        end

        tPlayer = tPlayer + dt
        if tPlayer > 0.2 then
            tPlayer = 0
            local mapID = C_Map and C_Map.GetBestMapForUnit
                and C_Map.GetBestMapForUnit("player")
            local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
            if pos and map.mapID == mapID then
                local x, y = pos:GetXY()
                player:SetText(F.CoordText("Player", x, y))
            else
                -- Blank rather than stale. A coordinate readout showing
                -- where you were two zones ago is worse than none.
                player:SetText("")
            end
            F.KeepZoneClear(self)
        end

        tCursor = tCursor + dt
        if tCursor > 0.1 then
            tCursor = 0
            local nx, ny
            if sc.GetNormalizedCursorPosition and sc:IsMouseOver() then
                nx, ny = sc:GetNormalizedCursorPosition()
                if nx and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
                    cursor:SetText(F.CoordText("Cursor", nx, ny))
                else
                    cursor:SetText("")
                    nx, ny = nil, nil
                end
            else
                cursor:SetText("")
            end
            if DB().zoneLevels and map.mapID then
                zone:SetText(ZoneText(map.mapID, nx, ny))
            else
                zone:SetText("")
            end
        end
    end)

    coordsFrame = strip
    return strip
end

function F.ApplyCoords()
    if not coordsFrame then return end
    coordsFrame:SetShown(On("coords"))
    F.StyleStrip(coordsFrame)
    -- the modern map's own coordinate readout steps aside for this strip
    if ns.MapsSkin and ns.MapsSkin.SyncCoordsPanel then ns.MapsSkin.SyncCoordsPanel() end
end

-- ============================================================
-- APPLY
-- ============================================================
function F.Apply()
    local map = _G.WorldMapFrame
    if not map then return end

    if not installed then
        installed = true
        Detach(map)
        InstallCursorMath(map)
        MakeMovable(map)
        InstallZoom(map)
        InstallCentring(map)
        BuildCoords(map)
        InstallOpening(map)
        F.grip = BuildGrip(map)

        -- Blizzard re-anchors its close button whenever the map syncs,
        -- and at a windowed size it lands over the canvas. Ours is put
        -- where it belongs once and then pinned.
        local close = _G.WorldMapFrameCloseButton
            or (map.BorderFrame and map.BorderFrame.CloseButton)
            or map.CloseButton
        if close and not close._zMapPinned then
            close._zMapPinned = true
            -- PUT BACK AFTER BLIZZARD MOVES IT, NOT FROZEN. This used to
            -- replace close.SetPoint with an empty function. That is a
            -- write of our own function onto Blizzard's frame, and the
            -- map's display-state sync calls it - so Blizzard's code ran
            -- ours, inside its own execution, every sync. A post-hook
            -- runs after Blizzard's call and outside it, and the guard
            -- stops our own SetPoint re-entering the hook.
            local pinning = false
            local function Pin(self)
                if pinning then return end
                pinning = true
                self:ClearAllPoints()
                self:SetPoint("TOPRIGHT", map, "TOPRIGHT", -4, -4)
                pinning = false
            end
            Pin(close)
            hooksecurefunc(close, "SetPoint", Pin)
        end
    end

    -- (the world-map part's own window keeps the scale and the place;
    -- setting them here too would have two hands on the same frame)
    if not (Maps.OpenMapLoaded and Maps.OpenMapLoaded()) then
        F.ApplySize(DB().scale)
        Maps.RestorePoint(map, DB(), "CENTER", 0, 0)
    end
    F.ApplyFade()
    F.ApplyCoords()
    if F.grip then F.grip:SetShown(On("unlock")) end
end

-- shared with later ZacUI files
ns.MapsFrame = F
