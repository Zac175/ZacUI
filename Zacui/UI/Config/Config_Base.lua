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
              .. "voice tts text to speech speak volume rate "
              .. "update updates newer outdated out of date old curseforge notice" },
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
        { id = "style",  label = "Style", page = "Style",
          keywords = "look looks style styles classic vanilla blizzard forever bronze gold zacui flat "
              .. "skin theme art icon zoom crop per part apply" },
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

    -- a part or feature this game version does not run has no page there
    -- (Core_Flavor; General > Game versions lists it)
    local function Off(item)
        return ns.FeatureOffForPage and ns.FeatureOffForPage(item.id) and true or false
    end

    local s = State()
    for _, item in ipairs(MENU) do
        if Off(item) then
            -- (nothing: not listed, not searched)
        elseif item.children then
            local kept, here = {}, {}
            for _, child in ipairs(item.children) do
                if not Off(child) then
                    here[#here + 1] = child
                    if Matches(child, item) then kept[#kept + 1] = child end
                end
            end
            local selfMatch = Matches(item)
            if selfMatch or #kept > 0 then
                rows[#rows + 1] = { item = item, isCategory = true }
                -- A search always opens what it found; without this the
                -- results are hidden inside a collapsed category.
                local open = filter and true or s.expanded[item.id]
                if open then
                    local list = (filter and #kept > 0) and kept or here
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

-- THE SETTINGS WINDOW'S ROWS (match pass 2026-11-07, UI.S). A layout made
-- while UI._zSettings is on (the /zui window's builds) lays EllesmereUI's
-- page: every row is a band the card's width, 36 tall for a checkbox and
-- 50 for a control, black at 0.10 / 0.20 by turns (restarting each card),
-- its control centred in it 20 in. Two controls that each fit half a row
-- (a checkbox, a slider, a labelled dropdown, a colour) share one row, the
-- second at the half, as their two-up rows. A layout made anywhere else
-- (Meter_RaidSummary's window) works as before.
local SET = UI.S

local function BandH(wh)
    if wh <= 22 then return SET.ROW end
    return math.max(SET.ROW_CTL, math.ceil(wh) + 20)
end

-- a band of the open card: y (its top, card units) and h
local function AddBand(card, y, h)
    card._zBands = card._zBands or {}
    local b = { y = y, h = h }
    card._zBands[#card._zBands + 1] = b
    return b
end

-- the bands, drawn when the card closes: one small frame each (pooled on
-- a live page, see UIF_Pool), so a rebuild makes nothing new
local function NewBand(card)
    local f = CreateFrame("Frame", nil, card)
    local t = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    t._zui_own = true
    t:SetTexture(ns.FLAT)
    t:SetAllPoints(f)
    f._zBandTex = t
    f:EnableMouse(false)
    return f
end
local function PaintBands(card)
    for i, b in ipairs(card._zBands or {}) do
        local f = ns.UIPool and ns.UIPool.Make("RowBand", NewBand, card) or NewBand(card)
        f:SetFrameLevel(math.max(0, card:GetFrameLevel()))
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", card, "TOPLEFT", 0, b.y)
        f:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, b.y)
        f:SetHeight(b.h)
        f._zBandTex:SetVertexColor(0, 0, 0, (i % 2 == 0) and SET.ROW_EVEN or SET.ROW_ODD)
        f:Show()
    end
end

function Layout.New(parent, y)
    local set = UI._zSettings or nil
    return setmetatable({ parent = parent, y = y or (set and 0 or -14), cards = {}, tabRanges = {}, set = set }, Layout)
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
    -- a part wearing a look other than ZacUI's says so first, with the
    -- way to the Style page (Config_Style)
    if self.live and ns.LookBanner then pcall(ns.LookBanner, self) end
    return f
end

function Layout:Card(title)
    local card = UI.Card(self.parent, title, self.y)
    self.cards[#self.cards + 1] = card
    if self.set then
        card._zBands, card._zPair = {}, nil
        card._y = -(title and SET.SECTION or 0) - (card._zTitleExtra or 0)
        card._zTopY = card._y
        self.current = card
        return card
    end
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
    b:ClearAllPoints()
    if rawget(card, "_zSet") then
        b:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", -2, -SET.SECTION + 4)
    else
        b:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -7)
    end
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
    if self.set then
        PaintBands(card)
        card._zPair = nil
        self.y = self.y - card:GetHeight() - SET.CARD_GAP
        self.current = nil
        return
    end
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
    local m = (card and rawget(card, "_zSet")) and SET.PAD or UI.M.MARGIN
    if type(pw) == "number" and pw >= 200 + 2 * m then return pw - 2 * m end
    return 420
end

-- A row in the settings window: fitted, centred in its band, or put in
-- the free half of the row above (see the top of this section).
local function SetRow(self, widget, height, indent)
    local card = self.current
    local cw = CardWidth(card)
    local x = indent or SET.SIDE
    local room = cw - x - SET.SIDE
    local half = math.floor(cw / 2)
    local halfRoom = half - 2 * SET.SIDE
    -- a slider placed by the layout: half a row wide (EllesmereUI's row)
    if rawget(widget, "_zSet") and widget.slider and widget._zFit
        and (widget:GetWidth() or 0) < math.min(SET.SLIDER_W, room) - 0.5 then
        widget:_zFit(math.min(SET.SLIDER_W, room))
    end
    if widget._zFit and (widget:GetWidth() or 0) > room + 0.5 then widget:_zFit(room)
    elseif not widget._zFit and widget.GetObjectType and widget:GetObjectType() == "FontString"
        and not widget._zExtraH and (widget:GetStringWidth() or 0) > room + 0.5 then
        local one = widget:GetStringHeight() or 12
        widget:SetWidth(room)
        widget:SetJustifyH("LEFT")
        widget:SetWordWrap(true)
        widget._zExtraH = math.max(0, math.ceil((widget:GetStringHeight() or one) - one))
    end
    local ww = widget:GetWidth() or 0
    local wh = widget:GetHeight() or 0
    if widget.GetObjectType and widget:GetObjectType() == "FontString" then wh = math.max(wh, widget:GetStringHeight() or 0) end
    local halfable = widget._zHalf and not indent and ww <= halfRoom + 0.5 and wh <= 34
    local open = card._zPair
    widget:ClearAllPoints()
    -- (and only when the page made nothing else on the card since the row
    -- above: a page that hangs its own parts on that row by hand keeps
    -- its rows one under the other)
    local nk, nr = select("#", card:GetChildren()), select("#", card:GetRegions())
    if halfable and open and open.y == card._y and nk == open.nk + 1 and nr == open.nr then
        -- the second half of the row above
        local b = open.b
        local need = BandH(wh)
        if need > b.h then
            card._y = card._y - (need - b.h)
            b.h = need
            local fw = open.w
            fw:ClearAllPoints()
            fw:SetPoint("TOPLEFT", card, "TOPLEFT", open.x, b.y - math.floor((b.h - open.wh) / 2))
        end
        widget:SetPoint("TOPLEFT", card, "TOPLEFT", half + SET.SIDE, b.y - math.floor((b.h - wh) / 2))
        card._zPair = nil
        card._zSlack, card._zSlackY = math.floor((b.h - wh) / 2), card._y
        card._zLastRow = widget
        return widget
    end
    local band = BandH(wh)
    local asked = (height or 0) + (widget._zExtraH or 0)
    local off
    if asked > band + 4 then
        -- the page asked for more room than the control takes: top-aligned
        band = asked + SET.ROW_V
        off = SET.ROW_V
    else
        off = math.floor((band - wh) / 2)
    end
    local b = AddBand(card, card._y, band)
    widget:SetPoint("TOPLEFT", card, "TOPLEFT", x, card._y - off)
    card._y = card._y - band
    card._zPair = halfable and { b = b, w = widget, x = x, wh = wh, y = card._y, nk = nk, nr = nr } or nil
    card._zSlack, card._zSlackY = band - off - wh, card._y
    card._zLastRow = widget
    return widget
end
Layout._zSetRow = SetRow

function Layout:Row(widget, height, indent)
    if self.set then return SetRow(self, widget, height, indent) end
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
    if self.set then return SetRow(self, widget, (widget:GetHeight() or UI.M.ROW) - (widget._zExtraH or 0) + (gap or 8), indent) end
    local room = CardWidth(self.current) - (indent or UI.M.CONTROL_X) - UI.M.CONTROL_X
    if widget._zFit and (widget:GetWidth() or 0) > room + 0.5 then widget:_zFit(room) end
    -- (the fitted height is in GetHeight already; Row must not add it twice)
    return self:Row(widget, (widget:GetHeight() or UI.M.ROW) - (widget._zExtraH or 0) + (gap or 8), indent)
end

-- The room a row has in the open card, from x (default the control inset).
function Layout:Room(indent)
    local side = self.set and SET.SIDE or UI.M.CONTROL_X
    return CardWidth(self.current) - (indent or side) - side
end

-- A row of widgets (buttons, mostly) that wraps onto a new line instead of
-- running past the card's right edge.
function Layout:Flow(widgets, gap, rowGap, indent)
    local card = self.current
    if self.set then
        -- one band, the row of buttons centred in it
        local x = indent or SET.SIDE
        local h = UI.Flow(card, widgets, x, card._y, self:Room(indent), gap or 8, rowGap or 6)
        local band = BandH(h)
        local off = math.floor((band - h) / 2)
        UI.Flow(card, widgets, x, card._y - off, self:Room(indent), gap or 8, rowGap or 6)
        AddBand(card, card._y, band)
        card._y = card._y - band
        card._zLastRow, card._zSlack, card._zSlackY, card._zPair = widgets[1], band - off - h, card._y, nil
        return
    end
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
    if self.set then
        -- each line of the grid is a band; EllesmereUI's two-up gap
        local x0 = indent or SET.SIDE
        local room = self:Room(indent)
        local GAP = 2 * SET.SIDE
        local widest = 0
        for _, w in ipairs(widgets) do widest = math.max(widest, w:GetWidth() or 0) end
        cols = math.max(1, math.min(cols or 2, #widgets))
        while cols > 1 and (room - GAP * (cols - 1)) / cols < widest do cols = cols - 1 end
        local cell = math.floor((room - GAP * (cols - 1)) / cols)
        local i = 1
        while i <= #widgets do
            local tall = 0
            for c = 0, cols - 1 do
                local w = widgets[i + c]
                if not w then break end
                if w._zFit and (w:GetWidth() or 0) > cell + 0.5 then w:_zFit(cell) end
                tall = math.max(tall, w:GetHeight() or 0)
            end
            local band = BandH(tall)
            for c = 0, cols - 1 do
                local w = widgets[i + c]
                if not w then break end
                w:ClearAllPoints()
                w:SetPoint("TOPLEFT", card, "TOPLEFT", x0 + c * (cell + GAP),
                    card._y - math.floor((band - (w:GetHeight() or 0)) / 2))
            end
            AddBand(card, card._y, band)
            card._y = card._y - band
            i = i + cols
        end
        card._zPair = nil
        return
    end
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
-- why: what a dimmed one says on hover (UI.SetEnabled); a string, or the
-- parent's label (a string without "Needs") to say 'Needs "<label>" turned
-- on.'; nil = UI.WHY_DEFAULT.
UI.M.CHILD_INDENT = UI.M.CHILD_INDENT or 20
function Layout.Why(why)
    if type(why) ~= "string" or why == "" then return nil end
    if why:find("^Needs ") or why:find("%.$") then return why end
    return 'Needs "' .. why .. '" turned on.'
end
function Layout:Dependent(widgets, parentOn, cols, rowH, why)
    self:Grid(widgets, cols or 2, rowH, (self.set and SET.SIDE or UI.M.CONTROL_X) + UI.M.CHILD_INDENT)
    why = Layout.Why(why)
    for _, w in ipairs(widgets) do
        if UI.SetEnabled then UI.SetEnabled(w, parentOn and true or false, why) end
    end
    return widgets
end

-- LESS COMMON (finish pass): rarely used rows folded away inside a card,
-- behind one small button, so a long page shows what most players need.
--   L:Fold(id, label, build, { changed = fn })
-- build(L) adds the rows, in the card that is open. Open / closed is
-- remembered per page in the window state (ZacUIDB.config.folds, like the
-- remembered tab). It opens by itself when changed() says something inside
-- is not at its default; the search index always builds what is inside,
-- and a search jump that lands in a fold opens it (and keeps it open).
function Layout:Fold(id, label, build, opts)
    opts = opts or {}
    local s = State()
    s.folds = s.folds or {}
    local key = tostring(self.pageId or "page") .. ":" .. tostring(id)
    local open = s.folds[key]
    if open == nil and opts.changed then
        local ok, c = pcall(opts.changed)
        if ok and c then open = true end
    end
    if self.live and ns._zFoldsOpen and not open then
        s.folds[key] = true
        open = true
    end
    -- the search index (not a live build) sees every row
    if not self.live then open = true end
    open = open and true or false
    local function Toggle()
        if not (self.live and self.current and UI.Button) then return end
        local b = UI.Button(self.current, (open and "Hide less common: " or "Show less common: ") .. label, {
            width = 120, height = self.set and 26 or 18, size = UI.F.SMALL,
            tooltip = open and "Folds these rarely used settings away again."
                or "Rarely used settings, folded away to keep this page short.",
            onClick = function()
                s.folds[key] = not open
                if ns.RefreshConfig then ns.RefreshConfig() end
            end })
        b._zFoldKey = key
        self:Row(b, 18 + 6)
    end
    if open then
        build(self)
        Toggle()
    else
        Toggle()
    end
    return open
end

-- A label and its value on one line (the value in a column at keyW), the
-- value wrapping within the card; when the column would be too narrow the
-- value goes under the label instead. Returns the two strings.
function Layout:Pair(key, value, keyW, opts)
    opts = opts or {}
    local card = self.current
    if self.set then
        -- a band of its own; the key column a quarter wider (the type is)
        local x = opts.indent or SET.SIDE
        local room = self:Room(opts.indent)
        keyW = math.floor((keyW or 120) * 1.25)
        local size = opts.size or UI.F.LABEL
        local k = UI.Font(card, size, { text = key, cat = "text", key = opts.keyColor or "gray" })
        local kw = math.ceil(k:GetStringWidth() or 0)
        local below = room - keyW < 140 or kw > keyW - 6
        local vx = below and (x + 12) or (x + keyW)
        local v = UI.Font(card, size, { text = value, cat = "text", key = opts.valueColor or "normal",
            width = room - (vx - x) })
        local h
        if below then
            if kw > room then k:SetWidth(room) k:SetJustifyH("LEFT") k:SetWordWrap(true) end
            local kh = math.max(size, k:GetStringHeight() or size)
            h = kh + 2 + math.max(size, v:GetStringHeight() or size)
            local band = math.max(SET.ROW, h + 18)
            local top = card._y - math.floor((band - h) / 2)
            k:SetPoint("TOPLEFT", card, "TOPLEFT", x, top)
            v:SetPoint("TOPLEFT", card, "TOPLEFT", vx, top - kh - 2)
            AddBand(card, card._y, band)
            card._y = card._y - band
        else
            h = math.max(size, k:GetStringHeight() or size, v:GetStringHeight() or size)
            local band = math.max(SET.ROW, h + 18)
            local top = card._y - math.floor((band - h) / 2)
            k:SetPoint("TOPLEFT", card, "TOPLEFT", x, top)
            v:SetPoint("TOPLEFT", card, "TOPLEFT", vx, top)
            AddBand(card, card._y, band)
            card._y = card._y - band
        end
        card._zPair = nil
        return k, v
    end
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
    if self.set then
        -- the label on the left and the control after its column, centred in a band
        local x = opts.indent or SET.SIDE
        local room = self:Room(opts.indent)
        local fs = UI.Font(card, opts.size or UI.F.LABEL, { text = label, cat = "text", key = opts.color or "normal" })
        local lw = math.ceil(fs:GetStringWidth() or 0)
        labelW = math.floor(math.max(labelW or 0, 0) * 1.25)
        local minW = opts.minW or 120
        local ch = control:GetHeight() or SET.DD_H
        if lw + 8 <= labelW and room - labelW >= minW then
            local cr = room - labelW
            if (control:GetWidth() or 0) > cr + 0.5 then
                if control._zFit then control:_zFit(cr) else control:SetWidth(cr) end
            end
            ch = math.max(ch, control:GetHeight() or ch)
            local band = BandH(ch)
            local top = card._y - math.floor((band - ch) / 2)
            fs:SetPoint("LEFT", card, "TOPLEFT", x, top - ch / 2)
            control:ClearAllPoints()
            control:SetPoint("TOPLEFT", card, "TOPLEFT", x + labelW, top)
            AddBand(card, card._y, band)
            card._y = card._y - band
        else
            if lw > room then fs:SetWidth(room) fs:SetJustifyH("LEFT") fs:SetWordWrap(true) end
            if (control:GetWidth() or 0) > room + 0.5 then
                if control._zFit then control:_zFit(room) else control:SetWidth(room) end
            end
            local lh = math.max(12, fs:GetStringHeight() or 12)
            local h = lh + 4 + (control:GetHeight() or ch)
            local band = math.max(SET.ROW_CTL, h + 18)
            local top = card._y - math.floor((band - h) / 2)
            fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, top)
            control:ClearAllPoints()
            control:SetPoint("TOPLEFT", card, "TOPLEFT", x, top - lh - 4)
            AddBand(card, card._y, band)
            card._y = card._y - band
        end
        card._zPair = nil
        return fs
    end
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
    local follows = self.set and card._zSlackY == card._y and card._zBands and card._zBands[#card._zBands] or nil
    -- (settings window: under a checkbox it lines up with the label)
    local descX = UI.M.DESC_X
    if self.set then
        descX = SET.SIDE
        local lr = follows and card._zLastRow
        if lr and rawget(lr, "_zCheck") then descX = SET.SIDE + SET.CHECK + SET.CHECK_GAP end
        -- (the second of a pair: under it, at the half)
        if lr and lr.GetPoint then
            local _, _, _, px = lr:GetPoint(1)
            if type(px) == "number" and px > SET.SIDE + 1 then descX = descX - SET.SIDE + px end
        end
    end
    local fs = UI.Font(card, UI.F.DESC, {
        text = text, cat = "text", key = "gray",
        width = math.max(120, CardWidth(card) - descX - (self.set and SET.SIDE or 16)),
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
    if self.set then
        -- in the band of the row it belongs to, 6 above that band's foot,
        -- the band grown to hold it; on its own, a band of its own
        local dh = math.max(12, math.ceil(fs:GetStringHeight() or 12))
        if follows then
            -- (from the band's foot: never into what the row drew)
            local lift = 0
            fs:SetPoint("TOPLEFT", card, "TOPLEFT", descX, card._y + lift)
            local grow = dh - lift + SET.ROW_V
            follows.h = follows.h + grow
            card._y = card._y - grow
        else
            fs:SetPoint("TOPLEFT", card, "TOPLEFT", descX, card._y - SET.ROW_V)
            local band = dh + 2 * SET.ROW_V
            AddBand(card, card._y, band)
            card._y = card._y - band
        end
        card._zSlack, card._zPair = nil, nil
        return fs
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
    local dx = self.set and SET.SIDE or UI.M.DESC_X
    local fs = UI.Font(card, UI.F.DESC, {
        text = text, cat = "text", key = n.key,
        width = math.max(120, CardWidth(card) - dx - 16),
    })
    if self.set then
        local dh = math.max(12, math.ceil(fs:GetStringHeight() or 12))
        local band = math.max(SET.ROW, dh + 2 * SET.ROW_V)
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", dx, card._y - math.floor((band - dh) / 2))
        AddBand(card, card._y, band)
        card._y = card._y - band
    else
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", UI.M.DESC_X, card._y + 3)
        card._y = card._y - math.max(12, fs:GetStringHeight()) - 6
    end
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
    -- (settings window: EllesmereUI's dark band behind the tabs)
    local band = bar:CreateTexture(nil, "BACKGROUND", nil, -6)
    band._zui_own = true
    band:SetTexture(ns.FLAT)
    band:SetAllPoints(bar)
    band:SetVertexColor(0, 0, 0, 0.2)
    band:Hide()
    bar._zBand = band
    return bar
end

-- ============================================================
-- TABS ADDED FROM OUTSIDE THE PAGE (2026-11-07, feature cluster 1)
-- ============================================================
-- A feature that lives in a file of its own puts its cards on another
-- page without that page knowing it: ns.AddPageTab(pageId, tabId, label,
-- build). An existing tab of that id gets the cards built after its own;
-- a new id becomes a tab of its own, seated in the standard order
-- (General, Look, Text, Animation, Sound, Position, Advanced; anything
-- else at the end). The builder gets the page's Layout and runs on every
-- rebuild and once, unseen, for the search index, like any tab builder.
-- A file that loads before this one makes the list itself (ns.PageTabs).
local PAGE_TABS = ns.PageTabs or {}
ns.PageTabs = PAGE_TABS
local TAB_ORDER = { general = 1, look = 2, text = 3, anim = 4, sound = 5, pos = 6, adv = 7 }
local function AddPageTab(pageId, tabId, label, build)
    if type(pageId) ~= "string" or type(tabId) ~= "string" or type(build) ~= "function" then return false end
    local list = PAGE_TABS[pageId]
    if not list then list = {} PAGE_TABS[pageId] = list end
    list[#list + 1] = { tab = tabId, label = label or tabId, build = build }
    -- a page already read for the search is read again, with the new tab
    if ns.ConfigSearch and ns.ConfigSearch.Invalidate then ns.ConfigSearch.Invalidate(pageId) end
    return true
end
local function ExtendTabs(pageId, tabs)
    local extras = pageId and PAGE_TABS[pageId]
    if not (extras and #extras > 0) then return tabs end
    local out = {}
    for i, t in ipairs(tabs) do out[i] = t end
    for _, e in ipairs(extras) do
        local at
        for i, t in ipairs(out) do if t.id == e.tab then at = i end end
        if at then
            local own, extra, copy = out[at].build, e.build, {}
            for k, v in pairs(out[at]) do copy[k] = v end
            copy.build = function(L)
                if own then own(L) end
                extra(L)
            end
            out[at] = copy
        else
            local rank, pos = TAB_ORDER[e.tab] or 99, #out + 1
            for i, t in ipairs(out) do
                if (TAB_ORDER[t.id] or 99) > rank then pos = i break end
            end
            table.insert(out, pos, { id = e.tab, label = e.label, build = e.build })
        end
    end
    return out
end
ns.AddPageTab = AddPageTab

function Layout:Tabs(tabs)
    local s = State()
    s.tabs = s.tabs or {}
    local pageId = self.pageId or "?"
    tabs = ExtendTabs(pageId, tabs)
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
    -- (settings window: EllesmereUI's tab bar - 40 tall rows, the first tab
    -- 36 in, labels + 30 wide, 6 apart; Config_Window pins it under the
    -- page's title)
    local set = self.set
    local BH = set and SET.TABS or UI.M.BUTTON_H
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", self.parent, "TOPLEFT", set and 0 or UI.M.MARGIN, self.y)
    bar:SetPoint("RIGHT", self.parent, "RIGHT", set and 0 or -UI.M.MARGIN, 0)
    bar:SetHeight(BH)
    bar._zSet = set
    bar._zRule:SetShown(not set)
    if bar._zBand then bar._zBand:SetShown(set and true or false) end
    -- THE ROW FITS THE PAGE. Every button is as wide as its label (measured,
    -- in the font it is drawn in) and never narrower, so no label is ever
    -- cut short; buttons that do not fit on a line go to the next one. The
    -- row count is fixed at build (the cards below are placed from it); a
    -- resize rebuilds the page, and until then only re-flows the buttons.
    local GAP, MIN_W = set and 6 or 4, set and 40 or 56
    local X0 = set and 36 or 0
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
        natural[i] = math.max(MIN_W, tw + (set and 30 or 24))
        if set then b:SetHeight(BH) b:_zPaint() end
        b:SetWidth(natural[i])
        buttons[i] = b
    end
    local function Avail()
        local w = bar:GetWidth()
        if not w or w < 200 then
            w = (self.parent:GetWidth() or 0) - (set and 0 or 2 * UI.M.MARGIN)
        end
        if not w or w < 200 then w = 420 end
        return w - (set and 2 * X0 or 0)
    end
    local RGAP = set and 0 or GAP
    local function Place(width)
        local n = #buttons
        if n == 0 then return 1 end
        local x, r = 0, 1
        for i = 1, n do
            local b, w = buttons[i], natural[i]
            if x > 0 and x + w > width + 0.5 then x, r = 0, r + 1 end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", X0 + x, -(r - 1) * (BH + RGAP))
            x = x + w + GAP
        end
        return r
    end
    local rows = Place(Avail())
    bar:SetHeight(rows * BH + (rows - 1) * RGAP)
    bar:SetScript("OnSizeChanged", function(_, w)
        if w and w > 0 then Place(w - (set and 2 * X0 or 0)) end
    end)
    -- a rule under the row, so the tabs read as a header for what follows
    local rule = bar._zRule
    local a = ns.GetColor and ns.GetColor("ui", "border")
    if a then rule:SetVertexColor(a.r, a.g, a.b, 1) end

    self.y = self.y - bar:GetHeight() - (set and 0 or 12)
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

-- ============================================================
-- PARTS ON AND OFF (the sidebar's power buttons)
-- ============================================================
-- A part is its addon (Zacui_Bars, Zacui_UnitFrames...): on means the
-- game loads it, off means it does not - one switch, the AddOns list's,
-- set from here for THIS character (a profile is a character's too).
--   ns.PartState(addon)  "on" / "off" (loaded or not), "missing" (not in
--                        the AddOns folder), and whether the next load
--                        changes that (the second value: true = pending)
--   ns.AskPart(addon, label, on)  the "Turn off and reload" question
local function AddonApi()
    local C = C_AddOns
    return {
        loaded = (C and C.IsAddOnLoaded) or IsAddOnLoaded,
        info = (C and C.GetAddOnInfo) or GetAddOnInfo,
        exists = C and C.DoesAddOnExist,
        enable = (C and C.EnableAddOn) or EnableAddOn,
        disable = (C and C.DisableAddOn) or DisableAddOn,
        -- the new call takes (name, character), the old one (character, name)
        state = (C and C.GetAddOnEnableState) and function(name, who) return C.GetAddOnEnableState(name, who) end
            or (GetAddOnEnableState and function(name, who) return GetAddOnEnableState(who, name) end),
    }
end

local function Me() return (UnitName and UnitName("player")) or nil end

function ns.PartState(addon)
    if type(addon) ~= "string" then return nil end
    local A = AddonApi()
    local okL, loaded = pcall(A.loaded or function() return false end, addon)
    loaded = okL and loaded and true or false
    local exists = loaded
    if not exists then
        if A.exists then
            local ok, e = pcall(A.exists, addon)
            exists = ok and e and true or false
        elseif A.info then
            local ok, name, _, _, _, reason = pcall(A.info, addon)
            exists = ok and name ~= nil and reason ~= "MISSING"
        end
    end
    if not exists then return "missing", false end
    local next = loaded
    if A.state then
        local ok, st = pcall(A.state, addon, Me())
        if ok and type(st) == "number" then next = st > 0 end
    end
    return loaded and "on" or "off", (next ~= loaded)
end

-- Turns the part on or off for the next load. The reload is asked for
-- FIRST, inside the click (WoW Forever; UIF_Dialogs' ns.AskReload), then
-- the AddOns list is written.
function ns.SetPartEnabled(addon, on)
    local A = AddonApi()
    local fn = on and A.enable or A.disable
    if not fn then return false end
    return pcall(fn, addon, Me())
end

function ns.AskPart(addon, label, on)
    if not (ns.AskReload and addon) then return end
    label = label or addon
    local text
    if on then
        text = label .. " turns on for this character after the reload."
    else
        text = label .. " turns off for this character. The game's own version comes back after the reload, "
            .. "and its settings are kept. Turn it on again here any time."
    end
    ns.AskReload(text, {
        title = (on and "Turn on " or "Turn off ") .. label,
        acceptText = on and "Turn on and reload" or "Turn off and reload",
        apply = function() ns.SetPartEnabled(addon, on) end,
    })
end

-- A part that adds its own sidebar group when it loads (Class HUDs) keeps a
-- row while it is off, so it can be turned on again from here: added once,
-- at login, only when the part is in the AddOns folder and did not load.
function ns.KeepPartRow(id, label, addon, afterId)
    for _, item in ipairs(MENU) do if item.id == id then return end end
    if ns.PartState(addon) ~= "off" then return end
    local at = #MENU + 1
    for i, item in ipairs(MENU) do if item.id == afterId then at = i + 1 break end end
    table.insert(MENU, at, { id = id, label = label, addon = addon, keywords = addon:lower() })
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
