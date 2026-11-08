-- Config_Window - the sidebar settings window: shell, nav, search, and
-- the content pane pages are rendered into.
-- Part of ZacUI; load order is set by the TOC.
--
-- Structure, left to right:
--   [ 186px nav | 1px rule | content pane with its own scroll ]
-- On a page with a preview (Config_Preview) the page's title and the
-- preview strip under it are pinned at the top of the content pane, and
-- the scroll area starts below them; the window never changes size.
-- The nav scrolls independently of the content, because the module list
-- is long and losing your place in it while reading a page is worse than
-- the extra scrollbar.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local ConfigLayout = ns.ConfigLayout
local ConfigPages = ns.ConfigPages
local ConfigState = ns.ConfigState
local FLAT = ns.FLAT
local FindMenuItem = ns.FindMenuItem
local GetColor = ns.GetColor
local Print = ns.Print
local UI = ns.UI
local VisibleRows = ns.VisibleRows
local ZUI = ns.ZUI
local Search = ns.ConfigSearch
local SearchBox = ns.ConfigSearchBox
local Preview = ns.ConfigPreview

local M, F = UI.M, UI.F

local WIDTH, HEIGHT = 1300, 946
-- the part on/off glyph (Media/Icons/power, drawn for ZacUI 2026-11-07)
ns.ICON_POWER = ns.ICON_POWER or ((ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\power")
local MIN_W, MAX_W = 1000, 1600

local window, navScroll, navChild, content, contentScroll, pane
-- head: the pinned top of the content pane (the page's title and the
-- preview strip), shown only on a page with a preview.
local head, pinnedHeader, pinnedTabs, headTabBand, headStripBand, headStripDiv
local S = UI.S
local stripY = 0      -- where the strip starts in head (under the title and tabs)
local pageW = WIDTH   -- the window's width, as you sized it
local rowPool = {}

-- SEARCH. The box and its dropdown of results are Config_SearchBox's
-- (the index and ranking Config_Search's); this file lends them the nav
-- column, and does the jump. lastReal: what the page on screen contains
-- (with live widgets), read back after every build, so a jump can find
-- the exact frame to scroll to and flash.
local lastReal
local JumpTo
-- the window comforts (finish pass, defined below Build, used in it)
local badge, fightWatch, WatchFights, ApplyOpacity, Opacity

-- ============================================================
-- NAV ROWS (match pass 2026-11-07: EllesmereUI's sidebar, UI.S)
-- ============================================================
-- Three kinds, one pooled shape: a GROUP (a category: its name in the
-- accent at 15, a +/- after it while hovered, 28 tall), a CHILD (a page
-- in a category: 14 px at 36, 28 tall) and a PAGE at the top level (as a
-- child, 20 in). A selected row: a 3 px accent bar on its left edge, an
-- accent wash fading right (0.15 to 0), a hairline above and below; under
-- the mouse: white 0.06, a pale wash (0.03) and a pale bar (0.25). The
-- label: 1.0 selected, 0.60 at rest, 0.86 hovered; a part that is off
-- 0.11 (0.39 hovered).
local function Grad(tex, c, a0)
    if CreateColor and tex.SetGradient then
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradient("HORIZONTAL", CreateColor(c.r, c.g, c.b, a0), CreateColor(c.r, c.g, c.b, 0))
    elseif tex.SetGradientAlpha then
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradientAlpha("HORIZONTAL", c.r, c.g, c.b, a0, c.r, c.g, c.b, 0)
    else
        tex:SetVertexColor(c.r, c.g, c.b, a0 / 2)
    end
end

local function PaintRow(self)
    local a = GetColor("ui", "accent")
    local sel, hot, kind = self._zSelected, self._zHot, self._zKind
    local group = kind == "group"
    -- a part that is off (or waits for a reload to come on)
    local off = false
    -- THE PART'S SWITCH (2026-11-08, EllesmereUI's toggle at its small
    -- size): the knob right and the track in the accent when the part
    -- loads next time, left and #444 when it does not, the track orange
    -- while a reload is waiting to change it. A part that is simply on
    -- shows only its label; the switch comes up under the mouse.
    local pw = self._zPower
    if pw and pw:IsShown() and pw._zItem then
        local state, pending = ns.PartState(pw._zItem.addon)
        off = state ~= "on"
        local nextOn = (state == "on") ~= (pending and true or false)
        local c, al
        if pending then c, al = GetColor("text", "orange"), S.TG_ON_A
        elseif nextOn then c, al = a, S.TG_ON_A
        else c, al = S.TG_OFF, S.TG_OFF_A end
        pw._zPill:Color(c.r, c.g, c.b, al)
        local k = pw._zKnob
        k:ClearAllPoints()
        if nextOn then k:SetPoint("RIGHT", pw, "RIGHT", -S.KNOB_PAD, 0)
        else k:SetPoint("LEFT", pw, "LEFT", S.KNOB_PAD, 0) end
        k:SetVertexColor(1, 1, 1, nextOn and 1 or S.KNOB_OFF_A)
        -- (still there for the mouse while it is see-through)
        pw:SetAlpha((off or pending or hot or pw._zHot) and 1 or 0)
    end
    local showSel = sel and not group
    self._zInd:SetShown(showSel)
    self._zInd:SetVertexColor(a.r, a.g, a.b, 1)
    self._zGlow:SetShown(showSel)
    if showSel then Grad(self._zGlow, a, S.NAV_GLOW) end
    self._zEdgeT:SetShown(showSel)
    self._zEdgeB:SetShown(showSel)
    if showSel then Grad(self._zEdgeT, S.EDGE_TINT, S.NAV_EDGE) Grad(self._zEdgeB, S.EDGE_TINT, S.NAV_EDGE) end
    local hover = hot and not showSel and not group
    self._zHL:SetShown(hover)
    self._zHL:SetVertexColor(1, 1, 1, S.NAV_HL)
    self._zHoverGlow:SetShown(hover)
    if hover then Grad(self._zHoverGlow, S.HOVER_TINT, S.NAV_HOVER_GLOW) end
    self._zHoverInd:SetShown(hover)
    local h = S.HOVER_TINT
    self._zHoverInd:SetVertexColor(h.r, h.g, h.b, S.NAV_HOVER_IND)
    if group then
        local k = hot and 1.25 or 1
        local r, g, b = math.min(1, a.r * k), math.min(1, a.g * k), math.min(1, a.b * k)
        self._zText:SetTextColor(r, g, b, 1)
        self._zSign:SetVertexColor(r, g, b, 1)
        self._zSign:SetShown(hot and true or false)
        return
    end
    self._zSign:Hide()
    local ta
    if sel then ta = 1
    elseif off then ta = hot and S.NAV_OFF_HOVER or S.NAV_OFF
    else ta = hot and S.NAV_HOVER or S.NAV_EN end
    self._zText:SetTextColor(1, 1, 1, ta)
end

local function AcquireRow(index)
    local row = rowPool[index]
    if row then return row end
    row = CreateFrame("Button", nil, navChild)
    row:SetHeight(S.CHILD_ROW)
    local function Tex(layer, sub)
        local t = row:CreateTexture(nil, layer, nil, sub)
        t._zui_own = true
        t:SetTexture(FLAT)
        t:Hide()
        return t
    end
    row._zGlow = Tex("BACKGROUND", 1)
    row._zGlow:SetAllPoints()
    row._zHoverGlow = Tex("BACKGROUND", 2)
    row._zHoverGlow:SetAllPoints()
    row._zHL = Tex("BACKGROUND", 3)
    row._zHL:SetAllPoints()
    local function Edge(side)
        local g = Tex("BORDER", 0)
        if ns.Pixel then ns.Pixel.Edge(g, side, row) else g:SetHeight(1) end
        g:SetPoint(side .. "LEFT", row, side .. "LEFT", 0, 0)
        g:SetPoint(side .. "RIGHT", row, side .. "RIGHT", 0, 0)
        return g
    end
    row._zEdgeT, row._zEdgeB = Edge("TOP"), Edge("BOTTOM")
    local function Bar(sub)
        local t = Tex("ARTWORK", sub)
        t:SetWidth(3)
        t:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        t:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        return t
    end
    row._zInd, row._zHoverInd = Bar(2), Bar(1)

    row._zText = UI.SFont(row, S.F_NAV, { justify = "LEFT" })
    row._zText:SetWordWrap(false)
    -- a group's +/- (ZacUI's add / minus icons), right after its name
    local sign = row:CreateTexture(nil, "ARTWORK")
    sign._zui_own = true
    sign:SetSize(14, 14)
    sign:SetPoint("LEFT", row._zText, "RIGHT", 4, 0)
    sign:Hide()
    row._zSign = sign
    -- (an invisible marker, shown on a group row: the tour and older code
    -- tell a category row from a page row by it)
    local chev = row:CreateTexture(nil, "ARTWORK")
    chev._zui_own = true
    chev:SetSize(1, 1)
    chev:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    chev:SetAlpha(0)
    row._zChevron = chev

    -- THE PART'S SWITCH (finish pass; a switch since 2026-11-08): on every
    -- row, shown on the rows that are a part (item.addon); PaintRow draws
    -- it. A click asks "Turn off and reload" (ns.AskPart).
    -- (EllesmereUI's toggle at its inline size, 0.8: a 32 x 16 pill, a
    -- 12 px round knob two in - our disc art, UI.Pill / UI.DiscArt)
    local SW, SH = math.floor(S.TOGGLE_W * 0.8 + 0.5), math.floor(S.TOGGLE_H * 0.8 + 0.5)
    local pw = CreateFrame("Button", nil, row)
    pw:SetSize(SW, SH)
    pw:SetPoint("RIGHT", -18, 0)
    pw:SetFrameLevel(row:GetFrameLevel() + 2)
    pw:SetHitRectInsets(-4, -4, -6, -6)
    local pill = UI.Pill(pw, "ARTWORK", 1, SH)
    pw._zPill = pill
    pw._zTex = pill.m
    local knob = pw:CreateTexture(nil, "ARTWORK", nil, 2)
    knob._zui_own = true
    local kd = SH - 2 * S.KNOB_PAD
    UI.DiscArt(knob, kd)
    knob:SetSize(kd, kd)
    pw._zKnob = knob
    pw:SetScript("OnEnter", function(self)
        self._zHot = true
        row._zHot = true
        row:_zPaint()
        local item = self._zItem
        if not item then return end
        local state, pending = ns.PartState(item.addon)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local t = GetColor("tooltip", "title")
        GameTooltip:AddLine(item.label, t.r, t.g, t.b)
        local o, g = GetColor("text", "orange"), GetColor("text", "gray")
        local now, click
        if state == "on" then
            now = pending and "Turns off at the next reload." or "On."
            click = pending and "Click to keep it on (reloads)." or "Click to turn it off (reloads)."
        else
            now = pending and "Turns on at the next reload." or "Off for this character."
            click = pending and "Click to keep it off (reloads)." or "Click to turn it on (reloads)."
        end
        local nc = (pending or state ~= "on") and o or GetColor("text", "green")
        GameTooltip:AddLine(now, nc.r, nc.g, nc.b)
        GameTooltip:AddLine(click, g.r, g.g, g.b)
        GameTooltip:Show()
    end)
    pw:SetScript("OnLeave", function(self)
        self._zHot = nil
        row._zHot = nil
        row:_zPaint()
        GameTooltip:Hide()
    end)
    pw:SetScript("OnClick", function(self)
        local item = self._zItem
        if not item then return end
        local state, pending = ns.PartState(item.addon)
        -- the switch flips what the NEXT load does
        local nextOn = (state == "on") ~= (pending and true or false)
        ns.AskPart(item.addon, item.label, not nextOn)
    end)
    row._zPower = pw

    row._zPaint = PaintRow
    row:HookScript("OnEnter", function(self) self._zHot = true; self:_zPaint() end)
    row:HookScript("OnLeave", function(self) self._zHot = nil; self:_zPaint() end)
    rowPool[index] = row
    return row
end

-- ============================================================
-- CONTENT
-- ============================================================
-- Everything under the scroll child is destroyed-by-orphaning on every
-- page change. WoW has no frame destructor, so the honest move is to
-- hide, unparent and drop the reference: the frames become garbage and
-- nothing on screen or in a pool still points at them.
local function ClearContent()
    if not content then return end
    -- The widgets the page took from the pool go back to it first (see
    -- UIF_Pool: the next build gets them back instead of making new
    -- frames); what is left - parts a page made by hand - is let go below.
    UI.CloseAllDropdowns()
    if ns.UIPool then pcall(ns.UIPool.Release) end
    if pinnedHeader and pinnedHeader._zPoolKey then
        pinnedHeader = nil
    end
    -- the previous page's title, pinned above its preview strip
    if pinnedHeader then
        pinnedHeader:Hide()
        pinnedHeader:ClearAllPoints()
        pinnedHeader:SetParent(nil)
        pinnedHeader = nil
    end
    -- and its tab bar (a pooled one went back with the pool, above)
    if pinnedTabs then
        if not pinnedTabs._zPoolKey then
            pinnedTabs:Hide()
            pinnedTabs:ClearAllPoints()
            pinnedTabs:SetParent(nil)
        end
        pinnedTabs = nil
    end
    if headTabBand then headTabBand:Hide() end
    stripY = 0
    -- Dropdown menus are parented to UIParent so they are not clipped by
    -- their card. That also means this loop cannot reach them: without
    -- this, an open list survives a page change and floats over the new
    -- page, still driving the old page's callback.
    UI.CloseAllDropdowns()
    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide()
        child:ClearAllPoints()
        child:SetParent(nil)
    end
    for _, region in ipairs({ content:GetRegions() }) do
        region:Hide()
        region:ClearAllPoints()
        region:SetParent(nil)
    end
end

-- THE PAGE'S TITLE, PINNED. On a page with a preview the title (and its
-- gold rule) moves out of the scrolled page into head, the strip goes
-- under it, and everything else on the page moves up by the room the
-- title took, so the scrolled page starts with its first card. Returns
-- how far the page moved up.
local function ShiftUp(obj, dy)
    local n = obj.GetNumPoints and obj:GetNumPoints() or 0
    if n == 0 then return end
    local pts = {}
    for i = 1, n do pts[i] = { obj:GetPoint(i) } end
    obj:ClearAllPoints()
    for _, q in ipairs(pts) do
        local p, rel, rp, x, y = q[1], q[2], q[3], q[4] or 0, q[5] or 0
        if (rel == nil or rel == content) and rp and rp:find("TOP") then y = y + dy end
        obj:SetPoint(p, rel or content, rp, x, y)
    end
end

-- THE PAGE'S TOP, PINNED (match pass: EllesmereUI's header). The page's
-- title (UI.PageHeader: 138 tall) moves out of the scrolled page into
-- head; everything else moves up so the page (its tab bar first, on its
-- black 0.20 band) starts 10 under the top of the scroll area. Returns how
-- far the page moved up.
local function PinHeader(layout)
    stripY = 0
    local hf = layout and layout.headerFrame
    if not (hf and hf:GetParent() == content) then return 0 end
    local _, _, _, _, hy = hf:GetPoint(1)
    hy = hy or 0
    -- only the page's own title at its top, not a heading further down
    if hy < -30 then return 0 end
    local hh = hf:GetHeight() or S.HEADER
    hf:SetParent(head)
    hf:ClearAllPoints()
    hf:SetPoint("TOPLEFT", head, "TOPLEFT", 0, 0)
    hf:SetPoint("RIGHT", head, "RIGHT", 0, 0)
    hf:Show()
    pinnedHeader = hf
    -- (the tab bar stays the first thing on the scrolled page, right under
    -- the pinned title and preview: every page and suite finds its tabs on
    -- the page, as before)
    local tabY, tabH
    if headTabBand then headTabBand:Hide() end
    stripY = hh + (tabH or 0)
    -- above the tab row: up by the title; below it: by the title and the row
    local upA = (-hy) + hh - S.TOP_PAD
    local upB = tabY and (upA + tabH) or upA
    local function Move(o)
        local n = o.GetNumPoints and o:GetNumPoints() or 0
        if n == 0 then return end
        local _, rel, rp, _, y = o:GetPoint(1)
        if (rel == nil or rel == content) and rp and rp:find("TOP") and tabY and (y or 0) <= tabY - tabH + 0.5 then
            ShiftUp(o, upB)
        else
            ShiftUp(o, upA)
        end
    end
    for _, child in ipairs({ content:GetChildren() }) do Move(child) end
    for _, region in ipairs({ content:GetRegions() }) do Move(region) end
    return upB
end

local ShowPage
-- Forward declared: Build's resize callback closes over it, and Build is
-- written above the definition. A local declared later is a DIFFERENT
-- variable, so without this the callback captures a global nil and the
-- window silently stops refreshing after a resize.
local RefreshConfig
local BuildNav

local function BuildNavInner()
    local s = ConfigState()
    local filter = window and window.search and window.search:GetText() or ""
    local searching = filter:find("%S") ~= nil
    local rows = VisibleRows(filter, searching and SearchBox.Hits() or nil)
    local y = 0
    local groups = 0

    for i, entry in ipairs(rows) do
        local item, row = entry.item, AcquireRow(i)
        local kind = entry.isCategory and "group" or (entry.isChild and "child" or "page")
        -- EllesmereUI's sidebar: 10 between groups, 28 a row
        if kind ~= "child" and groups > 0 then y = y - S.GROUP_GAP end
        if kind ~= "child" then groups = groups + 1 end
        local rh = (kind == "group") and S.GROUP_ROW or S.CHILD_ROW
        row._zKind = kind
        row._zChevron:SetShown(kind == "group")
        row:SetHeight(rh)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", navChild, "TOPLEFT", 0, y)
        row:SetPoint("RIGHT", navChild, "RIGHT", 0, 0)

        -- a page whose part this game version does not run is marked
        local label = item.label
        if ns.FeatureOffForPage and ns.FeatureOffForPage(item.id) then
            label = label .. "  |cff8a8a8aoff|r"
        end
        local fs = row._zText
        UI._zFontDress(fs, (kind == "group") and S.F_GROUP or S.F_NAV)
        fs:SetText(label)
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", row, "LEFT", (kind == "child") and S.CHILD_X or S.NAV_LEFT, 0)
        -- a part's power button (ns.PartState: in the AddOns folder)
        local part = item.addon and ns.PartState and ns.PartState(item.addon) ~= "missing"
        local pw = row._zPower
        pw._zItem = part and item or nil
        pw:SetShown(part and true or false)
        if kind == "group" then
            -- the label takes its text's width, so the +/- follows it
            fs:SetWidth(0)
            row._zSign:SetTexture(((ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\")
                .. (s.expanded[item.id] and "minus" or "add"))
        else
            fs:SetPoint("RIGHT", row, "RIGHT", part and -(18 + math.floor(S.TOGGLE_W * 0.8 + 0.5) + 12) or -18, 0)
        end

        row._zSelected = (s.selected == item.id)
        row:SetScript("OnClick", function()
            if entry.isCategory and item.children then
                s.expanded[item.id] = not s.expanded[item.id]
                -- A category with no page of its own opens to its first
                -- child rather than showing nothing.
                if not item.page and s.expanded[item.id] and item.children[1] then
                    ShowPage(item.children[1].id)
                    return
                end
                BuildNav()
                return
            end
            -- While searching, a page in the filtered list opens at the
            -- best thing it matched, not at its top.
            if searching then
                local best = SearchBox.BestFor(item.id)
                if best then
                    SearchBox.Go(best)
                    return
                end
            end
            ShowPage(item.id)
        end)
        row:Show()
        row:_zPaint()
        y = y - rh
    end

    for i = #rows + 1, #rowPool do rowPool[i]:Hide() end
    navChild:SetHeight(math.max(1, -y + 8))
    navScroll:Recalculate(-y + 8)
end

function BuildNav()
    local was = UI._zSettings
    UI._zSettings = true
    local ok, err = pcall(BuildNavInner)
    UI._zSettings = was
    if not ok then error(err, 0) end
end

-- The page the scroll offset below belongs to. Kept beside it so the two
-- can never describe different pages.
local scrolledPage, scrolledTo = nil, 0

-- A PAGE BUILD THAT REACHES BACK INTO THE CONFIG.
-- The aura page calls WeakAuras' OpenOptions while it is building, and the
-- engine's ShowOptions ends by calling WeakAuras.ZacUI.OpenPage - which is
-- OpenConfig("auras"), which lands right back in here with the page only
-- half built. The nested call cleared the half-built page and built a
-- COMPLETE second one; the outer build then carried on appending its own
-- cards on top, leaving two whole pages stacked in the same space.
--
-- Two identical pages look like one until something inside them scrolls
-- independently. The aura tree does: the wheel only reaches the topmost
-- scroll frame, so the copy underneath stays where it was and the pane
-- shows two lists sliding over each other, section headings landing in
-- the middle of rows and grey text behind everything.
--
-- The guard is here rather than in EnterEditMode because the loop is a
-- property of the window, not of that one page: any page whose build
-- touches something that opens the config would do the same.
local building, queuedPage = nil, nil

local function ShowPageInner(id)
    local s = ConfigState()
    -- An old id that is a tab on another page now lands on that tab.
    local alias = ns.ConfigAliases and ns.ConfigAliases[id]
    if alias then
        if alias[2] then
            s.tabs = s.tabs or {}
            s.tabs[alias[1]] = alias[2]
        end
        id = alias[1]
    end
    local item, parent = FindMenuItem(id)
    if not item then
        item = FindMenuItem("general")
        id = "general"
    end
    -- The page's category opens so the row you are on is in view.
    if parent then s.expanded[parent.id] = true end

    if building then
        -- Asking for the page already being built is what the callback
        -- above does, and the answer is "it is coming" - dropping it is
        -- correct, not a compromise. A request for a DIFFERENT page is a
        -- real navigation, so it runs once this build is off the stack.
        if id ~= building then queuedPage = id end
        return
    end
    building = id
    -- the page declares its preview (if any) while it builds
    if Preview then Preview.BeginPage() end

    -- A REBUILD IS NOT A NAVIGATION.
    -- Pages rebuild constantly - every toggle, every selection, anything
    -- that calls RefreshConfig - and snapping to the top each time throws
    -- you out of whatever you were reading. On a long page that is the
    -- difference between adjusting three settings and hunting for the same
    -- row three times. Switching to a DIFFERENT page still starts at the
    -- top, because there you genuinely are somewhere new.
    local samePage = (scrolledPage == id)
    local keep = samePage and scrolledTo or 0

    -- LEAVING THE AURA PAGE LEAVES EDIT MODE.
    -- Edit mode pauses the engine and pins auras on screen. Tying its exit
    -- only to the window closing meant clicking through to Bags left every
    -- aura frozen on screen with no page in sight explaining why.
    if id ~= "auras" and ns.Auras and ns.Auras.ExitEditMode then
        ns.Auras.ExitEditMode()
    end

    s.selected = id
    ClearContent()

    local fn = item.page and ConfigPages[item.page]
    local layout = ConfigLayout.New(content, 0)
    layout.pageId = id   -- Layout:Tabs keys its remembered tab by this
    layout.live = true   -- the build on screen, not one for the search index
    -- the widgets it asks for come from the pool (UIF_Pool), per page
    if ns.UIPool then ns.UIPool.Begin(content, id) end
    -- A part this game version does not run (Core_Flavor) has no page
    -- in the menu; reached some other way, its page says why instead of
    -- building. A page that keeps working shows only what runs here: a
    -- switched-off feature on it is left out, not explained (General >
    -- Game versions is the one place that lists it).
    local offId = ns.FeatureOffForPage and ns.FeatureOffForPage(id)
    if offId then
        layout:Header(item.label)
        layout:Notice("flavor", ns.FeatureOffNote(offId))
    elseif fn then
        local ok, err = pcall(fn, layout, item)
        if not ok then
            Print("config page '" .. tostring(item.page) .. "' failed: " .. tostring(err))
            layout:Header(item.label, "This page failed to build. The error is in your chat log.")
        end
    elseif item.addon then
        layout:Header(item.label)
        local state, pending = ns.PartState and ns.PartState(item.addon)
        if state == "off" then
            -- one click from here (the sidebar's power button does the same)
            layout:Notice("missing", pending and ("This part of ZacUI turns on at your next reload.")
                or ("This part of ZacUI is off for this character."))
            layout:Card("Turn it on")
            local on = UI.Button(layout.current, "Turn on and reload", { width = 160,
                onClick = function() ns.AskPart(item.addon, item.label, true) end })
            on:SetActive(true)
            layout:Row(on, S.BTN_H)
            layout:EndCard()
        else
            layout:Notice("missing", "This part of ZacUI is not loaded. Enable '" .. item.addon
                .. "' in the AddOns list (character select, or the game menu) and reload.")
        end
    else
        layout:Header(item.label)
        layout:Notice("warn", "Nothing to configure here yet.")
    end

    if ns.UIPool then ns.UIPool.End() end
    -- A page with a preview: its title is pinned at the top with the strip
    -- under it, and the strip is placed (or taken away) before the page is
    -- measured, since it moves the top of the scroll area.
    -- (every page: EllesmereUI's header is never part of the scroll)
    local shift = PinHeader(layout)
    if Preview then
        local ok, err = pcall(Preview.EndPage)
        if not ok then Print("preview: " .. tostring(err)) end
    end

    local h = math.max(1, layout:Height() - shift)
    content:SetHeight(h)
    contentScroll:Recalculate(h)

    -- Clamp: the rebuilt page can be shorter than the one we measured
    -- against, and restoring an offset past its end leaves the view
    -- parked in empty space below the content.
    local _, maxScroll = contentScroll.bar:GetMinMaxValues()
    if keep > (maxScroll or 0) then keep = maxScroll or 0 end
    contentScroll:SetVerticalScroll(keep)
    contentScroll.bar:SetValue(keep)

    scrolledPage, scrolledTo = id, keep

    -- Read the page back for the search: the jump below needs its live
    -- frames, and the index takes the fresh text.
    lastReal = nil
    if Search then
        local ok, entries = pcall(Search.Scan, content, layout, id)
        if ok then
            lastReal = entries
            pcall(Search.Refresh, id, layout, entries)
        end
    end
    -- Track it live, so the next rebuild restores where you actually are
    -- rather than where the last rebuild happened to put you.
    contentScroll.bar:SetScript("OnValueChanged", function(self, v)
        contentScroll:SetVerticalScroll(v)
        if scrolledPage == id then scrolledTo = v end
    end)

    -- Dropped before the nav is drawn, not after: the page itself is
    -- finished here, and holding the flag any longer only widens the
    -- window in which an error somewhere below would leave it stuck on
    -- and the config permanently unable to draw a page.
    building = nil

    BuildNav()

    if queuedPage then
        local q = queuedPage
        queuedPage = nil
        ShowPage(q)
    end
end

-- every build in the settings window's look (UI.S)
ShowPage = function(id)
    local was = UI._zSettings
    UI._zSettings = true
    local ok, err = pcall(ShowPageInner, id)
    UI._zSettings = was
    if not ok then
        building = nil
        error(err, 0)
    end
end

-- ============================================================
-- THE JUMP
-- ============================================================
-- A gold box over the setting a jump landed on, fading out, so the eye
-- finds it after the page has moved under it.
local function Flash(widget)
    local host = widget.GetParent and widget:GetParent()
    if not host then return end
    local f = CreateFrame("Frame", nil, host)
    local isFrame = widget.GetFrameLevel ~= nil
    f:SetFrameLevel(((isFrame and widget or host):GetFrameLevel()) + 4)
    f:SetPoint("TOPLEFT", widget, "TOPLEFT", -5, 4)
    f:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 5, -4)
    UI.Fill(f, "ui", "accent", 0.12)
    UI.Border(f, "ui", "accent")
    f._zPaint = UI.PaintBox
    f:_zPaint()
    local ag = f:CreateAnimationGroup()
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(1.4)
    fade:SetDuration(0.8)
    ag:SetScript("OnFinished", function() f:Hide() end)
    ag:Play()
end

JumpTo = function(r)
    if not r then return end
    local e = r.entry
    local s = ConfigState()
    -- Switch to the tab the setting is on before building the page.
    if e and e.tab then
        s.tabs = s.tabs or {}
        s.tabs[r.item] = e.tab
    end
    if ns.ConfigScrollTop then ns.ConfigScrollTop() end
    ShowPage(r.item)
    if not e or e.kind == "tab" then return end
    -- not on the page as built: folded away as less common (Layout:Fold) -
    -- built again with the page's folds open (they stay open)
    local seen = false
    for _, x in ipairs(lastReal or {}) do if x.key == e.key then seen = true break end end
    if not seen then
        ns._zFoldsOpen = true
        local okShow, errShow = pcall(ShowPage, r.item)
        ns._zFoldsOpen = nil
        if not okShow then error(errShow, 0) end
    end

    -- The fresh build's own entry for this setting, when it is there:
    -- its position is exact and it holds the real frame.
    local target = e
    for _, x in ipairs(lastReal or {}) do
        if x.key == e.key then
            target = x
            break
        end
    end
    -- Land it a little below the top edge, not flush against it.
    local _, maxV = contentScroll.bar:GetMinMaxValues()
    local v = math.max(0, math.min(maxV or 0, -(target.y or 0) - 70))
    contentScroll.bar:SetValue(v)
    contentScroll:SetVerticalScroll(v)
    if target.widget then Flash(target.widget) end
end

-- Escape or the X can close the window with a list still open, and a
-- FULLSCREEN_DIALOG menu outlives its owner happily.
local function OnWindowHide()
    -- folded to its badge (Fold, below): put away, not closed - previews,
    -- Edit Mode and the aura editor keep running
    if window and window._zFolded then return end
    UI.CloseAllDropdowns()
    SearchBox.Hide()
    -- Leaving the config window leaves aura edit mode: the engine resumes,
    -- the fake states clear and the drag handles come off. Without this the
    -- auras stay paused and pinned on screen after the window closes, which
    -- looks exactly like the addon having broken.
    if ns.Auras and ns.Auras.ExitEditMode then ns.Auras.ExitEditMode() end
    -- the profile this character wears picks up what was just changed
    if ns.Profiles and ns.Profiles.WriteBack then pcall(ns.Profiles.WriteBack) end
    -- a look picked but not applied is dropped with the window (Core_Look)
    if ns.Look and ns.Look.Discard then ns.Look.Discard() end
end

-- ============================================================
-- WINDOW
-- ============================================================
-- the scrolled page spans the right side (its 45 px pads hold the bar)
local function ContentWidth()
    return pageW - S.SIDEBAR
end

-- How far across a frame each anchor point sits (0 left, 1 right).
local ANCHOR_X = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5,
    BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }

-- Slides the window left (never right) when a bigger scale has put its
-- right edge off the screen. Measured at the scale the window is
-- settling to.
local function KeepOnScreen()
    if not window or window:GetNumPoints() ~= 1 then return end
    local p, rel, rp, x, y = window:GetPoint(1)
    rel = rel or UIParent
    if rel ~= UIParent then return end
    rp = rp or p
    local us = UIParent:GetEffectiveScale() or 1
    local screenW = (UIParent:GetWidth() or 0) * us
    if screenW <= 0 or not ANCHOR_X[p] or not ANCHOR_X[rp] then return end
    local s = (window._zPopBase or window:GetScale() or 1) * us
    local w = window:GetWidth() or 0
    local left = ANCHOR_X[rp] * screenW + ((x or 0) - ANCHOR_X[p] * w) * s
    local shift = 0
    if left + w * s > screenW + 0.5 then shift = screenW - (left + w * s) end
    if left + shift < 0 then shift = -left end
    if math.abs(shift) < 0.5 then return end
    window:ClearAllPoints()
    window:SetPoint(p, UIParent, rp, (x or 0) + shift / s, y or 0)
end

-- ============================================================
-- PIXEL-EXACT (finish pass; the ZacUI look, through ns.Pixel)
-- ============================================================
-- One unit of this window is (window scale / one physical pixel) screen
-- pixels: 1.055 at 1080p and UI scale 0.75, so its 11 px text and 1 px
-- rules land between pixels. When that is within 10% of a whole number
-- the window's scale is nudged onto it (one unit = exactly 1 or 2 px);
-- further off the size is left as chosen. Either way its top-left corner
-- lands on a whole pixel after an open, a drag, a resize and a scale
-- change. Off under the other looks (ns.Pixel.On), so they are as
-- before.
local function UserScale() return (ZacUIDB and ZacUIDB.config and ZacUIDB.config.scale) or 1 end
local function ExactScale(s)
    local P = ns.Pixel
    if not (P and P.On and P.On() and P.One) then return s end
    local unit = P.One(UIParent)
    if not (type(unit) == "number" and unit > 0) then return s end
    local r = s / unit
    local n = math.floor(r + 0.5)
    if n >= 1 and math.abs(r - n) <= 0.10 * r then return n * unit end
    return s
end
ns.ConfigExactScale = ExactScale

local function SnapWindow()
    local P = ns.Pixel
    if not (window and window:IsShown() and P and P.On and P.On() and P.Snap) then return end
    if window._zAnim then return end
    local left, top = window:GetLeft(), window:GetTop()
    if not (left and top) then return end
    -- (its size stays the whole units you sized it to: at an exact scale
    -- those are whole pixels already, and the saved size never drifts)
    local x, y = P.Snap(left, window), P.Snap(top, window)
    window:ClearAllPoints()
    window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end
ns.ConfigSnapWindow = SnapWindow

-- Config_Preview's way to place its strip (see Preview.Attach): a strip
-- h high under the pinned title (0: none), the scroll area below it.
-- Returns the strip's width (the page's cards' width).
local function PlaceStrip(h)
    if not (head and contentScroll) then return 0 end
    local cw = ContentWidth()
    local sw = cw - 2 * S.PAD
    head:SetWidth(cw)
    local top = stripY
    local dock = Preview and Preview.Frame()
    -- the preview: EllesmereUI's content header - a black 0.10 band the
    -- width of the right side, a white 0.06 hairline at its foot, the
    -- strip 10 in from its top and bottom
    if not headStripBand then
        headStripBand = head:CreateTexture(nil, "BACKGROUND", nil, -6)
        headStripBand._zui_own = true
        headStripBand:SetTexture(FLAT)
        headStripDiv = head:CreateTexture(nil, "ARTWORK")
        headStripDiv._zui_own = true
        headStripDiv:SetTexture(FLAT)
        if ns.Pixel then ns.Pixel.Edge(headStripDiv, "BOTTOM", head) else headStripDiv:SetHeight(1) end
    end
    if h and h > 0 and dock then
        dock:ClearAllPoints()
        dock:SetPoint("TOPLEFT", head, "TOPLEFT", S.PAD, -(stripY + S.TOP_PAD))
        dock:SetWidth(sw)
        top = stripY + S.TOP_PAD + h + S.TOP_PAD
        headStripBand:ClearAllPoints()
        headStripBand:SetPoint("TOPLEFT", head, "TOPLEFT", 0, -stripY)
        headStripBand:SetPoint("TOPRIGHT", head, "TOPRIGHT", 0, -stripY)
        headStripBand:SetHeight(top - stripY)
        headStripBand:SetVertexColor(0, 0, 0, S.HEAD_BAND_A)
        headStripBand:Show()
        headStripDiv:ClearAllPoints()
        headStripDiv:SetPoint("BOTTOMLEFT", head, "TOPLEFT", 0, -top)
        headStripDiv:SetPoint("BOTTOMRIGHT", head, "TOPRIGHT", 0, -top)
        headStripDiv:SetVertexColor(1, 1, 1, S.HEAD_DIV_A)
        headStripDiv:Show()
    else
        headStripBand:Hide()
        headStripDiv:Hide()
    end
    head:SetHeight(math.max(1, top))
    head:SetShown(top > 0)
    contentScroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -top)
    contentScroll.bar:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -6, -4 - top)
    contentScroll:Recalculate(content:GetHeight())
    return sw
end

-- THE WINDOW (match pass 2026-11-07): EllesmereUI's options window built
-- from its numbers (zui_tests/MATCH_OPTIONS_1107.md) - a 295 px sidebar
-- (the ZacUI mark, Edit Mode, the search, the groups), on the right a
-- 138 px header with the page's title, a 40 px tab bar, the preview band,
-- the page, and an 82 px footer (Reload, the window scale, Close).
local function Build()
    -- Class HUDs keep a sidebar row while their part is off (Config_Base)
    if ns.KeepPartRow then pcall(ns.KeepPartRow, "classhuds", "Class HUDs", "Zacui_HUD", "combat") end
    -- a first open: 1300 x 946, no more than 92% of the screen
    local sw0 = (UIParent and UIParent:GetWidth()) or 0
    local sh0 = (UIParent and UIParent:GetHeight()) or 0
    local w0, h0 = WIDTH, HEIGHT
    if sw0 > 0 then w0 = math.max(MIN_W, math.min(w0, math.floor(sw0 * 0.92))) end
    if sh0 > 0 then h0 = math.max(S.MIN_H, math.min(h0, math.floor(sh0 * 0.92))) end
    pageW = w0
    window = UI.Window("ZacUIConfigFrame", w0, h0, "ZacUI", { bare = true })
    local tb = window.titleBar

    -- RESIZABLE, and the size persists (a saved size wins over the
    -- default). The sidebar and the right side are anchored to the
    -- window's edges, so they follow a resize; the page is rebuilt for its
    -- new width when the resize ends.
    do
        local saved = ZacUIDB and ZacUIDB.config
        if saved and saved.w and saved.h then
            pageW = math.min(math.max(saved.w, MIN_W), MAX_W)
            window:SetSize(pageW, math.min(math.max(saved.h, S.MIN_H), S.MAX_H))
        end
        UI.AttachResizeGrip(window, {
            minW = MIN_W, minH = S.MIN_H, maxW = MAX_W, maxH = S.MAX_H,
            onResizeStopped = function(f)
                SnapWindow()
                pageW = math.max(MIN_W, f:GetWidth())
                if f:GetWidth() < MIN_W then f:SetWidth(MIN_W) end
                if f:GetHeight() < S.MIN_H then f:SetHeight(S.MIN_H) end
                ZacUIDB.config = ZacUIDB.config or {}
                ZacUIDB.config.w = math.floor(pageW + 0.5)
                ZacUIDB.config.h = math.floor(f:GetHeight() + 0.5)
                if content then content:SetWidth(ContentWidth()) end
                RefreshConfig()
            end,
        })
        window._zGrip:SetFrameLevel(window:GetFrameLevel() + 40)
    end

    -- THE SIDEBAR
    local nav = CreateFrame("Frame", nil, window)
    nav:SetPoint("TOPLEFT", 0, 0)
    nav:SetPoint("BOTTOMLEFT", 0, 0)
    nav:SetWidth(S.SIDEBAR)
    nav:SetFrameLevel(window:GetFrameLevel() + 3)
    UI.Fill(nav, "sidebar", "bg")
    nav._zPaint = function(self) self._zFill:SetVertexColor(0, 0, 0, S.SIDEBAR_A) end
    nav:_zPaint()
    local rule = nav:CreateTexture(nil, "OVERLAY")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    if ns.Pixel then ns.Pixel.Edge(rule, "RIGHT", nav) else rule:SetWidth(1) end
    rule:SetPoint("TOPRIGHT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetVertexColor(1, 1, 1, S.BORDER_A)

    -- the mark and the name in the sidebar's top 114 (EllesmereUI's logo
    -- band); the mark keeps its opening (UI.AnimateMark)
    local logo = CreateFrame("Frame", nil, nav)
    logo:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, 0)
    logo:SetPoint("TOPRIGHT", nav, "TOPRIGHT", -1, 0)
    logo:SetHeight(S.NAV_TOP)
    logo:EnableMouse(false)
    local mark = logo:CreateTexture(nil, "ARTWORK", nil, 3)
    mark._zui_own = true
    mark:SetSize(40, 40)
    mark:SetPoint("TOPLEFT", logo, "TOPLEFT", 22, -30)
    mark:SetTexture(ns.TEX_ICON)
    if ns.SharpenIcon then ns.SharpenIcon(mark) end
    local first = UI.SFont(logo, 28, { text = "Zac" })
    first:SetPoint("BOTTOMLEFT", mark, "RIGHT", 10, -7)
    first._zPaint = function(self) self:SetTextColor(1, 1, 1, 1) end
    first:_zPaint()
    local second = UI.SFont(logo, 28, { text = "UI" })
    second:SetPoint("LEFT", first, "RIGHT", 0, 0)
    second._zPaint = function(self) local a = GetColor("ui", "accent") self:SetTextColor(a.r, a.g, a.b, 1) end
    second:_zPaint()
    local version = UI.SFont(logo, S.F_VALUE, { text = "v" .. ZUI.VERSION })
    version:SetPoint("TOPLEFT", first, "BOTTOMLEFT", 1, -3)
    version._zPaint = function(self) self:SetTextColor(1, 1, 1, S.DIM_A) end
    version:_zPaint()
    logo._zPaint = function() first:_zPaint() second:_zPaint() version:_zPaint() end
    window.titleText = first
    if UI.AnimateMark then pcall(UI.AnimateMark, mark, logo, { inset = 0 }) end

    -- NEED HELP (2026-11-08): a speech bubble at the band's right, level
    -- with the mark; it opens "Message Zac on Discord" with the name ready
    -- to copy (UIF_Dialogs UI.ShowContact). On the drag surface, as the
    -- window's other buttons are.
    if UI.ContactButton then
        local help = UI.ContactButton(tb, 28)
        -- (the mark is 40 tall from 30 down: 28 centred on it is 36 down)
        help:SetPoint("TOPRIGHT", logo, "TOPRIGHT", -22, -36)
        help:SetFrameLevel(nav:GetFrameLevel() + 5)
        window.contactButton = help
    end

    -- EDIT MODE: the sidebar's one fixed row (EllesmereUI's Unlock Mode
    -- row: 40 tall, a 45 x 32 icon box 20 in, the label 10 after it)
    do
        -- (on the window's drag surface, over the sidebar: the window's
        -- buttons all live there)
        local row = CreateFrame("Button", nil, tb)
        row:SetHeight(S.NAV_ROW)
        row:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, -S.NAV_TOP)
        row:SetPoint("RIGHT", nav, "RIGHT", -1, 0)
        row:SetFrameLevel(nav:GetFrameLevel() + 5)
        local function Tex(layer, sub)
            local t = row:CreateTexture(nil, layer, nil, sub)
            t._zui_own = true
            t:SetTexture(FLAT)
            return t
        end
        local hl = Tex("BACKGROUND", 3) hl:SetAllPoints()
        local glow = Tex("BACKGROUND", 2) glow:SetAllPoints()
        local ind = Tex("ARTWORK", 1) ind:SetWidth(3)
        ind:SetPoint("TOPLEFT") ind:SetPoint("BOTTOMLEFT")
        local icon = row:CreateTexture(nil, "ARTWORK", nil, 2)
        icon._zui_own = true
        icon:SetSize(S.NAV_ICON_H, S.NAV_ICON_H)
        icon:SetPoint("LEFT", row, "LEFT", S.NAV_LEFT + (S.NAV_ICON_W - S.NAV_ICON_H) / 2, 0)
        icon:SetTexture((ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\mode")
        local label = UI.SFont(row, S.F_NAV, { text = "Edit Mode" })
        label:SetPoint("LEFT", row, "LEFT", S.NAV_LEFT + S.NAV_ICON_W + S.NAV_GAP, 0)
        row._zText = label
        row._zPaint = function(self)
            local hot = self._zHot
            hl:SetShown(hot and true or false)
            hl:SetVertexColor(1, 1, 1, S.NAV_HL)
            glow:SetShown(hot and true or false)
            if hot then Grad(glow, S.HOVER_TINT, S.NAV_HOVER_GLOW) end
            ind:SetShown(hot and true or false)
            local h = S.HOVER_TINT
            ind:SetVertexColor(h.r, h.g, h.b, S.NAV_HOVER_IND)
            local a = hot and S.NAV_HOVER or S.NAV_EN
            label:SetTextColor(1, 1, 1, a)
            icon:SetVertexColor(1, 1, 1, a)
        end
        row:SetScript("OnEnter", function(self)
            self._zHot = true
            self:_zPaint()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local t = GetColor("tooltip", "title")
            GameTooltip:AddLine("Edit Mode", t.r, t.g, t.b)
            local c = GetColor("tooltip", "body")
            GameTooltip:AddLine("Show every movable ZacUI element at once over a grid, drag them into place, then lock.",
                c.r, c.g, c.b, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self) self._zHot = nil self:_zPaint() GameTooltip:Hide() end)
        row:SetScript("OnClick", function() if ns.EnterEditMode then ns.EnterEditMode() end end)
        row:_zPaint()
        window.editButton = row
    end

    -- the search box and its dropdown of results (Config_SearchBox); the
    -- jump below opens what is picked
    window.search = SearchBox.Attach(nav, window, { JumpTo = function(r) JumpTo(r) end,
        BuildNav = function() BuildNav() end })
    local listTop = S.NAV_TOP + S.NAV_ROW + S.SB_TOP + S.SB_H + S.SB_BOT

    navScroll, navChild = UI.ScrollArea(nav, { style = "nav" })
    navScroll:SetPoint("TOPLEFT", 0, -listTop)
    navScroll:SetPoint("BOTTOMRIGHT", -1, 12)
    if navScroll.SetClipsChildren then navScroll:SetClipsChildren(true) end
    navChild:SetWidth(S.SIDEBAR - 1)
    navScroll.bar:SetPoint("TOPRIGHT", nav, "TOPRIGHT", (M.SCROLL_W - 3) / 2 - 2, -listTop - 2)
    navScroll.bar:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", (M.SCROLL_W - 3) / 2 - 2, 14)
    navScroll.bar:SetFrameLevel(nav:GetFrameLevel() + 6)

    -- THE RIGHT SIDE: above the footer
    pane = CreateFrame("Frame", nil, window)
    pane:SetPoint("TOPLEFT", nav, "TOPRIGHT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, S.FOOTER)
    pane:SetFrameLevel(window:GetFrameLevel() + 3)

    contentScroll, content = UI.ScrollArea(pane, { style = "settings" })
    contentScroll:SetPoint("TOPLEFT", 0, 0)
    contentScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    if contentScroll.SetClipsChildren then contentScroll:SetClipsChildren(true) end
    content:SetWidth(ContentWidth())
    contentScroll.bar:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -6, -4)
    contentScroll.bar:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -6, 4)

    -- THE PINNED TOP: the page's title, its tabs and its preview, above
    -- the scroll area (PlaceStrip moves the scroll area under it).
    head = CreateFrame("Frame", nil, pane)
    head:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    head:SetSize(ContentWidth(), 1)
    head:SetFrameLevel(pane:GetFrameLevel() + 4)
    head:Hide()
    if Preview then
        Preview.Attach(window, { holder = head, Place = PlaceStrip,
            -- the strip's width (the page's sections'), and the pane's
            -- height (the strip's cap is a share of it)
            Width = function() return ContentWidth() - 2 * S.PAD end,
            PaneHeight = function() return pane:GetHeight() or 0 end })
    end

    -- THE HEADER'S CORNER: fold to a badge, left of the close box (40 x 40
    -- boxes, as EllesmereUI's collapse and close)
    do
        local fold = CreateFrame("Button", nil, tb)
        fold:SetSize(40, 40)
        fold:SetPoint("TOPRIGHT", window, "TOPRIGHT", -(14 + 40 + 4), -11)
        fold:SetFrameLevel(window:GetFrameLevel() + 30)
        local ft = fold:CreateTexture(nil, "ARTWORK")
        ft._zui_own = true
        ft:SetSize(32, 32)
        ft:SetPoint("CENTER")
        ft:SetTexture((ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\collapse")
        fold._zPaint = function(self) ft:SetVertexColor(1, 1, 1, self._zHot and 1 or S.DIM_A) end
        fold:SetScript("OnEnter", function(self) self._zHot = true self:_zPaint() end)
        fold:SetScript("OnLeave", function(self) self._zHot = nil self:_zPaint() GameTooltip:Hide() end)
        fold:SetScript("OnClick", function() ns.ConfigFold() end)
        fold:_zPaint()
        UI.Tooltip(fold, "Fold", "Fold this window to a small badge so you can see the game. Previews and Edit Mode keep "
            .. "running; the badge's + brings it back.")
        window.foldButton = fold
    end

    -- THE FOOTER (82): Reload on the left, Close on the right (EllesmereUI's
    -- 180 / 160 x 36 at 24 in), the window's own scale between them. The
    -- buttons are the window's (on its drag surface), as before.
    do
        local reload = UI.Button(tb, "Reload", { width = S.FOOT_BTN_W, height = S.FOOT_BTN_H, style = "footer",
            tooltip = "/reload - the settings that say they need one.",
            onClick = function() ns.RequestReload() end })
        reload:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", S.SIDEBAR + S.FOOT_PAD, S.FOOT_PAD)
        reload:SetFrameLevel(window:GetFrameLevel() + 20)
        local close = UI.Button(tb, "Close", { width = S.FOOT_CLOSE_W, height = S.FOOT_BTN_H, style = "close",
            onClick = function() UI.CloseWindow(window) end })
        close:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -S.FOOT_PAD, S.FOOT_PAD)
        close:SetFrameLevel(window:GetFrameLevel() + 20)
        window.doneButton = close

        -- THE WINDOW'S SCALE: the window's, not the UI's - a big config on
        -- a 4k screen is a postage stamp, and SetScale on the frame is the
        -- one knob that fixes that without touching anything else.
        -- Persisted with the size.
        local Scale = UserScale
        local function SetScale(v)
            v = math.max(0.6, math.min(1.4, v))
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.scale = v
            window:SetScale(ExactScale(v))
            SnapWindow()
            -- bigger, the window may now run off the right edge
            KeepOnScreen()
            -- the preview keeps its sample at the real, in-game size
            if Preview and Preview.Place then Preview.Place() end
        end
        local plus = UI.Button(tb, "+", { width = S.FOOT_BTN_H, height = S.FOOT_BTN_H, style = "footer",
            onClick = function() SetScale(Scale() + 0.05); window.scaleText:SetText(math.floor(Scale() * 100 + 0.5) .. "%") end })
        plus:SetPoint("RIGHT", close, "LEFT", -20, 0)
        plus:SetFrameLevel(window:GetFrameLevel() + 20)
        local pct = UI.SFont(tb, S.F_VALUE, { text = math.floor(Scale() * 100 + 0.5) .. "%", justify = "CENTER" })
        pct._zPaint = function(self) self:SetTextColor(1, 1, 1, S.DIM_A) end
        pct:_zPaint()
        pct:SetWidth(52)
        pct:SetPoint("RIGHT", plus, "LEFT", 0, 0)
        window.scaleText = pct
        local minus = UI.Button(tb, "-", { width = S.FOOT_BTN_H, height = S.FOOT_BTN_H, style = "footer",
            onClick = function() SetScale(Scale() - 0.05); window.scaleText:SetText(math.floor(Scale() * 100 + 0.5) .. "%") end })
        minus:SetPoint("RIGHT", pct, "LEFT", 0, 0)
        minus:SetFrameLevel(window:GetFrameLevel() + 20)
        UI.Tooltip(pct, "Window scale", "Grows or shrinks this window only. Under the ZacUI look a size "
            .. "close to whole screen pixels is nudged onto them, so text and lines stay sharp.")
        window:SetScale(ExactScale(Scale()))
    end

    window.nav, window.content = nav, content
    -- ShowPage ends by rebuilding the nav, so calling BuildNav here too
    -- would build it twice on every open.
    window:SetScript("OnShow", function()
        -- A fresh open starts unfiltered; a stale search from last time
        -- would hide most of the sidebar for no visible reason.
        SearchBox.Reset()
        ShowPage(ConfigState().selected)
    end)
    window:HookScript("OnHide", OnWindowHide)
    -- whole pixels once it has settled after an open (the pop-in scales
    -- it), and after a drag; then the window's one-time hints, pointing
    -- at what they are about (Tutorial_Hints, UI.Callout)
    window:HookScript("OnShow", function()
        -- opened another way while folded: the badge goes
        if badge and badge:IsShown() then badge._zUnfolding = true badge:Hide() end
        window._zFolded = nil
        WatchFights()
        if Opacity() < 1 then C_Timer.After(0.2, ApplyOpacity) end
        C_Timer.After(0.3, SnapWindow)
        C_Timer.After(0.6, function()
            local H = ns.Hints
            if not (H and H.Callout and window:IsShown()) then return end
            if ns.Tutorial and ns.Tutorial.TourActive and ns.Tutorial.TourActive() then return end
            if InCombatLockdown and InCombatLockdown() then return end
            H.Callout("cfg_editmode", window.editButton,
                "Edit Mode shows every ZacUI frame at once over a grid. Drag them where you want them.", "RIGHT")
            for _, row in ipairs(rowPool) do
                if row:IsShown() and row._zPower and row._zPower:IsShown() then
                    H.Callout("cfg_power", row._zPower, "Each part has its own switch. Off means not loaded at all, "
                        .. "and it asks before the reload.", "RIGHT")
                    break
                end
            end
        end)
    end)
    window._zOnMoved = SnapWindow
    return window
end

-- ============================================================
-- WINDOW COMFORTS (finish pass)
-- ============================================================
-- Fold to a badge, an opacity, and what it does when a fight starts.
-- Window state (ZacUIDB.config: opacity, combat), nil = as before: fully
-- opaque, and it stays as it is in a fight.
local function Cfg()
    ZacUIDB.config = ZacUIDB.config or {}
    return ZacUIDB.config
end
Opacity = function()
    local o = tonumber(ZacUIDB and ZacUIDB.config and ZacUIDB.config.opacity)
    return o and math.max(0.5, math.min(1, o)) or 1
end
ApplyOpacity = function()
    if not (window and window:IsShown()) or window._zAnim or window._zFightFaded then return end
    local op = Opacity()
    if math.abs((window:GetAlpha() or 1) - op) < 0.005 then return end
    if ns.Motion and ns.Motion.FadeTo then ns.Motion.FadeTo(window, op, { style = "fade", duration = 0.15 })
    else window:SetAlpha(op) end
end
ns.ConfigApplyOpacity = ApplyOpacity

-- a point on screen in another frame's units
local function Into(v, from, to)
    return v * (from:GetEffectiveScale() or 1) / (to:GetEffectiveScale() or 1)
end

local function BuildBadge()
    local b = CreateFrame("Frame", "ZacUIConfigBadge", UIParent)
    b:SetSize(150, 30)
    b:SetFrameStrata("DIALOG")
    b:SetToplevel(true)
    b:SetClampedToScreen(true)
    b:EnableMouse(true)
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", b.StartMoving)
    b:SetScript("OnDragStop", b.StopMovingOrSizing)
    UI.Fill(b, "ui", "headerBg")
    UI.Border(b, "ui", "border")
    b._zPaint = UI.PaintBox
    b:_zPaint()
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon._zui_own = true
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 9, 0)
    icon:SetTexture(ns.TEX_ICON)
    local label = UI.Font(b, F.TITLE, { text = "ZacUI", cat = "text", key = "gold" })
    label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    local close = UI.CloseX(b, 22, function() ns.ConfigUnfold(true) end)
    close:SetPoint("RIGHT", -4, 0)
    local open = UI.Button(b, "", { width = 20, height = 20, tooltip = "Back to the settings window.",
        onClick = function() ns.ConfigUnfold() end })
    local ot = open:CreateTexture(nil, "ARTWORK")
    ot._zui_own = true
    ot:SetSize(14, 14)
    ot:SetPoint("CENTER")
    ot:SetTexture((ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\expand")
    open:SetPoint("RIGHT", close, "LEFT", -4, 0)
    b.open, b.close = open, close
    if UISpecialFrames then tinsert(UISpecialFrames, "ZacUIConfigBadge") end
    -- Escape on the badge closes the window for real
    b:SetScript("OnHide", function(self)
        if window and window._zFolded and not self._zUnfolding then
            window._zFolded = nil
            OnWindowHide()
        end
        self._zUnfolding = nil
    end)
    b:Hide()
    badge = b
    return b
end

function ns.ConfigFold()
    if not (window and window:IsShown()) or window._zFolded then return false end
    local b = badge or BuildBadge()
    local left, top = window:GetLeft(), window:GetTop()
    if left and top then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", Into(left, window, UIParent), Into(top, window, UIParent))
    end
    window._zFolded = true
    if ns.StopAnim then ns.StopAnim(window) end
    window:Hide()
    b:Show()
    return true
end

-- back: the window where the badge is now; closeIt = the badge's X (the
-- window closes for real)
function ns.ConfigUnfold(closeIt)
    if not (badge and badge:IsShown()) then return false end
    local left, top = badge:GetLeft(), badge:GetTop()
    badge._zUnfolding = not closeIt
    if closeIt then
        badge:Hide()
        return true
    end
    badge:Hide()
    if window and left and top then
        window:ClearAllPoints()
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", Into(left, UIParent, window), Into(top, UIParent, window))
    end
    if window then window._zFolded = nil end
    ns.OpenConfig()
    return true
end

function ns.ConfigFolded() return window ~= nil and window._zFolded == true end

-- a fight: fade it out, or close it (Cfg().combat); made with the window
WatchFights = function()
    if fightWatch then return end
    fightWatch = CreateFrame("Frame")
    fightWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
    fightWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
    fightWatch:SetScript("OnEvent", function(_, event)
        if not window then return end
        local rule = ZacUIDB and ZacUIDB.config and ZacUIDB.config.combat
        if event == "PLAYER_REGEN_DISABLED" then
            if not window:IsShown() then return end
            if rule == "close" then
                window:Hide()
                if Print then Print("Settings closed for the fight - /zui opens them again.") end
            elseif rule == "fade" then
                window._zFightFaded = true
                if ns.Motion and ns.Motion.FadeTo then ns.Motion.FadeTo(window, 0.25, { style = "fade", duration = 0.2 })
                else window:SetAlpha(0.25) end
            end
        elseif window._zFightFaded then
            window._zFightFaded = nil
            if window:IsShown() then
                if ns.Motion and ns.Motion.FadeTo then ns.Motion.FadeTo(window, Opacity(), { style = "fade", duration = 0.2 })
                else window:SetAlpha(Opacity()) end
            end
        end
    end)
end

-- General > Overview's card for this window
function ns.ConfigWindowCard(L)
    L:Card("This window")
    local pctOf = function(v) return math.floor(v * 100 + 0.5) end
    local sl = UI.Slider(L.current, { width = 200, min = 50, max = 100, step = 5, label = "Opacity",
        value = pctOf(Opacity()), format = function(v) return v .. "%" end,
        onChange = function(v)
            Cfg().opacity = (v < 100) and (v / 100) or nil
            ApplyOpacity()
        end })
    L:Row(sl, 40)
    local RULES = { { text = "Stay as it is", value = "stay" }, { text = "Fade it out", value = "fade" },
        { text = "Close it", value = "close" } }
    local function RuleText(v)
        for _, r in ipairs(RULES) do if r.value == v then return r.text end end
        return RULES[1].text
    end
    local dd = UI.Field(L.current, "In a fight", function(h)
        return UI.Dropdown(h, { width = 200, items = function() return RULES end,
            selected = function() return RuleText(Cfg().combat or "stay") end,
            selectedValue = function() return Cfg().combat or "stay" end,
            onSelect = function(v) Cfg().combat = (v ~= "stay") and v or nil end })
    end, { width = 200 })
    L:Add(dd, 8)
    L:Desc("Fade it out: down to a quarter until the fight ends. The - beside the window scale folds it to a "
        .. "small badge any time.")
    L:EndCard()
end

local function OpenConfig(pageId)
    if not window then UI.SettingsBuild(Build) end
    if pageId then ConfigState().selected = pageId end
    if window:IsShown() then
        if pageId then ShowPage(pageId) end
        return
    end
    -- the UI scale may have changed since: the exact scale again
    if not window._zAnim then window:SetScale(ExactScale(UserScale())) end
    UI.OpenWindow(window)
end

-- Live restyle. Anything ZacUI BUILT can repaint in place; anything it
-- STRIPPED off a Blizzard frame cannot, because there is no un-strip.
-- The colour page says so plainly rather than pretending otherwise.
RefreshConfig = function()
    if not window then return end
    -- A HIDDEN WINDOW DOES NOT REBUILD. Rebuilding runs the page builder,
    -- and the aura page's builder ENTERS EDIT MODE - pauses the engine,
    -- fakes every trigger, pins the selection on screen. Doing that with
    -- no window open is precisely how auras end up stuck on the world with
    -- nothing to explain them and nothing to close. Anything that refreshes
    -- after the close (a dialog's OnHide, a deferred callback) now lands
    -- here and stops; the next open builds fresh anyway.
    if not window:IsShown() then return end
    UI.Repaint(window)
    BuildNav()
    ShowPage(ConfigState().selected)
end

-- Published so the pages can ask, rather than guess from the selected id
-- - which persists across a close and says nothing about visibility.
ns.ConfigIsOpen = function()
    return window ~= nil and window:IsShown()
end

-- The minimap button's left click: open, or close if it is up.
ns.ToggleConfig = function()
    if window and window:IsShown() then
        UI.CloseWindow(window)
    else
        OpenConfig()
    end
end

-- Forget the kept scroll offset, so the next rebuild of the SAME page
-- starts at the top. A tab switch inside a page is a navigation in all
-- but the page id, and landing three screens down a new tab is worse
-- than the rebuild jump this offset exists to prevent.
ns.ConfigScrollTop = function()
    scrolledPage, scrolledTo = nil, 0
end

-- shared with later ZacUI files
ns.OpenConfig = OpenConfig
ns.RefreshConfig = RefreshConfig
