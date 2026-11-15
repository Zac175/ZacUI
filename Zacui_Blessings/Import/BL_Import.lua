-- BL_Import - PallyPower's own assignments for this paladin brought over
-- once while PallyPower is still loaded (its saved variables only exist
-- in memory then), then the offer to switch it off. Until it is off this
-- part stands down: both would speak for this paladin on the channel.
-- Other people running PallyPower are not affected in any way - ZacUI
-- speaks its channel.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local D = ns.BlessingsData
local BL = ns.Blessings
if not (D and BL) then return end

local Print = ns.Print
local UI = ns.UI

function BL.ImportPallyPower()
    local me = BL.me
    local ch = BL.Char()
    local n = 0
    local a = rawget(_G, "PallyPower_Assignments")
    if type(a) == "table" and type(a[me]) == "table" then
        for slot = 1, D.NUM_CLASSES do
            local b = tonumber(a[me][slot]) or 0
            ch.assign[slot] = (b >= 0 and b <= D.NUM_BLESSINGS) and b or 0
            if ch.assign[slot] > 0 then n = n + 1 end
        end
    end
    local aa = rawget(_G, "PallyPower_AuraAssignments")
    if type(aa) == "table" and tonumber(aa[me]) then
        local v = tonumber(aa[me])
        ch.aura = (v >= 0 and v <= D.NUM_AURAS) and v or 0
    end
    local na = rawget(_G, "PallyPower_NormalAssignments")
    if type(na) == "table" and type(na[me]) == "table" then
        ch.normal = {}
        for slot, t in pairs(na[me]) do
            slot = tonumber(slot)
            if slot and type(t) == "table" then
                ch.normal[slot] = {}
                for tn, b in pairs(t) do
                    b = tonumber(b)
                    if type(tn) == "string" and b and b > 0 and b <= D.SACRIFICE then ch.normal[slot][tn] = b end
                end
            end
        end
    end
    -- the "free assignment" choice, from the profile this character wore
    local db = rawget(_G, "PallyPowerDB")
    if type(db) == "table" and type(db.profiles) == "table" then
        local key = me .. " - " .. ((GetRealmName and GetRealmName()) or "")
        local prof = type(db.profileKeys) == "table" and db.profileKeys[key] or "Default"
        local p = db.profiles[prof] or db.profiles.Default
        if type(p) == "table" and p.freeassign ~= nil then BL.Cfg().freeassign = p.freeassign and true or false end
    end
    ch.importedPP = time and time() or true
    return n
end

local function DisablePallyPower()
    -- the reload FIRST, then the switch (WoW Forever honours a reload only when
    -- it is asked for at the start of the click; UIF_Dialogs' ns.AskReload)
    if ns.RequestReload then ns.RequestReload() else ReloadUI() end
    local f = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
    if f then pcall(f, "PallyPower") end
end
BL.DisablePallyPower = DisablePallyPower

function BL.OfferHandoff()
    if not (UI and UI.Confirm) then return end
    return UI.Confirm({
        title = "Blessings",
        text = "ZacUI does paladin blessings itself now, and still talks to everyone in the group who runs "
            .. "PallyPower. Turn PallyPower off and reload? Until then ZacUI's blessings stay off, so the two "
            .. "do not both answer for you.",
        acceptText = "Turn off + reload",
        onAccept = DisablePallyPower,
    })
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not BL.standDown then return end
    local ch = BL.Char()
    if not ch.importedPP then
        local n = BL.ImportPallyPower()
        if BL.isPaladin then Print("blessings: brought your PallyPower assignments over (" .. n .. " classes).") end
        -- in its turn among the login popups (Core_Popups), never in combat
        if ns.Popups then
            ns.Popups.Want("pallypower", function() return BL.OfferHandoff() end, { order = 45, delay = 4 })
        else
            C_Timer.After(4, BL.OfferHandoff)
        end
    else
        local line = "blessings: PallyPower is still on, so ZacUI's blessings stand down. ZacUI > Combat > Blessings can switch it off."
        if ns.Popups then ns.Popups.Say(line) else Print(line) end
    end
end)
