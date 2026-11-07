-- Config_PagesMeter - the Damage meter page. Everything the native
-- meter reads is editable here; the defaults ARE the ported Details
-- setup (profile Naowh + the two-window Zacw layout), this is where
-- you drift from it.
-- Part of ZacUI; load order is set by the TOC.
--
-- Tabs in the house order: General (windows, updates, segments, threat,
-- raid summary, report) - Look (rows, bars, borders, icons, window,
-- title bar, toolbar, threat rows, summary colours) - Text (every font
-- and number format) - Animation (rows appearing, going and changing
-- place; the window label) - Position (each window's lock, size and
-- spot; the threat dock) - Advanced (resets).
--
-- THE PREVIEW is a real meter window - Meter.NewPreviewWindow, the same
-- rows, styling and refresh as a live one - fed a made-up fight: damage,
-- healing, the threat list (through Threat.Paint, the live scan's own
-- drawing), and the raid summary's top card from its example raid. Its
-- three "Glow" modes are the screen-edge threat glow (Meter_ThreatGlow)
-- at its levels - warning (orange), danger (red, pulsing), pulled (a fast
-- flash) - drawn by the glow's own G.Create / G.Apply on a stand-in
-- screen at the game's size, of which the canvas shows a band of the
-- left edge at the real size (Zac 2026-11-04: the whole screen shrunk into
-- the strip was tiny). The Threat card's "Preview the glow at" slider
-- picks the level its value is in and draws it there. The alert modes
-- (Weak opener, Pulling in 3s, Threat stop, Aggro) are the lines in the
-- middle of the screen as the raid-warning frame draws them (its font,
-- the alerts' red, its grow-and-settle arrival on Replay), dimmed while
-- the Threat card has them off.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local RegisterPage = ns.RegisterPage
local UI = ns.UI

local M, F = UI.M, UI.F
local format = string.format

-- the words people type that are not on the page
if ns.AddMenuKeywords then
    ns.AddMenuKeywords("meter", "skada recount look style colour color colours colors "
        .. "class colors font fonts texture textures row height spacing gap border background "
        .. "title bar toolbar icon icons spec number format abbreviation percent rank "
        .. "animation animations fade preview test mode example size width position move lock "
        .. "death deaths recap killing blow overkill interrupt dispel")
end

-- the state the Look tab's state editor was on, across rebuilds
local STATE_PICK = {}

local function Look()
    local Meter = ns.Meter
    return Meter and Meter.Look and Meter.Look() or (ZacUIDB.meter or {})
end

local function MeterRefresh()
    local Meter = ns.Meter
    if Meter and Meter.DirtyAll then Meter.DirtyAll() end
    if Meter and Meter.enabled and Meter.StartRefreshTicker then
        Meter.StartRefreshTicker()
    end
end

-- ============================================================
-- SMALL BUILDERS
-- ============================================================
local function BindCheck(L, tbl, key, label, desc, after)
    local w = UI.Checkbox(L.current, label, tbl[key] and true or false,
        function(v)
            tbl[key] = v and true or false
            if after then after(v) else MeterRefresh() end
        end)
    L:Row(w, 17)
    if desc then L:Desc(desc) end
    return w
end

local function BindSlider(L, tbl, key, label, opts)
    opts = opts or {}
    local w = UI.Slider(L.current, {
        width = opts.width or 200, min = opts.min, max = opts.max, step = opts.step or 1,
        value = tonumber(tbl[key]) or opts.default or opts.min, label = label, format = opts.format,
        onChange = function(v)
            tbl[key] = v
            if opts.after then opts.after(v) else MeterRefresh() end
        end,
    })
    L:Row(w, 40)
    if opts.desc then L:Desc(opts.desc) end
    return w
end

local function Px(v) return format("%d px", v) end

local function Color(L, label, get, set, alpha, desc)
    local w = UI.ColorPicker(L.current, { label = label, alpha = alpha, get = get, set = set })
    L:Row(w, 22)
    if desc then L:Desc(desc) end
    return w
end

-- a colour setting stored as { r, g, b, a } under tbl[key]
local function BindColor(L, tbl, key, label, fallback, alpha, desc)
    return Color(L, label,
        function()
            local c = tbl[key]
            if type(c) == "table" then return c end
            return fallback
        end,
        function(r, g, b, a) tbl[key] = { r = r, g = g, b = b, a = a or 1 } end,
        alpha, desc)
end

local function Drop(L, label, items, get, set, width, desc)
    local w = UI.Field(L.current, label, function(host)
        return UI.Dropdown(host, { width = width or 200,
            items = function()
                local out = {}
                for _, it in ipairs(items) do out[#out + 1] = { text = it[2], value = it[1] } end
                return out
            end,
            selected = function()
                local v = get()
                for _, it in ipairs(items) do if it[1] == v then return it[2] end end
                return items[1][2]
            end,
            selectedValue = get,
            onSelect = function(v) set(v) end })
    end, { width = width or 200 })
    L:Add(w, 6)
    if desc then L:Desc(desc) end
    return w
end

local function Font(L, label, key, defaults, sample, desc)
    local d = Look()
    local w = UI.FontPicker(L.current, { label = label, defaultLabel = "The meter's font",
        get = function() return d[key] end,
        set = function(spec) d[key] = spec end,
        defaults = defaults, minSize = 6, maxSize = 32, sample = sample })
    L:Add(w, 6)
    if desc then L:Desc(desc) end
    return w
end

local function Anim(L, label, key, styles, desc)
    local d = Look()
    local w = UI.AnimationPicker(L.current, { label = label, styles = styles,
        get = function() return d[key] end,
        set = function(spec) d[key] = spec end })
    L:Add(w, 6)
    if desc then L:Desc(desc) end
    return w
end

local function Texture(L, label, key, default, tint, desc)
    local d = Look()
    local w = UI.TexturePicker(L.current, { label = label, width = 240, defaultLabel = "The meter's own",
        get = function() return d[key] end,
        set = function(name) d[key] = name end,
        defaultPath = function() return default end,
        color = tint })
    L:Add(w, 6)
    if desc then L:Desc(desc) end
    return w
end

local function WindowName(i, w)
    return "Window " .. i .. " (" .. (w.display == "threat" and "threat" or "meter") .. ")"
end

-- ============================================================
-- PREVIEW - a made-up fight
-- ============================================================
local function Me()
    local name = UnitName and UnitName("player") or "You"
    local _, class = UnitClass and UnitClass("player")
    return name or "You", class or "WARRIOR"
end

local ActorMeta = { __index = { ActivityTime = function(self) return self.act or 180 end } }
local function Actor(name, class, spec, total, isSelf)
    return setmetatable({ name = name, class = class, spec = spec, total = total, grupo = true,
        isSelf = isSelf or nil, act = 176, damageTaken = 0, healingTaken = 0 }, ActorMeta)
end

-- one fight of a raid night: ten damage dealers (you third, one name
-- carrying a realm) and five healers
local function FakeFight()
    local me, myClass = Me()
    local mySpec = myClass == "WARRIOR" and 72 or nil
    local dmg = {
        Actor("Orrin", "MAGE", 63, 412300), Actor("Brakka-Whitemane", "WARRIOR", 72, 398100),
        Actor(me, myClass, mySpec, 371400, true), Actor("Quillan", "ROGUE", 260, 355200),
        Actor("Velka", "WARLOCK", 265, 329800), Actor("Durnik", "HUNTER", 254, 301500),
        Actor("Tovren", "WARRIOR", 71, 276900), Actor("Nyssa", "ROGUE", 259, 248300),
        Actor("Mirel", "WARLOCK", 267, 233100), Actor("Sefa", "MAGE", 64, 190400),
    }
    local heal = {
        Actor("Elunara", "DRUID", 105, 251900), Actor("Ghaldor", "PRIEST", 257, 233400),
        Actor("Lightfang", "PALADIN", 65, 214700), Actor("Rokka", "SHAMAN", 264, 198200),
        Actor("Thessa", "PRIEST", 256, 160600), Actor(me, myClass, mySpec, 12400, true),
    }
    return {
        damage = { actors = dmg }, heal = { actors = heal }, misc = { actors = {} },
        GetCombatTime = function() return 184 end,
    }
end

-- the threat list on a boss: the tank, you closing on it, the raid behind
local function FakeThreat()
    local me, myClass = Me()
    return {
        { "Tankadin", 100, true, "TANK", "PALADIN", 58200, 100 },
        { me, 82.4, false, "DAMAGER", myClass, 47950, 82.4 },
        { "Brakka", 74.1, false, "DAMAGER", "WARRIOR", 43120, 74.1 },
        { "Orrin", 61.0, false, "DAMAGER", "MAGE", 35500, 61.0 },
        { "Quillan", 48.3, false, "DAMAGER", "ROGUE", 28110, 48.3 },
        { "Velka", 33.9, false, "DAMAGER", "WARLOCK", 19730, 33.9 },
        { "Ghaldor", 12.5, false, "HEALER", "PRIEST", 7270, 12.5 },
    }
end

local CANVAS_W, CANVAS_H = 400, 300
-- the death recap sample: the recap window's panel at its real size
local RECAP_W, RECAP_H = 460, 340
local DEATH_MODES = { deathTip = true, deathRecap = true }
-- the preview strip: a meter window at its real size (its saved width and
-- height, its row look), and the summary's night card at its width, a
-- page long (the strip shows its top part); update sizes the canvas to
-- whichever is up
local SUM_W = 620

-- the saved window a mode draws like: the threat window for threat, the
-- first meter window otherwise
local function ModelWindow(threat)
    local d = Look()
    for _, w in ipairs(d.windows or {}) do
        if (w.display == "threat") == threat then return w end
    end
    return (d.windows or {})[1] or { w = 226, h = 200 }
end

local function SettleAll(rows)
    local Meter = ns.Meter
    for _, row in ipairs(rows or {}) do
        Meter.SettleRow(row)
        row:Hide()
        row.actor = nil
    end
end

-- fill the preview window for the mode (no animation of its own: rows
-- that appear fade in as they would live)
local function FillMeter(P)
    local st, Meter = P.store, ns.Meter
    local win = st.win
    local threat = P.mode == "threat"
    local model = ModelWindow(threat)
    local w = math.max(100, tonumber(model.w) or 226)
    local h = math.max(50, tonumber(model.h) or 200)
    if win.settings.w ~= w or win.settings.h ~= h then
        SettleAll(win.rows)
        SettleAll(win.threatRows)
        win.settings.w, win.settings.h = w, h
        win.frame:SetSize(w, h)
    end
    if threat then
        SettleAll(win.rows)
        win.fakeCombat = nil
        win.settings.display = "threat"
        Meter.StyleWindow(win)
        local T = Meter.Threat
        win.threatRows = win.threatRows or {}
        for _, row in ipairs(win.threatRows) do T.StyleRow(row) end
        T.SizeChanged(win)
        T.Paint(win, FakeThreat(), (Me()))
        Meter.UpdateTitle(win)
    else
        SettleAll(win.threatRows)
        st.fight = st.fight or FakeFight()
        -- names are worked out again, so "hide realm names" shows
        for _, list in pairs({ st.fight.damage.actors, st.fight.heal.actors }) do
            for _, a in ipairs(list) do a.displayName = nil end
        end
        Meter.FillPreviewWindow(win, st.fight, P.mode == "healing" and "heal_done" or "damage_done")
    end
end

local function SummarySig()
    local d = Look()
    local parts = {}
    for _, k in ipairs({ "rsGood", "rsBad", "rsMid" }) do
        local c = d[k]
        parts[#parts + 1] = type(c) == "table" and format("%.3f/%.3f/%.3f", c.r or c[1] or 0, c.g or c[2] or 0, c.b or c[3] or 0) or "-"
    end
    return table.concat(parts, ",")
end

local function BuildPreview(canvas, P)
    local Meter = ns.Meter
    local st = P.store
    st.win = Meter.NewPreviewWindow(canvas, 226, 200)
    st.win.frame:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    st.serial = 0
    -- the raid summary's night card, drawn by the summary itself
    local host = UI.Box(canvas, "ui", "windowBg")
    host:SetAllPoints(canvas)
    if host.SetClipsChildren then host:SetClipsChildren(true) end
    local child = CreateFrame("Frame", nil, host)
    child:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    child:SetSize(SUM_W, CANVAS_H)
    host:Hide()
    st.sumHost, st.sumChild = host, child
    -- the screen-edge threat glow: a stand-in screen at the game's size,
    -- the glow on it made by the glow's own G.Create; the canvas is a
    -- band of its left edge at the real size (the whole screen shrunk
    -- into the strip was a sliver nobody could read)
    local G = ns.ThreatGlow
    if G then
        local screen = CreateFrame("Frame", nil, canvas)
        screen:SetPoint("LEFT", canvas, "LEFT", 0, 0)
        screen:SetSize(1024, 640)
        if UI.Border then UI.Border(screen, "ui", "border") end
        screen:Hide()
        st.glowScreen, st.glow = screen, G.Create(screen)
        st.glowNote = UI.Font(canvas, F.SMALL, { text = "", cat = "text", key = "gray" })
        st.glowNote:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -6, 4)
        st.glowNote:Hide()
        -- the alert lines in the middle of the screen, drawn as the
        -- raid-warning frame draws them (G.AlertLine / G.StyleAlert)
        st.line = G.AlertLine(canvas)
        st.line:SetPoint("TOP", canvas, "TOP", 0, -2)
        st.line:Hide()
        st.lineNote = UI.Font(canvas, F.SMALL, { text = "", cat = "text", key = "gray" })
        st.lineNote:SetPoint("TOP", st.line, "BOTTOM", 0, 0)
        st.lineNote:Hide()
        st.glowOpts = { instant = true }
        st.openerOpts = { instant = true, opener = true }
    end
    -- a death row's tooltip and its recap, drawn by the meter's own code
    -- from its sample death (Meter.SampleDeath)
    if Meter.NewTipSample then
        st.tip = Meter.NewTipSample(canvas)
        st.tip:SetPoint("CENTER", canvas, "CENTER", 0, 0)
        st.tip:Hide()
    end
    if Meter.NewRecapPanel then
        st.recapHost = UI.Box(canvas, "ui", "windowBg")
        st.recapHost:SetSize(RECAP_W, RECAP_H)
        st.recapHost:SetPoint("CENTER", canvas, "CENTER", 0, 0)
        st.recap = Meter.NewRecapPanel(st.recapHost, RECAP_W, RECAP_H)
        st.recap:SetPoint("TOPLEFT", st.recapHost, "TOPLEFT", 0, 0)
        st.recapHost:Hide()
    end
end

-- the threat the Threat glow sample is drawn at (the "Preview at" slider
-- on the Threat card; not saved; 100 = pulled it)
local glowSample = 92

-- the glow at each of its levels, and the alert lines in the middle
local GLOW_MODES = { glowWarn = true, glow = true, glowPulled = true }
local LINE_MODES = { opener = true, pullWarn = true, stop = true, aggro = true }
local SAMPLE_MOB = "Ragnaros"

-- the glow mode a threat belongs to (the slider picks it)
local function GlowModeFor(v)
    local G = ns.ThreatGlow
    local s = G and G.Level(v, v >= 100, G.Cfg()) or "red"
    return (s == "pulled" and "glowPulled") or (s == "red" and "glow") or "glowWarn"
end
-- the threat a glow mode is drawn at: the slider's while it is in that
-- mode's level (below the start too, for the warning), else the level's middle
local function GlowPct(mode)
    if GlowModeFor(glowSample) == mode then return glowSample end
    local c = ns.ThreatGlow.Cfg()
    if mode == "glowPulled" then return 100 end
    if mode == "glow" then return math.floor((c.red + 100) / 2) end
    return math.floor((c.start + c.red) / 2)
end
-- an alert line's text, and whether the options let it show
local function LineOf(mode)
    local G, T = ns.ThreatGlow, ns.Meter.Threat
    local t = ns.Meter.DB().threat or {}
    local screen = t.voiceWarn and t.screenAlert ~= false
    if mode == "opener" then return G.OPENER_TEXT, G.OpenerOn() end
    if mode == "pullWarn" then return G.PULL_TEXT[3], G.PullWarnOn() end
    if mode == "stop" then return T.StopText(96), screen and true or false end
    return T.AggroText(SAMPLE_MOB), (screen and t.aggroAlert ~= false) and true or false
end

local function UpdatePreview(canvas, P)
    local st, Meter = P.store, ns.Meter
    local RS = Meter.RaidSummary
    local G = ns.ThreatGlow
    -- the death samples step aside for every other mode
    if not DEATH_MODES[P.mode] then
        if st.tip then st.tip:Hide() end
        if st.recapHost then st.recapHost:Hide() end
    end
    if st.glow then
        if GLOW_MODES[P.mode] and G then
            -- the screen at its real size, the canvas a band of its left
            -- edge (the whole depth of the glow at the real size, short
            -- enough to fit even the Compact strip)
            st.win.frame:Hide()
            st.sumHost:Hide()
            st.line:Hide()
            st.lineNote:Hide()
            local w = math.floor((UIParent:GetWidth() or 1024) + 0.5)
            local h = math.floor((UIParent:GetHeight() or 640) + 0.5)
            st.glowScreen:SetSize(w, h)
            st.glowScreen:Show()
            local c = G.Cfg()
            local pct = GlowPct(P.mode)
            local state = G.Apply(st.glow, pct, pct >= 100, c, st.glowOpts)
            st.glowNote:SetText(pct >= 100 and "Left edge of the screen: a mob that turned on you"
                or format("Left edge of the screen at %d%% of a pull%s", pct, state == "off" and ": no glow yet" or ""))
            st.glowNote:Show()
            local cw = math.min(w, math.max(340, c.width * 3 + 60))
            local ch = math.min(h, 52)
            if P.Resize then P.Resize(cw, ch) end
            return
        end
        st.glowScreen:Hide()
        st.glowNote:Hide()
        G.Off(st.glow, true)
        if LINE_MODES[P.mode] and G then
            -- one alert line, as the raid-warning frame shows it
            st.win.frame:Hide()
            st.sumHost:Hide()
            local text, on = LineOf(P.mode)
            local _, wMax = G.StyleAlert(st.line, text)
            st.line:SetAlpha(on and 1 or 0.35)
            st.line:Show()
            st.lineNote:SetText(on and "" or "Off: turned off on the Threat card")
            st.lineNote:SetShown(not on)
            local nw = on and 0 or (st.lineNote:GetStringWidth() or 0)
            if P.Resize then P.Resize(math.ceil(math.max(wMax, nw)) + 24, G.ALERT_MAX + 6 + 18) end
            return
        end
        st.line:Hide()
        st.lineNote:Hide()
    end
    if DEATH_MODES[P.mode] then
        -- what hovering a death shows, or what clicking one opens
        st.win.frame:Hide()
        st.sumHost:Hide()
        local who = Me() or "Zac"
        if P.mode == "deathTip" and st.tip then
            if st.recapHost then st.recapHost:Hide() end
            st.tip:Show()
            local w, h = st.tip:SetLines(who, Meter.SampleDeathTip(who))
            if P.Resize then P.Resize(w + 10, h + 10) end
        elseif st.recap then
            if st.tip then st.tip:Hide() end
            st.recapHost:Show()
            st.recap:SetDeath(Meter.SampleDeath(who), who)
            if P.Resize then P.Resize(RECAP_W + 10, RECAP_H + 10) end
        end
        return
    end
    if P.mode == "summary" then
        st.win.frame:Hide()
        st.sumHost:Show()
        if RS and RS.Fill and RS.DemoSession then
            st.demo = st.demo or RS.DemoSession()
            st.target = st.target or RS.NewTarget(st.sumChild, nil, SUM_W)
            local sig = SummarySig()
            if st.sumSig ~= sig then
                st.sumSig = sig
                RS.Fill(st.demo, st.target, true)
            end
            -- the canvas is the whole card as laid out; it is a page long,
            -- so the strip shows its top part (its heading and the night's
            -- numbers, where the summary's colours show) at the real size
            local cx, cy, w, h
            if P.Measure then cx, cy, w, h = P.Measure(st.sumChild) end
            if cx and P.Resize then
                -- how far under the child's top the card starts
                local below = (st.sumChild:GetHeight() or 0) / 2 - (h / 2 + cy)
                st.sumHost:ClearAllPoints()
                st.sumHost:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
                st.sumHost:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", 0, 0)
                st.sumChild:ClearAllPoints()
                st.sumChild:SetPoint("TOPLEFT", st.sumHost, "TOPLEFT", 0, below - 4)
                P.Resize(SUM_W, h + 8)
            end
        end
        return
    end
    st.sumHost:Hide()
    st.win.frame:Show()
    FillMeter(P)
    -- the canvas is the window (the strip scales it)
    if P.Resize then
        local f = st.win.frame
        P.Resize((f:GetWidth() or 226) + 10, (f:GetHeight() or 96) + 10)
    end
end

local DISPLAY_LABEL = { damage = "Damage Done", healing = "Healing Done", threat = "Threat" }

local function ReplayPreview(canvas, P)
    local st, G = P.store, ns.ThreatGlow
    if G and st.glow and GLOW_MODES[P.mode] then
        -- the glow arriving (its fade in) and its pulse from the start
        local pct = GlowPct(P.mode)
        G.Off(st.glow, true)
        G.Apply(st.glow, pct, pct >= 100, G.Cfg())
        return
    end
    if G and st.line and LINE_MODES[P.mode] then
        G.PlayAlert(st.line)
        return
    end
    if P.mode == "summary" or DEATH_MODES[P.mode] then return end
    local st, Meter = P.store, ns.Meter
    local Motion = ns.Motion
    local d = Look()
    local win = st.win
    st.serial = st.serial + 1
    local mine = st.serial
    local function Live() return mine == st.serial and win.frame:IsVisible() end
    local function Arrive()
        if not Live() then return end
        SettleAll(win.rows)
        SettleAll(win.threatRows)
        FillMeter(P)
        Meter.FlashLabel(win, DISPLAY_LABEL[P.mode] or "")
        -- then a change of place on the second row, once the rows are in
        local move = d.rowMoveAnim
        if Motion and type(move) == "table" and move.style ~= "none" then
            local inn = Motion.Normalize(d[P.mode == "threat" and "threatShowAnim" or "rowShowAnim"])
            local wait = (inn.style == "none" and 0 or (inn.duration + inn.delay)) / Motion.Speed() + 0.1
            C_Timer.After(wait, function()
                if not Live() then return end
                local list = P.mode == "threat" and win.threatRows or win.rows
                local row = list and list[2]
                if row and row:IsShown() then Motion.Play(row, move, "update") end
            end)
        end
    end
    -- rows that are up go first (when they have a way of going), then
    -- everything comes back in
    local threat = P.mode == "threat"
    local hideKey = threat and "threatHideAnim" or "rowHideAnim"
    local out = d[hideKey]
    local any = false
    if Motion and Motion.Enabled() and type(out) == "table" and out.style ~= "none" then
        for _, row in ipairs((threat and win.threatRows or win.rows) or {}) do
            if row:IsShown() then any = true Meter.HideRow(row, hideKey) end
        end
    end
    if any then
        local o = Motion.Normalize(out)
        C_Timer.After((o.duration + o.delay) / Motion.Speed() + 0.1, Arrive)
    else
        Arrive()
    end
end

-- ============================================================
-- TABS
-- ============================================================
local function Tab_general(L)
    local Meter = ns.Meter
    local d = Look()

    L:Card("Windows")
    L:Desc("Window 1 is your threat window (bottom center), window 2 the "
        .. "current-fight damage window (bottom right, locked), window 3 "
        .. "the overall stacked above it - every boss and every trash pull "
        .. "of the night, updating live during a fight. Unlock to drag "
        .. "anywhere on the rows and resize from the bottom-right corner; "
        .. "the hover toolbar's first icon also locks and unlocks. Mouse "
        .. "wheel over any window scrolls the list.")
    for i, w in ipairs(d.windows) do
        BindCheck(L, w, "open", "Show window " .. i .. " (" .. (w.display == "threat" and "threat" or "meter") .. ")")
    end
    L:Desc("Opening or closing a window takes a /reload to settle. Locking, size and place are on the Position tab.")
    L:EndCard()

    -- when every meter window shows (look.visibility; nothing saved = always)
    L:Card("When the windows show")
    local vg, vs = ns.CustomAccess(Look, "visibility", nil, MeterRefresh)
    L:Add(UI.VisibilityPicker(L.current, { width = UI.CardInnerWidth(L), get = vg, set = vs,
        shows = { "always", "combat", "nocombat", "group", "raid", "instance", "mouseover" } }), 6)
    L:Desc("Hidden windows only fade out: they still take clicks and keep counting.")
    L:EndCard()

    L:Card("Updates")
    BindSlider(L, d, "updateSpeed", "Update interval", { min = 0.5, max = 3, step = 0.5,
        format = function(v) return format("%.1fs", v) end,
        desc = "Seconds between window refreshes. The parser always records everything." })
    L:EndCard()

    L:Card("Segments")
    BindSlider(L, d, "segmentsAmount", "Fights kept", { min = 5, max = 40,
        desc = "How many past fights the segment browser holds. Data "
        .. "lives in memory and clears on logout, like a fresh Details "
        .. "session." })
    BindSlider(L, d, "minCombatTime", "Minimum fight length", { min = 0, max = 20,
        format = function(v) return format("%ds", v) end,
        desc = "Fights shorter than this are discarded." })
    BindCheck(L, d, "overallClearNewBoss", "Reset overall on a new raid boss",
        "The overall segment wipes when you pull a raid boss you have "
        .. "not seen this session.")
    L:EndCard()

    L:Card("Threat")
    local t = d.threat
    BindSlider(L, t, "updateSpeed", "Scan interval", { min = 0.5, max = 3, step = 0.5,
        format = function(v) return format("%.1fs", v) end,
        desc = "Seconds between threat scans. TinyThreat ran 1.0." })
    BindCheck(L, t, "absoluteMode", "Absolute mode",
        "Sort by raw threat instead of percent, with the ranged (130%) "
        .. "and melee (110%) pull thresholds. Yours was off - relative "
        .. "mode, 100% pulls.")
    BindCheck(L, t, "hidePullBar", "Hide the 'You pull at' bar", nil)
    BindCheck(L, t, "onlyMyGroup", "Raid: only my group", nil)
    BindCheck(L, t, "showPartyPets", "Show party pets", nil)
    local function ThreatOptions()
        local T = Meter and Meter.Threat
        if T and T.ApplyOptions then T.ApplyOptions() end
    end
    BindCheck(L, t, "voiceWarn", "Warn me before I pull threat",
        "On the boss you are fighting, when you are not the one tanking it: \"Threat\" once as you "
        .. "get within 10% of the level below, then \"Stop\" with a red warning on screen (showing "
        .. "your %) at that level. One word each, so it is said at once. Quiet for the first few seconds of a fight. Warriors hear these only in "
        .. "Berserker Stance.", ThreatOptions)
    if t.voiceAt == nil then t.voiceAt = 95 end
    BindSlider(L, t, "voiceAt", "Stop warning at", { min = 80, max = 100, step = 1,
        format = function(v) return format("%d%% of pull", v) end })
    -- on unless switched off (nil = on; browsing writes nothing)
    local function OnCheck(key, label, desc)
        local w = UI.Checkbox(L.current, label, t[key] ~= false, function(v)
            t[key] = (not v) and false or nil
            ThreatOptions()
        end)
        L:Row(w, 17)
        if desc and UI.Tooltip then UI.Tooltip(w, label, desc) end
        return w
    end
    OnCheck("voiceRepeat", "Keep saying it while I stay that high",
        "\"Stop\" again every 3 seconds until you drop under it.")
    OnCheck("screenAlert", "Red warning in the middle of the screen",
        "The stop and aggro calls also show as a raid warning, with its sound.")
    OnCheck("aggroAlert", "Tell me when I pull aggro",
        "\"Aggro\" once when a boss turns on you (not in Defensive Stance).")
    -- raids only unless ticked (nil = off; browsing writes nothing)
    local dg = UI.Checkbox(L.current, "Also in dungeons and parties", t.inDungeons == true, function(v)
        t.inDungeons = v and true or nil
        ThreatOptions()
    end, { tooltip = "Every threat warning here (the voice, the red line, the glow, the weak opener and the "
        .. "pull warning) runs in raids. Tick this to have them in 5-man groups and dungeons too." })
    L:Row(dg, 17)
    -- bosses only unless ticked (nil = off)
    local tr = UI.Checkbox(L.current, "Also on trash", t.onTrash == true, function(v)
        t.onTrash = v and true or nil
        ThreatOptions()
    end, { tooltip = "The threat warnings run on bosses only. Tick this to have them on trash and other "
        .. "mobs too." })
    L:Row(tr, 17)
    -- the screen-edge glow (Meter_ThreatGlow): threat.glow nil = on for a
    -- warrior, off for everyone else; every other option nil = its default
    local G = ns.ThreatGlow
    if G then
        local GD = G.DEFAULTS
        local function GlowOptions() G.ApplyOptions() end
        L:Gap(6)
        -- the weak tank opener and the pull warning (nil = on for a warrior)
        local opOn = G.OpenerOn()
        local op = UI.Checkbox(L.current, "Warn me about a weak tank opener", opOn, function(v)
            t.opener = v and true or false
            GlowOptions()
            ns.RefreshConfig()
        end, { tooltip = "In the first seconds of a pull on an elite or a boss: if at the rates you and "
            .. "the tank are building threat you would pull within the time below, \"WEAK TANK OPENER\" in "
            .. "the middle of the screen with the raid-warning sound, \"Weak opener, hold\" said once, and the "
            .. "edges glow orange. Once per pull. On for warriors to begin with." })
        L:Row(op, 17)
        L:Dependent({
            UI.Slider(L.current, { width = 200, min = 3, max = 12, step = 1, label = "When I would pull within",
                value = tonumber(t.openerAt) or GD.openerAt,
                format = function(v) return format("%ds", v) end,
                onChange = function(v) t.openerAt = v GlowOptions() end }),
        }, opOn, 1)
        local pw = UI.Checkbox(L.current, "Warn me a few seconds before I pull", G.PullWarnOn(), function(v)
            t.pullWarn = v and true or false
            GlowOptions()
        end, { tooltip = "Later in a fight, while you would pull within 3 seconds at the rates you and the "
            .. "tank are going: \"PULLING IN 3s\" in the middle of the screen, again every 3 seconds while "
            .. "it holds. On for warriors to begin with." })
        L:Row(pw, 17)
        L:Gap(6)
        local on = G.On()
        local cb = UI.Checkbox(L.current, "Glow round the screen as I near a pull", on, function(v)
            t.glow = v and true or false
            GlowOptions()
            ns.RefreshConfig()
        end, { tooltip = "A faint orange glow at the edges of the screen from the first level (or a pull "
            .. "within the opener's time), red and pulsing from the second (or a pull 3 seconds away), "
            .. "quicker the closer it gets, and a solid red flash when a mob turns on you. Like the voice it "
            .. "stays quiet for the first seconds of a fight (a weak opener aside) and never shows while you "
            .. "tank on purpose: a warrior sees it in every stance but Defensive. On for warriors to begin with." })
        L:Row(cb, 17)
        local function GlowSlider(key, label, lo, hi, step, fmt, scale)
            scale = scale or 1
            return UI.Slider(L.current, { width = 200, min = lo, max = hi, step = step, label = label,
                format = fmt, value = (tonumber(t[key]) or GD[key]) * scale,
                onChange = function(v) t[key] = v / scale GlowOptions() end })
        end
        local function GlowColor(key, label)
            local d = GD[key]
            return UI.ColorPicker(L.current, { label = label,
                get = function() return t[key] end,
                set = function(r, g, b) t[key] = r and { r = r, g = g, b = b, a = 1 } or nil GlowOptions() end,
                default = function() return d.r, d.g, d.b, 1 end, reset = true })
        end
        local function OfPull(v) return format("%d%% of pull", v) end
        L:Dependent({
            GlowSlider("glowStart", "Starts at", 50, 95, 1, OfPull),
            GlowSlider("glowRed", "Turns red at", 60, 99, 1, OfPull),
            GlowSlider("glowStrength", "Strength", 20, 100, 5, function(v) return format("%d%%", v) end, 100),
            GlowSlider("glowWidth", "Edge width", 20, 300, 5, Px),
            GlowColor("glowColor", "Warning colour"),
            GlowColor("glowRedColor", "Danger colour"),
        }, on, 2)
        -- not a setting: the threat the preview's Threat glow is drawn at
        local pv = UI.Slider(L.current, { width = 200, min = 50, max = 100, step = 1,
            label = "Preview the glow at", value = glowSample,
            format = function(v) return v >= 100 and "Pulled it" or format("%d%%", v) end,
            onChange = function(v)
                glowSample = v
                local PV = ns.ConfigPreview
                if PV and PV.UseMode then PV.UseMode("meter.window", GlowModeFor(v)) end
            end })
        L:Row(pv, 40)
        if UI.Tooltip then
            UI.Tooltip(pv, "Preview the glow at", "Not saved. Shows the preview's Threat glow at this threat; "
                .. "all the way right is a mob that just turned on you.")
        end
    end
    L:EndCard()

    local RSm = Meter.RaidSummary
    if RSm and RSm.Cfg then
        local rc = RSm.Cfg()
        L:Card("Raid summary")
        BindCheck(L, rc, "raidSummary", "Collect a summary of each raid",
            "Your damage and ranks (raid and class), each boss, your abilities next to the rest of your class, "
            .. "what hit you hardest, your deaths and the hesitation numbers - for the whole raid.")
        BindCheck(L, rc, "raidSummaryShow", "Open it when the last boss dies",
            "Ragnaros, Onyxia, Nefarian, Hakkar, Ossirian, C'Thun, Kel'Thuzad. /zui raid opens it any time.")
        local open = UI.Button(L.current, "Open the last raid summary", { width = 200,
            onClick = function() RSm.Open() end })
        local row = { open }
        if RSm.Demo then
            row[2] = UI.Button(L.current, "Show an example", { width = 140,
                onClick = function() RSm.Demo() end })
        end
        L:Flow(row, 8, 4)
        L:Desc("Its colours are on the Look tab; the preview's Raid summary button shows the example.")
        L:EndCard()
    end

    L:Card("Report")
    BindSlider(L, d, "reportLines", "Lines to paste", { min = 1, max = 10 })
    L:EndCard()
end

local function Tab_look(L)
    local Meter = ns.Meter
    local d = Look()
    local CC = Meter.CLASS_COLORS

    L:Card("Rows")
    BindSlider(L, d, "rowHeight", "Row height", { min = 10, max = 40, format = Px,
        desc = "How tall each bar is. A window shows as many rows as fit its height." })
    BindSlider(L, d, "rowGap", "Row spacing", { min = 0, max = 10, format = Px,
        desc = "The gap between rows, in the meter and the threat window." })
    Texture(L, "Bar texture", "bar", Meter.TEX_BAR, function() return CC.WARRIOR[1], CC.WARRIOR[2], CC.WARRIOR[3] end,
        "Also set by Appearance > Fonts & Textures when the meter is ticked there.")
    BindSlider(L, d, "barAlpha", "Bar opacity", { min = 0.1, max = 1, step = 0.05,
        format = function(v) return format("%d%%", v * 100 + 0.5) end })
    L:EndCard()

    L:Card("Bar colours")
    Drop(L, "Bars are coloured by", { { "class", "Class" }, { "custom", "One colour for everyone" } },
        function() return d.barColorMode end,
        function(v) d.barColorMode = v ns.RefreshConfig() end)
    local custom = BindColor(L, d, "barColor", "Bar colour", Meter.LOOK_DEFAULTS.barColor, true)
    UI.SetEnabled(custom, d.barColorMode == "custom")
    BindCheck(L, d, "useSelfColor", "Colour my own bar", "Your bar wears its own colour instead of your class colour.",
        function() ns.RefreshConfig() end)
    local selfc = BindColor(L, d, "selfColor", "My bar's colour", Meter.LOOK_DEFAULTS.selfColor, true)
    UI.SetEnabled(selfc, d.useSelfColor and true or false)
    L:EndCard()

    -- per-state looks (look.states: your row, the leader's row)
    L:Card("Row states")
    local sg, ss = ns.CustomAccess(Look, "states", nil, MeterRefresh)
    local se = UI.StateEditor(L.current, { width = UI.CardInnerWidth(L), get = sg, set = ss,
        states = Meter.STATE_LIST, remember = STATE_PICK, fields = { color = true, textColor = true },
        defaults = function() return Meter.StateDefaults() end })
    L:Add(se, 6)
    if ns.CustomPick then ns.CustomPick.RegisterGroup("meter.bar", se) end
    L:Desc("Colour is the bar, text colour the name. Unset fields keep the colours above.")
    L:EndCard()

    L:Card("Row background")
    Texture(L, "Background texture", "rowBgTexture", Meter.TEX_BAR_BG, function() return 0.2, 0.2, 0.2 end)
    Color(L, "Background colour", function() return Meter.RowBgColor(d) end,
        function(r, g, b, a) d.rowBgColor = { r = r, g = g, b = b, a = a or 1 } end, true,
        "Drawn the whole width of every row, behind the bar.")
    BindColor(L, d, "rowHoverColor", "Under the mouse", Meter.LOOK_DEFAULTS.rowHoverColor, true,
        "The background of the row you are pointing at.")
    L:EndCard()

    L:Card("Row border")
    BindCheck(L, d, "rowBorder", "Show a border round each row", nil, function() ns.RefreshConfig() end)
    local bc = BindColor(L, d, "rowBorderColor", "Border colour", Meter.LOOK_DEFAULTS.rowBorderColor, true)
    local bs = BindSlider(L, d, "rowBorderSize", "Border thickness", { min = 1, max = 4, format = Px,
        desc = "1 px is one screen pixel, the thinnest line there is." })
    UI.SetEnabled(bc, d.rowBorder ~= false)
    UI.SetEnabled(bs, d.rowBorder ~= false)
    L:EndCard()

    L:Card("Icons")
    BindCheck(L, d, "showIcons", "Show an icon on each row", nil, function() ns.RefreshConfig() end)
    local spec = BindCheck(L, d, "useSpecIcons", "Spec icons when the spec is known",
        "Off, or until a fight shows the spec, the class icon.")
    local size = BindSlider(L, d, "iconSizeOffset", "Icon size", { min = -12, max = 4, step = 1,
        format = function(v)
            v = math.floor(v + (v < 0 and -0.5 or 0.5))
            if v == 0 then return "Row height" end
            return format("%+d px", v)
        end,
        desc = "Next to the row height: below zero leaves a margin round the icon." })
    UI.SetEnabled(spec, d.showIcons ~= false)
    UI.SetEnabled(size, d.showIcons ~= false)
    local dmf = BindCheck(L, d, "dmfIcon", "Mark who has the Darkmoon Faire damage buff",
        "In a raid, a small Darkmoon Faire icon after the name of everyone with Sayge's Dark Fortune of "
        .. "Damage (+10% damage), so you can see who has it. Checked every 15 seconds.",
        function(v) if Meter.DMFScan then Meter.DMFScan() end if Meter.DirtyAll then Meter.DirtyAll() end ns.RefreshConfig() end)
    local ob = BindCheck(L, d, "dmfOnlyBuffed", "Only while I have my world buffs on",
        "Rallying Cry, Warchief's Blessing, Zandalar, Songflower or a Dire Maul buff.",
        function() if Meter.DMFScan then Meter.DMFScan() end if Meter.DirtyAll then Meter.DirtyAll() end MeterRefresh() end)
    UI.SetEnabled(ob, d.dmfIcon ~= false)
    -- not asked on TBC (no world-buff raiding there): dimmed, and the
    -- tooltip says so
    if Meter.DMF_WORLD_BUFFS == false then
        UI.SetEnabled(ob, false)
        if UI.Tooltip then UI.Tooltip(ob, "Only while I have my world buffs on", "Not used on "
            .. (ns.FlavorName and ns.FlavorName() or "this game") .. ": the mark shows in any raid.") end
    end
    -- Classic Era's world buffs: dimmed where the mark is off (Core_Flavor;
    -- the note at the top of the page says why)
    if Meter.DMF_ON == false then
        UI.SetEnabled(dmf, false)
        UI.SetEnabled(ob, false)
    end
    L:EndCard()

    L:Card("Window")
    BindCheck(L, d, "bgShown", "Fill the window background", "Off, the windows are bare rows on the screen.",
        function() ns.RefreshConfig() end)
    local bgc = Color(L, "Background colour", function() return Meter.WinBgColor(d) end,
        function(r, g, b, a) d.bgColor = { r = r, g = g, b = b, a = a or 1 } end, true)
    UI.SetEnabled(bgc, d.bgShown and true or false)
    BindCheck(L, d, "winBorder", "Border round the window", nil, function() ns.RefreshConfig() end)
    local wbc = BindColor(L, d, "winBorderColor", "Window border colour", Meter.LOOK_DEFAULTS.winBorderColor, true)
    local wbs = BindSlider(L, d, "winBorderSize", "Window border thickness", { min = 1, max = 6, format = Px })
    UI.SetEnabled(wbc, d.winBorder and true or false)
    UI.SetEnabled(wbs, d.winBorder and true or false)
    L:EndCard()

    L:Card("Title bar")
    BindCheck(L, d, "titleBar", "Show a title bar", "A strip on top of each window naming what it shows. "
        .. "It sits above the rows, so the window keeps its size; the toolbar moves into it.",
        function() ns.RefreshConfig() end)
    local on = d.titleBar and true or false
    local th = BindSlider(L, d, "titleHeight", "Title bar height", { min = 12, max = 30, format = Px })
    local tt = Texture(L, "Title bar texture", "titleTexture", ns.FLAT or "Interface\\Buttons\\WHITE8X8",
        function() return 0.3, 0.3, 0.3 end)
    local tc = BindColor(L, d, "titleColor", "Title bar colour", Meter.LOOK_DEFAULTS.titleColor, true)
    local ts = BindCheck(L, d, "titleSegment", "Name the segment too", "\"Damage Done - Current fight\" rather than \"Damage Done\".")
    for _, w in ipairs({ th, tt, tc, ts }) do UI.SetEnabled(w, on) end
    L:EndCard()

    L:Card("Toolbar")
    Drop(L, "Show the toolbar", { { "hover", "While the mouse is over the window" }, { "always", "Always" } },
        function() return d.toolbarMode end, function(v) d.toolbarMode = v end, 260,
        "The five icons over a window: mode, segment, display, report and reset.")
    L:EndCard()

    L:Card("Threat rows")
    BindCheck(L, d, "threatIcons", "Show role icons", nil, function() ns.RefreshConfig() end)
    local ti = BindSlider(L, d, "threatIconSize", "Role icon size", { min = 8, max = 30, format = Px })
    UI.SetEnabled(ti, d.threatIcons ~= false)
    L:Desc("Threat rows share the row height, spacing and bar texture above; their colours "
        .. "are the threat itself, green to red.")
    L:EndCard()

    local RSm = Meter.RaidSummary
    if RSm and RSm.COLOUR_DEFAULTS then
        local D = RSm.COLOUR_DEFAULTS
        L:Card("Raid summary colours")
        local function RS(key, label)
            local c = D[key]
            BindColor(L, d, key, label, { r = c[1], g = c[2], b = c[3], a = 1 }, false)
        end
        RS("rsGood", "Good")
        RS("rsMid", "Middling")
        RS("rsBad", "Needs work")
        L:Desc("Ranks, shares of the best and the fixes on the raid summary page.")
        L:EndCard()
    end
end

-- Where one text or part sits: ZacUI's anchor picker over the look's
-- anchors.<key> (nil = its built-in spot, Meter.AnchorDefaults).
local function Spot(L, key, targets, o)
    local Meter = ns.Meter
    local list = {}
    for _, k in ipairs(targets) do
        if k ~= key then list[#list + 1] = { value = k, text = Meter.ANCHOR_LABELS[k] or k } end
    end
    local get, set = ns.CustomAccess(Look, "anchors", key, MeterRefresh)
    local spec = { key = "meter." .. key, anchorGet = get, anchorSet = set,
        anchorDefaults = function() return Meter.AnchorDefaults(key) end, targets = list,
        defaultTargetLabel = "Where it sits now", anchorMin = -60, anchorMax = 60 }
    -- the value's and the names' formats (look.formats.<value|name>;
    -- nothing saved = the number layout / the names as they are)
    if key == "value" then
        local fg, fs = ns.CustomAccess(Look, "formats", "value", MeterRefresh)
        spec.formatGet, spec.formatSet, spec.formatKinds = fg, fs, { number = true }
        spec.formatDefaults = function() return Meter.ValueDefaults(Look()) end
        spec.formatTokens = { { token = "total", label = "total" }, { token = "ps", label = "per second" },
            { token = "pct", label = "share" } }
        spec.formatSample = function(f)
            return ns.FormatText(f, Meter.ValueDefaults(Look()), { total = 1234567, ps = 1520, pct = 23.4 },
                { total = "number", ps = "number", pct = "percent" })
        end
    elseif key == "name" then
        local fg, fs = ns.CustomAccess(Look, "formats", "name", MeterRefresh)
        spec.formatGet, spec.formatSet, spec.formatKinds = fg, fs, { name = true }
        spec.formatSample = function(f) return ns.FormatName("Thunderfury-Gehennas", f) end
    end
    if o and o.label then spec.label = o.label end
    if o and o.gap then spec.gap = o.gap end
    if o and o.part then return UI.FrameElement(L, spec) end
    return UI.TextElement(L, spec)
end

local function Tab_text(L)
    local Meter = ns.Meter
    local d = Look()
    local me = (Me())

    L:Card("Names")
    Font(L, "Name text", "nameFont", Meter.NameFontDefaults(d), me .. "  Brakka  Orrin")
    Drop(L, "Name colour", { { "white", "White" }, { "class", "Class colour" }, { "custom", "One colour" } },
        function() return d.nameColorMode end, function(v) d.nameColorMode = v ns.RefreshConfig() end)
    local nc = BindColor(L, d, "nameColor", "Name colour", Meter.LOOK_DEFAULTS.nameColor, true)
    UI.SetEnabled(nc, d.nameColorMode == "custom")
    BindCheck(L, d, "showRank", "Number the rows", "\"3. " .. me .. "\": each name with its place in the list.")
    BindCheck(L, d, "removeRealm", "Hide realm names", nil)
    Spot(L, "name", Meter.ROW_TARGETS)
    L:EndCard()

    L:Card("Numbers")
    Font(L, "Number text", "numberFont", Meter.NumberFontDefaults(d), "371.4K I 2.0K  (18.6%)")
    BindColor(L, d, "numberColor", "Number colour", Meter.LOOK_DEFAULTS.numberColor, true)
    local abbrevs = { { 1, "Plain (12345.0)" }, { 2, "12.3K" }, { 3, "12.3K / 123K" }, { 4, "12K" } }
    Drop(L, "Number abbreviation", abbrevs, function() return d.psAbbrev end,
        function(v) d.psAbbrev = v MeterRefresh() end)
    local layouts = {
        { "both", "Total and per second" }, { "paren", "Total (per second)" }, { "total", "Total only" },
        { "ps", "Per second only" }, { "pct", "Total (share)" }, { "all", "Total, per second and share" },
    }
    Drop(L, "What the number shows", layouts, function() return d.numberLayout end,
        function(v) d.numberLayout = v MeterRefresh() ns.RefreshConfig() end, 240,
        "Counts (deaths, interrupts) are always a plain number. Share is the row's part of the window's total.")
    local sepOn = d.numberLayout == "both" or d.numberLayout == "all" or d.numberLayout == nil
    local sep = UI.Field(L.current, "Between total and per second", function(host)
        return UI.EditBox(host, { width = 120, text = d.numberSep or " I ",
            onEnter = function(text) d.numberSep = text MeterRefresh() end })
    end, { width = 200 })
    L:Add(sep, 6)
    UI.SetEnabled(sep, sepOn)
    L:Desc("Yours was \" I \" (a capital I with a space each side). Press Enter to use it.")
    Spot(L, "value", Meter.ROW_TARGETS)
    L:EndCard()

    L:Card("Title and label")
    Font(L, "Title text", "titleFont", Meter.TitleFontDefaults(d), "Damage Done  -  Current fight",
        "The title bar, and the name that shows over a window when you change its display or segment.")
    Spot(L, "title", { "titlebar" })
    L:EndCard()

    L:Card("Threat")
    Font(L, "Threat text", "threatFont", Meter.ThreatFontDefaults(d), me .. "  47.9K (82.4%)")
    -- where the name and the threat sit on the threat rows
    -- (look.anchors.threatName / threatValue; nothing saved = as always)
    Spot(L, "threatName", Meter.THREAT_TARGETS, { label = "Where the name sits" })
    Spot(L, "threatValue", Meter.THREAT_TARGETS, { label = "Where the threat sits" })
    L:EndCard()
end

local function Tab_anim(L)
    L:Card("Rows")
    Anim(L, "When a row appears", "rowShowAnim", nil,
        "A new name joining the list, and every row at the start of a fight.")
    Anim(L, "When a row goes", "rowHideAnim", { "none", "fade", "slide", "pop", "bounce" },
        "Someone dropping off the list, or the list clearing.")
    Anim(L, "When the order changes", "rowMoveAnim", { "none", "fade", "slide", "pop", "pulse", "bounce", "flash" },
        "A highlight on a row whose place in the list just changed hands.")
    L:EndCard()
    L:Card("Threat rows")
    Anim(L, "When a threat row appears", "threatShowAnim", { "none", "fade", "slide", "pop", "bounce" },
        "The threat list filling in when a fight starts or you pick a new target.")
    Anim(L, "When a threat row goes", "threatHideAnim", { "none", "fade", "slide", "pop", "bounce" })
    L:EndCard()
    L:Card("Label")
    Anim(L, "The window's label", "labelAnim", { "none", "fade", "slide", "pop", "flash" },
        "The display or segment name that shows over a window when you change it, and how it goes "
        .. "(the delay is how long it stays first). None turns the label off.")
    L:Desc("Replay in the preview plays them all. Appearance > Motion turns every animation off or speeds them up.")
    L:EndCard()
end

local POINT_NAMES = {
    TOPLEFT = "top-left corner", TOP = "top edge", TOPRIGHT = "top-right corner",
    LEFT = "left edge", CENTER = "middle", RIGHT = "right edge",
    BOTTOMLEFT = "bottom-left corner", BOTTOM = "bottom edge", BOTTOMRIGHT = "bottom-right corner",
}

local function Tab_pos(L)
    local Meter = ns.Meter
    local d = Look()
    for i, w in ipairs(d.windows) do
        L:Card(WindowName(i, w))
        BindCheck(L, w, "locked", "Lock its place and size", "Unlocked, drag the rows to move it and the "
            .. "bottom-right corner to resize it.")
        BindCheck(L, w, "clickthrough", "Click-through in combat",
            "Mouse goes straight through the window while fighting.")
        -- the live windows follow on the next frame (Meter.RestyleAll)
        local function Geo() end
        BindSlider(L, w, "w", "Width", { min = 100, max = 600, format = Px, width = 240, after = Geo })
        BindSlider(L, w, "h", "Height", { min = 50, max = 600, format = Px, width = 240, after = Geo })
        BindSlider(L, w, "x", "Across", { min = -1200, max = 1200, format = Px, width = 240, after = Geo })
        BindSlider(L, w, "y", "Up", { min = -800, max = 800, format = Px, width = 240, after = Geo,
            desc = "Measured from the " .. (POINT_NAMES[w.point or ""] or "middle") .. " of the screen. "
            .. "A threat window sitting under the target frame ignores these." })
        L:EndCard()
    end
    -- the list's order and length (look.layout; nothing saved = biggest
    -- first, everyone)
    L:Card("Order and length")
    local lg, ls = ns.CustomAccess(Look, "layout", nil, MeterRefresh)
    L:Add(UI.LayoutPicker(L.current, { width = UI.CardInnerWidth(L), get = lg, set = ls,
        fields = { sort = true, reverse = true, max = true }, sorts = Meter.SORTS, maxItems = 40,
        defaults = { sort = "value", max = 40 } }), 6)
    L:Desc("Every meter window. The bars stay measured against the biggest.")
    L:EndCard()
    L:Card("Class icon on the rows")
    Spot(L, "icon", Meter.ROW_TARGETS, { part = true })
    L:Desc("Every window's rows. The name follows the icon unless it is placed itself (Text tab).")
    L:EndCard()
    L:Card("Role icon on the threat rows")
    Spot(L, "threatIcon", Meter.THREAT_TARGETS, { part = true, gap = 4 })
    L:EndCard()
    L:Card("Threat window")
    local t = d.threat
    BindCheck(L, t, "dockUnderTarget", "Sit right under the target frame",
        "The threat window follows your target frame, and drops below the target's cast bar "
        .. "while it is casting. Off: the window stays where you put it.",
        function()
            local T = Meter and Meter.Threat
            if T and T.ApplyOptions then T.ApplyOptions() end
        end)
    L:EndCard()
end

local function Tab_adv(L)
    local Meter = ns.Meter
    L:Card("Look")
    local reset = UI.Button(L.current, "Reset the look", { width = 140,
        onClick = function()
            local d = Look()
            for _, k in ipairs(Meter.LOOK_KEYS or {}) do d[k] = nil end
            for _, k in ipairs({ "rsGood", "rsBad", "rsMid" }) do d[k] = nil end
            if Meter.ForgetLook then Meter.ForgetLook() end
            Look()
            ns.SettingsChanged("reset")
            ns.RefreshConfig()
        end })
    L:Row(reset, 26)
    L:Desc("Every setting on the Look, Text and Animation tabs back to how the meter first looked. "
        .. "Windows, segments and threat options stay as they are.")
    L:EndCard()

    L:Card("Data")
    local wipeData = UI.Button(L.current, "Reset meter data", { width = 140,
        onClick = function()
            if Meter.ResetData then Meter.ResetData() end
        end })
    L:Row(wipeData, 26)
    L:Desc("Wipes every segment and the overall, exactly like the "
        .. "toolbar's reset icon.")
    L:EndCard()
end

-- ============================================================
-- PAGE
-- ============================================================
-- the strip's modes (the threat glow's only while its file loaded)
local function PreviewModes()
    local m = {
        { id = "damage", label = "Damage" },
        { id = "healing", label = "Healing" },
        { id = "threat", label = "Threat" },
    }
    if ns.ThreatGlow then
        m[#m + 1] = { id = "glowWarn", label = "Glow: warning" }
        m[#m + 1] = { id = "glow", label = "Glow: danger" }
        m[#m + 1] = { id = "glowPulled", label = "Glow: pulled" }
        m[#m + 1] = { id = "opener", label = "Weak opener" }
        m[#m + 1] = { id = "pullWarn", label = "Pulling in 3s" }
        m[#m + 1] = { id = "stop", label = "Threat stop" }
        m[#m + 1] = { id = "aggro", label = "Aggro" }
    end
    if ns.Meter and ns.Meter.NewRecapPanel then
        m[#m + 1] = { id = "deathTip", label = "Death tooltip" }
        m[#m + 1] = { id = "deathRecap", label = "Death recap" }
    end
    m[#m + 1] = { id = "summary", label = "Raid summary" }
    return m
end

RegisterPage("Meter", function(L)
    local Meter = ns.Meter
    L:Header("Damage meter",
        "Damage meter and threat display. Defaults are the ported Details setup.")

    if not Meter or not Meter.DB or not Meter.Look then
        L:Notice("missing", "The meter engine did not load.")
        return
    end

    -- a sample's text or icon picked in the preview: its spot
    if ns.CustomPick then
        ns.CustomPick.SetHandler("meter.window", function(el)
            local k = type(el) == "string" and el:match("^meter%.(.+)$")
            if not k then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            ZacUIDB.config.tabs.meter = (k == "bar") and "look" or (k == "icon" or k == "threatIcon") and "pos" or "text"
            ns.RefreshConfig()
        end)
    end

    if not (ZacUIDB.modules and ZacUIDB.modules.meter) then
        L:Notice("off", "The Damage meter module is off; these settings wait for it.", "Modules > HUD", "meter")
    end

    L:Preview({
        key = "meter.window",
        title = "Meter window",
        width = CANVAS_W, height = CANVAS_H,
        modes = PreviewModes(),
        -- the summary is a page long: its top part at the real size reads
        -- better than the whole page shrunk to a stamp
        overflow = function(P) return P.mode == "summary" and "clip" or nil end,
        build = BuildPreview,
        update = UpdatePreview,
        replay = ReplayPreview,
    })

    L:Tabs({
        { id = "general", label = "General",   build = Tab_general },
        { id = "look",    label = "Look",      build = Tab_look },
        { id = "text",    label = "Text",      build = Tab_text },
        { id = "anim",    label = "Animation", build = Tab_anim },
        { id = "pos",     label = "Position",  build = Tab_pos },
        { id = "adv",     label = "Advanced",  build = Tab_adv },
    })
end)
