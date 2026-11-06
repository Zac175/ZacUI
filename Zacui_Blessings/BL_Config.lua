-- BL_Config - the Blessings page (Combat > Blessings): on/off, the
-- casting bar's options and its look, the assignment window, the
-- PallyPower hand-over.
-- Part of ZacUI; load order is set by the TOC.
--
-- Tabs in the house order: General (blessings, what the bar shows) -
-- Look (sizes, colours, status colours, fill texture) - Text (title,
-- button and count fonts) - Animation (the bar appearing, a blessing
-- running out) - Position (scale, its spot).
--
-- THE PREVIEW is the casting bar itself: Bar.NewView / Arrange / Paint*
-- (BL_Bar), the live bar's own drawing, on plain buttons with a made-up
-- raid or party - some missing a blessing, one running low, one dead.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local D = ns.BlessingsData
local BL = ns.Blessings
if not (D and BL) then return end

local UI = ns.UI
local M, F = UI.M, UI.F
local format = string.format

-- the words people type that are not on the page
if ns.AddMenuKeywords then
    ns.AddMenuKeywords("blessings", "casting bar button buttons size width height spacing font fonts "
        .. "colour color colours colors texture fill missing running low animation alert preview scale "
        .. "position anchor corner offset format shadow glow sound fade opacity mouseover "
        .. "assignment window grid paladin names cells single players")
end

local function Check(L, label, value, fn, desc)
    local w = UI.Checkbox(L.current, label, value and true or false, fn)
    L:Row(w, 17)
    if desc then L:Desc(desc) end
    return w
end

local function Bar() if BL.Bar then BL.Bar.Refresh() end end

local function BC()
    local c = BL.Cfg()
    return c and c.bar or {}
end

local function Px(v) return format("%d px", v) end

local function Slider(L, key, label, min, max, opts)
    opts = opts or {}
    local bc = BC()
    local w = UI.Slider(L.current, { width = opts.width or 220, min = min, max = max, step = opts.step or 1,
        value = tonumber(bc[key]) or opts.default or min, label = label, format = opts.format or Px,
        onChange = function(v) bc[key] = v end })
    L:Row(w, 40)
    if opts.desc then L:Desc(opts.desc) end
    return w
end

-- a colour: `fallback` is a function giving today's colour (the theme's,
-- for the ones that follow it)
local function Colour(L, key, label, fallback, desc)
    local bc = BC()
    local w = UI.ColorPicker(L.current, { label = label, alpha = true,
        get = function()
            local c = bc[key]
            if type(c) == "table" then return c end
            return fallback(bc)
        end,
        set = function(r, g, b, a) bc[key] = { r = r, g = g, b = b, a = a or 1 } end })
    L:Row(w, 22)
    if desc then L:Desc(desc) end
    return w
end

local function Font(L, label, key, sample)
    local bc = BC()
    local w = UI.FontPicker(L.current, { label = label, defaultLabel = "Game font",
        get = function() return bc[key] end,
        set = function(spec) bc[key] = spec end,
        defaults = BL.Bar.FONT_DEFAULTS[key], minSize = 6, maxSize = 24, sample = sample })
    L:Add(w, 6)
    return w
end

local function Anim(L, label, key, styles, desc)
    local bc = BC()
    local w = UI.AnimationPicker(L.current, { label = label, styles = styles,
        get = function() return bc[key] end,
        set = function(spec) bc[key] = spec end })
    L:Add(w, 6)
    if desc then L:Desc(desc) end
    return w
end

-- Where one text or part sits: ZacUI's anchor picker over the bar's
-- anchors.<key> (nil = its built-in spot, Bar.AnchorDefaults), with the
-- text's format when it has one.
local FORMAT_KINDS = { name = { name = true }, count = { time = true } }
local function Spot(L, key, o)
    local Bar = BL.Bar
    o = o or {}
    local list = {}
    for _, k in ipairs(o.targets or Bar.BUTTON_TARGETS) do
        if k ~= key then list[#list + 1] = { value = k, text = Bar.ANCHOR_LABELS[k] or k } end
    end
    local get, set = ns.CustomAccess(BC, "anchors", key)
    local spec = { key = "blessings." .. key, label = o.label, anchorGet = get, anchorSet = set,
        anchorDefaults = function() return Bar.AnchorDefaults(key, BC()) end, targets = list,
        defaultTargetLabel = "Where it sits now", anchorMin = -60, anchorMax = 60 }
    local fk = o.format
    if fk then
        local fg, fs = ns.CustomAccess(BC, "formats", fk)
        spec.formatGet, spec.formatSet, spec.formatKinds = fg, fs, FORMAT_KINDS[key] or { name = true }
        if fk == "time" then
            spec.formatDefaults = Bar.TIME_FORMAT_DEFAULTS
            spec.formatSample = function(f) return ns.FormatTime(13 * 60, f, Bar.TIME_FORMAT_DEFAULTS) .. "  "
                .. ns.FormatTime(45, f, Bar.TIME_FORMAT_DEFAULTS) end
        else
            spec.formatSample = function(f) return ns.FormatName("Lightbringer", f) end
        end
    end
    if o.part then return UI.FrameElement(L, spec) end
    return UI.TextElement(L, spec)
end

-- ============================================================
-- PREVIEW - a made-up group
-- ============================================================
local GREATER_ICON = {
    [1] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofWisdom",
    [2] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofKings",
    [3] = "Interface\\Icons\\Spell_Magic_GreaterBlessingofKings",
    [4] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofSalvation",
    [5] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofLight",
    [6] = "Interface\\Icons\\Spell_Holy_GreaterBlessingofSanctuary",
}
local function BlessIcon(b)
    local e = D.BLESSINGS[b]
    return (e and BL.Bar.SpellIcon(e.greater or e.normal)) or GREATER_ICON[b]
end
local function AuraPlan()
    local name = GetSpellInfo and GetSpellInfo(D.AURAS[1].id) or "Devotion Aura"
    return { name = name, icon = BL.Bar.SpellIcon(D.AURAS[1].id) or "Interface\\Icons\\Spell_Holy_DevotionAura" }
end

local MIN = 60
-- { name, seconds left (nil = missing), dead, out of range }
-- The bar as a paladin sees it: in a raid, a row for every class he
-- blesses (Kings for everyone, the usual job of one paladin); in a party,
-- the two classes there. Between them one of each state (someone
-- missing, one out of range, a row running low, one dead - not counted
-- missing).
local GROUPS = {
    raid = {
        { slot = 1, b = 3, members = { { "Brakka", 13 * MIN }, { "Tovren", 12 * MIN }, { "Holgrim" },
            { "Sefa", 13 * MIN }, { "Garrok", nil, false, true }, { "Ulfar", 11 * MIN } } },
        { slot = 2, b = 3, members = { { "Quillan", 12 * MIN }, { "Sneakz", 12 * MIN }, { "Vex", 12 * MIN } } },
        { slot = 3, b = 3, members = { { "Ghaldor", 2 * MIN }, { "Thessa", 2 * MIN }, { "Kesh", nil, true } } },
        { slot = 4, b = 3, members = { { "Treehug", 14 * MIN }, { "Barkskin", 14 * MIN } } },
        { slot = 5, b = 3, members = { { "Lightbulb", 10 * MIN }, { "Judge", 10 * MIN } } },
        { slot = 6, b = 3, members = { { "Bowman", 13 * MIN }, { "Trapz", 13 * MIN }, { "Volley", 13 * MIN } } },
        { slot = 7, b = 3, members = { { "Orrin", 11 * MIN }, { "Frostie", 11 * MIN }, { "Pyro", 11 * MIN }, { "Blinky", 11 * MIN } } },
        { slot = 8, b = 3, members = { { "Velka", 9 * MIN }, { "Dotsy", 9 * MIN }, { "Felbro", 9 * MIN } } },
    },
    party = {
        { slot = 1, b = 3, members = { { "Brakka", 13 * MIN }, { "Tovren" } } },
        { slot = 3, b = 1, members = { { "Ghaldor", 2 * MIN }, { "Maren", nil, true } } },
    },
}

local function Plan(mode)
    local src = GROUPS[mode] or GROUPS.raid
    local plan = { aura = AuraPlan(), rows = {} }
    for i, g in ipairs(src) do
        local members = {}
        for j, m in ipairs(g.members) do
            members[j] = { name = m[1], left = m[2], dead = m[3] or false, far = m[4] or false }
        end
        plan.rows[i] = { slot = g.slot, b = g.b, members = members,
            label = BL.Bar.ClassLabel(g.slot), color = BL.Bar.ClassColor(g.slot), icon = BlessIcon(g.b) }
    end
    return plan
end

local CANVAS_W, CANVAS_H = 300, 120   -- update sizes the canvas to the bar

local function BuildPreview(canvas, P)
    local view = BL.Bar.NewView(canvas, true)
    view.root:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    P.store.view = view
    P.store.serial = 0
end

local function UpdatePreview(canvas, P)
    local Bar, view = BL.Bar, P.store.view
    local bc = BC()
    local root = view.root
    if ns.Motion then ns.Motion.StopTree(root) end
    root:Show()
    local plan = Plan(P.mode)
    Bar.Arrange(view, bc, plan)
    -- the canvas is the bar at its own scale (the strip shows it at the
    -- real size, or scaled down to fit)
    local s = bc.scale or 1
    if s <= 0 then s = 1 end
    local w, h = root:GetWidth() or 1, root:GetHeight() or 1
    if P.Resize then P.Resize(w * s + 8, h * s + 8) end
    root:SetScale(s)
    Bar.PaintSymbols(view, 37)
    if view.aura and view.aura:IsShown() then Bar.PaintAura(view.aura, bc, true) end
    for r, row in ipairs(plan.rows) do
        local missing, total, least = 0, 0, nil
        for j, m in ipairs(row.members) do
            total = total + 1
            if not m.left and not m.dead then missing = missing + 1 end
            if m.left and (not least or m.left < least) then least = m.left end
            local pb = view.playerBtns[(r - 1) * 15 + j]
            if pb and pb:IsShown() and pb.member == m then Bar.PaintPlayer(pb, bc, m.dead, m.left, not m.far) end
        end
        local cb = view.classBtns[r]
        cb.lastMissing = nil      -- a settings change is not a blessing running out
        Bar.PaintClass(cb, bc, missing, total, least)
    end
end

local function ReplayPreview(canvas, P)
    local Bar, view = BL.Bar, P.store.view
    local bc = BC()
    local st = P.store
    st.serial = st.serial + 1
    local mine = st.serial
    local root = view.root
    if ns.Motion then ns.Motion.StopTree(root) end
    root:Hide()
    Bar.ShowAnimated(view, bc)
    -- then the warriors' row: a blessing just ran out
    local wait = 0.1
    local Motion = ns.Motion
    if Motion and type(bc.showAnim) == "table" and bc.showAnim.style ~= "none" then
        local s = Motion.Normalize(bc.showAnim)
        wait = (s.duration + s.delay) / Motion.Speed() + 0.1
    end
    C_Timer.After(wait, function()
        if mine ~= st.serial or not root:IsVisible() then return end
        local cb = view.classBtns[1]
        if cb and cb:IsShown() then Bar.Alert(cb, bc) end
    end)
end

-- ============================================================
-- TABS
-- ============================================================
local function Tab_general(L)
    local c = BL.Cfg()
    L:Card("Blessings")
    Check(L, "Blessings on", c.enabled, function(v)
        c.enabled = v and true or false
        if v then BL.Start() else BL.Stop() end
        Bar()
    end, "Who gives which class which blessing, and each paladin's aura - shared with every paladin in the "
        .. "group, whether they run ZacUI or PallyPower. The leader and raid assistants can set anyone's.")
    local open = UI.Button(L.current, "Open the assignments", { width = 200, onClick = function()
        if BL.Grid then BL.Grid.Open() end
    end })
    L:Row(open, M.BUTTON_H + 8)
    if BL.isPaladin then
        Check(L, "Anyone may set my blessings", c.freeassign, function(v)
            c.freeassign = v and true or false
            local p = BL.pallys[BL.me]
            if p then p.freeassign = c.freeassign end
            if BL.Running() then BL.Comm.Fresh() BL.Comm.SendSelf() end
        end, "Lets a raider who is not leader or assistant set your blessings (PallyPower calls this free assignment).")
    end
    L:EndCard()

    L:Card("Casting bar")
    if not BL.isPaladin then
        L:Desc("The casting bar is a paladin's. These settings are shared by every character on the account, "
            .. "so you can set it up for your paladins from here.")
    end
    Check(L, "Show the casting bar", c.bar.enabled, function(v) c.bar.enabled = v and true or false Bar() end,
        "A row per class you bless: left click casts the Greater Blessing, right click the normal one on "
        .. "whoever needs it. Red counts are players missing it; the bar fills with the time left. Click the "
        .. "title for the assignments, drag the title to move it (out of combat).")
    Check(L, "A button per player", c.bar.players, function(v) c.bar.players = v and true or false Bar() end,
        "Beside each class: left click gives that player the Greater Blessing (or their own blessing), right "
        .. "click the normal one. Grey: dead, offline or out of range.")
    Check(L, "Aura button", c.bar.aura, function(v) c.bar.aura = v and true or false Bar() end)
    Check(L, "Show it outside a group", c.bar.solo, function(v) c.bar.solo = v and true or false Bar() end)
    local p = UI.Slider(L.current, { width = 220, min = 1, max = 15, step = 1, value = c.bar.maxPlayers or 8,
        label = "Player buttons per class", onChange = function(v) c.bar.maxPlayers = v Bar() end })
    L:Row(p, 40)
    L:Desc("The bar changes out of combat only (the game allows nothing else); a change in a fight shows when it ends.")
    L:EndCard()

    -- when the casting bar shows (bar.visibility; nothing saved = always)
    L:Card("When the bar shows")
    local vg, vs = ns.CustomAccess(BC, "visibility", nil)
    L:Add(UI.VisibilityPicker(L.current, { width = UI.CardInnerWidth(L), get = vg, set = vs,
        shows = { "always", "combat", "nocombat", "group", "raid", "instance", "mouseover" } }), 6)
    L:Desc("A hidden bar only fades out: its buttons still take clicks.")
    L:EndCard()

    L:Card("Sound")
    local sg, ss = ns.CustomAccess(BC, "sounds", "expire")
    local sp = UI.SoundSpecPicker(L.current, { width = UI.CardInnerWidth(L), label = "When a blessing runs out",
        get = sg, set = ss, defaults = { sound = "none" } })
    L:Add(sp, 6)
    L:EndCard()
end

local function Tab_look(L)
    local Bar = BL.Bar
    local bc = BC()
    L:Card("Sizes")
    Slider(L, "rowHeight", "Button height", 14, 40)
    Slider(L, "classWidth", "Class column width", 80, 260)
    Slider(L, "playerWidth", "Player button width", 40, 160)
    Slider(L, "gap", "Space between buttons", 0, 10)
    Slider(L, "titleHeight", "Title strip height", 12, 32)
    local icons = UI.Checkbox(L.current, "Blessing and aura icons", bc.icons ~= false,
        function(v) bc.icons = v and true or false end)
    L:Row(icons, 17)
    L:EndCard()

    L:Card("Colours")
    Colour(L, "bgColor", "Background", Bar.BackgroundColor)
    Colour(L, "stripColor", "Title strip", Bar.StripColor)
    Colour(L, "borderColor", "Border", Bar.BorderColor)
    Colour(L, "buttonColor", "Button background", Bar.ButtonColor)
    Colour(L, "buttonBorderColor", "Button border", function() return Bar.BorderColor({}) end)
    local back = UI.Button(L.current, "Back to the theme colours", { width = 200,
        onClick = function()
            for _, k in ipairs({ "bgColor", "stripColor", "borderColor", "buttonColor", "buttonBorderColor", "titleColor" }) do
                bc[k] = nil
            end
            ns.SettingsChanged("reset")
            ns.RefreshConfig()
        end })
    L:Row(back, M.BUTTON_H + 6)
    L:Desc("Until you pick one, these follow the UI theme (Appearance > Colours).")
    L:EndCard()

    L:Card("Shadow and glow")
    local cg, cs = ns.CustomAccess(BC, "chrome", nil)
    L:Add(UI.ChromePicker(L.current, { width = UI.CardInnerWidth(L), get = cg, set = cs,
        fields = { shadowSize = true, shadowColor = true, glowSize = true, glowColor = true } }), 6)
    L:EndCard()

    L:Card("Status")
    local D0 = BL.BAR_DEFAULTS
    local function Fixed(key) return function() return D0[key] end end
    Colour(L, "colorHave", "Has it", Fixed("colorHave"), "The fill: how much of the 15 minutes is left.")
    Colour(L, "colorLow", "Running low", Fixed("colorLow"))
    Slider(L, "lowAt", "Running low below", 5, 60, { format = function(v) return format("%d%% of 15 min", v) end,
        desc = "Player buttons only." })
    Colour(L, "colorMissing", "Missing", Fixed("colorMissing"), "Also the tint of the alert when a blessing runs out.")
    Colour(L, "colorDead", "Dead, offline or away", Fixed("colorDead"))
    Colour(L, "colorAura", "Aura up", Fixed("colorAura"))
    local tex = UI.TexturePicker(L.current, { label = "Fill texture", width = 240, defaultLabel = "ZacUI Flat",
        get = function() return bc.fillTexture end,
        set = function(name) bc.fillTexture = name end,
        defaultPath = function() return Bar.DefaultFillTexture() end,
        color = function() return 0.3, 0.8, 0.3 end })
    L:Add(tex, 6)
    L:EndCard()
end

local function Tab_text(L)
    local bc = BC()
    L:Card("Title")
    Font(L, "Title text", "titleFont", "Blessings")
    local w = UI.ColorPicker(L.current, { label = "Title colour", alpha = true,
        get = function()
            if type(bc.titleColor) == "table" then return bc.titleColor end
            return BL.Bar.TitleColor(bc)
        end,
        set = function(r, g, b, a) bc.titleColor = { r = r, g = g, b = b, a = a or 1 } end })
    L:Row(w, 22)
    Spot(L, "title", { targets = BL.Bar.ROOT_TARGETS })
    L:EndCard()
    L:Card("Symbols count")
    Spot(L, "symbols", { targets = BL.Bar.ROOT_TARGETS })
    L:Desc("Uses the count font below.")
    L:EndCard()
    L:Card("Buttons")
    Font(L, "Class, aura and player names", "textFont", "Warrior  Brakka  Devotion Aura")
    Spot(L, "name", { format = "name", label = "Names" })
    Font(L, "Counts and time left", "countFont", "2/6  13m  37 symbols")
    Spot(L, "count", { format = "time", label = "Counts and time left" })
    L:EndCard()
end

local function Tab_anim(L)
    L:Card("Animations")
    Anim(L, "When the bar appears", "showAnim", { "none", "fade", "slide", "pop", "bounce" },
        "Joining a group, or the bar coming back. Out of combat only: it holds the casting buttons.")
    Anim(L, "When a blessing runs out", "alertAnim", { "none", "flash", "pulse", "fade", "pop" },
        "A tint over the class row the moment one more player is missing its blessing - in combat too.")
    L:Desc("Replay in the preview plays both. Appearance > Motion turns every animation off or speeds them up.")
    L:EndCard()
end

local function Tab_pos(L)
    local c = BL.Cfg()
    L:Card("Size and place")
    local s = UI.Slider(L.current, { width = 220, min = 0.6, max = 1.6, step = 0.05, value = c.bar.scale or 1,
        label = "Scale", format = function(v) return format("%d%%", v * 100 + 0.5) end,
        onChange = function(v) c.bar.scale = v Bar() end })
    L:Row(s, 40)
    local back = UI.Button(L.current, "Put it back where it started", { width = 220,
        onClick = function()
            c.barPos = nil
            if BL.Bar and BL.Bar.Place then BL.Bar.Place() end
        end })
    L:Row(back, M.BUTTON_H + 6)
    L:Desc("Drag the bar by its title to move it (out of combat).")
    L:EndCard()

    L:Card("Blessing icon on the buttons")
    Spot(L, "icon", { part = true })
    L:Desc("Every class and aura button. The names follow the icon unless placed themselves (Text tab).")
    L:EndCard()
end

-- ============================================================
-- THE ASSIGNMENT WINDOW (its own tab and preview)
-- ============================================================
-- The sample is the window's own header and rows (Grid.NewHeader /
-- NewRow, the cells' own constructor), two made-up paladins, its texts
-- placed by Grid.PlaceHeader / PlaceRow like the real window's.
local GRID_PALS = {
    { name = "Lightbringer", sub = "37 sym  lead", assign = { 3, 3, 1, 1, 1, 2, 1, 1 }, marks = { [1] = 2 }, aura = 1 },
    { name = "Ashwarden", sub = "12 sym  free", assign = { 2, 2, 5, 4, 4, 4, 4, 4 }, marks = {}, aura = 2 },
}
local GRID_COUNTS = { 6, 3, 3, 2, 2, 3, 4, 3 }

local function GridWidth()
    local G = BL.Grid
    return G.NAME_W + (D.NUM_CLASSES + 1) * (G.CELL + G.GAP)
end

local function BuildGridPreview(canvas, P)
    local G, st = BL.Grid, P.store
    local w = GridWidth()
    st.header = G.NewHeader(canvas, w, true)
    st.header:SetPoint("TOPLEFT", canvas, "TOPLEFT", 6, -6)
    st.rows = {}
    for i = 1, #GRID_PALS do
        local r = G.NewRow(canvas, w, true)
        r:SetPoint("TOPLEFT", st.header, "BOTTOMLEFT", 0, -6 - (i - 1) * (G.CELL + G.GAP))
        st.rows[i] = r
    end
end

local function UpdateGridPreview(canvas, P)
    local G, st = BL.Grid, P.store
    for slot = 1, D.NUM_CLASSES do
        local n = GRID_COUNTS[slot] or 0
        st.header.cells[slot].count:SetText(n > 0 and tostring(n) or "")
    end
    G.PlaceHeader(st.header)
    local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS.PALADIN or { r = 0.96, g = 0.55, b = 0.73 }
    for i, pal in ipairs(GRID_PALS) do
        local r = st.rows[i]
        r.name:SetText(pal.name)
        r.name:SetTextColor(col.r, col.g, col.b)
        r.sub:SetText(pal.sub)
        for slot = 1, D.NUM_CLASSES do
            local c = r.cells[slot]
            c:SetBlessingIcon(BlessIcon(pal.assign[slot]))
            local m = pal.marks[slot]
            c.mark:SetText(m and ("+" .. m) or "")
        end
        local ac = r.cells[D.NUM_CLASSES + 1]
        local aura = D.AURAS[pal.aura]
        ac:SetBlessingIcon(aura and BL.Bar.SpellIcon(aura.id) or "Interface\\Icons\\Spell_Holy_DevotionAura")
        ac.mark:SetText("")
        G.PlaceRow(r)
    end
    if P.Resize then P.Resize(GridWidth() + 12, 12 + G.CELL + 6 + #GRID_PALS * (G.CELL + G.GAP)) end
end

local function Tab_grid(L)
    local G = BL.Grid
    if not (G and G.NewRow) then return end
    L:Preview({ key = "blessings.grid", title = "Assignment window", width = GridWidth() + 12, height = 120,
        build = BuildGridPreview, update = UpdateGridPreview })
    L:Card("The assignment window")
    local b = UI.Button(L.current, "Open the window", { width = 160, onClick = function() G.Toggle() end })
    L:Row(b, M.BUTTON_H + 6)
    L:Desc("One row per paladin, one column per class, the aura at the end. The casting bar's title opens it too.")
    L:EndCard()
    -- every text, freely (ZacUIDB.blessings.gridAnchors.<key>)
    L:Card("Texts in the window")
    ZacUIDB.config = ZacUIDB.config or {}
    local function Which()
        local v = ZacUIDB.config.blGridText
        for _, k in ipairs(G.ANCHOR_KEYS) do if k == v then return v end end
        return "name"
    end
    local which = Which()
    L:Add(UI.Field(L.current, "Text", function(h)
        return UI.Dropdown(h, { width = 240,
            items = function()
                local out = {}
                for _, k in ipairs(G.ANCHOR_KEYS) do out[#out + 1] = { text = G.ANCHOR_LABELS[k], value = k } end
                return out
            end,
            selected = function() return G.ANCHOR_LABELS[Which()] end, selectedValue = Which,
            onSelect = function(v) ZacUIDB.config.blGridText = v ns.RefreshConfig() end })
    end, { width = 240 }), 8)
    local targets, defLabel = {}, G.ANCHOR_LABELS.row
    if which == "name" then targets = { { value = "sub", text = G.ANCHOR_LABELS.sub } }
    elseif which == "sub" then targets = { { value = "row", text = G.ANCHOR_LABELS.row } } defLabel = G.ANCHOR_LABELS.name
    elseif which == "mark" then targets = { { value = "row", text = G.ANCHOR_LABELS.row } } defLabel = G.ANCHOR_LABELS.cell
    else defLabel = G.ANCHOR_LABELS.header end
    local get, set = ns.CustomAccess(BL.Cfg, "gridAnchors", which, function() if G.Refresh then G.Refresh() end end)
    UI.TextElement(L, { key = "blgrid." .. which, anchorGet = get, anchorSet = set, targets = targets,
        anchorDefaults = function() return G.AnchorDefaults(which) end, defaultTargetLabel = defLabel,
        anchorMin = -60, anchorMax = 60 })
    L:EndCard()
end

ns.RegisterPage("Blessings", function(L)
    L:Header("Blessings", "Paladin blessings and auras for the group")
    if BL.standDown then
        L:Notice("warn", "PallyPower is turned on, so ZacUI's blessings are standing down (both would speak for you). "
            .. "Your PallyPower assignments have been brought over.")
        L:Card("PallyPower")
        local b = UI.Button(L.current, "Turn PallyPower off + reload", { width = 220, onClick = BL.DisablePallyPower })
        L:Row(b, M.BUTTON_H + 8)
        L:EndCard()
        return
    end

    -- a sample's text or icon picked in the preview: its spot
    if ns.CustomPick then
        ns.CustomPick.SetHandler("blessings.grid", function(el)
            local k = type(el) == "string" and el:match("^blgrid%.(.+)$")
            if not k then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            ZacUIDB.config.blGridText = k
            ZacUIDB.config.tabs.blessings = "grid"
            ns.RefreshConfig()
        end)
        ns.CustomPick.SetHandler("blessings.bar", function(el)
            local k = type(el) == "string" and el:match("^blessings%.(.+)$")
            if not k then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            ZacUIDB.config.tabs.blessings = (k == "icon") and "pos" or "text"
            ns.RefreshConfig()
        end)
    end

    L:Preview({
        key = "blessings.bar",
        title = "Casting bar",
        width = CANVAS_W, height = CANVAS_H,
        modes = { { id = "raid", label = "Raid" }, { id = "party", label = "Party" } },
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
        { id = "grid",    label = "Window",    build = Tab_grid },
    })
end)
