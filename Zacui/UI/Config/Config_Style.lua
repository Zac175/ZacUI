-- Config_Style - choosing the look (Core_Look): the look cards, the Style
-- page, the first-run look popup and the "this part wears another look"
-- banner on part pages.
-- Part of ZacUI; load order is set by the TOC (after the config pages and
-- Config_Base's layout, before the Tutorial).
--
-- THE CARDS (ns.Look.Cards). One card per look this client can draw
-- (Look.Choices): ZacUI first, then the client's own modern look (WoW
-- Forever on Forever, Blizzard style on Retail), then Classic WoW UI.
-- Each card: a rule along the top and the name in the look's own colour
-- (ZacUI's is the palette accent), a short tag, a stage with the look's
-- miniature (Look.Preview: the real primitives under Look.With), a
-- description, and one button on the card's foot. The look the world
-- wears now (every part) carries a CURRENT LOOK badge above its card;
-- hovering a card lights its edge in its colour; the whole card clicks.
-- The same row is the popup's, the Style page's and the setup wizard's;
-- only the button words and what a click does differ (opts).
--
-- THE STYLE PAGE (Appearance > Style). The cards, each button staging its
-- look for EVERY part and asking for the reload at once; under each card
-- the parts that wear (or will wear) that look, a menu of ticks: ticking
-- a part under another card moves it there (a part is in exactly one
-- card's list). "Apply part looks" under the row is always there, dimmed
-- until a part has moved; it asks for the reload too. NOTHING IS WRITTEN
-- until a reload confirm is accepted (Look.Commit is the one writer);
-- cancelling keeps the moves staged on the page, leaving the window drops
-- them (Config_Window calls Look.Discard). Then the icon zoom.
--
-- THE FIRST-RUN POPUP. A fresh install's first thing, before the welcome
-- (which waits for it): the same cards over a dimmed screen. The current
-- look's card closes it with nothing written, so does Escape (the welcome
-- follows); any other card asks for the one reload (the welcome shows on
-- the next load). Never after "Reset ZacUI" (the setup wizard has its own
-- look step) and never on an existing install. See WHO SEES IT below.
--
-- THE BANNER. A part's page, while that part wears a look other than
-- ZacUI's, opens with one line saying so and an "Open Style" button
-- (Layout:Header draws it, Config_Base): its border, texture and colour
-- options stay as they are and apply again under ZacUI's look.

local ADDON_NAME, ns = ...

local UI = ns.UI
local Look = ns.Look
local M, F = UI.M, UI.F
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local RegisterPage = ns.RegisterPage

local ICONS = "Interface\\AddOns\\Zacui\\Media\\Icons\\"

-- THE CARD'S NUMBERS (match pass, 2026-11-07). Zac: "make it match".
-- The sizes, gaps, font sizes, colours and alphas are the numbers of the
-- reference look picker (zui_tests/MATCH_SPEC_1107.md lists each with its
-- source line); the code, words and art are ZacUI's own. Units are the
-- popup's (ShowFirstRun sets its scale: one unit = 0.96 screen pixels at
-- a 1.0 window scale); the Style page draws the same cards in its units.
local CARD_W, CARD_H, CARD_GAP = 212, 296, 16
local STAGE_W, STAGE_H = 186, 118
local BADGE_H = 16               -- room above a line for the CURRENT LOOK badge (its text rides up into the gap above)
local LINE_GAP = 8               -- between wrapped lines (+ the badge line)
local PICKER_H = M.BUTTON_H or 22
local BTN_W, BTN_H, BTN_FOOT = CARD_W - 32, 34, 14
local NAME_PT, TAG_PT, BADGE_PT, DESC_PT, BTN_PT = 17, 11, 11, 12, 14
local NAME_Y, TAG_GAP, STAGE_GAP, DESC_GAP, BADGE_GAP = -16, -3, -12, -10, 6
local DESC_W = CARD_W - 28
-- the card's own colours (fixed, as the reference's are: a warm near-black
-- card, a hairline of white at 14%, a darker stage)
local CARD_BG = { 0.103, 0.095, 0.088, 1 }
local CARD_EDGE = { 1, 1, 1, 0.14 }
local STAGE_BG = { 0.051, 0.040, 0.030, 1 }
local STAGE_EDGE = { 1, 1, 1, 0.08 }
local RULE_A, EDGE_LIT_A = 0.9, 0.9
-- the button: the look's colour behind (12%, 28% hovered, 6% with nothing
-- to do), its edge (80%, 100%, 35%) and white words (95%, 45%)
local BTN_BG_A, BTN_BG_HOVER_A, BTN_BG_OFF_A = 0.12, 0.28, 0.06
local BTN_EDGE_A, BTN_EDGE_HOVER_A, BTN_EDGE_OFF_A = 0.8, 1, 0.35
local BTN_TEXT_A, BTN_TEXT_OFF_A = 0.95, 0.45

-- THE FONT'S WIDTH. The reference's numbers are for a wider face than
-- ZacUI's HD font (Barlow Semi Condensed): at the same size its lines come
-- out about 15% narrower (measured on the reference's own lines, MATCH_SPEC).
-- Every size here is stepped by this factor so a line is as wide as the
-- reference's; the font itself stays ZacUI's.
local FONT_FIT = 1.15
Look.FONT_FIT = FONT_FIT

-- a string in the card's style: the house font at a fixed size (x
-- FONT_FIT), no outline and no shadow; its colour is painted by the caller
local function CardText(parent, size, opts)
    opts = opts or {}
    opts.outline = ""
    local fs = UI.Font(parent, size * FONT_FIT, opts)
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
    if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
    return fs
end

-- four pixel-exact strips round `target`, drawn on `frame` (ns.Pixel)
local function Edge(frame, c, target)
    local list
    if ns.Pixel and ns.Pixel.Border then
        list = ns.Pixel.Border(frame, c[1], c[2], c[3], c[4], "OVERLAY", 6, target)
    end
    return list or {}
end
local function TintEdge(list, r, g, b, a)
    for _, t in ipairs(list) do t:SetColorTexture(r, g, b, a) end
end

local function Reload()
    if ns.RequestReload then ns.RequestReload()
    elseif type(ReloadUI) == "function" then ReloadUI()
    elseif C_UI and C_UI.Reload then C_UI.Reload() end
end

-- a look's own colour: the palette accent for ZacUI's, the look's rule
-- for the others
local function LookColor(id)
    local l = Look.Get(id)
    if not l then return GetColor("ui", "accent") end
    if l.ruleKey then return GetColor(l.ruleKey[1], l.ruleKey[2]) end
    return l.rule or { r = 1, g = 1, b = 1 }
end

-- ============================================================
-- PARTS: which are loaded (a part that is off cannot be moved)
-- ============================================================
local PART_ADDON = { unitframes = "Zacui_UnitFrames", nameplates = "Zacui_Nameplates", bars = "Zacui_Bars",
    windows = "Zacui_Windows", bags = "Zacui_Bags", meter = "Zacui_Meter", auraengine = "Zacui_Auras",
    sct = "Zacui_SBT", maps = "Zacui_Maps" }
local function PartLoaded(key)
    local a = PART_ADDON[key]
    if not a then return true end
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(f) ~= "function" then return true end
    local ok, on = pcall(f, a)
    return (not ok) or on and true or false
end

local function PartLabel(key)
    for _, p in ipairs(Look.PARTS) do if p.key == key then return p.label end end
    return key
end

-- the parts a card lists: those that wear (or are staged to wear) its look
local function PartsIn(id)
    local out = {}
    for _, p in ipairs(Look.PARTS) do
        if Look.EffectiveFor(p.key) == id then out[#out + 1] = p end
    end
    return out
end

local function Summary(id)
    local list = PartsIn(id)
    if #list == 0 then return "No parts" end
    if #list == #Look.PARTS then return "Every part" end
    if #list <= 2 then
        local names = {}
        for _, p in ipairs(list) do names[#names + 1] = p.label end
        return table.concat(names, ", ")
    end
    return list[1].label .. ", " .. list[2].label .. " +" .. (#list - 2)
end

-- ============================================================
-- THE CARDS
-- ============================================================
--   ns.Look.Cards(parent, opts) -> holder
--   opts.width      the room the row has (cards wrap onto more lines)
--   opts.button(id, isCurrent) -> the card button's words
--   opts.onPick(id) a card or its button was clicked
--   opts.lit()      the id to light (green edge, the house "selected"):
--                   the setup wizard's staged pick; nil: none
--   opts.fadeCurrent  the current look's card at half strength (its
--                   badge whole): the Style page, where it has nothing to do
--   opts.parts      a parts menu under every card (the Style page);
--                   opts.onParts() runs after a move
-- holder.cards[id] = card (card.button, card.picker); holder:Refresh()
-- repaints every state; holder:Layout(room) re-flows; holder._zPaint.
function Look.Cards(parent, opts)
    opts = opts or {}
    local holder = CreateFrame("Frame", nil, parent)
    holder.cards, holder.order = {}, {}

    local function Current() return Look.LiveUniform() end

    for _, choice in ipairs(Look.Choices()) do
        local id = choice.id
        local card = CreateFrame("Button", nil, holder)
        card:SetSize(CARD_W, CARD_H)
        card._zLookId = id
        local bg = card:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg._zui_own = true
        bg:SetAllPoints()
        bg:SetColorTexture(CARD_BG[1], CARD_BG[2], CARD_BG[3], CARD_BG[4])
        card._zEdge = Edge(card, CARD_EDGE)

        -- the rule: three pixels of the look's colour along the top,
        -- inside the hairline
        local rule = card:CreateTexture(nil, "OVERLAY", nil, 7)
        rule._zui_own = true
        rule:SetTexture(FLAT)
        rule:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
        rule:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
        if ns.Pixel and ns.Pixel.Edge then ns.Pixel.Edge(rule, "TOP", card, 3) else rule:SetHeight(3) end
        card.rule = rule

        local name = CardText(card, NAME_PT, { text = choice.name, justify = "CENTER" })
        name:SetPoint("TOP", card, "TOP", 0, NAME_Y)
        name._zPaint = function(self) local c = LookColor(id) self:SetTextColor(c.r, c.g, c.b, 1) end
        name:_zPaint()
        local tag = CardText(card, TAG_PT, { text = (choice.tag or ""):upper(), justify = "CENTER" })
        tag:SetPoint("TOP", name, "BOTTOM", 0, TAG_GAP)
        tag._zPaint = function(self) local c = LookColor(id) self:SetTextColor(c.r, c.g, c.b, 0.7) end
        tag:_zPaint()

        -- the stage: a dark plate the miniature is drawn on
        local stage = CreateFrame("Frame", nil, card)
        stage:SetSize(STAGE_W, STAGE_H)
        stage:SetPoint("TOP", tag, "BOTTOM", 0, STAGE_GAP)
        local sbg = stage:CreateTexture(nil, "BACKGROUND", nil, -8)
        sbg._zui_own = true
        sbg:SetAllPoints()
        sbg:SetColorTexture(STAGE_BG[1], STAGE_BG[2], STAGE_BG[3], STAGE_BG[4])
        Edge(stage, STAGE_EDGE)
        local mini = Look.Preview(stage, id, STAGE_W, STAGE_H)
        mini:SetPoint("CENTER", stage, "CENTER", 0, 0)
        if mini.EnableMouse then mini:EnableMouse(false) end
        card.preview, card.stage = mini, stage

        -- the words: centred, three lines at most
        local desc = CardText(card, DESC_PT, { text = choice.desc, width = DESC_W, justify = "CENTER" })
        desc:SetPoint("TOP", stage, "BOTTOM", 0, DESC_GAP)
        if desc.SetMaxLines then desc:SetMaxLines(3) end
        -- (cut at three lines on purpose, as the reference's are: the card's
        -- tooltip carries the whole description)
        desc._zTruncTip = true
        desc._zPaint = function(self) self:SetTextColor(1, 1, 1, 0.7) end
        desc:_zPaint()
        card.desc = desc

        -- the button on the card's foot: the look's colour, faint behind
        -- and stronger round it
        local btn = CreateFrame("Button", nil, card)
        btn:SetSize(BTN_W, BTN_H)
        btn:SetPoint("BOTTOM", card, "BOTTOM", 0, BTN_FOOT)
        local bbg = btn:CreateTexture(nil, "BACKGROUND", nil, -6)
        bbg._zui_own = true
        bbg:SetAllPoints()
        bbg:SetTexture(FLAT)
        btn._zBg = bbg
        btn._zEdge = Edge(btn, { 1, 1, 1, 1 })
        btn._zText = CardText(btn, BTN_PT, { text = opts.button and opts.button(id, false) or "Use this look",
            justify = "CENTER" })
        btn._zText:SetPoint("CENTER", btn, "CENTER", 0, 0)
        function btn:SetLabel(t) self._zText:SetText(t) end
        btn._zPaint = function(self)
            local c = LookColor(id)
            local off, hov = card._zIdle, card._zHover
            local ba = off and BTN_BG_OFF_A or (hov and BTN_BG_HOVER_A or BTN_BG_A)
            local ea = off and BTN_EDGE_OFF_A or (hov and BTN_EDGE_HOVER_A or BTN_EDGE_A)
            self._zBg:SetVertexColor(c.r, c.g, c.b, ba)
            TintEdge(self._zEdge, c.r, c.g, c.b, ea)
            self._zText:SetTextColor(1, 1, 1, off and BTN_TEXT_OFF_A or BTN_TEXT_A)
        end
        card.button = btn

        -- the badge above the card, on the holder (so a faded card's badge
        -- stays whole)
        local badge = CardText(holder, BADGE_PT, { text = "CURRENT LOOK", justify = "CENTER" })
        badge:SetPoint("BOTTOM", card, "TOP", 0, BADGE_GAP)
        badge._zPaint = function(self) local c = LookColor(id) self:SetTextColor(c.r, c.g, c.b, 1) end
        badge:_zPaint()
        badge:Hide()
        card.badge = badge

        local function Pick()
            if opts.onPick then opts.onPick(id) end
        end
        card:SetScript("OnClick", Pick)
        btn:SetScript("OnClick", Pick)
        local function Enter() card._zHover = true card:_zPaint() end
        local function Leave() card._zHover = nil card:_zPaint() end
        card:HookScript("OnEnter", Enter)
        card:HookScript("OnLeave", Leave)
        btn:HookScript("OnEnter", Enter)
        btn:HookScript("OnLeave", Leave)
        UI.Tooltip(card, choice.name, choice.desc)

        -- lit: the mouse on it or the current look (the look's colour), or
        -- the setup wizard's staged pick (the house "selected" green)
        card._zPaint = function(self)
            local c = LookColor(id)
            self.rule:SetVertexColor(c.r, c.g, c.b, RULE_A)
            if self._zHover or self._zCurrent then
                TintEdge(self._zEdge, c.r, c.g, c.b, EDGE_LIT_A)
            elseif self._zLit then
                local e = GetColor("ui", "borderSelected")
                TintEdge(self._zEdge, e.r, e.g, e.b, e.a or 1)
            else
                TintEdge(self._zEdge, CARD_EDGE[1], CARD_EDGE[2], CARD_EDGE[3], CARD_EDGE[4])
            end
            for _, fs in ipairs({ name, tag, desc, badge }) do if fs._zPaint then fs:_zPaint() end end
            if self.preview and self.preview._zPaint then self.preview:_zPaint() end
            btn:_zPaint()
        end

        -- the parts menu under the card (the Style page)
        if opts.parts then
            local picker = UI.Button(holder, Summary(id), { width = CARD_W, height = PICKER_H,
                tooltip = "The parts that wear this look. Tick a part here to move it to " .. choice.name
                    .. "; the move is kept until you apply it." })
            picker:SetPoint("TOP", card, "BOTTOM", 0, -6)
            local arrow = picker:CreateTexture(nil, "OVERLAY")
            arrow._zui_own = true
            arrow:SetTexture(ns.TEX_ARROW or FLAT)
            arrow:SetSize(10, 10)
            arrow:SetPoint("RIGHT", picker, "RIGHT", -6, 0)
            arrow._zPaint = function(self)
                local c = GetColor("dropdown", "arrow")
                self:SetVertexColor(c.r, c.g, c.b, c.a or 1)
            end
            arrow:_zPaint()
            picker:SetScript("OnClick", function(self)
                local items = { { text = choice.name, isTitle = true } }
                for _, p in ipairs(Look.PARTS) do
                    local key = p.key
                    local loaded = PartLoaded(key)
                    items[#items + 1] = {
                        text = p.label,
                        keepOpen = true,
                        disabled = not loaded,
                        tooltip = (not loaded) and ("Turn " .. p.label .. " on to give it a look.") or nil,
                        checked = function() return Look.EffectiveFor(key) == id end,
                        func = function()
                            -- ticking moves the part here; it leaves a card
                            -- only by being ticked under another
                            if Look.EffectiveFor(key) ~= id then
                                Look.StagePart(key, id)
                                holder:Refresh()
                                if opts.onParts then opts.onParts() end
                            end
                        end,
                    }
                end
                if UI.ContextMenu then UI.ContextMenu(items, { anchor = self }) end
            end)
            card.picker = picker
        end

        holder.cards[id] = card
        holder.order[#holder.order + 1] = card
    end

    function holder:Refresh()
        local cur = Current()
        local lit = opts.lit and opts.lit() or nil
        for _, card in ipairs(self.order) do
            local id = card._zLookId
            local isCur = (id == cur)
            card._zCurrent = isCur or nil
            card._zLit = (lit ~= nil and id == lit and not isCur) or nil
            -- (the Style page's current card has nothing to do: its button dims)
            card._zIdle = (isCur and opts.fadeCurrent) or nil
            card.badge:SetShown(isCur)
            card:SetAlpha((isCur and opts.fadeCurrent) and 0.55 or 1)
            if opts.button then card.button:SetLabel(opts.button(id, isCur)) end
            if card.picker then card.picker:SetLabel(Summary(id)) end
            card:_zPaint()
        end
    end

    -- left to right, wrapping; each line keeps room above for the badges
    local extra = opts.parts and (6 + PICKER_H) or 0
    function holder:Layout(room)
        room = room or opts.width or 400
        local x, y, h = 0, -BADGE_H, 0
        for _, card in ipairs(self.order) do
            if x > 0 and x + CARD_W > room + 0.5 then
                x = 0
                y = y - CARD_H - extra - LINE_GAP - BADGE_H
            end
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
            x = x + CARD_W + CARD_GAP
        end
        h = -y + CARD_H + extra
        -- a row narrower than the room sits centred in it
        local perLine = math.max(1, math.floor((room + CARD_GAP) / (CARD_W + CARD_GAP)))
        local lineN = math.min(perLine, #self.order)
        local used = lineN * CARD_W + (lineN - 1) * CARD_GAP
        local shift = math.max(0, math.floor((room - used) / 2))
        if shift > 0 then
            for _, card in ipairs(self.order) do
                local p, rel, rp, cx, cy = card:GetPoint(1)
                card:ClearAllPoints()
                card:SetPoint(p or "TOPLEFT", rel or self, rp or "TOPLEFT", (cx or 0) + shift, cy or 0)
            end
        end
        self:SetSize(math.max(CARD_W, room), h)
        return h
    end
    function holder:_zFit(w) self:Layout(w) end
    holder._zPaint = function(self) self:Refresh() end

    holder:Layout(opts.width)
    holder:Refresh()
    return holder
end
Look.CARD_W, Look.CARD_H, Look.CARD_GAP = CARD_W, CARD_H, CARD_GAP

-- ============================================================
-- THE RELOAD CONFIRM (the only path to Look.Commit from here)
-- ============================================================
local function ConfirmApply(what, onCancel)
    UI.Confirm({
        title = "Change the look",
        text = what .. " The interface reloads once; your settings, positions and colours stay as they are.",
        acceptText = "Reload now",
        onAccept = function()
            if type(ZacUIDB) ~= "table" then return end
            -- the reload FIRST, at the start of the click (WoW Forever turns
            -- down one asked for after the click saved things, build 70425;
            -- UIF_Dialogs' ns.AskReload), then the one place a look is
            -- written, still inside the click: the reload saves it
            Reload()
            Look.Commit()
        end,
        onCancel = onCancel,
    })
end
Look.ConfirmApply = ConfirmApply

-- ============================================================
-- THE STYLE PAGE
-- ============================================================
local function StylePage(L)
    L:Header("Style", "Which art the world wears. Your settings, positions and colours carry over; "
        .. "only the look changes. This window and Readycheck keep ZacUI's look.")

    local card = L:Card("Looks")
    L:Desc("Put one look on everything, or give each part a look of its own with the lists under the cards. "
        .. "A change applies at a reload.")
    L:Gap(4)
    local apply
    local function SyncApply()
        if not apply then return end
        local on = Look.Dirty()
        apply:SetDisabled(not on, "Pick a different look first: nothing to apply yet.")
        apply:SetAlpha(on and 1 or 0.35)
        apply:EnableMouse(on)
    end
    local row
    row = Look.Cards(card, {
        width = L:Room(),
        fadeCurrent = true,
        parts = true,
        onParts = function() SyncApply() end,
        button = function(id, isCur) return isCur and "Current look" or "Use everywhere" end,
        onPick = function(id)
            if Look.LiveUniform() == id and not Look.Dirty() then return end
            Look.StageEverywhere(id)
            row:Refresh()
            SyncApply()
            ConfirmApply("Every part goes to the " .. (Look.Get(id).name) .. " look.", function()
                Look.Discard()
                row:Refresh()
                SyncApply()
            end)
        end,
    })
    L:Add(row, 6)
    apply = UI.Button(card, "Apply part looks", { width = 180, height = 26,
        tooltip = "Saves the parts you moved between the cards and reloads the interface. "
            .. "Nothing is saved until you confirm.",
        onClick = function()
            if not Look.Dirty() then return end
            ConfirmApply("The parts you moved change look.", function() row:Refresh() SyncApply() end)
        end })
    local room = L:Room() or 400
    L:Add(apply, 10, (M.CONTROL_X or 12) + math.max(0, math.floor((room - 180) / 2)))
    SyncApply()
    L:EndCard()

    -- icon zoom: how much of the game's bevel every icon ZacUI draws cuts
    -- away (ZacUI's look; Classic keeps the game's frame). Live: the icons
    -- re-crop as it moves (Look.RecropAll), no reload
    if Look.IconCrop and Look.IconSamples then
        L:Card("Icon zoom")
        local base = Look.Get("zacui").iconCrop
        local basePct = math.floor(base * 100 + 0.5)
        local function Shown() return math.floor((tonumber(ZacUIDB.iconZoom) or base) * 100 + 0.5) end
        local zs = UI.Slider(L.current, { width = 220, min = 0, max = 25, step = 1, value = Shown(), label = "Icon zoom",
            format = function(v) return v .. "%" end,
            onChange = function(v)
                -- the look's own value saves as nothing
                ZacUIDB.iconZoom = (v ~= basePct) and (v / 100) or nil
                Look.RecropAll()
                if ns.Bars and ns.Bars.ApplyAll then pcall(ns.Bars.ApplyAll) end
                if ns.BuffLook and ns.BuffLook.Changed then pcall(ns.BuffLook.Changed) end
            end })
        L:Row(zs, 40)
        L:Desc("How far every icon is zoomed in, so none of the game's icon frame shows (ZacUI's look; "
            .. basePct .. "% by default). The Classic look keeps the game's frame.")
        L:Add(Look.IconSamples(L.current), 6)
        L:EndCard()
    end
end
if RegisterPage then RegisterPage("Style", StylePage) end

-- ============================================================
-- THE BANNER (Layout:Header calls it on every live page)
-- ============================================================
local PAGE_PART = {
    unitframes = "unitframes", nameplates = "nameplates", bars = "bars", minimap = "minimap",
    chat = "chat", tooltips = "tooltip", buffs = "auras", bags = "bags", meter = "meter",
    sbt = "sct", maps = "maps", auras = "auraengine", auction = "bags", lootroll = "blizzard",
}
Look.PAGE_PART = PAGE_PART

function ns.LookBanner(L)
    local part = L and PAGE_PART[L.pageId]
    if not part then return end
    local live = Look.LiveFor(part)
    if live == "zacui" then return end
    local l = Look.Get(live)
    if not l then return end
    local label = PartLabel(part)
    local card = L:Card("Look")
    local text = label .. " wear the " .. l.name .. " look. Some options here only affect ZacUI's own look; "
        .. "they are kept for when it is back."
    local fs = UI.Font(card, F.DESC, { text = text, cat = "text", key = "normal",
        width = math.max(120, (UI.Room(card) or 400) - 120) })
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", M.DESC_X or 12, card._y + 3)
    local b = UI.Button(card, "Open Style", { width = 104, onClick = function()
        if ns.OpenConfig then ns.OpenConfig("style") end
    end })
    b:SetPoint("TOPRIGHT", card, "TOPRIGHT", -(M.CONTROL_X or 12), card._y + 4)
    local ic = b:CreateTexture(nil, "OVERLAY")
    ic._zui_own = true
    ic:SetTexture(ICONS .. "settings")
    ic:SetSize(12, 12)
    ic:SetPoint("LEFT", b, "LEFT", 6, 0)
    local c = LookColor(live)
    ic:SetVertexColor(c.r, c.g, c.b, 1)
    card._zLookBanner = live
    card._y = card._y - math.max(PICKER_H + 4, math.ceil(fs:GetStringHeight() or 12)) - 6
    L:EndCard()
    return card
end

-- ============================================================
-- THE FIRST-RUN POPUP
-- ============================================================
local popup, dimmer

-- THE POPUP'S NUMBERS (the reference's, MATCH_SPEC_1107.md): 700 wide at
-- least (the card row + 32), 480 tall, the warm near-black fill with a one
-- pixel edge of white at 15%, the screen dimmed to 45%, text sizes 13 / 26
-- / 14 and 12 for the footnote.
local POPUP_MIN_W, POPUP_H = 700, 480
local POPUP_BG = { 0.077, 0.068, 0.058, 1 }
local POPUP_EDGE = { 1, 1, 1, 0.15 }
local EYEBROW_PT, TITLE_PT, SUB_PT, FOOT_PT = 13, 26, 14, 12
-- how big a popup unit is on screen: 1.15 x 768 / (1440 x 0.64) = 0.958
-- screen pixels, times the ZacUI window's own scale (the same knob that
-- sizes /zui). Without the screen's size (a test stub) the popup keeps
-- UIParent's units.
local POPUP_PX = 1.15 * 768 / (1440 * 0.64)
local function PopupScale(parent)
    local gps = _G.GetPhysicalScreenSize
    if type(gps) ~= "function" then return 1 end
    local ok, _, h = pcall(gps)
    if not (ok and type(h) == "number" and h > 0) then return 1 end
    local es = parent and parent.GetEffectiveScale and parent:GetEffectiveScale()
    if type(es) ~= "number" or es <= 0 then return 1 end
    local user = type(ZacUIDB) == "table" and type(ZacUIDB.config) == "table" and tonumber(ZacUIDB.config.scale) or 1
    -- px per unit = effective scale x physical height / 768
    local want = POPUP_PX * user * 768 / h
    local sc = want / es
    if sc ~= sc or sc <= 0 then return 1 end
    return sc
end


local function Stamp()
    if type(ZacUIDB) == "table" and type(ZacUIDB.tutorial) == "table" then ZacUIDB.tutorial.lookPicked = true end
end

function Look.ShowFirstRun()
    if not dimmer then
        dimmer = CreateFrame("Frame", "ZacUILookPopupDim", UIParent)
        dimmer:SetAllPoints(UIParent)
        dimmer:SetFrameStrata("DIALOG")
        dimmer:EnableMouse(true)
        local t = dimmer:CreateTexture(nil, "BACKGROUND")
        t._zui_own = true
        t:SetAllPoints()
        t:SetColorTexture(0, 0, 0, 0.45)
        -- closing it (the current look's card, Escape) stamps it and lets
        -- the welcome come next; a reload never gets here. Set once, here:
        -- the login queue (Core_Popups) hooks this frame's OnHide too.
        dimmer:SetScript("OnHide", function() Stamp() if Look.ReleaseWelcome then Look.ReleaseWelcome() end end)
    end
    if popup then popup:Hide() popup = nil end
    local n = #Look.Choices()
    local rowW = n * CARD_W + (n - 1) * CARD_GAP
    local W, H = math.max(POPUP_MIN_W, rowW + 32), POPUP_H
    local f = CreateFrame("Frame", "ZacUILookPopup", dimmer)
    popup = f
    f:SetScale(PopupScale(dimmer))
    f:SetSize(W, H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg._zui_own = true
    bg:SetAllPoints()
    bg:SetColorTexture(POPUP_BG[1], POPUP_BG[2], POPUP_BG[3], POPUP_BG[4])
    Edge(f, POPUP_EDGE)

    local eyebrow = CardText(f, EYEBROW_PT, { text = "WELCOME TO ZACUI", justify = "CENTER" })
    eyebrow:SetPoint("TOP", f, "TOP", 0, -26)
    eyebrow._zPaint = function(self) local c = GetColor("ui", "accent") self:SetTextColor(c.r, c.g, c.b, 0.9) end
    eyebrow:_zPaint()
    local title = CardText(f, TITLE_PT, { text = "Pick a look to start in", justify = "CENTER" })
    title:SetPoint("TOP", eyebrow, "BOTTOM", 0, -6)
    title._zPaint = function(self) self:SetTextColor(1, 1, 1, 1) end
    title:_zPaint()
    local sub = CardText(f, SUB_PT, { text = "Every ZacUI feature works in every look. Mix looks part by part "
        .. "any time on the Style page.", justify = "CENTER", width = W - 90 })
    sub:SetPoint("TOP", title, "BOTTOM", 0, -10)
    sub._zPaint = function(self) self:SetTextColor(1, 1, 1, 0.5) end
    sub:_zPaint()

    local live = Look.LiveUniform() or Look.Active()
    local function Close() Stamp() dimmer:Hide() end
    local row = Look.Cards(f, {
        width = rowW,
        -- "Use <the look>" on each card, "In use" on the current one (its
        -- click keeps the look and closes the popup)
        button = function(id, isCur)
            if isCur then return "In use" end
            local l = Look.Get(id)
            return "Use " .. (l and l.name or id)
        end,
        onPick = function(id)
            if id == live then Close() return end
            Look.StageEverywhere(id)
            ConfirmApply("ZacUI starts in the " .. Look.Get(id).name .. " look.", function() Look.Discard() end)
        end,
    })
    -- the cards' tops 138 under the popup's (the holder keeps the badge
    -- line above them)
    row:SetPoint("TOP", f, "TOP", 0, -138 + BADGE_H)
    f.row = row

    local others = {}
    for _, ch in ipairs(Look.Choices()) do if ch.id ~= live then others[#others + 1] = ch.name end end
    local foot = CardText(f, FOOT_PT, { justify = "CENTER", width = W - 90,
        text = (#others > 0 and ("Starting in " .. table.concat(others, " or ") .. " reloads once. ") or "")
            .. "Esc keeps the current look." })
    foot:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    foot._zPaint = function(self) self:SetTextColor(1, 1, 1, 0.35) end
    foot:_zPaint()

    -- Escape: keep the look (nothing written)
    if UISpecialFrames then
        local seen = false
        for _, nm in ipairs(UISpecialFrames) do if nm == "ZacUILookPopupDim" then seen = true end end
        if not seen then table.insert(UISpecialFrames, "ZacUILookPopupDim") end
    end
    dimmer:Show()
    return f
end

-- WHO SEES IT, AND WHEN (the first-run order, so nothing stacks):
--   a fresh install          the look popup FIRST; the welcome waits for it
--                            (in the login popup queue, Core_Popups: the
--                            look at 20, the welcome at 30; without the
--                            queue Tutorial_Core's TryShow asks HoldWelcome). A
--                            look that needs a reload reloads - the stamp
--                            (tutorial.lookPicked, set by Look.Commit) rides
--                            the reload and the welcome shows on the next
--                            load; keeping the look or Escape shows the
--                            welcome after the popup has closed.
--   after "Reset ZacUI"      never (ns.openSetupAfterReset: the setup
--                            wizard opens by itself and has its own look step)
--   an existing install      never
local holding = false
function Look.HoldWelcome() return holding end

function Look.FirstRunDue()
    if type(ZacUIDB) ~= "table" then return false end
    if ns.openSetupAfterReset then return false end
    local st = ZacUIDB.tutorial
    if type(st) == "table" then
        if st.existing or not st.fresh or st.lookPicked then return false end
    elseif not ns.freshInstall then
        return false
    end
    -- a look already saved counts as chosen
    if ZacUIDB.look ~= nil then
        if type(st) == "table" then st.lookPicked = true end
        return false
    end
    return #Look.Choices() > 1
end

local function Released()
    if not holding then return end
    holding = false
    if ns.Tutorial and ns.Tutorial.ResumeWelcome then ns.Tutorial.ResumeWelcome() end
end
Look.ReleaseWelcome = Released

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if not Look.FirstRunDue() then return end
        holding = true
        -- its turn in the login popup queue (after the import offer, before
        -- the welcome; never in combat): the queue waits for the dimmer
        if ns.Popups then
            ns.Popups.Want("look", function()
                local ok = pcall(Look.ShowFirstRun)
                -- a popup that could not be drawn must not hold the welcome
                if not ok then Released() return nil end
                return dimmer
            end, { delay = 2 })
            return
        end
        local function Try()
            if InCombatLockdown and InCombatLockdown() then
                self:RegisterEvent("PLAYER_REGEN_ENABLED")
                return
            end
            local ok = pcall(Look.ShowFirstRun)
            -- a popup that could not be drawn must not hold the welcome
            if not ok then Released() end
        end
        self._zTry = Try
        if C_Timer and C_Timer.After then C_Timer.After(2, Try) else Try() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if self._zTry then self._zTry() end
    end
end)
