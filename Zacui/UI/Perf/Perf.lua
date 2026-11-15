-- Perf - /zui perf: what ZacUI costs, read from the game's own addon
-- profiler. Part of ZacUI; load order is set by the TOC (after the
-- framework's dialogs).
--
-- WHY (2026-11-13, Zac: "look at how elesmere optimizes performance ...
-- and add something like that"). EllesmereUI shows what its suite costs
-- in its settings window; a UI that cannot see its own cost can only
-- guess at it. The client measures every addon all the time
-- (C_AddOnProfiler: Classic Era 1.15.6, TBC 2.5.5, Forever 1.60.1, the
-- modern client 11.0.7) - no scriptProfile CVar, no cost of its own - and
-- this window puts ZacUI's parts, Readycheck's and the busiest other
-- addons side by side:
--   Now        milliseconds a frame, averaged over the last 60 frames
--   % frame    that as a share of the whole frame's time
--   Session    the average since login or the last /reload
--   Last boss  the average over a boss fight
--   Peak       the worst single frame since login or /reload (for a
--              group: its worst part's)
--   Over 5 ms  how many frames it took more than 5 ms of (hitches)
-- "Copy as text" gives the same table as text to send on.
--
-- COST. Nothing runs until the window is opened; while it is open the
-- numbers are read once a second (one tracked ticker, stopped on close).
-- Rows are built once and re-labelled.
--
-- THE TWO DEBUG CVARS. scriptProfile makes the game time every addon call
-- (slower everywhere, most of all in a raid); taintLog writes a log of
-- taint. Both are for debugging and easy to leave on. The window says
-- when one is on, with a button that turns them off, and one chat line
-- says so the first time an instance is entered with one on.

local ADDON_NAME, ns = ...
local UI = ns.UI
local Print = ns.Print
if not UI then return end

local Perf = {}
ns.Perf = Perf

local floor, max, min = math.floor, math.max, math.min
local format = string.format

-- addons shown as groups (a folder name that starts so, any case); the
-- rest are "other addons", the busiest OTHERS of them listed
local GROUPS = {
    { id = "zacui", label = "ZacUI", prefix = "zacui" },
    { id = "readycheck", label = "Readycheck", prefix = "readycheck" },
}
local OTHERS = 5
Perf.GROUPS, Perf.OTHERS = GROUPS, OTHERS

-- ============================================================
-- THE CLIENT'S PROFILER
-- ============================================================
local function Profiler()
    local P = _G.C_AddOnProfiler
    local E = _G.Enum and _G.Enum.AddOnProfilerMetric
    if not (P and P.GetAddOnMetric and E and E.RecentAverageTime) then return nil end
    if P.IsEnabled and not P.IsEnabled() then return nil end
    return P, E
end
function Perf.Available() return Profiler() ~= nil end

local function Num(fn, ...)
    if type(fn) ~= "function" then return 0 end
    local ok, v = pcall(fn, ...)
    return (ok and type(v) == "number") and v or 0
end

-- the installed addons: name, title, loaded
local function AddOns()
    local A = _G.C_AddOns
    local count = (A and A.GetNumAddOns) or _G.GetNumAddOns
    local info = (A and A.GetAddOnInfo) or _G.GetAddOnInfo
    local loaded = (A and A.IsAddOnLoaded) or _G.IsAddOnLoaded
    local out = {}
    if not (count and info and loaded) then return out end
    for i = 1, count() or 0 do
        local name, title = info(i)
        if name and loaded(name) then out[#out + 1] = { name = name, title = title } end
    end
    return out
end

-- what a row is called: the part's own name ("Nameplates"), else the
-- addon's title without its colour codes, else its folder
local function Label(name, title)
    local A = _G.C_AddOns
    local meta = (A and A.GetAddOnMetadata) or _G.GetAddOnMetadata
    if meta then
        local ok, part = pcall(meta, name, "X-ZacUI-Part")
        if ok and type(part) == "string" and part ~= "" then return part end
    end
    if type(title) == "string" and title ~= "" then
        local t = title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= "" then return t end
    end
    return name
end

local KEYS = { "now", "session", "boss", "peak", "spikes" }
local function Metrics(E)
    return { now = E.RecentAverageTime, session = E.SessionAverageTime, boss = E.EncounterAverageTime,
             peak = E.PeakTime, spikes = E.CountTimeOver5Ms }
end

-- One reading. nil when this client has no profiler. Otherwise
--   { app = {...}, all = {...},                 the whole frame / every addon
--     groups = { { id, label, total = {...}, rows = { {name, label, ...} } } },
--     others = { rows = {...top OTHERS...}, more = n, moreNow = ms } }
-- with now / session / boss / peak in milliseconds and spikes a count.
function Perf.Read()
    local P, E = Profiler()
    if not P then return nil end
    local M = Metrics(E)
    local out = { app = {}, all = {}, groups = {}, others = { rows = {}, more = 0, moreNow = 0 } }
    for _, k in ipairs(KEYS) do
        out.app[k] = M[k] and Num(P.GetApplicationMetric, M[k]) or 0
        out.all[k] = M[k] and Num(P.GetOverallMetric, M[k]) or 0
    end
    local byId = {}
    for i, g in ipairs(GROUPS) do
        local grp = { id = g.id, label = g.label, rows = {}, total = { now = 0, session = 0, boss = 0, peak = 0, spikes = 0 } }
        out.groups[i], byId[g.id] = grp, grp
    end
    local rest = {}
    for _, a in ipairs(AddOns()) do
        local row = { name = a.name, label = Label(a.name, a.title) }
        for _, k in ipairs(KEYS) do row[k] = M[k] and Num(P.GetAddOnMetric, a.name, M[k]) or 0 end
        local low, home = a.name:lower(), nil
        for _, g in ipairs(GROUPS) do
            if low:sub(1, #g.prefix) == g.prefix then home = byId[g.id] break end
        end
        if home then
            home.rows[#home.rows + 1] = row
            local t = home.total
            t.now, t.session, t.boss = t.now + row.now, t.session + row.session, t.boss + row.boss
            t.spikes = t.spikes + row.spikes
            if row.peak > t.peak then t.peak = row.peak end
        else
            rest[#rest + 1] = row
        end
    end
    local function ByNow(a, b)
        if a.now ~= b.now then return a.now > b.now end
        return a.name < b.name
    end
    for _, g in ipairs(out.groups) do table.sort(g.rows, ByNow) end
    table.sort(rest, ByNow)
    for i, row in ipairs(rest) do
        if i <= OTHERS then out.others.rows[i] = row
        else out.others.more, out.others.moreNow = out.others.more + 1, out.others.moreNow + row.now end
    end
    return out
end

-- ============================================================
-- THE DEBUG CVARS
-- ============================================================
-- which of the two are on: { scriptProfile = true, taintLog = true } (nil
-- when neither)
function Perf.DebugCVars()
    local get = (_G.C_CVar and _G.C_CVar.GetCVar) or _G.GetCVar
    if not get then return nil end
    local on
    local okS, sp = pcall(get, "scriptProfile")
    if okS and (tonumber(sp) or 0) > 0 then on = on or {} on.scriptProfile = true end
    local okT, tl = pcall(get, "taintLog")
    if okT and (tonumber(tl) or 0) > 0 then on = on or {} on.taintLog = true end
    return on
end
local function CVarWords(on)
    if not on then return nil end
    if on.scriptProfile and on.taintLog then return "scriptProfile and taintLog are on" end
    return (on.scriptProfile and "scriptProfile" or "taintLog") .. " is on"
end
-- turns both off (scriptProfile only stops at the next /reload)
function Perf.DebugCVarsOff()
    local set = (_G.C_CVar and _G.C_CVar.SetCVar) or _G.SetCVar
    local on = Perf.DebugCVars()
    if not (set and on) then return false end
    if on.scriptProfile then pcall(set, "scriptProfile", "0") end
    if on.taintLog then pcall(set, "taintLog", "0") end
    if Print then
        Print("Performance: " .. (on.scriptProfile and "scriptProfile is off from the next /reload" or "")
            .. ((on.scriptProfile and on.taintLog) and "; " or "") .. (on.taintLog and "taintLog is off" or "") .. ".")
    end
    return true
end

-- ============================================================
-- AS TEXT
-- ============================================================
local function Ms(v) return (v and v > 0) and format("%.2f", v) or "-" end
local function Share(v, app) return (v and v > 0 and app and app > 0) and format("%.1f%%", v / app * 100) or "-" end
local function Count(v) return (v and v > 0) and tostring(floor(v + 0.5)) or "-" end
local function Fps(app) return (app and app > 0) and floor(1000 / app + 0.5) or nil end

local function Summary(r)
    local fps = Fps(r.app.now)
    local s = "Frame " .. Ms(r.app.now) .. " ms" .. (fps and (" (" .. fps .. " fps)") or "")
    s = s .. "   All addons " .. Ms(r.all.now) .. " ms (" .. Share(r.all.now, r.app.now) .. ")"
    return s
end
Perf.Summary = Summary

function Perf.Text()
    local r = Perf.Read()
    if not r then return "This game client has no addon profiler." end
    local out = {}
    local where = ""
    if GetInstanceInfo then
        local name, kind = GetInstanceInfo()
        if kind and kind ~= "none" then where = "   " .. tostring(name) end
    end
    out[#out + 1] = "ZacUI performance   " .. (date and date("%Y-%m-%d %H:%M") or "") .. where
        .. ((InCombatLockdown and InCombatLockdown()) and "   in combat" or "")
    out[#out + 1] = Summary(r)
    local function Line(label, v)
        out[#out + 1] = format("%-26s %7s %7s %8s %9s %7s %8s", label, Ms(v.now), Share(v.now, r.app.now), Ms(v.session), Ms(v.boss), Ms(v.peak), Count(v.spikes))
    end
    out[#out + 1] = format("%-26s %7s %7s %8s %9s %7s %8s", "", "now", "frame", "session", "last boss", "peak", "over 5ms")
    for _, g in ipairs(r.groups) do
        if #g.rows > 0 then
            Line(g.label .. " (" .. #g.rows .. ")", g.total)
            for _, row in ipairs(g.rows) do Line("  " .. row.label, row) end
        end
    end
    if #r.others.rows > 0 then
        out[#out + 1] = "Other addons, the busiest:"
        for _, row in ipairs(r.others.rows) do Line("  " .. row.label, row) end
        if r.others.more > 0 then out[#out + 1] = format("  and %d more: %s ms", r.others.more, Ms(r.others.moreNow)) end
    end
    local on = Perf.DebugCVars()
    out[#out + 1] = "Debug CVars: " .. (CVarWords(on) or "off")
    return table.concat(out, "\n")
end

-- ============================================================
-- THE WINDOW
-- ============================================================
local COLS = {
    { key = "label", title = "", w = 196, just = "LEFT" },
    { key = "now", title = "Now", w = 56 },
    { key = "share", title = "% frame", w = 64 },
    { key = "session", title = "Session", w = 64 },
    { key = "boss", title = "Last boss", w = 72 },
    { key = "peak", title = "Peak", w = 56 },
    { key = "spikes", title = "Over 5 ms", w = 76 },
}
local ROW_H, WIN_W, WIN_H = 20, 640, 500
local win, rows, ticker = nil, {}, nil
local Refresh

local function NewRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row.cells = {}
    local x = 0
    for c, col in ipairs(COLS) do
        local fs = UI.SFont(row, UI.S.F_VALUE or 13, { text = "", justify = col.just or "RIGHT" })
        fs:SetWordWrap(false)
        fs:SetWidth(col.w - 6)
        fs:SetPoint("LEFT", row, "LEFT", x + (c == 1 and 0 or 6), 0)
        row.cells[col.key] = fs
        x = x + col.w
    end
    row.rule = row:CreateTexture(nil, "ARTWORK")
    row.rule._zui_own = true
    row.rule:SetTexture(ns.FLAT)
    row.rule:SetHeight(1)
    row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.rule:SetVertexColor(1, 1, 1, UI.S.SECTION_RULE_A or 0.04)
    rows[i] = row
    return row
end

-- kind: "group" (a total: white), "part" (one addon: indented, dimmer),
-- "head" (a caption), "note"
local function Paint(row, kind, label, v, app)
    local c = row.cells
    local a = (kind == "group") and 1 or ((kind == "head" or kind == "note") and (UI.S.SECTION_A or 0.41) or 0.78)
    c.label:SetText((kind == "part" and "    " or "") .. (label or ""))
    for _, col in ipairs(COLS) do
        local fs = c[col.key]
        fs:SetTextColor(1, 1, 1, a)
        fs._zPaint = function(self) self:SetTextColor(1, 1, 1, a) end
    end
    if v then
        c.now:SetText(Ms(v.now)) c.share:SetText(Share(v.now, app)) c.session:SetText(Ms(v.session))
        c.boss:SetText(Ms(v.boss)) c.peak:SetText(Ms(v.peak)) c.spikes:SetText(Count(v.spikes))
    else
        c.now:SetText("") c.share:SetText("") c.session:SetText("") c.boss:SetText("") c.peak:SetText("") c.spikes:SetText("")
    end
    row.rule:SetShown(kind == "group")
    row.kind = kind
    row:Show()
end

Refresh = function()
    if not (win and win:IsShown()) then return end
    local r = Perf.Read()
    local child = win.child
    local n, y = 0, -2
    local function Add(kind, label, v)
        n = n + 1
        local row = rows[n] or NewRow(child, n)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, y)
        Paint(row, kind, label, v, r and r.app.now)
        y = y - ROW_H
    end
    if not r then
        Add("note", "This game client has no addon profiler.")
        win:SetTitle(nil, " ")
    else
        for _, g in ipairs(r.groups) do
            if #g.rows > 0 then
                Add("group", g.label .. "  (" .. #g.rows .. ")", g.total)
                for _, row in ipairs(g.rows) do Add("part", row.label, row) end
                y = y - 6
            end
        end
        if #r.others.rows > 0 then
            Add("head", "Other addons, the busiest")
            for _, row in ipairs(r.others.rows) do Add("part", row.label, row) end
            if r.others.more > 0 then
                Add("part", "and " .. r.others.more .. " more", { now = r.others.moreNow })
            end
        end
        win:SetTitle(nil, Summary(r))
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    local h = -y + 4
    child:SetHeight(h)
    if win.scroll.Recalculate then win.scroll:Recalculate(h) end
    -- the debug CVars
    local words = CVarWords(Perf.DebugCVars())
    if words then
        win.cvarText:SetText(words .. " - a debug setting that slows every addon.")
        win.cvarText:Show()
        win.cvarOff:Show()
    else
        win.cvarText:Hide()
        win.cvarOff:Hide()
    end
    if win.copy and win.copy:IsShown() then
        local t = Perf.Text()
        if win.copy.shownText ~= t and not win.copy.editBox:HasFocus() then
            win.copy.shownText = t
            win.copy:SetText(t)
        end
    end
end
Perf.Refresh = Refresh

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, Refresh)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "core.perf") end
end
local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
end
function Perf.Ticking() return ticker ~= nil end

local function Build()
    local f = UI.Popup("ZacUIPerfFrame", WIN_W, WIN_H, "Performance", { rule = true, size = "small", desc = " " })
    f:SetPoint("CENTER", 0, 30)
    local pad = f.pad
    local buttons = f:SetButtons({
        { text = "Copy as text", width = 120, onClick = function() Perf.ToggleCopy() end },
        { text = "Close", kind = "primary", onClick = function() UI.CloseWindow(f) end },
    })
    f.copyButton = buttons[1]

    -- the column heads
    local head = CreateFrame("Frame", nil, f)
    head:SetHeight(ROW_H)
    head:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -(f.headerHeight + 4))
    head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(pad + UI.M.SCROLL_W), -(f.headerHeight + 4))
    local x = 0
    f.heads = {}
    for c, col in ipairs(COLS) do
        local fs = UI.PopupText(head, "head", { text = col.title, justify = col.just or "RIGHT" })
        fs:SetWordWrap(false)
        fs:SetWidth(col.w - 6)
        fs:SetPoint("LEFT", head, "LEFT", x + (c == 1 and 0 or 6), 0)
        f.heads[col.key] = fs
        x = x + col.w
    end
    f.head = head

    -- the debug CVars' line, over the button row
    f.cvarText = UI.PopupText(f, "hint", { text = "", justify = "LEFT" })
    f.cvarText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", pad, f:FooterHeight() + 6)
    f.cvarText._zPaint = function(self) local c = ns.GetColor("text", "orange") self:SetTextColor(c.r, c.g, c.b, 1) end
    f.cvarText:_zPaint()
    f.cvarOff = UI.PopupBuild(UI.Button, f, "Turn off", { width = 84, height = 20, onClick = function()
        Perf.DebugCVarsOff()
        Refresh()
    end })
    f.cvarOff:SetPoint("LEFT", f.cvarText, "RIGHT", 10, 0)
    f.cvarOff:SetFrameLevel(f:GetFrameLevel() + 20)

    local top = f.headerHeight + 4 + ROW_H + 2
    local bottom = f:FooterHeight() + 30
    local scroll, child = UI.ScrollArea(f, { style = "settings" })
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -top)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(pad + UI.M.SCROLL_W), bottom)
    scroll.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -top)
    scroll.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, bottom)
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    child:SetWidth(WIN_W - 2 * pad - UI.M.SCROLL_W)
    f.scroll, f.child = scroll, child

    -- the same as text, over the table while it is asked for
    local copy = UI.PopupBuild(UI.TextBox, f, { width = WIN_W - 2 * pad, height = WIN_H - top - bottom + ROW_H, selectOnFocus = true })
    copy:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -(f.headerHeight + 4))
    copy:SetFrameLevel(f:GetFrameLevel() + 10)
    copy:Hide()
    f.copy = copy

    f:HookScript("OnShow", function()
        StartTicker()
        Refresh()
    end)
    f:HookScript("OnHide", function()
        StopTicker()
        if f.copy:IsShown() then Perf.ToggleCopy() end
    end)
    win = f
    return f
end

function Perf.ToggleCopy()
    if not win then return end
    local on = not win.copy:IsShown()
    win.copy:SetShown(on)
    win.head:SetShown(not on)
    win.scroll:SetShown(not on)
    win.scroll.bar:SetShown(not on)
    win.copyButton:SetLabel(on and "Back to the table" or "Copy as text")
    win:LayoutButtons()
    if on then
        local t = Perf.Text()
        win.copy.shownText = t
        win.copy:SetText(t)
        if win.copy.editBox then
            win.copy.editBox:SetFocus()
            win.copy.editBox:HighlightText()
        end
    else
        Refresh()
    end
end

function Perf.Show()
    if not win then Build() end
    if win:IsShown() then win:Raise() return end
    UI.OpenWindow(win)
end
function Perf.Toggle()
    if win and win:IsShown() then UI.CloseWindow(win) else Perf.Show() end
end
function Perf.Window() return win end

-- /zui perf
ns.SlashCommands = ns.SlashCommands or {}
ns.SlashCommands.perf = function() Perf.Toggle() end
ns.SlashCommands.performance = ns.SlashCommands.perf

-- ============================================================
-- ONE LINE, THE FIRST TIME AN INSTANCE IS ENTERED WITH A DEBUG CVAR ON
-- ============================================================
local said = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if said then return end
    C_Timer.After(5, function()
        if said then return end
        local inside = false
        if IsInInstance then
            local yes, kind = IsInInstance()
            inside = yes and (kind == "raid" or kind == "party")
        end
        if not inside then return end
        local words = CVarWords(Perf.DebugCVars())
        if not words then return end
        said = true
        ev:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if Print then Print("Performance: " .. words .. " (a debug setting that slows every addon in a fight). /zui perf turns it off.") end
    end)
end)
