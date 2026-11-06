-- Config_Base - the config window's menu tree, its state, and the page
-- registry every page file writes into.
-- Part of ZacUI; load order is set by the TOC.
--
-- Pages are DATA, not code paths. A menu entry names a page; the page
-- registers itself under that name from whichever file it lives in. That
-- is what keeps Config_Window free of any knowledge about what a page
-- contains, and lets a page move between files without touching the nav.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local MODULE_GROUPS = ns.MODULE_GROUPS
local Print = ns.Print
local UI = ns.UI

-- ============================================================
-- MENU
-- ============================================================
-- Nine rows at the top level, grouped by what the thing on screen is,
-- the ones you visit most first (Screen, Combat, the class HUDs, Bags &
-- maps, Quality of life), then the settings about the settings
-- (Appearance, Modules, Profiles); a category opens to its first page
-- and remembers whether it is open.
-- Sub-features that used to be rows of their own (bar loadouts, plate
-- scripts, the button tray) are tabs on their parent page now; the
-- ALIASES table below keeps their old ids working for OpenConfig.
local MENU = {
    -- The category has its own id; the overview page keeps "general", the
    -- id every slash alias, saved selection and fallback already uses.
    { id = "general_group", label = "General", children = {
        { id = "general", label = "Overview", page = "General",
          keywords = "overview status version summary slash commands "
              .. "rescan identify inset line reset reload debug xray tools diagnostics "
              .. "voice tts text to speech speak volume rate" },
        { id = "changelog", label = "Changelog", page = "Changelog",
          keywords = "changelog changes what's new whats new news version versions "
              .. "update updates release notes history patch notes added fixed" },
        { id = "flavors", label = "Game versions", page = "Flavors",
          keywords = "game version versions flavor flavour classic era tbc burning crusade anniversary "
              .. "forever simulate simulation test testing as client what runs enabled disabled off" },
    } },

    -- (2026-10-28 tidy: what is on screen all the time here; the windows
    -- you open - bags, auction house, map - in their own group below)
    { id = "interface", label = "Screen", children = {
        { id = "bars", label = "Action bars", page = "Bars", addon = "Zacui_Bars",
          keywords = "action bar bars bartender buttons paging stance page fade "
              .. "mouseover scale padding rows keybind hotkey pet bar bag bar micro "
              .. "menu xp bar profile unlock move "
              .. "loadout loadouts myslot macros macro keybinds bindings keys "
              .. "slots spells import export string new character login auto "
              .. "apply class rule" },
        { id = "unitframes", label = "Unit frames", page = "UnitFrames", addon = "Zacui_UnitFrames",
          keywords = "unit frames unitframes player target pet party raid frames health power "
              .. "incoming heals healcomm zacuf castbar portrait group" },
        { id = "nameplates", label = "Nameplates", page = "Nameplates", addon = "Zacui_Nameplates",
          keywords = "nameplate nameplates plates plater threat aggro tank dps "
              .. "cast castbar interrupt aura debuff dot health bar enemy "
              .. "friendly target highlight fade stacking naowh "
              .. "script scripts mod mods hook lua wago trigger npc envtable editor code custom" },
        { id = "minimap", label = "Minimap", page = "Minimap",
          keywords = "minimap zone name clock calendar day date mail envelope "
              .. "tracking eye wheel zoom scale size hide show declutter "
              .. "button tray stash collect flyout icons clutter" },
        { id = "chat", label = "Chat", page = "Chat",
          keywords = "chat bar info data panel fps latency ms ping durability "
              .. "repair bags slots gold money clock time coordinates friends "
              .. "guild group raid whisper reply channel say party edit box "
              .. "typing input overlap copy fade opacity arrow history scroll "
              .. "tab tabs strip header general log" },
        { id = "tooltips", label = "Tooltips", page = "Tooltips",
          keywords = "tooltip tooltips mouseover anchor spot cursor follow hide combat raid "
              .. "shift border colour color health numbers spell id" },
        { id = "buffs", label = "Buffs", page = "Buffs",
          keywords = "buff buffs debuffs aura auras row per row consolidate consolidated "
              .. "wrap stride player buff frame" },
        { id = "lootroll", label = "Loot rolls", page = "LootRoll",
          keywords = "loot roll rolls need greed pass group loot dice coin item drop "
              .. "bars bar timer time left bind bop boe testroll elvui" },
    } },

    { id = "combat", label = "Combat", children = {
        { id = "raidmods", label = "Raid mods", page = "RaidMods", addon = "Zacui_RaidMods",
          keywords = "raid mods boss mod dbm bigwigs timers timer warning warnings "
              .. "alerts icons lists molten core bwl blackwing zul gurub zg aq40 ahn qiraj "
              .. "naxx naxxramas kel thuzad encounter pull break anchors test mode tts voice" },
        { id = "auras", label = "Aura engine", page = "Auras",
          keywords = "aura auras weakauras weak wa engine trigger triggers "
              .. "icon bar progress texture dynamic group condition custom lua "
              .. "wago import export pack embedded load on demand" },
        { id = "sbt", label = "Scrolling text", page = "SBT", addon = "Zacui_SBT",
          keywords = "scrolling battle text combat text sct damage numbers "
              .. "healing heals crit crits floating scroll area areas sticky "
              .. "alert alerts low health mana execute overpower revenge loot notification "
              .. "event events merge font fonts colour nameplate" },
        { id = "meter", label = "Damage meter", page = "Meter", addon = "Zacui_Meter",
          keywords = "damage meter details dps hps healing threat tinythreat "
              .. "tiny aggro segment overall report bars window parse combat "
              .. "log deaths interrupts dispels naowh" },
        { id = "clickcast", label = "Click casting", page = "ClickCast", addon = "Zacui_Clicks",
          keywords = "click casting clique click cast bindings binding mouse button "
              .. "hover hovercast mouseover heal heals healer unit frames raid frames "
              .. "shift ctrl alt modifier spell macro target menu keybind" },
        { id = "blessings", label = "Blessings", page = "Blessings", addon = "Zacui_Blessings",
          keywords = "blessings blessing pally power pallypower paladin paladins "
              .. "greater blessing kings might wisdom salvation light sanctuary "
              .. "aura auras assign assignments buff buffs symbol of kings" },
    } },

    -- "Class HUDs" is inserted here by Zacui_HUD when it loads.

    { id = "windows", label = "Bags & maps", children = {
        { id = "bags", label = "Bags", page = "Bags", addon = "Zacui_Bags",
          keywords = "bag bags inventory backpack bank columns slots search sort combined" },
        { id = "auction", label = "Auction house", page = "Auction", addon = "Zacui_Bags",
          keywords = "auction ah price prices sell selling cancel undercut "
              .. "shopping list scan memory market" },
        { id = "maps", label = "Maps", page = "Maps", addon = "Zacui_Maps",
          keywords = "map maps world map leatrix reveal unexplored fog explore "
              .. "flight point taxi zeppelin boat tram dungeon raid entrance "
              .. "spirit healer graveyard zone crossing border coordinates coords "
              .. "zoom scale opacity fade battlefield battleground minimap "
              .. "level range fishing arrow class icons" },
    } },

    { id = "qol", label = "Quality of life", page = "QoL", addon = "Zacui_QoL",
      keywords = "leatrix plus sell junk grey repair vendor merchant "
          .. "gossip skip loot faster autoloot invite whisper inv "
          .. "dismount mount mute sound sounds train chime fizzle "
          .. "screen glow effects automation raid performance fps "
          .. "particles particle density boss encounter linger "
          .. "buff remover cancelaura macros macro cleanup auto roll need greed pass" },

    -- (2026-11-02 polish: what draws on screen first, the settings about
    -- settings - look, modules, profiles - after it)
    { id = "appearance", label = "Appearance", children = {
        { id = "font",   label = "Fonts & Textures", page = "Font",
          keywords = "typeface size outline sharedmedia lsm texture statusbar status bar health power cast media global everywhere weakauras readycheck" },
        { id = "colors", label = "Colours", page = "Colors",
          keywords = "colour color palette accent gold theme swatch" },
        { id = "motion", label = "Motion", page = "Motion",
          keywords = "motion animation animations animate reduce reduced speed fast slow "
              .. "fade slide pop pulse bounce flash easing duration delay off" },
        { id = "movers", label = "Movers", page = "Movers",
          keywords = "move position drag anchor tooltip loot buffs minimap edit mode" },
    } },

    { id = "modules", label = "Modules", children = {
        { id = "mod_hud",     label = "HUD",     page = "Modules", group = "hud",
          keywords = "minimap chat tooltip buffs action bars unit frames cast "
              .. "tracker nameplates plates plater threat" },
        { id = "mod_windows", label = "Windows", page = "Modules", group = "windows",
          keywords = "character bags bank quest merchant mail trade loot guild pvp map" },
        { id = "mod_engine",  label = "Engine",  page = "Modules", group = "engine",
          keywords = "sweep watcher hooks fonts classifier" },
    } },

    { id = "profiles", label = "Profiles", children = {
        { id = "profiles_page", label = "Profiles", page = "Profiles",
          keywords = "profile profiles export import share backup save load "
              .. "copy string character alt preset" },
        { id = "import", label = "Import",  page = "Import",
          keywords = "import adopt readycheck match copy settings first run" },
    } },

}

-- Old page ids that are tabs on another page now: id -> { page id, tab }.
-- OpenConfig and a remembered selection go through this, so nothing that
-- linked to the old rows breaks.
local ALIASES = {
    loadouts  = { "bars", "loadouts" },
    npscripts = { "nameplates", "scripts" },
    tray      = { "minimap", "tray" },
    profiles  = { "profiles_page" },
    tools     = { "general" },
}

-- ============================================================
-- PAGE REGISTRY
-- ============================================================
local Pages = {}
local function RegisterPage(name, fn)
    Pages[name] = fn
end

-- ============================================================
-- STATE
-- ============================================================
-- Lives in the DB so the window reopens where you left it. A settings
-- window that always reopens on page one is a small papercut you feel
-- every single time.
local function State()
    ZacUIDB.config = ZacUIDB.config or {}
    local s = ZacUIDB.config
    s.expanded = s.expanded or {}
    s.selected = s.selected or "general"
    return s
end

-- Flatten the tree into the rows the sidebar actually draws, honouring
-- which categories are open. Rebuilt on every nav change - cheap, and it
-- means expansion state can never disagree with what is on screen.
local function Tokens(text)
    local out = {}
    for w in (text or ""):lower():gmatch("%S+") do out[#out + 1] = w end
    return out
end

-- hits: optional set of item ids the settings search found something on,
-- so a page shows up for "particle" even though only one checkbox on it
-- says so.
local function VisibleRows(filter, hits)
    local rows = {}
    filter = filter and filter:lower()
    if filter and not filter:find("%S") then filter = nil end
    local tokens = Tokens(filter)

    local function Matches(item, parent)
        if not filter then return true end
        local hay = (item.label .. " " .. (item.keywords or "")):lower()
        if parent then hay = hay .. " " .. parent.label:lower() end
        -- Module names are searchable too, so typing "sunder" or
        -- "auctionator" lands on the page that owns it.
        if item.group then
            for _, g in ipairs(MODULE_GROUPS) do
                if g.key == item.group then
                    for _, m in ipairs(g.modules) do
                        hay = hay .. " " .. m.label:lower() .. " " .. m.key
                    end
                end
            end
        end
        if hits and hits[item.id] then return true end
        -- Every word somewhere, in any order: "boss particle" finds
        -- "Boss particles", and so does "particle boss".
        for _, w in ipairs(tokens) do
            if not hay:find(w, 1, true) then return false end
        end
        return true
    end

    local s = State()
    for _, item in ipairs(MENU) do
        if item.children then
            local kept = {}
            for _, child in ipairs(item.children) do
                if Matches(child, item) then kept[#kept + 1] = child end
            end
            local selfMatch = Matches(item)
            if selfMatch or #kept > 0 then
                rows[#rows + 1] = { item = item, isCategory = true }
                -- A search always opens what it found; without this the
                -- results are hidden inside a collapsed category.
                local open = filter and true or s.expanded[item.id]
                if open then
                    local list = (filter and #kept > 0) and kept or item.children
                    for _, child in ipairs(list) do
                        rows[#rows + 1] = { item = child, isChild = true }
                    end
                end
            end
        elseif Matches(item) then
            rows[#rows + 1] = { item = item }
        end
    end
    return rows
end

local function FindItem(id)
    local alias = ALIASES[id]
    if alias then id = alias[1] end
    for _, item in ipairs(MENU) do
        if item.id == id then return item end
        for _, child in ipairs(item.children or {}) do
            if child.id == id then return child, item end
        end
    end
end

-- Words people type that are not on a page, added to its menu entry
-- (a row at the top level or under a category). A part appends to the
-- entry Config_Base owns when it loads; only words the entry does not
-- already carry are added, so loading twice or two parts naming the same
-- word never doubles anything. Returns true when the entry exists.
--   ns.AddMenuKeywords("bars", "skin border backdrop")
local function AddMenuKeywords(id, words)
    if type(id) ~= "string" or type(words) ~= "string" then return false end
    local item
    for _, top in ipairs(MENU) do
        if top.id == id then item = top break end
        for _, child in ipairs(top.children or {}) do
            if child.id == id then item = child break end
        end
        if item then break end
    end
    if not item then return false end
    local have = {}
    for w in (item.keywords or ""):lower():gmatch("%S+") do have[w] = true end
    local add = {}
    for w in words:gmatch("%S+") do
        local lw = w:lower()
        if not have[lw] then
            have[lw] = true
            add[#add + 1] = w
        end
    end
    if #add > 0 then
        item.keywords = ((item.keywords and item.keywords ~= "") and (item.keywords .. " ") or "")
            .. table.concat(add, " ")
    end
    return true
end

-- ============================================================
-- LAYOUT HELPERS
-- ============================================================
-- Every page walks down a single running y. These wrap the arithmetic so
-- pages read as content rather than as coordinates.
local Layout = {}
Layout.__index = Layout

function Layout.New(parent, y)
    return setmetatable({ parent = parent, y = y or -14, cards = {}, tabRanges = {} }, Layout)
end

function Layout:Header(title, subtitle)
    local f
    f, self.y = UI.PageHeader(self.parent, title, subtitle, self.y)
    -- Remembered for the search index, which skips the page's own title.
    self.headerFrame = f
    -- a feature on this page that this game version does not run says so
    -- under the title (Core_Flavor; nothing on the client's own game
    -- unless that feature is off there)
    local notes = self.flavorNotes
    if notes then
        self.flavorNotes = nil
        for _, text in ipairs(notes) do self:Notice("flavor", text) end
    end
    return f
end

function Layout:Card(title)
    local card = UI.Card(self.parent, title, self.y)
    self.cards[#self.cards + 1] = card
    card._y = UI.M.CONTENT_Y - (card._zTitleExtra or 0)
    card._zTopY = card._y
    self.current = card
    return card
end

-- A card's "?" (top right): hovering it shows the card's longer notes.
-- Its tooltip is indexed by the search like any label on the page.
-- (the button itself; pooled on a live page, see UIF_Pool)
local function NewCardHelp(card)
    local b = CreateFrame("Button", nil, card)
    b:SetSize(16, 16)
    local q = UI.Font(b, UI.F.SMALL, { text = "?", cat = "text", key = "gray", justify = "CENTER" })
    q:SetPoint("CENTER", 0, 0)
    b:HookScript("OnEnter", function() local c = ns.GetColor("text", "gold") q:SetTextColor(c.r, c.g, c.b, 1) end)
    b:HookScript("OnLeave", function() if q._zPaint then q:_zPaint() end end)
    b._zPaint = function() if q._zPaint then q:_zPaint() end end
    return b
end

local function CardHelp(card, text)
    if card._zHelp then return card._zHelp end
    local b = ns.UIPool and ns.UIPool.Make("CardHelp", NewCardHelp, card) or NewCardHelp(card)
    b:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -7)
    local title = card._zTitle and card._zTitle:GetText() or "About this"
    UI.Tooltip(b, title, text)
    b._zCardHelp = true
    card._zHelp = b
    -- the title keeps clear of it
    local t = card._zTitle
    if t then
        local room = (UI.Room(card, UI.M.CARD_PAD) or 300) - 22
        if room > 60 and (t:GetStringWidth() or 0) > room + 0.5 then
            -- one line's height (the title may already be wrapped)
            local lines = (t.GetNumLines and t:GetNumLines()) or 1
            if type(lines) ~= "number" or lines < 1 then lines = 1 end
            local one = (t:GetStringHeight() or UI.F.CARD) / lines
            local before = card._zTitleExtra or 0
            t:SetWidth(room)
            t:SetJustifyH("LEFT")
            t:SetWordWrap(true)
            card._zTitleExtra = math.max(0, math.ceil((t:GetStringHeight() or one) - one))
            card._y = card._y - (card._zTitleExtra - before)
        end
    end
    return b
end

-- Close the open card, advancing the page cursor past it.
function Layout:EndCard()
    local card = self.current
    if not card then return end
    card:SetContentHeight(-card._y)
    self.y = self.y - card:GetHeight() - UI.M.CARD_GAP
    self.current = nil
end

-- A widget wider than the room left of the card's right edge is fitted
-- to it (its _zFit: sliders, dropdowns and edit boxes narrow, a checkbox
-- wraps its label, a picker re-lays its columns); what the fit added in
-- height (_zExtraH) is added to the row.
local function CardWidth(card)
    local w = card and card.GetWidth and card:GetWidth()
    if type(w) == "number" and w >= 200 then return w end
    local page = card and card.GetParent and card:GetParent()
    local pw = page and page.GetWidth and page:GetWidth()
    if type(pw) == "number" and pw >= 200 + 2 * UI.M.MARGIN then return pw - 2 * UI.M.MARGIN end
    return 420
end

function Layout:Row(widget, height, indent)
    local card = self.current
    local x = indent or UI.M.CONTROL_X
    widget:SetPoint("TOPLEFT", card, "TOPLEFT", x, card._y)
    local room = CardWidth(card) - x - UI.M.CONTROL_X
    if widget._zFit and (widget:GetWidth() or 0) > room + 0.5 then widget:_zFit(room)
    elseif not widget._zFit and widget.GetObjectType and widget:GetObjectType() == "FontString"
        and not widget._zExtraH and (widget:GetStringWidth() or 0) > room + 0.5 then
        -- a line of text wider than the card wraps, and the row grows
        local one = widget:GetStringHeight() or 12
        widget:SetWidth(room)
        widget:SetJustifyH("LEFT")
        widget:SetWordWrap(true)
        widget._zExtraH = math.max(0, math.ceil((widget:GetStringHeight() or one) - one))
    end
    local rowH = (height or UI.M.ROW) + (widget._zExtraH or 0)
    card._y = card._y - rowH
    -- How much room the row leaves under what it draws: a label centred
    -- on a control (a checkbox's) reaches past the control when the font
    -- is bigger than it. A description that follows tucks up into that
    -- room, never into the row (see Desc).
    local wh = (widget.GetHeight and widget:GetHeight()) or 0
    local vis = wh
    if widget.GetRegions and not (widget.GetObjectType and widget:GetObjectType() == "FontString") then
        for _, r in ipairs({ widget:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and r:IsShown() then
                local t = r.GetText and r:GetText()
                if t and t ~= "" and r.GetStringHeight then
                    local lh = r:GetStringHeight() or 0
                    vis = math.max(vis, (wh + lh) / 2)
                end
            end
        end
    end
    card._zSlack, card._zSlackY = rowH - vis, card._y
    card._zLastRow = widget
    return widget
end

-- The control a description written under it can hang its long text on
-- as a tooltip: the checkbox or button itself, a slider's track, a
-- labelled field's control.
local function TipTarget(w)
    if not w then return nil end
    local k = w.GetObjectType and w:GetObjectType()
    if k == "Button" or k == "CheckButton" then return w end
    if w.slider then return w.slider end
    if w.control and w.control.HookScript then return w.control end
    if w.dropdown and w.dropdown.HookScript then return w.dropdown end
    if w.editBox and w.editBox.HookScript then return w.editBox end
    -- a row of buttons: the first of them
    if w.GetChildren then
        for _, k in ipairs({ w:GetChildren() }) do
            local kk = k.GetObjectType and k:GetObjectType()
            if (kk == "Button" or kk == "CheckButton") and k:IsShown() then return k end
        end
    end
    return nil
end

local function LabelOf(w)
    local fs = w and (w._zText or w.label or (w.title))
    local t = fs and fs.GetText and fs:GetText()
    if type(t) == "string" and t ~= "" then return t end
    return nil
end

-- A row as tall as the widget says it is, plus `gap` - for the pickers
-- (UIF_Pickers) and anything else that knows its own height.
function Layout:Add(widget, gap, indent)
    local room = CardWidth(self.current) - (indent or UI.M.CONTROL_X) - UI.M.CONTROL_X
    if widget._zFit and (widget:GetWidth() or 0) > room + 0.5 then widget:_zFit(room) end
    -- (the fitted height is in GetHeight already; Row must not add it twice)
    return self:Row(widget, (widget:GetHeight() or UI.M.ROW) - (widget._zExtraH or 0) + (gap or 8), indent)
end

-- The room a row has in the open card, from x (default the control inset).
function Layout:Room(indent)
    return CardWidth(self.current) - (indent or UI.M.CONTROL_X) - UI.M.CONTROL_X
end

-- A row of widgets (buttons, mostly) that wraps onto a new line instead of
-- running past the card's right edge.
function Layout:Flow(widgets, gap, rowGap, indent)
    local card = self.current
    local x = indent or UI.M.CONTROL_X
    local h = UI.Flow(card, widgets, x, card._y, self:Room(indent), gap or 8, rowGap or 6)
    card._y = card._y - h - (rowGap or 6)
    -- a description written under the row can hang its long text on the
    -- row's first button (see Desc)
    card._zLastRow, card._zSlack, card._zSlackY = widgets[1], rowGap or 6, card._y
end

-- A grid of widgets (checkboxes, mostly), at most `cols` across: as many
-- columns as the widest one fits in, down to one; a label still too wide
-- for its cell wraps inside it (_zFit). Rows are as tall as their tallest.
function Layout:Grid(widgets, cols, rowH, indent)
    local card = self.current
    local x0 = indent or UI.M.CONTROL_X
    local room = self:Room(indent)
    local GAP = 12
    local widest = 0
    for _, w in ipairs(widgets) do widest = math.max(widest, w:GetWidth() or 0) end
    cols = math.max(1, math.min(cols or 2, #widgets))
    while cols > 1 and (room - GAP * (cols - 1)) / cols < widest do cols = cols - 1 end
    local cell = math.floor((room - GAP * (cols - 1)) / cols)
    rowH = rowH or UI.M.ROW
    local y = card._y
    local i = 1
    while i <= #widgets do
        local tall = 0
        for c = 0, cols - 1 do
            local w = widgets[i + c]
            if not w then break end
            if w._zFit and (w:GetWidth() or 0) > cell + 0.5 then w:_zFit(cell) end
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", card, "TOPLEFT", x0 + c * (cell + GAP), y)
            tall = math.max(tall, w:GetHeight() or 0)
        end
        y = y - math.max(rowH, tall + (rowH - UI.M.CHECK))
        i = i + cols
    end
    card._y = y
end

-- Options that only matter while a parent option is on: indented under
-- it in a tidy grid (cols across, fewer when narrow) and dimmed while the
-- parent is off (the parent's toggle rebuilds the page, which re-dims).
UI.M.CHILD_INDENT = UI.M.CHILD_INDENT or 20
function Layout:Dependent(widgets, parentOn, cols, rowH)
    self:Grid(widgets, cols or 2, rowH, UI.M.CONTROL_X + UI.M.CHILD_INDENT)
    for _, w in ipairs(widgets) do
        if UI.SetEnabled then UI.SetEnabled(w, parentOn and true or false) end
    end
    return widgets
end

-- A label and its value on one line (the value in a column at keyW), the
-- value wrapping within the card; when the column would be too narrow the
-- value goes under the label instead. Returns the two strings.
function Layout:Pair(key, value, keyW, opts)
    opts = opts or {}
    local card = self.current
    local x = opts.indent or UI.M.CONTROL_X
    local room = self:Room(opts.indent)
    local size = opts.size or UI.F.LABEL
    local k = UI.Font(card, size, { text = key, cat = "text", key = opts.keyColor or "gray" })
    k:SetPoint("TOPLEFT", card, "TOPLEFT", x, card._y)
    local kw = math.ceil(k:GetStringWidth() or 0)
    local below = room - keyW < 140 or kw > keyW - 6
    local vx = below and (x + 12) or (x + keyW)
    local v = UI.Font(card, size, { text = value, cat = "text", key = opts.valueColor or "normal",
        width = room - (vx - x) })
    if below then
        if kw > room then k:SetWidth(room) k:SetJustifyH("LEFT") k:SetWordWrap(true) end
        local kh = math.max(size, k:GetStringHeight() or size)
        v:SetPoint("TOPLEFT", card, "TOPLEFT", vx, card._y - kh - 2)
        card._y = card._y - kh - 2 - math.max(size, v:GetStringHeight() or size) - (opts.gap or 5)
    else
        v:SetPoint("TOPLEFT", card, "TOPLEFT", vx, card._y)
        card._y = card._y - math.max(size, k:GetStringHeight() or size, v:GetStringHeight() or size) - (opts.gap or 5)
    end
    return k, v
end

-- A label and a control on one row: the control in a column at labelW
-- (fitted to what is left of the card), or under the label when that
-- column would leave the control less than minW. Returns the label.
function Layout:Labeled(label, control, labelW, opts)
    opts = opts or {}
    local card = self.current
    local x = opts.indent or UI.M.CONTROL_X
    local room = self:Room(opts.indent)
    local fs = UI.Font(card, opts.size or UI.F.LABEL, { text = label, cat = "text", key = opts.color or "normal" })
    local lw = math.ceil(fs:GetStringWidth() or 0)
    local ch = control:GetHeight() or UI.M.DROPDOWN_H
    labelW = math.max(labelW or 0, 0)
    local minW = opts.minW or 120
    if lw + 8 <= labelW and room - labelW >= minW then
        fs:SetPoint("LEFT", card, "TOPLEFT", x, card._y - ch / 2)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", card, "TOPLEFT", x + labelW, card._y)
        local cr = room - labelW
        if (control:GetWidth() or 0) > cr + 0.5 then
            if control._zFit then control:_zFit(cr) else control:SetWidth(cr) end
        end
        card._y = card._y - math.max(ch, control:GetHeight() or ch) - (opts.gap or 6)
    else
        if lw > room then fs:SetWidth(room) fs:SetJustifyH("LEFT") fs:SetWordWrap(true) end
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, card._y)
        card._y = card._y - math.max(12, fs:GetStringHeight() or 12) - 4
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", card, "TOPLEFT", x, card._y)
        if (control:GetWidth() or 0) > room + 0.5 then
            if control._zFit then control:_zFit(room) else control:SetWidth(room) end
        end
        card._y = card._y - (control:GetHeight() or ch) - (opts.gap or 6)
    end
    return fs
end

-- (CardWidth, above: a card is anchored to both sides of its parent, so
-- its width is derived rather than set. Before the rect resolves GetWidth
-- returns 0 - which is TRUTHY, so an `or 400` fallback never fires; the
-- number is tested, and the page's own width stands in.)

function Layout:Desc(text)
    local card = self.current
    local fs = UI.Font(card, UI.F.DESC, {
        text = text, cat = "text", key = "gray",
        width = math.max(120, CardWidth(card) - UI.M.DESC_X - 16),
    })
    -- SHORT HELP, THE REST ON HOVER. A description longer than about a
    -- line, written under a control, keeps its first sentence on the page
    -- and the whole of it moves into that control's tooltip (the search
    -- finds tooltip text, so nothing goes missing).
    local lineH = (fs.GetLineHeight and fs:GetLineHeight()) or UI.F.DESC or 11
    if type(lineH) ~= "number" or lineH <= 0 then lineH = 11 end
    local row = (card._zSlackY == card._y) and card._zLastRow or nil
    local target = TipTarget(row)
    local long = (fs:GetStringHeight() or 0) > lineH * 1.6
    local first = long and text:match("^(.-[%.!?])%s+%S")
    if first and (#first < 12 or #first >= #text) then first = nil end
    if first and target and not target._zTipBody then
        UI.Tooltip(target, LabelOf(row) or "", text)
        fs:SetText(first)
    elseif first and card._y == card._zTopY and not card._zHelp then
        -- a card's opening paragraph: its first sentence stays, the whole
        -- of it is on the card's "?"
        CardHelp(card, text)
        fs:ClearAllPoints()
        fs:SetText(first)
    end
    -- tucked up under the row above (3 px), but never into what it drew
    local lift = 3
    if card._zSlack and card._zSlackY == card._y then lift = math.min(3, card._zSlack) end
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", UI.M.DESC_X, card._y + lift)
    card._y = card._y - math.max(12, fs:GetStringHeight()) - 6 + (lift - 3)
    card._zSlack = nil
    return fs
end

-- One shape for every "this page cannot do much right now" message, so
-- the pages stop hand-rolling them. kind is "missing" (the part or
-- engine did not load - red), "off" (the module is switched off - gold)
-- or "warn" (anything else - orange). `where` names the switch for an
-- "off" notice ("Modules > HUD").
local NOTICE = {
    missing = { title = "Not loaded",    key = "red" },
    off     = { title = "Module is off", key = "gold" },
    warn    = { title = "Heads up",      key = "orange" },
    -- a part or feature this game version does not run (Core_Flavor)
    flavor  = { title = "Game version",  key = "orange" },
}
-- moduleKey (an "off" notice): a "Turn it on" button right there, so
-- every module page that is off reads the same and needs one click -
-- not a trip to Modules (2026-10-28 settings tidy).
function Layout:Notice(kind, text, where, moduleKey)
    local n = NOTICE[kind] or NOTICE.warn
    if kind == "off" and where and not moduleKey then
        text = text .. " Turn it on under " .. where .. "."
    end
    local card = self:Card(n.title)
    local fs = UI.Font(card, UI.F.DESC, {
        text = text, cat = "text", key = n.key,
        width = math.max(120, CardWidth(card) - UI.M.DESC_X - 16),
    })
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", UI.M.DESC_X, card._y + 3)
    card._y = card._y - math.max(12, fs:GetStringHeight()) - 6
    if kind == "off" and moduleKey and UI.Button then
        local b = UI.Button(card, "Turn it on", { width = 110, onClick = function()
            if ns.EnableModuleLive then ns.EnableModuleLive(moduleKey)
            elseif ZacUIDB and ZacUIDB.modules then ZacUIDB.modules[moduleKey] = true end
            if ns.RefreshConfig then ns.RefreshConfig() end
        end })
        self:Row(b, (UI.M.BUTTON_H or 20) + 4)
    end
    self:EndCard()
    return card
end

function Layout:Gap(n)
    if self.current then
        self.current._y = self.current._y - (n or 6)
    else
        self.y = self.y - (n or 6)
    end
end

function Layout:Height()
    return -self.y + 20
end

-- ============================================================
-- TABS - a row of buttons that splits a long page into sections, one
-- shown at a time. `tabs` is { { id, label, build = function(L) }, ... }
-- in display order. The chosen tab is remembered per page in the config
-- state (so a rebuild - every toggle rebuilds - lands on the same tab),
-- and switching tabs scrolls to the top, because a tab IS a navigation
-- even though the page id did not change. Cards written before the tab
-- row (the "module is off" notices) stay above it on every tab.
-- ============================================================
-- The row's frame and its rule (pooled on a live page, see UIF_Pool).
local function NewTabBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    local rule = bar:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(ns.FLAT)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, -4)
    rule:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -4)
    bar._zRule = rule
    return bar
end

function Layout:Tabs(tabs)
    local s = State()
    s.tabs = s.tabs or {}
    local pageId = self.pageId or "?"
    local current = s.tabs[pageId]
    local active
    for _, t in ipairs(tabs) do
        if t.id == current then active = t end
    end
    if not active then
        active = tabs[1]
        s.tabs[pageId] = active and active.id
    end

    -- ONE TAB IS NO TAB BAR: a lone button reads as a control that does
    -- nothing. Its settings go straight on the page.
    if #tabs == 1 and not self.indexAll then
        self.tabBar, self.tabList = nil, tabs
        local t = tabs[1]
        local from = select("#", self.parent:GetChildren()) + 1
        if t.build then t.build(self) end
        self.tabRanges[#self.tabRanges + 1] = { id = t.id, from = from,
            to = select("#", self.parent:GetChildren()) }
        return
    end

    local bar = ns.UIPool and ns.UIPool.Make("TabBar", NewTabBar, self.parent) or NewTabBar(self.parent)
    bar:SetPoint("TOPLEFT", self.parent, "TOPLEFT", UI.M.MARGIN, self.y)
    bar:SetPoint("RIGHT", self.parent, "RIGHT", -UI.M.MARGIN, 0)
    bar:SetHeight(UI.M.BUTTON_H)
    -- THE ROW FITS THE PAGE. Every button is as wide as its label (measured,
    -- in the font it is drawn in) and never narrower, so no label is ever
    -- cut short; buttons that do not fit on a line go to the next one. The
    -- row count is fixed at build (the cards below are placed from it); a
    -- resize rebuilds the page, and until then only re-flows the buttons.
    local GAP, MIN_W = 4, 56
    local buttons, natural = {}, {}
    for i, t in ipairs(tabs) do
        local b = UI.Button(bar, t.label, { width = MIN_W, tab = true,
            onClick = function()
                if s.tabs[pageId] == t.id then return end
                s.tabs[pageId] = t.id
                if ns.ConfigScrollTop then ns.ConfigScrollTop() end
                if ns.RefreshConfig then ns.RefreshConfig() end
            end })
        -- the tab look (UI.Button opts.tab): open = lifted, white label,
        -- gold line along its foot; no green anywhere
        b:SetActive(t == active)
        if b._zText then
            b._zText:ClearAllPoints()
            b._zText:SetPoint("CENTER", 0, 0)
            b._zText:SetJustifyH("CENTER")
            b._zText:SetWordWrap(false)
        end
        local tw = b._zText and math.ceil(b._zText:GetStringWidth() or 0) or (#t.label * 7)
        natural[i] = math.max(MIN_W, tw + 24)
        b:SetWidth(natural[i])
        buttons[i] = b
    end
    local function Avail()
        local w = bar:GetWidth()
        if not w or w < 200 then
            w = (self.parent:GetWidth() or 0) - 2 * UI.M.MARGIN
        end
        if not w or w < 200 then w = 420 end
        return w
    end
    local function Place(width)
        local n = #buttons
        if n == 0 then return 1 end
        local x, r = 0, 1
        for i = 1, n do
            local b, w = buttons[i], natural[i]
            if x > 0 and x + w > width + 0.5 then x, r = 0, r + 1 end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -(r - 1) * (UI.M.BUTTON_H + GAP))
            x = x + w + GAP
        end
        return r
    end
    local rows = Place(Avail())
    bar:SetHeight(rows * UI.M.BUTTON_H + (rows - 1) * GAP)
    bar:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then Place(w) end
    end)
    -- a rule under the row, so the tabs read as a header for what follows
    local rule = bar._zRule
    local a = ns.GetColor and ns.GetColor("ui", "border")
    if a then rule:SetVertexColor(a.r, a.g, a.b, 1) end

    self.y = self.y - bar:GetHeight() - 12
    self.tabBar, self.tabList = bar, tabs

    -- Each tab's frames are the run of children it added to the page, so
    -- the search index can tell which tab a setting lives on (and switch
    -- to it before scrolling there).
    local function BuildTab(t)
        local from = select("#", self.parent:GetChildren()) + 1
        if t.build then t.build(self) end
        self.tabRanges[#self.tabRanges + 1] = { id = t.id, from = from,
            to = select("#", self.parent:GetChildren()) }
    end
    if self.indexAll then
        -- Indexing builds EVERY tab, each from the same starting height
        -- (they are never shown, only measured), and a tab that fails to
        -- build costs only its own entries.
        local startY = self.y
        for _, t in ipairs(tabs) do
            self.y, self.current = startY, nil
            pcall(BuildTab, t)
        end
    elseif active then
        BuildTab(active)
    end
end

-- ============================================================
-- AUDIT
-- ============================================================
-- MODULE_ORDER and MODULE_GROUPS are maintained by hand in two places on
-- purpose (order is a runtime concern, grouping is a presentation one).
-- This catches the inevitable moment they drift, at login, in chat -
-- rather than as a module that silently has no checkbox.
local function AuditModules()
    local grouped = {}
    for _, g in ipairs(MODULE_GROUPS) do
        for _, m in ipairs(g.modules) do grouped[m.key] = true end
    end
    local missing = {}
    for _, key in ipairs(ns.MODULE_ORDER) do
        if not grouped[key] then missing[#missing + 1] = key end
    end
    if #missing > 0 then
        Print("|cFFFF6666config:|r no sidebar home for: "
            .. table.concat(missing, ", ") .. " (add them to MODULE_GROUPS)")
    end
end

-- shared with later ZacUI files
ns.AddMenuKeywords = AddMenuKeywords
ns.AuditModules = AuditModules
ns.CardWidth = CardWidth
ns.ConfigLayout = Layout
ns.ConfigMenu = MENU
ns.ConfigPages = Pages
ns.ConfigState = State
ns.FindMenuItem = FindItem
ns.ConfigAliases = ALIASES
ns.RegisterPage = RegisterPage
ns.VisibleRows = VisibleRows
ns.ConfigTokens = Tokens
