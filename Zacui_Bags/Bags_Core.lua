-- Bags_Core - the data layer under ZacUI's combined inventory: which bags
-- exist, what is in them, and when that changed.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHY A COMPAT LAYER. 1.15 backported retail's C_Container namespace, but
-- the old global functions still exist on some builds and the two do not
-- agree on shape: GetContainerItemInfo used to return seven values and now
-- returns one table with named fields. Every read in this addon goes
-- through the wrappers below so the rest of the bag code never has to know
-- which client it is on - and so that when one of them disappears, this is
-- the only file that changes.

local ADDON_NAME = ...
-- Zacui_Bags is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print

local C = _G.C_Container

-- ============================================================
-- BAG SETS
-- ============================================================
-- Backpack is 0; the four equipped bags are 1-4. The bank is bag -1
-- (the fixed 28 slots) plus the purchased bank bags, which are 5-11 on
-- this client. Held as data rather than as loops so the bank view and
-- the inventory view are the same code with a different list.
local BACKPACK_BAGS = { 0, 1, 2, 3, 4 }
local BANK_BAGS     = { -1, 5, 6, 7, 8, 9, 10, 11 }

local BANK_CONTAINER = _G.BANK_CONTAINER or -1
local NUM_BANKBAGSLOTS = _G.NUM_BANKBAGSLOTS or 7

-- ============================================================
-- API COMPAT
-- ============================================================
local function NumSlots(bag)
    if C and C.GetContainerNumSlots then return C.GetContainerNumSlots(bag) or 0 end
    if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
    return 0
end

-- ONE normalised item shape for the whole addon:
--   { icon, count, quality, link, locked, quest, questActive, noValue, itemID }
-- Returns nil for an empty slot, which is the only thing callers test.
local function ItemInfo(bag, slot)
    if C and C.GetContainerItemInfo then
        local info = C.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        return {
            icon    = info.iconFileID,
            count   = info.stackCount,
            quality = info.quality,
            link    = info.hyperlink,
            locked  = info.isLocked,
            noValue = info.hasNoValue,
            itemID  = info.itemID,
        }
    end
    if not GetContainerItemInfo then return nil end
    local icon, count, locked, quality, _, _, link, _, noValue, itemID =
        GetContainerItemInfo(bag, slot)
    if not icon then return nil end
    return {
        icon = icon, count = count, quality = quality, link = link,
        locked = locked, noValue = noValue, itemID = itemID,
    }
end

local function QuestInfo(bag, slot)
    if C and C.GetContainerItemQuestInfo then
        local q = C.GetContainerItemQuestInfo(bag, slot)
        if q then return q.isQuestItem, q.questID, q.isActive end
    elseif GetContainerItemQuestInfo then
        local isQuest, questID, isActive = GetContainerItemQuestInfo(bag, slot)
        return isQuest, questID, isActive
    end
    return false
end

local function Cooldown(bag, slot)
    if C and C.GetContainerItemCooldown then
        return C.GetContainerItemCooldown(bag, slot)
    end
    if GetContainerItemCooldown then return GetContainerItemCooldown(bag, slot) end
    return 0, 0, 0
end

-- ============================================================
-- SEARCH
-- ============================================================
-- Deliberately simple: a case-insensitive substring over the item's name,
-- plus a few one-word type filters. A full query language is Syndicator's
-- job; what people actually type in a bag search is "shard" or "potion".
local TYPE_WORDS = {
    quest = function(_, _, _, isQuest) return isQuest end,
    equip = function(item) return item.link and IsEquippableItem
        and IsEquippableItem(item.link) end,
    junk  = function(item) return item.quality == 0 end,
    epic  = function(item) return item.quality == 4 end,
    rare  = function(item) return item.quality == 3 end,
    uncommon = function(item) return item.quality == 2 end,
}

local function Matches(item, query, bag, slot, isQuest)
    if not query or query == "" then return true end
    if not item then return false end
    query = query:lower()

    local typeFn = TYPE_WORDS[query]
    if typeFn then return typeFn(item, bag, slot, isQuest) and true or false end

    local name = item.link and item.link:match("%[(.-)%]")
    if name and name:lower():find(query, 1, true) then return true end
    -- Fall back to the item's type/subtype so "cloth" or "herb" work even
    -- when the name does not contain the word.
    if item.link and GetItemInfo then
        local _, _, _, _, _, itemType, itemSubType = GetItemInfo(item.link)
        if itemType and itemType:lower():find(query, 1, true) then return true end
        if itemSubType and itemSubType:lower():find(query, 1, true) then return true end
    end
    return false
end

-- ============================================================
-- SPLITTING A STACK
-- ============================================================
-- SplitContainerItem lives on C_Container on 1.15 and the bare global is
-- nil - the same move that made auction posting report "this client has
-- no posting API" while the API was right there. Both spellings, one
-- place.
local function Split(bag, slot, amount)
    if not amount or amount < 1 then return false end
    if C_Container and C_Container.SplitContainerItem then
        C_Container.SplitContainerItem(bag, slot, amount)
        return true
    elseif _G.SplitContainerItem then
        _G.SplitContainerItem(bag, slot, amount)
        return true
    end
    return false
end

-- PickupContainerItem moved the same way. One spelling for the sorter
-- and the auction poster alike; false when neither exists.
local function Pickup(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
        return true
    elseif _G.PickupContainerItem then
        _G.PickupContainerItem(bag, slot)
        return true
    end
    return false
end

-- ============================================================
-- CHANGE NOTIFICATION AND THE SHARED ITEM CACHE
-- ============================================================
-- One event frame for the whole bag system, with a coalescing timer.
-- BAG_UPDATE fires once PER BAG, so moving a stack can produce five
-- events in the same frame; rebuilding the grid five times is visible.
--
-- WHAT CHANGED, NOT JUST THAT SOMETHING DID. Listeners get a batch:
--   batch.bags[bag]   these bags' contents changed (BAG_UPDATE, a lock)
--   batch.full        anything else: repaint everything
--   batch.money       PLAYER_MONEY - only the footer cares
--   batch.cooldown    BAG_UPDATE_COOLDOWN - only the swipes care
-- so a stack looted into bag 2 repaints bag 2, a coin pickup touches
-- one font string, and a GCD with the bags open is cooldowns alone.
--
-- THE CACHE. Bags.Item(bag, slot) is the normalised item (plus its
-- quest flag) read once per change of that bag, not once per reader:
-- the bag window, the auction sell list and the mail collector all
-- read through it. An entry is dropped the moment its bag's event
-- arrives - before the coalesced repaint - so a read is never stale.
-- Entries are shared and read-only.
local listeners = {}
local function Subscribe(fn)
    listeners[#listeners + 1] = fn
end

local cache = {}                 -- bag -> { n = slots, [slot] = item|false }
local pending
local batch = { bags = {} }

local function Flush()
    pending = nil
    local b = batch
    batch = { bags = {} }
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, b)
        if not ok then Print("bags: refresh failed - " .. tostring(err)) end
    end
end

local function Schedule()
    if pending or #listeners == 0 then return end
    pending = true
    C_Timer.After(0, Flush)
end

local function DirtyBag(bag)
    if bag == nil then return end
    cache[bag] = nil
    batch.bags[bag] = true
    Schedule()
end

local function DirtyAll()
    wipe(cache)
    batch.full = true
    Schedule()
end

-- Kept for callers outside the event path (and for a reason string from
-- older code): anything that is not a known narrow change is a full one.
local function Notify(reason)
    if reason == "BAG_UPDATE_COOLDOWN" then
        batch.cooldown = true
        Schedule()
    elseif reason == "PLAYER_MONEY" then
        batch.money = true
        Schedule()
    else
        DirtyAll()
    end
end

local events
local function OnBagEvent(_, event, a1, a2)
    if event == "BAG_UPDATE" or event == "BAG_CLOSED" then
        DirtyBag(a1)
    elseif event == "ITEM_LOCK_CHANGED" then
        -- (bag, slot) for a container slot; (inventory slot, nil) for
        -- an equipped item or a bank square, which is rare enough to
        -- simply repaint everything.
        if a2 then DirtyBag(a1) else DirtyAll() end
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        DirtyBag(BANK_CONTAINER)
    elseif event == "BAG_UPDATE_DELAYED" then
        -- The end of a burst whose BAG_UPDATEs already named the bags.
        return
    else
        Notify(event)
    end
end

local function StartEvents()
    if events then return end
    events = CreateFrame("Frame")
    for _, e in ipairs({
        "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_CLOSED",
        "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
        "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED",
        "PLAYER_MONEY", "QUEST_ACCEPTED",
        "MERCHANT_SHOW", "MERCHANT_CLOSED",
        -- The bank's slots read empty while it is shut, so whatever was
        -- cached then is wrong the moment it opens (and vice versa).
        "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_ENTERING_WORLD",
    }) do
        pcall(events.RegisterEvent, events, e)
    end
    -- Our own quest log only: unfiltered, this fired for every raid
    -- member who picked up a quest item and repainted the whole bag.
    pcall(events.RegisterUnitEvent, events, "UNIT_QUEST_LOG_CHANGED", "player")
    events:SetScript("OnEvent", OnBagEvent)
end

-- The cached reads. The cache is only trusted while the event frame is
-- up to drop entries, so the first read starts it.
local function BagEntry(bag)
    local c = cache[bag]
    if not c then
        StartEvents()
        c = { n = NumSlots(bag) }
        cache[bag] = c
    end
    return c
end

local function Slots(bag)
    return BagEntry(bag).n
end

local function Item(bag, slot)
    local c = BagEntry(bag)
    local item = c[slot]
    if item == nil then
        item = ItemInfo(bag, slot) or false
        if item then item.isQuest = QuestInfo(bag, slot) and true or false end
        c[slot] = item
    end
    return item or nil
end

-- ============================================================
-- ACCOUNT GOLD LEDGER
-- ============================================================
-- "How much do I have across everyone" needs a record that is written
-- whether or not you ever open anything. Readycheck already keeps one -
-- ReadycheckDB.goldByToon - but it is only written from its stats bar
-- and its gold panel, so a character that never touched either is
-- simply absent, and a character sitting at zero is deliberately
-- DELETED from the table rather than stored. Both read as "missing
-- toons".
--
-- This ledger is written on PLAYER_MONEY and on logout, from an event
-- frame that exists as soon as the file loads. No module has to be on,
-- no window has to be opened, and zero is a real number that gets
-- stored. The two ledgers are then merged at read time, newest stamp
-- winning, so nothing already collected is thrown away.
--
-- What NEITHER can fix from inside the game: SavedVariables are
-- per-WoW-account. Characters on a different account folder are
-- invisible, full stop - there is no API that reaches them. That merge
-- has to happen outside the client.
local function GoldRealm()
    return (GetNormalizedRealmName and GetNormalizedRealmName())
        or (GetRealmName and GetRealmName()) or ""
end

local function GoldKey(name, realm)
    return tostring(name or "?") .. "-" .. tostring(realm or "")
end

local function Ledger()
    ZacUIDB.gold = ZacUIDB.gold or {}
    return ZacUIDB.gold
end

-- CACHED, because the reader is the hot one. The bag footer pulls the
-- total from view:Paint, and Paint runs on every BAG_UPDATE - several
-- times a second while looting. GoldRows builds a table per character,
-- unions two ledgers and SORTS them; paying that per loot is exactly
-- the quiet per-frame cost that ends up as "why is my framerate worse".
-- Recomputed only when something can actually have changed: your money,
-- an accepted sync message, or a fresh login.
local goldCache, goldDirty = 0, true
local function GoldChanged() goldDirty = true end

local function RecordGold()
    if not UnitName or not GetMoney then return end
    local name = UnitName("player")
    if not name then return end
    local key = GoldKey(name, GoldRealm())
    local copper = GetMoney() or 0
    local prev = Ledger()[key]

    -- A ZERO IS NOT ALWAYS A ZERO. GetMoney() answers 0 during
    -- PLAYER_LOGOUT and for a moment at login before the real value has
    -- arrived from the server. Storing that erases a true balance with a
    -- fake one, and it already did: Zacw was written to disk at 0 copper
    -- while holding 6195g, so the account total was short by his whole
    -- purse. A zero is only believed when this character has never been
    -- seen with money - which keeps a genuinely broke alt at 0.
    if copper == 0 and prev and (prev.copper or 0) > 0 then return end

    if prev and prev.copper == copper then return end   -- nothing moved
    local _, class = UnitClass("player")
    Ledger()[key] = {
        name = name,
        realm = GoldRealm(),
        copper = copper,
        class = class,
        faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
        t = time(),
    }
    GoldChanged()
end

-- READYCHECK'S LEDGER IS THE ONE SOURCE WHEN IT IS THERE. It is the one
-- that is actually correct across accounts: every account's own
-- characters, versioned by their owner, synced on every character whether
-- or not the mesh is on, with money in mailboxes and in the post counted.
-- The home-grown merge below (this file's own ledger + Readycheck's
-- retired goldByToon + the buff board's peer cache) only ever saw what
-- each client happened to see, so three clients logged in together
-- showed three different totals. It stays only as the fallback for a
-- setup without Readycheck.
local function ReadycheckLedger()
    local RC = _G.Readycheck
    local L = RC and RC.GoldLedger
    if L and L.Rows then return L end
end

local function ReadycheckRows(L)
    local src, total, transit = L:Rows()
    local rows = {}
    for _, r in ipairs(src or {}) do
        rows[#rows + 1] = {
            name = r.name, realm = r.realm, class = r.class,
            copper = (r.copper or 0) + (r.mail or 0), mail = r.mail,
            t = r.t, isMe = r.me, account = r.account,
        }
    end
    if (transit or 0) > 0 then
        rows[#rows + 1] = { name = "In the post", copper = transit, isPost = true }
    end
    return rows, total or 0
end

-- Every toon we know about, from both ledgers, most gold first.
-- Returns rows, total.
local function GoldRows()
    local RL = ReadycheckLedger()
    if RL then return ReadycheckRows(RL) end
    local rows, byKey = {}, {}
    local meName, meRealm = UnitName("player"), GoldRealm()

    -- DEDUPE ON A CASE-FOLDED KEY, never on the raw string. The two
    -- SavedVariables ledgers store a name exactly as UnitName gives it
    -- ("Thanda"), while Readycheck's mesh lowercases every peer name and
    -- strips realm whitespace before using it as a key. Matching on the
    -- raw string put the same character in as two rows - once per source -
    -- and the total counted their gold twice.
    --
    -- Readycheck's own comment on the same problem: "Keys arrive from
    -- three sources and must normalize identically or the same character
    -- shows up as two roster rows." Now there are four sources.
    local function FoldKey(name, realm)
        return (string.lower(GoldKey(name, realm)):gsub("%s+", ""))
    end
    local meKey = FoldKey(meName, meRealm)

    -- NOT-MINE LIST. Deleting a row is not enough on its own: this
    -- function unions Readycheck's goldByToon at read time, and that
    -- table is rewritten by Readycheck whenever one of those characters
    -- logs in. A character removed from the ledger would simply come
    -- back on the next read. The exclusion is what makes it stick.
    local excluded = ZacUIDB.goldExclude
    local function add(key, d)
        if type(d) ~= "table" then return end
        local nm = d.name or key
        local raw = GoldKey(nm, d.realm)
        local k = FoldKey(nm, d.realm)
        -- Existing exclusions were written with the raw key, so both
        -- spellings count: folding alone would quietly un-exclude every
        -- row the user had already removed.
        if excluded and (excluded[raw] or excluded[k]) then return end
        local rec = byKey[k]
        if not rec then
            rec = { name = nm, realm = d.realm, class = d.class,
                    copper = d.copper or 0, t = d.t or 0 }
            byKey[k] = rec
            rows[#rows + 1] = rec
        else
            -- Keep the best-looking display name. The mesh only ever
            -- supplies a lowercased one, and it must not overwrite the
            -- capitalised name a SavedVariables ledger already had.
            if nm and rec.name and nm ~= string.lower(nm)
               and rec.name == string.lower(rec.name) then
                rec.name = nm
            end
            if (d.t or 0) > (rec.t or 0) then
                -- NEWEST STAMP WINS. The sources can disagree about a
                -- character; the fresher write is the honest one.
                rec.copper, rec.t = d.copper or 0, d.t or 0
                rec.class = d.class or rec.class
            end
        end
    end

    for k, d in pairs(Ledger()) do add(k, d) end
    local rc = _G.ReadycheckDB and _G.ReadycheckDB.goldByToon
    if type(rc) == "table" then
        for k, d in pairs(rc) do add(k, d) end
    end

    -- THIRD LEDGER: Readycheck's live mesh peers.
    --
    -- The two ledgers above are both SavedVariables, so both are blind to
    -- characters on a different WoW account folder - the limitation called
    -- out at the top of this section. ZacUI's own whisper sync does not
    -- close it either: it only whispers names already in OUR ledger, which
    -- by definition never contains another account's toons.
    --
    -- Readycheck's mesh does reach across accounts, and already carries a
    -- gold figure per peer for exactly this purpose (its own gold panel
    -- reads the same table). Reading it here is what makes a second client
    -- running on another account show up in the account total at all.
    --
    -- Still a read-time union with newest-stamp-wins, so a peer never
    -- overwrites a fresher local record, and the live GetMoney() pass
    -- below still wins outright for the character you are standing on.
    local rcMesh = _G.Readycheck and _G.Readycheck.WorldBuffs
    local peers = rcMesh and rcMesh.peers
    if type(peers) == "table" then
        for _, p in pairs(peers) do
            if type(p) == "table" and p.name and (p.gold or 0) > 0 then
                -- Mesh keys are "Name-Realm", or bare "Name" on a lossy
                -- hop. Split so the row merges with the local ledger's
                -- key instead of forking the same character into two rows.
                local pn, pr = string.match(tostring(p.name), "^([^%-]+)%-?(.*)$")
                if pn and pn ~= "" then
                    add(pn, {
                        name   = pn,
                        realm  = (pr ~= "" and pr) or meRealm,
                        class  = p.class,
                        copper = p.gold,
                        t      = p.goldT or p.t or 0,
                    })
                end
            end
        end
    end

    -- The character you are standing on is authoritative and live - no
    -- stamp beats actually asking.
    local mine = byKey[meKey]
    if not mine then
        mine = { name = meName, realm = meRealm }
        byKey[meKey] = mine
        rows[#rows + 1] = mine
    end
    local _, myClass = UnitClass("player")
    mine.copper = GetMoney and GetMoney() or 0
    mine.class = myClass or mine.class
    mine.t = time()
    mine.isMe = true

    local total = 0
    for _, r in ipairs(rows) do total = total + (r.copper or 0) end
    table.sort(rows, function(a, b) return (a.copper or 0) > (b.copper or 0) end)
    return rows, total
end

local goldAt = 0
local function GoldTotal()
    -- Readycheck's ledger changes on the wire with no event of ours to
    -- mark it dirty, so it is re-read at most once a second instead.
    if ReadycheckLedger() then
        local now = GetTime and GetTime() or 0
        if goldDirty or now - goldAt >= 1 then
            local _, total = GoldRows()
            goldCache, goldDirty, goldAt = total, false, now
        end
        return goldCache
    end
    if goldDirty then
        local _, total = GoldRows()
        goldCache, goldDirty = total, false
    end
    return goldCache
end

-- ============================================================
-- DUAL-BOX SYNC
-- ============================================================
-- The mesh cannot introduce characters that are never online together,
-- and one person logs in serially - so this is not a general alt sync
-- and does not pretend to be. It covers exactly one case: two clients
-- running at once, where both characters ARE on the wire.
--
-- WHISPER to our own known names only. Not GUILD, not YELL: a broadcast
-- channel would hand your per-character gold to every other player
-- running this addon, which is the trade that was explicitly declined.
-- A whisper aimed at a name already in your own ledger cannot reach
-- anyone but you.
--
-- Only names confirmed ONLINE are whispered. Blind-whispering thirty
-- offline alts is how you paper the chat frame with "No player named X
-- is currently playing" - Readycheck's own mesh takes the same care
-- (Mesh_Proto only whispers peers whose info.online is set).
local GOLD_PREFIX = "ZacUIGold"
local GOLD_SEP = "\029"
local lastGoldSync = 0

-- CACHED FOR A MINUTE. With an alt on this realm in the ledger (the
-- usual case for a multi-boxer) every money change past the 10s
-- throttle walked the whole guild roster - every few seconds while
-- looting coin in a raid. Who is online does not move that fast.
local onlineSet, onlineAt = nil, -60
local function OnlineNames()
    local now = GetTime and GetTime() or 0
    if onlineSet and now - onlineAt < 60 then return onlineSet end
    onlineAt = now
    local set = {}
    onlineSet = set
    if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, (GetNumGuildMembers() or 0) do
            local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if name and online then
                set[(Ambiguate and Ambiguate(name, "none")) or name] = true
            end
        end
    end
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, (C_FriendList.GetNumFriends() or 0) do
            local info = C_FriendList.GetFriendInfoByIndex
                and C_FriendList.GetFriendInfoByIndex(i)
            if info and info.connected and info.name then set[info.name] = true end
        end
    end
    return set
end

local function SyncGold()
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    -- WoW Forever delivers no addon messages inside an instance; the next
    -- money change outside sends it (Core_Flavor)
    if ns.AddonMessagesBlocked and ns.AddonMessagesBlocked() then return end
    local now = GetTime and GetTime() or 0
    if now - lastGoldSync < 10 then return end   -- money changes constantly
    lastGoldSync = now

    RecordGold()
    local myName = UnitName("player")
    local me = Ledger()[GoldKey(myName, GoldRealm())]
    if not me then return end

    -- Cheap exit BEFORE the roster walk. OnlineNames iterates the whole
    -- guild - potentially hundreds of GetGuildRosterInfo calls - and
    -- there is no point paying for it when the ledger holds nobody on
    -- this realm to whisper. Solo-account players never walk it at all.
    local anyPeer = false
    for _, d in pairs(Ledger()) do
        if d and d.name and d.name ~= myName and (d.realm or "") == (me.realm or "") then
            anyPeer = true
            break
        end
    end
    if not anyPeer then return end

    -- Our OWN record only, one message. The rest of the ledger is
    -- already on both sides and would not fit in an addon message
    -- anyway - 255 bytes, and this is the only row we can vouch for.
    local payload = table.concat({ "g1", tostring(me.name),
        tostring(me.realm or ""), tostring(me.copper or 0),
        tostring(me.class or ""), tostring(me.t or 0) }, GOLD_SEP)

    local online = OnlineNames()
    for _, d in pairs(Ledger()) do
        local n = d and d.name
        if n and n ~= myName and online[n]
            and (d.realm or "") == (me.realm or "") then
            pcall(C_ChatInfo.SendAddonMessage, GOLD_PREFIX, payload, "WHISPER", n)
        end
    end
end

local function OnGoldMessage(prefix, msg)
    if prefix ~= GOLD_PREFIX or type(msg) ~= "string" then return end
    local kind, name, realm, copper, class, t = strsplit(GOLD_SEP, msg)
    if kind ~= "g1" or not name or name == "" then return end
    -- UNAUTHENTICATED INPUT. An addon message is whatever any player who
    -- can whisper you decided to send. Records are only ever UPDATED,
    -- never created, so a stranger cannot invent characters and inflate
    -- your total - the worst they can do is restate a row you already
    -- have, and only with a newer stamp than the one you hold.
    local led = Ledger()
    local cur = led[GoldKey(name, realm)]
    if not cur then return end
    t = tonumber(t) or 0
    if t > (cur.t or 0) then
        cur.copper = tonumber(copper) or cur.copper
        if class and class ~= "" then cur.class = class end
        cur.t = t
        GoldChanged()
    end
end

local goldEvents = CreateFrame("Frame")
goldEvents:RegisterEvent("PLAYER_MONEY")
goldEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
goldEvents:RegisterEvent("CHAT_MSG_ADDON")
pcall(goldEvents.RegisterEvent, goldEvents, "PLAYER_LOGOUT")
goldEvents:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "CHAT_MSG_ADDON" then
        -- THE HOTTEST LINE IN THIS FILE. CHAT_MSG_ADDON fires for every
        -- addon message from every addon on your machine - Readycheck's
        -- mesh, WeakAuras, Questie, Gargul - which in a 40-man is a
        -- constant stream. The prefix compare happens inline, before any
        -- call or vararg unpack, so a message that is not ours costs one
        -- string comparison and nothing else.
        if arg1 == GOLD_PREFIX then OnGoldMessage(arg1, arg2) end
        return
    end
    RecordGold()
    if event ~= "PLAYER_LOGOUT" then SyncGold() end
end)
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, GOLD_PREFIX)
end

-- Mesh peer gold lands in Readycheck's peer table whenever a broadcast
-- arrives, which no event of ours observes - so without this the total
-- would only pick it up the next time our own money changed.
--
-- Marking dirty is not the same as recomputing: GoldRows only actually
-- runs on the next GoldTotal() read, and the only reader is the bag
-- footer's Paint. With the window shut this costs one flag write every
-- 15s and nothing else. Deliberately NOT hooked to CHAT_MSG_ADDON - see
-- the note on that handler above about what it costs in a 40-man.
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(15, function()
        if _G.Readycheck and _G.Readycheck.WorldBuffs then GoldChanged() end
    end)
end

-- shared with later ZacUI files
ns.Bags = {
    GoldRows = GoldRows,
    GoldTotal = GoldTotal,
    FromReadycheck = function() return ReadycheckLedger() ~= nil end,
    BACKPACK_BAGS = BACKPACK_BAGS,
    BANK_BAGS = BANK_BAGS,
    BANK_CONTAINER = BANK_CONTAINER,
    NUM_BANKBAGSLOTS = NUM_BANKBAGSLOTS,
    Cooldown = Cooldown,
    Item = Item,
    ItemInfo = ItemInfo,
    Matches = Matches,
    Notify = Notify,
    NumSlots = NumSlots,
    Pickup = Pickup,
    Slots = Slots,
    Split = Split,
    StartEvents = StartEvents,
    Subscribe = Subscribe,
}
