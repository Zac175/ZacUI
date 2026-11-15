-- ============================================================================
-- ZacUF - Config.lua
-- Default settings. Everything configurable lives here; nothing about look or
-- layout is hardcoded elsewhere. Media is stored as LibSharedMedia *names*
-- (resolved at apply time by Media.lua).
--
-- Element APPEARANCE (sizes, textures, colors) is global; element ENABLE flags
-- (power / name / auras / castbar) and health-text mode are PER FRAME, so each
-- frame can be customized independently.
-- ============================================================================
local ADDON, ns = ...

ns.defaults = {
    -- when false, frames + group headers can be dragged. A fresh install
    -- starts locked (2026-11-07): unlocked, its first restyle (the font
    -- push a second after login) put the target's castbar into its move
    -- preview ("Castbar - drag me") and showed the move handles
    locked = true,
    smoothBars = true, -- health and power glide to a new value (~0.15 s) instead of jumping
    smoothTime = 0.15, -- how long that glide takes (seconds; the global Motion speed divides it)

    -- Text styles, one font setting per kind of text (ZacUI's standard font
    -- shape: face / size / outline / shadow). Any field left out reads as
    -- today's look: the unit frames' font (media.font below), outlined, no
    -- shadow, at the size each text always had. The name's size stays in
    -- name.size and the heal number's in heal.total.size, where saves keep it.
    fonts = {
        name      = {},
        health    = {},
        castbar   = {},
        auraCount = {},
        healTotal = {},
        tauntCount = {},   -- the AoE-taunt countdown (16, outlined)
    },

    -- Media: LibSharedMedia names. "Blizzard" is always safe; Smooth / Flat /
    -- Minimalist / ZacUF Gradient come from ZacUF\Media and appear in the
    -- texture dropdowns.
    media = {
        font    = "Friz Quadrata TT",
        bar     = "Blizzard",
        nameBar = "Blizzard",
    },

    -- Colors (r,g,b,a). Health/name can instead use class/reaction color.
    colors = {
        border        = { 0, 0, 0, 1 },
        background    = { 0.06, 0.06, 0.06, 0.85 },
        health        = { 0.20, 0.20, 0.20, 1 },    -- used when class/reaction color off
        healthBg      = { 0.08, 0.08, 0.08, 0.90 },
        nameBg        = { 0.10, 0.10, 0.10, 0.85 }, -- tint of the name strip
        nameText      = { 1, 1, 1, 1 },             -- used when name class-color off
        castbar       = { 0.25, 0.45, 0.80, 1 },    -- normal cast
        castbarNoInt  = { 0.70, 0.30, 0.30, 1 },    -- non-interruptible cast
        healthText    = { 0.85, 0.85, 0.85, 1 },    -- the health value on the bar
        powerBg       = { 0, 0, 0, 0.6 },           -- behind the power bar
        -- Fallback for incoming heals the data source can't attribute to a caster
        -- (the built-in UnitGetIncomingHeals reports totals only). Per-healer
        -- colors live in `heal` below, not here.
        incomingHeal  = { 0.30, 0.78, 0.42, 0.55 },
    },

    -- Incoming-heal display. Prediction itself is a PER-FRAME toggle
    -- (cfg.healPrediction, off by default everywhere); this block is the shared
    -- look and behavior for wherever it is switched on. See HealColors.lua for
    -- the color model and Heal.lua for the data sources.
    heal = {
        window      = 4,      -- seconds ahead to count (HoT tails past this would overstate the bar)
        maxSegments = 4,      -- visible per-healer chunks; extras merge into one "+N"
        overheal    = 0,      -- % of the bar heals may extend past full (0 = clamp at full)

        colorMode   = "class",  -- "class" (deterministic, same on every screen) | "slot" (per-healer)
        classColors = {},       -- CLASS -> {r,g,b}   overrides in class mode
        roleColors  = {},       -- role  -> {[row] = {r,g,b}}   overrides in slot mode
        slots       = {},       -- role  -> name -> slot   (persisted so a healer keeps their color)

        ownHeal = { enabled = true,  color = { 0.95, 0.95, 0.95 } },  -- your own heals stand out
        hot     = { show    = true,  uniform = false, color = { 0.30, 0.55, 0.95 } },

        -- LibHealPredict only. Off, it times HoT ticks from aura refreshes; on,
        -- it also reads combat-log periodic-heal events, which makes tick timing
        -- and amounts noticeably more accurate at the cost of parsing the combat
        -- log. Worth turning on if you heal; not worth it if you don't.
        preciseHots = false,

        segment = {
            fill         = "class",             -- "class" (per-healer color) | "uniform" (one flat color)
            uniformColor = { 0.50, 0.50, 0.50 },
            marker       = "none",              -- "none" | "dot" | "initials"
            spark        = true,                -- bright line at the health -> heal boundary
            outline      = true,                -- dark top/bottom edge framing each chip
            texture      = "flat",              -- "flat" (matte, reads as a different material) | "glossy"
            layer        = "behind",            -- "behind" (name + health text stay on top) | "front" (chips cover them)
            alpha        = 0.85,                -- chips read solid but still hint "prediction"
        },

        -- Persistent legend: a colored dot on a healer's OWN frame in the color
        -- their incoming-heal chips use, so you can read the bars at a glance.
        dot = { enabled = true, position = "LEFT_OF_NAME", size = 10, hideInCombat = false },

        -- Total incoming healing as an actual NUMBER on the frame. The chips show
        -- you the SHAPE of what is landing; this shows the SIZE of it. Shown
        -- wherever prediction is on, and only while something is inbound.
        --
        -- This is built for reading your OWN frame as a dps: the question is
        -- "am I covered - do I back out or full send?". So the number is the raw
        -- incoming total, never clamped to missing health, and the COLOR answers
        -- the question directly by where the heals will actually land you:
        --
        --   coverage (default) - green at/above safePct, yellow down to
        --                        partialPct, red below. Green means the heals
        --                        top you off: send it. Red means what is inbound
        --                        will not save you: back out.
        --   overheal           - the healer's framing instead: amber once the
        --                        total exceeds the deficit, i.e. mana is being
        --                        wasted on this target.
        --   flat               - one color, no judgment.
        total = {
            enabled       = true,
            -- "LEFT_OF_HP" / "RIGHT_OF_HP" pin the number to the health TEXT
            -- rather than to the frame, so it reads as one line with the health
            -- value wherever that text has been anchored: "+3000  3.4k  87%".
            -- Any 9-point value places it on the frame independently instead.
            anchor        = "LEFT_OF_HP",
            x             = 0,
            y             = 0,
            size          = 11,
            format        = "auto",      -- "auto" (exact under 10k, 12.3k above) | "full" | "short"
            prefix        = true,        -- leading "+"
            showProjected = false,       -- append the health % the heals land you at

            colorMode     = "coverage",  -- "coverage" | "overheal" | "flat"
            safePct       = 90,          -- projected health at/above this = safe
            partialPct    = 55,          -- ...down to this = it helps but is not enough

            safeColor     = { 0.40, 1.00, 0.50 },   -- covered: full send
            partialColor  = { 1.00, 0.85, 0.30 },   -- helps, still exposed
            lowColor      = { 1.00, 0.45, 0.35 },   -- will not save you: back out
            color         = { 0.85, 0.92, 1.00 },   -- flat mode / coverage at full health
            overhealColor = { 1.00, 0.82, 0.25 },   -- overheal mode only
        },
    },

    health = {
        classColor    = true,   -- color player health by class
        reactionColor = true,   -- color npc health by reaction
    },

    -- Global element appearance (enable flags are per-frame below)
    power = { height = 4 },

    name = {
        classColor = true,
        size       = 12,
        height     = 14,        -- height of the texture strip behind the name (when shown)
        showStrip  = false,     -- texture strip behind the name (off = no background box)
    },

    auras = {
        size     = 20,
        max      = 6,
        perRow   = 6,
        onlyMine = false,       -- only show debuffs you cast (buffs/debuffs are toggled per frame)
        filterEnabled = false,  -- when ON, only auras whose name or spell ID is listed below are shown
        dispellableOnly = false, -- when ON, debuff icons show only what YOUR class can dispel
        dispelHighlight = true,  -- tint the frame border by dispel type when a cleansable debuff is present
        buffList   = {},        -- entries: { label = "Renew",      name = "renew" }      or { label = "139",   id = 139 }
        debuffList = {},        -- entries: { label = "Death Wish", name = "death wish" } or { label = "12292", id = 12292 }
        spacing     = 2,                      -- gap between icons
        borderColor = { 0, 0, 0, 1 },         -- the 1px edge round each icon
        countColor  = { 0.85, 0.85, 0.85, 1 }, -- the stack number
    },

    castbar = {
        height   = 16,
        showIcon = true,
        showTime = true,
        -- texture = nil: the bars' texture (media.bar)
        bgColor     = { 0, 0, 0, 0.7 },
        borderColor = { 0, 0, 0, 1 },
        textColor   = { 0.85, 0.85, 0.85, 1 },
        -- how it appears when a cast starts and goes when it ends (none = instant, as it always was)
        showAnim = { style = "none", duration = 0.2, delay = 0, easing = "easeOutQuad", dir = "up", distance = 10 },
        hideAnim = { style = "none", duration = 0.3, delay = 0, easing = "easeOutQuad", dir = "down", distance = 10 },
    },

    -- Status icons (combat swords, leader crown / assist, main tank-assist role,
    -- raid target marker, PvP flag + timer). Shown per frame via the per-frame
    -- toggles below; this is the shared icon size.
    indicators = { size = 18 },

    -- Challenging Shout / Challenging Roar alert (ShoutAlert.lua): a bright
    -- glow round every frame showing the caster, a countdown of the six
    -- seconds on it, and a TTS callout - the safe-to-sapper window. On by
    -- default; keys here so a save can turn either half off.
    -- color: the glow's colour. anim: how the "Tint only" style (the old
    -- wash) throbs (a flash on repeat, two beats a 1.6s cycle).
    -- style..offset: the glow's look, the shape in Glows.lua (the warrior
    -- HUD's edge glow, reaching 10 px, with its wide halo, breathing).
    -- countdown..countTenths: the seconds left on the frame (its font is
    -- fonts.tauntCount).
    shoutAlert = { enabled = true, tts = true,
        color = { 1, 0.45, 0.05, 0.9 },
        anim  = { style = "flash", duration = 1.6, delay = 0, easing = "linear", dir = "up", distance = 10, loop = true },
        style = "edge", alpha = 1, size = 10, thickness = 3, wide = true,
        pulse = true, pulseSpeed = 0.4, pulseDepth = 0.55,
        lines = 10, length = 10, speed = 0.4, offset = 0,
        countdown = true, countPoint = "CENTER", countColor = { 1, 1, 1, 1 }, countTenths = false,
    },

    -- Dispel glow (Glows.lua): a glow round any frame whose unit has a
    -- debuff YOU can remove right now (your known spells; the Felhunter's
    -- Devour Magic while it is out), in the debuff type's colour (byType)
    -- or `color`. onlyInRange: hidden while the unit is out of range of
    -- the spell that removes it. The look: the warrior HUD's edge glow,
    -- reaching 6 px, breathing gently. The border tint
    -- (auras.dispelHighlight) is separate and stays as it was.
    dispelGlow = { enabled = true, byType = true, onlyInRange = true,
        color = { 1, 1, 1, 1 },
        style = "edge", alpha = 1, size = 6, thickness = 2, wide = false,
        pulse = true, pulseSpeed = 0.8, pulseDepth = 0.45,
        lines = 8, length = 8, speed = 0.25, offset = 0,
    },

    -- Text-to-speech voice shared by every ZacUF callout (shout alert, low
    -- health). Stored by NAME, not id - ids are per-machine. "auto" = the first
    -- female voice installed (same default Readycheck uses), else voice 1.
    tts = { voice = "auto" },

    -- Options window size (0 = default 600x540). Set by the resize grip.
    window = { w = 0, h = 0 },

    -- Low-health warning on YOUR frame (LowHealth.lua). OFF by default. Under
    -- `threshold` %: TTS says `ttsText` (again every `ttsRepeat` s while low
    -- and in combat, but only if you've dropped LOWER than the last callout -
    -- so parking at 30% on Patchwerk gets one line, not a loop; 0 = once per
    -- dip), and a colored wash gradients in over the player frame, ramping
    -- from 0 at the threshold to `glowMax` at 0%.
    lowHealth = {
        enabled   = false,
        threshold = 35,
        tts       = true,
        ttsText   = "low health",
        ttsRepeat = 4,
        glow      = true,
        glowColor = { 1, 0.10, 0.10 },
        glowMax   = 0.7,
        pulse     = true,
        -- how the wash pulses (a flash on repeat, 0.6s each way as before)
        pulseAnim = { style = "flash", duration = 2.4, delay = 0, easing = "linear", dir = "up", distance = 10, loop = true },
    },

    -- Single unit frames. power/name/auras/castbar are per-frame toggles;
    -- healthText is "none" | "current" | "percent" | "both".
    frames = {
        player = {
            enabled = true, width = 176, height = 38, point = "CENTER", x = -240, y = -170,
            -- healPrediction on: your own frame is where incoming healing is a
            -- decision input rather than a curiosity - it is the difference
            -- between backing out and committing. Off everywhere else.
            power = true, name = true, showBuffs = false, showDebuffs = false, castbar = true, healPrediction = true, healthText = "percent",
            nameAnchor = "LEFT", nameX = 0, nameY = 0, hpAnchor = "RIGHT", hpX = 0, hpY = 0,
            healthClassColor = true, healthColor = { 0.20, 0.20, 0.20, 1 }, nameClassColor = true, nameColor = { 1, 1, 1, 1 },
            bgColor = { 0.06, 0.06, 0.06, 0.85 }, borderColor = { 0, 0, 0, 1 },
            buffAnchor = "ABOVE", buffX = 0, buffY = 0, debuffAnchor = "BELOW", debuffX = 0, debuffY = 0,
            combatIcon = true, leaderIcon = true, roleIcon = false, raidIcon = true, pvpIcon = true, rezIcon = true,
            combatSize = 18, leaderSize = 14, roleSize = 14, raidSize = 22, pvpSize = 12, rezSize = 18,
            combatAnchor = "CENTER", combatX = 0, combatY = 0, leaderAnchor = "TOPLEFT", leaderX = 3, leaderY = -3, roleAnchor = "TOPLEFT", roleX = 19, roleY = -3,
            raidAnchor = "TOP", raidX = 0, raidY = 0, pvpAnchor = "BOTTOM", pvpX = 0, pvpY = 2, rezAnchor = "CENTER", rezX = 0, rezY = 0,
            cbAnchor = "BELOW", cbX = 0, cbY = -2, cbWidth = 0, cbHeight = 0,
        },
        target = {
            enabled = true, width = 176, height = 38, point = "CENTER", x = 240, y = -170,
            power = true, name = true, showBuffs = false, showDebuffs = true, castbar = true, healPrediction = false, healthText = "percent",
            nameAnchor = "LEFT", nameX = 0, nameY = 0, hpAnchor = "RIGHT", hpX = 0, hpY = 0,
            healthClassColor = true, healthColor = { 0.20, 0.20, 0.20, 1 }, nameClassColor = true, nameColor = { 1, 1, 1, 1 },
            bgColor = { 0.06, 0.06, 0.06, 0.85 }, borderColor = { 0, 0, 0, 1 },
            buffAnchor = "ABOVE", buffX = 0, buffY = 0, debuffAnchor = "BELOW", debuffX = 0, debuffY = 0,
            combatIcon = false, leaderIcon = true, roleIcon = false, raidIcon = true, pvpIcon = false, rezIcon = true,
            combatSize = 18, leaderSize = 14, roleSize = 14, raidSize = 22, pvpSize = 12, rezSize = 18,
            combatAnchor = "CENTER", combatX = 0, combatY = 0, leaderAnchor = "TOPLEFT", leaderX = 3, leaderY = -3, roleAnchor = "TOPLEFT", roleX = 19, roleY = -3,
            raidAnchor = "TOP", raidX = 0, raidY = 0, pvpAnchor = "BOTTOM", pvpX = 0, pvpY = 2, rezAnchor = "CENTER", rezX = 0, rezY = 0,
            cbAnchor = "BELOW", cbX = 0, cbY = -2, cbWidth = 0, cbHeight = 0,
        },
        -- Soft Target frame: shown while soft-engaged with no hard target;
        -- clicking it hard-targets the mob (secure, combat-legal). It has NO
        -- styling of its own - SpawnUnit borrows the Target frame's cfg
        -- wholesale and pins the frame onto the Target frame's exact rect,
        -- so it is always a pixel-perfect twin. Only the enable flag lives
        -- here. (Style keys seeded into saves by an earlier build are inert.)
        softtarget = { enabled = true },
        targettarget = {
            enabled = true, width = 96, height = 24, point = "CENTER", x = 400, y = -170,
            power = false, name = true, showBuffs = false, showDebuffs = false, castbar = false, healPrediction = false, healthText = "none", rangeFade = true,
            nameAnchor = "CENTER", nameX = 0, nameY = 0, hpAnchor = "RIGHT", hpX = 0, hpY = 0,
            healthClassColor = true, healthColor = { 0.20, 0.20, 0.20, 1 }, nameClassColor = true, nameColor = { 1, 1, 1, 1 },
            bgColor = { 0.06, 0.06, 0.06, 0.85 }, borderColor = { 0, 0, 0, 1 },
            buffAnchor = "ABOVE", buffX = 0, buffY = 0, debuffAnchor = "BELOW", debuffX = 0, debuffY = 0,
            combatIcon = false, leaderIcon = false, roleIcon = false, raidIcon = false, pvpIcon = false, rezIcon = false,
            combatSize = 12, leaderSize = 10, roleSize = 10, raidSize = 15, pvpSize = 9, rezSize = 12,
            combatAnchor = "CENTER", combatX = 0, combatY = 0, leaderAnchor = "TOPLEFT", leaderX = 3, leaderY = -3, roleAnchor = "TOPLEFT", roleX = 19, roleY = -3,
            raidAnchor = "TOPRIGHT", raidX = -2, raidY = -2, pvpAnchor = "BOTTOM", pvpX = 0, pvpY = 2, rezAnchor = "CENTER", rezX = 0, rezY = 0,
            cbAnchor = "BELOW", cbX = 0, cbY = -2, cbWidth = 0, cbHeight = 0,
        },
        pet = {
            enabled = false, width = 116, height = 22, point = "CENTER", x = -240, y = -218,
            power = true, name = false, showBuffs = false, showDebuffs = false, castbar = false, healPrediction = false, healthText = "none",
            nameAnchor = "LEFT", nameX = 0, nameY = 0, hpAnchor = "RIGHT", hpX = 0, hpY = 0,
            healthClassColor = true, healthColor = { 0.20, 0.20, 0.20, 1 }, nameClassColor = true, nameColor = { 1, 1, 1, 1 },
            bgColor = { 0.06, 0.06, 0.06, 0.85 }, borderColor = { 0, 0, 0, 1 },
            buffAnchor = "ABOVE", buffX = 0, buffY = 0, debuffAnchor = "BELOW", debuffX = 0, debuffY = 0,
            combatIcon = false, leaderIcon = false, roleIcon = false, raidIcon = false, pvpIcon = false, rezIcon = false,
            combatSize = 12, leaderSize = 10, roleSize = 10, raidSize = 15, pvpSize = 9, rezSize = 12,
            combatAnchor = "CENTER", combatX = 0, combatY = 0, leaderAnchor = "TOPLEFT", leaderX = 3, leaderY = -3, roleAnchor = "TOPLEFT", roleX = 19, roleY = -3,
            raidAnchor = "TOPRIGHT", raidX = -2, raidY = -2, pvpAnchor = "BOTTOM", pvpX = 0, pvpY = 2, rezAnchor = "CENTER", rezX = 0, rezY = 0,
            cbAnchor = "BELOW", cbX = 0, cbY = -2, cbWidth = 0, cbHeight = 0,
        },
    },

    -- Party (secure group header)
    party = {
        enabled = true, showPlayer = false, showInRaid = false,
        sortMethod = "Index", sortDir = "Ascending",
        width = 124, height = 32, spacing = 4, growth = "DOWN",
        rangeAlpha = 0.40,   -- opacity of a member out of range (with rangeFade on)
        point = "TOPLEFT", x = 20, y = -240,
        power = false, name = true, showBuffs = false, showDebuffs = false, castbar = false, healPrediction = false, healthText = "percent", rangeFade = true,
        nameAnchor = "LEFT", nameX = 0, nameY = 0, hpAnchor = "RIGHT", hpX = 0, hpY = 0,
        healthClassColor = true, healthColor = { 0.20, 0.20, 0.20, 1 }, nameClassColor = true, nameColor = { 1, 1, 1, 1 },
        bgColor = { 0.06, 0.06, 0.06, 0.85 }, borderColor = { 0, 0, 0, 1 },
        buffAnchor = "ABOVE", buffX = 0, buffY = 0, debuffAnchor = "BELOW", debuffX = 0, debuffY = 0,
        combatIcon = false, leaderIcon = true, roleIcon = false, raidIcon = true, pvpIcon = false, rezIcon = true,
        combatSize = 14, leaderSize = 12, roleSize = 12, raidSize = 17, pvpSize = 10, rezSize = 14,
        combatAnchor = "CENTER", combatX = 0, combatY = 0, leaderAnchor = "TOPLEFT", leaderX = 3, leaderY = -3, roleAnchor = "TOPLEFT", roleX = 19, roleY = -3,
        raidAnchor = "TOP", raidX = 0, raidY = 0, pvpAnchor = "BOTTOM", pvpX = 0, pvpY = 2, rezAnchor = "CENTER", rezX = 0, rezY = 0,
        cbAnchor = "BELOW", cbX = 0, cbY = -2, cbWidth = 0, cbHeight = 0,
    },

    -- Raid (secure group header)
    raid = {
        enabled = true, showPlayer = true,
        sortMethod = "Index", sortDir = "Ascending",
        width = 70, height = 30, spacing = 3,
        unitsPerColumn = 5, maxColumns = 8, columnSpacing = 4,
        growth = "DOWN", columnGrowth = "RIGHT", groupBy = true,
        point = "TOPLEFT", x = 20, y = -300,
        fitChat = false, fitGap = 4,  -- line the raid up with the chat window (Groups.lua; opt-in)
        rangeAlpha = 0.40,   -- opacity of a member out of range (with rangeFade on)
        power = false, name = true, showBuffs = false, showDebuffs = false, castbar = false, healPrediction = false, healthText = "none", rangeFade = true,
        nameAnchor = "TOP", nameX = 0, nameY = 0, hpAnchor = "BOTTOM", hpX = 0, hpY = 0,
        healthClassColor = true, healthColor = { 0.20, 0.20, 0.20, 1 }, nameClassColor = true, nameColor = { 1, 1, 1, 1 },
        bgColor = { 0.06, 0.06, 0.06, 0.85 }, borderColor = { 0, 0, 0, 1 },
        buffAnchor = "ABOVE", buffX = 0, buffY = 0, debuffAnchor = "BELOW", debuffX = 0, debuffY = 0,
        combatIcon = false, leaderIcon = true, roleIcon = true, raidIcon = true, pvpIcon = false, rezIcon = true,
        combatSize = 12, leaderSize = 10, roleSize = 10, raidSize = 16, pvpSize = 9, rezSize = 14,
        combatAnchor = "CENTER", combatX = 0, combatY = 0, leaderAnchor = "TOPLEFT", leaderX = 3, leaderY = -3, roleAnchor = "TOPLEFT", roleX = 19, roleY = -3,
        raidAnchor = "CENTER", raidX = 0, raidY = 0, pvpAnchor = "BOTTOM", pvpX = 0, pvpY = 2, rezAnchor = "CENTER", rezX = 0, rezY = 0,
        cbAnchor = "BELOW", cbX = 0, cbY = -2, cbWidth = 0, cbHeight = 0,
    },

    -- Blizzard frame hiding (applied only when the matching ZacUF frame is on).
    blizzard = {
        player = true, target = true, pet = true, party = true, raid = true,
        castbar = true,   -- hide Blizzard's player cast bar when ZacUF's player castbar is on
    },
}

-- ----------------------------------------------------------------------------
-- Config helpers (operate on ns.db, the live saved table)
-- ----------------------------------------------------------------------------
function ns.DeepFill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            ns.DeepFill(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

function ns.Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, val in pairs(v) do t[k] = val end
    return t
end

-- Portrait, per frame (Portrait.lua). OFF everywhere until it is switched
-- on: a frame without one is laid out exactly as it always was, and a
-- save from before this key simply gains it switched off.
--   style      "2d" (the face as the game draws it) | "3d" (a model)
--   classIcon  players show their class icon instead of the face (2D)
--   side       "LEFT" | "RIGHT" of the bars
--   layout     "shrink" (the bars make room inside the frame) | "outside"
--              (beside the frame, which stays as it is) | "inside" (over
--              the bar's end)
--   size       px, square; 0 = as tall as the frame
--   gap        px between it and the bars (or the frame, outside)
--   border / background   in the frame's own colours
--   zoom       the 3D camera, 0 (whole body) .. 1 (the face)
-- enabled: nil = the LOOK's default (2026-11-07, Zac): off under ZacUI's
-- own look, on under WoW Forever / Blizzard style / Classic (each drawn in
-- that look's portrait art where it has one), except on the raid and tank
-- frames, which the game's own looks draw without one. An explicit
-- true / false (the "Show a portrait" box) always wins. ns.PortraitOn.
local PORTRAIT = { style = "2d", classIcon = false, side = "LEFT", layout = "shrink",
    size = 0, gap = 2, border = true, background = true, zoom = 1 }
ns.PORTRAIT_DEFAULTS = PORTRAIT
for _, k in ipairs({ "player", "target", "targettarget", "pet" }) do
    ns.defaults.frames[k].portrait = ns.Copy(PORTRAIT)
end
ns.defaults.party.portrait = ns.Copy(PORTRAIT)
ns.defaults.raid.portrait  = ns.Copy(PORTRAIT)

-- is the portrait on for this frame cfg (see PORTRAIT above)
function ns.PortraitOn(cfg)
    local pc = cfg and cfg.portrait
    if type(pc) ~= "table" then return false end
    if pc.enabled ~= nil then return pc.enabled and true or false end
    local Z = _G.ZacUI
    local L = Z and Z.Look
    if not (L and L.For) then return false end
    local ok, look = pcall(L.For, "unitframes")
    if not (ok and type(look) == "table") or look.id == "zacui" then return false end
    local db = ns.db
    if db and (cfg == db.raid or (db.frames and cfg == db.frames.tanks)) then return false end
    return true
end

-- ----------------------------------------------------------------------------
-- Match pass (2026-11-07, zui_tests/MATCH_FRAMES_1107.md): under ZacUI's
-- own look the shipped numbers are the reference UI's (sizes, colours,
-- spacing), so a fresh install - or a save still on the old shipped
-- values, moved once by InitDB (ns.MatchMigrate) - draws the same frames.
-- The Classic look keeps every old default. A value someone set by hand
-- is never touched. Portraits stay off.
-- ----------------------------------------------------------------------------
function ns.MatchOn()
    local Z = _G.ZacUI
    local L = Z and Z.Look
    if not (L and L.For) then return false end
    local ok, look = pcall(L.For, "unitframes")
    return (ok and type(look) == "table" and look.id == "zacui") and true or false
end

-- { path..., new value }; the old shipped value is read from the table
-- as it stands before the overlay (ns.MATCH_OLD)
local MATCH = {
    { "media", "font", "Barlow Semi Condensed" },
    { "colors", "healthBg", { 0.067, 0.067, 0.067, 1 } },
    { "colors", "powerBg", { 0.067, 0.067, 0.067, 1 } },
    { "colors", "castbar", { 0.863, 0.820, 0.639, 1 } },
    { "colors", "castbarNoInt", { 0.5, 0.5, 0.5, 1 } },
    { "colors", "healthText", { 1, 1, 1, 1 } },
    { "power", "height", 5 },
    { "auras", "size", 22 }, { "auras", "spacing", 1 }, { "auras", "max", 14 }, { "auras", "perRow", 7 },
    { "castbar", "height", 14 }, { "castbar", "bgColor", { 0, 0, 0, 0.5 } }, { "castbar", "textColor", { 1, 1, 1, 1 } },
    { "frames", "player", "width", 181 }, { "frames", "player", "height", 52 },
    { "frames", "player", "nameClassColor", false }, { "frames", "player", "cbY", 0 },
    { "frames", "target", "width", 181 }, { "frames", "target", "height", 52 },
    { "frames", "target", "nameClassColor", false }, { "frames", "target", "cbY", 0 },
    { "frames", "target", "showBuffs", true },
    { "frames", "targettarget", "width", 101 }, { "frames", "targettarget", "height", 25 },
    { "frames", "targettarget", "nameAnchor", "LEFT" }, { "frames", "targettarget", "nameClassColor", false },
    { "frames", "pet", "width", 101 }, { "frames", "pet", "height", 31 },
    { "frames", "pet", "name", true }, { "frames", "pet", "nameClassColor", false },
    { "party", "width", 125 }, { "party", "height", 60 }, { "party", "spacing", -1 },
    { "party", "nameAnchor", "TOPLEFT" }, { "party", "healthText", "none" },
    { "party", "nameClassColor", false }, { "party", "nameSize", 10 },
    { "raid", "width", 125 }, { "raid", "height", 60 }, { "raid", "spacing", -1 }, { "raid", "columnSpacing", -1 },
    { "raid", "nameAnchor", "TOPLEFT" }, { "raid", "nameClassColor", false }, { "raid", "nameSize", 10 },
}
ns.MATCH = MATCH
ns.MATCH_OLD = {}

-- the frames other files register (Extras.lua): { key, old, new }; the old
-- values are what those files shipped (copied from the old target / ToT)
ns.MATCH_EXTRA = {
    focus = { { "width", 176, 160 }, { "height", 38, 40 }, { "nameClassColor", true, false },
        { "cbY", -2, 0 }, { "showBuffs", false, false } },
    focustarget = { { "width", 96, 101 }, { "height", 24, 25 }, { "nameAnchor", "CENTER", "LEFT" },
        { "nameClassColor", true, false } },
    boss = { { "width", 170, 160 }, { "height", 32, 40 }, { "spacing", 28, 40 },
        { "nameClassColor", true, false }, { "cbY", -2, 0 } },
}

-- THE FRESH DESIGN (2026-11-08, Zac: "what are these ugly ass default
-- settings with super tall player and target frames do better"). The
-- 181 x 52 above is the reference's frame WITH its portrait (a 52 square
-- beside 181 x 46 + 6 of bars, ~233 wide in all); ZacUI's look has no
-- portrait, so the bars alone read as a tall block. Without one the
-- frames run wider and shorter (zui_tests/mock_1108/fresh_look_1108*.png):
--   player / target  224 x 36: a 31 health bar over the slim 5 power bar
--                    (power.height above), name left and health right at
--                    14, outlined, both centred on the health bar; the
--                    cast bar (14) flush under the frame (cbY 0)
--   target of target 112 x 22, its name at 12, the target's top edge, 8
--                    clear of the target's right end
-- On the defaults only, after MATCH, under ZacUI's look: every save has
-- these keys written (DeepFill), so a save that exists keeps its sizes
-- and spots - only a fresh install (Reset, a new profile) draws them.
-- They are NOT in MATCH: no migration ever moves a saved value to them,
-- and the _matchRev 1 restore keeps reading MATCH's 181 x 52.
local DESIGN_TOT = { w = 112, h = 22, gap = 8 }
ns.MATCH_DESIGN = {
    { "frames", "player", "width", 224 }, { "frames", "player", "height", 36 },
    { "frames", "target", "width", 224 }, { "frames", "target", "height", 36 },
    { "frames", "targettarget", "width", DESIGN_TOT.w }, { "frames", "targettarget", "height", DESIGN_TOT.h },
    { "name", "size", 14 },
}
-- the keys a save does not carry until set (nil = the look's own size):
-- written into a brand-new unit frame save only (Core.lua's InitDB), so
-- a save that exists keeps the size it draws today
ns.MATCH_FRESH_SAVE = {
    { "fonts", "health", "size", 14 },
    { "frames", "targettarget", "nameSize", 12 },
}

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepCopy(x) end
    return t
end
ns.MatchCopy = deepCopy

-- THE OLD SHIPPED VALUES, read off the defaults at file load (nothing is
-- changed here): what MatchMigrate compares a save with and
-- MatchRestoreGeometry puts back.
for i, e in ipairs(MATCH) do
    local t = ns.defaults
    for j = 1, #e - 2 do t = t and t[e[j]] end
    if type(t) == "table" then ns.MATCH_OLD[i] = deepCopy(t[e[#e - 1]]) end
end

-- THE OVERLAY: the reference UI's numbers onto the defaults, decided ONCE
-- by InitDB (Core.lua) at login, from the LATCHED look (2026-11-08). It
-- used to be decided here at file load, where the look had no live answer
-- yet and read as ZacUI's - so a Classic save got the overlay, its
-- migration and the ZacUI text style. Under a game look it never applies.
-- Returns whether it is on. The frames registered by later files
-- (Extras.lua) get their own numbers here too.
function ns.ApplyMatchOverlay()
    if ns._matchDecided then return ns._matchApplied end
    -- (from the look as the worn profile has it: InitDB runs at
    -- PLAYER_LOGIN, after the profile is worn, so the latch is re-read
    -- here when ZacUI's own PLAYER_LOGIN has not got to it yet - the
    -- client does not promise which addon hears the event first)
    local Z = _G.ZacUI
    local L = Z and Z.Look
    if L and L.Settled and not L.Settled() and L.Relatch then L.Relatch() end
    ns._matchDecided = true
    if not ns.MatchOn() then
        ns._matchApplied = nil
        return false
    end
    local copies = ns.DEFAULT_COPIES or {}
    for i, e in ipairs(MATCH) do
        local t = ns.defaults
        for j = 1, #e - 2 do t = t and t[e[j]] end
        if type(t) == "table" then
            local k = e[#e - 1]
            t[k] = deepCopy(e[#e])
            -- a frame's defaults copied from this one at file load (the
            -- boss, focus, party-target and tank frames) take the number
            -- too, unless they set that key themselves
            for c, from in pairs(copies) do
                if from.src == t and from.over[k] == nil then c[k] = deepCopy(e[#e]) end
            end
        end
    end
    -- the fresh design over the match numbers (above), and the target of
    -- target's spot worked out from the target's: its top edge, 8 clear
    -- of the target's right end
    for _, e in ipairs(ns.MATCH_DESIGN) do
        local t = ns.defaults
        for j = 1, #e - 2 do t = t and t[e[j]] end
        if type(t) == "table" then t[e[#e - 1]] = deepCopy(e[#e]) end
    end
    local F = ns.defaults.frames
    local T, ToT = F and F.target, F and F.targettarget
    if type(T) == "table" and type(ToT) == "table" and T.point == "CENTER" and ToT.point == "CENTER" then
        ToT.x = (tonumber(T.x) or 240) + T.width / 2 + DESIGN_TOT.gap + ToT.width / 2
        ToT.y = (tonumber(T.y) or -170) + T.height / 2 - ToT.height / 2
    end
    for _, x in ipairs(ns.UF_EXTRA_FRAMES or {}) do
        local mx = x.defaults and ns.MATCH_EXTRA[x.key]
        if mx then
            for _, p in ipairs(mx) do x.defaults[p[1]] = p[3] end
            -- (the fresh design: the focus target is the ToT's twin)
            if x.key == "focustarget" then
                x.defaults.width, x.defaults.height = DESIGN_TOT.w, DESIGN_TOT.h
            end
        end
    end
    ns._matchApplied = true
    return true
end

-- a brand-new save under ZacUI's look takes the fresh design's keys that
-- no save carries until set (ns.MATCH_FRESH_SAVE); a value already there
-- stays
function ns.MatchFreshSave(db)
    if not ns._matchApplied or type(db) ~= "table" then return 0 end
    local n = 0
    for _, e in ipairs(ns.MATCH_FRESH_SAVE) do
        local t = db
        for j = 1, #e - 2 do
            if type(t[e[j]]) ~= "table" then t[e[j]] = {} end
            t = t[e[j]]
        end
        local k = e[#e - 1]
        if t[k] == nil then t[k] = deepCopy(e[#e]) n = n + 1 end
    end
    return n
end

-- a saved value still on the old shipped default (colours within 0.005)
local function sameValue(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(b) do
        local w = a[k]
        if type(v) == "number" and type(w) == "number" then
            if math.abs(v - w) > 0.005 then return false end
        elseif not sameValue(w, v) then return false end
    end
    for k in pairs(a) do if b[k] == nil then return false end end
    return true
end
ns.MatchSame = sameValue

-- Sizes and spacing are never moved on a save that already exists
-- (2026-11-08, Zac: "why is my tot now not alligned?"): a layout built
-- round a frame's size (ZacLayout's, anyone's) keeps it. Only a fresh
-- install draws the new sizes (the overlay on the defaults above).
local GEOMETRY = { width = true, height = true, spacing = true, columnSpacing = true, cbY = true }
local function isGeometry(e)
    local k = e[#e - 1]
    if GEOMETRY[k] then return true end
    if k == "height" then return true end
    return (e[1] == "power" or e[1] == "castbar") and k == "height"
end
ns.MatchIsGeometry = isGeometry

-- moves db's old-default values to the new ones; returns how many moved
function ns.MatchMigrate(db)
    local moved = 0
    for i, e in ipairs(MATCH) do
        local old = ns.MATCH_OLD[i]
        if isGeometry(e) then old = nil end
        local t = db
        for j = 1, #e - 2 do t = type(t) == "table" and t[e[j]] or nil end
        local k = e[#e - 1]
        if type(t) == "table" and old ~= nil and t[k] ~= nil and sameValue(t[k], old) then
            t[k] = deepCopy(e[#e])
            moved = moved + 1
        end
    end
    local frames = db.frames
    for key, list in pairs(ns.MATCH_EXTRA) do
        local c = type(frames) == "table" and frames[key]
        if type(c) == "table" then
            for _, p in ipairs(list) do
                if not GEOMETRY[p[1]] and c[p[1]] ~= nil and sameValue(c[p[1]], p[2]) and not sameValue(p[2], p[3]) then
                    c[p[1]] = p[3]
                    moved = moved + 1
                end
            end
        end
    end
    return moved
end

-- A save the first match pass moved (_matchRev 1) gets its sizes back: a
-- size still on the new number goes back to the old shipped one. Returns
-- how many went back.
function ns.MatchRestoreGeometry(db)
    local back = 0
    for i, e in ipairs(MATCH) do
        local old = ns.MATCH_OLD[i]
        if isGeometry(e) and old ~= nil and not sameValue(old, e[#e]) then
            local t = db
            for j = 1, #e - 2 do t = type(t) == "table" and t[e[j]] or nil end
            local k = e[#e - 1]
            if type(t) == "table" and t[k] ~= nil and sameValue(t[k], e[#e]) then
                t[k] = deepCopy(old)
                back = back + 1
            end
        end
    end
    local frames = db.frames
    for key, list in pairs(ns.MATCH_EXTRA) do
        local c = type(frames) == "table" and frames[key]
        if type(c) == "table" then
            for _, p in ipairs(list) do
                if GEOMETRY[p[1]] and c[p[1]] ~= nil and sameValue(c[p[1]], p[3]) and not sameValue(p[2], p[3]) then
                    c[p[1]] = p[2]
                    back = back + 1
                end
            end
        end
    end
    return back
end
