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
end
