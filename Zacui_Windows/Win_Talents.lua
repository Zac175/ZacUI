-- Win_Talents - ZacUI's talent window: all three trees side by side in
-- one window, with the dual-spec tabs, instead of Blizzard's one tree
-- per page.
-- Part of ZacUI; load order is set by the TOC.
--
-- A WIN_KIT COVER, BIGGER THAN THE PANEL. The window is parented to
-- PlayerTalentFrame (load-on-demand, Blizzard_TalentUI) and keeps its
-- top-left corner, so N, the micro button and Escape open and close it
-- through Blizzard's own code. It is wide enough for three 4-column
-- trees, so everything of Blizzard's frame sits under it.
--
-- WHAT IS SECURE AND WHY. Learning a talent is an ordinary call
-- (Blizzard's talent button is a plain Button calling LearnTalent /
-- AddPreviewTalentPoints), so our talent buttons are plain buttons too.
-- Switching spec is not: Blizzard's Activate button casts the spec-swap
-- spell through C_SpecializationInfo.SetActiveSpecGroup, and it reads
-- WHICH spec from the talent UI's own selected-spec state. So the spec
-- tabs, Activate, Learn / Reset (preview) and the X are secure "click"
-- buttons on Blizzard's own PlayerSpecTabN / ActivateButton /
-- LearnButton / ResetButton / CloseButton. Blizzard's handlers then run
-- with Blizzard's credentials and Blizzard's state, and we only ever
-- READ that state to draw. The price: those few buttons can only be
-- shown, hidden or moved out of combat - in a fight they stay as they
-- were (they still click) and settle when it ends.
--
--   Left-click         spend a point (or add a preview point)
--   Right-click        remove a preview point (preview mode only)
--   Shift-click        link the talent in chat
--   Spec tabs          view Primary / Secondary / Pet talents
--   Activate           switch to the spec you are viewing

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local SharpenIcon = ns.SharpenIcon
local TEX_ARROW = ns.TEX_ARROW
local TEX_ARROWL = ns.TEX_ARROWL
local UI = ns.UI

local M, F = UI.M, UI.F

-- ============================================================
-- GEOMETRY
-- ============================================================
-- Blizzard spaces talents 63px apart around 32px buttons (TalentFrameBase
-- SetTalentButtonLocation). Three trees side by side need it tighter:
-- 34px icons on a 50px pitch keeps a 16px gap for the prerequisite lines.
local BTN       = 34
local PITCH     = 50
local GRID_X    = 14     -- grid edge -> first column
local GRID_Y    = 10     -- grid edge -> first tier
local ARROW     = 8
local LINE      = 2
local HEADER_H  = 30
local MIN_TIERS = 7      -- every Era tree ends at tier 7 (the 31-point talent)
local SPEC_ORDER = { "spec1", "spec2", "petspec1" }   -- TALENT_UI_SPECS keys

local function Columns()
    local c = Constants and Constants.TalentConsts and Constants.TalentConsts.NumTalentColumns
    if type(c) ~= "number" or c < 1 or c > 8 then c = 4 end
    return c
end

local COLS = Columns()
local TREE_W = GRID_X * 2 + (COLS - 1) * PITCH + BTN
local tiers = MIN_TIERS

local function GridH() return GRID_Y * 2 + (tiers - 1) * PITCH + BTN end
local function TreeH() return HEADER_H + GridH() end
local function TreesTop() return M.TITLEBAR + Kit.PAD + Kit.TAB_H + Kit.GAP end
local function WindowWidth() return Kit.PAD * 2 + 3 * TREE_W + 2 * Kit.GAP end
local function WindowHeight()
    return TreesTop() + TreeH() + Kit.GAP + Kit.FOOTER_H + 1
end

-- Distances measured DOWN / RIGHT from the grid's top-left corner.
local function CellLeft(col) return GRID_X + (col - 1) * PITCH end
local function CellTop(tier) return GRID_Y + (tier - 1) * PITCH end

local win, coverOpts, specRow, statusText, emptyText
local unspentText, summaryText, activate, learnBtn, resetBtn
local trees, specTabs = {}, {}
local pendingApply, hooked = false, false
local Queue, Apply   -- defined below; the event handlers need them first

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.talentswin ~= false
end

-- ============================================================
-- API SHIMS (each call copied from Classic/Blizzard_TalentUI.lua and
-- Vanilla/TalentFrameBase.lua; the old globals stay as fallbacks so a
-- client change degrades rather than errors)
-- ============================================================
local CSI = C_SpecializationInfo

local function ActiveGroup(pet)
    if CSI and CSI.GetActiveSpecGroup then return CSI.GetActiveSpecGroup(false, pet) or 1 end
    if GetActiveTalentGroup then return GetActiveTalentGroup(false, pet) or 1 end
    return 1
end

local function NumGroups(pet)
    if GetNumTalentGroups then return GetNumTalentGroups(false, pet) or 0 end
    return pet and 0 or 1
end

local function NumTabs(pet)
    return (GetNumTalentTabs and GetNumTalentTabs(false, pet)) or 0
end

-- name, icon, pointsSpent, background, previewPointsSpent
local function TabInfo(tab, pet, group)
    if CSI and CSI.GetSpecializationInfo then
        local _, name, _, icon, _, _, spent, bg, preview =
            CSI.GetSpecializationInfo(tab, false, pet, nil, nil, group)
        return name, icon, spent or 0, bg, preview or 0
    end
    if GetTalentTabInfo then
        local name, icon, spent, bg, preview = GetTalentTabInfo(tab, false, pet, group)
        return name, icon, spent or 0, bg, preview or 0
    end
    return nil, nil, 0, nil, 0
end

-- The TalentInfoResult table (talentID, icon, tier, column, rank,
-- maxRank, previewRank, meetsPrereq, meetsPreviewPrereq).
local function TalentInfo(tab, index, pet, group)
    if CSI and CSI.GetTalentInfo then
        return CSI.GetTalentInfo({
            specializationIndex = tab, talentIndex = index,
            isInspect = false, isPet = pet, groupIndex = group,
        })
    end
    if GetTalentInfo then
        local name, icon, tier, column, rank, maxRank, _, available, previewRank, previewAvailable =
            GetTalentInfo(tab, index, false, pet, group)
        if not name then return nil end
        return {
            talentID = 0, name = name, icon = icon, tier = tier, column = column,
            rank = rank or 0, maxRank = maxRank or 0, previewRank = previewRank or rank or 0,
            meetsPrereq = available, meetsPreviewPrereq = previewAvailable or available,
        }
    end
    return nil
end

local function IsPreview()
    return GetCVarBool and GetCVarBool("previewTalentsOption") and true or false
end

local function Unspent(pet, group)
    local points = (GetUnspentTalentPoints and GetUnspentTalentPoints(false, pet, group)) or 0
    local pending = (GetGroupPreviewTalentPointsSpent and GetGroupPreviewTalentPointsSpent(pet, group)) or 0
    return points - pending, points, pending
end

-- The spec Blizzard's talent UI has selected - the one its Activate
-- button would switch to. We draw that spec; our tabs change it by
-- clicking Blizzard's own tabs.
local function ViewedSpec()
    local spec = TalentUIUtil and TalentUIUtil.GetSelectedSpec and TalentUIUtil.GetSelectedSpec()
    if spec then return spec.talentGroup or 1, spec.pet and true or false, spec end
    return ActiveGroup(false), false, nil
end

local function IsSpecActive(spec)
    return spec and not spec.pet and spec.talentGroup == ActiveGroup(false)
end

-- Blizzard's rule (PlayerTalentFrameTalent_OnClick): points can only be
-- spent in the active spec, or in the pet's.
local function CanEdit(group, pet, spec)
    if spec then return spec.pet or IsSpecActive(spec) end
    if TalentUIUtil then return false end
    return not pet and group == ActiveGroup(false)
end

-- Blizzard's "primary tree" rule (TalentFrame_UpdateSpecInfoCache...
-- FromTalentTabInfo), reproduced rather than called so no Blizzard
-- upvalue is ever written from our code.
local function PrimaryTab(points, n)
    if n <= 0 then return 0 end
    local high, highI, low = 0, nil, math.huge
    local sorted = {}
    for i = 1, n do
        local p = points[i] or 0
        if p > high then high, highI = p, i end
        if p < low then low = p end
        sorted[i] = p
    end
    table.sort(sorted)
    local mid = sorted[math.floor(n / 2) + 1] or 0
    if highI and (3 * (mid - low)) < (2 * (high - low)) then return highI end
    return 0
end

local function SpecPoints(pet, group)
    local n = NumTabs(pet)
    local pts, names, icons, total = {}, {}, {}, 0
    for tab = 1, n do
        local name, icon, spent, _, preview = TabInfo(tab, pet, group)
        pts[tab] = spent + preview
        names[tab], icons[tab] = name, icon
        total = total + pts[tab]
    end
    return pts, names, icons, n, total
end

local function SetTextKey(fs, cat, key)
    fs._zPaintCat, fs._zPaintKey = cat, key
    fs:_zPaint()
end

local function SetBorderKey(frame, cat, key)
    frame._zBorderCat, frame._zBorderKey = cat, key
    frame:_zPaint()
end

-- ============================================================
-- SECURE CLICK OVERLAYS
-- ============================================================
-- A UI.Button for the look, with a SecureActionButton laid over it that
-- clicks Blizzard's own button. The visual takes no mouse; the overlay
-- forwards hover so the visual still lights up.
local function HoverPaint(visual)
    if visual._zDisabled or visual._zActive then return end
    local c = GetColor("button", "hover")
    if visual._zFill then visual._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
    if visual._zText then
        local a = GetColor("ui", "accent")
        visual._zText:SetTextColor(a.r, a.g, a.b, 1)
    end
end

-- Out of combat only (Build): a secure button's attributes and anchors
-- are frozen in a fight.
local function SecureOverlay(visual, target, onEnter)
    local s = CreateFrame("Button", nil, visual, "SecureActionButtonTemplate")
    s:SetAllPoints(visual)
    s:SetFrameLevel(visual:GetFrameLevel() + 2)
    s:SetAttribute("useOnKeyDown", false)
    s:RegisterForClicks("LeftButtonUp")
    s:SetAttribute("type", "click")
    s:SetAttribute("clickbutton", target)
    s:SetScript("OnEnter", function(self)
        HoverPaint(visual)
        if onEnter then onEnter(self) end
    end)
    s:SetScript("OnLeave", function()
        visual:_zPaint()
        GameTooltip:Hide()
    end)
    visual:EnableMouse(false)
    visual.secure = s
    return s
end

-- Paint-only disable: UI.Button:SetDisabled calls Disable(), which is
-- not ours to call on a protected button in combat.
local function PaintDisabled(visual, off)
    visual._zDisabled = off and true or nil
    visual:_zPaint()
end

-- ============================================================
-- TREE DRAWING: LINES AND ARROWS
-- ============================================================
local function Acquire(tree, pool, isArrow)
    tree.used[pool] = tree.used[pool] + 1
    local list = tree[pool]
    local t = list[tree.used[pool]]
    if not t then
        t = tree.lines:CreateTexture(nil, isArrow and "OVERLAY" or "ARTWORK")
        t._zui_own = true
        if not isArrow then t:SetTexture(FLAT) end
        list[#list + 1] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
end

local function LineColour(t, lit)
    local c = GetColor("text", lit and "green" or "disabled")
    t:SetVertexColor(c.r, c.g, c.b, lit and 1 or 0.8)
end

-- Horizontal at distance y down, from xa to xb.
local function HLine(tree, y, xa, xb, lit)
    local t = Acquire(tree, "lineTex")
    t:SetPoint("TOPLEFT", tree.grid, "TOPLEFT", math.min(xa, xb), -(y - LINE / 2))
    t:SetSize(math.max(1, math.abs(xb - xa)), LINE)
    LineColour(t, lit)
end

-- Vertical at distance x right, from ya to yb (both measured down).
local function VLine(tree, x, ya, yb, lit)
    local t = Acquire(tree, "lineTex")
    t:SetPoint("TOPLEFT", tree.grid, "TOPLEFT", x - LINE / 2, -math.min(ya, yb))
    t:SetSize(LINE, math.max(1, math.abs(yb - ya)))
    LineColour(t, lit)
end

-- "down": tip on the target's top edge (ex), centred on x.
-- "right"/"left": tip on the target's left / right edge, centred on y.
local function Arrow(tree, dir, a, b, lit)
    local t = Acquire(tree, "arrowTex", true)
    t:SetSize(ARROW, ARROW)
    if dir == "down" then
        t:SetTexture(TEX_ARROW)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetPoint("TOPLEFT", tree.grid, "TOPLEFT", a - ARROW / 2, -(b - ARROW))
    elseif dir == "right" then
        t:SetTexture(TEX_ARROWL)
        t:SetTexCoord(1, 0, 0, 1)
        t:SetPoint("TOPLEFT", tree.grid, "TOPLEFT", a - ARROW, -(b - ARROW / 2))
    else
        t:SetTexture(TEX_ARROWL)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetPoint("TOPLEFT", tree.grid, "TOPLEFT", a, -(b - ARROW / 2))
    end
    LineColour(t, lit)
end

local function OccKey(tier, col) return tier * 16 + col end

-- The route Blizzard's TalentFrame_DrawLines takes, drawn as flat lines:
-- straight down in a column, straight across a tier, and for a diagonal
-- across the prerequisite's tier then down - or, when a talent is in the
-- way on that tier, down the prerequisite's column then across.
local function DrawPrereq(tree, bt, bc, pt, pc, lit)
    local half = BTN / 2
    if pc == bc then
        local x = CellLeft(bc) + half
        VLine(tree, x, CellTop(pt) + BTN, CellTop(bt) - ARROW / 2, lit)
        Arrow(tree, "down", x, CellTop(bt), lit)
    elseif pt == bt then
        local y = CellTop(bt) + half
        if pc < bc then
            HLine(tree, y, CellLeft(pc) + BTN, CellLeft(bc) - ARROW / 2, lit)
            Arrow(tree, "right", CellLeft(bc), y, lit)
        else
            HLine(tree, y, CellLeft(bc) + BTN + ARROW / 2, CellLeft(pc), lit)
            Arrow(tree, "left", CellLeft(bc) + BTN, y, lit)
        end
    else
        local lo, hi = math.min(pc, bc), math.max(pc, bc)
        local blocked = false
        for i = lo, hi do
            if i ~= pc and tree.occ[OccKey(pt, i)] then blocked = true end
        end
        if not blocked then
            local y, x = CellTop(pt) + half, CellLeft(bc) + half
            if pc < bc then
                HLine(tree, y, CellLeft(pc) + BTN, x + LINE / 2, lit)
            else
                HLine(tree, y, x - LINE / 2, CellLeft(pc), lit)
            end
            VLine(tree, x, y - LINE / 2, CellTop(bt) - ARROW / 2, lit)
            Arrow(tree, "down", x, CellTop(bt), lit)
        else
            local x, y = CellLeft(pc) + half, CellTop(bt) + half
            VLine(tree, x, CellTop(pt) + BTN, y + LINE / 2, lit)
            if pc < bc then
                HLine(tree, y, x - LINE / 2, CellLeft(bc) - ARROW / 2, lit)
                Arrow(tree, "right", CellLeft(bc), y, lit)
            else
                HLine(tree, y, CellLeft(bc) + BTN + ARROW / 2, x + LINE / 2, lit)
                Arrow(tree, "left", CellLeft(bc) + BTN, y, lit)
            end
        end
    end
end

-- TalentFrame_SetPrereqs: the requirement goes unmet at the first
-- prerequisite that is not learnable, and every line from there on is
-- drawn unlit. Varargs walked with select() because the flags can be
-- nil - a table built from them would have holes.
local function WalkPrereqs(tree, bt, bc, met, forceDesat, preview, ...)
    for k = 1, select("#", ...), 4 do
        local pt, pc, learnable, previewLearnable = select(k, ...)
        if forceDesat or (preview and not previewLearnable) or (not preview and not learnable) then
            met = false
        end
        if pt and pc then DrawPrereq(tree, bt, bc, pt, pc, met) end
    end
    return met
end

-- ============================================================
-- TALENT BUTTONS
-- ============================================================
local function TalentTooltip(self)
    if not self.tab then return end
    local group, pet = ViewedSpec()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- Blizzard's own call (PlayerTalentFrameTalent_OnEnter).
    if self.talentID and self.talentID ~= 0 then
        GameTooltip:SetTalent(self.talentID, false, pet, group)
    else
        pcall(GameTooltip.SetTalent, GameTooltip, self.tab, self.index, false, pet, group)
    end
    self.UpdateTooltip = TalentTooltip
end

local function TalentClick(self, button)
    if not self.tab then return end
    local group, pet, spec = ViewedSpec()
    local tab, id = self.tab, self.index
    -- Same order and calls as PlayerTalentFrameTalent_OnClick.
    if IsModifiedClick("CHATLINK") then
        local link = GetTalentLink and GetTalentLink(tab, id, false, pet, group, IsPreview())
        local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if link and insert then insert(link) end
        return
    end
    if not CanEdit(group, pet, spec) then return end
    if button == "LeftButton" then
        if IsPreview() then
            if AddPreviewTalentPoints then AddPreviewTalentPoints(tab, id, 1, pet, group) end
        elseif LearnTalent then
            LearnTalent(tab, id, pet, group)
        end
    elseif button == "RightButton" and IsPreview() and AddPreviewTalentPoints then
        AddPreviewTalentPoints(tab, id, -1, pet, group)
    end
end

local function NewTalentButton(tree)
    local b = CreateFrame("Button", nil, tree.grid)
    b:SetSize(BTN, BTN)
    b:SetFrameLevel(tree.grid:GetFrameLevel() + 3)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    b.icon = Kit.Icon(b, BTN)
    b.icon:SetAllPoints()

    -- The rank plate, inside the icon's corner so no line can run under it.
    local badge = CreateFrame("Frame", nil, b)
    badge:SetSize(24, 12)
    badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    badge:SetFrameLevel(b.icon:GetFrameLevel() + 2)
    UI.Fill(badge, "ui", "elementBg")
    UI.Border(badge, "ui", "border")
    badge._zPaint = UI.PaintBox
    badge:_zPaint()
    badge.text = UI.Font(badge, F.SMALL, { justify = "CENTER" })
    badge.text:SetPoint("CENTER", 0, 0)
    badge.text:SetWordWrap(false)
    b.badge = badge

    -- Hover is gold (house rule); the state colour comes back on leave.
    b:SetScript("OnEnter", function(self)
        self.icon._zBorderCat, self.icon._zBorderKey = "ui", "accent"
        self.icon:_zPaint()
        TalentTooltip(self)
    end)
    b:SetScript("OnLeave", function(self)
        self.icon._zBorderCat, self.icon._zBorderKey = self._zStateCat or "ui", self._zStateKey or "border"
        self.icon:_zPaint()
        self.UpdateTooltip = nil
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", TalentClick)
    return b
end

local function PaintTalent(b, info, lit, displayRank)
    b.icon:SetIcon(info.icon)
    local cat, key
    if lit then
        b.icon:SetDesaturated(false)
        b.icon.texture:SetAlpha(1)
        if displayRank < (info.maxRank or 0) then
            -- Room to spend: green, like Blizzard's green slot.
            cat, key = "text", "green"
            SetTextKey(b.badge.text, "text", "green")
        else
            -- Maxed: the "selected" ring, white rank.
            cat, key = "ui", "borderSelected"
            SetTextKey(b.badge.text, "text", "normal")
        end
        b.badge:Show()
    else
        b.icon:SetDesaturated(true)
        b.icon.texture:SetAlpha(0.55)
        cat, key = "ui", "border"
        SetTextKey(b.badge.text, "text", "disabled")
        -- Blizzard hides the rank of a locked talent with no points in it.
        b.badge:SetShown((info.rank or 0) > 0)
    end
    b.badge.text:SetText(displayRank .. "/" .. (info.maxRank or 0))
    b._zStateCat, b._zStateKey = cat, key
    if not b:IsMouseOver() then SetBorderKey(b.icon, cat, key) end
end

-- ============================================================
-- TREES
-- ============================================================
local ART = {   -- Blizzard's four background quadrants (texcoords from the XML)
    { "TopLeft",     0, 1,      0, 1,         256, 256 },
    { "TopRight",    0, 0.6875, 0, 1,          44, 256 },
    { "BottomLeft",  0, 1,      0, 0.5859375, 256,  75 },
    { "BottomRight", 0, 0.6875, 0, 0.5859375,  44,  75 },
}

local function LayoutArt(tree)
    -- The composite is 300 x 331; scaled as ONE image so the seams meet.
    local w, h = TREE_W - 2, GridH() - 2
    local sx, sy = w / 300, h / 331
    local tl, tr, bl, br = tree.art[1], tree.art[2], tree.art[3], tree.art[4]
    tl:ClearAllPoints(); tl:SetPoint("TOPLEFT", tree.grid, "TOPLEFT", 1, -1)
    tl:SetSize(256 * sx, 256 * sy)
    tr:ClearAllPoints(); tr:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
    tr:SetSize(44 * sx, 256 * sy)
    bl:ClearAllPoints(); bl:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
    bl:SetSize(256 * sx, 75 * sy)
    br:ClearAllPoints(); br:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT", 0, 0)
    br:SetSize(44 * sx, 75 * sy)
end

local function BuildTree(index)
    local tree = CreateFrame("Frame", nil, win)
    tree:SetSize(TREE_W, TreeH())
    tree:SetPoint("TOPLEFT", win, "TOPLEFT",
        Kit.PAD + (index - 1) * (TREE_W + Kit.GAP), -TreesTop())
    UI.Fill(tree, "ui", "cardBg")
    UI.Border(tree, "ui", "border")
    tree._zPaint = UI.PaintBox
    tree:_zPaint()
    tree.tab = index

    local header = CreateFrame("Frame", nil, tree)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    UI.Fill(header, "ui", "headerBg")
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    header._zPaint = function(self)
        local h = GetColor("ui", "headerBg")
        self._zFill:SetVertexColor(h.r, h.g, h.b, h.a or 1)
        local b = GetColor("ui", "border")
        rule:SetVertexColor(b.r, b.g, b.b, b.a or 1)
    end
    header:_zPaint()

    local icon = header:CreateTexture(nil, "ARTWORK")
    icon._zui_own = true
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    SharpenIcon(icon)
    tree.icon = icon

    tree.points = UI.Font(header, F.CARD, { justify = "RIGHT" })
    tree.points:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    tree.points:SetWordWrap(false)

    tree.name = UI.Font(header, F.CARD, { justify = "LEFT", cat = "text", key = "gold" })
    tree.name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    tree.name:SetPoint("RIGHT", tree.points, "LEFT", -6, 0)
    tree.name:SetWordWrap(false)

    local grid = CreateFrame("Frame", nil, tree)
    grid:SetPoint("TOPLEFT", tree, "TOPLEFT", 0, -HEADER_H)
    grid:SetPoint("BOTTOMRIGHT", tree, "BOTTOMRIGHT", 0, 0)
    tree.grid = grid

    -- The tree's painted art, dimmed well down under the grid.
    tree.art = {}
    for i, a in ipairs(ART) do
        local t = grid:CreateTexture(nil, "BACKGROUND", nil, -6)
        t._zui_own = true
        t:SetTexCoord(a[2], a[3], a[4], a[5])
        t:SetAlpha(0.3)
        tree.art[i] = t
    end
    LayoutArt(tree)

    local lines = CreateFrame("Frame", nil, grid)
    lines:SetAllPoints(grid)
    lines:SetFrameLevel(grid:GetFrameLevel() + 1)
    tree.lines = lines

    tree.buttons, tree.lineTex, tree.arrowTex, tree.nButtons = {}, {}, {}, 0
    tree.used = { lineTex = 0, arrowTex = 0 }
    tree.occ, tree.infos = {}, {}
    return tree
end

-- One tree, mirroring TalentFrame_Update for the viewed spec. Returns the
-- deepest tier it holds (for the window height) and its points.
local function UpdateTree(tree, ctx)
    local tab = tree.tab
    if tab > ctx.numTabs then
        tree:Hide()
        return 0, 0
    end
    tree:Show()

    local name, icon, spent, background, previewSpent = TabInfo(tab, ctx.pet, ctx.group)
    local tabPoints = spent + previewSpent
    tree.name:SetText(name or "")
    tree.icon:SetTexture(icon)
    tree.icon:SetShown(icon ~= nil)
    tree.points:SetText(tabPoints)
    SetTextKey(tree.points, "text", previewSpent > 0 and "green" or "normal")

    for i, t in ipairs(tree.art) do
        if background then
            t:SetTexture("Interface\\TalentFrame\\" .. background .. "-" .. ART[i][1])
            -- Blizzard greys the art of the spec you are not using.
            t:SetDesaturated(not ctx.isActiveGroup)
            t:Show()
        else
            t:Hide()
        end
    end

    local n = (GetNumTalents and GetNumTalents(tab, false, ctx.pet)) or 0
    wipe(tree.occ)
    wipe(tree.infos)
    local deepest = 0
    for i = 1, n do
        local info = TalentInfo(tab, i, ctx.pet, ctx.group)
        if info and info.tier and info.column then
            tree.infos[i] = info
            tree.occ[OccKey(info.tier, info.column)] = true
            if info.tier > deepest then deepest = info.tier end
        end
    end

    tree.used.lineTex, tree.used.arrowTex = 0, 0
    local perTier = ctx.pet and (PET_TALENTS_PER_TIER or 3) or (PLAYER_TALENTS_PER_TIER or 5)
    for i = 1, n do
        local info = tree.infos[i]
        local b = tree.buttons[i]
        if info then
            if not b then
                b = NewTalentButton(tree)
                tree.buttons[i] = b
                if i > tree.nButtons then tree.nButtons = i end
            end
            b.tab, b.index, b.talentID = tab, i, info.talentID
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", tree.grid, "TOPLEFT", CellLeft(info.column), -CellTop(info.tier))

            local displayRank = (ctx.preview and info.previewRank or info.rank) or 0
            -- No points to spend, or not the active spec: only talents
            -- with points in them stay lit.
            local forceDesat = (ctx.unspent <= 0 or not ctx.isActiveGroup) and displayRank == 0
            local tierUnlocked = (info.tier - 1) * perTier <= tabPoints
            local met = tierUnlocked and not forceDesat
            if GetTalentPrereqs then
                met = WalkPrereqs(tree, info.tier, info.column, met, forceDesat, ctx.preview,
                    GetTalentPrereqs(tab, i, false, ctx.pet, ctx.group))
            end
            local lit = met and ((ctx.preview and info.meetsPreviewPrereq)
                or (not ctx.preview and info.meetsPrereq)) and true or false
            PaintTalent(b, info, lit, displayRank)
            b:Show()
            if GameTooltip:IsOwned(b) then TalentTooltip(b) end
        elseif b then
            b.tab = nil
            b:Hide()
        end
    end
    -- nButtons, not #buttons: a talent index with no info leaves a hole.
    for i = n + 1, tree.nButtons do
        local b = tree.buttons[i]
        if b then
            b.tab = nil
            b:Hide()
        end
    end
    for i = tree.used.lineTex + 1, #tree.lineTex do tree.lineTex[i]:Hide() end
    for i = tree.used.arrowTex + 1, #tree.arrowTex do tree.arrowTex[i]:Hide() end
    return deepest, tabPoints
end

-- ============================================================
-- SPEC TABS / ACTIVATE / PREVIEW BUTTONS
-- ============================================================
local function SpecLabel(entry)
    local label = entry.spec.name or entry.key
    if IsSpecActive(entry.spec) and NumGroups(false) > 1 then
        label = label .. " (Active)"
    end
    return label
end

-- The tab icon Blizzard picks (PlayerSpecTab_Update): the primary tree,
-- else the hybrid icon, else the spec's default / the unit's portrait.
local function PaintSpecIcon(entry)
    local spec = entry.spec
    local pts, _, icons, n, total = SpecPoints(spec.pet, spec.talentGroup)
    local primary = PrimaryTab(pts, n)
    local tex = entry.icon
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if primary > 0 and icons[primary] then
        tex:SetTexture(icons[primary])
    elseif n > 1 and total > 0 and TALENT_HYBRID_ICON then
        tex:SetTexture(TALENT_HYBRID_ICON)
    elseif spec.defaultSpecTexture then
        tex:SetTexture(spec.defaultSpecTexture)
    elseif spec.portraitUnit and SetPortraitTexture then
        tex:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(tex, spec.portraitUnit)
    else
        tex:SetTexture(nil)
    end
end

-- PlayerSpecTab_OnEnter, in the palette.
local function SpecTooltip(entry, owner)
    local spec = entry.spec
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local t = GetColor("tooltip", "title")
    if NumGroups(true) <= 1 and NumGroups(false) <= 1 then
        GameTooltip:AddLine(UnitName(spec.unit or "player") or spec.name or "", t.r, t.g, t.b)
    else
        GameTooltip:AddLine(spec.tooltip or spec.name or "", t.r, t.g, t.b)
        if IsSpecActive(spec) then
            local g = GetColor("text", "green")
            GameTooltip:AddLine(TALENT_ACTIVE_SPEC_STATUS or "Active", g.r, g.g, g.b)
        end
    end
    local pts, names, _, n = SpecPoints(spec.pet, spec.talentGroup)
    local primary = PrimaryTab(pts, n)
    local body = GetColor("tooltip", "body")
    local green = GetColor("text", "green")
    for tab = 1, n do
        if names[tab] then
            local c = (tab == primary) and green or body
            GameTooltip:AddDoubleLine(names[tab], pts[tab], body.r, body.g, body.b, c.r, c.g, c.b, 1)
        end
    end
    GameTooltip:Show()
end

local function BlizzSpecTab(key, i)
    local f = TalentUIUtil and TalentUIUtil.GetSpecTab and TalentUIUtil.GetSpecTab(key)
    if f then return f end
    f = _G["PlayerSpecTab" .. i]
    if f and f.specIndex == key then return f end
    return nil
end

local function BuildSpecTabs()
    local specs = TALENT_UI_SPECS
    if not specs then return end
    for i, key in ipairs(SPEC_ORDER) do
        local spec = specs[key]
        local target = spec and BlizzSpecTab(key, i)
        if target then
            local entry = { key = key, spec = spec }
            local v = UI.Button(win, spec.name or key, { height = Kit.TAB_H, size = F.LABEL })
            local icon = v:CreateTexture(nil, "ARTWORK", nil, 1)
            icon._zui_own = true
            icon:SetSize(16, 16)
            icon:SetPoint("LEFT", 4, 0)
            SharpenIcon(icon)
            entry.icon = icon
            v._zText:ClearAllPoints()
            v._zText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            v._zText:SetPoint("RIGHT", v, "RIGHT", -6, 0)
            v._zText:SetJustifyH("LEFT")
            v._zText:SetWordWrap(false)
            -- Sized once for the longer "(Active)" label: widths are frozen
            -- in combat, and a spec can only change out of it anyway.
            v._zText:SetText((spec.name or key) .. " (Active)")
            local w = math.ceil(v._zText:GetStringWidth()) + 4 + 16 + 5 + 10
            v:SetWidth(math.max(90, math.min(190, w)))
            v._zText:SetText(spec.name or key)
            v:Hide()
            entry.visual = v
            SecureOverlay(v, target, function(self) SpecTooltip(entry, self) end)
            specTabs[#specTabs + 1] = entry
        end
    end
end

local function BuildActions()
    local blizzActivate = _G.PlayerTalentFrameActivateButton
    if blizzActivate then
        activate = UI.Button(win, TALENT_SPEC_ACTIVATE or "Activate", { height = Kit.TAB_H, size = F.LABEL })
        activate:SetWidth(math.max(80, math.ceil(activate._zText:GetStringWidth()) + 22))
        activate:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, win.top)
        activate:Hide()
        SecureOverlay(activate, blizzActivate, function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local t = GetColor("tooltip", "title")
            GameTooltip:AddLine(TALENT_SPEC_ACTIVATE or "Activate", t.r, t.g, t.b)
            local c = GetColor("tooltip", "body")
            GameTooltip:AddLine("Switch to the spec you are viewing. Not possible in combat.", c.r, c.g, c.b, true)
            GameTooltip:Show()
        end)
    end

    local blizzReset, blizzLearn = _G.PlayerTalentFrameResetButton, _G.PlayerTalentFrameLearnButton
    if blizzReset and blizzLearn then
        resetBtn = UI.Button(win, RESET or "Reset", { height = 24, width = 80 })
        resetBtn:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
        resetBtn:SetFrameLevel(win.footer:GetFrameLevel() + 2)
        resetBtn:Hide()
        SecureOverlay(resetBtn, blizzReset, function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TALENT_TOOLTIP_RESETTALENTGROUP or "Reset the preview points.")
        end)

        -- Blizzard's Learn opens its own CONFIRM_LEARN_PREVIEW_TALENTS popup.
        learnBtn = UI.Button(win, LEARN or "Learn", { height = 24, width = 80 })
        learnBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
        learnBtn:SetFrameLevel(win.footer:GetFrameLevel() + 2)
        learnBtn:Hide()
        SecureOverlay(learnBtn, blizzLearn, function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TALENT_TOOLTIP_LEARNTALENTGROUP or "Learn the previewed talents.")
        end)
    end
end

local function ActivationCasting(group)
    local spells = TALENT_ACTIVATION_SPELLS
    local id = spells and spells[group]
    if not id then return false end
    if C_Spell and C_Spell.IsCurrentSpell then return C_Spell.IsCurrentSpell(id) and true or false end
    if IsCurrentSpell then return IsCurrentSpell(id) and true or false end
    return false
end

-- Paint only - safe in combat.
local function PaintActivate()
    if not activate then return end
    local group, pet, spec = ViewedSpec()
    local off = InCombatLockdown() or pet or IsSpecActive(spec) or ActivationCasting(group)
    PaintDisabled(activate, off)
end

local function PaintControls(ctx)
    for _, e in ipairs(specTabs) do
        e.visual:SetActive(TalentUIUtil and TalentUIUtil.IsSpecSelected
            and TalentUIUtil.IsSpecSelected(e.key) and true or false)
        e.visual:SetLabel(SpecLabel(e))
        PaintSpecIcon(e)
    end
    PaintActivate()
    if learnBtn then
        local on = ctx.preview and ctx.canEdit and ctx.pending > 0
        PaintDisabled(learnBtn, not on)
        PaintDisabled(resetBtn, not on)
    end
end

-- Everything that shows, hides or moves a secure button. Out of combat
-- only; a fight queues it for PLAYER_REGEN_ENABLED.
local function LayoutSecure(ctx, deepest)
    if InCombatLockdown() then
        win._zLayoutPending = true
        return
    end
    win._zLayoutPending = nil

    -- PlayerTalentFrame_UpdateSpecs: a tab per talent group that exists,
    -- and no tabs at all when there would only be one.
    local numGroups, numPetGroups = NumGroups(false), NumGroups(true)
    local shown = {}
    for _, e in ipairs(specTabs) do
        local canShow
        if e.spec.pet then
            canShow = (e.spec.talentGroup or 1) <= numPetGroups
        else
            canShow = (e.spec.talentGroup or 1) <= numGroups
        end
        if canShow then shown[#shown + 1] = e end
    end
    if #shown <= 1 then shown = {} end
    -- SetShown per tab, not hide-all-then-show: a tab hidden and re-shown
    -- under the mouse drops its tooltip on every redraw.
    local want = {}
    for _, e in ipairs(shown) do want[e] = true end
    for _, e in ipairs(specTabs) do e.visual:SetShown(want[e] and true or false) end
    local last
    for _, e in ipairs(shown) do
        local v = e.visual
        v:ClearAllPoints()
        if last then
            -- A wider gap between your specs and the pet's, as Blizzard does.
            local gap = (last.spec.pet ~= e.spec.pet) and 12 or 3
            v:SetPoint("LEFT", last.visual, "RIGHT", gap, 0)
        else
            v:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, win.top)
        end
        last = e
    end

    if activate then
        activate:SetShown(numGroups > 1 and not ctx.pet and not ctx.isActiveSpec)
    end
    if learnBtn then
        -- PlayerTalentFrame_UpdateControls' preview bar condition.
        local bar = ctx.preview and ctx.canEdit and ctx.points > 0
        learnBtn:SetShown(bar)
        resetBtn:SetShown(bar)
    end

    statusText:ClearAllPoints()
    if last then
        statusText:SetPoint("LEFT", last.visual, "RIGHT", Kit.GAP * 2, 0)
    else
        statusText:SetPoint("LEFT", specRow, "LEFT", 0, 0)
    end
    if activate and activate:IsShown() then
        statusText:SetPoint("RIGHT", activate, "LEFT", -Kit.GAP, 0)
    else
        statusText:SetPoint("RIGHT", specRow, "RIGHT", 0, 0)
    end

    -- A tree deeper than Era's seven tiers grows the window (never shrinks
    -- below seven, so it does not jump about between specs).
    local needTiers = math.max(MIN_TIERS, deepest or 0)
    if needTiers ~= tiers then
        tiers = needTiers
        coverOpts.height = WindowHeight()
        win.Reanchor()
        for _, tree in ipairs(trees) do
            tree:SetHeight(TreeH())
            LayoutArt(tree)
        end
    end
end

-- ============================================================
-- REFRESH
-- ============================================================
local function StatusLine(ctx)
    if ctx.numTabs == 0 then return "", "gray" end
    if ctx.pet then return UnitName("pet") or (PET or "Pet"), "normal" end
    if NumGroups(false) > 1 and not ctx.isActiveSpec then
        return "Viewing your inactive spec - activate it to spend points here.", "gray"
    end
    if ctx.preview then
        return "Click: preview a point  |  Right-click: remove it  |  Shift-click: link", "gray"
    end
    return "Click: learn  |  Shift-click: link", "gray"
end

local function Refresh()
    if not win or not win:IsVisible() then return end
    local group, pet, spec = ViewedSpec()
    local unspent, points, pending = Unspent(pet, group)
    local ctx = {
        group = group, pet = pet, spec = spec,
        preview = IsPreview(),
        isActiveGroup = (group == ActiveGroup(pet)),
        isActiveSpec = IsSpecActive(spec) and true or false,
        canEdit = CanEdit(group, pet, spec) and true or false,
        unspent = unspent, points = points, pending = pending,
        numTabs = math.min(3, NumTabs(pet)),
    }

    local deepest = 0
    local parts = {}
    for i, tree in ipairs(trees) do
        local d, tabPoints = UpdateTree(tree, ctx)
        if d > deepest then deepest = d end
        if i <= ctx.numTabs then parts[#parts + 1] = tostring(tabPoints) end
    end
    emptyText:SetShown(ctx.numTabs == 0)

    -- Title: the spec's name when there is more than one (Blizzard's
    -- PlayerTalentFrame_PostUpdateActiveSpec), with its primary tree's icon.
    if spec and NumGroups(false) > 1 then
        win:SetTitle(spec.name or (TALENTS or "Talents"))
    else
        win:SetTitle(TALENTS or "Talents")
    end
    -- SetIcon shows / hides a texture and re-anchors the title inside the
    -- protected cover: out of combat only (a spec can not change in one).
    if not InCombatLockdown() then
        local pts, _, icons, n = SpecPoints(pet, group)
        local primary = PrimaryTab(pts, n)
        win:SetIcon(primary > 0 and icons[primary] or nil)
    end

    local text, key = StatusLine(ctx)
    statusText:SetText(text)
    SetTextKey(statusText, "text", key)

    local label = UNSPENT_TALENT_POINTS and string.format(UNSPENT_TALENT_POINTS, tostring(unspent))
        or ("Unspent points: " .. unspent)
    if pending > 0 then label = label .. "  (" .. pending .. " previewed)" end
    unspentText:SetText(label)
    SetTextKey(unspentText, "text", unspent > 0 and "green" or "normal")
    summaryText:SetText(table.concat(parts, " / "))

    PaintControls(ctx)
    LayoutSecure(ctx, deepest)
end

Queue = Kit.Coalesce(Refresh, function() return win end)

-- ============================================================
-- BUILD
-- ============================================================
local function Build()
    if win then return win end
    coverOpts = {
        name = "ZacUITalentWindow",
        title = TALENTS or "Talents",
        insetName = "PlayerTalentFrame",
        width = WindowWidth(),
        height = WindowHeight(),
        onClose = function() HideUIPanel(PlayerTalentFrame) end,
    }
    win = Kit.Cover(PlayerTalentFrame, coverOpts)

    -- The spec row holds only insecure text; the secure tabs and Activate
    -- are the window's own children, so this frame never becomes
    -- protected and can be redrawn in combat.
    specRow = CreateFrame("Frame", nil, win)
    specRow:SetHeight(Kit.TAB_H)
    specRow:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, win.top)
    specRow:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, win.top)
    statusText = UI.Font(specRow, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    statusText:SetPoint("LEFT", specRow, "LEFT", 0, 0)
    statusText:SetPoint("RIGHT", specRow, "RIGHT", 0, 0)
    statusText:SetWordWrap(false)

    win.footer = Kit.Footer(win, Kit.FOOTER_H)
    unspentText = UI.Font(win.footer, F.LABEL, { justify = "LEFT" })
    unspentText:SetPoint("LEFT", win.footer, "LEFT", 8, 0)
    unspentText:SetWordWrap(false)
    summaryText = UI.Font(win.footer, F.CARD, { justify = "CENTER" })
    summaryText:SetPoint("CENTER", win.footer, "CENTER", 0, 0)
    summaryText:SetWordWrap(false)

    for i = 1, 3 do trees[i] = BuildTree(i) end

    emptyText = UI.Font(win, F.LABEL, { cat = "text", key = "gray", justify = "CENTER" })
    emptyText:SetPoint("CENTER", win, "CENTER", 0, 0)
    emptyText:SetText("No talents to show yet.")
    emptyText:Hide()

    BuildSpecTabs()
    BuildActions()

    local ev = CreateFrame("Frame", nil, win)
    -- All registered by Blizzard's PlayerTalentFrame_OnLoad on this client.
    ev:RegisterEvent("PLAYER_TALENT_UPDATE")
    ev:RegisterEvent("PET_TALENT_UPDATE")
    ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    ev:RegisterEvent("PREVIEW_TALENT_POINTS_CHANGED")
    ev:RegisterEvent("PREVIEW_PET_TALENT_POINTS_CHANGED")
    ev:RegisterEvent("PLAYER_LEVEL_UP")
    ev:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterUnitEvent("UNIT_PET", "player")
    -- Not registered by the 1.15 talent UI: an unknown event is an error,
    -- so these go through pcall.
    pcall(ev.RegisterEvent, ev, "CHARACTER_POINTS_CHANGED")
    pcall(ev.RegisterEvent, ev, "CVAR_UPDATE")
    ev:SetScript("OnEvent", function(_, event)
        if event == "CURRENT_SPELL_CAST_CHANGED" or event == "PLAYER_REGEN_DISABLED" then
            if win:IsVisible() then PaintActivate() end
            return
        end
        if event == "PLAYER_REGEN_ENABLED" then
            -- Anything that had to wait for the fight lands now.
            if win._zLayoutPending or win:IsVisible() then Queue() end
            return
        end
        Queue()
    end)
    win:HookScript("OnShow", Queue)

    -- THE X, SECURELY. Our secure children make PlayerTalentFrame a
    -- protected frame, so an addon's HideUIPanel on it is refused in
    -- combat; clicking Blizzard's own close button from a secure button
    -- runs their handler with their credentials instead.
    local blizzClose = _G.PlayerTalentFrameCloseButton
    if blizzClose then
        local sx = CreateFrame("Button", nil, win.titleBar, "SecureActionButtonTemplate")
        sx:SetAllPoints(win.closeButton)
        sx:SetFrameLevel(win.closeButton:GetFrameLevel() + 2)
        sx:SetAttribute("useOnKeyDown", false)
        sx:RegisterForClicks("AnyUp")
        sx:SetAttribute("type", "click")
        sx:SetAttribute("clickbutton", blizzClose)
        local x = win.closeButton
        sx:SetScript("OnEnter", function() x._zHot = true; x:_zPaint() end)
        sx:SetScript("OnLeave", function() x._zHot = nil; x:_zPaint() end)
        x:EnableMouse(false)
    end
    return win
end

-- Blizzard's pieces. The art corners and the portrait poke a few pixels
-- past the cover's top-left; the Close button (Vanilla keeps it) is
-- frameStrata HIGH and would draw OVER the cover; the rest sits under it
-- but is faded anyway so nothing can ghost through a gap: the tree tabs
-- along the bottom, the spec tabs down the right edge, the title-bar X,
-- the Activate / status / preview bars.
local function BlizzardLeftovers()
    local t = {}
    for i = 1, 4 do t[#t + 1] = _G["PlayerTalentFrameTab" .. i] end
    for i = 1, 3 do t[#t + 1] = _G["PlayerSpecTab" .. i] end
    for _, n in ipairs({ "Portrait", "TopLeft", "TopRight", "BottomLeft", "BottomRight",
                         "CloseButton", "CancelButton", "ActivateButton", "StatusFrame",
                         "PreviewBar", "PointsBar", "TitleText" }) do
        t[#t + 1] = _G["PlayerTalentFrame" .. n]
    end
    return t
end

-- Kit.Silence is written for frames: it also turns their mouse off, and
-- Unsilence turns it back ON - which on a plain texture or FontString
-- (the portrait, the art corners, the title) would make it start
-- catching the mouse. Regions only fade; frames go through the kit.
-- Kit.Silence fades textures and frames alike (a texture has no mouse
-- to take away), remembering each piece's own alpha and mouse state.
local Quiet, Unquiet = Kit.Silence, Kit.Unsilence


function Apply()
    if not PlayerTalentFrame then return end
    -- Building, showing or hiding the cover touches secure buttons.
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    if Enabled() then
        Build()
        win.Reanchor()
        win:Show()
        Quiet(BlizzardLeftovers())
        Queue()
    elseif win then
        win:Hide()
        Unquiet(BlizzardLeftovers())
    end
end

-- ============================================================
-- MODULE
-- ============================================================
-- Hooked once, when Blizzard_TalentUI is up. NOT through ns.RegisterLoD:
-- its registry holds ONE function per addon name, and the "panels"
-- module already parks the talent skin there - a second registration
-- would silently replace it.
local function OnTalentUILoaded()
    if hooked or not PlayerTalentFrame then return end
    hooked = true
    -- A build or toggle refused in combat (Apply sets pendingApply) runs
    -- when it ends. Its own frame: the window's may not exist yet.
    local regen = CreateFrame("Frame")
    regen:RegisterEvent("PLAYER_REGEN_ENABLED")
    regen:SetScript("OnEvent", function()
        if pendingApply then
            pendingApply = false
            Apply()
        end
    end)
    PlayerTalentFrame:HookScript("OnShow", function()
        Apply()
        -- Blizzard re-shows its tabs on every update; keep them quiet.
        if win and win:IsShown() then Quiet(BlizzardLeftovers()) end
    end)
    -- Blizzard's spec switch (our tabs click theirs) and its own redraws.
    if PlayerSpecTab_OnClick then hooksecurefunc("PlayerSpecTab_OnClick", function() Queue() end) end
    if PlayerTalentFrame_Refresh then hooksecurefunc("PlayerTalentFrame_Refresh", function() Queue() end) end
    Apply()
end

Modules.talentswin = function()
    if ns._zTalentsWin then return end
    ns._zTalentsWin = true
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded("Blizzard_TalentUI") then
        OnTalentUILoaded()
        return
    end
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("ADDON_LOADED")
    watch:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_TalentUI" then
            self:UnregisterEvent("ADDON_LOADED")
            OnTalentUILoaded()
        end
    end)
end
