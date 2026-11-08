-- QoL_TalentReminder - a small icon with a count while you have talent
-- points to spend; click it to open the talents. Off by default (Quality
-- of life > Reminders); a mover ("Unspent talents") puts it anywhere.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE COUNT comes from the game's own talent calls (the ones ZacUI's
-- talent window uses): unspent points less any the talent preview is
-- holding. A client without those calls, or one that hands back a hidden
-- value (WoW Forever can, in a fight), shows nothing and says so on the
-- page. Retail's talents are trees of their own with no Classic count:
-- off there (Core_Flavor, talent_reminder).
--
-- COST: four rare events, coalesced; no tickers.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local QoL = ns.QoL

local TR = {}
QoL.TalentReminder = TR

local OWN_ID = "talent_reminder"
local MOVER = "talentreminder"
local DEFAULT_SIZE = 28
local ICON = "Interface\\Icons\\INV_Misc_Book_09"

-- ============================================================
-- SETTINGS (qol.talents; nothing saved = off, 28 px)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.talents) ~= "table" then q.talents = {} end
    return q.talents
end
TR.DB = DB
function TR.On() return DB().enabled == true end
function TR.Size()
    local v = tonumber(DB().size) or DEFAULT_SIZE
    return math.max(16, math.min(64, v))
end
TR.COUNT_FONT_DEFAULTS = { size = 12, outline = "outline", shadow = false }

-- ============================================================
-- THE COUNT
-- ============================================================
-- this client has a talent point count to read
function TR.Available()
    return type(GetUnspentTalentPoints) == "function" or type(UnitCharacterPoints) == "function"
end

-- unspent points, or nil when the client has no count or hides it
function TR.Unspent()
    local points, pending
    if type(GetUnspentTalentPoints) == "function" then
        local group = 1
        if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
            local ok, g = pcall(C_SpecializationInfo.GetActiveSpecGroup, false, false)
            if ok and type(g) == "number" then group = g end
        elseif type(GetActiveTalentGroup) == "function" then
            local ok, g = pcall(GetActiveTalentGroup, false, false)
            if ok and type(g) == "number" then group = g end
        end
        local ok, p = pcall(GetUnspentTalentPoints, false, false, group)
        if ok then points = p end
        if type(GetGroupPreviewTalentPointsSpent) == "function" then
            local ok2, q = pcall(GetGroupPreviewTalentPointsSpent, false, group)
            if ok2 then pending = q end
        end
    elseif type(UnitCharacterPoints) == "function" then
        local ok, p = pcall(UnitCharacterPoints, "player")
        if ok then points = p end
    end
    if points == nil or (ns.IsSecret and ns.IsSecret(points)) then return nil end
    if type(points) ~= "number" then return nil end
    if type(pending) == "number" and not (ns.IsSecret and ns.IsSecret(pending)) then points = points - pending end
    return math.max(0, points)
end

-- opens the talents the way the micro button does
function TR.OpenTalents()
    if type(ToggleTalentFrame) == "function" then pcall(ToggleTalentFrame) return true end
    local PSU = _G.PlayerSpellsUtil
    if PSU and type(PSU.ToggleClassTalentOrSpecFrame) == "function" then pcall(PSU.ToggleClassTalentOrSpecFrame) return true end
    if PSU and type(PSU.TogglePlayerSpellsFrame) == "function" then pcall(PSU.TogglePlayerSpellsFrame) return true end
    local b = _G.TalentMicroButton
    if b and b.Click then pcall(b.Click, b) return true end
    return false
end

-- ============================================================
-- THE ICON (the live one and the page's sample)
-- ============================================================
function TR.Build(parent, sample)
    local UI = ns.UI
    local f = CreateFrame("Button", (not sample) and "ZacUITalentReminder" or nil, parent or UIParent)
    f:SetSize(DEFAULT_SIZE, DEFAULT_SIZE)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ICON)
    ZacUI.Look.CropIcon(icon)
    f._zIcon = icon
    if UI then
        UI.Border(f, "ui", "accent")
        f._zPaint = function(self) UI.PaintBox(self) end
    end
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    f._zCount = fs
    if not sample then
        f:SetFrameStrata("MEDIUM")
        f:RegisterForClicks("LeftButtonUp")
        f:SetScript("OnClick", function() TR.OpenTalents() end)
        if UI and UI.Tooltip then
            UI.Tooltip(f, "Unspent talent points", "Click to open your talents. Movers places this icon.")
        end
    else
        f:EnableMouse(false)
    end
    return f
end

function TR.Style(f, count)
    local d = DB()
    local size = TR.Size()
    f:SetSize(size, size)
    local fs = f._zCount
    if ns.ApplyFontSpec then
        ns.ApplyFontSpec(fs, d.countFont, TR.COUNT_FONT_DEFAULTS)
    elseif ns.HouseFont then
        ns.HouseFont(fs, 12, "OUTLINE")
    end
    local c = GetColor("text", "gold")
    fs:SetTextColor(c.r, c.g, c.b, 1)
    fs:SetText(tostring(count or 0))
    if f._zPaint then f:_zPaint() end
end

local live
local function Live()
    if live then return live end
    live = TR.Build(UIParent, false)
    live:Hide()
    live:ClearAllPoints()
    live:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -230, -12)
    if ns.ApplyMover then ns.ApplyMover(MOVER) end
    return live
end
TR.Frame = function() return live end

local testUntil = 0
function TR.Refresh()
    local on = TR.On() and TR.Available() and not (ns.FeatureOn and not ns.FeatureOn(OWN_ID))
    local n = on and TR.Unspent() or nil
    -- the Test button: a sample count while nothing real is there to show
    if GetTime() < testUntil and (n == nil or n == 0) then n = 3 end
    if n and n > 0 then
        local f = Live()
        TR.Style(f, n)
        f:Show()
    elseif live then
        live:Hide()
    end
end
local soon = ns.Coalesce and ns.Coalesce(TR.Refresh) or TR.Refresh
TR.Apply = function() soon() end

-- the Test button: the icon with a sample count for five seconds
function TR.Test()
    testUntil = GetTime() + 5
    TR.Refresh()
    C_Timer.After(5.1, function() pcall(TR.Refresh) end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "CHARACTER_POINTS_CHANGED")
pcall(ev.RegisterEvent, ev, "PLAYER_TALENT_UPDATE")
pcall(ev.RegisterEvent, ev, "PLAYER_LEVEL_UP")
ev:SetScript("OnEvent", function() if TR.On() then soon() end end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if ns.RegisterMover then
        ns.RegisterMover(MOVER, "Unspent talents", function() return live end, "TOPRIGHT", -230, -12, nil, { own = true })
    end
    if ns.OnSettingsChanged then ns.OnSettingsChanged(function() soon() end) end
end)

-- ============================================================
-- THE PAGE: a card on Quality of life > Reminders
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

AddTab("qol", "reminders", "Reminders", function(L)
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    local d = DB()
    L:Card("Unspent talent points")
    if not TR.Available() then
        L:Desc("This client has no talent point count for addons to read, so there is nothing to show.")
        L:EndCard()
        return
    end
    local on = UI.Checkbox(L.current, "Show an icon while I have points to spend", TR.On(), function(v)
        d.enabled = v or nil
        TR.Refresh()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "A small book icon with the count, near the minimap by default (Movers moves it). "
        .. "Click it to open your talents. Gone while every point is spent." })
    L:Row(on, 17)
    -- the sample, styled live
    local row = UI.Holder(L.current)
    row:SetSize(200, TR.Size() + 4)
    local sample = TR.Build(row, true)
    sample:SetPoint("LEFT", row, "LEFT", 2, 0)
    TR.Style(sample, 3)
    local hint = UI.Font(row, UI.F.SMALL, { cat = "text", key = "gray", text = "the icon, as it looks" })
    hint:SetPoint("LEFT", sample, "RIGHT", 8, 0)
    L:Row(row, TR.Size() + 8)
    local kids = {}
    kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 16, max = 64, step = 2,
        value = TR.Size(), label = "Size",
        format = function(v) return v .. " px" end,
        onChange = function(v)
            d.size = (v ~= DEFAULT_SIZE) and v or nil
            TR.Style(sample, 3)
            TR.Refresh()
        end })
    kids[#kids + 1] = UI.Button(L.current, "Test", { width = 80,
        tooltip = "Shows the icon with a made-up count for five seconds.",
        onClick = function() TR.Test() end })
    L:Dependent(kids, TR.On(), 1, nil, "Show an icon while I have points to spend")
    if Kit then
        Kit.Font(L, "Count", DB, "countFont", TR.COUNT_FONT_DEFAULTS,
            { sample = "3", after = function() TR.Style(sample, 3) TR.Refresh() end })
        if Kit.Mover and ns.MOVERS and ns.MOVERS[MOVER] then Kit.Mover(L, MOVER, "the icon") end
    end
    local n = TR.Unspent()
    if n == nil then
        L:Desc("The count cannot be read right now (hidden by the game).")
    else
        L:Desc(string.format("You have %d unspent point%s right now.", n, n == 1 and "" or "s"))
    end
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "talent talents unspent points reminder icon level up")
end
