-- HUD_V2_Keybinds - Class HUD v2: the key that casts each icon's spell,
-- and the press mirror. One cache for every class HUD: for each of the
-- 120 action slots (ZacUI's shared slot reader) the key bound to the
-- button that shows it - the main bar's keys for the slots its stance /
-- form pages swap in (slots 73-120), so a warrior's keybind text does not
-- change with the stance - the multibars' keys, ZacUI's own bars' keys
-- when that part is loaded, and the spells and items a macro names in
-- its body. The lowest-numbered bar wins; a key bound straight to the
-- spell beats one through a macro.
-- Perf: slot, binding and macro events only mark the cache dirty; it is
-- rebuilt once, half a second after the last of them, out of combat (a
-- change in combat waits for the fight to end), and only while a HUD
-- shows keybind text or mirrors presses. Icons repaint when the cache's
-- version moved, on the engine's 0.2s tick.
-- Part of ZacUI; load order is set by the TOC (after HUD_V2_Sources).

local ns = _G.ZacUI
if not ns or not ns.HUD or not ns.HUD.V2 then return end
local HUD = ns.HUD
local V2 = HUD.V2

local GetSpellInfo = HUD.GetSpellInfo

local Keys = { version = 0, bySpellId = {}, bySpellName = {}, byItem = {}, byMacroName = {}, wanted = 0 }
V2.Keys = Keys

-- slot -> the Blizzard binding that shows it; the main bar's pages (1-6)
-- and its bonus pages (7-10) all answer to ACTIONBUTTON
local function BlizzBinding(slot)
    local i = (slot - 1) % 12 + 1
    if slot >= 25 and slot <= 36 then return "MULTIACTIONBAR3BUTTON" .. i end
    if slot >= 37 and slot <= 48 then return "MULTIACTIONBAR4BUTTON" .. i end
    if slot >= 49 and slot <= 60 then return "MULTIACTIONBAR2BUTTON" .. i end
    if slot >= 61 and slot <= 72 then return "MULTIACTIONBAR1BUTTON" .. i end
    return "ACTIONBUTTON" .. i
end

-- the first key bound to a slot's button, or nil
local function KeyForSlot(slot)
    local AB = ns.Bars
    local n, i = math.ceil(slot / 12), (slot - 1) % 12 + 1
    local key
    if AB and AB.KeyFor then
        key = AB.KeyFor(n, i)
    end
    if not key and GetBindingKey then
        key = GetBindingKey(BlizzBinding(slot))
    end
    if key == "" then key = nil end
    return key
end

-- "SHIFT-F" -> "S-F", mouse buttons shortened; ZacUI's bars' own
-- shortener when that part is loaded, so both read alike
local MODS = { { "SHIFT%-", "S-" }, { "CTRL%-", "C-" }, { "ALT%-", "A-" } }
local function Short(key)
    if not key or key == "" then return nil end
    local AB = ns.Bars
    if AB and AB.ShortKey then
        local s = AB.ShortKey(key)
        if s and s ~= "" then return s end
    end
    local s = key:upper()
    for _, m in ipairs(MODS) do s = s:gsub(m[1], m[2]) end
    s = s:gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD"):gsub("BUTTON", "M")
        :gsub("NUMPAD", "N"):gsub("PAGEUP", "PU"):gsub("PAGEDOWN", "PD"):gsub("SPACE", "SP")
    return s
end
Keys.Short = Short

-- lower is better: the bar the slot sits on, then "a macro, not the spell"
local function Rank(slot, macro)
    local n = math.ceil(slot / 12)
    -- the main bar's bonus pages rank with the main bar
    if n >= 7 then n = 1 end
    return n * 2 + (macro and 1 or 0)
end

local function Put(map, k, key, rank, ranks)
    if k == nil or key == nil then return end
    local cur = ranks[map][k]
    if cur == nil or rank < cur then
        ranks[map][k] = rank
        map[k] = key
    end
end

-- every spell and item a macro body names (/cast, /use, /castsequence,
-- #showtooltip), conditions stripped
local function MacroNames(body, out)
    if type(body) ~= "string" then return end
    for line in body:gmatch("[^\n]+") do
        local cmd, rest = line:match("^%s*([#/]%a+)%s*(.*)$")
        if cmd then
            cmd = cmd:lower()
            if cmd == "/cast" or cmd == "/use" or cmd == "/castsequence" or cmd == "#showtooltip" or cmd == "/castrandom" then
                rest = rest:gsub("%[.-%]", "")
                if cmd == "/castsequence" then rest = rest:gsub("^reset=[^%s,]*%s*", "") end
                for part in rest:gmatch("[^;,]+") do
                    local name = part:match("^%s*(.-)%s*$")
                    name = name:gsub("^!", "")
                    if name ~= "" then
                        local itemId = name:match("^item:(%d+)$")
                        if itemId then
                            out[#out + 1] = { item = tonumber(itemId) }
                        else
                            out[#out + 1] = { name = name:lower() }
                        end
                    end
                end
            end
        end
    end
end

local function Rebuild()
    local AS = ns.ActionSlots
    local bySpellId, bySpellName, byItem, byMacroName = {}, {}, {}, {}
    local ranks = { [bySpellId] = {}, [bySpellName] = {}, [byItem] = {}, [byMacroName] = {} }
    local names = {}
    for slot = 1, 120 do
        local kind, id
        if AS and AS.At then kind, id = AS.At(slot)
        elseif GetActionInfo then kind, id = GetActionInfo(slot) end
        if kind and id and not ns.IsSecret(id) then
            local key = KeyForSlot(slot)
            if key then
                local short = Short(key)
                if kind == "spell" then
                    Put(bySpellId, id, short, Rank(slot, false), ranks)
                    local name = GetSpellInfo and GetSpellInfo(id)
                    if name then Put(bySpellName, name:lower(), short, Rank(slot, false), ranks) end
                elseif kind == "item" then
                    Put(byItem, id, short, Rank(slot, false), ranks)
                elseif kind == "macro" and GetMacroBody then
                    wipe(names)
                    local ok, body = pcall(GetMacroBody, id)
                    if ok then MacroNames(body, names) end
                    for _, e in ipairs(names) do
                        if e.item then Put(byItem, e.item, short, Rank(slot, true), ranks)
                        elseif e.name then Put(byMacroName, e.name, short, Rank(slot, true), ranks) end
                    end
                end
            end
        end
    end
    Keys.bySpellId, Keys.bySpellName, Keys.byItem, Keys.byMacroName = bySpellId, bySpellName, byItem, byMacroName
    Keys.version = Keys.version + 1
    Keys.dirty = false
end
Keys.Rebuild = Rebuild

-- the key for a spell (id and / or name) or an item; nil = none bound
function Keys.ForSpell(id, name)
    if Keys.dirty and Keys.version == 0 then Rebuild() end
    local k = id and Keys.bySpellId[id]
    if k then return k end
    local l = name and name:lower()
    if l then
        k = Keys.bySpellName[l]
        if k then return k end
        return Keys.byMacroName[l]
    end
    return nil
end

function Keys.ForItem(id, name)
    if Keys.dirty and Keys.version == 0 then Rebuild() end
    local k = id and Keys.byItem[id]
    if k then return k end
    local l = name and name:lower()
    return l and Keys.byMacroName[l] or nil
end

-- the dirty flag and its half-second coalesce; a rebuild in combat waits
local ev = CreateFrame("Frame")
local pending, waitCombat = false, false
local function RunRebuild()
    pending = false
    if InCombatLockdown and InCombatLockdown() then
        waitCombat = true
        return
    end
    Rebuild()
end
local function MarkDirty()
    Keys.dirty = true
    if pending then return end
    pending = true
    C_Timer.After(0.5, RunRebuild)
end
Keys.MarkDirty = MarkDirty
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if waitCombat then waitCombat = false MarkDirty() end
        return
    end
    MarkDirty()
end)

-- registered only while a HUD wants keys (Want(true) / Want(false))
local WANT_EVENTS = { "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "UPDATE_MACROS", "PLAYER_ENTERING_WORLD",
    "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "PLAYER_REGEN_ENABLED" }
function Keys.Want(on)
    Keys.wanted = Keys.wanted + (on and 1 or -1)
    if Keys.wanted < 0 then Keys.wanted = 0 end
    if on and Keys.wanted == 1 then
        for _, e in ipairs(WANT_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
        MarkDirty()
    elseif not on and Keys.wanted == 0 then
        ev:UnregisterAllEvents()
    end
end

-- ------------------------------------------------------------
-- the press mirror: the icon of a pressed button darkens for the press
-- ------------------------------------------------------------
-- listeners: the engines that mirror presses (instance -> true)
Keys.pressers = setmetatable({}, { __mode = "k" })
local hooked = false

local function Pressed(slot, down)
    if not slot then return end
    local kind, id
    local AS = ns.ActionSlots
    if AS and AS.At then kind, id = AS.At(slot) elseif GetActionInfo then kind, id = GetActionInfo(slot) end
    if not kind or ns.IsSecret(id) then return end
    local name
    if kind == "spell" then name = GetSpellInfo and GetSpellInfo(id) end
    for eng in pairs(Keys.pressers) do
        if eng.V2Press then eng:V2Press(kind, id, name, down) end
    end
end

-- the slot the main bar's button `id` shows right now (its page, or the
-- stance / form page the game swapped in)
local function MainSlot(id)
    local bonus = GetBonusBarOffset and GetBonusBarOffset() or 0
    local page = GetActionBarPage and GetActionBarPage() or 1
    if ns.IsSecret(bonus) or ns.IsSecret(page) then return nil end
    if bonus and bonus > 0 and page == 1 then
        return (6 + bonus - 1) * 12 + id
    end
    return (page - 1) * 12 + id
end

local MULTI = { MultiBarBottomLeft = 60, MultiBarBottomRight = 48, MultiBarRight = 24, MultiBarLeft = 36 }

local function HookBars()
    if hooked then return end
    hooked = true
    if hooksecurefunc and ActionButtonDown then
        hooksecurefunc("ActionButtonDown", function(id) Pressed(MainSlot(id), true) end)
        hooksecurefunc("ActionButtonUp", function(id) Pressed(MainSlot(id), false) end)
    end
    if hooksecurefunc and MultiActionButtonDown then
        hooksecurefunc("MultiActionButtonDown", function(bar, id)
            local base = MULTI[bar]
            if base then Pressed(base + id, true) end
        end)
        hooksecurefunc("MultiActionButtonUp", function(bar, id)
            local base = MULTI[bar]
            if base then Pressed(base + id, false) end
        end)
    end
    -- ZacUI's own bars: their buttons' clicks (a CLICK binding is a click)
    local AB = ns.Bars
    if AB and AB.ButtonName then
        for abs = 1, 120 do
            local b = _G[AB.ButtonName(abs)]
            if b and b.HookScript then
                -- a click is one press: down at PreClick, up at PostClick (the
                -- icon keeps the press on screen for a moment either way)
                b:HookScript("PreClick", function(btn)
                    local slot = btn.GetAttribute and btn:GetAttribute("action")
                    if type(slot) == "number" then Pressed(slot, true) end
                end)
                b:HookScript("PostClick", function(btn)
                    local slot = btn.GetAttribute and btn:GetAttribute("action")
                    if type(slot) == "number" then Pressed(slot, false) end
                end)
            end
        end
    end
end

function Keys.MirrorPresses(eng, on)
    if on then
        Keys.pressers[eng] = true
        HookBars()
    else
        Keys.pressers[eng] = nil
    end
end
