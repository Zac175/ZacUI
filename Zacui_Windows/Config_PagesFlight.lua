-- Config_PagesFlight - the Flight times page: the times at the flight
-- master and the countdown bar while you fly (Win_FlightTimes).
-- Part of ZacUI; load order is set by the TOC (after Config_PagesWindows,
-- whose row it sits under in the menu).
--
-- Every setting is ZacUIDB.windows.flight (FT.DB), so profiles carry it
-- with the Game windows' look; the learned times are gathered data and
-- stay out of every profile. The preview is the live bar itself, made by
-- FT.NewBar and dressed by FT.StyleBar, counting down a sample flight.

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local FT = ns.FlightTimes
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local UI = ns.UI

if not (FT and RegisterPage and UI) then return end

local M = UI.M

local PAGE_ID, MENU_ID = "FlightTimes", "flighttimes"

-- ============================================================
-- THE MENU ROW
-- ============================================================
-- Under Game windows, in the "Bags & maps" group, inserted when this part
-- loads (so the row is there exactly when the flight master window is).
do
    for _, group in ipairs(ns.ConfigMenu or {}) do
        if group.id == "windows" and group.children then
            local have, after = false, nil
            for i, child in ipairs(group.children) do
                if child.id == MENU_ID then have = true end
                if child.id == "gamewindows" then after = i end
            end
            if not have then
                table.insert(group.children, (after or #group.children) + 1, {
                    id = MENU_ID, label = "Flight times", page = PAGE_ID, addon = "Zacui_Windows",
                    keywords = "flight flights flight time flight times flight path flight master taxi "
                        .. "gryphon wind rider bat hippogryph countdown timer landing how long travel route",
                })
            end
        end
    end
end

-- ============================================================
-- SMALL BUILDERS
-- ============================================================
local function Changed(source)
    if ns.SettingsChanged then ns.SettingsChanged(source or "flight") end
end
local function Px(v) return v .. " px" end

local function Check(L, d, key, label, desc, after, tip)
    local w = UI.Checkbox(L.current, label, d[key] and true or false, function(v)
        d[key] = v and true or false
        if after then after(v) end
    end, tip and { tooltip = tip } or nil)
    L:Row(w, 17)
    if desc then L:Desc(desc) end
    return w
end

local function Slide(L, d, key, label, mn, mx, fmt, desc)
    local w = UI.Slider(L.current, { width = 220, min = mn, max = mx, step = 1,
        value = tonumber(d[key]) or mn, label = label, format = fmt,
        onChange = function(v) d[key] = v end })
    L:Row(w, 40)
    if desc then L:Desc(desc) end
    return w
end

-- a colour bound to d[key] ({ r, g, b, a }); nil reads as the palette's
local function Colour(L, d, key, label, fallback, alpha, desc)
    local cp = UI.ColorPicker(L.current, { label = label, alpha = alpha,
        get = function() return d[key] end,
        set = function(r, g, b, a) d[key] = r and { r = r, g = g, b = b, a = alpha and a or nil } or nil end,
        default = function() local c = fallback() return c.r, c.g, c.b, c.a or 1 end,
        reset = true })
    L:Row(cp, 22)
    if desc then L:Desc(desc) end
    return cp
end

local function Pal(cat, key) return function() return ns.GetColor(cat, key) end end

local function Choice(L, d, key, label, items, width)
    local f = UI.Field(L.current, label, function(host)
        return UI.Dropdown(host, { width = width or 200,
            items = function() return items end,
            selected = function()
                for _, it in ipairs(items) do if it.value == d[key] then return it.text end end
                return items[1].text
            end,
            selectedValue = function() return d[key] end,
            onSelect = function(v) d[key] = v end })
    end, { width = width or 200 })
    L:Add(f, 6)
    return f
end

local function Buttons(L, specs)
    local row = UI.Holder(L.current)
    row:SetSize(300, M.BUTTON_H)
    local prev
    for _, s in ipairs(specs) do
        local b = UI.Button(row, s[1], { width = s[2], tooltip = s[3], onClick = s[4] })
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("LEFT") end
        prev = b
    end
    L:Row(row, M.BUTTON_H + 4)
    return row
end

-- ============================================================
-- THE PREVIEW: THE BAR, COUNTING DOWN A SAMPLE FLIGHT
-- ============================================================
local SAMPLE = { measured = { name = "Ironforge, Dun Morogh", secs = 102, est = false },
                 estimate = { name = "Menethil Harbor, Wetlands", secs = 130, est = true } }
local SAMPLE_START = 0.62       -- the sample starts this far through its flight

local function BuildPreview(canvas, P)
    local st = P.store
    st.holder = CreateFrame("Frame", nil, canvas)
    st.holder:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    st.bar = FT.NewBar(st.holder)
    st.bar:SetPoint("CENTER", st.holder, "CENTER", 0, 0)
    st.bar:Show()
    st.t0 = GetTime()
    -- the countdown ticks only while the sample is on screen
    st.bar:SetScript("OnUpdate", function(self)
        local s = SAMPLE[P.mode or "measured"] or SAMPLE.measured
        local left = s.secs * SAMPLE_START - (GetTime() - st.t0)
        if left <= 0 then st.t0 = GetTime() left = s.secs * SAMPLE_START end
        FT.FillBar(self, left, s.secs, s.est, FT.DB())
    end)
end

local function UpdatePreview(canvas, P)
    local st = P.store
    local d = FT.DB()
    local s = SAMPLE[P.mode or "measured"] or SAMPLE.measured
    if ns.Motion and ns.Motion.IsPlaying(st.bar) then ns.Motion.Stop(st.bar) end
    FT.StyleBar(st.bar, d)
    st.bar.label:SetText(FT.Place(s.name))
    st.bar:Show()
    FT.FillBar(st.bar, s.secs * SAMPLE_START - (GetTime() - st.t0), s.secs, s.est, d)
    local w, h = tonumber(d.width) or 240, tonumber(d.height) or 20
    st.holder:SetSize(w, h)
    -- the canvas is the bar at its real size
    if P.Resize then P.Resize(math.max(220, w + 40), math.max(40, h + 20)) end
end

local function ReplayPreview(canvas, P)
    local st = P.store
    st.t0 = GetTime()
    if not ns.Motion then return end
    ns.Motion.Stop(st.bar)
    st.bar:Hide()
    ns.Motion.Show(st.bar, FT.DB().showAnim)
end

-- ============================================================
-- THE PAGE
-- ============================================================
RegisterPage(PAGE_ID, function(L)
    L:Header("Flight times",
        "How long each flight takes, at the flight master and in the air. Times are learned from "
        .. "your own flights; until you have flown one it is estimated and marked with a ~.")

    local d = FT.DB()

    if ns.CustomPick then
        ns.CustomPick.SetHandler("windows.flight", function(el)
            if el ~= "flight.label" and el ~= "flight.time" then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            ZacUIDB.config.tabs[MENU_ID] = "text"
            RefreshConfig()
        end)
    end

    L:Preview({
        key = "windows.flight",
        title = "Flight timer",
        width = math.max(220, (tonumber(d.width) or 240) + 40),
        height = math.max(40, (tonumber(d.height) or 20) + 20),
        modes = { { id = "measured", label = "Flown before" }, { id = "estimate", label = "Estimate" } },
        modesLabel = "Show",
        build = BuildPreview,
        update = UpdatePreview,
        replay = ReplayPreview,
    })

    local function Tab_general(L)
        L:Card("At the flight master")
        Check(L, d, "listTimes", "Show how long each flight takes",
            "On ZacUI's flight master list and on the flight map's tooltips.", nil,
            "1:42 is a flight you have taken before (the middle of your last few). ~2:10 is an "
            .. "estimate: the legs you have flown, the rest from their length at the speed your "
            .. "own flights fly on that continent.")
        Check(L, d, "sortTime", "List the quickest flights first",
            "The Quickest button on the list does the same.")
        L:EndCard()

        L:Card("While you fly")
        Check(L, d, "enabled", "Show a countdown while flying", nil, nil,
            "Where you are going and the time left; it disappears when you land.")
        Choice(L, d, "style", "Show it as", {
            { text = "A bar", value = "bar" }, { text = "Text only", value = "text" } })
        Check(L, d, "voice", "Say \"Landing in 5 seconds\"",
            "In ZacUI's voice (the game's text to speech).")
        L:EndCard()

        L:Card("What has been learned")
        local n = FT.Counts()
        L:Pair("Trips timed", tostring(n.trips), 200)
        L:Pair("Legs timed", tostring(n.legs), 200)
        L:Pair("From the world map", tostring(n.imported), 200)
        L:Desc("Each game keeps its own times. A flight left early, cut short by death or "
            .. "a logout, or ending somewhere else teaches nothing.")
        L:EndCard()
    end

    local function Tab_look(L)
        L:Card("The bar")
        Slide(L, d, "width", "Width", 120, 400, Px)
        Slide(L, d, "height", "Height", 12, 36, Px)
        local tp = UI.TexturePicker(L.current, { label = "Texture", width = 240,
            get = function() return d.texture end,
            set = function(name) d.texture = name end,
            color = function() local c = ns.GetColor("ui", "accent") return c.r, c.g, c.b end })
        L:Add(tp, 6)
        Colour(L, d, "fillColor", "Fill", Pal("ui", "accent"), false)
        Colour(L, d, "bgColor", "Behind the fill", function()
            local w, c = ns.GetColor("ui", "windowBg"), ns.GetColor("ui", "accent")
            return { r = w.r * 0.45 + c.r * 0.12, g = w.g * 0.45 + c.g * 0.12, b = w.b * 0.45 + c.b * 0.12, a = 0.9 }
        end, true, "Until you pick one, a dark shade of the fill.")
        Check(L, d, "icon", "The icon at the left")
        Check(L, d, "spark", "A glow at the end of the fill")
        L:Desc("Text only shows just the destination and the time.")
        L:EndCard()
    end

    local function Tab_text(L)
        local targets = {}
        for _, k in ipairs({ "bar", "fill", "icon", "label", "time" }) do
            targets[#targets + 1] = { value = k, text = FT.ANCHOR_LABELS[k] }
        end
        local function Others(key)
            local out = {}
            for _, e in ipairs(targets) do if e.value ~= key then out[#out + 1] = e end end
            return out
        end
        L:Card("Destination")
        local ag, as = ns.CustomAccess(FT.DB, "anchors", "label")
        UI.TextElement(L, { key = "flight.label",
            fontGet = function() return d.labelFont end, fontSet = function(spec) d.labelFont = spec end,
            fontDefaults = { size = FT.LabelSize(d), outline = "outline" }, minSize = 6, maxSize = 24,
            sample = "Ironforge",
            colorGet = function() return d.textColor end,
            colorSet = function(r, g, b) d.textColor = r and { r = r, g = g, b = b } or nil end,
            colorDefault = function() local c = ns.GetColor("text", "normal") return c.r, c.g, c.b, 1 end,
            colorReset = true, colorAlpha = false, colorLabel = "Text colour",
            anchorGet = ag, anchorSet = as, targets = Others("label"),
            defaultTargetLabel = "Where it sits now", anchorMin = -40, anchorMax = 40,
            anchorDefaults = function() return FT.AnchorDefaults("label") end })
        L:Desc("Until a font is picked, the size follows the bar's height. The colour is both texts'.")
        L:EndCard()

        L:Card("Time left")
        local tg, ts = ns.CustomAccess(FT.DB, "anchors", "time")
        local fg, fs = ns.CustomAccess(FT.DB, "formats", "time")
        UI.TextElement(L, { key = "flight.time",
            fontGet = function() return d.timeFont end, fontSet = function(spec) d.timeFont = spec end,
            fontDefaults = { size = FT.TimeSize(d), outline = "outline" }, minSize = 6, maxSize = 28,
            sample = "1:42  ~2:10",
            formatGet = fg, formatSet = fs, formatKinds = { time = true }, formatDefaults = FT.TIME_DEFAULTS,
            formatSample = function(f)
                return ns.FormatTime(102, f, FT.TIME_DEFAULTS) .. "  ~" .. ns.FormatTime(130, f, FT.TIME_DEFAULTS)
            end,
            anchorGet = tg, anchorSet = ts, targets = Others("time"),
            defaultTargetLabel = "Where it sits now", anchorMin = -40, anchorMax = 40,
            anchorDefaults = function() return FT.AnchorDefaults("time") end })
        L:Desc("An estimate always starts with a ~.")
        L:EndCard()
    end

    local function Tab_anim(L)
        L:Card("Animation")
        local sa = UI.AnimationPicker(L.current, { label = "When you take off",
            styles = { "none", "fade", "slide", "pop", "bounce" },
            get = function() return d.showAnim end, set = function(spec) d.showAnim = spec end })
        L:Add(sa, 6)
        local ha = UI.AnimationPicker(L.current, { label = "When you land",
            styles = { "none", "fade", "slide", "pop" },
            get = function() return d.hideAnim end, set = function(spec) d.hideAnim = spec end })
        L:Add(ha, 6)
        L:EndCard()
        if ns.Motion and not ns.Motion.Enabled() then
            L:Notice("warn", "Animations are off (Appearance > Motion), so the bar simply appears.")
        end
    end

    local function Tab_pos(L)
        L:Card("Where it sits")
        L:Desc("Drag the box to place the countdown; Edit Mode and the Movers page move it too.")
        Buttons(L, {
            { "Move", 90, "Shows a sample flight and a box to drag; press again to lock.", function()
                FT.Test(30)
                if ns.ToggleMover then ns.ToggleMover("flighttimer") end
            end },
            { "Test", 90, "A 20 second sample flight on the real bar.", function() FT.Test(20) end },
            { "Put it back", 110, "Back to the top of the screen.", function()
                if ns.ResetMover then ns.ResetMover("flighttimer") end
            end },
        })
        L:EndCard()
    end

    local function Tab_adv(L)
        L:Card("Learned times")
        L:Desc("Forgetting starts this game's times over from your next flights. The times "
            .. "copied from the world map stay.")
        Buttons(L, {
            { "Forget learned times", 170, "This game's timed trips, legs and speeds.", function()
                FT.Forget()
                Changed("flight.forget")
                RefreshConfig()
            end },
        })
        L:EndCard()

        L:Card("Reset")
        Buttons(L, {
            { "Reset the look", 140, "Size, colours, fonts, text spots and animations back to how ZacUI ships them.", function()
                for _, k in ipairs({ "width", "height", "texture", "fillColor", "bgColor", "textColor",
                    "labelFont", "timeFont", "icon", "spark", "style", "anchors", "formats", "showAnim", "hideAnim" }) do
                    d[k] = nil
                end
                FT.DB()
                Changed("flight.reset")
                RefreshConfig()
            end },
        })
        L:EndCard()
    end

    L:Tabs({
        { id = "general", label = "General", build = Tab_general },
        { id = "look", label = "Look", build = Tab_look },
        { id = "text", label = "Text", build = Tab_text },
        { id = "anim", label = "Animation", build = Tab_anim },
        { id = "pos", label = "Position", build = Tab_pos },
        { id = "adv", label = "Advanced", build = Tab_adv },
    })
end)
