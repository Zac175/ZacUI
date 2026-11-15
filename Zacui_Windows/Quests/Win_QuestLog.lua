-- Win_QuestLog - ZacUI's quest log: the list on the left, the quest on
-- the right, one wide window instead of Blizzard's six-row list stacked
-- over a scroll of parchment.
-- Part of ZacUI; load order is set by the TOC.
--
-- Built on Win_Kit's cover, so it lives inside Blizzard's QuestLogFrame:
-- L, the micro button, Escape and a click in the quest tracker open and
-- close it through Blizzard's own code, and it keeps the panel's top-left
-- corner - it is just wider, growing to the right.
--
-- THE CLIENT'S SELECTION IS THE TRUTH. Every detail API (the objectives,
-- the rewards, abandon, share) reads "the selected quest", so a click
-- here is SelectQuestLogEntry and the right pane then reads the log the
-- way Blizzard's does. A selection made elsewhere (a tracker click that
-- opens the log on a quest) is simply adopted.
--
-- INDEXES MOVE. Expanding or collapsing a zone renumbers every entry
-- below it, so nothing here holds an index across a redraw: the list is
-- re-read from the log each time, and the quest you were looking at is
-- found again by its quest ID.
--
--   Click              select the quest (or open / close a zone)
--   Shift-click        track / untrack it (Blizzard's watch rules)
--   Shift-click, chat open   put its name in the chat box
--   Reward icons       tooltip; shift-click links, ctrl-click previews

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
-- Not on every game version (Core_Flavor's feature table: Retail's quest log is inside the world map):
-- this window stands down here, before it makes a frame or a module.
if ns.FeatureOn and not ns.FeatureOn("win_questlog") then return end

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local TEX_CHECK = ns.TEX_CHECK
local UI = ns.UI

local M, F = UI.M, UI.F

-- ============================================================
-- LAYOUT
-- ============================================================
-- Fixed width, so the detail pane's text width is a known number: a
-- FontString has to be given its wrap width before it can be measured.
local COVER_W   = 640
local LIST_W    = 268
local ROW_H     = 20
local BOX_PAD   = 6
local DETAIL_W  = COVER_W - 2 * Kit.PAD - LIST_W - Kit.GAP
local CONTENT_W = DETAIL_W - 2 * BOX_PAD - (M.SCROLL_W + 4)
local REWARD_H  = 34
local REWARD_W  = math.floor((CONTENT_W - 4) / 2)

local TEX_WINDOW = "Interface\\Icons\\INV_Misc_Book_08"

local win, list, search, chipOpen, chipGroup, allButton, countText
local detailBox, scroll, child, hint
local abandonBtn, shareBtn, trackBtn, footHint
local query = ""
local shownIndex, shownID       -- the quest the right pane is showing
local pendingID                 -- quest to re-find after a zone toggle
local lastRenderedID            -- detail scroll resets only on a new quest
local timerTicker

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.questlogwin ~= false
end

-- ============================================================
-- SMALL HELPERS
-- ============================================================
local function InsertChat(text)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if text and insert then return insert(text) end
end

-- Blizzard only turns a modified click into a chat insert while an edit
-- box is actually open; otherwise shift means "track".
local function ChatBoxOpen()
    if ChatFrameUtil and ChatFrameUtil.GetActiveWindow then
        return ChatFrameUtil.GetActiveWindow() and true or false
    end
    if ChatEdit_GetActiveWindow then return ChatEdit_GetActiveWindow() and true or false end
    return false
end

local function ErrorMessage(text)
    if UIErrorsFrame and text then
        local r, g, b = Kit.TextRGB("red")
        UIErrorsFrame:AddMessage(text, r, g, b, 1.0)
    end
end

local function InGroup()
    if IsInGroup then return IsInGroup() end
    return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
end

-- The level prefix quest addons made standard: [60] plain, [60+] elite,
-- [60D] dungeon, [60R] raid, [60P] PvP. The tag is the localised word
-- GetQuestLogTitle returns (Blizzard prints it as "(Elite)").
local function TagLetter(tag)
    if type(tag) ~= "string" or tag == "" then return "" end
    if (ELITE and tag == ELITE) then return "+" end
    if (RAID and tag == RAID) then return "R" end
    if (LFG_TYPE_DUNGEON and tag == LFG_TYPE_DUNGEON) then return "D" end
    if (PVP and tag == PVP) then return "P" end
    local l = string.lower(tag)
    if l == "elite" then return "+" end
    if l == "dungeon" then return "D" end
    if l == "raid" then return "R" end
    if l == "pvp" then return "P" end
    if l == "group" then return "+" end
    return ""
end

local function LevelTag(level, tag)
    if type(level) ~= "number" or level <= 0 then return "" end
    return "[" .. level .. TagLetter(tag) .. "] "
end

-- Blizzard's difficulty colours are data (QuestDifficultyColors), the one
-- place literal RGB is expected in a quest list.
local function DifficultyRGB(level)
    if type(level) == "number" and GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, level)
        if ok and c and c.r then return c.r, c.g, c.b end
    end
    return Kit.TextRGB("normal")
end

local function PartyOnQuest(index)
    local n = 0
    local members = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
    if members > 0 and IsUnitOnQuest then
        for j = 1, members do
            if IsUnitOnQuest(index, "party" .. j) then n = n + 1 end
        end
    end
    return n
end

-- ============================================================
-- DATA
-- ============================================================
-- One pass over the log: every visible entry, headers carrying their
-- quests, so the filter can keep a zone that still has a match.
local function ScanLog()
    local numEntries, numQuests = GetNumQuestLogEntries()
    numEntries, numQuests = numEntries or 0, numQuests or 0
    local blocks, quests = {}, {}
    local cur = { header = nil, quests = {} }
    blocks[1] = cur
    local headers, collapsedHeaders = 0, 0
    for i = 1, numEntries do
        local title, level, tag, isHeader, isCollapsed, isComplete, _, questID,
            _, displayQuestID = GetQuestLogTitle(i)
        if isHeader then
            if title then
                headers = headers + 1
                if isCollapsed then collapsedHeaders = collapsedHeaders + 1 end
            end
            cur = {
                header = { header = true, index = i, title = title or "",
                           collapsed = isCollapsed and true or false, count = 0 },
                quests = {},
            }
            blocks[#blocks + 1] = cur
        elseif title then
            local e = {
                index = i, title = title, level = level,
                tag = (type(tag) == "string" and tag ~= "") and tag or nil,
                complete = isComplete, questID = questID,
                displayID = displayQuestID and true or false,
                zone = cur.header and cur.header.title or "",
                watched = IsQuestWatched and IsQuestWatched(i) and true or false,
                party = PartyOnQuest(i),
            }
            cur.quests[#cur.quests + 1] = e
            quests[#quests + 1] = e
            if cur.header then cur.header.count = cur.header.count + 1 end
        end
    end
    return blocks, quests, numEntries, numQuests, headers, collapsedHeaders
end

local function BuildRows(blocks)
    local data = {}
    local onlyOpen = chipOpen and chipOpen:IsOn()
    local onlyGroup = chipGroup and chipGroup:IsOn()
    local filtering = query ~= "" or onlyOpen or onlyGroup
    for _, blk in ipairs(blocks) do
        local h = blk.header
        local keep = {}
        for _, q in ipairs(blk.quests) do
            if (not onlyOpen or q.complete ~= 1)
                and (not onlyGroup or q.tag ~= nil)
                and Kit.Matches(query, q.title, q.zone) then
                keep[#keep + 1] = q
            end
        end
        local showHeader = false
        if h then
            if not filtering or #keep > 0 then
                showHeader = true
            elseif h.collapsed then
                -- A shut zone's quests are not in the log to test. Keep it
                -- when it could hold a match: always for the chips, and
                -- for a search only when the zone name itself matches.
                showHeader = (query == "") or Kit.Matches(query, h.title)
            end
        end
        if showHeader then data[#data + 1] = h end
        for _, q in ipairs(keep) do data[#data + 1] = q end
    end
    return data
end

-- ============================================================
-- SELECTION
-- ============================================================
-- Adopt the client's selection when it is a quest; after one of our own
-- zone toggles, re-find the quest by ID; failing both, the first quest
-- (what Blizzard's QuestLog_SetFirstValidSelection does).
local function ResolveSelection(quests)
    local byIndex, byID = {}, {}
    for _, q in ipairs(quests) do
        byIndex[q.index] = q
        if q.questID then byID[q.questID] = q end
    end
    -- pendingID is not cleared here: the log may only renumber on the
    -- QUEST_LOG_UPDATE that follows the toggle, and the redraw after
    -- that event is the one that must still find the quest (see Queue).
    local pick
    if pendingID then pick = byID[pendingID] end
    if not pick then
        local cur = GetQuestLogSelection and GetQuestLogSelection() or 0
        pick = byIndex[cur]
    end
    if not pick then pick = quests[1] end
    if pick and GetQuestLogSelection() ~= pick.index then
        SelectQuestLogEntry(pick.index)
    end
    shownIndex = pick and pick.index or nil
    shownID = pick and pick.questID or nil
    return pick
end

-- The index the pane shows, re-checked against the log right before an
-- action acts on "the selected quest" - abandon must never hit a quest
-- that slid into that slot.
local function ConfirmShown()
    if not shownIndex then return false end
    local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(shownIndex)
    if not title or isHeader or questID ~= shownID then return false end
    if GetQuestLogSelection() ~= shownIndex then SelectQuestLogEntry(shownIndex) end
    return true
end

-- ============================================================
-- TRACKING (Blizzard's QuestLogTitleButton_OnClick, shift branch)
-- ============================================================
-- Returns false when Blizzard would have refused (no objectives, watch
-- list full) - its click handler stops there without selecting.
local function ToggleWatch(index)
    if IsQuestWatched(index) then
        local questID = GetQuestIDFromLogIndex and GetQuestIDFromLogIndex(index)
            or select(8, GetQuestLogTitle(index))
        if questID then
            -- Blizzard's own timer list for auto-watched quests; drop the
            -- entry so the watch does not come back on its own.
            if type(QUEST_WATCH_LIST) == "table" then
                for k = #QUEST_WATCH_LIST, 1, -1 do
                    local v = QUEST_WATCH_LIST[k]
                    if v and v.id == questID then tremove(QUEST_WATCH_LIST, k) end
                end
            end
            RemoveQuestWatch(index)
            if QuestWatch_Update then QuestWatch_Update() end
        end
        return true
    end
    if GetNumQuestLeaderBoards(index) == 0 then
        ErrorMessage(QUEST_WATCH_NO_OBJECTIVES)
        return false
    end
    local maxWatch = MAX_WATCHABLE_QUESTS or 5
    if GetNumQuestWatches() >= maxWatch then
        ErrorMessage(format(QUEST_WATCH_TOO_MANY or "You can only track %d quests.", maxWatch))
        return false
    end
    if AutoQuestWatch_Insert then
        AutoQuestWatch_Insert(index, QUEST_WATCH_NO_EXPIRE or 999)
    else
        AddQuestWatch(index)
    end
    if QuestWatch_Update then QuestWatch_Update() end
    return true
end

-- ============================================================
-- DETAIL PANE
-- ============================================================
local fsPool = {}       -- keyed FontStrings, created on first use
local objPool = {}      -- objective lines
local rewardPool = {}   -- reward buttons
local y = 0

local function FS(key, size, cat, colorKey)
    local fs = fsPool[key]
    if not fs then
        fs = UI.Font(child, size or F.LABEL, { cat = cat or "text", key = colorKey or "normal",
            justify = "LEFT" })
        fs:SetWordWrap(true)
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
        fsPool[key] = fs
    end
    return fs
end

-- One block of text at the running y, full content width, measured.
local function Place(fs, text, gapAfter, colorKey)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    fs:SetWidth(CONTENT_W)
    fs:SetText(text or "")
    if colorKey then fs._zPaintKey = colorKey end
    fs:_zPaint()
    fs:Show()
    y = y + math.ceil(fs:GetStringHeight() or 12) + (gapAfter or 4)
end

local function RewardTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.kind == "item" then
        GameTooltip:SetQuestLogItem(self.rtype, self.rindex)
    elseif self.kind == "spell" and self.spellID and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(self.spellID)
    end
    GameTooltip:Show()
end

-- Blizzard's QuestLogRewardItem_OnClick: dress-up and chat link.
-- HandleModifiedItemClick is both of those for an item link.
local function RewardClick(self)
    if self.kind == "item" then
        local link = GetQuestLogItemLink and GetQuestLogItemLink(self.rtype, self.rindex)
        if link and IsModifiedClick() then HandleModifiedItemClick(link) end
    elseif self.kind == "spell" then
        if IsModifiedClick("CHATLINK") and self.spellID and GetSpellLink then
            InsertChat(GetSpellLink(self.spellID))
        end
    end
end

local function RewardButton(i)
    local b = rewardPool[i]
    if b then return b end
    b = CreateFrame("Button", nil, child)
    b:SetSize(REWARD_W, REWARD_H)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = Kit.Icon(b, REWARD_H - 2)
    b.icon:SetPoint("LEFT", 0, 0)
    b.name = UI.Font(b, F.SMALL, { justify = "LEFT" })
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.name:SetPoint("RIGHT", b, "RIGHT", -2, 0)
    b.name:SetWordWrap(true)
    if b.name.SetMaxLines then b.name:SetMaxLines(2) end
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl._zui_own = true
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    b:SetScript("OnEnter", RewardTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", RewardClick)
    rewardPool[i] = b
    return b
end

-- Two per row like Blizzard's grid, starting at the running y.
local nextReward = 1
local function PlaceRewards(entries)
    for k, r in ipairs(entries) do
        local b = RewardButton(nextReward)
        nextReward = nextReward + 1
        local col = (k - 1) % 2
        local row = math.floor((k - 1) / 2)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", child, "TOPLEFT", col * (REWARD_W + 4), -(y + row * (REWARD_H + 4)))
        b.kind, b.rtype, b.rindex, b.spellID = r.kind, r.rtype, r.rindex, r.spellID
        b.icon:SetIcon(r.texture)
        b.icon:SetCount(r.count)
        local q = (type(r.quality) == "number" and r.quality >= 0) and r.quality or nil
        b.icon:SetQuality(q)
        b.icon:SetUsable(r.usable ~= false)
        b.name:SetText(r.name or "")
        if r.usable == false then
            b.name:SetTextColor(Kit.TextRGB("red"))
        elseif q then
            b.name:SetTextColor(ns.QualityRGB(q))
        else
            b.name:_zPaint()
        end
        b:Show()
    end
    if #entries > 0 then
        y = y + math.ceil(#entries / 2) * (REWARD_H + 4) + 4
    end
end

local function ItemRewards(count, getInfo, rtype)
    local out = {}
    for i = 1, count do
        local name, texture, numItems, quality, isUsable = getInfo(i)
        out[#out + 1] = {
            kind = "item", rtype = rtype, rindex = i, name = name, texture = texture,
            count = numItems, quality = quality, usable = isUsable and true or false,
        }
    end
    return out
end

-- Era's one spell reward, the way QuestFrameItems_Update reads it.
local function SpellReward()
    local questID = (GetQuestLogSelectedID and GetQuestLogSelectedID()) or shownID
    local sys = C_QuestInfoSystem
    if not (questID and sys and sys.GetQuestRewardSpells and sys.GetQuestRewardSpellInfo) then
        return nil
    end
    local ok, spells = pcall(sys.GetQuestRewardSpells, questID)
    if not ok or type(spells) ~= "table" or not spells[1] then return nil end
    local ok2, info = pcall(sys.GetQuestRewardSpellInfo, questID, spells[1])
    if not ok2 or type(info) ~= "table" then return nil end
    return {
        kind = "spell", spellID = spells[1], name = info.name, texture = info.texture,
        tradeskill = info.isTradeskill and true or false,
    }
end

local function TimerText(t)
    return (TIME_REMAINING or "Time remaining:") .. " " .. (SecondsToTime and SecondsToTime(t) or tostring(t))
end

local function StopTimer()
    if timerTicker then
        timerTicker:Cancel()
        timerTicker = nil
    end
end

-- Only the one line changes, so the tick never re-lays the pane out.
local function StartTimer()
    if timerTicker then return end
    timerTicker = C_Timer.NewTicker(1, function()
        local fs = fsPool.timer
        if not win or not win:IsVisible() or not fs or not fs:IsShown() then
            StopTimer()
            return
        end
        local t = GetQuestLogTimeLeft()
        if t then fs:SetText(TimerText(t)) else StopTimer() end
    end)
end

local function HideDetail()
    for _, fs in pairs(fsPool) do fs:Hide() end
    for _, fs in ipairs(objPool) do fs:Hide() end
    for _, b in ipairs(rewardPool) do b:Hide() end
end

local function RenderDetail(pick)
    HideDetail()
    y = 0
    nextReward = 1
    if not pick then
        StopTimer()
        hint:SetShown(true)
        child:SetHeight(1)
        scroll:Recalculate(1)
        lastRenderedID = nil
        return
    end
    hint:SetShown(false)

    -- Title, and the facts Blizzard spreads around the page on one line.
    local title = pick.title
    if IsCurrentQuestFailed and IsCurrentQuestFailed() then
        title = title .. " - (" .. (FAILED or "Failed") .. ")"
    end
    Place(FS("title", F.HEADER, "text", "gold"), title, 3)
    local facts = {}
    if type(pick.level) == "number" and pick.level > 0 then
        facts[#facts + 1] = (LEVEL or "Level") .. " " .. pick.level
    end
    if pick.tag then facts[#facts + 1] = pick.tag end
    if GetQuestLogGroupNum then
        local ok, n = pcall(GetQuestLogGroupNum)
        if ok and type(n) == "number" and n > 0 then
            facts[#facts + 1] = format(QUEST_SUGGESTED_GROUP_NUM or "Suggested players: %d", n)
        end
    end
    if pick.zone and pick.zone ~= "" then facts[#facts + 1] = pick.zone end
    if #facts > 0 then Place(FS("facts", F.SMALL, "text", "gray"), table.concat(facts, "  |  "), 8) end

    local description, objectives = GetQuestLogQuestText()
    if objectives and objectives ~= "" then Place(FS("objText"), objectives, 8) end

    local t = GetQuestLogTimeLeft()
    if t then
        Place(FS("timer", F.LABEL, "text", "orange"), TimerText(t), 8)
        StartTimer()
    else
        StopTimer()
    end

    -- The objectives themselves: done in green, still to do in white.
    local numObj = GetNumQuestLeaderBoards() or 0
    for i = 1, numObj do
        local text, oType, finished = GetQuestLogLeaderBoard(i)
        if not text or text == "" then text = oType or "" end
        local fs = objPool[i]
        if not fs then
            fs = UI.Font(child, F.LABEL, { justify = "LEFT" })
            fs:SetWordWrap(true)
            objPool[i] = fs
        end
        if finished then text = text .. " (" .. (COMPLETE or "Complete") .. ")" end
        Place(fs, "- " .. text, 2, finished and "green" or "normal")
    end
    if numObj > 0 then y = y + 6 end

    local required = GetQuestLogRequiredMoney and GetQuestLogRequiredMoney() or 0
    if required > 0 then
        Place(FS("reqMoney"), (REQUIRED_MONEY or "Required Money:") .. " " .. ns.Money(required), 8,
            required > GetMoney() and "red" or "normal")
    end

    if description and description ~= "" then
        Place(FS("descHead", F.CARD, "text", "gold"), QUEST_DESCRIPTION or "Description", 4)
        Place(FS("desc"), description, 10)
    end

    -- Rewards, in Blizzard's order: choices, the spell, then the rest.
    local numChoices = GetNumQuestLogChoices() or 0
    local numRewards = GetNumQuestLogRewards() or 0
    local money = GetQuestLogRewardMoney() or 0
    local spell = SpellReward()
    if numChoices + numRewards + money > 0 or spell then
        Place(FS("rewHead", F.CARD, "text", "gold"), QUEST_REWARDS or REWARDS or "Rewards", 4)
        if numChoices > 0 then
            Place(FS("choose", F.SMALL, "text", "gray"),
                REWARD_CHOICES or "You will be able to choose one of these rewards:", 4)
            PlaceRewards(ItemRewards(numChoices, GetQuestLogChoiceInfo, "choice"))
        end
        if spell then
            Place(FS("learn", F.SMALL, "text", "gray"), spell.tradeskill
                and (REWARD_TRADESKILL_SPELL or "You will learn how to create:")
                or (REWARD_SPELL or "You will learn:"), 4)
            PlaceRewards({ spell })
        end
        if numRewards > 0 or money > 0 then
            local receive = (numChoices > 0 or spell) and (REWARD_ITEMS or "You will also receive:")
                or (REWARD_ITEMS_ONLY or "You will receive:")
            Place(FS("receive", F.SMALL, "text", "gray"), receive, 4)
            if money > 0 then Place(FS("money"), ns.Money(money), 6) end
            PlaceRewards(ItemRewards(numRewards, GetQuestLogRewardInfo, "reward"))
        end
    end

    local h = math.max(1, y + 4)
    child:SetHeight(h)
    scroll:Recalculate(h)
    -- A new quest opens at the top; a refresh of the same one (an
    -- objective ticking over) keeps your place.
    if pick.questID ~= lastRenderedID then
        scroll.bar:SetValue(0)
        lastRenderedID = pick.questID
    end
end

-- ============================================================
-- FOOTER STATE
-- ============================================================
local function UpdateFooter(pick)
    local valid = pick ~= nil
    abandonBtn:SetDisabled(not valid)
    trackBtn:SetDisabled(not valid)
    if valid and pick.watched then
        trackBtn:SetLabel(UNTRACK_QUEST or "Untrack")
    else
        trackBtn:SetLabel(TRACK_QUEST or "Track")
    end
    -- Blizzard's rule, from QuestLog_Update: pushable AND in a group.
    local canShare = valid and GetQuestLogPushable and GetQuestLogPushable() and InGroup()
    shareBtn:SetDisabled(not canShare)
end

-- ============================================================
-- REFRESH
-- ============================================================
local function Refresh(keepOffset)
    -- IsVisible, not IsShown: the cover is a shown child of QuestLogFrame
    -- all session, and quest events fire constantly while you play.
    if not win or not win:IsVisible() then return end
    local blocks, quests, numEntries, numQuests, headers, collapsed = ScanLog()
    local pick = ResolveSelection(quests)
    local data = BuildRows(blocks)

    countText:SetText(format(QUEST_LOG_COUNT_TEMPLATE or "%d/%d", numQuests, MAX_QUESTLOG_QUESTS or 20))
    list:SetEmptyText(numEntries == 0 and (QUESTLOG_NO_QUESTS_TEXT or "No active quests.")
        or "Nothing matches.")
    list.selected = nil
    for _, e in ipairs(data) do
        if pick and e == pick then list.selected = e end
    end
    list:SetData(data, keepOffset)

    -- Blizzard's all-button rule: every zone shut -> offer "expand".
    allButton._zExpand = headers > 0 and collapsed == headers
    allButton:SetLabel(allButton._zExpand and "Expand all" or "Collapse all")
    allButton:SetDisabled(headers == 0)

    RenderDetail(pick)
    UpdateFooter(pick)
end

-- A zone toggle's quest is re-found on every redraw until the log has
-- sent its QUEST_LOG_UPDATE and that redraw has run; then it lapses, so
-- it can never override a selection made later from somewhere else.
local logUpdated = false
local Queue = Kit.Coalesce(function()
    Refresh(true)
    if logUpdated then
        logUpdated = false
        pendingID = nil
    end
end, function() return win end)

-- ============================================================
-- ROWS
-- ============================================================
-- Blizzard's party tooltip (QuestLog_UpdatePartyInfoTooltip), led by the
-- full title - the row may have had to cut it short.
local function RowTooltip(row)
    local e = row.item
    if not e or e.header then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(e.title, DifficultyRGB(e.level))
    local members = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
    if members > 0 and IsUnitOnQuest then
        local hi = HIGHLIGHT_FONT_COLOR_CODE or ""
        local ly = LIGHTYELLOW_FONT_COLOR_CODE or ""
        local close = FONT_COLOR_CODE_CLOSE or ""
        local any = false
        for i = 1, members do
            if IsUnitOnQuest(e.index, "party" .. i) then
                if not any then
                    GameTooltip:AddLine(hi .. (PARTY_QUEST_STATUS_ON or "Party members on quest:") .. close)
                    any = true
                end
                GameTooltip:AddLine(ly .. (UnitName("party" .. i) or "") .. close)
            end
        end
        if not any then
            GameTooltip:AddLine(hi .. (PARTY_QUEST_STATUS_NONE or "No party members on quest") .. close)
        end
    end
    if not e.watched then
        local c = GetColor("tooltip", "body")
        GameTooltip:AddLine("Shift-click to track.", c.r, c.g, c.b)
    end
    GameTooltip:Show()
end

local function ToggleHeader(e)
    pendingID = shownID
    if e.collapsed then ExpandQuestHeader(e.index) else CollapseQuestHeader(e.index) end
    Refresh(true)
end

local function BuildRow(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.toggle = UI.Font(row, F.LABEL, { cat = "text", key = "gray", justify = "CENTER" })
    row.toggle:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.toggle:SetWidth(12)

    row.status = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.status:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.status:SetWordWrap(false)

    row.party = UI.Font(row, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    row.party:SetPoint("RIGHT", row.status, "LEFT", -4, 0)
    row.party:SetWordWrap(false)

    local check = row:CreateTexture(nil, "ARTWORK")
    check._zui_own = true
    check:SetSize(12, 12)
    check:SetTexture(TEX_CHECK)
    check:SetPoint("RIGHT", row.party, "LEFT", -3, 0)
    row.check = check

    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetWordWrap(false)

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Blizzard's QuestLogTitleButton_OnClick, in its order: chat link (only
    -- with an edit box open), else shift = track, then select.
    row:SetScript("OnClick", function(self)
        local e = self.item
        if not e then return end
        if e.header then
            -- Blizzard ignores modified clicks on a zone.
            if IsModifiedClick("CHATLINK") or IsShiftKeyDown() then return end
            ToggleHeader(e)
            return
        end
        if IsModifiedClick("CHATLINK") and ChatBoxOpen() then
            local text = e.title
            if e.displayID and e.questID then text = e.questID .. " - " .. text end
            InsertChat(text)
        elseif IsShiftKeyDown() then
            if not ToggleWatch(e.index) then return end
        end
        SelectQuestLogEntry(e.index)
        shownIndex, shownID = e.index, e.questID
        pendingID = nil
        Refresh(true)
    end)
end

local function UpdateRow(row, e)
    row.nameText:ClearAllPoints()
    if e.header then
        -- Zones sit on the header colour, so they read as dividers.
        local hb = GetColor("ui", "headerBg")
        row.stripe:SetVertexColor(hb.r, hb.g, hb.b, 1)
        row.toggle:SetText(e.collapsed and "+" or "-")
        row.toggle:Show()
        row.check:Hide()
        row.party:SetText("")
        row.status:SetText(e.collapsed and "" or e.count)
        row.status._zPaintKey = "gray"
        row.status:_zPaint()
        row.nameText:SetPoint("LEFT", row, "LEFT", 16, 0)
        row.nameText:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
        row.nameText:SetText(e.title)
        row.nameText:_zPaint()
        return
    end

    row.toggle:Hide()
    local status, key = "", "gray"
    if e.complete and e.complete < 0 then
        status, key = "(" .. (FAILED or "Failed") .. ")", "red"
    elseif e.complete and e.complete > 0 then
        status, key = "(" .. (COMPLETE or "Complete") .. ")", "green"
    end
    row.status:SetText(status)
    row.status._zPaintKey = key
    row.status:_zPaint()
    row.party:SetText(e.party > 0 and ("[" .. e.party .. "]") or "")

    local c = GetColor("text", "green")
    row.check:SetVertexColor(c.r, c.g, c.b, 1)
    row.check:SetShown(e.watched)
    -- The title runs up to whatever is showing on the right, so an
    -- untracked quest does not keep an empty hole for the check.
    row.nameText:SetPoint("LEFT", row, "LEFT", 22, 0)
    if e.watched then
        row.nameText:SetPoint("RIGHT", row.check, "LEFT", -4, 0)
    else
        row.nameText:SetPoint("RIGHT", row.party, "LEFT", -4, 0)
    end
    local title = e.title
    if e.displayID and e.questID then title = e.questID .. " - " .. title end
    row.nameText:SetText(LevelTag(e.level, e.tag) .. title)
    row.nameText:SetTextColor(DifficultyRGB(e.level))
end

-- ============================================================
-- BUILD
-- ============================================================
local function CloseLog()
    -- HideUIPanel refuses addon callers in combat (UIParentPanelManager's
    -- CheckProtectedFunctionsAllowed); Escape and L still close it then.
    if InCombatLockdown() then
        ErrorMessage("Press Escape or L to close the quest log in combat.")
        return
    end
    HideUIPanel(QuestLogFrame)
end

local function Build()
    if win then return win end
    win = Kit.Cover(QuestLogFrame, {
        name = "ZacUIQuestLogWindow",
        title = QUEST_LOG or "Quest Log",
        insetName = "QuestLogFrame",
        width = COVER_W,
        onClose = CloseLog,
    })
    win:SetIcon(TEX_WINDOW)

    -- Quest count in the title bar, the title stopping short of it.
    countText = UI.Font(win.titleBar, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    countText:SetPoint("RIGHT", win.closeButton, "LEFT", -8, 0)
    countText:SetWordWrap(false)
    win.titleText:SetPoint("RIGHT", countText, "LEFT", -8, 0)

    -- Toolbar: search, expand/collapse all, two chips.
    local barY = win.top
    chipOpen = Kit.Chip(win, "Unfinished", false, function() Refresh() end,
        "Hide quests that are ready to hand in.")
    chipOpen:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, barY)
    chipGroup = Kit.Chip(win, "Group", false, function() Refresh() end,
        "Only elite, dungeon, raid and PvP quests.")
    chipGroup:SetPoint("RIGHT", chipOpen, "LEFT", -4, 0)

    allButton = UI.Button(win, "Collapse all", { height = Kit.SEARCH_H, width = 78, size = F.SMALL })
    allButton:SetPoint("RIGHT", chipGroup, "LEFT", -Kit.GAP, 0)
    allButton:SetScript("OnClick", function(self)
        pendingID = shownID
        -- Index 0 is every zone at once (QuestLogCollapseAllButton_OnClick).
        if self._zExpand then
            ExpandQuestHeader(0)
        else
            list.offset = 0
            CollapseQuestHeader(0)
        end
        Refresh(true)
    end)

    search = Kit.Search(win, 100, function(text)
        query = Kit.NormalizeQuery(text)
        Refresh()
    end, "Search quests and zones")
    search:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, barY)
    search:SetPoint("RIGHT", allButton, "LEFT", -Kit.GAP, 0)

    -- Footer: abandon on the left, track and share on the right.
    win.footer = Kit.Footer(win, Kit.FOOTER_H)

    abandonBtn = UI.Button(win.footer, ABANDON_QUEST or "Abandon", { width = 110, height = 22 })
    abandonBtn:SetPoint("LEFT", win.footer, "LEFT", 6, 0)
    abandonBtn:SetScript("OnClick", function()
        if not ConfirmShown() then Refresh(true) return end
        -- Blizzard's QuestLogFrameAbandonButton OnClick, word for word:
        -- the popups themselves call AbandonQuest on Yes.
        SetAbandonQuest()
        local items = GetAbandonQuestItems and GetAbandonQuestItems()
        if items then
            StaticPopup_Hide("ABANDON_QUEST")
            StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", GetAbandonQuestName(), items)
        else
            StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
            StaticPopup_Show("ABANDON_QUEST", GetAbandonQuestName())
        end
    end)
    if NEWBIE_TOOLTIP_ABANDONQUEST then UI.Tooltip(abandonBtn, ABANDON_QUEST or "Abandon", NEWBIE_TOOLTIP_ABANDONQUEST) end

    shareBtn = UI.Button(win.footer, SHARE_QUEST or "Share", { width = 100, height = 22 })
    shareBtn:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    shareBtn:SetScript("OnClick", function()
        if not ConfirmShown() then Refresh(true) return end
        QuestLogPushQuest()
    end)
    UI.Tooltip(shareBtn, SHARE_QUEST or "Share",
        NEWBIE_TOOLTIP_SHAREQUEST or "Offer this quest to your group. Needs a group, and a quest that can be shared.")

    trackBtn = UI.Button(win.footer, TRACK_QUEST or "Track", { width = 100, height = 22 })
    trackBtn:SetPoint("RIGHT", shareBtn, "LEFT", -4, 0)
    trackBtn:SetScript("OnClick", function()
        if not ConfirmShown() then Refresh(true) return end
        ToggleWatch(shownIndex)
        Refresh(true)
    end)
    UI.Tooltip(trackBtn, TRACK_QUEST or "Track",
        QUEST_WATCH_TOOLTIP or "Show this quest's objectives on screen.")

    footHint = UI.Font(win.footer, F.SMALL, { cat = "text", key = "gray", justify = "CENTER" })
    footHint:SetPoint("LEFT", abandonBtn, "RIGHT", 8, 0)
    footHint:SetPoint("RIGHT", trackBtn, "LEFT", -8, 0)
    footHint:SetWordWrap(false)
    footHint:SetText("Shift-click a quest to track it")

    -- Left: the list.
    local listY = barY - Kit.SEARCH_H - Kit.GAP
    list = Kit.List(win, {
        rowHeight = ROW_H,
        build = BuildRow,
        update = UpdateRow,
    })
    list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, listY)
    list:SetPoint("BOTTOMLEFT", win.footer, "TOPLEFT", Kit.PAD - 1, Kit.GAP)
    list:SetWidth(LIST_W)

    -- Right: the quest, in a scroll.
    detailBox = UI.Box(win, "ui", "cardBg")
    detailBox:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD + LIST_W + Kit.GAP, listY)
    detailBox:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)
    local s, c, bar = UI.ScrollArea(detailBox)
    scroll, child = s, c
    scroll:SetPoint("TOPLEFT", detailBox, "TOPLEFT", BOX_PAD, -BOX_PAD)
    scroll:SetPoint("BOTTOMRIGHT", detailBox, "BOTTOMRIGHT", -(BOX_PAD + M.SCROLL_W + 4), BOX_PAD)
    bar:SetPoint("TOPRIGHT", detailBox, "TOPRIGHT", -3, -3)
    bar:SetPoint("BOTTOMRIGHT", detailBox, "BOTTOMRIGHT", -3, 3)
    child:SetWidth(CONTENT_W)
    -- Range depends on the viewport height; re-measure when it settles.
    scroll:SetScript("OnSizeChanged", function(self) self:Recalculate() end)

    hint = UI.Font(detailBox, F.LABEL, { cat = "text", key = "gray", justify = "CENTER" })
    hint:SetPoint("TOP", detailBox, "TOP", 0, -30)
    hint:SetText("Select a quest to see it here.")
    hint:Hide()

    -- Events: coalesced to one redraw a frame, and only while it shows.
    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("QUEST_LOG_UPDATE")
    ev:RegisterEvent("QUEST_WATCH_UPDATE")
    ev:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    ev:RegisterEvent("PLAYER_MONEY")
    ev:RegisterEvent("PLAYER_LEVEL_UP")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    pcall(ev.RegisterEvent, ev, "PARTY_MEMBER_ENABLE")
    pcall(ev.RegisterEvent, ev, "PARTY_MEMBER_DISABLE")
    ev:SetScript("OnEvent", function(_, event)
        if not win:IsVisible() then return end
        if event == "QUEST_LOG_UPDATE" then logUpdated = true end
        Queue()
    end)
    -- Party changes (the "group" chip, who is on each quest) through the
    -- core roster: one notice per burst instead of every
    -- GROUP_ROSTER_UPDATE, and still nothing while the log is shut.
    ns.Roster.On("Win_QuestLog", function() Queue() end)
    -- Watches change without an event of their own (the tracker, other
    -- addons, the auto-watch timer); Blizzard redraws the tracker through
    -- QuestWatch_Update every time, so that is the hook.
    if type(QuestWatch_Update) == "function" then
        hooksecurefunc("QuestWatch_Update", function()
            if win and win:IsVisible() then Queue() end
        end)
    end

    win:HookScript("OnShow", function()
        query = ""
        search:SetText("")
        lastRenderedID = nil
        -- Opened on a quest (a tracker click): that selection wins.
        pendingID = nil
        Refresh()
    end)
    win:HookScript("OnHide", StopTimer)
    return win
end

-- Pieces of QuestLogFrame outside the cover: the Abandon / Share / Exit
-- row hangs below it, the close button's corner pokes above it, the
-- empty-log parchment runs far below it, and the frame's own art (book
-- icon, border) frames it when the quest log skin is off.
local function BlizzardLeftovers()
    local t = {}
    local function Add(f) if f then t[#t + 1] = f end end
    Add(_G.QuestLogFrameCloseButton)
    Add(_G.QuestLogFrameAbandonButton)
    Add(_G.QuestFramePushQuestButton)
    Add(_G.QuestFrameExitButton)
    Add(_G.EmptyQuestLogFrame)
    if QuestLogFrame then
        for _, r in ipairs({ QuestLogFrame:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") and not r._zui_own then Add(r) end
        end
    end
    return t
end

-- NOT TOLD TO THE PANEL MANAGER. Blizzard still lays the next window out
-- as if the log were 353 wide, so a second panel can open over the
-- cover's right half. Telling it otherwise means a UIPanelLayout attribute
-- written by addon code, which the secure panel manager then reads - the
-- one path that could block the spellbook or talents opening in combat.
-- Every wide ZacUI window makes the same trade.

local function Apply()
    if not QuestLogFrame then return end
    if Enabled() then
        Build()
        win.Reanchor()
        win:Show()
        Kit.Silence(BlizzardLeftovers())
        if QuestLogFrame:IsShown() then Refresh() end
    elseif win then
        win:Hide()
        StopTimer()
        Kit.Unsilence(BlizzardLeftovers())
        -- Hand Blizzard's own list back up to date.
        if QuestLogFrame:IsShown() and QuestLog_Update then QuestLog_Update() end
    end
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.questlogwin = function()
    if not QuestLogFrame or ns._zQuestLogWin then return end
    ns._zQuestLogWin = true
    Apply()
    -- A later /zui toggle only flips the saved flag; the window checks it
    -- on every open so turning it off never needs a reload.
    QuestLogFrame:HookScript("OnShow", function()
        Apply()
        if win and win:IsShown() then Refresh() end
    end)
end
