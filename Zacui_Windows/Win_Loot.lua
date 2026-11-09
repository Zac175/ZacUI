-- Win_Loot - ZacUI's loot window: every slot in one list instead of
-- Blizzard's four-per-page LootFrame.
-- Part of ZacUI; load order is set by the TOC.
--
-- Built on Win_Kit's cover, parented to LootFrame and filling it, so it
-- opens, closes and moves exactly when LootFrame does - at the cursor
-- when "loot under mouse" is on, in the left panel slot when it is off.
-- LootFrame itself is sized to the list, so no invisible part of it is
-- left catching clicks around the window.
--
-- Clicks go through Blizzard's own handler with a stand-in for its loot
-- button, so the rest of Blizzard's loot flow is untouched: the bind
-- prompt for soulbound items, and - when you are the master looter -
-- the candidate list, which opens under the row you clicked.
--
--   Click (left or right)  loot the slot
--   Shift-click            link it          (HandleModifiedItemClick)
--   Ctrl-click             preview it       (HandleModifiedItemClick)
--   Loot all               every slot that is not locked or waiting for
--                          master-loot assignment
--
-- ZacUI's "faster looting" empties the corpse on LOOT_READY, before the
-- window has anything to show; the list just follows the slots as they
-- clear and LootFrame closes itself when the last one goes.

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local Kit = ns.Kit
local Modules = ns.Modules
local UI = ns.UI

local M, F = UI.M, UI.F

local WIDTH = 236
local MAX_ROWS = 10
local SLOT_ITEM = LOOT_SLOT_ITEM or 1
local SLOT_MONEY = LOOT_SLOT_MONEY or 2
local SLOT_CURRENCY = LOOT_SLOT_CURRENCY or 3
local QUEST_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
local MASTER_LOOT = (Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter) or 2
local TEX_QUEST_BANG = TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang"

local win, list, lootAll, countText, proxy
local origW, origH
local sized = false

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.lootwin ~= false
end

local function Str(name, fallback)
    local v = _G[name]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

-- Distance from the window's top edge to the middle of the first row:
-- the point the cursor should land on when the window opens under it.
local function FirstRowCenter()
    return M.TITLEBAR + Kit.PAD + math.floor(Kit.ROW_H / 2)
end

local function HeightFor(rows)
    return M.TITLEBAR + Kit.PAD + rows * Kit.ROW_H + Kit.GAP + Kit.FOOTER_H + 2
end

-- ============================================================
-- DATA
-- ============================================================
local function IsQuestLink(link)
    if not link then return false end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local classID = select(12, getInfo(link))
    return classID == QUEST_CLASS
end

-- One entry per loot slot, cleared ones included: slots keep their
-- index for the whole session, so a looted row stays an empty row and
-- nothing slides under the cursor between two clicks.
local pendingInfo = false
local function SlotEntry(slot)
    local e = { slot = slot }
    if not LootSlotHasItem(slot) then
        e.cleared = true
        return e
    end
    local texture, item, quantity, currencyID, quality, locked, isQuestItem, questID, isActive = GetLootSlotInfo(slot)
    if currencyID and CurrencyContainerUtil and CurrencyContainerUtil.GetCurrencyContainerInfo then
        local ok, n, t, q, ql = pcall(CurrencyContainerUtil.GetCurrencyContainerInfo,
            currencyID, quantity, item, texture, quality)
        if ok and n then item, texture, quantity, quality = n, t, q, ql end
    end
    -- Blizzard shows a slot with no texture yet as an empty, disabled
    -- button and looks again shortly; so do we.
    if not texture then
        e.cleared, e.waiting = true, true
        pendingInfo = true
        return e
    end
    e.type = GetLootSlotType(slot)
    e.icon, e.count, e.quality, e.locked = texture, quantity or 0, quality, locked and true or false
    if e.type == SLOT_MONEY then
        e.money = true
        e.name = string.gsub(item or "", "\n", " ")
    else
        e.name = item or ""
        e.link = GetLootSlotLink(slot)
        e.starts = questID and not isActive
        e.quest = isQuestItem or questID or IsQuestLink(e.link)
    end
    return e
end

local function Title()
    if IsFishingLoot and IsFishingLoot() then return Str("PROFESSIONS_FISHING", "Fishing") end
    if UnitExists("target") and UnitIsDead("target") then
        local n = UnitName("target")
        if n and n ~= "" then return n end
    end
    return Str("LOOT", "Loot")
end

-- ============================================================
-- REFRESH
-- ============================================================
local Queue
local retryQueued = false

local function Refresh()
    if not win or not win:IsVisible() then return end
    pendingInfo = false
    local n = GetNumLootItems() or 0
    local data, left = {}, 0
    for slot = 1, n do
        local e = SlotEntry(slot)
        data[#data + 1] = e
        if not e.cleared then left = left + 1 end
    end
    list:SetEmptyText("Nothing to loot.")
    list:SetData(data, true)
    countText:SetText(left == 0 and "" or (left .. (left == 1 and " item" or " items")))
    lootAll:SetDisabled(left == 0)
    if pendingInfo and not retryQueued then
        retryQueued = true
        C_Timer.After(0.5, function()
            retryQueued = false
            Queue()
        end)
    end
end

Queue = Kit.Coalesce(Refresh, function() return win end)

-- ============================================================
-- LOOTING
-- ============================================================
-- A named stand-in for Blizzard's loot button: LootButton_OnClick reads
-- the slot, quality, "<name>Text" and "<name>IconTexture" off it into
-- LootFrame.selected*, and MasterLooterFrame anchors under it by name.
local function Proxy()
    if proxy then return proxy end
    proxy = CreateFrame("Frame", "ZacUILootSlotProxy", win)
    proxy:EnableMouse(false)
    proxy.text = proxy:CreateFontString("ZacUILootSlotProxyText", "ARTWORK", "GameFontNormal")
    proxy.text:Hide()
    proxy.icon = proxy:CreateTexture("ZacUILootSlotProxyIconTexture", "ARTWORK")
    proxy.icon._zui_own = true
    proxy.icon:Hide()
    return proxy
end

local function LootRow(row, button)
    local e = row.item
    if not e or e.cleared then return end
    if LootButton_OnClick then
        local p = Proxy()
        p:ClearAllPoints()
        p:SetAllPoints(row)
        p.slot, p.quality = e.slot, e.quality or 0
        p.text:SetText(e.name or "")
        p.icon:SetTexture(e.icon)
        LootButton_OnClick(p, button)
    else
        if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION") end
        LootSlot(e.slot)
    end
end

-- Everything that can be taken in one go. Locked slots are someone
-- else's or mid-roll; master-loot items above the threshold wait for the
-- looter to hand them out.
local function LootEverything()
    local method = C_PartyInfo and C_PartyInfo.GetLootMethod and C_PartyInfo.GetLootMethod()
    local master = IsInGroup() and method == MASTER_LOOT
    local threshold = GetLootThreshold and GetLootThreshold()
    for slot = (GetNumLootItems() or 0), 1, -1 do
        if LootSlotHasItem(slot) then
            local _, _, _, _, quality, locked = GetLootSlotInfo(slot)
            local held = master and quality and threshold and quality >= threshold
            if not locked and not held then LootSlot(slot) end
        end
    end
end

-- ============================================================
-- ROWS
-- ============================================================
local function RowTooltip(row)
    local e = row.item
    if not e or e.cleared then return end
    -- LootItem_OnEnter: items and currency have tooltips, coin does not.
    local t = GetLootSlotType(e.slot)
    if t == SLOT_ITEM then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetLootItem(e.slot)
        if CursorUpdate then CursorUpdate(row) end
    elseif t == SLOT_CURRENCY and GameTooltip.SetLootCurrency then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetLootCurrency(e.slot)
        if CursorUpdate then CursorUpdate(row) end
    end
end

local function BuildRow(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local rh = Kit.ROW_H

    row.icon = Kit.Icon(row, rh - 4)
    row.icon:SetPoint("LEFT", 3, 0)
    row.bang = row.icon:CreateTexture(nil, "OVERLAY")
    row.bang._zui_own = true
    row.bang:SetAllPoints(row.icon.texture)
    row.bang:SetTexture(TEX_QUEST_BANG)
    row.bang:Hide()

    -- The name spans the row's full height: TOP-justified when a second
    -- line sits under it, centred when it is alone.
    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, -2)
    row.nameText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
    row.nameText:SetWordWrap(false)

    row.sub = UI.Font(row, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, 2)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.sub:SetWordWrap(false)
    row.sub:SetJustifyV("BOTTOM")

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if ResetCursor then ResetCursor() end
    end)
    row.UpdateTooltip = RowTooltip

    -- LootButtonTemplate's OnClick: a modified click only ever links or
    -- previews; it never loots.
    row:SetScript("OnClick", function(self, button)
        local e = self.item
        if not e or e.cleared then return end
        if IsModifiedClick() then
            local link = GetLootSlotLink(e.slot)
            if link then HandleModifiedItemClick(link) end
            return
        end
        LootRow(self, button)
    end)
end

local function UpdateRow(row, e)
    row.hasItem = (not e.cleared and not e.money) and 1 or nil
    if e.cleared then
        row.icon:Hide()
        row.nameText:SetText("")
        row.sub:SetText("")
        return
    end
    row.icon:Show()
    row.icon:SetIcon(e.icon)
    row.icon:SetCount(e.count)
    row.icon:SetQuality(not e.money and e.quality or nil)
    row.icon:SetUsable(not e.locked)
    row.bang:SetShown(e.starts and true or false)

    row.nameText:SetText(e.name)
    if e.money or not e.quality then
        row.nameText:_zPaint()
    else
        row.nameText:SetTextColor(ns.QualityRGB(e.quality))
    end

    local sub, key = "", "gray"
    if e.locked then
        sub, key = Str("LOCKED", "Locked"), "red"
    elseif e.starts then
        sub, key = Str("ITEM_STARTS_QUEST", "This Item Begins a Quest"), "orange"
    elseif e.quest then
        sub, key = Str("ITEM_BIND_QUEST", "Quest Item"), "orange"
    end
    row.sub:SetText(sub)
    row.sub:SetTextColor(Kit.TextRGB(key))
    row.nameText:SetJustifyV(sub ~= "" and "TOP" or "MIDDLE")
end

-- ============================================================
-- BUILD
-- ============================================================
local function Build()
    if win then return win end
    origW, origH = LootFrame:GetSize()
    win = Kit.Cover(LootFrame, {
        name = "ZacUILootWindow",
        title = Str("LOOT", "Loot"),
        insetName = "LootFrame",
        onClose = function() CloseLoot() end,
    })
    -- The cover IS the loot frame's rectangle; LootFrame is resized to
    -- fit the list, never the other way round.
    win.Reanchor = function()
        win:ClearAllPoints()
        win:SetAllPoints(LootFrame)
    end
    win.Reanchor()

    win.footer = Kit.Footer(win, Kit.FOOTER_H)
    lootAll = UI.Button(win.footer, "Loot all", { width = 80, height = 22 })
    lootAll:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    lootAll:SetScript("OnClick", LootEverything)
    UI.Tooltip(lootAll, "Loot all",
        "Take every slot that can be taken. Locked items and master-loot items waiting to be assigned are left.")

    countText = UI.Font(win.footer, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    countText:SetPoint("LEFT", win.footer, "LEFT", 8, 0)
    countText:SetPoint("RIGHT", lootAll, "LEFT", -Kit.GAP, 0)
    countText:SetWordWrap(false)

    list = Kit.List(win, {
        rowHeight = Kit.ROW_H,
        build = BuildRow,
        update = UpdateRow,
        empty = "Nothing to loot.",
    })
    list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, win.top)
    list:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("LOOT_OPENED")
    ev:RegisterEvent("LOOT_SLOT_CLEARED")
    ev:RegisterEvent("LOOT_SLOT_CHANGED")
    ev:RegisterEvent("LOOT_CLOSED")
    ev:SetScript("OnEvent", function() Queue() end)

    win:HookScript("OnShow", function()
        win:SetTitle(Title())
        Queue()
    end)
    win:HookScript("OnHide", function()
        for _, row in ipairs(list.rows) do
            if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
        end
    end)
    return win
end

-- Everything of LootFrame's that is not under the cover: the frame's
-- own art (the portrait and corners poke past its edges), the portrait
-- container at frame level 400, the X, the four page buttons and arrows
-- (they sit at fixed offsets and hang below a short list), the skin's
-- panel. Textures fade; frames fade and give up the mouse, and get their
-- exact mouse state back later.
local function Leftovers()
    local f = LootFrame
    local t = {}
    local function Add(x) if x and x ~= win then t[#t + 1] = x end end
    for _, r in ipairs({ f:GetRegions() }) do Add(r) end
    Add(f.NineSlice)
    Add(f.PortraitContainer)
    Add(f.TitleContainer)
    Add(f.CloseButton or _G.LootFrameCloseButton)
    Add(_G.LootCloseButton)  -- Era/TBC name: left showing, it drew a second X beside ours
    Add(f.Inset or _G.LootFrameInset)
    Add(f._zui_panel)
    for i = 1, (LOOTFRAME_NUMBUTTONS or 4) do Add(_G["LootButton" .. i]) end
    Add(_G.LootFrameUpButton)
    Add(_G.LootFrameDownButton)
    return t
end

-- Blizzard's leftovers go through Kit.Silence with QUIET: silenced once
-- (a repeat call leaves an already-faded piece alone) and only Frames lose
-- the mouse - textures and font strings just fade.
local QUIET = { once = true, framesOnly = true }

-- Size LootFrame (and so the cover) to this session's slot count, and
-- under the cursor put the FIRST ROW where Blizzard would have put its
-- first button. Runs after Blizzard's LootFrame_Show has placed it.
local function Fit()
    local n = GetNumLootItems() or 0
    local rows = math.max(1, math.min(n, MAX_ROWS))
    LootFrame:SetSize(WIDTH, HeightFor(rows))
    sized = true
    if n > 0 and GetCVar("lootUnderMouse") == "1" then
        local x, y = GetCursorPosition()
        local s = LootFrame:GetEffectiveScale()
        x, y = x / s, y / s
        LootFrame:ClearAllPoints()
        LootFrame:SetPoint("TOPLEFT", nil, "BOTTOMLEFT", x - 40, y + FirstRowCenter())
    end
end

local function Apply()
    if not LootFrame then return end
    if Enabled() then
        Build()
        win.Reanchor()
        win:Show()
        Kit.Silence(Leftovers(), QUIET)
        if LootFrame:IsShown() then
            Fit()
            Queue()
        end
    elseif win then
        win:Hide()
        Kit.Unsilence(Leftovers(), QUIET)
        if sized and origW and origH then
            LootFrame:SetSize(origW, origH)
            sized = false
        end
    end
end

-- ============================================================
-- MODULE
-- ============================================================
Modules.lootwin = function()
    if not LootFrame or ns._zLootWin then return end
    ns._zLootWin = true
    Apply()
    -- LootFrame_OnEvent calls this global on every LOOT_OPENED, after
    -- which the frame is shown and placed; the toggle is read every time.
    if LootFrame_Show then
        hooksecurefunc("LootFrame_Show", function() Apply() end)
    else
        LootFrame:HookScript("OnShow", function() Apply() end)
    end
end
