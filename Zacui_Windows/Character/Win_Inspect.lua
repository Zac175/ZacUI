-- Win_Inspect - ZacUI's inspect window: the inspected player's gear in
-- two named columns and a weapon row, their 3D model between them, the
-- average item level, and their honor page.
-- Part of ZacUI; load order is set by the TOC.
--
-- A WIN_KIT COVER, WIDER THAN THE PANEL. The window is parented to
-- InspectFrame (load-on-demand, Blizzard_InspectUI) and keeps its
-- top-left corner, so right-click > Inspect, the inspect key and Escape
-- open and close it through Blizzard's own code. The extra width holds
-- each item's name and level beside its slot.
--
-- NOTHING HERE IS SECURE. Blizzard's inspect slots are plain buttons: a
-- click only links or previews (HandleModifiedItemClick) and hovering
-- shows the tooltip. So ours are plain buttons too, InspectFrame stays
-- an unprotected frame, and the window can be built and redrawn in
-- combat. The one thing an addon cannot do in combat is close a UI panel
-- (HideUIPanel refuses tainted callers then), so the X says so and
-- Escape - Blizzard's own path - closes it.
--
-- THE INSPECT LIFECYCLE IS BLIZZARD'S. InspectFrame_Show calls
-- NotifyInspect and shows the frame when INSPECT_READY arrives; target
-- and roster changes hide it; its OnHide calls ClearInspectPlayer. We
-- only draw: on show, on INSPECT_READY / UNIT_INVENTORY_CHANGED for the
-- inspected unit, and we wipe everything on hide so the next inspect
-- never flashes the last player's gear.
--
-- NO TALENTS TAB. Era's inspect window has only Character and Honor
-- (INSPECTFRAME_SUBFRAMES in Vanilla/Blizzard_InspectUI.lua - the talent
-- page loads for TBC and later only), and the 1.x server does not send
-- another player's talents with an inspect, so there is nothing to draw.
--
--   Hover a slot        the item's tooltip
--   Shift / Ctrl-click  link it / preview it (HandleModifiedItemClick)
--   Model               drag to rotate, wheel to zoom
--   Honor tab           rank, rank progress, and the period table

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

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local format = string.format

-- ============================================================
-- GEOMETRY
-- ============================================================
-- Two columns of eight gear cells around the model, the three weapons in
-- a row underneath, all inside a window wider and taller than
-- InspectFrame (338 x 424) so every Blizzard piece sits under it.
local SLOT      = 36
local ROW_GAP   = 4
local TEXT_W    = 128                     -- item name / level beside a slot
local CELL_W    = SLOT + 6 + TEXT_W
local MODEL_W   = 200
local COL_GAP   = 8
local INFO_H    = 18
local ROWS      = 8
local COLUMN_H  = ROWS * SLOT + (ROWS - 1) * ROW_GAP
local WEAPON_GAP = 8
local PAGE_H    = COLUMN_H + WEAPON_GAP + SLOT

local WIN_W = Kit.PAD * 2 + CELL_W * 2 + COL_GAP * 2 + MODEL_W
local TABS_Y = -(M.TITLEBAR + 2 + INFO_H + 4)            -- tab strip top
local PAGE_Y = TABS_Y - Kit.TAB_H - Kit.GAP              -- page top
local WIN_H = -PAGE_Y + PAGE_H + Kit.GAP + Kit.FOOTER_H + 2

local LEFT_SLOTS  = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot",
                      "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot" }
local RIGHT_SLOTS = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
                      "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local WEAPON_SLOTS = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }

-- Shirt and tabard carry no item level worth a number.
local NO_ILVL = { [4] = true, [19] = true }
-- The average: every gear slot but shirt and tabard (17 on Era), the
-- same rule as Win_Paperdoll so the two numbers compare.
local AVG_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local MAINHAND, OFFHAND = 16, 17

-- InspectPaperDollFrame_OnShow's out-of-range fallback art.
local FACTION_LOGO = {
    Alliance = "Interface\\Timer\\Alliance-Logo",
    Horde    = "Interface\\Timer\\Horde-Logo",
}

local win, pages, tabs, infoLevel, infoGuild
local model, logo, ilvlText, statusText
local cells = {}
local honor = {}
local itemPending, honorPending = false, false
local hooked = false
local Leftovers, Apply, Mark   -- defined below; earlier code calls them

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.inspectwin ~= false
end

-- The unit Blizzard is inspecting ("target", "party2", ...), or nil
-- while nothing is (InspectFrame_OnHide clears it).
local function Unit()
    local u = InspectFrame and InspectFrame.unit
    if u and UnitExists(u) then return u end
    return nil
end

-- ============================================================
-- SMALL HELPERS
-- ============================================================
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function SafeFormat(fmt, ...)
    if type(fmt) ~= "string" then return nil end
    local ok, s = pcall(format, fmt, ...)
    if ok then return s end
    return nil
end

local function SetTextKey(fs, key)
    fs._zPaintKey = key
    fs:_zPaint()
end

local function ItemLevel(link)
    if not link then return nil end
    local detailed = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if detailed then
        local ok, lvl = pcall(detailed, link)
        if ok and type(lvl) == "number" and lvl > 0 then return lvl end
    end
    local lvl = select(4, GetInfo(link))
    if type(lvl) == "number" and lvl > 0 then return lvl end
    return nil
end

local function SlotQuality(unit, id, link)
    if GetInventoryItemQuality then
        local q = GetInventoryItemQuality(unit, id)
        if q then return q end
    end
    return link and select(3, GetInfo(link)) or nil
end

-- "Plate", "Two-Handed Swords" ... and for rings, necks, trinkets and
-- cloaks (armour subclass "Miscellaneous" / "Cloth") the slot word
-- instead, which says more.
local function ItemKind(link)
    local _, _, _, _, _, _, subType, _, equipLoc, _, _, classID, subclassID = GetInfo(link)
    if not subType and not equipLoc then return nil end
    if classID == 4 and (subclassID == 0 or equipLoc == "INVTYPE_CLOAK") then
        local slotWord = equipLoc and _G[equipLoc]
        if type(slotWord) == "string" and slotWord ~= "" then return slotWord end
    end
    return subType
end

local ClassText = Kit.ClassText

-- ============================================================
-- GEAR CELLS
-- ============================================================
-- A cell is one Button over the slot icon and its two text lines, so the
-- whole strip is the hover / click target. side = "left" puts the icon
-- on the left and the text after it; "right" mirrors it.
local function CellEnter(self)
    local unit = Unit()
    self.hover:Show()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- InspectPaperDollItemSlotButton_OnEnter: the item, else the slot's
    -- name (the relic name on a relic class).
    if not unit or not GameTooltip:SetInventoryItem(unit, self.slotId) then
        local text = _G[string.upper(self.slotName)]
        if self.checkRelic and unit and UnitHasRelicSlot and UnitHasRelicSlot(unit) then
            text = RELICSLOT
        end
        GameTooltip:SetText(text or self.slotName)
    end
    CursorUpdate(self)
end

local function CellLeave(self)
    self.hover:Hide()
    GameTooltip:Hide()
    ResetCursor()
end

-- InspectPaperDollItemSlotButton_OnClick: every click goes to
-- HandleModifiedItemClick, which links / previews on the modifier and
-- does nothing without one.
local function CellClick(self)
    local unit = Unit()
    if not unit then return end
    local link = GetInventoryItemLink(unit, self.slotId)
    if link then HandleModifiedItemClick(link) end
end

local function BuildCell(parent, slotName, side, width)
    local id, emptyTex, checkRelic = GetInventorySlotInfo(slotName)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or CELL_W, SLOT)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.slotId, b.slotName, b.emptyTex, b.checkRelic = id, slotName, emptyTex, checkRelic

    local icon = Kit.Icon(b, SLOT)
    b.icon = icon

    local hover = icon:CreateTexture(nil, "ARTWORK", nil, 6)
    hover._zui_own = true
    hover:SetPoint("TOPLEFT", 1, -1)
    hover:SetPoint("BOTTOMRIGHT", -1, 1)
    hover:SetColorTexture(1, 1, 1, 0.10)
    hover:SetBlendMode("ADD")
    hover:Hide()
    b.hover = hover

    -- Name on the top edge, level + kind on the bottom edge: two anchors
    -- per line on the same edge, so the lines can never meet.
    b.name = UI.Font(b, F.SMALL)
    b.name:SetWordWrap(false)
    b.name:SetJustifyV("TOP")
    b.sub = UI.Font(b, F.SMALL, { cat = "text", key = "gray" })
    b.sub:SetWordWrap(false)
    b.sub:SetJustifyV("BOTTOM")
    if side == "right" then
        icon:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
        b.name:SetJustifyH("RIGHT")
        b.name:SetPoint("TOPRIGHT", icon, "TOPLEFT", -6, -4)
        b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -4)
        b.sub:SetJustifyH("RIGHT")
        b.sub:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", -6, 4)
        b.sub:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 4)
    else
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b.name:SetJustifyH("LEFT")
        b.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -4)
        b.name:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -4)
        b.sub:SetJustifyH("LEFT")
        b.sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 4)
        b.sub:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 4)
    end

    b:SetScript("OnEnter", CellEnter)
    b:SetScript("OnLeave", CellLeave)
    -- GameTooltip re-runs this while it is owned, so pressing Ctrl over
    -- a slot turns the dress-up cursor on (Blizzard's OnUpdate does it).
    b.UpdateTooltip = CellEnter
    b:SetScript("OnClick", CellClick)
    cells[#cells + 1] = b
    return b
end

local function EmptyCell(b, unit)
    b.hasItem = nil
    local tex = b.emptyTex
    if b.checkRelic and unit and UnitHasRelicSlot and UnitHasRelicSlot(unit) then
        tex = "Interface\\Paperdoll\\UI-PaperDoll-Slot-Relic.blp"
    end
    b.icon:SetIcon(tex)
    b.icon:SetCount(0)
    b.icon:SetQuality(nil)
    b.icon:SetDesaturated(false)
    b.name:SetText(_G[string.upper(b.slotName)] or "")
    SetTextKey(b.name, "disabled")
    b.sub:SetText("")
end

-- InspectPaperDollItemSlotButton_Update, drawn our way: the item or the
-- slot's empty art, plus its name in quality colour, item level and kind.
local function UpdateCell(b, unit)
    local tex = unit and GetInventoryItemTexture(unit, b.slotId)
    if not tex then
        EmptyCell(b, unit)
    else
        local link = GetInventoryItemLink(unit, b.slotId)
        b.hasItem = 1
        b.icon:SetIcon(tex)
        b.icon:SetCount(GetInventoryItemCount(unit, b.slotId))
        b.icon:SetDesaturated(false)
        local q = SlotQuality(unit, b.slotId, link)
        b.icon:SetQuality(q)
        -- The link carries the name even before the item cache has it.
        local name = (link and GetInfo(link)) or (link and link:match("%[(.-)%]"))
        if not name then itemPending = true end
        b.name:SetText(name or "")
        if q then b.name:SetTextColor(ns.QualityRGB(q)) else SetTextKey(b.name, "normal") end
        local parts = {}
        if link and not NO_ILVL[b.slotId] then
            local lvl = ItemLevel(link)
            if lvl then parts[#parts + 1] = "ilvl " .. lvl else itemPending = true end
        end
        local kind = link and ItemKind(link)
        if kind and kind ~= "" then parts[#parts + 1] = kind end
        b.sub:SetText(table.concat(parts, "  "))
    end
    if GameTooltip:IsOwned(b) then CellEnter(b) end
end

local function UpdateCells()
    local unit = Unit()
    itemPending = false
    for _, b in ipairs(cells) do UpdateCell(b, unit) end
end

-- ============================================================
-- MODEL
-- ============================================================
-- Rotation by dragging, like Model_OnUpdate, but the OnUpdate only lives
-- while the button is held (Win_Paperdoll's model, minus the equip-on-
-- drop: an inspected model takes nothing).
local ROTATE = MODELFRAME_DRAG_ROTATION_CONSTANT or 0.010
local TWO_PI = 2 * math.pi
local DEFAULT_ROTATION = MODELFRAME_DEFAULT_ROTATION or 0.61

local function DragUpdate(self)
    local x = GetCursorPosition()
    local diff = (x - (self.dragX or x)) * ROTATE
    self.dragX = x
    self.rotation = self.rotation + diff
    if self.rotation < 0 then self.rotation = self.rotation + TWO_PI end
    if self.rotation > TWO_PI then self.rotation = self.rotation - TWO_PI end
    self:SetRotation(self.rotation)
end

local function StopDrag(self)
    self:SetScript("OnUpdate", nil)
    self.dragX = nil
end

local function BuildModel(parent)
    local m = CreateFrame("PlayerModel", nil, parent)
    m:SetPoint("TOPLEFT", 1, -1)
    m:SetPoint("BOTTOMRIGHT", -1, 1)
    m.rotation = DEFAULT_ROTATION
    m.zoom = 0
    m.maxZoom = MODELFRAME_MAX_PLAYER_ZOOM or 0.8
    m:EnableMouse(true)
    m:EnableMouseWheel(true)
    m:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self.dragX = GetCursorPosition()
            self:SetScript("OnUpdate", DragUpdate)
        end
    end)
    m:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then StopDrag(self) end
    end)
    m:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = max(0, min(self.maxZoom, self.zoom + delta * (MODELFRAME_ZOOM_STEP or 0.15)))
        if self.SetPortraitZoom then self:SetPortraitZoom(self.zoom) end
    end)
    -- WoW Forever: the modern client loads the model after SetUnit and
    -- resets the camera then; the framing goes back on once it is in
    if _G.ZACUI_MODERN and m.HasScript and m:HasScript("OnModelLoaded") then
        m:SetScript("OnModelLoaded", function(self)
            self:SetRotation(self.rotation)
            if self.SetPortraitZoom then self:SetPortraitZoom(self.zoom) end
        end)
    end
    m:SetScript("OnHide", StopDrag)
    m:RegisterEvent("UI_SCALE_CHANGED")
    m:RegisterEvent("DISPLAY_SIZE_CHANGED")
    m:SetScript("OnEvent", function(self)
        if self.RefreshCamera then self:RefreshCamera() end
    end)
    return m
end

-- InspectPaperDollFrame_OnShow: SetUnit reports whether the model can be
-- drawn (not out of range); when it cannot, the faction crest instead.
local function UpdateModel()
    local unit = Unit()
    if not unit then
        if model.ClearModel then model:ClearModel() end
        logo:Hide()
        return
    end
    model:Show()
    local canDraw = model:SetUnit(unit)
    model:SetRotation(model.rotation)
    if model.SetPortraitZoom then model:SetPortraitZoom(model.zoom) end
    if canDraw ~= true then
        local crest = FACTION_LOGO[UnitFactionGroup(unit) or ""]
        if crest then
            logo:SetTexture(crest)
            logo:Show()
            model:Hide()
        else
            logo:Hide()
        end
    else
        logo:Hide()
    end
end

-- ============================================================
-- HEADER + FOOTER
-- ============================================================
-- InspectPaperDollFrame_SetLevel's line, with the class in its colour,
-- and the guild on the right (Era's inspect keeps its guild line hidden;
-- GetGuildInfo answers for any unit in range).
local function UpdateHeader()
    local unit = Unit()
    if not unit then
        win:SetTitle(INSPECT or "Inspect")
        infoLevel:SetText("")
        infoGuild:SetText("")
        return
    end
    win:SetTitle(GetUnitName(unit, true) or UnitName(unit) or (INSPECT or "Inspect"))
    local level = UnitLevel(unit)
    if not level or level == -1 then level = "??" end
    local className, classFile = UnitClass(unit)
    local race = UnitRace(unit) or ""
    local classText = ClassText(className, classFile)
    infoLevel:SetText(SafeFormat(PLAYER_LEVEL, level, race, classText)
        or ((LEVEL or "Level") .. " " .. level .. " " .. race .. " " .. classText))
    local guildName, rankTitle = GetGuildInfo(unit)
    if guildName then
        infoGuild:SetText(SafeFormat(GUILD_TITLE_TEMPLATE, rankTitle or "", guildName)
            or ((rankTitle or "") .. " - " .. guildName))
    else
        infoGuild:SetText("")
    end
end

local function AverageItemLevel(unit)
    local total, any, pending = 0, false, false
    for _, id in ipairs(AVG_SLOTS) do
        local link = GetInventoryItemLink(unit, id)
        if link then
            any = true
            local lvl = ItemLevel(link)
            if lvl then total = total + lvl else pending = true end
        end
    end
    -- A two-hander leaves the off hand empty by design: count it twice.
    local mh = GetInventoryItemLink(unit, MAINHAND)
    if mh and not GetInventoryItemLink(unit, OFFHAND)
        and select(9, GetInfo(mh)) == "INVTYPE_2HWEAPON" then
        total = total + (ItemLevel(mh) or 0)
    end
    return total / #AVG_SLOTS, any, pending
end

local function UpdateFooter()
    local unit = Unit()
    if not unit then
        ilvlText:SetText("")
        statusText:SetText("")
        return
    end
    local avg, any, pending = AverageItemLevel(unit)
    if pending then itemPending = true end
    if any then
        ilvlText:SetText("Item level " .. format("%.1f", avg) .. (pending and "*" or ""))
    else
        ilvlText:SetText("Item level --")
    end

    local status, key
    if tabs and tabs.active == "honor" then
        if honorPending then status, key = "Requesting honor data...", "gray" end
    elseif UnitIsVisible and not UnitIsVisible(unit) then
        status, key = "Out of range - showing the last data received", "orange"
    elseif not any then
        status, key = "Waiting for inspect data...", "gray"
    else
        status, key = "Shift-click: link  |  Ctrl-click: preview", "gray"
    end
    statusText:SetText(status or "")
    SetTextKey(statusText, key or "gray")
end

local function IlvlTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    local t = GetColor("tooltip", "title")
    local b = GetColor("tooltip", "body")
    GameTooltip:AddLine("Average item level", t.r, t.g, t.b)
    GameTooltip:AddLine("Every gear slot except shirt and tabard. An empty slot counts as 0; "
        .. "a two-hander counts for both hands.", b.r, b.g, b.b, true)
    if itemPending then
        GameTooltip:AddLine("* Some item details are still loading.", b.r, b.g, b.b, true)
    end
    GameTooltip:Show()
end

-- ============================================================
-- HONOR
-- ============================================================
-- InspectHonorFrame_Update's data, as a rank card and a period table
-- (Win_Character's honor page, fed by the inspect calls).
local DASH = "-"
local HONOR_ROWS = {
    { key = "session",   label = function() return HONOR_THIS_SESSION or "Today" end },
    { key = "yesterday", label = function() return HONOR_YESTERDAY or "Yesterday" end },
    { key = "thisweek",  label = function() return HONOR_THISWEEK or "This week" end },
    { key = "lastweek",  label = function() return HONOR_LASTWEEK or "Last week" end },
    { key = "lifetime",  label = function() return HONOR_LIFETIME or "Lifetime" end },
}

local function Num(v) return v and tostring(v) or DASH end

local function HasHonorAPI()
    -- (WoW Forever has none of the Classic honor calls)
    return GetInspectHonorData and HasInspectHonorData and RequestInspectHonorData
        and GetPVPRankInfo and UnitPVPRank and true or false
end

-- InspectHonorFrame_OnShow: ask the server once, draw when it answers.
local function RequestHonor()
    if not HasHonorAPI() or not Unit() then return end
    if HasInspectHonorData() then
        honorPending = false
    else
        honorPending = true
        RequestInspectHonorData()
    end
end

-- A flat bar: our own fill over our own box, no StatusBar art.
local function FlatBar(parent, height)
    local f = UI.Box(parent, "ui", "elementBg")
    f:SetHeight(height)
    local b = CreateFrame("StatusBar", nil, f)
    b:SetPoint("TOPLEFT", 1, -1)
    b:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetStatusBarTexture(FLAT)
    local t = b:GetStatusBarTexture()
    if t then t._zui_own = true end
    b:SetMinMaxValues(0, 1)
    b:SetValue(0)
    b:SetFrameLevel(f:GetFrameLevel() + 1)
    f.bar = b
    return f
end

local function ClearHonor()
    honor.rankName:SetText(NONE or "None")
    honor.rankNum:SetText("")
    honor.rankIcon:Hide()
    honor.bar.bar:SetValue(0)
    honor.pct:SetText("")
    for _, row in ipairs(honor.cells) do
        for c = 2, 4 do row[c]:SetText(DASH) end
    end
    honor.standing:SetText("")
    honor.highest:SetText("")
end

local function Label(text)
    local c = GetColor("text", "gray")
    return format("|cff%02x%02x%02x%s|r", floor(c.r * 255 + 0.5), floor(c.g * 255 + 0.5),
        floor(c.b * 255 + 0.5), text)
end

local function UpdateHonor()
    local unit = Unit()
    if not unit or not HasHonorAPI() then
        ClearHonor()
        return
    end
    if HasInspectHonorData() then honorPending = false end
    local sessionHK, sessionDK, yesterdayHK, yesterdayHonor, thisweekHK, thisweekHonor,
        lastweekHK, lastweekHonor, lastweekStanding, lifetimeHK, lifetimeDK, lifetimeRank = GetInspectHonorData()

    -- Blizzard reads the rank off "target" even for a party inspect; the
    -- inspected unit is what it means.
    local rankName, rankNumber = GetPVPRankInfo(UnitPVPRank(unit) or 0)
    rankNumber = rankNumber or 0
    honor.rankName:SetText(rankName or (NONE or "None"))
    honor.rankNum:SetText("(" .. (RANK or "Rank") .. " " .. rankNumber .. ")")
    if rankNumber > 0 then
        honor.rankIcon:SetTexture(format("%s%02d", "Interface\\PvPRankBadges\\PvPRank", rankNumber))
        honor.rankIcon:Show()
    else
        honor.rankIcon:Hide()
    end

    -- Faction colour for the progress bar: Blizzard's own table.
    local faction = UnitFactionGroup(unit)
    local fc = PLAYER_FACTION_COLORS and PLAYER_FACTION_COLORS[(faction == "Alliance") and 1 or 0]
    local r, g, b
    if fc and fc.r then r, g, b = fc.r, fc.g, fc.b
    else r, g, b = Kit.TextRGB((faction == "Alliance") and "blue" or "red") end
    local prog = (GetInspectPVPRankProgress and GetInspectPVPRankProgress()) or 0
    honor.bar.bar:SetStatusBarColor(r, g, b, 1)
    honor.bar.bar:SetValue(max(0, min(prog, 1)))
    honor.pct:SetText(floor(prog * 100 + 0.5) .. "%")

    local values = {
        session   = { Num(sessionHK), Num(sessionDK), DASH },
        yesterday = { Num(yesterdayHK), DASH, Num(yesterdayHonor) },
        thisweek  = { Num(thisweekHK), DASH, Num(thisweekHonor) },
        lastweek  = { Num(lastweekHK), DASH, Num(lastweekHonor) },
        lifetime  = { Num(lifetimeHK), Num(lifetimeDK), DASH },
    }
    for i, spec in ipairs(HONOR_ROWS) do
        local row, vals = honor.cells[i], values[spec.key]
        for c = 1, 3 do row[c + 1]:SetText(vals[c]) end
    end
    honor.standing:SetText(Label((HONOR_STANDING or "Standing") .. ": ")
        .. ((lastweekStanding and lastweekStanding > 0) and tostring(lastweekStanding) or DASH))
    local hiName = lifetimeRank and GetPVPRankInfo(lifetimeRank)
    honor.highest:SetText(Label((HONOR_HIGHEST_RANK or "Highest rank") .. ": ")
        .. (hiName or (NONE or "None")))
end

local function BuildHonor(page)
    local y = 0
    local icon = page:CreateTexture(nil, "ARTWORK")
    icon._zui_own = true
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
    honor.rankIcon = icon
    honor.rankName = UI.Font(page, F.CARD, { justify = "LEFT" })
    honor.rankName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    honor.rankName:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, y - 2)
    honor.rankName:SetWordWrap(false)
    honor.rankNum = UI.Font(page, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    honor.rankNum:SetPoint("TOPLEFT", honor.rankName, "BOTTOMLEFT", 0, -4)
    honor.rankNum:SetPoint("TOPRIGHT", honor.rankName, "BOTTOMRIGHT", 0, -4)
    honor.rankNum:SetWordWrap(false)
    -- Blizzard's rank tooltip (InspectHonorFrameRankButton).
    local rankHit = CreateFrame("Frame", nil, page)
    rankHit:SetPoint("TOPLEFT", icon, "TOPLEFT")
    rankHit:SetPoint("BOTTOMRIGHT", honor.rankNum, "BOTTOMRIGHT")
    rankHit:EnableMouse(true)
    UI.Tooltip(rankHit, RANK or "Rank", NEWBIE_TOOLTIP_RANK)

    local y2 = y - 32 - 10
    honor.pct = UI.Font(page, F.SMALL, { justify = "RIGHT" })
    honor.pct:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, y2 - 1)
    honor.pct:SetWidth(40)
    honor.pct:SetWordWrap(false)
    honor.bar = FlatBar(page, 14)
    honor.bar:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y2)
    honor.bar:SetPoint("TOPRIGHT", page, "TOPRIGHT", -46, y2)
    honor.bar:EnableMouse(true)
    -- InspectHonorFrameProgressButton's tooltip.
    UI.Tooltip(honor.bar, RANK_POSITION or "Rank progress", NEWBIE_TOOLTIP_RANK_POSITION)

    -- The table: a header row and five periods, fixed rows (nothing here
    -- scrolls), on one flat card.
    local y3 = y2 - 14 - 14
    local ROW = 24
    local tbl = UI.Box(page, "ui", "cardBg")
    tbl:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y3)
    tbl:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, y3)
    tbl:SetHeight(ROW * (#HONOR_ROWS + 1) + 2)

    local function MakeRow(i)
        local r = CreateFrame("Frame", nil, tbl)
        r:SetHeight(ROW)
        r:SetPoint("TOPLEFT", tbl, "TOPLEFT", 1, -1 - (i - 1) * ROW)
        r:SetPoint("TOPRIGHT", tbl, "TOPRIGHT", -1, -1 - (i - 1) * ROW)
        local stripe = r:CreateTexture(nil, "BACKGROUND")
        stripe._zui_own = true
        stripe:SetAllPoints()
        stripe:SetTexture(FLAT)
        r._zPaint = function()
            local e = GetColor("ui", i == 1 and "headerBg" or "elementBg")
            stripe:SetVertexColor(e.r, e.g, e.b, (i == 1) and 1 or ((i % 2 == 0) and 0.30 or 0.10))
        end
        r:_zPaint()
        return r
    end

    local columns = {
        { text = "HK",    title = HONORABLE_KILLS or "Honorable kills",       body = NEWBIE_TOOLTIP_HONORABLE_KILLS },
        { text = "DK",    title = DISHONORABLE_KILLS or "Dishonorable kills", body = NEWBIE_TOOLTIP_DISHONORABLE_KILLS },
        { text = HONOR or "Honor", title = HONOR_CONTRIBUTION_POINTS or "Honor",
          body = NEWBIE_TOOLTIP_HONOR_CONTRIBUTION_POINTS },
    }
    -- Header cells take the mouse for Blizzard's newbie tooltips.
    local head = MakeRow(1)
    local headCells = { UI.Font(head, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" }) }
    for c, col in ipairs(columns) do
        local hit = CreateFrame("Frame", nil, head)
        hit:SetHeight(ROW)
        hit:EnableMouse(true)
        local fs = UI.Font(hit, F.SMALL, { text = col.text, cat = "text", key = "gold", justify = "RIGHT" })
        fs:SetPoint("RIGHT", hit, "RIGHT", 0, 0)
        fs:SetWordWrap(false)
        UI.Tooltip(hit, col.title, col.body)
        headCells[c + 1] = hit
    end

    honor.cells = {}
    for i, spec in ipairs(HONOR_ROWS) do
        local r = MakeRow(i + 1)
        local row = { UI.Font(r, F.SMALL, { text = spec.label(), justify = "LEFT" }) }
        row[1]:SetWordWrap(false)
        for c = 1, 3 do
            row[c + 1] = UI.Font(r, F.SMALL, { justify = "RIGHT", text = DASH })
            row[c + 1]:SetWordWrap(false)
        end
        honor.cells[i] = row
    end

    -- Column widths follow the table's measured width: the label takes a
    -- third, the three numbers share the rest, each right-aligned 8px
    -- inside its column (the header text too, so they line up).
    local function Layout()
        local w = (tbl:GetWidth() or 0) - 2
        if w <= 0 then return end
        local labelW = floor(w * 0.34)
        local colW = floor((w - labelW) / 3)
        local function Place(row)
            for c, cell in ipairs(row) do
                cell:ClearAllPoints()
                if c == 1 then
                    cell:SetPoint("LEFT", cell:GetParent(), "LEFT", 8, 0)
                    cell:SetWidth(labelW - 8)
                else
                    cell:SetPoint("LEFT", cell:GetParent(), "LEFT", labelW + (c - 2) * colW, 0)
                    cell:SetWidth(colW - 8)
                end
            end
        end
        Place(headCells)
        for _, row in ipairs(honor.cells) do Place(row) end
    end
    tbl:SetScript("OnSizeChanged", Layout)
    Layout()

    local y4 = y3 - (ROW * (#HONOR_ROWS + 1) + 2) - 10
    honor.standing = UI.Font(page, F.SMALL, { justify = "LEFT" })
    honor.standing:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y4)
    honor.standing:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, y4)
    honor.standing:SetWordWrap(false)
    honor.highest = UI.Font(page, F.SMALL, { justify = "LEFT" })
    honor.highest:SetPoint("TOPLEFT", honor.standing, "BOTTOMLEFT", 0, -6)
    honor.highest:SetPoint("TOPRIGHT", honor.standing, "BOTTOMRIGHT", 0, -6)
    honor.highest:SetWordWrap(false)
    ClearHonor()
end

-- ============================================================
-- REFRESH (coalesced)
-- ============================================================
local dirty = {}
local queued = false

local function Flush()
    queued = false
    -- IsVisible, not IsShown: the cover is a shown child all session.
    if not win or not win:IsVisible() then
        for k in pairs(dirty) do dirty[k] = nil end
        return
    end
    if dirty.header then UpdateHeader() end
    if dirty.slots then UpdateCells() end
    if dirty.model then UpdateModel() end
    if dirty.honor and tabs.active == "honor" then UpdateHonor() end
    if dirty.footer or dirty.slots or dirty.honor then UpdateFooter() end
    for k in pairs(dirty) do dirty[k] = nil end
end

function Mark(...)
    for i = 1, select("#", ...) do dirty[select(i, ...)] = true end
    if queued then return end
    queued = true
    C_Timer.After(0, Flush)
end

local function MarkAll() Mark("header", "slots", "model", "honor", "footer") end

-- Everything back to empty: the inspect window is closing, and the next
-- one may be somebody else.
local function Clear()
    for k in pairs(dirty) do dirty[k] = nil end
    itemPending, honorPending = false, false
    if not win then return end
    for _, b in ipairs(cells) do
        if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
        b.hover:Hide()
        EmptyCell(b, nil)
    end
    if model then
        StopDrag(model)
        if model.ClearModel then model:ClearModel() end
        model.rotation, model.zoom = DEFAULT_ROTATION, 0
    end
    if logo then logo:Hide() end
    win:SetTitle(INSPECT or "Inspect")
    infoLevel:SetText("")
    infoGuild:SetText("")
    ilvlText:SetText("")
    statusText:SetText("")
    ClearHonor()
end

local function SelectPage(key)
    for k, p in pairs(pages) do p:SetShown(k == key) end
    if key == "honor" then RequestHonor() end
    Mark("honor", "footer")
end

-- ============================================================
-- EVENTS
-- ============================================================
local function OnEvent(_, event, arg1)
    if not win or not win:IsVisible() then return end
    local unit = Unit()
    if not unit then return end
    if event == "INSPECT_READY" then
        if arg1 and UnitGUID(unit) == arg1 then MarkAll() end
    elseif event == "INSPECT_HONOR_UPDATE" then
        honorPending = false
        Mark("honor", "footer")
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if itemPending then Mark("slots", "footer") end
    elseif arg1 == unit then
        if event == "UNIT_INVENTORY_CHANGED" then
            Mark("slots", "footer")
        elseif event == "UNIT_MODEL_CHANGED" then
            Mark("model")
        elseif event == "UNIT_LEVEL" or event == "UNIT_NAME_UPDATE" then
            Mark("header")
        end
    end
end

-- Names verified against Vanilla/Blizzard_InspectUI.lua,
-- InspectPaperDollFrame_Shared.lua and InspectHonorFrame.lua; pcall so a
-- client without one raises nothing.
local function RegisterEvents(ev)
    for _, e in ipairs({ "INSPECT_READY", "INSPECT_HONOR_UPDATE", "UNIT_INVENTORY_CHANGED",
        "UNIT_MODEL_CHANGED", "UNIT_LEVEL", "UNIT_NAME_UPDATE", "GET_ITEM_INFO_RECEIVED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
end

-- ============================================================
-- BUILD
-- ============================================================
-- The X runs Blizzard's close button handler (UIPanelCloseButton_OnClick
-- -> HideUIPanel). That is refused for any addon in combat, so there it
-- points at Escape instead of raising "Interface action blocked".
local function CloseInspect()
    if InCombatLockdown() then
        if UIErrorsFrame then
            local c = GetColor("text", "red")
            UIErrorsFrame:AddMessage("Press Escape to close the inspect window in combat.", c.r, c.g, c.b)
        end
        return
    end
    local blizzClose = InspectFrame.CloseButton or _G.InspectFrameCloseButton
    if blizzClose then
        blizzClose:Click()
    else
        HideUIPanel(InspectFrame)
    end
end

local function HotSpot(parent, region, fn)
    local hot = CreateFrame("Frame", nil, parent)
    hot:SetAllPoints(region)
    hot:EnableMouse(true)
    hot:SetScript("OnEnter", fn)
    hot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return hot
end

local function Build()
    if win then return win end
    win = Kit.Cover(InspectFrame, {
        name = "ZacUIInspectWindow",
        title = INSPECT or "Inspect",
        insetName = "InspectFrame",
        width = WIN_W,
        height = WIN_H,
        onClose = CloseInspect,
    })

    -- Level / race / class on the left, guild on the right, one line.
    local info = CreateFrame("Frame", nil, win)
    info:SetHeight(INFO_H)
    info:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, -(M.TITLEBAR + 2))
    info:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, -(M.TITLEBAR + 2))
    infoLevel = UI.Font(info, F.LABEL, { justify = "LEFT" })
    infoLevel:SetPoint("LEFT", info, "LEFT", 0, 0)
    infoLevel:SetWordWrap(false)
    infoGuild = UI.Font(info, F.SMALL, { justify = "RIGHT", cat = "text", key = "gray" })
    infoGuild:SetPoint("RIGHT", info, "RIGHT", 0, 0)
    infoGuild:SetPoint("LEFT", infoLevel, "RIGHT", 10, 0)
    infoGuild:SetWordWrap(false)

    -- Pages: the gear sheet and the honor page, one shown at a time.
    pages = {}
    local function Page(key)
        local p = CreateFrame("Frame", nil, win)
        p:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, PAGE_Y)
        p:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, PAGE_Y)
        p:SetHeight(PAGE_H)
        pages[key] = p
        return p
    end

    -- GEAR: two columns of eight in Blizzard's order, the model between.
    local gear = Page("gear")
    local step = SLOT + ROW_GAP
    for i, name in ipairs(LEFT_SLOTS) do
        BuildCell(gear, name, "left"):SetPoint("TOPLEFT", gear, "TOPLEFT", 0, -(i - 1) * step)
    end
    for i, name in ipairs(RIGHT_SLOTS) do
        BuildCell(gear, name, "right"):SetPoint("TOPRIGHT", gear, "TOPRIGHT", 0, -(i - 1) * step)
    end
    -- Weapons across the full width, three equal cells. The ranged slot
    -- only where the client shows one (InspectPaperDollFrame_OnLoad).
    local weapons = {}
    for _, name in ipairs(WEAPON_SLOTS) do
        local shown = true
        if name == "RangedSlot" and C_PaperDollInfo and C_PaperDollInfo.IsRangedSlotShown then
            shown = C_PaperDollInfo.IsRangedSlotShown() and true or false
        end
        if shown then weapons[#weapons + 1] = name end
    end
    local innerW = WIN_W - Kit.PAD * 2
    local wW = floor((innerW - (#weapons - 1) * COL_GAP) / max(1, #weapons))
    for i, name in ipairs(weapons) do
        BuildCell(gear, name, "left", wW):SetPoint("TOPLEFT", gear, "TOPLEFT",
            (i - 1) * (wW + COL_GAP), -(COLUMN_H + WEAPON_GAP))
    end

    local stage = UI.Box(gear, "ui", "cardBg")
    stage:SetPoint("TOPLEFT", gear, "TOPLEFT", CELL_W + COL_GAP, 0)
    stage:SetSize(MODEL_W, COLUMN_H)
    model = BuildModel(stage)
    logo = stage:CreateTexture(nil, "ARTWORK")
    logo._zui_own = true
    logo:SetSize(160, 160)
    logo:SetPoint("CENTER", stage, "CENTER", 0, 0)
    logo:SetAlpha(0.6)
    logo:Hide()

    -- HONOR
    local honorPage = Page("honor")
    BuildHonor(honorPage)
    honorPage:Hide()

    local specs = { { key = "gear", label = "Gear" } }
    if HasHonorAPI() then specs[2] = { key = "honor", label = HONOR or "Honor" } end
    tabs = Kit.Tabs(win, specs, SelectPage)
    tabs:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, TABS_Y)
    tabs:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, TABS_Y)
    tabs:Paint("gear")

    -- Footer: average item level on the left, status / hint on the right.
    win.footer = Kit.Footer(win)
    ilvlText = UI.Font(win.footer, F.LABEL, { justify = "LEFT" })
    ilvlText:SetPoint("LEFT", win.footer, "LEFT", 8, 0)
    ilvlText:SetWordWrap(false)
    HotSpot(win.footer, ilvlText, IlvlTooltip)
    statusText = UI.Font(win.footer, F.SMALL, { justify = "RIGHT", cat = "text", key = "gray" })
    statusText:SetPoint("RIGHT", win.footer, "RIGHT", -8, 0)
    statusText:SetPoint("LEFT", win.footer, "LEFT", 150, 0)
    statusText:SetWordWrap(false)

    local ev = CreateFrame("Frame", nil, win)
    RegisterEvents(ev)
    ev:SetScript("OnEvent", OnEvent)

    Clear()
    return win
end

-- ============================================================
-- SILENCING BLIZZARD'S PIECES
-- ============================================================
-- What of InspectFrame shows around or through the cover: its portrait
-- and frame art (they poke past the top-left), PortraitContainer and
-- TitleContainer (absolute frame levels 400 / 510 - they would draw OVER
-- the cover), the close button, the Character / Honor tabs below it (our
-- tabs replace them), the name plate, and InspectModelFrame (under the
-- cover, but a second model rendering for nobody).
function Leftovers()
    local t = {}
    local function Add(f) if f then t[#t + 1] = f end end
    local host = InspectFrame
    if not host then return t end
    for _, r in ipairs({ host:GetRegions() }) do
        if not r._zui_own then Add(r) end
    end
    Add(host.NineSlice)
    Add(host.PortraitContainer)
    Add(host.TitleContainer)
    Add(host.Inset)
    Add(host.CloseButton or _G.InspectFrameCloseButton)
    Add(_G.InspectNameFrame)
    Add(_G.InspectModelFrame)
    for i = 1, max(host.numTabs or 0, 2) do Add(_G["InspectFrameTab" .. i]) end
    return t
end

-- ============================================================
-- APPLY
-- ============================================================
-- Nothing secure, so no combat gate: the toggle is read on every open.
function Apply()
    if not InspectFrame then return end
    if Enabled() then
        Build()
        win.Reanchor()
        win:Show()
        Kit.Silence(Leftovers())
    elseif win then
        win:Hide()
        Kit.Unsilence(Leftovers())
    end
end

-- InspectFrame_Show opens every inspect on Blizzard's first tab; we do
-- the same, with the model turned back to face the camera.
local function OnHostShow()
    Apply()
    if not win or not win:IsShown() then return end
    if model then model.rotation, model.zoom = DEFAULT_ROTATION, 0 end
    tabs:Select("gear")
    MarkAll()
end

local function OnHostHide()
    Clear()
end

-- ============================================================
-- MODULE
-- ============================================================
-- Hooked once, when Blizzard_InspectUI is up. NOT through
-- ns.RegisterLoD: its registry holds ONE function per addon name and the
-- "inspect" skin module already parks its skin there.
local function OnInspectUILoaded()
    if hooked or not InspectFrame then return end
    hooked = true
    InspectFrame:HookScript("OnShow", OnHostShow)
    InspectFrame:HookScript("OnHide", OnHostHide)
    -- Blizzard's own redraw points: the slot pass on show / INSPECT_READY,
    -- and a unit swap on an open window.
    if InspectPaperDollFrame_UpdateButtons then
        hooksecurefunc("InspectPaperDollFrame_UpdateButtons", function() Mark("slots", "footer") end)
    end
    if InspectFrame_UnitChanged then
        hooksecurefunc("InspectFrame_UnitChanged", function() MarkAll() end)
    end
    if InspectFrame:IsShown() then OnHostShow() end
end

Modules.inspectwin = function()
    if ns._zInspectWin then return end
    ns._zInspectWin = true
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded("Blizzard_InspectUI") then
        OnInspectUILoaded()
        return
    end
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("ADDON_LOADED")
    watch:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_InspectUI" then
            self:UnregisterEvent("ADDON_LOADED")
            OnInspectUILoaded()
        end
    end)
end
