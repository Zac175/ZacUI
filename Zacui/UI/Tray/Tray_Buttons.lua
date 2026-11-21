-- Tray_Buttons - sweep every addon's minimap button into one movable bar
-- with a flyout tray.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE PROBLEM THIS SOLVES: minimap buttons belong to the addons that made
-- them, they are all different sizes, and by patch three you cannot see
-- the minimap. Collecting them means REPARENTING other addons' frames,
-- which works but comes with two rules learned the hard way:
--
--   1. THEY FIGHT BACK. LibDBIcon repositions its buttons whenever the
--      minimap updates, and several addons re-anchor on their own events.
--      So every grabbed button gets its SetPoint and SetParent hooked, and
--      any move we did not make queues a relayout that puts it back.
--
--   2. DO NOT RECURSE. Our own layout calls SetPoint, which would trip
--      the hook above, which would queue another layout, forever. A single
--      `laying` flag guards the whole pass.
--
-- Everything a button had is recorded before we touch it, so turning the
-- module off puts the minimap back exactly as it was.
--
-- WHERE THE BUTTONS GO is ZacUIDB.tray.dock (DOCKED TO THE MINIMAP, below):
--   nothing saved / "bar"   the bar with its flyout, anywhere on screen
--   "left" "right" "top" "bottom"   a strip on that edge of the minimap
--   "inside"   a band on the map itself, along its bottom edge
--   "tab"      a small tab under the map's corner that opens a grid
-- A tray nobody has used yet starts on "left" (the column down the map's
-- side, Zac's pick of the five mocks); one already in use stays as it is.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local Col = ns.Col
local FLAT = ns.FLAT
local Modules = ns.Modules
local Print = ns.Print
local SharpenIcon = ns.SharpenIcon
local UI = ns.UI
local ZUI = ns.ZUI

-- Blizzard's own minimap furniture. These are NOT addon buttons and
-- grabbing them breaks the minimap - the mail icon, the tracking dropdown
-- and the battleground queue all live here.
local BLIZZARD = {
    MinimapBackdrop = true, MinimapZoomIn = true, MinimapZoomOut = true,
    MiniMapWorldMapButton = true, MiniMapMailFrame = true,
    MiniMapMailBorder = true, MiniMapMailIcon = true,
    MiniMapTracking = true, MiniMapTrackingButton = true,
    MiniMapTrackingFrame = true, MiniMapTrackingIcon = true,
    MiniMapBattlefieldFrame = true, MiniMapMeetingStoneFrame = true,
    MiniMapLFGFrame = true, MinimapZoneTextButton = true,
    MinimapZoneText = true, TimeManagerClockButton = true,
    GameTimeFrame = true, MiniMapVoiceChatFrame = true,
    QueueStatusMinimapButton = true, MiniMapInstanceDifficulty = true,
    GarrisonLandingPageMinimapButton = true, MinimapNorthTag = true,
    MiniMapPing = true, MinimapCompassTexture = true,
    MinimapCluster = true, Minimap = true, MinimapZoomHitArea = true,
    ExpansionLandingPageMinimapButton = true,
}

-- Prefixes that are never a collectable button, whatever they are called.
local SKIP_PREFIX = { "ZacUI", "Minimap", "MiniMap", "GameTime", "Queue" }

-- ============================================================
-- Z-ORDER: THE TRAY MUST SIT *BELOW* THE BUTTONS IT HOLDS
-- ============================================================
-- This got fixed twice the wrong way, so the reasoning is written down.
--
-- Strata beats level, always. A frame in DIALOG draws over a frame in
-- MEDIUM no matter what levels they carry, and mouse input follows the
-- same order. So a DIALOG tray holding MEDIUM buttons means the tray's
-- own background is painted over its contents and eats every click.
--
-- Attempt 1 was to leave the buttons alone and let them inherit. They do
-- not: inheritance only happens for a frame that has NEVER been given a
-- strata, and LibDBIcon gives every button it creates an explicit MEDIUM.
--
-- Attempt 2 was to force each button up to DIALOG on every layout pass.
-- The dump from that build is why this comment exists:
--     tray               strata=DIALOG lvl=20
--     LFGMinimapFrame    strata=DIALOG lvl=24   <- ours, and it stuck
--     LibDBIcon10_Details strata=MEDIUM lvl=8   <- LibDBIcon put it back
-- Two buttons, same layout pass, different outcomes. LibDBIcon re-asserts
-- MEDIUM/8 on its own refresh, and a refresh is triggered by the very
-- reparenting and re-anchoring the tray has to do. That is a fight over a
-- shared value with no last word, and hooking harder only makes the two
-- addons take turns.
--
-- So the tray stops fighting. MEDIUM is where a minimap button already
-- expects to live, so the tray lives there too and wins the z-order by
-- FRAME LEVEL instead - a value the tray owns for its own frames and does
-- not have to take from anyone. The tray sits at 4, its cells at 5, the
-- buttons at 8. When LibDBIcon re-asserts MEDIUM/8 it is writing the same
-- numbers this module wanted, and the argument has nothing left to be
-- about.
--
-- The cost is that the tray no longer floats over HIGH/DIALOG frames.
-- That is the correct trade: a tray occasionally behind a dialog is a
-- nuisance, a tray whose buttons cannot be clicked is broken.
local TRAY_STRATA = "MEDIUM"
local TRAY_LEVEL = 4
local CELL_LEVEL = TRAY_LEVEL + 1
local BUTTON_LEVEL = 8

-- The BAR is the one exception and it is safe. Nothing foreign is ever
-- parented to it, so no one else's frame can end up underneath it; it is a
-- 6px sliver you have to be able to find, and it never overlaps the tray
-- (the tray is anchored 4px clear of it).
local BAR_STRATA = "DIALOG"
local BAR_LEVEL = 20

local bar, tray
local grabbed, order, original = {}, {}, {}
local laying, queued

-- Bumped when the shipped default position changes. A saved point from an
-- older build otherwise wins forever, and the new default is never seen -
-- which is exactly what happened when the bar moved from under the minimap
-- to the top of the screen.
local POSITION_REV = 2

local function DB()
    -- (never used: no table, or the empty one a look at its page left)
    local fresh = ZacUIDB.tray == nil or next(ZacUIDB.tray) == nil
    ZacUIDB.tray = ZacUIDB.tray or {}
    local t = ZacUIDB.tray
    if fresh then t.dock = "left" end
    if (t.posRev or 0) < POSITION_REV then
        t.posRev = POSITION_REV
        t.point, t.x, t.y = nil, nil, nil
    end
    if t.columns == nil then t.columns = 6 end
    if t.size == nil then t.size = 28 end
    if t.barWidth == nil then t.barWidth = 90 end
    if t.barHeight == nil then t.barHeight = 6 end
    if t.barAlpha == nil then t.barAlpha = 0.5 end
    if t.openOnHover == nil then t.openOnHover = true end
    if t.autoClose == nil then t.autoClose = 1.5 end
    if t.locked == nil then t.locked = false end
    -- Uniform square icons rather than each addon's own artwork.
    if t.uniform == nil then t.uniform = true end
    t.ignore = t.ignore or {}
    return t
end

-- ============================================================
-- UNIFORM STYLING
-- ============================================================
-- This file used to say, in capitals, that it deliberately did NOT
-- restyle these buttons - every addon draws its own differently and any
-- attempt to normalise them mangles some. That was the right call while
-- the tray was only trying to be legible. Asked for a tray that looks
-- like one row of buttons rather than a jumble, the answer changes, but
-- the reason for the old caution does not go away, so:
--
--   * an icon that cannot be identified means the button is LEFT ALONE
--     rather than stripped. A slightly out-of-place button is a much
--     better failure than an empty square;
--   * everything touched is recorded first, and Release puts back the
--     exact texture state it found;
--   * it is a setting, so if it does mangle one you can turn it off.
--
-- The treatment itself is the standard one: hide the addon's own ring
-- and backing, crop the icon's built-in border away, and put the icon on
-- ZacUI's flat plate with a pixel border.
local ICON_KEYS = { "icon", "Icon", "texture", "Texture" }

-- Four ways of finding the icon, in order of how much they can be
-- trusted. The bag layer taught this lesson expensively: identifying an
-- icon by one method and deleting everything else deleted every icon on
-- the builds where that method missed.
local function IconOf(btn)
    for _, key in ipairs(ICON_KEYS) do
        local t = btn[key]
        if type(t) == "table" and t.GetObjectType and t:GetObjectType() == "Texture" then
            return t
        end
    end
    local name = btn.GetName and btn:GetName()
    if name then
        for _, suffix in ipairs({ "Icon", "icon", "Texture" }) do
            local t = _G[name .. suffix]
            if t and t.GetObjectType and t:GetObjectType() == "Texture" then return t end
        end
    end
    -- By what it draws: an actual spell or item icon lives under
    -- Interface\Icons, and addon art usually says so in the path.
    local biggest, biggestArea
    for _, r in ipairs({ btn:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then
            local tex = r.GetTexture and r:GetTexture()
            local path = type(tex) == "string" and tex:lower() or ""
            if path:find("icon", 1, true) then return r end
            local w, h = r:GetSize()
            local area = (w or 0) * (h or 0)
            if not biggestArea or area > biggestArea then
                biggest, biggestArea = r, area
            end
        end
    end
    -- Last resort: the largest texture is nearly always the icon, but
    -- only trust it if there is something to it.
    if biggest and (biggestArea or 0) > 25 then return biggest end
    return nil
end

local function StyleButton(btn, size)
    if not DB().uniform then return end
    if btn._zTrayStyled then return end

    local icon = IconOf(btn)
    if not icon then
        -- Deliberately no fallback. Stripping a button whose icon we
        -- could not find leaves an empty square, which is worse than the
        -- button looking slightly different from its neighbours.
        btn._zTraySkipped = true
        return
    end
    btn._zTrayStyled = true

    local saved = original[btn]
    if saved and not saved.regions then
        saved.regions = {}
        for _, r in ipairs({ btn:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then
                local l, rr, t, b
                if r.GetTexCoord then l, _, _, _, rr, _, t, b = r:GetTexCoord() end
                saved.regions[#saved.regions + 1] = {
                    tex = r, shown = r:IsShown(),
                    coord = r.GetTexCoord and { r:GetTexCoord() } or nil,
                    layer = r.GetDrawLayer and r:GetDrawLayer() or nil,
                }
            end
        end
        saved.iconPoints = {}
        for i = 1, (icon.GetNumPoints and icon:GetNumPoints() or 0) do
            local p, rel, rp, x, y = icon:GetPoint(i)
            saved.iconPoints[i] = { p, rel, rp, x, y }
        end
        saved.icon = icon
    end

    -- Everything that is not the icon goes: the ring, the border, the
    -- background plate the addon drew for itself.
    for _, r in ipairs({ btn:GetRegions() }) do
        if r ~= icon and r.IsObjectType and r:IsObjectType("Texture")
            and not r._zui_own then
            local layer = r.GetDrawLayer and r:GetDrawLayer()
            -- The highlight is the only one worth keeping: it is what
            -- tells you the button is live under the cursor.
            if layer == "HIGHLIGHT" then
                r:SetColorTexture(1, 1, 1, 0.25)
            else
                r:Hide()
            end
        end
    end

    -- Crop the icon's own baked-in border away and fill the plate.
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    if icon.SetDrawLayer then icon:SetDrawLayer("ARTWORK") end
    SharpenIcon(icon)
    icon:Show()

    if not btn._zTrayPlate then
        local plate = btn:CreateTexture(nil, "BACKGROUND")
        plate._zui_own = true
        plate:SetAllPoints()
        plate:SetTexture(FLAT)
        btn._zTrayPlate = plate
        AddPixelBorder(btn)
    end
    local c = Col("elementBg")
    btn._zTrayPlate:SetVertexColor(c.r, c.g, c.b, 1)
end

local function UnstyleButton(btn)
    local saved = original[btn]
    if not saved or not saved.regions then return end
    for _, rec in ipairs(saved.regions) do
        local r = rec.tex
        if r then
            r:SetShown(rec.shown)
            if rec.coord and r.SetTexCoord then r:SetTexCoord(unpack(rec.coord)) end
            if rec.layer and r.SetDrawLayer then r:SetDrawLayer(rec.layer) end
        end
    end
    if saved.icon and saved.iconPoints then
        saved.icon:ClearAllPoints()
        for _, p in ipairs(saved.iconPoints) do
            saved.icon:SetPoint(p[1], p[2], p[3], p[4], p[5])
        end
    end
    if btn._zTrayPlate then btn._zTrayPlate:Hide() end
    for _, t in ipairs(btn._zui_borderTex or {}) do t:Hide() end
    btn._zTrayStyled = nil
end

-- ============================================================
-- LAYOUT
-- ============================================================
-- EACH BUTTON GETS A CELL, and the button is centred in it and SCALED.
--
-- The first version resized the buttons directly and cropped their icons.
-- That was wrong: a minimap button is not a bare icon. It is an icon plus
-- a ring plus a border plus a highlight, anchored with offsets tuned for
-- its own size - usually 31x31. Forcing it to 28x28 squashes those offsets
-- and cropping the icon slices into the ring, which is why the tray came
-- out as a grid of dark smudges.
--
-- Scaling keeps every internal proportion exactly as its author drew it.
-- The cell exists so the grid maths stays in tray coordinates while the
-- button lives in its own scaled space.
local function Cell(index)
    local cell = tray.cells[index]
    if not cell then
        cell = CreateFrame("Frame", nil, tray)
        tray.cells[index] = cell
    end
    -- Re-asserted every pass rather than only at creation: SetParent
    -- re-files a frame's level, and a cell that has drifted above the
    -- buttons would put an invisible, mouse-less frame over them.
    cell:SetFrameStrata(TRAY_STRATA)
    cell:SetFrameLevel(CELL_LEVEL)
    -- A cell is pure geometry. It must never take a click that belongs to
    -- the button sitting in it.
    cell:EnableMouse(false)
    return cell
end

-- STANDING DOWN. The tray lives in MEDIUM because that is the only
-- strata its buttons can be clicked in - LibDBIcon pins them there and
-- wins any argument about it. That also means a near-fullscreen window
-- cannot get above them by z-order without going above its own canvas
-- and eating every click meant for it. So when something owns the
-- screen, the tray gets out of the way instead.
local suppressed = false

-- Hides WE do must not read as the owner's: the Hide hook below checks
-- this flag, as every write in Layout checks `laying`.
local ownHide = false
local function HideAll()
    if bar then bar:Hide() end
    if tray then tray:Hide() end
    ownHide = true
    for btn in pairs(grabbed) do
        if btn.Hide then btn:Hide() end
    end
    ownHide = false
end

-- THE OWNER'S WISH. A button its addon hid - WeakAuras with its minimap
-- icon switched off, an addon that only shows its button in a group, a
-- LibDBIcon button whose saved table says hide - stays hidden in the tray
-- too. Before this the layout pass re-showed every grabbed button, which
-- is how a button someone had deliberately turned off kept turning up in
-- the tray. Intent is read from the owner's own Show/Hide calls (hooked
-- in Grab) and from LibDBIcon's db.hide.
local function OwnerHidden(btn)
    if btn._zOwnerHid then return true end
    local db = btn.db
    if type(db) == "table" and db.hide then return true end
    return false
end

-- THE BUTTONS' LAYOUT on ZacUI's standard shape (ZacUIDB.tray.layout:
-- grow, wrap, per line, gaps, padding, reverse). Its defaults ARE the
-- Columns / Space between buttons / Space around the edge settings, and
-- with nothing saved the grid below is placed exactly as it always was.
local function LayoutDefaults(db)
    db = db or DB()
    local size, gap = db.size or 28, tonumber(db.gap) or 4
    return { grow = "RIGHT", wrap = "DOWN", perLine = math.max(1, db.columns or 6),
        spacingX = gap, spacingY = gap, padding = tonumber(db.pad) or 6, itemW = size, itemH = size }
end
local function LayoutSpec(db)
    local l = db and db.layout
    if type(l) ~= "table" or next(l) == nil then return nil end
    return l
end
-- cells[1..n] (already size x size) re-placed by the saved layout; returns
-- the tray's width and height, or nil with nothing saved (the old grid stands)
local function LayoutCells(cells, n, container, db)
    local spec = LayoutSpec(db)
    if not (spec and ns.LayoutItems) or n < 1 then return nil end
    local w, h = ns.LayoutItems(cells, n, container, spec, LayoutDefaults(db))
    return w, h
end

-- ============================================================
-- DOCKED TO THE MINIMAP (ZacUIDB.tray.dock)
-- ============================================================
-- (2026-11-18, Zac picked this from the mocks: a column down the map's
-- side that comes out on mouseover.) The tray hangs on one edge of the
-- minimap, as long as that edge: filled along it, a second line further
-- out once the first is full. It comes out while the mouse is on the map
-- (Open on hover) or stays out (dockAlways), and the bar is a short tick
-- in the middle of the same edge (dockTick false = none). It keeps its own
-- button size and spaces, because a strip beside a 185 px map wants
-- smaller buttons than a flyout does: dockSize 22, dockGap 2, dockPad 4.
-- The tray and the tick take the map's scale, so they are measured in the
-- map's own units and grow with it.
--
-- (2026-11-18, later: "users should be able to pick, just use my choice
-- as default") The other two mocks are modes too:
--   "inside"  a band ON the map along its bottom edge: smaller buttons
--             (dockSize 18), centred, a second row above the first; it
--             keeps clear of a bottom corner icon that is showing, and
--             the minimap's own pieces at the bottom stand above it while
--             it is out (ns.MinimapLook.Lift). No tick.
--   "tab"     the bar is a small tab under the map's bottom-right corner
--             with the number of buttons on it; pointing at it (Open on
--             hover) or clicking it opens a grid, dockColumns wide (3),
--             in its place. The mouse on the map does nothing here.
local DOCK = { left = true, right = true, top = true, bottom = true, inside = true, tab = true }
local DOCK_GAP = 3                      -- clear of the map's outline and its hover ring
local TICK_LONG, TICK_THICK, TICK_REACH = 40, 2, 5
local TAB_W, TAB_H = 30, 14
local INSIDE_LIFT = 2                   -- between the band and the pieces standing above it
-- the side a strip slides in from: out of the map
local DOCK_FROM = { left = "right", right = "left", top = "down", bottom = "up", inside = "down", tab = "up" }

local function DockSide(db)
    db = db or DB()
    -- (no minimap to hang on: the bar)
    return Minimap and DOCK[db.dock] and db.dock or nil
end

-- the map, with its header and footer when ZacUI's minimap draws them
-- (the band on the map lies on the map itself)
local function DockHost()
    if DockSide() == "inside" then return Minimap end
    local p = _G.ZacUIMinimapPanel
    if p and p:IsShown() then return p end
    return Minimap
end

-- "inside": the room a bottom corner icon that is showing keeps (the
-- tracking icon, the battleground crest): left, right. One showing is
-- kept clear of on both sides, so the band stays in the middle of the map.
local function InsideInsets()
    local ML = ns.MinimapLook
    local busy = ML and ML.CornerBusy
    if not busy then return 0, 0 end
    local w = ((busy("BOTTOMLEFT") or busy("BOTTOMRIGHT")) and ((ML.ICON or 22) + 6)) or 0
    return w, w
end

-- the minimap's pieces at the bottom stand this much higher (0 = back)
local function SetLift(px)
    local ML = ns.MinimapLook
    if ML and ML.Lift then ML.Lift(px) end
end

local function HostScale(host)
    local us = UIParent:GetEffectiveScale() or 1
    local k = (host:GetEffectiveScale() or 1) / (us > 0 and us or 1)
    return k > 0 and k or 1
end

-- button size, space between, space round the edge: the strip's or the flyout's
local function DockSizeDefault(side) return side == "inside" and 18 or 22 end
local function Metrics(db)
    local side = DockSide(db)
    if side then
        return tonumber(db.dockSize) or DockSizeDefault(side), tonumber(db.dockGap) or 2, tonumber(db.dockPad) or 4
    end
    return db.size, tonumber(db.gap) or 4, tonumber(db.pad) or 6
end

-- cells[1..n] (already size x size) along the `side` of a hostW x hostH
-- map; returns the strip's width and height
local function DockCells(cells, n, container, side, hostW, hostH, size, gap, pad)
    if side == "inside" then
        -- rows across the band (hostW: the room between the corner icons),
        -- each centred, the first along the map's edge and the next above it
        local per = math.max(1, math.floor((hostW - pad * 2 + gap) / (size + gap)))
        local lines = math.max(1, math.ceil(n / per))
        for i = 1, n do
            local line = math.floor((i - 1) / per)
            local inLine = (line < lines - 1) and per or (n - per * (lines - 1))
            local rowW = inLine * size + (inLine - 1) * gap
            local x = math.floor((hostW - rowW) / 2 + 0.5) + ((i - 1) % per) * (size + gap)
            local cell = cells[i]
            cell:ClearAllPoints()
            cell:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", x, pad + line * (size + gap))
        end
        return hostW, pad * 2 + lines * size + (lines - 1) * gap
    end
    local upright = side == "left" or side == "right"
    local run = upright and hostH or hostW
    local per = math.max(1, math.floor((run - pad * 2 + gap) / (size + gap)))
    for i = 1, n do
        local along = pad + ((i - 1) % per) * (size + gap)
        local out = pad + math.floor((i - 1) / per) * (size + gap)
        local cell = cells[i]
        cell:ClearAllPoints()
        if side == "left" then
            cell:SetPoint("TOPRIGHT", container, "TOPRIGHT", -out, -along)
        elseif side == "right" then
            cell:SetPoint("TOPLEFT", container, "TOPLEFT", out, -along)
        elseif side == "top" then
            cell:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", along, out)
        else
            cell:SetPoint("TOPLEFT", container, "TOPLEFT", along, -out)
        end
    end
    local lines = math.max(1, math.ceil(n / per))
    local thick = pad * 2 + lines * size + (lines - 1) * gap
    if upright then return thick, hostH end
    return hostW, thick
end

-- frame (the strip or the tick) against that edge of the host; inset: the
-- band on the map starts that far in from the map's left edge
local function DockPoint(frame, host, side, centred, inset)
    frame:ClearAllPoints()
    if side == "inside" then
        frame:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", inset or 0, 0)
    elseif side == "tab" then
        -- the tab and the grid it opens: under the map's bottom-right corner
        frame:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, -DOCK_GAP)
    elseif side == "left" then
        frame:SetPoint(centred and "RIGHT" or "TOPRIGHT", host, centred and "LEFT" or "TOPLEFT", -DOCK_GAP, 0)
    elseif side == "right" then
        frame:SetPoint(centred and "LEFT" or "TOPLEFT", host, centred and "RIGHT" or "TOPRIGHT", DOCK_GAP, 0)
    elseif side == "top" then
        frame:SetPoint(centred and "BOTTOM" or "BOTTOMLEFT", host, centred and "TOP" or "TOPLEFT", 0, DOCK_GAP)
    else
        frame:SetPoint(centred and "TOP" or "TOPLEFT", host, centred and "BOTTOM" or "BOTTOMLEFT", 0, -DOCK_GAP)
    end
end

-- How the tray opens ("openAnim") and closes ("closeAnim"): what is
-- saved, else docked it slides out of the map's edge and back into it,
-- else at once. nil = at once.
local function AnimDefault(key, db)
    local side = DockSide(db)
    if not side then return nil end
    return { style = "slide", duration = key == "closeAnim" and 0.12 or 0.15, dir = DOCK_FROM[side], distance = 8 }
end
local function AnimSpec(key)
    local db = DB()
    local spec = db[key]
    if type(spec) ~= "table" then spec = AnimDefault(key, db) end
    if type(spec) == "table" and spec.style and spec.style ~= "none" then return spec end
    return nil
end

local function Layout()
    if laying then return end
    -- before the tray is built (a settings slider moved first) there is
    -- nothing to lay out
    if not tray then return end
    if suppressed then
        -- Not just an early return: the owning addons re-show their
        -- buttons on their own schedule, and a layout pass that only
        -- skipped would let them drift back one at a time.
        HideAll()
        return
    end
    laying = true
    local db = DB()
    local dock = DockSide(db)
    local size, gap, pad = Metrics(db)
    local cols = math.max(1, db.columns)
    if dock == "tab" then cols = math.max(1, tonumber(db.dockColumns) or 3) end

    local n = 0
    for _, btn in ipairs(order) do
        if grabbed[btn] and OwnerHidden(btn) then
            -- parked out of the way, still ours; its cell is not spent
            if btn:IsShown() then btn:Hide() end
        elseif grabbed[btn] then
            local col = n % cols
            local row = math.floor(n / cols)
            n = n + 1

            local cell = Cell(n)
            cell:SetSize(size, size)
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", tray, "TOPLEFT",
                pad + col * (size + gap), -(pad + row * (size + gap)))
            cell:Show()

            -- Scale from the button's ORIGINAL width, not its current one,
            -- or each pass scales the result of the last one.
            local native = (original[btn] and original[btn].w) or btn:GetWidth() or size
            if native < 1 then native = size end

            btn:SetParent(cell)
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", cell, "CENTER", 0, 0)
            btn._zCell = cell        -- what the fight-back hooks compare against
            btn:SetScale(size / native)

            -- Set to the tray's own strata, which is deliberately the one
            -- LibDBIcon insists on. For its buttons this is a no-op, so
            -- there is nothing to argue about; for a button some other
            -- addon parked in a LOWER strata it is a genuine rescue. What
            -- it must never be is HIGHER than the tray - see the block at
            -- the top of this file.
            btn:SetFrameStrata(TRAY_STRATA)
            btn:SetFrameLevel(BUTTON_LEVEL)

            -- Re-asserted because the owning addon may have turned mouse
            -- input off while its button was hidden behind the minimap.
            btn:EnableMouse(true)
            if btn.SetMouseClickEnabled then btn:SetMouseClickEnabled(true) end
            if btn.SetMouseMotionEnabled then btn:SetMouseMotionEnabled(true) end

            -- HIT RECT INSETS shrink a frame's clickable area without
            -- changing anything you can see, which makes them invisible as
            -- a cause. Several addons inset their button to keep clicks off
            -- the minimap ring behind it - sensible on the minimap, and in
            -- a tray it just leaves a button that only responds near its
            -- centre. The original values are recorded in Grab and put back
            -- by Release.
            if btn.SetHitRectInsets then btn:SetHitRectInsets(0, 0, 0, 0) end

            -- ALPHA ON THE REGIONS, not just the frame. Frame alpha is a
            -- multiplier - a texture at alpha 0 stays invisible however
            -- opaque its button is. Minimap-button faders (and some addons
            -- themselves) dim the ICON rather than the button, which shows
            -- up as a tray full of empty rings: the border renders, the
            -- icon does not.
            btn:SetAlpha(1)
            if btn.GetRegions then
                for _, region in ipairs({ btn:GetRegions() }) do
                    if region.IsObjectType and region:IsObjectType("Texture")
                        and region.GetAlpha and region:GetAlpha() < 1 then
                        region:SetAlpha(1)
                    end
                end
            end
            for _, key in ipairs(ICON_KEYS) do
                local piece = btn[key]
                if piece and piece.SetAlpha then
                    piece:SetAlpha(1)
                    if piece.SetDesaturated then piece:SetDesaturated(false) end
                end
            end
            StyleButton(btn, size)
            btn:Show()
        end
    end
    for i = n + 1, #tray.cells do tray.cells[i]:Hide() end

    local rows = math.max(1, math.ceil(n / cols))
    local w = pad * 2 + math.min(n, cols) * size + (math.min(n, cols) - 1) * gap
    local h = pad * 2 + rows * size + (rows - 1) * gap
    local lw, lh
    if dock == "tab" then
        -- (the grid placed above stands: dockColumns wide)
    elseif dock then
        local host = DockHost()
        local hostW = host:GetWidth() or 0
        if dock == "inside" then
            local li, ri = InsideInsets()
            hostW = math.max(size + pad * 2, hostW - li - ri)
        end
        lw, lh = DockCells(tray.cells, n, tray, dock, hostW, host:GetHeight() or 0, size, gap, pad)
    else
        lw, lh = LayoutCells(tray.cells, n, tray, db)
    end
    if lw then tray:SetSize(lw, lh) else tray:SetSize(math.max(size + pad * 2, w), h) end
    -- (a strip is too narrow for the words: with nothing in it, it is not shown at all)
    tray.empty:SetShown(n == 0 and not dock)
    tray.count = n
    if bar and bar._zTab then bar._zTab.count:SetText(tostring(n)) end
    if dock and n == 0 and tray:IsShown() then tray:Hide() end
    -- (the band grew or lost a row while out: the pieces above it follow)
    if dock == "inside" and tray:IsShown() then SetLift((tray:GetHeight() or 0) + INSIDE_LIFT) end
    laying = false
end

local function QueueLayout()
    if queued or laying then return end
    queued = true
    C_Timer.After(0.05, function()
        queued = nil
        Layout()
    end)
end

-- ============================================================
-- GRABBING
-- ============================================================
local function Skippable(name)
    if BLIZZARD[name] then return true end
    for _, prefix in ipairs(SKIP_PREFIX) do
        if name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function Grab(btn)
    if not btn or grabbed[btn] then return end
    local name = btn.GetName and btn:GetName()
    if not name or Skippable(name) then return end
    if DB().ignore[name] then return end

    -- Record everything before the first write, so Release can be exact.
    local point, rel, relPoint, x, y = btn:GetPoint(1)
    local hl, hr, ht, hb
    if btn.GetHitRectInsets then hl, hr, ht, hb = btn:GetHitRectInsets() end
    original[btn] = {
        parent = btn:GetParent(), point = point, rel = rel,
        relPoint = relPoint, x = x, y = y,
        scale = btn:GetScale(), strata = btn:GetFrameStrata(),
        level = btn:GetFrameLevel(), alpha = btn:GetAlpha(),
        w = btn:GetWidth(), h = btn:GetHeight(),
        shown = btn:IsShown(),
        hit = { hl or 0, hr or 0, ht or 0, hb or 0 },
    }

    grabbed[btn] = name
    order[#order + 1] = btn

    -- THE FIGHT-BACK GUARD. Anything that moves or reparents this button
    -- while we own it gets undone on the next frame. `laying` keeps our
    -- own writes from re-entering.
    if not btn._zTrayHooked then
        btn._zTrayHooked = true
        -- An owner that re-anchors its button on a timer would otherwise
        -- relayout the whole tray twenty times a second; only a call that
        -- actually moves it off its cell queues one.
        hooksecurefunc(btn, "SetPoint", function(b, point, rel)
            if laying or not grabbed[b] then return end
            if b._zCell and point == "CENTER" and rel == b._zCell then return end
            QueueLayout()
        end)
        hooksecurefunc(btn, "SetParent", function(b, parent)
            if laying or not grabbed[b] then return end
            if b._zCell and parent == b._zCell then return end
            QueueLayout()
        end)
        -- LibDBIcon re-asserts strata and level on its own refresh, which
        -- is how a button that WAS on top silently drops behind the tray
        -- a second later. Same treatment as SetPoint: anything we did not
        -- do gets undone on the next frame.
        hooksecurefunc(btn, "SetFrameStrata", function()
            if not laying and grabbed[btn] then QueueLayout() end
        end)
        hooksecurefunc(btn, "SetFrameLevel", function()
            if not laying and grabbed[btn] then QueueLayout() end
        end)
        btn:HookScript("OnShow", QueueLayout)
        btn:HookScript("OnHide", QueueLayout)
        -- the owner's own Show/Hide is intent; ours (laying, ownHide) is not
        hooksecurefunc(btn, "Hide", function()
            if not laying and not ownHide and grabbed[btn] then btn._zOwnerHid = true end
        end)
        hooksecurefunc(btn, "Show", function()
            if not laying and grabbed[btn] then btn._zOwnerHid = nil end
        end)
        hooksecurefunc(btn, "SetShown", function(_, v)
            if not laying and not ownHide and grabbed[btn] then btn._zOwnerHid = (not v) or nil end
        end)
    end
    -- a button that arrives hidden was hidden by its owner
    btn._zOwnerHid = (not btn:IsShown()) or nil

    -- DELIBERATELY NO RESTYLING. These buttons belong to other addons and
    -- every one of them draws itself differently - LibDBIcon's circular
    -- mask, hand-rolled square ones, a few that are just a texture. Any
    -- attempt to normalise them (crop the icon, hide the border, add our
    -- own edge) mangles some of them, and the tray is legible without it.
    -- ZacUI moves them and scales them. That is all.
    QueueLayout()
end

local function Release(btn)
    local saved = original[btn]
    if not saved then return end
    laying = true
    UnstyleButton(btn)
    btn:SetParent(saved.parent or Minimap)
    btn:ClearAllPoints()
    if saved.point then
        btn:SetPoint(saved.point, saved.rel, saved.relPoint, saved.x, saved.y)
    end
    btn:SetSize(saved.w, saved.h)
    btn:SetScale(saved.scale or 1)
    if saved.strata then btn:SetFrameStrata(saved.strata) end
    btn:SetFrameLevel(saved.level or 1)
    if saved.hit and btn.SetHitRectInsets then
        btn:SetHitRectInsets(saved.hit[1], saved.hit[2], saved.hit[3], saved.hit[4])
    end
    btn:SetAlpha(saved.alpha)
    btn:SetShown(saved.shown)
    laying = false
    grabbed[btn] = nil
    original[btn] = nil
    for i, b in ipairs(order) do
        if b == btn then table.remove(order, i) break end
    end
end

-- ============================================================
-- SCANNING
-- ============================================================
-- Candidates come from the three frames addons actually parent to. Size
-- is the discriminator: a minimap button is roughly icon-sized, and the
-- things that are not (invisible driver frames, the zone text) are not.
local function Scan()
    if InCombatLockdown and InCombatLockdown() then return end

    -- EXPLICIT APPENDS, not a table literal. `ipairs({ Minimap,
    -- MinimapBackdrop, MinimapCluster })` stops at the first nil, so on a
    -- build where any one of them is missing every host AFTER it is
    -- silently never scanned - and the tray collects nothing at all with
    -- no error to show for it. Same hole-in-ipairs trap the font system
    -- hit; it is worth being paranoid about in this codebase.
    local hosts = {}
    local function AddHost(f) if f then hosts[#hosts + 1] = f end end
    AddHost(Minimap)
    AddHost(MinimapBackdrop)
    AddHost(MinimapCluster)

    for _, host in ipairs(hosts) do
        if host.GetChildren then
            for _, child in ipairs({ host:GetChildren() }) do
                local otype = child.GetObjectType and child:GetObjectType()
                if (otype == "Button" or otype == "Frame")
                    and not grabbed[child] then
                    local w = child:GetWidth() or 0
                    if w >= 15 and w <= 45 then
                        Grab(child)
                    end
                end
            end
        end
    end
end

-- ============================================================
-- BAR AND TRAY
-- ============================================================
local closeTimer
local watch      -- docked: reads the mouse on the map (WatchTick)

-- The bar is shown unless something owns the screen. Docked it is the
-- tick, which also goes while the strip is out, when the strip is always
-- out, with the map hidden, and when the tick is switched off.
local function ShowBar()
    if not bar then return end
    local db = DB()
    local on = not suppressed
    local dock = on and DockSide(db)
    if dock == "inside" then
        on = false                  -- (the band has no tick: the map itself is its handle)
    elseif dock == "tab" then
        on = not (tray and tray:IsShown()) and Minimap:IsVisible() and true or false
    elseif dock then
        on = db.dockTick ~= false and not db.dockAlways
            and not (tray and tray:IsShown()) and Minimap:IsVisible() and true or false
    end
    bar:SetShown(on)
end

-- The bar where its mode puts it.
local function PlaceBar()
    local db = DB()
    local dock = DockSide(db)
    -- (the tab's own art: only as the tab)
    if bar._zTab then
        bar._zTab:SetShown(dock == "tab")
        bar._zFill:SetShown(dock ~= "tab")
    end
    if dock == "tab" then
        local host = DockHost()
        bar:SetScale(HostScale(host))
        bar:SetSize(TAB_W, TAB_H)
        bar:SetHitRectInsets(0, 0, 0, 0)
        DockPoint(bar, host, dock, true)
        return
    end
    if dock then
        local host = DockHost()
        local upright = dock == "left" or dock == "right"
        bar:SetScale(HostScale(host))
        bar:SetSize(upright and TICK_THICK or TICK_LONG, upright and TICK_LONG or TICK_THICK)
        -- (a 2 px line is drawn; the mouse gets 5 more on each side of it)
        bar:SetHitRectInsets(upright and -TICK_REACH or 0, upright and -TICK_REACH or 0,
            upright and 0 or -TICK_REACH, upright and 0 or -TICK_REACH)
        DockPoint(bar, host, dock, true)
        return
    end
    bar:SetScale(1)
    bar:SetHitRectInsets(0, 0, 0, 0)
    bar:SetSize(db.barWidth, db.barHeight)
    bar:ClearAllPoints()
    -- DEFAULT: top centre of the screen, not under the minimap. The bar is
    -- a thin sliver you reach for deliberately; the top edge is dead space
    -- in almost every layout, and anchoring to the minimap put it wherever
    -- the minimap happened to be - which for a moved or hidden minimap is
    -- off screen. Anchored to UIParent it needs no moving to be usable.
    if db.point then
        bar:SetPoint(db.point, UIParent, db.point, db.x or 0, db.y or 0)
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -2)
    end
end

-- Put the tray away, with the close animation if there is one.
local function HideTray()
    if not tray or not tray:IsShown() then return end
    local spec = AnimSpec("closeAnim")
    if spec and ns.Motion and ns.Motion.Hide then
        tray._zClosing = true        -- (OnHide clears it; the watcher reopens a strip caught mid-close)
        ns.Motion.Hide(tray, spec)
    else
        tray:Hide()
    end
end

local function OpenTray()
    if closeTimer then closeTimer:Cancel() closeTimer = nil end
    Layout()
    local dock = DockSide()
    -- (docked with nothing collected: no empty strip beside the map)
    if dock and tray.count == 0 then return end
    if dock then
        local host = DockHost()
        tray:SetScale(HostScale(host))
        DockPoint(tray, host, dock, false, dock == "inside" and (InsideInsets()) or nil)
    else
        tray:SetScale(1)
        -- The tray grows away from whichever screen half the bar sits in, so
        -- it never opens off the bottom of the screen.
        tray:ClearAllPoints()
        local mid = (UIParent:GetHeight() or 768) / 2
        if (bar:GetBottom() or 0) > mid then
            tray:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
        else
            tray:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 4)
        end
    end
    -- reopened while its close animation runs: that animation stops here
    if ns.Motion and ns.Motion.Stop then ns.Motion.Stop(tray) end
    tray._zClosing = nil
    tray:Show()
    bar:SetAlpha(1)
    if dock == "inside" then SetLift((tray:GetHeight() or 0) + INSIDE_LIFT) end
end

-- docked: what keeps the strip out besides the mouse being on it
local function DockHeld()
    local db = DB()
    local side = DockSide(db)
    -- (the tab's grid is held by the mouse on the grid or the tab alone)
    if not side or side == "tab" then return false end
    if db.dockAlways then return true end
    return db.openOnHover and MouseIsOver(DockHost()) and true or false
end

local function CloseTray(delay)
    if closeTimer then closeTimer:Cancel() end
    local db = DB()
    closeTimer = C_Timer.NewTimer(delay or db.autoClose, function()
        closeTimer = nil
        if tray:IsMouseOver() or bar:IsMouseOver() or DockHeld() then return end
        HideTray()
        bar:SetAlpha(db.barAlpha)
    end)
end

-- DOCKED: THE MOUSE ON THE MAP. The map has no OnEnter to borrow - its
-- pills, corner icons and secure buttons sit on top of it - so the mouse
-- is read by rect, ten times a second, only in a docked mode and only
-- while the map is on screen (this frame is the map's child). Two rect
-- tests and a few table reads a pass; the layout runs when the strip
-- opens, not here.
local function WatchTick(self, dt)
    self.t = (self.t or 0) + dt
    if self.t < 0.1 then return end
    self.t = 0
    if suppressed then return end
    local db = DB()
    local side = DockSide(db)
    if not side then return end
    -- ZacUI's minimap drew (or dropped) its header and footer since the
    -- tick was placed: onto the map as it is now
    local host = DockHost()
    if host ~= self.host then
        self.host = host
        PlaceBar()
    end
    -- (the tab is pointed at or clicked: the mouse on the map opens nothing)
    if side == "tab" then return end
    local out = tray:IsShown() and not tray._zClosing
    if db.dockAlways then
        if not out and tray.count ~= 0 then OpenTray() end
        return
    end
    if not db.openOnHover then return end
    if MouseIsOver(host) or (out and tray:IsMouseOver()) then
        if not out then
            if tray.count ~= 0 then OpenTray() end
        elseif closeTimer then
            closeTimer:Cancel()
            closeTimer = nil
        end
    elseif out and not closeTimer then
        CloseTray()
    end
end

-- the bar (or tick) and the watcher, as the mode has them
local function Dock()
    PlaceBar()
    watch.host = DockHost()
    watch.side = DockSide()
    watch:SetScript("OnUpdate", watch.side and WatchTick or nil)
    ShowBar()
end

-- A dock setting changed (the Button tray tab): the strip put away, then
-- everything placed for the mode as it now is.
local function ApplyDock()
    if not bar then return end
    if closeTimer then closeTimer:Cancel() closeTimer = nil end
    if ns.Motion and ns.Motion.Stop then ns.Motion.Stop(tray) end
    tray:Hide()
    Dock()
    bar:SetAlpha(DB().barAlpha)
    Layout()
end

local function BuildUI()
    local db = DB()

    bar = CreateFrame("Button", "ZacUITrayBar", UIParent)
    bar:SetFrameStrata(BAR_STRATA)
    bar:SetFrameLevel(BAR_LEVEL)
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar:RegisterForDrag("LeftButton")

    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    fill:SetTexture(FLAT)
    bar._zFill = fill

    local hl = bar:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)

    -- AS THE TAB ("tab"): a small dark plate with a grid mark and the
    -- number of buttons, in the accent colour. Shown only in that mode
    -- (PlaceBar); the accent sliver above is the bar and the tick.
    local tab = CreateFrame("Frame", nil, bar)
    tab:SetAllPoints()
    local tbg = tab:CreateTexture(nil, "BACKGROUND")
    tbg:SetAllPoints()
    tbg:SetTexture(FLAT)
    tab._zFill = tbg
    AddPixelBorder(tab)
    tab.dots = {}
    for i = 1, 4 do
        local d = tab:CreateTexture(nil, "ARTWORK")
        d:SetTexture(FLAT)
        d:SetSize(3, 3)
        d:SetPoint("TOPLEFT", tab, "LEFT", 5 + ((i - 1) % 2) * 4, 3.5 - math.floor((i - 1) / 2) * 4)
        tab.dots[i] = d
    end
    tab.count = UI.Font(tab, UI.F.SMALL, { text = "0", cat = "ui", key = "accent" })
    tab.count:SetPoint("LEFT", tab, "LEFT", 15, 0)
    tab:Hide()
    bar._zTab = tab

    bar._zPaint = function(self)
        local a = Col("accent")
        self._zFill:SetVertexColor(a.r, a.g, a.b, 1)
        local w = Col("windowBg")
        tab._zFill:SetVertexColor(w.r, w.g, w.b, 0.95)
        for _, d in ipairs(tab.dots) do d:SetVertexColor(a.r, a.g, a.b, 1) end
    end
    bar:_zPaint()
    bar:SetAlpha(db.barAlpha)

    -- (docked, it is the tick on the map's edge: the map is what moves)
    bar:SetScript("OnDragStart", function(self)
        if DB().locked or DockSide() then return end
        self:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        local t = DB()
        t.point, t.x, t.y = point, x, y
    end)
    -- in ZacUI's mover mode too (Movers page, Edit Mode), its spot kept
    -- where its own drag keeps it. Docked it has no spot of its own: the
    -- bar's saved one is left as it is for when the bar comes back.
    if ns.RegisterMover then
        ns.RegisterMover("tray", "Minimap button tray", function() return bar end, "TOP", 0, -2, nil, {
            get = function()
                local t = DB()
                if DockSide(t) then return nil end
                if t.point then return t.point, t.x or 0, t.y or 0 end
            end,
            set = function(point, x, y)
                local t = DB()
                if DockSide(t) then PlaceBar() return end
                t.point, t.x, t.y = point, x, y
            end,
            reset = function()
                if DockSide() then PlaceBar() return end
                bar:ClearAllPoints()
                bar:SetPoint("TOP", UIParent, "TOP", 0, -2)
            end,
            off = function()
                if DockSide() then
                    return "It sits on the minimap's edge, so it moves with the minimap. Where it sits is on the Button tray tab."
                end
            end,
            own = true,
            -- (its buttons are sized on the Button tray tab)
            scale = false,
            -- (2026-11-20) and on its box in Edit Mode: that tab's own
            -- sliders (the bar itself only while it is not docked to the map)
            sizes = function()
                if DockSide() then return nil end
                local function Row(label, key, def, lo, hi, step, after)
                    return { label = label, unit = "px", min = lo, max = hi, step = step, fine = 1, def = def,
                        get = function() return tonumber(DB()[key]) or def end,
                        set = function(v)
                            DB()[key] = v
                            after(v)
                        end }
                end
                return {
                    Row("Button size", "size", 28, 16, 44, 2, function() Layout() end),
                    Row("Space between", "gap", 4, 0, 12, 1, function() Layout() end),
                    Row("Bar width", "barWidth", 90, 30, 300, 5, function(v) if bar then bar:SetWidth(v) end end),
                    Row("Bar height", "barHeight", 6, 2, 24, 1, function(v) if bar then bar:SetHeight(v) end end),
                }
            end,
        })
    end
    bar:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if ns.OpenConfig then ns.OpenConfig("tray") end
            return
        end
        if tray:IsShown() then
            HideTray()
            bar:SetAlpha(DB().barAlpha)
        else
            OpenTray()
        end
    end)
    bar:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if DB().openOnHover then OpenTray() end
    end)
    bar:SetScript("OnLeave", function() CloseTray() end)

    tray = CreateFrame("Frame", "ZacUITray", UIParent)
    -- MEDIUM at a LOW level, on purpose: the tray has to end up underneath
    -- the buttons it is holding, and level is the only part of that it can
    -- decide on its own. See the block at the top of this file.
    tray:SetFrameStrata(TRAY_STRATA)
    tray:SetFrameLevel(TRAY_LEVEL)
    tray:SetClampedToScreen(true)
    -- Mouse ON, but harmlessly: this only exists so hovering the tray
    -- cancels the auto-close timer. At level 4 against buttons at 8 the
    -- buttons take every click that lands on one, and the tray only hears
    -- about the gaps between them.
    tray:EnableMouse(true)
    tray:Hide()

    local bg = tray:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(FLAT)
    tray._zFill = bg
    tray._zPaint = function(self)
        local w = Col("windowBg")
        self._zFill:SetVertexColor(w.r, w.g, w.b, 0.95)
    end
    tray:_zPaint()
    AddPixelBorder(tray)

    tray.empty = UI.Font(tray, UI.F.SMALL,
        { text = "Nothing collected yet", cat = "text", key = "gray" })
    tray.empty:SetPoint("CENTER")

    tray.cells = {}
    tray:SetScript("OnLeave", function() CloseTray() end)
    tray:SetScript("OnEnter", function()
        if closeTimer then closeTimer:Cancel() closeTimer = nil end
    end)
    -- (docked: the tick goes while the strip is out and comes back after)
    tray:SetScript("OnShow", ShowBar)
    tray:SetScript("OnHide", function(self)
        self._zClosing = nil
        SetLift(0)
        ShowBar()
    end)

    watch = CreateFrame("Frame", nil, Minimap)
    watch:SetScript("OnShow", ShowBar)
    watch:SetScript("OnHide", function()
        if DockSide() then tray:Hide() end
        ShowBar()
    end)
    Dock()
end

-- ============================================================
-- DIAGNOSTIC
-- ============================================================
-- ZacUI IS the button-stash addon now, so there is deliberately no check
-- for the standalone one and no deference to it. If both are somehow
-- running they will fight over the same buttons, and the honest fix is to
-- turn one off - not for this module to quietly do nothing and leave the
-- player wondering why its settings have no effect.
-- FULL DUMP. Four rounds of guessing at this from screenshots is four too
-- many: "the icons are dark" has at least six plausible causes and they
-- are indistinguishable by eye. This prints the state that actually
-- decides what you see - alpha, scale, strata, level, and every texture
-- region with its own alpha and path.
local function Dump()
    Print("--- tray dump ---")
    if not tray then
        Print("no tray built.")
        return
    end
    Print(string.format("tray: strata=%s level=%d shown=%s alpha=%.2f size=%.0fx%.0f",
        tostring(tray:GetFrameStrata()), tray:GetFrameLevel() or -1,
        tostring(tray:IsShown()), tray:GetAlpha() or -1,
        tray:GetWidth() or 0, tray:GetHeight() or 0))
    -- The invariant that decides whether anything in here is clickable,
    -- stated in the dump so it never has to be inferred from the numbers
    -- again: buttons must be at or above the tray, never below it.
    Print(string.format("expect: buttons at %s lvl>=%d (tray lvl %d, cells lvl %d)",
        TRAY_STRATA, BUTTON_LEVEL, TRAY_LEVEL, CELL_LEVEL))

    local n = 0
    for _, btn in ipairs(order) do
        if grabbed[btn] then
            n = n + 1
            if n > 12 then
                Print("...more, truncated.")
                break
            end
            local parent = btn:GetParent()
            Print(string.format("|cffffd100%s|r", tostring(grabbed[btn])))
            Print(string.format("  frame: strata=%s lvl=%d parentLvl=%d "
                .. "alpha=%.2f scale=%.2f shown=%s mouse=%s",
                tostring(btn:GetFrameStrata()), btn:GetFrameLevel() or -1,
                parent and parent:GetFrameLevel() or -1,
                btn:GetAlpha() or -1, btn:GetScale() or -1,
                tostring(btn:IsShown()),
                tostring(btn.IsMouseEnabled and btn:IsMouseEnabled())))
            if btn.GetRegions then
                for _, region in ipairs({ btn:GetRegions() }) do
                    if region.IsObjectType and region:IsObjectType("Texture") then
                        local tex = region.GetTexture and region:GetTexture()
                        Print(string.format("  tex: layer=%s alpha=%.2f %s",
                            tostring(region.GetDrawLayer and region:GetDrawLayer()),
                            region.GetAlpha and region:GetAlpha() or -1,
                            tostring(tex):sub(1, 46)))
                    end
                end
            end
        end
    end
    if n == 0 then Print("no buttons collected.") end
end

-- WHAT IS ACTUALLY UNDER THE CURSOR.
--
-- Every z-order theory so far has been an inference from a list of numbers,
-- and inference is how this took four rounds. The client already knows the
-- answer: whichever frame owns the mouse right now is by definition the one
-- receiving the click. This asks it, after a delay long enough to move the
-- pointer onto a tray button, and walks up the parent chain so the answer
-- includes WHOSE frame it is.
--
-- If the tray is still swallowing clicks this prints ZacUITray. If
-- something else is on top it prints that instead, by name. Either way
-- there is nothing left to guess at.
local function Focus(delay)
    delay = tonumber(delay) or 3
    Print(string.format("hover a tray button - reading the mouse in %.0fs...", delay))
    C_Timer.After(delay, function()
        local focus
        if GetMouseFoci then
            local list = GetMouseFoci()
            focus = list and list[1]
        elseif GetMouseFocus then
            focus = GetMouseFocus()
        end
        if not focus then
            Print("nothing under the cursor - the click is going to the world.")
            return
        end
        Print("--- mouse focus ---")
        local f, depth = focus, 0
        while f and depth < 6 do
            local name = (f.GetName and f:GetName()) or "<anonymous>"
            local mine = grabbed[f] and " |cff66ff66(a tray button)|r"
                or (f == tray and " |cffff9900(the tray itself)|r")
                or (f == bar and " (the tray bar)") or ""
            Print(string.format("  %s%s strata=%s lvl=%s%s",
                string.rep("  ", depth), name,
                tostring(f.GetFrameStrata and f:GetFrameStrata()),
                tostring(f.GetFrameLevel and f:GetFrameLevel()), mine))
            f = f.GetParent and f:GetParent()
            depth = depth + 1
        end
    end)
end

local function Diagnose()
    Print("--- button tray ---")
    Print("module: "
        .. (ZacUIDB.modules and ZacUIDB.modules.tray and "|cff66ff66enabled|r"
            or "|cffff6666disabled|r"))
    Print("tray built: " .. (bar and "yes" or "|cffff9900no|r"))
    local n = 0
    for _ in pairs(grabbed) do n = n + 1 end
    Print("buttons collected: " .. n)
    if bar and DockSide() then
        Print("on the minimap's edge: " .. DockSide())
    elseif bar then
        local point, _, _, x, y = bar:GetPoint(1)
        Print("bar anchored: " .. tostring(point) .. " "
            .. string.format("%.0f, %.0f", x or 0, y or 0))
    end
    if not bar then
        Print("|cffff9900The module is off - nothing has been built.|r")
    end
    Print("run |cffffd100/zui traydump|r for the full per-button state,")
    Print("or |cffffd100/zui trayfocus|r then hover a button to see what")
    Print("is actually receiving the click.")
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.tray = function()
    if bar then
        QueueLayout()
        return
    end

    BuildUI()
    -- the look settings (colours, open animation) take hold at once
    local TL = ns.MinimapLook and ns.MinimapLook.Tray
    if TL and TL.Install then pcall(TL.Install) end
    -- Settings changed. A profile or an import that moved the buttons
    -- between the bar and the map: everything placed for the new mode.
    -- Docked as before: the map may have changed size or look, so the tick
    -- and the strip are measured against it again.
    if ns.OnSettingsChanged and ns.Coalesce then
        ns.OnSettingsChanged(ns.Coalesce(function()
            if DockSide() ~= watch.side then
                ApplyDock()
            elseif watch.side then
                Dock()
                QueueLayout()
            end
        end))
    end

    -- Addons create their minimap buttons on their own schedule, and some
    -- do it minutes in. A short burst catches the login crowd; the slow
    -- ticker catches stragglers without costing anything measurable.
    C_Timer.After(1, Scan)
    C_Timer.After(5, Scan)
    if not ZUI._trayTicker then
        ZUI._trayTicker = C_Timer.NewTicker(15, Scan)
    end

    -- LibDBIcon announces new icons directly, which is faster and cheaper
    -- than waiting for the next sweep.
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBIcon and LDBIcon.RegisterCallback then
        pcall(LDBIcon.RegisterCallback, LDBIcon, {}, "LibDBIcon_IconCreated",
            function() C_Timer.After(0.2, Scan) end)
    end
end

-- shared with later ZacUI files
-- Called by anything that takes over the screen. Idempotent, and it
-- restores by relaying out rather than by remembering which buttons were
-- shown - the owning addons may have changed their minds meanwhile.
local function SetSuppressed(v)
    v = v and true or false
    if suppressed == v then return end
    suppressed = v
    if suppressed then
        HideAll()
    else
        ShowBar()
        Layout()
    end
end

ns.Tray = {
    Diagnose = Diagnose,
    StyleButton = StyleButton,
    UnstyleButton = UnstyleButton,
    IconOf = IconOf,
    RestyleAll = function()
        for btn in pairs(grabbed) do
            UnstyleButton(btn)
            btn._zTrayStyled, btn._zTraySkipped = nil, nil
        end
        Layout()
    end,
    Dump = Dump,
    Focus = Focus,
    Grab = Grab,
    SetSuppressed = SetSuppressed,
    IsSuppressed = function() return suppressed end,
    Layout = Layout,
    LayoutDefaults = LayoutDefaults,
    LayoutCells = LayoutCells,
    -- docked to the minimap (the Button tray tab and its preview)
    DB = DB,
    DockSide = DockSide,
    DockHost = DockHost,
    DockSizeDefault = DockSizeDefault,
    InsideInsets = InsideInsets,
    TAB_W = TAB_W, TAB_H = TAB_H,
    DockCells = DockCells,
    DockPoint = DockPoint,
    Metrics = Metrics,
    AnimDefault = AnimDefault,
    AnimSpec = AnimSpec,
    ApplyDock = ApplyDock,
    TICK_LONG = TICK_LONG, TICK_THICK = TICK_THICK,
    Release = Release,
    Scan = Scan,
    grabbed = grabbed,
    order = order,
    GetBar = function() return bar end,
    GetTray = function() return tray end,
    ReleaseAll = function()
        for i = #order, 1, -1 do Release(order[i]) end
    end,
}
