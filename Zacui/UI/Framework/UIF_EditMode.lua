-- UIF_EditMode - one button that puts EVERY ZacUI placeholder on screen
-- at once over a dimmed, gridded world. A bar at the top of the screen
-- finds elements, turns the grid and snapping on and off, undoes a move
-- and leaves (keeping the changes or putting everything back); the box
-- you click wears its own actions (attach, match size, reset, settings,
-- hide); the Elements panel lists every element with its tick.
-- (2026-11-09 redesign, Zac: the bar and the actions on the box replace
-- the floating control box as the way in; that box is the Frames panel.)
-- (2026-11-10 tidy, Zac: "keep the top bar ... there was some text
-- overlap on that top bar ... clean it up make it more user friendly")
--   * the top bar lays itself out from what its texts measure: the
--     status line shortens, then goes, then the search box goes, before
--     anything can run into anything else; a button that is not there
--     (Raid mods) leaves no hole
--   * a line under the bar says how to use it (drag, arrows, right-click,
--     Escape); the "click another frame" prompt takes its place while
--     picking instead of sitting on top of the bar
--   * one word for the things you move: "frame" (was "element" in some
--     places and "frame" in others)
--   * the Frames panel lists what can be placed first and what cannot
--     (switched off, Blizzard's, not on this version) under a heading
--   * the picked box shows only what can be done with it, the common
--     things first (Reset, Settings, Hide)
-- Part of ZacUI; load order is set by the TOC (after UIF_EditSession).
--
-- WHAT IT MOVES. Everything with a ZacUI-owned position:
--   * the mover registry: loot rolls, buffs, minimap (each greyed, with
--     the reason, when Blizzard's Edit Mode or the client owns it) and
--     every class HUD anchor and the drink ticker
--   * the tooltip anchor (Blz_Tooltip's, shown silently)
--   * whatever the parts contribute through ns.EditModeProviders: the
--     action bars, the scrolling text areas and the unit frames (player,
--     target, party, raid - their own move mode, with the previews)
--   * the open meter windows, unlocked for the duration and put back to
--     whatever lock state they had (and told through ns.WatchEditMode)
--   Readycheck's frames are NOT part of this: it has an Edit Mode of its
--   own, and the two on screen at once was one pile of boxes too many.
--
-- A MOVABLE is a table: key, label, show(), hide(), and optionally
--   reset(silent)        back to its default spot
--   frames() / content() the boxes to outline / the real frames (faded
--                        while it is hidden here; what a link follows)
--   blocked()            Blizzard's Edit Mode or the client owns it
--   offscreen()          pushed off the screen (the list says so)
--   snapshot() / restore(v)   its spot of record, for undo and Cancel
--   size = { set(w, h) }      Match width / height can set its size
--   page                 the settings page that styles it
--   state()              -> tag, reason when it is off here (greyed)
--   follower             a ZacUI mover: it can be attached to another
--
-- LEAVING. Save & Exit keeps everything (it is written as it happens);
-- Cancel puts back every frame moved in this pass (UIF_EditSession);
-- the X and Escape are Save & Exit, so a stray key never throws work
-- away. Ctrl+Z undoes the last move. A pull ends the pass (keeping it):
-- frames that hold secure buttons cannot move in a fight, and Edit Mode
-- will not open in one.
--
-- SNAPPING. While a box is dragged its edges and centre snap to the
-- nearest other element's edges and centres and to the screen's middle
-- and edges (within a few units), live: the guide line that matched turns
-- green and the element it snapped to lights. Shift keeps one direction,
-- Alt places freely, the box's own toggle turns snapping off.
--
-- HIDING. Untick an element (or Hide all) and it is out of the way for
-- the pass: its box goes and, where the movable names them through
-- `content`, the real frames are faded to nothing. The ticks are
-- remembered (editMode.parked). The filter box hides, for the moment,
-- every element whose name does not hold what was typed.
--
-- THE OVERLAY is BACKGROUND strata: it dims the world and draws the grid
-- UNDER every UI frame, one physical pixel wide. Mouse stays off on it,
-- so the camera still turns.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local FLAT = ns.FLAT
local HideMover = ns.HideMover
local MOVERS = ns.MOVERS
local MoverBlocked = ns.MoverBlocked
local Print = ns.Print
local ResetMover = ns.ResetMover
local ShowMover = ns.ShowMover
local UI = ns.UI
local Kit = ns.MoverKit
local ES = ns.EditSession

local M, F = UI.M, UI.F
local ICONS = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\"

-- ============================================================
-- SETTINGS (written only once Edit Mode has been opened)
-- ============================================================
local function DB()
    ZacUIDB.editMode = ZacUIDB.editMode or {}
    local d = ZacUIDB.editMode
    if d.dim == nil then d.dim = 55 end       -- overlay darkness, percent
    if d.grid == nil then d.grid = true end
    if d.snap == nil then d.snap = true end
    d.parked = d.parked or {}                 -- [key] = true: hidden in edit mode
    return d
end

-- ============================================================
-- MOVABLES - gathered fresh on every entry: which meter windows are
-- open changes, and a mover the client took over since login should
-- drop out rather than error.
-- ============================================================
ns.EditModeProviders = ns.EditModeProviders or {}

-- a registry mover that is off here: why, in a few words and a sentence
local function RegistryState(m)
    local f = m.getFrame()
    if f and MoverBlocked(m.key, f) then
        return "Blizzard's Edit Mode",
            "On this game version Blizzard's own Edit Mode places this. Move it there: Esc > Edit Mode."
    end
    if m.off then
        local ok, why = pcall(m.off)
        if ok and why then return "off", tostring(why) end
    end
    if not f then
        return "off", "It is switched off, so there is nothing on screen to place. Turn it on in its settings, then it can be moved here."
    end
    return nil
end

local function MeterWin(w)
    local Meter = ns.Meter
    for _, win in ipairs(Meter and Meter.windowFrames or {}) do
        if win.settings == w then return win end
    end
    return nil
end

local function PlaceMeter(w)
    local win = MeterWin(w)
    local f = win and win.frame
    if not f then return end
    f:ClearAllPoints()
    f:SetPoint(w.point or "CENTER", UIParent, w.point or "CENTER", w.x or 0, w.y or 0)
    if w.w and w.h then f:SetSize(w.w, w.h) end
    local Meter = ns.Meter
    if Meter.LayoutRows then pcall(Meter.LayoutRows, win) end
    if Meter.RefreshWindow then pcall(Meter.RefreshWindow, win, true) end
end

local function Movables()
    local list = {}
    for _, m in ipairs(MOVERS) do
        local key = m.key
        list[#list + 1] = {
            key = key, label = m.label, follower = true,
            blocked = function() return MoverBlocked(key, m.getFrame()) end,
            show = function() ShowMover(key) end,
            hide = function() HideMover(key) end,
            reset = function(silent) ResetMover(key, silent) end,
            offscreen = function() return ns.MoverOffScreen and ns.MoverOffScreen(key) end,
            frames = function() local p = ns.MoverProxy and ns.MoverProxy(key) return p and { p } or nil end,
            content = function()
                local f = m.getFrame()
                if not f or MoverBlocked(key, f) then return nil end
                return { f }
            end,
            snapshot = function() return ns.MoverSnapshot(key) end,
            restore = function(v) ns.MoverRestore(key, v) end,
            size = m.size,
            page = m.page,
            state = function() return RegistryState(m) end,
        }
    end
    if ns.SetTipMover then
        list[#list + 1] = {
            key = "tooltip", label = "Tooltip anchor",
            show = function() ns.SetTipMover(true, true) end,
            hide = function() ns.SetTipMover(false) end,
            frames = function() local p = _G.ZacUITooltipMover return p and { p } or nil end,
            reset = function(silent)
                if ns.ResetTipPos then ns.ResetTipPos() else ZacUIDB.tooltipPos = nil end
                if not silent then Print("Tooltip position reset to Blizzard default.") end
            end,
            snapshot = function() return ES.Copy(ZacUIDB.tooltipPos) or false end,
            restore = function(v)
                ZacUIDB.tooltipPos = v or nil
                local p = _G.ZacUITooltipMover
                if p and p._zPlace then p._zPlace() end
            end,
        }
    end
    -- other systems (the action bars) contribute their own movables
    for _, provider in ipairs(ns.EditModeProviders or {}) do
        local ok, extra = pcall(provider)
        if ok and type(extra) == "table" then
            for _, e in ipairs(extra) do list[#list + 1] = e end
        end
    end
    local Meter = ns.Meter
    local md = Meter and Meter.DB and Meter.DB()
    for i, w in ipairs(md and md.windows or {}) do
        if w.open then
            list[#list + 1] = {
                key = "meter" .. i,
                label = "Meter window " .. i
                    .. (w.display == "threat" and " (threat)" or ""),
                -- unlock for the pass, restore the exact flag after -
                -- both ship locked, and an unlocked window eats drags
                -- meant for the world
                show = function()
                    if w._zEditWasLocked == nil then w._zEditWasLocked = w.locked end
                    w.locked = false
                end,
                hide = function()
                    if w._zEditWasLocked ~= nil then
                        w.locked = w._zEditWasLocked
                        w._zEditWasLocked = nil
                    end
                end,
                frames = function() local p = _G["ZacUIMeterWindow" .. i] return p and { p } or nil end,
                content = function() local p = _G["ZacUIMeterWindow" .. i] return p and { p } or nil end,
                snapshot = function() return { point = w.point, x = w.x, y = w.y, w = w.w, h = w.h } end,
                restore = function(v)
                    if type(v) ~= "table" then return end
                    w.point, w.x, w.y, w.w, w.h = v.point, v.x, v.y, v.w, v.h
                    PlaceMeter(w)
                end,
                size = { set = function(nw, nh)
                    local win = MeterWin(w)
                    local f = win and win.frame
                    local k = 1
                    if f and f.GetEffectiveScale then
                        k = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
                        if k <= 0 then k = 1 end
                    end
                    if nw then w.w = math.max(100, nw / k) end
                    if nh then w.h = math.max(50, nh / k) end
                    PlaceMeter(w)
                end },
                page = "meter",
            }
        end
    end
    -- a movable whose page this game version does not run says so
    for _, m in ipairs(list) do
        if not m.state then
            local page = ES.PageFor(m)
            local offId = page and ns.FeatureOffForPage and ns.FeatureOffForPage(page)
            if offId then
                local note = ns.FeatureOffNote and ns.FeatureOffNote(offId) or "Not on this game version."
                m.state = function() return "not on this version", note end
            end
        end
    end
    table.sort(list, function(a, b) return tostring(a.label):lower() < tostring(b.label):lower() end)
    return list
end

local function StateOf(m)
    if m.blocked and m.blocked() then
        local tag, why = m.state and m.state()
        return tag or "Blizzard's Edit Mode", why
            or "On this game version Blizzard's own Edit Mode places this. Move it there: Esc > Edit Mode."
    end
    if m.state then
        local ok, tag, why = pcall(m.state)
        if ok and tag then return tag, why end
    end
    return nil
end

-- ============================================================
-- OVERLAY
-- ============================================================
local overlay
local GRID = 50

-- UI units in one physical pixel, so the lines are one pixel on any scale
local function Px()
    if not GetPhysicalScreenSize then return 1 end
    local _, ph = GetPhysicalScreenSize()
    local uh = UIParent:GetHeight()
    if ph and ph > 0 and uh and uh > 0 then return uh / ph end
    return 1
end

local function BuildGrid()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local px = Px()
    if overlay._gridW == w and overlay._gridH == h and overlay._gridPx == px then return end
    overlay._gridW, overlay._gridH, overlay._gridPx = w, h, px
    overlay.lines = overlay.lines or {}
    local n = 0
    local function line()
        n = n + 1
        local t = overlay.lines[n]
        if not t then
            t = overlay:CreateTexture(nil, "ARTWORK")
            t._zui_own = true
            t:SetTexture(FLAT)
            overlay.lines[n] = t
        end
        t:ClearAllPoints()
        return t
    end
    -- from the middle out, so the centre lines sit exactly on the centre
    local cx, cy = w / 2, h / 2
    local cols = math.ceil(cx / GRID)
    local rows = math.ceil(cy / GRID)
    overlay._centreV, overlay._centreH = nil, nil
    for i = -cols, cols do
        local x = cx + i * GRID
        if x >= 0 and x <= w then
            local t = line()
            t:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", x - px / 2, 0)
            t:SetSize(px, h)
            t._zCentre = (i == 0)
        end
    end
    for i = -rows, rows do
        local y = cy + i * GRID
        if y >= 0 and y <= h then
            local t = line()
            t:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, y - px / 2)
            t:SetSize(w, px)
            t._zCentre = (i == 0)
        end
    end
    overlay._nLines = n
    for i = n + 1, #overlay.lines do overlay.lines[i]:Hide() end
end

local function PaintOverlay()
    if not overlay then return end
    local d = DB()
    overlay.bg:SetVertexColor(0, 0, 0, (d.dim or 55) / 100)
    -- the centre lines a touch brighter, so the middle of the screen is
    -- findable at a glance
    for i = 1, overlay._nLines or 0 do
        local t = overlay.lines[i]
        t:SetVertexColor(1, 1, 1, t._zCentre and 0.18 or 0.07)
        t:SetShown(d.grid and true or false)
    end
end

local function ShowOverlay()
    if not overlay then
        overlay = CreateFrame("Frame", "ZacUIEditOverlay", UIParent)
        overlay:SetAllPoints(UIParent)
        overlay:SetFrameStrata("BACKGROUND")
        overlay:EnableMouse(false)
        local bg = overlay:CreateTexture(nil, "BACKGROUND")
        bg._zui_own = true
        bg:SetAllPoints()
        bg:SetTexture(FLAT)
        overlay.bg = bg
    end
    BuildGrid()
    PaintOverlay()
    overlay:Show()
end

-- ============================================================
-- STATE
-- ============================================================
local active = false
local current = {}          -- the movables of this pass
local byKey = {}            -- [key] = movable
local reopenConfig = false
local openPage              -- a page to open on the way out (its settings)
local bar
local top                   -- the bar across the top of the screen
local acts                  -- the picked box's actions
local filterText = ""
local filtered = {}         -- [key] = true: hidden by the filter just now
local focusKeys, focusUntil = {}, nil  -- what a page sent us to, and its flash

local function IsParked(key) return DB().parked[key] == true end
local function IsGrey(m) return StateOf(m) ~= nil end

-- (2026-11-10, Zac: "the move ui is still kinda confusing to use
-- especially with the raid mods") The raid mods add some twenty boxes of
-- their own, most of them in the middle of the screen where the HUD is
-- placed. They are out of the way until the top bar's "Raid mods" button
-- brings them in (remembered); a settings page that sends one of them
-- here brings them in too.
local function IsRaidMod(m)
    local k = m and m.key
    return type(k) == "string" and (k:find("^raidmods_") ~= nil or k == "rmRazTarget")
end
local function Matches(m)
    if IsRaidMod(m) and not DB().showRaidMods then return false end
    if filterText == "" then return true end
    local label = tostring(m.label or ""):lower()
    for word in filterText:gmatch("%S+") do
        if not label:find(word, 1, true) then return false end
    end
    return true
end

local function ShowMovable(m)
    if IsGrey(m) or filtered[m.key] then return end
    m.show()
end

-- FADING. A hidden element's real frames go to alpha 0 for the pass (not
-- Hide: their owners show and hide them, some are secure). Owners that
-- fade their own frames would bring them back, so the guide tick, which
-- runs every frame while Edit Mode is open, puts the fade back.
local faded = {}             -- [frame] = the alpha it had before

local function ContentOf(m)
    if not m.content then return {} end
    local ok, list = pcall(m.content)
    if not (ok and type(list) == "table") then return {} end
    local out = {}
    for _, item in ipairs(list) do
        if type(item) == "table" and rawget(item, "union") then
            for _, f in ipairs(item.union) do out[#out + 1] = f end
        elseif item then
            out[#out + 1] = item
        end
    end
    return out
end

local function FadeContent(m)
    for _, f in ipairs(ContentOf(m)) do
        if f.SetAlpha and f.GetAlpha then
            if faded[f] == nil then faded[f] = f:GetAlpha() or 1 end
            f:SetAlpha(0)
        end
    end
end

local function UnfadeFrame(f)
    local a = faded[f]
    if a == nil then return end
    faded[f] = nil
    f:SetAlpha(a)
end

local function UnfadeContent(m)
    for _, f in ipairs(ContentOf(m)) do UnfadeFrame(f) end
end

local function UnfadeAll()
    local list = {}
    for f in pairs(faded) do list[#list + 1] = f end
    for _, f in ipairs(list) do UnfadeFrame(f) end
end

local function KeepFaded()
    for f in pairs(faded) do
        if f:GetAlpha() ~= 0 then f:SetAlpha(0) end
    end
end

-- One element out of the way, or back. Remembered for the next pass.
local function SetParked(m, park)
    local d = DB()
    if park then
        d.parked[m.key] = true
        m.hide()
        FadeContent(m)
    else
        d.parked[m.key] = nil
        UnfadeContent(m)
        ShowMovable(m)
    end
end

local BuildTop   -- forward: the bar across the top (built on first entry)
local LayoutTop  -- forward: what fits on it, measured (status, search box)
local Select     -- forward: pick a box, with its actions
local Exit       -- forward: the bar's OnHide calls it
local FillBar    -- forward: Show all / Hide all refill the list
local RefreshBar -- forward: the count, the undo button, the moved dots

-- ============================================================
-- OUTLINES, GUIDES AND SNAPPING
-- ============================================================
--   OUTLINES  a one-pixel box round everything that can be moved, with a
--             tick at the middle of each side. A party or raid block gets
--             ONE box round the whole block. The box being dragged or
--             pointed at is white; the one a drag snapped to, green.
--   GUIDES    point at an element (or drag it) and six lines run the width
--             and height of the screen from its left edge, centre and
--             right edge, and its top, centre and bottom. A line turns
--             green the moment it lies on the same edge or centre of any
--             other element, or on the centre of the screen.
-- Nothing is anchored to anybody's frame - the boxes are placed from each
-- frame's rect, read every frame while Edit Mode is open (it cannot be
-- open in combat).
local guides, lines, readout, chip
local outlines, targets = {}, {}
local activeId
local GOOD = { 0.3, 1, 0.4 }
local SNAP = 8               -- UI units: how close counts as "on"
local snapState = {}         -- [handle] = the target it snapped to (or nil)
local picking                -- { kind = "attach" | "w" | "h", m = movable }
local underTarget            -- the target under the cursor this frame

-- left, right, top, bottom of a frame in UIParent units; nil when it is
-- not on screen
local function RectOf(f)
    if not (f and f.IsVisible and f:IsVisible() and f.GetRect) then return nil end
    local l, b, w, h = f:GetRect()
    if not (l and b and w and h) or w <= 0 or h <= 0 then return nil end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, (l + w) * s, (b + h) * s, b * s
end

local function RectOfTarget(t)
    if not t.union then return RectOf(t.frame) end
    local l, r, top, b
    for _, f in ipairs(t.union) do
        local fl, fr, ft, fb = RectOf(f)
        if fl then
            if not l or fl < l then l = fl end
            if not r or fr > r then r = fr end
            if not top or ft > top then top = ft end
            if not b or fb < b then b = fb end
        end
    end
    return l, r, top, b
end

local function CollectTargets()
    wipe(targets)
    for _, m in ipairs(current) do
        if m.frames and not IsParked(m.key) and not filtered[m.key] and not IsGrey(m) then
            local ok, list = pcall(m.frames)
            if ok and type(list) == "table" then
                for _, item in ipairs(list) do
                    if type(item) == "table" and rawget(item, "union") then
                        -- a union is known by its first frame, so it is
                        -- the same target from one collection to the next
                        targets[#targets + 1] = { union = item.union, id = item.union[1], key = m.key }
                    elseif item then
                        targets[#targets + 1] = { frame = item, id = item, key = m.key }
                    end
                end
            end
        end
    end
end

-- the movable a drag handle belongs to
local function MovableOf(h)
    for _, t in ipairs(targets) do
        if t.frame == h then return byKey[t.key] end
    end
    for _, m in ipairs(current) do
        local ok, list = pcall(m.frames or function() end)
        if ok and type(list) == "table" then
            for _, f in ipairs(list) do if f == h then return m end end
        end
    end
    return nil
end

-- Kit.edit.snap: the dragged box's left / bottom (UIParent units), moved
-- onto the nearest edge or centre within SNAP on each axis
local function Snap(h, l, b, w, ht)
    snapState[h] = nil
    rawset(h, "_zSnapped", nil)
    if not DB().snap or (IsAltKeyDown and IsAltKeyDown()) then return l, b end
    local own = MovableOf(h)
    local skip = {}
    if own then
        skip[own.key] = true
        for _, k in ipairs(ES.FollowersOf(own.key)) do skip[k] = true end
    end
    local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    local mx = { l, l + w / 2, l + w }
    local my = { b, b + ht / 2, b + ht }
    local bestX, bestY = SNAP + 0.001, SNAP + 0.001
    local dxBest, dyBest, tx, ty = 0, 0, nil, nil
    local function TryX(v, t)
        for i = 1, 3 do
            local d = v - mx[i]
            if math.abs(d) < bestX then bestX, dxBest, tx = math.abs(d), d, t end
        end
    end
    local function TryY(v, t)
        for i = 1, 3 do
            local d = v - my[i]
            if math.abs(d) < bestY then bestY, dyBest, ty = math.abs(d), d, t end
        end
    end
    -- the screen: edges and middle
    TryX(0, false) TryX(sw / 2, false) TryX(sw, false)
    TryY(0, false) TryY(sh / 2, false) TryY(sh, false)
    for _, t in ipairs(targets) do
        if t.frame ~= h and not skip[t.key] then
            local tl, tr, tt, tb = RectOfTarget(t)
            if tl then
                TryX(tl, t) TryX((tl + tr) / 2, t) TryX(tr, t)
                TryY(tb, t) TryY((tt + tb) / 2, t) TryY(tt, t)
            end
        end
    end
    if bestX <= SNAP then l = l + dxBest end
    if bestY <= SNAP then b = b + dyBest end
    local hit = (bestX <= SNAP and tx) or (bestY <= SNAP and ty) or nil
    if bestX <= SNAP or bestY <= SNAP then
        rawset(h, "_zSnapped", true)
        snapState[h] = hit or "screen"
    end
    return l, b
end

local function Outline(i)
    local o = outlines[i]
    if o then return o end
    o = CreateFrame("Frame", nil, guides)
    o.edges, o.ticks = {}, {}
    for n = 1, 4 do
        local e = o:CreateTexture(nil, "OVERLAY")
        e._zui_own = true
        e:SetTexture(FLAT)
        o.edges[n] = e
        local t = o:CreateTexture(nil, "OVERLAY")
        t._zui_own = true
        t:SetTexture(FLAT)
        o.ticks[n] = t
    end
    function o:Dress(px, r, g, b, a, thick)
        local w = px * (thick or 1)
        local top, bottom, left, right = self.edges[1], self.edges[2], self.edges[3], self.edges[4]
        top:ClearAllPoints() top:SetPoint("TOPLEFT") top:SetPoint("TOPRIGHT") top:SetHeight(w)
        bottom:ClearAllPoints() bottom:SetPoint("BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT") bottom:SetHeight(w)
        left:ClearAllPoints() left:SetPoint("TOPLEFT") left:SetPoint("BOTTOMLEFT") left:SetWidth(w)
        right:ClearAllPoints() right:SetPoint("TOPRIGHT") right:SetPoint("BOTTOMRIGHT") right:SetWidth(w)
        -- the middle of each side, as a short stroke across the edge
        local len = px * 7
        local tt, tb, tl, tr = self.ticks[1], self.ticks[2], self.ticks[3], self.ticks[4]
        tt:ClearAllPoints() tt:SetPoint("CENTER", self, "TOP", 0, 0) tt:SetSize(px, len)
        tb:ClearAllPoints() tb:SetPoint("CENTER", self, "BOTTOM", 0, 0) tb:SetSize(px, len)
        tl:ClearAllPoints() tl:SetPoint("CENTER", self, "LEFT", 0, 0) tl:SetSize(len, px)
        tr:ClearAllPoints() tr:SetPoint("CENTER", self, "RIGHT", 0, 0) tr:SetSize(len, px)
        for n = 1, 4 do
            self.edges[n]:SetVertexColor(r, g, b, a)
            self.ticks[n]:SetVertexColor(r, g, b, a)
        end
    end
    outlines[i] = o
    return o
end

local function LeftDown() return IsMouseButtonDown ~= nil and IsMouseButtonDown("LeftButton") and true or false end

local function Near(a, b, tol) return a and b and math.abs(a - b) <= tol end

-- the handle a drag is happening on (the kit's own drag), if any
local function Dragged()
    for h in pairs(snapState) do
        if rawget(h, "_zDragging") then return h end
    end
    return nil
end

local checkAcc = 0
local function GuideTick(_, dt)
    if next(faded) then KeepFaded() end
    guides._acc = (guides._acc or 1) + dt
    if guides._acc >= 0.5 then
        guides._acc = 0
        CollectTargets()
    end
    -- frames attached to a moving frame follow it, live
    ES.FollowAll()
    -- frames that drag themselves (unit frames, meter windows) and the
    -- list's own buttons are noticed here, between moves
    checkAcc = checkAcc + dt
    if checkAcc >= 0.25 and not LeftDown() then
        checkAcc = 0
        ES.Check()
    end
    local px = Px()
    -- "on" means on the same pixel: half a pixel either way, so green is
    -- exact and one pixel out is not
    local tol = px * 0.55
    local us = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    mx, my = mx / us, my / us
    local a = Col("accent")
    local now = GetTime and GetTime() or 0

    -- place every box; find what the cursor is on (the smallest, so an
    -- element inside a bigger one can still be picked)
    local under, underArea, held
    local selected = Kit.selected
    local selT
    for i, t in ipairs(targets) do
        local l, r, top, b = RectOfTarget(t)
        t.l, t.r, t.t, t.b = l, r, top, b
        local o = Outline(i)
        if l then
            o:ClearAllPoints()
            o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
            o:SetSize(r - l, top - b)
            o:Show()
            if t.id == activeId then held = t end
            if selected and t.frame == selected then selT = t end
            if mx >= l and mx <= r and my >= b and my <= top then
                local area = (r - l) * (top - b)
                if not underArea or area < underArea then under, underArea = t, area end
            end
        else
            o:Hide()
        end
    end
    for i = #targets + 1, #outlines do outlines[i]:Hide() end
    underTarget = under

    -- while the button is down the element being dragged keeps the guides,
    -- even if the cursor crosses something else on the way
    local active = (held and LeftDown()) and held or under
    if picking then active = nil end
    activeId = active and active.id or nil

    local dragging = Dragged()
    local snappedTo = dragging and snapState[dragging]
    local pulse = (focusUntil and now < focusUntil) and (0.5 + 0.5 * math.abs(math.sin(now * 6))) or nil
    for i, t in ipairs(targets) do
        if t.l then
            local o = outlines[i]
            if picking and t == under and t.key ~= picking.m.key then
                o:Dress(px, GOOD[1], GOOD[2], GOOD[3], 1, 2)
            elseif type(snappedTo) == "table" and t == snappedTo then
                o:Dress(px, GOOD[1], GOOD[2], GOOD[3], 1, 2)
            elseif pulse and focusKeys[t.key] then
                o:Dress(px, 1, 1, 1, pulse, 2)
            elseif t == active or t == selT then
                o:Dress(px, 1, 1, 1, 1)
            else
                o:Dress(px, a.r, a.g, a.b, 0.9)
            end
        end
    end

    -- the snap chip: what the dragged box landed on
    if dragging and snappedTo then
        local name = (snappedTo == "screen") and "the screen" or (byKey[snappedTo.key] and byKey[snappedTo.key].label) or ""
        chip.text:SetText("Snapped to " .. name)
        chip:SetWidth(chip.text:GetStringWidth() + 12)
        chip:ClearAllPoints()
        chip:SetPoint("LEFT", dragging, "RIGHT", 8, 0)
        chip:Show()
    else
        chip:Hide()
    end

    if not active then
        for n = 1, 6 do lines[n]:Hide() end
        readout:Hide()
        return
    end

    local l, r, top, b = active.l, active.r, active.t, active.b
    local cx, cy = (l + r) / 2, (top + b) / 2
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local vx = { l, cx, r }          -- the three vertical lines
    local hy = { top, cy, b }        -- the three horizontal lines
    local vOn, hOn = {}, {}
    for n = 1, 3 do
        if Near(vx[n], sw / 2, tol) then vOn[n] = true end
        if Near(hy[n], sh / 2, tol) then hOn[n] = true end
    end
    for _, t in ipairs(targets) do
        if t ~= active and t.l then
            local ox = { t.l, (t.l + t.r) / 2, t.r }
            local oy = { t.t, (t.t + t.b) / 2, t.b }
            for n = 1, 3 do
                for k = 1, 3 do
                    if Near(vx[n], ox[k], tol) then vOn[n] = true end
                    if Near(hy[n], oy[k], tol) then hOn[n] = true end
                end
            end
        end
    end
    for n = 1, 3 do
        local v, h = lines[n], lines[n + 3]
        v:ClearAllPoints()
        v:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", vx[n] - px / 2, 0)
        v:SetSize(px, sh)
        if vOn[n] then v:SetVertexColor(GOOD[1], GOOD[2], GOOD[3], 1)
        else v:SetVertexColor(a.r, a.g, a.b, 0.45) end
        v:Show()
        h:ClearAllPoints()
        h:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, hy[n] - px / 2)
        h:SetSize(sw, px)
        if hOn[n] then h:SetVertexColor(GOOD[1], GOOD[2], GOOD[3], 1)
        else h:SetVertexColor(a.r, a.g, a.b, 0.45) end
        h:Show()
    end

    -- a ZacUI handle shows its own readout (its spot in its own numbers,
    -- the same ones its settings show); this one is for everything else
    if active.frame and Kit.IsDressed(active.frame) then
        readout:Hide()
        return
    end
    -- offset of the element's centre from the centre of the screen, and
    -- its size, just above its top-left corner (below it at the screen top)
    readout:SetText(("%+d, %+d    %d x %d"):format(
        math.floor(cx - sw / 2 + 0.5), math.floor(cy - sh / 2 + 0.5),
        math.floor(r - l + 0.5), math.floor(top - b + 0.5)))
    readout:ClearAllPoints()
    if top + 16 < sh then
        readout:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, top + 3)
    else
        readout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, b - 3)
    end
    readout:Show()
end

local function ShowGuides()
    if not guides then
        guides = CreateFrame("Frame", "ZacUIEditGuides", UIParent)
        guides:SetAllPoints(UIParent)
        -- above every element being placed, below the control box
        guides:SetFrameStrata("FULLSCREEN_DIALOG")
        guides:EnableMouse(false)
        lines = {}
        for n = 1, 6 do
            local t = guides:CreateTexture(nil, "BACKGROUND")
            t._zui_own = true
            t:SetTexture(FLAT)
            t:Hide()
            lines[n] = t
        end
        readout = UI.Font(guides, F.SMALL, { text = "", cat = "text", key = "normal" })
        readout:Hide()
        chip = CreateFrame("Frame", nil, guides)
        chip:SetHeight(16)
        UI.Fill(chip, "tooltip", "bg")
        chip.text = UI.Font(chip, F.SMALL, { text = "", cat = "text", key = "green" })
        chip.text:SetPoint("LEFT", 6, 0)
        chip:Hide()
        guides:SetScript("OnUpdate", GuideTick)
    end
    guides._acc = 1          -- collect on the first tick
    activeId = nil
    guides:Show()
end

local function HideGuides()
    if guides then guides:Hide() end
    wipe(targets)
    wipe(snapState)
    activeId = nil
    underTarget = nil
end

-- ============================================================
-- PICKING ANOTHER FRAME (Attach to... / Match width... / Match height...)
-- A click anywhere is caught; the element under the cursor (lit green)
-- is the one picked. Right-click or Escape gives up.
-- ============================================================
local catcher, banner

local function StopPick()
    picking = nil
    if catcher then catcher:Hide() end
    if banner then banner:Hide() end
    if top and top.hint then top.hint:SetShown(active) end
end

local PICK_TEXT = {
    attach = "Click the frame %s should follow.",
    w = "Click the frame whose width %s should take.",
    h = "Click the frame whose height %s should take.",
}

local function FinishPick()
    local p = picking
    local t = underTarget
    StopPick()
    if not (p and t) then return end
    local other = byKey[t.key]
    if not other or other.key == p.m.key then return end
    local ok, why
    if p.kind == "attach" then
        ok, why = ES.Attach(p.m.key, other)
        if ok then Print(p.m.label .. " now follows " .. other.label .. ".") end
    else
        ok, why = ES.Match(p.m, other, p.kind)
        if ok then ES.Check() end
    end
    if not ok and why then Print(p.m.label .. ": " .. why .. ".") end
    ES.Check()
    if RefreshBar then RefreshBar() end
end

local function StartPick(kind, m)
    if not catcher then
        catcher = CreateFrame("Frame", "ZacUIEditPick", UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(50)
        catcher:EnableMouse(true)
        catcher:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then StopPick() else FinishPick() end
        end)
        banner = CreateFrame("Frame", nil, UIParent)
        banner:SetFrameStrata("TOOLTIP")
        banner:SetHeight(28)
        UI.Fill(banner, "tooltip", "bg")
        UI.Border(banner, "ui", "accent")
        -- (a fill is white until its box is painted)
        banner._zPaint = UI.PaintBox
        banner:_zPaint()
        banner.text = UI.Font(banner, F.LABEL, { text = "", cat = "text", key = "normal" })
        banner.text:SetPoint("CENTER", 0, 0)
        -- under the top bar, where the how-to line is (it steps aside
        -- while a frame is being picked), never on the bar's own text
        banner:SetPoint("TOP", UIParent, "TOP", 0, -50)
    end
    picking = { kind = kind, m = m }
    banner.text:SetText(PICK_TEXT[kind]:format(m.label) .. "  |cff999999Right-click or Escape: never mind.|r")
    banner:SetWidth((banner.text:GetStringWidth() or 300) + 28)
    if top and top.hint then top.hint:Hide() end
    catcher:Show()
    banner:Show()
end

-- ============================================================
-- SETTINGS LINK and THE MOVER'S MENU
-- ============================================================
local function OpenSettings(m)
    local page = ES.PageFor(m)
    if not page then return end
    openPage = page
    Exit("save")
end

local function Menu(m, anchor)
    if not (m and UI.ContextMenu) then return false end
    local page = ES.PageFor(m)
    local link = ES.LinkOf(m.key)
    local items = { { text = m.label, isTitle = true } }
    items[#items + 1] = { text = "Open its settings", disabled = page == nil,
        tooltip = page == nil and "It has no settings page of its own." or nil,
        func = function() OpenSettings(m) end }
    if link then
        local to = byKey[link.to]
        items[#items + 1] = { text = "Detach from " .. (to and to.label or link.to),
            func = function() ES.Detach(m.key) ES.Check() RefreshBar() end }
    elseif m.follower then
        items[#items + 1] = { text = "Attach to...",
            tooltip = "Click another frame: this one then follows it wherever it goes.",
            func = function() StartPick("attach", m) end }
    else
        items[#items + 1] = { text = "Attach to...", disabled = true,
            tooltip = "This one keeps its spot in its own settings, so it cannot follow another frame." }
    end
    local canSize = m.size and m.size.set
    local sizeWhy = (not canSize) and "Its size comes from its own settings." or nil
    items[#items + 1] = { text = "Match width...", disabled = not canSize, tooltip = sizeWhy,
        func = function() StartPick("w", m) end }
    items[#items + 1] = { text = "Match height...", disabled = not canSize, tooltip = sizeWhy,
        func = function() StartPick("h", m) end }
    local followers = ES.FollowersOf(m.key)
    if #followers > 0 then
        local names = {}
        for _, k in ipairs(followers) do names[#names + 1] = byKey[k] and byKey[k].label or k end
        items[#items + 1] = { text = (#followers == 1 and "1 frame follows it" or (#followers .. " frames follow it")),
            disabled = true, tooltip = table.concat(names, ", ") }
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = "Reset to its default spot", disabled = m.reset == nil,
        func = function() if m.reset then m.reset(true) ES.Check() end end }
    items[#items + 1] = { text = "Hide while editing",
        func = function() SetParked(m, true) FillBar() end }
    UI.ContextMenu(items, anchor and { anchor = anchor } or nil)
    return true
end

-- ============================================================
-- CONTROL BOX
-- ============================================================
local W = 320
local ROW = 24

local function IconButton(parent, icon, tip, body, onClick)
    local b = UI.Button(parent, "", { width = 18, height = 18, size = F.SMALL, onClick = onClick })
    local t = b:CreateTexture(nil, "OVERLAY")
    t._zui_own = true
    t:SetSize(14, 14)
    t:SetPoint("CENTER", 0, 0)
    t:SetTexture(ICONS .. icon)
    local function Tint(on)
        local c = on and Col("accent") or ns.GetColor("text", "normal")
        t:SetVertexColor(c.r, c.g, c.b, 1)
    end
    Tint(false)
    b:HookScript("OnEnter", function() Tint(true) end)
    b:HookScript("OnLeave", function() Tint(false) end)
    UI.Tooltip(b, tip, body)
    return b
end

local function ShowTip(owner, title, body)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local t, c = ns.GetColor("tooltip", "title"), ns.GetColor("tooltip", "body")
    GameTooltip:AddLine(title, t.r, t.g, t.b)
    if body then GameTooltip:AddLine(body, c.r, c.g, c.b, true) end
    GameTooltip:Show()
end

local function ApplyFilter()
    for _, m in ipairs(current) do
        local want = Matches(m)
        if not want and not filtered[m.key] then
            filtered[m.key] = true
            if not IsParked(m.key) then m.hide() end
        elseif want and filtered[m.key] then
            filtered[m.key] = nil
            if not IsParked(m.key) then ShowMovable(m) end
        end
    end
    if guides then guides._acc = 1 end
end

-- THE SEARCH (2026-11-10). Both boxes (the top bar's and the panel's)
-- come here. The top bar's used to pass its text to the panel's box and
-- rely on that box's own change handler, which a text set by code does
-- not fire; and every key refilled the whole list, making a new tick box
-- for every row. Now: one function, applied a beat after the last key.
local filterSerial = 0
local function SetFilter(text, now)
    local t = (tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""))
    filterSerial = filterSerial + 1
    local mine = filterSerial
    local function Apply()
        if mine ~= filterSerial or not active then return end
        if t == filterText then return end
        filterText = t
        ApplyFilter()
        FillBar()
    end
    if now or not (C_Timer and C_Timer.After) then Apply() else C_Timer.After(0.12, Apply) end
end

local function BuildBar()
    -- (2026-11-08) the popup shell (UIF_Dialogs UI.Popup), its margin the
    -- bar's own so the title lines up with the list
    bar = UI.Popup("ZacUIEditModeBar", W, 200, "Frames", { pad = M.CARD_PAD })
    bar:SetFrameStrata("TOOLTIP")
    bar:SetClampedToScreen(true)
    bar._zOnMoved = function()
        local point, _, _, x, y = bar:GetPoint(1)
        local d = DB()
        d.barPoint, d.barX, d.barY = point, x, y
    end
    local pad = M.CARD_PAD
    local iw = W - 2 * pad

    -- how many frames this pass has moved, beside the close
    bar.count = UI.Font(bar.titleBar or bar, F.SMALL, { text = "", cat = "text", key = "gray" })
    if bar.closeButton then
        bar.count:SetPoint("RIGHT", bar.closeButton, "LEFT", -6, 0)
    else
        bar.count:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -34, -10)
    end

    local desc = UI.Font(bar, F.DESC, {
        text = "Drag to place. Shift keeps one direction, Alt places freely. "
            .. "Right-click a frame for more.",
        cat = "text", key = "gray", width = iw })
    desc:SetPoint("TOPLEFT", bar, "TOPLEFT", pad, -bar.headerHeight)
    bar.desc = desc

    -- the filter: hides every element whose name lacks what is typed
    bar.filter = UI.EditBox(bar, { width = iw, hint = "Find a frame...", onChange = function(text)
        SetFilter(text, true)
    end })
    bar.filter:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)

    local d = DB()
    bar.snap = UI.Checkbox(bar, "Snap to frames", d.snap, function(v)
        DB().snap = v and true or false
    end)
    bar.snap:SetPoint("TOPLEFT", bar.filter, "BOTTOMLEFT", 0, -8)
    UI.Tooltip(bar.snap, "Snap to frames",
        "A dragged frame's edges and centre snap to the nearest other frame's, and to the middle and edges "
            .. "of the screen. Hold Alt while dragging to place one freely.")
    bar.grid = UI.Checkbox(bar, "Grid", d.grid, function(v)
        DB().grid = v and true or false
        PaintOverlay()
    end)
    bar.grid:SetPoint("TOPLEFT", bar.filter, "BOTTOMLEFT", 150, -8)

    bar.dim = UI.Slider(bar, { width = iw, min = 0, max = 90,
        step = 5, value = d.dim, label = "Dim the world",
        format = function(v) return v .. "%" end,
        onChange = function(v)
            DB().dim = v
            PaintOverlay()
        end })
    bar.dim:SetPoint("TOPLEFT", bar.snap, "BOTTOMLEFT", 0, -8)

    -- The element list scrolls. A class HUD alone is seven rows and the
    -- bars, meter windows and tooltip add more; the box has a ceiling and
    -- the list scrolls inside it.
    bar.rows = {}
    bar.scroll, bar.list, bar.scrollBar = UI.ScrollArea(bar)
    bar.scroll:SetPoint("TOPLEFT", bar.dim, "BOTTOMLEFT", 0, -6)
    bar.scrollBar:SetPoint("TOPLEFT", bar.scroll, "TOPRIGHT", 4, 0)
    bar.scrollBar:SetPoint("BOTTOMLEFT", bar.scroll, "BOTTOMRIGHT", 4, 0)

    local half = math.floor((iw - 6) / 2)
    local third = math.floor((iw - 12) / 3)
    bar.cancel = UI.Button(bar, "Cancel", { width = half,
        tooltip = "Put back every frame moved since Edit Mode opened, and leave.",
        onClick = function() Exit("cancel") end })
    bar.save = UI.Button(bar, "Save & Exit", { width = iw - half - 6,
        tooltip = "Keep everything where it is now, and leave. (The X and Escape do the same.)",
        onClick = function() Exit("save") end })
    bar.save:SetActive(true)
    bar.cancel:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", pad, pad)
    bar.save:SetPoint("LEFT", bar.cancel, "RIGHT", 6, 0)

    bar.undo = UI.Button(bar, "Undo  Ctrl+Z", { width = third, height = M.BUTTON_H, size = F.SMALL,
        tooltip = "Put back the last move.",
        onClick = function() ES.Undo() RefreshBar() end })
    bar.showHide = UI.Button(bar, "Hide all", { width = third, height = M.BUTTON_H, size = F.SMALL,
        onClick = function()
            local anyShown = false
            for _, m in ipairs(current) do
                if not IsParked(m.key) and not IsGrey(m) then anyShown = true break end
            end
            for _, m in ipairs(current) do
                if not IsGrey(m) then
                    if anyShown and not IsParked(m.key) then SetParked(m, true)
                    elseif not anyShown and IsParked(m.key) then SetParked(m, false) end
                end
            end
            FillBar()
        end })
    UI.Tooltip(bar.showHide, "Hide all / Show all",
        "Every frame out of the way while you place the rest, or all of them back.")
    bar.resetAll = UI.Button(bar, "Reset all", { width = iw - 2 * third - 12, height = M.BUTTON_H, size = F.SMALL,
        tooltip = "Every frame back to its default spot. Cancel or Ctrl+Z puts them back.",
        onClick = function()
            for _, m in ipairs(current) do
                if m.reset and not IsGrey(m) then m.reset(true) end
            end
            ES.Check()
            Print("every frame back to its default spot (Ctrl+Z or Cancel puts them back).")
        end })
    bar.undo:SetPoint("BOTTOMLEFT", bar.cancel, "TOPLEFT", 0, 6)
    bar.showHide:SetPoint("LEFT", bar.undo, "RIGHT", 6, 0)
    bar.resetAll:SetPoint("LEFT", bar.showHide, "RIGHT", 6, 0)

    bar.rule = bar:CreateTexture(nil, "ARTWORK")
    bar.rule._zui_own = true
    bar.rule:SetTexture(FLAT)
    bar.rule:SetHeight(1)
    bar.rule:SetPoint("BOTTOMLEFT", bar.undo, "TOPLEFT", -pad + 1, 8)
    bar.rule:SetPoint("RIGHT", bar, "RIGHT", -1, 0)
    local bc = ns.GetColor("ui", "border")
    bar.rule:SetVertexColor(bc.r, bc.g, bc.b, 1)

    -- (2026-11-09) the panel is the element list now: closing it only
    -- closes it. The top bar's buttons and Escape leave Edit Mode.
    bar:HookScript("OnHide", function() if RefreshBar then RefreshBar() end end)

    -- what the top bar does is not shown twice: the filter, the two
    -- toggles, Undo, Cancel and Save & Exit stay built (the top bar and
    -- the tests drive them) and out of sight
    bar.desc:SetText("Untick a frame to hide it while you place the rest. The buttons beside a name reset it "
        .. "or open its settings.")
    for _, w in ipairs({ bar.filter, bar.snap, bar.grid, bar.undo, bar.cancel, bar.save }) do w:Hide() end
    bar.dim:ClearAllPoints()
    bar.dim:SetPoint("TOPLEFT", bar.desc, "BOTTOMLEFT", 0, -8)
    bar.showHide:ClearAllPoints()
    bar.showHide:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", pad, pad)
    bar.resetAll:ClearAllPoints()
    bar.resetAll:SetPoint("LEFT", bar.showHide, "RIGHT", 6, 0)
    bar.rule:ClearAllPoints()
    bar.rule:SetPoint("BOTTOMLEFT", bar.showHide, "TOPLEFT", -pad + 1, 8)
    bar.rule:SetPoint("RIGHT", bar, "RIGHT", -1, 0)
end

local function NewRow(i)
    local row = CreateFrame("Frame", nil, bar.list)
    row:SetHeight(ROW)
    row:EnableMouse(true)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl._zui_own = true
    row.hl:SetPoint("TOPLEFT", -4, 0)
    row.hl:SetPoint("BOTTOMRIGHT", 0, 0)
    row.hl:SetTexture(FLAT)
    row.hl:Hide()
    row.reset = IconButton(row, "reset", "Reset", "Back to its default spot.", nil)
    row.reset:SetPoint("RIGHT", 0, 0)
    row.cog = IconButton(row, "settings", "Open its settings", "Leave Edit Mode (keeping your changes) on the page that styles it.", nil)
    row.cog:SetPoint("RIGHT", row.reset, "LEFT", -4, 0)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot._zui_own = true
    row.dot:SetTexture(FLAT)
    row.dot:SetSize(5, 5)
    row.grey = UI.Font(row, F.LABEL, { text = "", cat = "text", key = "disabled" })
    row.grey:SetPoint("LEFT", M.CHECK + 7, 0)
    row.tag = UI.Font(row, F.SMALL, { text = "", cat = "text", key = "disabled" })
    row.tag:SetPoint("LEFT", row.grey, "RIGHT", 6, 0)
    row.box = row:CreateTexture(nil, "ARTWORK")
    row.box._zui_own = true
    row.box:SetTexture(FLAT)
    row.box:SetSize(M.CHECK, M.CHECK)
    row.box:SetPoint("LEFT", 0, 0)
    local bg = ns.GetColor("checkbox", "bg")
    row.box:SetVertexColor(bg.r, bg.g, bg.b, 0.6)
    row:SetScript("OnEnter", function(self)
        if self.why then ShowTip(self, self.movable and self.movable.label or "", self.why) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and self.movable and not self.why then Menu(self.movable) end
    end)
    bar.rows[i] = row
    return row
end

local function PaintRow(row)
    local m = row.movable
    if not m then return end
    local moved = ES.Moved(m.key)
    row.dot:SetShown(moved and not row.why)
    if moved then
        local a = Col("accent")
        row.dot:SetVertexColor(a.r, a.g, a.b, 1)
    end
    local focus = focusKeys[m.key] and true or false
    row.hl:SetShown(focus)
    if focus then
        local c = ns.GetColor("button", "hover")
        row.hl:SetVertexColor(c.r, c.g, c.b, 1)
    end
end

local function BarHeight(listH)
    local descH = math.max(12, (bar.desc and bar.desc:GetStringHeight()) or 24)
    -- (the hidden filter, toggles and second button row take no room)
    return bar.headerHeight + descH + 8 + 30 + 6 + listH
        + 8 + 9 + M.BUTTON_H + M.CARD_PAD
end

FillBar = function()
    local d = DB()
    local y = 0
    local iw = W - 2 * M.CARD_PAD
    local shown = {}
    for _, m in ipairs(current) do
        if Matches(m) then shown[#shown + 1] = m end
    end
    -- (2026-11-10) what can be placed comes first; what cannot (switched
    -- off, Blizzard's own, not on this version) follows under a heading,
    -- so the list reads top to bottom as "these you can move"
    local firstGrey
    do
        local live, grey = {}, {}
        for _, m in ipairs(shown) do
            if StateOf(m) then grey[#grey + 1] = m else live[#live + 1] = m end
        end
        if #grey > 0 then firstGrey = #live + 1 end
        shown = live
        for _, m in ipairs(grey) do shown[#shown + 1] = m end
    end
    if firstGrey and not bar.offHead then
        bar.offHead = UI.Font(bar.list, F.SMALL, { text = "Can't be placed right now  (hover a name for why)",
            cat = "text", key = "disabled" })
    end
    if bar.offHead then bar.offHead:SetShown(firstGrey ~= nil) end
    for i, m in ipairs(shown) do
        if i == firstGrey then
            bar.offHead:ClearAllPoints()
            bar.offHead:SetPoint("BOTTOMLEFT", bar.list, "TOPLEFT", 0, -(y + ROW) + 5)
            y = y + ROW
        end
        local row = bar.rows[i] or NewRow(i)
        row.movable = m
        -- (2026-11-10) one tick box per row for the row's life: its
        -- callback reads the row's movable when clicked. It was rebuilt
        -- on every refill, a new frame each time for every row (frames
        -- are never given back), which is what made the search crawl.
        local tag, why = StateOf(m)
        row.why = tag and why or nil
        -- a frame pushed off the screen says so (its Reset brings it back)
        local off = not tag and m.offscreen and m.offscreen()
        if tag then
            -- greyed: no tick, no buttons; hovering says why
            row.grey:SetText(m.label)
            row.tag:SetText(tag)
            row.grey:Show() row.tag:Show() row.box:Show()
            row.cog:Hide() row.reset:Hide()
            if row.check then row.check:Hide() end
            row.dot:ClearAllPoints()
        else
            row.grey:Hide() row.tag:Hide() row.box:Hide()
            local label = m.label .. (off and " |cffff9933(off screen)|r" or "")
                .. (ES.LinkOf(m.key) and " |cff999999(attached)|r" or "")
            if not row.check then
                row.check = UI.Checkbox(row, label, true, function(v)
                    local mv = row.movable
                    if mv then SetParked(mv, not v) end
                end)
                row.check:SetPoint("LEFT")
            end
            row.check._zText:SetText(label)
            row.check:SetChecked(not IsParked(m.key))
            local textW = row.check._zText and row.check._zText:GetStringWidth() or 0
            row.check:SetWidth(M.CHECK + 7 + math.max(10, textW))
            row.check:Show()
            row.dot:ClearAllPoints()
            row.dot:SetPoint("LEFT", row, "LEFT", M.CHECK + 7 + textW + 6, 0)
            row.reset:SetScript("OnClick", function()
                if m.reset then m.reset(true) ES.Check() RefreshBar() end
            end)
            row.reset:SetShown(m.reset ~= nil)
            row.cog:SetScript("OnClick", function() OpenSettings(m) end)
            row.cog:SetShown(ES.PageFor(m) ~= nil)
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", bar.list, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", bar.list, "RIGHT", 0, 0)
        row._zY = y
        PaintRow(row)
        y = y + ROW
        row:Show()
    end
    for i = #shown + 1, #bar.rows do
        bar.rows[i]:Hide()
        bar.rows[i].movable = nil
    end

    -- the list gets what the screen allows, up to a ceiling; past that
    -- it scrolls, and the scrollbar takes its width from the rows
    local fixed = BarHeight(0)
    local room = (UIParent:GetHeight() or 768) - 80 - fixed
    local listH = math.max(ROW, math.min(math.max(y, ROW), room, 14 * ROW))
    local scrolls = y > listH + 1
    local listW = iw - (scrolls and (M.SCROLL_W + 4) or 0)
    bar.scroll:SetSize(listW, listH)
    bar.list:SetSize(listW, math.max(1, y))
    bar.scroll:Recalculate(y)
    if not scrolls then bar.scrollBar:SetValue(0) end
    bar._rowCount = #shown

    bar:SetHeight(fixed + listH)

    bar:ClearAllPoints()
    if d.barPoint then
        bar:SetPoint(d.barPoint, UIParent, d.barPoint, d.barX or 0, d.barY or 0)
    else
        -- top left, under the top bar: the middle of the screen is where
        -- the HUD is placed
        bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -60)
    end
    RefreshBar()
end

RefreshBar = function()
    if not bar then return end
    local n = ES.MovedCount()
    bar.count:SetText(n == 0 and "" or (n == 1 and "1 moved" or (n .. " moved")))
    bar.undo:SetDisabled(not ES.CanUndo())
    local anyShown = false
    for _, m in ipairs(current) do
        if not IsParked(m.key) and not IsGrey(m) then anyShown = true break end
    end
    bar.showHide:SetLabel(anyShown and "Hide all" or "Show all")
    if top then
        local live = 0
        for _, m in ipairs(current) do
            if not IsGrey(m) and not (IsRaidMod(m) and not DB().showRaidMods) then live = live + 1 end
        end
        -- the status line, long and short (LayoutTop takes what fits)
        if n > 0 then
            top._status = { n .. (n == 1 and " frame moved" or " frames moved"), n .. " moved" }
        else
            top._status = { live .. (live == 1 and " frame" or " frames"), "" }
        end
        top.undo:SetDisabled(not ES.CanUndo())
        top.grid:SetActive(DB().grid and true or false)
        top.snap:SetActive(DB().snap and true or false)
        top.list:SetActive(bar:IsShown() and true or false)
        local anyRM = false
        for _, m in ipairs(current) do if IsRaidMod(m) then anyRM = true break end end
        top.rm:SetShown(anyRM)
        top.rm:SetActive(DB().showRaidMods and true or false)
        LayoutTop()
    end
    if acts and acts:IsShown() and acts.Fill then acts:Fill() end
    for _, row in ipairs(bar.rows) do
        if row:IsShown() and row.movable then PaintRow(row) end
    end
end

-- the list scrolled so a row is in view
local function ScrollTo(key)
    for i, row in ipairs(bar.rows) do
        if row:IsShown() and row.movable and row.movable.key == key then
            local top = (i - 1) * ROW
            if row._zY then top = row._zY end
            local h = bar.scroll:GetHeight() or 0
            local _, max = bar.scrollBar:GetMinMaxValues()
            local v = math.max(0, math.min(max or 0, top - h / 2 + ROW / 2))
            bar.scrollBar:SetValue(v)
            return
        end
    end
end

-- ============================================================
-- THE TOP BAR (2026-11-09)
-- One strip at the top of the screen: what Edit Mode is, how many
-- elements and how many moved, the filter, Grid, Snap, the Elements
-- panel, Undo, Cancel, Save & Exit.
-- ============================================================
local TOP_H = 44
local HINT_H = 22
local FILTER_MIN, FILTER_MAX = 120, 240
local HINT_TEXT = "Drag a box to move it.     Arrow keys nudge the picked box (Shift: 10).     "
    .. "Right-click a box for more.     Escape saves and exits."

-- What fits, from what the texts measure (2026-11-10). Right to left:
-- Save & Exit, Cancel, Undo | Frames, Raid mods (only when there are
-- any), Snap, Grid | the search box. Left: the title and a status line.
-- The search box gets what is left between the two, between FILTER_MIN
-- and FILTER_MAX. When that is too little the status line shortens, then
-- goes; then the search box goes. Nothing is ever laid over anything.
LayoutTop = function()
    if not top then return end
    local width = top:GetWidth() or 640
    local x = 12
    local function Put(b, gap)
        b:ClearAllPoints()
        b:SetPoint("RIGHT", top, "RIGHT", -x, 0)
        x = x + (b:GetWidth() or 0) + gap
    end
    Put(top.save, 6) Put(top.cancel, 6) Put(top.undo, 16)
    Put(top.list, 6)
    if top.rm:IsShown() then Put(top.rm, 6) end
    Put(top.snap, 6) Put(top.grid, 16)
    local left = 14 + 3 + 9 + math.ceil(top.title:GetStringWidth() or 80)
    local st = top._status or { "", "" }
    local tries = { { st[1], true }, { st[2], true }, { "", true }, { st[2], false }, { "", false } }
    for _, t in ipairs(tries) do
        local status, withFilter = t[1], t[2]
        local sw = 0
        if status ~= "" then
            top.count:SetText(status)
            sw = 10 + math.ceil(top.count:GetStringWidth() or (#status * 6))
        end
        local room = width - x - left - sw - 16
        if room >= (withFilter and FILTER_MIN or 0) then
            top.count:SetText(status)
            top.count:SetShown(status ~= "")
            top.filter:SetShown(withFilter)
            if withFilter then
                top.filter:SetWidth(math.min(FILTER_MAX, room))
                top.filter:ClearAllPoints()
                top.filter:SetPoint("RIGHT", top, "RIGHT", -x, 0)
            end
            top._layout = { status = status, filter = withFilter, room = room }
            return
        end
    end
    top.count:SetText("")
    top.count:Hide()
    top.filter:Hide()
    top._layout = { status = "", filter = false, room = 0 }
end

BuildTop = function()
    top = CreateFrame("Frame", "ZacUIEditModeTop", UIParent)
    top:SetFrameStrata("TOOLTIP")
    top:SetHeight(TOP_H)
    local sw = UIParent:GetWidth() or 1024
    top:SetWidth(math.max(640, math.min(1040, sw - 40)))
    top:SetPoint("TOP", UIParent, "TOP", 0, 0)
    top:EnableMouse(true)
    UI.Fill(top, "ui", "windowBg", 0.97)
    UI.Border(top, "ui", "border")
    -- (2026-11-10, Zac: "moveui header is white and no texture") a fill
    -- is white until its box is painted
    top._zPaint = UI.PaintBox
    top:_zPaint()
    top:Hide()

    local tick = top:CreateTexture(nil, "ARTWORK")
    tick._zui_own = true
    tick:SetTexture(FLAT)
    tick:SetSize(3, 20)
    tick:SetPoint("LEFT", top, "LEFT", 14, 0)
    local a = Col("accent")
    tick:SetVertexColor(a.r, a.g, a.b, 1)
    top.title = UI.Font(top, F.TITLE, { text = "Edit Mode", cat = "text", key = "normal" })
    top.title:SetPoint("LEFT", tick, "RIGHT", 9, 0)
    -- the status line: how many frames moved in this pass (LayoutTop
    -- shortens or drops it when the bar is narrow)
    top.count = UI.Font(top, F.SMALL, { text = "", cat = "text", key = "gray" })
    top.count:SetPoint("LEFT", top.title, "RIGHT", 10, -1)
    top.count:SetWordWrap(false)

    local function Btn(label, w, tip, body, fn)
        local b = UI.Button(top, label, { width = w, height = 24, size = F.LABEL, onClick = fn })
        if tip then UI.Tooltip(b, tip, body) end
        return b
    end
    top.save = Btn("Save & Exit", 96, "Save & Exit",
        "Keep everything where it is now, and leave. (Escape does the same.)", function() Exit("save") end)
    top.save:SetActive(true)
    top.cancel = Btn("Cancel", 64, "Cancel",
        "Put back every frame moved since Edit Mode opened, and leave.", function() Exit("cancel") end)
    top.undo = Btn("Undo", 56, "Undo  (Ctrl+Z)", "Put back the last move.", function() ES.Undo() RefreshBar() end)
    top.list = Btn("Frames", 66, "Frames",
        "The list of everything that can be moved: untick one to hide it while you place the rest, "
            .. "reset one or all of them, open a frame's settings, dim the world.", function()
            if bar:IsShown() then bar:Hide() else UI.OpenWindow(bar) end
            RefreshBar()
        end)
    top.snap = Btn("Snap", 52, "Snap to frames",
        "A dragged frame's edges and centre snap to the nearest other frame's, and to the middle and edges "
            .. "of the screen. Hold Alt while dragging to place one freely.", function()
            local d = DB()
            d.snap = not d.snap
            bar.snap:SetChecked(d.snap)
            RefreshBar()
        end)
    top.rm = Btn("Raid mods", 78, "Raid mods",
        "The raid mods' own boxes (timers, warnings, icons, lists): out of the way until you ask for them, "
            .. "so the rest is easier to place.", function()
            local d = DB()
            d.showRaidMods = not d.showRaidMods
            ApplyFilter()
            FillBar()
        end)
    top.grid = Btn("Grid", 52, "Grid", "The grid under everything, one pixel wide.", function()
        local d = DB()
        d.grid = not d.grid
        bar.grid:SetChecked(d.grid)
        PaintOverlay()
        RefreshBar()
    end)

    top.filter = UI.EditBox(top, { width = FILTER_MIN, hint = "Find a frame...", onChange = function(text)
        local t = tostring(text or "")
        -- (the panel's hidden box keeps the same text; the filtering is
        -- done here, a beat after the last key)
        if bar and bar.filter and bar.filter.editBox and bar.filter.editBox:GetText() ~= t then
            bar.filter:SetText(t)
        end
        SetFilter(t)
    end })

    -- HOW TO USE IT, in one line under the bar. It steps aside for the
    -- "click another frame" prompt while one is being picked.
    local hint = CreateFrame("Frame", "ZacUIEditModeHint", top)
    hint:SetFrameStrata("TOOLTIP")
    hint:SetHeight(HINT_H)
    hint:EnableMouse(false)
    UI.Fill(hint, "ui", "windowBg", 0.80)
    hint._zPaint = UI.PaintBox
    hint:_zPaint()
    hint.text = UI.Font(hint, F.SMALL, { text = HINT_TEXT, cat = "text", key = "gray" })
    hint.text:SetPoint("CENTER", 0, 0)
    hint.text:SetWordWrap(false)
    hint:SetPoint("TOP", top, "BOTTOM", 0, 0)
    -- as wide as its text, never wider than the bar (a short version
    -- when even that is too much)
    local tw = math.ceil(hint.text:GetStringWidth() or 560) + 28
    if tw > top:GetWidth() then
        hint.text:SetText("Drag to move.   Arrows nudge.   Right-click for more.   Escape saves.")
        tw = math.min(top:GetWidth(), math.ceil(hint.text:GetStringWidth() or 400) + 28)
    end
    hint:SetWidth(tw)
    top.hint = hint

    LayoutTop()
end

-- ============================================================
-- THE PICKED BOX'S ACTIONS (2026-11-09)
-- Click a box and what can be done with it is written on it (under it
-- when the box is too small): attach / detach, match width, match
-- height, reset, its settings, hide. The same things the right-click
-- menu holds, with nothing to go looking for.
-- ============================================================
local function ActsFor(m)
    local link = ES.LinkOf(m.key)
    local canSize = m.size and m.size.set and true or false
    local out = {}
    -- (2026-11-10) only what can be done with this frame, the common
    -- things first; what it cannot do (and why) is in its right-click menu
    if m.reset ~= nil then
        out[#out + 1] = { "Reset", true, function() if m.reset then m.reset(true) ES.Check() RefreshBar() end end,
            "Back to its default spot. Ctrl+Z puts it back." }
    end
    if ES.PageFor(m) ~= nil then
        out[#out + 1] = { "Settings", true, function() OpenSettings(m) end,
            "Leave Edit Mode (keeping your changes) on the page that styles it." }
    end
    out[#out + 1] = { "Hide", true, function() SetParked(m, true) FillBar() end,
        "Out of the way while you place the rest. The Frames button on the top bar brings it back." }
    if link then
        out[#out + 1] = { "Detach", true, function() ES.Detach(m.key) ES.Check() RefreshBar() end,
            "It stops following the frame it is attached to." }
    elseif m.follower then
        out[#out + 1] = { "Attach to", true, function() StartPick("attach", m) end,
            "Click another frame: this one then follows it wherever it goes." }
    end
    if canSize then
        out[#out + 1] = { "Match width", true, function() StartPick("w", m) end,
            "Click the frame whose width this one should take." }
        out[#out + 1] = { "Match height", true, function() StartPick("h", m) end,
            "Click the frame whose height this one should take." }
    end
    return out
end

local function BuildActs()
    acts = CreateFrame("Frame", "ZacUIEditModeActs", UIParent)
    acts:SetFrameStrata("FULLSCREEN_DIALOG")
    acts:SetHeight(18)
    acts:EnableMouse(true)
    UI.Fill(acts, "ui", "windowBg", 0.92)
    acts._zPaint = UI.PaintBox
    acts:_zPaint()
    acts.items, acts.rules = {}, {}
    acts:Hide()
    local function Item(i)
        local b = acts.items[i]
        if b then return b end
        b = CreateFrame("Button", nil, acts)
        b:SetHeight(18)
        b.text = UI.Font(b, F.SMALL, { text = "", cat = "text", key = "gold" })
        b.text:SetPoint("CENTER", 0, 0)
        b:SetScript("OnEnter", function(self)
            self.hot = true
            acts:Tint(self)
            if self.tip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                local t, c = ns.GetColor("tooltip", "title"), ns.GetColor("tooltip", "body")
                GameTooltip:AddLine(self.text:GetText() or "", t.r, t.g, t.b)
                GameTooltip:AddLine(self.tip, c.r, c.g, c.b, true)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function(self) self.hot = nil acts:Tint(self) GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self) if self.on and self.fn then self.fn() end end)
        local r = acts:CreateTexture(nil, "ARTWORK")
        r._zui_own = true
        r:SetTexture(FLAT)
        r:SetSize(1, 10)
        acts.rules[i] = r
        acts.items[i] = b
        return b
    end
    function acts:Tint(b)
        local c
        if not b.on then c = ns.GetColor("text", "disabled")
        elseif b.hot then c = ns.GetColor("text", "normal")
        else c = Col("accent") end
        b.text:SetTextColor(c.r, c.g, c.b, 1)
    end
    function acts:Fill()
        local h = self.h
        local m = h and MovableOf(h)
        if not (m and h:IsShown()) then self:Hide() return end
        local list = ActsFor(m)
        local x = 6
        local bc = ns.GetColor("text", "disabled")
        for i, it in ipairs(list) do
            local b = Item(i)
            b.text:SetText(it[1])
            b.on, b.fn, b.tip = it[2], it[3], it[4]
            local w = math.floor((b.text:GetStringWidth() or 40) + 12.5)
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("LEFT", self, "LEFT", x, 0)
            b:Show()
            self:Tint(b)
            local r = self.rules[i]
            r:ClearAllPoints()
            r:SetPoint("LEFT", self, "LEFT", x - 1, 0)
            r:SetVertexColor(bc.r, bc.g, bc.b, 0.6)
            r:SetShown(i > 1)
            x = x + w
        end
        for i = #list + 1, #self.items do self.items[i]:Hide() self.rules[i]:Hide() end
        self:SetWidth(x + 6)
        -- on the box, under its name, when there is room; else under the
        -- box (above it at the bottom of the screen)
        self:ClearAllPoints()
        local bw, bh = h:GetWidth() or 0, h:GetHeight() or 0
        local follows = rawget(h, "_zFollows")
        if bw >= x + 16 and bh >= (follows and 62 or 50) then
            self:SetPoint("TOP", h, "CENTER", 0, follows and -18 or -8)
            self._zFill:Hide()
        else
            self._zFill:Show()
            if (h:GetBottom() or 100) < 40 then
                self:SetPoint("BOTTOM", h, "TOP", 0, 18)
            else
                self:SetPoint("TOP", h, "BOTTOM", 0, -16)
            end
        end
        self:Show()
    end
    -- the box went (hidden, filtered, another picked): so do its actions
    acts:SetScript("OnUpdate", function(self, dt)
        self._acc = (self._acc or 0) + dt
        if self._acc < 0.15 then return end
        self._acc = 0
        local h = self.h
        if not (active and h and Kit.selected == h and h:IsShown()) or picking then self:Hide() end
    end)
end

Select = function(h)
    Kit.Select(h)
    if not active then return end
    if not acts then BuildActs() end
    acts.h = h
    if h then acts:Fill() else acts:Hide() end
end

-- ============================================================
-- KEYS (through the handle kit's keyboard frame, up for the pass)
-- ============================================================
local function Key(key)
    if picking and key == "ESCAPE" then StopPick() return true end
    -- Escape: the Frames panel first when it is open, else leave,
    -- keeping the changes (a stray key never throws work away)
    if key == "ESCAPE" and active then
        if bar and bar:IsShown() then bar:Hide() else Exit("save") end
        return true
    end
    if key == "Z" and IsControlKeyDown() then
        if ES.Undo() then RefreshBar() end
        return true
    end
    return false
end

-- ============================================================
-- ENTER / EXIT
-- ============================================================
-- PREVIEW WATCHERS: things with nothing to move but something to show
-- while the HUD is being arranged (the crosshair, the meter windows'
-- lock state) register a function here and are told on every enter
-- (true) and exit (false).
local watchers = {}
local function WatchEditMode(fn)
    watchers[#watchers + 1] = fn
end
local function NotifyWatchers(on)
    for _, fn in ipairs(watchers) do pcall(fn, on) end
end

local KIT_HOOKS = {
    snap = Snap,
    select = function(h) Select(h) end,
    follows = function(h)
        local m = MovableOf(h)
        local link = m and ES.LinkOf(m.key)
        if not link then return nil end
        local to = byKey[link.to]
        return to and to.label or link.to
    end,
    changed = function() ES.Check() end,
    dropped = function() end,
    menu = function(h)
        local m = MovableOf(h)
        if not m then return false end
        Select(h)
        return Menu(m)
    end,
    key = Key,
}

-- opts.focus: a key (or list of keys) to pick out - a settings page's
-- "Move in Edit Mode" sends its frame here
local function Enter(opts)
    if InCombatLockdown and InCombatLockdown() then
        Print("Edit Mode can't open in combat - frames that hold secure buttons can't move in a fight. Try again when it ends.")
        return
    end
    local focus = opts and opts.focus
    if active then
        if focus then ns.EditModeFocus(focus) end
        return
    end
    active = true
    openPage = nil
    filterText = ""
    filterSerial = filterSerial + 1   -- (a search still waiting on its beat is dropped)
    wipe(filtered)

    -- the config window gets out of the way and comes back on the way out
    reopenConfig = ns.ConfigIsOpen and ns.ConfigIsOpen() or false
    if reopenConfig and ZacUIConfigFrame then UI.CloseWindow(ZacUIConfigFrame) end

    current = Movables()
    wipe(byKey)
    for _, m in ipairs(current) do byKey[m.key] = m end
    ES.SetMovables(current)
    ShowOverlay()
    for _, m in ipairs(current) do
        if IsParked(m.key) then FadeContent(m) else ShowMovable(m) end
    end
    ShowGuides()
    ES.Begin()
    ES.OnChange = function() RefreshBar() end
    Kit.edit = KIT_HOOKS
    Kit.EditKeys(true)

    if not bar then BuildBar() end
    if not top then BuildTop() end
    bar.filter:SetText("")
    top.filter:SetText("")
    ApplyFilter()       -- (the raid mods' boxes stay out unless asked for)
    FillBar()
    bar.dim:SetValue(DB().dim)
    bar.grid:SetChecked(DB().grid)
    bar.snap:SetChecked(DB().snap)
    -- (the screen may have changed size since the bar was built)
    top:SetWidth(math.max(640, math.min(1040, (UIParent:GetWidth() or 1024) - 40)))
    top:Show()
    if top.hint then top.hint:Show() end
    RefreshBar()
    NotifyWatchers(true)
    if focus then ns.EditModeFocus(focus) end
end

-- pick one element out: shown, selected, its row in view, a short flash
function ns.EditModeFocus(keys)
    if not active then return end
    if type(keys) ~= "table" then keys = { keys } end
    local first
    for _, key in ipairs(keys) do
        local m = byKey[key]
        if m and not IsGrey(m) then
            if IsParked(key) then SetParked(m, false) end
            first = first or m
        end
    end
    if not first then return end
    -- (a raid mods page sent one of its boxes here: they come in)
    for _, key in ipairs(keys) do
        if byKey[key] and IsRaidMod(byKey[key]) and not DB().showRaidMods then
            DB().showRaidMods = true
            ApplyFilter()
            break
        end
    end
    if filterText ~= "" then
        filterText = ""
    filterSerial = filterSerial + 1   -- (a search still waiting on its beat is dropped)
        bar.filter:SetText("")
        if top then top.filter:SetText("") end
        ApplyFilter()
    end
    wipe(focusKeys)
    for _, key in ipairs(keys) do if byKey[key] then focusKeys[key] = true end end
    focusUntil = (GetTime and GetTime() or 0) + 1.6
    local ok, list = pcall(first.frames or function() end)
    local h = ok and type(list) == "table" and list[1]
    if h and Kit.IsDressed(h) then Select(h) end
    FillBar()
    ScrollTo(first.key)
    if guides then guides._acc = 1 end
end

-- mode: "save" keeps everything (the default), "cancel" puts back every
-- frame moved in this pass
Exit = function(mode)
    if not active then return end
    StopPick()
    if UI.CloseAllDropdowns then UI.CloseAllDropdowns() end
    local undone
    if mode == "cancel" then
        undone = ES.Cancel()
    else
        ES.Check()
    end
    active = false
    ES.OnChange = nil
    Kit.edit = nil
    Kit.Select(nil)
    Kit.EditKeys(false)
    HideGuides()
    for _, m in ipairs(current) do m.hide() end
    UnfadeAll()
    ES.End()
    current = {}
    wipe(byKey)
    wipe(filtered)
    filterText = ""
    filterSerial = filterSerial + 1   -- (a search still waiting on its beat is dropped)
    wipe(focusKeys)
    focusUntil = nil
    if overlay then overlay:Hide() end
    if acts then acts:Hide() end
    if top then
        top:Hide()
        if top.hint then top.hint:Hide() end
    end
    if bar and bar:IsShown() then bar:Hide() end
    if undone and undone > 0 then
        Print(undone == 1 and "1 frame put back where it was." or (undone .. " frames put back where they were."))
    end
    local page = openPage
    openPage = nil
    if page and ns.OpenConfig then
        reopenConfig = false
        ns.OpenConfig(page)
    elseif reopenConfig and ns.OpenConfig then
        reopenConfig = false
        ns.OpenConfig()
    end
    NotifyWatchers(false)
end

local function Toggle()
    if active then Exit("save") else Enter() end
end

-- combat: secure frames cannot move in a fight, the meter unlock and the
-- config reopen are not worth the lockdown errors - a pull ends the pass,
-- keeping what was done
local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:SetScript("OnEvent", function()
    if active then
        Exit("save")
        Print("Edit Mode closed for combat - your changes are kept.")
    end
end)

-- shared with later ZacUI files
ns.EnterEditMode = Enter
ns.ExitEditMode = Exit
ns.CancelEditMode = function() Exit("cancel") end
ns.ToggleEditMode = Toggle
ns.IsEditMode = function() return active end
-- the bar and the list repainted and laid out again (after the bar's
-- width or the UI scale changed)
ns.EditModeRefresh = function() if active and RefreshBar then RefreshBar() end end
ns.WatchEditMode = WatchEditMode
ns.EditModeMovables = Movables
-- the movable frames a settings page styles that can be moved here now
-- (its "Move in Edit Mode" button; Config_EditLinks)
ns.EditModeKeysForPage = function(pageId)
    local out = {}
    for _, m in ipairs(Movables()) do
        if ES.PageFor(m) == pageId then
            -- asked quietly: a page build never prints the "managed by
            -- Edit Mode" note a real move would
            local reg = MOVERS[m.key]
            local f = reg and reg.getFrame()
            local grey
            if reg then
                grey = (not f) or MoverBlocked(m.key, f, true)
            else
                grey = (m.blocked and m.blocked()) or (m.state and m.state() ~= nil)
            end
            if not grey then out[#out + 1] = m.key end
        end
    end
    return out
end
-- Attach to... / Match width... / Match height... for `key` (the menu's
-- items; tests drive the pick through this)
ns.EditModeStartPick = function(kind, key)
    if active and byKey[key] then StartPick(kind, byKey[key]) end
end
