-- HUD_Hesitation - the button you are sitting on. In combat each watched
-- ability is checked ten times a second: off cooldown, the global
-- cooldown free, enough rage (IsUsableSpell, which also covers the
-- stance), a living enemy target in range. When all of that has been
-- true for longer than the grace time and you still have not pressed
-- it, the alert goes up - a big "BT NOOB" above the active buff row (or
-- wherever it is dragged) and a cooldown row over the target's nameplate -
-- and stays until you press it or it stops being pressable. Every press
-- is timed from the moment it became pressable; the late ones are
-- counted and summed, and the fight's worst offenders are printed when
-- combat ends.
-- Part of ZacUI; load order is set by the TOC.
-- Perf: UNIT_SPELLCAST_SUCCEEDED is player-filtered and does one table
-- lookup; SPELLS_CHANGED is coalesced; all the reads live in the 0.1 s
-- combat ticker, which stops with combat.
local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end
if not ns.HUD then return end   -- (the part stands down on this game version: HUD_Shared, Core_Flavor)
local HUD = ns.HUD
local UI = ns.UI
local Print = ns.Print
local GetColor = ns.GetColor

ns.Hesitation = ns.Hesitation or {}
local H = ns.Hesitation

local GetTime = GetTime
local GetSpellInfo = GetSpellInfo
-- (WoW Forever: the HUD's reader, which never hands back a hidden cooldown)
local GetSpellCooldown = (issecretvalue ~= nil and ns.HUD and ns.HUD.GetSpellCooldown) or GetSpellCooldown
local IsUsableSpell = IsUsableSpell
local IsSpellInRange = IsSpellInRange
local UnitExists, UnitCanAttack, UnitIsDeadOrGhost = UnitExists, UnitCanAttack, UnitIsDeadOrGhost
local InCombatLockdown = InCombatLockdown
local IsCurrentSpell = IsCurrentSpell
local math_floor, string_format = math.floor, string.format

local GCD_SPELL = 61304     -- Blizzard's dummy "Global Cooldown" spell
local ATTACK_SPELL = 6603   -- Attack: IsCurrentSpell says whether auto-attack is on
-- While an on-next-swing ability is queued, IT is the "current" melee
-- spell and Attack stops answering IsCurrentSpell, so a queued Heroic
-- Strike would read as "not attacking" and silence the alert. Any of
-- these being current counts as swinging.
local ON_SWING = { "Heroic Strike", "Cleave", "Maul", "Raptor Strike" }
local SWING_NAMES = {}
for _, n in ipairs(ON_SWING) do SWING_NAMES[n] = true end
-- Execute phase: when this is usable (target under 20%, rage for it) the
-- watched abilities are the wrong buttons, and nothing is shouted.
local EXECUTE = "Execute"
-- Melee reach, for the abilities that have no range of their own
-- (Whirlwind: IsSpellInRange says nil at any distance, so a crossbow pull
-- started its clock 30 yards out - Zac: "the noob stuff will start before
-- i can actually melee the mob"). The first of these the character knows
-- is the ruler; with none known, nothing changes.
local MELEE_PROXY = { "Hamstring", "Sunder Armor", "Rend", "Heroic Strike", "Bloodthirst",
    "Mortal Strike", "Overpower", "Revenge", "Sinister Strike", "Claw", "Maul" }
local TICK = 0.1
local SOUND_GAP = 2.0       -- never two alert sounds closer than this

-- The abilities a class starts with. Everything is matched by spell
-- NAME (GetSpellInfo by name only answers for spells you know, which is
-- the "do I have it" test for free); the short form is what the alert
-- shouts. Anything else goes in through the custom list.
H.CLASS_DEFAULTS = {
    WARRIOR = { "Bloodthirst", "Whirlwind", "Mortal Strike", "Shield Slam", "Revenge", "Overpower" },
    ROGUE   = { "Riposte", "Ghostly Strike" },
    PALADIN = { "Holy Shock", "Hammer of Justice" },
    SHAMAN  = { "Stormstrike", "Earth Shock" },
    HUNTER  = { "Raptor Strike", "Mongoose Bite", "Aimed Shot", "Multi-Shot" },
    DRUID   = { "Swipe", "Bash" },
    MAGE    = { "Fire Blast", "Cone of Cold" },
    WARLOCK = { "Conflagrate", "Shadowburn" },
    PRIEST  = { "Mind Blast" },
}
H.SHORT = {
    ["Bloodthirst"] = "BT", ["Whirlwind"] = "WW", ["Mortal Strike"] = "MS",
    ["Shield Slam"] = "SS", ["Revenge"] = "REV", ["Overpower"] = "OP",
    ["Execute"] = "EXE", ["Heroic Strike"] = "HS", ["Cleave"] = "CLV",
    ["Stormstrike"] = "SS", ["Earth Shock"] = "ES", ["Mind Blast"] = "MB",
    ["Fire Blast"] = "FB", ["Cone of Cold"] = "CoC", ["Holy Shock"] = "HS",
    ["Hammer of Justice"] = "HoJ", ["Raptor Strike"] = "RS", ["Mongoose Bite"] = "MB",
    ["Aimed Shot"] = "AIM", ["Multi-Shot"] = "MULTI", ["Shadowburn"] = "SB",
    ["Conflagrate"] = "CONF", ["Ghostly Strike"] = "GS", ["Riposte"] = "RIP",
    ["Swipe"] = "SWIPE", ["Bash"] = "BASH",
}
H.STYLES = {
    { key = "noob",  label = "BT NOOB",  fmt = "%s NOOB" },
    { key = "press", label = "PRESS BT", fmt = "PRESS %s" },
    { key = "plain", label = "BT!",      fmt = "%s!" },
}

-- Storage: ZacUIDB.hud.hesitation
local DEFAULTS = {
    enabled = false,             -- off on a fresh install (2026-11-08, Zac); a save that has it keeps it
    grace = 1.0,
    style = "noob",
    showPopup = false,           -- the big alert box; the nameplate row says it now (2026-10-19)
    plateCDs = true,             -- BT/WW cooldowns over the target's nameplate
    plateSoon = 1.5,             -- ...an icon appears this many seconds before it is ready
    plateSize = 30,              -- (24 until 2026-10-20: Zac "bigger by default")
    plateGrow = true,            -- a NOOB icon keeps growing while it is ignored...
    plateGrowMax = 2.0,          -- ...up to this many times its size
    plateRowX = 0, plateRowY = 2, -- the row's fixed spot over a ZacUI plate: its bottom this far above the target box
    plateExecute = true,         -- Execute joins the row while the target is under 20%
    plateExecBoss = false,       -- ...on bosses only
    playSound = false,
    sound = "",                  -- a LibSharedMedia sound name; "" = the raid warning
    tts = false,
    logKeep = 60,                -- fights kept in the log (one record per pull: the log card, /zui noob, the trend)
    onlyAttacking = true,        -- nothing counts unless auto-attack is on
    executeQuiet = true,         -- quiet while Execute is usable
    idle = 8,                    -- quiet after this many seconds without any press (0 = never)
    scale = 1.0,
    x = 0, y = 180,              -- default spot when no HUD aura row exists
    abilities = {},              -- name -> false for an unticked one
    custom = {},                 -- extra spell names
    -- smarter (2026-10-19)
    scorecard = false,           -- the summary as a popup after each pull (off: kept quietly, /zui noob shows it)
    ttkQuiet = 1.5,              -- no call-out on a mob about to die in under this many seconds (0 = off; never bosses)
    execBTap = 2000,             -- in execute range, Bloodthirst still beats Execute from this much attack power (0 = off)
    wwFirstAt = 3,               -- from this many mobs in reach Whirlwind goes before Bloodthirst (0 = always BT first)
    wwAuto = true,               -- ...worked out from attack power and the main hand instead (2026-10-28)
    shortfall = true,            -- "-6" on BT / WW when they are (nearly) back and the rage is short
    practice = false,            -- on a training dummy: your reaction time after each press (a popup over the plate)
    -- 2026-10-28, Zac: "a blatant identification of what button i should
    -- press first lets say 4 mobs in range ww first or 1 mob ... the bt
    -- button": the ONE button to press now says NEXT over it and comes up
    -- a size; the other ready ones dim and lose the gold
    nextMark = true,
    nextLabel = false,           -- ...and the word "NEXT" over it (off by default, 2026-10-28)
    prePull = true,              -- the pack counted before you charge it: Whirlwind marked as the opener (2026-10-29)
    -- cooldowns and trinkets (2026-10-29, Zac: "if i have like death wish
    -- going and a trinket up that im ignoring or just trinkets in general")
    cdEnabled = true,            -- Death Wish, racials and on-use trinkets are watched too
    cdGrace = 1.5,               -- seconds a cooldown may sit wanted before it is called out
    cdTrash = false,             -- also outside boss fights (stacking onto a running burst counts everywhere)
    dwAt = 30,                   -- Death Wish in the last this-many seconds of a boss (2026-10-29 22:59)
    trinketAt = 15,              -- trinkets (and racials) in the last this-many seconds of Death Wish
    cdEarly = false,             -- ...and earlier too when the trinket will be back for the end
    cdReck = false,              -- Recklessness too (a 30 minute cooldown - usually planned)
    cdSkip = "",                 -- trinkets never to call (names, comma between each)
    -- look (2026-11; the defaults are what it always drew). A colour left
    -- unset follows ZacUI's palette, as it always has.
    -- alertColor / subColor / bgColor / edgeColor: the big alert's text,
    -- its "ready 1.4s", its backing and its edge; readyColor / noobColor /
    -- noRageColor: the nameplate row's gold, the NOOB glow, the no-rage ring
    alertFont = { size = 18, outline = "thick", shadow = true },
    subFont = { size = 11, outline = "outline", shadow = true },
    pulse = true,                -- the alert text breathes while it is up
    popupShow = { style = "none", duration = 0.2, delay = 0, easing = "easeOutQuad" },
    popupHide = { style = "none", duration = 0.2, delay = 0, easing = "easeOutQuad" },
}

-- The one-time save migrations below run once per stored table (a new
-- table - profile switch, import, reset - runs them again); every later
-- call is the plain store read. DB() is called many times a second.
local migratedFor
function H.Store()
    local db = HUD.Store("hesitation", DEFAULTS)
    if not db or db == migratedFor then return db end
    migratedFor = db
    -- the alert sound went off by default (2026-10-18); a save from
    -- before that is switched off once, and the old nameplate tag's
    -- switch carries over to the cooldown row that replaced it
    if db and db.plateRowY == 48 and not db._rowV2 then db._rowV2 = true db.plateRowY = 32 end
    -- the name went inside the bar, so the row comes down to just over
    -- it (Zac: "still kinda far up"); an untouched 32 moves once
    if db and not db._rowV3 then db._rowV3 = true if db.plateRowY == 32 then db.plateRowY = 12 end end
    -- the spot is measured from the bar's TOP (clear of the target box)
    -- now, not its centre: centre-measured it sank into the box on a
    -- taller bar (Zac: "overlap with the outline"); an untouched 12 moves
    if db and not db._rowV4 then db._rowV4 = true if db.plateRowY == 12 then db.plateRowY = 2 end end
    -- the row's icons are bigger by default now; an untouched 24 moves once
    if db and not db._plateSizeV2 then db._plateSizeV2 = true if db.plateSize == 24 then db.plateSize = 30 end end
    if db and not db.soundOffDone then
        db.soundOffDone = true
        db.playSound = false
        if db.showOnNameplate ~= nil then db.plateCDs = db.showOnNameplate ~= false end
    end
    -- the row took the Overpower window and the Execute cue from the
    -- plates' debuff groups (2026-10-19): Overpower is watched again if
    -- it had been unticked, and the Execute group's bosses-only choice
    -- carries over (read when the plates module is up, see Rebuild)
    if db and not db._procRowV1 then
        db._procRowV1 = true
        if type(db.abilities) == "table" then db.abilities["Overpower"] = nil end
    end
    -- Execute shows on every target under 20%; the first build carried
    -- Readycheck's bosses-only choice over and hid it on trash (Zac:
    -- "not seeing the execute thing next to bt or ww when the mob hits 20%")
    -- the big popup is off: the cooldown row over the target's plate
    -- carries the call-out as a glow (Zac: "the same functionality
    -- without the big annoying popup"); once, for saves that had it on
    if db and not db._popupOffV1 then
        db._popupOffV1 = true
        db.showPopup = false
        db.plateCDs = true
    end
    -- no popups (Zac: "dont want the scoreboard ... i dont want popups"):
    -- the scorecard is kept quietly for /zui noob, the dummy readout off
    if db and not db._noPopupsV1 then
        db._noPopupsV1 = true
        db.scorecard = false
        db.practice = false
    end
    if db and not db._execAllV2 then
        db._execAllV2 = true
        db._execBossDone = true
        db.plateExecBoss = false
    end
    return db
end
local function DB() return H.Store() end
local HidePlateRow            -- the plate cooldown row's hide, defined with the row below
local Secondary               -- "the other one goes first", defined with the row below
-- the row came or went over the target's plate: the crosshair (ZacUI
-- Nameplates) re-measures the plate so its line stops clear of the row
local function Remeasure()
    local CH = ns.Nameplates and ns.Nameplates.Crosshair
    if CH and CH.Remeasure then CH.Remeasure() end
end

local function PlayerClass()
    local _, class = UnitClass("player")
    return class or "WARRIOR"
end

-- The names this character could watch: the class defaults and the
-- custom additions, in that order, each once.
function H:CandidateNames()
    local db = DB()
    local out, seen = {}, {}
    for _, name in ipairs(self.CLASS_DEFAULTS[PlayerClass()] or {}) do
        if not seen[name] then seen[name] = true out[#out + 1] = name end
    end
    for _, name in ipairs(db and db.custom or {}) do
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true out[#out + 1] = name
        end
    end
    return out
end

function H:IsWatched(name)
    local db = DB()
    return not (db and db.abilities[name] == false)
end

function H:ShortName(name)
    local s = self.SHORT[name]
    if s then return s end
    -- initials of a name nobody abbreviated for us: "Sinister Strike" -> "SS"
    local out = ""
    for word in tostring(name):gmatch("%a+") do out = out .. word:sub(1, 1):upper() end
    return out ~= "" and out or tostring(name):upper()
end

function H:Callout(name)
    local db = DB()
    local style = db and db.style or "noob"
    for _, s in ipairs(self.STYLES) do
        if s.key == style then return string_format(s.fmt, self:ShortName(name)) end
    end
    return string_format("%s NOOB", self:ShortName(name))
end

-- ============================================================
-- THE WATCHED SET - rebuilt when spells or settings change, never in
-- the tick
-- ============================================================
H.watch = H.watch or {}        -- ordered entries { name, icon, short }
H.swing = H.swing or {}        -- spell ids of the known on-next-swing abilities
H.hasExecute = false           -- the character knows Execute
H.byName = H.byName or {}      -- spell name -> entry
H.stats = H.stats or {}        -- per fight: name -> { presses, late, wasted, worst }
H.session = H.session or {}    -- this login: same shape

-- (2026-10-30, Zac: "some of the stuff resets when it shouldnt") The
-- list is rebuilt on SPELLS_CHANGED and loading screens, which can come
-- mid-fight: every button's wait, its growing NOOB icon and the alert
-- on screen started over. What each button was doing now carries over
-- to its new entry by name.
local CARRY = { "since", "cause", "cdDur", "plateRem", "plateStart", "plateDur", "plateUsable",
    "shortBy", "dumped", "waitPast", "ignored", "want", "hold", "ready", "rcShown" }
local carryOld = {}
local function CarryFrom(old, e)
    local o = old[e.name]
    if not o then return end
    for i = 1, #CARRY do local k = CARRY[i] if o[k] ~= nil then e[k] = o[k] end end
    if H.showing == o then H.showing = e end
    if H.nextE == o then H.nextE = e end
end
H._CarryFrom = CarryFrom
function H:Rebuild()
    wipe(carryOld)
    for k, e in pairs(self.byName) do carryOld[k] = e end
    wipe(self.watch)
    wipe(self.byName)
    local db = DB()
    if not (db and db.enabled) then self:StopTicker() return end
    for _, name in ipairs(self:CandidateNames()) do
        if self:IsWatched(name) then
            local known, _, icon = GetSpellInfo(name)
            if known then
                local e = { name = known, icon = icon, short = self:ShortName(known),
                    cost = HUD.RageCost(select(7, GetSpellInfo(name))) or 0 }
                CarryFrom(carryOld, e)
                self.watch[#self.watch + 1] = e
                self.byName[known] = e
            end
        end
    end
    if #self.watch == 0 then self:StopTicker() end
    if not InCombatLockdown() then HidePlateRow() end
    local known, _, icon = GetSpellInfo(EXECUTE)
    self.hasExecute = known ~= nil
    -- Execute's own row entry (never in the watch list: its clock is the
    -- execute-phase one in the tick, not a cooldown)
    if known and not self.execEntry then
        self.execEntry = { name = known, icon = icon, short = self:ShortName(known), isExecute = true }
    end
    self.meleeProxy = nil
    for _, name in ipairs(MELEE_PROXY) do
        local known = GetSpellInfo(name)
        if known then self.meleeProxy = known break end
    end
    wipe(self.swing)
    for _, name in ipairs(ON_SWING) do
        local known, _, _, _, _, _, id = GetSpellInfo(name)
        if known and id then self.swing[#self.swing + 1] = id end
    end
    if self.RebuildCds then self:RebuildCds() end
end

local BT_NAME = GetSpellInfo(23881) or "Bloodthirst"
local WW_NAME = GetSpellInfo(1680) or "Whirlwind"
H.BT_NAME, H.WW_NAME = BT_NAME, WW_NAME
local FALLBACK_COST = { [BT_NAME] = 30, [WW_NAME] = 25 }
local function CostOf(e)
    local WS = ns.WarriorHUD and ns.WarriorHUD.State
    if WS and e.name == BT_NAME and WS.btCost then return WS.btCost end
    if WS and e.name == WW_NAME and WS.wwCost then return WS.wwCost end
    if e.cost and e.cost > 0 then return e.cost end
    return FALLBACK_COST[e.name] or 0
end

-- TIME TO DIE: how fast the target's health is falling, measured over
-- half-second steps and smoothed; restarts on a new target. Seconds
-- left, or nil while there is no reading yet.
local ttk = { guid = nil, t = 0, pct = 0, rate = nil }
local function TimeToDie(now)
    local guid = UnitGUID and UnitGUID("target")
    local hpMax, hp = UnitHealthMax("target"), UnitHealth("target")
    -- (WoW Forever hides an enemy's health in combat: no reading)
    if ns.IsSecret and (ns.IsSecret(hpMax) or ns.IsSecret(hp)) then ttk.guid = nil return nil end
    if not guid or not hpMax or hpMax <= 0 then ttk.guid = nil return nil end
    local pct = hp / hpMax
    if ttk.guid ~= guid then
        ttk.guid, ttk.t, ttk.pct, ttk.rate = guid, now, pct, nil
        return nil
    end
    if now - ttk.t >= 0.5 then
        local r = (ttk.pct - pct) / (now - ttk.t)
        if r < 0 then r = 0 end
        ttk.rate = ttk.rate and (ttk.rate * 0.6 + r * 0.4) or r
        ttk.t, ttk.pct = now, pct
    end
    if not ttk.rate or ttk.rate <= 0 then return nil end
    return pct / ttk.rate
end

-- The Warrior HUD's snapshot (HUD_Warrior_Core) when it runs: one read of
-- each spell for the HUD and this tick. Other classes, or a spell the HUD
-- does not track, read the client directly.
local function WHud()
    local WH = ns.WarriorHUD
    return (WH and WH.running) and WH or nil
end

-- IsUsableSpell through the snapshot when the HUD tracks the spell
local function Usable(name, attackable)
    local WH = WHud()
    local _, us = nil, nil
    if WH then _, us = WH.SpellState(name, attackable) end
    if us then return us.usable, us.noPower end
    return IsUsableSpell(name)
end

local function PlayerAP()
    if not UnitAttackPower then return 0 end
    local base, pos, neg = UnitAttackPower("player")
    -- (WoW Forever can hide your own attack power: no reading)
    if ns.Hidden(base, pos, neg) then return 0 end
    return (base or 0) + (pos or 0) + (neg or 0)
end

-- 2026-10-28, Zac: work the Whirlwind-first mob count out from the
-- character instead of a fixed 3. With both up, the one pressed second
-- waits a global cooldown, and that costs 1.5s worth of its cooldown:
-- 1.5/6 of a Bloodthirst (45% of attack power, one target) or 1.5/10
-- of a Whirlwind (one main-hand hit - the character sheet's damage,
-- which already has the gear, buffs and talents in it - on each mob, up
-- to four). Whirlwind goes first from the smallest mob count where
-- delaying it costs more. Cheap: two API reads, at most every 2s, only
-- from the hesitation ticker (in combat) - never from an event.
-- the main hand's normalised speed and its own (unhasted) speed, nil
-- without one; the item's speed comes from ZacUI's weapon scan (cached
-- per item), else the swing timer's (hasted, so a smaller correction)
function H.MainHandSpeeds()
    local id = GetInventoryItemID and GetInventoryItemID("player", 16)
    if not id then return nil end
    local _, _, _, loc, _, _, sub = GetItemInfoInstant(id)
    local norm = (loc == "INVTYPE_2HWEAPON") and 3.3 or (sub == 15 and 1.7) or 2.4
    local WR = ns.WeaponRoles
    local f = WR and WR.Facts and WR.Facts(id)
    local speed = f and f.speed
    if not speed and UnitAttackSpeed then speed = UnitAttackSpeed("player") end
    if ns.IsSecret(speed) then speed = nil end
    return norm, speed
end

local WW_MAX_TARGETS = 4
local AUTO_EVERY = 2
local autoAt, autoN = nil, nil
H.wwAutoInfo = {}       -- the last numbers, for /zui noob ww
local function AutoWWFirstAt(now, force)
    if not force and autoAt and now - autoAt < AUTO_EVERY then return autoN end
    autoAt = now
    autoN = nil
    if not UnitDamage then return nil end
    local ap = PlayerAP()
    local lo, hi, _, _, _, _, pct = UnitDamage("player")
    -- (hidden on WoW Forever: the fixed count stands)
    if ns.Hidden(lo, hi, pct) then return nil end
    if not (lo and hi and hi > 0 and ap > 0) then return nil end
    local ww = (lo + hi) / 2                      -- the sheet's main hand, all bonuses in
    -- (2026-10-30) Whirlwind hits with the NORMALISED speed (dagger 1.7,
    -- one-hander 2.4, two-hander 3.3), the sheet with the weapon's own:
    -- a 2.7 sword's sheet hit is AP/14 x 0.3 bigger than its Whirlwind
    local norm, speed = H.MainHandSpeeds()
    if norm and speed and speed > norm then ww = ww - ap / 14 * (speed - norm) * (pct or 1) end
    if ww <= 0 then return nil end
    local bt = 0.45 * ap * (pct or 1)             -- the same damage multipliers
    -- every hit that crits leaves Deep Wounds (60% of the weapon's average
    -- hit over 12 s) on THAT mob: worth the same per hit for both, so it
    -- counts once for Bloodthirst and once per mob for Whirlwind
    local critRead = GetCritChance and GetCritChance() or 0
    if ns.IsSecret(critRead) then critRead = 0 end
    local crit = critRead / 100
    local dw = 0.6 * crit * (lo + hi) / 2
    bt, ww = bt + dw, ww + dw
    local be, we = H.byName[BT_NAME], H.byName[WW_NAME]
    local btCD = (be and be.cdDur and be.cdDur > 1.5) and be.cdDur or 6
    local wwCD = (we and we.cdDur and we.cdDur > 1.5) and we.cdDur or 10
    local need = (wwCD / btCD) * (bt / ww)        -- WW first once mobs > this
    local n = math_floor(need) + 1
    if n < 1 then n = 1 end
    if n > WW_MAX_TARGETS then n = WW_MAX_TARGETS + 1 end   -- it cannot hit enough: never first
    autoN = n
    local a = H.wwAutoInfo
    a.ap, a.bt, a.ww, a.need, a.n, a.btCD, a.wwCD, a.crit = ap, bt, ww, need, n, btCD, wwCD, crit
    return n
end
H.AutoWWFirstAt = AutoWWFirstAt

-- Some abilities are "ready" only under a condition the cooldown does
-- not show. Overpower: the 5s window after THIS target dodged you -
-- ZacUI's one Overpower window (ns.Overpower), the same one the HUD's
-- buff bar times, carried through a stance dance. Revenge and Shield
-- Slam: Defensive Stance (form 2). Anything else: always.
local STANCE_ONLY = { ["Revenge"] = 2, ["Shield Slam"] = 2 }
function H.Gate(e, usable, noPower)
    local name = e.name
    if name == "Overpower" then
        return ns.Overpower.Left() > 0
    end
    local form = STANCE_ONLY[name]
    if form then return GetShapeshiftForm() == form end
    return true
end

-- auto-attack on, or an on-next-swing ability queued (which is the
-- same thing with extra rage)
-- a Heroic Strike / Cleave (or Maul, Raptor Strike) queued right now
local function SwingQueued()
    local WH = WHud()
    local q = WH and WH.SwingQueued()
    if q ~= nil then return q end
    local sw = H.swing
    for i = 1, #sw do
        if IsCurrentSpell(sw[i]) then return true end
    end
    return false
end

local function Swinging()
    if IsCurrentSpell(ATTACK_SPELL) then return true end
    return SwingQueued()
end

-- ============================================================
-- THE PACK BEFORE IT REACHES YOU (2026-10-29, Zac: "part of it is
-- preemptive like lets say im about to charge into a pack of 4 mobs").
-- The mob count the Whirlwind call reads (the HUD's, ~10 yd, in combat)
-- only sees mobs already on you, so the first button of a charge into a
-- pack was always called as Bloodthirst. Two guesses fill that gap:
--   * before the pull, out of combat, with your target in Charge range:
--     the target plus every hostile plate at about the same distance
--     (Charge range or ~10 yd) and near it on screen - the pack around
--     it. Enough for Whirlwind first and the row shows Whirlwind as the
--     opener over the target, with the count.
--   * the first seconds of the fight: that guess still counts, and so
--     does every hostile mob in combat that is within ~10 yd or within
--     Charge range and coming at you (targeting you).
-- Classic gives ranges, not positions, so it is a guess: a second pack
-- just as far away and close on screen counts too. Cost: a 0.25 s scan
-- of the plates only while you are out of combat targeting an enemy
-- (stops otherwise), and one in the first 3 s of a fight.
-- ============================================================
local CHARGE = GetSpellInfo(100) or "Charge"
local PACK_HOLD = 3          -- seconds into a fight the pack guess still counts
local PLATE_U, PLATE_UT = {}, {}
for i = 1, 40 do PLATE_U[i] = "nameplate" .. i PLATE_UT[i] = "nameplate" .. i .. "target" end
-- 1 melee, 2 within ~10 yd, 3 Charge range (8-25 yd), 4 further
local function Bracket(u)
    if H.meleeProxy and IsSpellInRange(H.meleeProxy, u) == 1 then return 1 end
    if IsSpellInRange(CHARGE, u) == 1 then return 3 end
    local ok, near = pcall(CheckInteractDistance, u, 3)
    if ok and near then return 2 end
    return 4
end
-- A plate's spot on screen. Some places refuse to say where a plate is
-- ("Can't measure restricted regions" - 2026-10-29, 33 errors in a
-- row): asked under pcall, and once refused not asked again for 10 s;
-- meanwhile the pack is counted by distance alone (PlatesBlocked).
local blockedAt
local function PlatesBlocked() return blockedAt and (GetTime() - blockedAt) < 10 end
local function PlateXY(u)
    if PlatesBlocked() then return nil end
    local p = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(u)
    if not p then return nil end
    local ok, x, y = pcall(p.GetCenter, p)
    if not ok then blockedAt = GetTime() return nil end
    if not x then return nil end
    local k = p:GetEffectiveScale() or 1
    return x * k, y * k
end
-- THE MOBS A WHIRLWIND WOULD HIT NOW (2026-10-30, Zac: "the noob stuff
-- tells me to ww when i should be pressing bt"). The call used the
-- Warrior HUD's sapper count: every attackable plate within ~10 yd, in
-- combat or not - and, where the client refuses the distance check in
-- combat, EVERY attackable plate on screen. A pack standing next to you
-- or the room behind you turned one target into "Whirlwind first". Now
-- only mobs that are fighting, alive, not critters or totems, and in
-- your melee reach (the spell range check, which works in combat) count.
-- Read at most every 0.3 s, from the combat tick only.
local reachAt, reachN = nil, 0
local NOT_A_MOB = { Critter = true, Totem = true }
function H.MobsInReach(now)
    if reachAt and now - reachAt < 0.3 and now >= reachAt then return reachN end
    reachAt = now
    local proxy = H.meleeProxy
    if not proxy then reachN = 0 return 0 end
    local n, sawTarget = 0, false
    for i = 1, 40 do
        local u = PLATE_U[i]
        if UnitExists(u) and UnitCanAttack("player", u) and not UnitIsDead(u) and UnitAffectingCombat(u)
            and not NOT_A_MOB[UnitCreatureType(u) or ""] and IsSpellInRange(proxy, u) == 1 then
            n = n + 1
            if UnitIsUnit(u, "target") then sawTarget = true end
        end
    end
    -- the target with its plate hidden still counts
    if not sawTarget and UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDead("target") and IsSpellInRange(proxy, "target") == 1 then n = n + 1 end
    reachN = n
    return n
end

local function PackMob(u)
    return UnitExists(u) and UnitCanAttack("player", u) and not UnitIsDead(u)
        and UnitCreatureType(u) ~= "Critter"
end
-- how many mobs the pull is about: out of combat the pack round your
-- target (0 when it is not in Charge range); in combat the ones close or
-- coming at you
function H.PackGuess(inCombat)
    local tx, ty, r2
    if not inCombat then
        if Bracket("target") ~= 3 then return 0 end
        tx, ty = PlateXY("target")
        -- no screen spot to be had here: distance alone decides
        if not tx and not PlatesBlocked() then return 0 end
        local r = (UIParent:GetHeight() or 768) * (UIParent:GetEffectiveScale() or 1) * 0.3
        r2 = r * r
    end
    local n = 0
    for i = 1, 40 do
        local u = PLATE_U[i]
        if PackMob(u) then
            if inCombat then
                if UnitAffectingCombat(u) then
                    local b = Bracket(u)
                    if b <= 2 or (b == 3 and UnitIsUnit(PLATE_UT[i], "player")) then n = n + 1 end
                end
            elseif UnitIsUnit(u, "target") then
                n = n + 1
            else
                local b = Bracket(u)
                if b == 2 or b == 3 then
                    if not tx then
                        -- positions refused: a mob at about the same
                        -- distance that is not already fighting counts
                        if not UnitAffectingCombat(u) then n = n + 1 end
                    else
                        local x, y = PlateXY(u)
                        if x and (x - tx) * (x - tx) + (y - ty) * (y - ty) <= r2 then n = n + 1 end
                    end
                end
            end
        end
    end
    return n
end

-- ============================================================
-- COOLDOWNS AND TRINKETS (2026-10-29, Zac: "if i have like death wish
-- going and a trinket up that im ignoring or just trinkets in general.
-- be creative come up with a good system")
-- Death Wish, the racials (Blood Fury, Berserking), Recklessness if
-- asked, and every ON-USE trinket you wear are watched as well. Each one
-- that is ready is either WANTED now, HELD, or of no concern - and one
-- sat wanted past cdGrace while you swing is called out like a rotation
-- button: red and growing on the plate row and on the Warrior HUD,
-- counted on the scorecard. What makes it wanted, in order:
--   1. Readycheck's plan. When your raid profile has this boss or mob
--      with this cooldown in it (deathwish / trinket1 / trinket2 / the
--      trinket's item id ...), Readycheck decides when - it is wanted
--      only once Readycheck's reminder shows it, and only then can you
--      be late with it. Its popup already says "use it", so the row
--      lights only when you sit on it. No second opinion on its timing.
--   2. Zac's plan (2026-10-29 22:59: "ideally i want to deathwish last 30
--      seconds of a fight and then trinket last 15 seconds of the death
--      wish"), in a boss fight (or anywhere, with "on trash too"):
--      Death Wish once the target has dwAt (30) seconds left to live;
--      the trinkets and racials once Death Wish has trinketAt (15)
--      seconds left - or, with no Death Wish still to come this fight,
--      once the target has that long left. Until then they are HELD:
--      nothing is called at the start of a fight. Optionally a trinket
--      is also used early when it will be back for the end anyway.
--      Time left: Readycheck's time-to-kill (its kill history) when it
--      has one for the fight, else the target's health falling.
-- Read in the 0.1 s combat tick, every other pass (a cooldown read per
-- entry); a burst is timed from your own casts, no aura scans.
-- ============================================================
H.cds = H.cds or {}
H.cdByName = H.cdByName or {}
local CD_SPELLS = {
    { name = "Death Wish", key = "deathwish", short = "DW", burst = 30, dw = true },
    { name = "Recklessness", key = "recklessness", short = "RECK", burst = 15, opt = "cdReck" },
    { name = "Blood Fury", key = "bloodfury", short = "BF", burst = 15 },
    { name = "Berserking", key = "berserking", short = "BERS", burst = 10 },
}
-- on-use trinkets that are not damage: never called
local CD_NOT_DAMAGE = { "Insignia of the", "Medallion of the Alliance", "Medallion of the Horde",
    "Carrot on a Stick", "Lifegiving Gem", "Nifty Stopwatch", "Skull of Impending Doom",
    "Arena Grand Master", "Rune of the Guard Captain", "Gnomish Mind Control", "Hearthstone" }
local TRINKET_BURST = 20    -- seconds a used trinket's buff is taken to run
local function SkipTrinket(name, db)
    if not name then return true end
    for _, pat in ipairs(CD_NOT_DAMAGE) do
        if name:find(pat, 1, true) then return true end
    end
    for n in tostring(db.cdSkip or ""):gmatch("[^,\n]+") do
        n = n:gsub("^%s+", ""):gsub("%s+$", "")
        if n ~= "" and name:lower() == n:lower() then return true end
    end
    return false
end
local carryCd = {}
function H:RebuildCds()
    wipe(carryCd)
    for k, e in pairs(self.cdByName) do carryCd[k] = e end
    wipe(self.cds)
    wipe(self.cdByName)
    self.cdDW = nil
    local db = DB()
    if not (db and db.enabled and db.cdEnabled ~= false) then return end
    for _, c in ipairs(CD_SPELLS) do
        local known, _, icon = GetSpellInfo(c.name)
        if known and (not c.opt or db[c.opt] == true) then
            local e = { name = known, icon = icon, short = c.short, isCd = true, rcKey = c.key,
                burst = c.burst, isDW = c.dw }
            H._CarryFrom(carryCd, e)
            self.cds[#self.cds + 1] = e
            self.cdByName[known] = e
            if c.dw then self.cdDW = e end
        end
    end
    for slot = 13, 14 do
        local id = GetInventoryItemID and GetInventoryItemID("player", slot)
        local spellName, spellId
        if id and GetItemSpell then spellName, spellId = GetItemSpell(id) end
        local name = id and GetItemInfo and (GetItemInfo(id))
        if id and spellName and name and not SkipTrinket(name, db) then
            local e = { name = name, icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slot),
                short = self:ShortName(name), isCd = true, slot = slot, itemId = id,
                rcKey = (slot == 13) and "trinket1" or "trinket2", useSpell = spellId, useName = spellName,
                burst = TRINKET_BURST, isTrinket = true }
            H._CarryFrom(carryCd, e)
            self.cds[#self.cds + 1] = e
            self.cdByName[name] = e
        elseif id and not name then
            self._cdRetry = true          -- the item is not in the client's cache yet
        end
    end
    self._cdSlots = { GetInventoryItemID and GetInventoryItemID("player", 13), GetInventoryItemID and GetInventoryItemID("player", 14) }
end

-- Readycheck's plan for this cooldown on the current target: planned
-- (its config has it), said (its reminder is showing it now). nil, nil
-- without Readycheck or without a plan for the target.
local function RcPlan(e)
    local RC = _G.Readycheck
    local cache = RC and RC.encounterCache
    local cfg = cache and cache.mobConfig
    if not (cfg and cfg.enabled and type(cfg.abilities) == "table") then return nil, nil end
    if cache.targetGUID and UnitGUID and cache.targetGUID ~= ns.SafeGUID("target") then return nil, nil end
    local a = cfg.abilities
    local keys = { e.rcKey, e.itemId, e.itemId and tostring(e.itemId) }
    local planned
    for i = 1, 3 do
        local k = keys[i]
        if k ~= nil and type(a[k]) == "table" and a[k].enabled then planned = k break end
    end
    if not planned then return nil, nil end
    local said = false
    local fr = RC.reminderFrame
    local list = RC.activeReminderData and RC.activeReminderData.abilities
    if fr and fr:IsShown() and type(list) == "table" then
        for _, k in ipairs(list) do
            if k == planned or tostring(k) == tostring(planned) then said = true break end
        end
    end
    return true, said
end

-- one pass over the cooldowns (from the tick). able: you are swinging at
-- a living target in reach with control of your character.
local function CdRemaining(e, now)
    local s, d, en
    if e.slot then
        s, d, en = GetInventoryItemCooldown("player", e.slot)
        if ns.Hidden(s, d, en) then return 0 end  -- (hidden on WoW Forever: unknown, so ready)
        if en == 0 then return nil end           -- a trinket with nothing to use
    else
        s, d = GetSpellCooldown(e.name)
    end
    if s and d and s > 0 and d > 1.5 then
        e.cdDur = d
        local rem = s + d - now
        if rem > 0 then return rem end
    end
    return 0
end
-- seconds the target has left: Readycheck's time-to-kill for a boss
-- fight it is timing (its kill history), else the health slope given;
-- read twice a second at most
local ttkAt, ttkVal
local function TimeLeft(now, fallback)
    if ttkAt and now - ttkAt < 0.5 then return ttkVal or fallback end
    ttkAt, ttkVal = now, nil
    local RC = _G.Readycheck
    local calc = RC and RC.executeCalculator
    local fight = calc and calc.currentFight
    if fight and fight.started and fight.bossEngaged and RC.GetTTKRemaining then
        local ok, rem = pcall(RC.GetTTKRemaining, RC)
        if ok and type(rem) == "number" and rem > 0 and rem < 999 then ttkVal = rem end
    end
    return ttkVal or fallback
end
H.TimeLeft = TimeLeft

function H:UpdateCds(now, able, boss, ttkLeft, db)
    local grace = tonumber(db.cdGrace) or 1.5
    local dwAt = tonumber(db.dwAt) or 30
    local trAt = tonumber(db.trinketAt) or 15
    ttkLeft = TimeLeft(now, ttkLeft)
    local dw = self.cdDW
    local dwRem = dw and CdRemaining(dw, now) or nil
    -- Death Wish running (timed from your cast): seconds of it left
    local dwLeft = (self.dwUntil or 0) - now
    if dwLeft <= 0 then dwLeft = nil end
    -- a Death Wish still to come this fight: known, and back before the
    -- target dies (or nothing known about when it dies)
    local dwComing = dw and dwRem and not dwLeft
        and (dwRem == 0 or not ttkLeft or dwRem < ttkLeft) or false
    for _, e in ipairs(self.cds) do
        local rem = (e == dw) and dwRem or CdRemaining(e, now)
        local want, hold = false, nil
        local planned, said = nil, nil
        if rem == 0 then
            local usable = true
            if not e.slot then usable = IsUsableSpell(e.name) and true or false end
            planned, said = RcPlan(e)
            if not usable then
                want = false
            elseif planned then
                want = said and true or false
            elseif not e.isDW and dwLeft then
                -- Death Wish is running: its last trAt seconds (stacking
                -- counts on trash too - you started it)
                want = dwLeft <= trAt
                if not want then hold = dwLeft - trAt end
            elseif not (boss or db.cdTrash) then
                want = false
            elseif not boss and ttkLeft and ttkLeft < 8 then
                want = false                     -- a trash mob about to die
            elseif e.isDW then
                -- the last dwAt seconds of the fight
                want = ttkLeft ~= nil and ttkLeft <= dwAt
                if not want and ttkLeft then hold = ttkLeft - dwAt end
            elseif dwComing then
                -- a trinket waits for Death Wish's last trAt seconds;
                -- early only when it will be back for them anyway
                want = db.cdEarly == true and ttkLeft ~= nil and ttkLeft > (e.cdDur or 120) + dwAt + 5
                if not want then hold = ttkLeft and (ttkLeft - dwAt) or nil end
            else
                -- no Death Wish to come: the fight's last trAt seconds
                want = ttkLeft ~= nil and (ttkLeft <= trAt
                    or (db.cdEarly == true and ttkLeft > (e.cdDur or 120) + trAt + 5))
                if not want and ttkLeft then hold = ttkLeft - trAt end
            end
        end
        e.ready = rem == 0
        e.want, e.hold, e.rcShown = want, hold, (planned and said) or false
        if want and able then
            e.since = e.since or now
            local late = (now - e.since) >= grace
            if late and not e.ignored then e.fresh = true end
            e.ignored = late
        else
            if not want then e.since = nil end
            e.ignored = false
        end
        -- the plate row: up while wanted (unless Readycheck's popup is
        -- already saying it) or ignored
        if (want and not e.rcShown) or e.ignored then
            e.plateRem, e.plateUsable = 0, true
        else
            e.plateRem, e.plateUsable = nil, nil
        end
    end
end

-- a press of one of them: its wait is recorded, a burst starts
function H:OnCdCast(spellId, name)
    local now = GetTime()
    for _, e in ipairs(self.cds) do
        local hit = (e.slot and ((e.useSpell and e.useSpell == spellId) or (e.useName and e.useName == name)))
            or ((not e.slot) and e.name == name)
        if hit then
            local delay = e.since and (now - e.since) or 0
            local db = DB()
            local late = e.since and delay >= (tonumber(db.cdGrace) or 1.5) or false
            H._Bump(self.stats, e.name, delay, late, e.ignored and "ignored" or nil)
            H._Bump(self.session, e.name, delay, late, nil)
            if e.cdDur and e.cdDur > 1.5 then self.stats[e.name].cdDur = e.cdDur end
            e.since, e.ignored, e.want = nil, false, false
            self.burstUntil = math.max(self.burstUntil or 0, now + (e.burst or TRINKET_BURST))
            if e.isDW then self.dwUntil = now + (e.burst or 30) end
            return true
        end
    end
    return false
end

-- ============================================================
-- DISPLAY: the big alert (a HUD mover) and the cooldown row over the
-- target's nameplate
-- ============================================================
local popup, prow
local BIG                     -- the NOOB icon's size, set with the row below
-- The row lives on UIParent, the plate on its own (scaled) frame: what
-- is "N px" on the plate is N * k on the row. The target box sits 2 px
-- outside the bar with a 1 px line (ZacUI Nameplates); the row's bottom
-- clears it by plateRowY.
local function PlateK(zf)
    local rs = prow and prow:GetEffectiveScale() or 1
    local bs = zf and zf.health and zf.health:GetEffectiveScale() or 1
    if not rs or rs <= 0 or not bs or bs <= 0 then return 1 end
    return bs / rs
end
local BOX_OUT = 3

-- A colour setting, or (unset) the palette colour it always was.
local function Pal(c, cat, key, a)
    if type(c) == "table" then return HUD.Col(c) end
    local p = GetColor(cat, key)
    return p.r, p.g, p.b, a or 1
end
H.Pal = Pal

-- Colours and fonts onto one alert frame (the live one and the preview's).
local function PaintFrame(f)
    local db = DB()
    f.text:SetTextColor(Pal(db.alertColor, "text", "red"))
    f.sub:SetTextColor(Pal(db.subColor, "text", "gray"))
    f.bg:SetVertexColor(Pal(db.bgColor, "ui", "cardBg", 0.85))
    local r, g, b, a = Pal(db.edgeColor, "ui", "border")
    for _, t in ipairs(f.edge) do t:SetVertexColor(r, g, b, a) end
    if ns.ApplyFontSpec then
        -- (the game font's own drop shadow, as these texts always had)
        ns.ApplyFontSpec(f.text, db.alertFont, { size = 18, outline = "thick", shadow = true })
        ns.ApplyFontSpec(f.sub, db.subFont, { size = 11, outline = "outline", shadow = true })
    end
    if f.iconW and f.iconW.glows and f.iconW.glows.alert then
        local W = ns.WarriorHUD and ns.WarriorHUD.Widgets
        if W and W.SetGlowColor then W.SetGlowColor(f.iconW.glows.alert, Pal(db.noobColor, "text", "red")) end
    end
end

-- The nameplate row icon's three glow colours.
local function PaintPlateIcon(ic)
    local W = ns.WarriorHUD and ns.WarriorHUD.Widgets
    if not (W and W.SetGlowColor and ic.glows) then return end
    local db = DB()
    W.SetGlowColor(ic.glows.alert, Pal(db.noobColor, "text", "red"))
    W.SetGlowColor(ic.glows.norage, Pal(db.noRageColor, "text", "red", 0.85))
    W.SetGlowColor(ic.glows.ready, Pal(db.readyColor, "ui", "accent"))
    local gr, gg, gb = Pal(db.readyColor, "ui", "accent")
    if ic.texts and ic.texts.nx then ic.texts.nx:SetTextColor(gr, gg, gb, 1) end
end

local function Paint()
    if popup then PaintFrame(popup) end
    if prow then for _, ic in ipairs(prow.icons) do PaintPlateIcon(ic) end end
end

-- The spell icon, drawn by the Warrior HUD's icon widget so it matches
-- the buff row exactly (same crop, 1px border, dark backing, sheen),
-- plus a pulsing red border glow that is the alert itself. Without the
-- widget (another class's HUD build) a plain cropped texture stands in.
local function MakeIcon(parent, size)
    local W = ns.WarriorHUD and ns.WarriorHUD.Widgets
    if W and W.CreateIcon then
        local f = W.CreateIcon(parent, { width = size, height = size,
            zoom = W.ICON_ZOOM or 0.12, keepAspect = true, noCooldown = true })
        local red = GetColor("text", "red")
        f:AddGlow("alert", "Pixel", { color = { red.r, red.g, red.b, 1 }, thickness = 2 })
        return f
    end
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local t = f:CreateTexture(nil, "ARTWORK")
    t._zui_own = true
    t:SetAllPoints()
    t:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    f.icon = t
    function f:SetIconTexture(tex) t:SetTexture(tex) end
    function f:SetGlow() end
    return f
end

-- (re)starts the glow pulse each time an alert frame shows: the glow's
-- animation stops with the frame's OnHide
local function Arm(f)
    f.iconW:SetGlow("alert", false)
    f.iconW:SetGlow("alert", true)
end

-- The text pulse only runs while an alert is showing; the frame hides
-- itself otherwise, so this OnUpdate costs nothing out of an alert.
local function Pulse(self, elapsed)
    if DB().pulse == false then
        if self._pulsed then self._pulsed = nil self.text:SetAlpha(1) end
        return
    end
    self._pulsed = true
    self._t = (self._t or 0) + elapsed
    self.text:SetAlpha(0.72 + 0.28 * math.abs(math.sin(self._t * 5)))
end

-- The default spot: just above the Warrior HUD's active buff row when
-- there is one, otherwise the store's own x/y. A dragged position
-- (ZacUIDB.movers.hesitation) wins over both, like every HUD piece.
local function PlacePopup(holder)
    local cfg = DB()
    if HUD.MoverPos("hesitation") then
        HUD.PlaceAnchor("hesitation", holder, cfg)
        return
    end
    local D = ns.WarriorHUD and ns.WarriorHUD.Display
    local row = D and D.Holder and D.Holder("AuraRow")
    holder:ClearAllPoints()
    if row then
        holder:SetPoint("BOTTOM", row, "TOP", 0, 10)
    else
        holder:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or 180)
    end
end

-- One alert strip on `parent`, named or not: the live alert (BuildPopup
-- adds its holder, mover and handle) and the settings preview's sample.
local POP_W, POP_H = 230, 30
local function MakePopup(parent, name)
    -- a slim strip, as wide as ever but half the height (Zac: "not as
    -- tall but still just as long") - icon, call-out and the wait on one line
    local W, H_ = POP_W, POP_H
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(W, H_)
    f:SetPoint("CENTER", parent, "CENTER", 0, 0)
    f:SetFrameStrata("HIGH")
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg._zui_own = true
    bg:SetAllPoints()
    bg:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8X8")
    f.bg = bg
    -- a 1px edge in the alert colour, four strips
    f.edge = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
        t._zui_own = true
        t:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8X8")
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT") t:SetPoint(side .. "RIGHT") t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side) t:SetPoint("BOTTOM" .. side) t:SetWidth(1)
        end
        f.edge[i] = t
    end

    local icon = MakeIcon(f, H_ - 6)
    icon:SetPoint("LEFT", f, "LEFT", 3, 0)
    f.iconW = icon

    -- how long it has been ready, small, at the right end
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sub:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    sub:SetJustifyH("RIGHT")
    f.sub = sub

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    text:SetPoint("RIGHT", sub, "LEFT", -6, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    f.text = text

    f:SetScript("OnUpdate", Pulse)
    PaintFrame(f)
    -- what the anchors may hang off, and where each piece sits by default
    local parts = { strip = f, icon = icon, text = text, time = sub }
    f._zAnchorTo = function(k) return parts[k] end
    f._zAD = {}
    if ns.TagElement then
        ns.TagElement(text, "hud.alertText")
        ns.TagElement(sub, "hud.alertTime")
        ns.TagElement(icon, "hud.alertIcon")
    end
    H.PlacePopupParts(f)
    return f
end

-- WHERE THE ALERT'S PIECES SIT (db.anchors.<alertIcon|alertText|
-- alertTime>, ZacUI's anchor shape): the SetPoints MakePopup gives them
-- are the defaults, and a piece with nothing saved is never touched.
local function PopDef(f, k)
    local d = f._zAD[k]
    if not d then d = {} f._zAD[k] = d end
    return d
end
function H.PlacePopupParts(f)
    if not (f and f._zAD and ns.ApplyAnchor) then return end
    local db = DB()
    local A = db and type(db.anchors) == "table" and db.anchors or nil
    local to = f._zAnchorTo
    local function One(region, key, fill)
        local spec = A and A[key]
        if not spec and not region._zMoved then return end
        local d = PopDef(f, key)
        fill(d)
        local _, two = ns.ApplyAnchor(region, spec, d, to)
        if region == f.text and two == false then region:SetWidth(POP_W - 70) end
        region._zMoved = spec ~= nil or nil
    end
    One(f.iconW, "alertIcon", function(d)
        d.point, d.to, d.relPoint, d.x, d.y = "LEFT", f, "LEFT", 3, 0
    end)
    One(f.sub, "alertTime", function(d)
        d.point, d.to, d.relPoint, d.x, d.y, d.justify = "RIGHT", f, "RIGHT", -8, 0, "RIGHT"
    end)
    One(f.text, "alertText", function(d)
        d.point, d.to, d.relPoint, d.x, d.y, d.justify = "LEFT", f.iconW, "RIGHT", 8, 0, "LEFT"
        d.point2, d.to2, d.relPoint2, d.x2, d.y2 = "RIGHT", f.sub, "LEFT", -6, 0
    end)
end
-- the same, without a frame (what the page's pickers show as the default)
H.POPUP_ANCHORS = {
    alertIcon = { point = "LEFT", relPoint = "LEFT", x = 3, y = 0, label = "The strip" },
    alertText = { point = "LEFT", relPoint = "RIGHT", x = 8, y = 0, label = "The icon" },
    alertTime = { point = "RIGHT", relPoint = "RIGHT", x = -8, y = 0, label = "The strip" },
}

local function BuildPopup()
    if popup then return popup end
    local cfg = DB()
    local holder = CreateFrame("Frame", "ZacUIHUD_Hesitation_Holder", UIParent)
    holder:SetSize(POP_W, POP_H)
    holder:SetFrameStrata("HIGH")
    PlacePopup(holder)
    local f = MakePopup(holder, "ZacUIHUD_Hesitation")
    f.holder = holder
    f:SetScale(cfg.scale or 1)
    -- shown by the mover with nothing to say: the sample
    f:HookScript("OnShow", function(self)
        if not H.showing then H:Fill(self, nil, 1.4) end
        Arm(self)
    end)
    -- reset: back above the Warrior HUD's buff row (or the store's spot)
    HUD.RegisterMover("hesitation", "Hesitation Alert", holder, cfg,
        { reset = function() PlacePopup(holder) end })
    -- padlock (the HUD mover) and resize grip over the corner
    if UI.HudHandle then
        f.handle = UI.HudHandle(f, {
            getLocked = function() return not (ns.IsMoverShown and ns.IsMoverShown("hesitation")) end,
            setLocked = function() if ns.ToggleMover then ns.ToggleMover("hesitation") end end,
            getScale = function() return tonumber(DB().scale) or 1 end,
            setScale = function(v) DB().scale = v f:SetScale(v) end,
            onScaleEnd = function() H:ApplyAppearance() end,
            minScale = 0.6, maxScale = 2.0,
        })
    end
    popup = f
    Paint()
    return f
end

-- The cooldown row over the target's nameplate: one icon per watched
-- ability (Bloodthirst, Whirlwind...). An icon is there only when the
-- ability is about to come back (plateSoon seconds, counting down) or
-- is back and waiting to be pressed; on a long cooldown it is gone, so
-- the plate stays clean. Ready = gold border; the alert itself = the
-- red pulse the popup uses. Fed by the same 10 Hz tick as the alert
-- (combat only), re-anchored when the target's plate changes; nothing
-- runs out of combat.
local function BuildPlateRow()
    if prow then return prow end
    local f = CreateFrame("Frame", "ZacUIHUD_HesitationPlate", UIParent)
    f:SetSize(24, 24)
    f:SetFrameStrata("HIGH")
    f:Hide()
    f.icons = {}
    prow = f
    return f
end

-- One row icon on `f` (the live row, or the settings preview's row).
local function MakePlateIcon(f)
    local ic
    local size = DB().plateSize or 30
    local W = ns.WarriorHUD and ns.WarriorHUD.Widgets
    if W and W.CreateIcon then
        ic = W.CreateIcon(f, { width = size, height = size, zoom = W.ICON_ZOOM or 0.12,
            keepAspect = true, inverse = true })
        local red = GetColor("text", "red")
        local gold = GetColor("ui", "accent")
        -- the three ready states, no text: gold = press it; a steady red
        -- ring = ready but no rage for it; the NOOB (sat unpressed past
        -- the grace) = a bigger, faster-breathing red glow
        ic:AddGlow("alert", "Pixel", { color = { red.r, red.g, red.b, 1 }, size = 1.35, freq = 0.08 })
        ic:AddGlow("norage", "Pixel", { color = { red.r, red.g, red.b, 0.85 }, static = true })
        ic:AddGlow("ready", "buttonOverlay", { color = { gold.r, gold.g, gold.b, 1 }, freq = 0.15 })
        ic:AddText("t", "CENTER", 12, { 1, 1, 1, 1 }, 0, -1)
        -- Whirlwind: how many mobs it reaches (the warrior HUD's count),
        -- in the top-left corner so the centred timer never sits on it
        ic:AddText("n", "INNER_TOPLEFT", 9, { 0, 0.9412, 1, 1 }, 1, -1)
        -- how much rage it is short, top-right ("-6")
        ic:AddText("r", "INNER_TOPRIGHT", 9, { 1, 0.3, 0.3, 1 }, -1, -1)
        -- the button to press first: "NEXT" over it
        ic:AddText("nx", "ABOVE", 11, { gold.r, gold.g, gold.b, 1 }, 0, 7)
    else
        ic = MakeIcon(f, size)
        local t = HUD.Text(ic, 13, "OUTLINE")
        t:SetPoint("CENTER")
        function ic:SetText(key, v) if key == "t" then t:SetText(v) end end
        function ic:SetSwipe() end
        function ic:SetDesat() end
    end
    PaintPlateIcon(ic)
    ic:Hide()
    return ic
end

local function PlateIcon(i, row)
    local f = row or BuildPlateRow()
    local ic = f.icons[i]
    if ic then return ic end
    ic = MakePlateIcon(f)
    f.icons[i] = ic
    return ic
end

-- how much bigger a NOOB icon grows (Zac: "go from gold border to red
-- and maybe increase icon size")
BIG = 1.35

-- ...and it keeps growing the longer it is ignored (Zac: "get even bigger
-- if im ignoring them"): a tenth more every half second past the grace,
-- up to plateGrowMax. Stepped, so the row is laid out again twice a
-- second at most, not on every tick.
local GROW_STEP, GROW_EVERY = 0.1, 0.5
-- the button to press first comes up this much (under BIG: a NOOB stays bigger)
local NEXT_POP = 1.2
local NEXT_LABEL_H = 13     -- the "NEXT" over it reaches this far above the icon
local DIM_ALPHA = 0.4       -- a ready button that is not the one to press first
local function NoobScale(e, db, now)
    if db.plateGrow == false or not e.since then return BIG end
    local past = (now - e.since) - (db.grace or 1)
    if past <= 0 then return BIG end
    local top = math.max(BIG, tonumber(db.plateGrowMax) or 2.0)
    local s = BIG + math.floor(past / GROW_EVERY) * GROW_STEP
    if s > top then s = top end
    return math.floor(s * 100 + 0.5) / 100
end

-- lays the shown icons out left to right, centred over the plate; only
-- when the set of shown icons (or a NOOB icon's size) changed - `changed`
-- - or a layout was asked for (f._sig cleared)
local function LayoutPlateRow(f, changed)
    if f._sig and not changed then return end
    f._sig = true
    local size = DB().plateSize or 30
    local gap = 3
    local n, x, h = 0, 0, size
    for i = 1, #f.icons do
        local ic = f.icons[i]
        if ic._on then
            -- each icon its own width: a NOOB one is bigger (see BIG;
            -- _big is its scale while it grows, true in the preview)
            local w = ic._big and math.floor(size * (tonumber(ic._big) or BIG) + 0.5) or size
            ic:ClearAllPoints()
            ic:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0)
            x = x + w + gap
            if w > h then h = w end
            if ic._nx and w + NEXT_LABEL_H > h then h = w + NEXT_LABEL_H end
            n = n + 1
        end
    end
    f:SetSize(math.max(1, x - gap), h)
    f._rowH = h
end

HidePlateRow = function()
    if prow and prow:IsShown() then
        prow:Hide()
        prow._plate, prow._to, prow._pt = nil, nil, nil
        prow._sig = nil
        local sz = DB().plateSize or 30
        for _, ic in ipairs(prow.icons) do
            ic._on = nil ic._tenth = nil ic:Hide()
            if ic._big then ic._big = nil ic:SetSize(sz, sz) end
            if ic._dim then ic._dim = nil ic:SetAlpha(1) end
            if ic._nx then ic._nx = nil ic:SetText("nx", "") end
        end
        prow._rowH = nil
        Remeasure()
    end
end

-- Every state of the row once on the row frame f: the first watched
-- ability ready (gold, NEXT), the second 1.3s out, then ready without
-- the rage (greyed, red ring) and the NOOB glow (grown a size). The
-- nameplate preview and the settings preview's sample both draw this.
local function FillSampleRow(f)
    local db = DB()
    local self = H
    if #self.watch == 0 then self:Rebuild() end
    local names = { self.watch[1] and self.watch[1].name or "Bloodthirst", self.watch[2] and self.watch[2].name or "Whirlwind" }
    -- the Overpower window and the Execute cue ride the same row
    if names[1] ~= "Overpower" and names[2] ~= "Overpower" and GetSpellInfo("Overpower") and self:IsWatched("Overpower") then
        names[#names + 1] = "Overpower"
    end
    if db.plateExecute ~= false and GetSpellInfo(EXECUTE) then names[#names + 1] = EXECUTE end
    for i = 1, #names do
        local ic = PlateIcon(i, f)
        ic._tenth = nil
        local _, _, icon = GetSpellInfo(names[i])
        ic:SetIconTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        ic._tex = nil            -- the live row sets its own again
        ic._on = true
        ic:Show()
        ic:SetText("n", names[i] == "Whirlwind" and "3" or "")
        -- every state once: BT ready (gold), WW 1.3s out, then ready but
        -- no rage (greyed, red ring) and the NOOB glow (grown a size)
        ic:SetDesat(i == 3)
        -- the first one is the button to press first (NEXT over it, a size up)
        local nx = i == 1 and db.nextMark ~= false
        local big = (i >= 4 and BIG) or (nx and NEXT_POP) or nil
        local lab = nx and db.nextLabel == true
        if ic._big ~= big then
            ic._big = big
            local sz = db.plateSize or 30
            local w = big and math.floor(sz * big + 0.5) or sz
            ic:SetSize(w, w)
        end
        ic._nx = lab or nil
        ic:SetText("nx", lab and "NEXT" or "")
        ic._txt = nil
        if i ~= 2 then
            ic:SetText("t", "")
            ic:ClearSwipe()
            ic:SetGlow("ready", i == 1)
            ic:SetGlow("norage", i == 3)
            ic:SetGlow("alert", i >= 4)
        else
            ic:SetText("t", "1.3")
            ic:SetSwipe(GetTime() - 4.7, 6)
            ic:SetGlow("ready", false)
            ic:SetGlow("norage", false)
            ic:SetGlow("alert", false)
        end
    end
    for i = #names + 1, #f.icons do if f.icons[i]._on then f.icons[i]._on = nil f.icons[i]:Hide() end end
    f._sig = nil
    LayoutPlateRow(f, true)
end
H._FillSampleRow = FillSampleRow

-- The nameplate preview (ZacUI Nameplates > preview): the row on the
-- sample plate at its configured spot, until EndPreviewPlateRow.
function H:PreviewPlateRow(zf)
    local db = DB()
    local f = BuildPlateRow()
    if not (zf and zf.health) or db.plateCDs == false then
        if f._preview then f._preview = nil HidePlateRow() end
        return
    end
    if #self.watch == 0 then self:Rebuild() end
    f._preview = true
    f._plate, f._to, f._pt = nil, nil, nil
    f._ox, f._oy = tonumber(db.plateRowX) or 0, (tonumber(db.plateRowY) or 2) + BOX_OUT * PlateK(zf)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", zf.health, "TOP", f._ox, f._oy)
    FillSampleRow(f)
    f:Show()
end

-- How far the row reaches above a ZacUI plate's health bar right now
-- (in the bar's units), for the crosshair to keep its line clear of it:
-- the row's bottom sits plateRowY above the bar's centre, plateSize
-- tall - and 0 while the row is not up on that plate (the crosshair is
-- told to look again whenever it comes or goes).
function H.PlateReach(plate, zf)
    if not (prow and prow:IsShown() and prow._plate == plate) then return 0 end
    local db = DB()
    -- in the bar's units: the box, the gap over it, the row itself
    local k = PlateK(zf)
    return BOX_OUT + ((tonumber(db.plateRowY) or 2) + (prow._rowH or db.plateSize or 30)) / k
end

-- The widest the row can ever get over a plate, as half its width in the
-- health bar's units, and its sideways offset (plateRowX) in the same
-- units - every icon it can show (the watched abilities, then Execute),
-- one of them at its biggest NOOB size, the glow round it. A fixed
-- answer, not today's row: what lives beside the row (ZacUI's damage
-- numbers on the plate) stays put while an icon grows. 0 when the row is
-- off.
function H.PlateRowHalfWidth(zf)
    local db = DB()
    if db.plateCDs == false or db.enabled == false then return 0, 0 end
    local n = #(H.watch or {}) + #(H.cds or {})
    if db.plateExecute ~= false and GetSpellInfo(EXECUTE) then n = n + 1 end
    if n == 0 then return 0, 0 end
    local size, gap = db.plateSize or 30, 3
    local grow = (db.plateGrow == false) and (BIG or 1.35)
        or math.max(BIG or 1.35, tonumber(db.plateGrowMax) or 2.0)
    local w = (n - 1) * (size + gap) + size * grow + 2 * 6   -- the glow, both sides
    local rs = (prow and prow:GetEffectiveScale()) or UIParent:GetEffectiveScale() or 1
    local bs = zf and zf.health and zf.health:GetEffectiveScale() or rs
    local k = (rs > 0 and bs > 0) and (bs / rs) or 1
    return (w / 2) / k, (tonumber(db.plateRowX) or 0) / k
end

-- For the Warrior HUD's own ability icons: the same state the nameplate
-- row shows for that spell - "noob" (sat unpressed past the grace),
-- "ready" (up, with the rage), "norage" (up, no rage) - or nil (on
-- cooldown, out of combat, not watched). Second value: pressable now.
-- the call-out up right now is a ready ability starved by a queued
-- Heroic Strike / Cleave: the HUD lights its queued-swing icon too
function H.HudDumping()
    local e = H.showing
    return e and e.dumped and true or false
end

-- For the Warrior HUD's Whirlwind icon: the mob count the Whirlwind call
-- is using right now (the pack before a pull, the call's own count in a
-- fight) and whether the NEXT mark is what lights the HUD's icons - then
-- the HUD's own "enough mobs" flash stands down: one rule, not two
-- (2026-10-29). nil when nothing is being worked out.
function H.HudMobs()
    if H._opener then return H._opener, true end
    if H.ticker then return H.mobsShown, DB().nextMark ~= false end
    return nil, false
end

function H.HudState(name)
    -- in a fight, or before one with the Whirlwind opener up
    if not (name and (H.ticker or H._opener)) then return nil end
    -- a cooldown or trinket: red when sat on, gold and a size up when
    -- wanted (and Readycheck's popup is not already saying it)
    local c = H.ticker and H.cdByName[name]
    if c then
        if c.ignored then return "noob", true end
        if c.want and not c.rcShown then return "ready", true, nil, true end
        return nil
    end
    local e = H.byName[name]
    if not e and H.execEntry and H.execEntry.name == name then e = H.execEntry end
    if not e then return nil end
    local usable = e.plateUsable and true or false
    local sb = (DB().shortfall ~= false) and e.shortBy or nil
    if H.showing == e then return "noob", usable, sb end
    if e.plateRem == 0 then
        -- the NEXT mark on: only the button to press first is "ready"
        -- (gold, a size up); every other pressable one is "ready2"
        if DB().nextMark ~= false then
            if usable and H.nextE and H.nextE ~= e then return "ready2", usable, sb end
            if usable and H.nextE == e then return "ready", usable, sb, true end
        end
        if usable and Secondary(e) then return "ready2", usable, sb end
        return usable and "ready" or "norage", usable, sb
    end
    return nil, nil, sb
end

function H:EndPreviewPlateRow()
    if prow and prow._preview then
        prow._preview = nil
        HidePlateRow()
    end
end

-- Both Bloodthirst and Whirlwind up and pressable: only the one to press
-- first (H.prioName - Whirlwind with the mobs for it) wears the gold.
Secondary = function(e)
    local p = H.prioName
    if not p or e.name == p then return false end
    if e.name ~= BT_NAME and e.name ~= WW_NAME then return false end
    local pe = H.byName[p]
    return (pe and pe.plateRem == 0 and pe.plateUsable) and true or false
end
H.Secondary = Secondary

-- One pass from the tick. state[i] = { remaining, usable } per watched
-- ability (remaining = 0 when off cooldown; nil = unknown/not shown).
function H:UpdatePlateRow(hasTarget)
    local db = DB()
    if not (db.plateCDs ~= false and hasTarget) then HidePlateRow() return end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
        and C_NamePlate.GetNamePlateForUnit("target")
    if not plate then HidePlateRow() return end
    local f = BuildPlateRow()
    -- ONE FIXED SPOT. On a ZacUI plate the row's bottom sits plateRowY
    -- above the target box over the health bar (plateRowX sideways), whatever else
    -- the plate is showing - debuff groups, aura strip, marks - so the
    -- eye always finds it in the same place; those other things are
    -- placed around it (Nameplates > Debuffs). On any other plate: just
    -- above the plate.
    local to, pt, ox, oy = plate, "TOP", 0, 6
    local zf = rawget(plate, "_zuiNP")           -- ZacUI's own plate frame
    if type(zf) == "table" and zf.health then
        to, pt = zf.health, "TOP"
        ox, oy = tonumber(db.plateRowX) or 0, (tonumber(db.plateRowY) or 2) + BOX_OUT * PlateK(zf)
    end
    if f._plate ~= plate or f._to ~= to or f._ox ~= ox or f._oy ~= oy then
        f._plate, f._to, f._pt, f._ox, f._oy = plate, to, pt, ox, oy
        f:ClearAllPoints()
        f:SetPoint("BOTTOM", to, pt, ox, oy)
    end
    local soon = tonumber(db.plateSoon) or 1.5
    local markOn = db.nextMark ~= false
    local labelOn = markOn and db.nextLabel == true
    local changed, any = false, false
    -- the watched abilities in list order, then Execute (its slot is
    -- always the last one, so the others never shuffle when it comes)
    local n = #self.watch
    local ex = self.execEntry
    local exN = ex and 1 or 0
    -- then the cooldowns and trinkets (their slots after Execute's)
    for i = 1, n + exN + #self.cds do
        local e
        if i <= n then e = self.watch[i] elseif i == n + 1 and ex then e = ex else e = self.cds[i - n - exN] end
        local ic = PlateIcon(i)
        local rem = e.plateRem
        local show = rem ~= nil and (rem <= 0 or rem <= soon)
        local nx, dim = false, false
        if show then
            any = true
            if not ic._on then
                ic._on = true
                changed = true
                ic:Show()
                if e.name ~= "Whirlwind" then ic:SetText("n", "") end
            end
            -- (a trinket swapped while its icon is up brings its own)
            if ic._tex ~= e.icon then ic._tex = e.icon ic:SetIconTexture(e.icon) end
            -- the Whirlwind icon carries the mob count the HUD scans
            -- (2 or more, in combat); the other icons never show one
            if e.name == "Whirlwind" then
                local WH = ns.WarriorHUD
                local n = H._opener or H.mobsShown or (WH and WH.State and WH.State.plateCount) or 0
                local cfg = WH and WH.Store and WH.Store()
                if cfg and cfg.wwCount == false then n = 0 end
                ic:SetText("n", n >= 2 and tostring(n) or "")
            end
            local alert
            if rem > 0 then
                -- the tenths only change ten times a second: format then
                local tenth = math_floor(rem * 10 + 0.5)
                ic._txt = nil
                if ic._tenth ~= tenth then
                    ic._tenth = tenth
                    ic:SetText("t", string_format("%.1f", tenth / 10))
                end
                ic:SetSwipe(e.plateStart or 0, e.plateDur or 0)
                ic:SetDesat(false)
                ic:SetGlow("ready", false)
                dim = false
                ic:SetGlow("alert", false)
                ic:SetGlow("norage", false)
            else
                ic._tenth = nil
                -- Overpower carries its window's time left, written the
                -- way the HUD's buff bar writes it (the same clock)
                local txt = ""
                if e.name == "Overpower" then
                    local left = ns.Overpower.Left()
                    local WH = ns.WarriorHUD
                    local W = WH and WH.Widgets
                    if left > 0 then txt = (W and W.FormatTime) and W.FormatTime(left, 0) or tostring(math_floor(left)) end
                end
                if ic._txt ~= txt then ic._txt = txt; ic:SetText("t", txt) end
                ic:ClearSwipe()
                alert = self.showing == e
                if e.isCd then alert = e.ignored and true or false end
                local usable = e.plateUsable and true or false
                -- no rage for it: greyed out (the red border stays)
                ic:SetDesat(not usable)
                ic:SetGlow("alert", alert)
                -- with the NEXT mark on, the gold is that one button's
                -- alone and every other ready one dims; off, the old
                -- rule (only Bloodthirst / Whirlwind's turn decides)
                local gold
                if e.isCd then
                    -- off the global cooldown: pressed alongside the
                    -- rotation, so never dimmed and never NEXT
                    gold = not alert
                elseif markOn then
                    nx = self.nextE == e
                    gold = nx and usable and not alert
                    dim = self.nextE ~= nil and not nx and not alert
                else
                    gold = (not alert) and usable and not Secondary(e)
                end
                ic:SetGlow("ready", gold)
                ic:SetGlow("norage", (not alert) and not usable)
            end
            if ic._dim ~= dim then
                ic._dim = dim
                ic:SetAlpha(dim and DIM_ALPHA or 1)
            end
            local lab = nx and labelOn
            if (ic._nx or false) ~= lab then
                ic._nx = lab or nil
                ic:SetText("nx", lab and "NEXT" or "")
                changed = true
            end
            if ic.texts and ic.texts.r then
                local sb = (db.shortfall ~= false) and e.shortBy
                ic:SetText("r", sb and string_format("-%d", sb) or "")
            end
            -- the NOOB grows the icon, more the longer it is ignored;
            -- pressing it (or it going away) brings it straight back
            local scale = alert and NoobScale(e, db, GetTime()) or (nx and NEXT_POP) or nil
            if ic._big ~= scale then
                ic._big = scale
                local sz = db.plateSize or 30
                local w = scale and math.floor(sz * scale + 0.5) or sz
                ic:SetSize(w, w)
                changed = true
            end

        elseif ic._on then
            ic._on = nil
            ic._tenth, ic._txt = nil, nil
            changed = true
            ic:Hide()
            if ic._big then
                ic._big = nil
                local sz = db.plateSize or 30
                ic:SetSize(sz, sz)
            end
            if ic._dim then ic._dim = nil ic:SetAlpha(1) end
            if ic._nx then ic._nx = nil ic:SetText("nx", "") end
        end
    end
    if not any then HidePlateRow() return end
    local hWas = f._rowH
    LayoutPlateRow(f, changed)
    if not f:IsShown() then f:Show() Remeasure()
    elseif f._rowH ~= hWas then Remeasure() end
end

-- Writes one alert into a frame. e = nil draws the sample.
function H:Fill(f, e, wait)
    local name = e and e.name or (self.watch[1] and self.watch[1].name) or "Bloodthirst"
    local icon = e and e.icon or (self.watch[1] and self.watch[1].icon)
    if not icon then local _, _, i = GetSpellInfo(name) icon = i end
    f.iconW:SetIconTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    f.text:SetText(self:Callout(name))
    -- the icon already says which ability: just how long it has sat ready
    if f.sub then f.sub:SetText(string_format("ready %.1fs", wait or 0)) end
end

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end
local lastSound = 0
local function Announce(e)
    local db = DB()
    local now = GetTime()
    if db.playSound and (now - lastSound) >= SOUND_GAP then
        lastSound = now
        local lib = LSM()
        local file = db.sound and db.sound ~= "" and lib and lib:Fetch("sound", db.sound, true)
        if file then pcall(PlaySoundFile, file, "Master")
        elseif db.sound and db.sound ~= "" and ns.PlaySoundRef and ns.PlaySoundRef(db.sound, "Master") then -- luacheck: ignore
        else pcall(PlaySound, 8959, "Master") end      -- the raid warning
    end
    if db.tts then
        if ns.RaidMods and ns.RaidMods.Speak then ns.RaidMods.Speak(e.name)
        elseif C_VoiceChat and C_VoiceChat.SpeakText then pcall(C_VoiceChat.SpeakText, (ns.VoiceId and ns.VoiceId()) or 0, e.name, 0, 75, 1) end
    end
end

-- The alert shows the ability that has waited longest.
function H:Show(e, wait)
    local db = DB()
    local fresh = self.showing ~= e
    self.showing = e
    if db.showPopup then
        local f = BuildPopup()
        self:Fill(f, e, wait)
        if f._leaving then
            f._leaving = nil
            if ns.Motion then ns.Motion.Stop(f) end
        end
        if not f:IsShown() then
            f._t = 0
            if ns.Motion then ns.Motion.Play(f, db.popupShow, "in") else f:Show() end
        end
    elseif popup and popup:IsShown() then
        popup:Hide()
    end
    if fresh then Announce(e) end
end

-- the alert goes ("When it goes"; instant by default)
local function HidePopup()
    if not (popup and popup:IsShown()) or popup._leaving then return end
    local spec = DB().popupHide
    if ns.Motion and spec and spec.style ~= "none" then
        popup._leaving = true
        ns.Motion.Play(popup, spec, "out", function() popup._leaving = nil end)
        if not popup:IsShown() then popup._leaving = nil end
    else
        popup:Hide()
    end
end

function H:Hide()
    self.showing = nil
    HidePopup()
end

-- the page's Test button: three seconds of the sample
function H:Preview()
    local e = self.watch[1]
    if not e then
        local known, _, icon = GetSpellInfo("Bloodthirst")
        e = { name = known or "Bloodthirst", icon = icon or "Interface\\Icons\\Spell_Nature_BloodLust", short = "BT" }
    end
    local f = BuildPopup()
    self:Fill(f, e, 1.4)
    f._t = 0
    if f._leaving then f._leaving = nil if ns.Motion then ns.Motion.Stop(f) end end
    if not f:IsShown() and ns.Motion then ns.Motion.Play(f, DB().popupShow, "in") else f:Show() end
    Announce(e)
    C_Timer.After(3, function()
        if not self.showing and popup then HidePopup() end
    end)
end

function H:ApplyAppearance()
    local db = DB()
    if popup then
        popup:SetScale(db.scale or 1)
        PlacePopup(popup.holder)
        H.PlacePopupParts(popup)
    end
    Paint()
end

-- ============================================================
-- STATS
-- ============================================================
local function Bump(t, name, delay, late, cause)
    local s = t[name]
    if not s then s = { presses = 0, late = 0, wasted = 0, worst = 0, total = 0 } t[name] = s end
    s.presses = s.presses + 1
    s.total = (s.total or 0) + delay
    if late then
        s.late = s.late + 1
        s.wasted = s.wasted + delay
        if delay > s.worst then s.worst = delay s.worstCause = cause end
    end
end

H._Bump = Bump
local MAX_EVENTS = 60       -- late presses kept per fight
local MIN_FIGHT = 6         -- seconds; shorter fights are not worth a row

function H:RecordPress(e, delay, cause)
    local late = delay >= (DB().grace or 1)
    Bump(self.stats, e.name, delay, late, cause)
    Bump(self.session, e.name, delay, late, cause)
    if e.cdDur and e.cdDur > 1.5 then
        local st = self.stats[e.name]
        st.cdDur = e.cdDur
    end
    local f = self.fight
    if late and f and #f.events < MAX_EVENTS then
        f.events[#f.events + 1] = { math_floor((GetTime() - f.start) * 10) / 10, e.short, math_floor(delay * 10) / 10 }
    end
end

-- The log lives in the per-character saved variables, outside the
-- profile, so a profile export or copy never drags the fights along.
-- 2026-10-28 audit: ONE record per pull. The scorecard's lines, the
-- Bloodthirst trend and the log used to be three stores of the same
-- pulls (hesitationCards, hesitationTrend, hesitationLog); the log entry
-- now carries the card's lines and each ability's average, and the other
-- two are read from it. The old stores are dropped once.
function H:Log()
    ZacUICharDB = ZacUICharDB or {}
    ZacUICharDB.hesitationLog = ZacUICharDB.hesitationLog or {}
    ZacUICharDB.hesitationCards, ZacUICharDB.hesitationTrend = nil, nil
    return ZacUICharDB.hesitationLog
end

-- Closes the current fight into the log: when it ran long enough, with
-- the boss (ENCOUNTER_START) or the most-targeted mob as its name.
function H:CloseFight()
    local f = self.fight
    self.fight = nil
    if not f then return end
    local db = DB()
    local dur = GetTime() - f.start
    local lines = self._card
    self._card = nil
    if not db or dur < MIN_FIGHT or #self.watch == 0 then return end
    local name = f.encounter
    if not name then
        local best = 0
        for n, c in pairs(f.targets) do if c > best then best, name = c, n end end
    end
    local abilities, anyPress = {}, false
    for _, e in ipairs(self:Tracked()) do
        local st = self.stats[e.name]
        if st and st.presses > 0 then
            anyPress = true
            abilities[#abilities + 1] = { e.short, st.presses, st.late,
                math_floor(st.wasted * 10) / 10, math_floor(st.worst * 10) / 10,
                math_floor((st.total or 0) / st.presses * 100 + 0.5) / 100 }   -- [6] average wait
        end
    end
    if not anyPress then return end
    local log = self:Log()
    log[#log + 1] = {
        at = time(), zone = f.zone, name = name or "?", dur = math_floor(dur),
        kill = f.kill, abilities = abilities, events = f.events, lines = lines,
    }
    local keep = db.logKeep or 60
    while #log > keep do table.remove(log, 1) end
end

-- ============================================================
-- THE TICK - in combat only
-- ============================================================
-- The global cooldown is not hesitation: you pressed SOMETHING. So time
-- on the GCD neither counts against an ability nor resets its clock -
-- the clock pauses - and no alert or sound is raised until the GCD is
-- over and the rest of the grace has passed. An alert already showing
-- holds quietly through it. (Without this, every other button you
-- press hides and re-shouts the alert a second later.)
local lastTick
-- Two kinds of "not ready", treated differently:
--  * the ABILITY is not pressable (real cooldown, no rage, wrong stance,
--    proc gone): its clock resets - you could not have pressed it.
--  * the SITUATION is not pressable (no living enemy target, out of
--    range, auto-attack off, on the GCD): its clock PAUSES - the ability
--    has been sitting there all along, you just could not use it this
--    instant. So a target swap, a mob dying or a step out of range does
--    not hand you a fresh grace on the next mob; the fight is tracked
--    as a whole. Going idle (nothing pressed for db.idle seconds) is
--    "parked on purpose" and resets everything.
-- The ONE button to press now, for the NEXT mark - pure priority, from
-- what this tick already worked out: in execute range Execute
-- (Bloodthirst instead while it is up with the attack power for it);
-- else Bloodthirst / Whirlwind's turn (Whirlwind with the mobs for it);
-- else the first ready one in the list. Only buttons up AND pressable
-- count. The call-out (a button you sat on) is NOT followed: it stays
-- red on its own icon, and NEXT says what to press now (2026-10-28 audit).
-- exeUp: Execute pressable on the target now; btOverExe: Bloodthirst
-- beats it at this attack power (both from the tick).
local function ReadyNow(e) return e and e.plateRem == 0 and e.plateUsable and true or false end
local function PickNext(db, exeUp, btOverExe)
    if db.nextMark == false then H.nextE = nil return end
    local pick
    if exeUp and H.execEntry then
        local bt = H.byName[BT_NAME]
        if btOverExe and ReadyNow(bt) then pick = bt else pick = H.execEntry end
    end
    if not pick then
        local p = H.prioName and H.byName[H.prioName]
        if ReadyNow(p) then
            pick = p
        else
            for i = 1, #H.watch do
                if ReadyNow(H.watch[i]) then pick = H.watch[i] break end
            end
        end
    end
    H.nextE = pick
end
H.PickNext = PickNext

local function Tick()
    local db = DB()
    if not (db and db.enabled) or #H.watch == 0 or not InCombatLockdown() then
        H:StopTicker()
        return
    end
    local now = GetTime()
    local dt = lastTick and (now - lastTick) or 0
    lastTick = now
    local gs, gd = GetSpellCooldown(ns.GCDSpell and ns.GCDSpell() or GCD_SPELL)
    local onGCD = (gs and gd and gs > 0 and gd > 0 and (gs + gd - now) > 0) and true or false
    -- the plate row wants a target at all (attacking or not)
    local plateTarget = HUD.TargetAttackable()
    local target = plateTarget
    if target and db.onlyAttacking and IsCurrentSpell and not Swinging() then
        target = false
    end
    -- in melee reach of it: one range check a tick, only with a target
    local inMelee = true
    if target and H.meleeProxy then inMelee = IsSpellInRange(H.meleeProxy, "target") == 1 end
    -- "idle" is parked-on-purpose: nothing pressed for a while AND not
    -- swinging at anything. Auto-attacking a target is the opposite of
    -- idle - that is exactly when sitting on Bloodthirst is the sin -
    -- so the idle clock never silences an alert while the swings land.
    local idle = (db.idle or 0) > 0 and (now - (H.lastPress or now)) > db.idle and not target
    -- execute phase: the target is under 20% and Execute is the button,
    -- so Bloodthirst and Whirlwind go quiet - but quiet is not the same
    -- as nothing: if Execute itself then sits unpressed past the grace
    -- while the swings land, THAT is called out ("EXE NOOB")
    -- Stunned, feared, sapped, charmed, polymorphed: you cannot press
    -- anything, so nothing is your fault. Every wait starts over (a fresh
    -- grace once you can act again), a running alert is dropped, and the
    -- plate row still shows the cooldowns. One cheap API call a tick.
    local noControl = HasFullControl and not HasFullControl() or false
    -- Heroic Strike / Cleave queued: the rage the ability below is
    -- missing is going into the next swing instead - that is the same
    -- sin, so "no rage" stops excusing a ready Bloodthirst while a swing
    -- is queued (Zac: "if im cleaving or heroic striking and letting my
    -- bt sit there")
    local dumping = SwingQueued()
    -- a trash mob about to die: pressing anything into it is a waste, so
    -- nothing is blamed (bosses never count)
    local dying = false
    if target and (db.ttkQuiet or 0) > 0 then
        local boss = (UnitClassification and UnitClassification("target") == "worldboss") or UnitLevel("target") == -1
        local left = TimeToDie(now)
        dying = (not boss) and left ~= nil and left < db.ttkQuiet
    end
    -- Execute pressable on the target right now (it is only usable under
    -- 20%): one read a tick with a target, for the quiet rule and NEXT
    local exeUp = H.hasExecute and plateTarget and Usable(EXECUTE, true)
        and IsSpellInRange(EXECUTE, "target") ~= 0 and true or false
    local executing = db.executeQuiet and target and exeUp
    -- in execute range Bloodthirst still beats Execute with enough attack
    -- power (the Warrior HUD's Execute helper reads the same setting)
    local btOverExe = exeUp and (db.execBTap or 0) > 0 and PlayerAP() >= db.execBTap
    -- which goes first when both are up: Whirlwind with enough mobs in
    -- reach (the HUD's count), Bloodthirst otherwise
    local mobs = H.MobsInReach(now)
    -- the first seconds of a pull: the pack is still running in (see
    -- THE PACK BEFORE IT REACHES YOU) - for the OPENER only: once you
    -- have pressed a button in this fight, the mobs really on you decide
    local f0 = H.fight and H.fight.start
    if f0 and now - f0 < PACK_HOLD and db.prePull ~= false and not H.fight.pressed then
        if (H.packAt or 0) >= f0 - 2 then mobs = math.max(mobs, H.packGuess or 0) end
        if now - (H._earlyAt or 0) >= 0.3 then H._earlyAt = now H._early = H.PackGuess(true) end
        mobs = math.max(mobs, H._early or 0)
    end
    H.mobsShown = mobs
    local firstAt, reach = db.wwFirstAt or 0, mobs
    if db.wwAuto ~= false and H.byName[WW_NAME] and H.byName[BT_NAME] then
        local n = AutoWWFirstAt(now)
        if n then
            firstAt = n
            if reach > WW_MAX_TARGETS then reach = WW_MAX_TARGETS end   -- it hits four at most
        end
    end
    local wwFirst = firstAt > 0 and reach >= firstAt and H.byName[WW_NAME] ~= nil
    -- a count flickering over the line (a mob stepping in and out of
    -- reach) does not flip the call back and forth: a change has to hold
    -- for 0.6 s, except the very first call of a fight
    if H.wwFirst ~= nil and wwFirst ~= H.wwFirst then
        H._wwFlipAt = H._wwFlipAt or now
        if now - H._wwFlipAt < 0.6 then wwFirst = H.wwFirst else H._wwFlipAt = nil end
    else
        H._wwFlipAt = nil
    end
    H.prioName = wwFirst and WW_NAME or BT_NAME
    H.wwFirst = wwFirst
    local rage = UnitPower and UnitPower("player", 1) or 0
    -- hidden (WoW Forever): no maths on it, so "short by" sits out
    if ns.IsSecret and ns.IsSecret(rage) then rage = nil end
    if executing and not noControl then
        if not H.execSince then H.execSince = now end
    else
        H.execSince = nil
    end
    if target and H.fight then
        local tn = UnitName("target")
        if tn and not ns.IsSecret(tn) then H.fight.targets[tn] = (H.fight.targets[tn] or 0) + 1 end
    end
    local worst, worstWait
    local showingStillReady = false
    local WH = WHud()
    for i = 1, #H.watch do
        local e = H.watch[i]
        local s, d, usable, noPower, rng
        local cdT, usT, r0 = nil, nil, nil
        if WH then cdT, usT, r0 = WH.SpellState(e.name, target) end
        if cdT then
            s, d, usable, noPower, rng = cdT.start, cdT.duration, usT.usable, usT.noPower, r0
        else
            s, d = GetSpellCooldown(e.name)
            usable, noPower = IsUsableSpell(e.name)
        end
        -- a spell on the GCD reports the GCD as its cooldown; only a
        -- cooldown that is not the GCD itself means "really used"
        local onCD = s and d and s > 0 and d > 0 and (s + d - now) > 0
            and not (onGCD and s == gs and d == gd)
        usable = usable and true or false
        -- what the ability needs besides its cooldown: Overpower the
        -- dodge window, Revenge (and Shield Slam) Defensive Stance
        local gate = H.Gate(e, usable, noPower)
        -- for the plate row: seconds left (0 = off cooldown), and whether
        -- it could be pressed right now; nil while the gate is shut
        if not gate then
            e.plateRem, e.plateStart, e.plateDur = nil, nil, nil
        elseif onCD then
            e.plateRem, e.plateStart, e.plateDur = s + d - now, s, d
        else
            e.plateRem, e.plateStart, e.plateDur = 0, nil, nil
        end
        e.plateUsable = gate and (not onCD) and usable
        -- Rage is the one thing that must not clear a running alert: the
        -- usual way to sit on Bloodthirst is to let Heroic Strike queues
        -- eat the rage it needed, which drops the button to "no rage"
        -- every other swing - and the alert vanished after a second or
        -- two for exactly the sin it was there to name. Once the alert
        -- is up, "no rage" (noPower) keeps it up as long as the ability
        -- is off cooldown; a fresh wait still needs real usability.
        local stillRageless = (H.showing == e or e.since ~= nil) and noPower and (not onCD)
        local dumped = dumping and noPower and (not onCD) and not SWING_NAMES[e.name]
        e.dumped = dumped
        local quietExec = executing and e.name ~= EXECUTE and not (btOverExe and e.name == BT_NAME)
        local able = gate and (not onCD) and (usable or stillRageless or dumped) and not idle
            and not quietExec and not noControl and not dying
        -- how much rage it is short, while it is back or nearly (the "-6")
        local need = CostOf(e)
        e.shortBy = (gate and rage and need > 0 and rage < need and (not onCD or (s + d - now) <= 1.5)) and (need - rage) or nil
        -- what kept it waiting, for the scorecard's "worst"
        if able and e.since then
            if dumped then e.cause = "HS queued"
            elseif noPower and not e.cause then e.cause = "no rage"
            elseif (H.lastPress or 0) > e.since and not e.cause then e.cause = "other buttons"
            end
        end
        if onCD then e.cdDur = d end
        if not able then
            e.since = nil
            e.cause = nil
        else
            local canHit = false
            if target then
                local r
                if cdT then r = rng else r = IsSpellInRange(e.name, "target") end
                -- its own range when it has one, melee reach when not
                canHit = (r == 1) or (r == nil and inMelee)
            end
            if canHit and not onGCD then
                e.since = e.since or now
                local wait = now - e.since
                -- the first past the grace in list order wins: the list
                -- is the priority (Bloodthirst before Whirlwind), not
                -- whichever happened to wait longest
                if wait >= (db.grace or 1) and not worst then
                    worst, worstWait = e, wait
                end
                e.waitPast = wait >= (db.grace or 1) and wait or nil
            else
                -- pause: push the start forward by this tick
                if e.since then e.since = e.since + dt end
                if canHit and H.showing == e then showingStillReady = true end
            end
        end
    end
    -- Execute's row slot: up while the target is under 20% (bosses only
    -- if so set), lit when there is rage for it, grey when not. The row
    -- is the one place the cue lives now (the plates' debuff groups no
    -- longer carry it).
    local ex = H.execEntry
    if ex then
        local low = false
        if plateTarget and db.plateExecute ~= false then
            low = HUD.TargetHealthFrac() <= 0.20
            if low and db.plateExecBoss then
                low = UnitClassification("target") == "worldboss" or UnitLevel("target") == -1
            end
        end
        if low then
            ex.plateRem, ex.plateStart, ex.plateDur = 0, nil, nil
            ex.plateUsable = Usable(EXECUTE, plateTarget) and true or false
        else
            ex.plateRem, ex.plateStart, ex.plateDur, ex.plateUsable = nil, nil, nil, nil
        end
    end
    -- the cooldowns and trinkets (off the global cooldown: every other
    -- pass, GCD or not)
    if #H.cds > 0 then
        H._cdClock = (H._cdClock or 0) + 1
        if H._cdClock % 2 == 0 then
            local boss = plateTarget and ((UnitClassification and UnitClassification("target") == "worldboss")
                or UnitLevel("target") == -1) or false
            local able = (target and inMelee and not noControl and not idle) and true or false
            H:UpdateCds(now, able, boss, plateTarget and TimeToDie(now) or nil, db)
            for _, e in ipairs(H.cds) do
                if e.fresh then e.fresh = nil Announce(e) end
            end
        end
    end
    if onGCD then
        -- nothing new while a button is going down; drop an alert whose
        -- ability stopped being pressable (target died, rage gone)
        if H.showing and not showingStillReady then H:Hide() end
        PickNext(db, exeUp, btOverExe)
        H:UpdatePlateRow(plateTarget)
        return
    end
    -- Whirlwind's turn first with the mobs for it
    if wwFirst and worst and worst.name == BT_NAME then
        local w = H.byName[WW_NAME]
        if w and w.waitPast then worst, worstWait = w, w.waitPast end
    end
    for i = 1, #H.watch do H.watch[i].waitPast = nil end
    -- with Bloodthirst the better button, Execute is not called out while BT is up
    local btUp = btOverExe and H.byName[BT_NAME] and H.byName[BT_NAME].plateRem == 0
    if not worst and executing and not noControl and not dying and not btUp and not H.byName[EXECUTE] then
        -- Execute's own clock: from the later of "became usable" and
        -- the last press of anything
        local since = math.max(H.execSince or now, H.lastPress or 0)
        local wait = now - since
        if wait >= (db.grace or 1) then
            if not H.execEntry then
                local known, _, icon = GetSpellInfo(EXECUTE)
                H.execEntry = { name = known or EXECUTE, icon = icon, short = H:ShortName(EXECUTE), isExecute = true }
            end
            worst, worstWait = H.execEntry, wait
        end
    end
    if worst then
        H:Show(worst, worstWait)
    elseif H.showing then
        H:Hide()
    end
    PickNext(db, exeUp, btOverExe)
    H:UpdatePlateRow(plateTarget)
end

function H:StartTicker()
    if self.ticker then return end
    local db = DB()
    if not (db and db.enabled) or #self.watch == 0 then return end
    lastTick = nil
    self.ticker = HUD.Ticker(TICK, Tick, "hud.hesitation")
end

function H:StopTicker()
    if self.ticker then self.ticker:Cancel() self.ticker = nil end
    for i = 1, #self.watch do
        local e = self.watch[i]
        e.since, e.plateRem, e.plateStart, e.plateDur, e.plateUsable = nil, nil, nil, nil, nil
    end
    if self.execEntry then
        local e = self.execEntry
        e.plateRem, e.plateStart, e.plateDur, e.plateUsable = nil, nil, nil, nil
    end
    if self.showing then self:Hide() end
    self.nextE = nil
    self.mobsShown = nil
    for _, e in ipairs(self.cds) do
        e.since, e.ignored, e.want, e.plateRem, e.plateUsable = nil, false, false, nil, nil
    end
    HidePlateRow()
end

function H:OnCast(spellId)
    self.lastPress = GetTime()
    if self.fight then self.fight.pressed = true end
    local name = spellId and GetSpellInfo(spellId)
    if #self.cds > 0 and self:OnCdCast(spellId, name) then return end
    if self.showing and self.showing == self.execEntry then
        -- any press ends the execute call-out; the next one waits again
        self.execSince = GetTime()
        self:Hide()
    end
    -- Whirlwind on one or two mobs while a Bloodthirst sat there ready
    if name == WW_NAME and self.fight and not self.wwFirst then
        local bt = self.byName[BT_NAME]
        if bt and bt.plateRem == 0 and bt.plateUsable then
            self.fight.wrongOrder = (self.fight.wrongOrder or 0) + 1
        end
    end
    local e = name and self.byName[name]
    if not e then return end
    local now = GetTime()
    local delay = e.since and (now - e.since) or 0
    self:RecordPress(e, delay, e.cause)
    e.since, e.cause = nil, nil
    if self.showing == e then self:Hide() end
    if self.Practice then self:Practice(e, delay) end
end

function H:OnCombatStart()
    self:StopPrePull(true)
    -- a trinket swapped (or an item that was not cached) since the last
    -- look: the list again
    local s13 = GetInventoryItemID and GetInventoryItemID("player", 13)
    local s14 = GetInventoryItemID and GetInventoryItemID("player", 14)
    local was = self._cdSlots
    if self._cdRetry or not was or was[1] ~= s13 or was[2] ~= s14 then
        self._cdRetry = nil
        self:RebuildCds()
    end
    -- a Death Wish or trinket popped just before the pull (or a moment
    -- out of combat between packs) is still running: only spent ones go
    -- (2026-10-30, Zac: "some of the stuff resets when it shouldnt")
    local t = GetTime()
    if (self.burstUntil or 0) <= t then self.burstUntil = nil end
    if (self.dwUntil or 0) <= t then self.dwUntil = nil end
    self.wwFirst, self._wwFlipAt = nil, nil
    for _, e in ipairs(self.cds) do e.since, e.ignored, e.want = nil, false, false end
    self._early, self._earlyAt = nil, nil
    wipe(self.stats)
    self.lastPress = GetTime()
    self.fight = { start = GetTime(), zone = GetRealZoneText and GetRealZoneText() or "",
                   targets = {}, events = {} }
    -- a boss pull that beat the combat flag by a moment still names the
    -- fight (the meter's rule: a start in the last 3 seconds claims it)
    local _, name, _, _, started = ns.Encounter.Info()
    if name and started and started >= GetTime() - 3 then self.fight.encounter = name end
    self:StartTicker()
end

-- the rotation buttons, then the cooldowns and trinkets (stats, log)
local trackedList = {}
function H:Tracked()
    wipe(trackedList)
    for _, e in ipairs(self.watch) do trackedList[#trackedList + 1] = e end
    for _, e in ipairs(self.cds) do trackedList[#trackedList + 1] = e end
    return trackedList
end

function H:OnCombatEnd()
    self:StopTicker()
    local db = DB()
    if db and self.Scorecard then self:Scorecard(db.scorecard == true) end
    -- each pull's numbers for the raid summary (Zacui_Meter)
    local f = self.fight
    if H.OnFightStats and f and #self.watch > 0 then
        local out = { dur = GetTime() - f.start, encounter = f.encounter, kill = f.kill,
            wrongOrder = f.wrongOrder or 0, abilities = {} }
        for _, e in ipairs(self:Tracked()) do
            local st = self.stats[e.name]
            if st and st.presses > 0 then
                out.abilities[e.name] = { short = e.short, presses = st.presses, total = st.total or 0,
                    late = st.late or 0, wasted = st.wasted or 0, worst = st.worst or 0,
                    worstCause = st.worstCause, cdDur = st.cdDur or e.cdDur }
            end
        end
        pcall(H.OnFightStats, out)
    end
    self:CloseFight()
    self:CheckPrePull()
end

-- a named boss encounter names the fight, and its end says kill or wipe
-- (ns.Encounter's "start" / "end"; a "reset" comes after the fight has
-- already closed on leaving combat)
function H:OnEncounter(event, name, success)
    local f = self.fight
    if not f then return end
    if event == "start" then
        f.encounter = name
    elseif event == "end" and f.encounter == name then
        f.kill = (success == 1) and true or false
    end
end

function H:SettingsChanged()
    self:Rebuild()
    self:ApplyAppearance()
    if InCombatLockdown() then self:StartTicker() else self:StopPrePull() self:CheckPrePull() end
    local Pv = ns.Nameplates and ns.Nameplates.Preview
    if Pv and Pv.IsShown and Pv.IsShown() then Pv.Refresh() end
end

-- ============================================================
-- THE SCORECARD - a few lines after each pull: how each watched ability
-- went (presses, average and worst delay with what caused it, roughly
-- how many casts that cost), Whirlwind pressed over a ready Bloodthirst
-- on one or two mobs, and how your Bloodthirst is trending pull to pull.
-- Click it away; it fades by itself. Its mover is "Hesitation Scorecard".
-- ============================================================
local card
local CARD_SHOW = 10
local practice = { n = 0, sum = 0 }       -- the dummy readout's running average
local function DelayHex(v)
    if v < 0.3 then return "59f259" elseif v < 0.8 then return "ffcc40" end
    return "ff5040"
end
-- Bloodthirst's average wait, pull by pull (pulls with 3+ presses), the
-- last 30, read from the log; `extra` is this pull's, not logged yet
local function Trend(extra)
    local out = {}
    local bt = H:ShortName(BT_NAME)
    for _, f in ipairs(H:Log()) do
        for _, a in ipairs(f.abilities or {}) do
            if a[1] == bt and (a[2] or 0) >= 3 and a[6] then out[#out + 1] = a[6] end
        end
    end
    if extra then out[#out + 1] = extra end
    while #out > 30 do table.remove(out, 1) end
    return out
end
local function BuildCard()
    if card then return card end
    local f = CreateFrame("Frame", "ZacUIHUD_HesitationScore", UIParent)
    f:SetSize(300, 20)
    f:SetFrameStrata("HIGH")
    HUD.PlaceAnchor("hesScore", f, { x = 0, y = 260 })
    HUD.RegisterMover("hesScore", "Hesitation Scorecard", f, { x = 0, y = 260 })
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg._zui_own = true
    bg:SetAllPoints()
    bg:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8X8")
    local w = GetColor("ui", "windowBg")
    bg:SetVertexColor(w.r, w.g, w.b, 0.88)
    if UI and UI.Border then UI.Border(f, "ui", "border") end
    f.lines = {}
    for i = 1, 6 do
        local t = HUD.Text(f, i == 1 and 12 or 11, "OUTLINE")
        t:SetJustifyH("LEFT")
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6 - (i - 1) * 15)
        t:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        t:SetWordWrap(false)
        f.lines[i] = t
    end
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function(self) self:Hide() end)
    f:SetScript("OnUpdate", function(self, el)
        self.left = (self.left or 0) - el
        if self.left <= 0 then self:Hide() return end
        self:SetAlpha(self.left < 1 and self.left or 1)
    end)
    f:Hide()
    card = f
    return f
end

-- the last pulls' cards for /zui noob: the log's records (one written
-- before the cards moved into it gets a line made from its numbers)
local function Cards()
    local out = {}
    for _, f in ipairs(H:Log()) do
        local lines = f.lines
        if not lines then
            local parts = {}
            for _, a in ipairs(f.abilities or {}) do
                parts[#parts + 1] = string_format("%s %dx, %d late", a[1], a[2] or 0, a[3] or 0)
            end
            lines = { string_format("%s  %ds", f.name or "Pull", f.dur or 0), table.concat(parts, "   ") }
        end
        out[#out + 1] = { at = f.at, lines = lines }
    end
    return out
end

function H:Scorecard(show)
    self._card = nil
    local f = self.fight
    if not f or #self.watch == 0 then return end
    local dur = GetTime() - f.start
    if dur < 6 then return end
    local lines = {}
    local name = f.encounter
    if not name then
        local best = 0
        for n, c in pairs(f.targets) do if c > best then best, name = c, n end end
    end
    lines[#lines + 1] = string_format("|cffffffff%s|r  |cff9aa5a2%ds|r", name or "Pull", math_floor(dur))
    local btAvg
    for _, e in ipairs(self:Tracked()) do
        local st = self.stats[e.name]
        if st and st.presses > 0 and #lines < 5 then
            local avg = (st.total or 0) / st.presses
            if e.name == BT_NAME then btAvg = avg end
            local txt = string_format("%s  %dx  avg |cff%s%.1fs|r", e.short, st.presses, DelayHex(avg), avg)
            if st.late > 0 then
                txt = txt .. string_format("  worst |cff%s%.1fs|r", DelayHex(st.worst), st.worst)
                if st.worstCause then txt = txt .. " (" .. st.worstCause .. ")" end
            end
            local cd = st.cdDur or e.cdDur
            if cd and cd > 1.5 and (st.total or 0) / cd >= 0.5 then
                txt = txt .. string_format("  |cffff5040~%.1f lost|r", (st.total or 0) / cd)
            end
            lines[#lines + 1] = txt
        end
    end
    if #lines == 1 then return end
    if (f.wrongOrder or 0) > 0 then
        lines[#lines + 1] = string_format("|cffffcc40WW over a ready BT x%d|r (too few mobs for WW first)", f.wrongOrder)
    end
    -- the trend: Bloodthirst's average delay, pull to pull
    local st = self.stats[BT_NAME]
    if btAvg and st and st.presses >= 3 then
        local tr = Trend(math_floor(btAvg * 100 + 0.5) / 100)
        if #tr >= 6 then
            local function Avg(a, b) local sum, n = 0, 0 for i = a, b do sum, n = sum + tr[i], n + 1 end return sum / n end
            local recent, before = Avg(#tr - 2, #tr), Avg(math.max(1, #tr - 5), #tr - 3)
            local arrow = recent < before - 0.05 and "|cff59f259better|r" or (recent > before + 0.05 and "|cffff5040worse|r" or "|cff9aa5a2steady|r")
            lines[#lines + 1] = string_format("BT trend: %.2fs -> %.2fs over your last pulls (%s)", before, recent, arrow)
        end
    end
    self._card = lines              -- kept with this pull's log record (CloseFight)
    if not show then return end
    local c = BuildCard()
    for i, t in ipairs(c.lines) do
        t:SetText(lines[i] or "")
        t:SetShown(lines[i] ~= nil)
    end
    c:SetHeight(12 + #lines * 15)
    c.left = CARD_SHOW
    c:SetAlpha(1)
    c:Show()
end

-- /zui noob [n]: the last pull's card in chat (or the last n pulls' top
-- lines), the Bloodthirst trend and the dummy practice average
function H:Report(arg)
    -- /zui noob ww: the worked-out Whirlwind-first mob count and why
    if type(arg) == "string" and arg:lower():match("^%s*ww%s*$") then
        local n = AutoWWFirstAt(GetTime(), true)
        local a = self.wwAutoInfo
        if not (n and a.n) then
            Print("Whirlwind first: no attack power / weapon damage to work it out from.")
            return
        end
        local mode = DB().wwAuto ~= false and "auto, in use" or "auto is off - the slider decides"
        if n > WW_MAX_TARGETS then
            Print(string_format("Whirlwind first: never (it would need more than %d mobs) - %s.", WW_MAX_TARGETS, mode))
        else
            Print(string_format("Whirlwind first from %d mob%s (%s).", n, n == 1 and "" or "s", mode))
        end
        Print(string_format("  %d AP: Bloodthirst ~%d, Whirlwind ~%d a mob; cooldowns %gs / %gs -> past %.2f mobs.",
            a.ap, a.bt, a.ww, a.btCD, a.wwCD, a.need))
        return
    end
    local cards = Cards()
    if #cards == 0 then
        Print("Hesitation: no pulls recorded yet - fight something first.")
        return
    end
    local n = tonumber(arg)
    if n and n > 1 then
        Print(string_format("Hesitation: the last %d pulls", math.min(n, #cards)))
        for i = math.max(1, #cards - n + 1), #cards do
            local c = cards[i]
            Print(string_format("  %s - %s", c.lines[1] or "?", c.lines[2] or ""))
        end
    else
        Print("Hesitation: your last pull")
        for _, l in ipairs(cards[#cards].lines) do Print("  " .. l) end
    end
    local tr = Trend()
    if #tr >= 2 then
        local sum = 0
        for i = 1, #tr do sum = sum + tr[i] end
        Print(string_format("  BT over %d pulls: average %.2fs late, last pull %.2fs", #tr, sum / #tr, tr[#tr]))
    end
    if practice.n > 0 then
        Print(string_format("  Dummy practice this session: %d presses, average %.2fs", practice.n, practice.sum / practice.n))
    end
end

-- ============================================================
-- PRACTICE - on a training dummy, your reaction time after each press
-- of a watched ability: big and coloured above the target's plate, with
-- the running average under it. Off the dummy nothing shows.
-- ============================================================
local react
local function IsDummy()
    local n = UnitName("target")
    return n and n:find("Dummy", 1, true) ~= nil
end
local function BuildReact()
    if react then return react end
    local f = CreateFrame("Frame", "ZacUIHUD_HesitationReact", UIParent)
    f:SetSize(160, 34)
    f:SetFrameStrata("HIGH")
    f.big = HUD.Text(f, 18, "THICKOUTLINE")
    f.big:SetPoint("TOP", f, "TOP", 0, 0)
    f.small = HUD.Text(f, 10, "OUTLINE")
    f.small:SetPoint("TOP", f.big, "BOTTOM", 0, -1)
    f:SetScript("OnUpdate", function(self, el)
        self.left = (self.left or 0) - el
        if self.left <= 0 then self:Hide() return end
        self:SetAlpha(self.left < 0.6 and (self.left / 0.6) or 1)
    end)
    f:Hide()
    react = f
    return f
end
function H:Practice(e, delay)
    local db = DB()
    if not IsDummy() then return end
    -- counted either way (for /zui noob); shown only when the readout is on
    practice.n, practice.sum = practice.n + 1, practice.sum + delay
    if not (db and db.practice == true) then return end
    local f = BuildReact()
    f.big:SetText(string_format("%s |cff%s%.2fs|r", e.short, DelayHex(delay), delay))
    f.small:SetText(string_format("avg %.2fs - %d presses", practice.sum / practice.n, practice.n))
    f:ClearAllPoints()
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
    local zf = plate and rawget(plate, "_zuiNP")
    if type(zf) == "table" and zf.health then
        f:SetPoint("BOTTOM", zf.health, "TOP", 0, 3 + (tonumber(db.plateRowY) or 2) + (prow and prow._rowH or db.plateSize or 30) + 6)
    elseif plate then
        f:SetPoint("BOTTOM", plate, "TOP", 0, 40)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    end
    f.left = 1.8
    f:SetAlpha(1)
    f:Show()
end

-- ============================================================
-- THE OPENER - before the pull (see THE PACK BEFORE IT REACHES YOU)
-- ============================================================
local preTicker
local function PrePullWanted()
    local db = DB()
    if not (db and db.enabled and db.prePull ~= false and db.nextMark ~= false and db.plateCDs ~= false) then return false end
    if InCombatLockdown() or not (H.byName[WW_NAME] and H.byName[BT_NAME]) then return false end
    return HUD.TargetAttackable() and not UnitIsDead("target")
end
local function ClearOpener()
    if not H._opener then return end
    H._opener = nil
    local w = H.byName[WW_NAME]
    if w then w.plateRem, w.plateUsable = nil, nil end
    H.nextE = nil
    HidePlateRow()
end
local function ShowOpener(n)
    for i = 1, #H.watch do
        local e = H.watch[i]
        e.plateRem, e.plateStart, e.plateDur, e.plateUsable, e.shortBy = nil, nil, nil, nil, nil
    end
    local ex = H.execEntry
    if ex then ex.plateRem, ex.plateUsable = nil, nil end
    local w = H.byName[WW_NAME]
    w.plateRem, w.plateUsable = 0, true
    H.showing = nil
    H.nextE = w
    H._opener = n
    H:UpdatePlateRow(true)
end
local function PrePullTick()
    if not PrePullWanted() then H:StopPrePull() return end
    local db = DB()
    local n = H.PackGuess(false)
    H.packGuess, H.packAt = n, GetTime()
    local firstAt = db.wwFirstAt or 0
    if db.wwAuto ~= false then firstAt = AutoWWFirstAt(GetTime()) or firstAt end
    if firstAt > 0 and math.min(n, WW_MAX_TARGETS) >= firstAt then ShowOpener(n) else ClearOpener() end
end
-- keep: entering combat - the guess stays for the fight's first seconds
function H:StopPrePull(keep)
    if preTicker then preTicker:Cancel() preTicker = nil end
    ClearOpener()
    if not keep then self.packGuess, self.packAt = nil, nil end
end
function H:CheckPrePull()
    if PrePullWanted() then
        if not preTicker then
            preTicker = HUD.Ticker(0.25, PrePullTick, "hud.hesitation.prepull")
            PrePullTick()
        end
    elseif preTicker then
        self:StopPrePull()
    end
end

-- ============================================================
-- EVENTS
-- ============================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("SPELLS_CHANGED")       -- also fires when a spell is learned
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
local rebuildQueued = false
-- UNIT_SPELLCAST_SUCCEEDED: unit, castGUID, spellId
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if a1 == "player" then H:OnCast(a3) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        H:OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        H:OnCombatEnd()
    elseif event == "PLAYER_TARGET_CHANGED" then
        if not InCombatLockdown() then H:CheckPrePull() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- a trinket in or out: the list again (a1 = the slot)
        if a1 == 13 or a1 == 14 then H:RebuildCds() end
    else
        -- SPELLS_CHANGED comes in bursts at login and on talent swaps
        if rebuildQueued then return end
        rebuildQueued = true
        C_Timer.After(0.5, function()
            rebuildQueued = false
            H:Rebuild()
            if InCombatLockdown() then H:StartTicker() end
        end)
    end
end)
ns.Encounter.On("HUD.Hesitation", function(event, _, name, _, _, success)
    H:OnEncounter(event, name, success)
end)

-- ============================================================
-- CONFIG PAGE (Class HUDs > Hesitation Alerts)
-- ============================================================
local function SoundItems()
    local items = { { text = "Raid warning (default)", value = "" } }
    -- the game's own sounds, under plain names
    if ns.Sounds and ns.Sounds.PickerItems then
        for _, it in ipairs(ns.Sounds.PickerItems()) do items[#items + 1] = it end
    end
    local lib = LSM()
    if lib then
        local list = lib:List("sound") or {}
        for _, name in ipairs(list) do items[#items + 1] = { text = name, value = name } end
    end
    return items
end

local function Clock(secs)
    return string_format("%d:%02d", math_floor(secs / 60), math_floor(secs % 60))
end

-- One row per fight, newest first: when, what, how long, and the late
-- presses per ability. A Details button opens the fight's late presses
-- in order; Close folds it back.
local function BuildLogCard(L)
    L:Card("Fight log")
    local log = H:Log()
    if #log == 0 then
        L:Desc("No fights logged yet. Fights longer than 6 seconds with at least one press of a "
            .. "watched ability are kept here, newest first.")
        L:EndCard()
        return
    end
    local shown = 0
    for i = #log, 1, -1 do
        local f = log[i]
        shown = shown + 1
        if shown > 40 then break end
        local parts = {}
        local anyLate = false
        for _, a in ipairs(f.abilities or {}) do
            if a[3] > 0 then
                anyLate = true
                parts[#parts + 1] = string_format("%s late %dx (%.1fs)", a[1], a[3], a[4])
            end
        end
        local when = date("%a %H:%M", f.at or 0)
        local tag = f.kill == true and "  kill" or (f.kill == false and "  wipe" or "")
        local head = string_format("%s   %s%s   %s", when, f.name or "?", tag, Clock(f.dur or 0))
        local line = #parts > 0 and (head .. "   -   " .. table.concat(parts, ", ")) or (head .. "   -   clean")
        local card = L.current
        local y = card._y or 0
        HUD.Label(L, line, anyLate and "orange" or "normal")
        if anyLate then
            local open = H.openFight == i
            local b = UI.Button(card, open and "Close" or "Details", { width = 70, height = 18, onClick = function()
                H.openFight = (not open) and i or nil
                HUD.RefreshPage()
            end })
            b:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, y + 1)
            if open then
                for _, ev in ipairs(f.events or {}) do
                    HUD.Label(L, string_format("      %s   %s sat ready %.1fs", Clock(ev[1]), ev[2], ev[3]), "gray")
                end
                local tot = {}
                for _, a in ipairs(f.abilities or {}) do
                    tot[#tot + 1] = string_format("%s %d pressed, %d late, worst %.1fs", a[1], a[2], a[3], a[5])
                end
                HUD.Label(L, "      " .. table.concat(tot, "  |  "), "gray")
                L:Gap(4)
            end
        end
    end
    if #log > 40 then L:Desc(string_format("Showing the last 40 of %d fights.", #log)) end
    L:Gap(4)
    HUD.Button(L, "Clear the log", 120, function()
        wipe(H:Log())
        H.openFight = nil
        HUD.RefreshPage()
    end)
    L:EndCard()
end

-- The preview: the nameplate row (every state of it, over a plain bar
-- standing in for the target's plate) or the big alert, both built by the
-- same functions as the live ones (MakePlateIcon / FillSampleRow /
-- LayoutPlateRow, MakePopup / Fill / PaintFrame).
local function PreviewSpec()
    return {
        key = "hud.hesitation", title = "Hesitation",
        width = 200, height = 60,   -- the fitting sizes the canvas to the sample
        modes = { { id = "row", label = "Nameplate row" }, { id = "alert", label = "Big alert" } },
        build = function(canvas, P)
            local st = P.store
            -- all of it on the stage, so the fitting can keep it inside the canvas
            local stage = HUD.SampleStage(canvas)
            local bar = CreateFrame("StatusBar", nil, stage)
            bar:SetSize(130, 10)
            bar:SetPoint("CENTER", stage, "CENTER", 0, -30)
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0.62)
            bar:SetStatusBarTexture(ns.ResolveBarTexture and ns.ResolveBarTexture(nil) or "Interface\\Buttons\\WHITE8X8")
            bar:SetStatusBarColor(0.8, 0.15, 0.15, 1)
            local bbg = bar:CreateTexture(nil, "BACKGROUND")
            bbg:SetAllPoints()
            bbg:SetTexture("Interface\\Buttons\\WHITE8X8")
            bbg:SetVertexColor(0, 0, 0, 0.6)
            local lab = HUD.Text(bar, 9, "OUTLINE")
            lab:SetPoint("CENTER", bar, "CENTER", 0, 0)
            lab:SetText("Target")
            st.bar = bar
            local row = CreateFrame("Frame", nil, stage)
            row:SetSize(24, 24)
            row.icons = {}
            st.row = row
            st.alert = MakePopup(stage, nil)
            st.alert:ClearAllPoints()
            st.alert:SetPoint("CENTER", stage, "CENTER", 0, 0)
        end,
        update = function(canvas, P)
            local st, db = P.store, DB()
            if not (st.row and db) then return end
            HUD.CheckLook()
            local alertMode = P.mode == "alert"
            st.bar:SetShown(not alertMode)
            -- the row
            local sz = db.plateSize or 30
            for _, ic in ipairs(st.row.icons) do
                ic._big = nil
                ic:SetSize(sz, sz)
            end
            FillSampleRow(st.row)
            for _, ic in ipairs(st.row.icons) do PaintPlateIcon(ic) end
            st.row:ClearAllPoints()
            st.row:SetPoint("BOTTOM", st.bar, "TOP", tonumber(db.plateRowX) or 0, (tonumber(db.plateRowY) or 2) + BOX_OUT)
            st.row:SetShown(not alertMode and db.plateCDs ~= false)
            -- the alert
            local f = st.alert
            H:Fill(f, nil, 1.4)
            PaintFrame(f)
            H.PlacePopupParts(f)
            f:SetScale(tonumber(db.scale) or 1)
            if alertMode then
                if not f:IsShown() then f:Show() Arm(f) end
            else
                if ns.Motion then ns.Motion.Stop(f) end
                f:Hide()
            end
        end,
        replay = function(canvas, P)
            local st, db = P.store, DB()
            if not (st.alert and P.mode == "alert") then return end
            local f = st.alert
            if ns.Motion then
                ns.Motion.Stop(f)
                f:Hide()
                ns.Motion.Play(f, db.popupShow, "in")
            else
                f:Show()
            end
            Arm(f)
        end,
    }
end

-- a colour setting that follows ZacUI's palette until it is set
local function PalColor(L, cfg, label, key, cat, pkey, a)
    return { label,
        get = function() return Pal(cfg[key], cat, pkey, a) end,
        set = function(r, g, b, al)
            cfg[key] = { r = r, g = g, b = b, a = al or a or 1 }
            H:ApplyAppearance()
        end }
end

local function Tab_General(L, cfg)
    local function Changed() H:SettingsChanged() end
    L:Card("Alert")
    L:Desc("In combat, each watched ability is checked ten times a second: off cooldown, "
        .. "enough rage (and the right stance), a living enemy target in range. Once that has "
        .. "been true for the grace time and you still have not pressed it, the alert shows "
        .. "until you do. Time on the global cooldown never counts and never resets the clock - "
        .. "pressing other buttons is not hesitation - and nothing new is raised while you are "
        .. "on it. Every press is timed; the late ones are summed up when combat ends.")
    HUD.Check(L, "Enable hesitation alerts", cfg.enabled, function(v)
        cfg.enabled = v
        Changed()
        HUD.RefreshPage()
    end)
    if cfg.enabled then
        HUD.Slider(L, "Grace time", 0.3, 3.0, cfg.grace or 1, function(v)
            cfg.grace = math_floor(v * 10 + 0.5) / 10
        end, { width = 250, step = 0.1, format = function(v) return string_format("%.1fs", v) end,
            desc = "How long an ability may sit pressable before you get shouted at. "
            .. "1.0s catches real hesitation without nagging during normal weaving." })
        local labels = {}
        local items = {}
        for _, s in ipairs(H.STYLES) do labels[s.key] = s.label items[#items + 1] = { text = s.label, value = s.key } end
        HUD.Dropdown(L, 200, items,
            function() return labels[cfg.style] or labels.noob end,
            function(v) cfg.style = v Changed() end,
            "Wording of the alert.")
        HUD.Check(L, "Big alert above the active buff row", cfg.showPopup, function(v)
            cfg.showPopup = v Changed()
        end, "Sits above the Warrior HUD's active buffs until dragged; its mover is \"Hesitation Alert\".")
        HUD.Check(L, "Cooldowns over the target's nameplate", cfg.plateCDs ~= false, function(v)
            cfg.plateCDs = v and true or false Changed() HUD.RefreshPage()
        end)
        if cfg.plateCDs ~= false then
            L:Desc("An icon per watched ability appears over your target's nameplate when "
                .. "the ability is this close to coming back (counting down), and stays while "
                .. "it is ready: gold border = press it, red pulse = the alert. On a longer "
                .. "cooldown the icon is gone. In combat only, with a target.")
            HUD.Slider(L, "Show from", 0.5, 5, cfg.plateSoon or 1.5, function(v)
                cfg.plateSoon = v Changed()
            end, { step = 0.1, format = function(v) return string_format("%.1fs left", v) end })
            L:Desc("Overpower rides the row only while its dodge window is open; Execute joins it "
                .. "while the target is under 20% (gold with the rage for it, grey without).")
            HUD.Check(L, "Execute in the row", cfg.plateExecute ~= false, function(v)
                cfg.plateExecute = v and true or false Changed() HUD.RefreshPage()
            end)
            if cfg.plateExecute ~= false then
                HUD.Check(L, "...on bosses only", cfg.plateExecBoss and true or false, function(v)
                    cfg.plateExecBoss = v and true or false Changed()
                end)
            end
        end
        HUD.Check(L, "Play a sound when an alert starts (off by default)", cfg.playSound, function(v)
            cfg.playSound = v Changed() HUD.RefreshPage()
        end)
        if cfg.playSound then
            HUD.Dropdown(L, 260, SoundItems(),
                function() return (cfg.sound and cfg.sound ~= "") and cfg.sound or "Raid warning (default)" end,
                function(v)
                    cfg.sound = v
                    local lib = LSM()
                    local file = v ~= "" and lib and lib:Fetch("sound", v, true)
                    if file then pcall(PlaySoundFile, file, "Master")
                    elseif v ~= "" and ns.PlaySoundRef and ns.PlaySoundRef(v, "Master") then -- luacheck: ignore
                    else pcall(PlaySound, 8959, "Master") end
                end,
                "Any LibSharedMedia sound.")
        end
        HUD.Check(L, "Say the ability name (text-to-speech)", cfg.tts, function(v)
            cfg.tts = v Changed()
        end)
        L:Gap(6)
        HUD.Label(L, "When you are parked on purpose")
        HUD.Check(L, "Only while auto-attacking", cfg.onlyAttacking, function(v)
            cfg.onlyAttacking = v Changed()
        end, "Nothing shows unless Attack is toggled on against a living target in range. "
            .. "A target swap, a mob dying or a step out of range only pauses an ability's "
            .. "clock - the fight is tracked as a whole, not per mob.")
        HUD.Check(L, "Quiet while Execute is usable", cfg.executeQuiet, function(v)
            cfg.executeQuiet = v Changed()
        end, "Target under 20% and the rage for Execute: Bloodthirst and Whirlwind stop being "
            .. "called out until it is gone.")
        HUD.Slider(L, "Go quiet after this long without pressing anything", 0, 30, cfg.idle or 0, function(v)
            cfg.idle = v
        end, { width = 250, format = function(v) return v == 0 and "never" or (v .. "s") end,
            desc = "No spell of any kind for this long and the alert stops until your next press. "
                .. "Covers an auto-attack left on while you wait. 0 turns it off." })
        L:Gap(4)
        HUD.Button(L, "Test the alert", 150, function() H:Preview() end,
            "Three seconds of the big alert where it sits on screen.")
    end
    L:EndCard()

    if not cfg.enabled then return end

    L:Card("Smarter")
    L:Desc("What makes a call-out fair, and what helps you get better.")
    HUD.Check(L, "Scorecard popup after each pull", cfg.scorecard == true, function(v)
        cfg.scorecard = v and true or false
    end, "Every pull is scored either way: each ability's presses, average and worst delay (and "
        .. "what caused it), roughly how many casts that cost, and your Bloodthirst trend. Type "
        .. "/zui noob for the last pull in chat, /zui noob 10 for the last ten. Ticked, it also "
        .. "pops up when combat ends (mover \"Hesitation Scorecard\").")
    HUD.Slider(L, "Quiet on a mob about to die", 0, 4, cfg.ttkQuiet or 1.5, function(v)
        cfg.ttkQuiet = v Changed()
    end, { step = 0.25, format = function(v) return v > 0 and string_format("under %.2fs", v) or "off" end,
        desc = "Time to die is read from how fast the target's health is falling. Never on a boss." })
    HUD.Slider(L, "Bloodthirst over Execute from", 0, 3000, cfg.execBTap or 2000, function(v)
        cfg.execBTap = v Changed()
    end, { step = 50, format = function(v) return v > 0 and (v .. " AP") or "off" end,
        desc = "In execute range with this much attack power, Bloodthirst is still the call and "
            .. "Execute is not called out while it is up - the Warrior HUD's Execute helper uses "
            .. "the same line." })
    HUD.Check(L, "Work out when Whirlwind goes first", cfg.wwAuto ~= false, function(v)
        cfg.wwAuto = v and true or false Changed()
    end, "From your attack power and main-hand damage (the character sheet's, with your buffs): "
        .. "Whirlwind goes before Bloodthirst from the mob count where letting it wait costs more "
        .. "than letting Bloodthirst wait. Checked again every couple of seconds in combat. "
        .. "/zui noob ww shows the numbers. Unticked, the slider below decides.")
    HUD.Slider(L, "Whirlwind before Bloodthirst from", 0, 6, cfg.wwFirstAt or 3, function(v)
        cfg.wwFirstAt = v Changed()
    end, { step = 1, format = function(v) return v > 0 and (v .. " mobs") or "never" end,
        desc = "With both up, only the one to press first wears the gold. Whirlwind pressed on "
            .. "fewer mobs while Bloodthirst sat ready is noted on the scorecard and in the raid "
            .. "summary." })
    HUD.Check(L, "Mark the button to press first", cfg.nextMark ~= false, function(v)
        cfg.nextMark = v and true or false Changed() HUD.RefreshPage()
    end, "Of everything up and pressable, exactly one keeps the gold and comes up a size on the "
        .. "nameplate row (and on the Warrior HUD): Execute in execute range (Bloodthirst instead "
        .. "from the attack power above), Whirlwind from the mob count above, Bloodthirst otherwise, "
        .. "then the list order below. The other ready buttons dim. A button you have been sitting "
        .. "on still turns red and grows - gold is what to press now, red is what you ignored.")
    if cfg.nextMark ~= false then
        HUD.Check(L, "...and write NEXT over it", cfg.nextLabel == true, function(v)
            cfg.nextLabel = v and true or false Changed()
        end)
        HUD.Check(L, "Count the pack before you charge it", cfg.prePull ~= false, function(v)
            cfg.prePull = v and true or false Changed()
        end, "Out of combat, with your target in Charge range: it and the mobs at about the same "
            .. "distance near it on screen are counted. Enough for Whirlwind first, and Whirlwind "
            .. "shows over your target as the opener (with the count) - and stays the call for the "
            .. "first seconds of the pull while the pack runs in. A guess from ranges: another pack "
            .. "just as far away and close on screen counts too.")
    end
    HUD.Check(L, "Show the rage it is short (\"-6\")", cfg.shortfall ~= false, function(v)
        cfg.shortfall = v and true or false Changed()
    end, "On the nameplate row and the Warrior HUD, while Bloodthirst / Whirlwind are back or "
        .. "under 1.5s from it and you cannot pay for them yet.")
    HUD.Check(L, "Practice: reaction time on a training dummy", cfg.practice == true, function(v)
        cfg.practice = v and true or false
    end, "After each press of a watched ability on a dummy: how long it sat ready, coloured "
        .. "(green under 0.3s, yellow under 0.8s), with your running average.")
    L:EndCard()

    L:Card("Cooldowns and trinkets")
    L:Desc("Death Wish, Blood Fury / Berserking and every on-use trinket you wear are watched "
        .. "too. When one should be pressed it lights gold on the nameplate row and the Warrior "
        .. "HUD; sat on past the grace while you swing, it turns red and grows, and the scorecard "
        .. "counts it. When should it be pressed: Readycheck's plan first - a boss or mob your raid "
        .. "profile has that cooldown on waits for Readycheck's reminder, and only then can you be "
        .. "late. Otherwise, in boss fights: Death Wish in the fight's last 30 seconds, the trinkets "
        .. "in Death Wish's last 15 - nothing is called before that.")
    HUD.Check(L, "Watch cooldowns and trinkets", cfg.cdEnabled ~= false, function(v)
        cfg.cdEnabled = v and true or false Changed() HUD.RefreshPage()
    end)
    if cfg.cdEnabled ~= false then
        HUD.Slider(L, "Called out after", 0.5, 5, cfg.cdGrace or 1.5, function(v)
            cfg.cdGrace = math_floor(v * 10 + 0.5) / 10
        end, { step = 0.1, format = function(v) return string_format("%.1fs", v) end })
        HUD.Check(L, "On trash too, not only bosses", cfg.cdTrash == true, function(v)
            cfg.cdTrash = v and true or false Changed()
        end, "Stacking a trinket onto a burst you already started counts everywhere either way.")
        HUD.Slider(L, "Death Wish in the fight's last", 10, 120, cfg.dwAt or 30, function(v)
            cfg.dwAt = v Changed()
        end, { step = 5, format = function(v) return v .. "s" end,
            desc = "Time left from Readycheck's time-to-kill (your kill history) when it has one, "
                .. "else from how fast the target's health falls. Before that Death Wish is held - "
                .. "nothing is called at the start of a fight." })
        HUD.Slider(L, "Trinkets in Death Wish's last", 5, 30, cfg.trinketAt or 15, function(v)
            cfg.trinketAt = v Changed()
        end, { step = 1, format = function(v) return v .. "s" end,
            desc = "Blood Fury / Berserking too. With no Death Wish still to come this fight, the "
                .. "fight's last that-many seconds instead." })
        HUD.Check(L, "Also use a trinket early when it will be back for the end", cfg.cdEarly == true, function(v)
            cfg.cdEarly = v and true or false Changed()
        end, "On a long fight a two-minute trinket can go once early and still be ready for Death Wish.")
        HUD.Check(L, "Recklessness too", cfg.cdReck == true, function(v)
            cfg.cdReck = v and true or false Changed()
        end, "Its 30 minute cooldown is usually planned for one boss - Readycheck's raid profile is the "
            .. "better place for it.")
        local title = UI.Font(L.current, UI.F and UI.F.LABEL or 12, { text = "Never call these trinkets (comma between each)" })
        L:Row(title, 16)
        local sk = UI.EditBox(L.current, { width = 300, text = cfg.cdSkip or "", hint = "Lifegiving Gem",
            onChange = function(v) cfg.cdSkip = v end,
            onEnter = function(v) cfg.cdSkip = v Changed() end })
        L:Row(sk, UI.M.EDIT_H + 8)
        L:Desc("PvP insignias, Carrot on a Stick, Lifegiving Gem and other non-damage trinkets are left out already.")
    end
    L:EndCard()

    L:Card("Abilities")
    L:Desc("Ticked abilities are watched when you know them, and the order is the "
        .. "priority: when more than one is overdue, the highest on the list is the one "
        .. "called out (Bloodthirst before Whirlwind). Procs like Revenge and Overpower "
        .. "only count while they are actually usable, and a wrong stance never counts "
        .. "against you.")
    for _, name in ipairs(H:CandidateNames()) do
        local known = GetSpellInfo(name)
        local label = name .. "  |cff888888(" .. H:ShortName(name) .. ")|r"
        if not known then label = label .. "  |cff666666not known|r" end
        HUD.Check(L, label, H:IsWatched(name), function(v)
            if v then cfg.abilities[name] = nil else cfg.abilities[name] = false end
            Changed()
        end)
    end
    local isCustom = {}
    for _, c in ipairs(cfg.custom) do isCustom[c] = true end
    if next(isCustom) ~= nil then
        local items = {}
        for _, c in ipairs(cfg.custom) do items[#items + 1] = { text = c, value = c } end
        HUD.Dropdown(L, 220, items,
            function() return "Remove an added ability..." end,
            function(v)
                for i = #cfg.custom, 1, -1 do if cfg.custom[i] == v then table.remove(cfg.custom, i) end end
                cfg.abilities[v] = nil
                Changed()
                HUD.RefreshPage()
            end)
    end
    L:Gap(4)
    HUD.Label(L, "Add an ability by name")
    local eb = UI.EditBox(L.current, { width = 220, hint = "e.g. Execute", onEnter = function(text)
        text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then return end
        local known = GetSpellInfo(text)
        local name = known or text
        for _, c in ipairs(cfg.custom) do if c:lower() == name:lower() then return end end
        cfg.custom[#cfg.custom + 1] = name
        Changed()
        HUD.RefreshPage()
    end })
    L:Row(eb, UI.M.EDIT_H + 8)
    L:Desc("Type the spell's exact name and press Enter. It is matched against your spellbook, "
        .. "so a spell you do not know is listed greyed out until you learn it.")
    L:EndCard()
end

local function Tab_Look(L, cfg)
    local function Changed() H:SettingsChanged() end
    L:Card("Big alert")
    HUD.Slider(L, "Alert size", 60, 200, math_floor((cfg.scale or 1) * 100 + 0.5), function(v)
        cfg.scale = v / 100
        H:ApplyAppearance()
    end, { width = 250, format = function(v) return v .. "%" end })
    HUD.ColorGrid(L, {
        PalColor(L, cfg, "Alert text", "alertColor", "text", "red"),
        PalColor(L, cfg, "Time ready text", "subColor", "text", "gray"),
        PalColor(L, cfg, "Background", "bgColor", "ui", "cardBg", 0.85),
        PalColor(L, cfg, "Edge", "edgeColor", "ui", "border"),
    })
    L:Desc("Until you pick one, each colour follows ZacUI's palette (Appearance > Colours).")
    L:EndCard()

    L:Card("Nameplate row")
    HUD.Slider(L, "Icon size", 16, 48, cfg.plateSize or 30, function(v)
        cfg.plateSize = v
        if prow then
            for _, ic in ipairs(prow.icons) do ic:SetSize(v, v) ic._big = nil end
            prow._sig = nil
        end
        Changed()
    end, { format = function(v) return v .. "px" end })
    HUD.Check(L, "A NOOB icon keeps growing while you ignore it", cfg.plateGrow ~= false, function(v)
        cfg.plateGrow = v Changed()
    end)
    HUD.Slider(L, "...up to", 1.4, 3.0, cfg.plateGrowMax or 2.0, function(v)
        cfg.plateGrowMax = math.floor(v * 10 + 0.5) / 10 Changed()
    end, { step = 0.1, format = function(v) return string.format("%.1fx", v) end })
    HUD.ColorGrid(L, {
        PalColor(L, cfg, "Press it (gold)", "readyColor", "ui", "accent"),
        PalColor(L, cfg, "The NOOB glow", "noobColor", "text", "red"),
        PalColor(L, cfg, "Ready, no rage", "noRageColor", "text", "red", 0.85),
    })
    L:EndCard()
    HUD.SharedLookCards(L)
end

local function Tab_Text(L, cfg)
    L:Card("Big alert text")
    local fp = UI.FontPicker(L.current, { label = "Call-out", width = 400,
        get = function() return cfg.alertFont end,
        set = function(spec) cfg.alertFont = spec H:ApplyAppearance() end,
        defaults = { size = 18, outline = "thick", shadow = true }, minSize = 8, maxSize = 40,
        sample = "BT NOOB" })
    L:Add(fp, 6)
    local sp = UI.FontPicker(L.current, { label = "Time ready", width = 400,
        get = function() return cfg.subFont end,
        set = function(spec) cfg.subFont = spec H:ApplyAppearance() end,
        defaults = { size = 11, outline = "outline", shadow = true }, minSize = 6, maxSize = 24,
        sample = "ready 1.4s" })
    L:Add(sp, 6)
    L:EndCard()

    -- where the call-out and the time sit on the strip (db.anchors.*;
    -- nothing saved = as always)
    L:Card("Where the alert's texts sit")
    local targets = { { value = "strip", text = "The strip" }, { value = "icon", text = "The icon" },
        { value = "text", text = "The call-out" }, { value = "time", text = "The time ready" } }
    local function Apply() H:ApplyAppearance() end
    for _, e in ipairs({ { "alertText", "Call-out" }, { "alertTime", "Time ready" } }) do
        local ag, as = ns.CustomAccess(cfg, "anchors", e[1], Apply)
        local d = H.POPUP_ANCHORS[e[1]]
        UI.TextElement(L, { key = "hud." .. e[1], label = e[2], anchorGet = ag, anchorSet = as,
            anchorDefaults = d, targets = targets, defaultTargetLabel = d.label, anchorMin = -80, anchorMax = 80 })
    end
    L:EndCard()
    HUD.SharedTextCards(L)
end

local function Tab_Anim(L, cfg)
    L:Card("Big alert")
    local a = UI.AnimationPicker(L.current, { label = "When it appears",
        get = function() return cfg.popupShow end, set = function(spec) cfg.popupShow = spec end })
    L:Add(a, 6)
    local b = UI.AnimationPicker(L.current, { label = "When it goes", styles = HUD.EXIT_STYLES,
        get = function() return cfg.popupHide end, set = function(spec) cfg.popupHide = spec end })
    L:Add(b, 6)
    HUD.Check(L, "Pulse the call-out while it is up", cfg.pulse ~= false, function(v)
        cfg.pulse = v and true or false
    end)
    L:EndCard()
    HUD.SharedAnimCards(L)
end

local function Tab_Position(L, cfg)
    local function Changed() H:SettingsChanged() end
    L:Card("Big alert")
    HUD.Button(L, "Unlock / lock the alert", 170, function()
        BuildPopup()
        HUD.ToggleMovers("hesitation")
    end, "Also on ZacUI's Movers page and in Edit Mode.")
    L:EndCard()
    L:Card("The alert's icon")
    do
        local ag, as = ns.CustomAccess(cfg, "anchors", "alertIcon", function() H:ApplyAppearance() end)
        local d = H.POPUP_ANCHORS.alertIcon
        UI.FrameElement(L, { key = "hud.alertIcon", anchorGet = ag, anchorSet = as, anchorDefaults = d,
            targets = { { value = "strip", text = "The strip" }, { value = "text", text = "The call-out" },
                { value = "time", text = "The time ready" } },
            defaultTargetLabel = d.label, anchorMin = -80, anchorMax = 80, gap = 4 })
    end
    L:EndCard()
    L:Card("Nameplate row")
    L:Desc("Where the row sits over a ZacUI plate: a fixed spot just over the target box "
        .. "round the health bar, the same whatever else the plate shows.")
    HUD.Slider(L, "Row: up from the target box", 0, 60, cfg.plateRowY or 2, function(v)
        cfg.plateRowY = v Changed()
    end, { format = function(v) return v .. "px" end })
    HUD.Slider(L, "Row: sideways", -150, 150, cfg.plateRowX or 0, function(v)
        cfg.plateRowX = v Changed()
    end, { format = function(v) return v .. "px" end })
    L:EndCard()
end

local function Tab_Advanced(L, cfg)
    L:Card("This session")
    local any = false
    for _, e in ipairs(H:Tracked()) do
        local s = H.session[e.name]
        if s and s.presses > 0 then
            any = true
            HUD.Label(L, string_format("%s: %d presses, %d late (%.1fs wasted, worst %.1fs)",
                e.name, s.presses, s.late, s.wasted, s.worst), s.late > 0 and "orange" or "normal")
        end
    end
    if not any then
        L:Desc("Nothing recorded yet this session. Fights are counted from the first combat after login.")
    else
        L:Gap(4)
        HUD.Button(L, "Clear", 90, function() wipe(H.session) HUD.RefreshPage() end)
    end
    L:EndCard()

    BuildLogCard(L)

    L:Card("Reset")
    HUD.Button(L, "Reset the look", 150, function()
        cfg.alertColor, cfg.subColor, cfg.bgColor, cfg.edgeColor = nil, nil, nil, nil
        cfg.readyColor, cfg.noobColor, cfg.noRageColor = nil, nil, nil
        cfg.alertFont = { size = 18, outline = "thick", shadow = true }
        cfg.subFont = { size = 11, outline = "outline", shadow = true }
        cfg.popupShow = ns.CopySetting(DEFAULTS.popupShow)
        cfg.popupHide = ns.CopySetting(DEFAULTS.popupHide)
        cfg.pulse = true
        H:ApplyAppearance()
        ns.SettingsChanged("reset")
        HUD.RefreshPage()
    end, "The alert's and the row's colours, fonts and animations back to the defaults.")
    L:EndCard()
end

local function BuildPage(L)
    L:Header("Hesitation Alerts",
        "Calls you out when an ability sits ready and you are not pressing it")
    local cfg = DB()
    if not cfg then
        L:Notice("missing", "The hesitation settings are not available yet.")
        return
    end
    -- fitted after every update: in the dock's strata, the canvas the
    -- sample's box (the big alert at its own scale, as it shows in game)
    L:Preview(HUD.FitSpec(PreviewSpec()))
    L:Tabs({
        { id = "general", label = "General",   build = function(L2) Tab_General(L2, cfg) end },
        { id = "look",    label = "Look",      build = function(L2) Tab_Look(L2, cfg) end },
        { id = "text",    label = "Text",      build = function(L2) Tab_Text(L2, cfg) end },
        { id = "anim",    label = "Animation", build = function(L2) Tab_Anim(L2, cfg) end },
        { id = "pos",     label = "Position",  build = function(L2) Tab_Position(L2, cfg) end },
        { id = "adv",     label = "Advanced",  build = function(L2) Tab_Advanced(L2, cfg) end },
    })
end

HUD.RegisterPage("hesitation", "Hesitation Alerts",
    "hesitation noob bt noob ww noob late slow press not pressing button idle wasted bloodthirst whirlwind apm "
    .. "nameplate row glow fight log scorecard " .. HUD.PAGE_KEYWORDS,
    nil,
    BuildPage)

-- first build once the settings exist
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(1, function()
        H:Rebuild()
        if InCombatLockdown() then H:StartTicker() end
    end)
end)
