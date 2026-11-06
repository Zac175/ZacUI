-- Win_Profession - ZacUI's profession windows: one wide window with the
-- recipe list on the left and the recipe on the right, in the spirit of
-- TSM's crafting screen, instead of Blizzard's stacked 8-row list.
-- Part of ZacUI; load order is set by the TOC.
--
-- TWO BLIZZARD WINDOWS, ONE LAYOUT. Era has two profession UIs that do
-- the same job through different APIs: TradeSkillFrame (every craft that
-- makes an item - Tailoring, Engineering, Cooking, Smelting ...) and
-- CraftFrame (Enchanting, and Beast Training for hunters). A small
-- adapter table per window hides the API differences (GetTradeSkillInfo
-- vs GetCraftInfo and friends), and one builder makes both windows.
--
-- Both are Win_Kit covers, WIDER than Blizzard's panel (the panel's
-- top-left corner is kept, the window extends right). Blizzard's frame
-- keeps doing the session work: it opens on TRADE_SKILL_SHOW, and hiding
-- it is what ends the session (CloseTradeSkill / CloseCraft in its
-- OnHide) - so the X clicks Blizzard's own close button.
--
-- THE PROFESSION TABS ARE SECURE. Switching profession means casting its
-- spell, and casting is protected, so each tab is a SecureActionButton
-- running "/cast <profession>". A secure child makes the window (and
-- TradeSkillFrame / CraftFrame) protected in combat: the tabs and the
-- secure X are only ever created, pointed and re-attributed out of
-- combat, the window is never moved or hidden by us in combat, and the X
-- runs Blizzard's close button through a secure click so it still works
-- mid-fight. A tab for the OTHER window type (Enchanting from the
-- Tailoring window) closes this window first, so the two never open
-- side by side and overlap.
--
--   Recipe click          select it
--   Shift-click recipe    link the recipe (crafts: shift links, ctrl previews)
--   Header click          collapse / expand the category
--   Reagent / product     hover for the tooltip, shift-click to link,
--                         ctrl-click to preview (Blizzard's modified click)
--   Create / Create All   DoTradeSkill, with the -/+ quantity like Blizzard

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
local UI = ns.UI

local M, F = UI.M, UI.F

-- ============================================================
-- LAYOUT
-- ============================================================
local WIN_W       = 660
local LIST_W      = 300
local COL_GAP     = 8
local DETAIL_W    = WIN_W - 2 * Kit.PAD - LIST_W - COL_GAP
local LIST_ROW_H  = 18
local RANK_H      = 16
local ICON_BIG    = 38
local REAGENT_H   = 30
local MAX_REAGENTS = 8
local BTN_W       = 80

-- Rows of the window, top down. Everything below the tabs hangs off
-- these, so a change of one height is one edit.
local TABS_Y    = -(M.TITLEBAR + Kit.PAD)
local RANK_Y    = TABS_Y - Kit.TAB_H - Kit.GAP
local TOOLBAR_Y = RANK_Y - RANK_H - Kit.GAP
-- The toolbar mixes 22px chips with 24px dropdowns: every piece rides
-- one centre line so their middles agree.
local TOOLBAR_MID = TOOLBAR_Y - 12
local BODY_Y    = TOOLBAR_Y - M.DROPDOWN_H - Kit.GAP

-- ============================================================
-- SMALL HELPERS
-- ============================================================
-- Palette colour as an inline |c code, for a coloured piece inside one
-- string ("Requires: <red>Anvil</red>"). Derived, never a literal.
local function Hex(cat, key)
    local c = GetColor(cat, key)
    return string.format("|cff%02x%02x%02x",
        math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

local function ItemQuality(link)
    if not link then return nil end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return nil end
    return (select(3, getInfo(link)))
end

local function Insert(link)
    local f = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if link and f then return f(link) end
end

local function ActiveChat()
    if ChatFrameUtil and ChatFrameUtil.GetActiveWindow then
        return ChatFrameUtil.GetActiveWindow()
    end
    return true
end

-- HandleModifiedItemClick is Blizzard's one entry for shift (link) and
-- ctrl (dress-up) on an item; it checks the modifiers itself.
local function ModifiedItem(link)
    if link and HandleModifiedItemClick then return HandleModifiedItemClick(link) end
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local n = C_Spell.GetSpellName(id)
        if n then return n end
    end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function On(v) return v == 1 or v == true end

local function Hover(self)
    if CursorUpdate then CursorUpdate(self) end
end
local function Unhover()
    GameTooltip:Hide()
    if ResetCursor then ResetCursor() end
end

-- ============================================================
-- ADAPTERS
-- ============================================================
-- Every call below is copied from Blizzard's Vanilla Blizzard_TradeSkillUI
-- / Blizzard_CraftUI - argument and return order included. The builder
-- only ever talks to these.

-- TRADE SKILLS -----------------------------------------------
local TRADE = {
    key = "tradeskillwin", lod = "Blizzard_TradeSkillUI",
    hostName = "TradeSkillFrame", frameName = "ZacUITradeSkillWindow",
    closeName = "TradeSkillFrameCloseButton",
    title = TRADE_SKILLS or "Trade Skills",
    craft = false, batch = true, filters = true,
    events = { "TRADE_SKILL_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
               "UPDATE_TRADESKILL_RECAST" },
    listEvents = { TRADE_SKILL_UPDATE = true, TRADE_SKILL_SHOW = true },
    closeEvent = "TRADE_SKILL_CLOSE",
}
function TRADE.Host() return _G.TradeSkillFrame end
function TRADE.Num() return (GetNumTradeSkills and GetNumTradeSkills()) or 0 end
-- Normalised to the craft shape: name, type, available, expanded,
-- sub-name, training cost, required level.
function TRADE.Info(i)
    local name, kind, avail, expanded = GetTradeSkillInfo(i)
    return name, kind, avail, expanded, nil, 0, nil
end
function TRADE.Color(kind)
    local t = _G.TradeSkillTypeColor
    return t and t[kind]
end
function TRADE.Selected() return (GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex()) or 0 end
-- Through Blizzard's own selection path when it is there, so its state
-- (TradeSkillFrame.selectedSkill, and every addon that hooks it) stays
-- in step with ours - exactly what a click on its list does.
function TRADE.Select(i)
    if TradeSkillFrame_SetSelection then
        local ok = pcall(TradeSkillFrame_SetSelection, i)
        if ok then
            if TradeSkillFrame_Update then pcall(TradeSkillFrame_Update, _G.TradeSkillFrame) end
            return
        end
    end
    SelectTradeSkill(i)
end
function TRADE.Expand(i) ExpandTradeSkillSubClass(i) end
function TRADE.Collapse(i) CollapseTradeSkillSubClass(i) end
function TRADE.Line() return GetTradeSkillLine() end
function TRADE.LineName() return (GetTradeSkillLine()) end
function TRADE.Icon(i) return GetTradeSkillIcon(i) end
function TRADE.ItemLink(i) return GetTradeSkillItemLink and GetTradeSkillItemLink(i) end
function TRADE.NumReagents(i) return GetTradeSkillNumReagents(i) or 0 end
function TRADE.Reagent(i, j) return GetTradeSkillReagentInfo(i, j) end
function TRADE.ReagentLink(i, j)
    return GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(i, j)
end
-- Blizzard builds this string itself: tools you lack come back red.
function TRADE.Requires(i)
    if BuildColoredListString and GetTradeSkillTools then
        return BuildColoredListString(GetTradeSkillTools(i))
    end
end
function TRADE.Cooldown(i) return GetTradeSkillCooldown and GetTradeSkillCooldown(i) end
function TRADE.NumMade(i)
    if GetTradeSkillNumMade then return GetTradeSkillNumMade(i) end
    return 1, 1
end
function TRADE.Description() return nil end
function TRADE.TooltipRecipe(i) GameTooltip:SetTradeSkillItem(i) end
function TRADE.TooltipProduct(i) GameTooltip:SetTradeSkillItem(i) end
function TRADE.TooltipReagent(i, j) GameTooltip:SetTradeSkillItem(i, j) end
-- Blizzard's list: ANY modified click links the recipe and never selects.
function TRADE.RowModifiedClick(i)
    if not IsModifiedClick() then return false end
    ModifiedItem(GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i))
    return true
end
function TRADE.ProductClick(i) ModifiedItem(TRADE.ItemLink(i)) end
function TRADE.ReagentClick(i, j) ModifiedItem(TRADE.ReagentLink(i, j)) end
function TRADE.ButtonLabel() return CREATE or "Create" end
function TRADE.Do(i, n)
    -- Blizzard's Create buttons refuse on a play-time-limited account.
    if PartialPlayTime and PartialPlayTime() then return end
    if NoPlayTime and NoPlayTime() then return end
    DoTradeSkill(i, n)
end
-- Ends the session; TRADE_SKILL_CLOSE then hides the frame from
-- Blizzard's own (secure) handler - the in-combat close that works.
function TRADE.EndSession() if CloseTradeSkill then CloseTradeSkill() end end

-- CRAFTS (Enchanting, Beast Training) ---------------------------
local CRAFT = {
    key = "craftwin", lod = "Blizzard_CraftUI",
    hostName = "CraftFrame", frameName = "ZacUICraftWindow",
    closeName = "CraftFrameCloseButton",
    title = TRADE_SKILLS or "Trade Skills",
    craft = true, batch = false, filters = false,
    events = { "CRAFT_UPDATE", "CRAFT_SHOW", "CRAFT_CLOSE", "UNIT_PET_TRAINING_POINTS" },
    listEvents = { CRAFT_UPDATE = true, CRAFT_SHOW = true },
    closeEvent = "CRAFT_CLOSE",
}
function CRAFT.Host() return _G.CraftFrame end
function CRAFT.Num() return (GetNumCrafts and GetNumCrafts()) or 0 end
function CRAFT.Info(i)
    local name, sub, kind, avail, expanded, tp, reqLevel = GetCraftInfo(i)
    return name, kind, avail, expanded, sub, tp or 0, reqLevel
end
function CRAFT.Color(kind)
    local t = _G.CraftTypeColor
    return t and t[kind]
end
function CRAFT.Selected() return (GetCraftSelectionIndex and GetCraftSelectionIndex()) or 0 end
function CRAFT.Select(i)
    if CraftFrame_SetSelection then
        local ok = pcall(CraftFrame_SetSelection, i)
        if ok then
            if CraftFrame_Update then pcall(CraftFrame_Update) end
            return
        end
    end
    SelectCraft(i)
end
function CRAFT.Expand(i) ExpandCraftSkillLine(i) end
function CRAFT.Collapse(i) CollapseCraftSkillLine(i) end
-- Nil for Beast Training: it has no rank bar in Blizzard's window either.
function CRAFT.Line()
    if GetCraftDisplaySkillLine then return GetCraftDisplaySkillLine() end
end
function CRAFT.LineName() return GetCraftName and GetCraftName() end
function CRAFT.Icon(i) return GetCraftIcon(i) end
function CRAFT.ItemLink(i) return GetCraftItemLink and GetCraftItemLink(i) end
function CRAFT.NumReagents(i) return GetCraftNumReagents(i) or 0 end
function CRAFT.Reagent(i, j) return GetCraftReagentInfo(i, j) end
function CRAFT.ReagentLink(i, j) return GetCraftReagentItemLink and GetCraftReagentItemLink(i, j) end
function CRAFT.Requires(i, reqLevel)
    if BuildColoredListString and GetCraftSpellFocus then
        local s = BuildColoredListString(GetCraftSpellFocus(i))
        if s then return s end
    end
    -- Beast Training: the pet's level. Blizzard prints it plain; red
    -- when the pet is too low reads the way the tool line does.
    if reqLevel and reqLevel > 0 and TRAINER_REQ_LEVEL then
        local text = format(TRAINER_REQ_LEVEL, reqLevel)
        if (UnitLevel("pet") or 0) < reqLevel then
            return Hex("text", "red") .. text .. "|r"
        end
        return text
    end
end
function CRAFT.Cooldown() return nil end
function CRAFT.NumMade() return 1, 1 end
function CRAFT.Description(i) return GetCraftDescription and GetCraftDescription(i) end
function CRAFT.TooltipRecipe(i) GameTooltip:SetCraftSpell(i) end
function CRAFT.TooltipProduct(i) GameTooltip:SetCraftSpell(i) end
function CRAFT.TooltipReagent(i, j) GameTooltip:SetCraftItem(i, j) end
-- Blizzard's craft list ignores modifiers; ours links on shift and
-- previews on ctrl the way its product icon does, and never selects.
local function CraftModified(link)
    if IsControlKeyDown() then
        if DressUpItemLink then DressUpItemLink(link) end
        return true
    elseif IsShiftKeyDown() then
        if ActiveChat() then Insert(link) end
        return true
    end
    return false
end
function CRAFT.RowModifiedClick(i)
    local link = (GetCraftRecipeLink and GetCraftRecipeLink(i)) or CRAFT.ItemLink(i)
    if IsShiftKeyDown() then
        if ActiveChat() then Insert(link) end
        return true
    elseif IsControlKeyDown() then
        if DressUpItemLink then DressUpItemLink(CRAFT.ItemLink(i)) end
        return true
    end
    return false
end
function CRAFT.ProductClick(i) CraftModified(CRAFT.ItemLink(i)) end
function CRAFT.ReagentClick(i, j) CraftModified(CRAFT.ReagentLink(i, j)) end
-- "Enchant" / "Train": the craft window's button names itself.
function CRAFT.ButtonLabel()
    local tok = GetCraftButtonToken and GetCraftButtonToken()
    return (tok and _G[tok]) or CREATE or "Create"
end
function CRAFT.Do(i) DoCraft(i) end
function CRAFT.EndSession() if CloseCraft then CloseCraft() end end

-- ============================================================
-- PROFESSIONS THE PLAYER KNOWS
-- ============================================================
-- One entry per profession spell that opens a window. The name is
-- looked up from the id (so it is localised), then the spellbook is
-- scanned for it: a spell in the book is one you know, and the book
-- holds the rank you know. `line` is the skill line the window reports
-- when it differs from the spell (Smelting opens the Mining window).
local PROFESSIONS = {
    { id = 2259 },               -- Alchemy
    { id = 2018 },               -- Blacksmithing
    { id = 7411, craft = true }, -- Enchanting
    { id = 4036 },               -- Engineering
    { id = 2108 },               -- Leatherworking
    { id = 3908 },               -- Tailoring
    { id = 2656, line = 2575 },  -- Smelting (the Mining window)
    { id = 2550 },               -- Cooking
    { id = 3273 },               -- First Aid
    { id = 2842 },               -- Poisons (rogues)
    { id = 5149, craft = true }, -- Beast Training (hunters)
}

local BOOK = BOOKTYPE_SPELL or "spell"
local profCache, profDirty = {}, true

local function Professions()
    if not profDirty then return profCache end
    profDirty = false
    profCache = {}
    local want = {}
    for order, p in ipairs(PROFESSIONS) do
        local name = SpellName(p.id)
        if name then
            want[name] = {
                order = order, id = p.id, name = name, craft = p.craft and true or false,
                line = (p.line and SpellName(p.line)) or name,
            }
        end
    end
    local getName = GetSpellBookItemName or GetSpellName
    local getTex = GetSpellBookItemTexture or GetSpellTexture
    if not (GetNumSpellTabs and GetSpellTabInfo and getName) then return profCache end
    local found = {}
    for t = 1, GetNumSpellTabs() do
        local _, _, offset, numSlots = GetSpellTabInfo(t)
        for slot = (offset or 0) + 1, (offset or 0) + (numSlots or 0) do
            local n = getName(slot, BOOK)
            local w = n and want[n]
            if w and not found[n] then
                local slotType = GetSpellBookItemInfo and GetSpellBookItemInfo(slot, BOOK)
                if slotType ~= "FUTURESPELL" then
                    w.slot = slot
                    w.icon = getTex and getTex(slot, BOOK)
                    found[n] = w
                    profCache[#profCache + 1] = w
                end
            end
        end
    end
    table.sort(profCache, function(a, b) return a.order < b.order end)
    return profCache
end

local function ProfFor(lineName)
    if not lineName then return nil end
    for _, p in ipairs(Professions()) do
        if p.line == lineName or p.name == lineName then return p end
    end
end

-- ============================================================
-- THE WINDOW BUILDER
-- ============================================================
local function Enabled(A)
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules[A.key] ~= false
end

-- Pieces of Blizzard's frame outside the cover: the portrait and its
-- ring poke past the top-left corner, the close button past the top.
-- The art is the frame's own regions (the ZacUI skin's own textures are
-- marked and left alone). A list without holes: Kit.Silence walks ipairs.
local function Leftovers(A)
    local host = A.Host()
    local t = {}
    local close = _G[A.closeName]
    if close then t[#t + 1] = close end
    if host then
        for _, r in ipairs({ host:GetRegions() }) do
            if not r._zui_own then t[#t + 1] = r end
        end
    end
    return t
end

-- Same paint as UI.Button (not exported, and a secure button cannot BE a
-- UI.Button): selected = green fill, green ring, green text.
local function PaintTab(self)
    local c = GetColor("button", self._zActive and "active" or "bg")
    self._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1)
    local b = GetColor("ui", self._zActive and "borderSelected" or "border")
    for _, t in ipairs(self._zBorder) do t:SetVertexColor(b.r, b.g, b.b, b.a or 1) end
    local t = GetColor("text", self._zActive and "green" or "normal")
    self._zText:SetTextColor(t.r, t.g, t.b, 1)
end

local function NewWindow(A)
    local W = { A = A, query = "", tabButtons = {}, tabCount = 0 }
    local win, list, detail, footer

    -- ------------------------------------------------------------
    -- DATA
    -- ------------------------------------------------------------
    -- Reagent names per recipe index, for the search. Built only while a
    -- query is typed, dropped whenever the list or the item cache moves.
    local function ReagentText(i)
        W.cache = W.cache or {}
        local s = W.cache[i]
        if s == nil then
            local parts = {}
            for j = 1, A.NumReagents(i) do
                local n = A.Reagent(i, j)
                if n then parts[#parts + 1] = n end
            end
            s = table.concat(parts, "\n")
            W.cache[i] = s
        end
        return s
    end

    local function Pass(e, q, wantMats, wantSkill)
        if wantMats and (e.avail or 0) == 0 then return false end
        if wantSkill and (e.kind == "trivial" or e.kind == "used") then return false end
        if q ~= "" and not Kit.Matches(q, e.name, e.sub)
            and not Kit.Matches(q, ReagentText(e.index)) then
            return false
        end
        return true
    end

    -- Headers are kept in order; while filtering, an open header only
    -- shows once one of its recipes passes, and a closed one always shows
    -- (what is under it cannot be searched until it is opened).
    local function BuildData()
        local q = W.query
        local wantMats = W.chipMats:IsOn()
        local wantSkill = W.chipSkill:IsOn()
        local filtering = q ~= "" or wantMats or wantSkill
        local data, total, shown = {}, 0, 0
        local numHeaders, closed = 0, 0
        local pending, selEntry
        local sel = A.Selected()
        for i = 1, A.Num() do
            local name, kind, avail, expanded, sub, tp = A.Info(i)
            if name then
                if kind == "header" then
                    numHeaders = numHeaders + 1
                    local h = { index = i, name = name, header = true,
                                expanded = expanded and true or false }
                    if not h.expanded then closed = closed + 1 end
                    if not filtering or not h.expanded then
                        data[#data + 1] = h
                        pending = nil
                    else
                        pending = h
                    end
                else
                    total = total + 1
                    local e = { index = i, name = name, kind = kind, avail = avail or 0,
                                sub = sub, tp = tp or 0 }
                    if not filtering or Pass(e, q, wantMats, wantSkill) then
                        if pending then
                            data[#data + 1] = pending
                            pending = nil
                        end
                        data[#data + 1] = e
                        shown = shown + 1
                        if i == sel then selEntry = e end
                    end
                end
            end
        end
        return data, total, shown, filtering, numHeaders, closed, selEntry
    end

    -- ------------------------------------------------------------
    -- TABS (secure; out of combat only)
    -- ------------------------------------------------------------
    local function TabWidth(b)
        return math.ceil(b._zText:GetStringWidth()) + 16 + 4 + 5 + 10
    end

    local function NewTab()
        local b = CreateFrame("Button", nil, W.tabStrip, "SecureActionButtonTemplate")
        b:SetHeight(Kit.TAB_H)
        -- Act on release, like the spellbook rows: a press-cast would
        -- fire on the way into a drag and on every accidental mouse-down.
        b:SetAttribute("useOnKeyDown", false)
        b:RegisterForClicks("AnyUp")
        UI.Fill(b, "button", "bg")
        UI.Border(b, "ui", "border")
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon._zui_own = true
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 5, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        SharpenIcon(icon)
        b.icon = icon
        b._zText = UI.Font(b, F.LABEL, { justify = "LEFT" })
        b._zText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        b._zText:SetWordWrap(false)
        b._zNormalKey = "bg"
        b._zPaint = PaintTab
        UI.Hover(b, "bg", "hover")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl._zui_own = true
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        hl:SetBlendMode("ADD")
        function b:SetActive(on)
            self._zActive = on and true or nil
            self:_zPaint()
        end
        b:HookScript("OnEnter", function(self)
            local p = self._zProf
            if not p then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            if p.slot and GameTooltip.SetSpellBookItem then
                GameTooltip:SetSpellBookItem(p.slot, BOOK)
            else
                local tc = GetColor("tooltip", "title")
                GameTooltip:AddLine(p.name, tc.r, tc.g, tc.b)
            end
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        b:_zPaint()
        return b
    end

    -- Lights the tab of the profession on screen and disarms it: casting
    -- the open profession again is at best a no-op. Paint is safe in
    -- combat; attributes are not, so a fight defers them.
    local function SyncTabs()
        local cur = A.LineName()
        local locked = InCombatLockdown()
        for i = 1, W.tabCount do
            local b = W.tabButtons[i]
            local p = b._zProf
            local active = p and cur and (p.line == cur or p.name == cur) or false
            b:SetActive(active)
            -- _zArmed/_zArmedMacro mirror the attributes, so a redraw in
            -- combat only flags a resync when one is actually owed.
            local wantArmed = not active
            if b._zArmed ~= wantArmed or (wantArmed and b._zArmedMacro ~= b._zMacro) then
                if locked then
                    W.tabsDirty = true
                elseif wantArmed then
                    b:SetAttribute("type", "macro")
                    b:SetAttribute("macrotext", b._zMacro)
                    b._zArmed, b._zArmedMacro = true, b._zMacro
                else
                    b:SetAttribute("type", nil)
                    b._zArmed, b._zArmedMacro = false, nil
                end
            end
        end
    end

    local function BuildTabs()
        if not W.secureBuilt then return end
        if InCombatLockdown() then
            W.tabsDirty = true
            return
        end
        W.tabsDirty = nil
        local profs = Professions()
        local btns = W.tabButtons
        for i, p in ipairs(profs) do
            local b = btns[i]
            if not b then
                b = NewTab()
                btns[i] = b
            end
            b._zProf = p
            b.icon:SetTexture(p.icon)
            b._zText:SetText(p.name)
            -- The other window type: close this one first, so the craft
            -- and trade windows never stand side by side over each other.
            if p.craft == A.craft then
                b._zMacro = "/cast " .. p.name
            else
                b._zMacro = "/click " .. A.closeName .. "\n/cast " .. p.name
            end
        end
        for i = #profs + 1, #btns do
            btns[i]._zProf = nil
            btns[i]:SetAttribute("type", nil)
            btns[i]._zArmed, btns[i]._zArmedMacro = false, nil
            btns[i]:Hide()
        end
        W.tabCount = #profs

        -- Icon-only when every name will not fit on one row.
        local avail = WIN_W - 2 * Kit.PAD
        local full = 0
        for i = 1, #profs do full = full + TabWidth(btns[i]) + ((i > 1) and 3 or 0) end
        local compact = full > avail
        local prev
        for i = 1, #profs do
            local b = btns[i]
            b._zText:SetShown(not compact)
            b:SetWidth(compact and 26 or TabWidth(b))
            b:ClearAllPoints()
            if prev then
                b:SetPoint("LEFT", prev, "RIGHT", 3, 0)
            else
                b:SetPoint("LEFT", W.tabStrip, "LEFT", 0, 0)
            end
            b:Show()
            prev = b
        end
        SyncTabs()
    end

    -- THE X, SECURELY, and the tabs. Built together and only out of
    -- combat: the first secure child is what makes the window protected.
    local function BuildSecure()
        if W.secureBuilt or InCombatLockdown() or not win then return end
        W.secureBuilt = true
        local blizzClose = _G[A.closeName]
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
            W.secureX = sx
        end
        BuildTabs()
    end

    -- ------------------------------------------------------------
    -- HEADER: rank bar
    -- ------------------------------------------------------------
    local function UpdateRank()
        local name, rank, maxRank = A.Line()
        if name and rank and maxRank then
            W.rankBar:Show()
            W.rankBar:SetMinMaxValues(0, (maxRank > 0) and maxRank or 1)
            W.rankBar:SetValue(rank)
            W.rankName:SetText(name)
            W.rankValue:SetText(rank .. " / " .. maxRank)
            W.points:SetText("")
        else
            W.rankBar:Hide()
            local total, spent = 0, 0
            if GetPetTrainingPoints then total, spent = GetPetTrainingPoints() end
            if (total or 0) > 0 then
                W.points:SetText((TRAINING_POINTS or "Training Points:") .. " "
                    .. Hex("text", "normal") .. ((total or 0) - (spent or 0)) .. "|r")
            else
                W.points:SetText("")
            end
        end
    end

    -- ------------------------------------------------------------
    -- TOOLBAR
    -- ------------------------------------------------------------
    local function SubClassItems()
        local items = { { text = ALL_SUBCLASSES or ALL or "All", value = 0 } }
        if GetTradeSkillSubClasses then
            for i, name in ipairs({ GetTradeSkillSubClasses() }) do
                items[#items + 1] = { text = name, value = i }
            end
        end
        return items
    end
    -- Blizzard's IsSelected: "All" wins while it is on.
    local function SubClassValue()
        if not GetTradeSkillSubClassFilter then return 0 end
        if On(GetTradeSkillSubClassFilter(0)) then return 0 end
        local items = SubClassItems()
        for k = 2, #items do
            if On(GetTradeSkillSubClassFilter(items[k].value)) then return items[k].value end
        end
        return 0
    end
    local function SlotItems()
        local items = { { text = ALL_INVENTORY_SLOTS or ALL or "All", value = 0 } }
        if GetTradeSkillInvSlots then
            for i, name in ipairs({ GetTradeSkillInvSlots() }) do
                items[#items + 1] = { text = name, value = i }
            end
        end
        return items
    end
    local function SlotValue()
        if not GetTradeSkillInvSlotFilter then return 0 end
        for _, it in ipairs(SlotItems()) do
            if On(GetTradeSkillInvSlotFilter(it.value)) then return it.value end
        end
        return 0
    end
    local function TextFor(items, value)
        for _, it in ipairs(items) do
            if it.value == value then return it.text end
        end
        return items[1] and items[1].text or ""
    end

    -- Right to left from the window edge, skipping whatever is hidden,
    -- then the search box takes the room that is left.
    local function LayoutToolbar()
        local prev
        -- Built without holes: the craft window has no dropdowns, and a
        -- nil first entry would end an ipairs walk before the chips.
        local order = {}
        for _, w in ipairs({ W.ddSlot or false, W.ddSub or false, W.chipSkill, W.chipMats }) do
            if w then order[#order + 1] = w end
        end
        for _, w in ipairs(order) do
            if w:IsShown() then
                w:ClearAllPoints()
                if prev then
                    w:SetPoint("RIGHT", prev, "LEFT", -4, 0)
                else
                    w:SetPoint("RIGHT", win, "TOPRIGHT", -Kit.PAD, TOOLBAR_MID)
                end
                prev = w
            end
        end
        W.search:ClearAllPoints()
        if W.collapse:IsShown() then
            W.search:SetPoint("LEFT", W.collapse, "RIGHT", 4, 0)
        else
            W.search:SetPoint("LEFT", win, "TOPLEFT", Kit.PAD, TOOLBAR_MID)
        end
        W.search:SetPoint("RIGHT", prev, "LEFT", -Kit.GAP, 0)
    end

    local function UpdateFilters()
        if not A.filters then return end
        local subs, slots = SubClassItems(), SlotItems()
        W.ddSub:SetShown(#subs > 1)
        W.ddSlot:SetShown(#slots > 1)
        W.ddSub:SetText(TextFor(subs, SubClassValue()))
        W.ddSlot:SetText(TextFor(slots, SlotValue()))
    end

    -- ------------------------------------------------------------
    -- DETAIL PANE
    -- ------------------------------------------------------------
    local function SetCreatable(ok)
        W.create:SetDisabled(not ok)
        if W.createAll then W.createAll:SetDisabled(not ok) end
    end

    local function HideDetail()
        detail.icon:Hide()
        detail.iconButton:Hide()
        detail.name:SetText("")
        detail.req:SetText("")
        detail.cd:SetText("")
        detail.desc:SetText("")
        detail.cost:SetText("")
        detail.label:Hide()
        for j = 1, MAX_REAGENTS do detail.reagents[j]:Hide() end
    end

    -- Stacked top-down with a running y rather than chained anchors: an
    -- empty line (no tools, no cooldown) then takes no room at all.
    local function UpdateDetail()
        local sel = A.Selected() or 0
        local name, kind, avail, _, sub, tp, reqLevel
        if sel > 0 and sel <= A.Num() then
            name, kind, avail, _, sub, tp, reqLevel = A.Info(sel)
        end
        if not name or kind == "header" then
            W.sel = nil
            HideDetail()
            detail.empty:Show()
            SetCreatable(false)
            W.numAvailable = 0
            return
        end
        detail.empty:Hide()
        W.sel = sel
        W.numAvailable = math.abs(avail or 0)

        local d = detail
        local textX = 8 + ICON_BIG + 8
        local y = -8

        d.icon:Show()
        d.iconButton:Show()
        d.icon:SetIcon(A.Icon(sel))
        local link = A.ItemLink(sel)
        local q = ItemQuality(link)
        d.icon:SetQuality(q)
        local minMade, maxMade = A.NumMade(sel)
        if maxMade and maxMade > 1 then
            d.icon.count:SetText((minMade == maxMade) and minMade or (minMade .. "-" .. maxMade))
        else
            d.icon.count:SetText("")
        end

        local shown = name
        if sub and sub ~= "" then
            shown = shown .. " " .. Hex("text", "gray") .. format(PARENS_TEMPLATE or "(%s)", sub) .. "|r"
        end
        d.name:SetText(shown)
        if q then d.name:SetTextColor(ns.QualityRGB(q)) else d.name:SetTextColor(Kit.TextRGB("gold")) end
        d.name:ClearAllPoints()
        d.name:SetPoint("TOPLEFT", d.pane, "TOPLEFT", textX, y)
        y = y - 16

        local req = A.Requires(sel, reqLevel)
        if req and req ~= "" then
            d.req:SetText((REQUIRES_LABEL or "Requires:") .. " " .. req)
            d.req:ClearAllPoints()
            d.req:SetPoint("TOPLEFT", d.pane, "TOPLEFT", textX, y)
            y = y - math.ceil(d.req:GetStringHeight()) - 3
        else
            d.req:SetText("")
        end

        local cd = A.Cooldown(sel)
        if cd and cd > 0 then
            local left = SecondsToTime and SecondsToTime(cd) or tostring(math.floor(cd))
            d.cd:SetText((COOLDOWN_REMAINING or "Cooldown remaining:") .. " " .. left)
            d.cd:ClearAllPoints()
            d.cd:SetPoint("TOPLEFT", d.pane, "TOPLEFT", textX, y)
            y = y - 14
        else
            d.cd:SetText("")
        end

        y = math.min(y, -(8 + ICON_BIG)) - 8

        local desc = A.Description(sel)
        if desc and desc ~= "" then
            d.desc:SetText(desc)
            d.desc:ClearAllPoints()
            d.desc:SetPoint("TOPLEFT", d.pane, "TOPLEFT", 8, y)
            y = y - math.ceil(d.desc:GetStringHeight()) - 8
        else
            d.desc:SetText("")
        end

        -- Beast Training: what the skill costs in training points.
        if (tp or 0) > 0 then
            local total, spent = 0, 0
            if GetPetTrainingPoints then total, spent = GetPetTrainingPoints() end
            local enough = ((total or 0) - (spent or 0)) >= tp
            d.cost:SetText((COSTS_LABEL or "Cost:") .. " "
                .. (enough and "" or Hex("text", "red")) .. tp .. (enough and "" or "|r")
                .. " " .. (TRAINING_POINTS_LABEL or "Training Points"))
            d.cost:ClearAllPoints()
            d.cost:SetPoint("TOPLEFT", d.pane, "TOPLEFT", 8, y)
            y = y - 18
        else
            d.cost:SetText("")
        end

        local creatable = true
        local numReagents = A.NumReagents(sel)
        d.label:SetShown(numReagents > 0)
        if numReagents > 0 then
            d.label:ClearAllPoints()
            d.label:SetPoint("TOPLEFT", d.pane, "TOPLEFT", 8, y)
            y = y - 16
        end
        local colW = math.floor((DETAIL_W - 16 - 6) / 2)
        for j = 1, MAX_REAGENTS do
            local r = d.reagents[j]
            local rName, rTex, need, have
            if j <= numReagents then rName, rTex, need, have = A.Reagent(sel, j) end
            if rName and rTex then
                need, have = need or 0, have or 0
                local col = (j - 1) % 2
                local rowN = math.floor((j - 1) / 2)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", d.pane, "TOPLEFT", 8 + col * (colW + 6), y - rowN * REAGENT_H)
                r:SetWidth(colW)
                r.icon:SetIcon(rTex)
                r.icon:SetQuality(ItemQuality(A.ReagentLink(sel, j)))
                r.name:SetText(rName)
                r.count:SetText(have .. " / " .. need)
                if have < need then
                    creatable = false
                    r.icon:SetDesaturated(true)
                    r.name:SetTextColor(Kit.TextRGB("gray"))
                    r.count:SetTextColor(Kit.TextRGB("red"))
                else
                    r.icon:SetDesaturated(false)
                    r.name:_zPaint()
                    r.count:SetTextColor(Kit.TextRGB("green"))
                end
                r:Show()
            else
                r:Hide()
            end
        end
        if kind == "used" then creatable = false end
        SetCreatable(creatable)
    end

    -- ------------------------------------------------------------
    -- FOOTER STATUS
    -- ------------------------------------------------------------
    local function BatchLeft()
        return (GetTradeskillRepeatCount and GetTradeskillRepeatCount()) or 0
    end

    local function UpdateStatus(total, shown, filtering)
        local parts = {}
        if filtering then
            parts[1] = shown .. " / " .. total .. " shown"
        else
            parts[1] = total .. (total == 1 and " recipe" or " recipes")
        end
        if W.batch then
            local casting = UnitCastingInfo and UnitCastingInfo("player")
            local left = BatchLeft()
            if casting or left > 1 then
                parts[#parts + 1] = "Creating: " .. left .. " left"
            else
                W.batch = nil
            end
        end
        if not W.secureBuilt or (W.tabsDirty and InCombatLockdown()) then
            parts[#parts + 1] = "Profession tabs update after combat"
        end
        W.status:SetText(table.concat(parts, "  |  "))
    end

    -- ------------------------------------------------------------
    -- REFRESH
    -- ------------------------------------------------------------
    local function Refresh()
        -- IsVisible, not IsShown: the cover is a shown child of the
        -- Blizzard frame all session.
        if not win or not win:IsVisible() then return end
        if W.tabsDirty and not InCombatLockdown() then BuildTabs() end

        local lineName = A.LineName()
        if lineName ~= W.lastLine then
            W.lastLine = lineName
            W.cache = nil
            list.offset = 0
        end
        local prof = ProfFor(lineName)
        win:SetTitle(lineName or A.title)
        win:SetIcon(prof and prof.icon or nil)

        UpdateRank()
        UpdateFilters()

        local data, total, shown, filtering, numHeaders, closed, selEntry = BuildData()
        W.collapse:SetShown(numHeaders > 0)
        -- Blizzard's "All" toggle: every header shut -> it expands all.
        W.allClosed = numHeaders > 0 and closed == numHeaders
        W.collapse:SetLabel(W.allClosed and "+" or "-")
        LayoutToolbar()

        list:SetEmptyText((total == 0 and not filtering) and "No recipes learned yet."
            or "Nothing matches.")
        list.selected = selEntry
        list:SetData(data, true)

        UpdateDetail()
        if W.sel ~= W.lastSel then
            W.lastSel = W.sel
            if W.qty then W.qty.editBox:SetNumber(math.max(1, BatchLeft())) end
        end
        W.create:SetLabel(A.ButtonLabel())
        UpdateStatus(total, shown, filtering)
        SyncTabs()
    end
    W.Refresh = Refresh

    W.Queue = Kit.Coalesce(Refresh, function() return win end)

    -- ------------------------------------------------------------
    -- LIST ROWS
    -- ------------------------------------------------------------
    local function RowTooltip(row)
        local e = row.item
        if not e or e.header then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        A.TooltipRecipe(e.index)
        GameTooltip:Show()
    end

    local function BuildRow(row)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.toggle = UI.Font(row, F.LABEL, { cat = "text", key = "gray", justify = "CENTER" })
        row.toggle:SetPoint("LEFT", 2, 0)
        row.toggle:SetWidth(12)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon._zui_own = true
        icon:SetSize(LIST_ROW_H - 4, LIST_ROW_H - 4)
        icon:SetPoint("LEFT", 16, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        SharpenIcon(icon)
        row.icon = icon

        row.right = UI.Font(row, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
        row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.right:SetWordWrap(false)

        row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
        row.nameText:SetWordWrap(false)

        row:SetScript("OnEnter", RowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.UpdateTooltip = RowTooltip

        row:SetScript("OnClick", function(self, button)
            local e = self.item
            if not e then return end
            if e.header then
                if button == "LeftButton" then
                    if e.expanded then A.Collapse(e.index) else A.Expand(e.index) end
                end
                return
            end
            if A.RowModifiedClick(e.index) then return end
            if button == "LeftButton" then
                A.Select(e.index)
                Refresh()
            end
        end)
    end

    local function UpdateRow(row, e)
        row.nameText:ClearAllPoints()
        if e.header then
            row.toggle:SetText(e.expanded and "-" or "+")
            row.toggle:Show()
            row.icon:Hide()
            row.nameText:SetPoint("LEFT", row.toggle, "RIGHT", 2, 0)
            row.nameText:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
            row.nameText:SetText(e.name)
            local c = A.Color("header")
            if c then row.nameText:SetTextColor(c.r, c.g, c.b) else row.nameText:SetTextColor(Kit.TextRGB("gold")) end
            row.right:SetText("")
            return
        end
        row.toggle:Hide()
        row.icon:SetTexture(A.Icon(e.index))
        row.icon:Show()
        row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.nameText:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
        -- Blizzard's own "[n]" for how many you can make right now.
        if e.avail and e.avail ~= 0 then
            row.nameText:SetText(e.name .. " [" .. e.avail .. "]")
        else
            row.nameText:SetText(e.name)
        end
        local c = A.Color(e.kind)
        if c then row.nameText:SetTextColor(c.r, c.g, c.b) else row.nameText:_zPaint() end
        local bits = {}
        if e.sub and e.sub ~= "" then bits[#bits + 1] = format(PARENS_TEMPLATE or "(%s)", e.sub) end
        if e.tp and e.tp > 0 then
            bits[#bits + 1] = TRAINER_LIST_TP and format(TRAINER_LIST_TP, e.tp) or (e.tp .. " TP")
        end
        row.right:SetText(table.concat(bits, " "))
    end

    -- ------------------------------------------------------------
    -- REAGENT + PRODUCT BUTTONS
    -- ------------------------------------------------------------
    local function ReagentTooltip(self)
        if not W.sel then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        A.TooltipReagent(W.sel, self._zIndex)
        Hover(self)
    end

    local function NewReagent(pane, j)
        local r = CreateFrame("Button", nil, pane)
        r:SetHeight(REAGENT_H - 2)
        r._zIndex = j
        r.hasItem = 1   -- what CursorUpdate reads for the dress-up cursor
        r.icon = Kit.Icon(r, REAGENT_H - 4)
        r.icon:SetPoint("LEFT", 0, 0)
        r.name = UI.Font(r, F.SMALL, { justify = "LEFT" })
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 5, -2)
        r.name:SetPoint("RIGHT", r, "RIGHT", -2, 0)
        r.name:SetWordWrap(false)
        r.name:SetJustifyV("TOP")
        r.count = UI.Font(r, F.SMALL, { justify = "LEFT" })
        r.count:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 5, 2)
        r.count:SetPoint("RIGHT", r, "RIGHT", -2, 0)
        r.count:SetWordWrap(false)
        r.count:SetJustifyV("BOTTOM")
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl._zui_own = true
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.07)
        r:SetScript("OnEnter", ReagentTooltip)
        r:SetScript("OnLeave", Unhover)
        r.UpdateTooltip = ReagentTooltip
        r:SetScript("OnClick", function(self)
            if W.sel then A.ReagentClick(W.sel, self._zIndex) end
        end)
        r:Hide()
        return r
    end

    local function ProductTooltip(self)
        if not W.sel then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        A.TooltipProduct(W.sel)
        Hover(self)
    end

    -- ------------------------------------------------------------
    -- BUILD
    -- ------------------------------------------------------------
    local function Build()
        if win then return win end
        local host = A.Host()
        win = Kit.Cover(host, {
            name = A.frameName,
            title = A.title,
            insetName = A.hostName,
            width = WIN_W,
            -- Only until the secure X exists (out of combat), which then
            -- sits over this one and clicks Blizzard's close button. An
            -- addon's HideUIPanel is refused in combat, so a fight ends
            -- the session instead and Blizzard's close event hides it.
            onClose = function()
                if InCombatLockdown() then A.EndSession() else HideUIPanel(host) end
            end,
        })
        W.win = win

        W.tabStrip = CreateFrame("Frame", nil, win)
        W.tabStrip:SetHeight(Kit.TAB_H)
        W.tabStrip:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, TABS_Y)
        W.tabStrip:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, TABS_Y)

        -- Rank bar: flat, the skill-bar colour from the palette.
        local bar = CreateFrame("StatusBar", nil, win)
        bar:SetHeight(RANK_H)
        bar:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, RANK_Y)
        bar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, RANK_Y)
        bar:SetStatusBarTexture(FLAT)
        local bt = bar:GetStatusBarTexture()
        if bt then bt._zui_own = true end
        bar:SetMinMaxValues(0, 1)
        UI.Fill(bar, "ui", "elementBg")
        UI.Border(bar, "ui", "border")
        W.rankName = UI.Font(bar, F.SMALL, { justify = "LEFT" })
        W.rankName:SetPoint("LEFT", 6, 0)
        W.rankName:SetWordWrap(false)
        W.rankValue = UI.Font(bar, F.SMALL, { justify = "RIGHT" })
        W.rankValue:SetPoint("RIGHT", -6, 0)
        W.rankValue:SetWordWrap(false)
        bar._zPaint = function(self)
            UI.PaintBox(self)
            local c = GetColor("text", "blue")
            self:SetStatusBarColor(c.r, c.g, c.b, 0.55)
            W.rankName:_zPaint()
            W.rankValue:_zPaint()
        end
        bar:_zPaint()
        W.rankBar = bar
        -- Beast Training has no rank; its training points sit here instead.
        W.points = UI.Font(win, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
        W.points:SetPoint("LEFT", win, "TOPLEFT", Kit.PAD, RANK_Y - RANK_H / 2)
        W.points:SetWordWrap(false)

        -- Toolbar ------------------------------------------------
        W.collapse = UI.Button(win, "-", { width = 22, height = Kit.SEARCH_H,
            tooltip = "Expand or collapse every category.", tooltipTitle = ALL or "All" })
        W.collapse:SetPoint("LEFT", win, "TOPLEFT", Kit.PAD, TOOLBAR_MID)
        W.collapse:SetScript("OnClick", function()
            if W.allClosed then
                A.Expand(0)
            else
                list.offset = 0
                A.Collapse(0)
            end
        end)

        W.chipMats = Kit.Chip(win, "Have materials", false, function()
            list.offset = 0
            Refresh()
        end, "Only recipes you have every reagent for right now.")
        W.chipSkill = Kit.Chip(win, "Skill-ups", false, function()
            list.offset = 0
            Refresh()
        end, "Hide grey recipes - the ones that can no longer raise your skill.")

        if A.filters then
            W.ddSub = UI.Dropdown(win, {
                width = 108,
                items = SubClassItems,
                selectedValue = SubClassValue,
                selected = function() return TextFor(SubClassItems(), SubClassValue()) end,
                onSelect = function(value)
                    -- Blizzard's own call from its dropdown: on, exclusive.
                    SetTradeSkillSubClassFilter(value, 1, 1)
                    list.offset = 0
                    W.Queue()
                end,
            })
            W.ddSlot = UI.Dropdown(win, {
                width = 108,
                items = SlotItems,
                selectedValue = SlotValue,
                selected = function() return TextFor(SlotItems(), SlotValue()) end,
                onSelect = function(value)
                    SetTradeSkillInvSlotFilter(value, 1, 1)
                    list.offset = 0
                    W.Queue()
                end,
            })
        end

        W.search = Kit.Search(win, 100, function(text)
            W.query = Kit.NormalizeQuery(text)
            list.offset = 0
            Refresh()
        end, "Search recipes or reagents")

        -- Footer -------------------------------------------------
        footer = Kit.Footer(win, Kit.FOOTER_H)
        W.footer = footer

        W.create = UI.Button(footer, A.ButtonLabel(), { width = BTN_W })
        W.create:SetPoint("RIGHT", footer, "RIGHT", -6, 0)
        W.create:SetScript("OnClick", function()
            if not W.sel then return end
            if A.batch then
                local n = math.max(1, W.qty.editBox:GetNumber() or 1)
                W.batch = (n > 1) and true or nil
                A.Do(W.sel, n)
                W.qty.editBox:ClearFocus()
            else
                A.Do(W.sel)
            end
            W.Queue()
        end)

        if A.batch then
            W.inc = UI.Button(footer, "+", { width = 22 })
            W.inc:SetPoint("RIGHT", W.create, "LEFT", -4, 0)
            W.qty = UI.EditBox(footer, { width = 34, height = M.BUTTON_H })
            W.qty:SetPoint("RIGHT", W.inc, "LEFT", -3, 0)
            local eb = W.qty.editBox
            eb:SetNumeric(true)
            eb:SetMaxLetters(3)
            eb:SetJustifyH("CENTER")
            eb:SetNumber(1)
            -- Blizzard's TradeSkillInputBox: 0 is never a quantity.
            eb:HookScript("OnTextChanged", function(self)
                if self:GetText() == "0" then self:SetText("1") end
            end)
            eb:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
            eb:HookScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
            W.dec = UI.Button(footer, "-", { width = 22 })
            W.dec:SetPoint("RIGHT", W.qty, "LEFT", -3, 0)
            W.inc:SetScript("OnClick", function()
                local n = eb:GetNumber() or 1
                if n < 100 then eb:SetNumber(n + 1) end
                eb:ClearFocus()
            end)
            W.dec:SetScript("OnClick", function()
                local n = eb:GetNumber() or 1
                if n > 1 then eb:SetNumber(n - 1) end
                eb:ClearFocus()
            end)
            W.createAll = UI.Button(footer, CREATE_ALL or "Create All", { width = BTN_W })
            W.createAll:SetPoint("RIGHT", W.dec, "LEFT", -6, 0)
            W.createAll:SetScript("OnClick", function()
                if not W.sel then return end
                local n = W.numAvailable or 0
                if n < 1 then return end
                eb:SetNumber(n)
                W.batch = (n > 1) and true or nil
                A.Do(W.sel, n)
                eb:ClearFocus()
                W.Queue()
            end)
        end

        W.status = UI.Font(footer, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
        W.status:SetPoint("LEFT", footer, "LEFT", 8, 0)
        W.status:SetPoint("RIGHT", W.createAll or W.create, "LEFT", -8, 0)
        W.status:SetWordWrap(false)

        -- Body: list left, detail right ---------------------------
        list = Kit.List(win, {
            rowHeight = LIST_ROW_H,
            build = BuildRow,
            update = UpdateRow,
            wheelStep = 3,
        })
        list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, BODY_Y)
        list:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", Kit.PAD - 1, Kit.GAP)
        list:SetWidth(LIST_W)
        W.list = list

        local pane = UI.Box(win, "ui", "cardBg")
        pane:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD + LIST_W + COL_GAP, BODY_Y)
        pane:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -(Kit.PAD - 1), Kit.GAP)
        -- A long description must end at the pane's edge, not over the footer.
        if pane.SetClipsChildren then pane:SetClipsChildren(true) end
        detail = { pane = pane, reagents = {} }
        W.detail = detail

        local textW = DETAIL_W - (8 + ICON_BIG + 8) - 8
        detail.icon = Kit.Icon(pane, ICON_BIG)
        detail.icon:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, -8)
        local ib = CreateFrame("Button", nil, pane)
        ib:SetAllPoints(detail.icon)
        ib.hasItem = 1
        ib:SetScript("OnEnter", ProductTooltip)
        ib:SetScript("OnLeave", Unhover)
        ib.UpdateTooltip = ProductTooltip
        ib:SetScript("OnClick", function() if W.sel then A.ProductClick(W.sel) end end)
        detail.iconButton = ib

        detail.name = UI.Font(pane, F.CARD, { justify = "LEFT" })
        detail.name:SetWidth(textW)
        detail.name:SetWordWrap(false)
        detail.req = UI.Font(pane, F.SMALL, { justify = "LEFT", width = textW })
        detail.cd = UI.Font(pane, F.SMALL, { justify = "LEFT", cat = "text", key = "red" })
        detail.cd:SetWidth(textW)
        detail.cd:SetWordWrap(false)
        detail.desc = UI.Font(pane, F.SMALL, { justify = "LEFT", width = DETAIL_W - 16 })
        detail.cost = UI.Font(pane, F.SMALL, { justify = "LEFT" })
        detail.cost:SetWidth(DETAIL_W - 16)
        detail.cost:SetWordWrap(false)
        detail.label = UI.Font(pane, F.SMALL, { cat = "text", key = "gold",
            text = SPELL_REAGENTS or "Reagents:" })
        detail.empty = UI.Font(pane, F.LABEL, { cat = "text", key = "gray", justify = "CENTER",
            text = "Select a recipe." })
        detail.empty:SetPoint("TOP", pane, "TOP", 0, -40)
        for j = 1, MAX_REAGENTS do detail.reagents[j] = NewReagent(pane, j) end
        HideDetail()
        -- Anchored now as well as on every redraw: nothing may sit
        -- unanchored for the frame before the first refresh lands.
        W.collapse:Hide()
        LayoutToolbar()

        -- Events -------------------------------------------------
        local ev = CreateFrame("Frame", nil, win)
        for _, e in ipairs(A.events) do pcall(ev.RegisterEvent, ev, e) end
        ev:RegisterEvent("BAG_UPDATE_DELAYED")
        ev:RegisterEvent("SKILL_LINES_CHANGED")
        ev:RegisterEvent("SPELLS_CHANGED")
        ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        if A.batch then
            for _, e in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
                                 "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
                pcall(ev.RegisterUnitEvent, ev, e, "player")
            end
        end
        ev:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_ENABLED" then
                if W.pendingApply then
                    W.pendingApply = nil
                    W.Apply()
                end
                if not W.secureBuilt and win:IsShown() and Enabled(A) then BuildSecure() end
                if W.tabsDirty then BuildTabs() end
                W.Queue()
                return
            end
            if event == "SPELLS_CHANGED" or event == "SKILL_LINES_CHANGED" then
                -- The book is re-read (and the tabs rebuilt) on the next
                -- redraw, not per event: SPELLS_CHANGED comes in bursts.
                profDirty = true
                W.tabsDirty = true
                W.Queue()
                return
            end
            if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
                W.batch = nil
            elseif event == A.closeEvent then
                W.batch = nil
            end
            if A.listEvents[event] or event == "GET_ITEM_INFO_RECEIVED" then W.cache = nil end
            -- Bag and item-info storms in a raid: nothing below matters to
            -- a window nobody sees (the cover is shown all session, so
            -- IsVisible is the real test).
            if not win:IsVisible() then return end
            if event == "UPDATE_TRADESKILL_RECAST" then
                -- Blizzard mirrors the remaining repeat count in its box.
                if W.qty then W.qty.editBox:SetNumber(math.max(1, BatchLeft())) end
            end
            W.Queue()
        end)

        win:HookScript("OnShow", function()
            W.query = ""
            W.search:SetText("")
            W.lastSel = nil
            if W.qty then W.qty.editBox:SetNumber(1) end
            W.Queue()
        end)
        win:HookScript("OnHide", function()
            W.batch = nil
            if W.ddSub then W.ddSub.Close() end
            if W.ddSlot then W.ddSlot.Close() end
        end)
        return win
    end

    -- ------------------------------------------------------------
    -- APPLY (open / module toggle)
    -- ------------------------------------------------------------
    -- Once the secure pieces exist the window is protected: in combat it
    -- is neither re-anchored nor shown/hidden by us - the change waits
    -- for PLAYER_REGEN_ENABLED. It is a shown child already, so an open
    -- in combat still shows it.
    function W.Apply()
        local host = A.Host()
        if not host then return end
        local locked = InCombatLockdown() and W.secureBuilt
        if Enabled(A) then
            Build()
            if locked then
                W.pendingApply = true
            else
                win.Reanchor()
                win:Show()
                BuildSecure()
            end
            Kit.Silence(Leftovers(A))
            if host:IsShown() then W.Queue() end
        elseif win then
            if locked then
                W.pendingApply = true
                return
            end
            win:Hide()
            Kit.Unsilence(Leftovers(A))
        end
    end

    -- ------------------------------------------------------------
    -- SETUP (the Blizzard addon is loaded)
    -- ------------------------------------------------------------
    function W.Setup()
        if W.setup then return end
        local host = A.Host()
        if not host then return end
        W.setup = true
        W.Apply()
        -- A /zui toggle only flips the saved flag; every open checks it.
        host:HookScript("OnShow", function()
            W.Apply()
            W.Queue()
            if W.OnOpened then W.OnOpened() end
        end)
    end

    return W
end

-- ============================================================
-- MODULES
-- ============================================================
-- ns.RegisterLoD keeps ONE callback per Blizzard addon, and the
-- "panels" skin registers these same two addons: a plain second
-- registration would replace the skin (or be replaced by it). So ours
-- chains onto whatever is already parked, and a private ADDON_LOADED
-- watcher covers a registration made after ours. Setup is idempotent,
-- so running from both paths is harmless.
local function WhenLoaded(addonName, fn)
    local parked = ns.LOD and ns.LOD[addonName]
    if parked then
        ns.RegisterLoD(addonName, function()
            local ok, err = pcall(parked)
            if not ok and ns.Print then ns.Print(addonName .. " skin failed: " .. tostring(err)) end
            fn()
        end)
    else
        ns.RegisterLoD(addonName, fn)
    end
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded(addonName) then return end
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("ADDON_LOADED")
    watch:SetScript("OnEvent", function(self, _, name)
        if name ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        -- A frame later, so Blizzard's own OnLoad and the drain of the
        -- LoD registry have both run first.
        C_Timer.After(0, function()
            local ok, err = pcall(fn)
            if not ok and ns.Print then ns.Print(addonName .. " window failed: " .. tostring(err)) end
        end)
    end)
end

local tradeWin = NewWindow(TRADE)
local craftWin = NewWindow(CRAFT)

-- ONE PROFESSION WINDOW AT A TIME. The tabs close the other window type
-- before casting, but a cast from an action bar or a macro does not:
-- Blizzard then lays both panels side by side at its own panel width,
-- and at WIN_W the two covers overlap. So the one that opened closes the
-- other. A frame later (this runs inside Blizzard's ShowUIPanel) and
-- only out of combat, where an addon's HideUIPanel is allowed - in a
-- fight the older window just stays until it is closed.
local function CloseBeside(opened, other)
    C_Timer.After(0, function()
        if InCombatLockdown() then return end
        local a, b = opened.A.Host(), other.A.Host()
        if not (a and b and a:IsShown() and b:IsShown()) then return end
        if not (Enabled(opened.A) or Enabled(other.A)) then return end
        HideUIPanel(b)
    end)
end
tradeWin.OnOpened = function() CloseBeside(tradeWin, craftWin) end
craftWin.OnOpened = function() CloseBeside(craftWin, tradeWin) end

Modules.tradeskillwin = function()
    if ns._zTradeSkillWin then return end
    ns._zTradeSkillWin = true
    WhenLoaded(TRADE.lod, tradeWin.Setup)
end

Modules.craftwin = function()
    if ns._zCraftWin then return end
    ns._zCraftWin = true
    WhenLoaded(CRAFT.lod, craftWin.Setup)
end
