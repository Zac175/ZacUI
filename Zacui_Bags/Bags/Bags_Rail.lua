-- Bags_Rail - the bag window with a rail (2026-11-13, Zac picked it from
-- the bags mock: "a bit of a b and c ... an option to split bags up is
-- good i like the sidebar stuff", "a keyring is something we should have
-- 100%").
-- Part of ZacUI; load order is set by the TOC (after Bags_Frame, which
-- hands this file its window: Rail.Geo, Build, Attach, Layout, Paint,
-- Count are called from there and from nowhere else).
--
-- OFF UNTIL TICKED on an install from before (ZacUIDB.bags.rail, Bags >
-- Look, a reload); a fresh install starts with it. ZacUI's own look only:
-- under a game look the window is that look's, as it was.
--
-- WHAT IT IS
--   the rail      down the left of the window: the bags (the backpack,
--                 the four bag slots; the bank's own slots and its seven
--                 bag slots), the keyring, then the views
--   a bag         click it and its slots stay lit while the rest dim;
--                 again to clear. Drag it off to take the bag out, drop
--                 a bag on it to swap - as the bag row always did
--   the keyring   a key on the rail: the keyring's slots as a section of
--                 their own at the bottom (bags.railKeys). Only on a game
--                 version that has a keyring
--   the views     All (one grid), Kind (split up by kind: bags.layout =
--                 "groups", the Groups button's own setting), New (what
--                 the game still calls new; closing the window marks it
--                 seen), Alts (opens Bags_Alts' list; only while "alt
--                 bags" is on)
--   pinned        a row at the top for what you use most: drop an item
--                 on the "+" tile to pin it (again to take it out). By
--                 item id, in bags.pinned; "Hide" folds the row away
--   headings      every section under a quiet label with its count
--   free slots    in the Kind view, folded into one tile you drop onto
--   the count     "61 / 80" beside the title; the footer is the money's
--
-- NOTHING MOVES IN THE BAGS. A slot's button IS its slot (Bags_Frame: the
-- button's parent carries the bag, its id the slot), so every view only
-- changes where each button is drawn, or hides it. And nothing here is on
-- an item button's click path: pinning is a drop on our own tile, the
-- keyring's buttons are the same template with only their tooltip owned
-- (as the bank's own slots are, for the same reason).

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
local Bags = ns.Bags
local BL = ns.BagLook
if not (Bags and BL and BL.GroupOf) then return end

local UI = ns.UI
local Col, GetColor, FLAT = ns.Col, ns.GetColor, ns.FLAT
local M, F = UI.M, UI.F

local Rail = {}
Bags.Rail = Rail

local RAIL_W = 36           -- the rail's width
local PAD = 14              -- rail -> grid, grid -> window edge
local TOP = 10              -- title bar -> the first heading
local RBTN = 24             -- a bag on the rail
local RSTEP = 28
local VIEW_W, VIEW_H = 30, 20
local HEAD_H = 14           -- a section heading
local HEAD_GAP = 5          -- heading -> its slots
local SEC_GAP = 10          -- a section's slots -> the next heading
local KEY_ICON = "Interface\\Icons\\INV_Misc_Key_03"
local BANK_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local PACK_ICON = "Interface\\Buttons\\Button-Backpack-Up"

Rail.W, Rail.PAD = RAIL_W, PAD

local function Cfg() return BL.Cfg() end

-- the keyring's container id on a game version that has one (Classic
-- Era, TBC), nil elsewhere
local function Keyring()
    local id = _G.KEYRING_CONTAINER
    if type(id) ~= "number" then return nil end
    if type(_G.IsKeyRingEnabled) == "function" then
        local ok, on = pcall(_G.IsKeyRingEnabled)
        if ok and on == false then return nil end
    end
    return id
end
Rail.Keyring = Keyring

function Rail.Wanted(view)
    return Cfg().rail == true
end

function Rail.Geo(view)
    local foot = BL.FOOTER or 22
    return { l = RAIL_W + PAD, r = PAD, rowY = M.TITLEBAR + TOP, top = M.TITLEBAR + TOP,
        gridBottom = foot, bottom = foot + 8 }
end

-- an item's id: the pin key
local function ItemKey(item)
    if not item then return nil end
    return tonumber(item.itemID) or tonumber(item.id)
        or (type(item.link) == "string" and tonumber(item.link:match("item:(%d+)"))) or nil
end

local function Pinned()
    local c = Cfg()
    if type(c.pinned) ~= "table" then c.pinned = {} end
    return c.pinned
end

local function Relayout(view)
    view._layoutSig = nil
    view:Refresh()
end

local function AllViews(fn)
    for _, v in pairs(ns.BagViews or {}) do
        if v.rail then fn(v) end
    end
end

------------------------------------------------------------------------
-- The views
------------------------------------------------------------------------
local function NewItemsOK()
    return C_NewItems ~= nil and type(C_NewItems.IsNewItem) == "function"
end

-- "all" | "kind" | "new"
function Rail.Mode(view)
    if view.railNew and view.key == "inventory" and NewItemsOK() then return "new" end
    return (Cfg().layout == "groups") and "kind" or "all"
end

-- back to my own bags, when another character's are being looked at
local function LeaveAlt(view)
    local Alts = ns.BagAlts
    if view.altViewKey and Alts and Alts.ShowAlt and Alts.MyKey and view.altViewKey ~= Alts.MyKey() then
        Alts.ShowAlt(view, Alts.MyKey())
    end
end

function Rail.SetMode(view, mode)
    LeaveAlt(view)
    if mode == "new" then
        view.railNew = true
        Relayout(view)
        return
    end
    view.railNew = nil
    Cfg().layout = (mode == "kind") and "groups" or nil
    -- one setting for the bag and the bank, as the Groups button's was
    AllViews(function(v)
        if v ~= view then v.railNew = nil end
        Relayout(v)
    end)
end

-- Is this slot's item new? The game's own mark - and, once seen in the
-- New view, it stays listed until the window closes (the mark goes when
-- the mouse crosses the slot; the item must not jump away under it).
local function IsNew(view, bag, slot, item)
    if not item then return false end
    local keep = view.railNewKeep
    local key = bag * 1000 + slot
    local link = item.link or ItemKey(item)
    if keep and keep[key] == link then return true end
    local ok, isNew = pcall(C_NewItems.IsNewItem, bag, slot)
    if ok and isNew == true then
        keep = keep or {}
        view.railNewKeep = keep
        keep[key] = link
        return true
    end
    return false
end

------------------------------------------------------------------------
-- The rail
------------------------------------------------------------------------
-- a rail tile's edge (UI.Border's four strips): the accent while it is
-- the one picked, the palette's border otherwise
local function Edge(b, lit)
    local strips = b and b._zBorder
    if not strips then return end
    local c = lit and Col("accent") or GetColor(b._zBorderCat or "ui", b._zBorderKey or "border")
    for _, t in ipairs(strips) do t:SetVertexColor(c.r, c.g, c.b, lit and 1 or (c.a or 1)) end
end

local function PaintRail(view)
    for _, b in ipairs(view.railBags or {}) do
        local lit = view.railLit ~= nil and b._zBag == view.railLit
        Edge(b, lit)
        b._zLit = lit or nil
    end
    if view.railKey then
        local on = Cfg().railKeys == true
        Edge(view.railKey, on)
        view.railKey._zOn = on or nil
    end
    local mode = Rail.Mode(view)
    local viewingAlt = false
    do
        local Alts = ns.BagAlts
        viewingAlt = (view.altViewKey ~= nil and Alts ~= nil and Alts.MyKey ~= nil
            and view.altViewKey ~= Alts.MyKey()) or false
    end
    for id, b in pairs(view.railViews or {}) do
        if id == "alts" then b:SetActive(viewingAlt)
        else b:SetActive(not viewingAlt and mode == id) end
    end
end
Rail.PaintRail = PaintRail

-- A bag picked on the rail: its slots stay lit, the rest dim. The same
-- bag again (or nil) clears it.
function Rail.Light(view, bag)
    if bag == nil or view.railLit == bag then view.railLit = nil else view.railLit = bag end
    PaintRail(view)
    if view.frame:IsShown() then view:Paint() end
end

local function RailTip(btn, title, body)
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    local t = GetColor("tooltip", "title")
    GameTooltip:AddLine(title, t.r, t.g, t.b)
    if body then
        local c = GetColor("tooltip", "body")
        GameTooltip:AddLine(body, c.r, c.g, c.b, true)
    end
    GameTooltip:Show()
end

-- a square tile on the rail that is not a bag slot (the backpack, the
-- bank's own slots, the keyring)
local function RailTile(view, icon)
    local b = CreateFrame("Button", nil, view.frame)
    b:SetSize(RBTN, RBTN)
    b:RegisterForClicks("LeftButtonUp")
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex._zui_own = true
    tex:SetAllPoints()
    tex:SetTexture(icon)
    if ns.Look and ns.Look.CropIcon then ns.Look.CropIcon(tex, nil, nil, { part = "bags" }) end
    b._zIcon = tex
    pcall(UI.Border, b, "ui", "border")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl._zui_own = true
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function ViewButton(view, id, label, title, body)
    local b = UI.Button(view.railStrip, label, { width = VIEW_W, height = VIEW_H, size = F.SMALL })
    -- (the label spans the button: a button that owns its label's two
    -- points is not widened to it, and the rail is only so wide)
    b._zText:ClearAllPoints()
    b._zText:SetPoint("LEFT", b, "LEFT", 1, 0)
    b._zText:SetPoint("RIGHT", b, "RIGHT", -1, 0)
    b._zText:SetJustifyH("CENTER")
    b:SetWidth(VIEW_W)
    UI.Tooltip(b, title, body)
    view.railViews[id] = b
    return b
end

function Rail.Build(view)
    local frame = view.frame
    local isBank = view.key == "bank"

    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(M.TITLEBAR + 1))
    strip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    strip:SetWidth(RAIL_W)
    UI.Fill(strip, "sidebar", "bg")
    strip._zPaint = UI.PaintBox
    strip:_zPaint()
    local edge = strip:CreateTexture(nil, "ARTWORK")
    edge._zui_own = true
    edge:SetTexture(FLAT)
    edge:SetWidth(1) if ZacUI and ZacUI.Pixel then ZacUI.Pixel.Edge(edge, "LEFT") end
    edge:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
    edge:SetVertexColor(0, 0, 0, 1)
    view.railStrip = strip

    view.railBags, view.railViews = {}, {}
    view.bagSlots = {}
    local x = (RAIL_W - RBTN) / 2 + 1
    local y = -(M.TITLEBAR + 9)

    -- the first tile: the backpack (bag 0), or the bank's own slots
    local first = RailTile(view, isBank and BANK_ICON or PACK_ICON)
    first._zBag = isBank and Bags.BANK_CONTAINER or 0
    first:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    first:SetScript("OnClick", function(self) Rail.Light(view, self._zBag) end)
    first:SetScript("OnEnter", function(self)
        RailTip(self, isBank and "Bank" or "Backpack", "Click to light only what is in it. Click again to light everything.")
    end)
    view.packSlot = first
    view.railBags[#view.railBags + 1] = first
    y = y - RSTEP

    -- the bag slots: Bags_Frame's own buttons (drag a bag off, drop one
    -- on, buy a bank slot), with a plain click lighting the bag's slots
    local count = isBank and (Bags.NUM_BANKBAGSLOTS or 7) or 4
    for i = 1, count do
        local btn = BL.CreateBagSlot(view, i)
        btn:SetSize(RBTN, RBTN)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        btn._zBag = isBank and Bags.BANK_BAGS[i + 1] or i
        local baseClick, baseEnter = btn:GetScript("OnClick"), btn:GetScript("OnEnter")
        btn:SetScript("OnClick", function(self)
            local owned = isBank and (GetNumBankSlots and GetNumBankSlots() or 0) or count
            -- an item on the cursor goes into the bag, an unbought bank
            -- slot is bought: both as they always were
            if (CursorHasItem and CursorHasItem()) or self._zIndex > owned then
                if baseClick then baseClick(self) end
                return
            end
            if not self._zHasBag then return end
            Rail.Light(view, self._zBag)
        end)
        btn:SetScript("OnEnter", function(self)
            local owned = isBank and (GetNumBankSlots and GetNumBankSlots() or 0) or count
            if self._zIndex > owned or not self._zHasBag then
                if baseEnter then baseEnter(self) end
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self._zInv then GameTooltip:SetInventoryItem("player", self._zInv) end
            GameTooltip:AddLine("Click to light only what is in this bag. Drag it off to take it out; "
                .. "drop a bag here to swap it.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        view.bagSlots[i] = btn
        view.railBags[#view.railBags + 1] = btn
        y = y - RSTEP
    end

    -- the keyring
    if not isBank and Keyring() then
        local key = RailTile(view, KEY_ICON)
        key:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        key:SetScript("OnClick", function()
            local c = Cfg()
            c.railKeys = (c.railKeys ~= true) and true or nil
            Relayout(view)
        end)
        key:SetScript("OnEnter", function(self)
            RailTip(self, "Keyring", "Click to show your keys as a section of their own at the bottom. Click again to put them away.")
        end)
        view.railKey = key
        y = y - RSTEP
    end

    -- a hairline, then the views
    local rule = strip:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    rule:SetSize(RAIL_W - 14, 1)
    rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, y - 1)
    rule:SetVertexColor(1, 1, 1, 0.08)
    y = y - 9

    local vx = (RAIL_W - VIEW_W) / 2 + 1
    local function Place(b)
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", vx, y)
        y = y - (VIEW_H + 4)
    end
    local all = ViewButton(view, "all", "All", "All", "Every slot in one grid.")
    all:SetScript("OnClick", function() Rail.SetMode(view, "all") end)
    Place(all)
    local kind = ViewButton(view, "kind", "Kind", "By kind",
        "Split up by kind (consumables, gear, trade goods, quest items, the rest), with the free slots "
        .. "folded into one tile. Nothing moves in your bags: only where each slot is drawn.")
    kind:SetScript("OnClick", function() Rail.SetMode(view, "kind") end)
    Place(kind)
    if not isBank and NewItemsOK() then
        local new = ViewButton(view, "new", "New", "New",
            "Only what you have picked up and not looked at yet. Closing the bag marks it all as seen.")
        new:SetScript("OnClick", function() Rail.SetMode(view, "new") end)
        Place(new)
    end
    if not isBank then
        -- (Bags_Alts shows it while "alt bags" is on, and puts its list
        -- of characters under it)
        local alts = ViewButton(view, "alts", "Alts", "Another character's bags",
            "Their bags and bank as last seen, read-only. Pick yourself to get your own back.")
        alts:SetScript("OnClick", function()
            local dd = view.altDrop
            local open = dd and dd:GetScript("OnClick")
            if open then open(dd) end
        end)
        Place(alts)
        alts:Hide()
        view.railAlts = alts
    end
    -- the window is never shorter than its rail (measured from under
    -- the title bar)
    view.railMinH = (-y) - M.TITLEBAR + 6
    -- the tiles are the window's children, as the bag slots have to be:
    -- drawn above the rail's own fill
    local lvl = strip:GetFrameLevel() + 2
    for _, b in ipairs(view.railBags) do b:SetFrameLevel(lvl) end
    if view.railKey then view.railKey:SetFrameLevel(lvl) end
end

------------------------------------------------------------------------
-- The grid's own parts
------------------------------------------------------------------------
-- the keyring's tooltip: its slots are inventory slots to the tooltip,
-- as the bank's own are (Bags_Frame, BANK CONTAINER TOOLTIPS)
local function KeySlotEnter(self)
    -- (a new item's gold edge goes once the mouse has been over it, as
    -- on every other slot)
    local n = self._zNew
    if n then
        self._zNew = nil
        if C_NewItems and C_NewItems.RemoveNewItem then pcall(C_NewItems.RemoveNewItem, n[1], n[2]) end
    end
    local toInv = _G.KeyRingButtonIDToInvSlotID
    local inv
    if type(toInv) == "function" then
        local ok, v = pcall(toInv, self:GetID())
        if ok then inv = v end
    end
    local shown = false
    if inv then
        if GetInventoryItemID and not GetInventoryItemID("player", inv) then
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
            self.updateTooltip = nil
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetInventoryItem("player", inv)
        shown = true
    elseif Bags.Item(Keyring(), self:GetID()) then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(Keyring(), self:GetID())
        shown = true
    end
    if shown and GameTooltip:NumLines() > 0 then GameTooltip:Show() else GameTooltip:Hide() end
    self.updateTooltip = nil
end

local function KeyButton(view, slot)
    local key = Keyring()
    local had = view.buttons[key] and view.buttons[key][slot]
    local btn = view:Button(key, slot)
    if btn and not had then
        btn:SetScript("OnEnter", KeySlotEnter)
        btn.UpdateTooltip = KeySlotEnter
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return btn
end

-- how many keyring slots are drawn: the game's own count (the rows that
-- hold your keys), else every slot
local function KeySlots()
    local key = Keyring()
    if not key then return 0 end
    local n = Bags.Slots(key) or 0
    if type(_G.GetKeyRingSize) == "function" then
        local ok, size = pcall(_G.GetKeyRingSize)
        if ok and type(size) == "number" and size > 0 then n = math.min(n, size) end
    end
    return n
end
Rail.KeySlots = KeySlots

function Rail.Attach(view)
    local frame, grid = view.frame, view.grid
    view.railHeads = {}

    -- the keyring's holder (the id is the bag, as every holder's is)
    local key = view.key == "inventory" and Keyring() or nil
    if key then
        local holder = CreateFrame("Frame", nil, grid)
        holder:SetAllPoints()
        holder:SetID(key)
        view.holders[key] = holder
    end

    -- how full the bags are, beside the title
    if frame.titleBar and frame.titleText then
        local count = UI.Font(frame.titleBar, F.SMALL, { cat = "text", key = "gray" })
        count:SetPoint("LEFT", frame.titleText, "RIGHT", 8, -1)
        view.railCount = count
    end

    -- the "+" tile of the pinned row: drop an item on it
    if view.key == "inventory" then
        local plus = CreateFrame("Button", nil, grid)
        plus:SetFrameLevel(grid:GetFrameLevel() + 6)
        plus:RegisterForClicks("LeftButtonUp")
        local bg = plus:CreateTexture(nil, "BACKGROUND")
        bg._zui_own = true
        bg:SetAllPoints()
        bg:SetTexture(FLAT)
        plus._zBg = bg
        pcall(UI.Border, plus, "ui", "border")
        plus._zPlus = UI.Font(plus, F.TITLE, { text = "+", cat = "text", key = "gray" })
        plus._zPlus:SetPoint("CENTER", 0, 0)
        plus._zPaint = function(self)
            local e = Col("elementBg")
            self._zBg:SetVertexColor(e.r, e.g, e.b, 0.25)
            for _, t in ipairs(self._zBorder or {}) do t:SetVertexColor(1, 1, 1, self._zHot and 0.25 or 0.06) end
        end
        plus:_zPaint()
        local function Drop() Rail.PinCursor(view) end
        plus:SetScript("OnReceiveDrag", Drop)
        plus:SetScript("OnClick", Drop)
        plus:SetScript("OnEnter", function(self)
            self._zHot = true
            self:_zPaint()
            RailTip(self, "Pinned items", "Drop an item here to keep it in this row, whatever else the bag "
                .. "is showing. Drop a pinned item here to take it out again.")
        end)
        plus:SetScript("OnLeave", function(self)
            self._zHot = nil
            self:_zPaint()
            GameTooltip:Hide()
        end)
        plus:Hide()
        view.railPlus = plus
    end

    -- over the folded free tile: how many are free (it takes no mouse,
    -- so a drop lands on the slot under it)
    local over = CreateFrame("Frame", nil, grid)
    over:SetFrameLevel(grid:GetFrameLevel() + 20)
    over:EnableMouse(false)
    over.count = UI.Font(over, F.LABEL, { cat = "text", key = "gray" })
    over.count:SetPoint("CENTER", 0, 0)
    over.label = UI.Font(grid, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    over.label:SetText("empty slots - drop an item here")
    over:Hide()
    over.label:Hide()
    view.railFree = over

    -- the New view with nothing in it
    view.railNone = UI.Font(grid, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    view.railNone:SetText("Nothing new since you last looked.")
    view.railNone:Hide()

    frame:HookScript("OnHide", function()
        -- the New view was looked at: it is all seen now
        if view.railNew then
            view.railNew = nil
            if C_NewItems and C_NewItems.ClearAll then pcall(C_NewItems.ClearAll) end
        end
        view.railNewKeep = nil
        view.railLit = nil
        view._layoutSig = nil
    end)
    PaintRail(view)
end

-- Pins (or unpins) the item on the cursor and puts it back where it was.
function Rail.PinCursor(view)
    if not GetCursorInfo then return false end
    local kind, id = GetCursorInfo()
    if kind ~= "item" or not tonumber(id) then return false end
    id = tonumber(id)
    local pins = Pinned()
    pins[id] = (not pins[id]) and true or nil
    if ClearCursor then ClearCursor() end
    local c = Cfg()
    c.railPinsHidden = nil
    Relayout(view)
    return true
end

-- a section heading: its name, its count, a hairline (and, on the pinned
-- row's, the Hide / Show link at the right)
local function Head(view, i)
    local h = view.railHeads[i]
    if h then return h end
    h = CreateFrame("Frame", nil, view.grid)
    h:SetHeight(HEAD_H)
    h.name = UI.Font(h, F.SMALL, { cat = "text", key = "normal" })
    h.name:SetPoint("LEFT", 0, 0)
    h.count = UI.Font(h, F.SMALL, { cat = "text", key = "gray" })
    h.count:SetPoint("LEFT", h.name, "RIGHT", 6, 0)
    h.link = CreateFrame("Button", nil, h)
    h.link:SetHeight(HEAD_H)
    h.link.text = UI.Font(h.link, F.SMALL, { cat = "text", key = "gray" })
    h.link.text:SetPoint("RIGHT", 0, 0)
    h.link:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    h.link:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1, 1) end)
    h.link:SetScript("OnLeave", function(self) if self.text._zPaint then self.text:_zPaint() end end)
    h.line = h:CreateTexture(nil, "ARTWORK")
    h.line._zui_own = true
    h.line:SetTexture(FLAT)
    h.line:SetHeight(1) if ZacUI and ZacUI.Pixel then ZacUI.Pixel.Edge(h.line, "TOP") end
    h.line:SetPoint("LEFT", h.count, "RIGHT", 8, 0)
    view.railHeads[i] = h
    return h
end

------------------------------------------------------------------------
-- Layout
------------------------------------------------------------------------
-- the first free slot to stand for all of them: one in an ordinary bag
-- when there is one (a quiver's or a soul bag's takes only its own kind)
local function GeneralBag(bag)
    local fn = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
    if type(fn) ~= "function" then return true end
    local ok, _, family = pcall(fn, bag)
    if not ok then return true end
    return family == nil or family == 0
end

-- What the window shows, as lists of buttons. Also the signature: one
-- string that changes exactly when a button would be drawn elsewhere.
local function Model(view)
    local c = Cfg()
    local mode = Rail.Mode(view)
    local inv = view.key == "inventory"
    local pinsOn = inv and c.railPinsHidden ~= true
    local pins = inv and Pinned() or nil
    local m = { mode = mode, pinsOn = pinsOn, pinned = {}, all = {}, kinds = {}, free = {}, new = {}, hidden = {},
        keys = {}, used = 0, total = 0 }
    local sig = { mode, pinsOn and "P" or "-" }
    local GroupOf, FREE = BL.GroupOf, #BL.GROUP_NAMES
    for _, bag in ipairs(view.bagList) do
        local slots = Bags.Slots(bag)
        m.total = m.total + slots
        local general
        for slot = 1, slots do
            local btn = view:Button(bag, slot)
            if btn then
                local item = Bags.Item(bag, slot)
                local code
                if item then m.used = m.used + 1 end
                if pinsOn and item and pins[ItemKey(item) or 0] then
                    m.pinned[#m.pinned + 1] = btn
                    code = "p"
                elseif mode == "new" then
                    if IsNew(view, bag, slot, item) then
                        m.new[#m.new + 1] = btn
                        code = "n"
                    else
                        m.hidden[#m.hidden + 1] = btn
                        code = "."
                    end
                elseif mode == "kind" then
                    local g = GroupOf(item)
                    if g == FREE then
                        if general == nil then general = GeneralBag(bag) end
                        m.free[#m.free + 1] = { btn = btn, general = general }
                    else
                        m.kinds[g] = m.kinds[g] or {}
                        m.kinds[g][#m.kinds[g] + 1] = btn
                    end
                    code = tostring(g)
                else
                    m.all[#m.all + 1] = btn
                    code = "a"
                end
                sig[#sig + 1] = code
            end
        end
        sig[#sig + 1] = "|"
        -- slots that went when a smaller bag was equipped
        local list = view.buttons[bag]
        if list then
            for i = slots + 1, #list do m.hidden[#m.hidden + 1] = list[i] end
        end
    end
    -- the keyring
    local key = inv and Keyring() or nil
    if key then
        local on = c.railKeys == true
        local n = on and KeySlots() or 0
        m.keysOn, m.keyUsed = on, 0
        for slot = 1, n do
            local btn = KeyButton(view, slot)
            if btn then
                m.keys[#m.keys + 1] = btn
                if Bags.Item(key, slot) then m.keyUsed = m.keyUsed + 1 end
            end
        end
        local list = view.buttons[key]
        if list then
            for i = n + 1, #list do m.hidden[#m.hidden + 1] = list[i] end
        end
        -- (how many keys: the keyring's heading says it)
        sig[#sig + 1] = "k" .. n .. ":" .. m.keyUsed
    end
    -- (how full: the All view's heading says it)
    sig[#sig + 1] = "u" .. m.used
    m.sig = table.concat(sig)
    return m
end

function Rail.Layout(view, force)
    local c = Cfg()
    local cols = math.max(4, tonumber(c.columns) or 10)
    local size, gap = BL.SlotSize(), BL.SlotGap()
    local m = Model(view)
    local sig = cols .. ":" .. size .. ":" .. gap .. ":" .. m.sig
    if not force and sig == view._layoutSig then
        view._layoutPending = nil
        return true
    end

    local grid = view.grid
    local gridW = cols * size + (cols - 1) * gap
    local y, heads = 0, 0
    local rule = GetColor("text", "gray")

    local function Heading(name, count, link, onLink)
        heads = heads + 1
        local h = Head(view, heads)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
        h:SetWidth(gridW)
        h.name:SetText(name)
        h.count:SetText(count or "")
        h.line:ClearAllPoints()
        h.line:SetPoint("LEFT", h.count, "RIGHT", 8, 0)
        if link then
            h.link.text:SetText(link)
            h.link:SetWidth(math.max(20, math.ceil(h.link.text:GetStringWidth() or 20) + 2))
            h.link:SetScript("OnClick", onLink)
            h.link:Show()
            h.line:SetPoint("RIGHT", h.link, "LEFT", -8, 0)
        else
            h.link:Hide()
            h.line:SetPoint("RIGHT", h, "RIGHT", 0, 0)
        end
        h.line:SetVertexColor(rule.r, rule.g, rule.b, 0.22)
        h:Show()
        y = y + HEAD_H + HEAD_GAP
        return h
    end
    -- frames in a grid from the current y; returns how many rows it took
    local function Place(list, extra)
        local n = #list + (extra and 1 or 0)
        for i, btn in ipairs(list) do
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            btn:ClearAllPoints()
            btn:SetSize(size, size)
            btn:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (size + gap), -(y + row * (size + gap)))
            btn:Show()
            if btn._zCooldown and btn._zCooldown.Show then btn._zCooldown:Show() end
        end
        if extra then
            local i = n
            local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
            extra:ClearAllPoints()
            extra:SetSize(size, size)
            extra:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (size + gap), -(y + row * (size + gap)))
            extra:Show()
        end
        local rows = math.max(1, math.ceil(n / cols))
        y = y + rows * size + (rows - 1) * gap + SEC_GAP
    end

    for _, btn in ipairs(m.hidden) do btn:Hide() end

    -- pinned
    if view.railPlus then
        if m.pinsOn then
            Heading("Pinned", (#m.pinned > 0) and tostring(#m.pinned) or "", "Hide", function()
                Cfg().railPinsHidden = true
                Relayout(view)
            end)
            Place(m.pinned, view.railPlus)
        else
            Heading("Pinned", "", "Show", function()
                Cfg().railPinsHidden = nil
                Relayout(view)
            end)
            view.railPlus:Hide()
            y = y + SEC_GAP - HEAD_GAP
        end
    end

    -- the view
    local over = view.railFree
    over:Hide()
    over.label:Hide()
    view.railNone:Hide()
    if m.mode == "kind" then
        for g = 1, #BL.GROUP_NAMES - 1 do
            local list = m.kinds[g]
            if list and #list > 0 then
                Heading(BL.GROUP_NAMES[g], tostring(#list))
                Place(list)
            end
        end
        if #m.free > 0 then
            -- one tile for every free slot: the first in an ordinary bag
            local pick = m.free[1]
            for _, f in ipairs(m.free) do
                if f.general then pick = f break end
            end
            for _, f in ipairs(m.free) do
                if f ~= pick then f.btn:Hide() end
            end
            Heading("Free", tostring(#m.free))
            local top = y
            Place({ pick.btn })
            over:ClearAllPoints()
            over:SetAllPoints(pick.btn)
            over.count:SetText(tostring(#m.free))
            over:Show()
            over.label:ClearAllPoints()
            over.label:SetPoint("LEFT", grid, "TOPLEFT", size + 10, -(top + size / 2))
            over.label:Show()
        end
    elseif m.mode == "new" then
        Heading("New", tostring(#m.new))
        if #m.new > 0 then
            Place(m.new)
        else
            view.railNone:ClearAllPoints()
            view.railNone:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
            view.railNone:Show()
            y = y + 14 + SEC_GAP
        end
    else
        Heading(view.key == "bank" and "Bank" or "Bags", m.used .. " / " .. m.total)
        Place(m.all)
    end

    -- the keyring
    if m.keysOn then
        Heading("Keyring", m.keyUsed .. " / " .. #m.keys)
        if #m.keys > 0 then Place(m.keys) else y = y + SEC_GAP end
    end

    for i = heads + 1, #view.railHeads do view.railHeads[i]:Hide() end

    local geo = view.geo
    local w = geo.l + geo.r + gridW
    local h = geo.top + math.max(size, y - SEC_GAP) + geo.bottom
    h = math.max(h, M.TITLEBAR + (view.railMinH or 0))
    view.frame:SetSize(math.max(300, w), h)
    view._layoutSig = sig
    view._layoutPending = nil
    PaintRail(view)
    return true
end

------------------------------------------------------------------------
-- Paint
------------------------------------------------------------------------
-- The keyring's slots (the bags' own are Bags_Frame's) and the rail.
-- bags: the set of bags that changed, or nil for all; query: the search.
function Rail.Paint(view, bags, query)
    local key = view.key == "inventory" and Keyring() or nil
    local list = key and view.buttons[key]
    if list and Cfg().railKeys == true and (not bags or bags[key]) then
        for slot = 1, KeySlots() do
            local btn = list[slot]
            if btn then
                local item = Bags.Item(key, slot)
                if SetItemButtonCount then SetItemButtonCount(btn, item and item.count or 0) end
                local faded = (query ~= nil and not Bags.Matches(item, query, key, slot, false))
                    or (view.railLit ~= nil)
                BL.Paint(btn, item, false, faded)
            end
        end
    end
    PaintRail(view)
end

-- how full the bags are: on the title bar
function Rail.Count(view, free, total)
    if view.railCount then view.railCount:SetText((total - free) .. " / " .. total) end
end

-- Bags_Alts: its list of characters hangs off the rail's Alts button,
-- which is there while "alt bags" is on
function Rail.Alts(view, on)
    if view.railAlts then view.railAlts:SetShown(on and true or false) end
    PaintRail(view)
end
