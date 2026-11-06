-- AE_Actions - what a display does when it shows and when it hides
-- (sounds, chat, glows on other frames, its own code), and how it moves
-- while doing so (its start / main / finish animations).
-- Part of ZacUI (Zacui_Auras). Written for ZacUI.
--
-- actions = { init = { do_custom, custom, do_custom_load, customOnLoad,
--                      do_custom_unload, customOnUnload },
--             start / finish = { do_message, message_type, message, message_dest,
--                      message_dest_isunit, message_custom, message_format_*,
--                      do_sound, sound, sound_channel, sound_path, sound_kit_id,
--                      do_loop, sound_repeat, stop_sound, do_custom, custom,
--                      do_glow, glow_action, glow_frame_type, glow_frame, glow_type,
--                      use_glow_color, glow_color, glow_lines, glow_frequency,
--                      glow_length, glow_thickness, glow_XOffset, glow_YOffset,
--                      glow_scale, glow_border, hide_all_glows } }
-- animation = { start / main / finish = { type = "none" | "preset" | "custom",
--                      preset, duration, duration_type ("seconds" | "relative"),
--                      easeType, easeStrength, use_translate, x, y, translateType,
--                      use_alpha, alpha, alphaType, use_scale, scalex, scaley,
--                      scaleType, use_rotate, rotate, rotateType, use_color,
--                      colorR, colorG, colorB, colorA, colorType, and the
--                      *Func code for the "custom" curve of each } }
local ns = _G.ZacUI
if not ns then return end
local E = ns.AuraEngine
if not E then return end

local Ac = {}
E.Actions = Ac
local Color = E.Color

-- the message kinds the format offers (and what each needs)
Ac.MESSAGE_TYPES = { WHISPER = true, SAY = true, EMOTE = true, YELL = true, PARTY = true, GUILD = true,
    OFFICER = true, RAID = true, SMARTRAID = true, RAID_WARNING = true, INSTANCE_CHAT = true, COMBAT = true,
    PRINT = true, ERROR = true, TTS = true }

-- ============================================================
-- SOUND
-- ============================================================
local function Fetch(sound)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    return LSM and LSM:Fetch("sound", sound, true) or sound
end

-- A name or a path goes through ZacUI's sound reference (Core_Sounds):
-- "ui:Pop" is a game sound, "tts:..." is spoken, and a path or name from
-- the old raid-pack media folder is read for what it was (a spoken line,
-- a blip, or silence for a joke clip).
local function PlayRef(ref, channel)
    if ns.PlaySoundRef then
        local played, handle = ns.PlaySoundRef(ref, channel)
        return played, handle
    end
    local file = Fetch(ref)
    if tonumber(file) then return select(2, pcall(PlaySound, tonumber(file), channel)) end
    local ok, played, handle = pcall(PlaySoundFile, file, channel)
    return ok and played, handle
end

local function PlayOnce(opts)
    local channel = opts.sound_channel
    if channel == nil or channel == "" then channel = "Master" end
    local ok, _, handle
    if opts.sound == " custom" then
        if not opts.sound_path or opts.sound_path == "" then return nil end
        ok, handle = PlayRef(opts.sound_path, channel)
    elseif opts.sound == " KitID" then
        local kit = tonumber(opts.sound_kit_id)
        if not kit then return nil end
        ok, _, handle = pcall(PlaySound, kit, channel)
    else
        if type(opts.sound) ~= "string" or opts.sound == "" then return nil end
        ok, handle = PlayRef(opts.sound, channel)
    end
    return ok and handle or nil
end

function Ac.SoundStop(r, fade)
    if r and r.soundHandle and StopSound then pcall(StopSound, r.soundHandle, fade or 0) end
    if r then r.soundHandle = nil end
    if r and r.soundRepeat then
        r.soundRepeat:Cancel()
        r.soundRepeat = nil
    end
end

-- opts: a start/finish action table or a condition's sound value
function Ac.SoundPlay(r, opts)
    if type(opts) ~= "table" then return end
    if E.optionsOpen and not E.soundsInOptions then return end
    if opts.sound_type == "Stop" then
        Ac.SoundStop(r, tonumber(opts.sound_fade) and opts.sound_fade * 1000 or 0)
        return
    end
    Ac.SoundStop(r)
    local handle = PlayOnce(opts)
    if r then r.soundHandle = handle end
    local loop = opts.do_loop or opts.sound_type == "Loop"
    local every = tonumber(opts.sound_repeat)
    if r and loop and every and every > 0 and every < 1e6 and C_Timer.NewTicker then
        r.soundRepeat = C_Timer.NewTicker(every, function() r.soundHandle = PlayOnce(opts) end)
    end
end

-- the plain name/channel form older code calls
function Ac.Sound(sound, channel)
    PlayOnce({ sound = sound, sound_channel = channel })
end

-- ============================================================
-- CHAT
-- ============================================================
local function InInstance() return IsInInstance and (IsInInstance()) or false end

function Ac.Message(r, text, kind, dest, channel, opts, destIsUnit, color, customFn)
    if type(text) ~= "string" or text == "" then return end
    opts = type(opts) == "table" and opts or {}
    local ctx = r and r.ctx or {}
    if customFn and r then
        local res = { E.Env.Run(r.id, customFn, r.state, E.states[r.id], r) }
        ctx = setmetatable({ custom = res }, { __index = ctx })
    end
    local msg = text:find("%%") and E.Text.Format(text, opts, "message", ctx) or text
    local cr, cg, cb = 1, 1, 1
    if type(color) == "table" then cr, cg, cb = Color(color)
    elseif type(opts.message_color) == "table" then cr, cg, cb = Color(opts.message_color)
    elseif opts.r then cr, cg, cb = opts.r, opts.g or 1, opts.b or 1 end
    kind = kind or "SAY"
    if kind == "PRINT" then
        DEFAULT_CHAT_FRAME:AddMessage(msg, cr, cg, cb)
    elseif kind == "ERROR" then
        if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, cr, cg, cb) end
    elseif kind == "TTS" then
        pcall(function()
            local voice = TextToSpeech_GetSelectedVoice and Enum and Enum.TtsVoiceType
                and TextToSpeech_GetSelectedVoice(Enum.TtsVoiceType.Standard)
            if voice and TextToSpeech_Speak then TextToSpeech_Speak(msg, voice)
            elseif C_VoiceChat and C_VoiceChat.SpeakText and voice then
                C_VoiceChat.SpeakText(voice.voiceID, msg, 0, 0, 100)
            end
        end)
    elseif kind == "COMBAT" then
        -- ZacUI's own scrolling text first. The game's combat text only with
        -- a real scroll function: a nil one makes its update throw every
        -- frame and freezes every line it shows ("-Combat" stuck on screen).
        local scroll = COMBAT_TEXT_SCROLL_FUNCTION or CombatText_StandardScroll
        local ok, shown = false, nil
        if ns.SBT and ns.SBT.Display then
            ok, shown = pcall(ns.SBT.Display, "notification", msg, { r = cr, g = cg, b = cb })
        end
        if ok and shown then
            -- shown
        elseif CombatText_AddMessage and type(scroll) == "function" then
            pcall(CombatText_AddMessage, msg, scroll, cr, cg, cb)
        end
    elseif kind == "WHISPER" then
        if dest and dest ~= "" then
            if dest:find("%%") then dest = E.Text.Format(dest, opts, "message", ctx) end
            if destIsUnit and GetUnitName then dest = GetUnitName(dest, true) or dest end
            pcall(SendChatMessage, msg, "WHISPER", nil, dest)
        end
    elseif kind == "SMARTRAID" then
        if UnitInBattleground and UnitInBattleground("player") then pcall(SendChatMessage, msg, "INSTANCE_CHAT")
        elseif (UnitInRaid and UnitInRaid("player")) or (IsInRaid and IsInRaid()) then pcall(SendChatMessage, msg, "RAID")
        elseif (UnitInParty and UnitInParty("player")) or (IsInGroup and IsInGroup()) then pcall(SendChatMessage, msg, "PARTY")
        elseif InInstance() then pcall(SendChatMessage, msg, "SAY") end
    elseif kind == "SAY" or kind == "YELL" then
        -- the game only lets addons speak inside instances
        if InInstance() then pcall(SendChatMessage, msg, kind) end
    elseif kind == "CHANNEL" then
        local num = channel and GetChannelName and GetChannelName(channel)
        if num and num > 0 then pcall(SendChatMessage, msg, "CHANNEL", nil, num) end
    else
        pcall(SendChatMessage, msg, kind)
    end
end

-- ============================================================
-- GLOWS ON OTHER FRAMES
-- ============================================================
local function GlowTarget(r, v)
    local kind = v.glow_frame_type
    local unit = r.state and r.state.unit
    if kind == "UNITFRAME" then
        return unit and E.UnitFrame(unit) or nil
    elseif kind == "NAMEPLATE" then
        return unit and C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit) or nil
    elseif kind == "PARENTFRAME" then
        return r:GetParent()
    elseif type(v.glow_frame) == "string" and v.glow_frame ~= "" then
        local name = v.glow_frame
        if name:sub(1, 10) == "WeakAuras:" then return E.regions[name:sub(11)] end
        local f = _G[name]
        if type(f) == "table" and f.GetObjectType then return f end
    end
    return nil
end

function Ac.FrameGlow(r, v, on)
    if type(v) ~= "table" then return end
    local target = GlowTarget(r, v)
    if not target then return end
    local key = "action:" .. tostring(r.id) .. ":" .. tostring(r.cloneId)
    if on and v.glow_action ~= "hide" then
        E.Glow.Show(target, { type = v.glow_type, color = v.use_glow_color and v.glow_color or nil,
            lines = v.glow_lines, frequency = v.glow_frequency, length = v.glow_length,
            thickness = v.glow_thickness, xOffset = v.glow_XOffset, yOffset = v.glow_YOffset,
            scale = v.glow_scale, border = v.glow_border, duration = v.glow_duration,
            startAnim = v.glow_startAnim }, key)
        r.glowed = r.glowed or {}
        r.glowed[target] = key
    else
        E.Glow.Hide(target, key)
        if r.glowed then r.glowed[target] = nil end
    end
end

local function UnglowAll(r)
    if r.glowed then
        for target, key in pairs(r.glowed) do E.Glow.Hide(target, key) end
        r.glowed = nil
    end
end

-- ============================================================
-- ON SHOW / ON HIDE
-- ============================================================
local function Run(r, phase)
    local a = r.d.actions and r.d.actions[phase]
    if type(a) ~= "table" then return end
    if a.do_message and a.message_type and a.message then
        local fn
        if a.message_custom and a.message_custom ~= "" then
            r.actionFns = r.actionFns or {}
            local k = phase .. "_message"
            fn = r.actionFns[k]
            if fn == nil then
                fn = E.Env.Function(r.id, a.message_custom, phase .. " message") or false
                r.actionFns[k] = fn
            end
        end
        Ac.Message(r, a.message, a.message_type, a.message_dest, a.message_channel, a, a.message_dest_isunit,
            nil, fn or nil)
    end
    if a.stop_sound then
        Ac.SoundStop(r, a.do_sound_fade and tonumber(a.stop_sound_fade) and a.stop_sound_fade * 1000 or 0)
    end
    if a.do_sound and a.sound then Ac.SoundPlay(r, a) end
    if a.do_custom and a.custom and a.custom ~= "" then
        r.actionFns = r.actionFns or {}
        local fn = r.actionFns[phase]
        if fn == nil then
            fn = E.Env.Body(r.id, a.custom, phase .. " action") or false
            r.actionFns[phase] = fn
        end
        if fn then E.Env.Run(r.id, fn, r.state, E.states[r.id], r) end
    end
    if a.do_glow then
        if a.glow_action == "hide" then Ac.FrameGlow(r, a, false)
        else Ac.FrameGlow(r, a, true) end
    end
    if phase == "finish" and a.hide_all_glows then UnglowAll(r) end
end
Ac.Run = Run

-- ============================================================
-- ANIMATION CURVES (the named kinds the format stores)
-- ============================================================
local pi, sin, cos, abs, floor = math.pi, math.sin, math.cos, math.abs, math.floor
local function Wave(p) return (sin(p * 2 * pi - pi / 2) + 1) / 2 end   -- 0 -> 1 -> 0 over one go

local MOVE = {
    straightTranslate = function(p, x, y, dx, dy) return x + p * dx, y + p * dy end,
    circle = function(p, x, y, dx, dy) local a = p * 2 * pi return x + dx * cos(a), y + dy * sin(a) end,
    circle2 = function(p, x, y, dx, dy) local a = p * 2 * pi return x + dx * sin(a), y + dy * cos(a) end,
    spiral = function(p, x, y, dx, dy) local a = p * 2 * pi return x + p * dx * cos(a), y + p * dy * sin(a) end,
    spiralandpulse = function(p, x, y, dx, dy)
        local a = (p + 0.25) * 2 * pi
        return x + cos(a) * dx * cos(a * 2), y + abs(cos(a)) * dy * sin(a * 2)
    end,
    shake = function(p, x, y, dx, dy)
        local q = p < 0.25 and p * 4 or (p < 0.75 and 2 - p * 4 or (p - 1) * 4)
        return x + q * dx, y + q * dy
    end,
    bounce = function(p, x, y, dx, dy) local b = sin(p * pi) return x + b * dx, y + b * dy end,
    bounceDecay = function(p, x, y, dx, dy)
        local b = sin(((p * 3.5) % 1) * pi) * (math.ceil(p * 3.5) / 4)
        return x + b * dx, y + b * dy
    end,
    starShakeDecay = function(p, x, y, dx, dy)
        local spokes, turns = 10, 4
        local r = math.min(abs(dx), abs(dy))
        if r == 0 then return 0, 0 end
        local step = turns * 2 / spokes * pi
        local k = p * spokes
        local i = floor(k)
        k = k - i
        local a1, a2 = i * step, (i + 1) * step
        local px = k * r * cos(a2) + (1 - k) * r * cos(a1)
        local py = k * r * sin(a2) + (1 - k) * r * sin(a1)
        local e = sin(p * pi / 2)
        return e * px * dx / r, e * py * dy / r
    end,
}
local FADE = {
    straight = function(p, a, da) return a + p * da end,
    alphaPulse = function(p, a, da) return a + Wave(p) * da end,
    flash = function(p, a, da) return a + (p < 0.5 and p * 2 or (p - 1) * 2) * da end,
    hide = function() return 0 end,
}
local GROW = {
    straightScale = function(p, x, y, sx, sy) return x + p * (sx - x), y + p * (sy - y) end,
    pulse = function(p, x, y, sx, sy) local w = Wave(p) return x + w * (sx - 1), y + w * (sy - 1) end,
    fauxspin = function(p, x, y, sx, sy) return cos(p * 2 * pi) * sx, y + p * (sy - y) end,
    fauxflip = function(p, x, y, sx, sy) return x + p * (sx - x), cos(p * 2 * pi) * sy end,
}
local TURN = {
    straight = function(p, a, da) return a + p * da end,
    backandforth = function(p, a, da)
        local q = p < 0.25 and p * 4 or (p < 0.75 and 2 - p * 4 or (p - 1) * 4)
        return a + q * da
    end,
    wobble = function(p, a, da) return a + sin(p * 2 * pi) * da end,
}
local function Mix(p, r1, g1, b1, a1, r2, g2, b2, a2)
    return r1 + p * (r2 - r1), g1 + p * (g2 - g1), b1 + p * (b2 - b1), a1 + p * (a2 - a1)
end
local TINT = {
    straightColor = Mix,
    straightHSV = function(p, ...) return E.WA.GetHSVTransition(p, ...) end,
    pulseColor = function(p, ...) return Mix(Wave(p), ...) end,
    pulseHSV = function(p, ...) return E.WA.GetHSVTransition(Wave(p), ...) end,
}
local EASE = {
    none = function(p) return p end,
    easeIn = function(p, k) return p ^ k end,
    easeOut = function(p, k) return 1 - (1 - p) ^ k end,
    easeOutIn = function(p, k)
        if p < 0.5 then return (p * 2) ^ k * 0.5 end
        return 1 - ((1 - p) * 2) ^ k * 0.5
    end,
}
Ac.CURVES = { translate = MOVE, alpha = FADE, scale = GROW, rotate = TURN, color = TINT, ease = EASE }

-- the presets, as the custom animation each one stands for
local PRESETS = {
    slidetop = { duration = 0.25, use_translate = true, x = 0, y = 50, use_alpha = true, alpha = 0 },
    slideleft = { duration = 0.25, use_translate = true, x = -50, y = 0, use_alpha = true, alpha = 0 },
    slideright = { duration = 0.25, use_translate = true, x = 50, y = 0, use_alpha = true, alpha = 0 },
    slidebottom = { duration = 0.25, use_translate = true, x = 0, y = -50, use_alpha = true, alpha = 0 },
    fade = { duration = 0.25, use_alpha = true, alpha = 0 },
    grow = { duration = 0.25, use_scale = true, scalex = 2, scaley = 2, use_alpha = true, alpha = 0 },
    shrink = { duration = 0.25, use_scale = true, scalex = 0, scaley = 0, use_alpha = true, alpha = 0 },
    spiral = { duration = 0.5, use_translate = true, x = 100, y = 100, translateType = "spiral", use_alpha = true, alpha = 0 },
    bounceDecay = { duration = 1.5, use_translate = true, x = 50, y = 50, translateType = "bounceDecay", use_alpha = true, alpha = 0 },
    starShakeDecay = { duration = 1, use_translate = true, x = 50, y = 50, translateType = "starShakeDecay", use_alpha = true, alpha = 0 },
    shake = { duration = 0.5, use_translate = true, x = 10, y = 0, translateType = "circle2" },
    spin = { duration = 1, use_scale = true, scalex = 1, scaley = 1, scaleType = "fauxspin" },
    flip = { duration = 1, use_scale = true, scalex = 1, scaley = 1, scaleType = "fauxflip" },
    wobble = { duration = 0.5, use_rotate = true, rotate = 3, rotateType = "wobble" },
    pulse = { duration = 0.75, use_scale = true, scalex = 1.05, scaley = 1.05, scaleType = "pulse" },
    alphaPulse = { duration = 0.5, use_alpha = true, alpha = 0.5, alphaType = "alphaPulse" },
    rotateClockwise = { duration = 4, use_rotate = true, rotate = -360 },
    rotateCounterClockwise = { duration = 4, use_rotate = true, rotate = 360 },
    spiralandpulse = { duration = 6, use_translate = true, x = 100, y = 100, translateType = "spiralandpulse" },
    circle = { duration = 4, use_translate = true, x = 100, y = 100, translateType = "circle" },
    orbit = { duration = 4, use_translate = true, x = 100, y = 100, translateType = "circle", use_rotate = true, rotate = 360 },
    bounce = { duration = 0.6, use_translate = true, x = 0, y = 25, translateType = "bounce" },
}
Ac.PRESETS = PRESETS
-- which presets each phase offers
Ac.PHASE_PRESETS = {
    start = { "slidetop", "slideleft", "slideright", "slidebottom", "fade", "shrink", "grow", "spiral", "bounceDecay", "starShakeDecay" },
    main = { "shake", "spin", "flip", "wobble", "pulse", "alphaPulse", "rotateClockwise", "rotateCounterClockwise",
        "spiralandpulse", "orbit", "bounce" },
    finish = { "slidetop", "slideleft", "slideright", "slidebottom", "fade", "shrink", "grow", "spiral", "bounceDecay", "starShakeDecay" },
}

-- ============================================================
-- RUNNING AN ANIMATION
-- ============================================================
local anims = {}            -- region -> running animation
local driver = CreateFrame("Frame")
driver:Hide()

-- a curve: the named one, or the display's own code for "custom"
local function Curve(r, an, kindKey, funcKey, table, default)
    local kind = an[kindKey] or default
    if kind == "custom" and type(an[funcKey]) == "string" then
        r.animFns = r.animFns or {}
        local cacheKey = an[funcKey]
        local fn = r.animFns[cacheKey]
        if fn == nil then
            fn = E.Env.Function(r.id, an[funcKey], "animation") or false
            r.animFns[cacheKey] = fn
        end
        return fn or nil
    end
    return table[kind] or table[default]
end

local function Reset(r, a)
    if a.moved then r:SetOffsetAnim(0, 0) end
    if a.faded then r:SetAnimAlpha(nil) end
    if a.scaled then r:Scale(1, 1) end
    if a.turned and r.SetAnimRotation then r:SetAnimRotation(nil) end
    if a.tinted and r.ColorAnim then r:ColorAnim(nil) end
end

-- progress 0..1 of a "relative" animation from the region's own progress
local function Relative(r, a, now)
    local st = r.state
    local rel
    if st and st.progressType == "timed" then
        local dur = tonumber(st.duration) or 0
        if dur < 0.01 then return nil end
        rel = 1 - (((tonumber(st.expirationTime) or now) - now) / dur)
    elseif st and st.progressType == "static" then
        local v, t = tonumber(st.value) or 0, tonumber(st.total) or 0
        if v < 0.01 or t == 0 then return nil end
        rel = v / t
    else
        return nil
    end
    if r.inverse then rel = 1 - rel end
    return a.dur > 0 and rel / a.dur or 0
end

local function Step(r, a, now, elapsed)
    local finished = false
    if a.relative then
        local p = Relative(r, a, now)
        if not p then
            a.progress = 0
            if a.phase ~= "main" then finished = true end
        else
            local it = floor(p)
            if a.iteration == nil then a.iteration = it
            elseif a.iteration ~= it then a.iteration = nil finished = true end
            a.progress = p - it
        end
    else
        a.progress = a.progress + (elapsed / (a.dur > 0 and a.dur or 1))
        if a.progress >= 1 then a.progress = 1 finished = true end
    end
    local p = a.inverse and (1 - a.progress) or a.progress
    p = a.ease(p, a.easeStrength)
    local spec = a.spec
    local ok, x, y
    if a.move then
        ok, x, y = pcall(a.move, p, 0, 0, a.dx, a.dy)
        if ok then r:SetOffsetAnim(x, y) a.moved = true end
    end
    if a.fade then
        ok, x = pcall(a.fade, p, a.startAlpha, a.dAlpha)
        if ok then r:SetAnimAlpha(x) a.faded = true end
    end
    if a.grow then
        ok, x, y = pcall(a.grow, p, 1, 1, a.sx, a.sy)
        if ok then r:Scale(x, y) a.scaled = true end
    end
    if a.turn and r.SetAnimRotation then
        ok, x = pcall(a.turn, p, r:GetBaseRotation(), a.rot)
        if ok then r:SetAnimRotation(x) a.turned = true end
    end
    if a.tint and r.ColorAnim then
        local r1, g1, b1, a1 = r:GetColor()
        local okc, cr, cg, cb, ca = pcall(a.tint, p, r1 or 1, g1 or 1, b1 or 1, a1 or 1, spec.colorR or 1,
            spec.colorG or 1, spec.colorB or 1, spec.colorA or 1)
        if okc then r:ColorAnim(cr, cg, cb, ca) a.tinted = true end
    end
    return finished
end

-- starts one of a region's animations; false when there is none to play
function Ac.Animate(r, phase, done, inverse, loop)
    local an = r.d.animation and r.d.animation[phase]
    local old = anims[r]
    local spec
    if type(an) == "table" and an.type == "preset" and an.preset and PRESETS[an.preset] then
        spec = PRESETS[an.preset]
    elseif type(an) == "table" and an.type == "custom"
        and (an.use_translate or an.use_alpha or an.use_scale or (an.use_rotate and r.SetAnimRotation) or an.use_color) then
        spec = an
    end
    if not spec then
        if old and (old.phase ~= phase or loop) then
            anims[r] = nil
            Reset(r, old)
        end
        return false
    end
    if old then
        if old.phase == phase and not loop then return true end
        anims[r] = nil
        Reset(r, old)
    end
    local a = { phase = phase, spec = spec, done = done, inverse = inverse, loop = loop, progress = 0 }
    a.dur = tonumber(spec.duration) or tonumber(an.duration) or 0
    -- a preset's length can be changed in the display's own duration
    if spec ~= an and tonumber(an.duration) then a.dur = tonumber(an.duration) end
    a.relative = (an.duration_type or "seconds") == "relative"
    a.ease = EASE[an.easeType or "none"] or EASE.none
    a.easeStrength = tonumber(an.easeStrength) or 3
    if spec.use_translate then
        a.move = Curve(r, spec, "translateType", "translateFunc", MOVE, "straightTranslate")
        a.dx, a.dy = tonumber(spec.x) or 0, tonumber(spec.y) or 0
    end
    if spec.use_alpha then
        a.fade = Curve(r, spec, "alphaType", "alphaFunc", FADE, "straight")
        a.startAlpha = r.baseAlpha or r:GetAlpha() or 1
        a.dAlpha = (tonumber(spec.alpha) or 0) - a.startAlpha
    end
    if spec.use_scale and r.Scale then
        a.grow = Curve(r, spec, "scaleType", "scaleFunc", GROW, "straightScale")
        a.sx, a.sy = tonumber(spec.scalex) or 1, tonumber(spec.scaley) or 1
    end
    if spec.use_rotate then
        a.turn = Curve(r, spec, "rotateType", "rotateFunc", TURN, "straight")
        a.rot = tonumber(spec.rotate) or 0
    end
    if spec.use_color then
        a.tint = Curve(r, spec, "colorType", "colorFunc", TINT, "straightColor")
    end
    anims[r] = a
    Step(r, a, GetTime(), 0)
    driver:Show()
    return true
end

driver:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()
    local any = false
    for r, a in pairs(anims) do
        any = true
        local ok, finished = pcall(Step, r, a, now, elapsed or 0)
        if not ok then
            E.Error(r.id, "animation", finished)
            finished = true
            a.loop = nil
        end
        if finished then
            if a.loop then
                a.progress, a.iteration = 0, nil
            else
                anims[r] = nil
                Reset(r, a)
                if a.done then a.done() end
            end
        end
    end
    if not any then self:Hide() end
end)

-- stops what a region is playing (the region keeps its own look)
function Ac.Stop(r)
    local a = anims[r]
    if a then
        anims[r] = nil
        Reset(r, a)
    end
end

-- ============================================================
-- HOOKS THE DISPLAY CODE CALLS
-- ============================================================
local function StartMain(r)
    if r:IsShown() or r.showing then Ac.Animate(r, "main", nil, false, true) end
end

function E.OnShow(r)
    Run(r, "start")
    if not Ac.Animate(r, "start", function() StartMain(r) end, true, false) then StartMain(r) end
end

function E.OnHide(r)
    Run(r, "finish")
    UnglowAll(r)
    if r.soundRepeat then
        r.soundRepeat:Cancel()
        r.soundRepeat = nil
    end
    if E.Conditions then E.Conditions.Reset(r) end
end

-- a finish animation plays before the region really hides; true when
-- it will hide itself afterwards
function E.FinishThenHide(r, hide)
    return Ac.Animate(r, "finish", hide, false, false)
end

-- the display's load / unload code (actions.init) when it loads
function Ac.OnLoad(id)
    local d = E.data[id]
    local a = d and d.actions and d.actions.init
    if type(a) ~= "table" then return end
    if a.do_custom_load and a.customOnLoad then
        local fn = E.Env.Body(id, a.customOnLoad, "on load")
        if fn then E.Env.Run(id, fn) end
    end
end
function Ac.OnUnload(id)
    local d = E.data[id]
    local a = d and d.actions and d.actions.init
    if type(a) ~= "table" then return end
    if a.do_custom_unload and a.customOnUnload then
        local fn = E.Env.Body(id, a.customOnUnload, "on unload")
        if fn then E.Env.Run(id, fn) end
    end
end
-- wrap build / unbuild so the load and unload code run with them
local Build, Unbuild = E.Build, E.Unbuild
if Build then
    E.Build = function(id, ...)
        local r = Build(id, ...)
        if E.loaded[id] then Ac.OnLoad(id) end
        return r
    end
end
if Unbuild then
    E.Unbuild = function(id, ...)
        local was = E.loaded[id]
        local r = Unbuild(id, ...)
        if was then Ac.OnUnload(id) end
        return r
    end
end
