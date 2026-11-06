-- ============================================================================
-- ZacUF - ShoutAlert.lua
-- AoE-taunt alert: when a group member lands Challenging Shout (or the druid
-- twin, Challenging Roar), every visible frame showing that person gets a
-- bright glow round the whole frame with a countdown of the taunt's 6s, and
-- TTS calls out "<name> challenging shout" - the safe-to-sapper/dynamite
-- window.
--
-- Detection is SPELL_CAST_SUCCESS from ZacUI's shared combat-log reader
-- (ns.CLEU), not per-frame events: one shout lights every frame showing
-- the caster - their raid slot, party slot, target, ToT - via a GUID sweep of
-- ns.unitButtons. Era and TBC share the IDs (one rank each); the name
-- fallback covers a client that hides IDs. WoW Forever has no combat log:
-- see the cast-event path at the bottom.
-- ============================================================================
local ADDON, ns = ...

-- What counts as an AoE taunt. Duration is the aura's 6s on both.
local TAUNTS = {
    [1161] = { text = "challenging shout", dur = 6 },   -- Warrior
    [5209] = { text = "challenging roar",  dur = 6 },   -- Druid (bear)
}

-- Name fallback in case this client's combat log hides spell IDs (id == 0) -
-- same dual-path stance as the scanAura shim: never assume, cover both.
-- Built from GetSpellInfo so it's locale-correct, with English literals as a
-- last resort if the ID lookup itself returns nothing.
local TAUNT_NAMES = {}
do
    for id, info in pairs(TAUNTS) do
        local n = GetSpellInfo and GetSpellInfo(id)
        if n then TAUNT_NAMES[n] = info end
    end
    TAUNT_NAMES["Challenging Shout"] = TAUNT_NAMES["Challenging Shout"] or TAUNTS[1161]
    TAUNT_NAMES["Challenging Roar"]  = TAUNT_NAMES["Challenging Roar"]  or TAUNTS[5209]
end

-- ----------------------------------------------------------------------------
-- TTS - compact version of the shape proven in Readycheck on this client
-- (1.15.9): SpeakText arg 4 is VOLUME, arg 5 is rate (0 = zero-speed, use 1);
-- destination 0 is the route that plays at full volume; push the system
-- speech volume before each line or the client quietly re-suppresses it.
-- ----------------------------------------------------------------------------
-- Voice picked by NAME from ns.db.tts.voice ("auto" = first female-sounding
-- voice, same hint list Readycheck uses; else the first voice). Cached until
-- the setting changes or a playback fails (voice list can change under us).
local FEMALE_HINTS = { "female", "samantha", "victoria", "karen", "moira", "fiona",
                       "zira", "hazel", "susan", "julie", "kate", "emily", "siri" }
local ttsVoice

function ns.TTSVoices()
    local v = C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices()
    return type(v) == "table" and v or {}
end

local function ttsVoiceId()
    -- the one voice picked on ZacUI's General page (2026-10-28)
    local Z = _G.ZacUI
    if Z and Z.VoiceId then return Z.VoiceId() end
    if ttsVoice then return ttsVoice end
    local voices = ns.TTSVoices()
    local want = ns.db and ns.db.tts and ns.db.tts.voice or "auto"
    ttsVoice = (voices[1] and voices[1].voiceID) or 0
    if want ~= "auto" then
        for _, v in ipairs(voices) do
            if v.name == want then ttsVoice = v.voiceID; return ttsVoice end
        end
        -- saved voice not installed on this machine: fall through to auto
    end
    for _, v in ipairs(voices) do
        local n = (v.name or ""):lower()
        for _, h in ipairs(FEMALE_HINTS) do
            if n:find(h, 1, true) then ttsVoice = v.voiceID; return ttsVoice end
        end
    end
    return ttsVoice
end

function ns.SetTTSVoice(name)
    ns.db.tts.voice = name or "auto"
    ttsVoice = nil
end

do
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "VOICE_CHAT_TTS_PLAYBACK_FAILED")
    f:SetScript("OnEvent", function() ttsVoice = nil end)
end

local lastSpoke, waiting = 0, nil
local function speak(text, force)
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then return end
    local now = GetTime()
    -- two lines inside 2s would garble each other: the second waits for
    -- the first instead of being dropped (a low-health line right after a
    -- shout alert used to vanish); a third while one waits replaces it
    if not force and now - lastSpoke < 2 then
        local again = not waiting
        waiting = text
        if again then
            C_Timer.After(2 - (now - lastSpoke) + 0.05, function()
                local t = waiting
                waiting = nil
                if t then speak(t, true) end
            end)
        end
        return
    end
    lastSpoke = now
    if C_TTSSettings and C_TTSSettings.SetSpeechVolume then
        pcall(C_TTSSettings.SetSpeechVolume, 100)
    end
    pcall(C_VoiceChat.SpeakText, ttsVoiceId(), text, 0, 100, 1)
end
ns.Speak = speak   -- shared TTS route (LowHealth.lua uses it too)

-- ----------------------------------------------------------------------------
-- Frame glow + countdown
-- ----------------------------------------------------------------------------
-- The glow round the whole frame (Glows.lua's ns.Glow, the same family as
-- the dispel glow: by default the warrior HUD's soft edge glow, brighter,
-- with the wide halo), on a host above the status icons so the countdown -
-- the seconds left of the six - is never covered. Built lazily: raid frames
-- that never see a shout never pay for it.
--
-- Its look is shoutAlert's own glow settings (style, strength, reach, wide
-- halo, pulse...; the shape is in Glows.lua), its colour shoutAlert.color.
-- The old look is the "Tint only" style, which still throbs by
-- shoutAlert.anim (a ZacUI animation) as it always did.
local DEFAULT_COLOR = { 1, 0.45, 0.05, 0.9 }                          -- hot orange
local DEFAULT_ANIM = { style = "flash", duration = 1.6, easing = "linear", loop = true }

-- where the countdown sits on the frame
local COUNT_SPOT = {
    CENTER = { 0, 0 }, TOP = { 0, -2 }, BOTTOM = { 0, 2 }, LEFT = { 3, 0 }, RIGHT = { -3, 0 },
    TOPLEFT = { 3, -2 }, TOPRIGHT = { -3, -2 }, BOTTOMLEFT = { 3, 2 }, BOTTOMRIGHT = { -3, 2 },
}
ns.COUNT_POINTS = {
    { value = "CENTER", text = "Centre" }, { value = "TOP", text = "Top" }, { value = "BOTTOM", text = "Bottom" },
    { value = "LEFT", text = "Left" }, { value = "RIGHT", text = "Right" },
    { value = "TOPLEFT", text = "Top left" }, { value = "TOPRIGHT", text = "Top right" },
    { value = "BOTTOMLEFT", text = "Bottom left" }, { value = "BOTTOMRIGHT", text = "Bottom right" },
}

local function sdb() return ns.db and ns.db.shoutAlert end

-- The countdown's OnUpdate (only while the glow shows, only with the
-- countdown on). The text changes once a second (once a tenth with tenths
-- on); in between it costs one subtraction.
local function countTick(self)
    local left = (self.endT or 0) - GetTime()
    local fs = self.count
    if left <= 0 then
        if self._ck ~= 0 then self._ck = 0 fs:SetText("") end
        return
    end
    -- (a hair under, so a fresh 6 s reads 6, not 7 from float dust)
    local k = self._tenths and math.ceil(left * 10 - 1e-6) or math.ceil(left - 1e-6)
    if k ~= self._ck then
        self._ck = k
        if self._tenths then fs:SetFormattedText("%.1f", k / 10) else fs:SetFormattedText("%d", k) end
    end
end

-- the countdown's font (ZacUI's font shape, db.fonts.tauntCount, 16 and
-- outlined by default), colour, spot and on / off
local function styleCount(g)
    local db = sdb()
    local fs = g.count
    if ns.ApplyFont then ns.ApplyFont(fs, "tauntCount")
    else pcall(fs.SetFont, fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 16, "OUTLINE") end
    local c = db and type(db.countColor) == "table" and db.countColor
    if c then fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1) else fs:SetTextColor(1, 1, 1, 1) end
    local point = (db and COUNT_SPOT[db.countPoint]) and db.countPoint or "CENTER"
    local o = COUNT_SPOT[point]
    fs:ClearAllPoints()
    fs:SetPoint(point, g, point, o[1], o[2])
    g._tenths = (db and db.countTenths) and true or false
    g._ck = nil
    local on = not (db and db.countdown == false)
    if on then fs:Show() else fs:Hide() end
    g:SetScript("OnUpdate", on and countTick or nil)
end

local function getGlow(frame)
    local had = rawget(frame, "ShoutGlow")
    if had then return had end
    if not (frame.Overlay and ns.Glow) then return nil end
    local g = ns.Glow.New(frame, 11, "tauntGlow")
    local fs = g:CreateFontString(nil, "OVERLAY")
    fs._zElement = "tauntCount"
    g.count = fs
    frame.ShoutGlow = g
    return g
end

-- style, look and colour from the settings (also on any settings change
-- while it shows: ns.ShoutGlowRestyle, called by Glows.lua's restyle)
local function paint(g)
    local db = sdb()
    local c = (db and type(db.color) == "table") and db.color or DEFAULT_COLOR
    ns.Glow.Configure(g, db, c[1] or 1, c[2] or 0.45, c[3] or 0.05, c[4] or 0.9)
    -- the old wash keeps its own throb
    local tint = g.spec.style == "tint"
    g.motionSpec = tint and ((db and type(db.anim) == "table") and db.anim or DEFAULT_ANIM) or nil
    styleCount(g)
end

local function stopGlow(frame, g)
    ns.Glow.Stop(g)
    g.endT = nil
    if ns.DispelGlowDecide then ns.DispelGlowDecide(frame) end   -- the dispel glow comes back
end

-- Light one frame for dur seconds. A per-frame generation counter makes a
-- second shout inside the window simply extend it - the stale timer sees a
-- newer generation and does nothing. Any frame with an Overlay will do: the
-- settings preview lights its sample frames through this too.
local function glowFrame(frame, dur)
    local g = getGlow(frame)
    if not g then return end
    paint(g)
    frame._shoutGen = (frame._shoutGen or 0) + 1
    local gen = frame._shoutGen
    g.endT = GetTime() + dur
    g._ck = nil
    ns.Glow.Start(g, g.motionSpec)
    if g.count:IsShown() then countTick(g) end
    -- the taunt wins: a dispel glow on this frame steps aside for it
    if ns.DispelGlowDecide then ns.DispelGlowDecide(frame) end
    C_Timer.After(dur, function()
        if frame._shoutGen == gen then stopGlow(frame, g) end
    end)
end
ns.ShoutGlowFrame = glowFrame

-- a setting changed while a glow shows: the new look at once
function ns.ShoutGlowRestyle(frame)
    local g = rawget(frame, "ShoutGlow")
    if not g then return end
    if g:IsShown() then
        paint(g)
        ns.Glow.Repulse(g)
    end
end

-- Put a frame's glow out now (the preview, when it changes what it shows).
function ns.ShoutGlowOff(frame)
    local g = frame and rawget(frame, "ShoutGlow")
    if not g then return end
    frame._shoutGen = (frame._shoutGen or 0) + 1
    stopGlow(frame, g)
end

-- Every visible frame currently showing this GUID (mocks carry no .unit and
-- fall out, same as ns.GetUnitFrame). With no readable GUID (Forever), the
-- unit token itself.
local function glowByGUID(guid, dur, unit)
    if not ns.unitButtons then return end
    for f in pairs(ns.unitButtons) do
        if f.unit and f:IsVisible() then
            local same
            if guid then
                same = UnitGUID(f.unit) == guid
            elseif unit then
                local ok, r = pcall(UnitIsUnit, f.unit, unit)
                same = ok and r == true
            end
            if same then glowFrame(f, dur) end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Detection
-- ----------------------------------------------------------------------------
local AFFIL_GROUP = (COMBATLOG_OBJECT_AFFILIATION_MINE  or 0x1)
                  + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2)
                  + (COMBATLOG_OBJECT_AFFILIATION_RAID  or 0x4)

-- Shared by the watchers and the /zuf shout test. unit: the caster's
-- token, used only when the GUID is not readable (Forever).
function ns.ShoutAlertFire(guid, name, info, unit)
    local db = ns.db and ns.db.shoutAlert
    if guid or unit then glowByGUID(guid, info.dur, unit) end
    if db and db.tts then
        local short = (name and name:match("^[^-]+")) or "someone"   -- strip -Realm
        speak(short .. " " .. info.text)
    end
end

function ns.ShoutAlertTest()
    ns.ShoutAlertFire(UnitGUID("player"), UnitName("player"), TAUNTS[1161])
    ns.Print("Shout alert test - your frames glow 6s + TTS line.")
end

local CLEU = _G.ZacUI.CLEU
local CLEU_KEY = "ZacUF.ShoutAlert"

local function OnCast(_, _, _, srcGUID, srcName, srcFlags, _, _, _, _, _, spellId, spellName)
    local db = ns.db and ns.db.shoutAlert
    if not (db and db.enabled) then return end
    if bit.band(srcFlags or 0, AFFIL_GROUP) == 0 then return end     -- group members (incl. you) only
    local info = TAUNTS[spellId]
        or ((not spellId or spellId == 0) and spellName and TAUNT_NAMES[spellName])
    if not info then return end
    ns.ShoutAlertFire(srcGUID, srcName, info)
end

-- WoW FOREVER has no combat log for addons. There the cast is seen through
-- UNIT_SPELLCAST_SUCCEEDED on you and your group (raidN / partyN /
-- player), when the game lets an addon read the spell ID; a secret ID,
-- GUID or name is skipped (nothing happens, no errors). One cast reaches
-- every token that names the caster (player and raid5), so a repeat of the
-- same cast - same cast GUID, or the same caster within a second - is
-- dropped. Era and TBC keep the combat log: it sees the whole raid.
local isSecret = issecretvalue
local function secret(v) return isSecret ~= nil and isSecret(v) and true or false end
local function groupToken(unit)
    if unit == "player" then return true end
    return type(unit) == "string" and (unit:find("^raid%d") or unit:find("^party%d")) and true or false
end
local lastCast, lastGUID, lastAt
local function OnUnitCast(_, _, unit, castGUID, spellId)
    local db = ns.db and ns.db.shoutAlert
    if not (db and db.enabled) then return end
    if secret(unit) or secret(spellId) or not groupToken(unit) then return end
    local info = TAUNTS[spellId]
    if not info then return end
    local guid = UnitGUID(unit)
    if secret(guid) then guid = nil end
    if secret(castGUID) then castGUID = nil end
    local now = GetTime()
    if castGUID and castGUID == lastCast then return end
    if guid and guid == lastGUID and now - (lastAt or 0) < 1 then return end
    lastCast, lastGUID, lastAt = castGUID, guid, now
    local name = UnitName(unit)
    if secret(name) then name = nil end
    ns.ShoutAlertFire(guid, name, info, unit)
end
local castWatch = CreateFrame("Frame")
castWatch:SetScript("OnEvent", OnUnitCast)

-- which signal this client has (looked up each time: a test can switch it)
local function useCastEvent()
    if _G.ZACUI_IS_FOREVER == true or CombatLogGetCurrentEventInfo == nil then return true end
    -- Forever's rules under ZacUI's game-version override too (Core_Flavor)
    local Z = _G.ZacUI
    return (Z and Z.NoCombatLog and Z.NoCombatLog()) and true or false
end

-- The combat log (or the cast event) is only listened to while the alert
-- is on; the options checkbox calls ns.ShoutAlertApply after flipping it.
function ns.ShoutAlertApply()
    local db = ns.db and ns.db.shoutAlert
    local on = db and db.enabled
    if on and not useCastEvent() then CLEU.On(CLEU_KEY, "SPELL_CAST_SUCCESS", OnCast)
    else CLEU.Off(CLEU_KEY) end
    if on and useCastEvent() then pcall(castWatch.RegisterEvent, castWatch, "UNIT_SPELLCAST_SUCCEEDED")
    else castWatch:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED") end
end
local applyOnce = CreateFrame("Frame")
applyOnce:RegisterEvent("PLAYER_LOGIN")
applyOnce:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- the settings table is built by Core's own PLAYER_LOGIN; a frame
    -- later is always after it
    C_Timer.After(0, ns.ShoutAlertApply)
end)
