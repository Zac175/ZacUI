-- Core_Services - shared game-state services for every ZacUI part.
-- Part of ZacUI; load order is set by the TOC (after Core_Media, before
-- anything that reads these).
-- ============================================================
-- WHY. Each part used to answer the same questions on its own: about
-- nine frames each unpacked every combat-log line, thirteen handlers
-- rebuilt their own picture of the group on every roster change, half a
-- dozen features walked the player's buffs on every aura change, and
-- the dodge/parry/block window was worked out three different ways (so
-- the HUD and the nameplate could disagree about Overpower). These
-- services answer each question once, for everyone.
--
--   ns.CLEU      one combat-log reader; listeners by sub-event
--   ns.Swings    your own swings on WoW Forever (no combat log there)
--   ns.Roster    the group: units, GUID/name -> unit, class
--   ns.PlayerAuras   the player's own buffs/debuffs, one read per change
--                (Readycheck's RC.Auras is used when it is loaded, so
--                both addons share that one read)
--   ns.Misses    the player's own dodged/parried/blocked swings and
--                abilities, by target
--   ns.Overpower the Overpower window on the exact mob that dodged
--   ns.Macros    macro name -> indexes, one walk per UPDATE_MACROS
--   ns.ActionSlots  action slot contents, one walk per slot change
--   ns.Profiler  TrackTicker(ticker, name) - counts live tickers
--   helpers      ns.Coalescer, ns.InRaidInstance, ns.GroupChannel,
--                ns.ShortName, ns.ClassColor, ns.OnAddonLoaded
--
-- RULES for callers:
--   * Data handed out (arrays, entries) is shared and read-only.
--   * Listener keys are strings owned by the caller ("NP_Debuffs.dodge");
--     registering the same key again replaces it; nil fn removes it.
--   * Listeners run inside pcall: one that errors is reported and the
--     others still run.
-- ============================================================

local ADDON_NAME, ns = ...

local pairs, ipairs, type, select, pcall, wipe = pairs, ipairs, type, select, pcall, wipe
local GetTime, UnitGUID, UnitName, UnitClass = GetTime, UnitGUID, UnitName, UnitClass
local IsInRaid, IsInGroup, GetNumGroupMembers, GetNumSubgroupMembers =
    IsInRaid, IsInGroup, GetNumGroupMembers, GetNumSubgroupMembers
local UnitExists = UnitExists
local C_Timer = C_Timer

local function Report(err)
    local h = geterrorhandler and geterrorhandler()
    if h then h(err) end
end

-- UnitGUID, or nil while WoW Forever hides it (an enemy's in a fight comes
-- back as a secret value: no keying, comparing or splitting it). On the
-- other clients exactly UnitGUID (read at call time).
function ns.SafeGUID(unit)
    local g = _G.UnitGUID(unit)
    if issecretvalue ~= nil and issecretvalue(g) then return nil end
    return g
end

-- The spell whose cooldown is the global cooldown: Blizzard's dummy 61304;
-- on WoW Forever 29515 when that client does not know 61304. Always 61304
-- on the other clients.
local gcdSpell
function ns.GCDSpell()
    if gcdSpell then return gcdSpell end
    local id = 61304
    if _G.ZACUI_MODERN and C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, 61304)
        if ok and not info then id = 29515 end
        if not ok then return id end   -- (ask again later)
    end
    gcdSpell = id
    return id
end

-- Runs every fn in a keyed listener table, isolated.
local function Notify(listeners, ...)
    for _, fn in pairs(listeners) do
        local ok, err = pcall(fn, ...)
        if not ok then Report(err) end
    end
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
-- fn runs once, delay seconds after the first call of a burst (0 = next
-- frame). gate, when given, must return true for a call to schedule
-- anything (e.g. "is the window visible").
function ns.Coalescer(fn, delay, gate)
    local pending = false
    local function run()
        pending = false
        fn()
    end
    return function()
        if pending then return end
        if gate and not gate() then return end
        pending = true
        C_Timer.After(delay or 0, run)
    end
end

function ns.InRaidInstance()
    local inInstance, kind = IsInInstance()
    return inInstance and kind == "raid" or false
end

-- The chat channel a group message should go to, or nil when solo.
function ns.GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) and not IsInGroup(LE_PARTY_CATEGORY_HOME or 1) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- "Name-Realm" -> "Name" (nil stays nil).
function ns.ShortName(name)
    if not name then return nil end
    if Ambiguate then return Ambiguate(name, "short") end
    return (name:match("^([^%-]+)")) or name
end

-- r, g, b for a class file name ("WARRIOR"); a class-colour addon's table
-- wins over Blizzard's. Unknown class -> grey.
function ns.ClassColor(classFile)
    local t = classFile and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFile])
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]))
    if t then return t.r, t.g, t.b end
    return 0.6, 0.6, 0.6
end

-- fn() once the named addon is loaded (now, if it already is).
local addonWaiters = {}
local addonFrame
function ns.OnAddonLoaded(name, fn)
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    if loaded and loaded(name) then
        local ok, err = pcall(fn)
        if not ok then Report(err) end
        return
    end
    addonWaiters[name] = addonWaiters[name] or {}
    table.insert(addonWaiters[name], fn)
    if not addonFrame then
        addonFrame = CreateFrame("Frame")
        addonFrame:RegisterEvent("ADDON_LOADED")
        addonFrame:SetScript("OnEvent", function(_, _, loadedName)
            local list = addonWaiters[loadedName]
            if not list then return end
            addonWaiters[loadedName] = nil
            for _, f in ipairs(list) do
                local ok, err = pcall(f)
                if not ok then Report(err) end
            end
        end)
    end
end

------------------------------------------------------------------------
-- Profiler: the parts call ns.Profiler.TrackTicker(ticker, name); it was
-- referenced but never defined, so nothing was tracked. Weak-keyed, so a
-- cancelled ticker drops out by itself.
------------------------------------------------------------------------
local tracked = setmetatable({}, { __mode = "k" })
ns.Profiler = ns.Profiler or {}
function ns.Profiler.TrackTicker(ticker, name)
    if ticker then tracked[ticker] = name or "?" end
    return ticker
end
function ns.Profiler.Tickers()
    local out = {}
    for t, name in pairs(tracked) do
        if not (t.IsCancelled and t:IsCancelled()) then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

------------------------------------------------------------------------
-- ns.CLEU - one combat-log reader.
--   ns.CLEU.On(key, sub, fn)   sub: a sub-event name, a list of them, or
--                              "*" for every line. fn gets exactly what
--                              CombatLogGetCurrentEventInfo() returns.
--   ns.CLEU.Off(key)           removes everything under key
--   ns.CLEU.Has(key)
-- The event is registered only while someone listens. Listener lists
-- are rebuilt into NEW tables on any change, so a listener may call
-- On/Off from inside a dispatch safely.
------------------------------------------------------------------------
local CLEU = {}
ns.CLEU = CLEU
local cleuReg = {}            -- key -> { [sub] = fn }
local cleuBySub, cleuAll = {}, {}
local cleuFrame = CreateFrame("Frame")
local GetCLEU = CombatLogGetCurrentEventInfo

local function CLEURebuild()
    local bySub, all, any = {}, {}, false
    for _, subs in pairs(cleuReg) do
        for sub, fn in pairs(subs) do
            any = true
            if sub == "*" then
                all[#all + 1] = fn
            else
                local l = bySub[sub]
                if not l then l = {}; bySub[sub] = l end
                l[#l + 1] = fn
            end
        end
    end
    cleuBySub, cleuAll = bySub, all
    -- no combat log for addons on WoW Forever (registering it is an
    -- error), and none under the override's Forever either (Core_Flavor)
    if _G.ZACUI_MODERN or (ns.NoCombatLog and ns.NoCombatLog()) then any = false end
    -- (on Forever even UNregistering it is forbidden, so only undo what
    -- was done: the frame never touches the event there at all)
    if any then
        if not cleuFrame._zOn then
            cleuFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
            cleuFrame._zOn = true
        end
    elseif cleuFrame._zOn then
        cleuFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        cleuFrame._zOn = nil
    end
end

local function CLEUDispatch(...)
    local list = cleuBySub[select(2, ...)]
    if list then
        for i = 1, #list do
            local ok, err = pcall(list[i], ...)
            if not ok then Report(err) end
        end
    end
    local all = cleuAll
    for i = 1, #all do
        local ok, err = pcall(all[i], ...)
        if not ok then Report(err) end
    end
end
cleuFrame:SetScript("OnEvent", function() CLEUDispatch(GetCLEU()) end)

function CLEU.On(key, sub, fn)
    if not fn then return CLEU.Off(key) end
    local subs = {}
    if type(sub) == "table" then
        for _, s in ipairs(sub) do subs[s] = fn end
    else
        subs[sub or "*"] = fn
    end
    cleuReg[key] = subs
    CLEURebuild()
end

function CLEU.Off(key)
    if cleuReg[key] == nil then return end
    cleuReg[key] = nil
    CLEURebuild()
end

function CLEU.Has(key) return cleuReg[key] ~= nil end

------------------------------------------------------------------------
-- ns.Swings - your own melee swings without the combat log (WoW
-- Forever). The game sends PLAYER_SWING(swingDuration, swingType) on
-- each of your swings (swingType 0 main hand, 1 off hand, 2 ranged;
-- warcraft.wiki.gg Event:PLAYER_SWING, a Forever-only event of the
-- SwingTimer system). It is only listened for on the real Forever
-- client, and only while someone wants it; on Era and TBC the combat
-- log's SWING_* lines keep doing this, so nothing here runs there.
--   ns.Swings.On(key, fn)   fn(hand, now, duration): hand "mh" | "oh" |
--                           "ranged" | "parry" (you parried a hit:
--                           UNIT_COMBAT on the player); duration is the
--                           game's swing time, else your attack speed,
--                           else nil when both are hidden. nil fn removes.
--   ns.Swings.Available()   true while this client sends the event
-- One event per swing (a second or so apart): the listeners only write
-- timestamps.
------------------------------------------------------------------------
local Swings = {}
ns.Swings = Swings
local swingReg, swingFrame, swingLive = {}, nil, false
local HANDS = { [0] = "mh", [1] = "oh", [2] = "ranged" }
local function Plain(v)
    if v ~= nil and issecretvalue ~= nil and issecretvalue(v) then return nil end
    return v
end

local function SwingDispatch(hand, dur, durObj)
    local now = GetTime()
    for _, fn in pairs(swingReg) do
        local ok, err = pcall(fn, hand, now, dur, durObj)
        if not ok then Report(err) end
    end
end

-- When the game hides both the swing time and your attack speed (WoW
-- Forever often does, even out of combat), the swing time is learned
-- from your own swings instead: the gap between two swings of the same
-- hand (plain GetTime() maths, never a hidden value). A faster gap is
-- taken at once (Flurry, Enrage); a slower one once two in a row agree,
-- so a swing held up out of range doesn't stretch the bar. Before any
-- gap is known the weapon's own speed off its tooltip stands in.
local SLOT_OF = { mh = 16, oh = 17, ranged = 18 }
local lastSwingAt, learned, pendingSlow = {}, {}, {}
local function WeaponSpeed(hand)
    local TI = C_TooltipInfo
    if not (TI and TI.GetInventoryItem) then return nil end
    local ok, data = pcall(TI.GetInventoryItem, "player", SLOT_OF[hand])
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    local word = _G.SPEED or "Speed"
    for _, line in ipairs(data.lines) do
        for _, txt in ipairs({ line.rightText, line.leftText }) do
            if type(txt) == "string" and not (issecretvalue ~= nil and issecretvalue(txt)) then
                local n = txt:match("^" .. word .. "%s+(%d+[%.,]%d+)")
                if n then
                    n = tonumber((n:gsub(",", ".")))
                    if n and n > 0 then return n end
                end
            end
        end
    end
    return nil
end

local function LearnedSwing(hand, now)
    local last = lastSwingAt[hand]
    lastSwingAt[hand] = now
    if last then
        local gap = now - last
        if gap > 0.5 and gap < 6 then
            local cur = learned[hand]
            if not cur or gap <= cur * 1.05 then
                learned[hand], pendingSlow[hand] = gap, nil
            elseif pendingSlow[hand] and math.abs(gap - pendingSlow[hand]) <= gap * 0.05 then
                learned[hand], pendingSlow[hand] = gap, nil
            else
                pendingSlow[hand] = gap
            end
        end
    end
    if not learned[hand] then learned[hand] = WeaponSpeed(hand) end
    return learned[hand]
end

-- (2026-11-07) A swing time the game hands over hidden still times a bar
-- exactly: a duration object (C_DurationUtil, Forever's API docs) started
-- now with that hidden length, which a StatusBar runs on the game's own
-- clock (HUD.TimedSwing). nil where the client has no such object.
local function SwingDuration(secretDur)
    local DU = C_DurationUtil
    if not (DU and DU.CreateDuration) then return nil end
    local ok, d = pcall(DU.CreateDuration)
    if not (ok and d and d.SetTimeFromStart) then return nil end
    if not pcall(d.SetTimeFromStart, d, GetTime(), secretDur, 1) then return nil end
    return d
end

local function OnSwingEvent(_, event, a1, a2)
    if event == "PLAYER_SWING" then
        local kind = Plain(a2)
        local hand = HANDS[kind] or "mh"
        local dur = Plain(a1)
        if type(dur) ~= "number" or dur <= 0 then
            dur = nil
            if hand == "ranged" then
                dur = UnitRangedDamage and Plain((UnitRangedDamage("player")))
            elseif UnitAttackSpeed then
                local mh, oh = UnitAttackSpeed("player")
                dur = Plain(hand == "oh" and oh or mh)
            end
        end
        local now = GetTime()
        if type(dur) == "number" and dur > 0 then
            lastSwingAt[hand], learned[hand], pendingSlow[hand] = now, dur, nil
        else
            dur = LearnedSwing(hand, now)
        end
        local durObj = issecretvalue ~= nil and issecretvalue(a1) and SwingDuration(a1) or nil
        SwingDispatch(hand, dur, durObj)
    elseif event == "UNIT_COMBAT" then
        -- (unit, action, ...): a hit on you that you parried
        if a1 == "player" and Plain(a2) == "PARRY" then SwingDispatch("parry", nil) end
    end
end

local function SwingRebuild()
    local want = next(swingReg) ~= nil and _G.ZACUI_IS_FOREVER and true or false
    if want == swingLive then return end
    if want then
        if not swingFrame then
            swingFrame = CreateFrame("Frame")
            swingFrame:SetScript("OnEvent", OnSwingEvent)
        end
        -- registering an event this client lacks throws: ask first
        local valid = C_EventUtils and C_EventUtils.IsEventValid
        if valid and not valid("PLAYER_SWING") then return end
        if not pcall(swingFrame.RegisterEvent, swingFrame, "PLAYER_SWING") then return end
        if swingFrame.RegisterUnitEvent then
            pcall(swingFrame.RegisterUnitEvent, swingFrame, "UNIT_COMBAT", "player")
        end
        swingLive = true
    elseif swingFrame then
        swingFrame:UnregisterAllEvents()
        swingLive = false
    end
end

function Swings.On(key, fn)
    swingReg[key] = fn
    SwingRebuild()
end

function Swings.Available() return swingLive end

------------------------------------------------------------------------
-- ns.Roster - the group, rebuilt once per burst of roster news.
--   Roster.Units()         array of unit tokens: "player" + party1..4,
--                          or raid1..N (the player is one of those)
--   Roster.PetUnits()      pet tokens that exist right now
--   Roster.UnitOf(guid)    unit token or nil
--   Roster.UnitByName(n)   by short name or "Name-Realm"
--   Roster.Class(x)        class file for a unit token or a name
--   Roster.Size(), Roster.InRaid(), Roster.Version()
--   Roster.On(key, fn)     fn(version) once per change, 0.1s after the
--                          burst; nil fn removes
-- Readers never see stale data: a pending rebuild runs on the first read.
------------------------------------------------------------------------
local Roster = {}
ns.Roster = Roster
local rUnits, rPets = {}, {}
local rByGUID, rByName, rClass = {}, {}, {}
local rDirty, rPetsDirty, rVersion, rInRaid = true, true, 0, false
local rListeners = {}

local function RosterAdd(unit)
    local guid = UnitGUID(unit)
    if not guid then return end
    rUnits[#rUnits + 1] = unit
    rByGUID[guid] = unit
    local name, realm = UnitName(unit)
    local _, class = UnitClass(unit)
    if name then
        rByName[name] = unit
        if realm and realm ~= "" then rByName[name .. "-" .. realm] = unit end
        rClass[name] = class
    end
    rClass[unit] = class
end

local function RosterRebuild()
    rDirty = false
    rPetsDirty = true
    rVersion = rVersion + 1
    wipe(rUnits); wipe(rByGUID); wipe(rByName); wipe(rClass)
    rInRaid = IsInRaid()
    if rInRaid then
        for i = 1, GetNumGroupMembers() do RosterAdd("raid" .. i) end
    else
        RosterAdd("player")
        for i = 1, GetNumSubgroupMembers() do RosterAdd("party" .. i) end
    end
end

local function RosterFresh() if rDirty then RosterRebuild() end end

function Roster.Units() RosterFresh() return rUnits end
function Roster.UnitOf(guid) RosterFresh() return guid and rByGUID[guid] end
function Roster.UnitByName(n) RosterFresh() return n and rByName[n] end
function Roster.Class(x) RosterFresh() return x and rClass[x] end
function Roster.Size() RosterFresh() return #rUnits end
function Roster.InRaid() RosterFresh() return rInRaid end
function Roster.Version() RosterFresh() return rVersion end
function Roster.On(key, fn) rListeners[key] = fn end

function Roster.PetUnits()
    RosterFresh()
    if rPetsDirty then
        rPetsDirty = false
        wipe(rPets)
        if rInRaid then
            for i = 1, #rUnits do
                local p = "raidpet" .. i
                if UnitExists(p) then rPets[#rPets + 1] = p end
            end
        else
            if UnitExists("pet") then rPets[#rPets + 1] = "pet" end
            for i = 1, GetNumSubgroupMembers() do
                local p = "partypet" .. i
                if UnitExists(p) then rPets[#rPets + 1] = p end
            end
        end
    end
    return rPets
end

local rosterFrame = CreateFrame("Frame")
local RosterAnnounce = ns.Coalescer(function()
    RosterFresh()
    Notify(rListeners, rVersion)
end, 0.1)
rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rosterFrame:RegisterEvent("UNIT_NAME_UPDATE")
rosterFrame:RegisterEvent("UNIT_PET")
rosterFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_PET" then
        rPetsDirty = true
        return
    end
    if event == "UNIT_NAME_UPDATE" then
        -- names arrive late for people who just joined; plates and
        -- strangers fire this too and are not ours
        if not (unit == "player" or (unit and (unit:find("^raid%d") or unit:find("^party%d")))) then
            return
        end
    end
    rDirty = true
    RosterAnnounce()
end)

------------------------------------------------------------------------
-- ns.PlayerAuras - the player's own buffs and debuffs.
--   Auras.Buffs() / Debuffs()     arrays of entries, slot order
--   Auras.Buff(id) / BuffNamed(n) / Debuff(id) / DebuffNamed(n)
--   Auras.Version()               moves on every change
--   Auras.On(key, fn)             fn() once per frame with aura changes,
--                                 on the frame AFTER the UNIT_AURA burst
--   Auras.Invalidate()
-- Entry: { name, icon, count, dispelType, duration, expirationTime,
--          source, spellId, index, instance } - the same shape as
-- Readycheck's RC.Auras, which this hands through when it is loaded.
-- Listen with Auras.On instead of registering UNIT_AURA yourself: the
-- notice comes after every addon's invalidation has run, so a read in
-- the listener is always current.
------------------------------------------------------------------------
local Auras = {}
ns.PlayerAuras = Auras
local GetBuffData = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex
local GetDebuffData = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex
local UnitBuff, UnitDebuff = UnitBuff, UnitDebuff
-- (WoW Forever can refuse an aura read outright: "Auras cannot be accessed
-- when secret while tainted" - read under pcall there, as no more auras)
local foreverClient = _G.ZACUI_MODERN and true or false   -- (Forever or Retail)
local aDirty, aVersion = true, 0
local aBuffs, aDebuffs = {}, {}
local aBuffById, aBuffByName, aDebuffById, aDebuffByName = {}, {}, {}, {}
local aListeners = {}

local function RCA()
    local RC = _G.Readycheck
    return RC and RC.Auras
end

local function FromData(a, i)
    return {
        name = a.name, icon = a.icon, count = a.applications or a.charges or 0,
        dispelType = a.dispelName, duration = a.duration or 0,
        expirationTime = a.expirationTime or 0, source = a.sourceUnit,
        spellId = a.spellId, index = i, instance = a.auraInstanceID,
    }
end

local function FromUnitAura(i, name, icon, count, dispelType, duration, expirationTime, source, _, _, spellId)
    if not name then return nil end
    return {
        name = name, icon = icon, count = count or 0, dispelType = dispelType,
        duration = duration or 0, expirationTime = expirationTime or 0,
        source = source, spellId = spellId, index = i,
    }
end

local function ReadList(getData, unitAura)
    local list, byId, byName = {}, {}, {}
    for i = 1, 40 do
        local e
        if getData then
            local a
            if foreverClient then
                local ok, r = pcall(getData, "player", i)
                a = ok and r or nil
            else
                a = getData("player", i)
            end
            if not a then break end
            -- WoW Forever may hide an aura in combat (secret values: no
            -- compare, no table key): it is left out, the rest still read
            if not (ns.AuraHidden and ns.AuraHidden(a)) then e = FromData(a, i) end
        else
            e = FromUnitAura(i, unitAura("player", i))
            if not e then break end
        end
        if e then
            list[#list + 1] = e
            if e.spellId and not byId[e.spellId] then byId[e.spellId] = e end
            if e.name and not byName[e.name] then byName[e.name] = e end
        end
    end
    return list, byId, byName
end

local function AurasFresh()
    if not aDirty then return end
    aDirty = false
    aVersion = aVersion + 1
    aBuffs, aBuffById, aBuffByName = ReadList(GetBuffData, UnitBuff)
    aDebuffs, aDebuffById, aDebuffByName = ReadList(GetDebuffData, UnitDebuff)
end

function Auras.Invalidate()
    aDirty = true
    local rc = RCA()
    if rc then rc:Invalidate() end
end

function Auras.Version()
    local rc = RCA()
    if rc then return rc:Version() end
    AurasFresh()
    return aVersion
end

function Auras.Buffs()
    local rc = RCA()
    if rc then return rc:Buffs() end
    AurasFresh()
    return aBuffs
end

function Auras.Debuffs()
    local rc = RCA()
    if rc then return rc:Debuffs() end
    AurasFresh()
    return aDebuffs
end

function Auras.Buff(id)
    if not id then return nil end
    local rc = RCA()
    if rc then return rc:Buff(id) end
    AurasFresh()
    return aBuffById[id]
end

function Auras.BuffNamed(n)
    if not n then return nil end
    local rc = RCA()
    if rc then return rc:BuffNamed(n) end
    AurasFresh()
    return aBuffByName[n]
end

function Auras.Debuff(id)
    if not id then return nil end
    local rc = RCA()
    if rc then return rc:Debuff(id) end
    AurasFresh()
    return aDebuffById[id]
end

function Auras.DebuffNamed(n)
    if not n then return nil end
    local rc = RCA()
    if rc then return rc:DebuffNamed(n) end
    AurasFresh()
    return aDebuffByName[n]
end

function Auras.On(key, fn) aListeners[key] = fn end

-- Marking stale is only a flag, here and in Readycheck's index (whose own
-- dispatcher marks it too; two marks before a read still mean one read),
-- so a ZacUI reader can never be handed a stale list and nothing is read
-- until someone asks. The notice only goes out when someone listens.
local AurasAnnounce = ns.Coalescer(function() Notify(aListeners) end, 0)

local auraFrame = CreateFrame("Frame")
auraFrame:RegisterUnitEvent("UNIT_AURA", "player")
auraFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
auraFrame:SetScript("OnEvent", function()
    aDirty = true
    local rc = RCA()
    if rc then rc:Invalidate() end
    if next(aListeners) then AurasAnnounce() end
end)

------------------------------------------------------------------------
-- ns.Misses - the player's own swings and abilities that the target
-- dodged, parried or blocked.
--   Misses.Want(key, on)       keep listening while any key wants it
--   Misses.On(key, fn)         fn(kind, destGUID, now, sub, spellId,
--                              isOffHand); also keeps it listening
--   Misses.Last(kind, guid)    time of the last miss of that kind on
--                              guid, or on any target when guid is nil
-- kind: "DODGE" | "PARRY" | "BLOCK". (A partial block on a hit counts;
-- the combat log reports it as a hit with a blocked amount.)
------------------------------------------------------------------------
local Misses = {}
ns.Misses = Misses
local mWant, mListeners = {}, {}
local mLastAny = {}           -- kind -> time
local mByGUID = {}            -- guid -> { kind -> time }
local playerGUID

local function MissRecord(kind, guid, sub, spellId, offHand)
    local now = GetTime()
    mLastAny[kind] = now
    if guid then
        local t = mByGUID[guid]
        if not t then t = {}; mByGUID[guid] = t end
        t[kind] = now
    end
    Notify(mListeners, kind, guid, now, sub, spellId, offHand)
end

local KINDS = { DODGE = true, PARRY = true, BLOCK = true }

local function MissCLEU(_, sub, _, srcGUID, _, _, _, destGUID, _, _, _, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21)
    if srcGUID ~= playerGUID then return end
    if sub == "SWING_MISSED" then
        -- missType, isOffHand, amountMissed
        if KINDS[a12] then MissRecord(a12, destGUID, sub, nil, a13) end
    elseif sub == "SPELL_MISSED" then
        -- spellId, spellName, spellSchool, missType, isOffHand
        if KINDS[a15] then MissRecord(a15, destGUID, sub, a12, a16) end
    elseif sub == "SWING_DAMAGE" then
        -- amount, overkill, school, resisted, blocked(16), ...
        if a16 and a16 > 0 then MissRecord("BLOCK", destGUID, sub, nil, a21) end
    elseif sub == "SPELL_DAMAGE" then
        -- spellId, name, school, amount, overkill, school, resisted, blocked(19)
        if a19 and a19 > 0 then MissRecord("BLOCK", destGUID, sub, a12, nil) end
    end
end

local function MissesSync()
    local want = next(mWant) ~= nil or next(mListeners) ~= nil
    if want then
        playerGUID = playerGUID or UnitGUID("player")
        if not CLEU.Has("ZacUI.Misses") then
            CLEU.On("ZacUI.Misses", { "SWING_MISSED", "SPELL_MISSED", "SWING_DAMAGE", "SPELL_DAMAGE" }, MissCLEU)
        end
    elseif CLEU.Has("ZacUI.Misses") then
        CLEU.Off("ZacUI.Misses")
    end
end

function Misses.Want(key, on)
    mWant[key] = on and true or nil
    MissesSync()
end

function Misses.On(key, fn)
    mListeners[key] = fn
    MissesSync()
end

function Misses.Last(kind, guid)
    if guid then
        local t = mByGUID[guid]
        return t and t[kind]
    end
    return mLastAny[kind]
end

-- per-target memory only matters during a fight
local missFrame = CreateFrame("Frame")
missFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
missFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
missFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then playerGUID = UnitGUID("player") end
    wipe(mByGUID)
end)

------------------------------------------------------------------------
-- ns.Overpower - THE Overpower window, one answer for the warrior HUD's
-- buff bar and the plate row. They used to keep two: the buff bar timed
-- the last dodge from ANY mob, the plate row only the target's (with its
-- clock started late), so the two showed different timers on trash.
--   Overpower.Left(guid)   seconds left on that mob (default: your
--                          attackable target); 0 when shut
-- Opened for 5s by a dodge of YOUR swing or ability on that exact mob
-- (ns.Misses, by GUID); shut early once you Overpower that mob. In
-- Battle Stance the game's own button state must agree too, so a window
-- the game has closed never lingers. Warriors only; the dodge feed runs
-- only while you are in combat, and a read is two table lookups.
------------------------------------------------------------------------
local Overpower = {}
ns.Overpower = Overpower
local OP_WINDOW = 5
local opName, opIds              -- Overpower's (localised) name; its rank ids
local opSpent = {}               -- guid -> GetTime() you last Overpowered it

-- WoW Forever gives addons no combat log, so no dodge is seen there (nor
-- under the game-version override's Forever). There the window is the
-- game's own Overpower button: in Battle Stance it lights only after a
-- dodge, so it opens when the button lights (read 5 times a second in
-- combat, warriors only) and runs 5s from then, on the target you had;
-- it shuts the moment the button goes dark. Other stances cannot tell.
local opNoLog                    -- set at login: true where there is no combat log
local opLit = { at = nil, guid = nil, lit = false }
local opPoll
local function OPButton()
    local lit = false
    if opName and GetShapeshiftForm() == 1 then
        local usable, noPower = IsUsableSpell(opName)
        lit = (usable or noPower) and true or false
    end
    if lit and not opLit.lit then
        opLit.at = GetTime()
        opLit.guid = UnitExists("target") and ns.SafeGUID("target") or nil
    elseif not lit then
        opLit.at, opLit.guid = nil, nil
    end
    opLit.lit = lit
end
local function OPPoll(on)
    if on and not opPoll then
        opPoll = C_Timer.NewTicker(0.2, OPButton)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(opPoll, "core.overpower") end
        OPButton()
    elseif not on and opPoll then
        opPoll:Cancel()
        opPoll = nil
        opLit.at, opLit.guid, opLit.lit = nil, nil, false
    end
end
Overpower._Button = OPButton     -- (tests)

local function LeftFromButton(guid)
    if not opLit.at then return 0 end
    if not guid then
        if not (UnitExists("target") and UnitCanAttack("player", "target")) then return 0 end
        guid = ns.SafeGUID("target")
    end
    if opLit.guid and guid ~= opLit.guid then return 0 end
    local left = opLit.at + OP_WINDOW - GetTime()
    return left > 0 and left or 0
end

function Overpower.Left(guid)
    if not opName then return 0 end
    if opNoLog then return LeftFromButton(guid) end
    if not guid then
        if not (UnitExists("target") and UnitCanAttack("player", "target")) then return 0 end
        guid = ns.SafeGUID("target")
        if not guid then return 0 end
    end
    local t = mByGUID[guid]
    local at = t and t.DODGE
    if not at then return 0 end
    local spent = opSpent[guid]
    if spent and spent >= at then return 0 end
    local now = GetTime()
    local left = at + OP_WINDOW - now
    if left <= 0 then return 0 end
    -- Battle Stance: the button is the game's word on it (it goes dark
    -- the moment the window is spent). A moment's grace after the dodge,
    -- while the client catches up.
    if now - at > 0.3 and GetShapeshiftForm() == 1 then
        local usable, noPower = IsUsableSpell(opName)
        if not (usable or noPower) then return 0 end
    end
    return left
end

local opFrame = CreateFrame("Frame")
local function OPResolve()
    local name = GetSpellInfo and GetSpellInfo(7384)
    opName = name
    opIds = {}
    if name then
        for _, id in ipairs({ 7384, 7887, 11584, 11585 }) do opIds[id] = true end
    end
end
opFrame:SetScript("OnEvent", function(_, event, unit, _, spellId)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if opIds and (opIds[spellId] or (opName and GetSpellInfo(spellId) == opName)) then
            local g = UnitExists("target") and ns.SafeGUID("target")
            if g then opSpent[g] = GetTime() end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if opNoLog then OPPoll(true) return end
        Misses.Want("ZacUI.Overpower", true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if opNoLog then OPPoll(false) return end
        Misses.Want("ZacUI.Overpower", false)
        wipe(opSpent)
    elseif event == "SPELLS_CHANGED" then
        OPResolve()
    elseif event == "PLAYER_LOGIN" then
        opFrame:UnregisterEvent("PLAYER_LOGIN")
        if select(2, UnitClass("player")) ~= "WARRIOR" then return end   -- warriors only
        opNoLog = (_G.ZACUI_MODERN or (ns.NoCombatLog and ns.NoCombatLog())) and true or false
        OPResolve()
        opFrame:RegisterEvent("SPELLS_CHANGED")
        opFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        opFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        opFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        if UnitAffectingCombat("player") then
            if opNoLog then OPPoll(true) else Misses.Want("ZacUI.Overpower", true) end
        end
    end
end)
opFrame:RegisterEvent("PLAYER_LOGIN")

------------------------------------------------------------------------
-- ns.Macros - macro names, walked once per change.
--   Macros.FindAll(name)   array of indexes with that exact name
--                          (account first, then character), or nil
--   Macros.Find(name)      the first of those, or nil
--   Macros.Names()         index -> name for every macro
--   Macros.Version()
-- Bodies and icons are NOT cached (read them with GetMacroInfo when
-- needed); only the name -> index map is.
------------------------------------------------------------------------
local Macros = {}
ns.Macros = Macros
local mcDirty, mcVersion = true, 0
local mcByName, mcNames = {}, {}

local function MacrosFresh()
    if not mcDirty then return end
    mcDirty = false
    mcVersion = mcVersion + 1
    mcByName, mcNames = {}, {}
    local numAcct, numChar = GetNumMacros()
    local acctMax = MAX_ACCOUNT_MACROS or 120
    local function add(i)
        local name = GetMacroInfo(i)
        if name then
            mcNames[i] = name
            local l = mcByName[name]
            if not l then l = {}; mcByName[name] = l end
            l[#l + 1] = i
        end
    end
    for i = 1, numAcct or 0 do add(i) end
    for i = acctMax + 1, acctMax + (numChar or 0) do add(i) end
end

function Macros.FindAll(name) MacrosFresh() return name and mcByName[name] end
function Macros.Find(name)
    MacrosFresh()
    local l = name and mcByName[name]
    return l and l[1]
end
function Macros.Names() MacrosFresh() return mcNames end
function Macros.Version() MacrosFresh() return mcVersion end
function Macros.Invalidate() mcDirty = true end

------------------------------------------------------------------------
-- ns.ActionSlots - what each of the 120 action slots holds.
--   ActionSlots.Find(kind, id)   array of slots holding it, or nil
--                                (kind: "spell", "item", "macro", ...)
--   ActionSlots.At(slot)         kind, id, subType
--   ActionSlots.Version()
------------------------------------------------------------------------
local ActionSlots = {}
ns.ActionSlots = ActionSlots
local asDirty, asVersion = true, 0
local asKind, asId, asSub, asFind = {}, {}, {}, {}

local function SlotsFresh()
    if not asDirty then return end
    asDirty = false
    asVersion = asVersion + 1
    asKind, asId, asSub, asFind = {}, {}, {}, {}
    for slot = 1, 120 do
        local kind, id, sub = GetActionInfo(slot)
        if kind then
            asKind[slot], asId[slot], asSub[slot] = kind, id, sub
            local byKind = asFind[kind]
            if not byKind then byKind = {}; asFind[kind] = byKind end
            local l = byKind[id]
            if not l then l = {}; byKind[id] = l end
            l[#l + 1] = slot
        end
    end
end

function ActionSlots.Find(kind, id)
    SlotsFresh()
    local byKind = asFind[kind]
    return byKind and byKind[id]
end
function ActionSlots.At(slot) SlotsFresh() return asKind[slot], asId[slot], asSub[slot] end
function ActionSlots.Version() SlotsFresh() return asVersion end
function ActionSlots.Invalidate() asDirty = true end

local slotFrame = CreateFrame("Frame")
slotFrame:RegisterEvent("UPDATE_MACROS")
slotFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
slotFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
slotFrame:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_MACROS" then
        mcDirty = true
        asDirty = true          -- a macro's id on a slot is its index
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        asDirty = true
    else
        mcDirty, asDirty = true, true
    end
end)

------------------------------------------------------------------------
-- Item quality and money - one copy for every part (the bags, the
-- auction house and the windows each carried their own).
--   ns.QualityRGB(quality)   r, g, b of an item quality; nil or unknown
--                            -> the theme's text colour
--   ns.Money(c)              Blizzard's coin string (tooltips, footers)
--   ns.Money(c, true)        compact coloured "12g 34s" for dense tables
--   ns.Money(c, "gold")      whole gold with separators and one coin
--                            icon, for a five-figure account total
------------------------------------------------------------------------
local QUALITY = _G.ITEM_QUALITY_COLORS
function ns.QualityRGB(quality)
    local q = quality and QUALITY and QUALITY[quality]
    if q then return q.r, q.g, q.b end
    local c = ns.Col("text")
    return c.r, c.g, c.b
end

local floor, format = math.floor, string.format
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
function ns.Money(copper, mode)
    copper = floor(copper or 0)
    if not mode then
        if GetCoinTextureString then return GetCoinTextureString(copper) end
        if GetCoinText then return GetCoinText(copper) end
    end
    local g = floor(copper / 10000)
    if mode == "gold" then
        local s = tostring(g)
        while true do
            local new, n = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
            s = new
            if n == 0 then break end
        end
        return s .. GOLD_ICON
    end
    local sv = floor((copper % 10000) / 100)
    local c = copper % 100
    if mode then
        if g > 0 then return format("|cffffd700%d|rg %d|cffc7c7c7s|r", g, sv) end
        if sv > 0 then return format("%d|cffc7c7c7s|r %d|cffeda55fc|r", sv, c) end
        return format("%d|cffeda55fc|r", c)
    end
    return format("%dg %ds %dc", g, sv, c)
end

-- ============================================================
-- THE VOICE (2026-10-28 settings tidy). Every part of ZacUI that speaks
-- - the shout alert and low-health warning, the threat callout, the raid
-- mods, Hesitation Alerts, the Sapper call - speaks in ONE voice, picked
-- once on the General page. Saved by name in ZacUIDB.voice, so it
-- follows you between machines; "auto" (nothing saved) is the voice
-- Readycheck speaks with (its saved pick), else voice 0 when installed,
-- else the first voice whose name reads female, else the first voice.
-- Volume and rate stay with each part: the raid packs pass their own
-- level per line.
-- ============================================================
local VOICE_HINTS = { "female", "samantha", "victoria", "karen", "moira", "fiona",
                      "zira", "hazel", "susan", "julie", "kate", "emily", "siri" }
local voiceCache, voiceCacheAt
function ns.Voices()
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local ok, v = pcall(C_VoiceChat.GetTtsVoices)
        if ok and type(v) == "table" then return v end
    end
    return {}
end
function ns.VoiceCfg()
    if type(ZacUIDB) ~= "table" then return {} end
    local v = ZacUIDB.voice
    if type(v) ~= "table" then
        v = {}
        ZacUIDB.voice = v
        -- first run: the pick a part had made on its own becomes the one
        local uf = ZacUIDB.unitframes
        local ufName = type(uf) == "table" and type(uf.tts) == "table" and uf.tts.voice
        if type(ufName) == "string" and ufName ~= "" and ufName ~= "auto" then v.name = ufName end
        local rm = ZacUIDB.raidmods
        if not v.name and type(rm) == "table" and type(rm.voice) == "number" then
            for _, x in ipairs(ns.Voices()) do
                if x.voiceID == rm.voice then v.name = x.name break end
            end
        end
    end
    return v
end
local function AutoVoice(voices)
    local function Has(id)
        for _, x in ipairs(voices) do if x.voiceID == id then return true end end
    end
    local RC = _G.Readycheck
    local want = RC and RC.db and RC.db.consumablesHelper and RC.db.consumablesHelper.ttsVoiceId
    if type(want) == "number" and Has(want) then return want end
    if Has(0) then return 0 end
    for _, x in ipairs(voices) do
        local n = (x.name or ""):lower()
        for _, h in ipairs(VOICE_HINTS) do
            if n:find(h, 1, true) then return x.voiceID end
        end
    end
    return (voices[1] and voices[1].voiceID) or 0
end
function ns.VoiceId()
    local now = GetTime()
    if voiceCache and voiceCacheAt and now - voiceCacheAt < 30 then return voiceCache end
    local voices = ns.Voices()
    local name = ns.VoiceCfg().name
    local id
    if name then
        for _, x in ipairs(voices) do
            if x.name == name then id = x.voiceID break end
        end
    end
    id = id or AutoVoice(voices)
    voiceCache, voiceCacheAt = id, now
    return id
end
function ns.VoiceName(id)
    for _, x in ipairs(ns.Voices()) do if x.voiceID == id then return x.name end end
    return "voice " .. tostring(id)
end
function ns.SetVoice(name)
    ns.VoiceCfg().name = (name ~= "auto" and name) or nil
    voiceCache = nil
    if ns.RaidMods and ns.RaidMods.ForgetVoice then ns.RaidMods.ForgetVoice() end
end
do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "VOICE_CHAT_TTS_PLAYBACK_FAILED")
    f:SetScript("OnEvent", function() voiceCache = nil end)
end
-- the General page's card
function ns.VoiceCard(L)
    local UI = ns.UI
    if not (UI and UI.Dropdown and UI.Button) then return end
    local voices = ns.Voices()
    L:Card("Voice")
    if #voices == 0 then
        L:Desc("No text-to-speech voices are installed on this system.")
        L:EndCard()
        return
    end
    local AUTO = "auto"
    local dd = UI.Dropdown(L.current, { width = 260,
        items = function()
            local items = { { text = "Automatic (" .. ns.VoiceName(AutoVoice(voices)) .. ")", value = AUTO } }
            for _, x in ipairs(voices) do items[#items + 1] = { text = x.name, value = x.name } end
            return items
        end,
        selected = function()
            local n = ns.VoiceCfg().name
            return n or ("Automatic (" .. ns.VoiceName(AutoVoice(voices)) .. ")")
        end,
        onSelect = function(v)
            ns.SetVoice(v)
            if C_VoiceChat and C_VoiceChat.SpeakText then
                pcall(C_VoiceChat.SpeakText, ns.VoiceId(), "Testing voice", 0, 100, 1)
            end
            if ns.RefreshConfig then ns.RefreshConfig() end
        end })
    L:Row(dd, 26)
    local test = UI.Button(L.current, "Test", { width = 80, onClick = function()
        if C_VoiceChat and C_VoiceChat.SpeakText then
            pcall(C_VoiceChat.SpeakText, ns.VoiceId(), "Testing voice", 0, 100, 1)
        end
    end })
    L:Row(test, (UI.M and UI.M.BUTTON_H or 20) + 4)
    L:Desc("One voice for everything ZacUI says: the shout alert and low-health warning, "
        .. "the threat callout, the raid mods, Hesitation Alerts and the Sapper call. "
        .. "Automatic is the voice Readycheck speaks with. Saved by name, so it follows you between machines.")
    L:EndCard()
end
