-- Maps_Group - solid, class-coloured dots for your party and raid, with
-- each one's name under it.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHY THIS DOES NOT GO THROUGH BLIZZARD'S UNIT PINS. Three attempts did.
-- Setting the appearance field `useClassColor` is the documented route
-- and changed nothing visible. Pointing SetPinTexture at a class icon
-- sheet drew the whole sheet on every teammate. Painting the pin's own
-- texture object found nothing to paint, because a group pin is not a
-- frame with a texture on it - it is a UnitPositionFrame, a widget that
-- draws its blips internally where no addon can reach them. Every one of
-- those attempts LOOKED like it worked in code and did nothing on screen.
--
-- So this stops asking and draws. One small frame per group member,
-- parented to the map canvas, positioned from C_Map.GetPlayerMapPosition
-- and tinted from the unit's class. Being a child of the canvas is what
-- makes it correct: the canvas owns panning and zoom, so a dot placed as
-- a fraction of the canvas moves and scales with the map for free, which
-- is the one thing hand-placed frames on a map normally get wrong.
--
-- BLIZZARD'S OWN BLIPS HAVE TO GO, AND THAT HAPPENS IN Maps_Icons.
-- This paragraph used to say they were "pushed down to a size that reads
-- as a pinprick". They were not. Nothing anywhere did that, and
-- Maps_Icons was in fact sizing them to classIconSize - the same size as
-- these dots, in the same place - so each teammate was drawn twice and
-- the dots looked broken no matter what was done to them here. The
-- lesson is worth more than the fix: a comment describing what the code
-- ought to do reads exactly like a comment describing what it does, and
-- this one sent three rounds of debugging to the wrong file.

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

local G = {}

local dots = {}
local driver

-- WHAT A DOT IS MADE OF.
--
-- The previous version pointed at Interface\COMMON\Indicator-Gray and
-- hoped. That is a ring, not a filled circle, so tinting it produced a
-- coloured outline around nothing - and if a build does not have it, the
-- texture resolves to nil and the dot is invisible with no error. Both
-- failures look identical to "the dots do not work".
--
-- ElvUI's whole visual language is a flat fill with a one-pixel black
-- border, and that is buildable from a texture every client has:
-- WHITE8X8. No atlas to resolve, no art to be missing, and it matches
-- the rest of the interface.
local FILL = "Interface\\Buttons\\WHITE8X8"

-- One strata up: the table Maps_Skin uses to lift ZacUI's own map
-- furniture (Maps_Core).
local STRATA_UP = Maps.STRATA_UP

local function RaiseAboveCanvas(dot, canvas)
    if not dot or not canvas or not canvas.GetFrameStrata then return end
    local base = canvas:GetFrameStrata() or "MEDIUM"
    dot:SetFrameStrata(STRATA_UP[base] or "HIGH")
end

local function Canvas()
    local map = _G.WorldMapFrame
    local sc = map and map.ScrollContainer
    if not sc then return nil end
    return sc.Child or (sc.GetCanvas and sc:GetCanvas())
end

-- Class colour through the core helper, so the map dots, the minimap
-- names and every window agree (a class-colour addon's table first).
local function ClassColour(unit)
    local _, class = UnitClass(unit)
    if class then return ns.ClassColor(class) end
    local a = Col("accent")
    return a.r, a.g, a.b
end

-- ============================================================
-- MAKING A SQUARE ROUND
-- ============================================================
-- A flat fill is a SQUARE, which is what ended up on the map: the right
-- colour, the right size, the wrong shape. There is no filled-circle
-- texture that can be relied on across builds, and guessing at one -
-- Indicator-Gray was the last guess, and it is a ring - is how this has
-- gone wrong before.
--
-- So the shape is cut rather than found. A mask texture multiplies the
-- alpha of everything it is attached to, so a circular mask over a solid
-- fill leaves a solid circle in exactly the colour asked for, with no
-- art to be missing and nothing to tint incorrectly. The mask used is
-- Blizzard's portrait mask, which every client has because the portrait
-- system is built on it.
--
-- If a build has no mask API at all the dot stays square rather than
-- disappearing, and Maps.Diagnose says which shape you are getting -
-- because "it is still a square" should be answerable without a
-- screenshot.
local CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
G.rounded = nil

-- A mask that masks nothing: solid white, so every pixel it covers keeps
-- its full alpha. Pointing the mask here is how the round shape is turned
-- OFF, because AddMaskTexture is one-way - there is no detach.
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"

local function Round(frame, tex)
    if not frame.CreateMaskTexture or not tex.AddMaskTexture then
        G.rounded = false
        return
    end
    local mask = frame:CreateMaskTexture()
    if not mask or not mask.SetTexture then
        G.rounded = false
        return
    end
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)
    tex._zMask = mask
    G.rounded = true
    return mask
end

local function SetRound(tex, round)
    local mask = tex and tex._zMask
    if not mask then return end
    mask:SetTexture(round and CIRCLE_MASK or SQUARE_MASK,
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
end

-- One dot: border, fill, round masks and a name, on `parent`. The map's
-- dots and the settings preview's sample dots are both made here.
function G.NewDot(parent)
    local dot = CreateFrame("Frame", nil, parent)
    dot._zui_own = true

    -- Border first, underneath, drawn as a plain fill one pixel
    -- larger on every side. Four edge strips would be tidier and
    -- four times the textures for something this small.
    dot.edge = dot:CreateTexture(nil, "ARTWORK")
    dot.edge._zui_own = true
    dot.edge:SetTexture(FILL)
    dot.edge:SetVertexColor(0, 0, 0, 1)
    dot.edge:SetPoint("TOPLEFT", -1, 1)
    dot.edge:SetPoint("BOTTOMRIGHT", 1, -1)

    dot.tex = dot:CreateTexture(nil, "OVERLAY")
    dot.tex._zui_own = true
    dot.tex:SetTexture(FILL)
    dot.tex:SetAllPoints()

    -- Both layers, or the round dot sits on a square shadow.
    Round(dot, dot.edge)
    Round(dot, dot.tex)
    -- The masks stay attached for the life of the dot. Turning the
    -- round shape off cannot remove them - a mask cannot be
    -- detached - so the square is produced by pointing the mask at
    -- something that masks nothing rather than by taking it away.
    dot._zMasks = { dot.edge, dot.tex }

    dot.label = dot:CreateFontString(nil, "OVERLAY")
    dot.label._zui_own = true
    dot.label:SetPoint("TOP", dot, "BOTTOM", 0, -1)
    dot.label:SetWordWrap(false)
    return dot
end

local function Dot(index, canvas)
    local dot = dots[index]
    if not dot or dot:GetParent() ~= canvas then
        dot = G.NewDot(canvas)

        -- ============================================================
        -- ABOVE THE HOUSES - BY STRATA, NOT BY GUESSING A LEVEL
        -- ============================================================
        -- Blizzard's map pins are handed levels in blocks of hundreds, so
        -- a frame made on the canvas the ordinary way lands underneath
        -- every town and landmark on the map. That much was right.
        --
        -- The first attempt fixed it with `canvas level + 900` - a number
        -- picked to be bigger than Blizzard's highest block, with no API
        -- to check it against. That is a guess wearing a comment, and it
        -- went out alongside three other changes to these same dots in
        -- one go, which is how "the icons are gone or in the wrong spot"
        -- became impossible to attribute.
        --
        -- Strata beats frame level unconditionally, and this addon
        -- already relies on that in Maps_Skin to lift its own furniture
        -- over the canvas. One strata up is exact, needs no magic number,
        -- and cannot be out-ranked by a pin however high its level.
        RaiseAboveCanvas(dot, canvas)
        dots[index] = dot
    end
    return dot
end

-- ============================================================
-- ONE POSITION READ PER MEMBER, FOR BOTH MAPS
-- ============================================================
-- Everyone worth drawing - the party or the raid (from the core roster),
-- never yourself: the player arrow already says where you are - with a
-- position on mapID. The world-map dots (10/s) and the minimap names
-- (5/s) both ask; in the same zone the second asker within a tick gets
-- the first one's reads instead of forty more GetPlayerMapPosition calls.
-- Off-map units report 0,0 rather than nil and are left out. The arrays
-- are shared and rewritten in place; callers read them at once.
local snap = { mapID = nil, t = -1, n = 0, unit = {}, x = {}, y = {} }
local SNAP_AGE = 0.09

function G.Positions(mapID)
    local now = GetTime()
    if snap.mapID == mapID and now - snap.t < SNAP_AGE then return snap end
    snap.mapID, snap.t = mapID, now
    local n = 0
    local units = ns.Roster.Units()
    local getPos = C_Map and C_Map.GetPlayerMapPosition
    if mapID and getPos then
        for i = 1, #units do
            local unit = units[i]
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local pos = getPos(mapID, unit)
                if pos then
                    local x, y = pos:GetXY()
                    if x and y and (x > 0 or y > 0) then
                        n = n + 1
                        snap.unit[n], snap.x[n], snap.y[n] = unit, x, y
                    end
                end
            end
        end
    end
    for i = n + 1, snap.n do snap.unit[i] = nil end
    snap.n = n
    return snap
end

local declutter = Maps.NewDeclutter()

-- Shape, outline, opacity and strata are remembered on each dot and only
-- re-applied when the wanted value differs, so the options stay live
-- (every config toggle lands on the next tick) without a mask retexture
-- and a strata sort per dot ten times a second.
local function Style(dot, round, border, alpha, strata)
    if dot._zRound ~= round then
        dot._zRound = round
        SetRound(dot.tex, round)
        SetRound(dot.edge, round)
    end
    if dot._zBorder ~= border then
        dot._zBorder = border
        dot.edge:SetShown(border)
    end
    if dot._zAlpha ~= alpha then
        dot._zAlpha = alpha
        dot:SetAlpha(alpha)
    end
    if strata and dot._zStrata ~= strata then
        dot._zStrata = strata
        dot:SetFrameStrata(strata)
    end
end

-- ============================================================
-- THE LOOK OF A PASS (shared with the settings preview)
-- ============================================================
-- Everything the same for every dot, read once per pass: this runs ten
-- times a second for the whole raid while the map is up, so the table is
-- kept and rewritten in place. cs is the canvas scale the dots sit at
-- (1 for the preview) - sizes are divided by it so a dot is the same
-- size on screen at every zoom.
local look = {}
function G.Look(cs)
    local db = DB()
    cs = (cs and cs > 0) and cs or 1
    look.size = (db.classIconSize or 14) / cs
    look.names = db.dotNames ~= false
    look.nameSize = math.max(1, (tonumber(db.dotNameSize) or 9) / cs)
    look.dodge = db.dotNameDeclutter ~= false
    look.round = db.dotRound ~= false
    look.border = db.dotBorder ~= false
    look.alpha = tonumber(db.dotAlpha) or 1
    -- the outline: black, 1px, unless picked otherwise
    look.br, look.bg, look.bb, look.ba = Maps.Color("dotBorderColor", { 0, 0, 0, 1 })
    -- (in canvas units, like the dot's outline always was)
    look.bsize = math.max(0, tonumber(db.dotBorderSize) or 1)
    -- the fill and the name: class colour, or one colour for everyone
    look.oneColour = db.dotColorMode == "custom"
    if look.oneColour then look.fr, look.fg, look.fb = Maps.Color("dotColor", "accent") end
    look.oneName = db.dotNameColorMode == "custom"
    if look.oneName then look.nr, look.ng, look.nb = Maps.Color("dotNameColor", "text", "normal") end
    -- the name's font: ZacUI's font (and its global size adjustment),
    -- outlined, no shadow - unless the Maps page says otherwise
    local spec = type(db.dotNameFont) == "table" and db.dotNameFont or {}
    local cfg = ZacUIDB and ZacUIDB.font or {}
    look.fpath = (spec.face and ns.ResolveFontFace and ns.ResolveFontFace(spec.face))
        or (ns.ResolveFontPath and ns.ResolveFontPath(cfg.name))
    look.fdelta = cfg.delta or 0
    look.fflags = ns.FontOutlineFlags and ns.FontOutlineFlags(spec.outline or "outline") or "OUTLINE"
    look.fshadow = spec.shadow and true or false
    look.fsx, look.fsy = tonumber(spec.shadowX) or 1, tonumber(spec.shadowY) or -1
    look.lh = look.nameSize / 2 + 1
    return look
end

-- One dot dressed for one member: size, shape, outline, opacity, colour
-- and name (class colour r, g, b unless one colour is picked). strata is
-- the map's; the preview passes nil.
function G.Paint(dot, L, r, g, b, name, strata)
    if dot._zSize ~= L.size then
        dot._zSize = L.size
        dot:SetSize(L.size, L.size)
    end
    if dot._zBSize ~= L.bsize then
        dot._zBSize = L.bsize
        dot.edge:ClearAllPoints()
        dot.edge:SetPoint("TOPLEFT", -L.bsize, L.bsize)
        dot.edge:SetPoint("BOTTOMRIGHT", L.bsize, -L.bsize)
    end
    dot.edge:SetVertexColor(L.br, L.bg, L.bb, L.ba)
    if L.oneColour then
        dot.tex:SetVertexColor(L.fr, L.fg, L.fb)
    else
        dot.tex:SetVertexColor(r, g, b)
    end
    Style(dot, L.round, L.border, L.alpha, strata)
    local label = dot.label
    if L.names then
        Maps.LabelFont(label, L.nameSize, L.fpath, L.fdelta, L.fflags, L.fshadow, L.fsx, L.fsy)
        label:SetText(name)
        if L.oneName then label:SetTextColor(L.nr, L.ng, L.nb) else label:SetTextColor(r, g, b) end
    end
end

-- The name under a dot at (x, y) on the canvas, left off when it would
-- land on one already placed (declutter). Returns whether it shows.
function G.PlaceName(dot, L, x, y, declutter)
    local showName = false
    if L.names then
        showName = true
        if L.dodge and declutter then
            local lw = (dot.label:GetStringWidth() or 0) / 2 + 1
            showName = declutter.Place(x, y - L.size / 2 - 1 - L.lh, lw, L.lh)
        end
    end
    dot.label:SetShown(showName)
    return showName
end

-- The canvas restacks its children when the map changes, so anything
-- set once does not survive clicking through to a zone. Forgetting what
-- was applied makes the next pass apply it all again - on exactly the
-- change that used to lose it, instead of on every tick in case.
local function ForgetStyle()
    for i = 1, #dots do dots[i]._zStrata = nil end
end

function G.Update()
    local canvas = Canvas()
    local map = _G.WorldMapFrame
    if not canvas or not map then return end

    local shown = 0
    if On("classIcons") and map:IsShown() then
        local db = DB()
        local mapID = map.mapID
        local w, h = canvas:GetWidth(), canvas:GetHeight()

        -- SCREEN PIXELS, NOT CANVAS UNITS (2026-10-31, Zac: "huge player
        -- dots"). The dots are children of the canvas, which is scaled
        -- to zoom, so a 14-unit dot was 14 x the zoom on screen - three
        -- times too big at Blizzard's deepest level and a blob the size
        -- of a city once the world-map part drove the canvas's scale up.
        -- Divided by the canvas scale here, a dot and its name are the
        -- same size on screen at every zoom, which is what a marker is.
        local cs = canvas.GetScale and canvas:GetScale() or 1
        if not cs or cs <= 0 then cs = 1 end
        -- Everything the same for every dot, read once per pass (G.Look):
        -- this runs ten times a second for the whole raid while the map
        -- is up.
        local L = G.Look(cs)
        local strata = STRATA_UP[canvas:GetFrameStrata() or "MEDIUM"] or "HIGH"
        declutter.Reset()
        if mapID and w and h and w > 0 then
            local snapshot = G.Positions(mapID)
            for i = 1, snapshot.n do
                local unit, x, y = snapshot.unit[i], snapshot.x[i], snapshot.y[i]
                shown = shown + 1
                local dot = Dot(shown, canvas)
                dot:ClearAllPoints()
                -- As a FRACTION of the canvas, so panning and
                -- zooming carry the dot along.
                dot:SetPoint("CENTER", canvas, "TOPLEFT", x * w, -y * h)
                local r, g, b = ClassColour(unit)
                -- Size, shape, outline, opacity, colour and strata: live,
                -- but only touched when they differ from what this dot
                -- already has (see Style), and the name under it.
                G.Paint(dot, L, r, g, b, (UnitName(unit)), strata)
                -- With declutter on, a name that would land on one
                -- already placed is left off - a stacked group shows one
                -- readable name, not a smear.
                G.PlaceName(dot, L, x * w, -y * h, declutter)
                dot:Show()
            end
        end
    end

    for i = shown + 1, #dots do dots[i]:Hide() end
    G.shown = shown
end

-- ============================================================
-- APPLY
-- ============================================================
function G.Apply()
    local map = _G.WorldMapFrame
    if not map then return end

    if not driver then
        driver = CreateFrame("Frame", nil, map)
        local elapsed = 0
        driver:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            -- FIVE TIMES A SECOND IS NOT SMOOTH, it is five positions a
            -- second. The old comment here called it "smooth enough to
            -- follow and cheap enough not to notice", and both halves
            -- were wrong: a dot that only moves every 200ms visibly hops,
            -- and the work per tick is a handful of arithmetic on at most
            -- forty frames - nothing worth saving.
            --
            -- Blizzard's own blips update every frame, which is exactly
            -- why they look like they are moving and ours looked like
            -- they were teleporting.
            --
            -- Ten a second is the compromise: at 33 Hz the pass - a
            -- position read per raid member plus the label work - was
            -- the single largest OnUpdate in the addon whenever the map
            -- was open, and people run with the map open in a 40-man.
            if elapsed < 0.1 then return end
            elapsed = 0
            G.Update()
        end)
        -- The canvas restacks on show and on a map change; the dots'
        -- remembered styling is dropped so the next pass re-applies it.
        map:HookScript("OnShow", function() ForgetStyle() G.Update() end)

        -- ...AND IMMEDIATELY WHEN THE MAP ITSELF CHANGES. Clicking through
        -- to a zone replaces every coordinate on screen at once, and the
        -- dots kept the positions they had on the old map until the next
        -- tick came round - so the one moment they were guaranteed to be
        -- wrong was the moment you were looking hardest. A tick cannot fix
        -- that however fast it runs; it has to be driven by the change.
        if map.OnMapChanged then
            hooksecurefunc(map, "OnMapChanged", function() ForgetStyle() G.Update() end)
        end
    end
    -- A config toggle lands here through Maps.Refresh. Shape, outline and
    -- opacity are compared by value every pass so they take at once; the
    -- strata is re-asserted here as well, as a re-apply should.
    ForgetStyle()
    G.Update()
end

G.dots = dots
G.ClassColour = ClassColour

-- shared with later ZacUI files
ns.MapsGroup = G
