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
    ZacUIDB.tray = ZacUIDB.tray or {}
    local t = ZacUIDB.tray
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

local function Layout()
    if laying then return end
    if suppressed then
        -- Not just an early return: the owning addons re-show their
        -- buttons on their own schedule, and a layout pass that only
        -- skipped would let them drift back one at a time.
        HideAll()
        return
    end
    laying = true
    local db = DB()
    local size, cols = db.size, math.max(1, db.columns)
    local pad, gap = tonumber(db.pad) or 6, tonumber(db.gap) or 4

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
    local lw, lh = LayoutCells(tray.cells, n, tray, db)
    if lw then tray:SetSize(lw, lh) else tray:SetSize(math.max(size + pad * 2, w), h) end
    tray.empty:SetShown(n == 0)
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
-- Put the tray away, with the close animation if one is picked.
local function HideTray()
    if not tray or not tray:IsShown() then return end
    local spec = DB().closeAnim
    if type(spec) == "table" and spec.style and spec.style ~= "none" and ns.Motion and ns.Motion.Hide then
        ns.Motion.Hide(tray, spec)
    else
        tray:Hide()
    end
end

local function OpenTray()
    if closeTimer then closeTimer:Cancel() closeTimer = nil end
    Layout()
    -- The tray grows away from whichever screen half the bar sits in, so
    -- it never opens off the bottom of the screen.
    tray:ClearAllPoints()
    local mid = (UIParent:GetHeight() or 768) / 2
    if (bar:GetBottom() or 0) > mid then
        tray:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
    else
        tray:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 4)
    end
    -- reopened while its close animation runs: that animation stops here
    if ns.Motion and ns.Motion.Stop then ns.Motion.Stop(tray) end
    tray:Show()
    bar:SetAlpha(1)
end

local function CloseTray(delay)
    if closeTimer then closeTimer:Cancel() end
    local db = DB()
    closeTimer = C_Timer.NewTimer(delay or db.autoClose, function()
        closeTimer = nil
        if tray:IsMouseOver() or bar:IsMouseOver() then return end
        HideTray()
        bar:SetAlpha(db.barAlpha)
    end)
end

local function BuildUI()
    local db = DB()

    bar = CreateFrame("Button", "ZacUITrayBar", UIParent)
    bar:SetSize(db.barWidth, db.barHeight)
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

    bar._zPaint = function(self)
        local a = Col("accent")
        self._zFill:SetVertexColor(a.r, a.g, a.b, 1)
    end
    bar:_zPaint()

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
    bar:SetAlpha(db.barAlpha)

    bar:SetScript("OnDragStart", function(self)
        if DB().locked then return end
        self:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        local t = DB()
        t.point, t.x, t.y = point, x, y
    end)
    -- in ZacUI's mover mode too (Movers page, Edit Mode), its spot kept
    -- where its own drag keeps it
    if ns.RegisterMover then
        ns.RegisterMover("tray", "Minimap button tray", function() return bar end, "TOP", 0, -2, nil, {
            get = function()
                local t = DB()
                if t.point then return t.point, t.x or 0, t.y or 0 end
            end,
            set = function(point, x, y)
                local t = DB()
                t.point, t.x, t.y = point, x, y
            end,
            reset = function()
                bar:ClearAllPoints()
                bar:SetPoint("TOP", UIParent, "TOP", 0, -2)
            end,
            own = true,
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
    if bar then
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
        if bar then bar:Show() end
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
