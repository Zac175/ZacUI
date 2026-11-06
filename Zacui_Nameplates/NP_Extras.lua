-- NP_Extras - the visible behaviors of the profile's Plater MODS,
-- rebuilt natively: target arrows (Naowh Arrow / Double Arrow Target),
-- the mob's current target on the plate (Target Name on Plate), and the
-- quest ! icon (Extra Quest Icon). Raid marks ride UpdateName in
-- NP_Health; cast target names ride NP_Cast.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local NP = ns.Nameplates

local DB = NP.DB
local SetNPFont = NP.SetNPFont

-- ============================================================
-- BUILD
-- ============================================================
function NP.BuildExtras(f)
    -- "Arrow Thin", the target indicator the profile had selected -
    -- Plater's own texture (bundled in ZacUI's media now), one on each
    -- side pointing in, additive blend, exactly as Plater drew it.
    -- (they live on the target marks' host, NP_Health's f.tgtCue, so the
    -- target animation plays them with the neon)
    local arrowTex = NP.TEX_ARROW_THIN
    local host = f.tgtCue or f
    local left = host:CreateTexture(nil, "OVERLAY")
    left:SetTexture(arrowTex)            -- points right, into the bar
    left:SetBlendMode("ADD")
    local right = host:CreateTexture(nil, "OVERLAY")
    right:SetTexture(arrowTex)
    right:SetTexCoord(1, 0, 0, 1)        -- mirrored: points left
    right:SetBlendMode("ADD")
    left:Hide()
    right:Hide()
    f.arrowL, f.arrowR = left, right

    -- who the mob is hitting, tucked under the bar's right corner.
    -- FONT AT BIRTH: a FontString with no font errors on the first
    -- SetText, and build order must never be what stands between us
    -- and that - layout re-sizes later.
    f.targetName = f:CreateFontString(nil, "OVERLAY")
    SetNPFont(f.targetName, 8)
    f.targetName:SetJustifyH("RIGHT")

    -- quest !
    f.quest = f:CreateFontString(nil, "OVERLAY")
    SetNPFont(f.quest, 10)
    f.quest:SetText("|cffffd100!|r")
    f.quest:Hide()
end

-- Where the mob's target name hangs: under the threat strip's text when
-- the strip is on for this plate (NP_Threat moves that stack under the
-- cast bar while one shows, and calls this again), else its original
-- spot under the health bar's right corner.
function NP.AnchorTargetName(f)
    local tail = NP.ThreatTail and NP.ThreatTail(f)
    -- the name STAYS where it is - right under the bar (or the threat
    -- strip) - while the icons under the bar grow from the left. Only
    -- when they actually run into it does it step down under them, and
    -- it comes back as soon as they no longer reach it.
    local D = NP.Debuffs
    local nameW = ((f.targetName:GetText() or "") ~= "") and (f.targetName:GetStringWidth() or 0) or 0
    local drop = 0
    if D and D.UnderHitsName and D.UnderHitsName(f, nameW) then drop = D.UnderReach(f) end
    local host = tail or ((f.cast and f.cast:IsShown()) and f.cast) or f.health
    -- the icon line starts where the row was put (level with the threat
    -- strip, or under it when crowded)
    local under = (drop > 0) and (f.dbUnderPad or (NP.CastDrop and NP.CastDrop(f)) or 0) or 0
    local key = under * 10000 + drop * 10 + (tail and 1 or (host == f.cast and 2 or 3))
    if f._tnKey == key and f._tnHost == host then return end
    f._tnKey, f._tnHost = key, host
    local def
    if drop > 0 then
        local y = -under - drop - 1
        def = NP.SetDef(f, "targetName", "TOPRIGHT", f.health, "BOTTOMRIGHT", 0, y)
    elseif tail then
        def = NP.SetDef(f, "targetName", "TOPRIGHT", tail, "BOTTOMRIGHT", 0, -1)
    else
        def = NP.SetDef(f, "targetName", "TOPRIGHT", host, "BOTTOMRIGHT", 0, -2)
    end
    -- (the justify stays the one it was born with: RIGHT)
    NP.Place(f, f.targetName, "targetName", def)
end

-- The box - the chosen look (2026-10-19): an outline running all the
-- way round the health bar ("fully go around the target plate"), or
-- its four corners only (brackets), drawn from flat strips so they stay
-- pixel-crisp at any size and take the crosshair's colour like the
-- arrows do. Built on first use; the arrow textures stay for the other
-- looks.
local WHITE = "Interface\\Buttons\\WHITE8x8"
local function Brackets(f)
    if f.brackets then return f.brackets end
    local b = {}
    local host = f.tgtCue or f
    for i = 1, 8 do
        local t = host:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetTexture(WHITE)
        t:SetBlendMode("BLEND")
        t:Hide()
        b[i] = t
    end
    f.brackets = b
    -- born white: the next tint must paint them even if the arrows
    -- already wear that colour (the first-target white box came from the
    -- tint cache saying "already red" while these did not exist yet)
    f._arR, f._arG, f._arB = nil, nil, nil
    return b
end

-- arm length and thickness from the bar height and the size slider:
-- a 10-tall bar gets 6 x 2 arms sitting 2 outside the bar's edge
local function LayoutBrackets(f, h, sc)
    local b = Brackets(f)
    local L = math.max(4, math.floor(h * 0.6 + 0.5)) * sc
    -- a 1px line at 100% ("a bit thinner"); the size slider thickens it
    local T = math.max(1, math.floor(1 * sc + 0.5))
    local o = 2
    -- measured from the marks' host, which sits exactly over the bar
    local hb = f.tgtCue or f.health
    if f._arrowStyle == "box" then
        -- four edges, each running the full length plus the outset, so
        -- the corners meet; the other four strips idle
        local top, bottom, left, right = b[1], b[2], b[3], b[4]
        top:SetHeight(T)    top:ClearAllPoints()
        top:SetPoint("BOTTOMLEFT", hb, "TOPLEFT", -o, o - T)
        top:SetPoint("BOTTOMRIGHT", hb, "TOPRIGHT", o, o - T)
        bottom:SetHeight(T) bottom:ClearAllPoints()
        bottom:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", -o, T - o)
        bottom:SetPoint("TOPRIGHT", hb, "BOTTOMRIGHT", o, T - o)
        left:SetWidth(T)    left:ClearAllPoints()
        left:SetPoint("TOPLEFT", hb, "TOPLEFT", -o, o)
        left:SetPoint("BOTTOMLEFT", hb, "BOTTOMLEFT", -o, -o)
        right:SetWidth(T)   right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", hb, "TOPRIGHT", o, o)
        right:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", o, -o)
        for i = 5, 8 do b[i]:Hide() end
        return
    end
    local corners = {
        { "TOPLEFT",     -o,  o },
        { "TOPRIGHT",     o,  o },
        { "BOTTOMLEFT",  -o, -o },
        { "BOTTOMRIGHT",  o, -o },
    }
    for i, c in ipairs(corners) do
        local horiz, vert = b[i * 2 - 1], b[i * 2]
        horiz:SetSize(L, T)
        horiz:ClearAllPoints()
        horiz:SetPoint(c[1], hb, c[1], c[2], c[3])
        vert:SetSize(T, L)
        vert:ClearAllPoints()
        vert:SetPoint(c[1], hb, c[1], c[2], c[3])
    end
end

-- shows or hides whichever set the look uses (arrows, or the strips)
local STRIPS = { brackets = 8, box = 4 }
local function ShowArrows(f, on)
    on = on and true or false
    f._arrowsOn = on
    local n = STRIPS[f._arrowStyle]
    f.arrowL:SetShown(on and not n)
    f.arrowR:SetShown(on and not n)
    if f.brackets or n then
        local b = Brackets(f)
        for i = 1, 8 do b[i]:SetShown(on and n ~= nil and i <= n) end
    end
end
NP.ShowTargetArrows = ShowArrows

-- the looks of the target arrows; the solid triangle art points down,
-- so it is turned a quarter to point at the bar from each side
local ARROW_TEX = { thin = NP.TEX_ARROW_THIN, chevron = NP.TEX_ARROW_CHEVRON, solid = NP.TEX_ARROW_SOLID }
local function StyleArrows(f, style)
    if f._arrowStyle == style then return end
    f._arrowStyle = style
    if STRIPS[style] then
        Brackets(f)                -- exist before the tint that follows
        f.arrowL:Hide()
        f.arrowR:Hide()
        return
    end
    local tex = ARROW_TEX[style] or NP.TEX_ARROW_THIN
    f.arrowL:SetTexture(tex)
    f.arrowR:SetTexture(tex)
    if style == "solid" then
        f.arrowL:SetTexCoord(0, 1, 0, 1)
        f.arrowR:SetTexCoord(0, 1, 0, 1)
        f.arrowL:SetBlendMode("BLEND")
        f.arrowR:SetBlendMode("BLEND")
        if f.arrowL.SetRotation then
            f.arrowL:SetRotation(math.pi / 2)        -- points right, into the bar
            f.arrowR:SetRotation(-math.pi / 2)       -- points left
        end
    else
        f.arrowL:SetTexCoord(0, 1, 0, 1)
        f.arrowR:SetTexCoord(1, 0, 0, 1)             -- mirrored: points left
        f.arrowL:SetBlendMode("ADD")
        f.arrowR:SetBlendMode("ADD")
        if f.arrowL.SetRotation then f.arrowL:SetRotation(0) f.arrowR:SetRotation(0) end
    end
end

-- The arrows' colour: the crosshair's (its live colour - range and
-- in-front tints included - so the two always match), or plain white.
local function ArrowColor(d)
    local mode = d.extras.arrowColor or "crosshair"
    if mode == "custom" then
        local c = d.extras.arrowCustomColor
        if c then return c[1] or 1, c[2] or 1, c[3] or 1 end
    end
    if mode == "crosshair" then
        local CH = NP.Crosshair
        if CH and CH.Enabled and CH.Enabled() and CH.CurrentColor then
            local c = CH.CurrentColor()
            if c then return c[1], c[2], c[3] end
        end
    end
    return 1, 1, 1
end
local function TintArrows(f, r, g, b)
    if f._arR ~= r or f._arG ~= g or f._arB ~= b then
        f._arR, f._arG, f._arB = r, g, b
        f.arrowL:SetVertexColor(r, g, b, 1)
        f.arrowR:SetVertexColor(r, g, b, 1)
        if f.brackets then
            for i = 1, 8 do f.brackets[i]:SetVertexColor(r, g, b, 1) end
        end
    end
end
-- the crosshair repainted (range changed): the shown arrows follow
function NP.TintTargetArrows(col)
    local d = DB()
    if (d.extras.arrowColor or "crosshair") ~= "crosshair" then return end
    for _, f in pairs(NP.activePlates or {}) do
        if f.arrowL and f._arrowsOn then TintArrows(f, col[1], col[2], col[3]) end
    end
end

-- a cast starting or ending moves the stack under the bar: the name follows
if NP.OnUnderBarChange then
    NP.OnUnderBarChange(function(f) if f.targetName then NP.AnchorTargetName(f) end end)
end

function NP.LayoutExtras(f)
    f._tnKey = nil                 -- the name re-anchors below, whatever it was
    local d = DB()
    local h = select(2, NP.FrameDims(f))
    -- Plater's "Arrow Thin" auto-scale: 1.5x / 2x the bar height, sized
    -- as for a 10-tall bar at most - a taller bar grew them into the icons
    -- Readycheck puts beside the plate.
    local ah0 = math.min(h, 10)
    local sc = tonumber(d.extras.arrowScale) or 1
    if not d.extras.arrowV2 then
        d.extras.arrowV2 = true
        if d.extras.arrowStyle == "solid" then d.extras.arrowStyle = "chevron" end
    end
    -- the brackets were picked from the examples (2026-10-19): a save
    -- still on one of the arrow looks it never chose goes to them once
    if not d.extras.arrowV3 then
        d.extras.arrowV3 = true
        d.extras.arrowStyle = "brackets"
    end
    -- ...and then asked to go all the way round (same day)
    if not d.extras.arrowV4 then
        d.extras.arrowV4 = true
        if d.extras.arrowStyle == "brackets" then d.extras.arrowStyle = "box" end
    end
    local style = d.extras.arrowStyle or "box"
    local switched = f._arrowStyle ~= nil and f._arrowStyle ~= style
    StyleArrows(f, style)
    TintArrows(f, ArrowColor(d))
    if STRIPS[style] then
        LayoutBrackets(f, ah0, sc)
    else
        local aw, ah
        if style == "solid" then
            -- a triangle reads best square-ish and a touch smaller
            ah = math.max(12, ah0 * 1.6) * sc
            aw = ah
        else
            aw = math.max(12, math.floor(ah0 * 1.5 + 0.5)) * sc
            ah = math.max(16, ah0 * 2) * sc
        end
        local gap = (style == "solid") and 3 or 1
        local hb = f.tgtCue or f.health
        f.arrowL:SetSize(aw, ah)
        f.arrowL:ClearAllPoints()
        f.arrowL:SetPoint("RIGHT", hb, "LEFT", -gap, 0)
        f.arrowR:SetSize(aw, ah)
        f.arrowR:ClearAllPoints()
        f.arrowR:SetPoint("LEFT", hb, "RIGHT", gap, 0)
    end
    -- a look change while the plate is the target: swap what is shown
    if switched and f._arrowsOn then ShowArrows(f, true) end

    f._tnKey = nil          -- a layout always re-places it (a saved anchor may have changed)
    NP.AnchorTargetName(f)
    local tnf = d.extras.targetNameFont
    NP.ApplyNPFont(f.targetName, tnf, tonumber(tnf and tnf.size) or 8)

    -- the quest mark wears the name's font
    local qcfg = f.isFriend and d.friendly or d.enemy
    NP.ApplyNPFont(f.quest, qcfg.nameFont, qcfg.nameSize)
    if f._nameInside then
        -- the name is inside the bar: the quest mark goes just outside it
        NP.Place(f, f.quest, "quest", NP.SetDef(f, "quest", "RIGHT", f.health, "LEFT", -2, 0))
    else
        NP.Place(f, f.quest, "quest", NP.SetDef(f, "quest", "RIGHT", f.name, "LEFT", -2, 0))
    end
end

-- ============================================================
-- QUEST SCAN - era has no UnitIsQuestBoss, so the tooltip is the truth.
-- One hidden tooltip, results cached per npc id, cache dropped whenever
-- the quest log changes.
-- ============================================================
local questCache = {}
local scanTip = CreateFrame("GameTooltip", "ZacUI_NPQuestScan",
    nil, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

function NP.WipeQuestCache()
    wipe(questCache)
end

local function UnitIsOnQuest(unit, npcId)
    if not npcId then return false end
    local hit = questCache[npcId]
    if hit ~= nil then return hit end

    scanTip:ClearLines()
    scanTip:SetUnit(unit)
    local found = false
    for i = 2, scanTip:NumLines() do
        local line = _G["ZacUI_NPQuestScanTextLeft" .. i]
        local text = line and line:GetText()
        if text and text ~= "" then
            local tr, tg, tb = line:GetTextColor()
            -- quest lines render gold-ish yellow in the tooltip
            if tr > 0.9 and tg > 0.75 and tb < 0.35 then
                found = true
                break
            end
        end
    end
    questCache[npcId] = found
    return found
end

-- ============================================================
-- UPDATE
-- ============================================================
function NP.UpdateExtras(f)
    if not f.unit then return end
    local d = DB()
    local unit = f.unit

    -- the mob's current target, class-colored, combat only
    local tn, r, g, b
    if d.extras.targetName and not f.isFriend
        and UnitAffectingCombat(unit) then
        local t = unit .. "target"
        tn = UnitExists(t) and UnitName(t)
        if tn then
            r, g, b = 1, 1, 1
            if UnitIsPlayer(t) then
                local _, class = UnitClass(t)
                local cc = class and RAID_CLASS_COLORS
                    and RAID_CLASS_COLORS[class]
                if cc then r, g, b = cc.r, cc.g, cc.b end
            end
        end
    end

    -- quest !
    local showQuest = false
    if d.extras.questIcon and not f.isFriend and not UnitIsPlayer(unit) then
        -- the id NP_Core read when the plate was assigned; false means
        -- "not a creature", nil means it was never read
        local npcId = f.npcId
        if npcId == nil then npcId = NP.NpcIdFromUnit(unit) end
        showQuest = UnitIsOnQuest(unit, npcId)
    end
    NP.FillExtras(f, UnitIsUnit(unit, "target"), tn, r, g, b, showQuest)
end

-- The extras from the facts: is it the target, who the mob is hitting
-- (and their colour; nil = nobody, or not shown), whether a quest wants
-- it. The switches are read here, so the settings preview's samples obey
-- them exactly as a live plate does.
function NP.FillExtras(f, isTarget, tn, r, g, b, showQuest)
    local d = DB()
    -- target arrows - never on a name-only plate: they anchor to the
    -- health bar, and a friendly showing just a name has no bar to flank
    local wantArrows = d.extras.targetArrows and isTarget
        and not f.nameOnly
    if wantArrows then TintArrows(f, ArrowColor(d)) end
    ShowArrows(f, wantArrows)

    if tn and d.extras.targetName and not f.isFriend then
        if f.targetName:GetText() ~= tn then
            f.targetName:SetText(tn)
            -- a longer or shorter name may now meet the icons, or no longer
            NP.AnchorTargetName(f)
        end
        f.targetName:SetTextColor(r or 1, g or 1, b or 1, 0.9)
    else
        f.targetName:SetText("")
    end
    f.quest:SetShown((showQuest and d.extras.questIcon) and true or false)
end
