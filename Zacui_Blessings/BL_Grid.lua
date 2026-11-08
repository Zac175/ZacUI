-- BL_Grid - the assignment window: one row per paladin in the group, one
-- column per class, the aura at the end. Click a cell to give that class
-- the next blessing the paladin knows that nobody else gives it (right
-- click goes back), Shift-click gives every class that blessing, Ctrl-
-- click sets a single player's own blessing. Cells you may not change
-- are dimmed (see BL.CanControl). Open it from the Blessings page or by
-- clicking the casting bar's title.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local D = ns.BlessingsData
local BL = ns.Blessings
if not (D and BL) then return end

local UI = ns.UI
local M, F = UI.M, UI.F
local Print = ns.Print

local Grid = {}
BL.Grid = Grid

local NAME_W = 130
local CELL = 32
local GAP = 3
local PAD = 12

local win, header, rowsHost, footer
local rowFrames = {}

local function Icon(id) local _, _, i = GetSpellInfo(id or 0) return i end
local function BlessingIcon(b)
    local e = D.BLESSINGS[b]
    if e then return Icon(e.greater or e.normal) end
    if D.NORMAL_ONLY[b] then return Icon(D.NORMAL_ONLY[b]) end
    return nil
end
local function BlessingName(b, greater)
    local e = D.BLESSINGS[b]
    if e then return GetSpellInfo(greater and e.greater or e.normal) end
    if D.NORMAL_ONLY[b] then return GetSpellInfo(D.NORMAL_ONLY[b]) end
    return nil
end
Grid.BlessingIcon, Grid.BlessingName = BlessingIcon, BlessingName

local function Cell(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(CELL, CELL)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    UI.Fill(c, "ui", "elementBg")
    UI.Border(c, "ui", "border")
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 2, -2)
    c.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    ZacUI.Look.CropIcon(c.icon)
    -- an empty cell: a faint dash, not a white square
    c.empty = c:CreateFontString(nil, "OVERLAY")
    -- (ZacUI's font, kept up when it changes)
    if ns.FollowFont then ns.FollowFont(c.empty, 14, "OUTLINE", STANDARD_TEXT_FONT) end
    if not c.empty:GetFont() then c.empty:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE") end
    c.empty:SetPoint("CENTER", 0, 0)
    c.empty:SetText("-")
    c.empty:SetTextColor(0.45, 0.45, 0.45)
    c.SetBlessingIcon = function(self, tex)
        if tex then
            self.icon:SetTexture(tex)
            self.icon:Show()
            self.empty:Hide()
        else
            self.icon:Hide()
            self.empty:Show()
        end
    end
    c.mark = c:CreateFontString(nil, "OVERLAY")
    if ns.FollowFont then ns.FollowFont(c.mark, 10, "OUTLINE", STANDARD_TEXT_FONT) end
    if not c.mark:GetFont() then c.mark:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE") end
    c.mark:SetPoint("BOTTOMRIGHT", -1, 1)
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(ns.FLAT or "Interface\\Buttons\\WHITE8X8")
    hl:SetVertexColor(1, 1, 1, 0.12)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return c
end

-- the per-player menu for one paladin and one class
local function PlayerMenu(cell, name, slot)
    local members = BL.bySlot[slot] or {}
    if #members == 0 then Print("blessings: nobody of that class in the group.") return end
    local p = BL.Pally(name)
    local items = { { text = name .. " - single players", isTitle = true } }
    for _, m in ipairs(members) do
        local cur = p.normal[slot] and p.normal[slot][m.name]
        local children = { { text = "The class blessing", checked = not cur, func = function()
            BL.SetNormal(name, slot, m.name, 0) end } }
        for b = 1, D.SACRIFICE do
            local known = BL.Knows(name, b) or (b == D.SACRIFICE)
            if known and BlessingName(b) then
                children[#children + 1] = { text = BlessingName(b), checked = cur == b,
                    func = function() BL.SetNormal(name, slot, m.name, b) end }
            end
        end
        items[#items + 1] = { text = m.name .. (cur and ("  |cffffd100" .. (BlessingName(cur) or "") .. "|r") or ""),
            children = children }
    end
    UI.ContextMenu(items, { anchor = cell })
end

-- THE WINDOW'S TEXTS, placeable (ZacUIDB.blessings.gridAnchors.<name|sub|
-- mark|count>, ZacUI's anchor shape): each SetPoint this file always made
-- is the default, the saved anchor goes on top. Nothing saved = never
-- touched. The live window and the Blessings page's sample share it.
--   name   a paladin's name on his row      sub    the line under it
--   mark   a cell's "+N" single players     count  how many of a class (header)
local function GridSpec(key)
    local c = BL.Cfg()
    local a = c and c.gridAnchors
    local s = type(a) == "table" and a[key] or nil
    if type(s) ~= "table" or next(s) == nil then return nil end
    return s
end
local function FillDefault(d, key, r)
    if key == "name" then
        d.point, d.relPoint, d.x, d.y, d.to = "LEFT", "LEFT", 0, 4, r
    elseif key == "sub" then
        d.point, d.relPoint, d.x, d.y, d.to = "TOPLEFT", "BOTTOMLEFT", 0, -1, r and r.name
    elseif key == "mark" then
        d.point, d.relPoint, d.x, d.y, d.to = "BOTTOMRIGHT", "BOTTOMRIGHT", -1, 1, r
    else -- count
        d.point, d.relPoint, d.x, d.y, d.to = "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, r
    end
    return d
end
function Grid.AnchorDefaults(key) return FillDefault({}, key, nil) end
Grid.ANCHOR_KEYS = { "name", "sub", "mark", "count" }
Grid.ANCHOR_LABELS = { name = "Paladin names", sub = "The line under a name", mark = "Single players (+N) on a cell",
    count = "How many of a class (header)", row = "The row", cell = "The cell", header = "The class icon" }
-- one text onto its spot: region, key, the frame its default hangs off
-- (row / cell / header cell), what "row" means for a row text
local function PlaceText(region, key, host, row)
    local spec = GridSpec(key)
    if not (spec or region._zGridPlaced) then return end
    local d = region._zGridDef or {}
    region._zGridDef = d
    FillDefault(d, key, host)
    ns.ApplyAnchor(region, spec, d, function(k)
        if k == "row" then return row end
        if k == "name" then return row and row.name end
        if k == "sub" then return row and row.sub end
    end)
    region._zGridPlaced = spec and true or nil
end
-- a row's name, sub line and every cell's mark
function Grid.PlaceRow(r)
    PlaceText(r.name, "name", r, r)
    PlaceText(r.sub, "sub", r, r)
    for _, c in ipairs(r.cells) do PlaceText(c.mark, "mark", c, r) end
end
function Grid.PlaceHeader(h)
    for _, cell in ipairs(h.cells) do PlaceText(cell.count, "count", cell, nil) end
end

-- The class header: an icon per class (and the aura), each with its count.
-- (`preview`: the Blessings page's sample, tagged for "customize this element")
function Grid.NewHeader(parent, width, preview)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(width, CELL)
    header.cells = {}
    for slot = 1, D.NUM_CLASSES + 1 do
        local h = CreateFrame("Frame", nil, header)
        h:SetSize(CELL, CELL)
        h:SetPoint("LEFT", header, "LEFT", NAME_W + (slot - 1) * (CELL + GAP), 0)
        h.icon = h:CreateTexture(nil, "ARTWORK")
        h.icon:SetAllPoints()
        h.count = h:CreateFontString(nil, "OVERLAY")
        if ns.FollowFont then ns.FollowFont(h.count, 10, "OUTLINE", STANDARD_TEXT_FONT) end
        if not h.count:GetFont() then h.count:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE") end
        h.count:SetPoint("BOTTOMRIGHT", 0, 0)
        if slot <= D.NUM_CLASSES then
            local cls = D.CLASSES[slot]
            if cls ~= "PET" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls] then
                h.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                h.icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[cls]))
            else
                h.icon:SetTexture(D.CLASS_ICON[cls])
                ZacUI.Look.CropIcon(h.icon)
            end
        else
            h.icon:SetTexture(Icon(465))
            ZacUI.Look.CropIcon(h.icon)
        end
        header.cells[slot] = h
        if preview and ns.TagElement then ns.TagElement(h.count, "blgrid.count") ns.TagElement(h, "blgrid.count") end
    end
    local hint = UI.Font(header, F.SMALL, { text = "Paladin", cat = "text", key = "gray" })
    hint:SetPoint("LEFT", header, "LEFT", 0, 0)
    header.hint = hint
    return header
end

local function Build()
    if win then return end
    local w = PAD * 2 + NAME_W + (D.NUM_CLASSES + 1) * (CELL + GAP)
    win = UI.Window("ZacUIBlessingsGrid", w, 200, "Blessings")
    win._zOnMoved = function()
        local p = { win:GetPoint(1) }
        local c = BL.Cfg()
        if c then c.gridPos = { p[1], p[4], p[5] } end
    end
    header = Grid.NewHeader(win, w - PAD * 2)
    header:SetPoint("TOPLEFT", PAD, -(win.headerHeight + 8))
    rowsHost = CreateFrame("Frame", nil, win)
    rowsHost:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    rowsHost:SetSize(w - PAD * 2, 10)
    footer = CreateFrame("Frame", nil, win)
    footer:SetSize(w - PAD * 2, 74)
    footer:SetPoint("BOTTOMLEFT", PAD, 8)
    local auto = UI.Button(footer, "Auto-assign", { width = 100, tooltip = "Splits the blessings over the paladins "
        .. "you may set: Kings for everyone, Might for melee, Wisdom for casters, Salvation for all but warriors, "
        .. "then Light, best talent first. Auras one each.", onClick = function()
            local n = BL.AutoAssign()
            if n == 0 then Print("blessings: you may not set anyone's blessings here.") end
        end })
    auto:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    local clear = UI.Button(footer, "Clear", { width = 70, tooltip = "Clears what you may change (as leader or "
        .. "assistant: everyone's).", onClick = function()
            UI.Confirm({ title = "Blessings", text = "Clear the blessing assignments you may change?",
                acceptText = "Clear", onAccept = function() BL.ClearAll(false) end })
        end })
    clear:SetPoint("LEFT", auto, "RIGHT", 6, 0)
    local req = UI.Button(footer, "Refresh", { width = 70, tooltip = "Asks every paladin in the group to send "
        .. "their blessings again.", onClick = function() BL.Comm.Request() BL.ScanRoster() end })
    req:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    win.free = UI.Checkbox(footer, "Anyone may set my blessings", BL.FreeAssign(), function(v)
        local c = BL.Cfg()
        c.freeassign = v and true or false
        local p = BL.pallys[BL.me]
        if p then p.freeassign = c.freeassign end
        BL.Comm.Fresh()
        BL.Comm.SendSelf()
    end)
    win.free:SetPoint("TOPLEFT", auto, "BOTTOMLEFT", 0, -8)
    -- its own line under the rest, where the buttons can't cover it
    win.help = UI.Font(footer, F.SMALL, { text = "Click: next   Right-click: back   Shift: every class   Ctrl: single players",
        cat = "text", key = "gray" })
    win.help:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", 0, 0)
    local c = BL.Cfg()
    if c and type(c.gridPos) == "table" then
        win:ClearAllPoints()
        win:SetPoint(c.gridPos[1] or "CENTER", UIParent, c.gridPos[1] or "CENTER", c.gridPos[2] or 0, c.gridPos[3] or 0)
    end
end

-- The window in ZacUI's mover mode as well (Movers page, Edit Mode), its
-- spot kept where the window keeps it (gridPos). Before it is first
-- opened the box stands at that spot at its usual width.
if ns.RegisterMover then
    ns.RegisterMover("blessingsGrid", "Blessings assignment window", function() return win end, "CENTER", 0, 0, nil, {
        get = function()
            local c = BL.Cfg and BL.Cfg()
            local p = c and c.gridPos
            if type(p) == "table" then return p[1] or "CENTER", p[2] or 0, p[3] or 0 end
        end,
        set = function(point, x, y)
            local c = BL.Cfg and BL.Cfg()
            if c then c.gridPos = point and { point, x or 0, y or 0 } or nil end
        end,
        reset = function()
            if not win then return end
            win:ClearAllPoints()
            win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end,
        own = true,
    })
end

-- One paladin's row: name, the line under it, a cell per class and the aura.
function Grid.NewRow(parent, width, preview)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(width, CELL)
    r.name = UI.Font(r, F.LABEL, { text = "" })
    r.name:SetPoint("LEFT", r, "LEFT", 0, 4)
    r.sub = UI.Font(r, F.SMALL, { text = "", cat = "text", key = "gray" })
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
    r.cells = {}
    for slot = 1, D.NUM_CLASSES + 1 do
        local c = Cell(r)
        c:SetPoint("LEFT", r, "LEFT", NAME_W + (slot - 1) * (CELL + GAP), 0)
        r.cells[slot] = c
        if preview and ns.TagElement then ns.TagElement(c.mark, "blgrid.mark") ns.TagElement(c, "blgrid.mark") end
    end
    if preview and ns.TagElement then
        ns.TagElement(r, "blgrid.name") ns.TagElement(r.name, "blgrid.name") ns.TagElement(r.sub, "blgrid.sub")
    end
    return r
end
Grid.CELL, Grid.GAP, Grid.NAME_W, Grid.PAD, Grid.Cell = CELL, GAP, NAME_W, PAD, Cell

local function Row(i)
    local r = rowFrames[i]
    if r then return r end
    r = Grid.NewRow(rowsHost, rowsHost:GetWidth())
    rowFrames[i] = r
    return r
end

function Grid.Refresh()
    if not (win and win:IsShown()) then return end
    for slot = 1, D.NUM_CLASSES do
        local n = BL.bySlot[slot] and #BL.bySlot[slot] or 0
        header.cells[slot].count:SetText(n > 0 and tostring(n) or "")
        header.cells[slot].icon:SetAlpha(n > 0 and 1 or 0.35)
    end
    Grid.PlaceHeader(header)
    local names = BL.PallyNames()
    for i, name in ipairs(names) do
        local r = Row(i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", rowsHost, "TOPLEFT", 0, -(i - 1) * (CELL + GAP))
        r:Show()
        Grid.PlaceRow(r)
        local p = BL.Pally(name)
        local may = BL.CanControl(name)
        local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS.PALADIN or { r = 0.96, g = 0.55, b = 0.73 }
        r.name:SetText(name)
        r.name:SetTextColor(col.r, col.g, col.b)
        local bits = {}
        bits[#bits + 1] = (p.symbols or 0) .. " sym"
        if p.freeassign then bits[#bits + 1] = "free" end
        if BL.IsLeader(name) then bits[#bits + 1] = "lead" end
        r.sub:SetText(table.concat(bits, "  "))
        for slot = 1, D.NUM_CLASSES do
            local c = r.cells[slot]
            local b = p.assign[slot] or 0
            c:SetBlessingIcon(b > 0 and BlessingIcon(b) or nil)
            local overs = 0
            if p.normal[slot] then for _ in pairs(p.normal[slot]) do overs = overs + 1 end end
            c.mark:SetText(overs > 0 and ("+" .. overs) or "")
            c:SetAlpha(may and 1 or 0.55)
            c:SetScript("OnClick", function(self, button)
                if not BL.CanControl(name) then Print("blessings: only " .. name .. ", the leader or an assistant may change that.") return end
                if IsControlKeyDown() then PlayerMenu(self, name, slot) return end
                if IsShiftKeyDown() then
                    local cur = BL.Pally(name).assign[slot] or 0
                    if cur == 0 then BL.Cycle(name, slot, 1) cur = BL.Pally(name).assign[slot] or 0 end
                    BL.SetAllClasses(name, cur)
                    return
                end
                BL.Cycle(name, slot, button == "RightButton" and -1 or 1)
            end)
            c:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(name .. " -> " .. (ns.Blessings.Bar and ns.Blessings.Bar.ClassLabel(slot) or D.CLASSES[slot]))
                local cur = BL.Pally(name).assign[slot] or 0
                GameTooltip:AddLine(cur > 0 and (BlessingName(cur, true) or BlessingName(cur)) or "nothing", 1, 0.82, 0)
                if p.normal[slot] then
                    for tn, nb in pairs(p.normal[slot]) do GameTooltip:AddLine(tn .. ": " .. (BlessingName(nb) or "?"), 0.8, 0.8, 0.8) end
                end
                GameTooltip:Show()
            end)
        end
        local ac = r.cells[D.NUM_CLASSES + 1]
        local a = p.aura or 0
        ac:SetBlessingIcon(a > 0 and Icon(D.AURAS[a].id) or nil)
        ac.mark:SetText("")
        ac:SetAlpha(may and 1 or 0.55)
        ac:SetScript("OnClick", function(_, button)
            if not BL.CanControl(name) then return end
            BL.CycleAura(name, button == "RightButton" and -1 or 1)
        end)
        ac:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local cur = BL.Pally(name).aura or 0
            GameTooltip:SetText(name .. " - aura")
            GameTooltip:AddLine(cur > 0 and GetSpellInfo(D.AURAS[cur].id) or "nothing", 1, 0.82, 0)
            GameTooltip:Show()
        end)
    end
    for i = #names + 1, #rowFrames do rowFrames[i]:Hide() end
    local rowsH = math.max(1, #names) * (CELL + GAP)
    if #names == 0 then
        if not win.empty then
            win.empty = UI.Font(rowsHost, F.LABEL, { text = "No paladins in the group yet.", cat = "text", key = "gray" })
            win.empty:SetPoint("TOPLEFT", rowsHost, "TOPLEFT", 0, -8)
        end
        win.empty:Show()
    elseif win.empty then
        win.empty:Hide()
    end
    win.free:SetShown(BL.isPaladin)
    win.free:SetChecked(BL.FreeAssign())
    win:SetHeight(win.headerHeight + 8 + CELL + 6 + rowsH + 92)
end

function Grid.Toggle()
    Build()
    if win:IsShown() then UI.CloseWindow(win) return end
    BL.ScanRoster()
    UI.OpenWindow(win)
    Grid.Refresh()
end

function Grid.Open()
    Build()
    if not win:IsShown() then UI.OpenWindow(win) end
    Grid.Refresh()
end

BL.OnChange("grid", Grid.Refresh)
