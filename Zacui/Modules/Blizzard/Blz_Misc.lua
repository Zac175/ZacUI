-- Blz_Misc - the bank, the guild windows, trainers, and the long tail of
-- small frames nobody thinks about until one of them is still beige.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local ForEachNamed = ns.ForEachNamed
local HideNamed = ns.HideNamed
local HideRegions = ns.HideRegions
local LiftDarkText = ns.LiftDarkText
local Modules = ns.Modules
local RegisterLoD = ns.RegisterLoD
local SkinAllScrollBarsUnder = ns.SkinAllScrollBarsUnder
local SkinArrowButton = ns.SkinArrowButton
local SkinBackdrop = ns.SkinBackdrop
local SkinBottomTabs = ns.SkinBottomTabs
local SkinButton = ns.SkinButton
local SkinIconButton = ns.SkinIconButton
local SkinPanel = ns.SkinPanel
local SkinScrollFrame = ns.SkinScrollFrame
local SkinStatusBar = ns.SkinStatusBar
local StripDeep = ns.StripDeep
local StripFrameChrome = ns.StripFrameChrome
local StripTextures = ns.StripTextures
local ZUI = ns.ZUI

-- ============================================================
-- BANK
-- ============================================================
Modules.bank = function()
    local bank = BankFrame
    if not bank or ZUI.skinned[bank] then return end

    SkinPanel(bank, { buttons = { "BankFramePurchaseButton", "BankCloseButton" } })
    if BankSlotsFrame then StripTextures(BankSlotsFrame) end

    -- The 28 general slots and the 7 bag slots. Bag slots keep their
    -- NormalTexture - on those it IS the bag artwork, and killing it is
    -- the "my bank bags went invisible" bug in a different window.
    ForEachNamed("BankFrameItem", 1, 28, function(btn)
        SkinIconButton(btn)
    end)
    ForEachNamed("BankFrameBag", 1, 7, function(btn, i, name)
        SkinIconButton(btn, true)
        HideRegions(name, { "HighlightFrameTexture" })
    end)

    -- The purchase prompt sits on its own inset with a coin readout.
    if BankFramePurchaseInfo then StripTextures(BankFramePurchaseInfo) end
    for _, n in ipairs({ "BankFrameMoneyFrameBorder", "BankSlotsFrameBackground" }) do
        local t = _G[n]
        if t then t:SetAlpha(0) end
    end
    -- Through the tab layout, not bare SkinButton: flat art at Blizzard's
    -- overlap offsets drew the bordered tabs through each other.
    SkinBottomTabs("BankFrameTab", 3)
    LiftDarkText(bank, 0)
end

-- ============================================================
-- GUILD
-- ============================================================
Modules.guild = function()
    -- Era's guild UI is a family of small windows rather than one panel.
    -- Each is optional depending on what the player has open and on
    -- whether they are in a guild at all.
    -- NOT GuildFrame: it is FriendsFrame's own tab page (setAllPoints),
    -- already stripped by the social module. A second full-size panel on it
    -- sat a level above FriendsFrame and covered the window's title.
    for _, n in ipairs({ "GuildInfoFrame", "GuildEventLogFrame",
                         "GuildMemberDetailFrame", "GuildControlPopupFrame",
                         "GuildRegistrarFrame", "GuildInviteFrame" }) do
        local f = _G[n]
        if f and not ZUI.skinned[f] then
            SkinPanel(f)
            SkinAllScrollBarsUnder(f, 0)
            LiftDarkText(f, 0)
        end
    end

    -- The list toggle is an ARROW button (its art is the glyph); SkinButton
    -- blanked it into an empty box.
    if GuildFrameGuildListToggleButton then
        SkinArrowButton(GuildFrameGuildListToggleButton, "right")
    end
    for _, n in ipairs({ "GuildFrameControlButton",
                         "GuildFrameAddMemberButton", "GuildFrameLeaveButton",
                         "GuildMemberDetailRemoveButton", "GuildMemberDetailPromoteButton",
                         "GuildMemberDetailDemoteButton", "GuildMemberDetailGuildLeaderButton",
                         "GuildControlPopupAcceptButton", "GuildInfoSaveButton",
                         "GuildInfoCancelButton", "GuildRegistrarPurchaseButton",
                         "GuildRegistrarCancelButton" }) do
        local b = _G[n]
        if b then SkinButton(b) end
    end

    SkinBottomTabs("GuildFrameTab", 4)

    -- Roster rows: strip the striped sheet, keep the class-coloured names.
    ForEachNamed("GuildFrameButton", 1, 20, function(row)
        StripTextures(row)
        local hl = row.GetHighlightTexture and row:GetHighlightTexture()
        if hl then
            hl:SetColorTexture(1, 1, 1, 0.08)
            -- StripTextures Hide()s it; without this there is no hover and
            -- no LockHighlight selection on the row at all.
            hl:SetAlpha(1)
            hl:Show()
        end
    end)

    -- The registrar and the tabard designer share the same greeting shell.
    for _, n in ipairs({ "GuildRegistrarGreetingFrame", "TabardFrame" }) do
        local f = _G[n]
        if f and not ZUI.skinned[f] then
            SkinPanel(f)
            LiftDarkText(f, 0)
        end
    end
    ForEachNamed("TabardFrameCustomization", 1, 5, function(f)
        StripTextures(f)
    end)
    for _, n in ipairs({ "TabardFrameAcceptButton", "TabardFrameCancelButton" }) do
        local b = _G[n]
        if b then SkinButton(b) end
    end
    -- Rotate buttons draw their glyph AS the normal texture: arrows, not
    -- text buttons (SkinButton left two blank squares).
    if TabardCharacterModelRotateLeftButton then
        SkinArrowButton(TabardCharacterModelRotateLeftButton, "left")
    end
    if TabardCharacterModelRotateRightButton then
        SkinArrowButton(TabardCharacterModelRotateRightButton, "right")
    end
end

-- ============================================================
-- TRAINERS
-- ============================================================
Modules.trainer = function()
    -- Class and profession trainers share Blizzard_TrainerUI.
    RegisterLoD("Blizzard_TrainerUI", function()
        local f = ClassTrainerFrame
        if not f or ZUI.skinned[f] then return end
        SkinPanel(f, { buttons = { "ClassTrainerTrainButton", "ClassTrainerCancelButton" } })
        SkinScrollFrame("ClassTrainerListScrollFrame", true)
        SkinScrollFrame("ClassTrainerDetailScrollFrame", true)
        if ClassTrainerSkillIcon then SkinIconButton(ClassTrainerSkillIcon) end
        if ClassTrainerExpandButtonFrame then StripTextures(ClassTrainerExpandButtonFrame) end
        ForEachNamed("ClassTrainerSkill", 1, 12, function(row)
            StripTextures(row)
            local hl = row.GetHighlightTexture and row:GetHighlightTexture()
            if hl then
                hl:SetColorTexture(1, 1, 1, 0.08)
                hl:SetAlpha(1)   -- re-shown: StripTextures Hide()s it
                hl:Show()
            end
        end)
        if ClassTrainerStatusBar then SkinStatusBar(ClassTrainerStatusBar) end
        if ClassTrainerFrameFilterDropDown and ns.SkinDropdown then
            ns.SkinDropdown(ClassTrainerFrameFilterDropDown)
        end
        LiftDarkText(f, 0)
    end)

    -- Pet stable and the talent-wipe confirmation live near enough to
    -- trainers to belong here rather than in the odds and ends.
    if PetStableFrame and not ZUI.skinned[PetStableFrame] then
        SkinPanel(PetStableFrame)
        -- PetStableActivePet is unindexed - the numbered helper was
        -- looking up PetStableActivePet1, which does not exist, so the
        -- active slot was never skinned.
        if PetStableActivePet then SkinIconButton(PetStableActivePet) end
        ForEachNamed("PetStabledPet", 1, 5, function(b) SkinIconButton(b) end)
        if PetStablePetInfo then StripTextures(PetStablePetInfo) end
    end
end

-- ============================================================
-- ODDS AND ENDS
-- ============================================================
-- Small windows, one line each. They earn their place because every one
-- of them is a beige rectangle in an otherwise dark UI the first time you
-- happen to open it - usually months later, usually mid-raid.
Modules.misc = function()
    local PANELS = {
        "DressUpFrame", "PetitionFrame", "ItemTextFrame", "HelpFrame",
        "RaidInfoFrame", "RaidParentFrame", "CoinPickupFrame",
        "TutorialFrame", "LFGParentFrame",
        "MeetingStoneFrame", "PetRenameFrame",
        "ChannelFrame", "ReportPlayerNameDialog",
    }
    local function SkinLoose(n)
        local f = _G[n]
        if f and not ZUI.skinned[f] then
            SkinPanel(f)
            SkinAllScrollBarsUnder(f, 0)
            LiftDarkText(f, 0)
        end
    end
    for _, n in ipairs(PANELS) do SkinLoose(n) end
    -- The group finder and the channel list are load-on-demand: a login
    -- pass alone found nothing to skin. Same one-liner once they load.
    -- Listing and Browse are setAllPoints PAGES of LFGParentFrame: stripped,
    -- never given a panel of their own (a second full-size panel covers the
    -- parent's title - the GuildFrame lesson).
    RegisterLoD("Blizzard_GroupFinder_VanillaStyle", function()
        SkinLoose("LFGParentFrame")
        for _, n in ipairs({ "LFGListingFrame", "LFGBrowseFrame" }) do
            local f = _G[n]
            if f and not ZUI.skinned[f] then
                ZUI.skinned[f] = true
                StripTextures(f)
                SkinAllScrollBarsUnder(f, 0)
                LiftDarkText(f, 0)
            end
        end
    end)
    RegisterLoD("Blizzard_Channels", function() SkinLoose("ChannelFrame") end)

    -- CALENDAR (load-on-demand). Frame, weekday, month and year art are
    -- chrome; the last-day shading and the selected-weekday glow are state
    -- and stay. Day tiles are child buttons and keep their own art.
    RegisterLoD("Blizzard_Calendar", function()
        local cal = CalendarFrame
        if not cal or ZUI.skinned[cal] then return end
        ZUI.skinned[cal] = true
        for _, region in ipairs({ cal:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture")
                and region ~= CalendarLastDayDarkTexture
                and region ~= CalendarWeekdaySelectedTexture then
                region:SetTexture(nil)
                region:Hide()
            end
        end
        SkinBackdrop(cal, "windowBg", 0.97)
        if CalendarCloseButton and ns.SkinCloseButton then
            ns.SkinCloseButton(CalendarCloseButton)
        end
        SkinAllScrollBarsUnder(cal, 0)
    end)

    local BUTTONS = {
        "DressUpFrameCancelButton", "DressUpFrameResetButton",
        "PetitionFrameSignButton", "PetitionFrameRequestButton",
        "PetitionFrameCancelButton", "PetitionFrameRenameButton",
        "CoinPickupOkayButton", "CoinPickupCancelButton",
        "RaidInfoExtendButton", "RaidInfoCancelButton",
        "TutorialFrameOkayButton", "TutorialFrameCloseButton",
        "PetRenameAcceptButton", "PetRenameCancelButton",
    }
    for _, n in ipairs(BUTTONS) do
        local b = _G[n]
        if b then SkinButton(b) end
    end

    -- DURABILITY: the little armour man. Nothing to skin, everything to
    -- tone down - at full alpha it is the brightest thing on a dark UI.
    if DurabilityFrame then
        DurabilityFrame:SetAlpha(0.75)
    end

    -- GM ticket status: a floating parchment strip.
    for _, n in ipairs({ "TicketStatusFrame", "GhostFrame", "VehicleSeatIndicator" }) do
        local f = _G[n]
        if f then StripTextures(f) end
    end
    if GhostFrame then
        SkinBackdrop(GhostFrame, "windowBg", 0.85)
        if GhostFrameContentsFrame then StripTextures(GhostFrameContentsFrame) end
    end

    -- COLOUR PICKER and OPACITY: shared by the whole UI, including our own
    -- swatches, so they are worth getting right.
    if ColorPickerFrame and not ZUI.skinned[ColorPickerFrame] then
        ZUI.skinned[ColorPickerFrame] = true
        StripTextures(ColorPickerFrame)
        StripFrameChrome(ColorPickerFrame)
        SkinBackdrop(ColorPickerFrame, "windowBg", 0.97)
        for _, n in ipairs({ "ColorPickerOkayButton", "ColorPickerCancelButton" }) do
            local b = _G[n]
            if b then SkinButton(b) end
        end
        if ColorPickerFrame.Header then ColorPickerFrame.Header:SetAlpha(0) end
        -- NOT StripTextures: a Slider's thumb is one of its regions, and
        -- stripping it leaves an invisible drag target with no way to get
        -- it back. The scrollbar skinner strips the track and re-textures
        -- the thumb, which is what this needs.
        if OpacitySliderFrame then ns.SkinAnyScrollBar(OpacitySliderFrame) end
    end
    if OpacityFrame then
        StripTextures(OpacityFrame)
        SkinBackdrop(OpacityFrame, "windowBg", 0.97)
    end

    -- RAID WARNING and the boss-emote strip: text only, but Blizzard's
    -- default has no outline and it is the one message you must not miss.
    -- These are MessageFrames: their lines are created and recycled by the
    -- widget, so they are not reachable as ordinary regions. The font has
    -- to be set on the frame itself, which is what every line inherits.
    for _, n in ipairs({ "RaidWarningFrame", "RaidBossEmoteFrame" }) do
        local f = _G[n]
        if f and f.GetFont and f.SetFont then
            local font, size = f:GetFont()
            if font then
                if ns.FollowFont then ns.FollowFont(f, size or 20, "OUTLINE")
                else f:SetFont(font, size or 20, "OUTLINE") end
            end
        end
    end

    -- AUTOCOMPLETE (the name popup on whispers and mail). It floats over
    -- everything and is pure white by default.
    if AutoCompleteBox and not ZUI.skinned[AutoCompleteBox] then
        ZUI.skinned[AutoCompleteBox] = true
        StripTextures(AutoCompleteBox)
        SkinBackdrop(AutoCompleteBox, "windowBg", 0.97)
    end

    -- The item-text (book / plaque) pages are parchment like the quest
    -- log, so they need the same text lift to stay readable.
    -- NO StripDeep here any more: the panel loop above already skinned this
    -- frame, and a deep strip AFTER it nilled ZacUI's own textures too - the
    -- panel fill and header, the X, the page buttons and the scrollbar.
    if ItemTextFrame then
        if ItemTextPrevPageButton then SkinArrowButton(ItemTextPrevPageButton, "left") end
        if ItemTextNextPageButton then SkinArrowButton(ItemTextNextPageButton, "right") end
        local function Repaint()
            -- Non-parchment books Show() and retexture these per page, and
            -- write material text colours onto the HTML page.
            HideNamed("ItemText", { "MaterialTopLeft", "MaterialTopRight",
                                    "MaterialBotLeft", "MaterialBotRight" })
            LiftDarkText(ItemTextFrame, 0)
            if ItemTextPageText then
                local c = Col("text")
                for _, tag in ipairs({ "p", "h1", "h2", "h3" }) do
                    pcall(ItemTextPageText.SetTextColor, ItemTextPageText, tag, c.r, c.g, c.b)
                end
            end
        end
        Repaint()
        ItemTextFrame:HookScript("OnEvent", Repaint)
        ItemTextFrame:HookScript("OnShow", Repaint)
        if ItemTextStatusBar and not ZUI.skinned[ItemTextStatusBar] then
            -- Border art is an unnamed region; the bar texture is spared.
            local fill = ItemTextStatusBar:GetStatusBarTexture()
            for _, region in ipairs({ ItemTextStatusBar:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("Texture")
                    and region ~= fill then
                    region:SetTexture(nil)
                    region:SetAlpha(0)
                end
            end
            SkinStatusBar(ItemTextStatusBar)
        end
    end

    -- Anything with a plain money frame border: the etched ring around a
    -- coin readout is the last piece of gold trim in most windows.
    for _, n in ipairs({ "MerchantMoneyInset", "MerchantMoneyBg",
                         "SendMailMoneyInset", "SendMailMoneyBg",
                         "OpenMailMoneyInset", "OpenMailMoneyBg",
                         "BankFrameMoneyFrameInset", "BankFrameMoneyFrameBg" }) do
        local t = _G[n]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
end
