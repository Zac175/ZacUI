-- Config_PagesNameplates - the Nameplates page. Every value the plate
-- engine reads is editable here, live, and shown on sample plates in the
-- preview dock (NP_Preview builds them with the engine's own code).
-- Part of ZacUI; load order is set by the TOC.
--
-- THE SHAPE (the settings guide's standard order):
--   General    what shows and when: plates, target, fading, priority
--              mobs, threat, extras, debuff groups and their members
--   Look       textures, bar colours, sizes, every colour, target marks
--   Text       the plate font, then one font per text on the plate
--   Animation  the plates' fades, size changes, entrances
--   Position   name and marker spots, click box, debuff groups' spots
--   Advanced   resets and custom debuffs
-- then the two features that live on the plates but are not drawn by
-- them: Soft target & crosshair, and Scripts.
--
-- Saved keys are the ones the engine has always read (ZacUIDB.nameplates);
-- the new ones (fonts, colours, animations) are filled from NP_Core's
-- DEFAULTS, which are exactly what the plates drew before they existed.

local ADDON_NAME = ...
-- Zacui_Nameplates is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Print = ns.Print
local RefreshConfig = ns.RefreshConfig
local RegisterPage = ns.RegisterPage
local UI = ns.UI

local M, F = UI.M, UI.F

local function NPRefresh()
    local NP = ns.Nameplates
    if NP then NP.RefreshAll() end
end

-- the words people type that are not on the page
do
    local extra = " font fonts typeface outline shadow colour color colours texture textures "
        .. "background border animation animations animate fade fading scale size grow shrink "
        .. "pop slide flash preview sample test soft target softtarget arrow arrows crosshair "
        .. "reticle priority important boss totem quest marker skull raid mark click box spark "
        .. "interrupt channel spell name level percent glow neon hover mouseover "
        .. "state states edge opacity alpha visibility faded casting uninterruptible"
    if ns.AddMenuKeywords then ns.AddMenuKeywords("nameplates", extra) end
end

-- ============================================================
-- BIND HELPERS - every control edits ZacUIDB.nameplates directly and
-- asks the engine to re-fit the live plates (the soft-target and
-- crosshair blocks pass a refresh of their own). The widgets raise the
-- change signal themselves, so the preview follows every one.
-- ============================================================
local function BindCheck(L, tbl, key, label, desc, refresh)
    local w = UI.Checkbox(L.current, label, tbl[key] and true or false,
        function(v)
            tbl[key] = v and true or false
            local fn = refresh or NPRefresh
            fn()
        end)
    L:Row(w, 17)
    if desc then L:Desc(desc) end
    return w
end

local function BindSlider(L, tbl, key, label, opts)
    opts = opts or {}
    local refresh = opts.refresh or NPRefresh
    local w = UI.Slider(L.current, {
        width = opts.width or 200, min = opts.min, max = opts.max, step = opts.step or 1,
        value = opts.get and opts.get(tbl[key]) or tbl[key],
        label = label, format = opts.format,
        onChange = function(v)
            tbl[key] = opts.set and opts.set(v) or v
            refresh()
        end,
    })
    L:Row(w, 40)
    if opts.desc then L:Desc(opts.desc) end
    return w
end

local function PX(v) return v .. " px" end
local function PCT(v) return v .. "%" end
-- a 0..1 value shown as a percentage slider
local function PctOpts(def, opts)
    opts = opts or {}
    opts.get = function(v) return math.floor((v or def) * 100 + 0.5) end
    opts.set = function(v) return v / 100 end
    opts.format = PCT
    return opts
end

-- A labelled dropdown over a key; items are { text, value } pairs.
local function BindDropdown(L, tbl, key, label, items, desc, refresh)
    local title = UI.Font(L.current, F.LABEL, { text = label })
    L:Row(title, 16)
    local function TextOf(v)
        for _, it in ipairs(items) do
            if it.value == v then return it.text end
        end
        return tostring(v)
    end
    local dd = UI.Dropdown(L.current, { width = 240,
        items = function() return items end,
        selectedValue = function() return tbl[key] end,
        selected = function() return TextOf(tbl[key]) end,
        onSelect = function(v)
            tbl[key] = v
            local fn = refresh or NPRefresh
            fn()
        end })
    L:Row(dd, M.DROPDOWN_H + 6)
    if desc then L:Desc(desc) end
    return dd
end

-- A colour kept in OUR settings as an {r, g, b[, a]} array - the shape
-- the engine reads. UI.ColorPicker's getter takes the array as it is.
local function ColorSet(tbl, key, alpha, refresh)
    return function(r, g, b, a)
        local c = { r, g, b }
        if alpha then c[4] = a or 1 end
        tbl[key] = c
        local fn = refresh or NPRefresh
        fn()
    end
end

local function BindColor(L, tbl, key, label, opts)
    opts = opts or {}
    local w = UI.ColorPicker(L.current, { label = label, alpha = opts.alpha,
        tooltip = opts.tooltip,
        get = function() return tbl[key] or opts.default or { 1, 1, 1 } end,
        set = ColorSet(tbl, key, opts.alpha, opts.refresh) })
    L:Row(w, 20)
    if opts.desc then L:Desc(opts.desc) end
    return w
end

-- A row of preset swatches under a colour: one click sets the stored
-- {r,g,b} and repaints the picker above it. The border lights gold on
-- the preset that matches what is stored. A hand-made control, so it
-- raises the change signal itself.
-- (one swatch's frame, fill and edge: handed back by the settings pool
-- on a rebuild instead of made again)
local function NewPresetSwatch(row)
    local sw = CreateFrame("Button", nil, row)
    sw:SetSize(18, 14)
    local fill = sw:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    sw._zPresetFill = fill
    UI.Border(sw, "ui", "border")
    return sw
end

local function BindPresetRow(L, tbl, key, presets, refresh, picker)
    local row = UI.Holder(L.current)
    row:SetSize(300, 14)
    local x = 0
    for _, preset in ipairs(presets) do
        local sw = ns.UIPool and ns.UIPool.Make("NPPresetSwatch", NewPresetSwatch, row) or NewPresetSwatch(row)
        sw:SetPoint("LEFT", row, "LEFT", x, 0)
        local fill = sw._zPresetFill
        local pc = preset.color
        fill:SetColorTexture(pc[1], pc[2], pc[3], 1)
        sw._zPaint = function(self)
            local c = tbl[key]
            local sel = c and math.abs((c[1] or 0) - pc[1]) < 0.02
                and math.abs((c[2] or 0) - pc[2]) < 0.02
                and math.abs((c[3] or 0) - pc[3]) < 0.02
            local b = ns.GetColor("ui", sel and "accent" or "border")
            for _, t in ipairs(self._zBorder or {}) do
                t:SetVertexColor(b.r, b.g, b.b, 1)
            end
        end
        sw:_zPaint()
        UI.Tooltip(sw, preset.name)
        sw:SetScript("OnClick", function()
            tbl[key] = { pc[1], pc[2], pc[3] }
            if picker and picker.Refresh then picker.Refresh() end
            for _, sib in ipairs({ row:GetChildren() }) do
                if sib._zPaint then sib:_zPaint() end
            end
            local fn = refresh or NPRefresh
            fn()
            if ns.SettingsChanged then ns.SettingsChanged("preset") end
        end)
        x = x + 22
    end
    L:Row(row, 18)
    return row
end

-- The plate font's name for the font pickers' "nil" (false = ZacUI's).
local function PlateFace()
    local NP = ns.Nameplates
    local f = NP and NP.DB().fontName
    if type(f) == "string" and f ~= "" then return f end
    return nil
end

-- One text's font: the size in its old key (sizeKey) so saved settings
-- keep working, the rest (face, outline, shadow) in a spec beside it
-- (specKey). sizeKey nil = the size lives in the spec too.
local function BindFont(L, label, tbl, sizeKey, specKey, defSize, opts)
    opts = opts or {}
    local refresh = opts.refresh or NPRefresh
    local picker = UI.FontPicker(L.current, {
        label = label, width = 400, defaultLabel = "Plate font",
        get = function()
            local t = {}
            for k, v in pairs(tbl[specKey] or {}) do t[k] = v end
            if sizeKey then t.size = tbl[sizeKey] end
            return t
        end,
        set = function(new)
            local sp = {}
            for k, v in pairs(new) do
                if not (sizeKey and k == "size") then sp[k] = v end
            end
            if sizeKey and new.size then tbl[sizeKey] = new.size end
            tbl[specKey] = sp
            refresh()
        end,
        defaults = { face = PlateFace(), size = defSize, outline = "outline", shadow = false },
        minSize = opts.min or 6, maxSize = opts.max or 32, sample = opts.sample,
    })
    L:Add(picker, 10)
    if opts.desc then L:Desc(opts.desc) end
    return picker
end

-- The same font binding as a get / set / defaults trio, for ZacUI's
-- UI.TextElement (font, colour, format and spot of one text in a group).
local function FontAccess(tbl, sizeKey, specKey, defSize, refresh)
    refresh = refresh or NPRefresh
    local function get()
        local t = {}
        for k, v in pairs(tbl[specKey] or {}) do t[k] = v end
        if sizeKey then t.size = tbl[sizeKey] end
        return t
    end
    local function set(new)
        local sp = {}
        for k, v in pairs(new or {}) do
            if not (sizeKey and k == "size") then sp[k] = v end
        end
        if sizeKey and new and new.size then tbl[sizeKey] = new.size end
        tbl[specKey] = sp
        refresh()
    end
    return get, set, { face = PlateFace(), size = defSize, outline = "outline", shadow = false }
end

-- An {r, g, b[, a]} colour of ours as a TextElement colour entry.
local function ColorEntry(tbl, key, label, def)
    return { label = label, alpha = true,
        get = function() return tbl[key] or def or { 1, 1, 1 } end,
        set = ColorSet(tbl, key, true) }
end

-- ZacUI's customization standard on the plates: where each text and part
-- sits, per side (d.enemy.anchors.<key> / d.friendly.anchors.<key>), and
-- the health percent's format (cfg.formats.percent). Group keys carry an
-- "np." prefix so they never meet the unit frames' own "name" group.
-- the state the Look tab's state editor was on, across rebuilds
local STATE_PICK = {}

local function NPAccess(tbl, family, key)
    return ns.CustomAccess(tbl, family, key, NPRefresh)
end
local function NPTargets(self)
    local NP = ns.Nameplates
    local out = {}
    for _, k in ipairs(NP.ANCHOR_TARGETS or {}) do
        if k ~= self then out[#out + 1] = { value = k, text = NP.ANCHOR_LABELS[k] or k } end
    end
    return out
end
local function NPAnchorDef(side, key)
    return function() return ns.Nameplates.AnchorDefaults(side, key) end
end

-- One animation: a spec under ZacUIDB.nameplates.anim (NP_Core's
-- DEFAULTS fill it with "none", today's behaviour).
local function BindAnim(L, key, label, styles, desc)
    local NP = ns.Nameplates
    local d = NP.DB()
    local picker = UI.AnimationPicker(L.current, {
        label = label, styles = styles, width = 400,
        get = function() return d.anim[key] end,
        set = function(spec) d.anim[key] = spec end,
    })
    L:Add(picker, 8)
    if desc then L:Desc(desc) end
    return picker
end

local NAME_POS = {
    { text = "Inside the bar", value = "inside" },
    { text = "Above the bar", value = "above" },
}
local NAME_JUSTIFY = {
    { text = "Left, after the level", value = "LEFT" },
    { text = "Centred", value = "CENTER" },
}
local MARKER_POS = {
    { text = "Above the bar", value = "above" },
    { text = "On the bar, centred", value = "centre" },
    { text = "Left of the bar", value = "left" },
    { text = "Left end of the bar", value = "level" },
}
local ARROW_STYLES = {
    { text = "Box all round the bar", value = "box" },
    { text = "Corner brackets", value = "brackets" },
    { text = "Glowing chevron", value = "chevron" },
    { text = "Solid triangles", value = "solid" },
    { text = "Thin chevron", value = "thin" },
}
local ARROW_COLORS = {
    { text = "The crosshair's colour (live)", value = "crosshair" },
    { text = "White", value = "white" },
    { text = "My own colour", value = "custom" },
}

-- ============================================================
-- PREVIEW - sample plates in the dock (NP_Preview's scenes)
-- ============================================================
local MODES = {
    { id = "enemy", label = "Enemy" },
    { id = "target", label = "Target" },
    { id = "casting", label = "Casting" },
    { id = "friendly", label = "Friendly" },
    { id = "important", label = "Important" },
}

local function BuildPreview(canvas, P)
    local NP = ns.Nameplates
    local S = NP.Sample
    local st = P.store
    st.sets = {}
    st.serial = 0
    for _, m in ipairs(MODES) do
        -- a small host the plates hang from; update centres it on what
        -- they draw and sizes the canvas to that
        local host = CreateFrame("Frame", nil, canvas)
        host:SetSize(10, 10)
        host:SetPoint("CENTER", canvas, "CENTER", 0, 0)
        host:Hide()
        local set = { host = host, plates = {} }
        for i, s in ipairs(S.SCENES[m.id]) do
            -- each sample hangs from a slot of its own, so a plate that
            -- grows (the target, a priority mob) grows about its centre
            local slot = CreateFrame("Frame", nil, host)
            slot:SetSize(1, 1)
            slot:SetPoint("CENTER", host, "CENTER", s.x or 0, s.y or 0)
            local f = S.New(slot)
            f:SetPoint("CENTER", slot, "CENTER", 0, 0)
            set.plates[i] = f
        end
        if m.id == "target" then
            -- the HUD's cooldown row is lent to this scene; hand it back
            -- the moment the scene is not on screen
            host:HookScript("OnHide", function() S.ReleaseRow(set.plates[1]) end)
        elseif m.id == "important" then
            -- the mid-screen priority count, as a sample line
            local box = CreateFrame("Frame", nil, host)
            box:SetSize(230, 30)
            box:SetPoint("LEFT", host, "CENTER", 200, 0)
            local fs = box:CreateFontString(nil, "OVERLAY")
            NP.SetNPFont(fs, 22)
            fs:SetPoint("LEFT")
            fs:SetText("Lightning Totem x2")
            set.warnBox, set.warn = box, fs
        end
        st.sets[m.id] = set
    end
end

local function ModeOf(P)
    local st = P.store
    return (P.mode and st.sets[P.mode]) and P.mode or "enemy"
end

local function UpdatePreview(canvas, P)
    local NP = ns.Nameplates
    local S = NP.Sample
    local st = P.store
    local mode = ModeOf(P)
    for id, set in pairs(st.sets) do
        if id ~= mode then set.host:Hide() end
    end
    local set = st.sets[mode]
    set.host:Show()
    local scenes = S.SCENES[mode]
    for i, f in ipairs(set.plates) do
        local s = scenes[i]
        S.Fill(f, s, false)
        S.Arrow(set.host, f, s.arrow)
    end
    if mode == "target" then S.ShowRow(set.plates[1], true) end
    if set.warn then
        local p = NP.DB().priority
        NP.StylePrioWarn(set.warn)
        set.warnBox:SetShown((p.enabled and p.countWarn ~= false) and true or false)
    end
    -- SIDE BY SIDE FROM WHAT THEY DRAW. A plate's width is a setting (and
    -- a priority mob or the target is drawn bigger, with auras and a
    -- threat strip hanging off it), so fixed offsets let the plates run
    -- into each other (Zac 2026-11-02: the Lightning Totem over Faerlina).
    -- Each plate is measured and the next starts a gap after it; the
    -- priority count line goes after the last one.
    if P.Measure then
        local GAP, cursor = 22, 0
        for i, f in ipairs(set.plates) do
            local slot = f:GetParent()
            local cx, _, w = P.Measure(f)
            if cx and w then
                -- Measure answers in the plate's own units; a priority mob
                -- or the target is drawn scaled up, so turn them into the
                -- host's (unscaled, the big plate ran into the next one)
                -- (where its size glide is heading, not where it is now)
                local hs = set.host:GetEffectiveScale() or 1
                local ps = slot.GetEffectiveScale and slot:GetEffectiveScale() or hs
                local fs = (ns.Nameplates.FX and ns.Nameplates.FX.Target) and ns.Nameplates.FX.Target(f, "scale")
                    or (f.GetScale and f:GetScale()) or 1
                local k = (tonumber(fs) or 1) * ps / (hs ~= 0 and hs or 1)
                cx, w = cx * k, w * k
                local x = cursor - cx + w / 2
                slot:ClearAllPoints()
                slot:SetPoint("CENTER", set.host, "CENTER", x, scenes[i].y or 0)
                cursor = x + cx + w / 2 + GAP
            end
        end
        if set.warnBox and set.warnBox:IsShown() then
            set.warnBox:ClearAllPoints()
            set.warnBox:SetPoint("LEFT", set.host, "CENTER", cursor, 0)
        end
    end
    -- the canvas is what the plates draw (where the settings put it),
    -- centred; the strip scales it
    if P.Measure then
        local cx, cy, w, h = P.Measure(set.host)
        if cx then
            set.host:ClearAllPoints()
            set.host:SetPoint("CENTER", canvas, "CENTER", -cx, -cy)
            P.Resize(w + 6, h + 6)
        end
    end
end

local function ReplayPreview(canvas, P)
    local NP = ns.Nameplates
    local S = NP.Sample
    local st = P.store
    st.serial = st.serial + 1
    local mine = st.serial
    local function Stale() return st.serial ~= mine end
    local mode = ModeOf(P)
    local set = st.sets[mode]
    local scenes = S.SCENES[mode]
    if mode == "target" then
        -- the target moves here from the plate below: the fade, the size
        -- and the marks' entrance play as they would in a fight
        for i, s in ipairs(scenes) do
            S.Fill(set.plates[i], setmetatable({ target = (i == 2) }, { __index = s }), false)
        end
        for i, s in ipairs(scenes) do
            S.Fill(set.plates[i], s, true)
            S.Arrow(set.host, set.plates[i], s.arrow)
        end
        S.ShowRow(set.plates[1], true)
    elseif mode == "casting" then
        for i, f in ipairs(set.plates) do S.ReplayCast(f, scenes[i], i == 1, Stale) end
    else
        for _, f in ipairs(set.plates) do
            if NP.FX then NP.FX.Appear(f) end
        end
        if set.warnBox and set.warnBox:IsShown() and ns.Motion then
            local spec = NP.DB().anim.prioWarn
            if spec and spec.style ~= "none" then ns.Motion.Show(set.warnBox, spec) end
        end
    end
end

-- ============================================================
-- SOFT TARGET - the cvar manager, the next-up picker and the arrows
-- (NP_SoftTarget). Its block sits under ZacUIDB.nameplates like the
-- rest, but the engine has nothing to re-fit for it, so every control
-- refreshes the module itself.
-- ============================================================
local function SoftTargetSection(L)
    local ST = ns.SoftTarget
    L:Card("Soft target")
    if not ST or not ST.DB then
        L:Desc("The soft-target module did not load.")
        L:EndCard()
        return
    end
    local s = ST.DB()
    if not s then
        L:Desc("Settings are not available yet.")
        L:EndCard()
        return
    end
    local Refresh = ST.Refresh
    local function SkullRefresh()
        ST.ResetSkull()
        ST.Refresh()
    end

    BindCheck(L, s, "instanceOnly", "Only active in raids and dungeons",
        "Ticked, the whole tab system (soft targeting, arrows, skulls, plate "
        .. "distance) arms only inside dungeons and raids and switches itself "
        .. "off in the open world. Untick to run it everywhere. Applies at "
        .. "the next loading screen, or at once when toggled here.", Refresh)
    BindCheck(L, s, "softTarget", "Mark the enemy the game is soft-targeting",
        "With nothing targeted: marks who you would pick up (the game's soft "
        .. "target). While targeting: the game will not soft-track a second "
        .. "mob, so the next-mob option below switches to ZacUI's own pick - "
        .. "your next mob by its ordering. Your target frame and normal "
        .. "targeting are never touched.", Refresh)
    BindCheck(L, s, "maxPlates", "Max nameplate distance while this is on",
        "Tab grabs mobs out to about 40 yards, but the picker can only rank mobs "
        .. "that have nameplates. This holds plates at the 41 yard cap (your old "
        .. "value comes back when unticked).", Refresh)
    BindCheck(L, s, "untargetedMark", "Mark the target you would pick up when nothing is targeted",
        "Off: soft targeting is never armed at all (the game's own behaviour "
        .. "while untargeted). The next-mob marker below works either way.", Refresh)
    BindCheck(L, s, "fullTime", "Full-time mode - stays on while you fight",
        "On: never disarms, a soft pick lives alongside your hard target with "
        .. "the game's own circle, and hops to the next mob on kills. Off: soft "
        .. "targeting only while untargeted, with the arrows doing the marking.", Refresh)

    local srStatus
    if ST._srSupported == false then
        srStatus = "|cffff6666not supported by this client|r - the cap does nothing here"
    elseif ST._srSupported then
        srStatus = "|cff66ff66active|r - soft targeting will not grab mobs beyond this"
    else
        srStatus = "|cffcccc66not applied yet|r - arms next time you are untargeted out of combat"
    end
    BindSlider(L, s, "softRange", "Soft target max range", {
        min = 10, max = 45, step = 5, refresh = Refresh,
        format = function(v) return v .. " yd" end,
        desc = "How far soft targeting will pick up a mob (" .. srStatus .. "). "
            .. "The Tab key still reaches about 40 yards whatever this says." })

    BindCheck(L, s, "nextUp", "Mark my next mob",
        "Ranked by distance from the centre of your screen - the rule Tab "
        .. "uses - wherever the game lets ZacUI read plate positions (it falls "
        .. "back to nearest-first with mobs on you at the top). Your current "
        .. "target and the two before it are skipped, like Tab. Click the "
        .. "marked plate (or tab) to take it.", Refresh)
    local scStatus
    if ST._scrBlockedT then
        scStatus = "|cffff6666blocked in this zone|r - ranking by range"
    elseif ST._scrEverOK then
        scStatus = "|cff66ff66active|r - ranking by distance from screen centre"
    else
        scStatus = "|cffcccc66not sampled yet|r - needs a target and visible plates for a moment"
    end
    L:Desc("Screen-centre reading here: " .. scStatus .. ".")
    BindCheck(L, s, "nextSkull", "Also put Skull on the next mob",
        "Raid-marks the pick so it is obvious in the pile. Works solo or as "
        .. "party lead; does nothing when you cannot mark.",
        SkullRefresh)
    L:EndCard()

    -- ============================================================
    L:Card("Soft target arrows")
    BindCheck(L, s, "softMarker", "Use ZacUI's coloured arrows",
        "Off: the game's own plain icon.", Refresh)
    local curRow = BindColor(L, s, "curColor", "Current arrow", { refresh = Refresh })
    BindPresetRow(L, s, "curColor", ST.COLOR_PRESETS, Refresh, curRow)
    local nextRow = BindColor(L, s, "softColor", "Next arrow", { refresh = Refresh })
    BindPresetRow(L, s, "softColor", ST.COLOR_PRESETS, Refresh, nextRow)
    L:Desc("Current sits over the mob you are on (hard or soft target); next "
        .. "sits over the picker's next mob. Both have a 1 pixel black outline "
        .. "at any size. The pulse is on the Animation tab.")
    BindSlider(L, s, "markerSize", "Arrow size", { min = 16, max = 72, step = 2,
        refresh = Refresh, format = PX,
        desc = "Arrows grow upward from the same spot, so making them bigger "
            .. "never shifts the plate or anything on it." })
    BindCheck(L, s, "markerClearAuras", "Keep arrows clear of the debuff icons",
        "Off by default - the arrows already draw on top of the debuff icons. "
        .. "On lifts them above the debuff rows instead.", Refresh)
    BindSlider(L, s, "markerOffX", "Arrow position - sideways", {
        min = -60, max = 60, refresh = Refresh, format = PX })
    BindSlider(L, s, "markerOffY", "Arrow position - height above plate", {
        min = -40, max = 80, refresh = Refresh, format = PX,
        desc = "Moves both arrows on every plate. 0 / 4 is the standard spot "
            .. "(centred, just above the plate)." })
    L:EndCard()

    -- ============================================================
    L:Card("Fighting with the marker up (macro mode)")
    L:Desc("Instead of hard-targeting, aim your attacks at the soft target "
        .. "with a macro. With no hard target the marker never collapses, so "
        .. "it stays on screen the whole fight. Macro pattern:")
    L:Desc("|cffcccccc/cast [@softenemy,harm,nodead][] Heroic Strike|r")
    local row = UI.Holder(L.current)
    row:SetSize(300, M.BUTTON_H)
    local mk = UI.Button(row, "Create RCSoft template macro", { width = 200,
        tooltip = "Makes (or updates) a general macro called RCSoft with the "
            .. "pattern above; swap YourAbility for a real spell in "
            .. "Esc > Macros, then copy the pattern for each attack.",
        onClick = function()
            if InCombatLockdown() then
                Print("can't edit macros in combat.")
                return
            end
            local body = "#showtooltip\n/cast [@softenemy,harm,nodead][] YourAbility"
            local idx = GetMacroIndexByName and GetMacroIndexByName("RCSoft") or 0
            if idx and idx > 0 then
                pcall(EditMacro, idx, "RCSoft", "INV_Misc_QuestionMark", body)
                Print("updated the RCSoft template - swap YourAbility for a "
                    .. "real spell in Esc > Macros.")
            else
                local ok, res = pcall(CreateMacro, "RCSoft", "INV_Misc_QuestionMark", body, nil)
                if ok and res then
                    Print("created the RCSoft template - swap YourAbility for a "
                        .. "real spell in Esc > Macros, then copy the pattern "
                        .. "for each attack.")
                else
                    Print("couldn't create the macro (general macro list may be full).")
                end
            end
        end })
    mk:SetPoint("LEFT")
    L:Row(row, M.BUTTON_H + 4)
    L:Desc("The [] fallback means the same macro still works normally "
        .. "whenever you do have a target. /zui soft opens the soft target "
        .. "tools (dump, grassy, set, off).")
    L:EndCard()
end

-- ============================================================
-- CROSSHAIR - lines from the screen edges in to the target's plate
-- (NP_Crosshair). It draws over the world itself, so it is seen on
-- screen rather than in the preview.
-- ============================================================
local CH_MODES = {
    { value = "target",         text = "While I have an attackable target" },
    { value = "combat",         text = "In combat" },
    { value = "targetOrCombat", text = "Target or combat" },
    { value = "always",         text = "Always" },
}
local CH_LENGTHS = {
    { value = "full",  text = "Full screen" },
    { value = "short", text = "Short arms (200 px out from the plate)" },
    { value = "none",  text = "No lines (frame only)" },
}
local CH_FRAMES = {
    { value = "none",    text = "None" },
    { value = "box",     text = "Box" },
    { value = "corners", text = "Corner brackets" },
    { value = "ring",    text = "Ring (circle)" },
    { value = "oval",    text = "Oval (hugs the plate)" },
    { value = "dots",    text = "Dotted ring" },
    { value = "ticks",   text = "Four ticks" },
    { value = "arrows",  text = "Four arrows pointing in" },
}
local CH_FOLLOWS = {
    { value = "target", text = "My target's nameplate" },
    { value = "soft",   text = "Target, else the soft target's nameplate" },
    { value = "center", text = "Fixed screen centre (never follows)" },
}
local CH_PRESETS = {
    { name = "Red",   color = { 1, 0.2, 0.2 } },
    { name = "Green", color = { 0.3, 1, 0.35 } },
    { name = "White", color = { 1, 1, 1 } },
}

local function CrosshairSection(L)
    local CH = ns.Crosshair
    L:Card("Crosshair")
    if not CH or not CH.DB then
        L:Desc("The crosshair module did not load.")
        L:EndCard()
        return
    end
    local c = CH.DB()
    if not c then
        L:Desc("Settings are not available yet.")
        L:EndCard()
        return
    end
    local Refresh = CH.Refresh

    BindCheck(L, c, "enabled", "Show the crosshair",
        "Thin lines from the screen edges in to your target's nameplate, "
        .. "stopping at its edges and following it around. It draws over the "
        .. "world itself: turn it on and target something to see it.",
        Refresh)
    BindDropdown(L, c, "follow", "Cross sits on", CH_FOLLOWS, nil, Refresh)
    BindDropdown(L, c, "mode", "Show", CH_MODES, nil, Refresh)
    BindDropdown(L, c, "length", "Length", CH_LENGTHS, nil, Refresh)
    L:EndCard()

    -- ============================================================
    L:Card("Crosshair look")
    BindSlider(L, c, "thickness", "Line thickness", { min = 1, max = 8,
        refresh = Refresh, format = PX, desc = "1 is a hairline." })
    BindSlider(L, c, "gap", "Gap from the plate", { min = 0, max = 30,
        refresh = Refresh, format = PX,
        desc = "Air between the plate's edge and where each line stops." })
    BindCheck(L, c, "outline", "Soft shadow round the lines",
        "A faint dark edge along each line and the centre dot, so even a "
        .. "hairline stands out on a bright or busy background.", Refresh)
    BindSlider(L, c, "alpha", "Opacity", PctOpts(0.6, { min = 10, max = 100, step = 5, refresh = Refresh }))
    local colRow = BindColor(L, c, "color", "Colour", { refresh = Refresh })
    BindPresetRow(L, c, "color", CH_PRESETS, Refresh, colRow)
    L:EndCard()

    -- ============================================================
    L:Card("Reticle frame")
    L:Desc("A shape drawn around the plate itself, with the lines or instead "
        .. "of them. It follows the plate's size.")
    BindDropdown(L, c, "frame", "Shape", CH_FRAMES, nil, Refresh)
    BindSlider(L, c, "framePad", "Padding from the plate", { min = 0, max = 40,
        refresh = Refresh, format = PX })
    BindSlider(L, c, "frameThickness", "Frame thickness", { min = 1, max = 8,
        refresh = Refresh, format = PX })
    BindCheck(L, c, "frameOwnColor", "Frame has its own colour",
        "Off, the frame takes the lines' colour, range and warning colours included.",
        Refresh)
    BindColor(L, c, "frameColor", "Frame colour", { refresh = Refresh })
    BindCheck(L, c, "centerDot", "Centre dot",
        "A dot in the middle of the plate, in the frame's colour.", Refresh)
    BindSlider(L, c, "centerDotSize", "Dot size", { min = 2, max = 16,
        refresh = Refresh, format = PX })
    L:EndCard()

    -- ============================================================
    L:Card("Colour by range and position")
    BindCheck(L, c, "rangeColor", "Colour by melee range",
        "Lines turn the first colour while an enemy you can attack is in "
        .. "melee range and the second when it is out. Friendly targets, "
        .. "and anything the game can't give a range for, use the colour above.",
        Refresh)
    BindColor(L, c, "inColor", "In melee range", { refresh = Refresh })
    BindColor(L, c, "outColor", "Out of melee range", { refresh = Refresh })
    BindCheck(L, c, "posWarn", "Warn when I am in front of the target",
        "When it parries or blocks one of your attacks (which a mob can only "
        .. "do from the front), or swings at you in melee. The lines hold the "
        .. "colour below for 3 seconds and sit on top of the range colours. "
        .. "Leave it off when you tank.", Refresh)
    BindColor(L, c, "frontColor", "I am in front of it", { refresh = Refresh })
    L:EndCard()

    -- ============================================================
    L:Card("Leave these alone")
    L:Desc("Units the cross treats differently, by name. 'No cross' hides it "
        .. "while that unit is your target - a boss where there is nothing to "
        .. "line up. 'No warning' keeps the cross but never changes its colour "
        .. "for that unit being on you. Click the tag on a row to switch.")
    local names = {}
    for n in pairs(c.skip) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        local row = UI.Holder(L.current)
        row:SetSize(340, 18)
        local fs = UI.Font(row, F.LABEL, { text = n:gsub("^%l", string.upper) })
        fs:SetPoint("LEFT")
        local mode = c.skip[n]
        local tag = UI.Button(row, mode == "hide" and "no cross" or "no warning", {
            width = 86, height = 16, size = F.SMALL,
            tooltip = "Click to switch.",
            onClick = function()
                c.skip[n] = (c.skip[n] == "hide") and "warn" or "hide"
                Refresh()
                RefreshConfig()
            end })
        tag:SetPoint("LEFT", fs, "RIGHT", 10, 0)
        local del = UI.Button(row, "x", { width = 16, height = 14, size = F.SMALL,
            onClick = function()
                c.skip[n] = nil
                Refresh()
                RefreshConfig()
            end })
        del:SetPoint("LEFT", tag, "RIGHT", 6, 0)
        L:Row(row, 20)
    end
    if #names == 0 then L:Desc("Nothing yet.") end

    local add = UI.Holder(L.current)
    add:SetSize(360, M.BUTTON_H)
    local eb = UI.EditBox(add, { width = 150, hint = "unit name" })
    eb:SetPoint("LEFT")
    local function AddName(n)
        n = n and n:gsub("^%s+", ""):gsub("%s+$", "")
        if not n or n == "" then return end
        c.skip[n:lower()] = c.skip[n:lower()] or "hide"
        if eb.SetText then eb:SetText("") end
        Refresh()
        RefreshConfig()
    end
    local addBtn = UI.Button(add, "Add", { width = 50,
        onClick = function() AddName(eb.GetText and eb:GetText()) end })
    addBtn:SetPoint("LEFT", eb, "RIGHT", 6, 0)
    local tgtBtn = UI.Button(add, "Add my target", { width = 100,
        tooltip = "Adds whatever you have targeted right now.",
        onClick = function()
            local n = UnitExists("target") and UnitName("target")
            if not n then Print("no target.") return end
            AddName(n)
        end })
    tgtBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    L:Row(add, M.BUTTON_H + 4)
    L:EndCard()
end

-- debuff group choices
local MODE = { { text = "One icon (first present)", value = "single" }, { text = "Row (every present one)", value = "row" } }
local ATTACH = { { text = "Bar centre", value = "center" }, { text = "Bar's left edge", value = "left" },
    { text = "Bar's right edge", value = "right" }, { text = "Bar top", value = "top" }, { text = "Bar bottom", value = "bottom" },
    { text = "Under the bar, from its left corner", value = "bottomleft" },
    { text = "Under the bar, from its right corner", value = "bottomright" },
    { text = "Over the bar, from its left corner", value = "topleft" },
    { text = "Over the bar, from its right corner", value = "topright" } }
local PACKAT = { { text = "Under the bar, straight after the debuff row", value = "after" },
    { text = "Under the bar, from its right corner (grows left)", value = "bottomright" },
    { text = "A spot measured from the bar's centre", value = "center" } }
local GROW = { { text = "Right", value = "right" }, { text = "Left", value = "left" }, { text = "Up", value = "up" }, { text = "Down", value = "down" } }
local TPOS = { { text = "Beside the count", value = "beside" }, { text = "Under the count", value = "under" } }

-- which side's texts the Text tab shows (window state, not a setting)
local function TextSide()
    ZacUIDB.config = ZacUIDB.config or {}
    local v = ZacUIDB.config.npTextSide
    return (v == "friendly") and "friendly" or "enemy"
end

-- the part the Position tab's fine placement is on (window state)
local function PartPick()
    ZacUIDB.config = ZacUIDB.config or {}
    local v = ZacUIDB.config.npPart
    local NP = ns.Nameplates
    for _, k in ipairs(NP and NP.ANCHOR_PARTS or {}) do if k == v then return v end end
    return "castbar"
end

-- ============================================================
-- PAGE
-- ============================================================
RegisterPage("Nameplates", function(L)
    local NP = ns.Nameplates
    L:Header("Nameplates",
        "Health, cast bars, debuffs, threat colours, target marks and scripts. "
        .. "The preview shows sample plates with every change as you make it.")

    if not NP then
        L:Notice("missing", "The nameplate engine did not load.")
        return
    end
    local d = NP.DB()

    if not (ZacUIDB.modules and ZacUIDB.modules.nameplates) then
        L:Notice("off", "The Nameplates module is off; these settings apply the moment it is on.", "Modules > HUD", "nameplates")
    end

    if NP.Sample then
        L:Preview({
            key = "nameplates.plates",
            title = "Nameplates",
            width = 420, height = 90,
            modes = MODES,
            modesLabel = "Show",
            build = BuildPreview,
            update = UpdatePreview,
            replay = ReplayPreview,
        })
    end

    -- a sample element picked in the preview: its controls (the texts on
    -- Text, the parts on Position with the part picked)
    if ns.CustomPick then
        ns.CustomPick.SetHandler("nameplates.plates", function(el)
            local k = type(el) == "string" and el:match("^np%.(.+)$")
            if not k then return end
            ZacUIDB.config = ZacUIDB.config or {}
            local cfgw = ZacUIDB.config
            cfgw.tabs = cfgw.tabs or {}
            local isPart = false
            for _, pk in ipairs(NP.ANCHOR_PARTS or {}) do if pk == k then isPart = true end end
            if k == "health" then
                -- the bar itself: its edge and its states are on Look
                cfgw.tabs.nameplates = "look"
            elseif isPart then
                cfgw.tabs.nameplates = "pos"
                cfgw.npPart = k
            else
                cfgw.tabs.nameplates = "text"
            end
            RefreshConfig()
        end)
    end

    local NPD = NP.Debuffs
    local dc = NPD and NPD.Cfg and NPD.Cfg()
    local DApply = NPD and NPD.Apply or NPRefresh

    -- ============================================================
    -- GENERAL
    -- ============================================================
    local function Tab_general(L)
        L:Card("Plates")
        BindCheck(L, d, "friendlyNpcPlates", "Friendly NPC plates",
            "Uses the game's own setting, so it applies out of combat.")
        BindCheck(L, d, "stacking", "Stacking plates",
            "Plates push each other apart instead of overlapping.")
        BindSlider(L, d, "maxDistance", "Plate distance", { min = 20, max = 41,
            format = function(v) return v .. " yd" end,
            desc = "How far away plates still show. 41 yards is the cap." })
        L:EndCard()

        L:Card("Enemy plates")
        BindCheck(L, d.enemy, "castbar", "Show the cast bar")
        BindCheck(L, d.enemy, "levelShow", "Show the level on NPCs")
        BindCheck(L, d.enemy, "percent", "Show the health percent")
        BindCheck(L, d.enemy, "barClassColor", "Class colour player bars",
            "Enemy players' bars in their class colour.")
        BindCheck(L, d.enemy, "nameClassColor", "Class colour player names")
        L:EndCard()

        L:Card("Friendly plates")
        BindCheck(L, d.friendly, "nameOnly", "Name only - no bar",
            "Friendly players are just a class-coloured name. Untick to give "
            .. "them real health bars (sizes on the Look tab).")
        BindCheck(L, d.friendly, "castbar", "Show the cast bar")
        BindCheck(L, d.friendly, "levelShow", "Show the level on NPCs")
        BindCheck(L, d.friendly, "percent", "Show the health percent")
        BindCheck(L, d.friendly, "barClassColor", "Class colour player bars")
        BindCheck(L, d.friendly, "nameClassColor", "Class colour player names")
        L:EndCard()

        L:Card("Your target")
        BindCheck(L, d.target, "highlight", "Highlight your target",
            "A glow above and below your target's bar (colour on the Look tab).")
        BindCheck(L, d.target, "hover", "Mouseover glow",
            "A light sheen on the plate under your cursor.")
        BindCheck(L, d.target, "softTarget", "Soft target counts as your target",
            "With no hard target, the mob your next ability would hit gets the "
            .. "full target treatment - glow, size and fade.")
        BindCheck(L, d.extras, "targetArrows", "Mark your target's plate",
            "An outline, corners or arrows round your target's bar (look on the Look tab).")
        L:EndCard()

        L:Card("Fading the rest")
        BindCheck(L, d.target, "nonTargetFade", "Fade everything else",
            "Every plate that is not your target drops to the opacity on the "
            .. "Look tab, so the one you are on is the only plate at full strength.")
        BindCheck(L, d.target, "bossNoFade", "Bosses never fade",
            "A skull-level or world boss keeps its plate at full strength while "
            .. "you are on something else, and takes the important bar colour "
            .. "with threat on the border.")
        local nfTitle = UI.Font(L.current, F.LABEL, { text = "Mobs that never fade (comma between each)" })
        L:Row(nfTitle, 16)
        local nfBox = UI.EditBox(L.current, { width = 300, text = d.target.noFadeNames or "",
            hint = "Deathknight Captain",
            onChange = function(v) d.target.noFadeNames = v; NPRefresh() end,
            onEnter = function(v) d.target.noFadeNames = v; NPRefresh() end })
        L:Row(nfBox, (M.EDIT_H or 20) + 8)
        L:Desc("These never fade and take the important bar colour (threat on the "
            .. "border); no size change and no count. For bigger and counted, use "
            .. "Priority mobs below.")
        BindCheck(L, d.target, "combatOnly", "Fade and size change only in combat",
            "Out of combat every plate stays full size and full opacity; the glow "
            .. "still marks your target. Stops always-on soft targeting from making "
            .. "plates pulse as you walk past mobs.")
        -- the fade on the standard's visibility shape (d.visibility):
        -- nothing saved = the switches above
        local vg, vs = NPAccess(d, "visibility", nil)
        L:Add(UI.VisibilityPicker(L.current, { width = UI.CardInnerWidth(L), get = vg, set = vs,
            label = "Faded plates' opacity", fields = { alpha = true, combatAlpha = true },
            defaults = function() return NP.FadeDefaults() end }), 6)
        L:Desc("Every plate but your target while you have one. Until you set these "
            .. "they follow the switches above.")
        L:EndCard()

        L:Card("Priority mobs")
        L:Desc("Plates for these mobs never fade, grow, sit above every other "
            .. "plate and take their own colour - for adds that have to die "
            .. "first, like the Lightning Totems in Naxxramas. The click box "
            .. "stays the same size, so a /tar macro is the surest grab.")
        BindCheck(L, d.priority, "enabled", "Highlight priority mobs")
        local title = UI.Font(L.current, F.LABEL, { text = "Mob names (comma between each)" })
        L:Row(title, 16)
        local eb = UI.EditBox(L.current, { width = 300, text = d.priority.names or "",
            hint = "Lightning Totem",
            onChange = function(v) d.priority.names = v; NPRefresh() end,
            onEnter = function(v) d.priority.names = v; NPRefresh() end })
        L:Row(eb, (M.EDIT_H or 20) + 8)
        BindCheck(L, d.priority, "recolor", "Important plates take their own bar colour",
            "These mobs, the never-fade list and bosses: the bar takes the "
            .. "priority colour, and the threat colour moves to a border round it.")
        BindCheck(L, d.priority, "countWarn", "Count them mid-screen when two or more are up",
            "A line like \"Embalming Slime x2\" while that many priority plates "
            .. "are up - one left stays quiet.")
        BindSlider(L, d.priority, "countFrom", "From how many", { min = 2, max = 6 })
        L:EndCard()

        L:Card("Threat")
        BindCheck(L, d.threat, "enabled", "Colour bars by threat",
            "In combat the bar shows whose the mob is. Auto reads your stance - "
            .. "Defensive Stance or Bear Form means the tank colours.")
        BindDropdown(L, d.threat, "role", "Colours for", {
            { text = "Auto (by stance)", value = "AUTO" },
            { text = "Always tank", value = "TANK" },
            { text = "Always damage / healer", value = "DPS" },
        })
        BindCheck(L, d.threat, "glow", "Aggro alarm glow",
            "|cffff9900Off by default.|r A steady sheen on plates whose threat "
            .. "is an alarm. In a group with many players that is most things you "
            .. "hit, which is why it defaults off.")
        local tbd = d.threatBar
        BindCheck(L, tbd, "enabled", "Threat bar under the health bar",
            "A short strip under the bar's right corner that fills with your "
            .. "threat on that mob - 100% is the moment it turns on you. While "
            .. "you tank your target, it shows whoever is closest to taking it, "
            .. "with their name. Hidden out of combat.")
        BindCheck(L, tbd, "targetOnly", "Only on your target",
            "Off shows it on every enemy you are fighting.")
        BindCheck(L, tbd, "text", "Show the percent on the threat bar")
        L:EndCard()

        L:Card("Extras")
        BindCheck(L, d.extras, "raidMark", "Show raid markers",
            "Skull, cross and friends on the plate (spot on the Position tab).")
        BindCheck(L, d.extras, "targetName", "Mob's target under the bar",
            "Who each enemy is hitting, class coloured, in combat.")
        BindCheck(L, d.extras, "castTargetName", "Cast target on the cast bar",
            "'Fireball [Zacw]' instead of just 'Fireball'.")
        BindCheck(L, d.extras, "questIcon", "Quest mark",
            "A gold ! next to mobs your quest log still needs.")
        BindCheck(L, d.castbar, "icon", "Spell icon beside the cast bar")
        BindCheck(L, d, "smooth", "Smooth health",
            "The health fill glides to a new value instead of jumping (speed on "
            .. "the Animation tab).")
        L:EndCard()

        if dc then
            L:Card("Debuffs on enemy plates")
            L:Desc("Sunder stacks, Faerie Fire, curses, taunts and the rest, "
                .. "with their timers: the Sunder count big at the bar's right "
                .. "end, everything else as a row of small icons under the bar. "
                .. "Each group's look, text and spot are on their own tabs.")
            BindCheck(L, dc, "enabled", "Show debuffs on enemy plates", nil,
                function() NPD.SetEnabled(dc.enabled) end)
            local function RMRe()
                local RM = ns.RaidMods
                if RM and RM.Layout and RM.Layout.Replace then RM.Layout.Replace() end
                if NPD.RefreshAll then NPD.RefreshAll() end
                if NP.Preview and NP.Preview.Refresh then NP.Preview.Refresh() end
            end
            BindCheck(L, dc, "packStrip", "One strip for the raid mods' plate icons",
                "What the raid mods put on a mob's plate (Disarm, Enrage...) "
                .. "gathered into one row, scaled to match the debuff icons.", RMRe)
            L:EndCard()
            for _, g in ipairs(dc.groups) do
                L:Card(g.name or g.id)
                BindCheck(L, g, "enabled", "Show this group", nil, DApply)
                if g.enabled then
                    L:Desc("Which debuffs show in it (ticked ones):")
                    g.memberOn = g.memberOn or {}
                    for _, key in ipairs(g.members or {}) do
                        local entry = NPD.CATALOG[key]
                        local label = entry and entry.name or key
                        local w = UI.Checkbox(L.current, label, NPD.MemberEnabled(g, key), function(v)
                            if v then g.memberOn[key] = nil else g.memberOn[key] = false end
                            DApply()
                        end)
                        L:Row(w, 17)
                    end
                end
                L:EndCard()
            end
        end

        L:Card("Simple aura row (older)")
        L:Desc("The plates' first aura row, kept for anyone who used it. Leave it "
            .. "off while debuffs on enemy plates are on, or a mob shows its "
            .. "debuffs twice.")
        BindCheck(L, d.auras, "enabled", "Show the simple aura row")
        BindCheck(L, d.auras, "mineOnly", "Mine only",
            "Only auras you applied. Off shows everyone's.")
        BindSlider(L, d.auras, "max", "Most icons", { min = 1, max = 12 })
        L:EndCard()
    end

    -- ============================================================
    -- LOOK
    -- ============================================================
    local function Tab_look(L)
        L:Card("Textures")
        local function Tex(key, label, color)
            local w = UI.TexturePicker(L.current, { label = label, width = 260,
                get = function() local v = d[key] if v == false then return nil end return v end,
                set = function(name) d[key] = name or false NPRefresh() end,
                color = color })
            L:Add(w, 8)
            return w
        end
        Tex("healthTexture", "Health bar", function() return 0.2, 0.8, 0.2 end)
        Tex("castTexture", "Cast bar", function() local c = d.castbar.normal return c[1], c[2], c[3] end)
        local tt = UI.TexturePicker(L.current, { label = "Threat bar", width = 260,
            defaultLabel = "Same as the health bar",
            defaultPath = function() return NP.BarTexture("healthTexture") end,
            get = function() local v = d.threatTexture if v == false then return nil end return v end,
            set = function(name) d.threatTexture = name NPRefresh() end,
            color = function() local c = d.threatBar.safe return c[1], c[2], c[3] end })
        L:Add(tt, 8)
        L:Desc("ZacUI's texture is the one on Appearance > Fonts & Textures, which "
            .. "can set every part at once.")
        L:EndCard()

        L:Card("Bar background and border")
        local function ChromeColor(key, label, alpha, theme)
            local row = UI.Holder(L.current)
            row:SetSize(360, 18)
            local pick = UI.ColorPicker(row, { label = label, alpha = alpha,
                get = function()
                    local c = d[key]
                    if type(c) == "table" then return c end
                    return theme()
                end,
                set = ColorSet(d, key, alpha) })
            pick:SetPoint("LEFT")
            local reset = UI.Button(row, "Theme", { width = 56, height = 16, size = F.SMALL,
                tooltip = "Back to the theme's colour (Appearance > Colours).",
                onClick = function()
                    d[key] = nil
                    NPRefresh()
                    pick.Refresh()
                    if ns.SettingsChanged then ns.SettingsChanged("reset") end
                end })
            reset:SetPoint("LEFT", row, "LEFT", 200, 0)
            L:Row(row, 22)
        end
        ChromeColor("barBg", "Bar background", true, function()
            local w = ns.Col and ns.Col("windowBg") or { r = 0, g = 0, b = 0 }
            return { w.r, w.g, w.b, 0.85 }
        end)
        ChromeColor("borderColor", "Bar border", true, function()
            local b = ns.Col and ns.Col("border") or { r = 0, g = 0, b = 0, a = 1 }
            return { b.r, b.g, b.b, b.a or 1 }
        end)
        L:Desc("Behind and round the health, cast and threat bars. Until you pick "
            .. "one they follow the theme.")
        -- the edge on the standard's chrome shape (d.chrome): thickness,
        -- shadow and glow; nothing saved = today's 1 px edge, no extras
        local chg, chs = NPAccess(d, "chrome", nil)
        local chp = UI.ChromePicker(L.current, { width = UI.CardInnerWidth(L), get = chg, set = chs,
            fields = { borderSize = true, shadowSize = true, shadowColor = true, glowSize = true, glowColor = true },
            defaults = function() return NP.ChromeDefaults() end })
        L:Add(chp, 6)
        if ns.CustomPick then ns.CustomPick.RegisterGroup("np.health", chp) end
        L:EndCard()

        -- per-state looks (d.states): the important plate and the cast
        -- bar's states, over their usual colours
        L:Card("States")
        local stg, sts = NPAccess(d, "states", nil)
        L:Add(UI.StateEditor(L.current, { width = UI.CardInnerWidth(L), get = stg, set = sts,
            states = NP.STATE_LIST, remember = STATE_PICK,
            fields = { color = true, textColor = true, border = true },
            defaults = function() return NP.StateDefaults() end }), 6)
        L:Desc("Colour is the bar; text colour the spell name (the name on an important "
            .. "plate). Unset fields keep the colours above.")
        L:EndCard()

        L:Card("Enemy size")
        -- Enemy plates are the same size in and out of combat, so the
        -- sliders move both (combat sizes are what the engine reads in a
        -- fight, and a slider that only worked out of combat looked broken).
        local function EnemySize()
            d.enemy.combatWidth, d.enemy.combatHeight = d.enemy.width, d.enemy.height
            NPRefresh()
        end
        BindSlider(L, d.enemy, "width", "Bar width", { min = 60, max = 220, refresh = EnemySize, format = PX })
        BindSlider(L, d.enemy, "height", "Bar height", { min = 4, max = 32, refresh = EnemySize, format = PX,
            desc = "16 fits the name inside. The click box is separate (Position tab)." })
        BindSlider(L, d.enemy, "castWidth", "Cast bar width", { min = 60, max = 220, format = PX })
        BindSlider(L, d.enemy, "castHeight", "Cast bar height", { min = 4, max = 32, format = PX })
        L:EndCard()

        L:Card("Friendly size")
        BindSlider(L, d.friendly, "width", "Bar width", { min = 60, max = 220, format = PX })
        BindSlider(L, d.friendly, "height", "Bar height", { min = 4, max = 32, format = PX })
        BindSlider(L, d.friendly, "combatWidth", "Bar width in combat", {
            min = 60, max = 220, format = PX,
            desc = "Friendly plates can grow in combat: 124 x 12 resting, 142 x 16 fighting to begin with." })
        BindSlider(L, d.friendly, "combatHeight", "Bar height in combat", { min = 4, max = 32, format = PX })
        BindSlider(L, d.friendly, "castWidth", "Cast bar width", { min = 40, max = 220, format = PX })
        BindSlider(L, d.friendly, "castHeight", "Cast bar height", { min = 4, max = 32, format = PX })
        L:Desc("Only seen with Name only off (General tab).")
        L:EndCard()

        L:Card("Raid marker size")
        local function Auto(v) return v == 0 and "auto" or (v .. " px") end
        BindSlider(L, d.enemy, "markerSize", "On enemy plates", { min = 0, max = 32, format = Auto,
            desc = "Auto is a shade taller than the bar." })
        BindSlider(L, d.friendly, "markerSize", "On friendly plates", { min = 0, max = 32, format = Auto })
        L:EndCard()

        L:Card("Bar colours")
        L:Desc("Out of combat the plates use reaction colours:")
        BindColor(L, d.reaction, "hostile",  "Hostile")
        BindColor(L, d.reaction, "neutral",  "Neutral")
        BindColor(L, d.reaction, "friendly", "Friendly")
        BindColor(L, d, "tapped", "Tapped (someone else's kill)")
        L:Gap(6)
        L:Desc("In combat, with Colour bars by threat on (General tab):")
        BindColor(L, d.threat, "tankAggro",   "Tank: you have it")
        BindColor(L, d.threat, "tankNoAggro", "Tank: you lost it")
        BindColor(L, d.threat, "tankOther",   "Tank: another tank has it")
        BindColor(L, d.threat, "dpsAggro",    "Damage: you pulled it")
        BindColor(L, d.threat, "dpsNoAggro",  "Damage: safe")
        BindColor(L, d.threat, "pulling",     "Warning: about to change hands")
        BindColor(L, d.threat, "solo",        "Solo: mobs on you")
        BindColor(L, d.threat, "glowColor",   "Aggro alarm glow")
        L:EndCard()

        L:Card("Threat bar")
        local tbd = d.threatBar
        BindSlider(L, tbd, "width", "Width", { min = 10, max = 220, format = PX,
            desc = "Capped at the health bar's width; half of it to begin with." })
        BindSlider(L, tbd, "height", "Height", { min = 1, max = 12, format = PX })
        BindSlider(L, tbd, "warnAt", "Warning colour from", { min = 30, max = 99, step = 5, format = PCT })
        BindColor(L, tbd, "safe",    "Safe")
        BindColor(L, tbd, "warn",    "Warning")
        BindColor(L, tbd, "danger",  "At 100% - pulling")
        BindColor(L, tbd, "tanking", "You hold it (no one close)")
        L:EndCard()

        L:Card("Cast bar colours")
        L:Desc("Shared by enemy and friendly plates.")
        BindColor(L, d.castbar, "normal", "Cast")
        BindColor(L, d.castbar, "channel", "Channel")
        BindColor(L, d.castbar, "uninterruptible", "Can't be interrupted")
        BindColor(L, d.castbar, "interrupted", "Interrupted flash")
        BindCheck(L, d.castbar, "spark", "Spark on the moving edge",
            "A bright line where the cast bar is filling.")
        L:EndCard()

        L:Card("Target highlight")
        local c1 = BindColor(L, d.target, "color", "Glow colour")
        local s1 = BindSlider(L, d.target, "alpha", "Glow opacity", PctOpts(0.8, { min = 10, max = 100, step = 5 }))
        local s2 = BindSlider(L, d.target, "neonHeight", "Glow height", { min = 4, max = 30, format = PX })
        for _, w in ipairs({ c1, s1, s2 }) do UI.SetEnabled(w, d.target.highlight) end
        local c2 = BindColor(L, d.target, "hoverColor", "Mouseover glow colour")
        local s3 = BindSlider(L, d.target, "hoverAlpha", "Mouseover glow strength", PctOpts(0.2, { min = 5, max = 60, step = 5 }))
        UI.SetEnabled(c2, d.target.hover)
        UI.SetEnabled(s3, d.target.hover)
        BindSlider(L, d.target, "scale", "Target plate size", PctOpts(1, { min = 100, max = 150, step = 5,
            desc = "Your target's plate grows to this size; 100% turns the size change off." }))
        BindSlider(L, d.target, "nonTargetAlpha", "Faded plate opacity", PctOpts(1, { min = 10, max = 100, step = 5,
            desc = "Every other plate, while you have a target and Fade everything else is on." }))
        L:EndCard()

        L:Card("Target mark")
        BindDropdown(L, d.extras, "arrowStyle", "Look", ARROW_STYLES)
        BindDropdown(L, d.extras, "arrowColor", "Colour", ARROW_COLORS, nil, function()
            NPRefresh()
            RefreshConfig()
        end)
        if d.extras.arrowColor == "custom" then
            BindColor(L, d.extras, "arrowCustomColor", "Mark colour")
        end
        BindSlider(L, d.extras, "arrowScale", "Size", { min = 0.5, max = 2.5, step = 0.1,
            format = function(v) return math.floor(v * 100 + 0.5) .. "%" end })
        if not d.extras.targetArrows then L:Desc("Mark your target's plate is off (General tab).") end
        L:EndCard()

        L:Card("Important plates")
        BindColor(L, d.priority, "color", "Bar colour",
            { desc = "Priority mobs, the never-fade list and bosses, with Important plates take their own bar colour on." })
        BindSlider(L, d.priority, "edgeSize", "Threat border thickness", { min = 1, max = 6, format = PX })
        BindSlider(L, d.priority, "scale", "Priority mob size", PctOpts(1.8, { min = 100, max = 300, step = 10 }))
        L:EndCard()

        if dc then
            for _, g in ipairs(dc.groups) do
                if g.enabled then
                    L:Card((g.name or g.id) .. " - look")
                    BindDropdown(L, g, "mode", "Layout", MODE, nil, DApply)
                    BindCheck(L, g, "showIcon", "Show the icon", nil, DApply)
                    BindCheck(L, g, "showCount", "Show the stack count", nil, DApply)
                    BindCheck(L, g, "showTimer", "Show the time left", nil, DApply)
                    L:EndCard()
                end
            end
        end

        L:Card("Simple aura row (older)")
        BindSlider(L, d.auras, "width", "Icon width", { min = 10, max = 40, format = PX })
        BindSlider(L, d.auras, "height", "Icon height", { min = 8, max = 40, format = PX })
        BindSlider(L, d.auras, "spacing", "Space between icons", { min = 0, max = 10, format = PX })
        L:EndCard()

        -- ============================================================
        L:Card("NPC colours")
        L:Desc("Force a bar colour for specific creatures. Names fill in as you "
            .. "see each creature; entries without names have never been seen on "
            .. "this client.")
        local function NpcRow(id, label)
            local row = UI.Holder(L.current)
            row:SetSize(340, 16)
            local sw = UI.ColorPicker(row, { label = label,
                get = function() return d.npcColors[id] or { 1, 1, 1 } end,
                set = ColorSet(d.npcColors, id) })
            sw:SetPoint("LEFT")
            local del = UI.Button(row, "x", { width = 16, height = 14,
                size = F.SMALL,
                onClick = function()
                    d.npcColors[id] = nil
                    NPRefresh()
                    RefreshConfig()
                end })
            del:SetPoint("RIGHT")
            L:Row(row, 19)
        end
        local named, unnamed = {}, 0
        for id in pairs(d.npcColors) do
            if d.npcNames[id] then
                named[#named + 1] = id
            else
                unnamed = unnamed + 1
            end
        end
        table.sort(named, function(a, b)
            return (d.npcNames[a] or "") < (d.npcNames[b] or "")
        end)
        for _, id in ipairs(named) do
            NpcRow(id, ("%s  |cff888888(%d)|r"):format(d.npcNames[id], id))
        end
        if unnamed > 0 then
            L:Desc(("...plus %d not seen on this realm yet."):format(unnamed))
        end
        local addRow = L.current
        local addTarget = UI.Button(addRow, "Add current target", { width = 130,
            tooltip = "Adds whatever you are targeting, coloured white - then "
                .. "click its swatch to pick the colour.",
            onClick = function()
                local id = NP.NpcIdFromUnit and NP.NpcIdFromUnit("target")
                if not id then
                    Print("target something first (a creature, not a player).")
                    return
                end
                d.npcColors[id] = d.npcColors[id] or { 1, 1, 1 }
                d.npcNames[id] = UnitName("target")
                NPRefresh()
                RefreshConfig()
            end })
        local purge = UI.Button(addRow, "Drop unseen entries", { width = 140,
            tooltip = "Removes every entry whose creature has never been "
                .. "seen on this client.",
            onClick = function()
                local dropped = 0
                for id in pairs(d.npcColors) do
                    if not d.npcNames[id] then
                        d.npcColors[id] = nil
                        dropped = dropped + 1
                    end
                end
                Print(dropped .. " unused npc colours removed.")
                NPRefresh()
                RefreshConfig()
            end })
        L:Flow({ addTarget, purge }, 8, 4)
        L:EndCard()

        -- ============================================================
        L:Card("Cast alerts")
        L:Desc("Force a cast bar colour for specific spells.")
        local alertIds = {}
        for id in pairs(d.castAlerts) do alertIds[#alertIds + 1] = id end
        table.sort(alertIds)
        for _, id in ipairs(alertIds) do
            local row = UI.Holder(L.current)
            row:SetSize(340, 16)
            local spellName = GetSpellInfo and GetSpellInfo(id)
            local sw = UI.ColorPicker(row, {
                label = ("%s  |cff888888(%d)|r"):format(spellName or "?", id),
                get = function() return d.castAlerts[id] or { 1, 0.1, 0.1 } end,
                set = ColorSet(d.castAlerts, id) })
            sw:SetPoint("LEFT")
            local del = UI.Button(row, "x", { width = 16, height = 14,
                size = F.SMALL,
                onClick = function()
                    d.castAlerts[id] = nil
                    NPRefresh()
                    RefreshConfig()
                end })
            del:SetPoint("RIGHT")
            L:Row(row, 19)
        end
        local castAdd = UI.Holder(L.current)
        castAdd:SetSize(320, M.BUTTON_H)
        local eb = UI.EditBox(castAdd, { width = 110, hint = "spell ID" })
        eb:SetPoint("LEFT")
        local addBtn = UI.Button(castAdd, "Add", { width = 60,
            onClick = function()
                local id = tonumber(eb.GetText and eb:GetText() or "")
                if not id or not (GetSpellInfo and GetSpellInfo(id)) then
                    Print("that is not a spell id this client knows.")
                    return
                end
                d.castAlerts[id] = d.castAlerts[id] or { 1, 0.1, 0.1 }
                NPRefresh()
                RefreshConfig()
            end })
        addBtn:SetPoint("LEFT", eb, "RIGHT", 8, 0)
        L:Row(castAdd, M.BUTTON_H + 4)
        L:EndCard()
    end

    -- ============================================================
    -- TEXT
    -- ============================================================
    local function Tab_text(L)
        L:Card("Plate font")
        local face = UI.Field(L.current, "Font for every plate text", function(h)
            return UI.FontFaceDropdown(h, { width = 260, defaultLabel = "ZacUI's font",
                get = function() local v = d.fontName if v == false then return nil end return v end,
                set = function(v) d.fontName = v or false NPRefresh() RefreshConfig() end })
        end, { width = 260 })
        L:Add(face, 8)
        L:Desc("Each text below starts in this font; give any of them a font of "
            .. "its own. ZacUI's font is the one on Appearance > Fonts & Textures.")
        L:EndCard()

        local side = TextSide()
        local cfg = d[side]
        local en = side == "enemy"
        L:Card("Which plates")
        local sideDD = UI.Field(L.current, "Plates", function(h)
            return UI.Dropdown(h, { width = 200,
                items = function() return { { text = "Enemy plates", value = "enemy" }, { text = "Friendly plates", value = "friendly" } } end,
                selected = function() return TextSide() == "friendly" and "Friendly plates" or "Enemy plates" end,
                selectedValue = TextSide,
                onSelect = function(v) ZacUIDB.config.npTextSide = v RefreshConfig() end })
        end, { width = 200 })
        L:Add(sideDD, 10)
        L:Desc("Every text below: its font, colour and spot on these plates.")
        L:EndCard()

        -- one group per text: font, colour, format and its spot on the plate
        local function Text(title, o, desc)
            L:Card(title)
            local el = o.key
            o.key = "np." .. el
            o.anchorGet, o.anchorSet = NPAccess(cfg, "anchors", el)
            o.anchorDefaults = o.anchorDefaults or NPAnchorDef(side, el)
            o.targets = o.targets or NPTargets(el)
            o.defaultTargetLabel = "Where it sits now"
            o.fontDefaultLabel = "Plate font"
            o.anchorMin, o.anchorMax = o.anchorMin or -150, o.anchorMax or 150
            UI.TextElement(L, o)
            if desc then L:Desc(desc) end
            L:EndCard()
        end

        local fg, fs, fd = FontAccess(cfg, "nameSize", "nameFont", en and 11 or 10)
        Text("Name", { key = "name", fontGet = fg, fontSet = fs, fontDefaults = fd, minSize = 6, maxSize = 20,
            sample = "Deathknight Captain",
            colors = { ColorEntry(cfg, "nameColor", "Name colour") } },
            "The colour is for names that are not class coloured.")

        fg, fs, fd = FontAccess(cfg, "levelSize", "levelFont", en and 10 or 9)
        Text("Level", { key = "level", fontGet = fg, fontSet = fs, fontDefaults = fd, minSize = 6, maxSize = 20,
            sample = "60  61  ??" })

        fg, fs, fd = FontAccess(cfg, "percentSize", "percentFont", en and 9 or 8)
        local pfg, pfs = NPAccess(cfg, "formats", "percent")
        Text("Health percent", { key = "percent", fontGet = fg, fontSet = fs, fontDefaults = fd, minSize = 6, maxSize = 16,
            sample = "62%  100%",
            colors = { ColorEntry(cfg, "percentColor", "Percent colour") },
            formatGet = pfg, formatSet = pfs, formatDefaults = NP.PCT_FORMAT_DEFAULTS,
            formatKinds = { number = true, percent = true }, formatTokens = NP.PCT_FORMAT_TOKENS,
            formatSample = function(spec)
                return ns.FormatText(spec, NP.PCT_FORMAT_DEFAULTS,
                    { pct = 62.4, cur = 3120, max = 5000, deficit = 1880 }, NP.PCT_FORMAT_KINDS)
            end })

        fg, fs, fd = FontAccess(cfg, "castTextSize", "castFont", en and 9 or 8)
        Text("Spell name on the cast bar", { key = "castText", fontGet = fg, fontSet = fs, fontDefaults = fd,
            minSize = 6, maxSize = 16, sample = "Shadow Bolt [Zaccw]",
            colors = { ColorEntry(d.castbar, "textColor", "Spell name colour (all plates)") } })

        local tbd = d.threatBar
        fg, fs, fd = FontAccess(tbd, "textSize", "font", 8)
        Text("Threat bar percent", { key = "threatText", fontGet = fg, fontSet = fs, fontDefaults = fd,
            minSize = 6, maxSize = 14, sample = "Zacr 82%",
            colors = { ColorEntry(tbd, "textColor", "Threat percent colour") } },
            "Its font and colour are for every plate; its spot is for these plates.")

        fg, fs, fd = FontAccess(d.extras, nil, "targetNameFont", 8)
        Text("Mob's target under the bar", { key = "targetName", fontGet = fg, fontSet = fs, fontDefaults = fd,
            minSize = 6, maxSize = 20, sample = "Zaccw" },
            "Its font is for every plate. Left where it is, it steps down out of the way of the icons under the bar.")

        Text("Quest mark", { key = "quest" }, "It wears the name's font.")

        L:Card("Priority mob count")
        BindFont(L, "Priority mob count", d.priority, nil, "countFont", 22,
            { min = 10, max = 40, sample = "Lightning Totem x2" })
        L:Desc("Its spot on the screen is on the Position tab (Move it).")
        L:EndCard()

        L:Card("Simple aura row stack count")
        fg, fs, fd = FontAccess(d.auras, nil, "countFont", 8)
        local cag, cas = NPAccess(d.auras, "anchors", "count")
        UI.TextElement(L, { key = "np.auraCount", fontGet = fg, fontSet = fs, fontDefaults = fd,
            fontDefaultLabel = "Plate font", minSize = 6, maxSize = 20, sample = "5",
            anchorGet = cag, anchorSet = cas, anchorDefaults = NP.AURA_COUNT_DEF, anchorMin = -20, anchorMax = 20 })
        L:Desc("For every plate: where the number sits on each icon.")
        L:EndCard()

        if dc then
            for _, g in ipairs(dc.groups) do
                if g.enabled then
                    L:Card((g.name or g.id) .. " - text")
                    BindFont(L, "Count / icon size", g, "fontSize", "countFont", 11,
                        { min = 7, max = 40, refresh = DApply, sample = "5  3" })
                    BindFont(L, "Timer", g, "timerSize", "timerFont", math.max(7, math.floor((g.fontSize or 11) * 0.6)),
                        { min = 6, max = 30, refresh = DApply, sample = "25s  2m" })
                    BindDropdown(L, g, "timerPos", "Timer sits", TPOS, nil, DApply)
                    L:EndCard()
                end
            end
        end
    end

    -- ============================================================
    -- ANIMATION
    -- ============================================================
    local function Tab_anim(L)
        L:Card("Plates")
        L:Desc("Every plate animation is off to begin with - plates change at "
            .. "once, as they always have. Replay in the preview plays what you "
            .. "pick; the Target view shows the fade and size change. "
            .. "Appearance > Motion can switch every animation off or speed it up.")
        BindAnim(L, "appear", "When a plate appears", { "none", "fade", "pop" },
            "A plate coming into view fades in (or pops in) instead of appearing at once.")
        BindAnim(L, "fade", "Fading between plates", { "none", "fade" },
            "The opacity glides as your target moves and the rest fade behind it.")
        BindAnim(L, "scale", "Size change", { "none", "pop" },
            "Your target's plate (and a priority mob's) grows and shrinks smoothly. Pick an overshoot easing for a bounce.")
        BindSlider(L, d, "smoothRate", "Health glide speed", { min = 4, max = 40,
            desc = "How quickly the health fill catches up with a new value (with Smooth health on). 18 is the standard." })
        L:EndCard()

        L:Card("Your target")
        BindAnim(L, "target", "When a plate becomes your target",
            { "none", "fade", "slide", "pop", "pulse", "bounce", "flash" },
            "Plays on the target marks - the glow and the box or arrows - as they arrive on a new target.")
        L:EndCard()

        L:Card("Cast bar")
        BindAnim(L, "cast", "When a cast bar appears", { "none", "fade", "slide", "pop" })
        BindAnim(L, "interrupt", "When a cast is interrupted", { "none", "pulse", "flash", "bounce", "pop" },
            "A highlight on the bar as it turns the interrupted colour.")
        BindSlider(L, d.castbar, "interruptHold", "Interrupted flash stays up", { min = 0.1, max = 2, step = 0.05,
            format = function(v) return string.format("%.2fs", v) end })
        L:EndCard()

        L:Card("Priority mob count")
        BindAnim(L, "prioWarn", "When the count appears", { "none", "fade", "slide", "pop", "bounce", "pulse" })
        L:EndCard()

        local ST = ns.SoftTarget
        local s = ST and ST.DB and ST.DB()
        if s then
            L:Card("Soft target arrows")
            BindCheck(L, s, "markerPulse", "Pulse the arrows so they catch the eye", nil, ST.Refresh)
            BindSlider(L, s, "markerPulseTime", "Pulse speed", { min = 0.2, max = 1.5, step = 0.05,
                refresh = ST.Refresh, format = function(v) return string.format("%.2fs", v) end,
                desc = "Seconds to dim, and as long again to come back." })
            BindSlider(L, s, "markerPulseAlpha", "Pulse dims to", PctOpts(0.45, { min = 10, max = 90, step = 5,
                refresh = ST.Refresh }))
            L:EndCard()
        end
    end

    -- ============================================================
    -- POSITION
    -- ============================================================
    local function Tab_pos(L)
        L:Card("Sample plate on screen")
        local Pv = NP.Preview
        if Pv then
            local on = Pv.IsShown()
            local b = UI.Button(L.current, on and "Hide the sample plate" or "Show a sample plate on screen",
                { width = 240, onClick = function() Pv.Toggle() RefreshConfig() end })
            L:Row(b, M.BUTTON_H + 6)
            L:Desc("One target plate with everything on, on the screen itself, so you "
                .. "can line it up with the rest of your UI. Movable on the Movers "
                .. "page while it is up. Also /zui plate.")
        end
        L:EndCard()

        L:Card("Click box")
        BindSlider(L, d, "clickWidth", "Enemy click box width", { min = 40, max = 220, format = PX })
        BindSlider(L, d, "clickHeight", "Enemy click box height", { min = 1, max = 60, format = PX,
            desc = "The area that takes your clicks, apart from the bar you see. "
            .. "The friendly click box stays tiny so friendly plates never block clicks." })
        L:EndCard()

        L:Card("Enemy name and marker")
        BindDropdown(L, d.enemy, "namePos", "Name", NAME_POS,
            "Inside: level on the left, then the name, health percent on the "
            .. "right. Above: the name floats over the bar.")
        BindDropdown(L, d.enemy, "nameJustify", "Name alignment (inside)", NAME_JUSTIFY)
        BindDropdown(L, d.enemy, "markerPos", "Raid marker", MARKER_POS,
            "Left end of the bar puts it before the level; the level and name "
            .. "step right while a mark is up.")
        BindSlider(L, d.enemy, "markerY", "Marker height above the bar", { min = 0, max = 40, format = PX,
            desc = "Above only." })
        BindSlider(L, d.enemy, "markerX", "Marker sideways", { min = -60, max = 60, format = PX })
        L:EndCard()

        L:Card("Friendly name and marker")
        BindDropdown(L, d.friendly, "namePos", "Name (with a bar)", NAME_POS)
        BindDropdown(L, d.friendly, "nameJustify", "Name alignment (inside)", NAME_JUSTIFY)
        BindDropdown(L, d.friendly, "markerPos", "Raid marker", MARKER_POS)
        BindSlider(L, d.friendly, "markerY", "Marker height above the bar", { min = 0, max = 40, format = PX })
        BindSlider(L, d.friendly, "markerX", "Marker sideways", { min = -60, max = 60, format = PX })
        L:EndCard()

        L:Card("Threat bar")
        BindSlider(L, d.threatBar, "gap", "Gap below the health bar", { min = 0, max = 8, format = PX })
        L:EndCard()

        -- the simple aura row's icons, laid out (ZacUI's layout shape;
        -- nothing saved = one row left to right, as always)
        L:Card("Simple aura row (older)")
        local lg, ls = ns.CustomAccess(d.auras, "layout", nil, NPRefresh)
        L:Add(UI.LayoutPicker(L.current, { width = UI.CardInnerWidth(L), get = lg, set = ls,
            defaults = function()
                local gap = tonumber(d.auras.spacing) or 2
                return { grow = "RIGHT", wrap = "UP", perLine = 0, spacingX = gap, spacingY = gap }
            end,
            fields = { grow = true, wrap = true, perLine = true, spacingX = true, spacingY = true, reverse = true } }), 6)
        L:Desc("Where its icons go when there are several. Its spot over the plate is under Fine placement.")
        L:EndCard()

        -- every part, freely: any corner of anything on the plate, on top
        -- of the spots the cards above give it (the texts are on Text)
        local side = TextSide()
        local pcfg = d[side]
        L:Card("Fine placement of the plate's parts")
        local sideDD = UI.Field(L.current, "Plates", function(h)
            return UI.Dropdown(h, { width = 200,
                items = function() return { { text = "Enemy plates", value = "enemy" }, { text = "Friendly plates", value = "friendly" } } end,
                selected = function() return TextSide() == "friendly" and "Friendly plates" or "Enemy plates" end,
                selectedValue = TextSide,
                onSelect = function(v) ZacUIDB.config.npTextSide = v RefreshConfig() end })
        end, { width = 200 })
        L:Add(sideDD, 8)
        local part = PartPick()
        local partDD = UI.Field(L.current, "Part", function(h)
            return UI.Dropdown(h, { width = 200,
                items = function()
                    local out = {}
                    for _, k in ipairs(NP.ANCHOR_PARTS) do out[#out + 1] = { text = NP.ANCHOR_LABELS[k] or k, value = k } end
                    return out
                end,
                selected = function() return NP.ANCHOR_LABELS[PartPick()] or PartPick() end,
                selectedValue = PartPick,
                onSelect = function(v) ZacUIDB.config.npPart = v RefreshConfig() end })
        end, { width = 200 })
        L:Add(partDD, 10)
        local ag, as = NPAccess(pcfg, "anchors", part)
        local o = { key = "np." .. part, anchorGet = ag, anchorSet = as, anchorDefaults = NPAnchorDef(side, part),
            targets = NPTargets(part), defaultTargetLabel = "Where it sits now", anchorMin = -200, anchorMax = 200 }
        if part == "castIcon" then
            o.sizeLabel, o.sizeMin, o.sizeMax = "Icon size", 6, 48
            o.sizeGet = function() return tonumber(pcfg.castIconSize) or ((pcfg.castHeight or 14) + 6) end
            o.sizeSet = function(v) pcfg.castIconSize = v NPRefresh() end
        end
        UI.FrameElement(L, o)
        L:Desc("Reset puts the part back where the settings above place it.")
        L:EndCard()

        L:Card("Priority mob count")
        local mv = UI.Button(L.current, "Move it", { width = 100,
            tooltip = "Shows the count with a sample line and unlocks it to drag.",
            onClick = function()
                if NP.PriorityWarnDemo then NP.PriorityWarnDemo(true) end
                if ns.ToggleMover then ns.ToggleMover("prioWarn") end
            end })
        L:Row(mv, 26)
        L:EndCard()

        if dc then
            local function RMRe()
                local RM = ns.RaidMods
                if RM and RM.Layout and RM.Layout.Replace then RM.Layout.Replace() end
                if NPD.RefreshAll then NPD.RefreshAll() end
                if NP.Preview and NP.Preview.Refresh then NP.Preview.Refresh() end
            end
            if dc.packStrip then
                L:Card("Raid mod icons")
                BindDropdown(L, dc, "packAt", "Where", PACKAT, nil, RMRe)
                BindSlider(L, dc, "packX", "Sideways", { min = -200, max = 200, step = 1, refresh = RMRe, format = PX })
                BindSlider(L, dc, "packY", "Up / down", { min = -120, max = 120, step = 1, refresh = RMRe, format = PX })
                BindSlider(L, dc, "packScale", "Icon scale", { min = 0.3, max = 1.5, step = 0.05, refresh = RMRe,
                    format = function(v) return math.floor(v * 100 + 0.5) .. "%" end })
                L:EndCard()
            end
            for _, g in ipairs(dc.groups) do
                if g.enabled then
                    L:Card((g.name or g.id) .. " - position")
                    BindDropdown(L, g, "attach", "Measured from", ATTACH, nil, DApply)
                    if g.mode == "row" then BindDropdown(L, g, "growDir", "Row grows", GROW, nil, DApply) end
                    BindSlider(L, g, "offsetX", "Sideways", { min = -200, max = 200, step = 1, refresh = DApply, format = PX })
                    BindSlider(L, g, "offsetY", "Up / down", { min = -120, max = 120, step = 1, refresh = DApply, format = PX })
                    L:EndCard()
                end
            end
        end
    end

    -- ============================================================
    -- ADVANCED
    -- ============================================================
    local function Tab_adv(L)
        L:Card("Reset")
        local row = UI.Holder(L.current)
        row:SetSize(400, M.BUTTON_H)
        local reset = UI.Button(row, "Reset nameplates", { width = 170,
            tooltip = "Puts every nameplate setting back to ZacUI's defaults.",
            onClick = function()
                ZacUIDB.nameplates = nil
                NP.DB()
                NPRefresh()
                RefreshConfig()
                Print("nameplate options reset to the defaults.")
            end })
        reset:SetPoint("LEFT")
        if dc then
            local rg = UI.Button(row, "Reset debuff groups", { width = 170,
                tooltip = "The debuff groups back to their standard layout.",
                onClick = function() NPD.ResetGroups() RefreshConfig() end })
            rg:SetPoint("LEFT", reset, "RIGHT", 8, 0)
        end
        L:Row(row, M.BUTTON_H + 4)
        L:EndCard()

        if dc then
            L:Card("Custom debuffs")
            L:Desc("Any debuff by spell id; it joins the \"Under the bar\" row, "
                .. "muted until ticked there (General tab).")
            for key, def in pairs(dc.custom) do
                local entry = NPD.CATALOG[key]
                local crow = UI.Holder(L.current)
                crow:SetSize(400, 22)
                local b = UI.Button(crow, "Remove", { width = 80, onClick = function() NPD.RemoveCustom(key) RefreshConfig() end })
                b:SetPoint("LEFT")
                local fs = UI.Font(crow, F.LABEL, { text = (entry and entry.name or key) .. "  (" .. tostring(def.spellID) .. ")" })
                fs:SetPoint("LEFT", b, "RIGHT", 8, 0)
                L:Row(crow, 26)
            end
            local add = UI.Holder(L.current)
            add:SetSize(400, 24)
            local eb = UI.EditBox(add, { width = 120, hint = "spell id" })
            eb:SetPoint("LEFT")
            local addBtn = UI.Button(add, "Add", { width = 70, onClick = function()
                local id = tonumber(eb.GetText and eb:GetText() or "")
                local key, name = NPD.AddCustom(id)
                if not key then Print("nameplate debuffs: " .. tostring(name) .. " spell id") return end
                for _, g in ipairs(dc.groups) do
                    if g.id == (NPD.UNDER_ID or "under") then
                        g.members[#g.members + 1] = key
                        g.memberOn = g.memberOn or {}
                        g.memberOn[key] = false
                    end
                end
                DApply()
                RefreshConfig()
            end })
            addBtn:SetPoint("LEFT", eb, "RIGHT", 8, 0)
            L:Row(add, M.BUTTON_H + 4)
            L:EndCard()
        end
    end

    local function Tab_soft(L)
        SoftTargetSection(L)
        CrosshairSection(L)
    end

    L:Tabs({
        { id = "general", label = "General", build = Tab_general },
        { id = "look", label = "Look", build = Tab_look },
        { id = "text", label = "Text", build = Tab_text },
        { id = "anim", label = "Animation", build = Tab_anim },
        { id = "pos", label = "Position", build = Tab_pos },
        { id = "adv", label = "Advanced", build = Tab_adv },
        { id = "soft", label = "Soft target & crosshair", build = Tab_soft },
        -- the plate scripts page, as a tab here rather than a row of its own
        { id = "scripts", label = "Scripts", build = function(TL)
            local page = ns.ConfigPages and ns.ConfigPages["PlateScripts"]
            if page then
                TL.asTab = true
                page(TL)
            end
        end },
    })
end)
