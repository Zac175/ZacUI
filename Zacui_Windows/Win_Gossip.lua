-- Win_Gossip - ZacUI's NPC dialogue windows: the gossip page (what an NPC
-- says and the things you can pick) and the quest pages a quest giver
-- opens (the greeting list, a quest's offer, the hand-in check and the
-- reward choice).
-- Part of ZacUI; load order is set by the TOC.
--
-- TWO COVERS, ONE FILE. They share their rows and text panes, and the two
-- Blizzard frames hand off to each other constantly: picking a quest in
-- the gossip list closes GossipFrame and opens QuestFrame on its offer.
--
-- Built on Win_Kit's cover, so each window lives inside Blizzard's frame
-- and opens, closes and ends the NPC interaction exactly when Blizzard's
-- does - GossipFrame's OnHide calls C_GossipInfo.CloseGossip, QuestFrame's
-- calls CloseQuest. Blizzard still receives every event and builds its
-- own page underneath; the covers READ the same APIs Blizzard's pages read
-- and act through the same calls (Blizzard's own button handlers where it
-- has them), so auto-accept, the QoL gossip skip and every other addon
-- that drives these frames keep working unchanged.
--
-- WHICH QUEST PAGE. QuestFrame shows exactly one of four panels (greeting,
-- detail, progress, reward) and swaps them from its event handler. The
-- cover follows whichever panel last showed, so it can never disagree
-- with the page Blizzard's buttons would act on.
--
--   Gossip row           pick it (available quest / active quest / option)
--   Quest-list row       open that quest (the greeting page)
--   Reward icon          tooltip; shift-click links, ctrl-click previews;
--                        plain click picks a choice on the reward page
--   Footer               Accept / Decline, Continue / Cancel,
--                        Complete Quest / Cancel, Goodbye
--   X                    Blizzard's close - ends the interaction
--
-- No number-key shortcuts, deliberately: SetPropagateKeyboardInput is
-- refused to addons in combat, and the override-binding route shadows the
-- 1-9 action-bar keys while a window is open. Not worth it on a warrior.

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local UI = ns.UI

local M, F = UI.M, UI.F

-- ============================================================
-- LAYOUT
-- ============================================================
local ROW_H    = 22     -- one gossip / quest-list line
local BOX_PAD  = 6      -- text box edge -> text
local REWARD_H = 36
local BAR_ROOM = M.SCROLL_W + 4

local ICON_AVAILABLE        = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_AVAILABLE_DAILY  = "Interface\\GossipFrame\\DailyQuestIcon"
local ICON_AVAILABLE_LEGEND = "Interface\\GossipFrame\\AvailableLegendaryQuestIcon"
local ICON_ACTIVE           = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_ACTIVE_DAILY     = "Interface\\GossipFrame\\DailyActiveQuestIcon"
local ICON_ACTIVE_LEGEND    = "Interface\\GossipFrame\\ActiveLegendaryQuestIcon"

local function GossipEnabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.gossipwin ~= false
end

local function QuestEnabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.questdialogwin ~= false
end

-- ============================================================
-- SMALL HELPERS
-- ============================================================
local function InsertChat(text)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if text and insert then return insert(text) end
end

local function Sound(key)
    if SOUNDKIT and SOUNDKIT[key] and PlaySound then PlaySound(SOUNDKIT[key]) end
end

-- Blizzard's difficulty colours are data (QuestDifficultyColors), the one
-- place literal RGB is expected in a quest list.
local function DifficultyRGB(level)
    if type(level) == "number" and level > 0 and GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, level)
        if ok and c and c.r then return c.r, c.g, c.b end
    end
    return Kit.TextRGB("normal")
end

local function LevelTag(level)
    if type(level) ~= "number" or level <= 0 then return "" end
    return "[" .. level .. "] "
end

-- Guarded legacy call: a missing API or an error reads as "no answer".
local function Try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
    return nil
end

-- HideUIPanel refuses addon callers in combat (UIParentPanelManager's
-- CheckProtectedFunctionsAllowed). Ending the interaction instead makes
-- Blizzard's own event handler (GOSSIP_CLOSED / QUEST_FINISHED) hide the
-- frame from its secure code, so the X and Goodbye still work mid-fight.
local function CloseHost(host, endInteraction)
    if not host then return end
    if InCombatLockdown() then
        if endInteraction then endInteraction() end
    else
        HideUIPanel(host)
    end
end

-- Every art region a frame draws itself (textures and its own strings),
-- skipping ours.
local function AddRegions(t, frame)
    if not (frame and frame.GetRegions) then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if not r._zui_own and r.IsObjectType
            and (r:IsObjectType("Texture") or r:IsObjectType("FontString")) then
            t[#t + 1] = r
        end
    end
end

-- ============================================================
-- SCROLLING TEXT BOX
-- ============================================================
-- A card-coloured box holding a UI.ScrollArea. The greeting of both
-- windows and the quest pages are all one of these.
local function TextBox(parent)
    local box = UI.Box(parent, "ui", "cardBg")
    local scroll, child, bar = UI.ScrollArea(box)
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", BOX_PAD, -BOX_PAD)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -(BOX_PAD + BAR_ROOM), BOX_PAD)
    bar:SetPoint("TOPRIGHT", box, "TOPRIGHT", -3, -3)
    bar:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
    -- Range depends on the viewport height; re-measure when it settles.
    scroll:SetScript("OnSizeChanged", function(self) self:Recalculate() end)
    box.scroll, box.child, box.bar = scroll, child, bar
    return box
end

-- Wrap width inside a TextBox that spans the window, known before the box
-- has ever been laid out (a FontString needs it before it can measure).
local function TextWidth(win)
    local w = win:GetWidth() or 0
    if w < 120 then w = 320 end
    return math.floor(w - 2 * Kit.PAD - 2 * BOX_PAD - BAR_ROOM)
end

-- Height between the title bar and the footer.
local function ContentHeight(win)
    local h = win:GetHeight() or 0
    if h < 150 then h = 400 end
    return h - (M.TITLEBAR + Kit.PAD) - (win.footer:GetHeight() + Kit.GAP)
end

-- ============================================================
-- DIALOGUE ROWS (gossip options and the quest greeting list)
-- ============================================================
-- An entry is either { header = true, text = ... } or a pickable line:
-- { icon, desat, dim, text, r, g, b, tag, tagKey, action }.
local function RowTooltip(row)
    local e = row.item
    if not e or e.header then return end
    if row.label.IsTruncated and row.label:IsTruncated() then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.text, row.label:GetTextColor())
        GameTooltip:Show()
    end
end

local function BuildDialogRow(row)
    row:RegisterForClicks("LeftButtonUp")
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon._zui_own = true
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon = icon

    row.tag = UI.Font(row, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    row.tag:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.tag:SetWordWrap(false)

    row.label = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.label:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        local e = self.item
        if e and not e.header and e.action then e.action() end
    end)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function UpdateDialogRow(row, e)
    row.label:ClearAllPoints()
    if e.header then
        -- Section names sit on the header colour, so they read as dividers
        -- and not as something to click. Disabled: no hover lift either.
        local hb = GetColor("ui", "headerBg")
        row.stripe:SetVertexColor(hb.r, hb.g, hb.b, 1)
        row:Disable()
        row.icon:Hide()
        row.tag:SetText("")
        row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.label:SetText(e.text or "")
        row.label._zPaintKey = "gold"
        row.label:_zPaint()
        return
    end

    row:Enable()
    row.icon:SetTexture(e.icon)
    row.icon:SetDesaturated(e.desat and true or false)
    row.icon:SetAlpha(e.dim and 0.55 or 1)
    row.icon:Show()

    row.tag:SetText(e.tag or "")
    row.tag._zPaintKey = e.tagKey or "gray"
    row.tag:_zPaint()

    -- The line runs up to the tag when there is one, the row edge when not.
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    if e.tag and e.tag ~= "" then
        row.label:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
    else
        row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    end
    row.label:SetText(e.text or "")
    if e.r then
        row.label:SetTextColor(e.r, e.g, e.b)
    else
        row.label._zPaintKey = e.dim and "gray" or "normal"
        row.label:_zPaint()
    end
end

-- ============================================================
-- DIALOGUE PANE: greeting text over a list of picks
-- ============================================================
-- The text box takes what the text needs and no more, leaving the list
-- room for the picks it has; a long greeting scrolls in its box.
local function DialogPane(win)
    local pane = {}
    local box = TextBox(win)
    local text = UI.Font(box.child, F.CARD, { justify = "LEFT" })
    text:SetPoint("TOPLEFT", box.child, "TOPLEFT", 0, 0)
    text:SetWordWrap(true)
    if text.SetNonSpaceWrap then text:SetNonSpaceWrap(true) end

    local list = Kit.List(win, {
        rowHeight = ROW_H,
        build = BuildDialogRow,
        update = UpdateDialogRow,
    })

    function pane:SetShown(on)
        if not on then
            box:Hide()
            list:Hide()
        else
            list:Show()
        end
    end

    function pane:Render(greeting, entries, fresh)
        greeting = greeting or ""
        local avail = ContentHeight(win)
        local cw = TextWidth(win)

        list:ClearAllPoints()
        if greeting ~= "" then
            text:SetWidth(cw)
            text:SetText(greeting)
            local th = math.ceil(text:GetStringHeight() or 12)
            -- Leave the list the rows it actually has (up to eight).
            local need = math.min(#entries, 8) * ROW_H
            local maxBox = (#entries == 0) and avail or math.max(60, avail - Kit.GAP - need)
            local bh = math.max(30, math.min(th + 2 * BOX_PAD, maxBox))
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, win.top)
            box:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, win.top)
            box:SetHeight(bh)
            box:Show()
            box.child:SetSize(cw, math.max(1, th))
            box.scroll:Recalculate(th)
            if fresh then box.bar:SetValue(0) end
            list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -Kit.GAP)
        else
            box:Hide()
            list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, win.top)
        end
        list:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)
        list:SetShown(#entries > 0 or greeting == "")
        list:SetEmptyText(greeting == "" and #entries == 0 and "Nothing to say." or nil)
        list:SetData(entries, not fresh)
    end

    pane.box, pane.list = box, list
    return pane
end

-- ============================================================
-- GOSSIP
-- ============================================================
local gwin, gpane
local gFresh = false

-- Blizzard's IsFrequentRecurring (Classic GossipFrame.lua).
local function Recurring(q)
    local QF = Enum and Enum.QuestFrequency
    if not QF or q.isMeta or not q.frequency then return false end
    return q.frequency == QF.Daily or q.frequency == QF.Weekly
        or (QF.ResetByScheduler ~= nil and q.frequency == QF.ResetByScheduler)
end

local function RecurringWord(q)
    local QF = Enum and Enum.QuestFrequency
    if QF and q.frequency == QF.Weekly then return WEEKLY or "Weekly" end
    return DAILY or "Daily"
end

-- The option label with Blizzard's "(Quest)" style prefixes
-- (GossipOptionButtonMixin:Setup).
local function OptionText(info)
    local name = info.name or ""
    local RF = Enum and Enum.GossipOptionRecFlags
    local flags = info.flags or 0
    if RF and FlagsUtil and FlagsUtil.IsSet and flags ~= 0 and GOSSIP_OPTION_PREPEND then
        local pre = {}
        if RF.QuestLabelPrepend and QUEST_PREPEND
            and Try(FlagsUtil.IsSet, flags, RF.QuestLabelPrepend) then
            pre[#pre + 1] = QUEST_PREPEND
        end
        if RF.PlayMovieLabelPrepend and PLAY_MOVIE_PREPEND
            and Try(FlagsUtil.IsSet, flags, RF.PlayMovieLabelPrepend) then
            pre[#pre + 1] = PLAY_MOVIE_PREPEND
        end
        if #pre > 0 then
            local ok, s = pcall(string.format, GOSSIP_OPTION_PREPEND, table.concat(pre, " "), name)
            if ok and s then name = s end
        end
    end
    return name
end

local function AvailableEntry(q)
    local recurring = Recurring(q)
    local tags = {}
    if q.isIgnored then tags[#tags + 1] = "Ignored" end
    if q.isTrivial then tags[#tags + 1] = "Low level" end
    if recurring then
        tags[#tags + 1] = RecurringWord(q)
    elseif q.repeatable then
        tags[#tags + 1] = "Repeatable"
    end
    local e = {
        icon = q.isLegendary and ICON_AVAILABLE_LEGEND
            or (recurring and ICON_AVAILABLE_DAILY or ICON_AVAILABLE),
        dim = (q.isTrivial or q.isIgnored) and true or false,
        text = LevelTag(q.questLevel) .. (q.title or ""),
        tag = table.concat(tags, "  "),
    }
    if not q.isIgnored and type(q.questLevel) == "number" and q.questLevel > 0 then
        e.r, e.g, e.b = DifficultyRGB(q.questLevel)
    end
    local questID = q.questID
    e.action = function() C_GossipInfo.SelectAvailableQuest(questID) end
    return e
end

local function ActiveEntry(q)
    local recurring = Recurring(q)
    local e = {
        icon = q.isLegendary and ICON_ACTIVE_LEGEND
            or (recurring and ICON_ACTIVE_DAILY or ICON_ACTIVE),
        -- isComplete is optional in the struct: only a definite "not yet"
        -- greys the icon, an unknown leaves it as Blizzard draws it.
        desat = q.isComplete == false,
        dim = (q.isTrivial or q.isIgnored) and true or false,
        text = LevelTag(q.questLevel) .. (q.title or ""),
    }
    if q.isComplete then
        e.tag, e.tagKey = COMPLETE or "Complete", "green"
    end
    if not q.isIgnored and type(q.questLevel) == "number" and q.questLevel > 0 then
        e.r, e.g, e.b = DifficultyRGB(q.questLevel)
    end
    local questID = q.questID
    e.action = function() C_GossipInfo.SelectActiveQuest(questID) end
    return e
end

local function OptionEntry(info)
    local orderIndex = info.orderIndex or 0
    return {
        icon = info.overrideIconID or info.icon,
        text = OptionText(info),
        action = function() C_GossipInfo.SelectOptionByIndex(orderIndex) end,
    }
end

-- Blizzard's order: available quests, active quests, then the options
-- sorted by orderIndex (GossipFrameSharedMixin:Update / HandleShow).
local function GossipEntries()
    local G = C_GossipInfo
    if not G then return {} end
    local avail = (G.GetAvailableQuests and G.GetAvailableQuests()) or {}
    local active = (G.GetActiveQuests and G.GetActiveQuests()) or {}
    local options = (G.GetOptions and G.GetOptions()) or {}
    table.sort(options, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)

    local sections = 0
    if #avail > 0 then sections = sections + 1 end
    if #active > 0 then sections = sections + 1 end
    if #options > 0 then sections = sections + 1 end
    local headers = sections > 1

    local data = {}
    if #avail > 0 then
        if headers then data[#data + 1] = { header = true, text = AVAILABLE_QUESTS or "Available Quests" } end
        for _, q in ipairs(avail) do data[#data + 1] = AvailableEntry(q) end
    end
    if #active > 0 then
        if headers then data[#data + 1] = { header = true, text = CURRENT_QUESTS or "Current Quests" } end
        for _, q in ipairs(active) do data[#data + 1] = ActiveEntry(q) end
    end
    if #options > 0 then
        if headers then data[#data + 1] = { header = true, text = "Options" } end
        for _, o in ipairs(options) do data[#data + 1] = OptionEntry(o) end
    end
    return data
end

local function RefreshGossip(fresh)
    -- IsVisible, not IsShown: the cover is a shown child of GossipFrame
    -- all session, and QUEST_LOG_UPDATE fires on every kill while questing.
    if not gwin or not gwin:IsVisible() then return end
    gwin:SetTitle(UnitName("npc") or "")
    local text = (C_GossipInfo and C_GossipInfo.GetText and C_GossipInfo.GetText()) or ""
    gpane:Render(text, GossipEntries(), fresh)
end

local QueueGossip = Kit.Coalesce(function()
    local fresh = gFresh
    gFresh = false
    RefreshGossip(fresh)
end, function() return gwin end)

local function CloseGossipWindow()
    CloseHost(GossipFrame, C_GossipInfo and C_GossipInfo.CloseGossip)
end

local function BuildGossip()
    if gwin then return gwin end
    gwin = Kit.Cover(GossipFrame, {
        name = "ZacUIGossipWindow",
        title = "",
        insetName = "GossipFrame",
        onClose = CloseGossipWindow,
    })

    gwin.footer = Kit.Footer(gwin, Kit.FOOTER_H)
    local goodbye = UI.Button(gwin.footer, GOODBYE or "Goodbye", { width = 96, height = 22 })
    goodbye:SetPoint("RIGHT", gwin.footer, "RIGHT", -6, 0)
    goodbye:SetScript("OnClick", CloseGossipWindow)

    gpane = DialogPane(gwin)

    local ev = CreateFrame("Frame", nil, gwin)
    ev:RegisterEvent("GOSSIP_SHOW")
    ev:RegisterEvent("GOSSIP_CLOSED")
    ev:RegisterEvent("QUEST_LOG_UPDATE")
    ev:RegisterEvent("PLAYER_LEVEL_UP")
    ev:SetScript("OnEvent", function(_, event)
        -- A new page: back to the top. Marked even while hidden, the
        -- first GOSSIP_SHOW arrives before GossipFrame has shown.
        if event == "GOSSIP_SHOW" then gFresh = true end
        if event == "GOSSIP_CLOSED" then return end
        if gwin:IsVisible() then QueueGossip() end
    end)

    -- Synchronous on show, so a second NPC never flashes the first one's
    -- page for a frame.
    gwin:HookScript("OnShow", function()
        gFresh = false
        RefreshGossip(true)
    end)
    return gwin
end

-- Pieces of GossipFrame (ButtonFrameTemplate) the cover does not hide:
-- the portrait (frame level 400) and title strip (510) draw ABOVE any
-- cover, the NineSlice corners and close button poke past its edges, and
-- GossipFrameBg is a 512x512 texture hanging far off the frame's right
-- and bottom. The rest of the frame's own art is faded with it.
local function GossipLeftovers()
    local t = {}
    local f = GossipFrame
    if not f then return t end
    local function Add(x) if x then t[#t + 1] = x end end
    Add(f.NineSlice)
    Add(f.PortraitContainer)
    Add(f.TitleContainer)
    Add(f.NameFrame)
    Add(f.CloseButton)
    Add(_G.GossipFrameCloseButton)
    Add(_G.GossipFramePortrait)
    AddRegions(t, f)
    if f.GreetingPanel then AddRegions(t, f.GreetingPanel) end
    return t
end

local function ApplyGossip()
    if not GossipFrame then return end
    if GossipEnabled() then
        BuildGossip()
        gwin.Reanchor()
        gwin:Show()
        Kit.Silence(GossipLeftovers())
        if GossipFrame:IsShown() then RefreshGossip(true) end
    elseif gwin then
        gwin:Hide()
        Kit.Unsilence(GossipLeftovers())
    end
end

-- ============================================================
-- QUEST PAGES
-- ============================================================
local qwin, qpane, docBox
local btnPrimary, btnSecondary, footHint
local qFresh = false
local lastPanel        -- the QuestFrame panel that showed last
local lastKey          -- page + quest the pane last drew
local choice           -- picked reward choice on the reward page, nil = none
local currentPage

local PANEL_ORDER = { "reward", "progress", "detail", "greeting" }
local function PanelFor(page)
    if page == "reward" then return _G.QuestFrameRewardPanel end
    if page == "progress" then return _G.QuestFrameProgressPanel end
    if page == "detail" then return _G.QuestFrameDetailPanel end
    if page == "greeting" then return _G.QuestFrameGreetingPanel end
end

local function CurrentPage()
    local p = lastPanel and PanelFor(lastPanel)
    if p and p:IsShown() then return lastPanel end
    for _, key in ipairs(PANEL_ORDER) do
        local panel = PanelFor(key)
        if panel and panel:IsShown() then return key end
    end
    return nil
end

-- ---------- the page body ----------
local fsPool, rewardPool = {}, {}
local docY, nextReward = 0, 1

local function DocWidth() return TextWidth(qwin) end

local function FS(key, size, colorKey)
    local fs = fsPool[key]
    if not fs then
        fs = UI.Font(docBox.child, size or F.CARD, { cat = "text", key = colorKey or "normal",
            justify = "LEFT" })
        fs:SetWordWrap(true)
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
        fsPool[key] = fs
    end
    return fs
end

-- One block of text at the running y, full width, measured. Empty text
-- places nothing, so a quest with no objective text leaves no hole.
local function Place(fs, text, gapAfter, colorKey)
    if not text or text == "" then return end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", docBox.child, "TOPLEFT", 0, -docY)
    fs:SetWidth(DocWidth())
    fs:SetText(text)
    if colorKey then fs._zPaintKey = colorKey end
    fs:_zPaint()
    fs:Show()
    docY = docY + math.ceil(fs:GetStringHeight() or 12) + (gapAfter or 4)
end

local function PaintChoice()
    local sel = GetColor("ui", "borderSelected")
    for _, b in ipairs(rewardPool) do
        local on = b:IsShown() and b.choosable and choice ~= nil and b.rindex == choice
        b.sel:SetVertexColor(sel.r, sel.g, sel.b, 0.22)
        b.sel:SetShown(on and true or false)
        b.ring:SetShown(on and true or false)
    end
    if footHint and currentPage == "reward" then
        local n = GetNumQuestChoices and GetNumQuestChoices() or 0
        footHint:SetText((n > 1 and not choice) and "Choose a reward" or "")
    end
end

-- Blizzard's QuestInfoRewardItemCodeTemplate_OnEnter / the spell mixin's.
local function RewardTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.kind == "item" then
        GameTooltip:SetQuestItem(self.rtype, self.rindex)
        if GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
    elseif self.kind == "spell" and self.spellID and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(self.spellID, nil, true)
    end
    GameTooltip:Show()
end

-- Blizzard's QuestInfoRewardItemCodeTemplate_OnClick: a modified click is
-- a link or a preview and never a pick; a plain click picks a choice.
local function RewardClick(self)
    if self.kind == "item" then
        if IsModifiedClick() then
            local link = GetQuestItemLink and GetQuestItemLink(self.rtype, self.rindex)
            if link then HandleModifiedItemClick(link) end
            return
        end
    elseif self.kind == "spell" then
        if IsModifiedClick("CHATLINK") and self.spellID and GetSpellLink then
            InsertChat(GetSpellLink(self.spellID))
        end
        return
    end
    if self.choosable then
        choice = self.rindex
        PaintChoice()
    end
end

local function RewardButton(i)
    local b = rewardPool[i]
    if b then return b end
    b = CreateFrame("Button", nil, docBox.child)
    b:SetSize(140, REWARD_H)
    b:RegisterForClicks("LeftButtonUp")

    -- Picked = the list's green: a tinted fill and a green ring.
    local sel = b:CreateTexture(nil, "BORDER")
    sel._zui_own = true
    sel:SetAllPoints()
    sel:SetTexture(FLAT)
    sel:Hide()
    b.sel = sel
    local ring = CreateFrame("Frame", nil, b)
    ring:SetAllPoints()
    UI.Border(ring, "ui", "borderSelected")
    ring._zPaint = UI.PaintBox
    ring:_zPaint()
    ring:Hide()
    b.ring = ring

    b.icon = Kit.Icon(b, REWARD_H - 2)
    b.icon:SetPoint("LEFT", b, "LEFT", 1, 0)

    b.name = UI.Font(b, F.SMALL, { justify = "LEFT" })
    b.sub = UI.Font(b, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    b.sub:SetWordWrap(false)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl._zui_own = true
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    b:SetScript("OnEnter", function(self)
        RewardTooltip(self)
        self.UpdateTooltip = RewardTooltip
    end)
    b:SetScript("OnLeave", function(self)
        self.UpdateTooltip = nil
        GameTooltip:Hide()
        if ResetCursor then ResetCursor() end
    end)
    b:SetScript("OnClick", RewardClick)
    rewardPool[i] = b
    return b
end

-- Two per row like Blizzard's grid, starting at the running y. A line
-- under the name (the required-item count) gets its own string, so the
-- name then stays on one line above it.
local function PlaceRewards(entries)
    if #entries == 0 then return end
    local cw = DocWidth()
    local w = math.floor((cw - 4) / 2)
    for k, r in ipairs(entries) do
        local b = RewardButton(nextReward)
        nextReward = nextReward + 1
        local col = (k - 1) % 2
        local row = math.floor((k - 1) / 2)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", docBox.child, "TOPLEFT", col * (w + 4), -(docY + row * (REWARD_H + 4)))
        b:SetWidth(w)
        b.kind, b.rtype, b.rindex, b.spellID = r.kind, r.rtype, r.rindex, r.spellID
        b.choosable = r.choosable and true or false
        b.icon:SetIcon(r.texture)
        b.icon:SetCount(r.count)
        local q = (type(r.quality) == "number" and r.quality >= 0) and r.quality or nil
        b.icon:SetQuality(q)
        b.icon:SetUsable(r.usable ~= false)

        b.name:ClearAllPoints()
        b.sub:ClearAllPoints()
        if r.sub then
            -- Top pair / bottom pair: a lone RIGHT point would pin each
            -- string's vertical centre to the button's and stretch both
            -- boxes over each other.
            b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 6, -3)
            b.name:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -4)
            b.name:SetJustifyV("TOP")
            b.name:SetWordWrap(false)
            b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 6, 3)
            b.sub:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 4)
            b.sub:SetJustifyV("BOTTOM")
            b.sub:SetText(r.sub)
            b.sub._zPaintKey = r.subKey or "gray"
            b.sub:_zPaint()
            b.sub:Show()
        else
            b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
            b.name:SetPoint("RIGHT", b, "RIGHT", -2, 0)
            b.name:SetJustifyV("MIDDLE")
            b.name:SetWordWrap(true)
            if b.name.SetMaxLines then b.name:SetMaxLines(2) end
            b.sub:Hide()
        end
        b.name:SetText(r.name or "")
        if r.usable == false then
            b.name:SetTextColor(Kit.TextRGB("red"))
        elseif q then
            b.name:SetTextColor(ns.QualityRGB(q))
        else
            b.name._zPaintKey = "normal"
            b.name:_zPaint()
        end
        b:Show()
    end
    docY = docY + math.ceil(#entries / 2) * (REWARD_H + 4) + 6
    -- the coin on the reward that sells for most (Win_QuestRewards), when on
    if ns.QuestRewardMark and ns.QuestRewardMark.MarkOwn then pcall(ns.QuestRewardMark.MarkOwn, rewardPool) end
end

local function QuestItems(rtype, n, choosable)
    local out = {}
    for i = 1, n do
        local name, texture, numItems, quality, isUsable = GetQuestItemInfo(rtype, i)
        out[#out + 1] = {
            kind = "item", rtype = rtype, rindex = i, name = name, texture = texture,
            count = numItems, quality = quality, usable = isUsable and true or false,
            choosable = choosable,
        }
    end
    return out
end

-- Spell rewards the way Vanilla QuestInfo_ShowRewards buckets them: only
-- spells you do not already know, grouped under Blizzard's own headings.
local function KnowsSpell(spellID)
    local SB = C_SpellBook
    if SB and SB.IsSpellInSpellBook and Enum and Enum.SpellBookSpellBank then
        return Try(SB.IsSpellInSpellBook, spellID, Enum.SpellBookSpellBank.Player, true) and true or false
    end
    return false
end

local function SpellRewards(questID)
    local sys = C_QuestInfoSystem
    if not (questID and sys and sys.GetQuestRewardSpells and sys.GetQuestRewardSpellInfo) then
        return {}
    end
    local spells = Try(sys.GetQuestRewardSpells, questID)
    if type(spells) ~= "table" then return {} end
    local buckets = { tradeskill = {}, aura = {}, spell = {}, unlock = {} }
    for _, spellID in ipairs(spells) do
        local info = Try(sys.GetQuestRewardSpellInfo, questID, spellID)
        if type(info) == "table" and info.texture and not info.isBoostSpell
            and not info.garrFollowerID and not KnowsSpell(spellID) then
            local kind = "aura"
            if info.isTradeskillSpell or info.isTradeskill then kind = "tradeskill"
            elseif info.isSpellLearned then kind = "spell"
            elseif info.genericUnlock then kind = "unlock" end
            local list = buckets[kind]
            list[#list + 1] = {
                kind = "spell", spellID = spellID, name = info.name, texture = info.texture,
                hideHeader = info.hideSpellLearnText and true or false,
            }
        end
    end
    local out = {}
    local order = {
        { "tradeskill", REWARD_TRADESKILL_SPELL or "You will learn how to create:" },
        { "aura",       REWARD_AURA or "The following will be cast on you:" },
        { "spell",      REWARD_SPELL or "You will learn the following:" },
        { "unlock",     REWARD_UNLOCK or "You will unlock access to the following:" },
    }
    for _, o in ipairs(order) do
        local list = buckets[o[1]]
        if #list > 0 then out[#out + 1] = { header = o[2], spells = list } end
    end
    return out
end

-- Rewards, in Blizzard's order: choices, spells, then the rest (money and
-- the fixed items). On the reward page the choices can be picked.
local function PlaceRewardSection(rewardPage)
    local numChoices = GetNumQuestChoices() or 0
    local numRewards = GetNumQuestRewards() or 0
    local money = GetRewardMoney() or 0
    local spellGroups = SpellRewards(GetQuestID and GetQuestID())
    if numChoices + numRewards + money == 0 and #spellGroups == 0 then return end

    Place(FS("rewHead", F.HEADER, "gold"), QUEST_REWARDS or "Rewards", 6)
    if numChoices > 0 then
        local label
        if numChoices == 1 then
            label = REWARD_ITEMS_ONLY or "You will receive:"
        elseif rewardPage then
            label = REWARD_CHOOSE or "Choose your reward:"
        else
            label = REWARD_CHOICES or "You will be able to choose one of these rewards:"
        end
        Place(FS("choose", F.LABEL, "gray"), label, 4)
        PlaceRewards(QuestItems("choice", numChoices, rewardPage and numChoices > 1))
    end
    for gi, g in ipairs(spellGroups) do
        if not g.spells[1].hideHeader then
            Place(FS("spellHead" .. gi, F.LABEL, "gray"), g.header, 4)
        end
        PlaceRewards(g.spells)
    end
    if numRewards > 0 or money > 0 then
        local receive = (numChoices > 0 or #spellGroups > 0) and (REWARD_ITEMS or "You will also receive:")
            or (REWARD_ITEMS_ONLY or "You will receive:")
        Place(FS("receive", F.LABEL, "gray"), receive, 4)
        if money > 0 then Place(FS("money", F.LABEL), ns.Money(money), 6) end
        PlaceRewards(QuestItems("reward", numRewards, false))
    end
end

-- A quest that teaches a spell as its objective (QuestInfo_ShowSpecialObjectives).
local function PlaceCriteriaSpell()
    local spellID, spellName, spellTexture = Try(GetCriteriaSpell)
    if not spellID then return end
    Place(FS("learnObj", F.LABEL, "gray"), LEARN_SPELL_OBJECTIVE or "Learn Spell:", 4)
    PlaceRewards({ { kind = "spell", spellID = spellID, name = spellName, texture = spellTexture } })
end

-- Blizzard's QuestFrameProgressItems_Update: the visible required items,
-- plus what you are carrying of each.
local function RequiredItems()
    local out = {}
    local n = GetNumQuestItems and GetNumQuestItems() or 0
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    for i = 1, n do
        local hidden = IsQuestItemHidden and IsQuestItemHidden(i)
        if hidden == 0 or hidden == nil or hidden == false then
            local name, texture, numItems = GetQuestItemInfo("required", i)
            local e = {
                kind = "item", rtype = "required", rindex = i, name = name,
                texture = texture, count = numItems,
            }
            local link = GetQuestItemLink and GetQuestItemLink("required", i)
            local have = link and count and Try(count, link)
            if type(have) == "number" and type(numItems) == "number" then
                e.sub = "Have " .. have .. " / " .. numItems
                e.subKey = (have >= numItems) and "green" or "red"
            end
            out[#out + 1] = e
        end
    end
    return out
end

local function HideDoc()
    for _, fs in pairs(fsPool) do fs:Hide() end
    for _, b in ipairs(rewardPool) do b:Hide() end
end

local function RenderDoc(page, fresh)
    HideDoc()
    docY, nextReward = 0, 1
    local cw = DocWidth()

    Place(FS("title", F.HEADER, "gold"), GetTitleText and GetTitleText() or "", 6)
    if page == "detail" then
        Place(FS("body"), GetQuestText and GetQuestText() or "", 12)
        Place(FS("objHead", F.HEADER, "gold"), QUEST_OBJECTIVES or "Quest Objectives", 6)
        Place(FS("objText"), GetObjectiveText and GetObjectiveText() or "", 12)
        PlaceCriteriaSpell()
        PlaceRewardSection(false)
    elseif page == "progress" then
        Place(FS("body"), GetProgressText and GetProgressText() or "", 12)
        local items = RequiredItems()
        local money = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
        if #items > 0 or money > 0 then
            Place(FS("reqHead", F.HEADER, "gold"), TURN_IN_ITEMS or "Required items:", 6)
        end
        if money > 0 then
            Place(FS("reqMoney", F.LABEL), (REQUIRED_MONEY or "Required Money:") .. " " .. ns.Money(money),
                6, money > GetMoney() and "red" or "normal")
        end
        PlaceRewards(items)
    elseif page == "reward" then
        Place(FS("body"), GetRewardText and GetRewardText() or "", 12)
        PlaceRewardSection(true)
    end

    local h = math.max(1, docY + 4)
    docBox.child:SetSize(cw, h)
    docBox.scroll:Recalculate(h)
    if fresh then docBox.bar:SetValue(0) end
    PaintChoice()
end

-- ---------- the greeting page (several quests from one NPC) ----------
-- Blizzard's QuestFrameGreetingPanel_OnShow: current quests first, then
-- the ones on offer; the click is QuestTitleButton_OnClick.
local function GreetingEntries()
    local data = {}
    local numActive = GetNumActiveQuests and GetNumActiveQuests() or 0
    local numAvail = GetNumAvailableQuests and GetNumAvailableQuests() or 0
    if numActive > 0 then
        data[#data + 1] = { header = true, text = CURRENT_QUESTS or "Current Quests" }
        for i = 1, numActive do
            local title, isComplete = GetActiveTitle(i)
            local level = Try(GetActiveLevel, i)
            local trivial = Try(IsActiveQuestTrivial, i)
            local e = {
                icon = ICON_ACTIVE,
                desat = isComplete == false,
                dim = trivial and true or false,
                text = LevelTag(level) .. (title or ""),
            }
            if isComplete then e.tag, e.tagKey = COMPLETE or "Complete", "green" end
            if type(level) == "number" and level > 0 then e.r, e.g, e.b = DifficultyRGB(level) end
            local index = i
            e.action = function()
                SelectActiveQuest(index)
                Sound("IG_QUEST_LIST_SELECT")
            end
            data[#data + 1] = e
        end
    end
    if numAvail > 0 then
        data[#data + 1] = { header = true, text = AVAILABLE_QUESTS or "Available Quests" }
        for i = 1, numAvail do
            local title = GetAvailableTitle(i)
            local level = Try(GetAvailableLevel, i)
            -- 1.15 answers the second value as a daily flag or a frequency.
            local isTrivial, freq, isRepeatable, isLegendary = Try(GetAvailableQuestInfo, i)
            local daily = (freq == true) or (type(freq) == "number" and freq > 0)
            local tags = {}
            if isTrivial then tags[#tags + 1] = "Low level" end
            if daily then
                tags[#tags + 1] = DAILY or "Daily"
            elseif isRepeatable then
                tags[#tags + 1] = "Repeatable"
            end
            local e = {
                icon = isLegendary and ICON_AVAILABLE_LEGEND
                    or (daily and ICON_AVAILABLE_DAILY or ICON_AVAILABLE),
                dim = isTrivial and true or false,
                text = LevelTag(level) .. (title or ""),
                tag = table.concat(tags, "  "),
            }
            if type(level) == "number" and level > 0 then e.r, e.g, e.b = DifficultyRGB(level) end
            local index = i
            e.action = function()
                SelectAvailableQuest(index)
                Sound("IG_QUEST_LIST_SELECT")
            end
            data[#data + 1] = e
        end
    end
    return data
end

-- ---------- footer ----------
local function Accept()
    if QuestDetailAcceptButton_OnClick then QuestDetailAcceptButton_OnClick() else AcceptQuest() end
end

local function Decline()
    if QuestDetailDeclineButton_OnClick then
        QuestDetailDeclineButton_OnClick()
    else
        DeclineQuest()
        Sound("IG_QUEST_CANCEL")
    end
end

local function Continue()
    if IsQuestCompletable and not IsQuestCompletable() then return end
    if QuestProgressCompleteButton_OnClick then
        QuestProgressCompleteButton_OnClick()
    else
        CompleteQuest()
        Sound("IG_QUEST_LIST_OPEN")
    end
end

local function ProgressCancel()
    if QuestGoodbyeButton_OnClick then
        QuestGoodbyeButton_OnClick()
    else
        DeclineQuest()
        Sound("IG_QUEST_CANCEL")
    end
end

-- Blizzard's QuestRewardCompleteButton_OnClick, Era branch, with our pick
-- in place of QuestInfoFrame.itemChoice (written to Blizzard's table it
-- would only taint it): one choice is taken for you, several need a pick
-- first - Blizzard's own "choose a reward" error - and Era has no
-- expensive-quest prompt (that popup is TBC and later).
local function CompleteReward()
    local n = GetNumQuestChoices() or 0
    local c = choice or 0
    if n == 1 then c = 1 end
    if c == 0 and n > 0 then
        if QuestChooseRewardError then QuestChooseRewardError() end
        return
    end
    GetQuestReward(c)
end

local function RewardCancel()
    if QuestRewardCancelButton_OnClick then
        QuestRewardCancelButton_OnClick()
    else
        DeclineQuest()
        Sound("IG_QUEST_CANCEL")
    end
end

local function CloseQuestWindow()
    CloseHost(QuestFrame, CloseQuest)
end

local FOOTER = {
    greeting = { nil, nil, GOODBYE or "Goodbye", CloseQuestWindow },
    detail   = { ACCEPT or "Accept", Accept, DECLINE or "Decline", Decline },
    progress = { CONTINUE or "Continue", Continue, CANCEL or "Cancel", ProgressCancel },
    reward   = { COMPLETE_QUEST or "Complete Quest", CompleteReward, CANCEL or "Cancel", RewardCancel },
}

local function UpdateFooter(page)
    local spec = page and FOOTER[page]
    footHint:SetText("")
    if not spec then
        btnPrimary:Hide()
        btnSecondary:Hide()
        return
    end
    btnPrimary:SetShown(spec[1] ~= nil)
    if spec[1] then btnPrimary:SetLabel(spec[1]) end
    btnSecondary:SetShown(spec[3] ~= nil)
    if spec[3] then btnSecondary:SetLabel(spec[3]) end
    -- Blizzard's rule (QuestFrameProgressPanel_OnShow): Continue only
    -- once the quest can be handed in.
    if page == "progress" then
        local ok = not IsQuestCompletable or IsQuestCompletable()
        btnPrimary:SetDisabled(not ok)
        if not ok then footHint:SetText("Not complete yet") end
    else
        btnPrimary:SetDisabled(false)
    end
    if page == "reward" then PaintChoice() end
end

-- ---------- refresh ----------
local function RefreshQuest(fresh)
    if not qwin or not qwin:IsVisible() then return end
    local page = CurrentPage()
    -- A different page or a different quest starts at the top with no
    -- reward picked, like Blizzard's panel OnShow; a refresh of the same
    -- page (item info arriving, a bag change) keeps your place and pick.
    local key = (page or "") .. ":" .. tostring(GetQuestID and GetQuestID() or 0)
        .. ":" .. tostring(GetTitleText and GetTitleText() or "")
    if key ~= lastKey then fresh = true end
    lastKey = key
    if fresh then choice = nil end
    currentPage = page

    qwin:SetTitle(UnitName("questnpc") or "Quest")
    if page == "greeting" then
        docBox:Hide()
        qpane:SetShown(true)
        qpane:Render(GetGreetingText and GetGreetingText() or "", GreetingEntries(), fresh)
    else
        qpane:SetShown(false)
        if page then
            docBox:Show()
            RenderDoc(page, fresh)
        else
            docBox:Hide()
        end
    end
    UpdateFooter(page)
end

local QueueQuest = Kit.Coalesce(function()
    local fresh = qFresh
    qFresh = false
    RefreshQuest(fresh)
end, function() return qwin end)

local function BuildQuest()
    if qwin then return qwin end
    qwin = Kit.Cover(QuestFrame, {
        name = "ZacUIQuestDialogWindow",
        title = "",
        insetName = "QuestFrame",
        onClose = CloseQuestWindow,
    })

    qwin.footer = Kit.Footer(qwin, Kit.FOOTER_H)
    btnPrimary = UI.Button(qwin.footer, "", { width = 118, height = 22 })
    btnPrimary:SetPoint("LEFT", qwin.footer, "LEFT", 6, 0)
    btnSecondary = UI.Button(qwin.footer, "", { width = 96, height = 22 })
    btnSecondary:SetPoint("RIGHT", qwin.footer, "RIGHT", -6, 0)
    -- The action is looked up at click time from the page Blizzard is on,
    -- so a click can never act on a page that has just been swapped out.
    btnPrimary:SetScript("OnClick", function()
        local spec = FOOTER[CurrentPage() or ""]
        if spec and spec[2] then spec[2]() end
    end)
    btnSecondary:SetScript("OnClick", function()
        local spec = FOOTER[CurrentPage() or ""]
        if spec and spec[4] then spec[4]() end
    end)

    footHint = UI.Font(qwin.footer, F.SMALL, { cat = "text", key = "gray", justify = "CENTER" })
    footHint:SetPoint("LEFT", btnPrimary, "RIGHT", 6, 0)
    footHint:SetPoint("RIGHT", btnSecondary, "LEFT", -6, 0)
    footHint:SetWordWrap(false)

    -- The offer / hand-in / reward pages: one scrolling document.
    docBox = TextBox(qwin)
    docBox:SetPoint("TOPLEFT", qwin, "TOPLEFT", Kit.PAD, qwin.top)
    docBox:SetPoint("BOTTOMRIGHT", qwin.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)
    docBox:Hide()

    -- The greeting page: text over a list, like gossip.
    qpane = DialogPane(qwin)
    qpane:SetShown(false)

    local ev = CreateFrame("Frame", nil, qwin)
    for _, e in ipairs({ "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
                         "QUEST_FINISHED", "QUEST_ITEM_UPDATE", "QUEST_LOG_UPDATE",
                         "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED", "PLAYER_MONEY",
                         "PLAYER_LEVEL_UP" }) do
        ev:RegisterEvent(e)
    end
    ev:SetScript("OnEvent", function(_, event)
        if event == "QUEST_GREETING" or event == "QUEST_DETAIL"
            or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
            qFresh = true
        end
        if event == "QUEST_FINISHED" then
            choice = nil
            return
        end
        if qwin:IsVisible() then QueueQuest() end
    end)

    -- Blizzard swaps pages by showing a panel; that is the page now.
    for _, key in ipairs(PANEL_ORDER) do
        local panel = PanelFor(key)
        if panel then
            panel:HookScript("OnShow", function()
                lastPanel = key
                qFresh = true
                if qwin:IsVisible() then QueueQuest() end
            end)
        end
    end

    qwin:HookScript("OnShow", function()
        qFresh = false
        lastKey = nil
        RefreshQuest(true)
    end)
    qwin:HookScript("OnHide", function()
        choice = nil
        lastKey = nil
    end)
    return qwin
end

-- Pieces of QuestFrame the cover does not hide: the NPC portrait and the
-- close button poke past its corner, and every panel's parchment and
-- material art runs out into the transparent margin round the cover.
-- (The giver's 3D model is handled by HideGiverModel below.)
local function QuestLeftovers()
    local t = {}
    local function Add(x) if x then t[#t + 1] = x end end
    Add(_G.QuestFrameCloseButton)
    Add(_G.QuestFramePortrait)
    if QuestFrame then AddRegions(t, QuestFrame) end
    for _, key in ipairs(PANEL_ORDER) do AddRegions(t, PanelFor(key)) end
    return t
end

-- The quest giver's 3D model (QuestNPCModel) hangs off QuestFrame's right
-- edge, outside any cover, and carries mouse-enabled children (a name
-- tooltip, a text scroll) that fading alone would leave hoverable. It is
-- not a session frame and nothing secure touches it, so it is simply hidden
-- whenever Blizzard parents it to QuestFrame while the window is on.
local function HideGiverModel()
    local model = _G.QuestNPCModel
    if model and model:IsShown() and model:GetParent() == QuestFrame
        and QuestEnabled() and qwin and qwin:IsShown() then
        model:Hide()
    end
end

local function ApplyQuest()
    if not QuestFrame then return end
    if QuestEnabled() then
        BuildQuest()
        qwin.Reanchor()
        qwin:Show()
        Kit.Silence(QuestLeftovers())
        HideGiverModel()
        if QuestFrame:IsShown() then RefreshQuest(true) end
    elseif qwin then
        qwin:Hide()
        Kit.Unsilence(QuestLeftovers())
    end
end

-- ============================================================
-- MODULES
-- ============================================================
Modules.gossipwin = function()
    if not GossipFrame or ns._zGossipWin then return end
    ns._zGossipWin = true
    ApplyGossip()
    -- A later /zui toggle only flips the saved flag; the window checks it
    -- on every open so turning it off never needs a reload.
    GossipFrame:HookScript("OnShow", ApplyGossip)
end

Modules.questdialogwin = function()
    if not QuestFrame or ns._zQuestDialogWin then return end
    ns._zQuestDialogWin = true
    ApplyQuest()
    QuestFrame:HookScript("OnShow", ApplyQuest)
    -- Blizzard shows the model from each page's OnShow; hide it right
    -- after, in the same call, so it never draws a frame.
    if type(QuestFrame_ShowQuestPortrait) == "function" then
        hooksecurefunc("QuestFrame_ShowQuestPortrait", HideGiverModel)
    end
    -- QuestFrame_SetMaterial Show()s and retextures the stone / marble /
    -- bronze art on every page; fade it again each time.
    if type(QuestFrame_SetMaterial) == "function" then
        hooksecurefunc("QuestFrame_SetMaterial", function(frame)
            if not (QuestEnabled() and qwin and qwin:IsShown()) then return end
            local n = frame and frame.GetName and frame:GetName()
            if not n then return end
            local t = {}
            for _, sfx in ipairs({ "MaterialTopLeft", "MaterialTopRight",
                                   "MaterialBotLeft", "MaterialBotRight" }) do
                if _G[n .. sfx] then t[#t + 1] = _G[n .. sfx] end
            end
            Kit.Silence(t)
        end)
    end
end
