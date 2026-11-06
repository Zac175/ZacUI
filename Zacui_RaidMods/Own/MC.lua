-- MC - ZacUI's own Molten Core boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Settings in Own\MC_Data.lua.
--
-- Most pieces are facts handed to the kit (RM_OwnKit.lua): one controller
-- per boss ability puts its countdown on the bus, and the timer bars,
-- flashes, heads-up bars and speech listen for it. The one-offs - the
-- Majordomo health pool, the Ragnaros submerge cycle - are written out
-- below.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
if not (RM and RM.Own and RM.Own.on) then return end
local K = RM.Own.Kit

local B = {}

-- the chat prefix the raid's leader tools print with
local SAY = "|cff0070ddRaid Mods|r |cffff8000MC|r: "
-- who a piece speaks to
local decursers = K.IsClass({ "MAGE", "DRUID" })
local decursersAndLead = K.IsClass({ "MAGE", "DRUID" }, true)
local dispellersAndLead = K.IsClass({ "PRIEST", "PALADIN" }, true)
local hunters = K.IsClass({ "HUNTER" })
local rangedOrLead = function() return _G.FJI_RANGED or UnitIsGroupLeader("player") end

-- who sees a raid-frame dispel glow
local magicDispellers = K.LeaderOrClass("PALADIN", "PRIEST", "WARLOCK")
local curseRemovers = K.LeaderOrClass("DRUID", "MAGE")

-- the logic most raid-frame pieces share: shown to the leader, assists
-- and healers
local function ForHealersAndLead(env, t)
    return t[1] and (UnitIsGroupLeader("player") or _G.FJI_HEALER or UnitIsGroupAssistant("player"))
end
-- and the Shazzrah reflect pieces: the leader and ranged
local function ForRangedAndLead(env, t)
    return (UnitIsGroupLeader("player") or _G.FJI_RANGED) and t[1]
end

-- a progress bar's preview: dur seconds
local function BarSample(dur)
    return function() return K.Timed(dur, { changed = true, autoHide = true }) end
end

-- ============================================================
-- RAID LEADER: MARKING
-- ============================================================
B["[RAIDLEAD][MC-Classic][Garr] AutoMark Firesworn Adds"] = K.Merge(
    K.AutoMark{ npcs = { ["12099"] = "enable" }, what = "Firesworn", say = SAY, other = false },
    { ["actions.start.custom"] = K.MarkOnShow() })

-- Living Bomb: mark whoever has it (an aura trigger finds them), and give
-- the mark back when it ends
B["[RAIDLEAD][MC-Classic][Baron Geddon] AutoMark Living Bomb"] = {
    ["init"] = K.MarkPool(),
    ["actions.start.custom"] = K.MarkOnShow{ say = SAY },
    ["actions.finish.custom"] = K.MarkClear(),
}

B["[RAIDLEAD][MC-Classic][Sulfuron] AutoMark Flamewaker Adds"] =
    K.AutoMark{ npcs = { ["11662"] = "enable" }, what = "Add", say = SAY, other = false }

-- Majordomo: the elites and the healers each have their own switch and
-- their own four marks (firstMark..fourthMark, firstMarkHealer..
-- fourthMarkHealer); either switch on is enough. Shift over an unmarked
-- add gives it the next free mark of its kind, in the order set.
do
    local ORDER = { "first", "second", "third", "fourth" }
    local KIND = { ["11664"] = { option = "enable", tail = "Mark" }, ["11663"] = { option = "enableHealer", tail = "MarkHealer" } }
    local function Pools(env)
        local opt = env.config.group.option
        env.pools = {}
        env.originalMarks = {}
        -- each kind: its marks in order, and which of them are still free
        for _, kind in pairs(KIND) do
            local pool = { order = {}, free = {} }
            if opt[kind.option] then
                for _, n in ipairs(ORDER) do
                    local mark = opt[n .. kind.tail]
                    if mark and mark ~= 9 and pool.free[mark] == nil then
                        pool.order[#pool.order + 1] = mark
                        pool.free[mark] = true
                    end
                end
            end
            env.pools[kind.option] = pool
        end
    end
    local function Next(env, unit, kind)
        local pool = env.pools[kind.option]
        for _, mark in ipairs(pool.order) do
            if pool.free[mark] then
                SetRaidTarget(unit, mark)
                -- a mark in both lists is used up for both
                for _, other in pairs(env.pools) do
                    if other.free[mark] then other.free[mark] = false end
                end
                print(SAY .. "AutoMarked Add with |TInterface/TargetingFrame/UI-RaidTargetingIcon_" .. mark .. ":14:14|t")
                return
            end
        end
    end
    B["[RAIDLEAD][MC-Classic][Majordomo] AutoMark Adds"] = {
        ["init"] = Pools,
        ["triggers.1.trigger"] = function(env, event)
            if event ~= "UPDATE_MOUSEOVER_UNIT" then return end
            local unit = "mouseover"
            local opt = env.config.group.option
            if not (opt.enable or opt.enableHealer) then return false end
            if not UnitExists(unit) then return false end
            if UnitIsDead(unit) then return false end
            local kind = KIND[K.NpcId(UnitGUID(unit))]
            if not (kind and opt[kind.option]) then return end
            if GetRaidTargetIndex(unit) then return false end
            if not IsShiftKeyDown() then
                -- remind at most every three minutes
                if not env.lastReminder or env.lastReminder < GetTime() - 180 then
                    print(SAY .. "Hold LSHIFT to AutoMark")
                    env.lastReminder = GetTime()
                end
                return false
            end
            Next(env, unit, kind)
            return true
        end,
    }
end

B["[RAIDLEAD][MC-Classic][Ragnaros] AutoMark Adds"] =
    K.AutoMark{ npcs = { ["12143"] = "enable" }, what = "Son", say = SAY, other = false }

-- ============================================================
-- TIMER BARS
-- ============================================================
-- no MC boss has a berserk timer
B["BT:[MC-Classic][All] Berserk Timer"] = K.Berserk{ keys = {} }

B["BTE:[MC-Classic][All] Emphasized Timers"] = K.Emphasized()

-- colours are 0-255 RGB plus alpha
B["BT:[MC-Classic][All] Boss Timers"] = K.TimerBars{ bars = {
    LUCIFRON_CURSE = { name = "Lucifron's Curse", icon = 136123, color = { 255, 182, 193, 1 } },
    LUCIFRON_DOOM = { name = "Impending Doom", icon = 136179, color = { 135, 206, 250, 1 } },
    MAGMADAR_PANIC = { name = "Panic", icon = 136147, color = { 255, 182, 193, 1 } },
    MAGMADAR_FRENZY = { name = "Frenzy", icon = 132117, color = { 255, 165, 0, 1 } },
    GEHENNAS_CURSE = { name = "Gehennas' Curse", icon = 136160, color = { 255, 182, 193, 1 } },
    GARR_PULSE = { name = "Anti-Magic Pulse", icon = 135894, color = { 173, 216, 230, 1 } },
    GEDDON_INFERNO = { name = "Inferno", icon = 135818, color = { 255, 0, 0, 1 } },
    GEDDON_IGNITE_MANA = { name = "Ignite Mana", icon = 135818, color = { 173, 216, 230, 1 } },
    GEDDON_LIVING_BOMB = { name = "Living Bomb", icon = 132863, color = { 255, 165, 0, 1 } },
    SHAZZRAH_CURSE = { name = "Shazzrah's Curse", icon = 136121, color = { 255, 182, 193, 1 } },
    SHAZZRAH_COUNTERSPELL = { name = "Counterspell", icon = 135856, color = { 173, 216, 230, 1 } },
    SHAZZRAH_BLINK = { name = "Blink", icon = 135743, color = { 0, 0, 255, 1 } },
    SHAZZRAH_REFLECT_MAGIC = { name = "Reflect Magic", icon = 132361, color = { 173, 216, 230, 1 } },
    GOLEMAGG_EARTHQUAKE = { name = "Earthquake", icon = 136025, color = { 210, 180, 140, 1 } },
    SULFURON_HAND_OF_RAG = { name = "Hand of Ragnaros", icon = 135807, color = { 255, 255, 224, 1 } },
    MAJORDOMO_DAMAGE_SHIELD = { name = "Damage Shield", icon = 136121, color = { 128, 0, 128, 1 } },
    MAJORDOMO_TELEPORT = { name = "Teleport", icon = 135736, color = { 0, 0, 255, 1 } },
    RAGNAROS_WRATH_OF_RAGNAROS = { name = "Wrath of Ragnaros", icon = 135827, color = { 255, 99, 71, 1 } },
} }

-- ============================================================
-- MAJORDOMO: ONE HEALTH BAR FOR ALL EIGHT ADDS
-- ============================================================
-- Counted down from the combat log: every hit on an elite or a healer
-- comes off one shared pool.
do
    local ADDS = K.Set{ "11664", "11663" }
    -- (every hit in the fight comes through here: a plain text search
    -- turns the rest away before the GUID is taken apart)
    local function IsAdd(guid)
        return guid:find("%-1166[34]%-") ~= nil and ADDS[K.NpcId(guid)] == true
    end
    local POOL = 804800
    -- where the amount sits in the values after destRaidFlags
    local AMOUNT_AT = { SWING_DAMAGE = 1, RANGE_DAMAGE = 4, SPELL_DAMAGE = 4, SPELL_PERIODIC_DAMAGE = 4, ENVIRONMENTAL_DAMAGE = 2 }

    local function Hit(env, allstates, _, subEvent, _, _, _, _, _, destGUID, _, _, _, ...)
        if subEvent == "UNIT_DIED" then
            local st = allstates[""]
            if IsAdd(destGUID) and st then
                st.adds = st.adds - 1
                st.changed = true
            end
            return true
        end
        if not IsAdd(destGUID) then return false end
        local at = AMOUNT_AT[subEvent]
        if not at then return false end
        local amount = (select(at, ...))
        local st = allstates[""] or K.Put(allstates, "", { name = "HP", progressType = "static", value = POOL, total = POOL })
        env.hpLeft = env.hpLeft - amount
        st.value = env.hpLeft
        st.show = env.hpLeft > 0
        st.changed = true
        return true
    end

    B["BS:[MC-Classic][Majordomo] Combined HP Bar"] = {
        ["init"] = function(env) env.hpLeft = POOL end,
        ["text"] = function(env)
            local pct
            local st = env.state
            if st and st.value and st.total then pct = Round(st.value / st.total * 100) end
            return pct
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "COMBAT_LOG_EVENT_UNFILTERED" then
                return Hit(env, allstates, ...)
            elseif event == "ENCOUNTER_START" then
                env.hpLeft = POOL
                K.Put(allstates, "", { name = "Combined HP", progressType = "static", value = POOL, total = POOL, adds = 8 })
                return true
            elseif event == "OPTIONS" then
                if not RM.WA.IsOptionsOpen() then return false end
                local value = math.random(1, 1000000)
                K.Put(allstates, "", { name = "HP", progressType = "static", value = value, total = POOL, adds = math.random(1, 8) })
                return true
            end
        end,
    }
end

-- ============================================================
-- SHAZZRAH: DECURSE LEADERBOARD
-- ============================================================
-- Counts every dispel in the raid and posts the table to raid chat when
-- the Baron Geddon fight ends.
do
    local function Short(n)
        local units, i = { "", "K", "M" }, 1
        while n >= 1000 and i < #units do
            n = math.floor(n / 1000)
            i = i + 1
        end
        return n .. units[i]
    end

    local function Post(tally)
        if not tally or next(tally) == nil then return end
        local rows = {}
        for who, n in pairs(tally) do rows[#rows + 1] = { who = who, n = n } end
        table.sort(rows, function(a, b) return a.n > b.n end)
        SendChatMessage("Decurse Leaderboard:", "RAID")
        for _, row in ipairs(rows) do
            SendChatMessage(row.who .. " - " .. Short(row.n) .. " " .. (row.n == 1 and "Decurse" or "Decurses"), "RAID")
        end
    end

    B["CH:[MC-Classic][Shazzrah] Decurse Reporter"] = {
        ["init"] = function(env) env.amount = {} end,
        ["triggers.1.trigger"] = function(env, event, encounterId, subEvent, _, _, sourceName)
            if event == "ENCOUNTER_END" and encounterId == 668 then
                Post(env.amount)
                env.amount = {}
                return true
            end
            if subEvent == "SPELL_DISPEL" then
                env.amount[sourceName] = (env.amount[sourceName] or 0) + 1
                return true
            end
        end,
    }
end

-- ============================================================
-- CONTROLLERS - every boss ability's countdown
-- ============================================================
B["CT:[MC-Classic][Lucifron] Doom"] = K.Controller{ key = "LUCIFRON_DOOM", spell = 19702, first = 7, every = 20 }
-- Dominate Mind only says when the cast starts; the flashes take it from there
B["CT:[MC-Classic][Lucifron] Dominate Mind"] = K.Controller{ key = "LUCIFRON_DOMINATE_MIND", spell = 20604, sub = "SPELL_CAST_START", pull = false, count = false }
B["CT:[MC-Classic][Lucifron] Curse"] = K.Controller{ key = "LUCIFRON_CURSE", spell = 19703, first = 12, every = 20.5 }
-- Conflagration has no timer: it says who caught it
B["CT:[MC-Classic][Magmadar] Conflagration"] = K.Controller{ key = "MAGMADAR_CONFLAG", spell = 19428, sub = "SPELL_AURA_APPLIED", count = false, guid = true }
B["CT:[MC-Classic][Magmadar] Frenzy"] = K.Controller{ key = "MAGMADAR_FRENZY", spell = 19451, sub = "SPELL_AURA_APPLIED", first = 9, every = 15 }
B["CT:[MC-Classic][Magmadar] Panic"] = K.Controller{ key = "MAGMADAR_PANIC", spell = 19408, first = 9, every = 30 }
B["CT:[MC-Classic][Gehennas] Rain of Fire"] = K.Controller{ key = "GEHENNAS_RAIN_OF_FIRE", spell = 19717, first = 6, every = 6 }
B["CT:[MC-Classic][Gehennas] Gehennas' Curse"] = K.Controller{ key = "GEHENNAS_CURSE", spell = 19716, first = 6, every = 26 }
B["CT:[MC-Classic][Garr] Antimagic Pulse"] = K.Controller{ key = "GARR_PULSE", spell = 19492, first = 10, every = 15.7 }
B["CT:[MC-Classic][Baron Geddon] Ignite Mana"] = K.Controller{ key = "GEDDON_IGNITE_MANA", spell = 19659, first = 30, every = 30 }
B["CT:[MC-Classic][Baron Geddon] Inferno"] = K.Controller{ key = "GEDDON_INFERNO", spell = 19695, first = 7, every = 21 }
B["CT:[MC-Classic][Baron Geddon] Living Bomb"] = K.Controller{ key = "GEDDON_LIVING_BOMB", spell = 20475, first = 11, every = 13.3 }
B["CT:[MC-Classic][Shazzrah] Blink"] = K.Controller{ key = "SHAZZRAH_BLINK", spell = 23138, first = 30, every = 31.3 }
B["CT:[MC-Classic][Shazzrah] Counterspell"] = K.Controller{ key = "SHAZZRAH_COUNTERSPELL", spell = 19715, first = 9.6, every = 10, prewarn = 2.5 }
-- Reflect Magic is Season of Discovery only; Era Shazzrah never casts it.
-- With no spell to watch it runs its first countdown and heads-up on the
-- pull and nothing after (left that way on purpose)
B["CT:[MC-Classic][Shazzrah] Reflect Magic"] = K.Controller{ key = "SHAZZRAH_REFLECT_MAGIC", spell = nil, first = 18, every = 20, prewarn = 3 }
B["CT:[MC-Classic][Shazzrah] Shazzrah's Curse"] = K.Controller{ key = "SHAZZRAH_CURSE", spell = 19713, first = 6, every = 22 }
B["CT:[MC-Classic][Sulfuron] Shadow Word: Pain"] = K.Controller{ key = "SULFURON_SHADOW_WORD_PAIN", spell = 19776, first = 6, every = 22 }
B["CT:[MC-Classic][Sulfuron] Hand of Ragnaros"] = K.Controller{ key = "SULFURON_HAND_OF_RAG", spell = 19780, first = 6, every = 16 }
B["CT:[MC-Classic][Golemagg] Quake"] = K.Controller{ key = "GOLEMAGG_EARTHQUAKE", spell = 19798, first = 26, every = 14 }
B["CT:[MC-Classic][Golemagg] Pyroblast"] = K.Controller{ key = "GOLEMAGG_PYROBLAST", spell = 20228, first = 6, every = 16 }
B["CT:[MC-Classic][Golemagg] Magma Splash"] = K.Controller{ key = "GOLEMAGG_MAGMA_SPLASH", spell = 13880, first = 6, every = 16 }
-- one timer for both shields; which one went up is its own bus event
B["CT:[MC-Classic][Majordomo] Damage Shield"] = K.Controller{ key = "MAJORDOMO_DAMAGE_SHIELD", spells = { 21075, 20619 }, first = 27.8, every = 30.3,
    tell = { [21075] = "WA_MAJORDOMO_DAMAGE_SHIELD", [20619] = "WA_MAJORDOMO_MAGIC_REFLECTION" } }
B["CT:[MC-Classic][Majordomo] Teleport"] = K.Controller{ key = "MAJORDOMO_TELEPORT", spell = 20534, first = 19.4, every = 25 }
B["CT:[MC-Classic][Ragnaros] Elemental Fire"] = K.Controller{ key = "RAGNAROS_ELEMENTAL_FIRE", spell = 20564, sub = "SPELL_AURA_APPLIED", first = 2, every = 25, guid = true }
-- Wrath pauses while Ragnaros is under and starts over when he comes up
B["CT:[MC-Classic][Ragnaros] Wrath of Ragnaros"] = K.Controller{ key = "RAGNAROS_WRATH_OF_RAGNAROS", spell = 20566, first = 26.7, every = 25, prewarn = 5,
    pullOn = { "ENCOUNTER_START", "WA_RAGNAROS_EMERGE" }, stopOn = { "WA_RAGNAROS_SUBMERGE" }, recount = true, finish = false }

-- ============================================================
-- FIRE RESISTANCE
-- ============================================================
B["FR:[MC-Classic] Fire Resistance Aura"] = { ["logic"] = K.OptionAnd("frHelper") }
B["FR:[MC-Classic] Fire Resistance Totem"] = { ["logic"] = K.OptionAnd("frHelper") }
B["FR:[MC-Classic] Fire Resistance Text"] = {
    ["logic"] = K.OptionAnd("frHelper"),
    ["triggers.1.trigger"] = function(env, allstates, event)
        if event == "UNIT_RESISTANCES" or event == "OPTIONS" or event == "STATUS" then
            K.Put(allstates, "", { progressType = "static", fr = select(2, UnitResistance("player", 2)) })
            return true
        end
    end,
}

-- raid leader types !fr: everyone posts theirs, staggered by the value so
-- the chat comes out in order
B["[MC-Classic] Fire Resistance Check"] = {
    ["triggers.1.trigger"] = function(env, event, msg)
        if event == "CHAT_MSG_RAID_LEADER" and msg == "!fr" then return true end
    end,
    ["actions.start.custom"] = function()
        local fr = select(2, UnitResistance("player", 2))
        C_Timer.After(fr / 100, function()
            SendChatMessage("My Fire Resistance is: " .. fr, "RAID")
        end)
    end,
}

-- ============================================================
-- ICONS
-- ============================================================
B["A:[MC-Classic][Trash] Ancient Dread"] = { ["conditions.1.check.fn"] = K.Flag("FJI_MELEE", "FJI_TANK") }
B["A:[MC-Classic][Lucifron] Lucifron's Curse"] = {
    ["logic"] = function(env, t) return t[1] end,
}
-- each stack of Magma Splash costs 250 armor
B["A:[MC-Classic][Golemagg] Magma Splash"] = {
    ["text"] = function(env, expirationTime, duration, progress, formatedDuration, name, icon, stacks)
        return (tonumber(stacks) or 0) * 250
    end,
}

-- ============================================================
-- MISC
-- ============================================================
B["[MC-Classic] Disable Raid Emotes"] = K.MuteBossEmotes()

-- ============================================================
-- NAMEPLATES
-- ============================================================
B["N:[MC-Classic][Trash] Lava Spawn CD"] = K.PlateCooldown{ npcs = { "11668" }, spell = 19392, sub = "SPELL_SUMMON", cd = 18 }
B["N:[MC-Classic][Trash] Cone of Fire CD"] = K.PlateCooldown{ npcs = { "11667" }, spell = 19630, cd = 13 }
B["N:[MC-Classic][Trash] Pyroclast Barrage CD"] = K.PlateCooldown{ npcs = { "12076" }, spell = 19641, cd = 10 }
B["N:[MC-Classic][Trash] Surge CD"] = K.PlateCooldown{ npcs = { "12101" }, spell = 19196, cd = 8 }
-- the icon stays up at 0 here (it turns grey) rather than going away
B["N:[MC-Classic][Lucifron] Dominate Mind CD"] = K.PlateCooldown{ npcs = { "12119", "228441" }, spell = 20604, cd = 8, keep = true }

-- Core Hounds get back up unless the pack dies together: a hound that
-- drops to 100 health or less starts its 16 second revive clock.
do
    local HOUND, REVIVE = "11671", 16
    local fields = { autoHide = true }
    B["N:[MC-Classic][Trash] Core Hound Revive CD"] = {
        ["init"] = function(env)
            env.seen = {}
            env.ends = {}
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, unit)
            if event == "UNIT_HEALTH" then
                local guid = UnitGUID(unit)
                if UnitHealth(unit) <= 100 then
                    if not env.ends[guid] and K.NpcId(guid) == HOUND then
                        if K.PlateStart(env, allstates, guid, REVIVE, fields) then return true end
                    end
                elseif allstates[guid] then
                    -- back on its feet (or healed): clock off
                    K.Drop(allstates, guid)
                    env.ends[guid] = nil
                    env.seen[guid] = nil
                    return true
                end
            end
            return K.PlateFollow(env, allstates, event, unit, fields)
        end,
    }
end

-- Dark Mending on the Flamewaker Priests: a 6 second cast clock on each
-- priest's plate from the pull.
do
    local MENDING, EVERY, CAST = 19775, 6, 2
    local TRACKED = K.Set{ "11662" }
    local function Restart(st, ends)
        st.duration = ends - GetTime()
        st.expirationTime = ends
        st.status = "CD"
        st.changed = true
    end
    B["N:[MC-Classic][Sulfuorn] Dark Mending"] = {
        ["init"] = function(env) env.nextCasts = {} end,
        ["triggers.1.trigger"] = function(env, allstates, event, unit, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId, _, _, extraSpellId)
            if event == "OPTIONS" then
                K.Put(allstates, "", { progressType = "timed", status = "CD" })
                return true
            end
            if event == "ENCOUNTER_START" then
                for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                    local u = plate.UnitFrame.displayedUnit
                    local guid = UnitGUID(u)
                    if guid and TRACKED[K.NpcId(guid)] then
                        env.nextCasts[guid] = GetTime() + EVERY
                        K.Put(allstates, guid, K.Timed(EVERY, { expirationTime = env.nextCasts[guid], unit = u, status = "CD" }))
                    end
                end
                return true
            end
            if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
                local guid = UnitGUID(unit)
                if guid and TRACKED[K.NpcId(guid)] then
                    if event == "NAME_PLATE_UNIT_REMOVED" then
                        K.Drop(allstates, guid)
                    elseif env.nextCasts[guid] then
                        local left = env.nextCasts[guid] - GetTime()
                        K.Put(allstates, guid, { progressType = "timed", duration = left > 0 and left or 0,
                            expirationTime = env.nextCasts[guid], unit = unit, status = left > 0 and "CD" or "Casting" })
                    end
                    return true
                end
            end
            if subEvent == "SPELL_CAST_START" and spellId == MENDING then
                env.nextCasts[sourceGUID] = GetTime() + EVERY
                local st = allstates[sourceGUID]
                if st then
                    st.duration = CAST
                    st.expirationTime = CAST + GetTime()
                    st.status = "Casting"
                    st.changed = true
                    return true
                end
            elseif subEvent == "SPELL_CAST_SUCCESS" and spellId == MENDING then
                if allstates[sourceGUID] then
                    Restart(allstates[sourceGUID], env.nextCasts[sourceGUID])
                    return true
                end
            elseif subEvent == "SPELL_INTERRUPT" and extraSpellId == MENDING then
                if allstates[destGUID] then
                    Restart(allstates[destGUID], env.nextCasts[destGUID])
                    return true
                end
            end
        end,
    }
end

B["N:[MC-Classic][Sulfuron] Inspire"] = K.PlateBuff{ npcs = { "12098", "11662" }, spells = { 19779 }, dur = 10 }
-- both of Majordomo's shields, each with its own icon
B["N:[MC-Classic][Majordomo] Damage Shield"] = K.PlateBuff{ npcs = { "11664", "11663" }, spells = { 21075, 20619 }, dur = 10, spellIcon = true }

-- ============================================================
-- PROGRESS BARS
-- ============================================================
-- Douse (Aqual Quintessence) on a rune
B["PC:[MC-Classic][ALL] Douse Bar"] = K.Merge(K.CastBar{ spell = 21358, dur = 2 }, { ["text"] = K.Field("addColour") })

B["PC:[MC-Classic][Trash] Fire Blossom"] = {
    ["init"] = function(env) env.blossom = 19636 end,
    ["text"] = K.Field("addColour"),
    ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellId)
        if subEvent == "SPELL_AURA_APPLIED" and spellId == 19636 then
            K.Put(allstates, sourceGUID, K.Timed(6, { autoHide = true }))
            return true
        elseif subEvent == "UNIT_DIED" then
            return K.Drop(allstates, destGUID)
        end
    end,
}

B["PC:[MC-Classic][Lucifron] Dominate Mind"] = K.Merge(
    K.Flash{ key = "LUCIFRON_DOMINATE_MIND", dur = 2, sample = BarSample(2), sampleShows = true },
    { ["text"] = K.Field("addColour") })
B["PC:[MC-Classic][Baron Geddon] Inferno"] = K.Flash{ key = "GEDDON_INFERNO", dur = 8, sample = BarSample(8), sampleShows = true }
-- Reflect Magic goes up a second after the cast: the "active" bar follows then
B["PC:[MC-Classic][Shazzrah] Reflect Magic"] = K.Merge(
    K.Flash{ key = "SHAZZRAH_REFLECT_MAGIC", dur = 1, sample = BarSample(2), sampleShows = true,
        also = function() C_Timer.After(1, function() RM.Fire("WA_SHAZZRAH_REFLECT") end) end },
    { ["text"] = K.Field("addColour"), ["logic"] = ForRangedAndLead })
B["PC:[MC-Classic][Shazzrah] Reflect Magic Active"] = K.Merge(
    K.Flash{ event = "WA_SHAZZRAH_REFLECT", dur = 5, sample = BarSample(2), sampleShows = true },
    { ["logic"] = ForRangedAndLead })

-- Ragnaros' entrance: 83 seconds from Majordomo's speech (shared with the
-- raid so latecomers see it too), 10 from the summon.
do
    local PULL_LINE = {
        enUS = "Impudent whelps! You've rushed headlong to your own deaths! See now, the master stirs!",
        frFR = "Impudents imbéciles ! Vous vous êtes précipités vers votre propre mort !",
        deDE = "Unverschämte Welpen! Ihr seid sehenden Auges dem Tod in die Arme gelaufen!",
        esES = "¡Crías imprudentes! ¡Os habéis precipitado hasta vuestra propia muerte!",
        koKR = "건방진 젖먹이! 죽고 싶어 안달이구나!",
        ruRU = "Нахальные щенки! Вы сами обрекли себя на смерть!",
        zhCN = "你这个莽撞的家伙!",
        zhTW = "你這個莽撞的傢伙!你簡直是自尋死路!",
    }
    local function Countdown(allstates, ends)
        _G.RagTimer = ends
        K.Put(allstates, "", { progressType = "timed", duration = ends - GetTime(), expirationTime = ends, autoHide = true })
        return true
    end
    B["PC:[MC-Classic][Ragnaros] RP Timer"] = {
        ["init"] = function(env)
            env.currentLocale = { ragPull = PULL_LINE[GetLocale()] or PULL_LINE.enUS }
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, msg, subEvent, _, _, _, _, _, destGUID, _, _, _, spellId)
            if event == "OPTIONS" then
                K.Put(allstates, "", K.Timed(60, { autoHide = true }))
                return true
            end
            if event == "CHAT_MSG_MONSTER_YELL" then
                if msg and msg:find(env.currentLocale.ragPull) then
                    WA_SYNC_RESULT = (_G.SyncEvents or function() end)("RAID", nil, "WA_RAGNAROS_RP_TIMER")
                end
            elseif event == "WA_RAGNAROS_RP_TIMER" then
                return Countdown(allstates, GetTime() + 83)
            elseif event == "STATUS" and _G.RagTimer and _G.RagTimer - GetTime() > 0 then
                return Countdown(allstates, _G.RagTimer)
            end
            if spellId ~= 19773 then return false end
            if subEvent == "SPELL_CAST_SUCCESS" then return Countdown(allstates, GetTime() + 10) end
        end,
    }
end

-- Ragnaros: three minutes up, then he submerges for ninety seconds or
-- until all eight Sons of Flame are dead. Fires WA_RAGNAROS_SUBMERGE /
-- WA_RAGNAROS_EMERGE for the Wrath timer.
do
    local SUBMERGE_LINE = {
        enUS = "COME FORTH, MY SERVANTS!",
        frFR = "VENEZ, MES SERVITEURS !",
        deDE = "KOMMT HERBEI, MEINE DIENER!",
        esES = "¡AVANZAD, MIS SIRVIENTES!",
        koKR = "나의 종들아!",
        ruRU = "ПРИДИТЕ, МОИ СЛУГИ!",
        zhCN = "出现吧，我的奴仆!",
        zhTW = "出現吧，我的奴僕!",
    }
    local SON, SONS, UP, UNDER = "12143", 8, 180, 90
    local function Phase(allstates, dur, status)
        K.Put(allstates, "", K.Timed(dur, { autoHide = true, status = status }))
        return true
    end
    B["PC:[MC-Classic][Ragnaros] Submerge Timer"] = {
        ["init"] = function(env)
            env.currentLocale = { ragSubmerge = SUBMERGE_LINE[GetLocale()] or SUBMERGE_LINE.enUS }
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, msg, subEvent, _, _, _, _, _, destGUID)
            if event == "OPTIONS" then
                K.Put(allstates, "", K.Timed(6, { autoHide = true }))
                return true
            end
            if event == "ENCOUNTER_START" then
                env.addsLeft = SONS
                return Phase(allstates, UP, "Emerged")
            elseif event == "CHAT_MSG_MONSTER_YELL" and msg and msg:find(env.currentLocale.ragSubmerge) then
                RM.Fire("WA_RAGNAROS_SUBMERGE")
                return Phase(allstates, UNDER, "Submerged")
            end
            if subEvent == "UNIT_DIED" and K.NpcId(destGUID) == SON then
                env.addsLeft = env.addsLeft - 1
                if env.addsLeft == 0 then
                    RM.Fire("WA_RAGNAROS_EMERGE")
                    return Phase(allstates, UP, "Emerged")
                end
            end
        end,
    }
end

-- ============================================================
-- REMINDERS
-- ============================================================
-- after a boss with a rune: douse it
do
    local RUNE_BOSSES = K.Set{ 664, 665, 666, 667, 670, 669 }
    B["R:[MC-Classic][ALL] Douse Reminder"] = {
        ["init"] = function() end,
        ["triggers.1.trigger"] = function(env, allstates, event, encounterId, _, _, _, success)
            if event == "ENCOUNTER_END" and RUNE_BOSSES[encounterId] and success == 1 then
                K.Put(allstates, "", K.Timed(5, { icon = 236279, autoHide = true }))
                return true
            end
        end,
    }
end

-- on the Hands of the Enemy quest: a reminder to loot this boss's hand
do
    local QUEST = 6824
    local DROPS = {
        [663] = { icon = 132960, name = "Lucifron's" },
        [665] = { icon = 135817, name = "Gehennas's" },
        [667] = { icon = 132953, name = "Shazzrah's" },
        [669] = { icon = 132937, name = "Sulfuron's" },
    }
    B["R:[MC-Classic][ALL] Hand of Ragnaros"] = {
        ["init"] = function() end,
        ["triggers.1.trigger"] = function(env, allstates, event, encounterId, _, _, _, success)
            if event == "OPTIONS" then
                K.Put(allstates, "", K.Timed(5, { icon = 132960, autoHide = true, name = "Lucifron's" }))
                return true
            end
            if event ~= "ENCOUNTER_END" then return end
            if not C_QuestLog.IsOnQuest(QUEST) then return false end
            local drop = DROPS[encounterId]
            if drop and success == 1 then
                K.Put(allstates, "", K.Timed(5, { icon = drop.icon, autoHide = true, name = drop.name }))
                return true
            end
        end,
    }
end

-- warlock: missing Detect Invisibility or Unending Breath before Garr's trash
B["R:[MC-Classic][Garr][Warlock] Trash Buff Reminder"] = {
    ["logic"] = function(env, t) return t[3] and (t[1] or t[2]) end,
}

-- ============================================================
-- SPECIAL ALERTS AND WARNINGS
-- ============================================================
B["SA:[MC-Classic][Magmadar] Conflagration"] = {
    ["actions.start.custom"] = function()
        SendChatMessage("Conflag on " .. UnitName("player") .. "!", "YELL")
    end,
}

-- Living Bomb on you: yell the cross mark every second until it ends
B["SA:[MC-Classic][Baron Geddon] Living Bomb"] = {
    ["actions.start.custom"] = function(env)
        if env.ticker then return end
        env.ticker = C_Timer.NewTicker(1, function() SendChatMessage("{rt7}", "YELL") end)
    end,
    ["actions.finish.custom"] = function(env)
        if env.ticker then
            env.ticker:Cancel()
            env.ticker = nil
        end
    end,
}

B["SA:[MC-Classic][Shazzrah] Counterspell PreWarn"] = K.Merge(
    K.Prewarn{ key = "SHAZZRAH_COUNTERSPELL", on = "WA_SHAZZRAH_COUNTERSPELL_PREWARN",
        cancel = { "WA_SHAZZRAH_COUNTERSPELL_PREWARN_CANCEL" }, dur = 2.5, sampleDur = 3, icon = 135856 },
    { ["logic"] = function(env, t) return (_G.FJI_HEAL or _G.FJI_RANGED) and t[1] end })
B["SA:[MC-Classic][Ragnaros] Wrath of Ragnaros PreWarn"] = K.Prewarn{ key = "RAGNAROS_WRATH_OF_RAGNAROS", on = "WA_RAGNAROS_WRATH_OF_RAGNAROS_PREWARN",
    cancel = { "WA_RAGNAROS_WRATH_OF_RAGNAROS_PREWARN_CANCEL", "WA_RAGNAROS_SUBMERGE" }, dur = 5, sampleDur = 5, icon = 135827 }

B["SW:[MC-Classic][Magmadar] Conflagration"] = K.Flash{ key = "MAGMADAR_CONFLAG", icon = 135818, guid = true,
    sample = function() return { icon = 135818, guid = RM.WA.myGUID } end }
B["SW:[MC-Classic][Shazzrah] Blink"] = K.Flash{ key = "SHAZZRAH_BLINK", icon = 135743, sample = K.IconSample(135743) }
B["SW:[MC-Classic][Shazzrah] Reflect PreWarn"] = K.Merge(
    K.Prewarn{ key = "SHAZZRAH_REFLECT_MAGIC", on = "WA_SHAZZRAH_REFLECT_MAGIC_PREWARN",
        cancel = { "WA_SHAZZRAH_REFLECT_MAGIC_PREWARN_CANCEL" }, dur = 3, sampleDur = 5, icon = 132361 },
    { ["logic"] = ForRangedAndLead })
B["SW:[MC-Classic][All] Berserk in 30"] = K.Flash{ event = "WA_FOJJI_BERSERK_30", icon = 136224, sample = K.IconSample(136224) }
B["SW:[MC-Classic][All] Berserk Warn"] = K.Flash{ event = "WA_FOJJI_BERSERK", icon = 136224, sample = K.IconSample(136224) }

-- ============================================================
-- RAID FRAMES
-- ============================================================
B["RF:[MC-Classic][Trash] Ancient Dread"] = { ["conditions.1.check.fn"] = magicDispellers, ["logic"] = ForHealersAndLead }
B["RF:[MC-Classic][Trash] Ancient Hysteria"] = { ["logic"] = ForHealersAndLead }
B["RF:[MC-Classic][Trash] Cauterizing Flames"] = { ["conditions.1.check.fn"] = magicDispellers, ["logic"] = ForHealersAndLead }
B["RF:[MC-Classic][Trash] Soul Burn"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[MC-Classic][Lucifron] Dominate Mind"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[MC-Classic][Lucifron] Lucifron's Curse"] = { ["conditions.1.check.fn"] = curseRemovers }
B["RF:[MC-Classic][Lucifron] Impending Doom"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[MC-Classic][Magmadar] Panic"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[MC-Classic][Baron Geddon] Inferno"] = K.HitGlow{ spells = { 19695 } }
B["RF:[MC-Classic][Baron Geddon] Ignite Mana"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[MC-Classic][Shazzrah] Shazzrah's Curse"] = { ["conditions.1.check.fn"] = curseRemovers }
B["RF:[MC-Classic][Ragnaros] Wrath of Ragnaros"] = K.HitGlow{ spells = { 20566 } }

-- ============================================================
-- TEXTS
-- ============================================================
-- the countdown flashes: an icon for three seconds when the ability goes off
local function CountdownFlash(key, icon, speech)
    local map = K.Flash{ key = key, icon = icon, sample = K.IconSample(icon) }
    if speech then map = K.Merge(map, K.Speak(speech)) end
    return map
end
B["T:[MC-Classic][Lucifron] Lucifron's Curse"] = CountdownFlash("LUCIFRON_CURSE", 136123, { say = "Decurse", who = decursers })
B["T:[MC-Classic][Lucifron] Impending Doom"] = CountdownFlash("LUCIFRON_DOOM", 136179, { say = "Dispel", who = dispellersAndLead })
B["T:[MC-Classic][Magmadar] Frenzy"] = CountdownFlash("MAGMADAR_FRENZY", 132117, { say = "Frenzy", who = hunters })
B["T:[MC-Classic][Magmadar] Panic"] = CountdownFlash("MAGMADAR_PANIC", 136147)
B["T:[MC-Classic][Gehennas] Gehennas's Curse"] = CountdownFlash("GEHENNAS_CURSE", 136160, { say = "Decurse", who = decursers })
B["T:[MC-Classic][Garr] Antimagic Pulse"] = CountdownFlash("GARR_PULSE", 135894)
B["T:[MC-Classic][Baron Geddon] Ignite Mana"] = CountdownFlash("GEDDON_IGNITE_MANA", 135818, { say = "Ignite Mana", who = dispellersAndLead })
B["T:[MC-Classic][Shazzrah] Counterspell"] = CountdownFlash("SHAZZRAH_COUNTERSPELL", 135856)
B["T:[MC-Classic][Shazzrah] Shazzrah' Curse"] = CountdownFlash("SHAZZRAH_CURSE", 136121, { say = "Decurse", who = decursersAndLead })
B["T:[MC-Classic][Ragnaros] Wrath of Ragnaros"] = CountdownFlash("RAGNAROS_WRATH_OF_RAGNAROS", 135827)

-- the Majordomo shields have their own events
B["T:[MC-Classic][Majordomo] Damage Shield"] = K.Flash{ event = "WA_MAJORDOMO_DAMAGE_SHIELD", icon = 136121, sample = K.IconSample(136121) }
B["T:[MC-Classic][Majordomo] Magic Reflection"] = K.Merge(
    K.Flash{ event = "WA_MAJORDOMO_MAGIC_REFLECTION", icon = 135849, sample = K.IconSample(135849) },
    K.Speak{ say = "Reflect", who = rangedOrLead })

-- who got Dominate Mind / Living Bomb, under a heading
B["T:[[MC-Classic][Lucifron] Dominate Mind Title"] = K.Flash{ event = "WA_LUCIFRON_DOMINATE_MIND", icon = 136206, dur = 2.5,
    sample = { changed = true, icon = 136206 }, sampleShows = true }
B["T:[MC-Classic][Lucifron] Dominate Mind Players"] = K.PlayerList{ spell = 20604, title = "WA_LUCIFRON_DOMINATE_MIND" }
B["T:[MC-Classic][Baron Geddon] Living Bomb Title"] = K.Merge(
    K.Flash{ event = "WA_BARON_GEDDON_LIVING_BOMB", icon = 132863, dur = 2.5, sample = { changed = true, icon = 132863 }, sampleShows = true },
    K.Speak{ say = "Living Bomb" })
B["T:[MC-Classic][Baron Geddon] Living Bomb Players"] = K.PlayerList{ spell = 20475, title = "WA_BARON_GEDDON_LIVING_BOMB" }

RM.Own.Finish("MC", B)
