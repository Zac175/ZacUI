-- QoL_BossFX - per-boss particle density. Inside a raid the particle
-- cvar sits at a low "trash" level for FPS; on ENCOUNTER_START of a boss
-- you have ticked it jumps to the encounter level so the mechanics that
-- are drawn as particles (Grobbulus clouds, Sapphiron blizzard, Viscidus
-- slime, Ouro residue, Geddon bombs) are visible; on ENCOUNTER_END it
-- drops back (a loading screen does too) - after
-- an optional linger, for the fights whose ground
-- effects outlive the boss. Part of ZacUI; load order is set by the TOC.
--
-- LINEAGE. This is the particle WeakAura, by way of Driev's Essentials'
-- Particles module and its Raids.lua encounter table, rebuilt on the
-- QoL_RaidPerf contract:
--   * RESTORE, NOT ASSUME. Outside a raid your own particle setting is
--     put back exactly; the original is captured on the FIRST write and
--     persisted in ZacUIDB beside an `active` flag, so a /reload or crash
--     mid-raid never captures the lowered value as the "original" and a
--     login back in town after a crash still restores it.
--   * ONE CVAR. graphicsParticleDensity, nothing else. QoL_RaidPerf owns
--     the cosmetic set and never touches particles; this file owns
--     particles and never touches anything else.
--   * CVAR HONESTY. Existence-checked at apply time, written through
--     pcall. A build that lacks the cvar does nothing, silently, rather
--     than erroring on every encounter.
--
-- The encounter IDs are ENCOUNTER_START's first argument. Those marked
-- verified were confirmed live by the original author; the rest are the
-- standard Classic Era journal IDs. The "Print encounter IDs" toggle on
-- the QoL page prints each one as it fires, so a wrong one is a
-- one-line fix in the table below.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local QoL = ns.QoL

local DB = QoL.DB

local CVAR = "graphicsParticleDensity"
-- The RAID profile's copy. With "Raid and Battleground" graphics turned on
-- (RAIDsettingsEnabled), the client draws raids from the raidGraphics*
-- set and ignores the normal one entirely - so writing graphicsParticleDensity
-- in a raid changed a setting nobody was looking at, and the raid stayed on
-- whatever its own profile said. Same 0-5 scale.
local RAID_CVAR = "raidGraphicsParticleDensity"

-- ============================================================
-- THE ENCOUNTER TABLE
-- Bosses are { name, id, default?, linger?, wing? }. `default` ticks
-- the boss on first init (the WA's original set), `linger` seeds a
-- keep-on-after-kill duration in seconds, `wing` colours the name on
-- the config page. All three are starting values only: the config page
-- edits the saved copy, never this table.
-- The Stockades entry is the test raid: enabling it makes 5-man
-- dungeons count as raids, so the whole on/off/linger cycle can be
-- exercised without a 40-man.
-- ============================================================
local RAIDS = {
    {
        key = "naxx", label = "Naxxramas",
        bosses = {
            { name = "Anub'Rekhan",            id = 1107, wing = "spider" },
            { name = "Grand Widow Faerlina",   id = 1110, default = true, wing = "spider" },
            { name = "Maexxna",                id = 1116, wing = "spider" },
            { name = "Noth the Plaguebringer", id = 1117, wing = "plague" },
            { name = "Heigan the Unclean",     id = 1112, wing = "plague" },
            { name = "Loatheb",                id = 1115, wing = "plague" },
            { name = "Instructor Razuvious",   id = 1113, wing = "military" },
            { name = "Gothik the Harvester",   id = 1109, wing = "military" },
            { name = "The Four Horsemen",      id = 1121, default = true, wing = "military" },
            { name = "Patchwerk",              id = 1118, wing = "construct" },
            { name = "Grobbulus",              id = 1111, default = true, wing = "construct" },
            { name = "Gluth",                  id = 1108, wing = "construct" },
            { name = "Thaddius",               id = 1120, wing = "construct" },
            { name = "Sapphiron",              id = 1119, default = true, linger = 10, wing = "frostwyrm" },
            { name = "Kel'Thuzad",             id = 1114, default = true, wing = "frostwyrm" },
        },
    },
    {
        key = "aq40", label = "Temple of Ahn'Qiraj",
        bosses = {
            { name = "The Prophet Skeram",      id = 709 },
            { name = "Bug Trio",                id = 710, default = true },
            { name = "Battleguard Sartura",     id = 711 },
            { name = "Fankriss the Unyielding", id = 712 },
            { name = "Viscidus",                id = 713, default = true, linger = 15 },
            { name = "Princess Huhuran",        id = 714 },
            { name = "Twin Emperors",           id = 715, default = true },
            { name = "Ouro",                    id = 716, default = true, linger = 30 },
            { name = "C'Thun",                  id = 717, default = true },
        },
    },
    {
        key = "bwl", label = "Blackwing Lair",
        bosses = {
            { name = "Razorgore the Untamed",   id = 610 },
            { name = "Vaelastrasz the Corrupt", id = 611 },
            { name = "Broodlord Lashlayer",     id = 612 },
            { name = "Firemaw",                 id = 613 },
            { name = "Ebonroc",                 id = 614 },
            { name = "Flamegor",                id = 615 },
            { name = "Chromaggus",              id = 616 },
            { name = "Nefarian",                id = 617 },
        },
    },
    {
        key = "mc", label = "Molten Core",
        bosses = {
            { name = "Lucifron",                 id = 663 },
            { name = "Magmadar",                 id = 664 },
            { name = "Gehennas",                 id = 665 },
            { name = "Garr",                     id = 666 },
            { name = "Shazzrah",                 id = 667 },
            { name = "Baron Geddon",             id = 668, default = true },
            { name = "Sulfuron Harbinger",       id = 669 },
            { name = "Golemagg the Incinerator", id = 670 },
            { name = "Majordomo Executus",       id = 671 },
            { name = "Ragnaros",                 id = 672 },
        },
    },
    {
        key = "aq20", label = "Ruins of Ahn'Qiraj",
        bosses = {
            { name = "Kurinnaxx",              id = 718 },
            { name = "General Rajaxx",         id = 719 },
            { name = "Moam",                   id = 720 },
            { name = "Buru the Gorger",        id = 721 },
            { name = "Ayamiss the Hunter",     id = 722 },
            { name = "Ossirian the Unscarred", id = 723 },
        },
    },
    {
        key = "zg", label = "Zul'Gurub",
        bosses = {
            { name = "High Priestess Jeklik", id = 785 },
            { name = "High Priest Venoxis",   id = 784, default = true },
            { name = "High Priestess Mar'li", id = 791 },
            { name = "Bloodlord Mandokir",    id = 787 },
            { name = "Edge of Madness",       id = 789 },
            { name = "High Priest Thekal",    id = 788 },
            { name = "Gahz'ranka",            id = 792 },
            { name = "High Priestess Arlokk", id = 790 },
            { name = "Jin'do the Hexxer",     id = 786 },
            { name = "Hakkar",                id = 793, default = true },
        },
    },
    {
        key = "test", label = "The Stockades (testing)", test = true,
        bosses = {
            { name = "Targorr the Dread", id = 2756, default = true, linger = 10 },
            { name = "Kam Deepfury",      id = 2757, default = true, linger = 10 },
            { name = "Hamhock",           id = 2758, default = true, linger = 10 },
            { name = "Dextren Ward",      id = 2759, default = true, linger = 10 },
            { name = "Bazil Thredd",      id = 2760, default = true, linger = 10 },
        },
    },
}

-- encounterID -> { raidKey, name }. Built once at load: the table above
-- is small and static, and every ENCOUNTER_START does one lookup.
local INDEX = {}
for _, raid in ipairs(RAIDS) do
    for _, boss in ipairs(raid.bosses) do
        INDEX[boss.id] = { raidKey = raid.key, name = boss.name }
    end
end

-- ============================================================
-- CVAR ACCESS - the QoL_RaidPerf pair, verbatim.
-- ============================================================
local function ReadCVar(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not get then return nil end
    local ok, v = pcall(get, name)
    if ok and v ~= nil then return tostring(v) end
    return nil
end

local function WriteCVar(name, value)
    pcall(SetCVar, name, value)
end

-- Which particle cvar the game is drawing with right now: the raid
-- profile's inside a raid or battleground when that profile is switched
-- on, the normal one everywhere else (including the 5-man test raid).
local function ActiveCVar()
    local _, instanceType = IsInInstance()
    if (instanceType == "raid" or instanceType == "pvp")
            and ReadCVar("RAIDsettingsEnabled") == "1"
            and ReadCVar(RAID_CVAR) ~= nil then
        return RAID_CVAR
    end
    return CVAR
end

-- ============================================================
-- STATE - lives in the QoL table of ZacUIDB so it survives /reload.
--   enabled          : the config toggle
--   raidDensity      : particle level between encounters in a raid
--   encounterDensity : particle level during a ticked boss
--   worldEnabled     : also set a level OUTSIDE raids (open world,
--                      dungeons, battlegrounds), instead of only putting
--                      back whatever was held. The restore-only design
--                      had a trap: once the held "original" was ever a
--                      low value (the old WA left it at 0 the first time
--                      this ran), every raid exit restored 0 and every
--                      raid entry captured 0 again - the world never got
--                      its particles back.
--   worldDensity     : that level (0-5)
--   chat             : print every ENCOUNTER_START/END id to chat
--   active           : we are holding an original (the cvar is ours)
--   saved            : the original string value, nil when not held
--   cvar             : WHICH cvar `saved` belongs to (normal or raid
--                      profile); nil on states saved before it existed,
--                      which were always the normal one
--   raids[key]       : { enabled, bosses = { [id] = true },
--                        linger = { [id] = seconds } }
-- Nil-filled, never rev-wiped: adding this must not reset the QoL page.
-- Each raid's block seeds itself the first time it is read, from the
-- `default` and `linger` fields above.
-- ============================================================
local function State()
    local d = DB()
    if d.bossFX == nil then
        d.bossFX = {
            enabled = true,
            raidDensity = 0,
            encounterDensity = 3,
            chat = false,
            active = false,
            saved = nil,
            raids = {},
        }
    end
    local st = d.bossFX
    st.raids = st.raids or {}
    -- nil-filled for saves from before the world level existed
    if st.worldEnabled == nil then st.worldEnabled = true end
    if st.worldDensity == nil then st.worldDensity = 5 end
    return st
end
QoL.BossFXState = State

local function RaidState(raid)
    local st = State()
    local r = st.raids[raid.key]
    if not r then
        -- the test raid is opt-in; every real raid starts armed with the
        -- WA's original boss set, which is the point of the port
        r = { enabled = not raid.test, bosses = {}, linger = {} }
        for _, boss in ipairs(raid.bosses) do
            if boss.default then r.bosses[boss.id] = true end
            if boss.linger then r.linger[boss.id] = boss.linger end
        end
        st.raids[raid.key] = r
    end
    r.bosses = r.bosses or {}
    r.linger = r.linger or {}
    return r
end
QoL.BossFXRaidState = RaidState
QoL.BossFXRaids = RAIDS

local function RaidByKey(key)
    for _, raid in ipairs(RAIDS) do
        if raid.key == key then return raid end
    end
end

-- ============================================================
-- DECISIONS
-- ============================================================
local function Chat(msg)
    if State().chat then Print("bossfx: " .. msg) end
end

-- Test raid on -> a 5-man counts as a raid, so the Stockades can drive
-- the whole cycle. Read live: flipping the toggle mid-dungeon re-decides
-- on the next event.
local function InRaidLike()
    local _, instanceType = IsInInstance()
    if instanceType == "raid" then return true end
    if instanceType == "party" then
        local test = RaidByKey("test")
        return test ~= nil and RaidState(test).enabled == true
    end
    return false
end

-- Which raid block owns this encounter, and is the boss ticked.
local function Managed(encounterID)
    local info = INDEX[encounterID]
    if not info then return false, nil end
    local raid = RaidByKey(info.raidKey)
    local r = RaidState(raid)
    if not r.enabled then return false, info end
    return r.bosses[encounterID] == true, info
end

local function LingerSeconds(encounterID)
    local info = INDEX[encounterID]
    if not info then return nil end
    local r = RaidState(RaidByKey(info.raidKey))
    local secs = tonumber(r.linger[encounterID])
    if secs and secs > 0 then return secs end
    return nil
end

-- ============================================================
-- THE WRITES
-- Hold() captures the original on the first write and never again while
-- `active` is up. Release() puts it back and drops the flag. Everything
-- that sets a level goes through Level(), so the capture can't be
-- skipped by a new code path.
-- ============================================================
local function Release(st)
    if not st.active then return end
    if st.saved ~= nil then WriteCVar(st.cvar or CVAR, st.saved) end
    st.saved = nil
    st.cvar = nil
    st.active = false
end

local function Level(st, value)
    local cvar = ActiveCVar()
    -- Holding the other profile's cvar (the raid profile was switched on
    -- or off mid-raid, or an old save): put that one back first, then
    -- take this one, so neither is ever left lowered.
    if st.active and (st.cvar or CVAR) ~= cvar then Release(st) end
    local current = ReadCVar(cvar)
    if current == nil then return false end  -- build lacks the cvar
    if not st.active then
        st.saved = current
        st.cvar = cvar
        st.active = true
    end
    value = tostring(value)
    if current ~= value then WriteCVar(cvar, value) end
    return true
end

-- ============================================================
-- ENCOUNTER FLOW
--   session.encounter : the managed encounter currently running
--   session.linger    : the C_Timer handle keeping the level up after it
-- Session, not DB: a /reload mid-fight loses the encounter (nothing
-- re-fires ENCOUNTER_START), and PLAYER_ENTERING_WORLD re-baselines.
-- ============================================================
local session = { encounter = nil, linger = nil }

local function CancelLinger()
    if session.linger then
        session.linger:Cancel()
        session.linger = nil
    end
end

-- Outside raids: the held original goes back first (so nothing is ever
-- left lowered by us), then the world level is written over it when
-- that is switched on. The world level is a plain write, never a hold:
-- it is the setting you want, not one we borrowed.
local function World(st)
    Release(st)
    if not st.worldEnabled then return end
    local current = ReadCVar(CVAR)
    if current == nil then return end
    local value = tostring(st.worldDensity)
    if current ~= value then
        WriteCVar(CVAR, value)
        Chat("world " .. value .. " (" .. CVAR .. ")")
    end
end

-- The one baseline decision: in a raid-like instance with the feature
-- on, hold the raid level; anywhere else, release and set the world
-- level. Called from every path that is not "a boss is running".
local function Baseline()
    local st = State()
    if not QoL.enabled or not st.enabled then
        Release(st)
        return
    end
    if InRaidLike() then
        Level(st, st.raidDensity)
        Chat("baseline " .. tostring(st.raidDensity) .. " (" .. ActiveCVar() .. ")")
    else
        World(st)
    end
end

local function OnEncounterStart(encounterID, encounterName)
    local st = State()
    local managed, info = Managed(encounterID)
    Chat(string.format("ENCOUNTER_START %s (%s)%s", tostring(encounterID),
        tostring((info and info.name) or encounterName or "?"),
        managed and "" or " - not ticked"))
    if not managed or not QoL.enabled or not st.enabled then return end
    session.encounter = encounterID
    CancelLinger()
    if Level(st, st.encounterDensity) then
        Chat("  particles " .. tostring(st.encounterDensity) .. " (" .. ActiveCVar() .. ")")
    end
end

-- how: "end" (ENCOUNTER_END) or "reset" (it never came; the whole group
-- left combat - ns.Encounter's check, the one the raid mods unload by)
local function OnEncounterEnd(encounterID, encounterName, how)
    Chat(string.format("%s %s (%s)", how == "reset" and "encounter reset (group out of combat)" or "ENCOUNTER_END",
        tostring(encounterID), tostring(encounterName or "?")))
    if session.encounter ~= encounterID then return end
    session.encounter = nil
    local linger = LingerSeconds(encounterID)
    if linger then
        Chat("  linger " .. linger .. "s")
        CancelLinger()
        session.linger = C_Timer.NewTimer(linger, function()
            session.linger = nil
            Baseline()
        end)
    else
        Baseline()
    end
end

-- Leaving combat with no encounter running and no linger pending puts
-- the baseline back (a level changed by the config or a zone mid-
-- combat). A combat drop mid-encounter leaves the level alone; an
-- ENCOUNTER_END that never came is cleared by the next loading screen.
local function OnRegenEnabled()
    if session.encounter or session.linger then return end
    Baseline()
end

-- PLAYER_ENTERING_WORLD covers login, /reload, the instance portal,
-- hearthing and summons. It also ends whatever encounter we thought was
-- running: a reload mid-fight will not get a second ENCOUNTER_START.
local function OnEnteringWorld()
    session.encounter = nil
    CancelLinger()
    Baseline()
end

-- Config changes re-decide immediately. During a boss or a linger the
-- encounter level is re-applied (so the slider edits live mid-fight);
-- turning the feature off mid-fight releases at once, which puts YOUR
-- setting back - never lower than the level that mattered.
local function Refresh()
    if ns.FeatureOn and not ns.FeatureOn("boss_fx") then return end   -- (Core_Flavor)
    local st = State()
    if session.encounter or session.linger then
        if QoL.enabled and st.enabled then
            Level(st, st.encounterDensity)
            return
        end
        -- module or feature turned off: the fight is no longer ours
        session.encounter = nil
        CancelLinger()
    end
    Baseline()
end
QoL.BossFXRefresh = Refresh

-- boss pulls and their ends from ZacUI's one encounter tracker
-- The tracker's "reset" (the whole group out of combat with no
-- ENCOUNTER_END) is not used here: a raid-wide combat drop can happen
-- mid-fight (Kel'Thuzad's phase gap), and dropping the particles there
-- would hide the mechanics they are raised for for the rest of the fight.
-- (the bosses are Classic Era's: on TBC and Forever, or the game-version
-- override's, none of this listens - Core_Flavor)
if not (ns.FeatureOn and not ns.FeatureOn("boss_fx")) then
    ns.Encounter.On("QoL.BossFX", function(event, encounterID, encounterName)
        if event == "start" then
            OnEncounterStart(encounterID, encounterName)
        elseif event == "end" then
            OnEncounterEnd(encounterID, encounterName, event)
        end
    end)

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            OnRegenEnabled()
        elseif event == "PLAYER_ENTERING_WORLD" then
            OnEnteringWorld()
        end
    end)
end
