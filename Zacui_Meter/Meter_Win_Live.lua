-- Meter_Win_Live - the meter windows DURING a fight on a game that gives
-- addons no combat log (WoW Forever, Retail, or the game-version
-- override's): the rows are painted straight from the game's own meter
-- (C_DamageMeter) once a second while a window is on screen, where before
-- a window stayed empty until the fight ended.
-- Part of ZacUI; load order is set by the TOC (after Meter_Win_Breakdown).
--
-- METER V2, phase 4 (2026-11-07). In a fight the game's numbers are
-- secret values: an addon may show them but never add, compare, sort or
-- join them. So this view:
--   * reads GetCombatSessionFromType(Current or Overall, the mode's type)
--     once per visible window per second, in a pcall, and nothing else
--     (your own breakdown reads your source when it is open);
--   * paints the rows the game's way round: its order (the sources come
--     sorted), the class icon from classFilename (never hidden), the name
--     and the numbers handed to the widgets whole (SetText, SetFormattedText
--     with the game's own abbreviation, StatusBar min/max and value), your
--     row by isLocalPlayer (never hidden);
--   * does the plain maths (the share, the realm cut, the meter's number
--     format) only when ns.Hidden says the values are plain;
--   * writes NOTHING into the meter's segments: the fight is still filled
--     from the game's meter when it closes (Meter_GameMeter), the one
--     writer, so the overall, the raid summary and reports keep plain
--     numbers.
-- Modes the game does not keep for addons (friendly fire, overheal,
-- shields, healing taken, CC breaks, battle res - and enemies or deaths
-- where the client has no such type) show a line saying so instead of an
-- empty window. Era and TBC never load this file.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local Meter = ns.Meter
if not (Meter and Meter.GameMeter and Meter.winMeta and Meter.Win) then return end
if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return end

local floor, max, min, format = math.floor, math.max, math.min, string.format
local type, pcall, ipairs = type, pcall, ipairs

local Live = {}
Meter.Live = Live
local Look = Meter.Look
local windows = Meter.windowFrames

local TICK = 1.0

-- ============================================================
-- THE GAME'S METER
-- ============================================================
local function Types()
    local E = Enum and Enum.DamageMeterType
    local t = Meter.GameMeter.Types and Meter.GameMeter.Types() or {}
    t.damage = t.damage or (E and E.DamageDone) or 0
    t.heal = t.heal or (E and E.HealingDone) or 2
    t.interrupt = t.interrupt or (E and E.Interrupts) or 5
    t.dispel = t.dispel or (E and E.Dispels) or 6
    t.taken = t.taken or (E and E.DamageTaken) or 7
    t.enemyTaken = E and E.EnemyDamageTaken or nil
    t.deaths = t.deaths or (E and E.Deaths) or nil
    return t
end
Live.Types = Types

local function SessionType(seg)
    local E = Enum and Enum.DamageMeterSessionType
    if seg == -1 then return E and E.Overall or 0 end
    return E and E.Current or 1
end

-- the meter's mode -> the game's type, and how its value reads
local MODE = { damage_done = "damage", dps = "damage", heal_done = "heal", hps = "heal",
    damage_taken = "taken", enemy_taken = "enemyTaken", interrupts = "interrupt", dispels = "dispel",
    deaths = "deaths" }
local PER_SECOND = { dps = true, hps = true }
Live.MODE = MODE

-- the game's session for a window: its fight (Current / Overall) and mode
local reads = 0
function Live.Reads() return reads end
local function Read(seg, kind)
    reads = reads + 1
    local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, SessionType(seg), kind)
    if not ok or type(s) ~= "table" or type(s.combatSources) ~= "table" then return nil end
    return s
end

local function Hidden(...) return ns.Hidden and ns.Hidden(...) or false end

-- ============================================================
-- WHICH WINDOWS
-- ============================================================
local function GameKind(display)
    local k = MODE[display]
    if not k then return nil end
    return Types()[k]
end

-- this window is painted from the game's meter right now
function Live.Owns(win)
    if win.liveSample then return true end
    if win.preview or not Meter.inCombat then return false end
    local s = win.settings
    if s.display == "threat" or not Meter.DISPLAYS[s.display] then return false end
    local seg = s.segment or 0
    return seg == 0 or seg == -1
end

-- the modes the game never gives addons on this client (out of combat
-- too: the fill at the end of a fight has none of them either)
local NEVER = { friendly_fire = true, overheal = true, absorbs = true, heal_taken = true,
    cc_breaks = true, ress = true }
local function NotKept(display, live)
    if NEVER[display] then return true end
    if display == "enemy_taken" then return not (live and Types().enemyTaken ~= nil) end
    if display == "deaths" and live then return Types().deaths == nil end
    return false
end
Live.NotKept = NotKept

local function VersionName()
    local fl = ns.Flavor and ns.Flavor() or ""
    if fl == "retail" then return "Retail" end
    return "Forever"
end

local function Note(win, text)
    local n = win.liveNote
    if not n then
        if not text then return end
        n = win.rowframe:CreateFontString(nil, "OVERLAY")
        n:SetPoint("TOPLEFT", win.rowframe, "TOPLEFT", 6, -6)
        n:SetPoint("TOPRIGHT", win.rowframe, "TOPRIGHT", -6, -6)
        n:SetJustifyH("LEFT")
        n:SetWordWrap(true)
        win.liveNote = n
    end
    if text then
        local d = Look()
        ns.ApplyFontSpec(n, d.nameFont, Meter.NameFontDefaults(d))
        local c = ns.GetColor("text", "gray")
        n:SetTextColor(c.r, c.g, c.b, 1)
        n:SetText(text)
        n:Show()
    else
        n:Hide()
    end
end
Live.Note = Note

-- ============================================================
-- PAINTING A ROW FROM A SOURCE
-- ============================================================
local function Esc(sep) return (tostring(sep or " I "):gsub("%%", "%%%%")) end

-- the right-hand text while the numbers are hidden: the meter's layout,
-- each figure the game's own abbreviation, no share (that is maths)
local function HiddenRight(row, disp, v, ps, d)
    local ToK = Meter.ToKList[d.psAbbrev] or Meter.ToK
    if disp.count then return ns.ShowText(row.rightText, "%s", v) end
    if disp.single then return ns.ShowText(row.rightText, "%s", ToK(v)) end
    local layout = d.numberLayout or "both"
    if layout == "total" or layout == "pct" then return ns.ShowText(row.rightText, "%s", ToK(v)) end
    if layout == "ps" then return ns.ShowText(row.rightText, "%s", ToK(ps)) end
    local dim, undim = "", ""
    if d.dimSecond ~= false and Meter.DIM_CODE then dim, undim = Meter.DIM_CODE, "|r" end
    if layout == "paren" then return ns.ShowText(row.rightText, "%s" .. dim .. " (%s)" .. undim, ToK(v), ToK(ps)) end
    return ns.ShowText(row.rightText, "%s" .. dim .. Esc(d.numberSep) .. "%s" .. undim, ToK(v), ToK(ps))
end

local function PaintRow(row, src, rank, top, disp, display, d, sum)
    local a = row.liveActor or {}
    row.liveActor = a
    a.live, a.src = true, src
    a.name, a.displayName = src.name, nil
    a.class = (type(src.classFilename) == "string" and not Hidden(src.classFilename)) and src.classFilename or nil
    a.isSelf = src.isLocalPlayer == true or nil
    a.grupo = true
    a.deathRecapID = (not Hidden(src.deathRecapID)) and src.deathRecapID or nil
    row.actor, row.combat = a, nil
    -- the bar's colour: class / one colour / yours, never from a number
    local r, g, b, al = Meter.BarColor(a, d)
    row.tex:SetVertexColor(r, g, b, al * (tonumber(d.barAlpha) or 1))
    local v = PER_SECOND[display] and src.amountPerSecond or src.totalAmount
    local ps = src.amountPerSecond
    local hidden = Hidden(v, top, ps, src.name)
    if not hidden and type(v) == "number" and type(top) == "number" and top > 0 then
        row.bar:SetMinMaxValues(0, 100)
        row.bar:SetValue(floor(v / top * 100))
    else
        ns.ShowBar(row.bar, v, top)
    end
    -- the icon: the game's spec icon where it reads plain, else the class
    if d.showIcons ~= false then
        local sid = src.specIconID
        if d.useSpecIcons and sid ~= nil and not Hidden(sid) and type(sid) == "number" and sid > 0 then
            row.icon:SetTexture(sid)
            ZacUI.Look.CropIcon(row.icon)
        else
            Meter.SetRowIcon(row, a, d)
        end
    end
    -- the name (its realm cut and its format only when it reads plain)
    local name = src.name
    if not Hidden(name) and type(name) == "string" then
        name = Meter.DisplayName(a)
        local nf = type(d.formats) == "table" and d.formats.name
        if nf and ns.FormatName then name = ns.FormatName(name, nf) end
        if d.showRank then
            name = (d.dimRank ~= false and ((Meter.DIM_CODE or "") .. rank .. ".|r ") or (rank .. ". ")) .. name
        end
        row.leftText:SetText(name)
    elseif d.showRank then
        ns.ShowText(row.leftText, (d.dimRank ~= false and Meter.DIM_CODE) and (Meter.DIM_CODE .. "%d.|r %s") or "%d. %s", rank, name)
    else
        pcall(row.leftText.SetText, row.leftText, name)
    end
    if d.nameColorMode == "class" then
        local c = Meter.CLASS_COLORS[a.class or ""] or Meter.CLASS_COLORS.UNKNOW
        row.leftText:SetTextColor(c[1], c[2], c[3], 1)
    end
    -- the number
    if hidden or Hidden(ps) then
        HiddenRight(row, disp, v, ps, d)
    else
        local ToK = Meter.ToKList[d.psAbbrev] or Meter.ToK
        local share = (sum and sum > 0 and type(v) == "number") and (v / sum * 100) or 0
        row.rightText:SetText(Meter.RightText(disp, v or 0, type(ps) == "number" and ps or 0, share, ToK, d))
    end
    if row.dmf and row.dmf:IsShown() then row.dmf:Hide() end
end

-- a fight's sum of the values, only when every one reads plain
local function PlainSum(list, display)
    local sum = 0
    for _, src in ipairs(list) do
        local v = PER_SECOND[display] and src.amountPerSecond or src.totalAmount
        if Hidden(v) or type(v) ~= "number" then return nil end
        sum = sum + v
    end
    return sum
end

-- your own Feign Death: a death row the game counts for it is not one
local feignAt = 0
local FEIGN = 5384
local feignFrame = CreateFrame("Frame")
feignFrame:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" or Hidden(spellID) then return end
    if spellID == FEIGN then feignAt = GetTime() end
end)
if feignFrame.RegisterUnitEvent then
    pcall(feignFrame.RegisterUnitEvent, feignFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
else
    pcall(feignFrame.RegisterEvent, feignFrame, "UNIT_SPELLCAST_SUCCEEDED")
end
local function Feigning(src)
    if src.isLocalPlayer ~= true then return false end
    if GetTime() - feignAt > 30 then return false end
    return not (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
end

-- ============================================================
-- PAINTING A WINDOW
-- ============================================================
function Live.Paint(win)
    local s = win.settings
    local display = s.display
    local disp = Meter.DISPLAYS[display]
    if not disp then return end
    local d = Look()
    if NotKept(display, true) then
        for _, row in ipairs(win.rows) do Meter.HideRow(row) row.actor = nil end
        Note(win, format("%s doesn't give addons %s.", VersionName(), disp.label:lower()))
        return
    end
    Note(win, nil)
    if not win.frame:IsVisible() and not win.liveSample then win.liveStale = true return end
    win.liveStale = nil
    local session = win.liveSample or Read(s.segment or 0, GameKind(display))
    local list = session and session.combatSources or {}
    if display == "deaths" then
        local kept = {}
        for _, src in ipairs(list) do if not Feigning(src) then kept[#kept + 1] = src end end
        list = kept
    end
    local n = #list
    local fit = win.rowsFit or 0
    win.scrollMax = max(0, n - fit)
    local offset = win.scroll or 0
    if offset > win.scrollMax then offset = win.scrollMax win.scroll = offset end
    local first = list[1]
    local top = first and (PER_SECOND[display] and first.amountPerSecond or first.totalAmount)
    local sum = PlainSum(list, display)
    -- your own row (look.pinSelf), as the meter's own refresh does it
    local pin = d.pinSelf or "follow"
    local pinSlot, pinRank
    if pin ~= "off" and fit > 0 then
        for j = 1, n do
            if list[j].isLocalPlayer == true then
                if j < offset + 1 and pin == "pin" then pinSlot, pinRank = 1, j
                elseif j > offset + fit and (pin == "pin" or offset == 0) then pinSlot, pinRank = fit, j end
                break
            end
        end
    end
    if win.title and win.title:IsShown() then Meter.UpdateTitle(win) end
    local selfShown = false
    for i = 1, fit do
        local row = win.rows[i]
        if row then
            local rank = i + offset
            local src = list[rank]
            if i == pinSlot and not selfShown then src, rank = list[pinRank], pinRank end
            if row.pinLine then row.pinLine:Hide() end
            if src then
                if src.isLocalPlayer == true then selfShown = true end
                PaintRow(row, src, rank, top, disp, display, d, sum)
                if not row:IsShown() or row._zLeaving then Meter.ShowRow(row) end
            else
                Meter.HideRow(row)
                row.actor = nil
            end
        end
    end
end

-- the refresh asks first (Meter_Windows): true = this file took the window
function Live.Hook(win, force)
    if Live.Owns(win) then
        if win.bd and Meter.Breakdown then
            Meter.Breakdown.Refresh(win)
        elseif force or win.liveStale then
            Live.Paint(win)
        end
        return true
    end
    -- out of the fight: the modes the game never keeps say so
    local disp = Meter.DISPLAYS[win.settings.display]
    if disp and win.settings.display ~= "threat" and NotKept(win.settings.display, false) and not win.preview then
        Note(win, format("%s doesn't give addons %s.", VersionName(), disp.label:lower()))
    else
        Note(win, nil)
    end
    return false
end

-- ============================================================
-- THE BREAKDOWN IN A FIGHT: yours, from the game; anyone else's waits
-- ============================================================
local HIDDEN_DETAILS = "Details are hidden while fighting; click again after the fight."

function Live.OpenBreakdown(win, actor)
    local BD = Meter.Breakdown
    if not BD then return end
    local key = actor.isSelf and "live:self" or "live:other"
    if win.bd and win.bd.liveKey == key then BD.Close(win) return end
    local me = Meter.playerName or (UnitName and UnitName("player")) or "You"
    BD.Show(win, { name = actor.isSelf and me or "", label = actor.isSelf and me or "This player",
        live = true, liveKey = key, deathRecapID = actor.deathRecapID, scroll = 0 })
end

local function SpellName(id)
    local C = C_Spell
    if C and C.GetSpellName then
        local ok, n = pcall(C.GetSpellName, id)
        if ok and n ~= nil then return n end
    end
    if GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok and n ~= nil then return n end
    end
    return "Ability"
end
local function SpellIcon(id)
    local C = C_Spell
    if C and C.GetSpellTexture then
        local ok, t = pcall(C.GetSpellTexture, id)
        if ok and t ~= nil then return t end
    end
    if GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, id)
        if ok then return t end
    end
end

-- your death's recap from the game (C_DeathRecap), its fields handed whole
local function RecapEntries(out, id)
    local DR = C_DeathRecap
    if not (DR and DR.GetRecapEvents and type(id) == "number" and id > 0) then
        out[#out + 1] = { kind = "line", left = (Meter.FOREVER_DEATH_NOTE or "No recap for this one.") }
        return
    end
    local ok, evs = pcall(DR.GetRecapEvents, id)
    if not ok or type(evs) ~= "table" or #evs == 0 then
        out[#out + 1] = { kind = "line", left = "No recap for this one." }
        return
    end
    out[#out + 1] = { kind = "section", text = "The last hits" }
    for i = 1, min(#evs, 8) do
        local e = evs[i]
        local name = e.spellName
        if name == nil and e.spellId ~= nil then name = SpellName(e.spellId) end
        out[#out + 1] = { kind = "bar", live = true, name = name or "Melee", value = nil, top = nil,
            color = { 0.78, 0.25, 0.22 }, icon = e.spellId ~= nil and SpellIcon(e.spellId) or nil,
            rfmt = "%s", rargs = { e.amount } }
    end
end

function Live.Entries(win, st)
    local out = {}
    -- your own breakdown opened before the pull carries on, live
    if not st.live and st.name ~= nil and st.name == Meter.playerName then
        st.live, st.liveKey = true, "live:self"
    end
    if not st.live then
        -- a breakdown opened before the fight: it waits for the fight's end
        out[1] = { kind = "line", left = HIDDEN_DETAILS }
        return out, nil
    end
    if st.liveKey ~= "live:self" then
        out[1] = { kind = "line", left = HIDDEN_DETAILS }
        return out, nil
    end
    local display = win.settings.display
    if display == "deaths" then
        RecapEntries(out, st.deathRecapID)
        return out, nil
    end
    local kind = GameKind(display)
    local guid = UnitGUID and UnitGUID("player")
    local fn = C_DamageMeter.GetCombatSessionSourceFromType
    if not (kind and guid and fn) or NotKept(display, true) or display == "damage_taken" or display == "enemy_taken"
        or Meter.MISC_KIND and Meter.MISC_KIND[display] then
        out[1] = { kind = "line", left = HIDDEN_DETAILS }
        return out, nil
    end
    reads = reads + 1
    local ok, src = pcall(fn, SessionType(win.settings.segment or 0), kind, guid)
    local spells = ok and type(src) == "table" and src.combatSpells or nil
    if type(spells) ~= "table" or #spells == 0 then
        out[1] = { kind = "line", left = "Nothing from the game's meter yet." }
        return out, nil
    end
    local d = Look()
    local r, g, b = Meter.BarColor({ isSelf = true, class = select(2, UnitClass("player")) }, d)
    out[1] = { kind = "section", text = "Abilities (live)" }
    local top = spells[1].totalAmount
    local ToK = Meter.ToKList[d.psAbbrev] or Meter.ToK
    for _, sp in ipairs(spells) do
        local v = sp.totalAmount
        local plain = not Hidden(v, top, sp.spellID)
        local e = { kind = "bar", live = true, name = SpellName(sp.spellID), value = v, top = top,
            color = { r, g, b }, icon = SpellIcon(sp.spellID), spell = plain and sp.spellID or nil,
            rfmt = "%s", rargs = { ToK(v) } }
        out[#out + 1] = e
    end
    return out, nil
end

-- ============================================================
-- THE ROW TOOLTIP IN A FIGHT: what the mode means, and that the rest
-- comes when it ends (the plain-words lines read the meter's own fight)
-- ============================================================
local origTooltip = Meter.RowTooltip
Meter.RowTooltip = function(row, win)
    local a = row.actor
    if not (a and a.live) then return origTooltip(row, win) end
    local disp = Meter.DISPLAYS[win.settings.display]
    GameTooltip:SetOwner(row, "ANCHOR_TOPRIGHT")
    local t, c = ns.GetColor("tooltip", "title"), ns.GetColor("tooltip", "body")
    pcall(GameTooltip.AddLine, GameTooltip, a.name, t.r, t.g, t.b)
    if disp and disp.desc then GameTooltip:AddLine(disp.desc, c.r, c.g, c.b, true) end
    GameTooltip:AddLine("Live from the game's own meter. Its details come when the fight ends"
        .. (a.isSelf and "; click for your abilities now." or "."), c.r, c.g, c.b, true)
    GameTooltip:Show()
end

-- ============================================================
-- THE TICK - once a second in a fight, only the windows on screen
-- ============================================================
local ticker
local function Tick()
    if not Meter.inCombat then
        if ticker then ticker:Cancel() ticker = nil end
        return
    end
    for _, win in ipairs(windows) do
        if Live.Owns(win) and win.frame:IsVisible() then
            if win.bd and Meter.Breakdown then Meter.Breakdown.Refresh(win) else Live.Paint(win) end
        end
    end
end
Live.Tick = Tick

function Live.Start()
    if ticker then return end
    ticker = C_Timer.NewTicker(TICK, Tick)
    if ns.Profiler and ns.Profiler.TrackTicker then ns.Profiler.TrackTicker(ticker, "meter.live") end
end
function Live.Stop()
    if ticker then ticker:Cancel() ticker = nil end
end
function Live.Running() return ticker ~= nil end

-- the rows go back to the meter's own fight: their 0-100 bars, no live
-- actor; a breakdown of yours carries on with the filled fight
local function Release(win)
    for _, row in ipairs(win.rows) do
        if row.actor and row.actor.live then row.actor = nil end
        row.bar:SetMinMaxValues(0, 100)
    end
    Note(win, nil)
    local st = win.bd
    if st and st.live then
        if st.liveKey == "live:self" then
            st.live, st.liveKey = nil, nil
        elseif Meter.Breakdown then
            Meter.Breakdown.Close(win)
        end
    end
end
Live.Release = Release

local origStart, origEnd = Meter.OnCombatStart, Meter.OnCombatEnd
Meter.OnCombatStart = function(...)
    if origStart then origStart(...) end
    Live.Start()
    for _, win in ipairs(windows) do
        if Live.Owns(win) then win.scroll = 0 Live.Paint(win) end
    end
end
Meter.OnCombatEnd = function(...)
    Live.Stop()
    for _, win in ipairs(windows) do Release(win) end
    if origEnd then return origEnd(...) end
end
