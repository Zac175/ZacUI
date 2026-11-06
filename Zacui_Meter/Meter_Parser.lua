-- Meter_Parser - the combat log reader. One frame, one dispatch table,
-- zero allocation on the hot path except new actors and new spells.
-- Part of ZacUI; load order is set by the TOC.
--
-- POLICY, ported from Details' Classic parser so the numbers agree:
--   * melee swings record under synthetic spellId 1, auto shot under 2,
--     environmental damage under 3-8
--   * partial absorbs COUNT AS DAMAGE DONE (amount + absorbed); fully
--     absorbed hits arrive as SPELL_MISSED/ABSORB and are re-injected
--     as damage at the absorbed value
--   * overkill is subtracted from damage done - but only inside
--     instances, and with the original's deliberate +1
--   * SPELL_ABSORBED credits the shield owner as a HEAL (the Classic
--     branch: no blacklist, no overheal bookkeeping)
--   * effective healing = amount - overhealing + absorbed-arg
--   * friendly fire adds to the source's FF total and the target's
--     damage taken, and NEVER to damage done
--   * pet damage adds to the pet actor AND the owner's total; the
--     owner's no-pet total is untouched
--   * a fight starts on the first qualifying damage event (with
--     Ignite's id blacklisted from starting one), not on REGEN
-- The GUID hot-caches are rebuilt every combat (UpdateParserGears);
-- lookups hit them first and the name index only on a miss.
-- The lines come from ZacUI's one combat-log reader (ns.CLEU), asked for
-- exactly the sub-events this file handles; the group from ns.Roster.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Meter = ns.Meter

local band = bit.band
local floor, max = math.floor, math.max
local UnitAffectingCombat = UnitAffectingCombat
local Roster = ns.Roster

local MELEE = _G.MELEE or "Melee"
local AUTOSHOT_NAME = "Auto Shot"

-- flags
local AFFILIATION_GROUP = 0x00000007
local REACTION_FRIENDLY = 0x00000010
local OBJECT_TYPE_ENEMY = 0x00000040
local OBJECT_TYPE_PLAYER = 0x00000400
local OBJECT_TYPE_PETGUARDIAN = 0x00003000
local OBJECT_NONE = 0x80000000
local RAIDTARGET_MASK = 0x000000FF

local SPEC_SPELLS = Meter.SPEC_SPELLS
local ENVIRONMENT_IDS = Meter.ENVIRONMENT_IDS
local ENVIRONMENT_NAMES = Meter.ENVIRONMENT_NAMES

-- spells that must never START a combat when the player casts them
-- (Details' classic list: Ignite's rolling ticks)
local cantStartCombat = { [12654] = true }

-- ============================================================
-- HOT STATE - rebound every combat by UpdateParserGears
-- ============================================================
local current            -- current combat object
local damageContainer, healContainer, miscContainer
local totals, groupTotals, miscTotals
local damageCache = setmetatable({}, { __mode = "v" })   -- serial -> actor
local damagePetCache = setmetatable({}, { __mode = "v" })
local damageOwnerCache = setmetatable({}, { __mode = "v" })
local healCache = setmetatable({}, { __mode = "v" })
local miscCache = setmetatable({}, { __mode = "v" })

function Meter.UpdateParserGears()
    current = Meter.current
    damageContainer = current.damage
    healContainer = current.heal
    miscContainer = current.misc
    totals = current.totals
    groupTotals = current.groupTotals
    miscTotals = current.miscTotals
    wipe(damageCache); wipe(damagePetCache); wipe(damageOwnerCache)
    wipe(healCache); wipe(miscCache)
end

-- ============================================================
-- ACTOR RESOLUTION
-- ============================================================
local function ReadGroupFlag(actor, flags, serial)
    if flags and band(flags, OBJECT_TYPE_PLAYER) ~= 0 then
        if band(flags, AFFILIATION_GROUP) ~= 0 or Roster.UnitOf(serial) then
            actor.grupo = true
        end
    end
    if flags and band(flags, OBJECT_TYPE_ENEMY) ~= 0 and band(flags, REACTION_FRIENDLY) == 0 then
        actor.enemy = true
    end
end

local function GuessClass(actor, serial, name)
    if actor.class then return end
    if serial and serial:find("^Player") then
        local _, engClass = GetPlayerInfoByGUID(serial)
        actor.class = engClass or "UNGROUPPLAYER"
    elseif actor.ownerName then
        actor.class = "PET"
    else
        actor.class = "UNKNOW"
    end
end

-- Resolve source into (actor, ownerActor) creating as needed. The pet
-- caches make repeat events one table hit.
local function GetDamageActor(serial, name, flags)
    local actor = damageCache[serial]
    if actor then return actor, damageOwnerCache[serial] end
    local petActor = damagePetCache[serial]
    if petActor then return petActor, damageOwnerCache[serial] end

    local ownerActor
    if flags and band(flags, OBJECT_TYPE_PETGUARDIAN) ~= 0 and serial ~= "" then
        local pet = Meter.ResolvePet(serial, name, flags)
        if pet then
            actor = damageContainer:GetOrCreate(pet.hashName)
            actor.class = "PET"
            actor.ownerName = pet.ownerName
            actor.serial = serial
            actor.flag = flags
            ownerActor = damageContainer:GetOrCreate(pet.ownerName)
            ReadGroupFlag(ownerActor, pet.ownerFlags, pet.ownerGuid)
            GuessClass(ownerActor, pet.ownerGuid, pet.ownerName)
            ownerActor.serial = ownerActor.serial or pet.ownerGuid
            if ownerActor.grupo then actor.grupo = true end
            if not ownerActor.pets then ownerActor.pets = {} end
            ownerActor.pets[actor.name] = true
            damagePetCache[serial] = actor
            damageOwnerCache[serial] = ownerActor
            return actor, ownerActor
        end
    end
    actor = damageContainer:GetOrCreate(name)
    if not actor.flag then
        actor.flag = flags
        actor.serial = serial
        ReadGroupFlag(actor, flags, serial)
        GuessClass(actor, serial, name)
        if name == Meter.playerName then actor.isSelf = true end
    end
    if serial and serial ~= "" then damageCache[serial] = actor end
    return actor, nil
end

local function GetHealActor(serial, name, flags)
    local actor = healCache[serial ~= "" and serial or name]
    if actor then return actor end
    actor = healContainer:GetOrCreate(name)
    if not actor.flag then
        actor.flag = flags
        actor.serial = serial
        ReadGroupFlag(actor, flags, serial)
        GuessClass(actor, serial, name)
        if name == Meter.playerName then actor.isSelf = true end
    end
    healCache[serial ~= "" and serial or name] = actor
    return actor
end

local function GetMiscActor(name, serial, flags)
    local actor = miscCache[name]
    if actor then return actor end
    actor = miscContainer:GetOrCreate(name)
    if not actor.flag then
        actor.flag = flags
        actor.serial = serial
        ReadGroupFlag(actor, flags, serial)
        GuessClass(actor, serial, name)
    end
    miscCache[name] = actor
    return actor
end

-- ============================================================
-- COMBAT START GATE
-- ============================================================
-- THE TAIL OF A FIGHT ARRIVES AFTER THE FIGHT.
-- PLAYER_REGEN_ENABLED lands before the last combat-log packets do: the
-- killing blow's overkill line, the pet's final swing, an arrow already
-- in flight. Solo, EndCombat runs synchronously on that event, so those
-- trailing lines are parsed with inCombat already false - and the branch
-- below happily opened a BRAND NEW combat for them.
--
-- That is what emptied the meter the instant a fight ended. Window
-- segment 0 is Meter.current by identity, StartCombat replaces
-- Meter.current with fresh empty containers, and the fight you just
-- finished stopped being anything the window could see. The phantom
-- segment then closed a second later and was discarded for being under
-- the minimum length, so it never even showed up in the segment list -
-- the damage simply vanished with nothing to point at.
local COMBAT_END_GRACE = 2      -- seconds; trailing log lines, not a new pull

local function MaybeStartCombat(token, spellId, sourceName, sourceFlags,
                                targetName, targetFlags)
    if Meter.inCombat then return true end
    -- Nothing reopens a segment while the player is out of combat and the
    -- last one only just closed. A real new pull flags the player first,
    -- so this costs a genuine re-engage nothing.
    if Meter.lastCombatEndTime
        and GetTime() - Meter.lastCombatEndTime < COMBAT_END_GRACE
        and not UnitAffectingCombat("player") then
        return false
    end
    if token ~= "SPELL_PERIODIC_DAMAGE" then
        local sourceGrouped = sourceFlags and band(sourceFlags, AFFILIATION_GROUP) ~= 0
        local targetGrouped = targetFlags and band(targetFlags, AFFILIATION_GROUP) ~= 0
        if (sourceGrouped and UnitAffectingCombat(sourceName))
            -- Solo: the log alone is not enough. The player has to
            -- actually be in combat - the old branch trusted the source
            -- flags by themselves, which is precisely how a post-fight
            -- straggler counted as a pull.
            or (targetGrouped and UnitAffectingCombat(targetName))
            or (not IsInGroup() and not IsInRaid() and sourceGrouped
                and UnitAffectingCombat("player")) then
            if cantStartCombat[spellId] and sourceName == Meter.playerName then
                return false
            end
            Meter.StartCombat()
            return true
        end
    else
        -- a dot from the player restarts combat only after a 10s gap
        if sourceName == Meter.playerName then
            if cantStartCombat[spellId] then return false end
            -- GetTime, not Meter.now(): now() returns _tempo, which only
            -- advances inside the combat ticker and StartCombat. Out of
            -- combat it is frozen, so "lastCombatEnd + 10 < now()" could
            -- never once be true and this whole debounce was dead code.
            if not Meter.lastCombatEndTime
                or GetTime() - Meter.lastCombatEndTime > 10 then
                Meter.StartCombat()
                return true
            end
        end
    end
    return false
end

-- ============================================================
-- DAMAGE
-- ============================================================
-- "[*] <name>": the source a sourceless or environmental hit is filed
-- under, built once per name instead of once per line
local starNames = setmetatable({}, { __index = function(t, k)
    local v = "[*] " .. k
    t[k] = v
    return v
end })

local function SpellDamage(token, evTime, sourceSerial, sourceName, sourceFlags,
                           targetSerial, targetName, targetFlags, targetRaidFlags,
                           spellId, spellName, spellSchool,
                           amount, overkill, school, resisted, blocked, absorbed,
                           critical, glancing, crushing)
    if not sourceName then
        -- damage with no source (some environmental ticks): fold under
        -- the spell's own name so it still lands somewhere visible
        sourceName = starNames[spellName or "?"]
        sourceFlags = 0xa48
        sourceSerial = ""
    end
    if not MaybeStartCombat(token, spellId, sourceName, sourceFlags,
                            targetName, targetFlags) then
        if not Meter.inCombat then return end
    end

    local healthChange = amount or 0
    if absorbed then amount = absorbed + (amount or 0) end
    if Meter.inInstance and overkill and overkill > 0 then
        overkill = overkill + 1
        amount = amount - overkill
    end

    local sourceActor, ownerActor = GetDamageActor(sourceSerial, sourceName, sourceFlags)
    local targetActor = GetDamageActor(targetSerial, targetName, targetFlags)
    local now = Meter.now()

    -- activity clock
    if not sourceActor.started then
        sourceActor:OpenClock()
        Meter.activeDamage[sourceActor] = true
        if ownerActor and not ownerActor.started then
            ownerActor:OpenClock()
            Meter.activeDamage[ownerActor] = true
        end
    end
    sourceActor.lastEvent = now
    if ownerActor then ownerActor.lastEvent = now end

    -- spec sniffing off signature damage spells
    local spec = SPEC_SPELLS[spellId]
    if spec and sourceActor.grupo then sourceActor.spec = spec end

    -- death log for group players taking hits
    if targetActor.grupo and band(targetFlags, OBJECT_TYPE_PLAYER) ~= 0 then
        if targetSerial and targetSerial ~= "" then
            local hc = Meter.HealthCache
            hc[targetSerial] = (hc[targetSerial] or (Meter.HealthMaxCache[targetSerial] or 0)) - healthChange
            if hc[targetSerial] < 0 then hc[targetSerial] = 0 end
        end
        Meter.DeathLogEvent(targetName, true, spellId, amount, evTime,
            sourceName, overkill, critical, spellSchool, targetSerial)
    end

    -- friendly fire?
    local isFF
    if Meter.inInstance then
        isFF = (sourceActor.grupo or (ownerActor and ownerActor.grupo))
            and targetActor.grupo
    else
        isFF = targetFlags and sourceFlags
            and band(targetFlags, REACTION_FRIENDLY) ~= 0
            and band(sourceFlags, REACTION_FRIENDLY) ~= 0
    end

    if isFF then
        sourceActor.friendlyFireTotal = sourceActor.friendlyFireTotal + amount
        if not sourceActor.friendlyFire then sourceActor.friendlyFire = {} end
        sourceActor.friendlyFire[targetName] = (sourceActor.friendlyFire[targetName] or 0) + amount
        targetActor.damageTaken = targetActor.damageTaken + amount - (absorbed or 0)
        current.needRefresh.damage = true
        return
    end

    -- totals
    totals.damage = totals.damage + amount
    if (sourceActor.grupo or (ownerActor and ownerActor.grupo)) then
        groupTotals.damage = groupTotals.damage + amount
    end
    targetActor.damageTaken = targetActor.damageTaken + amount

    -- accumulate
    if ownerActor then
        ownerActor.total = ownerActor.total + amount
        ownerActor.targets[targetName] = (ownerActor.targets[targetName] or 0) + amount
    end
    sourceActor.total = sourceActor.total + amount
    sourceActor.totalNoPet = sourceActor.totalNoPet + amount
    sourceActor.targets[targetName] = (sourceActor.targets[targetName] or 0) + amount

    local sp = sourceActor.spells[spellId]
    if not sp then
        sp = Meter.NewSpellTable(spellId)
        sp.name = spellName
        sp.school = spellSchool
        sourceActor.spells[spellId] = sp
    end
    sp.total = sp.total + amount
    sp.counter = sp.counter + 1
    sp.targets[targetName] = (sp.targets[targetName] or 0) + amount
    if resisted and resisted > 0 then sp.r_amt = sp.r_amt + 1; sp.r_dmg = sp.r_dmg + amount end
    if blocked and blocked > 0 then sp.b_amt = sp.b_amt + 1; sp.b_dmg = sp.b_dmg + amount end
    if absorbed and absorbed > 0 then sp.a_amt = sp.a_amt + 1; sp.a_dmg = sp.a_dmg + amount end
    if glancing then
        sp.g_amt = sp.g_amt + 1; sp.g_dmg = sp.g_dmg + amount
    elseif critical then
        sp.c_amt = sp.c_amt + 1; sp.c_total = sp.c_total + amount
        if amount > sp.c_max then sp.c_max = amount end
        if sp.c_min == 0 or amount < sp.c_min then sp.c_min = amount end
    else
        sp.n_amt = sp.n_amt + 1; sp.n_total = sp.n_total + amount
        if amount > sp.n_max then sp.n_max = amount end
        if sp.n_min == 0 or amount < sp.n_min then sp.n_min = amount end
    end
    current.needRefresh.damage = true
end

local function SwingDamage(token, evTime, ss, sn, sf, ts, tn, tf, trf,
                           amount, overkill, school, resisted, blocked,
                           absorbed, critical, glancing, crushing)
    return SpellDamage(token, evTime, ss, sn, sf, ts, tn, tf, trf,
        1, MELEE, 0x1, amount, overkill, school, resisted, blocked,
        absorbed, critical, glancing, crushing)
end

local function EnvironmentDamage(token, evTime, ss, sn, sf, ts, tn, tf, trf,
                                 envType, amount)
    local id = ENVIRONMENT_IDS[envType] or 1
    local name = ENVIRONMENT_NAMES[id] or tostring(envType)
    return SpellDamage(token, evTime, "", starNames[name], 0xa48,
        ts, tn, tf, trf, id, name, 0x1, amount, -1, 1)
end

-- misses: a fully absorbed hit is damage at the absorbed value
local function SpellMissed(token, evTime, ss, sn, sf, ts, tn, tf, trf,
                           spellId, spellName, spellSchool, missType,
                           isOffHand, amountMissed)
    if missType == "ABSORB" and amountMissed and amountMissed > 0 then
        return SpellDamage(token, evTime, ss, sn, sf, ts, tn, tf, trf,
            spellId, spellName, spellSchool, amountMissed, -1, 1)
    end
    if not Meter.inCombat then return end
    local actor = GetDamageActor(ss, sn or "?", sf)
    local sp = actor.spells[spellId]
    if sp then
        sp.counter = sp.counter + 1
        sp[missType] = (sp[missType] or 0) + 1
    end
end

local function SwingMissed(token, evTime, ss, sn, sf, ts, tn, tf, trf,
                           missType, isOffHand, amountMissed)
    return SpellMissed(token, evTime, ss, sn, sf, ts, tn, tf, trf,
        1, MELEE, 0x1, missType, isOffHand, amountMissed)
end

local function RangeMissed(token, evTime, ss, sn, sf, ts, tn, tf, trf,
                           spellId, spellName, spellSchool, missType,
                           isOffHand, amountMissed)
    return SpellMissed(token, evTime, ss, sn, sf, ts, tn, tf, trf,
        spellId or 2, spellName or AUTOSHOT_NAME, spellSchool or 0x1,
        missType, isOffHand, amountMissed)
end

-- ============================================================
-- HEALING
-- ============================================================
local function Heal(token, evTime, sourceSerial, sourceName, sourceFlags,
                    targetSerial, targetName, targetFlags, targetRaidFlags,
                    spellId, spellName, spellSchool,
                    amount, overHealing, absorbed, critical, bIsShield)
    if not Meter.inCombat or not sourceName then return end
    overHealing = overHealing or 0
    absorbed = absorbed or 0

    local effective
    if bIsShield then effective = amount
    else effective = absorbed + amount - overHealing end

    local sourceActor = GetHealActor(sourceSerial, sourceName, sourceFlags)
    local targetActor = GetHealActor(targetSerial, targetName, targetFlags)
    local now = Meter.now()

    -- enemy healing gets tracked lightly and leaves
    if sourceActor.enemy and not sourceActor.grupo then
        sourceActor.healEnemyAmt = (sourceActor.healEnemyAmt or 0) + effective
        return
    end

    if not sourceActor.started then
        sourceActor:OpenClock()
        Meter.activeHeal[sourceActor] = true
    end
    sourceActor.lastEvent = now

    local spec = SPEC_SPELLS[spellId]
    if spec and sourceActor.grupo then sourceActor.spec = spec end

    -- death log HP recovery for group targets
    if targetFlags and band(targetFlags, OBJECT_TYPE_PLAYER) ~= 0 then
        if targetSerial and targetSerial ~= "" then
            local hc, hm = Meter.HealthCache, Meter.HealthMaxCache
            local recover = max(amount - overHealing, 0)
            hc[targetSerial] = (hc[targetSerial] or 0) + recover
            if hm[targetSerial] and hc[targetSerial] > hm[targetSerial] then
                hc[targetSerial] = hm[targetSerial]
            end
        end
        Meter.DeathLogEvent(targetName, false, spellId, effective, evTime,
            sourceName, -1, critical, spellSchool, targetSerial)
    end

    totals.heal = totals.heal + effective
    if sourceActor.grupo then groupTotals.heal = groupTotals.heal + effective end
    sourceActor.total = sourceActor.total + effective
    sourceActor.totalOver = sourceActor.totalOver + overHealing
    if bIsShield then sourceActor.totalAbsorb = sourceActor.totalAbsorb + effective end
    targetActor.healingTaken = targetActor.healingTaken + effective
    sourceActor.targets[targetName] = (sourceActor.targets[targetName] or 0) + effective
    if overHealing > 0 then
        sourceActor.targetsOverheal[targetName] = (sourceActor.targetsOverheal[targetName] or 0) + overHealing
    end

    local sp = sourceActor.spells[spellId]
    if not sp then
        sp = Meter.NewHealSpellTable(spellId)
        sp.name = spellName
        sp.school = spellSchool
        sp.isShield = bIsShield or nil
        sourceActor.spells[spellId] = sp
    end
    sp.total = sp.total + effective
    sp.counter = sp.counter + 1
    sp.overheal = sp.overheal + overHealing
    if bIsShield then sp.absorbed = sp.absorbed + effective end
    sp.targets[targetName] = (sp.targets[targetName] or 0) + effective
    if overHealing > 0 then
        sp.targets_overheal[targetName] = (sp.targets_overheal[targetName] or 0) + overHealing
    end
    if critical then
        sp.c_amt = sp.c_amt + 1; sp.c_total = sp.c_total + effective
        if effective > sp.c_max then sp.c_max = effective end
        if sp.c_min == 0 or effective < sp.c_min then sp.c_min = effective end
    else
        sp.n_amt = sp.n_amt + 1; sp.n_total = sp.n_total + effective
        if effective > sp.n_max then sp.n_max = effective end
        if sp.n_min == 0 or effective < sp.n_min then sp.n_min = effective end
    end
    current.needRefresh.heal = true
end

-- SPELL_ABSORBED, classic shape. Two arg layouts: the melee variant has
-- no absorbed-spell prefix and everything shifts four left.
local function HealAbsorb(token, evTime, sourceSerial, sourceName, sourceFlags,
                          targetSerial, targetName, targetFlags, targetRaidFlags,
                          a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
    local shieldOwnerSerial, shieldOwnerName, shieldOwnerFlags
    local shieldSpellId, shieldName, shieldType, amount
    if type(a8) == "number" and a8 ~= nil and type(a4) == "string" then
        -- spell variant: a1-a3 = attacking spell, a4-a7 = shield owner,
        -- a8-a10 = shield spell, a11 = amount
        shieldOwnerSerial, shieldOwnerName, shieldOwnerFlags = a4, a5, a6
        shieldSpellId, shieldName, shieldType, amount = a8, a9, a10, a11
    else
        -- melee variant: a1-a4 = shield owner, a5-a7 = shield spell, a8 = amount
        shieldOwnerSerial, shieldOwnerName, shieldOwnerFlags = a1, a2, a3
        shieldSpellId, shieldName, shieldType, amount = a5, a6, a7, a8
    end
    if not amount or not shieldOwnerName then return end
    return Heal(token, evTime, shieldOwnerSerial, shieldOwnerName, shieldOwnerFlags,
        targetSerial, targetName, targetFlags, targetRaidFlags,
        shieldSpellId, shieldName, shieldType, amount, 0, 0, nil, true)
end

-- ============================================================
-- MISC - interrupts, dispels, cc breaks, ress, deaths, summons
-- ============================================================
local function Summon(token, evTime, sourceSerial, sourceName, sourceFlags,
                      petGuid, petName, petFlags, petRaidFlags, spellId)
    if not petGuid or not sourceName then return end
    -- pet summoning a pet: promote to the grandparent
    local grand = Meter.petCache[sourceSerial]
    if grand then
        sourceName, sourceSerial, sourceFlags =
            grand.ownerName, grand.ownerGuid, grand.ownerFlags
    end
    Meter.RegisterPet(petGuid, petName, sourceName, sourceSerial, sourceFlags)
end

local function Interrupt(token, evTime, ss, sourceName, sf, ts, targetName, tf, trf,
                         spellId, spellName, _, extraId, extraName)
    if not Meter.inCombat or not sourceName then return end
    local actor = GetMiscActor(sourceName, ss, sf)
    actor.interrupt = (actor.interrupt or 0) + 1
    if not actor.interruptTargets then
        actor.interruptTargets = {}
        actor.interruptSpells = {}
        actor.interruptedWhat = {}
    end
    actor.interruptTargets[targetName or "?"] = (actor.interruptTargets[targetName or "?"] or 0) + 1
    actor.interruptSpells[spellId] = (actor.interruptSpells[spellId] or 0) + 1
    if extraId then
        actor.interruptedWhat[extraId] = (actor.interruptedWhat[extraId] or 0) + 1
    end
    actor.lastEvent = Meter.now()
    miscTotals.interrupt = miscTotals.interrupt + 1
    current.needRefresh.misc = true
end

local function Dispel(token, evTime, ss, sourceName, sf, ts, targetName, tf, trf,
                      spellId, spellName, _, extraId, extraName)
    if not Meter.inCombat or not sourceName then return end
    local actor = GetMiscActor(sourceName, ss, sf)
    actor.dispell = (actor.dispell or 0) + 1
    if not actor.dispellTargets then
        actor.dispellTargets = {}
        actor.dispellSpells = {}
        actor.dispelledWhat = {}
    end
    actor.dispellTargets[targetName or "?"] = (actor.dispellTargets[targetName or "?"] or 0) + 1
    actor.dispellSpells[spellId] = (actor.dispellSpells[spellId] or 0) + 1
    if extraId then
        actor.dispelledWhat[extraId] = (actor.dispelledWhat[extraId] or 0) + 1
    end
    actor.lastEvent = Meter.now()
    miscTotals.dispell = miscTotals.dispell + 1
    current.needRefresh.misc = true
end

local function CCBreak(token, evTime, ss, sourceName, sf, ts, targetName, tf, trf,
                       spellId)
    if not Meter.inCombat or not sourceName then return end
    local actor = GetMiscActor(sourceName, ss, sf)
    actor.cc_break = (actor.cc_break or 0) + 1
    actor.lastEvent = Meter.now()
    miscTotals.cc_break = miscTotals.cc_break + 1
    current.needRefresh.misc = true
end

local function Ress(token, evTime, ss, sourceName, sf, ts, targetName, tf, trf,
                    spellId)
    if not Meter.inCombat or not sourceName then return end
    local actor = GetMiscActor(sourceName, ss, sf)
    actor.ress = (actor.ress or 0) + 1
    miscTotals.ress = miscTotals.ress + 1
    current.needRefresh.misc = true
end

local function Dead(token, evTime, ss, sourceName, sf,
                    targetSerial, targetName, targetFlags)
    Meter.RemovePet(targetSerial)
    if not targetName or not targetFlags then return end
    if not Meter.inCombat then return end
    if band(targetFlags, OBJECT_TYPE_PLAYER) == 0 then return end
    if band(targetFlags, AFFILIATION_GROUP) == 0
        and not Roster.UnitByName(targetName) then return end
    if UnitIsFeignDeath(targetName) then return end
    local damageActor = current.damage:Get(targetName)
    local class = damageActor and damageActor.class
    if not class then
        local healActor = current.heal:Get(targetName)
        class = healActor and healActor.class or "UNKNOW"
    end
    local actor = GetMiscActor(targetName, targetSerial, targetFlags)
    actor.dead = (actor.dead or 0) + 1
    actor.class = actor.class or class
    miscTotals.dead = miscTotals.dead + 1
    Meter.BuildDeathTable(targetName, class, evTime, targetSerial)
    current.needRefresh.misc = true
end

-- spec sniffing off casts: the cheapest possible handler
local function CastSuccess(token, evTime, sourceSerial, sourceName, sourceFlags,
                           ts, tn, tf, trf, spellId)
    local spec = SPEC_SPELLS[spellId]
    if not spec or not sourceName then return end
    if not Meter.inCombat then return end
    local actor = damageCache[sourceSerial] or damageContainer:Get(sourceName)
    if actor and actor.grupo then actor.spec = spec end
    local hactor = healContainer:Get(sourceName)
    if hactor and hactor.grupo then hactor.spec = spec end
end

-- ============================================================
-- DISPATCH
-- ============================================================
local tokens = {
    SPELL_DAMAGE = SpellDamage,
    SPELL_PERIODIC_DAMAGE = SpellDamage,
    SPELL_BUILDING_DAMAGE = SpellDamage,
    RANGE_DAMAGE = SpellDamage,
    DAMAGE_SHIELD = SpellDamage,
    DAMAGE_SPLIT = SpellDamage,
    SWING_DAMAGE = SwingDamage,
    ENVIRONMENTAL_DAMAGE = EnvironmentDamage,
    SPELL_MISSED = SpellMissed,
    SPELL_PERIODIC_MISSED = SpellMissed,
    SPELL_BUILDING_MISSED = SpellMissed,
    DAMAGE_SHIELD_MISSED = SpellMissed,
    SWING_MISSED = SwingMissed,
    RANGE_MISSED = RangeMissed,
    SPELL_HEAL = Heal,
    SPELL_PERIODIC_HEAL = Heal,
    SPELL_ABSORBED = HealAbsorb,
    SPELL_SUMMON = Summon,
    SPELL_INTERRUPT = Interrupt,
    SPELL_DISPEL = Dispel,
    SPELL_STOLEN = Dispel,
    SPELL_AURA_BROKEN = CCBreak,
    SPELL_AURA_BROKEN_SPELL = CCBreak,
    SPELL_RESURRECT = Ress,
    SPELL_CAST_SUCCESS = CastSuccess,
    UNIT_DIED = Dead,
    UNIT_DESTROYED = Dead,
}

-- the sub-events asked for: exactly the handled ones
local TOKEN_LIST = {}
for token in pairs(tokens) do TOKEN_LIST[#TOKEN_LIST + 1] = token end

local function OnCLEU(evTime, token, _, sourceSerial, sourceName, sourceFlags, _,
                      targetSerial, targetName, targetFlags, targetRaidFlags,
                      a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
    local fn = tokens[token]
    if fn then
        return fn(token, evTime, sourceSerial, sourceName, sourceFlags,
            targetSerial, targetName, targetFlags, targetRaidFlags,
            a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12)
    end
end

function Meter.EnableParser()
    ns.CLEU.On("Meter.parser", TOKEN_LIST, OnCLEU)
    Meter.UpdateParserGears()
end
