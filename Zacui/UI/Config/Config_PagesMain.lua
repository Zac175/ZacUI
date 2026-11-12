-- Config_PagesMain - the General, Modules, Movers and Tools pages.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local ArmIdentify = ns.ArmIdentify
local ClassifyAndSkin = ns.ClassifyAndSkin
local EnableModuleLive = ns.EnableModuleLive
local MODULE_GROUPS = ns.MODULE_GROUPS
local MODULE_ORDER = ns.MODULE_ORDER
local MOVERS = ns.MOVERS
local Print = ns.Print
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local ResetMover = ns.ResetMover
local ToggleMover = ns.ToggleMover
local ToggleTipMover = ns.ToggleTipMover
local UI = ns.UI
local ZUI = ns.ZUI

local M, F = UI.M, UI.F

-- ============================================================
-- PAGE KIT - the rows the Screen and Bags pages are built from
-- ============================================================
-- Each takes the layout and a function returning the live settings
-- table (not the table itself: a Reset swaps the table out, and a row
-- built before it must write to the new one). Shared with
-- Config_PagesMinimap through ns.CorePageKit.
local Kit = {}

-- A colour that may be unset: nil reads as `fallback()` (the palette
-- colour the module uses) until it is picked.
function Kit.Color(L, label, tbl, key, fallback, opts)
    opts = opts or {}
    local p = UI.ColorPicker(L.current, { label = label, alpha = opts.alpha,
        get = function()
            local c = tbl()[key]
            if type(c) == "table" then return ns.ColorOf(c) end
            return fallback()
        end,
        set = function(r, g, b, a)
            tbl()[key] = { r = r, g = g, b = b, a = a }
            if opts.after then opts.after() end
        end })
    L:Add(p, 6)
    if opts.desc then L:Desc(opts.desc) end
    return p
end

function Kit.Palette(cat, key)
    return function()
        local c = ns.GetColor(cat, key)
        return c.r, c.g, c.b, c.a or 1
    end
end

function Kit.Check(L, label, tbl, key, desc, opts)
    opts = opts or {}
    local on = tbl()[key]
    if opts.invert then on = not on end
    if opts.defaultOn then on = tbl()[key] ~= false end
    local cb = UI.Checkbox(L.current, label, on and true or false, function(v)
        if opts.invert then v = not v end
        tbl()[key] = v and true or false
        if opts.after then opts.after(v) end
    end)
    L:Row(cb, 17)
    if desc then L:Desc(desc) end
    return cb
end

-- opts: min, max, step, format, get(v) -> shown value, set(v) -> stored
function Kit.Slider(L, label, tbl, key, opts, desc)
    local raw = tbl()[key]
    local s = UI.Slider(L.current, { width = opts.width or 220,
        min = opts.min, max = opts.max, step = opts.step or 1,
        value = (opts.get and opts.get(raw)) or raw or opts.min, label = label,
        format = opts.format,
        onChange = function(v)
            tbl()[key] = opts.set and opts.set(v) or v
            if opts.after then opts.after(v) end
        end })
    L:Row(s, 40)
    if desc then L:Desc(desc) end
    return s
end

-- items: { { text, value }, ... }
function Kit.Choice(L, label, tbl, key, items, desc, opts)
    opts = opts or {}
    local function TextOf(v)
        for _, it in ipairs(items) do if it.value == v then return it.text end end
        return items[1] and items[1].text or tostring(v)
    end
    local f = UI.Field(L.current, label, function(h)
        return UI.Dropdown(h, { width = opts.width or 220,
            items = function() return items end,
            selectedValue = function() return tbl()[key] end,
            selected = function() return TextOf(tbl()[key]) end,
            onSelect = function(v)
                tbl()[key] = v
                if opts.after then opts.after(v) end
            end })
    end, { width = opts.width or 220 })
    L:Add(f, 6)
    if desc then L:Desc(desc) end
    return f
end

function Kit.Font(L, label, tbl, key, defaults, opts)
    opts = opts or {}
    local p = UI.FontPicker(L.current, { label = label, defaults = defaults,
        defaultLabel = opts.defaultLabel, sample = opts.sample,
        minSize = opts.minSize, maxSize = opts.maxSize,
        get = function() return tbl()[key] end,
        set = function(spec)
            -- an emptied spec is "as before", not an empty table
            tbl()[key] = (type(spec) == "table" and next(spec)) and spec or nil
            if opts.after then opts.after() end
        end })
    L:Add(p, 8)
    if opts.desc then L:Desc(opts.desc) end
    return p
end

function Kit.Anim(L, label, tbl, key, styles, desc, opts)
    opts = opts or {}
    local p = UI.AnimationPicker(L.current, { label = label, styles = styles,
        get = function() return tbl()[key] or opts.default end,
        set = function(spec)
            tbl()[key] = spec
            if opts.after then opts.after() end
        end })
    L:Add(p, 8)
    if desc then L:Desc(desc) end
    return p
end

-- A row of buttons; each { text, width, onClick, tooltip }.
function Kit.Buttons(L, list)
    local row = UI.Holder(L.current)
    row:SetSize(440, M.BUTTON_H)
    local prev
    for _, b in ipairs(list) do
        local btn = UI.Button(row, b[1], { width = b[2] or 110, onClick = b[3], tooltip = b[4] })
        if prev then btn:SetPoint("LEFT", prev, "RIGHT", 8, 0) else btn:SetPoint("LEFT") end
        prev = btn
    end
    L:Row(row, M.BUTTON_H + 6)
    return row
end

-- Move / reset for a ZacUI mover, with the same Edit Mode honesty as the
-- Movers page.
function Kit.Mover(L, key, label)
    local mv = MOVERS and MOVERS[key]
    if not mv then return end
    local frame = mv.getFrame and mv.getFrame()
    local managed = frame and ((frame.IsProtected and frame:IsProtected()) or frame.system ~= nil)
    local row = Kit.Buttons(L, {
        { "Move " .. (label or mv.label):lower(), 140, function() ToggleMover(key) end },
        { "Reset", 70, function() ResetMover(key) end },
    })
    if managed then
        L:Desc("Edit Mode manages this frame on this client: move and scale it there "
            .. "(Esc > Edit Mode). A saved ZacUI spot is kept but stays dormant.")
    end
    return row
end

-- Words people type that are not on the page, added to a menu entry.
function Kit.Keywords(id, words)
    if ns.AddMenuKeywords then ns.AddMenuKeywords(id, words) end
end

ns.CorePageKit = Kit

local function Reload()
    if ns.RequestReload then
        ns.RequestReload()
    elseif type(ReloadUI) == "function" then
        ReloadUI()
    elseif C_UI and C_UI.Reload then
        C_UI.Reload()
    else
        Print("Reload unavailable - type /reload.")
    end
end

local function Rescan()
    if not EnumerateFrames then
        Print("rescan: EnumerateFrames unavailable on this client.")
        return
    end
    local f, n = EnumerateFrames(), 0
    while f do
        pcall(ClassifyAndSkin, f)
        n = n + 1
        f = EnumerateFrames(f)
    end
    Print("rescan: walked " .. n .. " frames (finished ones are fenced out).")
end

-- ============================================================
-- THE LOOK (Core_Look): what the world wears, and the way to the Style
-- page where it is chosen (Config_Style: the cards, the per-part lists,
-- the reload-gated apply)
-- ============================================================

local function LookCard(L)
    local Look = ns.Look
    if not Look then return end
    -- the look is chosen on Appearance > Style (Config_Style); here, one
    -- line saying what the world wears and the way there
    local card = L:Card("Look")
    local uni = Look.LiveUniform and Look.LiveUniform()
    local l = Look.Get(uni or Look.Active())
    L:Desc(uni and ("The world wears the " .. (l and l.name or uni) .. " look.")
        or "Your parts wear a mix of looks.")
    local b = UI.Button(card, "Open Style", { width = 120, onClick = function()
        if ns.OpenConfig then ns.OpenConfig("style") end
    end })
    L:Flow({ b }, 8, 6)
    L:EndCard()
    return card
end
ns.LookCard = LookCard
-- (a pending look is dropped with the window: Config_Window's OnHide
-- calls Look.Discard; the confirm is the only way it is kept)

-- ============================================================
-- GENERAL
-- ============================================================
RegisterPage("General", function(L)
    L:Header("ZacUI",
        "A flat dark skin for the Classic Era interface. Every module is "
        .. "independent - turn off anything you would rather keep stock. "
        .. "Diagnostics, the shared voice and the reset switch are here too.")

    -- the tour and quick setup (UI/Tutorial)
    if ns.TutorialCard then ns.TutorialCard(L) end
    -- the Look: ZacUI's flat art or the game's Classic one (Core_Look)
    LookCard(L)
    -- SETUP2: run the setup, reset the one-time hints, uninstall (Tutorial_Setup2)
    if ns.SetupCard then ns.SetupCard(L) end

    local on = 0
    for _, m in ipairs(MODULE_ORDER) do
        if ZacUIDB.modules[m] then on = on + 1 end
    end

    -- NEED HELP (2026-11-08): Zac's Discord name, ready to copy
    -- (UIF_Dialogs UI.ShowContact)
    if UI.ShowContact then
        local card = L:Card("Need help?")
        L:Desc("Message Zac on Discord: " .. (ns.CONTACT_DISCORD or "Zac12")
            .. ". The button shows the name ready to copy.")
        local b = UI.Button(card, "Discord", { width = 120, onClick = function() UI.ShowContact() end,
            tooltip = "Shows Zac's Discord name selected, ready for Ctrl+C." })
        L:Flow({ b }, 8, 6)
        L:EndCard()
    end

    L:Card("At a glance")
    local stats = {
        { "Version",    ZUI.VERSION },
        { "Modules on", on .. " of " .. #MODULE_ORDER },
        { "Frames skinned this session", tostring(ns.SkinnedCount and ns.SkinnedCount() or 0) },
    }
    for _, pair in ipairs(stats) do
        L:Pair(pair[1], pair[2], 150, { gap = 7 })
    end
    L:EndCard()

    -- the newer-version notice (Core_VersionCheck); account-wide
    local VC = ns.VersionCheck
    if VC then
        L:Card("Updates")
        local cb = UI.Checkbox(L.current, "Tell me when a newer ZacUI is out", VC.NoticeOn(),
            function(on) VC.SetNotice(on) end,
            { tooltip = "ZacUI compares versions with your guild and group in the background. When someone "
                .. "has a newer one, one line in chat says so, once a session. Your version is still "
                .. "shared while this is off. /zacui version shows the newest one seen." })
        L:Row(cb, 17)
        L:Desc("One line in chat, once a session. Update with the CurseForge app.")
        L:EndCard()
    end

    -- this window: its opacity and what it does in a fight (Config_Window)
    if ns.ConfigWindowCard then ns.ConfigWindowCard(L) end

    L:Card("Quick actions")
    local bar = L.current
    local b1 = UI.Button(bar, "Rescan frames", { width = 120, onClick = Rescan,
        tooltip = "Walk every frame alive right now through the classifier. Safe to repeat - already-skinned frames are skipped." })
    local b2 = UI.Button(bar, "Reload UI", { width = 100, onClick = Reload,
        tooltip = "Some changes - anything that strips Blizzard artwork - can only be undone by reloading." })
    local b3 = UI.Button(bar, "Identify a frame", { width = 130,
        onClick = function()
            if ArmIdentify then ArmIdentify() end
            Print("Click any frame to identify it.")
        end,
        tooltip = "Arms /zacui id. The next thing you click prints its name and type in chat - useful when reporting something that skinned badly." })
    L:Flow({ b1, b2, b3 })
    L:Desc("Identify prints the name, type and parent of the next frame you "
        .. "click. That name is what /zacui inset and /zacui line take.")
    L:EndCard()

    -- the shared voice (one for every part that speaks)
    if ns.VoiceCard then ns.VoiceCard(L) end

    L:Card("Slash commands")
    for _, line in ipairs({
        { "/zui",             "open this window" },
        { "/zui <page>",      "jump straight to a page, e.g. /zui colors" },
        { "/zui tour",        "a guided tour of this window" },
        { "/zui setup",       "quick setup: the look, the parts, the basics" },
        { "/zacui <mod> on",  "turn a single module on or off" },
        { "/zacui rescan",    "re-run the classifier over every live frame" },
        { "/zacui inset <Frame> l r t b", "nudge a panel background that sits wrong" },
        { "/zacui line <Frame> <y>",      "move a panel's header hairline" },
        { "/zacui status",    "list every module and its state" },
        { "/zacui flavor",    "what runs on this game version (era, tbc, forever, retail, auto to test)" },
        { "/zacui version",   "your version and the newest one seen in your guild and group" },
        { "/zacui reset",     "back to shipped defaults" },
    }) do
        L:Pair(line[1], line[2], 215, { size = F.SMALL, keyColor = "gold", valueColor = "gray", gap = 6 })
    end
    L:EndCard()

    L:Card("Panel calibration")
    L:Desc("A few classic windows hide their real content edge behind "
        .. "transparent margin, so ZacUI's dark panel can sit slightly off. "
        .. "Both of these apply live and save straight away:")
    for _, line in ipairs({
        "/zacui inset QuestFrame 11 32 12 42",
        "/zacui line CharacterFrame -46",
        "/zacui inset <Frame> reset",
    }) do
        local fs = UI.Font(L.current, F.SMALL, { text = line, cat = "text", key = "gold" })
        fs:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.DESC_X, L.current._y)
        -- (a line as tall as the type: the settings window's is larger)
        L.current._y = L.current._y - math.max(15, math.ceil(fs:GetStringHeight() or 12) + 3)
    end
    L:Gap(4)
    L:EndCard()

    L:Card("Reset")
    local reset = UI.Button(L.current, "Reset all settings", { width = 150,
        onClick = function()
            UI.Confirm({
                title = "Reset ZacUI",
                text = "Every module state, colour, font choice, mover "
                    .. "position and panel calibration goes back to the "
                    .. "shipped defaults. This cannot be undone.",
                acceptText = "Reset everything",
                destructive = true,
                onAccept = function()
                    -- the reload FIRST, then the writes, inside the click
                    -- (WoW Forever; UIF_Dialogs' ns.AskReload)
                    Reload()
                    ZacUIDB.modules = {}
                    for m, v in pairs(ns.DEFAULT_MODULES) do ZacUIDB.modules[m] = v end
                    ZacUIDB.insets, ZacUIDB.lines = {}, {}
                    ZacUIDB.colors, ZacUIDB.palette = {}, {}
                    ZacUIDB.movers, ZacUIDB.tooltipPos = {}, nil
                    ZacUIDB.font = { name = nil, delta = 0, outline = nil }
                    ZacUIDB.look = nil
                    ZacUIDB.config = nil
                    -- "Everything" includes the first-run bookkeeping, or
                    -- a reset would silently keep declining the import
                    -- offer forever.
                    ZacUIDB.importPrompted, ZacUIDB.importedFrom = nil, nil
                    Print("Settings reset - reloading.")
                end,
            })
        end })
    L:Flow({ reset }, 8, 4)
    L:EndCard()
end)

-- ============================================================
-- MODULES
-- ============================================================
-- One page function serves all four module pages; the menu entry names
-- which group to draw. Adding a group is a data edit, not a new page.
RegisterPage("Modules", function(L, item)
    local group
    for _, g in ipairs(MODULE_GROUPS) do
        if g.key == item.group then group = g end
    end
    if not group then
        L:Header(item.label, "This group is empty.")
        return
    end

    L:Header(group.label, group.desc)

    L:Card("Everything in this group")
    local bar = UI.Holder(L.current)
    bar:SetSize(300, M.BUTTON_H)
    local checks = {}
    local function SetAll(state)
        for _, m in ipairs(group.modules) do
            if state then
                EnableModuleLive(m.key)
            else
                ZacUIDB.modules[m.key] = false
            end
            if checks[m.key] then checks[m.key]:SetChecked(state) end
        end
        if not state then
            ns.AskReload("Turned off. The game's own look comes back after a reload.")
        end
    end
    local allOn = UI.Button(bar, "Enable all", { width = 100,
        onClick = function() SetAll(true) end })
    allOn:SetPoint("LEFT")
    local allOff = UI.Button(bar, "Disable all", { width = 100,
        onClick = function() SetAll(false) end })
    allOff:SetPoint("LEFT", allOn, "RIGHT", 8, 0)
    L:Row(bar, M.BUTTON_H + 4)
    L:EndCard()

    L:Card(group.label)
    -- Rendered A-Z by label: the registry's hand order is a runtime
    -- concern (load/apply), but a settings list you SCAN wants the
    -- alphabet. Sorted copy - the registry itself is never reordered.
    local listed = {}
    for _, m in ipairs(group.modules) do listed[#listed + 1] = m end
    table.sort(listed, function(a, b)
        return tostring(a.label):lower() < tostring(b.label):lower()
    end)
    local Modules, MODULE_ADDON = ns.Modules, ns.MODULE_ADDON or {}
    -- a module whose part IS loaded but brought no code stood down for
    -- this game version (Retail has no Classic character sheet, quest log,
    -- battlemaster ...): its switch could do nothing, so it is not listed
    local Loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local function StoodDown(m)
        local part = MODULE_ADDON[m.key]
        return (not Modules[m.key]) and part and Loaded and Loaded(part) and true or false
    end
    for i = #listed, 1, -1 do
        if StoodDown(listed[i]) then table.remove(listed, i) end
    end
    for _, m in ipairs(listed) do
        local cb = UI.Checkbox(L.current, m.label,
            ZacUIDB.modules[m.key] and true or false,
            function(checked)
                if checked then
                    EnableModuleLive(m.key)
                else
                    ZacUIDB.modules[m.key] = false
                    ns.AskReload(m.label .. " is off. The game's own look comes back after a reload.")
                end
            end)
        checks[m.key] = cb
        L:Row(cb, 17)
        -- the module's code lives in a part that is not loaded: the switch
        -- is remembered, but nothing happens until that addon is on
        if not Modules[m.key] and MODULE_ADDON[m.key] then
            if cb.SetAlpha then cb:SetAlpha(0.5) end
            L:Desc("Needs '" .. MODULE_ADDON[m.key] .. "' - that addon is not loaded, so this does nothing right now.")
        elseif m.desc then
            L:Desc(m.desc)
        end
    end
    L:EndCard()

    L:Card("How toggling behaves")
    local note = UI.Font(L.current, F.DESC, {
        text = "Turning a module ON applies it immediately. Turning one OFF "
            .. "needs a reload, because skinning strips Blizzard's artwork "
            .. "and there is nothing left to put back - ZacUI will not "
            .. "pretend otherwise.",
        cat = "text", key = "gray",
        width = math.max(150, (L.current:GetWidth() or 420) - 30),
    })
    note:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.CONTROL_X, L.current._y)
    L.current._y = L.current._y - note:GetStringHeight() - 6
    L:EndCard()
end)

-- ============================================================
-- MOVERS
-- ============================================================
RegisterPage("Movers", function(L)
    L:Header("Movers",
        "Drag a placeholder to reposition the frame behind it, then click "
        .. "the button again to lock it.")

    if ns.Bars then
        L:Card("Action bars")
        local AB = ns.Bars
        local row = UI.Holder(L.current)
        row:SetSize(360, M.BUTTON_H)
        local unlock = UI.Button(row, AB.unlocked and "Lock bars" or "Unlock bars", { width = 130,
            onClick = function() AB.SetUnlocked(not AB.unlocked) if ns.RefreshConfig then ns.RefreshConfig() end end })
        unlock:SetPoint("LEFT")
        if AB.unlocked then unlock:SetActive(true) end
        local page = UI.Button(row, "Action bars page", { width = 130,
            onClick = function() if ns.OpenConfig then ns.OpenConfig("bars") end end })
        page:SetPoint("LEFT", unlock, "RIGHT", 8, 0)
        L:Row(row, M.BUTTON_H + 4)
        L:Desc("Every ZacUI bar gets a gold drag box while unlocked. Edit Mode (/zui edit) unlocks "
            .. "them too and lists each bar in its control box, with park and reset. Exact "
            .. "positions, nudging and per-bar settings are on the Action bars page.")
        L:EndCard()
    end

    L:Card("Frames")
    -- the tooltip's spot sits with every other spot (its look is on
    -- Screen > Tooltips)
    do
        local row = UI.Holder(L.current)
        row:SetSize(320, M.BUTTON_H)
        local move = UI.Button(row, "Tooltip", { width = 130, onClick = ToggleTipMover })
        move:SetPoint("LEFT")
        local reset = UI.Button(row, "Reset", { width = 70, onClick = function()
            ZacUIDB.tooltipPos = nil
            Print("Tooltip position reset to Blizzard default.")
        end })
        reset:SetPoint("LEFT", move, "RIGHT", 8, 0)
        L:Row(row, M.BUTTON_H + 4)
    end
    for _, mv in ipairs(MOVERS) do
        -- 1.15.9: Edit Mode owns whole HUD systems now. Rather than fight
        -- it and lose silently, the row says who is in charge.
        local frame = mv.getFrame and mv.getFrame()
        local managed = frame and ((frame.IsProtected and frame:IsProtected())
            or frame.system ~= nil)

        local row = UI.Holder(L.current)
        row:SetSize(320, M.BUTTON_H)
        local move = UI.Button(row, mv.label, { width = 130,
            onClick = function() ToggleMover(mv.key) end })
        move:SetPoint("LEFT")
        local reset = UI.Button(row, "Reset", { width = 70,
            onClick = function() ResetMover(mv.key) end })
        reset:SetPoint("LEFT", move, "RIGHT", 8, 0)
        if managed then
            -- (the game's own Edit Mode places it on this client)
            move:SetDisabled(true, "Placed by the game's Edit Mode on this game version.")
            reset:SetDisabled(true, "Placed by the game's Edit Mode on this game version.")
            local tag = UI.Font(row, F.SMALL, { text = "Edit Mode",
                cat = "text", key = "orange" })
            tag:SetPoint("LEFT", reset, "RIGHT", 8, 0)
        end
        L:Row(row, M.BUTTON_H + 4)
        if managed then
            L:Desc("This frame is managed by Edit Mode on this client. "
                .. "Move and scale it there (Esc > Edit Mode) - any saved "
                .. "ZacUI position is kept but stays dormant.")
        end
    end
    L:EndCard()
end)

-- ============================================================
-- TOOLTIPS (2026-10-28 tidy: these lived on the Movers page)
-- ============================================================
-- The look lives in ZacUIDB.tooltip and is drawn by Blz_Tooltip
-- (ns.TipLook). The preview is a tooltip of its own (Blizzard's tooltip
-- template) skinned, painted and filled by the same functions.
Kit.Keywords("tooltips", "scale size background backdrop opacity alpha transparent "
    .. "health bar texture height font title text fade animation appear offset "
    .. "target of target spell id guild")

local function TipCfgOf() return ns.TipCfg and ns.TipCfg() or {} end

local function BuildTipPreview(canvas, P)
    local tt = CreateFrame("GameTooltip", "ZacUIPreviewTooltip", canvas, "GameTooltipTemplate")
    ns.TipLook.Skin(tt)
    local bar = CreateFrame("StatusBar", nil, tt)
    bar:SetPoint("TOPLEFT", tt, "BOTTOMLEFT", 2, -1)
    bar:SetPoint("TOPRIGHT", tt, "BOTTOMRIGHT", -2, -1)
    bar:SetMinMaxValues(0, 4620)
    if ns.AddPixelBorder then ns.AddPixelBorder(bar) end
    P.store.tt, P.store.bar = tt, bar
end

local function UpdateTipPreview(canvas, P)
    local T = ns.TipLook
    local st, cfg, mode = P.store, TipCfgOf(), P.mode or "player"
    local tt, bar = st.tt, st.bar
    -- the fonts are Blizzard's own tooltip fonts: set them now (only when
    -- the module is on - off means Blizzard's tooltips are left alone)
    if ZacUIDB.modules and ZacUIDB.modules.tooltip then T.ApplyFonts(cfg) end
    if ns.Motion then ns.Motion.Stop(tt) end
    if tt.SetOwner then tt:SetOwner(canvas, "ANCHOR_NONE") end
    if tt.ClearLines then tt:ClearLines() end
    tt:ClearAllPoints()
    tt:SetPoint("CENTER", canvas, "CENTER", 0, 8)
    T.SampleLines(tt, mode, cfg)
    tt:Show()
    -- its dark panel a level under it, so the lines read on top
    if tt._zui_bg then
        if (tt:GetFrameLevel() or 0) < 1 then tt:SetFrameLevel(1) end
        tt._zui_bg:SetFrameLevel(math.max(0, tt:GetFrameLevel() - 1))
    end
    T.Paint(tt, cfg)
    if mode ~= "item" and cfg.unitBorder then
        T.TintUnit(tt, T.UnitColor(mode))
    else
        T.TintUnit(tt)
    end
    bar:SetShown(mode ~= "item")
    T.StyleBar(bar, cfg)
    local cur, maxv = 3100, 4620
    if mode == "enemy" then cur, maxv = 87, 100 end
    bar:SetMinMaxValues(0, maxv)
    bar:SetValue(cur)
    bar:SetStatusBarColor(T.BarColor(T.UnitColor(mode)))
    bar._zui_text:SetText(T.HealthText(cur, maxv, cfg))
    -- the pick hook: the health numbers -> their group (Text), the rest of
    -- the sample -> its look
    if ns.TagElement then
        ns.TagElement(bar._zui_text, "tooltip.health")
        ns.TagElement(tt, "tooltip.look")
    end
    -- the canvas is the tooltip (and its bar) at its real size; the strip
    -- scales it
    if P.Resize then
        local w, h = tt:GetWidth() or 0, tt:GetHeight() or 0
        if w < 20 or h < 20 then w, h = 220, 96 end
        local barH = bar:IsShown() and ((bar:GetHeight() or 0) + 1) or 0
        -- (the tooltip wears its own scale setting, as the real one does)
        local k = tt:GetScale() or 1
        tt:ClearAllPoints()
        tt:SetPoint("CENTER", canvas, "CENTER", 0, barH / 2)
        P.Resize((w + 6) * k, (h + barH + 6) * k)
    end
end

local function ReplayTipPreview(canvas, P)
    local spec = TipCfgOf().showAnim
    local tt = P.store.tt
    if ns.Motion and type(spec) == "table" and spec.style and spec.style ~= "none" then
        tt:Hide()
        ns.Motion.Play(tt, spec, "in")
    end
end

RegisterPage("Tooltips", function(L)
    L:Header("Tooltips", "How tooltips look, where they sit, and when unit tooltips stay out of the way.")
    if not (ZacUIDB.modules and ZacUIDB.modules.tooltip) then
        L:Notice("off", "The Tooltips module is off, so Blizzard's own tooltips are in use.", "Modules > HUD", "tooltip")
    end
    if not ns.TipLook then
        L:Notice("missing", "The tooltip module did not load.")
        return
    end
    if ns.CustomPick then
        ns.CustomPick.SetHandler("screen.tooltips", function(el)
            if el ~= "tooltip.health" and el ~= "tooltip.look" then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            ZacUIDB.config.tabs.tooltips = (el == "tooltip.health") and "text" or "look"
            ns.RefreshConfig()
        end)
    end
    L:Preview({
        key = "screen.tooltips", title = "Tooltip",
        width = 226, height = 104,
        modes = { { id = "player", label = "Player" }, { id = "enemy", label = "Enemy" },
                  { id = "item", label = "Item" } },
        modesLabel = "Show",
        build = BuildTipPreview, update = UpdateTipPreview, replay = ReplayTipPreview,
    })

    local function Tab_general(L)
        L:Card("When unit tooltips show")
        if type(ZacUIDB.tooltipHide) ~= "table" then ZacUIDB.tooltipHide = { combat = true, raid = true } end
        local tipCombat = UI.Checkbox(L.current, "Hide unit tooltips in combat",
            ZacUIDB.tooltipHide.combat ~= false,
            function(v) ZacUIDB.tooltipHide.combat = v and true or false end)
        L:Row(tipCombat, 17)
        local tipRaid = UI.Checkbox(L.current, "Hide unit tooltips inside raids",
            ZacUIDB.tooltipHide.raid ~= false,
            function(v) ZacUIDB.tooltipHide.raid = v and true or false end)
        L:Row(tipRaid, 17)
        L:Desc("Players, mobs and unit frames under the mouse; item, spell and button "
            .. "tooltips always show. Hold Shift while you point to see one anyway.")
        L:EndCard()

        L:Card("What they say")
        Kit.Check(L, "Show the unit's target", TipCfgOf, "showTarget",
            "A last line naming who the unit is targeting - in red when it is you.", { defaultOn = true })
        Kit.Check(L, "Spell ID on aura and spell tooltips", TipCfgOf, "spellId",
            "Buffs, debuffs, action buttons, the spellbook and spell links end with the spell's ID.",
            { defaultOn = true })
        Kit.Check(L, "Health numbers on the bar", TipCfgOf, "healthText",
            "\"4.6k / 4.6k  100%\" on the health bar, which grows to fit them.", { defaultOn = true })
        L:EndCard()
    end

    local function Tab_look(L)
        L:Card("Panel")
        Kit.Color(L, "Background", TipCfgOf, "bgColor", function()
            local c = ns.GetColor("ui", "windowBg")
            return c.r, c.g, c.b, 0.95
        end, { alpha = true })
        Kit.Color(L, "Border", TipCfgOf, "borderColor", Kit.Palette("ui", "border"), { alpha = true })
        Kit.Check(L, "Border in the unit's colour", TipCfgOf, "unitBorder",
            "Players in their class colour, creatures in their reaction colour.", { defaultOn = true })
        Kit.Slider(L, "Scale", TipCfgOf, "scale", { min = 50, max = 200, step = 5,
            get = function(v) return math.floor((v or 1) * 100 + 0.5) end,
            set = function(v) return v / 100 end,
            format = function(v) return v .. "%" end },
            "Every tooltip ZacUI skins, item comparisons included.")
        L:EndCard()

        L:Card("Health bar")
        Kit.Slider(L, "Height", TipCfgOf, "barHeight", { min = 0, max = 24, step = 1,
            format = function(v) return v == 0 and "Automatic" or (v .. " px") end },
            "Automatic is 11 px with the numbers on it and 6 px without.")
        local tex = UI.TexturePicker(L.current, { label = "Texture", width = 240,
            get = function() return TipCfgOf().barTexture end,
            set = function(name) TipCfgOf().barTexture = name end,
            color = function() return ns.TipLook.UnitColor("player") end })
        L:Add(tex, 8)
        local byUnit = type(TipCfgOf().barColor) ~= "table"
        local cb = UI.Checkbox(L.current, "Colour the bar by the unit", byUnit, function(v)
            TipCfgOf().barColor = (not v) and { r = 0.2, g = 0.8, b = 0.2 } or nil
            RefreshConfig()
        end)
        L:Row(cb, 17)
        if not byUnit then
            Kit.Color(L, "Bar colour", TipCfgOf, "barColor", function() return 0.2, 0.8, 0.2, 1 end)
        end
        L:EndCard()
    end

    local function Tab_text(L)
        local T = ns.TipLook
        local function Stock(obj)
            local p, s, f = T.StockFont(obj)
            return { fallbackFace = p, size = s or 12, outline = (f and f ~= "") and f or "none", shadow = true }
        end
        L:Card("Tooltip text")
        Kit.Font(L, "Title line", TipCfgOf, "headerFont", Stock("GameTooltipHeaderText"),
            { sample = "Zaccw <Petri Out>", defaultLabel = "Blizzard's tooltip font" })
        Kit.Font(L, "Other lines", TipCfgOf, "bodyFont", Stock("GameTooltipText"),
            { sample = "Level 60 Human Warrior", defaultLabel = "Blizzard's tooltip font",
              desc = "The small print (comparisons, set bonuses) follows two sizes smaller." })
        L:EndCard()

        L:Card("Health numbers")
        Kit.Font(L, "Font", TipCfgOf, "healthFont", T.HealthFontDefaults(), { sample = "3.1k / 4.6k  67%" })
        Kit.Color(L, "Colour", TipCfgOf, "healthColor", Kit.Palette("text", "normal"))
        -- how the numbers read and where they sit (cfg.formats.health /
        -- cfg.anchors.health; nothing saved = as always)
        local fg, fs = ns.CustomAccess(TipCfgOf, "formats", "health")
        local ag, as = ns.CustomAccess(TipCfgOf, "anchors", "health")
        UI.TextElement(L, { key = "tooltip.health",
            formatGet = fg, formatSet = fs, formatDefaults = T.HP_DEFAULT,
            formatKinds = { number = true, percent = true }, formatTokens = T.HP_TOKENS,
            formatSample = function(spec)
                return ns.FormatText(spec, T.HP_DEFAULT, { cur = 3120, max = 4600, deficit = 1480, pct = 67.8 }, T.HP_KINDS)
            end,
            anchorGet = ag, anchorSet = as, anchorDefaults = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
            targets = { { value = "tooltip", text = "The tooltip" } }, defaultTargetLabel = "The bar",
            anchorMin = -60, anchorMax = 60 })
        L:EndCard()
    end

    local function Tab_anim(L)
        L:Card("Appearing")
        Kit.Anim(L, "When a tooltip appears", TipCfgOf, "showAnim", { "none", "fade" },
            "A short fade as a tooltip comes up. None is instant, as it has always been.",
            { default = { style = "none", duration = 0.15 } })
        L:EndCard()
    end

    local function Tab_pos(L)
        L:Card("Where it sits")
        Kit.Buttons(L, {
            { "Move tooltip", 130, ToggleTipMover },
            { "Reset", 70, function()
                ZacUIDB.tooltipPos = nil
                Print("Tooltip position reset to Blizzard default.")
            end },
        })
        L:Desc("Tooltips that would sit in Blizzard's corner go to this spot instead. "
            .. "Reset puts them back in the corner.")
        local follow = TipCfgOf().cursor and true or false
        Kit.Check(L, "Follow the cursor instead", TipCfgOf, "cursor", nil,
            { after = function() RefreshConfig() end })
        local sx = Kit.Slider(L, "Beside the cursor", TipCfgOf, "cursorX", { min = -60, max = 60, step = 1,
            format = function(v) return v .. " px" end })
        local sy = Kit.Slider(L, "Above the cursor", TipCfgOf, "cursorY", { min = -60, max = 60, step = 1,
            format = function(v) return v .. " px" end })
        UI.SetEnabled(sx, follow, 'Needs "Follow the cursor instead" turned on.')
        UI.SetEnabled(sy, follow, 'Needs "Follow the cursor instead" turned on.')
        L:EndCard()
    end

    local function Tab_adv(L)
        L:Card("Reset")
        Kit.Buttons(L, { { "Reset the look", 130, function()
            local t = TipCfgOf()
            for _, k in ipairs({ "scale", "cursorX", "cursorY", "barHeight", "barTexture", "bgColor",
                                 "borderColor", "barColor", "healthColor", "headerFont", "bodyFont",
                                 "healthFont", "showAnim" }) do t[k] = nil end
            ns.TipCfg()
            ns.SettingsChanged("reset")
            RefreshConfig()
        end, "Colours, fonts, the bar, scale, cursor offsets and the animation. "
            .. "What shows and when stays as it is." } })
        L:EndCard()
    end

    L:Tabs({
        { id = "general", label = "General",   build = Tab_general },
        { id = "look",    label = "Look",      build = Tab_look },
        { id = "text",    label = "Text",      build = Tab_text },
        { id = "anim",    label = "Animation", build = Tab_anim },
        { id = "pos",     label = "Position",  build = Tab_pos },
        { id = "adv",     label = "Advanced",  build = Tab_adv },
    })
end)

-- ============================================================
-- BUFFS (2026-10-28 tidy: this lived on the Movers page)
-- ============================================================
-- The look lives in ZacUIDB.auraStyle and is drawn by Blz_Auras
-- (ns.BuffLook); the row length and the consolidation switch keep their
-- old top-level keys. The preview is a row of sample buttons dressed by
-- the module's own Style/PaintTimer, with fake auras counting down.
Kit.Keywords("buffs", "icon size spacing gap grow direction left right up down timer "
    .. "duration countdown time left stack stacks count border thickness debuff dispel "
    .. "magic curse poison disease colour color font zoom crop running out expiring "
    .. "alert pulse flash weapon enchant")

-- one of each way the time reads (hours, minutes, a minute and a bit,
-- running out, running out with stacks): with the enchant, one row of the
-- default six, and the debuffs under them, as on screen
local BUFF_FAKE = {
    { icon = "Interface\\Icons\\Spell_Holy_WordFortitude", left = 1795 },
    { icon = "Interface\\Icons\\Ability_Warrior_BattleShout", left = 95 },
    { icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", left = 6900 },
    { icon = "Interface\\Icons\\Spell_Holy_Renew", left = 14 },
    { icon = "Interface\\Icons\\Spell_Holy_BlessingOfStrength", left = 9, count = 3 },
}
local DEBUFF_FAKE = {
    { icon = "Interface\\Icons\\Ability_Warrior_Sunder", left = 27, count = 5, tint = { 0.8, 0, 0 } },
    { icon = "Interface\\Icons\\Spell_Shadow_UnholyStrength", left = 110, tint = { 0.6, 0, 1 } },
    { icon = "Interface\\Icons\\Ability_Rogue_DualWeild", left = 8, count = 2, tint = { 0, 0.6, 0 } },
    { icon = "Interface\\Icons\\Spell_Frost_FrostNova", left = 6, tint = { 0.2, 0.6, 1 } },
}
local ENCHANT_FAKE = { icon = "Interface\\Icons\\INV_Stone_02", left = 1700 }
-- the hours-long one is a world buff (Rallying Cry); TBC has none that
-- work at its level (Core_Flavor), so a flask stands in there. (Asked when
-- the preview is built: this file loads before the game version is fixed.)
local BUFF_FAKE_TBC3 = { icon = "Interface\\Icons\\INV_Potion_62", left = 6900 }
local BUFF_FAKE_ERA3 = BUFF_FAKE[3]
local function VersionBuffFake()
    BUFF_FAKE[3] = (ns.Flavor and ns.Flavor() == "tbc") and BUFF_FAKE_TBC3 or BUFF_FAKE_ERA3
end

local function BuffCfg() return ns.BuffLook and ns.BuffLook.Cfg() or {} end
-- the state the Buffs page's state editor was on, across rebuilds
local AURA_STATE_PICK = {}

local function BuildBuffPreview(canvas, P)
    VersionBuffFake()
    local BL = ns.BuffLook
    local st = P.store
    st.buffs, st.debuffs = {}, {}
    for i, a in ipairs(BUFF_FAKE) do
        st.buffs[i] = BL.NewSample(canvas, "buff")
        st.buffs[i]._zFake = a
    end
    for i, a in ipairs(DEBUFF_FAKE) do
        st.debuffs[i] = BL.NewSample(canvas, "debuff")
        st.debuffs[i]._zFake = a
    end
    st.enchant = BL.NewSample(canvas, "enchant")
    st.enchant._zFake = ENCHANT_FAKE
    st.all = {}
    for _, b in ipairs(st.buffs) do st.all[#st.all + 1] = b end
    for _, b in ipairs(st.debuffs) do st.all[#st.all + 1] = b end
    st.all[#st.all + 1] = st.enchant
    for _, b in ipairs(st.all) do
        b._zLeft = b._zFake.left
        BL.FillSample(b, b._zFake)
    end
    -- the clock: fake timers run down (and start again) while the dock is
    -- on screen; an OnUpdate on a sample-only frame stops when it hides
    local clock = CreateFrame("Frame", nil, canvas)
    st.clock = clock
    local acc = 0
    clock:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.2 then return end
        local step = acc
        acc = 0
        local cfg = BL.Cfg()
        for _, b in ipairs(st.all) do
            b._zLeft = b._zLeft - step
            if b._zLeft <= 0 then b._zLeft = b._zFake.left end
            b.timeLeft = b._zLeft
            BL.PaintTimer(b, cfg)
        end
    end)
end

local function UpdateBuffPreview(canvas, P)
    local BL = ns.BuffLook
    local st = P.store
    local cfg = BL.Cfg()
    local perRow = (ZacUIDB.buffsPerRow and ZacUIDB.buffsPerRow >= 1) and ZacUIDB.buffsPerRow or 6
    -- buffs (and the enchant, which Blizzard puts first) from the corner
    -- the growth starts at; debuffs in their own block under them
    local _, _, cw, ch, xMul, yMul = BL.SampleOffset(0, perRow, cfg)
    local hx = (xMul < 0) and "RIGHT" or "LEFT"
    local vy = (yMul < 0) and "TOP" or "BOTTOM"
    -- the buffs block, and the debuffs block under it, as on screen (the
    -- debuff row hangs a gap under the buff rows, from the same corner)
    local edge = 6
    local GAP_Y = 12
    local pad = select(1, BL.Grid(cfg, { iconPadding = 5 }))
    local function Place(list, startY)
        for i, b in ipairs(list) do
            local x, y = BL.SampleOffset(i - 1, perRow, cfg)
            b:ClearAllPoints()
            b:SetSize(cw, ch)
            b.Icon:SetSize(cw, cw)
            b:SetPoint(vy .. hx, canvas, vy .. hx, (xMul < 0 and -edge or edge) + x,
                (yMul < 0 and -startY or startY) + y)
        end
        local cols = math.min(#list, perRow)
        local rows = math.ceil(#list / perRow)
        return cols * cw + (cols - 1) * pad, rows * ch + (rows - 1) * pad
    end
    local row1 = { st.enchant }
    for _, b in ipairs(st.buffs) do row1[#row1 + 1] = b end
    local w1, h1 = Place(row1, edge)
    local w2, h2 = Place(st.debuffs, edge + h1 + GAP_Y)
    if P.Resize then P.Resize(2 * edge + math.max(w1, w2), 2 * edge + h1 + GAP_Y + h2) end
    for _, b in ipairs(st.all) do
        BL.FillSample(b, b._zFake)
        b.timeLeft = b._zLeft
        BL.Style(b, cfg)
        BL.PaintTimer(b, cfg)
    end
end

local function ReplayBuffPreview(canvas, P)
    local BL = ns.BuffLook
    local st = P.store
    local cfg = BL.Cfg()
    -- the short ones restart just above the red line, so the running-out
    -- alert is seen starting
    for _, b in ipairs(st.all) do
        if b._zFake.left < 30 then
            b._zLeft = (tonumber(cfg.urgentAt) or 10) + 1.5
        end
        b._zAlerting = nil
        if ns.Motion and b._zTimerHolder then ns.Motion.Stop(b._zTimerHolder) end
        b.timeLeft = b._zLeft
        BL.PaintTimer(b, cfg)
    end
end

RegisterPage("Buffs", function(L)
    local BL = ns.BuffLook
    L:Header("Buffs", "Your buff and debuff rows by the minimap: how many to a row, "
        .. "how big, which way they grow, and how the time left reads.")
    if not (ZacUIDB.modules and ZacUIDB.modules.auras) then
        L:Notice("off", "The Buffs module is off, so Blizzard's own buff buttons are in use.", "Modules > HUD", "auras")
    end
    if not BL then
        L:Notice("missing", "The buff module did not load.")
        return
    end
    L:Preview({
        key = "screen.buffs", title = "Buffs and debuffs",
        width = 380, height = 56,
        build = BuildBuffPreview, update = UpdateBuffPreview, replay = ReplayBuffPreview,
    })

    local function Restyle()
        if ns.ApplyAuraStride then ns.ApplyAuraStride() end
    end

    local function Tab_general(L)
        L:Card("Buffs")
        local expand = UI.Checkbox(L.current, "Show every buff separately",
            ZacUIDB.buffsAlwaysExpanded ~= false,
            function(v)
                ZacUIDB.buffsAlwaysExpanded = v and true or false
                if ns.ApplyBuffConsolidation then ns.ApplyBuffConsolidation() end
                if not v then
                    ns.AskReload("Consolidated buffs come back after a reload.")
                end
            end)
        L:Row(expand, 17)
        L:Desc("Blizzard's Consolidate Buffs folds every long raid buff behind "
            .. "one icon and shows them in a flyout when you hover it - which "
            .. "is why they read as a single stack. This turns that off "
            .. "so each buff keeps its own slot in the row.")
        Kit.Check(L, "Show the time left", BuffCfg, "showTimer",
            "The countdown on each icon. Off leaves just the icons.", { defaultOn = true })
        Kit.Check(L, "Show stack counts", BuffCfg, "showCount",
            "The number on an aura that stacks.", { defaultOn = true })
        L:EndCard()
        -- which of them show: the aura filter (off until it is changed)
        local AF = ns.AuraFilter
        if AF and AF.PanelFor and AF.Def("player_buffs") then
            ns._afBuffPick = ns._afBuffPick or {}
            AF.PanelFor(L, { "player_buffs", "player_debuffs" }, ns._afBuffPick)
        end
    end

    local function Tab_look(L)
        L:Card("Icons")
        Kit.Slider(L, "Icon size", BuffCfg, "iconSize",
            { min = 16, max = 64, step = 1, after = Restyle,
              format = function(v) return v == 30 and "30 px (Blizzard's)" or (v .. " px") end })
        Kit.Slider(L, "Icon zoom", BuffCfg, "zoom",
            { min = 0, max = 30, step = 1, format = function(v) return v .. "%" end },
            "How much of each icon's own edge is cropped away. 8% hides Blizzard's baked-in border.")
        Kit.Slider(L, "Spacing", BuffCfg, "spacing",
            { min = -1, max = 20, step = 1, after = Restyle,
              format = function(v) return v < 0 and "Blizzard's" or (v .. " px") end },
            "The gap between icons, across and down.")
        L:EndCard()

        L:Card("Border")
        Kit.Slider(L, "Border thickness", BuffCfg, "borderSize",
            { min = 0, max = 4, step = 1, format = function(v) return v == 0 and "None" or (v .. " px") end })
        Kit.Color(L, "Border colour", BuffCfg, "borderColor", Kit.Palette("ui", "border"), { alpha = true })
        Kit.Check(L, "Colour debuffs by type", BuffCfg, "debuffColors",
            "Magic blue, curse purple, poison green, disease brown - the colour that says who can remove it.",
            { defaultOn = true })
        Kit.Color(L, "Weapon enchant border", BuffCfg, "enchantColor", Kit.Palette("ui", "border"),
            { desc = "Poisons, oils and sharpening stones on your weapons." })
        L:EndCard()

        L:Card("Time left colours")
        Kit.Color(L, "Plenty of time", BuffCfg, "timerColor", Kit.Palette("text", "normal"))
        Kit.Color(L, "Running low", BuffCfg, "warnColor", Kit.Palette("text", "orange"))
        Kit.Slider(L, "Running low below", BuffCfg, "warnAt",
            { min = 10, max = 600, step = 10, format = function(v)
                return v >= 60 and string.format("%dm%s", math.floor(v / 60), (v % 60 > 0) and (" " .. (v % 60) .. "s") or "") or (v .. "s") end })
        Kit.Color(L, "About to run out", BuffCfg, "urgentColor", Kit.Palette("text", "red"))
        Kit.Slider(L, "About to run out below", BuffCfg, "urgentAt",
            { min = 0, max = 60, step = 1, format = function(v) return v .. "s" end })
        L:EndCard()

        -- per-state looks (auraStyle.states: the three time-left states)
        L:Card("Time left states")
        local sg, ss = ns.CustomAccess(BuffCfg, "states", nil, Restyle)
        local se = UI.StateEditor(L.current, { width = UI.CardInnerWidth(L), get = sg, set = ss,
            states = ns.AURA_STATE_LIST or {}, remember = AURA_STATE_PICK, fields = { textColor = true, color = true },
            defaults = function() return ns.AuraStateDefaults and ns.AuraStateDefaults() or {} end })
        L:Add(se, 6)
        if ns.CustomPick then ns.CustomPick.RegisterGroup("buffs.icon", se) end
        L:Desc("Text colour is the time left, colour tints the icon. Unset fields keep the colours above.")
        L:EndCard()
    end

    -- the fine placement of one aura text: ZacUI's anchor picker over
    -- auraStyle.anchors.<key>, on top of the preset above it
    local function AuraSpot(L, key)
        local targets = {}
        for _, k in ipairs({ "icon", "button", "timer", "count" }) do
            if k ~= key then targets[#targets + 1] = { value = k, text = ns.AURA_TEXT_LABELS and ns.AURA_TEXT_LABELS[k] or k } end
        end
        local get, set = ns.CustomAccess(BuffCfg, "anchors", key, Restyle)
        UI.TextElement(L, { key = "buffs." .. key, anchorGet = get, anchorSet = set, targets = targets,
            anchorDefaults = function() return ns.AuraTextDefaults and ns.AuraTextDefaults(BuffCfg(), key) end,
            defaultTargetLabel = "The icon", anchorMin = -40, anchorMax = 40 })
        L:Desc("Any corner of the icon or the button, or next to the other text. Reset goes back to the spot above.")
    end

    if ns.CustomPick then
        ns.CustomPick.SetHandler("screen.buffs", function(el)
            if el ~= "buffs.timer" and el ~= "buffs.count" and el ~= "buffs.icon" then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            -- the icon itself: its states are on Look
            ZacUIDB.config.tabs.buffs = (el == "buffs.icon") and "look" or "text"
            RefreshConfig()
        end)
    end

    local function Tab_text(L)
        L:Card("Time left")
        Kit.Font(L, "Time font", BuffCfg, "timerFont", BL.TimerDefaults(),
            { sample = "29m  4m  12", maxSize = 24 })
        Kit.Choice(L, "Where it sits", BuffCfg, "timerPos", {
            { text = "Bottom edge", value = "edge" },
            { text = "Centred on the icon", value = "center" },
            { text = "Under the icon", value = "below" },
            { text = "Top edge", value = "top" },
            { text = "Inside the icon, at the bottom", value = "inside" },
        }, nil, { after = Restyle })
        -- HD polish: the dark sweep as the time runs out (ZacUI look)
        Kit.Choice(L, "Dark sweep as it runs out", BuffCfg, "swipe", {
            { text = "Short buffs and debuffs (5 minutes or less)", value = "short" },
            { text = "Every buff and debuff", value = "all" },
            { text = "Off", value = "off" },
        }, nil, { after = Restyle })
        Kit.Slider(L, "Nudge across", BuffCfg, "timerX", { min = -15, max = 15, step = 1,
            format = function(v) return v .. " px" end })
        Kit.Slider(L, "Nudge up", BuffCfg, "timerY", { min = -15, max = 15, step = 1,
            format = function(v) return v .. " px" end })
        AuraSpot(L, "timer")
        L:EndCard()

        L:Card("Stack count")
        Kit.Font(L, "Count font", BuffCfg, "countFont", { size = 14, outline = "outline", shadow = false },
            { sample = "3  5  20", maxSize = 24, defaultLabel = "Blizzard's number font" })
        Kit.Color(L, "Count colour", BuffCfg, "countColor", function() return 1, 1, 1, 1 end)
        Kit.Choice(L, "Corner", BuffCfg, "countPos", {
            { text = "Top right", value = "TOPRIGHT" },
            { text = "Top left", value = "TOPLEFT" },
            { text = "Bottom right", value = "BOTTOMRIGHT" },
            { text = "Bottom left", value = "BOTTOMLEFT" },
        })
        Kit.Slider(L, "Nudge across", BuffCfg, "countX", { min = -15, max = 15, step = 1,
            format = function(v) return v .. " px" end })
        Kit.Slider(L, "Nudge up", BuffCfg, "countY", { min = -15, max = 15, step = 1,
            format = function(v) return v .. " px" end })
        AuraSpot(L, "count")
        L:EndCard()
    end

    local function Tab_anim(L)
        L:Card("Running out")
        Kit.Anim(L, "When a buff is about to run out", BuffCfg, "alertAnim",
            { "none", "pulse", "flash", "bounce", "pop" },
            "Plays on the time left once it drops under the 'about to run out' line (Look tab), "
            .. "and repeats until the buff is refreshed or gone. None is how it has always been.",
            { default = { style = "none", duration = 0.6, loop = true } })
        L:EndCard()
    end

    local function Tab_pos(L)
        L:Card("Rows")
        local stride = UI.Slider(L.current, {
            width = 220, min = 0, max = 16, step = 1,
            value = ZacUIDB.buffsPerRow or 0,
            label = "Buffs per row",
            format = function(v)
                if v < 1 then return "Blizzard default" end
                return tostring(v)
            end,
            onChange = function(v)
                ZacUIDB.buffsPerRow = (v >= 1) and v or nil
                if ns.ApplyAuraStride then ns.ApplyAuraStride() end
            end,
        })
        L:Row(stride, 40)
        L:Desc("Blizzard wraps buffs to the width worked out once from the gap beside "
            .. "the minimap, so a moved buff frame piles its icons into a narrow block. "
            .. "Zero leaves Blizzard's wrapping alone; Edit Mode's Icon Limit is the same setting.")
        Kit.Choice(L, "Grow across", BuffCfg, "growX", {
            { text = "Blizzard's (Edit Mode)", value = "auto" },
            { text = "To the left", value = "left" },
            { text = "To the right", value = "right" },
        }, nil, { after = Restyle })
        Kit.Choice(L, "New rows", BuffCfg, "growY", {
            { text = "Blizzard's (Edit Mode)", value = "auto" },
            { text = "Below", value = "down" },
            { text = "Above", value = "up" },
        }, nil, { after = Restyle })
        L:EndCard()

        L:Card("Where they sit")
        Kit.Mover(L, "buffs", "buffs")
        L:EndCard()
    end

    local function Tab_adv(L)
        L:Card("Reset")
        Kit.Buttons(L, { { "Reset the look", 130, function()
            ZacUIDB.auraStyle = nil
            ns.SettingsChanged("reset")
            if ns.BuffLook then ns.BuffLook.Changed() end
            RefreshConfig()
        end, "Every setting on this page except buffs per row and the consolidation switch." } })
        L:EndCard()
    end

    L:Tabs({
        { id = "general", label = "General",   build = Tab_general },
        { id = "look",    label = "Look",      build = Tab_look },
        { id = "text",    label = "Text",      build = Tab_text },
        { id = "anim",    label = "Animation", build = Tab_anim },
        { id = "pos",     label = "Position",  build = Tab_pos },
        { id = "adv",     label = "Advanced",  build = Tab_adv },
    })
end)

-- ============================================================
-- BAGS
-- ============================================================
-- The look lives in ZacUIDB.bags (beside columns) and is drawn by
-- Zacui_Bags (ns.BagLook). The preview is a small bag window of fake
-- items, each slot dressed and painted by the bag's own functions.
Kit.Keywords("bags", "slot slots size spacing gap border quality colour color quest empty "
    .. "opacity background window font count stack footer money animation open close fade position anchor corner format gold silver copper")

-- The whole bag window as it opens with a typical set of bags (84 slots:
-- a backpack and four 16-slot bags), its columns from the settings. The
-- first slots carry one of everything: a potion (what the search finds),
-- every quality, a quest item, a locked slot and an empty one; the rest
-- is ordinary loot with a few gaps. It is taller than the strip, so the
-- strip shows its top part at the real size.
local BAG_SLOTS = 84
local BAG_FAKE = {
    { icon = "Interface\\Icons\\INV_Potion_54", quality = 1, count = 5, name = "Major Healing Potion" },
    { icon = "Interface\\Icons\\INV_Misc_Bone_ElfSkull_01", quality = 0, name = "Skull" },
    { icon = "Interface\\Icons\\INV_Sword_04", quality = 2, name = "Sword" },
    { icon = "Interface\\Icons\\INV_Misc_Bag_10", quality = 3, name = "Onyxia Hide Backpack" },
    { icon = "Interface\\Icons\\INV_Helmet_36", quality = 4, name = "Lionheart Helm" },
    { icon = "Interface\\Icons\\INV_Hammer_Unique_Sulfuras", quality = 5, name = "Sulfuras" },
    { icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", quality = 4, quest = true, name = "Head of Onyxia" },
    { icon = "Interface\\Icons\\INV_Misc_Food_19", quality = 1, count = 8, locked = true, name = "Bread" },
    false,
    { icon = "Interface\\Icons\\INV_Potion_32", quality = 1, count = 3, name = "Elixir of the Mongoose potion" },
    { icon = "Interface\\Icons\\INV_Misc_Rune_01", quality = 1, name = "Hearthstone" },
    { icon = "Interface\\Icons\\INV_Fabric_Silk_02", quality = 1, count = 20, name = "Runecloth" },
    { icon = "Interface\\Icons\\INV_Misc_MonsterScales_11", quality = 1, count = 4, name = "Juju Power" },
    { icon = "Interface\\Icons\\INV_Ore_Thorium_02", quality = 1, count = 12, name = "Thorium Ore" },
    false, false,
}

local function BagCfgOf() return ns.BagLook and ns.BagLook.Cfg() or (ZacUIDB.bags or {}) end

local function BuildBagPreview(canvas, P)
    local BL, UIF = ns.BagLook, ns.UI
    local st = P.store
    local win = CreateFrame("Frame", nil, canvas)
    UIF.Fill(win, "ui", "windowBg", 0.97)
    UIF.Border(win, "ui", "border")
    win._zPaint = function(self) UIF.PaintBox(self) BL.PaintWindow(self) end
    local bar = CreateFrame("Frame", nil, win)
    bar:SetHeight(20)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    UIF.Fill(bar, "ui", "headerBg")
    bar._zPaint = UIF.PaintBox
    local title = UIF.Font(bar, UIF.F.LABEL, { text = "Bags", cat = "text", key = "gold" })
    title:SetPoint("LEFT", 8, 0)
    st.win, st.bar = win, bar
    st.free = UIF.Font(win, UIF.F.SMALL, { cat = "text", key = "gray" })
    st.free:SetPoint("BOTTOMLEFT", 8, 5)
    st.money = UIF.Font(win, UIF.F.SMALL, { justify = "RIGHT" })
    st.money:SetPoint("BOTTOMRIGHT", -8, 5)
    st.slots = {}
    for i = 1, BAG_SLOTS do st.slots[i] = BL.NewSample(win) end
    -- the footer's spots (a saved anchor goes on top) and the pick hook
    st.footDef = { free = { point = "BOTTOMLEFT", to = win, relPoint = "BOTTOMLEFT", x = 8, y = 5 },
        money = { point = "BOTTOMRIGHT", to = win, relPoint = "BOTTOMRIGHT", x = -8, y = 5, justify = "RIGHT" } }
    st.footTo = function(k)
        if k == "window" then return win elseif k == "free" then return st.free elseif k == "money" then return st.money end
    end
    if ns.TagElement then
        ns.TagElement(st.free, "bags.free") ns.TagElement(st.money, "bags.money")
        for _, b in ipairs(st.slots) do ns.TagElement(b._zCount, "bags.count") end
    end
end

-- the item in slot i: the curated first ones, then ordinary loot
-- (the stackables again) with every fifth slot empty
local function BagItem(i)
    if i <= #BAG_FAKE then return BAG_FAKE[i] end
    if i % 5 == 0 then return false end
    return BAG_FAKE[10 + (i % 5)] or false
end

local function UpdateBagPreview(canvas, P)
    local BL = ns.BagLook
    local st, cfg = P.store, BagCfgOf()
    local size, gap = BL.SlotSize(), BL.SlotGap()
    local cols = math.max(4, tonumber(cfg.columns) or 10)
    local searching = (P.mode or "normal") == "search"
    local top, foot, pad = 26, 20, 8
    local n = BAG_SLOTS
    for i = 1, n do
        local it = BagItem(i)
        local btn = st.slots[i]
        btn:Show()
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        btn:ClearAllPoints()
        btn:SetSize(size, size)
        btn:SetPoint("TOPLEFT", st.win, "TOPLEFT", pad + col * (size + gap), -(top + row * (size + gap)))
        local item = it or nil
        if item then
            item.link = item.link or item.name
            btn._zCount:SetText((item.count and item.count > 1) and tostring(item.count) or "")
        else
            btn._zCount:SetText("")
        end
        local faded = searching and not (item and item.name:lower():find("potion", 1, true))
        BL.Style(btn, cfg)
        BL.Paint(btn, item, item and item.quest or false, faded)
    end
    local rows = math.ceil(n / cols)
    local w = pad * 2 + cols * size + (cols - 1) * gap
    local h = top + rows * size + (rows - 1) * gap + foot + 4
    st.win:SetSize(w, h)
    -- the canvas is the window at its real size; the strip scales it
    st.win:SetScale(1)
    st.win:ClearAllPoints()
    st.win:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    if P.Resize then P.Resize(w + 8, h + 8) end
    st.win:_zPaint()
    st.bar:_zPaint()
    st.free:SetText(searching and "Searching: potion" or "15 / 84 free")
    local mf = type(cfg.formats) == "table" and cfg.formats.money
    st.money:SetText((mf and BL.MoneyText) and BL.MoneyText(12345678, cfg) or "1234|cffffd700g|r 56|cffc7c7cfs|r")
    BL.StyleFooter({ st.free, st.money })
    if BL.PlaceFooterText and (type(cfg.anchors) == "table" or st.footMoved) then
        st.footMoved = type(cfg.anchors) == "table" or nil
        BL.PlaceFooterText(st.free, "free", cfg, st.footDef.free, st.footTo)
        BL.PlaceFooterText(st.money, "money", cfg, st.footDef.money, st.footTo)
    end
end

local function ReplayBagPreview(canvas, P)
    local spec = BagCfgOf().openAnim
    if ns.Motion and type(spec) == "table" and spec.style and spec.style ~= "none" then
        P.store.win:Hide()
        ns.Motion.Play(P.store.win, spec, "in")
    end
end

RegisterPage("Bags", function(L)
    -- a sample's text picked in the preview: its spot
    if ns.CustomPick then
        ns.CustomPick.SetHandler("windows.bags", function(el)
            if type(el) ~= "string" or not el:match("^bags%.") then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            ZacUIDB.config.tabs.bags = "text"
            ns.RefreshConfig()
        end)
    end
    L:Header("Bags",
        "ZacUI's combined inventory: every bag in one window, with search, "
        .. "sorting and quality borders.")

    local on = ZacUIDB.modules.inventory and true or false
    ZacUIDB.bags = ZacUIDB.bags or { columns = 10 }
    local BL = ns.BagLook
    local function Relayout()
        local views = ns.BagViews
        if views then
            for _, view in pairs(views) do view:Refresh() end
        end
    end

    if BL then
        L:Preview({
            key = "windows.bags", title = "Bag window",
            width = 440, height = 420,
            -- a full bag is taller than the strip: its top rows at the
            -- real size read better than every row shrunk
            overflow = "clip",
            modes = { { id = "normal", label = "Open" }, { id = "search", label = "Searching" } },
            build = BuildBagPreview, update = UpdateBagPreview, replay = ReplayBagPreview,
        })
    end

    local function Tab_general(L)
        L:Card("Combined bag")
        local cb = UI.Checkbox(L.current, "Use ZacUI's combined bag", on,
            function(checked)
                if checked then
                    EnableModuleLive("inventory")
                else
                    ZacUIDB.modules.inventory = false
                    ns.AskReload("The combined bag is off. The game's own bags come back after a reload.")
                end
            end)
        L:Row(cb, 17)
        L:Desc("Replaces Blizzard's one-window-per-bag layout. Turning it off "
            .. "needs a reload, because the bag keys stay pointed at ZacUI's "
            .. "window until the originals are restored at load.")

        -- Honesty about the one situation where this module does nothing.
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        local rival
        for _, other in ipairs({ "Baganator", "Bagnon", "AdiBags", "ArkInventory",
                                 "Baggins", "OneBag3" }) do
            local ok, res = pcall(isLoaded, other)
            if ok and res then rival = other end
        end
        if rival then
            L:Gap(2)
            local warn = UI.Font(L.current, F.DESC, {
                text = rival .. " is loaded and does the same job, so ZacUI's bag "
                    .. "stays out of the way. Disable one of them to choose.",
                cat = "text", key = "orange",
                width = math.max(150, (L.current:GetWidth() or 420) - 44) })
            warn:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.DESC_X, L.current._y)
            L.current._y = L.current._y - warn:GetStringHeight() - 6
        end
        L:EndCard()

        L:Card("Searching")
        L:Desc("Type in the bag's search box to fade everything that does not "
            .. "match. It matches the item name, its type and its subtype, so "
            .. "\"cloth\", \"potion\" and \"herb\" all work. A few single words "
            .. "are treated as filters instead:")
        for _, line in ipairs({
            { "quest", "items tied to a quest you are on" },
            { "equip", "anything you can wear or wield" },
            { "junk",  "grey items" },
            { "uncommon / rare / epic", "by quality" },
        }) do
            L:Pair(line[1], line[2], 150, { indent = M.DESC_X, size = F.SMALL, keyColor = "gold",
                valueColor = "gray", gap = 6 })
        end
        L:Gap(4)
        L:EndCard()
    end

    local function Tab_look(L)
        L:Card("Grid")
        Kit.Slider(L, "Columns", BagCfgOf, "columns", { min = 4, max = 20, step = 1, after = Relayout },
            "The window resizes itself to whatever grid this produces, so a "
            .. "wide bag is short and a narrow one is tall.")
        Kit.Slider(L, "Slot size", BagCfgOf, "slotSize", { min = 20, max = 64, step = 1, after = Relayout,
            format = function(v) return v .. " px" end })
        Kit.Slider(L, "Spacing", BagCfgOf, "spacing", { min = 0, max = 20, step = 1, after = Relayout,
            format = function(v) return v .. " px" end })
        L:EndCard()

        L:Card("Slots")
        Kit.Color(L, "Slot colour", BagCfgOf, "slotColor", Kit.Palette("ui", "elementBg"))
        local pct = { get = function(v) return math.floor((v or 0) * 100 + 0.5) end,
                      set = function(v) return v / 100 end, format = function(v) return v .. "%" end }
        Kit.Slider(L, "Empty slot opacity", BagCfgOf, "emptyAlpha",
            { min = 0, max = 100, step = 5, get = pct.get, set = pct.set, format = pct.format })
        Kit.Slider(L, "Filled slot opacity", BagCfgOf, "filledAlpha",
            { min = 0, max = 100, step = 5, get = pct.get, set = pct.set, format = pct.format })
        Kit.Color(L, "Border colour", BagCfgOf, "borderColor", Kit.Palette("ui", "border"), { alpha = true })
        Kit.Check(L, "Quality colours on the border", BagCfgOf, "qualityBorders",
            "Green, blue, purple and orange edges for uncommon items and up.", { defaultOn = true })
        -- (2026-11-10, the bags mock)
        Kit.Check(L, "Gold edge on new items", BagCfgOf, "newItemRing",
            "An item you just picked up wears the accent colour on its edge until the mouse has been over it.",
            { defaultOn = true })
        Kit.Check(L, "Search and Sort in the title bar", BagCfgOf, "titleTools",
            "Search, Groups and Sort sit on the title bar beside the X and the row they had goes, so the bag is "
            .. "one row shorter. ZacUI's own bag window only. Takes a /reload.",
            { after = function() if ns.AskReload then ns.AskReload("The bag's title bar changes after a reload.") end end })
        Kit.Check(L, "A bar for how full the bags are", BagCfgOf, "fillBar",
            "Beside the free slot count at the bottom of the window. It turns red when nothing is free.",
            { defaultOn = true })
        Kit.Color(L, "Quest item border", BagCfgOf, "questColor", function() return 1, 0.82, 0, 1 end,
            { desc = "Quest items win over quality - a quest item you cannot spot is a corpse run." })
        Kit.Slider(L, "Items that do not match a search", BagCfgOf, "fadedAlpha",
            { min = 0, max = 100, step = 5, get = pct.get, set = pct.set, format = pct.format })
        L:EndCard()

        L:Card("Window")
        Kit.Color(L, "Background", BagCfgOf, "bgColor", function()
            local c = ns.GetColor("ui", "windowBg")
            return c.r, c.g, c.b, 0.97
        end, { alpha = true })
        Kit.Color(L, "Border", BagCfgOf, "frameBorderColor", Kit.Palette("ui", "border"), { alpha = true })
        L:EndCard()
    end

    local function Tab_text(L)
        L:Card("Text")
        Kit.Font(L, "Stack counts", BagCfgOf, "countFont", { size = 14, outline = "outline", shadow = false },
            { sample = "20  5  200", defaultLabel = "Blizzard's number font" })
        Kit.Color(L, "Count colour", BagCfgOf, "countColor", function() return 1, 1, 1, 1 end)
        local f = ZacUIDB.font
        Kit.Font(L, "Free slots and money", BagCfgOf, "footerFont",
            { size = F.SMALL + ((f and f.delta) or 0), outline = (f and f.outline == "NONE") and "none" or "outline", shadow = true },
            { sample = "3 / 80 free   1234g 56s" })
        L:EndCard()

        -- where each text sits (bags.anchors.<count|free|money>) and how
        -- your money reads (bags.formats.money); nothing saved = as ever
        if BL and BL.MoneyText then
            local function Group(key, label, targets, def, extra)
                local ag, as = ns.CustomAccess(BagCfgOf, "anchors", key)
                local o = { key = "bags." .. key, label = label, anchorGet = ag, anchorSet = as, targets = targets,
                    defaultTargetLabel = "Where it sits now", anchorMin = -40, anchorMax = 40,
                    anchorDefaults = function() return def end }
                if extra then for k, v in pairs(extra) do o[k] = v end end
                return UI.TextElement(L, o)
            end
            L:Card("Where the texts sit")
            Group("count", "Stack counts", BL.COUNT_TARGETS, { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -3, y = 2, justify = "RIGHT" })
            Group("free", "Free slots", BL.FOOTER_TARGETS, { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 8, y = 7 })
            local mg, ms = ns.CustomAccess(BagCfgOf, "formats", "money")
            Group("money", "Your money", BL.FOOTER_TARGETS, { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -8, y = 7, justify = "RIGHT" },
                { formatGet = mg, formatSet = ms, formatKinds = { number = true },
                  formatTokens = { { token = "coins", label = "the game's coins" }, { token = "g", label = "gold" },
                      { token = "s", label = "silver" }, { token = "c", label = "copper" } },
                  formatSample = function(spec)
                      local t = ns.FormatText(spec, nil, { coins = "1234g 56s 78c", g = 1234, s = 56, c = 78 },
                          { g = "number", s = "text", c = "text", coins = "text" }, "coins")
                      return (t:gsub("|T.-|t", ""))
                  end })
            L:EndCard()
        end
    end

    local function Tab_anim(L)
        L:Card("The window")
        Kit.Anim(L, "When it opens", BagCfgOf, "openAnim", { "none", "fade", "slide", "pop" }, nil,
            { default = { style = "none", duration = 0.15 } })
        Kit.Anim(L, "When it closes", BagCfgOf, "closeAnim", { "none", "fade", "slide", "pop" },
            "Your bag key and the auto-open at a vendor or the bank. None is instant, as it has always been.",
            { default = { style = "none", duration = 0.1 } })
        L:EndCard()
    end

    local function Tab_adv(L)
        L:Card("Reset")
        Kit.Buttons(L, { { "Reset the look", 130, function()
            local t = ZacUIDB.bags or {}
            for _, k in ipairs({ "slotSize", "spacing", "emptyAlpha", "filledAlpha", "fadedAlpha",
                                 "qualityBorders", "newItemRing", "fillBar", "titleTools", "slotColor", "borderColor", "questColor", "countFont",
                                 "countColor", "footerFont", "bgColor", "frameBorderColor",
                                 "openAnim", "closeAnim" }) do t[k] = nil end
            ns.SettingsChanged("reset")
            RefreshConfig()
        end, "Everything on the Look, Text and Animation tabs except the column count." } })
        L:EndCard()
    end

    L:Tabs({
        { id = "general", label = "General",   build = Tab_general },
        { id = "look",    label = "Look",      build = Tab_look },
        { id = "text",    label = "Text",      build = Tab_text },
        { id = "anim",    label = "Animation", build = Tab_anim },
        { id = "adv",     label = "Advanced",  build = Tab_adv },
    })
end)

-- ============================================================
-- BUTTON TRAY (a tab on the Minimap page)
-- ============================================================
-- The tray itself is UI/Tray (ZacUIDB.tray); its colours and the way it
-- opens are drawn by Blz_Minimap (ns.MinimapLook.Tray). The preview is a
-- bar and a tray of fake minimap buttons, the buttons dressed by the
-- tray's own StyleButton.
local TRAY_FAKE = {
    "Interface\\Icons\\INV_Misc_Map_01", "Interface\\Icons\\INV_Misc_Bag_08",
    "Interface\\Icons\\Spell_Nature_Lightning", "Interface\\Icons\\INV_Misc_Note_01",
    "Interface\\Icons\\Ability_Warrior_BattleShout", "Interface\\Icons\\INV_Misc_Gear_01",
    "Interface\\Icons\\Spell_Holy_PrayerOfHealing", "Interface\\Icons\\INV_Misc_Coin_01",
}
local TRAY_PAD, TRAY_GAP, TRAY_NATIVE = 6, 4, 31    -- the tray's own grid

local function TrayDB() ZacUIDB.tray = ZacUIDB.tray or {} return ZacUIDB.tray end

-- A minimap button the way LibDBIcon draws one: backing, icon, ring.
local function FakeMinimapButton(parent, icon)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TRAY_NATIVE, TRAY_NATIVE)
    local back = b:CreateTexture(nil, "BACKGROUND")
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    back:SetSize(20, 20)
    back:SetPoint("CENTER")
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetTexture(icon)
    ic:SetSize(17, 17)
    ic:SetPoint("CENTER")
    b.icon = ic
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    return b
end

local function BuildTrayPreview(canvas, P)
    local st = P.store
    local bar = CreateFrame("Button", nil, canvas)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    fill:SetTexture(ns.FLAT)
    bar._zFill = fill
    bar:SetPoint("TOP", canvas, "TOP", 0, -10)
    local tray = CreateFrame("Frame", nil, canvas)
    local bg = tray:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(ns.FLAT)
    tray._zFill = bg
    if ns.AddPixelBorder then ns.AddPixelBorder(tray) end
    tray:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
    st.bar, st.tray = bar, tray
    st.cells, st.plain, st.uniform = {}, {}, {}
    for i, icon in ipairs(TRAY_FAKE) do
        local cell = CreateFrame("Frame", nil, tray)
        st.cells[i] = cell
        st.plain[i] = FakeMinimapButton(cell, icon)
        st.uniform[i] = FakeMinimapButton(cell, icon)
        st.plain[i]:SetPoint("CENTER")
        st.uniform[i]:SetPoint("CENTER")
    end
end

local function UpdateTrayPreview(canvas, P)
    local st, db = P.store, TrayDB()
    local TL = ns.MinimapLook and ns.MinimapLook.Tray
    local T = ns.Tray
    local size = db.size or 28
    local cols = math.max(1, db.columns or 6)
    if ns.Motion then ns.Motion.Stop(st.tray) end
    st.bar:SetSize(db.barWidth or 90, db.barHeight or 6)
    local uniform = db.uniform ~= false
    -- every sample button, in the tray's real rows and columns
    local n = #TRAY_FAKE
    for i = n + 1, #TRAY_FAKE do st.cells[i]:Hide() end
    for i = 1, n do
        st.cells[i]:Show()
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local cell = st.cells[i]
        cell:SetSize(size, size)
        cell:ClearAllPoints()
        local pad, gap = tonumber(db.pad) or TRAY_PAD, tonumber(db.gap) or TRAY_GAP
        cell:SetPoint("TOPLEFT", st.tray, "TOPLEFT", pad + col * (size + gap),
            -(pad + row * (size + gap)))
        local u, pl = st.uniform[i], st.plain[i]
        if uniform and T and T.StyleButton and not u._zTrayStyled then T.StyleButton(u, size) end
        u:SetShown(uniform)
        pl:SetShown(not uniform)
        u:SetScale(size / TRAY_NATIVE)
        pl:SetScale(size / TRAY_NATIVE)
    end
    local rows = math.max(1, math.ceil(n / cols))
    local tpad, tgap = tonumber(db.pad) or TRAY_PAD, tonumber(db.gap) or TRAY_GAP
    local w = tpad * 2 + math.min(n, cols) * size + (math.min(n, cols) - 1) * tgap
    local h = tpad * 2 + rows * size + (rows - 1) * tgap
    -- the saved layout (grow / wrap / per line / gaps), by the tray's own code
    if T and T.LayoutCells then
        local lw, lh = T.LayoutCells(st.cells, n, st.tray, db)
        if lw then w, h = lw, lh end
    end
    st.tray:SetSize(w, h)
    if TL then
        TL.PaintTray(st.tray)
        TL.PaintBar(st.bar)
    end
    local open = (P.mode or "open") == "open"
    st.tray:SetShown(open)
    st.bar:SetAlpha(open and 1 or (db.barAlpha or 0.5))
    -- the canvas is the bar and the open tray; the strip scales it
    if P.Resize then
        local bw, bh = db.barWidth or 90, db.barHeight or 6
        P.Resize(math.max(bw, open and w or 0) + 12, 10 + bh + (open and (4 + h) or 0) + 8)
    end
end

local function ReplayTrayPreview(canvas, P)
    local st = P.store
    if (P.mode or "open") ~= "open" then return end
    local TL = ns.MinimapLook and ns.MinimapLook.Tray
    local spec = TL and TL.OpenSpec()
    if spec and ns.Motion then
        st.tray:Hide()
        ns.Motion.Play(st.tray, spec, "in")
    end
end

RegisterPage("Tray", function(L)
    if L.asTab then
        L:Card("Button tray")
        L:Desc("Collects every addon's minimap button into one bar, so the minimap "
            .. "stays a map.")
        L:EndCard()
    else
        L:Header("Button tray",
            "Collects every addon's minimap button into one bar, so the minimap "
            .. "stays a map.")
    end

    local db = TrayDB()
    local Tray = ns.Tray
    L:Preview({
        key = "screen.tray", title = "Button tray",
        width = 230, height = 60,
        modes = { { id = "open", label = "Open" }, { id = "rest", label = "At rest" } },
        build = BuildTrayPreview, update = UpdateTrayPreview, replay = ReplayTrayPreview,
    })
    local function Relayout() if Tray then Tray.Layout() end end

    -- General
    L:Card("Collecting")
    local cb = UI.Checkbox(L.current, "Use ZacUI's button tray",
        ZacUIDB.modules.tray and true or false,
        function(checked)
            if checked then
                EnableModuleLive("tray")
                if ns.MinimapLook then ns.MinimapLook.Tray.Install() end
            else
                ZacUIDB.modules.tray = false
                if Tray then Tray.ReleaseAll() end
                Print("Tray off - buttons put back on the minimap.")
            end
        end)
    L:Row(cb, 17)
    L:Desc("Turning it off puts every button back exactly where it was - "
        .. "position, size and all were recorded before anything moved.")

    local count = 0
    if Tray then for _ in pairs(Tray.grabbed) do count = count + 1 end end
    L:Gap(2)
    local stat = UI.Font(L.current, F.SMALL,
        { text = count .. " button" .. (count == 1 and "" or "s") .. " collected",
          cat = "text", key = "gray" })
    stat:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.DESC_X, L.current._y)
    L.current._y = L.current._y - math.max(16, math.ceil(stat:GetStringHeight() or 12) + 4)
    Kit.Check(L, "Open on hover", TrayDB, "openOnHover",
        "Off means the tray only opens when you click the bar.", { defaultOn = true })
    L:EndCard()

    -- Look
    L:Card("Look")
    Kit.Slider(L, "Button size", TrayDB, "size", { min = 16, max = 44, step = 1, after = Relayout,
        format = function(v) return v .. " px" end })
    Kit.Slider(L, "Columns", TrayDB, "columns", { min = 1, max = 12, step = 1, after = Relayout })
    Kit.Slider(L, "Space between buttons", TrayDB, "gap", { min = 0, max = 12, step = 1, after = Relayout,
        get = function(v) return v or 4 end, format = function(v) return v .. " px" end })
    Kit.Slider(L, "Space around the edge", TrayDB, "pad", { min = 0, max = 16, step = 1, after = Relayout,
        get = function(v) return v or 6 end, format = function(v) return v .. " px" end })
    Kit.Check(L, "Uniform square icons", TrayDB, "uniform",
        "Crops each addon's icon out of its own ring and puts it on a "
        .. "ZacUI plate, so the tray reads as one row rather than a jumble. "
        .. "A button whose icon cannot be identified is left alone rather "
        .. "than stripped - turn this off if one still comes out wrong.",
        { defaultOn = true, after = function() if Tray and Tray.RestyleAll then Tray.RestyleAll() end end })
    local TL = ns.MinimapLook and ns.MinimapLook.Tray
    local function RepaintTray() if TL then TL.Install() end end
    Kit.Color(L, "Tray background", TrayDB, "bgColor", function()
        local c = ns.GetColor("ui", "windowBg")
        return c.r, c.g, c.b, 0.95
    end, { alpha = true, after = RepaintTray })
    Kit.Color(L, "Tray border", TrayDB, "borderColor", Kit.Palette("ui", "border"),
        { alpha = true, after = RepaintTray })
    L:EndCard()

    -- the buttons' layout on the standard shape (ZacUIDB.tray.layout); its
    -- defaults are Columns and the two spaces on Look
    if Tray and Tray.LayoutDefaults and UI.LayoutPicker then
        L:Card("Button layout")
        local lg, ls = ns.CustomAccess(TrayDB, "layout", nil, Relayout)
        L:Add(UI.LayoutPicker(L.current, { label = "Buttons in the tray", width = UI.CardInnerWidth(L),
            get = lg, set = ls, defaults = function() return Tray.LayoutDefaults(TrayDB()) end,
            fields = { grow = true, wrap = true, perLine = true, spacingX = true, spacingY = true,
                padding = true, reverse = true },
            grows = { "RIGHT", "LEFT", "DOWN", "UP" } }), 6)
        L:Desc("Which way the buttons fill the tray. Nothing changed here = the columns and spaces above.")
        L:EndCard()
    end

    L:Card("The bar")
    Kit.Color(L, "Bar colour", TrayDB, "barColor", Kit.Palette("ui", "accent"), { after = RepaintTray })
    Kit.Slider(L, "Bar width", TrayDB, "barWidth", { min = 30, max = 300, step = 5,
        format = function(v) return v .. " px" end,
        after = function(v)
            local b = Tray and Tray.GetBar()
            if b then b:SetWidth(v) end
        end })
    Kit.Slider(L, "Bar height", TrayDB, "barHeight", { min = 2, max = 24, step = 1,
        format = function(v) return v .. " px" end,
        after = function(v)
            local b = Tray and Tray.GetBar()
            if b then b:SetHeight(v) end
        end })
    Kit.Slider(L, "Bar opacity at rest", TrayDB, "barAlpha", { min = 0, max = 100, step = 5,
        get = function(v) return math.floor((v or 0.5) * 100 + 0.5) end,
        set = function(v) return v / 100 end,
        format = function(v) return v .. "%" end,
        after = function()
            local b = Tray and Tray.GetBar()
            if b and not (Tray.GetTray() and Tray.GetTray():IsShown()) then b:SetAlpha(TrayDB().barAlpha) end
        end },
        "The bar goes fully opaque on hover regardless, so it can sit "
        .. "almost invisible until you reach for it.")
    L:EndCard()

    -- Animation
    L:Card("Opening and closing")
    Kit.Anim(L, "When the tray opens", TrayDB, "openAnim", { "none", "fade", "slide", "pop" },
        "None opens it at once, as it always has.",
        { default = { style = "none", duration = 0.15, dir = "down", distance = 8 },
          after = RepaintTray })
    Kit.Anim(L, "When the tray closes", TrayDB, "closeAnim", { "none", "fade", "slide", "pop" },
        "None puts it away at once, as it always has.",
        { default = { style = "none", duration = 0.12, dir = "up", distance = 8 } })
    Kit.Slider(L, "Close after", TrayDB, "autoClose", { min = 0, max = 5, step = 0.5,
        format = function(v) return string.format("%.1fs", v) end },
        "How long the tray waits once the mouse leaves it.")
    L:EndCard()

    -- Position
    L:Card("Where it sits")
    Kit.Check(L, "Lock the bar in place", TrayDB, "locked",
        "Drag the bar with the left mouse button to move it. Right-click "
        .. "it at any time to come back to this page.")
    Kit.Buttons(L, { { "Reset position", 120, function()
        db.point, db.x, db.y = nil, nil, nil
        local b = Tray and Tray.GetBar()
        if b then
            b:ClearAllPoints()
            b:SetPoint("TOP", UIParent, "TOP", 0, -2)
        end
        Print("tray bar reset to the top of the screen.")
    end, "Puts the bar back at the top centre of the screen." } })
    L:EndCard()

    -- Advanced
    L:Card("Tools")
    Kit.Buttons(L, {
        { "Scan now", 100, function()
            if Tray then Tray.Scan() end
            RefreshConfig()
        end, "Addons add their minimap button whenever they feel like "
            .. "it. ZacUI rescans automatically, but this does it immediately." },
        { "Diagnose", 90, function() if Tray then Tray.Diagnose() end end },
    })
    L:EndCard()
end)

-- ============================================================
-- AUCTION HOUSE
-- ============================================================
RegisterPage("Auction", function(L)
    local AH = ns.AH
    -- Declared FIRST: the cards below all bind against it, and it used
    -- to live between two of them - every control above the declaration
    -- was indexing a nil global and killing the whole page.
    local store = AH and AH.Store() or {}
    L:Header("Auction house",
        "Search, Sell and Cancel tabs on the auction window, backed by a "
        .. "price memory built from whatever you browse.")

    -- the window as it opens, with made-up auctions (ns.AHLook: the real
    -- window's frame, tabs and result list; nothing in it searches or buys)
    local AL = ns.AHLook
    if AL then
        L:Preview({
            key = "windows.auction", title = "Auction window",
            width = AL.WIDTH + 8, height = AL.HEIGHT + 8,
            -- taller than the strip: its top part at the real size
            overflow = "clip",
            build = function(canvas, P)
                P.store.win = AL.NewSample(canvas)
                P.store.win:ClearAllPoints()
                P.store.win:SetPoint("CENTER", canvas, "CENTER", 0, 0)
            end,
            update = function(canvas, P)
                AL.Fill(P.store.win)
                if P.Resize then P.Resize(AL.WIDTH + 8, AL.HEIGHT + 8) end
            end,
        })
    end

    -- (2026-11-01: General for what it does and how it sells, Advanced for
    -- the price memory's upkeep.)
    local function Tab_general(L)
        L:Card("Auction tabs")
        local cb = UI.Checkbox(L.current, "Use ZacUI's auction tabs",
            ZacUIDB.modules.auctionhouse and true or false,
            function(checked)
                if checked then
                    EnableModuleLive("auctionhouse")
                else
                    ZacUIDB.modules.auctionhouse = false
                    ns.AskReload("The auction tabs are off. They leave the auction house after a reload.")
                end
            end)
        L:Row(cb, 17)
        L:Desc("Adds three tabs below the auction window. Stands down "
            .. "automatically if Auctionator is loaded, since both would add "
            .. "competing tabs to the same frame.")
        L:EndCard()

        L:Card("Blizzard's window")
        local hideBlizz = UI.Checkbox(L.current, "Hide Blizzard's auction window",
            not (store.keepBlizzard),
            function(checked)
                store.keepBlizzard = not checked
                if checked then
                    if ns.AHHideBlizzard then ns.AHHideBlizzard() end
                elseif AuctionFrame then
                    AuctionFrame:Show()
                end
            end)
        L:Row(hideBlizz, 17)
        L:Desc("ZacUI's window covers searching, selling and cancelling, so "
            .. "Blizzard's is usually just in the way. It stays one click away "
            .. "on the 'Blizzard window' button for its category tree and level "
            .. "filters, which ZacUI does not reimplement.")

        local anchorRC = UI.Checkbox(L.current, "Anchor Readycheck's consumables checker",
            store.anchorReadycheck ~= false,
            function(checked) store.anchorReadycheck = checked end)
        L:Row(anchorRC, 17)
        L:Desc("Readycheck opens its consumables checker when the auction house "
            .. "opens. This puts it beside ZacUI's window instead of wherever "
            .. "Blizzard's used to be. Drag it yourself once and ZacUI leaves it "
            .. "alone from then on.")
        L:EndCard()

        L:Card("Selling")
        local under = UI.Slider(L.current, { width = 200, min = 0, max = 100, step = 1,
            value = store.undercut or 1, label = "Undercut by",
            format = function(v) return v .. " copper" end,
            onChange = function(v) store.undercut = v end })
        L:Row(under, 40)
        L:Desc("The Sell tab suggests the median remembered price minus this. "
            .. "One copper is enough to be the cheapest listing; larger "
            .. "undercuts only cost you money.")
        L:Gap(4)

        local durations = { [1] = "2 hours", [2] = "8 hours", [3] = "24 hours" }
        local dd = UI.Field(L.current, "Auction length", function(h)
            return UI.Dropdown(h, { width = 160,
                items = function()
                    return { { text = "2 hours", value = 1 },
                             { text = "8 hours", value = 2 },
                             { text = "24 hours", value = 3 } }
                end,
                selected = function() return durations[store.duration or 3] end,
                onSelect = function(v) store.duration = v end })
        end, { width = 160 })
        L:Add(dd, 6)
        L:Desc("How long new auctions run. Longer costs a larger deposit.")
        L:EndCard()

        -- (2026-11-09, Zac: both mock ideas, "give users the option to choose")
        L:Card("Buy window")
        local layouts = { card = "Card", list = "List" }
        local lay = UI.Field(L.current, "Layout", function(h)
            return UI.Dropdown(h, { width = 160,
                items = function()
                    return { { text = "Card", value = "card" }, { text = "List", value = "list" } }
                end,
                selected = function()
                    return layouts[(ZacUIDB.bags and ZacUIDB.bags.ahBuyLayout) or "card"] or "Card"
                end,
                onSelect = function(v)
                    ZacUIDB.bags = ZacUIDB.bags or {}
                    ZacUIDB.bags.ahBuyLayout = (v ~= "card") and v or nil
                end })
        end, { width = 160 })
        L:Add(lay, 6)
        L:Desc("The window that buys what you clicked. Card: the item, a bar of how far along it is, and the "
            .. "totals. List: each auction it will buy - seller, stack and price each - ticking off as you go.")
        L:EndCard()
    end

    local function Tab_adv(L)
        L:Card("Price memory")
        local known = AH and AH.Count() or 0
        L:Desc("There is no API that tells you what an item is worth. The only "
            .. "price data that exists is what the server sends while you "
            .. "browse, so ZacUI records the cheapest price it sees for each "
            .. "item and keeps the last ten observations. Prices you have never "
            .. "searched for are simply unknown, and old ones are shown with "
            .. "their age rather than presented as current.")
        L:Gap(2)
        local stat = UI.Font(L.current, F.SMALL,
            { text = known .. " item" .. (known == 1 and "" or "s") .. " remembered",
              cat = "text", key = "gray" })
        stat:SetPoint("TOPLEFT", L.current, "TOPLEFT", M.DESC_X, L.current._y)
        L.current._y = L.current._y - 18

        local keep = UI.Slider(L.current, { width = 200, min = 7, max = 120, step = 7,
            value = store.keepDays or 30, label = "Forget prices after",
            format = function(v) return v .. " days" end,
            onChange = function(v) store.keepDays = v end })
        L:Row(keep, 40)

        local prow = UI.Holder(L.current)
        prow:SetSize(400, M.BUTTON_H)
        local prune = UI.Button(prow, "Forget old prices", { width = 140,
            onClick = function()
                local n = AH.Prune()
                Print("forgot " .. n .. " stale item" .. (n == 1 and "" or "s") .. ".")
                RefreshConfig()
            end })
        prune:SetPoint("LEFT")
        local wipeAll = UI.Button(prow, "Forget everything", { width = 140,
            onClick = function()
                UI.Confirm({ title = "Clear price memory",
                    text = "Forget every price ZacUI has recorded? You will have "
                        .. "to browse the auction house again to rebuild it.",
                    acceptText = "Forget it all", destructive = true,
                    onAccept = function()
                        AH.Store().prices = {}
                        Print("price memory cleared.")
                        RefreshConfig()
                    end })
            end })
        wipeAll:SetPoint("LEFT", prune, "RIGHT", 8, 0)
        L:Row(prow, M.BUTTON_H + 4)
        L:EndCard()

        L:Card("What this does not do")
        L:Desc("No full-AH scanning. A complete scan hammers a rate-limited "
            .. "server, takes minutes, and is the single most common reason an "
            .. "auction addon gets an account disconnected. Every query ZacUI "
            .. "makes is queued behind the server's own throttle, and the price "
            .. "memory fills from searches you were going to run anyway.")
        L:EndCard()
    end

    L:Tabs({
        { id = "general", label = "General",  build = Tab_general },
        { id = "adv",     label = "Advanced", build = Tab_adv },
    })
end)

-- ============================================================
-- CHAT
-- ============================================================
-- EVERY CONTROL HERE IS LIVE, like the Minimap page: the chat layer
-- (ns.Chat, in Blz_Chat) places and shows things rather than skipping
-- setup, so nothing asks for a reload. The preview is a docked chat in
-- miniature - tabs on their strip, the panel with a few lines, the bar,
-- the edit box - built from Blz_Chat's own pieces (ns.Chat.Look).
Kit.Keywords("chat", "height colour color background border line thickness font size "
    .. "outline shadow message messages text tab tabs highlight underline pulse "
    .. "animation alert unread new fade timing linger visible duration")

local CHAT_LINES = {
    { "[Guild] [Zaccw]: pulling in 10", "GUILD", { 0.25, 1, 0.25 } },
    { "[Raid] [Thallen]: rez please", "RAID", { 1, 0.5, 0 } },
    { "[Mograine] whispers: inv to Petri Out?", "WHISPER", { 1, 0.5, 1 } },
    { "[Party] [Ashbringer]: ready", "PARTY", { 0.67, 0.67, 1 } },
    { "You receive loot: [Lionheart Helm].", "LOOT", { 0, 0.67, 0 } },
    { "[Zaccw] says: Ragnaros down!", "SAY", { 1, 1, 1 } },
}
local CHAT_TABS = { "General", "Combat Log", "Whispers" }
-- the panel at the chat window's real size (the main chat frame's, or
-- the game's default 430 x 120), as many lines as it holds
local CHAT_PV_LINES, CHAT_PV_W, CHAT_PV_H = #CHAT_LINES, 430, 120
local function ChatSize()
    local cf = _G.ChatFrame1
    local w = cf and cf.GetWidth and cf:GetWidth() or 0
    local h = cf and cf.GetHeight and cf:GetHeight() or 0
    if not (w and w >= 150 and h and h >= 40) then return CHAT_PV_W, CHAT_PV_H end
    return math.floor(w + 0.5), math.floor(h + 0.5)
end

local function ChatTypeRGB(id, fallback)
    local info = ChatTypeInfo and ChatTypeInfo[id]
    if info and info.r then return info.r, info.g, info.b end
    return fallback[1], fallback[2], fallback[3]
end

local function BuildChatPreview(canvas, P)
    local C, UIF = ns.Chat, ns.UI
    local CL = C.Look
    local st = P.store
    -- the panel and its lines
    local panel = CreateFrame("Frame", nil, canvas)
    st.panel = panel
    st.lines = {}
    for i = 1, CHAT_PV_LINES do
        local fs = panel:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
        if fs.GetFont and not fs:GetFont() then pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, 14, "") end
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        st.lines[i] = fs
    end
    -- the strip and the tabs on it
    local head = CreateFrame("Frame", nil, canvas)
    CL.MakeHeadLook(head)
    st.head = head
    st.tabs = {}
    for i, name in ipairs(CHAT_TABS) do
        local tab = CreateFrame("Button", nil, canvas)
        tab:SetFrameLevel(head:GetFrameLevel() + 2)
        local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if label.GetFont and not label:GetFont() then pcall(label.SetFont, label, STANDARD_TEXT_FONT, 12, "") end
        label:SetPoint("CENTER")
        label:SetText(name)
        tab:SetSize(70, 20)
        tab._label = label
        tab._chip = CL.MakeChip(tab, label)
        if ns.TagElement then ns.TagElement(label, "chat.tabText") end
        st.tabs[i] = tab
    end
    -- the bar: channel buttons on the left, numbers on the right
    local bar = CreateFrame("Frame", nil, canvas)
    CL.MakeBarLook(bar)
    st.bar = bar
    local content = CreateFrame("Frame", nil, bar)
    content:SetAllPoints()
    st.content = content
    st.chips = {}
    for _, c in ipairs({ { "S", "SAY" }, { "G", "GUILD" }, { "W 2", "WHISPER", whisper = true },
                         { "R", "RAID" } }) do
        local b = CL.Plate(content)
        b.spec = { id = c[2] }
        b._label:SetText(c[1])
        b._zWhisper = c.whisper
        if c.whisper then CL.AddWhisperGlow(b) end
        st.chips[#st.chips + 1] = b
    end
    st.items = {}
    local function ItemPlate(it)
        local b = CL.Plate(content)
        b._label:ClearAllPoints()
        b._label:SetPoint("RIGHT", b, "RIGHT", -6, 0)
        local rule = b:CreateTexture(nil, "ARTWORK")
        rule:SetTexture(ns.FLAT)
        rule:SetWidth(1)
        rule:SetPoint("TOPLEFT", 0, -5)
        rule:SetPoint("BOTTOMLEFT", 0, 5)
        b._rule = rule
        b._it = it
        return b
    end
    for _, it in ipairs(C.ITEMS) do st.items[#st.items + 1] = ItemPlate(it) end
    -- the bar's list can change later (another addon's block docked or
    -- undocked, Chat_LDB): the sample follows it on the next update
    st.SyncItems = function()
        local byId = {}
        for _, b in ipairs(st.items) do byId[b._it.id] = b b:Hide() end
        local list = {}
        for _, it in ipairs(C.ITEMS) do
            local b = byId[it.id] or ItemPlate(it)
            b._it = it
            list[#list + 1] = b
        end
        st.items = list
    end
    -- the edit box
    local eb = CreateFrame("EditBox", nil, canvas)
    eb:SetAutoFocus(false)
    eb:EnableMouse(false)
    if eb.SetFontObject then eb:SetFontObject("ChatFontNormal") end
    if eb.GetFont and not eb:GetFont() then pcall(eb.SetFont, eb, STANDARD_TEXT_FONT, 14, "") end
    if ns.SkinEditBox then ns.SkinEditBox(eb, CL.EditH()) end
    local header = eb:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    if header.GetFont and not header:GetFont() then pcall(header.SetFont, header, STANDARD_TEXT_FONT, 14, "") end
    header:SetPoint("LEFT", eb, "LEFT", 8, 0)
    header:SetText("Raid:")
    eb:SetTextInsets(48, 8, 0, 0)
    eb:SetText("pull on 3")
    eb._header = header
    st.eb = eb
    if ns.TagElement then ns.TagElement(eb, "chat.editBox") end
    st.fader = CreateFrame("Frame", nil, canvas)
    st.fader:Hide()
end

local function UpdateChatPreview(canvas, P)
    local C = ns.Chat
    local CL = C.Look
    local st, d = P.store, C.DB()
    if st.SyncItems then
        local stale = #st.items ~= #C.ITEMS
        if not stale then
            for i, b in ipairs(st.items) do if b._it ~= C.ITEMS[i] then stale = true break end end
        end
        if stale then st.SyncItems() end
    end
    local mode = P.mode or "reading"
    local W, H = ChatSize()
    local PAD, GAP = CL.PAD, CL.GAP
    st.fader:SetScript("OnUpdate", nil)
    st.fader:Hide()

    -- panel + lines (bottom up, like the chat: as many as it holds)
    local panelH = H
    st.panel:ClearAllPoints()
    st.panel:SetSize(W, panelH)
    st.panel:SetPoint("CENTER", canvas, "CENTER", 0, 0)
    CL.PaintPanel(st.panel, d)
    local fits = math.max(1, math.floor((panelH - 10) / 16))
    local shown = math.min(#st.lines, fits)
    for i, fs in ipairs(st.lines) do
        local k = i - (#st.lines - shown)      -- the newest lines stay
        if k >= 1 then
            local line = CHAT_LINES[i]
            CL.StyleBlizzText(fs, d.messageFont, true)
            -- (short channel names, names in colour, time stamps: Chat_Lines)
            local CLn = ns.ChatLines
            fs:SetText((CLn and CLn.PreviewOn() and CLn.Preview(line[1])) or line[1])
            fs:SetTextColor(ChatTypeRGB(line[2], line[3]))
            fs:ClearAllPoints()
            fs:SetWidth(W - 2 * PAD - 4)
            fs:SetPoint("BOTTOMLEFT", st.panel, "BOTTOMLEFT", PAD + 2, 6 + (#st.lines - i) * 16)
            fs:Show()
        else
            fs:Hide()
        end
    end

    -- strip + tabs
    local tabsOn = d.tabs and true or false
    st.head:ClearAllPoints()
    st.head:SetPoint("BOTTOMLEFT", st.panel, "TOPLEFT", 0, -1)
    st.head:SetPoint("BOTTOMRIGHT", st.panel, "TOPRIGHT", 0, -1)
    st.head:SetHeight(22)
    st.head:SetShown(tabsOn and d.tabStrip and true or false)
    st.head:_zPaint()
    local x = 6
    for i, tab in ipairs(st.tabs) do
        CL.StyleBlizzText(tab._label, d.tabFont)
        CL.PlaceTabText(tab._label, tab, d)
        local w = math.ceil(tab._label:GetStringWidth() or 40) + 2 * CL.TAB_PAD_X + 4
        tab:SetSize(w, 20)
        tab:ClearAllPoints()
        tab:SetPoint("BOTTOMLEFT", st.panel, "TOPLEFT", x, 2)
        x = x + w + 4
        local chip = tab._chip
        if tabsOn then
            CL.PaintChipState(chip, i == 1, false, mode == "news" and i == 3, d)
        else
            chip.pulse:Stop()
            chip.fill:Hide()
            chip.line:Hide()
            if ns.Motion then ns.Motion.Stop(chip.host) end
            chip.host:Hide()
        end
        tab:SetAlpha(1)
    end
    st.head:SetAlpha(1)

    -- the bar
    local barH = CL.BarH()
    local barOn = d.bar and true or false
    st.bar:SetShown(barOn)
    st.bar:ClearAllPoints()
    st.bar:SetPoint("TOPLEFT", st.panel, "BOTTOMLEFT", 1, -GAP + PAD)
    st.bar:SetPoint("TOPRIGHT", st.panel, "BOTTOMRIGHT", -1, -GAP + PAD)
    st.bar:SetHeight(barH)
    st.bar:_zPaint()
    local cx = 3
    for _, chip in ipairs(st.chips) do
        local on = chip._zWhisper and d.whispers or (not chip._zWhisper and d.channels)
        chip:SetShown(on and true or false)
        CL.StyleBarText(chip._label, d)
        CL.PaintChannel(chip)
        chip._sized = nil
        CL.SizeChip(chip, chip._zWhisper and "W 9" or nil)
        chip:SetHeight(barH - 6)
        chip:ClearAllPoints()
        if on then
            chip:SetPoint("LEFT", st.content, "LEFT", cx, 0)
            cx = cx + chip:GetWidth() + 2
        end
        if chip._zWhisper then CL.LightWhisper(chip, mode == "news", d) end
    end
    local rx, leftmost = -2, nil
    local g = ns.GetColor("text", "gray")
    -- (in the saved order, as the real bar: d.barOrder)
    local ordered = (C.OrderedItems and C.OrderedItems(st.items)) or st.items
    for i = #ordered, 1, -1 do
        local b = ordered[i]
        local on = d.items[b._it.id] and true or false
        b:SetShown(on)
        if on then
            CL.StyleBarText(b._label, d)
            b._label:SetText(b._it.sample or "")
            local w = math.ceil((b._label:GetStringWidth() or 0) + 12)
            b:SetSize(w, barH - 2)
            b:ClearAllPoints()
            b:SetPoint("RIGHT", st.content, "RIGHT", rx, 0)
            b._rule:SetVertexColor(g.r, g.g, g.b, 0.35)
            b._rule:Show()
            rx = rx - w
            leftmost = b
        end
    end
    if leftmost then leftmost._rule:Hide() end

    -- the edit box, where it opens
    local typing = mode == "typing"
    local eb = st.eb
    eb:SetShown(typing)
    st.content:SetShown(not (typing and barOn and d.editBox == "bar"))
    if typing then
        local where = d.editBox
        if where == "bar" and not barOn then where = "below" end
        local over = (st.head:IsShown() and d.tabsVisible == "always") and st.head or st.panel
        local under = barOn and st.bar or st.panel
        -- the real chat's own placing (its spot, or the saved anchor on top)
        CL.PlaceEditBoxAt(eb, where, st.bar, over, under, d)
        CL.StyleBlizzText(eb, d.editFont)
        CL.StyleBlizzText(eb._header, d.editFont)
        local r, gg, b = ChatTypeRGB("RAID", { 1, 0.5, 0 })
        eb._header:SetTextColor(r, gg, b)
        if d.tint and ns.TintBorder then ns.TintBorder(eb, r, gg, b, 1)
        elseif ns.TintBorder then ns.TintBorder(eb) end
    end
    -- the canvas is the tabs, panel, bar and edit box as they are laid
    -- out, centred; the strip scales it
    if P.Measure then
        local cx, cy, w, h = P.Measure(canvas)
        if cx then
            st.panel:ClearAllPoints()
            st.panel:SetPoint("CENTER", canvas, "CENTER", -cx, -cy)
            P.Resize(w + 6, h + 6)
        end
    end
end

-- Replay: the tabs fading in and out with the mouse (reading), or the
-- new-message alerts starting again.
local function ReplayChatPreview(canvas, P)
    local C = ns.Chat
    local st, d = P.store, C.DB()
    local mode = P.mode or "reading"
    if mode == "news" then
        UpdateChatPreview(canvas, P)
        for _, chip in ipairs(st.chips) do
            if chip._zWhisper then
                C.Look.LightWhisper(chip, false, d)
                C.Look.LightWhisper(chip, true, d)
            end
        end
        local chip = st.tabs[3]._chip
        if ns.Motion then ns.Motion.Stop(chip.host) end
        C.Look.PaintChipState(chip, false, false, true, d)
        return
    end
    if mode ~= "reading" or d.tabsVisible ~= "hover" or not d.tabs then return end
    -- animations off (Appearance > Motion): the module's fade is instant too
    if ns.Motion and not ns.Motion.Enabled() then return end
    local fin = math.max(0.01, tonumber(d.tabFadeIn) or 0.12)
    local fout = math.max(0.01, tonumber(d.tabFadeOut) or 0.3)
    local linger = tonumber(d.tabLinger) or 0.6
    local speed = (ns.Motion and ns.Motion.Speed()) or 1
    -- in, held a beat (the mouse leaves), linger, out, then back in
    local steps = { { 0, 1, fin }, { 1, 1, 0.8 + linger }, { 1, 0, fout }, { 0, 0, 0.4 }, { 0, 1, fin } }
    local i, t = 1, 0
    local function Set(a)
        st.head:SetAlpha(a)
        for _, tab in ipairs(st.tabs) do tab:SetAlpha(a) end
    end
    Set(0)
    st.fader:Show()
    st.fader:SetScript("OnUpdate", function(self, dt)
        t = t + dt * speed
        local s = steps[i]
        local p = math.min(1, t / s[3])
        Set(s[1] + (s[2] - s[1]) * p)
        if p >= 1 then
            i, t = i + 1, 0
            if not steps[i] then
                self:SetScript("OnUpdate", nil)
                self:Hide()
            end
        end
    end)
end

if ns.AddMenuKeywords then ns.AddMenuKeywords("chat", "position anchor corner offset tab names fine placement") end
RegisterPage("Chat", function(L)
    local C = ns.Chat
    L:Header("Chat",
        "The bar under the chat, what it shows, how the tabs and panel look, and "
        .. "where you type. Right-click the bar for the same switches.")

    if not C then
        L:Notice("missing", "The chat module did not load.")
        return
    end
    if not (C.Built and C.Built()) then
        L:Notice("off", "The Chat module is off, so there is no bar to set up.", "Modules > HUD", "chat")
    end

    local d = C.DB()
    local function DB() return C.DB() end
    local function Refresh() C.Refresh() end
    -- a sample's tab name or edit box picked in the preview: its spot
    if ns.CustomPick then
        ns.CustomPick.SetHandler("screen.chat", function(el)
            if el ~= "chat.tabText" and el ~= "chat.editBox" then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            ZacUIDB.config.tabs.chat = (el == "chat.editBox") and "pos" or "text"
            ns.RefreshConfig()
        end)
    end
    local function Check(tbl, key, label, desc)
        local cb = UI.Checkbox(L.current, label, tbl[key] and true or false, function(v)
            tbl[key] = v and true or false
            C.Refresh()
        end)
        L:Row(cb, 17)
        if desc then L:Desc(desc) end
        return cb
    end

    if C.Look then
        L:Preview({
            key = "screen.chat", title = "Chat",
            width = 430, height = 96,
            modes = { { id = "reading", label = "Reading" }, { id = "typing", label = "Typing" },
                      { id = "news", label = "New message" } },
            build = BuildChatPreview, update = UpdateChatPreview, replay = ReplayChatPreview,
        })
    end

    local function Tab_general(L)
        -- ============================================================
        L:Card("The bar")
        Check(d, "bar", "Show the bar under the chat",
            "A strip along the bottom of the chat panel: channel buttons on "
            .. "the left, the numbers you tick below on the right. It belongs "
            .. "to the docked chat - General and every tab docked with it - "
            .. "and windows you have dragged out do not get one.")
        Check(d, "channels", "Channel buttons",
            "S, P, R, RW and G, each in that channel's own colour and only "
            .. "while you can talk there. Click one to start typing in it.")
        Check(d, "whispers", "Whisper counter",
            "A W button that counts whispers since you last answered one. "
            .. "Hover for the last few, click to reply to the most recent, "
            .. "right-click to clear the count.")
        Check(d, "latest", "Jump to latest",
            "ZacUI hides Blizzard's scroll buttons, so when you are scrolled "
            .. "up a Latest button appears on the bar. Click it to drop back "
            .. "to the newest message.")
        L:EndCard()

        L:Card("What the bar shows")
        L:Desc("In the order they sit on the bar, left to right. When the "
            .. "chat is too narrow for all of them, the bar fits the most "
            .. "urgent first - durability, then bag space, then gold - and "
            .. "leaves off whatever there is no room for.")
        local ITEM_DESC = {
            group   = "Raid or party size, only while you are in one. Hover for loot method, threshold, and who is offline or dead.",
            guild   = "Hover for who is on and where; click for the roster.",
            friends = "Battle.net friends included. Hover for who and where; click for the list.",
            coords  = "Blank inside instances, which report no position.",
            bags    = "Free slots in your ordinary bags (quivers, soul bags and profession bags are left out). Orange at three, red when full. Click opens your bags.",
            dur     = "Your most worn piece. Orange at 50%, red at 20%. Hover for every slot.",
            gold    = "Hover for the exact amount and what you have made or spent since logging in.",
            fps     = "Orange under 40, red under 20.",
            ms      = "The worse of home and world latency. Hover for both.",
            clock   = "Realm time, or local time if Blizzard's clock is set to it. The minimap has one too, so this starts off.",
        }
        for _, it in ipairs(C.ITEMS) do
            -- (other addons' blocks have their own card below)
            if not it.ldb then Check(d.items, it.id, it.label, ITEM_DESC[it.id]) end
        end
        L:EndCard()

        -- other addons' LibDataBroker blocks on the bar (Chat_LDB.lua)
        if ns.ChatLDB and ns.ChatLDB.Card then ns.ChatLDB.Card(L) end

        L:Card("Tabs")
        Check(d, "tabs", "Style the chat tabs",
            "The tab you are on gets a raised chip with a line under "
            .. "it, a tab with something new pulses its line, and the one "
            .. "under the mouse lights faintly. Off leaves them as bare words.")
        Check(d, "tabStrip", "Put the docked tabs on a strip",
            "A header strip on top of the chat panel, behind General and "
            .. "everything docked with it. It shows and hides with the tabs. "
            .. "Sized from where the tabs actually are; if it ever sits wrong, "
            .. "/zui chatinfo prints the measurements.")
        local SHOWN = {
            hover    = "Only with the mouse over the chat",
            always   = "Always",
            blizzard = "Blizzard's dimming",
        }
        local vis = UI.Field(L.current, "When the tabs show", function(h)
            return UI.Dropdown(h, { width = 240,
                items = function()
                    return { { text = SHOWN.hover, value = "hover" },
                             { text = SHOWN.always, value = "always" },
                             { text = SHOWN.blizzard, value = "blizzard" } }
                end,
                selected = function() return SHOWN[d.tabsVisible] or SHOWN.hover end,
                onSelect = function(v)
                    d.tabsVisible = v
                    C.Refresh()
                end })
        end, { width = 240 })
        L:Add(vis, 6)
        L:Desc("With the mouse over the chat, the tabs (and their strip) are hidden "
            .. "until the cursor is on the chat, its tab row or the bar, then fade in - "
            .. "and a tab with something new shows either way. Blizzard's dimming is "
            .. "the game's own: faint when the mouse is away, never gone.")
        L:EndCard()

        L:Card("Typing")
        if _G.Prat then
            L:Desc("|cffff9900Prat is running|r and draws its own edit box, so "
                .. "ZacUI leaves the edit box alone and these settings "
                .. "do nothing. Prat's Editbox module has its own.")
        end
        Check(d, "arrows", "Arrow keys without Alt",
            "Up and down recall what you typed before, left and right move "
            .. "through the text. Off is Blizzard's way: hold Alt.")
        L:EndCard()

        -- ============================================================
        L:Card("In a raid")
        -- the raid / party frames inside the chat box (chat.raidMode, also
        -- /zacui raidchat; a character's own override is cleared like the
        -- slash command does, so the tick box is what this character gets)
        local RMo = C.RaidMode
        local inBox = UI.Checkbox(L.current, "Raid frames in the chat box",
            (RMo and RMo.Enabled and RMo.Enabled()) and true or false, function(v)
            d.raidMode = v and true or false
            if ZacUICharDB then ZacUICharDB.chatRaidMode = nil end
            if RMo and RMo.Update then RMo.Update() end
        end)
        L:Row(inBox, 17)
        L:Desc("In a raid the chat box holds the raid frames, fitted to its size, and the messages move "
            .. "to a strip you can hide. Leaving the raid gives the box back. Same as /zacui raidchat.")
        local pb = UI.Checkbox(L.current, "Party frames in the chat box too", d.raidModeParty ~= false, function(v)
            d.raidModeParty = v and true or false
            if RMo and RMo.Update then RMo.Update() end
        end)
        L:Row(pb, 17)
        L:Desc("While the raid frames are in the chat box, a 5-man party sits there too, in one row across "
            .. "the top. Off keeps the party frames where you put them.")
        -- Readycheck's route tracker in the box (2026-11-12, Zac: "make
        -- sure all of this is configurable in zui"). The three settings
        -- are Readycheck's own (this character's raidRoute), read and
        -- written through its route module and saved its way; shown only
        -- with a Readycheck that can dock its tracker here.
        do
            local RC = _G.Readycheck
            local RR = RC and RC.RaidRoute
            local rs = RR and RR.ChatDockArea and RR.GetSettings and RR:GetSettings()
            if type(rs) == "table" then
                local function RouteSet(key, v)
                    rs[key] = v
                    if RC.SaveConfigurationToProfile then RC:SaveConfigurationToProfile() end
                    if RR.RefreshTracker then RR:RefreshTracker() end
                end
                local gearBox
                local dock = UI.Checkbox(L.current, "Readycheck's route tracker along the top of the box",
                    rs.trackerChatDock == true, function(v) RouteSet("trackerChatDock", v and true or false) end)
                L:Row(dock, 17)
                L:Desc("With a Readycheck raid route running, its tracker becomes a bar across the top of the "
                    .. "chat box and the raid frames start under it. The tracker's own spot, size and look "
                    .. "are kept and come back when this is off.")
                local swaps = UI.Checkbox(L.current, "Route bar: confirm gear swaps beside the step",
                    rs.trackerBandSwaps ~= false, function(v)
                        RouteSet("trackerBandSwaps", v and true or false)
                        if gearBox then UI.SetEnabled(gearBox, v and true or false) end
                    end)
                L:Row(swaps, 17)
                L:Desc("A tick and the set's name on the bar when Readycheck changes your gear.")
                gearBox = UI.Checkbox(L.current, "Route bar: show your gear when a swap lands",
                    rs.trackerBandGear ~= false, function(v) RouteSet("trackerBandGear", v and true or false) end)
                L:Row(gearBox, 17)
                if rs.trackerBandSwaps == false then UI.SetEnabled(gearBox, false) end
                L:Desc("For a few seconds the bar's mob names give way to what you are wearing, slot by slot "
                    .. "as in the character window, with the pieces that changed lit.")
            end
        end
        local rt = UI.Checkbox(L.current, "Raid timer on the raid strip", d.raidTimer ~= false, function(v)
            d.raidTimer = v and true or false
            local T = C.RaidMode and C.RaidMode.Timer
            if T and T.Paint then T.Paint() end
        end)
        L:Row(rt, 17)
        L:Desc("While the raid frames hold the chat box: a clock from the first pull, and each boss kill "
            .. "against the same kill on your best full clear with the same Readycheck raid config. "
            .. "Hover it for every split.")
        -- how its clock reads (chat.formats.raidClock; nothing saved = 23:45)
        local T = C.RaidMode and C.RaidMode.Timer
        if T and T.CLOCK_DEFAULTS then
            local fg, fs = ns.CustomAccess(DB, "formats", "raidClock", function() if T.Paint then T.Paint() end end)
            local fp = UI.TextFormatPicker(L.current, { label = "Raid timer clock", width = UI.CardInnerWidth(L),
                get = fg, set = fs, defaults = T.CLOCK_DEFAULTS, kinds = { time = true },
                sample = function(f) return ns.FormatTime(23 * 60 + 45, f, T.CLOCK_DEFAULTS) .. "  "
                    .. ns.FormatTime(3723, f, T.CLOCK_DEFAULTS) end })
            L:Add(fp, 6)
        end
        L:EndCard()
    end

    local function Tab_look(L)
        L:Card("Panel")
        local op = UI.Slider(L.current, { width = 220, min = 0, max = 100, step = 5,
            value = math.floor(((ns.Chat and ns.Chat.PanelOpacity and ns.Chat.PanelOpacity(d)) or d.opacity or 0.75) * 100 + 0.5), label = "Background opacity",
            format = function(v) return v .. "%" end,
            onChange = function(v)
                d.opacity = v / 100
                C.Refresh()
            end })
        L:Row(op, 40)
        L:Desc("The dark panel behind the messages. The bar stays solid.")
        Kit.Color(L, "Background colour", DB, "panelColor", Kit.Palette("ui", "windowBg"), { after = Refresh })
        Kit.Color(L, "Edge", DB, "panelBorderColor", Kit.Palette("ui", "border"), { alpha = true, after = Refresh })
        L:EndCard()

        L:Card("Bar")
        Kit.Slider(L, "Bar height", DB, "barHeight", { min = 14, max = 40, step = 1, after = Refresh,
            format = function(v) return v .. " px" end })
        Kit.Color(L, "Bar colour", DB, "barColor", Kit.Palette("ui", "headerBg"), { alpha = true, after = Refresh })
        Kit.Color(L, "Line along its top", DB, "barLineColor", Kit.Palette("ui", "border"), { alpha = true, after = Refresh })
        L:EndCard()

        L:Card("Tabs")
        Kit.Color(L, "Tab you are on", DB, "tabFillColor", Kit.Palette("button", "hover"), { after = Refresh,
            desc = "Its chip; the tab under the mouse gets the same colour, fainter." })
        Kit.Color(L, "Line under it", DB, "tabLineColor", Kit.Palette("ui", "accent"), { after = Refresh,
            desc = "Also the line that pulses on a tab with something new." })
        Kit.Slider(L, "Line thickness", DB, "tabLine", { min = 1, max = 6, step = 1, after = Refresh,
            format = function(v) return v .. " px" end })
        Kit.Color(L, "Strip colour", DB, "stripColor", Kit.Palette("ui", "headerBg"), { alpha = true, after = Refresh })
        Kit.Color(L, "Strip's bottom line", DB, "stripLineColor", function()
            local a = ns.GetColor("ui", "accent")
            return a.r, a.g, a.b, 0.6
        end, { alpha = true, after = Refresh })
        L:EndCard()

        L:Card("Edit box")
        Kit.Slider(L, "Height", DB, "editHeight", { min = 16, max = 40, step = 1, after = Refresh,
            format = function(v) return v .. " px" end },
            "Under or above the panel; in the bar it is as tall as the bar.")
        Check(d, "tint", "Colour the edit box by channel",
            "The box's edge takes the colour of the channel you are about to "
            .. "talk in, so a message headed for the wrong one is visible "
            .. "before you press Enter.")
        L:EndCard()
    end

    local function Tab_text(L)
        local CL = C.Look
        local f = ZacUIDB.font
        L:Card("Bar")
        Kit.Font(L, "Buttons and numbers", DB, "barFont",
            { size = UI.F.SMALL + ((f and f.delta) or 0), outline = (f and f.outline == "NONE") and "none" or "outline", shadow = true },
            { sample = "S  G  W 2   Bags 23 | 98% | 412g", after = Refresh })
        L:EndCard()

        L:Card("Chat")
        local function Stock(obj, size)
            local o = _G[obj]
            local p, s, fl
            if o and o.GetFont then p, s, fl = o:GetFont() end
            return { fallbackFace = p, size = s or size, outline = (fl and fl ~= "") and fl or "none", shadow = true }
        end
        Kit.Font(L, "Messages", DB, "messageFont", Stock("ChatFontNormal", 14),
            { sample = "[Guild] [Zaccw]: pulling in 10", defaultLabel = "Blizzard's chat font", after = Refresh,
              desc = "Each chat window keeps the size you give it in Blizzard's own chat "
                .. "menu unless you set one here." })
        Kit.Font(L, "Tab names", DB, "tabFont", Stock("GameFontNormalSmall", 12),
            { sample = "General  Combat Log  Whispers", defaultLabel = "Blizzard's tab font", after = Refresh })
        Kit.Font(L, "Edit box", DB, "editFont", Stock("ChatFontNormal", 14),
            { sample = "Raid: pull on 3", defaultLabel = "Blizzard's chat font", after = Refresh })
        L:EndCard()

        -- where the tab names sit on their tabs (anchors.tabText; nothing
        -- saved = where the game puts them)
        L:Card("Tab names on their tabs")
        local tg, ts = ns.CustomAccess(DB, "anchors", "tabText", Refresh)
        UI.TextElement(L, { key = "chat.tabText", anchorGet = tg, anchorSet = ts, targets = CL.TAB_TARGETS,
            defaultTargetLabel = "Where the game puts it", anchorMin = -20, anchorMax = 20,
            anchorDefaults = function()
                local t = _G.ChatFrame1Tab
                local fs = t and (t.Text or (t.GetFontString and t:GetFontString()))
                local o = fs and fs._zOrigPts
                if o and o[1] then return { point = o[1][1], relPoint = o[1][3], x = o[1][4], y = o[1][5] } end
                return { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
            end })
        L:EndCard()
    end

    local function Tab_anim(L)
        L:Card("Tabs on mouseover")
        local function secs(v) return string.format("%.2fs", v) end
        Kit.Slider(L, "Fade in", DB, "tabFadeIn", { min = 0, max = 1, step = 0.02, after = Refresh, format = secs })
        Kit.Slider(L, "Stay after the mouse leaves", DB, "tabLinger", { min = 0, max = 3, step = 0.1, after = Refresh,
            format = function(v) return string.format("%.1fs", v) end })
        Kit.Slider(L, "Fade out", DB, "tabFadeOut", { min = 0, max = 2, step = 0.05, after = Refresh, format = secs })
        L:Desc("When the tabs show only with the mouse over the chat. Replay in the "
            .. "preview (Reading) plays it.")
        L:EndCard()

        L:Card("Something new")
        Kit.Anim(L, "A tab with something new", DB, "newsAnim", { "none", "pulse", "flash", "bounce" },
            "Its line. None keeps the slow pulse it has always had.",
            { default = { style = "none", duration = 0.6, loop = true }, after = Refresh })
        Kit.Anim(L, "Unread whispers", DB, "whisperAnim", { "none", "pulse", "flash", "bounce" },
            "The W button's glow. None keeps the slow pulse it has always had.",
            { default = { style = "none", duration = 0.9, loop = true }, after = Refresh })
        L:EndCard()

        L:Card("Old messages")
        Check(d, "fade", "Fade old messages",
            "Off keeps every message on screen until it scrolls away, which "
            .. "is how ZacUI has always had it.")
        Kit.Slider(L, "Fade after", DB, "timeVisible", { min = 0, max = 300, step = 5, after = Refresh,
            format = function(v) return v == 0 and "Blizzard's" or (v .. "s") end })
        Kit.Slider(L, "Fade takes", DB, "fadeDuration", { min = 0, max = 10, step = 0.5, after = Refresh,
            format = function(v) return v == 0 and "Blizzard's" or string.format("%.1fs", v) end })
        L:EndCard()
    end

    local function Tab_pos(L)
        L:Card("Where you type")
        local WHERE = {
            bar   = "In the bar",
            below = "Under the chat panel",
            above = "Above the chat panel",
        }
        local dd = UI.Field(L.current, "Edit box", function(h)
            return UI.Dropdown(h, { width = 220,
                items = function()
                    return { { text = WHERE.bar, value = "bar" },
                             { text = WHERE.below, value = "below" },
                             { text = WHERE.above, value = "above" } }
                end,
                selected = function() return WHERE[d.editBox] or WHERE.bar end,
                onSelect = function(v)
                    d.editBox = v
                    C.Refresh()
                end })
        end, { width = 220 })
        L:Add(dd, 6)
        L:Desc("Where the edit box opens when you press Enter. In the bar, "
            .. "the buttons and numbers step aside while you type and come "
            .. "back when you finish. Under the panel is where Blizzard puts "
            .. "it, moved clear of the panel it used to overlap. Above sits "
            .. "over the top of the panel (over the tabs, if the tab strip is "
            .. "off). Windows without a bar use Under.")
        -- fine placement on top of that spot (anchors.editBox)
        local eg, es = ns.CustomAccess(DB, "anchors", "editBox", Refresh)
        UI.FrameElement(L, { key = "chat.editBox", label = "Fine placement", gap = 0, anchorGet = eg, anchorSet = es,
            targets = C.Look.EDIT_TARGETS, defaultTargetLabel = "Its spot above", anchorMin = -100, anchorMax = 100,
            anchorDefaults = function()
                local w = d.editBox
                if w == "above" then return { point = "BOTTOMLEFT", relPoint = "TOPLEFT", x = 0, y = 2 }
                elseif w == "below" then return { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -2 } end
                return { point = "TOPLEFT", relPoint = "TOPLEFT", x = 0, y = 0 }
            end })
        L:EndCard()

        L:Card("Size and spot")
        local cw = _G.ChatFrame1 and math.floor((_G.ChatFrame1:GetWidth() or 400) + 0.5) or 400
        Check(d, "sameSpot", "Same chat size and spot on every character",
            "Every character on this account opens with the main chat window "
            .. "in the same place at the same size. Moving or resizing it on "
            .. "one character carries over to all of them.")
        Check(d, "sameWidth", "Same chat width on every character",
            "Every character on this account opens with the main chat window "
            .. "at the width below. The raid frames line up to it.")
        local wsl = UI.Slider(L.current, { width = 220, min = 250, max = 900, step = 1,
            value = math.floor((tonumber(d.width) or cw) + 0.5), label = "Chat width",
            format = function(v) return v .. " px" end,
            onChange = function(v)
                d.width = v
                if C.ApplyWidth then C.ApplyWidth() end
            end })
        L:Row(wsl, 40)
        L:EndCard()
    end

    local function Tab_adv(L)
        -- ============================================================
        L:Card("Tools")
        local row = UI.Holder(L.current)
        row:SetSize(320, M.BUTTON_H)
        local copy = UI.Button(row, "Copy chat", { width = 100,
            tooltip = "Opens the tab you are looking at as plain text you can "
                .. "select and copy. Also on the bar's right-click menu, and "
                .. "/zui copychat.",
            onClick = function() C.CopyChat() end })
        copy:SetPoint("LEFT")
        local diag = UI.Button(row, "Diagnose", { width = 90,
            tooltip = "Prints what each chat window, edit box and bar item is "
                .. "doing on this client. /zui chatinfo does the same.",
            onClick = function() C.Diagnose() end })
        diag:SetPoint("LEFT", copy, "RIGHT", 8, 0)
        local reset = UI.Button(row, "Reset", { width = 90,
            tooltip = "Puts every option on this page back to the default.",
            onClick = function()
                ZacUIDB.chat = nil
                C.DB()
                C.Refresh()
                ns.SettingsChanged("reset")
                RefreshConfig()
                Print("chat options reset.")
            end })
        reset:SetPoint("LEFT", diag, "RIGHT", 8, 0)
        L:Row(row, M.BUTTON_H + 4)
        L:EndCard()
    end

    L:Tabs({
        { id = "general", label = "General",   build = Tab_general },
        { id = "look",    label = "Look",      build = Tab_look },
        { id = "text",    label = "Text",      build = Tab_text },
        { id = "anim",    label = "Animation", build = Tab_anim },
        { id = "pos",     label = "Position",  build = Tab_pos },
        { id = "adv",     label = "Advanced",  build = Tab_adv },
    })
end)

-- ============================================================
-- LOOT ROLLS (2026-11-03): the group loot bars get a page of their own
-- ============================================================
-- Everything lives in ZacUIDB.lootRoll (nothing saved = the bars as they
-- always were) and is drawn by Blz_LootRoll (ns.LootRoll). The preview is
-- three bars made, styled and filled by the module's own NewBar / Style /
-- Fill, with the made-up drops /zui testroll shows, their timers running.
Kit.Keywords("lootroll", "width height size gap texture font item name time left timer "
    .. "format bind tag roll count counts stack icon position move grow up down")

local function LRCfg() return ns.LootRoll and ns.LootRoll.Cfg() or {} end
-- written only by a change (browsing the page leaves the save alone), and
-- an emptied table goes again
local function LROwn()
    if type(ZacUIDB.lootRoll) ~= "table" then ZacUIDB.lootRoll = {} end
    return ZacUIDB.lootRoll
end
local function LRTidy()
    if type(ZacUIDB.lootRoll) == "table" and next(ZacUIDB.lootRoll) == nil then ZacUIDB.lootRoll = nil end
end
local function LRSet(key, v)
    LROwn()[key] = v
    LRTidy()
end
local function LRAccess(family, key)
    local get = ns.CustomAccess(LRCfg, family, key)
    local _, set = ns.CustomAccess(LROwn, family, key, LRTidy)
    return get, set
end

local LR_TARGETS = {
    { value = "bar", text = "The bar" }, { value = "icon", text = "Item icon" },
    { value = "name", text = "Item name" }, { value = "time", text = "Time left" },
    { value = "bind", text = "Bind tag" }, { value = "buttons", text = "Roll buttons" },
}
-- where each piece sits with nothing saved (what its anchor picker shows)
local LR_ANCHORS = {
    name = { point = "LEFT", relPoint = "LEFT", x = 4, y = 0, label = "The bar" },
    time = { point = "RIGHT", relPoint = "LEFT", x = -4, y = 0, label = "The bind tag" },
    bind = { point = "RIGHT", relPoint = "LEFT", x = -4, y = 0, label = "The need button" },
    buttons = { point = "RIGHT", relPoint = "RIGHT", x = -3, y = 0, label = "The bar" },
    icon = { point = "RIGHT", relPoint = "LEFT", x = -2, y = 0, label = "The bar" },
    count = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = 2, y = -2, label = "Its roll button" },
    stack = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -1, y = 1, label = "The item icon" },
}

local function BuildLootPreview(canvas, P)
    local LR = ns.LootRoll
    local st = P.store
    st.holder = CreateFrame("Frame", nil, canvas)
    st.bars, st.items = {}, {}
    for i, fake in ipairs(LR.SAMPLES) do
        st.bars[i] = LR.NewBar(canvas)
        local item = {}
        for k, v in pairs(fake) do item[k] = v end
        -- a little way into each roll, so the timers read differently
        item.left = fake.time * (0.9 - 0.15 * i)
        st.items[i] = item
    end
    -- the timers run down (and start again) while the strip is on screen;
    -- an OnUpdate on a sample-only frame stops by itself when it hides
    local clock = CreateFrame("Frame", nil, canvas)
    local acc = 0
    clock:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.2 then return end
        local step = acc
        acc = 0
        local cfg = LR.Cfg()
        for i, bar in ipairs(st.bars) do
            local item = st.items[i]
            item.left = item.left - step
            if item.left <= 0 then item.left = item.time end
            bar.status:SetValue(item.left)
            LR.PaintTime(bar, item.left, cfg)
        end
    end)
    st.clock = clock
end

local function UpdateLootPreview(canvas, P)
    local LR = ns.LootRoll
    local st, cfg = P.store, LR.Cfg()
    for i, bar in ipairs(st.bars) do
        LR.Style(bar, cfg)
        LR.Fill(bar, st.items[i], cfg)
        bar:Show()
    end
    local W, H = LR.V(cfg, "width"), LR.V(cfg, "height")
    local lay = cfg.layout or {}
    local gap = tonumber(lay.spacingY) or LR.D.gap
    local n = #st.bars
    local PAD = 8
    st.holder:ClearAllPoints()
    if lay.grow == "UP" then
        st.holder:SetPoint("BOTTOM", canvas, "BOTTOM", 0, PAD)
    else
        st.holder:SetPoint("TOP", canvas, "TOP", 0, -PAD)
    end
    LR.Place(st.bars, st.holder, cfg)
    if P.Resize then
        P.Resize(W + H + 2 + 2 * PAD + 6, n * H + (n - 1) * math.max(0, gap) + 2 * PAD)
    end
end

RegisterPage("LootRoll", function(L)
    L:Header("Loot rolls", "The bars that come up when a group drop is rolled for: need, greed or pass.")
    if not (ZacUIDB.modules and ZacUIDB.modules.lootroll) then
        L:Notice("off", "The Loot rolls module is off, so Blizzard's own roll frames are in use.", "Modules > Windows", "lootroll")
    end
    local LR = ns.LootRoll
    if not LR then
        L:Notice("missing", "The loot roll module did not load.")
        return
    end
    if ns.CustomPick then
        ns.CustomPick.SetHandler("screen.lootroll", function(el)
            if type(el) ~= "string" or not el:find("^lootroll%.") then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            local part = (el == "lootroll.icon" or el == "lootroll.buttons")
            ZacUIDB.config.tabs.lootroll = part and "pos" or "text"
            ns.RefreshConfig()
        end)
    end
    L:Preview({
        key = "screen.lootroll", title = "Loot rolls",
        width = 220, height = 76,
        build = BuildLootPreview, update = UpdateLootPreview,
    })

    local function Check(label, key, defaultOn, tip)
        local on = LRCfg()[key]
        if defaultOn then on = on ~= false else on = on and true or false end
        local cb = UI.Checkbox(L.current, label, on, function(v)
            if defaultOn then if v then LRSet(key, nil) else LRSet(key, false) end
            else LRSet(key, v and true or nil) end
        end, { tooltip = tip })
        L:Row(cb, 17)
        return cb
    end

    local function Tab_general(L)
        L:Card("What the bars show")
        Check("Show the bind tag", "showBind", true, "BoP, BoE or BoU in front of the roll buttons.")
        Check("Show how many rolled", "showCounts", true, "A small number on need, greed and pass as people roll.")
        Check("Show the time left", "showTime", false, "The seconds the roll has left, written on the bar.")
        L:EndCard()
        L:Card("Try them")
        Kit.Buttons(L, { { "Show test bars", 130, function()
            if ns.LootRollTest then ns.LootRollTest() end
        end, "Three made-up drops on screen for a few seconds (/zui testroll). Their buttons just close them." } })
        L:EndCard()
    end

    local function Tab_look(L)
        L:Card("Size")
        local W = UI.Slider(L.current, { label = "Bar width", min = 120, max = 400, step = 2, width = 220,
            value = LR.V(LRCfg(), "width"), format = function(v) return v .. " px" end,
            onChange = function(v) LRSet("width", v ~= LR.D.width and v or nil) end })
        L:Row(W, 40)
        local H = UI.Slider(L.current, { label = "Bar height", min = 12, max = 40, step = 1, width = 220,
            value = LR.V(LRCfg(), "height"), format = function(v) return v .. " px" end,
            onChange = function(v) LRSet("height", v ~= LR.D.height and v or nil) end })
        L:Row(H, 40)
        L:Desc("The item icon is as tall as the bar; the roll buttons follow it.")
        L:EndCard()
        L:Card("Timer bar")
        local tex = UI.TexturePicker(L.current, { label = "Texture", width = 240,
            get = function() return LRCfg().texture end,
            set = function(name) LRSet("texture", name) end,
            color = function() local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[3] return c and c.r or 0, c and c.g or 0.44, c and c.b or 0.87 end })
        L:Add(tex, 8)
        L:Desc("Tinted in the item's quality colour. ZacUI's texture is the one on Appearance > Fonts & Textures.")
        L:EndCard()
    end

    local function Group(L, key, label, o)
        local ag, as = LRAccess("anchors", key)
        local d = LR_ANCHORS[key]
        local spec = { key = "lootroll." .. key, label = label,
            anchorGet = ag, anchorSet = as, anchorDefaults = d,
            targets = LR_TARGETS, defaultTargetLabel = d.label, anchorMin = -80, anchorMax = 80 }
        for k, v in pairs(o or {}) do spec[k] = v end
        return spec
    end
    local function FontOf(key, size)
        return function() return LRCfg()[key] end,
            function(s) LRSet(key, (type(s) == "table" and next(s)) and s or nil) end,
            { size = size, outline = "none", shadow = true }
    end

    local function Tab_text(L)
        L:Card("Item name")
        local fg, fs, fd = FontOf("nameFont", 12)
        UI.TextElement(L, Group(L, "name", nil, { fontGet = fg, fontSet = fs, fontDefaults = fd,
            fontDefaultLabel = "ZacUI's font", sample = "High Councillor's Boots" }))
        L:EndCard()

        L:Card("Time left")
        local tg, ts, td = FontOf("timeFont", 10)
        local fmtGet, fmtSet = LRAccess("formats", "time")
        local g = UI.TextElement(L, Group(L, "time", nil, { fontGet = tg, fontSet = ts, fontDefaults = td,
            fontDefaultLabel = "ZacUI's font", sample = "32s",
            formatGet = fmtGet, formatSet = fmtSet, formatDefaults = LR.TIME_DEFAULT,
            formatKinds = { time = true },
            formatSample = function(spec) return ns.FormatTime(32, spec, LR.TIME_DEFAULT) end }))
        if not LRCfg().showTime and UI.SetEnabled then UI.SetEnabled(g, false, 'Needs "Show the time left" turned on.') end
        L:Desc("Switch it on under General first.")
        L:EndCard()

        L:Card("Bind tag")
        local bg, bs, bd = FontOf("bindFont", 10)
        UI.TextElement(L, Group(L, "bind", nil, { fontGet = bg, fontSet = bs, fontDefaults = bd,
            fontDefaultLabel = "ZacUI's font", sample = "BoP" }))
        L:EndCard()

        L:Card("Small numbers")
        UI.TextElement(L, Group(L, "count", "Roll counts", {}))
        UI.TextElement(L, Group(L, "stack", "Stack count on the icon", {}))
        L:EndCard()
    end

    local function Tab_pos(L)
        L:Card("Where they come up")
        Kit.Mover(L, "lootroll", "Loot rolls")
        local lg, ls = LRAccess("layout", nil)
        local lp = UI.LayoutPicker(L.current, { width = UI.CardInnerWidth(L),
            get = lg, set = ls, defaults = { grow = "DOWN", spacingY = LR.D.gap },
            fields = { grow = true, spacingY = true }, grows = { "DOWN", "UP" } })
        L:Add(lp, 8)
        L:Desc("A second roll goes under the first one, or over it.")
        L:EndCard()

        L:Card("Parts of a bar")
        UI.FrameElement(L, Group(L, "icon", "Item icon", {}))
        UI.FrameElement(L, Group(L, "buttons", "Roll buttons", { gap = 4 }))
        L:EndCard()
    end

    local function Tab_adv(L)
        L:Card("Reset")
        Kit.Buttons(L, { { "Reset the bars", 130, function()
            ZacUIDB.lootRoll = nil
            ns.SettingsChanged("reset")
            RefreshConfig()
        end, "Every option on this page back to how the bars always looked." } })
        L:EndCard()
    end

    L:Tabs({
        { id = "general", label = "General",  build = Tab_general },
        { id = "look",    label = "Look",     build = Tab_look },
        { id = "text",    label = "Text",     build = Tab_text },
        { id = "pos",     label = "Position", build = Tab_pos },
        { id = "adv",     label = "Advanced", build = Tab_adv },
    })
end)
