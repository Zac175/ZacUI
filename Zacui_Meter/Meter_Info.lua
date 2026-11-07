-- Meter_Info - the meter's inspection surfaces: the row tooltip, the
-- breakdown window a bar click opens, and the report-to-chat flow.
-- Part of ZacUI; load order is set by the TOC.
--
-- The tooltip shows what his Details tooltip config showed: the top 3
-- abilities and top 3 targets (n_abilities = 3, n_enemies = 3), with
-- ToK values and percents. The breakdown window is the useful core of
-- Details' player window - every spell with hits, crits, min/max and
-- its targets - built on ZacUI chrome instead of a port of 10k lines
-- of frame code. Reports paste the same lines Details pasted: rank,
-- name, then the bar's right text.
--
-- EVERY VIEW SAYS WHAT HAPPENED (Zac 2026-11-07: "you need to do a better
-- job of explaining things more like for example deaths"). Each row
-- tooltip opens with the display's one-line meaning, then what the row
-- means: a death's killing blow and the hits and heals before it, what an
-- interrupt stopped or a dispel removed, a damage row's active time and
-- DPS, a healer's overheal. A death click opens the death recap (the
-- whole log, a small health line, report to chat) in the breakdown
-- window's place. All of it is built on hover or click from what the
-- parser already keeps; nothing new runs in combat.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local Col = ns.Col
local Meter = ns.Meter
local Print = ns.Print

local floor, format = math.floor, string.format
local tsort, wipe = table.sort, wipe

local FONT = Meter.FONT
-- the meter's font (ZacUI's, handed over from Fonts & Textures, unless the
-- meter page picked its own), kept up when it changes
local function MeterFont(fs, size)
    local ok, set = pcall(fs.SetFont, fs, Meter.FontPath and Meter.FontPath() or FONT, size)
    if not (ok and set) then fs:SetFont(FONT, size) end
    if ns.TrackHouseFont then ns.TrackHouseFont(fs, function(s) MeterFont(s, size) end) end
end

-- ============================================================
-- HELPERS
-- ============================================================
local function SpellName(id, fallback)
    if id == 1 then return _G.MELEE or "Melee" end
    if id == 2 then return "Auto Shot" end
    if Meter.ENVIRONMENT_NAMES[id] then return Meter.ENVIRONMENT_NAMES[id] end
    local name = GetSpellInfo and GetSpellInfo(id)
    return name or fallback or ("Spell " .. tostring(id))
end

local function TopEntries(map, n, nameFn)
    local list = {}
    for key, value in pairs(map) do
        list[#list + 1] = { key = key, value = value }
    end
    tsort(list, function(a, b) return a.value > b.value end)
    for i = n + 1, #list do list[i] = nil end
    return list
end

-- ============================================================
-- PLAIN WORDS - colours, icons and the line list every explanation is
-- built as. A tooltip is a list of { l, r, lc, rc, wrap } lines (lc/rc a
-- palette key pair): the row tooltip hands them to GameTooltip, the
-- settings preview draws the very same list in a box of its own.
-- ============================================================
local GetColor = ns.GetColor
local UI = ns.UI
local TIP_MAX_LINES = 30            -- a tooltip taller than this runs off the screen

local function Hex(cat, key)
    local c = GetColor(cat, key)
    return format("|cff%02x%02x%02x", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5))
end
local function Paint(cat, key, text) return Hex(cat, key) .. text .. "|r" end
local function Gray(text) return Paint("text", "gray", text) end

local MELEE_ICON = "Interface\\Icons\\INV_Sword_04"
local function SpellIcon(id)
    if id == 1 then return MELEE_ICON end
    if id == 2 then return GetSpellTexture and GetSpellTexture(75) or nil end
    if type(id) ~= "number" or Meter.ENVIRONMENT_NAMES[id] then return nil end
    return GetSpellTexture and GetSpellTexture(id) or nil
end
local function IconText(id)
    local tex = SpellIcon(id)
    return tex and ("|T" .. tex .. ":0|t ") or ""
end

-- a death's spell name: the game's, else a name the death carries (the
-- sample death names its own spells)
local function DeathSpell(dt, id)
    return Meter.SpellLabel(id, dt and dt.names and dt.names[id])
end

local function Add(lines, l, r, lc, rc, wrap)
    lines[#lines + 1] = { l = l or "", r = r, lc = lc or { "text", "normal" }, rc = rc or { "text", "normal" }, wrap = wrap }
end
local GAP = { l = " " }
local function Gap(lines) lines[#lines + 1] = GAP end

-- the lines onto GameTooltip (the owner is already set, the title added)
local function EmitTip(lines)
    for i = 1, math.min(#lines, TIP_MAX_LINES) do
        local ln = lines[i]
        if ln == GAP then
            GameTooltip:AddLine(" ")
        else
            local a = GetColor(ln.lc[1], ln.lc[2])
            if ln.r then
                local b = GetColor(ln.rc[1], ln.rc[2])
                GameTooltip:AddDoubleLine(ln.l, ln.r, a.r, a.g, a.b, b.r, b.g, b.b)
            else
                GameTooltip:AddLine(ln.l, a.r, a.g, a.b, ln.wrap and true or false)
            end
        end
    end
end
Meter.EmitTip = EmitTip
Meter.TIP_MAX_LINES = TIP_MAX_LINES

-- this client gets no death log or misc lines at all (WoW Forever: the
-- game's own meter gives addons counts only)
local function CountsOnly(combat)
    return (combat and combat.fromGameMeter) or Meter.GameMeter ~= nil
end
Meter.FOREVER_DEATH_NOTE = "Forever doesn't give addons the hits before a death."
Meter.FOREVER_MISC_NOTE = "Forever only gives addons the count, not what it was."
Meter.PARTLY_SEEN_NOTE = "The meter may have missed the hit that killed them (out of range?)."

-- ============================================================
-- DEATHS - one block of lines per death
-- ============================================================
local function WhenText(dt, withFight)
    local t = "Died " .. Meter.Clock(dt.deadAt) .. " into the pull"
    if withFight and dt.fight then t = "Died on " .. dt.fight .. ", " .. Meter.Clock(dt.deadAt) .. " in" end
    return t
end
local function ClockOf(dt)
    return (dt.clock and date) and date("%H:%M:%S", dt.clock) or nil
end

-- "-4,210 crit" in red / "+1,800" in green, and the health after it
local function AmountText(e, hpKnown)
    local amt = (e.dmg and "-" or "+") .. Meter.Comma(e.amt) .. (e.crit and " crit" or "")
    amt = e.dmg and Paint("text", "red", amt) or Paint("text", "green", amt)
    if hpKnown and type(e.hp) == "number" then
        amt = amt .. Gray(format("  %d%%", floor(e.hp * 100 + 0.5)))
    end
    return amt
end

-- One death as tooltip lines: when, the killing blow, up to maxEvents
-- earlier hits and heals newest first, the last five seconds. Returns how
-- many events did not fit.
function Meter.DeathTipLines(dt, lines, maxEvents, withFight)
    local s = Meter.DeathSummary(dt)
    Add(lines, WhenText(dt, withFight), ClockOf(dt), { "text", "red" }, { "text", "gray" })
    if not s.seen then
        Add(lines, "The meter saw none of the hits before it:", nil, { "text", "gray" })
        Add(lines, "out of range, or they joined the fight late.", nil, { "text", "gray" })
        return 0
    end
    local evs = Meter.DeathEvents(dt)
    local kbAt
    for i, e in ipairs(evs) do if e.dmg then kbAt = i break end end
    if kbAt then
        local k = evs[kbAt]
        local r = Meter.Comma(k.amt) .. (k.crit and " crit" or "")
        if k.over > 0 then r = r .. " (" .. Meter.Comma(k.over) .. " overkill)" end
        Add(lines, (s.sure and "Killing blow: " or "Last hit seen: ") .. IconText(k.spell) .. DeathSpell(dt, k.spell)
            .. (k.src and Gray(" from " .. k.src) or ""), r, { "text", "gold" }, { "text", "red" })
        if not s.sure then
            Add(lines, Meter.PARTLY_SEEN_NOTE, nil, { "text", "gray" }, nil, true)
        end
    else
        Add(lines, "No hit seen; only heals reached the log.", nil, { "text", "gray" })
    end
    local shown, more = 0, 0
    for i, e in ipairs(evs) do
        if i ~= kbAt then
            if shown < maxEvents then
                shown = shown + 1
                Add(lines, Gray(format("-%.1fs", e.ago)) .. "  " .. IconText(e.spell) .. DeathSpell(dt, e.spell)
                    .. (e.src and Gray("  " .. e.src) or ""), AmountText(e, s.hpKnown))
            else
                more = more + 1
            end
        end
    end
    Add(lines, format("Last 5 seconds: took %s, healed %s", Meter.Comma(s.took5), Meter.Comma(s.healed5)),
        nil, { "text", "gray" })
    return more
end

-- this player's deaths in a window's combat, newest first
local function DeathsOf(combat, name)
    local out = {}
    local all = Meter.DeathsFor(combat)
    for i = #all, 1, -1 do
        if all[i].name == name then out[#out + 1] = all[i] end
    end
    return out
end
Meter.DeathsOf = DeathsOf

-- Every death of one player: one block each, newest first, as many as
-- fit; the ones that do not are counted at the end.
function Meter.DeathRowLines(combat, actor, lines)
    local deaths = DeathsOf(combat, actor.name)
    local counted = actor.dead or 0
    if #deaths == 0 then
        if CountsOnly(combat) then
            Add(lines, format("Died %d time%s", counted, counted == 1 and "" or "s"), nil, { "text", "red" })
            Add(lines, Meter.FOREVER_DEATH_NOTE, nil, { "text", "gray" }, nil, true)
        else
            Add(lines, "The meter kept no log of these deaths (from before a reload).", nil, { "text", "gray" }, nil, true)
        end
        return
    end
    local n = #deaths
    local blocks = math.min(n, 3)
    local per = (n == 1 and 10) or (n == 2 and 6) or 3
    local hidden = 0
    for i = 1, blocks do
        if i > 1 then Gap(lines) end
        hidden = hidden + Meter.DeathTipLines(deaths[i], lines, per, combat.overall)
    end
    Gap(lines)
    if n > blocks then
        Add(lines, format("+%d earlier death%s. Click to see them all.", n - blocks, n - blocks == 1 and "" or "s"),
            nil, { "text", "gray" })
    else
        Add(lines, hidden > 0 and format("Click for the full recap (%d more hits and heals).", hidden)
            or "Click for the full recap.", nil, { "text", "gray" })
    end
    if counted > n then
        Add(lines, format("%d more not kept (from before a reload).", counted - n), nil, { "text", "gray" })
    end
end

-- ============================================================
-- INTERRUPTS, DISPELS, CC BREAKS, BATTLE RES - what each one was
-- ============================================================
local MISC_KIND = { interrupts = "interrupt", dispels = "dispel", cc_breaks = "cc", ress = "ress" }
local MISC_HEAD = {
    interrupt = "Stopped, newest first",
    dispel = "Removed, newest first",
    cc = "Broke, newest first",
    ress = "Brought back, newest first",
}
Meter.MISC_KIND = MISC_KIND

-- when it happened: "1:05", or "Ebonroc 1:05" across several fights
local function MiscWhen(e, withFight)
    local t = Meter.Clock(e.at)
    if withFight and e.fight then t = e.fight .. " " .. t end
    return t
end
-- one line, worded for its kind: left, right
function Meter.MiscLine(e, withFight)
    local when = MiscWhen(e, withFight)
    if e.k == "interrupt" then
        local what = e.what and (IconText(e.what) .. Meter.SpellLabel(e.what)) or "a cast"
        return what .. (e.on and Gray("  " .. e.on) or ""),
            Gray((e.spell and (Meter.SpellLabel(e.spell) .. "  ") or "") .. when)
    elseif e.k == "dispel" then
        local what = e.what and (IconText(e.what) .. Meter.SpellLabel(e.what)) or "an effect"
        return what .. (e.on and Gray("  on " .. e.on) or ""), Gray(when)
    elseif e.k == "cc" then
        return IconText(e.spell) .. Meter.SpellLabel(e.spell) .. (e.on and Gray("  on " .. e.on) or ""),
            Gray((e.what and ("with " .. Meter.SpellLabel(e.what) .. "  ") or "") .. when)
    end
    return (e.on or "?") .. Gray("  " .. Meter.SpellLabel(e.spell)), Gray(when)
end

-- this player's lines of one kind, newest first
local function MiscOf(combat, name, kind)
    local out = {}
    local all = Meter.MiscLogFor(combat)
    for i = #all, 1, -1 do
        local e = all[i]
        if e.k == kind and e.who == name then out[#out + 1] = e end
    end
    return out
end
Meter.MiscOf = MiscOf

function Meter.MiscRowLines(combat, actor, display, lines, max)
    local kind = MISC_KIND[display]
    if not kind then return end
    local list = MiscOf(combat, actor.name, kind)
    if #list == 0 then
        if CountsOnly(combat) then
            Add(lines, Meter.FOREVER_MISC_NOTE, nil, { "text", "gray" }, nil, true)
        else
            Add(lines, "No details kept for these (from before a reload).", nil, { "text", "gray" }, nil, true)
        end
        return
    end
    Add(lines, MISC_HEAD[kind], nil, { "text", "gold" })
    max = max or 12
    for i = 1, math.min(#list, max) do
        local l, r = Meter.MiscLine(list[i], combat.overall)
        Add(lines, l, r)
    end
    if #list > max then
        Add(lines, format("+%d more. Click to see them all.", #list - max), nil, { "text", "gray" })
    end
end

-- ============================================================
-- PER-ROW CONTEXT for the damage and healing displays
-- ============================================================
local function Pct(part, whole) return whole > 0 and format("%.1f%%", part / whole * 100) or "0%" end

-- who did the most of `field` TO this player: every actor's targets map
-- read for this name (hover only)
local function FromOthers(cont, name)
    local map = {}
    for _, a in ipairs(cont and cont.actors or {}) do
        if a.name ~= name then
            local t = a.targets
            local v = t and t[name]
            if v and v >= 1 then map[a.displayName or a.name] = v end
        end
    end
    return map
end

local function TopBlock(lines, title, map, n, total, ToK)
    if not (map and next(map)) then return end
    Gap(lines)
    Add(lines, title, nil, { "text", "gold" })
    for _, e in ipairs(TopEntries(map, n)) do
        Add(lines, e.key, ToK(e.value) .. (total and total > 0 and (" (" .. Pct(e.value, total) .. ")") or ""))
    end
end

local function ContextLines(display, actor, combat, lines, ToK)
    local total = actor.total or 0
    if display == "damage_done" or display == "dps" then
        local act = actor.ActivityTime and actor:ActivityTime() or 0
        Add(lines, "Active " .. Meter.Clock(act), ToK(act > 0 and total / act or 0) .. " DPS", { "text", "gray" })
        local group = combat.groupTotals and combat.groupTotals.damage or 0
        if group > 0 then Add(lines, "Share of the group's damage", Pct(total, group), { "text", "gray" }) end
    elseif display == "heal_done" or display == "hps" then
        local act = actor.ActivityTime and actor:ActivityTime() or 0
        Add(lines, "Active " .. Meter.Clock(act), ToK(act > 0 and total / act or 0) .. " HPS", { "text", "gray" })
        local over = actor.totalOver or 0
        Add(lines, "Overheal", Pct(over, total + over) .. "  (" .. ToK(over) .. " wasted)", { "text", "gray" })
        if (actor.totalAbsorb or 0) >= 1 then
            Add(lines, "Shields that absorbed damage", ToK(actor.totalAbsorb), { "text", "gray" })
        end
    elseif display == "overheal" then
        local over = actor.totalOver or 0
        Add(lines, Pct(over, total + over) .. " of their healing went past full health.", nil, { "text", "gray" }, nil, true)
        local map = {}
        for id, sp in pairs(actor.spells or {}) do
            if (sp.overheal or 0) >= 1 then map[Meter.SpellLabel(id, sp.name)] = sp.overheal end
        end
        TopBlock(lines, "Most overheal from", map, 3, over, ToK)
    elseif display == "absorbs" then
        local map = {}
        for id, sp in pairs(actor.spells or {}) do
            if (sp.absorbed or 0) >= 1 then map[Meter.SpellLabel(id, sp.name)] = sp.absorbed end
        end
        TopBlock(lines, "Shields", map, 3, actor.totalAbsorb, ToK)
    elseif display == "heal_taken" then
        TopBlock(lines, "Healed most by", FromOthers(combat.heal, actor.name), 3, actor.healingTaken, ToK)
    elseif display == "damage_taken" then
        TopBlock(lines, "Hit hardest by", FromOthers(combat.damage, actor.name), 3, actor.damageTaken, ToK)
    elseif display == "friendly_fire" then
        TopBlock(lines, "Hit in the group", actor.friendlyFire, 3, actor.friendlyFireTotal, ToK)
    end
end

-- the displays whose rows also list the actor's abilities and targets
local ABILITY_DISPLAYS = { damage_done = true, dps = true, heal_done = true, hps = true }

-- ============================================================
-- ROW TOOLTIP - the display's one-line meaning on top, then what this
-- row means: a death's killing blow and the hits before it, what an
-- interrupt stopped, a damage row's active time and DPS...
-- ============================================================
function Meter.RowTooltipLines(row, win)
    local actor = row.actor
    local lines = {}
    if not actor then return lines end
    local ToK = Meter.ToKList[Meter.DB().psAbbrev] or Meter.ToK
    local display = win.settings.display
    local disp = Meter.DISPLAYS[display]
    local combat = row.combat or Meter.CombatForWindow(win)
    if disp and disp.desc then Add(lines, disp.desc, nil, { "text", "gray" }, nil, true) end
    if not combat then return lines end

    if disp and disp.container == "misc" then
        Gap(lines)
        if display == "deaths" then
            Meter.DeathRowLines(combat, actor, lines)
        else
            Meter.MiscRowLines(combat, actor, display, lines)
        end
        return lines
    end

    ContextLines(display, actor, combat, lines, ToK)
    if not ABILITY_DISPLAYS[display] then return lines end
    local total = (actor.total and actor.total > 0) and actor.total or 1
    if actor.spells and next(actor.spells) then
        local spellTotals = {}
        for id, sp in pairs(actor.spells) do spellTotals[id] = sp.total end
        Gap(lines)
        Add(lines, "Abilities", nil, { "text", "gold" })
        for _, e in ipairs(TopEntries(spellTotals, 3)) do
            local sp = actor.spells[e.key]
            Add(lines, SpellName(e.key, sp.name), ToK(e.value) .. " (" .. format("%.1f", e.value / total * 100) .. "%)")
        end
    end
    if actor.targets and next(actor.targets) then
        Gap(lines)
        Add(lines, "Targets", nil, { "text", "gold" })
        for _, e in ipairs(TopEntries(actor.targets, 3)) do
            Add(lines, e.key, ToK(e.value) .. " (" .. format("%.1f", e.value / total * 100) .. "%)")
        end
    end
    return lines
end

function Meter.RowTooltip(row, win)
    local actor = row.actor
    if not actor then return end
    GameTooltip:SetOwner(row, "ANCHOR_TOPRIGHT")
    local t = GetColor("tooltip", "title")
    GameTooltip:AddLine(row.leftText:GetText() or actor.name, t.r, t.g, t.b)
    EmitTip(Meter.RowTooltipLines(row, win))
    GameTooltip:Show()
end

-- ============================================================
-- BREAKDOWN WINDOW - spells on top, targets below, one actor at a time.
-- ============================================================
local breakdown

local function BuildBreakdown()
    local f = CreateFrame("Frame", "ZacUIMeterBreakdown", UIParent)
    f:SetSize(330, 320)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.97)
    if AddPixelBorder then AddPixelBorder(f) end

    f.title = f:CreateFontString(nil, "OVERLAY")
    MeterFont(f.title, 13)
    f.title:SetShadowColor(0, 0, 0, 1)
    f.title:SetShadowOffset(1, -1)
    f.title:SetPoint("TOPLEFT", 10, -8)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -6, -6)
    local x = close:CreateFontString(nil, "OVERLAY")
    MeterFont(x, 12)
    x:SetPoint("CENTER")
    x:SetText("X")
    close:SetScript("OnClick", function() f:Hide() end)

    f.lines = {}
    for i = 1, 24 do
        local left = f:CreateFontString(nil, "OVERLAY")
        MeterFont(left, 11)
        left:SetShadowColor(0, 0, 0, 1)
        left:SetShadowOffset(1, -1)
        left:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 12)
        left:SetJustifyH("LEFT")
        local right = f:CreateFontString(nil, "OVERLAY")
        MeterFont(right, 11)
        right:SetShadowColor(0, 0, 0, 1)
        right:SetShadowOffset(1, -1)
        right:SetPoint("TOPRIGHT", -10, -28 - (i - 1) * 12)
        right:SetJustifyH("RIGHT")
        left:SetPoint("RIGHT", right, "LEFT", -6, 0)
        left:SetWordWrap(false)
        f.lines[i] = { left = left, right = right }
    end
    f:Hide()
    return f
end

function Meter.OpenBreakdown(win, actor)
    local display = win.settings.display
    -- a death opens its recap in this window's place
    if display == "deaths" and Meter.OpenDeathRecap then
        return Meter.OpenDeathRecap(Meter.CombatForWindow(win), actor)
    end
    breakdown = breakdown or BuildBreakdown()
    if Meter.CloseDeathRecap then Meter.CloseDeathRecap() end
    local ToK = Meter.ToKList[Meter.DB().psAbbrev] or Meter.ToK
    local f = breakdown
    local disp = Meter.DISPLAYS[display]
    f.title:SetText((actor.displayName or actor.name)
        .. "  -  " .. (disp and disp.label or ""))

    local li = 0
    local function line(l, r, gold)
        li = li + 1
        local fs = f.lines[li]
        if not fs then return end
        fs.left:SetText(l or "")
        fs.right:SetText(r or "")
        local cr, cg, cb = 1, 1, 1
        if gold then cr, cg, cb = 1, 0.82, 0 end
        fs.left:SetTextColor(cr, cg, cb)
        fs.right:SetTextColor(1, 1, 1)
    end

    -- interrupts, dispels, cc breaks, battle res: every one of them,
    -- worded as the tooltip words them
    local kind = Meter.MISC_KIND[display]
    if kind then
        local combat = Meter.CombatForWindow(win)
        local list = Meter.MiscOf(combat, actor.name, kind)
        if #list == 0 then
            line((combat and combat.fromGameMeter or Meter.GameMeter) and Meter.FOREVER_MISC_NOTE
                or "No details kept for these (from before a reload).", "")
        else
            line(#list .. " in all, newest first", "When", true)
            for i = 1, math.min(#list, #f.lines - 1) do
                local l, r = Meter.MiscLine(list[i], combat and combat.overall)
                line(l, r)
            end
        end
        for i = li + 1, #f.lines do
            f.lines[i].left:SetText("")
            f.lines[i].right:SetText("")
        end
        f:Show()
        return
    end

    local total = (actor.total and actor.total > 0) and actor.total or 1
    if actor.spells and next(actor.spells) then
        line("Ability   (hits, crit%)", "Total", true)
        local ordered = {}
        for id, sp in pairs(actor.spells) do
            ordered[#ordered + 1] = { id = id, sp = sp }
        end
        tsort(ordered, function(a, b) return a.sp.total > b.sp.total end)
        for i = 1, math.min(#ordered, 12) do
            local sp = ordered[i].sp
            local critPct = sp.counter > 0 and (sp.c_amt / sp.counter * 100) or 0
            line(SpellName(ordered[i].id, sp.name)
                .. "  (" .. sp.counter .. ", " .. format("%.0f", critPct) .. "%)",
                ToK(sp.total) .. " (" .. format("%.1f", sp.total / total * 100) .. "%)")
        end
    end
    if actor.targets and next(actor.targets) then
        line(" ", " ")
        line("Targets", "", true)
        for _, e in ipairs(TopEntries(actor.targets, 8)) do
            line(e.key, ToK(e.value) .. " (" .. format("%.1f", e.value / total * 100) .. "%)")
        end
    end
    for i = li + 1, #f.lines do
        f.lines[i].left:SetText("")
        f.lines[i].right:SetText("")
    end
    f:Show()
end

-- ============================================================
-- REPORT - channel picker, then paste the visible rows.
-- ============================================================
local report

local CHANNELS = {
    { key = "PARTY", label = "Party" },
    { key = "RAID", label = "Raid" },
    { key = "GUILD", label = "Guild" },
    { key = "SAY", label = "Say" },
    { key = "WHISPER", label = "Whisper" },
}

-- the window's visible rows as chat lines (nil: nothing to report)
local function WindowLines(win)
    local d = Meter.DB()
    local disp = Meter.DISPLAYS[win.settings.display]
    local segLabel = (win.settings.segment == -1) and "Overall - " or ""
    local header = "ZacUI: " .. segLabel .. (disp and disp.label or "Threat")

    local lines = { header }
    local count = 0
    for i = 1, #win.rows do
        local row = win.rows[i]
        if row:IsShown() and row.actor then
            count = count + 1
            if count > d.reportLines then break end
            lines[#lines + 1] = count .. ". " .. (row.leftText:GetText() or "")
                .. " " .. (row.rightText:GetText() or "")
        end
    end
    if #lines == 1 then return nil end
    return lines
end

-- lines to a channel (the window's rows, or a death recap's sentence)
local function SendLines(lines, channel, whisperTarget)
    if type(lines) ~= "table" or #lines == 0 then Print("Nothing to report.") return end
    -- party/raid swap to instance chat when in an instance group
    if (channel == "PARTY" or channel == "RAID")
        and GetNumGroupMembers(LE_PARTY_CATEGORY_INSTANCE or 2) > 0
        and IsInInstance() then
        channel = "INSTANCE_CHAT"
    end
    for _, text in ipairs(lines) do
        if channel == "WHISPER" then
            SendChatMessage(text, "WHISPER", nil, whisperTarget)
        else
            SendChatMessage(text, channel)
        end
    end
end

local function BuildReport()
    local f = CreateFrame("Frame", "ZacUIMeterReport", UIParent)
    f:SetSize(160, 30 + #CHANNELS * 22 + 34)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.97)
    if AddPixelBorder then AddPixelBorder(f) end

    local title = f:CreateFontString(nil, "OVERLAY")
    MeterFont(title, 12)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetShadowOffset(1, -1)
    title:SetPoint("TOP", 0, -8)
    title:SetText("Report to...")

    f.buttons = {}
    for i, ch in ipairs(CHANNELS) do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(20)
        b:SetPoint("TOPLEFT", 8, -26 - (i - 1) * 22)
        b:SetPoint("RIGHT", -8, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        local t = b:CreateFontString(nil, "OVERLAY")
        MeterFont(t, 11)
        t:SetShadowColor(0, 0, 0, 1)
        t:SetShadowOffset(1, -1)
        t:SetPoint("LEFT", 4, 0)
        t:SetText(ch.label)
        b:SetScript("OnClick", function()
            f:Hide()
            if ch.key == "WHISPER" then
                StaticPopupDialogs = StaticPopupDialogs or {}
                StaticPopupDialogs["ZACUI_METER_WHISPER"] = {
                    text = "Whisper report to:",
                    button1 = OKAY or "Okay",
                    button2 = CANCEL or "Cancel",
                    hasEditBox = true,
                    timeout = 0, whileDead = true, hideOnEscape = true,
                    OnAccept = function(self)
                        local target = self.editBox:GetText()
                        if target and target ~= "" then
                            SendLines(f.getLines and f.getLines(), "WHISPER", target)
                        end
                    end,
                }
                StaticPopup_Show("ZACUI_METER_WHISPER")
            else
                SendLines(f.getLines and f.getLines(), ch.key)
            end
        end)
        f.buttons[i] = b
    end
    f:Hide()
    return f
end

function Meter.OpenReport(win)
    report = report or BuildReport()
    report.win = win
    report.getLines = function() return WindowLines(win) end
    report:ClearAllPoints()
    report:SetPoint("BOTTOM", win.frame, "TOP", 0, 6)
    report:Show()
end

-- the same channel picker over any frame, sending what getLines returns
function Meter.OpenReportLines(anchor, getLines)
    report = report or BuildReport()
    report.win = nil
    report.getLines = getLines
    report:ClearAllPoints()
    report:SetPoint("BOTTOM", anchor, "TOP", 0, 6)
    report:Show()
end
Meter.SendLines = SendLines

-- ============================================================
-- DEATH RECAP - one death's whole log: who died and when, the killing
-- blow, a small health line over the last ten seconds and every hit and
-- heal in them, newest first, with "Report to chat". A death click opens
-- it in the breakdown window's place. The panel is its own piece so the
-- settings preview shows the very same thing.
-- ============================================================
local UF, UM = UI.F, UI.M
local RECAP_W, RECAP_H = 460, 440
local ROW_H, GRAPH_H, PAD = 16, 46, 10

local function HpKey(hp)
    if hp > 0.5 then return "green" elseif hp > 0.25 then return "orange" end
    return "red"
end

-- the health line: a filled step of health over the window, each event
-- holding the level it left until the next one
local function DrawGraph(g, dt, evs, hpKnown)
    for _, t in ipairs(g.cols) do t:Hide() end
    local gw, gh = (g:GetWidth() or 0), GRAPH_H - 2
    if not hpKnown or #evs == 0 or gw <= 4 then return false end
    gw = gw - 2
    local win = Meter.DEATH_WINDOW
    local mx = tonumber(dt.maxHealth) or 0
    local function X(ago) return floor(gw * (1 - math.min(ago, win) / win) + 0.5) end
    local steps = {}
    -- before the oldest event: the level it started from
    local first = evs[#evs]
    if type(first.hp) == "number" and mx > 0 then
        local before = first.hp + (first.dmg and first.amt or -first.amt) / mx
        if before > 1 then before = 1 elseif before < 0 then before = 0 end
        steps[#steps + 1] = { x0 = 0, x1 = X(first.ago), hp = before }
    end
    for i = #evs, 1, -1 do
        local e = evs[i]
        local nextAgo = (i > 1) and evs[i - 1].ago or 0
        if type(e.hp) == "number" then
            steps[#steps + 1] = { x0 = X(e.ago), x1 = (i > 1) and X(nextAgo) or gw, hp = e.hp }
        end
    end
    for i, st in ipairs(steps) do
        local t = g.cols[i]
        if not t then
            t = g:CreateTexture(nil, "ARTWORK")
            t._zui_own = true
            g.cols[i] = t
        end
        local c = GetColor("text", HpKey(st.hp))
        t:SetColorTexture(c.r, c.g, c.b, 0.75)
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 1 + st.x0, 1)
        t:SetSize(math.max(1, st.x1 - st.x0), math.max(1, floor(st.hp * gh + 0.5)))
        t:Show()
    end
    return true
end

local function RecapRow(p, i)
    local r = p.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, p.child)
    r:SetHeight(ROW_H)
    r.mark = r:CreateTexture(nil, "BACKGROUND")
    r.mark._zui_own = true
    r.mark:SetAllPoints()
    local w = p.innerW
    local nameW = floor((w - 60 - 112) * 0.58)
    r.t = UI.Font(r, UF.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    r.t:SetPoint("LEFT", 0, 0) r.t:SetWidth(36)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon._zui_own = true
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 42, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = UI.Font(r, UF.LABEL, { cat = "text", key = "normal" })
    r.name:SetPoint("LEFT", 60, 0) r.name:SetWidth(nameW) r.name:SetJustifyH("LEFT") r.name:SetWordWrap(false)
    r.src = UI.Font(r, UF.SMALL, { cat = "text", key = "gray" })
    r.src:SetPoint("LEFT", 64 + nameW, 0) r.src:SetWidth(w - 64 - nameW - 112) r.src:SetJustifyH("LEFT")
    r.src:SetWordWrap(false)
    r.amt = UI.Font(r, UF.LABEL, { cat = "text", key = "normal", justify = "RIGHT" })
    r.amt:SetPoint("RIGHT", -40, 0) r.amt:SetWidth(70)
    r.hp = UI.Font(r, UF.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    r.hp:SetPoint("RIGHT", 0, 0) r.hp:SetWidth(36)
    p.rows[i] = r
    return r
end

function Meter.NewRecapPanel(parent, w, h)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(w, h)
    p.innerW = w - 2 * PAD - UM.SCROLL_W - 2
    p.rows = {}
    p.head = UI.Font(p, UF.LABEL + 1, { cat = "text", key = "red", width = w - 2 * PAD })
    p.head:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -6)
    p.kb = UI.Font(p, UF.LABEL, { cat = "text", key = "normal", width = w - 2 * PAD })
    p.kb:SetPoint("TOPLEFT", p.head, "BOTTOMLEFT", 0, -5)
    p.graphLabel = UI.Font(p, UF.SMALL, { cat = "text", key = "gray", text = "Health over the last 10 seconds" })
    p.graphLabel:SetPoint("TOPLEFT", p.kb, "BOTTOMLEFT", 0, -10)
    p.graphEnd = UI.Font(p, UF.SMALL, { cat = "text", key = "gray", text = "death", justify = "RIGHT" })
    p.graph = UI.Box(p, "ui", "elementBg")
    p.graph:SetHeight(GRAPH_H)
    p.graph:SetPoint("TOPLEFT", p.graphLabel, "BOTTOMLEFT", 0, -3)
    p.graph:SetWidth(w - 2 * PAD)
    p.graph.cols = {}
    p.graphEnd:SetPoint("BOTTOMRIGHT", p.graph, "TOPRIGHT", 0, 3)
    p.graphNote = UI.Font(p.graph, UF.SMALL, { cat = "text", key = "gray", text = "Health not known for this player." })
    p.graphNote:SetPoint("CENTER")
    -- column titles over the list, on the rows' own columns
    local listRight = -(UM.SCROLL_W + 2)
    local function Head(text, justify, width)
        local fs = UI.Font(p, UF.SMALL, { cat = "text", key = "gold", text = text, justify = justify })
        if width then fs:SetWidth(width) end
        return fs
    end
    p.colsHead = Head("When", "RIGHT", 36)
    p.colsHead:SetPoint("TOPLEFT", p.graph, "BOTTOMLEFT", 0, -8)
    p.colsWhat = Head("Hit or heal", "LEFT")
    p.colsWhat:SetPoint("TOPLEFT", p.graph, "BOTTOMLEFT", 60, -8)
    p.colsRight = Head("Health", "RIGHT", 40)
    p.colsRight:SetPoint("TOPRIGHT", p.graph, "BOTTOMRIGHT", listRight, -8)
    p.colsAmt = Head("Amount", "RIGHT", 70)
    p.colsAmt:SetPoint("TOPRIGHT", p.graph, "BOTTOMRIGHT", listRight - 40, -8)
    local sa, child, bar = UI.ScrollArea(p)
    sa:SetPoint("TOPLEFT", p.colsHead, "BOTTOMLEFT", 0, -4)
    sa:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -(PAD + UM.SCROLL_W + 2), 24)
    bar:SetPoint("TOPLEFT", sa, "TOPRIGHT", 2, 0)
    bar:SetPoint("BOTTOMLEFT", sa, "BOTTOMRIGHT", 2, 0)
    child:SetWidth(p.innerW)
    p.scroll, p.child = sa, child
    p.foot = UI.Font(p, UF.SMALL, { cat = "text", key = "gray", width = w - 2 * PAD })
    p.foot:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", PAD, 6)
    p.note = UI.Font(p, UF.LABEL, { cat = "text", key = "gray", width = w - 2 * PAD })
    p.note:SetPoint("TOPLEFT", p.kb, "BOTTOMLEFT", 0, -10)
    p.note:Hide()

    -- the parts that only show with a log
    local logParts = { p.graphLabel, p.graphEnd, p.graph, p.colsHead, p.colsWhat, p.colsAmt, p.colsRight, sa, p.foot }
    local function ShowLog(on)
        for _, x in ipairs(logParts) do if on then x:Show() else x:Hide() end end
        if not on then bar:Hide() end
        if on then p.note:Hide() else p.note:Show() end
    end

    -- No log to show: the player, a heading and why (Forever, a reload).
    function p:SetNote(who, headline, why)
        ShowLog(false)
        self.head:SetText(headline or ((who or "?") .. " died"))
        self.kb:SetText("")
        self.note:SetText(why or "")
    end

    -- One death. Returns its summary (what the report words).
    function p:SetDeath(dt, who, withFight)
        local s = Meter.DeathSummary(dt)
        local evs = Meter.DeathEvents(dt)
        local when = Meter.Clock(dt.deadAt) .. " into the pull"
        if withFight and dt.fight then when = when .. " on " .. dt.fight end
        local clock = ClockOf(dt)
        local headline = (who or dt.name or "?") .. " died " .. when .. (clock and ("  " .. Gray("(" .. clock .. ")")) or "")
        if not s.seen then
            self:SetNote(who, headline,
                "The meter saw none of the hits before this death: they were out of range, or joined the fight late.")
            return s
        end
        ShowLog(true)
        self.head:SetText(headline)
        local kb = Meter.KillingBlowText(s, function(id) return DeathSpell(dt, id) end)
        self.kb:SetText(kb and ((s.sure and "Killed by " or "Last hit seen: ") .. kb
            .. (s.sure and "" or ("  " .. Gray(Meter.PARTLY_SEEN_NOTE))))
            or "No hit seen; only heals reached the log.")
        local drawn = DrawGraph(self.graph, dt, evs, s.hpKnown)
        if drawn then self.graphNote:Hide() else self.graphNote:Show() end
        local kbAt
        for i, e in ipairs(evs) do if e.dmg then kbAt = i break end end
        for i, e in ipairs(evs) do
            local r = RecapRow(self, i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -(i - 1) * ROW_H)
            r:SetWidth(self.innerW)
            r.t:SetText(format("-%.1fs", e.ago))
            local tex = SpellIcon(e.spell)
            r.icon:SetTexture(tex)
            if tex then r.icon:Show() else r.icon:Hide() end
            r.name:SetText(DeathSpell(dt, e.spell))
            r.src:SetText(e.src or "")
            local amt = (e.dmg and "-" or "+") .. Meter.Comma(e.amt) .. (e.crit and " crit" or "")
            if e.over > 0 then amt = amt .. Gray(" (" .. Meter.Comma(e.over) .. " over)") end
            r.amt:SetText(amt)
            local c = GetColor("text", e.dmg and "red" or "green")
            r.amt:SetTextColor(c.r, c.g, c.b)
            r.hp:SetText((s.hpKnown and type(e.hp) == "number") and (floor(e.hp * 100 + 0.5) .. "%") or "")
            if i == kbAt then
                local a = GetColor("ui", "accent")
                r.mark:SetColorTexture(a.r, a.g, a.b, 0.14)
                r.mark:Show()
            else
                r.mark:Hide()
            end
            r:Show()
        end
        for i = #evs + 1, #self.rows do self.rows[i]:Hide() end
        local listH = math.max(1, #evs * ROW_H)
        self.child:SetHeight(listH)
        if self.scroll.Recalculate then self.scroll:Recalculate(listH) end
        self.foot:SetText(format("Last 5 seconds: took %s damage, healed %s.", Meter.Comma(s.took5), Meter.Comma(s.healed5)))
        self.shownRows = #evs
        return s
    end
    return p
end

local recap

local function ShowRecap(f)
    local dt = f.deaths[f.index]
    if dt then
        local s = f.panel:SetDeath(dt, f.who, f.withFight)
        f.sentence = Meter.DeathSentence(s, f.who, function(id) return DeathSpell(dt, id) end, true, 250)
        f.report:SetDisabled(false)
    else
        local n = f.counted or 0
        f.panel:SetNote(f.who, format("%s died %d time%s", f.who, n, n == 1 and "" or "s"),
            f.countsOnly and Meter.FOREVER_DEATH_NOTE or "The meter kept no log of these deaths (from before a reload).")
        f.sentence = nil
        f.report:SetDisabled(true)
    end
    local many = #f.deaths > 1
    f.navText:SetText(many and format("Death %d of %d, newest first", f.index, #f.deaths) or "")
    for _, b in ipairs({ f.prev, f.next }) do if many then b:Show() else b:Hide() end end
    if many then
        f.prev:SetDisabled(f.index >= #f.deaths)
        f.next:SetDisabled(f.index <= 1)
    end
end

local function BuildRecap()
    local f = UI.Window("ZacUIMeterDeathRecap", RECAP_W, RECAP_H, "Death recap")
    local top = f.headerHeight or UM.TITLEBAR
    f.prev = UI.Button(f, "<", { width = 24, tooltip = "An earlier death" })
    f.prev:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(top + 6))
    f.next = UI.Button(f, ">", { width = 24, tooltip = "A later death" })
    f.next:SetPoint("LEFT", f.prev, "RIGHT", 4, 0)
    f.navText = UI.Font(f, UF.SMALL, { cat = "text", key = "gray" })
    f.navText:SetPoint("LEFT", f.next, "RIGHT", 8, 0)
    f.prev:SetScript("OnClick", function() if f.index < #f.deaths then f.index = f.index + 1 ShowRecap(f) end end)
    f.next:SetScript("OnClick", function() if f.index > 1 then f.index = f.index - 1 ShowRecap(f) end end)
    f.panel = Meter.NewRecapPanel(f, RECAP_W, RECAP_H - top - 34 - 34)
    f.panel:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(top + 32))
    f.report = UI.Button(f, "Report to chat", { width = 120,
        tooltip = "Sends a short recap to a channel: what killed them and the hits before it." })
    f.report:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 8)
    f.report:SetScript("OnClick", function(self)
        if f.sentence then Meter.OpenReportLines(self, function() return { f.sentence } end) end
    end)
    return f
end

-- a death row's click: that player's newest death, the others a click away
function Meter.OpenDeathRecap(combat, actor, index)
    if not actor then return end
    recap = recap or BuildRecap()
    local f = recap
    f.who = actor.displayName or actor.name
    f.deaths = DeathsOf(combat, actor.name)
    f.counted = actor.dead or #f.deaths
    f.countsOnly = #f.deaths == 0 and CountsOnly(combat)
    f.withFight = combat and combat.overall
    f.index = math.max(1, math.min(index or 1, math.max(1, #f.deaths)))
    -- in the breakdown window's place
    if breakdown then
        local l, t = breakdown:GetLeft(), breakdown:GetTop()
        if l and t then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
        end
        breakdown:Hide()
    end
    ShowRecap(f)
    UI.OpenWindow(f)
    return f
end
function Meter.CloseDeathRecap()
    if recap and recap:IsShown() then recap:Hide() end
end
function Meter.DeathRecapFrame() return recap end

-- ============================================================
-- THE SAMPLE DEATH - a made-up Ebonroc pull, for the settings preview
-- (the tooltip and the recap drawn by the code above). Fresh each time.
-- ============================================================
function Meter.SampleDeath(name)
    local t0 = 1000
    local function E(ago, dmg, spell, amt, hp, src, over, crit)
        return { dmg, spell, amt, t0 - ago, hp, src, over or -1, crit or false, 1 }
    end
    return {
        name = name or "Zac", class = "WARRIOR", time = t0, deadAt = 133, maxHealth = 9200,
        clock = time and (time() - 40) or nil,
        names = { [22539] = "Shadow Flame", [23339] = "Wing Buffet", [10917] = "Flash Heal", [25315] = "Renew" },
        events = {
            E(9.4, true, 1, 1850, 0.78, "Ebonroc"),
            E(8.1, false, 10917, 1420, 0.94, "Pria"),
            E(6.0, true, 1, 2010, 0.72, "Ebonroc"),
            E(4.6, true, 23339, 1240, 0.59, "Ebonroc"),
            E(3.2, true, 1, 3050, 0.25, "Ebonroc", nil, true),
            E(2.0, false, 25315, 310, 0.28, "Pria"),
            E(1.2, true, 1, 1920, 0.07, "Ebonroc"),
            E(0.0, true, 22539, 4210, 0, "Ebonroc", 3560),
        },
    }
end

-- the sample row's tooltip lines: what hovering that death shows
function Meter.SampleDeathTip(name)
    local lines = {}
    local disp = Meter.DISPLAYS.deaths
    Add(lines, disp.desc, nil, { "text", "gray" }, nil, true)
    Gap(lines)
    local more = Meter.DeathTipLines(Meter.SampleDeath(name), lines, 10)
    Gap(lines)
    Add(lines, more > 0 and format("Click for the full recap (%d more hits and heals).", more)
        or "Click for the full recap.", nil, { "text", "gray" })
    return lines
end

-- A tooltip-shaped box that draws a line list (the settings preview's
-- copy of a row tooltip). :SetLines(title, lines) sizes it; returns w, h.
function Meter.NewTipSample(parent)
    local f = UI.Box(parent, "tooltip", "bg", { borderCat = "tooltip", borderKey = "border" })
    f.left, f.right = {}, {}
    function f:SetLines(title, lines)
        local all = { { l = title, lc = { "tooltip", "title" } } }
        for i = 1, math.min(#lines, TIP_MAX_LINES) do all[#all + 1] = lines[i] end
        -- the texts first, and the width the unwrapped lines need
        local w = 160
        for i, ln in ipairs(all) do
            local L = self.left[i]
            if not L then
                L = UI.Font(self, UF.LABEL, { cat = "text", key = "normal" })
                self.left[i] = L
                self.right[i] = UI.Font(self, UF.LABEL, { cat = "text", key = "normal", justify = "RIGHT" })
            end
            local R = self.right[i]
            local lc = ln.lc or { "text", "normal" }
            local a = GetColor(lc[1], lc[2])
            L:SetWidth(0)
            L:SetWordWrap(false)
            L:SetText(ln.l or "")
            L:SetTextColor(a.r, a.g, a.b)
            L:Show()
            local lw = L:GetStringWidth() or 0
            if ln.r then
                local rc = ln.rc or lc
                local b = GetColor(rc[1], rc[2])
                R:SetText(ln.r)
                R:SetTextColor(b.r, b.g, b.b)
                R:Show()
                lw = lw + 16 + (R:GetStringWidth() or 0)
            else
                R:Hide()
            end
            if not ln.wrap and lw > w then w = lw end
        end
        for i = #all + 1, #self.left do self.left[i]:Hide() self.right[i]:Hide() end
        w = math.min(floor(w + 20), 420)
        -- then each line under the last (a wrapped one as tall as it wraps)
        local y = -8
        for i, ln in ipairs(all) do
            local L, R = self.left[i], self.right[i]
            if ln.wrap then
                L:SetWidth(w - 20)
                L:SetWordWrap(true)
            end
            L:ClearAllPoints()
            L:SetPoint("TOPLEFT", self, "TOPLEFT", 10, y)
            if ln.r then
                R:ClearAllPoints()
                R:SetPoint("TOPRIGHT", self, "TOPRIGHT", -10, y)
            end
            y = y - math.max(14, floor((L:GetStringHeight() or 12) + 2.5))
        end
        self:SetSize(w, -y + 6)
        return w, -y + 6
    end
    return f
end
