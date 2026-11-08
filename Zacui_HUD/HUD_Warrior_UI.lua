-- HUD_Warrior_UI - the Warrior HUD settings page: General | Grid icons |
-- Buff row | Look | Text | Animation | Position | Advanced, a test toggle
-- that forces every enabled icon visible on screen, and the HUD drawn in
-- the preview dock (built by the HUD's own constructors, placed where the
-- pieces sit on screen, from made-up cooldowns, buffs, rage and swings).
-- Part of ZacUI; load order is set by the TOC.
local ADDON_NAME = ...
-- Zacui_HUD is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
if not ns.HUD then return end   -- (the part stands down on this game version: HUD_Shared, Core_Flavor)
local HUD = ns.HUD
local UI = ns.UI
local Print = ns.Print

local WH = ns.WarriorHUD

local M, F = UI.M, UI.F
local SLIDER_W = 200          -- two-column layout; a page-wide slider
                              -- would run off the card
local COL2_X = 290            -- right slider column

-- Card width at build time. The card is anchored to both sides of the
-- content pane so its own width is not resolved yet, but the pane's is.
local function CardW(L)
    local w = L.parent and L.parent.GetWidth and L.parent:GetWidth()
    if not w or w < 200 then return 534 end
    return w - 2 * M.MARGIN
end

-- Every sizing change here has to re-run the HUD layout (the preview
-- follows by itself: every control raises the change signal).
local function AfterSizing()
    if WH.Display and WH.Display.InvalidateLayout then
        WH.Display:InvalidateLayout()
    end
end

-- Two sizing sliders side by side (left / right column). Each spec is
-- { label, min, max, cur, onChange }; right may be nil.
local function SliderPair(L, left, right)
    local card = L.current
    local twoCols = CardW(L) >= COL2_X + SLIDER_W + 10
    local function make(x, spec)
        local w = UI.Slider(card, {
            width = SLIDER_W, min = spec[2], max = spec[3], step = 1,
            value = spec[4], label = spec[1], format = spec[6],
            onChange = function(v)
                v = math.floor(v + 0.5)
                spec[5](v)
                AfterSizing()
            end,
        })
        w:SetPoint("TOPLEFT", card, "TOPLEFT", x, card._y)
        -- (a row as tall as its slider: a bigger font makes it taller)
        return math.max(M.BLOCK, (w:GetHeight() or 0) + 8)
    end
    local h = make(M.CONTROL_X, left)
    if right then
        if not twoCols then card._y = card._y - h h = 0 end
        h = math.max(h, make(twoCols and COL2_X or M.CONTROL_X, right))
    end
    card._y = card._y - h
end

-- A checkbox row; indent shifts it right of the usual control column.
local function Check(L, label, checked, onSet, indent)
    if not indent then return HUD.Check(L, label, checked, onSet) end
    local w = UI.Checkbox(L.current, label, checked and true or false, function(v)
        onSet(v and true or false)
    end)
    L:Row(w, M.ROW, M.CONTROL_X + indent)
    return w
end

local function PreviewCheck(L)
    return Check(L, "Show every enabled icon on screen (test)",
        WH.Display and WH.Display.preview or false,
        function(v)
            if WH.Display then WH.Display:SetPreview(v) end
        end)
end

local STANCE_ITEMS = {
    { text = "Any stance", value = 0 },
    { text = "Battle", value = 1 },
    { text = "Defensive", value = 2 },
    { text = "Berserker", value = 3 },
}
local STANCE_LABELS = { [0] = "Any stance", [1] = "Battle",
                        [2] = "Defensive", [3] = "Berserker" }
local KIND_ITEMS = {
    { text = "Cooldown", value = "cd" },
    { text = "Buff", value = "buff" },
}
local KIND_LABELS = { cd = "Cooldown", buff = "Buff" }

local function PotionItems()
    local items = { { text = "Automatic Icon", value = 1 } }
    for i = 2, 20 do
        local e = WH.POTION_DROPDOWN[i]
        if e then items[#items + 1] = { text = e.label, value = i } end
    end
    return items
end

local function PotionLabel(idx)
    if not idx or idx == 1 then return "Automatic Icon" end
    local e = WH.POTION_DROPDOWN[idx]
    return e and e.label or "Automatic Icon"
end

-- 3-column checkbox grid; hidden[key] = true removes, checkboxes show "shown".
-- (up to three across, as many as the longest label fits; L:Grid)
local function IconGrid(L, list, hidden)
    local card = L.current
    local boxes = {}
    for _, entry in ipairs(list) do
        boxes[#boxes + 1] = UI.Checkbox(card, entry.label, not hidden[entry.key], function(shown)
            hidden[entry.key] = (not shown) or nil
        end)
    end
    L:Grid(boxes, 3, M.ROW)
    card._y = card._y - 4
end

-- Where an element actually sits: the dragged position of record from
-- the mover registry when there is one, else the store's default offsets.
local function Pos(moverKey, store)
    local pos = HUD.MoverPos(moverKey)
    if pos and (pos.point == nil or pos.point == "CENTER") then
        return pos.x or 0, pos.y or 0
    end
    return store.x or 0, store.y or 0
end

-- ============================================================
-- THE PREVIEW DOCK'S SAMPLE
-- ============================================================
-- The HUD's pieces made by the Display's own constructors (MakeMainIcon,
-- MakeAuraIcon, MakeStanceIcon, MakeExecIcon, MakeRageBar, MakeSwingBars)
-- on plain anchors on the canvas, laid out by the HUD's own row layouts
-- and styled by its StyleIcon, each piece where it sits on screen
-- relative to the others. Fed made-up cooldowns, buffs, rage and swings;
-- its timers and swing bars move on one OnUpdate that only runs while
-- the canvas is on screen. Nothing here registers events or joins a mover.
local SAMPLE_PAD = 8

local PIECES = { "Main", "AuraRow", "Stance", "Execute", "RageBar", "Swing" }
local MOVER_OF = { Main = "whMainRow", AuraRow = "whAuraRow", Stance = "whStance",
    Execute = "whExecute", RageBar = "whRageBar", Swing = "whSwing" }

local function StoreOf(cfg, key)
    local r = cfg.resources
    if key == "Main" then return cfg.mainRow
    elseif key == "AuraRow" then return cfg.auraRow
    elseif key == "Stance" then return r.stance
    elseif key == "Execute" then return r.execute
    elseif key == "RageBar" then return r.rage end
    return r.swing
end

-- Which pieces the sample draws: the ones switched on, or every one of
-- them when nothing is (an empty preview shows nobody anything).
local function Shown(cfg)
    local r = cfg.resources
    local on = {
        Main = cfg.mainRow.enabled and true or false,
        AuraRow = cfg.auraRow.enabled and true or false,
        Stance = (r.enabled and r.stanceHud) and true or false,
        Execute = (r.enabled and r.executeHelper) and true or false,
        RageBar = (r.enabled and r.rageBar) and true or false,
        Swing = (r.enabled and r.swingTimer) and true or false,
    }
    for _, v in pairs(on) do
        if v then return on, false end
    end
    for k in pairs(on) do on[k] = true end
    return on, true
end

-- How big each piece is (scales included) and how far its box's centre
-- sits above its anchor: the grid grows down from its first row, the
-- swing bars stack up from the main-hand bar.
local function PieceSizes(cfg, nGrid)
    local out = {}
    local m = cfg.mainRow
    local s = m.scale or 1
    local rows = m.rows or {}
    local sp = m.spacing or 3
    -- the rows the grid's icons fill, the last taking whatever is left
    -- over (as W.LayoutMainRow lays them out)
    local wMax, span, left = 0, 0, nGrid or 0
    for i, rc in ipairs(rows) do
        if left <= 0 then break end
        local n = (i == #rows) and left or math.min(left, rc.limit or 8)
        left = left - n
        wMax = math.max(wMax, n * (rc.w or 26) + (n - 1) * sp)
        span = span + (rc.h or 26) + (i > 1 and sp or 0)
    end
    if wMax <= 0 then wMax, span = 8 * 26 + 7 * sp, 26 end
    local h1 = (rows[1] and rows[1].h or 26)
    out.Main = { w = wMax * s, h = span * s, dy = (h1 / 2 - span / 2) * s }
    local a = cfg.auraRow
    local as = a.scale or 1
    out.AuraRow = { w = (6 * (a.iconW or 30) + 5 * (a.spacing or 4)) * as,
        h = ((a.iconH or 30) + 8) * as, dy = -4 * as }
    local r = cfg.resources
    local ss = r.stance.scale or 1
    out.Stance = { w = (r.stance.w or 32) * ss, h = (r.stance.h or 34) * ss, dy = 0 }
    local es = r.execute.scale or 1
    out.Execute = { w = 40 * es, h = 38 * es, dy = 0 }
    out.RageBar = { w = r.rage.w or 229, h = r.rage.h or 4, dy = 0 }
    local mhH, ohH = WH.Display.SwingHeights(r.swing.h or 3)
    out.Swing = { w = r.swing.w or 229, h = mhH + 2 * ohH + 2, dy = ohH }
    return out
end

-- Where each piece sits on screen (its anchor, screen units): the dragged
-- position of record, else the store's default.
local function RealPos(cfg)
    local out = {}
    for _, key in ipairs(PIECES) do
        local x, y = Pos(MOVER_OF[key], StoreOf(cfg, key))
        out[key] = { x, y }
    end
    return out
end

-- The box the shown pieces cover at `pos`: centre and size.
local function PieceBox(on, sizes, pos)
    local minX, maxX, minY, maxY
    for _, key in ipairs(PIECES) do
        if on[key] then
            local sz, p = sizes[key], pos[key]
            local cx, cy = p[1], p[2] + sz.dy
            local l, rt, b, t = cx - sz.w / 2, cx + sz.w / 2, cy - sz.h / 2, cy + sz.h / 2
            minX = minX and math.min(minX, l) or l
            maxX = maxX and math.max(maxX, rt) or rt
            minY = minY and math.min(minY, b) or b
            maxY = maxY and math.max(maxY, t) or t
        end
    end
    if not minX then return 0, 0, 240, 120 end
    return (minX + maxX) / 2, (minY + maxY) / 2, maxX - minX, maxY - minY
end

-- Everything the sample's layout needs: which pieces, where (exactly
-- where they sit on screen relative to each other: the strip shows the
-- HUD at its real size and scales it down only when it does not fit),
-- and the box they cover.
-- how many icons the sample's grid draws (every one, when all are hidden)
local function GridCount(cfg)
    local D = WH.Display
    local tex = D and D.GetPreviewTextures and D:GetPreviewTextures(cfg)
    local n = tex and #(tex.gridDefs or {}) or 0
    if n == 0 and tex then
        local all = D:GetPreviewTextures(setmetatable({
            mainRow = setmetatable({ hidden = {} }, { __index = cfg.mainRow }),
        }, { __index = cfg }))
        n = all and #(all.gridDefs or {}) or 0
    end
    return n
end

local function SampleLayout(cfg)
    local on, fallback = Shown(cfg)
    local sizes = PieceSizes(cfg, GridCount(cfg))
    local pos = RealPos(cfg)
    local cx, cy, w, h = PieceBox(on, sizes, pos)
    return { on = on, pos = pos, cx = cx, cy = cy, w = w, h = h }
end

-- the canvas the dock is asked for: the pieces' box and a margin
local function SampleSize(cfg)
    local lay = SampleLayout(cfg)
    return math.max(120, math.floor(lay.w + 2 * SAMPLE_PAD)),
           math.max(50, math.floor(lay.h + 2 * SAMPLE_PAD))
end

-- THE BATTLE SHOUT SLOT'S STATES (Buff reminders > "Show it in the
-- warrior HUD's buff row instead"): what BR.HudState would say. Missing:
-- three of your party lack it; running low: 12 s left on someone; fine:
-- everyone has it (the In combat / Out of combat modes).
local SHOUT_LOW_SECS = 12
local function ShoutSample(st, mode, now)
    local sh = st.shout or {}
    st.shout = sh
    local tex = ns.BuffRem and ns.BuffRem.Data and ns.BuffRem.Data.BY_KEY and ns.BuffRem.Data.BY_KEY.battleshout
        and ns.BuffRem.Icon_ and ns.BuffRem.Icon_(ns.BuffRem.Data.BY_KEY.battleshout) or nil
    local selfOnly = ns.BuffRem and ns.BuffRem.Opt and ns.BuffRem.Opt("battleshout", "scope") == "self"
    sh.tex, sh.selfOnly = tex, selfOnly and true or false
    sh.missing = mode == "shoutMissing"
    sh.low = mode == "shoutLow"
    sh.count = sh.missing and 3 or 0
    -- the names beside it, when the reminder shows them
    local ic = ns.BuffRem and ns.BuffRem.Icon and ns.BuffRem.Icon()
    sh.names = (sh.missing and ic and ic.showMissingNames) and "Rowdy\nStabbs\nTankz" or nil
    if sh.low then
        if not (sh.lowAt and sh.lowAt > now) then sh.lowAt = now + SHOUT_LOW_SECS end
    else
        sh.lowAt = nil
    end
    return sh
end

local function BuildWarriorSample(canvas, P)
    local D = WH.Display
    local W = WH.Widgets
    local st = P.store
    st.anchors = {}
    for _, k in ipairs({ "Main", "AuraRow", "Stance", "Execute", "RageBar", "Swing" }) do
        st.anchors[k] = HUD.SampleAnchor(canvas, 26, 26)
    end
    st.grid, st.aura, st.gridList, st.auraList = {}, {}, {}, {}
    st.stance = D.MakeStanceIcon(st.anchors.Stance)
    st.exec = D.MakeExecIcon(st.anchors.Execute)
    st.rage = D.MakeRageBar(st.anchors.RageBar)
    st.mh, st.oh = D.MakeSwingBars(st.anchors.Swing)
    st.swMH = { start = 0, duration = 2.6 }
    st.swOH = { start = 0, duration = 1.8 }
    -- one driver: swing bars every frame, timer texts ten times a second
    local drive = CreateFrame("Frame", nil, canvas)
    drive._acc = 0
    drive:SetScript("OnUpdate", function(f, el)
        local now = GetTime()
        for _, pair in ipairs({ { st.mh, st.swMH }, { st.oh, st.swOH } }) do
            local bar, sw = pair[1], pair[2]
            if bar:IsShown() then
                local rem = sw.start + sw.duration - now
                if rem <= 0 then sw.start = now rem = sw.duration end
                local frac = rem / sw.duration
                bar.bar:SetValue(frac)
                if bar.UpdateSpark then bar:UpdateSpark(frac) end
            end
        end
        f._acc = f._acc + (el or 0)
        if f._acc < 0.1 then return end
        f._acc = 0
        for _, list in ipairs({ st.gridList, st.auraList }) do
            for _, icon in ipairs(list) do
                if icon.texts.p and icon._fakeEnd ~= nil then
                    local rem = icon._fakeEnd - now
                    icon:SetText("p", rem > 0 and W.FormatTime(rem, 0) or "")
                end
                -- the Battle Shout slot running low: its red seconds count
                -- down (and start over at the bottom)
                local sh = icon._shoutSample
                if sh and sh.lowAt then
                    if sh.lowAt - now < 0 then sh.lowAt = now + SHOUT_LOW_SECS end
                    D.FillShoutRem(icon, sh, now)
                end
            end
        end
    end)
end

local function UpdateWarriorSample(canvas, P)
    local D = WH.Display
    local W = WH.Widgets
    local cfg = WH.Store()
    local st = P.store
    if not (cfg and D and st.anchors) then return end
    HUD.CheckLook()
    local combat = (P.mode or "combat") ~= "ready"
    local now = GetTime()
    local C = D.Colors()
    local r = cfg.resources
    local lay = SampleLayout(cfg)
    local show = lay.on
    st.layout = lay
    -- the canvas follows the layout (the strip scales it)
    if P.Resize then P.Resize(SampleSize(cfg)) end
    local function place(key, scale)
        local p = lay.pos[key]
        local a = st.anchors[key]
        a:SetScale(scale or 1)
        HUD.PlaceSample(a, canvas, p[1] - lay.cx, p[2] - lay.cy)
    end
    place("Main", cfg.mainRow.scale)
    place("AuraRow", cfg.auraRow.scale)
    place("Stance", r.stance.scale)
    place("Execute", r.execute.scale)
    place("RageBar")
    place("Swing")

    local tex = D:GetPreviewTextures(cfg) or { grid = {}, buffs = {}, gridDefs = {}, buffDefs = {} }
    -- every icon hidden: the sample shows the usual set rather than nothing
    if #(tex.gridDefs or {}) == 0 or #(tex.buffDefs or {}) == 0 then
        local all = D:GetPreviewTextures(setmetatable({
            mainRow = setmetatable({ hidden = {} }, { __index = cfg.mainRow }),
            auraRow = setmetatable({ hidden = {} }, { __index = cfg.auraRow }),
        }, { __index = cfg }))
        if all then
            if #(tex.gridDefs or {}) == 0 then tex.grid, tex.gridDefs = all.grid, all.gridDefs end
            if #(tex.buffDefs or {}) == 0 then tex.buffs, tex.buffDefs = all.buffs, all.buffDefs end
        end
    end

    -- the cooldown grid: a few on cooldown, one short of rage, one out of
    -- range, Whirlwind with a pack in reach, the consumables with counts
    local list, seen = st.gridList, {}
    wipe(list)
    if show.Main then
        local n = 0
        for i, def in ipairs(tex.gridDefs or {}) do
            local icon = st.grid[def.key]
            if not icon or icon.def.kind ~= def.kind then
                if icon then icon:Hide() end
                icon = D.MakeMainIcon(st.anchors.Main, def)
                st.grid[def.key] = icon
            end
            icon.def = def
            seen[icon] = true
            icon:SetIconTexture(tex.grid[i])
            D.StyleIcon(icon, cfg)
            icon:SetIconColor(1, 1, 1, 1)
            for gk in pairs(icon.glows) do icon:SetGlow(gk, false) end
            icon._fakeEnd = nil
            if def.kind == "spell" or def.kind == "customBuff" then
                n = n + 1
                local onCd = combat and n % 3 == 2
                icon:SetSwipe(onCd and (now - 5) or 0, onCd and (12 + 4 * n) or 0)
                icon._fakeEnd = onCd and (now - 5 + 12 + 4 * n) or 0
                local desat = onCd or (combat and n == 4)
                if combat and n == 5 then
                    icon:SetIconColor(C.oor[1], C.oor[2], C.oor[3], 1)
                    desat = true
                end
                icon:SetDesat(desat)
                if icon.texts.mobs then
                    icon:SetText("mobs", combat and "4" or "")
                    icon:SetGlow("mobs", combat and not onCd)
                end
            else
                local potCd = combat and def.kind == "itemPotion"
                icon:SetSwipe(potCd and (now - 30) or 0, potCd and 120 or 0)
                icon._fakeEnd = potCd and (now + 90) or 0
                icon:SetDesat(potCd)
                if icon.texts.count then icon:SetText("count", def.kind == "itemPotion" and "5" or "3") end
            end
            icon:SetText("p", "")
            list[#list + 1] = icon
            W.SetShownAnimated(icon, true)
        end
    end
    for _, icon in pairs(st.grid) do if not seen[icon] then icon:Hide() end end
    W.LayoutMainRow(st.anchors.Main, list, cfg.mainRow.rows, cfg.mainRow.spacing)

    -- the active buff row: a handful up with timers (one with stacks)
    local alist, aseen = st.auraList, {}
    wipe(alist)
    if show.AuraRow then
        local want = combat and 7 or 2
        for i, def in ipairs(tex.buffDefs or {}) do
            if #alist >= want then break end
            local icon = st.aura[def.key]
            if not icon or icon.def.kind ~= def.kind then
                if icon then icon:Hide() end
                icon = D.MakeAuraIcon(st.anchors.AuraRow, def)
                st.aura[def.key] = icon
            end
            icon.def = def
            aseen[icon] = true
            icon:SetIconTexture(tex.buffs[i])
            D.StyleIcon(icon, cfg)
            if def.kind == "shoutRem" then
                -- the Battle Shout reminder's slot (docked here from the
                -- Buff reminders page), in the mode's state, filled by the
                -- live row's own D.FillShoutRem
                local sh = ShoutSample(st, P.mode, now)
                icon._shoutSample = sh
                icon._fakeEnd = nil
                if icon.ClearSwipe then icon:ClearSwipe() end
                D.FillShoutRem(icon, sh, now)
                alist[#alist + 1] = icon
                W.SetShownAnimated(icon, true)
            else
            icon._shoutSample = nil
            local k = #alist + 1
            local dur = 20 + 5 * k
            icon:SetSwipe(now - 4 * k, dur)
            icon._fakeEnd = icon.texts.p and (now - 4 * k + dur) or nil
            if icon.texts.s then icon:SetText("s", k == 2 and "3" or "") end
            if icon.glows.proc then icon:SetGlow("proc", combat) end
            alist[#alist + 1] = icon
            W.SetShownAnimated(icon, true)
            end
        end
    end
    for _, icon in pairs(st.aura) do if not aseen[icon] then icon:Hide() end end
    W.LayoutHRow(st.anchors.AuraRow, alist, cfg.auraRow.iconW, cfg.auraRow.iconH, cfg.auraRow.spacing)

    -- resources
    st.stance:SetShown(show.Stance)
    st.stance:SetIconTexture(tex.stance or D.STANCE_ICONS[3])
    st.stance:SetSize(r.stance.w or 32, r.stance.h or 34)
    D.StyleIcon(st.stance, cfg)
    st.exec:SetShown(show.Execute and combat)
    st.exec:SetIconTexture(D.EXEC_ICON)
    st.exec:SetSwipe(now - 2, 6)
    D.StyleIcon(st.exec, cfg)

    local rb = st.rage
    rb:SetShown(show.RageBar)
    local w, h = r.rage.w or 229, r.rage.h or 4
    rb:SetSize(w, h)
    local pct = combat and 62 or 18
    rb.bar:SetValue(pct / 100)
    rb.text:SetText(tostring(pct))
    local rc = (pct <= 30) and C.rageLow or C.rage
    rb:SetBarColor(rc[1], rc[2], rc[3], rc[4])
    rb.text:SetTextColor(C.rageText[1], C.rageText[2], C.rageText[3], C.rageText[4])
    local marks = r.rageMarks ~= false
    for i, cost in ipairs({ 30, 25 }) do
        local m = rb.marks[i]
        m:ClearAllPoints()
        m:SetPoint("TOP", rb.bar, "TOPLEFT", w * cost / 100, 1)
        m:SetPoint("BOTTOM", rb.bar, "BOTTOMLEFT", w * cost / 100, -1)
        m:SetShown(marks)
    end
    local q = combat and r.rageQueue ~= false
    rb.qSeg:SetShown(q or false)
    if q then
        rb.qSeg:SetWidth(math.max(1, w * 15 / 100))
        rb.qSeg:SetVertexColor(C.queueHS[1], C.queueHS[2], C.queueHS[3], C.queueHS[4])
    end

    local swOn = show.Swing and combat
    st.mh:SetShown(swOn)
    st.oh:SetShown(swOn)
    D.SizeSwingBars(st.mh, st.oh, st.anchors.Swing, r.swing.w or 229, r.swing.h or 3)
    st.mh:SetBarColor(C.swingMH[1], C.swingMH[2], C.swingMH[3], C.swingMH[4])
    st.oh:SetBarColor(C.swingOH[1], C.swingOH[2], C.swingOH[3], C.swingOH[4])
end

-- the strip's modes: the Battle Shout slot's two warning states only
-- while the reminder is set to live in the buff row
local function WarriorModes()
    local m = { { id = "combat", label = "In combat" }, { id = "ready", label = "Out of combat" } }
    local D = WH.Display
    if D and D.ShoutDocked and D.ShoutDocked() then
        m[#m + 1] = { id = "shoutMissing", label = "Shout missing" }
        m[#m + 1] = { id = "shoutLow", label = "Shout running low" }
    end
    return m
end

local function WarriorPreview(cfg)
    local w, h = SampleSize(cfg)
    -- fitted after every update: the pieces in the dock's strata, and
    -- shrunk to the canvas when the layout is bigger than it
    return HUD.FitSpec({
        key = "hud.warrior", title = "Warrior HUD",
        width = w, height = h,
        modes = WarriorModes(),
        build = BuildWarriorSample,
        update = UpdateWarriorSample,
        replay = function(canvas, P)
            local st = P.store
            if not st.grid then return end
            HUD.ReplayIcons({ st.gridList, st.auraList }, true)
        end,
    }, function(canvas, P)
        -- the layout's own box (the pieces are centred on it) for when the
        -- game cannot measure them yet
        local lay = P.store.layout
        if lay then return 0, 0, lay.w, lay.h end
    end)
end

-- The four consumable icons are the only ones a macro can drive: they draw
-- a bag item, which is what a smart macro resolves to. A spell icon has
-- nothing to swap.
local MACRO_BINDABLE = {
    { key = "potion", label = "Potion" },
    { key = "sapper", label = "Sapper" },
    { key = "dense",  label = "Dynamite" },
    { key = "dummy",  label = "Dummy" },
}

-- One dropdown per bindable icon, listing the smart macros by name. Binding
-- one makes that icon follow the macro instead of its own item list, so a
-- macro that swaps between two throwables shows whichever one it is on.
-- No smart macros available means no editor at all.
local function MacroBindEditor(L, cfg)
    local SM = HUD.SmartMacro()
    local names = (SM and SM.ListMacroNames) and SM:ListMacroNames() or {}
    if #names == 0 then return end

    local bind = cfg.mainRow.macroBind
    if type(bind) ~= "table" then
        bind = {}
        cfg.mainRow.macroBind = bind
    end

    local items = { { text = "Not linked", value = "" } }
    for _, n in ipairs(names) do items[#items + 1] = { text = n, value = n } end

    L:Gap(4)
    HUD.Label(L, "Follow a smart macro")
    L:Desc("Link one of the consumable icons to a smart macro and it shows "
        .. "whichever item that macro is currently set to use, with that "
        .. "item's count and cooldown, instead of its own list.")

    local card = L.current
    -- label | dropdown pairs, two across when two fit, the label column as
    -- wide as the longest label
    local labW = 60
    for _, entry in ipairs(MACRO_BINDABLE) do
        local probe = UI.Font(card, F.LABEL, { text = entry.label })
        labW = math.max(labW, math.ceil(probe:GetStringWidth() or 0) + 8)
        probe:Hide()
    end
    local room = L:Room()
    local pairW = labW + 130
    local perRow = (room >= 2 * pairW + 20) and 2 or 1
    local colX = { M.CONTROL_X, M.CONTROL_X + math.max(pairW + 20, math.floor(room / 2)) }
    local col = 0
    for _, entry in ipairs(MACRO_BINDABLE) do
        local lbl = UI.Font(card, F.LABEL, { text = entry.label, cat = "text", key = "normal" })
        lbl:SetPoint("TOPLEFT", card, "TOPLEFT", colX[col + 1], card._y - 6)

        local key = entry.key
        local dd = UI.Dropdown(card, {
            width = 130,
            items = function() return items end,
            selected = function()
                local cur = bind[key] or ""
                return cur ~= "" and cur or "Not linked"
            end,
            selectedValue = function() return bind[key] or "" end,
            onSelect = function(value)
                bind[key] = (value ~= "" and value) or nil
                local disp = WH.Display
                if disp and disp.InvalidateLayout then disp:InvalidateLayout() end
            end,
        })
        dd:SetPoint("TOPLEFT", card, "TOPLEFT", colX[col + 1] + labW, card._y)
        if room - labW < 130 then dd:SetWidth(math.max(60, room - labW)) end

        col = col + 1
        if col >= perRow then
            col = 0
            card._y = card._y - (M.DROPDOWN_H + 6)
        end
    end
    if col > 0 then card._y = card._y - (M.DROPDOWN_H + 6) end
    card._y = card._y - 6
end

-- Add-entry editbox + kind/stance dropdowns + current entries with
-- remove buttons. Re-renders the page (tab is remembered) after changes.
local function CustomEditor(L, customList, placeholder, defaultKind)
    local card = L.current
    local y = card._y
    local lbl = UI.Font(card, F.LABEL, { text = placeholder, cat = "text", key = "normal" })
    lbl:SetPoint("TOPLEFT", card, "TOPLEFT", M.CONTROL_X, y - 6)
    -- the box and its dropdowns flow after the label, wrapping in a narrow card
    local indent = M.CONTROL_X + math.max(36, math.ceil(lbl:GetStringWidth() or 0) + 8)

    local eb = UI.EditBox(card, { width = 140 })

    local selKind, selStance = defaultKind, 0
    local kindDd = UI.Dropdown(card, {
        width = 95,
        items = function() return KIND_ITEMS end,
        selected = function() return KIND_LABELS[selKind] end,
        selectedValue = function() return selKind end,
        onSelect = function(value) selKind = value end,
    })

    local stanceDd = UI.Dropdown(card, {
        width = 105,
        items = function() return STANCE_ITEMS end,
        selected = function() return STANCE_LABELS[selStance] end,
        selectedValue = function() return selStance end,
        onSelect = function(value) selStance = value end,
    })

    -- No validation here: an unresolved name or spell ID still gets stored,
    -- and Core's ResolveCustomList marks it known=false, so the icon just
    -- never appears - no error, no feedback telling the user why.
    local addBtn = UI.Button(card, "Add", { width = 45, onClick = function()
        local txt = (eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if txt ~= "" then
            customList[#customList + 1] =
                { input = txt, kind = selKind, stance = selStance }
            WH.MarkSpellsDirty()
            HUD.RefreshPage()
        end
    end })
    L:Flow({ eb, kindDd, stanceDd, addBtn }, 6, 8, indent)

    -- each entry: its text wrapping in what is left of Remove (held right)
    for i, entry in ipairs(customList) do
        local rmBtn = UI.Button(card, "Remove", { width = 60, height = 20, onClick = function()
            table.remove(customList, i)
            WH.MarkSpellsDirty()
            HUD.RefreshPage()
        end })
        rmBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -M.CONTROL_X, card._y)
        local fs = UI.Font(card, F.LABEL, {
            text = string.format("%s  |cff999999(%s, %s)|r",
                tostring(entry.input),
                KIND_LABELS[entry.kind or defaultKind] or "?",
                STANCE_LABELS[entry.stance or 0] or "Any stance"),
            cat = "text", key = "normal",
            width = math.max(60, L:Room() - (M.DESC_X - M.CONTROL_X) - (rmBtn:GetWidth() or 60) - 8),
        })
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", M.DESC_X, card._y - 5)
        card._y = card._y - math.max(24, (fs:GetStringHeight() or 12) + 10)
    end
end

-- Tab sections
local function Px(v) return v .. " px" end
local function Pct(v) return v .. "%" end

local function TabGeneral(L, cfg)
    L:Card("General")
    L:Desc("Native port of the Warrior Class Pack WeakAura. Warrior characters "
        .. "only. Every element is its own anchor in ZacUI's movers - use them "
        .. "to line things up with your unit frames exactly.")

    Check(L, "Enable Warrior HUD", cfg.enabled, function(v)
        WH:SetEnabled(v)
    end)
    PreviewCheck(L)
    L:Desc("Forces every enabled icon visible where it sits, to line things up. Not saved.")
    L:Gap(4)
    Check(L, "Cooldown grid (main rows)", cfg.mainRow.enabled, function(v)
        cfg.mainRow.enabled = v
    end)
    Check(L, "Active buff row", cfg.auraRow.enabled, function(v)
        cfg.auraRow.enabled = v
    end)
    Check(L, "Resources group", cfg.resources.enabled, function(v)
        cfg.resources.enabled = v
    end)
    Check(L, "Stance icon", cfg.resources.stanceHud, function(v)
        cfg.resources.stanceHud = v
    end, 20)
    Check(L, "Execute helper (swaps to Bloodthirst from the AP set under Hesitation, 2000 by default)",
        cfg.resources.executeHelper, function(v)
            cfg.resources.executeHelper = v
        end, 20)
    Check(L, "Rage bar", cfg.resources.rageBar, function(v)
        cfg.resources.rageBar = v
    end, 20)
    Check(L, "Show what a queued Heroic Strike / Cleave will spend", cfg.resources.rageQueue ~= false, function(v)
        cfg.resources.rageQueue = v and true or false
    end, 40)
    Check(L, "Marks at what Bloodthirst and Whirlwind cost", cfg.resources.rageMarks ~= false, function(v)
        cfg.resources.rageMarks = v and true or false
    end, 40)
    Check(L, "Swing timer bars (in combat)", cfg.resources.swingTimer, function(v)
        cfg.resources.swingTimer = v
    end, 20)
    L:EndCard()

    L:Card("Consumables")
    local card = L.current
    local ddLbl = UI.Font(card, F.LABEL, { text = "Potion icon", cat = "text", key = "normal" })
    ddLbl:SetPoint("TOPLEFT", card, "TOPLEFT", M.CONTROL_X, card._y - 6)
    local dd = UI.Dropdown(card, {
        width = 220,
        items = function() return PotionItems() end,
        selected = function() return PotionLabel(cfg.potionChoice) end,
        selectedValue = function() return cfg.potionChoice or 1 end,
        onSelect = function(value) cfg.potionChoice = value end,
    })
    UI.Tooltip(dd, "Potion icon", "The potion the cooldown grid's potion icon shows. Automatic shows the first "
        .. "potion found in your bags, in the pack's priority order.")
    -- beside its label, however wide the label comes out
    dd:SetPoint("TOPLEFT", card, "TOPLEFT", M.CONTROL_X + math.max(90, math.ceil(ddLbl:GetStringWidth() or 0) + 10), card._y)
    card._y = card._y - (M.DROPDOWN_H + 10)

    HUD.Slider(L, "Sapper threshold", 1, 20, cfg.sapperThreshold or 7, function(v)
        cfg.sapperThreshold = v
    end, { width = SLIDER_W, format = function(v) return v .. " plates" end })
    L:Desc("The sapper icon glows when this many attackable nameplates are near and it is ready.")
    Check(L, "Say \"Sapper now\" when it glows", cfg.sapperTTS, function(v)
        cfg.sapperTTS = v
    end)
    L:Gap(6)
    local ww = Check(L, "Whirlwind mob count", cfg.wwCount ~= false, function(v)
        cfg.wwCount = v and true or false
    end)
    UI.Tooltip(ww, "Whirlwind mob count", "A small cyan number on the Whirlwind icon: how many mobs the "
        .. "Whirlwind call is counting (2 or more: in a fight the ones within reach, before a charge the "
        .. "pack round your target), and a cyan flash while that many are there and Whirlwind is ready. "
        .. "With Hesitation's \"Mark the button to press first\" on, that mark decides when Whirlwind "
        .. "lights up and this flash stays off - one rule, not two.")
    L:Desc("A cyan count of the mobs Whirlwind would hit, and a flash when it is worth pressing.")
    HUD.Slider(L, "Flash Whirlwind at", 2, 10, cfg.wwFlashAt or 4, function(v)
        cfg.wwFlashAt = v
    end, { width = SLIDER_W, format = function(v) return v .. " mobs" end })
    L:EndCard()
end

local function TabGrid(L, cfg)
    local D = WH.Display
    L:Card("Cooldown grid icons")
    L:Desc("Untick an icon to remove it from the grid. Add anything by name or "
        .. "spell ID as a Cooldown (standard template: swipe, desaturate, "
        .. "countdown) or a Buff (shows while active), optionally limited to "
        .. "one stance.")
    if D and D.MainIconList then
        IconGrid(L, D.MainIconList, cfg.mainRow.hidden)
    end
    MacroBindEditor(L, cfg)
    CustomEditor(L, cfg.mainRow.custom, "Add:", "cd")
    L:EndCard()
end

local function TabBuffRow(L, cfg)
    local D = WH.Display
    L:Card("Active buff icons")
    L:Desc("Untick an icon to remove it from the active-buff row. Add any player "
        .. "buff/self-debuff (shows while active with swipe + timer) or a "
        .. "Cooldown icon, optionally limited to one stance.")
    if D and D.AuraIconList then
        IconGrid(L, D.AuraIconList, cfg.auraRow.hidden)
    end
    CustomEditor(L, cfg.auraRow.custom, "Add:", "buff")
    L:EndCard()
end

local COLOR_LABELS = {
    { "rage", "Rage bar" }, { "rageLow", "Rage bar at 30 or less" }, { "rageText", "Rage value text" },
    { "queueHS", "Queued Heroic Strike" }, { "queueCleave", "Queued Cleave" },
    { "swingMH", "Main-hand swing" }, { "swingOH", "Off-hand swing" },
    { "oor", "Out of range tint" }, { "timer", "Timer text" },
}

local function TabLook(L, cfg)
    local r = cfg.resources
    L:Card("Cooldown grid")
    L:Desc("Per-row icon sizes and capacity (icons past row 3 keep filling row 3).")
    local rows = cfg.mainRow.rows
    for ri = 1, 3 do
        local rowCfg = rows and rows[ri]
        if rowCfg then
            SliderPair(L,
                { "Grid row " .. ri .. " width", 16, 64, rowCfg.w or 26,
                  function(v) rowCfg.w = v end, Px },
                { "Grid row " .. ri .. " height", 16, 64, rowCfg.h or 26,
                  function(v) rowCfg.h = v end, Px })
        end
    end
    if rows and rows[1] and rows[2] then
        SliderPair(L,
            { "Row 1 max icons", 1, 20, rows[1].limit or 8,
              function(v) rows[1].limit = v end },
            { "Row 2 max icons", 1, 20, rows[2].limit or 9,
              function(v) rows[2].limit = v end })
    end
    SliderPair(L,
        { "Grid icon spacing", 0, 12, cfg.mainRow.spacing or 3,
          function(v) cfg.mainRow.spacing = v end, Px })
    L:EndCard()

    L:Card("Active buff row")
    SliderPair(L,
        { "Buff row icon width", 16, 64, cfg.auraRow.iconW or 30,
          function(v) cfg.auraRow.iconW = v end, Px },
        { "Buff row icon height", 16, 64, cfg.auraRow.iconH or 30,
          function(v) cfg.auraRow.iconH = v end, Px })
    SliderPair(L,
        { "Buff row spacing", 0, 12, cfg.auraRow.spacing or 4,
          function(v) cfg.auraRow.spacing = v end, Px })
    L:EndCard()

    L:Card("Bars and icons")
    SliderPair(L,
        { "Rage bar width", 100, 400, r.rage.w or 229, function(v) r.rage.w = v end, Px },
        { "Rage bar height", 2, 20, r.rage.h or 4, function(v) r.rage.h = v end, Px })
    SliderPair(L,
        { "Swing bar width", 100, 400, r.swing.w or 229, function(v) r.swing.w = v end, Px },
        { "Swing bar height", 2, 12, r.swing.h or 3, function(v) r.swing.h = v end, Px })
    SliderPair(L,
        { "Icon border thickness", 1, 4, cfg.borderSize or 1,
          function(v) cfg.borderSize = v end, Px },
        nil)
    L:Desc("The main-hand swing bar comes out a little thicker than this, the off hand thinner. "
        .. "Border thickness is every Warrior HUD icon's.")
    L:EndCard()

    L:Card("Colours")
    local defaults = WH.COLOR_DEFAULTS or {}
    local entries = {}
    for _, c in ipairs(COLOR_LABELS) do
        local key = c[1]
        entries[#entries + 1] = { c[2],
            get = function() return HUD.Col(cfg.colors[key], defaults[key]) end,
            set = function(rr, g, b, a)
                cfg.colors[key] = { r = rr, g = g, b = b, a = a or 1 }
                AfterSizing()
            end }
    end
    HUD.ColorGrid(L, entries)
    L:EndCard()

    HUD.SharedLookCards(L, { ownBorder = true })
end

local function TabText(L, cfg)
    L:Card("Warrior HUD text sizes")
    L:Desc("Countdown timers and the count / stack numbers on every Warrior HUD icon.")
    local tsz = cfg.textSizes
    SliderPair(L,
        { "Countdown text size", 8, 24, tsz.timer or 14, function(v) tsz.timer = v end, Px },
        { "Count text size", 8, 20, tsz.count or 12, function(v) tsz.count = v end, Px })
    L:EndCard()
    -- the grid's and the buff row's icons can each keep their own spots
    local D = WH.Display
    local icons = {}
    for _, list in ipairs({ D and D.MainIconList or {}, D and D.AuraIconList or {} }) do
        for _, ic in ipairs(list) do icons[#icons + 1] = ic end
    end
    HUD.SharedTextCards(L, nil, { icons = icons })
end

local function TabPosition(L, cfg)
    local r = cfg.resources
    L:Card("Position")
    L:Desc("Every piece of the HUD is its own anchor: drag them to line up with your unit frames. "
        .. "The preview shows them where they sit relative to each other.")
    HUD.UnlockButton(L, "wh")
    L:Gap(4)
    SliderPair(L,
        { "Cooldown grid scale", 50, 200,
          math.floor((cfg.mainRow.scale or 1) * 100 + 0.5),
          function(v) cfg.mainRow.scale = v / 100 end, Pct },
        { "Active buffs scale", 50, 200,
          math.floor((cfg.auraRow.scale or 1) * 100 + 0.5),
          function(v) cfg.auraRow.scale = v / 100 end, Pct })
    SliderPair(L,
        { "Stance icon scale", 50, 200,
          math.floor((r.stance.scale or 1) * 100 + 0.5),
          function(v) r.stance.scale = v / 100 end, Pct },
        { "Execute helper scale", 50, 200,
          math.floor((r.execute.scale or 1) * 100 + 0.5),
          function(v) r.execute.scale = v / 100 end, Pct })
    L:EndCard()
end

local function TabAdvanced(L, cfg)
    L:Card("Reset")
    HUD.Button(L, "Reset colours", 150, function()
        cfg.colors = ns.CopySetting(WH.COLOR_DEFAULTS or {})
        AfterSizing()
        ns.SettingsChanged("reset")
        HUD.RefreshPage()
    end, "Puts the Warrior HUD's colours back to the defaults.")
    HUD.ResetLookButton(L)
    L:EndCard()
end

-- The page: header, the preview dock, the tab row and the chosen tab.
local function BuildPage(L)
    L:Header("Warrior HUD",
        "WeakAura port: cooldown grid, resources and active-buff row")
    local cfg = WH.Store()
    if not cfg then
        L:Notice("missing", "The HUD settings are not available yet.")
        return
    end
    -- an old page id ("sizing") lands on Look
    local s = ns.ConfigState and ns.ConfigState()
    if s and s.tabs and s.tabs.warrior == "sizing" then s.tabs.warrior = "look" end
    if WH.Display and WH.Display.GetPreviewTextures then L:Preview(WarriorPreview(cfg)) end
    L:Tabs({
        { id = "general", label = "General",    build = function(L2) TabGeneral(L2, cfg) end },
        { id = "grid",    label = "Grid icons", build = function(L2) TabGrid(L2, cfg) end },
        { id = "buffrow", label = "Buff row",   build = function(L2) TabBuffRow(L2, cfg) end },
        { id = "look",    label = "Look",       build = function(L2) TabLook(L2, cfg) end },
        { id = "text",    label = "Text",       build = function(L2) TabText(L2, cfg) end },
        { id = "anim",    label = "Animation",  build = function(L2) HUD.SharedAnimCards(L2) end },
        { id = "pos",     label = "Position",   build = function(L2) TabPosition(L2, cfg) end },
        { id = "adv",     label = "Advanced",   build = function(L2) TabAdvanced(L2, cfg) end },
    })
end

HUD.RegisterPage("warrior", "Warrior HUD",
    "warrior hud weakaura class pack cooldowns swing timer rage bar execute "
    .. "overpower sapper potion stance active buffs salv sizing scale spacing "
    .. "add spell add buff hide icon custom icon grid icons buff row preview "
    .. "smart macro " .. HUD.PAGE_KEYWORDS,
    { WARRIOR = true },
    BuildPage)
