-- Bags_Extras - two small texts on the bag window's gear slots:
--   Item level   the item level of a piece of gear, bottom left, in its
--                quality's colour (only gear: armour, weapons, rings,
--                trinkets; never bags, shirts, tabards, ammo)
--   BoE          "BoE" at the top of gear that binds when equipped and is
--                not bound yet: what you can still sell or hand on
-- Each its own switch, both off by default (Bags > General, "Text on gear").
--   Cannot use   (2026-11-24) an item you cannot use - the wrong class or
--                armour, too high a level, a skill you lack, a recipe you
--                cannot learn or already know - has its icon tinted (red
--                unless you pick another colour). Its own switch, off by
--                default (Bags > General, "Items you cannot use"). Known
--                by what the game itself prints in red on the item's
--                tooltip, read once per item and kept until your level,
--                skills or spells change. A broken item's red durability
--                line does not count.
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

-- ============================================================
-- ITEMS YOU CANNOT USE (bags.unusableTint; nothing saved = off)
-- ============================================================
BX.UNUSABLE_COLOR = { r = 1, g = 0.25, b = 0.25 }
local function BagCfg() local b = ZacUIDB and ZacUIDB.bags return type(b) == "table" and b or EMPTY end
function BX.TintOn() return Allowed() and BagCfg().unusableTint == true end
function BX.TintKnown() return BagCfg().unusableKnown ~= false end
function BX.TintColor()
    local c = BagCfg().unusableColor
    if type(c) ~= "table" then c = BX.UNUSABLE_COLOR end
    return c.r or c[1] or 1, c.g or c[2] or 0.25, c.b or c[3] or 0.25
end

-- the game's red (RED_FONT_COLOR is 1, 0.125, 0.125)
local function IsRed(r, g, b)
    return type(r) == "number" and type(g) == "number" and type(b) == "number" and r > 0.95 and g < 0.2 and b < 0.2
end
local durabilityHead
local function Ignored(text)
    -- a broken item's "Durability 0 / 60" is red too: the item is still yours to use
    if durabilityHead == nil then
        local t = _G.DURABILITY_TEMPLATE
        durabilityHead = type(t) == "string" and t:match("^(.-)%s*%%") or false
        if durabilityHead == "" then durabilityHead = false end
    end
    if durabilityHead and text:sub(1, #durabilityHead) == durabilityHead then return true end
    if not BX.TintKnown() and text == _G.ITEM_SPELL_KNOWN then return true end
    return false
end

local scanTip
local function ScanTip()
    if scanTip == nil then
        local okT, t = pcall(CreateFrame, "GameTooltip", "ZacUIBagScanTip", nil, "GameTooltipTemplate")
        scanTip = okT and t or false
    end
    return scanTip or nil
end

-- true / false, or nil while the item's tooltip is not there to read
local function Scan(link)
    -- the newer clients hand a tooltip's lines over as data
    local TI = _G.C_TooltipInfo
    if TI and type(TI.GetHyperlink) == "function" then
        local okD, data = pcall(TI.GetHyperlink, link)
        local lines = okD and type(data) == "table" and data.lines
        if type(lines) ~= "table" or #lines == 0 then return nil end
        for _, line in ipairs(lines) do
            for _, side in ipairs({ { line.leftText, line.leftColor }, { line.rightText, line.rightColor } }) do
                local text, c = side[1], side[2]
                if Hidden(text) or Hidden(c) then return nil end
                if type(text) == "string" and text ~= "" and type(c) == "table" then
                    local r, g, b = c.r, c.g, c.b
                    if Hidden(r) or Hidden(g) or Hidden(b) then return nil end
                    if IsRed(r, g, b) and not Ignored(text) then return true end
                end
            end
        end
        return false
    end
    local tip = ScanTip()
    if not (tip and tip.SetHyperlink) then return nil end
    tip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    if not pcall(tip.SetHyperlink, tip, link) then return nil end
    local n = tip:NumLines() or 0
    if n == 0 then return nil end
    for i = 1, n do
        for _, side in ipairs({ "TextLeft", "TextRight" }) do
            local fs = _G["ZacUIBagScanTip" .. side .. i]
            local text = fs and fs:GetText()
            if Hidden(text) then return nil end
            if type(text) == "string" and text ~= "" and (side == "TextLeft" or fs:IsShown()) then
                local r, g, b = fs:GetTextColor()
                if Hidden(r) then return nil end
                if IsRed(r, g, b) and not Ignored(text) then return true end
            end
        end
    end
    return false
end

local unusable = {}    -- link -> true / false
function BX.Unusable(link)
    if type(link) ~= "string" or Hidden(link) then return false end
    local u = unusable[link]
    if u ~= nil then return u end
    local okS, got = pcall(Scan, link)
    if not okS or got == nil then return false end     -- not readable yet: asked again next paint
    unusable[link] = got
    return got
end
function BX.ForgetUsable() wipe(unusable) end

function BX.PaintUsable(btn, item)
    local icon = btn._zIcon
    if not icon then return end
    if BX.TintOn() and item and BX.Unusable(item.link) then
        icon:SetVertexColor(BX.TintColor())
        btn._zCannotUse = true
    elseif btn._zCannotUse then
        icon:SetVertexColor(1, 1, 1)
        btn._zCannotUse = nil
    end
end

if Allowed() then
    function Bags.SlotExtra(btn, item, bag, slot)
        BX.Paint(btn, item, bag, slot)
        BX.PaintUsable(btn, item)
    end
end

local function Repaint()
    if ns.BagLook and ns.BagLook.Changed then pcall(ns.BagLook.Changed) end
end
BX.Repaint = Repaint

-- What you can use changes with your level, your skills and the recipes
-- you know: the answers are thrown away then and the open window painted
-- again, once, half a second after the last such event. Listened for only
-- while the tint is on.
local watch, watchQueued
local WATCH = { "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "NEW_RECIPE_LEARNED" }
function BX.ApplyWatch()
    local on = BX.TintOn()
    if on and not watch then
        watch = CreateFrame("Frame")
        watch:SetScript("OnEvent", function()
            if watchQueued then return end
            watchQueued = true
            C_Timer.After(0.5, function()
                watchQueued = false
                BX.ForgetUsable()
                if BX.TintOn() then Repaint() end
            end)
        end)
    end
    if not watch then return end
    for _, e in ipairs(WATCH) do
        if on then pcall(watch.RegisterEvent, watch, e) else pcall(watch.UnregisterEvent, watch, e) end
    end
end
if Allowed() then
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        BX.ApplyWatch()
    end)
end

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

    -- ITEMS YOU CANNOT USE
    L:Card("Items you cannot use")
    local function BagTable()
        ZacUIDB.bags = type(ZacUIDB.bags) == "table" and ZacUIDB.bags or {}
        return ZacUIDB.bags
    end
    local t = UI.Checkbox(L.current, "Tint items you cannot use", BX.TintOn(), function(v)
        BagTable().unusableTint = v and true or nil
        BX.ApplyWatch()
        Changed()
    end, { tooltip = "The wrong class or armour, too high a level, a skill you do not have, a recipe you cannot learn: "
        .. "whatever the game prints in red on the item's tooltip. The icon takes the colour below." })
    L:Row(t, 17)
    if Kit then
        local col = Kit.Color(L, "Tint", BagTable, "unusableColor", function()
            return BX.UNUSABLE_COLOR.r, BX.UNUSABLE_COLOR.g, BX.UNUSABLE_COLOR.b, 1
        end, { after = Repaint })
        local known = UI.Checkbox(L.current, "Recipes you already know count too", BX.TintKnown(), function(v)
            BagTable().unusableKnown = (not v) and false or nil
            BX.ForgetUsable()
            Changed()
        end, { tooltip = "A recipe, pattern or plan the game marks \"Already known\" is tinted as well." })
        L:Row(known, 17)
        -- (both already have their rows: dimmed while the tick is off, not laid out again)
        if UI.SetEnabled then
            local why = 'Needs "Tint items you cannot use" turned on.'
            UI.SetEnabled(col, BX.TintOn(), why)
            UI.SetEnabled(known, BX.TintOn(), why)
        end
    end
    L:EndCard()
end
if Allowed() and ns.AddPageTab then ns.AddPageTab("bags", "general", "General", function(L) BX.Card(L) end) end

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("bags", "item level ilvl gear boe bind on equip bound text slot "
        .. "unusable cannot use red tint class armor level requirement recipe known learn")
end
