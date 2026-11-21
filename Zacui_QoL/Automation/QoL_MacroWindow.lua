-- QoL_MacroWindow - the macro cleaner: every macro in one list with a
-- tick, deleted in one go (2026-11-20, Zac: "a fast macro deleter with
-- maybe the option to do it automatically as well").
-- Part of ZacUI; load order is set by the TOC (after QoL_MacroCleanup,
-- whose engine this draws: MC.Survey, MC.DeleteAll, the bin, the
-- always-delete list).
--
--   /zui macros   /zmacros   the "Clean up" button on the macro window
--   Quality of life > Macros > "Open the macro cleaner"
--
-- FOUR TABS
--   Account / Character   every macro of that kind: icon, name, its first
--       line, and what uses it (on your bars, key bound, used by another
--       character, unused). Tick rows (a click anywhere on the row), or
--       All / None / Unused; the search box narrows the list by name or
--       text. Delete removes every ticked one. "...and delete them again
--       whenever they come back" also puts their names on the
--       always-delete list and switches that list on.
--   Always delete   the names deleted on sight, with the switch for it;
--       ticked names are taken off the list.
--   Bin   everything deleted (by hand or by itself), newest first;
--       ticked ones are made again. "Empty the bin" forgets them for good.
--
-- Nothing is lost by a delete: each macro is binned first. ZacUI's own
-- macros (the buff remover's, anything with its marks) are listed greyed
-- and cannot be ticked. Macros cannot be changed in a fight (the game
-- refuses), so the action buttons are greyed then and say why.
--
-- COST: nothing until it is opened. While open it listens for the macro
-- list, a bar slot or a key binding changing and for a fight starting or
-- ending, and redraws once a moment later (one short timer, nothing in
-- the event). Closed, it listens for nothing.

local ADDON_NAME = ...
local ns = _G.ZacUI
if not ns then return end

local GetColor = ns.GetColor
local Print = ns.Print
local QoL = ns.QoL
local MC = QoL and QoL.MacroCleanup
if not MC then return end

local W = {}
MC.Window = W

local WIN_NAME = "ZacUIMacroCleaner"
local WIN_W, WIN_H = 620, 540
local MIN_W, MIN_H, MAX_W, MAX_H = 590, 340, 1100, 1200   -- (narrower and the four tabs do not fit)
local ROW_H = 24
local TABS_H, TOOLS_H = 26, 28
local NAME_W, TAG_W = 150, 150
local IN_FIGHT = "Macros cannot be changed in a fight. It works again when the fight ends."

W.TABS = {
    { id = "account",   label = "Account" },
    { id = "character", label = "Character" },
    { id = "always",    label = "Always delete" },
    { id = "bin",       label = "Bin" },
}

local win
local rows = {}                 -- pooled row frames
local entries = {}              -- what the rows show now
local tab = "account"
local picked = { account = {}, character = {}, always = {}, bin = {} }
local query = ""
local keep = false              -- "...and delete them again whenever they come back"

local function MaxAccount() return MAX_ACCOUNT_MACROS or 120 end
local function MaxChar() return MAX_CHARACTER_MACROS or 18 end
local function InFight() return (InCombatLockdown and InCombatLockdown()) and true or false end

-- ============================================================
-- WHAT A TAB LISTS
--   { id, name, icon, sub, tag, tagKey, locked, macro | binIndex }
-- ============================================================
local function Matches(m)
    if query == "" then return true end
    local q = query:lower()
    return (m.name or ""):lower():find(q, 1, true) ~= nil or (m.body or ""):lower():find(q, 1, true) ~= nil
end

local function UseTag(m)
    if m.protected then return "ZacUI's own", "disabled" end
    if m.bar and m.key then return "on your bars, key bound", "gray" end
    if m.bar then return "on your bars", "gray" end
    if m.key then return "key bound", "gray" end
    if m.others then return "used by " .. m.others, "gray" end
    return "unused", "orange"
end

local function MacroEntries(account)
    local out = {}
    for _, m in ipairs(MC.Survey()) do
        if m.account == account and Matches(m) then
            local tag, tagKey = UseTag(m)
            if m.always and not m.protected then tag = tag .. ", on the delete list" end
            out[#out + 1] = { id = m.id, name = m.name, icon = m.icon, sub = MC.Preview(m.body),
                tag = tag, tagKey = tagKey, locked = m.protected or false, macro = m }
        end
    end
    return out
end

local function AlwaysEntries()
    local out = {}
    local have = {}
    for _, m in ipairs(MC.AllMacros()) do have[m.name] = (have[m.name] or 0) + 1 end
    for _, name in ipairs(MC.AlwaysNames()) do
        if query == "" or name:lower():find(query:lower(), 1, true) then
            local n = have[name] or 0
            out[#out + 1] = { id = name, name = name, icon = 134400,
                sub = (n == 0) and "none right now" or (n == 1 and "1 macro has this name now" or (n .. " macros have this name now")),
                tag = "", tagKey = "gray" }
        end
    end
    return out
end

local function BinEntries()
    local out = {}
    local bin = MC.Bin()
    for i = #bin, 1, -1 do
        local m = bin[i]
        if type(m) == "table" and Matches(m) then
            local who = tostring(m.who or "?"):match("^(.-)%-") or tostring(m.who or "?")
            local when = (m.t and date) and date("%d %b %H:%M", m.t) or ""
            out[#out + 1] = { id = tostring(i), name = tostring(m.name), icon = m.icon, sub = MC.Preview(m.body),
                tag = (m.account and "account" or "character") .. ", " .. who .. (when ~= "" and (", " .. when) or ""),
                tagKey = "gray", binIndex = i, macro = m }
        end
    end
    return out
end

function W.Entries(which)
    which = which or tab
    if which == "account" then return MacroEntries(true) end
    if which == "character" then return MacroEntries(false) end
    if which == "always" then return AlwaysEntries() end
    return BinEntries()
end

local function PickedCount(which)
    local n = 0
    for _ in pairs(picked[which or tab]) do n = n + 1 end
    return n
end
-- the ticked entries of the tab on show (a tick on a macro that has since
-- gone is dropped)
local function PickedEntries()
    local out, live = {}, {}
    for _, e in ipairs(W.Entries(tab)) do
        if picked[tab][e.id] and not e.locked then
            out[#out + 1] = e
            live[e.id] = true
        end
    end
    -- (a search hides rows without unticking them: only ids that no longer
    -- exist at all are dropped)
    if query == "" then
        for id in pairs(picked[tab]) do if not live[id] then picked[tab][id] = nil end end
    end
    return out
end

-- ============================================================
-- THE ACTIONS
-- ============================================================
local Refresh

local function DeletePicked()
    local list = {}
    for _, e in ipairs(PickedEntries()) do list[#list + 1] = e.macro end
    if #list == 0 then return end
    local alsoKeep = keep
    local function Go()
        if InFight() then
            Print("macros: " .. IN_FIGHT)
            return
        end
        local n = MC.DeleteAll(list)
        if alsoKeep then
            for _, m in ipairs(list) do MC.SetAlways(m.name, true) end
            MC.SetOpt("autoNames", true)
        end
        picked[tab] = {}
        Print("macros: deleted " .. n .. (n == 1 and " macro" or " macros") .. " (the Bin tab brings one back)"
            .. (alsoKeep and ", and they are deleted again whenever they come back." or "."))
        Refresh()
    end
    if MC.Opt("confirm") then
        ns.UI.Confirm({
            title = "Delete macros",
            text = "Delete " .. (#list == 1 and "this macro" or ("these " .. #list .. " macros")) .. "? "
                .. (#list == 1 and "It goes" or "Each goes") .. " into the bin first, and the Bin tab makes "
                .. (#list == 1 and "it" or "one") .. " again."
                .. (alsoKeep and " Their names also go on the always-delete list." or ""),
            acceptText = DELETE or "Delete",
            destructive = true,
            onAccept = Go,
        })
    else
        Go()
    end
end

local function UnlistPicked()
    local n = 0
    for _, e in ipairs(PickedEntries()) do
        MC.SetAlways(e.name, false)
        n = n + 1
    end
    picked.always = {}
    if n > 0 then Print("macros: " .. n .. (n == 1 and " name is" or " names are") .. " no longer deleted on sight.") end
    Refresh()
end

local function RestorePicked()
    if InFight() then
        Print("macros: " .. IN_FIGHT)
        return
    end
    local idx = {}
    for _, e in ipairs(PickedEntries()) do idx[#idx + 1] = e.binIndex end
    if #idx == 0 then return end
    local n, why = MC.RestoreMany(idx)
    picked.bin = {}
    Print("macros: restored " .. n .. (n == 1 and " macro" or " macros")
        .. (why and (" (" .. (#idx - n) .. " not: " .. tostring(why) .. ")") or "") .. ".")
    Refresh()
end

local function EmptyBin()
    local n = #MC.Bin()
    if n == 0 then return end
    ns.UI.Confirm({
        title = "Empty the bin",
        text = "Forget " .. (n == 1 and "the 1 deleted macro" or ("all " .. n .. " deleted macros"))
            .. " in the bin? They cannot be brought back after this.",
        acceptText = "Empty it",
        destructive = true,
        onAccept = function()
            MC.EmptyBin()
            picked.bin = {}
            Refresh()
        end,
    })
end

-- (each reads the list again first: a bar or a key may have changed since
-- the rows were drawn)
function W.SelectAll()
    entries = W.Entries(tab)
    for _, e in ipairs(entries) do
        if not e.locked then picked[tab][e.id] = true end
    end
    Refresh()
end
function W.SelectNone()
    picked[tab] = {}
    Refresh()
end
-- only the unused ones (of what the search shows)
function W.SelectUnused()
    picked[tab] = {}
    entries = W.Entries(tab)
    for _, e in ipairs(entries) do
        if not e.locked and e.macro and e.macro.unused then picked[tab][e.id] = true end
    end
    Refresh()
end

-- ============================================================
-- THE ROWS
-- ============================================================
local function RowTip(self)
    local e = self._zEntry
    if not e or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(e.name or "", 1, 1, 1)
    local m = e.macro
    if m and m.body and m.body ~= "" then
        for line in (m.body .. "\n"):gmatch("([^\r\n]*)\r?\n") do
            if line ~= "" then GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
        end
    end
    if e.tag and e.tag ~= "" then GameTooltip:AddLine(e.tag, 0.6, 0.6, 0.6, true) end
    if e.locked then
        GameTooltip:AddLine("One of ZacUI's own macros: it is not deleted from here.", 0.6, 0.6, 0.6, true)
    elseif m and m.bar and tab ~= "bin" then
        GameTooltip:AddLine("Deleting it empties the bar slots it sits in.", 1, 0.6, 0.2, true)
    end
    GameTooltip:Show()
end

local function SetRowPicked(row, on)
    local e = row._zEntry
    if not e or e.locked then return end
    picked[tab][e.id] = on and true or nil
    row._zCheck:SetChecked(on and true or false)
    row._zPickFill:SetShown(on and true or false)
    if W.UpdateFooter then W.UpdateFooter() end
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    local UI = ns.UI
    local S = UI.S
    row = CreateFrame("Button", nil, win.child)
    row:SetHeight(ROW_H)
    -- hover, and the ticked wash (green = picked: ZacUI's selected colour)
    local hot = row:CreateTexture(nil, "BACKGROUND")
    hot._zui_own = true
    hot:SetAllPoints()
    hot:SetColorTexture(1, 1, 1, 0.04)
    hot:Hide()
    row._zHotFill = hot
    local pick = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    pick._zui_own = true
    pick:SetAllPoints()
    local g = GetColor("text", "green")
    pick:SetColorTexture(g.r, g.g, g.b, 0.10)
    pick:Hide()
    row._zPickFill = pick

    local check = UI.SettingsBuild(UI.Checkbox, row, "", false, function(v) SetRowPicked(row, v) end)
    check:SetPoint("LEFT", row, "LEFT", 6, 0)
    check:SetWidth(S.CHECK or 18)          -- (the box alone: it has no label)
    row._zCheck = check
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon._zui_own = true
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", row, "LEFT", 32, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row._zIcon = icon
    local name = UI.SFont(row, S.F_VALUE, { text = "", justify = "LEFT" })
    name:SetPoint("LEFT", row, "LEFT", 58, 0)
    name:SetWidth(NAME_W)
    name:SetWordWrap(false)
    row._zName = name
    local tag = UI.SFont(row, S.F_HINT, { text = "", justify = "RIGHT" })
    tag:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    tag:SetWidth(TAG_W)
    tag:SetWordWrap(false)
    row._zTag = tag
    local sub = UI.SFont(row, S.F_HINT, { text = "", justify = "LEFT" })
    sub:SetPoint("LEFT", name, "RIGHT", 8, 0)
    sub:SetPoint("RIGHT", tag, "LEFT", -8, 0)
    sub:SetWordWrap(false)
    sub._zPaint = function(self) self:SetTextColor(1, 1, 1, S.DIM_A) end
    sub:_zPaint()
    row._zSub = sub

    row:SetScript("OnClick", function(self)
        local e = self._zEntry
        if not e or e.locked then return end
        SetRowPicked(self, not picked[tab][e.id])
    end)
    local function Enter() hot:Show() RowTip(row) end
    local function Leave() hot:Hide() if GameTooltip then GameTooltip:Hide() end end
    row:SetScript("OnEnter", Enter)
    row:SetScript("OnLeave", Leave)
    check:HookScript("OnEnter", Enter)
    check:HookScript("OnLeave", Leave)
    rows[i] = row
    return row
end

local function PaintRow(row, e)
    row._zEntry = e
    row._zIcon:SetTexture(e.icon or 134400)
    row._zName:SetText(e.name or "")
    row._zSub:SetText(e.sub or "")
    row._zTag:SetText(e.tag or "")
    local nameC = e.locked and GetColor("text", "disabled") or GetColor("text", "normal")
    row._zName._zPaint = function(self) self:SetTextColor(nameC.r, nameC.g, nameC.b, e.locked and 0.5 or 1) end
    row._zName:_zPaint()
    local tc = GetColor("text", e.tagKey or "gray")
    row._zTag._zPaint = function(self) self:SetTextColor(tc.r, tc.g, tc.b, 1) end
    row._zTag:_zPaint()
    row._zIcon:SetDesaturated(e.locked and true or false)
    row._zIcon:SetAlpha(e.locked and 0.45 or 1)
    local on = (not e.locked) and picked[tab][e.id] == true
    row._zCheck:SetChecked(on)
    row._zCheck:SetAlpha(e.locked and 0.3 or 1)
    row._zCheck:EnableMouse(not e.locked)
    row._zPickFill:SetShown(on)
end

-- ============================================================
-- THE WINDOW
-- ============================================================
local function TabLabel(t)
    if t.id == "account" then
        local a = GetNumMacros and GetNumMacros() or 0
        return t.label .. "  " .. (a or 0) .. " / " .. MaxAccount()
    elseif t.id == "character" then
        local _, c = 0, 0
        if GetNumMacros then _, c = GetNumMacros() end
        return t.label .. "  " .. (c or 0) .. " / " .. MaxChar()
    elseif t.id == "always" then
        return t.label .. "  " .. #MC.AlwaysNames()
    end
    return t.label .. "  " .. #MC.Bin()
end

function W.UpdateFooter()
    if not win then return end
    local n = PickedCount()
    local fight = InFight()
    local specs
    if tab == "always" then
        specs = { { text = n > 0 and ("Take " .. n .. " off the list") or "Take off the list", width = 170, onClick = UnlistPicked } }
    elseif tab == "bin" then
        specs = {
            { text = "Empty the bin", width = 130, onClick = EmptyBin },
            { text = n > 0 and ("Restore " .. n) or "Restore", kind = "primary", width = 120, onClick = RestorePicked },
        }
    else
        specs = { { text = n > 0 and ((DELETE or "Delete") .. " " .. n) or (DELETE or "Delete"), kind = "destructive",
            width = 130, onClick = DeletePicked } }
    end
    local b = win:SetButtons(specs)
    if tab == "bin" then
        b[1]:SetDisabled(#MC.Bin() == 0, "The bin is empty.")
        b[2]:SetDisabled(n == 0 or fight, fight and IN_FIGHT or "Tick the macros to bring back first.")
    elseif tab == "always" then
        b[1]:SetDisabled(n == 0, "Tick the names to take off the list first.")
    else
        b[1]:SetDisabled(n == 0 or fight, fight and IN_FIGHT or "Tick the macros to delete first.")
    end
    win._zKeep:SetShown(tab == "account" or tab == "character")
    win._zKeep:SetChecked(keep)
end

local function Layout()
    local UI = ns.UI
    local top = win.headerHeight
    local x = win.pad
    for _, t in ipairs(W.TABS) do
        local b = win._zTabs[t.id]
        b:SetLabel(TabLabel(t))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", win, "TOPLEFT", x, -top)
        b:SetActive(tab == t.id)
        x = x + math.ceil(b:GetWidth() or 100) + 6
    end
    local toolsY = -(top + TABS_H + 8)
    local macros = (tab == "account" or tab == "character")
    win._zSearch:ClearAllPoints()
    win._zSearch:SetPoint("TOPLEFT", win, "TOPLEFT", win.pad, toolsY)
    win._zUnused:SetShown(macros)
    win._zAuto:SetShown(tab == "always")
    win._zAuto:SetChecked(MC.Opt("autoNames") == true)
    -- All / None / Unused, right of the search box
    win._zAll:ClearAllPoints()
    win._zAll:SetPoint("LEFT", win._zSearch, "RIGHT", 8, 0)
    win._zNone:ClearAllPoints()
    win._zNone:SetPoint("LEFT", win._zAll, "RIGHT", 4, 0)
    win._zUnused:ClearAllPoints()
    win._zUnused:SetPoint("LEFT", win._zNone, "RIGHT", 4, 0)
    win._zAuto:ClearAllPoints()
    win._zAuto:SetPoint("LEFT", win._zNone, "RIGHT", 12, 0)
    local listTop = top + TABS_H + 8 + TOOLS_H + 8
    win.scroll:ClearAllPoints()
    win.scroll:SetPoint("TOPLEFT", win, "TOPLEFT", win.pad - 6, -listTop)
    win.scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -(UI.M.SCROLL_W + 6), win:FooterHeight() + 2)
    win.scroll.bar:ClearAllPoints()
    win.scroll.bar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -listTop)
    win.scroll.bar:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -4, win:FooterHeight() + 2)
end

local EMPTY = {
    account = "No account macros.",
    character = "This character has no macros of its own.",
    always = "No names yet. Tick macros on the Account or Character tab, tick \"...and delete them again "
        .. "whenever they come back\", and Delete: their names land here.",
    bin = "Nothing has been deleted yet.",
}

Refresh = function()
    if not win then return end
    entries = W.Entries(tab)
    W.UpdateFooter()
    Layout()
    local width = math.max(200, (win:GetWidth() or WIN_W) - (win.pad - 6) - (ns.UI.M.SCROLL_W + 6))
    win.child:SetWidth(width)
    for i, e in ipairs(entries) do
        local row = Row(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win.child, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetWidth(width)
        PaintRow(row, e)
        row:Show()
    end
    for i = #entries + 1, #rows do
        rows[i]:Hide()
        rows[i]._zEntry = nil
    end
    local h = math.max(1, #entries * ROW_H)
    win.child:SetHeight(h)
    win.scroll:Recalculate(h)
    if #entries == 0 then
        win._zEmpty:SetText((query ~= "" and tab ~= "always") and "Nothing matches the search." or EMPTY[tab])
        win._zEmpty:Show()
    else
        win._zEmpty:Hide()
    end
    local a, c = 0, 0
    if GetNumMacros then a, c = GetNumMacros() end
    win:SetTitle("Macros", InFight() and "In a fight: nothing can be deleted or restored until it ends."
        or ((a or 0) .. " account, " .. (c or 0) .. " character. Deleted macros go to the bin first."))
    Layout()      -- (the title's second line can change the header's height)
end
W.Refresh = Refresh

-- one redraw a moment after the last change
local queued = false
local function Queue()
    if queued then return end
    queued = true
    C_Timer.After(0.2, function()
        queued = false
        if win and win:IsShown() then pcall(Refresh) end
    end)
end
W.Queue = Queue

local function Build()
    if win then return win end
    local UI = ns.UI
    win = UI.Popup(WIN_NAME, WIN_W, WIN_H, "Macros", { rule = true, size = "small", desc = " ", part = "qol" })
    win._zOnMoved = function()
        local p = { win:GetPoint(1) }
        MC.DB().winPos = { p[1], math.floor((p[4] or 0) + 0.5), math.floor((p[5] or 0) + 0.5) }
    end
    local d = MC.DB()
    if type(d.winSize) == "table" then
        win:SetSize(math.max(MIN_W, math.min(MAX_W, tonumber(d.winSize[1]) or WIN_W)),
                    math.max(MIN_H, math.min(MAX_H, tonumber(d.winSize[2]) or WIN_H)))
    end
    if type(d.winPos) == "table" then
        win:ClearAllPoints()
        win:SetPoint(d.winPos[1] or "CENTER", UIParent, d.winPos[1] or "CENTER", d.winPos[2] or 0, d.winPos[3] or 0)
    end

    win._zTabs = {}
    for _, t in ipairs(W.TABS) do
        local id = t.id
        local b = UI.SettingsBuild(UI.Button, win, t.label, { width = 90, height = TABS_H, onClick = function()
            if tab == id then return end
            tab = id
            win.scroll:SetVerticalScroll(0)
            win.scroll.bar:SetValue(0)
            Refresh()
        end })
        win._zTabs[id] = b
    end
    win._zSearch = UI.SettingsBuild(UI.EditBox, win, { width = 210, height = TOOLS_H, hint = "Search name or text",
        onChange = function(t)
            query = (t or ""):gsub("^%s+", ""):gsub("%s+$", "")
            Queue()
        end })
    local function Tool(label, w, tip, fn)
        local b = UI.SettingsBuild(UI.Button, win, label, { width = w, height = TOOLS_H, onClick = fn })
        UI.Tooltip(b, label, tip)
        return b
    end
    win._zAll = Tool("All", 50, "Tick every row listed.", function() W.SelectAll() end)
    win._zNone = Tool("None", 56, "Untick everything in this tab.", function() W.SelectNone() end)
    win._zUnused = Tool("Unused", 72, "Tick only the macros nothing uses: on no action bar, no key bound, and (account "
        .. "macros) on no other character seen so far.", function() W.SelectUnused() end)
    win._zAuto = UI.SettingsBuild(UI.Checkbox, win, "Delete these on sight", MC.Opt("autoNames") == true, function(v)
        MC.SetOpt("autoNames", v)
        if ns.RefreshConfig then pcall(ns.RefreshConfig) end
    end, { tooltip = "A macro with one of these names is deleted a few seconds after you log in and whenever it is "
        .. "made again - for the macros another addon keeps creating. Off: the list is kept and nothing is deleted." })

    local scroll, child = UI.ScrollArea(win, { style = "settings" })
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    win.scroll, win.child = scroll, child
    win._zEmpty = UI.PopupText(win, "hint", { text = "", justify = "CENTER", width = 380 })
    win._zEmpty:SetPoint("TOP", scroll, "TOP", 0, -40)
    win._zEmpty:Hide()

    -- the foot: the "keep them deleted" tick, level with the button
    win._zKeep = UI.SettingsBuild(UI.Checkbox, win, "...and delete them again whenever they come back", keep, function(v)
        keep = v and true or false
    end, { tooltip = "Also puts the names of what you delete now on the always-delete list and switches that list on: "
        .. "a macro with one of those names is deleted again whenever it turns up. For the macros another addon "
        .. "keeps making." })
    win._zKeep:ClearAllPoints()
    win._zKeep:SetPoint("LEFT", win, "BOTTOMLEFT", win.pad - 2, (win.pad - 4) + UI.POP.BTN_H / 2)

    UI.AttachResizeGrip(win, { minW = MIN_W, minH = MIN_H, maxW = MAX_W, maxH = MAX_H,
        onResizeStopped = function(f)
            MC.DB().winSize = { math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5) }
            if win._zOnMoved then win._zOnMoved() end
            Refresh()
        end })

    local ev = CreateFrame("Frame", nil, win)
    ev:SetScript("OnEvent", Queue)
    win:HookScript("OnShow", function()
        ev:RegisterEvent("UPDATE_MACROS")
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        -- (what uses a macro: a bar slot or a key changing while it is open)
        ev:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        ev:RegisterEvent("UPDATE_BINDINGS")
    end)
    win:HookScript("OnHide", function()
        ev:UnregisterAllEvents()
        -- closed: the ticks and the search are for one sitting
        picked = { account = {}, character = {}, always = {}, bin = {} }
        keep = false
    end)
    win._zEvents = ev
    return win
end

function W.Frame() return win end
function W.Tab() return tab end
function W.Rows() return rows end
function W.Picked(which) return picked[which or tab] end
function W.SetTab(id)
    for _, t in ipairs(W.TABS) do
        if t.id == id then tab = id end
    end
    if win and win:IsShown() then Refresh() end
end

function W.Open(which)
    Build()
    if which then
        for _, t in ipairs(W.TABS) do if t.id == which then tab = which end end
    end
    Refresh()
    if win:IsShown() then win:Raise() return end
    ns.UI.OpenWindow(win)
end
function W.Close()
    if win and win:IsShown() then ns.UI.CloseWindow(win) end
end
function W.Toggle(which)
    if win and win:IsShown() and not win._zAnim then W.Close() else W.Open(which) end
end
MC.Open, MC.Toggle = W.Open, W.Toggle
-- the automatic part deleted something: an open window shows it
MC.OnChanged = Queue

-- ============================================================
-- WAYS IN
-- ============================================================
ns.SlashCommands = ns.SlashCommands or {}
local function Slash(rest)
    local which = (rest or ""):lower():match("^(%a+)")
    if which == "bin" or which == "always" or which == "account" or which == "character" then
        W.Open(which)
    else
        W.Toggle()
    end
end
ns.SlashCommands.macros = Slash
ns.SlashCommands.macro = Slash
if SlashCmdList then
    SLASH_ZACUIMACROS1 = "/zmacros"
    SlashCmdList["ZACUIMACROS"] = function(msg) Slash(msg) end
end

-- THE BUTTON ON THE GAME'S OWN MACRO WINDOW (only where ZacUI's macro
-- window is not covering it: that one has the button in its footer,
-- Win_Macros.lua). It sits OUTSIDE the game's panel, over its top right
-- corner, so it lies on nothing of the game's on any game version.
-- Made and placed out of a fight only.
local gameBtn
local function GameButton()
    local frame = _G.MacroFrame
    if not frame then return end
    local cover = ns.MacroCover and ns.MacroCover()
    local want = MC.Opt("button") and not (cover and cover:IsShown())
    if not want then
        if gameBtn then gameBtn:Hide() end
        return
    end
    if not gameBtn then
        if InFight() then return end
        local UI = ns.UI
        gameBtn = UI.Button(frame, "Clean up", { width = 84, height = 22, onClick = function() W.Toggle() end })
        gameBtn:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -4, 2)
        UI.Tooltip(gameBtn, "Clean up macros", "ZacUI's macro cleaner: every macro with a tick, deleted in one go. /zui macros")
    end
    gameBtn:Show()
end
W.GameButton = function() return gameBtn end
W.SyncGameButton = GameButton
local function HookGameWindow()
    local frame = _G.MacroFrame
    if not frame or frame._zCleanerHooked then return end
    frame._zCleanerHooked = true
    frame:HookScript("OnShow", function() C_Timer.After(0, function() pcall(GameButton) end) end)
    if frame:IsShown() then C_Timer.After(0, function() pcall(GameButton) end) end
end
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self, event, name)
        if event == "ADDON_LOADED" and name ~= "Blizzard_MacroUI" then return end
        if _G.MacroFrame then
            HookGameWindow()
            self:UnregisterAllEvents()
        end
    end)
end

if ns.AddMenuKeywords then
    ns.AddMenuKeywords("qol", "macro macros delete deleter cleaner clean up bulk unused bin restore always delete on sight")
end
