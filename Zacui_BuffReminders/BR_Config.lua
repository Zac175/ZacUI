-- BR_Config - the Buff reminders page (Combat > Buff reminders).
-- Part of ZacUI; load order is set by the TOC.
--
-- Tabs in the house order: General (which buffs, when each frame shows,
-- the tracker's casting help, fades, sound) - Look (sizes, colours,
-- shadow / glow) - Text (every text: font, colour, format, where it sits)
-- - Animation - Position (movers, layer, the parts, the layouts) -
-- Advanced (copy from Readycheck, Readycheck's own switch, reset).
--
-- THE PREVIEW is the reminder icons and the tracker themselves (BR_Icon's
-- Icon.New / Style / Fill, BR_Tracker's T.New / Style / Layout) with a
-- made-up group: someone missing, all buffed, or a raid by group.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local BR = ns.BuffRem
if not (BR and BR.IconUI and BR.TrackerUI) then return end
local D, Icon, T = BR.Data, BR.IconUI, BR.TrackerUI

local UI = ns.UI
local M = UI.M
local format = string.format

-- the menu row: Combat > Buff reminders (after Blessings)
do
    local combat
    for _, item in ipairs(ns.ConfigMenu or {}) do
        if item.id == "combat" and item.children then combat = item end
    end
    if combat then
        local have = false
        for _, c in ipairs(combat.children) do if c.id == "buffrem" then have = true end end
        if not have then
            local at = #combat.children + 1
            for i, c in ipairs(combat.children) do if c.id == "blessings" then at = i + 1 end end
            table.insert(combat.children, at, { id = "buffrem", label = "Buff reminders", page = "BuffRem",
                addon = "Zacui_BuffReminders",
                keywords = "buff buffs reminder reminders missing battle shout bs party tracker raid group "
                    .. "arcane intellect brilliance fortitude prayer spirit shadow protection mark of the wild "
                    .. "gift motw gotw thorns trueshot soulstone reagent reagents candle powder thornroot "
                    .. "rebuff buffing click cast readycheck warrior mage priest druid hunter warlock" })
        end
    end
end
if ns.AddMenuKeywords then
    ns.AddMenuKeywords("buffrem", "bloodrage ap attack power greed improved cleave oor range names "
        .. "timer bar duration expiring low sound voice tts font colour color anchor position layout "
        .. "fade opacity mouseover shadow glow scale layer import copy")
end

local function IC() return BR.Icon() end
local function TC() return BR.Tracker() end
local function Px(v) return format("%d px", v) end
local function Pct(v) return format("%d%%", v * 100 + 0.5) end
local function Secs(v)
    if v == 0 then return "Missing only" end
    if v >= 60 and v % 60 == 0 then return format("%d min", v / 60) end
    return format("%ds", v)
end

local function Check(L, label, value, fn, tip)
    local w = UI.Checkbox(L.current, label, value and true or false, function(v) fn(v and true or false) end,
        tip and { tooltip = tip } or nil)
    L:Row(w, M.ROW or 22)
    return w
end
local function Slider(L, label, min, max, step, value, fmt, set)
    local w = UI.Slider(L.current, { width = 240, min = min, max = max, step = step, value = value,
        label = label, format = fmt, onChange = set })
    L:Row(w, 40)
    return w
end
local function Drop(L, label, items, cur, set, width)
    local function Text(v) for _, it in ipairs(items) do if it.value == v then return it.text end end return items[1].text end
    local f = UI.Field(L.current, label, function(h)
        return UI.Dropdown(h, { width = width or 200,
            items = function() return items end,
            selected = function() return Text(cur()) end, selectedValue = cur,
            onSelect = function(v) set(v) end })
    end, { width = width or 200 })
    L:Add(f, 8)
    return f
end
-- a colour setting (sec "icon" | "tracker"), nil until picked = Readycheck's
local function Colour(L, sec, key, label, default)
    local function T_() return sec == "icon" and IC() or TC() end
    local w = UI.ColorPicker(L.current, { label = label, alpha = true,
        get = function() return BR.Color(sec, key) end,
        set = function(r, g, b, a)
            local t = T_()
            if r == nil then
                if type(t.colors) == "table" then t.colors[key] = nil end
                return
            end
            t.colors = t.colors or {}
            t.colors[key] = { r = r, g = g, b = b, a = a or 1 }
        end,
        default = function()
            local d = default and default() or BR.DEFAULTS[sec].colors[key]
            return d.r, d.g, d.b, d.a or 1
        end, reset = true })
    L:Row(w, 22)
    return w
end
local function Anim(L, tbl, key, label, styles)
    local w = UI.AnimationPicker(L.current, { label = label, styles = styles,
        get = function() return tbl[key] end, set = function(spec) tbl[key] = spec end })
    L:Add(w, 6)
    return w
end
local function Fresh() if BR.RunAll then BR.RunAll() end end

local SHOW_IN = {
    { text = "Inside raids", value = "raids" },
    { text = "Dungeons and raids", value = "instances" },
    { text = "In any group", value = "always" },
    { text = "Everywhere", value = "everywhere" },
}
local RAID_MODES = { raids = true, instances = true, always = true }

-- "Show in" and, under the raid modes, the raids it counts in
local function ShowIn(L, tbl)
    Drop(L, "Show in", SHOW_IN, function() return tbl.visibilityMode or "raids" end,
        function(v) tbl.visibilityMode = v Fresh() ns.RefreshConfig() end)
    if RAID_MODES[tbl.visibilityMode or "raids"] then
        local boxes = {}
        for _, name in ipairs(D.RAIDS) do
            local n = name
            boxes[#boxes + 1] = UI.Checkbox(L.current, n, type(tbl.visibilityRaids) == "table" and tbl.visibilityRaids[n] or false,
                function(v)
                    tbl.visibilityRaids = type(tbl.visibilityRaids) == "table" and tbl.visibilityRaids or {}
                    tbl.visibilityRaids[n] = v and true or nil
                    if next(tbl.visibilityRaids) == nil then tbl.visibilityRaids = nil end
                    Fresh()
                end)
        end
        L:Grid(boxes, 3, 20)
        L:Desc("Tick raids to count only those; none ticked counts every raid.")
    end
end

-- ============================================================
-- PREVIEW
-- ============================================================
-- the buffs shown: the class's own (on ones first), else Battle Shout
local function PreviewBuffs()
    local list = {}
    local mine = BR.MyBuffs()
    if #mine == 0 then mine = D.ForClass(BR.PlayerClass() or "WARRIOR") end
    if #mine == 0 then mine = { D.BY_KEY.battleshout } end
    for _, def in ipairs(mine) do if BR.ReminderOn(def.key) then list[#list + 1] = def end end
    if #list == 0 then list[1] = mine[1] end
    return list, mine[1]
end

local function BuildPreview(canvas, P)
    local st = P.store
    st.holder = CreateFrame("Frame", nil, canvas)
    st.holder:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
    st.holder:SetSize(10, 10)
    st.iconHost = CreateFrame("Frame", nil, st.holder)
    st.iconHost:SetSize(40, 40)
    st.icons = {}
    st.tracker = T.New(st.holder, true)
    st.rows = {}
end

local SAMPLE_NAMES = "Rowdy\nStabbs"
-- the warrior HUD's parts the docked Battle Shout slot is drawn with
local function HudSlot()
    local WH = ns.WarriorHUD
    local WD = WH and WH.Display
    if WD and WD.MakeAuraIcon and WD.FillShoutRem and WD.StyleIcon and WD.SHOUT_REM_DEF and WH.Store then
        return WH, WD
    end
end
-- the seconds a "Running low" sample shows (inside the warn time)
local function LowSecs(def)
    local thr = tonumber(BR.Opt(def.key, "threshold")) or 0
    return thr > 1 and math.floor(thr * 0.6) or 14
end
local function UpdatePreview(canvas, P)
    local st = P.store
    local ic, tc = IC(), TC()
    local mode = P.mode or "missing"
    local low = mode == "low"
    local missing = mode ~= "buffed" and not low
    local warn = missing or low
    local defs, primary = PreviewBuffs()
    local shown = {}
    local now = GetTime()
    for key, f in pairs(st.icons) do f:Hide() end
    if st.hud then st.hud:Hide() end
    local dockedH = 0
    for _, def in ipairs(defs) do
        local selfOnly = BR.Opt(def.key, "scope") == "self"
        local WH, WD = HudSlot()
        if def.key == "battleshout" and BR.Opt(def.key, "hudDock") == true and WH then
            -- set to live in the warrior HUD's buff row: the HUD's own
            -- slot in place of the icon, filled as the live row fills it
            if not st.hud then st.hud = WD.MakeAuraIcon(st.iconHost, WD.SHOUT_REM_DEF) end
            local hc = WH.Store()
            local hs = st.hud
            WD.StyleIcon(hs, hc)
            local row = hc and hc.auraRow or {}
            hs:SetSize(tonumber(row.iconW) or 30, tonumber(row.iconH) or 30)
            st.hudState = st.hudState or {}
            local sh = st.hudState
            sh.tex, sh.selfOnly = BR.Icon_(def), selfOnly
            sh.missing, sh.low = missing, low
            sh.count = missing and (mode == "raid" and 5 or 2) or 0
            sh.lowAt = low and (now + LowSecs(def)) or nil
            sh.names = (missing and ic.showMissingNames and not selfOnly) and (ic.shortenNames and "Row\nSta" or SAMPLE_NAMES) or nil
            WD.FillShoutRem(hs, sh, now)
            -- its red seconds count down here too (and start over), as on
            -- the HUD page: one light driver while the slot is shown
            if not hs._zDrive then
                hs._zDrive = true
                local acc, secs = 0, LowSecs(def)
                hs:HookScript("OnUpdate", function(_, el)
                    acc = acc + (el or 0)
                    if acc < 0.1 then return end
                    acc = 0
                    local s2 = st.hudState
                    if s2 and s2.low and s2.lowAt then
                        local t = GetTime()
                        if s2.lowAt - t < 0 then s2.lowAt = t + secs end
                        WD.FillShoutRem(hs, s2, t)
                    end
                end)
            end
            hs:Show()
            shown[#shown + 1] = hs
            -- (its numbers hang under it)
            dockedH = 16
        else
            local f = st.icons[def.key]
            if not f then f = Icon.New(st.iconHost, def, true) st.icons[def.key] = f end
            Icon.Style(f, ic)
            local text, names = "", nil
            if missing then
                text = selfOnly and "" or (mode == "raid" and "5" or "2")
                if ic.showMissingNames and not selfOnly then names = ic.shortenNames and "Row\nSta" or SAMPLE_NAMES end
            elseif low then
                text = tostring(LowSecs(def))
            elseif def.port and BR.Opt(def.key, "showAPValue") then
                text = "290 AP"
            end
            Icon.Fill(f, warn, text, names)
            f:Show()
            shown[#shown + 1] = f
        end
    end
    Icon.Place(st.iconHost, shown)

    -- the tracker: the first buff's made-up group, through its own filter
    local all = T.SampleRows(primary, mode == "buffed" and "buffed" or mode, GetTime(), st.all)
    st.all = all
    local rows = st.rows
    for i = #rows, 1, -1 do rows[i] = nil end
    for _, r in ipairs(all) do
        if r.kind or not tc.showOnlyMissing or not r.hasBuff or r.belowThreshold then rows[#rows + 1] = r end
    end
    T.Style(st.tracker, tc)
    T.Layout(st.tracker, rows, tc, nil, { title = primary.label, icon = BR.Icon_(primary) })
    st.tracker:SetShown(#rows > 0)

    -- the icons (and their names) on the left, the tracker beside them at
    -- its own scale; the canvas is the pair
    local size = ic.iconSize or 40
    local iw, ih = st.iconHost:GetWidth() or size, st.iconHost:GetHeight() or size
    local pos = ic.namesPosition or "right"
    local gap = tonumber(ic.namesOffset) or 5
    local nameW, nameH = 0, 0
    -- (the docked HUD slot has no names: only the reminder's own icon)
    if missing and ic.showMissingNames and shown[1] and shown[1].namesText then
        nameW = (shown[1].namesText:GetStringWidth() or 40) + gap
        nameH = (shown[1].namesText:GetStringHeight() or 24) + gap
    end
    local side = (pos == "left" or pos == "right") and nameW or 0
    local above = (pos == "above") and nameH or 0
    local below = (pos == "below") and nameH or 0
    local tsc = tonumber(tc.scale) or 1
    if tsc <= 0 then tsc = 1 end
    local tw = (#rows > 0) and (st.tracker:GetWidth() or 165) or 0
    local th = (#rows > 0) and (st.tracker:GetHeight() or 60) or 0
    below = math.max(below, dockedH)
    local leftW = iw + side * 2
    local trackX = 8 + leftW + ((#rows > 0) and 14 or 0)
    local w = trackX + tw * tsc + 8
    local h = math.max(ih + above + below, th * tsc) + 8
    local isc = (type(ic.framePos) == "table" and tonumber(ic.framePos.scale)) or 1
    st.iconHost:SetScale(isc)
    st.iconHost:ClearAllPoints()
    st.iconHost:SetPoint("LEFT", st.holder, "LEFT", (8 + side) / isc, (below - above) / 2 / isc)
    st.tracker:SetScale(tsc)
    st.tracker:ClearAllPoints()
    st.tracker:SetPoint("LEFT", st.holder, "LEFT", trackX / tsc, 0)
    st.holder:SetSize(w, h)
    if P.Resize then P.Resize(w, h) end
end

local function ReplayPreview(canvas, P)
    local st = P.store
    local ic, tc = IC(), TC()
    local missing = (P.mode or "missing") ~= "buffed"
    local Motion = ns.Motion
    st.serial = (st.serial or 0) + 1
    local mine = st.serial
    for _, f in pairs(st.icons) do
        if f:IsShown() then
            Motion.Stop(f)
            f:Hide()
            local ff = f
            if not Motion.Show(ff, ic.showAnim or { style = "none" }, function()
                if missing and ic.alertAnim and ff:IsVisible() and mine == st.serial then Motion.Play(ff, ic.alertAnim, "update") end
            end) then ff:Show() end
        end
    end
    if st.tracker:IsShown() then
        Motion.Stop(st.tracker)
        st.tracker:Hide()
        if not Motion.Show(st.tracker, tc.showAnim or { style = "none" }) then st.tracker:Show() end
    end
end

-- ============================================================
-- TABS
-- ============================================================
local function BuffCard(L, def)
    local key = def.key
    L:Card(def.label)
    local rem = Check(L, "Reminder icon", BR.ReminderOn(key), function(v) BR.SetOpt(key, "enabled", v) Fresh() end,
        "An icon that warns when you, or the people it reaches, are missing it or it is about to run out.")
    local trk = Check(L, "Show in the tracker", BR.TrackerOn(key), function(v) BR.SetOpt(key, "tracker", v) Fresh() end,
        def.reach == "party" and "Your party, each with the time left on them."
            or "Everyone in the raid who needs it, by group, with the cast to use and a click to cast it.")
    local whoLabel = def.reach == "party" and "My group" or (def.reach == "chosen" and "The people listed" or "The raid")
    Drop(L, "Remind me about", { { text = whoLabel, value = "group" }, { text = "Only me", value = "self" } },
        function() return BR.Opt(key, "scope") end, function(v) BR.SetOpt(key, "scope", v) Fresh() end)
    Slider(L, "Warn before it runs out", 0, def.port and 120 or 600, def.port and 5 or 30,
        BR.Opt(key, "threshold") or 0, Secs, function(v) BR.SetOpt(key, "threshold", v) end)
    local rng = Check(L, "Count people out of range apart", BR.Opt(key, "rangeCheck"), function(v) BR.SetOpt(key, "rangeCheck", v) end,
        "People out of range are left out of the count and show as ~Name in the names.")
    if def.port then
        local greed = Check(L, "Stay quiet while my own long (15-min) Battle Shout is still up", BR.Opt(key, "greedMode"),
            function(v) BR.SetOpt(key, "greedMode", v) ns.RefreshConfig() end,
            "Hides the reminder while the long 400 AP Battle Shout on you has more than three minutes left.")
        L:Dependent({ UI.Checkbox(L.current, "Also when specced into Improved Cleave", BR.Opt(key, "greedSkipIfImpCleave"),
            function(v) BR.SetOpt(key, "greedSkipIfImpCleave", v and true or false) end) }, BR.Opt(key, "greedMode"), 1, 20)
        Check(L, "Show the attack power when buffed", BR.Opt(key, "showAPValue"), function(v) BR.SetOpt(key, "showAPValue", v) end)
        Check(L, "Show it in the warrior HUD's buff row instead", BR.Opt(key, "hudDock"),
            function(v) BR.SetOpt(key, "hudDock", v) Fresh() if ns.WarriorHUD and ns.WarriorHUD.Display
                and ns.WarriorHUD.Display.Refresh then pcall(ns.WarriorHUD.Display.Refresh, ns.WarriorHUD.Display) end end,
            "The reminder sits first in the HUD's active-buff row (glowing while it warns, the count under it) "
            .. "instead of its own icon. Needs the warrior HUD and its buff row on.")
    end
    if def.reach == "chosen" then
        local list = BR.Opt(key, "targets")
        L:Add(UI.Field(L.current, def.tanks and "Who gets it (and the raid's main tanks)" or "Who gets it", function(h)
            return UI.EditBox(h, { width = 260, text = table.concat(type(list) == "table" and list or {}, ", "),
                hint = "Names, with commas",
                onEnter = function(text)
                    local out = {}
                    for n in tostring(text or ""):gmatch("[^,%s]+") do out[#out + 1] = n end
                    BR.SetOpt(key, "targets", #out > 0 and out or nil)
                    Fresh()
                end })
        end, { width = 260 }), 8)
    end
    if def.group then
        local gname = BR.GroupKnown(def)
        L:Desc(gname and (gname .. " covers a whole party: the tracker points it out when most of a group needs it.")
            or (def.group.label .. " is not learned yet: the tracker points out the single rank."))
    end
    L:EndCard()
end

local function Tab_general(L)
    local c = BR.Cfg()
    local cls = BR.PlayerClass()
    L:Card("Buff reminders")
    Check(L, "Buff reminders on", c.enabled ~= false, function(v) c.enabled = v and nil or false Fresh() end,
        "Off: no reminder and no tracker on any character wearing this profile.")
    L:EndCard()
    if cls == "PALADIN" then
        L:Card("Blessings")
        L:Desc("Paladin blessings have their own page: who blesses what, the casting bar and the auras.")
        L:Row(UI.Button(L.current, "Open Blessings", { width = 160, onClick = function() ns.OpenConfig("blessings") end }),
            M.BUTTON_H + 6)
        L:EndCard()
    end
    local mine = BR.MyBuffs()
    if #mine == 0 then
        local own = D.ForClass(cls or "")
        L:Card("Your buffs")
        L:Desc(#own > 0 and "Your class's group buffs show here once you have learned one."
            or "Your class gives no group buff this tracks. The settings below are shared: they are used by your characters that do.")
        L:EndCard()
    end
    for _, def in ipairs(mine) do BuffCard(L, def) end

    local ic, tc = IC(), TC()
    L:Card("When the reminder shows")
    ShowIn(L, ic)
    Check(L, "Hide when everyone has it", ic.hideWhenAllBuffed, function(v) ic.hideWhenAllBuffed = v end)
    L:EndCard()

    L:Card("Tracker")
    ShowIn(L, tc)
    Check(L, "Only list who needs it", tc.showOnlyMissing, function(v) tc.showOnlyMissing = v end,
        "Your party only: in a raid the tracker always lists only who needs it.")
    Check(L, "Range check (OOR instead of MISSING)", tc.rangeCheck, function(v) tc.rangeCheck = v end,
        "Battle Shout: shows OOR for party members outside ~28 yards. The buffs you cast on others always show who is out of range.")
    if cls == "WARRIOR" or cls == nil then
        local br = Check(L, "Show who is Bloodraging", tc.showBloodrage ~= false, function(v) tc.showBloodrage = v ns.RefreshConfig() end)
        local f = UI.Field(L.current, "Bloodrage shows as", function(h)
            return UI.Dropdown(h, { width = 160,
                items = function() return { { text = "Icon", value = "icon" }, { text = "Red name", value = "color" }, { text = "Both", value = "both" } } end,
                selected = function() local v = tc.bloodrageStyle or "both" return v == "icon" and "Icon" or (v == "color" and "Red name" or "Both") end,
                selectedValue = function() return tc.bloodrageStyle or "both" end,
                onSelect = function(v) tc.bloodrageStyle = v end })
        end, { width = 160 })
        L:Dependent({ f }, tc.showBloodrage ~= false, 1, (M.CHECK or 14) + 8)
    end
    Drop(L, "Time left shows as", { { text = "None", value = "none" }, { text = "Bar", value = "bar" },
        { text = "Timer", value = "timer" }, { text = "Both", value = "both" } },
        function() return tc.durationStyle or "bar" end, function(v) tc.durationStyle = v end)
    Slider(L, "A full bar", 60, 900, 30, tc.barMaxDuration or 120, function(v) return format("%ds", v) end,
        function(v) tc.barMaxDuration = v end)
    Check(L, "Click a row to cast", tc.clickCast ~= false, function(v) tc.clickCast = v end,
        "A click on a person casts your buff on them; a click on a group casts the group buff (or the single rank) "
        .. "on someone in it. Out of combat only - the game allows nothing else.")
    Slider(L, "Group buff once this many need it", 2, 5, 1, tonumber(tc.groupAt) or 3, tostring,
        function(v) tc.groupAt = v end)
    Slider(L, "Reagents run low under", 0, 100, 5, tonumber(tc.reagentLow) or 20, tostring, function(v) tc.reagentLow = v end)
    Check(L, "Say so in chat when reagents run low", tc.reagentWarn ~= false, function(v) tc.reagentWarn = v end)
    L:EndCard()

    L:Card("Icon fade and opacity")
    local vg, vs = ns.CustomAccess(IC, "visibility", nil)
    L:Add(UI.VisibilityPicker(L.current, { width = UI.CardInnerWidth(L), get = vg, set = vs,
        shows = { "always", "combat", "nocombat", "group", "raid", "instance", "mouseover" } }), 6)
    L:EndCard()
    L:Card("Tracker fade and opacity")
    vg, vs = ns.CustomAccess(TC, "visibility", nil)
    L:Add(UI.VisibilityPicker(L.current, { width = UI.CardInnerWidth(L), get = vg, set = vs,
        shows = { "always", "combat", "nocombat", "group", "raid", "instance", "mouseover" } }), 6)
    L:Desc("A faded tracker's rows can still be clicked.")
    L:EndCard()

    L:Card("Sound")
    Check(L, "Play a sound when a warning starts", ic.playSound, function(v) ic.playSound = v ns.RefreshConfig() end)
    local sg, ss = ns.CustomAccess(IC, "sounds", "warn")
    local sp = UI.SoundSpecPicker(L.current, { width = UI.CardInnerWidth(L), get = sg, set = ss,
        defaults = { sound = ic.soundKey or "WR: Warning", channel = "Master" } })
    L:Add(sp, 6)
    UI.SetEnabled(sp, ic.playSound and true or false)
    Check(L, "Say the buff's name", ic.speak, function(v) ic.speak = v end,
        "Spoken once as the warning starts, in the voice set on the Overview page.")
    L:EndCard()
end

local function Tab_look(L)
    local ic, tc = IC(), TC()
    L:Card("Reminder icon")
    Slider(L, "Icon size", 20, 80, 1, ic.iconSize or 40, Px, function(v) ic.iconSize = v end)
    Slider(L, "Opacity", 0.1, 1, 0.1, ic.opacity or 0.7, Pct, function(v) ic.opacity = v end)
    Slider(L, "Border thickness", 0, 4, 1, tonumber(ic.borderSize) or 1, Px, function(v) ic.borderSize = v end)
    Colour(L, "icon", "background", "Background")
    Colour(L, "icon", "normalBorder", "Border when everyone has it")
    Colour(L, "icon", "missingBorder", "Border when someone is missing it")
    local names = Check(L, "Show the missing names", ic.showMissingNames, function(v) ic.showMissingNames = v ns.RefreshConfig() end)
    L:Dependent({ UI.Checkbox(L.current, "Shorten names (first 3 letters)", ic.shortenNames,
        function(v) ic.shortenNames = v and true or false end) }, ic.showMissingNames, 1, 20)
    Drop(L, "Names sit", { { text = "Right", value = "right" }, { text = "Left", value = "left" },
        { text = "Above", value = "above" }, { text = "Below", value = "below" } },
        function() return ic.namesPosition or "right" end, function(v) ic.namesPosition = v end, 140)
    Slider(L, "Gap between icon and names", 0, 20, 1, tonumber(ic.namesOffset) or 5, Px, function(v) ic.namesOffset = v end)
    L:EndCard()

    L:Card("Tracker")
    Check(L, "Show background", tc.showBackground ~= false, function(v) tc.showBackground = v end)
    Check(L, "Show header", tc.showHeader ~= false, function(v) tc.showHeader = v end)
    Slider(L, "Background opacity", 0, 1, 0.05, tc.opacity or 0.85, Pct, function(v) tc.opacity = v end)
    Slider(L, "Width", 120, 280, 5, tc.width or 165, Px, function(v) tc.width = v end)
    Slider(L, "Row height", 14, 26, 1, tc.rowHeight or 17, Px, function(v) tc.rowHeight = v end)
    Slider(L, "Border thickness", 0, 4, 1, tonumber(tc.borderSize) or 1, Px, function(v) tc.borderSize = v end)
    Slider(L, "Time bar opacity", 0.1, 1, 0.05, tonumber(tc.barAlpha) or 0.45, Pct, function(v) tc.barAlpha = v end)
    Colour(L, "tracker", "background", "Background")
    Colour(L, "tracker", "border", "Border")
    Colour(L, "tracker", "headerBackground", "Header")
    Colour(L, "tracker", "rowBackground", "Row background")
    Colour(L, "tracker", "apGood", "Has it")
    Colour(L, "tracker", "apWarning", "Running out / out of range / reagents low")
    Colour(L, "tracker", "apMissing", "Missing")
    Colour(L, "tracker", "bloodrageActive", "Bloodraging name")
    L:Desc("The status colours paint the status text and its time bar.")
    L:EndCard()

    L:Card("Icon shadow and glow")
    local cg, cs = ns.CustomAccess(IC, "chrome", nil)
    L:Add(UI.ChromePicker(L.current, { width = UI.CardInnerWidth(L), get = cg, set = cs,
        fields = { shadowSize = true, shadowColor = true, glowSize = true, glowColor = true } }), 6)
    L:EndCard()
    L:Card("Tracker shadow and glow")
    cg, cs = ns.CustomAccess(TC, "chrome", nil)
    L:Add(UI.ChromePicker(L.current, { width = UI.CardInnerWidth(L), get = cg, set = cs,
        fields = { shadowSize = true, shadowColor = true, glowSize = true, glowColor = true } }), 6)
    L:EndCard()
end

local function Others(list, self)
    local out = {}
    for _, t in ipairs(list) do if t.value ~= self then out[#out + 1] = t end end
    return out
end
local function FontAccess(tbl, key)
    return function() return tbl()[key] end, function(spec) tbl()[key] = spec end
end

local function Tab_text(L)
    L:Card("Reminder icon")
    local ag, as = ns.CustomAccess(IC, "anchors", "count")
    local fg, fs = FontAccess(IC, "countFont")
    UI.TextElement(L, { label = "Count", key = "buffrem.count", fontGet = fg, fontSet = fs,
        fontDefaults = BR.DEFAULTS.icon.countFont, sample = "3   12   290 AP", minSize = 10, maxSize = 28,
        colors = {
            { label = "When someone is missing it", get = function() return BR.Color("icon", "missingText") end,
              set = function(r, g, b, a) local t = IC() t.colors = t.colors or {} t.colors.missingText = { r = r, g = g, b = b, a = a or 1 } end },
            { label = "When everyone has it", get = function() return BR.Color("icon", "allBuffedText") end,
              set = function(r, g, b, a) local t = IC() t.colors = t.colors or {} t.colors.allBuffedText = { r = r, g = g, b = b, a = a or 1 } end },
        },
        anchorGet = ag, anchorSet = as, targets = Others(Icon.TARGETS, "count"),
        anchorDefaults = function() return Icon.AnchorDefaults("count") end })
    ag, as = ns.CustomAccess(IC, "anchors", "names")
    fg, fs = FontAccess(IC, "namesFont")
    UI.TextElement(L, { label = "Missing names", key = "buffrem.names", fontGet = fg, fontSet = fs,
        fontDefaults = BR.DEFAULTS.icon.namesFont, sample = "Rowdy  Stabbs  ~Pewpew", minSize = 8, maxSize = 20,
        anchorGet = ag, anchorSet = as, targets = Others(Icon.TARGETS, "names"),
        defaultTargetLabel = "Beside the icon (Look tab)",
        anchorDefaults = function() return Icon.AnchorDefaults("names") end })
    L:Desc("The names follow the side and gap on the Look tab; a position set here goes on top.")
    L:EndCard()

    L:Card("Tracker")
    ag, as = ns.CustomAccess(TC, "anchors", "rowName")
    fg, fs = FontAccess(TC, "rowFont")
    local nfg, nfs = ns.CustomAccess(TC, "formats", "name")
    -- (one column while the card is narrow: the name format's "Longest"
    -- slider shows "13 letters" and needs the whole width then)
    local nw = UI.CardInnerWidth(L)
    if nw < 390 then nw = 299 end
    UI.TextElement(L, { label = "Names", key = "buffrem.rowName", width = nw, fontGet = fg, fontSet = fs,
        fontDefaults = BR.DEFAULTS.tracker.rowFont, sample = "Rowdy   290 AP  1:01", minSize = 8, maxSize = 18,
        formatGet = nfg, formatSet = nfs, formatKinds = { name = true }, formatDefaults = T.NAME_FORMAT,
        formatSample = function(spec) return ns.FormatName("Bonkersthewarrior", spec, T.NAME_FORMAT) end,
        anchorGet = ag, anchorSet = as, targets = Others(T.ROW_TARGETS, "name"),
        anchorDefaults = function() return T.AnchorDefaults("rowName") end })
    ag, as = ns.CustomAccess(TC, "anchors", "rowStatus")
    local tfg, tfs = ns.CustomAccess(TC, "formats", "time")
    UI.TextElement(L, { label = "Status and time", key = "buffrem.rowStatus",
        formatGet = tfg, formatSet = tfs, formatKinds = { time = true }, formatDefaults = T.TIME_FORMAT,
        formatSample = function(spec) return ns.FormatTime(61.4, spec, T.TIME_FORMAT) end,
        anchorGet = ag, anchorSet = as, targets = Others(T.ROW_TARGETS, "status"),
        anchorDefaults = function() return T.AnchorDefaults("rowStatus") end })
    ag, as = ns.CustomAccess(TC, "anchors", "title")
    fg, fs = FontAccess(TC, "titleFont")
    UI.TextElement(L, { label = "Title", key = "buffrem.title", fontGet = fg, fontSet = fs,
        fontDefaults = BR.DEFAULTS.tracker.titleFont, sample = "Battle Shout", minSize = 8, maxSize = 18,
        colors = { { label = "Title colour", get = function() return T.TitleColor(TC()) end,
            set = function(r, g, b, a) local t = TC() t.colors = t.colors or {} t.colors.titleText = { r = r, g = g, b = b, a = a or 1 } end } },
        anchorGet = ag, anchorSet = as, targets = Others(T.TITLE_TARGETS, "title"),
        anchorDefaults = function() return T.AnchorDefaults("title") end })
    L:Desc("Names wear their class colour; the status uses the colours on the Look tab. The status shares the names' font.")
    L:EndCard()
end

local function Tab_anim(L)
    local ic, tc = IC(), TC()
    L:Card("Reminder icon")
    Anim(L, ic, "showAnim", "When it appears")
    Anim(L, ic, "alertAnim", "While someone is missing it")
    Anim(L, ic, "hideAnim", "When it goes")
    L:EndCard()
    L:Card("Tracker")
    Anim(L, tc, "showAnim", "When it appears")
    Anim(L, tc, "hideAnim", "When it goes")
    L:Desc("Replay in the preview plays them. Appearance > Motion turns every animation off or speeds them up.")
    L:EndCard()
end

local function MoverButtons(L, key, label)
    local mv = UI.Button(L.current, "Move " .. label, { width = 160, onClick = function()
        if ns.ToggleMover then ns.ToggleMover(key) end
        Fresh()
    end })
    local rs = UI.Button(L.current, "Reset", { width = 80, onClick = function()
        if ZacUIDB.movers then ZacUIDB.movers[key] = nil end
        if key == Icon.MOVER then
            local h = Icon.Holder()
            h:ClearAllPoints()
            h:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
        elseif T.Place then T.Place() end
    end })
    L:Flow({ mv, rs }, 8)
end

local function Tab_pos(L)
    local tc = TC()
    L:Card("Reminder icon")
    MoverButtons(L, Icon.MOVER, "the reminder")
    L:Desc("Shows the icons with a made-up count while you place them; click Move again to lock.")
    local fg, fs = ns.CustomAccess(IC, "framePos", nil)
    L:Add(UI.FrameLayerPicker(L.current, { width = UI.CardInnerWidth(L), get = fg, set = fs,
        defaults = { strata = "MEDIUM", level = 0, scale = 1, clamp = true } }), 6)
    local lg, ls = ns.CustomAccess(IC, "layout", nil)
    L:Add(UI.LayoutPicker(L.current, { width = UI.CardInnerWidth(L), get = lg, set = ls, defaults = Icon.LAYOUT_DEF,
        fields = { grow = true, wrap = true, perLine = true, spacingX = true, spacingY = true, max = true, reverse = true },
        maxItems = 6 }), 6)
    L:Desc("How several icons sit (a priest's three, say).")
    L:EndCard()

    L:Card("Tracker")
    MoverButtons(L, T.MOVER, "the tracker")
    Slider(L, "Scale", 0.5, 2, 0.05, tonumber(tc.scale) or 1, Pct, function(v) tc.scale = v end)
    fg, fs = ns.CustomAccess(TC, "framePos", nil)
    L:Add(UI.FrameLayerPicker(L.current, { width = UI.CardInnerWidth(L), get = fg, set = fs,
        fields = { strata = true, level = true, clamp = true },
        defaults = { strata = "MEDIUM", level = 0, clamp = true } }), 6)
    L:EndCard()

    L:Card("Parts")
    local ag, as = ns.CustomAccess(IC, "anchors", "icon")
    UI.FrameElement(L, { label = "Icon art", key = "buffrem.icon", anchorGet = ag, anchorSet = as,
        targets = Others(Icon.TARGETS, "icon"), defaultTargetLabel = "Fills the icon frame",
        anchorDefaults = function() return Icon.AnchorDefaults("icon") end })
    ag, as = ns.CustomAccess(TC, "anchors", "titleIcon")
    UI.FrameElement(L, { label = "Tracker title icon", key = "buffrem.titleIcon", anchorGet = ag, anchorSet = as,
        targets = Others(T.TITLE_TARGETS, "titleIcon"),
        anchorDefaults = function() return T.AnchorDefaults("titleIcon") end })
    ag, as = ns.CustomAccess(TC, "anchors", "rowIcon")
    UI.FrameElement(L, { label = "Row icon (Bloodrage, the cast to use)", key = "buffrem.rowIcon", anchorGet = ag, anchorSet = as,
        targets = Others(T.ROW_TARGETS, "icon"),
        anchorDefaults = function() return T.AnchorDefaults("rowIcon") end })
    L:Desc("Reset puts a part back where it always sat.")
    L:EndCard()

    L:Card("Tracker rows")
    lg, ls = ns.CustomAccess(TC, "layout", nil)
    L:Add(UI.LayoutPicker(L.current, { width = UI.CardInnerWidth(L), get = lg, set = ls,
        defaults = { grow = "DOWN", spacingY = 0, padding = 0, max = 40 },
        fields = { grow = true, spacingY = true, padding = true, max = true, sort = true, reverse = true },
        grows = { "DOWN", "UP" }, sorts = T.SORTS, maxItems = 40 }), 6)
    L:Desc("Row height is on the Look tab. Order by sorts the people inside each group; groups stay in order.")
    L:EndCard()
end

local lastImport
local function Tab_adv(L)
    L:Card("Copy from Readycheck")
    L:Desc("Brings this character's Readycheck Battle Shout reminder and party tracker settings over: look, texts, "
        .. "sounds, when they show and where they sit.")
    local b = UI.Button(L.current, "Copy Readycheck's settings", { width = 220, onClick = function()
        local ok, why = BR.ImportFromReadycheck()
        lastImport = (ok and "Done: " or "Not copied: ") .. tostring(why)
        ns.RefreshConfig()
    end })
    L:Row(b, M.BUTTON_H + 6)
    if lastImport then L:Desc(lastImport) end
    L:EndCard()

    local rcIcon, rcTracker = BR.ReadycheckOn()
    L:Card("Readycheck's Battle Shout reminder")
    L:Desc((rcIcon or rcTracker) and "Readycheck's own reminder is on, so ZacUI's Battle Shout stays off until you pick it."
        or "Readycheck's own Battle Shout reminder and tracker are off.")
    local off = UI.Button(L.current, "Turn Readycheck's off", { width = 200, onClick = function()
        BR.TurnOffReadycheck()
        ns.RefreshConfig()
    end })
    L:Row(off, M.BUTTON_H + 6)
    UI.SetEnabled(off, (rcIcon or rcTracker) and true or false)
    L:EndCard()

    L:Card("Reset")
    L:Row(UI.Button(L.current, "Back to the defaults", { width = 200, onClick = function()
        UI.Confirm({ title = "Buff reminders", text = "Put every buff reminder setting back to its default?",
            acceptText = "Reset", onAccept = function()
                ZacUIDB.buffRem = nil
                if ZacUIDB.movers then ZacUIDB.movers.buffRemIcon, ZacUIDB.movers.buffRemTracker = nil, nil end
                BR.Restyle() Fresh()
                ns.SettingsChanged("reset")
                ns.RefreshConfig()
            end })
    end }), M.BUTTON_H + 6)
    L:EndCard()
end

ns.RegisterPage("BuffRem", function(L)
    L:Header("Buff reminders", "Your group buffs: a reminder when someone is missing one, and who needs it")
    BR.Cfg()
    local rcIcon, rcTracker = BR.ReadycheckOn()
    local cls = BR.PlayerClass()
    if (rcIcon or rcTracker) and (cls == "WARRIOR" or cls == nil) then
        L:Notice("warn", "Readycheck's own Battle Shout reminder is on, so ZacUI's Battle Shout stays off "
            .. "(both would warn). Turn Readycheck's off to use this one.")
        L:Card("Readycheck")
        L:Flow({
            UI.Button(L.current, "Turn Readycheck's off", { width = 200, onClick = function()
                BR.TurnOffReadycheck() ns.RefreshConfig() end }),
            UI.Button(L.current, "Copy its settings first", { width = 200, onClick = function()
                local ok, why = BR.ImportFromReadycheck()
                lastImport = (ok and "Done: " or "Not copied: ") .. tostring(why)
                ns.RefreshConfig() end }),
        }, 8)
        if lastImport then L:Desc(lastImport) end
        L:EndCard()
    end

    if ns.CustomPick then
        ns.CustomPick.SetHandler("buffrem.frames", function(el)
            local k = type(el) == "string" and el:match("^buffrem%.(.+)$")
            if not k then return end
            ZacUIDB.config = ZacUIDB.config or {}
            ZacUIDB.config.tabs = ZacUIDB.config.tabs or {}
            local part = (k == "icon" or k == "titleIcon" or k == "rowIcon")
            ZacUIDB.config.tabs.buffrem = part and "pos" or "text"
            ns.RefreshConfig()
        end)
    end

    local _, primary = PreviewBuffs()
    local modes = { { id = "missing", label = "Someone missing" }, { id = "low", label = "Running low" },
        { id = "buffed", label = "All buffed" } }
    if primary and primary.reach == "raid" then modes[#modes + 1] = { id = "raid", label = "Raid" } end
    -- a buff with a reagent (the group cast): its count running low
    if primary and primary.group then modes[#modes + 1] = { id = "reagent", label = "Reagent low" } end
    L:Preview({
        key = "buffrem.frames", title = "Buff reminders",
        width = 300, height = 120, modes = modes, modesLabel = "Show",
        build = BuildPreview, update = UpdatePreview, replay = ReplayPreview,
    })

    L:Tabs({
        { id = "general", label = "General",   build = Tab_general },
        { id = "look",    label = "Look",      build = Tab_look },
        { id = "text",    label = "Text",      build = Tab_text },
        { id = "anim",    label = "Animation", build = Tab_anim },
        { id = "pos",     label = "Position",  build = Tab_pos },
        { id = "adv",     label = "Advanced",  build = Tab_adv },
    })
end)
