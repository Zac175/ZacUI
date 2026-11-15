-- ============================================================================
-- ZacUF - LowHealth.lua
-- Low-health warning for YOUR frame only. Off by default. When your health
-- drops under a configurable threshold:
--
--   * TTS says a line ("low health" by default, editable), once on the way
--     down and then at most every N seconds while you stay low AND in combat
--     AND have dropped further since the last line (so a slow eat after a
--     fight, or sitting at a deliberate 30% on Patchwerk, doesn't loop it).
--   * A red wash gradients in over the player frame - transparent at the full
--     end of the bar, solid at the empty end - and gets stronger the lower you
--     go (0 at the threshold, full strength at 0% health), with an optional
--     slow pulse.
--
-- Driven by a single hidden watcher on player UNIT_HEALTH, not by the frame's
-- own event path, so it keeps working through restyles and doesn't add to the
-- per-tick cost of the shared UpdateHealth. Dead / ghost / feign all count as
-- "not low" (you already know).
-- ============================================================================
local ADDON, ns = ...

local HYST = 5   -- % above the threshold you must climb back to before it re-arms

local function cfg() return ns.db and ns.db.lowHealth end

-- ----------------------------------------------------------------------------
-- Overlay
-- ----------------------------------------------------------------------------
-- Own child frame of the player frame's Overlay (+5): above the health bar and
-- every incoming-heal chip (those are parented to the bar, +2), under the
-- health / name text (same-frame fontstrings win over sibling textures, and
-- our host sits BELOW the Overlay's own fontstrings by level). Severity is
-- pushed as the HOST frame's alpha so it never fights the pulse, which runs
-- on an inner frame through ZacUI's motion layer (lowHealth.pulseAnim, a
-- flash on repeat by default; the global Motion switch and speed apply).
-- `frame` defaults to the player frame; the settings preview passes its
-- sample, so the sample's wash is built and painted by this same code.
local function getOverlay(frame)
    frame = frame or (ns.frames and ns.frames.player)
    if not frame or not frame.Overlay then return nil end
    local had = rawget(frame, "LowHealth")
    if had then return had end

    local host = CreateFrame("Frame", nil, frame.Overlay)
    host:SetAllPoints()
    host:SetFrameLevel(frame.Overlay:GetFrameLevel())   -- textures below the Overlay's fontstrings
    host:Hide()

    local pulser = CreateFrame("Frame", nil, host)
    pulser:SetAllPoints(host)
    host.pulser = pulser

    local t = pulser:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetBlendMode("ADD")
    host.tex = t

    frame.LowHealth = host
    return host
end

local function Motion() local Z = _G.ZacUI return Z and Z.Motion end
local DEFAULT_PULSE = { style = "flash", duration = 2.4, easing = "linear", loop = true }

local function stopPulse(host)
    host.pulsing = nil
    local Mo = Motion()
    if Mo then Mo.Stop(host.pulser) end
end

local function startPulse(host)
    local Mo = Motion()
    if not Mo then return end
    local c = cfg()
    local spec = (c and type(c.pulseAnim) == "table") and c.pulseAnim or DEFAULT_PULSE
    Mo.Stop(host.pulser)
    host.pulsing = true
    if spec.style ~= "none" then Mo.Play(host.pulser, spec, "update") end
end

-- Paint the wash in the configured color. Real horizontal gradient where the
-- client offers one (10.x-style ColorMixin signature on 1.15, legacy
-- SetGradientAlpha on anything older); flat tint at reduced strength if
-- neither takes - never assume, cover both, fall through safely.
local function paint(host)
    local c = cfg()
    local col = (c and c.glowColor) or { 1, 0.1, 0.1 }
    local r, g, b = col[1] or 1, col[2] or 0.1, col[3] or 0.1
    local t = host.tex
    t:SetColorTexture(1, 1, 1, 1)
    host.flat = true
    if CreateColor then
        local ok = pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 1))
        if ok then host.flat = false end
    end
    if host.flat and t.SetGradientAlpha then
        local ok = pcall(t.SetGradientAlpha, t, "HORIZONTAL", r, g, b, 0, r, g, b, 1)
        if ok then host.flat = false end
    end
    if host.flat then t:SetColorTexture(r, g, b, 1) end
    host.painted = true
end

-- sev: 0 (at the threshold) .. 1 (dead). nil hides. The pulse starts when
-- the wash appears or is repainted (a settings change), not on every health
-- tick, so a one-shot pulse style plays once per dip.
local function showOverlay(sev, frame)
    local host = getOverlay(frame)
    if not host then return end
    local c = cfg()
    if not sev or not (c and c.glow) then
        if host:IsShown() then stopPulse(host); host:Hide() end
        return
    end
    local fresh = not host.painted or not host:IsShown()
    if not host.painted then paint(host) end
    local strength = c.glowMax or 0.7
    if host.flat then strength = strength * 0.6 end   -- a flat wash reads heavier than a gradient
    host:SetAlpha(strength * (0.3 + 0.7 * sev))        -- 30% floor so crossing the line is visible
    if not host:IsShown() then host:Show() end
    if c.pulse then
        if fresh or not host.pulsing then startPulse(host) end
    elseif host.pulsing then
        stopPulse(host)
    end
end

-- The wash on any frame at a severity (0..1, nil hides), repainted from the
-- settings first - the settings preview's way in.
function ns.LowHealthWash(frame, sev)
    local host = getOverlay(frame)
    if host then host.painted = false end
    showOverlay(sev, frame)
end

-- Options edits (color / strength / pulse) land here via ApplySettings.
function ns.RestyleLowHealth()
    local frame = ns.frames and ns.frames.player
    local host = frame and rawget(frame, "LowHealth")
    if host then host.painted = false end
    if ns.UpdateLowHealth then ns.UpdateLowHealth() end
end

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------
local low = false
local ticker
local spokenAt   -- health % at the last callout; a repeat needs you LOWER than this

local function stopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

-- WoW Forever may hide health in combat (a secret value: no arithmetic);
-- then the reading is "unknown", taken as full
local function hidden(v) return issecretvalue ~= nil and issecretvalue(v) end

local function pctNow()
    local max, cur = UnitHealthMax("player"), UnitHealth("player")
    if hidden(max) or hidden(cur) then return 100 end
    return max > 0 and (cur / max * 100) or 100
end

local function say()
    local c = cfg()
    if not (c and c.tts and ns.Speak) then return end
    local text = c.ttsText
    if not text or text == "" then text = "low health" end
    spokenAt = pctNow()
    ns.Speak(text)
end

local function startTicker()
    stopTicker()
    local c = cfg()
    local every = c and tonumber(c.ttsRepeat) or 0
    if not (c and c.tts) or every <= 0 then return end
    ticker = C_Timer.NewTicker(every, function()
        if not low then stopTicker(); return end
        -- Repeat only while in combat AND only if you've sunk below where the
        -- last line was spoken. Parking at a steady 30% (Patchwerk) gets one
        -- callout; the next comes when it gets worse, not on a clock.
        if UnitAffectingCombat("player") and pctNow() < (spokenAt or 100) - 2 then say() end
    end)
end

local function setLow(v)
    if v == low then return end
    low = v
    if low then say(); startTicker() else stopTicker(); spokenAt = nil end
end

function ns.UpdateLowHealth()
    local c = cfg()
    if not (c and c.enabled) then
        setLow(false); showOverlay(nil); return
    end
    local pct = pctNow()
    local thr = tonumber(c.threshold) or 35

    local alive = not (UnitIsDeadOrGhost("player") or (UnitIsFeignDeath and UnitIsFeignDeath("player")))
    if not alive then
        setLow(false); showOverlay(nil); return
    end

    -- Hysteresis: arm below the line, disarm only once you're clearly above it.
    if not low and pct < thr then setLow(true)
    elseif low and pct >= math.min(thr + HYST, 100) then setLow(false) end

    if pct < thr then
        showOverlay(thr > 0 and math.min(1, math.max(0, (thr - pct) / thr)) or 1)
    else
        showOverlay(nil)
    end
end

-- /zuf low - preview at the current settings without having to get hit:
-- the wash at ~70% severity for 3s + the TTS line.
function ns.LowHealthTest()
    local c = cfg()
    if not c then return end
    local wasOn = c.enabled
    c.enabled = true
    showOverlay(0.7)
    say()
    C_Timer.After(3, function()
        c.enabled = wasOn
        ns.UpdateLowHealth()
    end)
    ns.Print(("Low-health test - wash at %d%% threshold%s. /zuf for settings."):format(
        tonumber(c.threshold) or 35, c.enabled and "" or " (feature is currently OFF)"))
end

-- ----------------------------------------------------------------------------
-- Watcher
-- ----------------------------------------------------------------------------
local w = CreateFrame("Frame")
w:RegisterUnitEvent("UNIT_HEALTH", "player")
w:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
w:RegisterEvent("PLAYER_ENTERING_WORLD")
w:RegisterEvent("PLAYER_DEAD")
w:RegisterEvent("PLAYER_ALIVE")
w:RegisterEvent("PLAYER_UNGHOST")
w:RegisterEvent("PLAYER_REGEN_ENABLED")
w:SetScript("OnEvent", function() ns.UpdateLowHealth() end)
