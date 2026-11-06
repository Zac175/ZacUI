-- Core_Sounds - what a sound setting means, and how it is played.
-- Part of ZacUI; load order is set by the TOC (after Core_MediaNames).
--
-- ZacUI ships no sound files of its own. A sound is one of three things:
--   "ui:Pop"         one of the game's own interface sounds, under a plain
--                    name (the list below); played with PlaySound
--   "tts:Move out"   words, spoken with the game's text-to-speech
--   a file path      a file some other addon carries (SharedMedia names
--                    resolve to these too); played with PlaySoundFile
-- A number is a sound kit id. nil, "" and "none" are silence.
--
-- ns.PlaySoundRef(ref, channel, speak) plays any of them; ns.RaidSound is
-- the same function under the name the raid code uses. ns.ResolveSoundRef
-- says what a reference means without playing it.
--
-- THE LEGACY BRIDGE. The raid packs once came with a folder of voice
-- lines, interface blips and joke clips, and settings and auras saved
-- then still name those files - by path, or by the SharedMedia name they
-- were registered under. The folder is gone; each old reference is read
-- by what the file was: a spoken line becomes the same words through
-- text-to-speech, a blip becomes the matching game sound, a joke clip
-- becomes silence. The old pack textures go the same way
-- (ns.LegacyTexture): boss icons become the game's icons, shapes become
-- ZacUI's own, joke pictures become nothing.

local ADDON_NAME, ns = ...

local S = {}
ns.Sounds = S

-- ============================================================
-- THE GAME'S OWN SOUNDS, BY PLAIN NAME
-- ============================================================
-- Each has the SOUNDKIT names to try in order. A name this client does
-- not know falls back to a safe sound of the same weight: a blip to the
-- tick-box click, a loud one to the raid warning. Never an error.
local UI = {
    { name = "Pop",      kits = { "IG_MAINMENU_OPTION_CHECKBOX_ON" } },
    { name = "Pop 2",    kits = { "IG_CHARACTER_INFO_TAB" } },
    { name = "Pop 3",    kits = { "U_CHAT_SCROLL_BUTTON" } },
    { name = "Click",    kits = { "IG_MAINMENU_OPTION" } },
    { name = "Snap",     kits = { "IG_MAINMENU_OPTION_CHECKBOX_OFF" } },
    { name = "Ting",     kits = { "MAP_PING" } },
    { name = "Swoosh",   kits = { "IG_SPELLBOOK_OPEN" } },
    { name = "Drop",     kits = { "IG_BACKPACK_CLOSE" } },
    { name = "Coin",     kits = { "LOOT_WINDOW_COIN_SOUND" } },
    { name = "Message",  kits = { "TELL_MESSAGE" } },
    { name = "Notice",   kits = { "IG_PLAYER_INVITE" } },
    { name = "Chime",    kits = { "UI_BNET_TOAST", "IG_PLAYER_INVITE" } },
    { name = "Bell",     kits = { "READY_CHECK" }, loud = true },
    { name = "Beep",     kits = { "ALARM_CLOCK_WARNING_2", "ALARM_CLOCK_WARNING_3" } },
    { name = "Alarm",    kits = { "ALARM_CLOCK_WARNING_3", "RAID_WARNING" }, loud = true },
    { name = "Warning",  kits = { "RAID_BOSS_EMOTE_WARNING", "RAID_WARNING" }, loud = true },
    { name = "Air horn", kits = { "RAID_WARNING" }, loud = true },
    { name = "Fail",     kits = { "IG_QUEST_LOG_ABANDON_QUEST", "IG_PLAYER_INVITE_DECLINE" } },
}
S.UI = UI
local UI_BY = {}
for _, u in ipairs(UI) do UI_BY[u.name:lower()] = u end

-- the safe ones (by number too, for a client with no SOUNDKIT table)
local SAFE_BLIP, SAFE_LOUD = 856, 8959

-- the sound kit id for a plain name ("Pop"), or nil when it is not one
function S.Kit(name)
    local u = type(name) == "string" and UI_BY[name:lower()]
    if not u then return nil end
    local kits = _G.SOUNDKIT
    if type(kits) == "table" then
        for _, k in ipairs(u.kits) do
            if tonumber(kits[k]) then return tonumber(kits[k]) end
        end
        if u.loud then return tonumber(kits.RAID_WARNING) or SAFE_LOUD end
        return tonumber(kits.IG_MAINMENU_OPTION_CHECKBOX_ON) or SAFE_BLIP
    end
    return u.loud and SAFE_LOUD or SAFE_BLIP
end

-- the pickers' list: { text = "Pop", value = "ui:Pop" }, ...
function S.PickerItems()
    local out = {}
    for _, u in ipairs(UI) do out[#out + 1] = { text = u.name, value = "ui:" .. u.name } end
    return out
end

-- ============================================================
-- THE OLD PACK FILES
-- ============================================================
-- Interface blips, by the old file name (lower case, no extension).
local OLD_UI = {
    ["fojjipop1"] = "Pop", ["fojjimultipop"] = "Pop",
    ["fojjipop2"] = "Pop 2", ["fojjimultipop2"] = "Pop 2",
    ["fojjipop3"] = "Pop 3", ["heart"] = "Pop 3",
    ["fojjipopclick"] = "Click", ["click"] = "Click", ["clicktts"] = "Click", ["ratchet"] = "Click",
    ["fojjisnap"] = "Snap",
    ["fojjiting"] = "Ting", ["bright ting"] = "Ting", ["sonicring"] = "Ting", ["link"] = "Ting",
    ["fojjiswoosh"] = "Swoosh",
    ["fojjidrop"] = "Drop",
    ["kachink"] = "Coin", ["cashregister"] = "Coin", ["mario coin"] = "Coin",
    ["fojjimsg"] = "Message", ["im"] = "Message", ["text1"] = "Message", ["text2"] = "Message",
    ["info"] = "Notice", ["notification"] = "Notice", ["newnotification"] = "Notice",
    ["smooth notify"] = "Notice", ["fojjisoftnotice"] = "Notice",
    ["chime"] = "Chime",
    ["bell"] = "Bell", ["bell notification"] = "Bell", ["bell realistic"] = "Bell", ["gong"] = "Bell",
    ["beep"] = "Beep", ["sharp bleep"] = "Beep",
    ["alarmbeep"] = "Alarm", ["door alarm"] = "Alarm",
    ["alert5"] = "Warning", ["fireball"] = "Warning",
    ["airhorn"] = "Air horn",
    ["fojjiogredeath"] = "Fail", ["fojjivideogamedeath"] = "Fail",
}
-- Joke clips and music: silence.
local OLD_MEME = {}
for _, n in ipairs({
    "8bitloselife", "bananapeelslip", "blowitout", "bombhasbeenplanted", "bowlingpins", "bruh",
    "clevergirl", "dinosaureat", "dinosaureat2", "dinosaurroar", "fbiopenup", "foji", "furtherbeyond",
    "garymeow", "gasp", "hallelujah", "hallelujahshort", "heavenly", "homealabama", "hothothot",
    "itsjustafleshwound", "jackinthebox", "joardeeimafuckinggamer", "joardeelosingmymind",
    "joardeemassivethingonass", "jurassicparktheme", "leeroy", "lifeuhfindsaway", "lightsaber",
    "loudnoises", "manscreaming", "mario-jump", "mariojump", "mariokartracestart",
    "mariolevelcomplete", "marioshell", "marioslide", "marioyoshi", "metalgearalert", "newb",
    "numen", "ohno", "ohshitohshit", "omelete time", "retroshot", "run", "sadtrombone",
    "shadechant", "snooploot", "snooplootman", "springjump", "squish", "terroristswin",
    "tetsu5sunders", "tetsudeadactually", "theyaskmeme", "tisbutascratch", "tpirlosehorn", "uwu",
    "welcometojurassicpark", "wilheimscream", "yesyesbison", "zeldachest",
}) do OLD_MEME[n] = true end

-- How a spoken line's file name is said, where reading it out as written
-- would sound wrong.
local SAY = {
    ["healcd"] = "Heal cooldown", ["selfcd"] = "Self cooldown", ["cd"] = "Cooldown",
    ["tox etron"] = "Toxitron", ["d sac"] = "D sac", ["d sac soon"] = "D sac soon",
}

-- "Berserk Soon" -> "Berserk soon"; "Phase2" -> "Phase 2"; "07" -> "7".
-- Words with more than one capital (AoE, BoP, MC) keep their capitals.
function S.Words(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower()
    if SAY[key] then return SAY[key] end
    local s = name:gsub("(%l)(%d)", "%1 %2"):gsub("^0+(%d)", "%1")
    local out, first = {}, true
    for w in s:gmatch("%S+") do
        local caps = select(2, w:gsub("%u", ""))
        if not first and caps <= 1 then w = w:lower() end
        out[#out + 1] = w
        first = false
    end
    return table.concat(out, " ")
end

-- The folders the pack media lived in. Paths are compared lower case with
-- forward slashes turned back.
local OLD_SOUND_DIRS = {
    "interface\\addons\\fojjicore\\sound\\",
    "interface\\addons\\zacui_fojji\\sound\\",
    "interface\\addons\\zacui_raidmods\\media\\",
}
local function Norm(p) return (p:lower():gsub("/", "\\"):gsub("\\+", "\\")) end
local function BaseName(p) return ((p:match("([^\\]+)$") or p):gsub("%.%w+$", "")) end

-- the old file a path names (its base name, lower case), or nil
local function OldSoundFile(path)
    local n = Norm(path)
    for _, dir in ipairs(OLD_SOUND_DIRS) do
        if n:sub(1, #dir) == dir then
            local rest = n:sub(#dir + 1)
            if not rest:find("\\", 1, true) then
                return BaseName(rest), BaseName(path:gsub("/", "\\"))
            end
        end
    end
    return nil
end

-- what an old file was: "kit", id | "tts", words | "none"
local function OldSound(low, asWritten)
    if OLD_UI[low] then return "kit", S.Kit(OLD_UI[low]) end
    if OLD_MEME[low] or low:find("^ragnaros.*_%a%a$") then return "none" end
    -- in the raid mods' own folder only the blips and memes above lived
    return "tts", S.Words(asWritten)
end

-- The SharedMedia names the old folder registered: "fojji Pop1",
-- "fojji |cFFFF0000Berserk|r", "fojjiMeme |cFFFF0000Bruh|r" ... -> the file.
local OLD_LSM = {
    ["alarm beep"] = "alarmbeep", ["bell: notification"] = "bell notification",
    ["bell: realistic"] = "bell realistic", ["drop"] = "fojjidrop", ["msg"] = "fojjimsg",
    ["multipop"] = "fojjimultipop", ["multipop2"] = "fojjimultipop2",
    ["new notification"] = "newnotification", ["ogre death"] = "fojjiogredeath",
    ["pop1"] = "fojjipop1", ["pop2"] = "fojjipop2", ["pop3"] = "fojjipop3",
    ["popclick"] = "fojjipopclick", ["snap"] = "fojjisnap", ["softnotice"] = "fojjisoftnotice",
    ["sonic ring"] = "sonicring", ["swoosh"] = "fojjiswoosh", ["ting"] = "fojjiting",
    ["video game death"] = "fojjivideogamedeath", ["light saber"] = "lightsaber",
}
local function OldLSMName(name)
    local meme = name:find("^[Ff][Oo][Jj][Jj][Ii][Mm][Ee][Mm][Ee] ") ~= nil
    local rest = name:match("^[Ff][Oo][Jj][Jj][Ii] (.+)$") or name:match("^[Ff][Oo][Jj][Jj][Ii][Mm][Ee][Mm][Ee] (.+)$")
    if not rest then return nil end
    rest = rest:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
    if meme then return "none" end
    local low = OLD_LSM[rest:lower()] or rest:lower()
    return OldSound(low, rest)
end

-- ============================================================
-- RESOLVING AND PLAYING
-- ============================================================
local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end
local function IsPath(s) return s:find("\\", 1, true) or s:find("/", 1, true) end

-- what a reference means: "kit", id | "tts", words | "file", path |
-- nil (silence)
function S.Resolve(ref)
    if type(ref) == "number" then return "kit", ref end
    if type(ref) ~= "string" then return nil end
    local s = ref:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" or s:lower() == "none" then return nil end
    local tag, rest = s:match("^(%a+):(.*)$")
    if tag then
        tag = tag:lower()
        if tag == "tts" then return (rest ~= "" and "tts" or nil), (rest ~= "" and rest or nil) end
        if tag == "ui" then
            local id = S.Kit(rest)
            if id then return "kit", id end
            return nil
        end
        if tag == "kit" and tonumber(rest) then return "kit", tonumber(rest) end
    end
    if tonumber(s) then return "kit", tonumber(s) end
    if IsPath(s) then
        local low, asWritten = OldSoundFile(s)
        if low then
            local kind, v = OldSound(low, asWritten)
            if kind == "none" then return nil end
            return kind, v
        end
        return "file", s
    end
    -- a plain name: one of the game sounds, an old pack name, or a
    -- SharedMedia name some addon registered
    local id = S.Kit(s)
    if id then return "kit", id end
    local kind, v = OldLSMName(s)
    if kind then
        if kind == "none" then return nil end
        return kind, v
    end
    local lsm = LSM()
    local f = lsm and lsm:Fetch("sound", s, true)
    if f and f ~= "" and f ~= 1 then
        if type(f) == "number" then return "file", f end
        if f:lower():find("sound\\interface\\none") or f:lower():find("sound/interface/none") then return nil end
        return S.Resolve(f)
    end
    return nil
end
ns.ResolveSoundRef = S.Resolve

-- true when a reference names something from the old pack folders
function S.IsLegacy(ref)
    if type(ref) ~= "string" then return false end
    if IsPath(ref) then return OldSoundFile(ref) ~= nil end
    return ref:lower():find("^fojji") ~= nil
end

-- the words spoken when nothing else is asked for: ZacUI's one voice
-- (Zacui_UnitFrames), else the game's first voice
local function DefaultSpeak(words)
    if ns.Speak then return ns.Speak(words, true) end
    if C_VoiceChat and C_VoiceChat.SpeakText then
        pcall(C_VoiceChat.SpeakText, 0, words, 0, 75, 1)
    end
end
S.DefaultSpeak = DefaultSpeak

-- plays a reference; returns played, handle (handle only for kits and files)
function S.Play(ref, channel, speak)
    local kind, v = S.Resolve(ref)
    if not kind then return false end
    channel = (type(channel) == "string" and channel ~= "") and channel or "Master"
    if kind == "kit" then
        if not PlaySound then return false end
        local ok, played, handle = pcall(PlaySound, v, channel)
        return ok and played and true or false, ok and handle or nil
    elseif kind == "file" then
        if not PlaySoundFile then return false end
        local ok, played, handle = pcall(PlaySoundFile, v, channel)
        return ok and played and true or false, ok and handle or nil
    elseif kind == "tts" then
        pcall(speak or DefaultSpeak, v)
        return true
    end
    return false
end
ns.PlaySoundRef = S.Play
ns.RaidSound = S.Play

-- ============================================================
-- THE OLD PACK TEXTURES
-- ============================================================
local RM_OWN = "Interface\\AddOns\\Zacui_RaidMods\\Media\\Own\\"
local ICONS = "Interface\\Icons\\"
local ZACUI_ICON = "Interface\\AddOns\\ZacUI\\Media\\addonIcon"
local FLAT = "Interface\\Buttons\\WHITE8X8"
local M = "Interface\\AddOns\\ZacUI\\Media\\"

-- the raid mods' shapes, by old name -> ZacUI's own (false = nothing)
local RM_SHAPES = {
    ["aura3"] = RM_OWN .. "glow_sides", ["aura7"] = RM_OWN .. "chevrons_in",
    ["aura34"] = RM_OWN .. "arrow_circle", ["aura72"] = RM_OWN .. "disc_soft",
    ["circle_white_border"] = RM_OWN .. "circle_rim", ["circle_white"] = RM_OWN .. "circle",
    ["square_white"] = FLAT,
    ["ring_10px"] = RM_OWN .. "ring_10", ["ring_20px"] = RM_OWN .. "ring_20",
    ["ring_30px"] = RM_OWN .. "ring_30", ["ring_40px"] = RM_OWN .. "ring_40",
    ["aura113"] = false, ["rainbowbar"] = false,
}
-- Naxxramas boss icons, by encounter -> the boss's signature spell
local NAXX = {
    ["1107"] = "Spell_Nature_InsectSwarm",          -- Anub'Rekhan: Locust Swarm
    ["1108"] = "Ability_Druid_DemoralizingRoar",    -- Gluth: Terrifying Roar
    ["1109"] = "Spell_Shadow_RaiseDead",            -- Gothik the Harvester
    ["1110"] = "Spell_Shadow_RainOfFire",           -- Grand Widow Faerlina: Rain of Fire
    ["1111"] = "Spell_Nature_CorrosiveBreath",      -- Grobbulus: poison
    ["1112"] = "Spell_Shadow_PlagueCloud",          -- Heigan: Plague Cloud
    ["1113"] = "Ability_Warrior_BattleShout",       -- Razuvious: Disrupting Shout
    ["1114"] = "Spell_Frost_FrostNova",             -- Kel'Thuzad: frost
    ["1115"] = "Spell_Shadow_NightOfTheDead",       -- Loatheb: Inevitable Doom
    ["1116"] = "Spell_Nature_Web",                  -- Maexxna: Web Wrap
    ["1117"] = "Spell_Arcane_Blink",                -- Noth: Blink
    ["1118"] = "Ability_Warrior_DecisiveStrike",    -- Patchwerk: Hateful Strike
    ["1119"] = "Spell_Frost_FrostShock",            -- Sapphiron: frost breath
    ["1120"] = "Spell_Nature_Lightning",            -- Thaddius: Polarity Shift
    ["1121"] = "Ability_Mount_Undeadhorse",         -- the Four Horsemen
}
S.NAXX_ICONS = NAXX
-- the bar textures that sat in the old folder
local OLD_BARS = {
    ["melli"] = M .. "Textures\\bar_flat", ["fojjimelli"] = M .. "Textures\\bar_flat",
    ["fojjiflat"] = FLAT, ["fojjiblank"] = FLAT, ["fojjikui"] = M .. "normTex",
}
-- joke pictures and the pack's own logos in its top folder
local OLD_PICTURES = {}
for _, n in ipairs({ "bashful", "bowling", "joardepog", "joardeekid", "lightsaber", "mariocoin",
    "sombrerohat", "sonicring", "terrorists", "tetsupog", "tetsuhands", "weapon_c4", "nyan",
    "snowwhite", "tf", "back_1_overlay", "back_2_overlay", "left_1_overlay", "left_2_overlay",
    "right_1_overlay", "right_2_overlay", "shapagoda", "numop_gold_v2", "numop_green",
    "numop_sha_green256" }) do OLD_PICTURES[n] = false end
for _, n in ipairs({ "f_icon_green", "f_icon_orange", "f_icon_purple", "f_icon_teal", "f_icon_yellow",
    "fojjiblue", "fojjired", "nulogo_alliance", "discicon_nuhorde_v3anim", "discicon_nuhordev2",
    "discordicon_nuanim2_horde" }) do OLD_PICTURES[n] = ZACUI_ICON end
OLD_PICTURES["cast_shield"] = "Interface\\CastingBar\\UI-CastingBar-Small-Shield"
OLD_PICTURES["t_star3"] = "Interface\\Cooldown\\star4"
OLD_PICTURES["mask"], OLD_PICTURES["maskzero"] = FLAT, FLAT
-- the rest of the top folder were the game's spell alert overlays
local OVERLAY_NAME = { ["oldeclipse_moon"] = "eclipse_moon", ["oldeclipse_sun"] = "eclipse_sun",
    ["sudden_death_red"] = "sudden_death", ["brain_freeze2"] = "brain_freeze" }

local OLD_TEX_DIRS = {
    "interface\\addons\\fojjicore\\", "interface\\addons\\zacui_fojji\\",
}

-- A path from the old folders -> what replaces it: a path, or false for
-- "draw nothing". nil when the path is not an old one.
local NOT_OLD = {}
local texCache, texCached = {}, 0
local LegacyTextureUncached
function S.LegacyTexture(path)
    if type(path) ~= "string" or not IsPath(path) then return nil end
    -- textures are set on every refresh: each path is worked out once
    local c = texCache[path]
    if c == nil then
        c = LegacyTextureUncached(path)
        if c == nil then c = NOT_OLD end
        if texCached < 2000 then texCache[path] = c texCached = texCached + 1 end
    end
    if c == NOT_OLD then return nil end
    return c
end

LegacyTextureUncached = function(path)
    local n = Norm(path)
    local rm = n:match("^interface\\addons\\zacui_raidmods\\media\\([^\\]+)$")
    if rm then
        local v = RM_SHAPES[BaseName(rm)]
        if v == nil then return nil end
        return v
    end
    local rest
    for _, dir in ipairs(OLD_TEX_DIRS) do
        if n:sub(1, #dir) == dir then rest = n:sub(#dir + 1) break end
    end
    if not rest then return nil end
    local folder, file = rest:match("^([^\\]+)\\(.+)$")
    if not folder then return false end
    local base = BaseName(file)
    if folder == "statusbar" then
        return OLD_BARS[base] or FLAT
    elseif folder == "font" then
        return false
    elseif folder == "textures" then
        local sub, inner = file:match("^([^\\]+)\\(.+)$")
        if sub then
            if sub == "naxx pack icons" then
                local id = BaseName(inner):match("^(%d+)")
                return id and NAXX[id] and (ICONS .. NAXX[id]) or false
            end
            return false   -- Pepes, GuildEmotes, BTTV+FFZ, MemeArt
        end
        if OLD_PICTURES[base] ~= nil then return OLD_PICTURES[base] end
        return "Textures\\SpellActivationOverlays\\" .. (OVERLAY_NAME[base] or base)
    end
    return false
end
ns.LegacyTexture = S.LegacyTexture

-- a texture path with the old ones replaced ("" for nothing); anything
-- else comes back as it was
function S.Texture(path)
    local v = S.LegacyTexture(path)
    if v == nil then return path end
    return v or ""
end
