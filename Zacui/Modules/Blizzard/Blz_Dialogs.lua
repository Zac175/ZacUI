-- Blz_Dialogs - StaticPopups and the shared dialog chrome.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local KillPopupChrome = ns.KillPopupChrome
local Modules = ns.Modules
local SkinBackdrop = ns.SkinBackdrop
local SkinButton = ns.SkinButton
local SkinCloseButton = ns.SkinCloseButton
local SkinDropDownLists = ns.SkinDropDownLists
local SkinEditBox = ns.SkinEditBox
local SkinIconButton = ns.SkinIconButton
local SkinStackSplit = ns.SkinStackSplit
local StripDeep = ns.StripDeep
local StripFrameChrome = ns.StripFrameChrome
local StripTextures = ns.StripTextures
local SkinBlizzCheck = ns.SkinBlizzCheck
local UI = ns.UI
local ZUI = ns.ZUI
local RegisterLoD = ns.RegisterLoD

local function SkinStaticPopup(sp)
    if not sp or ZUI.skinned[sp] then return end
    ZUI.skinned[sp] = true
    local pname = sp.GetName and sp:GetName()
    if sp.Border then
        sp.Border:SetAlpha(0)
        -- Kill the border's own backdrop permanently: alpha alone loses,
        -- because Blizzard's show/resize path restores chrome alpha when
        -- the dialog actually appears - which is exactly why logout and
        -- summon popups kept arriving with default borders.
        if sp.Border.SetBackdrop then
            pcall(sp.Border.SetBackdrop, sp.Border, nil)
        end
    end
    StripFrameChrome(sp)
    StripDeep(sp.Border, 0)
    SkinBackdrop(sp, "windowBg", 0.97)
    -- CONTENT, not chrome: the warning "!" and the coin icons inside the
    -- money-input boxes. Tagged ours BEFORE the first kill so the per-show
    -- sweep below spares them.
    if pname then
        local alert = _G[pname .. "AlertIcon"] or sp.AlertIcon
        if alert then alert._zui_own = true end
        for _, coin in ipairs({ "Gold", "Silver", "Copper" }) do
            local eb = _G[pname .. "MoneyInputFrame" .. coin]
            if eb then
                SkinEditBox(eb)
                -- SkinEditBox has already blanked the box art; anything
                -- still drawing on it is the coin glyph.
                for _, region in ipairs({ eb:GetRegions() }) do
                    if region.IsObjectType and region:IsObjectType("Texture")
                        and region:IsShown() and region:GetAlpha() > 0 then
                        region._zui_own = true
                    end
                end
            end
        end
        local item = _G[pname .. "ItemFrame"]
        if item then SkinIconButton(item) end
    end
    -- Per-show enforcement: whatever the show path restores, re-hide it.
    KillPopupChrome(sp, 0)
    sp:HookScript("OnShow", function(f)
        if f.NineSlice then f.NineSlice:SetAlpha(0) end
        if f.Border then f.Border:SetAlpha(0) end
        if f.GetBackdrop and f.SetBackdrop then
            local okb, bd = pcall(f.GetBackdrop, f)
            if okb and type(bd) == "table" then
                pcall(f.SetBackdrop, f, nil)
            end
        end
        -- The complete kill, EVERY show: regions, repaints, whatever -
        -- anything without our ownership tag dies before you see it.
        KillPopupChrome(f, 0)
    end)
    if pname then
        -- 11509 popups carry FOUR buttons (the new GameDialog template);
        -- older builds stop at 3 and the nil lookup no-ops.
        for b = 1, 4 do
            local btn = _G[pname .. "Button" .. b]
            if btn then SkinButton(btn) end
        end
        local eb = _G[pname .. "EditBox"]
        if eb then SkinEditBox(eb) end
        local cb = _G[pname .. "CloseButton"] or sp.CloseButton
        if cb then SkinCloseButton(cb) end
    end
end

-- THE GROUP FINDER'S OWN DIALOGS. An invite to a group you applied to
-- through the Group Finder is not a StaticPopup - it is LFGListInviteDialog,
-- a free-standing frame with a gold dialog border - and so are its
-- sign-up dialog and the role-check invite. None of them went through the
-- popup skin above, so the group invite you accept most often was the one
-- left stock. Border off, ZacUI surface on, buttons in the house style;
-- the role icons and text are content and are left alone.
local function SkinFloatDialog(f, buttonKeys)
    if not f or ZUI.skinned[f] then return end
    ZUI.skinned[f] = true
    local name = f.GetName and f:GetName()
    if f.Border then
        f.Border:SetAlpha(0)
        StripDeep(f.Border, 0)
    end
    SkinBackdrop(f, "windowBg", 0.97)
    for _, key in ipairs(buttonKeys) do
        local b = f[key] or (name and _G[name .. key])
        if b then SkinButton(b) end
    end
    -- Re-asserted on every show: the dialog template restores its border.
    f:HookScript("OnShow", function(self)
        if self.Border then self.Border:SetAlpha(0) end
    end)
end

local function SkinGroupFinderDialogs()
    SkinFloatDialog(_G.LFGListInviteDialog, { "AcceptButton", "DeclineButton", "AcknowledgeButton" })
    SkinFloatDialog(_G.LFGInvitePopup, { "AcceptButton", "DeclineButton" })
    SkinFloatDialog(_G.LFGListApplicationDialog, { "SignUpButton", "CancelButton" })
end

-- QUICK KEYBIND MODE. The dialog from Settings > Keybindings (and
-- /zui kb). The login sweep caught its backdrop and its three buttons,
-- which is why it was HALF in the house style: the DialogHeaderTemplate
-- header stayed a stock box riding the top edge and the checkbox stayed
-- stock. Here the header becomes the same title bar every ZacUI window
-- wears, the checkbox goes flat, and the body text moves down under it.
local function SkinQuickKeybind()
    local f = _G.QuickKeybindFrame
    if not f or ZUI.skinned[f] then return end
    ZUI.skinned[f] = true
    if f.Border then f.Border:SetAlpha(0); StripDeep(f.Border, 0) end
    if f.NineSlice then f.NineSlice:SetAlpha(0) end
    SkinBackdrop(f, "windowBg", 0.97)

    local M, F = UI.M, UI.F
    local title = (f.Header and f.Header.Text and f.Header.Text:GetText())
        or _G.QUICK_KEYBIND_MODE or "Quick Keybind Mode"
    if f.Header then
        StripTextures(f.Header)
        f.Header:Hide()
    end
    local bar = CreateFrame("Frame", nil, f)
    bar:SetHeight(M.TITLEBAR)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    if UI.HeaderArt then UI.HeaderArt(bar, { stepX = 150 }) else UI.Fill(bar, "ui", "headerBg") end
    local label = UI.Font(bar, F.TITLE, { text = title, cat = "text", key = "gold" })
    label:SetPoint("LEFT", 10, 2)
    label:SetJustifyH("LEFT")
    bar._zPaint = function(self)
        if UI.PaintHeaderArt then UI.PaintHeaderArt(self) end
        label:_zPaint()
    end

    -- anything hanging from the frame's top edge now hangs from the bar
    for _, r in ipairs({ f:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "FontString" then
            local point, rel, relPoint, x, y = r:GetPoint(1)
            if rel == f and point and point:find("^TOP") and (y or 0) > -(M.TITLEBAR + 8) then
                r:SetPoint(point, rel, relPoint, x, (y or 0) - M.TITLEBAR)
            end
        end
    end
    for _, child in ipairs({ f:GetChildren() }) do
        local ot = child.GetObjectType and child:GetObjectType()
        if ot == "Button" and child.GetFontString and child:GetFontString() then
            SkinButton(child)
        elseif ot == "CheckButton" then
            SkinBlizzCheck(child)
        end
    end
    f:HookScript("OnShow", function(self)
        if self.Border then self.Border:SetAlpha(0) end
        if self.Header then self.Header:Hide() end
    end)
end

-- DIALOGS
Modules.dialogs = function()
    for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        SkinStaticPopup(_G["StaticPopup" .. i])
    end
    SkinStackSplit()
    SkinDropDownLists()

    -- A popup that is already open gets REUSED for the next one without
    -- hiding (an invite arriving while another popup is up), so its
    -- OnShow - where the chrome is killed - never runs and Blizzard's
    -- freshly applied dialog art shows through. Every StaticPopup_Show
    -- re-checks whatever is on screen.
    if not ZUI._zPopupShowHooked and type(StaticPopup_Show) == "function" then
        ZUI._zPopupShowHooked = true
        hooksecurefunc("StaticPopup_Show", function()
            for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
                local sp = _G["StaticPopup" .. i]
                if sp and sp:IsShown() and ZUI.skinned[sp] then
                    if sp.Border then sp.Border:SetAlpha(0) end
                    if sp.NineSlice then sp.NineSlice:SetAlpha(0) end
                    KillPopupChrome(sp, 0)
                end
            end
        end)
    end

    SkinGroupFinderDialogs()
    if RegisterLoD then RegisterLoD("Blizzard_GroupFinder", SkinGroupFinderDialogs) end

    -- the frame is there at login on this client; the callback covers a
    -- build that makes it on first use
    SkinQuickKeybind()
    if EventRegistry and EventRegistry.RegisterCallback and not ZUI._zQkbHooked then
        ZUI._zQkbHooked = true
        EventRegistry:RegisterCallback("QuickKeybindFrame.QuickKeybindModeEnabled", SkinQuickKeybind, ZUI)
    end
end

-- GAME MENU: same dark surface as every other panel, GOLD accents.
-- AUDIT FINDING: "light grey buttons on a black menu" = Blizzard's modern
-- light-grey buttons sitting UNSKINNED on our dark backdrop. The old
-- once-per-session skin missed buttons that are created per-open or
-- nested deeper than depth 3. Skin now runs on EVERY show (idempotent via
-- ZUI.skinned) at depth 5, and prints a one-time count so the theory
-- verifies itself in chat.


-- shared with later ZacUI files
ns.SkinStaticPopup = SkinStaticPopup
