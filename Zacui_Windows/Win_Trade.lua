-- Win_Trade - ZacUI's trade window.
-- Part of ZacUI; load order is set by the TOC.
--
-- A cover over TradeFrame, like the merchant or the mailbox, with ONE
-- difference that shapes the whole thing: your gold / silver / copper
-- boxes (TradePlayerInputMoneyFrame) are a FORBIDDEN frame. No addon may
-- touch it - not move it, not skin it, not call a method on it - and it
-- only works where Blizzard put it. So the cover is cut around it: the
-- background is drawn in four pieces that leave that one rectangle open,
-- a ZacUI ring frames it, and Blizzard's own money boxes show through
-- and take your typing as they always have. Everything else - both
-- sides' items, their money, the names, who has accepted, Trade and
-- Cancel - is ZacUI's.
--
-- The cover takes no mouse itself, only its rows and buttons do. A click
-- anywhere else lands on TradeFrame underneath, whose own handler drops
-- whatever the cursor holds into the first free slot - Blizzard's
-- behaviour, kept.
--
--   Your rows       click / drag an item in or out, right-click as
--                   Blizzard's slot does, shift / ctrl-click to link or
--                   preview
--   Their rows      click to put your enchant on the item in their
--                   "will not be traded" slot; shift / ctrl-click as above
--   Trade           AcceptTrade, disabled whenever Blizzard's is (more
--                   money typed than you have, already accepted)
--   Cancel          Blizzard's cancel: takes back an accept first, then
--                   closes the trade

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local UI = ns.UI

local M, F = UI.M, UI.F

-- Blizzard's geometry (TradeFrame.xml): the frame is 344 x 446 and the
-- money boxes sit in the inset at (4, -58) .. (166, -82).
local HOLE_L, HOLE_R, HOLE_T, HOLE_B = 4, 166, -58, -82
local LEFT_X, RIGHT_X, COL_W = 4, 176, 162
local HEAD_T, HEAD_H = -28, 26
local ROWS_T = -88
local ROW_H, ROW_GAP = 38, 4
local ICON = 34
local NUM_TRADE = 7
local NUM_TRADABLE = 6
local FOOT_H = 36

local win, sides, tradeBtn, cancelBtn, warnIcon, theirMoney, title
local targetAccepted = 0

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.tradewin ~= false
end

local function Str(name, fallback)
    local v = _G[name]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

-- ============================================================
-- REFRESH
-- ============================================================
local function PlayerSlot(i)
    local name, texture, count, quality, enchantment = GetTradePlayerItemInfo(i)
    return name, texture, count, quality, true, enchantment
end

local function TargetSlot(i)
    local name, texture, count, quality, isUsable, enchantment = GetTradeTargetItemInfo(i)
    return name, texture, count, quality, isUsable, enchantment
end

local function FillRow(row, name, texture, count, quality, usable, enchantment)
    row.hasItem = texture and true or false
    if texture then
        row.icon:SetIcon(texture)
        row.icon:SetCount(count)
        row.icon:SetQuality(quality)
        row.icon:SetUsable(usable ~= false)
    else
        row.icon:SetIcon(nil)
        row.icon:SetCount(0)
        row.icon:SetQuality(nil)
        row.icon:SetUsable(true)
    end
    if row.index == NUM_TRADE then
        -- The untraded slot: what matters is the enchant, not the name.
        if name then
            row.nameText:SetText(name)
            row.nameText:SetTextColor(ns.QualityRGB(quality))
            if enchantment then
                row.sub:SetText(enchantment)
                row.sub:SetTextColor(Kit.TextRGB("green"))
            else
                row.sub:SetText(Str("TRADEFRAME_NOT_MODIFIED_TEXT", "Will not be modified"))
                row.sub:SetTextColor(Kit.TextRGB("gray"))
            end
        else
            row.nameText:SetText("")
            row.sub:SetText("")
        end
        return
    end
    if name then
        row.nameText:SetText(name)
        row.nameText:SetTextColor(ns.QualityRGB(quality))
    else
        row.nameText:SetText("")
    end
    row.sub:SetText("")
end

local function PaintSide(side, accepted)
    local key = accepted and "borderSelected" or "border"
    for _, box in ipairs({ side.head, side.body }) do
        box._zBorderKey = key
        box:_zPaint()
    end
    side.tag:SetShown(accepted)
end

local function Refresh()
    -- IsVisible, not IsShown: the cover is a shown child of TradeFrame all
    -- session, so IsShown was true with no trade open and every item-info
    -- event in the game repainted both sides of a trade nobody had.
    if not win or not win:IsVisible() then return end
    title:SetText(string.format("%s - %s", Str("TRADE", "Trade"), GetUnitName("NPC", true) or "?"))
    sides.player.nameText:SetText(GetUnitName("player", true) or "")
    sides.target.nameText:SetText(GetUnitName("NPC", true) or "")
    local _, class = UnitClass("NPC")
    if class then sides.target.nameText:SetTextColor(ns.ClassColor(class))
    else sides.target.nameText:_zPaint() end
    local _, myClass = UnitClass("player")
    if myClass then sides.player.nameText:SetTextColor(ns.ClassColor(myClass))
    else sides.player.nameText:_zPaint() end

    for i = 1, NUM_TRADE do
        FillRow(sides.player.rows[i], PlayerSlot(i))
        FillRow(sides.target.rows[i], TargetSlot(i))
    end

    theirMoney:SetText(ns.Money(GetTargetTradeMoney and GetTargetTradeMoney() or 0))

    local mine = (TradeFrame and TradeFrame.acceptState == 1)
    PaintSide(sides.player, mine)
    PaintSide(sides.target, targetAccepted == 1)

    -- Blizzard's Trade button is the single source of truth for whether
    -- accepting is allowed (it disables itself for too much money typed,
    -- or once you have accepted).
    local blizz = TradeFrameTradeButton
    local ok = blizz and blizz:IsEnabled()
    tradeBtn:SetDisabled(not ok)
    tradeBtn:SetActive(mine)
    tradeBtn:SetLabel(mine and "Accepted" or Str("TRADE", "Trade"))
    warnIcon:SetShown(blizz and blizz.warningTooltip and true or false)
end

local Queue = Kit.Coalesce(Refresh, function() return win end)

-- ============================================================
-- ROWS
-- ============================================================
local function RowTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if row.side == "player" then
        if row.hasItem then
            GameTooltip:SetTradePlayerItem(row.index)
        elseif row.index == NUM_TRADE then
            GameTooltip:SetText(Str("ENCHANT_SLOT", "Enchant slot"), 1, 1, 1)
            local c = GetColor("tooltip", "body")
            GameTooltip:AddLine(Str("NEWBIE_TOOLTIP_ENCHANTSLOT",
                "Items placed here will not be traded, but can be enchanted by the other player."),
                c.r, c.g, c.b, true)
        else
            GameTooltip:Hide()
            return
        end
    else
        if not row.hasItem then GameTooltip:Hide() return end
        GameTooltip:SetTradeTargetItem(row.index)
    end
    GameTooltip:Show()
    if CursorUpdate then CursorUpdate(row) end
end

local function RowClick(row, button)
    local i = row.index
    if row.side == "player" then
        if IsModifiedClick() then
            HandleModifiedItemClick(GetTradePlayerItemLink(i))
        else
            ClickTradeButton(i, button == "RightButton")
        end
    else
        if IsModifiedClick() then
            HandleModifiedItemClick(GetTradeTargetItemLink(i))
        else
            ClickTargetTradeButton(i)
        end
    end
end

local function BuildRow(parent, side, index, y)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, y)
    row.side, row.index = side, index
    UI.Fill(row, "ui", "elementBg")
    row._zNormalKey = "elementBg"
    row._zPaint = function(self)
        local c = GetColor("ui", "elementBg")
        self._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1)
    end
    row:_zPaint()
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl._zui_own = true
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    hl:SetBlendMode("ADD")

    row.icon = Kit.Icon(row, ICON)
    row.icon:SetPoint("LEFT", 2, 0)

    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -2)
    row.nameText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
    row.nameText:SetWordWrap(true)
    row.nameText:SetJustifyV("MIDDLE")

    row.sub = UI.Font(row, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.sub:SetWordWrap(false)

    if index == NUM_TRADE then
        -- Name on top, enchant under it.
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -3)
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.nameText:SetWordWrap(false)
    end

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if side == "player" then
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self) ClickTradeButton(self.index) end)
        row:SetScript("OnReceiveDrag", function(self) ClickTradeButton(self.index) end)
    end
    row:SetScript("OnClick", RowClick)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if ResetCursor then ResetCursor() end
    end)
    row.UpdateTooltip = RowTooltip
    return row
end

-- One side: a header (name, "Accepted") and a body with the six traded
-- rows, a rule, the "will not be traded" label and its row.
local function BuildSide(key, x)
    local side = { rows = {} }

    local head = UI.Box(win, "ui", "headerBg")
    head:SetPoint("TOPLEFT", win, "TOPLEFT", x, HEAD_T)
    head:SetSize(COL_W, HEAD_H)
    side.head = head
    side.nameText = UI.Font(head, F.CARD, { justify = "LEFT" })
    side.nameText:SetPoint("LEFT", 8, 0)
    side.nameText:SetPoint("RIGHT", -64, 0)
    side.nameText:SetWordWrap(false)
    side.tag = UI.Font(head, F.SMALL, { cat = "text", key = "green", justify = "RIGHT",
        text = "Accepted" })
    side.tag:SetPoint("RIGHT", -8, 0)
    side.tag:Hide()

    local body = UI.Box(win, "ui", "cardBg")
    body:SetPoint("TOPLEFT", win, "TOPLEFT", x, ROWS_T + 4)
    body:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", x, FOOT_H + 6)
    body:SetWidth(COL_W)
    side.body = body

    local y = -4
    for i = 1, NUM_TRADABLE do
        side.rows[i] = BuildRow(body, key, i, y)
        y = y - ROW_H - ROW_GAP
    end
    local rule = body:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", body, "TOPLEFT", 1, y - 2)
    rule:SetPoint("TOPRIGHT", body, "TOPRIGHT", -1, y - 2)
    local label = UI.Font(body, F.SMALL, { cat = "text", key = "gray", justify = "LEFT",
        text = Str("TRADEFRAME_ENCHANT_SLOT_LABEL", "Will not be traded:") })
    label:SetPoint("TOPLEFT", body, "TOPLEFT", 8, y - 8)
    side.rows[NUM_TRADE] = BuildRow(body, key, NUM_TRADE, y - 22)
    body._zPaint = function(self)
        UI.PaintBox(self)
        local b = GetColor("ui", "border")
        rule:SetVertexColor(b.r, b.g, b.b, b.a or 1)
    end
    body:_zPaint()
    return side
end

-- ============================================================
-- BUILD
-- ============================================================
local function Build()
    if win then return win end
    local host = TradeFrame
    win = CreateFrame("Frame", "ZacUITradeWindow", host)
    win:SetAllPoints(host)
    win:SetFrameStrata(host:GetFrameStrata())
    win:SetFrameLevel(math.min(host:GetFrameLevel() + 50, 9000))
    -- No mouse on the cover itself: clicks between the rows reach
    -- TradeFrame, which drops the cursor's item into a free slot.
    win:EnableMouse(false)

    -- The background, in four pieces round the money boxes.
    local pieces = {}
    local function Piece()
        local t = win:CreateTexture(nil, "BACKGROUND", nil, -7)
        t._zui_own = true
        t:SetTexture(FLAT)
        pieces[#pieces + 1] = t
        return t
    end
    local top = Piece()
    top:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    top:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", 0, HOLE_T + 1)
    local bottom = Piece()
    bottom:SetPoint("TOPLEFT", win, "TOPLEFT", 0, HOLE_B - 1)
    bottom:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
    local left = Piece()
    left:SetPoint("TOPLEFT", win, "TOPLEFT", 0, HOLE_T + 1)
    left:SetPoint("BOTTOMRIGHT", win, "TOPLEFT", HOLE_L - 1, HOLE_B - 1)
    local right = Piece()
    right:SetPoint("TOPLEFT", win, "TOPLEFT", HOLE_R + 1, HOLE_T + 1)
    right:SetPoint("BOTTOMRIGHT", win, "TOPRIGHT", 0, HOLE_B - 1)
    UI.Border(win, "ui", "border")

    -- The ring round Blizzard's money boxes, so they read as a field of
    -- this window rather than a gap in it.
    local ring = CreateFrame("Frame", nil, win)
    ring:SetPoint("TOPLEFT", win, "TOPLEFT", HOLE_L - 1, HOLE_T + 1)
    ring:SetPoint("BOTTOMRIGHT", win, "TOPLEFT", HOLE_R + 1, HOLE_B - 1)
    ring:EnableMouse(false)
    UI.Border(ring, "ui", "border")
    ring._zPaint = UI.PaintBox
    ring:_zPaint()

    -- Title bar
    local bar = CreateFrame("Frame", nil, win)
    bar:SetHeight(24)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    UI.Fill(bar, "ui", "headerBg")
    local barRule = bar:CreateTexture(nil, "ARTWORK")
    barRule._zui_own = true
    barRule:SetTexture(FLAT)
    barRule:SetHeight(1)
    barRule:SetPoint("BOTTOMLEFT")
    barRule:SetPoint("BOTTOMRIGHT")
    title = UI.Font(bar, F.TITLE, { cat = "text", key = "gold", justify = "LEFT" })
    title:SetPoint("LEFT", 10, 0)
    title:SetPoint("RIGHT", -34, 0)
    title:SetWordWrap(false)
    local close = UI.CloseX(bar, 20, function() HideUIPanel(TradeFrame) end)
    close:SetPoint("RIGHT", -4, 0)
    if ns.AttachWindowDrag then ns.AttachWindowDrag(bar, host) end
    bar._zPaint = function(self)
        local h = GetColor("ui", "headerBg")
        self._zFill:SetVertexColor(h.r, h.g, h.b, h.a or 1)
        local a = GetColor("ui", "accent")
        barRule:SetVertexColor(a.r, a.g, a.b, 0.6)
        title:_zPaint()
    end
    bar:_zPaint()

    sides = {
        player = BuildSide("player", LEFT_X),
        target = BuildSide("target", RIGHT_X),
    }

    -- Their money, in the right side's money row.
    local money = UI.Box(win, "ui", "elementBg")
    money:SetPoint("TOPLEFT", win, "TOPLEFT", RIGHT_X, HOLE_T)
    money:SetSize(COL_W, HOLE_T - HOLE_B)
    theirMoney = UI.Font(money, F.LABEL, { justify = "RIGHT" })
    theirMoney:SetPoint("RIGHT", -8, 0)
    local moneyLabel = UI.Font(money, F.SMALL, { cat = "text", key = "gray", justify = "LEFT",
        text = Str("MONEY", "Money") })
    moneyLabel:SetPoint("LEFT", 8, 0)

    -- Footer: Trade and Cancel.
    local foot = Kit.Footer(win, FOOT_H)
    cancelBtn = UI.Button(foot, Str("CANCEL", "Cancel"), { width = 90, height = 24 })
    cancelBtn:SetPoint("RIGHT", foot, "RIGHT", -8, 0)
    cancelBtn:SetScript("OnClick", function()
        if TradeFrameCancelButton_OnClick then TradeFrameCancelButton_OnClick()
        else HideUIPanel(TradeFrame) end
    end)
    tradeBtn = UI.Button(foot, Str("TRADE", "Trade"), { width = 100, height = 24 })
    tradeBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -6, 0)
    tradeBtn:SetScript("OnClick", function()
        if TradeFrameTradeButton and TradeFrameTradeButton:IsEnabled() then AcceptTrade() end
    end)
    -- Blizzard's warning (the other player changed their offer after you
    -- looked): same icon, same tooltip text.
    warnIcon = tradeBtn:CreateTexture(nil, "OVERLAY")
    warnIcon._zui_own = true
    warnIcon:SetSize(16, 16)
    warnIcon:SetPoint("LEFT", tradeBtn, "LEFT", 5, 0)
    warnIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    warnIcon:Hide()
    tradeBtn:HookScript("OnEnter", function(self)
        local tip = TradeFrameTradeButton and TradeFrameTradeButton.warningTooltip
        if tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local r = GetColor("text", "red")
            GameTooltip:SetText(tip, r.r, r.g, r.b, 1, true)
            GameTooltip:Show()
        end
    end)
    tradeBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    win._zPaint = function(self)
        -- the window's colour (the theme's, or the Game windows page's)
        local r, g, b = Kit.Color("bg", "ui", "windowBg", 1)
        for _, t in ipairs(pieces) do t:SetVertexColor(r, g, b, 1) end
        Kit.StyleCover(self)
    end
    win:_zPaint()

    win:HookScript("OnShow", Queue)
    return win
end

-- ============================================================
-- HIDING BLIZZARD'S LOOK
-- ============================================================
-- Listed one by one, never by walking TradeFrame's children: that walk
-- would hand back the forbidden money frame, and touching it errors.
local function Leftovers()
    local f = TradeFrame
    local t = {}
    local function Add(x) if x and x ~= win then t[#t + 1] = x end end
    for _, r in ipairs({ f:GetRegions() }) do Add(r) end
    Add(f.NineSlice)
    Add(f.PortraitContainer)
    Add(f.TitleContainer)
    Add(f.CloseButton or _G.TradeFrameCloseButton)
    Add(f.Inset or _G.TradeFrameInset)
    Add(f._zui_panel)
    for i = 1, NUM_TRADE do
        Add(_G["TradePlayerItem" .. i])
        Add(_G["TradeRecipientItem" .. i])
    end
    for _, n in ipairs({ "TradeFrameTradeButton", "TradeFrameCancelButton",
            "TradeRecipientMoneyFrame", "TradeRecipientMoneyBg", "TradeRecipientMoneyInset",
            "TradeHighlightPlayer", "TradeHighlightRecipient",
            "TradeHighlightPlayerEnchant", "TradeHighlightRecipientEnchant",
            "TradeRecipientItemsInset", "TradeRecipientEnchantInset",
            "TradePlayerItemsInset", "TradePlayerEnchantInset",
            "TradeFramePlayerNameText", "TradeFrameRecipientNameText",
            "TradeFramePlayerEnchantText", "TradeFrameRecipientEnchantText" }) do
        Add(_G[n])
    end
    return t
end

-- Blizzard's leftovers go through Kit.Silence with QUIET: silenced once
-- (a repeat call leaves an already-faded piece alone) and only Frames lose
-- the mouse - textures and font strings just fade.
local QUIET = { once = true, framesOnly = true }

-- The item buttons carry the mouse, not the row frames around them.
local function ButtonLeftovers()
    local t = {}
    for i = 1, NUM_TRADE do
        local a = _G["TradePlayerItem" .. i .. "ItemButton"]
        local b = _G["TradeRecipientItem" .. i .. "ItemButton"]
        if a then t[#t + 1] = a end
        if b then t[#t + 1] = b end
    end
    return t
end

local function Apply()
    if not TradeFrame then return end
    if Enabled() then
        Build()
        win:Show()
        Kit.Silence(Leftovers(), QUIET)
        Kit.Silence(ButtonLeftovers(), QUIET)
        Queue()
    elseif win then
        win:Hide()
        Kit.Unsilence(Leftovers(), QUIET)
        Kit.Unsilence(ButtonLeftovers(), QUIET)
    end
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.tradewin = function()
    if not TradeFrame or ns._zTradeWin then return end
    ns._zTradeWin = true

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "TRADE_SHOW", "TRADE_UPDATE", "TRADE_PLAYER_ITEM_CHANGED",
            "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_MONEY_CHANGED",
            "PLAYER_TRADE_MONEY", "GET_ITEM_INFO_RECEIVED", "TRADE_UPDATE_WARNINGS",
            "TRADE_CLOSED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, event, a1, a2)
        if event == "TRADE_SHOW" or event == "TRADE_CLOSED" then
            targetAccepted = 0
        elseif event == "TRADE_ACCEPT_UPDATE" then
            targetAccepted = a2 or 0
        end
        Queue()
    end)
    -- Blizzard flips its Trade button on money typed and on accept; ours
    -- follows it.
    for _, fn in ipairs({ "TradeFrameTradeButton_Enable", "TradeFrameTradeButton_Disable",
            "TradeFrameTradeButton_SetToEnabledState" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, Queue) end
    end

    Apply()
    -- The /zui toggle is read on every open.
    TradeFrame:HookScript("OnShow", Apply)
end
