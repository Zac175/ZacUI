-- QoL_LootFeed - a strip of fading rows for what you just got: items
-- looted (icon, name, count, in the item's quality colour), money,
-- reputation and skill-ups. Off by default (Quality of life > Loot feed);
-- a mover ("Loot feed") puts it anywhere; a Test button plays sample rows.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT IT READS: the game's own chat lines for you (CHAT_MSG_LOOT,
-- CHAT_MSG_MONEY, CHAT_MSG_COMBAT_FACTION_CHANGE, CHAT_MSG_SKILL), matched
-- against the client's own format strings (LOOT_ITEM_SELF and friends,
-- GOLD_AMOUNT, FACTION_STANDING_INCREASED, SKILL_RANK_UP), so a localised
-- client reads its own words. Other people's loot is never shown.
--
-- SECRET-SAFE. On WoW Forever a chat line can be a hidden value in a
-- fight; one is skipped before any string work.
--
-- COST: the four events are registered only while the feed is on (and the
-- Quality of life module runs). A line
-- is queued, never drawn in the event; the queue drains on the next frame.
-- The fade runs on the strip's OnUpdate, which only exists while a row is
-- showing (the strip hides itself when the last row goes).

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local QoL = ns.QoL
if not (QoL and QoL.DB) then return end

local LF = {}
QoL.LootFeed = LF

local OWN_ID = "loot_feed"
local MOVER = "lootfeed"
local WIDTH = 260
LF.DEFAULTS = { duration = 6, maxRows = 6, quality = 0, iconSize = 18 }
LF.FONT_DEFAULTS = { size = 12, outline = "outline", shadow = false }
local FADE = 1.0   -- the last second of a row's life is its fade

local ICON_MONEY = "Interface\\Icons\\INV_Misc_Coin_01"
local ICON_REP = "Interface\\Icons\\INV_Scroll_03"
local ICON_SKILL = "Interface\\Icons\\INV_Misc_Book_11"
local ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark"

-- ============================================================
-- SETTINGS (qol.lootFeed; nothing saved = off). Reading writes nothing.
-- ============================================================
local EMPTY = {}
local function Cfg()
    local q = QoL.DB()
    return type(q.lootFeed) == "table" and q.lootFeed or EMPTY
end
local function Writable()
    local q = QoL.DB()
    if type(q.lootFeed) ~= "table" then q.lootFeed = {} end
    return q.lootFeed
end
LF.Cfg, LF.Writable = Cfg, Writable
-- a view of the settings that reads without writing and writes through
-- (the font picker takes a table)
local view = setmetatable({}, {
    __index = function(_, k) return Cfg()[k] end,
    __newindex = function(_, k, v) Writable()[k] = v end,
})
function LF.On()
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return false end
    return Cfg().enabled == true
end
local function Num(key, lo, hi)
    local v = tonumber(Cfg()[key]) or LF.DEFAULTS[key]
    return math.max(lo, math.min(hi, v))
end
function LF.Duration() return Num("duration", 2, 20) end
function LF.MaxRows() return math.floor(Num("maxRows", 1, 12)) end
function LF.MinQuality() return math.floor(Num("quality", 0, 5)) end
function LF.IconSize() return math.floor(Num("iconSize", 12, 32)) end
-- money, reputation and skill rows each have their own switch (on)
function LF.Shows(kind) return Cfg()[kind] ~= false end

-- ============================================================
-- READING THE LINES
-- ============================================================
-- a client format string ("You receive loot: %sx%d.") as a pattern
-- (the format's %s / %d - and a localised "%1$s" - become markers first,
-- then everything else is escaped, then the markers become captures)
local function Body(fmt)
    local p = fmt:gsub("%%%d?%$?s", "\001")
    p = p:gsub("%%%d?%$?d", "\002")
    p = p:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    p = p:gsub("\001", "(.+)")
    p = p:gsub("\002", "(%%d+)")
    return p
end
local function Pat(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    return "^" .. Body(fmt) .. "$"
end
LF.Pat = Pat

local itemPats, moneyPats, repPats, skillPats
local function BuildPatterns()
    itemPats = {}
    -- the "multiple" forms first: "x3" would otherwise end up in the name
    for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
                         "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF",
                         "LOOT_ITEM_CREATED_SELF" }) do
        local p = Pat(_G[g])
        if p then itemPats[#itemPats + 1] = p end
    end
    moneyPats = {}
    for i, g in ipairs({ "GOLD_AMOUNT", "SILVER_AMOUNT", "COPPER_AMOUNT" }) do
        local fmt = _G[g]
        if type(fmt) == "string" then
            moneyPats[#moneyPats + 1] = { Body(fmt), (i == 1 and 10000) or (i == 2 and 100) or 1 }
        end
    end
    repPats = {}
    local up, down = Pat(_G.FACTION_STANDING_INCREASED), Pat(_G.FACTION_STANDING_DECREASED)
    if up then repPats[#repPats + 1] = { up, 1 } end
    if down then repPats[#repPats + 1] = { down, -1 } end
    skillPats = {}
    local sk = Pat(_G.SKILL_RANK_UP)
    if sk then skillPats[1] = sk end
end

local function Quality(link)
    if GetItemInfo then
        local ok, _, _, q = pcall(GetItemInfo, link)
        if ok and type(q) == "number" then return q end
    end
    -- not cached yet: the link's own colour says it
    local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
    local Q = _G.ITEM_QUALITY_COLORS
    if hex and Q then
        hex = hex:lower()
        for q = 0, 7 do
            local c = Q[q]
            local h = c and c.hex and c.hex:lower():match("|c(%x%x%x%x%x%x%x%x)")
            if h == hex then return q end
        end
    end
    return 1
end
local function ItemIcon(link)
    if GetItemInfoInstant then
        local ok, _, _, _, _, icon = pcall(GetItemInfoInstant, link)
        if ok and icon then return icon end
    end
    if GetItemIcon then
        local ok, icon = pcall(GetItemIcon, link)
        if ok and icon then return icon end
    end
    if GetItemInfo then
        local ok, _, _, _, _, _, _, _, _, _, icon = pcall(GetItemInfo, link)
        if ok and icon then return icon end
    end
    return ICON_UNKNOWN
end

-- a line -> a row spec { icon, text, r, g, b } or nil (not ours, filtered)
function LF.Parse(event, msg)
    if type(msg) ~= "string" or (ns.IsSecret and ns.IsSecret(msg)) then return nil end
    if not itemPats then BuildPatterns() end
    if event == "CHAT_MSG_LOOT" then
        for _, p in ipairs(itemPats) do
            local link, count = msg:match(p)
            if link then
                local name = link:match("%[(.-)%]") or link
                local q = Quality(link)
                if q < LF.MinQuality() then return nil end
                local r, g, b = ns.QualityRGB(q)
                count = tonumber(count) or 1
                return { icon = ItemIcon(link), text = name .. (count > 1 and (" x" .. count) or ""),
                         r = r, g = g, b = b, kind = "item", quality = q }
            end
        end
    elseif event == "CHAT_MSG_MONEY" then
        if not LF.Shows("money") then return nil end
        local copper, any = 0, false
        for _, mp in ipairs(moneyPats) do
            local n = msg:match(mp[1])
            if n then copper, any = copper + tonumber(n) * mp[2], true end
        end
        if not any or copper <= 0 then return nil end
        local c = GetColor("text", "gold")
        return { icon = ICON_MONEY, text = ns.Money(copper), r = c.r, g = c.g, b = c.b, kind = "money" }
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        if not LF.Shows("rep") then return nil end
        for _, rp in ipairs(repPats) do
            local faction, amount = msg:match(rp[1])
            if faction then
                amount = tonumber(amount) or 0
                local c = GetColor("text", rp[2] > 0 and "green" or "red")
                return { icon = ICON_REP, text = (rp[2] > 0 and "+" or "-") .. amount .. " " .. faction,
                         r = c.r, g = c.g, b = c.b, kind = "rep" }
            end
        end
    elseif event == "CHAT_MSG_SKILL" then
        if not LF.Shows("skill") then return nil end
        for _, p in ipairs(skillPats) do
            local skill, rank = msg:match(p)
            if skill then
                local c = GetColor("text", "blue")
                return { icon = ICON_SKILL, text = skill .. " " .. tostring(rank), r = c.r, g = c.g, b = c.b, kind = "skill" }
            end
        end
    end
    return nil
end

-- ============================================================
-- THE STRIP
-- ============================================================
local strip
local rows = {}      -- the showing rows, newest first
local spare = {}     -- rows no longer showing, reused

local function StyleRow(row)
    local size = LF.IconSize()
    row:SetSize(WIDTH, size + 2)
    row._zIcon:SetSize(size, size)
    if ns.ApplyFontSpec then
        ns.ApplyFontSpec(row._zText, Cfg().font, LF.FONT_DEFAULTS)
    elseif ns.HouseFont then
        ns.HouseFont(row._zText, 12, "OUTLINE")
    end
end
LF.StyleRow = StyleRow

function LF.MakeRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    ZacUI.Look.CropIcon(icon)
    row._zIcon = icon
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    row._zText = fs
    StyleRow(row)
    return row
end

function LF.Fill(row, spec)
    row._zIcon:SetTexture(spec.icon or ICON_UNKNOWN)
    row._zText:SetText(spec.text or "")
    row._zText:SetTextColor(spec.r or 1, spec.g or 1, spec.b or 1, 1)
end

local function Layout()
    local size = LF.IconSize() + 4
    for i, row in ipairs(rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, -(i - 1) * size)
    end
    strip:SetHeight(math.max(size, LF.MaxRows() * size))
end

local acc = 0
local function OnUpdate(self, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.05 then return end
    acc = 0
    local now, life = GetTime(), LF.Duration()
    local gone = false
    for i = #rows, 1, -1 do
        local row = rows[i]
        local age = now - row._zBorn
        if age >= life then
            row:Hide()
            table.remove(rows, i)
            spare[#spare + 1] = row
            gone = true
        elseif age > life - FADE then
            row:SetAlpha(math.max(0, (life - age) / FADE))
        else
            row:SetAlpha(1)
        end
    end
    if gone then Layout() end
    if #rows == 0 then self:Hide() end
end

local function Strip()
    if strip then return strip end
    strip = CreateFrame("Frame", "ZacUILootFeed", UIParent)
    strip:SetSize(WIDTH, LF.MaxRows() * (LF.IconSize() + 4))
    strip:SetFrameStrata("MEDIUM")
    strip:EnableMouse(false)
    strip:ClearAllPoints()
    strip:SetPoint("CENTER", UIParent, "CENTER", 300, 120)
    strip:Hide()
    strip:SetScript("OnUpdate", OnUpdate)
    if ns.ApplyMover then ns.ApplyMover(MOVER) end
    return strip
end
LF.Frame = function() return strip end
LF.Rows = function() return rows end

-- one row in at the top; the oldest past the limit steps off
function LF.Push(spec)
    if not spec then return nil end
    local f = Strip()
    local row = table.remove(spare) or LF.MakeRow(f)
    StyleRow(row)
    LF.Fill(row, spec)
    row._zBorn = GetTime()
    row:SetAlpha(1)
    row:Show()
    table.insert(rows, 1, row)
    while #rows > LF.MaxRows() do
        local old = table.remove(rows)
        old:Hide()
        spare[#spare + 1] = old
    end
    Layout()
    f:Show()
    return row
end

-- every row gone at once (the feed turned off)
function LF.Clear()
    for i = #rows, 1, -1 do
        rows[i]:Hide()
        spare[#spare + 1] = rows[i]
        rows[i] = nil
    end
    if strip then strip:Hide() end
end

-- ============================================================
-- EVENTS (only while on): queued, drawn on the next frame
-- ============================================================
local EVENTS = { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_COMBAT_FACTION_CHANGE", "CHAT_MSG_SKILL" }
local queue, draining = {}, false
local function Drain()
    draining = false
    local list = queue
    queue = {}
    for _, q in ipairs(list) do
        local ok, spec = pcall(LF.Parse, q[1], q[2])
        if ok and spec then LF.Push(spec) end
    end
end
LF.Drain = Drain

-- (the event frame is made the first time the feed is on: off, this file
-- makes no frame at all)
local ev
local function OnEvent(_, event, msg)
    queue[#queue + 1] = { event, msg }
    -- (a burst of lines - a boss's loot - is one drain)
    if #queue > 40 then table.remove(queue, 1) end
    if not draining then
        draining = true
        C_Timer.After(0, Drain)
    end
end
local registered = false
function LF.Apply()
    local on = LF.On()
    if on and not registered then
        if not ev then
            ev = CreateFrame("Frame")
            ev:SetScript("OnEvent", OnEvent)
        end
        for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
        registered = true
    elseif not on and registered then
        ev:UnregisterAllEvents()
        registered = false
        LF.Clear()
    end
    for _, row in ipairs(rows) do StyleRow(row) end
    if strip then Layout() end
end
LF.Registered = function() return registered end

-- ============================================================
-- THE TEST BUTTON: sample rows, one after another
-- ============================================================
LF.SAMPLES = {
    { event = "CHAT_MSG_LOOT", item = "|cffa335ee|Hitem:19019::::::::60:::::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r", q = 5, count = 1 },
    { event = "CHAT_MSG_LOOT", item = "|cff0070dd|Hitem:18803::::::::60:::::::|h[Finkle's Lava Dredger]|h|r", q = 3, count = 1 },
    { event = "CHAT_MSG_LOOT", item = "|cffffffff|Hitem:12359::::::::60:::::::|h[Thorium Bar]|h|r", q = 1, count = 5 },
    { event = "CHAT_MSG_MONEY", copper = 123456 },
    { event = "CHAT_MSG_COMBAT_FACTION_CHANGE", faction = "Thorium Brotherhood", amount = 25 },
    { event = "CHAT_MSG_SKILL", skill = "Mining", rank = 276 },
}
-- the row a sample would make, without the client's lines (Test works on
-- any client, and with the quality filter set it still shows all kinds)
function LF.SampleSpec(s)
    if s.item then
        local r, g, b = ns.QualityRGB(s.q)
        return { icon = ItemIcon(s.item), text = (s.item:match("%[(.-)%]") or "?") .. (s.count > 1 and (" x" .. s.count) or ""),
                 r = r, g = g, b = b, kind = "item" }
    elseif s.copper then
        local c = GetColor("text", "gold")
        return { icon = ICON_MONEY, text = ns.Money(s.copper), r = c.r, g = c.g, b = c.b, kind = "money" }
    elseif s.faction then
        local c = GetColor("text", "green")
        return { icon = ICON_REP, text = "+" .. s.amount .. " " .. s.faction, r = c.r, g = c.g, b = c.b, kind = "rep" }
    elseif s.skill then
        local c = GetColor("text", "blue")
        return { icon = ICON_SKILL, text = s.skill .. " " .. s.rank, r = c.r, g = c.g, b = c.b, kind = "skill" }
    end
end
function LF.Test()
    for i, s in ipairs(LF.SAMPLES) do
        C_Timer.After((i - 1) * 0.4, function() LF.Push(LF.SampleSpec(s)) end)
    end
end

-- the mover and the settings hook now (no frame); the events once the
-- module starts (QoL_Core calls QoL.EnableAutomation at login), so the
-- feed stands down with the rest of the module behind Leatrix Plus
if not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) then
    if ns.RegisterMover then
        ns.RegisterMover(MOVER, "Loot feed", function() return strip end, "CENTER", 300, 120, nil, { own = true })
    end
    if ns.OnSettingsChanged then ns.OnSettingsChanged(function() if QoL.enabled then LF.Apply() end end) end
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        LF.Apply()
    end
end

-- ============================================================
-- THE PAGE: Quality of life > Loot feed
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

LF.QUALITIES = {
    { value = 0, text = "Everything (grey and up)" },
    { value = 1, text = "White and up" },
    { value = 2, text = "Green and up" },
    { value = 3, text = "Blue and up" },
    { value = 4, text = "Purple and up" },
    { value = 5, text = "Orange only" },
}

AddTab("qol", "lootfeed", "Loot feed", function(L)
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    L:Card("Loot feed")
    local on = UI.Checkbox(L.current, "Show what I loot as fading rows", Cfg().enabled == true, function(v)
        Writable().enabled = v or nil
        if QoL.enabled then LF.Apply() end
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "Items you loot (icon, name, count, in the item's colour), money, reputation and skill-ups, "
        .. "each a row that fades after a few seconds. Only yours, never other people's loot." })
    L:Row(on, 17)
    -- the sample, as it looks
    local size = LF.IconSize() + 4
    local box = UI.Holder(L.current)
    box:SetSize(WIDTH, size * 3 + 4)
    for i = 1, 3 do
        local row = LF.MakeRow(box)
        row:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -(i - 1) * size - 2)
        LF.Fill(row, LF.SampleSpec(LF.SAMPLES[i == 1 and 2 or (i == 2 and 3 or 4)]))
    end
    L:Row(box, size * 3 + 8)
    local kids = {}
    kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 2, max = 20, step = 1,
        value = LF.Duration(), label = "Each row stays",
        format = function(v) return v .. " s" end,
        onChange = function(v) Writable().duration = (v ~= LF.DEFAULTS.duration) and v or nil end })
    kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 1, max = 12, step = 1,
        value = LF.MaxRows(), label = "Rows at most",
        onChange = function(v) Writable().maxRows = (v ~= LF.DEFAULTS.maxRows) and v or nil LF.Apply() end })
    kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 12, max = 32, step = 1,
        value = LF.IconSize(), label = "Icon size",
        format = function(v) return v .. " px" end,
        onChange = function(v) Writable().iconSize = (v ~= LF.DEFAULTS.iconSize) and v or nil LF.Apply() end })
    kids[#kids + 1] = UI.Field(L.current, "Items shown", function(h)
        return UI.Dropdown(h, { width = 200,
            items = function() return LF.QUALITIES end,
            selectedValue = function() return LF.MinQuality() end,
            selected = function()
                for _, it in ipairs(LF.QUALITIES) do if it.value == LF.MinQuality() then return it.text end end
                return LF.QUALITIES[1].text
            end,
            onSelect = function(v) Writable().quality = (v ~= 0) and v or nil end })
    end, { width = 200 })
    for _, k in ipairs({ { "money", "Money" }, { "rep", "Reputation" }, { "skill", "Skill-ups" } }) do
        kids[#kids + 1] = UI.Checkbox(L.current, k[2], LF.Shows(k[1]), function(v)
            if v then Writable()[k[1]] = nil else Writable()[k[1]] = false end
        end)
    end
    kids[#kids + 1] = UI.Button(L.current, "Test", { width = 80,
        tooltip = "Plays a few sample rows: items of three qualities, money, reputation and a skill-up.",
        onClick = function() LF.Test() end })
    L:Dependent(kids, Cfg().enabled == true, 1, nil, "Show what I loot as fading rows")
    if Kit then
        Kit.Font(L, "Row text", function() return view end, "font", LF.FONT_DEFAULTS,
            { sample = "Thorium Bar x5", after = function() LF.Apply() end })
        if Kit.Mover and ns.MOVERS and ns.MOVERS[MOVER] then Kit.Mover(L, MOVER, "the feed") end
    end
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "loot feed looted items money gold reputation skill fading rows toast")
end
