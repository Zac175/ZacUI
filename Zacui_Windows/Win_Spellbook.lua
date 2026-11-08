-- Win_Spellbook - ZacUI's spellbook: every spell in one searchable list,
-- filtered by school, instead of Blizzard's twelve-per-page grid.
-- Part of ZacUI; load order is set by the TOC.
--
-- CASTING NEEDS SECURE BUTTONS, AND SECURE BUTTONS SET THE RULES.
-- CastSpell is protected, so every row is a SecureActionButton carrying
-- the spell as an attribute - a click casts exactly like Blizzard's own
-- button, in or out of combat. What the client does NOT allow is
-- re-pointing a secure button at another spell while you are fighting,
-- so in combat the list is frozen as it was: rows still cast, but
-- searching, scrolling and switching school wait until the fight ends,
-- and the footer says so. Out of combat everything is instant.
--
-- The window is a Win_Kit cover inside SpellBookFrame, so the P key,
-- Escape and the micro button open and close it through Blizzard's own
-- secure code - including in combat, where an addon could not.
--
--   Click              cast (pet spells: left cast, right toggle autocast)
--   Drag               put the spell on an action bar
--   Shift-click        link it in chat

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local UI = ns.UI
-- WoW Forever: every rank from its own book data (Win_SpellbookForever;
-- nil on every other game, where nothing below changes)
local FB = ns.SpellbookForever

local M, F = UI.M, UI.F

local BOOK_SPELL = BOOKTYPE_SPELL or "spell"
local BOOK_PET = BOOKTYPE_PET or "pet"

local win, list, bookTabs, schoolBar, search, chipRanks, chipPassive, status
local book = BOOK_SPELL
local school = 0          -- 0 = every school
local query = ""
local schoolButtons = {}

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.spellbookwin ~= false
end

-- WHERE THE BOOK LIVES. Classic Era and TBC: SpellBookFrame, and the
-- cover is its child. WoW Forever has the modern book instead (2026-11-07,
-- Zac: "these menus are not styled"): PlayerSpellsFrame (load on demand),
-- whose SpellBookFrame page sits at frame level 100 under a title bar at
-- 510 - so the cover hangs on PlayerSpellsFrame above all of that
-- (minLevel) and follows the page's own show and hide. Talents (N) are
-- another page of the same window and show as Blizzard's when picked.
local MODERN = false
local function Host()
    if SpellBookFrame then return SpellBookFrame end
    MODERN = PlayerSpellsFrame ~= nil and PlayerSpellsFrame.SpellBookFrame ~= nil
    return MODERN and PlayerSpellsFrame or nil
end

-- ============================================================
-- API SHIMS (1.15 has the SpellBookItem names; keep the old ones as a
-- fallback so a client change is a degraded list, not a Lua error)
-- ============================================================
local GetItemName = GetSpellBookItemName or GetSpellName
local GetItemTexture = GetSpellBookItemTexture or GetSpellTexture
local GetItemInfo = GetSpellBookItemInfo

local function SpellSubtext(spellID, fallback)
    if fallback and fallback ~= "" then return fallback end
    if spellID and GetSpellSubtext then
        local s = GetSpellSubtext(spellID)
        if s and s ~= "" then return s end
    end
    return ""
end

-- Warriors and rogues have no ranks worth showing; Blizzard hides the
-- checkbox for them and so do we.
local function ClassHasRanks()
    local _, class = UnitClass("player")
    return class ~= "WARRIOR" and class ~= "ROGUE"
end

-- ============================================================
-- DATA
-- ============================================================
local function Entry(slot, bookType, schoolName, schoolIndex)
    local name, sub, spellID = GetItemName(slot, bookType)
    if not name then return nil end
    local slotType
    if GetItemInfo then slotType = GetItemInfo(slot, bookType) end
    -- Future spells are unlearned; PETACTION entries (Attack, Follow,
    -- Stay) are pet-bar commands, not spells a button can cast by name.
    if slotType == "FUTURESPELL" or slotType == "PETACTION" then return nil end
    if IsSpellHidden and IsSpellHidden(slot, bookType) then return nil end
    local tex = GetItemTexture(slot, bookType)
    if not tex then return nil end
    local passive = IsPassiveSpell and IsPassiveSpell(slot, bookType) or false
    local rank = SpellSubtext(spellID, sub)
    local e = {
        slot = slot, book = bookType, name = name, rank = rank,
        spellID = spellID, icon = tex, passive = passive and true or false,
        school = schoolName, schoolIndex = schoolIndex,
    }
    if bookType == BOOK_PET and GetSpellAutocast then
        e.autoAllowed, e.autoOn = GetSpellAutocast(slot, bookType)
    end
    return e
end

local function Rows()
    local data = {}
    local hidePassive = chipPassive and chipPassive:IsOn()
    local function Add(e)
        if not e then return end
        if hidePassive and e.passive then return end
        if not Kit.Matches(query, e.name, e.rank, e.school) then return end
        data[#data + 1] = e
    end
    if FB then
        for _, e in ipairs(FB.Entries(book == BOOK_PET, school)) do Add(e) end
    elseif book == BOOK_PET then
        local n = HasPetSpells and HasPetSpells() or 0
        for slot = 1, n or 0 do Add(Entry(slot, BOOK_PET, PET or "Pet", 0)) end
    else
        for t = 1, GetNumSpellTabs() do
            local tabName, _, offset, numSlots = GetSpellTabInfo(t)
            if school == 0 or school == t then
                for slot = offset + 1, offset + numSlots do
                    Add(Entry(slot, BOOK_SPELL, tabName, t))
                end
            end
        end
    end
    return data
end

-- ============================================================
-- STATUS LINE
-- ============================================================
local function UpdateStatus()
    if not status then return end
    if InCombatLockdown() then
        status:SetText("In combat - the list is locked until it ends.")
        status:SetTextColor(Kit.TextRGB("red"))
    elseif book == BOOK_PET then
        status:SetText("Click to cast  |  Right-click toggles autocast  |  Drag to a bar")
        status:_zPaint()
    else
        status:SetText("Click to cast  |  Drag to a bar  |  Shift-click to link")
        status:_zPaint()
    end
end

-- ============================================================
-- SCHOOL BAR (icon per spell tab, plus "All")
-- ============================================================
local function PaintSchools()
    for i, b in ipairs(schoolButtons) do
        b:SetActive(b._zSchool == school)
    end
end

local Refresh

local function BuildSchools()
    if InCombatLockdown() then return end
    for _, b in ipairs(schoolButtons) do b:Hide() end
    local isPet = (book == BOOK_PET)
    schoolBar:SetShown(not isPet)
    if isPet then return end

    local all = schoolButtons[1]
    if not all then
        all = UI.Button(schoolBar, ALL or "All", { height = 24, width = 40, size = F.SMALL })
        all._zSchool = 0
        all:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            school = 0
            PaintSchools()
            Refresh()
        end)
        all:SetPoint("LEFT", schoolBar, "LEFT", 0, 0)
        schoolButtons[1] = all
    end
    all:Show()

    local prev = all
    -- (Forever: only the lines its own book shows; the line's index is the school)
    local lines = FB and FB.Lines() or nil
    local valid = lines and {} or nil
    for t = 1, lines and #lines or GetNumSpellTabs() do
        local tabName, tex
        if lines then tabName, tex = lines[t].name, lines[t].icon
        else tabName, tex = GetSpellTabInfo(t) end
        local b = schoolButtons[t + 1]
        if not b then
            b = Kit.IconButton(schoolBar, 24, tex, tabName, nil, nil)
            b:SetScript("OnClick", function(self)
                if InCombatLockdown() then return end
                school = self._zSchool
                PaintSchools()
                Refresh()
            end)
            schoolButtons[t + 1] = b
        end
        b.icon:SetTexture(tex)
        b._zSchool = lines and lines[t].index or t
        if valid then valid[b._zSchool] = true end
        -- The tooltip title is captured at creation; keep it current.
        b._zTitle = tabName
        b:ClearAllPoints()
        b:SetPoint("LEFT", prev, "RIGHT", 3, 0)
        b:Show()
        prev = b
    end
    if valid then
        if school ~= 0 and not valid[school] then school = 0 end
    elseif school > GetNumSpellTabs() then school = 0 end
    PaintSchools()
end

-- ============================================================
-- ROWS
-- ============================================================
local function CastName(e)
    -- (Forever: the spell id, so a lower rank casts that rank)
    if e.castValue then return e.castValue end
    if e.rank and e.rank ~= "" and e.book == BOOK_SPELL then
        return e.name .. "(" .. e.rank .. ")"
    end
    return e.name
end

local function UpdateCooldown(row)
    local e = row.item
    local cd = row.icon.cooldown
    if not e or not cd then return end
    local start, duration, enable
    if _G.ZACUI_MODERN then
        -- (the modern client has no spellbook-slot form: its GetSpellCooldown takes the spell)
        if e.spellID then start, duration, enable = GetSpellCooldown(e.spellID) end
    else
        start, duration, enable = GetSpellCooldown(e.slot, e.book)
    end
    if CooldownFrame_Set then
        CooldownFrame_Set(cd, start or 0, duration or 0, enable or 0)
    elseif start and duration and duration > 0 then
        cd:SetCooldown(start, duration)
    else
        cd:Hide()
    end
end

local function RowTooltip(row)
    local e = row.item
    if not e then return end
    if FB then return FB.Tooltip(row, e) end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetSpellBookItem then
        GameTooltip:SetSpellBookItem(e.slot, e.book)
    elseif GameTooltip.SetSpell then
        GameTooltip:SetSpell(e.slot, e.book)
    end
    GameTooltip:Show()
end

local function BuildRow(row)
    -- Act on RELEASE, whatever ActionButtonUseKeyDown says: a row that
    -- casts on press would cast the spell every time you start dragging
    -- it to a bar. useOnKeyDown is the per-button override for exactly
    -- this, and it pairs with registering the up-click only.
    row:SetAttribute("useOnKeyDown", false)
    row:RegisterForClicks("AnyUp")
    row:RegisterForDrag("LeftButton")
    local rh = Kit.ROW_H

    row.icon = Kit.Icon(row, rh - 4, { cooldown = true })
    row.icon:SetPoint("LEFT", 3, 0)
    row.icon:EnableMouse(false)

    row.auto = UI.Font(row, F.SMALL, { justify = "RIGHT", cat = "text", key = "gray" })
    row.auto:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, -2)
    row.nameText:SetPoint("RIGHT", row.auto, "LEFT", -6, 0)
    row.nameText:SetWordWrap(false)
    row.nameText:SetJustifyV("TOP")

    row.sub = UI.Font(row, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, 2)
    row.sub:SetPoint("RIGHT", row.auto, "LEFT", -6, 0)
    row.sub:SetWordWrap(false)
    row.sub:SetJustifyV("BOTTOM")

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.UpdateTooltip = RowTooltip

    -- Linking rides after the secure click. The shift click itself does
    -- nothing secure: shift-type1 points at a type with no handler.
    row:HookScript("OnClick", function(self, _, down)
        if down then return end
        local e = self.item
        if not e then return end
        if IsModifiedClick("CHATLINK") then
            local link = GetSpellLink and ((not _G.ZACUI_MODERN and GetSpellLink(e.slot, e.book)) or (e.spellID and GetSpellLink(e.spellID)))
            local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
            if link and insert then insert(link) end
        end
    end)

    row:SetScript("OnDragStart", function(self)
        local e = self.item
        if not e or e.passive then return end
        if FB then
            FB.Pickup(e)
        elseif PickupSpellBookItem then
            pcall(PickupSpellBookItem, e.slot, e.book)
        elseif PickupSpell then
            pcall(PickupSpell, e.slot, e.book)
        end
    end)
end

local function UpdateRow(row, e)
    -- Only ever reached out of combat: Kit.List queues secure redraws.
    if e.passive then
        row:SetAttribute("type", nil)
        row:SetAttribute("spell", nil)
    else
        row:SetAttribute("type", "spell")
        row:SetAttribute("spell", CastName(e))
    end
    row:SetAttribute("shift-type1", "zacui-link")
    if e.book == BOOK_PET and e.autoAllowed then
        row:SetAttribute("type2", "macro")
        row:SetAttribute("macrotext2", "/petautocasttoggle " .. e.name)
    else
        row:SetAttribute("type2", nil)
        row:SetAttribute("macrotext2", nil)
    end

    row.icon:SetIcon(e.icon)
    row.icon:SetCount(nil)
    row.icon:SetQuality(nil)
    row.icon:SetDesaturated(e.passive)
    row.icon:SetUsable(true)

    row.nameText:SetText(e.name)
    if e.passive then
        row.nameText:SetTextColor(Kit.TextRGB("gray"))
    else
        row.nameText:_zPaint()
    end

    local bits = {}
    if e.rank and e.rank ~= "" then bits[#bits + 1] = e.rank end
    if e.passive and e.rank ~= (SPELL_PASSIVE or "Passive") then
        bits[#bits + 1] = SPELL_PASSIVE or "Passive"
    end
    if school == 0 and e.book == BOOK_SPELL and e.school then bits[#bits + 1] = e.school end
    row.sub:SetText(table.concat(bits, "  |  "))

    if e.book == BOOK_PET and e.autoAllowed then
        row.auto:SetText(e.autoOn and "Auto" or "")
        if e.autoOn then row.auto:SetTextColor(Kit.TextRGB("green")) end
    else
        row.auto:SetText("")
    end
    UpdateCooldown(row)
end

-- ============================================================
-- REFRESH
-- ============================================================
-- Runs whether or not the book is open: the rows are secure, so they can
-- only be built and pointed at spells out of combat. Keeping them primed
-- while the book is shut is what lets a first open IN combat still show
-- (and cast) your spells.
function Refresh(keepOffset)
    if not win then return end
    UpdateStatus()
    if InCombatLockdown() then
        win._zStale = true
        return
    end
    win._zStale = nil
    local hasPet
    if FB then hasPet = FB.PetCount() else hasPet = HasPetSpells and HasPetSpells() end
    bookTabs:SetShownKey("pet", hasPet and hasPet > 0)
    if book == BOOK_PET and not (hasPet and hasPet > 0) then
        book = BOOK_SPELL
        bookTabs:Select("spell")
        return
    end
    local ranks = book == BOOK_SPELL and ClassHasRanks()
    chipRanks:SetShown(ranks)
    if GetCVarBool then chipRanks:SetOn(GetCVarBool("ShowAllSpellRanks")) end
    -- The search box runs up to whichever chip is showing, so warriors
    -- and rogues (no ranks chip) get no hole in the toolbar.
    search:SetPoint("RIGHT", ranks and chipRanks or chipPassive, "LEFT", -Kit.GAP, 0)
    local data = Rows()
    list:SetEmptyText(query ~= "" and "Nothing matches." or "No spells here yet.")
    list:SetData(data, keepOffset)
end

-- One redraw per frame. Deliberately NOT gated on the book being open:
-- the rows are secure and are primed while it is shut (see Refresh).
-- The school buttons are rebuilt with it, not per event - SPELLS_CHANGED
-- and PET_BAR_UPDATE come in bursts.
local queuedKeep, schoolsDirty = true, false
local runQueued = ns.Coalescer(function()
    local keep = queuedKeep
    queuedKeep = true
    if schoolsDirty and not InCombatLockdown() then
        schoolsDirty = false
        BuildSchools()
    end
    Refresh(keep)
end, 0)
local function Queue(keepOffset)
    if keepOffset == false then queuedKeep = false end
    runQueued()
end

local function UpdateVisibleCooldowns()
    if not list then return end
    for _, row in ipairs(list.rows) do
        if row:IsShown() and row.item then UpdateCooldown(row) end
    end
end

-- ============================================================
-- BUILD
-- ============================================================
local function Build()
    if win then return win end
    local host = Host()
    win = Kit.Cover(host, {
        name = "ZacUISpellbookWindow",
        title = SPELLBOOK or "Spellbook",
        insetName = MODERN and "PlayerSpellsFrame" or "SpellBookFrame",
        onClose = function() HideUIPanel(host) end,
        minLevel = MODERN and 700 or nil,
    })
    win:SetIcon("Interface\\Icons\\INV_Misc_Book_09")

    bookTabs = Kit.Tabs(win, {
        { key = "spell", label = SPELLBOOK or "Spells" },
        { key = "pet",   label = PET or "Pet" },
    }, function(key)
        if InCombatLockdown() then
            -- Refused: snap the highlight back to the book on screen.
            bookTabs:Paint(book == BOOK_PET and "pet" or "spell")
            return
        end
        book = (key == "pet") and BOOK_PET or BOOK_SPELL
        school = 0
        BuildSchools()
        Refresh()
    end)
    bookTabs:SetPoint("TOPLEFT", Kit.PAD, win.top)

    schoolBar = CreateFrame("Frame", nil, win)
    schoolBar:SetHeight(24)
    schoolBar:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, win.top - Kit.TAB_H - Kit.GAP)
    schoolBar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, win.top - Kit.TAB_H - Kit.GAP)

    local searchY = win.top - Kit.TAB_H - Kit.GAP - 24 - Kit.GAP
    chipPassive = Kit.Chip(win, "No passives", false, function() Refresh() end,
        "Hide passive abilities - the ones you never click.")
    chipPassive:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, searchY)
    chipRanks = Kit.Chip(win, "All ranks", false, function(on)
        if InCombatLockdown() then return false end
        -- Blizzard's own "Show all spell ranks" checkbox is this cvar; the
        -- client re-sends the book filtered by it and SPELLS_CHANGED
        -- brings the list round.
        -- SETUP2: through ns.CVar (recorded; put back when the window is off)
        if ns.CVar then ns.CVar.Set("ShowAllSpellRanks", on and "1" or "0", "spellbookwin")
        else SetCVar("ShowAllSpellRanks", on and "1" or "0") end
        Queue(false)
    end, "Every rank of every spell, not just the highest.")
    chipRanks:SetPoint("RIGHT", chipPassive, "LEFT", -4, 0)

    search = Kit.Search(win, 100, function(text)
        query = Kit.NormalizeQuery(text)
        Refresh()
    end, "Search spells")
    search:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, searchY)
    search:SetPoint("RIGHT", chipRanks, "LEFT", -Kit.GAP, 0)

    win.footer = Kit.Footer(win, 24)
    status = UI.Font(win.footer, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    status:SetPoint("LEFT", 8, 0)
    status:SetPoint("RIGHT", -8, 0)
    status:SetWordWrap(false)

    list = Kit.List(win, {
        rowHeight = Kit.ROW_H,
        template = "SecureActionButtonTemplate",
        secure = true,
        fallbackRows = 9,
        build = BuildRow,
        update = UpdateRow,
    })
    list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, searchY - Kit.SEARCH_H - Kit.GAP)
    list:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("SPELLS_CHANGED")
    -- LEARNED_SPELL_IN_TAB is gone on 1.15; registering an unknown event
    -- is an error, so both names go through pcall.
    pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_SKILL_LINE")
    pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_TAB")
    ev:RegisterEvent("PET_BAR_UPDATE")
    ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterUnitEvent("UNIT_PET", "player")
    ev:SetScript("OnEvent", function(_, event)
        if event == "SPELL_UPDATE_COOLDOWN" then
            if win:IsVisible() then UpdateVisibleCooldowns() end
        elseif event == "PLAYER_REGEN_DISABLED" then
            UpdateStatus()
        elseif event == "PLAYER_REGEN_ENABLED" then
            UpdateStatus()
            -- Anything that changed during the fight (a pet summoned, a
            -- rank learned, a search typed) lands now - and only then:
            -- an ordinary pull with nothing learned rebuilt the whole
            -- book after every fight, open or not.
            if win._zStale then
                schoolsDirty = true
                Queue()
            end
        else
            if InCombatLockdown() then
                win._zStale = true
            else
                schoolsDirty = true
                Queue()
            end
        end
    end)

    -- Blizzard opens the book on the tab you asked for (P vs Shift-P), and
    -- Shift-P on an OPEN book only switches bookType and calls Update - no
    -- OnShow - so both paths sync from here.
    local function SyncBook()
        if not win:IsVisible() then return end
        local want = (not MODERN and SpellBookFrame.bookType == BOOK_PET) and "pet" or "spell"
        if InCombatLockdown() then
            UpdateStatus()
            return
        end
        if (want == "pet") ~= (book == BOOK_PET) or win._zStale then
            book = (want == "pet") and BOOK_PET or BOOK_SPELL
            bookTabs:Select(want)
        else
            bookTabs:Paint(want)
            UpdateStatus()
            -- Rows were primed while shut; only their cooldowns can be old.
            UpdateVisibleCooldowns()
        end
    end
    win:HookScript("OnShow", SyncBook)
    if not MODERN and SpellBookFrame.Update then
        hooksecurefunc(SpellBookFrame, "Update", SyncBook)
    end

    -- THE X, SECURELY. SpellBookFrame is protected (it has secure
    -- children), so an addon's HideUIPanel on it is refused in combat.
    -- A secure "click" action on Blizzard's own close button runs their
    -- handler with secure credentials instead, so the X always works.
    local blizzClose = _G.SpellBookCloseButton or (MODERN and host.CloseButton) or nil
    if blizzClose then
        local sx = CreateFrame("Button", nil, win.titleBar, "SecureActionButtonTemplate")
        sx:SetAllPoints(win.closeButton)
        sx:SetFrameLevel(win.closeButton:GetFrameLevel() + 2)
        sx:SetAttribute("useOnKeyDown", false)
        sx:RegisterForClicks("AnyUp")
        sx:SetAttribute("type", "click")
        sx:SetAttribute("clickbutton", blizzClose)
        -- The drawn X underneath still lights up on hover.
        local x = win.closeButton
        sx:SetScript("OnEnter", function() x._zHot = true; x:_zPaint() end)
        sx:SetScript("OnLeave", function() x._zHot = nil; x:_zPaint() end)
        x:EnableMouse(false)
    end
    return win
end

-- Pieces of Blizzard's book that hang outside its visible rectangle: the
-- school tabs down the right edge and the Spells / Pet tabs underneath.
-- Also the "new spell" glow over those tabs, which pulses for half a
-- minute after training, and the close button, whose corner pokes past
-- the cover (it is still clicked - securely - through the cover's X).
local function BlizzardLeftovers()
    local t = {}
    for i = 1, 8 do
        t[#t + 1] = _G["SpellBookSkillLineTab" .. i]
        t[#t + 1] = _G["SpellBookSkillLineTab" .. i .. "Flash"]
    end
    for i = 1, 3 do t[#t + 1] = _G["SpellBookFrameTabButton" .. i] end
    t[#t + 1] = _G.SpellBookTabFlashFrame
    t[#t + 1] = _G.SpellBookCloseButton
    -- the modern window's parts above the cover (the maximise arrow at
    -- level 5510, the help-plate button in the HIGH strata)
    if MODERN and win then Kit.AboveCover(PlayerSpellsFrame, win, t) end
    return t
end

local function Apply()
    if not Host() then return end
    if InCombatLockdown() then return end
    if Enabled() then
        Build()
        win.Reanchor()
        win:Show()
        Kit.Silence(BlizzardLeftovers())
        -- Primed now, shown or not: see Refresh.
        BuildSchools()
        Refresh()
    elseif win then
        win:Hide()
        Kit.Unsilence(BlizzardLeftovers())
    end
end

-- ============================================================
-- MODULE
-- ============================================================
local function HookModern()
    if ns._zSpellbookWin or not Host() then return end
    ns._zSpellbookWin = true
    -- the window's own frame in ZacUI's look for its other pages (Talents)
    if ns.SkinModernWindow then pcall(ns.SkinModernWindow, PlayerSpellsFrame) end
    local page = PlayerSpellsFrame.SpellBookFrame
    -- the cover is PlayerSpellsFrame's child, so it shows with the book
    -- page and hides when Talents takes its place (or the window closes)
    page:HookScript("OnShow", function()
        if InCombatLockdown() then return end
        Apply()
        if win and win:IsShown() then Kit.Silence(BlizzardLeftovers()) end
    end)
    page:HookScript("OnHide", function()
        if win and not InCombatLockdown() then
            win:Hide()
            Kit.Unsilence(BlizzardLeftovers())
        end
    end)
    if page:IsVisible() and not InCombatLockdown() then Apply() end
end

Modules.spellbookwin = function()
    if not SpellBookFrame then
        -- WoW Forever: the modern book, loaded on demand
        if ns.RegisterLoD then ns.RegisterLoD("Blizzard_PlayerSpells", HookModern) end
        return
    end
    if ns._zSpellbookWin then return end
    ns._zSpellbookWin = true
    Apply()
    SpellBookFrame:HookScript("OnShow", function()
        if not InCombatLockdown() then Apply() end
        -- Blizzard re-shows its school tabs each update; keep them quiet.
        if win and win:IsShown() then Kit.Silence(BlizzardLeftovers()) end
    end)
end
