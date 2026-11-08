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
        .. "death deaths recap killing blow overkill interrupt dispel "
        .. "header clock window windows new close add breakdown abilities spells targets pin pinned "
        .. "snap snapping scale grow enemy enemies segment fight fights sync "
        .. "flat gloss shine outline dim dimmer edge highlight crisp polish "
        .. "blizzard game meter built-in builtin stock edit mode classic columns hits crit")
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

-- a checkbox over a key whose nil is `dflt` (Meter v2's per-window
-- options: nothing is written until it is clicked)
local function BindCheckD(L, tbl, key, label, desc, dflt, after)
    local cur = tbl[key]
    if cur == nil then cur = dflt end
    local w = UI.Checkbox(L.current, label, cur and true or false,
        function(v)
            tbl[key] = v and true or false
            if after then after(v) else MeterRefresh() end
        end)
    L:Row(w, 17)
    if desc then L:Desc(desc) end
    return w
end

-- the live window showing saved window `w` (nil while it is closed)
local function LiveWindow(w)
    local Meter = ns.Meter
    for _, win in ipairs(Meter and Meter.windowFrames or {}) do
        if win.settings == w then return win end
    end
end

-- look.breakdown.<key> (Meter v2; the table is made on the first write)
local function BDGet(key)
    local Meter = ns.Meter
    local BD = Meter and Meter.Breakdown
    if BD and BD.Opt then return BD.Opt(key) end
    local b = Look().breakdown
    if type(b) == "table" then return b[key] end
end
local function BDSet(key, v)
    local d = Look()
    if type(d.breakdown) ~= "table" then d.breakdown = {} end
    d.breakdown[key] = v
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

-- (each game version's own boss: Core_Flavor)
local SAMPLE_MOB = ({ tbc = "Gruul the Dragonkiller", forever = "Onyxia", retail = "Raider's Training Dummy" })[ns.Flavor and ns.Flavor() or "era"] or "Ragnaros"

-- your abilities in the sample fight, for the Breakdown mode (Meter v2):
-- id, the name it falls back to, its share of your damage, hits, crits
local SAMPLE_SPELLS = {
    WARRIOR = { { 23894, "Bloodthirst", 0.31, 22, 9 }, { 1680, "Whirlwind", 0.22, 14, 5 }, { 1, "Melee", 0.24, 96, 31 },
        { 11567, "Heroic Strike", 0.13, 30, 10 }, { 20662, "Execute", 0.10, 6, 3 } },
    MAGE = { { 10181, "Frostbolt", 0.62, 48, 12 }, { 10199, "Fire Blast", 0.21, 14, 4 }, { 10230, "Frost Nova", 0.17, 9, 2 } },
    ROGUE = { { 11294, "Sinister Strike", 0.42, 40, 14 }, { 1, "Melee", 0.38, 120, 38 }, { 11300, "Eviscerate", 0.20, 9, 4 } },
    WARLOCK = { { 11661, "Shadow Bolt", 0.70, 38, 9 }, { 11713, "Curse of Agony", 0.18, 12, 0 }, { 11672, "Corruption", 0.12, 14, 0 } },
    HUNTER = { { 2, "Auto Shot", 0.48, 70, 21 }, { 20904, "Aimed Shot", 0.30, 9, 4 }, { 14290, "Multi-Shot", 0.22, 14, 5 } },
}
local function SampleSpells(class, total)
    local out = {}
    for _, e in ipairs(SAMPLE_SPELLS[class or ""] or SAMPLE_SPELLS.WARRIOR) do
        local t = math.floor(total * e[3] + 0.5)
        out[e[1]] = { id = e[1], name = e[2], total = t, counter = e[4], c_amt = e[5], targets = { [SAMPLE_MOB] = t } }
    end
    return out
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
    -- your row's breakdown: its abilities and its two targets
    local mine = dmg[3]
    mine.spells = SampleSpells(myClass, mine.total)
    mine.targets = { [SAMPLE_MOB] = math.floor(mine.total * 0.86), ["Flamewaker Elite"] = math.floor(mine.total * 0.14) }
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
-- the sample fight as the game's meter hands a session out (Meter v2's
-- Live mode): its sources in order, the fields the live view reads
local function LiveSession(fight)
    local out = {}
    for _, a in ipairs(fight.damage.actors) do
        out[#out + 1] = { name = a.name, totalAmount = a.total, amountPerSecond = math.floor(a.total / 184),
            classFilename = a.class, isLocalPlayer = a.isSelf and true or false }
    end
    return { combatSources = out }
end

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
    -- the Header mode: a wide window, so the whole title shows
    if P.mode == "header" then w = math.max(w, 340) end
    -- a breakdown open from the Breakdown mode goes with any other mode
    if Meter.Breakdown and P.mode ~= "breakdown" and win.bd then Meter.Breakdown.Close(win) end
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
        -- the Header mode names a past fight in the title, the way a
        -- window on one does ("Damage Done  -  #3 Ragnaros (3:04)")
        win.sampleSegment = (P.mode == "header") and ("#3 " .. SAMPLE_MOB) or nil
        -- the Live mode (Forever / Retail): the window painted by the live
        -- view (Meter_Win_Live) from a made-up session of the game's meter
        win.liveSample = (P.mode == "live" and Meter.Live) and LiveSession(st.fight) or nil
        local BD = Meter.Breakdown
        Meter.FillPreviewWindow(win, st.fight, P.mode == "healing" and "heal_done" or "damage_done")
        -- the Breakdown mode: your row (the third) opened as bars
        if BD and P.mode == "breakdown" then
            local me = st.fight.damage.actors[3]
            if not (win.bd and win.bd.name == me.name) then BD.Open(win, me) else BD.Style(win) BD.Refresh(win) end
        end
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

-- (each game version's own boss: Core_Flavor)
-- Forever gives addons no combat log: the meter fills from the game's own
-- meter when a fight ends, and keeps no hits before a death
local function NoLog() return ns.NoCombatLog and ns.NoCombatLog() and true or false end

-- The raid summary's example night as this game version's summary would
-- show it (the summary's own example is a Classic Era Naxxramas night):
-- TBC's is Karazhan; Forever's is Onyxia's Lair from the game's meter,
-- so no "what hit you", no death causes and no hits a minute.
local KARA = { "Attumen the Huntsman", "Moroes", "Maiden of Virtue", "Opera Event", "The Curator",
    "Terestian Illhoof", "Shade of Aran", "Netherspite", "Chess Event", "Prince Malchezaar", "Nightbane" }
local function VersionDemo(s)
    local fl = ns.Flavor and ns.Flavor() or "era"
    if fl == "era" then return s end
    if fl == "tbc" then
        s.raid, s.instanceID = "Karazhan", 532
        local old = s.bosses
        s.bosses = {}
        for i, name in ipairs(KARA) do
            local b = old[i]
            if b then b.name = name b.killed = true s.bosses[#s.bosses + 1] = b end
        end
        -- only the swings: the Naxxramas spells are not on TBC
        for who, t in pairs(s.taken) do s.taken[who] = { [1] = t[1] } end
        for _, d in ipairs(s.myDeaths) do
            d.where, d.src, d.spell = "Prince Malchezaar", "Prince Malchezaar", 1
            for _, e in ipairs(d.before or {}) do if e.dmg then e.src = "Prince Malchezaar" end end
        end
        return s
    end
    -- (Forever: Onyxia's Lair; Retail: its raids are not listed yet, so the
    -- example night is one boss from the game's meter)
    if fl == "retail" then s.raid, s.instanceID = "A Retail raid", 0 else s.raid, s.instanceID = "Onyxia's Lair", 249 end
    local b = s.bosses[1]
    if b then b.name, b.killed = (fl == "retail") and "The last boss" or "Onyxia", true end
    s.bosses = { b }
    s.taken, s.myDeaths = {}, {}
    for _, p in pairs(s.players) do
        for _, sp in pairs(p.spells or {}) do sp.n, sp.c = nil, nil end
    end
    return s
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
    -- Forever: the numbers come from the game's own meter when the fight
    -- ends (Meter_GameMeter), so the sample is the window after a fight
    if NoLog() then
        st.foreverNote = UI.Font(canvas, F.SMALL, { text = (ns.Meter and ns.Meter.Live)
            and "After the fight: filled from the game's meter (Live: in a fight)"
            or "After the fight: Forever fills the meter when it ends",
            cat = "text", key = "gray" })
        st.foreverNote:SetPoint("TOP", st.win.frame, "BOTTOM", 0, -2)
        st.foreverNote:Hide()
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
    if st.foreverNote then st.foreverNote:Hide() end
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
            if NoLog() and st.recap.SetNote and Meter.FOREVER_DEATH_NOTE then
                st.recap:SetNote(who, format("%s died 1 time", who), Meter.FOREVER_DEATH_NOTE)
            else
                st.recap:SetDeath(Meter.SampleDeath(who), who)
            end
            if P.Resize then P.Resize(RECAP_W + 10, RECAP_H + 10) end
        end
        return
    end
    if P.mode == "summary" then
        st.win.frame:Hide()
        st.sumHost:Show()
        if RS and RS.Fill and RS.DemoSession then
            st.demo = st.demo or VersionDemo(RS.DemoSession())
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
    -- Forever: what the window shows once the fight is over
    if st.foreverNote then
        st.foreverNote:SetShown(P.mode == "damage" or P.mode == "healing")
        if P.mode == "live" then
            st.foreverNote:SetText("In a fight: live from the game's own meter")
            st.foreverNote:Show()
        elseif Meter.Live then
            st.foreverNote:SetText("After the fight: filled from the game's meter (Live: in a fight)")
        end
    end
    -- the canvas is the window (the strip scales it)
    if P.Resize then
        local f = st.win.frame
        P.Resize((f:GetWidth() or 226) + 10, (f:GetHeight() or 96) + 10)
    end
end

local DISPLAY_LABEL = { damage = "Damage Done", healing = "Healing Done", threat = "Threat",
    breakdown = "Damage Done", header = "Damage Done", live = "Damage Done" }

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

    -- (2026-11-08, Zac: "in forever and retail isnt there a blizzard made
    -- damage meter? ... make sure the damage meters use those options by
    -- default") WoW Forever and Retail only: whose damage windows these are
    local GW = Meter.Win
    local gameMeter = GW and GW.GameMeterAvailable and GW.GameMeterAvailable()
    if gameMeter then
        L:Card("Damage windows")
        local items = { { "look", "As the look decides" }, { "game", "The game's own meter" }, { "zacui", "ZacUI's meter" } }
        Drop(L, "Damage windows", items, function()
            local v = d.gameMeter
            if v == nil then return "look" end
            return v and "game" or "zacui"
        end, function(v)
            if v == "look" then d.gameMeter = nil else d.gameMeter = (v == "game") end
            if Meter.RestyleAll then Meter.RestyleAll() end
            if ns.SettingsChanged then ns.SettingsChanged("meter.gameMeter") end
            ns.RefreshConfig()
        end, 220)
        local uses = Meter.UsesGameMeter and Meter.UsesGameMeter()
        L:Desc((uses and "In use now: the game's own damage meter, with its own look and options (set up in the game's "
            .. "Edit Mode). ZacUI keeps its threat window." or "In use now: ZacUI's damage windows. They read the game's "
            .. "own meter for their numbers, as this client gives addons no combat log.")
            .. " As the look decides: the game's meter under WoW Forever and Blizzard style, ZacUI's under ZacUI and Classic.")
        if uses and GW.OpenGameMeterOptions then
            local open = UI.Button(L.current, "Open the game's meter options", { width = 220,
                onClick = function() GW.OpenGameMeterOptions() end })
            L:Row(open, 26)
        end
        L:EndCard()
    end

    L:Card("Windows")
    L:Desc("Window 1 is your threat window (bottom center), window 2 the "
        .. "current-fight damage window (bottom right, locked), window 3 "
        .. "the overall stacked above it - every boss and every trash pull "
        .. "of the night, updating live during a fight. Unlock to drag "
        .. "anywhere on the rows and resize from the bottom-right corner; "
        .. "the hover toolbar's first icon also locks and unlocks. Mouse "
        .. "wheel over any window scrolls the list.")
    -- (Meter v2) every window opens and closes at once; a meter window
    -- picks its mode and fight here as its header's menus do
    local Win = Meter.Win
    local modes = {}
    for _, key in ipairs(Meter.DISPLAY_ORDER or {}) do
        local disp = Meter.DISPLAYS[key]
        if disp then modes[#modes + 1] = { key, disp.label } end
    end
    for i, w in ipairs(d.windows) do
        local shown = BindCheck(L, w, "open", "Show window " .. i .. " (" .. (w.display == "threat" and "threat" or "meter") .. ")", nil,
            function(v) if Win and Win.SetOpen then Win.SetOpen(i, v) else MeterRefresh() end end)
        if Win and Win.GameOwns and Win.GameOwns(w) then
            UI.SetEnabled(shown, false, "The game's own damage meter is in use (Damage windows, above).")
        end
        if w.display ~= "threat" and #modes > 0 then
            Drop(L, "Window " .. i .. " shows", modes, function() return w.display end, function(v)
                local live = LiveWindow(w)
                if live then live:SetDisplay(v) else w.display = v end
                MeterRefresh()
            end, 200)
            Drop(L, "Window " .. i .. "'s fight", { { 0, "Current fight" }, { -1, "Overall" } },
                function() return (w.segment == -1) and -1 or 0 end, function(v)
                    local live = LiveWindow(w)
                    if live then live:SetSegment(v) else w.segment = v end
                    MeterRefresh()
                end, 200)
        end
        if i > 1 and Win then
            local close = UI.Button(L.current, "Close window " .. i, { width = 140,
                onClick = function()
                    local live = LiveWindow(w)
                    if live then live:Close()
                    else
                        table.remove(d.windows, i)
                        if ns.SettingsChanged then ns.SettingsChanged("meter.windows") end
                    end
                    ns.RefreshConfig()
                end })
            L:Row(close, 26)
        end
    end
    if Win then
        local add = UI.Button(L.current, "Add a window", { width = 140,
            onClick = function()
                local from
                for _, win in ipairs(Meter.windowFrames) do if win.id == 1 then from = win end end
                Win.Add(from or Meter.windowFrames[1])
                ns.RefreshConfig()
            end })
        L:Row(add, 26)
        if #d.windows >= (Win.MAX or 5) then UI.SetEnabled(add, false, format("%d windows is the most there can be.", Win.MAX or 5)) end
        L:Desc(format("Up to %d windows, each with its own mode and fight. They open and close at once; "
            .. "the + and x in a window's header do the same. Locking, size, scale and place are on the "
            .. "Position tab.", Win.MAX or 5))
    else
        L:Desc("Opening or closing a window takes a /reload to settle. Locking, size and place are on the Position tab.")
    end
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
    BindCheck(L, d, "confirmReset", "Ask before the reset icon wipes the data",
        "The reset icon in a window's header (and the Reset meter data key) ask first.")
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
            if v then t[key] = nil else t[key] = false end
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
        }, opOn, 1, nil, "Warn me about a weak tank opener")
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
        }, on, 2, nil, "Glow round the screen as I near a pull")
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
    if Meter.Breakdown then
        local w = UI.Slider(L.current, { width = 200, min = 0, max = 15, step = 1,
            label = "Lines from a breakdown", value = tonumber(BDGet("reportLines")) or 0,
            format = function(v) return v < 1 and "Same as above" or tostring(v) end,
            onChange = function(v) BDSet("reportLines", v >= 1 and v or nil) MeterRefresh() end })
        L:Row(w, 40)
        L:Desc("The report icon on a window with a breakdown open pastes its abilities (\"1. Bloodthirst 123.4K (31.2%)\").")
    end
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
    -- (2026-11-07 polish) the flat fill, and the light and shade option
    BindCheck(L, d, "barFlat", "Flat bars when no texture is picked",
        "A clean flat fill (the polished look). Off: the faded bar the meter wore before.", function() MeterRefresh() end)
    BindCheck(L, d, "rowGloss", "Light and shade on the bars",
        "A soft light along the top of each bar and a shade along the bottom.")
    -- (Meter v2) your own row, and which way the list grows
    Drop(L, "Your own row", { { "follow", "Takes the last row when it is off the list" },
        { "pin", "Pinned at the edge, with a line" }, { "off", "Only where it ranks" } },
        function() return d.pinSelf or "follow" end, function(v) d.pinSelf = v MeterRefresh() end, 280,
        "Pinned, your row stays in sight however far the list is scrolled.")
    Drop(L, "The list grows", { { "down", "Down from the header" }, { "up", "Up from the bottom (the header at the bottom)" } },
        function() return d.grow or "down" end, function(v) d.grow = v MeterRefresh() end, 280)
    L:EndCard()

    L:Card("Bar colours")
    Drop(L, "Bars are coloured by", { { "class", "Class" }, { "custom", "One colour for everyone" } },
        function() return d.barColorMode end,
        function(v) d.barColorMode = v ns.RefreshConfig() end)
    local custom = BindColor(L, d, "barColor", "Bar colour", Meter.LOOK_DEFAULTS.barColor, true)
    UI.SetEnabled(custom, d.barColorMode == "custom", 'Needs "Bars are coloured by" set to one colour for everyone.')
    BindCheck(L, d, "useSelfColor", "Colour my own bar", "Your bar wears its own colour instead of your class colour.",
        function() ns.RefreshConfig() end)
    local selfc = BindColor(L, d, "selfColor", "My bar's colour", Meter.LOOK_DEFAULTS.selfColor, true)
    UI.SetEnabled(selfc, d.useSelfColor and true or false, 'Needs "Colour my own bar" turned on.')
    local ss = Drop(L, "How my own row stands out", { { "color", "Its own bar colour (above)" },
        { "edge", "Class colour, with a light edge round it" } },
        function() return d.selfStyle or "color" end, function(v) d.selfStyle = v MeterRefresh() ns.RefreshConfig() end, 280)
    UI.SetEnabled(ss, d.useSelfColor and true or false, 'Needs "Colour my own bar" turned on.')
    UI.SetEnabled(selfc, (d.useSelfColor and d.selfStyle ~= "edge") and true or false,
        d.useSelfColor and "Not used while your row stands out by a light edge." or 'Needs "Colour my own bar" turned on.')
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
    UI.SetEnabled(bc, d.rowBorder ~= false, 'Needs "Show a border round each row" turned on.')
    UI.SetEnabled(bs, d.rowBorder ~= false, 'Needs "Show a border round each row" turned on.')
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
    UI.SetEnabled(spec, d.showIcons ~= false, 'Needs "Show an icon on each row" turned on.')
    UI.SetEnabled(size, d.showIcons ~= false, 'Needs "Show an icon on each row" turned on.')
    -- the Darkmoon Faire mark is not there where it does not load
    -- (Core_Flavor, meter_dmf), and "only with my world buffs" not where
    -- the version is not raided on Classic Era's world buffs (TBC): left
    -- out, not dimmed (General > Game versions says why)
    if Meter.DMF_ON ~= false then
        BindCheck(L, d, "dmfIcon", "Mark who has the Darkmoon Faire damage buff",
            "In a raid, a small Darkmoon Faire icon after the name of everyone with Sayge's Dark Fortune of "
            .. "Damage (+10% damage), so you can see who has it. Checked every 15 seconds.",
            function(v) if Meter.DMFScan then Meter.DMFScan() end if Meter.DirtyAll then Meter.DirtyAll() end ns.RefreshConfig() end)
        if Meter.DMF_WORLD_BUFFS ~= false then
            local ob = BindCheck(L, d, "dmfOnlyBuffed", "Only while I have my world buffs on",
                "Rallying Cry, Warchief's Blessing, Zandalar, Songflower or a Dire Maul buff.",
                function() if Meter.DMFScan then Meter.DMFScan() end if Meter.DirtyAll then Meter.DirtyAll() end MeterRefresh() end)
            UI.SetEnabled(ob, d.dmfIcon ~= false, 'Needs "Mark who has the Darkmoon Faire damage buff" turned on.')
        end
    end
    L:EndCard()

    L:Card("Window")
    BindCheck(L, d, "bgShown", "Fill the window background", "Off, the windows are bare rows on the screen.",
        function() ns.RefreshConfig() end)
    local bgc = Color(L, "Background colour", function() return Meter.WinBgColor(d) end,
        function(r, g, b, a) d.bgColor = { r = r, g = g, b = b, a = a or 1 } end, true)
    UI.SetEnabled(bgc, d.bgShown and true or false, 'Needs "Fill the window background" turned on.')
    BindCheck(L, d, "winBorder", "Border round the window", nil, function() ns.RefreshConfig() end)
    local wbc = BindColor(L, d, "winBorderColor", "Window border colour", Meter.LOOK_DEFAULTS.winBorderColor, true)
    local wbs = BindSlider(L, d, "winBorderSize", "Window border thickness", { min = 1, max = 6, format = Px })
    UI.SetEnabled(wbc, d.winBorder and true or false, 'Needs "Border round the window" turned on.')
    UI.SetEnabled(wbs, d.winBorder and true or false, 'Needs "Border round the window" turned on.')
    L:EndCard()

    -- (Meter v2) the header: the bar with the mode, the clock and the
    -- icons; the old floating toolbar; or nothing
    L:Card("Header")
    local HM = Meter.HeaderMode and Meter.HeaderMode(d) or "bar"
    Drop(L, "Header", { { "bar", "A bar: the mode, the fight clock and the icons" },
        { "hover", "No bar: the icons float above the window on hover" }, { "none", "Nothing (right-click for the menus)" } },
        function() return Meter.HeaderMode and Meter.HeaderMode(d) or d.headerMode end,
        function(v) d.headerMode = v MeterRefresh() ns.RefreshConfig() end, 300,
        "The bar sits inside the window: the + opens another window, then reset, mode, fight, report and "
        .. "this window's options. Right-click any window for its mode menu.")
    local bar = HM == "bar"
    local th = BindSlider(L, d, "titleHeight", "Header height", { min = 12, max = 30, format = Px })
    local tt = Texture(L, "Header texture", "titleTexture", ns.FLAT or "Interface\\Buttons\\WHITE8X8",
        function() return 0.3, 0.3, 0.3 end)
    local tc = BindColor(L, d, "titleColor", "Header colour", Meter.LOOK_DEFAULTS.titleColor, true)
    local ts = BindCheck(L, d, "titleSegment", "Name the fight when it is not the current one",
        "\"Damage Done  -  #3 Ragnaros\", \"Overall Damage Done\".")
    local tk = BindCheck(L, d, "headerClock", "Show the fight clock", "\"Damage Done (2:13)\": how long the fight has run, ticking in combat.")
    local ta = BindCheck(L, d, "titleAccent", "Mode name in the accent colour",
        "The mode's name in your accent colour with the clock in soft white after it. Off: the title text's own colour.")
    local hs = BindSlider(L, d, "headerIconSize", "Icon size", { min = 10, max = 24, format = Px })
    local ho = BindCheck(L, d, "headerIconsOnHover", "Icons only while the mouse is on the window",
        "Off, the mode and settings icons stay; the fight, report and window icons always come with the mouse.")
    local hl = BindCheck(L, d, "headerLine", "A line under the header", nil, function() MeterRefresh() ns.RefreshConfig() end)
    local hlc = BindColor(L, d, "headerLineColor", "Line colour", Meter.LOOK_DEFAULTS.headerLineColor, true)
    local NEEDS_BAR = 'Needs "Header" set to a bar.'
    UI.SetEnabled(hlc, bar and d.headerLine ~= false, bar and 'Needs "A line under the header" turned on.' or NEEDS_BAR)
    for _, w in ipairs({ th, tt, tc, ts, tk, ta, ho, hl }) do UI.SetEnabled(w, bar, NEEDS_BAR) end
    UI.SetEnabled(hs, HM ~= "none", "No icons while the header is set to nothing.")
    local tm = Drop(L, "Floating icons", { { "hover", "While the mouse is over the window" }, { "always", "Always" } },
        function() return d.toolbarMode end, function(v) d.toolbarMode = v MeterRefresh() end, 260)
    UI.SetEnabled(tm, HM == "hover", 'Needs "Header" set to icons floating on hover.')
    L:EndCard()

    -- (Meter v2) a row click opens its breakdown inside the window; the
    -- hover tooltip's look
    if Meter.Breakdown then
        L:Card("Breakdown")
        Drop(L, "Hovering a row shows", { { "tooltip", "What it means, in words" },
            { "bars", "Its abilities as bars" }, { "off", "Nothing" } },
            function() return BDGet("hover") end, function(v) BDSet("hover", v) MeterRefresh() end, 260,
            "Bars are for damage and healing; the other modes keep their words.")
        local ms = UI.Slider(L.current, { width = 200, min = 0, max = 20, step = 1, label = "Abilities listed",
            value = tonumber(BDGet("maxSpells")) or 0,
            format = function(v) return v < 1 and "All of them" or tostring(v) end,
            onChange = function(v) BDSet("maxSpells", v >= 1 and v or nil) MeterRefresh() end })
        L:Row(ms, 40)
        local function BDCheck(key, label, desc)
            local w = UI.Checkbox(L.current, label, BDGet(key) and true or false, function(v)
                BDSet(key, v and true or false)
                MeterRefresh()
            end)
            L:Row(w, 17)
            if desc then L:Desc(desc) end
        end
        BDCheck("showTargets", "Show the targets under the abilities", nil)
        BDCheck("spellTooltip", "The game's spell tooltip on an ability", nil)
        BDCheck("deathsInWindow", "A death opens a short recap in the window",
            "Off, a death opens the death recap window with its health line.")
        L:Desc("Click a row for its breakdown; the head, a right-click or Escape goes back.")
        L:EndCard()
    end

    L:Card("Threat rows")
    BindCheck(L, d, "threatIcons", "Show role icons", nil, function() ns.RefreshConfig() end)
    local ti = BindSlider(L, d, "threatIconSize", "Role icon size", { min = 8, max = 30, format = Px })
    UI.SetEnabled(ti, d.threatIcons ~= false, 'Needs "Show role icons" turned on.')
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
    UI.SetEnabled(nc, d.nameColorMode == "custom", 'Needs "Name colour" set to one colour.')
    BindCheck(L, d, "showRank", "Number the rows", "\"3. " .. me .. "\": each name with its place in the list.",
        function() MeterRefresh() ns.RefreshConfig() end)
    local dr = BindCheck(L, d, "dimRank", "The numbers dimmer than the names", nil)
    UI.SetEnabled(dr, d.showRank and true or false, 'Needs "Number the rows" turned on.')
    BindCheck(L, d, "textOutline", "A thin outline on the row texts",
        "Crisp on any background. Off: the soft drop shadow (a font picked above keeps its own).",
        function() MeterRefresh() ns.RefreshConfig() end)
    BindCheck(L, d, "removeRealm", "Hide realm names", nil)
    Spot(L, "name", Meter.ROW_TARGETS)
    L:EndCard()

    L:Card("Numbers")
    Font(L, "Number text", "numberFont", Meter.NumberFontDefaults(d), "371.4K I 2.0K  (18.6%)")
    BindCheck(L, d, "dimSecond", "The per-second figure dimmer than the total", "\"371.4K\" bright, \"I 2.0K\" softer.")
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
    UI.SetEnabled(sep, sepOn, 'Needs "What the number shows" to show both the total and per second.')
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
        -- (Meter v2) the window's own options, as its header's gear menu
        -- has them (nothing written until changed)
        local sc = UI.Slider(L.current, { width = 240, min = 50, max = 150, step = 5, label = "Scale",
            value = math.floor((tonumber(w.scale) or 1) * 100 + 0.5),
            format = function(v) return format("%d%%", v) end,
            onChange = function(v) w.scale = (v == 100) and nil or v / 100 MeterRefresh() end })
        L:Row(sc, 40)
        BindCheckD(L, w, "snap", "Snap to other meter windows", nil, true)
        if w.display ~= "threat" then
            BindCheckD(L, w, "syncSegments", "Sync its fight with other windows",
                "Picking a fight here switches every window that has this on.", false)
            BindCheckD(L, w, "autoCurrent", "Back to the current fight on a new pull", nil, true)
            BindCheckD(L, w, "hideClock", "Hide the fight clock", nil, false)
        end
        L:EndCard()
    end
    L:Card("Windows together")
    BindCheck(L, d, "snapWindows", "Dragging and resizing snap to other meter windows",
        "Edges and sizes line up with the nearest window within 6 px. Each window can opt out above.")
    L:EndCard()
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

    -- (Meter v2) every window parked and built again from the saved list
    local Win = Meter.Win
    if Win and Win.Rebuild then
        L:Card("Windows")
        local rb = UI.Button(L.current, "Rebuild the windows", { width = 160,
            onClick = function() Win.Rebuild() end })
        L:Row(rb, 26)
        L:Desc("Builds every meter window again from its settings - after a profile change, or if one went "
            .. "missing - without a reload. Key Bindings > ZacUI damage meter has a key to show and hide "
            .. "them all, and one to reset the data.")
        L:EndCard()
    end
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
    -- (Meter v2) a row's breakdown, and the header at a wide window's width
    if ns.Meter and ns.Meter.Breakdown then m[#m + 1] = { id = "breakdown", label = "Breakdown" } end
    m[#m + 1] = { id = "header", label = "Header" }
    -- (Forever / Retail) the window in a fight, from the game's own meter
    if ns.Meter and ns.Meter.Live then m[#m + 1] = { id = "live", label = "Live" } end
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
        -- (Forever keeps no hits before a death: no tooltip of them; the
        -- recap shows what it says there)
        if not NoLog() then m[#m + 1] = { id = "deathTip", label = "Death tooltip" } end
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
            ZacUIDB.config.tabs.meter = (k == "bar" or k == "headerIcons") and "look" or (k == "icon" or k == "threatIcon") and "pos" or "text"
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
