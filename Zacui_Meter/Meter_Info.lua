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
-- ROW TOOLTIP
-- ============================================================
function Meter.RowTooltip(row, win)
    local actor = row.actor
    if not actor then return end
    local ToK = Meter.ToKList[Meter.DB().psAbbrev] or Meter.ToK

    GameTooltip:SetOwner(row, "ANCHOR_TOPRIGHT")
    GameTooltip:AddLine(row.leftText:GetText() or actor.name)

    local disp = Meter.DISPLAYS[win.settings.display]
    if disp and disp.container == "misc" then
        -- misc displays: deaths get their death times, counters their targets
        if win.settings.display == "deaths" then
            local combat = row.combat
            if combat then
                for _, dt in ipairs(combat.deaths) do
                    if dt.name == actor.name then
                        GameTooltip:AddDoubleLine("Died", dt.timeString, 1, 1, 1, 1, 0.4, 0.4)
                    end
                end
            end
        elseif actor.interruptTargets or actor.dispellTargets then
            local targets = actor.interruptTargets or actor.dispellTargets
            for _, e in ipairs(TopEntries(targets, 3)) do
                GameTooltip:AddDoubleLine(e.key, e.value, 1, 1, 1, 1, 1, 1)
            end
        end
        GameTooltip:Show()
        return
    end

    if actor.spells and next(actor.spells) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Abilities", 1, 0.82, 0)
        local spellTotals = {}
        for id, sp in pairs(actor.spells) do spellTotals[id] = sp.total end
        local total = actor.total > 0 and actor.total or 1
        for _, e in ipairs(TopEntries(spellTotals, 3)) do
            local sp = actor.spells[e.key]
            GameTooltip:AddDoubleLine(SpellName(e.key, sp.name),
                ToK(e.value) .. " (" .. format("%.1f", e.value / total * 100) .. "%)",
                1, 1, 1, 1, 1, 1)
        end
    end
    if actor.targets and next(actor.targets) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Targets", 1, 0.82, 0)
        local total = actor.total > 0 and actor.total or 1
        for _, e in ipairs(TopEntries(actor.targets, 3)) do
            GameTooltip:AddDoubleLine(e.key,
                ToK(e.value) .. " (" .. format("%.1f", e.value / total * 100) .. "%)",
                1, 1, 1, 1, 1, 1)
        end
    end
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
    f.title:SetFont(FONT, 13)
    f.title:SetShadowColor(0, 0, 0, 1)
    f.title:SetShadowOffset(1, -1)
    f.title:SetPoint("TOPLEFT", 10, -8)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -6, -6)
    local x = close:CreateFontString(nil, "OVERLAY")
    x:SetFont(FONT, 12)
    x:SetPoint("CENTER")
    x:SetText("X")
    close:SetScript("OnClick", function() f:Hide() end)

    f.lines = {}
    for i = 1, 24 do
        local left = f:CreateFontString(nil, "OVERLAY")
        left:SetFont(FONT, 11)
        left:SetShadowColor(0, 0, 0, 1)
        left:SetShadowOffset(1, -1)
        left:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 12)
        left:SetJustifyH("LEFT")
        local right = f:CreateFontString(nil, "OVERLAY")
        right:SetFont(FONT, 11)
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
    breakdown = breakdown or BuildBreakdown()
    local ToK = Meter.ToKList[Meter.DB().psAbbrev] or Meter.ToK
    local f = breakdown
    local disp = Meter.DISPLAYS[win.settings.display]
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

local function SendReport(win, channel, whisperTarget)
    local d = Meter.DB()
    local disp = Meter.DISPLAYS[win.settings.display]
    local combat = Meter.CombatForWindow(win)
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
    if #lines == 1 then Print("Nothing to report.") return end

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
    title:SetFont(FONT, 12)
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
        t:SetFont(FONT, 11)
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
                            SendReport(f.win, "WHISPER", target)
                        end
                    end,
                }
                StaticPopup_Show("ZACUI_METER_WHISPER")
            else
                SendReport(f.win, ch.key)
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
    report:ClearAllPoints()
    report:SetPoint("BOTTOM", win.frame, "TOP", 0, 6)
    report:Show()
end
