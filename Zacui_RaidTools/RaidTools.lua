-- RaidTools - the raid helpers the boss mods lean on: /pull, /break and
-- /range, the raid sync, and the speech settings.
-- Part of ZacUI (Zacui_RaidTools); load order is set by the TOC.
--
-- WHAT IS HERE, and who uses it:
--   speech     three numbers the raid modules read when they speak
--              (_G.FJITTS_SFX_VOLUME / RATE / VOICEID - the names the
--              modules always had), set from the settings below
--   raid sync  _G.SyncEvents(channel, target, event, ...): fires the
--              event, with its arguments, in every raider's boss mods.
--              The MC, AQ40 and Naxxramas modules and the pull timer use it
--   timers     /pull and /break in every boss mod's language, and the
--              break messages other raiders send
--   range      /range 10 - a message to yourself the range piece reads
--
-- The wire names (the comm prefixes, the event names) are the ones other
-- raiders' boss mods send and read, so they stay exactly as they are.

local ADDON_NAME = ...
-- Zacui_RaidTools is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local Print = ns.Print
local AddonLoaded = ns.AddonLoaded

local T = {}
ns.RaidTools = T

-- ============================================================
-- SETTINGS
-- ============================================================
-- Under the aura engine's key, so they travel with its profile section
-- (where they have always lived). Saved before 2026-11-06 under an older
-- key, moved across once.
local DEFAULTS = { ttsVolume = 75, ttsRate = 1.8, ttsVoiceID = 0 }
local OLD_KEY = "fojji"

local function Settings()
    if type(ZacUIDB) ~= "table" then return DEFAULTS end
    ZacUIDB.auraEngine = ZacUIDB.auraEngine or {}
    local a = ZacUIDB.auraEngine
    if type(a.raidSpeech) ~= "table" then
        a.raidSpeech = type(a[OLD_KEY]) == "table" and a[OLD_KEY] or {}
    end
    a[OLD_KEY] = nil
    local d = a.raidSpeech
    for k, v in pairs(DEFAULTS) do
        if d[k] == nil then d[k] = v end
    end
    return d
end
T.Settings = Settings

-- ============================================================
-- SPEECH
-- ============================================================
-- Read at the moment of speaking, with a fallback each. Set now so a
-- warning during login already has them, and again at login in case the
-- saved values were not readable yet.
local function ApplySpeech()
    local d = Settings()
    _G.FJITTS_SFX_VOLUME = d.ttsVolume
    _G.FJITTS_SFX_RATE = d.ttsRate
    _G.FJITTS_SFX_VOICEID = d.ttsVoiceID
end
T.ApplySpeech = ApplySpeech
ApplySpeech()

-- ============================================================
-- RAID SYNC
-- ============================================================
-- A module keeps raiders in step - a pull timer asked for and answered, a
-- tentacle's health shared - by calling
--
--     (_G.SyncEvents or function() end)("RAID", nil, "WA_SOME_EVENT", ...)
--
-- and expecting that event to fire, with its arguments, for everyone
-- else. What goes over the wire is what the other raiders' boss mods send
-- and read: the comm prefix, then the event and its arguments serialized,
-- deflated and escaped for the addon channel, in the usual comm framing.
-- ZacUI's aura engine does all of that itself (AE_Codec, AE_Comm), so the
-- sync needs it on; without it the modules' own fallback (an empty
-- function) is the right answer to "sync is not available".
local SYNC_PREFIX = "WA_SYNC_EVENTS"

-- Whispered sync is never honoured on receipt: a stranger must not be
-- able to fire events in your boss mods.
local SYNC_FROM = { PARTY = true, RAID = true, INSTANCE_CHAT = true, GUILD = true, OFFICER = true }

local function StartSync()
    if T.sync then return end
    local E = ns.AuraEngine
    local Co, Cm = E and E.Codec, E and E.Comm
    if not (Co and Cm and Co.ToAddon and Cm.Send) then return end

    local function Send(channel, target, event, ...)
        -- One module passes its event where the channel belongs. That is a
        -- message to nowhere; drop it rather than let it throw.
        if type(channel) ~= "string" or type(event) ~= "string" then return false end
        if not (SYNC_FROM[channel] or channel == "WHISPER") then return false end
        if channel == "WHISPER" and type(target) ~= "string" then return false end
        -- "RAID" from a five-man reaches the party, so the test is being
        -- grouped at all, not being in a raid.
        if (channel == "RAID" or channel == "PARTY") and not IsInGroup() then return false end

        local ok, wire = pcall(function(...)
            return Co.ToAddon(Co.Deflate(Co.Serialize({ event = event, payload = { ... } })))
        end, ...)
        if not ok then return false end
        return Cm.Send(SYNC_PREFIX, wire, channel, target)
    end

    -- Your own broadcast comes back to you like anyone else's, and the
    -- modules rely on that: the raider who asks is also one of the raiders
    -- who hears the question.
    local function Receive(_, wire, channel)
        if not SYNC_FROM[channel] or type(wire) ~= "string" then return end
        local squeezed = Co.FromAddon(wire)
        if not squeezed then return end
        local ok, packed = pcall(Co.Inflate, squeezed)
        if not ok or type(packed) ~= "string" then return end
        local ok2, data = pcall(Co.Deserialize, packed)
        if not ok2 or type(data) ~= "table" or type(data.event) ~= "string" then return end
        local payload = type(data.payload) == "table" and data.payload or {}
        local WA = _G.WeakAuras
        if type(WA) == "table" and WA.ScanEvents then
            WA.ScanEvents(data.event, unpack(payload))
        end
    end

    Cm.Register(SYNC_PREFIX, Receive)

    T.sync = true
    T.SyncSend, T.SyncReceive = Send, Receive
    _G.SyncEvents = Send
end
StartSync()

-- ============================================================
-- TIMERS AND RANGE
-- ============================================================
-- An addon message only reaches a client that has registered its prefix.
-- The pull and break timers read two kinds: the raid packs' own break
-- call, and the boss-mod ones other raiders' DBM broadcasts, so a break
-- called by someone running DBM still shows up here without DBM
-- installed. TIMER_PREFIX and RANGE_PREFIX are the names other raiders'
-- clients use on the wire.
local TIMER_PREFIX = "FojjiTimerAddon"
local RANGE_PREFIX = "FojjiRangeAddon"
local BOSSMOD_PREFIXES = { "D5WCWC", "D5WCC", "D5WC", "D5C", "D5" }
T.TIMER_PREFIX, T.RANGE_PREFIX = TIMER_PREFIX, RANGE_PREFIX

local function RegisterPrefix(prefix)
    local fn = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix
    if fn then pcall(fn, prefix) end
end

local function SendAddon(prefix, text, channel, target)
    -- WoW Forever delivers no addon messages inside an instance (Core_Flavor)
    if ns.AddonMessagesBlocked and ns.AddonMessagesBlocked() then return end
    local fn = C_ChatInfo and C_ChatInfo.SendAddonMessage
    if fn then pcall(fn, prefix, text, channel, target) end
end

RegisterPrefix(TIMER_PREFIX)
for _, prefix in ipairs(BOSSMOD_PREFIXES) do RegisterPrefix(prefix) end

local function Me()
    return (UnitName("player")) or ""
end

-- Raid timers are the leader's and the assistants' to call. Alone, or in
-- a group you lead, anyone can.
local function MayCall()
    if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        Print("Only the group leader or an assistant can start that.")
        return false
    end
    return true
end

local function Slash(key, command, handler)
    _G["SLASH_" .. key .. "1"] = command
    SlashCmdList[key] = handler
end

-- ============================================================
-- /pull AND /break, IN EVERY BOSS MOD'S LANGUAGE
-- ============================================================
-- One command reaches everyone: the game's own countdown (pull only),
-- DBM's message (prefix D5: "Name-Realm<tab>1<tab>PT|BT<tab>seconds"),
-- BigWigs' ("P^Pull^seconds" / "P^Break^seconds"), and for breaks the
-- raid packs' own. ZacUI's timer bars start straight away too, so they
-- also work alone. Seconds of 0 cancel, in every one of them.
local GroupChannel = ns.GroupChannel

local function FullName()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName())
        or (GetRealmName() or ""):gsub("[%s-]+", "")
    return Me() .. "-" .. realm
end

local function BossMods(cmd, bwKind, seconds)
    local ch = GroupChannel()
    if not ch then return end
    local instance = tonumber((select(8, GetInstanceInfo()))) or 0
    if cmd == "PT" then
        SendAddon("D5", ("%s\t1\tPT\t%d\t%d"):format(FullName(), seconds, instance), ch)
    else
        SendAddon("D5", ("%s\t1\tBT\t%d"):format(FullName(), seconds), ch)
    end
    SendAddon("BigWigs", ("P^%s^%d"):format(bwKind, seconds), ch)
end

local function LocalBar(kind, seconds)
    local RT = ns.QoL and ns.QoL.RaidTimers
    if RT and RT.Set then RT.Set(kind, seconds, Me()) end
end

-- The game's own countdown, where this client has one.
local function Countdown(seconds)
    if C_PartyInfo and C_PartyInfo.DoCountdown then
        pcall(C_PartyInfo.DoCountdown, seconds)
    elseif SlashCmdList and SlashCmdList.COUNTDOWN then
        pcall(SlashCmdList.COUNTDOWN, tostring(seconds))
    end
end

local function Broadcast(text)
    local ch = GroupChannel()
    if ch then
        SendAddon(TIMER_PREFIX, text, ch)
    else
        SendAddon(TIMER_PREFIX, text, "WHISPER", Me())
    end
end

local function PullStart(seconds)
    Countdown(seconds)
    BossMods("PT", "Pull", seconds)
    LocalBar("pull", seconds)
end

local function PullCancel()
    Countdown(0)
    BossMods("PT", "Pull", 0)
    LocalBar("pull", 0)
end

local function BreakStart(seconds)
    Broadcast("BREAK:" .. seconds .. ":" .. Me())
    BossMods("BT", "Break", seconds)
    LocalBar("brk", seconds)
end

local function BreakCancel()
    Broadcast("BREAK_CANCEL::" .. Me())
    BossMods("BT", "Break", 0)
    LocalBar("brk", 0)
end
T.PullStart, T.PullCancel = PullStart, PullCancel
T.BreakStart, T.BreakCancel = BreakStart, BreakCancel

-- With DBM or BigWigs installed their own /pull and /break do all of
-- this, so ZacUI's stay out of the way.
if not (AddonLoaded("DBM-Core") or AddonLoaded("BigWigs")) then
    Slash("ZACUIPULL", "/pull", function(msg)
        if not MayCall() then return end
        msg = strtrim(msg or ""):lower()
        if msg == "cancel" or msg == "0" then
            PullCancel()
            return
        end
        local seconds = msg == "" and 10 or tonumber(msg)
        if seconds and seconds > 0 then
            PullStart(math.min(math.floor(seconds), 60))
        else
            Print("Usage: /pull 10 (seconds), or /pull cancel.")
        end
    end)

    Slash("ZACUIBREAK", "/break", function(msg)
        if not MayCall() then return end
        msg = strtrim(msg or ""):lower()
        if msg == "cancel" or msg == "0" then
            BreakCancel()
            return
        end
        local minutes = msg == "" and 5 or tonumber(msg)
        if minutes and minutes > 0 then
            BreakStart(math.floor(math.min(minutes, 60) * 60))
        else
            Print("Usage: /break 5 (minutes), or /break cancel.")
        end
    end)
end

-- Said in chat as well, because the timer bar may not be showing where
-- you are standing.
local function OnTimerMessage(text)
    local cmd, value, who = strsplit(":", text or "")
    who = (who and who ~= "") and who or "Someone"
    if cmd == "BREAK" then
        local seconds = tonumber(value) or 0
        if seconds > 0 then
            local minutes = math.floor(seconds / 60 + 0.5)
            Print(who .. " called a " .. minutes .. " minute break.")
        end
    elseif cmd == "BREAK_CANCEL" then
        Print(who .. " cancelled the break.")
    end
end
T.OnTimerMessage = OnTimerMessage

-- /range 10, /range cancel - a whisper to yourself that the range piece
-- listens for. A boss mod's own /range is the better tool where one is
-- installed, so this stays out of its way.
local function Range(yards)
    T.rangeShowing = yards
    if yards then
        SendAddon(RANGE_PREFIX, "_RANGE_SET:" .. yards, "WHISPER", Me())
    else
        SendAddon(RANGE_PREFIX, "_RANGE_CLEAR", "WHISPER", Me())
    end
end
T.Range = Range

if not (AddonLoaded("DBM-Core") or AddonLoaded("BigWigs")) then
    RegisterPrefix(RANGE_PREFIX)
    T.rangeOwned = true

    Slash("ZACUIRANGE", "/range", function(msg)
        msg = strtrim(msg or ""):lower()
        if msg:match("^%d+$") then
            Range(tonumber(msg))
        elseif msg == "cancel" or (msg == "" and T.rangeShowing) then
            Range(nil)
        else
            Print("Usage: /range 10 (yards), or /range cancel.")
        end
    end)
end

-- ============================================================
-- EVENTS
-- ============================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, prefix, text)
    if event == "CHAT_MSG_ADDON" then
        if prefix == TIMER_PREFIX then OnTimerMessage(text) end
        return
    end

    -- PLAYER_LOGIN
    self:UnregisterEvent("PLAYER_LOGIN")
    ApplySpeech()
    StartSync()
end)
