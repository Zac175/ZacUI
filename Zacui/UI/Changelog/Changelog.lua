-- Changelog - "what's new": the popup after an update, the Changelog
-- page under General, and the bookkeeping of which version was seen.
-- Part of ZacUI; load order is set by the TOC (after the config pages;
-- the data is Changelog_Data).
--
-- WHEN THE POPUP SHOWS. Once, a few seconds after the first login on a
-- version newer than the last one seen on this account - and only if
-- there are notes for it. Never on a fresh install's first login: a
-- character with no record yet has nothing to compare against, so that
-- login just writes the record down (the first-run import offer is
-- what a new install sees). The first version that ships this system
-- counts as fresh for everyone for the same reason - from the next
-- version on, everyone who has played gets the popup. It waits out
-- combat, and "Show what's new after an update" on the page turns it
-- off (the page still marks new versions).
--
-- SEEN. Closing the popup any way (Got it, the X, Escape) or pressing
-- Mark as seen on the page records the current version as seen. Account-
-- wide, in ZacUIDB.changelog - bookkeeping, outside every profile.
--
--   ns.Changelog.Show()          open the window
--   ns.Changelog.MarkSeen()
--   ns.Changelog.Unseen()        the versions after the last one seen
--   ns.Changelog.Compare(a, b)   -1 / 0 / 1, by number ("2.10" > "2.9")

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local FLAT = ns.FLAT
local GetColor = ns.GetColor
local RegisterPage = ns.RegisterPage
local UI = ns.UI
local ZUI = ns.ZUI

local M, F = UI.M, UI.F

local Changelog = {}

-- Section labels and their colours (palette text colours, so a theme
-- reaches them).
Changelog.STYLES = {
    added   = { label = "Added",   key = "blue" },
    changed = { label = "Changed", key = "yellow" },
    fixed   = { label = "Fixed",   key = "green" },
    removed = { label = "Removed", key = "red" },
}

local function DB()
    ZacUIDB.changelog = ZacUIDB.changelog or {}
    return ZacUIDB.changelog
end

-- WHAT THIS GAME VERSION SEES (2026-11-12, Zac: "can the changelog only
-- show relevant things for that version of the game ... the buff stuff
-- forever tbc and retail players dont need to see that because its
-- classic era only"). An item may say where it belongs (Changelog_Data:
-- a feature id, or the game versions); the list everything here reads
-- is the history with the other game versions' lines taken out, the
-- sections and versions that are left empty dropped. Worked out once
-- per game version (the flavor is fixed for a session once it is read).
local function Relevant(item, flavor)
    if type(item) ~= "table" then return true end
    local f = item.feature
    if ns.FeatureOn then
        if type(f) == "string" then
            if not ns.FeatureOn(f) then return false end
        elseif type(f) == "table" then
            for _, id in ipairs(f) do
                if not ns.FeatureOn(id) then return false end
            end
        end
    end
    local only = item.only
    if type(only) == "string" then
        return only == flavor
    elseif type(only) == "table" then
        for _, fl in ipairs(only) do
            if fl == flavor then return true end
        end
        return false
    end
    return true
end
Changelog.Relevant = Relevant

local shown, shownFor, shownFrom
local function Versions()
    local all = ns.CHANGELOG or {}
    local flavor = ns.Flavor and ns.Flavor() or "era"
    if shown and shownFor == flavor and shownFrom == all then return shown end
    local out = {}
    for _, v in ipairs(all) do
        local secs = {}
        for _, sec in ipairs(v.sections or {}) do
            local items = {}
            for _, item in ipairs(sec.items or {}) do
                if Relevant(item, flavor) then
                    items[#items + 1] = type(item) == "table" and item[1] or item
                end
            end
            if #items > 0 then secs[#secs + 1] = { type = sec.type, items = items } end
        end
        if #secs > 0 then
            -- (titles = { tbc = "..." }: where the title names something
            -- that game version does not have)
            out[#out + 1] = { version = v.version, date = v.date,
                title = (type(v.titles) == "table" and v.titles[flavor]) or v.title, sections = secs }
        end
    end
    shown, shownFor, shownFrom = out, flavor, all
    return out
end
Changelog.Versions = Versions
function Changelog.Current() return ZUI.VERSION end

local function Parts(v)
    local t = {}
    for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end

function Changelog.Compare(a, b)
    local pa, pb = Parts(a), Parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end
local Compare = Changelog.Compare

function Changelog.LastSeen() return DB().lastSeen end
function Changelog.PopupEnabled() return DB().popup ~= false end

-- Versions after the last one seen, up to the one running (an entry
-- written ahead for the next version is not "new" until it ships).
function Changelog.Unseen()
    local seen, cur, out = DB().lastSeen, Changelog.Current(), {}
    for _, v in ipairs(Versions()) do
        if Compare(v.version, cur) <= 0 and (not seen or Compare(v.version, seen) > 0) then
            out[#out + 1] = v
        end
    end
    return out
end

local function IsNew(v)
    local seen = DB().lastSeen
    return Compare(v.version, Changelog.Current()) <= 0
        and (not seen or Compare(v.version, seen) > 0)
end

-- What the window and the page list: everything with "show all versions"
-- ticked; otherwise what is new, or the newest entry when nothing is.
function Changelog.Visible(showAll)
    local list = Versions()
    if showAll then return list end
    local new = Changelog.Unseen()
    if #new > 0 then return new end
    for _, v in ipairs(list) do
        if Compare(v.version, Changelog.Current()) <= 0 then return { v } end
    end
    if not list[1] then return {} end
    return { list[1] }
end

local function PageOpen()
    local s = ns.ConfigState and ns.ConfigState()
    return ns.ConfigIsOpen and ns.ConfigIsOpen() and s and s.selected == "changelog"
end

function Changelog.MarkSeen()
    local db = DB()
    if db.lastSeen == Changelog.Current() then return end
    db.lastSeen = Changelog.Current()
    if PageOpen() and ns.RefreshConfig then ns.RefreshConfig() end
end

-- ============================================================
-- DRAWING ONE VERSION
-- ============================================================
-- Section by section, each label in its colour and each item a wrapped
-- line under it. Shared by the window and the page; returns the new y.
local function DrawSections(host, v, x, y, width)
    for _, sec in ipairs(v.sections or {}) do
        local style = Changelog.STYLES[sec.type] or { label = tostring(sec.type), key = "gray" }
        local head = UI.Font(host, F.LABEL, { text = style.label, cat = "text", key = style.key })
        head:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
        -- (as tall as its type: the settings window's is larger)
        y = y - math.max(16, math.ceil(head:GetStringHeight() or 12) + 3)
        for _, item in ipairs(sec.items or {}) do
            local dash = UI.Font(host, F.LABEL, { text = "-", cat = "text", key = "gray" })
            dash:SetPoint("TOPLEFT", host, "TOPLEFT", x + 4, y)
            local line = UI.Font(host, F.LABEL, { text = item, width = math.max(80, width - 16) })
            line:SetPoint("TOPLEFT", host, "TOPLEFT", x + 14, y)
            y = y - math.max(13, line:GetStringHeight() or 12) - 4
        end
        y = y - 6
    end
    return y
end

local function MetaText(v)
    local t = "v" .. tostring(v.version)
    if v.date then t = t .. "   " .. v.date end
    return t
end

-- ============================================================
-- THE WINDOW
-- ============================================================
local popup

local function Clear(frame)
    for _, c in ipairs({ frame:GetChildren() }) do
        c:Hide()
        c:ClearAllPoints()
        c:SetParent(nil)
    end
    for _, r in ipairs({ frame:GetRegions() }) do
        r:Hide()
        r:ClearAllPoints()
    end
end

local function Fill()
    local f = popup
    local child = f.child
    Clear(child)
    local S, pad = UI.S, f.pad
    local width = (f:GetWidth() or 460) - 2 * pad - 10
    child:SetWidth(width + pad)
    local showAll = DB().showAll and true or false
    -- (the settings window's type: 14 px lines, the section heads at 12,
    -- white 0.41, over a white 0.02 rule)
    local x, y = pad - 1, -12
    UI.SettingsBuild(function()
        for _, v in ipairs(Changelog.Visible(showAll)) do
            local meta = UI.PopupText(child, "hint", { text = MetaText(v), justify = "RIGHT" })
            meta:SetPoint("TOPRIGHT", child, "TOPLEFT", x + width, y)
            -- the title wraps short of the version and date (and the tag)
            local room = width - math.ceil(meta:GetStringWidth() or 0) - (IsNew(v) and 52 or 16)
            local title = UI.PopupText(child, "head", { text = v.title or ("Version " .. tostring(v.version)),
                width = math.max(80, room), justify = "LEFT" })
            title:SetPoint("TOPLEFT", child, "TOPLEFT", x, y)
            -- (2026-11-08, Zac likes Readycheck's: the version's title in
            -- the accent, the heads in their colours, a compact window)
            title._zPaint = function(self) local a = GetColor("ui", "accent") self:SetTextColor(a.r, a.g, a.b, 1) end
            title:_zPaint()
            local extra = math.max(0, math.ceil(title:GetStringHeight() or 0) - (UI.POP.HEAD + 4))
            y = y - extra
            if IsNew(v) then
                local tag = UI.SFont(child, S.F_HINT, { text = "New" })
                tag._zPaint = function(self) local a = GetColor("ui", "accent") self:SetTextColor(a.r, a.g, a.b, 1) end
                tag:_zPaint()
                tag:SetPoint("RIGHT", meta, "LEFT", -8, 0)
            end
            local rule = child:CreateTexture(nil, "ARTWORK")
            rule._zui_own = true
            rule:SetTexture(FLAT)
            rule:SetHeight(1)
            rule:SetPoint("TOPLEFT", child, "TOPLEFT", x, y - 20)
            rule:SetWidth(width)
            rule:SetVertexColor(1, 1, 1, S.SECTION_RULE_A)
            -- (2026-11-09, Zac: "i like readychecks changelog more") the
            -- sections in Readycheck's compact type: small coloured heads,
            -- small indented lines, close together
            local wasSet = UI._zSettings
            UI._zSettings = false
            local okD, ny = pcall(DrawSections, child, v, x + 2, y - 28, width - 4)
            UI._zSettings = wasSet
            if not okD then error(ny, 0) end
            y = ny - 6
        end
    end)
    local h = -y + 6
    child:SetHeight(h)
    f.scroll:Recalculate(h)
    f.scroll.bar:SetValue(0)
    f.scroll:SetVerticalScroll(0)
    f:SetTitle(showAll and "Changelog" or "What's New", "")
    if f.verText then f.verText:SetText("v" .. tostring(Changelog.Current())) end
    f.showAll:SetChecked(showAll)
end

-- (2026-11-08) the popup shell (UIF_Dialogs UI.Popup): the settings
-- window's look - the title and the version under it, the close box, the
-- list, and a foot with "Show all versions" and Got it.
local function BuildPopup()
    -- (one-line head, as Readycheck's: the title left, the version by the X)
    local f = UI.Popup("ZacUIChangelogFrame", 520, 380, "What's New", { rule = true, size = "small" })
    f:SetPoint("CENTER", 0, 40)
    f.verText = UI.PopupText(f, "hint", { text = "", justify = "RIGHT" })
    if f.closeButton then
        f.verText:SetPoint("RIGHT", f.closeButton, "LEFT", -10, 0)
    else
        f.verText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -44, -14)
    end
    f.version = f.verText

    local got = f:SetButtons({ { text = "Got it", kind = "primary", onClick = function() UI.CloseWindow(f) end } })[1]
    got:SetActive(true)

    local scroll, child = UI.ScrollArea(f, { style = "settings" })
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -(f.headerHeight + 1))
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(M.SCROLL_W + 4), f:FooterHeight() - 8)
    scroll.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -(f.headerHeight + 4))
    scroll.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, f:FooterHeight() - 4)
    if scroll.SetClipsChildren then scroll:SetClipsChildren(true) end
    f.scroll, f.child = scroll, child

    -- the foot: the "all versions" switch, level with Got it
    f.showAll = UI.SettingsBuild(UI.Checkbox, f, "Show all versions", DB().showAll, function(on)
        DB().showAll = on and true or nil
        Fill()
        if PageOpen() and ns.RefreshConfig then ns.RefreshConfig() end
    end)
    f.showAll:ClearAllPoints()
    f.showAll:SetPoint("LEFT", f, "BOTTOMLEFT", f.pad - 2, (f.pad - 4) + UI.POP.BTN_H / 2)

    UI.AttachResizeGrip(f, { minW = 360, minH = 260, maxW = 900, maxH = 900,
        onResizeStopped = function() Fill() end })
    -- closed by any route = read
    f:HookScript("OnHide", function() Changelog.MarkSeen() end)
    popup = f
    return f
end

function Changelog.Show()
    if not popup then BuildPopup() end
    Fill()
    if popup:IsShown() then popup:Raise() return end
    UI.OpenWindow(popup)
end

function Changelog.Hide()
    if popup and popup:IsShown() then UI.CloseWindow(popup) end
end

-- ============================================================
-- LOGIN
-- ============================================================
local function InCombat()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

local function ShowWhenCalm()
    if not InCombat() then
        Changelog.Show()
        return
    end
    local wait = CreateFrame("Frame")
    wait:RegisterEvent("PLAYER_REGEN_ENABLED")
    wait:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(1, Changelog.Show)
    end)
end

-- Returns true when the popup was scheduled (for the tests).
function Changelog.CheckOnLogin()
    local db, cur = DB(), Changelog.Current()
    if not db.lastSeen then
        db.lastSeen = cur
        return false
    end
    local cmp = Compare(cur, db.lastSeen)
    if cmp < 0 then
        -- back on an older version: that is the new baseline
        db.lastSeen = cur
        return false
    end
    if cmp == 0 or db.popup == false then return false end
    if #Changelog.Unseen() == 0 then return false end
    -- its turn in the login popup queue (Core_Popups: after the welcome,
    -- never in combat, never on top of another popup)
    if ns.Popups then
        ns.Popups.Want("changelog", function()
            Changelog.Show()
            return popup
        end, { delay = 3 })
        return true
    end
    C_Timer.After(3, ShowWhenCalm)
    return true
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if ZacUIDB then
        local ok, err = pcall(Changelog.CheckOnLogin)
        if not ok and ns.Print then ns.Print("changelog: " .. tostring(err)) end
    end
end)

-- ============================================================
-- PAGE (General > Changelog)
-- ============================================================
RegisterPage("Changelog", function(L)
    local cur = Changelog.Current()
    L:Header("Changelog", "What changed in each version of ZacUI. You are on v" .. tostring(cur) .. ".")

    L:Card("Options")
    local row = UI.Holder(L.current)
    row:SetSize(360, M.BUTTON_H)
    local open = UI.Button(row, "Open in a window", { width = 140,
        onClick = function() Changelog.Show() end })
    open:SetPoint("LEFT")
    local seen = UI.Button(row, "Mark as seen", { width = 120,
        tooltip = "Stops marking these versions as new.",
        onClick = function()
            Changelog.MarkSeen()
            if ns.RefreshConfig then ns.RefreshConfig() end
        end })
    seen:SetPoint("LEFT", open, "RIGHT", 8, 0)
    seen:SetDisabled(#Changelog.Unseen() == 0)
    L:Row(row, M.BUTTON_H + 8)
    local popupCb = UI.Checkbox(L.current, "Show what's new after an update",
        Changelog.PopupEnabled(), function(on)
            if on then DB().popup = nil else DB().popup = false end
        end)
    L:Row(popupCb, 17)
    L:Desc("Opens this list once, a few seconds after the first login on a new version.")
    local allCb = UI.Checkbox(L.current, "Show all versions", DB().showAll, function(on)
        DB().showAll = on and true or nil
        if popup and popup:IsShown() then Fill() end
        if ns.RefreshConfig then ns.RefreshConfig() end
    end)
    L:Row(allCb, 17)
    L:Desc("Off: only what is new since you last looked (or the latest version).")
    L:EndCard()

    for _, v in ipairs(Changelog.Visible(DB().showAll)) do
        local card = L:Card(v.title or ("Version " .. tostring(v.version)))
        local meta = UI.Font(card, F.SMALL, { text = MetaText(v) .. (IsNew(v) and "   - new" or ""),
            cat = IsNew(v) and "ui" or "text", key = IsNew(v) and "accent" or "gray" })
        meta:SetPoint("TOPLEFT", card, "TOPLEFT", M.CONTROL_X, card._y + 4)
        card._y = card._y - 16
        card._y = DrawSections(card, v, M.CONTROL_X, card._y, ns.CardWidth(card) - M.CONTROL_X - 16)
        L:EndCard()
    end
end)

-- shared with later ZacUI files
ns.Changelog = Changelog
