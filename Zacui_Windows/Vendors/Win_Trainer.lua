-- Win_Trainer - ZacUI's trainer window: every service in one searchable
-- list with Blizzard's availability filters, a detail pane and a
-- one-click-per-service "Train all".
-- Part of ZacUI; load order is set by the TOC.
--
-- ClassTrainerFrame lives in Blizzard_TrainerUI, a LOAD-ON-DEMAND addon
-- the client loads on the first TRAINER_SHOW, so the window is built from
-- ADDON_LOADED. Class and profession trainers share the same frame.
--
-- It is a Win_Kit cover inside ClassTrainerFrame, so it opens and closes
-- with the trainer (Escape, walking away, the X - which hides the frame,
-- whose OnHide calls CloseTrainer exactly as Blizzard intends). It keeps
-- the panel's top-left and width and only runs a little further down
-- over the frame's empty bottom margin, so a second panel opening beside
-- it is never overlapped.
--
-- ONE SELECTION, BLIZZARD'S. The selected row is GetTrainerSelectionIndex
-- and a click goes through Blizzard's own ClassTrainerSkillButton_OnClick,
-- so ClassTrainerFrame's state (selectedService, the new-profession flag)
-- is always the one their Train button and the CONFIRM_PROFESSION prompt
-- read. Training calls their Train button's handler: learning a new
-- profession still asks first, and after a purchase Blizzard moves the
-- selection to the next available service, which this window follows.
--
--   Click              select (headers expand / collapse)
--   Shift-click        link the spell in chat (HandleModifiedItemClick)
--   Train              Blizzard's Train button
--   Train all          trains the next affordable service, one per click

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local Hex = ns.Hex
local Kit = ns.Kit
local Modules = ns.Modules
local Print = ns.Print
local UI = ns.UI

local F = UI.F

local LOD_NAME   = "Blizzard_TrainerUI"
local TEX_ICON   = "Interface\\Icons\\INV_Misc_Book_11"
local RH         = Kit.ROW_H          -- two text lines per row
local HEIGHT     = 496                -- panel height + most of the empty bottom margin
local DETAIL_H   = 124
local BUSY_SECS  = 1.5                -- no second purchase until TRAINER_UPDATE (or this)

local win, list, search, chips, allButton, countText
local detail, trainButton, trainAllButton, moneyText, totalText
local query = ""
local busy = false
local busyToken = 0

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.trainerwin ~= false
end

-- ============================================================
-- COLOUR HELPERS
-- ============================================================
-- Availability colours are Blizzard's own data - the same three colour
-- objects their filter menu paints its labels with.
local function TypeRGB(kind)
    local c
    if kind == "available" then c = GREEN_FONT_COLOR
    elseif kind == "used" then c = GRAY_FONT_COLOR
    else c = RED_FONT_COLOR end
    if c and c.r then return c.r, c.g, c.b end
    return Kit.TextRGB((kind == "available") and "green" or (kind == "used") and "gray" or "red")
end

-- Inline colour escape from the palette, for mixed-colour lines.
local function Paint(text, key)
    return "|cff" .. Hex(GetColor("text", key)) .. text .. "|r"
end

-- ============================================================
-- DATA
-- ============================================================
local function Service(i)
    local name, sub, kind, expanded = GetTrainerServiceInfo(i)
    if kind == "header" then
        return { header = true, index = i, name = name or UNKNOWN or "?", expanded = expanded and true or false }
    end
    local cost, isProf = GetTrainerServiceCost(i)
    return {
        index = i, name = name or UNKNOWN or "?", sub = sub, kind = kind,
        cost = cost or 0, isProf = isProf and true or false,
        -- (WoW Forever's own trainer never calls these two: asked only if there)
        level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0,
        icon = GetTrainerServiceIcon and GetTrainerServiceIcon(i) or nil,
    }
end

-- Search keeps a header when anything under it matches (or the header
-- itself does, which shows the whole group). Collapsed headers always
-- stay: what they hide is not enumerated, so it cannot be ruled out.
local function Rows()
    local all, out = {}, {}
    local n = GetNumTrainerServices() or 0
    for i = 1, n do all[#all + 1] = Service(i) end
    local filtering = query ~= ""
    local pending, showAll = nil, false
    for _, e in ipairs(all) do
        if e.header then
            pending, showAll = e, Kit.Matches(query, e.name)
            if not filtering or not e.expanded or showAll then
                out[#out + 1] = e
                pending = nil
            end
        elseif not filtering or showAll or Kit.Matches(query, e.name, e.sub) then
            if pending then
                out[#out + 1] = pending
                pending = nil
            end
            out[#out + 1] = e
        end
    end
    return out, all, n
end

-- Every available service you can afford, in list order, with the money
-- spent on the ones before it taken off first. New professions are left
-- out: they take a profession slot and Blizzard asks before each one.
local function Trainable(all)
    local money = GetMoney()
    local first, count, total = nil, 0, 0
    for _, e in ipairs(all) do
        if not e.header and e.kind == "available" then
            total = total + e.cost
            if not e.isProf and e.cost <= money then
                money = money - e.cost
                count = count + 1
                first = first or e
            end
        end
    end
    return first, count, total
end

-- ============================================================
-- BLIZZARD'S SELECTION AND TRAIN FLOW
-- ============================================================
-- Their row click with a stand-in row: it only asks :GetID().
local function BlizzSelect(index)
    if ClassTrainerSkillButton_OnClick then
        ClassTrainerSkillButton_OnClick({ GetID = function() return index end })
    elseif SelectTrainerService then
        SelectTrainerService(index)
    end
end

local function CanTrain(e)
    if not e or e.header or e.kind ~= "available" then return false end
    if e.cost > GetMoney() then return false end
    -- Blizzard disables Train for a third primary profession.
    if e.isProf and GetNumPrimaryProfessions and GetNumPrimaryProfessions() >= 2 then return false end
    return true
end

local Refresh, Queue

local function SetBusy()
    busy = true
    busyToken = busyToken + 1
    local token = busyToken
    C_Timer.After(BUSY_SECS, function()
        if busy and busyToken == token then
            busy = false
            Queue()
        end
    end)
end

local function Train(e)
    if busy or not CanTrain(e) or not ClassTrainerFrame then return end
    -- A profession is always re-selected through Blizzard's click: that
    -- is what sets ClassTrainerFrame.showDialog, and a stale flag left by
    -- an earlier selection would let their Train handler buy it unasked.
    if e.isProf or ClassTrainerFrame.selectedService ~= e.index
        or GetTrainerSelectionIndex() ~= e.index then
        BlizzSelect(e.index)
    end
    if ClassTrainerTrainButton_OnClick and ClassTrainerFrame.selectedService == e.index then
        -- Their handler: the profession prompt, or the purchase.
        ClassTrainerTrainButton_OnClick()
    elseif not e.isProf then
        BuyTrainerService(e.index)
    else
        -- Never learn a profession without Blizzard's prompt.
        return
    end
    SetBusy()
    Refresh(true)
end

-- ============================================================
-- DETAIL PANE
-- ============================================================
-- Blizzard's requirement line, rebuilt with palette colours: each unmet
-- requirement red, everything met in the normal text colour. A service
-- you already know never shows red (their "used" rule).
local function IsPetSpell(index)
    if not IsTrainerServiceLearnSpell then return false end
    local _, isPet = IsTrainerServiceLearnSpell(index)
    return isPet and true or false
end

local function Requirements(e)
    local parts = {}
    local isPet = IsPetSpell(e.index)
    local known = (e.kind == "used")
    if e.level and e.level > 1 then
        local have = UnitLevel(isPet and "pet" or "player") or 0
        local label = (LEVEL or "Level") .. " " .. e.level
        if isPet then label = (PET or "Pet") .. " " .. label end
        parts[#parts + 1] = (known or have >= e.level) and label or Paint(label, "red")
    end
    if GetTrainerServiceSkillReq then
        local skill, rank, hasReq = GetTrainerServiceSkillReq(e.index)
        if skill then
            local s = skill .. " (" .. (rank or 0) .. ")"
            parts[#parts + 1] = (known or hasReq) and s or Paint(s, "red")
        end
    end
    local n = GetTrainerServiceNumAbilityReq and GetTrainerServiceNumAbilityReq(e.index) or 0
    for i = 1, n do
        local ability, hasReq = GetTrainerServiceAbilityReq(e.index, i)
        if ability then
            parts[#parts + 1] = (known or hasReq) and ability or Paint(ability, "red")
        end
    end
    if #parts == 0 then return "" end
    return Paint((REQUIRES_LABEL or "Requires:"), "gray") .. " " .. table.concat(parts, ", ")
end

local function UpdateDetail(e)
    if not e or e.header then
        detail.empty:Show()
        detail.icon:Hide()
        detail.name:SetText("")
        detail.sub:SetText("")
        detail.cost:SetText("")
        detail.req:SetText("")
        detail.desc:SetText("")
        detail.item = nil
        return
    end
    detail.item = e
    detail.empty:Hide()
    detail.icon:Show()
    detail.icon:SetIcon(e.icon)
    detail.icon:SetDesaturated(e.kind == "used")
    detail.name:SetText(e.name)
    detail.name:SetTextColor(TypeRGB(e.kind))

    local sub = (e.sub and e.sub ~= "") and e.sub or ""
    if TRAINER_PET_SPELL_LABEL and IsPetSpell(e.index) then sub = sub .. TRAINER_PET_SPELL_LABEL end
    if e.isProf then
        sub = (sub ~= "" and (sub .. "  |  ") or "") .. (TRADE_SKILLS or "Profession")
    end
    detail.sub:SetText(sub)

    if e.cost > 0 then
        detail.cost:SetText(ns.Money(e.cost))
        if e.cost > GetMoney() and e.kind ~= "used" then
            detail.cost:SetTextColor(Kit.TextRGB("red"))
        else
            detail.cost:_zPaint()
        end
    else
        detail.cost:SetText("")
    end
    detail.req:SetText(Requirements(e))
    detail.desc:SetText(GetTrainerServiceDescription and GetTrainerServiceDescription(e.index) or "")
end

-- ============================================================
-- FOOTER
-- ============================================================
local function UpdateFooter(all)
    local first, count, total = Trainable(all)
    moneyText:SetText(Paint("You have ", "gray") .. ns.Money(GetMoney()))
    if total > 0 then
        local t = ns.Money(total)
        if total > GetMoney() then t = Paint(t, "red") end
        totalText:SetText(Paint("All available ", "gray") .. t)
    else
        totalText:SetText(Paint("Nothing left to learn here.", "gray"))
    end
    trainAllButton._zNext = first
    trainAllButton:SetLabel(count > 0 and ("Train all (" .. count .. " left)") or "Train all")
    trainAllButton:SetDisabled(busy or count == 0)
    trainButton:SetDisabled(busy or not CanTrain(detail.item))
end

-- ============================================================
-- REFRESH
-- ============================================================
function Refresh(keepOffset)
    -- IsVisible, not IsShown: the cover is a shown child all session.
    if not win or not win:IsVisible() then return end
    local data, all, n = Rows()

    -- Blizzard's filters are the server's, so the chips read them back
    -- rather than keep their own copy.
    if GetTrainerServiceTypeFilter then
        for key, chip in pairs(chips) do
            chip:SetOn(GetTrainerServiceTypeFilter(key) and true or false)
        end
    end

    local sel = GetTrainerSelectionIndex and GetTrainerSelectionIndex() or 0
    local selEntry
    for _, e in ipairs(all) do
        if e.index == sel and not e.header then selEntry = e break end
    end
    list.selected = nil
    for _, e in ipairs(data) do
        if selEntry and e.index == selEntry.index then list.selected = e break end
    end
    list:SetEmptyText(n == 0 and "Nothing to show - check the filters." or "Nothing matches.")
    list:SetData(data, keepOffset)

    local services, headers, expanded = 0, 0, 0
    for _, e in ipairs(all) do
        if e.header then
            headers = headers + 1
            if e.expanded then expanded = expanded + 1 end
        else
            services = services + 1
        end
    end
    local shown = 0
    for _, e in ipairs(data) do if not e.header then shown = shown + 1 end end
    countText:SetText(query ~= "" and (shown .. " / " .. services) or (services .. (services == 1 and " service" or " services")))
    allButton._zCollapse = expanded > 0
    allButton:SetLabel(expanded > 0 and "Collapse all" or "Expand all")
    allButton:SetDisabled(headers == 0)

    UpdateDetail(selEntry)
    UpdateFooter(all)
end

Queue = Kit.Coalesce(function() Refresh(true) end, function() return win end)

-- ============================================================
-- ROWS
-- ============================================================
local function RowTooltip(row)
    local e = row.item
    if not e or e.header then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetTrainerService then
        GameTooltip:SetTrainerService(e.index)
    else
        GameTooltip:SetText(e.name)
    end
    GameTooltip:Show()
end

local function LinkService(index)
    local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(index)
    return link and HandleModifiedItemClick(link)
end

local function BuildRow(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.icon = Kit.Icon(row, RH - 8)
    row.icon:SetPoint("LEFT", 3, 0)

    -- Header rows: a +/- and the group name.
    row.toggle = UI.Font(row, F.LABEL, { cat = "text", key = "gray", justify = "CENTER" })
    row.toggle:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.toggle:SetWidth(RH - 8)
    row.head = UI.Font(row, F.LABEL, { cat = "text", key = "gold", justify = "LEFT" })
    row.head:SetPoint("LEFT", row.toggle, "RIGHT", 6, 0)
    row.head:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.head:SetWordWrap(false)

    -- Service rows: name / cost on top, rank / level underneath. Each
    -- line is pinned TOPLEFT+TOPRIGHT (or BOTTOMLEFT+BOTTOMRIGHT) to its
    -- right-hand partner, so the two can never overlap.
    local x = 3 + (RH - 8) + 6
    row.cost = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.cost:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    row.cost:SetWordWrap(false)
    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", x, -4)
    row.nameText:SetPoint("TOPRIGHT", row.cost, "TOPLEFT", -6, 0)
    row.nameText:SetWordWrap(false)

    row.level = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.level:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 4)
    row.level:SetWordWrap(false)
    row.sub = UI.Font(row, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    row.sub:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 4)
    row.sub:SetPoint("BOTTOMRIGHT", row.level, "BOTTOMLEFT", -6, 0)
    row.sub:SetWordWrap(false)

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.UpdateTooltip = RowTooltip

    row:SetScript("OnClick", function(self)
        local e = self.item
        if not e then return end
        if e.header then
            -- Blizzard's header click, minus the selection it would move.
            if not (CollapseTrainerSkillLine and ExpandTrainerSkillLine) then return end   -- (not on WoW Forever)
            if e.expanded then CollapseTrainerSkillLine(e.index) else ExpandTrainerSkillLine(e.index) end
            return
        end
        if IsModifiedClick() and LinkService(e.index) then return end
        BlizzSelect(e.index)
        Queue()
    end)
end

local function UpdateRow(row, e)
    local isHeader = e.header and true or false
    row.toggle:SetShown(isHeader)
    row.head:SetShown(isHeader)
    row.icon:SetShown(not isHeader)
    row.nameText:SetShown(not isHeader)
    row.sub:SetShown(not isHeader)
    row.cost:SetShown(not isHeader)
    row.level:SetShown(not isHeader)
    if isHeader then
        row.toggle:SetText(e.expanded and "-" or "+")
        row.head:SetText(e.name)
        return
    end

    row.icon:SetIcon(e.icon)
    row.icon:SetQuality(nil)
    row.icon:SetDesaturated(e.kind == "used")
    row.nameText:SetText(e.name)
    row.nameText:SetTextColor(TypeRGB(e.kind))
    row.sub:SetText(e.sub or "")

    if e.kind ~= "used" and e.cost > 0 then
        row.cost:SetText(ns.Money(e.cost))
        if e.cost > GetMoney() then row.cost:SetTextColor(Kit.TextRGB("red")) else row.cost:_zPaint() end
    else
        row.cost:SetText("")
    end

    if e.kind ~= "used" and e.level > 1 then
        row.level:SetText((LEVEL or "Level") .. " " .. e.level)
        if e.level > (UnitLevel("player") or 0) then
            row.level:SetTextColor(Kit.TextRGB("red"))
        else
            row.level:SetTextColor(Kit.TextRGB("gray"))
        end
    else
        row.level:SetText("")
    end
end

-- ============================================================
-- BUILD
-- ============================================================
local function BuildDetail()
    detail = UI.Box(win, "ui", "cardBg")
    detail:SetHeight(DETAIL_H)
    detail:SetPoint("BOTTOMLEFT", win.footer, "TOPLEFT", Kit.PAD - 1, Kit.GAP)
    detail:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)

    detail.empty = UI.Font(detail, F.LABEL, { cat = "text", key = "gray", justify = "CENTER",
        text = "Select a service to see what it needs." })
    detail.empty:SetPoint("CENTER")

    -- The icon: Blizzard's detail icon tooltips and links the service.
    detail.icon = Kit.Icon(detail, 34)
    detail.icon:SetPoint("TOPLEFT", 6, -6)
    detail.icon:EnableMouse(true)
    detail.icon:SetScript("OnEnter", function(self)
        local e = detail.item
        if not e or not GameTooltip.SetTrainerService then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetTrainerService(e.index)
        GameTooltip:Show()
    end)
    detail.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    detail.icon:SetScript("OnMouseUp", function()
        local e = detail.item
        if e then LinkService(e.index) end
    end)

    detail.cost = UI.Font(detail, F.SMALL, { justify = "RIGHT" })
    detail.cost:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -6, -8)
    detail.cost:SetWordWrap(false)
    detail.name = UI.Font(detail, F.LABEL, { justify = "LEFT" })
    detail.name:SetPoint("TOPLEFT", detail.icon, "TOPRIGHT", 8, -2)
    detail.name:SetPoint("TOPRIGHT", detail.cost, "TOPLEFT", -6, 0)
    detail.name:SetWordWrap(false)
    -- The sub line sits on the icon's bottom edge (icon: 6 down, 34 tall,
    -- so its bottom is 40 down; +2 inset = 38). Both points are BOTTOM
    -- ones at the same height - a TOPLEFT + RIGHT pair would centre it on
    -- the pane's middle, right over the requirements line.
    detail.sub = UI.Font(detail, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    detail.sub:SetPoint("BOTTOMLEFT", detail.icon, "BOTTOMRIGHT", 8, 2)
    detail.sub:SetPoint("BOTTOMRIGHT", detail, "TOPRIGHT", -6, -38)
    detail.sub:SetJustifyV("BOTTOM")
    detail.sub:SetWordWrap(false)

    detail.req = UI.Font(detail, F.SMALL, { justify = "LEFT" })
    detail.req:SetPoint("TOPLEFT", detail, "TOPLEFT", 6, -46)
    detail.req:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -6, -46)
    detail.req:SetHeight(24)
    detail.req:SetJustifyV("TOP")
    detail.req:SetWordWrap(true)

    detail.desc = UI.Font(detail, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    detail.desc:SetPoint("TOPLEFT", detail.req, "BOTTOMLEFT", 0, -3)
    detail.desc:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -6, 6)
    detail.desc:SetJustifyV("TOP")
    detail.desc:SetWordWrap(true)
end

local function Build()
    if win then return win end
    win = Kit.Cover(ClassTrainerFrame, {
        name = "ZacUITrainerWindow",
        title = TRAINER or "Trainer",
        insetName = "ClassTrainerFrame",
        height = HEIGHT,
        -- An addon's HideUIPanel is refused in combat; ending the session
        -- makes Blizzard hide the frame from its own close event instead.
        onClose = function()
            if InCombatLockdown() and CloseTrainer then CloseTrainer()
            else HideUIPanel(ClassTrainerFrame) end
        end,
    })
    win:SetIcon(TEX_ICON)

    -- The greeting rides beside the trainer's name, muted, and gives way
    -- (truncates) before the name does.
    local title = win.titleText
    title:ClearAllPoints()
    title:SetPoint("LEFT", win.titleBar, "LEFT", 8 + 18 + 7, 0)
    local greet = UI.Font(win.titleBar, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    greet:SetPoint("LEFT", title, "RIGHT", 8, 0)
    greet:SetPoint("RIGHT", win.titleBar, "RIGHT", -34, 0)
    greet:SetWordWrap(false)
    win.greeting = greet

    -- Row 1: search + collapse/expand all.
    local y = win.top
    allButton = UI.Button(win, "Collapse all", { width = 78, height = Kit.SEARCH_H, size = F.SMALL })
    allButton:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y)
    allButton:SetScript("OnClick", function(self)
        -- Blizzard's "All" button: index 0 means every header.
        if not (CollapseTrainerSkillLine and ExpandTrainerSkillLine) then return end   -- (not on WoW Forever)
        if self._zCollapse then CollapseTrainerSkillLine(0) else ExpandTrainerSkillLine(0) end
    end)
    search = Kit.Search(win, 100, function(text)
        query = Kit.NormalizeQuery(text)
        Refresh()
    end, "Search this trainer")
    search:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
    search:SetPoint("TOPRIGHT", allButton, "TOPLEFT", -Kit.GAP, 0)

    -- Row 2: Blizzard's three service filters.
    local y2 = y - Kit.SEARCH_H - Kit.GAP
    chips = {}
    local function Filter(key)
        return function(on)
            if not SetTrainerServiceTypeFilter then return false end
            -- The server re-sends the list; TRAINER_UPDATE redraws it.
            SetTrainerServiceTypeFilter(key, on and true or false)
            Queue()
        end
    end
    chips.available = Kit.Chip(win, AVAILABLE or "Available", true, Filter("available"),
        "Services you can learn now.")
    chips.available:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y2)
    chips.unavailable = Kit.Chip(win, UNAVAILABLE or "Unavailable", true, Filter("unavailable"),
        "Services you do not meet the requirements for yet.")
    chips.unavailable:SetPoint("LEFT", chips.available, "RIGHT", 4, 0)
    chips.used = Kit.Chip(win, USED or "Already known", false, Filter("used"),
        "Services you have already learned.")
    chips.used:SetPoint("LEFT", chips.unavailable, "RIGHT", 4, 0)
    countText = UI.Font(win, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    countText:SetPoint("TOPLEFT", chips.used, "TOPRIGHT", Kit.GAP, -5)
    countText:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y2 - 5)
    countText:SetWordWrap(false)

    -- Footer: money and the total on the left, the buttons on the right.
    win.footer = Kit.Footer(win, Kit.FOOTER_H + 6)
    trainButton = UI.Button(win.footer, TRAIN or "Train", { width = 64, height = 24 })
    trainButton:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    trainButton:SetScript("OnClick", function() Train(detail.item) end)
    trainAllButton = UI.Button(win.footer, "Train all", { width = 112, height = 24, size = F.SMALL })
    trainAllButton:SetPoint("RIGHT", trainButton, "LEFT", -4, 0)
    trainAllButton:SetScript("OnClick", function(self) Train(self._zNext) end)
    UI.Tooltip(trainAllButton, "Train all",
        "Trains the next available service you can afford, one per click - the count "
        .. "shows how many are left. New professions are skipped (use Train, Blizzard "
        .. "asks first). Only services shown by the filters and in expanded groups count.")

    moneyText = UI.Font(win.footer, F.SMALL, { justify = "LEFT" })
    moneyText:SetPoint("TOPLEFT", win.footer, "TOPLEFT", 8, -6)
    moneyText:SetPoint("TOPRIGHT", trainAllButton, "TOPLEFT", -6, 0)
    moneyText:SetWordWrap(false)
    totalText = UI.Font(win.footer, F.SMALL, { justify = "LEFT" })
    totalText:SetPoint("BOTTOMLEFT", win.footer, "BOTTOMLEFT", 8, 6)
    totalText:SetPoint("BOTTOMRIGHT", trainAllButton, "BOTTOMLEFT", -6, 0)
    totalText:SetWordWrap(false)

    BuildDetail()

    list = Kit.List(win, {
        rowHeight = RH,
        build = BuildRow,
        update = UpdateRow,
    })
    list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y2 - Kit.SEARCH_H - Kit.GAP)
    list:SetPoint("BOTTOMRIGHT", detail, "TOPRIGHT", 0, Kit.GAP)

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("TRAINER_UPDATE")
    ev:RegisterEvent("TRAINER_DESCRIPTION_UPDATE")
    ev:RegisterEvent("TRAINER_SERVICE_INFO_NAME_UPDATE")
    ev:RegisterEvent("PLAYER_MONEY")
    ev:RegisterEvent("SKILL_LINES_CHANGED")
    ev:SetScript("OnEvent", function(_, event)
        -- A learned service (or a filter / collapse) comes back as
        -- TRAINER_UPDATE: that is the end of the purchase in flight.
        if event == "TRAINER_UPDATE" then busy = false end
        if win:IsVisible() then Queue() end
    end)

    win:HookScript("OnShow", function()
        query = ""
        busy = false
        search:SetText("")
        list.offset = 0
        local name = UnitName("npc") or (TRAINER or "Trainer")
        title:SetText(name)
        title:SetWidth(math.min(math.ceil(title:GetStringWidth()) + 2, 190))
        greet:SetText(GetTrainerGreetingText and GetTrainerGreetingText() or "")
        Queue()
    end)
    win:HookScript("OnHide", function() busy = false end)
    return win
end

-- Pieces of ClassTrainerFrame outside the cover: the close button pokes
-- past the top-right corner, the portrait past the top-left, and the
-- frame's own border art runs round every edge (the "trainer" skin
-- strips it, but that skin can be turned off on its own). The art is the
-- frame's regions; ZacUI's own skin textures are marked and left alone.
-- Built by appending, never a literal with possible nil holes (ipairs
-- stops at the first one).
local function Leftovers()
    local t = {}
    local function Add(f) if f then t[#t + 1] = f end end
    Add(_G.ClassTrainerFrameCloseButton)
    Add(_G.ClassTrainerFramePortrait)
    local f = ClassTrainerFrame
    if f then
        Add(f.CloseButton)
        Add(f.PortraitContainer)
        Add(f.NineSlice)
        Add(f.TitleContainer)           -- Forever's modern trainer window only (level 510, over the cover)
        for _, r in ipairs({ f:GetRegions() }) do
            if not r._zui_own then Add(r) end
        end
    end
    return t
end

local function Apply()
    if not ClassTrainerFrame then return end
    if Enabled() then
        Build()
        win.Reanchor()
        win:Show()
        Kit.Silence(Leftovers())
        if ClassTrainerFrame:IsShown() then Queue() end
    elseif win then
        win:Hide()
        Kit.Unsilence(Leftovers())
    end
end

-- ============================================================
-- MODULE
-- ============================================================
local function Setup()
    if not ClassTrainerFrame or ns._zTrainerWinHooked then return end
    ns._zTrainerWinHooked = true
    Apply()
    -- A later /zui toggle only flips the saved flag; the window checks it
    -- on every open so turning it off never needs a reload.
    ClassTrainerFrame:HookScript("OnShow", function()
        Apply()
        Queue()
    end)
end

Modules.trainerwin = function()
    if ns._zTrainerWin then return end
    ns._zTrainerWin = true
    -- The LoD registry keeps ONE function per addon, and the trainer skin
    -- registers for this addon too: chain whatever is parked there rather
    -- than replace it.
    local prev = ns.LOD and ns.LOD[LOD_NAME]
    if prev then
        ns.RegisterLoD(LOD_NAME, function()
            local ok, err = pcall(prev)
            if not ok and Print then Print(LOD_NAME .. " skin failed: " .. tostring(err)) end
            Setup()
        end)
    else
        ns.RegisterLoD(LOD_NAME, Setup)
    end
    -- And our own listener, in case a later registration replaces ours.
    -- A frame later, so the skin (drained from the LoD registry in the
    -- same ADDON_LOADED) has run first: its LiftDarkText walks every
    -- child of ClassTrainerFrame and would otherwise restyle our cover.
    if not ClassTrainerFrame then
        local watch = CreateFrame("Frame")
        watch:RegisterEvent("ADDON_LOADED")
        watch:SetScript("OnEvent", function(self, _, name)
            if name ~= LOD_NAME then return end
            self:UnregisterEvent("ADDON_LOADED")
            C_Timer.After(0, function()
                local ok, err = pcall(Setup)
                if not ok and Print then Print(LOD_NAME .. " window failed: " .. tostring(err)) end
            end)
        end)
    end
end
