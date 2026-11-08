-- Meter_Win_Breakdown - what a row is made of, inside the meter window.
-- Click a row and the window's body turns into its breakdown, drawn as
-- the window's own bars: the abilities (icon, name, hits and crit share,
-- total, share) and the targets of a damage or healing row; who hit or
-- healed a player for the taken displays; the spells of overheal, shields
-- and friendly fire; who hit an enemy for Enemy Damage Taken; every
-- interrupt / dispel / broken crowd control / battle res for the counts.
-- A death still opens the death recap window (its health line needs the
-- room), or a short recap in the window when asked.
-- Back: the "<" head, a right-click, Escape, or the same row again. The
-- mode and fight icons keep working and refill the view; the report icon
-- reports the view; the meter's refresh tick refreshes it while it is
-- open, and nothing else runs.
-- Also here: the hover tooltip's look (look.breakdown.hover): ZacUI's
-- plain words (the default), the same bars in a small panel, or off.
-- Part of ZacUI; load order is set by the TOC (after Meter_Win_Frame).
--
-- METER V2, phase 2 (2026-11-07). Built from what the parser already
-- keeps (actor.spells, actor.targets, the misc log); no new reads in
-- combat. The rows are styled by Meter.StyleRow, so the breakdown wears
-- every row setting the meter has.

local ADDON_NAME = ...
-- Zacui_Meter is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

local Meter = ns.Meter
if not (Meter and Meter.winMeta and Meter.Win) then return end

local floor, max, min, format = math.floor, math.max, math.min, string.format
local tsort = table.sort

local winMeta = Meter.winMeta
local Look = Meter.Look

local BD = {}
Meter.Breakdown = BD
BD.MAX_ROWS = 40
local WHEEL_STEP = 3
local TARGETS_MAX = 8

-- look.breakdown = { hover = "tooltip" | "bars" | "off", maxSpells,
-- showTargets, spellTooltip, deathsInWindow, reportLines }; nil = the
-- defaults below
BD.DEFAULTS = { hover = "tooltip", maxSpells = 0, showTargets = true, spellTooltip = true,
    deathsInWindow = false, reportLines = 0 }
local function Opt(key)
    local b = Look().breakdown
    local v
    if type(b) == "table" then v = b[key] end
    if v == nil then return BD.DEFAULTS[key] end
    return v
end
BD.Opt = Opt

-- ============================================================
-- WORDS AND NUMBERS
-- ============================================================
local function ToK()
    return Meter.ToKList[Meter.DB().psAbbrev] or Meter.ToK
end

local function HexOf(cat, key)
    local c = ns.GetColor(cat, key)
    return format("|cff%02x%02x%02x", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5), floor(c.b * 255 + 0.5))
end
local function Gray(t) return HexOf("text", "gray") .. t .. "|r" end

local function SpellLabel(id, fallback)
    if Meter.SpellLabel then return Meter.SpellLabel(id, fallback) end
    return fallback or tostring(id)
end

local MELEE_ICON = "Interface\\Icons\\INV_Sword_04"
local function SpellIcon(id)
    if id == 1 then return MELEE_ICON end
    if id == 2 then return GetSpellTexture and GetSpellTexture(75) or nil end
    if type(id) ~= "number" or (Meter.ENVIRONMENT_NAMES and Meter.ENVIRONMENT_NAMES[id]) then return nil end
    return GetSpellTexture and GetSpellTexture(id) or nil
end

local function Pct(part, whole)
    if not whole or whole <= 0 then return "0%" end
    return format("%.1f%%", part / whole * 100)
end

local function Sorted(map)
    local list = {}
    for k, v in pairs(map or {}) do
        if type(v) == "number" and v >= 1 then list[#list + 1] = { key = k, value = v } end
    end
    tsort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

local function NameOf(actor)
    if Meter.DisplayName then return Meter.DisplayName(actor) end
    return actor.displayName or actor.name
end

-- ============================================================
-- THE VIEW'S CONTENT - a list of entries, built from the fight:
--   { kind = "section", text }
--   { kind = "bar", name, right, value, top, color = {r,g,b}, icon,
--     coords, spell, report }
--   { kind = "line", left, right }
-- The same list paints the rows and makes the report.
-- ============================================================
-- cols: the section's number columns, right to left ("pct", "total",
-- "crit", "hits"); the view lines the bars under it up in them
local function Section(out, text, cols) out[#out + 1] = { kind = "section", text = text, cols = cols } end
local COLS_ABILITIES = { "pct", "total", "crit", "hits" }
local COLS_AMOUNT = { "pct", "total" }
BD.COLS_ABILITIES, BD.COLS_AMOUNT = COLS_ABILITIES, COLS_AMOUNT
local function Line(out, l, r) out[#out + 1] = { kind = "line", left = l or "", right = r or "" } end

local RED = { 0.78, 0.25, 0.22 }
local GREEN = { 0.3, 0.72, 0.36 }

local function ClassColor(class)
    local c = Meter.CLASS_COLORS[class or ""] or Meter.CLASS_COLORS.UNKNOW
    return { c[1], c[2], c[3] }
end

-- the abilities of an actor: every spell, biggest first
local function Abilities(out, actor, total, color, field)
    field = field or "total"
    local list = {}
    for id, sp in pairs(actor.spells or {}) do
        local v = sp[field] or 0
        if v >= 1 then list[#list + 1] = { id = id, sp = sp, v = v } end
    end
    tsort(list, function(a, b) if a.v ~= b.v then return a.v > b.v end return tostring(a.id) < tostring(b.id) end)
    local most = tonumber(Opt("maxSpells")) or 0
    local n = (most >= 1) and min(most, #list) or #list
    local K = ToK()
    local top = list[1] and list[1].v or 1
    for i = 1, n do
        local e = list[i]
        local sp = e.sp
        local label = SpellLabel(e.id, sp.name)
        local hits = sp.counter or 0
        local crit = hits > 0 and ((sp.c_amt or 0) / hits * 100) or 0
        local share = Pct(e.v, total)
        out[#out + 1] = { kind = "bar", name = label .. (field == "total" and Gray(format("  (%d, %.0f%%)", hits, crit)) or ""),
            plain = label, right = K(e.v) .. " (" .. share .. ")", value = e.v, top = top, color = color,
            icon = SpellIcon(e.id), spell = e.id, sp = sp,
            colv = { pct = share, total = K(e.v), hits = field == "total" and tostring(hits) or nil,
                crit = field == "total" and format("%.0f%%", crit) or nil },
            report = label .. " " .. K(e.v) .. " (" .. share .. ")" }
    end
    return n
end

-- name -> amount as bars (targets, who hit whom)
local function NameBars(out, map, total, colorOf, n)
    local K = ToK()
    local list = Sorted(map)
    local top = list[1] and list[1].value or 1
    for i = 1, min(#list, n or #list) do
        local e = list[i]
        local col, icon, l, r, t, b = colorOf(e.key)
        local share = Pct(e.value, total)
        out[#out + 1] = { kind = "bar", name = tostring(e.key), plain = tostring(e.key), right = K(e.value) .. " (" .. share .. ")",
            value = e.value, top = top, color = col, icon = icon, coords = l and { l, r, t, b } or nil,
            colv = { pct = share, total = K(e.value) },
            report = tostring(e.key) .. " " .. K(e.value) .. " (" .. share .. ")" }
    end
    return #list
end

-- who did `field` to this player: every actor's targets map, read for
-- the name (what the tooltip's "Hit hardest by" reads)
local function FromOthers(cont, name)
    local map = {}
    for _, a in ipairs(cont and cont.actors or {}) do
        if a.name ~= name then
            local v = a.targets and a.targets[name]
            if v and v >= 1 then map[NameOf(a)] = (map[NameOf(a)] or 0) + v end
        end
    end
    return map
end
-- the spells that landed on this player, whoever cast them
local function SpellsOn(cont, name)
    local map, ids = {}, {}
    for _, a in ipairs(cont and cont.actors or {}) do
        if a.name ~= name then
            for id, sp in pairs(a.spells or {}) do
                local v = sp.targets and sp.targets[name]
                if v and v >= 1 then
                    local label = SpellLabel(id, sp.name)
                    map[label] = (map[label] or 0) + v
                    ids[label] = ids[label] or id
                end
            end
        end
    end
    return map, ids
end

local function ActorIndex(cont)
    local by = {}
    for _, a in ipairs(cont and cont.actors or {}) do by[NameOf(a)] = a end
    return by
end

local function Neutral() return { 0.55, 0.55, 0.6 } end

-- the content of `display` for the actor named `name` in `combat`
function BD.Entries(combat, display, name)
    local out = {}
    local disp = Meter.DISPLAYS[display]
    if not (disp and combat) then Line(out, "Nothing to show.") return out, nil end
    local cont = combat[disp.container]
    local actor = cont and cont.Get and cont:Get(name) or (cont and cont.index and cont.index[name])
    if not actor and cont and cont.actors then
        -- a made-up fight (the settings preview) has no index
        for _, a in ipairs(cont.actors) do if a.name == name then actor = a break end end
    end
    if not actor then
        Line(out, format("Nothing for %s in this fight.", name))
        return out, nil
    end
    local K = ToK()
    local kind = Meter.MISC_KIND and Meter.MISC_KIND[display]
    if kind then
        local list = Meter.MiscOf and Meter.MiscOf(combat, actor.name, kind) or {}
        if #list == 0 then
            Line(out, (combat.fromGameMeter or Meter.GameMeter) and Meter.FOREVER_MISC_NOTE
                or "No details kept for these (from before a reload).")
        else
            Section(out, format("%d in all, newest first", #list))
            for i = 1, #list do
                local l, r = Meter.MiscLine(list[i], combat.overall)
                Line(out, l, r)
            end
        end
        return out, actor
    end
    if display == "deaths" then
        local deaths = Meter.DeathsOf and Meter.DeathsOf(combat, actor.name) or {}
        if #deaths == 0 then
            Line(out, "No death log kept for this one (out of range, or joined late).")
            return out, actor
        end
        local dt = deaths[1]      -- newest first
        local lines = {}
        if Meter.DeathTipLines then pcall(Meter.DeathTipLines, dt, lines, 8) end
        for _, ln in ipairs(lines) do
            if ln.l and ln.l ~= " " then Line(out, ln.l, ln.r) end
        end
        if #deaths > 1 then Line(out, Gray(format("+%d earlier death%s: the recap window pages them", #deaths - 1, #deaths == 2 and "" or "s"))) end
        return out, actor
    end
    -- the abilities in the player's class colour (the reference's), or the
    -- one colour when the bars are set to it - not "your row" colour: that
    -- marks your row in the list, and here every bar is one player's
    local myColor = ClassColor(actor.class)
    local dl = Look()
    if dl.barColorMode == "custom" and Meter.ColorOf then
        local r, g, b = Meter.ColorOf(dl.barColor, 0.33, 0.6, 0.85, 1)
        myColor = { r, g, b }
    end
    if display == "damage_done" or display == "dps" or display == "heal_done" or display == "hps" then
        local total = (actor.total and actor.total > 0) and actor.total or 1
        Section(out, "Abilities", COLS_ABILITIES)
        if Abilities(out, actor, total, myColor) == 0 then Line(out, Gray("No abilities kept.")) end
        if Opt("showTargets") ~= false and actor.targets and next(actor.targets) then
            Section(out, "Targets", COLS_AMOUNT)
            local heal = display == "heal_done" or display == "hps"
            local idx = heal and ActorIndex(combat.heal) or nil
            NameBars(out, actor.targets, total, function(n)
                if heal then
                    local a = idx[n]
                    if a then return ClassColor(a.class), Meter.ClassIcon and Meter.ClassIcon(a.class) end
                    return GREEN
                end
                return RED
            end, TARGETS_MAX)
        end
    elseif display == "damage_taken" or display == "heal_taken" then
        local heal = display == "heal_taken"
        local c = heal and combat.heal or combat.damage
        local total = (heal and actor.healingTaken or actor.damageTaken) or 0
        local idx = ActorIndex(c)
        Section(out, heal and "Healed most by" or "Hit hardest by", COLS_AMOUNT)
        local n = NameBars(out, FromOthers(c, actor.name), total, function(who)
            local a = idx[who]
            if a and (a.grupo or a.ownerName) then
                local tex, l, r, t, b
                if Meter.ClassIcon then tex, l, r, t, b = Meter.ClassIcon(a.class) end
                return ClassColor(a.class), tex, l, r, t, b
            end
            return heal and GREEN or RED
        end)
        if n == 0 then Line(out, Gray("Nobody kept.")) end
        local spells, ids = SpellsOn(c, actor.name)
        if next(spells) then
            Section(out, heal and "Heals that landed" or "Abilities that hit them", COLS_AMOUNT)
            local list = Sorted(spells)
            local top = list[1] and list[1].value or 1
            for _, e in ipairs(list) do
                local share = Pct(e.value, total)
                out[#out + 1] = { kind = "bar", name = e.key, plain = e.key, right = K(e.value) .. " (" .. share .. ")",
                    value = e.value, top = top, color = heal and GREEN or RED, icon = SpellIcon(ids[e.key]),
                    spell = ids[e.key], colv = { pct = share, total = K(e.value) },
                    report = e.key .. " " .. K(e.value) .. " (" .. share .. ")" }
            end
        end
    elseif display == "overheal" then
        local over = actor.totalOver or 0
        Section(out, Pct(over, (actor.total or 0) + over) .. " of their healing went past full health", COLS_AMOUNT)
        if Abilities(out, actor, over, GREEN, "overheal") == 0 then Line(out, Gray("No overheal kept.")) end
    elseif display == "absorbs" then
        Section(out, "Shields", COLS_AMOUNT)
        if Abilities(out, actor, actor.totalAbsorb or 0, myColor, "absorbed") == 0 then Line(out, Gray("No shields kept.")) end
    elseif display == "friendly_fire" then
        Section(out, "Hit in the group", COLS_AMOUNT)
        if NameBars(out, actor.friendlyFire, actor.friendlyFireTotal or 0, function() return RED end) == 0 then
            Line(out, Gray("Nobody kept."))
        end
    elseif display == "enemy_taken" then
        local total = actor.damageTaken or 0
        Section(out, "Hit by", COLS_AMOUNT)
        local map, idx = {}, {}
        for _, a in ipairs(combat.damage and combat.damage.actors or {}) do
            if (a.grupo or a.ownerName) and a.targets then
                local v = a.targets[actor.name]
                if v and v >= 1 then map[NameOf(a)] = v idx[NameOf(a)] = a end
            end
        end
        if NameBars(out, map, total, function(who)
            local a = idx[who]
            local tex, l, r, t, b
            if a and Meter.ClassIcon then tex, l, r, t, b = Meter.ClassIcon(a.class) end
            return ClassColor(a and a.class), tex, l, r, t, b
        end) == 0 then
            Line(out, Gray("Nobody kept."))
        end
    else
        Line(out, "Nothing more to show for this one.")
    end
    return out, actor
end

-- ============================================================
-- THE VIEW - a layer over the window's body: the head ("< Zac - Damage
-- Done"), then rows painted from the entries
-- ============================================================
local viewCount = 0

local function MakeRow(view, win, i)
    local row = CreateFrame("Button", nil, view)
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
    row.borders = {}
    for k = 1, 4 do row.borders[k] = row:CreateTexture(nil, "BACKGROUND", nil, -8) end
    local iconFrame = CreateFrame("Frame", nil, row.bar)
    iconFrame:SetFrameLevel(row.bar:GetFrameLevel() + 2)
    row.icon = iconFrame:CreateTexture(nil, "OVERLAY", nil, 5)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    if ns.SharpenIcon then ns.SharpenIcon(row.icon) end
    row.leftText = iconFrame:CreateFontString(nil, "OVERLAY")
    row.leftText:SetJustifyH("LEFT")
    row.leftText:SetWordWrap(false)
    row.rightText = iconFrame:CreateFontString(nil, "OVERLAY")
    row.rightText:SetPoint("RIGHT", row.bar, "RIGHT", 0, 0)
    row.rightText:SetJustifyH("RIGHT")
    row.dmf = iconFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    row.dmf:Hide()
    row.win = win
    row.bdRow = true
    if not win.preview then
        row:SetScript("OnClick", function(_, button)
            if button == "RightButton" then BD.Close(win) end
        end)
        row:SetScript("OnEnter", function(self)
            win:ShowToolbar(true)
            local e = self.entry
            if e and e.spell and Opt("spellTooltip") ~= false and type(e.spell) == "number" and e.spell > 2
                and GameTooltip.SetSpellByID then
                GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
                pcall(GameTooltip.SetSpellByID, GameTooltip, e.spell)
                local sp = e.sp
                if sp and (sp.counter or 0) > 0 then
                    local K = ToK()
                    local c = ns.GetColor("tooltip", "body")
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddDoubleLine("Hits", tostring(sp.counter), c.r, c.g, c.b, 1, 1, 1)
                    if (sp.c_amt or 0) > 0 then
                        GameTooltip:AddDoubleLine("Crits", format("%d (%.0f%%)", sp.c_amt, sp.c_amt / sp.counter * 100), c.r, c.g, c.b, 1, 1, 1)
                    end
                    GameTooltip:AddDoubleLine("Average", K(floor((sp.total or 0) / sp.counter)), c.r, c.g, c.b, 1, 1, 1)
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            win:ShowToolbar(false)
            GameTooltip:Hide()
        end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) BD.Scroll(win, delta) end)
    end
    Meter.StyleRow(row)
    row:Hide()
    view.rows[i] = row
    return row
end

-- the old row painter: the "bars" hover tooltip still draws with it
local function PaintRow(row, e, d)
    row.entry = e
    local K = e.kind
    if e.live then
        -- (Meter_Win_Live) the game's own numbers in combat, which may be
        -- hidden: handed to the widgets whole, no maths on them
        local c = e.color or { 0.5, 0.5, 0.5 }
        row.tex:SetVertexColor(c[1], c[2], c[3], tonumber(d.barAlpha) or 1)
        if e.value ~= nil and e.top ~= nil and not ns.Hidden(e.value, e.top) and type(e.value) == "number"
            and type(e.top) == "number" and e.top > 0 then
            row.bar:SetMinMaxValues(0, 100)
            row.bar:SetValue(floor(e.value / e.top * 100))
        elseif e.value ~= nil and e.top ~= nil then
            ns.ShowBar(row.bar, e.value, e.top)
        else
            row.bar:SetMinMaxValues(0, 100)
            row.bar:SetValue(0)
        end
        if not pcall(row.leftText.SetText, row.leftText, e.name) then row.leftText:SetText("") end
        row.leftText:SetTextColor(1, 1, 1, 1)
        if e.rfmt then ns.ShowText(row.rightText, e.rfmt, unpack(e.rargs or {}))
        else row.rightText:SetText(e.right or "") end
        if d.showIcons ~= false then
            if e.icon ~= nil then pcall(row.icon.SetTexture, row.icon, e.icon) ZacUI.Look.CropIcon(row.icon)
            else row.icon:SetTexture(nil) end
        end
        return
    end
    -- a bar painted from hidden values earlier: back to the 0-100 scale
    row.bar:SetMinMaxValues(0, 100)
    if K == "bar" then
        local c = e.color or { 0.5, 0.5, 0.5 }
        row.tex:SetVertexColor(c[1], c[2], c[3], tonumber(d.barAlpha) or 1)
        row.bar:SetValue(floor((e.value or 0) / max(e.top or 1, 0.0001) * 100))
        row.leftText:SetText(e.name or "")
        row.rightText:SetText(e.right or "")
        row.leftText:SetTextColor(1, 1, 1, 1)
    else
        row.bar:SetValue(0)
        if K == "section" then
            local g = ns.GetColor("text", "gold")
            row.leftText:SetText(e.text or "")
            row.leftText:SetTextColor(g.r, g.g, g.b, 1)
            row.rightText:SetText("")
        else
            row.leftText:SetText(e.left or "")
            row.leftText:SetTextColor(1, 1, 1, 1)
            row.rightText:SetText(e.right or "")
        end
    end
    if row.icon:IsShown() or d.showIcons ~= false then
        if e.icon then
            row.icon:SetTexture(e.icon)
            if e.coords then row.icon:SetTexCoord(e.coords[1], e.coords[2], e.coords[3], e.coords[4])
            else ZacUI.Look.CropIcon(row.icon) end
        else
            row.icon:SetTexture(nil)
        end
    end
end

BD.PaintRow = PaintRow

-- ============================================================
-- THE VIEW, REBUILT (2026-11-08). Zac: "the detailed view is still kinda
-- whack and not easy to get info from". It reads as a table now, with the
-- reference meter's breakdown numbers (its rows 18 + 2, an 18-unit spell
-- icon with the fill after it, the label 3 in, white 0.15 one-pixel
-- dividers, targets in #DD3131):
--   * the HEAD (22): the back arrow, who (in their class colour), what
--     (dimmer), and their total at the right - the answer first;
--   * a STATS line (16) under it where the mode has one: per second,
--     active time, hits;
--   * each SECTION a dim caps heading with its column names at the right
--     ("HITS  CRIT  TOTAL  %"), a hairline above it;
--   * each BAR: the spell's icon, the name, then the numbers in COLUMNS,
--     every column right-aligned and as wide as its widest figure, so a
--     column of totals reads straight down; the share dimmer; hits and
--     crit only where the window is wide enough to keep the names whole
--     (they fold away first);
--   * the misc lists (interrupts, dispels...) as plain lines, every other
--     one faintly shaded.
-- One row pool per window (BD.MAX_ROWS), painted on the meter's tick only
-- while the view is open; the widths are measured on that paint, from
-- the figures it shows.
-- ============================================================
local ROW_H, ROW_GAP = 18, 2          -- the reference's bar height and spacing
local HEAD_H, STATS_H = 22, 16
local ICON_W = 18
local LABEL_X = 3
local COL_PAD = 8                     -- room between two columns
local EDGE_R = 6                      -- the last column's room from the right edge
local NAME_MIN = 70                   -- a name keeps this much before hits / crit fold away
local FONT_FIT = 1.15                 -- (the HD font against the reference's face, MATCH_SPEC_1107.md)
local ROW_PT, SMALL_PT, HEAD_PT = 11 * FONT_FIT, 9 * FONT_FIT, 12 * FONT_FIT
local TARGET_RED = { 221 / 255, 49 / 255, 49 / 255 }
local HOVER_A = 0.08                  -- the row under the mouse: white 8%, exactly on the row
local DIM_A = 0.7                     -- the share and the small columns
local COL_LABEL = { pct = "%", total = "Total", crit = "Crit", hits = "Hits" }
BD.ROW_H, BD.ROW_GAP, BD.HEAD_H, BD.STATS_H = ROW_H, ROW_GAP, HEAD_H, STATS_H

local function Accent() return ns.GetColor("ui", "accent") end

-- the view's fonts: the meter's own face and outline, the reference's sizes
local function VFont(fs, size, d)
    d = d or Look()
    local nf = type(d.nameFont) == "table" and d.nameFont or nil
    ns.ApplyFontSpec(fs, { size = size, outline = nf and nf.outline or nil }, Meter.NameFontDefaults(d))
end

local function NewVRow(v, win, i)
    local row = CreateFrame("Button", nil, v)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHeight(ROW_H)
    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_W, ICON_W)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetMinMaxValues(0, 100)
    row.tex = row.bar:CreateTexture(nil, "ARTWORK")
    row.bar:SetStatusBarTexture(row.tex)
    -- the words above the fill
    local tf = CreateFrame("Frame", nil, row)
    tf:SetAllPoints(row)
    tf:SetFrameLevel(row.bar:GetFrameLevel() + 2)
    row.tf = tf
    row.hl = tf:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints(row)
    row.hl:SetColorTexture(1, 1, 1, HOVER_A)
    row.hl:Hide()
    row.div = tf:CreateTexture(nil, "ARTWORK")
    row.div:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.div:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.div:SetHeight(Meter.Pixels and Meter.Pixels(1) or 1)
    if ns.Pixel and ns.Pixel.Edge then pcall(ns.Pixel.Edge, row.div, "TOP", row, 1) end
    row.div:SetColorTexture(1, 1, 1, 0.15)
    row.div:Hide()
    row.leftText = tf:CreateFontString(nil, "OVERLAY")
    row.leftText:SetJustifyH("LEFT")
    row.leftText:SetWordWrap(false)
    row.cols = {}
    for k = 1, 4 do
        local c = tf:CreateFontString(nil, "OVERLAY")
        c:SetJustifyH("RIGHT")
        c:SetWordWrap(false)
        row.cols[k] = c
    end
    row.rightText = row.cols[1]
    row.win = win
    row.bdRow = true
    if not win.preview then
        row:SetScript("OnClick", function(_, button)
            if button == "RightButton" then BD.Close(win) end
        end)
        row:SetScript("OnEnter", function(self)
            win:ShowToolbar(true)
            local e = self.entry
            if e and (e.kind == "bar" or e.kind == "line") then self.hl:Show() end
            if e and e.spell and Opt("spellTooltip") ~= false and type(e.spell) == "number" and e.spell > 2
                and GameTooltip.SetSpellByID then
                GameTooltip:SetOwner(self, "ANCHOR_NONE")
                GameTooltip:ClearAllPoints()
                GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -6, 0)
                pcall(GameTooltip.SetSpellByID, GameTooltip, e.spell)
                local sp = e.sp
                if sp and (sp.counter or 0) > 0 then
                    local K = ToK()
                    local c = ns.GetColor("tooltip", "body")
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddDoubleLine("Hits", tostring(sp.counter), c.r, c.g, c.b, 1, 1, 1)
                    if (sp.c_amt or 0) > 0 then
                        GameTooltip:AddDoubleLine("Crits", format("%d (%.0f%%)", sp.c_amt, sp.c_amt / sp.counter * 100), c.r, c.g, c.b, 1, 1, 1)
                    end
                    GameTooltip:AddDoubleLine("Average", K(floor((sp.total or 0) / sp.counter)), c.r, c.g, c.b, 1, 1, 1)
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:Hide()
            win:ShowToolbar(false)
            GameTooltip:Hide()
        end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta) BD.Scroll(win, delta) end)
    end
    row:Hide()
    v.rows[i] = row
    BD.StyleVRow(row)
    return row
end

-- fonts and the bar's art (on open and on a restyle)
function BD.StyleVRow(row, d)
    d = d or Look()
    row._fk = nil
    VFont(row.leftText, ROW_PT, d)
    for k = 1, 4 do VFont(row.cols[k], ROW_PT, d) end
    row.tex:SetTexture(Meter.BarPath())
    row:SetHeight(ROW_H)
end

local function EnsureView(win)
    if win.bdView then return win.bdView end
    viewCount = viewCount + 1
    local name = (not win.preview) and ("ZacUIMeterBreakdownView" .. viewCount) or nil
    local v = CreateFrame("Frame", name, win.frame)
    v:Hide()        -- before its OnHide exists: hidden = "back to the list"
    v:SetFrameLevel((win.rowframe:GetFrameLevel() or 1) + 4)
    v.rows = {}
    -- the head: back, who, what, their total
    local head = CreateFrame("Button", nil, v)
    head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    head.bg = head:CreateTexture(nil, "BACKGROUND")
    head.bg:SetAllPoints()
    head.back = head:CreateTexture(nil, "ARTWORK")
    head.back:SetTexture((Meter.ICONS or "Interface\\AddOns\\ZacUI\\Media\\Icons\\") .. "back")
    head.back:SetSize(12, 12)
    head.back:SetPoint("LEFT", head, "LEFT", 6, 0)
    head.back:SetAlpha(0.8)
    head.text = head:CreateFontString(nil, "OVERLAY")
    head.text:SetPoint("LEFT", head.back, "RIGHT", 5, 0)
    head.text:SetJustifyH("LEFT")
    head.text:SetWordWrap(false)
    head.mode = head:CreateFontString(nil, "OVERLAY")
    head.mode:SetPoint("LEFT", head.text, "RIGHT", 5, 0)
    head.mode:SetJustifyH("LEFT")
    head.mode:SetWordWrap(false)
    head.total = head:CreateFontString(nil, "OVERLAY")
    head.total:SetPoint("RIGHT", head, "RIGHT", -EDGE_R, 0)
    head.total:SetJustifyH("RIGHT")
    head.total:SetWordWrap(false)
    v.head = head
    v.stats = v:CreateFontString(nil, "OVERLAY")
    v.stats:SetJustifyH("LEFT")
    v.stats:SetWordWrap(false)
    -- measures the figures for the columns (never shown)
    v.measure = v:CreateFontString(nil, "OVERLAY")
    v.measure:Hide()
    if not win.preview then
        head:SetScript("OnClick", function() BD.Close(win) end)
        head:SetScript("OnEnter", function(self)
            win:ShowToolbar(true)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local tc, bc = ns.GetColor("tooltip", "title"), ns.GetColor("tooltip", "body")
            GameTooltip:AddLine("Back", tc.r, tc.g, tc.b)
            GameTooltip:AddLine("Click, right-click or Escape to go back to the list.", bc.r, bc.g, bc.b, true)
            GameTooltip:Show()
        end)
        head:SetScript("OnLeave", function() win:ShowToolbar(false) GameTooltip:Hide() end)
        v:EnableMouse(true)
        v:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then BD.Close(win) end end)
        v:EnableMouseWheel(true)
        v:SetScript("OnMouseWheel", function(_, delta) BD.Scroll(win, delta) end)
        -- Escape: the game hides UISpecialFrames; hidden = back to the list
        if name and type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
        v:SetScript("OnHide", function() if win.bd and not win.bdClosing then BD.Close(win) end end)
    end
    win.bdView = v
    return v
end

-- the view's look: on open and on a restyle
function BD.Style(win)
    local v = win.bdView
    if not v then return end
    local d = Look()
    v:ClearAllPoints()
    v:SetAllPoints(win.rowframe)
    v.head:ClearAllPoints()
    v.head:SetPoint("TOPLEFT", v, "TOPLEFT", 0, 0)
    v.head:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, 0)
    v.head:SetHeight(HEAD_H)
    v.head.bg:SetColorTexture(1, 1, 1, 0.04)
    VFont(v.head.text, HEAD_PT, d)
    VFont(v.head.total, HEAD_PT, d)
    VFont(v.head.mode, ROW_PT, d)
    v.head.mode:SetTextColor(1, 1, 1, 0.55)
    v.head.total:SetTextColor(1, 1, 1, 1)
    VFont(v.stats, SMALL_PT, d)
    v.stats:SetTextColor(1, 1, 1, 0.55)
    v.stats:ClearAllPoints()
    v.stats:SetPoint("TOPLEFT", v, "TOPLEFT", 6, -(HEAD_H + 2))
    v.stats:SetPoint("TOPRIGHT", v, "TOPRIGHT", -EDGE_R, -(HEAD_H + 2))
    VFont(v.measure, ROW_PT, d)
    for _, row in ipairs(v.rows) do BD.StyleVRow(row, d) end
end

local function Measure(v, text, size)
    local m = v.measure
    if size then VFont(m, size) end
    m:SetText(text or "")
    local ok, w = pcall(m.GetStringWidth, m)
    if size then VFont(m, ROW_PT) end
    return (ok and type(w) == "number") and w or 0
end

-- the columns of each section: the widest figure of each, and which
-- ones the width keeps (hits and crit fold away before a name is cut)
local function Columns(v, entries, width)
    local plan, cur = {}, nil
    for i, e in ipairs(entries) do
        if e.kind == "section" then
            cur = { cols = e.cols or {}, w = {}, show = {} }
            for _, k in ipairs(cur.cols) do
                cur.w[k] = Measure(v, COL_LABEL[k] or "", SMALL_PT)
            end
            plan[i] = cur
        elseif e.kind == "bar" and cur and e.colv and not e.live then
            for _, k in ipairs(cur.cols) do
                local t = e.colv[k]
                if t then
                    local w = Measure(v, t)
                    if w > (cur.w[k] or 0) then cur.w[k] = w end
                end
            end
            plan[i] = cur
        end
    end
    -- which columns fit: pct and total always; then crit, then hits while
    -- the name keeps NAME_MIN
    local seen = {}
    for _, p in pairs(plan) do
        if not seen[p] then
            seen[p] = true
            local used = EDGE_R + ICON_W + LABEL_X
            for _, k in ipairs(p.cols) do
                local cw = (p.w[k] or 0) + COL_PAD
                if k == "pct" or k == "total" or (width - used - cw) >= NAME_MIN then
                    p.show[k] = cw
                    used = used + cw
                else
                    break
                end
            end
            p.used = used
        end
    end
    return plan
end
BD.Columns = Columns

local function PlaceCols(row, cols, show)
    local x = -EDGE_R
    local n = 0
    for _, k in ipairs(cols) do
        local cw = show[k]
        if not cw then break end
        n = n + 1
        local c = row.cols[n]
        c:ClearAllPoints()
        c:SetPoint("RIGHT", row, "RIGHT", x, 0)
        c:SetWidth(cw - COL_PAD + 1)
        c.key = k
        x = x - cw
    end
    for k = n + 1, 4 do row.cols[k]:SetText("") row.cols[k].key = nil end
    return n, x
end

local function Paint(row, e, d, plan, zebra)
    row.entry = e
    local K = e.kind
    row.bar:SetMinMaxValues(0, 100)
    row.div:Hide()
    row.hl:Hide()
    row.leftText:ClearAllPoints()
    if K == "section" then
        -- a dim caps heading, the column names at the right, a hairline above
        row.track:SetColorTexture(0, 0, 0, 0)
        row.icon:Hide()
        row.bar:Hide()
        row.div:SetShown(row.notFirst == true)
        local a = Accent()
        if row._fk ~= "s" then
            row._fk = "s"
            VFont(row.leftText, SMALL_PT, d)
            for k = 1, 4 do VFont(row.cols[k], SMALL_PT, d) end
        end
        row.leftText:SetText(tostring(e.text or ""):upper())
        row.leftText:SetTextColor(a.r, a.g, a.b, 0.9)
        local n, x = PlaceCols(row, e.cols or {}, plan and plan.show or {})
        for k = 1, n do
            local c = row.cols[k]
            c:SetText((COL_LABEL[c.key] or ""):upper())
            c:SetTextColor(1, 1, 1, 0.45)
        end
        row.leftText:SetPoint("LEFT", row, "LEFT", LABEL_X, 0)
        row.leftText:SetPoint("RIGHT", row, "RIGHT", x - 4, 0)
        return
    end
    if row._fk ~= "r" then
        row._fk = "r"
        VFont(row.leftText, ROW_PT, d)
        for k = 1, 4 do VFont(row.cols[k], ROW_PT, d) end
    end
    row.leftText:SetTextColor(1, 1, 1, 1)
    if K == "line" then
        row.track:SetColorTexture(1, 1, 1, zebra and 0.03 or 0)
        row.icon:Hide()
        row.bar:Hide()
        row.leftText:SetText(e.left or "")
        local c = row.cols[1]
        c:ClearAllPoints()
        c:SetPoint("RIGHT", row, "RIGHT", -EDGE_R, 0)
        c:SetWidth(0)
        c:SetText(e.right or "")
        c:SetTextColor(1, 1, 1, DIM_A)
        for k = 2, 4 do row.cols[k]:SetText("") end
        row.leftText:SetPoint("LEFT", row, "LEFT", LABEL_X, 0)
        row.leftText:SetPoint("RIGHT", c, "LEFT", -6, 0)
        return
    end
    -- a bar: the icon, the fill after it over a dark track, the name, the columns
    -- (an ability always keeps its icon's place, so the names line up: the
    -- game's question mark where a spell has no icon)
    local icon = e.icon
    if icon == nil and e.spell ~= nil and not e.live then icon = "Interface\\Icons\\INV_Misc_QuestionMark" end
    local iw = 0
    if icon ~= nil then
        local ok = pcall(row.icon.SetTexture, row.icon, icon)
        if ok then
            if e.coords then row.icon:SetTexCoord(e.coords[1], e.coords[2], e.coords[3], e.coords[4])
            elseif ns.Look and ns.Look.CropIcon then ns.Look.CropIcon(row.icon) end
            row.icon:Show()
            iw = ICON_W
        else
            row.icon:Hide()
        end
    else
        row.icon:Hide()
    end
    row.bar:ClearAllPoints()
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", iw, 0)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.bar:Show()
    row.track:ClearAllPoints()
    row.track:SetPoint("TOPLEFT", row, "TOPLEFT", iw, 0)
    row.track:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.track:SetColorTexture(Meter.RowBgColor(d))
    local c = e.color or { 0.5, 0.5, 0.5 }
    row.tex:SetVertexColor(c[1], c[2], c[3], tonumber(d.barAlpha) or 1)
    if e.live then
        -- (Meter_Win_Live) the game's own numbers in a fight, which may be
        -- hidden: handed to the widgets whole, no maths on them
        if e.value ~= nil and e.top ~= nil and not ns.Hidden(e.value, e.top) and type(e.value) == "number"
            and type(e.top) == "number" and e.top > 0 then
            row.bar:SetValue(floor(e.value / e.top * 100))
        elseif e.value ~= nil and e.top ~= nil then
            ns.ShowBar(row.bar, e.value, e.top)
        else
            row.bar:SetValue(0)
        end
        if not pcall(row.leftText.SetText, row.leftText, e.name) then row.leftText:SetText("") end
        local rc = row.cols[1]
        rc:ClearAllPoints()
        rc:SetPoint("RIGHT", row, "RIGHT", -EDGE_R, 0)
        rc:SetWidth(0)
        rc:SetTextColor(1, 1, 1, 1)
        if e.rfmt then ns.ShowText(rc, e.rfmt, unpack(e.rargs or {})) else rc:SetText(e.right or "") end
        for k = 2, 4 do row.cols[k]:SetText("") end
        row.leftText:SetPoint("LEFT", row.bar, "LEFT", LABEL_X, 0)
        row.leftText:SetPoint("RIGHT", row, "RIGHT", -70, 0)
        return
    end
    row.bar:SetValue(floor((e.value or 0) / max(e.top or 1, 0.0001) * 100))
    row.leftText:SetText(e.plain or e.name or "")
    local cols = plan and plan.cols or { "pct" }
    local show = plan and plan.show or { pct = 60 }
    local n, x = PlaceCols(row, cols, show)
    for k = 1, n do
        local col = row.cols[k]
        local key = col.key
        local t = e.colv and e.colv[key]
        if t == nil and key == "pct" and not e.colv then t = e.right end
        col:SetText(t or "")
        col:SetTextColor(1, 1, 1, key == "total" and 1 or DIM_A)
    end
    row.leftText:SetPoint("LEFT", row.bar, "LEFT", LABEL_X, 0)
    row.leftText:SetPoint("RIGHT", row, "RIGHT", x - 2, 0)
end
BD.PaintView = Paint

-- the head's numbers: who, what, the total; the stats line under it
local function HeadNumbers(win, combat, display, actor)
    local disp = Meter.DISPLAYS[display]
    if not (disp and actor and disp.value) then return nil, nil end
    local ct = (combat and combat.GetCombatTime and combat:GetCombatTime()) or 0
    if ct <= 0 then ct = 1 end
    if disp.prepare then pcall(disp.prepare, actor, combat, ct) end
    local okV, v = pcall(disp.value, actor, combat, ct)
    if not okV or type(v) ~= "number" then return nil, nil end
    local K = ToK()
    local total = disp.count and tostring(floor(v + 0.5)) or K(v)
    local parts = {}
    if disp.ps and not disp.single then
        local okP, ps = pcall(disp.ps, actor, combat, ct)
        if okP and type(ps) == "number" and ps == ps and ps < math.huge then parts[#parts + 1] = K(ps) .. " per sec" end
    end
    if actor.ActivityTime and (display == "damage_done" or display == "dps" or display == "heal_done" or display == "hps") then
        local okA, at = pcall(actor.ActivityTime, actor)
        if okA and type(at) == "number" and at > 0 and Meter.Clock then parts[#parts + 1] = Meter.Clock(at) .. " active" end
    end
    if actor.spells and (display == "damage_done" or display == "dps" or display == "heal_done" or display == "hps") then
        local hits = 0
        for _, sp in pairs(actor.spells) do hits = hits + (sp.counter or 0) end
        if hits > 0 then parts[#parts + 1] = hits .. (hits == 1 and " hit" or " hits") end
    end
    return total, (#parts > 0) and table.concat(parts, "  \194\183  ") or nil
end
BD.HeadNumbers = HeadNumbers

-- how many rows fit under the head (and the stats line when it shows)
local function Fit(win, stats)
    local hgt = (win.rowframe and win.rowframe:GetHeight()) or 0
    local top = HEAD_H + (stats and STATS_H or 0) + 2
    return max(0, min(BD.MAX_ROWS, floor((hgt - top + ROW_GAP) / (ROW_H + ROW_GAP)))), top
end

-- fill the view from the window's fight and mode
function BD.Refresh(win)
    local st = win.bd
    if not st then return end
    local v = EnsureView(win)
    local d = Look()
    local display = win.settings.display
    if display == "threat" or not Meter.DISPLAYS[display] then BD.Close(win) return end
    local entries, actor
    local Live = Meter.Live
    local combat = Meter.CombatForWindow(win)
    if Live and Live.Owns(win) then
        entries, actor = Live.Entries(win, st)
    else
        entries, actor = BD.Entries(combat, display, st.name)
    end
    st.entries = entries
    local disp = Meter.DISPLAYS[display]
    local who = actor and NameOf(actor) or st.label or st.name
    st.label = who
    -- the head
    local cc = actor and Meter.CLASS_COLORS[actor.class or ""]
    v.head.text:SetText(who)
    if cc then v.head.text:SetTextColor(cc[1], cc[2], cc[3], 1) else v.head.text:SetTextColor(1, 1, 1, 1) end
    v.head.mode:SetText(disp and disp.label or "")
    local total, stats
    if actor then total, stats = HeadNumbers(win, combat, display, actor) end
    v.head.total:SetText(total or "")
    -- the name and mode give way to the total
    local hw = (v.head:GetWidth() or 0)
    if hw > 0 then
        local tw = total and (Measure(v, total, HEAD_PT) + 8) or 0
        local room = hw - 6 - 12 - 5 - EDGE_R - tw
        local nw = Measure(v, who, HEAD_PT)
        if nw > room then v.head.text:SetWidth(max(10, room)) v.head.mode:Hide()
        else
            v.head.text:SetWidth(nw + 1)
            local mw = Measure(v, disp and disp.label or "")
            v.head.mode:SetShown(nw + 5 + mw <= room)
        end
    end
    v.stats:SetText(stats or "")
    v.stats:SetShown(stats ~= nil)
    local fit, top = Fit(win, stats ~= nil)
    st.fit = fit
    st.scrollMax = max(0, #entries - fit)
    if (st.scroll or 0) > st.scrollMax then st.scroll = st.scrollMax end
    local offset = st.scroll or 0
    local width = (win.rowframe and win.rowframe:GetWidth()) or (win.frame:GetWidth() or 200)
    local plan = Columns(v, entries, width)
    local pitch = ROW_H + ROW_GAP
    local zebra, firstSection = false, true
    for i = 1, max(fit, #v.rows) do
        local row = v.rows[i] or (i <= fit and NewVRow(v, win, i)) or nil
        if row then
            local idx = i + offset
            local e = (i <= fit) and entries[idx] or nil
            if e then
                row:ClearAllPoints()
                local y = -(top + (i - 1) * pitch)
                row:SetPoint("TOPLEFT", v, "TOPLEFT", 0, y)
                row:SetPoint("TOPRIGHT", v, "TOPRIGHT", 0, y)
                row.notFirst = (idx > 1)
                if e.kind == "section" then zebra = false end
                if e.kind == "line" then zebra = not zebra end
                Paint(row, e, d, plan[idx], zebra)
                row:Show()
            else
                row.entry = nil
                row:Hide()
            end
        end
    end
    if Meter.UpdateTitle then Meter.UpdateTitle(win) end
end

function BD.Scroll(win, delta)
    local st = win.bd
    if not st then return end
    local before = st.scroll or 0
    local after = before - delta * WHEEL_STEP
    if after < 0 then after = 0 end
    if after > (st.scrollMax or 0) then after = st.scrollMax or 0 end
    if after == before then return end
    st.scroll = after
    BD.Refresh(win)
end

function BD.IsOpen(win) return win.bd ~= nil end

-- open the view with its state: { name, label, scroll, ... }
function BD.Show(win, st)
    if not (win and st and win.rowframe) then return end
    win.bd = st
    st.scroll = st.scroll or 0
    local v = EnsureView(win)
    BD.Style(win)
    GameTooltip:Hide()
    win.rowframe:Hide()
    v:Show()
    BD.Refresh(win)
end

function BD.Open(win, actor)
    if not (win and actor and win.rowframe) then return end
    local st = win.bd
    -- the same row again: back
    if st and st.name == actor.name then BD.Close(win) return end
    BD.Show(win, { name = actor.name, label = NameOf(actor), scroll = 0 })
end

function BD.Close(win)
    if not win.bd then return end
    win.bd = nil
    local v = win.bdView
    if v and v:IsShown() then
        win.bdClosing = true
        v:Hide()
        win.bdClosing = nil
    end
    win.rowframe:Show()
    Meter.RefreshWindow(win, true)
    if Meter.UpdateTitle then Meter.UpdateTitle(win) end
end

-- the view as chat lines: "ZacUI: Zac - Damage Done" then the first
-- list's rows ("1. Bloodthirst 123.4K (31.2%)"), as many as asked
function BD.ReportLines(win)
    local st = win.bd
    if not (st and st.entries) then return nil end
    local disp = Meter.DISPLAYS[win.settings.display]
    local seg = win.settings.segment or 0
    local head = "ZacUI: " .. (st.label or st.name) .. " - " .. (disp and disp.label or "")
    if seg == -1 then head = head .. " (overall)"
    elseif seg > 0 and Meter.segments[seg] then head = head .. " (" .. Meter.segments[seg]:Name() .. ")" end
    local lines = { head }
    local most = tonumber(Opt("reportLines")) or 0
    if most < 1 then most = Meter.DB().reportLines or 5 end
    local n, started = 0, false
    for _, e in ipairs(st.entries) do
        if e.kind == "section" then
            if started then break end
        elseif e.kind == "bar" then
            started = true
            n = n + 1
            if n > most then break end
            lines[#lines + 1] = n .. ". " .. (e.report or e.plain or "")
        elseif e.kind == "line" and not started then
            local plain = tostring(e.left or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t ?", "")
            local pr = tostring(e.right or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t ?", "")
            n = n + 1
            if n > most then break end
            lines[#lines + 1] = n .. ". " .. plain .. (pr ~= "" and (" " .. pr) or "")
        end
    end
    if #lines == 1 then return nil end
    return lines
end

-- ============================================================
-- THE WINDOW'S OTHER CONTROLS WHILE A BREAKDOWN IS OPEN
-- ============================================================
-- a new mode refills the view for the same player; threat, and deaths
-- when they open the recap window, go back to the list
local origSetDisplay = winMeta.SetDisplay
function winMeta:SetDisplay(key)
    if self.bd then
        if key == "threat" or (key == "deaths" and not Opt("deathsInWindow")) then
            BD.Close(self)
        else
            self.bd.scroll = 0
        end
    end
    return origSetDisplay(self, key)
end

local origToolbar = winMeta.ToolbarClick
function winMeta:ToolbarClick(key, button)
    if self.bd and key == "report" and not self.preview then
        if Meter.OpenReportLines then Meter.OpenReportLines(self.frame, function() return BD.ReportLines(self) end) end
        return
    end
    return origToolbar(self, key, button)
end

-- a closed / parked window takes its breakdown with it
local origClose = winMeta.Close
function winMeta:Close()
    if self.bd then BD.Close(self) end
    return origClose(self)
end

-- every restyle restyles an open view
local origRestyle = Meter.RestyleAll
Meter.RestyleAll = function(...)
    for _, win in ipairs(Meter.windowFrames) do
        if win.bdView then BD.Style(win) end
    end
    local r = origRestyle(...)
    for _, win in ipairs(Meter.windowFrames) do
        if win.bd then BD.Refresh(win) end
    end
    return r
end
Meter.RestyleMedia = Meter.RestyleAll

-- ============================================================
-- THE HOVER TOOLTIP'S LOOK (look.breakdown.hover)
--   "tooltip" - ZacUI's plain words on the game's tooltip (Meter_Info)
--   "bars"    - the abilities as bars in a small panel by the row (the
--               plain words stay for the displays that are words)
--   "off"     - nothing on hover
-- ============================================================
local tip
local function BuildTip()
    local f = CreateFrame("Frame", "ZacUIMeterBarsTip", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
    if ns.AddPixelBorder then ns.AddPixelBorder(f) end
    f.fake = { id = -1, preview = true, frame = f, rowframe = f, settings = {} }
    f.rows = {}
    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -3)
    f:Hide()
    return f
end

local BAR_DISPLAYS = { damage_done = true, dps = true, heal_done = true, hps = true }
BD.TIP_ROWS = 8

function BD.ShowBarsTip(row, win)
    local actor = row.actor
    if not actor then return false end
    local display = win.settings.display
    if not BAR_DISPLAYS[display] then return false end
    tip = tip or BuildTip()
    local d = Look()
    local combat = row.combat or Meter.CombatForWindow(win)
    local entries = BD.Entries(combat, display, actor.name)
    local w = max(160, (win.frame:GetWidth() or 200))
    local rh = max(10, d.rowHeight - 4)
    local pitch = rh + 1
    ns.ApplyFontSpec(tip.title, d.nameFont, Meter.NameFontDefaults(d))
    local disp = Meter.DISPLAYS[display]
    tip.title:SetText(NameOf(actor) .. "  -  " .. (disp and disp.label or ""))
    local n = 0
    for _, e in ipairs(entries) do
        if e.kind == "bar" then
            n = n + 1
            if n > BD.TIP_ROWS then break end
            local r = tip.rows[n] or MakeRow(tip, tip.fake, n)
            r:SetHeight(rh)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", tip, "TOPLEFT", 2, -(4 + 14 + (n - 1) * pitch))
            r:SetPoint("TOPRIGHT", tip, "TOPRIGHT", -2, -(4 + 14 + (n - 1) * pitch))
            PaintRow(r, e, d)
            r:Show()
        elseif e.kind == "section" and n > 0 then
            break
        end
    end
    for i = n + 1, #tip.rows do tip.rows[i]:Hide() end
    if n == 0 then tip:Hide() return false end
    n = min(n, BD.TIP_ROWS)
    tip:SetSize(w, 4 + 14 + n * pitch + 3)
    tip:ClearAllPoints()
    tip:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 4)
    tip:SetScale(win.frame:GetScale() or 1)
    tip.owner = row
    tip:Show()
    if not row.bdTipHooked and row.HookScript then
        row.bdTipHooked = true
        row:HookScript("OnLeave", function() if tip and tip.owner == row then tip:Hide() tip.owner = nil end end)
    end
    return true
end
function BD.TipFrame() return tip end

local origTooltip = Meter.RowTooltip
Meter.RowTooltip = function(row, win)
    local mode = Opt("hover")
    if mode == "off" then return end
    if mode == "bars" and BD.ShowBarsTip(row, win) then return end
    return origTooltip(row, win)
end
