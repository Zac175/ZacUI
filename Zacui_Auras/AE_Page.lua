-- AE_Page - the Aura engine page in ZacUI's settings, for this engine:
-- the library on the left, the selected display's settings on the right.
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- Registered as ZacUI's "Auras" page, so it takes the place of the page
-- ZacUI ships for the older engine whenever this engine is the one
-- running. Every control writes straight into the display and rebuilds
-- it; only structural changes (select, new, delete, on/off) redraw the
-- page.
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end
local UI, RegisterPage = ns.UI, ns.RegisterPage
if not (UI and RegisterPage) then return end

local M, F = UI.M, UI.F
local Print = ns.Print or print
local function Refresh() if ns.RefreshConfig then ns.RefreshConfig() end end

-- view state: not saved (a search or a collapse that outlived the session
-- would hide most of the library and read as data loss)
local filter = ""
local expanded = {}
local selected
local tab = "display"
local importText = ""
local exportText
local treeScroll, propScroll = 0, 0

local SPLIT_H = 400
local LEFT_W = 200
local ROW_H = 20
local INDENT = 12
local ROW_CAP = 600

-- ============================================================
-- A RUNNING VERTICAL LAYOUT (what the option renderer draws on)
-- ============================================================
local Stack = {}
Stack.__index = Stack
local function NewStack(parent, x, w)
    return setmetatable({ p = parent, y = -4, x = x or 6, w = w or 280 }, Stack)
end
function Stack:Add(widget, h)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", self.p, "TOPLEFT", self.x, self.y)
    self.y = self.y - (h or 20)
    return widget
end
function Stack:Label(text, width, r, g, b)
    local fs = UI.Font(self.p, F.SMALL or 11, { text = tostring(text or ""), cat = "text", key = "gray",
        width = width or (self.w - 8) })
    fs:SetPoint("TOPLEFT", self.p, "TOPLEFT", self.x, self.y)
    fs:SetJustifyH("LEFT")
    if r then fs:SetTextColor(r, g, b) end
    self.y = self.y - math.max(12, (fs:GetStringHeight() or 12)) - 4
    return fs
end
function Stack:Section(text, width)
    self.y = self.y - 4
    local fs = UI.Font(self.p, F.LABEL or 12, { text = tostring(text or ""), cat = "text", key = "gold",
        width = width or (self.w - 8) })
    fs:SetPoint("TOPLEFT", self.p, "TOPLEFT", self.x, self.y)
    fs:SetJustifyH("LEFT")
    self.y = self.y - math.max(14, (fs:GetStringHeight() or 14)) - 4
    return fs
end
function Stack:Gap(h) self.y = self.y - (h or 8) end
function Stack:Height() return -self.y + 8 end

-- ============================================================
-- THE LIBRARY AS A TREE
-- ============================================================
local function Roots()
    local out = {}
    for id, d in pairs(E.data) do
        if not (d.parent and E.data[d.parent]) then out[#out + 1] = id end
    end
    table.sort(out, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return out
end

local iconCache = {}
local function IconOf(id)
    local c = iconCache[id]
    if c ~= nil then return c or nil end
    local d = E.data[id]
    local icon
    if d then
        if E.IsGroup(d) then
            icon = d.groupIcon
            if not icon then
                for _, child in ipairs(E.children[id] or {}) do
                    icon = IconOf(child)
                    if icon then break end
                end
            end
        else
            local _, ic = E.WA.GetNameAndIcon(d)
            icon = ic
        end
    end
    iconCache[id] = icon or false
    return icon
end

local function CountIn(id)
    local n = 0
    for _ in ipairs(E.Descendants(id)) do n = n + 1 end
    return n
end

local function Select(id)
    selected = id
    exportText = nil
    propScroll = 0
    if E.SetPreview then
        local d = id and E.data[id]
        E.SetPreview(d and not E.IsGroup(d) and not E.IsOff(id) and id or nil)
    end
    Refresh()
end

local function TreeRow(stack, id, depth, count, width)
    if count.n >= ROW_CAP then return end
    count.n = count.n + 1
    local d = E.data[id]
    local kids = E.children[id]
    local hasKids = kids and #kids > 0
    local row = CreateFrame("Button", nil, stack.p)
    row:SetSize(width, ROW_H)
    local x = depth * INDENT
    if hasKids then
        local plus = UI.Font(row, F.LABEL or 12, { text = expanded[id] and "-" or "+", cat = "text", key = "gold" })
        plus:SetPoint("LEFT", row, "LEFT", x, 0)
    end
    local ic = row:CreateTexture(nil, "ARTWORK")
    ic._zui_own = true
    ic:SetSize(16, 16)
    ic:SetPoint("LEFT", row, "LEFT", x + 10, 0)
    ic:SetTexture(IconOf(id) or 134400)
    ZacUI.Look.CropIcon(ic, nil, nil, { look = "zacui" })
    local off = E.IsOff(id)
    local live = E.IsLoaded(id)
    local key = off and "gray" or (live and "green" or "normal")
    local name = UI.Font(row, F.SMALL or 11, { text = tostring(id), cat = "text", key = key })
    name:SetPoint("LEFT", ic, "RIGHT", 4, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    if off then ic:SetDesaturated(true) end
    if id == selected then
        local hl = row:CreateTexture(nil, "BACKGROUND")
        hl._zui_own = true
        hl:SetAllPoints()
        local a = ns.Col and ns.Col("accent") or { r = 1, g = 0.82, b = 0 }
        hl:SetColorTexture(a.r, a.g, a.b, 0.25)
    end
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover._zui_own = true
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.06)
    row:SetScript("OnClick", function(_, button)
        -- right-click, or a click on the group already picked, opens or
        -- closes it; a first click picks it (and opens it)
        if hasKids and (button == "RightButton" or id == selected) then
            expanded[id] = not expanded[id]
            Refresh()
            return
        end
        if hasKids then expanded[id] = true end
        Select(id)
    end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    stack:Add(row, ROW_H)
    if hasKids and expanded[id] then
        for _, child in ipairs(kids) do TreeRow(stack, child, depth + 1, count, width) end
    end
end

-- ============================================================
-- THE RIGHT-HAND PANE
-- ============================================================
local TABS = {
    { key = "display",  label = "Display",    build = "Display" },
    { key = "text",     label = "Text",       build = "Text" },
    { key = "triggers", label = "Triggers",   build = "Triggers" },
    { key = "cond",     label = "Conditions", build = "Conditions" },
    { key = "actions",  label = "Actions",    build = "Actions" },
    { key = "anim",     label = "Anim",       build = "Animations" },
    { key = "load",     label = "Load",       build = "Load" },
    { key = "config",   label = "Config",     build = "Config" },
    { key = "group",    label = "Group",      build = "Group", groupOnly = true },
}
local BY_KEY = {}
for _, t in ipairs(TABS) do BY_KEY[t.key] = t end

local function TabBar(stack, width, isGroup)
    local usable = width - 16
    local list = {}
    for _, t in ipairs(TABS) do
        if not t.groupOnly or isGroup then list[#list + 1] = t end
    end
    local perRow = math.max(1, math.min(#list, math.floor(usable / 64)))
    local w = math.floor(usable / perRow)
    local col, rows = 0, 1
    for _, t in ipairs(list) do
        local b = UI.Button(stack.p, t.label, { width = w - 2, height = 20,
            onClick = function() tab = t.key propScroll = 0 Refresh() end })
        b:SetPoint("TOPLEFT", stack.p, "TOPLEFT", stack.x + col * w, stack.y - (rows - 1) * 22)
        if t.key == tab and b._zText then b._zText:SetTextColor(1, 0.82, 0.2) end
        col = col + 1
        if col >= perRow then col, rows = 0, rows + 1 end
    end
    if col == 0 then rows = rows - 1 end
    stack.y = stack.y - rows * 22 - 6
end

local function ButtonRow(stack, width, defs)
    local row = CreateFrame("Frame", nil, stack.p)
    row:SetSize(width - 16, 24)
    local x = 0
    for _, def in ipairs(defs) do
        local b = UI.Button(row, def[1], { width = def[2], onClick = def[3], tooltip = def[4] })
        b:SetPoint("LEFT", row, "LEFT", x, 0)
        x = x + def[2] + 4
    end
    stack:Add(row, 28)
    return row
end

-- a box of text to copy or paste (strings are long; it scrolls)
local function TextBox(stack, width, height, text, onChange, selectOnFocus)
    local box = UI.TextBox(stack.p, { width = width - 24, height = height, text = text or "",
        onChange = onChange, selectOnFocus = selectOnFocus })
    stack:Add(box, height + 6)
    return box
end

local function ImportPane(stack, width)
    stack:Section("Import")
    stack:Label("Paste an aura string (\"!WA:2!...\"). It is added to your library; nothing you have is replaced - a name that is taken gets a number after it.")
    local box = TextBox(stack, width, 120, importText, function(t) importText = t end)
    ButtonRow(stack, width, {
        { "Import", 90, function()
            local text = box.editBox and box.editBox:GetText() or importText
            local id, err = E.Import(text)
            if not id then Print("|cffff6666Could not import:|r " .. tostring(err)) return end
            importText = ""
            Print("Imported " .. tostring(id) .. ".")
            iconCache = {}
            tab = "display"
            local root = id
            local p = E.data[root] and E.data[root].parent
            if p then expanded[p] = true end
            expanded[id] = true
            Select(id)
        end },
        { "Clear", 70, function() importText = "" Refresh() end },
    })
end

local function Header(stack, width, id, d)
    local crest = stack.p:CreateTexture(nil, "ARTWORK")
    crest._zui_own = true
    crest:SetSize(20, 20)
    crest:SetPoint("TOPLEFT", stack.p, "TOPLEFT", stack.x, stack.y)
    crest:SetTexture(IconOf(id) or 134400)
    ZacUI.Look.CropIcon(crest, nil, nil, { look = "zacui" })
    local title = UI.Font(stack.p, F.CARD or F.LABEL or 13, { text = tostring(id), width = width - 50 })
    title:SetPoint("TOPLEFT", stack.p, "TOPLEFT", stack.x + 26, stack.y - 2)
    title:SetJustifyH("LEFT")
    stack.y = stack.y - math.max(24, (title:GetStringHeight() or 14) + 8)
    local off, live = E.IsOff(id), E.IsLoaded(id)
    local kind = d.regionType or "?"
    local inside = E.IsGroup(d) and (", " .. CountIn(id) .. " inside") or ""
    stack:Label(kind .. inside .. "  -  " .. (off and "switched off" or (live and "loaded" or "not loaded here")))
    local errs = E.errors[id]
    if errs and #errs > 0 then
        stack:Label("|cffff6666Its code reported:|r " .. tostring(errs[#errs]):sub(1, 220), nil)
    end
end

local function Properties(stack, width)
    if tab == "import" then
        ImportPane(stack, width)
        return
    end
    local id = selected
    local d = id and E.data[id]
    if not d then
        stack:Label("Pick a display on the left, or make or import one with the buttons above.")
        stack:Gap(4)
        stack:Label("Green names are loaded right now; grey ones are switched off. Right-click a group to open or close it.")
        return
    end
    Header(stack, width, id, d)
    local off = E.IsOff(id)
    ButtonRow(stack, width, {
        { off and "Switch on" or "Switch off", 84, function()
            E.SetEnabled(id, off)
            C_Timer.After(0.05, Refresh)
        end },
        { "Duplicate", 76, function()
            local newId = E.Duplicate(id)
            iconCache = {}
            if newId then Select(newId) end
        end },
        { "Export", 64, function() exportText = E.Export(id) Refresh() end },
        { "Delete", 64, function()
            local n = CountIn(id)
            local function Do()
                E.Delete(id)
                iconCache = {}
                selected = nil
                C_Timer.After(0.05, Refresh)
            end
            if UI.Confirm then
                UI.Confirm({ title = "Delete", text = "Delete '" .. tostring(id) .. "'"
                    .. (n > 0 and (" and the " .. n .. " displays inside it") or "") .. "?",
                    acceptText = "Delete", destructive = true, onAccept = Do })
            else
                Do()
            end
        end },
    })
    if exportText then
        stack:Label("Copy this string (Ctrl+A, Ctrl+C):")
        TextBox(stack, width, 90, exportText, nil, true)
    end
    -- the name
    local nameBox = UI.EditBox(stack.p, { width = width - 120, text = tostring(id), clear = false,
        onEnter = function(text)
            text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if text == "" or text == id or E.Saved().displays[text] then return end
            E.Rename(id, text)
            iconCache = {}
            Select(text)
        end })
    stack:Add(nameBox, 26)
    if E.IsGroup(d) then
        ButtonRow(stack, width, {
            { "New icon here", 100, function() local n = E.New("icon", id) expanded[id] = true iconCache = {} Select(n) end },
            { "New bar here", 92, function() local n = E.New("aurabar", id) expanded[id] = true iconCache = {} Select(n) end },
            { "New text here", 96, function() local n = E.New("text", id) expanded[id] = true iconCache = {} Select(n) end },
        })
    end
    stack:Gap(4)
    TabBar(stack, width, E.IsGroup(d))
    local spec = BY_KEY[tab] or BY_KEY.display
    if spec.groupOnly and not E.IsGroup(d) then
        tab = "display"
        spec = BY_KEY.display
    end
    local builder = E.Options and E.Options[spec.build]
    if not builder then return end
    local ok, options = pcall(builder, d)
    if not ok or type(options) ~= "table" then
        stack:Label("Could not build these settings: " .. tostring(options), nil, 0.85, 0.5, 0.5)
        return
    end
    -- structural edits (add / remove a trigger, change a type) redraw the
    -- pane; plain field edits do not
    local stats = ns.RenderAceOptions(stack, options, width, function()
        iconCache[id] = nil
        C_Timer.After(0.05, Refresh)
    end)
    if stats.drawn == 0 and stats.skipped == 0 then stack:Label("Nothing to set here for this display.") end
    if stats.skipped > 0 then
        stack:Label("|cffffcc00" .. stats.skipped .. " setting(s) this page cannot draw yet.|r")
    end
end

-- ============================================================
-- RENAME (keeps the parent's list and every child pointing right)
-- ============================================================
function E.Rename(id, newId)
    local sv = E.Saved().displays
    local d = sv[id]
    if not d or sv[newId] then return false end
    if E.SetPreview then E.SetPreview(nil) end
    -- its frames (and, for a group, those of everything in it) go; the
    -- data moves to the new name and is built again from there
    local all = E.Descendants(id)
    for _, x in ipairs(all) do E.Drop(x) end
    E.Drop(id)
    if E.Groups.list[id] then
        E.Groups.list[id].frame:Hide()
        E.Groups.list[id] = nil
    end
    sv[id] = nil
    d.id = newId
    sv[newId] = d
    if d.parent and sv[d.parent] and type(sv[d.parent].controlledChildren) == "table" then
        local kids = sv[d.parent].controlledChildren
        for i, c in ipairs(kids) do if c == id then kids[i] = newId end end
    end
    if type(d.controlledChildren) == "table" then
        for _, c in ipairs(d.controlledChildren) do if sv[c] then sv[c].parent = newId end end
    end
    E.Rebuild(newId, true)
    for _, x in ipairs(all) do E.Rebuild(x) end
    return true
end

-- ============================================================
-- THE PAGE
-- ============================================================
-- the preview goes when the page does
local watch
local function WatchPage()
    if watch then return end
    watch = C_Timer.NewTicker(0.5, function()
        local open = ns.ConfigIsOpen and ns.ConfigIsOpen()
        local st = ns.ConfigState and ns.ConfigState()
        if not open or (st and st.selected ~= "auras") then
            if E.SetPreview then E.SetPreview(nil) end
            E.optionsOpen = false
            watch:Cancel()
            watch = nil
        end
    end)
end

RegisterPage("Auras", function(L)
    L:Header("Aura engine", "Your auras - in the WeakAuras format, run by ZacUI's own engine.")
    local Auras = ns.Auras
    if not E.started then
        L:Notice("warn", "The aura engine has not started yet (it starts at login).")
        return
    end
    E.optionsOpen = true
    WatchPage()
    -- a string handed over by another import box waits in ours
    if type(E.pendingImport) == "string" then
        importText = E.pendingImport
        E.pendingImport = nil
        tab = "import"
    end
    if E.selectRequest and E.data[E.selectRequest] then
        selected = E.selectRequest
        E.selectRequest = nil
    end

    -- the switch, for going back to WeakAuras itself
    if Auras and Auras.Status then
        local s = Auras.Status()
        if s.upstreamHas then
            L:Card("Switch")
            local cb = UI.Checkbox(L.current, "Use ZacUI's aura engine", s.want and true or false,
                function(v) Auras.SetEnabled(v) end)
            L:Row(cb, 17)
            L:Desc("Off switches WeakAuras itself back on instead. Takes effect on /reload.")
            L:EndCard()
        end
    end

    -- auras whose code is failing
    local bad = {}
    for id, list in pairs(E.errors) do
        if E.data[id] and E.loaded[id] and #list > 0 then bad[#bad + 1] = id end
    end
    table.sort(bad)
    if #bad > 0 then
        L:Card("Auras reporting errors")
        L:Desc(#bad .. " loaded aura(s) had their own code fail. The aura keeps running; the error is kept here instead of spamming the error window.")
        local lines = {}
        for i = 1, math.min(6, #bad) do
            local list = E.errors[bad[i]]
            lines[#lines + 1] = bad[i] .. ": " .. tostring(list[#list]):sub(1, 120)
        end
        if #bad > 6 then lines[#lines + 1] = "... and " .. (#bad - 6) .. " more" end
        L:Desc(table.concat(lines, "\n"))
        local clear = UI.Button(L.current, "Clear the list", { width = 120, onClick = function()
            wipe(E.errors)
            Refresh()
        end })
        L:Row(clear, 26)
        L:EndCard()
    end

    -- the strip
    local total, loaded = 0, 0
    for id, d in pairs(E.data) do
        if not E.IsGroup(d) then
            total = total + 1
            if E.loaded[id] then loaded = loaded + 1 end
        end
    end
    local roots = Roots()
    L:Card("Auras")
    L:Desc(total .. " auras in " .. #roots .. " top-level entries, " .. loaded .. " loaded now. Most being asleep is normal - auras load by class, zone, boss and group.")
    -- (one row that wraps onto a second line in a narrow window)
    local bar = L.current
    local strip = {}
    local search = UI.EditBox(bar, { width = 120, text = filter, hint = "Search",
        onEnter = function(text) filter = text or "" Refresh() end })
    strip[#strip + 1] = search
    local function Btn(label, w, fn)
        local b = UI.Button(bar, label, { width = w, onClick = fn })
        strip[#strip + 1] = b
        return b
    end
    Btn("Icon", 46, function() local id = E.New("icon") iconCache = {} tab = "display" Select(id) end)
    Btn("Bar", 40, function() local id = E.New("aurabar") iconCache = {} tab = "display" Select(id) end)
    Btn("Text", 44, function() local id = E.New("text") iconCache = {} tab = "display" Select(id) end)
    Btn("Group", 52, function() local id = E.New("dynamicgroup", nil, "New group") iconCache = {} tab = "group" Select(id) end)
    -- the other kinds WeakAuras has, in one list
    local more = UI.Dropdown(bar, { width = 74,
        items = function()
            return { { text = "Texture", value = "texture" }, { text = "Progress texture", value = "progresstexture" },
                { text = "Stop motion", value = "stopmotion" }, { text = "Model", value = "model" },
                { text = "Empty", value = "empty" }, { text = "Group (static)", value = "group" } }
        end,
        onSelect = function(kind)
            local id = E.New(kind, nil, kind == "group" and "New group" or nil)
            iconCache = {}
            tab = (kind == "group") and "group" or "display"
            Select(id)
        end })
    more:SetText("More")
    strip[#strip + 1] = more
    local imp = Btn("Import", 58, function() tab = "import" selected = nil if E.SetPreview then E.SetPreview(nil) end Refresh() end)
    if tab == "import" and imp._zText then imp._zText:SetTextColor(1, 0.82, 0.2) end
    Btn(E.paused and "Resume" or "Pause", 62, function() E.SetPaused(not E.paused) C_Timer.After(0.05, Refresh) end)
    L:Flow(strip, 4, 6)

    -- the split
    local split = UI.Holder(L.current)
    split:SetHeight(SPLIT_H)
    L:Row(split, SPLIT_H + 6)
    split:SetPoint("RIGHT", L.current, "RIGHT", -M.CONTROL_X, 0)

    -- the tree takes up to LEFT_W, less in a narrow window so the pane
    -- beside it keeps room to draw
    local leftW = math.max(140, math.min(LEFT_W, L:Room() - 6 - 4 - M.SCROLL_W - 200))
    local left = UI.Box(split, "ui", "elementBg")
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(leftW)
    local lScroll, lChild = UI.ScrollArea(left)
    lScroll:SetPoint("TOPLEFT", 2, -2)
    lScroll:SetPoint("BOTTOMRIGHT", -(M.SCROLL_W + 2), 2)
    lChild:SetWidth(leftW - M.SCROLL_W - 8)
    lScroll.bar:SetPoint("TOPRIGHT", left, "TOPRIGHT", -2, -2)
    lScroll.bar:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -2, 2)

    local right = UI.Box(split, "ui", "elementBg")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    local rScroll, rChild = UI.ScrollArea(right)
    rScroll:SetPoint("TOPLEFT", 2, -2)
    rScroll:SetPoint("BOTTOMRIGHT", -(M.SCROLL_W + 2), 2)
    rScroll.bar:SetPoint("TOPRIGHT", right, "TOPRIGHT", -2, -2)
    rScroll.bar:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -2, 2)

    local treeW = leftW - M.SCROLL_W - 12
    local lStack = NewStack(lChild, 4, treeW)
    local count = { n = 0 }
    if filter ~= "" then
        local needle = filter:lower()
        local hits = {}
        for id in pairs(E.data) do
            if tostring(id):lower():find(needle, 1, true) then hits[#hits + 1] = id end
        end
        table.sort(hits, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
        for _, id in ipairs(hits) do TreeRow(lStack, id, 0, count, treeW) end
        if #hits == 0 then lStack:Label("No matches.", treeW) end
    else
        local live, rest = {}, {}
        for _, id in ipairs(roots) do
            if E.IsLoaded(id) then live[#live + 1] = id else rest[#rest + 1] = id end
        end
        if #live > 0 then
            lStack:Section("Loaded  (" .. #live .. ")", treeW)
            for _, id in ipairs(live) do TreeRow(lStack, id, 0, count, treeW) end
        end
        if #rest > 0 then
            lStack:Section("Not loaded  (" .. #rest .. ")", treeW)
            for _, id in ipairs(rest) do TreeRow(lStack, id, 0, count, treeW) end
        end
    end
    if count.n >= ROW_CAP then lStack:Label("(more not shown - search to find them)", treeW) end
    lChild:SetHeight(math.max(lStack:Height(), 10))
    if lScroll.Recalculate then lScroll:Recalculate() end
    if lScroll.SetVerticalScroll then pcall(lScroll.SetVerticalScroll, lScroll, treeScroll) end
    if lScroll.bar and lScroll.bar.HookScript then
        lScroll.bar:HookScript("OnValueChanged", function(_, v) treeScroll = v end)
    end

    -- the pane's own width (the split spans the card; the tree takes leftW)
    local rWidth = math.max(160, L:Room() - leftW - 6 - 4 - M.SCROLL_W)
    rChild:SetWidth(rWidth)
    local rStack = NewStack(rChild, 8, rWidth - 22)
    local ok, err = pcall(Properties, rStack, rWidth)
    if not ok then rStack:Label("|cffff6666This pane failed to draw:|r " .. tostring(err)) end
    rChild:SetHeight(math.max(rStack:Height(), 10))
    if rScroll.Recalculate then rScroll:Recalculate() end
    if rScroll.SetVerticalScroll then pcall(rScroll.SetVerticalScroll, rScroll, propScroll) end
    if rScroll.bar and rScroll.bar.HookScript then
        rScroll.bar:HookScript("OnValueChanged", function(_, v) propScroll = v end)
    end
    L:EndCard()
end)
