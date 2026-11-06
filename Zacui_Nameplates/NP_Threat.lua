-- NP_Threat - the threat bar under the health bar: a short strip tucked
-- under the bar's right corner, directly above the mob's target name,
-- that fills with your threat against THAT mob, 100% = you pull it. The
-- health bar's colour already says "safe / warning / yours"; this says
-- HOW CLOSE, per mob, without looking away from the plate. The percent
-- (or the name of who is closest) reads to the strip's left.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHAT IT SHOWS.
--   * Not tanking it: the bar is your scaled threat percentage from
--     UnitDetailedThreatSituation - scaled means the 110% / 130% melee
--     and ranged pull thresholds are already folded in, so 100% is the
--     moment it turns. Green below the warning line, yellow above it,
--     red at 100.
--   * Tanking it: the bar flips to the person CLOSEST to taking it off
--     you - their percentage, their name - the way TinyThreat colours
--     the tank's row from the highest non-tank. Green while the raid is
--     safe, red as someone closes in. Only your target gets that scan
--     (one API call per group member, twice a second); every other mob
--     on you shows a full bar in the tanking colour.
--   * Out of combat, or not on its threat list at all: hidden.
--
-- WHERE IT SITS. Under the health bar's right corner, text beneath it,
-- the mob's target name beneath that. When a CAST BAR shows, the whole
-- stack drops to hang off the cast bar's bottom-right corner instead,
-- and climbs back when the cast ends - the cast bar keeps its tight
-- anchor under the health bar and nothing is ever drawn over the strip.
-- The move is driven by the cast bar's own OnShow/OnHide, hooked once at
-- build, so every path that shows or hides a cast (start, stop,
-- interrupt flash, plate recycle) re-anchors without knowing about us.
--
-- The values ride NP.UpdateColor, which is already the funnel for every
-- threat event and the half-second combat sweep - there is no second
-- event driver to keep in step.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local Col = ns.Col
local NP = ns.Nameplates

local DB = NP.DB
local SetNPFont = NP.SetNPFont

-- ============================================================
-- BUILD
-- ============================================================
function NP.BuildThreat(f)
    local tb = CreateFrame("StatusBar", nil, f)
    tb:SetStatusBarTexture(NP.BarTexture("threatTexture"))
    tb:SetMinMaxValues(0, 100)
    tb:SetValue(0)
    -- above the cast bar: the two never overlap by layout, but if they
    -- ever meet, the strip wins the draw
    tb:SetFrameLevel(f.cast:GetFrameLevel() + 1)
    f.threat = tb

    local bg = tb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local w = Col("windowBg")
    bg:SetColorTexture(w.r, w.g, w.b, 0.85)
    tb.bg = bg
    AddPixelBorder(tb)

    -- FONT AT BIRTH, same rule as every other plate string. The text
    -- rides the strip's BOTTOM EDGE, right-aligned: its midline on the
    -- edge, so half sits on the coloured fill and half hangs below - it
    -- reads as part of the bar, not a caption under it. The strip is too
    -- short for "Frosty 82%" to fit inside outright.
    tb.text = tb:CreateFontString(nil, "OVERLAY")
    SetNPFont(tb.text, 8)
    tb.text:SetPoint("RIGHT", tb, "BOTTOMRIGHT", -1, 0)
    tb.text:SetJustifyH("RIGHT")
    tb.text:SetWordWrap(false)

    -- the cast bar showing or hiding moves the stack (see the header)
    f.cast:HookScript("OnShow", function() NP.AnchorThreat(f) end)
    f.cast:HookScript("OnHide", function() NP.AnchorThreat(f) end)
    -- and the strip itself coming or going moves what hangs under it
    tb:HookScript("OnShow", function() if NP.UnderBarChanged then NP.UnderBarChanged(f) end end)
    tb:HookScript("OnHide", function() if NP.UnderBarChanged then NP.UnderBarChanged(f) end end)

    tb:Hide()
end

-- The region the mob's target name hangs from: the last thing in our
-- stack when the strip is on for this plate, nil when it is off (the
-- name then keeps its original anchor under the health bar).
function NP.ThreatTail(f)
    if not f.threat or not f._threatOn then return nil end
    local t = DB().threatBar
    return t.text and f.threat.text or f.threat
end

-- Re-anchor the strip to whichever bar is the bottom of the plate right
-- now: the cast bar while one is showing, the health bar otherwise.
-- Runs from layout and from the cast bar's OnShow/OnHide.
function NP.AnchorThreat(f)
    local tb = f.threat
    if not tb or not f._threatOn then return end
    local gap = math.max(0, DB().threatBar.gap or 1)
    local host = (f.cast and f.cast:IsShown()) and f.cast or f.health
    -- under the bar itself it also clears the target box (the cast bar
    -- already does)
    if host == f.health and NP.BoxClear then gap = gap + NP.BoxClear() end
    -- flush with the bar's right edge, the corner the target name lives
    -- under, so the stack reads: bar, strip, text, name (the side's saved
    -- anchor on top: NP.Place)
    NP.Place(f, tb, "threatBar", NP.SetDef(f, "threatBar", "TOPRIGHT", host, "BOTTOMRIGHT", 0, -(1 + gap)))
    if NP.AnchorTargetName then NP.AnchorTargetName(f) end
end

-- ============================================================
-- LAYOUT - sizes and fonts; runs before LayoutExtras (NP_Health's
-- LayoutFrame orders it) so f._threatOn is settled when the target
-- name asks where to hang. Anchoring is AnchorThreat's, because it
-- also runs outside layout.
-- ============================================================
function NP.LayoutThreat(f)
    local d = DB()
    local t = d.threatBar
    local tb = f.threat
    f._threatOn = (t.enabled and not f.isFriend and not f.nameOnly) or false

    if not f._threatOn then
        tb:Hide()
        return
    end

    local h = math.max(1, t.height or 6)
    local bw = NP.FrameDims(f)
    -- never wider than the bar it hangs off
    local w = math.min(bw, math.max(10, t.width or 60))
    tb:SetStatusBarTexture(NP.BarTexture("threatTexture"))
    NP.BarChrome(tb.bg, tb)
    tb:SetSize(w, h)

    if t.text then
        NP.ApplyNPFont(tb.text, t.font, t.textSize or 8)
        local tc = t.textColor
        if tc then tb.text:SetTextColor(tc[1] or 1, tc[2] or 1, tc[3] or 1, tc[4] or 1) end
        NP.Place(f, tb.text, "threatText", NP.SetDef(f, "threatText", "RIGHT", tb, "BOTTOMRIGHT", -1, 0, "RIGHT"))
        tb.text:Show()
    else
        tb.text:Hide()
    end
    NP.AnchorThreat(f)
end

-- ============================================================
-- ROSTER - who could take it off you: ZacUI's shared roster (ns.Roster),
-- rebuilt once per burst of roster news, never per update.
-- ============================================================
local Roster = ns.Roster

-- Closest non-tank to pulling `unit` off you: their scaled % and name.
-- Pets are read too (a hunter pet ripping is a real rip, and the threat
-- API answers for partypetN / raidpetN). Anyone already tanking it is
-- skipped: a second tank who HAS it is not "about to take it".
--
-- This is the one expensive read in the file - a threat call for every
-- member of the raid and every pet - so the answer is kept for
-- NEXT_INTERVAL per mob. The colour pass that asks for it can run ten
-- times a second; who is second on threat does not change that fast.
local NEXT_INTERVAL = 0.5
local nextGuid, nextAt, nextPct, nextName

local function Better(u, unit, bestPct)
    local isTanking, status, pct = UnitDetailedThreatSituation(u, unit)
    if status ~= nil and not isTanking and pct and pct > bestPct then return pct end
end

local function NextThreat(unit, guid)
    local now = GetTime()
    if guid and guid == nextGuid and now - nextAt < NEXT_INTERVAL then
        return nextPct, nextName
    end
    local bestPct, bestUnit = 0, nil
    -- the group (yourself excluded) and every pet in it - your own too
    -- (PetUnits holds "pet" in a party, your raidpetN in a raid)
    local units = Roster.Units()
    for i = 1, #units do
        local u = units[i]
        if not UnitIsUnit(u, "player") then
            local p = Better(u, unit, bestPct)
            if p then bestPct, bestUnit = p, u end
        end
    end
    local pets = Roster.PetUnits()
    for i = 1, #pets do
        local p = Better(pets[i], unit, bestPct)
        if p then bestPct, bestUnit = p, pets[i] end
    end
    nextGuid, nextAt = guid, now
    nextPct, nextName = bestPct, bestUnit and UnitName(bestUnit) or nil
    return nextPct, nextName
end

-- ============================================================
-- UPDATE
-- ============================================================
local function Paint(tb, t, pct, isTanking)
    local c
    if isTanking then
        c = t.tanking
    elseif pct >= 100 then
        c = t.danger
    elseif pct >= (t.warnAt or 70) then
        c = t.warn
    else
        c = t.safe
    end
    tb:SetStatusBarColor(c[1], c[2], c[3], 1)
end

-- have/isTanking/status/pct: the threat read NP.UpdateColor already made
-- for this plate in the same pass, handed over so it is not made twice.
-- Called without them, the strip reads for itself.
function NP.UpdateThreat(f, have, isTanking, status, pct)
    local tb = f.threat
    if not tb then return end
    local unit = f.unit
    if not unit or not f._threatOn then
        tb:Hide()
        return
    end
    local d = DB()
    local t = d.threatBar

    if not UnitAffectingCombat(unit) then
        tb:Hide()
        return
    end
    local isTarget = NP.IsEffectiveTarget and NP.IsEffectiveTarget(unit, d)
        or UnitIsUnit(unit, "target")
    if t.targetOnly and not isTarget then
        tb:Hide()
        return
    end
    if not UnitDetailedThreatSituation then
        tb:Hide()
        return
    end

    if not have then
        isTanking, status, pct = UnitDetailedThreatSituation("player", unit)
    end
    if status == nil then
        -- fighting, but we are not on its list: nothing to measure
        tb:Hide()
        return
    end
    pct = pct or 0

    -- ours. The target plate shows who is closest to taking it; the
    -- rest just show that it is held.
    local nextPct, nextName
    if isTanking and isTarget and Roster.Size() > 1 then
        nextPct, nextName = NextThreat(unit, f.guid)
    end
    NP.FillThreat(f, pct, isTanking, nextPct, nextName)
end

-- The strip from the numbers alone (your scaled %, whether you hold it,
-- and while you do, who is closest and their %) - live plates above, the
-- settings preview's samples directly.
function NP.FillThreat(f, pct, isTanking, nextPct, nextName)
    local tb = f.threat
    if not tb then return end
    local t = DB().threatBar
    pct = pct or 0
    if isTanking then
        if nextName then
            tb:SetValue(math.min(100, nextPct))
            -- the colour is about THEM closing on you, so it walks the
            -- same safe/warn/danger scale as your own bar does
            Paint(tb, t, nextPct, false)
            if t.text then
                -- rewritten only when the shown number or name moves
                local shown = math.floor(nextPct + 0.5)
                if tb._tp ~= shown or tb._tn ~= nextName then
                    tb._tp, tb._tn = shown, nextName
                    tb.text:SetFormattedText("%s %d%%", nextName, shown)
                end
            end
        else
            tb:SetValue(100)
            Paint(tb, t, 100, true)
            if t.text and tb._tp ~= 100 then tb._tp, tb._tn = 100, nil tb.text:SetText("100%") end
        end
    else
        tb:SetValue(math.min(100, pct))
        Paint(tb, t, pct, false)
        if t.text then
            local shown = math.floor(pct + 0.5)
            if tb._tp ~= shown or tb._tn ~= false then
                tb._tp, tb._tn = shown, false
                tb.text:SetFormattedText("%d%%", shown)
            end
        end
    end
    tb:Show()
end
