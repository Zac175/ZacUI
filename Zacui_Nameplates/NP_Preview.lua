-- NP_Preview - sample nameplates, built and painted by the engine's own
-- code (NP_Health, NP_Cast, NP_Threat, NP_Extras, NP_Debuffs, the soft
-- target's arrows, the HUD's cooldown row) from made-up facts instead of
-- a unit. Two places use them:
--   * the settings preview dock (Nameplates page, Config_PagesNameplates)
--     - enemy, target, casting, friendly and important scenes, every
--     setting on the page reflected the moment it changes;
--   * one plate on screen with everything on (the "Show on screen"
--     button, /zui plate) for placing the plates against the rest of the
--     UI - movable on the Movers page while it is up.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local NP = ns.Nameplates
if not NP then return end

local S = {}
NP.Sample = S

-- the raid mods' plate strip, as two sample icons at its spot
local PACK = { 132343, 132345 }      -- Disarm, Enrage (the NX ones)

-- ============================================================
-- A SAMPLE PLATE
-- ============================================================
-- The sample cast bar loops through its cast instead of ending (the
-- live OnUpdate hides the bar when the cast is over). An OnUpdate on the
-- sample itself: it only runs while the sample is on screen.
local function SampleCastTick(cb, elapsed)
    local len = cb._pvLen
    if not len then return end
    cb._pvT = (cb._pvT or 0) + (elapsed or 0)
    if cb._pvT > len then cb._pvT = 0 end
    local frac = cb._pvT / len
    cb:SetValue(cb.channeling and (1 - frac) or frac)
end

-- A plate frame exactly as NP_Core makes one, parented where asked (the
-- preview canvas, or the on-screen holder). Never in the engine's plate
-- lists, no unit, no events: it is painted by S.Fill alone.
function S.New(parent, name)
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(150, 16)
    f.isFriend = false
    f.preview = true
    NP.BuildHealth(f)
    NP.BuildCast(f)
    NP.BuildAuras(f)
    NP.BuildExtras(f)
    if NP.BuildThreat then NP.BuildThreat(f) end
    f.cast:SetScript("OnUpdate", SampleCastTick)
    -- every text and part tagged with its element key, so a click in the
    -- preview can open its controls (ZacUI's pick hook, "np." keys)
    local Tag = ns.TagElement
    if Tag then
        local cb, tb = f.cast, f.threat
        Tag(f.health, "np.health")
        Tag(f.name, "np.name") Tag(f.level, "np.level") Tag(f.percent, "np.percent")
        Tag(cb, "np.castbar") Tag(cb.spell, "np.castText") Tag(cb.iconFrame, "np.castIcon")
        Tag(f.raidIconFrame, "np.raidMarker") Tag(f.targetName, "np.targetName") Tag(f.quest, "np.quest")
        Tag(f.auras, "np.auras")
        if tb then Tag(tb, "np.threatBar") Tag(tb.text, "np.threatText") end
    end

    -- the pack strip stand-ins
    f.pack = {}
    for i = 1, #PACK do
        local t = f:CreateTexture(nil, "OVERLAY")
        t._zui_own = true
        t:SetTexture(PACK[i])
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t:SetSize(30, 30)
        t:Hide()
        f.pack[i] = t
    end
    return f
end

-- ============================================================
-- THE SCENES - made-up facts for each kind of plate worth seeing
-- ============================================================
-- Side by side (x), for the settings preview strip: the page sizes the
-- canvas to whatever the plates draw.
-- facts: what NP.UpdateColor reads instead of the unit (combat, tanking,
-- status, pct, grouped, otherTank, isPlayer, class, tapped, reaction)
S.SCENES = {
    -- a mob you are fighting, not your target; a second one under the
    -- cursor, about to change hands
    enemy = {
        { name = "Deathknight Captain", level = 61, hp = 62, mark = 8, combat = true,
          facts = { combat = true, status = 0, pct = 45, grouped = true },
          threat = { pct = 45 }, targetName = "Zaccw", targetClass = "WARRIOR",
          debuffs = true, pack = true, auras = true, x = -105, y = 0 },
        { name = "Skeletal Smith", level = 60, hp = 88, combat = true, hover = true,
          facts = { combat = true, status = 1, pct = 92, grouped = true },
          threat = { pct = 92 }, targetName = "Zacp", targetClass = "PALADIN",
          quest = true, x = 105, y = 0 },
    },
    -- your target (with the BT/WW row and the soft target arrows) and the
    -- plate next to it, faded behind it
    target = {
        { name = "Deathknight Captain", level = 61, hp = 62, mark = 8, combat = true,
          target = true, anyTarget = true,
          facts = { combat = true, status = 0, pct = 45, grouped = true },
          threat = { pct = 45 }, targetName = "Zaccw", targetClass = "WARRIOR",
          debuffs = true, pack = true, auras = true, row = true, arrow = "cur", x = -110, y = 0 },
        { name = "Skeletal Smith", level = 60, hp = 88, combat = true, anyTarget = true,
          facts = { combat = true, status = 0, pct = 30, grouped = true },
          threat = { pct = 30 }, targetName = "Zacp", targetClass = "PALADIN",
          arrow = "next", x = 110, y = 0 },
    },
    -- the three cast bar colours: a cast, a channel, one that can't be
    -- interrupted (the first is interrupted on Replay)
    casting = {
        { name = "Deathknight Cavalier", level = 61, hp = 74, combat = true,
          facts = { combat = true, status = 0, pct = 20, grouped = true },
          cast = { name = "Shadow Bolt", icon = 136197, len = 3, at = 1.1, tn = "Zaccw", tclass = "WARRIOR" },
          x = -175, y = 0 },
        { name = "Necro Knight", level = 61, hp = 51, combat = true,
          facts = { combat = true, status = 0, pct = 20, grouped = true },
          cast = { name = "Mind Flay", icon = 136208, len = 3, at = 1.9, channel = true, tn = "Zacp", tclass = "PALADIN" },
          x = 0, y = 0 },
        { name = "Plagued Gargoyle", level = 60, hp = 93, combat = true,
          facts = { combat = true, status = 0, pct = 20, grouped = true },
          cast = { name = "Stoneskin", icon = 136025, len = 2.5, at = 0.8, uninterruptible = true },
          x = 175, y = 0 },
    },
    -- a friendly player and a friendly NPC
    friendly = {
        { friend = true, name = "Zacp", isPlayer = true, class = "PALADIN", hp = 80, combat = true,
          facts = { isPlayer = true, class = "PALADIN" },
          cast = { name = "Flash of Light", icon = 135907, len = 1.5, at = 0.6 },
          x = -95, y = 0 },
        { friend = true, name = "Stormwind Guard", level = 55, hp = 100, combat = false,
          facts = { reaction = 5 }, x = 95, y = 0 },
    },
    -- a priority mob and a boss: the important colour, threat on the
    -- border, the priority size, and the mid-screen count
    important = {
        { name = "Lightning Totem", level = 60, hp = 100, combat = true, priority = true,
          facts = { combat = true, status = 0, pct = 10, grouped = true },
          x = -95, y = 8 },
        { name = "Grand Widow Faerlina", level = -1, hp = 71, combat = true, boss = true,
          target = false, anyTarget = true,
          facts = { combat = true, status = 3, tanking = true, pct = 100, grouped = true },
          threat = { pct = 100, tanking = true }, targetName = "Zaccw", targetClass = "WARRIOR",
          debuffs = true, x = 95, y = 8 },
    },
}
-- the on-screen plate: the target, with everything on
S.SHOWCASE = S.SCENES.target[1]

local function ClassRGB(class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if cc then return cc.r, cc.g, cc.b end
    return 1, 1, 1
end

-- ============================================================
-- PAINT ONE
-- ============================================================
-- s: one scene entry. animate: let the target state glide and the marks
-- play their entrance (the dock's Replay) instead of setting it at once.
-- castEntrance: a hidden cast bar plays its entrance as it shows (only
-- the Replay asks; an update never animates).
function S.Fill(f, s, animate, castEntrance)
    local d = NP.DB()
    f.isFriend = s.friend and true or false
    f._pvCombat = s.combat and true or false
    -- the flags a live plate settles in UpdateName / on assign
    local p = d.priority
    f._priority = (s.priority and p and p.enabled) and true or false
    f._noFade = s.noFade and true or false
    f.isBoss = s.boss and true or false
    NP.LayoutFrame(f)
    local cfg = f.isFriend and d.friendly or d.enemy

    NP.FillHealth(f, s.hp or 62, 100, "zui-sample")
    NP.FillName(f, s.name or "", s.isPlayer, s.class, s.level)
    NP.FillRaidMark(f, s.mark)
    NP.UpdateColor(f, s.facts or {})
    NP.SetHoverGlow(f, (s.hover and d.target.hover) and d.target.hoverAlpha or 0)

    -- the fade, the size cue, the neon (and their animations on Replay)
    local cue = (not d.target.combatOnly) or s.combat
    NP.ApplyTargetState(f, s.target and true or false, s.anyTarget and true or false, cue, not animate)

    -- the threat strip: where a live plate would show it
    local tbd = d.threatBar
    local th = s.threat
    if th and s.combat and f._threatOn and (not tbd.targetOnly or s.target) then
        NP.FillThreat(f, th.pct, th.tanking, th.nextPct, th.nextName)
    elseif f.threat then
        f.threat:Hide()
    end

    -- the mob's target, the target box / arrows, the quest mark
    local tr, tg, tb = ClassRGB(s.targetClass)
    NP.FillExtras(f, s.target and true or false, s.combat and s.targetName or nil, tr, tg, tb,
        s.quest and not f.isFriend)

    -- a cast, looping
    local c = s.cast
    local cb = f.cast
    if c and cfg.castbar then
        local cr, cg, cbb = ClassRGB(c.tclass)
        local col = c.tn and string.format("ff%02x%02x%02x", math.floor(cr * 255 + 0.5),
            math.floor(cg * 255 + 0.5), math.floor(cbb * 255 + 0.5)) or nil
        cb._pvLen = c.len or 3
        if animate or not cb:IsShown() then cb._pvT = c.at or 1 end
        if not castEntrance and not cb:IsShown() then cb:Show() end
        NP.FillCast(f, c.name, c.icon, 0, 1, c.uninterruptible, nil, c.channel, c.tn, col)
        SampleCastTick(cb, 0)
    else
        cb._pvLen = nil
        if cb._zMotion and ns.Motion then ns.Motion.Stop(cb) end
        cb:Hide()
    end

    -- the older aura row: two sample icons, only while it is on
    local holder = f.auras
    if holder and NP.AcquireAuraIcon then
        if s.auras and d.auras.enabled and not f.isFriend then
            NP.LayoutAuras(f)
            local samples = { { 132363, 5 }, { 136033, 0 }, { 135358, 2 } }
            local n = math.min(2, d.auras.max or 6)
            -- a third icon only to show a layout that wraps
            if type(d.auras.layout) == "table" then n = math.min(#samples, d.auras.max or 6) end
            for i = 1, n do
                local smp = samples[i]
                local ic = NP.AcquireAuraIcon(holder, i)
                ic.tex:SetTexture(smp[1])
                if ic.count then ic.count:SetText(smp[2] > 0 and tostring(smp[2]) or "") end
                ic:Show()
            end
            for i = n + 1, #holder.icons do holder.icons[i]:Hide() end
            -- placed the way the live row places them (NP_Auras)
            if n > 0 and NP.PlaceAuraRow then NP.PlaceAuraRow(f, n) end
            holder:Show()
        else
            for _, ic in ipairs(holder.icons) do ic:Hide() end
            holder:Hide()
        end
    end

    -- the debuff groups, with sample states
    local D = NP.Debuffs
    if D then
        if s.debuffs and not f.isFriend and D.PreviewPlate then D.PreviewPlate(f)
        elseif D.ClearPreview then D.ClearPreview(f) end
    end

    -- the raid mods' plate strip: the packs' ~30px art at the strip's
    -- scale, straight after the debuff row (or from the bar's right
    -- corner growing left, or at the centre-measured spot growing right)
    local spot = s.pack and not f.isFriend and D and D.PackStrip and D.PackStrip()
    local psz = math.floor(30 * (spot and tonumber(spot.scale) or 1) + 0.5)
    local hb = f.health
    for i, t in ipairs(f.pack) do
        t:ClearAllPoints()
        t:SetSize(psz, psz)
        if spot and spot.at == "after" and f.dbUnderEnd then
            t:SetPoint("TOPLEFT", f.dbUnderEnd, "TOPLEFT", (tonumber(spot.x) or 0) + (i - 1) * (psz + 2), tonumber(spot.y) or 0)
            t:Show()
        elseif spot and spot.at ~= "center" then
            t:SetPoint("TOPRIGHT", hb, "BOTTOMRIGHT", (tonumber(spot.x) or 0) - (i - 1) * (psz + 2), tonumber(spot.y) or 0)
            t:Show()
        elseif spot then
            t:SetPoint("LEFT", hb, "CENTER", (tonumber(spot.x) or 0) + (i - 1) * (psz + 2), tonumber(spot.y) or 0)
            t:Show()
        else
            t:Hide()
        end
    end
    -- the target name steps round whatever ended up under the bar
    if NP.AnchorTargetName then f._tnKey = nil NP.AnchorTargetName(f) end
end

-- The cast bar's entrance and, after a beat, the interrupt (the casting
-- scene's Replay). Each step checks the sample is still on screen.
function S.ReplayCast(f, s, interrupt, token)
    local c = s.cast
    local cb = f.cast
    if not (c and cb) then return end
    local cfg = f.isFriend and NP.DB().friendly or NP.DB().enemy
    if not cfg.castbar then return end
    if cb._zMotion and ns.Motion then ns.Motion.Stop(cb) end
    cb:Hide()
    S.Fill(f, s, false, true)
    if not interrupt then return end
    C_Timer.After(1.2, function()
        if not f:IsVisible() or (token and token()) then return end
        NP.FlashInterrupt(f, function()
            if f:IsVisible() and not (token and token()) then S.Fill(f, s, false) end
        end)
    end)
end

-- ============================================================
-- THE HUD'S COOLDOWN ROW ON A SAMPLE
-- ============================================================
-- Zacui_HUD's Hesitation row is one frame on UIParent that it anchors
-- over the target's plate; its PreviewPlateRow puts it over a sample. In
-- the dock the row is lent to the sample (parented to it, so it scales
-- and clips with the canvas and hides with it) and handed back to
-- UIParent the moment the sample hides, a fight starts, or another scene
-- is chosen - the live row is never left inside the settings window.
local rowHost
local function RowFrame() return _G.ZacUIHUD_HesitationPlate end

function S.ReleaseRow(f)
    if f and rowHost ~= f then return end
    local row = RowFrame()
    if rowHost and row then
        row:SetParent(UIParent)
        row:SetFrameStrata("HIGH")
    end
    rowHost = nil
    local H = ns.Hesitation
    if H and H.EndPreviewPlateRow then H:EndPreviewPlateRow() end
    -- the on-screen sample takes it back if it is up
    if S._onScreenRefill then S._onScreenRefill() end
end

-- lend: true for a sample inside the dock
function S.ShowRow(f, lend)
    local H = ns.Hesitation
    if not (H and H.PreviewPlateRow) then return end
    if lend and InCombatLockdown and (InCombatLockdown() or UnitAffectingCombat("player")) then
        -- the live row is in use: the dock goes without
        if rowHost == f then S.ReleaseRow(f) end
        return
    end
    H:PreviewPlateRow(f)
    local row = RowFrame()
    if not (lend and row) then return end
    if row:IsShown() then
        if row:GetParent() ~= f then row:SetParent(f) end
        row:SetFrameStrata(f:GetFrameStrata())
        row:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
        rowHost = f
    elseif rowHost == f then
        S.ReleaseRow(f)
    end
end

function S.RowHost() return rowHost end

local guard = CreateFrame("Frame")
guard:RegisterEvent("PLAYER_REGEN_DISABLED")
guard:SetScript("OnEvent", function() if rowHost then S.ReleaseRow() end end)

-- ============================================================
-- THE SOFT TARGET ARROWS ON A SAMPLE
-- ============================================================
-- The soft target's own arrows (NP_SoftTarget's MakeArrow / StyleArrow)
-- over a sample plate, where the live ones would sit: "cur" over the
-- mob you are on, "next" over the picker's next mob.
function S.Arrow(owner, f, which)
    local ST = ns.SoftTarget
    owner._pvArrows = owner._pvArrows or {}
    local a = owner._pvArrows[f]
    local s = ST and ST.DB and ST.DB()
    local on = s and which and s.softTarget and s.softMarker
        and (which == "cur" or s.nextUp)
    if not on then
        if a then a:Hide() end
        return
    end
    if not a then
        if not ST.MakeArrow then return end
        a = ST.MakeArrow(nil, owner)
        owner._pvArrows[f] = a
    end
    ST.StyleArrow(a, s)
    local col = (which == "cur") and s.curColor or s.softColor
    if col then a.tex:SetVertexColor(col[1], col[2], col[3]) end
    a:SetFrameLevel((f:GetFrameLevel() or 1) + 30)
    a:ClearAllPoints()
    a:SetPoint("BOTTOM", f.markTop or f.name or f.health, "TOP", s.markerOffX or 0, s.markerOffY or 4)
    a:Show()
end

-- ============================================================
-- THE ON-SCREEN PLATE (/zui plate, "Show on screen")
-- ============================================================
local P = {}
NP.Preview = P

local holder, f
local shown = false

local function Build()
    if f then return f end
    local d = NP.DB()
    holder = CreateFrame("Frame", "ZacUIPlatePreview_Holder", UIParent)
    holder:SetSize(d.enemy.width or 120, 60)
    holder:SetFrameStrata("HIGH")
    if ns.HUD and ns.HUD.PlaceAnchor then ns.HUD.PlaceAnchor("platePreview", holder, { x = 0, y = 120 })
    else holder:SetPoint("CENTER", UIParent, "CENTER", 0, 120) end
    if ns.HUD and ns.HUD.RegisterMover then
        ns.HUD.RegisterMover("platePreview", "Nameplate preview", holder, { x = 0, y = 120 })
    end
    f = S.New(holder, "ZacUIPlatePreview")
    f:SetPoint("CENTER", holder, "CENTER", 0, 0)
    f:SetFrameStrata("HIGH")
    return f
end

local function Fill()
    S.Fill(f, S.SHOWCASE, false)
    local w, h = f:GetWidth(), f:GetHeight()
    holder:SetSize(w, h)
    -- the BT/WW cooldown row, unless the dock has it right now
    if not rowHost then S.ShowRow(f, false) end
    S.Arrow(holder, f, "cur")
end

function P.IsShown() return shown end

function P.Refresh()
    if shown and f then Fill() end
end
S._onScreenRefill = function() if shown and f then Fill() end end

function P.Show()
    Build()
    shown = true
    holder:Show()
    f:Show()
    Fill()
end

function P.Hide()
    shown = false
    if holder then holder:Hide() end
    if f then f:Hide() end
    if not rowHost then
        local H = ns.Hesitation
        if H and H.EndPreviewPlateRow then H:EndPreviewPlateRow() end
    end
end

function P.Toggle()
    if shown then P.Hide() else P.Show() end
    return shown
end

-- settings change under it: the live plates refresh, so does this one
local origRefresh = NP.RefreshAll
NP.RefreshAll = function(...)
    local r = origRefresh(...)
    P.Refresh()
    return r
end
