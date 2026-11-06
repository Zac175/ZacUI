-- RM_Core - ZacUI Raid Mods: the engine under the raid packs.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT THIS IS
-- Boss mods the way DBM has them: timers, warnings, icons, lists, marks
-- on raid frames and nameplates, driven by the combat log and encounter
-- events, as addon code - not auras. Each raid (MC, BWL, ZG, AQ40,
-- Naxxramas) is a module under Own\ holding UNITS - small pieces with a
-- load rule (zone,
-- encounter, class, role), the events they listen to, an init block,
-- triggers that write STATES, and a display spec the widget layer
-- (RM_Widgets) draws in one of the ANCHORS (RM_Anchors).
--
-- THE STATE MODEL
-- A trigger keeps a table of states keyed by a clone id ("" for a single
-- thing, a GUID or a unit token for one-per-target). A state is a plain
-- table { show, changed, name, icon, duration, expirationTime,
-- progressType, count, unit, guid, ... }. Triggers write states and
-- report a change; the engine combines a unit's triggers (any / all),
-- runs the unit's actions as states appear and go, and hands the live
-- set to the widgets. Every raid module is written against that
-- contract (see RM_Own.lua for how a module is put together).
--
-- TRIGGER KINDS. custom "stateupdate" (writes the states table), custom
-- "status" (returns show), custom "event" (returns true to show for a
-- duration); "aura" (declarative buff/debuff watch on player, group,
-- target or nameplate units - RM_Triggers scans), "combatlog"
-- (declarative CLEU filter), "chat" (CHAT_MSG_* match), "item" and
-- "unit" checks.
--
-- EVENTS. One frame registers every game event a loaded unit needs, as
-- it needs it. The combat log comes from ZacUI's one reader (ns.CLEU),
-- asked only for the sub-events a loaded unit listens to, and is handed
-- out by sub-event: a unit with no listener for that sub-event costs
-- nothing. The group comes from ns.Roster. Custom events - the packs'
-- own bus, "WA_NUMEN_TIMER" and friends - go through RM.Fire, which is
-- what the ported code calls where it called WeakAuras.ScanEvents.
--
-- PERF LAWS. No OnUpdate anywhere; bars tick from one shared ticker in
-- RM_Widgets. The aura scanner marks units dirty on UNIT_AURA and scans
-- from a 0.2 s ticker, never inline. Dispatch allocates nothing.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
-- Classic Era raids only: on TBC and Forever (or the override's) the part
-- stands down here, before it makes a frame. Every later file of the part
-- needs ns.RaidMods and returns at once without it (Core_Flavor).
if ns.PartOff and ns.PartOff("Zacui_RaidMods") then return end

local RM = ns.RaidMods or {}
ns.RaidMods = RM

local Print = ns.Print or function(m) print("|cff33ff99ZacUI|r " .. tostring(m)) end
RM.Print = Print

-- ZacUI's shared services (Core_Services): the one combat-log reader,
-- the group, and the player's own auras
local CLEUBus, Roster = ns.CLEU, ns.Roster

-- API compat (Interface 11509 / 20506)
local GetSpellInfo_C = GetSpellInfo or (C_Spell and function(spell)
    local info = C_Spell.GetSpellInfo(spell)
    if not info then return nil end
    return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
end)
local UnitAura_C = UnitAura or (C_UnitAuras and function(unit, index, filter)
    local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
    if not a then return nil end
    return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime,
        a.sourceUnit, a.isStealable, a.nameplateShowPersonal, a.spellId
end)
RM.GetSpellInfo = GetSpellInfo_C
RM.UnitAura = UnitAura_C

-- ============================================================
-- SETTINGS - ZacUIDB.raidmods
-- ============================================================
local DEFAULTS = {
    enabled = true,
    raids = {},            -- [raidKey] = false switches a whole raid off (nil = on)
    units = {},            -- [unitId] = true/false overrides the unit's shipped default
    sounds = true,
    chat = true,           -- the packs' /say /yell /raid messages
    config = {},           -- [unitId] = { option = value } the player changed from the pack's defaults
    scale = 1,
    testMode = false,
    testRaid = nil,        -- the raid the preview shows
    barTexture = "ZacUI Flat",  -- every bar (SharedMedia name)
    font = nil,            -- nil = each text keeps the pack's font (Barlow); a SharedMedia name overrides them all
    fontFromZacUI = false, -- let the Fonts & Textures page push ZacUI's font here too (the bar texture always follows)
    voice = nil,           -- TTS voice id; nil = the same voice Readycheck speaks with
    lists = false,         -- the packs' name lists (Mortal Wound List and the like); off for every raid unless turned on
    berserkOff = { WARRIOR = true }, -- [class] = true: no berserk timers / warnings for that class, any boss
}
local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
local dbCache
function RM.DB()
    if type(ZacUIDB) ~= "table" then return nil end
    if type(ZacUIDB.raidmods) ~= "table" then ZacUIDB.raidmods = {} end
    if dbCache ~= ZacUIDB.raidmods then
        CopyDefaults(DEFAULTS, ZacUIDB.raidmods)
        dbCache = ZacUIDB.raidmods
    end
    return ZacUIDB.raidmods
end
RM.DEFAULTS = DEFAULTS

-- ============================================================
-- THE VOICE
-- ============================================================
-- The packs speak through C_VoiceChat.SpeakText with a voice id of their
-- own choosing (a global, or a hard-coded 1). The engine hands them a
-- C_VoiceChat of its own (RM.VoiceChat, bound in every module) whose
-- SpeakText swaps in ONE voice: the one picked on the Raid mods page,
-- or - by default - the voice Readycheck speaks with, found the way
-- Readycheck finds it: its saved voice id, else voice 0 when installed,
-- else the first voice whose name reads female.
local FEMALE_HINTS = { "female", "samantha", "victoria", "karen", "moira", "fiona", "zira", "hazel", "susan", "julie", "kate", "emily", "siri" }
local voiceCache, voiceCacheAt
local function Voices()
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local ok, v = pcall(C_VoiceChat.GetTtsVoices)
        if ok and type(v) == "table" then return v end
    end
    return {}
end
local function Installed(voices, id)
    for _, v in ipairs(voices) do if v.voiceID == id then return true end end
    return false
end
function RM.VoiceId()
    -- ZacUI's one voice (General page, 2026-10-28); the raid mods' own
    -- pick moved into it the first time it was read (ns.VoiceCfg)
    if ns.VoiceId then
        if ns.VoiceCfg then ns.VoiceCfg() end
        local db = RM.DB()
        if db then db.voice = nil end
        return ns.VoiceId()
    end
    local now = GetTime()
    if voiceCache and voiceCacheAt and now - voiceCacheAt < 30 then return voiceCache end
    local db = RM.DB()
    local voices = Voices()
    local id
    if db and type(db.voice) == "number" and Installed(voices, db.voice) then id = db.voice end
    if not id then
        -- Readycheck's saved choice, when it has one
        local RC = _G.Readycheck
        local want = RC and RC.db and RC.db.consumablesHelper and RC.db.consumablesHelper.ttsVoiceId
        if type(want) == "number" and Installed(voices, want) then id = want end
    end
    if not id and Installed(voices, 0) then id = 0 end
    if not id then
        for _, v in ipairs(voices) do
            local lower = (v.name or ""):lower()
            for _, hint in ipairs(FEMALE_HINTS) do
                if lower:find(hint, 1, true) then id = v.voiceID break end
            end
            if id then break end
        end
    end
    if not id then id = (voices[1] and voices[1].voiceID) or 0 end
    voiceCache, voiceCacheAt = id, now
    return id
end
function RM.ForgetVoice() voiceCache = nil end

local lastSpoken, lastSpokenAt = nil, 0
function RM.Speak(text, volume, rate)
    local db = RM.DB()
    if not (db and db.sounds) then return end
    if not (C_VoiceChat and C_VoiceChat.SpeakText) or type(text) ~= "string" or text == "" then return end
    text = text:gsub("|T.-|t", " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+", " ")
    local now = GetTime()
    -- the same line twice within a second is one line
    if text == lastSpoken and now - lastSpokenAt < 1 then return end
    lastSpoken, lastSpokenAt = text, now
    local F = ns.RaidTools and ns.RaidTools.Settings and ns.RaidTools.Settings() or nil
    local vol = tonumber(volume) or (F and F.ttsVolume) or 75
    if vol > 100 then vol = 100 end
    local r = tonumber(rate) or (F and F.ttsRate) or 1
    pcall(C_VoiceChat.SpeakText, RM.VoiceId(), text, 0, vol, r)
end
-- A sound from the packs' settings: "tts:Move out" is spoken (through the
-- line above, so "Sounds and voice" and the speech settings apply), "ui:Pop"
-- is one of the game's own sounds, an old pack path is read for what it
-- was (Zacui\Core\Core_Sounds.lua). Returns played, handle.
function RM.RaidSound(ref, channel)
    if not ns.RaidSound then return false end
    return ns.RaidSound(ref, channel or "Master", RM.Speak)
end

-- what the modules see as C_VoiceChat
RM.VoiceChat = setmetatable({
    SpeakText = function(voice, text, dest, volume, rate)
        return RM.Speak(text, volume, rate)
    end,
}, { __index = function(_, k) return C_VoiceChat and C_VoiceChat[k] end })

-- The packs read their speech settings from three globals (a "TTS
-- Settings" aura used to set them). Zacui_RaidTools owns the volume and
-- rate (ns.RaidTools.Settings / ApplySpeech); the engine owns the voice,
-- mutes everything when its sounds are off, and mirrors the values onto
-- the second set of names the newer packs read.
function RM.ApplyTTSGlobals()
    local db = RM.DB()
    if not db then return end
    local F = ns.RaidTools
    if F and F.ApplySpeech then F.ApplySpeech() end
    if _G.FJITTS_SFX_VOLUME == nil then _G.FJITTS_SFX_VOLUME = 75 end
    if _G.FJITTS_SFX_RATE == nil then _G.FJITTS_SFX_RATE = 1.8 end
    _G.FJITTS_SFX_VOICEID = RM.VoiceId()
    if not db.sounds then _G.FJITTS_SFX_VOLUME = 0 end
    _G.FJIDS_SFX_VOICEID = _G.FJITTS_SFX_VOICEID
    _G.FJIDS_SFX_RATE = _G.FJITTS_SFX_RATE
    _G.FJIDS_SFX_VOLUME = _G.FJITTS_SFX_VOLUME
end

-- ============================================================
-- REGISTRY
-- ============================================================
RM.raids = {}        -- key -> { key, name, zone, encounters = { [id] = name }, bosses = { {key, name, enc} }, timers = { KEY = {...} } }
RM.raidOrder = {}
RM.units = {}        -- id -> definition
RM.unitOrder = {}
RM.byRaid = {}       -- raidKey -> { ids }
RM.groups = {}       -- key -> layout group definition (RM_Anchors lays them out)
RM.groupOrder = {}

function RM.Raid(def)
    if type(def) ~= "table" or type(def.key) ~= "string" then return end
    def.encounters = def.encounters or {}
    def.bosses = def.bosses or {}
    def.timers = def.timers or {}
    if not RM.raids[def.key] then RM.raidOrder[#RM.raidOrder + 1] = def.key end
    RM.raids[def.key] = def
    RM.byRaid[def.key] = RM.byRaid[def.key] or {}
    return def
end

-- One unit from a module file. A bad one is reported and skipped rather
-- than taking the raid with it.
RM.MOVE_FONT = 20

-- Reminders that only matter between fights: kept unloaded in combat and
-- loaded again when it ends, so they look again then (the Onyxia Scale
-- Cloak reminders would otherwise sit on screen for a whole drake fight).
local OUT_OF_COMBAT = { "Onyxia Scale Cloak" }
local function OutOfCombatOnly(def)
    if def._oocOnly == nil then
        def._oocOnly = false
        if type(def.group) == "string" and def.group:find(": Character", 1, true) then
            for _, s in ipairs(OUT_OF_COMBAT) do
                if def.id:find(s, 1, true) then def._oocOnly = true break end
            end
        end
    end
    return def._oocOnly
end

function RM.Unit(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or type(def.raid) ~= "string" then return end
    if RM.units[def.id] then
        Print("Raid Mods: '" .. def.id .. "' is defined twice; keeping the first.")
        return
    end
    def.load = def.load or {}
    def.triggers = def.triggers or {}
    def.kind = def.kind or "none"
    -- The packs' "%i MOVE %i" alerts (GTFO and the like) come at 28-34
    -- with an icon the same size each side, which covers the middle of
    -- the screen. They are drawn at MOVE_FONT at most.
    local D = def.display
    if def.kind == "text" and type(D) == "table" and type(D.displayText) == "string"
            and D.displayText:find("MOVE", 1, true) and (tonumber(D.fontSize) or 0) > RM.MOVE_FONT then
        D.fontSize = RM.MOVE_FONT
    end
    RM.units[def.id] = def
    RM.unitOrder[#RM.unitOrder + 1] = def.id
    RM.byRaid[def.raid] = RM.byRaid[def.raid] or {}
    table.insert(RM.byRaid[def.raid], def.id)
    return def
end
RM.U = RM.Unit

-- A layout group from a module: the pack's dynamic or static group, with
-- the engine anchor it hangs on (or its own screen position).
function RM.Group(def)
    if type(def) ~= "table" or type(def.key) ~= "string" then return end
    if RM.groups[def.key] then return RM.groups[def.key] end
    RM.groups[def.key] = def
    RM.groupOrder[#RM.groupOrder + 1] = def.key
    return def
end

-- ============================================================
-- PLAYER FACTS AND HELPERS THE PORTED CODE CALLS
-- ============================================================
RM.myGUID = UnitGUID and UnitGUID("player") or ""
RM.me = UnitName and UnitName("player") or ""
local _, playerClass = UnitClass("player")
RM.playerClass = playerClass or ""

-- the packs' own idea of a role: four globals their "Role" helper aura
-- set from class and talents. The engine sets them now, the same way.
local function HasSpell(id) return IsPlayerSpell and IsPlayerSpell(id) or false end
function RM.UpdateRole()
    _G.FJI_HEALER, _G.FJI_TANK, _G.FJI_MELEE, _G.FJI_RANGED = nil, nil, nil, nil
    local c = RM.playerClass
    if c == "DRUID" then
        if HasSpell(18562) then _G.FJI_HEALER = true
        elseif HasSpell(24858) then _G.FJI_RANGED = true
        elseif HasSpell(16933) or HasSpell(16930) or HasSpell(16932) or HasSpell(16929) or HasSpell(16931) then _G.FJI_TANK = true
        else _G.FJI_MELEE = true end
    elseif c == "HUNTER" or c == "MAGE" or c == "WARLOCK" then _G.FJI_RANGED = true
    elseif c == "PALADIN" then
        if HasSpell(20930) then _G.FJI_HEALER = true else _G.FJI_MELEE = true end
    elseif c == "PRIEST" then
        if HasSpell(15473) then _G.FJI_RANGED = true else _G.FJI_HEALER = true end
    elseif c == "ROGUE" then _G.FJI_MELEE = true
    elseif c == "SHAMAN" then
        if HasSpell(16190) then _G.FJI_HEALER = true
        elseif HasSpell(16166) then _G.FJI_RANGED = true
        else _G.FJI_MELEE = true end
    elseif c == "WARRIOR" then
        if HasSpell(12975) then _G.FJI_TANK = true else _G.FJI_MELEE = true end
    end
end
RM.UpdateRole()
function RM.PlayerRole()
    if _G.FJI_TANK then return "TANK" end
    if _G.FJI_HEALER then return "HEALER" end
    if _G.FJI_RANGED then return "RANGED" end
    if _G.FJI_MELEE then return "MELEE" end
    return nil
end

-- WA_IterateGroupMembers: raid1..N in a raid; party1..N then player in a
-- party; player alone.
function RM.IterateGroup(reversed, forceParty)
    local unit = (not forceParty and IsInRaid()) and "raid" or "party"
    local n = unit == "party" and GetNumSubgroupMembers() or GetNumGroupMembers()
    local i = reversed and n or (unit == "party" and 0 or 1)
    return function()
        local ret
        if i == 0 and unit == "party" then
            ret = "player"
        elseif i <= n and i > 0 then
            ret = unit .. i
        end
        i = i + (reversed and -1 or 1)
        return ret
    end
end

-- a spell id's name, looked up once (an aura is matched by id or by name)
local spellNames = {}
local function SpellNameOf(id)
    local n = spellNames[id]
    if n == nil then
        n = GetSpellInfo_C and GetSpellInfo_C(id) or false
        spellNames[id] = n
    end
    return n or nil
end
local function AuraByName(unit, spell, filter)
    if not unit or not spell then return nil end
    local wantId = type(spell) == "number" and spell or nil
    local wantName = type(spell) == "string" and spell or nil
    if wantId and not wantName then wantName = SpellNameOf(wantId) end
    for i = 1, 40 do
        local name, icon, count, dispel, duration, expires, caster, stealable, nameplate, id = UnitAura_C(unit, i, filter)
        if not name then break end
        if (wantId and id == wantId) or (wantName and name == wantName) then
            return name, icon, count, dispel, duration, expires, caster, stealable, nameplate, id
        end
    end
    return nil
end
function RM.GetUnitBuff(unit, spell, filter) return AuraByName(unit, spell, filter or "HELPFUL") end
function RM.GetUnitDebuff(unit, spell, filter) return AuraByName(unit, spell, filter or "HARMFUL") end
function RM.GetData(id) return RM.units[id] end
function RM.IsOptionsOpen() local db = RM.DB() return db and db.testMode or false end

local LRC = LibStub and LibStub("LibRangeCheck-3.0", true)
function RM.GetRange(unit)
    if LRC then return LRC:GetRange(unit) end
    return nil
end
function RM.CheckRange(unit, range, op)
    local min, max = RM.GetRange(unit)
    if not min then return nil end
    local v = (op == ">=" or op == ">") and min or (max or min)
    if op == "<=" then return v <= range end
    if op == ">=" then return v >= range end
    if op == "<" then return v < range end
    if op == ">" then return v > range end
    return nil
end
function RM.Utf8Sub(s, i, j) return string.utf8sub and string.utf8sub(s, i, j) or string.sub(s, i, j) end
function RM.GetUnitAura(unit, spell, filter) return AuraByName(unit, spell, filter or "HELPFUL") end
function RM.ClassColorName(unit)
    local name = UnitName(unit)
    if not name then return "" end
    local _, class = UnitClass(unit)
    local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    if c then return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) end
    return name
end

-- What the ported code sees as "WeakAuras": the handful of calls the
-- packs make, answered by the engine.
RM.WA = {
    ScanEvents = function(...) return RM.Fire(...) end,
    GetData = function(id) return RM.GetData(id) end,
    IsOptionsOpen = function() return RM.IsOptionsOpen() end,
    GetRange = function(unit) return RM.GetRange(unit) end,
    CheckRange = function(unit, range, op) return RM.CheckRange(unit, range, op) end,
    myGUID = RM.myGUID,
    me = RM.me,
    ScanUnitEvents = function(event, unit, ...) return RM.Fire(event, unit, ...) end,
    GetActiveTriggers = function() return {} end,
}

local guidNames = {}       -- names of players outside the group, as asked for
function RM.NameForGUID(guid)
    if type(guid) ~= "string" then return nil end
    if guid == RM.myGUID then return RM.me end
    local u = Roster.UnitOf(guid)
    if u then
        local un = UnitName(u)
        if un then return un end
    end
    local n = guidNames[guid]
    if n then return n end
    if GetPlayerInfoByGUID then
        local _, _, _, _, _, name = GetPlayerInfoByGUID(guid)
        if name then guidNames[guid] = name return name end
    end
    return nil
end

-- ============================================================
-- EVENT BUS
-- ============================================================
-- listeners[event] = { {inst, tindex}, ... }. "CLEU:<SUBEVENT>" for the
-- combat log. Names that look like game events but are the engine's own
-- are never registered on the frame.
local listeners = {}
local cleuListeners = {}   -- [subevent] = the same list as listeners["CLEU:" .. subevent]
local gameEvents = {}
local frame = CreateFrame("Frame", "ZacUIRaidModsFrame", UIParent)
RM.frame = frame
RM.CUSTOM_EVENTS = { OPTIONS = true, STATUS = true, WA_DELAYED_PLAYER_ENTERING_WORLD = true, WA_FJI_ENCOUNTER_END = true }

-- Unit events a custom trigger may ask for arrive 10-20+ times a second
-- in a raid, for every unit. They are never handed to trigger code
-- inline: the unit is noted and one short timer delivers each (event,
-- unit) pair once. Everything else still goes straight through.
local COALESCED = { UNIT_AURA = true, UNIT_HEALTH = true, UNIT_HEALTH_FREQUENT = true,
    UNIT_POWER_UPDATE = true, UNIT_POWER_FREQUENT = true, UNIT_MAXHEALTH = true }

-- "UNIT_AURA:target" (the WeakAuras form) means the event only for that
-- unit token; "nameplate" means any nameplate unit. The base event is
-- registered and the filter is applied when the event is dispatched.
-- THE COMBAT LOG comes from ZacUI's one reader (ns.CLEU), asked for
-- exactly the sub-events some loaded unit listens to - the custom
-- triggers' "CLEU:<SUB>" and the declarative combat log filters. Synced
-- whenever a unit loads or unloads.
local OnCLEU               -- forward
local cleuSubs, cleuSeen = {}, {}
local cleuWanted = ""
function RM.SyncCLEU()
    wipe(cleuSubs)
    wipe(cleuSeen)
    for sub, list in pairs(cleuListeners) do
        if #list > 0 then cleuSeen[sub] = true cleuSubs[#cleuSubs + 1] = sub end
    end
    local T = RM.Triggers
    if T and T.CombatLogSubs then
        for sub in pairs(T.CombatLogSubs()) do
            if not cleuSeen[sub] then cleuSeen[sub] = true cleuSubs[#cleuSubs + 1] = sub end
        end
    end
    table.sort(cleuSubs)
    local key = table.concat(cleuSubs, ",")
    if key == cleuWanted then return end
    cleuWanted = key
    if #cleuSubs == 0 then CLEUBus.Off("RaidMods") else CLEUBus.On("RaidMods", cleuSubs, OnCLEU) end
end

local function Subscribe(inst, tindex, ev)
    local base, unitFilter = ev:match("^([A-Z][A-Z_0-9]+):(%l+%d*)$")
    if base and not RM.CUSTOM_EVENTS[base] and base:sub(1, 3) ~= "WA_" then
        ev = base
    else
        unitFilter = nil
    end
    local list = listeners[ev]
    if not list then list = {} listeners[ev] = list end
    list[#list + 1] = { inst = inst, t = tindex, unit = unitFilter }
    if ev:sub(1, 5) == "CLEU:" then
        cleuListeners[ev:sub(6)] = list
    elseif ev:match("^[A-Z][A-Z_0-9]+$") and not ev:match("^WA_") and not RM.CUSTOM_EVENTS[ev] then
        if not gameEvents[ev] then
            gameEvents[ev] = true
            pcall(frame.RegisterEvent, frame, ev)
        end
    end
end
local function Unsubscribe(inst)
    for _, list in pairs(listeners) do
        for i = #list, 1, -1 do
            if list[i].inst == inst then table.remove(list, i) end
        end
    end
end

local RunCustom   -- forward
local function UnitPasses(filter, unit)
    if not filter then return true end
    if filter == "nameplate" then return type(unit) == "string" and unit:sub(1, 9) == "nameplate" end
    return unit == filter
end
local function Dispatch(list, event, ...)
    -- by index, no copy: a unit unloading mid-dispatch is skipped by the
    -- loaded check, one added is simply reached
    local i = 1
    while i <= #list do
        local e = list[i]
        local inst = e.inst
        if RM.loaded[inst.id] == inst and (not e.unit or UnitPasses(e.unit, (...))) then
            RunCustom(inst, e.t, event, ...)
        end
        i = i + 1
    end
end

-- the coalescer for COALESCED events: pending[event][unit] = true, one
-- timer, each pair delivered once per flush
local pending = {}
local flushArmed = false
local function FlushUnitEvents()
    flushArmed = false
    for event, units in pairs(pending) do
        local list = listeners[event]
        for unit in pairs(units) do
            units[unit] = nil
            if list and #list > 0 then Dispatch(list, event, unit) end
        end
    end
end
local function QueueUnitEvent(event, unit)
    local units = pending[event]
    if not units then units = {} pending[event] = units end
    units[unit or ""] = true
    if flushArmed then return end
    flushArmed = true
    C_Timer.After(0.1, FlushUnitEvents)
end

RM.hooks = {}
function RM.Hook(event, fn)
    RM.hooks[event] = RM.hooks[event] or {}
    table.insert(RM.hooks[event], fn)
end
function RM.Fire(event, ...)
    if type(event) ~= "string" then return end
    local list = listeners[event]
    if list and #list > 0 then Dispatch(list, event, ...) end
    local hooks = RM.hooks[event]
    if hooks then for i = 1, #hooks do hooks[i](...) end end
end

-- ============================================================
-- INSTANCES
-- ============================================================
RM.loaded = {}
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = DeepCopy(x) end
    return o
end
RM.DeepCopy = DeepCopy

local RegionFactory
function RM.SetRegionFactory(fn) RegionFactory = fn end

local function DefaultHideState(allstates)
    if type(allstates) ~= "table" then return end
    local st = allstates[""]
    if st then
        st.show = false
        st.changed = true
        return true
    end
end
local function DefaultUpdateState(allstates)
    if type(allstates) ~= "table" then return end
    allstates[""] = { show = true, changed = true }
    return true
end

local function NewInstance(def)
    local inst = { def = def, id = def.id, states = {}, tstates = {}, clones = {}, active = false }
    for i = 1, #def.triggers do inst.tstates[i] = {} end
    local env = setmetatable({}, { __index = function(_, k)
        if k == "states" then return inst.tstates[1] or inst.states end
        if k == "region" then return inst.regionProxy end
        if k == "id" then return def.id end
        if k == "cloneId" then return inst.cloneId end
        -- the two helpers nearly every controller defines in its init;
        -- a few forgot, and called them anyway
        if k == "hideState" then return DefaultHideState end
        if k == "updateState" then return DefaultUpdateState end
        if k == "nuTimer" then
            -- the timer-bus call every controller defines; a few call it
            -- in their finish action without having defined it
            return function(countdown, count)
                if inst.env.key then RM.Fire("WA_NUMEN_TIMER", inst.env.key, countdown, count) end
            end
        end
        return nil
    end })
    env.config = DeepCopy(def.config or {})
    local db = RM.DB()
    local over = db and db.config and db.config[def.id]
    if type(over) == "table" then
        local function Merge(dst, src)
            for k, v in pairs(src) do
                if type(v) == "table" and type(dst[k]) == "table" then Merge(dst[k], v) else dst[k] = DeepCopy(v) end
            end
        end
        Merge(env.config, over)
    end
    inst.env = env
    if RegionFactory then inst.regionProxy = RegionFactory(inst) end
    return inst
end

local function SafeCall(inst, what, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        inst.errors = (inst.errors or 0) + 1
        -- the preview feeds the packs' code sample states it never
        -- expected; what it says about them is not worth a line
        local db = RM.DB()
        if inst.errors <= 3 and not (db and db.testMode) then
            Print("Raid Mods: '" .. inst.id .. "' " .. what .. ": " .. tostring(a))
        end
        return nil
    end
    return a, b, c
end
RM.SafeCall = SafeCall

-- ============================================================
-- STATES -> WIDGETS
-- ============================================================
local function TriggerShown(t)
    for _, st in pairs(t) do if type(st) == "table" and st.show then return true end end
    return false
end

-- Combine the triggers' tables into the unit's display states (the
-- WeakAuras rule: "any" shows the first active trigger's states; "all"
-- shows them only while every trigger is active).
local function Combine(inst)
    local def = inst.def
    local n = #def.triggers
    local states = inst.states
    for k in pairs(states) do states[k] = nil end
    if n == 0 then return end
    local src
    if def.logic then
        local t = inst.logicT
        if not t then t = {} inst.logicT = t end
        for i = 1, n do t[i] = TriggerShown(inst.tstates[i]) end
        local ok = SafeCall(inst, "trigger logic", def.logic, inst.env, t)
        if not ok then return end
        local want = def.activeTrigger
        if want and want > 0 then src = inst.tstates[want]
        else for i = 1, n do if t[i] then src = inst.tstates[i] break end end end
    elseif def.disjunctive == "all" then
        for i = 1, n do if not TriggerShown(inst.tstates[i]) then return end end
        src = inst.tstates[def.activeTrigger or 1]
    else
        local want = def.activeTrigger
        if want and want > 0 then
            src = inst.tstates[want]
        else
            for i = 1, n do if TriggerShown(inst.tstates[i]) then src = inst.tstates[i] break end end
        end
    end
    if not src then return end
    for cid, st in pairs(src) do if type(st) == "table" and st.show then states[cid] = st end end
end

local function OnStateShown(inst, cloneId, state)
    local act = inst.def.actions and inst.def.actions.start
    if act and RM.RunActions then RM.RunActions(inst, act, state, cloneId) end
end
local function OnStateHidden(inst, cloneId, state)
    local act = inst.def.actions and inst.def.actions.finish
    if act and RM.RunActions then RM.RunActions(inst, act, state, cloneId, true) end
end

-- timed states that hide themselves: expire them, then combine, then
-- run the actions for what appeared or went, then draw
function RM.Update(inst)
    local now = GetTime()
    local nextExpiry
    for _, t in ipairs(inst.tstates) do
        for cid, st in pairs(t) do
            if type(st) ~= "table" then
                t[cid] = nil
            elseif st.show and st.progressType == "timed" and st.autoHide and st.expirationTime then
                if st.expirationTime <= now and st.preview and st.duration and st.duration > 0 then
                    -- a preview sample runs round again instead of going
                    st.expirationTime = now + st.duration
                    st.changed = true
                end
                if st.expirationTime <= now then
                    st.show = false
                    st.changed = true
                elseif not nextExpiry or st.expirationTime < nextExpiry then
                    nextExpiry = st.expirationTime
                end
            end
            if st.show == false and st.changed then
                -- the trigger's own table drops hidden states (the
                -- WeakAuras contract: a hidden clone is gone)
                t[cid] = nil
                st.changed = nil
                st._gone = true
            end
        end
    end
    Combine(inst)
    local shown = inst.states
    -- draw first, then the actions: a start action may colour the region
    -- it belongs to, so the widget has to exist by then
    if RM.Render then RM.Render(inst) end
    for cid, st in pairs(shown) do
        if not inst.clones[cid] then
            inst.clones[cid] = st
            OnStateShown(inst, cid, st)
        end
        st.changed = nil
    end
    for cid, st in pairs(inst.clones) do
        if not shown[cid] then
            inst.clones[cid] = nil
            OnStateHidden(inst, cid, st)
        end
    end
    if nextExpiry then RM.ScheduleExpiry(inst, nextExpiry) end
end

function RM.ScheduleExpiry(inst, at)
    if inst.expiryAt and inst.expiryAt <= at + 0.01 and inst.expiryAt > GetTime() then return end
    inst.expiryAt = at
    local delay = at - GetTime()
    if delay < 0 then delay = 0 end
    C_Timer.After(delay + 0.02, function()
        if RM.loaded[inst.id] == inst then
            inst.expiryAt = nil
            RM.Update(inst)
        end
    end)
end

-- ============================================================
-- CUSTOM TRIGGERS
-- ============================================================
local function TrigDuration(inst, trig)
    local d = trig.duration
    if type(d) == "function" then
        local a, b = SafeCall(inst, "duration", d, inst.env)
        if type(a) == "number" then return a, b end
        return nil
    end
    return tonumber(d)
end

RunCustom = function(inst, tindex, event, ...)
    local trig = inst.def.triggers[tindex]
    if not trig or trig.kind ~= "custom" then return end
    local states = inst.tstates[tindex]
    local env = inst.env
    env.state = states[""]
    local t = trig.ttype or "stateupdate"
    if t == "stateupdate" then
        local changed = SafeCall(inst, "trigger", trig.trigger, env, states, event, ...)
        if changed then RM.Update(inst) end
    elseif t == "status" then
        local show = SafeCall(inst, "trigger", trig.trigger, env, event, ...)
        local st = states[""]
        if show then
            if not st or not st.show then
                st = st or {}
                st.show = true
                st.changed = true
                local dur, isStatic = TrigDuration(inst, trig)
                if dur and not isStatic then
                    st.progressType = "timed"
                    st.duration = dur
                    st.expirationTime = GetTime() + dur
                end
                states[""] = st
                RM.Update(inst)
            end
        elseif st and st.show then
            st.show = false
            st.changed = true
            RM.Update(inst)
        end
    else -- "event"
        local st = states[""]
        if trig.untrigger and st and st.show then
            local hide = SafeCall(inst, "untrigger", trig.untrigger, env, event, ...)
            if hide then
                st.show = false
                st.changed = true
                RM.Update(inst)
                return
            end
        end
        local show = SafeCall(inst, "trigger", trig.trigger, env, event, ...)
        if show then
            st = st or {}
            st.show = true
            st.changed = true
            local dur = TrigDuration(inst, trig)
            if dur then
                st.progressType = "timed"
                st.duration = dur
                st.expirationTime = GetTime() + dur
                st.autoHide = true
            elseif trig.hideDuration then
                st.progressType = "timed"
                st.duration = trig.hideDuration
                st.expirationTime = GetTime() + trig.hideDuration
                st.autoHide = true
            end
            if trig.name then st.name = SafeCall(inst, "name", trig.name, env) end
            if trig.icon then st.icon = SafeCall(inst, "icon", trig.icon, env) end
            states[""] = st
            RM.Update(inst)
        end
    end
end

-- ============================================================
-- LOAD RULES
-- ============================================================
RM.zoneId = nil
RM.mapId = nil
RM.encounterId = nil
RM.inCombat = false

local function RefreshZone()
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    RM.zoneId = instanceID
    RM.mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

function RM.UnitEnabled(def)
    local db = RM.DB()
    if not db or not db.enabled then return false end
    if db.raids[def.raid] == false then return false end
    -- the packs' lists (every unit filed under a "...: Lists" group):
    -- one switch for all of them, over any per-unit choice
    if def._isList == nil then
        def._isList = type(def.group) == "string" and def.group:find(": Lists", 1, true) ~= nil
    end
    if def._isList and not db.lists then return false end
    -- berserk timers, bars and warnings, every boss, off per class
    if def._isBerserk == nil then def._isBerserk = def.id:find("Berserk", 1, true) ~= nil end
    if def._isBerserk and db.berserkOff[RM.playerClass] then return false end
    local o = db.units[def.id]
    if o ~= nil then return o and true or false end
    return not def.load.never
end

local function ZoneMatches(def)
    local z = def.load.zone
    if not z then return true end
    for i = 1, #z do
        local v = z[i]
        if v == RM.zoneId or v == RM.mapId then return true end
    end
    return false
end

local function ShouldLoad(def)
    if not RM.UnitEnabled(def) then return false end
    local L = def.load
    local db = RM.DB()
    if db.testMode then
        -- the preview: one raid's units, wherever you stand, whatever
        -- the fight; only the rules about the player still apply
        if def.raid ~= db.testRaid then return false end
        if L.class and not L.class[RM.playerClass] then return false end
        return true
    end
    if L.class and not L.class[RM.playerClass] then return false end
    if L.role then
        local r = RM.PlayerRole()
        if type(L.role) == "table" then
            if not L.role[r or ""] then return false end
        elseif L.role ~= r then return false end
    end
    if L.leader then
        local ok = (L.leader.LEADER and UnitIsGroupLeader("player")) or (L.leader.ASSIST and UnitIsGroupAssistant("player"))
            or (L.leader.NONE and not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player"))
        if not ok then return false end
    end
    if L.ingroup then
        local raid, grp = IsInRaid(), IsInGroup()
        local ok = (L.ingroup.raid and raid) or (L.ingroup.group and grp and not raid) or (L.ingroup.solo and not grp)
        if not ok then return false end
    end
    if L.faction and L.faction ~= UnitFactionGroup("player") then return false end
    if not ZoneMatches(def) then return false end
    if L.enc then
        if not RM.encounterId then return false end
        local ok = false
        for i = 1, #L.enc do if L.enc[i] == RM.encounterId then ok = true break end end
        if not ok then return false end
    end
    if L.combat ~= nil and L.combat ~= RM.inCombat then return false end
    if RM.inCombat and OutOfCombatOnly(def) then return false end
    if L.group == "raid" and not IsInRaid() then return false end
    if L.group == "group" and not IsInGroup() then return false end
    return true
end

local function Load(def)
    local inst = NewInstance(def)
    RM.loaded[def.id] = inst
    if def.init then SafeCall(inst, "init", def.init, inst.env) end
    for i, trig in ipairs(def.triggers) do
        if trig.kind == "custom" then
            for _, ev in ipairs(trig.events or {}) do Subscribe(inst, i, ev) end
        end
    end
    if RM.Triggers and RM.Triggers.Attach then RM.Triggers.Attach(inst) end
    RM.SyncCLEU()
    inst.active = true
    -- WeakAuras hands STATUS to a custom trigger when it loads; the
    -- packs use it to reset
    for i, trig in ipairs(def.triggers) do
        if trig.kind == "custom" and trig.ttype ~= "event" then RunCustom(inst, i, "STATUS") end
    end
    if RM.DB().testMode then RM.FireOptions(inst) end
end

-- The packs keep their C_Timer handles in their own aura_env (a timer,
-- a ticker, a table of them by key). Whatever is still pending when the
-- unit unloads is cancelled, so nothing it scheduled fires into the next
-- pull. Frames (they have GetObjectType) are never touched.
-- (a C_Timer handle may be a table or a native userdata, depending on
-- the client build; either way it answers :Cancel and is not a frame)
local function TimerField(v, k) return v[k] end
local function IsTimer(v)
    local t = type(v)
    if t ~= "table" and t ~= "userdata" then return false end
    local ok, cancel = pcall(TimerField, v, "Cancel")
    if not ok or type(cancel) ~= "function" then return false end
    local okF, isFrame = pcall(TimerField, v, "GetObjectType")
    return not (okF and isFrame)
end
local function CancelEnvTimers(env)
    for _, v in pairs(env) do
        if IsTimer(v) then
            pcall(v.Cancel, v)
        elseif type(v) == "table" and getmetatable(v) == nil then
            for _, x in pairs(v) do
                if IsTimer(x) then pcall(x.Cancel, x) end
            end
        end
    end
end

local function Unload(id)
    local inst = RM.loaded[id]
    if not inst then return end
    inst.active = false
    Unsubscribe(inst)
    if RM.Triggers and RM.Triggers.Detach then RM.Triggers.Detach(inst) end
    RM.SyncCLEU()
    for cid, st in pairs(inst.clones) do inst.clones[cid] = nil OnStateHidden(inst, cid, st) end
    -- after the finish actions, which may have scheduled one more
    local ok, err = pcall(CancelEnvTimers, inst.env)
    if not ok then RM.Print("Raid Mods: '" .. id .. "' timers: " .. tostring(err)) end
    for k in pairs(inst.states) do inst.states[k] = nil end
    if RM.Release then RM.Release(inst) end
    RM.loaded[id] = nil
end

function RM.ScanForLoads()
    for i = 1, #RM.unitOrder do
        local id = RM.unitOrder[i]
        local def = RM.units[id]
        local want = ShouldLoad(def)
        local have = RM.loaded[id] ~= nil
        if want and not have then Load(def)
        elseif have and not want then Unload(id) end
    end
end
function RM.ReloadUnit(id)
    Unload(id)
    local def = RM.units[id]
    if def and ShouldLoad(def) then Load(def) end
end
function RM.UnloadAll()
    for id in pairs(RM.loaded) do Unload(id) end
end

-- ============================================================
-- TEST MODE - the packs' OPTIONS preview
-- ============================================================
-- A sample state for a trigger whose own code shows nothing in the
-- preview (WeakAuras did the same: every aura is visible in its options).
local previewSeed = 0
local function FakeState(inst)
    previewSeed = previewSeed + 7
    local dur = 8 + (previewSeed % 23)
    local name = (RM.CleanId and RM.CleanId(inst.id)) or inst.id
    name = name:gsub("^[^:]+:%s*", "")
    local D = inst.def.display
    return { show = true, changed = true, preview = true, name = name, icon = (D and D.displayIcon ~= "" and D.displayIcon) or 134400,
        progressType = "timed", duration = dur, expirationTime = GetTime() + dur, autoHide = false,
        unit = "player", unitName = RM.me, GUID = RM.myGUID, stacks = 2, count = 2, value = 50, total = 100, text = name }
end
function RM.FireOptions(inst)
    for i, trig in ipairs(inst.def.triggers) do
        if trig.kind == "custom" then
            RunCustom(inst, i, "OPTIONS")
            local t = inst.tstates[i]
            if not TriggerShown(t) then
                t[""] = FakeState(inst)
            else
                -- what the pack's own OPTIONS code showed is a sample too
                for _, st in pairs(t) do if st.show then st.preview = true end end
            end
        end
    end
    if RM.Triggers and RM.Triggers.Preview then RM.Triggers.Preview(inst) end
    RM.Update(inst)
end

-- the raid to preview when none was picked: the one you stand in, else the first
function RM.PreviewRaidDefault()
    for _, key in ipairs(RM.raidOrder) do
        local r = RM.raids[key]
        if r.zone then
            for _, z in ipairs(r.zone) do if z == RM.zoneId then return key end end
        end
    end
    return RM.raidOrder[1]
end

-- THE PREVIEW. One raid's units load wherever you are, every trigger
-- shows a sample, and every anchor's handle is unlocked for dragging.
-- Off again: samples cleared, the real load rules back, handles locked.
function RM.SetTestMode(on, raidKey)
    local db = RM.DB()
    db.testMode = on and true or false
    if raidKey then db.testRaid = raidKey end
    if on and not (db.testRaid and RM.raids[db.testRaid]) then db.testRaid = RM.PreviewRaidDefault() end
    if on then
        RM.ScanForLoads()          -- loads the preview raid (Load fires OPTIONS in test mode), drops the rest
        for _, inst in pairs(RM.loaded) do RM.FireOptions(inst) end
        if RM.Layout and RM.Layout.ShowAnchors then RM.Layout.ShowAnchors(true) end
    else
        for _, inst in pairs(RM.loaded) do
            for _, t in ipairs(inst.tstates) do
                for _, st in pairs(t) do st.show = false st.changed = true end
            end
            RM.Update(inst)
        end
        if RM.Layout and RM.Layout.ShowAnchors then RM.Layout.ShowAnchors(false) end
        RM.ScanForLoads()          -- the real rules again: most of the preview unloads
        for _, inst in pairs(RM.loaded) do
            for i, trig in ipairs(inst.def.triggers) do
                if trig.kind == "custom" and trig.ttype ~= "event" then RunCustom(inst, i, "STATUS") end
            end
            if RM.Triggers and RM.Triggers.Rescan then RM.Triggers.Rescan(inst) end
        end
    end
end

-- ============================================================
-- ENCOUNTERS AND THE GAME EVENT FRAME
-- ============================================================
-- Boss encounters come from ZacUI's one tracker (ns.Encounter), so the
-- load rules, the meter, the particle levels and the other boss helpers
-- always agree about which fight is up. Its "reset" is the packs' own
-- "did the encounter really end" check (their Global Encounter Bug Fix
-- controller): the group left combat with no ENCOUNTER_END, so the
-- packs get WA_FJI_ENCOUNTER_END.
RM.Hook("WA_FJI_ENCOUNTER_END", function()
    if RM.encounterId then
        RM.encounterId = nil
        RM.encounterName = nil
        RM.ScanForLoads()
    end
end)

local ALWAYS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED" }
for _, ev in ipairs(ALWAYS) do gameEvents[ev] = true frame:RegisterEvent(ev) end
-- delivered from ns.Encounter below, never registered on the frame
gameEvents.ENCOUNTER_START, gameEvents.ENCOUNTER_END = true, true

ns.Encounter.On("RaidMods.core", function(event, id, name, difficulty, size, success)
    if event == "start" then
        -- load the units for it, THEN deliver to them
        RM.encounterId = id
        RM.encounterName = name
        RM.ScanForLoads()
        local list = listeners.ENCOUNTER_START
        if list and #list > 0 then Dispatch(list, "ENCOUNTER_START", id, name, difficulty, size) end
    elseif event == "end" then
        -- deliver to the units loaded for it, THEN unload them
        local list = listeners.ENCOUNTER_END
        if list and #list > 0 then Dispatch(list, "ENCOUNTER_END", id, name, difficulty, size, success) end
        RM.encounterId = nil
        RM.encounterName = nil
        RM.ScanForLoads()
    elseif event == "reset" then
        RM.Fire("WA_FJI_ENCOUNTER_END")
    end
end)

-- one combat log line, read once by ns.CLEU: the custom triggers that
-- listen to its sub-event, then the declarative filters
OnCLEU = function(...)
    local _, sub = ...
    local list = cleuListeners[sub]
    if list and #list > 0 then Dispatch(list, "COMBAT_LOG_EVENT_UNFILTERED", ...) end
    local T = RM.Triggers
    if T and T.CLEU then T.CLEU(sub, ...) end
end

-- the group changed (ns.Roster, once per burst): the load rules look again
Roster.On("RaidMods.core", function()
    wipe(guidNames)
    RM.ScanForLoads()
end)

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "SPELLS_CHANGED" then
        RM.UpdateRole()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        RM.myGUID = UnitGUID("player") or RM.myGUID
        RM.me = UnitName("player") or RM.me
        RM.WA.myGUID, RM.WA.me = RM.myGUID, RM.me
        RefreshZone()
        RM.UpdateRole()
        RM.ApplyTTSGlobals()
        if event == "PLAYER_ENTERING_WORLD" then
            -- a /reload, not walking in (the Naxx wing labels ask)
            RM.pewReload = select(2, ...) and true or false
            RM.encounterId = nil
            C_Timer.After(1, function() RM.Fire("WA_DELAYED_PLAYER_ENTERING_WORLD") end)
        end
        RM.ScanForLoads()
    elseif event == "PLAYER_REGEN_DISABLED" then
        RM.inCombat = true
        RM.ScanForLoads()
    elseif event == "PLAYER_REGEN_ENABLED" then
        RM.inCombat = false
        RM.ScanForLoads()
    end
    local list = listeners[event]
    if list and #list > 0 then
        if COALESCED[event] then QueueUnitEvent(event, (...))
        else Dispatch(list, event, ...) end
    end
end)

function RM.OpenPage()
    if ns.OpenConfig then ns.OpenConfig("raidmods") end
end
