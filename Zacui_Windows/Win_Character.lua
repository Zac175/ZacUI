-- Win_Character - ZacUI's Skills, Reputation and Honor pages, rebuilt
-- inside Blizzard's character window.
-- Part of ZacUI; load order is set by the TOC.
--
-- THREE COVERS, ONE PER TAB. Each page is a Win_Kit cover parented to
-- Blizzard's own sub-page frame (SkillFrame, ReputationFrame,
-- HonorFrame), so it shows exactly when that tab is the active one:
-- Blizzard's CharacterFrame_ShowSubFrame hides the other pages and shows
-- this one, and the cover rides along. The C / U / H keys, Escape and
-- the micro button all keep working through Blizzard's code.
--
-- THE BOTTOM TABS STAY BLIZZARD'S. Character / Pet / Reputation / Skills
-- / Honor hang below the frame and are how you switch page, so each cover
-- stops above the highest tab (measured on every show out of combat - the
-- ZacUI skin flattens them to 22px, Blizzard's art is 32px) and never
-- covers them. Win_Paperdoll's cover follows the same rule.
--
-- THE X IS SECURE, SO EVERY COVER IS PROTECTED. Win_Paperdoll's secure
-- slot buttons make CharacterFrame a protected frame, and an addon's
-- HideUIPanel on it is refused in combat. So each cover's X is a secure
-- "click" on Blizzard's own CharacterFrameCloseButton (as in
-- Win_Paperdoll and Win_Spellbook). That secure child makes the cover,
-- and its page frame, protected too: every cover is built, shown, hidden
-- and re-anchored only out of combat, and anything asked for in a fight
-- (a /zui toggle, a re-anchor, a first build) runs when it ends. The
-- lists, search and detail boxes inside are plain frames and stay live
-- in combat. All three modules are combat-sensitive.
--
-- Every click calls the same API Blizzard's widget does, and the one
-- destructive action - unlearning a profession - goes through Blizzard's
-- own UNLEARN_SKILL confirmation.
--
--   Skills       search, collapsible groups, rank bars, unlearn
--   Reputation   search, Hide inactive / At war filters, standing bars,
--                At war / Inactive / Show as experience bar
--   Honor        today, yesterday, this week, last week and lifetime

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end
-- Not on every game version (Core_Flavor's feature table: Retail's character sheet is its own; a Retail version comes later):
-- this window stands down here, before it makes a frame or a module.
if ns.FeatureOn and not ns.FeatureOn("win_character") then return end

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local Hex = ns.Hex
local Kit = ns.Kit
local Modules = ns.Modules
local TEX_CHECK = ns.TEX_CHECK
local UI = ns.UI

local F = UI.F

local RH = Kit.ROW_H

-- ============================================================
-- SHARED HELPERS
-- ============================================================
local function Paint(text, key)
    return "|cff" .. Hex(GetColor("text", key)) .. text .. "|r"
end

local function Sound(on)
    if PlaySound and SOUNDKIT then
        local id = on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
        if id then PlaySound(id) end
    end
end

-- The fallback X, used only if Blizzard's close button is ever missing
-- (the real X is the secure click built in Page). CharacterFrame is
-- protected, so in combat it does nothing rather than raise a blocked-
-- action error; Escape and the C key still close it there.
local function CloseCharacter()
    if not CharacterFrame then return end
    if InCombatLockdown() and CharacterFrame.IsProtected and CharacterFrame:IsProtected() then return end
    HideUIPanel(CharacterFrame)
end

-- A flat bar: our own fill over our own box, plus a paler second bar
-- behind it for a temporary bonus (a skill buff). No StatusBar art.
local function FlatBar(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height)
    UI.Fill(f, "ui", "elementBg")
    UI.Border(f, "ui", "border")
    f._zPaint = UI.PaintBox
    f:_zPaint()
    local function Make(up)
        local b = CreateFrame("StatusBar", nil, f)
        b:SetPoint("TOPLEFT", 1, -1)
        b:SetPoint("BOTTOMRIGHT", -1, 1)
        b:SetStatusBarTexture(FLAT)
        local t = b:GetStatusBarTexture()
        if t then t._zui_own = true end
        b:SetMinMaxValues(0, 1)
        b:SetValue(0)
        b:SetFrameLevel(f:GetFrameLevel() + up)
        return b
    end
    f.bonus = Make(1)
    f.bar = Make(2)
    function f:Set(value, max, bonusValue, r, g, b)
        if not max or max <= 0 then max = 1 end
        self.bar:SetMinMaxValues(0, max)
        self.bar:SetValue(math.max(0, math.min(value or 0, max)))
        self.bonus:SetMinMaxValues(0, max)
        self.bonus:SetValue(math.max(0, math.min(bonusValue or 0, max)))
        self.bar:SetStatusBarColor(r, g, b, 1)
        self.bonus:SetStatusBarColor(r, g, b, 0.35)
    end
    return f
end

-- Filter a header/child list. A header survives when something under it
-- is kept, or it matches the search itself (then its whole group shows),
-- or it is collapsed - what a collapsed header hides is not enumerated,
-- so it cannot be ruled out. dropHeader removes a group outright.
local function Grouped(all, filtering, keep, headerAll, dropHeader)
    local out, pending, showAll, dropping = {}, nil, false, false
    for _, e in ipairs(all) do
        if e.header then
            dropping = dropHeader and dropHeader(e) or false
            pending, showAll = nil, false
            if not dropping then
                showAll = headerAll and headerAll(e) or false
                if not filtering or not e.expanded or showAll then
                    out[#out + 1] = e
                else
                    pending = e
                end
            end
        elseif not dropping and keep(e, showAll) then
            if pending then
                out[#out + 1] = pending
                pending = nil
            end
            out[#out + 1] = e
        end
    end
    return out
end

-- Header rows share one look on every page: a +/- and the group name.
local function BuildHeaderBits(row)
    row.toggle = UI.Font(row, F.LABEL, { cat = "text", key = "gray", justify = "CENTER" })
    row.toggle:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.toggle:SetWidth(14)
    row.head = UI.Font(row, F.LABEL, { cat = "text", key = "gold", justify = "LEFT" })
    row.head:SetPoint("LEFT", row.toggle, "RIGHT", 6, 0)
    row.head:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.head:SetWordWrap(false)
end

local function ShowParts(parts, on)
    for _, p in ipairs(parts) do p:SetShown(on) end
end

-- ============================================================
-- PAGE PLUMBING (cover, placement, silencing, enable toggle)
-- ============================================================
-- Blizzard pieces outside every cover: the close button pokes past the
-- top-right corner, the portrait past the top-left, and the page's own
-- frame art rings the cover when the character skin is off. The shared
-- CharacterFrame pieces are the SAME list Win_Paperdoll silences, so a
-- tab switch hands them from one cover to the next without a flash.
-- Appended one by one - a literal with a nil hole would stop ipairs.
local function Leftovers(page)
    local t = {}
    local function Add(f) if f then t[#t + 1] = f end end
    -- (on the modern client the window's own chrome - close button,
    -- portrait, frame art, title bar - is Kit.CharacterCover's, quietened
    -- in a side table with the other parts, never with fields on them)
    if not _G.ZACUI_MODERN then
        Add(_G.CharacterFrameCloseButton)
        Add(_G.CharacterFramePortrait)
        if CharacterFrame then
            Add(CharacterFrame.PortraitContainer)
            Add(CharacterFrame.NineSlice)
            -- Forever's (modern) CharacterFrame has a title bar at frame level
            -- 510 that draws over the cover ("Zac Warrior" twice); Classic's has none
            Add(CharacterFrame.TitleContainer)
        end
    end
    local host = page.host()
    if host then
        for _, r in ipairs({ host:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") and not r._zui_own then Add(r) end
        end
    end
    if page.extra then for _, f in ipairs(page.extra()) do Add(f) end end
    -- (Forever's modern page parts - the reputation list and scroll bar
    -- in the HIGH strata, the pane divider and toggle - are
    -- Kit.CharacterCover's: quietened by name, never hidden)
    return t
end

-- Kit.Silence is written for frames: it also turns their mouse off, and
-- Unsilence turns it back ON - which on a plain texture (the portrait,
-- the page art) would make it start catching the mouse. Textures only
-- fade; frames go through the kit. Same field as the kit, so either path
-- can undo the other.
-- Kit.Silence fades textures and frames alike (a texture has no mouse
-- to take away), remembering each piece's own alpha and mouse state.
local Quiet, Unquiet = Kit.Silence, Kit.Unsilence


-- CharacterFrame's visible rectangle (the skin's inset), stopped above
-- the bottom tab row so every tab stays visible and clickable. The cover
-- is protected (its secure X), so this only ever runs out of combat.
local function PlaceOverCharacter(win)
    local host = CharacterFrame
    local ins = ns.GetPanelInset("CharacterFrame", host)
    local bottom = ins.b or 0
    -- With ZacUI's tab strip on, Blizzard's tabs are faded out and the
    -- strip hangs below the panel line, so the page runs down to it.
    local tabsOn = ns.CharTabs and ns.CharTabs.Enabled and ns.CharTabs.Enabled()
    local base = (not tabsOn) and host:GetBottom()
    -- (Forever can keep a window's edges secret: then the inset as it is)
    if ns.IsSecret and ns.IsSecret(base) then base = nil end
    if base then
        for i = 1, 5 do
            local tab = _G["CharacterFrameTab" .. i]
            local top = tab and tab:IsShown() and tab:GetTop()
            if ns.IsSecret and ns.IsSecret(top) then top = nil end
            if top then bottom = math.max(bottom, math.ceil(top - base) + 1) end
        end
    end
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", host, "TOPLEFT", ins.l or 0, -(ins.t or 0))
    win:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(ins.r or 0), bottom)
end

-- page = { key, host(), name, title, icon, build(page), draw(page, keep),
--          events = {...}, extra() }
local function Page(page)
    local function Enabled()
        return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules[page.key] ~= false
    end

    function page.Refresh(keepOffset)
        -- IsVisible, not IsShown: the cover is a shown child of a page
        -- that is hidden whenever another tab is up.
        local win = page.win
        if not win or not win:IsVisible() then return end
        page.draw(page, keepOffset)
    end

    page.Queue = Kit.Coalesce(function() page.Refresh(true) end,
        function() return page.win end)

    -- A protected cover cannot be moved in a fight: remember, redo later.
    local function Reanchor(win)
        if InCombatLockdown() then
            page.pending = true
            return
        end
        win.Reanchor()
    end

    -- Out of combat only (Apply checks): it creates a secure button.
    local function Build()
        if page.win then return page.win end
        local win = Kit.Cover(page.host(), {
            name = page.name,
            title = page.title,
            insetName = "CharacterFrame",
            onClose = CloseCharacter,
        })
        win:SetIcon(page.icon)
        win.Reanchor = function() PlaceOverCharacter(win) end
        win.Reanchor()
        page.win = win
        page.build(page)

        -- THE X, SECURELY. A secure "click" on Blizzard's own close button
        -- runs their handler with their credentials, so the X works in
        -- combat even though CharacterFrame is protected.
        local blizzClose = _G.CharacterFrameCloseButton
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
            if ns.ZUI and ns.ZUI.skinned then ns.ZUI.skinned[sx] = true end
        end

        local ev = CreateFrame("Frame", nil, win)
        for _, e in ipairs(page.events or {}) do pcall(ev.RegisterEvent, ev, e) end
        ev:SetScript("OnEvent", function()
            if win:IsVisible() then page.Queue() end
        end)

        -- Forever's modern page parts (the list above the cover, the pane
        -- chrome): hushed by name with the cover, again on a page rebuild
        Kit.CharacterCover(win, page.modern or page.key)

        -- Silenced only while this page is up: the Character tab still
        -- needs Blizzard's close button when no cover is over it. Fading
        -- is allowed in combat; the kit never touches a protected frame's
        -- mouse.
        win:HookScript("OnShow", function()
            Reanchor(win)
            -- Again next frame: the skin flattens the tabs in a timer of
            -- its own, and the cover should stop right above the new row.
            C_Timer.After(0, function() if win:IsVisible() then Reanchor(win) end end)
            Quiet(Leftovers(page))
            if page.onShow then page.onShow(page) end
            page.Queue()
        end)
        win:HookScript("OnHide", function()
            Unquiet(Leftovers(page))
        end)
        return win
    end

    function page.Apply()
        local host = page.host()
        if not host or not CharacterFrame then return end
        -- Build / Show / Hide / re-anchor a protected cover: out of
        -- combat only. A request in a fight lands when it ends.
        if InCombatLockdown() then
            page.pending = true
            return
        end
        page.pending = nil
        if Enabled() then
            Build()
            page.win:Show()
            if page.win:IsVisible() then
                page.win.Reanchor()
                Quiet(Leftovers(page))
                page.Queue()
            end
        elseif page.win then
            page.win:Hide()
            Unquiet(Leftovers(page))
        end
    end

    function page.Module()
        local host = page.host()
        if not host or not CharacterFrame or ns[page.flag] then return end
        ns[page.flag] = true
        -- Built at login rather than on first open, so a first open in
        -- combat still finds the page; a login in combat builds on the
        -- way out, like anything else a fight held back.
        local regen = CreateFrame("Frame")
        regen:RegisterEvent("PLAYER_REGEN_ENABLED")
        regen:SetScript("OnEvent", function()
            if page.pending then page.Apply() end
        end)
        page.Apply()
        -- The flag is read on every open, so a /zui toggle needs no reload.
        host:HookScript("OnShow", function()
            page.Apply()
        end)
    end
    return page
end

-- ============================================================
-- SKILLS
-- ============================================================
local skills = { query = "" }

local function SkillEntries()
    local all = {}
    local n = GetNumSkillLines and GetNumSkillLines() or 0
    for i = 1, n do
        local name, header, expanded, rank, temp, modifier, maxRank, abandonable,
            stepCost, _, minLevel, _, desc = GetSkillLineInfo(i)
        if name and name ~= "" then
            if header then
                all[#all + 1] = { header = true, index = i, name = name, expanded = expanded and true or false }
            else
                all[#all + 1] = {
                    index = i, name = name, rank = rank or 0, temp = temp or 0,
                    mod = modifier or 0, max = maxRank or 0,
                    abandonable = abandonable and true or false,
                    learnable = stepCost and true or false, minLevel = minLevel or 0,
                    desc = desc or "",
                }
            end
        end
    end
    return all
end

-- Blizzard's rank text: rank (with any temporary points) over the cap,
-- the equipment/buff modifier in green or red.
local function SkillRankText(e)
    if e.learnable or e.max <= 1 then return "" end
    local total = e.rank + e.temp
    if e.mod ~= 0 then
        local m = (e.mod > 0) and Paint("+" .. e.mod, "green") or Paint(tostring(e.mod), "red")
        return total .. " (" .. m .. ")/" .. e.max
    end
    return total .. "/" .. e.max
end

local function SetSkillBar(bar, e)
    if e.learnable then
        local r, g, b = Kit.TextRGB("gray")
        bar:Set(0, 1, 0, r, g, b)
    elseif e.max <= 1 then
        -- A proficiency (weapon, armour, language at 1/1): Blizzard shows
        -- it as a full grey bar with no numbers.
        local r, g, b = Kit.TextRGB("gray")
        bar:Set(1, 1, 1, r, g, b)
    else
        local r, g, b = Kit.TextRGB("blue")
        bar:Set(e.rank, e.max, e.rank + e.temp, r, g, b)
    end
end

local function SkillName(e)
    if e.learnable and LEARN_SKILL_TEMPLATE then return format(LEARN_SKILL_TEMPLATE, e.name) end
    return e.name
end

local function ToggleSkillHeader(e)
    if e.expanded then
        CollapseSkillHeader(e.index)
        -- Blizzard's header click: a pending unlearn prompt for a skill
        -- that is no longer the selected one is withdrawn.
        local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible("UNLEARN_SKILL")
        if dialog and dialog.data ~= GetSelectedSkill() then StaticPopup_Hide("UNLEARN_SKILL") end
    else
        ExpandSkillHeader(e.index)
    end
end

local function SkillBuildRow(row)
    row:RegisterForClicks("LeftButtonUp")
    BuildHeaderBits(row)
    row.rankText = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.rankText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)
    row.rankText:SetWordWrap(false)
    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -4)
    row.nameText:SetPoint("TOPRIGHT", row.rankText, "TOPLEFT", -6, 0)
    row.nameText:SetWordWrap(false)
    row.bar = FlatBar(row, 8)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 5)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 5)
    row.leafParts = { row.rankText, row.nameText, row.bar }
    row.headParts = { row.toggle, row.head }

    row:SetScript("OnClick", function(self)
        local e = self.item
        if not e then return end
        if e.header then
            ToggleSkillHeader(e)
        else
            SetSelectedSkill(e.index)
            skills.Queue()
        end
    end)
end

local function SkillUpdateRow(row, e)
    ShowParts(row.headParts, e.header)
    ShowParts(row.leafParts, not e.header)
    if e.header then
        row.toggle:SetText(e.expanded and "-" or "+")
        row.head:SetText(e.name)
        return
    end
    row.nameText:SetText(SkillName(e))
    if e.learnable and e.minLevel > (UnitLevel("player") or 0) then
        row.nameText:SetTextColor(Kit.TextRGB("gray"))
    else
        row.nameText:_zPaint()
    end
    row.rankText:SetText(SkillRankText(e))
    SetSkillBar(row.bar, e)
end

local function SkillDetail(p, e)
    local d = p.detail
    if not e then
        d.empty:Show()
        ShowParts(d.parts, false)
        d.unlearn:Hide()
        d.item = nil
        return
    end
    d.item = e
    d.empty:Hide()
    ShowParts(d.parts, true)
    d.name:SetText(SkillName(e))
    d.rank:SetText(SkillRankText(e))
    SetSkillBar(d.bar, e)
    d.desc:SetText(e.desc or "")
    d.unlearn:SetShown(e.abandonable)
end

local function SkillDraw(p, keepOffset)
    local all = SkillEntries()
    local q = p.query
    local data = Grouped(all, q ~= "",
        function(e, showAll) return showAll or Kit.Matches(q, e.name) end,
        function(e) return q ~= "" and Kit.Matches(q, e.name) end)
    local sel = GetSelectedSkill and GetSelectedSkill() or 0
    local selEntry
    for _, e in ipairs(all) do
        if e.index == sel and not e.header then selEntry = e break end
    end
    p.list.selected = nil
    for _, e in ipairs(data) do
        if selEntry and e.index == selEntry.index then p.list.selected = e break end
    end
    p.list:SetEmptyText(#all == 0 and "No skills yet." or "Nothing matches.")
    p.list:SetData(data, keepOffset)

    local headers, collapsed = 0, 0
    for _, e in ipairs(all) do
        if e.header then
            headers = headers + 1
            if not e.expanded then collapsed = collapsed + 1 end
        end
    end
    -- Blizzard's "All" button (SkillFrame_UpdateSkills): it collapses
    -- only when every group is open, and expands if any one is shut.
    local collapse = headers > 0 and collapsed == 0
    p.allButton._zCollapse = collapse
    p.allButton:SetLabel(collapse and "Collapse all" or "Expand all")
    p.allButton:SetDisabled(headers == 0)
    SkillDetail(p, selEntry)
end

local function SkillBuild(p)
    local win = p.win
    local y = win.top
    p.allButton = UI.Button(win, "Collapse all", { width = 78, height = Kit.SEARCH_H, size = F.SMALL })
    p.allButton:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y)
    p.allButton:SetScript("OnClick", function(self)
        -- Index 0 is every header, as Blizzard's own button sends it.
        if self._zCollapse then CollapseSkillHeader(0) else ExpandSkillHeader(0) end
    end)
    p.search = Kit.Search(win, 100, function(text)
        p.query = Kit.NormalizeQuery(text)
        p.Refresh()
    end, "Search skills")
    p.search:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
    p.search:SetPoint("TOPRIGHT", p.allButton, "TOPLEFT", -Kit.GAP, 0)

    -- Detail box along the bottom.
    local d = UI.Box(win, "ui", "cardBg")
    d:SetHeight(96)
    d:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", Kit.PAD, Kit.PAD)
    d:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -Kit.PAD, Kit.PAD)
    p.detail = d
    d.empty = UI.Font(d, F.LABEL, { cat = "text", key = "gray", justify = "CENTER",
        text = "Select a skill to see its details." })
    d.empty:SetPoint("CENTER")

    d.unlearn = UI.Button(d, UNLEARN or "Unlearn", { width = 70, height = 20, size = F.SMALL })
    d.unlearn:SetPoint("TOPRIGHT", d, "TOPRIGHT", -6, -5)
    d.unlearn:SetScript("OnClick", function()
        local e = d.item
        -- Blizzard's own prompt; its Accept calls AbandonSkill(index).
        if e and e.abandonable then StaticPopup_Show("UNLEARN_SKILL", e.name, nil, e.index) end
    end)
    if UNLEARN_SKILL_TOOLTIP then UI.Tooltip(d.unlearn, UNLEARN or "Unlearn", UNLEARN_SKILL_TOOLTIP) end
    d.unlearn:Hide()

    d.name = UI.Font(d, F.LABEL, { justify = "LEFT" })
    d.name:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -8)
    d.name:SetPoint("TOPRIGHT", d.unlearn, "TOPLEFT", -6, -3)
    d.name:SetWordWrap(false)
    d.rank = UI.Font(d, F.SMALL, { justify = "RIGHT" })
    d.rank:SetPoint("TOPRIGHT", d, "TOPRIGHT", -8, -31)
    d.rank:SetWordWrap(false)
    d.bar = FlatBar(d, 10)
    d.bar:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -31)
    d.bar:SetPoint("TOPRIGHT", d.rank, "TOPLEFT", -6, 0)
    d.desc = UI.Font(d, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    d.desc:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -48)
    d.desc:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -8, 6)
    d.desc:SetJustifyV("TOP")
    d.desc:SetWordWrap(true)
    d.parts = { d.name, d.rank, d.bar, d.desc }
    ShowParts(d.parts, false)

    p.list = Kit.List(win, { rowHeight = RH, build = SkillBuildRow, update = SkillUpdateRow })
    p.list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y - Kit.SEARCH_H - Kit.GAP)
    p.list:SetPoint("BOTTOMRIGHT", d, "TOPRIGHT", 0, Kit.GAP)
end

Page(skills)
skills.key = "skillswin"
skills.flag = "_zSkillsWin"
skills.name = "ZacUISkillsWindow"
skills.title = SKILLS or "Skills"
skills.icon = "Interface\\Icons\\INV_Misc_Gear_01"
skills.host = function() return SkillFrame end
skills.events = { "SKILL_LINES_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP" }
skills.build = SkillBuild
skills.draw = SkillDraw
skills.onShow = function(p)
    p.query = ""
    p.search:SetText("")
end

-- ============================================================
-- REPUTATION
-- ============================================================
local rep = { query = "" }

local function StandingText(id)
    if not id then return "" end
    local s
    if GetText then s = GetText("FACTION_STANDING_LABEL" .. id, UnitSex("player")) end
    return s or _G["FACTION_STANDING_LABEL" .. id] or ""
end

-- Standing colours are Blizzard's data: FACTION_BAR_COLORS by standing.
local function StandingRGB(id)
    local c = FACTION_BAR_COLORS and id and FACTION_BAR_COLORS[id]
    if c and c.r then return c.r, c.g, c.b end
    return Kit.TextRGB("gray")
end

-- THE FACTION CALLS (2026-11-07). Classic Era and TBC have the old
-- globals; WoW Forever has only C_Reputation (the list came up "No
-- reputations yet." there). Each call is the global when the client has
-- it, else the C_Reputation one with the old shape.
local CR = C_Reputation
local Rep = {}
function Rep.Num()
    if GetNumFactions then return GetNumFactions() end
    return CR and CR.GetNumFactions and CR.GetNumFactions() or 0
end
function Rep.Info(i)
    if GetFactionInfo then return GetFactionInfo(i) end
    local d = CR and CR.GetFactionDataByIndex and CR.GetFactionDataByIndex(i)
    if type(d) ~= "table" then return nil end
    return d.name, d.description, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold,
        d.currentStanding, d.atWarWith, d.canToggleAtWar, d.isHeader, d.isCollapsed, d.isHeaderWithRep,
        d.isWatched, d.isChild, d.factionID
end
function Rep.Inactive(i)
    if IsFactionInactive then return IsFactionInactive(i) end
    if CR and CR.IsFactionActive then return not CR.IsFactionActive(i) end
    return false
end
function Rep.Toggle(i, expanded)
    if expanded then
        if CollapseFactionHeader then CollapseFactionHeader(i) elseif CR then CR.CollapseFactionHeader(i) end
    else
        if ExpandFactionHeader then ExpandFactionHeader(i) elseif CR then CR.ExpandFactionHeader(i) end
    end
end
function Rep.Select(i)
    if SetSelectedFaction then SetSelectedFaction(i) elseif CR and CR.SetSelectedFaction then CR.SetSelectedFaction(i) end
end
function Rep.Selected()
    if GetSelectedFaction then return GetSelectedFaction() end
    return CR and CR.GetSelectedFaction and CR.GetSelectedFaction() or 0
end
function Rep.AtWar(i)
    if FactionToggleAtWar then FactionToggleAtWar(i) elseif CR and CR.ToggleFactionAtWar then CR.ToggleFactionAtWar(i) end
end
function Rep.SetInactive(i, on)
    if SetFactionInactive then
        if on then SetFactionInactive(i) else SetFactionActive(i) end
    elseif CR and CR.SetFactionActive then
        CR.SetFactionActive(i, not on)
    end
end
function Rep.Watch(i)
    if SetWatchedFactionIndex then SetWatchedFactionIndex(i)
    elseif CR and CR.SetWatchedFactionByIndex then CR.SetWatchedFactionByIndex(i) end
end

local function RepEntries()
    local all = {}
    local n = Rep.Num()
    for i = 1, n do
        local name, description, standingID, barMin, barMax, barValue, atWarWith,
            canToggleAtWar, isHeader, isCollapsed, _, isWatched, isChild = Rep.Info(i)
        if name then
            if isHeader then
                all[#all + 1] = { header = true, index = i, name = name, expanded = not isCollapsed }
            else
                -- Blizzard normalises the bar to the current standing.
                local lo = barMin or 0
                all[#all + 1] = {
                    index = i, name = name, desc = description or "",
                    standing = standingID, value = (barValue or 0) - lo, max = (barMax or 0) - lo,
                    atWar = atWarWith and true or false, canWar = canToggleAtWar and true or false,
                    watched = isWatched and true or false, child = isChild and true or false,
                    inactive = Rep.Inactive(i) and true or false,
                }
            end
        end
    end
    return all
end

local function RepTooltip(row)
    local e = row.item
    if not e or e.header then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local t = GetColor("tooltip", "title")
    GameTooltip:AddLine(e.name, t.r, t.g, t.b)
    local r, g, b = StandingRGB(e.standing)
    local c = GetColor("tooltip", "body")
    GameTooltip:AddDoubleLine(StandingText(e.standing), e.value .. " / " .. e.max, r, g, b, c.r, c.g, c.b)
    if e.desc ~= "" then
        GameTooltip:AddLine(e.desc, c.r, c.g, c.b, true)
    end
    if e.atWar and REPUTATION_STATUS_AT_WAR then
        GameTooltip:AddLine(REPUTATION_STATUS_AT_WAR, Kit.TextRGB("red"))
    end
    GameTooltip:Show()
end

local function RepBuildRow(row)
    row:RegisterForClicks("LeftButtonUp")
    BuildHeaderBits(row)
    -- The watched check sits in its own column so names line up.
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check._zui_own = true
    row.check:SetTexture(TEX_CHECK)
    row.check:SetSize(10, 10)
    row.standing = UI.Font(row, F.SMALL, { justify = "RIGHT" })
    row.standing:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)
    row.standing:SetWordWrap(false)
    row.nameText = UI.Font(row, F.LABEL, { justify = "LEFT" })
    row.nameText:SetPoint("TOPRIGHT", row.standing, "TOPLEFT", -6, 0)
    row.nameText:SetWordWrap(false)
    row.value = UI.Font(row, F.SMALL, { justify = "RIGHT", cat = "text", key = "gray" })
    row.value:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 3)
    row.value:SetWidth(70)
    row.value:SetWordWrap(false)
    row.bar = FlatBar(row, 8)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -80, 5)
    row.leafParts = { row.standing, row.nameText, row.value, row.bar }
    row.headParts = { row.toggle, row.head }

    row:SetScript("OnEnter", RepTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.UpdateTooltip = RepTooltip
    row:SetScript("OnClick", function(self)
        local e = self.item
        if not e then return end
        if e.header then
            Rep.Toggle(e.index, e.expanded)
        else
            Rep.Select(e.index)
            rep.Queue()
        end
    end)
end

local function RepUpdateRow(row, e)
    ShowParts(row.headParts, e.header)
    ShowParts(row.leafParts, not e.header)
    if e.header then
        row.check:Hide()
        row.toggle:SetText(e.expanded and "-" or "+")
        row.head:SetText(e.name)
        return
    end
    local x = 6 + (e.child and 10 or 0)
    row.check:ClearAllPoints()
    row.check:SetPoint("TOPLEFT", row, "TOPLEFT", x, -5)
    row.check:SetShown(e.watched)
    if UI.PaintTick then
        UI.PaintTick(row.check)
    else
        local c = GetColor("checkbox", "check")
        row.check:SetVertexColor(c.r, c.g, c.b, 1)
    end
    row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", x + 14, -4)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x + 14, 5)

    row.nameText:SetText(e.name)
    row.nameText:_zPaint()
    local st = StandingText(e.standing)
    if e.atWar then st = Paint(AT_WAR or "At war", "red") .. "  " .. st end
    row.standing:SetText(st)
    row.standing:SetTextColor(StandingRGB(e.standing))
    row.value:SetText(e.value .. " / " .. e.max)
    local r, g, b = StandingRGB(e.standing)
    row.bar:Set(e.value, e.max, 0, r, g, b)
end

local function RepDetail(p, e)
    local d = p.detail
    if not e then
        d.item = nil
        d.empty:Show()
        ShowParts(d.parts, false)
        return
    end
    d.item = e
    d.empty:Hide()
    ShowParts(d.parts, true)
    d.name:SetText(e.name)
    d.standing:SetText(StandingText(e.standing) .. "  " .. Paint(e.value .. " / " .. e.max, "gray"))
    d.standing:SetTextColor(StandingRGB(e.standing))
    d.desc:SetText(e.desc)

    -- Blizzard greys "At war" out for factions you cannot declare on.
    d.war:SetChecked(e.atWar)
    if e.canWar then
        d.war:Enable()
        d.war._zText._zPaintKey = "red"
    else
        d.war:Disable()
        d.war._zText._zPaintKey = "disabled"
    end
    d.war._zText:_zPaint()
    d.inactive:SetChecked(e.inactive)
    d.watch:SetChecked(e.watched)
end

local function RepDraw(p, keepOffset)
    local all = RepEntries()
    local q = p.query
    local hideInactive = p.chipInactive:IsOn()
    local warOnly = p.chipWar:IsOn()
    local inactiveName = FACTION_INACTIVE
    local data = Grouped(all, q ~= "" or hideInactive or warOnly,
        function(e, showAll)
            if hideInactive and e.inactive then return false end
            if warOnly and not e.atWar then return false end
            return showAll or Kit.Matches(q, e.name)
        end,
        function(e) return q ~= "" and Kit.Matches(q, e.name) end,
        function(e) return hideInactive and inactiveName ~= nil and e.name == inactiveName end)

    local sel = Rep.Selected() or 0
    local selEntry
    for _, e in ipairs(all) do
        if e.index == sel and not e.header then selEntry = e break end
    end
    p.list.selected = nil
    for _, e in ipairs(data) do
        if selEntry and e.index == selEntry.index then p.list.selected = e break end
    end
    p.list:SetEmptyText(#all == 0 and "No reputations yet." or "Nothing matches.")
    p.list:SetData(data, keepOffset)
    RepDetail(p, selEntry)
end

local function RepBuild(p)
    local win = p.win
    local y = win.top
    p.chipWar = Kit.Chip(win, AT_WAR or "At war", false, function() p.Refresh() end,
        "Only factions you are at war with.")
    p.chipWar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y)
    p.chipInactive = Kit.Chip(win, "Hide inactive", false, function() p.Refresh() end,
        "Hide the factions you moved to Inactive.")
    p.chipInactive:SetPoint("TOPRIGHT", p.chipWar, "TOPLEFT", -4, 0)
    p.search = Kit.Search(win, 100, function(text)
        p.query = Kit.NormalizeQuery(text)
        p.Refresh()
    end, "Search factions")
    p.search:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
    p.search:SetPoint("TOPRIGHT", p.chipInactive, "TOPLEFT", -Kit.GAP, 0)

    local d = UI.Box(win, "ui", "cardBg")
    d:SetHeight(118)
    d:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", Kit.PAD, Kit.PAD)
    d:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -Kit.PAD, Kit.PAD)
    p.detail = d
    d.empty = UI.Font(d, F.LABEL, { cat = "text", key = "gray", justify = "CENTER",
        text = "Select a faction to see its details." })
    d.empty:SetPoint("CENTER")

    d.standing = UI.Font(d, F.SMALL, { justify = "RIGHT" })
    d.standing:SetPoint("TOPRIGHT", d, "TOPRIGHT", -8, -8)
    d.standing:SetWordWrap(false)
    d.name = UI.Font(d, F.LABEL, { justify = "LEFT" })
    d.name:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -8)
    d.name:SetPoint("TOPRIGHT", d.standing, "TOPLEFT", -6, 0)
    d.name:SetWordWrap(false)
    d.desc = UI.Font(d, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    d.desc:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -24)
    d.desc:SetPoint("TOPRIGHT", d, "TOPRIGHT", -8, -24)
    d.desc:SetHeight(44)
    d.desc:SetJustifyV("TOP")
    d.desc:SetWordWrap(true)

    -- Blizzard's ReputationDetailFrame checkboxes, same calls.
    local function Index() return d.item and d.item.index end
    d.war = UI.Checkbox(d, AT_WAR or "At war", false, function(on)
        local i = Index()
        if i then Rep.AtWar(i) end
        Sound(on)
        rep.Queue()
    end, { size = F.SMALL, tooltip = REPUTATION_AT_WAR_DESCRIPTION })
    d.war:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 8, 28)
    d.inactive = UI.Checkbox(d, MOVE_TO_INACTIVE or "Inactive", false, function(on)
        local i = Index()
        if i then Rep.SetInactive(i, on) end
        Sound(on)
        rep.Queue()
    end, { size = F.SMALL, tooltip = REPUTATION_MOVE_TO_INACTIVE })
    d.inactive:SetPoint("LEFT", d.war, "RIGHT", 18, 0)
    d.watch = UI.Checkbox(d, SHOW_FACTION_ON_MAINSCREEN or "Show as experience bar", false, function(on)
        local i = Index()
        if i then Rep.Watch(on and i or 0) end
        Sound(on)
        rep.Queue()
    end, { size = F.SMALL, tooltip = REPUTATION_SHOW_AS_XP })
    d.watch:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 8, 9)
    d.parts = { d.name, d.standing, d.desc, d.war, d.inactive, d.watch }
    ShowParts(d.parts, false)

    p.list = Kit.List(win, { rowHeight = RH, build = RepBuildRow, update = RepUpdateRow })
    p.list:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y - Kit.SEARCH_H - Kit.GAP)
    p.list:SetPoint("BOTTOMRIGHT", d, "TOPRIGHT", 0, Kit.GAP)
end

Page(rep)
rep.key = "reputationwin"
rep.modern = "reputation"   -- its Forever parts (Kit.CharacterParts)
rep.flag = "_zReputationWin"
rep.name = "ZacUIReputationWindow"
rep.title = REPUTATION or "Reputation"
rep.icon = "Interface\\Icons\\INV_Misc_Note_01"
rep.host = function() return ReputationFrame end
rep.events = { "UPDATE_FACTION", "QUEST_LOG_UPDATE" }
rep.build = RepBuild
rep.draw = RepDraw
rep.onShow = function(p)
    p.query = ""
    p.search:SetText("")
    -- Blizzard's own detail pop-out (left open from a session with this
    -- page off) hangs off the right edge. Fading it is not enough - its
    -- checkboxes would still take clicks - so it is closed. It is not an
    -- ancestor of anything secure, so this is allowed in combat too.
    local bd = _G.ReputationDetailFrame
    if bd and bd:IsShown() then bd:Hide() end
end
-- Blizzard's detail panel hangs off the page's right edge.
rep.extra = function()
    local t = {}
    if _G.ReputationDetailFrame then t[1] = _G.ReputationDetailFrame end
    return t
end

-- ============================================================
-- HONOR
-- ============================================================
local honor = {}

local DASH = "-"

local HONOR_ROWS = {
    { key = "today",     label = function() return HONOR_THIS_SESSION or "Today" end },
    { key = "yesterday", label = function() return HONOR_YESTERDAY or "Yesterday" end },
    { key = "thisweek",  label = function() return HONOR_THISWEEK or "This week" end },
    { key = "lastweek",  label = function() return HONOR_LASTWEEK or "Last week" end },
    { key = "lifetime",  label = function() return HONOR_LIFETIME or "Lifetime" end },
}

local function Num(v) return v and tostring(v) or DASH end
-- (WoW Forever has none of the Classic honor calls: each reads as nothing)
local function Ask(fn, ...) if fn then return fn(...) end end

-- The same calls and return orders HonorFrame_Update uses.
local function HonorValues()
    local v = {}
    local hk, dk, honorPts, standing
    hk, dk = Ask(GetPVPSessionStats)
    v.today = { Num(hk), Num(dk), DASH }
    hk, dk, honorPts = Ask(GetPVPYesterdayStats)
    v.yesterday = { Num(hk), Num(dk), Num(honorPts) }
    hk, honorPts = Ask(GetPVPThisWeekStats)
    v.thisweek = { Num(hk), DASH, Num(honorPts) }
    hk, dk, honorPts, standing = Ask(GetPVPLastWeekStats)
    v.lastweek = { Num(hk), Num(dk), Num(honorPts) }
    v.standing = standing
    local highest
    hk, dk, highest = Ask(GetPVPLifetimeStats)
    v.lifetime = { Num(hk), Num(dk), DASH }
    v.highest = highest
    return v
end

local function HonorDraw(p)
    local rankName, rankNumber = Ask(GetPVPRankInfo, Ask(UnitPVPRank, "player"))
    rankNumber = rankNumber or 0
    p.rankName:SetText(rankName or (NONE or "None"))
    p.rankNum:SetText("(" .. (RANK or "Rank") .. " " .. rankNumber .. ")")
    if rankNumber > 0 then
        p.rankIcon:SetTexture(format("%s%02d", "Interface\\PvPRankBadges\\PvPRank", rankNumber))
        p.rankIcon:Show()
    else
        p.rankIcon:Hide()
    end

    -- Faction colour for the progress bar: Blizzard's own table.
    local faction = UnitFactionGroup("player")
    local fc = PLAYER_FACTION_COLORS and PLAYER_FACTION_COLORS[(faction == "Alliance") and 1 or 0]
    local r, g, b
    if fc and fc.r then r, g, b = fc.r, fc.g, fc.b
    else r, g, b = Kit.TextRGB((faction == "Alliance") and "blue" or "red") end
    local prog = GetPVPRankProgress and GetPVPRankProgress() or 0
    p.bar:Set(prog, 1, 0, r, g, b)
    p.pct:SetText(math.floor(prog * 100 + 0.5) .. "%")

    if PLAYER_LEVEL then
        p.level:SetFormattedText(PLAYER_LEVEL, UnitLevel("player"), UnitRace("player"), UnitClass("player"))
    else
        p.level:SetText((LEVEL or "Level") .. " " .. (UnitLevel("player") or ""))
    end
    local guildName, guildTitle = GetGuildInfo("player")
    if guildName and GUILD_TITLE_TEMPLATE then
        p.guild:SetFormattedText(GUILD_TITLE_TEMPLATE, guildTitle or "", guildName)
    else
        p.guild:SetText(guildName or "")
    end

    local v = HonorValues()
    for i, spec in ipairs(HONOR_ROWS) do
        local cells = p.cells[i]
        local vals = v[spec.key]
        for c = 1, 3 do cells[c + 1]:SetText(vals[c]) end
    end
    p.standing:SetText(Paint((HONOR_STANDING or "Standing") .. ": ", "gray")
        .. ((v.standing and v.standing > 0) and tostring(v.standing) or DASH))
    local hiName = v.highest and Ask(GetPVPRankInfo, v.highest)
    p.highest:SetText(Paint((HONOR_HIGHEST_RANK or "Highest rank") .. ": ", "gray")
        .. (hiName or (NONE or "None")))
end

local function HonorBuild(p)
    local win = p.win
    local y = win.top

    local icon = win:CreateTexture(nil, "ARTWORK")
    icon._zui_own = true
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y)
    p.rankIcon = icon
    p.rankName = UI.Font(win, F.CARD, { justify = "LEFT" })
    p.rankName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    p.rankName:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y - 2)
    p.rankName:SetWordWrap(false)
    p.rankNum = UI.Font(win, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    p.rankNum:SetPoint("TOPLEFT", p.rankName, "BOTTOMLEFT", 0, -4)
    p.rankNum:SetPoint("TOPRIGHT", p.rankName, "BOTTOMRIGHT", 0, -4)
    p.rankNum:SetWordWrap(false)
    -- Blizzard's rank tooltip, over the icon and the rank text.
    local rankHit = CreateFrame("Frame", nil, win)
    rankHit:SetPoint("TOPLEFT", icon, "TOPLEFT")
    rankHit:SetPoint("BOTTOMRIGHT", p.rankNum, "BOTTOMRIGHT")
    rankHit:EnableMouse(true)
    rankHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local t = GetColor("tooltip", "title")
        GameTooltip:AddLine(RANK or "Rank", t.r, t.g, t.b)
        if NEWBIE_TOOLTIP_RANK then
            local c = GetColor("tooltip", "body")
            GameTooltip:AddLine(NEWBIE_TOOLTIP_RANK, c.r, c.g, c.b, true)
        end
        GameTooltip:Show()
    end)
    rankHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local y2 = y - 32 - 10
    p.pct = UI.Font(win, F.SMALL, { justify = "RIGHT" })
    p.pct:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y2 - 1)
    p.pct:SetWidth(40)
    p.pct:SetWordWrap(false)
    p.bar = FlatBar(win, 14)
    p.bar:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y2)
    p.bar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD - 46, y2)
    p.bar:EnableMouse(true)
    UI.Tooltip(p.bar, RANK_POSITION or "Rank progress", NEWBIE_TOOLTIP_RANK_POSITION)

    local y3 = y2 - 14 - 10
    p.level = UI.Font(win, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    p.level:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y3)
    p.level:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y3)
    p.level:SetWordWrap(false)
    p.guild = UI.Font(win, F.SMALL, { justify = "LEFT", cat = "text", key = "gray" })
    p.guild:SetPoint("TOPLEFT", p.level, "BOTTOMLEFT", 0, -4)
    p.guild:SetPoint("TOPRIGHT", p.level, "BOTTOMRIGHT", 0, -4)
    p.guild:SetWordWrap(false)

    -- The table: a header row and five periods. A fixed five rows, not a
    -- list - there is nothing here to scroll.
    local y4 = y3 - 40
    local ROW = 22
    local tbl = CreateFrame("Frame", nil, win)
    tbl:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y4)
    tbl:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y4)
    tbl:SetHeight(ROW * (#HONOR_ROWS + 1))
    UI.Fill(tbl, "ui", "cardBg")
    UI.Border(tbl, "ui", "border")
    tbl._zPaint = UI.PaintBox
    tbl:_zPaint()

    local columns = {
        { text = "HK",    title = HONORABLE_KILLS or "Honorable kills",       body = NEWBIE_TOOLTIP_HONORABLE_KILLS },
        { text = "DK",    title = DISHONORABLE_KILLS or "Dishonorable kills", body = NEWBIE_TOOLTIP_DISHONORABLE_KILLS },
        { text = HONOR or "Honor", title = HONOR_CONTRIBUTION_POINTS or "Honor", body = NEWBIE_TOOLTIP_HONOR_CONTRIBUTION_POINTS },
    }
    local rows = {}
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
        rows[i] = r
        return r
    end

    -- Header cells take the mouse for Blizzard's newbie tooltips.
    local head = MakeRow(1)
    local headCells = { UI.Font(head, F.SMALL, { cat = "text", key = "gray", justify = "LEFT" }) }
    for c, col in ipairs(columns) do
        local hit = CreateFrame("Frame", nil, head)
        hit:SetHeight(ROW)
        hit:EnableMouse(true)
        local fs = UI.Font(hit, F.SMALL, { text = col.text, cat = "text", key = "gold", justify = "RIGHT" })
        fs:SetPoint("RIGHT", hit, "RIGHT", 0, 0)
        UI.Tooltip(hit, col.title, col.body)
        headCells[c + 1] = hit
    end

    p.cells = {}
    for i, spec in ipairs(HONOR_ROWS) do
        local r = MakeRow(i + 1)
        local cells = { UI.Font(r, F.SMALL, { text = spec.label(), justify = "LEFT" }) }
        for c = 1, 3 do
            cells[c + 1] = UI.Font(r, F.SMALL, { justify = "RIGHT", text = DASH })
            cells[c + 1]:SetWordWrap(false)
        end
        cells[1]:SetWordWrap(false)
        p.cells[i] = cells
    end

    -- Column widths follow the table's measured width: the label column
    -- takes a third, the three numbers share the rest, each right-aligned
    -- 6px inside its column (header text included, so they line up).
    local function Layout()
        local w = (tbl:GetWidth() or 0) - 2
        if w <= 0 then return end
        local labelW = math.floor(w * 0.34)
        local colW = math.floor((w - labelW) / 3)
        local function Place(cells)
            for c, cell in ipairs(cells) do
                cell:ClearAllPoints()
                if c == 1 then
                    cell:SetPoint("LEFT", cell:GetParent(), "LEFT", 6, 0)
                    cell:SetWidth(labelW - 6)
                else
                    cell:SetPoint("LEFT", cell:GetParent(), "LEFT", labelW + (c - 2) * colW, 0)
                    cell:SetWidth(colW - 6)
                end
            end
        end
        Place(headCells)
        for _, cells in ipairs(p.cells) do Place(cells) end
    end
    tbl:SetScript("OnSizeChanged", Layout)
    Layout()

    local y5 = y4 - ROW * (#HONOR_ROWS + 1) - 10
    p.standing = UI.Font(win, F.SMALL, { justify = "LEFT" })
    p.standing:SetPoint("TOPLEFT", win, "TOPLEFT", Kit.PAD, y5)
    p.standing:SetPoint("TOPRIGHT", win, "TOPRIGHT", -Kit.PAD, y5)
    p.standing:SetWordWrap(false)
    p.highest = UI.Font(win, F.SMALL, { justify = "LEFT" })
    p.highest:SetPoint("TOPLEFT", p.standing, "BOTTOMLEFT", 0, -6)
    p.highest:SetPoint("TOPRIGHT", p.standing, "BOTTOMRIGHT", 0, -6)
    p.highest:SetWordWrap(false)
end

Page(honor)
honor.key = "honorwin"
honor.flag = "_zHonorWin"
honor.name = "ZacUIHonorWindow"
honor.title = HONOR or "Honor"
honor.icon = "Interface\\Icons\\INV_BannerPVP_02"   -- corrected per faction on open
honor.host = function() return HonorFrame end
honor.events = { "PLAYER_PVP_KILLS_CHANGED", "PLAYER_PVP_RANK_CHANGED", "PLAYER_ENTERING_WORLD",
                 "UNIT_LEVEL", "PLAYER_GUILD_UPDATE" }
honor.build = HonorBuild
honor.draw = HonorDraw
honor.onShow = function(p)
    -- The faction is not known this early at load; set the icon on open.
    -- SetIcon re-anchors the title inside the protected cover: out of
    -- combat only (the faction never changes, so a later open catches up).
    if InCombatLockdown() then return end
    local horde = UnitFactionGroup("player") == "Horde"
    p.win:SetIcon(horde and "Interface\\Icons\\INV_BannerPVP_01" or "Interface\\Icons\\INV_BannerPVP_02")
end

-- ============================================================
-- MODULES
-- ============================================================
Modules.skillswin = skills.Module
Modules.reputationwin = rep.Module
Modules.honorwin = honor.Module
