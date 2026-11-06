-- BR_Tracker - who needs your buff: the party (Battle Shout, Trueshot
-- Aura) or the whole raid by group (everything you can cast on others),
-- with the time left on each, who is out of range, the efficient cast
-- and the reagent count, and a click on a row or a group to cast it.
-- Part of ZacUI; load order is set by the TOC.
--
-- The frame is Readycheck's Battle Shout party tracker, ported: the same
-- header (icon + title), the same rows (name in its class colour, status
-- on the right - "290 AP", the time, MISSING / OOR - a duration bar behind
-- it, the Bloodrage icon), the same sizes, colours, layout family, fonts
-- and formats. A warrior's tracker reads exactly as Readycheck's did.
-- What it adds, for the buffs you cast on others:
--   a GROUP row per raid group that needs it ("Group 3   3 missing"),
--     with the cast to use as its icon: the group buff (Gift of the Wild,
--     Arcane Brilliance, a Prayer) once `groupAt` or more of the group
--     need it and you have the reagent, else the single rank;
--   a member row under it for each who needs it (missing, low, OOR);
--   a REAGENT row (Wild Thornroot  37), warning colour when it runs low
--     (tracker.reagentLow) and a line in chat when it first does;
--   a section row per buff when more than one is listed.
--
-- CLICK TO CAST. A row's click is a SecureActionButton laid over it (the
-- spell, or the Soulstone item, on that unit; a group row: the group buff
-- on someone of that group in range). They hang off UIParent, not the
-- tracker, so the tracker itself never becomes protected and keeps its
-- animations; they are placed out of combat only, and a state driver
-- puts the whole layer away the moment a fight starts.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local BR = ns.BuffRem
if not BR then return end
local D = BR.Data

local T = {}
BR.TrackerUI = T

local FLAT = ns.FLAT or "Interface\\Buttons\\WHITE8X8"
local math_floor, math_max, math_min = math.floor, math.max, math.min

local MAX_ROWS = 60
local NONE = { style = "none" }
T.NAME_FORMAT = { maxLen = 13, mark = "." }
T.TIME_FORMAT = { time = "clock" }
T.SORTS = {
    { value = "name", text = "Name" }, { value = "time", text = "Time left" },
    { value = "status", text = "Missing first" },
}
local ROW_SORTS = {
    name = function(a, b) return (a.name or "") < (b.name or "") end,
    time = function(a, b)
        local ra = a.hasBuff and a.remaining or -1
        local rb = b.hasBuff and b.remaining or -1
        if ra ~= rb then return ra < rb end
        return (a.name or "") < (b.name or "")
    end,
    status = function(a, b)
        local sa = (not a.hasBuff and 0) or (a.belowThreshold and 1) or 2
        local sb = (not b.hasBuff and 0) or (b.belowThreshold and 1) or 2
        if sa ~= sb then return sa < sb end
        return (a.name or "") < (b.name or "")
    end,
}

-- ============================================================
-- WHERE THE TEXTS AND PARTS SIT (tracker.anchors.<key>)
-- ============================================================
local function SetDef(t, p, to, rp, x, y, j, p2, to2, rp2, x2, y2)
    t.point, t.to, t.relPoint, t.x, t.y, t.justify = p, to, rp, x, y, j
    t.point2, t.to2, t.relPoint2, t.x2, t.y2 = p2, to2, rp2, x2, y2
    return t
end
T.TITLE_ICON_DEF = { point = "LEFT", relPoint = "LEFT", x = 6, y = 1 }
T.STATUS_DEF = { point = "RIGHT", relPoint = "RIGHT", x = -4, y = 0 }
T.ROWICON_DEF = { point = "LEFT", relPoint = "LEFT", x = 3, y = 0 }
local pageDef = {}
function T.AnchorDefaults(key)
    if key == "titleIcon" then return T.TITLE_ICON_DEF end
    if key == "rowStatus" then return T.STATUS_DEF end
    if key == "rowIcon" then return T.ROWICON_DEF end
    if key == "title" then return SetDef(pageDef, "LEFT", nil, "RIGHT", 5, 1, nil, "RIGHT", nil, "RIGHT", -38, 0) end
    if key == "rowName" then return SetDef(pageDef, "LEFT", nil, "LEFT", 4, 0, nil, "RIGHT", nil, "LEFT", -4, 0) end
end
T.TITLE_TARGETS = {
    { value = "frame", text = "The tracker" }, { value = "header", text = "Header bar" },
    { value = "titleIcon", text = "Title icon" }, { value = "title", text = "Title" },
}
T.ROW_TARGETS = {
    { value = "row", text = "The row" }, { value = "name", text = "Name" },
    { value = "status", text = "Status" }, { value = "icon", text = "Row icon" },
}
local function SpecOf(tc, key)
    local a = tc and tc.anchors
    return type(a) == "table" and a[key] or nil
end

local function Font(tc, key)
    local s = tc[key]
    return type(s) == "table" and s or nil
end

-- ============================================================
-- BUILD / STYLE
-- ============================================================
local function NewRow(frame, i)
    local tc = BR.Tracker()
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(tc.rowHeight or 17)
    row:SetPoint("LEFT", frame, "LEFT", 1, 0)
    row:SetPoint("RIGHT", frame, "RIGHT", -1, 0)
    row.rowBg = row:CreateTexture(nil, "BACKGROUND")
    row.rowBg:SetAllPoints()
    local bar = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    bar:SetPoint("LEFT", row, "LEFT", 0, 1)
    bar:SetPoint("TOP", row, "TOP", 0, -1)
    bar:SetPoint("BOTTOM", row, "BOTTOM", 0, 1)
    bar:SetWidth(1)
    bar:Hide()
    row.durationBar = bar
    local nameText = row:CreateFontString(nil, "OVERLAY")
    ns.ApplyFontSpec(nameText, Font(tc, "rowFont"), BR.DEFAULTS.tracker.rowFont)
    nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
    nameText:SetWordWrap(false)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText
    local icon = row:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", row, "LEFT", 3, 0)
    icon:SetTexture("Interface\\Icons\\Ability_Racial_BloodRage")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    row.bloodrageIcon = icon
    local st = row:CreateFontString(nil, "OVERLAY")
    ns.ApplyFontSpec(st, Font(tc, "rowFont"), BR.DEFAULTS.tracker.rowFont)
    st:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    st:SetWidth(72)
    st:SetJustifyH("RIGHT")
    st:SetWordWrap(false)
    row.apText = st
    nameText:SetPoint("RIGHT", st, "LEFT", -4, 0)
    row._to = function(k)
        if k == "row" then return row elseif k == "name" then return nameText
        elseif k == "status" then return st elseif k == "icon" then return icon end
    end
    row._nameDef = {}
    if frame.preview and ns.TagElement then
        ns.TagElement(nameText, "buffrem.rowName") ns.TagElement(st, "buffrem.rowStatus")
        ns.TagElement(icon, "buffrem.rowIcon")
    end
    row:Hide()
    frame.rows[i] = row
    return row
end

-- the frame: header and the first rows; no position, mouse or name
function T.New(parent, preview)
    local tc = BR.Tracker()
    local frame = CreateFrame("Frame", (not preview) and "ZacUIBuffRemTracker" or nil, parent)
    frame.preview = preview
    frame:SetWidth(tc.width or 165)
    frame:SetHeight(26)
    frame.contentBg = frame:CreateTexture(nil, "BACKGROUND")
    frame.contentBg:SetAllPoints()
    frame.simpleBorder = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetTexture(FLAT)
        if side == "top" then t:SetPoint("TOPLEFT") t:SetPoint("TOPRIGHT") t:SetHeight(1)
        elseif side == "bottom" then t:SetPoint("BOTTOMLEFT") t:SetPoint("BOTTOMRIGHT") t:SetHeight(1)
        elseif side == "left" then t:SetPoint("TOPLEFT") t:SetPoint("BOTTOMLEFT") t:SetWidth(1)
        else t:SetPoint("TOPRIGHT") t:SetPoint("BOTTOMRIGHT") t:SetWidth(1) end
        frame.simpleBorder[side] = t
    end
    local hb = CreateFrame("Frame", nil, frame)
    hb:SetHeight(22)
    hb:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    hb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    hb.bg = hb:CreateTexture(nil, "BACKGROUND")
    hb.bg:SetAllPoints()
    hb.bg:SetTexture(FLAT)
    -- the accent rule under the title, as every ZacUI title strip
    hb.rule = hb:CreateTexture(nil, "BORDER")
    hb.rule:SetTexture(FLAT)
    hb.rule:SetPoint("BOTTOMLEFT", hb, "BOTTOMLEFT", 0, 0)
    hb.rule:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 0, 0)
    hb.rule:SetHeight(1)
    local ti = hb:CreateTexture(nil, "OVERLAY")
    ti:SetSize(14, 14)
    ti:SetPoint("LEFT", hb, "LEFT", 6, 1)
    ti:SetTexture("Interface\\Icons\\Ability_Warrior_BattleShout")
    ti:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local tt = hb:CreateFontString(nil, "OVERLAY")
    ns.ApplyFontSpec(tt, Font(tc, "titleFont"), BR.DEFAULTS.tracker.titleFont)
    tt:SetPoint("LEFT", ti, "RIGHT", 5, 1)
    tt:SetPoint("RIGHT", hb, "RIGHT", -38, 0)
    tt:SetJustifyH("LEFT")
    tt:SetWordWrap(false)
    tt:SetText("Battle Shout")
    hb.titleText, hb.titleIcon = tt, ti
    frame.headerBar = hb
    frame._to = function(k)
        if k == "frame" then return frame elseif k == "header" then return hb
        elseif k == "titleIcon" then return ti elseif k == "title" then return tt end
    end
    frame._titleDef, frame._titleIconDef = {}, {}
    if preview and ns.TagElement then
        ns.TagElement(tt, "buffrem.title") ns.TagElement(ti, "buffrem.titleIcon")
    end
    frame.rows = {}
    for i = 1, 25 do NewRow(frame, i) end
    T.Style(frame, tc)
    return frame
end

local function Row(frame, i)
    return frame.rows[i] or NewRow(frame, i)
end

-- fonts, the static colours, the parts' spots
function T.Style(frame, tc)
    tc = tc or BR.Tracker()
    local hb = frame.headerBar
    ns.ApplyFontSpec(hb.titleText, Font(tc, "titleFont"), BR.DEFAULTS.tracker.titleFont)
    ns.ApplyAnchor(hb.titleIcon, SpecOf(tc, "titleIcon"), SetDef(frame._titleIconDef, "LEFT", hb, "LEFT", 6, 1), frame._to)
    ns.ApplyAnchor(hb.titleText, SpecOf(tc, "title"),
        SetDef(frame._titleDef, "LEFT", hb.titleIcon, "RIGHT", 5, 1, nil, "RIGHT", hb, "RIGHT", -38, 0), frame._to)
    local tcol = T.TitleColor(tc)
    hb.titleText:SetTextColor(tcol.r, tcol.g, tcol.b, tcol.a or 1)
    local hc = BR.Color("tracker", "headerBackground")
    hb.bg:SetVertexColor(hc.r, hc.g, hc.b, hc.a or 1)
    local acc = ns.GetColor and ns.GetColor("ui", "accent") or { r = 1, g = 0.82, b = 0 }
    hb.rule:SetVertexColor(acc.r, acc.g, acc.b, 0.8)
    local rowC = BR.Color("tracker", "rowBackground")
    local statusSpec, iconSpec = SpecOf(tc, "rowStatus"), SpecOf(tc, "rowIcon")
    for _, row in ipairs(frame.rows) do
        ns.ApplyFontSpec(row.nameText, Font(tc, "rowFont"), BR.DEFAULTS.tracker.rowFont)
        ns.ApplyFontSpec(row.apText, Font(tc, "rowFont"), BR.DEFAULTS.tracker.rowFont)
        ns.ApplyAnchor(row.apText, statusSpec, T.STATUS_DEF, row._to)
        ns.ApplyAnchor(row.bloodrageIcon, iconSpec, T.ROWICON_DEF, row._to)
        row.rowBg:SetColorTexture(rowC.r, rowC.g, rowC.b, rowC.a or 1)
    end
    frame._styledRows = #frame.rows
    -- layer, shadow / glow (tracker.framePos, tracker.chrome)
    if ns.ApplyChrome and (tc.chrome or frame._zcShadow or frame._zcGlow) then ns.ApplyChrome(frame, tc.chrome) end
end

function T.TitleColor(tc)
    local c = type(tc.colors) == "table" and tc.colors.titleText
    if type(c) == "table" then return c end
    return ns.GetColor and ns.GetColor("text", "gold") or { r = 1, g = 0.82, b = 0, a = 1 }
end

local function FormatDuration(secs)
    if secs == math.huge then return "" end
    if secs <= 0 then return "0s" end
    local m = math_floor(secs / 60)
    local s = math_floor(secs % 60)
    if m > 0 then return string.format("%d:%02d", m, s) end
    return s .. "s"
end
T.FormatDuration = FormatDuration

-- ============================================================
-- LAYOUT: rows onto a frame (the live one and the preview's alike)
-- ============================================================
-- rows: { member rows (Readycheck's fields: name, classToken, hasBuff,
-- remaining, apValue, expirationTime, peakMax, belowThreshold,
-- outOfRange, hasBloodrage) | { kind = "group" | "section" | "reagent",
-- label, status, statusColor ("good"|"warn"|"missing"|nil), icon } }
-- head: { title, icon } for the header
function T.Layout(frame, rows, tc, cache, head)
    tc = tc or BR.Tracker()
    local width = tc.width or 165
    local showBg = tc.showBackground ~= false
    local showHdr = tc.showHeader ~= false
    local durStyle = tc.durationStyle or "bar"
    local trackBR = tc.showBloodrage ~= false
    for i = 1, math_min(#rows, MAX_ROWS) do Row(frame, i) end
    if (frame._styledRows or 0) < #frame.rows then T.Style(frame, tc) end
    for _, row in ipairs(frame.rows) do row:Hide() end
    local hb = frame.headerBar
    if head then
        hb.titleText:SetText(head.title or "")
        if head.icon then hb.titleIcon:SetTexture(head.icon) end
    end

    local rowH = tc.rowHeight or 17
    local headerH = showHdr and 23 or 0
    local topPad, botPad = 2, 2
    local lay = type(tc.layout) == "table" and tc.layout or nil
    local nRows = #rows
    if lay then
        -- the order within each block of member rows (a group's members,
        -- the party): headers stay where they are
        local key = lay.sort
        local cmp = key and ROW_SORTS[key]
        local i = 1
        while i <= nRows do
            if rows[i].kind then i = i + 1 else
                local j = i
                while j + 1 <= nRows and not rows[j + 1].kind do j = j + 1 end
                if cmp and j > i then
                    local block = {}
                    for k = i, j do block[#block + 1] = rows[k] end
                    table.sort(block, cmp)
                    for k = i, j do rows[k] = block[k - i + 1] end
                end
                if lay.reverse then
                    local a, b = i, j
                    while a < b do rows[a], rows[b] = rows[b], rows[a] a, b = a + 1, b - 1 end
                end
                i = j + 1
            end
        end
        local mx = tonumber(lay.max)
        if mx and mx >= 1 and nRows > mx then nRows = mx end
    end
    if nRows > MAX_ROWS then nRows = MAX_ROWS end
    local totalH = headerH + (#rows * rowH) + topPad + botPad
    local laySy, layPad = 0, 0
    if lay then
        laySy, layPad = tonumber(lay.spacingY) or 0, tonumber(lay.padding) or 0
        totalH = headerH + nRows * rowH + math_max(0, nRows - 1) * laySy + topPad + botPad + 2 * layPad
    elseif #rows > MAX_ROWS then
        totalH = headerH + (MAX_ROWS * rowH) + topPad + botPad
    end
    local fm = type(tc.formats) == "table" and tc.formats or nil
    local nameFmt, timeFmt = fm and fm.name, fm and fm.time
    local function Dur(secs)
        if timeFmt and secs ~= math.huge then return ns.FormatTime(secs, timeFmt, T.TIME_FORMAT) end
        return FormatDuration(secs)
    end
    frame:SetWidth(width)
    frame:SetHeight(totalH)

    local opacity = tc.opacity or 0.85
    local bgC = BR.Color("tracker", "background")
    if showBg then frame.contentBg:SetColorTexture(bgC.r, bgC.g, bgC.b, (bgC.a or 1) * opacity)
    else frame.contentBg:SetColorTexture(0, 0, 0, 0) end
    local borC = BR.Color("tracker", "border")
    local ba = showBg and (borC.a or 1) or 0
    local bs = tonumber(tc.borderSize) or 1
    for side, t in pairs(frame.simpleBorder) do
        t:SetColorTexture(borC.r, borC.g, borC.b, bs > 0 and ba or 0)
        if bs > 0 then
            if side == "top" or side == "bottom" then t:SetHeight(bs) else t:SetWidth(bs) end
        end
    end
    hb:SetShown(showHdr)
    hb.bg:SetShown(showBg)
    hb.rule:SetShown(showBg)

    local goodC = BR.Color("tracker", "apGood")
    local warnC = BR.Color("tracker", "apWarning")
    local missC = BR.Color("tracker", "apMissing")
    local brC = BR.Color("tracker", "bloodrageActive")
    local brStyle = tc.bloodrageStyle or "both"
    local brShowIcon = trackBR and (brStyle == "icon" or brStyle == "both")
    local brShowColor = trackBR and (brStyle == "color" or brStyle == "both")
    local barPx = math_max(1, width - 2)
    local barA = tonumber(tc.barAlpha) or 0.45
    local STATUS_COL = { good = goodC, warn = warnC, missing = missC }
    local defC = ns.GetColor and ns.GetColor("text", "normal") or { r = 1, g = 1, b = 1 }
    local gold = ns.GetColor and ns.GetColor("text", "gold") or { r = 1, g = 0.82, b = 0 }

    for i, data in ipairs(rows) do
        if i > (lay and nRows or MAX_ROWS) then break end
        local row = frame.rows[i]
        row.data = data
        row:ClearAllPoints()
        if lay then
            local up = lay.grow == "UP"
            local step = (i - 1) * (rowH + laySy) + layPad
            if up then
                row:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1 + layPad, botPad + step)
                row:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1 - layPad, botPad + step)
            else
                local yOff = -(headerH + topPad + step)
                row:SetPoint("TOPLEFT", frame, "TOPLEFT", 1 + layPad, yOff)
                row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1 - layPad, yOff)
            end
        else
            local yOff = -(headerH + topPad + (i - 1) * rowH)
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, yOff)
            row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, yOff)
        end
        row:SetHeight(rowH)
        row:Show()

        local showIcon, iconTex
        if data.kind then
            iconTex = data.icon
            showIcon = iconTex ~= nil
        else
            showIcon = data.hasBloodrage and brShowIcon
            iconTex = "Interface\\Icons\\Ability_Racial_BloodRage"
        end
        local nd = row._nameDef
        if showIcon then
            local sz = math_max(8, math_min(14, rowH - 4))
            row.bloodrageIcon:SetTexture(iconTex)
            row.bloodrageIcon:SetSize(sz, sz)
            row.bloodrageIcon:Show()
            SetDef(nd, "LEFT", row.bloodrageIcon, "RIGHT", 3, 0, nil, "RIGHT", row.apText, "LEFT", -4, 0)
        else
            row.bloodrageIcon:Hide()
            SetDef(nd, "LEFT", row, "LEFT", 4, 0, nil, "RIGHT", row.apText, "LEFT", -4, 0)
        end
        ns.ApplyAnchor(row.nameText, SpecOf(tc, "rowName"), nd, row._to)

        if data.kind then
            -- a group, section or reagent line: its label and its count
            local lc = (data.kind == "group") and defC or gold
            row.nameText:SetText(data.label or "")
            row.nameText:SetTextColor(lc.r, lc.g, lc.b, 1)
            local sc = STATUS_COL[data.statusColor or ""] or defC
            row.apText:SetText(data.status or "")
            row.apText:SetTextColor(sc.r, sc.g, sc.b, sc.a or 1)
            row.durationBar:Hide()
            if cache then cache[i] = { showBar = false } end
        else
            local nr, ng, nb = defC.r, defC.g, defC.b
            if data.hasBloodrage and brShowColor then
                nr, ng, nb = brC.r, brC.g, brC.b
            else
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.classToken]
                if cc then nr, ng, nb = cc.r, cc.g, cc.b end
            end
            local nm = data.name
            if nameFmt then nm = ns.FormatName(nm, nameFmt, T.NAME_FORMAT) end
            row.nameText:SetText(nm)
            row.nameText:SetTextColor(nr, ng, nb, 1)

            local col
            if not data.hasBuff then col = data.outOfRange and warnC or missC
            elseif data.belowThreshold then col = warnC
            else col = goodC end
            local s = ""
            if not data.hasBuff then
                s = data.outOfRange and "OOR" or "MISSING"
            else
                local apPart = (data.apValue or 0) > 0 and (data.apValue .. " AP") or ""
                local timPart = (durStyle == "timer" or durStyle == "both") and Dur(data.remaining) or ""
                if durStyle == "timer" then
                    s = apPart ~= "" and apPart or timPart
                elseif durStyle == "both" then
                    if apPart ~= "" and timPart ~= "" then s = apPart .. "  " .. timPart
                    else s = apPart ~= "" and apPart or timPart end
                else
                    s = apPart ~= "" and apPart or Dur(data.remaining)
                end
            end
            row.apText:SetText(s)
            row.apText:SetTextColor(col.r, col.g, col.b, col.a or 1)

            local showBar = (durStyle == "bar" or durStyle == "both") and data.hasBuff and data.remaining ~= math.huge
            local effMax = math_max(1, data.peakMax or 120)
            if showBar then
                local frac = math_min(1, math_max(0, data.remaining / effMax))
                local bw = math_max(1, math_floor(frac * barPx))
                row.durationBar:ClearAllPoints()
                row.durationBar:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.durationBar:SetPoint("TOP", row, "TOP", 0, 0)
                row.durationBar:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
                row.durationBar:SetWidth(bw)
                row.durationBar:SetColorTexture(col.r, col.g, col.b, barA)
                row.durationBar:Show()
            else
                row.durationBar:Hide()
            end
            if cache then
                cache[i] = { hasBuff = data.hasBuff, expirationTime = data.expirationTime, peakMax = effMax,
                    showBar = showBar, cr = col.r, cg = col.g, cb = col.b }
            end
        end
    end
    if cache then
        local painted = lay and nRows or math_min(#rows, MAX_ROWS)
        for j = painted + 1, #rows + 6 do cache[j] = nil end
    end
    return nRows
end

-- ============================================================
-- WHAT THE TRACKER LISTS
-- ============================================================
local peak = {}          -- [key .. name] = the most seen left (the bar's 100%)
function T.ResetPeaks() for k in pairs(peak) do peak[k] = nil end end
local function PeakMax(key, name, has, rem, fallback)
    local k = key .. ":" .. name
    if has and rem ~= math.huge then
        if not peak[k] or rem > peak[k] then peak[k] = rem end
    elseif not has then
        peak[k] = nil
    end
    return peak[k] or fallback
end

-- one member row (Readycheck's fields + unit, cast)
local function MemberRow(def, unit, tc, threshold, doRange)
    local _, classToken = UnitClass(unit)
    local hasBuff, remaining, apValue, expTime = BR.UnitBuffStatus(unit, def)
    local below = hasBuff and threshold > 0 and remaining <= threshold
    local oor
    if def.port then
        local inR, chk = false, false
        if UnitInRange then inR, chk = UnitInRange(unit) end
        oor = doRange and unit ~= "player" and chk and not inR
    else
        local inR, chk = BR.InSpellRange(BR.SingleName(def), unit)
        oor = unit ~= "player" and chk and not inR
    end
    local hasBR = false
    if def.port and tc.showBloodrage ~= false then hasBR = BR.UnitHasBloodrage(unit) end
    local uName = UnitName(unit) or "?"
    local name = uName
    local fm = tc.formats
    if not (type(fm) == "table" and fm.name) and #name > 13 then name = name:sub(1, 12) .. "." end
    return {
        name = name, fullName = uName, unit = unit, classToken = classToken,
        hasBuff = hasBuff, remaining = remaining, apValue = apValue, expirationTime = expTime,
        peakMax = PeakMax(def.key, uName, hasBuff, remaining, def.port and 120 or def.duration),
        isLong = hasBuff and remaining > 300, belowThreshold = below, outOfRange = oor and true or false,
        hasBloodrage = hasBR, def = def,
    }
end

local function Alive(unit)
    return UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit)
end

-- the click on a member row: the single rank (or the Soulstone) on them
local function MemberCast(def, r)
    if def.reach == "party" then return nil end
    if def.item then
        local id = BR.ItemInBags(def)
        if not id then return nil end
        return { type = "item", item = "item:" .. id, unit = r.unit, label = (GetItemInfo and GetItemInfo(id)) or def.label }
    end
    return { type = "spell", spell = BR.SingleName(def), unit = r.unit, label = BR.SingleName(def) }
end

local reachTmp = {}
-- the rows for one buff, appended to out; returns how many need it
function T.BuffRows(def, out, tc, now)
    tc = tc or BR.Tracker()
    local threshold = BR.Opt(def.key, "threshold") or 0
    local doRange = tc.rangeCheck
    local showMissing = tc.showOnlyMissing
    local inRaid = IsInRaid and IsInRaid() or false
    local units = BR.ReachUnits(def, "group", reachTmp)
    local need = 0
    if def.reach == "party" or def.reach == "chosen" then
        -- one flat list (Readycheck's party tracker)
        for _, unit in ipairs(units) do
            if Alive(unit) and BR.Wants(def, unit) then
                local r = MemberRow(def, unit, tc, threshold, doRange)
                local needs = (not r.hasBuff) or r.belowThreshold
                if needs then need = need + 1 end
                if not showMissing or needs then
                    r.cast = MemberCast(def, r)
                    out[#out + 1] = r
                end
            end
        end
        return need
    end
    -- by raid group (a party is one group)
    local groups = {}
    for _, unit in ipairs(units) do
        if Alive(unit) and BR.Wants(def, unit) then
            local g = BR.Subgroup(unit)
            groups[g] = groups[g] or {}
            local r = MemberRow(def, unit, tc, threshold, doRange)
            r.needs = (not r.hasBuff) or r.belowThreshold
            table.insert(groups[g], r)
        end
    end
    local gname, grank = BR.GroupKnown(def)
    local _, reagents = BR.Reagent(def)
    local groupAt = tonumber(tc.groupAt) or 3
    for g = 1, 8 do
        local list = groups[g]
        if list then
            local n, total, target, anyIn = 0, #list, nil, nil
            for _, r in ipairs(list) do
                if r.needs then
                    n = n + 1
                    if not r.outOfRange and not target then target = r end
                end
                if not r.outOfRange and not anyIn then anyIn = r end
            end
            need = need + n
            if n > 0 or not (showMissing or inRaid) then
                local useGroup = gname and n >= groupAt and (reagents or 0) > 0
                local castOn = target or anyIn
                local cast
                if castOn then
                    if useGroup then
                        cast = { type = "spell", spell = gname, unit = castOn.unit, label = gname, group = g }
                    elseif target then
                        cast = MemberCast(def, target)
                    end
                end
                local icon = (useGroup and def.group and (BR.SpellIcon(def.group.ids[grank or 1]) or def.group.icon))
                    or BR.Icon_(def)
                out[#out + 1] = { kind = "group", label = inRaid and ("Group " .. g) or "Party",
                    status = (n > 0) and (n .. " missing") or "all buffed",
                    statusColor = (n > 0) and "missing" or "good", icon = icon, cast = cast, need = n, total = total,
                    useGroup = useGroup and true or false, group = g, def = def }
                for _, r in ipairs(list) do
                    -- in a raid only those who need it; a party as Readycheck's list
                    if r.needs or not (showMissing or inRaid) then
                        r.cast = MemberCast(def, r)
                        out[#out + 1] = r
                    end
                end
            end
        end
    end
    return need
end

function BR.SpellIcon(id)
    if not (GetSpellInfo and id) then return nil end
    local _, _, t = GetSpellInfo(id)
    return t
end

-- every listed buff's rows; head = { title, icon }
local reagentWarned = {}
function T.Collect(out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    local tc = BR.Tracker()
    local blocks = {}
    for _, def in ipairs(BR.MyBuffs()) do
        if BR.TrackerOn(def.key) then
            local rows = {}
            local need = T.BuffRows(def, rows, tc)
            if #rows > 0 then blocks[#blocks + 1] = { def = def, rows = rows, need = need } end
        end
    end
    local head = { title = "Group buffs", icon = nil }
    if #blocks == 1 then
        head.title = blocks[1].def.label
        head.icon = BR.Icon_(blocks[1].def)
    elseif #blocks > 1 then
        head.icon = BR.Icon_(blocks[1].def)
    end
    for _, b in ipairs(blocks) do
        local def = b.def
        local rid, count, rname = BR.Reagent(def)
        local gname = BR.GroupKnown(def)
        local low = tonumber(tc.reagentLow) or 20
        if #blocks > 1 or (rid and gname) then
            local st, col
            if rid and gname then
                st = tostring(count)
                col = (count == 0 and "missing") or (count < low and "warn") or "good"
                -- running low: a line in chat, once each time it drops under
                if tc.reagentWarn ~= false and count < low then
                    if not reagentWarned[rid] and ns.Print and not BR.combat then
                        reagentWarned[rid] = true
                        ns.Print(string.format("buff reminders: %d %s left.", count, rname))
                    end
                elseif count >= low then
                    reagentWarned[rid] = nil
                end
            end
            out[#out + 1] = { kind = (#blocks > 1) and "section" or "reagent",
                label = (#blocks > 1) and def.label or rname, status = st, statusColor = col,
                icon = (#blocks > 1) and BR.Icon_(def) or nil, def = def }
        end
        for _, r in ipairs(b.rows) do out[#out + 1] = r end
    end
    return out, head, #blocks
end

-- a made-up group with every row state (the mover and the preview).
-- mode: "missing" | "low" | "buffed" | "raid" | "reagent"; def: the buff shown
function T.SampleRows(def, mode, now, out)
    now = now or GetTime()
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    def = def or D.BY_KEY.battleshout
    local _, myClass = UnitClass("player")
    local function M(name, cls, has, rem, ap, below, oor, br)
        out[#out + 1] = { name = name, classToken = cls, hasBuff = has, remaining = rem, apValue = ap,
            expirationTime = has and (now + rem) or 0, peakMax = def.port and 120 or def.duration,
            isLong = false, belowThreshold = below, outOfRange = oor, hasBloodrage = br, def = def }
    end
    local ap = def.port and 290 or 0
    local MIN = 60
    if def.reach == "party" or def.reach == "chosen" then
        local long = def.port and 1 or MIN
        M(UnitName("player") or "You", myClass or "WARRIOR", true, def.port and 96 or 24 * MIN, ap, false, false, def.port)
        M("Rowdy", "WARRIOR", true, def.port and 61 or 19 * MIN, ap, false, false, false)
        M("Stabbs", "ROGUE", true, 14 * long, ap, true, false, false)
        M("Bonker", "WARRIOR", false, 0, 0, false, false, false)
        M("Pewpew", "HUNTER", false, 0, 0, false, true, false)
        if mode == "buffed" then
            for _, r in ipairs(out) do
                if not r.hasBuff then r.hasBuff, r.remaining, r.apValue, r.outOfRange = true, def.port and 80 or 20 * MIN, ap, false end
                r.belowThreshold = false
                r.expirationTime = now + r.remaining
            end
        end
        return out
    end
    local gname = BR.GroupKnown(def) or (def.group and def.group.label)
    local gicon = def.group and (BR.SpellIcon(def.group.ids[#def.group.ids]) or def.group.icon) or BR.Icon_(def)
    if def.group then
        -- the reagent row: 37 carried, or (mode "reagent") under the
        -- tracker's "running low" count, coloured as the live row colours it
        local _, count, rname = BR.Reagent(def)
        local lowAt = tonumber(BR.Tracker().reagentLow) or 20
        local n = (mode == "reagent") and math.max(0, math.floor(lowAt * 0.6)) or 37
        out[#out + 1] = { kind = "reagent", label = rname or "Reagent", status = tostring(n),
            statusColor = (n == 0 and "missing") or (n < lowAt and "warn") or "good", def = def }
    end
    if mode == "buffed" then
        out[#out + 1] = { kind = "group", label = "Party", status = "all buffed", statusColor = "good", icon = BR.Icon_(def), def = def }
        M(UnitName("player") or "You", myClass or "MAGE", true, 44 * MIN, 0, false, false, false)
        M("Holgrim", "PRIEST", true, 38 * MIN, 0, false, false, false)
        M("Treehug", "DRUID", true, 21 * MIN, 0, false, false, false)
        return out
    end
    out[#out + 1] = { kind = "group", label = "Group 1", status = "4 missing", statusColor = "missing",
        icon = gicon, useGroup = true, def = def }
    M("Brakka", "WARRIOR", false, 0, 0, false, false, false)
    M("Tovren", "PALADIN", false, 0, 0, false, false, false)
    M("Sefa", "PRIEST", false, 0, 0, false, true, false)
    M("Ulfar", "SHAMAN", true, 90, 0, true, false, false)
    out[#out + 1] = { kind = "group", label = "Group 4", status = "1 missing", statusColor = "missing",
        icon = BR.Icon_(def), def = def }
    M("Frostie", "MAGE", false, 0, 0, false, false, false)
    if mode ~= "raid" then
        -- (the party view: one group only)
        local keep = {}
        for i, r in ipairs(out) do if i <= 6 then keep[#keep + 1] = r end end
        for i = #out, 1, -1 do out[i] = nil end
        for i, r in ipairs(keep) do out[i] = r end
        out[2].label = "Party"
    end
    return out
end

-- ============================================================
-- THE LIVE TRACKER
-- ============================================================
local frame
local barCache = {}
local MOVER = "buffRemTracker"
T.MOVER = MOVER

local function Place()
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 300, 400)
    if ns.ApplyMover then ns.ApplyMover(MOVER) end
end
T.Place = Place

function T.ApplyLayer()
    if not frame then return end
    local fp = BR.Tracker().framePos
    if fp or frame._zcLayered then
        frame._zcLayered = true
        -- (its scale is the tracker's own setting, never the layer's)
        local spec = fp
        if type(fp) == "table" and fp.scale ~= nil then
            spec = {}
            for k, v in pairs(fp) do if k ~= "scale" then spec[k] = v end end
        end
        ns.ApplyFramePosition(frame, spec, { strata = "MEDIUM", level = 50, clamp = true })
    end
end

local function Build()
    if frame then return frame end
    local tc = BR.Tracker()
    frame = T.New(UIParent, false)
    frame:SetScale(tonumber(tc.scale) or 1)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(50)
    frame:SetClampedToScreen(true)
    if ns.RegisterMover then
        -- reset: its own first spot (its top left at 300, 400 from the
        -- bottom left of the screen)
        ns.RegisterMover(MOVER, "Buff tracker", function() return frame end, "BOTTOMLEFT", 300, 400, nil,
            { reset = Place })
    end
    Place()
    if ns.Visibility and ns.Visibility.Register then
        ns.Visibility.Register(frame, function() return BR.Tracker().visibility end, { control = "alpha" })
    end
    T.ApplyLayer()
    frame:Hide()
    frame:HookScript("OnHide", function() if T.SyncClicks then T.SyncClicks() end end)
    return frame
end
T.Build = Build
T.Frame = function() return frame end

local function Wanted()
    if not BR.On() then return false end
    if BR.Placing(MOVER) then return true end
    if not BR.ShowIn(BR.Tracker()) then return false end
    for _, def in ipairs(BR.MyBuffs()) do
        if BR.TrackerOn(def.key) then return true end
    end
    return false
end
T.Wanted = Wanted

function T.Hide()
    if not frame or not frame:IsShown() or frame._leaving then return end
    frame._leaving = true
    ns.Motion.Hide(frame, BR.Tracker().hideAnim or NONE, function() frame._leaving = nil end)
    if not frame:IsShown() then frame._leaving = nil end
end

local collected = {}
local UpdateInner
function T.Update() return BR.InPass(UpdateInner) end
UpdateInner = function()
    if not Wanted() then
        if frame then
            ns.Motion.Stop(frame)
            frame._leaving = nil
            frame:Hide()
        end
        return
    end
    Build()
    local tc = BR.Tracker()
    local rows, head, nBlocks = T.Collect(collected)
    if BR.Placing(MOVER) then
        local mine = BR.MyBuffs()
        local def = mine[1] or D.BY_KEY.battleshout
        rows = T.SampleRows(def, "missing", GetTime(), collected)
        head = { title = def.label, icon = BR.Icon_(def) }
    end
    if #rows == 0 then
        T.Hide()
        T.SyncClicks()
        return
    end
    local sc = tonumber(tc.scale) or 1
    if math.abs((frame:GetScale() or 1) - sc) > 0.001 and not ns.Motion.IsPlaying(frame) then frame:SetScale(sc) end
    T.Layout(frame, rows, tc, barCache, head)
    if not frame:IsShown() or frame._leaving then
        frame._leaving = nil
        if not ns.Motion.Show(frame, tc.showAnim or NONE) then frame:Show() end
    end
    T.SyncClicks()
end

-- ============================================================
-- CLICK TO CAST (secure, out of combat only)
-- ============================================================
local clickLayer
local clicks = {}
local function ClickLayer()
    if clickLayer then return clickLayer end
    clickLayer = CreateFrame("Frame", "ZacUIBuffRemClicks", UIParent)
    clickLayer:SetAllPoints(UIParent)
    clickLayer:SetFrameStrata("MEDIUM")
    clickLayer:SetFrameLevel(60)
    -- the game itself puts the layer away in a fight
    if RegisterStateDriver then RegisterStateDriver(clickLayer, "visibility", "[combat] hide; show") end
    return clickLayer
end
local function ClickButton(i)
    local b = clicks[i]
    if b then return b end
    b = CreateFrame("Button", "ZacUIBuffRemClick" .. i, ClickLayer(), "SecureActionButtonTemplate")
    b:SetAttribute("useOnKeyDown", false)
    b:RegisterForClicks("AnyUp")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(FLAT)
    hl:SetVertexColor(1, 1, 1, 0.10)
    b:SetScript("OnEnter", function(self)
        local c = self.cast
        if not c then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(c.label or "")
        local who = c.unit and UnitName(c.unit) or "?"
        if c.group then
            GameTooltip:AddLine("Click: " .. (c.label or "") .. " on " .. who .. " (their whole party)", 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("Click: " .. (c.label or "") .. " on " .. who, 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Out of combat only", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    clicks[i] = b
    return b
end
T.Clicks = clicks

-- lay a button over each castable row (or take them all away)
function T.SyncClicks()
    if InCombatLockdown and InCombatLockdown() then T._clickPending = true return end
    T._clickPending = false
    local tc = BR.Tracker()
    local want = frame and frame:IsShown() and not frame._leaving and tc.clickCast ~= false
    local used = 0
    if want then
        local us = UIParent:GetEffectiveScale()
        for _, row in ipairs(frame.rows) do
            local c = row:IsShown() and row.data and row.data.cast
            if c and c.unit then
                local l, b, w, h = row:GetRect()
                if l then
                    used = used + 1
                    local btn = ClickButton(used)
                    local k = row:GetEffectiveScale() / us
                    btn:ClearAllPoints()
                    btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * k, b * k)
                    btn:SetSize(w * k, h * k)
                    btn:SetAttribute("type1", c.type)
                    btn:SetAttribute("spell1", c.type == "spell" and c.spell or nil)
                    btn:SetAttribute("item1", c.type == "item" and c.item or nil)
                    btn:SetAttribute("unit1", c.unit)
                    btn.cast = c
                    btn:Show()
                end
            end
        end
    end
    for i = used + 1, #clicks do
        local b = clicks[i]
        b.cast = nil
        b:SetAttribute("type1", nil)
        b:Hide()
    end
    T.clicksUsed = used
end
BR.regenHooks.tracker = function(entering)
    if not entering and T._clickPending then T.SyncClicks() end
end

-- the bars between scans: width from the time the scan stored (no aura reads)
local function BarTick()
    if not frame or not frame:IsShown() then return end
    if #barCache == 0 then return end
    local tc = BR.Tracker()
    local ds = tc.durationStyle or "bar"
    if ds ~= "bar" and ds ~= "both" then return end
    local px = (tc.width or 165) - 2
    local now = GetTime()
    for i, e in ipairs(barCache) do
        local row = frame.rows[i]
        if row and row:IsShown() and e.showBar then
            if e.hasBuff and e.expirationTime and e.expirationTime > 0 then
                local rem = math_max(0, e.expirationTime - now)
                local frac = math_min(1, math_max(0, rem / e.peakMax))
                row.durationBar:SetWidth(math_max(1, math_floor(frac * px)))
                row.durationBar:Show()
            else
                row.durationBar:Hide()
            end
        end
    end
end

local scanTicker, barTicker
function T.Refresh()
    if Wanted() then
        if not scanTicker then
            scanTicker = BR.NewTicker("buffRem.trackerScan", 1.5, function()
                if not Wanted() then T.Stop() return end
                T.Update()
            end)
            barTicker = BR.NewTicker("buffRem.trackerBars", 0.25, BarTick)
        end
        T.Update()
    else
        T.Stop()
    end
end
function T.Stop()
    if scanTicker then scanTicker:Cancel() scanTicker = nil end
    if barTicker then barTicker:Cancel() barTicker = nil end
    if frame then
        ns.Motion.Stop(frame)
        frame._leaving = nil
        frame:Hide()
    end
    T.SyncClicks()
end
T.Running = function() return scanTicker ~= nil end
function T.Restyle()
    if not frame then return end
    T.Style(frame, BR.Tracker())
    T.ApplyLayer()
    if ns.Visibility and ns.Visibility.Refresh then ns.Visibility.Refresh(frame) end
end
BR.OnRefresh("tracker", T.Refresh)

function BR.Restyle()
    if BR.IconUI then BR.IconUI.Restyle() end
    T.Restyle()
end
