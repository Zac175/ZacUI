-- NP_SoftTarget - the soft-targeting system: the SoftTarget* cvar
-- manager, the "next up" tab-order predictor and the two arrow markers
-- (current / next) that ride the nameplates. Ported from Readycheck's
-- Testing addon; the settings moved with it (see Migrate below).
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT IT DOES.
--   * Arms the 1.15 action-targeting cvars (SoftTargetEnemy and friends)
--     inside dungeons and raids (or everywhere, by setting), and puts
--     them back when it stands down. Never in combat - cvars are
--     protected there, so the regen event re-runs the pass instead.
--   * Predicts which mob Tab would take next, ranked by distance from
--     the screen centre where the client lets us read plate positions
--     and by range rungs where it does not, with Tab's real no-repeat
--     memory mimicked at its measured size.
--   * Draws an arrow over your current mob (hard or soft target) and
--     another over the predicted next one. The arrows anchor to ZacUI's
--     own plate frame (its name, else its bar) so they sit on the drawn
--     stack, not the Blizzard click box; on a plate the engine has not
--     dressed (Plater running) the Blizzard root is the fallback.
--
-- The per-mob Target Nameplate Range feature stays in Readycheck
-- (RC.TargetRange). While one of its overrides is active we must not
-- touch nameplateMaxDistance ourselves; the guard is nil-safe so this
-- file runs without Readycheck at all.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local NP = ns.Nameplates
local Print = ns.Print
local TEX_ARROW = ns.TEX_ARROW

local ST = {}
NP.SoftTarget = ST

local RANGE_MAX = 41  -- nameplate view-distance cap (matches RC.TargetRange)

-- {r,g,b} arrays, the shape every other nameplate colour is stored in
local COLOR_PRESETS = {
    { name = "Red",    color = { 1.00, 0.20, 0.20 } },
    { name = "Orange", color = { 1.00, 0.55, 0.10 } },
    { name = "Yellow", color = { 1.00, 0.90, 0.20 } },
    { name = "Green",  color = { 0.30, 1.00, 0.35 } },
    { name = "Cyan",   color = { 0.30, 0.90, 1.00 } },
    { name = "Blue",   color = { 0.35, 0.55, 1.00 } },
    { name = "Purple", color = { 0.75, 0.45, 1.00 } },
    { name = "White",  color = { 1.00, 1.00, 1.00 } },
}
ST.COLOR_PRESETS = COLOR_PRESETS

-- ============================================================
-- SETTINGS - ZacUIDB.nameplates.softTarget
-- ============================================================
local DEFAULTS = {
    softTarget = true,        -- the whole system on/off
    fullTime = true,          -- stay armed while fighting (Grassy mode)
    softMarker = true,        -- our arrows instead of Blizzard's icon
    nextUp = true,            -- predict + mark the next mob
    nextSkull = false,        -- also raid-mark the pick with skull
    untargetedMark = true,    -- arm soft targeting while untargeted
    maxPlates = true,         -- hold nameplateMaxDistance at the cap
    instanceOnly = true,      -- dungeons and raids only
    softRange = 30,           -- SoftTargetEnemyRange, yards
    markerOffX = 0,
    markerOffY = 4,
    markerSize = 24,
    markerPulse = true,
    markerPulseTime = 0.55,   -- seconds for each half of the pulse (dim, then back)
    markerPulseAlpha = 0.45,  -- how far the pulse dims the arrow
    -- Off by default: the arrows already draw over the debuff icons, so
    -- lifting them is a preference, not a fix, and it moves the arrows.
    markerClearAuras = false,
    softColor = { 1.00, 0.20, 0.20 },   -- the NEXT arrow
    curColor  = { 0.30, 1.00, 0.35 },   -- the CURRENT arrow
}

-- The scalar keys Readycheck's Store() kept, copied by name.
local MIGRATE_KEYS = {
    "softTarget", "fullTime", "softMarker", "nextUp", "nextSkull",
    "untargetedMark", "maxPlates", "instanceOnly", "softRange",
    "markerOffX", "markerOffY", "markerSize", "markerPulse",
    "markerClearAuras", "prevPlateDist",
}

-- ONE-TIME MIGRATION from ReadycheckDB.personalTargeting, which the
-- Testing addon wrote. Runs only while our block has never been seeded;
-- copies the values and leaves the source alone - Readycheck's Target
-- Range feature still keeps its own keys (rangeEnabled, entries) in
-- that same table, so it is not ours to clear.
local function Migrate(s)
    local rc = _G.ReadycheckDB
    local src = type(rc) == "table" and rc.personalTargeting
    if type(src) ~= "table" then return false end
    -- the table exists for Target Range alone on a DB that never ran
    -- the soft tools; only a soft key proves there is something to move
    if src.softTarget == nil and src.markerSize == nil then return false end
    for _, k in ipairs(MIGRATE_KEYS) do
        if src[k] ~= nil then s[k] = src[k] end
    end
    for _, k in ipairs({ "softColor", "curColor" }) do
        local c = src[k]
        if type(c) == "table" and c.r then
            s[k] = { c.r, c.g or 0, c.b or 0 }
        end
    end
    return true
end

-- DB() is read several times per marker pass and once per picker tick,
-- so the defaults merge (a ~20 key walk) runs once per settings table
-- and the result is remembered, the way NP.DB() does it. The full pass
-- runs again when the plate table or our block is a different one (a
-- profile switch, the reset button) or the block was wiped in place.
local seededParent, seededBlock

local function DB()
    if type(ZacUIDB) ~= "table" then return nil end
    local d = NP.DB()
    local s = d.softTarget
    if s and d == seededParent and s == seededBlock and s.seeded then return s end
    if type(s) ~= "table" then d.softTarget = {} s = d.softTarget end
    if not s.seeded then
        s.seeded = true
        if Migrate(s) then
            Print("soft target settings moved from Readycheck.")
        end
    end
    NP.CopyDefaults(DEFAULTS, s)
    seededParent, seededBlock = d, s
    return s
end
ST.DB = DB

local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function InstanceAllowed()
    local s = DB()
    if s and s.instanceOnly == false then return true end
    local inInst, instType = IsInInstance()
    return (inInst and (instType == "party" or instType == "raid")) and true or false
end
ST.InstanceAllowed = InstanceAllowed

-- Readycheck's per-mob Target Nameplate Range, when it is loaded.
local function RangeOverrideActive()
    local RC = _G.Readycheck
    local TR = RC and RC.TargetRange
    return (TR and TR.HasOverride and TR.HasOverride()) and true or false
end

-- ============================================================
-- RANGE LADDER - how far each plate is, by what reaches it
-- ============================================================
ST._order = ST._order or {}

local RANGE_LADDER = {
    WARRIOR = { {5,"Heroic Strike"}, {8,"Intimidating Shout"}, {25,"Charge"},
                {25,"Intercept"}, {30,"Throw"}, {30,"Shoot Bow"},
                {30,"Shoot Gun"}, {30,"Shoot Crossbow"} },
    ROGUE   = { {5,"Sinister Strike"}, {10,"Blind"}, {30,"Throw"},
                {30,"Shoot Bow"}, {30,"Shoot Gun"}, {30,"Shoot Crossbow"} },
    HUNTER  = { {5,"Raptor Strike"}, {35,"Auto Shot"} },
    MAGE    = { {5,"Attack"}, {20,"Fire Blast"}, {30,"Fireball"}, {30,"Frostbolt"} },
    WARLOCK = { {5,"Attack"}, {30,"Shadow Bolt"} },
    PRIEST  = { {5,"Attack"}, {30,"Smite"}, {30,"Mind Blast"} },
    SHAMAN  = { {5,"Attack"}, {20,"Earth Shock"}, {30,"Lightning Bolt"} },
    PALADIN = { {5,"Attack"}, {10,"Judgement"} },
    DRUID   = { {5,"Attack"}, {30,"Wrath"}, {30,"Moonfire"} },
}

local function BuildLadder()
    local _, cls = UnitClass("player")
    local l = {}
    local src = cls and RANGE_LADDER[cls]
    if src then
        for _, e in ipairs(src) do l[#l + 1] = { y = e[1], spell = e[2] } end
    end
    l[#l + 1] = { y = 9.9,  idx = 3 }
    l[#l + 1] = { y = 11.3, idx = 2 }
    l[#l + 1] = { y = 28,   idx = 1 }
    table.sort(l, function(a, b) return a.y < b.y end)
    ST._ladder = l
end

local function RawRangeScore(u)
    local lad = ST._ladder
    if lad then
        for i = 1, #lad do
            local r = lad[i]
            if r.spell then
                if IsSpellInRange(r.spell, u) == 1 then return r.y end
            else
                local ok, res = pcall(CheckInteractDistance, u, r.idx)
                if ok and res then return r.y end
            end
        end
    end
    return 99
end

ST._seen = ST._seen or {}
local SEEN_HOLD = 3

local function RangeScore(u, g)
    local score = RawRangeScore(u)
    if not g then return score end
    local m, now = ST._seen[g], GetTime()
    if m and m.s < score and (now - m.t) < SEEN_HOLD then
        return m.s
    end
    if m then m.s, m.t = score, now
    else ST._seen[g] = { s = score, t = now } end
    return score
end

-- ============================================================
-- SCREEN DISTANCE - Tab's real rule, where the client lets us read it
-- ============================================================
ST._scr = ST._scr or {}
local SCR_FRESH, SCR_RETRY = 1.5, 10

local function SamplePlatePositions()
    local now = GetTime()
    if ST._scrBlockedT and (now - ST._scrBlockedT) < SCR_RETRY then return end
    local okC, wx, wy = pcall(WorldFrame.GetCenter, WorldFrame)
    if not okC or not wx then return end
    local ws = WorldFrame:GetEffectiveScale()
    for _, u in ipairs(ST._order) do
        local plate = C_NamePlate.GetNamePlateForUnit(u)
        local g = NP.SafeGUID(u)   -- (nil while WoW Forever hides it: no key, no compare)
        if plate and g then
            local ok, px, py = pcall(plate.GetCenter, plate)
            if not ok then
                -- plate positions are refused in this zone; the range
                -- rungs carry the ranking until the retry window passes
                -- (/zui soft dump says which mode is live)
                ST._scrBlockedT = now
                return
            end
            if px and py then
                local ok3, ps = pcall(plate.GetEffectiveScale, plate)
                if ok3 and ps and ws and ws > 0 then
                    px, py = px * ps / ws, py * ps / ws
                end
                local dx, dy = px - wx, py - wy
                -- this runs for every plate every 0.5s; refill the mob's
                -- entry rather than allocating a fresh one each tick
                local e = ST._scr[g]
                if e then e.d, e.t = math.sqrt(dx * dx + dy * dy), now
                else ST._scr[g] = { d = math.sqrt(dx * dx + dy * dy), t = now } end
                ST._scrEverOK = true
            end
        end
    end
    ST._scrBlockedT = nil
end

local function ScreenScore(g)
    local e = g and ST._scr[g]
    if e and (GetTime() - e.t) <= SCR_FRESH then
        return math.floor(e.d / 80)
    end
end

-- ============================================================
-- PLATE ROSTER
-- ============================================================
local function TrackPlate(unit)
    if not unit then return end
    for _, u in ipairs(ST._order) do if u == unit then return end end
    ST._order[#ST._order + 1] = unit
end

local function UntrackPlate(unit)
    if not unit then return end
    for i = #ST._order, 1, -1 do
        if ST._order[i] == unit then table.remove(ST._order, i) end
    end
end

local function EligibleNext(u)
    return UnitExists(u) and UnitCanAttack("player", u) and not UnitIsDead(u)
        and not (UnitExists("target") and UnitIsUnit(u, "target"))
        and not (not UnitExists("target") and UnitExists("softenemy") and UnitIsUnit(u, "softenemy"))
end

-- ============================================================
-- THE PICKER
-- ============================================================
local SWITCH_AFTER = 3
local RECENT_TTL = 6
local RECENT_MAX = 3
local VISIT_WINDOW = 10
local CONE_TTL = 20

ST._visits  = ST._visits  or {}
ST._outCone = ST._outCone or {}
ST._recent  = ST._recent  or {}

local function RecentIndex(g, now)
    for i = 1, #ST._recent do
        local e = ST._recent[i]
        if e.g == g then
            if (now - e.t) <= RECENT_TTL then return i end
            return nil
        end
    end
end

local function NextUnit()
    local now = GetTime()
    for g, t in pairs(ST._visits) do
        if (now - t) > VISIT_WINDOW then ST._visits[g] = nil end
    end
    for g, t in pairs(ST._outCone) do
        if (now - t) > CONE_TTL then ST._outCone[g] = nil end
    end
    for g, e in pairs(ST._scr) do
        if (now - e.t) > 10 then ST._scr[g] = nil end
    end
    local best, bT, bS, bH, bestG
    local cur, cT, cS, cH
    local bestV, bestVi
    for pass = 1, 2 do
        for _, u in ipairs(ST._order) do
            if EligibleNext(u) then
                local g = NP.SafeGUID(u)
                if pass == 2 or not (g and ST._outCone[g]) then
                    local ri = g and RecentIndex(g, now)
                    if ri then
                        if not bestV or ri > bestVi then bestV, bestVi = u, ri end
                    else
                        -- the screen distance is Tab's real rule; the range
                        -- ladder (a dozen range checks) only stands in when
                        -- the client refuses plate positions
                        local sc = ScreenScore(g)
                        local score, tier = sc, 1
                        if not sc then
                            score = RangeScore(u, g)
                            if score <= 9.9 and UnitIsUnit(u .. "target", "player") then
                                tier = 0
                            end
                        end
                        -- (Forever hides health in combat: read as full)
                        local hcur, hm = UnitHealth(u), UnitHealthMax(u)
                        if ns.IsSecret and (ns.IsSecret(hcur) or ns.IsSecret(hm)) then hcur, hm = nil, nil end
                        local hp = (hm and hm > 0 and hcur) and (hcur / hm) or 1
                        if g and g == ST._pickGUID then
                            cur, cT, cS, cH = u, tier, score, hp
                        end
                        if not best or tier < bT or (tier == bT
                            and (score < bS or (score == bS and hp < bH))) then
                            best, bT, bS, bH, bestG = u, tier, score, hp, g
                        end
                    end
                end
            end
        end
        if best or bestV then break end
    end
    local pick
    if best then
        pick = best
        if cur and best ~= cur then
            if bT < cT then
                pick = best
            elseif cS < bS or (cS == bS and cH <= bH) then
                pick = cur
            elseif cS >= 99 and bS < 99 then
                pick = best
            else
                if ST._pendGUID == bestG then
                    ST._pendN = (ST._pendN or 0) + 1
                else
                    ST._pendGUID, ST._pendN = bestG, 1
                end
                if ST._pendN < SWITCH_AFTER then pick = cur end
            end
        end
        if not cur or best == cur or pick ~= cur then
            ST._pendGUID, ST._pendN = nil, nil
        end
    else
        pick = bestV
        ST._pendGUID, ST._pendN = nil, nil
    end
    ST._pickToken = pick
    ST._pickGUID = pick and NP.SafeGUID(pick) or nil
    return pick
end

local function NoteTargetVisit()
    if not (UnitExists("target") and UnitCanAttack("player", "target")) then return end
    local g = NP.SafeGUID("target")
    if not g then return end
    local now = GetTime()
    local prior = ST._visits[g]
    if prior and (now - prior) <= VISIT_WINDOW then
        for _, u in ipairs(ST._order) do
            if EligibleNext(u) then
                local ug = NP.SafeGUID(u)
                if ug and not ST._visits[ug] then ST._outCone[ug] = now end
            end
        end
    end
    ST._visits[g] = now
    ST._outCone[g] = nil
    local prev = ST._recent[1]
    if prev and prev.g ~= g then
        prev.t = now
        ST._visits[prev.g] = now
    end
    for i = #ST._recent, 1, -1 do
        if ST._recent[i].g == g then table.remove(ST._recent, i) end
    end
    table.insert(ST._recent, 1, { g = g, t = now })
    while #ST._recent > RECENT_MAX do table.remove(ST._recent) end
end

-- ============================================================
-- ARROWS
-- ============================================================
local markerNext, markerCur

local ARROW_MIN, ARROW_MAX = 16, 72

-- The outline is black copies of the arrow offset around a circle, so the
-- union of them shows as a border everywhere the shape has an edge. Eight
-- offsets on a SQUARE leave gaps at the triangle's sharp apex, because
-- there the neighbouring copies are a chord apart rather than overlapping.
-- Sixteen offsets on a UNIT CIRCLE put that chord at 2*sin(11.25deg) =
-- 0.39 of the radius, well under a pixel, so the border closes evenly all
-- the way round including the corners.
local RING = {}
for i = 1, 16 do
    local a = (i - 1) * (math.pi * 2 / 16)
    RING[i] = { math.cos(a), math.sin(a) }
end

local function ArrowSize(s)
    local n = tonumber(s and s.markerSize) or 24
    if n < ARROW_MIN then n = ARROW_MIN end
    if n > ARROW_MAX then n = ARROW_MAX end
    return n
end

-- One physical pixel in a frame's own units. The border is always 1px
-- regardless of arrow size or UI scale, so it never thickens into the
-- artwork.
local function PixelUnit(frame)
    if not GetPhysicalScreenSize then return 1 end
    local _, h = GetPhysicalScreenSize()
    if not h or h <= 0 then return 1 end
    local scale = (frame or UIParent):GetEffectiveScale()
    if not scale or scale <= 0 then return 1 end
    return (768 / h) / scale
end

-- parent: the settings preview's sample arrows hang in its canvas; the
-- live ones sit on UIParent.
local function MakeArrow(name, parent)
    local f = CreateFrame("Frame", name, parent or UIParent)
    f:SetSize(24, 24)
    -- Readycheck's NameplateAuras hosts its icons at DIALOG/100, so an
    -- arrow on HIGH draws underneath them. Sit above that, still below
    -- tooltips.
    if not parent then
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(130)
    end
    f:Hide()
    f.ring = {}
    for i = 1, #RING do
        local o = f:CreateTexture(nil, "ARTWORK")
        o:SetTexture(TEX_ARROW)
        o:SetVertexColor(0, 0, 0, 1)
        f.ring[i] = o
    end
    local tex = f:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture(TEX_ARROW)
    f.tex = tex

    -- Alpha only. A scale pulse would change the frame's footprint and
    -- drag the arrow off its anchor as it breathes.
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local out = ag:CreateAnimation("Alpha")
    out:SetFromAlpha(1); out:SetToAlpha(0.45); out:SetDuration(0.55); out:SetOrder(1)
    local back = ag:CreateAnimation("Alpha")
    back:SetFromAlpha(0.45); back:SetToAlpha(1); back:SetDuration(0.55); back:SetOrder(2)
    f.pulse = ag
    f.pulseOut, f.pulseBack = out, back
    return f
end

-- Restyles in place; markers are long-lived so settings changes must not
-- rebuild them (a rebuild drops the anchor and the arrow flickers).
local function StyleArrow(f, s)
    if not f then return end
    local size = ArrowSize(s)
    local px = PixelUnit(f)
    -- UpdateMarker runs on a 0.5s ticker, so skip the relayout unless
    -- something actually changed. Pixel size is part of the check because
    -- a UI scale change moves what one physical pixel is worth. Three
    -- number compares, not a built string - this is per arrow per tick.
    local pulse = (s and s.markerPulse) and 1 or 0
    -- the pulse's timing and depth (Soft target > Animation), with the
    -- global speed from Appearance > Motion; Motion off = no pulse
    local M = ns.Motion
    if pulse == 1 and M and M.Enabled and not M.Enabled() then pulse = 0 end
    local pt = (tonumber(s and s.markerPulseTime) or 0.55) / ((M and M.Speed and M.Speed()) or 1)
    local pa = tonumber(s and s.markerPulseAlpha) or 0.45
    if f._stSize == size and f._stPulse == pulse and f._stPx == px
        and f._stPT == pt and f._stPA == pa then return end
    f._stSize, f._stPulse, f._stPx, f._stPT, f._stPA = size, pulse, px, pt, pa
    if f.pulseOut then
        local was = f.pulse:IsPlaying()
        if was then f.pulse:Stop() end
        f.pulseOut:SetToAlpha(pa) f.pulseOut:SetDuration(pt)
        f.pulseBack:SetFromAlpha(pa) f.pulseBack:SetDuration(pt)
    end
    f:SetSize(size, size)
    for i, o in ipairs(f.ring) do
        local off = RING[i]
        o:ClearAllPoints()
        o:SetPoint("TOPLEFT", off[1] * px, off[2] * px)
        o:SetPoint("BOTTOMRIGHT", off[1] * px, off[2] * px)
    end
    if pulse == 1 then
        if not f.pulse:IsPlaying() then f.pulse:Play() end
    else
        f.pulse:Stop()
        f:SetAlpha(1)
    end
end

-- How far Readycheck's nameplate debuff icons reach above the health
-- bar, derived from their saved config rather than measured. Plate
-- frames refuse GetTop() in some contexts (see SamplePlatePositions),
-- and the arrows must never measure anything - they only ever anchor.
-- HALF_BAR is the nominal gap between the bar centre those icons are
-- offset from and the bar top the arrow is anchored above. Zero when
-- Readycheck is not loaded.
local HALF_BAR = 10
local function AuraClearance(s)
    if not (s and s.markerClearAuras) then return 0 end
    -- ZacUI's own debuff groups (NP_Debuffs) first; Readycheck's only
    -- when those are off
    local c
    local NPD = NP.Debuffs
    if NPD and NPD.Cfg then
        local mine = NPD.Cfg()
        if mine and mine.enabled then c = mine end
    end
    if not c then
        local RC = _G.Readycheck
        local NA = RC and RC.nameplateAuras
        c = NA and NA.cfg and NA.cfg()
    end
    if not (c and c.enabled and c.groups) then return 0 end
    local top = 0
    for _, g in ipairs(c.groups) do
        if g.enabled ~= false and (g.attach or "center") == "center" then
            local half = (((g.fontSize or 11) + 2) / 2)
            local reach = (g.offsetY or 0) + half
            if reach > top then top = reach end
        end
    end
    local lift = top - HALF_BAR
    return lift > 0 and math.floor(lift + 0.5) or 0
end

-- the settings preview builds its sample arrows with these, so they are
-- the live arrows' own art, border, size and pulse
ST.MakeArrow = MakeArrow
ST.StyleArrow = StyleArrow
ST.ArrowDefaults = DEFAULTS

local function EnsureMarkers()
    local s = DB()
    if not markerNext then markerNext = MakeArrow("ZacUI_SoftTargetMarker") end
    if not markerCur then markerCur = MakeArrow("ZacUI_CurrentTargetMarker") end
    StyleArrow(markerNext, s)
    StyleArrow(markerCur, s)
    return markerNext, markerCur
end

local function HideMarks()
    if markerNext then markerNext:Hide() end
    if markerCur then markerCur:Hide() end
end

local UpdateMarker  -- forward: the ticker body calls it

local function StopRecalc()
    if ST._recalc then ST._recalc:Cancel(); ST._recalc = nil end
end

local function StartRecalc()
    if ST._recalc then return end
    ST._recalc = C_Timer.NewTicker(0.5, function()
        local s = DB()
        if not (s and s.softTarget and s.softMarker and s.nextUp
                and (UnitExists("target") or UnitExists("softenemy"))
                and ST._order[1] and InstanceAllowed()) then
            StopRecalc()
        end
        SamplePlatePositions()
        UpdateMarker()
    end)
end

-- Where the arrow hangs. ZacUI's engine centres its bar inside the click
-- box and hides Blizzard's UnitFrame, so the plate ROOT's top is ~9px
-- above the visual stack - anchored there the arrow floats. Anchor to the
-- top of what is actually drawn: the name, else the bar. A plate the
-- engine has not dressed (Plater running, engine off) keeps the root.
local function MarkAnchor(plate)
    local z = plate and plate._zuiNP
    if z and z:IsShown() then return z.markTop or z.name or z.health or plate end
    return plate
end

function UpdateMarker()
    local s = DB()
    -- The master switch gates the arrows too: with the system off nothing
    -- may stay drawn, whatever the marker sub-options say.
    if not s or not s.softTarget or not s.softMarker or not C_NamePlate or not InstanceAllowed() then
        HideMarks()
        StopRecalc()
        return
    end
    local nextPlate, curPlate
    if s.nextUp and (UnitExists("target") or UnitExists("softenemy")) then
        local ok, u = pcall(NextUnit)
        if not ok then
            if ST._lastPickErr ~= tostring(u) then
                ST._lastPickErr = tostring(u)
                Print("soft target: picker error - " .. tostring(u))
            end
            u = nil
        end
        if u then
            nextPlate = C_NamePlate.GetNamePlateForUnit(u)
            if nextPlate and s.nextSkull then
                -- Skull the pick once per mob (GUID-gated; SetRaidTarget
                -- is unprotected - it just no-ops without permission).
                local g = NP.SafeGUID(u)
                if g and g ~= ST._lastSkullGUID then
                    ST._lastSkullGUID = g
                    pcall(SetRaidTarget, u, 8)
                end
            end
        end
    end
    if UnitExists("target") and UnitCanAttack("player", "target") then
        curPlate = C_NamePlate.GetNamePlateForUnit("target")
    elseif s.untargetedMark and UnitExists("softenemy") then
        curPlate = C_NamePlate.GetNamePlateForUnit("softenemy")
    end
    local mn, mc = EnsureMarkers()
    local offX = s.markerOffX or 0
    local offY = (s.markerOffY or 4) + AuraClearance(s)
    -- each arrow remembers the plate it rides, so a plate leaving can
    -- drop its arrow at once while the full pass waits for the coalescer
    mn._plate, mc._plate = nextPlate, curPlate
    if nextPlate then
        local col = s.softColor or DEFAULTS.softColor
        mn.tex:SetVertexColor(col[1], col[2], col[3])
        mn:ClearAllPoints()
        mn:SetPoint("BOTTOM", MarkAnchor(nextPlate), "TOP", offX, offY)  -- anchor only; never measure
        mn:Show()
    else
        mn:Hide()
    end
    if curPlate then
        local col = s.curColor or DEFAULTS.curColor
        mc.tex:SetVertexColor(col[1], col[2], col[3])
        mc:ClearAllPoints()
        mc:SetPoint("BOTTOM", MarkAnchor(curPlate), "TOP", offX, offY)
        mc:Show()
    else
        mc:Hide()
    end
    if s.nextUp and (UnitExists("target") or UnitExists("softenemy"))
            and ST._order[1] then
        StartRecalc()
    end
end
ST.UpdateMarker = UpdateMarker

-- the skull is GUID-gated; a settings change wants it re-applied
function ST.ResetSkull()
    ST._lastSkullGUID = nil
end

-- ============================================================
-- CVARS
-- ============================================================
local normalizedOnce = false

-- ApplySoftCVars re-runs on every recompute; writing a cvar that already
-- holds the wanted value is pointless churn, so compare first.
local function SetCVarIfChanged(name, val)
    local ok, cur = pcall(GetCVar, name)
    if ok and cur ~= nil and tostring(cur) == tostring(val) then return end
    -- SETUP2: through ns.CVar (recorded; put back when the plates are off)
    if ns.CVar then ns.CVar.Set(name, val, "nameplates") else pcall(SetCVar, name, val) end
end

local function ApplySoftCVars()
    -- NEVER write cvars in combat (protected -> ADDON_ACTION_BLOCKED). The
    -- PLAYER_REGEN_ENABLED recompute re-runs this the moment combat ends.
    if InCombat() then UpdateMarker(); return end
    if ST._labHold then UpdateMarker(); return end
    local s = DB()
    if not s then return end
    local armed = s.softTarget and InstanceAllowed()
        and (s.fullTime or (s.untargetedMark and not UnitExists("target")))
    if armed and s.fullTime then
        SetCVarIfChanged("SoftTargetEnemy", 3)
        SetCVarIfChanged("SoftTargetWithLocked", 2)
        SetCVarIfChanged("SoftTargetMatchLocked", 0)
        SetCVarIfChanged("SoftTargetIconEnemy", 1)
        SetCVarIfChanged("SoftTargetInteract", 3)
        SetCVarIfChanged("SoftTargetIconInteract", 1)
    elseif armed then
        SetCVarIfChanged("SoftTargetEnemy", 3)
        SetCVarIfChanged("SoftTargetIconEnemy", s.softMarker and 0 or 1)
        SetCVarIfChanged("SoftTargetWithLocked", 1)
        SetCVarIfChanged("SoftTargetMatchLocked", 1)
        SetCVarIfChanged("SoftTargetInteract", 1)
        SetCVarIfChanged("SoftTargetIconInteract", 0)
    else
        SetCVarIfChanged("SoftTargetEnemy", 1)
        SetCVarIfChanged("SoftTargetIconEnemy", 0)
        SetCVarIfChanged("SoftTargetWithLocked", 1)
        SetCVarIfChanged("SoftTargetMatchLocked", 1)
        SetCVarIfChanged("SoftTargetInteract", 1)
        SetCVarIfChanged("SoftTargetIconInteract", 0)
    end
    do
        local ok, cur = pcall(GetCVar, "SoftTargetEnemyRange")
        if ok and cur ~= nil then
            ST._srSupported = true
            if armed then
                if ST._srOrig == nil then ST._srOrig = tonumber(cur) or 45 end
                SetCVarIfChanged("SoftTargetEnemyRange", s.softRange or 30)
            elseif ST._srOrig ~= nil then
                SetCVarIfChanged("SoftTargetEnemyRange", ST._srOrig)
                ST._srOrig = nil
            end
        else
            ST._srSupported = false
        end
    end
    if not normalizedOnce then
        normalizedOnce = true
        SetCVarIfChanged("SoftTargetForce", 1)
    end
    if not RangeOverrideActive() then
        if s.softTarget and s.maxPlates and InstanceAllowed() then
            local cd = tonumber(GetCVar("nameplateMaxDistance")) or 0
            if cd < RANGE_MAX then
                if s.prevPlateDist == nil then s.prevPlateDist = cd end
                SetCVarIfChanged("nameplateMaxDistance", RANGE_MAX)
            end
        elseif s.prevPlateDist ~= nil then
            SetCVarIfChanged("nameplateMaxDistance", s.prevPlateDist)
            s.prevPlateDist = nil
        end
    end
    UpdateMarker()
end
ST.ApplySoftCVars = ApplySoftCVars
-- what the config page calls after any change: cvars (skipped in combat
-- and while the lab holds them) and the arrows, in one go
ST.Refresh = ApplySoftCVars

-- ============================================================
-- THE LAB - /zui soft: read and poke the raw cvars with the manager
-- paused, and put everything back
-- ============================================================
local LAB_CVARS = {
    "SoftTargetEnemy", "SoftTargetWithLocked", "SoftTargetMatchLocked",
    "SoftTargetIconEnemy", "SoftTargetIconGameObject", "SoftTargetInteract",
    "SoftTargetIconInteract", "SoftTargetEnemyRange", "SoftTargetEnemyArc",
    "SoftTargetForce", "SoftTargetNameplateEnemy", "SoftTargetNameplateSize",
}

local function LabGet(name)
    local ok, v = pcall(GetCVar, name)
    if ok and v ~= nil then return tostring(v) end
    return nil
end

local function LabSet(name, val)
    ST._labOrig = ST._labOrig or {}
    if ST._labOrig[name] == nil then
        local cur = LabGet(name)
        if cur ~= nil then ST._labOrig[name] = cur end
    end
    -- SETUP2: recorded like every other write (the lab's own LabRestore
    -- hands the values back itself, so that one stays a plain write)
    if ns.CVar then return ns.CVar.Set(name, val, "nameplates") end
    local ok = pcall(SetCVar, name, val)
    return ok
end

local function LabRestore()
    if not ST._labOrig then ST._labHold = nil; return end
    for name, v in pairs(ST._labOrig) do pcall(SetCVar, name, v) end
    ST._labOrig = nil
    ST._labHold = nil
end

function ST.Slash(msg)
    local cmd, arg = string.match(msg or "", "^%s*(%S*)%s*(%S*)")
    cmd = string.lower(cmd or "")
    if InCombat() and cmd ~= "" and cmd ~= "dump" then
        Print("soft lab: cvars are combat-locked - try again out of combat.")
        return
    end
    if cmd == "dump" or cmd == "" then
        Print("soft lab - current values (- = cvar not on this client):")
        for _, name in ipairs(LAB_CVARS) do
            Print("  " .. name .. " = " .. (LabGet(name) or "-"))
        end
        local s = DB()
        if s then
            Print(string.format("  settings: softTarget=%s fullTime=%s softMarker=%s nextUp=%s nextSkull=%s untargetedMark=%s labHold=%s",
                tostring(s.softTarget), tostring(s.fullTime), tostring(s.softMarker),
                tostring(s.nextUp), tostring(s.nextSkull), tostring(s.untargetedMark),
                tostring(ST._labHold ~= nil and ST._labHold or false)))
        end
        local tgt = UnitExists("target") and (UnitName("target") or "?") or "-"
        local se = UnitExists("softenemy") and (UnitName("softenemy") or "?") or "-"
        local okP, pick = pcall(NextUnit)
        local pk
        if not okP then pk = "ERROR: " .. tostring(pick)
        elseif pick then pk = (UnitName(pick) or "?") .. " (" .. pick .. ")"
        else pk = "-" end
        local scr
        if ST._scrBlockedT then scr = "blocked (range rungs)"
        elseif ST._scrEverOK then scr = "active"
        else scr = "not sampled yet" end
        Print(string.format("  live: target=%s softenemy=%s plates=%d pick=%s screen-centre=%s",
            tgt, se, #ST._order, pk, scr))
        if cmd == "" then
            Print("commands: /zui soft grassy (full-time mode), /zui soft set <CVar> <value>, /zui soft off (restore + hand control back).")
        end
        return
    end
    if cmd == "grassy" then
        local s = DB()
        ST._labHold = true
        LabSet("SoftTargetEnemy", 3)
        LabSet("SoftTargetWithLocked", 2)
        LabSet("SoftTargetMatchLocked", 0)
        LabSet("SoftTargetIconEnemy", 1)
        LabSet("SoftTargetInteract", 3)
        LabSet("SoftTargetIconInteract", 1)
        LabSet("SoftTargetEnemyRange", (s and s.softRange) or 30)
        Print("soft lab: GRASSY MODE ON - the cvar manager is paused (arrows/picker still run).")
        Print("Test 1: stand untargeted near mobs - does a mob get a native marker/ring at its FEET?")
        Print("Test 2: hard-target one mob - does a DIFFERENT mob keep a soft visual at the same time?")
        Print("Test 3: kill your target - does the soft visual hop to the next mob on its own?")
        Print("/zui soft dump shows values; /zui soft off puts everything back.")
        return
    end
    if cmd == "set" then
        local name, val = string.match(msg, "^%s*%S+%s+(%S+)%s+(%S+)")
        if not name then Print("soft lab: /zui soft set <CVar> <value>"); return end
        ST._labHold = true
        if LabSet(name, val) then
            Print("soft lab: " .. name .. " = " .. (LabGet(name) or tostring(val)) .. " (manager paused; /zui soft off restores).")
        else
            Print("soft lab: couldn't set " .. name .. ".")
        end
        return
    end
    if cmd == "off" then
        LabRestore()
        ApplySoftCVars()
        Print("soft lab: originals restored - safe-window manager back in control.")
        return
    end
    Print("soft lab: /zui soft dump | grassy | set <CVar> <value> | off")
end

-- ============================================================
-- EVENTS
-- ============================================================
-- Plate add/remove is registered here rather than borrowed from the
-- engine's driver: the roster has to stay right when the engine is
-- standing down (Plater installed), and the arrows still work then.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_LOGOUT")
pcall(f.RegisterEvent, f, "PLAYER_SOFT_ENEMY_CHANGED")
pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_ADDED")
pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_REMOVED")
-- Plate add/remove, soft-enemy hops and the combat flag arrive in bursts
-- (a 30-mob pack is 30 NAME_PLATE_UNIT_ADDED in one frame), and each one
-- used to run the full picker - every tracked plate through the range
-- ladder. Those events now only note the plate and arm one short timer;
-- the marker pass runs once when it fires. Target changes, zoning and
-- leaving combat keep their immediate pass (they are rare and the cvar
-- write wants to happen right then).
local function FlushMarker()
    ST._markArmed = nil
    UpdateMarker()
end

local function ArmMarker()
    if ST._markArmed then return end
    ST._markArmed = true
    C_Timer.After(0.1, FlushMarker)
end
ST.ArmMarker = ArmMarker

-- a plate that just went away takes its arrow with it right now; the
-- coalesced pass puts an arrow on whatever is right next
local function DropArrowsOn(unit)
    if not (markerNext or markerCur) or not C_NamePlate then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    if markerNext and markerNext._plate == plate then markerNext._plate = nil markerNext:Hide() end
    if markerCur and markerCur._plate == plate then markerCur._plate = nil markerCur:Hide() end
end

f:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGOUT" then
        LabRestore()
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        TrackPlate(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        UntrackPlate(unit)
        DropArrowsOn(unit)
    end
    if event == "PLAYER_TARGET_CHANGED" then
        NoteTargetVisit()
    end
    if event == "PLAYER_REGEN_ENABLED" then
        ST._seen, ST._visits, ST._outCone, ST._recent = {}, {}, {}, {}
        ApplySoftCVars()
    elseif event == "PLAYER_ENTERING_WORLD"
            or event == "PLAYER_TARGET_CHANGED" then
        if event == "PLAYER_ENTERING_WORLD" then
            BuildLadder()
            ST._seen, ST._visits, ST._outCone, ST._recent, ST._scr = {}, {}, {}, {}, {}
            ST._scrBlockedT, ST._scrEverOK = nil, nil
        end
        ApplySoftCVars()
    else
        ArmMarker()
    end
end)

-- shared with later ZacUI files
ns.SoftTarget = ST
