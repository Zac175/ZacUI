-- Config_PagesWindows - the Game windows page: how ZacUI's rebuilt
-- windows (character sheet, spellbook, talents, professions, merchant,
-- mail, social, quest log and the rest) look, how big they are and how
-- they open.
-- Part of ZacUI; load order is set by the TOC (last, after every window).
--
-- Which windows are rebuilt at all stays where it was, on Modules >
-- Windows; this page is the look they share. Every setting is in
-- ZacUIDB.windows and read by Win_Kit's cover (Kit.StyleCover, the
-- scale and the opening), and the preview dock shows a sample window
-- made by that same Kit.Cover.

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Kit = ns.Kit
local Print = ns.Print
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local UI = ns.UI

if not (Kit and RegisterPage and UI) then return end

local M, F = UI.M, UI.F

local PAGE_ID, MENU_ID = "GameWindows", "gamewindows"

-- ============================================================
-- THE MENU ROW
-- ============================================================
-- In the "Bags & maps" group, with the other windows you open. Inserted
-- when this part loads (Config_Base's menu is the core's), so the row is
-- there exactly when the windows are.
do
    for _, group in ipairs(ns.ConfigMenu or {}) do
        if group.id == "windows" and group.children then
            local have = false
            for _, child in ipairs(group.children) do
                if child.id == MENU_ID then have = true end
            end
            if not have then
                group.children[#group.children + 1] = {
                    id = MENU_ID, label = "Game windows", page = PAGE_ID, addon = "Zacui_Windows",
                    keywords = "windows window character sheet paperdoll spellbook spell book talents "
                        .. "professions tradeskill crafting enchanting trainer merchant vendor mail mailbox "
                        .. "social friends who guild ignore raid quest log gossip loot trade taxi flight "
                        .. "macros inspect pvp battlemaster scoreboard group finder lfg pet "
                        .. "scale size bigger smaller background colour color opacity transparent border "
                        .. "title font animation open opening fade slide pop preview position anchor icon",
                }
            end
        end
    end
end

-- ============================================================
-- THE WINDOWS' LOOK IN PROFILES
-- ============================================================
-- ZacUIDB.windows is a new top-level key. Profiles carry the keys in
-- Core_Profiles' list; until it names this one, it is added to that list
-- here, so wearing, saving, exporting and resetting a whole profile take
-- the windows' look along. The profile this character wears may already
-- have been put on before this part loaded, so its windows look is taken
-- from it now (none saved = the shipped look).
do
    local P = ns.Profiles
    if P and type(P.PROFILE_KEYS) == "table" then
        local have = false
        for _, k in ipairs(P.PROFILE_KEYS) do if k == "windows" then have = true end end
        if not have then
            table.insert(P.PROFILE_KEYS, "windows")
            local name = P.Current and P.Current()
            local snap = name and ZacUIDB and ZacUIDB.profiles and ZacUIDB.profiles[name]
            if type(snap) == "table" and ZacUIDB then
                local copy = ns.CopySetting or function(v) return v end
                ZacUIDB.windows = copy(snap.windows)
            end
        end
    end
end

-- A change on this page reaches every window once on the next frame,
-- however many landed in this one (a colour drag is dozens).
local LookSoon
do
    local function Run() Kit.ApplyLook() end
    LookSoon = ns.Coalesce and ns.Coalesce(Run) or Run
end

-- ============================================================
-- THE PREVIEW: A SAMPLE WINDOW
-- ============================================================
-- A cover made by Kit.Cover itself (in preview mode: no drag, never
-- registered), with a title and icon, a tab strip with the gear list
-- beside it and a footer - every piece one of the kit's, at the size of
-- the character window (384 wide). It wears the scale, the colours and
-- the title font; Replay plays the opening animation. The canvas is the
-- window at its scale, as it opens in game.
local HOST_W, HOST_H = 384, 290
local TABS_W = 150

local SAMPLE_ROWS = {
    { "Interface\\Icons\\INV_Helmet_03", "Lionheart Helm", 4, "62", "Head" },
    { "Interface\\Icons\\INV_Jewelry_Necklace_17", "Onyxia Tooth Pendant", 4, "60", "Neck" },
    { "Interface\\Icons\\INV_Shoulder_29", "Drake Talon Pauldrons", 4, "75", "Shoulder" },
    { "Interface\\Icons\\INV_Misc_Cape_20", "Cape of the Black Baron", 3, "63", "Back" },
    { "Interface\\Icons\\INV_Chest_Plate16", "Savage Gladiator Chain", 4, "57", "Chest" },
    { "Interface\\Icons\\INV_Gauntlets_26", "Flameguard Gauntlets", 4, "66", "Hands" },
    { "Interface\\Icons\\INV_Belt_10", "Onslaught Girdle", 4, "77", "Waist" },
    { "Interface\\Icons\\INV_Pants_04", "Legguards of the Fallen Crusader", 4, "73", "Legs" },
}

local function BuildWindowPreview(canvas, P)
    local st = P.store
    local host = CreateFrame("Frame", nil, canvas)
    host:SetSize(HOST_W, HOST_H)
    host:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    st.host = host

    local win = Kit.Cover(host, { preview = true, title = "Character" })
    win:SetIcon("Interface\\Icons\\INV_Chest_Plate16")
    st.win = win

    local tabs = Kit.Tabs(win, { { key = "gear", label = "Gear" }, { key = "stats", label = "Stats" } })
    tabs:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, win.top)
    tabs:SetPoint("RIGHT", win, "LEFT", Kit.PAD + TABS_W, 0)
    tabs:Paint("gear")
    st.tabs = tabs

    -- the gear list: a Kit.List with rows built the way the windows build
    -- theirs (icon, name over a second line, a right-hand column), so the
    -- row texts' spots show on it exactly as on every window's list
    local foot = Kit.Footer(win, 24)
    local list = Kit.List(win, { rowHeight = Kit.ROW_H,
        build = function(row)
            local rh = Kit.ROW_H
            row.icon = Kit.Icon(row, rh - 4)
            row.icon:SetPoint("LEFT", 3, 0)
            row.priceText = UI.Font(row, F.SMALL, { justify = "RIGHT", cat = "text", key = "gray" })
            row.priceText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
            row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, -2)
            row.nameText:SetPoint("RIGHT", row.priceText, "LEFT", -6, 0)
            row.nameText:SetWordWrap(false)
            row.sub = UI.Font(row, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
            row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, 2)
            row.sub:SetPoint("RIGHT", row.priceText, "LEFT", -6, 0)
            row.sub:SetWordWrap(false)
            if ns.TagElement then
                ns.TagElement(row.nameText, "windows.rowName") ns.TagElement(row.sub, "windows.rowSub")
                ns.TagElement(row.priceText, "windows.rowRight")
            end
        end,
        update = function(row, r)
            row.icon:SetIcon(r[1])
            row.icon:SetQuality(r[3])
            row.nameText:SetText(r[2])
            if ns.QualityRGB then row.nameText:SetTextColor(ns.QualityRGB(r[3])) end
            row.sub:SetText(r[5])
            row.priceText:SetText(r[4])
        end })
    list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD + TABS_W + 10, win.top - 3)
    list:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)
    list:SetData(SAMPLE_ROWS)
    st.list = list
    local close = UI.Button(foot, CLOSE or "Close", { width = 70, height = 20 })
    close:SetPoint("RIGHT", foot, "RIGHT", -6, 0)
    st.footer = foot

    -- in the footer, left of Close (the canvas is the window's own size)
    local note = UI.Font(canvas, F.SMALL, { text = "", cat = "text", key = "gray", justify = "LEFT" })
    note:SetPoint("LEFT", foot, "LEFT", 8, 0)
    st.note = note
end

local function UpdateWindowPreview(canvas, P)
    local st = P.store
    local db = Kit.DB()
    Kit.StyleCover(st.win)
    if st.win.titleBar._zPaint then st.win.titleBar:_zPaint() end
    if st.list then st.list:Refresh() end
    local s = math.max(0.5, math.min(2, tonumber(db.scale) or 1))
    if ns.Motion and ns.Motion.IsPlaying(st.host) then ns.Motion.Stop(st.host) end
    st.host:SetScale(s)
    st.host:Show()
    -- the canvas is the window at its scale (the strip shows it real size)
    if P.Resize then P.Resize((HOST_W + 12) * s, (HOST_H + 8) * s) end
    if ns.Motion and not ns.Motion.Enabled() then
        st.note:SetText("Animations are off (Appearance > Motion).")
    else
        st.note:SetText("")
    end
end

local function ReplayWindowPreview(canvas, P)
    local st = P.store
    local spec = Kit.DB().openAnim
    if not (ns.Motion and type(spec) == "table" and spec.style and spec.style ~= "none") then return end
    ns.Motion.Stop(st.host)
    st.host:Hide()
    ns.Motion.Play(st.host, spec, "in")
end

-- ============================================================
-- THE PAGE
-- ============================================================
local function Color(L, key, label, cat, ckey, alpha, desc)
    local db = Kit.DB()
    local p = UI.ColorPicker(L.current, { label = label, alpha = alpha,
        get = function() return Kit.Color(key, cat, ckey, (cat == "ui" and ckey == "windowBg") and 1 or nil) end,
        set = function(r, g, b, a)
            db[key] = { r = r, g = g, b = b, a = a or 1 }
            LookSoon()
        end })
    L:Add(p, 6)
    if desc then L:Desc(desc) end
    return p
end

RegisterPage(PAGE_ID, function(L)
    L:Header("Game windows",
        "The look of ZacUI's own windows - the character sheet, spellbook, talents, "
        .. "professions, merchant, mailbox, social, quest log and the rest: how big "
        .. "they are, their colours, their titles and how they open.")

    local db = Kit.DB()

    -- the preview's title or icon picked: its spot
    if ns.CustomPick then
        ns.CustomPick.SetHandler("windows.cover", function(el)
            local row = el == "windows.rowName" or el == "windows.rowSub" or el == "windows.rowRight"
            if el ~= "windows.title" and el ~= "windows.icon" and not row then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            ZacUIDB.config.tabs[MENU_ID] = (el == "windows.icon") and "pos" or "text"
            RefreshConfig()
        end)
    end

    L:Preview({
        key = "windows.cover",
        title = "Game window",
        width = HOST_W + 12, height = HOST_H + 8,
        build = BuildWindowPreview,
        update = UpdateWindowPreview,
        replay = ReplayWindowPreview,
    })

    local function Tab_general(L)
        L:Card("Which windows")
        L:Desc("Every window ZacUI rebuilds can be switched on and off on its own, "
            .. "on Modules > Windows. What you set here applies to all of them together.")
        local row = UI.Holder(L.current)
        row:SetSize(300, M.BUTTON_H)
        local go = UI.Button(row, "Choose windows", { width = 130,
            tooltip = "Opens Modules > Windows.",
            onClick = function() if ns.OpenConfig then ns.OpenConfig("mod_windows") end end })
        go:SetPoint("LEFT")
        L:Row(row, M.BUTTON_H + 4)
        L:EndCard()
    end

    local function Tab_look(L)
        L:Card("Colours")
        Color(L, "bg", "Background", "ui", "windowBg", true,
            "Below 100% you see through the window, and for some windows that means "
            .. "Blizzard's own art underneath it.")
        Color(L, "border", "Border", "ui", "border", true)
        L:Desc("Unchanged, both follow the theme on the Colours page. Advanced > Reset puts them back.")
        L:EndCard()
    end

    local function Tab_text(L)
        L:Card("Window titles")
        local fp = UI.FontPicker(L.current, { label = "Font", width = 400,
            get = function() return db.titleFont end,
            set = function(spec) db.titleFont = spec LookSoon() end,
            defaults = Kit.TitleFontDefaults(), sample = "Character" })
        L:Add(fp, 8)
        Color(L, "titleColor", "Colour", "text", (Kit and Kit.TITLE_KEY) or "normal", false)
        -- where the title sits (windows.anchors.title; nothing saved = as ever)
        local tg, ts = ns.CustomAccess(Kit.DB, "anchors", "title", LookSoon)
        local list = {}
        for _, e in ipairs(Kit.ANCHOR_TARGETS) do if e.value ~= "title" then list[#list + 1] = e end end
        UI.TextElement(L, { key = "windows.title", label = "Where the title sits", anchorGet = tg, anchorSet = ts,
            targets = list, defaultTargetLabel = "Where it sits now", anchorMin = -60, anchorMax = 60,
            anchorDefaults = function() return Kit.AnchorDefaults("title") end })
        L:EndCard()

        -- every list's row texts at once (windows.anchors.<rowName|rowSub|rowRight>)
        if Kit.ROW_TEXTS then
            L:Card("List rows (every window)")
            L:Desc("The rows of every list - spells, recipes, merchant goods, mail, quests, friends... "
                .. "Nothing set = where each window put them.")
            for _, key in ipairs(Kit.ROW_TEXTS) do
                local rg, rs = ns.CustomAccess(Kit.DB, "anchors", key, LookSoon)
                local list = {}
                for _, e in ipairs(Kit.ROW_TARGETS) do if e.value ~= key then list[#list + 1] = e end end
                UI.TextElement(L, { key = "windows." .. key, label = Kit.ROW_TEXT_LABELS[key],
                    anchorGet = rg, anchorSet = rs, targets = list,
                    anchorDefaults = function() return Kit.RowTextDefaults(key) end,
                    defaultTargetLabel = "Where each window put it", anchorMin = -80, anchorMax = 80 })
            end
            L:EndCard()
        end

        L:Card("Everything else")
        L:Desc("The text inside the windows uses ZacUI's font and size, set for the "
            .. "whole interface on Appearance > Fonts & Textures.")
        local row = UI.Holder(L.current)
        row:SetSize(300, M.BUTTON_H)
        local go = UI.Button(row, "Fonts & Textures", { width = 130,
            onClick = function() if ns.OpenConfig then ns.OpenConfig("font") end end })
        go:SetPoint("LEFT")
        L:Row(row, M.BUTTON_H + 4)
        L:EndCard()
    end

    local function Tab_anim(L)
        L:Card("When a window opens")
        local ap = UI.AnimationPicker(L.current, {
            styles = { "none", "fade", "slide", "pop" },
            get = function() return db.openAnim end,
            set = function(spec) db.openAnim = spec end,
        })
        L:Add(ap, 6)
        L:Desc("None is the window simply appearing, as it always has. Replay in the preview "
            .. "plays it. Closing is always instant - the game closes these windows itself.")
        L:EndCard()
        if ns.Motion and not ns.Motion.Enabled() then
            L:Notice("warn", "Animations are off (Appearance > Motion), so windows simply appear.")
        end
    end

    local function Tab_pos(L)
        L:Card("Size")
        local sl = UI.Slider(L.current, { width = 220, min = 50, max = 150, step = 5,
            label = "Scale",
            value = math.floor((tonumber(db.scale) or 1) * 100 + 0.5),
            format = function(v) return v .. "%" end,
            onChange = function(v)
                db.scale = v / 100
                LookSoon()
            end })
        L:Row(sl, 40)
        L:Desc("Every rebuilt window together, with the game window it sits in. In combat "
            .. "a protected window waits until the fight ends.")
        L:EndCard()

        L:Card("The title bar's icon")
        local ig, is = ns.CustomAccess(Kit.DB, "anchors", "icon", LookSoon)
        local ilist = {}
        for _, e in ipairs(Kit.ANCHOR_TARGETS) do if e.value ~= "icon" then ilist[#ilist + 1] = e end end
        UI.FrameElement(L, { key = "windows.icon", anchorGet = ig, anchorSet = is, targets = ilist,
            defaultTargetLabel = "Where it sits now", anchorMin = -60, anchorMax = 60,
            anchorDefaults = function() return Kit.AnchorDefaults("icon") end })
        L:Desc("Every window with an icon. The title follows it unless placed itself (Text tab).")
        L:EndCard()

        L:Card("Where they open")
        L:Desc("Drag a window by its title bar and it opens there from then on; shift-right-click "
            .. "the title bar to put that one back.")
        local row = UI.Holder(L.current)
        row:SetSize(300, M.BUTTON_H)
        local back = UI.Button(row, "Put them all back", { width = 140,
            tooltip = "Every rebuilt window opens where the game puts it again.",
            onClick = function()
                local pos = ZacUIDB and ZacUIDB.windowPos
                if not pos then return end
                local n = 0
                for top in pairs(Kit.tops) do
                    local name = top.GetName and top:GetName()
                    if name and pos[name] then pos[name] = nil n = n + 1 end
                end
                if Print then Print(n .. " window position(s) forgotten - they open where the game puts them.") end
            end })
        back:SetPoint("LEFT")
        L:Row(row, M.BUTTON_H + 4)
        L:EndCard()
    end

    local function Tab_adv(L)
        L:Card("Reset")
        local row = UI.Holder(L.current)
        row:SetSize(300, M.BUTTON_H)
        local reset = UI.Button(row, "Reset the look", { width = 120,
            tooltip = "Scale, colours, title font and opening back to how ZacUI ships them.",
            onClick = function()
                -- (the flight times' settings have their own page and reset)
                for k in pairs(db) do if k ~= "flight" then db[k] = nil end end
                for k, v in pairs(Kit.DEFAULTS) do
                    db[k] = (ns.CopySetting and ns.CopySetting(v)) or v
                end
                Kit.ApplyLook()
                if ns.SettingsChanged then ns.SettingsChanged("reset") end
                RefreshConfig()
            end })
        reset:SetPoint("LEFT")
        L:Row(row, M.BUTTON_H + 4)
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
