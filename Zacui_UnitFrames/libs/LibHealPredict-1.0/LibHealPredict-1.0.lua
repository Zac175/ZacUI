--[[
LibHealPredict-1.0

Comms-free, per-caster incoming-heal attribution and chronological segment building,
computed entirely from native Blizzard APIs (UnitGetIncomingHeals, aura data, combat log,
cast-start events). No coordinator, no election, no wire protocol -- every client derives
the same picture independently, the way LibHealComm-4.0 did with active comms, but without
needing other players to run compatible addon code.

Every spell-ID table and API-behavior assumption in this file was verified in-game on a
1.15.9 client as well as a 2.5.6 client -- do not add spell IDs or API assumptions
here without the same discipline; a wrong assumption here breaks every consumer addon.

This library does not touch AceDB, does not create any UI, and does not know what a frame is.
Consumers own their own toggles (see SetTrackHots/SetPreciseHotTracking below) and decide for
themselves what to draw and how.
]] local MAJOR, MINOR = "LibHealPredict-1.0", 2
local LibHealPredict = LibStub:NewLibrary(MAJOR, MINOR)
if not LibHealPredict then
    return
end

LibHealPredict.callbacks = LibStub("CallbackHandler-1.0"):New(LibHealPredict)

-- ==========================================
-- Hot-path local upvalues
-- ==========================================
local GetTime = GetTime
local UnitAura = UnitAura
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitSpellTargetName = UnitSpellTargetName
local UnitExists = UnitExists
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local GetRaidRosterInfo = GetRaidRosterInfo
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local pairs, wipe, next = pairs, wipe, next

local playerGUID = UnitGUID("player")

-- ==========================================
-- Settings (consumer-controlled, no AceDB dependency)
-- ==========================================
local settings = {showAoE = true, showHots = true, preciseHotTracking = false, debug = false}

function LibHealPredict:SetTrackAoE(enabled)
    settings.showAoE = enabled and true or false
end

function LibHealPredict:SetTrackHots(enabled)
    settings.showHots = enabled and true or false
end

function LibHealPredict:SetPreciseHotTracking(enabled)
    settings.preciseHotTracking = enabled and true or false
end

function LibHealPredict:SetDebug(enabled)
    settings.debug = enabled and true or false
end

-- ==========================================
-- State
-- ==========================================
local rosterUnits = {}
local rosterGUIDToUnit = {}
local rosterNameToGUID = {}
local rosterBaseNameToGUID = {}
local rosterUnitSubgroups = {}
local rosterSubgroupMembers = {}
local activeCasts = {}
local castPool = {}
local hotState = {}
local segmentPool = {}
local activeSegments = {}
local manualAoECasts = {}
local cachedTotalHeals = {}
local casterInfoCache = {}
local casterInfoRetryAt = {}

local CASTER_INFO_RETRY_INTERVAL = 5 -- seconds between retries for unresolved caster class/name

-- ==========================================
-- Spell data -- in-game verified on 1.15.9 and 2.5.6
-- ==========================================
local calibrationSpellStats = {
    -- PRIEST
    -- Flash Heal
    [2061] = 193, -- Rank 1
    [9472] = 258, -- Rank 2
    [9473] = 327, -- Rank 3
    [9474] = 400, -- Rank 4
    [10915] = 518, -- Rank 5
    [10916] = 644, -- Rank 6
    [10917] = 812, -- Rank 7
    [25233] = 986, -- Rank 8 (TBC)
    [25235] = 1190, -- Rank 9 (TBC)
    -- Lesser Heal
    [2050] = 45, -- Rank 1
    [2052] = 71, -- Rank 2
    [2053] = 135, -- Rank 3
    -- Heal
    [2054] = 295, -- Rank 1
    [2055] = 429, -- Rank 2
    [6063] = 566, -- Rank 3
    [6064] = 712, -- Rank 4
    -- Greater Heal
    [2060] = 899, -- Rank 1
    [10963] = 1149, -- Rank 2
    [10964] = 1437, -- Rank 3
    [10965] = 1798, -- Rank 4
    [25314] = 1966, -- Rank 5
    [25210] = 2074, -- Rank 6 (TBC)
    [25213] = 2396, -- Rank 7 (TBC)
    -- Binding Heal (TBC)
    [32546] = 1190, -- Rank 1 (TBC)
    -- Prayer of Healing
    [596] = 301, -- Rank 1
    [996] = 444, -- Rank 2
    [10960] = 657, -- Rank 3
    [10961] = 939, -- Rank 4
    [25316] = 1041, -- Rank 5
    [25308] = 1281, -- Rank 6 (TBC)

    -- PALADIN
    -- Holy Light
    [635] = 39, -- Rank 1
    [639] = 76, -- Rank 2
    [647] = 159, -- Rank 3
    [1026] = 310, -- Rank 4
    [1042] = 491, -- Rank 5
    [3472] = 698, -- Rank 6
    [10328] = 945, -- Rank 7
    [10329] = 1246, -- Rank 8
    [25292] = 1590, -- Rank 9
    [27135] = 1840, -- Rank 10 (TBC)
    [27136] = 2321, -- Rank 11 (TBC)
    -- Flash of Light
    [19750] = 62, -- Rank 1
    [19939] = 96, -- Rank 2
    [19940] = 145, -- Rank 3
    [19941] = 197, -- Rank 4
    [19942] = 267, -- Rank 5
    [19943] = 343, -- Rank 6
    [27137] = 475, -- Rank 7 (TBC)

    -- SHAMAN
    -- Healing Wave
    [331] = 34, -- Rank 1
    [332] = 64, -- Rank 2
    [547] = 129, -- Rank 3
    [913] = 268, -- Rank 4
    [939] = 376, -- Rank 5
    [959] = 536, -- Rank 6
    [8005] = 740, -- Rank 7
    [10395] = 1017, -- Rank 8
    [10396] = 1367, -- Rank 9
    [25357] = 1620, -- Rank 10
    [25391] = 1847, -- Rank 11 (TBC)
    [25396] = 2285, -- Rank 12 (TBC)
    -- Lesser Healing Wave
    [8004] = 162, -- Rank 1
    [8008] = 247, -- Rank 2
    [8010] = 337, -- Rank 3
    [10466] = 458, -- Rank 4
    [10467] = 631, -- Rank 5
    [10468] = 832, -- Rank 6
    [25420] = 1112, -- Rank 7 (TBC)
    -- Chain Heal
    [1064] = 320, -- Rank 1
    [10622] = 405, -- Rank 2
    [10623] = 551, -- Rank 3
    [25422] = 648, -- Rank 4 (TBC)
    [25423] = 884, -- Rank 5 (TBC)

    -- DRUID
    -- Healing Touch
    [5185] = 37, -- Rank 1
    [5186] = 88, -- Rank 2
    [5187] = 189, -- Rank 3
    [5188] = 363, -- Rank 4
    [5189] = 572, -- Rank 5
    [6778] = 742, -- Rank 6
    [8903] = 936, -- Rank 7
    [9758] = 1199, -- Rank 8
    [9888] = 1516, -- Rank 9
    [9889] = 1890, -- Rank 10
    [25297] = 2267, -- Rank 11
    [26978] = 2577, -- Rank 12 (TBC)
    [26979] = 2952, -- Rank 13 (TBC)
    -- Regrowth (Initial direct heal piece)
    [8936] = 82, -- Rank 1
    [8938] = 164, -- Rank 2
    [8939] = 240, -- Rank 3
    [8940] = 318, -- Rank 4
    [8941] = 405, -- Rank 5
    [9750] = 511, -- Rank 6
    [9856] = 646, -- Rank 7
    [9857] = 809, -- Rank 8
    [9858] = 1003, -- Rank 9
    -- Lifebloom (Bloom piece)
    [33763] = 600 -- Rank 1 (TBC)
}

-- Boolean tracking table for fast aura scanning
local trackedHotSpells = {
    -- Priest (Renew)
    [139] = true,
    [6074] = true,
    [6075] = true,
    [6076] = true,
    [6077] = true,
    [6078] = true,
    [10927] = true,
    [10928] = true,
    [10929] = true,
    [25315] = true,
    [22009] = true, -- T2 Greater Heal Renew

    -- Druid (Rejuvenation)
    [774] = true,
    [1058] = true,
    [1430] = true,
    [2090] = true,
    [2091] = true,
    [3627] = true,
    [8910] = true,
    [9839] = true,
    [9840] = true,
    [9841] = true,
    [25299] = true,
    [26981] = true, -- (TBC)
    [26982] = true, -- (TBC)

    -- Druid (Regrowth HoT)
    [8936] = true,
    [8938] = true,
    [8939] = true,
    [8940] = true,
    [8941] = true,
    [9750] = true,
    [9856] = true,
    [9857] = true,
    [9858] = true,
    [9889] = true,
    [25297] = true,
    [26978] = true,

    -- Druid (Lifebloom)
    [33763] = true,

    -- Hunter (Mend Pet)
    [136] = true,
    [3111] = true,
    [3661] = true,
    [3662] = true,
    [13542] = true,
    [13543] = true,
    [13544] = true
}

-- For consumers building their own combat-log spell-relevance filters (e.g. a targeted aura
-- resync keyed off SPELL_AURA_APPLIED/REMOVED/REFRESH) without needing this private table.
function LibHealPredict:IsTrackedHotSpell(spellId)
    return trackedHotSpells[spellId] == true
end

-- HoT tick interval and base unbuffed tick amounts
local defaultHotData = {
    -- PRIEST
    -- Renew (Interval: 3s, 5 Ticks)
    [139] = {interval = 3, baseTick = 9}, -- Rank 1 (45 total)
    [6074] = {interval = 3, baseTick = 20}, -- Rank 2 (100 total)
    [6075] = {interval = 3, baseTick = 35}, -- Rank 3 (175 total)
    [6076] = {interval = 3, baseTick = 49}, -- Rank 4 (245 total)
    [6077] = {interval = 3, baseTick = 63}, -- Rank 5 (315 total)
    [6078] = {interval = 3, baseTick = 80}, -- Rank 6 (400 total)
    [10927] = {interval = 3, baseTick = 102}, -- Rank 7 (510 total)
    [10928] = {interval = 3, baseTick = 130}, -- Rank 8 (650 total)
    [10929] = {interval = 3, baseTick = 162}, -- Rank 9 (810 total)
    [25315] = {interval = 3, baseTick = 194}, -- Rank 10 (970 total)
    [22009] = {interval = 3, baseTick = 13}, -- T2 GH Renew

    -- DRUID
    -- Rejuvenation (Interval: 3s, 4 Ticks)
    [774] = {interval = 3, baseTick = 8}, -- Rank 1
    [1058] = {interval = 3, baseTick = 14}, -- Rank 2
    [1430] = {interval = 3, baseTick = 29}, -- Rank 3
    [2090] = {interval = 3, baseTick = 45}, -- Rank 4
    [2091] = {interval = 3, baseTick = 61}, -- Rank 5
    [3627] = {interval = 3, baseTick = 76}, -- Rank 6
    [8910] = {interval = 3, baseTick = 97}, -- Rank 7
    [9839] = {interval = 3, baseTick = 122}, -- Rank 8
    [9840] = {interval = 3, baseTick = 152}, -- Rank 9
    [9841] = {interval = 3, baseTick = 189}, -- Rank 10
    [25299] = {interval = 3, baseTick = 222}, -- Rank 11
    [26981] = {interval = 3, baseTick = 233}, -- Rank 12 (TBC)
    [26982] = {interval = 3, baseTick = 265}, -- Rank 13 (TBC)

    -- Regrowth HoT Piece (Interval: 3s, 7 Ticks)
    [8936] = {interval = 3, baseTick = 14}, -- Rank 1
    [8938] = {interval = 3, baseTick = 25}, -- Rank 2
    [8939] = {interval = 3, baseTick = 37}, -- Rank 3
    [8940] = {interval = 3, baseTick = 49}, -- Rank 4
    [8941] = {interval = 3, baseTick = 61}, -- Rank 5
    [9750] = {interval = 3, baseTick = 78}, -- Rank 6
    [9856] = {interval = 3, baseTick = 98}, -- Rank 7
    [9857] = {interval = 3, baseTick = 123}, -- Rank 8
    [9858] = {interval = 3, baseTick = 152}, -- Rank 9
    [9889] = {interval = 3, baseTick = 182}, -- Rank 10
    [25297] = {interval = 3, baseTick = 256}, -- Rank 11
    [26978] = {interval = 3, baseTick = 335}, -- Rank 12

    -- Lifebloom (Interval: 1s, 7 Ticks)
    [33763] = {interval = 1, baseTick = 39}, -- Rank 1

    -- HUNTER
    -- Mend Pet (Interval: 1s Classic, 3s TBC) 
    -- Defined using Classic 1s interval (5 Ticks)
    [136] = {interval = 1, baseTick = 20},
    [3111] = {interval = 1, baseTick = 38},
    [3661] = {interval = 1, baseTick = 68},
    [3662] = {interval = 1, baseTick = 103},
    [13542] = {interval = 1, baseTick = 142},
    [13543] = {interval = 1, baseTick = 189},
    [13544] = {interval = 1, baseTick = 245}
}

-- Group/AoE heals native UnitGetIncomingHeals is known (per in-game testing) to miss secondary
-- targets for -- these get the manual subgroup-based estimation fallback in BuildSegmentList.
-- Chain Heal is deliberately NOT here: its jumps are proximity-based, not derivable client-side,
-- and a synthetic segment would land on the wrong person as often as the right one.
local pohSpells = {
    [596] = true, -- Prayer of Healing Rank 1
    [996] = true, -- Rank 2
    [10960] = true, -- Rank 3
    [10961] = true, -- Rank 4
    [25316] = true -- Rank 5
}
local tranqSpells = {
    [740] = true, -- Tranquility Rank 1
    [8918] = true, -- Rank 2
    [9862] = true, -- Rank 3
    [9863] = true, -- Rank 4
    [25817] = true -- Rank 5
}
local aoeHealSpells = {}
for id in pairs(pohSpells) do
    aoeHealSpells[id] = true
end
for id in pairs(tranqSpells) do
    aoeHealSpells[id] = true
end

-- ==========================================
-- Internal Utilities
-- ==========================================
local function Debug(msg, ...)
    if settings.debug then
        print(string.format("|cff3fbfff[LibHealPredict]|r " .. msg, ...))
    end
end

-- ==========================================
-- Pooling
-- ==========================================
local function GetPooledSegment()
    local seg = next(segmentPool)
    if seg then
        segmentPool[seg] = nil

        return seg
    end

    return {}
end

local function GetPooledCast()
    local cast = next(castPool)
    if cast then
        castPool[cast] = nil

        return cast
    end

    return {}
end

local function ReleaseCast(casterGUID)
    local cast = activeCasts[casterGUID]
    if cast then
        castPool[cast] = true
        activeCasts[casterGUID] = nil
    end
end

-- ==========================================
-- Caster info (class/name resolution, cached with retry backoff; also holds the AoE
-- calibration ratio used by the manual PoH/Tranquility estimation fallback)
-- ==========================================
-- Returns englishClass, shortName -- both nil if not yet resolvable (e.g. player out of range).
-- Consumers own their own color mapping (RAID_CLASS_COLORS[englishClass]) and fallback color.
function LibHealPredict:GetCasterInfo(guid)
    if not guid then
        return nil, nil
    end

    local cached = casterInfoCache[guid]
    if not cached then
        local now = GetTime()
        local retryAt = casterInfoRetryAt[guid]
        if retryAt and now < retryAt then
            return nil, nil
        end

        local _, englishClass, _, _, _, name = GetPlayerInfoByGUID(guid)

        if englishClass and name then
            cached = {class = englishClass, shortName = string.sub(name, 1, 5), abilityRatio = 1.0}
            casterInfoCache[guid] = cached
            casterInfoRetryAt[guid] = nil
        else
            casterInfoRetryAt[guid] = now + CASTER_INFO_RETRY_INTERVAL

            return nil, nil
        end
    end

    return cached.class, cached.shortName
end

function LibHealPredict:IsMine(casterGUID)
    return casterGUID == playerGUID
end

-- ==========================================
-- Roster tracking
-- ==========================================
local function RebuildRoster()
    wipe(rosterUnits)
    wipe(rosterGUIDToUnit)
    wipe(rosterNameToGUID)
    wipe(rosterBaseNameToGUID)
    wipe(rosterUnitSubgroups)
    for sg = 1, 8 do
        local members = rosterSubgroupMembers[sg]
        if members then
            wipe(members)
        end
    end

    local seen = {}

    local function addUnit(unit, subgroup)
        if not UnitExists(unit) then
            return
        end

        local guid = UnitGUID(unit)
        if not guid or seen[guid] then
            return
        end

        seen[guid] = true
        rosterUnits[#rosterUnits + 1] = unit
        rosterGUIDToUnit[guid] = unit
        local name, realm = UnitName(unit)
        if name then
            local lookupName = (realm and realm ~= "") and (name .. "-" .. realm) or name
            if not rosterNameToGUID[lookupName] then
                rosterNameToGUID[lookupName] = guid
            end

            -- Base name tracking: 
            -- If it's the first time seeing this name, save the GUID
            -- If we see it again with a different GUID, flag it with 'false' to indicate a collision
            if rosterBaseNameToGUID[name] == nil then
                rosterBaseNameToGUID[name] = guid
            elseif rosterBaseNameToGUID[name] ~= guid then
                rosterBaseNameToGUID[name] = false
            end
        end
        rosterUnitSubgroups[guid] = subgroup

        if subgroup then
            local members = rosterSubgroupMembers[subgroup]
            if not members then
                members = {}
                rosterSubgroupMembers[subgroup] = members
            end
            members[#members + 1] = guid
        end
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local _, _, subgroup = GetRaidRosterInfo(i)
            addUnit("raid" .. i, subgroup)
        end
    else
        addUnit("player")
        if IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do
                addUnit("party" .. i)
            end
        end
    end

    for guid in pairs(hotState) do
        if not seen[guid] then
            hotState[guid] = nil
        end
    end
    for guid in pairs(activeCasts) do
        if not seen[guid] then
            ReleaseCast(guid)
        end
    end
    for guid in pairs(cachedTotalHeals) do
        if not seen[guid] then
            cachedTotalHeals[guid] = nil
        end
    end
    for guid in pairs(casterInfoCache) do
        if not seen[guid] then
            casterInfoCache[guid] = nil
        end
    end
    for guid in pairs(casterInfoRetryAt) do
        if not seen[guid] then
            casterInfoRetryAt[guid] = nil
        end
    end

    LibHealPredict.callbacks:Fire("HealPredict_RosterChanged")
end

-- ==========================================
-- Cast tracking
-- ==========================================
local function RefreshAoESubgroup(subgroup)
    local members = rosterSubgroupMembers[subgroup]
    if members then
        for i = 1, #members do
            LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", members[i])
        end
    end
end

local function RefreshNonRaidGroup()
    LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", UnitGUID("player"))
    for i = 1, GetNumSubgroupMembers() do
        local guid = UnitGUID("party" .. i)
        if guid then
            LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", guid)
        end
    end
end

local function RegisterCastEndTime(unit, isChannel, castGUID)
    local casterGUID = UnitGUID(unit)
    if not casterGUID then
        return
    end

    local _, _, _, startMS, endMS, _, _, _, spellID
    if isChannel then
        _, _, _, startMS, endMS, _, _, spellID = UnitChannelInfo(unit)
    else
        _, _, _, startMS, endMS, _, _, _, spellID = UnitCastingInfo(unit)
    end
    if not spellID then
        return
    end
    -- (ZacUI) WoW Forever hides other units' casts (secret values): no
    -- maths on them, so such a cast isn't tracked
    if issecretvalue ~= nil and (issecretvalue(spellID) or issecretvalue(startMS) or issecretvalue(endMS)
        or issecretvalue(castGUID)) then
        return
    end

    local startTime = (startMS or 0) / 1000
    local kind = isChannel and "channel" or "direct"

    local existing = activeCasts[casterGUID]
    if existing and existing.castGUID == castGUID then
        return
    end

    local spellTargetName = UnitSpellTargetName(unit)
    local displayedTargetGUID = UnitGUID(unit .. "target")
    local displayedTargetName, displayedTargetRealm = UnitName(unit .. "target")

    local fullDisplayedName = displayedTargetName
    if fullDisplayedName and displayedTargetRealm and displayedTargetRealm ~= "" then
        fullDisplayedName = fullDisplayedName .. "-" .. displayedTargetRealm
    end

    -- Safely resolves a name, accounting for UnitSpellTargetName stripping realms
    local function ResolveTargetName(nameToFind)
        if not nameToFind then
            return nil
        end

        if rosterNameToGUID[nameToFind] then
            if rosterBaseNameToGUID[nameToFind] ~= false then
                return rosterNameToGUID[nameToFind]
            end
        end

        local baseGUID = rosterBaseNameToGUID[nameToFind]

        return (baseGUID ~= false) and baseGUID or nil
    end

    local destGUID
    if not spellTargetName or spellTargetName == displayedTargetName then
        destGUID = displayedTargetGUID or ResolveTargetName(spellTargetName or fullDisplayedName)
    else
        destGUID = ResolveTargetName(spellTargetName)
    end

    if existing and (existing.destGUID ~= destGUID or existing.isAoE) then
        if existing.isAoE then
            if IsInRaid() then
                RefreshAoESubgroup(existing.subgroup)
            else
                RefreshNonRaidGroup()
            end
        elseif existing.destGUID then
            LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", existing.destGUID)
        end
    end

    if aoeHealSpells[spellID] then
        local casterSubGroup = rosterUnitSubgroups[casterGUID]

        Debug("AoE cast registered: spell=%d caster=%s inRaid=%s subgroup=%s", spellID, casterGUID, tostring(IsInRaid()),
              tostring(casterSubGroup))

        local cast = GetPooledCast()
        cast.castGUID = castGUID
        cast.destGUID = nil
        cast.spellID = spellID
        cast.startTime = startTime
        cast.endTime = (endMS or 0) / 1000
        cast.kind = kind
        cast.isAoE = true
        cast.subgroup = IsInRaid() and casterSubGroup or nil
        activeCasts[casterGUID] = cast

        if IsInRaid() then
            RefreshAoESubgroup(casterSubGroup)
        else
            RefreshNonRaidGroup()
        end
    else
        local cast = GetPooledCast()
        cast.castGUID = castGUID
        cast.destGUID = destGUID
        cast.spellID = spellID
        cast.startTime = startTime
        cast.endTime = (endMS or 0) / 1000
        cast.kind = kind
        cast.isAoE = nil
        cast.subgroup = nil
        activeCasts[casterGUID] = cast

        if destGUID then
            LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", destGUID)
        end
    end
end

local function ClearCast(unit, castGUID)
    local _, _, _, _, _, _, _, spellID = UnitChannelInfo(unit)
    if spellID then
        return
    end

    local casterGUID = UnitGUID(unit)
    if not casterGUID then
        return
    end

    local cast = activeCasts[casterGUID]
    if not cast or cast.castGUID ~= castGUID then
        return
    end

    ReleaseCast(casterGUID)

    if cast.isAoE then
        if IsInRaid() then
            RefreshAoESubgroup(cast.subgroup)
        else
            RefreshNonRaidGroup()
        end
    elseif cast.destGUID then
        LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", cast.destGUID)
    end
end

local function HandleCastDelayed(unit, castGUID, isChannel)
    local casterGUID = UnitGUID(unit)
    if not casterGUID then
        return
    end

    local cast = activeCasts[casterGUID]
    if not cast or cast.castGUID ~= castGUID then
        return
    end

    local _, _, _, _, endMS
    if isChannel then
        _, _, _, _, endMS = UnitChannelInfo(unit)
    else
        _, _, _, _, endMS = UnitCastingInfo(unit)
    end
    if not endMS then
        return
    end

    cast.endTime = endMS / 1000

    if cast.isAoE then
        if IsInRaid() then
            RefreshAoESubgroup(cast.subgroup)
        else
            RefreshNonRaidGroup()
        end
    elseif cast.destGUID then
        LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", cast.destGUID)
    end
end

local castTrackerFrame = CreateFrame("Frame")
castTrackerFrame:RegisterEvent("UNIT_SPELLCAST_START")
castTrackerFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
castTrackerFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
castTrackerFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
castTrackerFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
castTrackerFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
castTrackerFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castTrackerFrame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
castTrackerFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
castTrackerFrame:RegisterEvent("UNIT_HEAL_PREDICTION")
castTrackerFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

local rosterRebuildScheduled = false

castTrackerFrame:SetScript("OnEvent", function(self, event, unit, castGUID, ...)
    if event == "UNIT_HEAL_PREDICTION" then
        local guid = UnitGUID(unit)
        if guid then
            LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", guid)
        end
    elseif event == "UNIT_SPELLCAST_START" then
        RegisterCastEndTime(unit, false, castGUID)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        RegisterCastEndTime(unit, true, castGUID)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" or
        event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        ClearCast(unit, castGUID)
    elseif event == "UNIT_SPELLCAST_DELAYED" then
        HandleCastDelayed(unit, castGUID, false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        HandleCastDelayed(unit, castGUID, true)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not rosterRebuildScheduled then
            rosterRebuildScheduled = true
            C_Timer.After(0.2, function()
                rosterRebuildScheduled = false
                RebuildRoster()
            end)
        end
    end
end)

-- ==========================================
-- Aura / HoT scanning
-- ==========================================
-- Same-unit-same-tick dedup. GetTime() only advances once per rendered client frame, so two
-- callers asking to scan the same unit token within one tick (e.g. the native UNIT_AURA handler
-- and a CLEU-triggered targeted resync reacting to the same underlying aura change) collapse
-- into a single UnitAura() pass -- that loop is the single most expensive thing this library
-- does, so this specifically prevents paying for it twice for one real change.
local lastScanTick = {}

-- Scans one unit's buffs. Fires HealPredict_AuraObserved once per relevant aura so consumers
-- (shield glow, defensive status text, whatever else) can piggyback on this single UnitAura
-- pass instead of running their own. Fires HealPredict_SegmentsChanged only if HoT state this
-- library owns actually changed. Always fires HealPredict_AuraScanComplete at the end so
-- consumers doing their own mark-and-sweep bookkeeping (e.g. shield/status presence) know the
-- pass for this unit is done and it's safe to finalize/compare.
--
-- Returns changed, skipped -- both booleans. `skipped` is true when this call was a same-tick
-- duplicate and no scan actually ran (no callbacks fired at all in that case). Callers that want
-- real evidence of whether this is happening (rather than assuming) should log `skipped`.
function LibHealPredict:ScanAuras(unitId)
    local now = GetTime()
    if lastScanTick[unitId] == now then
        return false, true
    end
    lastScanTick[unitId] = now

    local targetGUID = UnitGUID(unitId)
    if not targetGUID then
        return false, false
    end

    self.callbacks:Fire("HealPredict_AuraScanStart", targetGUID)

    local changed = false
    local i = 1
    while true do
        local name, _, _, _, _, expirationTime, source, _, _, spellId = UnitAura(unitId, i, "HELPFUL")
        if not name then
            break
        end

        if spellId then
            local casterGUID = source and UnitGUID(source)
            self.callbacks:Fire("HealPredict_AuraObserved", targetGUID, unitId, spellId, expirationTime, casterGUID)

            if settings.showHots and trackedHotSpells[spellId] and casterGUID then
                hotState[targetGUID] = hotState[targetGUID] or {}
                hotState[targetGUID][casterGUID] = hotState[targetGUID][casterGUID] or {}
                local hs = hotState[targetGUID][casterGUID][spellId]

                if not hs then
                    hs = {}
                    hotState[targetGUID][casterGUID][spellId] = hs
                    changed = true

                    local defaultData = defaultHotData[spellId]
                    if defaultData then
                        hs.medianInterval = defaultData.interval

                        local currentRatio = 1.0
                        if casterInfoCache[casterGUID] and casterInfoCache[casterGUID].abilityRatio then
                            currentRatio = casterInfoCache[casterGUID].abilityRatio
                        end
                        hs.lastTickAmount = defaultData.baseTick * currentRatio

                        hs.lastTickTime = GetTime()
                        hs.nextTickTime = hs.lastTickTime + hs.medianInterval
                    end
                end

                if hs.expirationTime and expirationTime and hs.medianInterval and (expirationTime - hs.expirationTime) >
                    (hs.medianInterval * 0.5) then
                    hs.lastTickTime = GetTime()
                    hs.nextTickTime = hs.lastTickTime + hs.medianInterval
                    changed = true
                end

                hs.expirationTime = expirationTime
                hs.seen = true
            end
        end
        i = i + 1
    end

    if hotState[targetGUID] then
        for _, bySpell in pairs(hotState[targetGUID]) do
            for spellId, hs in pairs(bySpell) do
                if not hs.seen then
                    bySpell[spellId] = nil
                    changed = true
                else
                    hs.seen = false
                end
            end
        end
    end

    if changed then
        self.callbacks:Fire("HealPredict_SegmentsChanged", targetGUID)
    end

    self.callbacks:Fire("HealPredict_AuraScanComplete", targetGUID)

    return changed, false
end

-- ==========================================
-- Precise HoT tracking (combat log) -- opt-in via SetPreciseHotTracking(true)
-- ==========================================
local combatLogFrame = CreateFrame("Frame")
if not (_G.ZACUI_MODERN or (_G.ZacUI and _G.ZacUI.NoCombatLog and _G.ZacUI.NoCombatLog())) then combatLogFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") end   -- (no combat log on WoW Forever or Retail, or under ZacUI's game-version override's Forever)
combatLogFrame:SetScript("OnEvent", function(self, event)
    local _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID, _, _, amount = CombatLogGetCurrentEventInfo()

    if not settings.showHots or not settings.preciseHotTracking then
        return
    end

    if subEvent == "SPELL_AURA_APPLIED" and tranqSpells[spellID] then
        hotState[destGUID] = hotState[destGUID] or {}
        hotState[destGUID][sourceGUID] = hotState[destGUID][sourceGUID] or {}
        if not hotState[destGUID][sourceGUID][spellID] then
            hotState[destGUID][sourceGUID][spellID] = {medianInterval = 2, lastTickAmount = 0}
        end
        LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", destGUID)
    end

    if subEvent == "SPELL_AURA_REMOVED" and tranqSpells[spellID] then
        if hotState[destGUID] and hotState[destGUID][sourceGUID] then
            hotState[destGUID][sourceGUID][spellID] = nil
        end
        LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", destGUID)
    end

    if subEvent == "SPELL_HEAL" and pohSpells[spellID] then
        if activeCasts[sourceGUID] then
            ReleaseCast(sourceGUID)
        end
        LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", destGUID)
    end

    if subEvent == "SPELL_PERIODIC_HEAL" and (trackedHotSpells[spellID] or tranqSpells[spellID]) then
        hotState[destGUID] = hotState[destGUID] or {}
        hotState[destGUID][sourceGUID] = hotState[destGUID][sourceGUID] or {}

        local hs = hotState[destGUID][sourceGUID][spellID]
        if not hs then
            hs = {}
            hotState[destGUID][sourceGUID][spellID] = hs
        end

        local now = GetTime()
        if hs.lastTickTime then
            local delta = now - hs.lastTickTime
            local isOutlier = hs.medianInterval and delta > (hs.medianInterval * 1.5)

            if not isOutlier then
                if not hs.medianInterval then
                    hs.medianInterval = delta
                else
                    hs.medianInterval = (hs.medianInterval * 0.8) + (delta * 0.2)
                end
            end
        end

        hs.lastTickTime = now
        hs.lastTickAmount = amount
        hs.nextTickTime = hs.medianInterval and (now + hs.medianInterval) or nil

        LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", destGUID)
    end
end)

-- ==========================================
-- Segment building
-- ==========================================
local function BuildSegmentList(destGUID, destUnit)
    for i = 1, #activeSegments do
        segmentPool[activeSegments[i]] = true
    end
    wipe(activeSegments)
    wipe(manualAoECasts)

    local now = GetTime()

    for casterGUID, cast in pairs(activeCasts) do
        if now > (cast.endTime + 0.5) then
            if cast.isAoE then
                if IsInRaid() then
                    RefreshAoESubgroup(cast.subgroup)
                else
                    RefreshNonRaidGroup()
                end
            elseif cast.destGUID then
                LibHealPredict.callbacks:Fire("HealPredict_SegmentsChanged", cast.destGUID)
            end
            ReleaseCast(casterGUID)
        end
    end

    local calculatedTotalHeals = 0
    local totalIncoming = UnitGetIncomingHeals(destUnit) or 0
    -- WoW Forever can hand the incoming heals back hidden (a secret value):
    -- no maths on it, so the game's own numbers sit out and only the
    -- library's own tracked casts count
    if issecretvalue ~= nil and issecretvalue(totalIncoming) then totalIncoming = 0 end

    if settings.debug then
        for _, cast in pairs(activeCasts) do
            if cast.isAoE then
                Debug("dest=%s (%s) native totalIncoming=%.1f while an AoE cast is active", destGUID, destUnit, totalIncoming)

                break
            end
        end
    end

    if totalIncoming > 0 then
        for i = 1, #rosterUnits do
            local casterUnit = rosterUnits[i]
            local amount = UnitGetIncomingHeals(destUnit, casterUnit)

            if amount and amount > 0 then
                local seg = GetPooledSegment()
                local casterGUID = UnitGUID(casterUnit)
                local cast = activeCasts[casterGUID]

                if cast and (cast.destGUID == destGUID or cast.isAoE) then
                    seg.kind = cast.kind or "direct"
                    seg.startTime = cast.startTime
                    seg.endTime = cast.endTime
                    seg.spellID = cast.spellID

                    if cast.isAoE then
                        manualAoECasts[casterGUID] = true
                        Debug("Native split covered AoE caster=%s dest=%s amount=%.1f -- fallback suppressed for this target",
                              casterGUID, destGUID, amount)
                    end

                    if cast.spellID and calibrationSpellStats[cast.spellID] then
                        local expectedBase = calibrationSpellStats[cast.spellID]
                        local ratio = amount / expectedBase

                        if not casterInfoCache[casterGUID] then
                            casterInfoCache[casterGUID] = {abilityRatio = 1.0}
                        end
                        casterInfoCache[casterGUID].abilityRatio = ratio
                    end
                else
                    seg.kind = "direct"
                    seg.startTime = now
                    seg.endTime = now
                    seg.spellID = nil
                end

                seg.casterGUID = casterGUID
                seg.isMine = (casterGUID == playerGUID)
                seg.amount = amount
                calculatedTotalHeals = calculatedTotalHeals + amount

                activeSegments[#activeSegments + 1] = seg

                if calculatedTotalHeals >= totalIncoming then
                    break
                end
            end
        end
    end

    for casterGUID, cast in pairs(activeCasts) do
        if cast.isAoE and not manualAoECasts[casterGUID] then
            if settings.showAoE then
                local isValidTarget = false

                if IsInRaid() then
                    local targetSubgroup = rosterUnitSubgroups[destGUID]
                    if targetSubgroup and targetSubgroup == cast.subgroup then
                        isValidTarget = true
                    end
                else
                    isValidTarget = true
                end

                Debug("Manual AoE injection check: caster=%s dest=%s inRaid=%s destSubgroup=%s castSubgroup=%s -> valid=%s",
                      casterGUID, destGUID, tostring(IsInRaid()), tostring(rosterUnitSubgroups[destGUID]),
                      tostring(cast.subgroup), tostring(isValidTarget))

                if isValidTarget then
                    local seg = GetPooledSegment()

                    seg.kind = cast.kind or "direct"
                    seg.startTime = cast.startTime
                    seg.endTime = cast.endTime
                    seg.spellID = cast.spellID
                    seg.casterGUID = casterGUID
                    seg.isMine = (casterGUID == playerGUID)

                    local expectedBase = cast.spellID and calibrationSpellStats[cast.spellID] or 300
                    local currentRatio = casterInfoCache[casterGUID] and casterInfoCache[casterGUID].abilityRatio or 1.0

                    seg.amount = expectedBase * currentRatio
                    calculatedTotalHeals = calculatedTotalHeals + seg.amount
                    activeSegments[#activeSegments + 1] = seg
                end
            end
        end
    end

    if settings.showHots and hotState[destGUID] then
        for casterGUID, bySpell in pairs(hotState[destGUID]) do
            for spellID, hs in pairs(bySpell) do
                if hs.lastTickAmount and hs.nextTickTime then
                    if hs.expirationTime and hs.expirationTime > 0 and now > hs.expirationTime then
                        -- naturally expired, do not draw
                    else
                        local seg = GetPooledSegment()

                        seg.kind = "hot_tick"
                        seg.casterGUID = casterGUID
                        seg.isMine = (casterGUID == playerGUID)
                        seg.amount = hs.lastTickAmount
                        calculatedTotalHeals = calculatedTotalHeals + hs.lastTickAmount
                        seg.startTime = hs.nextTickTime
                        seg.endTime = hs.nextTickTime
                        seg.spellID = spellID

                        activeSegments[#activeSegments + 1] = seg
                    end
                end
            end
        end
    end

    cachedTotalHeals[destGUID] = calculatedTotalHeals

    return activeSegments
end

-- Returns the current pending-segment list for destGUID. The returned table is reused
-- internally between calls (same pooling discipline as the rest of this library) -- copy it
-- if you need it to outlive the next call for any unit.
function LibHealPredict:GetSegments(destGUID, destUnit)
    if not destGUID or not destUnit then
        return activeSegments
    end

    return BuildSegmentList(destGUID, destUnit)
end

function LibHealPredict:GetTotalIncoming(destGUID)
    return cachedTotalHeals[destGUID] or 0
end

-- Returns the currently-mapped unit token for a roster GUID, or nil if it's not (or no longer)
-- in the tracked roster. Used by consumers doing their own staleness cleanup against roster
-- membership (e.g. clearing a cached shield/status flag for someone who left the group).
function LibHealPredict:GetUnitForGUID(guid)
    return rosterGUIDToUnit[guid]
end

-- ==========================================
-- Init
-- ==========================================
if IsLoggedIn() then
    RebuildRoster()
else
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        RebuildRoster()
    end)
end
