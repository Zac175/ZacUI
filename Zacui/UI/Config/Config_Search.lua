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

local ADDON_NAME, ns = ...

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
        if pcall(fn, layout, item) then
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

-- Forget a page's entries, so the next search reads it again (a part
-- that adds a tab to a page after the page was indexed, see
-- ns.AddPageTab; a whole new menu row is picked up on its own).
function Search.Invalidate(itemId)
    if itemId == nil then
        for k in pairs(done) do done[k] = nil end
        return
    end
    done[itemId] = nil
end

-- Start (once per session) the background build. onDone runs when every
-- page is in, so the window can redraw results that were partial.
function Search.EnsureIndex(onDone)
    if running then return end
    local todo = {}
    EachItem(function(item, parent)
        if item.page and not done[item.id] and not SKIP[item.id] and not Off(item)
            and not (parent and Off(parent)) then
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
    { cmd = "/zacui flavor",      desc = "what runs on this game version (era, tbc, forever)" },
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

-- Equal scores: a setting before its section, a section before a
-- command, a command before a tab, a tab before a page.
local KIND_RANK = { row = 1, desc = 1, tip = 1, card = 2, command = 3, tab = 4, page = 5 }

-- Run a query. Returns the ranked results and the set of item ids that
-- have something, for the sidebar filter. Each result: item (the menu
-- id), kind, label, score, page, parent, and entry (the indexed line)
-- or command.
function Search.Run(query)
    local tokens = Tokens(query)
    local results, hits = {}, {}
    if #tokens == 0 then return results, hits end
    local phrase = table.concat(tokens, " ")

    EachItem(function(item, parent)
        if not item.page or Off(item) or (parent and Off(parent)) then return end
        local pageName = item.label:lower()
        local parentName = parent and parent.label:lower() or ""

        -- The page itself: its name, then its keywords and module names.
        local pageOwn = pageName .. " " .. (item.keywords or ""):lower() .. ModuleHay(item)
        local score = Score(pageOwn, parentName, tokens)
        if score then
            -- a hit on the keywords alone sits below a setting that names
            -- the word itself; the page's own name counts in full
            if not Score(pageName, nil, tokens) then score = math.floor(score / 2) end
            if pageName:find(phrase, 1, true) then score = score + 30 end
            -- the page whose name is the query is what was asked for
            if pageName == phrase then score = score + 60 end
            results[#results + 1] = { item = item.id, kind = "page", label = item.label,
                score = score, page = item.label, parent = parent and parent.label, order = #results }
            hits[item.id] = true
        end

        -- Every setting on it.
        for _, e in ipairs(index[item.id] or {}) do
            local ctx = (e.card or ""):lower() .. " " .. (e.tabLabel or ""):lower() .. " "
                .. pageName .. " " .. parentName
            local s = Score(e.hay, ctx, tokens)
            if s then
                local label = (e.label or ""):lower()
                if label:find(phrase, 1, true) then s = s + 30 end
                if label == phrase then s = s + 40 end
                if e.kind == "card" then s = s + 4
                elseif e.kind == "tab" then s = s + 3
                elseif e.kind == "desc" or e.kind == "tip" then s = s - 10 end
                -- Short labels that match are closer matches.
                s = s + math.max(0, 12 - math.floor(#label / 8))
                results[#results + 1] = { entry = e, item = item.id, kind = e.kind,
                    label = e.label, score = s, page = item.label,
                    parent = parent and parent.label, order = #results }
                hits[item.id] = true
            end
        end
    end)

    -- The slash commands.
    for _, c in ipairs(COMMANDS) do
        if CommandOn(c) then
            local own = (c.cmd .. " " .. (c.desc or "")):lower()
            local s = Score(own, nil, tokens)
            if s then
                if c.cmd:lower():find(phrase, 1, true) then s = s + 20 end
                results[#results + 1] = { command = c, item = "_commands", kind = "command",
                    label = c.cmd, score = s, page = "Slash commands", order = #results }
            end
        end
    end

    -- One result per setting: a description hit that points at a row
    -- already in the list adds nothing.
    local seen, out = {}, {}
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        local ra, rb = KIND_RANK[a.kind] or 9, KIND_RANK[b.kind] or 9
        if ra ~= rb then return ra < rb end
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
