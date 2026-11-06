-- QoL_AutoRoll - rolls on group loot for you.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT THIS REPLACES. Two auras: "Auto Roll on Group Loot in Raids"
-- (wago KgtuiBtIQ - a choice per item quality, plus Naxx scraps and
-- Word of Thawing) and the ZG raid pack's "AutoRoll on Bijou/Coins" (a choice
-- for coins and one for bijous, per character name). The ZG one was
-- keyed to the names Zacwarrior and Sunderpls, so it never matched the
-- characters that actually raid; the other read the quality through
-- C_Item.GetItemQualityByID, which this client does not always have.
-- Neither rolled. The seeds below are what those auras were set to.
--
-- HOW IT DECIDES, in order: a custom item you added here, then a known
-- group (ZG coins, ZG bijous, Naxx wartorn scraps, Word of Thawing),
-- then the item's quality. "Ask" leaves the roll box alone. Need falls
-- back to Greed and Greed to Pass when the server does not offer that
-- button for the item, so it never errors on a roll it cannot make.
-- The quality comes from the roll itself (GetLootRollItemInfo), never
-- from the item cache, so an item the client has not seen before still
-- rolls; only the link can lag, and that is retried for a few seconds.
--
-- A roll it made on a bind-on-pickup item confirms its own "are you
-- sure" box. Rolls it did not make are never touched.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local QoL = ns.QoL

local AR = {}
QoL.AutoRoll = AR

-- RollOnLoot's ids. "ask" is ours: do nothing.
local ROLL_ID = { pass = 0, need = 1, greed = 2 }
AR.CHOICES = {
    { value = "ask",   label = "Ask (show the roll box)" },
    { value = "pass",  label = "Pass" },
    { value = "need",  label = "Need" },
    { value = "greed", label = "Greed" },
}
AR.CHOICE_LABEL = {}
for _, c in ipairs(AR.CHOICES) do AR.CHOICE_LABEL[c.value] = c.label end

-- Item qualities, in GetLootRollItemInfo's numbering.
AR.QUALITIES = {
    { q = 0, label = "|cff9d9d9dPoor|r",      key = "q0" },
    { q = 1, label = "|cffffffffCommon|r",    key = "q1" },
    { q = 2, label = "|cff1eff00Uncommon|r",  key = "q2" },
    { q = 3, label = "|cff0070ddRare|r",      key = "q3" },
    { q = 4, label = "|cffa335eeEpic|r",      key = "q4" },
    { q = 5, label = "|cffff8000Legendary|r", key = "q5" },
}

-- Known item groups: one choice covers the whole set.
AR.GROUPS = {
    { key = "zgCoins", label = "Zul'Gurub coins", ids = {
        19698, 19699, 19700, 19701, 19702, 19703, 19704, 19705, 19706 } },
    { key = "zgBijous", label = "Zul'Gurub bijous", ids = {
        19707, 19708, 19709, 19710, 19711, 19712, 19713, 19714, 19715 } },
    { key = "naxxScrap", label = "Naxxramas wartorn scraps", ids = {
        22373, 22374, 22375, 22376 } },
    { key = "wordThaw", label = "Word of Thawing", ids = { 23055 } },
}
local GROUP_OF = {}
for _, g in ipairs(AR.GROUPS) do
    for _, id in ipairs(g.ids) do GROUP_OF[id] = g.key end
end

-- ============================================================
-- SETTINGS - under ZacUIDB.qol so they travel with the profile.
-- Seeded from the two auras: every quality Pass, scraps and Word of
-- Thawing Pass, coins and bijous Need, raids only, no chat filter.
-- ============================================================
local function DB()
    local d = QoL.DB()
    if type(d.autoRoll) ~= "table" then
        d.autoRoll = {
            enabled = true,
            raidsOnly = true,
            announce = true,
            filterChat = false,
            quality = { q0 = "pass", q1 = "pass", q2 = "pass",
                        q3 = "pass", q4 = "pass", q5 = "pass" },
            groups = { zgCoins = "need", zgBijous = "need",
                       naxxScrap = "pass", wordThaw = "pass" },
            custom = {},   -- { { id = 12345, name = "...", roll = "need" }, ... }
        }
    end
    local a = d.autoRoll
    a.quality = a.quality or {}
    a.groups = a.groups or {}
    a.custom = a.custom or {}
    return a
end
AR.DB = DB

-- ============================================================
-- DECIDING
-- ============================================================
local function ItemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- The configured choice for an item, and where it came from.
local function Choice(itemId, quality)
    local a = DB()
    if itemId then
        for _, c in ipairs(a.custom) do
            if c.id == itemId then return c.roll or "ask", "custom" end
        end
        local gk = GROUP_OF[itemId]
        if gk then return a.groups[gk] or "ask", "group" end
    end
    if quality then
        local v = a.quality["q" .. quality]
        if v then return v, "quality" end
    end
    return "ask", nil
end
AR.Choice = Choice

local InRaidInstance = ns.InRaidInstance

-- rollID -> true for rolls this module made (so the BoP confirm and the
-- chat filter only touch our own), cleared when the roll goes away.
local mine = {}
-- itemId -> GetTime() of our last roll on it, for the chat filter.
local rolledItems = {}

local function Announce(choice, link, a)
    if not a.announce then return end
    local what = ({ pass = "|cffadadadPassed|r on", need = "Rolled |cff00ff00NEED|r on",
        greed = "Rolled |cffffff00GREED|r on" })[choice]
    if what then Print("auto-roll: " .. what .. " " .. tostring(link)) end
end

local function DoRoll(rollID, choice, canNeed, canGreed, link, a)
    -- Fall back to what the server offers rather than erroring.
    if choice == "need" and canNeed == false then choice = (canGreed ~= false) and "greed" or "pass" end
    if choice == "greed" and canGreed == false then choice = "pass" end
    local id = ROLL_ID[choice]
    if not id then return end
    mine[rollID] = true
    local itemId = ItemIdFromLink(link)
    if itemId then
        local now = GetTime()
        -- only the last five minutes matter to the chat filter
        for id, t in pairs(rolledItems) do
            if now - t > 300 then rolledItems[id] = nil end
        end
        rolledItems[itemId] = now
    end
    RollOnLoot(rollID, id)
    Announce(choice, link, a)
end

local function Handle(rollID, tries)
    local a = DB()
    if not a.enabled then return end
    if a.raidsOnly and not InRaidInstance() then return end
    local texture, name, count, quality, bop, canNeed, canGreed = GetLootRollItemInfo(rollID)
    if not texture then return end   -- roll already gone
    local link = GetLootRollItemLink(rollID)
    local itemId = ItemIdFromLink(link)
    -- The link can lag the event by a moment on an uncached item. The
    -- quality is already here, so only wait while an item rule (custom
    -- or group) could still change the answer.
    if not itemId and tries < 6 then
        C_Timer.After(0.5, function() Handle(rollID, tries + 1) end)
        return
    end
    local choice = Choice(itemId, quality)
    if choice == "ask" then return end
    DoRoll(rollID, choice, canNeed, canGreed, link or name, a)
end

-- ============================================================
-- EVENTS
-- ============================================================
local f = CreateFrame("Frame")
f:RegisterEvent("START_LOOT_ROLL")
f:RegisterEvent("CONFIRM_LOOT_ROLL")
f:RegisterEvent("CANCEL_LOOT_ROLL")
f:SetScript("OnEvent", function(_, event, rollID, arg2)
    if not QoL.enabled then return end
    if event == "START_LOOT_ROLL" then
        Handle(rollID, 0)
    elseif event == "CONFIRM_LOOT_ROLL" then
        -- Only a roll this module made: a BoP need asks "are you sure".
        if mine[rollID] and ConfirmLootRoll then
            ConfirmLootRoll(rollID, arg2)
            if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_LOOT_ROLL") end
        end
    elseif event == "CANCEL_LOOT_ROLL" then
        mine[rollID] = nil
    end
end)

-- ============================================================
-- CHAT FILTER - hides the "X has selected Need for: [item]" noise for
-- items this module rolled on in the last few minutes. Messages about
-- someone RECEIVING an item always stay.
-- ============================================================
-- The client's "X receives loot: [item]" format strings, turned into
-- loose patterns once: magic characters escaped, every %s / %d / %1$s
-- slot replaced by ".-".
local receivePats
local function ReceivePatterns()
    if receivePats then return receivePats end
    receivePats = {}
    for _, p in ipairs({ LOOT_ITEM, LOOT_ITEM_SELF, LOOT_ITEM_MULTIPLE, LOOT_ITEM_SELF_MULTIPLE,
                         LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE }) do
        if type(p) == "string" then
            local pat = p:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
            pat = pat:gsub("%%%d%$[sd]", ".-"):gsub("%%[sd]", ".-")
            receivePats[#receivePats + 1] = "^" .. pat
        end
    end
    return receivePats
end

local function IsReceiveMessage(msg)
    for _, pat in ipairs(ReceivePatterns()) do
        if msg:find(pat) then return true end
    end
    return false
end

local function Filter(_, _, msg)
    local a = DB()
    if not a.filterChat or not QoL.enabled then return false end
    local itemId = ItemIdFromLink(msg)
    if not itemId then return false end
    local t = rolledItems[itemId]
    if not t then return false end
    if (GetTime() - t) > 300 then
        rolledItems[itemId] = nil
        return false
    end
    if IsReceiveMessage(msg) then return false end
    return true
end
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_LOOT", Filter)
end

-- ============================================================
-- CUSTOM ITEMS - list helpers for the config page.
-- ============================================================
function AR.AddCustom(idOrLink, roll)
    local id = tonumber(idOrLink) or ItemIdFromLink(idOrLink)
    if not id then return false, "no item id in that" end
    local a = DB()
    for _, c in ipairs(a.custom) do
        if c.id == id then c.roll = roll or c.roll return true end
    end
    local name = GetItemInfo and GetItemInfo(id) or nil
    a.custom[#a.custom + 1] = { id = id, name = name, roll = roll or "pass" }
    return true
end

function AR.RemoveCustom(id)
    local a = DB()
    for i = #a.custom, 1, -1 do
        if a.custom[i].id == id then table.remove(a.custom, i) end
    end
end

-- Names fill in once the item is cached.
function AR.CustomName(c)
    if c.name and c.name ~= "" then return c.name end
    local n = GetItemInfo and GetItemInfo(c.id)
    if n then c.name = n return n end
    return "item " .. tostring(c.id)
end

-- /zui roll test <itemId> prints what it would do, without a roll.
function AR.Explain(itemId)
    local a = DB()
    local link = GetItemInfo and select(2, GetItemInfo(itemId))
    local q = GetItemInfo and select(3, GetItemInfo(itemId))
    local choice, why = Choice(itemId, q)
    Print(string.format("auto-roll: %s -> %s (%s)%s", tostring(link or itemId),
        AR.CHOICE_LABEL[choice] or choice, why or "no rule",
        (a.raidsOnly and not InRaidInstance()) and " - but only inside a raid instance" or ""))
end
