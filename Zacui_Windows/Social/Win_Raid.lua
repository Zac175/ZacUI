-- Win_Raid - ZacUI's Raid page: the eight groups as flat cards, members
-- dragged between them, Blizzard's raid menu on right-click.
-- Part of ZacUI; load order is set by the TOC.
--
-- A COVER ON RaidFrame, NOT A REPLACEMENT OF IT. RaidFrame is the Raid
-- tab's sub-frame (FriendsFrame claims it with ClaimRaidFrame before
-- showing it), so a cover parented to it opens and closes with the tab.
-- Blizzard_RaidUI's own layout - RaidGroup1-8 and the forty SECURE
-- RaidGroupButtonN unit buttons - stays underneath, untouched: nothing
-- here shows, hides, moves or re-parents any of it, so there is nothing
-- to refuse in combat. The cover needs Blizzard_RaidUI for nothing; its
-- data comes straight from GetRaidRosterInfo.
--
-- WHY NO SECURE ROWS. The member rows are plain buttons, and they can be:
-- in this client Blizzard's own raid buttons never get a "type" attribute
-- (SecureUnitButton_OnLoad is not called on them), so a left-click on one
-- does nothing, and their right-click is plain Lua -
-- RaidGroupButton_OpenMenu calls UnitPopup_OpenMenu("RAID", ...). Moving
-- members is SetRaidSubgroup / SwapRaidSubgroup, which Blizzard calls
-- from ordinary drag handlers. So none of this window is protected and it
-- works the same in and out of combat - except the drag, which is
-- refused in combat by choice (the roster should not be reshuffled
-- mid-pull).
--
-- WHY FORTY FIXED ROWS AND NOT A Kit.List. A raid is at most eight groups
-- of five and every slot has a fixed place - a grid, not a scrolling
-- list - exactly as Blizzard lays it out.
--
-- THE HEADER STAYS BLIZZARD'S (see Win_Social): FriendsFrame is protected
-- once the raid buttons exist, so the cover starts under the header's
-- hairline and Blizzard's title and secure X stay on top. The attic
-- controls it covers (All Assist, Raid Info, Ready Check) are rebuilt in
-- the toolbar and footer; the class count column that hangs off the
-- frame's right edge and the portrait are silenced while the cover is up.
--
--   Drag a member       move to another group; onto a member swaps them
--                       (leader or assistant, out of combat)
--   Right-click         Blizzard's raid menu (promote, remove), plus a
--                       Main Tank / Main Assist strip beside it for the
--                       leader and assists (out of combat)
--   Hover               Blizzard's unit tooltip
--   All assist          everyone an assistant (leader)
--   Ready Check / Raid Info / Convert to Raid or Party

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

local NUM_GROUPS = NUM_RAID_GROUPS or 8
local PER_GROUP = MEMBERS_PER_RAID_GROUP or 5
local MAX_MEMBERS = MAX_RAID_MEMBERS or 40
local ICON = 10
local HEADER_H = 15
local CARD_GAP = 4

-- Blizzard's own icon files (RaidGroupFrame_Update).
local TEX_LEADER = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local TEX_ASSIST = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
local TEX_MT     = "Interface\\GroupFrame\\UI-Group-MainTankIcon"
local TEX_MA     = "Interface\\GroupFrame\\UI-Group-MainAssistIcon"
local TEX_ML     = "Interface\\GroupFrame\\UI-Group-MasterLooter"
local TEX_READY    = READY_CHECK_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Ready"
local TEX_NOTREADY = READY_CHECK_NOT_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-NotReady"
local TEX_WAITING  = READY_CHECK_WAITING_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Waiting"

local rw = { cards = {}, lastStatus = {} }

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.raidwin ~= false
end

local function IsLeader() return UnitIsGroupLeader("player") and true or false end
local function IsLeadOrAssist()
    return (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and true or false
end

local ClassRGB = Kit.ClassRGB

local function ErrorMessage(text)
    if UIErrorsFrame and text then UIErrorsFrame:AddMessage(text, Kit.TextRGB("red")) end
end

-- One redraw per frame for a roster storm; health-driven redraws (the
-- dead state) at most four times a second. Neither runs while the page
-- is off screen.
local Refresh
local function RaidShown() return rw.win ~= nil and rw.win:IsVisible() end
local Queue = Kit.Coalesce(function() Refresh() end, function() return rw.win end)
local QueueSlow = ns.Coalescer(function() Refresh() end, 0.25, RaidShown)

-- ============================================================
-- LEFTOVERS
-- ============================================================
-- Blizzard pieces the cover does not hide: the class count column
-- anchored OFF the frame's right edge (Blizzard_RaidUI, so looked up
-- fresh every time - it loads on the first roster update), and the attic
-- controls whose top pixel sits above the cover's edge. None is secure.
-- WHERE THE RAID PAGE LIVES. Classic: RaidFrame under FriendsFrame. WoW
-- Forever (2026-11-07): the modern social window, SocialUIFrame, with
-- the raid list as its RaidFrame content frame under the Raid tab - the
-- cover hangs there, under the Battle.net bar, with ZacUI's title bar
-- from Kit.ModernHeader on top (see Win_Social).
-- Both windows can exist on Forever and the game picks which one opens
-- (it can flip mid-session), so the cover follows whichever raid page is
-- showing (Apply), as Win_Social's does.
local socialMode                     -- "modern" (SocialUIFrame) | nil (FriendsFrame)
local function Modern() return socialMode == "modern" end
local function Panel()
    if Modern() then return _G.SocialUIFrame end
    return _G.FriendsFrame
end
local function ModernRaid()
    local sui = _G.SocialUIFrame
    local rf = sui and rawget(sui, "RaidFrame")
    return type(rf) == "table" and rf or nil
end
local function RaidHosts()
    local t = {}
    if _G.FriendsFrame and _G.RaidFrame then t[#t + 1] = _G.RaidFrame end
    local m = ModernRaid()
    if m then t[#t + 1] = m end
    return t
end
local function RaidHost(shown)
    if shown then return shown end
    for _, h in ipairs(RaidHosts()) do if h:IsVisible() then return h end end
    if rw.host then return rw.host end
    return ModernRaid() or _G.RaidFrame
end
local function SetRaidHost(host)
    rw.host = host
    socialMode = (host ~= nil and host == ModernRaid()) and "modern" or nil
end

local function Leftovers()
    local list = {}
    local function Add(x) if x then list[#list + 1] = x end end
    for i = 1, (MAX_RAID_CLASS_BUTTONS or 15) do Add(_G["RaidClassButton" .. i]) end
    Add(_G.RaidFrameAllAssistCheckButton)
    Add(_G.RaidFrameRaidInfoButton)
    Add(_G.RaidFrameReadyCheckButton)
    -- Forever: whatever of the modern raid page still draws above the cover
    if Modern() and rw.win then Kit.AboveCover(rw.win:GetParent(), rw.win, list) end
    return list
end

-- The portrait sits at frame level 400 over the cover's top-left corner.
-- Win_Social silences the same frames for its Who and Guild covers and
-- the fade state lives on the frames, so the rule is shared: faded while
-- ANY cover that needs it is on screen. Page switches hide the old page
-- after showing the new one, so both modules re-check on every show/hide.
local portrait
local function Portrait()
    if portrait then return portrait end
    portrait = {}
    if _G.FriendsFrame and _G.FriendsFrame.PortraitContainer then portrait[#portrait + 1] = _G.FriendsFrame.PortraitContainer end
    local sui = _G.SocialUIFrame
    if sui and rawget(sui, "PortraitContainer") then portrait[#portrait + 1] = sui.PortraitContainer end
    if _G.FriendsFramePortrait then portrait[#portrait + 1] = _G.FriendsFramePortrait end
    return portrait
end

local function Vis(name)
    local f = _G[name]
    return f and f:IsVisible() and true or false
end

-- Faded only, the mouse left alone: Kit.Unsilence turns the mouse back ON,
-- which would make the portrait texture (and its container, which never
-- took the mouse) start eating clicks. Same _zKitAlpha field as the kit,
-- so Win_Social's path and this one undo each other.
local function FadePortrait(on)
    for _, f in ipairs(Portrait()) do
        if on then
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

local function SyncPortrait()
    if not Panel() then return end
    local need = (rw.win and rw.win:IsVisible()) or Vis("ZacUIWhoWindow") or Vis("ZacUIGuildWindow")
    FadePortrait(need and true or false)
end

-- ============================================================
-- DATA
-- ============================================================
-- GetRaidRosterInfo in Blizzard's order, slotted by subgroup with the same
-- "at most five" guard Blizzard uses against a server hiccup.
local function Roster()
    local groups = {}
    for g = 1, NUM_GROUPS do groups[g] = {} end
    local stats = { total = 0, offline = 0, dead = 0 }
    if not IsInRaid() then return groups, stats end
    local hold = rw.rcHold
    if hold and GetTime() > (rw.rcHoldUntil or 0) then
        hold, rw.rcHold = nil, nil
    end
    local status = {}
    local n = math.min(GetNumGroupMembers() or 0, MAX_MEMBERS)
    for i = 1, n do
        local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
        local grp = subgroup and groups[subgroup]
        if grp and #grp < PER_GROUP then
            local unit = "raid" .. i
            local rc = GetReadyCheckStatus and GetReadyCheckStatus(unit)
            name = name or (UNKNOWN or "Unknown")
            if rc then status[name] = rc elseif hold then rc = hold[name] end
            grp[#grp + 1] = {
                index = i, unit = unit, name = name, rank = rank or 0, group = subgroup,
                level = (level and level > 0) and level or nil, class = class, file = fileName,
                zone = zone, online = online and true or false, dead = isDead and true or false,
                role = role, ml = isML and true or false, ready = rc,
            }
            stats.total = stats.total + 1
            if not online then
                stats.offline = stats.offline + 1
            elseif isDead then
                stats.dead = stats.dead + 1
            end
        end
    end
    if next(status) then rw.lastStatus = status end
    return groups, stats
end

-- ============================================================
-- DRAG AND DROP
-- ============================================================
-- A ghost label follows the cursor while a member is held; the card and
-- slot under it light up. Its OnUpdate exists only for the drag.
local drag

local function CanMove()
    return IsInRaid() and IsLeadOrAssist() and not InCombatLockdown()
end

local function PaintDropTarget(tg, ts)
    for g, card in ipairs(rw.cards) do
        local hot = drag and g == tg and g ~= drag.group
        card._zBorderKey = hot and "accent" or "border"
        card:_zPaint()
        for s, slot in ipairs(card.slots) do
            slot.drop:SetShown(hot and s == ts and true or false)
        end
    end
end

-- The card and slot under the cursor, or nil.
local function FindTarget()
    for g, card in ipairs(rw.cards) do
        if card:IsShown() and card:IsMouseOver() then
            for s, slot in ipairs(card.slots) do
                if slot:IsMouseOver() then return g, s end
            end
            return g, nil
        end
    end
    return nil
end

local function GhostUpdate(self, elapsed)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale)
    self._zAcc = (self._zAcc or 0) + (elapsed or 0)
    if self._zAcc < 0.05 then return end
    self._zAcc = 0
    PaintDropTarget(FindTarget())
end

local function Ghost()
    if rw.ghost then return rw.ghost end
    local g = UI.Box(UIParent, "ui", "headerBg", { borderKey = "accent" })
    g:SetFrameStrata("TOOLTIP")
    g:SetHeight(18)
    g:EnableMouse(false)
    g.text = UI.Font(g, F.SMALL, { justify = "LEFT" })
    g.text:SetPoint("LEFT", 6, 0)
    g.text:SetWordWrap(false)
    g:Hide()
    rw.ghost = g
    return g
end

-- Still the same person in the same group? The roster can change under a
-- held member (someone leaves, a second assistant moves them).
local function StillAt(index, name, group)
    local n, _, subgroup = GetRaidRosterInfo(index)
    return n == name and (group == nil or subgroup == group)
end

-- RaidGroupButton_OnDragStop's rules: onto a member of another group
-- swaps the two, onto a free slot (or the card) of another group with
-- room moves the member there, anything else does nothing.
local function Drop(tg, ts)
    local d = drag
    if not d or not tg or tg == d.group then return end
    if not CanMove() or not StillAt(d.index, d.name, d.group) then return end
    local card = rw.cards[tg]
    local other = ts and card and card.slots[ts] and card.slots[ts].member
    if other then
        if StillAt(other.index, other.name, tg) then
            SwapRaidSubgroup(d.index, other.index)
        end
    elseif card and (card.count or 0) < PER_GROUP then
        SetRaidSubgroup(d.index, tg)
    end
end

local function StopDrag(drop)
    if not drag then return end
    local tg, ts
    if drop then tg, ts = FindTarget() end
    if rw.ghost then
        rw.ghost:SetScript("OnUpdate", nil)
        rw.ghost:Hide()
    end
    if drag.row then drag.row:SetAlpha(1) end
    if drop then Drop(tg, ts) end
    drag = nil
    PaintDropTarget(nil)
    Queue()
end

local function StartDrag(row)
    local m = row.member
    if not m then return end
    if not IsInRaid() or not IsLeadOrAssist() then return end
    if InCombatLockdown() then
        ErrorMessage(ERR_NOT_IN_COMBAT or "You can't do that while in combat.")
        return
    end
    GameTooltip:Hide()
    drag = { index = m.index, name = m.name, group = m.group, row = row }
    row:SetAlpha(0.4)
    local g = Ghost()
    g.text:SetText(m.name)
    g.text:SetTextColor(ClassRGB(m.file))
    g:SetWidth(math.ceil(g.text:GetStringWidth()) + 14)
    g._zAcc = 0
    g:Show()
    g:SetScript("OnUpdate", GhostUpdate)
    GhostUpdate(g, 1)
end

-- ============================================================
-- MEMBER ROWS
-- ============================================================
local function MemberTooltip(row)
    local m = row.member
    if not m then return end
    -- Blizzard's raid button tooltip (UnitFrame_UpdateTooltip reads
    -- .unit and keeps itself fresh through .UpdateTooltip).
    row.unit = m.unit
    if m.online and UnitFrame_UpdateTooltip and UnitExists(m.unit) then
        UnitFrame_UpdateTooltip(row)
        if GameTooltip:IsShown() then return end
    end
    row.UpdateTooltip = nil
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(m.name, ClassRGB(m.file))
    local bc = GetColor("tooltip", "body")
    local line = ((m.level and (m.level .. " ")) or "") .. (m.class or "")
    if line ~= "" then GameTooltip:AddLine(line, bc.r, bc.g, bc.b) end
    if m.zone and m.zone ~= "" then GameTooltip:AddLine(m.zone, Kit.TextRGB("gray")) end
    if not m.online then GameTooltip:AddLine(PLAYER_OFFLINE or "Offline", Kit.TextRGB("gray")) end
    GameTooltip:Show()
end

-- ============================================================
-- MAIN TANK / MAIN ASSIST
-- ============================================================
-- This client's raid menu has no Main Tank entry, and SetPartyAssignment
-- is protected, so addon code cannot call it. A secure macro button can:
-- /maintank and /mainassist run the same Blizzard code. The strip opens
-- beside the raid menu on right-click (leader or assist, out of combat;
-- secure attributes cannot change in combat) and closes with it.
local strip
local ASSIGN = {
    { key = "MAINTANK",   set = "Set Main Tank",   clear = "Remove Main Tank",   on = "/maintank ",   off = "/maintankoff " },
    { key = "MAINASSIST", set = "Set Main Assist", clear = "Remove Main Assist", on = "/mainassist ", off = "/mainassistoff " },
}

local function HideStrip()
    if strip and strip:IsShown() and not InCombatLockdown() then strip:Hide() end
end

local function BuildStrip()
    strip = CreateFrame("Frame", "ZacUIRaidAssignStrip", UIParent)
    strip:SetFrameStrata("FULLSCREEN_DIALOG")
    strip:SetFrameLevel(200)
    strip:SetClampedToScreen(true)
    UI.Fill(strip, "ui", "windowBg")
    UI.Border(strip, "ui", "border")
    strip.title = UI.Font(strip, F.SMALL, { cat = "text", key = "gold" })
    strip.title:SetPoint("TOPLEFT", 8, -7)
    strip.rows = {}
    for i, a in ipairs(ASSIGN) do
        local look = UI.Button(strip, a.set, { width = 150, height = 22 })
        look:SetPoint("TOPLEFT", 6, -22 - (i - 1) * 26)
        -- the secure click target sits over the ZacUI-styled button
        local sec = CreateFrame("Button", nil, look, "SecureActionButtonTemplate")
        sec:SetAllPoints(look)
        sec:RegisterForClicks("LeftButtonUp")
        sec:SetAttribute("type", "macro")
        sec:SetScript("OnEnter", function() local f = look:GetScript("OnEnter") if f then f(look) end end)
        sec:SetScript("OnLeave", function() local f = look:GetScript("OnLeave") if f then f(look) end end)
        sec:SetScript("PostClick", function()
            HideStrip()
            if Menu and Menu.GetManager then
                local mgr = Menu.GetManager()
                if mgr and mgr.CloseMenus then pcall(mgr.CloseMenus, mgr) end
            end
            if CloseDropDownMenus then CloseDropDownMenus() end
            C_Timer.After(0.3, Queue)
        end)
        strip.rows[i] = { look = look, sec = sec, a = a }
    end
    strip:SetSize(162, 22 + #ASSIGN * 26 + 4)
    strip:Hide()
end

-- The menu UnitPopup_OpenMenu just opened, when this client can say.
local function OpenMenuFrame()
    if Menu and Menu.GetManager then
        local mgr = Menu.GetManager()
        if mgr and mgr.GetOpenMenu then
            local ok, f = pcall(mgr.GetOpenMenu, mgr)
            if ok and f then return f end
        end
    end
    return nil
end

local function ShowStrip(m)
    if not (m and m.name and IsInRaid() and IsLeadOrAssist()) or InCombatLockdown() then
        HideStrip()
        return
    end
    if not strip then BuildStrip() end
    strip.title:SetText(m.name)
    for _, r in ipairs(strip.rows) do
        local has = m.role == r.a.key
        r.look:SetLabel(has and r.a.clear or r.a.set)
        r.sec:SetAttribute("macrotext", (has and r.a.off or r.a.on) .. m.name)
    end
    strip:ClearAllPoints()
    local menu = OpenMenuFrame()
    if menu then
        strip:SetPoint("TOPLEFT", menu, "TOPRIGHT", 4, 0)
        if not menu._zuiStripHook then
            menu._zuiStripHook = true
            menu:HookScript("OnHide", function() C_Timer.After(0, function()
                -- a menu frame is reused: only close if no menu came back
                if not (OpenMenuFrame() and OpenMenuFrame():IsShown()) then HideStrip() end
            end) end)
        end
    else
        local x, y = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale()
        strip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / sc + 12, y / sc)
    end
    strip:Show()
end

local function BuildSlot(card, s)
    local row = CreateFrame("Button", nil, card)
    row:RegisterForClicks("RightButtonUp")
    row:RegisterForDrag("LeftButton")

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe._zui_own = true
    stripe:SetAllPoints()
    stripe:SetTexture(FLAT)
    row.stripe = stripe

    local drop = row:CreateTexture(nil, "BORDER")
    drop._zui_own = true
    drop:SetAllPoints()
    drop:SetTexture(FLAT)
    drop:Hide()
    row.drop = drop

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl._zui_own = true
    hl:SetAllPoints()
    hl:SetTexture(FLAT)
    row.hl = hl

    -- Leader / assistant, main tank / assist, master looter: packed from
    -- the left, only the ones that apply (Blizzard's "jobs").
    row.icons = {}
    for i = 1, 3 do
        local t = row:CreateTexture(nil, "ARTWORK")
        t._zui_own = true
        t:SetSize(ICON, ICON)
        t:Hide()
        row.icons[i] = t
    end

    local ready = row:CreateTexture(nil, "ARTWORK")
    ready._zui_own = true
    ready:SetSize(ICON, ICON)
    ready:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    ready:Hide()
    row.ready = ready

    -- Right to left: ready mark, class / state, level, then the name
    -- taking what is left. Fixed widths on the right so the columns line
    -- up across all eight cards and the name can never run under them.
    row.state = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.state:SetWidth(46)
    row.state:SetPoint("RIGHT", ready, "LEFT", -2, 0)
    row.state:SetWordWrap(false)
    row.level = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.level:SetWidth(15)
    row.level:SetPoint("RIGHT", row.state, "LEFT", -3, 0)
    row.level:SetWordWrap(false)
    row.name = UI.Font(row, F.SMALL, { justify = "LEFT" })
    row.name:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.name:SetPoint("RIGHT", row.level, "LEFT", -3, 0)
    row.name:SetWordWrap(false)

    row.empty = UI.Font(row, F.SMALL, { justify = "CENTER", cat = "text", key = "disabled" })
    row.empty:SetPoint("CENTER")
    row.empty:SetText(EMPTY or "Empty")

    row:SetScript("OnEnter", MemberTooltip)
    row:SetScript("OnLeave", function(self)
        self.UpdateTooltip = nil
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self, button)
        local m = self.member
        if button ~= "RightButton" or not m or drag then return end
        -- RaidGroupButton_OpenMenu, with the same context.
        if UnitPopup_OpenMenu then
            UnitPopup_OpenMenu("RAID", { unit = m.unit, name = m.name })
        end
        ShowStrip(m)
    end)
    row:SetScript("OnDragStart", StartDrag)
    row:SetScript("OnDragStop", function() StopDrag(true) end)
    row.slot = s
    return row
end

local function PlaceIcons(row, m)
    local tex = {}
    if m then
        if m.rank == 2 then tex[#tex + 1] = TEX_LEADER elseif m.rank == 1 then tex[#tex + 1] = TEX_ASSIST end
        if m.role == "MAINTANK" then tex[#tex + 1] = TEX_MT elseif m.role == "MAINASSIST" then tex[#tex + 1] = TEX_MA end
        if m.ml then tex[#tex + 1] = TEX_ML end
    end
    local last
    for i, t in ipairs(row.icons) do
        if tex[i] then
            t:SetTexture(tex[i])
            t:ClearAllPoints()
            if last then
                t:SetPoint("LEFT", last, "RIGHT", 0, 0)
            else
                t:SetPoint("LEFT", row, "LEFT", 2, 0)
            end
            t:Show()
            last = t
        else
            t:Hide()
        end
    end
    if last then
        row.name:SetPoint("LEFT", last, "RIGHT", 2, 0)
    else
        row.name:SetPoint("LEFT", row, "LEFT", 3, 0)
    end
end

local function UpdateSlot(row, m, s)
    row.member = m
    -- Blizzard's tooltip refresh reads .unit; keep it on this row's member.
    row.unit = m and m.unit or nil
    local e = GetColor("ui", "elementBg")
    row.stripe:SetVertexColor(e.r, e.g, e.b, (s % 2 == 0) and 0.30 or 0.10)
    local a = GetColor("ui", "accent")
    row.drop:SetVertexColor(a.r, a.g, a.b, 0.25)
    local h = GetColor("button", "hover")
    row.hl:SetVertexColor(h.r, h.g, h.b, 0.5)
    PlaceIcons(row, m)
    if not m then
        row.name:SetText("")
        row.level:SetText("")
        row.state:SetText("")
        row.ready:Hide()
        row.empty:Show()
        row.UpdateTooltip = nil
        return
    end
    row.empty:Hide()
    row.name:SetText(m.name)
    row.level:SetText(m.level or "")
    -- Blizzard's colours: class colour, red when dead, grey offline -
    -- the state word replaces the class name for the last two.
    local r, g, b
    if not m.online then
        r, g, b = Kit.TextRGB("gray")
        row.state:SetText(PLAYER_OFFLINE or "Offline")
    elseif m.dead then
        r, g, b = Kit.TextRGB("red")
        row.state:SetText(DEAD or "Dead")
    else
        r, g, b = ClassRGB(m.file)
        row.state:SetText(m.class or "")
    end
    row.name:SetTextColor(r, g, b)
    row.level:SetTextColor(r, g, b)
    row.state:SetTextColor(r, g, b)
    if m.ready == "ready" then
        row.ready:SetTexture(TEX_READY)
        row.ready:Show()
    elseif m.ready == "notready" then
        row.ready:SetTexture(TEX_NOTREADY)
        row.ready:Show()
    elseif m.ready == "waiting" then
        row.ready:SetTexture(TEX_WAITING)
        row.ready:Show()
    else
        row.ready:Hide()
    end
end

-- ============================================================
-- CARDS
-- ============================================================
local function BuildCard(parent, g)
    local card = UI.Box(parent, "ui", "cardBg")
    card.group = g
    card.title = UI.Font(card, F.SMALL, { cat = "text", key = "gold", justify = "LEFT" })
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -3)
    card.title:SetText((GROUP or "Group") .. " " .. g)
    card.title:SetWordWrap(false)
    card.countText = UI.Font(card, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    card.countText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -3)
    card.countText:SetWordWrap(false)
    card.slots = {}
    for s = 1, PER_GROUP do card.slots[s] = BuildSlot(card, s) end
    return card
end

-- Two columns of four, sized from whatever room the cover has (its
-- height follows the panel inset, which the owner can re-dial).
local function Layout()
    local grid = rw.grid
    local w, h = grid:GetWidth() or 0, grid:GetHeight() or 0
    if w < 50 or h < 50 then return end
    local cw = math.floor((w - Kit.GAP) / 2)
    local rowsOfCards = math.ceil(NUM_GROUPS / 2)
    local ch = math.floor((h - (rowsOfCards - 1) * CARD_GAP) / rowsOfCards)
    local rh = math.floor((ch - HEADER_H - 3) / PER_GROUP)
    rh = math.max(11, math.min(18, rh))
    ch = HEADER_H + rh * PER_GROUP + 3
    for g, card in ipairs(rw.cards) do
        local col = (g - 1) % 2
        local line = math.floor((g - 1) / 2)
        card:ClearAllPoints()
        card:SetSize(cw, ch)
        card:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (cw + Kit.GAP), -line * (ch + CARD_GAP))
        for s, row in ipairs(card.slots) do
            row:ClearAllPoints()
            row:SetHeight(rh)
            row:SetPoint("TOPLEFT", card, "TOPLEFT", 2, -(HEADER_H + (s - 1) * rh))
            row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -(HEADER_H + (s - 1) * rh))
        end
    end
end

-- ============================================================
-- REFRESH
-- ============================================================
local function Buttons()
    local inRaid = IsInRaid()
    local lead = IsLeader()

    -- Convert: to raid from a party you lead (Blizzard's button rule),
    -- back to a party from a raid of five or fewer (the unit menu's rule).
    if not inRaid then
        rw.convert:SetLabel(CONVERT_TO_RAID or "Convert to Raid")
        rw.convert:Show()
        rw.convert:SetDisabled(not (UnitExists("party1") and lead))
    else
        rw.convert:SetLabel(CONVERT_TO_PARTY or "Convert to Party")
        local instance = LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
        -- Only offered when it can work: Blizzard's raid page has no such
        -- button at all, and a dead one would crowd the footer.
        rw.convert:SetShown(lead and not instance and (GetNumGroupMembers() or 0) <= PER_GROUP)
        rw.convert:SetDisabled(false)
    end
    rw.convert:SetWidth(math.max(96, math.ceil(rw.convert._zText:GetStringWidth()) + 16))

    rw.readyCheck:SetShown(IsInGroup() and IsLeadOrAssist())
    local hasInfo = (GetNumSavedInstances and GetNumSavedInstances() or 0) > 0
    local infoShown = RaidInfoFrame and RaidInfoFrame:IsShown()
    rw.raidInfo:SetDisabled(not (hasInfo or infoShown))
    rw.raidInfo:SetActive(infoShown and true or false)

    -- ChainRight: hidden buttons leave no hole.
    local last
    for _, b in ipairs({ rw.raidInfo, rw.readyCheck, rw.convert }) do
        if b:IsShown() then
            b:ClearAllPoints()
            if last then
                b:SetPoint("RIGHT", last, "LEFT", -4, 0)
            else
                b:SetPoint("RIGHT", rw.win.footer, "RIGHT", -6, 0)
            end
            last = b
        end
    end
    rw.hint:SetPoint("RIGHT", last or rw.win.footer, last and "LEFT" or "RIGHT", -6, 0)

    if not inRaid then
        rw.hint:SetText("")
    elseif not IsLeadOrAssist() then
        rw.hint:SetText("")
    elseif InCombatLockdown() then
        rw.hint:SetText("Groups are locked in combat.")
    else
        rw.hint:SetText("Drag members between groups.")
    end

    rw.allAssist:SetShown(inRaid)
    rw.allAssist:SetOn(IsEveryoneAssistant and IsEveryoneAssistant() or false)
end

function Refresh()
    if not rw.win or not rw.win:IsVisible() then return end
    local inRaid = IsInRaid()
    -- A held member whose drop can no longer work (left the raid, lost
    -- lead or assist): let go, or the ghost would follow the cursor on a
    -- hidden card.
    if drag and not (inRaid and IsLeadOrAssist()) then StopDrag(false) end
    local groups, stats = Roster()
    for g, card in ipairs(rw.cards) do
        local members = groups[g]
        card.count = #members
        card.countText:SetText(#members .. "/" .. PER_GROUP)
        for s, row in ipairs(card.slots) do
            -- A row being dragged keeps its member until the drop.
            if not (drag and drag.row == row) then UpdateSlot(row, members[s], s) end
        end
        card:SetShown(inRaid)
    end
    rw.notice:SetShown(not inRaid)

    if inRaid then
        local bits = { (RAID or "Raid") .. "  " .. stats.total .. " / " .. MAX_MEMBERS }
        if stats.offline > 0 then bits[#bits + 1] = stats.offline .. " offline" end
        if stats.dead > 0 then bits[#bits + 1] = stats.dead .. " dead" end
        rw.summary:SetText(table.concat(bits, "  |  "))
    elseif IsInGroup() then
        rw.summary:SetText((PARTY or "Party") .. "  " .. (GetNumGroupMembers() or 0) .. " / " .. PER_GROUP)
    else
        rw.summary:SetText("")
    end
    Buttons()
end

-- ============================================================
-- WINDOW
-- ============================================================
-- Just under the skinned header's gold hairline, like the Who and Guild
-- covers.
local function BelowHairline(ins)
    local lineY = (ns.GetPanelLineY and ns.GetPanelLineY("FriendsFrame", nil)) or -24
    return -(ins.t or 0) + lineY - 1
end

local function FooterButton(parent, label, width, onClick, tip)
    local b = UI.Button(parent, label, { width = width, height = 22 })
    b:SetScript("OnClick", onClick)
    b:SetMotionScriptsWhileDisabled(true)
    if tip then UI.Tooltip(b, label, tip) end
    return b
end

local function DoConvert()
    if IsInRaid() then
        local fn = ConvertToParty or (C_PartyInfo and C_PartyInfo.ConvertToParty)
        if fn then fn() end
    else
        local fn = ConvertToRaid or (C_PartyInfo and C_PartyInfo.ConvertToRaid)
        if fn then fn() end
    end
end

local function DoReadyCheckClick()
    local fn = (C_PartyInfo and C_PartyInfo.DoReadyCheck) or DoReadyCheck
    if fn then fn() end
end

local function ToggleRaidInfo()
    -- RaidFrameRaidInfoButton's OnClick.
    if not RaidInfoFrame then return end
    if RaidInfoFrame:IsShown() then RaidInfoFrame:Hide() else RaidInfoFrame:Show() end
    Buttons()
end

local ev
local function Build()
    if rw.win then return rw.win end
    local win = Kit.Cover(rw.host, {
        name = "ZacUIRaidWindow",
        insetName = Modern() and "SocialUIFrame" or "FriendsFrame",
        onClose = function() HideUIPanel(Panel()) end,
    })
    rw.win = win
    win.titleBar:Hide()
    win._zKeepHeader = Modern() or nil      -- Forever: ZacUI's title bar stays on the window
    win.top = -Kit.PAD
    win.Reanchor = function()
        local panel = Panel()
        if not panel then return end
        local ins = ns.GetPanelInset(Modern() and "SocialUIFrame" or "FriendsFrame", panel)
        local top = BelowHairline(ins)
        if Modern() then
            -- under the Battle.net bar (Win_Social's PageCover does the same)
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
    local y = win.top

    -- Toolbar: counts on the left, All assist on the right. The chip is
    -- Blizzard's RaidFrameAllAssistCheckButton: leader only, and it
    -- follows the server's answer (refreshed on the roster update).
    rw.allAssist = Kit.Chip(win, "All assist", false, function(on)
        if not IsLeader() then
            ErrorMessage(ALL_ASSIST_NOT_LEADER_ERROR or "Only the raid leader can do that.")
            return false
        end
        if C_PartyInfo and C_PartyInfo.SetEveryoneIsAssistant then
            C_PartyInfo.SetEveryoneIsAssistant(on)
        end
        if SOUNDKIT then
            PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
    end)
    rw.allAssist:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y)
    rw.allAssist:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local tc = GetColor("tooltip", "title")
        GameTooltip:AddLine(ALL_ASSIST_LABEL or "All assist", tc.r, tc.g, tc.b)
        local bc = GetColor("tooltip", "body")
        GameTooltip:AddLine(ALL_ASSIST_DESCRIPTION or "Make every member of the raid an assistant.",
            bc.r, bc.g, bc.b, true)
        if not IsLeader() then
            GameTooltip:AddLine(ALL_ASSIST_NOT_LEADER_ERROR or "Only the raid leader can change this.",
                Kit.TextRGB("red"))
        end
        GameTooltip:Show()
    end)
    rw.allAssist:HookScript("OnLeave", function() GameTooltip:Hide() end)

    rw.summary = UI.Font(win, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    rw.summary:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
    rw.summary:SetPoint("TOPRIGHT", win, "TOPRIGHT", -(Kit.PAD + 90), y)
    rw.summary:SetHeight(Kit.SEARCH_H)
    rw.summary:SetJustifyV("MIDDLE")
    rw.summary:SetWordWrap(false)

    win.footer = Kit.Footer(win, Kit.FOOTER_H)
    rw.raidInfo = FooterButton(win.footer, RAID_INFO or "Raid Info", 70, ToggleRaidInfo,
        RAID_INFO_DESC or "Your saved raid instances.")
    rw.readyCheck = FooterButton(win.footer, READY_CHECK or "Ready Check", 84, DoReadyCheckClick,
        "Ask everyone in the group to confirm they are ready.")
    rw.convert = FooterButton(win.footer, CONVERT_TO_RAID or "Convert to Raid", 104, DoConvert)
    rw.hint = UI.Font(win.footer, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    rw.hint:SetPoint("LEFT", win.footer, "LEFT", 8, 0)
    rw.hint:SetWordWrap(false)

    -- The grid: everything between the toolbar and the footer.
    local gy = y - Kit.SEARCH_H - Kit.GAP
    local grid = CreateFrame("Frame", nil, win)
    grid:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, gy)
    grid:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)
    rw.grid = grid
    for g = 1, NUM_GROUPS do rw.cards[g] = BuildCard(grid, g) end
    grid:SetScript("OnSizeChanged", Layout)

    -- Not in a raid: Blizzard's own explanation (RaidFrameNotInRaid).
    rw.notice = UI.Font(grid, F.LABEL, { justify = "LEFT" })
    rw.notice:SetPoint("TOPLEFT", grid, "TOPLEFT", 4, -8)
    rw.notice:SetPoint("TOPRIGHT", grid, "TOPRIGHT", -4, -8)
    rw.notice:SetJustifyV("TOP")
    rw.notice:SetWordWrap(true)
    rw.notice:SetText(RAID_DESCRIPTION or "A raid is a group of up to 40 players. Form a party and convert it to a raid below.")

    -- EVENTS. Roster and state changes redraw next frame; UNIT_* events
    -- fire for every unit in the world, so only raid units count. Health
    -- (for the dead state) is registered only while the page is up.
    ev = CreateFrame("Frame", nil, win)
    -- Roster changes come through the core roster (one notice per burst,
    -- 0.1s after it); everything else is registered here.
    ns.Roster.On("Win_Raid", function() Queue() end)
    for _, e in ipairs({ "PARTY_LEADER_CHANGED", "UNIT_CONNECTION",
                         "UNIT_NAME_UPDATE", "UNIT_LEVEL", "READY_CHECK", "READY_CHECK_CONFIRM",
                         "READY_CHECK_FINISHED", "UPDATE_INSTANCE_INFO", "PLAYER_REGEN_DISABLED",
                         "PLAYER_REGEN_ENABLED", "PARTY_LOOT_METHOD_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_DISABLED" then
            StopDrag(false)
            -- the regen event itself still allows hiding a secure frame
            if strip and strip:IsShown() then strip:Hide() end
        elseif event == "READY_CHECK_FINISHED" then
            -- Blizzard keeps the marks up for a while after the check
            -- ends (ReadyCheck_Finish); hold the last answers as long,
            -- with no answer shown as not ready.
            local last = rw.lastStatus or {}
            if IsInRaid() and GetReadyCheckStatus then
                for i = 1, math.min(GetNumGroupMembers() or 0, MAX_MEMBERS) do
                    local name = GetRaidRosterInfo(i)
                    local st = GetReadyCheckStatus("raid" .. i)
                    if name and st then last[name] = st end
                end
            end
            local hold = {}
            for name, st in pairs(last) do
                hold[name] = (st == "waiting") and "notready" or st
            end
            local stay = DEFAULT_READY_CHECK_STAY_TIME or 10
            rw.rcHold, rw.rcHoldUntil = hold, GetTime() + stay
            C_Timer.After(stay + 0.2, Queue)
        elseif event == "READY_CHECK" then
            -- A new check: nothing from the last one carries over.
            rw.rcHold, rw.lastStatus = nil, {}
        end
        if not win:IsVisible() then return end
        if event == "UNIT_HEALTH" then
            if unit and string.find(unit, "^raid%d") then QueueSlow() end
            return
        end
        if (event == "UNIT_CONNECTION" or event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL")
            and not (unit and string.find(unit, "^raid%d")) then
            return
        end
        Queue()
    end)
    if RaidInfoFrame then
        RaidInfoFrame:HookScript("OnShow", Queue)
        RaidInfoFrame:HookScript("OnHide", Queue)
    end

    win:HookScript("OnShow", function()
        pcall(ev.RegisterEvent, ev, "UNIT_HEALTH")
        Kit.Silence(Leftovers())
        SyncPortrait()
        Layout()
        Refresh()
    end)
    win:HookScript("OnHide", function()
        StopDrag(false)
        pcall(ev.UnregisterEvent, ev, "UNIT_HEALTH")
        GameTooltip:Hide()
        Kit.Unsilence(Leftovers())
        SyncPortrait()
    end)
    return win
end

-- Only while RaidFrame is FriendsFrame's own page: ClaimRaidFrame can
-- hand it to RaidParentFrame, and a cover anchored to FriendsFrame would
-- then float where the closed Friends window was.
local function Apply(shown)
    local host = RaidHost(type(shown) == "table" and shown or nil)
    if not host then return end
    SetRaidHost(host)
    if not Panel() then return end
    if Enabled() and host:GetParent() == Panel() then
        Build()
        if rw.win:GetParent() ~= host then
            rw.win:SetParent(host)
            rw.win._zKeepHeader = Modern() or nil
        end
        rw.win.Reanchor()
        rw.win:Show()
        if rw.win:IsVisible() then
            Kit.Silence(Leftovers())
            Layout()
            Refresh()
        end
    elseif rw.win then
        rw.win:Hide()
        Kit.Unsilence(Leftovers())
    end
    SyncPortrait()
end

-- ============================================================
-- MODULE
-- ============================================================
-- RaidFrame itself is always loaded (Blizzard_RaidFrame); only the class
-- column this page silences comes with the load-on-demand
-- Blizzard_RaidUI. That addon's single ns.RegisterLoD slot belongs to the
-- friends skin, so a watcher of our own re-silences when it arrives.
Modules.raidwin = function()
    local hosts = RaidHosts()
    if #hosts == 0 or ns._zRaidWin then return end
    ns._zRaidWin = true
    Apply()
    for _, h in ipairs(hosts) do h:HookScript("OnShow", function(self) Apply(self) end) end
    if ClaimRaidFrame then hooksecurefunc("ClaimRaidFrame", function() Apply() end) end
    -- Win_Social re-checks the shared portrait on its own Apply; follow.
    if ns.SocialWindow and ns.SocialWindow.Apply then
        hooksecurefunc(ns.SocialWindow, "Apply", SyncPortrait)
    end
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not (isLoaded and isLoaded("Blizzard_RaidUI")) then
        local watch = CreateFrame("Frame")
        watch:RegisterEvent("ADDON_LOADED")
        watch:SetScript("OnEvent", function(self, _, name)
            if name ~= "Blizzard_RaidUI" then return end
            self:UnregisterEvent("ADDON_LOADED")
            C_Timer.After(0, function()
                if rw.win and rw.win:IsVisible() then Kit.Silence(Leftovers()) end
            end)
        end)
    end
end
