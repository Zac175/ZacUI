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
--
-- MATCHING (2026-11-07, the way Zac liked in another addon's options):
-- case-insensitive, every word of the query somewhere in the title, the
-- description, the tooltip or the breadcrumb; a word may sit at the
-- start (best), at a word start, inside a word, as letters in order
-- ("castbar" finds "Cast Bar") or with one letter wrong. Results are
-- ranked by that, then a setting before its section before the page.
-- Slash commands are results too (kind "command"). A page this game
-- version does not run is never indexed or listed.
-- Config_SearchBox draws the results in a dropdown under the search box.

-- (Zacui_Options: the settings load on demand; ZacUI's namespace is the one Core_Boot publishes)
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local ConfigLayout = ns.ConfigLayout
local ConfigMenu = ns.ConfigMenu
local ConfigPages = ns.ConfigPages
local Tokens = ns.ConfigTokens
local UI = ns.UI

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
            -- (a settings section shows its title in capitals; the search
            -- reads it as written)
            local title = box._zTitle and Clean(rawget(box, "_zTitleText") or box._zTitle:GetText()) or nil
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
    if Search.SavePage then Search.SavePage(itemId) end
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

-- a page this game version does not run has nothing to find (Core_Flavor):
-- not built for the index, never a result
local function Off(item)
    return ns.FeatureOffForPage and ns.FeatureOffForPage(item.id) and true or false
end

local function IndexOne(item)
    if not scratch then
        scratch = CreateFrame("Frame", nil, UIParent)
        scratch:Hide()
        scratch:SetSize(560, 10)
    end
    local fn = item.page and ConfigPages[item.page]
    if fn then
        -- built in the settings window's look, as the window builds it
        -- (UI.S: its rows, sizes and type)
        local was = UI._zSettings
        UI._zSettings = true
        local layout = ConfigLayout.New(scratch, 0)
        layout.pageId, layout.indexAll = item.id, true
        Search._reading = true
        local built = pcall(fn, layout, item)
        Search._reading = nil
        if built then
            local ok, entries = pcall(Search.Scan, scratch, layout, item.id)
            if ok then
                for _, e in ipairs(entries) do e.widget = nil end
                index[item.id] = entries
            end
        end
        UI._zSettings = was
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

-- ============================================================
-- THE INDEX IS KEPT BETWEEN SESSIONS (2026-11-10)
-- Zac: "typing in the search box omega lags my game". Reading every page
-- unseen is the expensive part (each one is a full page build, some two
-- thousand frames in all that the client never gives back), and it ran
-- again on the first search of every session, one page a frame, right
-- under the typing. Now:
--   * what was read is saved (ZacUIDB.searchIndex) with a stamp of what
--     it was read on: the version, the game version, the language and
--     which modules are switched on. With the same stamp the next
--     session loads it and builds nothing; a new version (or a module
--     switched) reads again, once.
--   * a page you open is re-read from the real page as before
--     (Search.Refresh) and the saved copy follows.
--   * when pages do have to be read, the reading waits while keys are
--     arriving (TYPE_PAUSE after the last one), so typing stays smooth
--     and the results fill in a moment later.
-- Not a setting: no profile carries it, and it is safe to delete.
-- (2026-11-25: kept small, see Slim; and a page nobody has read yet on
-- this client comes from the shipped index before any page is read.)
-- ============================================================
local CACHE_FORMAT = 2
local TYPE_PAUSE = 0.4
local lastKey = -100

function Search.NoteKey() lastKey = GetTime and GetTime() or 0 end

local function CacheSig()
    local parts = { "f" .. CACHE_FORMAT, tostring(_G.ZacUIFrame and _G.ZacUIFrame.VERSION or "?"),
        tostring(ns.Flavor and ns.Flavor() or "?"), tostring(GetLocale and GetLocale() or "?") }
    local mods = type(ZacUIDB) == "table" and type(ZacUIDB.modules) == "table" and ZacUIDB.modules or {}
    local off = {}
    for k, v in pairs(mods) do if v == false then off[#off + 1] = tostring(k) end end
    table.sort(off)
    parts[#parts + 1] = table.concat(off, ",")
    return table.concat(parts, "|")
end

-- A page as it is kept (saved, and shipped): small. Every line is
--   { kind letter, label, tab number, card number, text }
-- (numbers into the page's own lists t / c, 0 = none; text only when it
-- has one; a tab in t is { its id, its label }), and nothing that can be
-- worked out again (hay, key, the page id) or that belongs to the build
-- it was read from (the frame, where the line sat).
local KIND_CODE = { row = "r", desc = "d", tip = "t", card = "c", tab = "b" }
local KIND_OF = { r = "row", d = "desc", t = "tip", c = "card", b = "tab" }
local function Slim(list, keep)
    local out, tabs, cards = {}, {}, {}
    local tabN, cardN = {}, {}
    for _, e in ipairs(list) do
        if not keep or keep(e) then
            local tn = 0
            if e.tab ~= nil then
                tn = tabN[e.tab]
                if not tn then
                    tn = #tabs + 1
                    tabs[tn] = { e.tab, false }
                    tabN[e.tab] = tn
                end
                if e.tabLabel and not tabs[tn][2] then tabs[tn][2] = e.tabLabel end
            end
            local cn = 0
            if e.card ~= nil then
                cn = cardN[e.card]
                if not cn then
                    cn = #cards + 1
                    cards[cn] = e.card
                    cardN[e.card] = cn
                end
            end
            local c = { KIND_CODE[e.kind] or e.kind or "r", e.label or false, tn, cn }
            if e.text ~= nil then c[5] = e.text end
            out[#out + 1] = c
        end
    end
    return { t = tabs, c = cards, e = out }
end
local function Fatten(id, saved)
    local list = {}
    local tabs = type(saved.t) == "table" and saved.t or {}
    local cards = type(saved.c) == "table" and saved.c or {}
    for i, c in ipairs(saved.e or {}) do
        local e = { kind = KIND_OF[c[1]] or c[1], item = id }
        if c[2] then e.label = c[2] end
        local t = tabs[c[3]]
        if t then
            e.tab = t[1]
            if e.kind ~= "tab" and t[2] then e.tabLabel = t[2] end
        end
        e.card = cards[c[4]]
        e.text = c[5]
        e.hay = ((e.label or "") .. " " .. (e.text or "")):lower()
        e.key = (e.kind or "") .. "\1" .. (e.label or "") .. "\1" .. (e.card or "")
            .. "\1" .. (e.text or "")
        list[i] = e
    end
    return list
end

local function Cache(create)
    if type(ZacUIDB) ~= "table" then return nil end
    local c = ZacUIDB.searchIndex
    local sig = CacheSig()
    if type(c) ~= "table" or c.sig ~= sig or type(c.pages) ~= "table" then
        if not create then return nil end
        c = { sig = sig, pages = {} }
        ZacUIDB.searchIndex = c
    end
    return c
end
local function SavePage(id)
    if not done[id] then return end
    local c = Cache(true)
    -- (a page with nothing to find is saved empty, so it is not read again)
    if c then c.pages[id] = Slim(index[id] or {}) end
end
function Search.ForgetSaved()
    if type(ZacUIDB) == "table" then ZacUIDB.searchIndex = nil end
end
function Search.SavedSig() local c = Cache(false) return c and c.sig or nil end
Search.SavePage = SavePage
-- (release tooling: every page read so far, as it would be kept)
function Search.Export(keep)
    local out = {}
    for id in pairs(done) do
        out[id] = Slim(index[id] or {}, keep and function(e) return keep(id, e) end or nil)
    end
    return out
end

-- A page from what this account saved (read on this client: a page you
-- have opened, with whatever only your setup adds to it) ...
local function FromSaved(id)
    local c = Cache(false)
    local saved = c and c.pages[id]
    if type(saved) ~= "table" then return nil end
    local okF, list = pcall(Fatten, id, saved)
    return (okF and type(list) == "table") and list or nil
end

-- ... or from THE INDEX THAT SHIPS WITH THE SETTINGS WINDOW (2026-11-25,
-- Zac: "searching in both addons still nukes fps"; Config_SearchData.lua,
-- written by tools/search_index from the pages themselves: each page as a
-- fresh install shows it, once per game version and class). With it
-- nobody's client reads a page unseen: the first search after every
-- update used to build every page, one a frame - some two thousand
-- frames the client never gives back, seconds of single-digit fps. Used
-- only when it was made for exactly this version (a build without a
-- fresh one reads the pages, as before) and this language. What it
-- cannot know - a line only your own setup adds - comes in the moment
-- you open that page (Search.Refresh), and is saved from then on.
local shippedPages
local function Shipped()
    if shippedPages ~= nil then return shippedPages end
    shippedPages = false
    local d = ns.SearchShipped
    -- (the file keeps only the pages of the client and class it loaded on)
    if type(d) == "table" and d.v == (_G.ZacUIFrame and _G.ZacUIFrame.VERSION) and type(d.pages) == "table"
            and next(d.pages)
            and d.flavor == (ns.Flavor and ns.Flavor() or "era")
            and d.class and d.class == (UnitClass and select(2, UnitClass("player")))
            and (not GetLocale or GetLocale() == (d.locale or "enUS")) then
        shippedPages = d.pages
    end
    ns.SearchShipped = nil
    return shippedPages
end
local function ShippedPart(text)
    if type(text) ~= "string" then return nil end
    local fn = loadstring(text)
    if not fn then return nil end
    local okL, saved = pcall(fn)
    if not okL or type(saved) ~= "table" then return nil end
    return saved
end
local function FromShipped(id)
    local pages = Shipped()
    local v = pages and pages[id]
    if not v then return nil end
    pages[id] = nil
    if type(v) == "string" then
        local saved = ShippedPart(v)
        if not saved then return nil end
        local okF, list = pcall(Fatten, id, saved)
        return (okF and type(list) == "table") and list or nil
    end
    -- the lines every class has, and this class's own, each where it
    -- stands on the page (`at`): the page as this class reads it
    local base, extra = ShippedPart(v[1]), ShippedPart(v[2])
    if not (base and extra and type(extra.at) == "table") then return nil end
    local okB, shared = pcall(Fatten, id, base)
    local okE, own = pcall(Fatten, id, extra)
    if not (okB and okE) then return nil end
    local at, list, si, oi = extra.at, {}, 1, 1
    for pos = 1, #shared + #own do
        if own[oi] and at[oi] == pos then
            list[pos] = own[oi]
            oi = oi + 1
        else
            list[pos] = shared[si]
            si = si + 1
        end
    end
    if #list ~= #shared + #own then return nil end
    return list
end
function Search.HasShipped() return Shipped() and true or false end

-- Forget a page's entries, so the next search reads it again (a part
-- that adds a tab to a page after the page was indexed, see
-- ns.AddPageTab; a whole new menu row is picked up on its own).
function Search.Invalidate(itemId)
    if itemId == nil then
        for k in pairs(done) do done[k] = nil end
        if Search.ForgetSaved then Search.ForgetSaved() end
        return
    end
    done[itemId] = nil
    local c = type(ZacUIDB) == "table" and ZacUIDB.searchIndex
    if type(c) == "table" and type(c.pages) == "table" then c.pages[itemId] = nil end
end

-- Fills the index in the background. A page comes from what this account
-- saved, else from the index that ships with the settings window - both
-- cheap, as many as fit in a few ms a frame, never waiting; only a page
-- neither has is READ (built unseen), and then never while keys are
-- arriving or in a fight, with a rest after each read twice as long as
-- the read took, so reading never takes more than a third of the time.
-- Every page is usable the moment it is in; onDone runs when all are
-- (and about every 2 s while pages are being read, so a list on screen
-- fills in).
local CHEAP_MS = 4
local function ClockMs()
    return (debugprofilestop and debugprofilestop()) or ((GetTime and GetTime() or 0) * 1000)
end
function Search.EnsureIndex(onDone)
    if running then return end
    -- (what an older version saved is of no use to this one: let it go
    -- now, not whenever a page is next saved - it is read at every login)
    do
        local c = type(ZacUIDB) == "table" and ZacUIDB.searchIndex
        if c ~= nil and (type(c) ~= "table" or c.sig ~= CacheSig()) then ZacUIDB.searchIndex = nil end
    end
    local todo = {}
    EachItem(function(item, parent)
        if item.page and not done[item.id] and not SKIP[item.id] and not Off(item)
            and not (parent and Off(parent)) then
            todo[#todo + 1] = item
        end
    end)
    if #todo == 0 then return end
    running = true
    local i, lastTold = 0, GetTime and GetTime() or 0
    local function Step()
        local t0 = ClockMs()
        while true do
            local item = todo[i + 1]
            if not item then
                running = false
                if onDone then pcall(onDone) end
                return
            end
            local id = item.id
            if done[id] then
                i = i + 1
            else
                local list = FromSaved(id) or FromShipped(id)
                if list then
                    index[id] = list
                    done[id] = true
                    i = i + 1
                    if ClockMs() - t0 >= CHEAP_MS then
                        C_Timer.After(0, Step)
                        return
                    end
                else
                    -- (keys are arriving, or a fight: the reading waits)
                    if GetTime and (GetTime() - lastKey) < TYPE_PAUSE then
                        C_Timer.After(0.1, Step)
                        return
                    end
                    if InCombatLockdown and InCombatLockdown() then
                        C_Timer.After(0.5, Step)
                        return
                    end
                    local r0 = ClockMs()
                    IndexOne(item)
                    SavePage(id)
                    local cost = (ClockMs() - r0) / 1000
                    i = i + 1
                    local now = GetTime and GetTime() or 0
                    if onDone and now - lastTold >= 2 and todo[i + 1] then
                        lastTold = now
                        pcall(onDone)
                    end
                    C_Timer.After(math.min(0.25, math.max(0, cost * 2)), Step)
                    return
                end
            end
        end
    end
    C_Timer.After(0, Step)
end
function Search.IndexedCount()
    local n = 0
    for _ in pairs(done) do n = n + 1 end
    return n
end
-- (the tests and the index tool: is a page being read unseen right now)
function Search.IsReading() return Search._reading and true or false end

-- ============================================================
-- COMMANDS
-- ============================================================
-- Slash commands are found like settings (kind "command"): the text
-- people type and what it does. One without a <placeholder> runs from a
-- result; one with a hole, or marked paste, goes into the chat box to be
-- finished. A part adds its own with ns.AddSearchCommand (words the
-- entry already carries are not doubled: the key is the command text).
--   ns.AddSearchCommand("/zui plate", "the sample nameplate", { feature = "nameplates" })
local COMMANDS = {
    { cmd = "/zui <page>",        desc = "jump straight to a page, e.g. /zui colors" },
    { cmd = "/zui search <words>", desc = "open this window with a search typed" },
    { cmd = "/zui tour",          desc = "a guided tour of this window", feature = "tutorial" },
    { cmd = "/zui setup",         desc = "quick setup: the look, the parts, the basics", feature = "tutorial" },
    { cmd = "/zui edit",          desc = "Edit Mode: every movable part of ZacUI at once" },
    { cmd = "/zacui <mod> on",    desc = "turn a single module on or off" },
    { cmd = "/zacui rescan",      desc = "re-run the classifier over every live frame" },
    { cmd = "/zacui inset <Frame> l r t b", desc = "nudge a panel background that sits wrong" },
    { cmd = "/zacui line <Frame> <y>",      desc = "move a panel's header hairline" },
    { cmd = "/zacui status",      desc = "list every module and its state" },
    { cmd = "/zacui id",          desc = "identify the next frame you click (its name in chat)" },
    { cmd = "/zacui flavor",      desc = "what runs on this game version (era, tbc, forever, retail)" },
    { cmd = "/zacui version",     desc = "your version and the newest one seen in your guild and group" },
    { cmd = "/zacui reset",       desc = "back to shipped defaults", paste = true },
    { cmd = "/zui plate",         desc = "the sample nameplate with everything on", feature = "nameplates" },
    { cmd = "/zui noob",          desc = "the hesitation scorecard of the last pull, in chat", feature = "hud" },
    { cmd = "/zui raid",          desc = "the raid summary of the last raid", feature = "raid_summary" },
    { cmd = "/zui bless",         desc = "the blessing assignments grid", feature = "blessings" },
    { cmd = "/zui mount",         desc = "what the smart mount macro picks here" },
    { cmd = "/zui msgs",          desc = "hide or show the raid messages over the raid frames", feature = "chat" },
    { cmd = "/zui raidchat",      desc = "raid frames in the chat box while in a raid: on / off", feature = "chat" },
    { cmd = "/zui testroll",      desc = "three made-up loot drops on screen", feature = "lootroll" },
}
local function CommandKey(cmd) return ((cmd or ""):lower():gsub("%s+", " ")) end
local function AddSearchCommand(cmd, desc, opts)
    if type(cmd) ~= "string" or cmd == "" then return false end
    local key = CommandKey(cmd)
    for _, c in ipairs(COMMANDS) do
        if CommandKey(c.cmd) == key then
            c.desc = desc or c.desc
            return true
        end
    end
    opts = opts or {}
    COMMANDS[#COMMANDS + 1] = { cmd = cmd, desc = desc or "", feature = opts.feature, paste = opts.paste }
    return true
end
ns.AddSearchCommand = AddSearchCommand
ns.SearchCommands = COMMANDS

-- true for a command that runs on this game version (Core_Flavor)
local function CommandOn(c)
    if c.feature and ns.FeatureOn and not ns.FeatureOn(c.feature) then return false end
    return true
end

-- Run a command result: a complete command runs now, one with a hole in
-- it (or marked paste) goes into the chat box to be finished.
function Search.RunCommand(r)
    local c = r and r.command
    if not c then return false end
    local text = c.cmd
    if c.paste or text:find("<", 1, true) or text:find("|", 1, true) then
        local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
        if open then open(text:gsub("%s*<.*$", "") .. " ") end
        return "pasted"
    end
    local slash, rest = text:match("^(/%S+)%s*(.-)$")
    if not slash then return false end
    local list = SlashCmdList
    local handler
    if list then
        -- the handler registered under this slash word (SLASH_X1 = "/zui")
        for name, fn in pairs(list) do
            local i = 1
            while true do
                local s = _G["SLASH_" .. name .. i]
                if not s then break end
                if s:lower() == slash:lower() then handler = fn break end
                i = i + 1
            end
            if handler then break end
        end
    end
    if not handler then return false end
    handler(rest or "")
    return "ran"
end

-- ============================================================
-- RANKING
-- ============================================================
-- One word against one lowercase string. The quality says how it
-- matched: at the start, at a word start, inside a word, as letters in
-- order (a fuzzy hit: "castbar" in "cast bar", "aoc" in "auto open
-- containers"), or with one letter wrong. nil when it does not.
local Q_PREFIX, Q_WORD, Q_INSIDE = 100, 85, 65

-- Letters in order. The forward pass finds where the earliest full match
-- ends; the backward pass from there finds the latest start, so "stat"
-- in "secondary stat display" lands on "stat" and not on the s of
-- secondary. A match spread over much more than its own length is noise
-- ("combat" scattered across a sentence, "cat" across "character
-- settings"), not a hit: slack is how many extra letters the spread may
-- hold, half the word's length unless given. Returns a quality 25..50 by
-- how tight the letters sit, or nil.
local function Subseq(hay, w, slack)
    local hl, wl = #hay, #w
    if wl > hl then return nil end
    -- (find per letter: one C call each, not a Lua loop over the string)
    local pos = 0
    for i = 1, wl do
        pos = hay:find(w:sub(i, i), pos + 1, true)
        if not pos then return nil end
    end
    local last = pos
    local hi, wi = last, wl
    while wi >= 1 do
        if hay:byte(hi) == w:byte(wi) then wi = wi - 1 end
        hi = hi - 1
    end
    local span = last - hi
    if span > wl + (slack or math.max(2, math.floor(wl / 2))) then return nil end
    return 25 + math.floor(25 * wl / span)
end

-- One letter wrong, dropped or doubled: the first letter of the word the
-- forward pass cannot place is left out and the rest must still be found
-- in order, close together. Cheap (two passes) and good enough for a slip
-- of the finger.
local function Typo(hay, w)
    local wl = #w
    local pos, stuck = 0, nil
    for i = 1, wl do
        pos = hay:find(w:sub(i, i), pos + 1, true)
        if not pos then stuck = i break end
    end
    if not stuck then return nil end   -- (it matched whole: not a typo)
    local short = w:sub(1, stuck - 1) .. w:sub(stuck + 1)
    if #short < 3 then return nil end
    local q = Subseq(hay, short, 3)
    return q and math.floor(q * 0.6) or nil
end

local function WordQuality(hay, w)
    local i = hay:find(w, 1, true)
    if i then
        if i == 1 then return Q_PREFIX end
        local prev = hay:byte(i - 1)
        if prev == 32 or prev < 48 or (prev > 57 and prev < 65) then return Q_WORD end
        return Q_INSIDE
    end
    local wl = #w
    if wl < 3 then return nil end
    local q = Subseq(hay, w)
    if q then return q end
    if wl >= 4 then return Typo(hay, w) end
    return nil
end
Search.WordQuality = WordQuality

-- Every word against the thing itself (own) and, failing that, against
-- the words around it (ctx: its card, tab, page, part) at a quarter of
-- the quality. nil unless every word landed and at least one landed on
-- the thing itself; otherwise every row of a matching card would be a
-- result.
local function Score(own, ctx, tokens)
    local total, hits = 0, 0
    for _, w in ipairs(tokens) do
        local q = WordQuality(own, w)
        if q then
            hits = hits + 1
            total = total + q
        else
            q = ctx and WordQuality(ctx, w)
            if not q then return nil end
            total = total + math.floor(q / 4)
        end
    end
    if hits == 0 then return nil end
    return total
end
Search.Score = Score

-- THE SAME ANSWERS, CHEAPER (2026-11-25). WordQuality above is the rule;
-- Fast* below gives exactly what it gives for a word prepared once per
-- search (its letters, and its one-letter-short spellings as they are
-- first needed), so nothing is cut out of a string or joined per line:
--   * the forward pass over the letters is made once and serves both the
--     letters-in-order test and the one-letter-wrong test (the rule made
--     it twice);
--   * a line's surroundings are the same string for every line of a card,
--     so a word's answer for one such string is kept for the search.
local string_find, string_byte, string_sub = string.find, string.byte, string.sub
local math_floor, math_max = math.floor, math.max
local function Prepare(w)
    local L = {}
    for i = 1, #w do L[i] = string_sub(w, i, i) end
    return { w = w, n = #w, L = L, B = { string_byte(w, 1, #w) }, short = {}, ctx = {} }
end
-- letters in order within a span (Subseq, from its backward pass on):
-- last is where the forward pass ended
local function Tight(hay, B, wl, last, slack)
    local hi, wi = last, wl
    while wi >= 1 do
        if string_byte(hay, hi) == B[wi] then wi = wi - 1 end
        hi = hi - 1
    end
    local span = last - hi
    if span > wl + (slack or math_max(2, math_floor(wl / 2))) then return nil end
    return 25 + math_floor(25 * wl / span)
end
local function FastQuality(hay, tk)
    local w = tk.w
    local i = string_find(hay, w, 1, true)
    if i then
        if i == 1 then return Q_PREFIX end
        local prev = string_byte(hay, i - 1)
        if prev == 32 or prev < 48 or (prev > 57 and prev < 65) then return Q_WORD end
        return Q_INSIDE
    end
    local wl = tk.n
    if wl < 3 then return nil end
    local L = tk.L
    local pos, stuck = 0, nil
    for k = 1, wl do
        pos = string_find(hay, L[k], pos + 1, true)
        if not pos then stuck = k break end
    end
    if not stuck then return Tight(hay, tk.B, wl, pos) end
    -- one letter wrong: the letter that could not be placed is left out
    if wl < 4 then return nil end
    local sh = tk.short[stuck]
    if sh == nil then
        local short = string_sub(w, 1, stuck - 1) .. string_sub(w, stuck + 1)
        sh = (#short >= 3) and Prepare(short) or false
        tk.short[stuck] = sh
    end
    if not sh then return nil end
    local sl, SL = sh.n, sh.L
    if sl > #hay then return nil end
    pos = 0
    for k = 1, sl do
        pos = string_find(hay, SL[k], pos + 1, true)
        if not pos then return nil end
    end
    local q = Tight(hay, sh.B, sl, pos, 3)
    return q and math_floor(q * 0.6) or nil
end
local function FastScore(own, ctx, tks)
    local total, hits = 0, 0
    for k = 1, #tks do
        local tk = tks[k]
        local q = FastQuality(own, tk)
        if q then
            hits = hits + 1
            total = total + q
        else
            if not ctx then return nil end
            q = tk.ctx[ctx]
            if q == nil then
                q = FastQuality(ctx, tk) or false
                tk.ctx[ctx] = q
            end
            if not q then return nil end
            total = total + math_floor(q / 4)
        end
    end
    if hits == 0 then return nil end
    return total
end
Search.FastScore = function(own, ctx, tokens)
    local tks = {}
    for i, w in ipairs(tokens) do tks[i] = Prepare(w) end
    return FastScore(own, ctx, tks)
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

-- Where the time went, and what holds it now:
--   * every line's surroundings (card, tab, page, part) were joined and
--     lower-cased again for every search: kept on the line (e._ctx,
--     e._ll; never saved - Slim leaves them out);
--   * a page's own words likewise: kept per page for the session;
--   * a one- or two-letter word matches thousands of lines and all of
--     them were sorted to show twelve: only the best KEEP (and whatever
--     ties with the last of them) are sorted; the best line of every page
--     is noted on the way (the third thing Search.Run returns) for a
--     sidebar row clicked while searching.
-- The twelve rows shown, their order and the pages lit in the sidebar are
-- exactly what they were.
local KEEP = 60
local pageWords = setmetatable({}, { __mode = "k" })    -- [item] = { own, name, parent }
local function PageWords(item, parent)
    local w = pageWords[item]
    if not w or w.parentRef ~= parent or w.labelRef ~= item.label or w.kwRef ~= item.keywords then
        local name = item.label:lower()
        w = { name = name, parent = parent and parent.label:lower() or "",
              own = name .. " " .. (item.keywords or ""):lower() .. ModuleHay(item),
              parentRef = parent, labelRef = item.label, kwRef = item.keywords }
        pageWords[item] = w
    end
    return w
end

-- Equal scores: a setting before its section, a section before a
-- command, a command before a tab, a tab before a page.
local KIND_RANK = { row = 1, desc = 1, tip = 1, card = 2, command = 3, tab = 4, page = 5 }
local function Before(a, b)
    if a.score ~= b.score then return a.score > b.score end
    local ra, rb = KIND_RANK[a.kind] or 9, KIND_RANK[b.kind] or 9
    if ra ~= rb then return ra < rb end
    return (a.order or 0) < (b.order or 0)
end

-- Run a query. Returns the ranked results, the set of item ids that
-- have something (for the sidebar filter) and the best result of each
-- of those. Each result: item (the menu id), kind, label, score, page,
-- parent, and entry (the indexed line) or command.
local function RunBody(query, tick)
    local tokens = Tokens(query)
    local results, hits, best = {}, {}, {}
    if #tokens == 0 then return results, hits, best end
    local phrase = table.concat(tokens, " ")
    local tks = {}
    for i, w in ipairs(tokens) do tks[i] = Prepare(w) end
    local n = 0
    local function Add(r)
        n = n + 1
        r.order = n - 1
        results[n] = r
        local b = best[r.item]
        if not b or Before(r, b) then best[r.item] = r end
    end

    EachItem(function(item, parent)
        if not item.page or Off(item) or (parent and Off(parent)) then return end
        local pw = PageWords(item, parent)
        local pageName, parentName = pw.name, pw.parent

        -- The page itself: its name, then its keywords and module names.
        local score = FastScore(pw.own, parentName, tks)
        if score then
            -- a hit on the keywords alone sits below a setting that names
            -- the word itself; the page's own name counts in full
            if not FastScore(pageName, nil, tks) then score = math_floor(score / 2) end
            if pageName:find(phrase, 1, true) then score = score + 30 end
            -- (2026-11-10) a page whose name BEGINS with what was typed
            -- ("colour" -> Colours) is what was asked for, ahead of a
            -- setting on some tab that happens to be called just that
            if pageName:sub(1, #phrase) == phrase and pageName ~= phrase then score = score + 50 end
            -- the page whose name is the query is what was asked for
            if pageName == phrase then score = score + 60 end
            Add({ item = item.id, kind = "page", label = item.label,
                score = score, page = item.label, parent = parent and parent.label })
            hits[item.id] = true
        end

        -- Every setting on it.
        for _, e in ipairs(index[item.id] or {}) do
            local ctx, label = e._ctx, e._ll
            if not ctx or e._ctxFor ~= pw then
                ctx = (e.card or ""):lower() .. " " .. (e.tabLabel or ""):lower() .. " "
                    .. pageName .. " " .. parentName
                label = (e.label or ""):lower()
                e._ctx, e._ll, e._ctxFor = ctx, label, pw
            end
            local s = FastScore(e.hay, ctx, tks)
            if tick then tick() end
            if s then
                if label:find(phrase, 1, true) then s = s + 30 end
                if label == phrase then s = s + 40 end
                if e.kind == "card" then s = s + 4
                elseif e.kind == "tab" then s = s + 3
                elseif e.kind == "desc" or e.kind == "tip" then s = s - 10 end
                -- Short labels that match are closer matches.
                s = s + math_max(0, 12 - math_floor(#label / 8))
                Add({ entry = e, item = item.id, kind = e.kind,
                    label = e.label, score = s, page = item.label,
                    parent = parent and parent.label })
                hits[item.id] = true
            end
        end
    end)

    -- The slash commands.
    for _, c in ipairs(COMMANDS) do
        if CommandOn(c) then
            local own = (c.cmd .. " " .. (c.desc or "")):lower()
            local s = FastScore(own, nil, tks)
            if s then
                if c.cmd:lower():find(phrase, 1, true) then s = s + 20 end
                Add({ command = c, item = "_commands", kind = "command",
                    label = c.cmd, score = s, page = "Slash commands" })
            end
        end
    end

    -- One result per setting: a description hit that points at a row
    -- already in the list adds nothing.
    local function Ranked(list)
        table.sort(list, Before)
        local seen, out = {}, {}
        for _, r in ipairs(list) do
            local k = r.item .. "\1" .. (r.label or "") .. "\1" .. ((r.entry and r.entry.card) or "")
                .. "\1" .. ((r.entry and r.entry.tab) or "")
            if not seen[k] then
                seen[k] = true
                out[#out + 1] = r
            end
        end
        return out
    end
    if n > KEEP * 3 then
        -- the score the KEEP-th best line has; everything at or over it
        local count, scores = {}, {}
        for i = 1, n do
            local sc = results[i].score
            if not count[sc] then count[sc] = 0 scores[#scores + 1] = sc end
            count[sc] = count[sc] + 1
        end
        table.sort(scores, function(a, b) return a > b end)
        local have, cut = 0, scores[#scores]
        for _, sc in ipairs(scores) do
            have = have + count[sc]
            if have >= KEEP then cut = sc break end
        end
        local top = {}
        for i = 1, n do
            local r = results[i]
            if r.score >= cut then top[#top + 1] = r end
        end
        local out = Ranked(top)
        -- (twelve are shown; fewer than that left after the doubles went:
        -- the whole list after all)
        if #out >= 12 then return out, hits, best end
    end
    return Ranked(results), hits, best
end
function Search.Run(query) return RunBody(query, nil) end

-- THE SEARCH AS YOU TYPE NEVER HOLDS A FRAME. Search.RunSliced does the
-- same work in pieces of at most SLICE_MS a frame and hands the three
-- answers to onDone when it is through (at once when the whole of it
-- fits in the first piece). A newer call drops the one before it.
-- Search.Run is the same search in one go, for Enter and the tests.
local SLICE_MS = 4
local sliceSerial = 0
function Search.RunSliced(query, onDone)
    sliceSerial = sliceSerial + 1
    local mine = sliceSerial
    local t0, count = ClockMs(), 0
    local co = coroutine.create(function()
        return RunBody(query, function()
            count = count + 1
            if count % 40 == 0 and ClockMs() - t0 > SLICE_MS then coroutine.yield() end
        end)
    end)
    local function Step()
        if mine ~= sliceSerial then return end
        t0 = ClockMs()
        local okR, a, b, c = coroutine.resume(co)
        if not okR then
            -- (never leave the box without an answer: the plain search)
            a, b, c = RunBody(query, nil)
            onDone(a, b, c)
            return
        end
        if coroutine.status(co) == "dead" then
            onDone(a, b, c)
        else
            C_Timer.After(0, Step)
        end
    end
    Step()
end
function Search.CancelSliced() sliceSerial = sliceSerial + 1 end

-- ============================================================
-- HOW A RESULT READS
-- ============================================================
-- The kind label a result row wears, and its breadcrumb
-- ("Part > Page > Tab > Card"), for whatever draws the results.
local KIND_LABEL = { page = "Page", tab = "Section", card = "Section", command = "Command" }
function Search.Kind(r)
    return KIND_LABEL[r.kind] or "Setting"
end

function Search.Crumb(r)
    local bits = {}
    if r.kind == "command" then
        bits[1] = "Slash commands"
        if r.command and r.command.desc and r.command.desc ~= "" then bits[2] = r.command.desc end
        return table.concat(bits, "  >  ")
    end
    if r.parent then bits[#bits + 1] = r.parent end
    if r.kind ~= "page" and r.page then bits[#bits + 1] = r.page end
    local e = r.entry
    if e then
        if e.tabLabel then bits[#bits + 1] = e.tabLabel end
        if e.card and r.kind ~= "card" then bits[#bits + 1] = e.card end
    end
    return table.concat(bits, "  >  ")
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
