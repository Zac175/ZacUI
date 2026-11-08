-- Win_QuestRewards - a coin on the quest reward that sells for most, when
-- the rewards are a choice: on ZacUI's own quest window (Win_Gossip) and
-- on Blizzard's quest frame when that one is in use. Off by default (Game
-- windows > General).
-- Part of ZacUI; load order is set by the TOC (after Win_Gossip).
--
-- THE PRICE is the item's vendor price (GetItemInfo's eleventh return, or
-- C_Item.GetItemInfo) times the stack the quest hands over. An item the
-- client has not cached yet answers nothing; the mark then waits for
-- ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED and tries once more. A
-- tie marks every reward that ties. One reward (nothing to choose) gets
-- no mark. The badge takes no mouse, so the reward under it clicks as
-- before; "show the price" writes the amount under the coin.
--
-- COST: a pass over the choices when a quest page is drawn; one item event
-- registered only while a price is missing.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local Kit = ns.Kit
local GetColor = ns.GetColor

local QR = {}
ns.QuestRewardMark = QR

local OWN_ID = "quest_reward_mark"
local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
local DEFAULT_SIZE = 14

-- ============================================================
-- SETTINGS (windows.rewardMark*; nothing saved = off, 14 px, no price)
-- ============================================================
local function DB()
    if Kit and Kit.DB then return Kit.DB() end
    ZacUIDB.windows = ZacUIDB.windows or {}
    return ZacUIDB.windows
end
function QR.On()
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return false end
    return DB().rewardMark == true
end
function QR.ShowPrice() return DB().rewardMarkPrice == true end
function QR.Size()
    local v = tonumber(DB().rewardMarkSize) or DEFAULT_SIZE
    return math.max(8, math.min(32, v))
end
QR.PRICE_FONT_DEFAULTS = { size = 10, outline = "outline", shadow = false }

-- ============================================================
-- PRICES
-- ============================================================
local function ItemInfo(link)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(f) ~= "function" or not link then return nil end
    local ok, a, b, c, d, e, g, h, i, j, k, sell = pcall(f, link)
    if not ok then return nil end
    return sell
end

-- the vendor value of choice i (copper), or nil while the item is not cached
function QR.ChoiceValue(i)
    if type(GetQuestItemLink) ~= "function" then return nil end
    local ok, link = pcall(GetQuestItemLink, "choice", i)
    if not ok or type(link) ~= "string" then return nil end
    local sell = ItemInfo(link)
    if type(sell) ~= "number" then return nil end
    local count = 1
    if type(GetQuestItemInfo) == "function" then
        local ok2, _, _, n = pcall(GetQuestItemInfo, "choice", i)
        if ok2 and type(n) == "number" and n > 0 then count = n end
    end
    return sell * count
end

-- the best choice indexes { [i] = true } and their value; nil, true when
-- a price is still missing; nil with fewer than two choices
function QR.Best()
    local n = type(GetNumQuestChoices) == "function" and GetNumQuestChoices() or 0
    if type(n) ~= "number" or n < 2 then return nil end
    local best, top, missing = {}, -1, false
    for i = 1, n do
        local v = QR.ChoiceValue(i)
        if v == nil then
            missing = true
        elseif v > top then
            top = v
            best = { [i] = true }
        elseif v == top then
            best[i] = true
        end
    end
    if missing then return nil, true end
    if top <= 0 then return nil end
    return best, false, top
end

-- ============================================================
-- THE BADGE
-- ============================================================
local function Badge(button)
    local b = button._zRewardCoin
    if b then return b end
    local UI = ns.UI
    b = CreateFrame("Frame", nil, button)
    b:EnableMouse(false)
    b:SetFrameLevel((button:GetFrameLevel() or 1) + 3)
    local tex = b:CreateTexture(nil, "OVERLAY")
    tex._zui_own = true
    tex:SetAllPoints()
    tex:SetTexture(COIN)
    b._zTex = tex
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOP", b, "BOTTOM", 0, -1)
    b._zPrice = fs
    button._zRewardCoin = b
    return b
end

function QR.Dress(button, value)
    local b = Badge(button)
    local size = QR.Size()
    b:SetSize(size, size)
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    local fs = b._zPrice
    if QR.ShowPrice() and value then
        if ns.ApplyFontSpec then ns.ApplyFontSpec(fs, DB().rewardMarkFont, QR.PRICE_FONT_DEFAULTS) end
        local c = GetColor("text", "coin")
        fs:SetTextColor(c.r, c.g, c.b, 1)
        fs:SetText(ns.Money and ns.Money(value, "short") or tostring(value))
        fs:Show()
    else
        fs:Hide()
    end
    b:Show()
end

local function Clear(button)
    if button._zRewardCoin then button._zRewardCoin:Hide() end
end

-- buttons: a list, each with .rindex (its choice index) - ZacUI's own
-- reward buttons (Win_Gossip, choosable ones) or Blizzard's (type "choice",
-- :GetID() as the index)
local waiting = false
local lastList
function QR.Mark(buttons)
    lastList = buttons
    if not QR.On() then
        for _, b in ipairs(buttons) do Clear(b) end
        return false
    end
    local best, missing, top = QR.Best()
    if missing then QR.WaitForPrices() end
    for _, b in ipairs(buttons) do
        local i = b.rindex or (b.GetID and b:GetID())
        if best and i and best[i] then QR.Dress(b, top) else Clear(b) end
    end
    return best ~= nil
end

-- ZacUI's own window hands over its pool after each draw
function QR.MarkOwn(pool)
    local list = {}
    for _, b in ipairs(pool or {}) do
        if b:IsShown() and b.kind == "item" and b.rtype == "choice" and b.choosable then list[#list + 1] = b end
        if b.kind ~= "item" or b.rtype ~= "choice" then Clear(b) end
    end
    return QR.Mark(list)
end

-- Blizzard's own reward frame
function QR.MarkBlizzard()
    local rf = _G.QuestInfoRewardsFrame
    local list = {}
    if rf and type(rf.RewardButtons) == "table" then
        for _, b in ipairs(rf.RewardButtons) do
            if b:IsShown() and b.type == "choice" then list[#list + 1] = b else Clear(b) end
        end
    else
        local n = type(GetNumQuestChoices) == "function" and GetNumQuestChoices() or 0
        for i = 1, (type(n) == "number" and n or 0) do
            local b = _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestInfoItem" .. i]
            if b and b:IsShown() then b.rindex = b.rindex or i list[#list + 1] = b end
        end
    end
    return QR.Mark(list)
end

-- a price was missing: once the client has the item, mark again
local ev = CreateFrame("Frame")
function QR.WaitForPrices()
    if waiting then return end
    waiting = true
    pcall(ev.RegisterEvent, ev, "ITEM_DATA_LOAD_RESULT")
    pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
end
local again = ns.Coalescer and ns.Coalescer(function()
    waiting = false
    pcall(ev.UnregisterEvent, ev, "ITEM_DATA_LOAD_RESULT")
    pcall(ev.UnregisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
    if lastList then QR.Mark(lastList) end
end, 0.2)
ev:SetScript("OnEvent", function() if again then again() end end)

if type(QuestInfo_Display) == "function" and hooksecurefunc then
    hooksecurefunc("QuestInfo_Display", function()
        if not QR.On() then return end
        -- ZacUI's own quest window covers Blizzard's: its buttons carry the mark
        local win = _G.ZacUIQuestDialogWindow
        if win and win.IsShown and win:IsShown() then return end
        pcall(QR.MarkBlizzard)
    end)
end

-- ============================================================
-- THE PAGE: a card on Game windows > General
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

AddTab("gamewindows", "general", "General", function(L)
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return end
    local UI = ns.UI
    local PK = ns.CorePageKit
    local d = DB()
    L:Card("Quest rewards")
    local on = UI.Checkbox(L.current, "Mark the reward that sells for most", QR.On(), function(v)
        d.rewardMark = v or nil
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "When a quest lets you choose a reward, a coin sits on the one with the highest vendor price "
        .. "(the item's sell price times how many you get). A tie marks each. On ZacUI's quest window and on "
        .. "the game's own." })
    L:Row(on, 17)
    -- a sample reward with the coin on it
    local row = UI.Holder(L.current)
    row:SetSize(200, 40)
    local sample = CreateFrame("Button", nil, row)
    sample:SetSize(140, 36)
    sample:EnableMouse(false)
    if UI.Fill then UI.Fill(sample, "ui", "elementBg") UI.Border(sample, "ui", "border") UI.PaintBox(sample) end
    local icon = sample:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", sample, "LEFT", 2, 0)
    icon:SetTexture("Interface\\Icons\\INV_Sword_04")
    ZacUI.Look.CropIcon(icon, 32, 32)
    local name = UI.Font(sample, UI.F.SMALL, { text = "Sample Sword" })
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    sample:SetPoint("LEFT", row, "LEFT", 0, 0)
    local function Draw() QR.Dress(sample, 12345) end
    Draw()
    L:Row(row, 44)
    local kids = {}
    kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 8, max = 32, step = 1,
        value = QR.Size(), label = "Coin size",
        format = function(v) return v .. " px" end,
        onChange = function(v) d.rewardMarkSize = (v ~= DEFAULT_SIZE) and v or nil Draw() end })
    kids[#kids + 1] = UI.Checkbox(L.current, "Show the price under the coin", QR.ShowPrice(), function(v)
        d.rewardMarkPrice = v or nil
        Draw()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end)
    L:Dependent(kids, QR.On(), 1, nil, "Mark the reward that sells for most")
    if PK and QR.ShowPrice() then
        PK.Font(L, "Price", DB, "rewardMarkFont", QR.PRICE_FONT_DEFAULTS, { sample = "1g 23s", after = Draw })
    end
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("gamewindows", "quest reward rewards coin vendor sell price value best mark")
end
