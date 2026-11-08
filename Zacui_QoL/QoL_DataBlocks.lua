-- QoL_DataBlocks - four small blocks of information for ZacUI's chat bar
-- (or any Broker display: Titan Panel, ChocolateBar...):
--   ZacUI Clock        the time, as the game's clock is set (local or
--                      realm, 12 or 24 hour); click: the game's clock
--   ZacUI Location     your map coordinates; the zone in the tooltip;
--                      click: the world map
--   ZacUI Experience   XP and rested to the next level; at the top level,
--                      the reputation you watch; click: reputation
--   ZacUI Supplies     ammo, and the reagent your class buys (soul shards,
--                      candles, powder, symbols, ankhs...); click: bags
-- They are LibDataBroker objects, the same kind other addons give, so they
-- dock on the chat bar from the Chat page's Broker card like any other.
-- Off by default: until switched on (Quality of life > On screen) no
-- object is made, nothing ticks. Off again later, they stop updating and
-- go blank (a Broker object cannot be taken back until the next reload).
-- Part of ZacUI; load order is set by the TOC.
--
-- SIZE: the bar gives a block the width of its name, so every text here
-- is kept no wider than its name ("21:05", "42.1, 65.3", "XP 45.2% +12%",
-- "Ammo 1,200").
--
-- COST: off, nothing. On: the clock checks the minute every 5 s; the
-- location reads the map position every half second (only while that block
-- is on); experience and supplies on their own events (bags a moment after
-- they change, never in BAG_UPDATE).

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local QoL = ns.QoL
if not QoL then return end

local DBK = {}
QoL.DataBlocks = DBK

local OWN_ID = "data_blocks"
-- the library, asked for when first needed (ZacUI's core ships it; asked
-- silently, so a client without it leaves this file dormant)
local LDB
local function Lib()
    if LDB then return LDB end
    local LS = rawget(_G, "LibStub")
    if LS ~= nil and (type(LS) == "table" or type(LS) == "function") then
        local ok, lib = pcall(LS, "LibDataBroker-1.1", true)
        if ok and type(lib) == "table" and type(lib.NewDataObject) == "function" then LDB = lib end
    end
    return LDB
end
DBK.HasLibrary = function() return Lib() ~= nil end

local function Hidden(v) return ns.IsSecret and ns.IsSecret(v) or false end

-- the blocks, in their order on the page
DBK.BLOCKS = {
    { id = "clock", name = "ZacUI Clock", label = "Clock", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" },
    { id = "location", name = "ZacUI Location", label = "Location", icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { id = "xp", name = "ZacUI Experience", label = "Experience", icon = "Interface\\Icons\\INV_Misc_Book_11" },
    { id = "supplies", name = "ZacUI Supplies", label = "Supplies", icon = "Interface\\Icons\\INV_Ammo_Arrow_02" },
}
DBK.BY_ID = {}
for _, b in ipairs(DBK.BLOCKS) do DBK.BY_ID[b.id] = b end

-- each class's reagent: item id, short name (the text) and long (the tooltip)
DBK.REAGENTS = {
    WARLOCK = { { 6265, "Shards", "Soul Shard" } },
    PRIEST  = { { 17029, "Candles", "Sacred Candle" }, { 17028, "Holy", "Holy Candle" } },
    MAGE    = { { 17020, "Powder", "Arcane Powder" }, { 17031, "Teleport", "Rune of Teleportation" }, { 17032, "Portal", "Rune of Portals" } },
    DRUID   = { { 17026, "Thornroot", "Wild Thornroot" }, { 22148, "Quillvine", "Wild Quillvine" } },
    PALADIN = { { 21177, "Symbols", "Symbol of Kings" }, { 17033, "Divinity", "Symbol of Divinity" } },
    SHAMAN  = { { 17030, "Ankhs", "Ankh" } },
    ROGUE   = { { 5140, "Powder", "Flash Powder" } },
}

-- ============================================================
-- SETTINGS (qol.dataBlocks; nothing saved = off)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.dataBlocks) ~= "table" then q.dataBlocks = {} end
    return q.dataBlocks
end
DBK.DB = DB
local function Permitted() return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) end
local function Allowed() return Permitted() and Lib() ~= nil end
function DBK.On() return Allowed() and QoL.enabled == true and DB().enabled == true end
function DBK.BlockOn(id) return DBK.On() and DB()["no_" .. id] ~= true end

-- ============================================================
-- THE TEXTS
-- ============================================================
local function Bool(cvar)
    if C_CVar and C_CVar.GetCVarBool then return C_CVar.GetCVarBool(cvar) and true or false end
    if GetCVarBool then return GetCVarBool(cvar) and true or false end
    return GetCVar and GetCVar(cvar) == "1" or false
end

-- the time as the game's own clock shows it
function DBK.ClockText(h, m)
    local h24 = Bool("timeMgrUseMilitaryTime")
    if not h then
        if Bool("timeMgrUseLocalTime") or type(GetGameTime) ~= "function" then
            local t = date("*t")
            h, m = t.hour, t.min
        else
            h, m = GetGameTime()
        end
    end
    if h24 then return string.format("%d:%02d", h, m) end
    local suffix = h >= 12 and "pm" or "am"
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    return string.format("%d:%02d %s", h12, m, suffix)
end

-- the player's map position: x, y in 0-100, or nil (an instance, a hidden value)
function DBK.Coords()
    local M = _G.C_Map
    if not (M and M.GetBestMapForUnit and M.GetPlayerMapPosition) then return nil end
    local map = M.GetBestMapForUnit("player")
    if not map or Hidden(map) then return nil end
    local pos = M.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y
    if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
    if x == nil or y == nil or Hidden(x) or Hidden(y) then return nil end
    if x == 0 and y == 0 then return nil end
    return x * 100, y * 100
end
function DBK.LocationText()
    local x, y = DBK.Coords()
    if not x then return "--" end
    return string.format("%.1f, %.1f", x, y)
end

-- the watched reputation: name, standing text, value in it, size of it
local function Watched()
    local R = _G.C_Reputation
    if R and type(R.GetWatchedFactionData) == "function" then
        local d = R.GetWatchedFactionData()
        if type(d) == "table" and d.name then
            local lo, hi, v = d.currentReactionThreshold or 0, d.nextReactionThreshold or 0, d.currentStanding or 0
            return d.name, _G["FACTION_STANDING_LABEL" .. (d.reaction or 4)], v - lo, hi - lo
        end
    end
    if type(GetWatchedFactionInfo) == "function" then
        local name, standing, lo, hi, v = GetWatchedFactionInfo()
        if name then return name, _G["FACTION_STANDING_LABEL" .. (standing or 4)], v - lo, hi - lo end
    end
    return nil
end
DBK.Watched = Watched

local function MaxLevel()
    if type(GetMaxPlayerLevel) == "function" then return GetMaxPlayerLevel() end
    return _G.MAX_PLAYER_LEVEL or 60
end
function DBK.XPText()
    local lvl = UnitLevel and UnitLevel("player") or 1
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if lvl < MaxLevel() and not Hidden(cur) and not Hidden(max) and (max or 0) > 0 then
        local rested = GetXPExhaustion and GetXPExhaustion() or nil
        local t = string.format("XP %.1f%%", cur / max * 100)
        if rested and not Hidden(rested) and rested > 0 then
            t = t .. string.format(" +%d%%", math.floor(rested / max * 100 + 0.5))
        end
        return t
    end
    local name, label, v, size = Watched()
    if not name then return "Max level" end
    if not size or size <= 0 then return label or name end
    return string.format("%s %d%%", label or "", math.floor(v / size * 100))
end

local function Count(id)
    if type(GetItemCount) ~= "function" then return 0 end
    local n = GetItemCount(id) or 0
    if Hidden(n) then return 0 end
    return n
end
local function Comma(n)
    if ns.Numbers and ns.Numbers.Comma then
        local ok, t = pcall(ns.Numbers.Comma, n)
        if ok and type(t) == "string" then return t end
    end
    return tostring(n)
end
function DBK.Ammo()
    if type(GetInventoryItemCount) ~= "function" then return 0 end
    local slot = _G.INVSLOT_AMMO or 0
    if type(GetInventoryItemID) == "function" and not GetInventoryItemID("player", slot) then return 0 end
    local n = GetInventoryItemCount("player", slot) or 0
    if Hidden(n) then return 0 end
    return n
end
function DBK.SuppliesText()
    local ammo = DBK.Ammo()
    local file = UnitClass and select(2, UnitClass("player"))
    local r = file and DBK.REAGENTS[file]
    local first = r and r[1]
    local rc = first and Count(first[1]) or nil
    if ammo > 0 and rc and rc > 0 then return Comma(ammo) .. " / " .. Comma(rc) end
    if ammo > 0 then return "Ammo " .. Comma(ammo) end
    if first then return first[2] .. " " .. Comma(rc or 0) end
    return "--"
end

-- ============================================================
-- TOOLTIPS AND CLICKS
-- ============================================================
local TIP = {}
function TIP.clock(tt)
    tt:AddLine("Clock", 1, 1, 1)
    local t = date("*t")
    tt:AddDoubleLine("Local time", string.format("%d:%02d", t.hour, t.min), 0.8, 0.8, 0.8, 1, 1, 1)
    if type(GetGameTime) == "function" then
        local h, m = GetGameTime()
        tt:AddDoubleLine("Realm time", string.format("%d:%02d", h, m), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    tt:AddDoubleLine("Date", date("%d %B %Y"), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddLine("Click: the game's clock and stopwatch", 0.5, 0.5, 0.5)
end
function TIP.location(tt)
    local zone = GetRealZoneText and GetRealZoneText() or ""
    local sub = GetSubZoneText and GetSubZoneText() or ""
    tt:AddLine(zone ~= "" and zone or "Location", 1, 1, 1)
    if sub ~= "" and sub ~= zone then tt:AddLine(sub, 0.8, 0.8, 0.8) end
    tt:AddDoubleLine("Coordinates", DBK.LocationText(), 0.8, 0.8, 0.8, 1, 1, 1)
    tt:AddLine("Click: the world map", 0.5, 0.5, 0.5)
end
function TIP.xp(tt)
    local lvl = UnitLevel and UnitLevel("player") or 1
    tt:AddLine("Level " .. lvl, 1, 1, 1)
    local cur, max = UnitXP("player"), UnitXPMax("player")
    if lvl < MaxLevel() and not Hidden(cur) and not Hidden(max) and (max or 0) > 0 then
        tt:AddDoubleLine("Experience", Comma(cur) .. " / " .. Comma(max), 0.8, 0.8, 0.8, 1, 1, 1)
        tt:AddDoubleLine("To level", Comma(max - cur), 0.8, 0.8, 0.8, 1, 1, 1)
        local rested = GetXPExhaustion and GetXPExhaustion() or nil
        if rested and not Hidden(rested) and rested > 0 then
            tt:AddDoubleLine("Rested", Comma(rested), 0.8, 0.8, 0.8, 0.4, 0.6, 1)
        end
    end
    local name, label, v, size = Watched()
    if name then
        tt:AddDoubleLine(name, (label or "") .. (size and size > 0 and string.format("  %s / %s", Comma(v), Comma(size)) or ""),
            0.8, 0.8, 0.8, 1, 1, 1)
    end
    tt:AddLine("Click: reputation", 0.5, 0.5, 0.5)
end
function TIP.supplies(tt)
    tt:AddLine("Supplies", 1, 1, 1)
    local ammo = DBK.Ammo()
    if ammo > 0 then tt:AddDoubleLine("Ammo", Comma(ammo), 0.8, 0.8, 0.8, 1, 1, 1) end
    local file = UnitClass and select(2, UnitClass("player"))
    for _, r in ipairs(file and DBK.REAGENTS[file] or {}) do
        tt:AddDoubleLine(r[3], Comma(Count(r[1])), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    tt:AddLine("Click: your bags", 0.5, 0.5, 0.5)
end
local CLICK = {
    clock = function()
        if type(ToggleTimeManager) == "function" then ToggleTimeManager()
        elseif _G.TimeManagerClockButton and TimeManagerClockButton.Click then TimeManagerClockButton:Click() end
    end,
    location = function() if type(ToggleWorldMap) == "function" then ToggleWorldMap() end end,
    xp = function() if type(ToggleCharacter) == "function" then ToggleCharacter("ReputationFrame") end end,
    supplies = function() if type(ToggleAllBags) == "function" then ToggleAllBags() end end,
}
local TEXT = { clock = DBK.ClockText, location = DBK.LocationText, xp = DBK.XPText, supplies = DBK.SuppliesText }
DBK.TEXT = TEXT

-- ============================================================
-- THE OBJECTS
-- ============================================================
local objects = {}
DBK.Object = function(id) return objects[id] end

local function Make(b)
    if objects[b.id] or not Lib() then return objects[b.id] end
    local obj = LDB:NewDataObject(b.name, {
        type = "data source", label = b.label, icon = b.icon, text = "",
        OnTooltipShow = function(tt) pcall(TIP[b.id], tt) end,
        OnClick = function() if DBK.BlockOn(b.id) then pcall(CLICK[b.id]) end end,
    })
    if not obj and LDB.GetDataObjectByName then obj = LDB:GetDataObjectByName(b.name) end
    objects[b.id] = obj
    return obj
end

function DBK.Update(id)
    local obj = objects[id]
    if not obj then return nil end
    local text = ""
    if DBK.BlockOn(id) then
        local ok, t = pcall(TEXT[id])
        text = (ok and type(t) == "string") and t or "--"
    end
    if obj.text ~= text then obj.text = text end
    return text
end
local function UpdateAll() for _, b in ipairs(DBK.BLOCKS) do DBK.Update(b.id) end end
DBK.UpdateAll = UpdateAll

-- ============================================================
-- UPDATES
-- ============================================================
local ev, clockTicker, posTicker
local lastMinute
local pending = false
local function Later(id)
    if pending then return end
    pending = true
    C_Timer.After(0.3, function() pending = false DBK.Update(id) end)
end

local function Track(t, what) if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(t, what) end return t end
local function Stop()
    if clockTicker then clockTicker:Cancel() clockTicker = nil end
    if posTicker then posTicker:Cancel() posTicker = nil end
    if ev then ev:UnregisterAllEvents() end
end
function DBK.Ticking() return clockTicker ~= nil, posTicker ~= nil end

function DBK.Apply()
    if not DBK.On() then
        Stop()
        UpdateAll()      -- blank them (if they were made)
        return
    end
    for _, b in ipairs(DBK.BLOCKS) do if DBK.BlockOn(b.id) then Make(b) end end
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event, unit)
            if event == "BAG_UPDATE_DELAYED" or event == "UNIT_INVENTORY_CHANGED" then
                if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
                Later("supplies")
            elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
                DBK.Update("location")
            else
                DBK.Update("xp")
            end
        end)
    end
    ev:UnregisterAllEvents()
    if DBK.BlockOn("xp") then
        for _, e in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION" }) do pcall(ev.RegisterEvent, ev, e) end
    end
    if DBK.BlockOn("supplies") then
        ev:RegisterEvent("BAG_UPDATE_DELAYED")
        pcall(ev.RegisterEvent, ev, "UNIT_INVENTORY_CHANGED")
    end
    if DBK.BlockOn("location") then
        for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS" }) do ev:RegisterEvent(e) end
        if not posTicker then posTicker = Track(C_Timer.NewTicker(0.5, function() DBK.Update("location") end), "qol.dataBlocks.location") end
    elseif posTicker then posTicker:Cancel() posTicker = nil end
    if DBK.BlockOn("clock") then
        if not clockTicker then
            clockTicker = Track(C_Timer.NewTicker(5, function()
                local m = date("%M")
                if m ~= lastMinute then lastMinute = m DBK.Update("clock") end
            end), "qol.dataBlocks.clock")
        end
    elseif clockTicker then clockTicker:Cancel() clockTicker = nil end
    UpdateAll()
end

local function Live() if QoL.enabled then DBK.Apply() end end
DBK.Live = Live
if Permitted() then
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        pcall(DBK.Apply)
    end
end

-- ============================================================
-- THE PAGE: Quality of life > On screen
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local l = ns.PageTabs[page] or {}
    ns.PageTabs[page] = l
    l[#l + 1] = { tab = tab, label = label, build = build }
end

AddTab("qol", "onscreen", "On screen", function(L)
    if not Allowed() then return end
    local UI = ns.UI
    local d = DB()
    local function Changed()
        Live()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end
    L:Card("Data blocks")
    local on = UI.Checkbox(L.current, "Make ZacUI's data blocks", d.enabled == true, function(v)
        d.enabled = v and true or nil
        Changed()
    end, { tooltip = "Four Broker blocks: the clock, your coordinates, experience (or reputation at the top level) "
        .. "and your supplies (ammo and your class's reagent). Tick them on the Chat page's Broker card to put them "
        .. "on the chat bar; any Broker display shows them too." })
    L:Row(on, 17)
    local kids = {}
    for _, b in ipairs(DBK.BLOCKS) do
        local sample = ""
        local ok, t = pcall(TEXT[b.id])
        if ok and type(t) == "string" then sample = "  (now: " .. t .. ")" end
        kids[#kids + 1] = UI.Checkbox(L.current, b.name .. sample, d["no_" .. b.id] ~= true, function(v)
            d["no_" .. b.id] = (not v) and true or nil
            Changed()
        end)
    end
    L:Dependent(kids, d.enabled == true, 1, nil, "Make ZacUI's data blocks")
    L:Desc("The blocks dock from Chat > the Broker card, like other addons' blocks. Unticked here, a block goes blank "
        .. "and stops updating; a reload takes it out of Broker lists.")
    if not QoL.enabled then L:Desc("The Quality of life part is not running, so these are not either.") end
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "data block blocks broker ldb clock time location coordinates experience xp rested reputation ammo arrows soul shards reagents supplies chat bar")
end
