-- QoL_BuffRemover - takes off the buffs you tick, so the 32-buff cap
-- pushes off nothing you care about. Part of ZacUI; load order is set by
-- the TOC.
--
-- WHERE THE COUNTING IS. Readycheck's buff cap counter (RC.BuffCap) does
-- all the counting, hidden slots included, and owns the buff list
-- (RC.BuffCapData). This file only decides what to take off, and hangs
-- itself on that counter, so the stats bar's Buffs cell shows Keep or
-- Remove beside every buff and a click there switches it. Without
-- Readycheck it stays off and its page says why.
--
-- OUT OF COMBAT a ticked buff is cancelled the moment it lands.
--
-- WHEN, PER BUFF. Every tick (and name tick) can be set to go out of
-- combat only, in combat only, or both. Both is what a fresh tick gets;
-- the choice is stored only when it is one of the other two, and goes
-- with the tick when it is unticked. Each of the three can also be held
-- to "only with world buffs out" (2026-10-30, Zac: "if i have world buffs
-- out as well to cancel maybe i dont want to cancel certain things if i
-- dont have world buffs out"): then the buff stays unless at least one
-- raid world buff is on you - Rallying Cry, Zandalar, Warchief's
-- Blessing, Songflower, the three Dire Maul buffs or Sayge's fortune.
-- In combat that is decided before the fight, with the cancel buttons.
--
-- IN COMBAT addon code cannot cancel a buff; only a secure button can,
-- and only when you press something. So there are 28 cancel buttons
-- (Z0 .. Zr), each holding a few ticked buff names and moving to the
-- next name on every press, and the macros you link get one
-- "/click Zx" line per button added under a "#ZB" line (macros written
-- with the older "#ZacUIBuffs" block are rewritten). Every press of a
-- linked macro then cancels up to 28 ticked buffs. A warrior's
-- Bloodthirst buff gets a button to itself, so it goes on every press.
-- Salvation that is only dropped while tanking rides along marked
-- tank-only: the button skips it unless you are in Defensive Stance or
-- bear form at that press. The names and the macro lines are set before
-- each fight (they cannot change in one), and unlinking a macro, or
-- switching the remover off, takes the lines back out.
--
-- A NAME CANCELS EVERY BUFF CALLED THAT. In combat a buff is cancelled
-- by name, so a ticked buff that shares its name with one you keep is
-- left alone in combat; out of combat it is cancelled by its own slot.
--
-- SALVATION WHILE TANKING. A warrior in Defensive Stance, a druid in bear
-- form or a paladin with Righteous Fury loses Blessing of Salvation
-- (ticked or not, unless that choice is off). Pausing never stops that.
--
-- BY NAME. Besides the ticks in the list, a buff can be ticked by its
-- name (for buffs the list does not know, or to match a /cancelaura line
-- exactly), and a name can be set to ALWAYS KEEP, which beats every tick.
--
-- TAKING OVER A MACRO. A linked macro's own /cancelaura lines can be
-- handed to the remover: their names become name ticks and the lines
-- come out of the macro, which frees the room the /click lines need. The
-- macro as it was is kept, and "Put my macros back" restores it.
--
-- IMPORT / EXPORT. All of that travels as one line of plain text,
-- "ZacUIBuffs:1:CLASS;remove=ids;names=...;keep=...;macros=...;takeover=1",
-- which every ZacUI and Readycheck import box takes.
--
-- GIVING UP. A buff that comes straight back three times (someone's aura
-- or totem) or will not go after two tries is left alone for the rest of
-- the session, with one chat line saying so.

local ADDON_NAME = ...
-- Zacui_QoL is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local QoL = ns.QoL
local DB = QoL.DB

local BR = {}
QoL.BuffRemover = BR

-- The marker line above our /click lines. It was "#ZacUIBuffs"; the
-- short one leaves room for another line, and the old one is still
-- found (and replaced) in macros written before.
local MARK = "#ZB"
local MARKS = { MARK, "#ZacUIBuffs" }
local MACRO_LIMIT = 255
-- Two-character button names keep each "/click" line at 10 characters
-- (it was 12 with ZBCa..ZBCv), so a macro fits more of them.
local BUTTONS = 28
local CHARS = "0123456789abcdefghijklmnopqr"
-- (was 5: a warrior presses BT, Whirlwind, Sunder, Heroic Strike,
-- Cleave, Execute and a tank Bloodthirst all fight)
local MAX_LINKED = 8
local SEEN_MAX = 400
local HITS_MAX = 300
local TANK_CLASSES = { WARRIOR = true, DRUID = true, PALADIN = true }
-- the stance bar slot of the tanking form, which a secure button can read
-- mid-fight (Righteous Fury it cannot, so paladins are decided pre-pull)
local TANK_INDEX = { WARRIOR = 2, DRUID = 1 }
-- Bloodthirst's own buff: on you again after every cast, so it gets a
-- button of its own and goes on every press, not every other one
local BLOODTHIRST_ID = 23885
BR.MAX_LINKED = MAX_LINKED

local function ButtonName(i) return "Z" .. CHARS:sub(i, i) end
local LINE_LEN = #("/click " .. ButtonName(1)) + 1

-- The restricted snippet each button runs before its click: move on to
-- the next name it holds (a click with no names does nothing). A name
-- marked tank-only (Salvation not ticked, but dropped while tanking) is
-- skipped unless you are in your tanking form right now, so switching
-- to Defensive Stance or bear form mid-fight takes Salvation off too.
local NEXT_NAME = [[
    local n = self:GetAttribute("count") or 0
    if n == 0 then return false end
    local tf = self:GetAttribute("tankform")
    local tank = tf ~= nil and GetShapeshiftForm() == tf
    local i = self:GetAttribute("at") or 0
    for _ = 1, n do
        i = i % n + 1
        if tank or not self:GetAttribute("tankonly" .. i) then
            self:SetAttribute("at", i)
            self:SetAttribute("spell", self:GetAttribute("name" .. i))
            return
        end
    end
    return false
]]

local function RCB() local rc = _G.Readycheck return rc and rc.BuffCap end
-- Off Classic Era the remover follows Readycheck's counter: it runs where
-- Readycheck counts this game's buff slots (its own game-version table
-- says where; it learns the limit from the first push-offs), and stands
-- down where Readycheck's counter does. Classic Era is not asked.
local function CounterHere()
    if not (ns.Flavor and ns.Flavor() ~= "era") then return true end
    local rc = _G.Readycheck
    if not (rc and rc.FeatureOn) then return true end
    local ok, on = pcall(rc.FeatureOn, rc, "buff_pushoff")
    return not (ok and on == false)
end
BR.CounterHere = CounterHere
local function DATA() local rc = _G.Readycheck return rc and rc.BuffCapData end

-- ============================================================
-- SETTINGS: ZacUIDB.qol.buffRemover (rides the profile), with the ticks
-- per class; this character's pause and linked macros in ZacUICharDB.
-- ============================================================
local cls, race

local function Cfg()
    local d = DB()
    local b = d.buffRemover
    if type(b) ~= "table" then
        b = {}
        d.buffRemover = b
    end
    if b.enabled == nil then b.enabled = true end
    if b.auto == nil then b.auto = true end
    if b.combat == nil then b.combat = true end
    if type(b.classes) ~= "table" then b.classes = {} end
    if type(b.seen) ~= "table" then b.seen = {} end
    return b
end
BR.Cfg = Cfg

local function ClassCfg()
    local b = Cfg()
    local key = cls or select(2, UnitClass("player")) or "?"
    local c = b.classes[key]
    if type(c) ~= "table" then
        c = {}
        b.classes[key] = c
    end
    if type(c.remove) ~= "table" then c.remove = {} end
    if type(c.names) ~= "table" then c.names = {} end
    if type(c.keep) ~= "table" then c.keep = {} end
    -- per tick: "ooc" or "combat"; missing means both
    if type(c.when) ~= "table" then c.when = {} end
    if type(c.whenName) ~= "table" then c.whenName = {} end
    -- per tick: true = only while world buffs are out
    if type(c.wb) ~= "table" then c.wb = {} end
    if type(c.wbName) ~= "table" then c.wbName = {} end
    if c.salv == nil then c.salv = TANK_CLASSES[key] or false end
    return c
end
BR.ClassCfg = ClassCfg

-- phase "ooc" / "combat" (nil = either): does a tick set to `mode` count?
local function Allows(mode, phase)
    return phase == nil or mode == nil or mode == phase
end

-- the picker's value: the phase, "_wb" added when held to world buffs
function BR.When(key)
    local c = ClassCfg()
    return (c.when[key] or "both") .. (c.wb[key] and "_wb" or "")
end
function BR.WhenName(name)
    local c = ClassCfg()
    return (c.whenName[name] or "both") .. (c.wbName[name] and "_wb" or "")
end
local function WhenValue(mode)
    mode = type(mode) == "string" and mode:gsub("_wb$", "") or mode
    return (mode == "ooc" or mode == "combat") and mode or nil
end
local function WbValue(mode)
    return (type(mode) == "string" and mode:find("_wb$")) and true or nil
end
-- the two apart, for the page's picker and its "while WBs out" tick
function BR.Phase(key) return ClassCfg().when[key] or "both" end
function BR.PhaseName(name) return ClassCfg().whenName[name] or "both" end
function BR.Wb(key) return ClassCfg().wb[key] == true end
function BR.WbName(name) return ClassCfg().wbName[name] == true end

-- At least one raid world buff on you now (ids from Readycheck's list,
-- the stored Chronoboon and the seasonal ones left out); read through the
-- buff counter's list, at most five times a second.
local WORLD_BUFF_IDS = {}
for _, id in ipairs({ 22888, 355363, 24425, 355365, 16609, 355366, 15366, 22817, 22818, 22820,
    23768, 23735, 23736, 23737, 23738, 23766, 23767, 23769 }) do WORLD_BUFF_IDS[id] = true end
local wbAt, wbUp = nil, false
local function WorldBuffsUp()
    local now = GetTime()
    if wbAt and now - wbAt < 0.2 then return wbUp end
    wbAt, wbUp = now, false
    local BC = RCB and RCB()
    if not BC then return false end
    for _, a in ipairs(BC:List()) do
        if a.id and WORLD_BUFF_IDS[a.id] then wbUp = true break end
    end
    return wbUp
end
BR.WorldBuffsUp = WorldBuffsUp
-- does a tick held to world buffs (flag) go now?
local function WbOk(flag) return not flag or WorldBuffsUp() end

local function Char()
    ZacUICharDB = ZacUICharDB or {}
    local c = ZacUICharDB.buffRemover
    if type(c) ~= "table" then
        c = {}
        ZacUICharDB.buffRemover = c
    end
    if type(c.macros) ~= "table" then c.macros = {} end
    if c.paused ~= true then c.paused = nil end
    return c
end
BR.Char = Char

-- the backup key of a character's own copy: its name plus this
local CHAR_COPY = "\t(character)"
BR.CHAR_COPY = CHAR_COPY

-- Macros as they were before a takeover, by name. Account-wide (account
-- macros are shared by every character on it, so whichever character
-- took one over, any of them can put it back).
local function Backups()
    ZacUIDB.buffMacroBackup = type(ZacUIDB.buffMacroBackup) == "table" and ZacUIDB.buffMacroBackup or {}
    return ZacUIDB.buffMacroBackup
end
BR.Backups = Backups

-- ============================================================
-- STATE FOR THE SESSION
-- ============================================================
local running = false
local armed = false
local pending, lastCancel, fails, comeback, blocked = {}, {}, {}, {}, {}
local status = { names = 0, linked = 0, lines = 0, missing = {} }
local loaded = {}
local nameCache = {}

local header, buttons
local function MakeButtons()
    if buttons then return end
    header = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    buttons = {}
    for i = 1, BUTTONS do
        local b = CreateFrame("Button", ButtonName(i), UIParent, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:Hide()
        buttons[i] = b
    end
end

local function SpellName(id)
    if not id then return nil end
    local n = nameCache[id]
    if n == nil then
        local BC = RCB()
        n = BC and BC.SpellName(id) or false
        if n then nameCache[id] = n end
    end
    return n or nil
end

-- An entry's names never change once every id has one, so the list is
-- kept (shared and read-only: callers only walk it).
local namesOf = setmetatable({}, { __mode = "k" })
local function NamesOf(e)
    local out = namesOf[e]
    if out then return out end
    if e.byName then
        out = { e.name }
        namesOf[e] = out
        return out
    end
    local seen, complete = {}, true
    out = {}
    for _, id in ipairs(e.ids) do
        local n = SpellName(id)
        if n then
            if not seen[n] then
                seen[n] = true
                out[#out + 1] = n
            end
        else
            complete = false
        end
    end
    if complete then namesOf[e] = out end
    return out
end
BR.NamesOf = NamesOf

-- ============================================================
-- WHAT GOES
-- ============================================================
local function Visible(e)
    if e.class then return e.class == cls end
    if e.race then return e.race == race end
    return true
end
BR.Visible = Visible

local function Fixed(e) return (e.provided or e.locked) and true or false end
BR.Fixed = Fixed

local function Tanking()
    if not TANK_CLASSES[cls] then return false end
    if cls == "PALADIN" then
        local BC, D = RCB(), DATA()
        return BC and D and BC:Has(D.RIGHTEOUS_FURY) or false
    end
    local D = DATA()
    return D and GetShapeshiftFormID and D.TANK_FORMS[GetShapeshiftFormID() or 0] == true or false
end

local function SalvOff(e)
    return e.family ~= nil and e.family.salv == true and ClassCfg().salv == true and Tanking()
end

local function KeyOf(a)
    if a.e then return a.e.key end
    return a.id
end

-- always keep > can't > Salvation while tanking > a tick > a name tick.
-- phase ("ooc" / "combat", nil = either) leaves out ticks set to the other.
local function Removes(a, phase)
    local c = ClassCfg()
    if a.name and c.keep[a.name] then return false end
    local e = a.e
    if e then
        if Fixed(e) then return false end
        if SalvOff(e) then return true end
        if c.remove[e.key] == true and Allows(c.when[e.key], phase) and WbOk(c.wb[e.key]) then return true end
    elseif a.id ~= nil and c.remove[a.id] == true and Allows(c.when[a.id], phase) and WbOk(c.wb[a.id]) then
        return true
    end
    return a.name ~= nil and c.names[a.name] == true and Allows(c.whenName[a.name], phase)
        and WbOk(c.wbName[a.name])
end

local function State(a)
    if a.e and Fixed(a.e) then return "s" end
    if Removes(a) then return "r" end
    return "k"
end

local function Paused() return Char().paused == true end

-- paused: only Salvation-while-tanking still goes
local function RemovesNow(a, ignorePause, phase)
    if not ignorePause and Paused() then return a.e ~= nil and SalvOff(a.e) end
    return Removes(a, phase)
end

-- ============================================================
-- OUT OF COMBAT: cancel by slot
-- ============================================================
-- blocked[id] holds the buff's own name: in combat that name must stay
local blockedVer = 0         -- moves whenever `blocked` changes
local function GiveUp(a, why)
    blocked[a.id] = a.name or true
    blockedVer = blockedVer + 1
    Print("buffs: " .. (a.name or "that buff") .. " " .. why)
end

-- By slot, and a slot number is only good until something before it
-- goes: so the slot is read again right before the cancel (a different
-- buff there means skip it, the next count is moments away), and it is
-- one cancel per pass.
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local function SlotHolds(idx, id)
    if GetAuraDataByIndex then
        local d = GetAuraDataByIndex("player", idx, "HELPFUL")
        if d ~= nil and ns.IsSecret and ns.IsSecret(d.spellId) then return false end   -- (Forever, hidden)
        return d ~= nil and d.spellId == id
    end
    if UnitBuff then
        return select(10, UnitBuff("player", idx, "HELPFUL")) == id
    end
    return false
end

local function Cancel(a, now)
    if not SlotHolds(a.idx, a.id) then return false end
    CancelUnitBuff("player", a.idx, "HELPFUL")
    pending[a.id] = now
    lastCancel[a.id] = now
    C_Timer.After(2.1, function()
        local BC = RCB()
        if BC then BC:Request() end
    end)
    return true
end

local function Plan()
    local BC = RCB()
    if not BC then return end
    for id in pairs(pending) do
        if not BC:Has(id) then pending[id] = nil end
    end
    if not Cfg().auto or InCombatLockdown() then return end
    local now = GetTime()
    for _, a in ipairs(BC:List()) do
        local id = a.id
        if id and not blocked[id] then
            local t = pending[id]
            if not (t and now - t < 2) then
                if t then
                    pending[id] = nil
                    fails[id] = (fails[id] or 0) + 1
                    if fails[id] >= 2 then
                        GiveUp(a, "can't be removed, so it is left alone.")
                    end
                end
                if not blocked[id] and RemovesNow(a, nil, "ooc") then
                    -- one per pass: the slots behind it shift once it goes
                    if Cancel(a, now) then return end
                end
            end
        end
    end
end

-- How often each buff name lands on you in raid fights (account-wide,
-- capped): the in-combat order puts the frequent ones first.
local function Hits()
    if type(ZacUIDB.buffHits) ~= "table" then ZacUIDB.buffHits = {} end
    return ZacUIDB.buffHits
end

local hitsVer = 0            -- moves whenever the counts do
local function Hit(name)
    local h = Hits()
    if h[name] then
        h[name] = h[name] + 1
        hitsVer = hitsVer + 1
        return
    end
    local n = 0
    for _ in pairs(h) do n = n + 1 end
    if n < HITS_MAX then
        h[name] = 1
        hitsVer = hitsVer + 1
    end
end

-- buffs that just arrived: one that keeps coming back right after we
-- cancel it is someone else's aura or totem. Your own buffs are never
-- counted: Bloodthirst is back after every cast, and three quick pulls
-- in a row used to mark it "keeps coming back" and stop it going in
-- combat for the rest of the session.
local function NoteAdded(added, now)
    local raidFight = InCombatLockdown() and IsInRaid and IsInRaid()
    for _, a in ipairs(added) do
        local id = a.id
        if raidFight and a.name then Hit(a.name) end
        local t = id and lastCancel[id]
        if t and now - t < 10 and not blocked[id] and a.src ~= "player" then
            comeback[id] = (comeback[id] or 0) + 1
            if comeback[id] >= 3 then
                GiveUp(a, "keeps coming back (someone's aura or totem), so it is left alone this session.")
            end
        end
    end
end

local seenVer = 0            -- moves whenever an entry is added
local function Seen(a)
    if not a.id then return end
    local s = Cfg().seen
    if s[a.id] then return end
    local n = 0
    for _ in pairs(s) do n = n + 1 end
    if n >= SEEN_MAX then return end
    s[a.id] = { n = a.name, i = a.icon }
    seenVer = seenVer + 1
end

-- ============================================================
-- IN COMBAT: the names the buttons hold
-- ============================================================
-- Salvation while tanking, for a warrior or druid not tanking right now:
-- loaded anyway, marked tank-only, for the buttons to check mid-fight.
local function SalvStandby(e)
    return e.family ~= nil and e.family.salv == true and ClassCfg().salv == true
        and TANK_INDEX[cls] ~= nil
end

-- Every ticked name that no kept buff shares, in this order: the ones on
-- you now, Salvation, the ones that land on you most in raid fights,
-- then the rest. The second result holds the tank-only names.
-- Everything the list below is worked out from, as one string: the
-- ticks (read as they are, since other code may write them directly),
-- the buffs on you, pause, tanking and the session's give-ups. The pull
-- runs this at the very moment of PLAYER_REGEN_DISABLED, so an unchanged
-- answer is handed back instead of being worked out again.
local sigParts = {}
local function CombatSig(ignorePause, BC, D, c)
    local t, n = sigParts, 0
    local function add(v) n = n + 1 t[n] = tostring(v) end
    add(ignorePause and 1 or 0) add(Paused() and 1 or 0) add(Tanking() and 1 or 0)
    add(cls) add(c) add(c.salv) add(D.ALL) add(Cfg().seen) add(seenVer) add(Hits()) add(hitsVer) add(blockedVer)
    add(WorldBuffsUp() and 1 or 0)
    for k, v in pairs(c.remove) do add(k) add(v) add(c.when[k]) add(c.wb[k]) end
    add("|")
    for k, v in pairs(c.names) do add(k) add(v) add(c.whenName[k]) add(c.wbName[k]) end
    add("|")
    for k in pairs(c.keep) do add(k) end
    add("|")
    for _, a in ipairs(BC:List()) do
        add(a.id) add(a.name) add(a.id and pending[a.id] and 1 or 0)
    end
    for i = n + 1, #t do t[i] = nil end
    return table.concat(t, "\031")
end

local combatCache = {}       -- [ignorePause and 1 or 0] = { sig, out, tankOnly }
local function CombatNames(ignorePause)
    local BC, D = RCB(), DATA()
    if not (BC and D) then return {}, {} end
    local c = ClassCfg()
    local sig = CombatSig(ignorePause, BC, D, c)
    local slot = ignorePause and 1 or 0
    local hit = combatCache[slot]
    if hit and hit.sig == sig then return hit.out, hit.tankOnly end
    local keep, want, only, salv, firm = {}, {}, {}, {}, {}
    local paused = not ignorePause and Paused()
    -- only the ticks that go in combat
    local remove, byName = {}, {}
    for k, v in pairs(c.remove) do
        if v == true and Allows(c.when[k], "combat") and WbOk(c.wb[k]) then remove[k] = true end
    end
    for n, v in pairs(c.names) do
        if v == true and Allows(c.whenName[n], "combat") and WbOk(c.wbName[n]) then byName[n] = true end
    end
    if not paused then
        for n in pairs(byName) do want[n] = true end
    end
    for n in pairs(c.keep) do keep[n] = true end
    for _, e in ipairs(D.ALL) do
        if Visible(e) then
            local off = not Fixed(e) and (SalvOff(e) or (not paused and remove[e.key] == true))
            local standby = not off and not Fixed(e) and SalvStandby(e)
            for _, n in ipairs(NamesOf(e)) do
                -- a name ticked by name is not held back by an unticked entry
                if off or standby then
                    want[n] = true
                    if e.family and e.family.salv then salv[#salv + 1] = n end
                    if off then firm[n] = true else only[n] = true end
                elseif not byName[n] then
                    keep[n] = true
                end
            end
        end
    end
    for id, s in pairs(Cfg().seen) do
        if s.n and not D.BY_ID[id] then
            if not paused and remove[id] == true then
                want[s.n] = true
                firm[s.n] = true
            elseif not byName[s.n] then
                keep[s.n] = true
            end
        end
    end
    -- a name wanted for good is never tank-only
    for n in pairs(only) do
        if firm[n] or (byName[n] and not paused) then only[n] = nil end
    end
    -- a buff on you that stays now (Salvation while not tanking) is only
    -- held back if it is not waiting for a tanking form
    for _, a in ipairs(BC:List()) do
        if a.name and not only[a.name] and not RemovesNow(a, ignorePause, "combat") then keep[a.name] = true end
    end
    for id, name in pairs(blocked) do
        local n = type(name) == "string" and name or SpellName(id)
        if n then keep[n] = true end
    end
    local out, used = {}, {}
    local function Take(n)
        if n and want[n] and not keep[n] and not used[n] then
            used[n] = true
            out[#out + 1] = n
        end
    end
    for _, a in ipairs(BC:List()) do
        if not (a.id and pending[a.id]) then Take(a.name) end
    end
    for _, n in ipairs(salv) do Take(n) end
    local hits = {}
    for n, k in pairs(Hits()) do
        if want[n] and type(k) == "number" then hits[#hits + 1] = { n = n, k = k } end
    end
    table.sort(hits, function(x, y)
        if x.k ~= y.k then return x.k > y.k end
        return x.n < y.n
    end)
    for _, h in ipairs(hits) do Take(h.n) end
    local rest = {}
    for n in pairs(want) do rest[#rest + 1] = n end
    table.sort(rest)
    for _, n in ipairs(rest) do Take(n) end
    -- tank-only only for names that made the list
    local tankOnly = {}
    for _, n in ipairs(out) do
        if only[n] then tankOnly[n] = true end
    end
    combatCache[slot] = { sig = sig, out = out, tankOnly = tankOnly }
    return out, tankOnly
end

local function Arm()
    if armed then return end
    MakeButtons()
    armed = true
    for _, b in ipairs(buttons) do
        b:SetAttribute("type", "cancelaura")
        b:SetAttribute("useOnKeyDown", false)
        SecureHandlerWrapScript(b, "OnClick", header, NEXT_NAME)
    end
end

local function Load(lists, only, tankForm)
    if not buttons then return end
    only = only or {}
    for k, b in ipairs(buttons) do
        local names = lists[k] or {}
        local flags = {}
        for j, n in ipairs(names) do flags[j] = only[n] and "t" or "-" end
        local sig = table.concat(names, "\n") .. "\n" .. table.concat(flags) .. "\n" .. tostring(tankForm)
        if sig ~= loaded[k] then
            local old = b:GetAttribute("count") or 0
            for j = 1, math.max(old, #names) do
                b:SetAttribute("name" .. j, names[j])
                b:SetAttribute("tankonly" .. j, (names[j] and only[names[j]]) and true or nil)
            end
            b:SetAttribute("count", #names)
            b:SetAttribute("at", 0)
            b:SetAttribute("tankform", tankForm)
            loaded[k] = sig
        end
    end
end

-- Where a marker line starts in a body (0 = the first line), matching the
-- whole line only.
local function MarkAt(body, m)
    if body == m or body:sub(1, #m + 1) == m .. "\n" then return 0 end
    local at = body:find("\n" .. m .. "\n", 1, true)
    if at then return at end
    if #body > #m and body:sub(-(#m + 1)) == "\n" .. m then return #body - #m end
    return nil
end

-- the user's own part of a macro (everything above our marker, old or new)
local function UserPart(body)
    body = body or ""
    local cut
    for _, m in ipairs(MARKS) do
        local at = MarkAt(body, m)
        if at and (not cut or at < cut) then cut = at end
    end
    if cut == 0 then return "" end
    if cut then return body:sub(1, cut - 1) end
    return body
end

-- true when a macro body carries our lines (old marker or new)
function BR.HasMark(body)
    return UserPart(body) ~= (body or "")
end

-- EVERY macro called that: the account one and this character's own. A
-- name is often both (an account "BT" and a character "BT"), and the game's
-- by-name lookup only ever finds the account one - so the copy actually on
-- this character's bars went without the lines. Account ones first.
-- From the shared macro map (one walk per UPDATE_MACROS, not one walk per
-- linked macro per Sync); the list is shared and read-only.
local NO_MACROS = {}
local function MacroIndexes(name)
    return (name and ns.Macros.FindAll(name)) or NO_MACROS
end

local function ClickLines(n)
    local t = {}
    for i = 1, n do t[i] = "/click " .. ButtonName(i) end
    return table.concat(t, "\n")
end

-- Out of combat only: the macros' lines and the buttons' names.
local syncedTanking = nil   -- Tanking() as the last Sync saw it
local function Sync()
    if not running or InCombatLockdown() then return end
    syncedTanking = Tanking()
    Arm()
    local useCombat = Cfg().combat
    local full, only = {}, {}
    if useCombat then full, only = CombatNames(true) end
    local names = full
    if useCombat and Paused() then names, only = CombatNames() end
    local lines = math.min(BUTTONS, #full)
    local found, missing = {}, {}
    status.limit = nil
    for _, name in ipairs(Char().macros) do
        local list = MacroIndexes(name)
        if #list == 0 then missing[name] = true end
        for _, idx in ipairs(list) do
            local mName, icon, body = GetMacroInfo(idx)
            local user = UserPart(body)
            local head = (user ~= "" and "\n" or "") .. MARK .. "\n"
            local room = math.floor((MACRO_LIMIT - #user - #head + 1) / LINE_LEN)
            if room < lines then
                lines = math.max(0, room)
                status.limit = name
            end
            found[#found + 1] = { idx = idx, name = mName, icon = icon, body = body or "", user = user, head = head }
        end
    end
    if #found == 0 then lines = 0 end
    for _, m in ipairs(found) do
        local new = m.user
        if lines > 0 then new = m.user .. m.head .. ClickLines(lines) end
        if new ~= m.body then EditMacro(m.idx, m.name, m.icon, new) end
    end
    status.names = #full
    status.missing = missing
    status.lines = lines
    -- Bloodthirst on a button of its own (when there are two or more):
    -- sharing one, it went only on every other press
    local bt
    if lines >= 2 and cls == "WARRIOR" then
        local btName = SpellName(BLOODTHIRST_ID)
        for _, n in ipairs(names) do
            if (n == btName or n == "Bloodthirst") and not only[n] then bt = n end
        end
    end
    status.ownButton = bt
    local lists = {}
    for i = 1, lines do lists[i] = {} end
    local first, span = 1, lines
    if bt then
        lists[1][1] = bt
        first, span = 2, lines - 1
    end
    if lines > 0 then
        local j = 0
        for _, n in ipairs(names) do
            if n ~= bt then
                j = j + 1
                local k = first + (j - 1) % span
                lists[k][#lists[k] + 1] = n
            end
        end
    end
    Load(lists, only, TANK_INDEX[cls])
end

function BR.Status() return status end

local function Unlink(name)
    if not name or InCombatLockdown() then return end
    for _, idx in ipairs(MacroIndexes(name)) do
        local mName, icon, body = GetMacroInfo(idx)
        local user = UserPart(body)
        if user ~= body then EditMacro(idx, mName, icon, user) end
    end
end

function BR.IsLinked(name)
    for _, n in ipairs(Char().macros) do
        if n == name then return true end
    end
    return false
end

function BR.Link(name)
    if InCombatLockdown() then return "combat" end
    if not name or name == "" then return "none" end
    local list = Char().macros
    if BR.IsLinked(name) then return "linked" end
    if #list >= MAX_LINKED then return "full" end
    list[#list + 1] = name
    Sync()
    return "ok"
end

function BR.Unlink(name)
    if InCombatLockdown() then return "combat" end
    local list = Char().macros
    for i, n in ipairs(list) do
        if n == name then
            table.remove(list, i)
            break
        end
    end
    Unlink(name)
    Sync()
    return "ok"
end

-- Empties the buttons and takes our lines out of every linked macro.
-- False in combat (nothing can change then); the caller retries after.
local function Shutdown()
    if InCombatLockdown() then return false end
    Load({})
    for _, name in ipairs(Char().macros) do Unlink(name) end
    return true
end

-- ============================================================
-- THE HOOK ON READYCHECK'S COUNTER
-- ============================================================
local function Changed()
    local BC = RCB()
    if BC then BC:Request() end
    if not InCombatLockdown() then Sync() end
end
BR.Changed = Changed

function BR.SetRemove(key, on)
    local c = ClassCfg()
    c.remove[key] = on and true or nil
    -- a fresh tick starts at both
    c.when[key] = nil
    c.wb[key] = nil
    Changed()
end

function BR.SetWhen(key, mode)
    local c = ClassCfg()
    c.when[key] = WhenValue(mode)
    c.wb[key] = WbValue(mode)
    Changed()
end

function BR.SetPhase(key, mode)
    ClassCfg().when[key] = WhenValue(mode)
    Changed()
end
function BR.SetWb(key, on)
    ClassCfg().wb[key] = on and true or nil
    Changed()
end
function BR.SetPhaseName(name, mode)
    if type(name) ~= "string" then return end
    ClassCfg().whenName[name] = WhenValue(mode)
    Changed()
end
function BR.SetWbName(name, on)
    if type(name) ~= "string" then return end
    ClassCfg().wbName[name] = on and true or nil
    Changed()
end

function BR.SetWhenName(name, mode)
    if type(name) ~= "string" then return end
    local c = ClassCfg()
    c.whenName[name] = WhenValue(mode)
    c.wbName[name] = WbValue(mode)
    Changed()
end

-- name ticks; a name ticked to go is no longer kept, and the other way
function BR.SetName(name, on)
    if type(name) ~= "string" or name == "" then return end
    local c = ClassCfg()
    c.names[name] = on and true or nil
    c.whenName[name] = nil
    c.wbName[name] = nil
    if on then c.keep[name] = nil end
    Changed()
end

function BR.SetKeep(name, on)
    if type(name) ~= "string" or name == "" then return end
    local c = ClassCfg()
    c.keep[name] = on and true or nil
    if on then
        c.names[name] = nil
        c.whenName[name] = nil
        c.wbName[name] = nil
    end
    Changed()
end

-- ============================================================
-- TAKING OVER A MACRO'S /cancelaura LINES
-- ============================================================
-- A plain "/cancelaura Name" line (not one with [conditions]): the name.
local function CancelauraName(line)
    local low = line:lower()
    if not low:find("^%s*/cancelaura%s") then return nil end
    local name = line:match("^%s*/[Cc][Aa][Nn][Cc][Ee][Ll][Aa][Uu][Rr][Aa]%s+(.-)%s*$")
    if not name or name == "" or name:find("[", 1, true) then return nil end
    return name
end

local function IsSalvation(name)
    return type(name) == "string" and name:lower():find("salvation", 1, true) ~= nil
end

-- Every name a macro body cancels with plain /cancelaura lines, and the
-- body without them. Salvation lines are never taken: they belong to
-- that one macro (a tank Bloodthirst drops Salvation, the DPS one must
-- not), and every linked macro shares one list - a Salvation tick would
-- reach them all.
local function SplitCancelauras(body)
    local names, kept = {}, {}
    for line in ((body or "") .. "\n"):gmatch("([^\n]*)\n") do
        local n = CancelauraName(line)
        if n and not IsSalvation(n) then names[#names + 1] = n else kept[#kept + 1] = line end
    end
    return names, table.concat(kept, "\n")
end

-- Hands the /cancelaura lines of the named macros (default: every
-- linked one) to the remover. Out of combat only. Returns the names
-- taken (kept names are dropped, not ticked) and the macros changed.
function BR.TakeOver(list)
    if InCombatLockdown() then return nil, "combat" end
    local ch, c = Char(), ClassCfg()
    list = list or ch.macros
    local took, changed = {}, {}
    -- a name the list knows becomes that entry's own tick (so it shows,
    -- ticked, under its category); only the rest are ticked by name
    local byName = {}
    local D = DATA()
    if D then
        for _, e in ipairs(D.ALL) do
            if Visible(e) and not Fixed(e) then
                if not byName[e.name] then byName[e.name] = e.key end
                for _, nm in ipairs(NamesOf(e)) do
                    if not byName[nm] then byName[nm] = e.key end
                end
            end
        end
    end
    local maxA = MAX_ACCOUNT_MACROS or 120
    for _, name in ipairs(list) do
        for _, idx in ipairs(MacroIndexes(name)) do
            local mName, icon, body = GetMacroInfo(idx)
            local user = UserPart(body)
            local names, rest = SplitCancelauras(user)
            if #names > 0 then
                local bk = Backups()
                -- a character's own copy is kept apart from the account one
                local bkey = idx > maxA and (mName .. CHAR_COPY) or mName
                if bk[bkey] == nil then bk[bkey] = user end
                for _, n in ipairs(names) do
                    if not c.keep[n] then
                        local key = byName[n]
                        if key then
                            if not c.remove[key] then took[#took + 1] = n end
                            c.remove[key] = true
                        else
                            if not c.names[n] then took[#took + 1] = n end
                            c.names[n] = true
                        end
                    end
                end
                local tail = body:sub(#user + 1)
                EditMacro(idx, mName, icon, rest .. tail)
                changed[#changed + 1] = mName
            end
        end
    end
    Changed()
    return took, changed
end

function BR.HasBackups() return next(Backups()) ~= nil end

-- Puts every taken-over macro back the way it was and unlinks it.
function BR.RestoreMacros()
    if InCombatLockdown() then return nil, "combat" end
    local ch = Char()
    local done = {}
    local bk = Backups()
    local maxA = MAX_ACCOUNT_MACROS or 120
    for key, body in pairs(bk) do
        local name, charCopy = key, false
        if key:sub(-#CHAR_COPY) == CHAR_COPY then
            name, charCopy = key:sub(1, -#CHAR_COPY - 1), true
        end
        for i, n in ipairs(ch.macros) do
            if n == name then
                table.remove(ch.macros, i)
                break
            end
        end
        for _, idx in ipairs(MacroIndexes(name)) do
            if (idx > maxA) == charCopy then
                local mName, icon = GetMacroInfo(idx)
                EditMacro(idx, mName, icon, body)
                done[#done + 1] = name
                break
            end
        end
        bk[key] = nil
    end
    Changed()
    return done
end

-- Puts back the Salvation /cancelaura lines an earlier takeover moved
-- out (it used to take them with the rest), from the kept copy of each
-- macro. Returns the macros fixed.
function BR.RestoreSalvationLines()
    if InCombatLockdown() then return nil, "combat" end
    local maxA = MAX_ACCOUNT_MACROS or 120
    local fixed = {}
    for key, old in pairs(Backups()) do
        local name, charCopy = key, false
        if key:sub(-#CHAR_COPY) == CHAR_COPY then
            name, charCopy = key:sub(1, -#CHAR_COPY - 1), true
        end
        local salv = {}
        for line in ((old or "") .. "\n"):gmatch("([^\n]*)\n") do
            if IsSalvation(CancelauraName(line)) then salv[#salv + 1] = line end
        end
        if #salv > 0 then
            for _, idx in ipairs(MacroIndexes(name)) do
                if (idx > maxA) == charCopy then
                    local mName, icon, body = GetMacroInfo(idx)
                    local user = UserPart(body)
                    local add = {}
                    for _, line in ipairs(salv) do
                        if not user:find(line, 1, true) then add[#add + 1] = line end
                    end
                    if #add > 0 then
                        local newUser = user .. (user ~= "" and "\n" or "") .. table.concat(add, "\n")
                        EditMacro(idx, mName, icon, newUser .. body:sub(#user + 1))
                        fixed[#fixed + 1] = mName
                    end
                    break
                end
            end
        end
    end
    Changed()
    return fixed
end

-- ============================================================
-- LINKING THE ATTACK MACROS BY ITSELF
-- ============================================================
-- The spells a class presses all fight, most-pressed first. A macro ON
-- THE BARS that casts one of them is an attack macro worth linking.
local ATTACKS = {
    WARRIOR = { "Bloodthirst", "Whirlwind", "Sunder Armor", "Heroic Strike", "Cleave",
                "Execute", "Mortal Strike", "Revenge", "Shield Slam" },
}
BR.ATTACKS = ATTACKS

-- the spells a macro casts (/cast and /use lines, conditions, ranks and
-- the ! stripped), lower-cased
local function CastsOf(body)
    local out = {}
    for line in ((body or "") .. "\n"):gmatch("([^\n]*)\n") do
        local rest = line:match("^%s*/[Cc][Aa][Ss][Tt]%s+(.*)$") or line:match("^%s*/[Uu][Ss][Ee]%s+(.*)$")
        if rest then
            for part in (rest .. ";"):gmatch("([^;]*);") do
                local sp = part:gsub("%b[]", ""):gsub("%(.-%)", ""):gsub("^%s*!?", ""):gsub("%s+$", "")
                if sp ~= "" then out[sp:lower()] = true end
            end
        end
    end
    return out
end

-- The macro names on this character's bars that cast its class's attack
-- spells, in the ATTACKS order (then by how many buttons hold them).
function BR.AttackMacros()
    local list = ATTACKS[select(2, UnitClass("player")) or ""]
    if not (list and GetMacroInfo) then return {} end
    local rank = {}
    for i, sp in ipairs(list) do rank[sp:lower()] = i end
    local best, count = {}, {}
    local At = ns.ActionSlots.At
    for slot = 1, 120 do
        local kind, id = At(slot)
        if kind == "macro" and id then
            local name, _, body = GetMacroInfo(id)
            if name and name ~= "" then
                local r
                for sp in pairs(CastsOf(UserPart(body))) do
                    if rank[sp] and (not r or rank[sp] < r) then r = rank[sp] end
                end
                if r then
                    if not best[name] or r < best[name] then best[name] = r end
                    count[name] = (count[name] or 0) + 1
                end
            end
        end
    end
    local out = {}
    for name in pairs(best) do out[#out + 1] = name end
    table.sort(out, function(a, b)
        if best[a] ~= best[b] then return best[a] < best[b] end
        if count[a] ~= count[b] then return count[a] > count[b] end
        return a < b
    end)
    return out
end

-- Links the attack macros on the bars (keeping the links already made)
-- and, with takeover, hands every linked macro's /cancelaura lines to
-- the remover. Salvation lines stay in their own macro (see
-- SplitCancelauras). Out of combat only. Returns the names newly
-- linked, the names taken over and the macros changed, or nil + why.
function BR.AutoLink(takeover)
    if InCombatLockdown() then return nil, "combat" end
    local ch, c = Char(), ClassCfg()
    local added = {}
    for _, name in ipairs(BR.AttackMacros()) do
        if #ch.macros >= MAX_LINKED then break end
        if not BR.IsLinked(name) then
            ch.macros[#ch.macros + 1] = name
            added[#added + 1] = name
        end
    end
    local took, changed = {}, {}
    if takeover and #ch.macros > 0 then
        took, changed = BR.TakeOver(ch.macros)
        took, changed = took or {}, changed or {}
    end
    Changed()
    return added, took, changed
end

-- ============================================================
-- IMPORT / EXPORT - one line of plain text
-- ============================================================
local HEADER = "ZacUIBuffs:1:"
BR.HEADER = HEADER

local function SortedKeys(t)
    local out = {}
    for k, v in pairs(t) do if v then out[#out + 1] = k end end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

-- , ; = separate the fields, so they are dropped from names
local function SafeName(n) return (tostring(n):gsub("[,;=\r\n]", " "):gsub("%s+", " ")) end

function BR.Export()
    local c = ClassCfg()
    local parts = { (cls or select(2, UnitClass("player")) or "?") }
    local ids = SortedKeys(c.remove)
    for i, v in ipairs(ids) do ids[i] = tostring(v) end
    parts[#parts + 1] = "remove=" .. table.concat(ids, ",")
    local names = SortedKeys(c.names)
    for i, v in ipairs(names) do names[i] = SafeName(v) end
    parts[#parts + 1] = "names=" .. table.concat(names, ",")
    local keep = SortedKeys(c.keep)
    for i, v in ipairs(keep) do keep[i] = SafeName(v) end
    parts[#parts + 1] = "keep=" .. table.concat(keep, ",")
    -- per-tick timing other than both: id:o / id:c, name:o / name:c
    local wid, wname = {}, {}
    for _, k in ipairs(SortedKeys(c.when)) do
        if c.remove[k] then wid[#wid + 1] = tostring(k) .. ":" .. (c.when[k] == "ooc" and "o" or "c") end
    end
    for _, n in ipairs(SortedKeys(c.whenName)) do
        if c.names[n] then wname[#wname + 1] = SafeName(n) .. ":" .. (c.whenName[n] == "ooc" and "o" or "c") end
    end
    if #wid > 0 then parts[#parts + 1] = "wid=" .. table.concat(wid, ",") end
    if #wname > 0 then parts[#parts + 1] = "wname=" .. table.concat(wname, ",") end
    -- held to world buffs: wbid=123,456  wbname=Name,Name
    local bid, bname = {}, {}
    for _, k in ipairs(SortedKeys(c.wb)) do if c.remove[k] then bid[#bid + 1] = tostring(k) end end
    for _, n in ipairs(SortedKeys(c.wbName)) do if c.names[n] then bname[#bname + 1] = SafeName(n) end end
    if #bid > 0 then parts[#parts + 1] = "wbid=" .. table.concat(bid, ",") end
    if #bname > 0 then parts[#parts + 1] = "wbname=" .. table.concat(bname, ",") end
    parts[#parts + 1] = "salv=" .. (c.salv and "1" or "0")
    local macros = {}
    for i, v in ipairs(Char().macros) do macros[i] = SafeName(v) end
    parts[#parts + 1] = "macros=" .. table.concat(macros, ",")
    if BR.HasBackups() then parts[#parts + 1] = "takeover=1" end
    return HEADER .. table.concat(parts, ";")
end

local function List(v)
    local out = {}
    for item in (v or ""):gmatch("[^,]+") do
        item = item:gsub("^%s+", ""):gsub("%s+$", "")
        if item ~= "" then out[#out + 1] = item end
    end
    return out
end

-- Reads a string into a plain table, or nil and why not. Nothing in it
-- is run: it is split on ; , and = and that is all.
function BR.Decode(text)
    if type(text) ~= "string" then return nil, "nothing to read" end
    text = text:gsub("[\r\n]+", " ")
    if text:sub(1, #HEADER) ~= HEADER then return nil, "not a ZacUI buff string" end
    local body = text:sub(#HEADER + 1)
    if #body > 20000 then return nil, "the string is far too long to be a buff setup" end
    local d = { remove = {}, names = {}, keep = {}, macros = {}, when = {}, whenName = {}, wb = {}, wbName = {} }
    local first = true
    for field in (body .. ";"):gmatch("([^;]*);") do
        field = field:gsub("^%s+", ""):gsub("%s+$", "")
        if first then
            first = false
            if not field:find("^%u+$") then return nil, "the string is damaged - copy it again, all of it" end
            d.class = field
        elseif field ~= "" then
            local k, v = field:match("^(%l+)%s*=%s*(.*)$")
            if not k then return nil, "the string is damaged - copy it again, all of it" end
            if k == "remove" then
                for _, x in ipairs(List(v)) do
                    local n = tonumber(x)
                    if not n or n ~= math.floor(n) or n <= 0 then return nil, "the string is damaged - copy it again, all of it" end
                    d.remove[#d.remove + 1] = n
                end
            elseif k == "names" then d.names = List(v)
            elseif k == "wid" or k == "wname" then
                for _, x in ipairs(List(v)) do
                    local key, m = x:match("^(.-)%s*:%s*([oc])$")
                    if key and key ~= "" then
                        local mode = (m == "o") and "ooc" or "combat"
                        if k == "wid" then
                            local n = tonumber(key)
                            if n then d.when[n] = mode end
                        else
                            d.whenName[key] = mode
                        end
                    end
                end
            elseif k == "wbid" then
                for _, x in ipairs(List(v)) do local n = tonumber(x) if n then d.wb[n] = true end end
            elseif k == "wbname" then
                for _, x in ipairs(List(v)) do d.wbName[x] = true end
            elseif k == "keep" then d.keep = List(v)
            elseif k == "macros" then d.macros = List(v)
            elseif k == "salv" then d.salv = (v == "1")
            elseif k == "takeover" then d.takeover = (v == "1")
            end
        end
    end
    if not d.class then return nil, "the string is damaged - copy it again, all of it" end
    if #d.macros > MAX_LINKED then
        for i = #d.macros, MAX_LINKED + 1, -1 do d.macros[i] = nil end
    end
    return d
end

local function ClassLabel(c)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or (c:sub(1, 1) .. c:sub(2):lower())
end

-- For the import boxes: what the string carries and what applying does.
function BR.Describe(text)
    local d, err = BR.Decode(text)
    if not d then return nil, err end
    local lines = {}
    lines[1] = ClassLabel(d.class) .. ": " .. (#d.remove + #d.names) .. " buff(s) to remove"
        .. (#d.keep > 0 and (", always keep " .. table.concat(d.keep, ", ")) or "")
    if #d.macros > 0 then
        lines[2] = "Macros: " .. table.concat(d.macros, ", ")
            .. (d.takeover and " (their /cancelaura lines move into the remover)" or "")
    end
    return d, lines
end

-- mode "all": ticks, macros, takeover. "ticks": the ticks only. Both
-- replace the class's ticks with the string's. "merge": like "all" but
-- adds to the ticks already there (a second character on an account
-- whose macros were already taken over keeps what the first took).
-- Returns ok, message.
function BR.ApplyImport(text, mode)
    local d, err = BR.Decode(text)
    if not d then return false, err end
    local useMacros = mode ~= "ticks" and #d.macros > 0
    if useMacros and InCombatLockdown() then return false, "not in combat - macros cannot change in a fight" end
    local b = Cfg()
    local c = b.classes[d.class]
    if type(c) ~= "table" then
        c = {}
        b.classes[d.class] = c
    end
    if mode == "merge" then
        if type(c.remove) ~= "table" then c.remove = {} end
        if type(c.names) ~= "table" then c.names = {} end
        if type(c.keep) ~= "table" then c.keep = {} end
        if type(c.when) ~= "table" then c.when = {} end
        if type(c.whenName) ~= "table" then c.whenName = {} end
        if type(c.wb) ~= "table" then c.wb = {} end
        if type(c.wbName) ~= "table" then c.wbName = {} end
    else
        c.remove, c.names, c.keep, c.when, c.whenName, c.wb, c.wbName = {}, {}, {}, {}, {}, {}, {}
    end
    -- merge keeps a "when" already chosen here unless the string sets one
    local merge = mode == "merge"
    for _, id in ipairs(d.remove) do
        c.remove[id] = true
        if not merge or d.when[id] ~= nil then c.when[id] = d.when[id] end
        if not merge or d.wb[id] then c.wb[id] = d.wb[id] end
    end
    for _, n in ipairs(d.names) do
        c.names[n] = true
        if not merge or d.whenName[n] ~= nil then c.whenName[n] = d.whenName[n] end
        if not merge or d.wbName[n] then c.wbName[n] = d.wbName[n] end
    end
    for _, n in ipairs(d.keep) do
        c.keep[n] = true
        c.names[n] = nil
    end
    if d.salv ~= nil then c.salv = d.salv end
    if c.salv == nil then c.salv = TANK_CLASSES[d.class] or false end
    b.enabled = true
    local msg = ClassLabel(d.class) .. ": " .. (#d.remove + #d.names) .. " buff(s) set to go"
        .. (#d.keep > 0 and (", " .. table.concat(d.keep, ", ") .. " always kept") or "") .. "."
    local myClass = select(2, UnitClass("player"))
    if useMacros and d.class == myClass then
        local ch = Char()
        local linked, missing = {}, {}
        for _, name in ipairs(d.macros) do
            local idx = GetMacroIndexByName(name)
            if not idx or idx == 0 then
                missing[#missing + 1] = name
            elseif not BR.IsLinked(name) and #ch.macros < MAX_LINKED then
                ch.macros[#ch.macros + 1] = name
                linked[#linked + 1] = name
            elseif BR.IsLinked(name) then
                linked[#linked + 1] = name
            end
        end
        if #linked > 0 then msg = msg .. " Linked " .. table.concat(linked, ", ") .. "." end
        if #missing > 0 then msg = msg .. " No macro called " .. table.concat(missing, ", ") .. " here." end
        if d.takeover and #linked > 0 then
            local took, changed = BR.TakeOver(linked)
            if changed and #changed > 0 then
                msg = msg .. " Moved the /cancelaura lines out of " .. table.concat(changed, ", ")
                    .. " (Buffs tab > Put my macros back undoes it)."
            end
        end
    elseif useMacros then
        msg = msg .. " Macros were not linked: this character is not a " .. ClassLabel(d.class) .. "."
    end
    if QoL.BuffRemoverRefresh then QoL.BuffRemoverRefresh() end
    Changed()
    return true, msg
end

function BR.Paused() return Paused() end

function BR.SetPaused(on)
    Char().paused = on and true or nil
    if on then
        Print("buffs: removal paused." .. (ClassCfg().salv and TANK_CLASSES[cls]
            and " Salvation still goes while you tank." or ""))
    else
        Print("buffs: removal resumed.")
    end
    if InCombatLockdown() then Print("buffs: your macros follow when this fight ends.") end
    Changed()
end

local API = {
    name = "ZacUI",
    State = State,
    Toggle = function(a)
        -- matched by name (a tier-set proc): its tick is a name tick
        if a.e and a.e.byName then
            BR.SetName(a.e.name, not Removes(a))
            return
        end
        local key = KeyOf(a)
        if key == nil or (a.e and Fixed(a.e)) then return end
        local c = ClassCfg()
        if Removes(a) then
            -- off: whatever ticked it (the tick and a name tick)
            c.remove[key] = nil
            c.when[key] = nil
            if a.name then
                c.names[a.name] = nil
                c.whenName[a.name] = nil
            end
        else
            if a.name then c.keep[a.name] = nil end
            c.remove[key] = true
            c.when[key] = nil
        end
        Changed()
    end,
    Paused = Paused,
    SetPaused = function(on) BR.SetPaused(on) end,
    RecentlyCancelled = function(id, now)
        local t = lastCancel[id]
        return t ~= nil and now - t < 3
    end,
    NoteAdded = NoteAdded,
    Seen = Seen,
}

local function OnCount()
    if not running then return end
    Plan()
end

-- (where there is no buff limit, Core_Flavor's buff_remover, nothing
-- here loads: no frames, no events, the page has no Buffs tab; the saved
-- ticks and linked macros are left exactly as they are)
local OFF_HERE = ns.FeatureOn and not ns.FeatureOn("buff_remover")
local events = OFF_HERE and ns.FlavorNullFrame or CreateFrame("Frame")
local cleanupLater = false
local macroSyncPending = false
local formSyncPending = false

local function Start()
    local BC = RCB()
    if running or not BC then return end
    running = true
    cls = select(2, UnitClass("player"))
    race = select(2, UnitRace("player"))
    for k in pairs(pending) do pending[k] = nil end
    for k in pairs(lastCancel) do lastCancel[k] = nil end
    for k in pairs(fails) do fails[k] = nil end
    for k in pairs(comeback) do comeback[k] = nil end
    for k in pairs(blocked) do blocked[k] = nil end
    blockedVer = blockedVer + 1
    BC:SetRemover(API)
    BC:Subscribe("zacuiRemover", OnCount)
    BC:Want("zacuiRemover", true)
    BC:Refresh()
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("UPDATE_MACROS")
    events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    Sync()
end

local function Stop()
    if not running then return end
    running = false
    local BC = RCB()
    if BC then
        if BC:Remover() == API then BC:SetRemover(nil) end
        BC:Subscribe("zacuiRemover", nil)
        BC:Want("zacuiRemover", false)
    end
    events:UnregisterEvent("UPDATE_MACROS")
    events:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
    events:UnregisterEvent("PLAYER_REGEN_DISABLED")
    if Shutdown() then
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    else
        cleanupLater = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if cleanupLater and not running then
            if Shutdown() then
                cleanupLater = false
                events:UnregisterEvent("PLAYER_REGEN_ENABLED")
            end
            return
        end
        Sync()
        -- a fresh read first (Plan runs from it): slots may have moved
        local BC = RCB()
        if BC then BC:Refresh() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- the last moment the buttons and macros can change before the
        -- fight: load what is on you now
        local BC = RCB()
        if BC then BC:Refresh() end
        Sync()
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        -- into or out of a tanking form decides Salvation. The event also
        -- comes for stance-bar bookkeeping with nothing changed, and a
        -- Sync reads every macro slot per linked macro, so it waits half
        -- a second and runs only when the tanking state is not the one
        -- the last Sync saw.
        if formSyncPending or InCombatLockdown() then return end
        formSyncPending = true
        C_Timer.After(0.5, function()
            formSyncPending = false
            if running and not InCombatLockdown() and Tanking() ~= syncedTanking then Sync() end
        end)
    elseif event == "UPDATE_MACROS" then
        -- a macro edited by hand: put our lines back once things settle
        -- (our own edit fires this too and then finds nothing to change)
        if macroSyncPending or InCombatLockdown() then return end
        macroSyncPending = true
        C_Timer.After(0.5, function()
            macroSyncPending = false
            Sync()
        end)
    end
end)

-- Called on login and by QoL.Refresh after any change on the page.
function BR.Refresh()
    -- where the feature is off (Core_Flavor), or Readycheck's counter does
    -- not run on this game version, it stands down and the macros are left
    -- as they are
    if (ns.FeatureOn and not ns.FeatureOn("buff_remover")) or not CounterHere() then
        Stop()
        return
    end
    if QoL.enabled and Cfg().enabled and RCB() then
        if running then
            Changed()
        else
            Start()
        end
    else
        Stop()
        -- off since last session (or Readycheck missing): lines it left in
        -- linked macros would only waste room
        if not running and not cleanupLater and not InCombatLockdown() then
            for _, name in ipairs(Char().macros) do Unlink(name) end
        end
    end
end
QoL.BuffRemoverRefresh = BR.Refresh
function BR.Running() return running end
function BR.HasCounter() return RCB() ~= nil end

-- ============================================================
-- ONE-TIME SETUPS - a setup string for one named character, applied
-- once by itself at login (out of combat, once that character's macros
-- have loaded) and never again: ZacUICharDB.buffRemover.applied holds
-- the ids already done. Applying goes through the same import as the
-- Import box, so the macros change through the game's own EditMacro
-- and only their plain /cancelaura lines come out.
-- ============================================================
local ONE_TIME = {
    -- every warrior: the BT / Sunder / WW cancels, Fire Shield (Oil of
    -- Immolation's buff has the same name) always kept; each account's
    -- own /cancelaura lines in those macros are added on top
    {
        id = "warriors-bt-sunder-ww-2026-10-09",
        class = "WARRIOR",
        text = "ZacUIBuffs:1:WARRIOR;remove=23028,27681,9910,27683,5697,25890,10060,552;"
            .. "names=Argent Dawn Commission,Bloodthirst,Snowball;keep=Fire Shield;salv=1;"
            .. "macros=BT,Sunder,WW;takeover=1",
    },
    -- every warrior: the 30-minute single-target versions Zac ticked on
    -- Zacw (Arcane Intellect, Divine Spirit) and the healers' tier-set
    -- procs; added to what is there, macros untouched
    {
        id = "warriors-30min-tier-2026-10-09",
        class = "WARRIOR",
        text = "ZacUIBuffs:1:WARRIOR;remove=10157,27841;"
            .. "names=Holy Power,Armor of Faith,Totemic Power,Blessing of the Claw;keep=Fire Shield",
    },
    -- every warrior: Regrowth, and both Shadow Protections (the
    -- 10-minute single one and the 20-minute Prayer); added on top
    {
        id = "warriors-rejuv-shadowprot-2026-10-09",
        class = "WARRIOR",
        text = "ZacUIBuffs:1:WARRIOR;remove=9858,10958,27683;keep=Fire Shield",
    },
    -- the setup above first ticked Rejuvenation by mistake; Regrowth was
    -- meant. Once per account (the ticks are shared by every warrior on
    -- it), so a later choice on one warrior is never undone by another.
    {
        id = "warriors-regrowth-not-rejuv-2026-10-09",
        class = "WARRIOR",
        account = true,
        untick = { 25299 },
        tick = { 9858 },
    },
    -- every character: the target dummy macro, exactly this
    {
        id = "dummy-macro-2026-10-09",
        macro = {
            name = "dummy", icon = 134400,
            body = "#showtooltip Masterwork Target DUmmy\n/stopattack\n/stopcasting\n"
                .. "/cast [@cursor] Masterwork Target Dummy",
        },
    },
}

local function MacrosLoaded()
    if not GetNumMacros then return true end
    local a, c = GetNumMacros()
    return ((a or 0) + (c or 0)) > 0
end

-- The macro by that name made exactly so: its body set if it differs, or
-- made as an account macro (a character macro when the account's are
-- full). Returns what it did.
local function EnsureMacro(m)
    local idx = GetMacroIndexByName(m.name)
    if idx and idx ~= 0 then
        local mName, icon, body = GetMacroInfo(idx)
        if body == m.body then return "already" end
        EditMacro(idx, mName, icon, m.body)
        return "updated"
    end
    if not CreateMacro then return "failed" end
    local a, c = 0, 0
    if GetNumMacros then a, c = GetNumMacros() end
    local maxA = MAX_ACCOUNT_MACROS or 120
    local maxC = MAX_CHARACTER_MACROS or 18
    -- a new macro moves the indexes after it: the shared maps are read
    -- again (the setups that follow look macros up in the same frame)
    if (a or 0) < maxA then
        CreateMacro(m.name, m.icon, m.body, nil)
        ns.Macros.Invalidate()
        ns.ActionSlots.Invalidate()
        return "made"
    elseif (c or 0) < maxC then
        CreateMacro(m.name, m.icon, m.body, true)
        ns.Macros.Invalidate()
        ns.ActionSlots.Invalidate()
        return "made for this character (the account's macros are full)"
    end
    return "no room (account and character macros are full)"
end

local function OneTimeSetups(tries)
    tries = tries or 0
    if not QoL.enabled then return end
    if InCombatLockdown() or not MacrosLoaded() then
        if tries < 60 then C_Timer.After(2, function() OneTimeSetups(tries + 1) end) end
        return
    end
    local myClass = select(2, UnitClass("player"))
    local ch = Char()
    if type(ch.applied) ~= "table" then ch.applied = {} end
    for _, setup in ipairs(ONE_TIME) do
        if not ch.applied[setup.id] then
            if setup.macro then
                ch.applied[setup.id] = true
                local did = EnsureMacro(setup.macro)
                if did ~= "already" then Print("macros: '" .. setup.macro.name .. "' " .. did .. ".") end
            elseif setup.untick or setup.tick then
                if setup.class == myClass then
                    ch.applied[setup.id] = true
                    local b = Cfg()
                    if type(b.applied) ~= "table" then b.applied = {} end
                    if not (setup.account and b.applied[setup.id]) then
                        b.applied[setup.id] = true
                        local c = ClassCfg()
                        for _, key in ipairs(setup.untick or {}) do c.remove[key] = nil end
                        for _, key in ipairs(setup.tick or {}) do c.remove[key] = true end
                        Changed()
                        Print("buffs: Regrowth now goes instead of Rejuvenation.")
                    end
                end
            elseif setup.text and setup.class == myClass and RCB() then
                ch.applied[setup.id] = true
                local ok, msg = BR.ApplyImport(setup.text, "merge")
                Print("buffs: " .. (ok and "set up for you. " or "setup failed: ") .. tostring(msg or ""))
            end
        end
    end
end

-- PLAYER_ENTERING_WORLD comes after the apply pass at login, so
-- QoL.enabled is settled by then (the same as the raid modes).
if not OFF_HERE then
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    BR.Refresh()
    -- a moment later, so the macros are surely in
    C_Timer.After(3, function() OneTimeSetups(0) end)
end)
end
