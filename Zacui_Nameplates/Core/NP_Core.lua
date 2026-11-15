-- NP_Core - the nameplate engine: settings, plate lifecycle, event
-- driver. ZacUI's native replacement for Plater.
-- Part of ZacUI; load order is set by the TOC.
--
-- HOW THIS IS BUILT. Blizzard still owns the plate that tracks the mob
-- in the world - anchoring, pooling, distance culling, protected
-- clicking all stay theirs. When a plate is assigned a unit we hide
-- Blizzard's art on it and dress our own frame over the top, and undress
-- when the unit leaves. That split is what Plater does too, and it is
-- what keeps every part of this insecure and combat-safe: our frames are
-- decoration on a host Blizzard manages.
--
-- THE DEFAULTS ARE ZAC'S PLATER PROFILE ("Naowh"), and not a summary of
-- it: they were produced by deep-merging Plater's stock defaults with
-- the profile's saved diff and reading the merged table, key by key.
-- That is why some look surprising - auras OFF, friendly cast bars OFF -
-- those are what the profile actually said. The one deliberate break
-- from it is the target block (REV 5): the profile had no non-target
-- fade and no size cue, and on a stacked pull that left the white neon
-- as the only way to tell which plate was yours. See DEFAULTS.target.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Col = ns.Col
local Modules = ns.Modules
local Print = ns.Print
local TEX_NORM = ns.TEX_NORM
local ZUI = ns.ZUI

local NP = {}

-- ============================================================
-- SETTINGS - merged Naowh profile, translated key by key
-- ============================================================
local DEFAULTS = {
    friendlyNpcPlates = false,     -- plate_config.friendlynpc.enabled = false
    stacking = true,               -- stacking_nameplates_enabled
    maxDistance = 41,              -- era ceiling
    clickWidth = 140,              -- click_space
    clickHeight = 28,
    clickWidthFriendly = 50,       -- click_space_friendly
    clickHeightFriendly = 1,

    -- LibSharedMedia names from the profile; anything LSM can't find
    -- falls back to ZacUI's flat texture / your ZacUI font.
    healthTexture = "ZacUI Flat",  -- health bar texture (SharedMedia name)
    castTexture = "ZacUI Flat",    -- cast bar texture
    fontName = "Roboto Condensed Bold", -- text face
    -- false on any of the three = ZacUI's own (Appearance > Fonts &
    -- Textures); nil is refilled with the name above, so "ZacUI's" needs
    -- a value of its own. threatTexture nil = the health bar's.
    -- barBg / borderColor nil = the theme's window colour (at 85%) and
    -- border colour, which is what the plates always wore.
    smoothRate = 18,               -- how fast the health fill glides (higher = quicker)

    -- the plates' animations (Nameplates > Animation): every one "none"
    -- by default, which is exactly how the plates have always behaved.
    -- appear/fade/scale run on the engine's own glide (NP_FX), the rest
    -- through ns.Motion; all of them follow Appearance > Motion.
    anim = {
        appear    = { style = "none", duration = 0.2, easing = "easeOutQuad" },
        fade      = { style = "none", duration = 0.2, easing = "easeOutQuad" },
        scale     = { style = "none", duration = 0.15, easing = "easeOutCubic" },
        target    = { style = "none", duration = 0.25, easing = "easeOutBack" },
        cast      = { style = "none", duration = 0.15, easing = "easeOutQuad", dir = "down", distance = 8 },
        interrupt = { style = "none", duration = 0.3 },
        prioWarn  = { style = "none", duration = 0.25, easing = "easeOutBack" },
    },

    enemy = {
        -- 150 x 16 (the profile ran 120 x 10) so the name fits inside the
        -- bar; REV 8 and 9 move the shipped values.
        width = 150, height = 16,          -- health / health_incombat
        combatWidth = 150, combatHeight = 16,
        castbar = true,                    -- hide_enemy_castbars = false
        castWidth = 150, castHeight = 14,  -- cast
        castTextSize = 9,                  -- spellname_text_size
        nameSize = 11,                     -- actorname_text_size (10 in the profile)
        namePos = "inside",                -- "inside" the bar after the level, or "above" it
        nameJustify = "LEFT",              -- inside: "LEFT" or "CENTER"
        -- The raid marker. "above" centres it markerY px over the bar's
        -- top edge - the empty middle of Readycheck's icon row at its
        -- default +20 from the plate's centre - "centre" puts it on the
        -- bar, "left" just outside the bar's left end. markerSize 0 =
        -- a shade taller than the bar.
        markerPos = "above", markerSize = 14, markerX = 0, markerY = 12,
        nameClassColor = false,            -- actorname_use_class_color
        barClassColor = true,              -- use_playerclass_color
        levelShow = true, levelSize = 10,  -- npc yes (players had it off)
        percent = true, percentSize = 9,   -- percent_text_enabled/size
        -- the rest of each text's font (face, outline, shadow); the sizes
        -- stay in the keys above. Empty = the plate font, outlined.
        nameFont = {}, levelFont = {}, percentFont = {}, castFont = {},
        nameColor = { 1, 1, 1, 0.95 },     -- names that are not class coloured
        percentColor = { 1, 1, 1, 1 },
    },
    friendly = {
        nameOnly = true,                   -- only_thename: the profile
                                           -- showed friendlies as just a
                                           -- class-colored name, no bar
        width = 124, height = 12,          -- health
        combatWidth = 142, combatHeight = 16, -- health_incombat
        castbar = false,                   -- hide_friendly_castbars = true
        castWidth = 105, castHeight = 7,   -- cast_incombat
        castTextSize = 8,
        nameSize = 10,
        namePos = "above", nameJustify = "LEFT",
        markerPos = "centre", markerSize = 0, markerX = 0, markerY = 12,
        nameClassColor = true,             -- actorname_use_class_color
        barClassColor = true,
        levelShow = false, levelSize = 9,
        percent = true, percentSize = 8,
        nameFont = {}, levelFont = {}, percentFont = {}, castFont = {},
        nameColor = { 1, 1, 1, 0.95 },
        percentColor = { 1, 1, 1, 1 },
    },
    reaction = {                           -- out-of-combat bar colors
        hostile  = { 0.92, 0.15, 0.15 },
        neutral  = { 1.00, 0.80, 0.00 },
        friendly = { 0.20, 0.85, 0.20 },
    },
    tapped = { 0.373, 0.373, 0.373 },      -- tap_denied_color
    threat = {                             -- tank.colors / dps.colors, merged
        enabled = true,
        role = "AUTO",                     -- AUTO | TANK | DPS
        glowColor = { 1, 0.25, 0.25 },     -- the aggro glow's sheen
        glow = false,                      -- off: with alt boxes in the
                                           -- group, "you ripped it" is
                                           -- every pull - it strobed
        tankAggro   = { 0.380, 0.875, 0.231 },
        tankNoAggro = { 0.996, 0.298, 0.310 },
        tankOther   = { 0.733, 0.196, 1.000 },
        dpsAggro    = { 0.996, 0.298, 0.310 },
        dpsNoAggro  = { 0.733, 0.196, 1.000 },
        pulling     = { 1.000, 0.933, 0.431 },
        solo        = { 0.500, 0.500, 1.000 }, -- dps.colors.solo
    },
    -- the threat bar under the health bar (NP_Threat): your scaled
    -- threat % against that mob, 100 = you pull; flips to "who is about
    -- to take it" on your target while you hold it
    threatBar = {
        enabled = true,
        width = 75,                        -- half the bar, over the target name
        height = 6,
        gap = 1,                           -- px between health bar and strip
        targetOnly = false,                -- every fighting enemy, or just the target
        text = true,                       -- the percent (and name) on the strip's bottom edge
        textSize = 8,
        warnAt = 70,                       -- yellow from here up
        safe    = { 0.200, 0.800, 0.200 },
        warn    = { 1.000, 0.933, 0.431 }, -- the palette's pulling yellow
        danger  = { 0.996, 0.298, 0.310 }, -- the palette's aggro red
        tanking = { 0.380, 0.875, 0.231 }, -- the palette's tank-holds green
        font = {},                         -- face / outline / shadow of the text
        textColor = { 1, 1, 1, 1 },
    },
    target = {
        highlight = false,                 -- target_highlight (off since 2026-11-02, Zac: "get rid of them")
        -- WHITE, not Plater's stock blue: the profile's saved diff
        -- overrides R and G to 1 and inherits B = 1. Drawn as Plater
        -- draws it - the selection_indicator3 neon above and below the
        -- bar - NOT as a border tint.
        color = { 1, 1, 1 },               -- target_highlight_color
        alpha = 0.8,                       -- target_highlight_alpha
        neonHeight = 12,                   -- target_highlight_height
        hover = true,                      -- hover_highlight
        hoverAlpha = 0.2,                  -- hover_highlight_alpha
        hoverColor = { 1, 1, 1 },          -- additive, so white is a plain sheen
        -- The profile shipped with every fade alpha at 1 (no fade) and
        -- the white neon as the ONLY target cue - on a stacked pull that
        -- was not enough to tell which plate was yours. REV 5 turns the
        -- fade on and grows the target plate; both stay user-tunable.
        nonTargetFade = true,
        nonTargetAlpha = 0.75,
        bossNoFade = true,                 -- a boss's plate stays at full strength
        -- mobs whose plates never fade either, nothing else about them
        -- changes (the priority list grows and recolours; this does not)
        noFadeNames = "",
        scale = 1.15,                      -- target plate grows by this
        -- Hold the fade and size cue to combat. Off by default because
        -- the neon always applied out of combat too; on stops the soft
        -- pick from making plates pulse as you walk past mobs.
        combatOnly = false,
        -- 1.15 action targeting: with no hard target, "softenemy" is
        -- what your abilities will actually hit, so it wears the full
        -- target treatment instead of no plate being highlighted at all.
        softTarget = true,
    },
    -- PRIORITY MOBS: plates for the mobs named here never fade, grow to
    -- `scale`, draw above every other plate and take `color` - for the
    -- adds that have to die first (Naxx's Lightning Totems). Names are
    -- comma-separated so the list stays one plain value.
    priority = {
        enabled = true,
        names = "Lightning Totem",
        scale = 1.8,
        recolor = true,
        color = { 0.40, 0.90, 1.00 },      -- light cyan
        -- With two or more priority mobs' plates up, a line mid-screen
        -- counts them by name (2026-10-27, Zac: a second Embalming Slime
        -- he had not seen killed him), so one left is quiet and two is not.
        countWarn = true,
        countFrom = 2,
        countFont = { size = 22 },         -- the mid-screen count's text
        edgeSize = 2,                      -- the threat border round an important plate
    },
    castbar = {
        icon = true,
        spark = true,                      -- the bright line on the bar's moving edge
        textColor = { 1, 1, 1, 1 },        -- the spell name
        interruptHold = 0.5,               -- seconds the "Interrupted" flash stays up
        normal        = { 1.0, 0.933, 0.431 }, -- cast_statusbar_color
        channel       = { 0.0, 1.0, 0.0 },
        uninterruptible = { 0.5, 0.5, 0.5 },
        interrupted   = { 1.0, 0.1, 0.1 },
    },
    auras = {
        enabled = false,                   -- aura_enabled = false. Really.
        mineOnly = true,
        width = 22, height = 14,           -- aura_width/height
        max = 6,
        spacing = 2,                       -- px between icons
        countFont = { size = 8 },          -- the stack count
    },
    -- the profile's Plater MODS, rebuilt as native switches
    extras = {
        raidMark = true,       -- "Raidmark in the Unitname"
        targetArrows = true,   -- "Naowh Arrow Target" / "Double Arrow"
        arrowStyle = "box",    -- box (an outline all round the bar) | brackets (its four corners) | chevron (Naowh's glowing one) | solid (triangles) | thin (Plater's Arrow Thin)
        arrowScale = 1,
        arrowColor = "crosshair", -- crosshair (the crosshair's live colour, white without it) | white | custom
        arrowCustomColor = { 1, 1, 1 }, -- the "custom" choice
        targetNameFont = { size = 8 },  -- the mob's target under the bar
        arrowV2 = false,          -- once: a saved "solid" (yesterday's default, disliked) goes to the chevron
        arrowV3 = false,          -- once: any saved arrow look goes to the brackets picked on 2026-10-19
        arrowV4 = false,          -- once: brackets -> the full box asked for the same day
        targetName = true,     -- "Target Name on Plate"
        castTargetName = true, -- "Cast Target on Spell Name"
        questIcon = true,      -- "Extra Quest Icon"
    },
    -- castAlerts: [spellID] = {r,g,b} bar color override while that
    -- spell is cast (the native form of the profile's cast-alert
    -- script tiers, whose retail spell lists are dead on era).
    castAlerts = {},
}

-- ============================================================
-- MATCH PASS (2026-11-07, zui_tests/MATCH_FRAMES_1107.md)
-- ============================================================
-- Under ZacUI's own look the shipped numbers are the reference UI's
-- plates (sizes, colours, the cast bar, the target glow, the debuff
-- row). An overlay on DEFAULTS, so a fresh table takes them, and a save
-- still on the OLD shipped value is moved once (d._matchRev, in DB()
-- below); a value set by hand stays. The Classic look keeps the old.
-- { path..., new }; the old value is read off DEFAULTS before the overlay
local MATCH = {
    { "enemy", "width", 156 }, { "enemy", "height", 17 },
    { "enemy", "combatWidth", 156 }, { "enemy", "combatHeight", 17 },
    { "enemy", "castWidth", 156 }, { "enemy", "castHeight", 17 }, { "enemy", "castTextSize", 10 },
    -- (2026-11-08, Zac: "nameplates ugly as fuck") the name 14 and the
    -- percent 11, outlined (ApplyNPFont): the reference's 11 / 10 are in
    -- its wide face; in ZacUI's semi-condensed one they read tiny. The
    -- hostile red out of combat 0.62 (the reference's 0.39-0.48 read
    -- brown-black on the dark track); in a fight the threat colours
    -- (0.80 red) take over as before. Fresh tables only: a saved table
    -- keeps its values (CopyDefaults fills missing keys only).
    { "enemy", "nameSize", 14 }, { "enemy", "namePos", "above" }, { "enemy", "nameJustify", "CENTER" },
    { "enemy", "percentSize", 11 }, { "enemy", "nameColor", { 1, 1, 1, 1 } },
    { "friendly", "nameSize", 15 },
    { "reaction", "hostile", { 0.62, 0.12, 0.11 } }, { "reaction", "neutral", { 0.81, 0.72, 0.19 } },
    { "reaction", "friendly", { 0.314, 0.800, 0.408 } }, { "tapped", { 0.5, 0.5, 0.5 } },
    { "threat", "tankAggro", { 0.800, 0.137, 0.137 } }, { "threat", "tankNoAggro", { 1.00, 0.22, 0.17 } },
    { "threat", "tankOther", { 0.188, 0.761, 0.812 } }, { "threat", "dpsAggro", { 1.00, 0.50, 0.00 } },
    { "threat", "dpsNoAggro", { 0.800, 0.137, 0.137 } }, { "threat", "pulling", { 0.81, 0.72, 0.19 } },
    { "threat", "solo", { 0.800, 0.137, 0.137 } },
    { "target", "scale", 1 }, { "target", "nonTargetFade", false }, { "target", "glow", true },
    { "castbar", "normal", { 0.70, 0.40, 0.90 } }, { "castbar", "channel", { 0.70, 0.40, 0.90 } },
    { "castbar", "uninterruptible", { 0.45, 0.45, 0.45 } }, { "castbar", "interrupted", { 0.8, 0.0, 0.0 } },
    { "auras", "enabled", true }, { "auras", "width", 26 }, { "auras", "height", 26 }, { "auras", "max", 5 },
    { "auras", "countFont", { size = 11 } },
    { "extras", "targetArrows", false },
    { "barBg", { 0.12, 0.12, 0.12, 1 } }, { "borderColor", { 0.067, 0.067, 0.067, 1 } },
}
local MATCH_OLD = {}
local function MCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = MCopy(x) end
    return t
end
local function MSame(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(b) do
        local w = a[k]
        if type(v) == "number" and type(w) == "number" then
            if math.abs(v - w) > 0.005 then return false end
        elseif not MSame(w, v) then return false end
    end
    for k in pairs(a) do if b[k] == nil then return false end end
    return true
end
-- the old shipped values, read off DEFAULTS at file load (nothing changed)
for i, e in ipairs(MATCH) do
    local t = DEFAULTS
    for j = 1, #e - 2 do t = t and t[e[j]] end
    if type(t) == "table" then MATCH_OLD[i] = { v = MCopy(t[e[#e - 1]]) } end
end
-- THE OVERLAY, decided ONCE from the latched look (2026-11-08): it used to
-- be decided at file load, where the look had no live answer yet and read
-- as ZacUI's, so a Classic save got the overlay and its migration. Now it
-- waits for Core_Look's PLAYER_LOGIN re-read (Look.Settled); a DB() read
-- before that sees the old defaults and moves nothing. Under a game look
-- it never applies.
local matchOn, matchDecided = false, false
-- THE GAME LOOKS' STOCK STYLE DEFAULTS (2026-11-08): under Classic WoW UI,
-- Blizzard style and WoW Forever the plates' ZacUI-only style defaults to
-- the game's own plates; a value set by hand stays, and the plates'
-- features (threat colours and strip, debuff tracking, priority mobs, the
-- cast bar, raid marks, quest icons) stay as they are:
--   the health percent text   the stock plates show no number
--   the target arrows / box   the stock cue is the plate's own wash
--   the mob's target's name   ZacUI's extra texts on the plate
--   friendly class colours    the stock friendly plates are green / blue
local stockFollowed = false
NP.STOCK_DEFAULTS = {
    { "enemy", "percent", false },
    { "friendly", "percent", false },
    { "friendly", "barClassColor", false },
    { "friendly", "nameClassColor", false },
    { "extras", "targetArrows", false },
    { "extras", "targetName", false },
    { "extras", "castTargetName", false },
}
local function MatchDecide()
    if matchDecided then return end
    local L = ns.Look
    if L and L.Settled and not L.Settled() then return end
    matchDecided = true
    local ok, on = pcall(function() return L and L.Is and L.Is("nameplates", "zacui") end)
    if not (ok and on) then return end
    matchOn = true
    for _, e in ipairs(MATCH) do
        local t = DEFAULTS
        for j = 1, #e - 2 do t = t and t[e[j]] end
        if type(t) == "table" then t[e[#e - 1]] = MCopy(e[#e]) end
    end
end
NP.MATCH, NP.MATCH_OLD = MATCH, MATCH_OLD
-- the plates wear a game look (Classic WoW UI, Blizzard style, WoW Forever):
-- the stock plate's art and cues, none of ZacUI's target boxes (2026-11-08,
-- Zac: "what is with these huge white borders when i target a mob")
function NP.StockLook()
    local L = ns.Look
    local lk = L and L.For and L.For("nameplates")
    return (lk and lk.id ~= "zacui") and true or false
end
function NP.MatchOn() MatchDecide() return matchOn end
-- a save's values still on the old shipped default move to the new one;
-- a key the save lacks is left for CopyDefaults (it takes the new one)
-- The plate's own sizes are never moved on a save that already exists
-- (the unit frames' rule, Zacui_UnitFrames/Config.lua GEOMETRY: "sizes
-- and positions of an existing save are never moved"): a 150 x 16 plate
-- with its 150 x 14 cast bar stays that size; only a fresh table draws
-- the new 156 x 17 (the overlay on DEFAULTS above).
local MATCH_GEOMETRY = { width = true, height = true, combatWidth = true, combatHeight = true,
    castWidth = true, castHeight = true }
local function MatchIsGeometry(e)
    return e[1] == "enemy" and MATCH_GEOMETRY[e[#e - 1]] == true
end
NP.MatchIsGeometry = MatchIsGeometry
-- (a table made this session - a fresh install, a new profile - is not a
-- save that exists: when it was filled before the look settled it holds
-- the old sizes only because DEFAULTS had no overlay yet, so its sizes
-- move with the rest; DB() below notes such tables here)
local matchFreshTables = setmetatable({}, { __mode = "k" })
local function MatchMigrate(d)
    local moved = 0
    local keepSizes = not matchFreshTables[d]
    for i, e in ipairs(MATCH) do
        local rec = MATCH_OLD[i]
        if keepSizes and MatchIsGeometry(e) then rec = nil end
        local t = d
        for j = 1, #e - 2 do t = type(t) == "table" and t[e[j]] or nil end
        local k = e[#e - 1]
        if rec and type(t) == "table" then
            local cur, old = t[k], rec.v
            -- (a key whose old default was nil - "the theme's colour" -
            -- moves while it is still nil)
            if (old == nil and cur == nil) or (cur ~= nil and old ~= nil and MSame(cur, old)) then
                t[k] = MCopy(e[#e])
                moved = moved + 1
            end
        end
    end
    return moved
end
NP.MatchMigrate = MatchMigrate

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- DB() IS THE HOTTEST CALL IN THE ENGINE: every health, colour, threat,
-- target and hover update reads its settings through it, and with eighty
-- plates up in a raid pull that is thousands of calls a second. The
-- migrations and the defaults merge below walk ~160 keys, so they run
-- ONCE per settings table and the result is remembered; after that a
-- read is one comparison. The full pass runs again whenever the table is
-- a different one (a profile switch, the reset button), whenever its
-- revision is not the current one (a wiped table), and whenever
-- RefreshAll runs (any settings change).
local DB_REV = 11        -- keep equal to the last REV migration below; if
                        -- it falls behind, every read takes the full pass
local seeded            -- the settings table the last full pass prepared

local function DB()
    -- (the match overlay, once the look is settled: a table seeded before
    -- it is seeded again, so its migration runs)
    if not matchDecided then
        MatchDecide()
        if matchDecided then seeded = nil end
    end
    -- (the game looks' stock style defaults, once the look is settled)
    if not stockFollowed and ns.Look and ns.Look.Settled and ns.Look.Settled() then
        stockFollowed = true
        seeded = nil
    end
    local d = ZacUIDB.nameplates
    if d and d == seeded and d._rev == DB_REV then return d end
    ZacUIDB.nameplates = d or {}
    d = ZacUIDB.nameplates
    -- (no revision yet: a table made now, not a save - MatchMigrate)
    if d._rev == nil then matchFreshTables[d] = true end
    -- REV 2: the first shipped defaults were a hand summary of the
    -- profile and got several values wrong (percent size, friendly name
    -- size, cast color, fades). Rev 1 tables are discarded wholesale -
    -- rev 2 IS the faithful port, so there is nothing in them to keep.
    -- Guard by "older than the faithful port", NEVER by "not a rev I
    -- know": the moment a rev-4 migration shipped, an exact-match guard
    -- here started wiping the table on every single read - which is why
    -- picking a font in a dropdown appeared to do nothing.
    if not d._rev or d._rev < 2 then
        wipe(d)
        d._rev = 2
    end
    -- REV 3: the target highlight shipped as a blue border tint; the
    -- profile actually ran Plater's white neon strips. Swap ONLY the
    -- exact shipped blue - a color the user picked survives.
    if d._rev == 2 then
        local c = d.target and d.target.color
        if c and math.abs(c[1] - 0) < 0.01 and math.abs(c[2] - 0.522) < 0.01
            and math.abs(c[3] - 1) < 0.01 then
            c[1], c[2], c[3] = 1, 1, 1
        end
        d._rev = 3
    end
    -- REV 4: the aggro glow shipped on and pulsing - in a group full of
    -- alt boxes that meant a strobe on every pull. Forced off once; the
    -- checkbox brings back the (now steady, not flashing) version.
    if d._rev == 3 then
        if d.threat then d.threat.glow = false end
        d._rev = 4
    end
    -- REV 5: the non-target fade shipped off (the profile's fade alphas
    -- were all 1) and the target had no size cue. Turn the fade on ONCE
    -- at the shipped alpha (0.75, same as DEFAULTS above - the two are
    -- meant to agree, so an account that has never seen the fade lands
    -- exactly where a fresh install does),
    -- and only if the pair still holds the untouched shipped values - a
    -- fade the user set themselves, on or off, survives. scale and
    -- softTarget are new keys, so CopyDefaults below seeds them.
    if d._rev == 4 then
        local t = d.target
        if t and t.nonTargetFade == false
            and math.abs((t.nonTargetAlpha or 1) - 1) < 0.01 then
            t.nonTargetFade = true
            t.nonTargetAlpha = 0.75
        end
        d._rev = 5
    end
    -- REV 6: the threat strip first shipped full-width at 4px with 8pt
    -- text; it is now a short strip over the target name. Only the exact
    -- shipped pair is replaced - anything the user set survives. width
    -- is a new key, so CopyDefaults seeds it.
    if d._rev == 5 then
        local t = d.threatBar
        if t and t.height == 4 and t.textSize == 8 then
            t.height, t.textSize = 3, 7
        end
        d._rev = 6
    end
    -- REV 7: the strip grew (40x3, 7pt -> 60x6, 8pt) once the text moved
    -- onto its bottom edge. Same rule: only the exact shipped set moves.
    if d._rev == 6 then
        local t = d.threatBar
        if t and t.width == 40 and t.height == 3 and t.textSize == 7 then
            t.width, t.height, t.textSize = 60, 6, 8
        end
        d._rev = 7
    end
    -- REV 8: the enemy plate became a 16-tall bar with the name inside
    -- it and the raid marker above it, in the gap of Readycheck's icon
    -- row. The exact shipped heights (10 / 10) and name size (10) move;
    -- the old on/off nameInside becomes namePos, and both of its states
    -- land inside, since that is the new look. markerPos and the rest
    -- are new keys, so CopyDefaults seeds them.
    if d._rev == 7 then
        local e = d.enemy
        if e then
            if e.height == 10 and e.combatHeight == 10 then
                e.height, e.combatHeight = 16, 16
            end
            if e.nameSize == 10 then e.nameSize = 11 end
            if e.namePos == nil then e.namePos = "inside" end
            e.nameInside = nil
        end
        if d.friendly then d.friendly.nameInside = nil end
        d._rev = 8
    end
    -- REV 9: the 16-tall enemy bar went from 120 to 150 wide to keep its
    -- shape, with the cast bar and the half-width threat strip under it.
    -- Only the exact shipped widths move.
    if d._rev == 8 then
        local e = d.enemy
        if e and e.width == 120 and e.combatWidth == 120 then
            e.width, e.combatWidth = 150, 150
            if e.castWidth == 120 then e.castWidth = 150 end
        end
        local t = d.threatBar
        if t and t.width == 60 then t.width = 75 end
        d._rev = 9
    end
    -- REV 10: the priority bar colour shipped gold; it is light cyan now.
    -- Only the exact shipped gold moves - a colour the user picked stays.
    if d._rev == 9 then
        local c = d.priority and d.priority.color
        if c and math.abs(c[1] - 1) < 0.01 and math.abs(c[2] - 0.85) < 0.01 and math.abs(c[3]) < 0.01 then
            c[1], c[2], c[3] = 0.40, 0.90, 1.00
        end
        d._rev = 10
    end
    -- REV 11: the white neon strips above and below the target's plate
    -- go off by default (Zac, 2026-11-02: "double white lines when im
    -- targeting someone get rid of them"). Switched off once; the
    -- "Target highlight" box brings them back.
    if d._rev == 10 then
        if d.target then d.target.highlight = false end
        d._rev = 11
    end
    -- the match pass, once, under ZacUI's look (a table that turns to it
    -- later is moved then)
    if matchOn and not d._matchRev then
        MatchMigrate(d)
        d._matchRev = 1
    end
    -- the game looks' stock style defaults (Core_Look's FollowDefaults)
    if stockFollowed and ns.Look and ns.Look.FollowDefaults then
        ns.Look.FollowDefaults(d, DEFAULTS, NP.STOCK_DEFAULTS, "nameplates")
    end
    CopyDefaults(DEFAULTS, d)
    -- npc colors seed ONCE from the ported Plater table (they are user
    -- data, not defaults - a deleted entry must stay deleted, so no
    -- CopyDefaults refill).
    if not d.npcColorsSeeded then
        d.npcColorsSeeded = true
        d.npcColors = d.npcColors or {}
        for id, c in pairs(ns.NP_PORT_NPC_COLORS or {}) do
            d.npcColors[id] = { c[1], c[2], c[3] }
        end
    end
    d.npcColors = d.npcColors or {}
    d.npcNames = d.npcNames or {}   -- learned as plates appear
    seeded = d
    return d
end

-- Is this plate one of the priority mobs? The name list is parsed once
-- per edit, so the check is one lowercase lookup.
local prioSrc, prioSet
local noFadeSrc, noFadeSet
function NP.CheckPriority(f)
    local p = DB().priority
    local on = false
    if p and p.enabled and f.unit and not f.isFriend and not UnitIsPlayer(f.unit) then
        if p.names ~= prioSrc then
            prioSrc, prioSet = p.names, {}
            for n in tostring(p.names or ""):gmatch("[^,\n]+") do
                n = n:gsub("^%s+", ""):gsub("%s+$", ""):lower()
                if n ~= "" then prioSet[n] = true end
            end
        end
        local name = NP.SafeName(f.unit)
        on = name and prioSet[name:lower()] or false
    end
    f._priority = on and true or false
    -- the never-fade list, the same way (2026-10-27, Zac: "deathknight
    -- captains nameplates should never fade")
    local t = DB().target
    local nf = false
    if t and t.noFadeNames and t.noFadeNames ~= "" and f.unit and not f.isFriend then
        if t.noFadeNames ~= noFadeSrc then
            noFadeSrc, noFadeSet = t.noFadeNames, {}
            for n in tostring(t.noFadeNames):gmatch("[^,\n]+") do
                n = n:gsub("^%s+", ""):gsub("%s+$", ""):lower()
                if n ~= "" then noFadeSet[n] = true end
            end
        end
        local name = NP.SafeName(f.unit)
        nf = name and noFadeSet[name:lower()] or false
    end
    f._noFade = nf and true or false
    return f._priority
end

-- ============================================================
-- PRIORITY COUNT - "Embalming Slime x2" mid-screen while two or more
-- priority plates are up. Recounted on plate add/remove and target
-- change only (not per health tick): a walk over the active plates.
-- ============================================================
local prioWarn, prioWarnHolder, prioWarnBox
local prioCounts = {}

-- The count line's look: its font (priority.countFont, 22 by default)
-- in the priority colour. The settings preview's sample line goes
-- through here too.
function NP.StylePrioWarn(fs)
    local p = DB().priority or {}
    local spec = p.countFont
    NP.ApplyNPFont(fs, spec, tonumber(spec and spec.size) or 22)
    local c = p.color or { 0.40, 0.90, 1.00 }
    fs:SetTextColor(c[1], c[2], c[3])
end

local function PriorityWarnFrame()
    if prioWarnHolder then return prioWarnHolder end
    prioWarnHolder = CreateFrame("Frame", "ZacUIPriorityWarn", UIParent)
    prioWarnHolder:SetSize(300, 30)
    prioWarnHolder:SetFrameStrata("HIGH")
    if ns.HUD and ns.HUD.PlaceAnchor then ns.HUD.PlaceAnchor("prioWarn", prioWarnHolder, { x = 0, y = 170 })
    else prioWarnHolder:SetPoint("CENTER", UIParent, "CENTER", 0, 170) end
    if ns.HUD and ns.HUD.RegisterMover then
        ns.HUD.RegisterMover("prioWarn", "Priority mob count", prioWarnHolder, { x = 0, y = 170 })
    end
    -- the line rides a box of its own, so its entrance animation never
    -- touches the holder the mover places
    prioWarnBox = CreateFrame("Frame", nil, prioWarnHolder)
    prioWarnBox:SetSize(300, 30)
    prioWarnBox:SetPoint("CENTER", prioWarnHolder, "CENTER", 0, 0)
    prioWarn = prioWarnBox:CreateFontString(nil, "OVERLAY")
    NP.SetNPFont(prioWarn, 22)
    prioWarn:SetPoint("CENTER")
    prioWarnHolder:Hide()
    return prioWarnHolder
end

local function HideWarn()
    if prioWarnHolder and prioWarnHolder:IsShown() then
        if ns.Motion then ns.Motion.Stop(prioWarnBox) end
        prioWarnHolder:Hide()
    end
end

-- up, with its entrance (Nameplates > Animation) when it was not already
local function ShowWarn(h)
    if h:IsShown() then return end
    h:Show()
    local a = DB().anim
    local spec = a and a.prioWarn
    if ns.Motion and spec and spec.style and spec.style ~= "none" then
        ns.Motion.Show(prioWarnBox, spec)
    end
end

function NP.PriorityCount()
    local p = DB().priority
    if not (p and p.enabled and p.countWarn ~= false) then
        HideWarn()
        return
    end
    wipe(prioCounts)
    local total = 0
    for _, f in pairs(NP.ActivePlates()) do
        if f._priority and f.unit and UnitExists(f.unit) and not UnitIsDeadOrGhost(f.unit) then
            local n = NP.SafeName(f.unit) or "?"
            prioCounts[n] = (prioCounts[n] or 0) + 1
            total = total + 1
        end
    end
    if total < (tonumber(p.countFrom) or 2) then
        HideWarn()
        return
    end
    local h = PriorityWarnFrame()
    local parts = {}
    for n, c in pairs(prioCounts) do parts[#parts + 1] = n .. " x" .. c end
    table.sort(parts)
    prioWarn:SetText(table.concat(parts, "   "))
    NP.StylePrioWarn(prioWarn)
    ShowWarn(h)
end
-- a plate's priority flag is settled in UpdateName; the count follows
-- from the add/remove and target passes below
function NP.PriorityWarnDemo(on)
    local h = PriorityWarnFrame()
    if on then
        prioWarn:SetText("Embalming Slime x2")
        NP.StylePrioWarn(prioWarn)
        HideWarn()
        ShowWarn(h)
    else
        NP.PriorityCount()
    end
end

-- A unit's GUID and name, or nil while WoW Forever hides them (an enemy's
-- in a fight comes back as a secret value: no keying, comparing or
-- splitting it). On the other clients exactly UnitGUID / UnitName.
function NP.SafeGUID(unit)
    local g = UnitGUID(unit)
    if ns.IsSecret(g) then return nil end
    return g
end
function NP.SafeName(unit)
    local n = UnitName(unit)
    if ns.IsSecret(n) then return nil end
    return n
end

-- npc id out of a unit's guid: Creature-0-xxxx-xxxx-xxxx-NPCID-yyyy
function NP.NpcIdFromUnit(unit)
    local guid = unit and NP.SafeGUID(unit)
    if not guid then return nil end
    local kind, _, _, _, _, npcId = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then
        return tonumber(npcId)
    end
    return nil
end

-- ============================================================
-- MEDIA (the part files use these too)
-- ============================================================
-- ZacUI's own bar textures and fonts (Core_MediaNames), resolved here
-- first so the plates never depend on SharedMedia being loaded; LSM is
-- only consulted for names ZacUI does not carry. A name saved by an
-- earlier version resolves to what replaced it (ns.NewMediaName).
local MEDIA_NP = [[Interface\AddOns\ZacUI\Media\Nameplates\]]
local LOCAL_MEDIA = { statusbar = {}, font = {} }
for _, b in ipairs(ns.MEDIA_BARS or {}) do LOCAL_MEDIA.statusbar[b.name] = b.path end
for _, f in ipairs(ns.MEDIA_FONTS or {}) do LOCAL_MEDIA.font[f.name] = f.path end
NP.TEX_ARROW_THIN = MEDIA_NP .. "arrowThin"
-- the other target-arrow looks: a rounded glowing chevron, and a solid
-- triangle (ZacUI's own arrow art, turned to point at the plate)
NP.TEX_ARROW_CHEVRON = ns.MEDIA_TEX_CHEVRON or [[Interface\AddOns\ZacUI\Media\Textures\target_chevron]]
NP.TEX_ARROW_SOLID = [[Interface\AddOns\ZacUI\Media\arrow]]

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- Publish ZacUI's own files to SharedMedia (Core_SharedMedia does the
-- same; LSM keeps the first registration), so a plate-only setup still
-- lists them.
local function RegisterMedia()
    local lsm = LSM()
    if not lsm then return end
    for kind, list in pairs(LOCAL_MEDIA) do
        for name, path in pairs(list) do
            pcall(lsm.Register, lsm, kind, name, path)
        end
    end
end

local function FontPath()
    -- one font: ZacUI's, whenever one is chosen (the plate font saved in
    -- fontName counts only while ZacUI has none); the game's own under
    -- the Classic look (Core_Look)
    local one = ns.OneFace and ns.OneFace("nameplates")
    if one then return one end
    local d = DB()
    local name = d.fontName
    name = ns.NewMediaName and ns.NewMediaName(name) or name
    if name and LOCAL_MEDIA.font[name] then
        return LOCAL_MEDIA.font[name]
    end
    local lsm = LSM()
    if lsm and name and name ~= "" then
        local p = lsm:Fetch("font", name, true)
        if p then return p end
    end
    local cfg = ZacUIDB and ZacUIDB.font
    local p = cfg and ns.ResolveFontPath(cfg.name)
    if p then return p end
    local gp = GameFontHighlight and GameFontHighlight:GetFont()
    return gp or [[Fonts\FRIZQT__.TTF]]
end

-- SetFont that says whether the face took: pcall catches a nil path, the
-- return value a font file that would not load - which leaves the string
-- with no font, so its next SetText errors ("Font not set")
local function TrySetFont(fs, path, size, flags)
    local ok, set = pcall(fs.SetFont, fs, path, size, flags)
    return (ok and set) and true or false
end
local function SetNPFont(fs, size)
    if not TrySetFont(fs, FontPath(), size, "OUTLINE") then
        fs:SetFont(STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]], size, "OUTLINE")
    end
    fs:SetShadowOffset(0, 0)
    -- the plate font (ZacUI's unless the page picks one), kept up when it
    -- changes - the lines outside a plate too (the priority count)
    if ns.TrackHouseFont then ns.TrackHouseFont(fs, function(s) SetNPFont(s, size) end) end
end

-- One text's face: the plate font above, always. A face saved in a text's
-- font spec (the per-text pickers of old) is kept there and ignored.
local function FaceFile(face)
    return FontPath()
end

-- A plate text from its font spec ({ face, outline, shadow, shadowX,
-- shadowY } - the house font shape) at `size`. An empty spec is exactly
-- SetNPFont: the plate font, outlined, no shadow - which is what every
-- plate text wore before the specs existed.
local function ApplyNPFont(fs, spec, size)
    if type(spec) ~= "table" or not (spec.face or spec.outline or spec.shadow) then
        -- (2026-11-08) nothing saved: the plate font, OUTLINED, under every
        -- look - the match pass's shadow-only text (the reference's) is
        -- gone, as on the unit frames (Zac: "what happened to the black
        -- border on text"; "nameplates ugly as fuck")
        return SetNPFont(fs, size)
    end
    local flags = "OUTLINE"
    if spec.outline ~= nil and ns.FontOutlineFlags then flags = ns.FontOutlineFlags(spec.outline) end
    if not TrySetFont(fs, FaceFile(spec.face), size, flags)
       and not TrySetFont(fs, FontPath(), size, flags) then
        fs:SetFont(STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]], size, flags)
    end
    if ns.TrackHouseFont then
        ns.TrackHouseFont(fs, function(s) ApplyNPFont(s, spec, size) end)
    end
    if spec.shadow then
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
        fs:SetShadowOffset(tonumber(spec.shadowX) or 1, tonumber(spec.shadowY) or -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- kind = "healthTexture" | "castTexture" | "threatTexture". false is
-- ZacUI's own texture; the threat strip with none of its own wears the
-- health bar's.
local function BarTexture(kind)
    local d = DB()
    local name = d[kind]
    if name == nil and kind == "threatTexture" then return BarTexture("healthTexture") end
    if name == false then
        return (ns.ResolveBarTexture and ns.ResolveBarTexture(nil, "nameplates")) or TEX_NORM
    end
    -- the shipped name follows the look (Core_Look): under the Classic look
    -- it is the game's bar; a texture picked by hand is the player's
    if name == DEFAULTS[kind] and ns.Look and ns.Look.Is("nameplates", "classic") then
        return ns.Look.For("nameplates").barTexture
    end
    -- HD polish (2026-11-07): under ZacUI's look the shipped name is the
    -- look's flat fill (a texture picked by hand is drawn as picked)
    if name == DEFAULTS[kind] and ns.Look and ns.Look.Is("nameplates", "zacui") then
        return ns.Look.For("nameplates").barTexture or TEX_NORM
    end
    name = ns.NewMediaName and ns.NewMediaName(name) or name
    if name and LOCAL_MEDIA.statusbar[name] then
        return LOCAL_MEDIA.statusbar[name]
    end
    local lsm = LSM()
    if lsm and name and name ~= "" then
        local p = lsm:Fetch("statusbar", name, true)
        if p then return p end
    end
    -- (an unknown name: the look's bar - ZacUI's gradient, or the game's
    -- under the Classic look)
    return (ns.Look and ns.Look.For("nameplates").barTexture) or TEX_NORM
end

-- The fill behind a bar and the 1px edge round it: the theme's window
-- colour at 85% and its border colour unless the plates have their own
-- (barBg / borderColor). Health, cast and threat bars all go through it.
-- The plates' edge on the standard (d.chrome, Nameplates > Look): its
-- background / border colours stand in for barBg / borderColor, plus the
-- border's thickness and a shadow / glow round the bars. Nothing saved =
-- the exact old paint below and no extra piece made.
local function ChromeOf(d)
    local ch = d.chrome
    if type(ch) == "table" and next(ch) ~= nil then return ch end
    return nil
end
local SG = {}            -- the shadow / glow part of the spec, reused
local SG_KEYS = { "shadowSize", "shadowColor", "glowSize", "glowColor" }
local function ChromeExtras(frame, ch, withBg)
    local strips = frame._zui_borderTex
    if strips then
        local size = ch and tonumber(ch.borderSize) or 1
        for i, t in ipairs(strips) do
            if size <= 0 then t:Hide() else
                t:Show()
                -- physical pixels under ZacUI's look (Core_Pixel, HD polish)
                if not (ns.Pixel and ns.Pixel.SetEdgeSize(t, size)) then
                    if i <= 2 then t:SetHeight(size) else t:SetWidth(size) end
                end
            end
        end
    end
    -- shadow and glow round the bars only (not the small aura icons)
    if withBg and ns.ApplyChrome then
        for _, k in ipairs(SG_KEYS) do SG[k] = ch and ch[k] or nil end
        ns.ApplyChrome(frame, SG, nil)
    end
end

local function BarChrome(bg, frame)
    local d = DB()
    local ch = ChromeOf(d)
    local c = (ch and ch.bgColor) or d.barBg
    if bg then
        if type(c) == "table" then
            bg:SetColorTexture(c[1] or c.r or 0, c[2] or c.g or 0, c[3] or c.b or 0, c[4] or c.a or 0.85)
        else
            local w = Col("windowBg")
            bg:SetColorTexture(w.r, w.g, w.b, 0.85)
        end
    end
    if frame and frame._zui_borderTex then
        local b = (ch and ch.borderColor) or d.borderColor
        -- a Classic edge (Core_Look) keeps the art's own colour: the border
        -- colour here is the ZacUI look's
        if frame._zui_borderTex._zEdge then
            if ns.TintBorder then ns.TintBorder(frame) end
        elseif type(b) == "table" then
            for _, t in ipairs(frame._zui_borderTex) do
                t:SetColorTexture(b[1] or b.r or 0, b[2] or b.g or 0, b[3] or b.b or 0, b[4] or b.a or 1)
            end
        elseif ns.TintBorder then
            ns.TintBorder(frame)
        end
    end
    if frame and (ch or frame._npChrome) then
        frame._npChrome = ch and true or nil
        ChromeExtras(frame, ch, bg ~= nil)
    end
end

-- what the Look tab's edge picker shows with nothing saved: the colours
-- the bars wear today (their own, else the theme's) and a 1 px border
local CHROME_DEF = { borderSize = 1, shadowSize = 0, glowSize = 0 }
local function ChromeDefaults()
    local d = DB()
    local c, b = d.barBg, d.borderColor
    if type(c) == "table" then
        CHROME_DEF.bgColor = { r = c[1] or c.r or 0, g = c[2] or c.g or 0, b = c[3] or c.b or 0, a = c[4] or c.a or 0.85 }
    else
        local w = Col("windowBg")
        CHROME_DEF.bgColor = { r = w.r, g = w.g, b = w.b, a = 0.85 }
    end
    if type(b) == "table" then
        CHROME_DEF.borderColor = { r = b[1] or b.r or 0, g = b[2] or b.g or 0, b = b[3] or b.b or 0, a = b[4] or b.a or 1 }
    else
        local k = Col("border")
        CHROME_DEF.borderColor = { r = k.r, g = k.g, b = k.b, a = k.a or 1 }
    end
    return CHROME_DEF
end

-- PER-STATE LOOKS on the standard (d.states.<id>, Nameplates > Look):
-- an important plate's bar, and the cast bar while casting, channelling,
-- unstoppable or interrupted. Each field set paints over the state's
-- usual colour (the defaults below ARE those colours); a field taken
-- away is put back from the plate's own settings. Nothing saved = not
-- one extra call on a plate.
local STATE_LIST = {
    { id = "important", label = "Important plate" },
    { id = "casting", label = "Casting" },
    { id = "channel", label = "Channelling" },
    { id = "uninterruptible", label = "Can't be interrupted" },
    { id = "interrupted", label = "Interrupted" },
}
local STATE_DEF = { important = {}, casting = {}, channel = {}, uninterruptible = {}, interrupted = {} }
local function StateDefaults()
    local d = DB()
    local cb = d.castbar
    STATE_DEF.important.color = d.priority.color
    for id, key in pairs({ casting = "normal", channel = "channel", uninterruptible = "uninterruptible", interrupted = "interrupted" }) do
        STATE_DEF[id].color = cb[key]
        STATE_DEF[id].textColor = cb.textColor
    end
    return STATE_DEF
end
local function StateOf(id)
    local st = DB().states
    local s = id and type(st) == "table" and st[id]
    return type(s) == "table" and s or nil
end
local function RGBA(c, fa)
    return c[1] or c.r or 1, c[2] or c.g or 1, c[3] or c.b or 1, c[4] or c.a or fa or 1
end
local function TintStrips(frame, c)
    local strips = frame._zui_borderTex
    if not strips then return end
    local r, g, b, a = RGBA(c)
    for _, t in ipairs(strips) do t:SetColorTexture(r, g, b, a) end
end
-- bar: the status bar; text: its FontString; restoreText(): puts the
-- text's own colour back; id: the state now (nil = none of these)
local function PaintState(bar, text, id, alpha, restoreText)
    local s = StateOf(id)
    if not (s or bar._npSt) then return end
    bar._npSt = s and true or nil
    local c = s and s.color
    if c then local r, g, b = RGBA(c) bar:SetStatusBarColor(r, g, b, alpha) end
    local tc = s and s.textColor
    if tc and text then
        text:SetTextColor(RGBA(tc))
        bar._npStT = true
    elseif bar._npStT then
        bar._npStT = nil
        if restoreText then restoreText() end
    end
    local bc = s and s.border
    if bc then
        TintStrips(bar, bc)
        bar._npStB = true
    elseif bar._npStB then
        bar._npStB = nil
        BarChrome(nil, bar)
    end
end

local function IsFriend(unit)
    return UnitIsFriend("player", unit) and true or false
end

-- The profile resized friendly plates in combat (124x12 -> 142x16), so
-- size reads go through here rather than straight at the table.
-- `combat` overrides the live state (the sample plates in the settings
-- preview say which sizes they show).
local function Dims(cfg, combat)
    if combat == nil then combat = UnitAffectingCombat("player") end
    if combat then
        return cfg.combatWidth or cfg.width, cfg.combatHeight or cfg.height
    end
    return cfg.width, cfg.height
end

-- A plate's bar size: the live combat state, or the sample's own.
local function FrameDims(f)
    local d = DB()
    local cfg = f.isFriend and d.friendly or d.enemy
    if f.preview then return Dims(cfg, f._pvCombat and true or false) end
    return Dims(cfg)
end

-- ============================================================
-- PLATE POOL
-- ============================================================
local frames = {}      -- [base plate] = our frame
local active = {}      -- [unitToken] = our frame
local byGUID = {}      -- [unit GUID] = our frame (the plate showing it)
function NP.ActivePlates() return active end

local function HideBlizzardArt(base)
    local uf = base.UnitFrame
    if not uf then return end
    uf:Hide()
    if not uf._zuiNPGuard then
        uf._zuiNPGuard = true
        uf:HookScript("OnShow", function(self)
            if NP.enabled then self:Hide() end
        end)
    end
end

local function Acquire(base)
    local f = frames[base]
    if f then return f end
    f = CreateFrame("Frame", nil, base)
    f:SetPoint("CENTER", base, "CENTER", 0, 0)
    f:SetSize(120, 32)
    f:EnableMouse(false)
    frames[base] = f
    NP.BuildHealth(f)
    NP.BuildCast(f)
    NP.BuildAuras(f)
    NP.BuildExtras(f)
    if NP.BuildThreat then NP.BuildThreat(f) end

    -- PUBLIC SURFACE for other addons (Readycheck's sunder counter,
    -- WeakAuras, anything Plater-aware): the frame is reachable from
    -- the base plate, and the bars wear Plater's member names. Safe
    -- because this engine stands down whenever real Plater is running.
    base._zuiNP = f
    f.healthBar = f.health
    f.castBar = f.cast
    f.PlateFrame = base
    return f
end

-- ============================================================
-- LAYOUT STAMP
-- ============================================================
-- LayoutFrame re-fits every size, texture and font on the plate - a dozen
-- SetFont calls and as many re-anchors. Its inputs are the settings, the
-- font file, which side the unit is on and the bar size for the current
-- combat state - nothing about the unit itself - so a recycled plate that
-- was last laid out under the same set is already right. In a big pull
-- plates come and go constantly as mobs die and the camera turns; this
-- is what keeps that churn, and the start of every fight, from re-fitting
-- plates that have not changed.
local layoutEpoch = 0   -- bumped by RefreshAll: any settings change

local function Layout(f)
    NP.LayoutFrame(f)
    local d = DB()
    f._layEpoch = layoutEpoch
    f._layFriend = f.isFriend
    f._layFont = FontPath()
    f._layW, f._layH = Dims(f.isFriend and d.friendly or d.enemy)
end

local function LayoutIfStale(f)
    local d = DB()
    local w, h = Dims(f.isFriend and d.friendly or d.enemy)
    if f._layEpoch ~= layoutEpoch
        or f._layFriend ~= f.isFriend
        or f._layW ~= w or f._layH ~= h
        or f._layFont ~= FontPath() then
        Layout(f)
    end
end

-- ============================================================
-- COALESCED UPDATES
-- ============================================================
-- Health, aura and threat events arrive per unit token and far faster
-- than a frame: forty mobs under raid AoE is hundreds of UNIT_HEALTH a
-- second (and UNIT_HEALTH_FREQUENT doubles each one), and
-- UNIT_THREAT_SITUATION_UPDATE - which asks for EVERY plate to be
-- recoloured - fires once per raid member per aggro flip. Handling each
-- one inline meant the same plate was repainted many times inside a
-- single frame. The events only mark what changed; this runs the work
-- once on the next frame. Bar colour and the threat strip are further
-- held to COLOR_INTERVAL, since the half-second combat sweep already
-- backs them up.
local COLOR_INTERVAL = 0.1

local dirtyHealth, dirtyAura, dirtyColor = {}, {}, {}
local sweepColor = false
local lastColorFlush = 0
local flushArmed = false
local flusher = CreateFrame("Frame")
flusher:Hide()

local function Arm()
    if not flushArmed then
        flushArmed = true
        flusher:Show()
    end
end

-- NAME-ONLY PLATES HAVE NO BAR. A friendly shown as just a name (the
-- profile's whole friendly look) has its health bar hidden, and with it
-- the percent, the bar colour, the aggro glow and the threat strip - so
-- the health and colour passes have nothing to paint there. In a raid
-- with friendly plates on that is half of all plates. They are still
-- painted in full when the plate is assigned and on RefreshAll, which is
-- also where name-only is decided, so a plate that gets its bar back
-- arrives up to date.

-- every plate with a bar, right now; also what the half-second sweep
-- counts as
local function ColorAll()
    sweepColor = false
    wipe(dirtyColor)
    lastColorFlush = GetTime()
    for _, f in pairs(active) do
        if not f.nameOnly then NP.UpdateColor(f) end
    end
end

flusher:SetScript("OnUpdate", function()
    -- clearing a key during traversal is safe; nothing below adds one
    for f in pairs(dirtyHealth) do
        dirtyHealth[f] = nil
        NP.UpdateHealth(f)
    end
    for f in pairs(dirtyAura) do
        dirtyAura[f] = nil
        NP.UpdateAuras(f)
        if NP.Scripts then NP.Scripts.AuraChanged(f) end
    end
    if sweepColor or next(dirtyColor) then
        if GetTime() - lastColorFlush < COLOR_INTERVAL then
            return          -- stay armed; colour is due shortly
        end
        if sweepColor then
            ColorAll()
        else
            lastColorFlush = GetTime()
            for f in pairs(dirtyColor) do
                dirtyColor[f] = nil
                NP.UpdateColor(f)
            end
        end
    end
    flushArmed = false
    flusher:Hide()
end)

local function ForgetDirty(f)
    dirtyHealth[f], dirtyAura[f], dirtyColor[f] = nil, nil, nil
end

local lastHover          -- the plate frame the cursor was last over

-- ============================================================
-- LIFECYCLE
-- ============================================================
local function OnUnitAdded(unit)
    if UnitIsUnit(unit, "player") then return end
    local base = C_NamePlate.GetNamePlateForUnit(unit)
    if not base then return end

    HideBlizzardArt(base)
    local f = Acquire(base)
    if f.guid and byGUID[f.guid] == f then byGUID[f.guid] = nil end
    f.unit = unit
    f.guid = NP.SafeGUID(unit)
    f.isFriend = IsFriend(unit)
    active[unit] = f
    if f.guid then byGUID[f.guid] = f end
    ForgetDirty(f)      -- everything below repaints it in full

    -- The npc id is read once here and kept on the frame: the colour
    -- pass wants it on every update, and digging it out of the GUID is a
    -- seven-way string split. false = "not a creature", as opposed to
    -- nil = "not read yet".
    local npcId = NP.NpcIdFromUnit(unit)
    f.npcId = npcId or false
    -- a boss (skull level or world boss) is read once here: its plate
    -- never fades behind the target's (2026-10-27, Zac: Faerlina and
    -- her adds - "boss nameplates should never fade")
    f.isBoss = (UnitClassification(unit) == "worldboss" or UnitLevel(unit) == -1) and true or false

    -- learn creature names for the npc-color list in the config
    if npcId then
        local d = DB()
        if d.npcColors[npcId] and not d.npcNames[npcId] then
            d.npcNames[npcId] = UnitName(unit)
        end
    end

    LayoutIfStale(f)
    NP.UpdateHealth(f)
    NP.UpdateName(f)
    NP.UpdateColor(f)
    NP.UpdateTarget(f, true)
    NP.UpdateHover(f)
    NP.UpdateAuras(f)
    NP.UpdateExtras(f)
    NP.CheckCast(f)
    f:Show()
    -- the plate's entrance (Nameplates > Animation; none by default)
    if NP.FX then NP.FX.Appear(f) end
    if f._priority then NP.PriorityCount() end
    if NP.Scripts then NP.Scripts.PlateAdded(f) end
    -- the debuff module rides this lifecycle rather than registering the
    -- plate events itself, so it can never run before the plate is dressed
    if NP.Debuffs and NP.Debuffs.OnAdded then NP.Debuffs.OnAdded(unit) end
end

local function OnUnitRemoved(unit)
    local f = active[unit]
    if not f then return end
    active[unit] = nil
    if f.guid and byGUID[f.guid] == f then byGUID[f.guid] = nil end
    if lastHover == f then lastHover = nil end
    if NP.Debuffs and NP.Debuffs.OnRemoved then NP.Debuffs.OnRemoved(unit) end
    -- scripts get their OnHide while the unit token is still readable
    if NP.Scripts then NP.Scripts.PlateRemoved(f) end
    NP.StopCast(f)
    ForgetDirty(f)
    if NP.FX then NP.FX.Forget(f) end
    f.unit, f.guid, f.npcId, f.isBoss = nil, nil, nil, nil
    local wasPrio = f._priority
    f._priority, f._prioDead, f._noFade = nil, nil, nil
    f:Hide()
    if wasPrio then NP.PriorityCount() end
end

-- ============================================================
-- TARGET / HOVER / ALPHA PASS
-- ============================================================
-- Which unit is "the target" for plate purposes. The hard target always
-- wins. With none, and softTarget on, the soft enemy stands in: under
-- 1.15 action targeting (SoftTargetEnemy, which NP_SoftTarget drives)
-- that IS the mob your next ability hits, and without this a
-- soft-target-only pull highlighted no plate at all - the only cue was
-- the soft-target arrow. "softenemy" is a real unit token on this
-- client; on a build without it UnitExists just answers false.
local function EffectiveTargetExists(d)
    if UnitExists("target") then return true end
    return d.target.softTarget and UnitExists("softenemy") or false
end

local function IsEffectiveTarget(unit, d)
    if UnitIsUnit(unit, "target") then return true end
    if d.target.softTarget and not UnitExists("target")
        and UnitExists("softenemy") and UnitIsUnit(unit, "softenemy") then
        return true
    end
    return false
end

-- The plate's alpha and scale go through NP_FX, which glides them when
-- the fade / size animations are on (Nameplates > Animation) and sets
-- them at once otherwise - and always when there is no NP_FX at all.
local function PlateAlpha(f, a, instant)
    local FX = NP.FX
    if FX then FX.Alpha(f, a, instant) else f:SetAlpha(a) end
end
local function PlateScale(f, s, instant)
    local FX = NP.FX
    if FX then FX.Scale(f, s, instant) elseif f:GetScale() ~= s then f:SetScale(s) end
end

function NP.UpdateTarget(f, instant)
    local d = DB()
    local isTarget = f.unit and IsEffectiveTarget(f.unit, d)
    -- The fade and the size cue can be held to combat: out of it, with
    -- always-on soft targeting, the soft pick follows the camera and the
    -- plates would fade and grow as you walk past mobs. The neon is
    -- exempt - it was always on out of combat and is not a whole-plate
    -- change.
    local cue = (not d.target.combatOnly) or UnitAffectingCombat("player")
    NP.ApplyTargetState(f, isTarget and true or false, EffectiveTargetExists(d), cue, instant)
end

-- The target treatment from the facts alone - is this plate the target,
-- is there a target at all, does the fade/size cue apply right now - so
-- the settings preview's sample plates wear it through the very same
-- code as a live plate. instant: no animation (a new plate, a settings
-- change, a preview update).
-- The fade on the standard's visibility shape (d.visibility, Nameplates >
-- General): alpha = the other plates' opacity while you have a target,
-- combatAlpha = the same in combat. The defaults ARE the old switches:
-- "Fade everything else" at its opacity, out of combat only when the fade
-- is not held to combat.
local FADE_DEF = {}
local function FadeDefaults()
    local t = DB().target
    local a = t.nonTargetFade and (tonumber(t.nonTargetAlpha) or 1) or 1
    FADE_DEF.combatAlpha = a
    FADE_DEF.alpha = t.combatOnly and 1 or a
    return FADE_DEF
end
NP.FadeDefaults = FadeDefaults

function NP.ApplyTargetState(f, isTarget, anyTarget, cue, instant)
    local d = DB()
    local prio = f._priority and d.priority and d.priority.enabled
    local vis = d.visibility
    if type(vis) ~= "table" or next(vis) == nil then vis = nil end
    if prio then
        PlateAlpha(f, 1, instant)
    elseif vis and anyTarget then
        local keep = isTarget or f._noFade or (f.isBoss and d.target.bossNoFade ~= false)
        local inCombat
        if f.preview then inCombat = f._pvCombat and true or false
        else inCombat = UnitAffectingCombat("player") and true or false end
        local a = (inCombat and tonumber(vis.combatAlpha)) or tonumber(vis.alpha)
        if a == nil then a = FadeDefaults()[inCombat and "combatAlpha" or "alpha"] end
        PlateAlpha(f, keep and 1 or a, instant)
    elseif cue and d.target.nonTargetFade and anyTarget then
        local keep = isTarget or f._noFade or (f.isBoss and d.target.bossNoFade ~= false)
        PlateAlpha(f, keep and 1 or d.target.nonTargetAlpha, instant)
    else
        PlateAlpha(f, 1, instant)
    end
    -- above every other plate, so a pack cannot bury it (not a settings
    -- preview sample: HIGH would lift it out of the settings window)
    if not f.preview then
        if not f._zStrata then f._zStrata = f:GetFrameStrata() end
        local strata = prio and "HIGH" or f._zStrata
        if f:GetFrameStrata() ~= strata then f:SetFrameStrata(strata) end
    end
    -- the neon strips above and below the bar, exactly Plater's
    -- UpdateTargetHighlight; the border itself stays house black
    -- (under a game look none of ZacUI's own target boxes: the stock
    -- plate's cue instead, a white wash over the bar - NP_ClassicPlate)
    local stock = NP.StockLook()
    NP.SetTargetNeon(f, isTarget and d.target.highlight and not stock)
    -- the match pass's target cue: a soft glow round the bar (NP_Health)
    if NP.SetTargetGlow then NP.SetTargetGlow(f, isTarget and d.target.glow and not stock and true or false) end
    if NP.StockTargetWash then NP.StockTargetWash(f, stock and isTarget) end
    -- Size cue. The frame hangs off a single CENTER anchor on the base
    -- plate, so SetScale grows it about its middle and the name, bar,
    -- cast bar and anything anchored to them (the soft-target arrows
    -- ride f.name) all follow. Everything not the target is put
    -- back to 1 here, which is also what un-grows the previous target -
    -- this pass runs for every plate on each target change.
    local scale = (isTarget and cue) and (d.target.scale or 1) or 1
    if prio then scale = math.max(scale, tonumber(d.priority.scale) or 1) end
    -- SetScale(0) is a hard error; a hand-edited saved value is the
    -- only way to get one, but the plates must never die to it
    if type(scale) ~= "number" or scale <= 0 then scale = 1 end
    PlateScale(f, scale, instant)
    -- the target marks' entrance (Nameplates > Animation) as a plate
    -- becomes the target
    local FX = NP.FX
    if FX then FX.TargetMarks(f, isTarget and true or false, instant) end
end

function NP.UpdateHover(f)
    local d = DB()
    -- (2026-11-09) under a game look no white wash on mouseover either:
    -- the stock plates keep their colours
    local hovered = d.target.hover and f.unit and not NP.StockLook()
        and UnitIsUnit(f.unit, "mouseover")
    NP.SetHoverGlow(f, hovered and d.target.hoverAlpha or 0)
end

local function TargetChanged()
    for _, f in pairs(active) do NP.UpdateTarget(f) end
end
local questDirty = false -- QUEST_LOG_UPDATE came in; the sweep re-reads

-- ============================================================
-- ROLE (for the threat palette)
-- ============================================================
local playerClass       -- read once; asked for per plate per colour pass
function NP.PlayerIsTank()
    local d = DB()
    if d.threat.role == "TANK" then return true end
    if d.threat.role == "DPS" then return false end
    if not playerClass then
        local _, class = UnitClass("player")
        playerClass = class
    end
    if playerClass ~= "WARRIOR" and playerClass ~= "DRUID" then return false end
    local form = GetShapeshiftForm and GetShapeshiftForm() or 0
    if playerClass == "WARRIOR" then return form == 2 end
    return form == 1
end

-- ============================================================
-- LIVE REFRESH (config page + combat resize + module re-run)
-- ============================================================
function NP.RefreshAll()
    -- a settings change: take the full defaults pass again, and let no
    -- plate keep a layout from before it
    seeded = nil
    layoutEpoch = layoutEpoch + 1
    if not NP.enabled then return end
    NP.ApplyCVars()
    for unit, f in pairs(active) do
        f.isFriend = IsFriend(unit)
        Layout(f)
        NP.UpdateHealth(f)
        NP.UpdateName(f)
        NP.UpdateColor(f)
        NP.UpdateTarget(f, true)
        NP.UpdateHover(f)
        NP.UpdateAuras(f)
        NP.UpdateExtras(f)
        NP.CheckCast(f)
    end
end

-- ============================================================
-- CVARS
-- ============================================================
function NP.ApplyCVars()
    if InCombatLockdown and InCombatLockdown() then
        NP._cvarsPending = true
        return
    end
    NP._cvarsPending = nil
    local d = DB()
    -- SETUP2: through ns.CVar (recorded; put back when the plates are off)
    local function Set(name, value)
        if ns.CVar then ns.CVar.Set(name, value, "nameplates") else pcall(SetCVar, name, value) end
    end
    Set("nameplateShowFriendlyNPCs", d.friendlyNpcPlates and 1 or 0)
    Set("nameplateMotion", d.stacking and 1 or 0)
    Set("nameplateMaxDistance", d.maxDistance)
    if C_NamePlate and C_NamePlate.SetNamePlateEnemySize then
        pcall(C_NamePlate.SetNamePlateEnemySize,
            d.clickWidth, d.clickHeight)
    end
    if C_NamePlate and C_NamePlate.SetNamePlateFriendlySize then
        pcall(C_NamePlate.SetNamePlateFriendlySize,
            d.clickWidthFriendly, math.max(1, d.clickHeightFriendly))
    end
end

-- ============================================================
-- EVENT DRIVER
-- ============================================================
local driver = CreateFrame("Frame")

local UNIT_EVENTS = {
    UNIT_HEALTH = "UpdateHealth",
    UNIT_MAXHEALTH = "UpdateHealth",
    UNIT_HEALTH_FREQUENT = "UpdateHealth",
    UNIT_NAME_UPDATE = "UpdateName",
    UNIT_LEVEL = "UpdateName",
    UNIT_FACTION = "UpdateColor",
    UNIT_THREAT_LIST_UPDATE = "UpdateColor",
    UNIT_AURA = "UpdateAuras",
}
-- NOT in the table above: UNIT_THREAT_SITUATION_UPDATE fires for YOU
-- (arg "player"), not for the mob's plate - routing it by unit token
-- would drop every one of them. It sweeps all plates instead, which is
-- exactly the moment your aggro state flipped somewhere.

local CAST_EVENTS = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
}

driver:SetScript("OnEvent", function(_, event, arg1)
    if event == "NAME_PLATE_CREATED" then
        -- dress the plate the moment the pool births it, so by the time
        -- ANY addon's NAME_PLATE_UNIT_ADDED runs (many fire before
        -- ours), base._zuiNP and its healthBar already exist
        Acquire(arg1)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        OnUnitAdded(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        OnUnitRemoved(arg1)
    elseif event == "PLAYER_TARGET_CHANGED" then
        TargetChanged()
        for _, f in pairs(active) do NP.UpdateExtras(f) end
        if NP.Scripts then NP.Scripts.TargetChanged() end
    elseif event == "PLAYER_SOFT_ENEMY_CHANGED" then
        -- the soft pick only matters to the plates while there is no
        -- hard target; UpdateTarget makes that call per plate
        if not UnitExists("target") then TargetChanged() end
    elseif event == "RAID_TARGET_UPDATE" then
        -- marks churn all fight: only the marker is re-read
        for _, f in pairs(active) do NP.UpdateRaidMark(f) end
    elseif event == "UNIT_TARGET" then
        local f = active[arg1]
        if f then NP.UpdateExtras(f) end
    elseif event == "QUEST_LOG_UPDATE" then
        -- comes in bursts (every rep tick, every loot); the quest cache
        -- is dropped once and the plates re-read it on the 0.5 s sweep
        NP.WipeQuestCache()
        questDirty = true
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        -- 10-20 a second while sweeping a pack: only the plate the
        -- cursor left and the one it is on are touched
        local g = NP.SafeGUID("mouseover")
        local nf = g and byGUID[g]
        if lastHover and lastHover ~= nf then NP.UpdateHover(lastHover) end
        if nf then NP.UpdateHover(nf) end
        lastHover = nf
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
        -- one of these per raid member per aggro flip, each asking for
        -- every plate: note it, recolour once (see COALESCED UPDATES)
        sweepColor = true
        Arm()
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        -- a stance change flips the whole threat palette; rare, and
        -- wanted now
        ColorAll()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- combat sizes (the profile grows friendly plates in combat);
        -- UpdateTarget too, so a combat-only fade/size cue switches on
        for _, f in pairs(active) do
            LayoutIfStale(f)    -- only the plates whose size changed
            NP.UpdateTarget(f)
        end
        if NP.Scripts then NP.Scripts.CombatEnter() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if NP._cvarsPending then NP.ApplyCVars() end
        for _, f in pairs(active) do
            LayoutIfStale(f)
            NP.UpdateTarget(f)
        end
        ColorAll()
        if NP.Scripts then NP.Scripts.CombatLeave() end
    elseif CAST_EVENTS[event] then
        local f = active[arg1]
        if f then NP.OnCastEvent(f, event) end
    else
        local handler = UNIT_EVENTS[event]
        local f = handler and active[arg1]
        if f then
            -- the three that storm in a big pull only mark the plate;
            -- the flusher above does the work once per frame
            if handler == "UpdateHealth" then
                if not f.nameOnly then
                    dirtyHealth[f] = true
                    Arm()
                end
            elseif handler == "UpdateColor" then
                if not f.nameOnly then
                    dirtyColor[f] = true
                    Arm()
                end
            elseif handler == "UpdateAuras" then
                -- nothing reads a plate's auras unless the aura row is
                -- on or a user script is (scripts re-check on auras)
                if DB().auras.enabled or (NP.Scripts and NP.Scripts.AnyEnabled()) then
                    dirtyAura[f] = true
                    Arm()
                end
            else
                NP[handler](f)
            end
        end
    end
end)

-- Threat on era is chatty in some fights and silent in others, so a slow
-- sweep keeps combat colors honest even when no event fires.
local ticker
local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.5, function()
        if not NP.enabled then return end
        local fighting = UnitAffectingCombat("player")
        -- the colour pass is the sweep every pending threat event was
        -- asking for, so it settles those as well
        if fighting then ColorAll() end
        local quest = questDirty
        questDirty = false
        for _, f in pairs(active) do
            -- (a name-only plate shows none of the extras either)
            if (fighting or quest) and not f.nameOnly then
                NP.UpdateExtras(f)  -- mob target swaps rarely fire events
            end
            -- scripts tick in and out of combat, like Plater's
            -- Nameplate Updated
            if NP.Scripts then NP.Scripts.PlateUpdated(f) end
        end
    end)
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.nameplates = function()
    -- Two nameplate engines dressing the same plates is chaos; while
    -- Plater is still installed and enabled, ZacUI's engine stands down.
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded("Plater") then
        local line = ("nameplates: Plater is running, so ZacUI's nameplate "
            .. "engine is standing down. Disable or delete Plater to "
            .. "switch over - your profile's look is already ported.")
        -- after the login popups (Core_Popups), not under them
        if ns.Popups then ns.Popups.Say(line) else Print(line) end
        return
    end
    DB()
    if NP.enabled then
        NP.RefreshAll()
        return
    end
    NP.enabled = true
    RegisterMedia()

    driver:RegisterEvent("NAME_PLATE_CREATED")
    driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    driver:RegisterEvent("PLAYER_TARGET_CHANGED")
    -- pcall: the soft-target events only exist on 1.15+ clients
    pcall(driver.RegisterEvent, driver, "PLAYER_SOFT_ENEMY_CHANGED")
    driver:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    driver:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    driver:RegisterEvent("PLAYER_REGEN_ENABLED")
    driver:RegisterEvent("RAID_TARGET_UPDATE")
    driver:RegisterEvent("QUEST_LOG_UPDATE")
    pcall(driver.RegisterEvent, driver, "UNIT_TARGET")
    for ev in pairs(UNIT_EVENTS) do pcall(driver.RegisterEvent, driver, ev) end
    for ev in pairs(CAST_EVENTS) do pcall(driver.RegisterEvent, driver, ev) end
    pcall(driver.RegisterEvent, driver, "UNIT_THREAT_SITUATION_UPDATE")

    NP.ApplyCVars()
    StartTicker()

    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, base in ipairs(C_NamePlate.GetNamePlates()) do
            if base.namePlateUnitToken then
                OnUnitAdded(base.namePlateUnitToken)
            end
        end
    end
end

NP.DB = DB
-- the soft-target and crosshair files seed their own blocks under
-- ZacUIDB.nameplates with the same merge, so a key added later arrives
-- without a migration step
NP.CopyDefaults = CopyDefaults
NP.IsEffectiveTarget = IsEffectiveTarget
NP.SetNPFont = SetNPFont
NP.ApplyNPFont = ApplyNPFont
NP.FontPath = FontPath
NP.BarTexture = BarTexture
NP.BarChrome = BarChrome
NP.ChromeDefaults = ChromeDefaults
NP.STATE_LIST = STATE_LIST
NP.StateDefaults = StateDefaults
NP.StateOf = StateOf
NP.PaintState = PaintState
NP.Dims = Dims
NP.FrameDims = FrameDims
NP.DEFAULTS = DEFAULTS
NP.activePlates = active
-- the plate frame showing this GUID, or nil
function NP.PlateByGUID(guid) return guid and byGUID[guid] end

-- the global font and bar texture (Fonts & Textures) land in the plate
-- settings and every plate re-lays out
if ns.Media and ns.Media.RegisterTarget then
    ns.Media.RegisterTarget("nameplates", {
        label = "Nameplates",
        desc = "Plate font, health bar and cast bar textures.",
        order = 20,
        -- still on its shipped font (or on ZacUI's)
        untouched = function()
            local n = DB().fontName
            return n == nil or n == false or n == "" or n == DEFAULTS.fontName
        end,
        apply = function(font, bar, cleared)
            local d = DB()
            if font then d.fontName = font
            elseif cleared then d.fontName = DEFAULTS.fontName end
            if bar then d.healthTexture = bar; d.castTexture = bar end
            NP.RefreshAll()
        end,
    })
end

-- shared with later ZacUI files
ns.Nameplates = NP
