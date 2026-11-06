-- ZG - ZacUI's own Zul'Gurub boss module: what each piece does.
-- Part of ZacUI (Zacui_RaidMods). Settings in Own\ZG_Data.lua.
--
-- Most pieces are facts handed to the kit (RM_OwnKit.lua): one controller
-- per boss ability puts its countdown on the bus, and the timer bars and
-- warnings listen for it. ZG's own shapes - its speech, the healer
-- watches with their cast bars, the Hakkar aspects and Blood Siphon, the
-- Thekal tiger health bars and the coin and bijou auto-roll - are below.
--
-- A few pieces are still missing a fact (a spell id, a timing); they
-- say so where they sit.
local ns = _G.ZacUI
local RM = ns and ns.RaidMods
if not (RM and RM.Own and RM.Own.on) then return end
local K = RM.Own.Kit

local B = {}

-- ============================================================
-- ZG'S OWN SMALL PIECES
-- ============================================================

-- ZG's lines are spoken at the volume and rate the speech settings put in
-- the shared FJIDS_SFX_* globals, read at the moment of speaking (75 and
-- 1.2 when nothing set them). rate: a fixed rate instead.
local function Say(text, rate)
    return function()
        RM.Speak(text, _G.FJIDS_SFX_VOLUME or 75, rate or _G.FJIDS_SFX_RATE or 1.2)
    end
end
local function SpeakOnShow(text, rate)
    return { ["actions.start.custom"] = Say(text, rate) }
end

-- The countdown call for key on the bus. A wide one always carries a
-- fourth value (who it hit, or nothing), so listeners see the same
-- number of values every time.
local function Countdown(key, wide)
    if wide then
        return function(secs, count, who) RM.Fire("WA_NUMEN_TIMER", key, secs, count, who) end
    end
    return function(secs, count) RM.Fire("WA_NUMEN_TIMER", key, secs, count) end
end

-- A controller that only reports casts: K.Controller with no pull of its
-- own, whose count goes back to 1 when an encounter starts.
local function Cast(s)
    s.pull = false
    local map = K.Controller(s)
    local watch = map["triggers.1.trigger"]
    map["triggers.1.trigger"] = function(env, allstates, event, ...)
        if event == "ENCOUNTER_START" then env.count = 1 end
        return watch(env, allstates, event, ...)
    end
    return map
end

-- The finish action every hand-made controller here shares: count from
-- 1 again and take the countdown down.
local function Rewind(tell)
    return function(env)
        env.count = 1
        tell(nil)
    end
end

-- A three-second warning when key's countdown reaches 0.
--   icon
--   count    the warning shows the count too
--   who      the state field ("guid" or "name") the countdown's fourth
--            value goes in
--   preview  what the options preview puts there: "me" (your name) or
--            "guid" (your GUID)
-- The options preview is an icon (and a sample count and player); it
-- does not count as a change on its own.
local function Warn(s)
    return {
        ["triggers.1.trigger"] = function(env, allstates, event, key, secs, count, hit)
            if event == "OPTIONS" then
                local sample = { show = true, icon = s.icon }
                if s.who then sample[s.who] = s.preview == "me" and RM.WA.me or RM.WA.myGUID end
                if s.count then sample.count = math.random(1, 3) end
                allstates[""] = sample
            end
            if event ~= "WA_NUMEN_TIMER" or key ~= s.key or secs ~= 0 then return end
            local st = K.Put(allstates, "", K.Timed(3, { icon = s.icon, autoHide = true }))
            if s.who then st[s.who] = hit end
            if s.count then st.count = count end
            return true
        end,
    }
end
local function Flash(key, icon)
    return K.Flash{ key = key, icon = icon, sample = K.IconSample(icon) }
end

-- An icon whose text is the debuff's stacks times a number (armor or
-- damage per stack).
local function PerStack(n)
    return function(env, expirationTime, duration, progress, formatedDuration, name, icon, stacks)
        return (tonumber(stacks) or 0) * n
    end
end

-- Raid-frame checks: the player is one of these classes (English names,
-- as UnitClass gives them) / the raid leader or a healer.
local function ClassIs(...)
    local names = { ... }
    return function()
        local class = UnitClass("player")
        for i = 1, #names do
            if class == names[i] then return true end
        end
        return false
    end
end
local function LeadOrHealer()
    return UnitIsGroupLeader("player") or _G.FJI_HEALER
end

-- ============================================================
-- AUTOMATION
-- ============================================================
-- Coins and bijous: roll on them as this character's options say (the
-- piece's list holds a row per character: need, greed or pass for each).
do
    local COINS = K.Set{ 19698, 19699, 19700, 19701, 19702, 19703, 19704, 19705, 19706 }
    local BIJOUS = K.Set{ 19707, 19708, 19709, 19710, 19711, 19712, 19713, 19714, 19715 }
    local GREEN, YELLOW, GREY = "|cFF00FF00", "|cFFFFFF00", "|cFFadadad"
    local HEADING = "|cff33ff99" .. "Raid Mods - ZG AutoRoll" .. "|r: "
    local ZG_MAP = 309
    -- option 1/2/3 -> the roll it means (need 1, greed 2, pass 0) and how
    -- the settings line names it
    local ROLL = { [1] = 1, [2] = 2, [3] = 0 }
    local NAME = { [1] = GREEN .. "NEED|r", [2] = YELLOW .. "GREED|r", [3] = GREY .. "PASS|r" }
    -- what the chat line says after a roll, by roll
    local ROLLED = { [0] = GREY .. "Passed on|r ", [1] = "Rolled " .. GREEN .. "NEED|r on ", [2] = "Rolled " .. YELLOW .. "GREED|r on " }

    local function Complain(what)
        print("|cFFFF0000Error:|r " .. what)
    end

    -- an option value looked up in one of the tables above
    local function Pick(value, from)
        if value == nil then
            Complain("Argument 'rollConfig' is null")
            return nil
        end
        local out = from[value]
        if out == nil then print("Unknown roll config value: " .. value) end
        return out
    end

    -- this character's row, when it has one switched on
    local function ReadOptions(env)
        local me = UnitName("player")
        for _, row in ipairs(env.config.zg) do
            if row.character == me and row.enabled then
                env.coinsRoll, env.bijousRoll = row.coinsRoll, row.bijouRoll
                return true
            end
        end
        env.coinsRoll, env.bijousRoll = nil, nil
        return false
    end

    local function ItemIdOf(link)
        if link == nil then
            Complain("Argument 'itemLink' is null")
            return nil
        end
        return tonumber(link:match("item:(%d+)"), 10)
    end

    local function Roll(env, rollId)
        local link = GetLootRollItemLink(rollId)
        local item = ItemIdOf(link)
        local coin, bijou = COINS[item], BIJOUS[item]
        if not (coin or bijou) then return end
        if not ReadOptions(env) then return end
        local choice = env.bijousRoll
        if coin then choice = env.coinsRoll end
        local roll = Pick(choice, ROLL)
        if roll == nil then return end
        RollOnLoot(rollId, roll)
        print(ROLLED[roll] .. link)
    end

    local function ShowSettings(env)
        if env.coinsRoll ~= nil and env.bijousRoll ~= nil then
            print(HEADING .. "Bijous Roll: " .. Pick(env.bijousRoll, NAME))
            print(HEADING .. "Coins Roll: " .. Pick(env.coinsRoll, NAME))
        else
            print(HEADING .. "No valid config for this Character or Character is set to Disabled. Open the Raid Mods options for Zul'Gurub (AutoRoll on Bijou/Coins) and add your Character and your Bijou/Coin AutoRoll settings.")
        end
    end

    B["[ZG] AutoRoll on Bijou/Coins"] = {
        ["init"] = function(env) ReadOptions(env) end,
        ["triggers.1.trigger"] = function(env, event, rollId)
            if select(8, GetInstanceInfo()) ~= ZG_MAP then return false end
            if event == "START_LOOT_ROLL" then
                if rollId == nil then return false end
                Roll(env, rollId)
            elseif event == "STATUS" then
                ReadOptions(env)
            elseif event == "PLAYER_ENTERING_WORLD" then
                ShowSettings(env)
            end
        end,
    }
end

-- Venoxis: tell the range helper (Zacui_RaidTools) to watch 10 yards while
-- the piece shows, and to stop after.
do
    local function TellRange(msg)
        return function()
            local T = ns.RaidTools
            if T and T.RANGE_PREFIX then
                C_ChatInfo.SendAddonMessage(T.RANGE_PREFIX, msg, "WHISPER", UnitName("player"))
            end
        end
    end
    B["[ZG][Venoxis] Auto-Range"] = {
        ["actions.start.custom"] = TellRange("_RANGE_SET:10"),
        ["actions.finish.custom"] = TellRange("_RANGE_CANCEL"),
        ["text"] = function() return GetGossipOptions() end,
    }
end

-- ============================================================
-- TIMER BARS
-- ============================================================
-- The emphasized list: the last ten seconds of a bar
B["BTE:[ZG][All] Emphasized Timers"] = K.Emphasized{ sampleKey = "LaserAttack_" }

-- colours are 0-255 RGB plus alpha; a bar shows only while its key is
-- ticked in the piece's options
do
    local PINK = { 255, 182, 193, 1 }
    B["BT:[ZG][All] Boss Timers"] = K.TimerBars{
        sample = 3,
        hideAtZero = true,
        allow = function(env, key) return env.config.option.enabledGroup[key] end,
        bars = {
            JEKLIK_HEAL = { name = "Greater Heal", icon = 135915, color = PINK },
            HAKKAR_SIPHON = { name = "Blood Siphon", icon = 136168, color = PINK },
            HAKKAR_ARLOKK = { name = "Aspect of Arlokk", icon = 132331, color = PINK },
            HAKKAR_MARLI = { name = "Aspect of Marli", icon = 132318, color = PINK },
            HAKKAR_JEKLIK = { name = "Aspect of Jeklik", icon = 136222, color = PINK },
            HAKKAR_THEKAL = { name = "Aspect of Thekal", icon = 132117, color = PINK },
            HAKKAR_VENOXIS = { name = "Aspect of Venoxis", icon = 136016, color = PINK },
        },
    }
end

-- A wipe: the boss is back in 30 seconds (15 minutes for encounter 617).
-- The time is kept in the shared eRespawnTimer global so a reload or
-- another pack picks it up.
do
    local function Respawn(allstates)
        local back = _G.eRespawnTimer
        K.Put(allstates, "", { progressType = "timed", duration = back - GetTime(), expirationTime = back, autoHide = true })
        return true
    end
    B["BT:[ZG][All] Boss Respawn"] = {
        ["triggers.1.trigger"] = function(env, allstates, event, encounterId, encounterName, difficulty, size, success)
            if event == "ENCOUNTER_END" and success == 0 then
                _G.eRespawnTimer = GetTime() + (encounterId == 617 and 900 or 30)
                env.bossName = encounterName
                return Respawn(allstates)
            end
            if event == "STATUS" and _G.eRespawnTimer and _G.eRespawnTimer - GetTime() > 0 then
                return Respawn(allstates)
            end
        end,
    }
end

-- ============================================================
-- CONTROLLERS - every boss ability's countdown
-- ============================================================
B["CT:[ZG][Venoxis] Enraged"] = Cast{ key = "VENOXIS_ENRAGED", spell = 8269, sub = "SPELL_AURA_APPLIED", guid = true }
B["CT:[ZG][Venoxis] Poison Cloud"] = Cast{ key = "VENOXIS_CLOUD", spell = 23861 }
B["CT:[ZG][Venoxis] Renew"] = Cast{ key = "VENOXIS_RENEW", spell = 23895, sub = "SPELL_AURA_APPLIED", guid = true }
B["CT:[ZG][Mar'li] Spiders"] = Cast{ key = "MARLI_SPIDERS", spell = 24083 }
B["CT:[ZG][Thekal] Adds"] = Cast{ key = "THEKAL_ADDS", spell = 24183, sub = "SPELL_SUMMON" }
B["CT:[ZG][Arlokk] Mark of Arlokk"] = Cast{ key = "ARLOKK_MARK", spell = 24210, sub = "SPELL_AURA_APPLIED", guid = true }
B["CT:[ZG][Broodlord] Mortal Strike"] = K.Controller{ key = "BROODLORD_MORTAL_STRIKE", spell = 16856, guid = true }
B["CT:[ZG][Jin'do] Brain Wash Totem"] = Cast{ key = "JINDO_BRAIN_WASH", spell = 24261, sub = "SPELL_SUMMON" }
B["CT:[ZG][Jin'do] Hex"] = Cast{ key = "JINDO_HEX", spell = 17172, sub = "SPELL_AURA_APPLIED", guid = true }
B["CT:[ZG][Jin'do] Powerful Healing Ward"] = Cast{ key = "JINDO_HEALING_WARD", spell = 24309, sub = "SPELL_SUMMON" }
B["CT:[ZG][Hakkar] Insanity"] = Cast{ key = "HAKKAR_INSANITY", spell = 24327, sub = "SPELL_AURA_APPLIED", every = 20, guid = true }

-- The two healers' Greater Heal: each cast start says so and starts the
-- next window (every). Thekal's heal has no reliable interval, so it is
-- announced on the cast only (his second call just stops the timer) - on
-- purpose. A kicked heal goes out as kick (who kicked).
local function HealWatch(key, spell, every, kick)
    local tell = Countdown(key)
    return {
        ["init"] = function(env)
            env.key = key
            env.count = 1
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, sourceGUID, _, _, _, _, _, _, _, spellId, _, _, extraSpellId)
            if event == "ENCOUNTER_START" then env.count = 1 end
            if subEvent == "SPELL_CAST_START" and spellId == spell then
                tell(0, env.count)
                env.count = env.count + 1
                tell(every, env.count)
                return true
            elseif subEvent == "SPELL_INTERRUPT" and extraSpellId == spell then
                RM.Fire(kick, sourceGUID)
            end
        end,
        ["actions.finish.custom"] = Rewind(tell),
    }
end
B["CT:[ZG][Jeklik] Heal"] = HealWatch("JEKLIK_HEAL", 23954, 20, "WA_JEKLIK_HEAL_KICK")
B["CT:[ZG][Thekal] Heal"] = HealWatch("THEKAL_HEAL", 24208, nil, "WA_THEKAL_HEAL_KICK")

-- Thekal's phases: the pull, each priest going down (the emote) and his
-- tiger form (the yell) go out as bus events for the revive list. It
-- has no countdown of its own; its finish only puts the count back.
do
    local LINES = {
        enUS = { priestDied = "Let the games begin!", phaseTwo = "Well done, my minions. The mortals' courage begins to wane!" },
        frFR = { priestDied = "%s meurt.", phaseTwo = "Shirvallah, que ta RAGE m’envahisse !" },
        deDE = { priestDied = "%s stirbt.", phaseTwo = "Shirvallah, erfülle mich mit deinem Zorn!" },
        esES = { priestDied = "%s muere.", phaseTwo = "Shirvallah, ¡lléname de tu IRA!" },
        esMX = { priestDied = "%s muere.", phaseTwo = "Shirvallah, ¡lléname de IRA!" },
        koKR = { priestDied = "%s 죽었습니다.", phaseTwo = "시르밸라시여, 분노를 채워 주소서!" },
        ptBR = { priestDied = "%s morre.", phaseTwo = "Shirvallah! Me preenche com a tua fúria!" },
        ruRU = { priestDied = "%s умирает.", phaseTwo = "Ширвалла, наполни меня своим ГНЕВОМ!" },
        zhCN = { priestDied = "%s死了。", phaseTwo = "西瓦尔拉，让我感受你的愤怒吧！" },
        zhTW = { priestDied = "%s死了。", phaseTwo = "希瓦拉爾，給我憤怒的力量吧！" },
    }
    B["CT:[ZG][Thekal] Phase Controller"] = {
        ["init"] = function(env)
            env.lines = LINES[GetLocale()] or LINES.enUS
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, msg)
            if event == "ENCOUNTER_START" then RM.Fire("WA_THEKAL_P1_START") end
            if not msg then return end
            if event == "CHAT_MSG_MONSTER_YELL" and msg:find(env.lines.phaseTwo) then
                RM.Fire("WA_THEKAL_P2_START")
            elseif event == "CHAT_MSG_MONSTER_EMOTE" and msg:find(env.lines.priestDied) then
                RM.Fire("WA_THEKAL_PRIEST_DIED")
            end
        end,
        ["actions.finish.custom"] = function(env) env.count = 1 end,
    }
end

-- Broodlord's gaze: his yell names who he is watching; the debuff landing
-- tells the warning who has it (WA_BROODLORD_GAZE guid) and, unless the
-- yell already counted this one in the last ten seconds, counts it too.
do
    local GAZE_LINE = {
        enUS = "I'm watching you",
        frFR = "je vous ai à l'œil",
        deDE = "Ich behalte Euch im Auge",
        esES = "Te estoy vigilando",
        esMX = "Te estoy vigilando",
        koKR = "널 지켜보고 있겠다!",
        ptBR = "Estou do olho em você",
        ruRU = "Я за тобой слежу",
        zhCN = "I'm watching you",
        zhTW = "我正在監視你",
    }
    local GAZE, QUIET = 24314, 10
    local tell = Countdown("BROODLORD_GAZE", true)
    B["CT:[ZG][Broodlord] Gaze"] = {
        ["init"] = function(env)
            env.key = "BROODLORD_GAZE"
            env.count = 1
            env.throttle = 0
            env.gazeLine = GAZE_LINE[GetLocale()] or GAZE_LINE.enUS
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, msg, subEvent, _, _, target, _, _, destGUID, destName, _, _, spellId)
            if event == "CHAT_MSG_MONSTER_YELL" and msg and msg:find(env.gazeLine) then
                tell(0, env.count, target)
                env.count = env.count + 1
                env.throttle = GetTime()
            end
            if spellId ~= GAZE then return false end
            if subEvent ~= "SPELL_AURA_APPLIED" then return end
            RM.Fire("WA_BROODLORD_GAZE", destGUID)
            if GetTime() - (env.throttle or 0) < QUIET then return end
            tell(0, env.count, destName)
            env.count = env.count + 1
            return true
        end,
        ["actions.finish.custom"] = Rewind(tell),
    }
end

-- Hakkar's hard mode (the version with all five priests alive): on the
-- pull, anyone in the raid targeting a Hakkar with 1079325 or more health
-- tells the aspect timers to start (WA_HAKKAR_HARD_MODE). Like Thekal's
-- phases it has no countdown of its own.
do
    local HAKKAR, HARD_HEALTH = "14834", 1079325
    local function HardMode()
        if not IsInRaid() then return false end
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i .. "target"
            local guid = UnitGUID(unit)
            if guid and K.NpcId(guid) == HAKKAR and UnitHealthMax(unit) >= HARD_HEALTH then
                return true
            end
        end
        return false
    end
    B["CT:[ZG][Hakkar] Hard Mode"] = {
        ["init"] = function() end,
        ["triggers.1.trigger"] = function(env, allstates, event)
            if event == "ENCOUNTER_START" and HardMode() then RM.Fire("WA_HAKKAR_HARD_MODE") end
        end,
        ["actions.finish.custom"] = function(env) env.count = 1 end,
    }
end

-- Blood Siphon: 90 seconds from the pull, then 90 after each one, with a
-- heads-up (WA_HAKKAR_SIPHON_PREWARN seconds, count) 5 seconds before
-- each one.
do
    local SIPHON, EVERY, LEAD = 24324, 90, 5
    local tell = Countdown("HAKKAR_SIPHON", true)
    local function HeadsUp(env, early, secs, count)
        if env.preWarnTimer then env.preWarnTimer:Cancel() end
        env.preWarnTimer = C_Timer.NewTimer(EVERY - early, function()
            RM.Fire("WA_HAKKAR_SIPHON_PREWARN", secs, count)
            env.preWarnTimer = nil
        end)
    end
    B["CT:[ZG][Hakkar] Siphon"] = {
        ["init"] = function(env)
            env.key = "HAKKAR_SIPHON"
            env.count = 1
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, _, _, _, _, _, _, _, spellId)
            if event == "ENCOUNTER_START" then
                env.count = 1
                HeadsUp(env, LEAD, LEAD, env.count)
                tell(EVERY, env.count)
            end
            if spellId ~= SIPHON then return false end
            if subEvent ~= "SPELL_CAST_SUCCESS" then return end
            tell(0, env.count)
            env.count = env.count + 1
            HeadsUp(env, LEAD, LEAD, env.count)
            tell(EVERY, env.count)
            return true
        end,
        ["actions.finish.custom"] = Rewind(tell),
    }
end

-- The five aspects (hard mode only). Hard mode shows the piece and starts
-- the count; each cast says so. There are no reliable timings for them,
-- so they are announced on the cast only (their countdown calls carry no
-- time and no bar runs) - on purpose.
local function Aspect(key, spell)
    local tell = Countdown(key)
    return {
        ["init"] = function(env)
            env.key = key
            env.count = 1
        end,
        ["triggers.1.trigger"] = function(env, allstates, event, _, subEvent, _, _, _, _, _, _, _, _, _, spellId)
            if event == "WA_HAKKAR_HARD_MODE" then
                K.Put(allstates, "", {})
                env.count = 1
                tell(nil, env.count)
            end
            if spellId ~= spell then return false end
            if subEvent ~= "SPELL_CAST_SUCCESS" then return end
            tell(0, env.count)
            env.count = env.count + 1
            tell(nil, env.count)
            return true
        end,
        ["actions.finish.custom"] = Rewind(tell),
    }
end
B["CT:[ZG][Hakkar] Aspect [Arlokk]"] = Aspect("HAKKAR_ARLOKK", 24690)
B["CT:[ZG][Hakkar] Aspect [Jeklik]"] = Aspect("HAKKAR_JEKLIK", 24687)
B["CT:[ZG][Hakkar] Aspect [Marli]"] = Aspect("HAKKAR_MARLI", 24686)
B["CT:[ZG][Hakkar] Aspect [Thekal]"] = Aspect("HAKKAR_THEKAL", 24689)
B["CT:[ZG][Hakkar] Aspect [Venoxis]"] = Aspect("HAKKAR_VENOXIS", 24688)

-- ============================================================
-- CHARACTER, CIRCLES
-- ============================================================
B["R:[ZG][Venoxis] Poison Cloud"] = K.Merge(Flash("VENOXIS_CLOUD", 136064), SpeakOnShow("Cloud"))

-- Broodlord is watching you: six seconds of the gaze icon
do
    local function Watched(allstates)
        K.Put(allstates, "", K.Timed(6, { icon = 136129, autoHide = true }))
    end
    B["R:[ZG][Broodlord] Threatening Gaze"] = {
        ["triggers.1.trigger"] = function(env, allstates, event, guid)
            if event == "OPTIONS" then Watched(allstates) end
            if event == "WA_BROODLORD_GAZE" and guid == RM.WA.myGUID then
                Watched(allstates)
                return true
            end
        end,
    }
end

-- the circle counting down to Blood Siphon
do
    local ICON = 136168
    B["C:[ZG][Hakkar] Siphon PreWarn"] = {
        ["triggers.1.icon"] = K.Always(135789),
        ["triggers.1.trigger"] = function(env, allstates, event, ...)
            if event == "OPTIONS" then
                K.Put(allstates, "", { progressType = "timed", icon = ICON, count = math.random(1, 3) })
                return true
            end
            if event == "WA_HAKKAR_SIPHON_PREWARN" then
                local duration, count = ...
                K.Put(allstates, "", { progressType = "timed", duration = duration, expirationTime = GetTime() + duration, icon = ICON, count = count })
                return true
            end
            if event == "WA_NUMEN_TIMER" then
                local key, secs = ...
                if key == "HAKKAR_SIPHON" and (secs == 0 or secs == nil) then return K.Drop(allstates, "") end
            end
        end,
    }
end

-- ============================================================
-- ICONS
-- ============================================================
B["I:[ZG][Venoxis] Venom Spit"] = { ["text"] = PerStack(200) }
B["I:[ZG][Venoxis] Virulent Poison"] = { ["text"] = PerStack(54) }
B["I:[ZG][Jeklik] Fear"] = SpeakOnShow("Fear")
B["I:[ZG][Broodlord] Intimidating Shout"] = SpeakOnShow("Fear")
B["A:[ZG][Jeklik] Sonic Burst"] = SpeakOnShow("Silenced")
B["A:[ZG][Thekal] Silence"] = SpeakOnShow("Silenced")
B["A:[ZG][Arlokk] Mark of Arlokk"] = SpeakOnShow("Marked")

-- ============================================================
-- LISTS
-- ============================================================
-- Thekal's priests get back up 20 seconds after dying unless all are
-- down together: a bar per death, cleared when he turns tiger.
do
    local REVIVE = 20
    B["L:[ZG][Thekal] Revive"] = {
        ["triggers.1.trigger"] = function(env, allstates, event)
            if event == "OPTIONS" then
                K.Put(allstates, RM.WA.myGUID, K.Timed(REVIVE, { autoHide = true }))
                return true
            end
            if event == "WA_THEKAL_PRIEST_DIED" then
                K.Put(allstates, GetTime(), K.Timed(REVIVE, { autoHide = true }))
                return true
            elseif event == "WA_THEKAL_P2_START" then
                for _, st in pairs(allstates) do
                    st.show = false
                    st.changed = true
                end
                return true
            end
        end,
    }
end

-- ============================================================
-- MISC, NAMEPLATES
-- ============================================================
B["[ZG] Disable Raid Emotes"] = K.MuteBossEmotes{ flat = true }

-- Renew landing on npc 5273: 30 seconds on its nameplate
B["N:[ZG][Venoxis] Renew"] = K.PlateBuff{ npcs = { "5273" }, spells = { 23895 }, dur = 30 }

-- ============================================================
-- PROGRESS BARS
-- ============================================================
B["PC:[ZG][Trash] Unstable Concoction"] = { ["text"] = K.Field("addColour") }

-- Greater Heal: a 4 second cast bar when the heal's countdown says it
-- went off (the cast started), a 1 second "Kicked" bar on the kick event;
-- the condition that says "Interrupt" is the second one.
local function HealBar(heal, kick)
    local ICON = 135915
    return {
        ["conditions.2.changes.1.value"] = Say("Interrupt"),
        ["text"] = K.Field("addColour"),
        -- (first: a countdown's key, or who kicked)
        ["triggers.1.trigger"] = function(env, allstates, event, first, secs)
            if event == "OPTIONS" then
                K.Put(allstates, "", { progressType = "timed", icon = ICON })
                return true
            end
            if event == "WA_NUMEN_TIMER" then
                if first ~= heal or secs ~= 0 then return end
                K.Put(allstates, "", K.Timed(4, { autoHide = true, icon = ICON, status = "Casting" }))
                return true
            elseif event == kick then
                K.Put(allstates, "", K.Timed(1, { autoHide = true, icon = ICON, status = "Kicked", interrupter = first }))
                return true
            end
        end,
    }
end
B["PC:[ZG][Jeklik] Greater Heal"] = HealBar("JEKLIK_HEAL", "WA_JEKLIK_HEAL_KICK")
B["PC:[ZG][Thekal] Greater Heal"] = HealBar("THEKAL_HEAL", "WA_THEKAL_HEAL_KICK")

-- Blood Siphon's 8 second bar, from the siphon going off.
do
    local ICON = 136168
    B["PC:[ZG][Hakkar] Blood Siphon"] = {
        ["actions.start.custom"] = Say("Siphon"),
        ["text"] = K.Field("addColour"),
        ["triggers.1.trigger"] = function(env, allstates, event, key, secs, count)
            if event == "OPTIONS" then
                K.Put(allstates, "", K.Timed(8, { icon = ICON, count = math.random(1, 3), guid = RM.WA.myGUID }))
                return true
            end
            if event == "WA_NUMEN_TIMER" and key == "HAKKAR_SIPHON" and secs == 0 then
                K.Put(allstates, "", K.Timed(8, { icon = ICON, autoHide = true, count = count }))
                return true
            end
        end,
    }
end

-- Thekal, Zath and Lorkhan must die together: a health bar each, read
-- once a second (the piece's own ticker fires WA_FJI_TIGER_TICKER) from
-- the raid's targets and the nameplates. Each bar keeps a "percent" text.
do
    local TIGERS = {
        { npc = "11348", name = "Zath", icon = 626005 },
        { npc = "14509", name = "Thekal", icon = 626008 },
        { npc = "11347", name = "Lorkhan", icon = 626004 },
    }
    local SLOT = {}
    for slot, t in ipairs(TIGERS) do SLOT[t.npc] = slot end

    -- a tiger's bar, made on first sight at full health; hp a fraction
    local function Health(allstates, slot, hp)
        local st = allstates[slot]
        if not st then
            local t = TIGERS[slot]
            st = K.Put(allstates, slot, { progressType = "static", value = 1, total = 1, percent = "100%", name = t.name, icon = t.icon })
        end
        if hp then
            st.value = hp
            st.percent = math.floor(hp * 100) .. "%"
        end
        st.changed = true
    end

    local function AllFull(allstates)
        for slot = 1, #TIGERS do Health(allstates, slot, 1) end
        return true
    end

    local function Look(allstates, unit)
        local guid = unit and UnitGUID(unit)
        if not guid then return end
        local hp = UnitHealth(unit) / UnitHealthMax(unit)
        local slot = SLOT[K.NpcId(guid)]
        if slot then Health(allstates, slot, hp) end
    end

    B["PT:[ZG][Thekal] HP Bars"] = {
        ["init"] = function() end,
        ["actions.start.custom"] = function(env)
            if env.ticker then return end
            env.ticker = C_Timer.NewTicker(1, function() RM.Fire("WA_FJI_TIGER_TICKER") end)
        end,
        ["actions.finish.custom"] = function(env)
            if env.ticker then
                env.ticker:Cancel()
                env.ticker = nil
            end
        end,
        ["triggers.1.trigger"] = function(env, allstates, event)
            if event == "OPTIONS" or event == "ENCOUNTER_START" then return AllFull(allstates) end
            if event ~= "WA_FJI_TIGER_TICKER" then return end
            for unit in RM.IterateGroup() do Look(allstates, unit .. "target") end
            for _, plate in pairs(C_NamePlate.GetNamePlates()) do
                Look(allstates, plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.displayedUnit))
            end
            return true
        end,
    }
end

-- ============================================================
-- RAID FRAMES
-- ============================================================
local magicDispellers = ClassIs("Paladin", "Priest")
local poisonCurers = ClassIs("Paladin", "Druid", "Shaman")
B["RF:[ZG][Venoxis] Holy Fire"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[ZG][Venoxis] Venom Split"] = { ["conditions.1.check.fn"] = poisonCurers }
B["RF:[ZG][Venoxis] Virulent Poison"] = { ["conditions.1.check.fn"] = poisonCurers }
B["RF:[ZG][Jeklik] Charge"] = { ["conditions.1.check.fn"] = LeadOrHealer }
B["RF:[ZG][Jeklik] Shadow Word: Pain"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[ZG][Mar'li] Corrosive Poison"] = { ["conditions.1.check.fn"] = poisonCurers }
B["RF:[ZG][Mar'li] Drain Life"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[ZG][Thekal] Mortal Cleave"] = { ["conditions.1.check.fn"] = LeadOrHealer }
B["RF:[ZG][Thekal] Silence"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[ZG][Arlokk] Shadow Word: Pain"] = { ["conditions.1.check.fn"] = magicDispellers }
B["RF:[ZG][Broodlord] Gaze"] = { ["conditions.1.check.fn"] = LeadOrHealer }
B["RF:[ZG][Broodlord] Mortal Strike"] = { ["conditions.1.check.fn"] = LeadOrHealer }
B["RF:[ZG][Jin'do] Hex"] = { ["conditions.1.check.fn"] = magicDispellers }

-- ============================================================
-- SPECIAL ALERTS AND WARNINGS
-- ============================================================
-- standing in something: "Move", always at the usual rate
B["SA:[ZG][All] GTFO"] = SpeakOnShow("Move", 1.2)

B["SW:[ZG][Venoxis] Renew"] = Flash("VENOXIS_RENEW", 135953)
B["SW:[ZG][Mar'li] Spiders"] = K.Merge(Warn{ key = "MARLI_SPIDERS", icon = 132196, count = true }, SpeakOnShow("Adds"))
B["SW:[ZG][Thekal] Adds"] = K.Merge(Warn{ key = "THEKAL_ADDS", icon = 132242, count = true }, SpeakOnShow("Adds"))
B["SW:[ZG][Arlokk] Mark of Arlokk"] = Warn{ key = "ARLOKK_MARK", icon = 132212, count = true, who = "guid", preview = "guid" }
B["SW:[ZG][Broodlord] Gaze"] = Warn{ key = "BROODLORD_GAZE", icon = 136129, count = true, who = "name", preview = "me" }
B["SW:[ZG][Broodlord] Mortal Strike"] = Warn{ key = "BROODLORD_MORTAL_STRIKE", icon = 132355, count = true, who = "name", preview = "guid" }
B["SW:[ZG][Jin'do] Brain Wash Totem"] = K.Merge(Flash("JINDO_BRAIN_WASH", 136120), SpeakOnShow("Totem"))
B["SW:[ZG][Jin'do] Hex"] = Warn{ key = "JINDO_HEX", icon = 136071, count = true, who = "guid", preview = "guid" }
B["SW:[ZG][Hakkar] Cause Insanity"] = Warn{ key = "HAKKAR_INSANITY", icon = 136206, count = true, who = "name", preview = "guid" }

-- ============================================================
-- TEXTS
-- ============================================================
-- Venoxis turns snake at 50%: the line shows how far off that is (a made
-- up figure in the preview)
B["T:[ZG][Venoxis] Phase 2 Warn"] = {
    ["text"] = function(env)
        local hp = env.state.percenthealth or math.random(50, 55)
        return "|cFFFFFF0050%|r | |cFF00FF00" .. string.format("%.2f", hp) .. "%|r"
    end,
}
B["T:[ZG][Venoxis] Enrage"] = Flash("VENOXIS_ENRAGED", 136224)
B["T:[ZG][Jin'do] Healing Ward"] = Flash("JINDO_HEALING_WARD", 135928)

RM.Own.Finish("ZG", B)
