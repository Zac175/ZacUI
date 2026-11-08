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

local function Versions() return ns.CHANGELOG or {} end
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
    local width = (f:GetWidth() or 460) - M.SCROLL_W - 26
    child:SetWidth(width + 16)
    local showAll = DB().showAll and true or false
    local y = -10
    for _, v in ipairs(Changelog.Visible(showAll)) do
        local title = UI.Font(child, F.CARD, { text = v.title or ("Version " .. tostring(v.version)),
            cat = "text", key = "gold" })
        title:SetPoint("TOPLEFT", child, "TOPLEFT", 10, y)
        local meta = UI.Font(child, F.SMALL, { text = MetaText(v), cat = "text", key = "gray", justify = "RIGHT" })
        meta:SetPoint("TOPRIGHT", child, "TOPLEFT", 10 + width, y - 2)
        if IsNew(v) then
            local tag = UI.Font(child, F.SMALL, { text = "New", cat = "ui", key = "accent" })
            tag:SetPoint("RIGHT", meta, "LEFT", -8, 0)
        end
        local rule = child:CreateTexture(nil, "ARTWORK")
        rule._zui_own = true
        rule:SetTexture(FLAT)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", child, "TOPLEFT", 10, y - 18)
        rule:SetWidth(width)
        local b = GetColor("ui", "border")
        rule:SetVertexColor(b.r, b.g, b.b, 1)
        y = DrawSections(child, v, 10, y - 26, width)
        y = y - 8
    end
    local h = -y + 6
    child:SetHeight(h)
    f.scroll:Recalculate(h)
    f.scroll.bar:SetValue(0)
    f.scroll:SetVerticalScroll(0)
    f.titleText:SetText(showAll and "Changelog" or "What's new")
    f.version:SetText("v" .. tostring(Changelog.Current()))
    f.showAll:SetChecked(showAll)
end

local function BuildPopup()
    local f = UI.Window("ZacUIChangelogFrame", 460, 420, "What's new")
    f:SetPoint("CENTER", 0, 40)

    local version = UI.Font(f.titleBar, F.SMALL, { cat = "text", key = "gray", justify = "RIGHT" })
    version:SetPoint("RIGHT", f.closeButton, "LEFT", -10, 0)
    f.version = version

    local scroll, child = UI.ScrollArea(f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -(f.headerHeight + 2))
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(M.SCROLL_W + 4), 40)
    scroll.bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -(f.headerHeight + 4))
    scroll.bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 44)
    f.scroll, f.child = scroll, child

    -- the footer: a rule, the "all versions" switch, and Got it
    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    foot:SetHeight(38)
    local rule = foot:CreateTexture(nil, "ARTWORK")
    rule._zui_own = true
    rule:SetTexture(FLAT)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT")
    rule:SetPoint("TOPRIGHT")
    foot._zPaint = function()
        local b = GetColor("ui", "border")
        rule:SetVertexColor(b.r, b.g, b.b, 1)
    end
    foot:_zPaint()
    f.showAll = UI.Checkbox(foot, "Show all versions", DB().showAll, function(on)
        DB().showAll = on and true or nil
        Fill()
        if PageOpen() and ns.RefreshConfig then ns.RefreshConfig() end
    end)
    f.showAll:SetPoint("LEFT", foot, "LEFT", 12, 0)
    local ok = UI.Button(foot, "Got it", { width = 90, onClick = function() UI.CloseWindow(f) end })
    ok:SetPoint("RIGHT", foot, "RIGHT", -24, 0)
    ok:SetActive(true)

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
