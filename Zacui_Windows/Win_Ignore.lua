-- Win_Ignore - ZacUI's Ignore page: a searchable list of the players you
-- ignore (and the Battle.net accounts whose invites you block) in place
-- of Blizzard's fixed nineteen-row page.
-- Part of ZacUI; load order is set by the TOC.
--
-- ONE COVER, ON IgnoreListFrame. The Friends tab has two sub-pages behind
-- Blizzard's Friends / Ignore header tabs, and they are SEPARATE frames:
-- FriendsFrame_Update shows FriendsListFrame for the first and
-- IgnoreListFrame for the second (FriendsFrame_ShowSubFrame hides every
-- other one). Win_Social's friends cover lives on FriendsListFrame, this
-- one on IgnoreListFrame, so exactly one of them is ever on screen and
-- they cannot overlap.
--
-- THE HEADER STAYS BLIZZARD'S, as on every FriendsFrame page (see
-- Win_Social): the cover starts just under the Friends / Ignore tabs, so
-- the title, Blizzard's secure X and the tabs themselves stay usable, and
-- nothing here is a secure frame.
--
-- NOTHING HERE WRITES BLIZZARD'S SELECTION. Blizzard keeps the ignore
-- selection in FriendsFrame.selectedSquelchType plus the client
-- (SetSelectedIgnore / BNSetSelectedBlock); a field written on the
-- protected FriendsFrame by an addon would taint it. The selection is
-- kept locally and the Remove button acts on the NAME (or block id) in
-- hand - an index could point at somebody else once the list reorders.
--
--   Click             select
--   Ignore Player     your target if it is a friendly player, else the
--                     name prompt (Blizzard's own button logic)
--   Remove            unignore / unblock the selected entry

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

local F = UI.F

-- The server's cap on the ignore list. The client exposes no constant
-- or API for it; it has been 50 on every Classic client.
local IGNORE_MAX = 50
local ROW_H = 20

-- Kinds of entry, matching Blizzard's SQUELCH_TYPE_* split.
local KIND_HEADER, KIND_IGNORE, KIND_BLOCK = "header", "ignore", "block"

local ig = { query = "" }

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.ignorewin ~= false
end


-- ============================================================
-- DATA
-- ============================================================
-- Blizzard's order (IgnoreList_Update): the ignored names under an
-- "Ignored" header, then Battle.net blocks under "Blocked Invites".
-- A header only appears when its section has something that matches.
local function Rows()
    local data = {}
    local numIgnores = C_FriendList.GetNumIgnores() or 0
    local numBlocks = BNGetNumBlocked and BNGetNumBlocked() or 0

    local section = {}
    for i = 1, numIgnores do
        local name = C_FriendList.GetIgnoreName(i)
        if name and Kit.Matches(ig.query, name) then
            section[#section + 1] = { kind = KIND_IGNORE, key = "i:" .. name, name = name, index = i }
        end
    end
    if #section > 0 then
        data[#data + 1] = { kind = KIND_HEADER, key = "h:i", name = IGNORED or "Ignored" }
        for _, e in ipairs(section) do data[#data + 1] = e end
    end

    section = {}
    if BNGetBlockedInfo then
        for i = 1, numBlocks do
            local blockID, blockName = BNGetBlockedInfo(i)
            if blockID and Kit.Matches(ig.query, blockName) then
                section[#section + 1] = {
                    kind = KIND_BLOCK, key = "b:" .. tostring(blockID),
                    name = blockName or (UNKNOWN or "Unknown"), blockID = blockID,
                }
            end
        end
    end
    if #section > 0 then
        data[#data + 1] = { kind = KIND_HEADER, key = "h:b", name = BLOCKED_INVITES or "Blocked Invites" }
        for _, e in ipairs(section) do data[#data + 1] = e end
    end
    return data, numIgnores, numBlocks
end

-- Keep the selection on the same entry across a rebuild.
local function Reselect(data)
    ig.list.selected = nil
    if not ig.selKey then return end
    for _, e in ipairs(data) do
        if e.key == ig.selKey then
            ig.list.selected = e
            return
        end
    end
    ig.selKey = nil
end

local function Buttons()
    local e = ig.list and ig.list.selected
    ig.remove:SetDisabled(not (e and (e.kind == KIND_IGNORE or e.kind == KIND_BLOCK)))
end

local function Refresh(keepOffset)
    if not ig.win or not ig.win:IsVisible() then return end
    local data, numIgnores, numBlocks = Rows()
    Reselect(data)
    local total = numIgnores + numBlocks
    ig.list:SetEmptyText(total == 0 and "Nobody ignored. Use Ignore Player below." or "Nothing matches.")
    ig.list:SetData(data, keepOffset)
    local text = numIgnores .. " / " .. IGNORE_MAX
    if numBlocks > 0 then text = text .. "  |  " .. numBlocks .. " blocked" end
    ig.count:SetText(text)
    -- Blizzard's own cue that the list is full: the count turns red.
    if numIgnores >= IGNORE_MAX then
        ig.count:SetTextColor(Kit.TextRGB("red"))
    else
        ig.count:_zPaint()
    end
    Buttons()
end
-- One redraw per frame for a burst of list updates, only while shown.
local Queue = Kit.Coalesce(Refresh, function() return ig.win end, true)

-- ============================================================
-- ACTIONS
-- ============================================================
-- FriendsFrameIgnorePlayerButton's OnClick, line for line: a friendly
-- player target is ignored directly (with the realm when it is not
-- yours), anything else opens Blizzard's name prompt.
local function IgnorePlayer()
    if UnitCanCooperate("player", "target") and UnitIsPlayer("target") then
        local name, server = UnitName("target")
        local fullname = name
        if server and server ~= "" and UnitRealmRelationship
            and UnitRealmRelationship("target") ~= LE_REALM_RELATION_SAME then
            fullname = name .. "-" .. server
        end
        if fullname then
            C_FriendList.AddIgnore(fullname)
            if SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
        end
    else
        StaticPopup_Show("ADD_IGNORE")
    end
end

-- FriendsFrameUnsquelchButton_OnClick, by name / block id instead of the
-- client's selected index (see the file header). No confirmation, as
-- Blizzard's button has none.
local function RemoveSelected()
    local e = ig.list and ig.list.selected
    if not e then return end
    if e.kind == KIND_IGNORE then
        -- FriendsFrame_UnIgnore: DelIgnore reports a name that is gone.
        if not C_FriendList.DelIgnore(e.name) and UIErrorsFrame and ERR_IGNORE_NOT_FOUND then
            UIErrorsFrame:AddExternalErrorMessage(ERR_IGNORE_NOT_FOUND)
        end
    elseif e.kind == KIND_BLOCK and BNSetBlocked then
        BNSetBlocked(e.blockID, false)
    else
        return
    end
    ig.selKey = nil
    if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
    Queue()
end

-- ============================================================
-- ROWS
-- ============================================================
-- One line: a status mark and the name. Header rows reuse the same pooled
-- frame with the mark hidden and the label as a section title.
local function BuildRow(row)
    row:RegisterForClicks("LeftButtonUp")
    local mark = row:CreateTexture(nil, "ARTWORK")
    mark._zui_own = true
    mark:SetTexture(FLAT)
    mark:SetSize(6, 6)
    mark:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.mark = mark

    row.kindText = UI.Font(row, F.SMALL, { justify = "RIGHT", cat = "text", key = "gray" })
    row.kindText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.kindText:SetWordWrap(false)

    row.label = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.label:SetPoint("LEFT", row, "LEFT", 20, 0)
    row.label:SetPoint("RIGHT", row.kindText, "LEFT", -6, 0)
    row.label:SetWordWrap(false)

    -- A 1px accent rule under a section title.
    local rule = row:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 1)
    rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 1)
    row.rule = rule

    -- Kit.List's hover lift, found once so a section title can drop it.
    for _, r in ipairs({ row:GetRegions() }) do
        if r.GetDrawLayer and r:GetDrawLayer() == "HIGHLIGHT" then row.hl = r end
    end

    row:SetScript("OnClick", function(self)
        local e = self.item
        if not e or e.kind == KIND_HEADER then return end
        if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        ig.selKey = e.key
        ig.list:Select(e)
        Buttons()
    end)
end

local function UpdateRow(row, e)
    if e.kind == KIND_HEADER then
        row.mark:Hide()
        row.kindText:SetText("")
        row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.label:SetText(e.name)
        row.label:SetTextColor(Kit.TextRGB("gold"))
        local a = GetColor("ui", "accent")
        row.rule:SetVertexColor(a.r, a.g, a.b, 0.45)
        row.rule:Show()
        -- A title is not a row: no stripe, no hover lift.
        row.stripe:SetVertexColor(0, 0, 0, 0)
        if row.hl then row.hl:SetAlpha(0) end
        return
    end
    if row.hl then row.hl:SetAlpha(1) end
    row.rule:Hide()
    row.mark:Show()
    row.label:SetPoint("LEFT", row, "LEFT", 20, 0)
    row.label:SetText(e.name)
    if e.kind == KIND_BLOCK then
        row.mark:SetVertexColor(Kit.TextRGB("blue"))
        row.label:SetTextColor(Kit.TextRGB("blue"))
        row.kindText:SetText("Battle.net")
    else
        row.mark:SetVertexColor(Kit.TextRGB("red"))
        row.label:_zPaint()
        row.kindText:SetText("")
    end
end

-- ============================================================
-- WINDOW
-- ============================================================
-- Just under the skinned header's gold hairline.
local function BelowHairline(ins)
    local lineY = (ns.GetPanelLineY and ns.GetPanelLineY("FriendsFrame", nil)) or -24
    return -(ins.t or 0) + lineY - 1
end

-- Just under Blizzard's Friends / Ignore tabs, where Blizzard's own
-- list inset starts (the same line Win_Social's friends cover uses).
local function BelowFriendTabs(ins)
    -- ZacUI's Friends / Ignore strip, when it is on (Win_CharTabs).
    local strip = ns.TabStrips and ns.TabStrips.FriendsHeaderBottom
        and ns.TabStrips.FriendsHeaderBottom(ins)
    if strip then return math.min(BelowHairline(ins), strip) end
    local tab = _G.FriendsTabHeaderTab1
    local h = (tab and tab:GetHeight()) or 32
    if not h or h < 16 then h = 32 end
    return math.min(BelowHairline(ins), -(51 + h))
end

local function FooterButton(parent, label, width, onClick)
    local b = UI.Button(parent, label, { width = width, height = 22 })
    b:SetScript("OnClick", onClick)
    return b
end

local function Build()
    if ig.win then return ig.win end
    local win = Kit.Cover(IgnoreListFrame, {
        name = "ZacUIIgnoreWindow",
        insetName = "FriendsFrame",
        onClose = function() HideUIPanel(FriendsFrame) end,
    })
    ig.win = win
    -- Blizzard's header above carries the title and the (secure) X.
    win.titleBar:Hide()
    win.top = -Kit.PAD
    win.Reanchor = function()
        local ins = ns.GetPanelInset("FriendsFrame", FriendsFrame)
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", FriendsFrame, "TOPLEFT", ins.l or 0, BelowFriendTabs(ins))
        win:SetPoint("BOTTOMRIGHT", FriendsFrame, "BOTTOMRIGHT", -(ins.r or 0), ins.b or 0)
    end
    win.Reanchor()
    local y = win.top

    -- Toolbar: search on the left, the count on the right.
    ig.count = UI.Font(win, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    -- As tall as the search box, text centred: the box's RIGHT anchor
    -- below then lands on the same vertical centre as its TOPLEFT.
    ig.count:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y)
    ig.count:SetHeight(Kit.SEARCH_H)
    ig.count:SetJustifyV("MIDDLE")
    ig.count:SetWordWrap(false)
    ig.search = Kit.Search(win, 100, function(text)
        ig.query = Kit.NormalizeQuery(text)
        Refresh()
    end, "Search ignored")
    ig.search:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
    ig.search:SetPoint("RIGHT", ig.count, "LEFT", -Kit.GAP, 0)
    -- A FontString takes no mouse; the tooltip rides a frame over it.
    do
        local hit = CreateFrame("Frame", nil, win)
        hit:SetAllPoints(ig.count)
        hit:EnableMouse(true)
        UI.Tooltip(hit, "Ignore list",
            "Players ignored out of the most the server keeps (" .. IGNORE_MAX
            .. "). Battle.net blocks are counted separately.")
    end

    win.footer = Kit.Footer(win, Kit.FOOTER_H)
    ig.add = FooterButton(win.footer, IGNORE_PLAYER or "Ignore Player", 100, IgnorePlayer)
    ig.add:SetPoint("LEFT", win.footer, "LEFT", 6, 0)
    UI.Tooltip(ig.add, IGNORE_PLAYER or "Ignore Player",
        NEWBIE_TOOLTIP_IGNOREPLAYER or "Ignores your target if it is a friendly player, otherwise asks for a name.")
    ig.remove = FooterButton(win.footer, REMOVE_PLAYER or "Remove Player", 104, RemoveSelected)
    ig.remove:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    ig.remove:SetMotionScriptsWhileDisabled(true)
    UI.Tooltip(ig.remove, REMOVE_PLAYER or "Remove Player",
        NEWBIE_TOOLTIP_REMOVEPLAYER or "Stop ignoring the selected player, or unblock the selected account.")

    ig.list = Kit.List(win, {
        rowHeight = ROW_H,
        build = BuildRow,
        update = UpdateRow,
    })
    ig.list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y - Kit.SEARCH_H - Kit.GAP)
    ig.list:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("IGNORELIST_UPDATE")
    pcall(ev.RegisterEvent, ev, "BN_BLOCK_LIST_UPDATED")
    ev:SetScript("OnEvent", Queue)

    win:HookScript("OnShow", function()
        ig.query = ""
        ig.search:SetText("")
        Refresh()
    end)
    return win
end

local function Apply()
    if not FriendsFrame or not IgnoreListFrame or not C_FriendList then return end
    if Enabled() then
        Build()
        ig.win.Reanchor()
        ig.win:Show()
        if ig.win:IsVisible() then Refresh() end
    elseif ig.win then
        ig.win:Hide()
    end
end

-- ============================================================
-- MODULE
-- ============================================================
-- The toggle is read on every open of the page, so switching it off
-- never needs a reload.
Modules.ignorewin = function()
    if not FriendsFrame or not IgnoreListFrame or not C_FriendList or ns._zIgnoreWin then return end
    ns._zIgnoreWin = true
    Apply()
    IgnoreListFrame:HookScript("OnShow", Apply)
end
