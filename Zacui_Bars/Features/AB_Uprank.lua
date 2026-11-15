-- AB_Uprank - when you learn a higher rank of a spell that sits on one of
-- ZacUI's action bars, the button is given the new rank (out of combat,
-- with a line in chat). Off by default (Bars > General, "New ranks");
-- a list of spells it never touches (a heal you keep low on purpose).
-- Part of ZacUI; load order is set by the TOC (after AB_ActionBars: it
-- walks the bars' buttons).
--
-- WHAT GETS SWAPPED. Only a button holding the rank that WAS your best
-- before you learned the new one: a lower rank you put there yourself
-- stays as it is. The best rank is the game's own answer to the spell's
-- name (GetSpellInfo by name: the highest rank known), remembered when
-- the feature turns on and after every pass. Levelling on Forever (or a
-- fresh character anywhere) is where it earns its keep; Era and TBC work
-- the same.
--
-- SAFE. PickupSpell / PlaceAction only out of combat, only with nothing
-- on the cursor; a pass due in a fight waits for its end. Nothing runs
-- while off: the two events are registered when it is switched on.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local AB = ns.Bars
if not AB then return end

local Print = ns.Print
local UP = {}
AB.Uprank = UP

local OWN_ID = "bars_uprank"

-- ============================================================
-- SETTINGS (ZacUIDB.bars.uprank; nothing saved = off) - read without writing
-- ============================================================
local EMPTY = {}
local function Cfg()
    local d = ZacUIDB and ZacUIDB.bars
    local u = type(d) == "table" and d.uprank
    return type(u) == "table" and u or EMPTY
end
local function Writable()
    local d = AB.DB()
    if type(d.uprank) ~= "table" then d.uprank = {} end
    return d.uprank
end
UP.Cfg, UP.Writable = Cfg, Writable
function UP.On()
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return false end
    return Cfg().enabled == true
end
-- the never-touch list: names, comma between, any case
function UP.Excluded(name)
    local raw = Cfg().exclude
    if type(raw) ~= "string" or type(name) ~= "string" then return false end
    local want = name:lower()
    for part in raw:gmatch("[^,]+") do
        local n = part:gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if n ~= "" and n == want then return true end
    end
    return false
end

local function Hidden(v) return ns.IsSecret and ns.IsSecret(v) or false end
local function InCombat() return InCombatLockdown and InCombatLockdown() or false end

-- ============================================================
-- THE SPELLS ON THE BARS
-- ============================================================
-- every action slot a ZacUI bar button shows (its own, and the page it
-- is on now)
function UP.Slots()
    local out, seen = {}, {}
    for _, header in pairs(AB.headers or {}) do
        for _, btn in ipairs(header.buttons or {}) do
            if btn.zAbs then
                for _, s in ipairs({ btn.zAbs, btn.action or (btn.GetAttribute and btn:GetAttribute("action")) }) do
                    s = tonumber(s)
                    if s and not seen[s] then seen[s] = true out[#out + 1] = s end
                end
            end
        end
    end
    table.sort(out)
    return out
end

local function SpellAt(slot)
    if not GetActionInfo then return nil end
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok or Hidden(kind) or Hidden(id) then return nil end
    if kind ~= "spell" or type(id) ~= "number" then return nil end
    return id
end

-- the name of a spell, and the best rank of it you know (the game's own
-- answer to the name)
local function NameOf(id)
    if not GetSpellInfo then return nil end
    local ok, name = pcall(GetSpellInfo, id)
    if not ok or Hidden(name) or type(name) ~= "string" then return nil end
    return name
end
local function BestOf(name)
    if not (GetSpellInfo and name) then return nil end
    local ok, _, _, _, _, _, _, id = pcall(GetSpellInfo, name)
    if not ok or Hidden(id) or type(id) ~= "number" then return nil end
    return id
end
UP.NameOf, UP.BestOf = NameOf, BestOf

local function RankText(id)
    if GetSpellSubtext then
        local ok, s = pcall(GetSpellSubtext, id)
        if ok and type(s) == "string" and s ~= "" and not Hidden(s) then return s end
    end
    return nil
end

-- the best rank of every spell on the bars, as it is now
local best = {}
function UP.Snapshot()
    wipe(best)
    for _, slot in ipairs(UP.Slots()) do
        local id = SpellAt(slot)
        local name = id and NameOf(id)
        if name and best[name] == nil then best[name] = BestOf(name) or false end
    end
end
UP.Best = function() return best end

-- what a pass would do: { slot, from, to, name } for each button holding
-- the old best rank of a spell whose best has moved on
function UP.Plan()
    local out = {}
    for _, slot in ipairs(UP.Slots()) do
        local id = SpellAt(slot)
        local name = id and NameOf(id)
        if name and not UP.Excluded(name) then
            local was = best[name]
            local now = BestOf(name)
            if was and now and now ~= was and id == was then
                out[#out + 1] = { slot = slot, from = id, to = now, name = name }
            end
        end
    end
    return out
end

-- ============================================================
-- THE PASS (out of combat only)
-- ============================================================
local pending = false
local function Place(slot, id)
    if PickupSpell then PickupSpell(id) end
    if not (GetCursorInfo and GetCursorInfo()) then return false end
    if PlaceAction then PlaceAction(slot) end
    if ClearCursor then ClearCursor() end
    return SpellAt(slot) == id
end

function UP.Pass()
    if not UP.On() or not AB.active then pending = false return 0 end
    if InCombat() then pending = true return 0 end
    -- (something on the cursor is the player's: leave it, try later)
    if GetCursorInfo and GetCursorInfo() then pending = true C_Timer.After(2, UP.Pass) return 0 end
    pending = false
    local done = 0
    local said = {}
    for _, step in ipairs(UP.Plan()) do
        if Place(step.slot, step.to) then
            done = done + 1
            if not said[step.name] then
                said[step.name] = true
                local r = RankText(step.to)
                Print("Bars: " .. step.name .. (r and (" is now " .. r) or " has a new rank") .. " on your bars.")
            end
        end
    end
    UP.Snapshot()
    return done
end
UP.Pending = function() return pending end

-- ============================================================
-- ON / OFF
-- ============================================================
local ev
local function OnEvent(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then C_Timer.After(0.5, UP.Pass) end
        return
    end
    -- a spell learned: the spellbook settles a moment later
    if not pending then
        pending = true
        C_Timer.After(0.5, UP.Pass)
    end
end
function UP.Apply()
    if UP.On() and AB.active then
        if not ev then
            ev = CreateFrame("Frame")
            ev:SetScript("OnEvent", OnEvent)
        end
        pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_TAB")
        pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_SKILL_LINE")
        pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
        if not UP.armed then
            UP.armed = true
            UP.Snapshot()
        end
    else
        if ev then ev:UnregisterAllEvents() end
        UP.armed = nil
        pending = false
    end
end
UP.Registered = function() return ev ~= nil and UP.armed == true end

-- with the bars (the module's start at login), and on a settings change
if ns.Modules and type(ns.Modules.bars) == "function" then
    local base = ns.Modules.bars
    ns.Modules.bars = function(...)
        base(...)
        pcall(UP.Apply)
    end
end
if ns.OnSettingsChanged then ns.OnSettingsChanged(function() pcall(UP.Apply) end) end

-- ============================================================
-- THE PAGE: Bars > General
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

AddTab("bars", "general", "General", function(L)
    if ns.FeatureOn and not ns.FeatureOn(OWN_ID) then return end
    local UI = ns.UI
    L:Card("New ranks")
    local on = UI.Checkbox(L.current, "Put a new rank on my bars when I learn it", Cfg().enabled == true, function(v)
        Writable().enabled = v or nil
        UP.Apply()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "When you learn a higher rank of a spell that is on ZacUI's bars, the buttons that held your "
        .. "best rank get the new one (out of combat, with a line in chat). A lower rank you put on a button "
        .. "yourself is left alone." })
    L:Row(on, 17)
    local list = UI.EditBox(L.current, { width = 300, text = type(Cfg().exclude) == "string" and Cfg().exclude or "",
        hint = "never these: spell names, comma between",
        onChange = function(v) Writable().exclude = (v and v:match("%S")) and v or nil end })
    local check = UI.Button(L.current, "Check now", { width = 100,
        tooltip = "Looks at your bars now and swaps in any new rank (out of combat).",
        onClick = function()
            if not (UP.On() and AB.active) then return end
            if InCombat() then Print("Bars: after the fight.") pending = true return end
            local plan = UP.Plan()
            if #plan == 0 then Print("Bars: every spell on your bars is at the rank it was.") return end
            UP.Pass()
        end })
    L:Dependent({ list, check }, Cfg().enabled == true, 1, nil, "Put a new rank on my bars when I learn it")
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("bars", "rank uprank new rank learned spell levelling trainer")
end
