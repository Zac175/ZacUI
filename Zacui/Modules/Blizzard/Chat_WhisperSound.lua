-- Chat_WhisperSound - a sound when a whisper arrives (a Battle.net
-- whisper too), picked from ZacUI's sound list. Off by default (Chat >
-- Sound). The whisper button's glow on the chat bar (Blz_Chat) is
-- separate and keeps working whatever this is set to.
-- Part of ZacUI; load order is set by the TOC (after Blz_Chat).
--
-- The sound is a sound spec on the customization standard
-- (chat.sounds.whisper: sound, channel, "not again within"), played
-- through ns.PlaySoundSpec like every other sound ZacUI makes, so the
-- list is the one every sound picker shows (the game's own blips, text
-- to speech, SharedMedia files). Nothing saved = the game's whisper blip
-- ("Message") on the Master channel, every time.
--
-- Only two events, both rare, registered only while the setting is on.

local ADDON_NAME, ns = ...

local Chat = ns.Chat

local WS = {}
ns.WhisperSound = WS

WS.DEFAULTS = { sound = "ui:Chime", channel = "Master", throttle = 0 }
WS.KEY = "chat.whisper"
-- the game plays its own whisper blip (SOUNDKIT.TELL_MESSAGE, this one
-- sound file) on every whisper; while ours is on that one is muted, or
-- every whisper would sound twice. Put back the moment ours goes off.
WS.TELL_FILE = 567421

local function DB()
    if Chat and Chat.DB then return Chat.DB() end
    ZacUIDB.chat = ZacUIDB.chat or {}
    return ZacUIDB.chat
end
function WS.On() return DB().whisperSound == true end
function WS.MuteGame() return DB().whisperMute ~= false end
function WS.Spec()
    local d = DB()
    return type(d.sounds) == "table" and d.sounds.whisper or nil
end

-- plays the chosen sound (the Test button and the live whisper both)
function WS.Play(test)
    if not ns.PlaySoundSpec then return false end
    return ns.PlaySoundSpec(WS.Spec(), WS.DEFAULTS, (not test) and WS.KEY or nil)
end

-- ============================================================
-- EVENTS
-- ============================================================
local ev = CreateFrame("Frame")
local listening = false
local function Listen(on)
    if on == listening then return end
    listening = on
    if on then
        ev:RegisterEvent("CHAT_MSG_WHISPER")
        pcall(ev.RegisterEvent, ev, "CHAT_MSG_BN_WHISPER")
    else
        ev:UnregisterEvent("CHAT_MSG_WHISPER")
        pcall(ev.UnregisterEvent, ev, "CHAT_MSG_BN_WHISPER")
    end
end
ev:SetScript("OnEvent", function(_, event)
    -- (the message and the sender are never read: on WoW Forever they can
    -- be hidden from addons in a fight, and the sound needs neither)
    WS.Play(false)
end)

local gameMuted = false
local function MuteGameBlip(on)
    if on == gameMuted then return end
    if on and not MuteSoundFile then return end
    gameMuted = on
    if on then pcall(MuteSoundFile, WS.TELL_FILE)
    elseif UnmuteSoundFile then pcall(UnmuteSoundFile, WS.TELL_FILE) end
end
WS.GameMuted = function() return gameMuted end

function WS.Apply()
    if ns.FeatureOn and not ns.FeatureOn("whisper_sound") then Listen(false) MuteGameBlip(false) return end
    local on = WS.On()
    Listen(on)
    MuteGameBlip(on and WS.MuteGame())
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    WS.Apply()
    if ns.OnSettingsChanged then
        local soon = ns.Coalesce and ns.Coalesce(WS.Apply) or WS.Apply
        ns.OnSettingsChanged(function() soon() end)
    end
end)

-- ============================================================
-- THE CHAT PAGE: a Sound tab
-- ============================================================
local function AddTab(page, tab, label, build)
    if ns.AddPageTab then return ns.AddPageTab(page, tab, label, build) end
    ns.PageTabs = ns.PageTabs or {}
    local list = ns.PageTabs[page] or {}
    ns.PageTabs[page] = list
    list[#list + 1] = { tab = tab, label = label, build = build }
end

AddTab("chat", "sound", "Sound", function(L)
    if ns.FeatureOn and not ns.FeatureOn("whisper_sound") then return end
    local UI = ns.UI
    local d = DB()
    L:Card("Whispers")
    local on = UI.Checkbox(L.current, "Play a sound when a whisper arrives", WS.On(), function(v)
        d.whisperSound = v and true or nil
        WS.Apply()
        if ns.RefreshConfig then ns.RefreshConfig() end
    end, { tooltip = "Whispers and Battle.net whispers. The W button on the chat bar glows either way." })
    L:Row(on, 17)
    local kids = {}
    if UI.SoundSpecPicker and ns.CustomAccess then
        local get, set = ns.CustomAccess(DB, "sounds", "whisper")
        local sp = UI.SoundSpecPicker(L.current, { get = get, set = set, defaults = WS.DEFAULTS,
            width = UI.CardInnerWidth and UI.CardInnerWidth(L) or nil })
        kids[#kids + 1] = sp
    end
    kids[#kids + 1] = UI.Checkbox(L.current, "Quiet the game's own whisper blip", WS.MuteGame(), function(v)
        if v then d.whisperMute = nil else d.whisperMute = false end
        WS.Apply()
    end, { tooltip = "The game plays a blip of its own on every whisper; with yours on, that one is muted so a "
        .. "whisper does not sound twice. It comes back the moment this is off." })
    kids[#kids + 1] = UI.Button(L.current, "Test", { width = 80,
        tooltip = "Plays the whisper sound the way a whisper would.",
        onClick = function() WS.Play(true) end })
    L:Dependent(kids, WS.On(), 1, nil, "Play a sound when a whisper arrives")
    L:Desc("Nothing picked plays a chime. Pick \"Message\" for the game's own whisper blip.")
    L:EndCard()
end)

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("chat", "whisper sound alert tell bnet battle.net ping noise")
end
