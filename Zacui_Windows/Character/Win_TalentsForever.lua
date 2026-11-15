-- Win_TalentsForever - ZacUI's talent window on WoW Forever: the three
-- Classic trees side by side, drawn from Forever's new talent data, the
-- way Win_Talents draws them on Classic Era.
-- Part of ZacUI; load order is set by the TOC (after Win_Talents).
--
-- WHAT FOREVER HAS. Forever's talents are the vanilla trees, but the
-- client keeps them the modern way: one "trait tree" per class, holding a
-- node per talent, with one trait group per vanilla tree (Arms, Fury,
-- Protection). The window that shows them is PlayerSpellsFrame (addon
-- Blizzard_PlayerSpells, load on demand), whose TalentsFrame page draws
-- the three trees in Forever's own art. Every call below is named in
-- Forever's own API documentation (Gethe/wow-ui-source, branch "forever",
-- Blizzard_APIDocumentationGenerated: SharedTraitsDocumentation,
-- ClassTalentsDocumentation, SpecializationInfoDocumentation) and used the
-- same way by Forever's own talent page (Blizzard_PlayerSpells/Camelot/
-- ClassTalents/Blizzard_ClassTalentsFrame.lua, read 2026-11-07):
--   C_ClassTalents.GetActiveConfigID     the config you are wearing
--   C_Traits.GetConfigInfo(id).treeIDs[1] its tree
--   C_Traits.GetGroupDisplayInfoByTreeID  one entry per vanilla tree:
--                                         groupID, displayName, icon,
--                                         skillLineID, orderIndex
--   C_Traits.GetGroupCurrencyInfo         points spent in each tree
--   C_Traits.GetTreeCurrencyInfo          points left to spend
--   C_Traits.GetTreeNodes / GetNodeInfo   the talents: posX / posY (tenths
--                                         of a pixel, 63 px apart), ranks,
--                                         canPurchaseRank, visibleEdges
--   C_Traits.GetEntryInfo / GetDefinitionInfo  the spell behind a talent
--   C_Traits.GetTraitDescription          its text at a rank
--   C_Traits.GetConditionInfo             "N points in the tree" gates
-- TREE ORDER: Blizzard lays its headers out in the order the groups come
-- back; ZacUI sorts them by their own orderIndex and keeps the returned
-- order for a tie, so both agree when the client agrees with itself.
--
-- A COVER, AND NOTHING SECURE. The window is a Win_Kit cover hung on
-- PlayerSpellsFrame that shows exactly while the Talents page does, so
-- the talent key, the talent micro button and Escape open and close it
-- through Blizzard's own (secure) code, in combat too: no key is rebound
-- and no Blizzard button is wrapped. It has no secure child, so it never
-- makes the window protected and can be shown or hidden at any time.
-- Blizzard's parts that would draw over it are faded (alpha 0) and made
-- click-through, never hidden, re-parented or written into: what was
-- done to which frame is kept in a weak table of ours.
--
--   Shift-click        link the talent in chat
--   "Game's view"      step aside to Blizzard's page until it next opens
--                      (spec switching and the search live there)

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
-- Forever only: the real client (its talent data and window) and the
-- feature's row (off on Retail - Core_Flavor, classic_book).
if not _G.ZACUI_IS_FOREVER then return end
if ns.FeatureOn and not ns.FeatureOn("classic_book") then return end

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local SharpenIcon = ns.SharpenIcon
local TEX_ARROW = ns.TEX_ARROW
local TEX_ARROWL = ns.TEX_ARROWL
local UI = ns.UI
if not (Kit and Modules and UI) then return end

local M, F = UI.M, UI.F

local CT = {}            -- the public face: ns.ClassicTalents
ns.ClassicTalents = CT

-- ============================================================
-- READING SAFELY
-- ============================================================
-- Nothing here is documented as secret, but a hidden value must never
-- reach a comparison: a secret reads as "not there".
local function Plain(v)
    if v == nil or (ns.IsSecret and ns.IsSecret(v)) then return nil end
    return v
end
local function Num(v, d)
    v = Plain(v)
    if type(v) ~= "number" then return d end
    return v
end
local function Bool(v) return Plain(v) == true end
local function Str(v)
    v = Plain(v)
    return type(v) == "string" and v or nil
end

local function SpellName(id)
    if not id then return nil end
    local S = C_Spell
    if S and S.GetSpellName then
        local ok, n = pcall(S.GetSpellName, id)
        if ok and Str(n) then return n end
    end
    if S and S.GetSpellInfo then
        local ok, i = pcall(S.GetSpellInfo, id)
        if ok and type(i) == "table" and Str(i.name) then return i.name end
    end
    return nil
end

local function SpellIcon(id)
    if not id then return nil end
    local S = C_Spell
    if S and S.GetSpellTexture then
        local ok, t = pcall(S.GetSpellTexture, id)
        if ok and Plain(t) then return t end
    end
    return nil
end

-- ============================================================
-- THE TREES' ART
-- ============================================================
-- The vanilla backgrounds ship in the client (Interface\TalentFrame\
-- <name>-TopLeft and so on). Forever's data names no file, so each tree's
-- skill line picks it; a skill line not listed falls back to the class's
-- trees in order.
local BG_BY_SKILL = {
    [26] = "WarriorArms", [256] = "WarriorFury", [257] = "WarriorProtection",
    [594] = "PaladinHoly", [267] = "PaladinProtection", [184] = "PaladinCombat",
    [50] = "HunterBeastMastery", [163] = "HunterMarksmanship", [51] = "HunterSurvival",
    [253] = "RogueAssassination", [38] = "RogueCombat", [39] = "RogueSubtlety",
    [613] = "PriestDiscipline", [56] = "PriestHoly", [78] = "PriestShadow",
    [375] = "ShamanElementalCombat", [373] = "ShamanEnhancement", [374] = "ShamanRestoration",
    [237] = "MageArcane", [8] = "MageFire", [6] = "MageFrost",
    [355] = "WarlockCurses", [354] = "WarlockSummoning", [593] = "WarlockDestruction",
    [574] = "DruidBalance", [134] = "DruidFeralCombat", [573] = "DruidRestoration",
}
local BG_BY_CLASS = {
    WARRIOR = { "WarriorArms", "WarriorFury", "WarriorProtection" },
    PALADIN = { "PaladinHoly", "PaladinProtection", "PaladinCombat" },
    HUNTER = { "HunterBeastMastery", "HunterMarksmanship", "HunterSurvival" },
    ROGUE = { "RogueAssassination", "RogueCombat", "RogueSubtlety" },
    PRIEST = { "PriestDiscipline", "PriestHoly", "PriestShadow" },
    SHAMAN = { "ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration" },
    MAGE = { "MageArcane", "MageFire", "MageFrost" },
    WARLOCK = { "WarlockCurses", "WarlockSummoning", "WarlockDestruction" },
    DRUID = { "DruidBalance", "DruidFeralCombat", "DruidRestoration" },
}
CT.BG_BY_SKILL, CT.BG_BY_CLASS = BG_BY_SKILL, BG_BY_CLASS

local function Background(tree, classFile)
    local bg = tree.skillLineID and BG_BY_SKILL[tree.skillLineID]
    if bg then return bg end
    local list = classFile and BG_BY_CLASS[classFile]
    return list and list[tree.index] or nil
end

-- ============================================================
-- THE DATA: ONE CONFIG READ INTO THREE TREES
-- ============================================================
-- A talent's spell, name and icon never change: kept per entry (only once
-- the name is known - the spell's text can arrive a moment later).
local defCache = {}

local function Definition(configID, entryID)
    if not entryID then return nil end
    local d = defCache[entryID]
    if d then return d end
    local Tr = C_Traits
    if not (Tr and Tr.GetEntryInfo and Tr.GetDefinitionInfo) then return nil end
    local ok, entry = pcall(Tr.GetEntryInfo, configID, entryID)
    if not ok or type(entry) ~= "table" then return nil end
    local defID = Num(entry.definitionID)
    if not defID then return nil end
    local okD, def = pcall(Tr.GetDefinitionInfo, defID)
    if not okD or type(def) ~= "table" then return nil end
    local spellID = Num(def.spellID)
    d = {
        spellID = spellID,
        name = Str(def.overrideName) or SpellName(spellID),
        icon = Plain(def.overrideIcon) or SpellIcon(spellID),
    }
    if d.name then defCache[entryID] = d end
    return d
end

-- The config you are wearing; nil before level 10 or while it loads.
function CT.ActiveConfig()
    local C = C_ClassTalents
    if not (C and C.GetActiveConfigID) then return nil end
    local ok, id = pcall(C.GetActiveConfigID)
    return ok and Num(id) or nil
end

-- Dual spec: how many, which is in force, and the config each one wears
-- (Forever's talent page: GetNumSpecGroups, C_SpecializationInfo).
function CT.NumSpecGroups()
    local f = _G.GetNumSpecGroups
    if type(f) ~= "function" then return 1 end
    local ok, n = pcall(f)
    n = ok and Num(n) or 1
    return math.max(1, math.min(2, n))
end

function CT.ActiveSpecGroup()
    local S = C_SpecializationInfo
    if not (S and S.GetActiveSpecGroup) then return 1 end
    local ok, g = pcall(S.GetActiveSpecGroup)
    return ok and Num(g, 1) or 1
end

function CT.ConfigForGroup(group)
    if group == CT.ActiveSpecGroup() then return CT.ActiveConfig() end
    local S = C_SpecializationInfo
    if not (S and S.GetCombatConfigIDForSpecGroup) then return nil end
    local ok, id = pcall(S.GetCombatConfigIDForSpecGroup, group)
    return ok and Num(id) or nil
end

-- The smallest step between the positions in use: the grid's pitch (63 px
-- on Forever, 630 in the data's tenths), whatever unit the data uses.
local function Step(values, into)
    table.sort(values)
    for i = 2, #values do
        local d = values[i] - values[i - 1]
        if d > 0.5 and (not into.step or d < into.step) then into.step = d end
    end
end

-- Positions to cells: tier from the top of the whole tree (every vanilla
-- tree starts on tier 1), column from each tree's left edge. A tree with
-- nothing in its first column would start one column late, so its edge is
-- set from the spacing between the other trees when that fits better.
function CT.Layout(model)
    local pitch = {}
    local ys, minY = {}, nil
    for _, n in ipairs(model.nodes) do
        ys[#ys + 1] = n.y
        if not minY or n.y < minY then minY = n.y end
    end
    Step(ys, pitch)
    for _, t in ipairs(model.trees) do
        local xs = {}
        t.minX, t.maxX = nil, nil
        for _, n in ipairs(t.nodes) do
            xs[#xs + 1] = n.x
            if not t.minX or n.x < t.minX then t.minX = n.x end
            if not t.maxX or n.x > t.maxX then t.maxX = n.x end
        end
        Step(xs, pitch)
    end
    local P = pitch.step or 630
    model.pitch = P
    local maxSpan = 0
    for _, t in ipairs(model.trees) do
        t.base = t.minX
        t.span = t.minX and math.floor((t.maxX - t.minX) / P + 0.5) or 0
        if t.span > maxSpan then maxSpan = t.span end
    end
    -- two full trees give the distance from one tree to the next
    local full = {}
    for _, t in ipairs(model.trees) do
        if t.minX and t.span == maxSpan then full[#full + 1] = t end
    end
    if #full >= 2 then
        local a, b = full[1], full[#full]
        local S = (b.base - a.base) / (b.index - a.index)
        for _, t in ipairs(model.trees) do
            if t.minX and t.span < maxSpan then
                local guess = a.base + (t.index - a.index) * S
                if guess <= t.minX + P / 2 and (t.maxX - guess) / P <= maxSpan + 0.5 then
                    t.base = guess
                end
            end
        end
    end
    local cols, tiers = 4, 7
    for _, n in ipairs(model.nodes) do
        local t = n.tree
        n.col = math.floor((n.x - (t.base or n.x)) / P + 0.5) + 1
        n.tier = math.floor((n.y - (minY or n.y)) / P + 0.5) + 1
        if n.col > cols then cols = n.col end
        if n.tier > tiers then tiers = n.tier end
    end
    model.cols, model.tiers = math.min(cols, 8), math.min(tiers, 12)
    return model
end

-- One config read into { trees = { tree, ... }, nodes, byID, unspent, ... }.
-- nil when the client has no talent data for it (yet).
function CT.Read(configID)
    local Tr = C_Traits
    if not (configID and Tr and Tr.GetConfigInfo and Tr.GetTreeNodes and Tr.GetNodeInfo) then return nil end
    local okC, cfg = pcall(Tr.GetConfigInfo, configID)
    local treeID = okC and type(cfg) == "table" and type(cfg.treeIDs) == "table" and Num(cfg.treeIDs[1]) or nil
    if not treeID then return nil end
    local model = { configID = configID, treeID = treeID, trees = {}, byGroup = {}, nodes = {}, byID = {},
        unspent = 0, staged = {}, stagedCount = 0 }

    -- the trees, in their own order
    local groups = {}
    if Tr.GetGroupDisplayInfoByTreeID then
        local ok, list = pcall(Tr.GetGroupDisplayInfoByTreeID, treeID)
        if ok and type(list) == "table" then
            for i, g in ipairs(list) do
                local gid = type(g) == "table" and Num(g.groupID)
                if gid then
                    groups[#groups + 1] = { groupID = gid, name = Str(g.displayName) or "", icon = Plain(g.icon),
                        skillLineID = Num(g.skillLineID), order = Num(g.orderIndex, i), listIndex = i }
                end
            end
        end
    end
    table.sort(groups, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.listIndex < b.listIndex
    end)
    local ids = {}
    for i, t in ipairs(groups) do
        if i > 3 then break end
        t.index, t.nodes, t.spent, t.ranks = i, {}, nil, 0
        model.trees[i] = t
        model.byGroup[t.groupID] = t
        ids[#ids + 1] = t.groupID
    end
    if #ids > 0 and Tr.GetGroupCurrencyInfo then
        local ok, infos = pcall(Tr.GetGroupCurrencyInfo, configID, ids)
        if ok and type(infos) == "table" then
            for _, gi in ipairs(infos) do
                local t = type(gi) == "table" and model.byGroup[Num(gi.traitNodeGroupID)]
                local c = t and type(gi.currencyInfos) == "table" and gi.currencyInfos[1]
                if t and type(c) == "table" then t.spent = Num(c.spent) end
            end
        end
    end

    -- points left, and what is picked but not learned yet
    if Tr.GetTreeCurrencyInfo then
        local ok, list = pcall(Tr.GetTreeCurrencyInfo, configID, treeID, false)
        local c = ok and type(list) == "table" and list[1]
        if type(c) == "table" then model.unspent = Num(c.quantity, 0) end
    end
    if Tr.GetStagedChanges then
        local ok, buys = pcall(Tr.GetStagedChanges, configID)
        if ok and type(buys) == "table" then
            for _, id in ipairs(buys) do
                id = Num(id)
                if id then model.staged[id] = true end
            end
        end
    end
    -- the points the picks cost (one per rank on Forever)
    if Tr.GetStagedChangesCost then
        local ok, costs = pcall(Tr.GetStagedChangesCost, configID)
        if ok and type(costs) == "table" then
            local n = 0
            for _, c in ipairs(costs) do n = n + (type(c) == "table" and Num(c.amount, 0) or 0) end
            model.pickedPoints = n
        end
    end
    if Tr.ConfigHasStagedChanges then
        local ok, has = pcall(Tr.ConfigHasStagedChanges, configID)
        model.hasStaged = ok and Bool(has) or false
    end

    -- the talents
    local okN, nodeIDs = pcall(Tr.GetTreeNodes, treeID)
    for _, nodeID in ipairs(okN and type(nodeIDs) == "table" and nodeIDs or {}) do
        local ok, info = pcall(Tr.GetNodeInfo, configID, nodeID)
        if ok and type(info) == "table" and Num(info.ID, 0) ~= 0 and Bool(info.isVisible) then
            local tree
            for _, gid in ipairs(type(info.groupIDs) == "table" and info.groupIDs or {}) do
                tree = tree or model.byGroup[Num(gid)]
            end
            if tree then
                local entryID = type(info.activeEntry) == "table" and Num(info.activeEntry.entryID) or nil
                if not entryID and type(info.entryIDs) == "table" then entryID = Num(info.entryIDs[1]) end
                local def = Definition(configID, entryID) or {}
                local n = {
                    id = nodeID, tree = tree, x = Num(info.posX, 0), y = Num(info.posY, 0),
                    rank = Num(info.currentRank, Num(info.ranksPurchased, 0)),
                    max = Num(info.maxRanks, 0),
                    canBuy = Bool(info.canPurchaseRank), canRefund = Bool(info.canRefundRank),
                    available = Bool(info.isAvailable), edgesMet = Bool(info.meetsEdgeRequirements),
                    entryID = entryID, spellID = def.spellID, name = def.name or "", icon = def.icon,
                    conditionIDs = type(info.conditionIDs) == "table" and info.conditionIDs or nil,
                    edges = {}, from = {}, staged = model.staged[nodeID] or false,
                }
                for _, e in ipairs(type(info.visibleEdges) == "table" and info.visibleEdges or {}) do
                    local to = type(e) == "table" and Num(e.targetNode)
                    if to then n.edges[#n.edges + 1] = { to = to, active = Bool(e.isActive) } end
                end
                if n.staged then
                    model.stagedCount = model.stagedCount + 1
                    tree.staged = true
                end
                tree.ranks = tree.ranks + n.rank
                tree.nodes[#tree.nodes + 1] = n
                model.nodes[#model.nodes + 1] = n
                model.byID[nodeID] = n
            end
        end
    end
    -- the edges both ways (a talent's requirement is the edge into it)
    for _, n in ipairs(model.nodes) do
        for _, e in ipairs(n.edges) do
            local to = model.byID[e.to]
            if to then to.from[#to.from + 1] = { node = n, active = e.active } end
        end
    end
    for _, t in ipairs(model.trees) do
        if t.spent == nil then t.spent = t.ranks end
    end
    return CT.Layout(model)
end

-- ============================================================
-- GEOMETRY
-- ============================================================
-- Close to Blizzard's vanilla spacing (63 px around 37 px buttons), a
-- little bigger: the window is Forever's talent page, 1218 x 708.
-- Every number even, so halves (a button's middle, an arrow's) land on
-- whole pixels.
local GEO = { btn = 44, pitch = 72, gx = 18, gy = 16, header = 34, arrow = 8, line = 2, gap = 14 }
CT.GEO = GEO

local function TreeW(g, cols) return g.gx * 2 + (cols - 1) * g.pitch + g.btn end
local function GridH(g, tiers) return g.gy * 2 + (tiers - 1) * g.pitch + g.btn end
local function TreeH(g, tiers) return g.header + GridH(g, tiers) end
CT.TreeW, CT.TreeH = TreeW, TreeH

-- ============================================================
-- THE LOOK
-- ============================================================
-- ZacUI's own (flat, the art dimmed under the grid, pixel borders, green
-- lines) or the Classic look (the art at full strength, the vanilla
-- button ring and rank plate, gold lines). Read when a tree is painted.
local function IsClassic()
    local L = ns.Look and ns.Look.For and ns.Look.For("windows")
    return L and L.id ~= "zacui" or false, L
end
CT.IsClassic = IsClassic

local RANK_BORDER = "Interface\\TalentFrame\\TalentFrame-RankBorder"
-- ZacUI's own glyph set (Media\Icons), for the footer buttons
local ICONS = (ns.MEDIA or "Interface\\AddOns\\ZacUI\\Media\\") .. "Icons\\"

-- A footer button with one of ZacUI's glyphs before its label, sized to
-- both (never cut short).
local function GlyphButton(parent, glyph, label, tooltip)
    local b = UI.Button(parent, label, { height = 24, width = 60, tooltip = tooltip })
    local t = b:CreateTexture(nil, "ARTWORK", nil, 2)
    t._zui_own = true
    t:SetSize(14, 14)
    t:SetTexture(ICONS .. glyph)
    b.glyph = t
    local fs = b._zText
    fs:ClearAllPoints()
    local w = math.ceil(fs:GetStringWidth() or 0)
    -- glyph, 5 px, label: the pair centred, whole pixels
    local total = 14 + 5 + w
    local left = math.floor((math.max(total + 20, 60) - total) / 2)
    b:SetWidth(math.max(total + 20, 60))
    t:SetPoint("LEFT", b, "LEFT", left, 0)
    fs:SetPoint("LEFT", t, "RIGHT", 5, 0)
    b._zGlyphPaint = function(self)
        local c = GetColor("text", self._zDisabled and "disabled" or "normal")
        t:SetVertexColor(c.r, c.g, c.b, 1)
    end
    b:HookScript("OnEnable", function(self) self:_zGlyphPaint() end)
    b:HookScript("OnDisable", function(self) self:_zGlyphPaint() end)
    b:_zGlyphPaint()
    return b
end
CT.GlyphButton = GlyphButton

-- ============================================================
-- DRAWING: LINES AND ARROWS
-- ============================================================
local function Acquire(view, pool, isArrow)
    view.used[pool] = view.used[pool] + 1
    local list = view[pool]
    local t = list[view.used[pool]]
    if not t then
        t = view.lines:CreateTexture(nil, isArrow and "OVERLAY" or "ARTWORK")
        t._zui_own = true
        if not isArrow then t:SetTexture(FLAT) end
        list[#list + 1] = t
    end
    t:ClearAllPoints()
    t:Show()
    return t
end

local function LineColour(view, t, lit)
    local c
    if lit then c = GetColor("text", view.classic and "gold" or "green")
    else c = GetColor("text", "disabled") end
    t:SetVertexColor(c.r, c.g, c.b, lit and 1 or 0.8)
end

local function CellLeft(g, col) return g.gx + (col - 1) * g.pitch end
local function CellTop(g, tier) return g.gy + (tier - 1) * g.pitch end

local function HLine(view, y, xa, xb, lit)
    local g = view.geo
    local t = Acquire(view, "lineTex")
    t:SetPoint("TOPLEFT", view.grid, "TOPLEFT", math.min(xa, xb), -(y - g.line / 2))
    t:SetSize(math.max(1, math.abs(xb - xa)), g.line)
    LineColour(view, t, lit)
end

local function VLine(view, x, ya, yb, lit)
    local g = view.geo
    local t = Acquire(view, "lineTex")
    t:SetPoint("TOPLEFT", view.grid, "TOPLEFT", x - g.line / 2, -math.min(ya, yb))
    t:SetSize(g.line, math.max(1, math.abs(yb - ya)))
    LineColour(view, t, lit)
end

local function Arrow(view, dir, a, b, lit)
    local A = view.geo.arrow
    local t = Acquire(view, "arrowTex", true)
    t:SetSize(A, A)
    if dir == "down" then
        t:SetTexture(TEX_ARROW)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetPoint("TOPLEFT", view.grid, "TOPLEFT", a - A / 2, -(b - A))
    elseif dir == "right" then
        t:SetTexture(TEX_ARROWL)
        t:SetTexCoord(1, 0, 0, 1)
        t:SetPoint("TOPLEFT", view.grid, "TOPLEFT", a - A, -(b - A / 2))
    else
        t:SetTexture(TEX_ARROWL)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetPoint("TOPLEFT", view.grid, "TOPLEFT", a, -(b - A / 2))
    end
    LineColour(view, t, lit)
end

local function OccKey(tier, col) return tier * 16 + col end

-- From a requirement (pt, pc) to the talent it opens (bt, bc), the way the
-- vanilla talent frame routes it: straight down a column, straight along a
-- tier, or along the requirement's tier then down - down its column then
-- across when a talent is in the way.
local function DrawEdge(view, bt, bc, pt, pc, lit)
    local g = view.geo
    local B, A, L = g.btn, g.arrow, g.line
    -- the Classic look's ring stands a few pixels off the button: the
    -- arrow's tip meets the ring, not the icon under it
    local P = view.pad or 0
    local half = B / 2
    if pc == bc then
        if pt == bt then return end
        local x = CellLeft(g, bc) + half
        if pt < bt then
            VLine(view, x, CellTop(g, pt) + B, CellTop(g, bt) - P - A / 2, lit)
            Arrow(view, "down", x, CellTop(g, bt) - P, lit)
        else
            VLine(view, x, CellTop(g, bt) + B, CellTop(g, pt), lit)
        end
    elseif pt == bt then
        local y = CellTop(g, bt) + half
        if pc < bc then
            HLine(view, y, CellLeft(g, pc) + B, CellLeft(g, bc) - P - A / 2, lit)
            Arrow(view, "right", CellLeft(g, bc) - P, y, lit)
        else
            HLine(view, y, CellLeft(g, bc) + B + P + A / 2, CellLeft(g, pc), lit)
            Arrow(view, "left", CellLeft(g, bc) + B + P, y, lit)
        end
    else
        local lo, hi = math.min(pc, bc), math.max(pc, bc)
        local blocked = false
        for i = lo, hi do
            if i ~= pc and view.occ[OccKey(pt, i)] then blocked = true end
        end
        if not blocked then
            local y, x = CellTop(g, pt) + half, CellLeft(g, bc) + half
            if pc < bc then HLine(view, y, CellLeft(g, pc) + B, x + L / 2, lit)
            else HLine(view, y, x - L / 2, CellLeft(g, pc), lit) end
            VLine(view, x, y - L / 2, CellTop(g, bt) - P - A / 2, lit)
            Arrow(view, "down", x, CellTop(g, bt) - P, lit)
        else
            local x, y = CellLeft(g, pc) + half, CellTop(g, bt) + half
            VLine(view, x, CellTop(g, pt) + B, y + L / 2, lit)
            if pc < bc then
                HLine(view, y, x - L / 2, CellLeft(g, bc) - P - A / 2, lit)
                Arrow(view, "right", CellLeft(g, bc) - P, y, lit)
            else
                HLine(view, y, CellLeft(g, bc) + B + P + A / 2, x + L / 2, lit)
                Arrow(view, "left", CellLeft(g, bc) + B + P, y, lit)
            end
        end
    end
end

-- ============================================================
-- TOOLTIP
-- ============================================================
local function Plural(n, one, many) return n == 1 and one or many end

local function Description(n, rank)
    local Tr = C_Traits
    if not (n.entryID and Tr and Tr.GetTraitDescription) then return nil end
    local ok, d = pcall(Tr.GetTraitDescription, n.entryID, rank)
    return ok and Str(d) or nil
end

-- What still stands between you and a talent: the tree's point gate (its
-- condition) and the talents leading into it.
local function Requirements(n, model)
    local out = {}
    local Tr = C_Traits
    if n.conditionIDs and Tr and Tr.GetConditionInfo and model then
        for _, condID in ipairs(n.conditionIDs) do
            local ok, c = pcall(Tr.GetConditionInfo, model.configID, condID)
            if ok and type(c) == "table" and not Bool(c.isMet) then
                local need = Num(c.spentAmountRequired)
                if need and need > 0 then
                    out[#out + 1] = string.format("Requires %d %s in %s", need,
                        Plural(need, "point", "points"), n.tree.name)
                end
            end
        end
    end
    for _, e in ipairs(n.from) do
        if not e.active then
            local src = e.node
            out[#out + 1] = string.format("Requires %d %s in %s", src.max,
                Plural(src.max, "point", "points"), src.name)
        end
    end
    return out
end

function CT.Tooltip(owner, n, model, ctx)
    if not n then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local title, body = GetColor("tooltip", "title"), GetColor("tooltip", "body")
    local green, red, gold = GetColor("text", "green"), GetColor("text", "red"), GetColor("text", "gold")
    GameTooltip:AddLine(n.name ~= "" and n.name or (TALENTS or "Talent"), title.r, title.g, title.b)
    GameTooltip:AddLine(string.format(TOOLTIP_TALENT_RANK or "Rank %d/%d", n.rank, n.max),
        body.r, body.g, body.b)
    local req = Requirements(n, model)
    for _, line in ipairs(req) do GameTooltip:AddLine(line, red.r, red.g, red.b, true) end
    local now = Description(n, math.max(1, n.rank))
    if now then GameTooltip:AddLine(now, gold.r, gold.g, gold.b, true) end
    if n.rank > 0 and n.rank < n.max then
        local nxt = Description(n, n.rank + 1)
        if nxt then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(TOOLTIP_TALENT_NEXT_RANK or "Next rank:", body.r, body.g, body.b)
            GameTooltip:AddLine(nxt, gold.r, gold.g, gold.b, true)
        end
    end
    if ctx and ctx.hint then
        local h = ctx.hint(n)
        if h then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(h, green.r, green.g, green.b, true)
        end
    end
    GameTooltip:Show()
end

-- ============================================================
-- A TREE VIEW: header, grid, art, talent buttons, lines
-- ============================================================
local function SetTextKey(fs, cat, key)
    fs._zPaintCat, fs._zPaintKey = cat, key
    fs:_zPaint()
end

local function NewNodeButton(view)
    local g = view.geo
    local b = CreateFrame("Button", nil, view.grid)
    b:SetSize(g.btn, g.btn)
    b:SetFrameLevel(view.grid:GetFrameLevel() + 3)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    b.icon = Kit.Icon(b, g.btn)
    b.icon:SetAllPoints()
    b.icon:EnableMouse(false)

    -- the Classic look's ring (the vanilla button's Quickslot art)
    b.ring = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.ring._zui_own = true
    b.ring:Hide()

    -- the rank, inside the icon's corner so no line runs under it
    local badge = CreateFrame("Frame", nil, b)
    badge:SetSize(26, 13)
    badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    badge:SetFrameLevel(b.icon:GetFrameLevel() + 2)
    UI.Fill(badge, "ui", "elementBg")
    UI.Border(badge, "ui", "border")
    badge._zPaint = UI.PaintBox
    badge:_zPaint()
    badge.art = badge:CreateTexture(nil, "BACKGROUND", nil, -6)
    badge.art._zui_own = true
    badge.art:SetPoint("CENTER")
    badge.art:SetSize(34, 26)
    badge.art:SetTexture(RANK_BORDER)
    badge.art:Hide()
    -- (a thin outline, whatever ZacUI's font is set to: the rank sits on art)
    badge.text = UI.Font(badge, F.SMALL, { justify = "CENTER", outline = "OUTLINE" })
    badge.text:SetPoint("CENTER", 0, 0)
    badge.text:SetWordWrap(false)
    b.badge = badge

    b:SetScript("OnEnter", function(self)
        self._zHot = true
        if self.paint then self:paint() end
        if self.node then CT.Tooltip(self, self.node, view.model, view.ctx) end
    end)
    b:SetScript("OnLeave", function(self)
        self._zHot = nil
        if self.paint then self:paint() end
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self, button)
        if self.node and view.onClick then view.onClick(self, self.node, button) end
    end)
    return b
end

local ART = {   -- the four background quadrants (texcoords from the vanilla XML)
    { "TopLeft",     0, 1,      0, 1 },
    { "TopRight",    0, 0.6875, 0, 1 },
    { "BottomLeft",  0, 1,      0, 0.5859375 },
    { "BottomRight", 0, 0.6875, 0, 0.5859375 },
}

local function LayoutArt(view, w, h)
    -- the composite is 300 x 331, scaled as one picture so the seams meet
    local sx, sy = (w - 2) / 300, (h - 2) / 331
    local tl, tr, bl, br = view.art[1], view.art[2], view.art[3], view.art[4]
    tl:ClearAllPoints() tl:SetPoint("TOPLEFT", view.grid, "TOPLEFT", 1, -1) tl:SetSize(256 * sx, 256 * sy)
    tr:ClearAllPoints() tr:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0) tr:SetSize(44 * sx, 256 * sy)
    bl:ClearAllPoints() bl:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0) bl:SetSize(256 * sx, 75 * sy)
    br:ClearAllPoints() br:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT", 0, 0) br:SetSize(44 * sx, 75 * sy)
end

function CT.NewTreeView(parent, geo)
    local g = geo or GEO
    local view = CreateFrame("Frame", nil, parent)
    view.geo = g
    UI.Fill(view, "ui", "cardBg")
    UI.Border(view, "ui", "border")
    view._zPaint = UI.PaintBox
    view:_zPaint()

    local header = CreateFrame("Frame", nil, view)
    header:SetHeight(g.header)
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
    view.header = header

    local icon = header:CreateTexture(nil, "ARTWORK")
    icon._zui_own = true
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 6, 0)
    ns.Look.CropIcon(icon)
    SharpenIcon(icon)
    view.icon = icon

    view.ptsText = UI.Font(header, F.CARD, { justify = "RIGHT" })
    view.ptsText:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    view.ptsText:SetWordWrap(false)
    view.titleText = UI.Font(header, F.CARD, { justify = "LEFT", cat = "text", key = "gold" })
    view.titleText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    view.titleText:SetPoint("RIGHT", view.ptsText, "LEFT", -6, 0)
    view.titleText:SetWordWrap(false)

    local grid = CreateFrame("Frame", nil, view)
    grid:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -g.header)
    grid:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
    view.grid = grid

    view.art = {}
    for i, a in ipairs(ART) do
        local t = grid:CreateTexture(nil, "BACKGROUND", nil, -6)
        t._zui_own = true
        t:SetTexCoord(a[2], a[3], a[4], a[5])
        view.art[i] = t
    end

    local lines = CreateFrame("Frame", nil, grid)
    lines:SetAllPoints(grid)
    lines:SetFrameLevel(grid:GetFrameLevel() + 1)
    view.lines = lines

    view.buttons, view.lineTex, view.arrowTex = {}, {}, {}
    view.used = { lineTex = 0, arrowTex = 0 }
    view.occ = {}
    view.SizeTo = function(self, cols, tiers)
        local w, h = TreeW(g, cols), TreeH(g, tiers)
        self:SetSize(w, h)
        LayoutArt(self, w, GridH(g, tiers))
        self._zCols, self._zTiers = cols, tiers
    end
    view:SizeTo(4, 7)
    return view
end

-- A talent's state, the way the vanilla frame colours it: gold when full
-- (or holding points with none left to spend), green while it can take
-- one, grey and faded while it is out of reach.
function CT.NodeState(n, ctx)
    if n.max > 0 and n.rank >= n.max then return "full" end
    if ctx.editable and n.canBuy and (ctx.unspent or 0) > 0 then return "open" end
    if n.rank > 0 then return (ctx.editable and (ctx.unspent or 0) > 0) and "open" or "full" end
    return "locked"
end

local function PaintNode(b)
    local n, view = b.node, b.view
    if not n then return end
    local state = b.state
    local classic = view.classic
    local icon = b.icon
    icon:SetIcon(n.icon)
    local lit = state ~= "locked"
    icon:SetDesaturated(not lit)
    icon.texture:SetAlpha(lit and 1 or 0.55)

    -- the border (ZacUI) or the ring (Classic): gold full, green open,
    -- grey locked; the accent while the mouse is over it
    local cat, key
    if b._zHot then cat, key = "ui", "accent"
    elseif state == "full" then cat, key = "ui", "borderSelected"
    elseif state == "open" then cat, key = "text", "green"
    else cat, key = "ui", "border" end
    if classic then
        local L = view.look
        local ring = L and L.iconRing
        if ring and ring.normal then
            local s = ring.scale or (66 / 36)
            b.ring:SetTexture(ring.normal)
            b.ring:ClearAllPoints()
            b.ring:SetPoint("CENTER", b, "CENTER", 0, (ring.dy or 0) * view.geo.btn)
            b.ring:SetSize(view.geo.btn * s, view.geo.btn * s)
            local c
            if b._zHot then c = GetColor("ui", "accent")
            elseif state == "full" then c = GetColor("text", "gold")
            elseif state == "open" then c = GetColor("text", "green")
            else c = GetColor("text", "disabled") end
            b.ring:SetVertexColor(c.r, c.g, c.b, 1)
            b.ring:Show()
        else
            b.ring:Hide()
        end
        for _, s in ipairs(icon._zBorder or {}) do s:SetAlpha(0) end
    else
        b.ring:Hide()
        for _, s in ipairs(icon._zBorder or {}) do s:SetAlpha(1) end
        icon._zBorderCat, icon._zBorderKey = cat, key
        icon:_zPaint()
    end

    -- the rank plate: gold rank on the vanilla plate (Classic) or the flat
    -- plate; a pick not learned yet in green; hidden on an empty, locked one
    local badge = b.badge
    badge.text:SetText(n.rank .. "/" .. n.max)
    if n.staged then SetTextKey(badge.text, "text", "green")
    elseif state == "locked" then SetTextKey(badge.text, "text", "disabled")
    elseif state == "open" then SetTextKey(badge.text, "text", "green")
    else SetTextKey(badge.text, "text", "gold") end
    if classic then
        badge._zFill:SetAlpha(0)
        for _, s in ipairs(badge._zBorder or {}) do s:SetAlpha(0) end
        badge.art:Show()
    else
        badge._zFill:SetAlpha(1)
        for _, s in ipairs(badge._zBorder or {}) do s:SetAlpha(1) end
        badge.art:Hide()
    end
    badge:SetShown(state ~= "locked" or n.rank > 0)
end

-- Draws one tree of a model. ctx: { editable, unspent, classFile,
-- dimArt (the spec you are not using), hint(n) for the tooltip }.
function CT.PaintTree(view, tree, model, ctx)
    local classic, L = IsClassic()
    view.classic, view.look = classic, L
    view.model, view.ctx = model, ctx
    -- (even: the ring's reach past the button, Classic only)
    view.pad = classic and 4 or 0
    local g = view.geo
    if not tree then
        view:Hide()
        return
    end
    view:Show()
    local cols, tiers = model.cols or 4, model.tiers or 7
    if view._zCols ~= cols or view._zTiers ~= tiers then view:SizeTo(cols, tiers) end

    view.titleText:SetText(tree.name or "")
    view.icon:SetTexture(tree.icon)
    view.icon:SetShown(tree.icon ~= nil)
    view.ptsText:SetText(tree.spent or 0)
    SetTextKey(view.ptsText, "text", tree.staged and "green" or "normal")

    local bg = Background(tree, ctx.classFile)
    for i, t in ipairs(view.art) do
        if bg then
            t:SetTexture("Interface\\TalentFrame\\" .. bg .. "-" .. ART[i][1])
            t:SetAlpha(classic and 1 or 0.3)
            t:SetDesaturated(ctx.dimArt and true or false)
            t:Show()
        else
            t:Hide()
        end
    end

    wipe(view.occ)
    for _, n in ipairs(tree.nodes) do view.occ[OccKey(n.tier, n.col)] = true end

    view.used.lineTex, view.used.arrowTex = 0, 0
    for i, n in ipairs(tree.nodes) do
        local b = view.buttons[i]
        if not b then
            b = NewNodeButton(view)
            b.view = view
            b.paint = PaintNode
            view.buttons[i] = b
        end
        b.node = n
        b.state = CT.NodeState(n, ctx)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", view.grid, "TOPLEFT", CellLeft(g, n.col), -CellTop(g, n.tier))
        PaintNode(b)
        b:Show()
        if GameTooltip:IsOwned(b) then CT.Tooltip(b, n, model, ctx) end
        -- the lines out of this talent into the ones it opens
        for _, e in ipairs(n.edges) do
            local to = model.byID[e.to]
            if to and to.tree == tree then DrawEdge(view, to.tier, to.col, n.tier, n.col, e.active) end
        end
    end
    for i = #tree.nodes + 1, #view.buttons do
        local b = view.buttons[i]
        b.node = nil
        b:Hide()
    end
    for i = view.used.lineTex + 1, #view.lineTex do view.lineTex[i]:Hide() end
    for i = view.used.arrowTex + 1, #view.arrowTex do view.arrowTex[i]:Hide() end
end

-- ============================================================
-- THE WINDOW
-- ============================================================
local win, specTabs, statusText, unspentText, emptyText, holder, gameView
local views = {}
local model                 -- the last read
local viewGroup             -- the spec on show (nil = the one in force)
local standAside = false    -- "Game's view" until the window next opens
local hooked, started = false, false
local Queue

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.talentswin ~= false
end
CT.Enabled = Enabled

local function Host() return _G.PlayerSpellsFrame end
local function Page()
    local h = Host()
    return h and h.TalentsFrame or nil
end

-- Blizzard's parts that would draw over the cover (a higher strata, or
-- the cover's level and up: the maximise arrow, the help-plate button).
-- Faded and click-through while the cover is up, put back after; never
-- hidden. What we changed, per frame, lives here - not on their frames.
local faded = setmetatable({}, { __mode = "k" })
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local function Above(host, cover)
    local out = {}
    local isCover = {}
    for _, c in ipairs(Kit.covers or {}) do isCover[c] = true end
    local cs = cover:GetFrameStrata()
    local cl = cover:GetFrameLevel()
    if Plain(cs) == nil or Plain(cl) == nil then return out end
    local cr = STRATA[cs] or 3
    local function Walk(f, depth)
        for _, child in ipairs({ f:GetChildren() }) do
            if child ~= cover and not isCover[child] and not child._zui_own then
                local s, l = child:GetFrameStrata(), child:GetFrameLevel()
                s, l = Plain(s), Plain(l)
                if s and l then
                    local r = STRATA[s] or 3
                    if r > cr or (r == cr and l >= cl) then
                        out[#out + 1] = child
                    elseif depth < 3 then
                        Walk(child, depth + 1)
                    end
                end
            end
        end
    end
    Walk(host, 1)
    return out
end

local function Quiet()
    local host = Host()
    if not (host and win) then return end
    for _, f in ipairs(Above(host, win)) do
        -- one the spellbook's cover already silenced is Win_Kit's
        if not faded[f] and not f._zKitQuiet then
            local rec = { alpha = f:GetAlpha() }
            f:SetAlpha(0)
            if f.EnableMouse and f.IsMouseEnabled and not (f:IsProtected() and InCombatLockdown()) then
                local m = f:IsMouseEnabled()
                if Plain(m) ~= nil then
                    rec.mouse = m and true or false
                    f:EnableMouse(false)
                end
            end
            faded[f] = rec
        end
    end
end

local function Unquiet()
    for f, rec in pairs(faded) do
        if not f._zKitQuiet then
            f:SetAlpha(rec.alpha or 1)
            if rec.mouse ~= nil and not (f:IsProtected() and InCombatLockdown()) then
                f:EnableMouse(rec.mouse)
                rec.mouse = nil
            end
        end
        faded[f] = nil
    end
end
CT._faded = faded

local function ClassFile()
    local _, file = UnitClass("player")
    if Plain(file) == nil then return nil end
    return file
end

local function ShownGroup()
    local n = CT.NumSpecGroups()
    local g = viewGroup or CT.ActiveSpecGroup()
    if g > n then g = CT.ActiveSpecGroup() end
    return g
end

local committing = false   -- a Learn on its way to the server
local commitTimer

local function StatusLine(m, editable, inactive)
    if not m then return "", "gray" end
    if inactive then return "Your other spec - switch to it in the game's view to change it.", "gray" end
    if committing then return "Learning your talents...", "gold" end
    if InCombatLockdown() then return "In combat - talents can be changed when it ends.", "red" end
    if (m.stagedCount or 0) > 0 then
        return "Learn keeps your picks  |  Right-click: take one back  |  Shift-click: link", "gray"
    end
    if (m.unspent or 0) > 0 then return "Click: pick a rank  |  Shift-click: link", "gray" end
    return "Shift-click: link the talent", "gray"
end

local function Refresh()
    if not win or not win:IsVisible() then return end
    local group = ShownGroup()
    local active = CT.ActiveSpecGroup()
    local configID = CT.ConfigForGroup(group)
    model = configID and CT.Read(configID) or nil
    local inactive = group ~= active
    -- only the spec in force, out of combat, with nothing being learned
    local editable = model ~= nil and not inactive and not committing and not InCombatLockdown()
    local ctx = {
        editable = editable, unspent = model and model.unspent or 0, classFile = ClassFile(),
        dimArt = inactive, hint = editable and CT.Hint or nil,
    }

    -- the trees, centred in the window
    local n = model and #model.trees or 0
    local cols, tiers = (model and model.cols) or 4, (model and model.tiers) or 7
    local tw, th = TreeW(GEO, cols), TreeH(GEO, tiers)
    local bw = 3 * tw + 2 * GEO.gap
    holder:SetSize(bw, th)
    -- centred in the room between the top row and the footer, on whole
    -- pixels (Forever's talent page is talentsWidth x talentsHeight)
    local host = Host()
    local W = host and Num(host.talentsWidth) or 1218
    local H = host and Num(host.talentsHeight) or 708
    local topY = M.TITLEBAR + Kit.PAD + ((CT.NumSpecGroups() > 1) and (Kit.TAB_H + Kit.GAP) or 0)
    local room = H - topY - Kit.FOOTER_H - Kit.GAP
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", win, "TOPLEFT", math.max(Kit.PAD, math.floor((W - bw) / 2)),
        -(topY + math.max(0, math.floor((room - th) / 2))))
    for i = 1, 3 do
        local v = views[i]
        v:ClearAllPoints()
        v:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (tw + GEO.gap), 0)
        CT.PaintTree(v, model and model.trees[i], model or { cols = cols, tiers = tiers, byID = {} }, ctx)
    end
    emptyText:SetShown(n == 0)

    -- spec tabs: only with dual spec
    local groups = CT.NumSpecGroups()
    specTabs:SetShown(groups > 1)
    if groups > 1 then
        for g = 1, 2 do
            local label = (g == 1) and (TALENT_SPEC_PRIMARY or DUAL_SPEC_PRIMARY or "Primary")
                or (TALENT_SPEC_SECONDARY or DUAL_SPEC_SECONDARY or "Secondary")
            if g == active then label = label .. " (Active)" end
            specTabs:SetLabel(g, label)
        end
        specTabs:Paint(group)
    end

    local text, key = StatusLine(model, editable, inactive)
    statusText:SetText(text)
    SetTextKey(statusText, "text", key)

    local unspent = model and model.unspent or 0
    local label = UNSPENT_TALENT_POINTS and string.format(UNSPENT_TALENT_POINTS, tostring(unspent))
        or ("Unspent points: " .. unspent)
    local picked = model and (model.pickedPoints or model.stagedCount) or 0
    if picked > 0 then label = label .. "  (" .. picked .. " picked)" end
    unspentText:SetText(label)
    CT.PaintLearn(model, editable and not inactive)
    SetTextKey(unspentText, "text", unspent > 0 and "green" or "normal")

    -- the title: the tree with most points, as the vanilla window's icon
    local best, bestPts = nil, 0
    for i = 1, n do
        local t = model.trees[i]
        if (t.spent or 0) > bestPts then best, bestPts = t, t.spent end
    end
    win:SetIcon(best and best.icon or nil)
end
CT.Refresh = function() if Queue then Queue() end end

local function CloseWindow()
    local host = Host()
    if not host then return end
    -- the spellbook's secure rows make this window protected: in a fight
    -- only Blizzard's own keys may close it
    if InCombatLockdown() and host:IsProtected() then
        if UIErrorsFrame then UIErrorsFrame:AddMessage("Close the talents with Escape or the talent key in combat.", 1, 0.2, 0.2) end
        return
    end
    HideUIPanel(host)
end

local function OnLinkClick(btn, n, button)
    if IsModifiedClick("CHATLINK") and n.spellID then
        local link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(n.spellID)
        local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if Str(link) and insert then insert(link) end
        return true
    end
    return false
end
CT.OnLinkClick = OnLinkClick

local function Build()
    if win then return win end
    local host = Host()
    win = Kit.Cover(host, {
        name = "ZacUIClassicTalentWindow",
        title = TALENTS or "Talents",
        insetName = "PlayerSpellsFrame",
        -- over the spellbook's cover (700): in a fight that one can not be
        -- put away when the window turns to its Talents page
        minLevel = 800,
        onClose = CloseWindow,
    })
    win:Hide()

    specTabs = Kit.Tabs(win, {
        { key = 1, label = TALENT_SPEC_PRIMARY or DUAL_SPEC_PRIMARY or "Primary" },
        { key = 2, label = TALENT_SPEC_SECONDARY or DUAL_SPEC_SECONDARY or "Secondary" },
    }, function(key)
        viewGroup = key
        if Queue then Queue() end
    end, { minWidth = 90 })
    specTabs:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, win.top)
    specTabs:SetWidth(300)
    specTabs:Hide()


    holder = CreateFrame("Frame", nil, win)
    for i = 1, 3 do views[i] = CT.NewTreeView(holder, GEO) end
    for _, v in ipairs(views) do v.onClick = function(btn, n, button) return CT.Click(btn, n, button) end end

    win.footer = Kit.Footer(win, Kit.FOOTER_H)
    unspentText = UI.Font(win.footer, F.LABEL, { justify = "LEFT" })
    unspentText:SetPoint("LEFT", win.footer, "LEFT", 8, 0)
    unspentText:SetWordWrap(false)
    -- what a click does, in the middle of the footer
    statusText = UI.Font(win.footer, F.SMALL, { cat = "text", key = "gray", justify = "CENTER" })
    statusText:SetPoint("CENTER", win.footer, "CENTER", 0, 0)
    statusText:SetWordWrap(false)

    gameView = GlyphButton(win.footer, "back", "Game's view",
        "Step aside to the game's own talent page until the window next opens - "
            .. "switching spec and the talent search live there.")
    gameView:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    gameView:SetScript("OnClick", function() CT.StandAside() end)
    win.gameView = gameView

    -- Learn (with a confirm) and Undo, shown while there are picks
    win.learn = UI.Button(win.footer, LEARN or "Learn", { height = 24, width = 84,
        tooltip = "Learn the ranks you picked. Asks first; not in combat." })
    win.learn:SetPoint("RIGHT", gameView, "LEFT", -Kit.GAP, 0)
    win.learn:SetScript("OnClick", function() CT.ConfirmLearn() end)
    win.learn:Hide()
    win.undo = GlyphButton(win.footer, "reset", "Undo",
        "Take back every pick you have not learned yet.")
    win.undo:SetPoint("RIGHT", win.learn, "LEFT", -Kit.GAP, 0)
    win.undo:SetScript("OnClick", function() CT.Undo() end)
    win.undo:Hide()

    emptyText = UI.Font(win, F.LABEL, { cat = "text", key = "gray", justify = "CENTER" })
    emptyText:SetPoint("CENTER", win, "CENTER", 0, 0)
    emptyText:SetText("No talents to show yet.")
    emptyText:Hide()

    Queue = Kit.Coalesce(Refresh, function() return win end)

    local ev = CreateFrame("Frame", nil, win)
    local valid = C_EventUtils and C_EventUtils.IsEventValid
    for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
            "ACTIVE_COMBAT_CONFIG_CHANGED", "CONFIG_COMMIT_FAILED", "TRAIT_CONFIG_LIST_UPDATED",
            "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_LEVEL_UP", "SPELL_TEXT_UPDATE",
            "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        if not valid or valid(e) then pcall(ev.RegisterEvent, ev, e) end
    end
    ev:SetScript("OnEvent", function(_, event, ...)
        if CT.OnEvent then CT.OnEvent(event, ...) end
        Queue()
    end)
    win:HookScript("OnShow", function() Queue() end)
    CT.win, CT.views = win, views
    return win
end

-- ============================================================
-- SHOWING: with the Talents page, never otherwise
-- ============================================================
function CT.Apply()
    local page = Page()
    if not page then return end
    if Enabled() and not standAside and page:IsVisible() then
        Build()
        win:Show()
        Quiet()
        Queue()
    elseif win and win:IsShown() then
        win:Hide()
        Unquiet()
    end
end

function CT.StandAside()
    standAside = true
    if CT.OnStandAside then CT.OnStandAside() end
    CT.Apply()
end

local function OnPageHide()
    if CT.OnPageHide then CT.OnPageHide() end
    if win and win:IsShown() then
        win:Hide()
        Unquiet()
    end
end

local function Hook()
    local host, page = Host(), Page()
    if hooked or not (host and page) then return end
    hooked = true
    page:HookScript("OnShow", CT.Apply)
    page:HookScript("OnHide", OnPageHide)
    -- the window closing ends "Game's view" and the spec on show
    host:HookScript("OnHide", function()
        standAside = false
        viewGroup = nil
    end)
    CT.Apply()
end
CT.Hook = Hook

-- The talents module on Forever (Win_Talents' Classic Era window waits for
-- Blizzard_TalentUI, which Forever does not have).
Modules.talentswin = function()
    if started then return end
    started = true
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded("Blizzard_PlayerSpells") then
        Hook()
        return
    end
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("ADDON_LOADED")
    watch:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_PlayerSpells" then
            self:UnregisterEvent("ADDON_LOADED")
            Hook()
        end
    end)
end

-- ============================================================
-- LEARNING: staged picks, then one commit (Forever's own flow)
-- ============================================================
-- A click PICKS a rank (C_Traits.PurchaseRank on the config you wear: a
-- staged change the server has not seen); right-click takes a pick back
-- (C_Traits.RefundRank - only a pick: a learned rank needs the trainer);
-- Learn asks first, then C_ClassTalents.CommitConfig sends every pick at
-- once. Out of combat only, and only on the spec in force. Picks still
-- standing when the window closes are dropped (C_Traits.RollbackConfig),
-- so the next open never finds half a build waiting.
local function Say(msg)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        local c = GetColor("text", "red")
        UIErrorsFrame:AddMessage(msg, c.r, c.g, c.b)
    end
end

function CT.Hint(n)
    if n.canBuy and (model and model.unspent or 0) > 0 then return "Click to pick a rank" end
    if n.staged and n.canRefund then return "Right-click to take the pick back" end
    return nil
end

function CT.Click(btn, n, button)
    if OnLinkClick(btn, n, button) then return end
    if not model or committing then return end
    if ShownGroup() ~= CT.ActiveSpecGroup() then return end
    local Tr = C_Traits
    if not Tr then return end
    if InCombatLockdown() then
        Say("Talents can't be changed in combat.")
        return
    end
    local ok, done
    if button == "RightButton" then
        if not (n.staged and n.canRefund and Tr.RefundRank) then return end
        ok, done = pcall(Tr.RefundRank, model.configID, n.id)
    else
        if not (n.canBuy and (model.unspent or 0) > 0 and Tr.PurchaseRank) then return end
        ok, done = pcall(Tr.PurchaseRank, model.configID, n.id)
    end
    if not (ok and Plain(done) ~= false) then Say("That talent can't be changed right now.") end
    if Queue then Queue() end
end

function CT.PaintLearn(m, editable)
    if not win or not win.learn then return end
    local picks = m and (m.hasStaged or (m.stagedCount or 0) > 0) or false
    win.learn:SetShown(picks)
    win.undo:SetShown(picks)
    win.learn:SetDisabled(not (picks and editable))
    -- the one button that matters while there are picks: lit
    win.learn:SetActive(picks and editable)
    win.undo:SetDisabled(not (picks and editable))
    if win.undo._zGlyphPaint then win.undo:_zGlyphPaint() end
    if picks then
        local n = m.pickedPoints or m.stagedCount or 0
        win.learn:SetLabel(n > 0 and ((LEARN or "Learn") .. " (" .. n .. ")") or (LEARN or "Learn"))
    end
end

function CT.Undo()
    if not model or committing or InCombatLockdown() then return end
    local Tr = C_Traits
    if Tr and Tr.RollbackConfig then pcall(Tr.RollbackConfig, model.configID) end
    if Queue then Queue() end
end

local function EndCommit()
    committing = false
    if commitTimer then commitTimer:Cancel() commitTimer = nil end
end

function CT.Learn()
    if not model or committing then return false end
    if InCombatLockdown() then
        Say("Talents can't be changed in combat.")
        return false
    end
    local C = C_ClassTalents
    if not (C and C.CommitConfig) then return false end
    if C.CanChangeTalents then
        local ok, can, _, err = pcall(C.CanChangeTalents)
        if ok and Plain(can) == false and Str(err) then
            Say(err)
            return false
        end
    end
    -- nil: the config in force (Forever keeps no loadouts of its own)
    local ok, sent = pcall(C.CommitConfig, nil)
    if not (ok and Plain(sent) ~= false) then
        Say("Your talents could not be learned. Try again in a moment.")
        return false
    end
    committing = true
    -- the server answers with TRAIT_CONFIG_UPDATED (or CONFIG_COMMIT_FAILED);
    -- a backstop in case neither comes
    if commitTimer then commitTimer:Cancel() end
    commitTimer = C_Timer.NewTimer and C_Timer.NewTimer(10, function()
        commitTimer = nil
        if committing then committing = false if Queue then Queue() end end
    end) or nil
    if Queue then Queue() end
    return true
end

function CT.ConfirmLearn()
    if not model or committing or InCombatLockdown() then return end
    local names = {}
    for _, n in ipairs(model.nodes) do
        if n.staged then names[#names + 1] = n.name .. " " .. n.rank .. "/" .. n.max end
    end
    local text = "Learn these talents?"
    if #names > 0 then text = text .. "\n\n" .. table.concat(names, "\n") end
    text = text .. "\n\nA learned rank can only be taken back at a trainer."
    UI.Confirm({
        title = LEARN or "Learn",
        text = text,
        acceptText = LEARN or "Learn",
        onAccept = function() CT.Learn() end,
    })
end

function CT.OnEvent(event, ...)
    if event == "TRAIT_CONFIG_UPDATED" or event == "CONFIG_COMMIT_FAILED"
        or event == "ACTIVE_COMBAT_CONFIG_CHANGED" then
        if committing then EndCommit() end
        if event == "CONFIG_COMMIT_FAILED" then Say("Your talents could not be learned.") end
    end
end

-- the window going away drops the picks that were never learned
function CT.OnPageHide()
    -- (only picks made on ZacUI's trees: the game's own page keeps its own)
    if not (win and win:IsShown()) then return end
    if not model or committing or InCombatLockdown() then return end
    if model.hasStaged or (model.stagedCount or 0) > 0 then
        local Tr = C_Traits
        if Tr and Tr.RollbackConfig then pcall(Tr.RollbackConfig, model.configID) end
    end
end
CT._committing = function() return committing end
