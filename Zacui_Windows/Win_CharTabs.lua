-- Win_CharTabs - ZacUI tab strips in place of Blizzard's tab rows: the
-- Character / Pet / Reputation / Skills / Honor tabs, the Friends / Who /
-- Guild / Raid tabs, the Friends / Ignore tabs and the Inbox / Send Mail
-- tabs.
-- Part of ZacUI; load order is set by the TOC.
--
-- WHY. The pages above these rows are ZacUI windows now, but the rows were
-- still Blizzard's - re-skinned, but Blizzard's label-hugging widths, their
-- overlap geometry and a 22px height that reads as a row of tiny buttons
-- hanging off a different window family.
--
-- HOW. A strip of UI.Button tabs laid where Blizzard's row sits, with the
-- visible tabs sharing the window's width. Each tab is a look only; on top
-- of it sits a SecureActionButton whose action is "click Blizzard's tab".
-- So switching page runs Blizzard's own tab handler with Blizzard's
-- credentials - these windows carry protected pages (ZacUI's secure gear
-- slots, the raid page's unit buttons), and an addon switching them itself
-- would be refused in combat. Blizzard's tabs are faded and click-through
-- underneath; they still exist, still show / hide / disable themselves,
-- and are what actually gets clicked. The strip mirrors all three.
--
-- Secure buttons: built, moved, shown and hidden out of combat only. The
-- selected / disabled look is paint (colours), which is allowed any time.

local ADDON_NAME = ...
-- Zacui_Windows is a part of ZacUI: one namespace, published by Core_Boot.
local ns = _G.ZacUI
if not ns then return end

-- shared state from earlier ZacUI files
local GetColor = ns.GetColor
local Kit = ns.Kit
local Modules = ns.Modules
local UI = ns.UI

local M, F = UI.M, UI.F

local TAB_H   = 28    -- bottom strip tab height
local HEAD_H  = 24    -- Friends / Ignore strip height
local TAB_GAP = 3     -- between tabs
local DROP    = 2     -- window bottom -> strip top
local MAX_W   = 130   -- a two-tab row does not stretch to the full width
local LABEL   = F.CARD
-- Friends / Ignore strip top, from the top of FriendsFrame: just under the
-- Battle.net bar (26px down, 29 tall in FriendsFrame.xml).
local HEAD_Y  = -57

local strips = {}        -- every strip spec that has a module, for the hooks
local pending = false    -- layout work waiting for combat to end
local hooked = false

local function ModuleOn(key)
    return ZacUIDB and ZacUIDB.modules and ZacUIDB.modules[key] ~= false
end

-- ============================================================
-- ONE STRIP
-- ============================================================
local Strip = {}
Strip.__index = Strip

function Strip:BlizzTab(i)
    return _G[self.prefix .. i]
end

function Strip:Enabled()
    return ModuleOn(self.key)
end

-- Blizzard's own (localised) label for each tab.
function Strip:Label(i)
    local t = self:BlizzTab(i)
    local text = t and t.GetText and t:GetText()
    if not text or text == "" then
        local fs = t and t.GetFontString and t:GetFontString()
        text = fs and fs:GetText()
    end
    if not text or text == "" then text = self.fallback[i] or "" end
    return text
end

function Strip:Selected()
    local owner = self.owner()
    return owner and owner.selectedTab
end

-- PAINT (combat-safe: colours only). Blizzard disables the SELECTED tab as
-- well as a truly unavailable one, so the "unavailable" look reads the
-- template's own isDisabled flag, not IsEnabled.
function Strip:Paint()
    if not self.frame then return end
    local sel = self:Selected()
    for _, t in ipairs(self.tabs) do
        local b = self:BlizzTab(t.index)
        local off = (b and b.isDisabled) and true or false
        -- Flags and paint only: the look is the parent of a secure button,
        -- so its Enable / Disable would be refused in combat.
        t.visual._zDisabled = off or nil
        t.visual._zActive = (not off and sel == t.index) or nil
        t.visual:_zPaint()
    end
end

-- Hover, forwarded from the secure overlay (the look takes no mouse).
local function HoverOn(v)
    if v._zActive or v._zDisabled then return end
    local c = GetColor("button", "hover")
    if v._zFill then v._zFill:SetVertexColor(c.r, c.g, c.b, c.a or 1) end
    if v._zText then
        local a = GetColor("ui", "accent")
        v._zText:SetTextColor(a.r, a.g, a.b, 1)
    end
end

-- LAYOUT (out of combat only)
function Strip:Layout()
    if not self.frame then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    local host = self.host()
    if not host then return end
    self.place(self.frame, host)

    local shown = {}
    for _, t in ipairs(self.tabs) do
        local b = self:BlizzTab(t.index)
        if b and b:IsShown() then shown[#shown + 1] = t else t.visual:Hide() end
        t.visual:SetLabel(self:Label(t.index))
    end
    local total = self.frame:GetWidth()
    if not total or total < 50 then total = self.fallbackWidth(host) end
    local n = #shown
    local w = n > 0 and math.floor((total - (n - 1) * TAB_GAP) / n) or 0
    if w > MAX_W then w = MAX_W end
    local prev
    for _, t in ipairs(shown) do
        t.visual:ClearAllPoints()
        t.visual:SetSize(w, self.height)
        -- A label wider than its share ("Reputation" in a five-tab row at a
        -- big UI font) steps down rather than spilling out of the tab.
        local fs = t.visual._zText
        local path, size, flags = fs:GetFont()
        t.baseSize = t.baseSize or size
        if path and t.baseSize then
            fs:SetFont(path, t.baseSize, flags)
            local s = t.baseSize
            while s > 9 and fs:GetStringWidth() > w - 8 do
                s = s - 1
                fs:SetFont(path, s, flags)
            end
        end
        if prev then
            t.visual:SetPoint("LEFT", prev, "RIGHT", TAB_GAP, 0)
        else
            t.visual:SetPoint("LEFT", self.frame, "LEFT", 0, 0)
        end
        t.visual:Show()
        prev = t.visual
    end
    self:Paint()
end

function Strip:QueueLayout()
    if InCombatLockdown() then
        pending = true
        return
    end
    if self._layoutQueued then return end
    self._layoutQueued = true
    local s = self
    C_Timer.After(0, function() s._layoutQueued = nil s:Layout() end)
end

-- BUILD (out of combat only)
function Strip:Build()
    if self.frame or InCombatLockdown() then return end
    local parent = self.parent()
    if not parent then return end
    local f = CreateFrame("Frame", self.name, parent)
    f:SetHeight(self.height)
    f:SetFrameLevel(math.min(parent:GetFrameLevel() + 60, 9000))
    self.frame = f

    for i = 1, self.count do
        local target = self:BlizzTab(i)
        if target then
            local v = UI.Button(f, self:Label(i), { height = self.height, width = 60, size = LABEL })
            v:EnableMouse(false)
            local s = CreateFrame("Button", nil, v, "SecureActionButtonTemplate")
            s:SetAllPoints(v)
            s:SetFrameLevel(v:GetFrameLevel() + 2)
            s:SetAttribute("useOnKeyDown", false)
            s:RegisterForClicks("AnyUp")
            s:SetAttribute("type", "click")
            s:SetAttribute("clickbutton", target)
            s:SetScript("OnEnter", function() HoverOn(v) end)
            s:SetScript("OnLeave", function() v:_zPaint() end)
            self.tabs[#self.tabs + 1] = { visual = v, secure = s, index = i }
        end
    end
end

function Strip:Leftovers()
    local t = {}
    for i = 1, self.count do
        local b = self:BlizzTab(i)
        if b then t[#t + 1] = b end
    end
    return t
end

function Strip:Apply()
    if not self.host() then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    if self:Enabled() then
        self:Build()
        if not self.frame then return end
        self.frame:Show()
        Kit.Silence(self:Leftovers())
        self:Layout()
    elseif self.frame then
        self.frame:Hide()
        Kit.Unsilence(self:Leftovers())
    end
end

local function NewStrip(spec)
    spec.tabs = {}
    spec.height = spec.height or TAB_H
    return setmetatable(spec, Strip)
end

-- ============================================================
-- PLACEMENT
-- ============================================================
-- Bottom rows: flush under the window's visible edge (its inset line), in
-- the band Blizzard's own tabs hang in.
local function PlaceBelow(insetName)
    return function(f, host)
        local ins = ns.GetPanelInset(insetName, host)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", host, "BOTTOMLEFT", ins.l or 0, (ins.b or 0) - DROP)
        f:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", -(ins.r or 0), (ins.b or 0) - DROP)
    end
end

local function WidthInside(insetName)
    return function(host)
        local ins = ns.GetPanelInset(insetName, host)
        return (host:GetWidth() or 338) - (ins.l or 0) - (ins.r or 0)
    end
end

-- Measured from FriendsFrame's own top edge, not the panel inset: the
-- Battle.net bar it sits under is at a fixed spot in Blizzard's XML.
local function FriendsHeaderPlace(f)
    local ins = ns.GetPanelInset("FriendsFrame", FriendsFrame)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", FriendsFrame, "TOPLEFT", (ins.l or 0) + Kit.PAD, HEAD_Y)
    f:SetPoint("TOPRIGHT", FriendsFrame, "TOPRIGHT", -(ins.r or 0) - Kit.PAD, HEAD_Y)
end

-- ============================================================
-- THE STRIPS
-- ============================================================
local charStrip = NewStrip({
    key = "chartabswin", name = "ZacUICharacterTabs",
    prefix = "CharacterFrameTab", count = 5,
    fallback = { CHARACTER or "Character", PET or "Pet", REPUTATION or "Reputation",
                 SKILLS or "Skills", HONOR or "Honor" },
    host   = function() return CharacterFrame end,
    parent = function() return CharacterFrame end,
    owner  = function() return CharacterFrame end,
    place  = PlaceBelow("CharacterFrame"),
    fallbackWidth = WidthInside("CharacterFrame"),
})

local friendsStrip = NewStrip({
    key = "friendtabswin", name = "ZacUIFriendsTabs",
    prefix = "FriendsFrameTab", count = 4,
    fallback = { FRIENDS or "Friends", WHO or "Who", GUILD or "Guild", RAID or "Raid" },
    host   = function() return FriendsFrame end,
    parent = function() return FriendsFrame end,
    owner  = function() return FriendsFrame end,
    place  = PlaceBelow("FriendsFrame"),
    fallbackWidth = WidthInside("FriendsFrame"),
})

-- Parented to Blizzard's header frame, so it shows on the Friends and
-- Ignore pages only - exactly when Blizzard shows its own two tabs -
-- without ZacUI ever showing or hiding it (which combat would refuse).
local headerStrip = NewStrip({
    key = "friendtabswin", name = "ZacUIFriendsHeaderTabs",
    prefix = "FriendsTabHeaderTab", count = 2, height = HEAD_H,
    fallback = { FRIENDS or "Friends", IGNORE or "Ignore" },
    host   = function() return _G.FriendsTabHeader and FriendsFrame end,
    parent = function() return _G.FriendsTabHeader end,
    owner  = function() return _G.FriendsTabHeader end,
    place  = FriendsHeaderPlace,
    fallbackWidth = function() return 300 end,
})

local mailStrip = NewStrip({
    key = "mailtabswin", name = "ZacUIMailTabs",
    prefix = "MailFrameTab", count = 2,
    fallback = { INBOX or "Inbox", SENDMAIL or "Send Mail" },
    host   = function() return MailFrame end,
    parent = function() return MailFrame end,
    owner  = function() return MailFrame end,
    place  = PlaceBelow("MailFrame"),
    fallbackWidth = WidthInside("MailFrame"),
})

-- ============================================================
-- SHARED HOOKS
-- ============================================================
local function ApplyPending()
    pending = false
    for _, s in ipairs(strips) do s:Apply() end
end

local function HookOnce()
    if hooked then return end
    hooked = true

    local watch = CreateFrame("Frame")
    watch:RegisterEvent("PLAYER_REGEN_ENABLED")
    watch:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(watch.RegisterEvent, watch, "UNIT_PET")
    watch:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_ENABLED" then
            if pending then ApplyPending() end
            return
        end
        if event == "UNIT_PET" then
            if unit == "player" then charStrip:QueueLayout() end
            return
        end
        for _, s in ipairs(strips) do s:QueueLayout() end
    end)

    -- Selection and availability: SetTab, EnableTab and DisableTab all end
    -- in PanelTemplates_UpdateTabs, with the owning frame.
    if PanelTemplates_UpdateTabs then
        hooksecurefunc("PanelTemplates_UpdateTabs", function(frame)
            for _, s in ipairs(strips) do
                if s.frame and s.owner() == frame then s:Paint() end
            end
        end)
    end
    -- The pet tab comes and goes with the pet.
    if PetTab_Update then
        hooksecurefunc("PetTab_Update", function() charStrip:QueueLayout() end)
    end
end

local function Setup(s)
    local host = s.host()
    if not host or s._zSetup then return end
    s._zSetup = true
    strips[#strips + 1] = s
    HookOnce()

    for i = 1, s.count do
        local b = s:BlizzTab(i)
        if b then
            b:HookScript("OnShow", function() s:QueueLayout() end)
            b:HookScript("OnHide", function() s:QueueLayout() end)
        end
    end
    host:HookScript("OnShow", function()
        if InCombatLockdown() then
            s:Paint()
            return
        end
        -- A /zui toggle takes effect on the next open.
        local on = s:Enabled()
        if on ~= (s.frame and s.frame:IsShown() or false) then s:Apply() end
        s:Layout()
    end)
    s:Apply()
end

-- ============================================================
-- MODULES
-- ============================================================
Modules.chartabswin = function()
    if not CharacterFrame then return end
    Setup(charStrip)
end

Modules.friendtabswin = function()
    if not FriendsFrame then return end
    Setup(friendsStrip)
    if _G.FriendsTabHeader then Setup(headerStrip) end
end

Modules.mailtabswin = function()
    if not MailFrame then return end
    Setup(mailStrip)
end

-- The top edge of the Friends / Ignore pages when the header strip is on
-- (an offset from the top of FriendsFrame), or nil to use Blizzard's tabs.
local function FriendsHeaderBottom(ins)
    if not (_G.FriendsTabHeader and headerStrip:Enabled()) then return nil end
    return HEAD_Y - HEAD_H - DROP
end

local function PageBottom()
    local ins = ns.GetPanelInset("CharacterFrame", CharacterFrame)
    return ins.b or 0
end

-- shared with later ZacUI files (and the pages, at call time)
ns.CharTabs = {
    Apply = function() charStrip:Apply() end,
    Refresh = function() charStrip:Paint() end,
    Enabled = function() return charStrip:Enabled() end,
    PageBottom = PageBottom,
}
ns.TabStrips = {
    FriendsHeaderBottom = FriendsHeaderBottom,
}
