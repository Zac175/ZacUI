-- QoL_JunkItems - a small window of the cheapest junk in your bags, for
-- when the bags are full: the stacks worth least at a vendor, cheapest
-- first, each with what it sells for under its icon.
--   Ctrl + left click   delete that stack (grey: at once; white / green:
--                       a second Ctrl + click within 3 seconds)
--   Middle click        never list that item again (Quality of life > Loot
--                       has the list, to take one back)
--   Hover               the item's own tooltip
-- Off by default: this window can delete items. Quality of life > Loot.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT IS LISTED: stacks of grey quality (or up to white / green, a
-- setting), never a quest item, never one you excluded; at most N stacks
-- (4 by default, up to 6), cheapest stack first. Shown always, or only
-- while fewer than N bag slots are free (5 by default) - the moment it is
-- needed. With nothing to list it hides.
--
-- THE LOOK: ZacUI's panel; a title row with "Junk" and the free slots
-- (orange when low); 32 px icons 20 px apart, the price under each cut to
-- whole silver (copper only under a gold). A mover places it (the middle
-- of the screen by default).
--
-- COST: nothing while off. On: the bags read again a moment after they
-- change (BAG_UPDATE_DELAYED starts one short timer, nothing in BAG_UPDATE),
-- and when an item's price arrives.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local Print = ns.Print
local QoL = ns.QoL
if not QoL then return end

local J = {}
QoL.Junk = J

local OWN_ID = "junk_items"
local MOVER = "qoljunk"
local MAX_CELLS = 6
local ICON, GAP, PAD, TITLE_H, PRICE_H = 32, 20, 10, 24, 12
local CONFIRM_FOR = 3          -- seconds a second Ctrl + click has
local READ_DELAY = 0.3
J.DEFAULTS = { count = 4, quality = 0, onlyLow = false, threshold = 5 }
J.QUALITIES = {
    { value = 0, text = "Grey only" },
    { value = 1, text = "Grey and white" },
    { value = 2, text = "Up to green" },
}

local function Hidden(v) return ns.IsSecret and ns.IsSecret(v) or false end

-- ============================================================
-- SETTINGS (qol.junk; nothing saved = off)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.junk) ~= "table" then q.junk = {} end
    return q.junk
end
J.DB = DB
local function Allowed() return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) end
function J.On() return Allowed() and QoL.enabled == true and DB().enabled == true end
local function Num(key, lo, hi)
    local v = tonumber(DB()[key]) or J.DEFAULTS[key]
    return math.max(lo, math.min(hi, v))
end
function J.Count() return Num("count", 1, MAX_CELLS) end
function J.Quality() return Num("quality", 0, 2) end
function J.Threshold() return Num("threshold", 1, 100) end
function J.OnlyLow() return DB().onlyLow == true end
function J.Excluded(id) local x = DB().exclude return type(x) == "table" and x[id] == true end

-- ============================================================
-- THE BAGS
-- ============================================================
local NUM_BAGS = _G.NUM_BAG_SLOTS or 4

local function SlotInfo(bag, slot)
    local C = _G.C_Container
    if C and type(C.GetContainerItemInfo) == "function" then
        local t = C.GetContainerItemInfo(bag, slot)
        if type(t) ~= "table" then return nil end
        return t.itemID, t.stackCount, t.quality, t.iconFileID, t.isLocked, t.hyperlink
    end
    if type(GetContainerItemInfo) == "function" then
        local tex, count, locked, quality, _, _, link, _, _, id = GetContainerItemInfo(bag, slot)
        return id, count, quality, tex, locked, link
    end
    return nil
end
local function NumSlots(bag)
    local C = _G.C_Container
    if C and type(C.GetContainerNumSlots) == "function" then return C.GetContainerNumSlots(bag) or 0 end
    if type(GetContainerNumSlots) == "function" then return GetContainerNumSlots(bag) or 0 end
    return 0
end
local function FreeSlots(bag)
    local C = _G.C_Container
    local free, family
    if C and type(C.GetContainerNumFreeSlots) == "function" then free, family = C.GetContainerNumFreeSlots(bag)
    elseif type(GetContainerNumFreeSlots) == "function" then free, family = GetContainerNumFreeSlots(bag) end
    return tonumber(free) or 0, family
end

-- free / total regular slots (special bags - quivers, soul bags - left out)
function J.Space()
    local free, total = 0, 0
    for bag = 0, NUM_BAGS do
        local f, family = FreeSlots(bag)
        if not family or family == 0 then
            free = free + f
            total = total + NumSlots(bag)
        end
    end
    return free, total
end

-- an item's sell price, class: nil while the client has not got it
local waiting = {}
local function ItemFacts(id)
    local name, _, _, _, _, _, _, _, _, _, price, classID
    if C_Item and type(C_Item.GetItemInfo) == "function" then
        name, _, _, _, _, _, _, _, _, _, price, classID = C_Item.GetItemInfo(id)
    elseif GetItemInfo then
        name, _, _, _, _, _, _, _, _, _, price, classID = GetItemInfo(id)
    end
    if not name then waiting[id] = true return nil end
    return tonumber(price) or 0, classID
end
local QUEST_CLASS = (_G.Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12

-- the cheapest listable stacks: { bag, slot, id, count, quality, icon, value }
function J.Scan()
    local out = {}
    local maxQ = J.Quality()
    for bag = 0, NUM_BAGS do
        for slot = 1, NumSlots(bag) do
            local id, count, quality, icon, locked = SlotInfo(bag, slot)
            if id and not Hidden(id) and not Hidden(quality) and type(quality) == "number"
                and quality <= maxQ and not locked and not J.Excluded(id) then
                local price, classID = ItemFacts(id)
                if price and classID ~= QUEST_CLASS then
                    count = (not Hidden(count) and tonumber(count)) or 1
                    out[#out + 1] = { bag = bag, slot = slot, id = id, count = count, quality = quality,
                        icon = icon, value = price * count }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.value ~= b.value then return a.value < b.value end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    local n = J.Count()
    for i = #out, n + 1, -1 do out[i] = nil end
    return out
end

-- "1g 15s" (cut to whole silver); copper only under a gold; "0c" for nothing
function J.Money(c)
    c = math.floor(tonumber(c) or 0)
    local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return s > 0 and string.format("%dg %ds", g, s) or string.format("%dg", g) end
    if s > 0 then return cp > 0 and string.format("%ds %dc", s, cp) or string.format("%ds", s) end
    return string.format("%dc", cp)
end

-- ============================================================
-- THE WINDOW
-- ============================================================
local win
local cells = {}
local list = {}
local armed, armedAt        -- the cell a second Ctrl + click deletes

local function QualityRGB(q)
    local c = _G.ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 0.62, 0.62, 0.62
end

local function Font(fs, size)
    if ns.HouseFont then ns.HouseFont(fs, size, "OUTLINE")
    else fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE") end
end

function J.Delete(e)
    if not e or InCombatLockdown and InCombatLockdown() then return false end
    local id = SlotInfo(e.bag, e.slot)
    if id ~= e.id then return false end   -- the bags moved since: nothing
    local C = _G.C_Container
    local pick = (C and C.PickupContainerItem) or _G.PickupContainerItem
    if type(pick) ~= "function" or type(DeleteCursorItem) ~= "function" then return false end
    if ClearCursor then ClearCursor() end
    pick(e.bag, e.slot)
    if CursorHasItem and not CursorHasItem() then return false end
    DeleteCursorItem()
    return true
end

local function CellClick(self, button)
    local e = list[self.index]
    if not e then return end
    if button == "MiddleButton" then
        local d = DB()
        if type(d.exclude) ~= "table" then d.exclude = {} end
        d.exclude[e.id] = true
        J.Refresh()
        return
    end
    if button ~= "LeftButton" or not (IsControlKeyDown and IsControlKeyDown()) then return end
    local now = GetTime()
    if e.quality > 0 and not (armed == self and armedAt and now - armedAt <= CONFIRM_FOR) then
        armed, armedAt = self, now
        if self._zArm then self._zArm:Show() end
        return
    end
    armed, armedAt = nil, nil
    if self._zArm then self._zArm:Hide() end
    if J.Delete(e) then C_Timer.After(READ_DELAY, J.Refresh) end
end

local function Cell(i)
    if cells[i] then return cells[i] end
    local UI = ns.UI
    local b = CreateFrame("Button", nil, win)
    b:SetSize(ICON, ICON)
    b.index = i
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    if ZacUI and ZacUI.Look and ZacUI.Look.CropIcon then ZacUI.Look.CropIcon(icon)
    else icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    b._zIcon = icon
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0.62, 0.62, 0.62, 1)
    b._zEdge = edge
    local count = b:CreateFontString(nil, "OVERLAY")
    Font(count, 11)
    count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b._zCount = count
    local price = b:CreateFontString(nil, "OVERLAY")
    Font(price, 10)
    price:SetPoint("TOP", b, "BOTTOM", 0, -2)
    b._zPrice = price
    local arm = b:CreateTexture(nil, "OVERLAY")
    arm:SetAllPoints()
    arm:SetColorTexture(1, 0.2, 0.2, 0.35)
    arm:Hide()
    b._zArm = arm
    b:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
    b:SetScript("OnClick", CellClick)
    b:SetScript("OnEnter", function(self)
        local e = list[self.index]
        if not e or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if GameTooltip.SetBagItem then GameTooltip:SetBagItem(e.bag, e.slot) end
        GameTooltip:AddLine("Ctrl + click: delete.  Middle click: never list it.", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    cells[i] = b
    return b
end

local function Window()
    if win then return win end
    local UI = ns.UI
    win = CreateFrame("Frame", "ZacUIJunkItems", UIParent)
    win:SetFrameStrata("MEDIUM")
    win:SetClampedToScreen(true)
    if UI then
        UI.Fill(win, "ui", "windowBg")
        UI.Border(win, "ui", "border")
        if UI.PaintBox then UI.PaintBox(win) end
    end
    local title = win:CreateFontString(nil, "OVERLAY")
    Font(title, 12)
    title:SetPoint("LEFT", win, "TOPLEFT", PAD, -TITLE_H / 2)
    title:SetText("Junk")
    local gold = GetColor("text", "gold")
    title:SetTextColor(gold.r, gold.g, gold.b)
    win._zTitle = title
    local space = win:CreateFontString(nil, "OVERLAY")
    Font(space, 10)
    space:SetPoint("RIGHT", win, "TOPRIGHT", -PAD, -TITLE_H / 2)
    win._zSpace = space
    win:Hide()
    win:ClearAllPoints()
    win:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    if ns.ApplyMover then ns.ApplyMover(MOVER) end
    return win
end
J.Frame = function() return win end
J.Cells = function() return cells end
J.List = function() return list end

-- fills the window from the bags; shows or hides it
function J.Refresh(test)
    if not J.On() and not test then
        if win then win:Hide() end
        return 0
    end
    local free, total = J.Space()
    local lowNow = free < J.Threshold()
    list = test and J.SampleList() or J.Scan()
    local show = #list > 0 and (test or not J.OnlyLow() or lowNow)
    if not show then
        if win then win:Hide() end
        return #list
    end
    Window()
    local n = #list
    local w = PAD * 2 + n * ICON + (n - 1) * GAP
    -- the title row must fit "Junk" and the count
    win:SetSize(math.max(w, 150), TITLE_H + ICON + 2 + PRICE_H + PAD)
    local c = lowNow and GetColor("text", "orange") or GetColor("text", "gray")
    win._zSpace:SetText(string.format("%d / %d free", free, total))
    win._zSpace:SetTextColor(c.r, c.g, c.b)
    for i = 1, MAX_CELLS do
        local e = list[i]
        if e then
            local b = Cell(i)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + (i - 1) * (ICON + GAP), -TITLE_H)
            b._zIcon:SetTexture(e.icon)
            b._zEdge:SetColorTexture(QualityRGB(e.quality))
            b._zCount:SetText(e.count > 1 and tostring(e.count) or "")
            b._zPrice:SetText(J.Money(e.value))
            if armed ~= b then b._zArm:Hide() end
            b:Show()
        elseif cells[i] then
            cells[i]:Hide()
        end
    end
    win:Show()
    return n
end

-- the Test button's stacks (made-up: three greys and a white)
function J.SampleList()
    local Q = "Interface\\Icons\\"
    return {
        { bag = 0, slot = 1, id = 0, count = 1, quality = 0, icon = Q .. "INV_Misc_Bone_01", value = 3 },
        { bag = 0, slot = 2, id = 0, count = 5, quality = 0, icon = Q .. "INV_Misc_Pelt_Wolf_Ruin_01", value = 12 },
        { bag = 0, slot = 3, id = 0, count = 1, quality = 0, icon = Q .. "INV_Misc_Gem_Variety_01", value = 104 },
        { bag = 0, slot = 4, id = 0, count = 1, quality = 1, icon = Q .. "INV_Misc_Food_15", value = 200 },
    }
end
function J.Test()
    J.Refresh(true)
    C_Timer.After(6, function() J.Refresh() end)
end

-- ============================================================
-- EVENTS: armed while on
-- ============================================================
local ev
local pending = false
local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(READ_DELAY, function()
        pending = false
        pcall(J.Refresh)
    end)
end
J.Schedule = Schedule
local function OnEvent(_, event, id)
    if event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
        if not waiting[id] then return end
        waiting[id] = nil
    end
    Schedule()
end

function J.Apply()
    if not J.On() then
        if ev then ev:UnregisterAllEvents() end
        if win then win:Hide() end
        return
    end
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", OnEvent)
    end
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
    pcall(ev.RegisterEvent, ev, "ITEM_DATA_LOAD_RESULT")
    Schedule()
end
function J.Armed() return ev ~= nil and ev:IsEventRegistered("BAG_UPDATE_DELAYED") or false end

local function Live() if QoL.enabled then J.Apply() end end
J.Live = Live
if Allowed() then
    if ns.RegisterMover then
        ns.RegisterMover(MOVER, "Junk items", function() return win end, "CENTER", 0, -120, nil, { own = true })
    end
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        pcall(J.Apply)
    end
end

-- ============================================================
-- THE PAGE: Quality of life > Loot
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local l = ns.PageTabs[page] or {}
    ns.PageTabs[page] = l
    l[#l + 1] = { tab = tab, label = label, build = build }
end

AddTab("qol", "loot", "Loot", function(L)
    if not Allowed() then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    local d = DB()
    L:Card("Junk items window")
    local on = UI.Checkbox(L.current, "Show the cheapest junk in my bags", d.enabled == true, function(v)
        d.enabled = v and true or nil
        Live()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "A small window of the stacks in your bags worth least at a vendor, cheapest first, with their "
        .. "price. Ctrl + click deletes a stack (white and green ask for a second Ctrl + click); middle click never lists that item again." })
    L:Row(on, 17)
    local kids = {}
    kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 1, max = MAX_CELLS, step = 1,
        value = J.Count(), label = "Stacks shown",
        onChange = function(v) d.count = (v ~= J.DEFAULTS.count) and v or nil Live() end })
    kids[#kids + 1] = UI.Field(L.current, "Quality", function(h)
        return UI.Dropdown(h, { width = 160,
            items = function() return J.QUALITIES end,
            selectedValue = function() return J.Quality() end,
            selected = function()
                for _, m in ipairs(J.QUALITIES) do if m.value == J.Quality() then return m.text end end
                return J.QUALITIES[1].text
            end,
            onSelect = function(v) d.quality = (v ~= 0) and v or nil Live() end })
    end, { width = 160 })
    kids[#kids + 1] = UI.Checkbox(L.current, "Only when my bags are nearly full", J.OnlyLow(), function(v)
        d.onlyLow = v and true or nil
        Live()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "Hidden until fewer bag slots than the number below are free." })
    kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 1, max = 30, step = 1,
        value = J.Threshold(), label = "Free slots under",
        onChange = function(v) d.threshold = (v ~= J.DEFAULTS.threshold) and v or nil Live() end })
    kids[#kids + 1] = UI.Button(L.current, "Test", { width = 80,
        tooltip = "Shows the window with made-up stacks for a few seconds.",
        onClick = function() J.Test() end })
    L:Dependent(kids, d.enabled == true, 1, nil, "Show the cheapest junk in my bags")
    if Kit and Kit.Mover and ns.MOVERS and ns.MOVERS[MOVER] then Kit.Mover(L, MOVER, "the window") end
    -- the never-list list
    local ex = type(d.exclude) == "table" and d.exclude or {}
    local ids = {}
    for id in pairs(ex) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids > 0 then
        L:Desc("Never listed (click one to list it again):")
        local row = {}
        for _, id in ipairs(ids) do
            local name = (GetItemInfo and GetItemInfo(id)) or ("item " .. id)
            row[#row + 1] = UI.Button(L.current, name, { width = 150,
                onClick = function()
                    d.exclude[id] = nil
                    if not next(d.exclude) then d.exclude = nil end
                    Live()
                    if ns.RefreshConfig then ns.RefreshConfig() end
                end })
        end
        if L.Flow then L:Flow(row) else for _, b in ipairs(row) do L:Row(b, 26) end end
    end
    if not QoL.enabled then L:Desc("The Quality of life part is not running, so this is not either.") end
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "junk grey gray trash delete destroy cheapest bag space full vendor price items window")
end
