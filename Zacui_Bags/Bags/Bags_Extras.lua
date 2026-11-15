-- Bags_Extras - two small texts on the bag window's gear slots:
--   Item level   the item level of a piece of gear, bottom left, in its
--                quality's colour (only gear: armour, weapons, rings,
--                trinkets; never bags, shirts, tabards, ammo)
--   BoE          "BoE" at the top of gear that binds when equipped and is
--                not bound yet: what you can still sell or hand on
-- Each its own switch, both off by default (Bags > General, "Text on gear").
-- Part of ZacUI (the bags part); load order is set by the TOC.
--
-- HOW: the bag window calls Bags.SlotExtra(btn, item, bag, slot) after it
-- paints a slot (one line in Bags_Frame). With both switches off it
-- returns at once and makes nothing. An item's facts (gear or not, item
-- level, how it binds) are read once per item link and kept for the
-- session; whether it is bound is the slot's own fact (the container's
-- isBound), read only while the BoE text is on. A client whose container
-- calls do not say "bound" shows no BoE text rather than a wrong one.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
local Bags = ns.Bags
if not Bags then return end

local BX = {}
Bags.Extras = BX

local OWN_ID = "bag_item_text"
BX.FONT_DEFAULTS = { size = 11, outline = "outline", shadow = false }
-- equip locations that are not gear for this purpose
local NOT_GEAR = { INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_BODY = true, INVTYPE_TABARD = true,
    INVTYPE_AMMO = true, INVTYPE_NON_EQUIP_IGNORE = true, [""] = true }
local BIND_ON_EQUIP = 2

local function Hidden(v) return ns.IsSecret and ns.IsSecret(v) or false end

-- ============================================================
-- SETTINGS (bags.itemText; nothing saved = off)
-- ============================================================
local EMPTY = {}
local function Cfg()
    local b = ZacUIDB and ZacUIDB.bags
    return type(b) == "table" and type(b.itemText) == "table" and b.itemText or EMPTY
end
local function Writable()
    ZacUIDB.bags = type(ZacUIDB.bags) == "table" and ZacUIDB.bags or {}
    local b = ZacUIDB.bags
    if type(b.itemText) ~= "table" then b.itemText = {} end
    return b.itemText
end
BX.Cfg, BX.Writable = Cfg, Writable
local function Allowed() return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) end
function BX.Level() return Allowed() and Cfg().level == true end
function BX.BoE() return Allowed() and Cfg().boe == true end
function BX.MinQuality() return tonumber(Cfg().minQuality) or 0 end

-- ============================================================
-- THE FACTS
-- ============================================================
local facts = {}      -- link -> { gear = bool, ilvl = n, bind = n }
function BX.Facts(link)
    if type(link) ~= "string" or Hidden(link) then return nil end
    local f = facts[link]
    if f then return f end
    local GI = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if type(GI) ~= "function" then return nil end
    local name, _, _, ilvl, _, _, _, _, equipLoc, _, _, _, _, bindType = GI(link)
    if not name then return nil end          -- not cached yet: asked again next paint
    if type(GetDetailedItemLevelInfo) == "function" then
        local d = GetDetailedItemLevelInfo(link)
        if type(d) == "number" and d > 0 then ilvl = d end
    end
    f = { gear = not NOT_GEAR[equipLoc or ""], ilvl = tonumber(ilvl) or 0, bind = tonumber(bindType) or 0 }
    facts[link] = f
    return f
end
function BX.Forget() wipe(facts) end

local function Bound(bag, slot)
    local C = _G.C_Container
    if not (C and C.GetContainerItemInfo) then return nil end
    local info = C.GetContainerItemInfo(bag, slot)
    if type(info) ~= "table" then return nil end
    if info.isBound == nil or Hidden(info.isBound) then return nil end
    return info.isBound == true
end

-- ============================================================
-- THE TEXTS ON A SLOT
-- ============================================================
local function Font(fs)
    if ns.ApplyFontSpec then ns.ApplyFontSpec(fs, Cfg().font, BX.FONT_DEFAULTS)
    elseif ns.HouseFont then ns.HouseFont(fs, 11, "OUTLINE")
    else fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "OUTLINE") end
end

local function Texts(btn)
    if btn._zIlvl then return btn._zIlvl, btn._zBoe end
    local lv = btn:CreateFontString(nil, "OVERLAY")
    lv:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 2)
    lv:SetJustifyH("LEFT")
    local bo = btn:CreateFontString(nil, "OVERLAY")
    bo:SetPoint("TOP", btn, "TOP", 0, -2)
    btn._zIlvl, btn._zBoe = lv, bo
    return lv, bo
end

local function QualityRGB(q)
    if ns.QualityRGB then return ns.QualityRGB(q) end
    local c = _G.ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

function BX.Paint(btn, item, bag, slot)
    local wantLv, wantBoe = BX.Level(), BX.BoE()
    if not (wantLv or wantBoe) then
        if btn._zIlvl then btn._zIlvl:Hide() btn._zBoe:Hide() end
        return
    end
    local lv, bo = Texts(btn)
    local f = item and BX.Facts(item.link) or nil
    local q = item and item.quality
    local gear = f and f.gear
    if wantLv and gear and f.ilvl > 1 and type(q) == "number" and not Hidden(q) and q >= BX.MinQuality() then
        Font(lv)
        lv:SetText(tostring(f.ilvl))
        lv:SetTextColor(QualityRGB(q))
        lv:Show()
    else
        lv:Hide()
    end
    if wantBoe and gear and f.bind == BIND_ON_EQUIP and bag and slot and Bound(bag, slot) == false then
        Font(bo)
        bo:SetText("BoE")
        local c = ns.GetColor and ns.GetColor("text", "green") or { r = 0.12, g = 1, b = 0 }
        bo:SetTextColor(c.r, c.g, c.b)
        bo:Show()
    else
        bo:Hide()
    end
end

if Allowed() then
    function Bags.SlotExtra(btn, item, bag, slot) BX.Paint(btn, item, bag, slot) end
end

local function Repaint()
    if ns.BagLook and ns.BagLook.Changed then pcall(ns.BagLook.Changed) end
end
BX.Repaint = Repaint

-- ============================================================
-- THE CARD: Bags > General
-- ============================================================
BX.QUALITIES = {
    { value = 0, text = "Every quality" },
    { value = 2, text = "Green and up" },
    { value = 3, text = "Blue and up" },
    { value = 4, text = "Purple and up" },
}
function BX.Card(L)
    if not Allowed() then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    L:Card("Text on gear")
    local function Changed()
        Repaint()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end
    local a = UI.Checkbox(L.current, "Show the item level on gear", BX.Level(), function(v)
        Writable().level = v and true or nil
        Changed()
    end, { tooltip = "Armour, weapons, rings and trinkets show their item level in the bottom corner of the slot, in the item's colour." })
    L:Row(a, 17)
    local q = UI.Field(L.current, "Item level on", function(h)
        return UI.Dropdown(h, { width = 160,
            items = function() return BX.QUALITIES end,
            selectedValue = function() return BX.MinQuality() end,
            selected = function()
                for _, m in ipairs(BX.QUALITIES) do if m.value == BX.MinQuality() then return m.text end end
                return BX.QUALITIES[1].text
            end,
            onSelect = function(v) Writable().minQuality = (v ~= 0) and v or nil Repaint() end })
    end, { width = 160 })
    L:Dependent({ q }, BX.Level(), 1, nil, "Show the item level on gear")
    local b = UI.Checkbox(L.current, "Mark gear that binds when equipped", BX.BoE(), function(v)
        Writable().boe = v and true or nil
        Changed()
    end, { tooltip = "\"BoE\" at the top of gear that is not bound to you yet: what you can still sell or hand on." })
    L:Row(b, 17)
    if Kit then
        local view = setmetatable({}, { __index = function(_, k) return Cfg()[k] end,
            __newindex = function(_, k, v) Writable()[k] = v end })
        Kit.Font(L, "Text", function() return view end, "font", BX.FONT_DEFAULTS,
            { sample = "115  BoE", after = function() Repaint() end })
    end
    L:EndCard()
end
if Allowed() and ns.AddPageTab then ns.AddPageTab("bags", "general", "General", function(L) BX.Card(L) end) end

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("bags", "item level ilvl gear boe bind on equip bound text slot")
end
