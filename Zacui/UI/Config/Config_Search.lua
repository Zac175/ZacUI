-- Config_Search - the settings search behind the config window's search
-- box: an index of every setting on every page, and the ranking.
-- Part of ZacUI; load order is set by the TOC (after Config_Base, before
-- Config_Window, which draws the results and does the jumping).
--
-- WHY AN INDEX. The old search only matched page names and a hand-kept
-- keyword list, so most settings could not be found at all - typing the
-- exact label of a checkbox found nothing unless someone had remembered
-- to copy it into that page's keywords. Pages are code, not data, so the
-- only complete list of what a page contains is the page itself.
--
-- So each page is BUILT ONCE, unseen, into a hidden frame the first time
-- the search box is used, and every label on it is read back off the
-- frames it made: the text, the card it sits in, the tab it is on, and
-- how far down the page it is. That last number is what lets a result
-- scroll the window to the setting rather than just open its page.
-- Building runs one page per frame so the first keystroke never hitches,
-- and a page you actually open refreshes its own entries, so the index
-- never trails what is on screen.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local ConfigLayout = ns.ConfigLayout
local ConfigMenu = ns.ConfigMenu
local ConfigPages = ns.ConfigPages
local Tokens = ns.ConfigTokens

local Search = {}

-- Pages never built for the index. The aura page's builder enters the
-- aura engine's edit mode (pauses it, pins every aura on screen); it is
-- still found by its name and keywords, just not setting by setting.
local SKIP = { auras = true }

local index = {}      -- [itemId] = { entry, ... }
local done = {}       -- [itemId] = true once its page has been indexed
local running = false
local scratch

-- ============================================================
-- READING A BUILT PAGE
-- ============================================================
local function Clean(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("[\r\n]+", " ")
    text = text:gsub("%s+", " ")
    text = text:gsub("^ ", "")
    text = text:gsub(" $", "")
    return text
end

-- A label, not a value: slider readouts ("75%", "1.2", "3 / 5") and
-- one-character marks are the widget talking about its state.
local function Meaningful(t)
    if #t < 2 then return false end
    if t:match("^[%d%.%%%s%-%+x:/,]+$") then return false end
    return true
end

local function VFrac(point)
    if not point then return 0 end
    if point:find("TOP") then return 0 end
    if point:find("BOTTOM") then return 1 end
    return 0.5
end

local function Height(r)
    local ok, h = pcall(r.GetHeight, r)
    return (ok and type(h) == "number") and h or 0
end

-- How far below the top of `stop` the top of `region` sits, worked out
-- from anchors alone. Nothing here is on screen while indexing, so
-- GetTop has no answer; the anchors a page set are known either way.
local function OffsetY(region, stop, depth)
    depth = depth or 0
    if region == stop or depth > 12 or not region then return 0 end
    local n = region.GetNumPoints and region:GetNumPoints() or 0
    local parent = region.GetParent and region:GetParent()
    if n == 0 then
        if parent and parent ~= region then return OffsetY(parent, stop, depth + 1) end
        return 0
    end
    local point, rel, relPoint, _, y = region:GetPoint(1)
    rel = rel or parent
    if not rel then return y or 0 end
    local top = (y or 0)
        - VFrac(relPoint) * Height(rel)
        + VFrac(point) * Height(region)
    return OffsetY(rel, stop, depth + 1) + top
end

local function IsShownSafe(f)
    local ok, v = pcall(f.IsShown, f)
    return not ok or v
end

-- Every label under one container (a card, normally): each FontString
-- with real text becomes an entry. `owner` is the container's direct
-- child it belongs to - the checkbox, the slider - which is what gets
-- flashed after a jump.
local function Collect(container, out, owner, depth)
    if depth > 7 then return end
    -- what its tooltip says (UI.Tooltip keeps it on the frame)
    if depth > 0 and type(container._zTipBody) == "string" then
        local t = Clean(container._zTipBody)
        if Meaningful(t) and IsShownSafe(container) then
            local title = Clean(container._zTipTitle)
            out[#out + 1] = { fs = container, text = t, owner = owner or container, tip = true,
                tipLabel = Meaningful(title) and title or nil }
        end
    end
    for _, r in ipairs({ container:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("FontString") and r ~= container._zTitle then
            local t = Clean(r:GetText())
            if Meaningful(t) and IsShownSafe(r) then
                out[#out + 1] = { fs = r, text = t, owner = owner }
            end
        end
    end
    for _, c in ipairs({ container:GetChildren() }) do
        if IsShownSafe(c) and not (c.IsObjectType and c:IsObjectType("EditBox")) then
            Collect(c, out, owner or c, depth + 1)
        end
    end
end

-- Read a built page back into entries. layout tells us which children
-- are the page title and the tab bar (skipped) and which belong to which
-- tab. The real window passes its own layout after a build, so the
-- entries it gets back hold live widgets; the indexer's are thrown away
-- with its scratch frame and keep only text and position.
function Search.Scan(parent, layout, itemId)
    local entries = {}
    local kids = { parent:GetChildren() }
    local tabOf = {}
    for _, r in ipairs(layout.tabRanges or {}) do
        for i = r.from, r.to do tabOf[i] = r.id end
    end
    for i, box in ipairs(kids) do
        if box ~= layout.headerFrame and box ~= layout.tabBar and IsShownSafe(box) then
            local tab = tabOf[i]
            local boxY = OffsetY(box, parent)
            local title = box._zTitle and Clean(box._zTitle:GetText()) or nil
            if title == "" then title = nil end
            if title then
                entries[#entries + 1] = { item = itemId, tab = tab, kind = "card",
                    label = title, card = title, y = boxY, widget = box }
            end
            local found = {}
            Collect(box, found, nil, 0)
            local lastLabel, lastY, lastWidget
            -- Top to bottom, so a description can borrow the label of
            -- the setting it is written under.
            for _, f in ipairs(found) do f.y = boxY + OffsetY(f.fs, box) end
            table.sort(found, function(a, b) return a.y > b.y end)
            for _, f in ipairs(found) do
                local long = #f.text > 70
                local e = { item = itemId, tab = tab, card = title, y = f.y,
                    widget = f.owner or f.fs }
                if f.tip then
                    -- a tooltip lands on the control it belongs to
                    e.kind, e.text, e.label = "tip", f.text, f.tipLabel or lastLabel or title or f.text
                elseif long then
                    -- A description lands on the setting it explains.
                    e.kind, e.text, e.label = "desc", f.text, lastLabel or title or f.text
                    if lastY then e.y, e.widget = lastY, lastWidget end
                else
                    e.kind, e.label = "row", f.text
                    lastLabel, lastY, lastWidget = f.text, e.y, e.widget
                end
                entries[#entries + 1] = e
            end
        end
    end
    -- One entry per tab name, pointing at the top of that tab.
    if layout.tabBar and layout.tabList then
        local barY = OffsetY(layout.tabBar, parent)
        for _, t in ipairs(layout.tabList) do
            entries[#entries + 1] = { item = itemId, tab = t.id, kind = "tab",
                label = t.label, y = barY }
        end
    end
    local tabName = {}
    for _, t in ipairs(layout.tabList or {}) do tabName[t.id] = t.label end
    for _, e in ipairs(entries) do
        if e.tab and e.kind ~= "tab" then e.tabLabel = tabName[e.tab] end
        e.hay = ((e.label or "") .. " " .. (e.text or "")):lower()
        e.key = (e.kind or "") .. "\1" .. (e.label or "") .. "\1" .. (e.card or "")
            .. "\1" .. (e.text or "")
    end
    return entries
end

-- After a real build: replace what the index held for the parts of the
-- page that were just built (everything outside tabs, plus the tab that
-- is showing). Other tabs keep their indexed entries.
function Search.Refresh(itemId, layout, entries)
    local active
    for _, r in ipairs(layout.tabRanges or {}) do active = r.id end
    local keep, hasTabs = {}, false
    for _, e in ipairs(index[itemId] or {}) do
        if e.kind == "tab" then
            keep[#keep + 1] = e
            hasTabs = true
        elseif e.tab ~= nil and e.tab ~= active then
            keep[#keep + 1] = e
        end
    end
    for _, e in ipairs(entries) do
        if e.kind ~= "tab" or not hasTabs then
            local copy = {}
            for k, v in pairs(e) do
                if k ~= "widget" then copy[k] = v end
            end
            keep[#keep + 1] = copy
        end
    end
    index[itemId] = keep
end

-- ============================================================
-- BUILDING THE INDEX
-- ============================================================
local function EachItem(fn)
    for _, item in ipairs(ConfigMenu) do
        fn(item, nil)
        for _, child in ipairs(item.children or {}) do fn(child, item) end
    end
end

local function IndexOne(item)
    if not scratch then
        scratch = CreateFrame("Frame", nil, UIParent)
        scratch:Hide()
        scratch:SetSize(560, 10)
    end
    local fn = item.page and ConfigPages[item.page]
    if fn then
        local layout = ConfigLayout.New(scratch, -14)
        layout.pageId, layout.indexAll = item.id, true
        if pcall(fn, layout, item) then
            local entries = Search.Scan(scratch, layout, item.id)
            for _, e in ipairs(entries) do e.widget = nil end
            index[item.id] = entries
        end
    end
    -- Throw the scratch build away (WoW has no frame destructor: hidden,
    -- unparented and unreferenced is as gone as a frame gets).
    for _, c in ipairs({ scratch:GetChildren() }) do
        c:Hide()
        c:ClearAllPoints()
        c:SetParent(nil)
    end
    for _, r in ipairs({ scratch:GetRegions() }) do r:Hide() end
    done[item.id] = true
end

function Search.IsIndexing() return running end

-- Start (once per session) the background build. onDone runs when every
-- page is in, so the window can redraw results that were partial.
function Search.EnsureIndex(onDone)
    if running then return end
    local todo = {}
    EachItem(function(item)
        if item.page and not done[item.id] and not SKIP[item.id] then
            todo[#todo + 1] = item
        end
    end)
    if #todo == 0 then return end
    running = true
    local i = 0
    local function Step()
        i = i + 1
        local item = todo[i]
        if not item then
            running = false
            if onDone then pcall(onDone) end
            return
        end
        if not done[item.id] then IndexOne(item) end
        C_Timer.After(0, Step)
    end
    C_Timer.After(0, Step)
end

-- ============================================================
-- RANKING
-- ============================================================
local function WordStart(hay, w)
    return (" " .. hay):find(" " .. w, 1, true) ~= nil
end

local function ModuleHay(item)
    local hay = ""
    if item.group and ns.MODULE_GROUPS then
        for _, g in ipairs(ns.MODULE_GROUPS) do
            if g.key == item.group then
                for _, m in ipairs(g.modules) do
                    hay = hay .. " " .. m.label:lower() .. " " .. m.key
                end
            end
        end
    end
    return hay
end

-- Run a query. Returns the ranked results and the set of item ids that
-- have something, for the sidebar filter.
function Search.Run(query)
    local tokens = Tokens(query)
    local results, hits = {}, {}
    if #tokens == 0 then return results, hits end
    local phrase = table.concat(tokens, " ")

    EachItem(function(item, parent)
        if not item.page then return end
        local pageName = item.label:lower()
        local pageHay = pageName .. " " .. (item.keywords or ""):lower()
            .. " " .. (parent and parent.label:lower() or "") .. ModuleHay(item)

        -- The page itself, by name / keywords.
        local all = true
        for _, w in ipairs(tokens) do
            if not pageHay:find(w, 1, true) then all = false break end
        end
        if all then
            -- Below a setting that names the word itself: a hit on the
            -- page's keywords alone should not outrank the setting.
            local score = 20
            if pageName:find(phrase, 1, true) then score = score + 50 end
            results[#results + 1] = { item = item.id, kind = "page", label = item.label,
                score = score, page = item.label, parent = parent and parent.label }
            hits[item.id] = true
        end

        -- Every setting on it.
        for _, e in ipairs(index[item.id] or {}) do
            local ctx = (e.card or ""):lower() .. " " .. pageName
            local score, ok, own = 0, true, 0
            for _, w in ipairs(tokens) do
                if e.hay:find(w, 1, true) then
                    own = own + 1
                    score = score + 10
                    if WordStart(e.hay, w) then score = score + 6 end
                elseif ctx:find(w, 1, true) then
                    score = score + 2
                else
                    ok = false
                    break
                end
            end
            -- At least one word must be in the setting itself, or every
            -- row of a matching card would come back.
            if ok and own > 0 then
                if e.hay:find(phrase, 1, true) then score = score + 25 end
                if e.kind == "card" then score = score + 8
                elseif e.kind == "tab" then score = score + 6
                elseif e.kind == "desc" or e.kind == "tip" then score = score - 12 end
                -- Short labels that match are closer matches.
                score = score + math.max(0, 12 - math.floor(#e.hay / 8))
                results[#results + 1] = { entry = e, item = item.id, kind = e.kind,
                    label = e.label, score = score, page = item.label,
                    parent = parent and parent.label, order = #results }
                hits[item.id] = true
            end
        end
    end)

    -- One result per setting: a description hit that points at a row
    -- already in the list adds nothing.
    local seen, out = {}, {}
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.order or 0) < (b.order or 0)
    end)
    for _, r in ipairs(results) do
        local k = r.item .. "\1" .. (r.label or "") .. "\1" .. ((r.entry and r.entry.card) or "")
            .. "\1" .. ((r.entry and r.entry.tab) or "")
        if not seen[k] then
            seen[k] = true
            out[#out + 1] = r
        end
    end
    return out, hits
end

-- Wrap each matched word in `hex` (case-insensitive), for result rows.
function Search.Highlight(text, query, hex)
    local tokens = Tokens(query)
    local lower = text:lower()
    local marks = {}
    for _, w in ipairs(tokens) do
        local s = 1
        while true do
            local a, b = lower:find(w, s, true)
            if not a then break end
            for i = a, b do marks[i] = true end
            s = b + 1
        end
    end
    local out, open = {}, false
    for i = 1, #text do
        if marks[i] and not open then
            out[#out + 1] = "|cff" .. hex
            open = true
        elseif not marks[i] and open then
            out[#out + 1] = "|r"
            open = false
        end
        out[#out + 1] = text:sub(i, i)
    end
    if open then out[#out + 1] = "|r" end
    return table.concat(out)
end

Search.Clean = Clean

-- shared with later ZacUI files
ns.ConfigSearch = Search
