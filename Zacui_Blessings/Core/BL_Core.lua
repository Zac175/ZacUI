-- BL_Core - paladin blessings for the group: who has which blessings,
-- who gives which class what, and the aura each paladin holds. The model
-- (BL.pallys), the group roster, this paladin's own spells, and every
-- change to an assignment. BL_Comm keeps the model in step with the
-- other paladins (ZacUI or PallyPower); BL_Bar casts; BL_Grid assigns.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHO MAY CHANGE WHAT (the same rule PallyPower keeps): every paladin
-- sets their own; the group leader and raid assistants set anyone's; a
-- paladin who allows "free assignment" takes changes from anybody.
--
-- WHILE PALLYPOWER IS ON this part stands down: both would answer for
-- the same paladin on the channel. BL_Import brings PallyPower's own
-- assignments over and offers to switch it off.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local D = ns.BlessingsData
if not D then return end

local Print = ns.Print

local BL = {}
ns.Blessings = BL

BL.me = UnitName("player") or "?"
BL.isPaladin = select(2, UnitClass("player")) == "PALADIN"
BL.pallys = {}       -- [name] = { blessings, auras, assign, aura, normal, symbols, freeassign, cd, seen }
BL.leaders = {}      -- [name] = true: leader or assistant
BL.roster = {}       -- { unit, name, class, slot, subgroup, pet }
BL.bySlot = {}       -- [slot] = { roster entries }

-- PallyPower is an OptionalDep: loaded before this file when it is on
BL.standDown = ns.AddonLoaded("PallyPower")

-- ============================================================
-- SETTINGS - ZacUIDB.blessings (account), this paladin's own
-- assignments in ZacUICharDB.blessings
-- ============================================================
local DEFAULTS = {
    enabled = true,
    freeassign = false,     -- let anyone in the group set my blessings
    bar = {
        enabled = true,     -- the casting bar (paladins only)
        scale = 1,
        players = false,    -- a button per player beside each class (off: the bar is one column)
        aura = true,        -- the aura button
        solo = false,       -- show it outside a group too
        maxPlayers = 8,     -- player buttons per class row
        -- the look (Blessings page, Look / Text / Animation): every
        -- default is what the bar always drew. Colours left out here
        -- (background, title strip, borders, button background, title
        -- text) follow the UI theme until one is picked; fonts left out
        -- are the game font, outlined, at the sizes the bar used.
        rowHeight = 24,     -- each button's height
        classWidth = 140,   -- the class (and aura) column
        playerWidth = 76,   -- each player button
        gap = 2,            -- between buttons
        titleHeight = 20,   -- the title strip
        icons = true,       -- blessing / aura icons on the class and aura buttons
        lowAt = 20,         -- a player's blessing shows "running low" under this % of its 15 minutes
        colorHave = { r = 0.3, g = 0.8, b = 0.3, a = 0.55 },
        colorLow = { r = 1, g = 0.6, b = 0.3, a = 0.55 },
        colorMissing = { r = 1, g = 0.35, b = 0.3, a = 0.55 },
        colorDead = { r = 0.5, g = 0.5, b = 0.5, a = 0.55 },
        colorAura = { r = 0.3, g = 0.8, b = 0.35, a = 0.55 },
        showAnim = { style = "none", duration = 0.2, delay = 0, easing = "easeOutQuad" },
        alertAnim = { style = "none", duration = 0.6, delay = 0, easing = "easeOutQuad" },
    },
}
BL.BAR_DEFAULTS = DEFAULTS.bar
local function Fill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Fill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
function BL.Cfg()
    if type(ZacUIDB) ~= "table" then return nil end
    if type(ZacUIDB.blessings) ~= "table" then ZacUIDB.blessings = {} end
    local c = ZacUIDB.blessings
    -- 2026-10-20: the per-player buttons made the bar most of the screen
    -- wide; they are off now (one column per class), once, for everyone
    if not c._compactV1 then
        c._compactV1 = true
        if type(c.bar) == "table" then c.bar.players = false end
    end
    Fill(c, DEFAULTS)
    return c
end
function BL.Char()
    if type(ZacUICharDB) ~= "table" then ZacUICharDB = {} end
    local c = ZacUICharDB.blessings
    if type(c) ~= "table" then c = {} ZacUICharDB.blessings = c end
    if type(c.assign) ~= "table" then c.assign = {} end
    if type(c.normal) ~= "table" then c.normal = {} end
    if type(c.aura) ~= "number" then c.aura = 0 end
    return c
end

function BL.FreeAssign()
    local c = BL.Cfg()
    return c and c.freeassign == true or false
end

local running = false
function BL.Running() return running end

-- ============================================================
-- THE MODEL
-- ============================================================
function BL.Pally(name)
    local p = BL.pallys[name]
    if not p then
        p = { blessings = {}, auras = {}, assign = {}, aura = 0, normal = {}, cd = {}, symbols = 0 }
        for i = 1, D.NUM_CLASSES do p.assign[i] = 0 end
        BL.pallys[name] = p
    end
    return p
end

function BL.IsLeader(name)
    return name ~= nil and BL.leaders[name] == true
end

function BL.CanControl(name)
    if name == BL.me then return true end
    if BL.IsLeader(BL.me) then return true end
    local p = BL.pallys[name]
    return p ~= nil and p.freeassign == true
end

-- the paladins, me first when I am one, then by name
function BL.PallyNames()
    local out = {}
    for name in pairs(BL.pallys) do if name ~= BL.me then out[#out + 1] = name end end
    table.sort(out)
    if BL.isPaladin then table.insert(out, 1, BL.me) end
    return out
end

-- who covers `slot` with `b` already (nil: nobody)
function BL.WhoGives(slot, b, except)
    for name, p in pairs(BL.pallys) do
        if name ~= except and p.assign[slot] == b then return name end
    end
    return nil
end

function BL.Knows(name, b)
    local p = BL.pallys[name]
    return p ~= nil and p.blessings[b] ~= nil
end

function BL.KnowsAura(name, a)
    local p = BL.pallys[name]
    return p ~= nil and p.auras[a] ~= nil
end

-- ============================================================
-- CHANGES - the UI and the channel both come through here
-- ============================================================
local listeners = {}
function BL.OnChange(key, fn) listeners[key] = fn end
local changeQueued = false
function BL.Changed()
    if changeQueued then return end
    changeQueued = true
    C_Timer.After(0.1, function()
        changeQueued = false
        for _, fn in pairs(listeners) do pcall(fn) end
    end)
end

local function SaveMine()
    if not BL.isPaladin then return end
    local p = BL.pallys[BL.me]
    if not p then return end
    local c = BL.Char()
    for i = 1, D.NUM_CLASSES do c.assign[i] = p.assign[i] or 0 end
    c.aura = p.aura or 0
    c.normal = {}
    for slot, t in pairs(p.normal) do
        c.normal[slot] = {}
        for tn, b in pairs(t) do c.normal[slot][tn] = b end
    end
end

BL.SaveMine = SaveMine

-- outgoing changes wait a second, so cycling a cell through four
-- blessings sends one line, not four
local sendQueue, sendTimer = {}, nil
local function QueueSend(key, fn)
    sendQueue[key] = fn
    if sendTimer then sendTimer:Cancel() end
    sendTimer = C_Timer.NewTimer(1.0, function()
        sendTimer = nil
        local q = sendQueue
        sendQueue = {}
        for _, f in pairs(q) do pcall(f) end
    end)
end

function BL.SetAssign(name, slot, b)
    if not BL.CanControl(name) then return false end
    BL.Pally(name).assign[slot] = b or 0
    if name == BL.me then SaveMine() end
    QueueSend("a:" .. name .. ":" .. slot, function() BL.Comm.SendAssign(name, slot, BL.Pally(name).assign[slot]) end)
    BL.Changed()
    return true
end

function BL.SetAllClasses(name, b)
    if not BL.CanControl(name) then return false end
    local p = BL.Pally(name)
    for i = 1, D.NUM_CLASSES do p.assign[i] = b or 0 end
    if name == BL.me then SaveMine() end
    QueueSend("m:" .. name, function() BL.Comm.SendMassAssign(name, b or 0) end)
    BL.Changed()
    return true
end

function BL.SetAura(name, a)
    if not BL.CanControl(name) then return false end
    BL.Pally(name).aura = a or 0
    if name == BL.me then SaveMine() end
    QueueSend("aura:" .. name, function() BL.Comm.SendAura(name, BL.Pally(name).aura) end)
    BL.Changed()
    return true
end

-- a per-player blessing (over the class one); b = nil / 0 clears it
function BL.SetNormal(name, slot, target, b)
    if not BL.CanControl(name) then return false end
    local p = BL.Pally(name)
    p.normal[slot] = p.normal[slot] or {}
    p.normal[slot][target] = (b and b > 0) and b or nil
    if name == BL.me then SaveMine() end
    QueueSend("n:" .. name .. ":" .. slot .. ":" .. target, function() BL.Comm.SendNormal(name, slot, target, b or 0) end)
    BL.Changed()
    return true
end

-- cycle a cell to the next blessing this paladin knows that nobody else
-- gives this class (dir -1 goes back); 0 = none
function BL.Cycle(name, slot, dir)
    local p = BL.Pally(name)
    local cur = p.assign[slot] or 0
    local n = D.NUM_BLESSINGS
    for _ = 1, n + 1 do
        cur = (cur + (dir or 1)) % (n + 1)
        if cur == 0 then break end
        if BL.Knows(name, cur) and not BL.WhoGives(slot, cur, name) then break end
    end
    return BL.SetAssign(name, slot, cur)
end

function BL.CycleAura(name, dir)
    local p = BL.Pally(name)
    local cur = p.aura or 0
    local n = D.NUM_AURAS
    for _ = 1, n + 1 do
        cur = (cur + (dir or 1)) % (n + 1)
        if cur == 0 then break end
        if BL.KnowsAura(name, cur) then
            local taken = false
            for other, q in pairs(BL.pallys) do if other ~= name and q.aura == cur then taken = true end end
            if not taken then break end
        end
    end
    return BL.SetAura(name, cur)
end

-- Clear: the leader clears everyone (and tells the group); anyone else
-- clears what they may. fromChannel: a leader's CLEAR arriving.
function BL.ClearAll(skipAuras, fromChannel)
    local cleared = {}
    for name, p in pairs(BL.pallys) do
        if (fromChannel ~= "own" and fromChannel) or (fromChannel == "own" and name == BL.me)
            or (not fromChannel and BL.CanControl(name)) then
            for slot, t in pairs(p.normal) do
                for tn in pairs(t) do cleared[#cleared + 1] = { name, slot, tn } end
            end
            for i = 1, D.NUM_CLASSES do p.assign[i] = 0 end
            p.normal = {}
            if not skipAuras then p.aura = 0 end
        end
    end
    SaveMine()
    if not fromChannel then
        if BL.IsLeader(BL.me) then
            BL.Comm.SendClear(skipAuras)
        else
            for name in pairs(BL.pallys) do
                if BL.CanControl(name) then
                    BL.Comm.SendAllAssign(name)
                    if not skipAuras then BL.Comm.SendAura(name, 0) end
                end
            end
            for _, c in ipairs(cleared) do BL.Comm.SendNormal(c[1], c[2], c[3], 0) end
        end
    end
    BL.Changed()
end

-- The automatic split: for each class, its wanted blessings in order
-- (D.PRIORITY), each handed to a paladin who knows it and gives that
-- class nothing yet - best talent first for Wisdom and Might. Only the
-- paladins I may change are touched; what the others give is kept.
function BL.AutoAssign()
    local names = BL.PallyNames()
    local mine = {}
    for _, n in ipairs(names) do if BL.CanControl(n) then mine[#mine + 1] = n end end
    if #mine == 0 then return 0 end
    for _, n in ipairs(mine) do
        local p = BL.Pally(n)
        for i = 1, D.NUM_CLASSES do p.assign[i] = 0 end
    end
    for slot, cls in ipairs(D.CLASSES) do
        local present = BL.bySlot[slot] and #BL.bySlot[slot] > 0
        if present or not IsInGroup or not IsInGroup() then
            local given = {}
            for name, p in pairs(BL.pallys) do
                if (p.assign[slot] or 0) > 0 then given[p.assign[slot]] = true end
            end
            for _, b in ipairs(D.PRIORITY[cls] or {}) do
                if not given[b] then
                    local best, bestScore
                    for _, n in ipairs(mine) do
                        local p = BL.Pally(n)
                        local r = p.blessings[b]
                        if r and (p.assign[slot] or 0) == 0 then
                            local score = (r.talent or 0) * 10 + (r.rank or 0)
                            if not bestScore or score > bestScore then best, bestScore = n, score end
                        end
                    end
                    if best then
                        BL.Pally(best).assign[slot] = b
                        given[b] = true
                    end
                end
            end
        end
    end
    -- auras: one each, in order, to paladins who know them
    local auraTaken = {}
    for name, p in pairs(BL.pallys) do
        if not BL.CanControl(name) and (p.aura or 0) > 0 then auraTaken[p.aura] = true end
    end
    for _, n in ipairs(mine) do
        local p = BL.Pally(n)
        p.aura = 0
        for _, a in ipairs(D.AURA_PRIORITY) do
            if not auraTaken[a] and p.auras[a] then p.aura = a; auraTaken[a] = true break end
        end
    end
    SaveMine()
    for _, n in ipairs(mine) do
        BL.Comm.SendAllAssign(n)
        BL.Comm.SendAura(n, BL.Pally(n).aura)
    end
    BL.Changed()
    return #mine
end

-- ============================================================
-- MY OWN SPELLS - highest rank and improving talent of each blessing
-- and aura, read from the spellbook and talent tree
-- ============================================================
local function SpellbookRanks()
    local out = {}
    if not GetNumSpellTabs then return out end
    local BOOK = BOOKTYPE_SPELL or "spell"
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, count = GetSpellTabInfo(tab)
        for slot = (offset or 0) + 1, (offset or 0) + (count or 0) do
            local name, sub = GetSpellBookItemName(slot, BOOK)
            if name then
                local r = tonumber((sub or ""):match("(%d+)")) or 1
                if not out[name] or r > out[name] then out[name] = r end
            end
        end
    end
    return out
end

-- the talent drawn with the spell's own icon that is not the spell
-- itself (Improved Blessing of Might and the like; any client language)
local function TalentFor(icon, spellName)
    if not (icon and GetNumTalentTabs and GetTalentInfo) then return 0 end
    for t = 1, GetNumTalentTabs() do
        for i = 1, (GetNumTalents and GetNumTalents(t) or 0) do
            local tname, ticon, _, _, rank = GetTalentInfo(t, i)
            if ticon == icon and tname and tname ~= spellName then return rank or 0 end
        end
    end
    return 0
end

function BL.ScanMe()
    if not BL.isPaladin then return end
    local ranks = SpellbookRanks()
    local p = BL.Pally(BL.me)
    p.blessings, p.auras = {}, {}
    for i, b in ipairs(D.BLESSINGS) do
        local name, _, icon = GetSpellInfo(b.normal)
        if name and ranks[name] then
            p.blessings[i] = { rank = ranks[name], talent = b.improved and TalentFor(icon, name) or 0 }
        end
        -- the Greater one known (level 52 / 60, or the book read): else
        -- the bar casts the normal blessing on a left click too
        local gname = b.greater and GetSpellInfo(b.greater)
        p.greaterKnown = p.greaterKnown or {}
        p.greaterKnown[i] = (gname and ranks[gname]) and true or nil
    end
    for i, a in ipairs(D.AURAS) do
        local name, _, icon = GetSpellInfo(a.id)
        if name and ranks[name] then
            p.auras[i] = { rank = ranks[name], talent = a.improved and TalentFor(icon, name) or 0 }
        end
    end
    p.symbols = GetItemCount and GetItemCount(D.SYMBOL_OF_KINGS) or 0
    p.freeassign = BL.FreeAssign()
    p.cd = p.cd or {}
    for i, ids in ipairs(D.COOLDOWNS) do
        p.cd[i] = nil
        for _, id in ipairs(ids) do
            if IsSpellKnown and IsSpellKnown(id) then
                local start, duration = GetSpellCooldown(id)
                if ns.Hidden(start, duration) then start, duration = 0, 0 end   -- (hidden on WoW Forever)
                p.cd[i] = { start = start or 0, duration = duration or 0 }
            end
        end
    end
end

-- ============================================================
-- THE GROUP
-- ============================================================
local function ClassSlot(unit)
    local _, cls = UnitClass(unit)
    return cls and D.CLASS_SLOT[cls]
end

function BL.ScanRoster()
    local roster, bySlot, leaders = {}, {}, {}
    local function Add(unit, subgroup, pet)
        if not UnitExists(unit) then return end
        local name = UnitName(unit)
        if not name then return end
        local slot = pet and D.CLASS_SLOT.PET or ClassSlot(unit)
        if not slot then return end
        local e = { unit = unit, name = name, slot = slot, subgroup = subgroup or 1, pet = pet }
        roster[#roster + 1] = e
        bySlot[slot] = bySlot[slot] or {}
        table.insert(bySlot[slot], e)
    end
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do
            local name, rank, subgroup = GetRaidRosterInfo(i)
            if name then
                local short = name:gsub("%-.*$", "")
                if (rank or 0) > 0 then leaders[short] = true end
                Add("raid" .. i, subgroup)
                Add("raidpet" .. i, subgroup, true)
            end
        end
    else
        -- the shared roster: the player and party1..4 that exist, then
        -- their pets (players and pets sit in different rows, so each
        -- row keeps the order it always had)
        for _, u in ipairs(ns.Roster.Units()) do
            Add(u, 1)
            if UnitIsGroupLeader and UnitIsGroupLeader(u) then leaders[UnitName(u)] = true end
        end
        for _, u in ipairs(ns.Roster.PetUnits()) do Add(u, 1, true) end
    end
    BL.roster, BL.bySlot, BL.leaders = roster, bySlot, leaders
    -- paladins who left the group drop out of the grid
    local here = {}
    for _, e in ipairs(roster) do if not e.pet then here[e.name] = true end end
    for name in pairs(BL.pallys) do
        if name ~= BL.me and not here[name] then BL.pallys[name] = nil end
    end
    BL.Changed()
end

-- ============================================================
-- START / EVENTS
-- ============================================================
local events = CreateFrame("Frame")
local rosterQueued = false
local wasInGroup = false
local function QueueRoster()
    if rosterQueued then return end
    rosterQueued = true
    C_Timer.After(0.5, function()
        rosterQueued = false
        BL.ScanRoster()
        local inGroup = (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
        if inGroup and not wasInGroup then
            -- joined: ask everyone, and say who I am
            BL.Comm.Request()
            BL.Comm.SendSelf()
        end
        wasInGroup = inGroup
    end)
end

local spellsQueued = false
function BL.RankSignature()
    local p = BL.pallys[BL.me]
    if not p then return "" end
    local t = {}
    for i = 1, D.NUM_BLESSINGS do local r = p.blessings[i] t[#t + 1] = r and (r.rank .. "." .. r.talent) or "-" end
    for i = 1, D.NUM_AURAS do local r = p.auras[i] t[#t + 1] = r and (r.rank .. "." .. r.talent) or "-" end
    return table.concat(t, ",")
end
BL.CooldownSpell = {}
for _, ids in ipairs(D.COOLDOWNS) do for _, id in ipairs(ids) do BL.CooldownSpell[id] = true end end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_PET" then
        QueueRoster()
    elseif event == "SPELLS_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
        -- SPELLS_CHANGED comes often; the others hear about it only when
        -- a rank or talent really moved
        if spellsQueued then return end
        spellsQueued = true
        C_Timer.After(2, function()
            spellsQueued = false
            local before = BL.RankSignature()
            BL.ScanMe()
            if BL.RankSignature() ~= before then
                BL.Comm.Fresh()
                BL.Comm.SendSelf()
                BL.Changed()
            end
        end)
    elseif event == "BAG_UPDATE_DELAYED" then
        if BL.isPaladin then
            local n = GetItemCount and GetItemCount(D.SYMBOL_OF_KINGS) or 0
            local p = BL.Pally(BL.me)
            if n ~= p.symbols then p.symbols = n; BL.Changed() end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Lay on Hands / Divine Intervention used: tell the others in a bit
        -- (only those two - every other cast says nothing)
        local spellId = select(3, ...)
        if spellId and BL.CooldownSpell[spellId] then
            C_Timer.After(1.5, function() BL.ScanMe(); BL.Comm.Fresh(); BL.Comm.SendSelf() end)
        end
    end
end)

function BL.Start()
    if running or BL.standDown then return end
    local c = BL.Cfg()
    if not (c and c.enabled) then return end
    running = true
    if BL.isPaladin then
        local p = BL.Pally(BL.me)
        local ch = BL.Char()
        for i = 1, D.NUM_CLASSES do p.assign[i] = tonumber(ch.assign[i]) or 0 end
        p.aura = ch.aura or 0
        for slot, t in pairs(ch.normal) do
            p.normal[slot] = {}
            for tn, b in pairs(t) do p.normal[slot][tn] = b end
        end
        BL.ScanMe()
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        events:RegisterEvent("BAG_UPDATE_DELAYED")
    end
    BL.Comm.Start()
    -- roster news (and zoning) from the shared roster; pets come and go
    -- without it
    ns.Roster.On("Blessings.roster", QueueRoster)
    events:RegisterEvent("UNIT_PET")
    events:RegisterEvent("SPELLS_CHANGED")
    events:RegisterEvent("CHARACTER_POINTS_CHANGED")
    QueueRoster()
    wasInGroup = false
end

function BL.Stop()
    if not running then return end
    running = false
    events:UnregisterAllEvents()
    ns.Roster.On("Blessings.roster", nil)
    BL.Comm.Stop()
    BL.Changed()
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BL.Start()
end)
