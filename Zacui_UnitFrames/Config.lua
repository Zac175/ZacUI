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
    locked = false,   -- when false, frames + group headers can be dragged
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
