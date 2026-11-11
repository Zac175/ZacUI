-- Tutorial_Tour - the guided tour of the settings window: one part of the
-- window at a time is lit (the rest of the screen dims, an accent ring
-- pulses round it) with a callout beside it - an arrow toward the part, a
-- title, a sentence or two, the step count, and Back / Next / Skip.
-- Part of ZacUI; load order is set by the TOC (after Tutorial_Core and
-- every config file it reads).
--
-- FINDING THINGS. Every step finds its target when it is shown, by name
-- or role, never by position: the nav rows by their menu entry, the
-- search box and title-bar buttons from the window, a page's header and
-- tab row as the page builds them (the two Layout methods are wrapped
-- below to note the live build's frames), the preview by asking its
-- module for its frame. A step whose target is not there - a part that
-- is not loaded, a preview that is folded away or reworked - is skipped
-- and taken out of the count.
--
-- THE WINDOW STAYS USABLE. The dim layer takes no clicks. The tour opens
-- the pages and groups it talks about and, when it ends, puts back the
-- page and the open groups you had. Positions are refitted from a 0.2s
-- ticker (tracked, and cancelled when the tour ends) so a drag, a resize
-- or a scale change of the window is followed; the pulse is an animation
-- group, so nothing runs per frame. Closing the window ends the tour.
--
--   ns.TutorialTour.Start()      open the window and begin
--   ns.TutorialTour.Next() / Back() / Skip() / Stop(reason)
--   ns.TutorialTour.IsActive()
--   ns.TutorialTour.Current()    the step on screen (id, position, total)

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local UI = ns.UI

local M, F = UI.M, UI.F

local Tour = {}

local CALLOUT_W = 330
local PAD = 12
local GAP = 14          -- callout to the lit area
local DIM_ALPHA = 0.5
local RING = 2          -- ring thickness
local FIT_EVERY = 0.2
local START_DELAY = 0.3 -- after the window's pop-in, so the first fit is on the settled frame

local active = false
local index = 0
local dir = 1
local steps
local saved               -- the window's state when the tour began
local lastRect
local ticker
local dim, ring, callout
local hooked              -- the window's OnHide is hooked (once)
local lastGroup           -- the group the previous step opened

-- ============================================================
-- WHAT THE PAGE ON SCREEN BUILT
-- ============================================================
-- The header and the tab row are made inside the page builder, so the
-- live build's (layout.live) are noted here as they are made. Weak, so a
-- rebuilt page's old frames are not kept alive.
local live = setmetatable({}, { __mode = "v" })
do
    local Layout = ns.ConfigLayout
    local origHeader, origTabs = Layout.Header, Layout.Tabs
    Layout.Header = function(self, ...)
        local f = origHeader(self, ...)
        if self.live then live.header, live.tabs = f, nil end
        return f
    end
    Layout.Tabs = function(self, ...)
        local r = origTabs(self, ...)
        if self.live then live.tabs = self.tabBar end
        return r
    end
end

-- ============================================================
-- FINDING TARGETS
-- ============================================================
local function Win()
    local w = _G.ZacUIConfigFrame
    if w and w:IsVisible() then return w end
end

local function Walk(root, fn, depth)
    depth = depth or 0
    if not root or depth > 12 then return nil end
    for _, c in ipairs({ root:GetChildren() }) do
        if fn(c) then return c end
        local hit = Walk(c, fn, depth + 1)
        if hit then return hit end
    end
end

local function Seen(f) return f and f.IsVisible and f:IsVisible() end

local function TextOf(f) return f and f._zText and f._zText.GetText and f._zText:GetText() end

-- A menu entry by its own id (not through the old-id aliases: "profiles"
-- is the group here, not the page an old link to it now opens).
local function MenuItem(id)
    for _, top in ipairs(ns.ConfigMenu or {}) do
        if top.id == id then return top end
        for _, child in ipairs(top.children or {}) do
            if child.id == id then return child end
        end
    end
end

-- A nav row by menu id. Category rows show their chevron, pages do not
-- (the Profiles group and its Profiles page share a label).
local function NavRow(win, id)
    local item = MenuItem(id)
    if not (win and win.nav and item) then return nil end
    local isCat = item.children ~= nil
    return Walk(win.nav, function(f)
        return f._zInd and f._zChevron and Seen(f) and TextOf(f) == item.label
            and (f._zChevron:IsShown() and true or false) == isCat
    end)
end

local function GroupRows(win, id)
    local item = MenuItem(id)
    local out = {}
    for _, child in ipairs((item and item.children) or {}) do
        local r = NavRow(win, child.id)
        if r then out[#out + 1] = r end
    end
    return out
end

local function TitleButton(win, label)
    return Walk(win and win.titleBar, function(f)
        return f._zText and not f._zCheck and Seen(f) and TextOf(f) == label
    end)
end

local function PreviewFrame()
    for _, P in ipairs({ ns.ConfigPreview, ns.Preview }) do
        if type(P) == "table" and type(P.Frame) == "function" then
            local ok, f = pcall(P.Frame)
            if ok and f then return f end
        end
    end
end

-- ============================================================
-- MOVING THE WINDOW ABOUT
-- ============================================================
local function State() return ns.ConfigState and ns.ConfigState() end

-- A search filters the nav; every step wants the whole list.
local function ClearSearch(win)
    local box = win and win.search
    if box and box.GetText and (box:GetText() or "") ~= "" then
        box:SetText("")
        if box.editBox then box.editBox:ClearFocus() end
        return true
    end
    return false
end

local function OpenPage(win, id)
    local s = State()
    local cleared = ClearSearch(win)
    if cleared or not s or s.selected ~= id then
        if ns.ConfigScrollTop then ns.ConfigScrollTop() end
        ns.OpenConfig(id)
    end
end

-- Opens a group in the nav (and folds the one the last step opened, if
-- you did not have it open yourself).
local function OpenGroup(win, id)
    local s = State()
    if not s then return end
    local dirty = ClearSearch(win)
    if lastGroup and lastGroup ~= id and s.expanded[lastGroup] and not (saved and saved.expanded[lastGroup]) then
        s.expanded[lastGroup] = nil
        dirty = true
    end
    lastGroup = id
    if not s.expanded[id] then
        s.expanded[id] = true
        dirty = true
    end
    if dirty and ns.RefreshConfig then ns.RefreshConfig() end
end

-- Scrolls the nav so `row` (down to `last`) is in view.
local function ScrollIntoView(row, last)
    local child = row and row:GetParent()
    local sf = child and child:GetParent()
    local bar = sf and sf.bar
    if not (bar and child.GetTop and sf.GetTop) then return end
    local cTop, rTop, rBot = child:GetTop(), row:GetTop(), (last or row):GetBottom()
    local sTop, sBot = sf:GetTop(), sf:GetBottom()
    if not (cTop and rTop and rBot and sTop and sBot) then return end
    if rTop <= sTop + 0.5 and rBot >= sBot - 0.5 then return end
    local lo, hi = bar:GetMinMaxValues()
    bar:SetValue(math.max(lo or 0, math.min(hi or 0, cTop - rTop - 8)))
end

-- ============================================================
-- THE STEPS
-- ============================================================
-- target(win) -> the frame to light, nil to skip the step. also(win) ->
-- more frames the ring grows to cover. prepare(win) opens what the step
-- needs. available() is the cheap check made when the tour starts (for
-- the count); place is where the callout goes.
local function Group(id, title, body)
    return {
        id = "group:" .. id, title = title, body = body, place = "right",
        available = function() local it = MenuItem(id) return it and it.children ~= nil end,
        prepare = function(win)
            OpenGroup(win, id)
            local rows = GroupRows(win, id)
            ScrollIntoView(NavRow(win, id), rows[#rows])
        end,
        target = function(win) return NavRow(win, id) end,
        also = function(win) return GroupRows(win, id) end,
    }
end

local function OnPage(pageId, step)
    local prep = step.prepare
    step.prepare = function(win)
        OpenPage(win, pageId)
        if prep then prep(win) end
    end
    local avail = step.available
    step.available = function()
        if not (ns.FindMenuItem and ns.FindMenuItem(pageId)) then return false end
        -- (no page where this game version does not run it: Core_Flavor)
        if ns.FeatureOffForPage and ns.FeatureOffForPage(pageId) then return false end
        return (not avail) or avail()
    end
    return step
end

-- The page the header, tab and preview steps stand on: the first of these
-- that builds a tab row here (Tooltips has the standard tabs and a
-- preview; Fonts & Textures is in every install).
local SAMPLE_PAGES = { "tooltips", "font" }
local function OnSample(step)
    local prep = step.prepare
    step.prepare = function(win)
        for _, id in ipairs(SAMPLE_PAGES) do
            if ns.FindMenuItem and ns.FindMenuItem(id) then
                OpenPage(win, id)
                if Seen(live.tabs) then break end
            end
        end
        if prep then prep(win) end
    end
    local avail = step.available
    step.available = function()
        local any = false
        for _, id in ipairs(SAMPLE_PAGES) do
            if ns.FindMenuItem and ns.FindMenuItem(id) then any = true end
        end
        return any and ((not avail) or avail())
    end
    return step
end

local function BuildSteps()
    return {
        { id = "welcome", place = "center", pad = 0,
          title = "This is the settings window",
          body = "Open it any time with /zui or the minimap button. This tour shows where things are. "
              .. "Use Next and Back, or Skip to stop.",
          target = function(win) return win end },
        { id = "nav", place = "right",
          title = "Pages, grouped",
          body = "Every part of ZacUI has a page here. Click a group to open it, then a page.",
          prepare = function(win) ClearSearch(win) end,
          target = function(win) return win.nav end },
        Group("appearance", "Appearance",
            "Start here: one font, one set of colours and one animation speed for all of ZacUI."),
        Group("interface", "Screen",
            "What stays on screen while you play: action bars, unit frames, nameplates, minimap, chat and more."),
        Group("combat", "Combat",
            "Raid timers, the damage meter, scrolling text and other fight helpers. "
            .. "A page whose part is not loaded says how to turn it on."),
        { id = "search", place = "right",
          title = "Search every setting",
          body = "Type what you are after - a page, a word on a checkbox. A result jumps to the exact setting.",
          prepare = function(win) ClearSearch(win) end,
          target = function(win) return win.search end },
        OnSample({ id = "header", place = "below",
          title = "Each page starts with a header",
          body = "The page's name and what it covers. Changes apply the moment you make them - there is no Save button.",
          target = function() return Seen(live.header) and live.header or nil end }),
        OnSample({ id = "tabs", place = "below",
          title = "Tabs split a page up",
          body = "Most pages use the same order - General, Look, Text, Animation, Position, Advanced - "
              .. "and show only the tabs they need.",
          target = function() return Seen(live.tabs) and live.tabs or nil end }),
        OnSample({ id = "preview", place = "left",
          title = "A live preview",
          body = "Pages that change how something looks show a sample of it, updated as you change settings. "
              .. "On many of them you can drag the sample's pieces to move, resize or reorder them - "
              .. "right-click a piece for more, Ctrl+Z undoes.",
          available = function() return (ns.ConfigPreview or ns.Preview) ~= nil end,
          target = function()
              local f = PreviewFrame()
              return Seen(f) and f or nil
          end }),
        { id = "editmode", place = "below",
          title = "Move things with Edit Mode",
          body = "Shows every movable ZacUI frame over a grid. Drag them where you want them, then lock.",
          target = function(win) return TitleButton(win, "Edit Mode") end },
        { id = "reload", place = "below",
          title = "Reload",
          body = "A few settings say they need a reload - turning a part off, for one. This button does it.",
          target = function(win)
              -- (the header's Reload is a drawn glyph, not a label)
              local b = win and win.reloadButton
              if b and Seen(b) then return b end
              return TitleButton(win, "Reload")
          end },
        OnPage("profiles_page", { id = "profiles", place = "right",
          title = "Profiles",
          body = "Each character wears a profile. Keep a second setup, copy one to an alt, "
              .. "or export it as a string to share or back up.",
          prepare = function(win)
              local rows = GroupRows(win, "profiles")
              ScrollIntoView(NavRow(win, "profiles"), rows[#rows])
          end,
          target = function(win) return NavRow(win, "profiles") end,
          also = function(win) return GroupRows(win, "profiles") end }),
        OnPage("changelog", { id = "changelog", place = "right",
          title = "What's new",
          body = "The changelog lists what changed in each version. After an update it opens by itself, once.",
          prepare = function(win) ScrollIntoView(NavRow(win, "changelog")) end,
          target = function(win) return NavRow(win, "changelog") end }),
        OnPage("general", { id = "again", place = "right",
          title = "See it again",
          body = "Replay this tour or run quick setup from here on General, or type /zui tour or /zui setup.",
          target = function(win)
              local T = ns.Tutorial
              local card = T and T.live and T.live.card
              if Seen(card) then return card end
              return win
          end }),
    }
end

-- ============================================================
-- GEOMETRY (UIParent's units throughout)
-- ============================================================
local function ScrollParent(f)
    local p = f and f.GetParent and f:GetParent()
    while p and p ~= UIParent do
        if p.GetObjectType and p:GetObjectType() == "ScrollFrame" then return p end
        p = p.GetParent and p:GetParent()
    end
end

local function RawRect(f)
    if not (f and f.GetLeft) then return nil end
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not (l and r and t and b) then return nil end
    local s = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return l * s, b * s, r * s, t * s
end

-- l, b, r, t of a frame, clipped to the scroll viewport it sits in, or
-- nil when nothing of it shows.
local function RectOf(f, pad)
    local l, b, r, t = RawRect(f)
    if not l or r - l < 2 or t - b < 2 then return nil end
    local sf = ScrollParent(f)
    if sf then
        local sl, sb, sr, st = RawRect(sf)
        if sl and sr - sl > 2 and st - sb > 2 then
            l, b, r, t = math.max(l, sl), math.max(b, sb), math.min(r, sr), math.min(t, st)
            if r - l <= 4 or t - b <= 4 then return nil end
        end
    end
    pad = pad or 6
    return l - pad, b - pad, r + pad, t + pad
end

local function StepRect(step, win)
    local tgt = step.target(win)
    if not Seen(tgt) then return nil end
    local l, b, r, t = RectOf(tgt, step.pad)
    if not l then return nil end
    if step.also then
        for _, f in ipairs(step.also(win) or {}) do
            local fl, fb, fr, ft = RectOf(f, step.pad)
            if fl then
                l, b, r, t = math.min(l, fl), math.min(b, fb), math.max(r, fr), math.max(t, ft)
            end
        end
    end
    return l, b, r, t
end

-- ============================================================
-- FRAMES (built on first use)
-- ============================================================
local function Strip(parent)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t._zui_own = true
    t:SetTexture(FLAT)
    return t
end

local function Build()
    if dim then return end
    dim = CreateFrame("Frame", "ZacUITourDim", UIParent)
    dim:SetAllPoints(UIParent)
    dim:SetFrameStrata("FULLSCREEN_DIALOG")
    dim:SetFrameLevel(100)
    dim:EnableMouse(false)
    dim.strips = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = Strip(dim)
        t:SetVertexColor(0, 0, 0, DIM_ALPHA)
        dim.strips[side] = t
    end
    dim:Hide()

    -- the ring: its own frame, so one alpha animation pulses all four edges
    ring = CreateFrame("Frame", "ZacUITourRing", dim)
    ring:SetFrameLevel(110)
    ring:EnableMouse(false)
    ring.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = ring:CreateTexture(nil, "OVERLAY")
        t._zui_own = true
        t:SetTexture(FLAT)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT")
            t:SetPoint(side .. "RIGHT")
            t:SetHeight(RING)
        else
            t:SetPoint("TOP" .. side)
            t:SetPoint("BOTTOM" .. side)
            t:SetWidth(RING)
        end
        ring.edges[#ring.edges + 1] = t
    end
    ring._zPaint = function(self)
        local a = GetColor("ui", "accent")
        for _, t in ipairs(self.edges) do t:SetVertexColor(a.r, a.g, a.b, 1) end
    end
    ring:_zPaint()
    local ag = ring:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local pulse = ag:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0.35)
    pulse:SetDuration(0.7)
    ring.pulse = ag

    -- the callout: takes the mouse, so a click on it never lands on
    -- whatever is underneath
    local co = CreateFrame("Frame", "ZacUITourCallout", UIParent)
    co:SetWidth(CALLOUT_W)
    co:SetHeight(120)
    co:SetPoint("CENTER")
    co:SetFrameStrata("FULLSCREEN_DIALOG")
    co:SetFrameLevel(120)
    co:EnableMouse(true)
    co:SetClampedToScreen(true)
    UI.Fill(co, "ui", "windowBg")
    UI.Border(co, "ui", "border")
    local bar = co:CreateTexture(nil, "ARTWORK")
    bar._zui_own = true
    bar:SetTexture(FLAT)
    bar:SetWidth(3)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMLEFT", 1, 1)
    co.arrow = co:CreateTexture(nil, "OVERLAY")
    co.arrow._zui_own = true
    co.arrow:SetSize(12, 12)
    co._zPaint = function(self)
        UI.PaintBox(self)
        local a = GetColor("ui", "accent")
        bar:SetVertexColor(a.r, a.g, a.b, 1)
        self.arrow:SetVertexColor(a.r, a.g, a.b, 1)
    end

    co.title = UI.Font(co, F.CARD, { cat = "text", key = "gold", width = CALLOUT_W - 2 * PAD - 22 })
    co.title:SetPoint("TOPLEFT", co, "TOPLEFT", PAD + 2, -PAD)
    co.body = UI.Font(co, F.LABEL, { width = CALLOUT_W - 2 * PAD - 2 })
    co.body:SetPoint("TOPLEFT", co.title, "BOTTOMLEFT", 0, -6)
    if co.body.SetSpacing then co.body:SetSpacing(2) end

    co.close = UI.CloseX(co, 18, function() Tour.Skip() end)
    co.close:SetPoint("TOPRIGHT", co, "TOPRIGHT", -4, -4)
    UI.Tooltip(co.close, "End the tour", "/zui tour starts it again.")

    co.counter = UI.Font(co, F.SMALL, { cat = "text", key = "gray" })
    co.counter:SetPoint("BOTTOMLEFT", co, "BOTTOMLEFT", PAD + 2, PAD + 5)
    co.next = UI.Button(co, "Next", { width = 74, onClick = function() Tour.Next() end })
    co.next:SetPoint("BOTTOMRIGHT", co, "BOTTOMRIGHT", -PAD, PAD)
    co.back = UI.Button(co, "Back", { width = 60, onClick = function() Tour.Back() end })
    co.back:SetPoint("RIGHT", co.next, "LEFT", -6, 0)
    co.skip = UI.Button(co, "Skip", { width = 56,
        tooltip = "Ends the tour. /zui tour starts it again.",
        onClick = function() Tour.Skip() end })
    co.skip:SetPoint("RIGHT", co.back, "LEFT", -6, 0)
    co:_zPaint()
    co:Hide()
    callout = co
end

-- ============================================================
-- LAYING IT OUT
-- ============================================================
local function Place(t, x, y, w, h)
    if w <= 1 or h <= 1 then t:Hide() return end
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    t:SetSize(w, h)
    t:Show()
end

-- The arrow sits on the callout's edge nearest the lit area and points
-- at it. The art: TEX_ARROW points down, TEX_ARROWL left.
local function Arrow(co, side)
    local a = co.arrow
    a:ClearAllPoints()
    if side == "right" then        -- callout right of the target: point left
        a:SetTexture(ns.TEX_ARROWL) a:SetTexCoord(0, 1, 0, 1)
        a:SetPoint("RIGHT", co, "TOPLEFT", 1, -22)
    elseif side == "left" then     -- point right
        a:SetTexture(ns.TEX_ARROWL) a:SetTexCoord(1, 0, 0, 1)
        a:SetPoint("LEFT", co, "TOPRIGHT", -1, -22)
    elseif side == "below" then    -- point up
        a:SetTexture(ns.TEX_ARROW) a:SetTexCoord(0, 1, 1, 0)
        a:SetPoint("BOTTOM", co, "TOP", 0, -1)
    elseif side == "above" then    -- point down
        a:SetTexture(ns.TEX_ARROW) a:SetTexCoord(0, 1, 0, 1)
        a:SetPoint("TOP", co, "BOTTOM", 0, 1)
    else
        a:Hide()
        return
    end
    a:Show()
end

local function PlaceCallout(place, l, b, r, t)
    local co = callout
    local W, H = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    local cw, ch = co:GetWidth() or CALLOUT_W, co:GetHeight() or 120
    local w, h = r - l, t - b
    co:ClearAllPoints()
    if place == "center" then
        co:SetPoint("CENTER", UIParent, "BOTTOMLEFT", l + w / 2, b + h / 2)
        Arrow(co, nil)
        return "center"
    end
    local order
    if place == "left" then order = { "left", "right", "below", "above" }
    elseif place == "below" then order = { "below", "above", "right", "left" }
    elseif place == "above" then order = { "above", "below", "right", "left" }
    else order = { "right", "left", "below", "above" } end
    for _, p in ipairs(order) do
        if p == "right" and r + GAP + cw <= W - 4 then
            co:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", r + GAP, math.min(t, H - 4))
            Arrow(co, "right")
            return p
        elseif p == "left" and l - GAP - cw >= 4 then
            co:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", l - GAP, math.min(t, H - 4))
            Arrow(co, "left")
            return p
        elseif p == "below" and b - GAP - ch >= 4 then
            co:SetPoint("TOP", UIParent, "BOTTOMLEFT", l + w / 2, b - GAP)
            Arrow(co, "below")
            return p
        elseif p == "above" and t + GAP + ch <= H - 4 then
            co:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", l + w / 2, t + GAP)
            Arrow(co, "above")
            return p
        end
    end
    -- nowhere fits: over the middle of it, clamped to the screen
    co:SetPoint("CENTER", UIParent, "BOTTOMLEFT", l + w / 2, b + h / 2)
    Arrow(co, nil)
    return "center"
end

-- Lays the dim, the ring and the callout round the current step. False
-- when its target is gone.
local function Fit()
    local step = steps and steps[index]
    local win = Win()
    if not (step and win) then return false end
    local l, b, r, t = StepRect(step, win)
    if not l then return false end
    local W, H = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    local s = dim.strips
    Place(s.top, 0, t, W, H - t)
    Place(s.bottom, 0, 0, W, b)
    Place(s.left, 0, b, l, t - b)
    Place(s.right, r, b, W - r, t - b)
    ring:ClearAllPoints()
    ring:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    ring:SetSize(r - l, t - b)
    Tour.side = PlaceCallout(step.place, l, b, r, t)
    lastRect = { l, b, r, t }
    return true
end

local function Moved(l, b, r, t)
    if not lastRect then return true end
    return math.abs(lastRect[1] - l) > 0.5 or math.abs(lastRect[2] - b) > 0.5
        or math.abs(lastRect[3] - r) > 0.5 or math.abs(lastRect[4] - t) > 0.5
end

-- ============================================================
-- STEPPING
-- ============================================================
local function Applies(step) return not step.gone end

local function Numbering(idx)
    local pos, total = 0, 0
    for i, step in ipairs(steps) do
        if Applies(step) then
            total = total + 1
            if i == idx then pos = total end
        end
    end
    return pos, total
end

local function HasEarlier(idx)
    for i = idx - 1, 1, -1 do if Applies(steps[i]) then return true end end
    return false
end

local function Reveal()
    dim:Show()
    ring:Show()
    if ring.pulse and ring.pulse.Play and not ring.pulse:IsPlaying() then ring.pulse:Play() end
    callout:Show()
    callout:Raise()
end

local function ShowStep(idx, d)
    local win = Win()
    if not win then Tour.Stop("closed") return end
    d = d or 1
    dir = d
    local n = #steps
    -- walk past the steps this window cannot show
    while idx >= 1 and idx <= n do
        local step = steps[idx]
        if Applies(step) then
            if step.prepare then pcall(step.prepare, win) end
            if StepRect(step, win) then break end
            step.gone = true
        end
        idx = idx + d
    end
    if idx > n then Tour.Stop("finished") return end
    if idx < 1 then
        -- nothing left behind us: show the first one that still applies
        for i = 1, n do
            if Applies(steps[i]) then return ShowStep(i, 1) end
        end
        Tour.Stop("lost")
        return
    end
    index = idx
    local st = ns.Tutorial and ns.Tutorial.DB()
    if st then st.step = math.max(tonumber(st.step) or 0, idx) end

    local step = steps[idx]
    local co = callout
    co.title:SetText(step.title or "")
    local body = step.body
    if type(body) == "function" then body = body(win) end
    co.body:SetText(body or "")
    local pos, total = Numbering(idx)
    co.counter:SetText(pos .. " of " .. total)
    local th = co.title:GetStringHeight() or 14
    local bh = co.body:GetStringHeight() or 24
    co:SetHeight(PAD + th + 6 + bh + 14 + M.BUTTON_H + PAD)
    co.back:SetShown(HasEarlier(idx))
    local last = (pos == total)
    co.next:SetLabel(last and "Done" or "Next")
    co.next:SetActive(last)
    co.skip:SetShown(not last)
    lastRect = nil
    if Fit() then Reveal() else Tour.Stop("lost") end
end

function Tour.Next()
    if not active then return end
    if index >= #steps then Tour.Stop("finished") return end
    ShowStep(index + 1, 1)
end

function Tour.Back()
    if not active then return end
    ShowStep(index - 1, -1)
end

function Tour.Skip()
    Tour.Stop("skipped")
end

local function Tick()
    if not active or index == 0 then return end
    local win = Win()
    if not win then Tour.Stop("closed") return end
    local step = steps[index]
    local l, b, r, t = StepRect(step, win)
    if not l then
        -- the window rebuilt under it (a click on a page, a scroll): try
        -- to bring it back, and move on when it cannot be
        if step.prepare then pcall(step.prepare, win) end
        l, b, r, t = StepRect(step, win)
        if not l then
            step.gone = true
            ShowStep(index + dir, dir)
            return
        end
    end
    if Moved(l, b, r, t) then Fit() end
end

function Tour.Start()
    if active then return true end
    if not ns.OpenConfig then return false end
    ns.OpenConfig()
    local win = _G.ZacUIConfigFrame
    if not win then return false end
    Build()
    local s = State()
    saved = { selected = s and s.selected, expanded = {} }
    for k, v in pairs((s and s.expanded) or {}) do saved.expanded[k] = v end
    steps = BuildSteps()
    for _, step in ipairs(steps) do
        local ok, yes = pcall(function() return (not step.available) or step.available() end)
        step.gone = not (ok and yes) or nil
    end
    active, index, dir, lastRect, lastGroup = true, 0, 1, nil, nil
    if not hooked then
        hooked = true
        win:HookScript("OnHide", function() if active then Tour.Stop("closed") end end)
    end
    local t = C_Timer.NewTicker(FIT_EVERY, Tick)
    ticker = (ns.Profiler and ns.Profiler.TrackTicker) and ns.Profiler.TrackTicker(t, "tutorial.tour") or t
    C_Timer.After(START_DELAY, function()
        if active and index == 0 then ShowStep(1, 1) end
    end)
    return true
end

-- Everything off, the window put back the way it was. reason: finished,
-- skipped, closed, lost.
function Tour.Stop(reason)
    if ticker then ticker:Cancel() ticker = nil end
    if ring then
        if ring.pulse and ring.pulse.Stop then ring.pulse:Stop() end
        ring:Hide()
    end
    if dim then dim:Hide() end
    if callout then callout:Hide() end
    local was = active
    active, index, lastRect = false, 0, nil
    if not was then return end
    Tour.lastReason = reason
    local st = ns.Tutorial and ns.Tutorial.DB()
    if st and reason == "finished" then st.tourDone = true end
    -- the page and the open groups you had
    local s = State()
    if s and saved then
        for k in pairs(s.expanded) do s.expanded[k] = nil end
        for k, v in pairs(saved.expanded) do s.expanded[k] = v end
        local back = saved.selected
        saved = nil
        local win = Win()
        if win and back then
            if ns.ConfigScrollTop then ns.ConfigScrollTop() end
            ns.OpenConfig(back)
        elseif back then
            s.selected = back
        end
    end
    lastGroup = nil
end

function Tour.IsActive() return active end

function Tour.Current()
    if not (active and steps and steps[index]) then return nil end
    local pos, total = Numbering(index)
    return steps[index].id, pos, total
end

-- for the tests
function Tour.Frames() return dim, ring, callout end
function Tour.StepIds()
    local out = {}
    for _, s in ipairs(BuildSteps()) do out[#out + 1] = s.id end
    return out
end

-- shared with later ZacUI files
ns.TutorialTour = Tour
