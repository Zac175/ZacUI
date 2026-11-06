-- Bags_Sort - client-side bag sorting.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHY THIS EXISTS. There is no sort API on Classic Era. C_Container.SortBags
-- and the old global SortBags are later-expansion additions; on 1.15 they
-- are simply absent, which is why the Sort button could only ever report
-- "this client has no sort API". Every bag addon on this client implements
-- sorting itself by picking items up and putting them down, and so does
-- this.
--
-- THE SHAPE OF THE PROBLEM. Moving an item is not synchronous. You pick it
-- up, you drop it, and the server confirms some time later - during which
-- the slot is LOCKED and reads as in-flight. So a sort cannot be a loop.
-- It is a state machine that does ONE move per tick, re-reads the bags
-- every time, and stops when the arrangement already matches the target.
-- That also makes it naturally resilient: if a move fails, the next tick
-- simply sees the old state and tries again.
--
-- TWO PASSES, in this order:
--   1. COMBINE partial stacks, because merging frees slots and changes
--      what the ordering pass has to place.
--   2. ORDER what remains, by category then quality then name.
--
-- Safety: never in combat, never while the cursor holds something, and a
-- hard iteration cap so a pathological case stops rather than spinning.

local ADDON_NAME = ...
-- Zacui_Bags is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Bags = ns.Bags
local Print = ns.Print

-- THROUGHPUT. The first version did ONE move per 0.1s tick, which for a
-- full bag is well over a minute of watching items shuffle. That was far
-- more conservative than the client requires.
--
-- The actual constraint is per-SLOT, not global: once you move an item,
-- its source and destination are locked until the server confirms, and
-- any further move touching those slots fails. Moves involving OTHER
-- slots are perfectly fine in the same frame. So each tick now performs
-- as many moves as it can find whose slots are all untouched and
-- unlocked, which typically drains a messy bag in a handful of ticks
-- instead of a hundred.
local MAX_TICKS = 200
local MOVES_PER_TICK = 12
local TICK = 0.05

local running, cancelled

-- ============================================================
-- ITEM ORDERING
-- ============================================================
-- Category rank first, so a sorted bag groups things the way a person
-- thinks about them rather than the way the item database happens to sort.
local CATEGORY_RANK = {
    ["Weapon"] = 1, ["Armor"] = 2, ["Container"] = 3, ["Consumable"] = 4,
    ["Trade Goods"] = 5, ["Reagent"] = 6, ["Projectile"] = 7, ["Quiver"] = 8,
    ["Recipe"] = 9, ["Quest"] = 10, ["Key"] = 11, ["Miscellaneous"] = 12,
}

local function ItemSortInfo(item)
    local name, itemType, subType, stackMax = nil, nil, nil, 1
    if item.link and GetItemInfo then
        local n, _, _, _, _, t, s, stack = GetItemInfo(item.link)
        name, itemType, subType, stackMax = n, t, s, stack
    end
    name = name or (item.link and item.link:match("%[(.-)%]")) or ""
    return {
        rank = CATEGORY_RANK[itemType or ""] or 99,
        subType = subType or "",
        quality = item.quality or 0,
        name = name,
        stackMax = stackMax or 1,
        count = item.count or 1,
        itemID = item.itemID,
    }
end

-- Deterministic and total: any two different items must order consistently,
-- or the sort oscillates forever swapping them past each other.
local function Compare(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.subType ~= b.subType then return a.subType < b.subType end
    if a.quality ~= b.quality then return a.quality > b.quality end
    if a.name ~= b.name then return a.name < b.name end
    if a.count ~= b.count then return a.count > b.count end
    return (a.itemID or 0) < (b.itemID or 0)
end

-- ============================================================
-- SNAPSHOT
-- ============================================================
local function Slots(bagList)
    local out = {}
    for _, bag in ipairs(bagList) do
        local n = Bags.NumSlots(bag)
        for slot = 1, n do
            local item = Bags.ItemInfo(bag, slot)
            out[#out + 1] = {
                bag = bag, slot = slot, item = item,
                info = item and ItemSortInfo(item) or nil,
                locked = item and item.locked or false,
                -- Enumeration position. Used as the final tiebreak when
                -- ordering, so items that compare equal never trade places.
                order = #out + 1,
            }
        end
    end
    return out
end

local function AnyLocked(slots)
    for _, s in ipairs(slots) do
        if s.locked then return true end
    end
    return false
end

-- ============================================================
-- MOVES
-- ============================================================
-- Bags_Core owns the one C_Container/global spelling of the pickup.
-- (The sorter reads the bags raw rather than through the shared item
-- cache: it acts on lock state a twentieth of a second after its own
-- moves, and must see the client's answer, not the last event's.)
local Pickup = Bags.Pickup

-- A slot key, so a batch can remember which slots it has already touched
-- this tick and never issue a second move against one.
local function Key(s) return s.bag .. ":" .. s.slot end

-- COMBINE, batched. Returns how many merges it issued.
--
-- Picking a whole stack up and dropping it on another stack of the same
-- item merges as much as fits and leaves the remainder ON THE CURSOR. The
-- third call puts that remainder back where it came from - without it, the
-- next tick starts with a full cursor and every subsequent move fails.
local function CombineBatch(slots, budget)
    local byItem = {}
    for _, s in ipairs(slots) do
        if s.item and s.info and s.info.stackMax > 1
            and s.info.count < s.info.stackMax and not s.locked then
            local list = byItem[s.item.itemID]
            if not list then
                list = {}
                byItem[s.item.itemID] = list
            end
            list[#list + 1] = s
        end
    end

    local used, done = {}, 0
    for _, list in pairs(byItem) do
        -- Smallest into largest: fewest moves, and it empties a slot as
        -- early as possible.
        table.sort(list, function(a, b) return a.info.count < b.info.count end)
        local lo, hi = 1, #list
        while lo < hi and done < budget do
            local src, dst = list[lo], list[hi]
            if used[Key(src)] or used[Key(dst)] then
                break
            end
            used[Key(src)], used[Key(dst)] = true, true
            Pickup(src.bag, src.slot)
            Pickup(dst.bag, dst.slot)
            Pickup(src.bag, src.slot)   -- put any remainder back
            if ClearCursor then ClearCursor() end
            done = done + 1
            lo, hi = lo + 1, hi - 1
        end
        if done >= budget then break end
    end
    return done
end

-- ORDER, batched. Selection sort, but issuing every independent swap it
-- can find in one pass rather than one and then waiting a tick.
--
-- TWO THINGS GO WRONG WITH DUPLICATE ITEMS, and both look like the sort
-- refusing to settle:
--
--  1. Compare() is only a total order over DIFFERENT items. Two stacks of
--     the same item with the same count compare equal, and table.sort is
--     not stable, so their relative order came out differently on every
--     tick. Each tick then "corrected" an arrangement the previous tick
--     had just made, forever. The fix is the positional tiebreak below:
--     among equal items, the one already earlier in the bags wins, so an
--     arrangement that is sorted reads as sorted and nothing moves.
--
--  2. A swap is pick up A, drop it on B. If B holds the SAME item and is
--     a partial stack, the drop MERGES instead of swapping and the
--     leftovers stay on the cursor. Counts then change underneath a
--     comparison that sorts by count, which reshuffles the order and
--     starts the churn again. So two slots holding the same item are
--     never swapped - they are interchangeable on screen anyway.
local function OrderBatch(slots, budget)
    -- Target: every occupied slot's contents, in sorted order, packed to
    -- the front. Empty slots fall to the end for free.
    local filled = {}
    for _, s in ipairs(slots) do
        if s.item then filled[#filled + 1] = s end
    end
    table.sort(filled, function(a, b)
        if Compare(a.info, b.info) then return true end
        if Compare(b.info, a.info) then return false end
        return a.order < b.order
    end)

    local used, done = {}, 0
    for i, want in ipairs(filled) do
        if done >= budget then break end
        local target = slots[i]
        if target and (target.bag ~= want.bag or target.slot ~= want.slot) then
            local sameItem = target.item and want.item
                and target.item.itemID and want.item.itemID
                and target.item.itemID == want.item.itemID

            if sameItem then
                -- Already the right item in this slot. Claim it so nothing
                -- else in this batch targets it, and leave it alone.
                used[Key(target)] = true
            -- Skip anything whose slots are mid-flight or already moved
            -- in this batch; the next tick sees the settled state and
            -- picks it up then.
            elseif not (used[Key(want)] or used[Key(target)]
                    or want.locked or target.locked) then
                used[Key(want)], used[Key(target)] = true, true
                Pickup(want.bag, want.slot)
                Pickup(target.bag, target.slot)
                if ClearCursor then ClearCursor() end
                done = done + 1
            end
        end
    end
    return done
end

-- ============================================================
-- THE RUN
-- ============================================================
local function Stop(message)
    running = false
    cancelled = nil
    if ClearCursor then ClearCursor() end
    if message then Print(message) end
    if ns.BagViews then
        for _, view in pairs(ns.BagViews) do
            if view.Refresh then pcall(view.Refresh, view) end
        end
    end
end

local function Sort(bagList, label)
    if running then
        Print("already sorting - wait for it to finish.")
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        Print("not while you are in combat.")
        return false
    end
    if GetCursorInfo and GetCursorInfo() then
        Print("put down whatever is on your cursor first.")
        return false
    end

    running = true
    local ticks, moves = 0, 0
    local combining = true

    local ticker
    ticker = C_Timer.NewTicker(TICK, function()
        if cancelled then
            ticker:Cancel()
            Stop("sort cancelled.")
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            ticker:Cancel()
            Stop("sort stopped - you entered combat.")
            return
        end

        ticks = ticks + 1
        if ticks > MAX_TICKS then
            ticker:Cancel()
            Stop("sort stopped - something is not settling. Your bags are "
                .. "safe, just not finished.")
            return
        end

        local slots = Slots(bagList)

        -- NOT "wait until nothing is locked". A single item still in
        -- flight used to stall the entire pass; now locked slots are
        -- simply skipped by the batchers and picked up next tick.
        if combining then
            local n = CombineBatch(slots, MOVES_PER_TICK)
            moves = moves + n
            if n > 0 then return end
            -- Nothing left to merge, but only believe that once the bags
            -- have settled - a mid-flight merge can look like nothing to do.
            if AnyLocked(slots) then return end
            combining = false
            return
        end

        local n = OrderBatch(slots, MOVES_PER_TICK)
        moves = moves + n
        if n > 0 then return end
        if AnyLocked(slots) then return end

        ticker:Cancel()
        Stop((label or "Bags") .. " sorted (" .. moves .. " moves in "
            .. ticks .. " passes).")
    end)
    return true
end

local function Cancel()
    if running then cancelled = true end
end

local function IsRunning() return running and true or false end

-- shared with later ZacUI files
ns.BagSort = {
    Cancel = Cancel,
    Compare = Compare,
    IsRunning = IsRunning,
    ItemSortInfo = ItemSortInfo,
    Sort = Sort,
}
