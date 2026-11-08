-- Core_DevSecrets - the developer's switch for the restricted environment:
-- /zui dev secrets on flips the client's own "addon restrictions forced"
-- settings, so the secret-value paths (hidden health, names, cooldowns...)
-- can be tested anywhere - in Elwynn, on a target dummy - instead of
-- waiting for an encounter. Off again on logout, by itself.
-- Part of ZacUI; load order is set by the TOC (after Core_CVar).
--
-- THE SIX SETTINGS (console variables, where this client has them):
--   addonChallengeModeRestrictionsForced   addonChatRestrictionsForced
--   addonCombatRestrictionsForced          addonEncounterRestrictionsForced
--   addonMapRestrictionsForced             addonPvPMatchRestrictionsForced
-- Each is looked up first (C_CVar.GetCVarInfo / GetCVarDefault); the
-- switch prints which ones the client has and sets only those, never
-- erroring on one that is missing. A client with none of them (Classic
-- Era, TBC) says so and sets nothing.
--
-- THROUGH THE CVAR HELPER: ns.CVar.Hold while on, ns.CVar.Release when off
-- (the value from before comes back, the record forgets the hold). Where
-- the helper is missing, SetCVar with the old value kept here. The owner
-- "dev" reads as off at every login, so a hold left behind by a crash is
-- put back by the helper's login pass.
--
-- ON SCREEN while on: a "DEV: secrets forced" badge under the game-version
-- note, clickable to switch off, with a mover. The Game versions page
-- carries a Developer card for it while developer tools are shown
-- (/zui dev tools on; ZacUIDB.dev.tools, account-wide, outside profiles).

local ADDON_NAME, ns = ...

local Print = ns.Print

local DS = {}
ns.DevSecrets = DS

DS.CVARS = {
    "addonChallengeModeRestrictionsForced", "addonChatRestrictionsForced", "addonCombatRestrictionsForced",
    "addonEncounterRestrictionsForced", "addonMapRestrictionsForced", "addonPvPMatchRestrictionsForced",
}
local OWNER = "dev"
local MOVER = "devsecrets"
DS.BADGE_TEXT = "DEV: secrets forced"

local on = false
local before = {}        -- [name] = the value from before (the fallback path)

-- ============================================================
-- WHICH ONES THIS CLIENT HAS
-- ============================================================
function DS.Has(name)
    if C_CVar and C_CVar.GetCVarInfo then
        local ok, v = pcall(C_CVar.GetCVarInfo, name)
        if ok and v ~= nil then return true end
    end
    if C_CVar and C_CVar.GetCVarDefault then
        local ok, v = pcall(C_CVar.GetCVarDefault, name)
        if ok and v ~= nil then return true end
    end
    return false
end

-- { names the client has }, { names it lacks }
function DS.Survey()
    local have, lack = {}, {}
    for _, n in ipairs(DS.CVARS) do
        if DS.Has(n) then have[#have + 1] = n else lack[#lack + 1] = n end
    end
    return have, lack
end

function DS.Value(name)
    if ns.CVar and ns.CVar.Get then return ns.CVar.Get(name) end
    local f = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    if not f then return nil end
    local ok, v = pcall(f, name)
    if ok and v ~= nil then return tostring(v) end
    return nil
end

local function Write(name, value)
    local f = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
    if not f then return false end
    local ok = pcall(f, name, value)
    return ok
end

-- ============================================================
-- THE SWITCH
-- ============================================================
function DS.On() return on end

-- developer tools shown on the settings pages (the Developer card)
function DS.ToolsShown()
    local dev = type(ZacUIDB) == "table" and ZacUIDB.dev
    return type(dev) == "table" and dev.tools == true
end
function DS.SetTools(v)
    if type(ZacUIDB) ~= "table" then return false end
    if type(ZacUIDB.dev) ~= "table" then ZacUIDB.dev = {} end
    ZacUIDB.dev.tools = v and true or nil
    if next(ZacUIDB.dev) == nil then ZacUIDB.dev = nil end
    if ns.RefreshConfig then pcall(ns.RefreshConfig) end
    return true
end

local badge
local function BadgeDefaultSpot(f)
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, -54)
end
function DS.BuildBadge(parent, sample)
    local UI = ns.UI
    local f = CreateFrame("Button", (not sample) and "ZacUIDevSecretsBadge" or nil, parent or UIParent)
    f:SetSize(170, 20)
    if UI then
        UI.Fill(f, "ui", "windowBg", 0.85)
        UI.Border(f, "text", "red")
        f._zPaint = function(self) UI.PaintBox(self) end
    end
    local fs = UI and UI.Font(f, UI.F and UI.F.SMALL or 11, { cat = "text", key = "red" })
        or f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetText(DS.BADGE_TEXT)
    f._zText = fs
    f:SetWidth(math.max(120, math.ceil(fs:GetStringWidth() or 120) + 18))
    if f._zPaint then f:_zPaint() end
    if not sample then
        f:SetFrameStrata("DIALOG")
        f:SetScript("OnClick", function() DS.Set(false) end)
        if UI and UI.Tooltip then
            UI.Tooltip(f, "Developer: addon restrictions forced",
                "The client's own \"addon restrictions forced\" settings are on, so values the game hides from "
                .. "addons in a fight are hidden here too. Click to switch them off (also /zui dev secrets off). "
                .. "Off by itself on logout.")
        end
    else
        f:EnableMouse(false)
    end
    return f
end
local function PaintBadge()
    if on then
        if not badge then
            badge = DS.BuildBadge(UIParent, false)
            BadgeDefaultSpot(badge)
            if ns.ApplyMover then ns.ApplyMover(MOVER) end
        end
        badge:Show()
    elseif badge then
        badge:Hide()
    end
end
DS.Badge = function() return badge end

-- on / off; prints what it did unless quiet. Returns the names it set.
function DS.Set(want, quiet)
    want = want and true or false
    local have, lack = DS.Survey()
    if want and not on then
        if #have == 0 then
            if not quiet then
                Print("dev secrets: this client has none of the addon restriction settings ("
                    .. ns.FlavorName(ns.RealFlavor and ns.RealFlavor() or nil) .. "); nothing set.")
            end
            return {}
        end
        for _, n in ipairs(have) do
            -- the value from before is kept here too: the way back when the
            -- helper has nowhere to write its hold (no saved table yet)
            before[n] = DS.Value(n)
            if not (ns.CVar and ns.CVar.Hold and ns.CVar.Hold(n, "1", OWNER)) then
                Write(n, "1")
            end
        end
        on = true
        PaintBadge()
        if not quiet then
            Print("dev secrets ON - forced: " .. table.concat(have, ", ") .. "."
                .. (#lack > 0 and (" Not on this client: " .. table.concat(lack, ", ") .. ".") or "")
                .. " Off by itself on logout; /zui dev secrets off before.")
        end
        if ns.RefreshConfig then pcall(ns.RefreshConfig) end
        return have
    elseif not want and on then
        for _, n in ipairs(have) do
            local back = ns.CVar and ns.CVar.Release and ns.CVar.Release(n, OWNER)
            if not back and DS.Value(n) == "1" then Write(n, before[n] or "0") end
            before[n] = nil
        end
        on = false
        PaintBadge()
        if not quiet then Print("dev secrets off - the restriction settings are back as they were.") end
        if ns.RefreshConfig then pcall(ns.RefreshConfig) end
        return have
    end
    if not quiet then
        Print("dev secrets already " .. (on and "on" or "off") .. ".")
    end
    return {}
end

function DS.Status()
    local have, lack = DS.Survey()
    Print("dev secrets: " .. (on and "ON" or "off") .. ".")
    if #have > 0 then
        local parts = {}
        for _, n in ipairs(have) do parts[#parts + 1] = n .. "=" .. tostring(DS.Value(n)) end
        Print("  this client has: " .. table.concat(parts, ", "))
    else
        Print("  this client has none of the six restriction settings.")
    end
    if #lack > 0 then Print("  not on this client: " .. table.concat(lack, ", ")) end
end

-- ============================================================
-- /zui dev
-- ============================================================
ns.SlashCommands = ns.SlashCommands or {}
ns.SlashCommands.dev = function(rest)
    rest = (rest or ""):lower()
    local what, arg = rest:match("^(%S+)%s*(%S*)")
    if what == "secrets" or what == "secret" or what == "restrict" then
        if arg == "on" then DS.Set(true)
        elseif arg == "off" then DS.Set(false)
        elseif arg == "" or arg == "status" then DS.Status()
        else Print("/zui dev secrets on|off|status") end
    elseif what == "tools" then
        if arg == "on" then DS.SetTools(true) Print("developer tools shown (General > Game versions).")
        elseif arg == "off" then DS.SetTools(false) Print("developer tools hidden.")
        else Print("developer tools are " .. (DS.ToolsShown() and "shown" or "hidden") .. ". /zui dev tools on|off") end
    else
        Print("/zui dev secrets on|off|status - force the client's addon restrictions (secret values anywhere)")
        Print("/zui dev tools on|off - show the Developer card on General > Game versions")
        DS.Status()
    end
end

-- ============================================================
-- LOGIN / LOGOUT
-- ============================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        -- the owner reads as off whenever the switch is off, so the CVar
        -- helper's login pass puts back a hold a crash left behind
        if ns.CVar and ns.CVar.OwnerCheck then ns.CVar.OwnerCheck(OWNER, function() return not on end) end
        if ns.RegisterMover then
            ns.RegisterMover(MOVER, "Developer: secrets badge", function() return badge end, "TOP", 0, -54, nil, {
                reset = function() if badge then BadgeDefaultSpot(badge) end end, own = true })
        end
    elseif event == "PLAYER_LOGOUT" then
        if on then DS.Set(false, true) end
    end
end)

-- ============================================================
-- THE DEVELOPER CARD (General > Game versions, while tools are shown)
-- ============================================================
function ns.DevCard(L)
    if not DS.ToolsShown() then return end
    local UI = ns.UI
    L:Card("Developer")
    local have, lack = DS.Survey()
    local cb = UI.Checkbox(L.current, "Force the game's addon restrictions now (secret values anywhere)", on, function(v)
        DS.Set(v)
    end, { tooltip = "Sets the client's own \"addon restrictions forced\" settings to 1 for this session, so "
        .. "everything the game hides from addons in a fight is hidden everywhere: the way to test those paths "
        .. "on a dummy. Off by itself on logout. Same as /zui dev secrets on|off." })
    L:Row(cb, 17)
    if #have == 0 then
        L:Desc("This client has none of the six restriction settings, so the switch sets nothing here.")
    else
        local parts = {}
        for _, n in ipairs(have) do parts[#parts + 1] = n .. " = " .. tostring(DS.Value(n) or "?") end
        L:Desc("This client has: " .. table.concat(parts, ", ") .. ".")
    end
    if #lack > 0 then L:Desc("Not on this client: " .. table.concat(lack, ", ") .. ".") end
    -- the badge, as it looks on screen
    local row = UI.Holder(L.current)
    row:SetSize(300, 24)
    local sample = DS.BuildBadge(row, true)
    sample:SetPoint("LEFT", row, "LEFT", 0, 0)
    local hint = UI.Font(row, UI.F.SMALL, { cat = "text", key = "gray", text = "the badge while it is on" })
    hint:SetPoint("LEFT", sample, "RIGHT", 8, 0)
    L:Row(row, 28)
    local hide = UI.Button(L.current, "Hide developer tools", { width = 160,
        tooltip = "Takes this card off the page. /zui dev tools on brings it back.",
        onClick = function() DS.SetTools(false) end })
    L:Row(hide, (UI.M.BUTTON_H or 20) + 6)
    L:EndCard()
end
