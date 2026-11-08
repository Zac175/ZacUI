-- Win_Social - ZacUI's Friends, Who and Guild pages: searchable,
-- filterable lists in place of Blizzard's fixed-row pages.
-- Part of ZacUI; load order is set by the TOC.
--
-- THREE COVERS, ONE PER SUB-PAGE. Each is a Win_Kit cover parented to
-- its own FriendsFrame sub-frame (FriendsListFrame, WhoFrame, GuildFrame),
-- so it shows exactly when Blizzard shows that page - the bottom tabs
-- (Friends / Who / Guild / Raid) switch pages through Blizzard's own code
-- and the Raid and Ignore pages stay Blizzard's (skinned).
--
-- WHY THE HEADER STAYS BLIZZARD'S. FriendsFrame becomes a PROTECTED frame
-- once the Raid page has claimed it (its member buttons are secure unit
-- buttons), and an addon cannot hide a protected panel in combat. So the
-- covers start BELOW the header: the title, Blizzard's X (a secure close
-- that works in combat) and, on the Friends page, the Battle.net bar and
-- the Friends / Ignore tabs all stay Blizzard's own. None of the covers
-- carries a secure button, so none of the sub-frames becomes protected
-- because of ZacUI.
--
-- WHY NOTHING HERE WRITES BLIZZARD'S SELECTION FIELDS. Friend and Who
-- selections are kept locally: FriendsFrame.selectedFriendType and
-- friends are read by Blizzard's OnShow before it re-lays the protected
-- Raid page, and a value written by an addon would taint that path.
-- Actions call the same functions Blizzard's buttons call, with the name
-- in hand.
--
--   Friends  click select, right-click Blizzard's friend menu,
--            Add Friend / Whisper / Invite / Remove
--   Who      type a /who query and press Enter; click a column to sort;
--            click select, right-click Blizzard's menu; Whisper /
--            Invite / Add Friend
--   Guild    click opens Blizzard's member detail panel, right-click the
--            member menu; Guild Info / Add Member / Impeach, and
--            Blizzard's own Guild Control button lifted into the footer

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

local SORT_H = 18

local function Enabled(key)
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules[key] ~= false
end

-- WHERE THE FRIENDS LIVE. Classic Era and TBC: FriendsFrame and its
-- sub-pages. WoW Forever (2026-11-07, Zac: "this looks horrible") has
-- the modern social window instead, SocialUIFrame, with a Battle.net bar
-- across its top and the Friends and Raid lists as content frames
-- (FriendsList, RaidFrame) under tabs down its right edge; no Who page
-- and no guild page (the guild went to Communities). So on Forever the
-- Friends cover hangs on SocialUIFrame.FriendsList, under the (flattened)
-- Battle.net bar, with ZacUI's title bar from Kit.ModernHeader on top.
-- BOTH WINDOWS CAN EXIST ON FOREVER, and the game picks which one opens
-- (a server-side switch that can flip mid-session). So the Friends cover
-- is not tied to one: it hangs on whichever friends list is showing,
-- moving between the two hosts as they open (ApplyFriends). The mode in
-- use is the one the cover sits in now.
local socialMode                     -- "modern" (SocialUIFrame) | nil (FriendsFrame)
local function Modern() return socialMode == "modern" end
local function Panel()
    if Modern() then return _G.SocialUIFrame end
    return _G.FriendsFrame
end
local function ModernList()
    local sui = _G.SocialUIFrame
    local list = sui and rawget(sui, "FriendsList")
    return type(list) == "table" and list or nil
end
-- every friends list the client has (classic, modern), and the one to use
-- now: the host showing, else the one the cover is already in, else the
-- modern one, else the classic
local function FriendsHosts()
    local t = {}
    if _G.FriendsListFrame then t[#t + 1] = _G.FriendsListFrame end
    local m = ModernList()
    if m then t[#t + 1] = m end
    return t
end
local fr = { query = "" }
local function FriendsHost(shown)
    if shown then return shown end
    for _, h in ipairs(FriendsHosts()) do if h:IsVisible() then return h end end
    if fr.host then return fr.host end
    return ModernList() or _G.FriendsListFrame
end
local function SetFriendsHost(host)
    fr.host = host
    socialMode = (host ~= nil and host == ModernList()) and "modern" or nil
end

-- ============================================================
-- SHARED HELPERS
-- ============================================================
-- Class colour from Blizzard's own table. Friends and Battle.net report
-- the LOCALISED class name, so it is mapped back to the class file once.
local classByName
local function ClassFile(localized)
    if not localized then return nil end
    if not classByName then
        classByName = {}
        for file, loc in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classByName[loc] = file end
        for file, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classByName[loc] = file end
    end
    return classByName[localized]
end

local ClassRGB = Kit.ClassRGB

-- The calls Blizzard's own Whisper / Invite buttons make.
local function SendTell(name)
    local f = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if f and name then f(name) end
end

local function SendBNetTell(name)
    local f = (ChatFrameUtil and ChatFrameUtil.SendBNetTell) or ChatFrame_SendBNetTell
    if f and name then f(name) end
end

local function Invite(name)
    if not name then return end
    if InviteToGroup then
        InviteToGroup(name)
    elseif C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
end

local function LevelClass(level, class)
    local bits = {}
    if level and level > 0 then bits[#bits + 1] = tostring(level) end
    if class and class ~= "" then bits[#bits + 1] = class end
    return table.concat(bits, " ")
end


-- Buttons chained leftward from the footer's right edge; hidden ones
-- leave no hole.
local function ChainRight(footer, buttons)
    local last
    for _, b in ipairs(buttons) do
        if b:IsShown() then
            b:ClearAllPoints()
            if last then
                b:SetPoint("RIGHT", last, "LEFT", -4, 0)
            else
                b:SetPoint("RIGHT", footer, "RIGHT", -6, 0)
            end
            last = b
        end
    end
end

local function FooterButton(parent, label, width, onClick, tip)
    local b = UI.Button(parent, label, { width = width, height = 22 })
    b:SetScript("OnClick", onClick)
    if tip then UI.Tooltip(b, label, tip) end
    return b
end

-- A cover over one sub-page, starting BELOW Blizzard's header (see the
-- file header). topFn returns the cover's top offset from FriendsFrame.
local function PageCover(host, name, topFn)
    local win = Kit.Cover(host, {
        name = name,
        insetName = Modern() and "SocialUIFrame" or "FriendsFrame",
        onClose = function() HideUIPanel(Panel()) end,
    })
    -- Blizzard's header above carries the title and the (secure) X.
    win.titleBar:Hide()
    -- (Forever: ZacUI's title bar on the social window stays up over a
    -- page cover - the cover brings none of its own)
    win._zKeepHeader = Modern() or nil
    win.top = -Kit.PAD
    win.Reanchor = function()
        local panel = Panel()
        if not panel then return end
        local ins = ns.GetPanelInset(Modern() and "SocialUIFrame" or "FriendsFrame", panel)
        local top = topFn(ins)
        if Modern() then
            -- under the Battle.net bar, which hangs 22px down from the top
            -- and is 50 tall (SocialUI.xml); measured when it has a size
            local bar = rawget(panel, "BattleNetBar")
            -- (Forever can keep a window's edges secret: then the bar's
            -- XML place, 22 down and 50 tall)
            local pt, bb = panel:GetTop(), type(bar) == "table" and bar.GetBottom and bar:GetBottom()
            if ns.IsSecret and (ns.IsSecret(pt) or ns.IsSecret(bb)) then pt, bb = nil, nil end
            top = (pt and bb) and -(pt - bb) - 2 or -74
        end
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", panel, "TOPLEFT", ins.l or 0, top)
        win:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(ins.r or 0), ins.b or 0)
    end
    win.Reanchor()
    return win
end

-- Just under the skinned header's gold hairline (Who, Guild).
local function BelowHairline(ins)
    local lineY = (ns.GetPanelLineY and ns.GetPanelLineY("FriendsFrame", nil)) or -24
    return -(ins.t or 0) + lineY - 1
end

-- Just under Blizzard's Friends / Ignore tabs (Friends).
local function BelowFriendTabs(ins)
    -- ZacUI's Friends / Ignore strip, when it is on (Win_CharTabs).
    local strip = ns.TabStrips and ns.TabStrips.FriendsHeaderBottom
        and ns.TabStrips.FriendsHeaderBottom(ins)
    if strip then return math.min(BelowHairline(ins), strip) end
    local tab = _G.FriendsTabHeaderTab1
    local h = (tab and tab:GetHeight()) or 32
    if ns.IsSecret and ns.IsSecret(h) then h = 32 end      -- (Forever may keep it secret)
    if not h or h < 16 then h = 32 end
    -- The tabs sit 51px down (FriendsFrame.xml); the cover starts where
    -- Blizzard's own list inset does.
    return math.min(BelowHairline(ins), -(51 + h))
end

-- Column sort buttons. First click sorts ascending, second descending,
-- third goes back to the server's order. Local sort: the data is a
-- few hundred rows at most.
local function SortBar(parent, specs, onChange)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(SORT_H)
    bar.buttons, bar.key, bar.desc = {}, nil, false
    local prev
    for i, spec in ipairs(specs) do
        local b = UI.Button(bar, spec.label .. " +", { height = SORT_H, size = F.SMALL })
        b:SetWidth(math.ceil(b._zText:GetStringWidth()) + 12)
        b:SetLabel(spec.label)
        b._zKey, b._zLabel = spec.key, spec.label
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 3, 0)
        else
            b:SetPoint("LEFT", bar, "LEFT", 0, 0)
        end
        b:SetScript("OnClick", function()
            if bar.key == spec.key then
                if bar.desc then
                    bar.key, bar.desc = nil, false
                else
                    bar.desc = true
                end
            else
                bar.key, bar.desc = spec.key, false
            end
            bar:Paint()
            onChange()
        end)
        UI.Tooltip(b, "Sort by " .. spec.label,
            "Click again to reverse, a third time for the default order.")
        bar.buttons[i] = b
        prev = b
    end
    function bar:Paint()
        for _, b in ipairs(self.buttons) do
            local on = (b._zKey == self.key)
            b:SetActive(on)
            b:SetLabel(on and (b._zLabel .. (self.desc and " -" or " +")) or b._zLabel)
        end
    end
    function bar:Sort(data, getters)
        local get = self.key and getters[self.key]
        if not get then return end
        local desc = self.desc
        table.sort(data, function(a, b)
            local va, vb = get(a), get(b)
            if va ~= vb then
                if desc then return va > vb end
                return va < vb
            end
            -- Strict tie-break so table.sort never sees an inconsistent
            -- order: by name, then by position.
            if a.name ~= b.name then return (a.name or "") < (b.name or "") end
            return (a.index or 0) < (b.index or 0)
        end)
    end
    return bar
end

-- Two-line row: status square, then left top / left bottom capped by
-- right top / right bottom. Every pair meets on explicit TOPRIGHT /
-- BOTTOMRIGHT points so no two strings can overlap.
local function BuildTwoLine(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local dot = row:CreateTexture(nil, "ARTWORK")
    dot._zui_own = true
    dot:SetTexture(FLAT)
    dot:SetSize(6, 6)
    dot:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.dot = dot

    row.rt = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.rt:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)
    row.rt:SetWordWrap(false)
    row.rb = UI.Font(row, F.SMALL, { justify = "RIGHT", cat = "text", key = "gray" })
    row.rb:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 4)
    row.rb:SetWordWrap(false)

    row.lt = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.lt:SetPoint("TOPLEFT", row, "TOPLEFT", 18, -4)
    row.lt:SetPoint("TOPRIGHT", row.rt, "TOPLEFT", -6, 0)
    row.lt:SetWordWrap(false)
    row.lb = UI.Font(row, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    row.lb:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 18, 4)
    row.lb:SetPoint("BOTTOMRIGHT", row.rb, "BOTTOMLEFT", -6, 0)
    row.lb:SetWordWrap(false)
end

local function PaintDot(row, online, afk, dnd)
    local key = "gray"
    if online then
        key = (dnd and "red") or (afk and "orange") or "green"
    end
    row.dot:SetVertexColor(Kit.TextRGB(key))
end

-- Keep the list's selection on the same person across a rebuild (the
-- data tables are new every redraw).
local function Reselect(list, data, key)
    list.selected = nil
    if not key then return end
    for _, e in ipairs(data) do
        if e.key == key then
            list.selected = e
            return
        end
    end
end

-- Blizzard's portrait sits at frame level 400 and hangs 53px down the
-- left edge - over the Who and Guild covers, which start at the header
-- line. Silenced while either of those is up; the Friends cover starts
-- below it and leaves Blizzard's header alone.
local portrait
local function Portrait()
    if portrait then return portrait end
    portrait = {}
    local function Add(x) if x then portrait[#portrait + 1] = x end end
    Add(_G.FriendsFrame and _G.FriendsFrame.PortraitContainer)
    Add(_G.SocialUIFrame and rawget(_G.SocialUIFrame, "PortraitContainer"))
    Add(_G.FriendsFramePortrait)
    return portrait
end

-- Faded only, the mouse left alone: Kit.Unsilence turns the mouse back ON,
-- which would make the portrait texture and its container start eating
-- clicks. Same _zKitAlpha field as the kit and Win_Raid, so either file
-- can undo the other; the raid cover counts too, since it shares the need.
local covers = {}
local function SyncSilence()
    local need = false
    for _, c in pairs(covers) do
        if c.needsPortrait and c.win and c.win:IsVisible() then need = true end
    end
    local raid = _G.ZacUIRaidWindow
    if raid and raid:IsVisible() then need = true end
    for _, f in ipairs(Portrait()) do
        if need then
            if not f._zKitQuiet then
                f._zKitQuiet = true
                f._zKitAlpha = f:GetAlpha() or 1
            end
            f:SetAlpha(0)
        elseif f._zKitQuiet then
            f:SetAlpha(f._zKitAlpha)
            f._zKitAlpha = nil
            f._zKitQuiet = nil
        end
    end
end

-- ============================================================
-- FRIENDS
-- ============================================================

local function FriendRows()
    local data = {}
    local onlineOnly = fr.chipOnline and fr.chipOnline:IsOn()
    local nW = C_FriendList.GetNumFriends() or 0
    local nWOn = C_FriendList.GetNumOnlineFriends() or 0
    local nB, nBOn = 0, 0
    if BNGetNumFriends then
        nB, nBOn = BNGetNumFriends()
        nB, nBOn = nB or 0, nBOn or 0
    end
    local function Add(e)
        if onlineOnly and not e.online then return end
        if not Kit.Matches(fr.query, e.name, e.char, e.class, e.zone, e.note) then return end
        data[#data + 1] = e
    end
    local function WoW(i)
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if not info or not info.name then return end
        Add({
            kind = "wow", id = i, key = "w:" .. info.name, name = info.name,
            online = info.connected and true or false,
            level = info.level, class = info.className, file = ClassFile(info.className),
            zone = info.area, note = info.notes, afk = info.afk, dnd = info.dnd,
            guid = info.guid,
        })
    end
    -- BNGetFriendInfo's tuple, or the same from C_BattleNet's account info
    -- (Forever has only the latter)
    local function BNetInfo(i)
        if BNGetFriendInfo then return BNGetFriendInfo(i) end
        local a = C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(i)
        if type(a) ~= "table" then return nil end
        local g = type(a.gameAccountInfo) == "table" and a.gameAccountInfo or {}
        return a.bnetAccountID, a.accountName, a.battleTag, a.isBattleTagFriend, g.characterName,
            g.gameAccountID, g.clientProgram, g.isOnline, a.lastOnlineTime, a.isAFK, a.isDND,
            a.customMessage, a.note
    end
    local function BNet(i)
        local bnetIDAccount, accountName, battleTag, isBattleTag, characterName,
            bnetIDGameAccount, client, isOnline, lastOnline, isAFK, isDND,
            messageText, noteText = BNetInfo(i)
        if not bnetIDAccount then return end
        local e = {
            kind = "bnet", id = i, key = "b:" .. bnetIDAccount, bnet = bnetIDAccount,
            name = accountName or (UNKNOWN or "Unknown"),
            online = isOnline and true or false,
            afk = isAFK, dnd = isDND, note = noteText,
        }
        if isOnline then
            if BNet_GetValidatedCharacterName then
                characterName = BNet_GetValidatedCharacterName(characterName, battleTag, client)
            end
            e.char = characterName
            local ga = bnetIDGameAccount and C_BattleNet and C_BattleNet.GetGameAccountInfoByID
                and C_BattleNet.GetGameAccountInfoByID(bnetIDGameAccount)
            if ga then
                e.afk = e.afk or ga.isGameAFK
                e.dnd = e.dnd or ga.isGameBusy
                -- Same game version: real zone, level and class. Anything
                -- else (the app, retail): the rich-presence line, as
                -- Blizzard's list shows it.
                if client == BNET_CLIENT_WOW and ga.wowProjectID == WOW_PROJECT_ID then
                    e.zone = ga.areaName
                    e.level = ga.characterLevel
                    e.class = ga.className
                    e.file = ClassFile(ga.className)
                else
                    e.zone = ga.richPresence
                end
            end
        else
            if lastOnline and lastOnline > 0 and FriendsFrame_GetLastOnline then
                e.status = string.format(BNET_LAST_ONLINE_TIME or "%s", FriendsFrame_GetLastOnline(lastOnline))
            end
        end
        Add(e)
    end
    -- Blizzard's order: online WoW, online Battle.net, offline WoW,
    -- offline Battle.net (the server lists online friends first).
    for i = 1, nWOn do WoW(i) end
    for i = 1, nBOn do BNet(i) end
    for i = nWOn + 1, nW do WoW(i) end
    for i = nBOn + 1, nB do BNet(i) end
    return data, nW + nB, nWOn + nBOn
end

local function FriendSelected()
    return fr.list and fr.list.selected
end

local function FriendButtons()
    local e = FriendSelected()
    local me = UnitName("player")
    local canTell = e and ((e.kind == "bnet") or e.online) or false
    local canInvite = false
    if e and e.online then
        if e.kind == "wow" then
            canInvite = e.name ~= me
        elseif CanGroupWithAccount and FriendsFrame_BattlenetInvite then
            canInvite = CanGroupWithAccount(e.bnet) and true or false
        end
    end
    fr.whisper:SetDisabled(not canTell)
    fr.invite:SetDisabled(not canInvite)
    -- Battle.net friends are removed from Blizzard's right-click menu,
    -- which carries its own confirmation.
    fr.remove:SetDisabled(not (e and e.kind == "wow"))
end

local function FriendsRefresh(keepOffset)
    if not fr.win or not fr.win:IsVisible() then return end
    local data, total, online = FriendRows()
    Reselect(fr.list, data, fr.selKey)
    if not fr.list.selected then fr.selKey = nil end
    fr.list:SetEmptyText(total == 0 and "No friends yet - add one below." or "Nothing matches.")
    fr.list:SetData(data, keepOffset)
    fr.count:SetText(online .. " / " .. total)
    FriendButtons()
end
-- One redraw per frame for an event storm (roster updates arrive in
-- bursts), and none at all - not even a timer - while the page is not
-- on screen.
local FriendsQueue = Kit.Coalesce(FriendsRefresh, function() return fr.win end, true)

local function FriendTooltip(row)
    local e = row.item
    if not e or not FriendsFrameTooltip_Show then return end
    -- Blizzard's own friend tooltip (Battle.net game accounts, note,
    -- broadcast) reads only these two fields off its button.
    row.buttonType = (e.kind == "bnet") and FRIENDS_BUTTON_TYPE_BNET or FRIENDS_BUTTON_TYPE_WOW
    row.id = e.id
    pcall(FriendsFrameTooltip_Show, row)
end

local function BuildFriendRow(row)
    BuildTwoLine(row)
    row:SetScript("OnEnter", FriendTooltip)
    row:SetScript("OnLeave", function(self)
        if FriendsTooltip then
            if FriendsTooltip.button == self then FriendsTooltip.button = nil end
            FriendsTooltip:Hide()
        end
    end)
    row:SetScript("OnClick", function(self, button)
        local e = self.item
        if not e then return end
        if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        fr.selKey = e.key
        fr.list:Select(e)
        FriendButtons()
        if button == "RightButton" then
            -- Blizzard's own friend menu, opened with the same arguments
            -- FriendsFrameFriendButton_OnClick passes.
            if e.kind == "bnet" then
                if FriendsFrame_ShowBNDropdown then
                    FriendsFrame_ShowBNDropdown(e.name, e.online, nil, nil, nil, 1, e.bnet,
                        nil, nil, nil, nil)
                end
            elseif FriendsFrame_ShowDropdown then
                FriendsFrame_ShowDropdown(e.name, e.online, nil, nil, nil, 1, nil,
                    nil, nil, nil, nil, e.guid)
            end
        end
    end)
end

local function UpdateFriendRow(row, e)
    PaintDot(row, e.online, e.afk, e.dnd)
    local name = e.name
    if e.char and e.char ~= "" then name = name .. " (" .. e.char .. ")" end
    row.lt:SetText(name)
    if not e.online then
        row.lt:SetTextColor(Kit.TextRGB("gray"))
    elseif e.file then
        row.lt:SetTextColor(ClassRGB(e.file))
    elseif e.kind == "bnet" then
        row.lt:SetTextColor(Kit.TextRGB("blue"))
    else
        row.lt:_zPaint()
    end
    row.rt:SetText(e.online and LevelClass(e.level, e.class) or "")
    if e.online then row.rt:_zPaint() else row.rt:SetTextColor(Kit.TextRGB("gray")) end

    local bits = {}
    if e.online and e.zone and e.zone ~= "" then bits[#bits + 1] = e.zone end
    if e.note and e.note ~= "" then bits[#bits + 1] = e.note end
    row.lb:SetText(table.concat(bits, "  |  "))

    if e.online then
        if e.dnd then
            row.rb:SetText(CHAT_FLAG_DND or "DND")
            row.rb:SetTextColor(Kit.TextRGB("red"))
        elseif e.afk then
            row.rb:SetText(CHAT_FLAG_AFK or "AFK")
            row.rb:SetTextColor(Kit.TextRGB("orange"))
        else
            row.rb:SetText("")
        end
    else
        row.rb:SetText(e.status or (FRIENDS_LIST_OFFLINE or "Offline"))
        row.rb:SetTextColor(Kit.TextRGB("gray"))
    end
end

local function BuildFriends()
    if fr.win then return fr.win end
    local win = PageCover(fr.host, "ZacUIFriendsWindow", BelowFriendTabs)
    fr.win = win
    local y = win.top

    fr.chipOnline = Kit.Chip(win, "Online only", false, function() FriendsRefresh() end,
        "Hide friends who are offline.")
    fr.chipOnline:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y)
    fr.count = UI.Font(win, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    fr.count:SetPoint("RIGHT", fr.chipOnline, "LEFT", -Kit.GAP, 0)
    fr.search = Kit.Search(win, 100, function(text)
        fr.query = Kit.NormalizeQuery(text)
        FriendsRefresh()
    end, "Search friends")
    fr.search:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
    fr.search:SetPoint("RIGHT", fr.count, "LEFT", -Kit.GAP, 0)

    win.footer = Kit.Footer(win, Kit.FOOTER_H)
    fr.add = FooterButton(win.footer, ADD_FRIEND or "Add Friend", 78, function()
        -- Blizzard's own Add Friend click: your target if it is a
        -- friendly player, else the Battle.net / name entry dialog.
        if FriendsFrameAddFriendButton_OnClick then
            FriendsFrameAddFriendButton_OnClick(_G.FriendsFrameAddFriendButton)
        else
            StaticPopup_Show("ADD_FRIEND")
        end
    end, "Adds your target if it is a friendly player, otherwise asks for a name.")
    fr.whisper = FooterButton(win.footer, WHISPER or "Whisper", 72, function()
        local e = FriendSelected()
        if not e then return end
        if e.kind == "bnet" then SendBNetTell(e.name) else SendTell(e.name) end
    end)
    fr.invite = FooterButton(win.footer, INVITE or "Invite", 68, function()
        local e = FriendSelected()
        if not e or not e.online then return end
        if e.kind == "bnet" then
            if FriendsFrame_BattlenetInvite then FriendsFrame_BattlenetInvite(nil, e.bnet) end
        else
            Invite(e.name)
        end
    end)
    fr.remove = FooterButton(win.footer, REMOVE or "Remove", 72, function()
        local e = FriendSelected()
        if not e or e.kind ~= "wow" then return end
        local name = e.name
        -- By NAME, captured now: the list reorders as friends log on and
        -- off, so an index could point at someone else by the time the
        -- dialog is accepted.
        UI.Confirm({
            title = REMOVE_FRIEND or "Remove friend",
            text = "Remove " .. name .. " from your friends list?",
            acceptText = REMOVE or "Remove",
            destructive = true,
            onAccept = function() C_FriendList.RemoveFriend(name) end,
        })
    end, "Battle.net friends are removed from the right-click menu.")
    ChainRight(win.footer, { fr.remove, fr.invite, fr.whisper, fr.add })

    fr.list = Kit.List(win, {
        rowHeight = Kit.ROW_H,
        build = BuildFriendRow,
        update = UpdateFriendRow,
    })
    fr.list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y - Kit.SEARCH_H - Kit.GAP)
    fr.list:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("FRIENDLIST_UPDATE")
    for _, e in ipairs({ "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_INFO_CHANGED",
                         "BN_CONNECTED", "BN_DISCONNECTED", "PLAYER_FLAGS_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", FriendsQueue)

    win:HookScript("OnShow", function()
        fr.query = ""
        fr.search:SetText("")
        SyncSilence()
        FriendsRefresh()
    end)
    win:HookScript("OnHide", function()
        if FriendsTooltip then FriendsTooltip:Hide() end
        SyncSilence()
    end)
    covers.friends = { win = win, needsPortrait = false }
    return win
end

local function ApplyFriends(shown)
    local host = FriendsHost(type(shown) == "table" and shown or nil)
    if not host then return end
    SetFriendsHost(host)
    if not Panel() then return end
    if Enabled("friendswin") then
        BuildFriends()
        -- the other window opened: the cover moves over to it
        if fr.win:GetParent() ~= host then
            fr.win:SetParent(host)
            fr.win._zKeepHeader = Modern() or nil
        end
        fr.win.Reanchor()
        fr.win:Show()
        if fr.win:IsVisible() then FriendsRefresh() end
    elseif fr.win then
        fr.win:Hide()
    end
    SyncSilence()
end

-- ============================================================
-- WHO
-- ============================================================
local who = {}

-- WHERE THE WHO LIST LIVES. Classic: WhoFrame, a page of FriendsFrame.
-- WoW Forever: a page of the group finder, LFGWhoListFrame (there is no
-- Who in its social window), reached by the Who tab ZacUI's group
-- finder window gains there (Win_LFG). The cover then hangs on that page,
-- in the group finder window's page area, under its tabs.
local function WhoHost()
    if _G.WhoFrame then return _G.WhoFrame end
    local f = _G.LFGWhoListFrame
    return type(f) == "table" and f or nil
end
local function WhoInLFG()
    return _G.WhoFrame == nil and _G.LFGWhoListFrame ~= nil
end

local WHO_SORT = {
    name  = function(e) return string.lower(e.name or "") end,
    level = function(e) return e.level or 0 end,
    class = function(e) return string.lower(e.class or "") end,
    zone  = function(e) return string.lower(e.zone or "") end,
    guild = function(e) return string.lower(e.guild or "") end,
}

local function WhoRows()
    local data = {}
    local num, total = C_FriendList.GetNumWhoResults()
    num, total = num or 0, total or 0
    for i = 1, num do
        local info = C_FriendList.GetWhoInfo(i)
        if info and info.fullName then
            data[#data + 1] = {
                index = i, key = info.fullName, name = info.fullName,
                guild = info.fullGuildName, level = info.level,
                race = info.raceStr, class = info.classStr,
                zone = info.area, file = info.filename,
            }
        end
    end
    who.sort:Sort(data, WHO_SORT)
    return data, num, total
end

local function WhoButtons()
    local e = who.list and who.list.selected
    local me = UnitName("player")
    who.whisper:SetDisabled(not e)
    who.invite:SetDisabled(not e or e.name == me)
    who.addFriend:SetDisabled(not e or e.name == me)
end

local function WhoRefresh(keepOffset)
    if not who.win or not who.win:IsVisible() then return end
    local data, num, total = WhoRows()
    Reselect(who.list, data, who.selKey)
    if not who.list.selected then who.selKey = nil end
    who.list:SetEmptyText("Type a /who query above and press Enter.")
    who.list:SetData(data, keepOffset)
    if total > num then
        who.totals:SetText(num .. " of " .. total .. " shown")
    else
        who.totals:SetText(num .. (num == 1 and " player" or " players"))
    end
    WhoButtons()
end
local WhoQueue = Kit.Coalesce(WhoRefresh, function() return who.win end, true)

-- The /who itself. SendWho is hardware-event restricted: this only ever
-- runs from Enter in the box or a click on the button.
local function SendWho(text)
    text = text and strtrim(text) or ""
    if text == "" then
        text = who.last or (WhoFrame_GetDefaultWhoCommand and WhoFrame_GetDefaultWhoCommand()) or ""
    end
    who.last = text
    local origin = Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social
    C_FriendList.SendWho(text, origin)
end

local function WhoTooltip(row)
    local e = row.item
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name, ClassRGB(e.file))
    local bc = GetColor("tooltip", "body")
    local line = LevelClass(e.level, e.class)
    if e.race and e.race ~= "" then line = (e.level and (e.level .. " ") or "") .. e.race .. " " .. (e.class or "") end
    GameTooltip:AddLine(line, bc.r, bc.g, bc.b)
    if e.guild and e.guild ~= "" then GameTooltip:AddLine("<" .. e.guild .. ">", bc.r, bc.g, bc.b) end
    if e.zone and e.zone ~= "" then GameTooltip:AddLine(e.zone, Kit.TextRGB("gray")) end
    GameTooltip:Show()
end

local function BuildWhoRow(row)
    BuildTwoLine(row)
    row.dot:Hide()
    row:SetScript("OnEnter", WhoTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        local e = self.item
        if not e then return end
        who.selKey = e.key
        who.list:Select(e)
        WhoButtons()
        if button == "RightButton" and FriendsFrame_ShowDropdown then
            -- As FriendsFrameWhoButton_OnClick: connected, and the who
            -- index as the last argument.
            FriendsFrame_ShowDropdown(e.name, 1, nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, e.index)
        end
    end)
end

local function UpdateWhoRow(row, e)
    row.lt:SetText(e.name)
    row.lt:SetTextColor(ClassRGB(e.file))
    row.rt:SetText(LevelClass(e.level, e.class))
    row.rt:_zPaint()
    row.lb:SetText((e.guild and e.guild ~= "") and ("<" .. e.guild .. ">") or "")
    row.rb:SetText(e.zone or "")
end

local function BuildWho()
    if who.win then return who.win end
    local win
    if WhoInLFG() then
        win = Kit.Cover(WhoHost(), {
            name = "ZacUIWhoWindow",
            insetName = "LFGParentFrame",
            onClose = function() HideUIPanel(_G.LFGParentFrame) end,
        })
        win.titleBar:Hide()
        win._zKeepHeader = true
        win.top = -Kit.PAD
        win.Reanchor = function()
            -- ZacUI's group finder window's page area, under its tabs;
            -- the whole page while that window is off
            local lfg = _G.ZacUILFGWindow
            win:ClearAllPoints()
            if lfg and lfg:IsShown() and lfg.pageTop then
                win:SetPoint("TOPLEFT", lfg, "TOPLEFT", Kit.PAD, lfg.pageTop)
                win:SetPoint("BOTTOMRIGHT", lfg, "BOTTOMRIGHT", -Kit.PAD, Kit.PAD)
            else
                win:SetAllPoints(WhoHost())
            end
        end
        win.Reanchor()
    else
        win = PageCover(WhoFrame, "ZacUIWhoWindow", BelowHairline)
    end
    who.win = win
    local y = win.top

    who.go = UI.Button(win, WHO or "Who", { width = 56, height = Kit.SEARCH_H })
    who.go:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y)
    who.go:SetScript("OnClick", function() SendWho(who.box:GetText()) end)
    UI.Tooltip(who.go, WHO or "Who",
        "Send the query. Empty repeats the last one (or your zone and level range).")

    -- Not Kit.Search: this box SENDS on Enter instead of filtering on
    -- every keystroke, and clearing it must not fire an empty /who.
    who.box = UI.EditBox(win, {
        width = 100, height = Kit.SEARCH_H,
        hint = "Who: name, zone, class, 50-60",
        onEnter = function(text)
            if text and strtrim(text) ~= "" then SendWho(text) end
        end,
    })
    who.box:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
    who.box:SetPoint("RIGHT", who.go, "LEFT", -Kit.GAP, 0)

    local sy = y - Kit.SEARCH_H - Kit.GAP
    who.sort = SortBar(win, {
        { key = "name",  label = NAME or "Name" },
        { key = "level", label = LEVEL_ABBR or "Lvl" },
        { key = "class", label = CLASS or "Class" },
        { key = "zone",  label = ZONE or "Zone" },
        { key = "guild", label = GUILD or "Guild" },
    }, function() WhoRefresh() end)
    who.sort:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, sy)
    who.sort:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, sy)

    win.footer = Kit.Footer(win, Kit.FOOTER_H)
    who.totals = UI.Font(win.footer, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    who.totals:SetPoint("LEFT", 8, 0)
    who.totals:SetWordWrap(false)
    who.addFriend = FooterButton(win.footer, ADD_FRIEND or "Add Friend", 78, function()
        local e = who.list.selected
        if e then C_FriendList.AddFriend(e.name) end
    end)
    who.invite = FooterButton(win.footer, INVITE or "Invite", 62, function()
        local e = who.list.selected
        if e then Invite(e.name) end
    end)
    who.whisper = FooterButton(win.footer, WHISPER or "Whisper", 66, function()
        local e = who.list.selected
        if e then SendTell(e.name) end
    end)
    ChainRight(win.footer, { who.addFriend, who.invite, who.whisper })
    who.totals:SetPoint("RIGHT", who.whisper, "LEFT", -6, 0)

    who.list = Kit.List(win, {
        rowHeight = Kit.ROW_H,
        build = BuildWhoRow,
        update = UpdateWhoRow,
    })
    who.list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, sy - SORT_H - 4)
    who.list:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("WHO_LIST_UPDATE")
    ev:SetScript("OnEvent", function()
        -- A new result set: the old selection means nothing any more
        -- (Blizzard clears WhoFrame.selectedWho on this event too).
        who.selKey = nil
        WhoQueue()
    end)

    -- Blizzard's own who box is HIGH strata - it would draw over any
    -- MEDIUM cover - so it is faded and made click-through while ours is up.
    who.leftovers = {}
    if _G.WhoFrameEditBox then who.leftovers[1] = _G.WhoFrameEditBox end

    win:HookScript("OnShow", function()
        Kit.Silence(who.leftovers)
        SyncSilence()
        WhoRefresh()
    end)
    win:HookScript("OnHide", function()
        Kit.Unsilence(who.leftovers)
        SyncSilence()
    end)
    covers.who = { win = win, needsPortrait = not WhoInLFG() }
    return win
end

local function ApplyWho()
    local host = WhoHost()
    if not host or (not WhoInLFG() and not FriendsFrame) then return end
    if Enabled("whowin") then
        BuildWho()
        who.win.Reanchor()
        who.win:Show()
        if who.win:IsVisible() then
            Kit.Silence(who.leftovers)
            -- (Forever's Who page keeps its search box and button in the
            -- HIGH strata and wears a title bar: ZacUI's group finder
            -- window silences them with the rest of that page, Win_LFG)
            WhoRefresh()
        end
    elseif who.win then
        who.win:Hide()
        Kit.Unsilence(who.leftovers)
    end
    SyncSilence()
end

-- ============================================================
-- GUILD
-- ============================================================
local gd = { query = "", lastRoster = 0 }

local GUILD_SORT = {
    name  = function(e) return string.lower(e.name or "") end,
    rank  = function(e) return e.rankIndex or 0 end,
    level = function(e) return e.level or 0 end,
    class = function(e) return string.lower(e.class or "") end,
    zone  = function(e) return string.lower(e.zone or "") end,
}

local function RequestRoster(force)
    local now = GetTime()
    if not force and now - gd.lastRoster < 15 then return end
    gd.lastRoster = now
    local fn = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster
    if fn and IsInGuild() then fn() end
end

local function GuildRows()
    local data = {}
    local total, online = GetNumGuildMembers()
    total, online = total or 0, online or 0
    -- Blizzard's own rule: with offline members hidden the roster only
    -- holds the online ones.
    local showOffline = GetGuildRosterShowOffline()
    local n = showOffline and total or online
    local canOfficer = C_GuildInfo and C_GuildInfo.CanViewOfficerNote and C_GuildInfo.CanViewOfficerNote()
    for i = 1, n do
        local fullName, rank, rankIndex, level, class, zone, note, officernote,
            isOnline, status, classFile = GetGuildRosterInfo(i)
        if fullName and (showOffline or isOnline) then
            local e = {
                index = i, full = fullName, key = fullName,
                name = Ambiguate and Ambiguate(fullName, "guild") or fullName,
                rank = rank, rankIndex = rankIndex, level = level, class = class,
                zone = zone, note = note, onote = canOfficer and officernote or nil,
                online = isOnline and true or false,
                afk = status == 1, dnd = status == 2, file = classFile,
            }
            if not e.online and GuildFrame_GetLastOnline then
                e.last = GuildFrame_GetLastOnline(i)
            end
            if Kit.Matches(gd.query, e.name, e.rank, e.zone, e.note, e.onote, e.class) then
                data[#data + 1] = e
            end
        end
    end
    gd.sort:Sort(data, GUILD_SORT)
    return data, total, online
end

-- The selected-member half of Blizzard's GuildStatus_Update, filling
-- Blizzard's own detail panel. Ported rather than called: the full
-- function also re-selects the Guild TAB (PanelTemplates_SetTab), and a
-- tab value written from addon code would taint the next open of this
-- protected window in combat. Blizzard's own roster update re-runs the
-- original a moment later and overwrites all of this anyway.
local function FillDetail()
    local sel = GetGuildRosterSelection()
    if not sel or sel <= 0 or not GuildMemberDetailName then return end
    local fullName, rank, rankIndex, level, class, zone, note, officernote, online = GetGuildRosterInfo(sel)
    if not fullName then return end
    local _, _, myRankIndex = GetGuildInfo("player")
    myRankIndex = myRankIndex or 0
    local maxRankIndex = (GuildControlGetNumRanks and GuildControlGetNumRanks() or 1) - 1
    local shown = Ambiguate and Ambiguate(fullName, "guild") or fullName
    -- The one Blizzard field written from here, and deliberately: the
    -- panel's Invite / Promote / Demote / Remove buttons act on it. Its
    -- readers call nothing protected, and GuildStatus_Update rewrites it
    -- (clean) on the next roster update.
    GuildFrame.selectedName = fullName

    GuildMemberDetailName:SetText(shown)
    GuildMemberDetailLevel:SetText(string.format(FRIENDS_LEVEL_TEMPLATE or "Level %d %s", level or 0, class or ""))
    GuildMemberDetailZoneText:SetText(zone)
    GuildMemberDetailRankText:SetText(rank)
    if online then
        GuildMemberDetailOnlineText:SetText(GUILD_ONLINE_LABEL or "Online")
    elseif GuildFrame_GetLastOnline then
        GuildMemberDetailOnlineText:SetText(GuildFrame_GetLastOnline(sel))
    end

    local canNote = CanEditPublicNote and CanEditPublicNote()
    if canNote then
        PersonalNoteText:SetTextColor(Kit.TextRGB("normal"))
        if not note or note == "" then note = GUILD_NOTE_EDITLABEL end
    else
        PersonalNoteText:SetTextColor(Kit.TextRGB("gray"))
    end
    GuildMemberNoteBackground:EnableMouse(canNote and true or false)
    PersonalNoteText:SetText(note)

    local canView = C_GuildInfo and C_GuildInfo.CanViewOfficerNote and C_GuildInfo.CanViewOfficerNote()
    if canView then
        local canEdit = C_GuildInfo.CanEditOfficerNote and C_GuildInfo.CanEditOfficerNote()
        if canEdit then
            if not officernote or officernote == "" then officernote = GUILD_OFFICERNOTE_EDITLABEL end
            OfficerNoteText:SetTextColor(Kit.TextRGB("normal"))
        else
            OfficerNoteText:SetTextColor(Kit.TextRGB("gray"))
        end
        GuildMemberOfficerNoteBackground:EnableMouse(canEdit and true or false)
        OfficerNoteText:SetText(officernote)
        GuildMemberDetailOfficerNoteLabel:Show()
        GuildMemberOfficerNoteBackground:Show()
        if GUILD_DETAIL_OFFICER_HEIGHT then GuildMemberDetailFrame:SetHeight(GUILD_DETAIL_OFFICER_HEIGHT) end
    else
        GuildMemberDetailOfficerNoteLabel:Hide()
        GuildMemberOfficerNoteBackground:Hide()
        if GUILD_DETAIL_NORM_HEIGHT then GuildMemberDetailFrame:SetHeight(GUILD_DETAIL_NORM_HEIGHT) end
    end

    rankIndex = rankIndex or 0
    if CanGuildPromote() and rankIndex > 1 and rankIndex > (myRankIndex + 1) then
        GuildFramePromoteButton:Enable()
    else
        GuildFramePromoteButton:Disable()
    end
    if CanGuildDemote() and rankIndex >= 1 and rankIndex > myRankIndex and rankIndex ~= maxRankIndex then
        GuildFrameDemoteButton:Enable()
    else
        GuildFrameDemoteButton:Disable()
    end
    if not GuildFrameDemoteButton:IsEnabled() and not GuildFramePromoteButton:IsEnabled() then
        GuildFramePromoteButton:Hide()
        GuildFrameDemoteButton:Hide()
        GuildMemberDetailRankText:SetPoint("RIGHT", GuildMemberDetailFrame, "RIGHT", -10, 0)
    else
        GuildFramePromoteButton:Show()
        GuildFrameDemoteButton:Show()
        GuildMemberDetailRankText:SetPoint("RIGHT", GuildFramePromoteButton, "LEFT", 3, 0)
    end
    if CanGuildRemove() and rankIndex >= 1 and rankIndex > myRankIndex then
        GuildMemberRemoveButton:Enable()
    else
        GuildMemberRemoveButton:Disable()
    end
    if UnitName("player") == shown or not online then
        GuildMemberGroupInviteButton:Disable()
    else
        GuildMemberGroupInviteButton:Enable()
    end
end

local function DetailOpen()
    return GuildMemberDetailFrame and GuildMemberDetailFrame:IsShown()
end

-- Blizzard's GuildFramePopup_Show, minus one thing: it would HIDE Guild
-- Control, whose OnHide rewrites UIPanelWindows.FriendsFrame.width and
-- re-lays the panels. Run from an addon that write is tainted, and the
-- panel manager reads it the next time a panel opens in combat. So Guild
-- Control is never closed from here; while it is open (it only ever
-- opens from Blizzard's own button, see GuildButtons) the others wait.
local SAFE_POPUPS = { "GuildEventLogFrame", "GuildInfoFrame", "GuildMemberDetailFrame" }
local function ShowPopup(frame)
    if not frame then return false end
    local control = _G.GuildControlPopupFrame
    if control and control:IsShown() then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage("Close Guild Control first.", Kit.TextRGB("red"))
        end
        return false
    end
    for _, n in ipairs(SAFE_POPUPS) do
        local f = _G[n]
        if f and f ~= frame then f:Hide() end
    end
    frame:Show()
    return true
end

-- Blizzard's roster click (FriendsFrameGuildStatusButton_OnClick): the
-- same member again closes the panel, another member re-fills it. The
-- selection lives in the client (SetGuildRosterSelection); nothing here
-- writes GuildFrame.selectedGuildMember, which Blizzard's own roster
-- click reads on its way to ShowUIPanel(FriendsFrame).
local function MemberClick(e)
    if not GuildMemberDetailFrame then return end
    local previous = GetGuildRosterSelection()
    SetGuildRosterSelection(e.index)
    if DetailOpen() and previous == e.index then
        GuildMemberDetailFrame:Hide()
        SetGuildRosterSelection(0)
    elseif ShowPopup(GuildMemberDetailFrame) then
        pcall(FillDetail)
    end
end

-- GUILD CONTROL IS BLIZZARD'S OWN BUTTON, lifted above the cover into a
-- gap left for it in the footer. Its OnShow writes the same panel-width
-- field as above, so only Blizzard's (secure) click may open it.
local function LiftControl(on)
    local b = _G.GuildFrameControlButton
    if not b or not gd.win then return end
    if on then
        if b._zLift == nil then b._zLift = b:GetFrameLevel() end
        b:SetFrameLevel(gd.win:GetFrameLevel() + 10)
        b:ClearAllPoints()
        b:SetPoint("CENTER", gd.control, "CENTER", 0, 0)
    elseif b._zLift ~= nil then
        b:SetFrameLevel(b._zLift)
        b._zLift = nil
        -- Back to its FriendsFrame.xml anchor.
        b:ClearAllPoints()
        b:SetPoint("BOTTOMRIGHT", GuildFrame, "BOTTOMRIGHT", -6, 4)
    end
end

local function GuildButtons()
    local lead = IsGuildLeader and IsGuildLeader()
    local impeach = CanReplaceGuildMaster and CanReplaceGuildMaster()
    gd.add:SetShown(CanGuildInvite and CanGuildInvite() and true or false)
    -- Blizzard swaps Guild Control for Impeach when the leader has been
    -- away long enough to be replaced; Control is leader-only.
    gd.impeach:SetShown(impeach and true or false)
    -- gd.control is only the gap Blizzard's own button is lifted into.
    local control = (not impeach) and lead and _G.GuildFrameControlButton ~= nil
    gd.control:SetShown(control and true or false)
    LiftControl(control)
    ChainRight(gd.footer, { gd.control, gd.impeach, gd.add, gd.info })
    gd.motdEdit:SetShown(CanEditMOTD and CanEditMOTD() and true or false)
end

local function GuildRefresh(keepOffset)
    if not gd.win or not gd.win:IsVisible() then return end
    if not IsInGuild() then
        gd.list:SetEmptyText(ERR_GUILD_PLAYER_NOT_IN_GUILD or "You are not in a guild.")
        gd.list:SetData({}, false)
        gd.count:SetText("")
        gd.motd:SetText("")
        return
    end
    local data, total, online = GuildRows()
    local sel = DetailOpen() and GetGuildRosterSelection() or 0
    gd.list.selected = nil
    for _, e in ipairs(data) do
        if e.index == sel then gd.list.selected = e end
    end
    gd.list:SetEmptyText(total == 0 and "Loading the guild roster..." or "Nothing matches.")
    gd.list:SetData(data, keepOffset)
    gd.count:SetText(online .. " / " .. total)
    local motd = C_GuildInfo and C_GuildInfo.GetMOTD and C_GuildInfo.GetMOTD() or ""
    if motd == "" then
        gd.motd:SetText("No message of the day.")
        gd.motd:SetTextColor(Kit.TextRGB("gray"))
    else
        gd.motd:SetText(motd)
        gd.motd:_zPaint()
    end
    gd.motdText = motd
    GuildButtons()
end
local GuildQueue = Kit.Coalesce(GuildRefresh, function() return gd.win end, true)

local function GuildTooltip(row)
    local e = row.item
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name, ClassRGB(e.file))
    local bc = GetColor("tooltip", "body")
    GameTooltip:AddLine(LevelClass(e.level, e.class), bc.r, bc.g, bc.b)
    if e.rank then GameTooltip:AddLine(e.rank, bc.r, bc.g, bc.b) end
    if e.online then
        if e.zone then GameTooltip:AddLine(e.zone, Kit.TextRGB("gray")) end
    elseif e.last then
        GameTooltip:AddLine(e.last, Kit.TextRGB("gray"))
    end
    if e.note and e.note ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine((NOTE_COLON or "Note:") .. " " .. e.note, bc.r, bc.g, bc.b, true)
    end
    if e.onote and e.onote ~= "" then
        GameTooltip:AddLine((OFFICER_NOTE_COLON or "Officer's Note:") .. " " .. e.onote,
            Kit.TextRGB("orange"))
    end
    GameTooltip:Show()
end

local function BuildGuildRow(row)
    BuildTwoLine(row)
    row:SetScript("OnEnter", GuildTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        local e = self.item
        if not e then return end
        if button == "RightButton" then
            -- As Blizzard's roster button: name and online, nothing else.
            if FriendsFrame_ShowDropdown then FriendsFrame_ShowDropdown(e.full, e.online) end
            return
        end
        MemberClick(e)
        GuildQueue()
    end)
end

local function UpdateGuildRow(row, e)
    PaintDot(row, e.online, e.afk, e.dnd)
    row.lt:SetText(e.name)
    if e.online then row.lt:SetTextColor(ClassRGB(e.file)) else row.lt:SetTextColor(Kit.TextRGB("gray")) end
    row.rt:SetText(LevelClass(e.level, e.class))
    if e.online then row.rt:_zPaint() else row.rt:SetTextColor(Kit.TextRGB("gray")) end

    local bits = {}
    if e.rank and e.rank ~= "" then bits[#bits + 1] = e.rank end
    if e.note and e.note ~= "" then bits[#bits + 1] = e.note end
    if e.onote and e.onote ~= "" then bits[#bits + 1] = "[" .. e.onote .. "]" end
    row.lb:SetText(table.concat(bits, "  |  "))

    if e.online then
        local z = e.zone or ""
        if e.dnd then z = z .. " " .. (CHAT_FLAG_DND or "<DND>")
        elseif e.afk then z = z .. " " .. (CHAT_FLAG_AFK or "<AFK>") end
        row.rb:SetText(z)
        row.rb:_zPaint()
    else
        row.rb:SetText(e.last or "")
        row.rb:SetTextColor(Kit.TextRGB("gray"))
    end
end

local function BuildGuild()
    if gd.win then return gd.win end
    local win = PageCover(GuildFrame, "ZacUIGuildWindow", BelowHairline)
    gd.win = win
    local y = win.top

    -- Message of the day, two lines, full text on hover.
    local box = UI.Box(win, "ui", "elementBg")
    box:SetHeight(34)
    box:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
    box:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y)
    box:EnableMouse(true)
    gd.motdEdit = UI.Button(box, EDIT or "Edit", { width = 36, height = 16, size = F.SMALL })
    gd.motdEdit:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, -4)
    gd.motdEdit:SetScript("OnClick", function() StaticPopup_Show("SET_GUILDMOTD") end)
    gd.motd = UI.Font(box, F.SMALL, { justify = "LEFT" })
    gd.motd:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -4)
    gd.motd:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -44, 4)
    gd.motd:SetJustifyV("TOP")
    gd.motd:SetWordWrap(true)
    if gd.motd.SetMaxLines then gd.motd:SetMaxLines(2) end
    box:SetScript("OnEnter", function(self)
        if not gd.motdText or gd.motdText == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local tc = GetColor("tooltip", "title")
        GameTooltip:AddLine(GUILD_MOTD_LABEL or "Guild Message of the Day:", tc.r, tc.g, tc.b)
        local bc = GetColor("tooltip", "body")
        GameTooltip:AddLine(gd.motdText, bc.r, bc.g, bc.b, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local ty = y - 34 - Kit.GAP
    gd.chipOnline = Kit.Chip(win, "Online only", not GetGuildRosterShowOffline(), function(on)
        -- Blizzard's own "Show offline members" switch, flipped: the
        -- roster the server sends follows it. Kept in step with
        -- Blizzard's checkbox so the skinned page agrees when ours is off.
        SetGuildRosterSelection(0)
        if GuildMemberDetailFrame then GuildMemberDetailFrame:Hide() end
        SetGuildRosterShowOffline(not on)
        if _G.GuildFrameLFGButton then _G.GuildFrameLFGButton:SetChecked(not on) end
        GuildRefresh()
    end, "Hide members who are offline.")
    gd.chipOnline:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, ty)
    gd.count = UI.Font(win, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    gd.count:SetPoint("RIGHT", gd.chipOnline, "LEFT", -Kit.GAP, 0)
    gd.search = Kit.Search(win, 100, function(text)
        gd.query = Kit.NormalizeQuery(text)
        GuildRefresh()
    end, "Search guild")
    gd.search:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, ty)
    gd.search:SetPoint("RIGHT", gd.count, "LEFT", -Kit.GAP, 0)

    local sy = ty - Kit.SEARCH_H - Kit.GAP
    gd.sort = SortBar(win, {
        { key = "name",  label = NAME or "Name" },
        { key = "rank",  label = RANK or "Rank" },
        { key = "level", label = LEVEL_ABBR or "Lvl" },
        { key = "class", label = CLASS or "Class" },
        { key = "zone",  label = ZONE or "Zone" },
    }, function() GuildRefresh() end)
    gd.sort:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, sy)
    gd.sort:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, sy)

    win.footer = Kit.Footer(win, Kit.FOOTER_H)
    gd.footer = win.footer
    -- Blizzard's own handlers, as its guild page buttons call them.
    gd.info = FooterButton(win.footer, "Guild Info", 76, function()
        -- ToggleGuildInfoFrame, through the popup switch that never
        -- closes Guild Control (see ShowPopup).
        local f = _G.GuildInfoFrame
        if not f then return end
        if f:IsShown() then f:Hide() else ShowPopup(f) end
    end, "The guild information text.")
    gd.add = FooterButton(win.footer, ADDMEMBER or "Add Member", 86, function()
        StaticPopup_Show("ADD_GUILDMEMBER")
    end)
    -- Not a button: the room Blizzard's own Guild Control button (104
    -- wide, 6px in from the frame's right edge) is lifted into.
    gd.control = CreateFrame("Frame", nil, win.footer)
    gd.control:SetSize(104, 22)
    gd.impeach = FooterButton(win.footer, "Impeach", 70, function()
        StaticPopup_Show("GUILD_IMPEACH")
    end, GUILD_IMPEACH_BUTTON_TEXT)
    ChainRight(win.footer, { gd.control, gd.impeach, gd.add, gd.info })

    gd.list = Kit.List(win, {
        rowHeight = Kit.ROW_H,
        build = BuildGuildRow,
        update = UpdateGuildRow,
    })
    gd.list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, sy - SORT_H - 4)
    gd.list:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("GUILD_ROSTER_UPDATE")
    ev:RegisterEvent("PLAYER_GUILD_UPDATE")
    ev:RegisterEvent("GUILD_MOTD")
    pcall(ev.RegisterEvent, ev, "GUILD_RANKS_UPDATE")
    ev:SetScript("OnEvent", GuildQueue)
    -- The detail panel closing (its own X, or Blizzard's update) clears
    -- the selected row.
    if GuildMemberDetailFrame then GuildMemberDetailFrame:HookScript("OnHide", GuildQueue) end

    win:HookScript("OnShow", function()
        gd.query = ""
        gd.search:SetText("")
        gd.chipOnline:SetOn(not GetGuildRosterShowOffline())
        SyncSilence()
        RequestRoster(false)
        GuildRefresh()
    end)
    win:HookScript("OnHide", function()
        LiftControl(false)
        SyncSilence()
    end)
    covers.guild = { win = win, needsPortrait = true }
    return win
end

local function ApplyGuild()
    if not FriendsFrame or not GuildFrame then return end
    -- Only FriendsFrame's own tab page; a standalone guild window (the
    -- Communities UI) is somebody else's layout.
    if GuildFrame:GetParent() ~= FriendsFrame then return end
    if Enabled("guildwin") then
        BuildGuild()
        gd.win.Reanchor()
        gd.win:Show()
        if gd.win:IsVisible() then GuildRefresh() end
    elseif gd.win then
        gd.win:Hide()
    end
    SyncSilence()
end

-- ============================================================
-- MODULES
-- ============================================================
-- Each page checks its own toggle every time its page opens, so turning
-- one off never needs a reload.
Modules.friendswin = function()
    local hosts = FriendsHosts()
    if #hosts == 0 or not C_FriendList or ns._zFriendsWin then return end
    ns._zFriendsWin = true
    ApplyFriends()
    -- every friends list the client has: the cover follows the one opening
    for _, h in ipairs(hosts) do h:HookScript("OnShow", function(self) ApplyFriends(self) end) end
    -- Forever's modern list sits at the window's own level; anything of
    -- the page that still draws above the cover is hidden under it
    if ModernList() and fr.win then
        fr.win:HookScript("OnShow", function(self)
            if Modern() then Kit.Silence(Kit.AboveCover(self:GetParent(), self)) end
        end)
        fr.win:HookScript("OnHide", function(self)
            if Modern() then Kit.Unsilence(Kit.AboveCover(self:GetParent(), self)) end
        end)
    end
end

Modules.whowin = function()
    local host = WhoHost()
    if not host and not _G.WhoFrame and C_FriendList and not ns._zWhoWin and not ns._zWhoWait then
        -- Forever: the Who list comes with the group finder, loaded on
        -- demand - come back when it is in (a frame late, after its skin)
        ns._zWhoWait = true
        local watch = CreateFrame("Frame")
        watch:RegisterEvent("ADDON_LOADED")
        watch:SetScript("OnEvent", function(self, _, name)
            if name ~= "Blizzard_GroupFinder_VanillaStyle" then return end
            self:UnregisterEvent("ADDON_LOADED")
            C_Timer.After(0, function() if Modules.whowin then Modules.whowin() end end)
        end)
        return
    end
    if not host or (not WhoInLFG() and not FriendsFrame) or not C_FriendList or ns._zWhoWin then return end
    ns._zWhoWin = true
    ApplyWho()
    host:HookScript("OnShow", ApplyWho)
end

Modules.guildwin = function()
    if not FriendsFrame or not GuildFrame or ns._zGuildWin then return end
    ns._zGuildWin = true
    ApplyGuild()
    GuildFrame:HookScript("OnShow", ApplyGuild)
end

-- shared with later ZacUI files
ns.SocialWindow = {
    Apply = function()
        ApplyFriends()
        ApplyWho()
        ApplyGuild()
    end,
}
