-- Core_Colors - the palette. ONE source of truth for every colour ZacUI
-- paints, in the flat dark / thin gold house style (Zac tried a darker
-- green with white titles 2026-10-20..23 and went back to gold).
-- Part of ZacUI; load order is set by the TOC.
--
-- TWO ACCESSORS, one table:
--   GetColor(category, key)  the structured read - what new code uses,
--                            and what the colour editor enumerates.
--   Col(flatKey)             the historic read. Every skin module in the
--                            addon calls Col("windowBg") and friends, so
--                            the flat names stay first-class forever;
--                            ALIAS maps each one onto its category pair.
--
-- OVERRIDE PRECEDENCE, deliberately in this order:
--   1. ZacUIDB.palette[cat][key]  - the structured user override
--   2. ZacUIDB.colors[flatKey]    - the legacy flat override, so a DB
--                                   saved by 1.x keeps its colours
--   3. PALETTE[cat][key]          - shipped default
-- Reads happen at PAINT time, never cached in an upvalue: that is what
-- lets the colour editor repaint a live window.

local ADDON_NAME, ns = ...

local Print = ns.Print

-- ============================================================
-- PALETTE
-- ============================================================
local PALETTE = {
    -- Window furniture
    -- (2026-11-10, Zac: "these 2 windows the ah in zui and then
    -- consumables checker in readycheck are still like pitch black") Every
    -- window outside the /zui window paints from this table, and it was
    -- still the old near-black (0.08 / 0.10 / 0.12) after the /zui window
    -- went to #1C1C1C. The same family now: window 0.110, cards 0.150,
    -- controls 0.160 or so. A colour picked on the Colours page still wins.
    ui = {
        windowBg    = { r = 0.110, g = 0.110, b = 0.110, a = 0.97 },
        elementBg   = { r = 0.160, g = 0.160, b = 0.160, a = 1.00 },
        cardBg      = { r = 0.150, g = 0.150, b = 0.150, a = 1.00 },
        headerBg    = { r = 0.140, g = 0.140, b = 0.140, a = 1.00 },
        -- The right-hand end of a title bar's fill. Until you set it, it
        -- is derived from headerBg and the accent (UIF_Controls); the value
        -- here is only what the editor shows as the default swatch.
        headerGradient = { r = 0.41, g = 0.33, b = 0.17, a = 1.00 },
        border      = { r = 0.00, g = 0.00, b = 0.00, a = 1.00 },
        borderHover = { r = 0.85, g = 0.65, b = 0.25, a = 1.00 },
        accent      = { r = 0.85, g = 0.65, b = 0.25, a = 1.00 },
        text        = { r = 0.90, g = 0.90, b = 0.90, a = 1.00 },
        -- The ring on a SELECTED tab / button / row. Green, never gold:
        -- gold means hover or focus in this UI, and a selected tab lit
        -- gold reads as "the mouse is here" when it is not.
        borderSelected = { r = 0.35, g = 0.62, b = 0.35, a = 1.00 },
    },
    -- Pressable things
    button = {
        bg          = { r = 0.165, g = 0.165, b = 0.165, a = 1.00 },
        hover       = { r = 0.215, g = 0.215, b = 0.215, a = 1.00 },
        pressed     = { r = 0.090, g = 0.090, b = 0.090, a = 1.00 },
        disabled    = { r = 0.120, g = 0.120, b = 0.120, a = 0.60 },
        active      = { r = 0.150, g = 0.210, b = 0.150, a = 1.00 },
        activeHover = { r = 0.180, g = 0.250, b = 0.180, a = 1.00 },
        xNormal     = { r = 0.70, g = 0.70, b = 0.70, a = 1.00 },
        xHover      = { r = 0.90, g = 0.30, b = 0.30, a = 1.00 },
    },
    -- The config window's left nav
    sidebar = {
        bg          = { r = 0.095, g = 0.095, b = 0.095, a = 1.00 },
        rowNormal   = { r = 0.150, g = 0.150, b = 0.150, a = 1.00 },
        rowHover    = { r = 0.215, g = 0.215, b = 0.215, a = 1.00 },
        rowSelected = { r = 0.150, g = 0.210, b = 0.150, a = 1.00 },
        indicator   = { r = 0.85, g = 0.65, b = 0.25, a = 1.00 },
    },
    checkbox = {
        bg          = { r = 0.160, g = 0.160, b = 0.160, a = 1.00 },
        border      = { r = 0.00, g = 0.00, b = 0.00, a = 1.00 },
        -- gold like the rest of the UI (Zac 2026-11-02). Unpicked, the tick
        -- is the gold Checkmark art as drawn (UIF_Controls PaintCheck).
        check       = { r = 0.85, g = 0.65, b = 0.25, a = 1.00 },
        hoverBorder = { r = 0.85, g = 0.65, b = 0.25, a = 1.00 },
    },
    dropdown = {
        bg          = { r = 0.150, g = 0.150, b = 0.150, a = 0.98 },
        itemHover   = { r = 0.240, g = 0.210, b = 0.140, a = 1.00 },
        itemText    = { r = 0.90, g = 0.90, b = 0.90, a = 1.00 },
        arrow       = { r = 0.80, g = 0.65, b = 0.35, a = 1.00 },
        selected    = { r = 0.85, g = 0.65, b = 0.25, a = 1.00 },
    },
    scrollbar = {
        track       = { r = 0.08, g = 0.08, b = 0.08, a = 0.80 },
        thumb       = { r = 0.60, g = 0.46, b = 0.18, a = 0.90 },
    },
    text = {
        normal      = { r = 0.90, g = 0.90, b = 0.90, a = 1.00 },
        gray        = { r = 0.60, g = 0.60, b = 0.60, a = 1.00 },
        gold        = { r = 1.00, g = 0.82, b = 0.00, a = 1.00 },
        green       = { r = 0.50, g = 0.80, b = 0.50, a = 1.00 },
        red         = { r = 1.00, g = 0.30, b = 0.30, a = 1.00 },
        orange      = { r = 1.00, g = 0.60, b = 0.20, a = 1.00 },
        blue        = { r = 0.40, g = 0.70, b = 1.00, a = 1.00 },
        disabled    = { r = 0.45, g = 0.45, b = 0.45, a = 1.00 },
        -- between fine and a warning (the chat bar's readouts)
        yellow      = { r = 1.00, g = 0.85, b = 0.30, a = 1.00 },
        -- the [ZacUI] name in chat messages (gold, like the titles)
        chat        = { r = 1.00, g = 0.82, b = 0.00, a = 1.00 },
        -- the money colours, so gold reads as gold whatever the theme
        coin        = { r = 1.00, g = 0.82, b = 0.20, a = 1.00 },
        silver      = { r = 0.78, g = 0.80, b = 0.84, a = 1.00 },
        copper      = { r = 0.85, g = 0.55, b = 0.30, a = 1.00 },
    },
    tooltip = {
        bg          = { r = 0.105, g = 0.105, b = 0.105, a = 0.95 },
        border      = { r = 0.00, g = 0.00, b = 0.00, a = 1.00 },
        title       = { r = 1.00, g = 0.82, b = 0.00, a = 1.00 },
        body        = { r = 0.90, g = 0.90, b = 0.90, a = 1.00 },
    },
    -- The map layer. `reveal` tints the parts of a zone you have not
    -- walked, and it lives here rather than in ZacUIDB.maps for the
    -- reason at the top of this file: one source of truth. Putting it
    -- here gets it the colour editor, the theme and profile export for
    -- free, none of which a private tint table would have had.
    map = {
        reveal      = { r = 0.55, g = 0.60, b = 0.85, a = 1.00 },
        -- the sea around and under the sharper map's tiles (Maps_HD)
        sea         = { r = 0.05, g = 0.10, b = 0.18, a = 1.00 },
    },
}

-- Category display order + labels for the colour editor. A literal list,
-- not pairs(): pairs() order is undefined and the editor would reshuffle
-- itself on every open.
local PALETTE_ORDER = {
    { key = "ui",        label = "Windows" },
    { key = "button",    label = "Buttons" },
    { key = "sidebar",   label = "Sidebar" },
    { key = "checkbox",  label = "Checkboxes" },
    { key = "dropdown",  label = "Dropdowns" },
    { key = "scrollbar", label = "Scroll bars" },
    { key = "text",      label = "Text" },
    { key = "tooltip",   label = "Tooltips" },
    { key = "map",       label = "Map" },
}

-- Key order within each category, same reasoning.
local PALETTE_KEYS = {
    ui        = { "windowBg", "elementBg", "cardBg", "headerBg", "headerGradient",
                  "border", "borderHover", "borderSelected", "accent", "text" },
    button    = { "bg", "hover", "pressed", "disabled",
                  "active", "activeHover", "xNormal", "xHover" },
    sidebar   = { "bg", "rowNormal", "rowHover", "rowSelected", "indicator" },
    checkbox  = { "bg", "border", "check", "hoverBorder" },
    dropdown  = { "bg", "itemHover", "itemText", "arrow", "selected" },
    scrollbar = { "track", "thumb" },
    text      = { "normal", "gray", "gold", "green", "red",
                  "orange", "yellow", "blue", "disabled", "coin", "silver", "copper", "chat" },
    tooltip   = { "bg", "border", "title", "body" },
    map       = { "reveal", "sea" },
}

-- Human labels, so the editor reads as English rather than as field names.
local KEY_LABELS = {
    windowBg = "Window background", elementBg = "Element background",
    cardBg = "Card background", headerBg = "Header background",
    headerGradient = "Header gradient (right end)",
    border = "Border", borderHover = "Border (hover)", borderSelected = "Border (selected)",
    accent = "Accent", text = "Text",
    bg = "Background", hover = "Hover", pressed = "Pressed",
    disabled = "Disabled", active = "Active", activeHover = "Active (hover)",
    xNormal = "Close X", xHover = "Close X (hover)",
    rowNormal = "Row", rowHover = "Row (hover)", rowSelected = "Row (selected)",
    indicator = "Selection bar", check = "Checkmark",
    hoverBorder = "Border (hover)", itemHover = "Item (hover)",
    itemText = "Item text", arrow = "Arrow", selected = "Selected",
    track = "Track", thumb = "Thumb",
    normal = "Normal", gray = "Muted", gold = "Gold", green = "Positive",
    red = "Negative", orange = "Warning", blue = "Link", title = "Title",
    yellow = "Caution", coin = "Gold coins", silver = "Silver coins", copper = "Copper coins",
    chat = "Chat messages",
    body = "Body", reveal = "Unexplored areas", sea = "Sea under the sharper map",
}

-- ============================================================
-- FLAT-NAME COMPATIBILITY
-- ============================================================
-- The whole skin layer speaks flat names. Rather than rewrite five
-- thousand call sites - and rather than keep a second palette in sync -
-- every flat name is an ALIAS onto a category pair. One table, two
-- vocabularies, no duplicated values.
local ALIAS = {
    windowBg  = { "ui", "windowBg" },
    elementBg = { "ui", "elementBg" },
    cardBg    = { "ui", "cardBg" },
    headerBg  = { "ui", "headerBg" },
    border    = { "ui", "border" },
    accent    = { "ui", "accent" },
    text      = { "ui", "text" },
    buttonBg  = { "button", "bg" },
    hoverBg   = { "button", "hover" },
    xNormal   = { "button", "xNormal" },
    xHover    = { "button", "xHover" },
    activeBg  = { "button", "active" },
    borderSelected = { "ui", "borderSelected" },
    textGreen = { "text", "green" },
}

local function Default(cat, key)
    local c = PALETTE[cat]
    return c and c[key]
end

-- The structured read. Falls back through the legacy flat override so a
-- 1.x DB keeps its saved colours without a migration step.
local function GetColor(cat, key)
    local db = ZacUIDB
    if db then
        local p = db.palette and db.palette[cat]
        if p and p[key] then return p[key] end
        -- the legacy flat table is {} on every current DB; only walk the
        -- alias list when it actually holds something
        if db.colors and next(db.colors) ~= nil then
            for flat, pair in pairs(ALIAS) do
                if pair[1] == cat and pair[2] == key and db.colors[flat] then
                    return db.colors[flat]
                end
            end
        end
    end
    return Default(cat, key) or PALETTE.text.normal
end

-- The flat read - the historic entry point. A PURE WRAPPER on purpose:
-- the earlier version checked the legacy store itself, which inverted the
-- documented precedence and let a DB carrying both stores hand different
-- colours to the skin layer (Col) and to ZacUI's own windows (GetColor).
-- GetColor owns the whole chain; this only translates the name.
local function Col(key)
    local pair = ALIAS[key]
    if pair then return GetColor(pair[1], pair[2]) end
    local o = ZacUIDB and ZacUIDB.colors and ZacUIDB.colors[key]
    return o or PALETTE.text.normal
end

-- SELF-HEALING colour read: every text path funnels through Col("text"),
-- so a dark saved swatch (or bad palette write) makes every lift and pin
-- faithfully repaint black TO black - the unifying explanation for
-- "still pitch black" surviving structurally correct fixes. ColSafe
-- guarantees a readable colour regardless of what is stored.
local function ColSafe(key, fr, fg, fb)
    local c = Col(key)
    if c and c.r and c.r < 0.35 and c.g < 0.35 and c.b < 0.35 then
        return { r = fr, g = fg, b = fb, a = 1 }
    end
    return c
end

local function SetColor(cat, key, r, g, b, a)
    if not Default(cat, key) then return end
    ZacUIDB.palette = ZacUIDB.palette or {}
    ZacUIDB.palette[cat] = ZacUIDB.palette[cat] or {}
    ZacUIDB.palette[cat][key] = { r = r, g = g, b = b,
                                  a = a or Default(cat, key).a or 1 }
    -- The legacy flat override would otherwise win the precedence race
    -- and silently swallow the new value.
    if ZacUIDB.colors then
        for flat, pair in pairs(ALIAS) do
            if pair[1] == cat and pair[2] == key then
                ZacUIDB.colors[flat] = nil
            end
        end
    end
end

local function ResetColor(cat, key)
    if ZacUIDB.palette and ZacUIDB.palette[cat] then
        ZacUIDB.palette[cat][key] = nil
    end
    if ZacUIDB.colors then
        for flat, pair in pairs(ALIAS) do
            if pair[1] == cat and pair[2] == key then
                ZacUIDB.colors[flat] = nil
            end
        end
    end
end

local function ResetAllColors()
    ZacUIDB.palette = {}
    ZacUIDB.colors = {}
end

local function Hex(c)
    return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function ColorLabel(key)
    return KEY_LABELS[key] or key
end

-- Live repainting lives in the config window (UI.Repaint walks the frame
-- tree and calls each widget's own _zPaint), so there is deliberately no
-- registry here. A registry would have to hold every widget ZacUI ever
-- built, forever, including the ones a rebuilt page has orphaned.

-- shared with later ZacUI files
ns.ALIAS = ALIAS
ns.Col = Col
ns.ColSafe = ColSafe
ns.ColorLabel = ColorLabel
ns.GetColor = GetColor
ns.Hex = Hex
ns.PALETTE = PALETTE
ns.PALETTE_KEYS = PALETTE_KEYS
ns.PALETTE_ORDER = PALETTE_ORDER
ns.ResetAllColors = ResetAllColors
ns.ResetColor = ResetColor
ns.SetColor = SetColor
