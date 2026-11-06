-- Auras_Core - the switch in front of ZacUI's aura engine (Zacui_Auras).
-- Part of ZacUI; load order is set by the TOC.
--
-- The engine is its own part: an addon in the list, off until it is
-- switched on. This file is what ZacUI knows about it before (or without)
-- it loading: whether it is wanted, whether it is there, turning it on or
-- off (and WeakAuras the other way, since the two share the WeakAuras
-- global and must never run together), and the Auras page shown while the
-- engine is off. Once the engine loads, its own page (AE_Page) takes over.
--
-- Nothing here reads or writes aura data. The engine keeps its own under
-- ZacUIAurasSaved; WeakAuras' saved variables are never touched.
local ADDON_NAME, ns = ...

local Print = ns.Print

local ENGINE   = "Zacui_Auras"
local UPSTREAM = "WeakAuras"

local Auras = {}
ns.Auras = Auras

-- ============================================================
-- THE ADDON LIST (C_AddOns where it exists, the old globals where not)
-- ============================================================
local function API(name)
    return (C_AddOns and C_AddOns[name]) or _G[name]
end

local function Loaded(name)
    local fn = API("IsAddOnLoaded")
    if not fn then return false end
    local ok, res = pcall(fn, name)
    return ok and res and true or false
end

local function Installed(name)
    local fn = API("GetAddOnInfo")
    if not fn then return false end
    local ok, title = pcall(fn, name)
    return ok and title ~= nil
end

-- enabled for this character, as a plain true/false (nil when unknown)
local function IsEnabled(name)
    local fn = API("GetAddOnEnableState")
    if not fn then return nil end
    local who = UnitName and UnitName("player")
    local ok, state = pcall(fn, name, who)
    if not ok then ok, state = pcall(fn, who, name) end
    if not ok or state == nil then return nil end
    if Enum and Enum.AddOnEnableState then return state ~= Enum.AddOnEnableState.None end
    return state ~= 0
end

local function SetAddOnEnabled(name, on)
    local fn = API(on and "EnableAddOn" or "DisableAddOn")
    if not fn then return false end
    return pcall(fn, name) and true or false
end

-- ZacUIDB.auraEngine.enabled: absent means off
local function DB()
    if type(ZacUIDB) ~= "table" then return { enabled = false } end
    ZacUIDB.auraEngine = ZacUIDB.auraEngine or {}
    local d = ZacUIDB.auraEngine
    if d.enabled == nil then d.enabled = false end
    return d
end
Auras.DB = DB

-- the WeakAuras global, but only when it is ZacUI's engine answering
function Auras.Engine()
    local WA = _G.WeakAuras
    if type(WA) == "table" and WA.IsZacUIEngine then return WA end
    return nil
end

function Auras.Status()
    local d = DB()
    return {
        want        = d.enabled and true or false,
        built       = Installed(ENGINE),
        engineOn    = IsEnabled(ENGINE),
        engineUp    = Auras.Engine() ~= nil,
        upstreamHas = Installed(UPSTREAM),
        upstreamOn  = IsEnabled(UPSTREAM),
        upstreamUp  = Loaded(UPSTREAM),
    }
end

-- one switch: ours on and WeakAuras off, or the other way; then a reload
function Auras.SetEnabled(on)
    on = on and true or false
    if on and not Installed(ENGINE) then
        Print("The aura engine (Zacui_Auras) is not in your AddOns folder.")
        return
    end
    DB().enabled = on
    if not SetAddOnEnabled(ENGINE, on) then
        Print("Could not switch Zacui_Auras - set it in the addon list (Esc > AddOns).")
        return
    end
    local other = Installed(UPSTREAM) and SetAddOnEnabled(UPSTREAM, not on)
    if on then
        Print("Aura engine on" .. (other and " and WeakAuras off" or "") .. ". /reload to apply.")
    else
        Print("Aura engine off" .. (other and " and WeakAuras back on" or "") .. ". /reload to apply.")
    end
end

function Auras.Toggle() Auras.SetEnabled(not DB().enabled) end

-- ============================================================
-- AT LOGIN: SAY SO WHEN THE SWITCH AND THE ADDON LIST DISAGREE
-- ============================================================
local function Reconcile()
    local s = Auras.Status()
    if not s.built then return end
    if s.engineUp and s.upstreamUp then
        Print("|cffff6666Both aura engines are loaded.|r ZacUI's and WeakAuras share one global; "
            .. "set the switch on the Auras page (or disable one in the addon list), then /reload.")
    elseif s.want and not s.engineUp then
        Print("The aura engine is set to on but Zacui_Auras did not load"
            .. (s.engineOn == false and " - it is disabled in the addon list." or ".")
            .. " Set the switch on the Auras page again, then /reload.")
    elseif not s.want and s.engineUp then
        -- turned on in the addon list by hand: that is a yes
        DB().enabled = true
    end
end

-- ============================================================
-- A STRING FROM ANOTHER IMPORT BOX
-- ============================================================
-- The profile importer recognises aura strings and hands them here; they
-- wait in the Auras page's import box for the player to look at.
function Auras.ImportString(text)
    if type(text) ~= "string" or text == "" then return false, "no string" end
    local E = ns.AuraEngine
    if not (E and E.Import and Auras.Engine()) then
        return false, "the aura engine is off - switch it on from the Auras page, reload, then paste it there"
    end
    E.pendingImport = text
    if ns.OpenConfig then pcall(ns.OpenConfig, "auras") end
    return true
end

-- ============================================================
-- THE PAGE WHILE THE ENGINE IS OFF
-- ============================================================
-- Registered at login (the config pages load after this file), and only
-- when the engine is not running - its own page is the Auras page then.
local function OffPage(L)
    local UI = ns.UI
    L:Header("Aura engine", "Auras in the WeakAuras format, run by ZacUI's own engine.")
    local s = Auras.Status()
    L:Card("Switch")
    if not s.built then
        L:Desc("Zacui_Auras is not in your AddOns folder.")
    else
        local cb = UI.Checkbox(L.current, "Use ZacUI's aura engine", s.want, function(v) Auras.SetEnabled(v) end)
        L:Row(cb, 17)
        L:Desc("Runs your auras and imports WeakAuras strings. "
            .. (s.upstreamHas and "WeakAuras itself is switched off while it is on, and back on when it is off. " or "")
            .. "Takes effect on /reload.")
    end
    L:EndCard()
end

local gate = CreateFrame("Frame")
gate:RegisterEvent("PLAYER_LOGIN")
gate:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if not Auras.Engine() and ns.RegisterPage and ns.UI then ns.RegisterPage("Auras", OffPage) end
    pcall(Reconcile)
end)
