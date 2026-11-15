-- QoL_Autos - five small automations, each its own switch, all off until
-- ticked: the DELETE confirmation typed for you, clams and other
-- containers opened out of combat, cinematics skipped (hold a key to
-- watch), a resurrection accepted out of combat, the spirit released in a
-- battleground.
-- Part of ZacUI; load order is set by the TOC (after QoL_Automation: it
-- arms itself with it).
--
-- WHAT IS HERE AND WHAT IS NOT. QoL_Automation already does gossip, junk,
-- repair, faster looting, the whisper invite and dismounting; these are
-- the ones a suite user expects that it lacked (feature cluster 3). Each
-- reads its switch per event, so a toggle needs no re-arm.
--
-- NOTHING IN A HOT EVENT. The container opener listens for
-- BAG_UPDATE_DELAYED (once at the end of a burst, not per bag) and even
-- then only marks a pass due for a short timer; the bag scan runs there,
-- never inline. Everything else rides rare events: a popup, a cinematic,
-- a resurrection, a death.
--
-- SAFE. Nothing is used in combat; the container opener needs a free bag
-- slot and no loot window; the release never fires with a Soulstone (or
-- a reincarnation) waiting, and only in a battleground, never an arena.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local Print = ns.Print
local QoL = ns.QoL
if not (QoL and QoL.DB) then return end

local A = {}
QoL.Autos = A

local function DB() return QoL.DB() end
function A.On(key) return DB()[key] == true end

local function InCombat()
    if InCombatLockdown and InCombatLockdown() then return true end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
    return false
end

-- ============================================================
-- THE DELETE CONFIRMATION, TYPED FOR YOU
-- ============================================================
-- Blizzard's DELETE_GOOD_ITEM popup asks for the word DELETE before it
-- deletes a green or better. The word is the client's own global, so a
-- localised client gets its own.
local DELETE_POPUPS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
local function FillDelete(which)
    if not DELETE_POPUPS[which] or not A.On("deleteFill") then return end
    local find = _G.StaticPopup_FindVisible
    local dlg = find and find(which)
    local box = dlg and (dlg.editBox or (dlg.GetName and _G[dlg:GetName() .. "EditBox"]))
    if box and box.SetText then
        box:SetText(_G.DELETE_ITEM_CONFIRM_STRING or "DELETE")
        -- the OK button listens to the text changing; with the word in it
        -- the client enables the button itself
    end
end
A.FillDelete = FillDelete

-- ============================================================
-- CONTAINERS OPENED OUT OF COMBAT
-- ============================================================
-- Classic Era's clams, the Naxxramas / AQ oozing bags and the fishing
-- trunks; TBC's clams. Plus whatever ids the player lists.
A.CONTAINERS = {
    [5523] = true,   -- Small Barnacled Clam
    [5524] = true,   -- Thick-shelled Clam
    [7973] = true,   -- Big-mouth Clam
    [15874] = true,  -- Soft-shelled Clam
    [24476] = true,  -- Jaggal Clam (TBC)
    [20766] = true,  -- Slimy Bag
    [20767] = true,  -- Scum Covered Bag
    [20768] = true,  -- Oozing Bag
    [21113] = true,  -- Watertight Trunk
    [21150] = true,  -- Iron Bound Trunk
    [21228] = true,  -- Mithril Bound Trunk
    [6351] = true,   -- Dented Crate
    [6352] = true,   -- Waterlogged Crate
    [6353] = true,   -- Small Chest
    [6356] = true,   -- Battered Chest
    [6357] = true,   -- Sealed Crate
}
local function ExtraContainers()
    local raw = DB().openList
    local out = {}
    if type(raw) ~= "string" then return out end
    for part in raw:gmatch("%d+") do
        local id = tonumber(part)
        if id then out[id] = true end
    end
    return out
end

local function FreeSlot()
    local Free = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
    if not Free then return true end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local ok, n = pcall(Free, bag)
        if ok and (tonumber(n) or 0) > 0 then return true end
    end
    return false
end

local function Use(bag, slot)
    if C_Container and C_Container.UseContainerItem then C_Container.UseContainerItem(bag, slot) return true end
    if _G.UseContainerItem then _G.UseContainerItem(bag, slot) return true end
    return false
end

-- one container per pass: the loot window that opens ends the pass, and
-- the next bag burst asks again
local openDue = false
function A.OpenPass()
    openDue = false
    if not A.On("openContainers") or InCombat() then return false end
    if LootFrame and LootFrame.IsShown and LootFrame:IsShown() then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
    if not FreeSlot() then return false end
    local extra = ExtraContainers()
    local Slots = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
    local ItemID = (C_Container and C_Container.GetContainerItemID) or _G.GetContainerItemID
    if not (Slots and ItemID) then return false end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n = Slots(bag) or 0
        for slot = 1, n do
            local id = ItemID(bag, slot)
            if type(id) == "number" and not (ns.IsSecret and ns.IsSecret(id))
                and (A.CONTAINERS[id] or extra[id]) then
                -- locked (being moved, or already being opened) slots are left
                local Info = C_Container and C_Container.GetContainerItemInfo
                local info = Info and Info(bag, slot)
                if not (info and info.isLocked) then
                    return Use(bag, slot)
                end
            end
        end
    end
    return false
end
local function OpenSoon()
    if openDue or not A.On("openContainers") then return end
    openDue = true
    C_Timer.After(0.8, A.OpenPass)
end

-- ============================================================
-- CINEMATICS SKIPPED, HOLD A KEY TO WATCH
-- ============================================================
local HOLD = {
    shift = function() return IsShiftKeyDown and IsShiftKeyDown() end,
    ctrl = function() return IsControlKeyDown and IsControlKeyDown() end,
    alt = function() return IsAltKeyDown and IsAltKeyDown() end,
}
A.HOLD_KEYS = { { value = "shift", text = "Shift" }, { value = "ctrl", text = "Ctrl" }, { value = "alt", text = "Alt" } }
local function Holding()
    local fn = HOLD[DB().cinematicHold or "shift"] or HOLD.shift
    return fn() and true or false
end
function A.SkipCinematic()
    if not A.On("skipCinematics") or Holding() then return false end
    if _G.CinematicFrame_CancelCinematic then pcall(_G.CinematicFrame_CancelCinematic) return true end
    if _G.StopCinematic then pcall(_G.StopCinematic) return true end
    return false
end
function A.SkipMovie()
    if not A.On("skipCinematics") or Holding() then return false end
    if _G.GameMovieFinished then pcall(_G.GameMovieFinished) return true end
    if MovieFrame and MovieFrame.Hide then pcall(MovieFrame.Hide, MovieFrame) return true end
    return false
end

-- ============================================================
-- A RESURRECTION ACCEPTED OUT OF COMBAT
-- ============================================================
function A.AcceptRes(caster)
    if not A.On("acceptRes") or InCombat() then return false end
    -- (a Soulstone's own popup is not a request from someone: nothing to do)
    if not _G.AcceptResurrect then return false end
    pcall(_G.AcceptResurrect)
    if _G.StaticPopup_Hide then
        pcall(_G.StaticPopup_Hide, "RESURRECT")
        pcall(_G.StaticPopup_Hide, "RESURRECT_NO_TIMER")
        pcall(_G.StaticPopup_Hide, "RESURRECT_NO_SICKNESS")
    end
    if DB().autoChat ~= false and caster and caster ~= "" and not (ns.IsSecret and ns.IsSecret(caster)) then
        Print("Resurrection from " .. tostring(caster) .. " accepted.")
    end
    return true
end

-- ============================================================
-- RELEASE IN A BATTLEGROUND
-- ============================================================
function A.ReleaseInBG()
    if not A.On("bgRelease") then return false end
    if not IsInInstance then return false end
    local inInstance, kind = IsInInstance()
    if not (inInstance and kind == "pvp") then return false end
    if _G.HasSoulstone and _G.HasSoulstone() then return false end
    if not _G.RepopMe then return false end
    pcall(_G.RepopMe)
    return true
end

-- ============================================================
-- ARMING
-- ============================================================
local armed = false
local ev
local function Arm()
    if armed then return end
    armed = true
    ev = CreateFrame("Frame")
    pcall(ev.RegisterEvent, ev, "BAG_UPDATE_DELAYED")
    pcall(ev.RegisterEvent, ev, "CINEMATIC_START")
    pcall(ev.RegisterEvent, ev, "PLAY_MOVIE")
    pcall(ev.RegisterEvent, ev, "RESURRECT_REQUEST")
    pcall(ev.RegisterEvent, ev, "PLAYER_DEAD")
    pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event, arg1)
        if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_REGEN_ENABLED" then
            OpenSoon()
        elseif event == "CINEMATIC_START" then
            A.SkipCinematic()
        elseif event == "PLAY_MOVIE" then
            -- the movie frame shows a beat later; both paths are harmless twice
            C_Timer.After(0.1, A.SkipMovie)
        elseif event == "RESURRECT_REQUEST" then
            A.AcceptRes(arg1)
        elseif event == "PLAYER_DEAD" then
            A.ReleaseInBG()
        end
    end)
    if _G.hooksecurefunc and _G.StaticPopup_Show then
        hooksecurefunc("StaticPopup_Show", function(which) FillDelete(which) end)
    end
    if CinematicFrame and CinematicFrame.HookScript then
        pcall(CinematicFrame.HookScript, CinematicFrame, "OnShow", function() A.SkipCinematic() end)
    end
    if MovieFrame and MovieFrame.HookScript then
        pcall(MovieFrame.HookScript, MovieFrame, "OnShow", function() A.SkipMovie() end)
    end
end
A.Arm = Arm

-- armed with the rest of the automation when the module turns on, and
-- only once a switch is on (nothing ticked: no frame, no event, no hook)
local SWITCHES = { "deleteFill", "openContainers", "skipCinematics", "acceptRes", "bgRelease" }
function A.AnyOn()
    local d = DB()
    for _, k in ipairs(SWITCHES) do if d[k] == true then return true end end
    return false
end
local base = QoL.EnableAutomation
function QoL.EnableAutomation(...)
    if base then base(...) end
    if A.AnyOn() then Arm() end
end

-- ============================================================
-- THE PAGE: a card on Quality of life > Automation
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

AddTab("qol", "auto", "Automation", function(L)
    if ns.FeatureOn and not ns.FeatureOn("qol_autos") then return end
    local UI = ns.UI
    local d = DB()
    local function Check(key, label, tip)
        local w = UI.Checkbox(L.current, label, d[key] == true, function(v)
            d[key] = v and true or nil
            -- (only while the module runs: standing down behind Leatrix
            -- Plus, nothing is armed here either)
            if v and QoL.enabled then Arm() end
            if ns.RefreshConfig then ns.RefreshConfig() end
        end, tip and { tooltip = tip } or nil)
        L:Row(w, 17)
        return w
    end
    L:Card("Small automations")
    Check("deleteFill", "Type DELETE for me",
        "The confirmation that asks you to type DELETE before destroying a good item is filled in; you still press the button.")
    Check("openContainers", "Open clams and crates on their own",
        "Clams, oozing bags, fishing trunks and the crates in the list below are opened when they land in your bags, "
        .. "out of combat, with a free slot, one at a time.")
    local list = UI.EditBox(L.current, { width = 260, text = d.openList or "",
        hint = "more item ids, comma between",
        onChange = function(v) d.openList = (v and v ~= "") and v or nil end })
    L:Dependent({ list }, d.openContainers == true, 1, nil, "Open clams and crates on their own")
    Check("skipCinematics", "Skip cinematics",
        "In-game cinematics and movies end at once. Hold the key below while one starts to watch it.")
    local hold = UI.Field(L.current, "Hold to watch", function(h)
        return UI.Dropdown(h, { width = 120,
            items = function() return A.HOLD_KEYS end,
            selectedValue = function() return d.cinematicHold or "shift" end,
            selected = function()
                for _, k in ipairs(A.HOLD_KEYS) do if k.value == (d.cinematicHold or "shift") then return k.text end end
                return "Shift"
            end,
            onSelect = function(v) d.cinematicHold = (v ~= "shift") and v or nil end })
    end, { width = 120 })
    L:Dependent({ hold }, d.skipCinematics == true, 1, nil, "Skip cinematics")
    Check("acceptRes", "Accept a resurrection out of combat",
        "A resurrection offered while you are out of combat is taken at once, with a line in chat saying whose.")
    Check("bgRelease", "Release at once in battlegrounds",
        "When you die in a battleground your spirit is released straight away (never in an arena, never with a Soulstone waiting).")
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "delete confirm clam container open cinematic movie skip resurrect accept release battleground spirit")
end
