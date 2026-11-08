-- Meter_Threat - the threat display, ZacUI's native TinyThreat. Lives
-- inside a meter window (window 1 in the ported layout) and drives its
-- own rows on its own one-second timer.
-- Part of ZacUI; load order is set by the TOC.
--
-- FAITHFUL TO THE PLUGIN, including its quirks:
--   * Classic's UnitDetailedThreatSituation raw value is divided by 100
--   * relative mode (his config): bars sort and fill by threat %,
--     100% = you pull
--   * bar colors are the green->yellow->red gradient of your threat %;
--     the current tank's bar is colored from the highest NON-tank's
--     percent instead (green while the raid is safe, red as someone
--     closes on 100%)
--   * the "You pull at" bar shows how much raw threat you have left
--     before aggro, whenever you have threat and are not tanking
--   * a "Current Tank" bar is synthesized when nobody in your list is
--     tanking (the boss is on someone outside the group)
--   * rows inherit the meter's font, size and texture, but text is
--     OUTLINED here - TinyThreat reads the old textL_outline flag the
--     meter rows no longer honor, and his flag is true
--   * threat rows have no class icon: a 14px role icon instead, and no
--     row border - that is exactly how the plugin drew them
-- Update cost: one UnitDetailedThreatSituation per group member per
-- second, only while attached, in combat, with a valid enemy target.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Meter = ns.Meter
local Print = ns.Print

local floor, max, abs, format = math.floor, math.max, math.abs, string.format
local wipe, tsort = wipe, table.sort
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local UnitExists, UnitCanAttack, UnitName, UnitClass = UnitExists, UnitCanAttack, UnitName, UnitClass
local IsInRaid, IsInGroup, GetNumGroupMembers = IsInRaid, IsInGroup, GetNumGroupMembers

local ToK2 = Meter.ToK2
local PercentColor = Meter.PercentColor
local ROLE_TEX, ROLE_COORDS = Meter.ROLE_TEX, Meter.ROLE_COORDS

local Threat = {}
Meter.Threat = Threat

local attachedWin = nil
local ticker = nil
local list = {}          -- { name, relPct, isTanking, role, class, absThreat, absPct }
local listByName = {}

-- ============================================================
-- ROWS - a separate pool on the window; meter rows stay untouched.
-- ============================================================
-- Row show / hide through the meter's row animations (Meter_Windows);
-- plain Show / Hide when that file is not there.
local function ShowRow(row)
    if Meter.ShowRow then Meter.ShowRow(row, "threatShowAnim") elseif not row:IsShown() then row:Show() end
end
local function HideRow(row)
    if Meter.HideRow then Meter.HideRow(row, "threatHideAnim") elseif row:IsShown() then row:Hide() end
end

-- the threat text's font when the setting leaves a field out: the
-- meter's font at the row size, outlined, no shadow (as it always was)
local function FontDefaults(d)
    if Meter.ThreatFontDefaults then return Meter.ThreatFontDefaults(d) end
    return { face = Meter.FontPath(), size = d.fontSize or 13, outline = "outline", shadow = false }
end
local function SetFontSpec(fs, spec, dflt)
    if ns.ApplyFontSpec then
        ns.ApplyFontSpec(fs, spec, dflt)
    else
        fs:SetFont(dflt.face, dflt.size, "OUTLINE")
    end
end

-- Everything a setting decides about a threat row, in place.
function Threat.StyleRow(row)
    local d = Meter.DB()
    row:SetHeight(d.rowHeight)
    row.tex:SetTexture(Meter.BarPath())
    local show = d.threatIcons ~= false
    local size = tonumber(d.threatIconSize) or 14
    row.icon:SetSize(size, size)
    row.icon:SetShown(show)
    -- WHERE THE ROLE ICON, THE NAME AND THE THREAT SIT (look.anchors.
    -- <threatIcon|threatName|threatValue>, ZacUI's anchor shape): the
    -- SetPoints the rows always had are the defaults, the spot goes on top.
    local A = type(d.anchors) == "table" and d.anchors or nil
    if not rawget(row, "_zTo") then
        row._zTo = function(k)
            if k == "row" then return row elseif k == "threatIcon" then return row.icon
            elseif k == "threatName" then return row.leftText elseif k == "threatValue" then return row.rightText end
        end
        row._zAD = { icon = {}, name = {}, value = {} }
    end
    local D = row._zAD
    local t = D.icon
    t.point, t.to, t.relPoint, t.x, t.y = "LEFT", row, "LEFT", 1, 0
    ns.ApplyAnchor(row.icon, A and A.threatIcon, t, row._zTo)
    t = D.value
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = "RIGHT", row, "RIGHT", -3, 0, "RIGHT"
    ns.ApplyAnchor(row.rightText, A and A.threatValue, t, row._zTo)
    t = D.name
    if show then
        t.point, t.to, t.relPoint, t.x, t.y = "LEFT", row.icon, "RIGHT", 3, 0
    else
        t.point, t.to, t.relPoint, t.x, t.y = "LEFT", row, "LEFT", 3, 0
    end
    t.justify = "LEFT"
    t.point2, t.to2, t.relPoint2, t.x2, t.y2 = "RIGHT", row.rightText, "LEFT", -4, 0
    local _, two = ns.ApplyAnchor(row.leftText, A and A.threatName, t, row._zTo)
    if two == false then row.leftText:SetWidth(math.max(40, (row:GetWidth() or 160) - 70)) end
    if ns.TagElement then
        ns.TagElement(row.icon, "meter.threatIcon")
        ns.TagElement(row.leftText, "meter.threatName")
        ns.TagElement(row.rightText, "meter.threatValue")
    end
    local dflt = FontDefaults(d)
    SetFontSpec(row.leftText, d.threatFont, dflt)
    SetFontSpec(row.rightText, d.threatFont, dflt)
end

local function CreateThreatRow(win, index)
    local row = CreateFrame("StatusBar", nil, win.rowframe)
    row:SetMinMaxValues(0, 100)
    local tex = row:CreateTexture(nil, "ARTWORK")
    row:SetStatusBarTexture(tex)
    row.tex = tex

    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetPoint("LEFT", row, "LEFT", 1, 0)
    row.icon:SetTexture(ROLE_TEX)

    row.leftText = row:CreateFontString(nil, "OVERLAY")
    row.leftText:SetJustifyH("LEFT")
    row.leftText:SetWordWrap(false)

    row.rightText = row:CreateFontString(nil, "OVERLAY")
    row.rightText:SetPoint("RIGHT", row, "RIGHT", -3, 0)
    row.rightText:SetJustifyH("RIGHT")

    row:Hide()
    win.threatRows[index] = row
    Threat.StyleRow(row)
    return row
end

function Threat.SizeChanged(win)
    if not win.threatRows then return end
    local d = Meter.DB()
    local pitch = math.max(1, d.rowHeight + (d.rowGap or 1))
    -- the window's body (under the header since Meter v2; the whole
    -- window without one)
    local body = win.rowframe or win.frame
    win.threatFit = floor((body:GetHeight() or 0) / pitch)
    for i = 1, max(win.threatFit, #win.threatRows) do
        local row = win.threatRows[i] or (i <= win.threatFit and CreateThreatRow(win, i)) or nil
        if row then
            local y = -((i - 1) * pitch)
            if Meter.SettleRow then Meter.SettleRow(row) end
            row:ClearAllPoints()
            -- 1px inset each side, exactly the plugin's anchor math
            row:SetPoint("TOPLEFT", body, "TOPLEFT", 1, y)
            row:SetPoint("TOPRIGHT", body, "TOPRIGHT", -1, y)
            row:SetHeight(d.rowHeight)
            if i > win.threatFit then row:Hide() end
        end
    end
end

local function HideWinRows(win)
    if not (win and win.threatRows) then return end
    for _, row in ipairs(win.threatRows) do HideRow(row) end
end
local function HideRows() HideWinRows(attachedWin) end

-- ============================================================
-- ROSTER
-- ============================================================
-- Who is measured. The raid comes from ns.Roster; entries are pooled by
-- slot and refilled (built when the fight starts and when the group
-- changes, never on a target swap - who is in the group does not depend
-- on what you target).
local roster = {}        -- array of {unit, name, class, role}
local rosterPool = {}
local rosterN = 0

local function add(unit)
    if not UnitExists(unit) then return end
    rosterN = rosterN + 1
    local e = rosterPool[rosterN]
    if not e then e = {} rosterPool[rosterN] = e end
    e.unit = unit
    e.name = UnitName(unit)
    local _, class = UnitClass(unit)
    e.class = class
    e.role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
    roster[rosterN] = e
end

local function BuildRoster()
    rosterN = 0
    local d = Meter.DB().threat
    if IsInRaid() and not d.onlyMyGroup then
        local units = ns.Roster.Units()
        for i = 1, #units do add(units[i]) end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do add("party" .. i) end
        add("player")
        if d.showPartyPets then
            for i = 1, GetNumGroupMembers() - 1 do add("partypet" .. i) end
            add("pet")
        end
    else
        add("player")
        add("pet")
    end
    for i = #roster, rosterN + 1, -1 do roster[i] = nil end
end

-- ============================================================
-- THE SCAN
-- ============================================================
-- Which enemy are we measuring threat against? Not one token - a
-- CHAIN. The hard target leads; then the soft enemy target (the 1.15
-- action-targeting Readycheck drives, SoftTargetEnemy = 3 in his
-- config); then the soft enemy's NAMEPLATE token - the threat API on
-- some builds answers a nameplate unit when it stays silent for
-- "softenemy" itself, and the plate carries the same GUID; then an
-- attackable mouseover as the last resort. The scan walks the chain
-- until one of them actually returns threat data, so soft-target-only
-- play reads exactly like hard targeting.
local candidates = {}
local function AddCandidate(u)
    if UnitExists(u) and UnitCanAttack("player", u) then
        candidates[#candidates + 1] = u
    end
end
local function GatherCandidates()
    wipe(candidates)
    AddCandidate("target")
    AddCandidate("softenemy")
    if UnitExists("softenemy") and C_NamePlate and C_NamePlate.GetNamePlates then
        local guid = ns.SafeGUID("softenemy")   -- (nil while WoW Forever hides it)
        if guid then
            for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
                local u = plate.namePlateUnitToken
                    or (plate.UnitFrame and plate.UnitFrame.unit)
                if u and ns.SafeGUID(u) == guid then
                    AddCandidate(u)
                    break
                end
            end
        end
    end
    AddCandidate("mouseover")
    return #candidates
end

local function ReadThreat(unit, target)
    local isTanking, status, threatPct, rawPct, threatValue =
        UnitDetailedThreatSituation(unit, target)
    -- WoW Forever hides threat in a fight (secret values): no reading
    if ns.Hidden(isTanking, status, threatPct, rawPct, threatValue) then return nil end
    if threatValue then threatValue = floor(threatValue / 100) end
    return isTanking, status, threatPct, rawPct, threatValue
end

-- The scan runs every second in combat for up to 40 members, so the
-- per-member entries are pooled by slot and refilled instead of being
-- allocated each pass; list holds them in sorted order, pool keeps them.
local pool = {}
local function ScanAgainst(target)
    local n = 0
    for _, member in ipairs(roster) do
        local isTanking, status, threatPct, rawPct, threatValue =
            ReadThreat(member.unit, target)
        if status ~= nil or threatPct then
            n = n + 1
            local e = pool[n]
            if not e then e = {} pool[n] = e end
            e[1] = member.name
            e[2] = threatPct or 0
            e[3] = isTanking or false
            e[4] = member.role
            e[5] = member.class
            e[6] = threatValue or 0
            e[7] = isTanking and 100 or (rawPct or 0)
            list[n] = e
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    return n
end

local function ByAbsolute(a, b) return a[6] > b[6] end
local function ByRelative(a, b) return a[2] > b[2] end

-- row cursor for one Paint; file-level so NextRow is not rebuilt per pass
local tickRows, tickFit, tickRowIndex
local function NextRow()
    tickRowIndex = tickRowIndex + 1
    if tickRowIndex > tickFit then return nil end
    local row = tickRows[tickRowIndex]
    if row then ShowRow(row) end
    return row
end

-- The rows for one measured list - { name, relPct, isTanking, role,
-- class, absThreat, absPct } per member - sorted here by the mode.
-- The scan below hands it the live list; the settings preview a made-up
-- one, so both draw exactly the same way.
function Threat.Paint(win, lst, playerName)
    local d = Meter.DB().threat
    local useAbsolute = d.absoluteMode
    if useAbsolute then
        tsort(lst, ByAbsolute)
    else
        tsort(lst, ByRelative)
    end
    if not lst[1] or lst[1][7] < 1 then HideWinRows(win) return end

    -- who am I, is anyone tanking
    local me, anyTank
    for _, t in ipairs(lst) do
        if t[1] == playerName then me = t end
        if t[3] then anyTank = true end
    end
    local mainTankAbsolute = lst[1][6] / (max(lst[1][7], 1) / 100)

    local rows = win.threatRows
    tickRows, tickFit, tickRowIndex = rows, win.threatFit or 0, 0

    -- "You pull at": some threat, not tanking (relative mode)
    if not d.hidePullBar and not useAbsolute and me and me[2] > 0 and not me[3] then
        local row = NextRow()
        if row then
            row.icon:SetTexture("Interface\\PVPFrame\\Icon-Combat")
            row.icon:SetTexCoord(0, 1, 0, 1)
            row.leftText:SetText("You pull at")
            local headroom = me[6] * (100 / max(me[2], 0.001)) - me[6]
            row.rightText:SetText("+" .. ToK2(headroom)
                .. " (" .. format("%.1f", 100 - me[2]) .. "%)")
            row:SetValue(me[2])
            local r, g = PercentColor(me[2])
            row.tex:SetVertexColor(r, g, 0, 1)
        end
    end

    -- "Current Tank" dummy when nobody in the list has aggro
    if not anyTank then
        local row = NextRow()
        if row then
            row.icon:SetTexture(ROLE_TEX)
            local c = ROLE_COORDS.TANK
            row.icon:SetTexCoord(c[1], c[2], c[3], c[4])
            row.leftText:SetText("Current Tank")
            row.rightText:SetText(ToK2(mainTankAbsolute) .. " (100.0%)")
            row:SetValue(100)
            local topPct = lst[1][2]
            row.tex:SetVertexColor(topPct * 0.01, abs(topPct - 100) * 0.01, 0, 1)
        end
    end

    for _, t in ipairs(lst) do
        local row = NextRow()
        if not row then break end
        local pct = useAbsolute and t[7] or t[2]
        row.icon:SetTexture(ROLE_TEX)
        local c = ROLE_COORDS[t[4]] or ROLE_COORDS.NONE
        row.icon:SetTexCoord(c[1], c[2], c[3], c[4])
        local name = t[1]
        local cut = name:find("-", 1, true)
        if cut then name = name:sub(1, cut - 1) end
        row.leftText:SetText(name)
        row.rightText:SetText(ToK2(t[6]) .. " (" .. format("%.1f", pct) .. "%)")
        row:SetValue(pct)
        if t[3] then
            -- the tank: colored by how close the best non-tank is
            local otherPct = 0
            for _, o in ipairs(lst) do
                if not o[3] then otherPct = o[2] break end
            end
            row.tex:SetVertexColor(otherPct * 0.01, abs(otherPct - 100) * 0.01, 0, 1)
        else
            local r, g = PercentColor(pct)
            row.tex:SetVertexColor(r, g, 0, 1)
        end
    end
    for i = tickRowIndex + 1, #rows do HideRow(rows[i]) end
end

local function Tick()
    local win = attachedWin
    if not win then return end
    if GatherCandidates() == 0 then
        HideRows()
        return
    end
    local playerName = Meter.playerName or UnitName("player")
    local found = 0
    for _, unit in ipairs(candidates) do
        found = ScanAgainst(unit)
        if found > 0 then break end
    end
    if found == 0 then HideRows() return end
    Threat.Paint(win, list, playerName)
end

-- ============================================================
-- LIFECYCLE
-- ============================================================
local function Start()
    if ticker then return end
    BuildRoster()
    ticker = C_Timer.NewTicker(Meter.DB().threat.updateSpeed or 1, Tick)
    Tick()
end

local function Stop()
    if ticker then ticker:Cancel(); ticker = nil end
    HideRows()
end

-- Target swaps fire several times a second under tab-targeting, and
-- each one used to run the whole scan (one threat query per member,
-- a sort, every row's text) inline. Now a swap only arms one short
-- timer; the first swap in a burst schedules the rescan, the rest ride
-- along, and the scan itself hides the rows when no enemy is left.
local rescanPending = false
local function Rescan()
    rescanPending = false
    if not ticker or not attachedWin then return end
    Tick()
end
local function RequestRescan()
    if rescanPending then return end
    rescanPending = true
    C_Timer.After(0.2, Rescan)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
-- soft-target swaps get the same instant rescan a hard-target swap
-- gets; pcall'd because older builds don't know the event
pcall(events.RegisterEvent, events, "PLAYER_SOFT_ENEMY_CHANGED")
-- a pet summoned (or lost) mid-fight joins the list (ns.Roster's notice
-- covers people, not pets)
events:RegisterEvent("UNIT_PET")       -- rare; RegisterUnitEvent takes two units at most
events:SetScript("OnEvent", function(_, event)
    if not attachedWin then return end
    if event == "UNIT_PET" then
        if ticker then BuildRoster() end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        Start()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Stop()
    elseif event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_SOFT_ENEMY_CHANGED" then
        if ticker then RequestRescan() end
    end
end)
-- the group changed (ns.Roster, once per burst)
ns.Roster.On("Meter.threat", function()
    if ticker and attachedWin then BuildRoster() end
end)

-- ============================================================
-- DOCK UNDER THE TARGET FRAME (threat.dockUnderTarget, off by default)
-- The threat window sits right under ZacUI's target frame - or under
-- the target's castbar while one shows below it, so a cast never covers
-- the bars. Moves only when that castbar shows or hides (hooked, no
-- polling). The window's own saved spot is untouched: switching the
-- dock off puts it straight back there.
-- ============================================================
local DOCK_GAP = 2
local dockHooked = {}

local function DockOn()
    local t = Meter.DB().threat
    return t and t.dockUnderTarget and true or false
end

local function UFFrames()
    local fr = ns.frames
    return fr and fr.target, fr and fr.softtarget
end

-- the castbar to sit under: shown, and below its frame
local function CastbarBelow(uf)
    local cb = uf and uf.Castbar
    if not (cb and cb:IsVisible()) then return nil end
    local cbB, fB = cb:GetBottom(), uf:GetBottom()
    if cbB and fB and cbB < fB - 1 then return cb end
    return nil
end

function Threat.IsDocked(win)
    return win ~= nil and win == attachedWin and DockOn() and (UFFrames()) ~= nil
end

function Threat.ApplyDock()
    local win = attachedWin
    if not win then return end
    local f, s = win.frame, win.settings
    local tf, sf = UFFrames()
    f:ClearAllPoints()
    if DockOn() and tf then
        local under = CastbarBelow(tf) or CastbarBelow(sf) or tf
        f:SetPoint("TOP", under, "BOTTOM", 0, -DOCK_GAP)
    else
        f:SetPoint(s.point, UIParent, s.point, s.x, s.y)
    end
end

local function HookDock()
    local tf, sf = UFFrames()
    for _, uf in ipairs({ tf or false, sf or false }) do
        local cb = uf and uf.Castbar
        if cb and not dockHooked[cb] then
            dockHooked[cb] = true
            cb:HookScript("OnShow", function() if DockOn() then Threat.ApplyDock() end end)
            cb:HookScript("OnHide", function() if DockOn() then Threat.ApplyDock() end end)
        end
    end
end

-- ============================================================
-- ONE THREAT READER (ns.Threat), 2026-11-03
-- Zac: "i want something other than tts its not helpful or its too late
-- to matter". The voice below and Meter_ThreatGlow (the screen-edge
-- glow, the weak tank opener, the pull warning) all read YOUR threat on
-- the mob you are fighting from here, and the tank's: a pass runs the moment the game hands over new threat for that mob (its
-- threat events, at most ten passes a second) and every 0.5 s when none
-- come, in combat only, and only while one of them is switched on. Out of
-- combat nothing runs at all. A pass asks at most two threat queries (you
-- and the cached tank). There is no second scan anywhere.
--
--   ns.Threat.Now() -> the last reading (one shared table, refilled on
--   every pass: read it, never keep it):
--     active     a mob has you on its threat list (the chain above:
--                target, soft target, its plate, mouseover)
--     pct        your threat on it, scaled: 100 = you pull it
--     raw        the raw % (runs to 110 / 130 before a pull)
--     tanking    you have it (you are its target)
--     tankForm   you are in a tanking form: Defensive Stance, bear form,
--                Righteous Fury
--     onPurpose  tanking it in that form
--     pulled     you have it and NOT on purpose
--     name, class (its classification), guid, unit, isTarget (it is your
--     target), worth (an elite or a boss, and you are in a group), stance
--     (a warrior's stance)
--     settled    past the quiet start: 4 s from the pull, or from when
--                this mob first showed up (the % is all over the place
--                while the tank opens)
--     since      seconds since the pull, or since this mob joined
--     pullIn     seconds until you pull at the rates you and the tank are
--                going (nil = never), headroom, myRate, tankRate, factor,
--                myValue, tankValue, tankUnit, tankName: THE TANK below
--   ns.Threat.Refresh()   an option changed: start or stop as needed
--
-- A reader of it is { wants = fn() -> on, update = fn(reading, now,
-- stopped) } in ns.ThreatConsumers[name]. That table is made by whichever
-- part loads first (the HUD part loads before the meter). update runs
-- after every pass while wants() says yes, and once with stopped = true
-- (reading.active false) when combat ends or that reader is switched off.
-- ============================================================
local THREAT_EVERY, THREAT_GRACE, EVAL_GAP = 0.5, 4, 0.1
local RIGHTEOUS_FURY = 25780
local _, myClass = UnitClass("player")
local isWarrior = myClass == "WARRIOR"
ns.ThreatConsumers = ns.ThreatConsumers or {}
local consumers = ns.ThreatConsumers
local reading = { active = false }
local OFF = { active = false }
local readTicker, combatAt = nil, 0
local seenAt = {}

local Reader = ns.Threat or {}
ns.Threat = Reader
Reader.EVERY, Reader.GRACE, Reader.GAP = THREAT_EVERY, THREAT_GRACE, EVAL_GAP

-- in the form you tank in (a warrior's Defensive Stance, a druid's bear
-- form, a paladin's Righteous Fury)
local function TankForm()
    if myClass == "WARRIOR" then return GetShapeshiftForm and GetShapeshiftForm() == 2 or false end
    if myClass == "DRUID" then return GetShapeshiftForm and GetShapeshiftForm() == 1 or false end
    if myClass == "PALADIN" then
        local A = ns.PlayerAuras
        return (A and A.Buff and A.Buff(RIGHTEOUS_FURY)) and true or false
    end
    return false
end

-- WHICH MOB, CHEAPLY. The same chain as the window's scan (target, soft
-- target, its plate, mouseover), but walked lazily: the next link is
-- only asked when the one before said nothing, so with a target there is
-- exactly ONE threat query for you, and the plate list (a new table from
-- the client every call) is only read when the soft target itself is
-- silent.
local function TryMob(u)
    if not (UnitExists(u) and UnitCanAttack("player", u)) then return nil end
    local isTanking, status, pct, raw, value = UnitDetailedThreatSituation("player", u)
    if ns.Hidden(isTanking, status, pct, raw, value) then return nil end   -- (WoW Forever)
    if pct then return u, isTanking, status, pct, raw, value end
    return nil
end

local function SoftPlate()
    if not (UnitExists("softenemy") and C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    local guid = ns.SafeGUID("softenemy")
    if not guid then return nil end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if u and ns.SafeGUID(u) == guid then return u end
    end
    return nil
end

local function FindMob()
    local u, a, b, c, d, e = TryMob("target")
    if u then return u, a, b, c, d, e end
    u, a, b, c, d, e = TryMob("softenemy")
    if u then return u, a, b, c, d, e end
    local plate = SoftPlate()
    if plate then
        u, a, b, c, d, e = TryMob(plate)
        if u then return u, a, b, c, d, e end
    end
    return TryMob("mouseover")
end

-- ============================================================
-- THE TANK AND THE PULL PREDICTION (2026-11-03)
-- Zac: "can we somehow detect the tanks horrible opener ... and somehow
-- alert me if the opener is horrible?" Your % only says where you are;
-- what kills you is how fast you are catching the tank. So the reader
-- also follows the TANK's threat on the same mob, keeps both over the
-- last ~3 s, and works out when you would pull at the rates you are both
-- going:
--   pull point = the tank's threat x 1.1 in melee, x 1.3 at range (read
--                off the game's own two percentages: raw / scaled)
--   headroom   = pull point - your threat
--   pullIn     = headroom / (your rate - the tank's rate), in seconds;
--                nil (never) while the tank gains as fast as you or faster
-- Published on the reading: myValue, tankValue, myRate, tankRate (threat
-- a second), factor (1.1 / 1.3), headroom, pullIn, tankUnit, tankName,
-- since (seconds since the pull or since this mob joined).
-- THE TANK is the unit whose isTanking is true on that mob. It is cached
-- per mob and asked once a tick (your query + the tank's = at most two
-- threat queries a tick). The group is searched again only when that
-- unit stops tanking or the mob changes, at most once a second, only
-- people in combat, stopping at the first one tanking. Not found (the
-- mob is on someone outside the group): the tank's threat is worked out
-- from your raw % instead (raw = yours / the tank's), no query at all.
-- No table is made per tick: the rate windows are fixed ring buffers.
-- ============================================================
local SCAN_EVERY, MISS_EVERY, WINDOW, MIN_SPAN, RING = 1, 3, 3, 0.5, 32
local tankOf = {}            -- mob guid -> unit token of its tank (this fight)
local lastScan = -10
local partyUnits = { "party1", "party2", "party3", "party4", "pet",
    "partypet1", "partypet2", "partypet3", "partypet4" }
local ringT, ringMe, ringTank = {}, {}, {}
for i = 1, RING do ringT[i], ringMe[i], ringTank[i] = 0, 0, 0 end
local ringN, ringHead, ringGuid, ringTankUnit = 0, 0, nil, nil
local stat = { scans = 0, scanQueries = 0, evals = 0 }   -- for the tests: passes, and what the tank search asked
Reader.stat = stat

local function ScanOne(u, mob)
    if not UnitExists(u) or UnitIsUnit(u, "player") then return false end
    if not UnitAffectingCombat(u) then return false end
    stat.scanQueries = stat.scanQueries + 1
    local isTanking, _, _, _, value = UnitDetailedThreatSituation(u, mob)
    if ns.Hidden(isTanking, value) then return false end   -- (WoW Forever)
    if isTanking then return true, value end
    return false
end

-- the group, searched for whoever has the mob (stops at the first)
local function ScanForTank(mob, now)
    lastScan = now
    stat.scans = stat.scans + 1
    if IsInRaid() then
        local units = ns.Roster and ns.Roster.Units and ns.Roster.Units() or {}
        for i = 1, #units do
            local hit, value = ScanOne(units[i], mob)
            if hit then return units[i], value end
        end
        local hit, value = ScanOne("pet", mob)
        if hit then return "pet", value end
    elseif IsInGroup() then
        for i = 1, #partyUnits do
            local hit, value = ScanOne(partyUnits[i], mob)
            if hit then return partyUnits[i], value end
        end
    else
        local hit, value = ScanOne("pet", mob)
        if hit then return "pet", value end
    end
    return nil
end

-- the tank's threat on the mob: its unit (cached) and its threat value
local LOST = 0                           -- tankOf: its tank lost it, search at the next chance
local function TankOf(mob, guid, now)
    local u = tankOf[guid]
    if type(u) == "string" then
        local isTanking, _, _, _, value = UnitDetailedThreatSituation(u, mob)
        if not ns.Hidden(isTanking, value) and isTanking and value then return u, value end
        tankOf[guid] = LOST              -- it lost the mob: search again
        u = LOST
    end
    -- at most once a second; a mob whose tank is not in the group (nobody
    -- found last time) is only looked at again every few seconds
    local wait = (u == false) and MISS_EVERY or SCAN_EVERY
    if now - lastScan < wait then return nil end
    local value
    u, value = ScanForTank(mob, now)
    tankOf[guid] = u or false
    return u, value                      -- (the search's own answer: no extra query)
end
Reader.TankOf = function(guid) return tankOf[guid] end

local function RingReset(guid, tankUnit)
    ringN, ringHead, ringGuid, ringTankUnit = 0, 0, guid, tankUnit
end

-- seconds until you pull, your headroom: the maths on its own (tests)
function Reader.Predict(me, tank, myRate, tankRate, factor)
    factor = factor or 1.1
    if not (me and tank and tank > 0) then return nil, nil end
    local headroom = tank * factor - me
    if headroom <= 0 then return 0, headroom end
    if not (myRate and tankRate) then return nil, headroom end
    local closing = myRate - tankRate
    if closing <= 0 then return nil, headroom end
    return headroom / closing, headroom
end

local function Predict(r, mob, now, value)
    r.pullIn, r.headroom, r.myRate, r.tankRate = nil, nil, nil, nil
    r.myValue, r.tankValue, r.tankUnit, r.tankName = value, nil, nil, nil
    if r.tanking or not value then
        RingReset(nil, nil)
        return
    end
    -- melee 110% / range 130%: the game's own raw over scaled
    local factor = 1.1
    if r.pct and r.pct > 0 and r.raw and r.raw > 0 then
        factor = (r.raw / r.pct >= 1.2) and 1.3 or 1.1
    end
    r.factor = factor
    local tu, tv = TankOf(mob, r.guid, now)
    if not tv and r.raw and r.raw > 0 then tv = value * 100 / r.raw end
    if not tv or tv <= 0 then return end
    r.tankUnit, r.tankValue = tu, tv
    if tu then r.tankName = UnitName(tu) end
    -- the window: a new mob or a new tank starts it over, and so does a
    -- threat drop (a fade, a taunt) - a rate across one means nothing
    if ringGuid ~= r.guid or ringTankUnit ~= tu then RingReset(r.guid, tu) end
    if ringN > 0 and (value < ringMe[ringHead] or tv < ringTank[ringHead]) then RingReset(r.guid, tu) end
    ringHead = ringHead % RING + 1
    ringT[ringHead], ringMe[ringHead], ringTank[ringHead] = now, value, tv
    if ringN < RING then ringN = ringN + 1 end
    -- the oldest sample still inside the window
    local oldest
    for k = ringN - 1, 1, -1 do
        local i = (ringHead - k - 1) % RING + 1
        if now - ringT[i] <= WINDOW then oldest = i break end
    end
    local headroom = tv * factor - value
    r.headroom = headroom
    if not oldest then return end
    local dt = now - ringT[oldest]
    if dt < MIN_SPAN then return end
    r.myRate = (value - ringMe[oldest]) / dt
    r.tankRate = (tv - ringTank[oldest]) / dt
    r.pullIn = Reader.Predict(value, tv, r.myRate, r.tankRate, factor)
end

local function Read(now)
    local r = reading
    r.active = false
    r.pullIn, r.headroom = nil, nil
    local unit, isTanking, status, pct, raw, value = FindMob()
    if not unit then return r end
    local guid = ns.SafeGUID(unit)
    if not guid then return r end
    -- the quiet start runs from the pull, or from when this mob joined
    if not seenAt[guid] then seenAt[guid] = now end
    r.active = true
    r.unit, r.guid, r.status = unit, guid, status
    r.pct, r.raw = pct, raw or pct
    r.tanking = isTanking and true or false
    r.tankForm = TankForm()
    r.onPurpose = r.tanking and r.tankForm
    r.pulled = r.tanking and not r.tankForm
    r.name = UnitName(unit)
    r.class = UnitClassification and UnitClassification(unit) or nil
    r.worth = (r.class == "worldboss" or r.class == "elite" or r.class == "rareelite")
        and (IsInGroup() or IsInRaid()) and true or false
    r.isTarget = (UnitIsUnit and UnitIsUnit(unit, "target")) and true or false
    r.stance = isWarrior and GetShapeshiftForm and GetShapeshiftForm() or nil
    r.since = now - max(combatAt, seenAt[guid])
    r.settled = r.since >= THREAT_GRACE
    Predict(r, unit, now, value)
    return r
end

local function Wants(c)
    local ok, on = pcall(c.wants)
    return ok and on and true or false
end

local function AnyWants()
    for _, c in pairs(consumers) do
        if Wants(c) then return true end
    end
    return false
end

-- a reader switched off (or the fight over): told once, so it can clear
local function TellOff(c, now)
    if c._zOn then
        c._zOn = nil
        c.update(OFF, now, true)
    end
end

-- ONE PASS: your query (+ the cached tank's), the rates, and every
-- reader's decision (the voice, the glow, the opener and pull alerts), all
-- in this one call.
local lastEval, evalPending = -10, false
local function ReadTick()
    local now = GetTime()
    lastEval = now
    stat.evals = stat.evals + 1
    local r = Read(now)
    for _, c in pairs(consumers) do
        if Wants(c) then
            c._zOn = true
            c.update(r, now, false)
        else
            TellOff(c, now)
        end
    end
end

-- THE SAME FRAME THE GAME HANDS OVER NEW THREAT (Zac: "a bad tank opener
-- can be life or death in the matter of a split second"). A threat event
-- for the mob you are fighting (or for you) runs the pass right there, at
-- most ten times a second: one that lands inside the 0.1 s after a pass
-- sets a flag and one C_Timer.After for the rest of it, so the latest
-- numbers are never dropped and never read twice. Any other unit's event
-- (forty raiders' threat situations, every mob in the pull) returns at
-- once on a string compare, with no API call. The 0.5 s ticker is only
-- the fallback for a stretch with no events; both live in combat only.
local function Deferred()
    evalPending = false
    if readTicker then ReadTick() end
end
local function Evaluate()
    local now = GetTime()
    local wait = EVAL_GAP - (now - lastEval)
    if wait <= 0 then
        ReadTick()
    elseif not evalPending then
        evalPending = true
        C_Timer.After(wait, Deferred)
    end
end
Reader.Evaluate = Evaluate

local threatEvents = CreateFrame("Frame")
threatEvents:SetScript("OnEvent", function(_, _, unit)
    if unit ~= "player" and unit ~= "target" and unit ~= reading.unit then return end
    Evaluate()
end)

local function ReaderStart()
    if readTicker or not AnyWants() then return end
    readTicker = C_Timer.NewTicker(THREAT_EVERY, Evaluate)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(readTicker, "meter.threatReader") end
    threatEvents:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    threatEvents:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    Evaluate()
end

-- keepSeen: an option stopped it mid-fight (a reader switched back on
-- does not get a second quiet start)
local function ReaderStop(keepSeen)
    if readTicker then readTicker:Cancel(); readTicker = nil end
    threatEvents:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
    threatEvents:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    if not keepSeen then
        wipe(seenAt)
        wipe(tankOf)
        lastScan = -10
        RingReset(nil, nil)
    end
    reading.active = false
    reading.unit = nil
    local now = GetTime()
    for _, c in pairs(consumers) do TellOff(c, now) end
end

function Reader.Now() return reading end
function Reader.Running() return readTicker ~= nil end
function Reader.LastEval() return lastEval end
function Reader.CombatStart() return combatAt end

-- an option changed (settings page, ZacLayout): start, stop, or tell a
-- reader that was just switched off
function Reader.Refresh()
    if UnitAffectingCombat("player") then
        if AnyWants() then
            ReaderStart()
        else
            ReaderStop(true)
        end
    end
    local now = GetTime()
    for _, c in pairs(consumers) do
        if not Wants(c) then TellOff(c, now) end
    end
end

-- ============================================================
-- THREAT VOICE (threat.voiceWarn, off by default)
-- 2026-11-03, Zac: "the threat tts is kinda useless i need something more
-- helpful i just died to threat that i just ignored". Three steps now,
-- on the mob you are fighting, never while you are the one tanking it on
-- purpose, never in the first few seconds of the fight or of that mob:
--   * getting close (threat.voiceAt - 10, 85%): "Threat" once;
--   * about to pull (threat.voiceAt, 95%): "Stop", and a red
--     warning in the middle of the screen with the raid-warning sound,
--     said again every 3 s for as long as you stay up there
--     (threat.voiceRepeat, on) - a warning that only comes once is easy
--     to talk over;
--   * pulled it (you are now its target, an elite or boss, in a group,
--     not in your tanking form): "Aggro" and the screen warning,
--     once per time you pull it (threat.aggroAlert, on).
-- The screen warning is threat.screenAlert (on). A warrior hears the
-- first two only in Berserker Stance (as before); the third in any stance
-- but Defensive. It reads the shared reader above (in combat only).
-- ============================================================
local VOICE_REARM, VOICE_SPACING = 10, 4
local DANGER_REPEAT, EARLY_BELOW = 3, 10
local warned, early, aggro = {}, {}, {}
local lastVoice, lastDanger = 0, 0

-- WORDS, NOT SENTENCES (Zac 2026-11-05: "the threat tts stuff is too
-- long and it can get to the point of not being helpful"): one word each -
-- "Threat" (getting close), "Stop" (about to pull, again every 3 s),
-- "Aggro" (pulled it). The number is on the screen line, not in the voice.
-- "Stop" and "Aggro" go out at once (urgent) instead of waiting behind
-- another voice line for its 2 s.
local function Say(text, urgent)
    if ns.Speak then ns.Speak(text, urgent) return end
    local RC = _G.Readycheck
    if RC and RC.SpeakTTS then RC:SpeakTTS(text, true) return end
    if C_VoiceChat and C_VoiceChat.SpeakText then
        pcall(C_VoiceChat.SpeakText, (ns.VoiceId and ns.VoiceId()) or 0, text, 0, 100, 1)
    end
end
Threat.Say = Say

-- the big red line in the middle of the screen (the game's raid-warning
-- frame, its sound). Center always shows (the glow file's opener and
-- pull warnings); Screen is the voice's, behind threat.screenAlert.
local CENTER_COLOR = { r = 1, g = 0.15, b = 0.1 }
local function Center(text)
    if ns.ThreatScreen then ns.ThreatScreen(text) return end
    if RaidNotice_AddMessage and RaidWarningFrame then
        pcall(RaidNotice_AddMessage, RaidWarningFrame, text, CENTER_COLOR)
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master") end
end
Threat.Center = Center
Threat.CENTER_COLOR = CENTER_COLOR
-- the voice's two screen lines (the settings preview draws them too)
function Threat.StopText(p) return "THREAT " .. p .. "% - STOP" end
function Threat.AggroText(name) return "AGGRO - YOU PULLED " .. (name or "IT"):upper() end
local StopText, AggroText = Threat.StopText, Threat.AggroText
-- WHERE THE WARNINGS RUN (Zac 2026-11-04: "the threat stuff runs in
-- dungions and stuff where im killing mobs purposly in zerker stance").
-- In a raid; in a party or a dungeon only with threat.inDungeons ticked
-- (off). Solo never. The voice, the glow, the opener and the pull
-- warnings all ask this.
-- And on bosses only (Zac 2026-11-04: "the threat stuff on trash is just
-- super annoying can we keep it to bosses only"), unless threat.onTrash is
-- ticked. r = the reading (its class is the mob's classification).
function Threat.WarnHere(r)
    local t = Meter.DB and Meter.DB().threat
    if r and r.class ~= "worldboss" and not (t and t.onTrash == true) then return false end
    if IsInRaid() then return true end
    return (t and t.inDungeons == true and IsInGroup()) and true or false
end
local function Screen(text)
    local t = Meter.DB().threat
    if t and t.screenAlert == false then return end
    Center(text)
end

local function VoiceUpdate(r, now, stopped)
    if stopped then wipe(warned); wipe(early); wipe(aggro) return end
    if not (r.active and r.settled) then return end
    if not Threat.WarnHere(r) then return end
    local t = Meter.DB().threat
    local guid, pct = r.guid, r.pct
    if r.tanking then
        -- pulled it (not a tank in its tanking form holding it)
        if t.aggroAlert ~= false and not r.onPurpose and not aggro[guid] and r.worth then
            aggro[guid], lastVoice = true, now
            Say("Aggro", true)
            Screen(AggroText(r.name))
        end
        return
    end
    aggro[guid] = nil
    local at = tonumber(t.voiceAt) or 95
    local quiet = isWarrior and r.stance ~= 3      -- Berserker Stance only
    local p = floor(pct)
    if pct >= at then
        if not quiet then
            if not warned[guid] then
                if now - lastVoice >= VOICE_SPACING then
                    warned[guid], lastVoice, lastDanger = true, now, now
                    early[guid] = true
                    Say("Stop", true)
                    Screen(StopText(p))
                end
            elseif t.voiceRepeat ~= false and now - lastDanger >= DANGER_REPEAT then
                lastDanger, lastVoice = now, now
                Say("Stop", true)
                Screen(StopText(p))
            end
        end
    elseif pct >= at - EARLY_BELOW then
        if not quiet and not early[guid] and now - lastVoice >= VOICE_SPACING then
            early[guid], lastVoice = true, now
            Say("Threat")
        end
        if pct < at - VOICE_REARM then warned[guid] = nil end
    else
        if pct < at - VOICE_REARM then warned[guid] = nil end
        if pct < at - EARLY_BELOW - VOICE_REARM then early[guid] = nil end
    end
end

consumers.voice = {
    wants = function()
        local t = Meter.DB().threat
        return (t and t.voiceWarn) and true or false
    end,
    update = VoiceUpdate,
}

-- settings page / ZacLayout: re-read the options now
function Threat.ApplyOptions()
    HookDock()
    Threat.ApplyDock()
    if UnitAffectingCombat("player") then
        -- the voice starts over (as it always did on an option change)
        wipe(warned); wipe(early); wipe(aggro)
    end
    Reader.Refresh()
end

local extra = CreateFrame("Frame")
extra:RegisterEvent("PLAYER_REGEN_DISABLED")
extra:RegisterEvent("PLAYER_REGEN_ENABLED")
extra:RegisterEvent("PLAYER_ENTERING_WORLD")
extra:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        combatAt = GetTime()
        ReaderStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ReaderStop()
    else
        -- the unit frames exist by now
        HookDock()
        if DockOn() then Threat.ApplyDock() end
    end
end)

function Threat.Attach(win)
    attachedWin = win
    win.threatRows = win.threatRows or {}
    Threat.SizeChanged(win)
    -- meter rows step aside while the threat display owns the window
    for _, row in ipairs(win.rows) do row:Hide(); row.actor = nil end
    if UnitAffectingCombat("player") then Start() end
    if DockOn() then HookDock(); Threat.ApplyDock() end
end

function Threat.Detach(win)
    if attachedWin == win then
        Stop()
        if DockOn() then
            local s = win.settings
            win.frame:ClearAllPoints()
            win.frame:SetPoint(s.point, UIParent, s.point, s.x, s.y)
        end
        attachedWin = nil
    end
end
