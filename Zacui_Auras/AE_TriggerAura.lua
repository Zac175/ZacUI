-- AE_TriggerAura - the buff / debuff trigger ("aura2" in the format).
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- One shared scan per unit, done at most once a frame for units whose
-- auras changed (UNIT_AURA fires many times a second in a raid; it only
-- marks the unit), then every trigger watching that unit re-reads the
-- scan. A trigger names (the format's keys):
--   unit            player, target, softenemy, softfriend, pet, group,
--                   party, raid, nameplate, boss, member (+ specificUnit),
--                   multi (tracked from the combat log)
--   debuffType      HELPFUL / HARMFUL / BOTH
--   useName + auranames            names (ids stand for their names)
--   useExactSpellId + auraspellids exact spell ids
--   ownOnly         true: mine (or my pet's), false: others', nil: anyone's
--   matchesShowOn   showOnActive, showOnMissing, showOnMatches, showAlways
--                   (single units; group units go by their counts)
--   showClones      a state per match; with combinePerUnit (group units)
--                   a state per unit, by perUnitMode
--   useStacks, useRem, useTotal, use_stealable, use_isBossDebuff,
--   use_castByPlayer, use_debuffClass, fetchTooltip + use_tooltip /
--   use_tooltipValue, useNamePattern, useIgnoreName,
--   useIgnoreExactSpellId                       narrow each match
--   useGroup_count, useMatch_count, useMatchPerUnit_count, ignoreSelf,
--   ignoreDead, ignoreDisconnected, ignoreInvisible, useGroupRole,
--   useRaidRole, useClass, useHostility, useUnitName, useNpcId,
--   use_includePets, unitExists, combineMode, fetchRole, fetchRaidMark,
--   useAffected                                 the units and counts
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local A = {}
E.TriggerTypes.aura2 = A
local Tr = E.Triggers

local GetTime, UnitAura, UnitExists, UnitGUID = GetTime, UnitAura, UnitExists, UnitGUID

local function Pr() return E.Protos end

-- ============================================================
-- SMALL HELPERS
-- ============================================================
local function Compare(a, op, b)
    a, b = tonumber(a), tonumber(b)
    if not a or not b then return true end
    if op == "<" then return a < b elseif op == "<=" then return a <= b
    elseif op == ">" then return a > b elseif op == ">=" then return a >= b
    elseif op == "~=" or op == "!=" then return a ~= b end
    return a == b
end

local function StrOp(have, op, want)
    if have == nil or want == nil then return false end
    have, want = tostring(have), tostring(want)
    if op == "find('%s')" then return have:find(want, 1, true) ~= nil end
    if op == "match('%s')" then
        local ok, res = pcall(string.match, have, want)
        return ok and res ~= nil
    end
    return have == want
end

-- "12", "50%", "1/2": a whole count or a share of the units
local function ParseCount(s)
    if type(s) == "number" then return s, "whole" end
    if type(s) ~= "string" then return nil end
    if s:sub(-1) == "%" then
        local p = tonumber(s:sub(1, -2))
        return p and p / 100, "fraction"
    end
    local a, b = s:match("(%d+)%s*/%s*(%d+)")
    a, b = tonumber(a), tonumber(b)
    if a and b then
        if b == 0 then return nil end
        return a / b, "fraction"
    end
    local n = tonumber(s)
    return n, n and "whole" or nil
end

local function IsGroupUnit(u) return u == "group" or u == "party" or u == "raid" end
local function IsMultiUnit(tr)
    local u = tr.unit
    return IsGroupUnit(u) or u == "boss" or u == "nameplate" or u == "arena" or u == "multi"
end
A.IsMultiUnit = IsMultiUnit

local function DebuffClass(dispel)
    if dispel == nil then return "none" end
    if dispel == "" then return "enrage" end
    return tostring(dispel):lower()
end

local CLASS_ICONS = { magic = 135894, curse = 136139, disease = 136066, poison = 136068 }

-- tooltip text and the first four numbers in it
local tip
local function TooltipOf(unit, index, filter)
    if not CreateFrame then return nil end
    if not tip then
        tip = CreateFrame("GameTooltip", "ZacUIAurasAuraTip", nil, "GameTooltipTemplate")
        if tip and tip.SetOwner then tip:SetOwner(UIParent, "ANCHOR_NONE") end
    end
    if not (tip and tip.SetUnitAura) then return nil end
    tip:ClearLines()
    tip:SetUnitAura(unit, index, filter)
    local fs = _G["ZacUIAurasAuraTipTextLeft2"]
    local text = fs and fs.GetText and fs:GetText() or ""
    local nums = {}
    for n in text:gsub("(%d),(%d)", "%1%2"):gmatch("%d+%.?%d*") do
        nums[#nums + 1] = tonumber(n)
        if #nums >= 4 then break end
    end
    return text, nums[1], nums[2], nums[3], nums[4]
end

-- ============================================================
-- THE SCAN
-- ============================================================
local scans = {}          -- unit -> { HELPFUL = { aura... }, HARMFUL = {...}, guid = }
local dirty = {}          -- unit -> true
local plates = {}         -- nameplate units on screen

local function Scan(unit)
    local s = { HELPFUL = {}, HARMFUL = {} }
    if UnitExists(unit) and UnitAura then
        s.guid = UnitGUID(unit)
        for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
            local list = s[filter]
            for i = 1, 40 do
                local name, icon, count, dispel, duration, expiration, source, stealable, _, spellId, _, isBoss, castByPlayer, _, modRate = UnitAura(unit, i, filter)
                if not name then break end
                list[#list + 1] = { name = name, icon = icon, stacks = count, debuffClass = DebuffClass(dispel),
                    duration = duration, expirationTime = expiration, unitCaster = source, isStealable = stealable,
                    isBossDebuff = isBoss, isCastByPlayer = castByPlayer, modRate = modRate or 1,
                    spellId = spellId, index = i, filter = filter, unit = unit }
            end
        end
    end
    scans[unit] = s
    return s
end

local function Get(unit)
    return scans[unit] or Scan(unit)
end

-- ============================================================
-- UNITS A TRIGGER WATCHES
-- ============================================================
local function GroupUnits(kind, pets)
    local out = {}
    local function Add(u, pet)
        if pets ~= "PetsOnly" then out[#out + 1] = u end
        if pets and pet then out[#out + 1] = pet end
    end
    if kind == "raid" or (kind == "group" and IsInRaid and IsInRaid()) then
        for i = 1, GetNumGroupMembers() do Add("raid" .. i, "raidpet" .. i) end
        if #out == 0 and kind == "group" then Add("player", "pet") end
    else
        Add("player", "pet")
        local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or math.max(0, GetNumGroupMembers() - 1)
        for i = 1, n do Add("party" .. i, "partypet" .. i) end
    end
    return out
end

local function Units(tr)
    local u = tr.unit or "player"
    local pets = tr.use_includePets and tr.includePets or nil
    if u == "group" then return GroupUnits("group", pets), true end
    if u == "party" then return GroupUnits("party", pets), true end
    if u == "raid" then return GroupUnits("raid", pets), true end
    if u == "nameplate" then
        local out = {}
        for unit in pairs(plates) do out[#out + 1] = unit end
        table.sort(out)
        return out, true
    end
    if u == "boss" then return { "boss1", "boss2", "boss3", "boss4", "boss5" }, true end
    if u == "multi" then return {}, true end
    if u == "member" then return { tr.specificUnit or "" }, false end
    return { u }, false
end

-- ============================================================
-- MATCHING
-- ============================================================
local function NameSet(ctx)
    if ctx.names ~= nil then return ctx.names, ctx.ids end
    local tr = ctx.trigger
    local names, ids = false, false
    if tr.useName and type(tr.auranames) == "table" then
        names = {}
        for _, n in ipairs(tr.auranames) do
            if type(n) == "string" and n ~= "" then
                local num = tonumber(n)
                if num then
                    names[num] = true
                    -- a spell id stands for its name too
                    local nm = GetSpellInfo and GetSpellInfo(num)
                    if nm then names[nm] = true end
                else
                    names[n] = true
                end
            elseif type(n) == "number" then
                names[n] = true
                local nm = GetSpellInfo and GetSpellInfo(n)
                if nm then names[nm] = true end
            end
        end
        if next(names) == nil then names = false end
    end
    if tr.useExactSpellId and type(tr.auraspellids) == "table" then
        ids = {}
        for _, n in ipairs(tr.auraspellids) do
            local num = tonumber(n)
            if num then ids[num] = true end
        end
        if next(ids) == nil then ids = false end
    end
    ctx.names, ctx.ids = names, ids
    -- what to ignore
    ctx.ignoreNames, ctx.ignoreIds = nil, nil
    if tr.useIgnoreName and type(tr.ignoreAuraNames) == "table" then
        ctx.ignoreNames = {}
        for _, n in ipairs(tr.ignoreAuraNames) do
            local num = tonumber(n)
            local nm = num and GetSpellInfo and GetSpellInfo(num) or n
            if nm then ctx.ignoreNames[nm] = true end
        end
    end
    if tr.useIgnoreExactSpellId and type(tr.ignoreAuraSpellids) == "table" then
        ctx.ignoreIds = {}
        for _, n in ipairs(tr.ignoreAuraSpellids) do
            local num = tonumber(n)
            if num then ctx.ignoreIds[num] = true end
        end
    end
    return names, ids
end

local function Mine(caster)
    if not caster then return false end
    if caster == "player" or caster == "pet" or caster == "vehicle" then return true end
    return UnitIsUnit(caster, "player") or UnitIsUnit(caster, "pet")
end

-- the per-match checks (the format applies them only where a match can
-- be checked: not on a single unit shown when missing)
local function CanCheck(tr)
    if IsMultiUnit(tr) then return true end
    local m = tr.matchesShowOn
    if m == "showOnMissing" then return false end
    if m == nil or m == "showOnActive" or m == "showOnMatches" then return true end
    return tr.showClones and true or false
end

local function Matches(ctx, unit, aura)
    local tr = ctx.trigger
    local names, ids = NameSet(ctx)
    if names or ids then
        local hit = (names and (names[aura.name] or (aura.spellId and names[aura.spellId])))
            or (ids and aura.spellId and ids[aura.spellId])
        if not hit then return false end
    end
    if tr.ownOnly == true then
        if not Mine(aura.unitCaster) then return false end
    elseif tr.ownOnly == false then
        if Mine(aura.unitCaster) then return false end
    end
    if not CanCheck(tr) or tr.unit == "multi" then return true end
    if tr.useTotal and tr.total and not Compare((aura.duration or 0) / (aura.modRate or 1), tr.totalOperator or ">=", tr.total) then return false end
    if tr.useStacks and not Compare(aura.stacks or 0, tr.stacksOperator or ">=", tr.stacks) then return false end
    if tr.use_stealable ~= nil and (aura.isStealable and true or false) ~= tr.use_stealable then return false end
    if tr.use_isBossDebuff ~= nil and (aura.isBossDebuff and true or false) ~= tr.use_isBossDebuff then return false end
    if tr.use_castByPlayer ~= nil and (aura.isCastByPlayer and true or false) ~= tr.use_castByPlayer then return false end
    if tr.use_debuffClass then
        local set = type(tr.debuffClass) == "table" and tr.debuffClass or {}
        if not set[aura.debuffClass] then return false end
    end
    if tr.fetchTooltip and (tr.use_tooltip or tr.use_tooltipValue) then
        if aura.tooltip == nil then
            aura.tooltip, aura.tooltip1, aura.tooltip2, aura.tooltip3, aura.tooltip4 = TooltipOf(aura.unit, aura.index, aura.filter)
            aura.tooltip = aura.tooltip or ""
        end
        if tr.use_tooltip and tr.tooltip_operator and tr.tooltip and not StrOp(aura.tooltip, tr.tooltip_operator, tr.tooltip) then return false end
        if tr.use_tooltipValue and tr.tooltipValueNumber and tr.tooltipValue_operator and tr.tooltipValue then
            local have = aura["tooltip" .. tostring(tonumber(tr.tooltipValueNumber) or 1)]
            if have == nil or not Compare(have, tr.tooltipValue_operator, tr.tooltipValue) then return false end
        end
    end
    if tr.useNamePattern and tr.namePattern_operator and tr.namePattern_name then
        if not StrOp(aura.name, tr.namePattern_operator, tr.namePattern_name) then return false end
    end
    if ctx.ignoreNames and ctx.ignoreNames[aura.name] then return false end
    if ctx.ignoreIds and aura.spellId and ctx.ignoreIds[aura.spellId] then return false end
    return true
end

-- the remaining-time check (auras without a duration never pass it)
local function RemOK(tr, aura, now)
    if tr.unit == "multi" or not tr.useRem or not CanCheck(tr) then return true end
    if not aura.expirationTime or aura.expirationTime == 0 or (aura.duration or 0) == 0 then return false end
    local rem = (aura.expirationTime - now) / (aura.modRate or 1)
    return Compare(rem, tr.remOperator or ">=", tonumber(tr.rem) or 0)
end

local function UnitOK(ctx, unit)
    local tr = ctx.trigger
    if not UnitExists(unit) then return false end
    local group = IsGroupUnit(tr.unit)
    if (group or tr.unit == "nameplate") and tr.ignoreSelf and UnitIsUnit(unit, "player") then return false end
    if group and (tr.ignoreDead or tr.use_ignoreDead) and UnitIsDeadOrGhost(unit) then return false end
    if group and (tr.ignoreDisconnected or tr.use_ignoreDisconnected) and UnitIsConnected and not UnitIsConnected(unit) then return false end
    if group and tr.ignoreInvisible and UnitIsVisible and not UnitIsVisible(unit) then return false end
    if group and tr.useGroupRole and type(tr.group_role) == "table" and next(tr.group_role) then
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
        if not tr.group_role[role] then return false end
    end
    if group and tr.useRaidRole and type(tr.raid_role) == "table" and next(tr.raid_role) then
        local role = "NONE"
        if GetPartyAssignment then
            if GetPartyAssignment("MAINTANK", unit) then role = "MAINTANK"
            elseif GetPartyAssignment("MAINASSIST", unit) then role = "MAINASSIST" end
        end
        if not tr.raid_role[role] then return false end
    end
    if group and tr.useClass and type(tr.class) == "table" and next(tr.class) then
        local c = select(2, UnitClass(unit))
        if not tr.class[c] then return false end
    end
    if (group or tr.unit == "nameplate") and tr.useHostility and tr.hostility then
        local r = UnitReaction and UnitReaction("player", unit)
        local h = r and (r < 5 and "hostile" or "friendly") or (UnitCanAttack and UnitCanAttack("player", unit) and "hostile" or "friendly")
        if h ~= tr.hostility then return false end
    end
    if group and tr.useUnitName and tr.unitName and Pr() then
        local name, realm = UnitName(unit)
        if not realm or realm == "" then realm = GetRealmName and GetRealmName() or "" end
        if not Pr().NameRealmCheck(tr.unitName, name, realm) then return false end
    end
    if (tr.unit == "nameplate" or tr.unit == "boss") and tr.useNpcId and tr.npcId and tr.npcId ~= "" then
        local guid = UnitGUID(unit)
        local npc = guid and select(6, strsplit("-", guid))
        if Pr() then
            if not Pr().ListCheck(tr.npcId, npc) then return false end
        else
            local hit = false
            for part in tostring(tr.npcId):gmatch("[^,%s]+") do if part == npc then hit = true break end end
            if not hit then return false end
        end
    end
    return true
end

-- ============================================================
-- STATES
-- ============================================================
local ROLE_ICONS = { TANK = "|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:0:0:0:0:256:256:0:67:67:134|t",
    HEALER = "|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:0:0:0:0:256:256:67:134:0:67|t",
    DAMAGER = "|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:0:0:0:0:256:256:67:134:67:134|t" }

local function Extras(ctx, st, unit)
    local tr = ctx.trigger
    if tr.fetchRole and unit then
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
        st.role, st.roleIcon = role, role and ROLE_ICONS[role] or nil
    end
    if tr.fetchRaidMark and unit then
        local rt = GetRaidTargetIndex and GetRaidTargetIndex(unit)
        st.raidMark = rt and ("{rt" .. rt .. "}") or nil
    end
end

local function StateFrom(ctx, st, unit, aura, now)
    st.show, st.changed = true, true
    if st.spellId ~= aura.spellId or not st.active then st.initialTime = now end
    if (st.expirationTime or 0) ~= (aura.expirationTime or 0) or not st.refreshTime then st.refreshTime = now end
    local oldStacks = st.stacks or 0
    if (aura.stacks or 0) > oldStacks and st.active then st.stackGainTime = now
    elseif (aura.stacks or 0) < oldStacks and st.active then st.stackLostTime = now end
    st.unit = unit
    st.unitName = unit and UnitName(unit) or nil
    st.GUID = unit and UnitGUID(unit) or aura.GUID
    st.name, st.icon, st.stacks = aura.name, aura.icon, aura.stacks
    st.spellId, st.debuffClass, st.unitCaster = aura.spellId, aura.debuffClass, aura.unitCaster
    st.debuffClassIcon = CLASS_ICONS[aura.debuffClass or ""]
    st.casterName = aura.unitCaster and UnitName(aura.unitCaster) or nil
    st.index, st.filter = aura.index, aura.filter
    st.modRate = aura.modRate or 1
    st.active = true
    st.time = now
    if ctx.trigger.fetchTooltip and aura.tooltip == nil and aura.index then
        aura.tooltip, aura.tooltip1, aura.tooltip2, aura.tooltip3, aura.tooltip4 = TooltipOf(aura.unit, aura.index, aura.filter)
    end
    st.tooltip, st.tooltip1, st.tooltip2, st.tooltip3, st.tooltip4 = aura.tooltip, aura.tooltip1, aura.tooltip2, aura.tooltip3, aura.tooltip4
    if aura.duration and aura.duration > 0 and aura.expirationTime and aura.expirationTime > 0 then
        st.progressType, st.duration, st.expirationTime = "timed", aura.duration, aura.expirationTime
    else
        st.progressType, st.duration, st.expirationTime = "timed", 0, math.huge
    end
    st.autoHide = false
    Extras(ctx, st, unit)
    return st
end

local function FallbackName(ctx)
    local names, ids = NameSet(ctx)
    local tr = ctx.trigger
    if tr.useName and type(tr.auranames) == "table" then
        for _, n in ipairs(tr.auranames) do
            local num = tonumber(n)
            local nm = num and GetSpellInfo and GetSpellInfo(num) or n
            if nm and nm ~= "" then
                local ic = GetSpellTexture and select(2, pcall(GetSpellTexture, num or nm)) or nil
                return nm, ic
            end
        end
    end
    if tr.useExactSpellId and type(tr.auraspellids) == "table" then
        for _, n in ipairs(tr.auraspellids) do
            local num = tonumber(n)
            if num and GetSpellInfo then
                local nm, _, ic = GetSpellInfo(num)
                if nm then return nm, ic end
            end
        end
    end
    return nil, nil
end

local function NoMatchState(ctx, st, unit, now)
    st.show, st.changed, st.active = true, true, false
    st.progressType, st.duration, st.expirationTime, st.modRate = "timed", 0, math.huge, 1
    st.stacks, st.initialTime, st.refreshTime = nil, nil, nil
    st.unit = unit
    st.unitName = unit and UnitName(unit) or ""
    st.time = now
    local nm, ic = FallbackName(ctx)
    st.name = nm
    st.icon = ic
    st.autoHide = false
    Extras(ctx, st, unit)
    return st
end

local function Better(mode, a, b)
    -- true when a beats b
    if mode == "showHighest" then
        if a.expirationTime and b.expirationTime then return a.expirationTime > b.expirationTime end
        return true
    end
    if mode == "showLowestSpellId" then return (a.spellId or 0) < (b.spellId or 0) end
    if mode == "showHighestSpellId" then return (a.spellId or 0) > (b.spellId or 0) end
    if a.expirationTime and b.expirationTime then
        local ea = a.expirationTime > 0 and a.expirationTime or math.huge
        local eb = b.expirationTime > 0 and b.expirationTime or math.huge
        return ea < eb
    end
    return false
end

-- the per-unit list of matching auras (and the multi-target ones)
local multiAuras = {}     -- destGUID -> { key -> aura }

local function Collect(ctx, units, now)
    local tr = ctx.trigger
    local filters
    if tr.debuffType == "HARMFUL" then filters = { "HARMFUL" }
    elseif tr.debuffType == "BOTH" then filters = { "HELPFUL", "HARMFUL" }
    else filters = { "HELPFUL" } end
    local perUnit, unitsSeen, nextCheck = {}, {}, nil
    if tr.unit == "multi" then
        for guid, list in pairs(multiAuras) do
            for _, aura in pairs(list) do
                local okFilter = false
                for _, f in ipairs(filters) do if aura.filter == f then okFilter = true end end
                if okFilter and (not aura.expirationTime or aura.expirationTime == 0 or aura.expirationTime > now) and Matches(ctx, nil, aura) then
                    perUnit[guid] = perUnit[guid] or {}
                    table.insert(perUnit[guid], aura)
                end
            end
        end
        return perUnit, unitsSeen, 0
    end
    local total = 0
    ctx.watch = {}
    for _, unit in ipairs(units) do
        ctx.watch[unit] = true
        if UnitOK(ctx, unit) then
            total = total + 1
            unitsSeen[#unitsSeen + 1] = unit
            local s = Get(unit)
            for _, f in ipairs(filters) do
                for _, aura in ipairs(s[f]) do
                    if Matches(ctx, unit, aura) then
                        if tr.useRem and CanCheck(tr) and aura.expirationTime and aura.expirationTime > 0 then
                            local want = tonumber(tr.rem) or 0
                            local at = aura.expirationTime - want * (aura.modRate or 1)
                            if at > now and (not nextCheck or at < nextCheck) then nextCheck = at end
                        end
                        if RemOK(tr, aura, now) then
                            perUnit[unit] = perUnit[unit] or {}
                            table.insert(perUnit[unit], aura)
                        end
                    end
                end
            end
        end
    end
    return perUnit, unitsSeen, total, nextCheck
end

local function Update(ctx)
    local tr = ctx.trigger
    local now = GetTime()
    local units, multiUnit = Units(tr)
    local group = IsMultiUnit(tr)
    local perUnit, unitsSeen, total, nextCheck = Collect(ctx, units, now)
    if tr.unit == "multi" then total = 0 end
    if not group then total = (units[1] and units[1] ~= "" and UnitExists(units[1])) and 1 or 0 end
    local showOn = tr.matchesShowOn or "showOnActive"
    local matchCount, unitCount, totalStacks = 0, 0, 0
    local all = {}
    for unit, list in pairs(perUnit) do
        unitCount = unitCount + 1
        for _, aura in ipairs(list) do
            matchCount = matchCount + 1
            totalStacks = totalStacks + (aura.stacks or 0)
            all[#all + 1] = { unit = unit, aura = aura }
        end
    end
    table.sort(all, function(a, b)
        if a.unit ~= b.unit then return tostring(a.unit) < tostring(b.unit) end
        return (a.aura.index or 0) < (b.aura.index or 0)
    end)

    -- the counts that decide whether anything shows
    local function CountsOK(perUnitMode)
        if group then
            if tr.useGroup_count then
                local n, kind = ParseCount(tr.group_count)
                local op = tr.group_countOperator
                if n and kind and op then
                    if kind == "whole" then
                        if not Compare(unitCount, op, n) then return false end
                    else
                        if total == 0 or not Compare(unitCount / total, op, n) then return false end
                    end
                elseif unitCount <= 0 then
                    return false
                end
            end
            if tr.useMatch_count and tr.match_countOperator and tonumber(tr.match_count) then
                if not Compare(matchCount, tr.match_countOperator, tonumber(tr.match_count)) then return false end
            elseif tr.showClones and not tr.combinePerUnit then
                if matchCount < 1 then return false end
            end
            return true
        end
        if tr.unitExists ~= nil and tr.unit ~= "player" and total == 0 then return tr.unitExists and true or false end
        if showOn == "showOnMatches" then
            if tr.match_countOperator and tonumber(tr.match_count) then
                return Compare(matchCount, tr.match_countOperator, tonumber(tr.match_count))
            end
            return true
        elseif showOn == "showOnMissing" then
            return matchCount == 0
        elseif showOn == "showOnActive" then
            return matchCount >= 1
        end
        return true
    end

    local affected, unaffected, affectedUnits, unaffectedUnits
    if group and tr.useAffected then
        affected, unaffected, affectedUnits, unaffectedUnits = {}, {}, {}, {}
        for _, unit in ipairs(unitsSeen) do
            if perUnit[unit] then affected[#affected + 1] = UnitName(unit) or unit affectedUnits[#affectedUnits + 1] = unit
            else unaffected[#unaffected + 1] = UnitName(unit) or unit unaffectedUnits[#unaffectedUnits + 1] = unit end
        end
        affected = #affected > 0 and table.concat(affected, ", ") or "None"
        unaffected = #unaffected > 0 and table.concat(unaffected, ", ") or "None"
    end

    local states = ctx.states
    local keep = {}
    local function Common(st, perUnitCount)
        st.matchCount, st.unitCount, st.maxUnitCount = matchCount, unitCount, total
        st.matchCountPerUnit = perUnitCount or matchCount
        st.totalStacks = totalStacks
        st.affected, st.unaffected, st.affectedUnits, st.unaffectedUnits = affected, unaffected, affectedUnits, unaffectedUnits
    end
    local function Best(list)
        local best
        for _, aura in ipairs(list) do
            if not best or Better(tr.combineMode, aura, best) then best = aura end
        end
        return best
    end

    local legacyMissing = group and showOn == "showOnMissing" and tr.showClones and not tr.combinePerUnit and multiUnit
    local single = not group and showOn == "showOnMissing"
    if legacyMissing then
        -- a ZacUI-made group trigger shown "when missing", one per unit
        -- without it (the format's own way is combinePerUnit + unaffected)
        local without = {}
        for _, unit in ipairs(unitsSeen) do if not perUnit[unit] then without[#without + 1] = unit end end
        local ok = true
        if tr.useGroup_count then
            local n, kind = ParseCount(tr.group_count)
            if n and tr.group_countOperator then
                ok = kind == "whole" and Compare(#without, tr.group_countOperator, n)
                    or (total > 0 and Compare(#without / total, tr.group_countOperator, n))
            end
        end
        if ok then
            for _, unit in ipairs(without) do
                local st = states[unit] or {}
                NoMatchState(ctx, st, unit, now)
                Common(st, 0)
                states[unit] = st
                keep[unit] = true
            end
        end
    elseif not single and tr.showClones and group and tr.combinePerUnit then
        local mode = (tr.unit == "multi") and "affected" or (tr.perUnitMode or "affected")
        local perOK = function(n)
            if tr.useMatchPerUnit_count and tonumber(tr.matchPerUnit_count) and tr.matchPerUnit_countOperator and mode ~= "unaffected" then
                return Compare(n, tr.matchPerUnit_countOperator, tonumber(tr.matchPerUnit_count))
            end
            return true
        end
        if CountsOK(mode) then
            if mode == "affected" then
                for unit, list in pairs(perUnit) do
                    if perOK(#list) then
                        local st = states[unit] or {}
                        StateFrom(ctx, st, tr.unit ~= "multi" and unit or nil, Best(list), now)
                        Common(st, #list)
                        states[unit] = st
                        keep[unit] = true
                    end
                end
            else
                for _, unit in ipairs(unitsSeen) do
                    local list = perUnit[unit]
                    local st = states[unit] or {}
                    if list then
                        if mode == "all" and perOK(#list) then
                            StateFrom(ctx, st, unit, Best(list), now)
                            Common(st, #list)
                            states[unit] = st
                            keep[unit] = true
                        end
                    else
                        NoMatchState(ctx, st, unit, now)
                        Common(st, 0)
                        states[unit] = st
                        keep[unit] = true
                    end
                end
            end
        end
    elseif not single and tr.showClones then
        if CountsOK() then
            local used = {}
            for _, m in ipairs(all) do
                local a = m.aura
                local cid
                if a.unit then cid = a.unit .. "." .. tostring(UnitGUID(a.unit) or a.unit) .. " " .. tostring(a.spellId or a.name)
                else cid = tostring(m.unit) .. " " .. tostring(a.spellId or a.name) end
                if used[cid] then used[cid] = used[cid] + 1 cid = cid .. used[cid] else used[cid] = 1 end
                local st = states[cid] or {}
                StateFrom(ctx, st, a.unit, a, now)
                if not a.unit then st.GUID = m.unit end
                Common(st, #perUnit[m.unit])
                states[cid] = st
                keep[cid] = true
            end
            if matchCount == 0 then
                local st = states[""] or {}
                NoMatchState(ctx, st, not group and units[1] or nil, now)
                Common(st, 0)
                states[""] = st
                keep[""] = true
            end
        end
    else
        if CountsOK() then
            local best
            for _, m in ipairs(all) do
                if not best or Better(tr.combineMode, m.aura, best.aura) then best = m end
            end
            local st = states[""] or {}
            if best and not single then
                StateFrom(ctx, st, best.aura.unit, best.aura, now)
                if not best.aura.unit then st.GUID = best.unit end
                Common(st, #perUnit[best.unit])
            else
                NoMatchState(ctx, st, not group and units[1] or nil, now)
                Common(st, 0)
            end
            states[""] = st
            keep[""] = true
        end
    end

    local changed = false
    for cid, st in pairs(states) do
        if keep[cid] then
            changed = true
        elseif st.show then
            st.show, st.changed = false, true
            changed = true
        else
            states[cid] = nil
        end
    end
    if nextCheck then A.At(ctx, nextCheck) end
    if changed then
        E.Changed(ctx.id)
        Tr.Notify(ctx.id, ctx.index)
    end
end
A.Update = Update

-- ============================================================
-- WHO IS LISTENING, AND THE ONCE-A-FRAME PASS
-- ============================================================
local ctxs = {}           -- ctx -> true
local pass = CreateFrame("Frame")
pass:Hide()
local all = false

local function Mark(unit)
    if unit then
        scans[unit] = nil
        dirty[unit] = true
    else
        wipe(scans)
        all = true
    end
    pass:Show()
end
A.Mark = Mark

local platesMoved, multiMoved = false, false
pass:SetScript("OnUpdate", function(self)
    self:Hide()
    local full = all
    all = false
    local pm, mm = platesMoved, multiMoved
    platesMoved, multiMoved = false, false
    local d = dirty
    dirty = {}
    for ctx in pairs(ctxs) do
        local u = ctx.trigger.unit
        local hit = full or (pm and u == "nameplate") or (mm and u == "multi")
        if not hit and ctx.watch then
            for unit in pairs(d) do
                if ctx.watch[unit] then hit = true break end
            end
        elseif not ctx.watch then
            hit = true
        end
        if hit then
            local ok, err = pcall(Update, ctx)
            if not ok then E.Error(ctx.id, "aura trigger", err) end
        end
    end
end)

-- a re-check at a moment (a remaining-time check flips, an aura ends)
function A.At(ctx, when)
    local delay = when - GetTime()
    if delay <= 0 or delay > 3600 then return end
    if ctx.atWhen and ctx.atWhen <= when and ctx.atWhen > GetTime() then return end
    ctx.atWhen = when
    C_Timer.After(delay + 0.01, function()
        if ctx.atWhen == when then ctx.atWhen = nil end
        if ctxs[ctx] then pcall(Update, ctx) end
    end)
end

function A.Add(ctx)
    ctxs[ctx] = true
    ctx.names = nil
    Update(ctx)
end

function A.Remove(ctx)
    ctxs[ctx] = nil
end

E.On("UNIT_AURA", "aura2.scan", function(_, unit) Mark(unit) end)
E.On("PLAYER_TARGET_CHANGED", "aura2.target", function() Mark("target") end)
E.On("PLAYER_SOFT_ENEMY_CHANGED", "aura2.soft", function() Mark("softenemy") end)
E.On("PLAYER_SOFT_FRIEND_CHANGED", "aura2.soft2", function() Mark("softfriend") end)
E.On("PLAYER_FOCUS_CHANGED", "aura2.focus", function() Mark("focus") end)
E.On("UNIT_PET", "aura2.pet", function() Mark("pet") end)
E.On("GROUP_ROSTER_UPDATE", "aura2.roster", function() Mark(nil) end)
E.On("PLAYER_ENTERING_WORLD", "aura2.world", function() Mark(nil) end)
E.On("INSTANCE_ENCOUNTER_ENGAGE_UNIT", "aura2.boss", function() Mark(nil) end)
E.On("UNIT_FLAGS", "aura2.flags", function(_, unit) if unit then Mark(unit) end end)
E.On("UNIT_CONNECTION", "aura2.conn", function(_, unit) if unit then Mark(unit) end end)
E.On("NAME_PLATE_UNIT_ADDED", "aura2.plates", function(_, unit)
    plates[unit] = true
    platesMoved = true
    Mark(unit)
end)
E.On("NAME_PLATE_UNIT_REMOVED", "aura2.plates", function(_, unit)
    plates[unit] = nil
    platesMoved = true
    Mark(unit)
end)

-- ============================================================
-- MULTI-TARGET: auras seen in the combat log, by target GUID
-- ============================================================
-- Only listened to while a "multi" trigger is loaded. The log carries
-- no durations, so these show without a timer until the log says the
-- aura went (or the target died).
local multiOn = false
local function MultiLog(_, ...)
    local _, sub, _, sGUID, _, _, _, dGUID, dName, _, _, spellId, spellName, _, auraType = ...
    if not dGUID then return end
    if sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" or sub == "SPELL_AURA_APPLIED_DOSE" then
        local list = multiAuras[dGUID] or {}
        multiAuras[dGUID] = list
        local key = tostring(spellId ~= 0 and spellId or spellName) .. ":" .. tostring(sGUID)
        local a = list[key] or {}
        a.name, a.spellId = spellName, spellId ~= 0 and spellId or nil
        a.filter = auraType == "DEBUFF" and "HARMFUL" or "HELPFUL"
        a.unitCaster = (sGUID == UnitGUID("player") and "player") or (sGUID == UnitGUID("pet") and "pet") or nil
        a.GUID, a.destName = dGUID, dName
        a.icon = GetSpellTexture and select(2, pcall(GetSpellTexture, a.spellId or spellName)) or nil
        a.stacks = a.stacks or 0
        a.duration, a.expirationTime = a.duration or 0, a.expirationTime or 0
        list[key] = a
        multiMoved = true
        pass:Show()
    elseif sub == "SPELL_AURA_REMOVED" then
        local list = multiAuras[dGUID]
        if list then
            list[tostring(spellId ~= 0 and spellId or spellName) .. ":" .. tostring(sGUID)] = nil
            if next(list) == nil then multiAuras[dGUID] = nil end
            multiMoved = true
            pass:Show()
        end
    elseif sub == "UNIT_DIED" or sub == "UNIT_DESTROYED" then
        if multiAuras[dGUID] then multiAuras[dGUID] = nil multiMoved = true pass:Show() end
    end
end

local baseAdd = A.Add
function A.Add(ctx)
    if ctx.trigger.unit == "multi" and not multiOn and not E.FOREVER then
        multiOn = true
        E.On("COMBAT_LOG_EVENT_UNFILTERED", "aura2.multi", MultiLog)
    end
    baseAdd(ctx)
end
