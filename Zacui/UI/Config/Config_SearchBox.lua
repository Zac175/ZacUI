-- Config_SearchBox - the search box at the top of the config window's
-- sidebar and the dropdown of results under it.
-- Part of ZacUI; load order is set by the TOC (after Config_Search, which
-- owns the index and the ranking; before Config_Window, which hands this
-- file its nav column and its jump when it builds).
--
-- HOW IT READS. Type, and a list drops under the box: up to twelve rows,
-- each with what kind of thing it is (Page / Section / Setting /
-- Command) in the accent colour, its title, and under that where it
-- lives ("Screen  >  Action bars  >  Look"). The first row is lit; the
-- arrow keys (or Tab) move the light, Enter opens the lit row, Escape
-- closes the list, a click anywhere else closes it, a click on a row
-- opens it. The page behind stays as it was - the results never take the
-- content pane over - and the sidebar still narrows to the pages that
-- have a hit, as it always did.
--
-- Opening a result: a page opens; a section or setting opens its page on
-- the right tab, scrolls it into view and flashes it (Config_Window's
-- jump); a command runs, or is put in the chat box when it needs words
-- added. Ctrl+F while the window is open puts the cursor in the box;
-- /zui search <words> opens the window with the words typed.
--
-- The index is read the first time the box is focused (one page per
-- frame, see Config_Search) and never at login; nothing here persists.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local UI = ns.UI
local Search = ns.ConfigSearch
local FLAT = ns.FLAT

local M, F = UI.M, UI.F

local Box = {}

local MAX_ROWS = 12
local DEBOUNCE = 0.12

local window, nav, host, eb, popup, api
local rows = {}
local lastQuery, lastResults, lastHits = "", {}, {}
local shown = {}      -- the results on the rows now
local sel = 1
local serial = 0
local msg               -- the one-line notice row (nothing found / still reading)

-- ============================================================
-- STATE FOR THE WINDOW
-- ============================================================
function Box.Query() return lastQuery end
function Box.Hits() return lastHits end
function Box.Results() return lastResults end
function Box.IsOpen() return popup ~= nil and popup:IsShown() end
function Box.Selected() return shown[sel] end

-- Best result on one page, for a sidebar row clicked while searching.
function Box.BestFor(itemId)
    for _, r in ipairs(lastResults) do
        if r.item == itemId then return r end
    end
end

-- ============================================================
-- THE DROPDOWN
-- ============================================================
local function AccentHex()
    local a = GetColor("ui", "accent")
    return string.format("%02x%02x%02x", math.floor(a.r * 255 + 0.5),
        math.floor(a.g * 255 + 0.5), math.floor(a.b * 255 + 0.5))
end

local function PaintRow(row)
    local on = row._zSel or row._zHot
    if on then
        -- (the settings window's menu: white 0.08 under the lit row)
        row.hl:SetVertexColor(1, 1, 1, UI.S.DD_HL_A)
        row.hl:Show()
    else
        row.hl:Hide()
    end
    if row.title._zPaint then row.title:_zPaint() end
    if row.sub._zPaint then row.sub:_zPaint() end
end

local function Select(i, paintOnly)
    local n = #shown
    if n == 0 then sel = 1 return end
    if not paintOnly then
        if i < 1 then i = n elseif i > n then i = 1 end
        sel = i
    end
    for k, row in ipairs(rows) do
        row._zSel = (k == sel) and row:IsShown()
        PaintRow(row)
    end
end

local Go

local function NewRow(i)
    local row = CreateFrame("Button", nil, popup)
    row:SetPoint("LEFT", popup, "LEFT", 2, 0)
    row:SetPoint("RIGHT", popup, "RIGHT", -2, 0)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl._zui_own = true
    row.hl:SetAllPoints()
    row.hl:SetTexture(FLAT)
    row.hl:Hide()
    -- "Setting: Icon zoom" - the kind in the accent, the title plain
    row.title = UI.SFont(row, UI.S.F_LABEL, { justify = "LEFT" })
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
    row.title:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.title:SetWordWrap(false)
    -- where it lives, in the muted text
    row.sub = UI.SFont(row, UI.S.F_VALUE, { justify = "LEFT", cat = "text", key = "gray" })
    row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.sub:SetWordWrap(false)
    UI.TruncTip(row.title, row)
    UI.TruncTip(row.sub, row)
    row._zPaint = PaintRow
    row:SetScript("OnEnter", function(self)
        self._zHot = true
        if shown[i] then Select(i) else PaintRow(self) end
    end)
    row:SetScript("OnLeave", function(self)
        self._zHot = nil
        PaintRow(self)
    end)
    row:SetScript("OnClick", function()
        if shown[i] then Go(shown[i]) end
    end)
    rows[i] = row
    return row
end

local function Row(i) return rows[i] or NewRow(i) end

-- Two lines of this font size, plus air. Measured off a row, so a bigger
-- font makes taller rows rather than clipped ones.
local function RowHeight()
    local r = rows[1]
    local th = (r and r.title.GetStringHeight and r.title:GetStringHeight()) or 0
    local sh = (r and r.sub.GetStringHeight and r.sub:GetStringHeight()) or 0
    if type(th) ~= "number" or th < 6 then th = UI.S.F_LABEL + 2 end
    if type(sh) ~= "number" or sh < 6 then sh = UI.S.F_VALUE + 2 end
    return math.ceil(th + sh) + 12
end

local function PopupWidth()
    local ww = (window and window:GetWidth()) or 780
    return math.max(260, math.min(400, ww - 24))
end

local function Hide()
    if popup then popup:Hide() end
end

local function Place()
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -3)
    popup:SetWidth(PopupWidth())
end

-- Draw the results on the rows (the first lit) and show the list.
local function Draw()
    if not popup then return end
    local hex = AccentHex()
    local n = math.min(#lastResults, MAX_ROWS)
    for k = 1, MAX_ROWS do
        local r = lastResults[k]
        local row = Row(k)
        if r and k <= n then
            shown[k] = r
            row.title:SetText("|cff" .. hex .. Search.Kind(r) .. ":|r " .. (r.label or ""))
            row.title._zPaintCat, row.title._zPaintKey = "text", "normal"
            row.sub:SetText(Search.Crumb(r))
            row:Show()
        else
            shown[k] = nil
            row:Hide()
        end
    end
    for k = n + 1, #shown do shown[k] = nil end
    -- nothing (yet): one quiet line says so, so the search is seen to run
    if n == 0 then
        local row = Row(1)
        row.title:SetText(Search.IsIndexing()
            and "Still reading the pages - results appear as they come in."
            or "Nothing matches. Try fewer words, or the start of a word.")
        row.title._zPaintCat, row.title._zPaintKey = "text", "gray"
        row.sub:SetText("")
        row:Show()
    end
    local rh = RowHeight()
    local count = math.max(n, 1)
    for k = 1, count do
        local row = rows[k]
        row:SetHeight(rh)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 2, -2 - (k - 1) * rh)
        row:SetPoint("RIGHT", popup, "RIGHT", -2, 0)
    end
    popup:SetHeight(count * rh + 4)
    Place()
    if sel > n then sel = 1 end
    Select(sel, true)
    if not popup:IsShown() then
        UI.CloseAllDropdowns()
        popup:Show()
    end
    popup:_zPaint()
end

-- ============================================================
-- RUNNING A SEARCH
-- ============================================================
local function Run(text)
    lastQuery = text or ""
    lastResults, lastHits = Search.Run(lastQuery)
end

local function Clear()
    lastQuery, lastResults, lastHits = "", {}, {}
    for k in pairs(shown) do shown[k] = nil end
    sel = 1
    Hide()
end

-- The index fills in over a few frames; once it is complete, redraw
-- whatever is showing so partial results become whole.
local function OnIndexed()
    if not (window and window:IsShown()) then return end
    local text = eb:GetText() or ""
    if not text:find("%S") then return end
    Run(text)
    if api and api.BuildNav then api.BuildNav() end
    if popup:IsShown() or eb:HasFocus() then Draw() end
end

-- Typing waits a beat before searching, so a fast word is one search,
-- not six half-word redraws.
local function OnChanged()
    serial = serial + 1
    local mine = serial
    C_Timer.After(DEBOUNCE, function()
        if mine ~= serial or not (window and window:IsShown()) then return end
        local text = eb:GetText() or ""
        if not text:find("%S") then
            Clear()
            if api and api.BuildNav then api.BuildNav() end
            return
        end
        Search.EnsureIndex(OnIndexed)
        Run(text)
        sel = 1
        if api and api.BuildNav then api.BuildNav() end
        Draw()
    end)
end

-- Open a result: the box empties and the list goes, then the page (and
-- its setting) shows, or the command runs.
Go = function(r)
    if not r then return end
    serial = serial + 1   -- a pending redraw would undo the jump
    local hadText = (eb:GetText() or "") ~= ""
    eb:SetText("")
    eb:ClearFocus()
    Clear()
    if r.kind == "command" then
        local how = Search.RunCommand(r)
        if how == false and ns.Print then ns.Print("That command is not here on this client.") end
        if hadText and api and api.BuildNav then api.BuildNav() end
        return
    end
    if api and api.JumpTo then api.JumpTo(r) end
end
Box.Go = Go

local function OnEnter()
    local text = eb:GetText() or ""
    if not text:find("%S") then return end
    if #shown == 0 or lastQuery ~= text then
        serial = serial + 1
        Search.EnsureIndex(OnIndexed)
        Run(text)
        sel = 1
    end
    local r = (lastResults[sel] and sel <= MAX_ROWS) and lastResults[sel] or lastResults[1]
    if r then Go(r) else Draw() end
end

-- Escape: the search is over - list gone, box empty, cursor out.
local function OnEscape()
    serial = serial + 1
    eb:SetText("")
    eb:ClearFocus()
    Clear()
    if api and api.BuildNav then api.BuildNav() end
end

local function Step(d)
    if not popup:IsShown() or #shown == 0 then return end
    Select(sel + d)
end

-- ============================================================
-- PUBLIC
-- ============================================================
function Box.Focus()
    if not eb then return end
    eb:SetFocus()
    local text = eb:GetText() or ""
    if text:find("%S") then
        Search.EnsureIndex(OnIndexed)
        Run(text)
        Draw()
    end
end

-- /zui search <words>: the words in the box, the list under it.
function Box.Open(text)
    if not eb then return end
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    serial = serial + 1
    eb:SetText(text)
    sel = 1
    if text == "" then
        Clear()
        eb:SetFocus()
        return
    end
    Search.EnsureIndex(OnIndexed)
    Run(text)
    if api and api.BuildNav then api.BuildNav() end
    eb:SetFocus()
    Draw()
end

-- A fresh open of the window starts unfiltered.
function Box.Reset()
    serial = serial + 1
    if eb then eb:SetText("") end
    Clear()
end

Box.Hide = Hide

-- Ctrl+F while the window is up puts the cursor in the box. The window
-- listens for keys but passes every one on (SetPropagateKeyboardInput,
-- which cannot be set in combat - so armed only out of it; a window
-- opened mid-fight gets the shortcut once the fight ends).
local function ArmKeys()
    if not window or window._zSearchKeys then return end
    if InCombatLockdown() then
        if not window._zSearchKeyWait then
            window._zSearchKeyWait = CreateFrame("Frame")
            window._zSearchKeyWait:RegisterEvent("PLAYER_REGEN_ENABLED")
            window._zSearchKeyWait:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                window._zSearchKeyWait = nil
                ArmKeys()
            end)
        end
        return
    end
    window._zSearchKeys = true
    if window.SetPropagateKeyboardInput then window:SetPropagateKeyboardInput(true) end
    window:EnableKeyboard(true)
    window:SetScript("OnKeyDown", function(self, key)
        local ctrl = type(IsControlKeyDown) == "function" and IsControlKeyDown()
        local mine = (key == "F" and ctrl) and true or false
        if self.SetPropagateKeyboardInput and not InCombatLockdown() then
            self:SetPropagateKeyboardInput(not mine)
        end
        if mine then Box.Focus() end
    end)
end
Box.ArmKeys = ArmKeys

-- Config_Window hands over its nav column and window when it builds.
-- opts: JumpTo(result) opens a page at a setting; BuildNav() redraws the
-- sidebar (it reads Box.Hits for the filter). Returns the box (the host
-- frame; .editBox is the EditBox), which the window keeps as its search.
function Box.Attach(navFrame, win, opts)
    nav, window, api = navFrame, win, opts or {}
    -- (match pass: EllesmereUI's sidebar search - 28 high, 20 in from both
    -- sides, 13 under the fixed rows; the look is UI.EditBox's in the
    -- settings window)
    local S = UI.S
    host = UI.EditBox(nav, { width = S.SIDEBAR - 2 * S.SB_INSET, height = S.SB_H,
        hint = "Search settings...", onChange = OnChanged, onEnter = OnEnter })
    host:SetPoint("TOPLEFT", S.SB_INSET + 2, -(S.NAV_TOP + S.NAV_ROW + S.SB_TOP))
    eb = host.editBox
    eb:SetScript("OnEscapePressed", OnEscape)
    -- the arrows (and Tab) walk the list; Enter opens the lit row
    eb:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then Step(-1) elseif key == "DOWN" then Step(1) end
    end)
    eb:SetScript("OnTabPressed", function()
        local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown()
        Step(shift and -1 or 1)
    end)
    -- Reading the pages starts the moment the box is clicked, so by the
    -- time a word is typed most of the index is already there; a word
    -- already in the box brings its list back.
    eb:HookScript("OnEditFocusGained", function()
        Search.EnsureIndex(OnIndexed)
        local text = eb:GetText() or ""
        if text:find("%S") and not popup:IsShown() then
            Run(text)
            Draw()
        end
    end)

    -- THE LIST. A child of the window (it moves and scales with it), above
    -- the content pane and the page's own dropdowns.
    popup = CreateFrame("Frame", nil, window)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(200)
    popup:SetClampedToScreen(true)
    popup:SetSize(PopupWidth(), 40)
    UI.Fill(popup, "dropdown", "bg")
    UI.Border(popup, "ui", "border")
    -- (the dropdown menu's look in the settings window)
    popup._zPaint = function(self)
        local c = S.DD_BG
        self._zFill:SetVertexColor(c.r, c.g, c.b, S.DD_BG_HA)
        for _, t in ipairs(self._zBorder) do t:SetVertexColor(1, 1, 1, S.DD_BRD_A) end
    end
    popup:_zPaint()
    popup:Hide()
    Place()
    Box.popup = popup
    host.popup = popup

    -- A click anywhere else closes the list: a mouse-down listener that
    -- exists only while the list is up. Row clicks land on mouse-up, and
    -- the down lands over the list, so results stay clickable.
    local clickOff = CreateFrame("Frame")
    clickOff:SetScript("OnEvent", function()
        if not popup:IsMouseOver() and not host:IsMouseOver() then Hide() end
    end)
    popup:SetScript("OnShow", function() clickOff:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    popup:SetScript("OnHide", function()
        clickOff:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        for _, row in ipairs(rows) do row._zHot = nil row._zSel = nil end
    end)
    window:HookScript("OnHide", Hide)

    ArmKeys()
    return host
end

-- /zui search <words>: open the window with the words typed (the window
-- builds on first open; Config_Window's OpenConfig does that).
ns.ConfigSearchOpen = function(text)
    if ns.OpenConfig then ns.OpenConfig() end
    if eb then Box.Open(text) end
end

-- shared with later ZacUI files
ns.ConfigSearchBox = Box
