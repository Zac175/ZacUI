-- CC_Import - brings Clique's bindings into ZacUI, once, while Clique is
-- still loaded (its saved variables only exist in memory then): every
-- character's set, read from CliqueDB3 - not just the one logged in - so
-- the other characters find theirs ready without Clique. Then it offers
-- to switch Clique off; until that happens ZacUI's click casting stands
-- down (two click-casters on one frame fight).
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local CC = ns.ClickCast
if not CC then return end

local Print = ns.Print
local UI = ns.UI

local SETS = { default = true, ooc = true, friend = true, enemy = true, hovercast = true, global = true }
local TYPES = { spell = true, macro = true, target = true, menu = true }

-- one Clique binding -> one ZacUI binding (nil when it cannot be one)
local function Convert(b)
    if type(b) ~= "table" or type(b.key) ~= "string" or b.key == "" then return nil end
    local t = b.type
    if not TYPES[t] then return nil end
    local out = { key = b.key:upper(), type = t, sets = {} }
    if t == "spell" then
        if type(b.spell) ~= "string" or b.spell == "" then return nil end
        out.spell = b.spell
        if type(b.spellSubName) == "string" and b.spellSubName ~= "" then out.rank = b.spellSubName end
    elseif t == "macro" then
        if type(b.macrotext) ~= "string" or b.macrotext == "" then return nil end
        out.macrotext = b.macrotext
    end
    if type(b.sets) == "table" then
        for k, v in pairs(b.sets) do if v and SETS[k] then out.sets[k] = true end end
    end
    if not next(out.sets) then out.sets.default = true end
    return out
end

-- every character's bindings from CliqueDB3; returns how many sets
function CC.ImportClique(overwrite)
    local db = rawget(_G, "CliqueDB3")
    local c = CC.Cfg()
    if type(db) ~= "table" or not c then return 0 end
    local profiles = type(db.profiles) == "table" and db.profiles or {}
    local keys = type(db.profileKeys) == "table" and db.profileKeys or {}
    local n = 0
    local function Take(charKey, profileName)
        local p = profiles[profileName]
        if type(p) ~= "table" or type(p.bindings) ~= "table" then return end
        if c.profiles[charKey] and not overwrite then return end
        local list = {}
        for _, b in ipairs(p.bindings) do
            local x = Convert(b)
            if x then list[#list + 1] = x end
        end
        c.profiles[charKey] = { bindings = list, from = "Clique" }
        n = n + 1
    end
    for charKey, profileName in pairs(keys) do
        if type(charKey) == "string" and type(profileName) == "string" then Take(charKey, profileName) end
    end
    -- profiles no character points at (a shared one) stay reachable by name
    for name in pairs(profiles) do
        if type(name) == "string" and not c.profiles[name] then Take(name, name) end
    end
    c.importedClique = time and time() or true
    return n
end

local function DisableClique()
    -- the reload FIRST, then the switch (WoW Forever honours a reload only when
    -- it is asked for at the start of the click; UIF_Dialogs' ns.AskReload)
    if ns.RequestReload then ns.RequestReload() else ReloadUI() end
    local f = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
    if f then pcall(f, "Clique") end
end
CC.DisableClique = DisableClique

function CC.OfferCliqueHandoff(count)
    if not (UI and UI.Confirm) then return end
    return UI.Confirm({
        title = "Click casting",
        text = (count and count > 0 and ("Brought " .. count .. " character binding set(s) over from Clique.\n\n") or "")
            .. "ZacUI does click casting itself now. Turn Clique off and reload? Until then ZacUI's click "
            .. "casting stays off, so the two do not fight over your frames.",
        acceptText = "Turn off + reload",
        onAccept = DisableClique,
    })
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not CC.standDown then return end
    local c = CC.Cfg()
    if not c then return end
    if not c.importedClique then
        local n = CC.ImportClique(false)
        Print("click casting: brought " .. n .. " binding set(s) over from Clique.")
        -- in its turn among the login popups (Core_Popups), never in combat
        if ns.Popups then
            ns.Popups.Want("clique", function() return CC.OfferCliqueHandoff(n) end, { order = 45, delay = 3 })
        else
            C_Timer.After(3, function() CC.OfferCliqueHandoff(n) end)
        end
    else
        local line = "click casting: Clique is still on, so ZacUI's click casting stands down. ZacUI > Combat > Click casting can switch Clique off."
        if ns.Popups then ns.Popups.Say(line) else Print(line) end
    end
end)
