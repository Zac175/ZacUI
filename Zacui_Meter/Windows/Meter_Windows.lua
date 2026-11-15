-- Meter_Windows - the meter windows' settings, rows, sorting, displays
-- and the refresh tick. The module entry point (Modules.meter) lives at
-- the bottom of this file. The window itself - its frame, header, lock
-- and grip, drag and snap, the add / close of windows, the preview
-- window and the restyle - is Meter_Win_Frame; its menus are
-- Meter_Win_Menus (Meter v2, 2026-11-07).
-- Part of ZacUI; load order is set by the TOC.
--
-- THE DEFAULTS ARE ZAC'S DETAILS SETUP, read from his SavedVariables
-- (profile "Naowh" + the Zacw window layout), not a summary of it:
--   * two windows: TinyThreat bottom-center (unlocked), Damage Done
--     bottom-right (locked), both open; sizes and anchors exact
--   * bare black rectangle at 40% alpha - no title bar, no status bar,
--     no window border, no attribute label (his profile disables all)
--   * rows: 23px + 1 gap, NaowhLeft fill in class colors over a Melli
--     black 69% background spanning the whole row, a hairline black
--     border, spec-or-class icon 18.98px riding the bar's left end,
--     Naowh 13px with a 1,-1 black shadow and no outline
--   * his own bar wears the profile's SELF deep red (use_self_color)
--   * right text is his custom "{data1} I {data2}": total, a literal
--     capital I, then the per-second value - no percent
--   * toolbar icons only appear while the mouse is over the window
--     (auto_hide_menu), overlapping by 3px, close button hidden - the
--     "hover" header of v2; since v2 every window wears the header bar
--     (the rev-8 migration, the one deliberate change of look)
--   * update tick every 3 seconds (his update_speed), gated on the
--     parser's dirty flag so an idle meter costs nothing
--   * windows are mouse-through during combat (clickthrough), window 1
--     entirely so

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Col = ns.Col
local Meter = ns.Meter
local Modules = ns.Modules
local Print = ns.Print
local ZUI = ns.ZUI

local floor, max, format = math.floor, math.max, string.format
local wipe, tsort, tinsert = wipe, table.sort, table.insert

local ROW_TEX = Meter.TEX_BAR
local ROW_BG_TEX = Meter.TEX_BAR_BG
local FONT = Meter.FONT
local CLASS_COLORS = Meter.CLASS_COLORS

-- ============================================================
-- SETTINGS
-- ============================================================
local function DB()
    ZacUIDB.meter = ZacUIDB.meter or {}
    local d = ZacUIDB.meter
    -- a meter save written for the first time on this call (a fresh
    -- install, a new profile, Reset ZacUI)
    local fresh = false
    if not d._rev or d._rev < 1 then
        wipe(d)
        d._rev = 1
        fresh = true
        d.enabled = true
        d.updateSpeed = 3          -- his update_speed (seconds)
        d.psAbbrev = 2             -- ToK: "12.3K"
        d.timeType = 2             -- effective (elapsed) time DPS
        d.segmentsAmount = 40
        d.minCombatTime = 5
        d.overallClearNewBoss = true
        d.removeRealm = true
        d.reportLines = 5
        d.rowHeight = 23
        d.rowGap = 1
        d.fontSize = 13
        d.rowBgAlpha = 0.6899999976158142
        d.iconSizeOffset = -4.020000457763672
        d.useSpecIcons = true
        d.useSelfColor = true
        -- his profile set bg 0,0,0 @ 0.4 but backdrop_texture = "None",
        -- so Details never actually DREW it - the window was fully
        -- transparent. bgShown carries that; the alpha waits in case he
        -- ever wants a fill.
        d.bgShown = false
        d.bgAlpha = 0.4000000357627869
        d.windows = {
            -- window 1: the TinyThreat host. libwindow point BOTTOM.
            -- Closed on a fresh install (2026-11-08, Zac: "why is the
            -- threat meter on by default"): a new user switches it on
            -- from the Damage meter page or the + in a window's header.
            -- This block only runs on a meter save that has never been
            -- written (_rev nil), so a save with it open keeps it open.
            { open = false, display = "threat",
              point = "BOTTOM", x = 215.3836669921875, y = 98.97835540771484,
              w = 159.4192199707031, h = 133.9609222412109,
              locked = true, clickthrough = true, segment = 0,
              lastMeterDisplay = "damage_done" },
            -- window 2: Damage Done, locked, bottom-right. (2026-11-08,
            -- Zac: "by default I only want the 1 damage meter showing")
            -- the one window a fresh install shows: 8 in from the right
            -- edge (the bars' fresh margin) and clear of the micro menu
            -- and bag bar in the bottom-right corner below it
            { open = true, display = "damage_done",
              point = "BOTTOMRIGHT", x = -8, y = 124,
              w = 225.6758728027344, h = 199.8019866943359,
              locked = true, clickthrough = false, segment = 0,
              lastMeterDisplay = "damage_done" },
        }
        -- (2026-11-10) an install made from now on: the threat window,
        -- when it is switched on, opens beside the damage window instead
        -- of on Blizzard's action bars at the bottom of the screen
        if ns.NewDefaults and ns.NewDefaults() then
            local t = d.windows[1]
            t.point, t.x, t.y = "BOTTOMRIGHT", -240, 124
        end
        d.threat = {
            updateSpeed = 1, absoluteMode = false, hidePullBar = false,
            onlyMyGroup = false, showPartyPets = false,
            -- (2026-11-08, Zac: off by default) the screen-edge glow is
            -- written off on a fresh save only; an older save keeps the
            -- class default it already had (nil = on for a warrior)
            glow = false,
        }
    end
    -- REV 2: rev 1 shipped the window background drawn - a faithful port
    -- of the SETTING but not of the RESULT (Details' "None" backdrop
    -- means nothing is ever painted). Transparent is the true default.
    if d._rev == 1 then
        d.bgShown = false
        d._rev = 2
    end
    -- REV 3: both windows lock by default. The saved Details layout had
    -- the threat window's flag false, but locked is how the setup plays
    -- - and an unlocked window eats drags meant for the world. Unlock
    -- lives in the hover toolbar's first menu and on the config page.
    if d._rev == 2 then
        for _, w in ipairs(d.windows) do w.locked = true end
        d._rev = 3
    end
    -- REV 4: one-time restore of the threat window to the ported Details
    -- anchor - it caught an accidental drag before the lock default
    -- landed. Values are the Zacw layout verbatim; runs once, so moving
    -- it on purpose afterwards sticks.
    if d._rev == 3 then
        local w1 = d.windows[1]
        if w1 then
            w1.point, w1.x, w1.y = "BOTTOM", 215.3836669921875, 98.97835540771484
            w1.w, w1.h = 159.4192199707031, 133.9609222412109
            w1.locked = true
        end
        d._rev = 4
    end
    -- REV 5: the threat window turned into a damage meter mid-raid. It is
    -- one stray pick away at all times - the hover toolbar's "mode" menu
    -- and its attribute menu both offer every display, on a window you
    -- only ever read, never operate. Losing threat on a warrior in the
    -- middle of a pull is not a cosmetic mistake.
    --
    -- Re-asserted by POSITION, not by index: window order is not a
    -- promise, and the ask was about sides of the screen. Whichever
    -- window is anchored to the right edge shows the group meter; the
    -- first one that is not shows threat. Runs once per profile, so
    -- swapping them ON PURPOSE afterwards still sticks.
    -- FLOOR, NOT EQUALITY, and that is not tidiness. Three of the live
    -- profiles were already sitting at _rev 5 from an earlier build, so
    -- an "== 4" gate would have skipped exactly the accounts that needed
    -- checking and reported success. The rest of the chain above can use
    -- equality because it walks 1-2-3-4 in order from a known start;
    -- this one has to catch anything that never saw it.
    if (d._rev or 0) < 6 then
        local right, inner
        for _, w in ipairs(d.windows) do
            if tostring(w.point or ""):find("RIGHT") then
                right = right or w
            else
                inner = inner or w
            end
        end
        if right and right.display == "threat" then
            right.display = right.lastMeterDisplay or "damage_done"
        end
        if inner then
            -- Keep whatever meter it was showing as the "back" option, so
            -- the toolbar's Group meter entry returns to that one.
            -- No DISPLAYS lookup here on purpose: DISPLAYS is a file
            -- local declared BELOW this function, so it is not an upvalue
            -- DB can see. A bad key just falls back at read time.
            if inner.display and inner.display ~= "threat" then
                inner.lastMeterDisplay = inner.display
            end
            inner.display = "threat"
        end
        d._rev = 6
    end
    -- REV 7: an OVERALL window, and an overall that means it.
    --
    -- The window: a third meter stacked above the damage window on the
    -- right edge, same size, pinned to segment -1. Sized and placed from
    -- whatever the right-edge window is at the moment, so it lands next
    -- to it wherever it has been dragged.
    --
    -- The setting: "reset overall on a new raid boss" goes OFF. Overall
    -- is now the whole night - every boss, every trash pull - which is
    -- what a window called Overall next to one called Current is for.
    -- The checkbox is still on the config page for anyone who wants the
    -- per-boss behaviour back.
    if (d._rev or 0) < 7 then
        local right
        for _, w in ipairs(d.windows) do
            if tostring(w.point or ""):find("RIGHT") and w.display ~= "threat" then
                right = right or w
            end
        end
        local base = right or d.windows[#d.windows] or {}
        d.windows[#d.windows + 1] = {
            -- (2026-11-08) a fresh install keeps it closed: one damage
            -- window on the screen; the Meter page's "Show window 3" (or
            -- the + in a window's header, for a new one) brings it up
            open = not fresh, display = "damage_done",
            point = base.point or "BOTTOMRIGHT",
            x = base.x or 0,
            y = (base.y or 0) + (base.h or 200) + 6,
            w = base.w or 225, h = base.h or 200,
            locked = true, clickthrough = false, segment = -1,
            lastMeterDisplay = "damage_done",
        }
        d.overallClearNewBoss = false
        d._rev = 7
    end
    -- REV 8: METER V2 (2026-11-07). Zac: "his damage meters and stuff are
    -- so much better than mine mine need a lot of cleanup and redoing."
    -- Every window gets the header bar (the mode and the fight clock,
    -- the icons at its right) and rank numbers before the names. The one
    -- deliberate change of look since the rules said "nil = today's":
    -- the redo was the ask, and the old look is one pick away (the
    -- header's "Hover toolbar"). The header sits INSIDE the window now
    -- (the old title bar sat on top of it), so every window grows by the
    -- header's height once and keeps every row it had.
    if (d._rev or 0) < 8 then
        d.headerMode = "bar"
        d.showRank = true
        local hh = math.max(8, tonumber(d.titleHeight) or 18)
        for _, w in ipairs(d.windows) do
            if type(w.h) == "number" then w.h = w.h + hh end
        end
        d._rev = 8
    end
    -- REV 9: THE HEADER POLISHED (2026-11-07, Zac: "the headers you added
    -- for the damage meters just looks like shit"). The header grows from
    -- 18 to 22 px when it is still at the shipped 18 (every window grows
    -- by the 4 px once, so no row is lost), and wears the rows' own dark
    -- (black 0.69 instead of 0.6) when its colour is still the shipped one.
    if (d._rev or 0) < 9 then
        local th = tonumber(d.titleHeight)
        if th == nil or th == 18 then
            if th ~= nil then d.titleHeight = 22 end
            for _, w in ipairs(d.windows) do
                if type(w.h) == "number" then w.h = w.h + 4 end
            end
        end
        local c = d.titleColor
        if type(c) == "table" and c.r == 0 and c.g == 0 and c.b == 0 and c.a == 0.6 then
            d.titleColor = { r = 0, g = 0, b = 0, a = 0.6899999976158142 }
        end
        d._rev = 9
    end
    -- REV 10: THE MATCH PASS (2026-11-07, Zac: make it match the reference
    -- meter). The header wears the reference's opaque #1B1B1B and its icons
    -- grow from 14 to 22, each only while it is still the value ZacUI
    -- shipped (black at 0.69 / 14): a colour or size set by hand stays.
    -- Nothing else moves: the header keeps its height, so no row is lost.
    if (d._rev or 0) < 10 then
        local c = d.titleColor
        if type(c) == "table" and c.r == 0 and c.g == 0 and c.b == 0
            and type(c.a) == "number" and math.abs(c.a - 0.6899999976158142) < 1e-6 then
            d.titleColor = { r = 27 / 255, g = 27 / 255, b = 27 / 255, a = 1 }
        end
        if d.headerIconSize == 14 then d.headerIconSize = 22 end
        d._rev = 10
    end
    return d
end
Meter.DB = DB

-- ============================================================
-- LOOK - how the rows, windows and text are drawn. Every default here
-- is what the meter drew before these settings existed, so nothing
-- moves for anyone until they change it. The older keys above
-- (rowHeight, rowGap, fontSize, rowBgAlpha, iconSizeOffset,
-- useSpecIcons, useSelfColor, bgShown, bgAlpha) keep their names and
-- their saved values; the settings that grew out of them (the row and
-- window background colours, the fonts) read nil as "what those say".
-- ============================================================
local LOOK = {
    showIcons = false,                      -- (2026-11-03, Zac: "off by default")
    dmfIcon = true,                         -- the Darkmoon Faire mark after a name (2026-11-06)
    dmfOnlyBuffed = true,                   -- ...only while you have your world buffs on
    dmfHideMine = true,                     -- ...and not while you have the fortune yourself (2026-11-09)
    barColorMode = "class",                 -- "class" | "custom"
    barColor = { r = 0.33, g = 0.6, b = 0.85, a = 1 },
    barAlpha = 1,
    selfColor = { r = 0.8901961445808411, g = 0.02352941408753395, b = 0, a = 1 },
    rowHoverColor = { r = 0.588, g = 0.588, b = 0.588, a = 0.7 },
    rowBorder = true,
    rowBorderColor = { r = 0, g = 0, b = 0, a = 1 },
    rowBorderSize = 1,                      -- 1 = one screen pixel (the hairline)
    winBorder = false,
    winBorderColor = { r = 0, g = 0, b = 0, a = 1 },
    winBorderSize = 1,
    titleBar = false,
    titleHeight = 22,                       -- (rev 9: 18 -> 22)
    titleColor = { r = 27 / 255, g = 27 / 255, b = 27 / 255, a = 1 },   -- #1B1B1B, opaque (rev 10, the match pass; was black 0.69)
    titleSegment = true,
    toolbarMode = "hover",                  -- "hover" | "always" (the "hover" header)
    -- METER V2: the header bar, the pinned row, the growth, the snap
    headerMode = "bar",                     -- "bar" | "hover" (the old floating toolbar) | "none"
    headerIconsOnHover = false,             -- the bar's icons only while the mouse is on the window
    headerIconSize = 22,                    -- (rev 10, the match pass: 14 -> 22)
    headerClock = true,                     -- "(2:13)" after the mode
    titleAccent = true,                     -- (match pass) the mode's name in the accent colour, the clock white at 70%
    pinSelf = "follow",                     -- "pin" (at the edge, with a line) | "follow" (the last row) | "off"
    grow = "down",                          -- "down" | "up" (the header at the bottom, rows rising)
    snapWindows = true,                     -- dragging and resizing line up with other meter windows
    confirmReset = false,                   -- the reset icon asks first
    -- THE POLISH (2026-11-07): a line under the header, the bars' soft
    -- light and shade, thin-outlined text, the rank and the per-second
    -- figure dimmed, and how your own row stands out
    headerLine = true,
    headerLineColor = { r = 1, g = 1, b = 1, a = 0.1 },
    barFlat = true,                         -- no texture picked: a flat fill (off: the old faded bar)
    rowGloss = false,                       -- light at the top of a bar, shade at the bottom (an option)
    textOutline = true,                     -- a thin outline instead of the drop shadow
    dimRank = true,                         -- "1." dimmer than the name
    dimSecond = true,                       -- the per-second figure dimmer than the total
    selfStyle = "color",                    -- "color" (your own bar colour) | "edge" (class colour, a light edge)
    nameColorMode = "white",                -- "white" | "class" | "custom"
    nameColor = { r = 1, g = 1, b = 1, a = 1 },
    numberColor = { r = 1, g = 1, b = 1, a = 1 },
    numberLayout = "both",                  -- see RightText
    numberSep = " I ",
    showRank = true,                        -- "1. " before the names (v2; the migration turns it on)
    threatIcons = true,
    threatIconSize = 14,
    -- a row fading in over 0.2s and going at once, the segment / display
    -- label fading out over 1.6s: the timings the meter always had
    rowShowAnim = { style = "fade", duration = 0.2, delay = 0, easing = "linear" },
    rowHideAnim = { style = "none", duration = 0.2, delay = 0, easing = "linear" },
    rowMoveAnim = { style = "none", duration = 0.4, delay = 0, easing = "easeOutQuad" },
    labelAnim = { style = "fade", duration = 1.6, delay = 0, easing = "linear" },
    -- threat rows always came and went at once
    threatShowAnim = { style = "none", duration = 0.2, delay = 0, easing = "linear" },
    threatHideAnim = { style = "none", duration = 0.2, delay = 0, easing = "linear" },
}
Meter.LOOK_DEFAULTS = LOOK
-- the look keys a reset clears: the table above plus the ones whose
-- default is worked out from an older setting
Meter.LOOK_KEYS = { "rowHeight", "rowGap", "fontSize", "rowBgAlpha", "iconSizeOffset", "useSpecIcons",
    "useSelfColor", "bgShown", "bgAlpha", "rowBgColor", "rowBgTexture", "bgColor", "titleTexture",
    "nameFont", "numberFont", "titleFont", "threatFont", "bar", "psAbbrev", "removeRealm" }
for k in pairs(LOOK) do Meter.LOOK_KEYS[#Meter.LOOK_KEYS + 1] = k end
-- the values the older keys shipped with (DB's rev 1), for a reset
Meter.LOOK_BASE = { rowHeight = 23, rowGap = 1, fontSize = 13, rowBgAlpha = 0.6899999976158142,
    iconSizeOffset = -4.020000457763672, useSpecIcons = true, useSelfColor = true,
    bgShown = false, bgAlpha = 0.4000000357627869, psAbbrev = 2, removeRealm = true }

-- Filled once per saved table: a profile worn replaces ZacUIDB.meter
-- with a new table, which is filled the first time it is read.
local filledFor
local function Look()
    local d = DB()
    if filledFor ~= d then
        filledFor = d
        if ns.FillDefaults then ns.FillDefaults(d, LOOK) end
        for k, v in pairs(Meter.LOOK_BASE) do if d[k] == nil then d[k] = v end end
    end
    return d
end
Meter.Look = Look
function Meter.ForgetLook() filledFor = nil end

-- ============================================================
-- WHO HAS THE DARKMOON FAIRE DAMAGE BUFF (Zac 2026-11-06: "can i get a dmf
-- icon on the players if i dont have dmf for example to see who is ratting
-- dmf?"). Sayge's Dark Fortune of Damage (+10% damage): a small mark after
-- the name of everyone who has it (look.dmfIcon, on). In a raid only, and
-- (look.dmfOnlyBuffed, on) only while you have your own world buffs on
-- (Zac: "should really only show in raid and then only when i have buffs
-- out"). Read from the raid every 15 s, a second after the roster changes
-- and as a fight starts - never from UNIT_AURA; nothing is read outside a
-- raid. Meter.DMF[guid] = true while they have it.
-- ============================================================
local DMF_SPELL = 23768
Meter.DMF_SPELL = DMF_SPELL
Meter.DMF = {}
function Meter.DMFTexture()
    return (GetSpellTexture and GetSpellTexture(DMF_SPELL)) or "Interface\\Icons\\INV_Misc_Orb_02"
end
-- your world buffs (any one of them = "buffs out"); Sayge's own is not one
local WORLD_BUFFS = {
    [22888] = true,   -- Rallying Cry of the Dragonslayer
    [16609] = true,   -- Warchief's Blessing
    [24425] = true,   -- Spirit of Zandalar
    [15366] = true,   -- Songflower Serenade
    [22817] = true, [22818] = true, [22820] = true,   -- Fengus' Ferocity, Mol'dar's Moxie, Slip'kik's Savvy
}
Meter.WORLD_BUFFS = WORLD_BUFFS
local function HasDMF(u, alsoWorld)
    if not UnitBuff then return false end
    local dmf, world = false, false
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, sid = UnitBuff(u, i)
        if not name then break end
        if sid == DMF_SPELL then dmf = true end
        if alsoWorld and WORLD_BUFFS[sid] then world = true end
    end
    return dmf, world
end
Meter.meBuffed = false
-- the mark shows now (a raid, and your buffs out when that is asked)
-- Classic Era's world buffs: off on TBC and Forever (Core_Flavor), where
-- nothing is read and no mark is drawn
local dmfOn = not (ns.FeatureOn and not ns.FeatureOn("meter_dmf"))
Meter.DMF_ON = dmfOn
-- TBC: Sayge's fortune is the same spell there (23768, Wowhead TBC), but
-- TBC is not raided on Classic Era's world buffs, so "only while my world
-- buffs are on" is not asked there: the mark shows in any raid
local worldBuffNights = not (ns.Flavor and ns.Flavor() ~= "era")
Meter.DMF_WORLD_BUFFS = worldBuffNights
function Meter.DMFShowNow(d)
    if not dmfOn then return false end
    d = d or Look()
    if d.dmfIcon == false or not IsInRaid() then return false end
    -- (2026-11-09, Zac: "the dmf icon should hide if i have dmf only show
    -- if others have it and i dont") with the fortune on yourself there is
    -- nobody to catch out: no marks, unless the switch is off
    if d.dmfHideMine ~= false and Meter.meDMF then return false end
    if not worldBuffNights then return true end
    return d.dmfOnlyBuffed == false or Meter.meBuffed
end
local dmfTicker, dmfSoon
local function DMFScan()
    dmfSoon = nil
    if not dmfOn then return end
    local d = Look()
    if d.dmfIcon == false or not IsInRaid() then
        -- nothing read outside a raid; what was there goes
        if next(Meter.DMF) or Meter.meBuffed or Meter.meDMF then
            wipe(Meter.DMF)
            Meter.meBuffed = false
            Meter.meDMF = false
            if Meter.DirtyAll then Meter.DirtyAll() end
        end
        return
    end
    local changed = false
    local mine, world = HasDMF("player", true)
    if world ~= Meter.meBuffed then Meter.meBuffed = world changed = true end
    mine = mine and true or false
    if mine ~= (Meter.meDMF or false) then Meter.meDMF = mine changed = true end
    for i = 1, 40 do
        local u = "raid" .. i
        local g = UnitGUID(u)
        if g then
            local has = HasDMF(u) or nil
            if Meter.DMF[g] ~= has then Meter.DMF[g] = has changed = true end
        end
    end
    if changed and Meter.DirtyAll then Meter.DirtyAll() end
end
Meter.DMFScan = DMFScan
if dmfOn then
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function()
        if not dmfSoon then dmfSoon = true C_Timer.After(1, DMFScan) end
        if not dmfTicker then
            dmfTicker = C_Timer.NewTicker(15, DMFScan)
            if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(dmfTicker, "meter.dmf") end
        end
    end)
end

local FLAT_TEX = ns.FLAT or "Interface\\Buttons\\WHITE8X8"
local function ColorOf(c, fr, fg, fb, fa)
    if type(c) == "table" then
        return c.r or c[1] or fr, c.g or c[2] or fg, c.b or c[3] or fb, c.a or c[4] or fa or 1
    end
    return fr, fg, fb, fa or 1
end
Meter.ColorOf = ColorOf
Meter.RowBgColor = function(d)
    -- (2026-11-08) under the Classic look a bar's track is a quarter black,
    -- the stock meter's, unless a row colour was picked
    if d.rowBgColor == nil and Meter.IsClassicLook and Meter.IsClassicLook() then return 0, 0, 0, 0.25 end
    return ColorOf(d.rowBgColor, 0, 0, 0, d.rowBgAlpha or 0.69)
end
Meter.WinBgColor = function(d) return ColorOf(d.bgColor, 0, 0, 0, d.bgAlpha or 0.4) end

-- What a nil font field means for each text the meter draws: the
-- meter's own font (the Fonts & Textures push, else the profile's),
-- at the row font size, exactly as the text was set before.
function Meter.NameFontDefaults(d)
    -- (look.textOutline, on since the 2026-11-07 polish: a thin outline;
    -- off, the drop shadow it always had)
    if d.textOutline ~= false then
        return { face = Meter.FontPath(), size = d.fontSize or 13, outline = "outline", shadow = false }
    end
    return { face = Meter.FontPath(), size = d.fontSize or 13, outline = "none", shadow = true, shadowX = 1, shadowY = -1 }
end
Meter.NumberFontDefaults = Meter.NameFontDefaults
function Meter.TitleFontDefaults()
    return { face = Meter.FontPath(), size = 12, outline = "none", shadow = true, shadowX = 1, shadowY = -1 }
end
function Meter.ThreatFontDefaults(d)
    return { face = Meter.FontPath(), size = d.fontSize or 13, outline = "outline", shadow = false }
end

-- ============================================================
-- DISPLAYS - what a window can show. reader() returns the sort value
-- for an actor; ps says whether a per-second figure joins the total in
-- the right text. container picks which actor set feeds the rows.
-- ============================================================
local function ActivityDps(actor, combat, combatTime)
    local d = DB()
    if d.timeType == 2 and actor.grupo then
        return actor.total / combatTime
    end
    return actor.total / actor:ActivityTime()
end

local DISPLAYS = {
    damage_done = {
        label = "Damage Done", desc = "All the damage each player did, their pets included.",
        container = "damage",
        value = function(a) return a.total end, ps = ActivityDps,
        icon = true,
    },
    dps = {
        label = "DPS", desc = "Damage per second over the time each player was fighting.",
        container = "damage",
        value = function(a, c, ct) return a.lastDps or 0 end,
        prepare = function(a, c, ct) a.lastDps = ActivityDps(a, c, ct) end,
        single = true, icon = true,
    },
    damage_taken = {
        label = "Damage Taken", desc = "Damage each player took, from everything that hit them.",
        container = "damage",
        value = function(a) return a.damageTaken end,
        ps = function(a, c, ct) return a.damageTaken / ct end, icon = true,
    },
    friendly_fire = {
        label = "Friendly Fire", desc = "Damage players did to their own group.",
        container = "damage",
        value = function(a) return a.friendlyFireTotal end, single = true,
        icon = true,
    },
    enemy_taken = {
        label = "Enemy Damage Taken", desc = "The enemies of the fight, by how much the group hit each of them.",
        container = "damage", enemies = true,
        value = function(a) return a.damageTaken end,
        ps = function(a, c, ct) return a.damageTaken / ct end, icon = true,
    },
    heal_done = {
        label = "Healing Done", desc = "Healing that landed, not counting overheal.",
        container = "heal",
        value = function(a) return a.total end,
        ps = function(a, c, ct)
            local d = DB()
            if d.timeType == 2 and a.grupo then return a.total / ct end
            return a.total / a:ActivityTime()
        end,
        icon = true,
    },
    hps = {
        label = "HPS", desc = "Healing per second over the time each healer was healing.",
        container = "heal",
        value = function(a, c, ct) return a.lastDps or 0 end,
        prepare = function(a, c, ct)
            local d = DB()
            if d.timeType == 2 and a.grupo then a.lastDps = a.total / ct
            else a.lastDps = a.total / a:ActivityTime() end
        end,
        single = true, icon = true,
    },
    overheal = {
        label = "Overhealing", desc = "Overheal: healing past full health, so wasted.",
        container = "heal",
        value = function(a) return a.totalOver end, single = true, icon = true,
    },
    absorbs = {
        label = "Damage Prevented", desc = "Shields that absorbed damage, credited to the caster.",
        container = "heal",
        value = function(a) return a.totalAbsorb end, single = true, icon = true,
    },
    heal_taken = {
        label = "Healing Taken", desc = "Healing each player received, from every healer.",
        container = "heal",
        value = function(a) return a.healingTaken end,
        ps = function(a, c, ct) return a.healingTaken / ct end, icon = true,
    },
    deaths = {
        label = "Deaths", desc = "Who died, what killed them and the hits before it. Click one for the full recap.",
        container = "misc",
        value = function(a) return a.dead or 0 end, count = true, icon = true,
    },
    interrupts = {
        label = "Interrupts", desc = "Spells each player stopped mid-cast.",
        container = "misc",
        value = function(a) return a.interrupt or 0 end, count = true, icon = true,
    },
    dispels = {
        label = "Dispels", desc = "Buffs and debuffs each player removed.",
        container = "misc",
        value = function(a) return a.dispell or 0 end, count = true, icon = true,
    },
    cc_breaks = {
        label = "CC Breaks", desc = "Crowd control each player broke early (sheep, shackle, trap...).",
        container = "misc",
        value = function(a) return a.cc_break or 0 end, count = true, icon = true,
    },
    ress = {
        label = "Battle Ress", desc = "Players brought back up during a fight.",
        container = "misc",
        value = function(a) return a.ress or 0 end, count = true, icon = true,
    },
}

local DISPLAY_ORDER = {
    "damage_done", "dps", "damage_taken", "friendly_fire", "enemy_taken",
    "heal_done", "hps", "overheal", "absorbs", "heal_taken",
    "deaths", "interrupts", "dispels", "cc_breaks", "ress",
    "threat",
}
Meter.DISPLAYS = DISPLAYS
Meter.DISPLAY_ORDER = DISPLAY_ORDER
-- the mode menu's groups (Meter_Win_Menus): threat is its own entry
Meter.GROUPS = {
    { label = "Damage", desc = "Damage done and taken, per second, friendly fire, the enemies.",
      keys = { "damage_done", "dps", "damage_taken", "friendly_fire", "enemy_taken" } },
    { label = "Healing", desc = "Healing done and taken, per second, overheal, shields.",
      keys = { "heal_done", "hps", "overheal", "absorbs", "heal_taken" } },
    { label = "Actions", desc = "Deaths, interrupts, dispels, broken crowd control, battle resurrections.",
      keys = { "deaths", "interrupts", "dispels", "cc_breaks", "ress" } },
}
-- what the threat window shows, for the mode menu (it is not a DISPLAYS row)
Meter.THREAT_DESC = "Your target's threat list: how close each player is to pulling it."

-- ============================================================
-- SMALL SHARED BITS
-- ============================================================
local windows = {}
Meter.windowFrames = windows

-- Declared here, ahead of the scroll handler that calls into both. A
-- method defined on a table that does not exist yet, or a call to a
-- local that is declared further down, both resolve to globals and
-- fail at the first wheel tick rather than at load.
local winMeta = {}
winMeta.__index = winMeta
-- the window object's methods: the frame, header, drag and menus are
-- added by Meter_Win_Frame / Meter_Win_Menus (Meter v2)
Meter.winMeta = winMeta
local RefreshMeterWindow

-- ============================================================
-- SCROLLING
-- ============================================================
-- A window shows rowsFit rows of a list that is usually longer - forty
-- people in a raid, seven rows on screen. The wheel moves a window-level
-- offset into the sorted list; the refresh reads from it. Clamped on
-- every refresh rather than on every wheel tick, because the list length
-- changes underneath it (a segment change, a reset) and an offset past
-- the end would show an empty window that is not empty.
local WHEEL_STEP = 3

function winMeta:Scroll(delta)
    local before = self.scroll or 0
    local after = before - delta * WHEEL_STEP
    if after < 0 then after = 0 end
    local most = self.scrollMax or 0
    if after > most then after = most end
    if after == before then return end
    self.scroll = after
    RefreshMeterWindow(self, true)
end

-- Rows have the mouse enabled for their own clicks, which makes them
-- the frame under the cursor - so the wheel has to be theirs as well, or
-- it only works in the gaps between rows.
local function WireWheel(frame, win)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) win:Scroll(delta) end)
end

local function DisplayName(actor)
    local name = actor.displayName
    if name then return name end
    name = actor.name
    if DB().removeRealm and not actor.ownerName then
        local cut = name:find("-", 1, true)
        if cut then name = name:sub(1, cut - 1) end
    end
    actor.displayName = name
    return name
end

-- r, g, b, a for an actor's bar: the SELF red for my own bar (when
-- asked), else one colour for everyone or the class colour
local function BarColor(actor, d)
    if actor.isSelf and d.useSelfColor and d.selfStyle ~= "edge" then
        local s = CLASS_COLORS.SELF
        return ColorOf(d.selfColor, s[1], s[2], s[3], 1)
    end
    if d.barColorMode == "custom" then return ColorOf(d.barColor, 0.33, 0.6, 0.85, 1) end
    local c = actor.class and CLASS_COLORS[actor.class] or CLASS_COLORS.UNKNOW
    return c[1], c[2], c[3], 1
end

local function SetRowIcon(row, actor, d)
    local tex, l, r, t, b
    if d.useSpecIcons and actor.spec then tex, l, r, t, b = Meter.SpecIcon(actor.spec) end
    if not tex then
        -- the client's own class art (ns.ClassIcon, Core_Pixel) where the
        -- core has it - only ever reached with the icons on (off by
        -- default: Zac, 2026-11-03)
        if ns.ClassIcon and actor.class then
            local ok, done = pcall(ns.ClassIcon, row.icon, actor.class)
            if ok and done then return end
        end
        tex, l, r, t, b = Meter.ClassIcon(actor.class)
    end
    row.icon:SetTexture(tex)
    row.icon:SetTexCoord(l, r, t, b)
end
-- (Meter v2: the in-window breakdown paints its rows with these too)
Meter.BarColor, Meter.SetRowIcon, Meter.DisplayName = BarColor, SetRowIcon, DisplayName

-- n screen pixels in UI units. One is the hairline the row border has
-- always been: Details' 0.54, snapped to one physical pixel.
local function Pixels(n)
    n = tonumber(n) or 1
    if n <= 0 then return 0 end
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        return PixelUtil.GetNearestPixelSize(0.54 * n, UIParent:GetEffectiveScale(), 0.54 * n)
    end
    return 0.6 * n
end
local function Hairline() return Pixels(1) end
Meter.Pixels = Pixels

-- four edge textures just outside `owner`, `size` thick. `px` (the row
-- borders, 2026-11-07 polish): under ZacUI's own look the thickness is
-- that many PHYSICAL pixels (ns.Pixel.One, Core_Pixel) so a 1 px border is
-- exactly one pixel at any UI scale; any other look, or a core without
-- ns.Pixel, keeps `size`.
local function PlaceEdges(edges, owner, size, px)
    local LK = ns.Look
    local lookId = LK and ((LK.For and LK.For("meter") and LK.For("meter").id) or (LK.Active and LK.Active()))
    if px and ns.Pixel and ns.Pixel.One and lookId == "zacui" then
        local ok, one = pcall(ns.Pixel.One, owner)
        local n = tonumber(px) or 1
        if ok and type(one) == "number" and one > 0 and n > 0 then size = one * n end
    end
    local e1, e2, e3, e4 = edges[1], edges[2], edges[3], edges[4]
    for i = 1, 4 do edges[i]:ClearAllPoints() end
    e1:SetPoint("TOPLEFT", owner, "TOPLEFT", -size, size)
    e1:SetPoint("BOTTOMRIGHT", owner, "TOPRIGHT", size, 0)       -- top
    e2:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", -size, 0)
    e2:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", size, -size) -- bottom
    e3:SetPoint("TOPRIGHT", owner, "TOPLEFT", 0, 0)
    e3:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -size, 0)     -- left
    e4:SetPoint("TOPLEFT", owner, "TOPRIGHT", 0, 0)
    e4:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", size, 0)    -- right
end
Meter.PlaceEdges = PlaceEdges

-- ============================================================
-- ROW ANIMATIONS - through ns.Motion, so the global switch and speed
-- apply. A row going away with an animation stays shown until it has
-- gone; _zLeaving marks it so a refresh that wants it back brings it
-- back instead of letting the hide finish under a live actor.
-- ============================================================
-- key: the animation setting to use (the meter rows' by default; the
-- threat rows pass their own)
function Meter.ShowRow(row, key)
    local Motion = ns.Motion
    local was = row._zLeaving
    row._zLeaving = nil
    if Motion then
        if was or not row:IsShown() then Motion.Show(row, Look()[key or "rowShowAnim"]) end
    elseif not row:IsShown() then
        row:Show()
    end
end

function Meter.HideRow(row, key)
    if not row:IsShown() or row._zLeaving then return end
    local Motion = ns.Motion
    local spec = Look()[key or "rowHideAnim"]
    if Motion and type(spec) == "table" and spec.style ~= "none" and row:IsVisible() then
        row._zLeaving = true
        Motion.Hide(row, spec, function() row._zLeaving = nil end)
    else
        if Motion then Motion.Stop(row) end
        row:Hide()
    end
end

-- put a row back at rest before it is re-anchored (Motion puts back the
-- anchors it started from when a play ends)
function Meter.SettleRow(row)
    if ns.Motion then ns.Motion.Stop(row) end
    if row._zLeaving then row._zLeaving = nil row:Hide() end
end

local function PlayMove(row, d)
    local spec = d.rowMoveAnim
    if ns.Motion and type(spec) == "table" and spec.style ~= "none" and row:IsVisible()
        and not ns.Motion.IsPlaying(row) then
        ns.Motion.Play(row, spec, "update")
    end
end

-- ============================================================
-- ROWS
-- ============================================================
-- WHERE THE TEXTS AND THE ICON SIT. Each has its built-in spot (exactly
-- the SetPoint it always had); the meter's saved anchor (look.anchors.
-- <name|value|icon|title>, ZacUI's anchor shape) goes on top, onto any
-- corner of the row, its bar, or the row's other pieces. Nothing saved =
-- the old points, exactly.
Meter.ANCHOR_TEXTS = { "name", "value", "title" }
Meter.ANCHOR_PARTS = { "icon" }
Meter.ANCHOR_LABELS = { row = "The row", bar = "The bar", icon = "Class icon", name = "Name",
    value = "Value", title = "Title text", titlebar = "The title bar",
    threatIcon = "Role icon", threatName = "Name", threatValue = "Threat" }
-- the threat rows' own pieces (Meter_Threat places them)
Meter.THREAT_TARGETS = { "row", "threatIcon", "threatName", "threatValue" }
Meter.ROW_TARGETS = { "row", "bar", "icon", "name", "value" }
local function RowTarget(row, k)
    if k == "row" then return row elseif k == "bar" then return row.bar
    elseif k == "icon" then return row.icon elseif k == "name" then return row.leftText
    elseif k == "value" then return row.rightText end
end
local function AnchorOf(d, key)
    local a = d.anchors
    return type(a) == "table" and a[key] or nil
end
local function RowDef(row, key)
    local D = row.anchorDef
    if not D then D = {} row.anchorDef = D end
    local t = D[key]
    if not t then t = {} D[key] = t end
    return t
end
-- what each spot is, for the page's pickers (no frame needed)
function Meter.AnchorDefaults(key)
    local d = Look()
    if key == "value" then return { point = "RIGHT", relPoint = "RIGHT", x = 0, y = 0, justify = "RIGHT" }
    elseif key == "icon" then return { point = "LEFT", relPoint = "LEFT", x = 0, y = 0 }
    elseif key == "title" then return { point = "LEFT", relPoint = "LEFT", x = 4, y = 0, justify = "LEFT" }
    elseif key == "threatIcon" then return { point = "LEFT", relPoint = "LEFT", x = 1, y = 0 }
    elseif key == "threatValue" then return { point = "RIGHT", relPoint = "RIGHT", x = -3, y = 0, justify = "RIGHT" }
    elseif key == "threatName" then
        if d.threatIcons ~= false then return { point = "LEFT", relPoint = "RIGHT", x = 3, y = 0, justify = "LEFT" } end
        return { point = "LEFT", relPoint = "LEFT", x = 3, y = 0, justify = "LEFT" }
    end
    if d.showIcons ~= false then return { point = "LEFT", relPoint = "RIGHT", x = 3, y = 0, justify = "LEFT" } end
    return { point = "LEFT", relPoint = "LEFT", x = 3, y = 0, justify = "LEFT" }
end

-- A texture's vertical gradient (the client's call of the day: SetGradient
-- with colours, or the older SetGradientAlpha), from the bottom colour to
-- the top one
local function Gradient(tex, r1, g1, b1, a1, r2, g2, b2, a2)
    if CreateColor and tex.SetGradient then
        if pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2)) then return end
    end
    if tex.SetGradientAlpha then pcall(tex.SetGradientAlpha, tex, "VERTICAL", r1, g1, b1, a1, r2, g2, b2, a2) end
end

-- THE BAR'S LIGHT AND SHADE (look.rowGloss): two thin layers over the
-- fill - light fading out from the top edge, shade fading in to the
-- bottom - so a bar reads as a plate, whatever its texture and colour.
-- On the fill texture's own area, so they end where the bar ends.
local function Gloss(row, d)
    local on = d.rowGloss == true
    if not row.glossTop then
        if not on then return end
        row.glossTop = row.bar:CreateTexture(nil, "ARTWORK", nil, 3)
        row.glossBot = row.bar:CreateTexture(nil, "ARTWORK", nil, 3)
        for _, t in ipairs({ row.glossTop, row.glossBot }) do t:SetTexture(FLAT_TEX) end
        row.glossTop:SetPoint("TOPLEFT", row.tex, "TOPLEFT", 0, 0)
        row.glossTop:SetPoint("TOPRIGHT", row.tex, "TOPRIGHT", 0, 0)
        row.glossBot:SetPoint("BOTTOMLEFT", row.tex, "BOTTOMLEFT", 0, 0)
        row.glossBot:SetPoint("BOTTOMRIGHT", row.tex, "BOTTOMRIGHT", 0, 0)
        Gradient(row.glossTop, 1, 1, 1, 0, 1, 1, 1, 0.18)
        Gradient(row.glossBot, 0, 0, 0, 0.28, 0, 0, 0, 0)
    end
    local h = (d.rowHeight or 23) / 2
    row.glossTop:SetHeight(h)
    row.glossBot:SetHeight(h)
    row.glossTop:SetShown(on)
    row.glossBot:SetShown(on)
end
Meter.Gloss = Gloss

-- YOUR ROW'S EDGE (look.selfStyle = "edge"): the row's border lit and a
-- thin accent stripe at its left, over the class-coloured bar. Only
-- touched when the row's state changes.
function Meter.SelfEdge(row, on, d)
    on = on and true or false
    if (row._edge or false) == on then return end
    row._edge = on
    if on and not row.edgeStripe then
        row.edgeStripe = row.bar:CreateTexture(nil, "OVERLAY", nil, 6)
        row.edgeStripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.edgeStripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        row.edgeStripe:SetWidth(2)
    end
    if row.edgeStripe then
        local a = ns.GetColor("ui", "accent")
        row.edgeStripe:SetColorTexture(a.r, a.g, a.b, 1)
        row.edgeStripe:SetShown(on)
    end
    d = d or Look()
    local br, bg, bb, ba = ColorOf(d.rowBorderColor, 0, 0, 0, 1)
    if on then br, bg, bb, ba = 1, 1, 1, 0.8 end
    for i = 1, 4 do
        local e = row.borders[i]
        e:SetColorTexture(br, bg, bb, ba)
        e:SetShown(on or d.rowBorder ~= false)
    end
end

-- Everything a setting decides about a row, applied in place: the live
-- rows and the preview's rows both come through here.
function Meter.StyleRow(row)
    local d = Look()
    local h = d.rowHeight
    row:SetHeight(h)
    row.bg:SetTexture(Meter.TexPath(d.rowBgTexture, ROW_BG_TEX))
    if row.hot then
        row.bg:SetVertexColor(ColorOf(d.rowHoverColor, 0.588, 0.588, 0.588, 0.7))
    else
        row.bg:SetVertexColor(Meter.RowBgColor(d))
    end
    row.tex:SetTexture(Meter.BarPath())
    Gloss(row, d)
    row._edge = nil         -- (the border is coloured below; the edge comes back on the next fill)
    if row.edgeStripe then row.edgeStripe:Hide() end

    -- (the Classic look's bars are plain, as the stock meter's: no border)
    local on = d.rowBorder ~= false and not (Meter.IsClassicLook and Meter.IsClassicLook())
    local br, bg, bb, ba = ColorOf(d.rowBorderColor, 0, 0, 0, 1)
    for i = 1, 4 do
        local e = row.borders[i]
        e:SetColorTexture(br, bg, bb, ba)
        e:SetShown(on)
    end
    PlaceEdges(row.borders, row, Pixels(d.rowBorderSize), d.rowBorderSize)

    local showIcon = d.showIcons ~= false
    local iconSize = math.max(1, h + (d.iconSizeOffset or 0))
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetShown(showIcon)
    if not row.anchorTo then row.anchorTo = function(k) return RowTarget(row, k) end end
    local t = RowDef(row, "value")
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = "RIGHT", row.bar, "RIGHT", 0, 0, "RIGHT"
    ns.ApplyAnchor(row.rightText, AnchorOf(d, "value"), t, row.anchorTo)
    t = RowDef(row, "icon")
    t.point, t.to, t.relPoint, t.x, t.y = "LEFT", row, "LEFT", 0, 0
    ns.ApplyAnchor(row.icon, AnchorOf(d, "icon"), t, row.anchorTo)
    t = RowDef(row, "name")
    if showIcon then
        t.point, t.to, t.relPoint, t.x, t.y = "LEFT", row.icon, "RIGHT", 3, 0
    else
        t.point, t.to, t.relPoint, t.x, t.y = "LEFT", row, "LEFT", 3, 0
    end
    t.justify = "LEFT"
    t.point2, t.to2, t.relPoint2, t.x2, t.y2 = "RIGHT", row.rightText, "LEFT", -4, 0
    local _, two = ns.ApplyAnchor(row.leftText, AnchorOf(d, "name"), t, row.anchorTo)
    if not two then
        -- one point: room for a long name, cut off past it
        local rw = row:GetWidth() or 0
        row.leftText:SetWidth(rw > 40 and (rw * 0.65) or 120)
    end

    local dflt = Meter.NameFontDefaults(d)
    ns.ApplyFontSpec(row.leftText, d.nameFont, dflt)
    ns.ApplyFontSpec(row.rightText, d.numberFont, dflt)
    row.rightText:SetTextColor(ColorOf(d.numberColor, 1, 1, 1, 1))
    if d.nameColorMode ~= "class" then
        if d.nameColorMode == "custom" then
            row.leftText:SetTextColor(ColorOf(d.nameColor, 1, 1, 1, 1))
        else
            row.leftText:SetTextColor(1, 1, 1, 1)
        end
    elseif row.actor then
        local c = CLASS_COLORS[row.actor.class or ""] or CLASS_COLORS.UNKNOW
        row.leftText:SetTextColor(c[1], c[2], c[3], 1)
    end
end

local function CreateRow(win, index)
    local preview = win.preview
    local row = CreateFrame("Button", (not preview) and ("ZacUIMeterRow_" .. win.id .. "_" .. index) or nil,
        win.rowframe)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT")
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT")
    row.bar:SetMinMaxValues(0, 100)
    local tex = row.bar:CreateTexture(nil, "ARTWORK")
    row.bar:SetStatusBarTexture(tex)
    row.tex = tex

    -- the border as four quads, outside the row edges (a black hairline
    -- by default)
    row.borders = {}
    for i = 1, 4 do
        row.borders[i] = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    end

    -- icon frame floats over the bar's left end (start_after_icon=false)
    local iconFrame = CreateFrame("Frame", nil, row.bar)
    iconFrame:SetFrameLevel(row.bar:GetFrameLevel() + 2)
    row.icon = iconFrame:CreateTexture(nil, "OVERLAY", nil, 5)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    if ns.SharpenIcon then ns.SharpenIcon(row.icon) end

    row.leftText = iconFrame:CreateFontString(nil, "OVERLAY")
    row.leftText:SetJustifyH("LEFT")
    row.leftText:SetWordWrap(false)

    -- the Darkmoon Faire mark, just after the name (shown by FillRow)
    row.dmf = iconFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    ZacUI.Look.CropIcon(row.dmf)
    row.dmf:Hide()
    row.win = win

    row.rightText = iconFrame:CreateFontString(nil, "OVERLAY")
    row.rightText:SetPoint("RIGHT", row.bar, "RIGHT", 0, 0)
    row.rightText:SetJustifyH("RIGHT")
    if preview and ns.TagElement then
        -- the pick hook: a click on a sample's text opens its spot
        ns.TagElement(row.leftText, "meter.name") ns.TagElement(row.rightText, "meter.value")
        ns.TagElement(row.icon, "meter.icon")
        ns.TagElement(row.bar, "meter.bar")
    end

    -- a preview row is a picture: no tooltip, no breakdown, no drag
    if not preview then
        row:SetScript("OnEnter", function(self)
            win:ShowToolbar(true)
            if self.actor and Meter.RowTooltip then
                self.hot = true
                self.bg:SetVertexColor(ColorOf(Look().rowHoverColor, 0.588, 0.588, 0.588, 0.7))
                Meter.RowTooltip(self, win)
            end
        end)
        row:SetScript("OnLeave", function(self)
            win:ShowToolbar(false)
            self.hot = nil
            self.bg:SetVertexColor(Meter.RowBgColor(Look()))
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                win:OpenDisplayMenu()
            elseif self.actor and Meter.OpenBreakdown then
                Meter.OpenBreakdown(win, self.actor)
            end
        end)
        -- dragging the window from a row, like the original when unlocked
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function()
            if not win.settings.locked then win.frame:StartMoving() end
        end)
        row:SetScript("OnDragStop", function() win:StopDrag() end)
        WireWheel(row, win)
    end

    -- born hidden: a row only shows once it carries an actor. Rows left
    -- visible at creation are exactly the "white lines" an empty window
    -- would otherwise wear.
    row:Hide()

    win.rows[index] = row
    Meter.StyleRow(row)
    return row
end

-- The rows fill the BODY (win.rowframe: under the header when there is
-- one, the whole window otherwise), from the top, or from the bottom
-- up when the window grows up.
local function LayoutRows(win)
    local d = Look()
    local pitch = math.max(1, d.rowHeight + d.rowGap)
    local body = win.rowframe or win.frame
    local fit = floor((body:GetHeight() or 0) / pitch)
    win.rowsFit = fit
    local up = d.grow == "up"
    for i = 1, max(fit, #win.rows) do
        local row = win.rows[i] or (i <= fit and CreateRow(win, i)) or nil
        if row then
            Meter.SettleRow(row)
            row:ClearAllPoints()
            if up then
                row:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, (i - 1) * pitch)
            else
                row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -((i - 1) * pitch))
            end
            -- (the Classic look's rows sit inside its rim: win.bodyInset)
            row:SetWidth((win.frame:GetWidth() or 0) - 2 * (win.bodyInset or 0))
            row:SetHeight(d.rowHeight)
            if i > fit then row:Hide() end
        end
    end
end
Meter.LayoutRows = LayoutRows

-- ============================================================
-- REFRESH - the data pass. Sort a scratch list, feed the rows.
-- ============================================================
local scratch = {}

local function CombatForWindow(win)
    -- a preview window shows the made-up fight it was handed
    if win.fakeCombat then return win.fakeCombat end
    local seg = win.settings.segment or 0
    if seg == 0 then return Meter.current
    -- Overall INCLUDING the fight in progress. The closed overall alone
    -- stood still for the whole pull.
    elseif seg == -1 then return Meter.LiveOverall and Meter.LiveOverall() or Meter.overall
    else return Meter.segments[seg] end
end
Meter.CombatForWindow = CombatForWindow


-- The right-hand text. Counts (deaths, interrupts) are plain numbers
-- and single-figure displays one number; the rest follow the layout:
--   both  "{total}{sep}{per second}"  (his custom "{data1} I {data2}")
--   paren "{total} ({per second})"    total  "{total}"   ps  "{per second}"
--   pct   "{total} ({share}%)"        all  "{total}{sep}{per second} ({share}%)"
-- YOUR NUMBER FORMAT (look.formats.value, ZacUI's text format: a template
-- over [total] [ps] [pct], big numbers, decimals). Its defaults are the
-- layout and separator above; nothing saved = the code below, exactly.
local VAL_V, VAL_K = {}, { total = "number", ps = "number", pct = "percent" }
local VAL_TPL = { both = "[total]%s[ps]", paren = "[total] ([ps])", total = "[total]", ps = "[ps]",
    pct = "[total] ([pct]%%)", all = "[total]%s[ps] ([pct]%%)" }
local VAL_DEF = {}
function Meter.ValueDefaults(d)
    d = d or Look()
    local t = VAL_TPL[d.numberLayout or "both"] or VAL_TPL.both
    VAL_DEF.template = format(t, (d.numberSep or " I "):gsub("%%", "%%%%"))
    VAL_DEF.decimals = 1
    return VAL_DEF
end
-- the dimmer half of a row's texts (the rank, the per-second figure)
local DIM = "|cffbdbdbd"
Meter.DIM_CODE = DIM
local function RightText(disp, v, ps, share, ToK, d)
    if disp.count then return floor(v) end
    local spec = type(d.formats) == "table" and d.formats.value
    if spec and ns.FormatText then
        VAL_V.total, VAL_V.ps, VAL_V.pct = v, floor(ps), share
        local def = Meter.ValueDefaults(d)
        if disp.single and not spec.template then
            -- one figure: the total (and its share when the layout shows one)
            local layout = d.numberLayout or "both"
            return ns.FormatText(spec, (layout == "pct" or layout == "all") and { template = "[total] ([pct]%)", decimals = 1 }
                or { template = "[total]", decimals = 1 }, VAL_V, VAL_K)
        end
        return ns.FormatText(spec, def, VAL_V, VAL_K)
    end
    local layout = d.numberLayout or "both"
    local pct = (layout == "pct" or layout == "all") and format(" (%.1f%%)", share) or ""
    -- the second figure dimmer than the total (look.dimSecond)
    local dim, undim = "", ""
    if d.dimSecond ~= false then dim, undim = DIM, "|r" end
    if disp.single then return ToK(v) .. (pct ~= "" and (dim .. pct .. undim) or "") end
    local sep = d.numberSep or " I "
    local total, per = ToK(v), ToK(floor(ps))
    if layout == "paren" then return total .. dim .. " (" .. per .. ")" .. undim
    elseif layout == "total" then return total
    elseif layout == "ps" then return per
    elseif layout == "pct" then return total .. dim .. pct .. undim
    elseif layout == "all" then return total .. dim .. sep .. per .. pct .. undim end
    return total .. dim .. sep .. per .. undim
end
Meter.RightText = RightText

-- One row's picture of one actor: bar length and colour, icon, name
-- (with its place in the list when asked), name colour, the number.
-- PER-STATE LOOKS on the standard (look.states.<self|first>: bar colour,
-- name colour - Look tab): your own row and the leader's row, over their
-- usual colours (the defaults ARE those: your colour when "Colour my own
-- bar" is on). A name colour taken away goes back to the window's own.
Meter.STATE_LIST = { { id = "self", label = "Your row" }, { id = "first", label = "The leader (first row)" } }
function Meter.StateDefaults()
    local d = Meter.Look()
    local out = { self = {}, first = {} }
    if d.useSelfColor then out.self.color = d.selfColor end
    return out
end
local function NameColor(row, actor, d)
    if d.nameColorMode == "class" then
        local c = CLASS_COLORS[actor.class or ""] or CLASS_COLORS.UNKNOW
        row.leftText:SetTextColor(c[1], c[2], c[3], 1)
    elseif d.nameColorMode == "custom" then
        row.leftText:SetTextColor(ColorOf(d.nameColor, 1, 1, 1, 1))
    else
        row.leftText:SetTextColor(1, 1, 1, 1)
    end
end
local function RowState(row, actor, d, rank)
    local st = d.states
    if type(st) ~= "table" or next(st) == nil then st = nil end
    if not (st or row._mSt) then return end
    local s = st and ((actor.isSelf and st.self) or (rank == 1 and st.first)) or nil
    if type(s) ~= "table" then s = nil end
    row._mSt = s and true or nil
    if s and s.color then
        local r, g, b, a = ColorOf(s.color, 1, 1, 1, 1)
        row.tex:SetVertexColor(r, g, b, a * (tonumber(d.barAlpha) or 1))
    end
    if s and s.textColor then
        row.leftText:SetTextColor(ColorOf(s.textColor, 1, 1, 1, 1))
        row._mStT = true
    elseif row._mStT then
        row._mStT = nil
        NameColor(row, actor, d)
    end
end

local function FillRow(row, actor, v, top, right, d, rank)
    row.actor = actor
    local r, g, b, a = BarColor(actor, d)
    row.tex:SetVertexColor(r, g, b, a * (tonumber(d.barAlpha) or 1))
    row.bar:SetValue(floor(v / top * 100))
    if d.showIcons ~= false then SetRowIcon(row, actor, d) end
    local name = DisplayName(actor)
    -- the names' format (look.formats.name: longest, case, before / after)
    local nf = type(d.formats) == "table" and d.formats.name
    if nf and ns.FormatName then name = ns.FormatName(name, nf) end
    if d.showRank and rank then
        if d.dimRank ~= false then name = DIM .. rank .. ".|r " .. name
        else name = rank .. ". " .. name end
    end
    row.leftText:SetText(name)
    -- your own row marked by a light edge (look.selfStyle = "edge")
    Meter.SelfEdge(row, actor.isSelf and d.useSelfColor and d.selfStyle == "edge", d)
    if d.nameColorMode == "class" then
        local c = CLASS_COLORS[actor.class or ""] or CLASS_COLORS.UNKNOW
        row.leftText:SetTextColor(c[1], c[2], c[3], 1)
    end
    row.rightText:SetText(right)
    RowState(row, actor, d, rank)
    -- the Darkmoon Faire mark after the name (the sample's second row has it)
    local dmf
    if row.win and row.win.preview then
        dmf = d.dmfIcon ~= false and rank == 2
    else
        dmf = actor.serial and Meter.DMF[actor.serial] and Meter.DMFShowNow(d)
    end
    if dmf then
        local sz = math.max(8, (row:GetHeight() or 20) - 6)
        row.dmf:SetTexture(Meter.DMFTexture())
        row.dmf:SetSize(sz, sz)
        local w = row.leftText:GetStringWidth() or 0
        local room = row.leftText:GetWidth() or w
        if room > 0 and w > room - sz - 3 then w = room - sz - 3 end
        row.dmf:ClearAllPoints()
        row.dmf:SetPoint("LEFT", row.leftText, "LEFT", math.max(0, w) + 3, 0)
        row.dmf:Show()
    elseif row.dmf:IsShown() then
        row.dmf:Hide()
    end
end

-- THE LIST'S ORDER AND LENGTH on the standard's layout shape (look.layout:
-- sort value | name | class, reverse, max - Position tab). Nothing saved
-- = biggest first, everyone, exactly as before.
Meter.SORTS = { { value = "value", text = "Biggest first" }, { value = "name", text = "Name" },
    { value = "class", text = "Class, then biggest" } }
local function ByName(a, b) return DisplayName(a) < DisplayName(b) end
local function ByClass(a, b)
    local ca, cb = a.class or "", b.class or ""
    if ca ~= cb then return ca < cb end
    return a.sortValue > b.sortValue
end
local function ApplyListLayout(list, d)
    local l = d.layout
    if type(l) ~= "table" or next(l) == nil then return end
    if l.sort == "name" then tsort(list, ByName) elseif l.sort == "class" then tsort(list, ByClass) end
    if l.reverse then
        local n = #list
        for i = 1, math.floor(n / 2) do list[i], list[n + 1 - i] = list[n + 1 - i], list[i] end
    end
    local most = tonumber(l.max)
    if most and most >= 1 then for i = #list, most + 1, -1 do list[i] = nil end end
end

RefreshMeterWindow = function(win, force)
    local settings = win.settings
    local disp = DISPLAYS[settings.display]
    if not disp then return end
    -- Forever / Retail in a fight: the game's own meter paints the window
    -- (Meter_Win_Live), and says so for a mode it does not keep
    if Meter.Live and Meter.Live.Hook(win, force) then return end
    -- a breakdown open in the window (Meter_Win_Breakdown) takes the tick
    -- instead; the rows are hidden under it and catch up when it closes
    if win.bd and Meter.Breakdown then return Meter.Breakdown.Refresh(win) end
    win.segRev = Meter.segmentsRev or 0
    local combat = CombatForWindow(win)
    if not combat then
        for i = 1, #win.rows do
            Meter.HideRow(win.rows[i])
            win.rows[i].actor = nil
        end
        return
    end
    local container = combat[disp.container]
    local combatTime = combat:GetCombatTime()
    local d = Look()

    wipe(scratch)
    local valueOf = disp.value
    local sum = 0
    local enemies = disp.enemies
    for _, actor in ipairs(container.actors) do
        if disp.prepare then disp.prepare(actor, combat, combatTime) end
        local v = valueOf(actor, combat, combatTime)
        -- the group and its pets; the enemies for the one display that
        -- lists them
        local mine = actor.grupo or actor.ownerName
        if v and v >= 1 and ((not enemies and mine) or (enemies and actor.enemy and not mine)) then
            scratch[#scratch + 1] = actor
            actor.sortValue = v
            sum = sum + v
        end
    end
    tsort(scratch, function(a, b) return a.sortValue > b.sortValue end)
    if sum <= 0 then sum = 1 end
    -- the bar length stays relative to the biggest, whatever the order
    local top = scratch[1] and scratch[1].sortValue or 0.00000001
    ApplyListLayout(scratch, d)
    local shown = 0
    local ToK = Meter.ToKList[d.psAbbrev] or Meter.ToK
    local playerRowShown = false
    if win.title and win.title:IsShown() then Meter.UpdateTitle(win) end

    -- The wheel offset, clamped against THIS list. The bar length stays
    -- relative to the true #1 so scrolling down does not re-stretch the
    -- rows you can see.
    win.scrollMax = max(0, #scratch - win.rowsFit)
    local offset = win.scroll or 0
    if offset > win.scrollMax then offset = win.scrollMax; win.scroll = offset end

    -- MY OWN ROW (look.pinSelf): "follow" - when my bar is outside the
    -- visible slice it claims the last visible row, unless you have
    -- scrolled (you are looking for someone else then); "pin" - the same,
    -- scrolled or not, at the top edge when I am above the slice and at
    -- the bottom when below, with a line marking the pinned row; "off".
    local pin = d.pinSelf or "follow"
    local pinSlot, pinRank
    if pin ~= "off" and win.rowsFit > 0 then
        local first, last = offset + 1, offset + win.rowsFit
        for j = 1, #scratch do
            if scratch[j].isSelf then
                if j < first and pin == "pin" then pinSlot, pinRank = 1, j
                elseif j > last and (pin == "pin" or offset == 0) then pinSlot, pinRank = win.rowsFit, j end
                break
            end
        end
    end
    for i = 1, win.rowsFit do
        local row = win.rows[i]
        local rank = i + offset
        local actor = scratch[rank]
        local pinned = false
        if i == pinSlot and not playerRowShown then
            actor, rank, pinned = scratch[pinRank], pinRank, pin == "pin"
        end
        if pinned then
            -- the line between the pinned row and the list: under a row
            -- pinned at the top, over one pinned at the bottom (placed
            -- each time: the same row can be pinned at either edge)
            local line = row.pinLine
            if not line then
                line = row:CreateTexture(nil, "OVERLAY", nil, 7)
                row.pinLine = line
            end
            local hl = Hairline()
            line:SetHeight(hl)
            line:SetColorTexture(ColorOf(d.rowBorderColor, 0, 0, 0, 1))
            line:ClearAllPoints()
            if pinSlot == 1 then
                line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, -hl)
                line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -hl)
            else
                line:SetPoint("TOPLEFT", row, "TOPLEFT", 0, hl)
                line:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, hl)
            end
            line:Show()
        elseif row.pinLine then
            row.pinLine:Hide()
        end
        if actor then
            local v = actor.sortValue
            -- someone else in this slot than last time: the order moved
            local moved = row.actor ~= nil and row.actor ~= actor and row:IsShown() and not row._zLeaving
            row.combat = combat
            if actor.isSelf then playerRowShown = true end
            local ps = (not disp.count and not disp.single and disp.ps) and disp.ps(actor, combat, combatTime) or 0
            FillRow(row, actor, v, top, RightText(disp, v, ps, v / sum * 100, ToK, d), d, rank)
            if not row:IsShown() or row._zLeaving then
                Meter.ShowRow(row)
            elseif moved then
                PlayMove(row, d)
            end
            shown = i
        else
            Meter.HideRow(row)
            row.actor = nil
        end
    end
end

local function RefreshWindow(win, force)
    if not win.settings.open then return end
    if win.settings.display == "threat" then return end -- the threat file drives it
    RefreshMeterWindow(win, force)
end
Meter.RefreshWindow = RefreshWindow
Meter.RefreshMeterWindow = function(win, force) return RefreshMeterWindow(win, force) end

function Meter.DirtyAll()
    for _, win in ipairs(windows) do RefreshWindow(win, true) end
end
Meter.Windows = { DirtyAll = Meter.DirtyAll }
-- every open meter window, for code outside this file (ZacLayout)
function Meter.Windows.Each(fn)
    for _, win in ipairs(windows) do fn(win) end
end

-- transient center label for segment / display feedback, over the
-- window (or over its header when one is shown). It shows at once and
-- goes with the label animation - a 1.6s fade unless changed; "None"
-- turns the label off. Held in a frame so ns.Motion can animate it.
local function FlashLabel(win, text)
    local d = Look()
    if not win.flash then
        local h = CreateFrame("Frame", nil, win.frame)
        h:SetSize(1, 1)
        h:SetFrameLevel(win.frame:GetFrameLevel() + 12)
        h.text = h:CreateFontString(nil, "OVERLAY")
        h.text:SetPoint("BOTTOM", h, "BOTTOM", 0, 0)
        h:Hide()
        win.flash = h
    end
    local h = win.flash
    local Motion = ns.Motion
    if Motion then Motion.Stop(h) end
    ns.ApplyFontSpec(h.text, d.titleFont, Meter.TitleFontDefaults(d))
    local over = (win.title and win.title:IsShown()) and win.title or win.frame
    h:ClearAllPoints()
    h:SetPoint("BOTTOM", over, "TOP", 0, 4)
    h.text:SetText(text)
    h:SetAlpha(1)
    h:Show()
    if Motion then
        Motion.Hide(h, d.labelAnim)
    else
        h:Hide()
    end
end
Meter.FlashLabel = FlashLabel


if ns.OnSettingsChanged and ns.Coalesce then
    local soon = ns.Coalesce(function()
        if Meter.enabled then Meter.RestyleAll() end
    end)
    -- only changes made on the meter's own page (its preview is the one on
    -- show); the Fonts & Textures push calls RestyleMedia itself
    ns.OnSettingsChanged(function()
        local P = ns.ConfigPreview
        if P and P.Current and P.Current() == "meter.window" then soon() end
    end)
end

if ns.Media and ns.Media.RegisterTarget then
    ns.Media.RegisterTarget("meter", {
        label = "Meter",
        desc = "Row font and bar texture in the damage and threat windows.",
        order = 40,
        -- still on its shipped font
        untouched = function() local d = DB() return d.font == nil or d.font == "" end,
        apply = function(font, bar, cleared)
            local d = DB()
            if font then d.font = font
            elseif cleared then d.font = nil end
            if bar then d.bar = bar end
            Meter.RestyleMedia()
        end,
    })
end

function Meter.ResetData()
    wipe(Meter.segments)
    Meter.ResetOverall()     -- bumps segmentsRev for the parked windows
    if Meter.inCombat then
        -- restart the live segment in place
        local c = Meter.NewCombat()
        c.combatId = Meter.combatCounter
        Meter.current = c
        Meter.UpdateParserGears()
    else
        Meter.current = Meter.NewCombat()
        Meter.UpdateParserGears()
    end
    for _, win in ipairs(windows) do
        if (win.settings.segment or 0) > 0 then win.settings.segment = 0 end
        RefreshWindow(win, true)
    end
    Print("Meter data reset.")
end

-- ============================================================
-- REFRESH TICK - one ticker for every window, dirty-gated.
-- ============================================================
local refreshTicker
local function StartRefreshTicker()
    if refreshTicker then refreshTicker:Cancel() end
    refreshTicker = C_Timer.NewTicker(DB().updateSpeed, function()
        local dirty = Meter.current and Meter.current.needRefresh
        local segRev = Meter.segmentsRev or 0
        for _, win in ipairs(windows) do
            if win.settings.open and win.settings.display ~= "threat" then
                local seg = win.settings.segment or 0
                local disp = DISPLAYS[win.settings.display]
                -- A window parked on a past fight or the overall only
                -- changes while a fight is running (the live overall) or
                -- when the segment list itself changed under it; out of
                -- combat it is not re-sorted and re-texted every tick.
                local isDirty = (seg ~= 0 and win.segRev ~= segRev)
                    or (dirty and (dirty.all or (disp and dirty[disp.container])))
                if isDirty or Meter.inCombat then
                    RefreshMeterWindow(win)
                end
            end
        end
        if dirty then wipe(dirty) end
    end)
end
Meter.StartRefreshTicker = StartRefreshTicker

-- combat hooks for clickthrough (Meter_Win_Frame wraps these: the
-- fresh-segment snap of a window parked on a past fight, the clock)
function Meter.OnCombatStart()
    for _, win in ipairs(windows) do
        win:ApplyClickthrough()
    end
end

function Meter.OnCombatEnd()
    for _, win in ipairs(windows) do
        win:ApplyClickthrough()
        RefreshWindow(win, true)
    end
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.meter = function()
    local d = DB()
    if not d.enabled then return end
    if Meter.enabled then
        for _, win in ipairs(windows) do
            LayoutRows(win)
            RefreshWindow(win, true)
        end
        return
    end
    -- two damage meters double-parse every combat; if Details is still
    -- installed and enabled, stand down and say so.
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded("Details") then
        local line = ("meter: Details! is running, so ZacUI's meter is standing "
            .. "down. Disable or delete Details to switch over - your "
            .. "windows, skin and threat setup are already ported.")
        -- after the login popups (Core_Popups), not under them
        if ns.Popups then ns.Popups.Say(line) else Print(line) end
        return
    end
    Meter.enabled = true
    Meter.EnableParser()
    -- the windows themselves: Meter_Win_Frame (Meter v2)
    local Win = Meter.Win
    -- the game's own meter on or off for this look before any window is
    -- built, so it is settled even with every ZacUI window closed
    if Win and Win.SyncGameMeter and not Win.gmSynced then Win.gmSynced = true Win.SyncGameMeter() end
    if Win and Win.Create then
        for id = 1, #d.windows do
            if d.windows[id].open then Win.Create(id) end
        end
    end
    StartRefreshTicker()
end
