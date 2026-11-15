-- Win_Merchant - ZacUI's merchant window: one scrolling, searchable list
-- instead of Blizzard's ten-per-page grid.
-- Part of ZacUI; load order is set by the TOC.
--
-- Built on Win_Kit's cover, so it lives inside Blizzard's MerchantFrame:
-- it opens with the vendor, closes with it (Escape, walking away, the X
-- - which hides MerchantFrame, whose OnHide ends the session exactly as
-- Blizzard intends) and takes Blizzard's slot in the panel layout.
--
-- Every click does what the Blizzard button it replaces does, through
-- the same calls - and for the purchases that deserve a second look
-- (token costs, anything over 150g) through Blizzard's OWN confirmation
-- functions, fed a row that answers :GetID() the way their item button
-- would. Re-implementing those prompts is how an addon ends up spending
-- somebody's marks without asking.
--
--   Right-click          buy one lot (Blizzard's right-click)
--   Shift-right-click    choose how many (Blizzard's stack split)
--   Left-click / drag    pick the item up, drop it in a bag to buy
--   Shift / Ctrl-click   link it / preview it (HandleModifiedItemClick)
--   Drop a bag item here sell it
--   Buyback tab          any click buys it back

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local UI = ns.UI

local M, F = UI.M, UI.F

local TEX_REPAIR     = "Interface\\Icons\\Trade_BlackSmithing"
local TEX_REPAIR_ONE = "Interface\\Icons\\INV_Hammer_20"
local TEX_JUNK       = "Interface\\Icons\\INV_Misc_Coin_02"

local win, list, tabs, search, chipUsable, chipAfford
local moneyText, repairAll, repairOne, sellJunk, countText
local mode = "buy"
local query = ""
local pickedFromUs = false
local Proxy, ClearPurchaseMarks, PickUp   -- defined with the rows below

-- An item from your bags (or your character) on the cursor - the only
-- thing a click on this window should try to sell.
local function HoldingBagItem()
    return GetCursorInfo() == "item" and not pickedFromUs
end

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.merchantwin ~= false
end

-- ============================================================
-- DATA
-- ============================================================
local function ItemQuality(link)
    if not link then return nil end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return (select(3, getInfo(link)))
end

-- Extended cost (marks, tokens) as inline icon text, e.g. "|T..|t 3".
local function CostText(index)
    if not GetMerchantItemCostInfo then return "" end
    local n = GetMerchantItemCostInfo(index) or 0
    local parts = {}
    for i = 1, math.max(n, 3) do
        local tex, value = GetMerchantItemCostItem(index, i)
        if tex and value and value > 0 then
            parts[#parts + 1] = value .. " |T" .. tex .. ":12:12:0:0|t"
        end
    end
    return table.concat(parts, "  ")
end

local function BuyRows()
    local data = {}
    local n = GetMerchantNumItems and GetMerchantNumItems() or 0
    local wantUsable = chipUsable and chipUsable:IsOn()
    local wantAfford = chipAfford and chipAfford:IsOn()
    for i = 1, n do
        local name, texture, price, stackCount, numAvailable, isPurchasable,
            isUsable, extendedCost = GetMerchantItemInfo(i)
        local link = GetMerchantItemLink(i)
        if name or link then
            local afford = true
            if CanAffordMerchantItem then
                local ok, res = pcall(CanAffordMerchantItem, i)
                if ok and res == false then afford = false end
            elseif price and price > GetMoney() then
                afford = false
            end
            local e = {
                index = i, name = name or "", icon = texture,
                price = price or 0, count = stackCount or 1,
                stock = numAvailable or -1,
                purchasable = isPurchasable ~= false,
                usable = isUsable and true or false,
                extended = extendedCost and true or false,
                link = link, quality = ItemQuality(link), afford = afford,
            }
            if Kit.Matches(query, e.name)
                and (not wantUsable or e.usable)
                and (not wantAfford or e.afford) then
                data[#data + 1] = e
            end
        end
    end
    return data, n
end

local function BuybackRows()
    local data = {}
    local n = GetNumBuybackItems and GetNumBuybackItems() or 0
    -- Newest sale first: that is almost always the one you want back.
    for i = n, 1, -1 do
        local name, texture, price, quantity, _, isUsable = GetBuybackItemInfo(i)
        if name then
            local link = GetBuybackItemLink and GetBuybackItemLink(i)
            local e = {
                index = i, name = name, icon = texture, price = price or 0,
                count = quantity or 1, usable = isUsable ~= false,
                link = link, quality = ItemQuality(link),
                afford = (price or 0) <= GetMoney(), buyback = true,
                stock = -1, purchasable = true,
            }
            if Kit.Matches(query, name) then data[#data + 1] = e end
        end
    end
    return data, n
end

-- ============================================================
-- FOOTER STATE
-- ============================================================
local function UpdateFooter()
    if not win then return end
    moneyText:SetText(ns.Money(GetMoney()))
    local canRepair = CanMerchantRepair and CanMerchantRepair()
    repairAll:SetShown(canRepair and true or false)
    repairOne:SetShown(canRepair and true or false)
    if canRepair then
        local cost, can = GetRepairAllCost()
        repairAll:SetUsable(can and cost and cost > 0 and GetMoney() >= cost)
        repairOne:SetUsable(true)
    end
    -- Sell junk sits where repair would, whether or not repair is there.
    sellJunk:ClearAllPoints()
    if canRepair then
        sellJunk:SetPoint("RIGHT", repairOne, "LEFT", -4, 0)
    else
        sellJunk:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    end
end

local function Refresh(keepOffset)
    -- IsVisible, not IsShown: the cover is a shown child of MerchantFrame
    -- all session, so IsShown is true with no vendor open and every bag
    -- or item-info event in a raid would rebuild a window nobody sees.
    if not win or not win:IsVisible() then return end
    local data, total
    if mode == "buyback" then
        data, total = BuybackRows()
        list:SetEmptyText(total == 0 and "Nothing sold here yet." or "Nothing matches.")
    else
        data, total = BuyRows()
        list:SetEmptyText(total == 0 and "This merchant has nothing for sale." or "Nothing matches.")
    end
    list:SetData(data, keepOffset)
    if query ~= "" or (mode == "buy" and ((chipUsable:IsOn()) or chipAfford:IsOn())) then
        countText:SetText(#data .. " / " .. total)
    else
        countText:SetText(total .. (total == 1 and " item" or " items"))
    end
    tabs:SetLabel("buyback", (BUYBACK or "Buyback")
        .. ((GetNumBuybackItems and GetNumBuybackItems() or 0) > 0
            and (" (" .. GetNumBuybackItems() .. ")") or ""))
    UpdateFooter()
end

-- Coalesce the event storm (MERCHANT_UPDATE, BAG_UPDATE, item info
-- arriving) into one redraw per frame.
local Queue = Kit.Coalesce(Refresh, function() return win end, true)

-- ============================================================
-- PURCHASE PROMPTS
-- ============================================================
local function HIGH_PRICE() return MERCHANT_HIGH_PRICE_COST or 1500000 end

-- What Blizzard's confirmation helpers read off their own item button,
-- frozen for one entry so no later re-use of a pooled row can change it.
function Proxy(e)
    return {
        GetID = function() return e.index end,
        price = e.price, count = e.count, link = e.link,
        texture = e.icon, name = e.name,
        extendedCost = e.extended or nil,
        showNonrefundablePrompt = nil,
    }
end

-- An item picked up (to drop in a bag) goes through the same prompts as a
-- right-click: Blizzard's bag click reads these two fields off
-- MerchantFrame when a merchant item lands, and asks before buying.
-- ZacUI's own bag uses Blizzard's container button, so it asks too.
local marked = false
function ClearPurchaseMarks()
    if marked and MerchantFrame then
        MerchantFrame.extendedCost = nil
        MerchantFrame.highPrice = nil
    end
    marked = false
end

-- Marks are only ever cleared when the cursor stops holding a merchant
-- item - never by a click on some other row, which would leave the item
-- in hand with its prompt forgotten.
function PickUp(e)
    pickedFromUs = true
    if MerchantFrame then
        MerchantFrame.extendedCost = nil
        MerchantFrame.highPrice = nil
    end
    marked = false
    PickupMerchantItem(e.index)
    if not MerchantFrame then return end
    if e.extended then
        MerchantFrame.extendedCost = Proxy(e)
        marked = true
    elseif e.price and e.price >= HIGH_PRICE() then
        MerchantFrame.highPrice = Proxy(e)
        marked = true
    end
end

-- ============================================================
-- ROWS
-- ============================================================
local function RowTooltip(row)
    local e = row.item
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if e.buyback then
        GameTooltip:SetBuybackItem(e.index)
    else
        GameTooltip:SetMerchantItem(e.index)
        if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
    end
    GameTooltip:Show()
end

local function BuildRow(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:RegisterForDrag("LeftButton")
    local rh = Kit.ROW_H

    row.icon = Kit.Icon(row, rh - 4)
    row.icon:SetPoint("LEFT", 3, 0)

    row.priceText = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.priceText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.priceText:SetWordWrap(false)

    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, -2)
    row.nameText:SetPoint("RIGHT", row.priceText, "LEFT", -6, 0)
    row.nameText:SetWordWrap(false)
    -- Both lines share the row's vertical middle through their RIGHT
    -- anchor; justification is what puts one on top of the other.
    row.nameText:SetJustifyV("TOP")

    row.sub = UI.Font(row, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, 2)
    row.sub:SetPoint("RIGHT", row.priceText, "LEFT", -6, 0)
    row.sub:SetWordWrap(false)
    row.sub:SetJustifyV("BOTTOM")

    -- What Blizzard's confirmation helpers read off their own button.
    -- The item is CAPTURED when the split opens: the pooled row can be
    -- re-pointed at another entry (scroll, a filter, MERCHANT_UPDATE)
    -- while the dialog is up, and the purchase must be the one you asked.
    row.SplitStack = function(self, split)
        local e = self._zSplitItem
        self._zSplitItem = nil
        if not e or not split or split <= 0 then return end
        if e.extended and MerchantFrame_ConfirmExtendedItemCost then
            MerchantFrame_ConfirmExtendedItemCost(Proxy(e), split)
        else
            BuyMerchantItem(e.index, split)
        end
    end

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if ResetCursor then ResetCursor() end
    end)
    row.UpdateTooltip = RowTooltip

    row:SetScript("OnClick", function(self, button)
        local e = self.item
        if not e then return end

        -- Something from a bag on the cursor: this click is a sale.
        if HoldingBagItem() then
            PickupMerchantItem(e.buyback and 1 or e.index)
            return
        end

        if e.buyback then
            if IsModifiedClick() and e.link and HandleModifiedItemClick(e.link) then return end
            BuybackItem(e.index)
            return
        end

        if IsModifiedClick() then
            if e.link and HandleModifiedItemClick(e.link) then return end
            if IsModifiedClick("SPLITSTACK") then
                local maxStack = GetMerchantItemMaxStack(e.index) or 1
                local canAfford = maxStack
                if e.price > 0 and e.count > 0 then
                    canAfford = math.floor(GetMoney() / (e.price / e.count))
                end
                local most = math.min(maxStack, canAfford)
                if maxStack > 1 and most > 0 and OpenStackSplitFrame then
                    self._zSplitItem = e
                    OpenStackSplitFrame(most, self, "BOTTOMLEFT", "TOPLEFT", e.count)
                end
                return
            end
        end

        if button == "LeftButton" then
            PickUp(e)
            return
        end

        -- Right-click: buy one lot, through Blizzard's prompts when they
        -- would have asked.
        if e.extended and MerchantFrame_ConfirmExtendedItemCost then
            MerchantFrame_ConfirmExtendedItemCost(Proxy(e))
        elseif e.price >= HIGH_PRICE() and MerchantFrame_ConfirmHighCostItem then
            MerchantFrame_ConfirmHighCostItem(Proxy(e))
        else
            BuyMerchantItem(e.index)
        end
    end)

    row:SetScript("OnDragStart", function(self)
        local e = self.item
        if e and not e.buyback then
            PickUp(e)
        end
    end)
    row:SetScript("OnReceiveDrag", function(self)
        if HoldingBagItem() then
            PickupMerchantItem(1)
        end
    end)
end

local function UpdateRow(row, e)
    -- Blizzard's confirmation helpers call :GetID() and read these off
    -- what they think is their own item button.
    row:SetID(e.index)
    row.price, row.count, row.link = e.price, e.count, e.link
    row.extendedCost = e.extended or nil
    row.texture, row.name = e.icon, e.name
    row.showNonrefundablePrompt = nil
    row.icon:SetIcon(e.icon)
    row.icon:SetCount(e.count)
    row.icon:SetQuality(e.quality)
    local ok = e.purchasable and e.usable
    row.icon:SetUsable(ok)
    row.icon:SetDesaturated(e.stock == 0)

    row.nameText:SetText(e.name)
    if e.quality then
        row.nameText:SetTextColor(ns.QualityRGB(e.quality))
    else
        row.nameText:_zPaint()
    end
    if not ok then row.nameText:SetTextColor(Kit.TextRGB("red")) end

    local bits = {}
    if e.stock and e.stock >= 0 then
        bits[#bits + 1] = (e.stock == 0) and "Sold out" or (e.stock .. " left")
    end
    if e.count and e.count > 1 then bits[#bits + 1] = "x" .. e.count .. " per purchase" end
    if not e.usable then bits[#bits + 1] = "Can't use" end
    row.sub:SetText(table.concat(bits, "  |  "))

    local text = ""
    if e.price and e.price > 0 then text = ns.Money(e.price) end
    if e.extended then
        local c = CostText(e.index)
        text = (text ~= "" and (text .. "  ") or "") .. c
    end
    row.priceText:SetText(text)
    if e.afford then row.priceText:_zPaint() else row.priceText:SetTextColor(Kit.TextRGB("red")) end
end

-- ============================================================
-- BUILD
-- ============================================================
local function Build()
    if win then return win end
    win = Kit.Cover(MerchantFrame, {
        name = "ZacUIMerchantWindow",
        title = MERCHANT or "Merchant",
        insetName = "MerchantFrame",
        onClose = function() HideUIPanel(MerchantFrame) end,
    })

    tabs = Kit.Tabs(win, {
        { key = "buy",     label = MERCHANT or "Buy" },
        { key = "buyback", label = BUYBACK or "Buyback",
          tooltip = "Everything you sold here this session. Click to buy it back." },
    }, function(key)
        mode = key
        chipUsable:SetShown(key == "buy")
        chipAfford:SetShown(key == "buy")
        list:Select(nil)
        Refresh()
    end)
    tabs:SetPoint("TOPLEFT", Kit.PAD, win.top)
    tabs:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, win.top)

    countText = UI.Font(win, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    countText:SetPoint("RIGHT", tabs, "RIGHT", 0, 0)

    local searchY = win.top - Kit.TAB_H - Kit.GAP
    chipAfford = Kit.Chip(win, "Affordable", false, function() Refresh() end,
        "Only items you have the money for.")
    chipAfford:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, searchY)
    chipUsable = Kit.Chip(win, "Usable", false, function() Refresh() end,
        "Only items your character can use.")
    chipUsable:SetPoint("RIGHT", chipAfford, "LEFT", -4, 0)

    search = Kit.Search(win, 100, function(text)
        query = Kit.NormalizeQuery(text)
        Refresh()
    end, "Search this merchant")
    search:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, searchY)
    search:SetPoint("RIGHT", chipUsable, "LEFT", -Kit.GAP, 0)

    win.footer = Kit.Footer(win, Kit.FOOTER_H + 4)

    moneyText = UI.Font(win.footer, F.LABEL, { justify = "LEFT" })
    moneyText:SetPoint("LEFT", 8, 0)

    repairAll = Kit.IconButton(win.footer, 26, TEX_REPAIR, REPAIR_ALL_ITEMS or "Repair all",
        function()
            local cost, can = GetRepairAllCost()
            if not can or not cost or cost == 0 then return "Nothing needs repairing." end
            return "Costs " .. ns.Money(cost)
        end,
        function()
            local cost, can = GetRepairAllCost()
            if can and cost and cost > 0 then
                RepairAllItems()
                if SOUNDKIT and SOUNDKIT.ITEM_REPAIR then PlaySound(SOUNDKIT.ITEM_REPAIR) end
            end
        end)
    repairAll:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)

    repairOne = Kit.IconButton(win.footer, 26, TEX_REPAIR_ONE, REPAIR_AN_ITEM or "Repair an item",
        "Then click the item to repair - in your bags or on your character.",
        function()
            if InRepairMode and InRepairMode() then HideRepairCursor() else ShowRepairCursor() end
        end)
    repairOne:SetPoint("RIGHT", repairAll, "LEFT", -4, 0)

    sellJunk = Kit.IconButton(win.footer, 26, TEX_JUNK, "Sell junk",
        "Sell every grey item in your bags (your keep list is honoured).",
        function()
            local QoL = ns.QoL
            if QoL and QoL.SellJunkNow then QoL.SellJunkNow() end
        end)

    list = Kit.List(win, {
        rowHeight = Kit.ROW_H,
        build = BuildRow,
        update = UpdateRow,
    })
    list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, searchY - Kit.SEARCH_H - Kit.GAP)
    list:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)

    -- Dropping a bag item anywhere on the window sells it.
    local function DropSell()
        if HoldingBagItem() and (GetMerchantNumItems() or 0) > 0 then
            PickupMerchantItem(1)
        elseif pickedFromUs then
            ClearCursor()
        end
    end
    win:SetScript("OnReceiveDrag", DropSell)
    win:SetScript("OnMouseUp", DropSell)

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("MERCHANT_UPDATE")
    ev:RegisterEvent("PLAYER_MONEY")
    ev:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("CURSOR_CHANGED")
    pcall(ev.RegisterEvent, ev, "CURSOR_UPDATE")
    ev:SetScript("OnEvent", function(_, event)
        if event == "CURSOR_CHANGED" or event == "CURSOR_UPDATE" then
            -- A merchant item on the cursor is its own cursor type; do not
            -- trust CursorHasItem to report it.
            if GetCursorInfo() ~= "merchant" and not CursorHasItem() then
                pickedFromUs = false
                -- Deferred a frame: the bag click that consumed the item
                -- reads the marks in the same tick the cursor empties.
                C_Timer.After(0, function()
                    if GetCursorInfo() ~= "merchant" then ClearPurchaseMarks() end
                end)
            end
            return
        end
        Queue()
    end)

    win:HookScript("OnShow", function()
        mode = "buy"
        query = ""
        search:SetText("")
        tabs:Select("buy")
        win:SetTitle(UnitName("npc") or (MERCHANT or "Merchant"))
        win:SetIcon("Interface\\Icons\\INV_Misc_Bag_10")
    end)
    win:HookScript("OnHide", function()
        if InRepairMode and InRepairMode() then HideRepairCursor() end
        pickedFromUs = false
    end)
    return win
end

-- Pieces of MerchantFrame that are not under the cover: the bottom tabs
-- hang below it, the template's border corners and close button poke a
-- few pixels past its edges, and the portrait sits at frame level 400 -
-- above any cover. The "merchant" skin hides most of these too, but it
-- can be turned off on its own.
local function BlizzardTabs()
    local f = MerchantFrame
    return {
        _G.MerchantFrameTab1, _G.MerchantFrameTab2,
        f and f.PortraitContainer, _G.MerchantFramePortrait,
        f and f.NineSlice, f and f.CloseButton, _G.MerchantFrameCloseButton,
    }
end

local function Apply()
    if not MerchantFrame then return end
    if Enabled() then
        Build()
        win.Reanchor()
        win:Show()
        Kit.Silence(BlizzardTabs())
        if MerchantFrame:IsShown() then Refresh() end
    elseif win then
        win:Hide()
        Kit.Unsilence(BlizzardTabs())
    end
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.merchantwin = function()
    if not MerchantFrame or ns._zMerchantWin then return end
    ns._zMerchantWin = true
    Apply()
    -- A later /zui toggle only flips the saved flag; the window checks it
    -- on every open so turning it off never needs a reload.
    MerchantFrame:HookScript("OnShow", function()
        Apply()
        if win and win:IsShown() then Refresh() end
    end)
end
