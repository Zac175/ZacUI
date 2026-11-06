-- BWL - ZacUI's own Blackwing Lair boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Settings in Own\BWL_Data.lua.
--
-- Built like the Molten Core module: one controller per boss ability
-- puts its countdown on the bus (WA_NUMEN_TIMER key, seconds, count) and
-- the bars, pop-ups, raid-frame glows and speech listen for it. BWL adds
-- a few shapes of its own, kept in the local section below: the drakes'
-- "who is the breath aimed at" lookup, pop-ups that carry a count or a
-- name, heads-up bars told their length by the event, and speech at the
-- volume the pack's speech setting picks.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
if not (RM and RM.Own and RM.Own.on) then return end
local K = RM.Own.Kit

local B = {}

-- the chat prefix the raid's reminders print with
local SAY = "|cff0070ddRaid Mods|r |cffff8000BWL|r: "
local CLOAK = 15138          -- Onyxia Scale Cloak
local CLOAK_ICON = 133757
local BWL_MAP = 469
-- the encounter ending (ours and the engine's own) takes a controller's
-- piece down
local ENDS = { "WA_FJI_ENCOUNTER_END", "ENCOUNTER_END" }

-- ============================================================
-- LOCAL HELPERS (BWL shapes the shared kit does not have)
-- ============================================================

-- Speech at the pack's speech volume (FJIDS_SFX_VOLUME, read each time),
-- the usual 1.2 rate.
local function Say(text)
    RM.Speak(text, _G.FJIDS_SFX_VOLUME or 75, 1.2)
end
-- the same as an action or condition: who = fn() limits it
local function Speech(text, who)
    return function()
        if who and not who() then return end
        Say(text)
    end
end

local function Me() return UnitClass("player") end
local function Leader() return UnitIsGroupLeader("player") end
-- a check: the player's class (by its English name) is one of these, or
-- they lead the raid
local function ClassOrLead(...)
    local set = K.Set({ ... })
    return function() return set[Me()] or Leader() end
end
-- logic: the first trigger, shown to tanks, healers and the leader only
local function TanksHealersLead(env, t)
    if not (_G.FJI_TANK or _G.FJI_HEALER or Leader()) then return false end
    return t[1]
end
-- logic: trigger n, as it is
local function Pick(n) return function(env, t) return t[n] end end

-- An amount per stack (Flame Buffet, Growing Flames).
local function PerStack(n)
    return function(env, _, _, _, _, _, _, stacks) return (tonumber(stacks) or 0) * n end
end

-- The unit (target, focus or a nameplate) currently showing guid.
local LOOK = { "target", "focus" }
for i = 1, 40 do LOOK[#LOOK + 1] = "nameplate" .. i end
local function UnitOf(guid)
    for _, unit in ipairs(LOOK) do
        if UnitExists(unit) and UnitGUID(unit) == guid then return unit end
    end
end

-- A raid member's unit by GUID.
local function Member(guid)
    for unit in RM.IterateGroup() do
        if UnitGUID(unit) == guid then return unit end
    end
end

-- An onCast for K.Controller: a moment after a cast starts, see who the
-- caster is looking at and put that on the bus (event unit, guid[, caster]).
local function Aim(event, withCaster)
    return function(env, _, casterGUID)
        C_Timer.After(0.05, function()
            local caster = UnitOf(casterGUID)
            local victim = caster and caster .. "target"
            if not (victim and UnitExists(victim)) then return end
            env.targetUnit, env.targetGUID = victim, UnitGUID(victim)
            if withCaster then
                RM.Fire(event, victim, env.targetGUID, casterGUID)
            else
                RM.Fire(event, victim, env.targetGUID)
            end
        end)
    end
end

-- K.Controller with BWL's extras:
--   aim   the bus event that names who the cast is aimed at
--   from  only this creature's casts count (all three drakes and
--         Nefarian share Shadow Flame's spell id)
local function Ability(s)
    if s.aim then s.onCast = Aim(s.aim) end
    local map = K.Controller(s)
    if s.from then
        local inner = map["triggers.1.trigger"]
        local sub = s.sub or "SPELL_CAST_SUCCESS"
        map["triggers.1.trigger"] = function(env, allstates, event, ts, subEvent, hide, srcGUID, srcName, srcFlags, srcRaid, dstGUID, dstName, dstFlags, dstRaid, spellId, ...)
            if spellId == s.spell and subEvent == sub and K.NpcId(srcGUID) ~= s.from then return false end
            return inner(env, allstates, event, ts, subEvent, hide, srcGUID, srcName, srcFlags, srcRaid, dstGUID, dstName, dstFlags, dstRaid, spellId, ...)
        end
    end
    return map
end

-- A spell landing on someone, passed on as a bus event with their GUID.
local function Relay(spell, event)
    return function(env, allstates, _, _, subEvent, _, _, _, _, _, destGUID, _, _, _, spellId)
        if spellId ~= spell then return false end
        if subEvent == "SPELL_AURA_APPLIED" then RM.Fire(event, destGUID) end
    end
end

-- The finish of a relay with no countdown of its own: only the count
-- goes back.
local function Rewind(env) env.count = 1 end

-- A pop-up: a short timed state when a countdown reaches 0 (key) or a bus
-- event arrives (event).
--   dur, icon
--   fill(st, ...)  extra fields from the event's values (a count, a name)
--   sample()       the options preview's fields; samplePut makes it a
--                  change, sampleTrue answers true for it
--   aimed          the event naming who it is aimed at: sets state.guid
local function Pop(s)
    return function(env, allstates, event, ...)
        if event == "OPTIONS" and s.sample then
            local f = s.sample()
            if s.samplePut then
                K.Put(allstates, "", f)
            else
                f.show = true
                allstates[""] = f
            end
            if s.sampleTrue then return true end
        end
        if s.aimed and event == s.aimed then
            local st = allstates[""]
            if st then
                st.guid = select(2, ...)
                st.changed = true
                return true
            end
            return
        end
        local fire
        if s.key then
            local key, secs = ...
            fire = event == "WA_NUMEN_TIMER" and key == s.key and secs == 0
        else
            fire = event == s.event
        end
        if not fire then return end
        local st = K.Put(allstates, "", K.Timed(s.dur, { icon = s.icon, autoHide = true }))
        if s.fill then s.fill(st, ...) end
        return true
    end
end
-- fills for Pop: from WA_NUMEN_TIMER key, 0, count, guid
local function WithCount(st, _, _, count) st.count = count end
local function WithCountAndName(st, _, _, count, guid) st.count = count st.name = guid end
-- previews
local function RandomCount(icon) return function() return { icon = icon, count = math.random(1, 3) } end end
local function MyName(icon) return function() return { icon = icon, name = RM.WA.myGUID } end end
local function MyNameCount(icon) return function() return { icon = icon, name = RM.WA.myGUID, count = math.random(1, 3) } end end

-- Fields for a timed state lasting duration seconds from now (the
-- heads-up bars are told their length by the event).
local function Lasting(duration, fields)
    fields.progressType, fields.duration, fields.expirationTime = "timed", duration, GetTime() + duration
    return fields
end

-- A heads-up bar told its length and count by the event (PREWARN secs,
-- count); goes when the countdown for key goes off or stops, or on cancel.
local function Heads(s)
    return function(env, allstates, event, ...)
        if event == "OPTIONS" then
            K.Put(allstates, "", { progressType = "timed", icon = s.icon, count = math.random(1, 3) })
            return true
        end
        if event == s.on then
            local secs, count = ...
            K.Put(allstates, "", Lasting(secs, { icon = s.icon, count = count, autoHide = s.autoHide }))
            return true
        end
        if event == "WA_NUMEN_TIMER" then
            local key, secs = ...
            if key == s.key and (secs == 0 or secs == nil) then return K.Drop(allstates, "") end
        elseif s.cancel and event == s.cancel then
            return K.Drop(allstates, "")
        end
    end
end

-- A raid-frame bar on whoever an aimed breath is pointed at (2 seconds).
local function AimedGlow(event, sampleKey, sampleDur)
    return function(env, allstates, ev, unit)
        if ev == "OPTIONS" then
            K.Put(allstates, sampleKey or "", K.Timed(sampleDur or 2, { remaining = math.random(1, 8), unit = "player" }))
            return true
        end
        if ev == event then
            K.Put(allstates, unit, K.Timed(2, { autoHide = true, unit = unit }))
            return true
        end
    end
end

-- The game's "pick this gossip line for me" shortcuts.
local function AutoGossip(option, ids)
    local want = K.Set(ids)
    return function(env, allstates, event)
        if event ~= "GOSSIP_SHOW" or not env.config.option[option] then return end
        for _, line in ipairs(C_GossipInfo.GetOptions()) do
            if want[line.gossipOptionID] then
                C_GossipInfo.SelectOption(line.gossipOptionID)
                return
            end
        end
    end
end

local function CloakOn() return IsEquippedItem(CLOAK) end

-- the eleven classes' names, colours and Class Call icons
local CLASSES = {
    { "Druid", "FF7C0A", 625999 }, { "Hunter", "AAD372", 626000 }, { "Mage", "3FC7EB", 626001 },
    { "Paladin", "F48CBA", 626003 }, { "Priest", "FFFFFF", 626004 }, { "Rogue", "FFF468", 626005 },
    { "Shaman", "0070DD", 626006 }, { "Warlock", "8788EE", 626007 }, { "Warrior", "C69B6D", 626008 },
}
local CLASS_ICON = {}
for _, c in ipairs(CLASSES) do CLASS_ICON[c[1]] = c[3] end
-- "Priest" -> "|cFFFFFFFFPriest|r" and its icon
local function ClassLook(class)
    for _, c in ipairs(CLASSES) do
        if c[1] == class then return string.format("|cFF%s%s|r", c[2], class), c[3] end
    end
end

-- Chromaggus' elemental vulnerabilities: buff id, school, icon
local VULNS = {
    { 22277, "Fire", 135812 }, { 22278, "Frost", 135846 }, { 22279, "Shadow", 136197 },
    { 22280, "Nature", 136006 }, { 22281, "Arcane", 136096 },
}
local NO_VULN_ICON = 135899   -- Detect Magic
-- the first vulnerability in the list showing in unit's first two buffs
local function VulnOn(unit)
    for _, v in ipairs(VULNS) do
        for slot = 1, 2 do
            if select(10, UnitBuff(unit, slot)) == v[1] then return v end
        end
    end
end
-- the add icons' preview: a random school
local function VulnSample(allstates)
    local v = VULNS[math.random(#VULNS)]
    K.Put(allstates, "", { name = "+" .. v[2], icon = v[3] })
    return true
end
-- the classes the vulnerability icons are shown to (every class)
local ALL_CLASSES = K.Set({ "Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior" })
local function ForClassesOrLeads(classes, needBoth)
    return function(env, t)
        if needBoth then
            if not (t[1] and t[2]) then return false end
        elseif not t[1] then
            return false
        end
        return classes[Me()] or Leader() or UnitIsGroupAssistant("player")
    end
end

-- ============================================================
-- RAID LEADER: MARKING
-- ============================================================
-- whoever has the spinning debuff / Burning Adrenaline (an aura trigger
-- finds them) gets the next free mark, and their own back afterwards
local MarkWhoHasIt = { ["init"] = K.MarkPool(), ["actions.start.custom"] = K.MarkOnShow(), ["actions.finish.custom"] = K.MarkClear() }
B["[RAIDLEAD][BWL][Trash] AutoMark Spin"] = MarkWhoHasIt
B["[RAIDLEAD][BWL][Vael] AutoMark Burning Adrenaline"] = MarkWhoHasIt

-- The drakes' Shadow Flame target: marked for three seconds, then the mark
-- comes off again (when the piece hides, or on its own
-- WA_<BOSS>_REMOVE_MARK event a moment later, whichever is first).
local function MarkAimed(boss)
    local aimed, unmark = "WA_" .. boss .. "_SHADOWFLAME_TARGET", "WA_" .. boss .. "_REMOVE_MARK"
    return {
        ["init"] = K.MarkPool(),
        ["actions.start.custom"] = function(env)
            if not (env.config.group.option.enable and env.state and env.unitMarkedGUID) then return end
            local unit = Member(env.unitMarkedGUID)
            if not unit then return end
            for mark, free in pairs(env.marks) do
                if free then
                    SetRaidTarget(unit, mark)
                    env.marks[mark] = false
                    return
                end
            end
        end,
        ["actions.finish.custom"] = function(env)
            local unit = env.unitMarkedGUID and Member(env.unitMarkedGUID)
            if not unit then return end
            local mark = GetRaidTargetIndex(unit)
            if mark then
                SetRaidTarget(unit, 0)
                env.marks[mark] = true
            end
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, _, guid)
            if event == aimed then
                env.unitMarkedGUID = guid
                C_Timer.After(3.1, function() RM.Fire(unmark) end)
                K.Put(allstates, "", K.Timed(3, { autoHide = true }))
                return true
            elseif event == unmark then
                local unit = env.unitMarkedGUID and Member(env.unitMarkedGUID)
                local mark = unit and GetRaidTargetIndex(unit)
                if mark then
                    SetRaidTarget(unit, 0)
                    env.marks[mark] = true
                end
                env.unitMarkedGUID = nil
            end
        end,
    }
end
B["[RAIDLEAD][BWL][Firemaw] AutoMark Shadow Flame Target"] = MarkAimed("FIREMAW")
B["[RAIDLEAD][BWL][Ebonroc] AutoMark Shadow Flame Target"] = MarkAimed("EBONROC")
B["[RAIDLEAD][BWL][Flamegor] AutoMark Shadow Flame Target"] = MarkAimed("FLAMEGOR")

-- ============================================================
-- TIMER BARS
-- ============================================================
-- no BWL boss has a berserk timer here
B["BT:[BWL][All] Berserk Timer"] = K.Berserk{ keys = {} }

-- The emphasized list: the last ten seconds of a bar
B["BTE:[BWL][All] Emphasized Timers"] = K.Emphasized{ sampleKey = "LaserAttack_" }

-- colours are 0-255 RGB plus alpha; all the same pink
do
    local PINK = { 255, 182, 193, 1 }
    local function Bar(name, icon) return { name = name, icon = icon, color = PINK } end
    local bars = {
        RAZORGORE_CONFLAGRATION = Bar("Conflagration", 135818),
        RAZORGORE_WAR_STOMP = Bar("War Stomp", 132091),
        VAEL_ADRENALINE = Bar("Burning Adrenaline", 132937),
        VAEL_FLAME_BREATH = Bar("Flame Breath", 135805),
        BROODLORD_BLAST_WAVE = Bar("Blast Wave", 135903),
        FIREMAW_SHADOW_FLAME = Bar("Shadow Flame", 135818),
        FIREMAW_WING_BUFFET = Bar("Wing Buffet", 134316),
        EBONROC_WING_BUFFET = Bar("Wing Buffet", 134316),
        EBONROC_SHADOW_FLAME = Bar("Shadow Flame", 135818),
        FLAMEGOR_FRENZY = Bar("Frenzy", 132117),
        FLAMEGOR_WING_BUFFET = Bar("Wing Buffet", 134316),
        FLAMEGOR_SHADOW_FLAME = Bar("Shadow Flame", 135818),
        CHROMAGGUS_BREATH_FIRST = Bar("First Breath", 134154),
        CHROMAGGUS_BREATH_SECOND = Bar("Second Breath", 134154),
        NEFARIAN_CLASS_CALL = Bar("Class Call", 136129),
        NEFARIAN_FEAR = Bar("Fear", 136129),
    }
    -- each of Chromaggus' two breath slots, once its breath is known
    local BREATH_BARS = { INCINERATE = { "Incinerate", 136130 }, CORROSIVE = { "Corrosive Acid", 136007 },
        FROST_BURN = { "Frost Burn", 135836 }, IGNITE_FLESH = { "Ignite Flesh", 135805 }, TIME_LAPSE = { "Time Lapse", 135744 } }
    for _, slot in ipairs({ "FIRST", "SECOND" }) do
        for breath, look in pairs(BREATH_BARS) do
            bars["CHROMAGGUS_BREATH_" .. slot .. "_" .. breath] = Bar(look[1], look[2])
        end
    end
    B["BT:[BWL][All] Boss Timers"] = K.TimerBars{
        bars = bars,
        sample = 3,
        hideAtZero = true,
        -- each bar has its own switch, except Chromaggus' (always on)
        allow = function(env, key) return key:find("CHROMAGGUS") or env.config.option.enabledGroup[key] end,
    }
end

-- a wipe: the boss is back in 30 seconds (Nefarian in 15 minutes); kept
-- in a global so a reload picks the bar up again
do
    local function Bar(allstates)
        K.Put(allstates, "", { progressType = "timed", duration = _G.eRespawnTimer - GetTime(), expirationTime = _G.eRespawnTimer, autoHide = true })
        return true
    end
    B["BT:[BWL][All] Boss Respawn"] = {
        ["triggers.1.trigger"] = function(env, allstates, event, encounterId, encounterName, _, _, success)
            if event == "ENCOUNTER_END" and success == 0 then
                _G.eRespawnTimer = GetTime() + (encounterId == 617 and 900 or 30)
                env.bossName = encounterName
                return Bar(allstates)
            elseif event == "STATUS" and _G.eRespawnTimer and _G.eRespawnTimer - GetTime() > 0 then
                return Bar(allstates)
            end
        end,
    }
end

-- ============================================================
-- ONYXIA SCALE CLOAK
-- ============================================================
-- zoning in without the cloak anywhere: say so once (until Nefarian dies)
do
    local function InBags()
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                if C_Container.GetContainerItemID(bag, slot) == CLOAK then return true end
            end
        end
        return false
    end
    B["CH:[BWL] Cloak Check on Zone"] = {
        ["init"] = function() _G.FJI_CLOAK_NOTIFIED = _G.FJI_CLOAK_NOTIFIED or false end,
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "ZONE_CHANGED_NEW_AREA" then
                local map = select(8, GetInstanceInfo())
                if map == BWL_MAP and not CloakOn() and not InBags() and not _G.FJI_CLOAK_NOTIFIED then
                    print("|cFFFF0000WARNING!|r")
                    print("|cFF40C7EBOnyxia Scale Cloak|r Missing. ")
                    K.Put(allstates, "", K.Timed(10, { autoHide = true }))
                    _G.FJI_CLOAK_NOTIFIED = true
                    return true
                end
            end
            if event == "ENCOUNTER_END" then
                local encounterId, _, _, _, success = ...
                if encounterId == 617 and success == 1 then _G.FJI_CLOAK_NOTIFIED = false end
            end
        end,
    }
end

local REMIND = SAY .. "Cloak Reminder! Note: Can be disabled in the Custom Options."
local function CloakIcon(allstates)
    K.Put(allstates, "", { icon = CLOAK_ICON })
    return true
end

-- in Nefarian's Lair (and after Chromaggus dies) without the cloak on
B["CH:[BWL][Nefarian] Onyxia Scale Cloak"] = {
    ["init"] = function() end,
    ["triggers.1.trigger"] = function(env, allstates, event, encounterId, _, _, _, success)
        if not env.config.option.enableCloak then return false end
        if event == "ENCOUNTER_END" and success == 1 and encounterId == 616 and not CloakOn() then
            return CloakIcon(allstates)
        end
        if event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" or event == "STATUS" then
            if GetSubZoneText() == "Nefarian's Lair" or GetZoneText() == "Nefarian's Lair" then
                if not CloakOn() then
                    print(REMIND)
                    return CloakIcon(allstates)
                end
            elseif K.Drop(allstates, "") then
                return true
            end
        end
        if event == "PLAYER_EQUIPMENT_CHANGED" and CloakOn() and K.Drop(allstates, "") then return true end
    end,
}

-- targeting one of the three drakes without the cloak on; one piece for
-- the tanks, one for everyone else
do
    local DRAKES = K.Set({ "11983", "14601", "11981" })
    local function OnADrake()
        return UnitExists("target") and DRAKES[K.NpcId(UnitGUID("target"))]
    end
    local function DrakeCloak(forTanks)
        return {
            ["init"] = function() end,
            ["triggers.1.trigger"] = function(env, allstates, event)
                if (_G.FJI_TANK and true or false) ~= forTanks then return false end
                if not env.config.option.enableCloak then return false end
                if event == "PLAYER_TARGET_CHANGED" or event == "STATUS" then
                    if OnADrake() then
                        if not CloakOn() then
                            print(REMIND)
                            return CloakIcon(allstates)
                        end
                    elseif K.Drop(allstates, "") then
                        return true
                    end
                end
                if event == "PLAYER_EQUIPMENT_CHANGED" and OnADrake() and CloakOn() and K.Drop(allstates, "") then return true end
            end,
        }
    end
    B["CH:[BWL][TANKS][Drakes] Onyxia Scale Cloak"] = DrakeCloak(true)
    B["CH:[BWL][Drakes] Onyxia Scale Cloak"] = DrakeCloak(false)
end

-- Nefarian lands without your cloak: hide behind the throne
do
    local function Hide(allstates)
        K.Put(allstates, "", K.Timed(15, { icon = 135818, autoHide = true }))
        return true
    end
    B["CH:[BWL][Nefarian] Hide Behind Throne!"] = {
        ["init"] = function() end,
        ["logic"] = Pick(1),
        ["actions.start.custom"] = Speech("Hide"),
        ["triggers.1.trigger"] = function(env, allstates, event)
            if event == "OPTIONS" then return Hide(allstates) end
            if event == "WA_NEFARIAN_P2_START" and not CloakOn() then return Hide(allstates) end
        end,
        ["triggers.2.icon"] = K.Always(CLOAK_ICON),
        ["triggers.2.trigger"] = K.Always(true),
    }
end

-- ============================================================
-- CIRCLES
-- ============================================================
B["C:[BWL][Nefarian] Bellowing Roar PreWarn"] = {
    ["triggers.1.icon"] = K.Always(135789),
    ["triggers.1.trigger"] = Heads{ key = "NEFARIAN_FEAR", on = "WA_NEFARIAN_FEAR_PREWARN", cancel = "WA_NEFARIAN_FEAR_PREWARN_CANCEL",
        icon = 136129, autoHide = true },
}

-- ============================================================
-- CONTROLLERS - every boss ability's countdown
-- ============================================================
-- trash: who got Flame Buffet / Mark of Detonation
B["CT:[BWL][Trash] Flame Buffet"] = { ["init"] = function() end, ["triggers.1.trigger"] = Relay(22433, "WA_FLAME_BUFFET"), ["actions.finish.custom"] = Rewind }
B["CT:[BWL][Trash] Mark of Detonation"] = { ["init"] = function() end, ["triggers.1.trigger"] = Relay(22438, "WA_MARK_OF_DETONATION"), ["actions.finish.custom"] = Rewind }

-- trash Flamestrike: the "went off" carries the caster's GUID (no count),
-- and a Hatcherbinder dying takes its bar down
do
    local BINDERS = K.Set({ "12468", "12457" })
    local aim = Aim("WA_TRASH_FLAMESTRIKE_TARGET", true)
    B["CT:[BWL][Trash] Flamestrike"] = {
        ["init"] = function(env) env.key = "TRASH_FLAMESTRIKE" end,
        ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId)
            if subEvent == "UNIT_DIED" and BINDERS[K.NpcId(destGUID)] then
                RM.Fire("WA_TRASH_HATCHERBINDER_DEATH", destGUID)
            end
            if spellId ~= 22275 then return false end
            if subEvent == "SPELL_CAST_START" then
                aim(env, allstates, sourceGUID)
                RM.Fire("WA_NUMEN_TIMER", "TRASH_FLAMESTRIKE", 0, sourceGUID)
                return true
            end
        end,
    }
end

-- Razorgore: the pull, and phase 2 when he casts Warming Flames (no
-- countdown of its own to stop).
B["CT:[BWL][Razorgore] Phase Controller"] = {
    ["init"] = function() end,
    ["triggers.1.trigger"] = function(env, allstates, event, encounterId, subEvent, _, _, _, _, _, _, _, _, _, spellId)
        if event == "ENCOUNTER_START" and encounterId == 610 then
            RM.Fire("WA_RAZORGORE_P1_START")
            return true
        end
        if spellId ~= 23040 then return false end
        if subEvent == "SPELL_CAST_SUCCESS" then
            RM.Fire("WA_RAZORGORE_P2_START")
            return true
        end
    end,
    ["actions.finish.custom"] = Rewind,
}

-- the thirty eggs: each Destroy Egg cast is on the bus, the successful
-- ones with how many are left (the event names are spelt as they always
-- were - other clients listen for them)
B["CT:[BWL][Razorgore] Destroy Egg"] = {
    ["init"] = function(env) env.eggs = 30 end,
    ["triggers.1.trigger"] = function(env, allstates, event, encounterId, subEvent, _, _, _, _, _, _, _, _, _, spellId)
        if event == "WA_FJI_ENCOUNTER_END" or (event == "ENCOUNTER_START" and encounterId == 610) then env.eggs = 30 end
        if spellId ~= 19873 then return false end
        if subEvent == "SPELL_CAST_START" then
            RM.Fire("WA_RAZORGORE_DESTROY_EGG_START")
        elseif subEvent == "SPELL_CAST_FAILED" then
            RM.Fire("WA_RAZOGORE_DESTROY_EGG_FAILED")
        elseif subEvent == "SPELL_CAST_SUCCESS" then
            env.eggs = env.eggs - 1
            RM.Fire("WA_RAZORGORE_DESTROY_EGG_SUCCESS", env.eggs)
            if env.eggs == 0 then RM.Fire("WA_RAZORGOR_NO_EGGS_LEFT") end
            return true
        end
    end,
}

-- whoever takes the orb (Mind Exhaustion lands on them)
B["CT:[BWL][Razorgore] Mind Exhaustion"] = { ["init"] = function() end, ["triggers.1.trigger"] = Relay(23958, "WA_RAZORGORE_CONTROL_ORB") }

-- Conflagration also says who caught it (at most every five seconds)
do
    local map = Ability{ key = "RAZORGORE_CONFLAGRATION", spell = 23023, pullOn = { "WA_RAZORGORE_P2_START" }, first = 16, every = 20.5, hideOn = ENDS }
    local timer, setup = map["triggers.1.trigger"], map["init"]
    map["init"] = function(env)
        setup(env)
        env.throttle = 0
    end
    map["triggers.1.trigger"] = function(env, allstates, event, ts, subEvent, hide, srcGUID, srcName, srcFlags, srcRaid, destGUID, ...)
        local r = timer(env, allstates, event, ts, subEvent, hide, srcGUID, srcName, srcFlags, srcRaid, destGUID, ...)
        if r ~= nil or subEvent ~= "SPELL_AURA_APPLIED" or select(4, ...) ~= 23023 then return r end
        if GetTime() - (env.throttle or 0) < 5 then return false end
        env.throttle = GetTime()
        RM.Fire("WA_RAZORGORE_CONFLAGRATION_TARGET", destGUID)
    end
    B["CT:[BWL][Razorgore] Conflagration"] = map
end
B["CT:[BWL][Razorgore] War Stomp"] = Ability{ key = "RAZORGORE_WAR_STOMP", spell = 24375, pullOn = { "WA_RAZORGORE_P2_START" }, first = 20.5, every = 20.5, hideOn = ENDS }
-- Fireball Volley only counts its casts: no reliable timer, on purpose
B["CT:[BWL][Razorgore] Fireball Volley"] = Ability{ key = "RAZORGORE_FIREBALL_VOLLEY", spell = 22425, sub = "SPELL_CAST_START", pullOn = { "WA_RAZORGORE_P2_START" } }

-- Vael: every Burning Adrenaline says who has it; the timer moves on at
-- most every three and a half seconds (the old and new spell ids)
do
    local SPELLS = K.Set({ 18173, 23620 })
    local map = Ability{ key = "VAEL_ADRENALINE", spells = { 18173, 23620 }, sub = "SPELL_AURA_APPLIED", first = 15.7, every = 15.7, hideOn = ENDS }
    local timer, setup = map["triggers.1.trigger"], map["init"]
    map["init"] = function(env)
        setup(env)
        env.throttle = 0
    end
    map["triggers.1.trigger"] = function(env, allstates, event, ts, subEvent, hide, srcGUID, srcName, srcFlags, srcRaid, destGUID, destName, destFlags, destRaid, spellId, ...)
        if subEvent == "SPELL_AURA_APPLIED" and SPELLS[spellId] then
            RM.Fire("WA_VAEL_ADRENALINE_TARGET", env.count, destGUID, destName)
            if GetTime() - (env.throttle or 0) < 3.5 then return false end
            env.throttle = GetTime()
        end
        return timer(env, allstates, event, ts, subEvent, hide, srcGUID, srcName, srcFlags, srcRaid, destGUID, destName, destFlags, destRaid, spellId, ...)
    end
    B["CT:[BWL][Vael] Burning Adrenaline"] = map
end
B["CT:[BWL][Vael] Flame Breath"] = Ability{ key = "VAEL_FLAME_BREATH", spell = 23461, sub = "SPELL_CAST_START", first = 4.5, every = 6, hideOn = ENDS,
    aim = "WA_VAEL_FLAME_BREATH_TARGET" }

B["CT:[BWL][Broodlord] Blast Wave"] = Ability{ key = "BROODLORD_BLAST_WAVE", spell = 23331, first = 16, every = 20, hideOn = ENDS }
-- Mortal Strike: no timer, just who it hit
B["CT:[BWL][Broodlord] Mortal Strike"] = Ability{ key = "BROODLORD_MORTAL_STRIKE", spell = 24573, guid = true, hideOn = ENDS }

-- the drakes: Shadow Flame (aimed at the tank) and Wing Buffet, each with
-- a heads-up shortly before
local SHADOW_FLAME, WING_BUFFET = 22539, 23339
B["CT:[BWL][Firemaw] Shadow Flame"] = Ability{ key = "FIREMAW_SHADOW_FLAME", ready = "WA_FIREMAW_SHADOW_FLAME_READY", spell = SHADOW_FLAME, sub = "SPELL_CAST_START", first = 18, every = 14,
    prewarn = 2, prewarnCount = true, hideOn = ENDS, aim = "WA_FIREMAW_SHADOWFLAME_TARGET" }
local function WingBuffet(boss)
    return Ability{ key = boss .. "_WING_BUFFET", spell = WING_BUFFET, sub = "SPELL_CAST_START", first = 30, every = 31,
        prewarn = 3.5, prewarnCount = true, hideOn = ENDS, finish = "prewarn" }
end
B["CT:[BWL][Firemaw] Wing Buffet"] = WingBuffet("FIREMAW")
-- Shadow of Ebonroc: no timer, who it landed on
B["CT:[BWL][Ebonroc] Shadow of Ebonroc"] = Ability{ key = "EBONROC_SHADOW_OF_EBONROC", spell = 23340, sub = "SPELL_AURA_APPLIED", pull = false,
    guid = true, hideOn = ENDS, onCast = function(env, allstates) K.Put(allstates, "", {}) end }
B["CT:[BWL][Ebonroc] Shadow Flame"] = Ability{ key = "EBONROC_SHADOW_FLAME", ready = "WA_EBONROC_SHADOW_FLAME_READY", spell = SHADOW_FLAME, from = "14601", sub = "SPELL_CAST_START",
    first = 18, every = 14, hideOn = ENDS, aim = "WA_EBONROC_SHADOWFLAME_TARGET" }
B["CT:[BWL][Ebonroc] Wing Buffet"] = WingBuffet("EBONROC")
B["CT:[BWL][Flamegor] Frenzy"] = Ability{ key = "FLAMEGOR_FRENZY", spell = 23342, first = 10, every = 9, prewarn = 3, prewarnCount = true,
    hideOn = ENDS, finish = "prewarn" }
B["CT:[BWL][Flamegor] Shadow Flame"] = Ability{ key = "FLAMEGOR_SHADOW_FLAME", ready = "WA_FLAMEGOR_SHADOW_FLAME_READY", spell = SHADOW_FLAME, from = "11981", sub = "SPELL_CAST_START",
    first = 18, every = 14, prewarn = 2, prewarnCount = true, hideOn = ENDS, aim = "WA_FLAMEGOR_SHADOWFLAME_TARGET" }
B["CT:[BWL][Flamegor] Wing Buffet"] = WingBuffet("FLAMEGOR")

-- Chromaggus: two breaths, picked per fight. The first two casts tell us
-- which is which; after that each slot has its own named countdown
-- (CHROMAGGUS_BREATH_FIRST_INCINERATE ...) and heads-up five seconds out.
do
    local FIRST, SECOND = "CHROMAGGUS_BREATH_FIRST", "CHROMAGGUS_BREATH_SECOND"
    local KIND = {
        [23308] = "INCINERATE", [23309] = "INCINERATE", [23313] = "CORROSIVE", [23314] = "CORROSIVE",
        [23187] = "FROST_BURN", [23189] = "FROST_BURN", [23315] = "IGNITE_FLESH", [23316] = "IGNITE_FLESH",
        [23310] = "TIME_LAPSE", [23312] = "TIME_LAPSE",
    }
    local EVERY, LEAD = 60, 5
    local function Countdown(key, secs, count) RM.Fire("WA_NUMEN_TIMER", key, secs, count) end
    local function HeadsUp(env, key, secs, count)
        local warns = env.warns
        if warns[key] then warns[key]:Cancel() end
        warns[key] = C_Timer.NewTimer(secs - LEAD, function()
            RM.Fire("WA_" .. key .. "_PREWARN", LEAD, count)
            warns[key] = nil
        end)
    end
    local function Fresh(env)
        env.firstBreath, env.secondBreath = nil, nil
        env.firstCount, env.secondCount, env.count = 1, 1, 1
    end
    B["CT:[BWL][Chromaggus] Breaths"] = {
        ["init"] = function(env)
            Fresh(env)
            env.warns = {}
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, _, _, _, _, _, _, _, spellId)
            if event == "WA_FJI_ENCOUNTER_END" or event == "ENCOUNTER_END" then K.Drop(allstates, "") end
            if event == "ENCOUNTER_START" then
                Fresh(env)
                K.Put(allstates, "", {})
                HeadsUp(env, FIRST, 30, env.count)
                HeadsUp(env, SECOND, 60, env.count)
                Countdown(FIRST, 30, env.count)
                Countdown(SECOND, 60, env.count)
                return true
            end
            local kind = subEvent == "SPELL_CAST_START" and KIND[spellId]
            if not kind then return end
            if env.count == 1 and not env.firstBreath then env.firstBreath = kind
            elseif env.count == 2 and not env.secondBreath then env.secondBreath = kind end
            local odd = env.count % 2 == 1
            local slot = odd and FIRST or SECOND
            local named = slot .. "_" .. (odd and env.firstBreath or env.secondBreath)
            local n = odd and env.firstCount or env.secondCount
            RM.Fire("WA_CHROMAGGUS_" .. kind .. "_START")
            if env.count <= 2 then
                -- the slot's unnamed countdown hands over to the named one
                Countdown(slot, 0, n)
                Countdown(slot, nil)
            end
            Countdown(named, EVERY, n)
            HeadsUp(env, named, EVERY, n)
            env.count = env.count + 1
            if odd then env.firstCount = env.firstCount + 1 else env.secondCount = env.secondCount + 1 end
            return true
        end,
        ["actions.finish.custom"] = function(env)
            Fresh(env)
            for _, t in pairs(env.warns) do t:Cancel() end
            env.warns = {}
        end,
    }
end

-- Frenzy: no timer; the pull puts the count back to 1
do
    local map = Ability{ key = "CHROMAGGUS_FRENZY", spell = 23128, sub = "SPELL_AURA_APPLIED", pull = false }
    local timer = map["triggers.1.trigger"]
    map["triggers.1.trigger"] = function(env, allstates, event, ...)
        if event == "ENCOUNTER_START" then env.count = 1 end
        return timer(env, allstates, event, ...)
    end
    B["CT:[BWL][Chromaggus] Frenzy"] = map
end

-- Chromaggus' vulnerability: when he flinches (or on the pull, or when
-- asked), read his buffs four times a second for a few seconds and put
-- the school on the bus (WA_CHROM_VULN school, icon) - or "Apply Detect
-- Magic" when none shows, at most every five seconds.
do
    local FLINCH = string.format("%s flinches as its skin shimmers.", ".*")
    local NONE = "Apply Detect Magic"
    local function Look(env)
        local name, icon, found = NONE, NO_VULN_ICON, false
        -- every school is checked; the last one showing wins
        for _, v in ipairs(VULNS) do
            for slot = 1, 2 do
                if select(10, UnitBuff("target", slot)) == v[1] then
                    name, icon, found = v[2], v[3], true
                    break
                end
            end
        end
        local quiet = GetTime() - (env.throttleTime or 0) > 5
        if found and (env.lastStateDetect or quiet) then
            RM.Fire("WA_CHROM_VULN", name, icon)
            env.throttleTime = GetTime()
            env.lastStateDetect = false
        elseif not found and quiet then
            RM.Fire("WA_CHROM_VULN", name, icon)
            env.throttleTime = GetTime()
            env.lastStateDetect = true
        end
    end
    local function Watch(env)
        if env.ticker then env.ticker:Cancel() end
        env.throttleTime = 0
        env.ticker = C_Timer.NewTicker(0.25, function() Look(env) end, 15)
    end
    B["CT:[BWL][Chromaggus] Vulnerability"] = {
        ["init"] = function() end,
        ["triggers.1.trigger"] = function(env, allstates, event, msg)
            if event == "CHAT_MSG_MONSTER_EMOTE" and msg and msg:find(FLINCH) then Watch(env) end
            if event == "WA_CHROM_VULN_CHECK" or event == "ENCOUNTER_START" then Watch(env) end
        end,
    }
end

-- Nefarian: Shadow Command (mind control) says who, by GUID and name
B["CT:[BWL][Nefarian] Shadow Command"] = {
    ["init"] = function() end,
    ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, _, _, _, destGUID, destName, _, _, spellId)
        if spellId ~= 22667 then return false end
        if subEvent == "SPELL_AURA_APPLIED" then
            RM.Fire("WA_NUMEN_TIMER", "NEFARIAN_SHADOW_COMMAND", 0, destGUID, destName)
            return true
        end
    end,
}

-- the phases, from his yells: P1 on the pull, P2 when he lands, P3 when
-- the dead rise; and the 42 drakonids of phase 1 counted down
do
    local LINES = {
        enUS = { "Let the games begin!", "Well done, my minions. The mortals' courage begins to wane!", "Impossible! Rise my minions!  Serve your master once more!" },
        frFR = { "Que les jeux commencent !", "Beau travail ! Le courage des mortels commence à faiblir ! Voyons maintenant s'ils peuvent lutter contre le véritable seigneur du pic Blackrock !", "C'est impossible ! Relevez-vous, serviteurs ! Servez une nouvelle fois votre maître !" },
        deDE = { "Let the games begin!", "Sehr gut, meine Diener. Der Mut der Sterblichen scheint zu schwinden! Nun lasst uns sehen, wie sie sich gegen den wahren Herrscher des Schwarzfels behaupten werden!", "Unmöglich! Erhebt Euch, meine Diener! Kämpft erneut für Euren Meister!" },
        esES = { "Let the games begin!", "Bien hecho, mis esbirros. El coraje de los mortales empieza a mermar. ¡Veamos ahora cómo se enfrentan al verdadero Señor de la Cubre de Roca Negra!", "¡Imposible! ¡Erguíos, mis esbirros! ¡Servid a vuestro maestro una vez más!" },
        esMX = { "¡Que comiencen los juegos!", "Bien hecho, mis esbirros. El coraje de los mortales empieza a mermar. ¡Veamos ahora cómo se enfrentan al verdadero Señor de la Cubre de Roca Negra!", "¡Imposible! ¡Levántense, mis esbirros! ¡Sirvan a su amo una vez más!" },
        koKR = { "게임을 시작하자!", "잘했다! 적들의 사기가 떨어지고 있다! 검은바위 첨탑의 군주에게 도전한 대가를 치르게 해주자!", "말도 안 돼! 일어나라! 다시 한 번 너희 주인을 섬겨라!" },
        ptBR = { "Que comecem os jogos!", "Muito bem, meus lacaios. A coragem dos mortais começa a vacilar! Agora vejamos como eles enfrentarão o verdadeiro Senhor dos Rocha Negra!!!", "Impossível! Ergam-se, meus lacaios! Sirvam ao seu mestre mais uma vez!" },
        ruRU = { "Let the games begin!", "Браво, слуги мои! Смертные утрачивают мужество! Поглядим же, как они справятся с истинным Повелителем Черной горы!!!", "Не может быть! Восстаньте, мои прислужники! Послужите господину еще раз!" },
        zhCN = { "Let the games begin!", "干得好，我的手下。凡人的勇气开始消退!现在，现在让我们看看他们如何应对黑石之王的力量!!!", "不可能!出现吧，我的仆人!再次为我的主人服务!" },
        zhTW = { "Let the games begin!", "幹得好，我的手下。凡人的勇氣開始消退!現在，現在讓我們看看他們如何應對黑石之王的力量!!!", "不可能!出現吧，我的僕人!再次為我的主人服務!" },
    }
    local PHASE_EVENT = { "WA_NEFARIAN_P1_START", "WA_NEFARIAN_P2_START", "WA_NEFARIAN_P3_START" }
    local DRAKONIDS = K.Set({ "14264", "14263", "14261", "14265", "14262", "14302" })
    local ADDS = 42
    B["CT:[BWL][Nefarian] Phase Controller"] = {
        ["init"] = function(env)
            env.lines = LINES[GetLocale()] or LINES.enUS
            env.addsGUID = {}
            env.addsLeft = ADDS
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, arg, subEvent, _, _, _, _, _, destGUID)
            if event == "ENCOUNTER_START" and arg == 617 then RM.Fire("WA_NEFARIAN_P1_START") end
            if event == "CHAT_MSG_MONSTER_YELL" and arg then
                for phase, line in ipairs(env.lines) do
                    if arg:find(line) then
                        RM.Fire(PHASE_EVENT[phase])
                        break
                    end
                end
            end
            if event == "WA_NEFARIAN_P1_START" then
                env.addsLeft = ADDS
                env.addsGUID = {}
                K.Put(allstates, "", {})
                return true
            end
            if subEvent == "UNIT_DIED" and DRAKONIDS[K.NpcId(destGUID)] and not env.addsGUID[destGUID] then
                env.addsGUID[destGUID] = true
                env.addsLeft = env.addsLeft - 1
                RM.Fire("WA_NEFARIAN_ADD_COUNT", env.addsLeft)
            end
        end,
    }
end

-- Class Call: heard in his yell; the "went off" carries the class. Every
-- call carries a fourth value (nil when there is no class). The lines are
-- matched as plain text (several have a "?" or "...").
do
    local CALLS = {
        enUS = {
            Druid = "Druids and your silly shapeshifting. Lets see it in action!",
            Hunter = "Hunters and your annoying pea-shooters!",
            Mage = "Mages too? You should be more careful when you play with magic...",
            Paladin = "Paladins... I've heard you have many lives. Show me.",
            Priest = "Priests! If you're going to keep healing like that, we might as well make it a little more interesting!",
            Rogue = "Rogues? Stop hiding and face me!",
            Shaman = "Shamans, show me",
            Warlock = "Warlocks, you shouldn't be playing with magic you don't understand. See what happens?",
            Warrior = "Warriors, I know you can hit harder than that! Lets see it!",
        },
        frFR = {
            Druid = "Les druides et leur stupides changements de forme. Voyons ce qu'ils donnent en vrai...",
            Hunter = "Ah, les chasseurs et les stupides sarbacanes !",
            Mage = "Les mages aussi ? Vous devriez être plus prudents lorsque vous jouez avec la magie.",
            Paladin = "Les paladins... J'en entendu dire que vous aviez de nombreuses vies... Montrez-moi.",
            Priest = "Prêtres ! Si vous continuez à soigner comme ça, nous pourrions rendre le processus plus intéressant !",
            Rogue = "Voleurs, arrêtez de vous cacher et affrontez-moi !",
            Shaman = "Chamans, montrez-moi ce que vos totems peuvent faire !",
            Warlock = "Démonistes, vous ne devriez pas jouer avec une magie qui vous dépasse. Vous voyez ce qui arrive ?",
            Warrior = "Guerriers, je sais que vous pouvez frapper plus fort que ça ! Voyons ça !",
        },
        deDE = {
            Druid = "Druiden und ihre lächerliche Gestaltwandlung. Zeigt mal was Ihr könnt!",
            Hunter = "Jäger und ihre lästigen Knallbüchsen!",
            Mage = "Auch Magier? Ihr solltet vorsichtiger sein, wenn Ihr mit Magie spielt...",
            Paladin = "Paladine... ich habe gehört, dass Ihr viele Leben habt. Zeigt es mir.",
            Priest = "Priester! Wenn Ihr weiterhin so heilt, können wir es auch gerne etwas interessanter gestalten!",
            Rogue = "Schurken? Kommt aus den Schatten und zeigt Euch!",
            Shaman = "Schamane, zeigt mir was eure Totems können!",
            Warlock = "Hexenmeister, Ihr solltet nicht mit Magie spielen, die Ihr nicht versteht. Seht Ihr was ich meine?",
            Warrior = "Krieger, Ich bin mir sicher, dass ihr kräftiger als das zuschlagen könnt!",
        },
        esES = {
            Druid = "Los druidas y vuestro estúpido poder de cambiar de forma. ¡Veámoslo en acción!",
            Hunter = "¡Cazadores y vuestras molestas cerbatanas!",
            Mage = "¡Magos también? Deberíais tener más cuidado cuando jugáis con la magia...",
            Paladin = "Paladines... He oído que tenéis muchas vidas. Demostrádmelo.",
            Priest = "¡Sacerdotes! Si vais a seguir curando de esa forma, ¡podríamos hacerlo más interesante!",
            Rogue = "¿Pícaros? ¡Dejad de esconderos y enfrentaos a mí!",
            Shaman = "¡Chamanes, mostradme lo que pueden hacer vuestros tótems!",
            Warlock = "Brujos... No deberíais estar jugando con magia que no comprendéis. ¿Veis lo que pasa?",
            Warrior = "¡Vamos guerreros, sé que podéis golpear más fuerte que eso! ¡Veámoslo!",
        },
        esMX = {
            Druid = "Los druidas y su estúpido poder de cambiar de forma. ¡Veámoslo en acción!",
            Hunter = "¡Cazadores y sus molestas cerbatanas!",
            Mage = "¿Magos también? Deberían tener más cuidado cuando juegan con la magia...",
            Paladin = "Paladines... He oído que tienen muchas vidas. Demuéstrenmelo.",
            Priest = "¡Sacerdotes! Si van a seguir curando de esa forma, ¡podíamos hacerlo más interesante!",
            Rogue = "¿Pícaros? ¡Dejen de esconderse y enfréntense a mí!",
            Shaman = "¡Chamanes, muéstrenme lo que pueden hacer sus tótems!",
            Warlock = "Brujos... No deberían estar jugando con magia que no comprenden. ¿Ven lo que pasa?",
            Warrior = "¡Vamos guerreros, sé que pueden golpear más fuerte que eso! ¡Veámoslo!",
        },
        koKR = {
            Druid = "드루이드 녀석, 그 바보 같은 변신을 했다고 내가 모를 줄 알았더냐? 받아라!",
            Hunter = "사냥꾼 놈에다 그 장난감 같은 총이라니! 정말 거슬리는구나!",
            Mage = "네가 마법사냐? 마법을 가지고 장난칠 상대를 고를 때는 좀 더 신중했어야지...",
            Paladin = "성기사여, 네 목숨은 여러개라고 하던데 어디 한번 보여다오.",
            Priest = "성직자야, 그렇게 치유를 계속할 테냐? 그럼 어디 좀 더 재미있게 만들어 줄까?",
            Rogue = "도적들인가? 숨어 다니지만 말고 나와서 나와 맞서라!",
            Shaman = "주술사, 네놈의 토템이 얼마나 쓸모 있는지 한번 보자!",
            Warlock = "흑마법사여, 네가 이해하지도 못하는 마법을 가지고 장난을 쳐서야 쓰나... 바로 이런 꼴이 되어버렸지 않느냐!",
            Warrior = "전사들이로군, 네가 그보다 더 강하게 내려칠 수 있다는 걸 알고 있다! 어디 한 번 제대로 쳐 보란 말이다!",
        },
        ptBR = {
            Druid = "Druidas e suas metamorfoses idiotas. Vamos vê-las em ação!",
            Hunter = "Caçadores e seus irritantes atiradores de ervilhas!",
            Mage = "Magos também? Vocês deveriam ter mais cuidado ao brincar com magia...",
            Paladin = "Paladinos... ouvi dizer que vocês têm muitas vidas. Isso eu quero ver.",
            Priest = "Sacerdotes! Se vocês continuarem a curar desse jeito, acho que podemos tornar as coisas um pouquinho mais interessantes!",
            Rogue = "Ladinos? Parem de se esconder e venham me enfrentar!",
            Shaman = "Xamãs, mostrem-me do que seus totens são capazes!",
            Warlock = "Bruxos, vocês não deveriam brincar com magias que não compreendem. Viram só o que acontece?",
            Warrior = "Guerreiros, sei que vocês conseguem bater mais forte que isso! Vamos!",
        },
        ruRU = {
            Druid = "Друиды и их дурацкие превращения… Ну что ж, поглядим!",
            Hunter = "Охотники со своими жалкими пугачами!",
            Mage = "И маги тоже? Осторожнее надо быть, когда играешь с магией…",
            Paladin = "Паладины… Я слышал, у вас несколько жизней. Докажите.",
            Priest = "Жрецы! Если вы собираетесь продолжать так лечить, то давайте хоть немного разнообразим процесс!",
            Rogue = "Rogues? Stop hiding and face me!",
            Shaman = "Шаманы, покажите, на что способны ваши тотемы!",
            Warlock = "Чернокнижники, ну не беритесь вы за волшебство, которого сами не понимаете! Видите, что получилось?",
            Warrior = "Воины! Я знаю, вы можете бить сильнее! Ну-ка, покажите!",
        },
        zhCN = {
            Druid = "德鲁伊和你们愚蠢的变身术。让我们看看什么会发生吧!",
            Hunter = "猎人和你那讨厌的豌豆射击!",
            Mage = "还有法师?你应该小心使用你的魔法...",
            Paladin = "圣骑士...听说你有无数条命。让我看看到底是怎么样的吧。",
            Priest = "牧师!如果你要继续像那样治疗，我们还不如让它看起来更有趣!",
            Rogue = "潜行者?不要躲了，面对我吧!",
            Shaman = "萨满，让我看看",
            Warlock = "术士，不要随便去玩那些你不理解的法术。看看会发生什么吧?",
            Warrior = "战士，我知道你的力量不只如此!让我们来见识一下吧!",
        },
        zhTW = {
            Druid = "德魯伊和你們愚蠢的變身術。讓我們看看什麼會發生吧!",
            Hunter = "獵人和你那討厭的豌豆射擊!",
            Mage = "還有法師?你應該小心使用你的魔法...",
            Paladin = "聖騎士...聽說你有無數條命。讓我看看到底是怎麼樣的吧。",
            Priest = "牧師!如果你要繼續這麼治療的話，那我們來玩點有趣的東西!",
            Rogue = "盜賊?不要躲了，面對我吧!",
            Shaman = "薩滿，讓我看看",
            Warlock = "術士，不要隨便去玩那些你不理解的法術。看看會發生什麼吧?",
            Warrior = "戰士，我知道你的力量不只如此!讓我們來見識一下吧!",
        },
    }
    local KEY, FIRST, EVERY = "NEFARIAN_CLASS_CALL", 30, 30
    local function Countdown(secs, count, class) RM.Fire("WA_NUMEN_TIMER", KEY, secs, count, class) end
    B["CT:[BWL][Nefarian] Class Call"] = {
        ["init"] = function(env)
            env.key = KEY
            env.count = 1
            env.calls = CALLS[GetLocale()] or CALLS.enUS
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, msg)
            if event == "WA_FJI_ENCOUNTER_END" or event == "ENCOUNTER_END" then K.Drop(allstates, "") end
            if event == "WA_NEFARIAN_P2_START" then
                K.Put(allstates, "", {})
                Countdown(FIRST, env.count)
                return true
            end
            if event ~= "CHAT_MSG_MONSTER_YELL" or not msg then return end
            for _, c in ipairs(CLASSES) do
                if msg:find(env.calls[c[1]], 1, true) then
                    Countdown(0, env.count, c[1])
                    env.count = env.count + 1
                    Countdown(EVERY, env.count)
                    return true
                end
            end
        end,
        ["actions.finish.custom"] = function(env)
            env.count = 1
            Countdown(nil)
        end,
    }
end

-- Fear (Bellowing Roar): counted from the landing, with a heads-up
B["CT:[BWL][Nefarian] Fear"] = Ability{ key = "NEFARIAN_FEAR", spell = 22686, sub = "SPELL_CAST_START", pullOn = { "WA_NEFARIAN_P2_START" },
    every = 26.7, prewarn = 5, prewarnCount = true, hideOn = ENDS }
-- a paladin's Blessing of Protection made improved by the class call:
-- only the "went off" (no count)
B["CT:[BWL][Nefarian] Improved Blessing of Protection"] = {
    ["init"] = function() end,
    ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, _, _, _, _, _, _, _, spellId)
        if spellId ~= 23415 then return false end
        if subEvent == "SPELL_AURA_APPLIED" then
            RM.Fire("WA_NUMEN_TIMER", "NEFARIAN_BOP", 0)
            return true
        end
    end,
}
-- Nefarian's Shadow Flame: who it is aimed at, no timer (none reliable)
B["CT:[BWL][Nefarian] Shadow Flame"] = Ability{ key = "NEFARIAN_SHADOW_FLAME", spell = SHADOW_FLAME, sub = "SPELL_CAST_START",
    pullOn = { "WA_NEFARIAN_P2_START" }, hideOn = ENDS, aim = "WA_NEFARIAN_SHADOWFLAME_TARGET" }

-- Veil of Shadow: no reliable timings, so on purpose the pull and each
-- cast send a countdown with no seconds (which stops any bar) - only the
-- "went off", with who it hit, does anything.
do
    local KEY = "NEFARIAN_VEIL"
    local function Countdown(secs, count, guid) RM.Fire("WA_NUMEN_TIMER", KEY, secs, count, guid) end
    B["CT:[BWL][Nefarian] Veil of Shadow"] = {
        ["init"] = function(env)
            env.key = KEY
            env.count = 1
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, _, _, _, destGUID, _, _, _, spellId)
            if event == "WA_FJI_ENCOUNTER_END" or event == "ENCOUNTER_END" then K.Drop(allstates, "") end
            if event == "ENCOUNTER_START" then
                K.Put(allstates, "", {})
                Countdown(nil, env.count)
                return true
            end
            if spellId ~= 22687 then return false end
            if subEvent == "SPELL_AURA_APPLIED" then
                Countdown(0, env.count, destGUID)
                env.count = env.count + 1
                Countdown(nil, env.count)
                return true
            end
        end,
        ["actions.finish.custom"] = function(env)
            env.count = 1
            Countdown(nil)
        end,
    }
end

-- ============================================================
-- ICONS
-- ============================================================
-- the vulnerability of the Wyrmguard / Overseer you are targeting
local VULN_ADDS = K.Set({ "12460", "12461" })
B["I:[BWL][Trash] Elemental Vulnerability"] = {
    ["init"] = function() end,
    ["logic"] = ForClassesOrLeads(ALL_CLASSES, true),
    ["triggers.1.trigger"] = function(env, allstates, event)
        local function Read()
            local v = VulnOn("target")
            if v then return "+" .. v[2], v[3] end
            return "", NO_VULN_ICON
        end
        if event == "OPTIONS" then return VulnSample(allstates) end
        if event == "PLAYER_TARGET_CHANGED" then
            local guid = UnitExists("target") and UnitGUID("target")
            if guid and VULN_ADDS[K.NpcId(guid)] then
                local name, icon = Read()
                K.Put(allstates, "", { name = name, icon = icon })
                return true
            end
            allstates[""] = { show = false, changed = true }
            return true
        elseif event == "UNIT_AURA" then
            local name, icon = Read()
            local st = allstates[""]
            if st then
                st.name, st.icon = name, icon
                return true
            end
        end
    end,
}
-- its settings piece: nothing to set up
B["I:[BWL][Trash] Onyxia Cloak"] = { ["init"] = function() end }
B["I:[BWL][Trash] Growing Flames"] = { ["text"] = PerStack(50) }
-- what Essence of the Red gives back, per class
B["I:[BWL][Trash] Essence of the Red"] = {
    ["text"] = function()
        local class = Me()
        if class == "Rogue" then return "20", "Energy p/s" end
        if class == "Warrior" then return "20", "Rage p/s" end
        return "500", "Mana p/s"
    end,
}
B["I:[BWL][Firemaw] Flame Buffet"] = { ["text"] = PerStack(150) }
B["I:[BWL][Chromaggus] Time Lapse"] = { ["actions.start.custom"] = Speech("Stunned") }
B["I:[BWL][Nefarian] Fear"] = { ["actions.start.custom"] = Speech("Fear") }

-- ============================================================
-- LARGE ICONS
-- ============================================================
B["A:[BWL][Trash] Mark of Detonation"] = { ["actions.start.custom"] = Speech("Marked") }
B["A:[BWL][Trash] Flame Buffet"] = { ["actions.start.custom"] = Speech("Flame Buffet") }
B["A:[BWL][Vael] Burning Adrenaline"] = { ["conditions.1.changes.1.value"] = Speech("Move Out") }
B["A:[BWL][Firemaw] Flame Buffet"] = { ["actions.start.custom"] = Speech("High Stacks"), ["text"] = PerStack(150) }
B["A:[BWL][Chromaggus] Brood Power: Bronze"] = { ["conditions.2.changes.1.value"] = Speech("Use Sand"), ["logic"] = Pick(1) }

-- your own class was called: its icon for the 30 seconds
B["A:[BWL][Nefarian] Your Class Call"] = {
    ["init"] = function() end,
    ["actions.start.custom"] = function(env)
        Say(((env.state and env.state.class) or "") .. " Class Call")
    end,
    ["triggers.1.trigger"] = function(env, allstates, event, key, secs, count, class)
        if not (event == "WA_NUMEN_TIMER" and key == "NEFARIAN_CLASS_CALL" and secs == 0) then return end
        if class == Me() then
            K.Put(allstates, "", K.Timed(30, { class = class, icon = CLASS_ICON[class] }))
            return true
        end
        return K.Drop(allstates, "")
    end,
}

-- ============================================================
-- LISTS
-- ============================================================
-- who has the orb: a minute each
do
    local function Orb(allstates, guid)
        K.Put(allstates, guid, K.Timed(60, { autoHide = true, controller = guid }))
        return true
    end
    B["L:[BWL][Razorgore] Mind Exhaustion"] = {
        ["triggers.1.trigger"] = function(env, allstates, event, guid)
            if event == "OPTIONS" then return Orb(allstates, RM.WA.myGUID) end
            if event == "WA_RAZORGORE_CONTROL_ORB" then return Orb(allstates, guid) end
        end,
    }
end
B["L:[BWL][Razorgore][Raid] Destroy Egg CD"] = { ["logic"] = function(env, t) return t[1] and not t[2] end }

-- the class just called, in its colour, for the 30 seconds
B["L:[BWL][Nefarian] Class Call"] = {
    ["init"] = function() end,
    ["triggers.1.icon"] = K.Always(135789),
    ["triggers.1.trigger"] = function(env, allstates, event, key, secs, count, class)
        if event == "OPTIONS" then
            allstates[""] = K.Timed(30, { show = true, icon = 626004, count = math.random(1, 3), class = "|cFFFFFFFFPriest|r" })
            return true
        end
        if event == "WA_NUMEN_TIMER" and key == "NEFARIAN_CLASS_CALL" and secs == 0 then
            local coloured, icon = ClassLook(class)
            K.Put(allstates, "", K.Timed(30, { icon = icon, autoHide = true, count = count, class = coloured }))
            return true
        end
    end,
}

-- ============================================================
-- MISC
-- ============================================================
B["[BWL] Auto Orb"] = { ["triggers.1.trigger"] = AutoGossip("autoOrb", { 29682 }) }
B["[BWL] Auto Vael"] = { ["triggers.1.trigger"] = AutoGossip("autoVael", { 29549, 30850 }) }
-- with its option on, the big boss-emote text in the middle of the screen
-- stops listening
B["[BWL] Disable Raid Emotes"] = K.MuteBossEmotes()

-- ============================================================
-- NAMEPLATES
-- ============================================================
B["N:[BWL][Trash] Bomb"] = { ["text"] = K.Field("addColour") }

-- the vulnerability of a Wyrmguard, Overseer or Chromaggus on its plate
do
    local SHOWN = K.Set({ "12460", "12461", "14020" })
    local function Read(unit)
        local v = VulnOn(unit)
        if v then return "+" .. v[2], v[3] end
        return "Apply Detect Magic", NO_VULN_ICON
    end
    B["N:[BWL][Trash] Elemental Vulnerability"] = {
        ["init"] = function() end,
        ["triggers.1.trigger"] = function(env, allstates, event, unit)
            if event == "OPTIONS" then return VulnSample(allstates) end
            if event == "NAME_PLATE_UNIT_ADDED" then
                local guid = UnitGUID(unit)
                if not SHOWN[K.NpcId(guid)] then return false end
                local name, icon = Read(unit)
                K.Put(allstates, guid, { name = name, icon = icon, unit = unit })
                return true
            end
            if event == "NAME_PLATE_UNIT_REMOVED" then
                K.Drop(allstates, UnitGUID(unit))
                return true
            end
            if event == "UNIT_AURA" then
                local guid = UnitGUID(unit)
                local st = allstates[guid]
                if st then
                    st.name, st.icon = Read(unit)
                    st.changed = true
                    return true
                end
            end
        end,
    }
end

-- Frenzy on the boss's plate for 15 seconds (gone early when it ends). A
-- mob whose buff ends off-screen picks its timer back up when its plate
-- returns.
do
    local DUR = 15
    local function PlateFrenzy(spell)
        return {
            ["init"] = function(env)
                env.expirationTimes = {}
                env.icons = {}
                env.guids = {}
            end,
            ["triggers.1.trigger"] = function(env, allstates, event, unit, subEvent, _, _, _, _, _, destGUID, _, _, _, spellId)
                if event == "NAME_PLATE_UNIT_REMOVED" and K.Drop(allstates, UnitGUID(unit)) then return true end
                if event == "NAME_PLATE_UNIT_ADDED" then
                    local guid = UnitGUID(unit)
                    local ends = env.expirationTimes[guid]
                    if ends and ends - GetTime() > 0 then
                        K.Put(allstates, guid, { progressType = "timed", duration = ends - GetTime(), expirationTime = ends, unit = unit,
                            autoHide = true, icon = env.icons[guid] })
                        return true
                    end
                end
                if spellId ~= spell then return false end
                if subEvent == "SPELL_AURA_APPLIED" then
                    env.guids[destGUID] = true
                    env.expirationTimes[destGUID] = DUR + GetTime()
                    env.icons[destGUID] = select(3, GetSpellInfo(spellId))
                    local plate = K.PlateFor(destGUID)
                    if plate then
                        K.Put(allstates, destGUID, { progressType = "timed", duration = DUR, expirationTime = env.expirationTimes[destGUID],
                            unit = plate, autoHide = true, icon = env.icons[destGUID] })
                        return true
                    end
                end
                if subEvent == "SPELL_AURA_REMOVED" and env.guids[destGUID] and K.Drop(allstates, destGUID) then
                    env.expirationTimes[destGUID] = nil
                    env.icons[destGUID] = nil
                    return true
                end
            end,
        }
    end
    -- the same Frenzy ids the bosses' controllers listen for
    B["N:[BWL][Flamegor] Frenzy"] = PlateFrenzy(23342)
    B["N:[BWL][Chromaggus] Frenzy"] = PlateFrenzy(23128)
end

-- trash with Brood Power: Bronze (it spins): marked on its plate until it
-- dies, and on the bus so the "spinner" text can check your target
B["N:[BWL][Trash] Brood Power: Bronze"] = {
    ["init"] = function(env) env.guids = {} end,
    ["triggers.1.trigger"] = function(env, allstates, event, unit, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId)
        if event == "NAME_PLATE_UNIT_REMOVED" and K.Drop(allstates, UnitGUID(unit)) then return true end
        if event == "NAME_PLATE_UNIT_ADDED" then
            local guid = UnitGUID(unit)
            if env.guids[guid] then
                K.Put(allstates, guid, { unit = unit })
                return true
            end
        end
        if subEvent == "UNIT_DIED" and env.guids[destGUID] and K.Drop(allstates, destGUID) then
            env.guids[destGUID] = nil
            return true
        end
        if spellId ~= 22291 then return false end
        if subEvent == "SPELL_AURA_APPLIED" then
            env.guids[sourceGUID] = true
            RM.Fire("WA_FJI_BWL_TRASH_SPINNER", sourceGUID)
            local plate = K.PlateFor(sourceGUID)
            if plate then
                K.Put(allstates, sourceGUID, { progressType = "static", unit = plate })
                return true
            end
        end
    end,
}

-- ============================================================
-- PROGRESS BARS
-- ============================================================
-- trash Flamestrike: one bar per caster, then who it is aimed at
B["PC:[BWL][Trash] Flamestrike"] = {
    ["text"] = K.Field("addColour"),
    ["triggers.1.trigger"] = function(env, allstates, event, ...)
        if event == "OPTIONS" then
            K.Put(allstates, "", K.Timed(2, { icon = 135826, guid = RM.WA.myGUID }))
            return true
        end
        if event == "WA_NUMEN_TIMER" then
            local key, secs, caster = ...
            if key == "TRASH_FLAMESTRIKE" and secs == 0 then
                K.Put(allstates, caster, K.Timed(2, { icon = 135826, autoHide = true }))
                return true
            end
        end
        if event == "WA_TRASH_FLAMESTRIKE_TARGET" then
            local _, victim, caster = ...
            local st = allstates[caster]
            if st then
                st.guid = victim
                st.changed = true
                st.isPlayer = victim == RM.WA.myGUID
                return true
            end
        end
        if event == "WA_TRASH_HATCHERBINDER_DEATH" then
            local guid = ...
            if K.Drop(allstates, guid) then return true end
        end
    end,
}

-- Vael's speech before the fight: 43 seconds (shared with the raid so
-- everyone's bar starts together; kept in a global for a reload)
do
    local PULL_LINE = {
        enUS = "Too late, friends!",
        frFR = "Trop tard, mes amis ! La corruption de Nefarius s'empare de moi… Je ne peux plus… me contrôler",
        deDE = "Zu spät, Freunde! Nefarius üble Macht wirkt bereits... Ich habe mich nicht... nicht mehr unter Kontrolle..",
        esES = "¡Demasiado tarde, amigos! Ahora estoy poseído por la corrupción de Nefarius... No puedo... controlarme.",
        koKR = "너무 늦었어! 네파리우스의 타락이 뿌리를 내려... 난... 나 자신을 통제할 수가 없어.",
        ruRU = "Слишком поздно, друзья!",
        zhCN = "太迟了，朋友! 奈法利斯的腐化已经掌握了我...我已经无法...控制我自己了。",
        zhTW = "太遲了，朋友! 奈法利斯的腐化已經掌握了我...我已經無法...控制我自己了。",
    }
    local function Bar(allstates)
        K.Put(allstates, "", { progressType = "timed", duration = _G.vaelTimer - GetTime(), expirationTime = _G.vaelTimer, autoHide = true })
        return true
    end
    B["PC:[BWL][Vael] RP Timer"] = {
        ["init"] = function(env) env.pullLine = PULL_LINE[GetLocale()] or PULL_LINE.enUS end,
        ["triggers.1.trigger"] = function(env, allstates, event, msg)
            if event == "CHAT_MSG_MONSTER_YELL" then
                if msg and msg:find(env.pullLine) then RM.Fire("WA_VAEL_RP_TIMER") end
            elseif event == "WA_VAEL_RP_TIMER" then
                _G.vaelTimer = GetTime() + 43
                return Bar(allstates)
            elseif event == "STATUS" and _G.vaelTimer and _G.vaelTimer - GetTime() > 0 then
                return Bar(allstates)
            end
        end,
    }
end

-- the breaths aimed at the tank: two seconds, with the count, then who
local function AimedBar(key, icon, aimed)
    return {
        ["text"] = K.Field("addColour"),
        ["triggers.1.trigger"] = Pop{ key = key, dur = 2, icon = icon, fill = WithCount, aimed = aimed, samplePut = true, sampleTrue = true,
            sample = function() return K.Timed(2, { icon = icon, count = math.random(1, 3), guid = RM.WA.myGUID }) end },
    }
end
B["PC:[BWL][Vael] Flame Breath"] = AimedBar("VAEL_FLAME_BREATH", 135805, "WA_VAEL_FLAME_BREATH_TARGET")
B["PC:[BWL][Firemaw] Shadow Flame"] = AimedBar("FIREMAW_SHADOW_FLAME", 135818, "WA_FIREMAW_SHADOWFLAME_TARGET")
B["PC:[BWL][Ebonroc] Shadow Flame"] = AimedBar("EBONROC_SHADOW_FLAME", 135818, "WA_EBONROC_SHADOWFLAME_TARGET")
B["PC:[BWL][Flamegor] Shadow Flame"] = AimedBar("FLAMEGOR_SHADOW_FLAME", 135818, "WA_FLAMEGOR_SHADOWFLAME_TARGET")
B["PC:[BWL][Nefarian] Shadow Flame"] = AimedBar("NEFARIAN_SHADOW_FLAME", 135818, "WA_NEFARIAN_SHADOWFLAME_TARGET")

-- a knock-back / fear going off: a short bar with the count
local function GoingOff(key, dur, icon)
    return {
        ["text"] = K.Field("addColour"),
        ["triggers.1.icon"] = K.Always(135789),
        ["triggers.1.trigger"] = Pop{ key = key, dur = dur, icon = icon, fill = WithCount, samplePut = true,
            sample = function() return K.Timed(dur, { icon = icon, autoHide = true, count = math.random(1, 3) }) end },
    }
end
B["PC:[BWL][Firemaw] Wing Buffet"] = GoingOff("FIREMAW_WING_BUFFET", 1, 134316)
B["PC:[BWL][Ebonroc] Wing Buffet"] = GoingOff("EBONROC_WING_BUFFET", 1, 134316)
B["PC:[BWL][Flamegor] Wing Buffet"] = GoingOff("FLAMEGOR_WING_BUFFET", 1, 134316)
B["PC:[BWL][Nefarian] Fear"] = K.Merge(GoingOff("NEFARIAN_FEAR", 1.5, 136129), { ["actions.start.custom"] = Speech("Fear") })
B["PC:[BWL][Nefarian] Active Timer"] = { ["triggers.1.trigger"] = K.Always(true) }

-- the Razorgore orb HUD: which trigger each shows
B["[BWL][Razorgore] Orb Duration"] = { ["logic"] = Pick(2) }
B["HUD:[BWL][Razorgore] Destroy Egg"] = { ["logic"] = Pick(2) }
B["HUD:[BWL][Razorgore] Calm Dragonkin"] = { ["logic"] = Pick(2) }
B["HUD:[BWL][Razorgore] Cleave"] = { ["logic"] = Pick(1) }
B["HUD:[BWL][Razorgore] Fireball Volley"] = { ["logic"] = Pick(2) }

-- ============================================================
-- PROGRESS BARS (TOP)
-- ============================================================
-- Chromaggus' vulnerability for its 17 seconds, spoken to the classes
-- that hit with that school (and the leader)
do
    local SHOWN = K.Set({ "Druid", "Hunter", "Mage", "Priest", "Rogue", "Warlock" })
    B["PT:[BWL][Chromaggus] Vulnerability"] = {
        ["conditions.2.changes.2.value"] = Speech("Fire Vuln"),
        ["conditions.3.changes.2.value"] = Speech("Frost Vuln", ClassOrLead("Mage")),
        ["conditions.4.changes.2.value"] = Speech("Nature Vuln", ClassOrLead("Druid", "Hunter", "Shaman", "Rogue")),
        ["conditions.5.changes.2.value"] = Speech("Arcane Vuln", ClassOrLead("Druid", "Hunter", "Mage")),
        ["conditions.6.changes.2.value"] = Speech("Shadow Vuln", ClassOrLead("Warlock", "Priest")),
        ["init"] = function() end,
        ["logic"] = ForClassesOrLeads(SHOWN),
        ["triggers.1.trigger"] = function(env, allstates, event, name)
            if event == "OPTIONS" then
                K.Put(allstates, "", K.Timed(2, { vulnerability = "Fire" }))
                return true
            end
            if event == "WA_CHROM_VULN" then
                K.Put(allstates, "", K.Timed(17, { vulnerability = name }))
                return true
            end
            if event == "WA_FJI_ENCOUNTER_END" and K.Drop(allstates, "") then return true end
        end,
    }
end

-- eggs destroyed, of thirty ("3 Eggs Left" is spoken by its condition)
B["PT:[BWL][Razorgore] Eggs Destroyed"] = {
    ["conditions.1.changes.1.value"] = Speech("3 Eggs Left"),
    ["init"] = function() end,
    ["triggers.1.trigger"] = function(env, allstates, event)
        if event == "OPTIONS" then
            local done = math.random(0, 30)
            K.Put(allstates, "", { value = done, total = 30, progressType = "static", remaining = done })
            return true
        end
        if event == "ENCOUNTER_START" then
            K.Put(allstates, "", { value = 0, total = 30, progressType = "static", remaining = 30 })
            return true
        end
        local st = allstates[""]
        if event == "WA_RAZORGORE_DESTROY_EGG_SUCCESS" and st then
            st.remaining = st.remaining - 1
            st.value = st.value + 1
            if st.value == 30 then st.show = false end
            st.changed = true
            return true
        end
        if event == "WA_FJI_ENCOUNTER_END" and K.Drop(allstates, "") then return true end
        return false
    end,
}

-- drakonids left in phase 1, of 42
B["PT:[BWL][Nefarian] Adds Remaining"] = {
    ["init"] = function() end,
    ["triggers.1.trigger"] = function(env, allstates, event, count)
        if event == "OPTIONS" then
            K.Put(allstates, "", { value = math.random(0, 42), total = 42, progressType = "static" })
            return true
        end
        if event == "WA_NEFARIAN_P1_START" then
            K.Put(allstates, "", { value = 42, total = 42, progressType = "static" })
            return true
        end
        local st = allstates[""]
        if event == "WA_NEFARIAN_ADD_COUNT" and st then
            st.value = count
            st.changed = true
            return true
        end
        if (event == "WA_NEFARIAN_P2_START" or event == "PLAYER_REGEN_ENABLED" or event == "WA_FJI_ENCOUNTER_END") and K.Drop(allstates, "") then
            return true
        end
        return false
    end,
}

-- ============================================================
-- RAID FRAMES
-- ============================================================
local function LeadOrHealer() return Leader() or _G.FJI_HEALER end
local function LeadHealerOr(...)
    local set = K.Set({ ... })
    return function() return Leader() or _G.FJI_HEALER or set[Me()] or false end
end
local function OneOf(...)
    local set = K.Set({ ... })
    return function() return set[Me()] or false end
end
local magicDispellers = LeadHealerOr("Paladin", "Priest")

B["RF:[BWL][Trash] Greater Polymorph"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[BWL][Trash] Flame Buffet"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[BWL][Trash] Mark of Detonation"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[BWL][Trash] War Stomp"] = { ["conditions.1.check.fn"] = LeadOrHealer }
B["RF:[BWL][Razorgore] Conflagration"] = { ["conditions.1.check.fn"] = LeadOrHealer }
B["RF:[BWL][Vael] Flame Breath Target"] = { ["triggers.1.trigger"] = AimedGlow("WA_VAEL_FLAME_BREATH_TARGET") }
B["RF:[BWL][Broodlord] Mortal Strike"] = { ["conditions.1.check.fn"] = LeadOrHealer }
B["RF:[BWL][Firemaw] Shadow Flame Target"] = { ["triggers.1.trigger"] = AimedGlow("WA_FIREMAW_SHADOWFLAME_TARGET") }
B["RF:[BWL][Ebonroc] Shadow of Ebonroc"] = { ["conditions.1.check.fn"] = K.IsClass({ "DRUID", "MAGE" }, true) }
B["RF:[BWL][Ebonroc] Shadow Flame Target"] = { ["triggers.1.trigger"] = AimedGlow("WA_EBONROC_SHADOWFLAME_TARGET", "player") }
B["RF:[BWL][Flamegor] Shadow Flame Target"] = { ["triggers.1.trigger"] = AimedGlow("WA_FLAMEGOR_SHADOWFLAME_TARGET", "player") }
-- Chromaggus' brood afflictions: who can take each off
B["RF:[BWL][Chromaggus] Brood: Black"] = { ["conditions.1.check.fn"] = OneOf("Mage", "Druid") }
B["RF:[BWL][Chromaggus] Brood: Blue"] = { ["conditions.1.check.fn"] = OneOf("Paladin", "Priest") }
B["RF:[BWL][Chromaggus] Brood: Green"] = { ["conditions.1.check.fn"] = OneOf("Paladin", "Druid", "Shaman") }
B["RF:[BWL][Chromaggus] Brood: Red"] = { ["conditions.1.check.fn"] = OneOf("Paladin", "Priest", "Shaman") }
B["RF:[BWL][Nefarian] Shadow Flame Target"] = {
    ["logic"] = function(env, t)
        if not t[1] then return false end
        return _G.FJI_HEAL or _G.FJI_TANK or Leader()
    end,
    ["triggers.1.trigger"] = AimedGlow("WA_NEFARIAN_SHADOWFLAME_TARGET", nil, 3),
}
B["RF:[BWL][Nefarian] Wild Polymorph"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[BWL][Nefarian] Veil of Shadow"] = { ["conditions.1.check.fn"] = LeadHealerOr("Mage", "Druid") }

-- ============================================================
-- SPECIAL ALERTS
-- ============================================================
B["SA:[BWL][All] GTFO"] = { ["actions.start.custom"] = Speech("Move") }
B["SA:[BWL][Trash] Brood Power: Green"] = { ["actions.start.custom"] = Speech("Stunned") }

-- the drake's Shadow Flame is due again: its controller fires
-- WA_<BOSS>_SHADOW_FLAME_READY when the countdown runs out
local function FlameReady(boss)
    return {
        ["logic"] = TanksHealersLead,
        ["triggers.1.trigger"] = Pop{ event = "WA_" .. boss .. "_SHADOW_FLAME_READY", dur = 1.5, icon = 135818,
            sample = function() return { icon = 135818 } end },
    }
end
B["SA:[BWL][Firemaw] Shadow Flame Ready"] = FlameReady("FIREMAW")
B["SA:[BWL][Ebonroc] Shadow Flame Ready"] = FlameReady("EBONROC")
B["SA:[BWL][Flamegor] Shadow Flame Ready"] = FlameReady("FLAMEGOR")

-- a Chromaggus breath being cast: its name and icon for two seconds
do
    local CAST = {
        WA_CHROMAGGUS_INCINERATE_START = { "Incinerate", 136130 },
        WA_CHROMAGGUS_CORROSIVE_START = { "Corrosive", 136007 },
        WA_CHROMAGGUS_FROST_BURN_START = { "Frost Burn", 135836 },
        WA_CHROMAGGUS_IGNITE_FLESH_START = { "Ignite Flesh", 135805 },
        WA_CHROMAGGUS_TIME_LAPSE_START = { "Time Lapse", 135744 },
    }
    B["SA:[BWL][Chromaggus] Breaths"] = {
        ["conditions.1.changes.3.value"] = Speech("Breath"),
        ["conditions.2.changes.3.value"] = Speech("Breath"),
        ["conditions.3.changes.3.value"] = Speech("Breath"),
        ["conditions.4.changes.3.value"] = Speech("Time Lapse"),
        ["conditions.5.changes.3.value"] = Speech("Breath"),
        ["init"] = function() end,
        ["triggers.1.trigger"] = function(env, allstates, event)
            if event == "OPTIONS" then
                K.Put(allstates, "", K.Timed(2, { breath = "Incinerate", icon = 135805 }))
                return true
            end
            local cast = CAST[event]
            if cast then
                K.Put(allstates, "", K.Timed(2, { breath = cast[1], icon = cast[2], autoHide = true }))
                return true
            end
        end,
    }
end

B["SA:[BWL][Nefarian] Improved BoP"] = {
    ["triggers.1.trigger"] = Pop{ key = "NEFARIAN_BOP", dur = 5, icon = 135964, samplePut = true, sampleTrue = true,
        sample = function() return K.Timed(5, { icon = 135964 }) end },
}

-- ============================================================
-- SPECIAL WARNINGS
-- ============================================================
B["SW:[BWL][Vael] Burning Adrenaline"] = {
    ["actions.start.custom"] = function(env) Say("Burning Adrenaline on " .. env.state.name) end,
    ["triggers.1.trigger"] = Pop{ event = "WA_VAEL_ADRENALINE_TARGET", dur = 3, icon = 132937,
        fill = function(st, count, _, name) st.name = name st.count = count end,
        sample = function() return { icon = 132937, count = math.random(1, 4), name = RM.WA.me, rooted = false } end },
}

local function WingBuffetSoon(boss)
    return {
        ["actions.start.custom"] = Speech("Knockback Soon"),
        ["logic"] = TanksHealersLead,
        ["triggers.1.icon"] = K.Always(135789),
        ["triggers.1.trigger"] = Heads{ key = boss .. "_WING_BUFFET", on = "WA_" .. boss .. "_WING_BUFFET_PREWARN", icon = 134316 },
    }
end
B["SW:[BWL][Firemaw] Wing Buffet PreWarn"] = WingBuffetSoon("FIREMAW")
B["SW:[BWL][Ebonroc] Wing Buffet PreWarn"] = WingBuffetSoon("EBONROC")
B["SW:[BWL][Flamegor] Wing Buffet PreWarn"] = WingBuffetSoon("FLAMEGOR")

B["SW:[BWL][Ebonroc] Shadow of Ebonroc"] = {
    ["triggers.1.trigger"] = Pop{ key = "EBONROC_SHADOW_OF_EBONROC", dur = 3, icon = 136160, fill = WithCountAndName, sample = MyNameCount(136160) },
}

-- Frenzy: for hunters (tranquilizing shot), the leader, healers and tanks
local function FrenzyFor(env, t)
    return (Me() == "Hunter" or Leader() or _G.FJI_HEALER or _G.FJI_TANK) and t[1]
end
B["SW:[BWL][Flamegor] Frenzy"] = {
    ["actions.start.custom"] = Speech("Frenzy"),
    ["logic"] = FrenzyFor,
    ["triggers.1.trigger"] = Pop{ key = "FLAMEGOR_FRENZY", dur = 3, icon = 132117, fill = WithCount, sample = RandomCount(132117) },
}

-- the next breath, five seconds out (one bar per breath slot); spoken by
-- name once the breath is known
do
    local BREATH_ICON = { INCINERATE = 136130, CORROSIVE = 136007, FROST_BURN = 135836, IGNITE_FLESH = 135805, TIME_LAPSE = 135744 }
    local SPOKEN = { INCINERATE = "Incinerate", CORROSIVE = "Corrosive Acid", FROST_BURN = "Frost Burn", IGNITE_FLESH = "Ignite Flesh", TIME_LAPSE = "Time Lapse" }
    B["SW:[BWL][Chromaggus] Breath PreWarn"] = {
        ["actions.start.custom"] = function(env)
            local breath = env.state and env.state.breath
            local said = SPOKEN[breath]
            Say(said and (said .. " Soon") or "Breath Soon")
        end,
        ["init"] = function() end,
        ["triggers.1.icon"] = K.Always(135789),
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "OPTIONS" then
                K.Put(allstates, "", K.Timed(5, { icon = 135805, count = math.random(1, 3) }))
                return true
            end
            local slot = event:match("^WA_(CHROMAGGUS_BREATH_.*)_PREWARN$")
            if slot then
                local secs, count = ...
                local breath
                for name in pairs(BREATH_ICON) do
                    if slot:find(name) then breath = name break end
                end
                K.Put(allstates, slot, Lasting(secs, { icon = breath and BREATH_ICON[breath] or 135805, count = count, breath = breath }))
                return true
            end
            if event == "WA_NUMEN_TIMER" then
                local key, secs = ...
                if key and key:find("CHROMAGGUS_BREATH") and (secs == 0 or secs == nil) then
                    for _, st in pairs(allstates) do
                        st.show = false
                        st.changed = true
                    end
                    return true
                end
            end
        end,
    }
end

B["SW:[BWL][Chromaggus] Frenzy"] = {
    ["actions.start.custom"] = Speech("Frenzy"),
    ["logic"] = FrenzyFor,
    ["triggers.1.trigger"] = Pop{ key = "CHROMAGGUS_FRENZY", dur = 3, icon = 132117, fill = WithCount, sample = MyNameCount(132117) },
}

-- mind control: who (the event carries GUID, then name)
B["SW:[BWL][Nefarian] Shadow Command"] = {
    ["actions.start.custom"] = function(env) Say("Mind Control on " .. env.state.name) end,
    ["triggers.1.trigger"] = Pop{ key = "NEFARIAN_SHADOW_COMMAND", dur = 3, icon = 136224,
        fill = function(st, _, _, _, name) st.name = name end,
        sample = function() return { icon = 136224, name = RM.WA.me } end },
}

B["SW:[BWL][Nefarian] Veil of Shadow"] = {
    ["conditions.1.changes.1.value"] = Speech("Decurse"),
    ["conditions.1.check.fn"] = function() return _G.FJI_HEAL or Leader() or Me() == "Druid" or Me() == "Mage" end,
    ["triggers.1.trigger"] = Pop{ key = "NEFARIAN_VEIL", dur = 3, icon = 136160, fill = WithCountAndName, sample = MyNameCount(136160) },
}

-- ============================================================
-- TEXTS
-- ============================================================
local function PriestPaladinOrLead() return Me() == "Priest" or Me() == "Paladin" or Leader() end
local function WhoGotIt(st, guid) st.name = guid end
B["T:[BWL][Trash] Mark of Detonation"] = {
    ["conditions.1.changes.1.value"] = Speech("Mark"),
    ["conditions.1.check.fn"] = PriestPaladinOrLead,
    ["triggers.1.trigger"] = Pop{ event = "WA_MARK_OF_DETONATION", dur = 3, icon = 135826, fill = WhoGotIt, sample = MyName(135826) },
}
B["T:[BWL][Trash] Flame Buffet"] = {
    ["conditions.1.changes.1.value"] = Speech("Buffet"),
    ["conditions.1.check.fn"] = PriestPaladinOrLead,
    ["triggers.1.trigger"] = Pop{ event = "WA_FLAME_BUFFET", dur = 3, icon = 135807, fill = WhoGotIt, sample = MyName(135807) },
}

-- your target is a spinner (Brood Power: Bronze); a new spinner makes
-- every listener look at the target again
B["T:[BWL][Trash] Brood Power: Bronze"] = {
    ["init"] = function(env) env.guids = {} end,
    ["triggers.1.trigger"] = function(env, allstates, event, guid)
        if event == "OPTIONS" then
            K.Put(allstates, "", { icon = 136022 })
            return true
        end
        if event == "WA_FJI_BWL_TRASH_SPINNER" then
            env.guids[guid] = true
            RM.Fire("PLAYER_TARGET_CHANGED")
            return false
        end
        if event == "PLAYER_TARGET_CHANGED" then
            if UnitExists("target") and env.guids[UnitGUID("target")] then
                K.Put(allstates, "", { icon = 136022 })
                return true
            end
            allstates[""] = { show = false, changed = true }
            return true
        end
    end,
}

local function PhaseTwo(icon)
    return { ["actions.start.custom"] = Speech("Phase 2"), ["triggers.1.icon"] = K.Always(icon), ["triggers.1.trigger"] = K.Always(true) }
end
B["T:[BWL][Razorgore] Phase"] = PhaseTwo(236469)
B["T:[BWL][Razorgore] War Stomp"] = {
    ["triggers.1.trigger"] = Pop{ key = "RAZORGORE_WAR_STOMP", dur = 3, icon = 132091, sample = function() return { icon = 132091 } end },
}
B["T:[BWL][Broodlord] Mortal Strike"] = {
    ["triggers.1.trigger"] = Pop{ key = "BROODLORD_MORTAL_STRIKE", dur = 3, icon = 132355, fill = WithCountAndName, sample = MyNameCount(132355) },
}
local function Knockback(boss)
    return {
        ["actions.start.custom"] = Speech("Knockback"),
        ["triggers.1.icon"] = K.Always(135789),
        ["triggers.1.trigger"] = Pop{ key = boss .. "_WING_BUFFET", dur = 3, icon = 134316, fill = WithCount, sample = RandomCount(134316) },
    }
end
B["T:[BWL][Firemaw] Wing Buffet"] = Knockback("FIREMAW")
B["T:[BWL][Ebonroc] Wing Buffet"] = Knockback("EBONROC")
B["T:[BWL][Flamegor] Wing Buffet"] = Knockback("FLAMEGOR")

B["T:[BWL][Chromaggus] Elemental Vulnerability"] = {
    ["init"] = function() end,
    ["logic"] = ForClassesOrLeads(ALL_CLASSES, true),
    ["triggers.1.trigger"] = function(env, allstates, event, name, icon)
        if event == "OPTIONS" then
            K.Put(allstates, "", K.Timed(3, { vulnerability = "Fire Vulnerable", icon = 135812 }))
            return true
        end
        if event == "WA_CHROM_VULN" then
            if not name then return false end
            K.Put(allstates, "", K.Timed(3, { vulnerability = name .. " Vulnerable", icon = icon, autoHide = true }))
            return true
        end
    end,
}
B["T:[BWL][Nefarian] Phase"] = PhaseTwo(134154)

-- the class just called, in its colour, for three seconds; each class's
-- condition speaks its own call
do
    local map = {
        ["init"] = function() end,
        ["triggers.1.icon"] = K.Always(135789),
        ["triggers.1.trigger"] = function(env, allstates, event, key, secs, count, class)
            if event == "OPTIONS" then
                allstates[""] = { show = true, icon = 626004, count = math.random(1, 3), class = "|cFFFFFFFFPriest|r" }
                return true
            end
            if event == "WA_NUMEN_TIMER" and key == "NEFARIAN_CLASS_CALL" and secs == 0 then
                local coloured, icon = ClassLook(class)
                K.Put(allstates, "", K.Timed(3, { icon = icon, autoHide = true, count = count, class = coloured }))
                return true
            end
        end,
    }
    for i, c in ipairs(CLASSES) do
        map["conditions." .. i .. ".changes.1.value"] = Speech(c[1] .. " Call")
    end
    B["T:[BWL][Nefarian] Class Call"] = map
end

-- ============================================================
-- CO-TANK ICONS AND HELPERS
-- ============================================================
local function ForTanks(env, t) return t[1] and _G.FJI_TANK end
B["CTI:[BWL][Vael] Burning Adrenaline"] = { ["logic"] = ForTanks }
B["CTI:[BWL][Broodlord] Mortal Strike"] = { ["logic"] = ForTanks }

-- Chromaggus' vulnerability as text, for the classes that care
B["[BWL][Chromaggus] Vulnerability Text"] = {
    ["init"] = function() end,
    ["logic"] = ForClassesOrLeads(K.Set({ "Druid", "Hunter", "Mage", "Priest", "Rogue", "Shaman", "Warlock" })),
    ["triggers.1.trigger"] = function(env, allstates, event, name, icon)
        if event == "OPTIONS" then
            K.Put(allstates, "", K.Timed(17, { vulnerability = "Fire", icon = 135812 }))
            return true
        end
        if event == "WA_CHROM_VULN" then
            K.Put(allstates, "", K.Timed(17, { vulnerability = name, icon = icon }))
            return true
        end
    end,
}

RM.Own.Finish("BWL", B)
