-- QoL_Durability - a one-line warning when anything you wear is under a
-- durability threshold: on login, on a zone change and after a death,
-- the moments gear gets checked anyway. Off by default (Quality of life
-- > Reminders).
-- Part of ZacUI; load order is set by the TOC.
--
-- THE WARNING is ZacUI's alert line: the game's raid-warning frame in the
-- middle of the screen (the same line the threat warnings use), in the
-- colour picked, a line in chat with the worst piece, and a sound on the
-- customization standard (qol.durability.sounds.warn; nothing saved = a
-- beep). The threshold is a slider (20% by default). A Test button shows
-- the line with made-up numbers.
--
-- Never in a fight: a death's check waits until you are alive and out of
-- combat. The slots are the eleven that wear (shirt and tabard do not).
-- WoW Forever may hide a durability read in a fight; a hidden value is
-- skipped (the checks run out of combat anyway).
--
-- COST: four rare events, one pass over eleven slots each.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local Print = ns.Print
local QoL = ns.QoL

local DW = {}
QoL.Durability = DW

local OWN_ID = "durability_warning"
local DEFAULT_THRESHOLD = 20
local WEAR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }
local SLOT_NAMES = {
    [1] = "Head", [3] = "Shoulders", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrists", [10] = "Hands", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged",
}
DW.SOUND_DEFAULTS = { sound = "ui:Beep", channel = "Master", throttle = 0 }
DW.SOUND_KEY = "qol.durability"
local REPEAT_AFTER = 60      -- the same warning not twice within a minute

-- ============================================================
-- SETTINGS (qol.durability; nothing saved = off, 20%)
-- ============================================================
local function DB()
    local q = QoL.DB()
    if type(q.durability) ~= "table" then q.durability = {} end
    return q.durability
end
DW.DB = DB
function DW.On() return DB().enabled == true end
function DW.Threshold()
    local v = tonumber(DB().threshold) or DEFAULT_THRESHOLD
    return math.max(5, math.min(90, v))
end
function DW.Chat() return DB().chat ~= false end
function DW.Screen() return DB().screen ~= false end

-- ============================================================
-- THE CHECK
-- ============================================================
-- the most worn piece: percent (0-100) and its slot, or nil with nothing worn
function DW.Worst()
    if type(GetInventoryItemDurability) ~= "function" then return nil end
    local low, slot
    for _, s in ipairs(WEAR_SLOTS) do
        local ok, cur, max = pcall(GetInventoryItemDurability, s)
        if ok and type(cur) == "number" and type(max) == "number" and max > 0
            and not (ns.IsSecret and (ns.IsSecret(cur) or ns.IsSecret(max))) then
            local pct = cur / max * 100
            if not low or pct < low then low, slot = pct, s end
        end
    end
    return low, slot
end

-- the line, as the screen and the chat show it
function DW.Text(pct, slot)
    local name = SLOT_NAMES[slot] or "gear"
    return string.format("Low durability: %s at %d%%", name, math.floor(pct + 0.5))
end

local lastAt, lastSlot = 0, nil
function DW.Warn(pct, slot, test)
    local text = DW.Text(pct, slot)
    local r, g, b = 1, 0.6, 0.2
    local c = DB().color
    if type(c) == "table" and ns.ColorOf then
        r, g, b = ns.ColorOf(c)
    else
        local p = GetColor("text", "orange")
        r, g, b = p.r, p.g, p.b
    end
    if DW.Screen() and RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = r, g = g, b = b })
    end
    if DW.Chat() or test then
        Print(string.format("|cff%02x%02x%02x%s|r - repair when you can.", r * 255, g * 255, b * 255, text))
    end
    if ns.PlaySoundSpec then
        local d = DB()
        local spec = type(d.sounds) == "table" and d.sounds.warn or nil
        ns.PlaySoundSpec(spec, DW.SOUND_DEFAULTS, (not test) and DW.SOUND_KEY or nil)
    end
    return text
end

-- true when it warned
function DW.Check(force)
    if not DW.On() then return false end
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local pct, slot = DW.Worst()
    if not pct or pct >= DW.Threshold() then
        lastSlot = nil
        return false
    end
    local now = GetTime()
    if not force and slot == lastSlot and now - lastAt < REPEAT_AFTER then return false end
    lastAt, lastSlot = now, slot
    DW.Warn(pct, slot, false)
    return true
end

-- the Test button: the line with made-up numbers, through the same path
function DW.Test()
    return DW.Warn(math.max(1, DW.Threshold() - 7), 5, true)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("PLAYER_UNGHOST")
ev:RegisterEvent("PLAYER_ALIVE")
ev:SetScript("OnEvent", function(self, event)
    if not DW.On() then return end
    -- a couple of seconds on, so the gear (and a death's wear) has landed
    C_Timer.After(2, function()
        if InCombatLockdown and InCombatLockdown() then
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        pcall(DW.Check)
    end)
end)
ev:HookScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        pcall(DW.Check)
    end
end)

function DW.Apply() end

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
    L:Card("Low durability")
    local on = UI.Checkbox(L.current, "Warn when my gear is worn down", DW.On(), function(v)
        d.enabled = v or nil
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "On login, on a zone change and after a death: when any piece you wear is under the "
        .. "threshold, one line in the middle of the screen names the worst piece, with a line in chat and a sound." })
    L:Row(on, 17)
    local kids = {}
    kids[#kids + 1] = UI.Slider(L.current, { width = 220, min = 5, max = 90, step = 5,
        value = DW.Threshold(), label = "Warn under",
        format = function(v) return v .. "%" end,
        onChange = function(v) d.threshold = (v ~= DEFAULT_THRESHOLD) and v or nil end })
    kids[#kids + 1] = UI.Checkbox(L.current, "On the screen", DW.Screen(), function(v)
        if v then d.screen = nil else d.screen = false end
    end, { tooltip = "The game's raid-warning line in the middle of the screen." })
    kids[#kids + 1] = UI.Checkbox(L.current, "In chat", DW.Chat(), function(v)
        if v then d.chat = nil else d.chat = false end
    end)
    if Kit then
        local p = UI.ColorPicker(L.current, { label = "Colour",
            get = function()
                local c = d.color
                if type(c) == "table" then return ns.ColorOf(c) end
                local o = GetColor("text", "orange")
                return o.r, o.g, o.b, 1
            end,
            set = function(r, g, b) d.color = { r = r, g = g, b = b, a = 1 } end })
        kids[#kids + 1] = p
    end
    if UI.SoundSpecPicker and ns.CustomAccess then
        local get, set = ns.CustomAccess(DB, "sounds", "warn")
        kids[#kids + 1] = UI.SoundSpecPicker(L.current, { get = get, set = set, defaults = DW.SOUND_DEFAULTS,
            width = UI.CardInnerWidth and UI.CardInnerWidth(L) or nil })
    end
    kids[#kids + 1] = UI.Button(L.current, "Test", { width = 80,
        tooltip = "Shows the warning with made-up numbers.",
        onClick = function() DW.Test() end })
    L:Dependent(kids, DW.On(), 1, nil, "Warn when my gear is worn down")
    local pct, slot = DW.Worst()
    if pct then
        L:Desc(string.format("Right now your most worn piece is %s at %d%%.", SLOT_NAMES[slot] or "?", math.floor(pct + 0.5)))
    end
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "durability repair worn broken gear armor warning threshold reminder")
end
