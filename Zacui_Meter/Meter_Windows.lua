-- Meter_Windows - the meter windows: rows, sorting, displays, the hover
-- toolbar, drag/resize and the refresh tick. The module entry point
-- (Modules.meter) lives at the bottom of this file.
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
--     (auto_hide_menu), overlapping by 3px, close button hidden
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
    if not d._rev or d._rev < 1 then
        wipe(d)
        d._rev = 1
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
            { open = true, display = "threat",
              point = "BOTTOM", x = 215.3836669921875, y = 98.97835540771484,
              w = 159.4192199707031, h = 133.9609222412109,
              locked = true, clickthrough = true, segment = 0,
              lastMeterDisplay = "damage_done" },
            -- window 2: Damage Done, locked, bottom-right.
            { open = true, display = "damage_done",
              point = "BOTTOMRIGHT", x = 0, y = 0,
              w = 225.6758728027344, h = 199.8019866943359,
              locked = true, clickthrough = false, segment = 0,
              lastMeterDisplay = "damage_done" },
        }
        d.threat = {
            updateSpeed = 1, absoluteMode = false, hidePullBar = false,
            onlyMyGroup = false, showPartyPets = false,
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
            open = true, display = "damage_done",
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
    titleHeight = 18,
    titleColor = { r = 0, g = 0, b = 0, a = 0.6 },
    titleSegment = true,
    toolbarMode = "hover",                  -- "hover" | "always"
    nameColorMode = "white",                -- "white" | "class" | "custom"
    nameColor = { r = 1, g = 1, b = 1, a = 1 },
    numberColor = { r = 1, g = 1, b = 1, a = 1 },
    numberLayout = "both",                  -- see RightText
    numberSep = " I ",
    showRank = false,
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
        if next(Meter.DMF) or Meter.meBuffed then
            wipe(Meter.DMF)
            Meter.meBuffed = false
            if Meter.DirtyAll then Meter.DirtyAll() end
        end
        return
    end
    local changed = false
    local _, world = HasDMF("player", true)
    if world ~= Meter.meBuffed then Meter.meBuffed = world changed = true end
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
Meter.RowBgColor = function(d) return ColorOf(d.rowBgColor, 0, 0, 0, d.rowBgAlpha or 0.69) end
Meter.WinBgColor = function(d) return ColorOf(d.bgColor, 0, 0, 0, d.bgAlpha or 0.4) end

-- What a nil font field means for each text the meter draws: the
-- meter's own font (the Fonts & Textures push, else the profile's),
-- at the row font size, exactly as the text was set before.
function Meter.NameFontDefaults(d)
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
    "damage_done", "dps", "damage_taken", "friendly_fire",
    "heal_done", "hps", "overheal", "absorbs", "heal_taken",
    "deaths", "interrupts", "dispels", "cc_breaks", "ress",
    "threat",
}
Meter.DISPLAYS = DISPLAYS
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
    if actor.isSelf and d.useSelfColor then
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
    if not tex then tex, l, r, t, b = Meter.ClassIcon(actor.class) end
    row.icon:SetTexture(tex)
    row.icon:SetTexCoord(l, r, t, b)
end

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

-- four edge textures just outside `owner`, `size` thick
local function PlaceEdges(edges, owner, size)
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

    local on = d.rowBorder ~= false
    local br, bg, bb, ba = ColorOf(d.rowBorderColor, 0, 0, 0, 1)
    for i = 1, 4 do
        local e = row.borders[i]
        e:SetColorTexture(br, bg, bb, ba)
        e:SetShown(on)
    end
    PlaceEdges(row.borders, row, Pixels(d.rowBorderSize))

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
    row.dmf:SetTexCoord(0.07, 0.93, 0.07, 0.93)
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

local function LayoutRows(win)
    local d = Look()
    local pitch = math.max(1, d.rowHeight + d.rowGap)
    local fit = floor(win.frame:GetHeight() / pitch)
    win.rowsFit = fit
    for i = 1, max(fit, #win.rows) do
        local row = win.rows[i] or (i <= fit and CreateRow(win, i)) or nil
        if row then
            Meter.SettleRow(row)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", win.frame, "TOPLEFT", 0, -((i - 1) * pitch))
            row:SetWidth(win.frame:GetWidth())
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
    if disp.single then return ToK(v) .. pct end
    local sep = d.numberSep or " I "
    local total, per = ToK(v), ToK(floor(ps))
    if layout == "paren" then return total .. " (" .. per .. ")"
    elseif layout == "total" then return total
    elseif layout == "ps" then return per
    elseif layout == "pct" then return total .. pct
    elseif layout == "all" then return total .. sep .. per .. pct end
    return total .. sep .. per
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
    if d.showRank and rank then name = rank .. ". " .. name end
    row.leftText:SetText(name)
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
    for _, actor in ipairs(container.actors) do
        if disp.prepare then disp.prepare(actor, combat, combatTime) end
        local v = valueOf(actor, combat, combatTime)
        if v and v >= 1 and (actor.grupo or actor.ownerName) then
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

    for i = 1, win.rowsFit do
        local row = win.rows[i]
        local rank = i + offset
        local actor = scratch[rank]
        -- "following": if my own bar is outside the visible slice, it
        -- claims the last visible row so I always see myself - unless
        -- you have scrolled, in which case you are looking for someone
        -- else and the row belongs to them.
        if i == win.rowsFit and not playerRowShown and offset == 0 then
            for j = win.rowsFit + 1, #scratch do
                if scratch[j].isSelf then actor = scratch[j] rank = j break end
            end
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

function Meter.DirtyAll()
    for _, win in ipairs(windows) do RefreshWindow(win, true) end
end
Meter.Windows = { DirtyAll = Meter.DirtyAll }
-- every open meter window, for code outside this file (ZacLayout)
function Meter.Windows.Each(fn)
    for _, win in ipairs(windows) do fn(win) end
end

-- ============================================================
-- TOOLBAR - five 16x16 icons on the toolbar strip, revealed on hover,
-- overlapped by 3px, anchored above the window's top-right.
-- ============================================================
local TOOLBAR_COORDS = {         -- ZacUI's toolbar sheet: five 32 px icons in a row
    mode      = { 0 / 256, 32 / 256, 0, 1 },
    segment   = { 32 / 256, 64 / 256, 0, 1 },
    attribute = { 64 / 256, 96 / 256, 0, 1 },
    report    = { 96 / 256, 128 / 256, 0, 1 },
    reset     = { 128 / 256, 160 / 256, 0, 1 },
}
local TOOLBAR_ORDER = { "mode", "segment", "attribute", "report", "reset" }

local function CreateToolbar(win)
    local holder = CreateFrame("Frame", nil, win.frame)
    holder:SetSize(80, 16)
    holder:SetPoint("BOTTOMRIGHT", win.frame, "TOPRIGHT", 0, 2)
    holder:SetAlpha(0)
    win.toolbar = holder
    win.toolbarButtons = {}
    local last
    for i = #TOOLBAR_ORDER, 1, -1 do
        local key = TOOLBAR_ORDER[i]
        local b = CreateFrame("Button", nil, holder)
        b:SetSize(16, 16)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture(Meter.TEX_TOOLBAR)
        local c = TOOLBAR_COORDS[key]
        t:SetTexCoord(c[1], c[2], c[3], c[4])
        if not last then
            b:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
        else
            b:SetPoint("RIGHT", last, "LEFT", 3, 0)   -- space = -3: overlap
        end
        last = b
        b:SetScript("OnEnter", function() win:ShowToolbar(true) end)
        b:SetScript("OnLeave", function() win:ShowToolbar(false) end)
        b:SetScript("OnClick", function(_, button) win:ToolbarClick(key, button) end)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        win.toolbarButtons[key] = b
    end
end

-- ============================================================
-- POPUP MENU - a tiny house-style list; no Blizzard dropdown taint.
-- ============================================================
local menu
local function GetMenu()
    if menu then return menu end
    menu = CreateFrame("Frame", "ZacUIMeterMenu", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    local bg = menu:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.97)
    if ns.AddPixelBorder then ns.AddPixelBorder(menu) end
    menu.buttons = {}
    menu:Hide()
    menu:SetScript("OnLeave", function()
        C_Timer.After(0.35, function()
            if menu:IsShown() and not menu:IsMouseOver() then menu:Hide() end
        end)
    end)
    return menu
end

local function ShowMenu(anchor, items)
    local m = GetMenu()
    local width = 150
    for i, item in ipairs(items) do
        local b = m.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, m)
            b:SetHeight(18)
            b:SetPoint("TOPLEFT", m, "TOPLEFT", 4, -((i - 1) * 18) - 4)
            b:SetPoint("RIGHT", m, "RIGHT", -4, 0)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            b.text = b:CreateFontString(nil, "OVERLAY")
            b.text:SetFont(Meter.FontPath(), 11)
            -- (the meter's font, kept up when it changes)
            if ns.TrackHouseFont then
                ns.TrackHouseFont(b.text, function(s) pcall(s.SetFont, s, Meter.FontPath(), 11) end)
            end
            b.text:SetPoint("LEFT", 4, 0)
            b.text:SetShadowColor(0, 0, 0, 1)
            b.text:SetShadowOffset(1, -1)
            m.buttons[i] = b
        end
        b.text:SetText(item.text)
        b:SetScript("OnClick", function()
            m:Hide()
            GameTooltip:Hide()
            item.func()
        end)
        -- what the entry means, while the mouse is on it
        b:SetScript("OnEnter", item.tip and function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            local t, c = ns.GetColor("tooltip", "title"), ns.GetColor("tooltip", "body")
            GameTooltip:AddLine(item.text, t.r, t.g, t.b)
            GameTooltip:AddLine(item.tip, c.r, c.g, c.b, true)
            GameTooltip:Show()
        end or nil)
        b:SetScript("OnLeave", item.tip and function() GameTooltip:Hide() end or nil)
        b:Show()
    end
    for i = #items + 1, #m.buttons do m.buttons[i]:Hide() end
    m:SetSize(width, #items * 18 + 8)
    m:ClearAllPoints()
    m:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    m:Show()
end

-- transient center label for segment / display feedback, over the
-- window (or over its title bar when one is shown). It shows at once and
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

-- ============================================================
-- WINDOW OBJECT
-- ============================================================
function winMeta:ShowToolbar(entering)
    self.hoverCount = (self.hoverCount or 0) + (entering and 1 or -1)
    if Look().toolbarMode == "always" then
        self.toolbar:SetAlpha(0.92)
        return
    end
    if entering then
        self.toolbar:SetAlpha(0.92)
    else
        C_Timer.After(0.6, function()
            if not self.frame:IsMouseOver() and not self.toolbar:IsMouseOver() then
                self.toolbar:SetAlpha(0)
            end
        end)
    end
end

-- ============================================================
-- THE LOCK GUARDS THE GEOMETRY. THE DISPLAY IS FREE.
-- ============================================================
-- Lock used to veto display changes too, and both windows ship locked, so
-- every pick in the attribute menu bounced off a window that stayed on
-- damage forever. The guard was aimed at one real hazard - a threat
-- window quietly turning into a damage meter mid-pull - and it paid for
-- that by breaking the menu you actually use.
--
-- Split the two concerns instead. Lock means "I am done ARRANGING this":
-- it stops drag and resize, nothing else. The threat hazard is handled
-- where it belongs, by keeping threat out of the fifteen-entry attribute
-- menu entirely - it is a two-entry choice in the mode menu, which is a
-- place you have to mean to go. Picking a statistic is now one click, and
-- picking threat is still deliberate.
function winMeta:SetDisplay(key)
    self.scroll = 0
    local settings = self.settings
    if settings.display == key then return end
    if settings.display ~= "threat" and DISPLAYS[settings.display] then
        settings.lastMeterDisplay = settings.display
    end
    settings.display = key
    if key == "threat" then
        if Meter.Threat then Meter.Threat.Attach(self) end
    else
        if Meter.Threat then Meter.Threat.Detach(self) end
        RefreshWindow(self, true)
    end
    Meter.UpdateTitle(self)
    FlashLabel(self, key == "threat" and "Threat" or DISPLAYS[key].label)
end

function winMeta:SegmentLabel()
    local seg = self.settings.segment or 0
    if seg == 0 then return "Current fight" end
    if seg == -1 then return Meter.inCombat and "Overall (live)" or "Overall" end
    local combat = Meter.segments[seg]
    return "#" .. seg .. (combat and (" " .. combat:Name()) or "")
end

function winMeta:SetSegment(seg)
    self.settings.segment = seg
    self.scroll = 0
    RefreshWindow(self, true)
    Meter.UpdateTitle(self)
    FlashLabel(self, self:SegmentLabel())
end

function winMeta:ToolbarClick(key, button)
    if self.preview then return end
    if key == "mode" then
        local items = {}
        items[1] = { text = "Group meter", tip = "Damage, healing, deaths and the rest; pick which from the display menu.",
            func = function()
            self:SetDisplay(self.settings.lastMeterDisplay or "damage_done")
        end }
        items[2] = { text = "Threat (TinyThreat)", tip = Meter.THREAT_DESC, func = function()
            self:SetDisplay("threat")
        end }
        -- Position lock only. It has nothing to say about which statistic
        -- the window shows - that is the attribute menu, always live.
        items[3] = { text = self.settings.locked and "Unlock position" or "Lock position",
            func = function()
                self.settings.locked = not self.settings.locked
                Print("Meter window " .. self.id .. (self.settings.locked
                    and " position locked - the display menu still works."
                    or " unlocked - drag rows to move, corner to resize."))
            end }
        ShowMenu(self.toolbar, items)
    elseif key == "segment" then
        local used = #Meter.segments
        local seg = self.settings.segment or 0
        if button == "MiddleButton" then
            self:SetSegment(0)
        elseif button == "RightButton" then
            seg = seg - 1
            if seg < -1 then seg = used end
            self:SetSegment(seg)
        else
            seg = seg + 1
            if seg > used then seg = -1 end
            self:SetSegment(seg)
        end
    elseif key == "attribute" then
        self:OpenDisplayMenu()
    elseif key == "report" then
        if Meter.OpenReport then Meter.OpenReport(self) end
    elseif key == "reset" then
        Meter.ResetData()
    end
end

function winMeta:OpenDisplayMenu()
    local items = {}
    for _, key in ipairs(DISPLAY_ORDER) do
        -- Threat is deliberately NOT in this list. This is the "which
        -- statistic" menu - fifteen damage and healing breakdowns - and
        -- threat sitting at the bottom of it made the one switch you can
        -- least afford the easiest one to hit by accident. It lives in
        -- the mode menu, which is the two-entry choice it actually is.
        if key ~= "threat" then
            items[#items + 1] = { text = DISPLAYS[key].label, tip = DISPLAYS[key].desc,
                func = function() self:SetDisplay(key) end }
        end
    end
    ShowMenu(self.toolbar, items)
end

function winMeta:StopDrag()
    local f = self.frame
    f:StopMovingOrSizing()
    local s = self.settings
    local T = Meter.Threat
    if T and T.IsDocked and T.IsDocked(self) then
        -- docked under the target frame: a resize keeps its size, and
        -- the window goes back under the frame (its own spot is kept)
        T.ApplyDock()
    else
        local point, _, _, x, y = f:GetPoint(1)
        s.point, s.x, s.y = point, x, y
    end
    s.w, s.h = f:GetWidth(), f:GetHeight()
    LayoutRows(self)
    if s.display == "threat" and Meter.Threat then Meter.Threat.SizeChanged(self) end
    RefreshWindow(self, true)
end

function winMeta:ApplyClickthrough()
    local through = self.settings.clickthrough and Meter.inCombat
    self.frame:EnableMouse(not through)
    for _, row in ipairs(self.rows) do
        row:EnableMouse(not through)
    end
end

-- ============================================================
-- WINDOW CREATION
-- ============================================================
-- The title bar (off by default: his profile had none). It sits on top
-- of the window, outside it, so turning it on never changes how many
-- rows fit; the toolbar moves into it.
local function EnsureTitle(win)
    if win.title then return win.title end
    local t = CreateFrame("Frame", nil, win.frame)
    t:SetPoint("BOTTOMLEFT", win.frame, "TOPLEFT", 0, 0)
    t:SetPoint("BOTTOMRIGHT", win.frame, "TOPRIGHT", 0, 0)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.text = t:CreateFontString(nil, "OVERLAY")
    t.text:SetPoint("LEFT", t, "LEFT", 4, 0)
    t.text:SetPoint("RIGHT", t, "RIGHT", -4, 0)
    t.text:SetJustifyH("LEFT")
    t.text:SetWordWrap(false)
    t:Hide()
    win.title = t
    return t
end

function Meter.UpdateTitle(win)
    local t = win.title
    if not (t and t:IsShown()) then return end
    local s = win.settings
    if s.display == "threat" then t.text:SetText("Threat") return end
    local disp = DISPLAYS[s.display]
    local text = disp and disp.label or ""
    if Look().titleSegment then text = text .. "  -  " .. win:SegmentLabel() end
    t.text:SetText(text)
end

-- Background, border, title bar and toolbar from the settings, applied
-- in place (live windows and the preview's alike).
function Meter.StyleWindow(win)
    local d = Look()
    if d.bgShown then
        win.bg:SetColorTexture(Meter.WinBgColor(d))
    else
        win.bg:SetColorTexture(0, 0, 0, 0)
    end
    local on = d.winBorder and true or false
    local r, g, b, a = ColorOf(d.winBorderColor, 0, 0, 0, 1)
    for i = 1, 4 do
        win.edges[i]:SetColorTexture(r, g, b, a)
        win.edges[i]:SetShown(on)
    end
    PlaceEdges(win.edges, win.frame, Pixels(d.winBorderSize))

    local t = EnsureTitle(win)
    local titleOn = d.titleBar and true or false
    if titleOn then
        t:SetHeight(math.max(8, tonumber(d.titleHeight) or 18))
        t.bg:SetTexture(Meter.TexPath(d.titleTexture, FLAT_TEX))
        t.bg:SetVertexColor(ColorOf(d.titleColor, 0, 0, 0, 0.6))
        ns.ApplyFontSpec(t.text, d.titleFont, Meter.TitleFontDefaults(d))
        -- its spot: the bar's left edge to its right edge, or the saved one
        local td = t.anchorDef or {}
        t.anchorDef = td
        td.point, td.to, td.relPoint, td.x, td.y, td.justify = "LEFT", t, "LEFT", 4, 0, "LEFT"
        td.point2, td.relPoint2, td.x2, td.y2 = "RIGHT", "RIGHT", -4, 0
        if not t.anchorTo then
            t.anchorTo = function(k) if k == "titlebar" then return t end end
        end
        local _, two = ns.ApplyAnchor(t.text, AnchorOf(d, "title"), td, t.anchorTo)
        if not two then t.text:SetWidth(math.max(40, (win.frame:GetWidth() or 200) - 8)) end
        t:Show()
        Meter.UpdateTitle(win)
    else
        t:Hide()
    end

    local tb = win.toolbar
    tb:ClearAllPoints()
    if titleOn then
        tb:SetPoint("RIGHT", t, "RIGHT", -2, 0)
    else
        tb:SetPoint("BOTTOMRIGHT", win.frame, "TOPRIGHT", 0, 2)
    end
    if d.toolbarMode == "always" then
        tb:SetAlpha(0.92)
    elseif not (win.frame:IsMouseOver() or tb:IsMouseOver()) then
        tb:SetAlpha(0)
    end
    if win.flash then ns.ApplyFontSpec(win.flash.text, d.titleFont, Meter.TitleFontDefaults(d)) end
end

-- the parts every window has, live or preview
local function BuildWindowFrame(win, parent, name)
    local settings = win.settings
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(settings.w, settings.h)
    win.frame = f

    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    win.bg = bg
    win.edges = {}
    for i = 1, 4 do
        local e = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        e:Hide()
        win.edges[i] = e
    end

    win.rowframe = CreateFrame("Frame", nil, f)
    win.rowframe:SetAllPoints()
    return f
end

local function CreateWindow(id)
    local d = Look()
    local settings = d.windows[id]
    local win = setmetatable({ id = id, settings = settings, rows = {} }, winMeta)

    local f = BuildWindowFrame(win, UIParent, "ZacUIMeterWindow" .. id)
    f:SetFrameStrata("LOW")
    f:SetPoint(settings.point, UIParent, settings.point, settings.x, settings.y)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(100, 50)
    elseif f.SetMinResize then f:SetMinResize(100, 50) end
    f:SetClampedToScreen(true)

    -- window-level mouse: hover reveals the toolbar, drag moves when
    -- unlocked (the gaps between rows and the empty bottom are the frame)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        -- a window docked under the target frame is placed by the dock
        local T = Meter.Threat
        if not settings.locked and not (T and T.IsDocked and T.IsDocked(win)) then f:StartMoving() end
    end)
    f:SetScript("OnDragStop", function() win:StopDrag() end)
    f:SetScript("OnEnter", function() win:ShowToolbar(true) end)
    f:SetScript("OnLeave", function() win:ShowToolbar(false) end)
    WireWheel(f, win)

    -- resize grip, bottom-right, only bites when unlocked
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT")
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip:SetScript("OnMouseDown", function()
        if not settings.locked then f:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function() win:StopDrag() end)

    CreateToolbar(win)
    Meter.StyleWindow(win)
    LayoutRows(win)
    -- when the windows show (look.visibility, ZacUI's visibility shape:
    -- in combat, in a group, opacity, mouseover...). Alpha only; nothing
    -- saved = the window is never touched, as before.
    if ns.Visibility and ns.Visibility.Register then
        ns.Visibility.Register(f, function() return Look().visibility end, { control = "alpha" })
    end

    if settings.display == "threat" and Meter.Threat then
        Meter.Threat.Attach(win)
    end

    -- dense append: ipairs walks this everywhere, and a closed window 1
    -- must never hide window 2 behind a nil hole (the ipairs lesson)
    windows[#windows + 1] = win
    return win
end

-- ============================================================
-- PREVIEW WINDOW - a window for the settings page's preview: the same
-- frame, rows, toolbar and styling as a live one, parented to the
-- preview canvas, never in the window list (no refresh tick, no combat
-- hooks, no movers), with no tooltips, menus or dragging, fed a made-up
-- fight instead of a segment.
-- ============================================================
function Meter.NewPreviewWindow(parent, w, h)
    local settings = { display = "damage_done", segment = 0, locked = true, w = w or 226, h = h or 200 }
    local win = setmetatable({ id = 0, settings = settings, rows = {}, preview = true }, winMeta)
    BuildWindowFrame(win, parent, nil)
    CreateToolbar(win)
    win.frame:SetScript("OnEnter", function() win:ShowToolbar(true) end)
    win.frame:SetScript("OnLeave", function() win:ShowToolbar(false) end)
    Meter.StyleWindow(win)
    LayoutRows(win)
    return win
end

-- restyle a preview window and refill it from `combat` showing `display`
function Meter.FillPreviewWindow(win, combat, display)
    win.fakeCombat = combat
    win.settings.display = display
    Meter.StyleWindow(win)
    for _, row in ipairs(win.rows) do Meter.StyleRow(row) end
    LayoutRows(win)
    RefreshMeterWindow(win, true)
    Meter.UpdateTitle(win)
end

-- ============================================================
-- RESTYLE
-- ============================================================
-- Size and place a window from its settings (the Position tab), unless
-- the threat dock places it.
local function ApplyGeometry(win)
    local f, s = win.frame, win.settings
    if s.w and s.h then f:SetSize(s.w, s.h) end
    local T = Meter.Threat
    if T and T.IsDocked and T.IsDocked(win) then
        T.ApplyDock()
    elseif s.point then
        f:ClearAllPoints()
        f:SetPoint(s.point, UIParent, s.point, s.x or 0, s.y or 0)
    end
end

-- Every setting onto what is already on screen: the settings page (each
-- change, coalesced to once a frame) and the Fonts & Textures push.
-- Rows made later read the same functions.
function Meter.RestyleAll()
    for _, win in ipairs(windows) do
        ApplyGeometry(win)
        Meter.StyleWindow(win)
        for _, row in ipairs(win.rows) do Meter.StyleRow(row) end
        LayoutRows(win)
        local T = Meter.Threat
        if win.threatRows and T then
            for _, row in ipairs(win.threatRows) do T.StyleRow(row) end
            T.SizeChanged(win)
        end
        RefreshWindow(win, true)
        if ns.Visibility and ns.Visibility.Refresh then ns.Visibility.Refresh(win.frame) end
    end
end
Meter.RestyleMedia = Meter.RestyleAll

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

-- combat hooks for clickthrough + fresh-segment window snap
function Meter.OnCombatStart()
    for _, win in ipairs(windows) do
        win:ApplyClickthrough()
        if (win.settings.segment or 0) > 0 then win.settings.segment = 0 end
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
        Print("meter: Details! is running, so ZacUI's meter is standing "
            .. "down. Disable or delete Details to switch over - your "
            .. "windows, skin and threat setup are already ported.")
        return
    end
    Meter.enabled = true
    Meter.EnableParser()
    for id = 1, #d.windows do
        if d.windows[id].open then CreateWindow(id) end
    end
    StartRefreshTicker()
end
