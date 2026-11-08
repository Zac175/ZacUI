-- AH_Frame - ZacUI's auction house window.
-- Part of ZacUI; load order is set by the TOC.
--
-- THIS WAS TABS ON BLIZZARD'S WINDOW AND THAT WAS WRONG. Blizzard's
-- AuctionFrame already has a tab strip along its bottom edge, its own
-- money frame, and its own bid/buyout buttons - adding a second row of
-- tabs put our text straight through theirs. The window is also fixed-size
-- and the wrong shape for a price table.
--
-- So this is a ZacUI window in the ZacUI house style, opened alongside the
-- auction house and closed with it. Posting still works because posting
-- only needs AuctionFrame to EXIST and be open - the item goes on the
-- cursor and through Blizzard's sell slot either way - not for their
-- Auctions tab to be the one on screen.

local ADDON_NAME = ...
-- Zacui_Bags is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
if not ns.AH then return end   -- (the auction house is off on this game version: AH_Core, Core_Flavor)

-- shared state from earlier ZacUI files
local AH = ns.AH
local AddPixelBorder = ns.AddPixelBorder
local Bags = ns.Bags
local Col = ns.Col
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Modules = ns.Modules
local Print = ns.Print
local SharpenIcon = ns.SharpenIcon
local TintBorder = ns.TintBorder
local UI = ns.UI
local ZUI = ns.ZUI

local M, F = UI.M, UI.F

local WIDTH, HEIGHT = 660, 500
local ROW_H = 22
local TABBAR = 26

local window, tabs, panels = nil, {}, {}
local active

local QualityColor = ns.QualityRGB
local Money = ns.Money

-- ============================================================
-- ROW LIST
-- ============================================================
-- Fixed pool over a scroll frame, with an optional icon per row. Auction
-- results run to hundreds of rows and a frame per result is exactly how an
-- AH addon becomes the reason your framerate dies at the auction house.
--
-- opts.key(entry): a stable identity for a row. New data replaces every
-- row table (each list update and bag change builds fresh ones), so a
-- selection held by identity was dropped on every refresh - the pick
-- you were about to buy or post simply vanished. With a key the
-- selection follows its row into the new data.
local function CreateList(parent, columns, opts)
    opts = opts or {}
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.data, list.columns = {}, {}, columns

    local header = CreateFrame("Frame", nil, list)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(16)
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(FLAT)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    local a = Col("accent")
    rule:SetVertexColor(a.r, a.g, a.b, 0.5)
    for _, col in ipairs(columns) do
        local fs = UI.Font(header, F.SMALL, { text = col.title,
            cat = "text", key = "gold", justify = col.justify or "LEFT" })
        fs:SetPoint("LEFT", col.x, 0)
        fs:SetWidth(col.w)
    end

    local scroll, child, bar = UI.ScrollArea(list)
    scroll:SetPoint("TOPLEFT", 0, -18)
    scroll:SetPoint("BOTTOMRIGHT", -18, 0)
    bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -18)
    bar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    list.scroll, list.child = scroll, child

    function list:Row(i)
        if self.rows[i] then return self.rows[i] end
        local row = CreateFrame("Button", nil, self.child)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", self.child, "RIGHT", 0, 0)

        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.stripe:SetTexture(FLAT)

        row.sel = row:CreateTexture(nil, "BORDER")
        row.sel:SetAllPoints()
        row.sel:SetTexture(FLAT)
        row.sel:Hide()

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        if opts.icons then
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(ROW_H - 4, ROW_H - 4)
            row.icon:SetPoint("LEFT", 2, 0)
            ZacUI.Look.CropIcon(row.icon)
            SharpenIcon(row.icon)
        end

        row.cells = {}
        for c, col in ipairs(self.columns) do
            local fs = UI.Font(row, F.SMALL, { justify = col.justify or "LEFT" })
            fs:SetPoint("LEFT", col.x, 0)
            fs:SetWidth(col.w)
            fs:SetWordWrap(false)
            row.cells[c] = fs
        end
        -- The scripts are set once here and read row.entry, which Refresh
        -- rewrites. Refresh used to install three fresh closures per row
        -- every pass, and the sell list refreshes on every bag change.
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", function(_, button)
            local entry = row.entry
            if not entry then return end
            self.selected = entry
            self:Refresh()
            if button == "RightButton" and self.onAlt then
                self.onAlt(entry)
            elseif self.onClick then
                self.onClick(entry)
            end
        end)
        -- The item tooltip is the whole reason to hover a row.
        row:SetScript("OnEnter", function(self2)
            local entry = row.entry
            if not (entry and entry.link) then return end
            GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(entry.link)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.rows[i] = row
        return row
    end

    function list:SetData(data)
        self.data = data or {}
        local was = self.selected
        self.selected = nil
        if was and opts.key then
            local k = opts.key(was)
            for _, e in ipairs(self.data) do
                if opts.key(e) == k then self.selected = e break end
            end
        end
        self:Refresh()
    end

    function list:Refresh()
        local e = Col("elementBg")
        local acc = Col("accent")
        for i, entry in ipairs(self.data) do
            local row = self:Row(i)
            row.stripe:SetVertexColor(e.r, e.g, e.b, (i % 2 == 0) and 0.35 or 0.12)
            row.sel:SetVertexColor(acc.r, acc.g, acc.b, 0.22)
            row.sel:SetShown(self.selected == entry)
            if row.icon then
                row.icon:SetTexture(entry.icon)
                row.icon:SetShown(entry.icon ~= nil)
            end
            for c, col in ipairs(self.columns) do
                local fs = row.cells[c]
                fs:SetText(col.get and col.get(entry) or "")
                if col.quality then
                    fs:SetTextColor(QualityColor(entry.quality))
                elseif col.color then
                    local key = col.color(entry)
                    if key then
                        local cc = GetColor("text", key)
                        fs:SetTextColor(cc.r, cc.g, cc.b, 1)
                    else
                        fs:_zPaint()
                    end
                else
                    fs:_zPaint()
                end
            end
            row.entry = entry
            row:Show()
        end
        for i = #self.data + 1, #self.rows do
            self.rows[i].entry = nil
            self.rows[i]:Hide()
        end
        local h = #self.data * ROW_H
        self.child:SetHeight(math.max(1, h))
        self.child:SetWidth(self.scroll:GetWidth() or 400)
        self.scroll:Recalculate(h)
    end

    return list
end

-- ============================================================
-- THE PURCHASE WINDOW
-- ============================================================
-- ONE CLICK PER PURCHASE, and not by choice. PlaceAuctionBid is a
-- protected function: it requires a hardware event, and an event handler
-- is not one. Driving a queue of purchases from AUCTION_ITEM_LIST_UPDATE
-- got every call after the first refused with ADDON_ACTION_BLOCKED.
--
-- So the button is the engine. It stays in one place, counts down, and
-- shows what the next click costs and what has been spent so far. That
-- turns the constraint into the safeguard this needed anyway - buying a
-- thousand gold of anything now takes a visible, countable number of
-- deliberate clicks with a running total in front of you, instead of one
-- OK on a dialog.
local buyWindow

local function BuildBuyWindow()
    -- (2026-11-08) the popup shell (UIF_Dialogs UI.Popup): the lines and
    -- buttons keep their places, under its taller header
    local win = UI.Popup("ZacUIAuctionBuy", 320, 190, "Buying")
    win._zMapOwn = true
    local D = win.headerHeight - 34
    win:SetHeight(190 + D + 14)
    UI.SettingsBuild(function()

    win.item = UI.Font(win, F.LABEL, { cat = "text", key = "gold",
        justify = "CENTER" })
    win.item:SetPoint("TOP", 0, -40 - D)

    win.progress = UI.Font(win, F.NORMAL, { cat = "text", key = "normal",
        justify = "CENTER" })
    win.progress:SetPoint("TOP", 0, -64 - D)

    win.spent = UI.Font(win, F.SMALL, { cat = "text", key = "gray",
        justify = "CENTER" })
    win.spent:SetPoint("TOP", 0, -86 - D)

    -- The stack callout. "Bought 5 thinking it was 1" happened because
    -- the only place the quantity appeared was inside the button label -
    -- this line exists to make a multi-item purchase impossible to miss.
    win.stackNote = UI.Font(win, F.SMALL, { justify = "CENTER" })
    win.stackNote:SetPoint("TOP", 0, -104 - D)

    win.buy = UI.Button(win, "Buy", { width = 200, onClick = function()
        -- THE HARDWARE EVENT. This click is the only thing the client
        -- will accept as authority to spend money.
        local ok, why = AH.BuyNext()
        if not ok and why and why ~= "done" then Print(why) end
        if buyWindow and buyWindow.Refresh then buyWindow:Refresh() end
    end })
    win.buy:SetPoint("BOTTOM", 0, 62)
    -- NEVER an enabled, unlabeled Buy: until the first Refresh names an
    -- exact quantity and price, this button does nothing. The old bare
    -- "Buy" was live for the instant before Refresh ran - exactly long
    -- enough for a fast click to spend money on an unstated amount.
    win.buy:SetText("waiting for the auction house...")
    if win.buy.Disable then win.buy:Disable() end

    -- "Done" rather than "Stop": the window no longer ends itself when a
    -- plan runs out, so closing it is what ends a run.
    win.stop = UI.Button(win, "Done", { width = 110, onClick = function()
        AH.CancelPurchase()
    end })
    win.stop:SetPoint("BOTTOM", -60, 20)

    -- Restock without leaving: re-runs the search that opened this
    -- window, and the next Buy click refills from the fresh page. This
    -- is how "keep buying that item" survives past one page.
    win.searchAgain = UI.Button(win, "Search again", { width = 110,
        onClick = function()
            if win._onSearchAgain then win._onSearchAgain() end
        end })
    win.searchAgain:SetPoint("BOTTOM", 60, 20)
    end)

    -- Closing the window IS ending the run - by X, by Escape, or by the
    -- Done button (whose cancel also closes it via the finish callback).
    win:HookScript("OnHide", function()
        if AH.PurchaseInProgress and AH.PurchaseInProgress() then
            AH.CancelPurchase()
        end
    end)

    function win:Refresh()
        local st = AH.PurchaseState()
        if not st then
            UI.CloseWindow(self)
            return
        end
        self.item:SetText(st.nextName or "")
        -- Items as well as auctions: one auction of a 20-stack is 20 of
        -- the thing, and "1 bought" read as one potion.
        local units = st.units or st.bought
        self.progress:SetText(units .. (units == 1 and " item" or " items") .. " bought"
            .. (units ~= st.bought and (" (" .. st.bought .. " auction"
                .. (st.bought == 1 and "" or "s") .. ")") or "")
            .. ", " .. st.remaining .. " more available")
        self.spent:SetText("spent " .. Money(st.spent, true)
            .. (st.missed > 0 and ("   " .. st.missed .. " already gone") or ""))
        if st.waiting then
            self.buy:SetText("waiting for the auction house...")
            self.stackNote:SetText("")
            if self.buy.Disable then self.buy:Disable() end
        elseif st.nextPrice then
            local n = st.nextCount or 1
            if n > 1 then
                self.buy:SetText("Buy STACK of " .. n .. " - "
                    .. Money(st.nextPrice, true))
                self.stackNote:SetText("|cffff9900One auction = " .. n
                    .. " items, bought whole - not 1.|r")
            else
                self.buy:SetText("Buy 1 item for "
                    .. Money(st.nextPrice, true))
                self.stackNote:SetText("")
            end
            if self.buy.Enable then self.buy:Enable() end
        else
            -- Nothing left of this item at a price you can afford. The
            -- window stays put and says so rather than vanishing -
            -- vanishing right after a purchase is indistinguishable from
            -- a crash, and it is what made buying one item at a time so
            -- tedious: every buyout closed the window.
            self.buy:SetText("none left on this page")
            self.stackNote:SetText("|cffaaaaaaSearch again to look for more.|r")
            if self.buy.Disable then self.buy:Disable() end
        end
    end

    return win
end

-- ONE DESCRIPTION OF A PURCHASE, used by every confirmation and by the
-- buy window itself. The three dialogs used to word this three different
-- ways - "Buy 1 across 1 listing", "Buy all 3 listings", "Buy 20" - and
-- mixed compact and full money formats, so the same purchase read as a
-- different one depending on which button opened it. With three separate
-- quantities in play (auctions, items per auction, items in total) that
-- is not a small ambiguity: it is the difference between buying one
-- potion and buying fifteen.
local function DescribePlan(plan)
    local auctions = #plan.picks
    local lines = {}

    -- Sellers first, because "who am I buying from" is the question the
    -- merged rows make hardest to answer.
    local sellers, order = {}, {}
    for _, pick in ipairs(plan.picks) do
        local who = pick.owner or "?"
        if not sellers[who] then
            sellers[who] = 0
            order[#order + 1] = who
        end
        sellers[who] = sellers[who] + 1
    end

    lines[#lines + 1] = auctions .. (auctions == 1 and " auction" or " auctions")
        .. ", " .. plan.units .. (plan.units == 1 and " item" or " items")
        .. " in total"
    if #order == 1 then
        lines[#lines + 1] = "from " .. order[1]
    else
        local bits = {}
        for _, who in ipairs(order) do
            bits[#bits + 1] = who .. " x" .. sellers[who]
        end
        lines[#lines + 1] = "from " .. table.concat(bits, ", ")
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = "Total " .. Money(plan.total)
    lines[#lines + 1] = Money(plan.avgUnit, true) .. " per item"
    if plan.wanted and plan.units < plan.wanted then
        lines[#lines + 1] = "|cffff9900Only " .. plan.units .. " of the "
            .. plan.wanted .. " you asked for are available at these prices.|r"
    end
    return table.concat(lines, "\n")
end

local function OpenBuyWindow(plan, onFinished, onSearchAgain)
    if not buyWindow then buyWindow = BuildBuyWindow() end
    buyWindow._onSearchAgain = onSearchAgain
    local ok, err = AH.BeginPurchase(plan,
        function() if buyWindow then buyWindow:Refresh() end end,
        function(bought, spent, reason, missed, units)
            units = units or bought
            local msg = "bought " .. units .. (units == 1 and " item" or " items")
                .. (units ~= bought and (" in " .. bought .. " auction"
                    .. (bought == 1 and "" or "s")) or "")
                .. " for " .. Money(spent)
            if missed and missed > 0 then
                msg = msg .. " (" .. missed .. " were already gone)"
            end
            if reason and reason ~= "done" then
                msg = msg .. " - " .. reason
            end
            Print(msg .. ".")
            if buyWindow then UI.CloseWindow(buyWindow) end
            if onFinished then onFinished() end
        end,
        -- after a CONFIRMED buy with nothing left in the queue, quietly
        -- re-run the search so the next click works on a live page
        -- instead of the stale cache
        function()
            local st = AH.PurchaseState()
            if st and st.remaining == 0 and onSearchAgain then
                onSearchAgain()
            end
        end)
    if not ok then
        Print(tostring(err))
        return
    end
    UI.OpenWindow(buyWindow)
    buyWindow:Refresh()
end

-- ============================================================
-- SEARCH
-- ============================================================
-- The Search tab's result columns (the settings preview's sample list is
-- drawn with the same ones).
local SEVERITY_COLOR = { good = "green", fair = nil, warn = "orange", bad = "red" }
local function SearchColumns()
    return {
        -- THREE DIFFERENT QUANTITIES LIVE ON ONE ROW and the old headings
        -- did not distinguish them, which is why the numbers read as
        -- nonsense: a row saying "x5" next to "Qty 1" looks like a
        -- contradiction unless you already know that one is the number of
        -- LISTINGS and the other is the stack size within each.
        --
        --   Stacks    how many separate auctions were merged into this row
        --   Each      how many items are in one of those auctions
        --   Per item  the price of a single item
        --   Per stack what one auction costs to buy outright
        --
        -- Nothing is abbreviated and nothing is implied.
        { title = "Item",   x = 26,  w = 158, quality = true,
          get = function(e) return e.name end },
        -- "Stacks"/"Each" read as prices sitting next to price columns,
        -- and that ambiguity bought somebody a 5-stack they thought was
        -- one item. The quantity column now SAYS what it is: "x5" gold
        -- when an auction is a stack, gray "x1" when it is single.
        { title = "Auctions", x = 182, w = 50, justify = "RIGHT",
          get = function(e) return tostring(e.listings or 1) end,
          color = function(e)
              return (e.listings and e.listings > 1) and "gold" or "gray"
          end },
        { title = "Size",   x = 236, w = 40, justify = "RIGHT",
          get = function(e) return "x" .. tostring(e.count or 1) end,
          color = function(e)
              return (e.count and e.count > 1) and "gold" or "gray"
          end },
        { title = "Per item", x = 280, w = 86, justify = "RIGHT",
          get = function(e) return e.unit and Money(e.unit, true) or "-" end,
          color = function(e) return SEVERITY_COLOR[e.severity or "fair"] end },
        { title = "vs market", x = 370, w = 62, justify = "RIGHT",
          get = function(e)
              if not e.ratio then return "|cff666666?|r" end
              return string.format("%.1fx", e.ratio)
          end,
          color = function(e) return SEVERITY_COLOR[e.severity or "fair"] end },
        { title = "Per stack", x = 436, w = 86, justify = "RIGHT",
          get = function(e) return e.buyout > 0 and Money(e.buyout, true) or "bid only" end },
        { title = "Seller", x = 528, w = 80, get = function(e) return e.owner or "?" end },
    }
end

local function BuildSearch(panel)
    local box = UI.EditBox(panel, { width = 250, height = 22, hint = "Item name" })
    box:SetPoint("TOPLEFT", 12, -12)

    -- RESULTS COME IN PAGES OF FIFTY and there was no way to reach page
    -- two. A search for "Elixir of the Mongoose" returned 151 results, of
    -- which the first fifty were all recipes, so the elixir itself was
    -- simply not on screen and nothing said why - it looked like the item
    -- was not listed at all.
    --
    -- The exact-name flag is the other half. The server can filter to an
    -- exact name itself, which is both faster and the only reliable way
    -- to stop "Recipe: X" crowding out "X". Sorting exact matches to the
    -- top only helps once they are on the page you were sent.
    -- exact: this search's own exact-name flag, for a search that did not
    -- come from the checkbox (Readycheck's checker asks for the exact item
    -- it lists). Page turns keep whatever the search they belong to used.
    local function Run(term, page, exact)
        term = term or box:GetText() or ""
        -- "" IS A REAL SEARCH - it browses everything, which is exactly
        -- what the empty-box screenshot full of results was. The guard
        -- that refused it also refused every PAGE TURN on results that
        -- arrived without a term (Blizzard's window, a list run): the
        -- arrow click hit the return and did nothing, silently.
        -- A NEW search may retry once; paging within one may not, or
        -- every page turn would bounce back to page one.
        local fresh = term ~= panel.term or (page or 0) == 0
        if fresh then panel.retried = nil end
        if exact ~= nil then
            panel.curExact = exact and true or false
        elseif fresh then
            panel.curExact = panel.exact and true or false
        end
        -- The box shows what is being searched, whoever asked.
        if (box:GetText() or "") ~= term then box:SetText(term) end
        panel.term = term
        panel.page = page or 0
        -- Armed here and disarmed by the results, so that an update we
        -- did not ask for cannot be mistaken for the answer to this.
        panel.awaiting = true
        panel.status:SetText((term == "" and "browsing everything"
                or ("searching for '" .. term .. "'"))
            .. (panel.page > 0 and (" - page " .. (panel.page + 1)) or "") .. "...")
        AH.Search(term, panel.page, panel.curExact)
    end
    panel.Run = Run
    panel.box = box

    local go = UI.Button(panel, "Search", { width = 76, onClick = function() Run() end })
    go:SetPoint("LEFT", box, "RIGHT", 6, 0)
    box.editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Run()
    end)

    local save = UI.Button(panel, "Save to list", { width = 90,
        tooltip = "Adds this search to the shopping list on the Lists tab, "
            .. "so you can run all of them in one click.",
        onClick = function()
            local term = box:GetText()
            if not term or term == "" then return end
            local store = AH.Store()
            local name = store.activeList or "Default"
            store.lists[name] = store.lists[name] or {}
            for _, existing in ipairs(store.lists[name]) do
                if existing:lower() == term:lower() then
                    Print("'" .. term .. "' is already on that list.")
                    return
                end
            end
            table.insert(store.lists[name], term)
            Print("added '" .. term .. "' to " .. name .. ".")
        end })
    save:SetPoint("LEFT", go, "RIGHT", 6, 0)

    local exactBox = UI.Checkbox(panel, "Exact name", false, function(v)
        panel.exact = v
        if panel.term then Run(panel.term, 0) end
    end)
    exactBox:SetPoint("LEFT", save, "RIGHT", 10, 0)
    UI.Tooltip(exactBox, "Exact name",
        "Asks the server for that name only, so a search for an elixir "
        .. "does not come back full of its recipe.")
    panel.exactBox = exactBox

    panel.status = UI.Font(panel, F.SMALL, { cat = "text", key = "gray" })
    panel.status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)

    -- Paging. Deliberately beside the result count rather than at the
    -- bottom of the list: the count is where you find out there is more.
    -- The pager wears the same arrow art as the rest of the suite
    -- (Readycheck's arrows, copied into ZacUI's own media so nothing
    -- breaks if that addon is off).
    local function ArrowIcon(btn, path)
        if btn._zText then btn._zText:SetText("") end
        local t = btn:CreateTexture(nil, "ARTWORK")
        t._zui_own = true
        t:SetSize(10, 10)
        t:SetPoint("CENTER")
        t:SetTexture(path)
        t:SetVertexColor(0.85, 0.85, 0.85, 1)
        return t
    end
    local prev = UI.Button(panel, "<", { width = 24, onClick = function()
        if (panel.page or 0) > 0 then Run(panel.term, (panel.page or 0) - 1) end
    end })
    prev:SetPoint("TOPLEFT", panel.status, "TOPRIGHT", 10, 6)
    ArrowIcon(prev, [[Interface\AddOns\ZacUI\Media\pagerLeft]])
    local nextBtn = UI.Button(panel, ">", { width = 24, onClick = function()
        if panel.hasMore then Run(panel.term, (panel.page or 0) + 1) end
    end })
    nextBtn:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    ArrowIcon(nextBtn, [[Interface\AddOns\ZacUI\Media\pagerRight]])
    panel.prevBtn, panel.nextBtn = prev, nextBtn

    local list = CreateList(panel, SearchColumns(), { icons = true, key = function(e)
        return tostring(e.itemID or e.name) .. "|" .. tostring(e.owner) .. "|"
            .. tostring(e.count) .. "|" .. tostring(e.buyout)
    end })
    list:SetPoint("TOPLEFT", 12, -60)
    list:SetPoint("BOTTOMRIGHT", -12, 56)
    panel.list = list

    -- ============================================================
    -- ONE BUTTON, NO NUMBER TO TYPE
    -- ============================================================
    -- There were three buttons and a quantity box here: "Buy amount"
    -- (type how many, confirm once), "Buy this row" and "Buy out". Buying
    -- ten stacks of something meant deciding up front how many items that
    -- was, in units rather than stacks, and typing it - which is
    -- arithmetic the player should never have been asked to do, on a
    -- number they usually do not know until they see the prices.
    --
    -- Now: pick the item, press Buy, and keep pressing. The buy window
    -- works down the cheapest listings one at a time and refills itself
    -- from the page, so "buy multiple" is just clicking again. Every
    -- click shows exactly what it is about to spend before it spends it,
    -- which is a better confirmation than a dialog answered once for a
    -- purchase that had not happened yet.
    local buyAll = UI.Button(panel, "Buy", { width = 120,
        tooltip = "Buys THE LISTING YOU PICKED - exact stack size, exact "
            .. "price. Press Buy again for the next identical one; a "
            .. "different stack size or price is never bought without "
            .. "you clicking its row.",
        onClick = function()
            local entry = list.selected
            if not entry then
                Print("pick a listing first.")
                return
            end
            -- cap = everything in the picked group, and only that group
            local groupUnits = entry.totalUnits
                or ((entry.count or 1) * (entry.listings or 1))
            local plan, err = AH.PlanPurchase(list.data, entry, groupUnits)
            if not plan then
                Print(tostring(err))
                return
            end

            local function go()
                OpenBuyWindow(plan,
                    function()
                        if panel.term then AH.Search(panel.term, 0, panel.curExact) end
                    end,
                    function()
                        if panel.term then AH.Search(panel.term, 0, panel.curExact) end
                    end)
            end

            -- THE ONLY SURVIVING DIALOG, and only for the one case worth
            -- interrupting somebody over: a listing priced well above
            -- what the item has actually been going for. Everything else
            -- is confirmed by the buy window itself, one click at a time.
            if plan.worst == "bad" then
                UI.Confirm({
                    title = "Buy " .. (plan.item or "item"),
                    text = DescribePlan(plan)
                        .. "\n\n|cffff3333This includes a listing at "
                        .. string.format("%.1f", plan.worstRatio or 0)
                        .. "x the going rate.|r",
                    acceptText = "Buy anyway",
                    destructive = true,
                    onAccept = go,
                })
            else
                go()
            end
        end })
    buyAll:SetPoint("BOTTOMLEFT", 12, 10)

    -- "Buy out" lived here: a second buy path that took the highlighted
    -- listing rather than the cheapest, behind its own confirmation
    -- dialog with its own wording for the same purchase. It is gone. The
    -- Buy button above starts at the cheapest and works down, which is
    -- what anybody wanted from "buy out" in all but the odd case, and one
    -- path means one set of wording, one set of warnings and one place
    -- for a bug to be.
    local again = UI.Button(panel, "Search again", { width = 96,
        onClick = function() if panel.term then Run(panel.term) end end })
    again:SetPoint("LEFT", buyAll, "RIGHT", 6, 0)

    panel.hint = UI.Font(panel, F.SMALL, { cat = "text", key = "gray",
        text = "A row is one price from one seller. Auctions = how many such listings, Size = items PER auction - buying one auction buys the whole stack." })
    -- Beside the buttons, between "Search again" and the right edge, two
    -- lines at most. Anchored at its left only it ran one long line past
    -- the window's right edge.
    panel.hint:SetPoint("LEFT", again, "RIGHT", 10, 0)
    panel.hint:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    panel.hint:SetJustifyH("LEFT")
    panel.hint:SetWordWrap(true)
    if panel.hint.SetMaxLines then panel.hint:SetMaxLines(2) end

    list.onAlt = function(entry)
        if not entry.itemID then return end
        local rec = AH.Store().prices[entry.itemID]
        if not rec or #rec.seen == 0 then
            Print(entry.name .. ": nothing recorded yet.")
            return
        end
        Print(entry.name .. " - last " .. #rec.seen .. " sightings:")
        for i, seen in ipairs(rec.seen) do
            Print("  " .. i .. ". " .. Money(seen.unit) .. " each, " .. AH.Age(seen.at))
        end
    end

    function panel.Results(rows, shown, total)
        -- ============================================================
        -- AN EMPTY UPDATE IS NOT AN ANSWER
        -- ============================================================
        -- AUCTION_ITEM_LIST_UPDATE is not "here are your search results".
        -- It fires whenever the client's browse list changes for ANY
        -- reason - Blizzard's own frame re-querying, a page being
        -- cleared, typing into a search box that is not even ours - and
        -- this function repainted from it every single time. So results
        -- appeared, and then the next unrelated update arrived carrying
        -- nothing and wiped them. Search, see it, watch it vanish.
        --
        -- The rule: an empty result set only replaces what is on screen
        -- if we asked a question and are waiting for the answer. An empty
        -- update nobody asked for is ignored, and the results stay.
        local grouped = AH.Group(rows, panel.term)
        if #grouped == 0 and not panel.awaiting and (panel.rowCount or 0) > 0 then
            return
        end
        -- Whether this page answers a search this window ran. Another
        -- addon (or Blizzard's own frame) can query the auction house
        -- behind our back, and its results arrive here too - judging them
        -- against OUR last term is how "no exact match" re-ran an old
        -- search on top of results that were right there.
        local ours = panel.awaiting and true or false
        panel.awaiting = nil
        panel.rowCount = #grouped
        list:SetData(grouped)

        local collapsed = shown - #grouped
        local exact = 0
        for _, e in ipairs(grouped) do
            if e.exact then exact = exact + 1 end
        end
        -- PAGE MATHS. `shown` is what came back for THIS page, `total`
        -- is everything matching. Fifty per page is the server's own
        -- limit, and it is what decides whether there is a page after
        -- this one - not the number of rows, which merging has already
        -- shrunk.
        local perPage = 50
        local page = panel.page or 0
        local pages = math.max(1, math.ceil((total or 0) / perPage))
        panel.hasMore = (page + 1) < pages

        panel.status:SetText(string.format(
            "%d-%d of %d  -  %d row%s%s%s",
            math.min(total, page * perPage + 1),
            math.min(total, page * perPage + shown),
            total, #grouped, #grouped == 1 and "" or "s",
            pages > 1 and ("  -  page " .. (page + 1) .. " of " .. pages) or "",
            collapsed > 0 and ("  -  " .. collapsed .. " merged") or ""))

        panel.prevBtn:SetShown(pages > 1)
        panel.nextBtn:SetShown(pages > 1)
        if panel.prevBtn.SetEnabled then
            panel.prevBtn:SetEnabled(page > 0)
            panel.nextBtn:SetEnabled(panel.hasMore)
        end

        -- ASK AGAIN, PROPERLY, instead of telling you to.
        --
        -- Searching "Elixir of the Mongoose" returns 151 results whose
        -- first fifty are all its RECIPE, so the elixir is not on screen
        -- and nothing says why - it reads as "not listed". Telling you to
        -- tick a box is not a fix; the addon knows enough to do it.
        --
        -- Only on page one, only when a loose search found no exact match
        -- at all, and only once per search - `retried` is what stops this
        -- becoming a loop when the item genuinely is not on the auction
        -- house.
        if ours and exact == 0 and panel.term and panel.term ~= "" and not panel.curExact
            and page == 0 and total > shown and not panel.retried then
            panel.retried = true
            panel.status:SetText("no exact match on page 1 - asking for '"
                .. panel.term .. "' by name...")
            -- Our question too: its answer may replace the page, even empty.
            panel.awaiting = true
            AH.Search(panel.term, 0, true)
            return
        end

        if ours and exact == 0 and panel.term and panel.term ~= ""
            and pages > 1 and not panel.curExact then
            panel.hint:SetText("No exact match for '" .. panel.term
                .. "' on this page - try Exact name, or the next page.")
        else
            panel.hint:SetText("A row is one price from one seller. "
                .. "Auctions = how many such listings, Size = items PER "
                .. "auction - buying one auction buys the whole stack.")
        end
    end
end

-- ============================================================
-- SHOPPING LISTS
-- ============================================================
local function BuildLists(panel)
    local store = AH.Store()

    local nameBox = UI.EditBox(panel, { width = 180, height = 22,
        hint = "New list name" })
    nameBox:SetPoint("TOPLEFT", 12, -12)

    local add = UI.Button(panel, "Create", { width = 76, onClick = function()
        local name = (nameBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then return end
        AH.Store().lists[name] = AH.Store().lists[name] or {}
        AH.Store().activeList = name
        nameBox:SetText("")
        panel.Refresh()
    end })
    add:SetPoint("LEFT", nameBox, "RIGHT", 6, 0)

    local listPicker = UI.Dropdown(panel, { width = 160,
        items = function()
            local out = {}
            for name in pairs(AH.Store().lists) do
                out[#out + 1] = { text = name, value = name }
            end
            table.sort(out, function(a, b) return a.text < b.text end)
            if #out == 0 then out[1] = { text = "Default", value = "Default" } end
            return out
        end,
        selected = function() return AH.Store().activeList or "Default" end,
        onSelect = function(v)
            AH.Store().activeList = v
            panel.Refresh()
        end })
    listPicker:SetPoint("LEFT", add, "RIGHT", 12, 0)
    panel.picker = listPicker

    local terms = CreateList(panel, {
        { title = "Saved searches", x = 6, w = 400, get = function(e) return e.term end },
    })
    terms:SetPoint("TOPLEFT", 12, -50)
    terms:SetPoint("BOTTOMRIGHT", -12, 40)
    panel.terms = terms

    local runAll = UI.Button(panel, "Run this list", { width = 110,
        tooltip = "Queues every search on the list. They go out one at a "
            .. "time behind the server's own throttle, so a long list takes "
            .. "a moment rather than getting you disconnected.",
        onClick = function()
            local name = AH.Store().activeList or "Default"
            local items = AH.Store().lists[name] or {}
            if #items == 0 then
                Print("that list is empty.")
                return
            end
            Print("running " .. #items .. " searches from '" .. name .. "'...")
            for _, term in ipairs(items) do AH.Search(term, 0) end
        end })
    runAll:SetPoint("BOTTOMLEFT", 12, 12)

    local remove = UI.Button(panel, "Remove", { width = 90, onClick = function()
        local entry = terms.selected
        if not entry then return end
        local name = AH.Store().activeList or "Default"
        local items = AH.Store().lists[name] or {}
        for i, term in ipairs(items) do
            if term == entry.term then table.remove(items, i) break end
        end
        panel.Refresh()
    end })
    remove:SetPoint("LEFT", runAll, "RIGHT", 6, 0)

    local drop = UI.Button(panel, "Delete list", { width = 90, onClick = function()
        local name = AH.Store().activeList or "Default"
        UI.Confirm({ title = "Delete list",
            text = "Delete the shopping list '" .. name .. "'?",
            acceptText = "Delete", destructive = true,
            onAccept = function()
                AH.Store().lists[name] = nil
                AH.Store().activeList = nil
                panel.Refresh()
            end })
    end })
    drop:SetPoint("LEFT", remove, "RIGHT", 6, 0)

    function panel.Refresh()
        local name = AH.Store().activeList or "Default"
        local items = AH.Store().lists[name] or {}
        local rows = {}
        for _, term in ipairs(items) do rows[#rows + 1] = { term = term } end
        terms:SetData(rows)
        listPicker:SetText(name)
    end
end

-- ============================================================
-- SELL
-- ============================================================
local function BuildSell(panel)
    local list = CreateList(panel, {
        { title = "In your bags", x = 26, w = 220, quality = true,
          get = function(e) return e.name end },
        { title = "Have", x = 250, w = 44, get = function(e) return e.count end },
        -- market / seenAt are worked out once per row in Refresh: these
        -- getters run for every row on every repaint, and Suggest builds
        -- and sorts a table each time it is asked.
        { title = "Market", x = 298, w = 100, justify = "RIGHT",
          get = function(e)
              return e.market and Money(e.market, true) or "unknown"
          end },
        { title = "Seen", x = 402, w = 80, justify = "RIGHT",
          get = function(e) return AH.Age(e.seenAt) end,
          color = function(e)
              local at = e.seenAt
              if not at then return "gray" end
              return ((time and time() or 0) - at) > 604800 and "orange" or nil
          end },
    }, { icons = true, key = function(e) return e.itemID end })
    list:SetPoint("TOPLEFT", 12, -12)
    list:SetPoint("BOTTOMRIGHT", -12, 104)
    panel.list = list

    local selName = UI.Font(panel, F.LABEL, { text = "Select an item above",
        cat = "text", key = "gray" })
    selName:SetPoint("BOTTOMLEFT", 12, 78)

    local function Field(label, x, width, default)
        local cap = UI.Font(panel, F.SMALL, { text = label, cat = "text", key = "gray" })
        cap:SetPoint("BOTTOMLEFT", x, 54)
        local box = UI.EditBox(panel, { width = width, height = 20, text = default })
        box:SetPoint("BOTTOMLEFT", x, 30)
        return box
    end

    local gold   = Field("Gold each", 12, 70, "0")
    local silver = Field("Silver", 88, 50, "0")
    local copper = Field("Copper", 144, 50, "0")
    local stack  = Field("Stack", 200, 46, "1")
    local count  = Field("Stacks", 252, 46, "1")

    local totalFS = UI.Font(panel, F.SMALL, { cat = "text", key = "gray" })
    totalFS:SetPoint("BOTTOMLEFT", 306, 34)

    -- WHAT IT IS GOING FOR RIGHT NOW. The Market column is a memory of
    -- what the item has been worth, which is the right thing for deciding
    -- whether to bother and the wrong thing for pricing a post - what
    -- your auction has to beat is what is listed this minute.
    local liveFS = UI.Font(panel, F.SMALL, { cat = "text", key = "gray" })
    liveFS:SetPoint("BOTTOMLEFT", 306, 50)
    panel.liveFS = liveFS

    local function UnitPrice()
        return (tonumber(gold:GetText()) or 0) * 10000
            + (tonumber(silver:GetText()) or 0) * 100
            + (tonumber(copper:GetText()) or 0)
    end

    local function UpdateTotal()
        local unit = UnitPrice()
        local size = tonumber(stack:GetText()) or 1
        local n = tonumber(count:GetText()) or 1
        totalFS:SetText(Money(unit * size, true) .. " per stack, "
            .. n .. " stack" .. (n == 1 and "" or "s"))
    end
    for _, box in ipairs({ gold, silver, copper, stack, count }) do
        box.editBox:HookScript("OnTextChanged", UpdateTotal)
    end

    local function SetPrice(unit)
        gold:SetText(tostring(math.floor(unit / 10000)))
        silver:SetText(tostring(math.floor((unit % 10000) / 100)))
        copper:SetText(tostring(unit % 100))
        UpdateTotal()
    end

    -- Asks the auction house what this item is listed at, then prices the
    -- post just under it. Deliberately a live query rather than a guess:
    -- the memory can be days old, and posting above the current lowest is
    -- the difference between selling and paying a deposit for nothing.
    -- _zPaintKey is a FIELD holding a colour name, not a method. Calling
    -- it as one - liveFS:_zPaintKey("gray") - threw on the first click of
    -- any item in the Sell list. One helper now owns both halves so there
    -- is no second place to get it wrong.
    local function SetLive(text, key)
        if text then liveFS:SetText(text) end
        liveFS._zPaintKey = key or "gray"
        liveFS:_zPaint()
    end

    local function CheckLive(entry, andPrice)
        SetLive("checking the auction house...", "gray")
        local ok, err = AH.LowestNow(entry.name, function(best, failed)
            -- The selection may have moved on while the server thought
            -- about it; an answer about the wrong item is worse than none.
            -- (by item: a bag refresh replaces the row table itself)
            local cur = panel.selected
            if not cur or cur.itemID ~= entry.itemID then return end
            if failed then
                SetLive(failed, "orange")
                return
            end
            if not best then
                SetLive("none listed - name your price", "green")
                return
            end
            SetLive("lowest now " .. Money(best.unit, true)
                .. " each" .. (best.owner and (" (" .. best.owner .. ")") or ""), "gold")
            if andPrice then
                SetPrice(math.max(1, best.unit - (AH.Store().undercut or 1)))
            end
        end)
        if not ok then
            SetLive(tostring(err), "orange")
        end
    end
    panel.CheckLive = CheckLive

    list.onClick = function(entry)
        panel.selected = entry
        list.selected = entry
        -- what the price memory says may have moved since the list was built
        entry.market, entry.seenAt = AH.Suggest(entry.itemID)
        selName:SetText(entry.name)
        local suggest = AH.Suggest(entry.itemID)
        if suggest then
            SetPrice(math.max(1, suggest - (AH.Store().undercut or 1)))
        else
            SetPrice(0)
        end
        -- Priced from the memory immediately so there is always a number
        -- in the box, then corrected from the live scan when it lands.
        CheckLive(entry, true)
        -- CLAMPED TO WHAT THE CLIENT WILL ACCEPT. One stack cannot be
        -- bigger than the item's own maximum, however many you own, and
        -- asking for more is refused in silence.
        local have = entry.count or 1
        local size = math.min(have, entry.stackMax or have)
        stack:SetText(tostring(size))
        -- ...and as many whole stacks as you can actually fill, which is
        -- the point of having 46 of something that stacks to 20.
        count:SetText(tostring(math.max(1, math.floor(have / math.max(1, size)))))
        UpdateTotal()
    end
    -- Exposed so the suite can read what the boxes ended up saying. The
    -- numbers offered here are the ones that get posted, and there was no
    -- way to assert them from outside.
    panel.Select = list.onClick
    function panel.stackSize() return tonumber(stack:GetText()) or 0 end
    function panel.stackCount() return tonumber(count:GetText()) or 0 end

    local post = UI.Button(panel, "Post", { width = 90, onClick = function()
        local item = panel.selected
        if not item then
            Print("pick an item from the list first.")
            return
        end
        -- WHAT IS IN THAT SLOT NOW. The row remembers where the item was
        -- when the list was built; a loot, a sort or a drag since then
        -- can put something else there, and posting it at this price
        -- would sell the wrong thing.
        local now = Bags.ItemInfo(item.bag, item.slot)
        if not now or now.itemID ~= item.itemID then
            Print((item.name or "that item") .. " has moved - pick it again.")
            if panel.Refresh then panel.Refresh() end
            return
        end
        local unit = UnitPrice()
        if unit <= 0 then
            Print("set a price first.")
            return
        end
        local size = tonumber(stack:GetText()) or 1
        local n = tonumber(count:GetText()) or 1
        -- No show/hide dance: the frame is off-screen, not hidden, so the
        -- sell slot is live exactly as it always was.
        -- The last two returns are what the client says is ACTUALLY in the
        -- sell slot. Reporting those instead of what was typed in the box
        -- is the difference between a message that is true and one that
        -- merely repeats the request back.
        local ok, err, sold, count = AH.PostAuction(item.bag, item.slot,
            unit, size, nil, n)
        if ok then
            Print("posting " .. (sold or item.name)
                .. (count and count > 1 and (" x" .. count) or "")
                .. " at " .. Money(unit * (size or count or 1), true)
                .. " per stack - waiting for the server to confirm.")
        else
            Print("could not post: " .. tostring(err))
        end
    end })
    post:SetPoint("BOTTOMRIGHT", -12, 30)

    local undercutBtn = UI.Button(panel, "Match lowest", { width = 100,
        onClick = function()
            local item = panel.selected
            if not item then return end
            local market = AH.Suggest(item.itemID)
            if market then
                SetPrice(math.max(1, market - (AH.Store().undercut or 1)))
            else
                Print("no remembered price for that item - search for it first.")
            end
        end })
    undercutBtn:SetPoint("RIGHT", post, "LEFT", -6, 0)

    function panel.Refresh()
        local rows, seen = {}, {}
        for _, bag in ipairs(Bags.BACKPACK_BAGS) do
            for slot = 1, Bags.Slots(bag) do
                local item = Bags.Item(bag, slot)
                if item and item.itemID then
                    local row = seen[item.itemID]
                    if row then
                        row.count = row.count + (item.count or 1)
                    else
                        -- THE MAXIMUM STACK, ASKED FOR RATHER THAN ASSUMED.
                        --
                        -- Nothing anywhere filled this in, so the Stack box
                        -- fell back to "however many you own" - 46 Winterfall
                        -- Firewater, an item that stacks to 20. The client
                        -- cannot make an auction of 46, so it refused the
                        -- post, said nothing about why, and the item stayed
                        -- in the bags. GetItemInfo returns the real limit as
                        -- its eighth value; aux clamps to exactly this.
                        local maxStack
                        if item.link and GetItemInfo then
                            maxStack = select(8, GetItemInfo(item.link))
                        end
                        local market, seenAt = AH.Suggest(item.itemID)
                        row = {
                            name = item.link and item.link:match("%[(.-)%]") or "?",
                            itemID = item.itemID, quality = item.quality,
                            icon = item.icon, link = item.link,
                            count = item.count or 1, bag = bag, slot = slot,
                            stackMax = maxStack,
                            market = market, seenAt = seenAt,
                        }
                        seen[item.itemID] = row
                        rows[#rows + 1] = row
                    end
                end
            end
        end
        table.sort(rows, function(a, b) return (a.name or "") < (b.name or "") end)
        -- Kept so the suite can read what the scan actually resolved. The
        -- stack limit is looked up here and nowhere else, and there was
        -- no way to check it had been looked up at all.
        panel.rows = rows
        list:SetData(rows)
        -- The selection follows its item to wherever it now sits (or goes,
        -- if the last of it left the bags).
        if panel.selected and panel.selected ~= list.selected then
            panel.selected = list.selected
            if not panel.selected then selName:SetText("Select an item above") end
        end
    end
end

-- ============================================================
-- CANCEL
-- ============================================================
local function BuildCancel(panel)
    local list = CreateList(panel, {
        { title = "Your auctions", x = 26, w = 220, quality = true,
          get = function(e) return e.name end },
        { title = "Qty", x = 250, w = 36, get = function(e) return e.count end },
        { title = "Yours", x = 288, w = 100, justify = "RIGHT",
          get = function(e) return e.unit and Money(e.unit, true) or "-" end },
        { title = "Lowest", x = 392, w = 100, justify = "RIGHT",
          get = function(e) return e.marketUnit and Money(e.marketUnit, true) or "-" end },
        { title = "", x = 496, w = 70,
          get = function(e) return e.marketUnit and "undercut" or "" end,
          color = function(e) return e.marketUnit and "red" or nil end },
    }, { icons = true })
    list:SetPoint("TOPLEFT", 12, -12)
    list:SetPoint("BOTTOMRIGHT", -12, 40)
    panel.list = list

    local cancel = UI.Button(panel, "Cancel selected", { width = 120,
        onClick = function()
            local entry = list.selected
            if not entry then
                Print("pick an auction first.")
                return
            end
            UI.Confirm({ title = "Cancel auction",
                text = "Cancel your listing of " .. entry.name
                    .. "? The deposit is not refunded.",
                acceptText = "Cancel it", destructive = true,
                onAccept = function()
                    local ok, why = AH.CancelAuction(entry.index)
                    if not ok then
                        Print("could not cancel: " .. tostring(why))
                        return
                    end
                    -- Asked for rather than assumed: the list is the only
                    -- evidence the cancel actually happened.
                    AH.RefreshOwned()
                end })
        end })
    cancel:SetPoint("BOTTOMLEFT", 12, 12)

    -- Cancelling many at once has to walk BACKWARDS: cancelling index 3
    -- renumbers everything above it, so a forward loop cancels the wrong
    -- auctions from the second one onwards.
    -- ONE PER PRESS, AND THE BUTTON SAYS HOW MANY ARE LEFT.
    --
    -- This used to loop over every undercut listing inside one
    -- confirmation. CancelAuction is protected: the client runs it while
    -- it is crediting a button press and credits one press to one call,
    -- so the loop cancelled the first and was refused for the rest -
    -- while the message cheerfully reported all of them cancelled.
    --
    -- Highest index first is still right and still load-bearing:
    -- cancelling index 3 renumbers everything above it, so working
    -- forwards cancels the wrong auctions from the second one onwards.
    local cancelAll = UI.Button(panel, "Cancel undercut", { width = 140,
        tooltip = "Cancels the most recent undercut listing. Press again "
            .. "for the next - the client only allows one cancel per "
            .. "click, so this cannot be done in one go.",
        onClick = function()
            local under = {}
            for _, entry in ipairs(list.data) do
                if entry.marketUnit then under[#under + 1] = entry end
            end
            if #under == 0 then
                Print("nothing of yours is undercut.")
                return
            end
            table.sort(under, function(a, b) return a.index > b.index end)
            local target = under[1]
            local left = #under - 1
            UI.Confirm({ title = "Cancel undercut auction",
                text = (target.name or "This listing")
                    .. "\n \nDeposits are not refunded."
                    .. (left > 0 and ("\n \n|cff888888" .. left .. " more "
                        .. (left == 1 and "listing is" or "listings are")
                        .. " undercut. The client allows one cancel per "
                        .. "click, so press again for the next.|r") or ""),
                acceptText = "Cancel it", destructive = true,
                onAccept = function()
                    -- Nothing between the click and the call.
                    local ok, why = AH.CancelAuction(target.index)
                    if not ok then
                        Print("could not cancel: " .. tostring(why))
                        return
                    end
                    AH.RefreshOwned()
                    Print("cancelling " .. (target.name or "that listing")
                        .. (left > 0 and (" - " .. left .. " more undercut.")
                            or "."))
                end })
        end })
    cancelAll:SetPoint("LEFT", cancel, "RIGHT", 6, 0)
    -- Exposed so the suite can press the button the player presses. Every
    -- previous test of this called AH.CancelAuction directly, which skips
    -- the sort that decides WHICH auction gets cancelled - so cancelling
    -- the wrong one was untestable.
    panel.cancelSelected, panel.cancelUndercut = cancel, cancelAll

    panel.summary = UI.Font(panel, F.SMALL, { cat = "text", key = "gray" })
    panel.summary:SetPoint("LEFT", cancelAll, "RIGHT", 12, 0)

    function panel.Refresh()
        local rows, under = {}, 0
        for i = 1, AH.NumOwnedAuctions() do
            local own = AH.OwnedEntry(i)
            if own then
                local itemID = own.link and tonumber(own.link:match("item:(%d+)"))
                local market = itemID and AH.LastSeen(itemID)
                if own.unit and market and market < own.unit then
                    own.marketUnit = market
                    under = under + 1
                end
                rows[#rows + 1] = own
            end
        end
        list:SetData(rows)
        panel.summary:SetText(#rows .. " listed, " .. under .. " undercut")
    end
end

-- ============================================================
-- BLIZZARD'S WINDOW
-- ============================================================
-- DO NOT CALL Hide() ON IT. Blizzard's AuctionFrame_OnHide calls
-- CloseAuctionHouse, so hiding the frame ENDS the auction house session -
-- which is exactly why the window opened for a split second and then
-- everything closed. The frame has to stay "shown" as far as the client
-- is concerned.
--
-- So it is moved off-screen instead. It keeps its shown state, its OnHide
-- never fires, the session stays open, and posting still works because
-- posting only needs the session - not a visible frame.
local blizzHidden, blizzPoint

-- ============================================================
-- THE POSTING BAR
-- ============================================================
-- Posting several stacks makes the client put up AuctionProgressFrame -
-- a bar with a cancel button that counts the stacks off as they go. It
-- looks exactly like a cast bar, it lands in the middle of the screen
-- because it is parented to UIParent rather than to the auction window
-- ZacUI has moved away, and ZacUI already says the same thing in chat
-- and in the Sell panel.
--
-- Faded and made click-through rather than hidden. Hiding it would mean
-- fighting Blizzard's own Show every time a stack goes up, and its
-- cancel button calls into the auction API - a frame an addon has been
-- shoving around is not one to leave in the player's way OR to leave
-- clickable. Alpha and mouse are enough to make it go away visually
-- while the client keeps driving it exactly as it expects to.
local progressHooked, progressAlpha

local function QuietPostingBar()
    local bar = _G.AuctionProgressFrame
    if not bar or not bar.SetAlpha then return end
    if progressAlpha == nil then progressAlpha = bar:GetAlpha() or 1 end
    bar:SetAlpha(0)
    if bar.EnableMouse then bar:EnableMouse(false) end
end

local function InstallPostingBarQuiet()
    local bar = _G.AuctionProgressFrame
    if progressHooked or not bar or not bar.HookScript then return end
    progressHooked = true
    -- It is re-shown for every stack, so quietening it once is not enough.
    bar:HookScript("OnShow", QuietPostingBar)
    QuietPostingBar()
end

local function RestorePostingBar()
    local bar = _G.AuctionProgressFrame
    if not bar or progressAlpha == nil then return end
    bar:SetAlpha(progressAlpha)
    if bar.EnableMouse then bar:EnableMouse(true) end
end

local function HideBlizzardAH()
    if not AuctionFrame then return end
    if ZacUIDB.auction and ZacUIDB.auction.keepBlizzard then return end
    if blizzHidden then return end
    if not AuctionFrame:IsShown() then return end

    -- Remember where it was so it can be put back exactly.
    local point, rel, relPoint, x, y = AuctionFrame:GetPoint(1)
    blizzPoint = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    AuctionFrame:ClearAllPoints()
    AuctionFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -6000, 0)
    blizzHidden = true
end

local function ShowBlizzardAH()
    if not AuctionFrame then return end
    AuctionFrame:ClearAllPoints()
    if blizzPoint and blizzPoint.point then
        AuctionFrame:SetPoint(blizzPoint.point, blizzPoint.rel,
            blizzPoint.relPoint, blizzPoint.x, blizzPoint.y)
    else
        AuctionFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    end
    AuctionFrame:Show()
    blizzHidden = nil
end

local function BlizzardVisible()
    return AuctionFrame and AuctionFrame:IsShown() and not blizzHidden
end

-- ============================================================
-- READYCHECK'S CONSUMABLES CHECKER
-- ============================================================
-- Readycheck opens its consumables checker when the auction house opens
-- (its own autoOpenAtAH setting), and it anchors to the screen - which put
-- it wherever Blizzard's window used to be. ZacUI cannot and does not edit
-- Readycheck; it just re-anchors the frame, which is an ordinary write to
-- an ordinary frame.
--
-- Deliberately only on AH open, and never if the player has dragged it
-- since: moving somebody's window out from under them every few seconds
-- would be worse than leaving it where it was.
local function AnchorReadycheck()
    if not window or not window:IsShown() then return end
    if ZacUIDB.auction and ZacUIDB.auction.anchorReadycheck == false then return end

    local checker = _G.WarriorReminderConsumablesChecker
        or (_G.Readycheck and _G.Readycheck.consumablesChecker
            and _G.Readycheck.consumablesChecker.frame)
    if not checker or not checker.IsShown or not checker:IsShown() then return end
    if checker._zUserMoved then return end

    checker:ClearAllPoints()
    checker:SetPoint("TOPLEFT", window, "TOPRIGHT", 6, 0)

    -- One hook, ever: the moment they drag it themselves, we stop.
    if not checker._zDragHooked then
        checker._zDragHooked = true
        if checker.HookScript then
            checker:HookScript("OnDragStop", function(self) self._zUserMoved = true end)
        end
    end
end

-- ============================================================
-- WINDOW
-- ============================================================
local TAB_SPECS = {
    { key = "search", label = "Search", build = BuildSearch },
    { key = "lists",  label = "Lists",  build = BuildLists },
    { key = "sell",   label = "Sell",   build = BuildSell },
    { key = "cancel", label = "Cancel", build = BuildCancel },
}

local function ShowTab(key)
    -- OPENING THE CANCEL TAB HAS TO ASK. The owner list is empty until
    -- GetOwnerAuctionItems is called, and reading it unasked returns a
    -- confident zero - which reads as "none of my auctions posted".
    if key == "cancel" and AH.RefreshOwned then AH.RefreshOwned() end
    active = key
    for k, panel in pairs(panels) do
        panel:SetShown(k == key)
        if k == key and panel.Refresh then pcall(panel.Refresh) end
    end
    for k, tab in pairs(tabs) do tab:SetActive(k == key) end
end

local function Build()
    if window then return window end
    window = UI.Window("ZacUIAuctionFrame", WIDTH, HEIGHT, "Auction house")

    for i, spec in ipairs(TAB_SPECS) do
        local tab = UI.Button(window, spec.label, { width = 84, height = 22 })
        if i == 1 then
            tab:SetPoint("TOPLEFT", 10, -(M.TITLEBAR + 4))
        else
            tab:SetPoint("LEFT", tabs[TAB_SPECS[i - 1].key], "RIGHT", 4, 0)
        end
        tab:SetScript("OnClick", function() ShowTab(spec.key) end)
        tabs[spec.key] = tab

        local panel = CreateFrame("Frame", nil, window)
        panel:SetPoint("TOPLEFT", 8, -(M.TITLEBAR + TABBAR + 8))
        panel:SetPoint("BOTTOMRIGHT", -8, 8)
        UI.Fill(panel, "ui", "cardBg")
        UI.Border(panel, "ui", "border", 0.6)
        panel._zPaint = UI.PaintBox
        panel:_zPaint()
        panel:Hide()
        panels[spec.key] = panel
        spec.build(panel)
    end

    -- Closing OUR window closes the auction house, because with Blizzard's
    -- frame hidden ours is the only thing on screen - leaving the
    -- interaction open behind a closed window is how you end up unable to
    -- talk to the auctioneer again.
    window.closeButton:SetScript("OnClick", function()
        if CloseAuctionHouse then CloseAuctionHouse() end
        UI.CloseWindow(window)
    end)

    -- An escape hatch to Blizzard's own filters (level range, usable only,
    -- the category tree), which ZacUI deliberately does not reimplement.
    local blizz = UI.Button(window, "Blizzard window", { width = 120, height = 22,
        tooltip = "Show Blizzard's auction window for its category tree and "
            .. "level filters. ZacUI's window stays open alongside it." })
    blizz:SetPoint("TOPRIGHT", -10, -(M.TITLEBAR + 4))
    blizz:SetScript("OnClick", function()
        if BlizzardVisible() then
            HideBlizzardAH()
            blizz:SetActive(false)
        else
            ShowBlizzardAH()
            blizz:SetActive(true)
        end
    end)
    window.blizzButton = blizz

    ShowTab("search")
    return window
end

-- The sell list's bag scan, coalesced: any number of BAG_UPDATEs in a
-- frame become one Refresh on the next, and none at all unless the Sell
-- tab is actually on screen. Switching to the tab refreshes anyway, so
-- nothing is missed while it is hidden.
local function SellShown()
    local panel = panels.sell
    return window and window:IsShown() and panel and panel:IsShown() and panel.Refresh
        and true or false
end
local QueueSellRefresh = ns.Coalescer(function()
    if SellShown() then panels.sell.Refresh() end
end, 0, SellShown)

-- ============================================================
-- EVENTS ONLY WHILE THEY CAN MATTER
-- ============================================================
-- The list/owner/multisell events are the auction house talking and
-- only exist while it is open. The confirmation evidence - "You won an
-- auction", the wallet, an item leaving the bags - can land a moment
-- after it closes and still belongs to a click that was made, so those
-- three linger until any post in flight is settled and the purchase
-- memory (a minute) has run out. Then they go, with the 1s post timer:
-- nothing of this runs during a raid.
local AH_EVENTS = { "AUCTION_ITEM_LIST_UPDATE", "AUCTION_OWNED_LIST_UPDATE",
    "AUCTION_MULTISELL_UPDATE", "AUCTION_MULTISELL_FAILURE" }
local LINGER_EVENTS = { "CHAT_MSG_SYSTEM", "PLAYER_MONEY", "BAG_UPDATE" }
local LINGER = 65
local ahOpen, closedAt, postTicker = false, 0, nil

local function SetEvents(ev, list, on)
    for _, e in ipairs(list) do
        if on then ev:RegisterEvent(e) else ev:UnregisterEvent(e) end
    end
end

local function OpenSession(ev)
    ahOpen = true
    SetEvents(ev, AH_EVENTS, true)
    SetEvents(ev, LINGER_EVENTS, true)
    if not postTicker and C_Timer and C_Timer.NewTicker then
        postTicker = C_Timer.NewTicker(1, function()
            -- A post that gets no answer at all has to end too, or the
            -- window sits there implying something is still happening.
            AH.PostTick()
            if not ahOpen and not AH.posting
                and (GetTime() - closedAt) > LINGER then
                SetEvents(ev, LINGER_EVENTS, false)
                postTicker:Cancel()
                postTicker = nil
            end
        end)
        if ns.Profiler then ns.Profiler.TrackTicker(postTicker, "AH post timer") end
    end
end

local function CloseSession(ev)
    ahOpen = false
    closedAt = GetTime()
    SetEvents(ev, AH_EVENTS, false)
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.auctionhouse = function()
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded then
        local ok, res = pcall(isLoaded, "Auctionator")
        if ok and res then
            Print("auctionhouse: Auctionator is loaded and does the same job "
                .. "- ZacUI's auction window stays off. Disable one to pick.")
            return
        end
    end

    AH.Store()
    if ZUI._ahEvents then return end

    ZUI._ahEvents = CreateFrame("Frame")
    local ev = ZUI._ahEvents
    -- The rest (see OpenSession) only while the auction house is open:
    -- purchase confirmation evidence (the server's "You won an auction"
    -- line, the wallet changing by exactly the pending buyout), posting
    -- evidence (multisell, the item leaving the bags), the lists.
    ev:RegisterEvent("AUCTION_HOUSE_SHOW")
    ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
    ev:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "AUCTION_HOUSE_SHOW" then
            OpenSession(ev)
            Build()
            -- One frame's grace: Blizzard shows its own window as part of
            -- handling this event, so hiding it in the same tick is a race.
            C_Timer.After(0, function()
                HideBlizzardAH()
                -- The progress bar only exists once Blizzard's auction
                -- frame has been built, which is why this waits with it.
                InstallPostingBarQuiet()
                if window.blizzButton then
                    window.blizzButton:SetActive(BlizzardVisible())
                end
            end)
            window:ClearAllPoints()
            window:SetPoint("CENTER", UIParent, "CENTER", -60, 40)
            UI.OpenWindow(window)
            -- Readycheck creates its checker lazily on the same event, so
            -- the anchor has to wait for it to exist.
            C_Timer.After(0.1, AnchorReadycheck)
            C_Timer.After(0.5, AnchorReadycheck)
            local dropped = AH.Prune()
            if dropped > 0 then
                Print("auction memory: forgot " .. dropped .. " item"
                    .. (dropped == 1 and "" or "s") .. " nobody has listed in "
                    .. (AH.Store().keepDays or 30) .. " days.")
            end

        elseif event == "AUCTION_HOUSE_CLOSED" then
            CloseSession(ev)
            AH.ClearQueue()
            -- Give Blizzard its bar back, for the same reason the auction
            -- frame goes back where it was found: nothing of ours should
            -- outlive the window that justified it.
            RestorePostingBar()
            if window then window:Hide() end
            -- Put the frame back where it belongs. It is only off-screen,
            -- so leaving it there would strand it for anything else that
            -- expects to find it - including Blizzard, next time.
            if blizzHidden then
                local keep = blizzPoint
                blizzHidden = nil
                AuctionFrame:ClearAllPoints()
                if keep and keep.point then
                    AuctionFrame:SetPoint(keep.point, keep.rel, keep.relPoint,
                        keep.x, keep.y)
                else
                    AuctionFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
                end
            end

        elseif event == "CHAT_MSG_SYSTEM" then
            AH.OnSystemMessage(arg1)

        elseif event == "PLAYER_MONEY" then
            AH.OnMoneyChanged()

        elseif event == "AUCTION_ITEM_LIST_UPDATE" then
            AH.QueryDone()
            -- Before harvesting: a purchase run confirms itself by the
            -- bought listing being gone from this very list, and it has
            -- to see the list before anything else reshapes it.
            AH.OnListUpdate()
            local rows, shown, total = AH.Harvest()
            local panel = panels.search
            if panel and panel.Results then panel.Results(rows, shown, total) end

        elseif event == "AUCTION_OWNED_LIST_UPDATE" then
            -- The owner list is a query like any other, so the throttle
            -- has to be released or the next one never fires.
            AH.QueryDone()
            local panel = panels.cancel
            if panel and panel.Refresh then panel.Refresh() end

        -- ============================================================
        -- THE CLIENT TELLING YOU WHETHER IT WORKED
        -- ============================================================
        -- These three were never registered, which is why posting could
        -- fail completely and the only thing you saw was a message
        -- claiming it had succeeded. The owner-list count that used to
        -- stand in for them is a guess; these are the client speaking.
        elseif event == "AUCTION_MULTISELL_UPDATE" then
            AH.OnMultisellUpdate(arg1, arg2)

        elseif event == "AUCTION_MULTISELL_FAILURE" then
            AH.OnMultisellFailure()

        elseif event == "BAG_UPDATE" then
            -- The item leaving your bags is the last thing to happen and
            -- the only unambiguous evidence that it did.
            AH.OnBagUpdate()
            -- BAG_UPDATE fires once per bag on every change. The sell list
            -- is a bag walk (through the shared item cache), so it only
            -- runs while the window is up with the Sell tab showing, and
            -- a burst of events is one walk next frame.
            QueueSellRefresh()
        end
    end)
    -- Opened before this module ran (a /reload at the auctioneer).
    if AuctionFrame and AuctionFrame:IsShown() then OpenSession(ev) end
end

-- ============================================================
-- FOR OTHER ADDONS
-- ============================================================
-- Readycheck's consumables checker searches the auction house when you
-- click one of its rows. It used to drive Blizzard's own (hidden) browse
-- frame, whose results then landed in this window judged against this
-- window's previous search - so what it found was wiped by a re-run of
-- the old term. With this it searches HERE: the box shows the item, the
-- results are rated against it, paging works, and it waits its turn in
-- the query throttle like every other search.
--   ZacUIAuction.IsOpen()              the ZacUI auction window is up
--   ZacUIAuction.Search(name, exact)   search it; false if it could not
_G.ZacUIAuction = {
    IsOpen = function()
        return window ~= nil and window:IsShown() and panels.search ~= nil
    end,
    Search = function(term, exact)
        if not (window and window:IsShown()) then return false end
        local panel = panels.search
        if not (panel and panel.Run) or type(term) ~= "string" or term == "" then
            return false
        end
        if active ~= "search" then ShowTab("search") end
        panel.Run(term, 0, exact and true or false)
        return true
    end,
}

-- shared with later ZacUI files
ns.AHHideBlizzard = HideBlizzardAH

-- ============================================================
-- THE SETTINGS PREVIEW'S SAMPLE
-- ============================================================
-- The window as it opens (UI.Window's frame, the tab row, the Search
-- panel and its result list from CreateList with the Search tab's own
-- columns), filled with made-up auctions. Parented to the canvas, no
-- name, nothing that searches, buys, posts or listens to the auction
-- house: the buttons have no handlers and the window cannot be dragged.
local SAMPLE_ROWS = {
    { name = "Elixir of the Mongoose", quality = 1, icon = 134812, listings = 3, count = 5, unit = 61000,
      ratio = 0.8, severity = "good", buyout = 305000, owner = "Brakka" },
    { name = "Major Healing Potion", quality = 1, icon = 134834, listings = 1, count = 5, unit = 18500,
      ratio = 1.0, buyout = 92500, owner = "Tovren" },
    { name = "Black Lotus", quality = 2, icon = 134202, listings = 1, count = 1, unit = 1450000,
      ratio = 1.3, severity = "warn", buyout = 1450000, owner = "Velka" },
    { name = "Arcanite Bar", quality = 2, icon = 134459, listings = 2, count = 1, unit = 980000,
      ratio = 1.9, severity = "bad", buyout = 980000, owner = "Sneakz" },
    { name = "Runecloth", quality = 1, icon = 132903, listings = 6, count = 20, unit = 3200,
      ratio = 0.9, severity = "good", buyout = 64000, owner = "Orrin" },
    { name = "Dense Grinding Stone", quality = 1, icon = 135246, listings = 1, count = 1, unit = 4800,
      buyout = 0, owner = "Ghaldor" },
}
local function NewSample(parent)
    local f = UI.Window(nil, WIDTH, HEIGHT, "Auction house")
    f:SetParent(parent)
    f:SetFrameStrata(parent:GetFrameStrata())
    f:EnableMouse(false)
    if f.titleBar then f.titleBar:EnableMouse(false) end
    if f.closeButton then f.closeButton:EnableMouse(false) end
    f.sampleTabs = {}
    for i, spec in ipairs(TAB_SPECS) do
        local tab = UI.Button(f, spec.label, { width = 84, height = 22 })
        if i == 1 then tab:SetPoint("TOPLEFT", 10, -(M.TITLEBAR + 4))
        else tab:SetPoint("LEFT", f.sampleTabs[i - 1], "RIGHT", 4, 0) end
        tab:SetActive(spec.key == "search")
        f.sampleTabs[i] = tab
    end
    local blizz = UI.Button(f, "Blizzard window", { width = 120, height = 22 })
    blizz:SetPoint("TOPRIGHT", -10, -(M.TITLEBAR + 4))
    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT", 8, -(M.TITLEBAR + TABBAR + 8))
    panel:SetPoint("BOTTOMRIGHT", -8, 8)
    UI.Fill(panel, "ui", "cardBg")
    UI.Border(panel, "ui", "border", 0.6)
    panel._zPaint = UI.PaintBox
    panel:_zPaint()
    local list = CreateList(panel, SearchColumns(), { icons = true })
    list:SetPoint("TOPLEFT", 12, -60)
    list:SetPoint("BOTTOMRIGHT", -12, 56)
    f.samplePanel, f.sampleList = panel, list
    f:Show()
    return f
end
local function FillSample(f)
    if f._zPaint then f:_zPaint() end
    if f.titleBar and f.titleBar._zPaint then f.titleBar:_zPaint() end
    if f.samplePanel then f.samplePanel:_zPaint() end
    f.sampleList:SetData(SAMPLE_ROWS)
end
ns.AHLook = { NewSample = NewSample, Fill = FillSample, WIDTH = WIDTH, HEIGHT = HEIGHT }
