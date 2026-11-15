-- SCT_Alerts - lines that warn you: low health, low mana, an ability
-- coming up, and your own "this aura just went up" alerts.
-- Part of ZacUI (Zacui_SBT). Written for ZacUI.
--
-- Built-in alerts are a small catalogue; sct.alerts stores only what you
-- changed. Your own alerts are a list in sct.auraAlerts:
--   { name = "Improved Hamstring", unit = "target" | "player",
--     text = "Improved Hamstring", on = true, size = 26, r, g, b,
--     sticky = true, sound = "..." }
local ns = _G.ZacUI
if not ns then return end
local S = ns.SBT
if not S then return end

local A = {}
S.Alerts = A

local UnitGUID = UnitGUID
local tonumber, type = tonumber, type
local secret = _G.issecretvalue

local ALERTS = {
    { key = "lowHealth", label = "Low health",       pct = 40, fmt = "Low Health! (%a)", c = { 1, 0.1, 0.1 },   size = 18 },
    { key = "lowMana",   label = "Low mana",         pct = 35, fmt = "Low Mana! (%a)",   c = { 0.25, 0.45, 1 }, size = 18 },
    { key = "lowPet",    label = "Pet low health",   pct = 40, fmt = "Pet Low Health! (%a)", c = { 1, 0.4, 0.1 }, size = 18, off = true },
    { key = "execute",   label = "Execute (target under 20%)", class = "WARRIOR", fmt = "Execute!",   c = { 1, 0.45, 0 }, size = 18, off = true },
    { key = "overpower", label = "Overpower (target dodged)",  class = "WARRIOR", fmt = "Overpower!", c = { 1, 0.45, 0 }, size = 18, off = true },
    { key = "revenge",   label = "Revenge (you blocked, dodged or parried)", class = "WARRIOR", fmt = "Revenge!", c = { 1, 0.45, 0 }, size = 18, off = true },
}
local BY_KEY = {}
for _, a in ipairs(ALERTS) do BY_KEY[a.key] = a end
S.ALERTS, S.ALERT_BY_KEY = ALERTS, BY_KEY

-- ============================================================
-- SETTINGS
-- ============================================================
local function Own(key)
    local t = S.Cfg().alerts[key]
    return type(t) == "table" and t or nil
end

function S.AlertOn(key)
    local def, own = BY_KEY[key], Own(key)
    if not def then return false end
    if own and own.off ~= nil then return not own.off end
    return not def.off
end

function S.AlertValue(key, field)
    local def, own = BY_KEY[key], Own(key)
    if own and own[field] ~= nil then return own[field] end
    if field == "area" then return "notification" end
    if field == "r" then return def.c[1] elseif field == "g" then return def.c[2] elseif field == "b" then return def.c[3] end
    return def and def[field]
end

function S.SetAlert(key, field, value, g, b)
    local def = BY_KEY[key]
    if not def then return end
    local all = S.Cfg().alerts
    local own = all[key]
    if type(own) ~= "table" then
        own = {}
        all[key] = own
    end
    if field == "color" then
        own.r, own.g, own.b = value, g, b
    elseif field == "off" then
        if (value and true or false) == (def.off and true or false) then own.off = nil
        else own.off = value and true or false end
    else
        own[field] = value
    end
    if next(own) == nil then all[key] = nil end
end

-- One alert as a line (area, text, look); the preview draws through it.
local function Line(key, amount)
    local def = BY_KEY[key]
    if not def then return nil end
    local text = def.fmt:gsub("%%a", amount and S.Digits(amount) or "")
    local area = S.AlertValue(key, "area")
    if not S.Area(area) then area = "notification" end
    return area, text, {
        r = S.AlertValue(key, "r"), g = S.AlertValue(key, "g"), b = S.AlertValue(key, "b"),
        size = tonumber(S.AlertValue(key, "size")), sticky = true,
        sound = S.AlertValue(key, "sound"), soundKey = key,
    }
end
A.Line = Line

-- Your own aura alert as a line.
function A.AuraLine(al)
    local area = al.area and S.Area(al.area) and al.area or "notification"
    return area, (al.text and al.text ~= "") and al.text or al.name, {
        r = al.r or 1, g = al.g or 1, b = al.b or 0,
        size = tonumber(al.size), sticky = al.sticky ~= false,
        icon = S.Icon and S.Icon(nil, al.name) or nil, sound = al.sound,
    }
end

local function Fire(key, amount, force)
    if not force and not S.AlertOn(key) then return end
    local area, text, o = Line(key, amount)
    if area then S.Display(area, text, o) end
end
A.Fire = Fire

-- a sample shows even while the alert is off
function S.TestAlert(key)
    if BY_KEY[key] then Fire(key, 1234, true) end
end

-- ============================================================
-- YOUR OWN AURA ALERTS
-- ============================================================
function S.AuraAlerts()
    return S.Cfg().auraAlerts
end

function S.AddAuraAlert(name)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then return false, "Type the name of the buff or debuff." end
    local list = S.Cfg().auraAlerts
    list[#list + 1] = { name = name, text = name, unit = "target", on = true, sticky = true,
        size = 20, r = 1, g = 1, b = 0 }
    return true
end

function S.RemoveAuraAlert(i)
    table.remove(S.Cfg().auraAlerts, i)
end

local function AuraAlert(spellName, toMe, dGUID)
    local list = S.Cfg().auraAlerts
    if #list == 0 then return end
    local target
    for _, al in ipairs(list) do
        if al.on ~= false and al.name == spellName then
            local hit = false
            if al.unit == "player" then
                hit = toMe
            else
                target = target or UnitGUID("target")
                hit = dGUID ~= nil and dGUID == target
            end
            if hit then
                S.Display(A.AuraLine(al))
            end
        end
    end
end

-- ============================================================
-- FROM THE COMBAT LOG (Classic Era) - SCT_Events hands every event
-- here first (auras on your target need not involve you)
-- ============================================================
local myClass
local function Class()
    if not myClass then myClass = select(2, UnitClass("player")) end
    return myClass
end

function A.OnCombatLog(sub, fromMe, toMe, sGUID, dGUID, dName, a1, a2, a3, a4, a5)
    if sub == "SPELL_AURA_APPLIED" then
        AuraAlert(a2, toMe, dGUID)
        return
    end
    if Class() ~= "WARRIOR" or not (fromMe or toMe) then return end
    if fromMe then
        local miss = (sub == "SWING_MISSED" and a1) or ((sub == "SPELL_MISSED") and a4)
        if miss == "DODGE" then Fire("overpower") end
    elseif toMe then
        local miss = (sub == "SWING_MISSED" and a1) or ((sub == "SPELL_MISSED") and a4)
        if miss == "DODGE" or miss == "PARRY" or miss == "BLOCK" then
            Fire("revenge")
        elseif sub == "SWING_DAMAGE" and (a5 or 0) > 0 then
            -- a partly blocked hit counts for Revenge too
            Fire("revenge")
        end
    end
end

-- ============================================================
-- HEALTH AND MANA
-- ============================================================
local armed = { lowHealth = true, lowMana = true, lowPet = true }
local executeFor

local function Pct(unit, power)
    local cur, max
    if power then
        cur, max = UnitPower(unit, 0), UnitPowerMax(unit, 0)
    else
        cur, max = UnitHealth(unit), UnitHealthMax(unit)
    end
    if secret and (secret(cur) or secret(max)) then return nil end
    cur, max = tonumber(cur), tonumber(max)
    if not cur or not max or max <= 0 then return nil end
    return cur / max * 100, cur
end

local function Check(key, unit, power)
    if not S.AlertOn(key) then return end
    if UnitIsDeadOrGhost(unit) then armed[key] = true return end
    local pct, cur = Pct(unit, power)
    if not pct then return end
    local limit = tonumber(S.AlertValue(key, "pct")) or 40
    if pct < limit then
        if armed[key] then
            armed[key] = false
            Fire(key, cur)
        end
    elseif pct > limit + 5 then
        armed[key] = true
    end
end

local function CheckExecute()
    if Class() ~= "WARRIOR" or not S.AlertOn("execute") then return end
    if not (UnitExists("target") and UnitCanAttack("player", "target")) or UnitIsDeadOrGhost("target") then return end
    local pct = Pct("target")
    if not pct then return end
    local g = UnitGUID("target")
    if pct < 20 then
        if executeFor ~= g then
            executeFor = g
            Fire("execute")
        end
    elseif executeFor == g and pct > 25 then
        executeFor = nil
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, unit, kind)
    if event == "UNIT_HEALTH" or event == "UNIT_HEALTH_FREQUENT" then
        if unit == "player" then Check("lowHealth", "player")
        elseif unit == "pet" then Check("lowPet", "pet")
        elseif unit == "target" then CheckExecute() end
    elseif event == "UNIT_POWER_UPDATE" then
        if unit == "player" and kind == "MANA" and UnitPowerType("player") == 0 then
            Check("lowMana", "player", true)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        CheckExecute()
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        pcall(self.RegisterUnitEvent, self, "UNIT_HEALTH", "player", "pet")
        pcall(self.RegisterUnitEvent, self, "UNIT_POWER_UPDATE", "player")
        if Class() == "WARRIOR" then
            -- the target's health only matters for Execute
            local f = CreateFrame("Frame")
            pcall(f.RegisterUnitEvent, f, "UNIT_HEALTH", "target")
            f:RegisterEvent("PLAYER_TARGET_CHANGED")
            f:SetScript("OnEvent", function() CheckExecute() end)
        end
    end
end)
