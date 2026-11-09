-- Blz_Auras - buff, debuff and weapon-enchant buttons.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- ============================================================
-- HOW MANY BUFFS PER ROW
-- ============================================================
-- Blizzard's aura container wraps to fit the width of the frame it lives
-- in, and that width is computed once from the space beside the minimap.
-- Move the buff frame - which ZacUI's mover does - and the width it was
-- given no longer matches where it sits, so the icons pile into a narrow
-- block instead of running along the top.
--
-- The container knows how to lay itself out; it just needs to be told how
-- wide to wrap. iconStride is that number. Everything here is existence-
-- checked because this frame has been rebuilt across expansions and a
-- build without it should quietly do nothing rather than error on login.

-- ============================================================
-- CONSOLIDATED BUFFS
-- ============================================================
-- BuffFrame.ConsolidatedBuffs is Blizzard's "Consolidate Buffs" feature:
-- every long-duration raid buff is folded behind ONE icon, and hovering
-- that icon opens a flyout listing them. That flyout is the hover menu of
-- your own buffs, and the single icon is why the rest look stacked.
--
-- A frame stack found it. An earlier guess here went after
-- CollapseAndExpandButton - a real control, on the wrong frame - which is
-- why nothing changed: the buffs were never collapsed, they were
-- CONSOLIDATED, and those are two different features.
--
-- The real switch is the consolidateBuffs cvar, so that is what gets set;
-- hiding the frame alone would leave the feature on and the buffs still
-- missing from the row. The frame is hidden too, because Blizzard rebuilds
-- and re-shows it on its own passes.
-- Unset means ON (that is, consolidation OFF). The setting and every check
-- have to agree or the box reads enabled on a fresh profile while nothing
-- applies.
local function WantSeparateBuffs()
    return not (ZacUIDB and ZacUIDB.buffsAlwaysExpanded == false)
end

local function ApplyBuffConsolidation()
    if not WantSeparateBuffs() then return end

    -- Read before writing. This runs from several events, and setting a
    -- cvar that already holds the value is wasted work on every aura
    -- change; it also means the write only ever happens when something
    -- has actually turned it back on.
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if get and set then
        local ok, current = pcall(get, "consolidateBuffs")
        if not ok or current ~= "0" then
            -- SETUP2: recorded, so it goes back when the module is off
            if ns.CVar then ns.CVar.Set("consolidateBuffs", "0", "auras")
            else pcall(set, "consolidateBuffs", "0") end
        end
    end

    local bf = _G.BuffFrame
    if not bf then return end

    local cb = bf.ConsolidatedBuffs
    if cb then
        cb:Hide()
        if not cb._zuiHidden then
            cb._zuiHidden = true
            cb:HookScript("OnShow", function(self)
                if not (ZacUIDB and ZacUIDB.buffsAlwaysExpanded == false) then
                    self:Hide()
                end
            end)
        end
    end

    -- NO REFRESH CALL. This used to end with
    --
    --     local update = bf.UpdateAllBuffAnchors or bf.UpdateAuraButtons or bf.Update
    --     if update then pcall(update, bf) end
    --
    -- and on 11509 that resolves to BuffFrame:UpdateAuraButtons(), which
    -- runs AuraButtonMixin:Update on every button - `self.buttonInfo =
    -- buttonInfo` - from OUR execution. A field written by an addon is
    -- tainted, and the button's own right-click reads it:
    --
    --     CancelUnitBuff(PlayerFrame.unit, self.buttonInfo.index, ...)
    --
    -- which is the ADDON_ACTION_BLOCKED for CancelUnitBuff, credited to
    -- ZacUI, on any buff refreshed since the last of these calls - so all
    -- of them, since this ran on every CVAR_UPDATE and every leave-combat.
    --
    -- It was never needed. Blizzard registers consolidateBuffs with
    -- CVarCallbackRegistry, and the SetCVar above lands in
    -- OnConsolidationSettingsChanged on Blizzard's own event dispatch,
    -- which is secure. The frame refreshes itself; we only had to stop
    -- refreshing it for it.
end
ns.ApplyBuffConsolidation = ApplyBuffConsolidation
-- Kept under the old name so the config page and any hook wired to it
-- keep working after the rename.
ns.ApplyAuraExpand = ApplyBuffConsolidation
local ApplyAuraExpand = ApplyBuffConsolidation

-- ============================================================
-- IT HAS TO STICK, AND IT HAS TO STICK FOR EVERYONE
-- ============================================================
-- Applying this once from the module's login pass was not enough: the buff
-- frame is not necessarily built yet at that moment, and a cvar written
-- too early can be overwritten by the client's own settings pass. The
-- symptom was having to toggle the option off and on by hand before it
-- took, which is not a fix, it is a workaround the user has to remember.
--
-- So it is asserted from its own watcher rather than from the skin module:
--   PLAYER_ENTERING_WORLD  every load and every zone, after the frame exists
--   CVAR_UPDATE            anything - the client, another addon, the
--                          Interface panel - turning consolidation back on
--   PLAYER_REGEN_ENABLED   cvar writes can be refused in combat
--
-- CVAR_UPDATE is the one that makes this permanent instead of merely
-- initial. Living outside Modules.auras means it holds even when the buff
-- SKIN is switched off, because this is behaviour, not appearance, and
-- nobody disabling a skin means "give me the hover menu back".
--
-- No migration flag: the default is "on unless explicitly disabled", so
-- every existing profile is covered the moment this file loads.
local consolidationWatcher = CreateFrame("Frame")
consolidationWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
consolidationWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
consolidationWatcher:RegisterEvent("CVAR_UPDATE")
consolidationWatcher:SetScript("OnEvent", function(_, event)
    ApplyBuffConsolidation()
    if event == "PLAYER_ENTERING_WORLD" then
        -- One settle pass: the frame and Blizzard's own layout finish
        -- after this event on a cold login.
        C_Timer.After(2, ApplyBuffConsolidation)
    end
end)

-- ============================================================
-- BUFFS PER ROW, WITHOUT TOUCHING A FIELD BLIZZARD READS
-- ============================================================
-- The first version did `container.iconStride = n`. That is the field
-- AuraContainerMixin:UpdateGridLayout reads to build its grid, and a
-- value an addon wrote is tainted: the moment secure code reads it, that
-- whole execution is tainted from there on. BuffFrame's own paths run the
-- layout BEFORE the aura refresh -
--
--     function BuffFrameMixin:OnConsolidationSettingsChanged()
--       self:UpdateGridLayout();
--       self:Update();
--
-- so the refresh that followed wrote every button's buttonInfo while
-- tainted, and right-clicking a buff was blocked. The relayout call that
-- went with it never worked at all: UpdateGridLayout takes the aura list
-- as an argument and the call passed none, so it died in tFilter inside
-- the pcall every time. Only the field write had any effect, and its
-- effect was the taint.
--
-- So the stride is now applied AFTER Blizzard's layout, by re-running the
-- same grid utility Blizzard just ran with a different stride. Everything
-- read here is read, never written; everything written is a SetPoint or
-- SetSize on an aura button or the frame, which are not protected and are
-- not Lua values, so nothing secure can later trip over them.
--
-- Zero, the default, re-applies Blizzard's own cached layout object, so
-- switching the slider off puts the grid back without a reload.
-- TIMERS ON THE ICON'S BOTTOM EDGE (set by Modules.auras). With the time
-- sitting on the icon instead of in a strip below it, each row is only as
-- tall as the icon plus the half of the text that hangs under it - so the
-- rows close up from Blizzard's 40 to this.
local edgeTimers = false

-- shared state from earlier ZacUI files
local Col = ns.Col
local GetColor = ns.GetColor
local Modules = ns.Modules
local ZUI = ns.ZUI
local SharpenIcon = ns.SharpenIcon

-- ============================================================
-- THE LOOK (ZacUIDB.auraStyle, Screen > Buffs)
-- ============================================================
-- Every default is what this file drew before the settings existed:
-- 30 px icons, Blizzard's own spacing and growth, an 8% crop, a 1 px
-- border in the palette colour tinted by debuff type, the time on the
-- icon's bottom edge in ZacUI's font (orange under a minute, red under
-- ten seconds) and the stack count in the top-right corner. A colour or
-- font left unset is "as before" (the palette, ZacUI's font, Blizzard's
-- count font), so nothing changes until it is changed.
--
-- The same functions style the real buttons and the samples on the
-- Buffs page: NewSample builds a button shaped like Blizzard's, Style
-- dresses either kind, PaintTimer writes the time on either.
local LOOK = {
    iconSize = 30,          -- px (Blizzard's)
    spacing = -1,           -- px between icons; -1 = Blizzard's (Edit Mode's)
    growX = "auto",         -- "auto" (Blizzard's) | "left" | "right"
    growY = "auto",         -- "auto" | "down" | "up"
    zoom = 8,               -- % cropped off each edge of the icon
    borderSize = 1,         -- px
    debuffColors = true,    -- debuff border in its dispel type's colour
    showTimer = true,
    timerPos = "edge",      -- "edge" | "below" | "inside" | "center"
    timerX = 0, timerY = 1,
    warnAt = 60, urgentAt = 10,   -- seconds: orange, then red
    showCount = true,
    countPos = "TOPRIGHT",  -- a corner of the icon
    countX = -1, countY = -2,
    swipe = "short",        -- the dark sweep as time runs out (ZacUI look):
                            -- "off" | "short" (auras of 5 minutes or less) | "all"
}

-- ============================================================
-- HD POLISH (2026-11-07, ZacUI look only)
-- ============================================================
-- The ZacUI look's buffs follow the HD standard (zui_tests/
-- HD_POLISH_STANDARD_1107.md): a ring exactly one physical pixel wide drawn
-- over the icon's edge, a lighter crop (0.07, proved to show none of
-- Blizzard's frame at 12-64 px under that ring), the time on the icon's
-- bottom edge in an 11 px outline (the row gap grown to its overhang;
-- centred, under the icon or on the top edge are settings), the stack
-- number 12 px outlined in the
-- bottom-right corner, a 4 px gap, debuff rings in the HD dispel palette
-- and a reversed dark sweep on short auras.
--
-- The settings above are SAVED as they are read (FillDefaults), so a
-- profile from before holds the old defaults as values. Once, under the
-- ZacUI look only, every setting still at its old shipped value moves to
-- the HD one (auraStyle.hdRev); anything changed by hand is kept, and
-- after this every value is the player's again (the old spots stay in
-- the menus). The Classic, Blizzard and Forever looks never run it.
local HD_CROP = 0.07
local HD_TIMER_FONT = { size = 11, outline = "outline", shadow = false }
local HD_COUNT_FONT = { size = 12, outline = "outline", shadow = false }
-- Blizzard's DebuffTypeColor (what its border art is tinted with, read by
-- TintFrom) -> the HD palette, matched by the nearest colour
local DISPEL_BLIZZ = {
    { 0.80, 0.00, 0.00, { 0.80, 0.10, 0.10 } },   -- none
    { 0.20, 0.60, 1.00, { 0.35, 0.48, 1.00 } },   -- Magic
    { 0.60, 0.00, 1.00, { 0.64, 0.00, 0.64 } },   -- Curse
    { 0.60, 0.40, 0.00, { 0.67, 0.38, 0.10 } },   -- Disease
    { 0.00, 0.60, 0.00, { 0.00, 0.71, 0.29 } },   -- Poison
}
-- THE GAME LOOKS' KIT (2026-11-08, zui_tests/AB_KITS_STUDY_1108.md section
-- 6): under Classic WoW UI, Blizzard style and WoW Forever (Core_Look, part
-- "auras") the buff buttons are Blizzard's own and wear Blizzard's own art,
-- the way the reference UI's stock styles draw its player auras: the whole
-- icon, no ZacUI ring, Blizzard's debuff and weapon-enchant borders left
-- exactly as Blizzard paints them, Blizzard's own rows. The time stays a
-- ZacUI text so it is outlined (Zac's black edge), but in Blizzard's spot
-- (under the icon), words (its own duration text) and colours (gold, white
-- under a minute); the stack number stays where Blizzard put it. Each only
-- while the setting is still the value ZacUI shipped; nothing is written.
local function Kit()
    local L = ns.Look
    local lk = L and L.For and L.For("auras")
    local id = lk and lk.id
    if id == "classic" or id == "blizzard" or id == "forever" then return id end
    return nil
end
ns.AuraKit = Kit
local function IsHD()
    local L = ns.Look
    return L ~= nil and L.Active ~= nil and L.Active() == "zacui" and not Kit()
end
-- the one-time moves below wait for the look to be settled (Core_Look's
-- PLAYER_LOGIN re-read): before it a Classic save can read as ZacUI's
-- look, and a move made then would be made for good (2026-11-08)
local function Settled()
    local L = ns.Look
    return not (L and L.Settled) or L.Settled()
end
local function HDTint(r, g, b)
    local best, bd
    for _, e in ipairs(DISPEL_BLIZZ) do
        local d = (e[1] - r) ^ 2 + (e[2] - g) ^ 2 + (e[3] - b) ^ 2
        if not bd or d < bd then best, bd = e[4], d end
    end
    -- a colour nothing like Blizzard's five (another addon's): as it is
    if bd and bd > 0.08 then return r, g, b end
    return best[1], best[2], best[3]
end
-- THE MATCH PASS (2026-11-07, zui_tests/MATCH_BARS_1107.md): a second
-- step on the same one-time move, ZacUI look only - 32 px icons, a 5 px
-- gap, the stack number 11 px in the very corner, the sweep on every timed
-- aura (the reference UI's numbers). The time stays on the bottom edge
-- (Zac's pick). Only values still at the number shipped before move.
local function HDMigrate2(t)
    if (tonumber(t.hdRev) or 0) >= 2 or not Settled() or not IsHD() then return end
    t.hdRev = 2
    if (tonumber(t.iconSize) or 30) == 30 then t.iconSize = 32 end
    if (tonumber(t.spacing) or 4) == 4 then t.spacing = 5 end
    if t.countPos == "BOTTOMRIGHT" and (tonumber(t.countX) or -1) == -1 and (tonumber(t.countY) or 1) == 1 then
        t.countX, t.countY = 0, 0
    end
    local cf = t.countFont
    if type(cf) == "table" and cf.size == HD_COUNT_FONT.size and cf.face == nil
        and (cf.outline or "outline") == "outline" and not cf.shadow then
        cf.size = 11
    end
    if t.swipe == nil or t.swipe == "short" then t.swipe = "all" end
end
local function HDMigrate(t)
    if not Settled() then return end
    if t.hdRev or not IsHD() then return HDMigrate2(t) end
    t.hdRev = 1
    -- (the time stays on the bottom edge, Zac's pick: only its font moves)
    if t.countPos == "TOPRIGHT" and (tonumber(t.countX) or -1) == -1 and (tonumber(t.countY) or -2) == -2 then
        t.countPos, t.countX, t.countY = "BOTTOMRIGHT", -1, 1
    end
    if (tonumber(t.spacing) or -1) == -1 then t.spacing = 4 end
    if type(t.timerFont) ~= "table" or next(t.timerFont) == nil then
        t.timerFont = { size = HD_TIMER_FONT.size, outline = HD_TIMER_FONT.outline, shadow = HD_TIMER_FONT.shadow }
    end
    if type(t.countFont) ~= "table" or next(t.countFont) == nil then
        t.countFont = { size = HD_COUNT_FONT.size, outline = HD_COUNT_FONT.outline, shadow = HD_COUNT_FONT.shadow }
    end
    HDMigrate2(t)
end
local TIMER_SIZE = 10       -- ZacUI's font, as UI.Font draws it

local function Fill(dst, src)
    if ns.FillDefaults then return ns.FillDefaults(dst, src) end
    for k, v in pairs(src) do if dst[k] == nil then dst[k] = v end end
    return dst
end

local function Look()
    if not ZacUIDB then return Fill({}, LOOK) end
    local t = ZacUIDB.auraStyle
    if type(t) ~= "table" then t = {} ZacUIDB.auraStyle = t end
    Fill(t, LOOK)
    HDMigrate(t)
    return t
end

-- UNDER THE KIT: the values ZacUI shipped draw Blizzard's. The time's
-- shipped spot (on the bottom edge, 0 / 1) is Blizzard's (under the icon);
-- the shipped sizes (30, and the ZacUI look's 32 from its one-time move)
-- are Blizzard's 30; the shipped gaps (-1, and that move's 4 / 5) are
-- Blizzard's own; the HD fonts that move saved are the shipped fonts.
local function SameFont(f, size)
    return type(f) == "table" and f.face == nil and f.size == size
        and (f.outline or "outline") == "outline" and not f.shadow
end
local function KitTimerSpot(cfg)
    if not Kit() then return nil end
    local a = type(cfg.anchors) == "table" and cfg.anchors.timer or nil
    if a ~= nil then return nil end
    if (cfg.timerPos or "edge") == "edge" and (tonumber(cfg.timerX) or 0) == 0 and (tonumber(cfg.timerY) or 1) == 1 then
        return "below"
    end
    return nil
end
local function TimerPos(cfg)
    return KitTimerSpot(cfg) or cfg.timerPos
end
local function KitSize(cfg)
    local s = tonumber(cfg.iconSize) or 30
    if Kit() and (s == 30 or (s == 32 and (tonumber(cfg.hdRev) or 0) >= 2)) then return 30 end
    return s
end
local function KitSpacing(cfg)
    local pad = tonumber(cfg.spacing) or -1
    if Kit() and (pad == -1 or (pad == 4 and cfg.hdRev) or (pad == 5 and (tonumber(cfg.hdRev) or 0) >= 2)) then return -1 end
    return pad
end
-- the timer's font as the settings say: nil while it is the shipped one
local function TimerFontOf(cfg)
    local f = cfg.timerFont
    if Kit() and SameFont(f, 11) then return nil end
    return f
end
-- the stack number stays Blizzard's while its spot and font are shipped
local function KitCountStock(cfg)
    if not Kit() then return false end
    if type(cfg.anchors) == "table" and cfg.anchors.count ~= nil then return false end
    local pos, x, y = cfg.countPos or "TOPRIGHT", tonumber(cfg.countX) or -1, tonumber(cfg.countY) or -2
    local spot = (pos == "TOPRIGHT" and x == -1 and y == -2) or (pos == "BOTTOMRIGHT" and x == -1 and y == 1)
        or (pos == "BOTTOMRIGHT" and x == 0 and y == 0)
    if not spot then return false end
    local f = cfg.countFont
    if not (type(f) ~= "table" or next(f) == nil or SameFont(f, 12) or SameFont(f, 11)) then return false end
    return type(cfg.countColor) ~= "table" and cfg.showCount ~= false
end
-- Blizzard's own border art on a button (debuff, weapon enchant), scaled
-- with the icon from the size Blizzard gave it (read once)
local function KitBlizzBorder(b)
    return b._zBlizzBorder or b.DebuffBorder or b.TempEnchantBorder or b.Border or b.border
end
local function KitFitBorder(b, s)
    local bd = KitBlizzBorder(b)
    if not (bd and bd.GetSize and bd.SetSize) then return end
    local nat = rawget(bd, "_zKitNat")
    if not nat then
        local w, h = bd:GetSize()
        if type(w) ~= "number" or w <= 0 then return end
        nat = { w, h }
        rawset(bd, "_zKitNat", nat)
    end
    local k = (s or 30) / 30
    bd:SetSize(nat[1] * k, nat[2] * k)
end

-- Bumped whenever a setting changes; a button restyles itself when its
-- own stamp is behind (the sweep passes every button often, the restyle
-- only happens once per change).
local styleVer = 1

-- The extra height under the icon each timer position needs, so rows
-- close up or open out with it (edge: half the text hangs below).
local TIMER_EXTRA = { edge = 6, below = 12, inside = 0, center = 0, top = 6 }
local function CellSize(cfg)
    cfg = cfg or Look()
    local s = math.max(16, math.min(64, KitSize(cfg)))
    local tpos = TimerPos(cfg)
    local extra = (cfg.showTimer ~= false) and (TIMER_EXTRA[tpos] or 6) or 0
    -- the room grows with the time's own size: under the icon the whole
    -- text, on an edge the half that hangs over it (and a pixel to spare),
    -- so a bigger time never runs into the next row
    local tf = TimerFontOf(cfg)
    local fsz = cfg.showTimer ~= false and type(tf) == "table" and tonumber(tf.size)
    if fsz then
        local need = (tpos == "below" and fsz + 3)
            or ((tpos == "edge" or tpos == "top") and math.ceil(fsz / 2) + 1) or 0
        if need > extra then extra = need end
    end
    return s, s + extra
end

-- Spacing and growth: the setting, or Blizzard's when it says so.
local function GridOf(cfg, info)
    cfg = cfg or Look()
    local pad = KitSpacing(cfg)
    if pad < 0 then pad = (info and info.iconPadding) or 0 end
    local xMul, yMul
    if cfg.growX == "right" then xMul = 1
    elseif cfg.growX == "left" then xMul = -1
    else xMul = (info and info.addIconsToRight) and 1 or -1 end
    if cfg.growY == "up" then yMul = 1
    elseif cfg.growY == "down" then yMul = -1
    else yMul = (info and info.addIconsToTop) and 1 or -1 end
    return pad, xMul, yMul
end

-- Font: an untouched spec is the exact call this file always made;
-- anything set goes through the shared font path with today's look as
-- what the unset fields mean.
local function HouseOutline()
    local f = ZacUIDB and ZacUIDB.font
    return (f and f.outline == "NONE") and "none" or "outline"
end
local function Empty(spec)
    return type(spec) ~= "table" or next(spec) == nil
end
local function TimerFontDefaults()
    local f = ZacUIDB and ZacUIDB.font
    return { size = TIMER_SIZE + ((f and f.delta) or 0), outline = HouseOutline(), shadow = true }
end

local function ColorOr(c, cat, key)
    if type(c) == "table" then
        if ns.ColorOf then return ns.ColorOf(c) end
        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
    end
    local p = (GetColor and GetColor(cat, key)) or (Col and Col(key)) or { r = 1, g = 1, b = 1 }
    return p.r, p.g, p.b, p.a or 1
end

local function EdgeBorder(btn, target)
    if btn._zui_border then return btn._zui_border end
    -- under a game look's kit Blizzard's own border art is the border
    if Kit() then return nil end
    -- target: what the edge TRACES. Classic aura buttons ARE their
    -- icon rect, so the button is fine; 1.15.9 pooled buttons are
    -- BIGGER than their icon (inset art, duration region inside the
    -- button bounds) - tracing the button there draws a floating
    -- black box around every buff. Pooled callers pass the icon.
    target = target or btn
    local bd = Col("border")
    local t = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local tex = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetColorTexture(bd.r, bd.g, bd.b, 1)
        if side == "TOP" or side == "BOTTOM" then
            tex:SetPoint(side .. "LEFT", target, side .. "LEFT")
            tex:SetPoint(side .. "RIGHT", target, side .. "RIGHT")
        else
            tex:SetPoint("TOP" .. side, target, "TOP" .. side)
            tex:SetPoint("BOTTOM" .. side, target, "BOTTOM" .. side)
        end
        -- one physical pixel under the ZacUI look (Core_Pixel), 1 else
        if ns.Pixel then ns.Pixel.Edge(tex, side, btn)
        elseif side == "TOP" or side == "BOTTOM" then tex:SetHeight(1)
        else tex:SetWidth(1) end
        tex._zSide = side
        t[#t + 1] = tex
    end
    btn._zui_border = t
    return t
end

-- The border's resting colour: the setting, else the palette. A debuff's
-- dispel tint is laid over this by TintFrom (and kept in _zTint).
-- THE KIT'S SAMPLE BORDER: the settings page's samples are not Blizzard
-- buttons, so under the kit they draw the Classic template's art - the
-- debuff overlay 33 x 32 round a 30 icon (Interface\Buttons\
-- UI-Debuff-Overlays, its border cell 0.296875-0.5703125 x 0-0.515625,
-- tinted the dispel type's colour, red untyped) and the weapon-enchant
-- ring 32 round 30 (UI-TempEnchant-Border). Real buttons keep Blizzard's.
local KIT_DEBUFF = { file = "Interface\\Buttons\\UI-Debuff-Overlays", w = 33, h = 32,
    tc = { 0.296875, 0.5703125, 0, 0.515625 }, none = { 0.80, 0, 0 } }
local KIT_ENCHANT = { file = "Interface\\Buttons\\UI-TempEnchant-Border", w = 32, h = 32 }
local function PaintKitSample(b)
    local t = b._zKitBorder
    if not t then return end
    local spec = (b._zKind == "enchant") and KIT_ENCHANT or ((b._zKind == "debuff") and KIT_DEBUFF) or nil
    if not spec then t:Hide() return end
    local icon = b._zIconRef or b.Icon or b.icon
    local k = ((icon and icon.GetWidth and icon:GetWidth()) or 30) / 30
    if k <= 0 then k = 1 end
    t:SetTexture(spec.file)
    if spec.tc then t:SetTexCoord(spec.tc[1], spec.tc[2], spec.tc[3], spec.tc[4]) else t:SetTexCoord(0, 1, 0, 1) end
    t:ClearAllPoints()
    t:SetPoint("CENTER", icon or b, "CENTER", 0, 0)
    t:SetSize(spec.w * k, spec.h * k)
    if spec == KIT_DEBUFF then
        local c = b._zTint or spec.none
        t:SetVertexColor(c[1], c[2], c[3], 1)
    else
        t:SetVertexColor(1, 1, 1, 1)
    end
    t:Show()
end

local function PaintBorder(b, cfg)
    if b._zKitBorder then return PaintKitSample(b) end
    local strips = b._zui_border
    if not strips then return end
    cfg = cfg or Look()
    local r, g, bl, a
    if b._zTint and cfg.debuffColors ~= false then
        r, g, bl, a = b._zTint[1], b._zTint[2], b._zTint[3], 1
        -- the HD dispel palette under the ZacUI look
        if IsHD() then r, g, bl = HDTint(r, g, bl) end
    elseif b._zKind == "enchant" and type(cfg.enchantColor) == "table" then
        r, g, bl, a = ColorOr(cfg.enchantColor)
    else
        r, g, bl, a = ColorOr(cfg.borderColor, "ui", "border")
        if type(cfg.borderColor) ~= "table" then a = 1 end
    end
    local size = math.max(0, math.min(4, tonumber(cfg.borderSize) or 1))
    for _, tex in ipairs(strips) do
        tex:SetColorTexture(r, g, bl, a)
        if size == 0 then
            tex:Hide()
        else
            tex:Show()
            if ns.Pixel and ns.Pixel.SetEdgeSize(tex, size) then
                -- (one of ns.Pixel's: sized in physical pixels)
            elseif tex._zSide == "TOP" or tex._zSide == "BOTTOM" then tex:SetHeight(size)
            else tex:SetWidth(size) end
        end
    end
end

-- READ Blizzard's dispel border color; tint OUR border. Blizzard's
-- art is never touched.
local function TintFrom(b, blizz)
    if not (blizz and b._zui_border and blizz.GetVertexColor) then return end
    local r, g, bl = blizz:GetVertexColor()
    -- Default (1,1,1) vertex means UNTINTED ART, not "this aura is
    -- white": the 1.15.9 pooled BUFF border reads exactly that, and
    -- copying it painted every buff's edge white - the same law as
    -- the weapon-enchant fix: NEVER tint from art. Real dispel
    -- tints (magic/poison/curse/disease) are never pure white.
    if r and not (r > 0.99 and g > 0.99 and bl > 0.99) then
        local t = b._zTint
        if not (t and t[1] == r and t[2] == g and t[3] == bl) then
            b._zTint = { r, g, bl }
            PaintBorder(b)
        end
    end
end

local function FormatTime(t)
    -- the kit: the game's own abbreviation (SecondsToTimeAbbrev, "28 m")
    if Kit() then
        if SecondsToTimeAbbrev then
            local ok, fmt, v = pcall(SecondsToTimeAbbrev, t)
            if ok and type(fmt) == "string" then
                local ok2, out = pcall(string.format, fmt, v)
                if ok2 and type(out) == "string" then return out end
            end
        end
        if t >= 86400 then return math.ceil(t / 86400) .. " d" end
        if t >= 3600 then return math.ceil(t / 3600) .. " h" end
        if t >= 60 then return math.ceil(t / 60) .. " m" end
        return math.floor(t) .. " s"
    end
    -- the ZacUI look (match pass): the reference UI's bands - seconds up to
    -- 89, minutes from 90 s, hours from 90 min, days from 36 h
    if IsHD() then
        if t >= 129601 then return math.ceil(t / 86400) .. "d" end
        if t >= 5401 then return math.ceil(t / 3600) .. "h" end
        if t >= 90 then return math.ceil(t / 60) .. "m" end
        return tostring(math.floor(t))
    end
    if t >= 3600 then return math.ceil(t / 3600) .. "h" end
    if t >= 60 then return math.ceil(t / 60) .. "m" end
    return tostring(math.floor(t))
end

local TIMER_POINT = {
    edge   = { "CENTER", "BOTTOM" },
    below  = { "TOP", "BOTTOM" },
    inside = { "BOTTOM", "BOTTOM" },
    center = { "CENTER", "CENTER" },
    top    = { "CENTER", "TOP" },
}

-- WHERE THE TIME AND THE STACK NUMBER SIT. The presets above (timerPos /
-- countPos and their X / Y) are each text's built-in spot; the saved
-- anchor (auraStyle.anchors.timer / .count, ZacUI's anchor shape) goes on
-- top: any corner of the icon or the button, or hung off the other text.
-- Nothing saved = the preset's point, exactly.
ns.AURA_TEXT_LABELS = { icon = "The icon", button = "The button", timer = "Time left", count = "Stack number" }
local function AnchorOf(cfg, key)
    local a = cfg.anchors
    return type(a) == "table" and a[key] or nil
end
-- the presets as defaults (the settings page's pickers read them too)
function ns.AuraTextDefaults(cfg, key, into)
    local t = into or {}
    if key == "timer" then
        if KitTimerSpot(cfg) then
            -- the kit: Blizzard's own spot, under the icon
            t.point, t.relPoint, t.x, t.y = "TOP", "BOTTOM", 0, 0
            return t
        end
        local spot = TIMER_POINT[cfg.timerPos] or TIMER_POINT.edge
        t.point, t.relPoint, t.x, t.y = spot[1], spot[2], tonumber(cfg.timerX) or 0, tonumber(cfg.timerY) or 1
    else
        local corner = cfg.countPos or "TOPRIGHT"
        t.point, t.relPoint, t.x, t.y = corner, corner, tonumber(cfg.countX) or -1, tonumber(cfg.countY) or -2
    end
    return t
end
local function TextTo(b)
    if not b._zAnchorTo then
        b._zAnchorTo = function(k)
            if k == "icon" then return b._zIconRef or b.Icon or b.icon
            elseif k == "button" then return b
            elseif k == "timer" then return b._zTimer
            elseif k == "count" then return b.Count end
        end
    end
    return b._zAnchorTo
end

-- The time, the stack count, the crop and the border on one button -
-- a real aura button or a sample. Cheap to call again; the sweep only
-- does when the settings changed (styleVer).
local function StyleButton(b, cfg)
    cfg = cfg or Look()
    b._zStyleVer = styleVer
    local icon = b._zIconRef or b.Icon or b.icon
    if icon and icon.SetTexCoord then
        local zoom = tonumber(cfg.zoom) or 8
        -- (2026-11-08) the HD 0.07 crop is retired: every icon takes
        -- ZacUI's one crop, which hides the game's icon border
        local hdCrop = false
        -- the shipped 8 follows the look's icon crop (Core_Look's helper);
        -- under the ZacUI look's ring the HD crop (see HD POLISH above)
        if hdCrop then
            if ns.Look and ns.Look.ForgetIcon then ns.Look.ForgetIcon(icon) end
            icon:SetTexCoord(HD_CROP, 1 - HD_CROP, HD_CROP, 1 - HD_CROP)
        elseif zoom == 8 and ns.Look and ns.Look.CropIcon then
            ns.Look.CropIcon(icon, nil, nil, { part = "auras", border = false })
        else
            if ns.Look and ns.Look.ForgetIcon then ns.Look.ForgetIcon(icon) end
            local z = math.max(0, math.min(30, zoom)) / 100
            icon:SetTexCoord(z, 1 - z, z, 1 - z)
        end
    end
    PaintBorder(b, cfg)

    local fs = b._zTimer
    if fs then
        local def = ns.AuraTextDefaults(cfg, "timer", fs._zAnchorDef)
        def.to = icon or b
        fs._zAnchorDef = def
        ns.ApplyAnchor(fs, AnchorOf(cfg, "timer"), def, TextTo(b))
        local tfont = TimerFontOf(cfg)
        if Empty(tfont) then
            if b._zTimerCustom then
                b._zTimerCustom = nil
                if ns.HouseFont then ns.HouseFont(fs, TIMER_SIZE) end
            end
        elseif ns.ApplyFontSpec then
            b._zTimerCustom = true
            ns.ApplyFontSpec(fs, tfont, TimerFontDefaults())
        end
        if b._zTimerHolder then b._zTimerHolder:SetShown(cfg.showTimer ~= false) end
        b._zTimerKey = nil       -- repaint the colour on the next paint
    end

    local count = b.Count
    if count and count.ClearAllPoints and KitCountStock(cfg) then
        -- the kit: Blizzard's stack number, where and as Blizzard draws it
        -- (a sample has no Blizzard spot: the Classic template's, bottom
        -- right of the icon, 2 in)
        if b._zSample then
            count:ClearAllPoints()
            count:SetPoint("BOTTOMRIGHT", icon or b, "BOTTOMRIGHT", -2, 2)
        end
        if count.SetAlpha then count:SetAlpha(1) end
    elseif count and count.ClearAllPoints then
        local def = ns.AuraTextDefaults(cfg, "count", count._zAnchorDef)
        def.to = icon or b
        count._zAnchorDef = def
        ns.ApplyAnchor(count, AnchorOf(cfg, "count"), def, TextTo(b))
        if not count._zStock and count.GetFont then
            count._zStock = { count:GetFont() }
        end
        if Empty(cfg.countFont) then
            if count._zCustom and count._zStock and count._zStock[1] then
                count._zCustom = nil
                if ns.FollowFont then ns.FollowFont(count, count._zStock[2], count._zStock[3])
                else pcall(count.SetFont, count, count._zStock[1], count._zStock[2], count._zStock[3]) end
            end
        elseif ns.ApplyFontSpec and count._zStock then
            count._zCustom = true
            ns.ApplyFontSpec(count, cfg.countFont, { fallbackFace = count._zStock[1],
                size = count._zStock[2] or 12, outline = count._zStock[3] or "OUTLINE", shadow = false })
        end
        if type(cfg.countColor) == "table" then
            count:SetTextColor(ColorOr(cfg.countColor))
            count._zColored = true
        elseif count._zColored then
            count._zColored = nil
            count:SetTextColor(1, 1, 1, 1)
        end
        if count.SetAlpha then count:SetAlpha(cfg.showCount == false and 0 or 1) end
    end
end

local STATE_OF = { normal = "normal", orange = "warning", red = "urgent" }
ns.AURA_STATE_LIST = { { id = "normal", label = "Plenty of time" }, { id = "warning", label = "Running low" },
    { id = "urgent", label = "About to run out" } }
-- what the state editor shows with nothing saved: the colours above
function ns.AuraStateDefaults()
    local cfg = Look()
    local function C(c, key) local r, g, bl = ColorOr(c, "text", key) return { r = r, g = g, b = bl, a = 1 } end
    return { normal = { textColor = C(cfg.timerColor, "normal") }, warning = { textColor = C(cfg.warnColor, "orange") },
        urgent = { textColor = C(cfg.urgentColor, "red") } }
end

-- THE SWEEP (HD, ZacUI look): a Cooldown over the icon, inside the ring,
-- reversed so the part already gone darkens (a fresh buff is bright, one
-- running out goes dark), no edge, no flash, no numbers of its own.
-- Started once per aura (when the expiry it implies moves), never per tick.
local SWIPE_SHORT = 300
local function Secret(v) return issecretvalue ~= nil and issecretvalue(v) end
local function AuraTimes(b)
    -- a preview sample's made-up length
    if b._zFakeDur then return b._zFakeDur, GetTime() + (tonumber(b.timeLeft) or 0) end
    -- 1.15.9's pooled button: Blizzard's own info table (read, never written)
    local info = b.buttonInfo
    if type(info) == "table" then return info.duration, info.expirationTime end
    -- the named buttons: the slot's aura, asked once per new aura
    local idx, filter = b._zAuraIndex, b._zAuraFilter
    if not (idx and filter) then return nil end
    local GetData = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if GetData then
        local ok, a = pcall(GetData, "player", idx, filter)
        if ok and type(a) == "table" then return a.duration, a.expirationTime end
    elseif UnitAura then
        local _, _, _, _, dur, exp = UnitAura("player", idx, filter)
        return dur, exp
    end
end
local function PaintSwipe(b, cfg, t)
    local cd = b._zSwipe
    if not cd then return end
    local mode = cfg.swipe or "short"
    if mode == "off" or t == nil or Secret(t) or not IsHD() then
        if b._zSwOn then b._zSwOn = nil cd:Hide() end
        b._zSwExp = nil
        return
    end
    local exp = GetTime() + t
    -- the same aura ticking down: nothing to do
    if b._zSwExp and math.abs(exp - b._zSwExp) < 0.5 then return end
    b._zSwExp = exp
    local dur, e = AuraTimes(b)
    if type(dur) == "number" and type(e) == "number" and not Secret(dur) and not Secret(e)
        and dur > 0 and (mode == "all" or dur <= SWIPE_SHORT) then
        cd:SetCooldown(e - dur, dur)
        cd:Show()
        b._zSwOn = true
    elseif b._zSwOn then
        b._zSwOn = nil
        cd:Hide()
    end
end
local function AddSwipe(b)
    if b._zSwipe or not IsHD() then return end
    local icon = b._zIconRef or b.Icon or b.icon
    if not icon then return end
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    if not (ok and cd) then return end
    -- inside the ring, so a debuff's coloured ring is never darkened
    local one = (ns.Pixel and ns.Pixel.One(b)) or 1
    cd:SetPoint("TOPLEFT", icon, "TOPLEFT", one, -one)
    cd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -one, one)
    cd:SetFrameLevel(b:GetFrameLevel() + 1)
    if cd.SetReverse then cd:SetReverse(true) end
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.6) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    -- cooldown-text addons (OmniCC and the like): our own time is on it
    cd.noCooldownCount = true
    cd:Hide()
    b._zSwipe = cd
end

local function PaintTimer(b, cfg)
    local fs, d = b._zTimer, b.Duration
    if not (fs and d) then return end
    cfg = cfg or Look()
    local text, key = "", "normal"
    local t
    local kit = Kit()
    if d:IsShown() then
        t = b.timeLeft
        if type(t) == "number" and t > 0 then
            -- the kit: Blizzard's own words for the time (its duration
            -- text, which it keeps writing under ours); a sample's own
            if kit and not b._zSample then
                text = d:GetText() or ""
            else
                text = FormatTime(t)
            end
            if t < (tonumber(cfg.urgentAt) or 10) then key = "red"
            elseif t < (tonumber(cfg.warnAt) or 60) then key = "orange" end
        else
            text = d:GetText() or ""
            t = nil
        end
    end
    if Secret(text) then
        -- (a hidden value: handed on as it is, never compared)
        b._zTimerText = nil
        fs:SetText(text)
    elseif text ~= b._zTimerText then
        b._zTimerText = text
        fs:SetText(text)
    end
    if key ~= b._zTimerKey then
        b._zTimerKey = key
        local which = (key == "red" and cfg.urgentColor) or (key == "orange" and cfg.warnColor)
            or (key == "normal" and cfg.timerColor) or nil
        local r, g, bl = ColorOr(which, "text", key)
        if kit and not which then
            -- Blizzard's colours: gold, white under a minute
            -- (BUFF_DURATION_WARNING_TIME in the stock buff frame)
            local c = (key == "normal") and (NORMAL_FONT_COLOR or { r = 1, g = 0.82, b = 0 })
                or (HIGHLIGHT_FONT_COLOR or { r = 1, g = 1, b = 1 })
            r, g, bl = c.r, c.g, c.b
        end
        fs:SetTextColor(r, g, bl, 1)
        -- the time-left states' own looks (auraStyle.states.<normal|
        -- warning|urgent>: text colour, icon tint) over the colours above;
        -- nothing saved = not one extra call
        local st = cfg.states
        if type(st) ~= "table" or next(st) == nil then st = nil end
        if st or b._zSt then
            local s = st and st[STATE_OF[key]]
            if type(s) ~= "table" then s = nil end
            b._zSt = s and true or nil
            if s and s.textColor then fs:SetTextColor(ns.ColorOf(s.textColor)) end
            local icon = b.Icon or b.icon
            if icon and icon.SetVertexColor then
                if s and s.color then
                    icon:SetVertexColor(ns.ColorOf(s.color))
                    b._zStIcon = true
                elseif b._zStIcon then
                    b._zStIcon = nil
                    icon:SetVertexColor(1, 1, 1, 1)
                end
            end
        end
    end
    -- RUNNING OUT: the timer's own holder plays the alert animation (a
    -- frame of ours, so nothing Blizzard lays out is moved). Off unless
    -- an animation is chosen on the Buffs page.
    local holder = b._zTimerHolder
    local spec = cfg.alertAnim
    if holder and ns.Motion then
        local want = type(spec) == "table" and spec.style and spec.style ~= "none"
            and t ~= nil and t < (tonumber(cfg.urgentAt) or 10)
        -- (again once a one-shot style has finished, or a recycled
        -- button's loop was ended by it hiding: it repeats until refreshed)
        if want and not (b._zAlerting and ns.Motion.IsPlaying(holder)) then
            b._zAlerting = true
            local s = ns.CopySetting and ns.CopySetting(spec) or spec
            if ns.Motion.LOOPS and ns.Motion.LOOPS[s.style] and s.loop == nil then s.loop = true end
            ns.Motion.Play(holder, s, "update")
        elseif not want and b._zAlerting then
            b._zAlerting = nil
            ns.Motion.Stop(holder)
        end
    end
    PaintSwipe(b, cfg, t)
end

-- Our time text on a button, over Blizzard's (which is faded out: it is
-- re-anchored and re-fonted from the button's own OnUpdate, every frame).
local function AddTimer(b)
    if b._zTimer or not (b.Duration and (b.Icon or b._zIconRef)) then return false end
    local UIF = ns.UI
    if not (UIF and UIF.Font) then return false end
    local holder = CreateFrame("Frame", nil, b)
    holder:SetAllPoints(b)
    holder:SetFrameLevel(b:GetFrameLevel() + 3)
    local fs = UIF.Font(holder, TIMER_SIZE, { justify = "CENTER" })
    fs:SetPoint("CENTER", b._zIconRef or b.Icon, "BOTTOM", 0, 1)
    b._zTimer, b._zTimerHolder = fs, holder
    b.Duration:SetAlpha(0)
    -- the HD sweep, under the time (the holder is two levels above it)
    AddSwipe(b)
    if b.Count and b.Count.ClearAllPoints and not KitCountStock(Look()) then
        b.Count:ClearAllPoints()
        b.Count:SetPoint("TOPRIGHT", b._zIconRef or b.Icon, "TOPRIGHT", -1, -2)
    end
    return true
end

-- Restride runs after every layout Blizzard does, i.e. per player
-- UNIT_AURA: the enabled list is one scratch table refilled each time,
-- and the grid layout object (which never changes for the same stride,
-- padding and growth) is built once per such combination.
local enabledScratch = {}
local layoutCache = {}

-- Icon size on one pooled button: the button and its icon. Only touched
-- once the size is not Blizzard's 30 (or was not, earlier), so a default
-- setup never writes the icon at all.
local function SizeButton(a, w, h, s)
    if a.SetSize then a:SetSize(w, h) end
    local icon = a.Icon or a.icon
    if icon and icon.SetSize and (s ~= 30 or a._zIconSized) then
        a._zIconSized = s ~= 30 or nil
        icon:SetSize(s, s)
        -- the kit: Blizzard's own border grows with the icon
        if Kit() then KitFitBorder(a, s) end
    end
end

-- under the kit with Blizzard's size, gap and growth: Blizzard's own rows
local function KitStockGrid(cfg)
    if not Kit() then return false end
    return KitSize(cfg) == 30 and KitSpacing(cfg) < 0
        and (cfg.growX or "auto") == "auto" and (cfg.growY or "auto") == "auto"
end

local function Restride(container)
    local info = container.currentGridLayoutInfo
    local auras = container._zuiAuras
    local GLU = _G.GridLayoutUtil
    if not (info and info.anchor and auras and GLU and GLU.ApplyGridLayout) then
        return
    end

    local n = ZacUIDB and ZacUIDB.buffsPerRow
    local frame = container:GetParent()
    -- the ZacUI look with no row count of its own (match pass): the
    -- reference UI's 11 buffs and 8 debuffs a row
    if (not n or n < 1) and IsHD() then n = (frame and frame == _G.DebuffFrame) and 8 or 11 end
    local cfg = Look()

    -- What Blizzard actually anchors. It drops the disabled buttons when
    -- the frame asks it to; so do we, or a hidden button occupies a cell.
    local enabled = enabledScratch
    for i = #enabled, 1, -1 do enabled[i] = nil end
    for _, a in ipairs(auras) do
        if a.hasValidInfo or a.isExample or a.isAuraAnchor then
            enabled[#enabled + 1] = a
        end
    end
    local toAnchor = (frame and frame.doNotAnchorDisabledFrames) and enabled or auras

    local horizontal = info.isHorizontal
    local compact = edgeTimers and horizontal and not KitStockGrid(cfg)

    if (not n or n < 1) and not compact then
        if info.layout then
            pcall(GLU.ApplyGridLayout, toAnchor, info.anchor, info.layout)
        end
        return
    end
    -- No row count of our own: Blizzard's (Edit Mode's) stride, re-laid
    -- out only so the shorter rows can close up.
    if not n or n < 1 then n = info.iconStride or 8 end
    local cw, ch = CellSize(cfg)
    if compact then
        for _, a in ipairs(auras) do SizeButton(a, cw, ch, cw) end
    end

    local pad, xMul, yMul
    if compact then
        pad, xMul, yMul = GridOf(cfg, info)
    else
        pad = info.iconPadding or 0
        xMul = info.addIconsToRight and 1 or -1
        yMul = info.addIconsToTop and 1 or -1
    end
    local make = horizontal and GLU.CreateStandardGridLayout
                            or GLU.CreateVerticalGridLayout
    if not make then return end

    local layout
    local slot = layoutCache[make]
    if not slot then slot = {} layoutCache[make] = slot end
    local cached = slot[n]
    if cached and cached.pad == pad and cached.xMul == xMul and cached.yMul == yMul then
        layout = cached.layout
    else
        local ok, made = pcall(make, n, pad, pad, xMul, yMul)
        if not ok or not made then return end
        layout = made
        slot[n] = { layout = made, pad = pad, xMul = xMul, yMul = yMul }
    end

    -- Same figures UpdateGridLayout uses, so the frame's own size follows
    -- the row count and the debuff frame anchored beneath keeps its gap.
    if frame and frame.UpdateSize then
        local w, h = 30, 40
        if compact then w, h = cw, ch end
        if not horizontal then w, h = 60, 30 end
        pcall(frame.UpdateSize, frame, w, h, n, pad, container.iconScale or 1,
              horizontal, #enabled)
    end

    pcall(GLU.ApplyGridLayout, toAnchor, info.anchor, layout)
end

local function HookContainer(container)
    if not container or container._zuiStrideHooked then return end
    if type(container.UpdateGridLayout) ~= "function" then return end
    container._zuiStrideHooked = true
    -- Post-hook on the instance. Runs after every layout Blizzard does,
    -- with the same list it laid out - the only place that list is handed
    -- to anyone. Kept on our own key so the slider can re-run the layout
    -- later without asking Blizzard to.
    hooksecurefunc(container, "UpdateGridLayout", function(self, auras)
        self._zuiAuras = auras
        Restride(self)
    end)
end

-- The list the client laid out BEFORE the hook went on. The pooled frame
-- (1.15 Era, TBC Anniversary, Forever: AuraFrame_OnLoad) makes its buttons
-- into frame.auraFrames and lays them out once, before any addon loads;
-- after that the BUFF frame only fills and shows those buttons on an aura
-- change and lays out again only on a consolidation or Edit Mode change.
-- So on a client where neither comes after login the hook never saw a list,
-- and the buff buttons were never styled or re-laid out (Zac on TBC
-- Anniversary, 2026-11-08: Blizzard's stock buff icons under ZacUI's look).
-- Same buttons, same list Blizzard passes - known by what the frame has,
-- not by which client this is.
local function SeedAuras(frame, container)
    if container._zuiAuras == nil and type(frame.auraFrames) == "table" then
        container._zuiAuras = frame.auraFrames
    end
end

local function ApplyAuraStride()
    for _, frame in ipairs({ _G.BuffFrame, _G.DebuffFrame }) do
        local container = frame and frame.AuraContainer
        if container then
            HookContainer(container)
            SeedAuras(frame, container)
            Restride(container)
        end
    end
end
ns.ApplyAuraStride = ApplyAuraStride

-- Set by Modules.auras: restyles every styled button now (a settings
-- change), rather than on the next sweep.
local RestyleAll

-- ============================================================
-- SAMPLES (the Buffs page's preview)
-- ============================================================
-- A button shaped like Blizzard's pooled aura button - Icon, Count and a
-- Duration it fades out - dressed by the same functions as the real ones.
-- Plain frames, parented to the preview canvas: no events, no tooltips,
-- nothing secure, never in the sweep's lists.
local function NewSample(parent, kind)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(30, 36)
    b._zKind = kind or "buff"
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOP", b, "TOP", 0, 0)
    icon:SetSize(30, 30)
    if SharpenIcon then SharpenIcon(icon) end
    b.Icon = icon
    local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    if count.GetFont and not count:GetFont() then
        pcall(count.SetFont, count, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    end
    b.Count = count
    local dur = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.Duration = dur
    b._zSample = true
    if Kit() then
        -- the kit: the Classic template's border art (PaintKitSample)
        local kb = b:CreateTexture(nil, "OVERLAY")
        kb._zui_own = true
        kb:Hide()
        b._zKitBorder = kb
    else
        EdgeBorder(b, icon)
    end
    AddTimer(b)
    -- the pick hook: a click on a sample's text opens its placement
    if ns.TagElement then
        if b._zTimer then ns.TagElement(b._zTimer, "buffs.timer") end
        ns.TagElement(b, "buffs.icon")
        ns.TagElement(count, "buffs.count")
    end
    return b
end

-- One sample's fake aura: icon, stacks, seconds left (nil = no timer),
-- and a dispel tint for debuffs.
local function FillSample(b, aura)
    b.Icon:SetTexture(aura.icon)
    if b.Count.SetText then b.Count:SetText((aura.count and aura.count > 1) and tostring(aura.count) or "") end
    b.timeLeft = aura.left
    if aura.left then b.Duration:Show() b.Duration:SetText("x") else b.Duration:Hide() end
    -- the sweep's made-up length: short auras sweep, long ones do not
    b._zFakeDur = aura.dur or ((aura.left and aura.left <= SWIPE_SHORT) and aura.left * 2) or 3600
    b._zSwExp = nil
    b._zTint = aura.tint
end

-- Where sample i (0-based) of n sits, the same arithmetic as the real
-- grid: n per row, the spacing and growth from the settings (Blizzard's
-- buffs grow left and down from the top right).
local function SampleOffset(i, perRow, cfg)
    local cw, ch = CellSize(cfg)
    local pad, xMul, yMul = GridOf(cfg, { iconPadding = 5, addIconsToRight = false, addIconsToTop = false })
    local col = i % perRow
    local row = math.floor(i / perRow)
    return xMul * col * (cw + pad), yMul * row * (ch + pad), cw, ch, xMul, yMul
end

ns.BuffLook = {
    DEFAULTS = LOOK,
    Cfg = Look,
    CellSize = CellSize,
    Grid = GridOf,
    Style = StyleButton,
    PaintTimer = PaintTimer,
    PaintBorder = PaintBorder,
    NewSample = NewSample,
    FillSample = FillSample,
    SampleOffset = SampleOffset,
    TimerDefaults = TimerFontDefaults,
    -- a setting changed: restyle and re-lay out the real buttons now
    Changed = function()
        styleVer = styleVer + 1
        if RestyleAll then RestyleAll() end
        ApplyAuraStride()
    end,
}

Modules.auras = function()
    -- Blizzard relayouts the container whenever auras change, which would
    -- undo the stride, so it is re-applied after each of those passes
    -- rather than set once at login.
    -- The stride hooks the container's own UpdateGridLayout now, so it
    -- runs after exactly the layouts it needs to correct and no others.
    -- The UpdateAuraButtons hook and the UIParent_UpdateTopFramePositions
    -- hook that used to drive it are gone with the old field write: the
    -- consolidation cvar has its own watcher above, and re-asserting it
    -- from inside Blizzard's layout pass was one more insecure execution
    -- for no benefit.
    if not ZUI._auraStrideHooked then
        ZUI._auraStrideHooked = true
        ApplyAuraExpand()
        ApplyAuraStride()
    end

    -- every button this file has styled, for a restyle on a settings change
    local styled = setmetatable({}, { __mode = "k" })

    -- CLASSIC named path: full style is SAFE here and re-asserted inside
    -- every Blizzard paint - the crop runs after Blizzard sets the icon,
    -- each update, on non-masked named textures; it cannot blank what
    -- Blizzard just drew. (The invisibility bug lived exclusively in the
    -- modern POOLED path, which stays strictly additive below.)
    if type(AuraButton_Update) == "function" then
        -- Blizzard calls this for all 32 buff + 16 debuff slots on every
        -- player UNIT_AURA. The three name lookups happen once per
        -- button (kept on the button), and the crop and sharpen once -
        -- Blizzard's update never touches the texture coordinates. Only
        -- the debuff border alpha and tint are re-asserted per call, since
        -- Blizzard rewrites those each time.
        local byName = {}
        hooksecurefunc("AuraButton_Update", function(btnName, index, filter)
            local b = byName[index] and byName[index][btnName]
            if b == nil then
                local name = btnName .. index
                b = _G[name] or false
                byName[index] = byName[index] or {}
                byName[index][btnName] = b
                if b then
                    b._zIconRef = _G[name .. "Icon"]
                    b._zBlizzBorder = _G[name .. "Border"]
                end
            end
            if not b then return end
            -- (which aura the slot shows: the sweep asks it once per aura)
            b._zAuraIndex, b._zAuraFilter = index, filter
            if not b._zStyled then
                b._zStyled = true
                local icon = b._zIconRef
                if icon and SharpenIcon then SharpenIcon(icon) end
                EdgeBorder(b)
                styled[b] = true
            end
            if b._zStyleVer ~= styleVer then
                StyleButton(b)
                -- named buttons are their icon: size the button itself
                local s = CellSize()
                if b.SetSize and (s ~= 30 or b._zIconSized) then
                    b._zIconSized = s ~= 30 or nil
                    b:SetSize(s, s)
                    if Kit() then KitFitBorder(b, s) end
                end
            end
            local blizz = b._zBlizzBorder
            -- (the kit: Blizzard's own dispel-coloured art is the border)
            if filter == "HARMFUL" and blizz and not Kit() then
                blizz:SetAlpha(0)
                TintFrom(b, blizz)
            end
        end)
    end
    -- WEAPON ENCHANTS (TempEnchant1/2): Blizzard's swirl border is
    -- baked-color ART - its VERTEX color is plain white, so TintFrom
    -- here copied white onto our pixel border (the "white border on
    -- weapon enchants" bug). Never tint from art. These are classic
    -- named statics, the same safety class as the HARMFUL path above:
    -- hide Blizzard's border art (one-time SetAlpha 0 - nothing ever
    -- re-shows it), crop the icon to match the hooked buff path, and
    -- leave our border house black (or the enchant colour, if one is set).
    for i = 1, 2 do
        local b = _G["TempEnchant" .. i]
        if b then
            b._zKind = "enchant"
            EdgeBorder(b)
            local blizz = _G["TempEnchant" .. i .. "Border"]
            b._zBlizzBorder = blizz
            -- (the kit: Blizzard's purple ring stays)
            if blizz and blizz.SetAlpha and not Kit() then blizz:SetAlpha(0) end
            local icon = _G["TempEnchant" .. i .. "Icon"]
            b._zIconRef = icon
            if icon and SharpenIcon then SharpenIcon(icon) end
            StyleButton(b)
            styled[b] = true
        end
    end

    -- ============================================================
    -- THE TIME LEFT, ON THE ICON'S BOTTOM EDGE
    -- ============================================================
    -- Blizzard's own duration text hangs in a strip under each icon in a
    -- stock gold font, and Blizzard re-anchors and re-fonts it from the
    -- button's OnUpdate, every frame - moving it would be a fight lost
    -- sixty times a second. So it is faded out and each button gets a
    -- text of ours, centred on the icon's bottom border in the ZacUI font,
    -- that reads the time from the button. One shared 0.2 s ticker drives
    -- every one of them (nothing per frame), and it skips buttons that are
    -- not on screen. The stack count moves to the top-right corner, out of
    -- the timer's way.
    local timed = setmetatable({}, { __mode = "k" })
    local ticker

    local function Tick()
        local cfg = Look()
        for b in pairs(timed) do
            if b:IsVisible() then PaintTimer(b, cfg) end
        end
    end
    -- the ticker runs only while the buff or debuff frame is on screen
    local function StartTicker()
        if ticker then return end
        local bf, df = _G.BuffFrame, _G.DebuffFrame
        if not ((bf and bf:IsVisible()) or (df and df:IsVisible())) then return end
        ticker = C_Timer.NewTicker(0.2, function()
            if not ((bf and bf:IsVisible()) or (df and df:IsVisible())) then
                ticker:Cancel()
                ticker = nil
                return
            end
            Tick()
        end)
        if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "auras.timers") end
    end
    for _, f in ipairs({ _G.BuffFrame, _G.DebuffFrame }) do
        if f and f.HookScript then f:HookScript("OnShow", StartTicker) end
    end

    local function SetupTimer(b)
        if not AddTimer(b) then return end
        timed[b] = true
        StyleButton(b)
        PaintTimer(b)
        StartTicker()
    end

    -- Modern pooled path: border-add only, on real aura events plus one
    -- settled pass after entering world.
    -- One pooled button, styled. The crop, sharpen and border are one-time
    -- (fenced on the button); the Blizzard border alpha is re-asserted
    -- every sweep because aura updates re-show it. SetupTimer guards
    -- itself. Defined once, not once per child per sweep.
    local function AddTo(b)
        if not (b and b.IsObjectType and b:IsObjectType("Button")) then return end
        local icon = b.Icon or b.icon
        if not b._zStyled then
            b._zStyled = true
            EdgeBorder(b, icon)
            if icon and SharpenIcon then SharpenIcon(icon) end
            styled[b] = true
            StyleButton(b)
        end
        local blizz = b.Border or b.border or b.DebuffBorder or b.TempEnchantBorder
        TintFrom(b, blizz)
        -- 1.15.9 pooled buttons carry their own bright border art. Keyed
        -- SetAlpha(0) ONLY - never SetTexture(nil), never a blanket strip
        -- (the pooled blanking law). The kit keeps Blizzard's art.
        if blizz and blizz.SetAlpha and not Kit() then blizz:SetAlpha(0) end
        SetupTimer(b)
        if b._zStyleVer ~= styleVer then StyleButton(b) end
    end
    -- The buttons Blizzard last laid out, from the list its own layout
    -- pass hands to UpdateGridLayout (kept on the container by the hook
    -- above) - each button once, and no child lists built per sweep.
    local function SweepModernAuras()
        for _, frame in ipairs({ _G.BuffFrame, _G.DebuffFrame }) do
            local container = frame and frame.AuraContainer
            if container then SeedAuras(frame, container) end
            local list = container and container._zuiAuras
            if list then
                for i = 1, #list do AddTo(list[i]) end
            end
        end
        if next(timed) then StartTicker() end
    end
    edgeTimers = true
    ApplyAuraStride()

    RestyleAll = function()
        local cfg = Look()
        for b in pairs(styled) do StyleButton(b, cfg) end
        for b in pairs(timed) do PaintTimer(b, cfg) end
    end
    -- the Buffs page: every change restyles now, once per frame at most
    if ns.OnSettingsChanged and ns.Coalesce and not ZUI._auraLookListen then
        ZUI._auraLookListen = true
        local soon = ns.Coalesce(function()
            local key = ns.ConfigState and ns.ConfigState().selected
            if key == "buffs" then ns.BuffLook.Changed() end
        end)
        ns.OnSettingsChanged(soon)
    end

    local sweepPending = false
    local ev = CreateFrame("Frame")
    if ev.RegisterUnitEvent then
        ev:RegisterUnitEvent("UNIT_AURA", "player")
    else
        ev:RegisterEvent("UNIT_AURA")
    end
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(3, SweepModernAuras)
            return
        end
        if unit and unit ~= "player" then return end
        if sweepPending then return end
        sweepPending = true
        -- a quarter second: in a raid UNIT_AURA on the player comes
        -- several times a second, and the 0.2 s timer ticker already
        -- keeps the durations moving in between
        C_Timer.After(0.25, function()
            sweepPending = false
            SweepModernAuras()
        end)
    end)
    -- 1.15.9: Edit Mode's aura settings (icon size, per-row limits,
    -- direction) rebuild the pooled buttons wholesale. One settled sweep
    -- after each Edit Mode exit re-adds borders to the new pool. Same
    -- additive-only sweep, same safety class. Unique owner table - the
    -- registry keys callbacks by (event, owner), and the minimap module
    -- registers this same event.
    if EventRegistry and EventRegistry.RegisterCallback then
        pcall(EventRegistry.RegisterCallback, EventRegistry,
            "EditMode.Exit", function()
                C_Timer.After(0.2, SweepModernAuras)
            end, { zacui = "auras" })
    end
end

-- ADDON LIST ("buttons in the addon list don't match"). 11509 rebuilt
-- this window on the retail template: ButtonFrameTemplate shell, KEYED
-- bottom buttons (the AddonList*Button globals are gone), a search box,
-- a WowStyle1 dropdown and a pooled ScrollBox. Both generations handled;
-- the modern dropdown and the per-row minimal checkboxes are already
-- flat-modern and stay stock on purpose.
