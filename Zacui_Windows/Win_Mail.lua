-- Win_Mail - ZacUI's inbox: every mail in one searchable, filterable
-- list, with a throttled "collect all" instead of Blizzard's seven-per-
-- page grid.
-- Part of ZacUI; load order is set by the TOC.
--
-- Built on Win_Kit's cover, parented to InboxFrame (the Inbox PAGE, not
-- MailFrame) and laid over MailFrame's rectangle. So it shows on the
-- Inbox tab only: MailFrame's own Inbox / Send Mail tabs hang below the
-- window untouched, and the Send Mail page stays Blizzard's (skinned).
-- The X hides MailFrame through HideUIPanel, and MailFrame's OnHide is
-- what calls CloseMail - the session ends exactly as Blizzard intends.
--
-- Reading, replying, deleting and returning stay on Blizzard's own
-- OpenMailFrame (skinned). It is a UIParent window anchored to
-- InboxFrame's top-right corner, which is past MailFrame's right edge,
-- so it opens BESIDE the cover and never under it.
--
--   Left-click          open the mail (Blizzard's InboxFrame_OnClick)
--   Shift-left-click    Blizzard's auto-loot click (MAILAUTOLOOTTOGGLE)
--   Right-click         take the money and items from that mail only
--   Collect all         the same for every mail, one take at a time
--
-- Nothing here ever pays a C.O.D.: those mails are skipped by both
-- collectors, and paying stays on OpenMailFrame's own confirmation.

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

local TEX_MAIL = "Interface\\Icons\\INV_Letter_15"

local win, list, search, chipMoney, chipItems, chipCOD
local moneyText, statusText, collectBtn, stopBtn
local query = ""
local collectable = 0          -- takes the collector could make right now
local Collect                  -- the collector, defined below
local Leftovers                -- Blizzard pieces to silence, defined below

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.mailwin ~= false
end

local function AttachMax()
    return ATTACHMENTS_MAX_RECEIVE or 16
end

-- ============================================================
-- DATA
-- ============================================================
-- One entry per mail the server has sent the client. GetInboxNumItems
-- returns (shown, total): past 50 the server holds the rest back until
-- some are taken, which is why the title can say "50 of 73".
local function ItemQuality(itemID)
    if not itemID then return nil end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    return (select(3, getInfo(itemID)))
end

local function Entry(i)
    -- Era return order, as InboxFrame_Update / OpenMail_Update read it.
    local packageIcon, stationeryIcon, sender, subject, money, cod, daysLeft,
        itemCount, wasRead, wasReturned, textCreated, canReply, isGM,
        firstQty, firstID = GetInboxHeaderInfo(i)
    local e = {
        index = i,
        icon = ((packageIcon and not isGM) and packageIcon) or stationeryIcon,
        stationery = stationeryIcon,
        sender = sender or (UNKNOWN or "Unknown"),
        subject = subject or "",
        money = money or 0, cod = cod or 0,
        daysLeft = daysLeft or 0,
        itemCount = itemCount or 0,
        read = wasRead and true or false,
        isGM = isGM and true or false,
        firstQty = firstQty, firstID = firstID,
        items = {},
    }
    if e.itemCount > 0 then
        for a = 1, AttachMax() do
            if HasInboxItem(i, a) then
                local name, itemID, tex, count, quality = GetInboxItem(i, a)
                e.items[#e.items + 1] = {
                    slot = a, name = name, id = itemID, icon = tex,
                    count = count or 1, quality = quality,
                }
            end
        end
    end
    local names = {}
    for _, it in ipairs(e.items) do
        if it.name then names[#names + 1] = it.name end
    end
    e.itemNames = table.concat(names, "\n")
    e.quality = (e.items[1] and e.items[1].quality) or ItemQuality(firstID)
    -- What the collectors may take: never a C.O.D., never a GM letter
    -- (Blizzard's Open All skips those too).
    e.takeable = (not e.isGM) and e.cod <= 0
    return e
end

local function Rows()
    local data = {}
    local shown, total = GetInboxNumItems()
    shown, total = shown or 0, total or 0
    local wantMoney = chipMoney and chipMoney:IsOn()
    local wantItems = chipItems and chipItems:IsOn()
    local wantCOD = chipCOD and chipCOD:IsOn()
    collectable = 0
    for i = 1, shown do
        local e = Entry(i)
        if e.takeable then
            collectable = collectable + (e.money > 0 and 1 or 0) + #e.items
        end
        if Kit.Matches(query, e.sender, e.subject, e.itemNames)
            and (not wantMoney or e.money > 0)
            and (not wantItems or e.itemCount > 0)
            and (not wantCOD or e.cod > 0) then
            data[#data + 1] = e
        end
    end
    return data, shown, total
end

-- ============================================================
-- REFRESH
-- ============================================================
local function OpenIndex()
    if OpenMailFrame and OpenMailFrame:IsShown() and InboxFrame then
        return InboxFrame.openMailID
    end
    return nil
end

local function UpdateFooter()
    moneyText:SetText(ns.Money(GetMoney()))
    local running = Collect.running
    collectBtn:SetShown(not running)
    stopBtn:SetShown(running)
    collectBtn:SetDisabled(collectable == 0)
    if not running then
        -- The run's last word keeps its colour (a red "bags are full")
        -- through the redraws that follow it.
        local key
        if Collect.message then
            statusText:SetText(Collect.message)
            key = Collect.messageKey
        elseif collectable > 0 then
            statusText:SetText(collectable .. " to collect")
        else
            statusText:SetText("")
        end
        if key then statusText:SetTextColor(Kit.TextRGB(key)) else statusText:_zPaint() end
    end
end

local function Refresh(keepOffset)
    -- IsVisible, not IsShown: the cover is a shown child of InboxFrame
    -- all session, so IsShown is true with no mailbox open at all.
    if not win or not win:IsVisible() then return end
    local data, shown, total = Rows()
    local open = OpenIndex()
    local selected
    for _, e in ipairs(data) do
        if open and e.index == open then selected = e end
    end
    list.selected = selected
    list:SetEmptyText(shown == 0 and (INBOX_EMPTY or "Your inbox is empty.") or "Nothing matches.")
    list:SetData(data, keepOffset)
    local title = INBOX or "Inbox"
    if total > shown then
        win:SetTitle(title .. "  (" .. shown .. " of " .. total .. ")")
    else
        win:SetTitle(title .. "  (" .. shown .. ")")
    end
    UpdateFooter()
end

-- Bag, money and item-info events all session long: nothing is even
-- scheduled unless the inbox page is on screen.
local Queue = Kit.Coalesce(Refresh, function() return win end, true)

-- ============================================================
-- COLLECTOR
-- ============================================================
-- One take (the money, or one attachment) per step. A step waits for the
-- inbox to report the take landed (MAIL_INBOX_UPDATE / MAIL_SUCCESS),
-- then a short C_Timer gap, then looks again from scratch - indices move
-- when an emptied mail is deleted, so nothing is remembered between
-- steps except which items the server refused. No OnUpdate, no loop.
local STEP_DELAY = 0.4       -- gap between takes; the server throttles faster
local STEP_TIMEOUT = 2.0     -- no answer in this long: look again anyway
local STUCK_AFTER = 2.5      -- same attachment still there: give up on it
local PENDING_MAX = 10       -- a mail command that never finishes: give up

Collect = { running = false, token = 0 }

-- What one mail looks like right now. Two auction mails for the same
-- item share a sender, subject and item ID, and when the first one is
-- emptied and deleted the second slides into its index - so "same index,
-- same slot, same item" alone cannot tell "the take has not landed yet"
-- from "that was the next mail". The inbox count, the mail's own money /
-- item count and the inbox totals can: a deleted mail always drops the
-- server-side total by one, even when a held-back mail refills the list.
local function MailSignature(i)
    local shown, total = GetInboxNumItems()
    local _, _, sender, subject, money, cod, _, itemCount = GetInboxHeaderInfo(i)
    return tostring(shown) .. "|" .. tostring(total) .. "|" .. tostring(sender) .. "|"
        .. tostring(subject) .. "|" .. tostring(money) .. "|" .. tostring(cod) .. "|"
        .. tostring(itemCount)
end

-- Far more takes than 50 mails x 16 attachments + money could need: a
-- last-ditch stop so no combination of server replies can run forever.
local MAX_TAKES = 1000

local function GeneralFreeSlots()
    local free = 0
    local getFree = C_Container and C_Container.GetContainerNumFreeSlots
    if not getFree then return 1 end        -- unknown: let the server decide
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n, family = getFree(bag)
        -- Family 0 is an ordinary bag; a quiver or soul bag only takes
        -- its own kind, so it does not count as room for a mailed sword.
        if n and (family == nil or family == 0) then free = free + n end
    end
    return free
end

-- Room for more of an item on stacks of it already in the bags (for when
-- there is no free slot: a mailed stack that fits on them still goes in).
-- nil when the item's stack size is not known yet - let the server decide.
-- Read through the bag window's shared item cache when ZacUI's bag part
-- is loaded (one read per bag change, shared with the bag window and the
-- auction sell list); straight from the client otherwise.
local function StackRoom(itemID)
    local Bags = ns.Bags
    local getInfo = C_Container and C_Container.GetContainerItemInfo
    local getSlots = C_Container and C_Container.GetContainerNumSlots
    if not (itemID and (Bags or (getInfo and getSlots))) then return nil end
    local itemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local maxStack = select(8, itemInfo(itemID))
    if not maxStack then return nil end
    if maxStack <= 1 then return 0 end
    local room = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n = Bags and Bags.Slots(bag) or getSlots(bag) or 0
        for slot = 1, n do
            local id, count
            if Bags then
                local item = Bags.Item(bag, slot)
                id, count = item and item.itemID, item and item.count
            else
                local info = getInfo(bag, slot)
                id, count = info and info.itemID, info and info.stackCount
            end
            if id == itemID and (count or 0) < maxStack then
                room = room + maxStack - (count or 0)
            end
        end
    end
    return room
end

-- Single-mail runs follow the mail by who sent it and what it is called,
-- so an earlier mail being deleted mid-run cannot redirect the take.
local function FindSingle()
    local s = Collect.single
    local n = GetInboxNumItems() or 0
    if s.index <= n then
        local _, _, sender, subject = GetInboxHeaderInfo(s.index)
        if sender == s.sender and subject == s.subject then return s.index end
    end
    for i = 1, n do
        local _, _, sender, subject = GetInboxHeaderInfo(i)
        if sender == s.sender and subject == s.subject then
            s.index = i
            return i
        end
    end
    return nil
end

-- The next take, or nil plus how many attachments were passed over for
-- want of bag room (bags full and no stack of the same item to go on).
-- Money is always taken - it needs no room.
local function NextTake()
    local first, last = 1, GetInboxNumItems() or 0
    local free, noRoom = nil, 0
    if Collect.single then
        -- A right-click takes what THAT mail held and no more: once the
        -- mail empties (and is deleted) the next one down may carry the
        -- same sender and subject - another auction mail - and must be
        -- left alone.
        if (Collect.single.left or 0) <= 0 then return nil end
        local i = FindSingle()
        if not i then return nil end
        first, last = i, i
    end
    for i = first, last do
        local _, _, sender, subject, money, cod, _, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(i)
        if not isGM and (cod or 0) <= 0 then
            local mkey = "money:" .. i .. ":" .. tostring(sender) .. ":" .. tostring(subject)
            if (money or 0) > 0 and not Collect.skip[mkey] then return i, 0, mkey end
            if (itemCount or 0) > 0 then
                for a = 1, AttachMax() do
                    if HasInboxItem(i, a) then
                        local _, itemID, _, count = GetInboxItem(i, a)
                        local key = itemID or ("slot" .. i .. ":" .. a)
                        if not Collect.skip[key] then
                            free = free or GeneralFreeSlots()
                            if free > 0 then return i, a, key end
                            local room = StackRoom(itemID)
                            if room == nil or room >= (count or 1) then return i, a, key end
                            noRoom = noRoom + 1
                        end
                    end
                end
            end
        end
    end
    return nil, noRoom
end

local function SetStatus(text, key)
    if not statusText then return end
    statusText:SetText(text or "")
    if key then statusText:SetTextColor(Kit.TextRGB(key)) else statusText:_zPaint() end
end

function Collect.Stop(message, key)
    local wasRunning = Collect.running
    Collect.running = false
    Collect.waiting = false
    Collect.token = Collect.token + 1
    Collect.single = nil
    Collect.pendingSince = nil
    Collect.message, Collect.messageKey = message, key
    if win then UpdateFooter() end
    -- Past fifty mails the server only sends more once some are gone;
    -- ask for the next batch the way Blizzard's MAIL_SUCCESS handler does.
    if wasRunning and MailFrame and MailFrame:IsShown() then
        local shown, total = GetInboxNumItems()
        if total and shown and total > shown and CheckInbox then CheckInbox() end
    end
end

local function Schedule(delay)
    local my = Collect.token
    C_Timer.After(delay, function()
        if Collect.running and Collect.token == my then Collect.Step() end
    end)
end

function Collect.Step()
    if not Collect.running then return end
    if not (MailFrame and MailFrame:IsShown()) then
        Collect.Stop(nil)
        return
    end
    -- The client queues one mail command at a time; asking again while
    -- one is in flight is how a take gets silently dropped.
    if C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending() then
        -- ...but not for ever: a command the server never answers ends
        -- the run instead of polling while the mailbox stays open.
        Collect.pendingSince = Collect.pendingSince or GetTime()
        if GetTime() - Collect.pendingSince > PENDING_MAX then
            Collect.Stop("Stopped: the mailbox stopped answering.", "red")
            return
        end
        Schedule(0.3)
        return
    end
    Collect.pendingSince = nil
    if Collect.taken >= MAX_TAKES then
        Collect.Stop("Stopped.")
        return
    end
    local i, a, key, noRoom = NextTake()
    if not i then
        local n = Collect.taken
        local took = n > 0 and ("Collected " .. n .. (n == 1 and " take" or " takes")) or "Nothing collected"
        if (noRoom or 0) > 0 or (Collect.noRoom or 0) > 0 then
            -- what is left does not fit: bags full, no stack to go on
            Collect.Stop(took .. " - the rest won't fit in your bags.", "red")
        else
            Collect.Stop(n > 0 and (took .. ".") or "Nothing to collect.")
        end
        return
    end
    -- The inbox has not caught up with the last take yet (the same mail,
    -- slot and item, and the mail unchanged): wait, and if it is STILL
    -- like that after a while, the server has quietly refused it - skip
    -- it rather than ask forever. A changed signature means the take
    -- landed and this is the next mail that slid into the same index.
    local last = Collect.last
    if last and last.i == i and last.a == a and last.key == key
        and last.sig == MailSignature(i) then
        if GetTime() - last.t < STUCK_AFTER then
            Schedule(0.3)
            return
        end
        if key then Collect.skip[key] = true end
        Collect.last = nil
        Schedule(0.1)
        return
    end
    Collect.token = Collect.token + 1
    Collect.waiting = true
    Collect.last = { i = i, a = a, key = key, t = GetTime(), sig = MailSignature(i) }
    if a == 0 then
        TakeInboxMoney(i)
    else
        TakeInboxItem(i, a)
    end
    Collect.taken = Collect.taken + 1
    if Collect.single then Collect.single.left = (Collect.single.left or 0) - 1 end
    SetStatus("Collecting... " .. Collect.taken .. " taken")
    -- No answer at all (a take that changes nothing we listen for):
    -- look again anyway rather than hang.
    local my = Collect.token
    C_Timer.After(STEP_TIMEOUT, function()
        if Collect.running and Collect.waiting and Collect.token == my then
            Collect.waiting = false
            Collect.Step()
        end
    end)
end

-- index = nil collects everything; an index collects that one mail.
function Collect.Start(index)
    if Collect.running then return end
    if index then
        local _, _, sender, subject, money, cod, _, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(index)
        if not sender and not subject then return end
        if (cod or 0) > 0 then
            -- Never here: C.O.D. is paid on the open letter, through
            -- Blizzard's own confirmation.
            Collect.message, Collect.messageKey = "C.O.D. mail - open it to pay and take.", "orange"
            UpdateFooter()
            return
        end
        if isGM then return end
        -- The takes this one mail holds: its money, then each attachment.
        local left = ((money or 0) > 0) and 1 or 0
        if (itemCount or 0) > 0 then
            for a = 1, AttachMax() do
                if HasInboxItem(index, a) then left = left + 1 end
            end
        end
        Collect.single = { index = index, sender = sender, subject = subject, left = left }
    else
        Collect.single = nil
    end
    Collect.running = true
    Collect.waiting = false
    Collect.taken = 0
    Collect.failures = 0
    Collect.skip = {}
    Collect.last = nil
    Collect.noRoom, Collect.fullAt = 0, nil
    Collect.message, Collect.messageKey = nil, nil
    UpdateFooter()
    Collect.Step()
end

-- The answer to a take: carry on after the throttle gap.
local function TakeAnswered()
    if Collect.running and Collect.waiting then
        Collect.waiting = false
        Schedule(STEP_DELAY)
    end
end

-- "Inventory is full" for the last take: that item (and more of it) is
-- left for this run and the run goes on with the rest - money and what
-- still fits. The same refusal can come as MAIL_FAILED too; once is enough.
function Collect.NoRoom()
    if not Collect.running then return end
    if Collect.fullAt and GetTime() - Collect.fullAt < 0.5 then return end
    Collect.fullAt = GetTime()
    local last = Collect.last
    if last and last.a > 0 and last.key then Collect.skip[last.key] = true end
    Collect.noRoom = (Collect.noRoom or 0) + 1
    Collect.last = nil
    if Collect.waiting then
        Collect.waiting = false
        Schedule(STEP_DELAY)
    end
end

local function TakeFailed(itemID)
    if not Collect.running then return end
    -- a refusal for want of room is not the mailbox misbehaving
    if Collect.fullAt and GetTime() - Collect.fullAt < 0.5 then return end
    local last = Collect.last
    if last and last.a > 0 and GeneralFreeSlots() == 0 then
        Collect.NoRoom()
        return
    end
    Collect.failures = (Collect.failures or 0) + 1
    -- A refused ITEM (unique, or one the server will not hand over) is
    -- skipped for the rest of the run, as Blizzard's Open All does; a
    -- failure with no item, or a third one, ends the run.
    if itemID and Collect.failures < 3 then
        Collect.skip[itemID] = true
        Collect.waiting = false
        Schedule(STEP_DELAY)
    else
        Collect.Stop("Stopped: the mailbox refused a take.", "red")
    end
end

-- ============================================================
-- ROWS
-- ============================================================
local function DaysText(days)
    if days >= 1 then
        return string.format(DAYS_ABBR or "%d Days", math.floor(days)), "green"
    end
    local secs = math.floor(days * 24 * 60 * 60)
    if SecondsToTime then return SecondsToTime(secs), "red" end
    return math.floor(secs / 3600) .. " h", "red"
end

local function AddMoneyLine(amount, red)
    if GameTooltip_AddMoneyLine then
        GameTooltip_AddMoneyLine(GameTooltip, amount, red)
    else
        local k = red and "red" or "normal"
        GameTooltip:AddLine(ns.Money(amount), Kit.TextRGB(k))
    end
end

local function RowTooltip(row)
    local e = row.item
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if #e.items == 1 then
        -- One attachment: its real item tooltip, as Blizzard shows it.
        GameTooltip:SetInboxItem(e.index, e.items[1].slot)
    else
        local tc = GetColor("tooltip", "title")
        GameTooltip:AddLine(e.sender, tc.r, tc.g, tc.b)
        if e.subject ~= "" then
            local bc = GetColor("tooltip", "body")
            GameTooltip:AddLine(e.subject, bc.r, bc.g, bc.b, true)
        end
        if #e.items > 1 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine((MAIL_MULTIPLE_ITEMS or "Multiple items") .. " (" .. #e.items .. ")",
                Kit.TextRGB("gray"))
            for _, it in ipairs(e.items) do
                local r, g, b = ns.QualityRGB(it.quality)
                local line = "|T" .. (it.icon or "Interface\\Icons\\INV_Misc_QuestionMark") .. ":14:14:0:0|t "
                    .. (it.name or (UNKNOWN or "Unknown"))
                if (it.count or 1) > 1 then line = line .. " x" .. it.count end
                GameTooltip:AddLine(line, r, g, b)
            end
        end
    end
    if e.money > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ENCLOSED_MONEY or "Enclosed money", nil, nil, nil, true)
        AddMoneyLine(e.money)
    elseif e.cod > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(COD_AMOUNT or "C.O.D. amount", nil, nil, nil, true)
        AddMoneyLine(e.cod, e.cod > GetMoney())
    end
    local canDelete = InboxItemCanDelete and InboxItemCanDelete(e.index)
    local days, dkey = DaysText(e.daysLeft)
    local lr, lg, lb = Kit.TextRGB("gray")
    local rr, rg, rb = Kit.TextRGB(dkey)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(canDelete and (TIME_UNTIL_DELETED or "Deleted in")
        or (TIME_UNTIL_RETURNED or "Returned in"), days, lr, lg, lb, rr, rg, rb)
    if e.takeable and (e.money > 0 or #e.items > 0) then
        GameTooltip:AddLine("Right-click to take everything", Kit.TextRGB("gray"))
    end
    GameTooltip:Show()
end

-- What InboxFrame_OnClick reads off its CheckButton: :GetChecked(). A
-- click on the letter that is already open un-checks it (closes it),
-- exactly like Blizzard's toggle.
local function ClickProxy(index)
    local checked = not (OpenIndex() == index)
    return { GetChecked = function() return checked end }
end

local function BuildRow(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local rh = Kit.ROW_H

    row.icon = Kit.Icon(row, rh - 4)
    row.icon:SetPoint("LEFT", 3, 0)

    -- Right column: time left on top, money / attachment count below.
    -- Explicit TOPRIGHT / BOTTOMRIGHT points, so the two can never meet.
    row.days = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.days:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    row.days:SetWordWrap(false)

    row.money = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.money:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 4)
    row.money:SetWordWrap(false)

    -- Left column, each line capped by its own right-column neighbour.
    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, -2)
    row.nameText:SetPoint("TOPRIGHT", row.days, "TOPLEFT", -6, 0)
    row.nameText:SetWordWrap(false)

    row.sub = UI.Font(row, F.SMALL, { justify = "LEFT" })
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, 2)
    row.sub:SetPoint("BOTTOMRIGHT", row.money, "BOTTOMLEFT", -6, 0)
    row.sub:SetWordWrap(false)

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
        -- A red C.O.D. line recolours the shared money frame; put it back
        -- the way Blizzard's own inbox button does on leave.
        if SetMoneyFrameColor and _G.GameTooltipMoneyFrame1 then
            SetMoneyFrameColor("GameTooltipMoneyFrame1", "white")
        end
    end)

    row:SetScript("OnClick", function(self, button)
        local e = self.item
        if not e then return end
        if button == "RightButton" then
            Collect.Start(e.index)
            return
        end
        if IsModifiedClick("MAILAUTOLOOTTOGGLE") and InboxFrame_OnModifiedClick then
            InboxFrame_OnModifiedClick(ClickProxy(e.index), e.index)
        elseif InboxFrame_OnClick then
            InboxFrame_OnClick(ClickProxy(e.index), e.index)
        end
        Queue()
    end)
end

local function UpdateRow(row, e)
    row.icon:SetIcon(e.icon)
    row.icon:SetCount(e.firstQty)
    row.icon:SetQuality(e.quality)
    row.icon:SetUsable(true)
    -- Read mail is dimmed and its icon greyed, as in Blizzard's inbox.
    row.icon:SetDesaturated(e.read)

    row.nameText:SetText(e.sender)
    row.nameText:SetTextColor(Kit.TextRGB(e.read and "gray" or "normal"))
    row.sub:SetText(e.subject)
    row.sub:SetTextColor(Kit.TextRGB(e.read and "gray" or "normal"))

    local days, key = DaysText(e.daysLeft)
    row.days:SetText(days)
    row.days:SetTextColor(Kit.TextRGB(key))

    local bits = {}
    if e.itemCount > 1 then bits[#bits + 1] = e.itemCount .. " items" end
    if e.cod > 0 then
        bits[#bits + 1] = "COD " .. ns.Money(e.cod)
    elseif e.money > 0 then
        bits[#bits + 1] = ns.Money(e.money)
    end
    row.money:SetText(table.concat(bits, "  "))
    if e.cod > 0 then
        row.money:SetTextColor(Kit.TextRGB(e.cod > GetMoney() and "red" or "orange"))
    else
        row.money:_zPaint()
    end

    -- The open letter is the selected row (Kit.List paints row.sel).
    row.sel:SetShown(OpenIndex() == e.index)
end

-- ============================================================
-- BUILD
-- ============================================================
local function Build()
    if win then return win end
    win = Kit.Cover(InboxFrame, {
        name = "ZacUIMailWindow",
        title = INBOX or "Inbox",
        insetName = "MailFrame",
        -- MailFrame carries secure buttons once ZacUI's tab strip is on,
        -- and an addon's HideUIPanel of it is refused in combat: ending the
        -- session instead lets Blizzard's MAIL_CLOSED handler hide it.
        onClose = function()
            if InCombatLockdown() and CloseMail then CloseMail() else HideUIPanel(MailFrame) end
        end,
    })
    -- Parented to InboxFrame (so it lives on the Inbox tab only) but laid
    -- over MailFrame's rectangle: InboxFrame is the old 384x512 art page
    -- and hangs past the 338x424 window on the right and bottom.
    win.Reanchor = function()
        ns.AnchorPanel(win, MailFrame, ns.GetPanelInset("MailFrame", MailFrame))
    end
    win.Reanchor()
    win:SetIcon(TEX_MAIL)

    -- Toolbar: search, then the three filter chips on the right.
    local y = win.top
    chipCOD = Kit.Chip(win, "COD", false, function() Refresh() end,
        "Only cash-on-delivery mail.")
    chipCOD:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y)
    chipItems = Kit.Chip(win, "Has items", false, function() Refresh() end,
        "Only mail with items attached.")
    chipItems:SetPoint("RIGHT", chipCOD, "LEFT", -4, 0)
    chipMoney = Kit.Chip(win, "Has money", false, function() Refresh() end,
        "Only mail with money enclosed.")
    chipMoney:SetPoint("RIGHT", chipItems, "LEFT", -4, 0)

    search = Kit.Search(win, 100, function(text)
        query = Kit.NormalizeQuery(text)
        Refresh()
    end, "Search mail")
    search:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
    search:SetPoint("RIGHT", chipMoney, "LEFT", -Kit.GAP, 0)

    -- Footer: your money, the collector's progress, collect / stop.
    win.footer = Kit.Footer(win, Kit.FOOTER_H + 4)
    moneyText = UI.Font(win.footer, F.LABEL, { justify = "LEFT" })
    moneyText:SetPoint("LEFT", 8, 0)
    moneyText:SetWordWrap(false)

    collectBtn = UI.Button(win.footer, "Collect all", { width = 86, height = 24 })
    collectBtn:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    collectBtn:SetScript("OnClick", function() Collect.Start(nil) end)
    UI.Tooltip(collectBtn, "Collect all",
        "Take the money and items from every mail, one at a time. C.O.D. mail is skipped. With your bags full it still takes the money and anything that stacks onto what you carry.")

    -- Same spot as Collect all: only one of the two is ever shown.
    stopBtn = UI.Button(win.footer, STOP or "Stop", { width = 86, height = 24 })
    stopBtn:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    stopBtn:SetScript("OnClick", function() Collect.Stop("Stopped.") end)
    stopBtn:Hide()

    statusText = UI.Font(win.footer, F.SMALL, { justify = "RIGHT", cat = "text", key = "gray" })
    statusText:SetPoint("LEFT", moneyText, "RIGHT", 10, 0)
    statusText:SetPoint("RIGHT", collectBtn, "LEFT", -8, 0)
    statusText:SetWordWrap(false)

    list = Kit.List(win, {
        rowHeight = Kit.ROW_H,
        build = BuildRow,
        update = UpdateRow,
    })
    list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y - Kit.SEARCH_H - Kit.GAP)
    list:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("MAIL_INBOX_UPDATE")
    ev:RegisterEvent("MAIL_SHOW")
    ev:RegisterEvent("MAIL_CLOSED")
    ev:RegisterEvent("UPDATE_PENDING_MAIL")
    ev:RegisterEvent("PLAYER_MONEY")
    ev:RegisterEvent("MAIL_SUCCESS")
    ev:RegisterEvent("MAIL_FAILED")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("UI_ERROR_MESSAGE")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    pcall(ev.RegisterEvent, ev, "CLOSE_INBOX_ITEM")
    ev:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "MAIL_CLOSED" then
            if Collect.running then Collect.Stop(nil) end
            return
        elseif event == "MAIL_FAILED" then
            TakeFailed(arg1)
        elseif event == "UI_ERROR_MESSAGE" then
            if Collect.running and ERR_INV_FULL and arg2 == ERR_INV_FULL then
                Collect.NoRoom()
            end
            return
        elseif event == "MAIL_SUCCESS" or event == "MAIL_INBOX_UPDATE" then
            TakeAnswered()
        end
        Queue()
    end)

    -- Opening / closing a letter on Blizzard's side moves the selection.
    if InboxFrame_Update then hooksecurefunc("InboxFrame_Update", Queue) end
    if OpenMailFrame then OpenMailFrame:HookScript("OnHide", Queue) end

    -- Silence follows the inbox PAGE: the cover shows and hides with
    -- InboxFrame, which is exactly the Inbox / Send Mail switch.
    win:HookScript("OnShow", function()
        Kit.Silence(Leftovers())
        query = ""
        search:SetText("")
        Collect.message, Collect.messageKey = nil, nil
        Refresh()
    end)
    -- The Send Mail tab or the mailbox closing: a run never outlives the
    -- page it was started from (Blizzard's Open All stops on hide too).
    win:HookScript("OnHide", function()
        if Collect.running then Collect.Stop(nil) end
        Kit.Unsilence(Leftovers())
    end)
    return win
end

-- Pieces of MailFrame the cover does not reach while the Inbox tab is
-- up: the portrait (frame level 400) and title container (510) sit above
-- any cover, the NineSlice corners and close button poke past its edges,
-- and InboxFrame's own page art and "too much mail" banner hang past
-- MailFrame's right edge. The bottom tabs are NOT here - they switch to
-- Send Mail and must keep working. Silenced only while the inbox page is
-- showing: the Send Mail page is Blizzard's and needs its frame back.
local leftovers
function Leftovers()
    if leftovers then return leftovers end
    local f = MailFrame
    -- Explicit appends, not a table literal: one of these missing on a
    -- build would leave a hole, and ipairs stops at the first hole.
    leftovers = {}
    local function Add(x) if x then leftovers[#leftovers + 1] = x end end
    Add(f.PortraitContainer)
    Add(_G.MailFramePortrait)
    Add(f.TitleContainer)
    Add(f.NineSlice)
    Add(f.CloseButton)
    Add(_G.MailFrameCloseButton)
    Add(_G.InboxTooMuchMail)
    for _, region in ipairs({ InboxFrame:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") then
            Add(region)
        end
    end
    -- The envelope icon: an unnamed 58x58 texture on MailFrame, anchored
    -- 5px left of and 7px above the corner.
    for _, region in ipairs({ f:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") then
            local w, h = region:GetSize()
            if w and h and math.abs(w - 58) < 1 and math.abs(h - 58) < 1 then
                Add(region)
            end
        end
    end
    -- Forever: whatever of the modern inbox page draws above the cover
    if win then Kit.AboveCover(InboxFrame, win, leftovers) end
    return leftovers
end

local function Apply()
    if not MailFrame or not InboxFrame then return end
    if Enabled() then
        Build()
        win.Reanchor()
        win:Show()
        if win:IsVisible() then
            Kit.Silence(Leftovers())
            Refresh()
        end
    elseif win then
        if Collect.running then Collect.Stop(nil) end
        win:Hide()
        Kit.Unsilence(Leftovers())
    end
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.mailwin = function()
    if not MailFrame or not InboxFrame or ns._zMailWin then return end
    ns._zMailWin = true
    Apply()
    -- A later /zui toggle only flips the saved flag; the window checks it
    -- on every open so turning it off never needs a reload.
    MailFrame:HookScript("OnShow", Apply)
end
