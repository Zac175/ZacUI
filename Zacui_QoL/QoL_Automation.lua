-- QoL_Automation - the event-driven half of the quality-of-life module:
-- gossip skipping, junk selling, auto repair, faster looting, whisper
-- invites and error-message dismounting.
-- Part of ZacUI; load order is set by the TOC.
--
-- Every behavior here is Leatrix's, constant for constant:
--   * gossip: needs Alt held, EXCEPT the big NPC table (stables,
--     bankers, flight masters, trainers, vendors, battlemasters) which
--     skips freely; Shift suppresses even those. Only fires when the
--     page has exactly one option and no quests.
--   * junk: 0.2s ticker, 500 iteration cap, stops on a clean pass, a
--     closed merchant, ERR_VENDOR_DOESNT_BUY or ERR_TOO_MUCH_GOLD.
--     Shift held on open skips entirely. The exclude list is
--     BIDIRECTIONAL: a grey on the list is kept, a white is sold.
--   * repair: personal gold only (the Era build has no guild-repair
--     path), Shift skips, silent when you can't afford it.
--   * loot: 0.3s floor between bursts, reverse slot order, honors the
--     auto-loot toggle and master-loot thresholds.
--   * invite: whole-message match on the keyword after trim+lower;
--     leader/assist guard; never while queued for a battleground.
--   * dismount: matches the localized error strings, so it survives
--     any client locale that defines the globals.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local QoL = ns.QoL

local GetTime = GetTime
local strlower, strtrim, strsplit = strlower, strtrim, strsplit

local DB = QoL.DB

-- ============================================================
-- AUTOMATE GOSSIP
-- ============================================================
local function SkipGossip(skipAltKeyRequirement)
    if not skipAltKeyRequirement and not IsAltKeyDown() then return end
    local options = C_GossipInfo.GetOptions()
    if options and #options == 1
        and C_GossipInfo.GetNumAvailableQuests() == 0
        and C_GossipInfo.GetNumActiveQuests() == 0
        and options[1] and options[1].gossipOptionID then
        C_GossipInfo.SelectOption(options[1].gossipOptionID)
    end
end

local gossipFrame = CreateFrame("Frame")
gossipFrame:SetScript("OnEvent", function()
    if not DB().gossip then return end
    local npcGuid = UnitGUID("npc")
    if npcGuid and not IsShiftKeyDown() then
        local npcId = tonumber(npcGuid:match("%-(%d+)%-%x+$") or "")
        if npcId and QoL.GOSSIP_NPCS[npcId] then
            SkipGossip(true)
            return
        end
    end
    SkipGossip()
end)

-- ============================================================
-- SELL JUNK + AUTO REPAIR - both ride MERCHANT_SHOW.
-- ============================================================
local whiteList = {}
local function UpdateWhiteList()
    wipe(whiteList)
    local raw = DB().sellExclude or ""
    raw = raw:gsub("[^,%d]", "")
    for _, part in ipairs({ strsplit(",", raw) }) do
        local id = tonumber(part)
        if id then whiteList[id] = true end
    end
end
QoL.UpdateWhiteList = UpdateWhiteList

local sellTicker, sellIterations, totalPrice

local function StopSelling()
    if sellTicker then sellTicker:Cancel(); sellTicker = nil end
end

local function SellJunkPass()
    local d = DB()
    sellIterations = sellIterations + 1
    if sellIterations > 500 or not MerchantFrame:IsShown() then
        StopSelling()
        return
    end
    local soldCount = 0
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if not MerchantFrame:IsShown() then StopSelling() return end
            local link = C_Container.GetContainerItemLink(bag, slot)
            if link then
                local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                local _, _, rarity, _, _, _, _, _, _, _, price = getInfo(link)
                local id = tonumber(link:match("item:(%d+)"))
                if id and whiteList[id] then
                    -- bidirectional list: keep this grey / sell this white
                    if rarity == 0 then rarity = 3; price = 0
                    elseif rarity == 1 then rarity = 0 end
                end
                if rarity == 0 and price and price ~= 0 then
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    local count = info and (info.stackCount or info[2]) or 1
                    C_Container.UseContainerItem(bag, slot)
                    totalPrice = totalPrice + price * count
                    soldCount = soldCount + 1
                end
            end
        end
    end
    if soldCount == 0 then
        StopSelling()
        if totalPrice > 0 and d.sellSummary then
            Print("Sold junk for " .. GetCoinText(totalPrice) .. ".")
        end
    end
end

local function OnMerchantShow()
    local d = DB()
    if IsShiftKeyDown() then return end
    if d.repair and CanMerchantRepair() then
        local cost = GetRepairAllCost()
        if cost and cost > 0 and GetMoney() >= cost then
            RepairAllItems()
            if d.repairSummary then
                Print("Repaired for " .. GetCoinText(cost) .. ".")
            end
        end
    end
    if d.sellJunk then
        UpdateWhiteList()
        StopSelling()
        sellIterations, totalPrice = 0, 0
        sellTicker = C_Timer.NewTicker(0.2, SellJunkPass)
    end
end

-- The merchant window's "Sell junk" button: the same pass, on demand,
-- whatever the auto-sell setting says.
function QoL.SellJunkNow()
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    UpdateWhiteList()
    StopSelling()
    sellIterations, totalPrice = 0, 0
    sellTicker = C_Timer.NewTicker(0.2, SellJunkPass)
end

local merchantFrame = CreateFrame("Frame")
merchantFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "MERCHANT_SHOW" then
        -- the sell pass stops on a vendor's refusal: listened for only
        -- while a merchant is open (error text comes all fight long)
        self:RegisterEvent("UI_ERROR_MESSAGE")
        OnMerchantShow()
    elseif event == "MERCHANT_CLOSED" then
        self:UnregisterEvent("UI_ERROR_MESSAGE")
        StopSelling()
    elseif event == "UI_ERROR_MESSAGE" then
        -- fires (messageType, message) - the string is the SECOND arg
        if arg2 == ERR_VENDOR_DOESNT_BUY or arg2 == ERR_TOO_MUCH_GOLD then
            StopSelling()
        end
    end
end)

-- ============================================================
-- FASTER LOOTING
-- ============================================================
local tDelay = 0
local function FastLoot()
    if not DB().fasterLoot then return end
    if GetTime() - tDelay < 0.3 then return end
    tDelay = GetTime()
    if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
        if TSMDestroyBtn and TSMDestroyBtn:IsShown()
            and TSMDestroyBtn:GetButtonState() == "DISABLED" then
            tDelay = GetTime()
            return
        end
        local lootMethod = C_PartyInfo and C_PartyInfo.GetLootMethod
            and C_PartyInfo.GetLootMethod()
        if lootMethod == 2 then
            local threshold = GetLootThreshold()
            for i = GetNumLootItems(), 1, -1 do
                local _, _, _, _, quality = GetLootSlotInfo(i)
                if quality and threshold and quality < threshold then
                    LootSlot(i)
                end
            end
        else
            for i = GetNumLootItems(), 1, -1 do
                LootSlot(i)
            end
        end
        tDelay = GetTime()
    end
end

local lootFrame = CreateFrame("Frame")
lootFrame:SetScript("OnEvent", FastLoot)

-- ============================================================
-- INVITE FROM WHISPER
-- ============================================================
local function IsInLFGQueue()
    if C_LFGList and C_LFGList.HasActiveEntryInfo
        and C_LFGList.HasActiveEntryInfo() then
        return true
    end
    for i = 1, GetMaxBattlefieldID() do
        local status = GetBattlefieldStatus(i)
        if status == "queued" or status == "confirmed" then return true end
    end
    return false
end

-- friend check, with the FriendlyGuild extension: online guildies count
local function FriendCheck(name, guid)
    if not name then return false end
    local short = strsplit("-", name, 2)
    for i = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name and (info.name == name or info.name == short) then
            return true
        end
    end
    if DB().friendlyGuild and IsInGuild() then
        for i = 1, GetNumGuildMembers() do
            local gName, _, _, _, _, _, _, _, online, _, _, _, _, isMobile =
                GetGuildRosterInfo(i)
            if gName and online and not isMobile then
                local gShort = strsplit("-", gName, 2)
                if gName == name or gShort == short then return true end
            end
        end
    end
    return false
end

local whisperFrame = CreateFrame("Frame")
whisperFrame:SetScript("OnEvent", function(_, event, arg1, arg2, ...)
    local d = DB()
    if not d.invite then return end
    if not (not UnitExists("party1") or UnitIsGroupLeader("player")
        or UnitIsGroupAssistant("player")) then return end
    if strlower(strtrim(arg1 or "")) ~= strlower(d.inviteKey or "inv") then return end
    if IsInLFGQueue() then return end
    if event == "CHAT_MSG_WHISPER" then
        local guid = select(10, ...)
        if not d.inviteFriendsOnly or FriendCheck(arg2, guid) then
            -- same-realm whisperers invite by short name
            local name, realm = strsplit("-", arg2, 2)
            if realm then
                local _, myRealm = UnitFullName("player")
                if myRealm and realm == myRealm then arg2 = name end
            end
            if C_PartyInfo and C_PartyInfo.InviteUnit then
                C_PartyInfo.InviteUnit(arg2)
            else
                InviteUnit(arg2)
            end
        end
    elseif event == "CHAT_MSG_BN_WHISPER" then
        local presenceID = select(11, ...)
        if presenceID and BNIsFriend and BNIsFriend(presenceID) then
            local accountInfo = C_BattleNet.GetFriendAccountInfo
                and C_BattleNet.GetFriendAccountInfo(presenceID)
            local gameAccount = accountInfo and accountInfo.gameAccountInfo
            if gameAccount and gameAccount.gameAccountID then
                BNInviteFriend(gameAccount.gameAccountID)
            end
        end
    end
end)

-- ============================================================
-- STAND AND DISMOUNT
-- ============================================================
local dismountFrame = CreateFrame("Frame")
dismountFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
    local d = DB()
    if not d.dismount then return end
    if event == "TAXIMAP_OPENED" then
        if d.dismountNoTaxi and IsMounted() then Dismount() end
        return
    end
    -- UI_ERROR_MESSAGE fires (messageType, message); compare the
    -- localized string, like the original - locale-safe via globals
    local msg = arg2
    local fire
    if msg == ERR_OUT_OF_RAGE or msg == ERR_OUT_OF_MANA
        or msg == ERR_OUT_OF_ENERGY then
        fire = d.dismountNoResource
    elseif msg == SPELL_FAILED_MOVING then
        fire = d.dismountNoMoving
    elseif msg == ERR_TAXIPLAYERSHAPESHIFTED then
        fire = true   -- ungated in the original whenever the parent is on
    end
    if fire and IsMounted() then
        Dismount()
        UIErrorsFrame:Clear()
    end
end)

-- ============================================================
-- ARM EVERYTHING - called once by the module entry point. Handlers
-- re-check the DB per event, so config toggles need no re-arm.
-- ============================================================
function QoL.EnableAutomation()
    gossipFrame:RegisterEvent("GOSSIP_SHOW")
    merchantFrame:RegisterEvent("MERCHANT_SHOW")
    merchantFrame:RegisterEvent("MERCHANT_CLOSED")
    lootFrame:RegisterEvent("LOOT_READY")
    whisperFrame:RegisterEvent("CHAT_MSG_WHISPER")
    whisperFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
    dismountFrame:RegisterEvent("UI_ERROR_MESSAGE")
    dismountFrame:RegisterEvent("TAXIMAP_OPENED")
    UpdateWhiteList()
end
