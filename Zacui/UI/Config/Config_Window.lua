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
local Preview = ns.ConfigPreview

local M, F = UI.M, UI.F

local WIDTH, HEIGHT = 780, 560
local MIN_W, MAX_W = 640, 1600

local window, navScroll, navChild, content, contentScroll, pane
-- head: the pinned top of the content pane (the page's title and the
-- preview strip), shown only on a page with a preview.
local head, pinnedHeader
local stripY = 8      -- where the strip starts in head (under the title)
local pageW = WIDTH   -- the window's width, as you sized it
local rowPool = {}

-- SEARCH STATE. searchMode: the content pane is showing results rather
-- than a page. lastReal: what the page on screen contains (with live
-- widgets), read back after every build, so a jump can find the exact
-- frame to scroll to and flash.
local searchMode = false
local lastQuery, lastResults, lastHits = "", {}, {}
local lastReal
local JumpTo, ShowResults

-- ============================================================
-- NAV ROWS
-- ============================================================
local function PaintRow(self)
    local key = "rowNormal"
    if self._zSelected then
        key = "rowSelected"
    elseif self._zHot then
        key = "rowHover"
    end
    local c = GetColor("sidebar", key)
    self._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1)
    local b = GetColor("ui", "border")
    for _, t in ipairs(self._zBorder) do t:SetVertexColor(b.r, b.g, b.b, 1) end

    local ind = GetColor("sidebar", "indicator")
    self._zInd:SetVertexColor(ind.r, ind.g, ind.b, self._zSelected and 1 or 0)

    local tc = self._zSelected and GetColor("text", "green") or GetColor("text", "normal")
    self._zText:SetTextColor(tc.r, tc.g, tc.b, 1)
    if self._zChevron then
        local a = GetColor("ui", "accent")
        self._zChevron:SetVertexColor(a.r, a.g, a.b, self._zHot and 1 or 0.65)
    end
end

local function AcquireRow(index)
    local row = rowPool[index]
    if row then return row end
    row = CreateFrame("Button", nil, navChild)
    row:SetHeight(M.ROW_H)
    UI.Fill(row, "sidebar", "rowNormal")
    UI.Border(row, "ui", "border")

    local ind = row:CreateTexture(nil, "ARTWORK")
    ind:SetTexture(FLAT)
    ind:SetWidth(3)
    ind:SetPoint("TOPLEFT", 1, -1)
    ind:SetPoint("BOTTOMLEFT", 1, 1)
    row._zInd = ind

    row._zText = UI.Font(row, F.NAV, { justify = "LEFT" })
    row._zText:SetWordWrap(false)

    -- The chevron only exists on category rows, but building it for every
    -- row and hiding it keeps the pool homogeneous - a pool where entry 3
    -- has fields entry 4 lacks is how recycled rows end up half-dressed.
    local chev = row:CreateTexture(nil, "ARTWORK")
    chev:SetSize(8, 8)
    chev:SetPoint("RIGHT", -8, 0)
    chev:SetTexture(ns.TEX_ARROW)
    row._zChevron = chev

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
    stripY = 8
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

local function PinHeader(layout)
    local hf = layout and layout.headerFrame
    if not (hf and hf:GetParent() == content) then
        stripY = 8
        return 0
    end
    local _, _, _, _, hy = hf:GetPoint(1)
    hy = hy or -14
    -- only the page's own title at its top, not a heading further down
    if hy < -30 then
        stripY = 8
        return 0
    end
    for _, list in ipairs({ { content:GetChildren() }, { content:GetRegions() } }) do
        for _, o in ipairs(list) do
            if o ~= hf and o:IsShown() and (o.GetNumPoints and o:GetNumPoints() or 0) > 0 then
                local _, rel, rp, _, y = o:GetPoint(1)
                if (rel == nil or rel == content) and rp and rp:find("TOP") and (y or 0) > hy + 0.5 then
                    stripY = 8
                    return 0
                end
            end
        end
    end
    local hh = hf:GetHeight() or 30
    hf:SetParent(head)
    hf:ClearAllPoints()
    hf:SetPoint("TOPLEFT", head, "TOPLEFT", M.MARGIN, hy)
    hf:SetPoint("RIGHT", head, "RIGHT", -M.MARGIN, 0)
    hf:Show()
    pinnedHeader = hf
    stripY = -hy + hh + 10
    -- the page went on 12 under the title; its first card now sits 6 down
    local shift = -hy + hh + 6
    for _, child in ipairs({ content:GetChildren() }) do ShiftUp(child, shift) end
    for _, region in ipairs({ content:GetRegions() }) do ShiftUp(region, shift) end
    return shift
end

local ShowPage
-- Forward declared: Build's resize callback closes over it, and Build is
-- written above the definition. A local declared later is a DIFFERENT
-- variable, so without this the callback captures a global nil and the
-- window silently stops refreshing after a resize.
local RefreshConfig

local function BuildNav()
    local s = ConfigState()
    local filter = window and window.search and window.search:GetText() or ""
    local searching = filter:find("%S") ~= nil
    local rows = VisibleRows(filter, searching and lastHits or nil)
    local y = -4

    for i, entry in ipairs(rows) do
        local item, row = entry.item, AcquireRow(i)
        local indent = entry.isChild and 14 or 4
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", navChild, "TOPLEFT", indent, y)
        row:SetPoint("RIGHT", navChild, "RIGHT", -4, 0)

        -- a page whose part this game version does not run is marked
        local label = item.label
        if ns.FeatureOffForPage and ns.FeatureOffForPage(item.id) then
            local g = GetColor("text", "gray")
            label = label .. string.format("  |cff%02x%02x%02xoff|r",
                math.floor(g.r * 255 + 0.5), math.floor(g.g * 255 + 0.5), math.floor(g.b * 255 + 0.5))
        end
        row._zText:SetText(label)
        row._zText:ClearAllPoints()
        row._zText:SetPoint("LEFT", entry.isChild and 10 or 9, 0)
        row._zText:SetPoint("RIGHT", -20, 0)

        row._zSelected = (s.selected == item.id)
        row._zChevron:SetShown(entry.isCategory and true or false)
        if entry.isCategory then
            -- Down when open, right when closed. The addon ships a down
            -- arrow and a left arrow; the right-pointing one is the left
            -- arrow mirrored on X, which is why the texcoord is reset on
            -- the open branch - leaving a stale mirror flips the down
            -- arrow too.
            if s.expanded[item.id] then
                row._zChevron:SetTexture(ns.TEX_ARROW)
                row._zChevron:SetTexCoord(0, 1, 0, 1)
            else
                row._zChevron:SetTexture(ns.TEX_ARROWL)
                row._zChevron:SetTexCoord(1, 0, 0, 1)
            end
        end

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
                for _, r in ipairs(lastResults) do
                    if r.item == item.id then
                        JumpTo(r)
                        return
                    end
                end
            end
            ShowPage(item.id)
        end)
        row:Show()
        row:_zPaint()
        y = y - M.ROW_H - 2
    end

    for i = #rows + 1, #rowPool do rowPool[i]:Hide() end
    navChild:SetHeight(math.max(1, -y + 8))
    navScroll:Recalculate(-y + 8)
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

ShowPage = function(id)
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
    searchMode = false
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
    local layout = ConfigLayout.New(content, -14)
    layout.pageId = id   -- Layout:Tabs keys its remembered tab by this
    layout.live = true   -- the build on screen, not one for the search index
    -- the widgets it asks for come from the pool (UIF_Pool), per page
    if ns.UIPool then ns.UIPool.Begin(content, id) end
    -- A part or feature this game version does not run (Core_Flavor):
    -- its page says why instead of building; a page that keeps working
    -- says which of its features are off, under its title.
    local offId = ns.FeatureOffForPage and ns.FeatureOffForPage(id)
    if not offId and ns.FlavorPageNotes then layout.flavorNotes = ns.FlavorPageNotes(id) end
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
        layout:Notice("missing", "This part of ZacUI is not loaded. Enable '" .. item.addon
            .. "' in the AddOns list (character select, or the game menu) and reload.")
    else
        layout:Header(item.label)
        layout:Notice("warn", "Nothing to configure here yet.")
    end

    if ns.UIPool then ns.UIPool.End() end
    -- A page with a preview: its title is pinned at the top with the strip
    -- under it, and the strip is placed (or taken away) before the page is
    -- measured, since it moves the top of the scroll area.
    local shift = 0
    if Preview and Preview.Declared() then shift = PinHeader(layout) end
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

-- ============================================================
-- SEARCH RESULTS
-- ============================================================
local MAX_RESULTS = 60

local function AccentHex()
    local a = GetColor("ui", "accent")
    return string.format("%02x%02x%02x", math.floor(a.r * 255 + 0.5),
        math.floor(a.g * 255 + 0.5), math.floor(a.b * 255 + 0.5))
end

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

local function ResultRow(card, r, query, hex)
    local b = CreateFrame("Button", nil, card)
    b:SetHeight(24)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl._zui_own = true
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    hl:SetBlendMode("ADD")

    local e = r.entry
    local where
    if r.kind == "page" then
        where = "open page"
    elseif r.kind == "tab" then
        where = "tab"
    else
        local bits = {}
        if e and e.tabLabel then bits[#bits + 1] = e.tabLabel end
        if e and e.card and r.kind ~= "card" then bits[#bits + 1] = e.card end
        if r.kind == "card" then bits[#bits + 1] = "section" end
        if r.kind == "desc" then bits[#bits + 1] = "in its description" end
        if r.kind == "tip" then bits[#bits + 1] = "in its tooltip" end
        where = table.concat(bits, "  >  ")
    end

    local crumb = UI.Font(b, F.SMALL, { text = where, cat = "text", key = "gray", justify = "RIGHT" })
    crumb:SetPoint("RIGHT", -8, 0)
    crumb:SetWordWrap(false)
    local label = UI.Font(b, F.LABEL, { justify = "LEFT" })
    label:SetPoint("LEFT", 8, 0)
    label:SetPoint("RIGHT", crumb, "LEFT", -12, 0)
    label:SetWordWrap(false)
    label:SetText(Search.Highlight(r.label or "", query, hex))

    if (r.kind == "desc" or r.kind == "tip") and e and e.text then
        UI.Tooltip(b, r.label, e.text)
    end
    b:SetScript("OnClick", function() JumpTo(r) end)
    return b
end

ShowResults = function(query)
    if not window or building then return end
    searchMode = true
    if ns.Auras and ns.Auras.ExitEditMode then ns.Auras.ExitEditMode() end
    ClearContent()
    -- results are not a page: no preview
    if Preview then Preview.BeginPage() pcall(Preview.EndPage) end
    local layout = ConfigLayout.New(content, -14)
    local n = #lastResults
    local indexing = Search.IsIndexing()
    local sub
    if n == 0 then
        sub = indexing and "Still reading the pages - results appear as they come in."
            or "Nothing matches. Try fewer words, or the start of a word."
    else
        sub = n .. (n == 1 and " match" or " matches")
            .. ". Click one to go straight to it - Enter opens the top one."
            .. (indexing and " Still reading pages..." or "")
    end
    layout:Header("Search: " .. query, sub)

    -- Grouped by page, pages in the order of their best match.
    local groups, order = {}, {}
    for i, r in ipairs(lastResults) do
        if i > MAX_RESULTS then break end
        local g = groups[r.item]
        if not g then
            g = { title = r.parent and (r.parent .. "  >  " .. r.page) or r.page, list = {} }
            groups[r.item] = g
            order[#order + 1] = g
        end
        g.list[#g.list + 1] = r
    end
    local hex = AccentHex()
    for _, g in ipairs(order) do
        layout:Card(g.title)
        for _, r in ipairs(g.list) do
            local row = ResultRow(layout.current, r, query, hex)
            layout:Row(row, 25, 6)
            row:SetPoint("RIGHT", layout.current, "RIGHT", -6, 0)
        end
        layout:EndCard()
    end
    if n > MAX_RESULTS then
        layout:Card(nil)
        layout:Desc("Showing the best " .. MAX_RESULTS .. ". Add another word to narrow it down.")
        layout:EndCard()
    end

    local h = layout:Height()
    content:SetHeight(h)
    contentScroll:Recalculate(h)
    contentScroll.bar:SetScript("OnValueChanged", function(_, v)
        contentScroll:SetVerticalScroll(v)
    end)
    contentScroll.bar:SetValue(0)
    contentScroll:SetVerticalScroll(0)
    scrolledPage, scrolledTo = nil, 0
    BuildNav()
end

local function RunSearch(text)
    lastQuery = text or ""
    lastResults, lastHits = Search.Run(lastQuery)
end

-- The index fills in over a few frames; once it is complete, redraw
-- whatever is showing so partial results become whole.
local function OnIndexed()
    if not window or not window:IsShown() then return end
    local text = window.search:GetText() or ""
    if not text:find("%S") then return end
    RunSearch(text)
    if searchMode then ShowResults(text) else BuildNav() end
end

-- Typing waits a beat before searching, so a fast word is one search,
-- not six half-word redraws.
local searchSerial = 0
local function OnSearchChanged()
    searchSerial = searchSerial + 1
    local mine = searchSerial
    C_Timer.After(0.12, function()
        if mine ~= searchSerial or not window or not window:IsShown() then return end
        local text = window.search:GetText() or ""
        if not text:find("%S") then
            lastQuery, lastResults, lastHits = "", {}, {}
            if searchMode then
                ShowPage(ConfigState().selected)
            else
                BuildNav()
            end
            return
        end
        Search.EnsureIndex(OnIndexed)
        RunSearch(text)
        ShowResults(text)
    end)
end

local function OnSearchEnter(text)
    if not (text or ""):find("%S") then return end
    searchSerial = searchSerial + 1   -- a pending redraw would undo the jump
    Search.EnsureIndex(OnIndexed)
    RunSearch(text)
    if lastResults[1] then JumpTo(lastResults[1]) else ShowResults(text) end
end

-- Escape or the X can close the window with a list still open, and a
-- FULLSCREEN_DIALOG menu outlives its owner happily.
local function OnWindowHide()
    UI.CloseAllDropdowns()
    -- Leaving the config window leaves aura edit mode: the engine resumes,
    -- the fake states clear and the drag handles come off. Without this the
    -- auras stay paused and pinned on screen after the window closes, which
    -- looks exactly like the addon having broken.
    if ns.Auras and ns.Auras.ExitEditMode then ns.Auras.ExitEditMode() end
    -- the profile this character wears picks up what was just changed
    if ns.Profiles and ns.Profiles.WriteBack then pcall(ns.Profiles.WriteBack) end
end

-- ============================================================
-- WINDOW
-- ============================================================
local function ContentWidth()
    return pageW - M.SIDEBAR_W - M.SCROLL_W - 8
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

-- Config_Preview's way to place its strip (see Preview.Attach): a strip
-- h high under the pinned title (0: none), the scroll area below it.
-- Returns the strip's width (the page's cards' width).
local function PlaceStrip(h)
    if not (head and contentScroll) then return 0 end
    local cw = ContentWidth()
    local sw = cw - 2 * M.MARGIN
    head:SetWidth(cw)
    local top = 0
    local dock = Preview and Preview.Frame()
    if h and h > 0 and dock then
        dock:ClearAllPoints()
        dock:SetPoint("TOPLEFT", head, "TOPLEFT", M.MARGIN, -stripY)
        dock:SetWidth(sw)
        top = stripY + h + 8
    elseif pinnedHeader then
        -- (a strip that failed to come up: the title alone)
        top = stripY
    end
    head:SetHeight(math.max(1, top))
    head:SetShown(top > 0)
    contentScroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -top)
    contentScroll.bar:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -2, -4 - top)
    contentScroll:Recalculate(content:GetHeight())
    return sw
end

local function Build()
    window = UI.Window("ZacUIConfigFrame", WIDTH, HEIGHT, "ZacUI",
        { hero = { first = "Zac", second = "UI", version = "v" .. ZUI.VERSION,
                   stepX = M.SIDEBAR_W, left = { "sidebar", "bg" } } })

    -- RESIZABLE, and the size persists. The aura tree in particular wants
    -- more room than a fixed 780x560 gives it, and a window that forgets
    -- how big you made it is a window you resize every session.
    --
    -- The nav column and content pane are anchored to the window's edges
    -- rather than sized, so they follow a resize on their own; only the
    -- content's scroll child needs its width recomputed, which is what the
    -- callback does.
    --
    -- The saved width is the window's (it never changes for a preview;
    -- the column the preview used to be never counted towards it).
    do
        local saved = ZacUIDB and ZacUIDB.config
        if saved and saved.w and saved.h then
            pageW = math.min(math.max(saved.w, MIN_W), MAX_W)
            window:SetSize(pageW, math.max(saved.h, 420))
        end
        UI.AttachResizeGrip(window, {
            minW = MIN_W, minH = 420, maxW = MAX_W, maxH = 1100,
            onResizeStopped = function(f)
                pageW = math.max(MIN_W, f:GetWidth())
                ZacUIDB.config = ZacUIDB.config or {}
                ZacUIDB.config.w = math.floor(pageW + 0.5)
                ZacUIDB.config.h = math.floor(f:GetHeight() + 0.5)
                if content then content:SetWidth(ContentWidth()) end
                RefreshConfig()
            end,
        })
    end

    -- NAV COLUMN
    local nav = CreateFrame("Frame", nil, window)
    nav:SetPoint("TOPLEFT", 1, -(window.headerHeight + 1))
    nav:SetPoint("BOTTOMLEFT", 1, 1)
    nav:SetWidth(M.SIDEBAR_W)
    UI.Fill(nav, "sidebar", "bg")
    nav._zPaint = UI.PaintBox
    nav:_zPaint()

    local rule = nav:CreateTexture(nil, "OVERLAY")
    rule:SetTexture(FLAT)
    rule:SetWidth(1)
    rule:SetPoint("TOPRIGHT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetVertexColor(0, 0, 0, 1)

    window.search = UI.EditBox(nav, { width = M.SIDEBAR_W - 12, height = 21,
        hint = "Search settings", onChange = OnSearchChanged, onEnter = OnSearchEnter })
    window.search:SetPoint("TOPLEFT", 6, -6)
    window.search.editBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        OnSearchChanged()
    end)
    -- Reading the pages starts the moment the box is clicked, so by the
    -- time a word is typed most of the index is already there.
    window.search.editBox:HookScript("OnEditFocusGained", function()
        Search.EnsureIndex(OnIndexed)
    end)

    navScroll, navChild = UI.ScrollArea(nav)
    navScroll:SetPoint("TOPLEFT", 0, -32)
    navScroll:SetPoint("BOTTOMRIGHT", -M.SCROLL_W, 4)
    navChild:SetWidth(M.SIDEBAR_W - M.SCROLL_W)
    navScroll.bar:SetPoint("TOPRIGHT", nav, "TOPRIGHT", -2, -32)
    navScroll.bar:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -2, 4)

    -- CONTENT COLUMN
    pane = CreateFrame("Frame", nil, window)
    pane:SetPoint("TOPLEFT", nav, "TOPRIGHT", 1, 0)
    pane:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -1, 1)

    contentScroll, content = UI.ScrollArea(pane)
    contentScroll:SetPoint("TOPLEFT", 0, 0)
    contentScroll:SetPoint("BOTTOMRIGHT", -M.SCROLL_W - 2, 0)
    content:SetWidth(ContentWidth())
    contentScroll.bar:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -2, -4)
    contentScroll.bar:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -2, 4)

    -- THE PINNED TOP: the title of a page with a preview and its strip,
    -- above the scroll area (PlaceStrip moves the scroll area under it).
    head = CreateFrame("Frame", nil, pane)
    head:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    head:SetSize(ContentWidth(), 1)
    head:Hide()
    if Preview then
        Preview.Attach(window, { holder = head, Place = PlaceStrip,
            -- the strip's width (the page's cards'), and the pane's height
            -- (the strip's cap is a share of it)
            Width = function() return ContentWidth() - 2 * M.MARGIN end,
            PaneHeight = function() return pane:GetHeight() or 0 end })
    end

    -- TITLE BAR TOOLS, right of the title, left of the X: Edit Mode
    -- (every placeholder at once, see UIF_EditMode), a reload, and the
    -- window's own scale. The scale is the window's, not the UI's - a
    -- 780px config on a 4k screen is a postage stamp, and SetScale on the
    -- frame is the one knob that fixes that without touching anything
    -- else. Persisted with the size.
    do
        local tb = window.titleBar
        local edit = UI.Button(tb, "Edit Mode", { width = 78, height = 20,
            tooltip = "Show every movable ZacUI element at once over a "
                .. "grid, drag them into place, then lock.",
            onClick = function()
                if ns.EnterEditMode then ns.EnterEditMode() end
            end })
        edit:SetPoint("RIGHT", window.closeButton, "LEFT", -10, 0)
        local reload = UI.Button(tb, "Reload", { width = 60, height = 20,
            tooltip = "/reload - the settings that say they need one.",
            onClick = function() ReloadUI() end })
        reload:SetPoint("RIGHT", edit, "LEFT", -6, 0)

        local function Scale() return (ZacUIDB.config and ZacUIDB.config.scale) or 1 end
        local function SetScale(v)
            v = math.max(0.6, math.min(1.4, v))
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.scale = v
            window:SetScale(v)
            -- bigger, the window may now run off the right edge
            KeepOnScreen()
            -- the preview keeps its sample at the real, in-game size
            if Preview and Preview.Place then Preview.Place() end
        end
        local plus = UI.Button(tb, "+", { width = 20, height = 20,
            onClick = function() SetScale(Scale() + 0.05); window.scaleText:SetText(math.floor(Scale() * 100 + 0.5) .. "%") end })
        plus:SetPoint("RIGHT", reload, "LEFT", -12, 0)
        local pct = UI.Font(tb, F.SMALL, { text = math.floor(Scale() * 100 + 0.5) .. "%",
            justify = "CENTER", cat = "text", key = "gray" })
        pct:SetWidth(34)
        pct:SetPoint("RIGHT", plus, "LEFT", -2, 0)
        window.scaleText = pct
        local minus = UI.Button(tb, "-", { width = 20, height = 20,
            onClick = function() SetScale(Scale() - 0.05); window.scaleText:SetText(math.floor(Scale() * 100 + 0.5) .. "%") end })
        minus:SetPoint("RIGHT", pct, "LEFT", -2, 0)
        UI.Tooltip(pct, "Window scale", "Grows or shrinks this window only.")
        window:SetScale(Scale())
    end

    window.nav, window.content = nav, content
    -- ShowPage ends by rebuilding the nav, so calling BuildNav here too
    -- would build it twice on every open.
    window:SetScript("OnShow", function()
        -- A fresh open starts unfiltered; a stale search from last time
        -- would hide most of the sidebar for no visible reason.
        searchSerial = searchSerial + 1
        window.search:SetText("")
        lastQuery, lastResults, lastHits = "", {}, {}
        ShowPage(ConfigState().selected)
    end)
    window:HookScript("OnHide", OnWindowHide)
    return window
end

local function OpenConfig(pageId)
    if not window then Build() end
    if pageId then ConfigState().selected = pageId end
    if window:IsShown() then
        if pageId then ShowPage(pageId) end
        return
    end
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
    if searchMode and lastQuery:find("%S") then
        RunSearch(lastQuery)
        ShowResults(lastQuery)
        return
    end
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
