-- Win_Macros - ZacUI's macro window: a searchable list of your macros on
-- the left and a proper editor on the right, instead of Blizzard's icon
-- grid with the text box squeezed underneath.
-- Part of ZacUI; load order is set by the TOC.
--
-- MacroFrame lives in Blizzard_MacroUI, a LOAD-ON-DEMAND addon the client
-- loads the first time you open macros, so the window is built from
-- ADDON_LOADED - through our own watcher, NOT ns.RegisterLoD: the
-- "panels" skin already parks its MacroFrame skin there, and the registry
-- keeps one function per addon.
--
-- It is a Win_Kit cover inside MacroFrame, WIDER than Blizzard's panel
-- (the top-left corner is kept, the window runs right), so Escape, the
-- game menu's Macros button and /macro open and close it exactly as they
-- do Blizzard's.
--
-- BLIZZARD'S FRAME STAYS ALIVE UNDERNEATH, AND THAT IS A HAZARD. On every
-- hide MacroFrame writes its own copy of its selected macro's text back
-- with EditMacro. Its UPDATE_MACROS handler re-reads that copy after
-- every change made here (which is why nothing here ever unregisters
-- Blizzard's event: a stale copy would overwrite your edit on close),
-- and the save-on-close waits one frame so it always lands after
-- Blizzard's own write (see OnClose).
--
-- MACROS CANNOT BE CHANGED IN COMBAT (EditMacro, CreateMacro, DeleteMacro
-- are refused), so in combat the editor locks and the footer says so.
-- Picking a macro up to drag it onto a bar still works, as it does in
-- Blizzard's window. The X is a secure click on Blizzard's own close
-- button (HideUIPanel from an addon is refused in combat), which makes
-- this window protected: it is only ever built, moved, shown or hidden
-- out of combat.
--
--   Click row           edit that macro (asks first if you have unsaved changes)
--   Drag row / icon     put the macro on an action bar (PickupMacro)
--   Icon                choose an icon - "?" is Blizzard's dynamic icon
--   Save / Revert       write the editor back / throw your changes away
--   New / Duplicate     start a new macro / copy the selected one
--   Delete              delete it, after a confirm

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local Hex = ns.Hex
local Kit = ns.Kit
local Modules = ns.Modules
local SharpenIcon = ns.SharpenIcon
local UI = ns.UI

local M, F = UI.M, UI.F

-- ============================================================
-- LAYOUT
-- ============================================================
local LOD_NAME   = "Blizzard_MacroUI"
local TEX_ICON   = "Interface\\Icons\\INV_Misc_Note_01"
local WIN_W      = 640
local WIN_H      = 424                          -- MacroFrame's own height
local LEFT_W     = 270
local COL_GAP    = 10
local RIGHT_X    = Kit.PAD + LEFT_W + COL_GAP
local RIGHT_W    = WIN_W - Kit.PAD - RIGHT_X
local ROW_H      = Kit.ROW_H
local FOOT_H     = Kit.FOOTER_H
local TOP        = -(M.TITLEBAR + Kit.PAD)       -- = win.top
local Y1         = TOP - Kit.TAB_H - Kit.GAP     -- search row / editor top
-- Editor column height: from Y1 down to just above the footer.
local ED_H       = (WIN_H - 1 - FOOT_H - Kit.GAP) + Y1
local ICON_BIG   = 40
local LABEL_Y    = -(ICON_BIG + 8)
local BODY_Y     = LABEL_Y - 14
local BTN_H      = 22
local BODY_H     = ED_H + BODY_Y - BTN_H - Kit.GAP
local NAME_MAX   = 16                            -- Blizzard's name box: letters="16"
local BODY_MAX   = 255                           -- MacroFrameText: letters="255"

-- Icon picker grid.
local CELL       = 32
local CELL_STEP  = CELL + 2
local GRID_BODY_W = (LEFT_W - 12) - (M.SCROLL_W + 2)
local COLS       = math.max(1, math.floor((GRID_BODY_W + 2) / CELL_STEP))

-- Blizzard's question mark: fileID 134400 is what C_Macro reports for a
-- dynamic-icon macro, and the path is what their New flow passes in.
local QMARK_ID    = 134400
local QMARK_VALUE = "INTERFACE\\ICONS\\INV_MISC_QUESTIONMARK"

local BOOK_SPELL = BOOKTYPE_SPELL or "spell"

-- ============================================================
-- STATE
-- ============================================================
local win, tabs, search, countText, list, status
local edit, emptyEd, iconBtn, nameBox, scopeText, bodyLabel, counter, bodyBox
local saveBtn, revertBtn, dupBtn, delBtn, newBtn
local picker, pickSearch, pickCount, grid

local tab = "account"        -- "account" | "character"
local query = ""
local sel = nil              -- absolute macro index being edited
local isNew = false          -- editor holds a macro not created yet
local prevSel = nil          -- where Revert goes back to from a new draft
local origName, origBody, origIcon = "", "", nil
local iconTex, iconValue, iconChanged = nil, nil, false
local loading = false        -- editor text being set by us, not typed

local icons, iconsShown = nil, nil
local iconQuery = ""

local hooked, pendingApply = false, false
local confirmDlg, confirmCancel = nil, nil
local inCombat = false

local function Enabled()
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules.macroswin ~= false
end

-- Editing is locked from PLAYER_REGEN_DISABLED on. InCombatLockdown()
-- alone is not enough: it is still false while that event is handled.
local function Locked()
    return inCombat or InCombatLockdown()
end

-- Inline colour escape from the palette, for mixed-colour lines.
local function Paint(text, key)
    return "|cff" .. Hex(GetColor("text", key)) .. text .. "|r"
end

-- ============================================================
-- API HELPERS
-- ============================================================
local function MaxAccount() return MAX_ACCOUNT_MACROS or 120 end
local function MaxCharacter() return MAX_CHARACTER_MACROS or 30 end

-- Account macros are 1..MAX_ACCOUNT_MACROS, character macros follow.
local function TabBase(key)
    return ((key or tab) == "character") and MaxAccount() or 0
end

local function TabMax(key)
    return ((key or tab) == "character") and MaxCharacter() or MaxAccount()
end

local function TabCount(key)
    local numAccount, numChar = GetNumMacros()
    if (key or tab) == "character" then return numChar or 0 end
    return numAccount or 0
end

-- The icon the macro was GIVEN (134400 for "?"), not the dynamic one
-- GetMacroInfo reports - what Blizzard's editor reads for the same job.
local function SelectedIcon(index)
    if C_Macro and C_Macro.GetSelectedMacroIcon then
        local ok, v = pcall(C_Macro.GetSelectedMacroIcon, index)
        if ok and v then return v end
    end
    return (select(2, GetMacroInfo(index)))
end

local function InTab(index, key)
    if not index then return false end
    local base = TabBase(key)
    return index > base and index <= base + TabCount(key)
end

-- Find a macro again after an insert, delete or rename re-sorted the
-- tab. Names need not be unique, so the body breaks ties: a same-name
-- same-body match first, then the first same-name one.
-- strict: only an exact name + body match (what a WRITE may target).
local function FindInTab(name, body, key, strict)
    if not name then return nil end
    local base = TabBase(key)
    local byName
    for i = base + 1, base + TabCount(key) do
        local n, _, b = GetMacroInfo(i)
        if n == name then
            if (b or "") == (body or "") then return i end
            byName = byName or i
        end
    end
    if strict then return nil end
    return byName
end

-- Blizzard strips quotes from names (IconSelectorEditBoxMixin).
local function CleanName(text)
    text = string.gsub(text or "", "\"", "")
    return strtrim(text)
end

-- First n characters of a UTF-8 string, never splitting a character.
local function Utf8Sub(s, n)
    local out, count = {}, 0
    for ch in string.gmatch(s, "[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > n then break end
        out[#out + 1] = ch
    end
    return table.concat(out)
end

-- A name no macro uses yet: "Name 2", "Name 3" ... kept to 16 letters.
local function UniqueName(base)
    local used = {}
    local numAccount, numChar = GetNumMacros()
    for i = 1, numAccount or 0 do
        local n = GetMacroInfo(i)
        if n then used[n] = true end
    end
    for i = MaxAccount() + 1, MaxAccount() + (numChar or 0) do
        local n = GetMacroInfo(i)
        if n then used[n] = true end
    end
    for k = 2, 99 do
        local suffix = " " .. k
        local stem = Utf8Sub(base, NAME_MAX - #suffix)
        local candidate = stem .. suffix
        if not used[candidate] then return candidate end
    end
    return Utf8Sub(base, NAME_MAX)
end

-- ============================================================
-- STATUS LINE
-- ============================================================
local statusToken = 0

local function DefaultStatus()
    if not status then return end
    if Locked() then
        status:SetText("In combat - macros can't be changed until it ends.")
        status:SetTextColor(Kit.TextRGB("red"))
    else
        status:SetText("Click to edit  |  Drag a macro to an action bar")
        status:_zPaint()
    end
end

-- A message that stays a few seconds, then gives the line back.
local function Flash(msg, key)
    if not status then return end
    statusToken = statusToken + 1
    local token = statusToken
    status:SetText(msg)
    status:SetTextColor(Kit.TextRGB(key or "red"))
    C_Timer.After(4, function()
        if statusToken == token then DefaultStatus() end
    end)
end

-- ============================================================
-- EDITOR STATE
-- ============================================================
local function HasEditor() return sel ~= nil or isNew end

local function IsDirty()
    if not HasEditor() or not nameBox then return false end
    if iconChanged then return true end
    return nameBox:GetText() ~= origName or bodyBox:GetText() ~= origBody
end

local function ScopeLabel()
    if tab == "character" then
        return (UnitName("player") or (CHARACTER or "Character")) .. "'s macro"
    end
    return "General macro"
end

local UpdateButtons   -- defined below, called from the loaders

local function SetEditorText(name, body)
    loading = true
    nameBox:SetText(name or "")
    bodyBox:SetText(body or "")
    loading = false
end

local function ShowIcon()
    iconBtn.icon:SetTexture(iconTex or QMARK_ID)
end

-- Read the selected macro back from the client into the editor.
local function LoadSelected()
    isNew = false
    if sel then
        local name, _, body = GetMacroInfo(sel)
        if not name then sel = nil end
        origName, origBody = name or "", body or ""
    else
        origName, origBody = "", ""
    end
    origIcon = sel and SelectedIcon(sel) or nil
    iconTex, iconValue, iconChanged = origIcon, nil, false
    if nameBox then
        SetEditorText(origName, origBody)
        ShowIcon()
    end
end

local function SelectIndex(index)
    sel = index
    LoadSelected()
end

-- Is sel still the macro the editor was loaded from (following it if a
-- re-sort moved it)? Checked before every write, so a draft can never
-- land on a different macro than the one it was typed over.
local function Resync()
    if isNew then return true end
    if not sel then return false end
    if InTab(sel) then
        local n, _, b = GetMacroInfo(sel)
        if n == origName and (b or "") == origBody then return true end
    end
    local found = FindInTab(origName, origBody, nil, true)
    if found then sel = found return true end
    return false
end

local function SelectFirst()
    sel = (TabCount() > 0) and (TabBase() + 1) or nil
    LoadSelected()
end

-- ============================================================
-- LIST DATA
-- ============================================================
local function Preview(body)
    local first
    for line in string.gmatch(body or "", "[^\n]+") do
        local t = strtrim(line)
        if t ~= "" then
            first = first or t
            -- #showtooltip / #show say nothing about what the macro does.
            if string.sub(t, 1, 1) ~= "#" then return t end
        end
    end
    return first or ""
end

local function Rows()
    local data = {}
    local base, n = TabBase(), TabCount()
    for i = base + 1, base + n do
        local name, tex, body = GetMacroInfo(i)
        if name then
            if Kit.Matches(query, name, body) then
                data[#data + 1] = {
                    index = i, name = name, tex = tex, body = body or "",
                    -- Pipes would be read as escape codes by the FontString.
                    preview = string.gsub(Preview(body), "|", "||"),
                }
            end
        end
    end
    return data, n
end

-- ============================================================
-- REFRESH
-- ============================================================
local function ScrollToSelected(data)
    if not sel or not list then return end
    for pos, e in ipairs(data) do
        if e.index == sel then
            local vis = math.max(1, math.floor(((list.body:GetHeight() or 0) + 1) / ROW_H))
            if pos <= list.offset then
                list.offset = pos - 1
            elseif pos > list.offset + vis then
                list.offset = pos - vis
            end
            return
        end
    end
end

local function Refresh(scrollToSel)
    -- IsVisible, not IsShown: the cover is a shown child all session.
    if not win or not win:IsVisible() then return end
    local data, n = Rows()
    list.selected = nil
    for _, e in ipairs(data) do
        if e.index == sel then list.selected = e break end
    end
    if scrollToSel then ScrollToSelected(data) end
    list:SetEmptyText(n == 0 and "No macros here yet - click New." or "Nothing matches.")
    list:SetData(data, true)
    local max = TabMax()
    if query ~= "" then
        countText:SetText(#data .. " shown  |  " .. n .. " / " .. max)
    else
        countText:SetText(n .. " / " .. max .. " macros")
    end
    UpdateButtons()
end

-- UPDATE_MACROS (ours, Blizzard's, another addon's): re-read the macro
-- the editor is on. An unsaved draft is kept if its macro is still
-- there - found again by name when an insert or delete moved it.
local function Reconcile()
    if isNew or not nameBox then return end
    if sel and not InTab(sel) then sel = nil end
    if IsDirty() then
        -- Same name AND body: two macros can share a name, and a delete
        -- above this one slides its twin into the old index.
        if sel then
            local n, _, b = GetMacroInfo(sel)
            if n == origName and (b or "") == origBody then return end
        end
        local found = FindInTab(origName, origBody)
        if found then
            sel = found
            return
        end
        Flash("The macro you were editing is gone - changes discarded.", "orange")
        SelectFirst()
        return
    end
    if not sel then
        SelectFirst()
    else
        LoadSelected()
    end
end

local Queue = Kit.Coalesce(function()
    if not win or not win:IsVisible() then return end
    Reconcile()
    Refresh()
end, function() return win end)

-- ============================================================
-- BUTTON STATE + COMBAT LOCK
-- ============================================================
function UpdateButtons()
    if not saveBtn then return end
    local locked = Locked()
    local has = HasEditor()
    local dirty = IsDirty()
    local full = TabCount() >= TabMax()
    local named = CleanName(nameBox:GetText()) ~= ""

    edit:SetShown(has)
    emptyEd:SetShown(not has)

    saveBtn:SetLabel(isNew and "Create" or (SAVE or "Save"))
    saveBtn:SetDisabled(locked or not dirty or not named)
    revertBtn:SetLabel(isNew and (CANCEL or "Cancel") or "Revert")
    revertBtn:SetDisabled(not (dirty or isNew))
    dupBtn:SetDisabled(locked or isNew or not sel or full)
    delBtn:SetDisabled(locked or isNew or not sel)
    newBtn:SetDisabled(locked or isNew or full)
    iconBtn:SetUsable(not locked)

    local line = ScopeLabel()
    if isNew then line = line .. "  |  " .. Paint("new, not created yet", "orange")
    elseif dirty then line = line .. "  |  " .. Paint("unsaved changes", "orange") end
    scopeText:SetText(line)
end

local function UpdateCounter()
    if not bodyBox then return end
    local n = bodyBox.editBox:GetNumLetters() or 0
    counter:SetText(n .. " / " .. BODY_MAX)
    if n >= BODY_MAX then counter:SetTextColor(Kit.TextRGB("red")) else counter:_zPaint() end
end

local function ClosePicker()
    if not picker then return end
    pickSearch.editBox:ClearFocus()
    picker:Hide()
end

-- Editing is refused in combat anyway; locking the boxes says so up front
-- instead of letting you type a change that cannot be saved.
local function Lock()
    if not nameBox then return end
    local locked = Locked()
    nameBox.editBox:EnableMouse(not locked)
    bodyBox.editBox:EnableMouse(not locked)
    bodyBox:EnableMouse(not locked)
    if locked then
        nameBox.editBox:ClearFocus()
        bodyBox.editBox:ClearFocus()
        ClosePicker()
    end
    DefaultStatus()
    UpdateButtons()
end

-- ============================================================
-- CONFIRMS
-- ============================================================
-- UI.Confirm is one shared dialog; remember which callback is ours so a
-- window close only ever dismisses OUR question.
local function Ask(opts)
    local onAccept, onCancel = opts.onAccept, opts.onCancel
    local function Cancel()
        confirmDlg, confirmCancel = nil, nil
        if onCancel then onCancel() end
    end
    opts.onAccept = function()
        confirmDlg, confirmCancel = nil, nil
        if onAccept then onAccept() end
    end
    opts.onCancel = Cancel
    confirmCancel = Cancel
    confirmDlg = UI.Confirm(opts)
end

local function DismissAsk()
    local d = confirmDlg
    if d and d:IsShown() and d._onCancel == confirmCancel then
        UI.CloseWindow(d)
    end
    confirmDlg, confirmCancel = nil, nil
end

-- ============================================================
-- SAVE / NEW / DUPLICATE / DELETE / REVERT
-- ============================================================
-- A spell link as macro text: "Name(Rank 3)" as Blizzard's spellbook
-- would insert it, or just "Name" for a spell without a rank.
local function SpellText(text)
    local id = tonumber(text:match("|Hspell:(%d+)"))
    local name = text:match("|h%[(.-)%]|h")
    if id and GetSpellInfo then name = GetSpellInfo(id) or name end
    if not name then return nil end
    local sub = id and GetSpellSubtext and GetSpellSubtext(id)
    if sub and sub ~= "" then return name .. "(" .. sub .. ")" end
    return name
end

local lastInsert, lastInsertAt
local function InsertIntoMacro(text)
    if type(text) ~= "string" or text == "" then return end
    local eb = bodyBox and bodyBox.editBox
    if not (eb and eb:HasFocus() and eb:IsVisible()) then return end
    -- Blizzard put it somewhere else: an open chat line or the auction
    -- house's own search box comes first, exactly as before.
    local util = ChatFrameUtil
    if util and util.GetActiveWindow and util.GetActiveWindow() then return end
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end
    if BrowseName and BrowseName:IsVisible() and text:find("item:", 1, true) then return end
    -- The old and new names of the insert call can both fire for one click.
    local now = GetTime()
    if lastInsert == text and lastInsertAt == now then return end
    lastInsert, lastInsertAt = text, now

    local item
    if text:find("item:", 1, true) then
        item = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(text))
            or (GetItemInfo and GetItemInfo(text))
    end
    local spell = (not item) and text:find("|Hspell:") and SpellText(text) or nil
    local plain = item or spell or text
    local pos = eb:GetCursorPosition() or 0
    local body = eb:GetText() or ""
    if pos == 0 or body:sub(pos, pos) == "\n" then
        if item then
            local useSpell = (C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(text))
                or (GetItemSpell and GetItemSpell(text))
            eb:Insert((useSpell and (SLASH_USE1 or "/use") or (SLASH_EQUIP1 or "/equip"))
                .. " " .. item .. "\n")
        else
            eb:Insert((SLASH_CAST1 or "/cast") .. " " .. plain .. "\n")
        end
    else
        eb:Insert(plain)
    end
end

local linkHooked
local function InstallLinkInsert()
    if linkHooked then return end
    linkHooked = true
    if ChatFrameUtil and type(ChatFrameUtil.InsertLink) == "function" then
        hooksecurefunc(ChatFrameUtil, "InsertLink", InsertIntoMacro)
    end
    if type(ChatEdit_InsertLink) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", InsertIntoMacro)
    end
end

local function Save(quiet)
    if not HasEditor() then return true end
    if not IsDirty() then return true end
    if Locked() then
        if not quiet then Flash("Can't save macros in combat.") end
        return false
    end
    local name = CleanName(nameBox:GetText())
    if name == "" then
        if not quiet then Flash("Give the macro a name first.") end
        return false
    end
    local body = bodyBox:GetText() or ""

    if isNew then
        if TabCount() >= TabMax() then
            if not quiet then Flash("This tab is full.") end
            return false
        end
        -- Blizzard's New: CreateMacro(name, icon, body, perCharacter).
        local ok, idx = pcall(CreateMacro, name, iconValue or QMARK_VALUE, body, tab == "character")
        if not ok or type(idx) ~= "number" or idx <= 0 then
            if not quiet then Flash("Couldn't create the macro.") end
            return false
        end
        prevSel = nil
        SelectIndex(idx)
    else
        if not Resync() then
            if not quiet then Flash("That macro changed elsewhere - click Revert to see it.") end
            return false
        end
        -- nil keeps a field as it is - Blizzard's own SaveMacro passes nil
        -- name and icon, and leaving the icon alone is what keeps "?"
        -- dynamic. EditMacro returns the macro's NEW index: the list is
        -- kept sorted by name, so a rename can move it.
        local nameArg = (name ~= origName) and name or nil
        local iconArg = iconChanged and iconValue or nil
        local bodyArg = (body ~= origBody) and body or nil
        if nameArg or iconArg or bodyArg then
            local ok, idx = pcall(EditMacro, sel, nameArg, iconArg, bodyArg)
            if not ok then
                if not quiet then Flash("Couldn't save the macro.") end
                return false
            end
            if type(idx) == "number" and idx > 0 then sel = idx end
        end
        LoadSelected()
    end
    if not quiet then Flash("Saved " .. name .. ".", "green") end
    Refresh(true)
    return true
end

-- Run fn, but ask first when the editor holds unsaved changes. Out of
-- combat the answer is "save them" (what Blizzard's window does silently
-- on every switch); in combat saving is impossible, so it is "discard".
local function Guard(fn)
    if not IsDirty() then fn() return end
    local name = CleanName(nameBox:GetText())
    if name == "" then name = origName ~= "" and origName or "this macro" end
    if Locked() then
        Ask({
            title = "Unsaved changes",
            text = "Macros can't be saved in combat. Discard your changes to \"" .. name .. "\"?",
            acceptText = "Discard", destructive = true,
            onAccept = function()
                if isNew then isNew = false; sel = prevSel end
                LoadSelected()
                fn()
            end,
        })
    else
        Ask({
            title = "Unsaved changes",
            text = "Save your changes to \"" .. name .. "\" first?",
            acceptText = SAVE or "Save",
            onAccept = function()
                if Save() then fn() end
            end,
        })
    end
end

local function StartNew()
    if Locked() then return end
    if TabCount() >= TabMax() then Flash("This tab is full.") return end
    Guard(function()
        ClosePicker()
        prevSel = sel
        sel = nil
        isNew = true
        origName, origBody, origIcon = "", "", nil
        iconTex, iconValue, iconChanged = QMARK_ID, QMARK_VALUE, false
        SetEditorText("", "")
        ShowIcon()
        UpdateCounter()
        Refresh()
        nameBox.editBox:SetFocus()
    end)
end

local function Revert()
    ClosePicker()
    if isNew then
        isNew = false
        sel = prevSel
        prevSel = nil
        if sel and not InTab(sel) then sel = nil end
        if not sel then SelectFirst() else LoadSelected() end
    else
        LoadSelected()
    end
    UpdateCounter()
    Refresh()
end

-- Copies the SAVED macro (saving first if the editor has changes) into
-- a new one in the same tab, with a free name.
local function Duplicate()
    if Locked() or isNew or not sel then return end
    Guard(function()
        if not sel or Locked() then return end
        if TabCount() >= TabMax() then Flash("This tab is full.") return end
        local name, _, body = GetMacroInfo(sel)
        if not name then return end
        local newName = UniqueName(name)
        -- A "?" macro is created the way Blizzard's New creates one (by
        -- path), so the copy stays dynamic too.
        local icon = SelectedIcon(sel)
        if not icon or icon == QMARK_ID then icon = QMARK_VALUE end
        local ok, idx = pcall(CreateMacro, newName, icon, body or "", tab == "character")
        if not ok or type(idx) ~= "number" or idx <= 0 then
            Flash("Couldn't duplicate the macro.")
            return
        end
        SelectIndex(idx)
        UpdateCounter()
        Flash("Made " .. newName .. ".", "green")
        Refresh(true)
    end)
end

local function Delete()
    if Locked() or isNew or not sel then return end
    -- Frozen now: the index must still be THIS macro when you click OK.
    local index, name, body, tabAt = sel, origName, origBody, tab
    Ask({
        title = DELETE or "Delete",
        text = (CONFIRM_DELETE_MACRO or "Delete this macro?") .. "\n\n" .. name,
        acceptText = DELETE or "Delete", destructive = true,
        onAccept = function()
            if Locked() then Flash("Can't delete macros in combat.") return end
            local n0, _, b0 = GetMacroInfo(index)
            if n0 ~= name or (b0 or "") ~= body then
                Flash("That macro changed - nothing deleted.")
                return
            end
            local localIdx = index - TabBase(tabAt)
            DeleteMacro(index)
            -- The next macro takes its place, as in Blizzard's window -
            -- unless you have switched tab since asking, when the editor
            -- (on the other tab) is left alone.
            if tab == tabAt then
                local n = TabCount()
                sel = (n > 0) and (TabBase() + math.min(localIdx, n)) or nil
                LoadSelected()
                UpdateCounter()
            end
            Refresh(true)
        end,
    })
end

-- ============================================================
-- ICON PICKER
-- ============================================================
-- The same sources Blizzard's picker uses, in the same order: "?" first,
-- then your spellbook's icons (named, so "fireball" finds them), then
-- the client's spell and item icon lists. Built on first open and
-- dropped when the window closes - it is thousands of entries.
local function BuildIcons()
    if icons then return icons end
    local out, seen = {}, {}
    local function Add(tex, value, label, key)
        if tex == nil then return end
        local id = (type(tex) == "number") and tex or string.lower(tostring(tex))
        if seen[id] then return end
        seen[id] = true
        out[#out + 1] = { tex = tex, value = value, label = label, key = key }
    end
    Add(QMARK_ID, QMARK_VALUE, "Dynamic icon",
        "? question mark dynamic inv_misc_questionmark " .. QMARK_ID)
    seen[string.lower(QMARK_VALUE)] = true

    if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemTexture then
        for t = 1, GetNumSpellTabs() do
            local _, _, offset, numSlots = GetSpellTabInfo(t)
            for slot = (offset or 0) + 1, (offset or 0) + (numSlots or 0) do
                local kind = GetSpellBookItemInfo and GetSpellBookItemInfo(slot, BOOK_SPELL)
                if kind ~= "FUTURESPELL" then
                    local fid = GetSpellBookItemTexture(slot, BOOK_SPELL)
                    if fid then
                        local nm = GetSpellBookItemName and GetSpellBookItemName(slot, BOOK_SPELL) or nil
                        Add(fid, fid, nm or ("Icon " .. tostring(fid)),
                            string.lower((nm or "") .. " " .. tostring(fid)))
                    end
                end
            end
        end
    end

    -- Each fills a table with file IDs or bare icon file names.
    local lists = { GetLooseMacroIcons, GetMacroIcons, GetLooseMacroItemIcons, GetMacroItemIcons }
    for i = 1, 4 do
        local fn = lists[i]
        if fn then
            local tmp = {}
            pcall(fn, tmp)
            for _, v in ipairs(tmp) do
                local n = tonumber(v)
                if n then
                    Add(n, n, "Icon " .. n, tostring(n))
                elseif type(v) == "string" and v ~= "" then
                    local path = "INTERFACE\\ICONS\\" .. v
                    Add(path, path, v, string.lower(v))
                end
            end
        end
    end
    icons = out
    return icons
end

local function FilterIcons()
    local all = BuildIcons()
    if iconQuery == "" then
        iconsShown = all
    else
        iconsShown = {}
        for _, e in ipairs(all) do
            if string.find(e.key, iconQuery, 1, true) then iconsShown[#iconsShown + 1] = e end
        end
    end
    local rows = {}
    for i = 1, #iconsShown, COLS do rows[#rows + 1] = { first = i } end
    return rows
end

local function RefreshGrid(scrollToCurrent)
    local rows = FilterIcons()
    if scrollToCurrent then
        grid.offset = 0
        for i, e in ipairs(iconsShown) do
            if e.tex == iconTex then
                grid.offset = math.max(0, math.floor((i - 1) / COLS) - 2)
                break
            end
        end
    end
    pickCount:SetText(#iconsShown .. (#iconsShown == 1 and " icon" or " icons"))
    grid:SetData(rows, true)
end

local function PickIcon(e)
    iconTex, iconValue = e.tex, e.value
    -- Picking the icon it already had is no change at all.
    iconChanged = not (not isNew and origIcon ~= nil and e.tex == origIcon)
    if isNew and e.tex == QMARK_ID then iconChanged = false end
    ShowIcon()
    ClosePicker()
    UpdateButtons()
    if list then list:Refresh() end
end

local function OpenPicker()
    if Locked() or not HasEditor() then return end
    iconQuery = ""
    pickSearch:SetText("")
    picker:Show()
    RefreshGrid(true)
end

local function PaintCell(self)
    local f = GetColor("ui", "elementBg")
    self._zFill:SetVertexColor(f.r, f.g, f.b, f.a or 1)
    -- Hover gold, the current icon green (selected), else the black line.
    local key = self._zHot and "accent" or (self._zCurrent and "borderSelected" or "border")
    local b = GetColor("ui", key)
    for _, t in ipairs(self._zBorder) do t:SetVertexColor(b.r, b.g, b.b, b.a or 1) end
end

local function CellTooltip(self)
    local e = self.entry
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local tc = GetColor("tooltip", "title")
    GameTooltip:AddLine(e.label or "", tc.r, tc.g, tc.b)
    local c = GetColor("tooltip", "body")
    if e.tex == QMARK_ID then
        GameTooltip:AddLine("Shows the icon of whatever the macro casts (#showtooltip).", c.r, c.g, c.b, true)
    elseif type(e.tex) == "number" then
        GameTooltip:AddLine("File ID " .. e.tex, c.r, c.g, c.b)
    end
    GameTooltip:Show()
end

local function BuildIconRow(row)
    -- The grid draws its own cells; the list's row stripe would only
    -- band the gaps between them.
    row.stripe:SetAlpha(0)
    row.cells = {}
    for c = 1, COLS do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(CELL, CELL)
        b:SetPoint("TOPLEFT", row, "TOPLEFT", (c - 1) * CELL_STEP, -1)
        UI.Fill(b, "ui", "elementBg")
        UI.Border(b, "ui", "border")
        local t = b:CreateTexture(nil, "ARTWORK")
        t._zui_own = true
        t:SetPoint("TOPLEFT", 1, -1)
        t:SetPoint("BOTTOMRIGHT", -1, 1)
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        SharpenIcon(t)
        b.tex = t
        b._zPaint = PaintCell
        b:SetScript("OnEnter", function(self)
            self._zHot = true
            self:_zPaint()
            CellTooltip(self)
        end)
        b:SetScript("OnLeave", function(self)
            self._zHot = nil
            self:_zPaint()
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", function(self)
            if self.entry then PickIcon(self.entry) end
        end)
        b:_zPaint()
        row.cells[c] = b
    end
end

local function UpdateIconRow(row, item)
    for c = 1, COLS do
        local b = row.cells[c]
        local e = iconsShown and iconsShown[item.first + c - 1]
        b.entry = e
        if e then
            b.tex:SetTexture(e.tex)
            b._zCurrent = (e.tex == iconTex) or nil
            b:_zPaint()
            b:Show()
        else
            b:Hide()
        end
    end
end

-- ============================================================
-- MACRO LIST ROWS
-- ============================================================
local function RowTooltip(row)
    local e = row.item
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local tc = GetColor("tooltip", "title")
    GameTooltip:AddLine(e.name, tc.r, tc.g, tc.b)
    if e.body ~= "" then
        local c = GetColor("tooltip", "body")
        GameTooltip:AddLine(string.gsub(e.body, "|", "||"), c.r, c.g, c.b, true)
    end
    GameTooltip:Show()
end

local function BuildRow(row)
    row:RegisterForClicks("LeftButtonUp")
    row:RegisterForDrag("LeftButton")

    row.icon = Kit.Icon(row, ROW_H - 4)
    row.icon:SetPoint("LEFT", 3, 0)
    row.icon:EnableMouse(false)

    -- Name on top, the first real line underneath; each is pinned by a
    -- TOP (or BOTTOM) pair so the two can never overlap.
    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, -2)
    row.nameText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -4)
    row.nameText:SetWordWrap(false)

    row.sub = UI.Font(row, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, 2)
    row.sub:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 4)
    row.sub:SetWordWrap(false)

    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.UpdateTooltip = RowTooltip

    row:SetScript("OnClick", function(self)
        local e = self.item
        if not e or (e.index == sel and not isNew) then return end
        local index, name, body = e.index, e.name, e.body
        Guard(function()
            ClosePicker()
            -- Saving first can rename or create a macro, which re-sorts
            -- the tab: follow the clicked one to wherever it is now.
            local n, _, b = GetMacroInfo(index)
            if not InTab(index) or n ~= name or (b or "") ~= body then
                index = FindInTab(name, body) or index
            end
            SelectIndex(index)
            UpdateCounter()
            Refresh()
        end)
    end)

    -- Blizzard's macro button does exactly this on drag.
    row:SetScript("OnDragStart", function(self)
        local e = self.item
        if e and PickupMacro then PickupMacro(e.index) end
    end)
end

local function UpdateRow(row, e)
    row.icon:SetIcon(e.tex)
    row.icon:SetQuality(nil)
    row.icon:SetCount(nil)
    local name = e.name
    if e.index == sel and not isNew and IsDirty() then name = name .. " " .. Paint("*", "orange") end
    row.nameText:SetText(name)
    row.sub:SetText(e.preview)
end

-- ============================================================
-- BUILD
-- ============================================================
local function CharacterTabLabel()
    local fmt = CHARACTER_SPECIFIC_MACROS
    if fmt then
        local ok, s = pcall(string.format, fmt, UnitName("player") or "")
        if ok and s then return s end
    end
    return (UnitName("player") or (CHARACTER or "Character"))
end

local function OnTab(key)
    if key == tab then return end
    -- Kit.Tabs painted the new tab already; hold the old one until the
    -- unsaved-changes question (if any) is answered.
    tabs:Paint(tab)
    Guard(function()
        ClosePicker()
        tab = key
        tabs:Paint(key)
        list.offset = 0
        SelectFirst()
        UpdateCounter()
        Refresh()
    end)
end

local function BuildPicker()
    picker = UI.Box(win, "ui", "cardBg")
    -- Set before any child exists, so the grid inherits a level above
    -- the macro list it covers.
    picker:SetFrameLevel(win:GetFrameLevel() + 20)
    -- From the search row down: the tab strip above stays whole.
    picker:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, Y1)
    picker:SetPoint("BOTTOMLEFT", win.footer, "TOPLEFT", Kit.PAD - 1, Kit.GAP)
    picker:SetWidth(LEFT_W)
    picker:EnableMouse(true)
    picker:Hide()

    local close = UI.CloseX(picker, 18, ClosePicker)
    close:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -3, -3)

    pickCount = UI.Font(picker, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    pickCount:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -26, -9)
    pickCount:SetWordWrap(false)

    local title = UI.Font(picker, F.LABEL, { cat = "text", key = "gold", justify = "LEFT",
        text = "Choose an icon" })
    title:SetPoint("TOPLEFT", picker, "TOPLEFT", 8, -8)
    title:SetPoint("TOPRIGHT", pickCount, "TOPLEFT", -6, 0)
    title:SetWordWrap(false)

    pickSearch = Kit.Search(picker, LEFT_W - 12, function(text)
        iconQuery = Kit.NormalizeQuery(text)
        grid.offset = 0
        RefreshGrid(false)
    end, "Search icons (spell, file or ID)")
    pickSearch:SetPoint("TOPLEFT", picker, "TOPLEFT", 6, -28)

    grid = Kit.List(picker, {
        rowHeight = CELL_STEP,
        frameType = "Frame",
        build = BuildIconRow,
        update = UpdateIconRow,
        empty = "No icons match.",
    })
    grid:SetPoint("TOPLEFT", picker, "TOPLEFT", 6, -28 - Kit.SEARCH_H - Kit.GAP)
    grid:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -6, 6)
end

local function BuildEditor()
    local ed = CreateFrame("Frame", nil, win)
    ed:SetPoint("TOPLEFT", win, "TOPLEFT", RIGHT_X, Y1)
    ed:SetPoint("BOTTOMRIGHT", win.footer, "TOPRIGHT", -Kit.PAD + 1, Kit.GAP)

    emptyEd = UI.Font(ed, F.LABEL, { cat = "text", key = "gray", justify = "CENTER",
        width = RIGHT_W - 20, text = "No macro selected. Click New to make one." })
    emptyEd:SetPoint("CENTER", ed, "CENTER", 0, 0)

    edit = CreateFrame("Frame", nil, ed)
    edit:SetAllPoints()

    -- The icon: click to choose, drag to put the macro on a bar (what
    -- Blizzard's big selected-macro button does).
    iconBtn = Kit.IconButton(edit, ICON_BIG, QMARK_ID, "Icon",
        "Click to choose an icon. Drag to put the macro on an action bar.",
        function() OpenPicker() end)
    iconBtn:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, 0)
    iconBtn:RegisterForDrag("LeftButton")
    iconBtn:SetScript("OnDragStart", function()
        if sel and not isNew and PickupMacro then PickupMacro(sel) end
    end)

    nameBox = UI.EditBox(edit, {
        width = RIGHT_W - ICON_BIG - 8, height = BTN_H,
        hint = "Macro name", clear = false,
        onChange = function()
            if not loading then UpdateButtons(); list:Refresh() end
        end,
        onEnter = function() bodyBox.editBox:SetFocus() end,
    })
    nameBox:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 8, 0)
    nameBox.editBox:SetMaxLetters(NAME_MAX)
    nameBox.editBox:SetScript("OnTabPressed", function() bodyBox.editBox:SetFocus() end)

    -- Sits on the icon's bottom edge: both points are BOTTOM ones at the
    -- same height, so it can never ride up into the name box.
    scopeText = UI.Font(edit, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    scopeText:SetPoint("BOTTOMLEFT", iconBtn, "BOTTOMRIGHT", 8, 1)
    scopeText:SetPoint("BOTTOMRIGHT", edit, "TOPRIGHT", 0, -(ICON_BIG - 1))
    scopeText:SetJustifyV("BOTTOM")
    scopeText:SetWordWrap(false)

    counter = UI.Font(edit, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    counter:SetPoint("TOPRIGHT", edit, "TOPRIGHT", 0, LABEL_Y)
    counter:SetWordWrap(false)
    bodyLabel = UI.Font(edit, F.SMALL, { cat = "text", key = "gray", justify = "LEFT",
        text = ENTER_MACRO_LABEL or "Enter macro commands:" })
    bodyLabel:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, LABEL_Y)
    bodyLabel:SetPoint("TOPRIGHT", counter, "TOPLEFT", -6, 0)
    bodyLabel:SetWordWrap(false)

    bodyBox = UI.TextBox(edit, {
        width = RIGHT_W, height = BODY_H,
        onChange = function()
            if not loading then UpdateButtons(); list:Refresh() end
        end,
    })
    bodyBox:SetPoint("TOPLEFT", edit, "TOPLEFT", 0, BODY_Y)
    local eb = bodyBox.editBox
    eb:SetMaxLetters(BODY_MAX)
    -- Colour codes count toward the limit, as in Blizzard's box.
    if eb.SetCountInvisibleLetters then eb:SetCountInvisibleLetters(true) end
    eb:HookScript("OnTextChanged", UpdateCounter)
    -- Keep the caret in view while typing past the bottom of the box.
    local scroll = eb:GetParent()
    -- Not clamped to the box's height: on a fresh line the edit box grows
    -- a moment after the caret moves, and a clamp would lag one line.
    eb:HookScript("OnCursorChanged", function(_, _, y, _, h)
        local view = scroll:GetHeight() or 0
        local top = -(y or 0)
        local cur = scroll:GetVerticalScroll() or 0
        if top < cur then
            scroll:SetVerticalScroll(math.max(0, top))
        elseif top + (h or 0) > cur + view then
            scroll:SetVerticalScroll(math.max(0, top + (h or 0) - view))
        end
    end)
    -- A click on the empty part of the box lands in the text.
    bodyBox:EnableMouse(true)
    bodyBox:SetScript("OnMouseDown", function()
        if Locked() then return end
        eb:SetFocus()
        eb:SetCursorPosition(eb:GetNumLetters() or 0)
    end)
    -- Tab / Enter can move focus without a click; refuse it in combat.
    local function NoFocusInCombat(self)
        if Locked() then self:ClearFocus() end
    end
    eb:HookScript("OnEditFocusGained", NoFocusInCombat)
    nameBox.editBox:HookScript("OnEditFocusGained", NoFocusInCombat)

    -- SHIFT-CLICK INTO THE MACRO. Blizzard's link insert knows exactly one
    -- macro editor - MacroFrameText - so with this one open a shift-clicked
    -- spell or item went nowhere. It now lands here, the way Blizzard's own
    -- editor takes it: at the start of a line an item becomes "/use Item"
    -- (or "/equip" for gear) and a spell "/cast Spell(Rank n)"; anywhere
    -- else just the name goes in.
    InstallLinkInsert()

    saveBtn = UI.Button(edit, SAVE or "Save", { width = 72, height = BTN_H })
    saveBtn:SetPoint("BOTTOMLEFT", edit, "BOTTOMLEFT", 0, 0)
    saveBtn:SetScript("OnClick", function() Save() end)
    revertBtn = UI.Button(edit, "Revert", { width = 72, height = BTN_H })
    revertBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)
    revertBtn:SetScript("OnClick", Revert)
    UI.Tooltip(revertBtn, "Revert", "Throw away your changes and show the macro as saved.")

    delBtn = UI.Button(edit, DELETE or "Delete", { width = 72, height = BTN_H })
    delBtn:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT", 0, 0)
    delBtn:SetScript("OnClick", Delete)
    dupBtn = UI.Button(edit, "Duplicate", { width = 80, height = BTN_H })
    dupBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
    dupBtn:SetScript("OnClick", Duplicate)
    UI.Tooltip(dupBtn, "Duplicate", "Copy the saved macro into a new one in this tab.")
end

local function Build()
    if win then return win end
    win = Kit.Cover(MacroFrame, {
        name = "ZacUIMacroWindow",
        title = MACROS or CREATE_MACROS or "Macros",
        insetName = "MacroFrame",
        width = WIN_W,
        height = WIN_H,
        -- Only reached if Blizzard's close button is missing (the secure
        -- X below normally sits over this one).
        onClose = function()
            if not InCombatLockdown() then HideUIPanel(MacroFrame) end
        end,
    })
    win:SetIcon(TEX_ICON)

    tabs = Kit.Tabs(win, {
        { key = "account",   label = GENERAL_MACROS or "General Macros",
          tooltip = "Macros every character on your account shares." },
        { key = "character", label = CharacterTabLabel(),
          tooltip = "Macros only this character has." },
    }, OnTab)
    tabs:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, TOP)
    tabs:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, TOP)

    countText = UI.Font(win, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    countText:SetPoint("RIGHT", tabs, "RIGHT", 0, 0)
    countText:SetWordWrap(false)

    search = Kit.Search(win, LEFT_W, function(text)
        query = Kit.NormalizeQuery(text)
        list.offset = 0
        Refresh()
    end, "Search macros")
    search:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, Y1)

    win.footer = Kit.Footer(win, FOOT_H)
    newBtn = UI.Button(win.footer, NEW or "New", { width = 90, height = 24 })
    newBtn:SetPoint("RIGHT", win.footer, "RIGHT", -6, 0)
    newBtn:SetScript("OnClick", StartNew)
    UI.Tooltip(newBtn, NEW or "New", "Start a new macro in this tab. It is created when you click Create.")
    status = UI.Font(win.footer, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" })
    status:SetPoint("LEFT", win.footer, "LEFT", 8, 0)
    status:SetPoint("RIGHT", newBtn, "LEFT", -8, 0)
    status:SetWordWrap(false)

    list = Kit.List(win, {
        rowHeight = ROW_H,
        build = BuildRow,
        update = UpdateRow,
    })
    list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, Y1 - Kit.SEARCH_H - Kit.GAP)
    list:SetPoint("BOTTOMLEFT", win.footer, "TOPLEFT", Kit.PAD - 1, Kit.GAP)
    list:SetWidth(LEFT_W)

    BuildEditor()
    BuildPicker()

    local ev = CreateFrame("Frame", nil, win)
    ev:RegisterEvent("UPDATE_MACROS")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    inCombat = InCombatLockdown() and true or false
    ev:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_MACROS" then
            if win:IsVisible() then Queue() end
        else
            inCombat = (event == "PLAYER_REGEN_DISABLED")
            Lock()
        end
    end)

    -- THE X, SECURELY. HideUIPanel from an addon is refused in combat; a
    -- secure "click" on Blizzard's own close button runs their handler
    -- with secure credentials, so the X always works - and MacroFrame's
    -- own OnHide save runs untainted.
    local blizzClose = MacroFrame.CloseButton or _G.MacroFrameCloseButton
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

-- Every open starts where Blizzard's does (General, first macro) -
-- unless an unsaved draft survived a close in combat, which is kept.
local function OnOpen()
    DismissAsk()
    local keep = IsDirty() and Resync()
    if not keep then
        tab = "account"
        isNew, prevSel = false, nil
        query = ""
        search:SetText("")
        list.offset = 0
        SelectFirst()
    end
    tabs:SetLabel("character", CharacterTabLabel())
    tabs:Paint(tab)
    ClosePicker()
    UpdateCounter()
    Lock()
    Refresh(true)
end

-- Blizzard saves the selected macro's text whenever the window closes;
-- this does the same for yours. In combat nothing can be saved, so the
-- draft is kept for the next open instead.
--
-- ONE FRAME LATE, ON PURPOSE. Blizzard's OnHide writes ITS copy of its
-- selected macro back, and its copy is only re-synced by UPDATE_MACROS,
-- which it stops listening to in that same OnHide. Saved here in the
-- same hide, our write could land first and Blizzard's stale copy on top
-- of it (both sit on General macro 1 after every open). Deferred, ours is
-- always the last write, whatever order the two OnHides run in.
local function SaveOnClose()
    if win and win:IsVisible() then return end   -- reopened already
    if not IsDirty() or Locked() then return end
    -- Something else renamed or deleted it meanwhile: never write a draft
    -- over a different macro.
    if not Resync() then
        if ns.Print then ns.Print("Macro changes could not be saved - the macro changed.") end
        LoadSelected()
        return
    end
    local wasNew = isNew
    if not Save(true) and ns.Print then
        if wasNew then
            ns.Print("New macro not created (no name, or the tab is full).")
        else
            ns.Print("Macro changes could not be saved.")
        end
    end
    if not IsDirty() then return end
    -- Unsavable (no name, full tab): drop it so the next open starts clean.
    if isNew then isNew = false; sel = prevSel end
    LoadSelected()
end

local function OnClose()
    DismissAsk()
    ClosePicker()
    icons, iconsShown = nil, nil
    if IsDirty() and not Locked() then C_Timer.After(0, SaveOnClose) end
end

-- ============================================================
-- BLIZZARD'S LEFTOVERS
-- ============================================================
-- MacroFrame is a ButtonFrameTemplate window: the portrait, the border
-- art and the close button sit at frame levels 400-510, above any cover,
-- and the icon grid, the selected-macro button and the Save / Cancel /
-- Change Name buttons are HIGH strata - above the cover whatever its
-- level. All are faded and made click-through; the HIGH pieces are also
-- dropped to the window's own strata, where the cover sits over them and
-- takes their clicks and mouse wheel. Every original is recorded and
-- put back exactly when the window is turned off (Kit.Silence remembers
-- each piece's own mouse state). Built by appending, so a
-- missing piece leaves no nil hole for ipairs to stop at.
local function Leftovers()
    local t = {}
    local function Add(f) if f then t[#t + 1] = f end end
    local f = MacroFrame
    Add(f.NineSlice)
    Add(f.PortraitContainer)
    Add(f.TitleContainer)
    Add(f.CloseButton)
    Add(_G.MacroFrameCloseButton)
    Add(f.portrait)
    Add(_G.MacroFramePortrait)
    Add(_G.MacroFrameTab1)
    Add(_G.MacroFrameTab2)
    Add(_G.MacroPopupFrame)
    for _, r in ipairs({ f:GetRegions() }) do
        if not r._zui_own then Add(r) end
    end
    return t
end

local function HighStrata()
    local t = {}
    local function Add(f) if f then t[#t + 1] = f end end
    Add(MacroFrame.MacroSelector)
    Add(MacroFrame.SelectedMacroButton or _G.MacroFrameSelectedMacroButton)
    Add(_G.MacroEditButton)
    Add(_G.MacroSaveButton)
    Add(_G.MacroCancelButton)
    return t
end

-- Children created later (the grid's pooled buttons) inherit the lowered
-- strata from their parent; the walk covers the ones that exist now.
-- Every original is recorded BEFORE anything changes (a parent's strata
-- change can carry down to its children), and restored children first,
-- parent last, so the parent's own value is the one that sticks.
local function RecordStrata(f, depth)
    if not f or depth > 6 or not f.GetFrameStrata then return end
    if f._zMacStrata == nil then f._zMacStrata = f:GetFrameStrata() end
    for _, c in ipairs({ f:GetChildren() }) do RecordStrata(c, depth + 1) end
end

local function LowerStrata(f, depth, strata)
    if not f or depth > 6 or not f.SetFrameStrata then return end
    f:SetFrameStrata(strata)
    for _, c in ipairs({ f:GetChildren() }) do LowerStrata(c, depth + 1, strata) end
end

local function Demote(f)
    RecordStrata(f, 0)
    LowerStrata(f, 0, MacroFrame:GetFrameStrata())
end

local function Restore(f, depth)
    if not f or depth > 6 then return end
    for _, c in ipairs({ f:GetChildren() }) do Restore(c, depth + 1) end
    if f._zMacStrata ~= nil then
        f:SetFrameStrata(f._zMacStrata)
        f._zMacStrata = nil
    end
end

local function QuietAll()
    Kit.Silence(Leftovers())
    local high = HighStrata()
    Kit.Silence(high)
    for _, f in ipairs(high) do Demote(f) end
end

local function UnquietAll()
    local high = HighStrata()
    for _, f in ipairs(high) do Restore(f, 0) end
    Kit.Unsilence(high)
    Kit.Unsilence(Leftovers())
end

-- ============================================================
-- APPLY
-- ============================================================
-- The cover carries a secure button, so building, placing, showing and
-- hiding it are out-of-combat work; a toggle or a first load in combat
-- waits for the fight to end (Blizzard's skinned window shows meanwhile).
local function Apply()
    if not MacroFrame then return end
    if InCombatLockdown() then
        pendingApply = true
        return
    end
    pendingApply = false
    if Enabled() then
        local fresh = not win
        Build()
        if fresh then
            win:HookScript("OnShow", OnOpen)
            win:HookScript("OnHide", OnClose)
        end
        win.Reanchor()
        win:Show()
        QuietAll()
        -- Built while MacroFrame is already open: no OnShow will come.
        if fresh and win:IsVisible() then OnOpen() end
    elseif win then
        win:Hide()
        UnquietAll()
    end
end

-- ============================================================
-- MODULE
-- ============================================================
local function OnMacroUILoaded()
    if hooked or not MacroFrame then return end
    hooked = true
    local regen = CreateFrame("Frame")
    regen:RegisterEvent("PLAYER_REGEN_ENABLED")
    regen:SetScript("OnEvent", function()
        if pendingApply then Apply() end
    end)
    -- A later /zui toggle only flips the saved flag; the window checks it
    -- on every open so turning it off never needs a reload.
    MacroFrame:HookScript("OnShow", function()
        if InCombatLockdown() then
            if not win or win:IsShown() ~= (Enabled() and true or false) then pendingApply = true end
            if win and win:IsShown() then QuietAll() end
        else
            Apply()
        end
    end)
    Apply()
end

Modules.macroswin = function()
    if ns._zMacrosWin then return end
    ns._zMacrosWin = true
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if isLoaded and isLoaded(LOD_NAME) and MacroFrame then
        OnMacroUILoaded()
        return
    end
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("ADDON_LOADED")
    watch:SetScript("OnEvent", function(self, _, name)
        if name ~= LOD_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        -- A frame later, so Blizzard's OnLoad and the skin parked in the
        -- LoD registry for this addon have both run first.
        C_Timer.After(0, function()
            local ok, err = pcall(OnMacroUILoaded)
            if not ok and ns.Print then ns.Print(LOD_NAME .. " window failed: " .. tostring(err)) end
        end)
    end)
end
