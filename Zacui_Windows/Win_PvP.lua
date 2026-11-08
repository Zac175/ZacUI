-- Win_PvP - ZacUI's battleground windows: the battlemaster's instance
-- list and the battleground scoreboard, rebuilt as flat ZacUI windows.
-- Part of ZacUI; load order is set by the TOC.
--
-- TWO COVERS, TWO DIFFERENT RULES.
--
-- The battlemaster window (BattlefieldFrame) is a Win_Kit cover whose
-- Join, Join as group, Cancel and X are SECURE "click" buttons laid over
-- Blizzard's own. Joining is a restricted call (C_PvP.JoinBattlefield),
-- and Blizzard's Join handler also hides the panel; running THEIR handler
-- through a secure click does both with Blizzard's own credentials and
-- leaves no addon taint in the panel manager. The cost is the usual one:
-- the cover carries secure buttons, so BattlefieldFrame becomes protected
-- and the module is combat-sensitive (built and re-laid out of combat
-- only; the buttons themselves work in combat). Picking an instance is
-- just C_PvP.SetSelectedBattlefieldByIndex - the same selection Blizzard's
-- Join reads - so the rows are plain buttons.
--
-- The scoreboard (WorldStateScoreFrame) carries NO secure buttons, on
-- purpose: it is opened, resized and closed in the middle of fights by
-- Blizzard's own code, and a protected scoreboard would turn every one of
-- those into a combat lockdown hazard. Sorting, the faction filter and
-- search are local (no SetBattlefieldScoreFaction / SortBattlefieldScoreData
-- calls that Blizzard's own tabs and headers would then disagree with).
-- Blizzard's OnUpdate keeps calling RequestBattlefieldScoreData while the
-- board is up (the client throttles it), so the cover only asks once on
-- show and redraws on UPDATE_BATTLEFIELD_SCORE, one redraw per frame.
--
-- Era 1.15 has no queue-from-anywhere PvP frame (PVPParentFrame /
-- PVPFrame / PVPBattlegroundFrame load only on TBC and later), so there is
-- no cover for one here.
--
--   Battlemaster  click an instance to select it; Join / Join as group
--                 (party leader only) / Cancel, exactly Blizzard's buttons
--   Scoreboard    click a column to sort (again to reverse, a third time
--                 for Blizzard's order); All / Alliance / Horde; search by
--                 name, class or race; right-click a player for Blizzard's
--                 menu, shift-click to put the name in chat; Leave
--                 battleground once the match is decided

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
-- Not on every game version (Core_Flavor's feature table: Retail's PvP window is a page of the group finder):
-- this window stands down here, before it makes a frame or a module.
if ns.FeatureOn and not ns.FeatureOn("win_pvp") then return end

-- shared state from earlier ZacUI files
local AnchorPanel = ns.AnchorPanel
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local TEX_ARROW = ns.TEX_ARROW
local UI = ns.UI

local M, F = UI.M, UI.F

local function Enabled(key)
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules[key] ~= false
end

-- ============================================================
-- SHARED HELPERS
-- ============================================================
-- Faction colour from Blizzard's own table (0 = Horde, 1 = Alliance).
local function FactionRGB(faction)
    local c = PLAYER_FACTION_COLORS and faction and PLAYER_FACTION_COLORS[faction]
    if c and c.r then return c.r, c.g, c.b end
    if c and c.GetRGB then return c:GetRGB() end
    if faction == 0 then return Kit.TextRGB("red") end
    if faction == 1 then return Kit.TextRGB("blue") end
    return Kit.TextRGB("normal")
end

local ClassRGB = Kit.ClassRGB

-- The player's own battle standard as the window icon.
local function FactionIcon()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if f == "Horde" then return "Interface\\Icons\\INV_BannerPVP_01" end
    return "Interface\\Icons\\INV_BannerPVP_02"
end

local function MaxQueues()
    return (GetMaxBattlefieldID and GetMaxBattlefieldID()) or MAX_BATTLEFIELD_QUEUES or 3
end

local function Tip(owner, title, body)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local t = GetColor("tooltip", "title")
    GameTooltip:AddLine(title or "", t.r, t.g, t.b)
    if body and body ~= "" then
        local c = GetColor("tooltip", "body")
        GameTooltip:AddLine(body, c.r, c.g, c.b, true)
    end
    GameTooltip:Show()
end

-- Blizzard's leftovers go through Kit.Silence with QUIET: silenced once
-- (a repeat call leaves an already-faded piece alone) and only Frames lose
-- the mouse - textures and font strings just fade.
local QUIET = { once = true, framesOnly = true }

-- Every region of the Blizzard frame, appended (a literal with a nil hole
-- would stop ipairs). ZacUI skin textures drawn on the frame itself are
-- included on purpose: the cover replaces the skin too, and anything the
-- skin fitted to the frame's full rect would ring the cover. The cover's
-- own textures live on the cover, not here.
local function AddRegions(t, host)
    for _, r in ipairs({ host:GetRegions() }) do t[#t + 1] = r end
end

-- Hover paint for a drawn button whose clicks are taken by a secure
-- overlay: the overlay gets the mouse, so the lift is painted by hand.
local function Hot(b, on)
    if b._zA then
        -- UI.CloseX
        b._zHot = on or nil
        b:_zPaint()
        return
    end
    if on and not b._zDisabled and not b._zActive then
        local c = GetColor("button", "hover")
        b._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1)
        local a = GetColor("ui", "accent")
        b._zText:SetTextColor(a.r, a.g, a.b, 1)
    else
        b:_zPaint()
    end
end

-- A secure button over one of ours that clicks one of Blizzard's: their
-- handler runs with secure credentials, in combat or not. Left button
-- only - a programmatic Click("RightButton") on Blizzard's button would
-- still run its handler. Out of combat only (callers build out of combat).
local function SecureDelegate(visual, target, tip)
    local sb = CreateFrame("Button", nil, visual:GetParent(), "SecureActionButtonTemplate")
    sb:SetAllPoints(visual)
    sb:SetFrameLevel(visual:GetFrameLevel() + 3)
    sb:SetAttribute("useOnKeyDown", false)
    sb:RegisterForClicks("LeftButtonUp")
    sb:SetAttribute("type", "click")
    sb:SetAttribute("clickbutton", target)
    visual:EnableMouse(false)
    sb:SetScript("OnEnter", function(self)
        Hot(visual, true)
        if tip then tip(self) end
    end)
    sb:SetScript("OnLeave", function()
        Hot(visual, false)
        GameTooltip:Hide()
    end)
    return sb
end

-- ============================================================
-- BATTLEMASTER WINDOW (BattlefieldFrame)
-- ============================================================
-- The 384x512 classic shell: the same visible rectangle as the trainer
-- (Blizzard's hit-rect insets are r34 / b75). /zacui inset BattlefieldFrame
-- still overrides it.
local BF_INSET = { l = 11, r = 32, t = 12, b = 74 }
local BF_ROW_H = 22

local bf = {}   -- win, list, descTitle, descBody, status, join, group, cancel, sGroup

-- Blizzard reads the battleground's name and text with the frame's own
-- selectedBG field (nil on Era, which the client answers with the NPC's
-- battleground) - read, never written.
local function BGInfo()
    if not GetBattlegroundInfo then return "", "" end
    local ok, name, _, _, _, _, mapDesc, _, _, _, _, shortDesc, longDesc =
        pcall(GetBattlegroundInfo, BattlefieldFrame and BattlefieldFrame.selectedBG)
    if not ok then return "", "" end
    local text = longDesc
    if not text or text == "" then text = mapDesc end
    if not text or text == "" then text = shortDesc end
    return name or "", text or ""
end

-- Index 1 is Blizzard's fake "First Available" entry, instance i is
-- index i + 1 - the numbering C_PvP's selection uses.
local function BFRows()
    local name = BGInfo()
    local n = GetNumBattlefields and GetNumBattlefields() or 0
    local data = {}
    data[1] = {
        index = 1, first = true,
        title = FIRST_AVAILABLE or "First Available",
        tip = NEWBIE_TOOLTIP_FIRST_AVAILABLE,
    }
    local shown = (name ~= "") and name or (BATTLEFIELDS or "Battleground")
    for i = 1, n do
        local id = tostring((GetBattlefieldInstanceInfo and GetBattlefieldInstanceInfo(i)) or i)
        data[#data + 1] = {
            index = i + 1,
            key = name .. " " .. id,       -- what Blizzard matches queues by
            title = shown .. " " .. id,
            tip = NEWBIE_TOOLTIP_ENTER_BATTLEGROUND,
        }
    end
    -- Queue marks, matched the way Blizzard's list matches them.
    for q = 1, MaxQueues() do
        local status, qMap, qInst = GetBattlefieldStatus(q)
        if status and status ~= "none" and qMap then
            local key = qMap .. " " .. tostring(qInst)
            local hit = false
            for _, e in ipairs(data) do
                if not e.first and e.key == key then
                    e.status = status
                    hit = true
                end
            end
            if not hit and qMap == name and n == 0 and status == "queued" then
                data[1].status = status
            end
        end
    end
    return data, name
end

local function QueueSummary()
    local parts = {}
    for q = 1, MaxQueues() do
        local status, qMap = GetBattlefieldStatus(q)
        if qMap and status == "queued" then
            parts[#parts + 1] = qMap .. ": " .. (BATTLEFIELD_QUEUE_STATUS or "Queued")
        elseif qMap and status == "confirm" then
            parts[#parts + 1] = qMap .. ": " .. (BATTLEFIELD_CONFIRM_STATUS or "Ready")
        elseif qMap and status == "active" then
            parts[#parts + 1] = qMap .. ": in progress"
        end
    end
    return table.concat(parts, "  |  ")
end

local function BFRefresh()
    -- IsVisible: the cover is a shown child all session.
    local win = bf.win
    if not win or not win:IsVisible() then return end
    local data, name = BFRows()
    local sel = C_PvP and C_PvP.GetSelectedBattlefieldIndex and C_PvP.GetSelectedBattlefieldIndex()
    bf.list.selected = nil
    for _, e in ipairs(data) do
        if e.index == sel then bf.list.selected = e end
    end
    bf.list:SetData(data, true)

    win:SetTitle(name ~= "" and name or (BATTLEFIELDS or "Battlegrounds"))
    local _, text = BGInfo()
    bf.descTitle:SetText(name ~= "" and name or (BATTLEFIELDS or "Battlegrounds"))
    bf.descBody:SetText(text)

    local summary = QueueSummary()
    if summary ~= "" then
        bf.status:SetText(summary)
        bf.status:SetTextColor(Kit.TextRGB("green"))
    else
        bf.status:SetText("Pick an instance, then Join.")
        bf.status:_zPaint()
    end

    -- Join as group: shown when the battleground allows it, usable by the
    -- party leader - Blizzard's rule. The secure overlay can only be shown
    -- or hidden out of combat; in combat it stays as it was, and clicking
    -- it clicks Blizzard's (disabled) button, which does nothing.
    local canGroup = CanJoinBattlefieldAsGroup and CanJoinBattlefieldAsGroup() and true or false
    local leader = (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
        and UnitIsGroupLeader and UnitIsGroupLeader("player")
    if not InCombatLockdown() then
        bf.group:SetShown(canGroup)
        if bf.sGroup then bf.sGroup:SetShown(canGroup) end
    end
    bf.group:SetDisabled(not leader)
end

local BFQueue = Kit.Coalesce(BFRefresh, function() return bf.win end)

local function BFBuildRow(row)
    row:RegisterForClicks("LeftButtonUp")
    row.statusText = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.statusText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.statusText:SetWordWrap(false)
    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.nameText:SetPoint("RIGHT", row.statusText, "LEFT", -6, 0)
    row.nameText:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        local e = self.item
        if not e then return end
        -- The selection Blizzard's own Join button reads.
        if C_PvP and C_PvP.SetSelectedBattlefieldByIndex then
            C_PvP.SetSelectedBattlefieldByIndex(e.index)
        end
        BFQueue()
    end)
    row:SetScript("OnEnter", function(self)
        local e = self.item
        if e then Tip(self, e.title, e.tip) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BFUpdateRow(row, e)
    row.nameText:SetText(e.title)
    row.nameText:_zPaint()
    if e.status == "queued" then
        row.statusText:SetText(BATTLEFIELD_QUEUE_STATUS or "Queued")
        row.statusText:SetTextColor(Kit.TextRGB("green"))
    elseif e.status == "confirm" then
        row.statusText:SetText(BATTLEFIELD_CONFIRM_STATUS or "Ready")
        row.statusText:SetTextColor(Kit.TextRGB("orange"))
    else
        row.statusText:SetText("")
    end
end

local function BFPlace()
    local o = ZacUIDB and ZacUIDB.insets and ZacUIDB.insets.BattlefieldFrame
    AnchorPanel(bf.win, BattlefieldFrame, o or BF_INSET)
end

-- Built out of combat only: it creates secure buttons.
local function BFBuild()
    if bf.win then return bf.win end
    local blizzClose = _G.BattlefieldFrameCloseButton
    local win = Kit.Cover(BattlefieldFrame, {
        name = "ZacUIBattlefieldWindow",
        title = BATTLEFIELDS or "Battlegrounds",
        insetName = "BattlefieldFrame",
        -- Only reached if the secure X below could not be made.
        onClose = function()
            if blizzClose then blizzClose:Click() else HideUIPanel(BattlefieldFrame) end
        end,
    })
    bf.win = win
    win.Reanchor = BFPlace
    BFPlace()
    win:SetIcon(FactionIcon())

    win.footer = Kit.Footer(win, Kit.FOOTER_H)

    -- Footer: Cancel on the right, Join, then Join as group - Blizzard's
    -- order. Widths follow the localised labels.
    local function FooterButton(label)
        local b = UI.Button(win.footer, label, { height = 22 })
        b:SetWidth(math.max(64, math.ceil(b._zText:GetStringWidth()) + 20))
        return b
    end
    bf.cancel = FooterButton(CANCEL or "Cancel")
    bf.cancel:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    bf.join = FooterButton(BATTLEFIELD_JOIN or "Join Battle")
    bf.join:SetPoint("RIGHT", bf.cancel, "LEFT", -4, 0)
    bf.group = FooterButton(BATTLEFIELD_GROUP_JOIN or "Join as Group")
    bf.group:SetPoint("RIGHT", bf.join, "LEFT", -4, 0)

    bf.status = UI.Font(win, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    bf.status:SetPoint("BOTTOMLEFT", win.footer, "TOPLEFT", Kit.PAD - 1, Kit.GAP)
    bf.status:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)
    bf.status:SetWordWrap(false)

    -- The battleground's own description, as a card under the list.
    local card = UI.Box(win, "ui", "cardBg")
    card:SetHeight(150)
    card:SetPoint("BOTTOMLEFT", win.footer, "TOPLEFT", Kit.PAD - 1, Kit.GAP + 14 + Kit.GAP)
    card:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP + 14 + Kit.GAP)
    bf.descTitle = UI.Font(card, F.LABEL, { cat = "text", key = "gold", justify = "LEFT" })
    bf.descTitle:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -7)
    bf.descTitle:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -7)
    bf.descTitle:SetWordWrap(false)
    bf.descBody = UI.Font(card, F.SMALL, { justify = "LEFT" })
    bf.descBody:SetPoint("TOPLEFT", bf.descTitle, "BOTTOMLEFT", 0, -5)
    bf.descBody:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 7)
    bf.descBody:SetJustifyV("TOP")
    bf.descBody:SetWordWrap(true)

    bf.list = Kit.List(win, {
        rowHeight = BF_ROW_H,
        build = BFBuildRow,
        update = BFUpdateRow,
    })
    bf.list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, win.top)
    bf.list:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", 0, Kit.GAP)

    -- THE BUTTONS, SECURELY: each clicks Blizzard's own. See the header.
    if _G.BattlefieldFrameJoinButton then
        SecureDelegate(bf.join, _G.BattlefieldFrameJoinButton)
    end
    if _G.BattlefieldFrameGroupJoinButton then
        bf.sGroup = SecureDelegate(bf.group, _G.BattlefieldFrameGroupJoinButton, function(self)
            Tip(self, BATTLEFIELD_GROUP_JOIN or "Join as Group", NEWBIE_TOOLTIP_BATTLEFIELD_GROUP_JOIN)
        end)
    end
    if _G.BattlefieldFrameCancelButton then
        SecureDelegate(bf.cancel, _G.BattlefieldFrameCancelButton)
    end
    if blizzClose then
        SecureDelegate(win.closeButton, blizzClose)
    end

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
    ev:RegisterEvent("PARTY_LEADER_CHANGED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function()
        if win:IsVisible() then BFQueue() end
    end)
    -- Group size / who can queue: one notice per roster burst (core).
    ns.Roster.On("Win_PvP", function() BFQueue() end)
    win:HookScript("OnShow", BFQueue)
    return win
end

-- Outside the cover: the portrait and the close button poke past its
-- top-left / top-right corners, and the frame's own art (or the "pvp"
-- skin's panel, fitted to the full 384x512 rect) rings every edge.
local function BFLeftovers()
    local t = {}
    local function Add(f) if f then t[#t + 1] = f end end
    Add(_G.BattlefieldFrameCloseButton)
    Add(_G.BattlefieldFramePortrait)
    local f = BattlefieldFrame
    if f then
        Add(f._zui_panel ~= f and f._zui_panel or nil)
        AddRegions(t, f)
    end
    return t
end

local function BFApply()
    if not BattlefieldFrame then return end
    -- Secure children: building, showing and re-anchoring wait for peace.
    if InCombatLockdown() then return end
    if Enabled("battlefieldwin") then
        BFBuild()
        bf.win.Reanchor()
        bf.win:Show()
        Kit.Silence(BFLeftovers(), QUIET)
        if BattlefieldFrame:IsShown() then BFQueue() end
    elseif bf.win then
        bf.win:Hide()
        Kit.Unsilence(BFLeftovers(), QUIET)
    end
end

-- ============================================================
-- SCOREBOARD (WorldStateScoreFrame)
-- ============================================================
-- Blizzard sizes the board for the battleground's stat columns (530 plus
-- 77 per column), so the cover is anchored at both corners and grows with
-- it. The rectangle is Blizzard's art (from x 8, y 16; the right ~100px and
-- bottom ~40px are the art's transparent margin and the bottom tabs), and
-- every Blizzard piece in the frame is silenced, so nothing shows round it.
local SW_INSET = { l = 8, r = 100, t = 12, b = 40 }
local SW_ROW_H = 18
local SORT_H = 26      -- two lines: "Killing Blows", "Honorable Kills"
local BANNER_H = 22

local sw = {}   -- win, list, header, nameHead, heads, tabs, search, banner, winText, timerText, count, run, leave
local faction = "all"
local query = ""
local sortKey, sortDesc = nil, false
local cols = {}
local colSig = ""
local ticker

local function CanSeeDamage()
    if not WorldStateScoreFrame_CanSeeDamageAndHealing then return false end
    local ok, res = pcall(WorldStateScoreFrame_CanSeeDamageAndHealing)
    return ok and res and true or false
end

-- Blizzard's column order: name, KB, deaths, HK, (damage, healing), the
-- battleground's own stats, honour.
local function BuildColumns()
    local c = {}
    c[#c + 1] = { key = "kb", label = SCORE_KILLING_BLOWS or "Killing Blows",
                  tip = KILLING_BLOW_TOOLTIP, w = 50 }
    c[#c + 1] = { key = "deaths", label = DEATHS or "Deaths", tip = DEATHS_TOOLTIP, w = 50 }
    c[#c + 1] = { key = "hk", label = SCORE_HONORABLE_KILLS or "Honorable Kills",
                  tip = HONORABLE_KILLS_TOOLTIP, w = 50 }
    if CanSeeDamage() then
        c[#c + 1] = { key = "damage", label = SCORE_DAMAGE_DONE or "Damage",
                      tip = DAMAGE_DONE_TOOLTIP, w = 62 }
        c[#c + 1] = { key = "healing", label = SCORE_HEALING_DONE or "Healing",
                      tip = HEALING_DONE_TOOLTIP, w = 62 }
    end
    local n = GetNumBattlefieldStats and GetNumBattlefieldStats() or 0
    for i = 1, math.min(n, 7) do
        local text, icon, tip = GetBattlefieldStatInfo(i)
        c[#c + 1] = { key = "stat" .. i, stat = i, label = text or "", tip = tip,
                      icon = (icon and icon ~= "") and icon or nil, w = 62 }
    end
    c[#c + 1] = { key = "honor", label = SCORE_HONOR_GAINED or "Honor",
                  tip = HONOR_GAINED_TOOLTIP, w = 54 }
    local parts = {}
    for _, col in ipairs(c) do parts[#parts + 1] = col.key .. "=" .. col.label end
    return c, table.concat(parts, ";")
end

-- Right-edge offset of every column, shared by the header and the rows
-- so the two can never drift apart.
local function ColumnOffsets()
    local off, x = {}, 4
    for i = #cols, 1, -1 do
        off[i] = x
        x = x + cols[i].w
    end
    return off
end

local function ScoreRows()
    local n = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
    local nStats = 0
    for _, col in ipairs(cols) do if col.stat then nStats = math.max(nStats, col.stat) end end
    local me = UnitName("player")
    local data, own = {}, nil
    local counts = { all = 0, alliance = 0, horde = 0 }
    for i = 1, n do
        local name, kb, hk, deaths, honor, fac, rank, race, class, classToken, dmg, heal =
            GetBattlefieldScore(i)
        if name then
            local e = {
                index = i, name = name, kb = kb or 0, hk = hk or 0, deaths = deaths or 0,
                honor = math.floor(honor or 0), faction = fac, rank = rank,
                race = race or "", class = class or "", classToken = classToken,
                damage = dmg or 0, healing = heal or 0,
            }
            for j = 1, nStats do
                e["stat" .. j] = (GetBattlefieldStatData and GetBattlefieldStatData(i, j)) or 0
            end
            counts.all = counts.all + 1
            if fac == 1 then counts.alliance = counts.alliance + 1
            elseif fac == 0 then counts.horde = counts.horde + 1 end
            local keep = (faction == "all")
                or (faction == "alliance" and fac == 1)
                or (faction == "horde" and fac == 0)
            if keep and Kit.Matches(query, name, e.class, e.race) then
                data[#data + 1] = e
                if name == me then own = e end
            end
        end
    end
    if sortKey then
        local key, desc = sortKey, sortDesc
        table.sort(data, function(a, b)
            local va, vb = a[key], b[key]
            if key == "name" then va, vb = string.lower(va or ""), string.lower(vb or "") end
            if va ~= vb then
                if desc then return va > vb end
                return va < vb
            end
            return a.index < b.index
        end)
    end
    return data, counts, own
end

-- ---------- header ----------
local SWRefresh

local function PaintHeader()
    local function PaintOne(b)
        local on = (b._zKey ~= nil and b._zKey == sortKey)
        b:SetActive(on)
        b.arrow:SetShown(on)
        if on then b.arrow:SetRotation(sortDesc and 0 or math.pi) end
        local a = GetColor("text", "green")
        b.arrow:SetVertexColor(a.r, a.g, a.b, 1)
    end
    PaintOne(sw.nameHead)
    for _, b in ipairs(sw.heads) do if b:IsShown() then PaintOne(b) end end
end

-- First click: names A-Z, numbers highest first. Second click reverses,
-- a third goes back to Blizzard's order.
local function ClickSort(key, numeric)
    if sortKey == key then
        if sortDesc == numeric then
            sortDesc = not sortDesc
        else
            sortKey, sortDesc = nil, false
        end
    else
        sortKey, sortDesc = key, numeric
    end
    PaintHeader()
    SWRefresh()
end

local function HeadButton(parent)
    local b = UI.Button(parent, "", { height = SORT_H, size = F.SMALL })
    b._zText:ClearAllPoints()
    b._zText:SetPoint("LEFT", b, "LEFT", 3, 0)
    b._zText:SetPoint("RIGHT", b, "RIGHT", -10, 0)
    b._zText:SetJustifyH("CENTER")
    -- Two lines at most; anything longer truncates (the tooltip has it).
    b._zText:SetWordWrap(true)
    if b._zText.SetMaxLines then b._zText:SetMaxLines(2) end
    local ar = b:CreateTexture(nil, "OVERLAY")
    ar._zui_own = true
    ar:SetTexture(TEX_ARROW or FLAT)
    ar:SetSize(8, 8)
    ar:SetPoint("RIGHT", b, "RIGHT", -2, 0)
    ar:Hide()
    b.arrow = ar
    b:SetScript("OnClick", function(self)
        if self._zKey then ClickSort(self._zKey, self._zKey ~= "name") end
    end)
    b:HookScript("OnEnter", function(self)
        Tip(self, self._zTitle, (self._zTip and (self._zTip .. "\n\n") or "")
            .. "Click to sort, again to reverse, a third time for Blizzard's order.")
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function LayoutHeader()
    local off = ColumnOffsets()
    for i, col in ipairs(cols) do
        local b = sw.heads[i]
        if not b then
            b = HeadButton(sw.header)
            sw.heads[i] = b
        end
        b:ClearAllPoints()
        b:SetWidth(col.w - 2)
        b:SetPoint("RIGHT", sw.header, "RIGHT", -(off[i] + 1), 0)
        b:SetLabel(col.label)
        b._zKey, b._zTitle, b._zTip = col.key, col.label, col.tip
        b:Show()
    end
    for i = #cols + 1, #sw.heads do sw.heads[i]:Hide() end
    sw.nameHead:ClearAllPoints()
    sw.nameHead:SetPoint("LEFT", sw.header, "LEFT", 0, 0)
    if sw.heads[1] and #cols > 0 then
        sw.nameHead:SetPoint("RIGHT", sw.heads[1], "LEFT", -3, 0)
    else
        sw.nameHead:SetPoint("RIGHT", sw.header, "RIGHT", 0, 0)
    end
    PaintHeader()
end

-- ---------- rows ----------
local function LayoutRow(row)
    local off = ColumnOffsets()
    for i, col in ipairs(cols) do
        local c = row.cells[i]
        if not c then
            c = UI.Font(row, F.SMALL, { justify = "CENTER" })
            c:SetWordWrap(false)
            row.cells[i] = c
        end
        c:ClearAllPoints()
        c:SetWidth(col.w - 2)
        c:SetPoint("RIGHT", row, "RIGHT", -(off[i] + 1), 0)
        c:Show()
    end
    for i = #cols + 1, #row.cells do row.cells[i]:Hide() end
    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("LEFT", row.rank, "RIGHT", 4, 0)
    if row.cells[1] and #cols > 0 then
        row.nameText:SetPoint("RIGHT", row.cells[1], "LEFT", -4, 0)
    else
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    end
    row._zSig = colSig
end

local function RowTooltip(row)
    local e = row.item
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name, ClassRGB(e.classToken))
    local c = GetColor("tooltip", "body")
    local line = strtrim((e.race or "") .. " " .. (e.class or ""))
    if line ~= "" then GameTooltip:AddLine(line, c.r, c.g, c.b) end
    if e.rankName and e.rankName ~= "" then
        GameTooltip:AddLine(e.rankName, c.r, c.g, c.b)
    end
    GameTooltip:Show()
end

local function SWBuildRow(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.cells = {}
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar._zui_own = true
    bar:SetTexture(FLAT)
    bar:SetWidth(3)
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.factionBar = bar
    local rank = row:CreateTexture(nil, "ARTWORK")
    rank._zui_own = true
    rank:SetSize(14, 14)
    rank:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.rank = rank
    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetWordWrap(false)
    LayoutRow(row)

    -- Blizzard's name-button clicks: right-click opens the scoreboard's
    -- player menu (not on yourself), shift-click puts the name in chat.
    row:SetScript("OnClick", function(self, button)
        local e = self.item
        if not e then return end
        if button == "RightButton" then
            if not UnitIsUnit(e.name, "player") and UnitPopup_OpenMenu then
                UnitPopup_OpenMenu("WORLD_STATE_SCORE", {
                    name = e.name,
                    battlefieldScoreIndex = e.index,
                })
            end
        elseif IsModifiedClick("CHATLINK") then
            local CFU = ChatFrameUtil
            if CFU and CFU.InsertLink then
                if not CFU.GetActiveWindow or CFU.GetActiveWindow() then CFU.InsertLink(e.name) end
            elseif ChatEdit_InsertLink then
                ChatEdit_InsertLink(e.name)
            end
        end
    end)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.UpdateTooltip = RowTooltip
end

local function SWUpdateRow(row, e)
    if row._zSig ~= colSig then LayoutRow(row) end
    row.factionBar:SetVertexColor(FactionRGB(e.faction))
    row.factionBar:SetShown(e.faction ~= nil)

    local rankName, rankNumber
    if GetPVPRankInfo and e.rank then rankName, rankNumber = GetPVPRankInfo(e.rank, e.faction) end
    e.rankName = rankName
    if rankNumber and rankNumber > 0 then
        row.rank:SetTexture(string.format("%s%02d", "Interface\\PvPRankBadges\\PvPRank", rankNumber))
        row.rank:Show()
    else
        row.rank:Hide()
    end

    row.nameText:SetText(e.name)
    row.nameText:SetTextColor(ClassRGB(e.classToken))

    for i, col in ipairs(cols) do
        local c = row.cells[i]
        local v = e[col.key] or 0
        if col.icon then
            -- Blizzard's flag columns: the faction's icon and a count, or
            -- nothing at all for zero.
            if v > 0 then
                c:SetText("|T" .. col.icon .. tostring(e.faction or 0) .. ":12:12|t " .. v)
            else
                c:SetText("")
            end
        else
            c:SetText(v)
        end
        c:_zPaint()
    end
end

-- ---------- layout ----------
-- The winner strip pushes the toolbar down while it is up.
local function LayoutTop(hasWinner)
    local win = sw.win
    local y = win.top
    sw.banner:ClearAllPoints()
    if hasWinner then
        sw.banner:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
        sw.banner:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y)
        sw.banner:Show()
        y = y - BANNER_H - Kit.GAP
    else
        sw.banner:Hide()
    end
    if sw._zTopY == y then return end
    sw._zTopY = y
    sw.tabs:ClearAllPoints()
    sw.tabs:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
    sw.search:ClearAllPoints()
    sw.search:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y)
    -- The tabs and the search box share this row; the taller of the two
    -- decides where the header goes.
    local hy = y - math.max(Kit.TAB_H, Kit.SEARCH_H) - Kit.GAP
    sw.header:ClearAllPoints()
    sw.header:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, hy)
    sw.header:SetPoint("TOPRIGHT", win, "TOPRIGHT", -(Kit.PAD + M.SCROLL_W + 2), hy)
    sw.list:ClearAllPoints()
    sw.list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, hy - SORT_H - 3)
    sw.list:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)
end

-- ---------- time to port ----------
local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function UpdateTimer()
    if not sw.win or not sw.win:IsVisible() or not GetBattlefieldWinner() then
        StopTicker()
        return
    end
    -- Blizzard's own countdown, kept by its PvP helper.
    local t = BATTLEFIELD_SHUTDOWN_TIMER or 0
    local text = ""
    if t > 0 and SecondsToTimeAbbrev then
        -- Blizzard's call, threshold 1.0 included (returns format, value).
        local ok, s = pcall(string.format, SecondsToTimeAbbrev(t, 1.0))
        if ok and s then text = (TIME_TO_PORT or "Time to port:") .. " " .. s end
    end
    sw.timerText:SetText(text)
end

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, UpdateTimer)
end

-- ---------- refresh ----------
function SWRefresh(keepOffset)
    local win = sw.win
    if not win or not win:IsVisible() then return end

    local c, sig = BuildColumns()
    if sig ~= colSig then
        cols, colSig = c, sig
        -- A column that is gone cannot stay the sort key.
        if sortKey and sortKey ~= "name" then
            local found = false
            for _, col in ipairs(cols) do if col.key == sortKey then found = true end end
            if not found then sortKey, sortDesc = nil, false end
        end
        LayoutHeader()
    end

    local winner = GetBattlefieldWinner()
    LayoutTop(winner ~= nil)
    if winner ~= nil then
        sw.winText:SetText(_G["VICTORY_TEXT" .. winner] or "")
        sw.winText:SetTextColor(FactionRGB(winner))
        sw.leave:Show()
        UpdateTimer()
        StartTicker()
    else
        sw.leave:Hide()
        sw.timerText:SetText("")
        StopTicker()
    end

    local data, counts, own = ScoreRows()
    sw.list.selected = own
    sw.list:SetEmptyText(counts.all == 0 and "Waiting for the scores..." or "Nothing matches.")
    sw.list:SetData(data, keepOffset)

    sw.tabs:SetLabel("all", (ALL or "All") .. " (" .. counts.all .. ")")
    sw.tabs:SetLabel("alliance", (FACTION_ALLIANCE or "Alliance") .. " (" .. counts.alliance .. ")")
    sw.tabs:SetLabel("horde", (FACTION_HORDE or "Horde") .. " (" .. counts.horde .. ")")

    -- Player counts and running time, Blizzard's strings.
    local nHorde, nAlliance = 0, 0
    if GetBattlefieldTeamInfo then
        nHorde = select(5, GetBattlefieldTeamInfo(0)) or 0
        nAlliance = select(5, GetBattlefieldTeamInfo(1)) or 0
    end
    local fa = PLAYER_COUNT_ALLIANCE or "Alliance: %d"
    local fh = PLAYER_COUNT_HORDE or "Horde: %d"
    if nHorde > 0 and nAlliance > 0 then
        sw.count:SetText(string.format(fa, nAlliance) .. " / " .. string.format(fh, nHorde))
    elseif nAlliance > 0 then
        sw.count:SetText(string.format(fa, nAlliance))
    elseif nHorde > 0 then
        sw.count:SetText(string.format(fh, nHorde))
    else
        sw.count:SetText("")
    end
    local run = GetBattlefieldInstanceRunTime and GetBattlefieldInstanceRunTime() or 0
    if run > 60000 and SecondsToTime then
        sw.run:SetText((TIME_ELAPSED or "Time elapsed:") .. " " .. SecondsToTime(run / 1000, true))
    else
        sw.run:SetText("")
    end
    win:SetTitle((GetRealZoneText and GetRealZoneText()) or (BATTLEFIELDS or "Battleground"))
end

local SWQueue = Kit.Coalesce(function() SWRefresh(true) end, function() return sw.win end)

local function SWPlace()
    local o = ZacUIDB and ZacUIDB.insets and ZacUIDB.insets.WorldStateScoreFrame
    AnchorPanel(sw.win, WorldStateScoreFrame, o or SW_INSET)
end

local function SWBuild()
    if sw.win then return sw.win end
    local win = Kit.Cover(WorldStateScoreFrame, {
        name = "ZacUIScoreWindow",
        title = BATTLEFIELDS or "Battleground",
        insetName = "WorldStateScoreFrame",
        -- Blizzard's close button: its onCloseCallback plays the sound and
        -- hides the panel through Blizzard's own path.
        onClose = function()
            local c = _G.WorldStateScoreFrameCloseButton
            if c then c:Click() else HideUIPanel(WorldStateScoreFrame) end
        end,
    })
    sw.win = win
    win.Reanchor = SWPlace
    SWPlace()
    win:SetIcon(FactionIcon())

    -- Winner strip: the victory line in the winner's colour, and
    -- Blizzard's time-to-port countdown on the right.
    local banner = UI.Box(win, "ui", "cardBg")
    banner:SetHeight(BANNER_H)
    sw.banner = banner
    sw.timerText = UI.Font(banner, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    sw.timerText:SetPoint("RIGHT", banner, "RIGHT", -8, 0)
    sw.timerText:SetWordWrap(false)
    sw.winText = UI.Font(banner, F.LABEL, { justify = "LEFT" })
    sw.winText:SetPoint("LEFT", banner, "LEFT", 8, 0)
    sw.winText:SetPoint("RIGHT", sw.timerText, "LEFT", -8, 0)
    sw.winText:SetWordWrap(false)
    banner:Hide()

    sw.tabs = Kit.Tabs(win, {
        { key = "all",      label = ALL or "All" },
        { key = "alliance", label = FACTION_ALLIANCE or "Alliance" },
        { key = "horde",    label = FACTION_HORDE or "Horde" },
    }, function(key)
        faction = key
        SWRefresh(false)
    end, { minWidth = 50 })
    sw.tabs:Paint("all")

    sw.search = Kit.Search(win, 150, function(text)
        query = Kit.NormalizeQuery(text)
        SWRefresh(false)
    end, "Search players")

    sw.header = CreateFrame("Frame", nil, win)
    sw.header:SetHeight(SORT_H)
    sw.heads = {}
    sw.nameHead = HeadButton(sw.header)
    sw.nameHead:SetLabel(NAME or "Name")
    sw.nameHead._zText:SetJustifyH("LEFT")
    sw.nameHead._zKey, sw.nameHead._zTitle = "name", NAME or "Name"

    win.footer = Kit.Footer(win, Kit.FOOTER_H)
    sw.leave = UI.Button(win.footer, LEAVE_BATTLEGROUND or "Leave Battleground", { height = 22 })
    sw.leave:SetWidth(math.max(120, math.ceil(sw.leave._zText:GetStringWidth()) + 20))
    sw.leave:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    -- Blizzard's own Leave button: the LFD branch, the sound, and the
    -- "are you sure" popup if the match is somehow not over.
    sw.leave:SetScript("OnClick", function()
        local b = _G.WorldStateScoreFrameLeaveButton
        if b then b:Click() elseif ConfirmOrLeaveBattlefield then ConfirmOrLeaveBattlefield() end
    end)
    sw.leave:Hide()
    sw.count = UI.Font(win.footer, F.SMALL, { justify = "LEFT" })
    sw.count:SetPoint("TOPLEFT", win.footer, "TOPLEFT", 8, -5)
    sw.count:SetPoint("TOPRIGHT", win.footer, "TOPRIGHT", -170, -5)
    sw.count:SetWordWrap(false)
    sw.count:SetJustifyV("TOP")
    sw.run = UI.Font(win.footer, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    sw.run:SetPoint("BOTTOMLEFT", win.footer, "BOTTOMLEFT", 8, 5)
    sw.run:SetPoint("BOTTOMRIGHT", win.footer, "BOTTOMRIGHT", -170, 5)
    sw.run:SetWordWrap(false)
    sw.run:SetJustifyV("BOTTOM")

    sw.list = Kit.List(win, {
        rowHeight = SW_ROW_H,
        build = SWBuildRow,
        update = SWUpdateRow,
    })
    LayoutTop(false)
    cols, colSig = BuildColumns()
    LayoutHeader()

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
    ev:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function()
        if win:IsVisible() then SWQueue() end
    end)

    -- Blizzard's OnShow puts its board back on "All"; so does ours.
    win:HookScript("OnShow", function()
        faction, query = "all", ""
        sw.search:SetText("")
        sw.tabs:Paint("all")
        sw.list.offset = 0
        SWQueue()
    end)
    win:HookScript("OnHide", StopTicker)
    return win
end

-- Everything of Blizzard's in the board: its art and labels, the tabs
-- that hang below it, the close button, the leave button, the header
-- buttons, the rows, the scroll bar - and the "pvp" skin's panel, which is
-- fitted to the full frame rect. All faded; the cover draws the board.
local function SWLeftovers()
    local t = {}
    local f = WorldStateScoreFrame
    if not f then return t end
    AddRegions(t, f)
    for _, child in ipairs({ f:GetChildren() }) do
        if child ~= sw.win then t[#t + 1] = child end
    end
    return t
end

local function SWApply()
    if not WorldStateScoreFrame then return end
    if Enabled("scorewin") then
        SWBuild()
        sw.win.Reanchor()
        sw.win:Show()
        Kit.Silence(SWLeftovers(), QUIET)
        if WorldStateScoreFrame:IsShown() then SWQueue() end
    elseif sw.win then
        sw.win:Hide()
        Kit.Unsilence(SWLeftovers(), QUIET)
    end
end

-- ============================================================
-- MODULES
-- ============================================================
-- Combat-sensitive: builds secure buttons inside BattlefieldFrame.
Modules.battlefieldwin = function()
    if not BattlefieldFrame or ns._zBattlefieldWin then return end
    ns._zBattlefieldWin = true
    BFApply()
    -- A later /zui toggle only flips the saved flag; the window checks it
    -- on every open (out of combat) so turning it off never needs a reload.
    BattlefieldFrame:HookScript("OnShow", function()
        if not InCombatLockdown() then BFApply() end
        BFQueue()
    end)
    -- Blizzard re-runs its update after picking "First Available" on
    -- BATTLEFIELDS_SHOW and on every scroll / leader change.
    if type(BattlefieldFrame_Update) == "function" then
        hooksecurefunc("BattlefieldFrame_Update", BFQueue)
    end
end

Modules.scorewin = function()
    if not WorldStateScoreFrame or ns._zScoreWin then return end
    ns._zScoreWin = true
    SWApply()
    WorldStateScoreFrame:HookScript("OnShow", function()
        SWApply()
        if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
        SWQueue()
    end)
end
