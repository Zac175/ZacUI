-- Config_PagesBars - the Action bars page and the Loadouts page.
-- Part of ZacUI; load order is set by the TOC.
--
-- EVERY CONTROL IS LIVE: a change re-applies the bars on the next frame
-- (or, in combat, the moment it ends), and the dock preview follows on
-- its own. The page edits the profile this character wears; other
-- characters wearing the same profile pick the change up on their next
-- login.
--
-- ONE BAR AT A TIME. A chooser at the top of every tab (and in the
-- preview dock) picks the bar the tabs edit - bars 1-10, pet, stance,
-- bags, micro menu, XP strip - and the tabs are the house order:
-- General · Look · Text · Animation · Position · Advanced, then
-- Loadouts. Cards marked "every bar" set the profile's shared options.
-- Tabs a bar has nothing on (Text, for the bag strip) are left out.

local ADDON_NAME = ...
-- Zacui_Bars is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local UI = ns.UI

local M, F = UI.M, UI.F

local function AB() return ns.Bars end
local function LO() return ns.Loadouts end

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Re-apply the bars once on the next frame, however many changes land in
-- this one (a colour drag or a slider sweep is many).
local function ApplyNow()
    local A = AB()
    if A and A.active then A.ApplyAll() end
end
local Apply = ns.Coalesce and ns.Coalesce(ApplyNow) or ApplyNow

-- Search: the words people type that are not on the page. The sidebar
-- row lives in the shared menu; this part adds to its keywords.
if ns.AddMenuKeywords then
    ns.AddMenuKeywords("bars", "skin border backdrop background zoom icon size shadow edge layer strata "
        .. "level state states per row wrap spacing gap "
        .. "cooldown cooldowns numbers countdown timer sweep swipe range out of range usable "
        .. "unusable mana rage colour color tint glow proc spell alert overlay highlight hover "
        .. "pressed checked animation fade in fade out delay speed transition preview font")
end

-- A row of buttons, laid left to right, wrapping onto a new line rather
-- than running past the card's edge. Returns the buttons.
local function ButtonRow(L, defs, height)
    local list = {}
    for _, d in ipairs(defs) do
        local b = UI.Button(L.current, d[1], { width = d.width or 100, onClick = d[2], tooltip = d.tooltip })
        if d.active then b:SetActive(true) end
        list[#list + 1] = b
    end
    L:Flow(list, 6, (height or (M.BUTTON_H + 6)) - M.BUTTON_H)
    return list
end

-- rebuild = the page's layout depends on it (other controls dim)
local function Check(L, label, get, set, desc, rebuild)
    local w = UI.Checkbox(L.current, label, get() and true or false, function(v)
        set(v and true or false)
        Apply()
        if rebuild then RefreshConfig() end
    end)
    L:Row(w, 17)
    if desc then L:Desc(desc) end
    return w
end

local function Slider(L, label, get, set, min, max, step, fmt, desc)
    local w = UI.Slider(L.current, {
        width = 200, min = min, max = max, step = step, value = get(), label = label,
        format = fmt, onChange = function(v) set(v) Apply() end,
    })
    L:Row(w, 40)
    if desc then L:Desc(desc) end
    return w
end

local function Dropdown(L, label, items, get, set, width)
    local lbl = UI.Font(L.current, F.LABEL, { text = label })
    lbl:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.CONTROL_X, L.current._y)
    L.current._y = L.current._y - 16
    local function Label(v)
        for _, it in ipairs(items) do if it.value == v then return it.text end end
        return tostring(v)
    end
    local dd = UI.Dropdown(L.current, { width = width or 220,
        items = function() return items end,
        selected = function() return Label(get()) end,
        selectedValue = function() return get() end,
        onSelect = function(v) set(v) Apply() RefreshConfig() end })
    L:Row(dd, M.DROPDOWN_H + 6)
    return dd
end

-- A colour setting. legacy = the key has always been saved as a plain
-- { r, g, b } list (Bartender imports write it that way): keep it so.
local function Color(L, label, tbl, key, fallback, opts)
    opts = opts or {}
    local w = UI.ColorPicker(L.current, { label = label, alpha = opts.alpha ~= false,
        tooltip = opts.tooltip,
        get = function() return tbl[key] or fallback end,
        set = function(r, g, b, a)
            if opts.legacy then tbl[key] = { r, g, b, a }
            else tbl[key] = { r = r, g = g, b = b, a = a } end
            Apply()
        end })
    L:Add(w, 6)
    if opts.desc then L:Desc(opts.desc) end
    return w
end

local function Pct(v) return v .. "%" end
local function Px(v) return v .. " px" end
-- the state the Look tab's state editor was on, across rebuilds
local STATE_PICK = {}

-- which kinds of bar carry which settings
local BUTTONS = { action = true, pet = true, stance = true }
local MAX_ROWS = { action = 12, pet = 10, stance = 10, bagbar = 6 }

-- ============================================================
-- THE BAR CHOOSER (top of every bar tab)
-- ============================================================
local function BarChooser(L, A, p, id)
    L:Card("Bar")
    local items = {}
    for _, c in ipairs(A.BAR_CHOICES) do
        local cfg = A.CfgFor(c.id, p)
        local off = cfg and cfg.enabled == false
        items[#items + 1] = { text = c.label .. (off and "  (off)" or ""), value = c.id }
    end
    local lbl = UI.Font(L.current, F.LABEL, { text = "Settings for" })
    lbl:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.CONTROL_X, L.current._y)
    L.current._y = L.current._y - 16
    local dd = UI.Dropdown(L.current, { width = 220,
        items = function() return items end,
        selected = function()
            for _, it in ipairs(items) do if it.value == id then return it.text end end
            return A.BarLabel(id)
        end,
        selectedValue = function() return id end,
        onSelect = function(v) A.SetEditing(v) RefreshConfig() end })
    L:Row(dd, M.DROPDOWN_H + 6)
    L:Desc("Every tab below edits this bar. Cards marked \"every bar\" are shared by all of them. "
        .. "The preview's own chooser switches it too.")
    L:EndCard()
end

-- ============================================================
-- GENERAL
-- ============================================================
local function VisibilityCard(L, cfg)
    L:Card("Hide when")
    local vis = cfg.visibility
    Check(L, "Always hidden", function() return vis.always end, function(v) vis.always = v end)
    Check(L, "In combat", function() return vis.combat end, function(v) vis.combat = v end)
    Check(L, "Out of combat", function() return vis.nocombat end, function(v) vis.nocombat = v end)
    Check(L, "A pet is out", function() return vis.pet end, function(v) vis.pet = v end)
    Check(L, "No pet is out", function() return vis.nopet end, function(v) vis.nopet = v end)
    Check(L, "Mounted", function() return vis.mounted end, function(v) vis.mounted = v end)
    Check(L, "Use a custom condition instead", function() return vis.custom end, function(v) vis.custom = v end)
    local custom = UI.EditBox(L.current, { width = 300, height = 20, text = vis.customdata or "",
        hint = "[combat]hide;[mounted]hide;show",
        onEnter = function(text) vis.customdata = Trim(text) Apply() end })
    L:Row(custom, 26)
    L:Desc("Macro conditions, each ending in hide or show, separated by semicolons - the same "
        .. "language /cast [combat] uses.")
    L:EndCard()

    -- when it shows (cfg.showRule, ZacUI's visibility shape; the game's
    -- own show / hide, so it works in combat on these secure bars)
    L:Card("When it shows")
    local rg, rs = ns.CustomAccess(cfg, "showRule", nil, Apply)
    L:Add(UI.VisibilityPicker(L.current, { width = UI.CardInnerWidth(L), get = rg, set = rs,
        fields = { show = true }, shows = { "always", "combat", "nocombat", "group", "raid", "target", "never" } }), 6)
    L:Desc("The ticks under Hide when still win. A custom condition replaces both.")
    L:EndCard()
end

local function PagingCard(L, A, cfg, n)
    L:Card("Paging")
    local p = cfg.paging
    Check(L, "Page this bar", function() return p.enabled end, function(v) p.enabled = v end,
        "Off: the bar always shows its own twelve slots (bar " .. n .. " = slots "
        .. ((n - 1) * 12 + 1) .. "-" .. (n * 12) .. ").")
    local class = A.PLAYER_CLASS or "WARRIOR"
    local has = p.stance[class] ~= nil
    Check(L, "Page with your stance / form (" .. (class:sub(1, 1) .. class:sub(2):lower()) .. ")",
        function() return has end,
        function(v)
            if v then
                p.stance[class] = ({ WARRIOR = { [1] = 7, [2] = 8, [3] = 9 }, DRUID = { [3] = 9, [1] = 7, prowl = 8 },
                                     ROGUE = { [1] = 7 } })[class] or {}
            else
                p.stance[class] = nil
            end
        end,
        "Warriors: Battle / Defensive / Berserker show pages 7 / 8 / 9, like Blizzard's main bar. "
        .. "Druids: cat 7, prowl 8, bear 9. Rogues: stealth 7.")
    Check(L, "Follow the action bar page keys ([bar:2] ... [bar:6])", function() return p.actionbar end,
        function(v) p.actionbar = v end)
    Slider(L, "Page while holding Ctrl (0 = off)", function() return p.ctrl or 0 end, function(v) p.ctrl = v end, 0, 10, 1)
    Slider(L, "Page while holding Alt", function() return p.alt or 0 end, function(v) p.alt = v end, 0, 10, 1)
    Slider(L, "Page while holding Shift", function() return p.shift or 0 end, function(v) p.shift = v end, 0, 10, 1)
    Slider(L, "Default page (0 = this bar's own)", function() return p.default or 0 end, function(v) p.default = v end, 0, 10, 1)
    Slider(L, "Button offset", function() return cfg.offset or 0 end, function(v) cfg.offset = v end, 0, 11, 1,
        nil, "Rotates which slot the first button shows.")
    local drv = UI.Font(L.current, F.SMALL, { cat = "text", key = "gray",
        text = "Driver: " .. A.PageDriver(cfg), width = L:Room() })
    drv:SetNonSpaceWrap(true)     -- (one long word: wrap it anywhere)
    drv:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.CONTROL_X, L.current._y)
    L.current._y = L.current._y - math.max(12, drv:GetStringHeight() or 12) - 6
    L:EndCard()
end

local function EveryBarGeneral(L, A, p)
    local c = p.core
    L:Card("Buttons (every bar)")
    Check(L, "Lock buttons (drag with the pickup modifier)", function() return c.buttonlock end,
        function(v) c.buttonlock = v end,
        "Blizzard's own lock. The modifier is Interface > Action Bars > Pick Up Action Key.")
    Dropdown(L, "Tooltips", { { text = "Always", value = "enabled" }, { text = "Out of combat only", value = "nocombat" },
                              { text = "Never", value = "disabled" } },
        function() return c.tooltip end, function(v) c.tooltip = v end)
    Check(L, "Self-cast modifier", function() return c.selfcast end, function(v) c.selfcast = v end,
        "Holding the self-cast key casts on you.")
    Check(L, "Focus-cast modifier", function() return c.focuscast end, function(v) c.focuscast = v end)
    Check(L, "Right-click casts on yourself", function() return c.rightclickself end, function(v) c.rightclickself = v end)
    L:EndCard()
end

local function GeneralTab(L, A, p, id, kind, cfg, n)
    L:Card("Show")
    Check(L, "Show this bar", function() return cfg.enabled end, function(v) cfg.enabled = v end, nil, true)
    if kind == "action" then
        Slider(L, "Buttons", function() return cfg.buttons or 12 end, function(v) cfg.buttons = v end, 1, 12, 1)
    end
    if kind == "action" or kind == "pet" then
        Check(L, "Show empty slots", function() return cfg.showgrid end, function(v) cfg.showgrid = v end,
            "Empty buttons stay on screen instead of only while you drag a spell.")
    end
    if kind ~= "status" then
        Check(L, "Click-through", function() return cfg.clickthrough end, function(v) cfg.clickthrough = v end,
            "The mouse passes straight through the buttons. Keys still work.")
    end
    L:EndCard()

    L:Card("Fade")
    Check(L, "Fade out until the mouse is over it", function() return cfg.fade end, function(v) cfg.fade = v end, nil, true)
    local s = Slider(L, "Faded opacity", function() return math.floor((cfg.fadeAlpha or 0.1) * 100 + 0.5) end,
        function(v) cfg.fadeAlpha = v / 100 end, 0, 100, 5, Pct,
        "0% hides the bar completely until you point at where it is. How it fades - speed, "
        .. "and a wait before fading out - is on the Animation tab.")
    UI.SetEnabled(s, cfg.fade)
    L:EndCard()

    VisibilityCard(L, cfg)
    if kind == "action" then PagingCard(L, A, cfg, n) end
    if kind == "bagbar" then
        L:Card("Bags")
        Check(L, "Show the key ring", function() return cfg.keyring end, function(v) cfg.keyring = v end)
        Check(L, "Only the backpack", function() return cfg.onebag end, function(v) cfg.onebag = v end)
        L:EndCard()
    end
    EveryBarGeneral(L, A, p)
end

-- ============================================================
-- LOOK
-- ============================================================
local function ThemeButton(L, text, tip, onClick)
    ButtonRow(L, { { text, function() onClick() Apply() ns.SettingsChanged("reset") RefreshConfig() end,
        width = 150, tooltip = tip } }, M.BUTTON_H + 4)
end

local function LookTab(L, A, p, id, kind, cfg)
    L:Card("Size")
    if BUTTONS[kind] then
        local def = (kind == "action") and A.BUTTON or A.PET_BUTTON
        Slider(L, "Button size", function() return cfg.buttonSize or def end, function(v) cfg.buttonSize = v end,
            16, 64, 1, Px)
    end
    if kind ~= "status" then
        Slider(L, "Space between buttons", function() return cfg.padding or 2 end, function(v) cfg.padding = v end,
            -10, 30, 1, Px)
    end
    if MAX_ROWS[kind] then
        Slider(L, "Rows", function() return cfg.rows or 1 end, function(v) cfg.rows = v end, 1, MAX_ROWS[kind], 1)
    end
    if kind == "status" then
        Slider(L, "Width", function() return cfg.width or 1024 end, function(v) cfg.width = v end, 200, 2000, 8, Px)
    end
    Slider(L, "Opacity", function() return math.floor((cfg.alpha or 1) * 100 + 0.5) end,
        function(v) cfg.alpha = v / 100 end, 0, 100, 5, Pct)
    L:EndCard()

    if BUTTONS[kind] then
        L:Card("Button skin")
        Slider(L, "Icon zoom", function() return cfg.iconZoom or 8 end, function(v) cfg.iconZoom = v end, 0, 20, 1, Pct,
            "How much of the icon's edge is cropped away. 0% shows the whole icon, frame art and all.")
        Slider(L, "Border thickness", function() return cfg.borderSize or 1 end, function(v) cfg.borderSize = v end,
            0, 4, 1, Px, "0 px: no border.")
        local accentBorder = ns.Col and ns.Col("border") or { r = 0, g = 0, b = 0, a = 1 }
        Color(L, "Border colour", cfg, "borderColor", accentBorder)
        ThemeButton(L, "Use the theme's border", "Back to the border colour on Appearance > Colours.",
            function() cfg.borderColor = nil end)
        if kind == "action" then
            Color(L, "Border while the slot holds gear you wear", cfg, "equippedColor", { 0.35, 0.65, 1, 1 })
        end
        Check(L, "Backing behind each button", function() return cfg.backdrop end, function(v) cfg.backdrop = v end,
            "A flat square under the icon - it shows through see-through icons and fills empty slots.", true)
        local bd = Color(L, "Backing colour", cfg, "backdropColor", { 0, 0, 0, 0.6 })
        UI.SetEnabled(bd, cfg.backdrop)
        -- shadow and glow round each button (cfg.chrome, the standard's
        -- shape; nothing saved = none)
        local cg, cs = ns.CustomAccess(cfg, "chrome", nil, Apply)
        local cp = UI.ChromePicker(L.current, { width = UI.CardInnerWidth(L), get = cg, set = cs,
            fields = { shadowSize = true, shadowColor = true, glowSize = true, glowColor = true } })
        L:Add(cp, 6)
        if ns.CustomPick then ns.CustomPick.RegisterGroup("ab.button", cp) end
        L:EndCard()

        L:Card("Highlights")
        Color(L, "When pointed at", cfg, "hoverColor", { 1, 1, 1, 0.12 })
        Color(L, "When pressed", cfg, "pushedColor", { 1, 1, 1, 0.18 })
        local a = ns.Col and ns.Col("accent") or { r = 1, g = 0.82, b = 0 }
        Color(L, "Active (a queued attack, a stance you are in)", cfg, "checkedColor", { a.r, a.g, a.b, 0.35 })
        ThemeButton(L, "Use the theme's accent", "Back to the accent colour on Appearance > Colours, at 35%.",
            function() cfg.checkedColor = nil end)
        L:EndCard()

        L:Card("Cooldowns")
        Check(L, "Show the dark sweep", function() return cfg.cdSwipe ~= false end, function(v) cfg.cdSwipe = v end)
        Dropdown(L, "Cooldown numbers", { { text = "As the game's option says", value = "game" },
                                          { text = "Always", value = "show" },
                                          { text = "Never", value = "hide" } },
            function() return cfg.cdText or "game" end, function(v) cfg.cdText = v end)
        L:Desc("The game's option is Interface > Action Bars > Show Numbers for Cooldowns. Their font "
            .. "and colour are on the Text tab.")
        L:EndCard()
    end

    if kind == "action" then
        local c = p.core
        L:Card("Range and usability (every bar)")
        Check(L, "Colour buttons by range and usability", function() return c.colorButtons end,
            function(v) c.colorButtons = v end,
            "Off: the game's own colours (red key text out of range, grey when unusable, blue without "
            .. "mana). On: the colours below.", true)
        local on = c.colorButtons and true or false
        local dd = Dropdown(L, "Out of range", { { text = "Tint the icon", value = "button" },
                                                 { text = "Tint the key text", value = "hotkey" },
                                                 { text = "No tint", value = "none" } },
            function() return c.outofrange end, function(v) c.outofrange = v end)
        UI.SetEnabled(dd, on)
        UI.SetEnabled(Color(L, "Out of range", c, "rangeColor", { 0.8, 0.1, 0.1 }, { alpha = false, legacy = true }), on)
        UI.SetEnabled(Color(L, "Not enough mana, rage or energy", c, "manaColor", { 0.5, 0.5, 1 }, { alpha = false, legacy = true }), on)
        UI.SetEnabled(Color(L, "Cannot be used now", c, "unusableColor", { 0.4, 0.4, 0.4 }, { alpha = false }), on)
        -- per-state looks (core.states): over whichever colours are on
        local sg, ss = ns.CustomAccess(c, "states", nil, Apply)
        L:Add(UI.StateEditor(L.current, { width = UI.CardInnerWidth(L), get = sg, set = ss,
            label = "Each state's own colours", states = A.STATE_LIST, remember = STATE_PICK,
            fields = { color = true, textColor = true },
            defaults = function() return A.StateDefaults(c) end }), 6)
        L:Desc("Colour tints the icon, text colour the key text. They go over the colours above, "
            .. "on or off.")
        L:EndCard()

        L:Card("Spell alerts (every bar)")
        Dropdown(L, "When a spell on a button lights up", { { text = "The game's alert", value = "game" },
                                                             { text = "ZacUI's glow", value = "zacui" },
                                                             { text = "Nothing", value = "none" } },
            function() return c.glow or "game" end, function(v) c.glow = v end)
        local zg = (c.glow == "zacui")
        UI.SetEnabled(Color(L, "Glow colour", c, "glowColor", { 1, 0.82, 0, 1 }), zg)
        UI.SetEnabled(Slider(L, "Glow thickness", function() return c.glowSize or 2 end,
            function(v) c.glowSize = v end, 1, 6, 1, Px), zg)
        L:Desc("ZacUI's glow is a coloured frame round the button; how it moves is on the Animation tab.")
        L:EndCard()
    end
end

-- ============================================================
-- TEXT
-- ============================================================
local ELEMENTS = {
    { key = "hotkey", hide = "hideHotkey", title = "Key text", show = "Show key text", sample = "S-1  C-WU", size = 13 },
    { key = "count", hide = "hideCount", title = "Count", show = "Show counts", sample = "5  20", size = 16 },
    { key = "macro", hide = "hideMacro", title = "Macro name", show = "Show macro names", sample = "Shout", size = 10 },
}

-- the template's own shadow on a live button's text, as the picker's
-- "unset" value, so the checkbox tells the truth before it is touched
local function StockShadow(A, key)
    local bar = A.actionBars and A.actionBars[1]
    local b = bar and bar.buttons and bar.buttons[1]
    local fs = b and ((key == "hotkey" and b.zHotkey) or (key == "count" and b.zCount) or (key == "macro" and b.zName))
    local sh = fs and fs.zStockShadow
    if sh and (sh[1] ~= 0 or sh[2] ~= 0) then return true, sh[1], sh[2] end
    return false, 1, -1
end

-- Where one text sits on the button: ZacUI's anchor picker over the bar's
-- cfg.anchors.<key>, its default the text's own corner and offsets (the
-- keys the bar always had). key nil = only for this bar's own texts.
local function TextSpot(L, A, cfg, key, defaults)
    local targets = {}
    for _, k in ipairs(A.ANCHOR_TARGETS or {}) do
        if k ~= key then targets[#targets + 1] = { value = k, text = A.ANCHOR_LABELS[k] or k } end
    end
    local get, set = ns.CustomAccess(cfg, "anchors", key, Apply)
    UI.TextElement(L, { key = "ab." .. key, anchorGet = get, anchorSet = set, anchorDefaults = defaults,
        targets = targets, defaultTargetLabel = "The button", anchorMin = -40, anchorMax = 40 })
end

local function TextTab(L, A, p, id, kind, cfg)
    if not BUTTONS[kind] then return end
    if kind == "action" then
        for _, e in ipairs(ELEMENTS) do
            local el = cfg.fonts[e.key]
            L:Card(e.title)
            Check(L, e.show, function() return not cfg[e.hide] end, function(v) cfg[e.hide] = not v end)
            local has, sx, sy = StockShadow(A, e.key)
            local fp = UI.FontPicker(L.current, { label = "Font",
                get = function() return A.FontSpecOf(el) end,
                set = function(spec) A.PutFontSpec(el, spec) Apply() end,
                defaults = { size = e.size, outline = "outline", shadow = has, shadowX = sx, shadowY = sy },
                minSize = 6, maxSize = 32, sample = e.sample })
            L:Add(fp, 6)
            Color(L, "Colour", el, "color", { 1, 1, 1, 1 }, { legacy = true })
            -- its spot: any corner of any piece of the button (the old
            -- corner and offsets are where it sits until it is moved)
            TextSpot(L, A, cfg, e.key, function() return A.TextAnchorDefaults(el) end)
            L:EndCard()
        end
    else
        L:Card("Key text")
        Check(L, "Show key text", function() return not cfg.hideHotkey end, function(v) cfg.hideHotkey = not v end)
        L:EndCard()
    end

    L:Card("Cooldown numbers")
    local fp = UI.FontPicker(L.current, { label = "Font",
        get = function() return cfg.fonts and cfg.fonts.cooldown end,
        set = function(spec)
            cfg.fonts = cfg.fonts or {}
            cfg.fonts.cooldown = spec
            Apply()
        end,
        defaults = { size = 16, outline = "outline", shadow = false },
        minSize = 6, maxSize = 32, sample = "12  3.4", defaultLabel = "ZacUI's font" })
    L:Add(fp, 6)
    Color(L, "Colour", cfg, "cdColor", { 1, 1, 1, 1 })
    ThemeButton(L, "Use the game's font", "Back to the numbers the game draws, in its own font and colour.",
        function() if cfg.fonts then cfg.fonts.cooldown = nil end cfg.cdColor = nil end)
    TextSpot(L, A, cfg, "cooldown", { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 })
    L:Desc("Until you change them the game draws these in its own font. Whether they show at all is "
        .. "on the Look tab.")
    L:EndCard()
end

-- ============================================================
-- ANIMATION
-- ============================================================
local function AnimTab(L, A, p, id, kind, cfg)
    L:Card("Fading")
    if not cfg.fade then
        L:Desc("This bar does not fade. Turn on \"Fade out until the mouse is over it\" on the General tab.")
    end
    local fin = UI.AnimationPicker(L.current, { label = "When the mouse arrives",
        styles = { "none", "fade" },
        get = function() return cfg.fadeIn or A.FADE_IN end,
        set = function(spec) cfg.fadeIn = spec Apply() end })
    L:Add(fin, 6)
    L:Desc("None is an instant change. Delay waits before fading in.")
    -- the fade-out's delay is the bar's fadeDelay (the wait after the
    -- mouse leaves), kept under the key it has always had
    local fout = UI.AnimationPicker(L.current, { label = "When the mouse leaves",
        styles = { "none", "fade" },
        get = function()
            local t = ns.CopySetting and ns.CopySetting(cfg.fadeOut or A.FADE_OUT) or {}
            t.delay = cfg.fadeDelay or 0.2
            return t
        end,
        set = function(spec)
            cfg.fadeDelay = spec.delay
            spec.delay = nil
            cfg.fadeOut = spec
            Apply()
        end })
    L:Add(fout, 6)
    L:Desc("Delay is how long the bar waits after the mouse leaves before it fades. Replay in the "
        .. "preview plays both; Appearance > Motion turns every animation off or speeds them up.")
    UI.SetEnabled(fin, cfg.fade)
    UI.SetEnabled(fout, cfg.fade)
    L:EndCard()

    if kind == "action" then
        local c = p.core
        L:Card("Spell alert glow (every bar)")
        if c.glow ~= "zacui" then
            L:Desc("Used when spell alerts are set to ZacUI's glow (Look tab).")
        end
        local g = UI.AnimationPicker(L.current, { label = "While a spell is lit",
            styles = { "none", "pulse", "flash", "fade" },
            get = function() return c.glowAnim end,
            set = function(spec) c.glowAnim = spec Apply() end })
        L:Add(g, 6)
        L:Desc("Pulse and Flash repeat for as long as the spell is lit when Repeat is on.")
        UI.SetEnabled(g, c.glow == "zacui")
        L:EndCard()
    end
end

-- ============================================================
-- POSITION
-- ============================================================
local function PositionTab(L, A, p, id, kind, cfg)
    L:Card("Position")
    local line = UI.Font(L.current, F.SMALL, { cat = "text", key = "gray",
        text = string.format("%s  x %.1f  y %.1f", cfg.point or "-", cfg.x or 0, cfg.y or 0) })
    line:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.CONTROL_X, L.current._y)
    L.current._y = L.current._y - 18
    ButtonRow(L, {
        { A.unlocked and "Lock bars" or "Unlock bars", function()
            A.SetUnlocked(not A.unlocked) RefreshConfig()
        end, width = 110, active = A.unlocked },
        { "Center", function()
            cfg.point, cfg.x, cfg.y = "CENTER", 0, 0
            ApplyNow() RefreshConfig()
        end, width = 90 },
        { "Nudge left", function() cfg.x = (cfg.x or 0) - 1 ApplyNow() RefreshConfig() end, width = 90 },
        { "Nudge right", function() cfg.x = (cfg.x or 0) + 1 ApplyNow() RefreshConfig() end, width = 90 },
    })
    ButtonRow(L, {
        { "Nudge up", function() cfg.y = (cfg.y or 0) + 1 ApplyNow() RefreshConfig() end, width = 90 },
        { "Nudge down", function() cfg.y = (cfg.y or 0) - 1 ApplyNow() RefreshConfig() end, width = 90 },
    })
    L:Desc("Unlock, then drag the gold boxes; or open ZacUI's Edit Mode (/zui edit), which unlocks "
        .. "every bar along with everything else.")
    L:EndCard()

    L:Card("Layout")
    if kind ~= "status" then
        Dropdown(L, "Grow", { { text = "Right and down", value = "RIGHT/DOWN" }, { text = "Left and down", value = "LEFT/DOWN" },
                              { text = "Right and up", value = "RIGHT/UP" }, { text = "Left and up", value = "LEFT/UP" } },
            function() return (cfg.growH or "RIGHT") .. "/" .. (cfg.growV or "DOWN") end,
            function(v) cfg.growH, cfg.growV = v:match("^(%u+)/(%u+)$") end)
        L:Desc("The anchor corner stays put when a bar grows the other way, so a bar pinned to the "
            .. "right edge can grow leftwards into the screen.")
    end
    if kind == "micro" then
        Check(L, "Vertical", function() return cfg.vertical end, function(v) cfg.vertical = v end)
    end
    Slider(L, "Scale", function() return math.floor((cfg.scale or 1) * 100 + 0.5) end,
        function(v) cfg.scale = v / 100 end, 50, 250, 5, Pct)
    L:EndCard()

    -- the buttons' layout on the standard's shape (cfg.layout): nothing
    -- saved = Grow / Rows / Space between buttons above and on Look
    if BUTTONS[kind] then
        L:Card("Button layout")
        local lg, ls = ns.CustomAccess(cfg, "layout", nil, Apply)
        L:Add(UI.LayoutPicker(L.current, { width = UI.CardInnerWidth(L), get = lg, set = ls,
            fields = { grow = true, wrap = true, perLine = true, spacingX = true, spacingY = true },
            grows = { "RIGHT", "LEFT" },
            defaults = function() return A.LayoutDefaults(cfg, (kind == "action") and (cfg.buttons or 12) or nil) end }), 6)
        L:Desc("Until you change these the bar follows Grow above and Rows and Space between "
            .. "buttons on the Look tab.")
        L:EndCard()
    end

    -- its layer (cfg.framePos: the standard's frame shape; the spot stays
    -- the mover's)
    L:Card("Layer")
    local fg, fs = ns.CustomAccess(cfg, "framePos", nil, Apply)
    L:Add(UI.FrameLayerPicker(L.current, { width = UI.CardInnerWidth(L), get = fg, set = fs,
        fields = { strata = true, level = true } }), 6)
    L:Desc("Which frames the bar draws over. Nothing set: the layer it has always had.")
    L:EndCard()
end

-- ============================================================
-- ADVANCED
-- ============================================================
-- the look keys a reset puts back (position, layout, paging and when the
-- bar shows are left alone)
local LOOK_KEYS = { "buttonSize", "iconZoom", "borderSize", "borderColor", "equippedColor", "backdrop",
                    "backdropColor", "hoverColor", "pushedColor", "checkedColor", "cdSwipe", "cdText",
                    "cdColor", "fadeIn", "fadeOut", "fadeDelay", "fadeAlpha", "alpha" }

local function ResetLook(A, id, kind, cfg)
    local fresh
    local n = tonumber(id:match("^bar(%d+)$") or "")
    if n then fresh = A.DefaultBar(n) else fresh = A.DefaultProfile()[id] end
    if not fresh then return end
    for _, k in ipairs(LOOK_KEYS) do cfg[k] = A.DeepCopy(fresh[k]) end
    if kind == "action" then cfg.fonts = A.DeepCopy(fresh.fonts) elseif cfg.fonts then cfg.fonts.cooldown = nil end
end

local function ProfileCard(L, A)
    L:Card("Profile")
    local d = A.DB()
    local names = A.ListProfiles()
    local _, current = A.Profile()
    local items = {}
    for _, n in ipairs(names) do items[#items + 1] = { text = n, value = n } end
    Dropdown(L, "This character uses", items, function() return current end,
        function(v) A.UseProfile(v) end, 260)
    local newName = UI.EditBox(L.current, { width = 200, height = 20, hint = "New profile name" })
    L:Row(newName, 26)
    ButtonRow(L, {
        { "New (defaults)", function()
            local ok, err = A.NewProfile(Trim(newName:GetText()))
            if ok then A.UseProfile(Trim(newName:GetText())) RefreshConfig() else Print(tostring(err)) end
        end, width = 110 },
        { "Copy current as", function()
            local ok, err = A.CopyProfile(current, Trim(newName:GetText()))
            if ok then A.UseProfile(Trim(newName:GetText())) RefreshConfig() else Print(tostring(err)) end
        end, width = 120 },
        { "Rename current", function()
            local ok, err = A.RenameProfile(current, Trim(newName:GetText()))
            if ok then RefreshConfig() else Print(tostring(err)) end
        end, width = 120 },
        { "Delete current", function()
            UI.Confirm({ title = "Delete bar profile", destructive = true, acceptText = "Delete",
                text = "Delete '" .. current .. "'? Characters wearing it fall back to the profile for new characters.",
                onAccept = function() A.DeleteProfile(current) A.ApplyAll() RefreshConfig() end })
        end, width = 110 },
    })
    Dropdown(L, "Profile for new characters", items, function() return d.defaultProfile end,
        function(v) d.defaultProfile = v end, 260)
    L:Desc("A character that has never chosen a profile wears this one. Bar profiles travel in "
        .. "ZacUI profile strings (Profiles page), so another account gets them with one paste.")
    L:EndCard()
end

local function AdvancedTab(L, A, p, id, kind, cfg)
    ProfileCard(L, A)

    L:Card("Reset")
    ButtonRow(L, { { "Reset this bar's look", function()
        UI.Confirm({ title = "Reset bar look", destructive = true, acceptText = "Reset",
            text = "Put " .. A.BarLabel(id) .. "'s size, skin, colours, text, opacity and fades back to "
                .. "the defaults? Its position, layout, paging and when it shows stay as they are.",
            onAccept = function()
                ResetLook(A, id, kind, cfg)
                ApplyNow()
                ns.SettingsChanged("reset")
                RefreshConfig()
            end })
    end, width = 170 } })
    L:EndCard()

    L:Card("Keys")
    L:Desc("Bars 1, 3, 4, 5 and 6 use Blizzard's own key names (Action Bar, Right Bar, Left Bar, "
        .. "Bottom Right, Bottom Left in the Key Bindings window). Bars 2 and 7-10 are listed under "
        .. "ZacUI there. Keys set on Bartender4's buttons are moved over the first time each character "
        .. "logs in; this button runs that again.")
    ButtonRow(L, { { "Move Bartender4 keys again", function() A.MigrateBartenderKeys(true) end, width = 200 } })
    L:EndCard()
end

-- ============================================================
-- ACTION BARS PAGE
-- ============================================================
-- Builds one bar tab: the preview (on every bar tab, not Loadouts), the
-- chooser, then the tab's cards for the chosen bar. The search index
-- builds every tab unseen; it builds for bar 1 and adds the cards only
-- the small bars have, so every label is findable.
local function BarTab(build, extras)
    return function(L)
        local A = AB()
        local p = A.Profile()
        local id = A.EditingId()
        L:Preview(A.PreviewSpec())
        if L.indexAll then
            build(L, A, p, "bar1", "action", p.bars[1], 1)
            for _, extra in ipairs(extras and { "bagbar", "micro", "status" } or {}) do
                local okx = pcall(build, L, A, p, extra, extra, p[extra])
                if not okx then break end
            end
            return
        end
        BarChooser(L, A, p, id)
        local cfg, n = A.CfgFor(id, p)
        build(L, A, p, id, A.KindOf(id), cfg, n)
    end
end

RegisterPage("Bars", function(L)
    local A = AB()
    L:Header("Action bars",
        "Ten bars, pet and stance bars, bags, the micro menu and the XP strip - how each looks, "
        .. "fades, pages and where it sits. Loadouts are the last tab.")

    if not A then
        L:Notice("missing", "The bar system did not load.")
        return
    end

    if A.BartenderLoaded() then
        L:Card("Bartender4 is running")
        L:Desc("ZacUI's bars stand down while Bartender4 is enabled. Import Bartender4's settings "
            .. "(every profile, with each character's choice), then turn Bartender4 off and reload.")
        ButtonRow(L, {
            { "Import from Bartender4", function()
                local n, err = A.ImportBartender()
                if n then
                    Print("Imported " .. n .. " Bartender4 profile" .. (n == 1 and "" or "s") .. ".")
                else
                    Print("Import failed: " .. tostring(err))
                end
                RefreshConfig()
            end, width = 170 },
            { "Turn Bartender4 off + reload", function()
                local disable = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
                if disable then pcall(disable, "Bartender4") end
                ReloadUI()
            end, width = 200 },
        })
        local d = A.DB()
        L:Desc(d.importedBT4 and ("Last import: " .. date("%Y-%m-%d %H:%M", d.importedBT4) .. ".")
            or "Not imported yet.")
        L:EndCard()
    elseif not (ZacUIDB.modules and ZacUIDB.modules.bars) then
        L:Notice("off", "The Action bars (ZacUI) module is off, so Blizzard's bars are showing.", "Modules > HUD", "bars")
    end

    -- a sample text picked in the preview: the Text tab, where its spot is
    if ns.CustomPick then
        ns.CustomPick.SetHandler("bars.bar", function(el)
            if type(el) ~= "string" or not el:find("^ab%.") then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            -- the button itself: its skin, shadow and glow are on Look
            ZacUIDB.config.tabs.bars = (el == "ab.button") and "look" or "text"
            RefreshConfig()
        end)
    end

    -- which bar the tabs edit (read before the tabs: a tab remembered
    -- from the old one-tab-per-bar page names the bar to start on)
    local id = A.EditingId()
    local kind = A.KindOf(id)
    local tabs = {
        { id = "general", label = "General", build = BarTab(GeneralTab, true) },
        { id = "look", label = "Look", build = BarTab(LookTab, true) },
    }
    if BUTTONS[kind] or L.indexAll then
        tabs[#tabs + 1] = { id = "text", label = "Text", build = BarTab(TextTab) }
    end
    tabs[#tabs + 1] = { id = "anim", label = "Animation", build = BarTab(AnimTab) }
    tabs[#tabs + 1] = { id = "pos", label = "Position", build = BarTab(PositionTab, true) }
    tabs[#tabs + 1] = { id = "adv", label = "Advanced", build = BarTab(AdvancedTab) }
    -- The loadouts page, as a tab here rather than a row of its own.
    tabs[#tabs + 1] = { id = "loadouts", label = "Loadouts", build = function(L2)
        local page = ns.ConfigPages and ns.ConfigPages["Loadouts"]
        if page then
            L2.asTab = true
            page(L2)
        end
    end }
    L:Tabs(tabs)
end)

-- ============================================================
-- LOADOUTS PAGE
-- ============================================================
local CLASS_LIST = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function Pretty(class)
    if not class then return "?" end
    return class:sub(1, 1) .. class:sub(2):lower()
end

RegisterPage("Loadouts", function(L)
    local Lo = LO()
    if L.asTab then
        L:Card("Loadouts")
        L:Desc("Everything ON your bars - slots, macros, key bindings, the pet bar - saved under a "
            .. "name. Apply one to any character, carry it as a string, or have it applied at login. "
            .. "Reads Myslot strings.")
        L:EndCard()
    else
        L:Header("Bar loadouts",
            "Everything ON your bars - slots, macros, key bindings, the pet bar - saved under a "
            .. "name. Apply one to any character, carry it as a string, or have it applied at login. "
            .. "Reads Myslot strings.")
    end
    if not Lo then
        L:Notice("missing", "The loadout system did not load.")
        return
    end
    local db = Lo.DB()
    local rules = Lo.Rules()
    local names = Lo.List()
    local items = { { text = "None", value = "" } }
    for _, n in ipairs(names) do items[#items + 1] = { text = n, value = n } end

    -- ---------------------------------------------------------
    L:Card("Save what is on your bars now")
    local nameBox = UI.EditBox(L.current, { width = 220, height = 20, hint = "Loadout name" })
    L:Row(nameBox, 26)
    ButtonRow(L, { { "Save", function()
        local name = Trim(nameBox:GetText())
        if name == "" then Print("Give the loadout a name first.") return end
        local function Commit()
            local ok, err = Lo.Save(name)
            Print(ok and ("Saved loadout '" .. name .. "'.") or ("Could not save: " .. tostring(err)))
            RefreshConfig()
        end
        if db[name] then
            UI.Confirm({ title = "Overwrite loadout", destructive = true, acceptText = "Overwrite",
                text = "'" .. name .. "' exists. Replace it with what is on your bars now?", onAccept = Commit })
        else
            Commit()
        end
    end, width = 90 } })
    L:Desc("Captures all 120 action slots, every macro (account and character), every key that is "
        .. "bound and the pet bar. Spells are saved by rank; items by id.")
    L:EndCard()

    -- ---------------------------------------------------------
    L:Card("Saved loadouts")
    if #names == 0 then L:Desc("Nothing saved yet.") end
    for _, name in ipairs(names) do
        local lo = db[name]
        local n = 0
        for _ in pairs(lo.slots or {}) do n = n + 1 end
        local line = UI.Holder(L.current)
        line:SetSize(460, M.BUTTON_H)
        local label = UI.Font(line, F.LABEL, { text = name })
        label:SetPoint("LEFT")
        label:SetWidth(150)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        local sub = UI.Font(line, F.SMALL, { cat = "text", key = "gray",
            text = Pretty(lo.class) .. (lo.player and (" - " .. lo.player) or "") .. "  " .. n .. " slots, "
                .. #(lo.macros or {}) .. " macros, " .. #(lo.binds or {}) .. " keys" })
        sub:SetPoint("LEFT", line, "LEFT", 152, 0)
        sub:SetWidth(170)
        sub:SetJustifyH("LEFT")
        sub:SetWordWrap(false)
        local apply = UI.Button(line, "Apply", { width = 58, height = 18, size = F.SMALL, onClick = function()
            UI.Confirm({ title = "Apply loadout", acceptText = "Apply",
                text = "Put '" .. name .. "' on this character's bars now? Slots the loadout does not mention "
                    .. (rules.clearSlots and "are emptied" or "are left alone") .. " (see the rules card).",
                onAccept = function() Lo.ApplyNamed(name) end })
        end })
        apply:SetPoint("LEFT", line, "LEFT", 326, 0)
        local export = UI.Button(line, "Export", { width = 58, height = 18, size = F.SMALL, onClick = function()
            local str, err = Lo.Export(name)
            if str and L.exportBox then L.exportBox:SetText(str) L.exportBox:Focus() end
            if not str then Print("Could not export: " .. tostring(err)) end
        end })
        export:SetPoint("LEFT", apply, "RIGHT", 4, 0)
        local del = UI.Button(line, "X", { width = 20, height = 18, size = F.SMALL, onClick = function()
            UI.Confirm({ title = "Delete loadout", destructive = true, acceptText = "Delete",
                text = "Delete '" .. name .. "'?", onAccept = function() Lo.Delete(name) RefreshConfig() end })
        end })
        del:SetPoint("LEFT", export, "RIGHT", 4, 0)
        L:Row(line, M.BUTTON_H + 2)
    end
    if #names > 0 then
        local renameBox = UI.EditBox(L.current, { width = 160, height = 20, hint = "New name" })
        L:Row(renameBox, 26)
        local which = names[1]
        Dropdown(L, "Rename", (function()
            local t = {}
            for _, n in ipairs(names) do t[#t + 1] = { text = n, value = n } end
            return t
        end)(), function() return which end, function(v) which = v end, 200)
        ButtonRow(L, { { "Rename", function()
            local ok, err = Lo.Rename(which, Trim(renameBox:GetText()))
            if ok then RefreshConfig() else Print(tostring(err)) end
        end, width = 90 } })
    end
    L:EndCard()

    -- ---------------------------------------------------------
    L:Card("This character")
    ZacUICharDB = ZacUICharDB or {}
    local rec = ZacUICharDB.loadout or {}
    Dropdown(L, "Loadout applied on login", items, function() return rec.name or "" end,
        function(v)
            if v == "" then ZacUICharDB.loadout = nil
            else ZacUICharDB.loadout = { name = v, mode = rec.mode or rules.mode } end
        end, 260)
    local MODES = { { text = "Every login", value = "always" }, { text = "Once (first login)", value = "once" },
                    { text = "Never", value = "off" } }
    Dropdown(L, "When", MODES, function() return rec.mode or rules.mode end,
        function(v) if ZacUICharDB.loadout then ZacUICharDB.loadout.mode = v ZacUICharDB.loadout.fromRule = nil end end, 200)
    L:Desc("Every login is cheap: slots that already match are left alone, so it only ever fixes "
        .. "what drifted and fills in spells learned since."
        .. (rec.fromRule and " This character is following the account rule below." or ""))
    L:EndCard()

    -- ---------------------------------------------------------
    L:Card("New characters (account rule)")
    L:Desc("A character that has never chosen a loadout gets one from here the first time it logs "
        .. "in - its class's loadout if set, otherwise the one for everyone.")
    Dropdown(L, "Everyone", items, function() return rules.all or "" end,
        function(v) rules.all = (v ~= "" and v) or nil end, 260)
    for _, class in ipairs(CLASS_LIST) do
        Dropdown(L, Pretty(class), items, function() return rules.byClass[class] or "" end,
            function(v) rules.byClass[class] = (v ~= "" and v) or nil end, 220)
    end
    Dropdown(L, "When", MODES, function() return rules.mode end, function(v) rules.mode = v end, 200)
    Check(L, "Empty slots the loadout does not mention", function() return rules.clearSlots end,
        function(v) rules.clearSlots = v end)
    Check(L, "Clear every key first", function() return rules.clearBinds end, function(v) rules.clearBinds = v end,
        "Off: the loadout's keys are set and any other key you had stays. On: keys not in the loadout are unbound.")
    L:EndCard()

    -- ---------------------------------------------------------
    L:Card("Export")
    local exportBox = UI.TextBox(L.current, { width = 400, height = 72, selectOnFocus = true })
    L:Row(exportBox, 80)
    L.exportBox = exportBox
    ButtonRow(L, { { "Export what is on my bars now", function()
        local str = Lo.Export()
        exportBox:SetText(str or "")
        exportBox:Focus()
    end, width = 220 } })
    L:Desc("Export next to a saved loadout above fills this box with that loadout. Ctrl-A, Ctrl-C.")
    L:EndCard()

    -- ---------------------------------------------------------
    L:Card("Import")
    local importBox = UI.TextBox(L.current, { width = 400, height = 72 })
    L:Row(importBox, 80)
    -- Any string, any box (Core_Profiles / Config_Profiles): name what
    -- was pasted, and offer it when it belongs to another page.
    local Import = ns.Import
    if Import and Import.StatusRow then Import.StatusRow(L, importBox, "loadout") end
    -- the box's text as the status line read it: without the code fence
    -- or quote mark a chat app left around it
    local function Pasted()
        local text = importBox:GetText()
        if Import and Import.Clean then text = Import.Clean(text) end
        return text
    end
    local importName = UI.EditBox(L.current, { width = 200, height = 20, hint = "Save as" })
    L:Row(importName, 26)
    ButtonRow(L, {
        { "Save", function()
            if Import and Import.Redirect and Import.Redirect(importBox:GetText(), "loadout") then return end
            local lo, err = Lo.Import(Pasted())
            if not lo then Print("Import failed: " .. tostring(err)) return end
            local name = Trim(importName:GetText())
            if name == "" then name = lo.name or lo.player or "Imported" end
            lo.name = name
            local ok, e2 = Lo.Save(name, lo)
            if ok then
                Print("Saved loadout '" .. name .. "'" .. (lo.source == "myslot" and " (from a Myslot string)." or "."))
                importBox:SetText("")
                RefreshConfig()
            else
                Print("Could not save: " .. tostring(e2))
            end
        end, width = 90 },
        { "Apply without saving", function()
            if Import and Import.Redirect and Import.Redirect(importBox:GetText(), "loadout") then return end
            local lo, err = Lo.Import(Pasted())
            if not lo then Print("Import failed: " .. tostring(err)) return end
            Lo.Report(Lo.Apply(lo, { clearSlots = rules.clearSlots, clearBinds = rules.clearBinds }), lo.name or "pasted")
        end, width = 150 },
    })
    L:Desc("Takes a ZacUI loadout string or a Myslot export (the whole thing, # lines included). "
        .. "Anything else ZacUI or Readycheck exports is recognised too and offered as what it is.")
    local saved = Lo.MyslotSaved()
    if saved then
        L:Gap(6)
        local t = UI.Font(L.current, F.LABEL, { text = "Myslot's saved exports on this account", cat = "ui", key = "accent" })
        t:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.CONTROL_X, L.current._y)
        L.current._y = L.current._y - 18
        for _, e in ipairs(saved) do
            local n = 0
            for _ in pairs(e.loadout.slots or {}) do n = n + 1 end
            L:Desc(e.name .. " - " .. Pretty(e.loadout.class) .. (e.loadout.player and (" " .. e.loadout.player) or "")
                .. ", " .. n .. " slots, " .. #(e.loadout.macros or {}) .. " macros, " .. #(e.loadout.binds or {}) .. " keys")
        end
        ButtonRow(L, { { "Adopt them all as loadouts", function()
            local n, err = Lo.AdoptMyslot()
            if n and n > 0 then Print("Adopted " .. n .. " Myslot export" .. (n == 1 and "" or "s") .. ".")
            else Print("Nothing adopted" .. (err and (": " .. err) or ".")) end
            RefreshConfig()
        end, width = 200 } })
        L:Desc("Myslot can be turned off afterwards; its exports live on here.")
    elseif not db.adoptedMyslot then
        L:Desc("Myslot is not loaded, so its saved exports cannot be read here. Enable Myslot once, "
            .. "open this page, adopt them, then turn it off.")
    end
    L:EndCard()
end)
