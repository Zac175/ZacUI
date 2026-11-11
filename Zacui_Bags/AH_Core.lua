-- AH_Core - the auction house data layer: the price memory, the scanner
-- that fills it, and the posting/cancelling calls.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT THE PRICE MEMORY IS. Every time you browse the auction house, the
-- server hands over pages of results. Those pages are the only price data
-- that exists client-side - there is no API that just tells you what a
-- thing is worth. So this records the cheapest per-unit price seen for
-- each item, every time, and keeps a short history. That history is what
-- makes "post at the going rate" possible without you looking it up.
--
-- ONE DELIBERATE LIMIT: it records what it SEES. A search you never run
-- produces no data, and a price from three weeks ago is labelled as three
-- weeks old rather than quietly presented as current. The UI shows the
-- age, because a stale price you believe is worse than no price.
--
-- THE THROTTLE IS NOT OPTIONAL. Classic's auction API is rate limited and
-- the server will disconnect a client that queries too fast. Every query
-- goes through CanQuery/Queue below, never directly.

local ADDON_NAME = ...
-- Zacui_Bags is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
-- Not on every game version (Core_Flavor's feature table: Retail's
-- auction house speaks C_AuctionHouse, which this price memory does not
-- yet): the feature stands down here, before it publishes ns.AH, and
-- AH_Frame returns at once without it.
if ns.FeatureOn and not ns.FeatureOn("auction") then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local Bags = ns.Bags

local AH = {}

-- ============================================================
-- API COMPAT
-- ============================================================
-- Classic Era exposes the old global auction API. Some of it moved behind
-- C_AuctionHouse on later flavours; both are probed so this file is the
-- only place that has to care.
local function CanQuery()
    if CanSendAuctionQuery then
        local canQuery, canFull = CanSendAuctionQuery()
        return canQuery, canFull
    end
    return false, false
end

local function NumBrowseResults()
    if GetNumAuctionItems then
        local shown, total = GetNumAuctionItems("list")
        return shown or 0, total or 0
    end
    return 0, 0
end

-- Normalised to ONE shape, because the raw return is eleven values whose
-- order has changed between flavours and is impossible to read at a call
-- site: { name, count, minBid, buyout, owner, quality, itemID, unit }
local function BrowseEntry(index)
    if not GetAuctionItemInfo then return nil end
    local name, _, count, quality, _, level, _, minBid, _, buyout,
          _, _, _, owner = GetAuctionItemInfo("list", index)
    if not name then return nil end
    count = (count and count > 0) and count or 1
    local link = GetAuctionItemLink and GetAuctionItemLink("list", index)
    local itemID
    if link then itemID = tonumber(link:match("item:(%d+)")) end
    return {
        name = name, count = count, quality = quality, level = level,
        minBid = minBid or 0, buyout = buyout or 0,
        unit = (buyout and buyout > 0) and math.floor(buyout / count) or nil,
        owner = owner, link = link, itemID = itemID, index = index,
    }
end

local function NumOwnedAuctions()
    if GetNumAuctionItems then
        local shown = GetNumAuctionItems("owner")
        return shown or 0
    end
    return 0
end

local function OwnedEntry(index)
    if not GetAuctionItemInfo then return nil end
    local name, _, count, quality, _, _, _, minBid, _, buyout,
          _, _, _, _, saleStatus = GetAuctionItemInfo("owner", index)
    if not name then return nil end
    count = (count and count > 0) and count or 1
    local link = GetAuctionItemLink and GetAuctionItemLink("owner", index)
    return {
        name = name, count = count, quality = quality,
        minBid = minBid or 0, buyout = buyout or 0,
        unit = (buyout and buyout > 0) and math.floor(buyout / count) or nil,
        link = link, index = index,
        sold = (saleStatus == 1),
    }
end

-- ============================================================
-- THE THROTTLE
-- ============================================================
-- One pending query at a time, retried until the server says yes. Without
-- this a shopping list of ten items fires ten queries in one frame and
-- gets the account disconnected.
local queue, waiting = {}, false
local waitingSince = nil

local function Pump()
    if waiting then
        -- WATCHDOG. The server does not always answer a query, and an
        -- unanswered one used to hold `waiting` forever - after which
        -- every later search, INCLUDING THE PAGE ARROWS, queued behind
        -- it silently. Five seconds without an answer voids the wait.
        if waitingSince and GetTime() - waitingSince > 5 then
            waiting = false
            waitingSince = nil
        else
            return
        end
    end
    if #queue == 0 then return end
    local job = queue[1]
    local canQuery = CanQuery()
    if not canQuery then
        C_Timer.After(0.2, Pump)
        return
    end
    table.remove(queue, 1)
    waiting = true
    waitingSince = GetTime()
    -- someone must look again AFTER the watchdog window, or a stuck
    -- wait only clears when the next user action happens to call Pump
    C_Timer.After(5.5, Pump)
    local ok, err = pcall(job.run)
    if not ok then
        waiting = false
        waitingSince = nil
        Print("auction query failed: " .. tostring(err))
        C_Timer.After(0.2, Pump)
    end
end

local function Queue(run, tag)
    queue[#queue + 1] = { run = run, tag = tag }
    Pump()
end

local function QueryDone()
    waiting = false
    waitingSince = nil
    C_Timer.After(0.1, Pump)
end

local function ClearQueue()
    wipe(queue)
    waiting = false
    waitingSince = nil
end

-- ASK THE SERVER FOR YOUR OWN AUCTIONS.
--
-- Nothing called this, and that is why the Cancel tab said "0 listed"
-- while auctions were sitting on the auction house perfectly happily.
-- GetNumAuctionItems("owner") does not go and look - it reads a list the
-- client only fills when GetOwnerAuctionItems is called. Reading it
-- without asking gives a confident zero, which is indistinguishable from
-- "your posts are failing" and is exactly how it was read.
--
-- Through the same throttle as searches: this is another auction query
-- and the server counts it the same way.
local function RefreshOwned()
    if not GetOwnerAuctionItems then
        return false, "this client has no owner-list API"
    end
    Queue(function() GetOwnerAuctionItems() end, "owner")
    return true
end


-- ============================================================
-- PRICE MEMORY
-- ============================================================
local MAX_HISTORY = 10

local function Store()
    ZacUIDB.auction = ZacUIDB.auction or {}
    local a = ZacUIDB.auction
    a.prices = a.prices or {}      -- [itemID] = { seen = {…}, name = }
    a.lists  = a.lists or {}       -- [name] = { "search term", … }
    if a.undercut == nil then a.undercut = 1 end   -- copper below lowest
    if a.duration == nil then a.duration = 3 end   -- 1=2h 2=8h 3=24h
    if a.keepDays == nil then a.keepDays = 30 end
    return a
end

-- Record ONE observation. Called per result row, so it must be cheap and
-- must not allocate a history entry for every duplicate listing of the
-- same item - only the cheapest per scan is worth keeping.
local scanLow = {}

-- ONE OBSERVATION PER QUERY, NOT PER LIST UPDATE.
--
-- AUCTION_ITEM_LIST_UPDATE fires again for the same page - as seller
-- names resolve, after every purchase, for the exact-name retry - and
-- every one of those used to append a fresh "sighting". One search could
-- fill most of the ten-entry history with itself, and the median the Sell
-- tab suggests collapsed to whatever the last scan said.
--
-- So each query, whoever sends it (this window, Blizzard's, another
-- addon), opens a scan: hooksecurefunc on QueryAuctionItems runs after
-- the call, outside its execution, and only bumps a counter. Updates that
-- belong to the same scan MERGE into the entry that scan already wrote
-- (keeping the cheaper unit) instead of adding another. The per-scan
-- record is session-only; nothing new goes into SavedVariables.
local scanToken = 0
local lastCommit = {}       -- itemID -> { token =, entry = }
local priorByScan = {}      -- itemID -> prior median, for THIS scan

local function NewScan()
    scanToken = scanToken + 1
    wipe(priorByScan)
end
if type(_G.QueryAuctionItems) == "function" and hooksecurefunc then
    hooksecurefunc("QueryAuctionItems", NewScan)
end

local function NoteResult(entry)
    if not entry or not entry.itemID or not entry.unit or entry.unit <= 0 then
        return
    end
    local cur = scanLow[entry.itemID]
    if not cur or entry.unit < cur.unit then
        scanLow[entry.itemID] = { unit = entry.unit, name = entry.name }
    end
end

local function NoteScanEnd()
    local prices = Store().prices
    local now = time and time() or 0
    for itemID, low in pairs(scanLow) do
        local rec = prices[itemID]
        if not rec then
            rec = { seen = {} }
            prices[itemID] = rec
        end
        rec.name = low.name or rec.name
        local lc = lastCommit[itemID]
        if lc and lc.token == scanToken and rec.seen[1] == lc.entry then
            -- Same scan seen again: one sighting, the cheapest of them.
            if low.unit < lc.entry.unit then lc.entry.unit = low.unit end
        else
            local e = { unit = low.unit, at = now }
            table.insert(rec.seen, 1, e)
            -- Bounded: ten observations is enough to see a trend and small
            -- enough that a full price memory stays a few hundred KB.
            while #rec.seen > MAX_HISTORY do table.remove(rec.seen) end
            if not lc then lc = {} lastCommit[itemID] = lc end
            lc.token, lc.entry = scanToken, e
        end
    end
    wipe(scanLow)
end

-- The number the Sell tab suggests. Median of what we have seen rather
-- than the minimum: one person dumping a stack at a silly price should
-- not drag every future suggestion down with it.
local function Suggest(itemID)
    local rec = Store().prices[itemID]
    if not rec or #rec.seen == 0 then return nil end
    local units = {}
    for _, s in ipairs(rec.seen) do units[#units + 1] = s.unit end
    table.sort(units)
    local mid = math.ceil(#units / 2)
    return units[mid], rec.seen[1].at, #units
end

local function LastSeen(itemID)
    local rec = Store().prices[itemID]
    if not rec or #rec.seen == 0 then return nil end
    return rec.seen[1].unit, rec.seen[1].at
end

-- Housekeeping: a price memory that only ever grows becomes a saved
-- variables file that takes a second to load.
local function Prune()
    local a = Store()
    local cutoff = (time and time() or 0) - (a.keepDays or 30) * 86400
    local dropped = 0
    for itemID, rec in pairs(a.prices) do
        for i = #rec.seen, 1, -1 do
            if (rec.seen[i].at or 0) < cutoff then table.remove(rec.seen, i) end
        end
        if #rec.seen == 0 then
            a.prices[itemID] = nil
            dropped = dropped + 1
        end
    end
    return dropped
end

local function Count()
    local n = 0
    for _ in pairs(Store().prices) do n = n + 1 end
    return n
end

-- ============================================================
-- SEARCH
-- ============================================================
-- sent(), when given, runs right after the query has gone out - the
-- moment its scan exists (see NewScan).
local function Search(text, page, exact, sent)
    Queue(function()
        QueryAuctionItems(text or "", nil, nil, page or 0, false, 0, false,
            exact and true or false)
        if sent then sent() end
    end, "search")
end

-- ============================================================
-- WHAT IS IT GOING FOR RIGHT NOW
-- ============================================================
-- The price memory answers "what has this been worth", which is the right
-- question when you are deciding whether to bother. It is the wrong
-- question when you are about to POST: what matters then is what the item
-- is listed at this minute, because that is what your auction has to beat.
--
-- So this runs a live, exact-name scan for one item and reports the
-- cheapest listing that is not your own. Your own auctions are excluded
-- deliberately - undercutting yourself is a loop that walks your own
-- price to zero, one relist at a time.
local priceCheck

local function LowestNow(itemName, callback)
    if not itemName or itemName == "" then return false, "no item" end
    if priceCheck then return false, "already checking a price" end
    local check = {
        name = itemName:lower(),
        callback = callback,
        startedAt = GetTime and GetTime() or 0,
    }
    priceCheck = check
    -- ANSWERED ONLY BY ITS OWN QUERY. The search waits its turn in the
    -- throttle, and the first list update after this call used to be
    -- taken as the answer - often a page that belonged to something else,
    -- which read as "none listed - name your price".
    Search(itemName, 0, true, function()
        if priceCheck == check then check.token = scanToken end
    end)
    -- The server does not always answer. Without this the Sell tab would
    -- sit on "checking..." forever and the next check would be refused
    -- because this one never ended.
    if C_Timer and C_Timer.After then
        local generation = priceCheck
        C_Timer.After(6, function()
            if priceCheck == generation then
                priceCheck = nil
                if callback then pcall(callback, nil, "the auction house did not answer") end
            end
        end)
    end
    return true
end

-- Fed by Harvest with the page that just arrived.
local function ResolvePriceCheck(rows)
    if not priceCheck or priceCheck.token ~= scanToken then return end
    local me = UnitName and UnitName("player")
    local best
    for _, row in ipairs(rows or {}) do
        if row.name and row.name:lower() == priceCheck.name
            and row.buyout and row.buyout > 0
            and row.owner ~= me then
            local unit = row.unit or row.buyout
            if not best or unit < best.unit then
                best = { unit = unit, count = row.count or 1,
                         buyout = row.buyout, owner = row.owner }
            end
        end
    end
    local cb = priceCheck.callback
    priceCheck = nil
    if cb then
        -- No listings is a real, useful answer - it means you can name
        -- your own price - so it is reported as success with no data
        -- rather than as a failure.
        pcall(cb, best, nil)
    end
end

-- Harvest whatever the server just delivered. Called from the update
-- event, so it must tolerate being called when nothing is showing.
-- THE ORDERING TRAP, and why this is two loops rather than one.
--
-- Harvesting a page does two different jobs: it RECORDS what it sees into
-- the price memory, and it hands the rows to the UI to be RATED against
-- that memory. Do them in one pass and the page rates itself - the first
-- time you ever search an item, one lowball listing becomes "the market"
-- and every other listing on the page is flagged as a scam. Worse, it is
-- self-confirming: the cheapest listing always looks fair and everything
-- above it always looks bad, whatever the real prices are.
--
-- So the prior median for each item is captured BEFORE anything from this
-- page is committed, stamped onto every row, and used for the rating.
-- A brand new item therefore has no rating at all, which is the honest
-- answer - not "fair".
local function Harvest()
    local shown, total = NumBrowseResults()
    local rows, priorMarket = {}, {}

    for i = 1, shown do
        local entry = BrowseEntry(i)
        if entry then
            if entry.itemID and priorMarket[entry.itemID] == nil then
                -- false, not nil, so "looked it up and there was nothing"
                -- is distinguishable from "have not looked yet". Taken
                -- once per SCAN: a repeat update of the same page must not
                -- be rated against the sighting its first update recorded.
                local prior = priorByScan[entry.itemID]
                if prior == nil then
                    prior = Suggest(entry.itemID) or false
                    priorByScan[entry.itemID] = prior
                end
                priorMarket[entry.itemID] = prior
            end
            entry.marketBefore = priorMarket[entry.itemID] or nil
            rows[#rows + 1] = entry
        end
    end

    -- Only now does this page become part of the memory.
    for _, entry in ipairs(rows) do NoteResult(entry) end
    NoteScanEnd()

    -- A live price check is waiting on exactly this page.
    ResolvePriceCheck(rows)
    return rows, shown, total
end

-- ============================================================
-- GROUPING AND RANKING
-- ============================================================
-- THREE PROBLEMS WITH A RAW RESULT PAGE, all of which this fixes.
--
--   1. THE THING YOU SEARCHED FOR IS NOT AT THE TOP. The server matches
--      substrings, so "Linen Cloth" also returns "Bolt of Linen Cloth" and
--      "Linen Cloth Bandage", interleaved by price. Exact name matches are
--      hoisted above everything else.
--
--   2. ONE SELLER, FIFTY ROWS. Somebody dumping fifty identical stacks at
--      one price fills the entire page and hides everyone else. Listings
--      that agree on item, seller, stack size AND price are one row with a
--      count - which is also honest, because they ARE one offer.
--
--   3. THE PRICE TRAP. A page sorted by total buyout puts a single unit at
--      2g above a 20-stack at 30g, and the single looks cheaper. Ranking
--      is per unit, and anything well above what the item has historically
--      gone for is flagged rather than left for you to notice.

local GOUGE_WARN  = 1.5    -- x market before it is worth mentioning
local GOUGE_BAD   = 3.0    -- x market before it is probably a trap

-- How this listing compares to what we have seen. Returns the multiple and
-- a severity, or nil when there is nothing to compare against - "unknown"
-- and "fair" must never look the same.
-- The `market` is passed in rather than looked up, because of the ordering
-- trap below: by the time a page is being rated, that same page has
-- already been recorded, so looking the price up here would rate every
-- listing against itself. Harvest captures the PRIOR median per item and
-- hands it over.
local function PriceRating(entry, market)
    if not entry.itemID or not entry.unit then return nil end
    market = market or (entry.marketBefore)
    if not market or market <= 0 then return nil end
    local ratio = entry.unit / market
    local severity = "fair"
    if ratio >= GOUGE_BAD then
        severity = "bad"
    elseif ratio >= GOUGE_WARN then
        severity = "warn"
    elseif ratio <= 0.75 then
        severity = "good"
    end
    return ratio, severity
end

local function Group(rows, term)
    local wanted = term and term:lower() or nil
    local byKey, out = {}, {}

    for _, e in ipairs(rows) do
        -- Identical offers only: same item, same seller, same stack size,
        -- same unit price. Anything else is genuinely a different choice.
        local key = table.concat({
            tostring(e.itemID or e.name), tostring(e.owner),
            tostring(e.count), tostring(e.unit or e.minBid),
        }, "|")
        local group = byKey[key]
        if group then
            group.listings = group.listings + 1
            group.indices[#group.indices + 1] = e.index
            group.totalUnits = group.totalUnits + (e.count or 1)
            -- Keep the LOWEST index: that is the one a single buyout
            -- targets, and the server orders its own page.
            if e.index < group.index then group.index = e.index end
        else
            e.listings = 1
            -- EVERY index is kept, not just one. A merged row is several
            -- real listings, and buying "200 of these" has to know all of
            -- them - collapsing to one index would silently cap a bulk
            -- purchase at a single stack.
            e.indices = { e.index }
            e.totalUnits = e.count or 1
            e.exact = wanted and e.name and (e.name:lower() == wanted) or false
            e.ratio, e.severity = PriceRating(e, e.marketBefore)
            byKey[key] = e
            out[#out + 1] = e
        end
    end

    table.sort(out, function(a, b)
        -- What you asked for, first.
        if a.exact ~= b.exact then return a.exact end
        if a.name ~= b.name then return (a.name or "") < (b.name or "") end
        -- Then cheapest PER UNIT, which is the only comparison that means
        -- anything across different stack sizes.
        local au = a.unit or math.huge
        local bu = b.unit or math.huge
        if au ~= bu then return au < bu end
        return (a.count or 0) > (b.count or 0)
    end)
    return out
end

-- ============================================================
-- BULK BUYING
-- ============================================================
-- Buying one listing at a time through a confirmation dialog is unusable
-- when you want two hundred of something that is listed in stacks of ten.
-- So the flow is: say how many UNITS you want, get one plan, confirm once.
--
-- TWO THINGS MAKE THIS DANGEROUS AND BOTH ARE HANDLED HERE.
--
--   1. INDICES RENUMBER. Buying listing 3 shifts everything above it down
--      by one, so any index recorded when the plan was made is wrong from
--      the second purchase onward. Issuing highest-index-first was the
--      first answer and it is not enough, because the server sends a
--      fresh list after every purchase and that reorders everything. So
--      the plan records WHAT each target is, and each purchase re-finds
--      it on the current page - see ExecutePurchase.
--
--   2. IT SPENDS REAL MONEY WITHOUT ASKING AGAIN. The plan therefore
--      refuses to exceed what you actually have, caps how many listings
--      one action can consume, and reports the worst price rating in the
--      set so a bulk buy cannot quietly include a gouge.

local MAX_BULK_LISTINGS = 25

local function PlanPurchase(grouped, entry, wantUnits)
    if not entry then return nil, "pick a listing first" end
    wantUnits = math.max(1, math.floor(tonumber(wantUnits) or 1))

    -- Candidates: THE ROW THAT WAS CLICKED, nothing else. This used to
    -- sweep every listing of the item cheapest-per-unit first, which
    -- meant selecting a 10-stack could buy a 20-stack because it was a
    -- hair cheaper per unit - a purchase nobody asked for. What you
    -- click is what you buy: a run is homogeneous by construction, every
    -- purchase in it the same stack size at the same price. Wanting the
    -- cheaper group is one click away - on that row.
    local candidates = {}
    for _, row in ipairs(grouped) do
        local isPicked = (row == entry)
            or (row.name == entry.name
                and (row.count or 1) == (entry.count or 1)
                and row.buyout == entry.buyout
                and row.owner == entry.owner)
        if isPicked and row.buyout and row.buyout > 0 then
            for _, index in ipairs(row.indices or { row.index }) do
                candidates[#candidates + 1] = {
                    index = index, unit = row.unit, count = row.count,
                    buyout = row.buyout, owner = row.owner,
                    name = row.name, severity = row.severity, ratio = row.ratio,
                }
            end
        end
    end
    if #candidates == 0 then
        return nil, "that listing has no buyout price"
    end
    table.sort(candidates, function(a, b) return a.index < b.index end)

    local money = GetMoney and GetMoney() or 0
    local plan = { picks = {}, units = 0, total = 0, worst = nil, item = entry.name }

    for _, c in ipairs(candidates) do
        if plan.units >= wantUnits then break end
        if #plan.picks >= MAX_BULK_LISTINGS then
            plan.cappedByCount = true
            break
        end
        if plan.total + c.buyout > money then
            plan.cappedByMoney = true
            break
        end
        plan.picks[#plan.picks + 1] = c
        plan.units = plan.units + (c.count or 1)
        plan.total = plan.total + c.buyout
        -- Track the WORST rating in the set, so one gouge inside a bulk
        -- buy cannot hide behind twenty fair ones.
        if c.ratio and (not plan.worstRatio or c.ratio > plan.worstRatio) then
            plan.worstRatio, plan.worst = c.ratio, c.severity
        end
    end

    if #plan.picks == 0 then
        if plan.cappedByMoney then return nil, "you cannot afford even one of these" end
        return nil, "nothing to buy"
    end
    plan.avgUnit = math.floor(plan.total / math.max(1, plan.units))
    plan.wanted = wantUnits
    return plan
end

-- ============================================================
-- BUYING, ONE AT A TIME
-- ============================================================
-- THIS WAS A LOOP AND THE LOOP WAS WRONG TWICE OVER.
--
-- ATTEMPT ONE fired every buyout in a single frame. The client blocked
-- the second one, and because each call was wrapped in pcall - which does
-- NOT catch a blocked action, since it is a message and not a Lua error -
-- every blocked purchase still counted as bought. It reported buying
-- twenty listings having bought one. It also bought by INDEX, and the
-- server renumbers the list after every purchase, so from the second buy
-- onwards those indices pointed at whatever had shifted into place.
--
-- ATTEMPT TWO made it sequential: buy one, wait for the list, re-find the
-- next target by what it IS, verify by counting. All of that is right and
-- all of it is kept. What was wrong was WHO drives the next purchase.
-- Chaining it off the AUCTION_ITEM_LIST_UPDATE event produced this:
--
--     ADDON_ACTION_BLOCKED: 'PlaceAuctionBid()'
--       AH_Core.lua:595 in function <AH_Core.lua:549>
--       AH_Core.lua:625 in function 'OnListUpdate'
--
-- PlaceAuctionBid is PROTECTED. It requires a hardware event - a real
-- click or keypress - and an event handler is not one. That is why the
-- first purchase always worked (it came from the confirm dialog's click)
-- and every one after it was refused. No amount of restructuring fixes
-- that; a chain of purchases cannot be driven by anything but the mouse.
--
-- So the design changes to suit the rule instead of fighting it. The plan
-- is prepared once, and then each purchase is taken by a CLICK on a
-- button that stays put and counts down. Nineteen listings is nineteen
-- clicks in one place - which is also, as it happens, nineteen chances to
-- stop, and this is the one part of the addon that spends real gold.
local buying

local function TargetOf(pick)
    return {
        name = pick.name, buyout = pick.buyout,
        count = pick.count or 1, owner = pick.owner,
    }
end

local function Matches(entry, target)
    return entry.name == target.name
        and entry.buyout == target.buyout
        and (entry.count or 1) == target.count
        and entry.owner == target.owner
end

-- Find a target in the CURRENT list.
local function FindTarget(target)
    local shown = NumBrowseResults()
    for i = 1, shown do
        local entry = BrowseEntry(i)
        if entry and Matches(entry, target) then return i, entry end
    end
    return nil
end

-- HOW MANY of that exact listing are on the page.
--
-- This exists because "is it still there?" is the wrong question, and
-- asking it broke bulk buying completely. A row like "Mighty Rage Potion
-- x19" is nineteen SEPARATE listings from one seller at one price -
-- identical in every field there is. Buy one and eighteen remain, so a
-- presence check says the listing is still there and concludes the
-- purchase was blocked. The run then stopped after exactly one purchase
-- and reported buying none.
--
-- Merging identical listings is a feature of this window, so identical
-- listings are the normal case, not an edge case. Counting is the only
-- check that works on them.
local function CountMatches(target)
    local shown = NumBrowseResults()
    local n = 0
    for i = 1, shown do
        local entry = BrowseEntry(i)
        if entry and Matches(entry, target) then n = n + 1 end
    end
    return n
end

-- The run that just ended, kept for a minute: the auction house can
-- confirm a purchase after you have already clicked Done, and that
-- purchase happened all the same.
local recent

local function FinishPurchase(reason)
    if not buying then return end
    local done = buying
    buying = nil
    recent = done
    if C_Timer and C_Timer.After then
        C_Timer.After(60, function() if recent == done then recent = nil end end)
    end
    if done.onDone then
        pcall(done.onDone, done.bought, done.spent, reason, done.missed, done.units)
    end
end

-- ONE PURCHASE. Must be called from a click - PlaceAuctionBid is
-- protected and refuses anything else. Returns false plus a reason when
-- there is nothing to do, so the button can say why.
-- KEEP GOING. The queue is what was PLANNED, and a plan is a snapshot -
-- "buy out this listing" plans exactly one. Reaching the end of it is not
-- a reason to shut the window in your face; it is a reason to look at
-- what is on the page now and offer the next cheapest of the same item.
--
-- The page is current by construction: the server sends a fresh list
-- after every purchase, which is the same list the confirmation reads.
local function Refill()
    if not buying or not buying.item then return 0 end
    local me = UnitName and UnitName("player")
    local money = GetMoney and GetMoney() or 0
    local found = {}
    for i = 1, NumBrowseResults() do
        local entry = BrowseEntry(i)
        if entry and entry.name == buying.item
            and entry.buyout and entry.buyout > 0
            and entry.owner ~= me
            and entry.buyout <= money
            -- THE RUN'S SIGNATURE: only listings with the exact stack
            -- size and price that was clicked may ever join the queue.
            -- Without this, exhausting the picked group let a re-search
            -- feed the run a different stack size - the same "bought 20
            -- thinking 10" bug arriving through the refill.
            and (not buying.sigCount or (entry.count or 1) == buying.sigCount)
            and (not buying.sigBuyout or entry.buyout == buying.sigBuyout) then
            found[#found + 1] = entry
        end
    end
    -- Cheapest per unit first, the same order the plan used.
    table.sort(found, function(a, b)
        return (a.unit or a.buyout) < (b.unit or b.buyout)
    end)
    for _, entry in ipairs(found) do
        buying.queue[#buying.queue + 1] = TargetOf(entry)
    end
    return #found
end

local function BuyNext()
    if not buying then return false, "nothing to buy" end
    if buying.pending then return false, "waiting for the last one" end
    -- Out of planned targets: look again rather than stop.
    if #buying.queue == 0 then Refill() end
    if not PlaceAuctionBid then
        FinishPurchase("this client has no bidding API")
        return false, "no bidding API"
    end

    -- Skip anything that is no longer on the list - somebody else got it
    -- while we were working through ours.
    local target, index, entry
    while #buying.queue > 0 do
        target = table.remove(buying.queue, 1)
        index, entry = FindTarget(target)
        if index then break end
        buying.missed = buying.missed + 1
        target = nil
    end
    if not target or not index then
        -- Page exhausted - but the RUN STAYS ALIVE. Finishing here is
        -- what slammed the window shut after one buy whenever the page
        -- held a single listing. The window now says "none left" and a
        -- fresh search refills the queue on the next click; only the
        -- Done button (or closing the window) ends a run.
        return false, "none left on this page - search again for more"
    end

    -- Money is re-checked here, not just when the plan was made: the
    -- earlier purchases in this run have already been paid for.
    local money = GetMoney and GetMoney() or 0
    if entry.buyout > money then
        FinishPurchase("ran out of money")
        return false, "ran out of money"
    end

    buying.pending = target
    -- Evidence for the confirmation signals: the copy-count of this exact
    -- listing, and the wallet before the click. The click itself is kept
    -- for the whole run, so a confirmation that arrives late still has
    -- something to land on.
    buying.pendingCount = CountMatches(target)
    buying.pendingMoney = GetMoney and GetMoney() or nil
    local click = { buyout = entry.buyout or 0, count = entry.count or 1, owner = target.owner,
        money = buying.pendingMoney, at = GetTime and GetTime() or 0 }
    buying.clicks[#buying.clicks + 1] = click
    buying.pendingClick = click

    -- Deliberately NOT wrapped in pcall. A blocked action is not a Lua
    -- error and pcall cannot see it; wrapping only hid the failure and
    -- let it be counted as a success.
    PlaceAuctionBid("list", index, entry.buyout)

    -- If nothing confirms, VOID the click - uncounted, unspent - and
    -- keep the run alive for the next one. A confirmation timeout is
    -- "the click may not have registered", never "stop everything".
    if C_Timer and C_Timer.After then
        local generation = buying
        C_Timer.After(4, function()
            if buying == generation and buying.pending == target then
                buying.pending, buying.pendingCount = nil, nil
                buying.pendingMoney, buying.pendingClick = nil, nil
                Print("the auction house has not confirmed that buy yet - it "
                    .. "is not counted, but it will be the moment the server "
                    .. "confirms it. Check your gold before clicking again.")
                if buying.onChange then pcall(buying.onChange) end
            end
        end)
    end
    return true
end

-- Called when the browse list arrives. CONFIRMATION ONLY - it must not
-- start the next purchase, because it is an event handler and a protected
-- call made from one is exactly what was refused.
-- ============================================================
-- CONFIRMING A PURCHASE - BY EVIDENCE, NEVER BY LIST TIMING
-- ============================================================
-- The old check watched AUCTION_ITEM_LIST_UPDATE and expected the bought
-- listing to be gone. On this client the FIRST update after a buyout
-- regularly still carries the stale page, so real purchases - "You won
-- an auction" printing in chat, gold leaving the bag - were declared
-- "did not go through" and the whole run was killed. Three signals now
-- confirm a purchase, whichever lands first:
--   1. the server's own ERR_AUCTION_WON_S system message for this item
--   2. the wallet dropping by EXACTLY the pending buyout
--   3. a list update where the listing's copy-count actually decreased
-- And there is NO failure verdict from events at all: if nothing
-- confirms within 4 seconds the pending click is voided - not counted,
-- not spent - and the run stays alive for the next click.
-- COUNTED BY THE SERVER'S WORD, ONCE PER CLICK.
--
-- Two ways the count used to disagree with what was actually bought:
--   * a buy confirmed later than four seconds was voided, and the "You
--     won an auction" that then arrived was ignored - so the window said
--     fewer than you got;
--   * a drop in how many identical listings were on the page counted as
--     a purchase - but that also happens when somebody else buys one, or
--     when the page is replaced - so the window could say more.
-- Now only two things count a purchase, and each click counts at most
-- once whichever of them lands: the server's ERR_AUCTION_WON_S message
-- for the item, and the wallet dropping by exactly that click's buyout.
-- A message that arrives late, even after Done, still finds its click.
-- The list update only lets the next click go ahead; it never counts.
local function CountClick(run, c)
    if c.counted then return false end
    c.counted = true
    run.bought = run.bought + 1
    run.units = run.units + (c.count or 1)
    run.spent = run.spent + (c.buyout or 0)
    if run.done then run.done[#run.done + 1] = { owner = c.owner, count = c.count or 1, buyout = c.buyout or 0 } end
    return true
end

-- The pending click is settled (counted or not): free the button.
local function Release(run)
    if not run.pending then return end
    run.pending, run.pendingCount = nil, nil
    run.pendingMoney, run.pendingClick = nil, nil
    if run == buying then
        if #run.queue == 0 then Refill() end
        if run.onChange then pcall(run.onChange) end
        if run.onConfirmed then pcall(run.onConfirmed) end
    end
end

local function OnListUpdate()
    local run = buying
    if not run or not run.pending then return end
    if CountMatches(run.pending) < (run.pendingCount or 1) then
        -- Something changed - most likely our buy. The next click may go;
        -- the count waits for the server or the wallet.
        Release(run)
    end
    -- an UNCHANGED count says nothing - stale page - so it is ignored
end

-- Which click a "you won" message belongs to: one the wallet already
-- confirmed and the message has not, newest first; else the click still
-- waiting; else the oldest click nothing has confirmed (a late answer).
local function ClickForMessage(run)
    local now = GetTime and GetTime() or 0
    for i = #run.clicks, 1, -1 do
        local c = run.clicks[i]
        if c.byMoney and not c.byMsg then return c end
    end
    local p = run.pendingClick
    if p and not p.byMsg then return p end
    for _, c in ipairs(run.clicks) do
        if not c.byMsg and not c.counted and now - (c.at or 0) <= 120 then return c end
    end
end

local function OnSystemMessage(msg)
    if not msg then return end
    -- Not ipairs over { buying, recent }: with no live run the first
    -- slot is nil and ipairs would never reach the recent one.
    for k = 1, 2 do
        local run = (k == 1) and buying or recent
        if run and run.item then
            local won = ERR_AUCTION_WON_S and string.format(ERR_AUCTION_WON_S, run.item)
            if won and msg == won then
                local c = ClickForMessage(run)
                if c then
                    c.byMsg = true
                    local added = CountClick(run, c)
                    if run == buying then
                        if run.pendingClick == c then Release(run)
                        elseif added and run.onChange then pcall(run.onChange) end
                    elseif added then
                        Print("one more " .. run.item .. " purchase was confirmed "
                            .. "after the window closed - " .. run.bought
                            .. " auction" .. (run.bought == 1 and "" or "s")
                            .. " (" .. run.units .. " item" .. (run.units == 1 and "" or "s")
                            .. ") in all.")
                    end
                    return
                end
            end
        end
    end
end

local function OnMoneyChanged()
    local run = buying
    local c = run and run.pendingClick
    if not c or not c.money then return end
    if c.buyout > 0 and (GetMoney and GetMoney() or 0) == c.money - c.buyout then
        c.byMoney = true
        CountClick(run, c)
        Release(run)
    end
end

-- Prepares a run. Buys NOTHING - the first purchase, like every one after
-- it, has to come from a click.
local function BeginPurchase(plan, onChange, onDone, onConfirmed)
    if buying then return false, "already buying something" end
    if not plan or not plan.picks or #plan.picks == 0 then
        return false, "nothing to buy"
    end
    if not PlaceAuctionBid then return false, "this client has no bidding API" end

    -- (2026-11-09: total and done are for the buy window's progress bar
    -- and its list of what was bought)
    buying = { queue = {}, bought = 0, spent = 0, missed = 0, units = 0, clicks = {}, done = {},
               total = #plan.picks,
               item = plan.item, onChange = onChange, onDone = onDone,
               onConfirmed = onConfirmed }
    -- the run's identity: stack size and price of what was clicked
    local first = plan.picks[1]
    buying.sigCount = first and (first.count or 1) or nil
    buying.sigBuyout = first and first.buyout or nil
    -- Cheapest first, so a run stopped part way has still bought the best
    -- of what was asked for.
    local picks = {}
    for _, pick in ipairs(plan.picks) do picks[#picks + 1] = pick end
    table.sort(picks, function(a, b)
        return (a.unit or a.buyout or 0) < (b.unit or b.buyout or 0)
    end)
    for _, pick in ipairs(picks) do
        buying.queue[#buying.queue + 1] = TargetOf(pick)
    end
    return true
end

-- Everything the button needs to draw itself.
local function PurchaseState()
    if not buying then return nil end
    local nextUp = buying.queue[1]
    return {
        bought = buying.bought, spent = buying.spent, missed = buying.missed,
        units = buying.units,
        remaining = #buying.queue, waiting = buying.pending ~= nil,
        nextPrice = nextUp and nextUp.buyout or nil,
        nextCount = nextUp and nextUp.count or nil,
        nextName = nextUp and nextUp.name or nil,
        -- every auction of the run (bought ones leave the queue), the
        -- queue itself and what was bought, for the window's bar and list
        total = buying.total, queue = buying.queue, done = buying.done,
    }
end

local function CancelPurchase()
    FinishPurchase("stopped")
end

local function PurchaseInProgress()
    return buying ~= nil
end

-- ============================================================
-- SELLING AND CANCELLING
-- ============================================================
-- THE SAME TRAP THE BAG SORT HIT. PickupContainerItem is not a global on
-- 1.15 - it lives on C_Container, and the bare name is nil. Posting
-- therefore failed its own capability check and reported "this client has
-- no posting API", which is a confident, specific, wrong diagnosis: the
-- API is there, it just moved. Both spellings are probed, and the error
-- now names what is actually missing.
-- ============================================================
-- POSTING, AS A WORKING CLASSIC ERA ADDON ACTUALLY DOES IT
-- ============================================================
-- THE FUNCTION IS CALLED PostAuction ON 1.15. StartAuction is the name
-- from the original client and it is simply not there any more, so the
-- capability check at the top of PostAuction - `if not StartAuction` -
-- was true on every single attempt and posting returned an error before
-- it did anything at all. That is the whole bug, and it is the third
-- variation of the same mistake in this file: the API had moved, the
-- guard reported the absence honestly, and the absence was read as "the
-- client cannot do this" rather than "the name changed".
--
-- The previous round's theory - that the Auctions tab had to be selected
-- first - was wrong, and it is worth saying so rather than quietly
-- deleting it. Aux, an auction addon that works on this client, never
-- touches AuctionFrame's tabs at any point; it nils out AuctionFrame_Show
-- entirely so Blizzard's window never appears. ClickAuctionSellItemButton
-- needs the auction house SESSION, not the tab. Switching Blizzard's tabs
-- from an addon would have been a taint risk for nothing.
--
-- What aux does do, and what was actually missing, is EMPTY THE SELL SLOT
-- FIRST. A click with an empty cursor takes whatever is in the slot back
-- out; without it, a slot still holding the last item silently refuses
-- the new one. Hence clear, click, clear - then pick up, click, clear.
local function CanPickUp()
    return (C_Container and C_Container.PickupContainerItem)
        or _G.PickupContainerItem
end

local function PostFn()
    return _G.PostAuction or _G.StartAuction
end

local function EmptySellSlot()
    ClearCursor()
    ClickAuctionSellItemButton()
    ClearCursor()
end

local function PostAuction(bag, slot, unitPrice, stackSize, duration, stacks)
    -- Named individually, so a future move of any one of them says which.
    if not CanPickUp() then
        return false, "cannot pick items up on this client"
    end
    if not PostFn() then
        return false, "this client has neither PostAuction nor StartAuction"
    end
    if not ClickAuctionSellItemButton then
        return false, "this client has no auction sell slot"
    end
    if not unitPrice or unitPrice <= 0 then return false, "set a price first" end
    stackSize = stackSize or 1

    -- ============================================================
    -- A STACK CANNOT BE BIGGER THAN THE ITEM ALLOWS
    -- ============================================================
    -- THIS IS WHY THE FIREWATER NEVER LISTED. The Sell panel offered a
    -- stack of 46 because that is how many were in the bags; Winterfall
    -- Firewater stacks to 20, and PostAuction will not build a stack it
    -- cannot make. It refuses the way this client refuses everything - by
    -- doing nothing and saying nothing - so the trace showed a flawless
    -- run right up to a call that quietly did not happen.
    --
    -- Checked BEFORE the item is picked up, not after. The first version
    -- of this check ran once the item was already in the sell slot, and
    -- refusing there left it stranded: out of the bags, not on the
    -- auction house, and invisible to the player. A guard that damages
    -- what it is guarding is worse than no guard.
    --
    -- Checked here as well as clamped in the panel, because the box is
    -- typeable and the panel is not the only caller.
    local bagItem = C_Container and C_Container.GetContainerItemInfo
        and C_Container.GetContainerItemInfo(bag, slot)
    local bagLink = bagItem and bagItem.hyperlink
    if bagLink and GetItemInfo then
        local maxStack = select(8, GetItemInfo(bagLink))
        if maxStack and stackSize > maxStack then
            local nice = bagLink:match("%[(.-)%]") or "that item"
            return false, nice .. " stacks to " .. maxStack
                .. ", so a stack of " .. stackSize .. " cannot be posted"
        end
    end
    local total = unitPrice * stackSize
    -- BLIZZARD COMPLAINS ABOUT ITS OWN API HERE.
    --
    -- Posting through the legacy auction functions makes the client show
    -- AUCTION_HOUSE_DEPRECATED, whose text reads "This addon has been
    -- disabled. You should install an updated version." Both halves are
    -- false: nothing is disabled, the auction posts perfectly, and there
    -- is no updated version to install because Classic Era has no other
    -- posting API - C_AuctionHouse is a later-expansion addition.
    --
    -- The popup is dismissed for exactly this call and nothing else. The
    -- timestamp is what scopes it: a deprecation popup that arrives a
    -- second after a post is ours, and one that arrives at any other time
    -- belongs to somebody else and is left alone.
    local function Trace(line)
        if AH.postWatch then Print("post: " .. line) end
    end

    Trace("posting with "
        .. (_G.PostAuction and "PostAuction" or "StartAuction"))

    AH.postedAt = GetTime and GetTime() or 0

    -- Take out whatever is already in the slot. A slot that still holds
    -- the last item refuses the next one in silence, which is exactly the
    -- failure that looks like "posting does nothing".
    EmptySellSlot()

    if not Bags.Pickup(bag, slot) then
        return false, "could not pick the item up"
    end
    Trace("picked up bag " .. tostring(bag) .. " slot " .. tostring(slot)
        .. ", cursor holds item = "
        .. tostring(GetCursorInfo and GetCursorInfo() ~= nil))
    ClickAuctionSellItemButton()
    ClearCursor()

    -- ASK WHETHER IT WORKED. This is the step whose absence turned a
    -- broken tab into "the auction did not go up, check your deposit" -
    -- a confident, specific and completely wrong diagnosis that sent the
    -- search in the wrong direction for days. GetAuctionSellItemInfo is
    -- the client's own answer to "what is in the sell slot", and if the
    -- answer is nothing then there is no point calling StartAuction.
    local sellName, _, sellCount = GetAuctionSellItemInfo and GetAuctionSellItemInfo()
    Trace("sell slot holds " .. tostring(sellName) .. " x" .. tostring(sellCount))

    if not sellName then
        -- Leave the bags exactly as they were found. EmptySellSlot, not a
        -- bare ClearCursor: by this point the item may be sitting in the
        -- sell slot rather than on the cursor, and clearing the cursor
        -- would strand it there - out of the bags, not on the auction
        -- house, and gone as far as the player can tell.
        EmptySellSlot()
        return false, "the item never reached the sell slot - nothing was posted"
    end

    -- The deposit is charged the moment the auction goes up, and a post
    -- that cannot pay it fails with no message of any kind.
    local runTime = duration or Store().duration
    local deposit = 0
    if CalculateAuctionDeposit then
        deposit = CalculateAuctionDeposit(runTime) or 0
    end
    local purse = GetMoney and GetMoney() or 0
    -- ONE stack's worth, not the whole run. Refusing a post that would
    -- actually have succeeded is a worse bug than the one this replaces,
    -- so the test is only the part that is certain: you cannot post even
    -- once without covering a single deposit.
    if deposit > 0 and purse < deposit then
        ClearCursor()
        return false, "the deposit is " .. ns.Money(deposit, true)
            .. " and you have " .. ns.Money(purse, true)
    end

    -- Recorded so the result can be CHECKED rather than announced. The
    -- old code printed "posted" the instant it had made the calls, which
    -- is the same mistake bulk buying made: reporting an intention as an
    -- outcome.
    --
    -- mode is what tells the event handlers what to wait for: a single
    -- stack is done when it leaves the bags, several are done when the
    -- client has counted them all off first.
    AH.posting = {
        mode = (stacks or 1) > 1 and "multi" or "single",
        at = AH.postedAt, name = sellName, stacks = stacks or 1,
    }

    -- Bid is deliberately set equal to buyout. A bid below buyout invites
    -- someone to win the item for less than you were willing to take.
    --
    -- STACK SIZE AND COUNT ARE REAL ARGUMENTS on 1.15, which the previous
    -- version did not believe: it apologised in a message for posting the
    -- whole stack because Classic Era "has no other posting API". It does.
    -- PostAuction takes the size of each stack and how many of them, and
    -- splits the bags itself - which is how aux posts five stacks of four
    -- from a stack of twenty in one click.
    local post = PostFn()
    Trace("post(" .. total .. ", " .. total .. ", " .. tostring(runTime)
        .. ", size " .. stackSize .. ", x" .. (stacks or 1)
        .. ") deposit " .. tostring(deposit)
        .. ", you own " .. NumOwnedAuctions() .. " auctions")
    -- SIX ARGUMENTS, NOT FIVE. The last one is the difference between an
    -- auction that goes up and an item that sits in your bags, and it is
    -- the argument I left off.
    --
    -- Classic Era's PostAuction ends with a confirmation flag. Without
    -- it the client does not post - it raises a dialog and waits to be
    -- told to go ahead. ZacUI was not only failing to pass it, it was
    -- then reaching over and hiding the very dialog that would have
    -- asked, so the post was cancelled by the code that was trying to
    -- tidy up after it. Passing true says "yes, go ahead", which is
    -- exactly what aux does and the only call shape known to work on
    -- this client.
    post(total, total, runTime, stackSize, stacks or 1, true)
    -- Ask for the owner list back, both to confirm this post and to fill
    -- the Cancel tab, which has no other source.
    RefreshOwned()
    return true, nil, sellName, sellCount
end

-- ============================================================
-- KNOWING WHETHER IT WORKED
-- ============================================================
-- THE CLIENT SAYS SO. It sends AUCTION_MULTISELL_UPDATE as each stack of
-- a multi-stack post goes up, AUCTION_MULTISELL_FAILURE if it gives up
-- part way, and BAG_UPDATE when the item finally leaves your bags. Those
-- three plus a timeout are the whole answer, and they are what aux uses.
--
-- What was here before asked the owner list "do you have more auctions
-- than you did a moment ago", which is a guess dressed as a measurement:
-- it needs a round trip that may not have happened yet, it cannot tell
-- your post from one that finished while you were reading, and when it
-- came up short it printed "check you can afford the deposit" - a
-- confident, specific, invented reason.
--
-- Nothing in here announces anything until the client has spoken.
local function FinishPost(ok, why)
    local p = AH.posting
    if not p then return end
    AH.posting = nil
    if ok then
        local n = p.stacks or 1
        Print("|cff66ff66posted|r " .. (p.name or "your item")
            .. (n > 1 and (" - " .. n .. " stacks") or "")
            .. ".")
        -- Now, and only now, refresh the list the Cancel tab reads.
        RefreshOwned()
        if AH.OnPosted then AH.OnPosted() end
    else
        Print("|cffff9900the auction did not go up|r - " .. (why or "no reason given")
            .. ". Your bags and your gold are untouched.")
    end
end

-- count/total arrive per stack while a multi-stack post is running.
local function OnMultisellUpdate(count, total)
    local p = AH.posting
    if not p then return end
    p.at = GetTime and GetTime() or 0
    if p.mode == "multi" and count and total and count == total then
        -- All stacks announced; the last one still has to leave the bags.
        p.mode = "single"
    end
end

local function OnMultisellFailure()
    if AH.posting then
        FinishPost(false, "the server stopped part way through the stacks")
    end
end

-- The item leaving your bags is the last thing to happen and the only
-- unambiguous evidence that it did.
local function OnBagUpdate()
    local p = AH.posting
    if p and p.mode == "single" then FinishPost(true) end
end

-- Nothing at all came back. Five seconds is aux's number.
local function PostTick()
    local p = AH.posting
    if not p then return end
    local now = GetTime and GetTime() or 0
    if now - (p.at or now) > 5 then
        FinishPost(false, "the server never answered")
    end
end

-- ============================================================
-- CANCELLING
-- ============================================================
-- PROTECTED, AND ONE PER CLICK. CancelAuction is in the same family as
-- PlaceAuctionBid: the client will only run it while it is crediting a
-- button press, and it credits one press to one call. A loop that
-- cancels five auctions from a single click gets the first one and
-- ADDON_ACTION_BLOCKED for the rest - or, if anything at all happens
-- between the click and the call, nothing at all.
--
-- So this cancels exactly one and says so, and the caller asks the
-- player to press again. That is the same shape the buy window ended up
-- with, for the same reason, and it is worth stating plainly: on this
-- client, anything that spends or destroys is one action per click.
local function CancelAuction(index)
    -- `if not CancelAuction` was the guard here, inside the function of
    -- that name - so it tested itself, was never false, and checked
    -- nothing at all. The global is what needs testing.
    if type(_G.CancelAuction) ~= "function" then
        return false, "this client has no CancelAuction"
    end
    if not index then return false, "no auction chosen" end
    _G.CancelAuction(index)
    return true
end

local function Age(at)
    if not at or at == 0 then return "never" end
    local secs = (time and time() or 0) - at
    if secs < 3600 then return math.max(1, math.floor(secs / 60)) .. "m ago" end
    if secs < 86400 then return math.floor(secs / 3600) .. "h ago" end
    return math.floor(secs / 86400) .. "d ago"
end

-- shared with later ZacUI files
AH.Age = Age
AH.BrowseEntry = BrowseEntry
AH.CanQuery = CanQuery
AH.CancelAuction = CancelAuction
AH.ClearQueue = ClearQueue
AH.Count = Count
AH.GOUGE_BAD = GOUGE_BAD
AH.GOUGE_WARN = GOUGE_WARN
AH.Group = Group
AH.Harvest = Harvest
AH.BeginPurchase = BeginPurchase
AH.BuyNext = BuyNext
AH.CancelPurchase = CancelPurchase
AH.PurchaseState = PurchaseState
AH.MAX_BULK_LISTINGS = MAX_BULK_LISTINGS
AH.PlanPurchase = PlanPurchase
AH.PriceRating = PriceRating
AH.LastSeen = LastSeen
AH.NumBrowseResults = NumBrowseResults
AH.OnMultisellUpdate = OnMultisellUpdate
AH.OnMultisellFailure = OnMultisellFailure
AH.OnBagUpdate = OnBagUpdate
AH.PostTick = PostTick
AH.FinishPost = FinishPost
AH.NumOwnedAuctions = NumOwnedAuctions
AH.RefreshOwned = RefreshOwned
AH.OwnedEntry = OwnedEntry
AH.PostAuction = PostAuction
AH.Prune = Prune
AH.Queue = Queue
AH.LowestNow = LowestNow
AH.OnListUpdate = OnListUpdate
AH.OnSystemMessage = OnSystemMessage
AH.OnMoneyChanged = OnMoneyChanged
AH.PurchaseInProgress = PurchaseInProgress
AH.QueryDone = QueryDone
AH.Search = Search
AH.Store = Store
AH.Suggest = Suggest

ns.AH = AH
