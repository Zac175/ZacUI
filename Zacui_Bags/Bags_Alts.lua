-- Bags_Alts - your other characters, seen from this one: everyone's gold
-- as a list in the bag window's footer (with a "forget" per character),
-- every character's bags and bank remembered and browsable from the bag
-- window ("View: <character>"), and their counts on item tooltips.
-- Part of ZacUI; load order is set by the TOC (after Bags_Frame).
--
-- OFF UNTIL ASKED. Three switches on the Bags page (ZacUIDB.bags):
--   altGold   the "Alts" button in the footer and its list
--   altBags   bags and bank snapshots, the View dropdown
--   altTips   "Zacw: 3 in bags, 2 in the bank" on item tooltips (on
--             while altBags is on, unless switched off)
-- With all three off this file makes no frame, takes no snapshot and adds
-- no tooltip line; the bag window is exactly as it always was.
--
-- THE GOLD comes from Bags_Core's ledger (ZacUIDB.gold, written on every
-- PLAYER_MONEY and at logout, Readycheck's ledger when it is there), so
-- nothing is recorded twice; the list here is the same rows the footer
-- tooltip shows, with the forget button. A forgotten character goes on
-- Bags_Core's exclusion list (ZacUIDB.goldExclude), which is what keeps
-- it gone when Readycheck's table brings it back.
--
-- THE SNAPSHOTS (ZacUIDB.altBags, account-wide bookkeeping, outside every
-- profile) are lean on purpose: item id -> count, bags and bank apart,
-- never a link. The bags are read when the bag window closes, at logout
-- and a few seconds after login (a character who never opens the bag is
-- still recorded); the bank while it is open (closed, the bank's slots
-- read empty). Nothing runs inline in a bag event: the bag system's own
-- coalesced batch marks the bank dirty and a short timer takes the read.
--
-- SECRET-SAFE. Item ids and counts are never secret, but every id is
-- checked with ns.IsSecret before it becomes a table key all the same.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local Bags = ns.Bags
local UI = ns.UI
local Print = ns.Print
if not (Bags and UI) then return end

local M, F = UI.M, UI.F
local Alts = {}
ns.BagAlts = Alts

-- ============================================================
-- SETTINGS AND STORES
-- ============================================================
local function Cfg()
    if ns.BagLook and ns.BagLook.Cfg then return ns.BagLook.Cfg() end
    if not ZacUIDB then return {} end
    ZacUIDB.bags = ZacUIDB.bags or {}
    return ZacUIDB.bags
end
Alts.Cfg = Cfg

local function GoldOn() return Cfg().altGold == true end
local function BagsOn() return Cfg().altBags == true end
local function TipsOn() local c = Cfg() return c.altBags == true and c.altTips ~= false end
Alts.GoldOn, Alts.BagsOn, Alts.TipsOn = GoldOn, BagsOn, TipsOn

local function Store()
    ZacUIDB.altBags = ZacUIDB.altBags or {}
    return ZacUIDB.altBags
end
Alts.Store = Store

local function Realm()
    return (GetNormalizedRealmName and GetNormalizedRealmName())
        or (GetRealmName and GetRealmName()) or ""
end

-- the character's key: ZacUI's shared one when Core_Names is there (on
-- WoW Forever name + ruleset; elsewhere "Name-Realm"), else Name-Realm
local function KeyOf(name, realm)
    if ns.CharKey then return ns.CharKey("-", name, realm) end
    return tostring(name or "?") .. "-" .. tostring(realm or "")
end
local function MyKey()
    -- (WoW Forever: a snapshot saved under the realm key moves over once)
    if ns.CharKey then return ns.CharKey("-", UnitName("player"), Realm(), ZacUIDB.altBags) end
    return KeyOf(UnitName("player"), Realm())
end
Alts.MyKey = MyKey

-- ============================================================
-- SNAPSHOTS
-- ============================================================
local function ReadBags(list, out)
    local secret = ns.IsSecret
    for _, bag in ipairs(list) do
        local n = Bags.Slots(bag) or 0
        for slot = 1, n do
            local item = Bags.Item(bag, slot)
            if item then
                local id = item.itemID
                if not id and type(item.link) == "string" then
                    id = tonumber(item.link:match("item:(%d+)"))
                end
                if type(id) == "number" and not (secret and secret(id)) then
                    local count = tonumber(item.count) or 1
                    if secret and secret(item.count) then count = 1 end
                    out[id] = (out[id] or 0) + count
                end
            end
        end
    end
    return out
end

local function Record(kind, counts)
    if not BagsOn() then return end
    local name = UnitName and UnitName("player")
    if not name then return end
    local store = Store()
    local key = MyKey()
    local rec = store[key]
    if not rec then rec = {} store[key] = rec end
    local _, class = UnitClass("player")
    rec.name, rec.realm, rec.class = name, Realm(), class or rec.class
    rec.faction = UnitFactionGroup and UnitFactionGroup("player") or rec.faction
    rec.t = time()
    rec[kind] = counts
    Alts.changed = (Alts.changed or 0) + 1
end

local bankOpen = false
function Alts.SnapshotBags()
    if not BagsOn() then return false end
    Record("bags", ReadBags(Bags.BACKPACK_BAGS, {}))
    return true
end
function Alts.SnapshotBank()
    if not BagsOn() or not bankOpen then return false end
    -- a game version whose bank is not the Classic bank bags (Core_Flavor
    -- "bank": Retail) remembers bags only
    if ns.FeatureOn and not ns.FeatureOn("bank") then return false end
    Record("bank", ReadBags(Bags.BANK_BAGS, {}))
    return true
end

-- the bank is read a moment after its contents moved, once per burst
local bankTimer = false
local function BankSoon()
    if bankTimer or not bankOpen or not BagsOn() then return end
    bankTimer = true
    C_Timer.After(0.5, function()
        bankTimer = false
        Alts.SnapshotBank()
    end)
end

-- every character we know about, this one first, then by name
function Alts.List()
    local out = {}
    local me = MyKey()
    for key, rec in pairs(Store()) do
        if type(rec) == "table" then
            out[#out + 1] = { key = key, rec = rec, isMe = (key == me) }
        end
    end
    table.sort(out, function(a, b)
        if a.isMe ~= b.isMe then return a.isMe end
        return tostring(a.rec.name) < tostring(b.rec.name)
    end)
    return out
end

-- who else holds this item: { { name, class, bags, bank }, ... }, by name
function Alts.Holders(itemID)
    local out = {}
    if type(itemID) ~= "number" then return out end
    local me = MyKey()
    for key, rec in pairs(Store()) do
        if key ~= me and type(rec) == "table" then
            local b = rec.bags and rec.bags[itemID] or 0
            local k = rec.bank and rec.bank[itemID] or 0
            if b > 0 or k > 0 then
                out[#out + 1] = { name = rec.name or key, class = rec.class, bags = b, bank = k }
            end
        end
    end
    table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return out
end

-- a character gone for good: its gold row (Bags_Core's exclusion list,
-- which also beats Readycheck's table bringing it back) and its bags
function Alts.Forget(name, realm)
    if not name then return end
    ZacUIDB.goldExclude = ZacUIDB.goldExclude or {}
    local gk = Bags.GoldKey and Bags.GoldKey(name, realm) or (tostring(name) .. "-" .. tostring(realm or ""))
    ZacUIDB.goldExclude[gk] = true
    ZacUIDB.goldExclude[(string.lower(gk):gsub("%s+", ""))] = true
    if type(ZacUIDB.gold) == "table" then ZacUIDB.gold[gk] = nil end
    local store = Store()
    store[KeyOf(name, realm)] = nil
    for key, rec in pairs(store) do
        if type(rec) == "table" and rec.name == name and (rec.realm or "") == (realm or "") then store[key] = nil end
    end
    if Bags.GoldChanged then Bags.GoldChanged() end
    Alts.changed = (Alts.changed or 0) + 1
    if Alts.RefreshViews then Alts.RefreshViews() end
end

-- ============================================================
-- ITEM FACTS (icon, quality, name) from the id alone, cached per session
-- ============================================================
local facts = {}
local function Facts(id)
    local f = facts[id]
    if f then return f end
    f = { id = id }
    local instant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if instant then
        local ok, _, _, _, _, icon = pcall(instant, id)
        if ok then f.icon = icon end
    end
    local info = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
    if info then
        local ok, name, link, quality = pcall(info, id)
        if ok and name then
            f.name, f.link, f.quality = name, link, quality
        else
            f.pending = true     -- GET_ITEM_INFO_RECEIVED repaints
        end
    end
    f.icon = f.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    facts[id] = f
    return f
end

-- ============================================================
-- THE TOOLTIP LINES
-- ============================================================
local function TipItemID(tt, data)
    if type(data) == "table" and type(data.id) == "number" then return data.id end
    if tt and tt.GetItem then
        local ok, _, link = pcall(tt.GetItem, tt)
        if ok and type(link) == "string" then return tonumber(link:match("item:(%d+)")) end
    end
    return nil
end

local function AddTipLines(tt, data)
    if not TipsOn() then return end
    local id = TipItemID(tt, data)
    if not id or (ns.IsSecret and ns.IsSecret(id)) then return end
    -- the same tooltip set twice for the same item (the bag buttons refresh
    -- theirs on every bag event) gets the lines once
    local n = tt.NumLines and tt:NumLines() or 0
    if tt._zAltId == id and tt._zAltLines == n then return end
    local holders = Alts.Holders(id)
    if #holders == 0 then tt._zAltId, tt._zAltLines = nil, nil return end
    local g = ns.GetColor and ns.GetColor("text", "gray") or { r = 0.6, g = 0.6, b = 0.6 }
    for _, h in ipairs(holders) do
        local r, gg, b = 1, 1, 1
        if h.class and ns.ClassColor then r, gg, b = ns.ClassColor(h.class) end
        local parts = {}
        if h.bags > 0 then parts[#parts + 1] = h.bags .. " in bags" end
        if h.bank > 0 then parts[#parts + 1] = h.bank .. " in the bank" end
        tt:AddDoubleLine(h.name, table.concat(parts, ", "), r, gg, b, g.r, g.g, g.b)
    end
    tt._zAltId, tt._zAltLines = id, (tt.NumLines and tt:NumLines() or 0)
    if tt.Show then tt:Show() end
end
Alts.AddTipLines = AddTipLines

local tipsHooked = false
local function HookTooltips()
    if tipsHooked then return end
    tipsHooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            if tt == GameTooltip or tt == ItemRefTooltip then AddTipLines(tt, data) end
        end)
        return
    end
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HookScript and (not tt.HasScript or tt:HasScript("OnTooltipSetItem")) then
            pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) AddTipLines(self, nil) end)
        end
    end
end

-- a sample tooltip, for the Bags page's Test button: what the lines look
-- like, whatever has been recorded
function Alts.SampleTooltip(owner)
    if not (GameTooltip and owner) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Major Healing Potion", 1, 1, 1)
    GameTooltip:AddLine("Use: Restores 1050 to 1750 health.", 0, 1, 0, true)
    local g = ns.GetColor and ns.GetColor("text", "gray") or { r = 0.6, g = 0.6, b = 0.6 }
    local sample = {
        { name = "Zacw", class = "WARRIOR", bags = 5, bank = 20 },
        { name = "Thanda", class = "PRIEST", bags = 0, bank = 12 },
        { name = "Noob", class = "MAGE", bags = 3, bank = 0 },
    }
    for _, h in ipairs(sample) do
        local r, gg, b = 1, 1, 1
        if ns.ClassColor then r, gg, b = ns.ClassColor(h.class) end
        local parts = {}
        if h.bags > 0 then parts[#parts + 1] = h.bags .. " in bags" end
        if h.bank > 0 then parts[#parts + 1] = h.bank .. " in the bank" end
        GameTooltip:AddDoubleLine(h.name, table.concat(parts, ", "), r, gg, b, g.r, g.g, g.b)
    end
    GameTooltip:Show()
end

-- ============================================================
-- THE BAG WINDOW: the Alts list and the View dropdown
-- ============================================================
local attached = {}       -- view -> true

-- the bag window's look (Bags_Frame's kit): nil under ZacUI's own look,
-- else the game look's stock widget art on these pieces too
local function KitOn()
    local BL = ns.BagLook
    return BL and BL.Kit and BL.Kit() or nil
end

local function Hide(f) if f then f:Hide() end end

-- the gold list: one row per character, most gold first (Bags_Core's
-- rows), with a forget X on everyone but the character you are on
local function BuildGoldPanel(view)
    if view.altGoldPanel then return view.altGoldPanel end
    local frame = view.frame
    local panel = UI.Box(frame, "ui", "windowBg", { alpha = 0.97 })
    panel:SetFrameLevel((frame:GetFrameLevel() or 1) + 12)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 26)
    panel:SetSize(260, 40)
    panel:EnableMouse(true)
    panel:Hide()
    panel.rows = {}
    panel.title = UI.Font(panel, F.SMALL, { text = "Gold across your characters", cat = "text", key = "gold" })
    panel.title:SetPoint("TOPLEFT", 8, -6)
    panel.total = UI.Font(panel, F.SMALL, { justify = "RIGHT" })
    panel.total:SetPoint("TOPRIGHT", -8, -6)
    panel.note = UI.Font(panel, F.DESC, { cat = "text", key = "gray" })
    panel.note:SetPoint("BOTTOMLEFT", 8, 5)
    if KitOn() then
        ns.BagLook.KitBox(panel)
        ns.BagLook.KitFont(panel.title, 11)
        panel.title:SetTextColor(1, 0.82, 0, 1)
    end
    view.altGoldPanel = panel
    return panel
end

local ROW_H = 16
local function FillGoldPanel(view)
    local panel = BuildGoldPanel(view)
    local rows, total = Bags.GoldRows()
    local n = 0
    for _, r in ipairs(rows) do
        if not r.isPost then
            n = n + 1
            local row = panel.rows[n]
            if not row then
                row = CreateFrame("Frame", nil, panel)
                row:SetHeight(ROW_H)
                row:SetPoint("LEFT", 8, 0)
                row:SetPoint("RIGHT", -8, 0)
                row.name = UI.Font(row, F.SMALL, { justify = "LEFT" })
                row.name:SetPoint("LEFT", 0, 0)
                row.name:SetWidth(120)
                row.name:SetWordWrap(false)
                row.gold = UI.Font(row, F.SMALL, { justify = "RIGHT" })
                row.gold:SetPoint("RIGHT", -22, 0)
                row.x = UI.CloseX(row, 14, function(self)
                    local rec = self:GetParent().rec
                    if rec then Alts.Forget(rec.name, rec.realm) end
                end)
                row.x:SetPoint("RIGHT", 0, 0)
                local kit = KitOn()
                if kit then ns.BagLook.KitClose(row.x, kit, 16) end
                UI.Tooltip(row.x, "Forget this character", "Takes them out of the gold total and the remembered bags. "
                    .. "They come back the next time you log in on them.")
                panel.rows[n] = row
            end
            row.rec = r
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -22 - (n - 1) * ROW_H)
            local cr, cg, cb = 1, 1, 1
            if r.class and ns.ClassColor then cr, cg, cb = ns.ClassColor(r.class) end
            local label = r.name or "?"
            if r.isMe then label = label .. " (here)" end
            row.name:SetText(label)
            row.name:SetTextColor(cr, cg, cb)
            row.gold:SetText(ns.Money(r.copper or 0, true))
            row.x:SetShown(not r.isMe)
            row:Show()
        end
    end
    for i = n + 1, #panel.rows do panel.rows[i]:Hide() end
    panel.total:SetText(ns.Money(total or 0, true))
    panel.note:SetText(Bags.FromReadycheck and Bags.FromReadycheck()
        and "Other accounts come from Readycheck's gold sync."
        or "Other WoW accounts are not visible to addons.")
    panel:SetHeight(22 + math.max(1, n) * ROW_H + 20)
end

local function ToggleGoldPanel(view)
    local panel = BuildGoldPanel(view)
    if panel:IsShown() then panel:Hide() return end
    FillGoldPanel(view)
    panel:Show()
end

-- the "Alts" button beside the account total
local function BuildGoldButton(view)
    if view.altGoldBtn then return view.altGoldBtn end
    local b = UI.Button(view.frame, "Alts", { width = 36, height = 16, size = F.SMALL,
        tooltip = "Everyone's gold, with a forget button per character.",
        onClick = function() ToggleGoldPanel(view) end })
    if view.totalText then
        b:SetPoint("RIGHT", view.totalText, "LEFT", -8, 0)
    else
        b:SetPoint("BOTTOMLEFT", view.frame, "BOTTOMLEFT", 120, 5)
    end
    if KitOn() then ns.BagLook.KitButton(b) end
    view.altGoldBtn = b
    return b
end

-- ------------------------------------------------------------
-- the View dropdown and the read-only grid of another character's items
-- ------------------------------------------------------------
local function Viewing(view) return view.altViewKey and view.altViewKey ~= MyKey() and view.altViewKey or nil end

local function AltSlot(view, i)
    local list = view.altSlots
    local btn = list[i]
    if btn then return btn end
    local BL = ns.BagLook
    btn = BL.NewSample(view.altGrid)
    btn:EnableMouse(true)
    btn:SetScript("OnEnter", function(self)
        local id = self._zAltItem
        if not id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = false
        if GameTooltip.SetItemByID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, id) end
        if not ok and GameTooltip.SetHyperlink then pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. id) end
        if self._zAltOwner then
            local g = ns.GetColor and ns.GetColor("text", "gray") or { r = 0.6, g = 0.6, b = 0.6 }
            GameTooltip:AddLine(self._zAltOwner, g.r, g.g, g.b)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    list[i] = btn
    return btn
end

local function SortedItems(counts)
    local out = {}
    for id, n in pairs(counts or {}) do
        local f = Facts(id)
        out[#out + 1] = { id = id, count = n, f = f }
    end
    table.sort(out, function(a, b)
        local qa, qb = a.f.quality or -1, b.f.quality or -1
        if qa ~= qb then return qa > qb end
        local na, nb = a.f.name or "", b.f.name or ""
        if na ~= nb then return na < nb end
        return a.id < b.id
    end)
    return out
end

local function LayoutAlt(view)
    local key = Viewing(view)
    local rec = key and Store()[key]
    if not rec then return end
    local BL = ns.BagLook
    local cfg = Cfg()
    local cols = math.max(4, tonumber(cfg.columns) or 10)
    local size, gap = BL.SlotSize(), BL.SlotGap()
    local grid = view.altGrid
    local used = 0
    local y = 0
    local owner = (rec.name or "?") .. "'s"
    local function Place(items, label)
        if #items == 0 then return end
        if label then
            local fs = view.altLabels[label]
            if not fs then
                fs = UI.Font(grid, F.SMALL, { cat = "text", key = "gray", text = label })
                view.altLabels[label] = fs
            end
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y - 2)
            fs:Show()
            y = y + 16
        end
        for i, it in ipairs(items) do
            used = used + 1
            local btn = AltSlot(view, used)
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            btn:SetSize(size, size)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (size + gap), -(y + row * (size + gap)))
            local f = it.f
            BL.Paint(btn, { icon = f.icon, count = it.count, quality = f.quality, link = f.link or ("item:" .. it.id), itemID = it.id }, false, false)
            if btn._zCount then btn._zCount:SetText(it.count > 1 and tostring(it.count) or "") end
            btn._zAltItem = it.id
            btn._zAltOwner = owner .. " " .. (label and "bank" or "bags")
            btn:Show()
        end
        y = y + math.ceil(#items / cols) * (size + gap)
    end
    for _, fs in pairs(view.altLabels) do fs:Hide() end
    Place(SortedItems(rec.bags), nil)
    Place(SortedItems(rec.bank), "Bank")
    for i = used + 1, #view.altSlots do view.altSlots[i]:Hide() end
    if used == 0 then
        local fs = view.altLabels.empty
        if not fs then
            fs = UI.Font(grid, F.SMALL, { cat = "text", key = "gray", text = "Nothing recorded yet" })
            view.altLabels.empty = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -4)
        fs:Show()
        y = 20
    end
    -- the window fits what it shows (the live layout puts its own size
    -- back when you return to your own bags)
    local PAD, HEADER, FOOTER = 10, 56, 22
    -- (the window's own spots: ZacUI's, or the client's bag's under its chrome)
    local geo = view.geo or { l = PAD, r = PAD, top = M.TITLEBAR + HEADER, bottom = FOOTER + 6 }
    local w = geo.l + geo.r + cols * size + (cols - 1) * gap
    local h = geo.top + math.max(y - gap, size) + geo.bottom
    view.frame:SetSize(math.max(300, w), h)
    local ago = rec.t and (time() - rec.t) or nil
    local when = ago and ((ago < 60 and "just now") or (ago < 3600 and (math.floor(ago / 60) .. " min ago"))
        or (ago < 86400 and (math.floor(ago / 3600) .. " h ago")) or (math.floor(ago / 86400) .. " days ago")) or ""
    view.altNote:SetText((rec.name or "?") .. "'s bags and bank, " .. when)
end

local function ShowAlt(view, key)
    local frame = view.frame
    -- the live grid holds the real slots; in secure mode they are
    -- protected and cannot be hidden in a fight
    if InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        Print("bags: another character's bags can't be shown in combat.")
        return false
    end
    view.altViewKey = key
    if Viewing(view) then
        view.grid:Hide()
        view.altGrid:Show()
        view.freeText:Hide()
        view.altNote:Show()
        LayoutAlt(view)
    else
        view.altGrid:Hide()
        view.grid:Show()
        view.altNote:Hide()
        view.freeText:Show()
        if view.Layout then view:Layout(true) end
        if view.Paint and frame:IsShown() then view:Paint() end
    end
    if view.altDrop and view.altDrop.SetText then view.altDrop:SetText(Alts.ViewLabel(view)) end
    return true
end
Alts.ShowAlt = ShowAlt

function Alts.ViewLabel(view)
    local key = Viewing(view)
    local rec = key and Store()[key]
    return "View: " .. ((rec and rec.name) or (UnitName and UnitName("player")) or "me")
end

local function BuildViewDrop(view)
    if view.altDrop then return view.altDrop end
    local frame = view.frame
    view.altSlots, view.altLabels = {}, {}
    local grid = CreateFrame("Frame", nil, frame)
    for i = 1, view.grid:GetNumPoints() do grid:SetPoint(view.grid:GetPoint(i)) end
    grid:Hide()
    view.altGrid = grid
    local note = UI.Font(frame, F.SMALL, { cat = "text", key = "gray" })
    if view.coinBand then
        note:SetPoint("LEFT", view.coinBand, "LEFT", 8, 0)
    else
        note:SetPoint("BOTTOMLEFT", 10, 7)
    end
    note:Hide()
    view.altNote = note
    local dd = UI.Dropdown(frame, { width = 150,
        items = function()
            local items = { { text = "Me (" .. ((UnitName and UnitName("player")) or "?") .. ")", value = MyKey() } }
            for _, e in ipairs(Alts.List()) do
                if not e.isMe then
                    local r, g, b = 1, 1, 1
                    if e.rec.class and ns.ClassColor then r, g, b = ns.ClassColor(e.rec.class) end
                    items[#items + 1] = { text = string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255,
                        e.rec.name or e.key), value = e.key }
                end
            end
            return items
        end,
        selected = function() return Alts.ViewLabel(view) end,
        selectedValue = function() return view.altViewKey or MyKey() end,
        onSelect = function(v) ShowAlt(view, v) end })
    dd:SetHeight(22)
    local last = view.bagSlots and view.bagSlots[#view.bagSlots]
    if last then
        dd:SetPoint("TOP", last, "TOP", 0, 0)
        dd:SetPoint("RIGHT", frame, "RIGHT", -((view.geo and view.geo.r) or 10), 0)
    else
        dd:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -(M.TITLEBAR + 30))
    end
    if dd.SetText then dd:SetText(Alts.ViewLabel(view)) end
    if KitOn() then ns.BagLook.KitDropdown(dd) end
    UI.Tooltip(dd, "Another character's bags", "Their bags and bank as last seen, read-only. "
        .. "Pick yourself to get your own back.")
    view.altDrop = dd
    return dd
end

-- the window dressed for the switches as they stand now
local function Dress(view)
    if not (view and view.frame) then return end
    if view.key == "inventory" then
        if BagsOn() then
            BuildViewDrop(view):Show()
            if Viewing(view) then LayoutAlt(view) end
        elseif view.altDrop then
            if Viewing(view) then ShowAlt(view, MyKey()) end
            view.altDrop:Hide()
        end
        if GoldOn() then
            BuildGoldButton(view):Show()
            if view.altGoldPanel and view.altGoldPanel:IsShown() then FillGoldPanel(view) end
        else
            Hide(view.altGoldBtn)
            Hide(view.altGoldPanel)
        end
    end
    if not attached[view] then
        attached[view] = true
        view.frame:HookScript("OnHide", function()
            Hide(view.altGoldPanel)
            if view.key == "inventory" then Alts.SnapshotBags() end
        end)
    end
end

function Alts.RefreshViews()
    local views = ns.BagViews
    if type(views) ~= "table" then return end
    for _, view in pairs(views) do Dress(view) end
end

-- ============================================================
-- EVENTS - none of them hot: the bag system's coalesced batch, the bank
-- opening and closing, the login and the logout
-- ============================================================
local started = false
local function Start()
    if started then return end
    started = true
    Bags.Subscribe(function(batch)
        -- windows built after this file loaded (the module's apply pass)
        -- are dressed the first time they are heard from
        local views = ns.BagViews
        if type(views) == "table" then
            for _, view in pairs(views) do
                if not attached[view] then Dress(view) end
            end
        end
        if not BagsOn() then return end
        if bankOpen and batch and (batch.full or batch.bags) then
            local touched = batch.full
            if not touched then
                for _, bag in ipairs(Bags.BANK_BAGS) do if batch.bags[bag] then touched = true end end
            end
            if touched then BankSoon() end
        end
        -- another character's grid stays current while it is up
        local inv = type(views) == "table" and views.inventory
        if inv and Viewing(inv) and inv.frame:IsShown() then LayoutAlt(inv) end
    end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("BANKFRAME_OPENED")
    ev:RegisterEvent("BANKFRAME_CLOSED")
    pcall(ev.RegisterEvent, ev, "PLAYER_LOGOUT")
    pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
    local infoTimer = false
    ev:SetScript("OnEvent", function(_, event)
        if event == "GET_ITEM_INFO_RECEIVED" then
            -- an item's name or quality arrived: the alt grid repaints once
            if infoTimer then return end
            local views = ns.BagViews
            local inv = type(views) == "table" and views.inventory
            if not (inv and Viewing(inv) and inv.frame:IsShown()) then return end
            infoTimer = true
            C_Timer.After(0.3, function()
                infoTimer = false
                for id, f in pairs(facts) do if f.pending then facts[id] = nil end end
                if inv and Viewing(inv) and inv.frame:IsShown() then LayoutAlt(inv) end
            end)
            return
        end
        if event == "BANKFRAME_OPENED" then
            bankOpen = true
            BankSoon()
        elseif event == "BANKFRAME_CLOSED" then
            bankOpen = false
        elseif event == "PLAYER_LOGOUT" then
            Alts.SnapshotBags()
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(3, function()
                Alts.SnapshotBags()
                Alts.RefreshViews()
            end)
        end
    end)
end

-- the switches as they stand: hooks and frames are made the first time
-- a switch is on, never before
function Alts.Apply()
    if BagsOn() or GoldOn() then Start() end
    if TipsOn() then HookTooltips() end
    Alts.RefreshViews()
end

-- ============================================================
-- THE BAGS PAGE: one card, General tab
-- ============================================================
function Alts.Card(L)
    local Kit = ns.CorePageKit
    if not (L and Kit) then return end
    L:Card("Your other characters")
    Kit.Check(L, "Everyone's gold in the footer", Cfg, "altGold",
        "An Alts button beside the account total opens the list: each character in their class colour, "
        .. "their gold, and an x to forget one.", { after = Alts.Apply })
    Kit.Check(L, "Remember every character's bags and bank", Cfg, "altBags",
        "Taken when you close the bag, open the bank and log out. The bag window gets a View dropdown "
        .. "to browse another character's items, read-only.", { after = Alts.Apply })
    local tips = UI.Checkbox(L.current, "Their counts on item tooltips", TipsOn(), function(v)
        Cfg().altTips = v and true or false
        Alts.Apply()
    end, { tooltip = "\"Zacw: 5 in bags, 20 in the bank\" under any item another character holds." })
    L:Dependent({ tips }, BagsOn(), 1, nil, "Remember every character's bags and bank")
    local n = 0
    for _ in pairs(Store()) do n = n + 1 end
    L:Desc(n == 0 and "No character recorded yet." or (n .. (n == 1 and " character recorded." or " characters recorded.")))
    Kit.Buttons(L, {
        { "Record now", 110, function()
            if not BagsOn() then Print("bags: turn on \"Remember every character's bags and bank\" first.") return end
            Alts.SnapshotBags()
            if bankOpen then Alts.SnapshotBank() end
            Print("bags: this character's bags recorded.")
            if ns.RefreshConfig then ns.RefreshConfig() end
        end, "Takes this character's bag snapshot now (the bank too while it is open)." },
        { "Sample tooltip", 120, function(self) Alts.SampleTooltip(self) end,
          "Shows what the tooltip lines look like." },
    })
    L:EndCard()
end

-- the card joins the Bags page's General tab (ns.AddPageTab: the page
-- itself is not touched)
if ns.AddPageTab then ns.AddPageTab("bags", "general", "General", function(L) Alts.Card(L) end) end
if ns.AddMenuKeywords then ns.AddMenuKeywords("bags", "alts characters gold ledger bank tooltip counts") end

-- the module may already have built the windows (ApplyAll runs before a
-- part's later files only on a reload); otherwise the first bag batch or
-- the login timer dresses them
Alts.Apply()
if ns.OnSettingsChanged and ns.Coalesce then
    ns.OnSettingsChanged(ns.Coalesce(function() Alts.Apply() end))
end
