-- Chat_LDB - other addons' LibDataBroker objects as blocks on ZacUI's
-- chat bar: a Broker addon's text and icon, its click, its tooltip.
-- Part of ZacUI; load order is set by the TOC (after Blz_Chat, whose bar
-- it docks onto).
--
-- WHAT A BLOCK IS. Any LibDataBroker-1.1 data object (ZacUI ships the
-- library for its own minimap button; every Broker / Titan / Bazooka
-- plugin registers one) can be ticked on the Chat page. A ticked object
-- becomes an item on the bar exactly like Gold or Latency (Blz_Chat's
-- Chat.AddBarItem): its text (and icon) in a fixed slot, left-click to
-- the object's OnClick, hover to its OnTooltipShow (or OnEnter / OnLeave
-- for objects that bring their own tooltip). The blocks sit at the left
-- of ZacUI's own numbers, in the order of the list, and are the first to
-- step off when the bar is narrow.
--
-- OFF BY DEFAULT: nothing is docked until ticked (ZacUIDB.chat.ldb[name]).
-- With nothing ticked this file registers two library callbacks and
-- nothing else: no frame, no ticker, no text read.
--
-- SECRET-SAFE. A block's text is whatever the other addon wrote; on WoW
-- Forever that could be a hidden value. One is shown as it is (no string
-- work on it, no icon stitched in front).
--
-- UPDATES ride the bar's own clock (Blz_Chat's quarter-second tick,
-- once a second per item); the library's attribute-changed callback
-- only marks the item due, never draws.

local ADDON_NAME, ns = ...

-- DORMANT WITHOUT THE LIBRARY: no LibStub, no LibDataBroker-1.1 (asked
-- silently), or one without the calls this file uses (its callbacks come
-- from CallbackHandler) - then nothing here loads: no card, no callback.
local Chat = ns.Chat
local LDB
do
    local LS = rawget(_G, "LibStub")
    if LS ~= nil and (type(LS) == "table" or type(LS) == "function") then
        local ok, lib = pcall(LS, "LibDataBroker-1.1", true)
        if ok and type(lib) == "table" then LDB = lib end
    end
end
if not (Chat and Chat.AddBarItem and LDB) then return end
if type(LDB.RegisterCallback) ~= "function" or type(LDB.GetDataObjectByName) ~= "function" then return end

local UI = ns.UI
local M, F = UI.M, UI.F

local L = {}
ns.ChatLDB = L

local PREFIX = "ldb:"
local docked = {}            -- name -> spec on the bar

-- the chat settings; the two tables of this file are made the first time
-- something is ticked (reading writes nothing into the save)
local EMPTY = {}
local function DB() return Chat.DB() end
local function Ticked() local d = DB() return type(d.ldb) == "table" and d.ldb or EMPTY end
local function Order_() local d = DB() return type(d.ldbOrder) == "table" and d.ldbOrder or EMPTY end
local function Writable()
    local d = DB()
    if type(d.ldb) ~= "table" then d.ldb = {} end
    if type(d.ldbOrder) ~= "table" then d.ldbOrder = {} end
    return d
end

-- every object the library knows, by name
function L.Found()
    local out = {}
    if LDB.DataObjectIterator then
        for name, obj in LDB:DataObjectIterator() do
            if type(name) == "string" then out[#out + 1] = { name = name, obj = obj, type = obj.type } end
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

-- the ticked objects in their order: saved order first, then any ticked
-- one not in it, by name
function L.Order()
    local ticked, order = Ticked(), Order_()
    local out, seen = {}, {}
    for _, name in ipairs(order) do
        if ticked[name] and not seen[name] then seen[name] = true out[#out + 1] = name end
    end
    local rest = {}
    for name, on in pairs(ticked) do if on and not seen[name] then rest[#rest + 1] = name end end
    table.sort(rest, function(a, b) return a:lower() < b:lower() end)
    for _, name in ipairs(rest) do out[#out + 1] = name end
    return out
end

local function Icons() return DB().ldbIcons ~= false end

local function Text(name)
    local obj = LDB:GetDataObjectByName(name)
    if not obj then return "" end
    local t = obj.text
    if t == nil or t == "" then t = obj.label or name end
    if ns.IsSecret and ns.IsSecret(t) then return t end
    t = tostring(t)
    local icon = obj.icon
    if Icons() and icon and not (ns.IsSecret and ns.IsSecret(icon)) then
        local tc = obj.iconCoords
        if type(tc) == "table" and #tc == 4 then
            t = string.format("|T%s:14:14:0:0:64:64:%d:%d:%d:%d|t ", tostring(icon),
                tc[1] * 64, tc[2] * 64, tc[3] * 64, tc[4] * 64) .. t
        else
            t = "|T" .. tostring(icon) .. ":14:14|t " .. t
        end
    end
    return t
end
L.Text = Text

local function Tip(self, name)
    local obj = LDB:GetDataObjectByName(name)
    GameTooltip:SetOwner(self, self._zTipAnchor or "ANCHOR_TOP")
    if obj and obj.OnTooltipShow then
        local ok, err = pcall(obj.OnTooltipShow, GameTooltip)
        if not ok then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(name)
        end
    elseif obj and obj.OnEnter then
        -- the object brings its own tooltip: our GameTooltip stays empty
        -- and hidden, theirs opens on the plate
        GameTooltip:Hide()
        pcall(obj.OnEnter, self)
        self._zLdbOwnTip = true
        return
    else
        GameTooltip:AddLine(name)
    end
end

local function Click(self, button, name)
    local obj = LDB:GetDataObjectByName(name)
    if obj and obj.OnClick then pcall(obj.OnClick, self, button or "LeftButton") end
end

local function Spec(name, i)
    return {
        id = PREFIX .. name, label = name, sample = name, ldb = true,
        keep = 50 + i, every = 1,
        text = function() return Text(name) end,
        tip = function(self) Tip(self, name) end,
        click = function(self, button) Click(self, button, name) end,
    }
end

-- the bar as the switches say: every ticked object docked in order,
-- everything else off the bar
function L.Apply()
    local d = DB()
    local want = L.Order()
    local wantSet = {}
    for _, name in ipairs(want) do wantSet[name] = true end
    -- order matters on the bar (items are laid out in list order), so a
    -- changed order re-docks the lot
    local same = true
    local n = 0
    for name in pairs(docked) do n = n + 1 if not wantSet[name] then same = false end end
    if n ~= #want then same = false end
    if same then
        local i = 0
        for _, name in ipairs(want) do
            i = i + 1
            if docked[name] and docked[name].keep ~= 50 + i then same = false end
        end
    end
    if same then
        for _, name in ipairs(want) do d.items[PREFIX .. name] = true end
        return
    end
    for name in pairs(docked) do
        Chat.RemoveBarItem(PREFIX .. name)
        docked[name] = nil
    end
    -- front-inserted one by one, so the LAST inserted is leftmost: insert
    -- in reverse to read in list order
    for i = #want, 1, -1 do
        local name = want[i]
        local spec = Spec(name, i)
        local added, plate = Chat.AddBarItem(spec, true)
        docked[name] = added
        d.items[PREFIX .. name] = true
        if plate and not plate._zLdbLeave then
            plate._zLdbLeave = true
            plate:HookScript("OnLeave", function(self)
                if self._zLdbOwnTip then
                    self._zLdbOwnTip = nil
                    local obj = LDB:GetDataObjectByName(name)
                    if obj and obj.OnLeave then pcall(obj.OnLeave, self) end
                end
            end)
        end
    end
    if Chat.Refresh then Chat.Refresh() end
end

function L.Set(name, on)
    local d = Writable()
    d.ldb[name] = on and true or nil
    if not on then d.items[PREFIX .. name] = nil end
    if on then
        local found = false
        for _, v in ipairs(d.ldbOrder) do if v == name then found = true end end
        if not found then d.ldbOrder[#d.ldbOrder + 1] = name end
    end
    L.Apply()
end

function L.Move(name, delta)
    local order = L.Order()
    local at
    for i, v in ipairs(order) do if v == name then at = i end end
    if not at then return end
    local to = at + delta
    if to < 1 or to > #order then return end
    order[at], order[to] = order[to], order[at]
    Writable().ldbOrder = order
    L.Apply()
end

-- a block is due the moment its object changes (the bar's tick draws it)
LDB.RegisterCallback(L, "LibDataBroker_AttributeChanged", function(_, name, key)
    if not docked[name] then return end
    if key ~= "text" and key ~= "icon" and key ~= "label" and key ~= "value" and key ~= "suffix" then return end
    local plate = Chat.BarItem(PREFIX .. name)
    if plate then plate._t = 99 end
end)
-- an object made after login that is already ticked docks itself
LDB.RegisterCallback(L, "LibDataBroker_DataObjectCreated", function(_, name)
    if Ticked()[name] then L.Apply() end
end)

-- ============================================================
-- THE CHAT PAGE: a card of the objects found, a tick each, up / down
-- ============================================================
function L.Card(Lay)
    if not Lay then return end
    local d = DB()
    local ticked = Ticked()
    Lay:Card("Other addons' blocks")
    Lay:Desc("Any addon that offers a LibDataBroker block (Broker addons, Titan Panel plugins) can sit on the bar: "
        .. "its text and icon, a click to its click, a hover to its tooltip. Blocks go to the left of ZacUI's "
        .. "own numbers, in this order, and step off first when the bar is narrow.")
    local found = L.Found()
    if #found == 0 then
        Lay:Desc("No blocks found. An addon that offers one shows up here once it is loaded.")
        Lay:EndCard()
        return
    end
    local order = L.Order()
    local pos = {}
    for i, name in ipairs(order) do pos[name] = i end
    for _, e in ipairs(found) do
        local name = e.name
        local row = UI.Holder(Lay.current)
        row:SetHeight(M.ROW)
        local on = ticked[name] and true or false
        local label = name
        if e.type == "launcher" then label = name .. " (a button)" end
        local cb = UI.Checkbox(row, label, on, function(v) L.Set(name, v) if ns.RefreshConfig then ns.RefreshConfig() end end,
            { tooltip = "Dock " .. name .. " on the chat bar." })
        cb:SetPoint("LEFT", 0, 0)
        if on then
            local i = pos[name] or 0
            local up = UI.Button(row, "Up", { width = 36, height = 18, size = F.SMALL,
                onClick = function() L.Move(name, -1) if ns.RefreshConfig then ns.RefreshConfig() end end })
            local down = UI.Button(row, "Down", { width = 46, height = 18, size = F.SMALL,
                onClick = function() L.Move(name, 1) if ns.RefreshConfig then ns.RefreshConfig() end end })
            down:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            up:SetPoint("RIGHT", down, "LEFT", -4, 0)
            UI.SetEnabled(up, i > 1)
            UI.SetEnabled(down, i < #order)
        end
        Lay:Row(row, M.ROW)
    end
    local icons = UI.Checkbox(Lay.current, "Show their icons", Icons(), function(v)
        d.ldbIcons = v and true or false
        if Chat.Refresh then Chat.Refresh() end
    end)
    Lay:Row(icons, 17)
    Lay:EndCard()
end

-- The login: Blz_Chat's module docks what was ticked once its bar is
-- built (it calls L.Apply), so this file makes no frame of its own.
