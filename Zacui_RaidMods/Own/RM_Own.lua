-- RM_Own - how ZacUI's boss modules are put together.
-- Part of ZacUI; load order is set by the TOC.
--
-- Each raid comes in two files under Own\:
--   <RAID>_Data.lua  what each piece looks like and where it sits, its
--                    load rules and options - settings, no code. Every
--                    place a piece needs behaviour holds C.
--   <RAID>.lua       the behaviour: for each piece, the functions that go
--                    in its C places. Most come from the kit
--                    (RM_OwnKit.lua: timers, countdown texts, warnings,
--                    nameplate cooldowns); the rest are written per boss.
-- O.Finish(raid) joins the two and hands the pieces to the engine. The
-- pieces keep the names they always had, so a piece switched off or moved
-- stays switched off or moved.
local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
local RM = ns.RaidMods
if not RM then return end

local O = {}
RM.Own = O

-- every raid has its module here (keyed by the raid key its pieces carry;
-- the pull timers' file is PullTimers, its pieces' raid is PT)
O.on = true
-- Which game's raids load (ns.Flavor, the developer override included):
-- Classic Era's five on Era, TBC Anniversary's nine on TBC (Own\TBC_Kit
-- and the TBC raid files). The pull and break timers run on both.
O.flavor = ns.Flavor and ns.Flavor() or "era"
if O.flavor == "era" then
    O.READY = { MC = true, BWL = true, ZG = true, AQ40 = true, NX = true, PullTimers = true, PT = true }
else
    O.READY = { PullTimers = true, PT = true }
end

-- ============================================================
-- DATA AND BEHAVIOUR
-- ============================================================
O.CODE = setmetatable({}, { __tostring = function() return "<behaviour slot>" end })
local CODE = O.CODE

local pending = {}   -- raid -> { raid = def, groups = {}, units = {}, byId = {} }

function O.Data(raidKey)
    local d = pending[raidKey]
    if not d then
        d = { groups = {}, units = {}, byId = {} }
        pending[raidKey] = d
        function d.G(def) d.groups[#d.groups + 1] = def end
        function d.U(def)
            d.units[#d.units + 1] = def
            d.byId[def.id] = def
        end
    end
    return d
end

-- the data's pieces, for the behaviour file to look at (a kit helper may
-- read a piece's settings)
function O.Piece(raidKey, id)
    local d = pending[raidKey]
    return d and d.byId[id]
end

-- Fill every C in t with behaviour[path]. Paths are dotted: "init",
-- "triggers.1.trigger", "actions.finish.custom", "conditions.2.check.fn".
local function Fill(t, path, beh, id, missing, used)
    for k, v in pairs(t) do
        local p = path == "" and tostring(k) or (path .. "." .. tostring(k))
        if v == CODE then
            local fn = beh and beh[p]
            used[p] = true
            if type(fn) == "function" then
                t[k] = fn
            else
                t[k] = nil
                missing[#missing + 1] = id .. " @ " .. p
            end
        elseif type(v) == "table" then
            Fill(v, p, beh, id, missing, used)
        end
    end
end

O.missing = {}
-- behaviour handed over for a place the settings do not have (a kit
-- builder that offers more than a piece uses is fine; a mistyped path is
-- not). Kept for the tests; nothing is printed in game.
O.unused = {}

local function Join(t, beh, id)
    local used = {}
    Fill(t, "", beh, id, O.missing, used)
    for p in pairs(beh or {}) do
        if not used[p] then O.unused[#O.unused + 1] = id .. " @ " .. p end
    end
end

-- behaviour: { [pieceId] = { [path] = function } }; a group's under
-- "group:<key>"
function O.Finish(raidKey, behaviour)
    local d = pending[raidKey]
    if not d then return end
    pending[raidKey] = nil
    -- (a raid's two files read a second time file nothing twice)
    if O.filed[raidKey] then return end
    O.filed[raidKey] = true
    if d.raid then RM.Raid(d.raid) end
    for _, g in ipairs(d.groups) do
        -- a group's own code (a custom sort) is filed as "group:<key>"
        Join(g, behaviour["group:" .. tostring(g.key)], "group:" .. tostring(g.key))
        RM.Group(g)
    end
    for _, u in ipairs(d.units) do
        Join(u, behaviour[u.id], u.id)
        RM.Unit(u)
    end
    if #O.missing > 0 and RM.Print then
        RM.Print("Raid mods (own): " .. raidKey .. " has " .. #O.missing .. " piece(s) without behaviour, first: " .. O.missing[1])
    end
    if O.PACK_RANK[raidKey] then O.FileInOrder() end
end

-- ============================================================
-- THE CLASSIC RAIDS LOAD ON DEMAND (2026-11-13)
-- ============================================================
-- (Zac: "yes i want it made load on demand") Molten Core, Blackwing Lair,
-- Zul'Gurub, Ahn'Qiraj and Naxxramas are 2.6 MB of the raid mods' 3.3 -
-- four fifths of what the game read and compiled for them at every login
-- and reload - and not one of their pieces can load outside its raid
-- (each names its zone in its load rule). Their ten files live in a
-- companion addon now - Zacui_RaidPacks, LoadOnDemand - and this is the
-- door to it. The engine, the pull and break timers and the TBC raids
-- (small) stay here and load as before.
--
--   O.LoadPacks()     reads them in (once); true when they are in. Says
--                     why in chat, once, when it cannot.
--   O.PacksLoaded()   whether they are in
--   O.PacksNeeded()   they are not in and something of theirs could load
--                     where the player stands, or the preview is on
--
-- WHO ASKS. The engine, each time it reads the zone (RM_Core: entering
-- the world, a new area) and before a preview; the Raid mods page and
-- /rm; and anything about to show every mover (ns.OnMoversAsk, RM_Anchors),
-- because five of the raids' groups have movers of their own.
--
-- THE SAME ORDER. The raids' pieces are filed ahead of everything else's,
-- raid by raid in the order below - where they stood when their files
-- were in this folder's list, ahead of the pull timers - whenever they
-- arrive (O.FileInOrder), so the page's tabs, the order pieces load in
-- and the Movers list read as they always did.
--
-- HERE, AND NOT IN A FILE OF ITS OWN: this file is in the raid mods' file
-- list before the move and after it. A game that was running through the
-- update still goes by the list it started with: the raids' files are
-- then read at login as they used to be and nothing here asks for the
-- companion.
O.PACKS_ADDON = "Zacui_RaidPacks"
O.PACKS = { "MC", "BWL", "ZG", "AQ40", "NX" }
O.PACK_RANK = {}
for i, k in ipairs(O.PACKS) do O.PACK_RANK[k] = i end
-- every zone a piece of theirs names in its load rule: the five raids'
-- instances, and 140, which one Blackwing Lair piece asks for
O.PACK_ZONES = { [409] = true, [469] = true, [140] = true, [309] = true, [531] = true, [533] = true }
O.filed = O.filed or {}

-- the five raids' entries first, in O.PACKS order; the rest as they were
local function InOrder(list, raidOf)
    local byRank, rest, any = {}, {}, false
    for i = 1, #list do
        local v = list[i]
        local r = O.PACK_RANK[raidOf(v) or ""]
        if r then
            byRank[r] = byRank[r] or {}
            byRank[r][#byRank[r] + 1] = v
            any = true
        else
            rest[#rest + 1] = v
        end
    end
    if not any then return end
    local n = 0
    for r = 1, #O.PACKS do
        local b = byRank[r]
        if b then for i = 1, #b do n = n + 1 list[n] = b[i] end end
    end
    for i = 1, #rest do n = n + 1 list[n] = rest[i] end
end
function O.FileInOrder()
    InOrder(RM.raidOrder, function(key) return key end)
    InOrder(RM.unitOrder, function(id) local d = RM.units[id] return d and d.raid end)
    InOrder(RM.groupOrder, function(key) local g = RM.groups[key] return g and g.raid end)
end

-- these are this game's raids at all (Classic Era's, the override included)
function O.PacksOffered() return O.READY.MC == true end
function O.PacksLoaded()
    for _, k in ipairs(O.PACKS) do if not O.filed[k] then return false end end
    return true
end
function O.PacksNeeded()
    if not O.PacksOffered() or O.PacksLoaded() then return false end
    if O.PACK_ZONES[RM.zoneId or false] or O.PACK_ZONES[RM.mapId or false] then return true end
    local db = RM.DB and RM.DB()
    return (db and db.testMode) and true or false
end

local told = {}
local function Tell(why, text)
    if told[why] then return end
    told[why] = true
    if RM.Print then RM.Print(text) end
end

-- Returns true when the five raids are in. The client's reason for a
-- refusal ("DISABLED", "MISSING", ...) comes back as the second value.
function O.LoadPacks()
    if O.PacksLoaded() then return true end
    if not O.PacksOffered() then return false, "FLAVOR" end
    local PACKS = O.PACKS_ADDON
    local C = C_AddOns
    local load = (C and C.LoadAddOn) or LoadAddOn
    if not load then
        Tell("NOAPI", "|cFFFF6666The Classic raids' boss mods could not be loaded:|r this game version has no way to load an addon on demand.")
        return false, "NOAPI"
    end
    local ok, loaded, reason = pcall(load, PACKS)
    -- switched off in the AddOns list: they are the raid mods' own files,
    -- so they are switched back on for this character and asked for again
    if not (ok and loaded) and reason == "DISABLED" and ns.SetPartEnabled then
        ns.SetPartEnabled(PACKS, true)
        ok, loaded, reason = pcall(load, PACKS)
    end
    if O.PacksLoaded() then
        -- the groups that came with them: their movers, in their place
        if RM.Layout and RM.Layout.GroupsArrived then RM.Layout.GroupsArrived() end
        return true
    end
    reason = (ok and reason) or (not ok and tostring(loaded)) or nil
    if reason == "MISSING" then
        Tell("MISSING", "|cFFFF6666The Classic raids' boss mods are not loaded yet.|r If ZacUI was updated while the game was "
            .. "running, close the game completely and start it again to finish the update. If it still says this afterwards, the "
            .. PACKS .. " folder is missing from Interface\\AddOns: install ZacUI again.")
    elseif reason == "DISABLED" then
        Tell("DISABLED", "|cFFFF6666The Classic raids' boss mods are switched off:|r tick " .. PACKS .. " in the AddOns list, then /reload.")
    else
        Tell("OTHER", "|cFFFF6666The Classic raids' boss mods could not be loaded|r (" .. tostring(reason or "no reason given") .. "). "
            .. "Check that the " .. PACKS .. " folder is in Interface\\AddOns and ticked in the AddOns list.")
    end
    return false, reason
end
