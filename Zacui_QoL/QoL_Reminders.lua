-- QoL_Reminders - small icons for things you forget, and a line at a
-- ready check:
--   No pet         a hunter or warlock without their pet out
--   Passive        your pet left on Passive
--   Tracking       you can track herbs or minerals and nothing is tracked
--   Mana           at a ready check, your mana under 80% (a line in the
--                  middle of the screen, on the alerts' spot)
-- Each its own switch, all off by default. Quality of life > Reminders.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHEN AN ICON SHOWS: never while you are mounted, on a flight, or dead
-- (a pet is sent away or set to Passive by the game then); the pet ones
-- not while resting in a city unless you say so. Each icon has its
-- tooltip; they sit in one row with a mover ("Reminders").
--
-- READING: the pet's stance from the pet bar (the game's own Passive
-- token), tracking from the minimap's tracking (C_Minimap where the client
-- has it, the single tracking texture on the older clients). Re-read a
-- moment after the events that change them (pet, pet bar, tracking,
-- mount, rest, spells), never on a timer.
--
-- COST: nothing while off; on, a few rare events.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local QoL = ns.QoL
if not QoL then return end

local R = {}
QoL.Reminders = R

local OWN_ID = "qol_reminders"
local MOVER = "qolreminders"
local ICON, PITCH = 32, 52
local DELAY = 0.2
R.MANA_DEFAULT = 80

-- the spells that say a class keeps a pet, and the tracking spells
local PET_SPELLS = {
    HUNTER = { 883 },                                  -- Call Pet
    WARLOCK = { 688, 697, 712, 691, 30146 },           -- Imp, Voidwalker, Succubus, Felhunter, Felguard
}
local TRACK_SPELLS = { 2383, 2580 }                    -- Find Herbs, Find Minerals

R.ITEMS = {
    { id = "pet", label = "No pet", key = "pet",
      icon = "Interface\\Icons\\Ability_Hunter_BeastCall", tip = "Your pet is not out." },
    { id = "passive", label = "Passive", key = "passive",
      icon = "Interface\\Icons\\Ability_Seal", tip = "Your pet is set to Passive: it will not fight back." },
    { id = "tracking", label = "Tracking", key = "tracking",
      icon = "Interface\\Icons\\INV_Misc_Flower_02", tip = "You can track herbs or minerals and nothing is tracked." },
}

local function Hidden(v) return ns.IsSecret and ns.IsSecret(v) or false end

-- ============================================================
-- SETTINGS (qol.reminders; nothing saved = off)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.reminders) ~= "table" then q.reminders = {} end
    return q.reminders
end
R.DB = DB
local function Allowed() return not (ns.FeatureOn and not ns.FeatureOn(OWN_ID)) end
function R.On(key) return Allowed() and QoL.enabled == true and DB()[key] == true end
function R.AnyIcon() return R.On("pet") or R.On("passive") or R.On("tracking") end
function R.ManaUnder()
    local v = tonumber(DB().manaUnder) or R.MANA_DEFAULT
    return math.max(10, math.min(100, v))
end

-- ============================================================
-- THE CHECKS (each true when its icon should show)
-- ============================================================
local function Known(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end
local function Busy()
    if IsMounted and IsMounted() then return true end
    if UnitOnTaxi and UnitOnTaxi("player") then return true end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return true end
    return false
end
local function PetClass()
    local file = UnitClass and select(2, UnitClass("player"))
    local list = file and PET_SPELLS[file]
    if not list then return false end
    for _, id in ipairs(list) do if Known(id) then return true end end
    return false
end
local function Resting() return DB().inCities ~= true and IsResting and IsResting() or false end

function R.NeedPet()
    if Busy() or Resting() or not PetClass() then return false end
    local has = UnitExists and UnitExists("pet")
    if Hidden(has) then return false end
    if has and UnitIsDead and UnitIsDead("pet") then has = false end
    return not has
end

function R.PetPassive()
    if Busy() or not (UnitExists and UnitExists("pet")) or type(GetPetActionInfo) ~= "function" then return false end
    for i = 1, (_G.NUM_PET_ACTION_SLOTS or 10) do
        local name, _, _, active = GetPetActionInfo(i)
        if name == "PET_MODE_PASSIVE" then
            if Hidden(active) then return false end
            return active == true
        end
    end
    return false
end

-- whether any tracking is on (any kind: a hunter's beasts count too)
function R.Tracking()
    local M = _G.C_Minimap
    if M and type(M.GetNumTrackingTypes) == "function" and type(M.GetTrackingInfo) == "function" then
        for i = 1, (M.GetNumTrackingTypes() or 0) do
            local a, b, c = M.GetTrackingInfo(i)
            local active
            if type(a) == "table" then active = a.active else active = c end
            if active == true then return true end
        end
        return false
    end
    if type(GetTrackingTexture) == "function" then return GetTrackingTexture() ~= nil end
    return true    -- no way to ask: never nag
end
function R.NeedTracking()
    if Busy() then return false end
    local can = false
    for _, id in ipairs(TRACK_SPELLS) do if Known(id) then can = true end end
    if not can then return false end
    return not R.Tracking()
end

local CHECK = { pet = R.NeedPet, passive = R.PetPassive, tracking = R.NeedTracking }

-- ============================================================
-- THE ICONS
-- ============================================================
local strip
local icons = {}
local function Font(fs, size)
    if ns.HouseFont then ns.HouseFont(fs, size, "OUTLINE")
    else fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE") end
end

local function Strip()
    if strip then return strip end
    strip = CreateFrame("Frame", "ZacUIReminders", UIParent)
    strip:SetSize(ICON, ICON + 16)
    strip:SetFrameStrata("MEDIUM")
    strip:EnableMouse(false)
    strip:Hide()
    strip:ClearAllPoints()
    strip:SetPoint("CENTER", UIParent, "CENTER", 0, 230)
    if ns.ApplyMover then ns.ApplyMover(MOVER) end
    return strip
end
R.Frame = function() return strip end
R.Icon = function(id) return icons[id] end

local function Icon(item)
    if icons[item.id] then return icons[item.id] end
    local UI = ns.UI
    local f = CreateFrame("Frame", nil, Strip())
    f:SetSize(ICON, ICON)
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(item.icon)
    if ZacUI and ZacUI.Look and ZacUI.Look.CropIcon then ZacUI.Look.CropIcon(t) else t:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    if UI then
        UI.Border(f, "ui", "accent")
        f._zPaint = function(self) UI.PaintBox(self) end
        f:_zPaint()
    end
    local fs = f:CreateFontString(nil, "OVERLAY")
    Font(fs, 11)
    fs:SetPoint("TOP", f, "BOTTOM", 0, -3)
    fs:SetText(item.label)
    f._zLabel = fs
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(item.label, 1, 1, 1)
        GameTooltip:AddLine(item.tip, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    icons[item.id] = f
    return f
end

-- which icons are up now; shows them in a row
function R.Refresh(test)
    local up = {}
    for _, item in ipairs(R.ITEMS) do
        if test or (R.On(item.key) and CHECK[item.id]()) then up[#up + 1] = item end
    end
    if #up == 0 then
        if strip then strip:Hide() end
        return up
    end
    Strip()
    for _, f in pairs(icons) do f:Hide() end
    for i, item in ipairs(up) do
        local f = Icon(item)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", strip, "TOPLEFT", (i - 1) * PITCH, 0)
        f:Show()
    end
    strip:SetSize((#up - 1) * PITCH + ICON, ICON + 16)
    strip:Show()
    return up
end
function R.Test()
    R.Refresh(true)
    C_Timer.After(6, function() R.Refresh() end)
end

-- ============================================================
-- THE READY-CHECK MANA LINE
-- ============================================================
function R.ManaText(pct) return string.format("Mana %d%% - drink before the pull", pct) end
function R.ReadyCheck(test)
    if not test and not R.On("mana") then return false end
    local pct
    if test then pct = 64 else
        if UnitPowerType and UnitPowerType("player") ~= 0 then return false end
        local cur, max = UnitPower("player", 0), UnitPowerMax("player", 0)
        if Hidden(cur) or Hidden(max) or not max or max <= 0 then return false end
        pct = math.floor(cur / max * 100)
        if pct >= R.ManaUnder() then return false end
    end
    local c = GetColor("text", "blue")
    local A = QoL.Alerts
    if A and A.Show then
        A.Show("mana", c.r, c.g, c.b, R.ManaText(pct))
    elseif RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, R.ManaText(pct), { r = c.r, g = c.g, b = c.b })
    end
    return true
end

-- ============================================================
-- EVENTS
-- ============================================================
local ev
local pending = false
local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(DELAY, function()
        pending = false
        pcall(R.Refresh)
    end)
end
local ICON_EVENTS = { "PLAYER_ENTERING_WORLD", "UNIT_PET", "PET_BAR_UPDATE", "MINIMAP_UPDATE_TRACKING",
    "PLAYER_UPDATE_RESTING", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
    "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_DEAD", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED" }

function R.Apply()
    local icons_, mana = R.AnyIcon(), R.On("mana")
    if not (icons_ or mana) then
        if ev then ev:UnregisterAllEvents() end
        if strip then strip:Hide() end
        return
    end
    if not ev then
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event, unit)
            if event == "READY_CHECK" then R.ReadyCheck() return end
            if event == "UNIT_PET" and unit ~= "player" then return end
            Schedule()
        end)
    end
    for _, e in ipairs(ICON_EVENTS) do
        if icons_ then pcall(ev.RegisterEvent, ev, e) else pcall(ev.UnregisterEvent, ev, e) end
    end
    if mana then ev:RegisterEvent("READY_CHECK") else ev:UnregisterEvent("READY_CHECK") end
    if icons_ then Schedule() elseif strip then strip:Hide() end
end
function R.Registered(e) return ev ~= nil and ev:IsEventRegistered(e) or false end

local function Live() if QoL.enabled then R.Apply() end end
R.Live = Live
if Allowed() then
    if ns.RegisterMover then
        ns.RegisterMover(MOVER, "Reminders", function() return strip end, "CENTER", 0, 230, nil, { own = true })
    end
    local base = QoL.EnableAutomation
    function QoL.EnableAutomation(...)
        if base then base(...) end
        pcall(R.Apply)
    end
end

-- ============================================================
-- THE PAGE: Quality of life > Reminders
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local l = ns.PageTabs[page] or {}
    ns.PageTabs[page] = l
    l[#l + 1] = { tab = tab, label = label, build = build }
end

AddTab("qol", "reminders", "Reminders", function(L)
    if not Allowed() then return end
    local UI = ns.UI
    local Kit = ns.CorePageKit
    local d = DB()
    local function Changed()
        Live()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end
    local function Check(key, label, tip)
        local w = UI.Checkbox(L.current, label, d[key] == true, function(v)
            d[key] = v and true or nil
            Changed()
        end, tip and { tooltip = tip } or nil)
        L:Row(w, 17)
        return w
    end
    L:Card("Pet and tracking")
    Check("pet", "Remind me when my pet is not out",
        "Hunters and warlocks: an icon while you have no pet out (not while mounted, flying or dead).")
    Check("passive", "Remind me when my pet is on Passive",
        "An icon while your pet is set to Passive, so it will not fight back.")
    local cities = UI.Checkbox(L.current, "In cities too", d.inCities == true, function(v)
        d.inCities = v and true or nil
        Live()
    end, { tooltip = "Off: no pet reminder while you are resting in a city or an inn." })
    L:Dependent({ cities }, d.pet == true, 1, nil, "Remind me when my pet is not out")
    Check("tracking", "Remind me when nothing is tracked",
        "If you can track herbs or minerals and no tracking is on (any tracking counts, a hunter's beasts too).")
    local test = UI.Button(L.current, "Test", { width = 80,
        tooltip = "Shows all three icons for a few seconds.", onClick = function() R.Test() end })
    L:Row(test, 26)
    if Kit and Kit.Mover and ns.MOVERS and ns.MOVERS[MOVER] then Kit.Mover(L, MOVER, "the icons") end
    L:EndCard()

    L:Card("Ready check")
    Check("mana", "Warn me at a ready check when my mana is low",
        "A line in the middle of the screen (where the alerts show) when a ready check starts and your mana is under the amount below.")
    local s = UI.Slider(L.current, { width = 220, min = 10, max = 100, step = 5,
        value = R.ManaUnder(), label = "Mana under",
        format = function(v) return v .. "%" end,
        onChange = function(v) d.manaUnder = (v ~= R.MANA_DEFAULT) and v or nil end })
    local t2 = UI.Button(L.current, "Test", { width = 80,
        tooltip = "Shows the line with a made-up number.", onClick = function() R.ReadyCheck(true) end })
    L:Dependent({ s, t2 }, d.mana == true, 1, nil, "Warn me at a ready check when my mana is low")
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "pet missing passive hunter warlock tracking herbs minerals find reminder ready check mana drink")
end
