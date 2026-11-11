-- RM_Config - the Raid mods page: the engine's switches, each raid's
-- units on and off, the packs' own options, anchors and test mode.
-- Part of ZacUI; load order is set by the TOC.

local ns = _G.ZacUI
if not ns then return end
local RM = ns.RaidMods
if not RM then return end

local RegisterPage = ns.RegisterPage
local UI = ns.UI
if not (RegisterPage and UI) then return end
local M, F = UI.M, UI.F
local Print = RM.Print

-- the words people type that are not on the page
if ns.AddMenuKeywords then
    ns.AddMenuKeywords("raidmods", "bar bars label labels timer timers time format position anchor corner offset dbm bigwigs "
        .. "warning warnings callout callouts icon icons glow flash circle circles nameplate nameplates frames razuvious")
end

-- ============================================================
-- NAMES
-- ============================================================
local RAID_TAGS = { "%[MC%-Classic%]", "%[MC%]", "%[BWL%]", "%[AQ40%]", "%[NX%]", "%[ZG%]", "%[T3%]" }
-- The pull-timer pieces keep the names they were saved under (the old
-- pack's name in them); shown without it.
local function NoPackName(s)
    return (s:gsub("Fojji %- ", ""):gsub("Fojji ", ""))
end
local function CleanId(id)
    local s = NoPackName(id)
    local lead = false
    s = s:gsub("^%u+:", "")
    if s:find("^%[RAIDLEAD%]") or s:find("^%[RL%]") then lead = true s = s:gsub("^%[RAIDLEAD%]", ""):gsub("^%[RL%]", "") end
    for _, t in ipairs(RAID_TAGS) do s = s:gsub("^" .. t .. ":?%s*", "") end
    s = s:gsub("^%s+", "")
    local boss, rest = s:match("^%[([^%]]+)%]%s*(.*)$")
    if boss then s = boss .. ": " .. rest end
    if lead then s = s .. " (raid lead)" end
    return s
end
RM.CleanId = CleanId
local function CleanGroup(key)
    local s = NoPackName(key)
    local kind = s:match("^(%u+):")
    s = s:gsub("^%u+:", "")
    for _, t in ipairs(RAID_TAGS) do s = s:gsub("^" .. t .. ":?%s*", "") end
    s = s:gsub("^%s+", "")
    local boss, rest = s:match("^%[([^%]]+)%]%s*(.*)$")
    if boss then s = boss .. ": " .. rest end
    if kind == "RF" then s = s .. " (raid frames)" elseif kind == "N" then s = s .. " (nameplates)" end
    return s
end

-- ============================================================
-- HELPERS
-- ============================================================
local function Check(L, label, value, onToggle, desc, indent)
    -- indent = true: one step in under the option above (the extras card
    -- passes that; a bare true reached L:Row as an x and broke the page)
    if indent == true then indent = M.CONTROL_X + 18 end
    local w = UI.Checkbox(L.current, label, value and true or false, onToggle)
    L:Row(w, 17, indent)
    if desc then L:Desc(desc) end
    return w
end

local function Slider(L, opts)
    local w = UI.Slider(L.current, opts)
    L:Row(w, 40)
    if opts.desc then L:Desc(opts.desc) end
    return w
end

local function Button(L, text, onClick, width)
    local b = UI.Button(L.current, text, { width = width or 160, onClick = onClick })
    L:Row(b, M.BUTTON_H + 6)
    return b
end

local function ReloadAll()
    RM.UnloadAll()
    RM.ScanForLoads()
end

-- ============================================================
-- PACK OPTIONS (the authors' own settings, from authorOptions)
-- ============================================================
local function Saved(def)
    local db = RM.DB()
    db.config[def.id] = db.config[def.id] or {}
    return db.config[def.id]
end
local function Current(def, path)
    -- the live value: saved override, else the pack's shipped value
    local function Walk(t)
        for _, k in ipairs(path) do
            if type(t) ~= "table" then return nil end
            t = t[k]
        end
        return t
    end
    local v = Walk(Saved(def))
    if v == nil then v = Walk(def.config or {}) end
    return v
end
local function Set(def, path, value)
    local t = Saved(def)
    for i = 1, #path - 1 do
        if type(t[path[i]]) ~= "table" then t[path[i]] = {} end
        t = t[path[i]]
    end
    t[path[#path]] = value
    RM.ReloadUnit(def.id)
end

local function OptionRows(L, def, options, path, depth)
    local indent = M.CONTROL_X + depth * 16
    for _, o in ipairs(options) do
        local t = o.type
        local p = {}
        for i, k in ipairs(path) do p[i] = k end
        if o.key then p[#p + 1] = o.key end
        local name = (o.name or o.key or ""):gsub("|T[^|]*|t", "")
        if t == "toggle" then
            local v = Current(def, p)
            if v == nil then v = o.default end
            Check(L, name, v, function(on) Set(def, p, on and true or false) end, o.useDesc and o.desc or nil, indent)
        elseif t == "range" or t == "number" then
            local v = tonumber(Current(def, p)) or tonumber(o.default) or 0
            local minv, maxv = tonumber(o.min) or tonumber(o.softMin) or 0, tonumber(o.max) or tonumber(o.softMax) or math.max(100, v)
            local step = tonumber(o.step) or tonumber(o.bigStep) or ((maxv - minv) >= 20 and 1 or 0.1)
            Slider(L, { width = 220, min = minv, max = maxv, step = step, value = v, label = name,
                format = function(x) if step >= 1 then return string.format("%d", x) end return string.format("%.1f", x) end,
                onChange = function(x) Set(def, p, x) end, desc = o.useDesc and o.desc or nil })
        elseif t == "select" then
            local values = o.values or {}
            local v = Current(def, p) or o.default or 1
            local dd = UI.Dropdown(L.current, { width = 220,
                items = function()
                    local items = {}
                    for i, label in ipairs(values) do items[#items + 1] = { text = tostring(label), value = i } end
                    return items
                end,
                selected = function() return tostring(values[tonumber(v) or 1] or "") end,
                onSelect = function(x) v = x Set(def, p, x) end })
            L:Row(dd, 26, indent)
            L:Desc(name)
        elseif t == "input" then
            local v = Current(def, p)
            if v == nil then v = o.default end
            local eb = UI.EditBox(L.current, { width = 220, text = tostring(v or ""),
                onEnter = function(txt) Set(def, p, txt) end })
            L:Row(eb, M.EDIT_H + 6, indent)
            L:Desc(name .. " (Enter to apply)")
        elseif t == "color" then
            local b = UI.Button(L.current, name, { width = 220, onClick = function()
                local cur = Current(def, p) or o.default or { 1, 1, 1, 1 }
                local function Commit()
                    local r, g, bb = ColorPickerFrame:GetColorRGB()
                    Set(def, p, { r, g, bb, cur[4] or 1 })
                end
                if ColorPickerFrame.SetupColorPickerAndShow then
                    ColorPickerFrame:SetupColorPickerAndShow({ r = cur[1], g = cur[2], b = cur[3], swatchFunc = Commit, cancelFunc = function() end })
                else
                    ColorPickerFrame:Hide()
                    ColorPickerFrame.func = Commit
                    ColorPickerFrame.cancelFunc = function() end
                    ColorPickerFrame:SetColorRGB(cur[1] or 1, cur[2] or 1, cur[3] or 1)
                    ColorPickerFrame:Show()
                end
            end })
            L:Row(b, M.BUTTON_H + 6, indent)
        elseif t == "header" then
            if o.useName and o.text and o.text ~= "" then L:Desc("|cffffd100" .. o.text:gsub("|T[^|]*|t", "") .. "|r") end
        elseif t == "description" then
            if o.text and o.text ~= "" then L:Desc((o.text:gsub("|T[^|]*|t", ""))) end
        elseif t == "space" then
            L:Gap(4)
        elseif t == "group" then
            if o.groupType == "array" then
                L:Desc("|cffffd100" .. name .. "|r - a list option; edit it in game is not supported yet, the pack's own values are used.")
            else
                L:Desc("|cffffd100" .. name .. "|r")
                OptionRows(L, def, o.subOptions or {}, p, depth + 1)
            end
        end
    end
end

-- ============================================================
-- THE PREVIEW - three timer bars as the packs draw them (the engine's own
-- Build / Setup / sub-text code, RM.Widgets.NewSample), counting down
-- round and round
-- ============================================================
local function Sub(point, text, x, fmt)
    return { type = "subtext", anchor_point = point, text_text = text, text_anchorXOffset = x or 0,
        text_font = "Barlow Semi Condensed Black", text_fontSize = 12, text_fontType = "OUTLINE", text_color = { 1, 1, 1, 1 },
        text_shadowColor = { 0, 0, 0, 1 }, text_shadowXOffset = 1, text_shadowYOffset = -1, text_automaticWidth = "Auto",
        text_justify = "CENTER", text_selfPoint = "AUTO", text_visible = true,
        fmt = { p = fmt or { format = "timed", time_dynamic_threshold = 10, time_precision = 1 } } }
end
local BORDER_BAR = { type = "subborder", anchor_area = "bar", border_color = { 0, 0, 0, 1 }, border_size = 1, border_visible = true }
local BORDER_ICON = { type = "subborder", anchor_area = "icon", border_color = { 0, 0, 0, 1 }, border_size = 1, border_visible = true }
local function BarD(w, h, color, subs)
    return { regionType = "aurabar", width = w, height = h, icon = true, icon_side = "LEFT", zoom = 0.32,
        texture = "ZacUI Flat", textureSource = "LSM", barColor = color, backgroundColor = { 0, 0, 0, 0.36 },
        orientation = "HORIZONTAL", frameStrata = 1, subRegions = subs }
end
local SAMPLE_BARS = {
    { D = BarD(220, 20, { 0.31, 0.65, 1, 0.75 }, { BORDER_BAR, BORDER_ICON, Sub("RIGHT", "%p"), Sub("LEFT", "%n", 5) }),
      name = "Living Bomb", left = 14.2, dur = 30, icon = 135826 },
    { D = BarD(220, 20, { 0.31, 0.65, 1, 0.75 }, { BORDER_BAR, BORDER_ICON, Sub("RIGHT", "%p"), Sub("LEFT", "%n", 5) }),
      name = "Inferno", left = 4.6, dur = 20, icon = 135805 },
    { D = BarD(200, 18, { 1, 0.42, 0.44, 1 }, { BORDER_BAR, Sub("RIGHT", "%p",
        0, { format = "timed", time_dynamic_threshold = 5, time_precision = 1, time_legacy_floor = true }), Sub("CENTER", "Berserk") }),
      name = "Berserk", left = 245, dur = 600, icon = 136224 },
}
-- an alert text and a three-line list (a pack's name list), the engine's
-- own text displays; the list laid out by RM_Anchors' own Arrange with the
-- group picked under Lists (its saved layout on top)
local function TextD(size, color, text)
    return { regionType = "text", displayText = text, font = "Barlow Semi Condensed Black", fontSize = size, outline = "OUTLINE",
        color = color, justify = "CENTER", automaticWidth = "Auto", shadowColor = { 0, 0, 0, 1 },
        shadowXOffset = 1, shadowYOffset = -1 }
end
local SAMPLE_ALERT = TextD(20, { 1, 0.82, 0, 1 }, "Living Bomb on YOU!")
local SAMPLE_LIST = { TextD(13, { 1, 1, 1, 1 }, "Mortal Wound: Brakka 3"), TextD(13, { 1, 1, 1, 1 }, "Mortal Wound: Tovren 2"),
    TextD(13, { 1, 1, 1, 1 }, "Mortal Wound: Holgrim 1") }
local SAMPLE_GROUP = { key = "__sample__", name = "Sample list", kind = "dynamicgroup", grow = "DOWN", space = 2, align = "LEFT" }
-- a piece whose group stands on its own (circles, the "on you" pictures):
-- by itself, in the middle
local SAMPLE_GROUP_ONE = { key = "__sample1__", name = "Sample", kind = "dynamicgroup", grow = "DOWN", space = 2, align = "CENTER" }
local MODE_SET, BuildModes, HideModes, UpdateMode   -- the modes, below
local function ListGroups()
    local out = {}
    for key, g in pairs(RM.groups or {}) do
        if type(g) == "table" and g.kind == "dynamicgroup" and not g.zuiPlate then out[#out + 1] = { key = key, name = g.name or key } end
    end
    table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return out
end
local function PickedList()
    local k = ZacUIDB.config and ZacUIDB.config.rmList
    if k and RM.groups and RM.groups[k] then return k end
    local all = ListGroups()
    -- nothing picked yet: the first of the packs' own lists, else the first group
    for _, g in ipairs(all) do
        if tostring(g.name):find("Lists", 1, true) then return g.key end
    end
    return all[1] and all[1].key or nil
end

-- ============================================================
-- THE OTHER MODES - every other thing the packs draw, each from a real
-- piece of the packs: its own display, drawn by the engine's own Build /
-- Setup / sub texts / borders / glows / animations (RM.Widgets samples),
-- wearing its own conditions' looks, laid out by its group's own Arrange
-- (RM.Layout.ArrangeSample, with that group's saved layout on top), with
-- made-up players and times counting down round and round.
-- ============================================================
local NAMES = { "Brakka", "Tovren", "Holgrim", "Myrell", "Senna", "Dorvak" }
local PREVIEW_MODES = {
    { id = "overview", label = "Overview" },
    { id = "warnings", label = "Big warnings" },
    { id = "callouts", label = "Call-outs" },
    { id = "icons", label = "Icons" },
    { id = "lists", label = "Lists" },
    { id = "bars", label = "Ability bars" },
    { id = "circles", label = "Circles" },
    { id = "onyou", label = "On you" },
    { id = "raidframes", label = "On raid frames" },
    { id = "plates", label = "On nameplates" },
    { id = "raz", label = "Razuvious on you" },
    { id = "boss", label = "Boss on you" },
}
-- each mode's pieces (left = seconds left when it starts, dur = its full
-- time); group = the container's group when it is not the first piece's
local MODE_PIECES = {
    warnings = { pieces = {
        { id = "SW:[NX][Anub] Locust Swarm PreWarn", left = 7.5, dur = 20 },
        { id = "SW:[AQ40][Twin Emperors] Teleport", left = 3, dur = 3 } } },
    callouts = { pieces = {
        { id = "SA:[BWL][All] GTFO", left = 2, dur = 2 },
        { id = "SA:[AQ40][Trash] Plague", left = 6.2, dur = 8 } } },
    icons = { pieces = {
        { id = "A:[BWL][Ebonroc] Shadow of Ebonroc", left = 4.4, dur = 8 },
        { id = "A:[MC-Classic][Gehennas] Sunder Armor >4", left = 21, dur = 30, stacks = 5 },
        { id = "A:[BWL][Nefarian] Veil of Shadow", left = 3.1, dur = 6 } } },
    bars = { pieces = {
        { id = "PC:[AQ40][C'thun] Dark Glare", left = 8.4, dur = 40 },
        { id = "PC:[BWL][Ebonroc] Wing Buffet", left = 18.5, dur = 30, count = 3 } } },
    circles = { pieces = { { id = "C:[AQ40][Ouro] Sweep PreWarn", left = 4.6, dur = 10 } } },
    onyou = { pieces = { { id = "CH:[NX][4HM] Void Zone Warn", left = 3, dur = 4 } } },
    raidframes = { pieces = {
        { id = "RF:[ZG][Thekal] Mortal Cleave", left = 5.2, dur = 8 },
        { id = "RF:[ZG][Thekal] Gouge", left = 2.4, dur = 4 },
        { id = "RF:[ZG][Thekal] Blind", left = 7.5, dur = 10 } } },
    plates = { group = "ZUI:PlateStrip", pieces = {
        { id = "N:[AQ40][Sartura] WW", left = 6, dur = 15 },
        { id = "N:[BWL][Chromaggus] Frenzy", left = 8, dur = 10 } } },
}
-- the Lists mode: the list picked under Lists, its first piece once per
-- made-up player, the most stacks first
local LIST_FALLBACK = "L:[AQ40][Fankriss] Mortal Wound"
MODE_SET = {}
for _, m in ipairs(PREVIEW_MODES) do MODE_SET[m.id] = true end
RM.PREVIEW_MODES, RM.MODE_PIECES, RM.LIST_FALLBACK = PREVIEW_MODES, MODE_PIECES, LIST_FALLBACK
-- the strip's own samples, so the TBC raids can name theirs (Own\TBC_Kit)
RM.SAMPLE_BARS, RM.SAMPLE_ALERT = SAMPLE_BARS, SAMPLE_ALERT

-- the icon a piece's trigger would hand it in game (its spell's)
local function PieceIcon(def)
    local tr = def.triggers and def.triggers[1]
    if not (tr and GetSpellTexture) then return nil end
    local id = (type(tr.spellId) == "table" and tr.spellId[1]) or (type(tr.ids) == "table" and tr.ids[1])
        or (type(tr.names) == "table" and tr.names[1])
    id = tonumber(id)
    return id and GetSpellTexture(id) or nil
end
local function ListPieces()
    local gkey = PickedList()
    local first
    for _, def in pairs(RM.units or {}) do
        if def.group == gkey and def.display and not (RM.IsSilent and RM.IsSilent(def)) then
            if not first or (def.order or 0) < (first.order or 0) or ((def.order or 0) == (first.order or 0) and def.id < first.id) then first = def end
        end
    end
    if not first then first = RM.units and RM.units[LIST_FALLBACK] end
    if not first then return nil end
    local out = {}
    for i = 1, 4 do
        out[i] = { id = first.id, left = 4 + i * 3.5, dur = 20, stacks = 5 - i, name = NAMES[i] }
    end
    return { pieces = out, group = first.group }
end

BuildModes = function(canvas, P)
    local st = P.store
    local host = CreateFrame("Frame", nil, canvas)
    host:SetPoint("CENTER")
    host:SetSize(1, 1)
    host:Hide()
    st.mhost, st.mpool, st.mused, st.mlive = host, {}, {}, {}
    -- the sample container: what RM_Anchors' Arrange lays out
    local c = CreateFrame("Frame", nil, host)
    c.members = {}
    c:SetPoint("CENTER")
    c:SetSize(1, 1)
    if ns.TagElement then ns.TagElement(c, "raidmods.list") end
    st.mc = c
    st.mnote = UI.Font(host, F.SMALL, { text = "", cat = "text", key = "gray" })
    st.mnote:Hide()
    -- Instructor Razuvious: the Extras alert's own constructor
    if RM.Extras and RM.Extras.NewRazSample then
        st.raz = RM.Extras.NewRazSample(host)
        -- any raid boss: the same alert, a boss's name and the skull
        st.boss = RM.Extras.NewRazSample(host)
    end
    -- the clock: every frame what moves smoothly (bar fill, swipes, the
    -- animations), ten times a second the texts, conditions and glow pulse
    local acc = 0
    host:SetScript("OnUpdate", function(_, el)
        local W = RM.Widgets
        acc = acc + (el or 0)
        local slow = acc >= 0.1
        if slow then acc = 0 end
        local now = GetTime()
        for _, w in ipairs(st.mlive) do
            local s = w.state
            if slow and s and s.progressType == "timed" and s.expirationTime and s.expirationTime <= now then
                s.expirationTime = now + (w.pvLeft or s.duration or 10)
            end
            W.TickSample(w, not slow)
        end
    end)
end
HideModes = function(P)
    local st = P.store
    if not st.mhost then return end
    for _, w in ipairs(st.mlive) do RM.Widgets.StopSample(w) end
    st.mhost:Hide()
end
local function Take(st, kind)
    local pool = st.mpool[kind]
    if not pool then pool = {} st.mpool[kind] = pool end
    local n = (st.mused[kind] or 0) + 1
    st.mused[kind] = n
    local w = pool[n]
    if not w then
        w = RM.Widgets.NewSample(st.mc, kind)
        pool[n] = w
    end
    return w
end
-- the box of what the mode draws, the canvas made that box
local function FitHost(canvas, P, host, fallbackW, fallbackH)
    local cx, cy, w, h
    if P.Measure then cx, cy, w, h = P.Measure(host) end
    host:ClearAllPoints()
    if cx then
        host:SetPoint("CENTER", canvas, "CENTER", -cx, -cy)
    else
        host:SetPoint("CENTER")
        w, h = fallbackW, fallbackH
    end
    local cw2, ch2 = math.max(40, (w or 40) + 16), math.max(24, (h or 24) + 12)
    P.store.pvH = ch2
    if P.Resize then P.Resize(cw2, ch2) end
end
-- the smallest text a sample shows (its own size, before any scaling)
local function MinText(w, m)
    local D = w.D
    if w.kind == "text" and w.text and (w.text:GetText() or "") ~= "" then m = math.min(m, tonumber(D.fontSize) or 12) end
    for i, sub in ipairs(D.subRegions or {}) do
        local fs = w.texts and w.texts[i]
        if sub.type == "subtext" and fs and fs:IsShown() and (fs:GetText() or "") ~= "" then
            m = math.min(m, tonumber(sub.text_fontSize) or 12)
        end
    end
    return m
end
local function Off(P)
    local db = RM.DB()
    if not db.enabled then return "Off: raid mods are turned off" end
    if P.mode == "lists" and not db.lists then return "Off: Lists is turned off above" end
    if P.mode == "raz" then
        local x = RM.Extras and RM.Extras.DB and RM.Extras.DB()
        if x and not x.razTarget then return "Off: turned off on the Extras card" end
    end
    if P.mode == "boss" then
        local x = RM.Extras and RM.Extras.DB and RM.Extras.DB()
        if x and not x.bossTarget then return "Off: turned off on the Extras card" end
    end
    return nil
end
UpdateMode = function(canvas, P)
    local W, st = RM.Widgets, P.store
    local host, c = st.mhost, st.mc
    host:Show()
    local off = Off(P)
    -- Instructor Razuvious's alert, and the same alert for any raid boss
    if P.mode == "raz" or P.mode == "boss" then
        for _, w in ipairs(st.mlive) do W.StopSample(w) w:Hide() end
        st.mlive = {}
        c:Hide()
        local f = (P.mode == "boss") and st.boss or st.raz
        local other = (P.mode == "boss") and st.raz or st.boss
        if other then other:Hide() end
        if not f then
            st.mnote:SetText("Not loaded")
            st.mnote:ClearAllPoints() st.mnote:SetPoint("CENTER", host, "CENTER") st.mnote:Show()
            st.pvMinText = 12
            FitHost(canvas, P, host, 80, 20)
            return
        end
        if P.mode == "boss" then RM.Extras.FillBossSample(f) else RM.Extras.FillRazSample(f) end
        f:ClearAllPoints()
        f:SetPoint("CENTER", host, "CENTER", 0, 0)
        if not f:IsShown() then f:Show() end
        f:SetAlpha(off and 0.35 or 1)
        st.mnote:SetText(off or "")
        st.mnote:ClearAllPoints()
        st.mnote:SetPoint("TOP", f, "BOTTOM", 0, -2)
        st.mnote:SetShown(off ~= nil)
        local sc = RM.Extras.RazScale()
        st.pvMinText = 26 * sc
        FitHost(canvas, P, host, RM.Extras.RAZ_W * sc, RM.Extras.RAZ_H * sc)
        return
    end
    if st.raz then st.raz:Hide() end
    if st.boss then st.boss:Hide() end
    c:Show()
    local spec = (P.mode == "lists") and ListPieces() or MODE_PIECES[P.mode]
    for k in pairs(st.mused) do st.mused[k] = 0 end
    local live, now = {}, GetTime()
    local first
    for i, p in ipairs(spec and spec.pieces or {}) do
        local def = RM.units and RM.units[p.id]
        local D = def and def.display
        if D and D.regionType then
            first = first or def
            local w = Take(st, D.regionType)
            local s = w.pvSt or {}
            w.pvSt = s
            -- one made-up state per sample, kept across updates so its
            -- countdown carries on
            if w.pvId ~= p.id or w.pvSeq ~= i then
                -- a pooled sample taking another piece: nothing of the old one left on it
                if w.pvId then W.StopSample(w) end
                w.pvId, w.pvSeq = p.id, i
                for k in pairs(s) do s[k] = nil end
                s.expirationTime = now + (p.left or 10)
            end
            local who = p.name or NAMES[i]
            s.show, s.preview, s.progressType, s.autoHide = true, true, "timed", false
            s.duration = p.dur or 10
            s.expirationTime = s.expirationTime or (now + (p.left or 10))
            s.name, s.unitName, s.unit, s.GUID = who, who, who, who
            s.stacks, s.count = p.stacks, p.count or p.stacks
            s.icon = PieceIcon(def)
            w.pvLeft = p.left
            w.pvInst = w.pvInst or { tstates = { [1] = {} }, def = {} }
            w.pvInst.tstates[1][""] = s
            w.pvInst.def.order, w.pvInst.def.conditions = def.order, def.conditions
            W.StyleSample(w, D, s, nil, w.pvInst)
            w.container, w.seq = c, i
            w:Show()
            live[#live + 1] = w
        end
    end
    -- whatever this mode does not use: put away
    for _, pool in pairs(st.mpool) do
        for _, w in ipairs(pool) do
            local used = false
            for _, x in ipairs(live) do if x == w then used = true break end end
            if not used and w:IsShown() then
                W.StopSample(w)
                w:Hide()
                w.state, w.container = nil, nil
            end
        end
    end
    st.mlive = live
    c.members = {}
    for i, w in ipairs(live) do c.members[i] = w end
    local gkey = spec and spec.group or (first and first.group)
    local grp = gkey and RM.groups and RM.groups[gkey]
    if not (grp and grp.kind == "dynamicgroup") then grp, gkey = SAMPLE_GROUP_ONE, nil end
    c.grp = grp
    c:SetScale(tonumber(grp.scale) or 1)
    if RM.Layout and RM.Layout.ArrangeSample then RM.Layout.ArrangeSample(c, gkey) end
    -- past the list's "most shown": not drawn (live keeps them invisible)
    for _, w in ipairs(live) do
        if w.overLimit then w:Hide() end
    end
    -- switched off: drawn dimmed (the whole container, so a pulse keeps it)
    c:SetAlpha(off and 0.35 or 1)
    c:ClearAllPoints()
    c:SetPoint("CENTER", host, "CENTER", 0, 0)
    -- measured at rest (an animation in flight carries on next frame)
    for _, w in ipairs(live) do W.RestSample(w) end
    if #live == 0 then off = "No pack piece to show" end
    local m = 99
    for _, w in ipairs(live) do if w:IsShown() then m = MinText(w, m) end end
    st.pvMinText = m < 99 and m or 12
    st.mnote:SetText(off or "")
    st.mnote:ClearAllPoints()
    st.mnote:SetPoint("TOP", c, "BOTTOM", 0, -4)
    st.mnote:SetShown(off ~= nil)
    FitHost(canvas, P, host, c:GetWidth() or 40, c:GetHeight() or 24)
end
local function ReplayPreview(canvas, P)
    local st = P.store
    if not st.mhost or not st.mhost:IsShown() then return end
    if P.mode == "raz" or P.mode == "boss" then
        local f = (P.mode == "boss") and st.boss or st.raz
        if f and f:IsShown() then f:Hide() f:Show() end
        return
    end
    for _, w in ipairs(st.mlive) do
        if w:IsShown() then RM.Widgets.PlaySample(w) end
    end
end

local function BuildPreview(canvas, P)
    local W = RM.Widgets
    local holder = CreateFrame("Frame", nil, canvas)
    holder:SetPoint("CENTER")
    P.store.holder, P.store.bars = holder, {}
    for i, s in ipairs(SAMPLE_BARS) do
        P.store.bars[i] = { w = W.NewSample(holder, "aurabar"), s = s, st = { progressType = "timed" } }
    end
    P.store.alert = W.NewSample(holder, "text")
    local list = CreateFrame("Frame", nil, holder)
    list.members = {}
    for i = 1, #SAMPLE_LIST do
        local w = W.NewSample(list, "text")
        w.container, w.seq = list, i
        list.members[i] = w
    end
    if ns.TagElement then ns.TagElement(list, "raidmods.list") end
    P.store.list = list
    BuildModes(canvas, P)
    -- the sample's own clock (OnUpdate runs only while the strip shows)
    local acc = 0
    holder:SetScript("OnUpdate", function(_, el)
        acc = acc + (el or 0)
        if acc < 0.1 then return end
        acc = 0
        local now = GetTime()
        for _, b in ipairs(P.store.bars) do
            if b.st.expirationTime and b.st.expirationTime <= now then
                b.st.expirationTime = now + b.s.left
                b.w.state = b.st
            end
            W.TickSample(b.w)
        end
    end)
end
local function UpdatePreview(canvas, P)
    local W = RM.Widgets
    local holder = P.store.holder
    if P.mode and P.mode ~= "overview" and MODE_SET[P.mode] then
        holder:Hide()
        UpdateMode(canvas, P)
        return
    end
    HideModes(P)
    holder:Show()
    -- the bars down the left; the alert text and the list beside them on
    -- the right (the strip is wide and short: side by side, the whole
    -- sample shows at a readable size instead of being cut off)
    local y, wide = 0, 0
    local now = GetTime()
    local bars = {}
    for _, b in ipairs(P.store.bars) do
        local st, s = b.st, b.s
        st.name, st.icon, st.duration = s.name, s.icon, s.dur
        st.expirationTime = st.expirationTime or (now + s.left)
        W.StyleSample(b.w, s.D, st)
        b.w:Show()
        bars[#bars + 1] = b
        y = y + (tonumber(s.D.height) or 20) + 3
        if (tonumber(s.D.width) or 0) > wide then wide = tonumber(s.D.width) end
    end
    local barsH = math.max(0, y - 3)
    local a = P.store.alert
    local aw, ah = 0, 0
    if a then
        W.StyleSample(a, SAMPLE_ALERT, {})
        a:Show()
        aw, ah = a:GetWidth() or 0, math.max(20, a:GetHeight() or 20)
    end
    local list = P.store.list
    local lw, lh = 0, 0
    if list and RM.Layout and RM.Layout.ArrangeSample then
        local gkey = PickedList()
        list.grp = (gkey and RM.groups[gkey]) or SAMPLE_GROUP
        for i, w in ipairs(list.members) do
            W.StyleSample(w, SAMPLE_LIST[i], {})
            w:Show()
        end
        RM.Layout.ArrangeSample(list, gkey)
        lw, lh = list:GetWidth() or 0, math.max(14, list:GetHeight() or 14)
    end
    local GAP = 18
    local rightW = math.max(aw, lw)
    local rightH = (a and ah or 0) + ((a and list) and 6 or 0) + (list and lh or 0)
    local room = P.boxW or 520
    local side = (wide + GAP + rightW) <= room
    local W2, H2
    if side then
        W2, H2 = wide + GAP + rightW, math.max(barsH, rightH)
        local by = math.floor((H2 - barsH) / 2)
        for _, b in ipairs(bars) do
            b.w:ClearAllPoints()
            b.w:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -by)
            by = by + (tonumber(b.s.D.height) or 20) + 3
        end
        local rx = wide + GAP + rightW / 2
        local ry = math.floor((H2 - rightH) / 2)
        if a then
            a:ClearAllPoints()
            a:SetPoint("TOP", holder, "TOPLEFT", rx, -ry)
            ry = ry + ah + 6
        end
        if list then
            list:ClearAllPoints()
            list:SetPoint("TOP", holder, "TOPLEFT", rx, -ry)
        end
    else
        -- too narrow for both: one under the other, as before
        local yy = 0
        for _, b in ipairs(bars) do
            b.w:ClearAllPoints()
            b.w:SetPoint("TOP", holder, "TOP", 0, -yy)
            yy = yy + (tonumber(b.s.D.height) or 20) + 3
        end
        if a then
            a:ClearAllPoints()
            a:SetPoint("TOP", holder, "TOP", 0, -(yy + 4))
            yy = yy + 4 + ah + 6
        end
        if list then
            list:ClearAllPoints()
            list:SetPoint("TOP", holder, "TOP", 0, -yy)
            yy = yy + lh + 3
        end
        W2, H2 = math.max(wide, aw, lw), yy - 3
    end
    holder:SetSize(W2, H2)
    P.store.pvMinText, P.store.pvH = 12, H2 + 16
    if P.Resize then P.Resize(W2 + 16, H2 + 16) end
end

-- Where one bar text sits: ZacUI's anchor picker over db.anchors.<role>
-- (nil = where each pack put it), with the time format on the timer.
local ROLE_LABEL = { barLabel = "Bar labels (left)", barTimer = "Bar times (right)", barCenter = "Bar middle texts" }
local function RoleGroup(L, role)
    local W = RM.Widgets
    local get, set = ns.CustomAccess(RM.DB, "anchors", role, W.RefreshAll)
    local targets = {}
    for _, k in ipairs({ "bar", "icon", "region" }) do targets[#targets + 1] = { value = k, text = W.BAR_TARGETS[k] } end
    local spec = { key = "raidmods." .. role, label = ROLE_LABEL[role], anchorGet = get, anchorSet = set,
        anchorDefaults = function() return W.RoleDefaults(role) end, targets = targets,
        defaultTargetLabel = "Where the pack put it", anchorMin = -80, anchorMax = 80 }
    if role == "barTimer" then
        local fg, fs = ns.CustomAccess(RM.DB, "formats", "timer", W.RefreshAll)
        spec.formatGet, spec.formatSet, spec.formatKinds = fg, fs, { time = true }
        spec.formatDefaults = W.TIMER_FORMAT_DEFAULTS
        spec.formatSample = function(f)
            return ns.FormatTime(75, f, W.TIMER_FORMAT_DEFAULTS) .. "  " .. ns.FormatTime(4.6, f, W.TIMER_FORMAT_DEFAULTS)
        end
    end
    return UI.TextElement(L, spec)
end
local function BarTextsCard(L)
    L:Card("Timer bar texts")
    L:Desc("Every pack's bars at once. Nothing set = where each pack put them.")
    RoleGroup(L, "barLabel")
    RoleGroup(L, "barTimer")
    RoleGroup(L, "barCenter")
    L:EndCard()
end

-- ============================================================
-- THE PAGE
-- ============================================================
-- the preview card, on the General tab and at the top of every raid tab
local function PreviewCard(L, raidKey)
    local db = RM.DB()
    L:Card("Preview and move")
    L:Desc("Shows one raid's timers, warnings, icons and lists with sample values - wherever you are, no fight "
        .. "needed - and unlocks a drag handle on every anchor and group. Drag the handles where you want things "
        .. "(the content follows), then stop the preview to lock them and clear the samples. Sample timers run "
        .. "round and round.")
    local pick = raidKey or (db.testMode and db.testRaid) or RM.PreviewRaidDefault()
    if not raidKey then
        local dd = UI.Dropdown(L.current, { width = 220,
            items = function()
                local items = {}
                for _, key in ipairs(RM.raidOrder) do items[#items + 1] = { text = RM.raids[key].name, value = key } end
                return items
            end,
            selected = function() return RM.raids[pick] and RM.raids[pick].name or "" end,
            onSelect = function(v)
                pick = v
                if db.testMode then RM.SetTestMode(true, v) end
                if ns.RefreshConfig then ns.RefreshConfig() end
            end })
        L:Row(dd, 26)
        L:Desc("Which raid to preview.")
    end
    local on = db.testMode and db.testRaid == pick
    Button(L, on and "Stop preview" or ("Preview " .. (RM.raids[pick] and RM.raids[pick].name or "")), function()
        if on then RM.SetTestMode(false) else RM.SetTestMode(true, pick) end
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, 220)
    if db.testMode then
        L:Desc("|cff33ff99Preview is on|r for " .. (RM.raids[db.testRaid] and RM.raids[db.testRaid].name or "?")
            .. ". Handles are unlocked; /rm test also stops it.")
    end
    Button(L, "Reset anchors to pack positions", function()
        UI.Confirm({ title = "Reset raid mod anchors", text = "Put every raid mod anchor and group back where your packs had it?",
            onAccept = function() if RM.Layout and RM.Layout.ResetAnchors then RM.Layout.ResetAnchors() end Print("Raid mod anchors reset.") end })
    end, 220)
    L:EndCard()
end

local function General(L)
    local db = RM.DB()
    if ns.CustomPick then
        ns.CustomPick.SetHandler("raidmods.bars", function(el)
            if type(el) ~= "string" or not el:match("^raidmods%.") then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            ZacUIDB.config.tabs.raidmods = "general"
            ns.RefreshConfig()
        end)
    end
    L:Preview({
        key = "raidmods.bars",
        title = "Timer bars",
        width = 240, height = 80,
        build = BuildPreview,
        update = UpdatePreview,
        replay = ReplayPreview,
        -- (no "top part": every sample is shown whole, scaled to fit - Zac
        -- 2026-11-04 "some are cut off")
        -- (a mode with no piece on this game version - TBC's raids have no
        -- circles - is not offered: it would be an empty strip)
        modes = (function()
            local out = {}
            for _, m in ipairs(PREVIEW_MODES) do
                local mp = MODE_PIECES[m.id]
                local have = mp == nil
                if mp then
                    for _, p in ipairs(mp.pieces or {}) do
                        if RM.units and RM.units[p.id] then have = true break end
                    end
                end
                if have then out[#out + 1] = m end
            end
            return out
        end)(),
        modesLabel = "Show",
    })
    PreviewCard(L)
    L:Card("Raid mods")
    L:Desc(((RM.Own and RM.Own.flavor == "tbc")
            and "Boss mods for Karazhan, Gruul's Lair, Magtheridon's Lair, Serpentshrine Cavern, Tempest Keep, Mount Hyjal, Black Temple, Zul'Aman and the Sunwell, as part of ZacUI: "
            or "Boss mods for Molten Core, Blackwing Lair, Zul'Gurub, Temple of Ahn'Qiraj and Naxxramas, as part of ZacUI: ")
        .. "timers, warnings, icons, lists, marks on raid frames and nameplates, driven by the combat log. "
        .. "All of it is ZacUI's own addon code - nothing here is an aura, and the aura engine can stay off.")
    Check(L, "Enable raid mods", db.enabled, function(v) db.enabled = v ReloadAll() end)
    Check(L, "Sounds and voice", db.sounds, function(v) db.sounds = v RM.ApplyTTSGlobals() end,
        "Every alert sound and every spoken warning the packs play. Off also silences the text-to-speech lines.")
    Check(L, "Chat messages", db.chat, function(v) db.chat = v end,
        "The packs' own /say, /yell and raid messages (\"Living Bomb on me\" and the like).")
    Check(L, "Lists", db.lists, function(v) db.lists = v ReloadAll() end,
        "The packs' name lists - Mortal Wound List, Taunt List, Life Drain List and the rest - in every raid. "
        .. "Off by default; this one switch beats the per-list ticks on the raid tabs.")
    local cls = RM.playerClass or "?"
    local clsName = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls
    Check(L, "Berserk timers on " .. clsName .. "s", not db.berserkOff[cls], function(v)
            db.berserkOff[cls] = not v
            ReloadAll()
        end,
        "The berserk (hard enrage) timer, bars and warnings for every boss. Per class: off for warriors "
        .. "to begin with, on for everyone else.")
    L:EndCard()

    if RM.Extras and RM.Extras.BuildCard then RM.Extras.BuildCard(L, Check, Button, Slider) end

    L:Card("Look")
    L:Desc("One bar texture for every timer and list, and (if you want) one font for every text. The packs "
        .. "use flat bars and Barlow Semi Condensed Black; the Fonts & Textures page can push ZacUI's choices here too.")
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    local function Names(kind, first)
        local list = {}
        if first then list[#list + 1] = first end
        if lsm then for _, n in ipairs(lsm:List(kind)) do list[#list + 1] = { text = n, value = n } end end
        return list
    end
    local bt = UI.Dropdown(L.current, { width = 220,
        items = function() return Names("statusbar") end,
        selected = function() return db.barTexture or "ZacUI Flat" end,
        onSelect = function(v) db.barTexture = v if RM.Widgets and RM.Widgets.RefreshAll then RM.Widgets.RefreshAll() end end })
    L:Row(bt, 26)
    L:Desc("Bar texture.")
    -- one font: every pack text wears ZacUI's font (Fonts & Textures); a
    -- face picked here before is kept in db.font, and ignored
    local ft = UI.Field(L.current, "Font for every text", function(h) return UI.OneFontNote(h, 220) end, { width = 220 })
    L:Row(ft, ft:GetHeight() + 2)
    L:Desc("The bar texture follows Fonts & Textures when 'Raid mods' is ticked there.")
    L:EndCard()

    BarTextsCard(L)

    -- every pack's text displays at once (db.anchors.alertText)
    L:Card("Alert texts")
    do
        local W = RM.Widgets
        local get, set = ns.CustomAccess(RM.DB, "anchors", "alertText", W.RefreshAll)
        UI.TextElement(L, { key = "raidmods.alertText", label = "Warnings, call-outs and list lines",
            anchorGet = get, anchorSet = set, anchorDefaults = function() return W.ALERT_TEXT_DEFAULTS end,
            defaultTargetLabel = "Its own spot", anchorMin = -120, anchorMax = 120 })
    end
    L:Desc("Round the spot each pack's group or anchor gives it. Nothing set = right on it.")
    L:EndCard()

    -- one pack list's layout (db.layouts.<group>): the pack's own grow /
    -- space / limit are the defaults
    L:Card("Lists")
    local groups = ListGroups()
    if #groups == 0 then
        L:Desc("No pack with a list is loaded.")
    else
        ZacUIDB.config = ZacUIDB.config or {}
        local gkey = PickedList()
        local function Name(k) for _, g in ipairs(groups) do if g.key == k then return g.name end end return tostring(k) end
        L:Add(UI.Field(L.current, "List", function(h)
            return UI.Dropdown(h, { width = 240,
                items = function()
                    local out = {}
                    for _, g in ipairs(groups) do out[#out + 1] = { text = g.name, value = g.key } end
                    return out
                end,
                selected = function() return Name(PickedList()) end, selectedValue = PickedList,
                onSelect = function(v)
                    ZacUIDB.config.rmList = v
                    -- the strip shows that list as its pack draws it
                    if ns.ConfigPreview and ns.ConfigPreview.UseMode then ns.ConfigPreview.UseMode("raidmods.bars", "lists") end
                    ns.RefreshConfig()
                end })
        end, { width = 240 }), 8)
        local function Relay() if RM.Layout and RM.Layout.ReArrange then RM.Layout.ReArrange(gkey) end end
        local lg, ls = ns.CustomAccess(function()
            local db2 = RM.DB()
            return db2
        end, "layouts", gkey, Relay)
        local lp = UI.LayoutPicker(L.current, { width = UI.CardInnerWidth(L), get = lg, set = ls,
            fields = { grow = true, spacingX = true, spacingY = true, max = true, reverse = true },
            grows = RM.Layout and RM.Layout.LIST_GROWS or { "DOWN", "UP", "LEFT", "RIGHT" }, maxItems = 40,
            defaults = function() return RM.Layout.ListDefaults(RM.groups[gkey]) end })
        L:Add(lp, 6)
        if ns.CustomPick then ns.CustomPick.RegisterGroup("raidmods.list", lp) end
        L:Desc("Gap down: between entries of a list going down or up; gap across: left or right. "
            .. "Nothing set = the pack's own list.")
    end
    L:EndCard()

    L:Card("Anchors")
    L:Desc("Where the timers, texts, icons and lists grow from. The defaults are your own anchor positions. "
        .. "The preview above unlocks every handle; this shows the handles on their own (toggle again to lock). "
        .. "Every handle is also on the Movers page and in Edit Mode.")
    Button(L, (RM.Layout and RM.Layout.showing) and "Lock anchors" or "Show anchor handles", function()
        local show = not (RM.Layout and RM.Layout.showing)
        if RM.Layout and RM.Layout.ShowAnchors then RM.Layout.ShowAnchors(show) end
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, 200)
    L:EndCard()

    local F = ns.RaidTools
    if F and F.Settings then
        local s = F.Settings()
        L:Card("Speech")
        L:Desc("How loud and how fast the raid packs speak (the numbers the packs always read).")
        Slider(L, { width = 220, min = 0, max = 100, step = 5, value = s.ttsVolume or 75, label = "Volume",
            onChange = function(v) s.ttsVolume = v RM.ApplyTTSGlobals() end })
        Slider(L, { width = 220, min = -5, max = 5, step = 0.1, value = s.ttsRate or 1.8, label = "Rate",
            format = function(v) return string.format("%.1f", v) end,
            onChange = function(v) s.ttsRate = v RM.ApplyTTSGlobals() end })
        L:Desc("The voice is ZacUI's one voice, picked on the General page; volume and rate here are the raid packs' own.")
        Button(L, "Say a test line", function() RM.Speak("Move out") end, 160)
        L:EndCard()
    end

    L:Card("Raids")
    for _, key in ipairs(RM.raidOrder) do
        local raid = RM.raids[key]
        local n = #(RM.byRaid[key] or {})
        Check(L, raid.name .. "  |cff888888(" .. n .. " units)|r", db.raids[key] ~= false, function(v)
            if v then db.raids[key] = nil else db.raids[key] = false end
            ReloadAll()
        end)
    end
    L:Desc("Each raid's units only load inside that raid (and most only during their boss). The tabs above list every one.")
    L:EndCard()

    local loaded = 0
    for _ in pairs(RM.loaded) do loaded = loaded + 1 end
    L:Card("Right now")
    L:Desc(loaded .. " unit" .. (loaded == 1 and "" or "s") .. " loaded"
        .. (RM.encounterId and (", encounter " .. tostring(RM.encounterName or RM.encounterId)) or "")
        .. (RM.zoneId and (", instance " .. tostring(RM.zoneId)) or "") .. ".")
    L:EndCard()
end

local function RaidTab(L, key)
    local db = RM.DB()
    local raid = RM.raids[key]
    PreviewCard(L, key)
    L:Card(raid.name)
    Check(L, "Enabled", db.raids[key] ~= false, function(v) if v then db.raids[key] = nil else db.raids[key] = false end ReloadAll() end)
    local z = raid.zone and raid.zone[1]
    L:Desc("Untick a unit to switch it off; the defaults are what your packs had switched on. "
        .. "A unit marked |cff888888(off in pack)|r was disabled in your aura setup and stays off until ticked here.")
    Button(L, "Everything to pack defaults", function()
        for _, id in ipairs(RM.byRaid[key] or {}) do db.units[id] = nil end
        ReloadAll()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, 220)
    L:EndCard()
    if RM.Extras and RM.Extras.BuildBossCard then RM.Extras.BuildBossCard(L, key, Check) end

    -- units by group, in module order
    local byGroup, order = {}, {}
    for _, id in ipairs(RM.byRaid[key] or {}) do
        local def = RM.units[id]
        local g = def.group or "(no group)"
        if not byGroup[g] then byGroup[g] = {} order[#order + 1] = g end
        table.insert(byGroup[g], def)
    end
    for _, g in ipairs(order) do
        local list = byGroup[g]
        L:Card(CleanGroup(g))
        for _, def in ipairs(list) do
            local label = CleanId(def.id)
            if def.load.never then label = label .. "  |cff888888(off in pack)|r" end
            if RM.loaded[def.id] then label = label .. "  |cff33ff99loaded|r" end
            Check(L, label, RM.UnitEnabled(def), function(v)
                local default = not def.load.never
                if v == default then db.units[def.id] = nil else db.units[def.id] = v end
                RM.ReloadUnit(def.id)
            end)
        end
        L:EndCard()
    end

    -- the packs' own options
    local any = false
    for _, id in ipairs(RM.byRaid[key] or {}) do if RM.units[id].options then any = true break end end
    if any then
        for _, id in ipairs(RM.byRaid[key] or {}) do
            local def = RM.units[id]
            if def.options then
                L:Card("Options: " .. CleanId(def.id))
                OptionRows(L, def, def.options, {}, 0)
                Button(L, "Back to the pack's values", function()
                    db.config[def.id] = nil
                    RM.ReloadUnit(def.id)
                    if ns.RefreshConfig then ns.RefreshConfig() end
                end, 200)
                L:EndCard()
            end
        end
    end
end

RegisterPage("RaidMods", function(L)
    L:Header("Raid mods", "Boss timers, warnings and helpers for the classic raids, as part of ZacUI.")
    if not RM.DB() then
        L:Notice("missing", "Settings are not loaded yet.")
        return
    end
    local tabs = { { id = "general", label = "General", build = General } }
    local SHORT = { AQ40 = "AQ40", PT = "Pull timers" }
    for _, key in ipairs(RM.raidOrder) do
        local raid = RM.raids[key]
        tabs[#tabs + 1] = { id = key, label = SHORT[key] or raid.short or raid.name, build = function(LL) RaidTab(LL, key) end }
    end
    L:Tabs(tabs)
end)

-- /rm opens the page
SLASH_ZACUIRAIDMODS1 = "/rm"
SLASH_ZACUIRAIDMODS2 = "/raidmods"
SlashCmdList.ZACUIRAIDMODS = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "test" or msg:match("^test%s") or msg == "preview" or msg:match("^preview%s") then
        local db = RM.DB()
        local want = msg:match("^%a+%s+(%S+)")
        local key
        if want then
            for _, k in ipairs(RM.raidOrder) do
                if k:lower() == want or RM.raids[k].name:lower():find(want, 1, true) then key = k break end
            end
        end
        if db.testMode and not key then
            RM.SetTestMode(false)
            Print("Raid mods preview off.")
        else
            RM.SetTestMode(true, key)
            Print("Raid mods preview: " .. RM.raids[db.testRaid].name .. ". Drag the handles; /rm test again to lock and clear.")
        end
        if ns.RefreshConfig then ns.RefreshConfig() end
    elseif msg == "anchors" then
        RM.Layout.showing = not RM.Layout.showing
        RM.Layout.ShowAnchors(RM.Layout.showing)
    elseif msg == "reload" then
        ReloadAll()
        Print("Raid mods reloaded.")
    else
        if ns.OpenConfig then ns.OpenConfig("raidmods") end
    end
end
