-- NP_Cast - the per-plate cast bar: icon, spell name, interruptible
-- coloring, interrupted flash.
-- Part of ZacUI; load order is set by the TOC.

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
local function CastOnUpdate(cb)
    local startMS, endMS = cb.startMS, cb.endMS
    if not startMS then return end   -- (also a hidden cast: the game's timer drives it)
    local now = GetTime() * 1000
    local total = endMS - startMS
    if total <= 0 then total = 1 end
    local frac = (now - startMS) / total
    if frac >= 1 then
        frac = 1
        cb.startMS = nil
        cb:Hide()
    end
    cb:SetValue(cb.channeling and (1 - frac) or frac)
end

function NP.BuildCast(f)
    local cb = CreateFrame("StatusBar", nil, f)
    cb:SetStatusBarTexture(NP.BarTexture("castTexture"))
    cb:SetMinMaxValues(0, 1)
    cb:Hide()
    cb:SetScript("OnUpdate", CastOnUpdate)
    f.cast = cb

    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local w = Col("windowBg")
    bg:SetColorTexture(w.r, w.g, w.b, 0.85)
    cb.bg = bg
    AddPixelBorder(cb)

    -- icon in its own bordered frame - the "Cast Icon Border" mod
    local iconFrame = CreateFrame("Frame", nil, cb)
    cb.iconFrame = iconFrame
    cb.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    cb.icon:SetPoint("TOPLEFT", 1, -1)
    cb.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ibg = iconFrame:CreateTexture(nil, "BACKGROUND")
    ibg:SetAllPoints()
    ibg:SetColorTexture(w.r, w.g, w.b, 0.85)
    iconFrame.bg = ibg
    AddPixelBorder(iconFrame)

    -- the leading-edge spark Plater draws on its cast bars
    local spark = cb:CreateTexture(nil, "OVERLAY", nil, 1)
    spark:SetColorTexture(1, 1, 1, 0.9)
    spark:SetBlendMode("ADD")
    spark:SetWidth(2)
    spark:SetPoint("TOP", cb:GetStatusBarTexture(), "TOPRIGHT", 0, 2)
    spark:SetPoint("BOTTOM", cb:GetStatusBarTexture(), "BOTTOMRIGHT", 0, -2)
    cb.spark = spark

    cb.spell = cb:CreateFontString(nil, "OVERLAY")
    SetNPFont(cb.spell, 9) -- font at birth; layout re-sizes
    cb.spell:SetPoint("CENTER", cb, "CENTER", 0, 0)
    cb.spell:SetWordWrap(false)

    -- the things that hang under the plate (debuff strip, raid-pack
    -- icons, the mob's target name) follow the lowest bar; a cast
    -- starting or ending moves them
    cb:HookScript("OnShow", function() NP.UnderBarChanged(f) end)
    cb:HookScript("OnHide", function() NP.UnderBarChanged(f) end)
end

-- How far below the health bar's bottom edge the first free line
-- starts right now: past the cast bar while one shows, past the threat
-- strip (and the text hanging half under it) while that is up. What
-- hangs "under the bar" anchors to the HEALTH bar's own corners with
-- this as its drop, so it always lines up with the plate's left and
-- right edges (the threat strip is a short bar flush right - hanging
-- from its corner put the debuff row in the middle of the plate).
-- The target box (Nameplates > Extras) runs 2 px outside the bar with a
-- 1 px line: everything hung under the bar starts clear of it - on
-- every plate while the box is the chosen look, so nothing shifts by
-- 3 px as the target changes.
function NP.BoxClear()
    local e = NP.DB().extras or {}
    local st = e.arrowStyle or "box"
    if e.targetArrows and (st == "box" or st == "brackets") then return 3 end
    return 0
end

function NP.UnderDrop(f)
    local y = NP.BoxClear()
    local cb = f.cast
    if cb and cb:IsShown() then y = y + 2 + (cb:GetHeight() or 0) end
    local tb = f.threat
    if tb and f._threatOn and tb:IsShown() then
        local t = NP.DB().threatBar or {}
        y = y + 1 + math.max(0, t.gap or 1) + (tb:GetHeight() or 0)
        if tb.text and tb.text:IsShown() then y = y + math.ceil((t.textSize or 8) / 2) + 1 end
    end
    return y
end

-- ...and only the cast bar's part of that: the debuff row under the
-- bar's left corner sits LEVEL with the threat strip (which is flush
-- right), not under it, so the plate stays symmetrical - row on the
-- left, strip on the right
function NP.CastDrop(f)
    local y = NP.BoxClear()
    local cb = f.cast
    if cb and cb:IsShown() then y = y + 2 + (cb:GetHeight() or 0) end
    return y
end
-- how much of the bar's width the threat strip takes from the right
-- (plus a little air), 0 while it is not up
function NP.ThreatWidth(f)
    local tb = f.threat
    if tb and f._threatOn and tb:IsShown() then return (tb:GetWidth() or 0) + 4 end
    return 0
end

-- modules that hang under the bar register here; called with the plate
local watchers = {}
function NP.OnUnderBarChange(fn) watchers[#watchers + 1] = fn end
function NP.UnderBarChanged(f)
    for i = 1, #watchers do watchers[i](f) end
    -- only the plate the crosshair sits on moves its lines; every other
    -- plate's casts coming and going are none of its business
    local CH = NP.Crosshair
    if CH and CH.Remeasure and CH.IsOn and CH.IsOn(f.PlateFrame) then CH.Remeasure() end
end

-- What hangs under the bar came or went (debuff icons, the raid-pack
-- strip): the mob's target name moves up or down to sit right under
-- it, and on my target the crosshair's bottom line follows
function NP.UnderContentChanged(f)
    if f.targetName and NP.AnchorTargetName then NP.AnchorTargetName(f) end
    local CH = NP.Crosshair
    if CH and CH.Remeasure and f.unit and UnitIsUnit(f.unit, "target") then CH.Remeasure() end
end

function NP.LayoutCast(f)
    local d = DB()
    local cfg = f.isFriend and d.friendly or d.enemy
    local cb = f.cast

    -- at rest before it moves: a cast bar mid-entrance would otherwise
    -- finish on the spot it had before this layout
    if cb._zMotion and ns.Motion then ns.Motion.Stop(cb) end
    cb:SetStatusBarTexture(NP.BarTexture("castTexture"))
    NP.BarChrome(cb.bg, cb)
    NP.BarChrome(cb.iconFrame.bg, cb.iconFrame)
    cb.spark:SetShown(d.castbar.spark ~= false)
    -- where the bar, its icon and its spell name sit: the built-in spot
    -- with the side's saved anchor on top (NP.Place, NP_Health)
    NP.Place(f, cb, "castbar", NP.SetDef(f, "castbar", "TOP", f.health, "BOTTOM", 0, -2 - NP.BoxClear()))
    cb:SetSize(cfg.castWidth, cfg.castHeight)

    if d.castbar.icon then
        -- castIconSize nil = a shade taller than the bar, as always
        local sz = tonumber(cfg.castIconSize) or (cfg.castHeight + 6)
        cb.iconFrame:SetSize(sz, sz)
        NP.Place(f, cb.iconFrame, "castIcon", NP.SetDef(f, "castIcon", "RIGHT", cb, "LEFT", -2, 0))
        cb.iconFrame:Show()
    else
        cb.iconFrame:ClearAllPoints()
        cb.iconFrame:Hide()
    end
    NP.Place(f, cb.spell, "castText", NP.SetDef(f, "castText", "CENTER", cb, "CENTER", 0, 0))

    NP.ApplyNPFont(cb.spell, cfg.castFont, cfg.castTextSize or 9)
    local tc = d.castbar.textColor
    if tc then cb.spell:SetTextColor(tc[1] or 1, tc[2] or 1, tc[3] or 1, tc[4] or 1) end
    cb.spell:SetWidth(cfg.castWidth - 4)
end

-- ============================================================
-- STATE
-- ============================================================
-- the spell name's own colour back (after a state's text colour)
local textBack = setmetatable({}, { __mode = "k" })
local function CastTextBack(cb)
    local fn = textBack[cb]
    if not fn then
        fn = function()
            local tc = DB().castbar.textColor
            if tc then cb.spell:SetTextColor(tc[1] or 1, tc[2] or 1, tc[3] or 1, tc[4] or 1)
            else cb.spell:SetTextColor(1, 1, 1, 1) end
        end
        textBack[cb] = fn
    end
    return fn
end

local function PaintCast(cb, notInterruptible)
    local d = DB()
    -- a cast-alert entry for this spell outranks the normal palette
    local alert = cb.spellID and d.castAlerts[cb.spellID]
    local c = alert
        or (notInterruptible and d.castbar.uninterruptible)
        or (cb.channeling and d.castbar.channel)
        or d.castbar.normal
    cb:SetStatusBarColor(c[1], c[2], c[3], 0.95)
    -- the cast states' own look (d.states, Nameplates > Look); a
    -- cast-alert colour outranks them like it outranks the palette
    if d.states or cb._npSt then
        NP.PaintState(cb, cb.spell, (not alert) and ((notInterruptible and "uninterruptible")
            or (cb.channeling and "channel") or "casting") or nil, 0.95, CastTextBack(cb))
    end
end

function NP.StopCast(f)
    local cb = f.cast
    local wasCasting = cb:IsShown()
    if cb._zMotion and ns.Motion then ns.Motion.Stop(cb) end
    cb.startMS, cb.endMS, cb.channeling, cb.spellID = nil, nil, nil, nil
    cb._scriptKey = nil
    cb:Hide()
    if wasCasting and NP.Scripts then NP.Scripts.CastStop(f) end
end

-- Re-read the unit's real cast state. Called on plate assign, on config
-- refresh and from the cast events - the events only say "something
-- changed"; the API is the truth.
function NP.CheckCast(f)
    if not f.unit then return end
    local cb = f.cast

    -- the profile hid friendly cast bars entirely
    local d = DB()
    local cfg = f.isFriend and d.friendly or d.enemy
    if not cfg.castbar then
        NP.StopCast(f)
        return
    end

    local name, _, texture, startMS, endMS, _, _, notInterruptible,
        spellID = UnitCastingInfo(f.unit)
    -- WoW Forever hides an enemy's cast in combat (secret values: no
    -- compare, no arithmetic): no bar until it reads again
    local Sec = ns.IsSecret
    if Sec and (Sec(name) or Sec(startMS) or Sec(endMS)) then
        if NP.FillHiddenCast(f, name, texture, false) then return end
        NP.StopCast(f) return
    end
    local channeling = false
    if not name and UnitChannelInfo then
        local cName, _, cTexture, cStartMS, cEndMS, _, cNotInterruptible,
            cSpellID = UnitChannelInfo(f.unit)
        if Sec and (Sec(cName) or Sec(cStartMS) or Sec(cEndMS)) then
            if NP.FillHiddenCast(f, cName, cTexture, true) then return end
            NP.StopCast(f) return
        end
        if cName then
            name, texture, startMS, endMS, notInterruptible, spellID =
                cName, cTexture, cStartMS, cEndMS, cNotInterruptible, cSpellID
            channeling = true
        end
    end

    if not name then
        NP.StopCast(f)
        return
    end

    -- "Cast Target on Spell Name": who this cast is aimed at
    local tn, color
    if d.extras.castTargetName then
        local t = f.unit .. "target"
        tn = UnitExists(t) and UnitName(t)
        if tn then
            color = "ffffffff"
            if UnitIsPlayer(t) then
                local _, class = UnitClass(t)
                local cc = class and RAID_CLASS_COLORS
                    and RAID_CLASS_COLORS[class]
                if cc and cc.colorStr then color = cc.colorStr end
            end
        end
    end
    NP.FillCast(f, name, texture, startMS, endMS, notInterruptible, spellID, channeling, tn, color)

    -- a NEW cast (not a re-read of the same one) wakes the script engine
    local key = tostring(spellID or name) .. "-" .. tostring(startMS)
    if cb._scriptKey ~= key then
        cb._scriptKey = key
        if NP.Scripts then NP.Scripts.CastStart(f, spellID, name) end
    end
end

-- WoW Forever hides an enemy's cast in combat (secret values: no compare,
-- no arithmetic). The bar still shows it: the game's own duration object
-- for the cast drives the fill (UnitCastingDuration / UnitChannelDuration
-- -> StatusBar:SetTimerDuration, ZacUI's display helpers), the spell's
-- name and icon go onto the text and icon as they are. What needs the
-- spell's id or the caster's target (cast alerts, the scripts, "cast
-- target on spell name") and whether it can be interrupted are hidden
-- too: it wears the plain casting / channel colour. false when this
-- client can't (the bar then goes, as before).
function NP.FillHiddenCast(f, name, texture, channeling)
    local cb = f.cast
    if not (ns.CastDuration and ns.ShowCastTimer) then return false end
    local dur = ns.CastDuration(f.unit, channeling)
    if not dur or not ns.ShowCastTimer(cb, dur, channeling) then return false end
    cb.startMS, cb.endMS, cb.channeling, cb.spellID = nil, nil, channeling, nil
    cb._scriptKey = nil
    cb._zTimer = true
    pcall(cb.spell.SetText, cb.spell, name)
    pcall(cb.icon.SetTexture, cb.icon, texture)
    PaintCast(cb, nil)
    if cb:IsShown() then return true end
    local a = DB().anim
    local spec = a and a.cast
    if ns.Motion and spec and spec.style and spec.style ~= "none" then
        ns.Motion.Show(cb, spec)
    else
        cb:Show()
    end
    return true
end

-- The bar for one cast from its facts - the live read above and the
-- settings preview's samples both paint through here. tn / color: the
-- cast's target and its colour string, shown only with Cast target on.
-- A bar that was not up plays its entrance (Nameplates > Animation).
function NP.FillCast(f, name, texture, startMS, endMS, notInterruptible, spellID, channeling, tn, color)
    local cb = f.cast
    local d = DB()
    local text = name
    if tn and d.extras.castTargetName then
        text = ("%s |c%s[%s]|r"):format(name, color or "ffffffff", tn)
    end
    -- (after a hidden cast on WoW Forever: back to the 0-1 fill)
    if cb._zTimer then cb._zTimer = nil cb:SetMinMaxValues(0, 1) end
    cb.startMS, cb.endMS, cb.channeling = startMS, endMS, channeling
    cb.spellID = spellID
    cb.spell:SetText(text)
    cb.icon:SetTexture(texture)
    PaintCast(cb, notInterruptible)
    cb:SetValue(channeling and 1 or 0)
    if cb:IsShown() then return end
    local a = d.anim
    local spec = a and a.cast
    if ns.Motion and spec and spec.style and spec.style ~= "none" then
        ns.Motion.Show(cb, spec)
    else
        cb:Show()
    end
end

-- The interrupt: a brief flash in the interrupted colour (and its own
-- animation, Nameplates > Animation), held castbar.interruptHold
-- seconds, then `after` (the live plate re-reads its cast).
function NP.FlashInterrupt(f, after)
    local cb = f.cast
    local d = DB()
    local c = d.castbar.interrupted
    cb.startMS = nil
    cb:SetValue(1)
    cb:SetStatusBarColor(c[1], c[2], c[3], 1)
    cb.spell:SetText(INTERRUPTED or "Interrupted")
    if d.states or cb._npSt then NP.PaintState(cb, cb.spell, "interrupted", 1, CastTextBack(cb)) end
    cb:Show()
    local a = d.anim
    local spec = a and a.interrupt
    if ns.Motion and spec and spec.style and spec.style ~= "none" then
        ns.Motion.Play(cb, spec, "update")
    end
    local hold = tonumber(d.castbar.interruptHold) or 0.5
    C_Timer.After(math.max(0.05, hold), after)
end

-- One entry point for every UNIT_SPELLCAST_* the driver routes here.
function NP.OnCastEvent(f, event)
    if event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- brief red flash so an interrupt reads as an interrupt, then
        -- let the state check clean up
        local cb = f.cast
        NP.FlashInterrupt(f, function()
            if f.unit then NP.CheckCast(f) else cb:Hide() end
        end)
        return
    end
    NP.CheckCast(f)
end
