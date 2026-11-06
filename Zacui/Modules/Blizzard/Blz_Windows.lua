-- Blz_Windows - quest log, social panel, containers, trade and loot.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local ForEachNamed = ns.ForEachNamed
local HideRegions = ns.HideRegions
local LiftDarkText = ns.LiftDarkText
local Modules = ns.Modules
local Print = ns.Print
local RegisterLoD = ns.RegisterLoD
local RecolorParchmentFonts = ns.RecolorParchmentFonts
local RecolorQuestLogStrings = ns.RecolorQuestLogStrings
local SkinAllScrollBarsUnder = ns.SkinAllScrollBarsUnder
local SkinArrowButton = ns.SkinArrowButton
local SkinBackdrop = ns.SkinBackdrop
local SkinCloseButton = ns.SkinCloseButton
local SkinDropdown = ns.SkinDropdown
local SkinIconButton = ns.SkinIconButton
local SkinPanel = ns.SkinPanel
local SkinScrollFrame = ns.SkinScrollFrame
local SkinStatusBar = ns.SkinStatusBar
local StripDeep = ns.StripDeep
local StripFrameChrome = ns.StripFrameChrome
local StripTextures = ns.StripTextures
local ZUI = ns.ZUI

Modules.questlog = function()
    RecolorParchmentFonts()
    -- Blizzard calls QuestLog_Update on QUEST_LOG_UPDATE, UPDATE_FACTION
    -- and UNIT_QUEST_LOG_CHANGED whether the log is open or not (it also
    -- drives the tracker) - every rep tick on raid trash. The lift walks
    -- the whole frame, so it only runs while the log is shown, and a
    -- burst of updates becomes one lift a fifth of a second later.
    if type(QuestLog_Update) == "function" then
        local pending = false
        local function Lift()
            pending = false
            if not (QuestLogFrame and QuestLogFrame:IsShown()) then return end
            RecolorQuestLogStrings()
            LiftDarkText(QuestLogFrame, 0)
        end
        hooksecurefunc("QuestLog_Update", function()
            if pending or not (QuestLogFrame and QuestLogFrame:IsShown()) then return end
            pending = true
            C_Timer.After(0.2, Lift)
        end)
        if QuestLogFrame and QuestLogFrame.HookScript then
            QuestLogFrame:HookScript("OnShow", function()
                if pending then return end
                pending = true
                C_Timer.After(0, Lift)
            end)
        end
    end
    RecolorQuestLogStrings()
    SkinPanel(QuestLogFrame, { buttons = {
        "QuestLogFrameAbandonButton", "QuestFramePushQuestButton",
        "QuestLogFrameTrackButton", "QuestLogFrameCancelButton",
    }})
    SkinScrollFrame("QuestLogListScrollFrame")
    SkinScrollFrame("QuestLogDetailScrollFrame")
    -- Child-frame art the window strip never reaches: the "All" sort tab,
    -- the empty-log parchment, and the reward rows' name plates.
    if QuestLogExpandButtonFrame then StripTextures(QuestLogExpandButtonFrame) end
    if EmptyQuestLogFrame then StripTextures(EmptyQuestLogFrame) end
    for i = 1, 10 do
        local item = _G["QuestLogItem" .. i]
        if item then SkinIconButton(item) end
    end
end

-- FRIENDS / SOCIAL
Modules.friends = function()
    -- Sub-panels stripped only when they are actually FriendsFrame's own
    -- tab panels (GuildFrame/RaidFrame can be standalone windows on some
    -- builds - stripping those would wreck unrelated UI).
    for _, fname in ipairs({ "FriendsListFrame", "WhoFrame", "GuildFrame",
                             "RaidFrame", "IgnoreListFrame" }) do
        local f = _G[fname]
        if f and f.GetParent and f:GetParent() == FriendsFrame then
            StripTextures(f)
        end
    end
    SkinPanel(FriendsFrame, { tabs = "FriendsFrameTab", tabCount = 4, buttons = {
        "FriendsFrameAddFriendButton", "FriendsFrameSendMessageButton",
        "FriendsFrameIgnorePlayerButton", "FriendsFrameUnsquelchButton",
        "FriendsFrameMuteButton", "GuildFrameControlButton",
        "WhoFrameWhoButton", "WhoFrameAddFriendButton", "WhoFrameGroupInviteButton",
    }})
    if WhoFrameDropDown then SkinDropdown(WhoFrameDropDown) end
    SkinScrollFrame("FriendsFrameFriendsScrollFrame")
    SkinScrollFrame("WhoListScrollFrame")
    SkinScrollFrame("GuildListScrollFrame")
    -- 11509: the Who dropdown went WowStyle1 (already flat-modern, left
    -- stock - the nil global above no-ops) and the friends list rides a
    -- HybridScrollFrame; the deep sweep catches whichever bar generation
    -- this build ships.
    if FriendsFrame then SkinAllScrollBarsUnder(FriendsFrame, 0) end

    -- RAID TAB CONTENTS live in Blizzard_RaidUI (load-on-demand): group
    -- outlines, slot art, the member bars and the pullouts. Member buttons
    -- and pullout rows are SECURE unit buttons - region writes only.
    RegisterLoD("Blizzard_RaidUI", function()
        local e = Col("elementBg")
        for g = 1, 8 do
            local group = _G["RaidGroup" .. g]
            if group and not ZUI.skinned[group] then
                ZUI.skinned[group] = true
                StripTextures(group)
                SkinBackdrop(group, "elementBg", 0.5)
                for s = 1, 5 do
                    local slot = _G["RaidGroup" .. g .. "Slot" .. s]
                    if slot then
                        -- the slot's highlight is the drag-drop target cue
                        local hl = slot.GetHighlightTexture and slot:GetHighlightTexture()
                        for _, region in ipairs({ slot:GetRegions() }) do
                            if region.IsObjectType and region:IsObjectType("Texture")
                                and region ~= hl then
                                region:SetTexture(nil)
                                region:SetAlpha(0)
                            end
                        end
                        if hl then hl:SetColorTexture(1, 1, 1, 0.08) end
                    end
                end
            end
        end
        local function SkinMember(btn)
            if not btn or ZUI.skinned[btn] then return end
            ZUI.skinned[btn] = true
            local nt = btn.GetNormalTexture and btn:GetNormalTexture()
            if nt then nt:SetColorTexture(e.r, e.g, e.b, 0.8) end
            local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
            if hl then hl:SetColorTexture(1, 1, 1, 0.08) end
        end
        ForEachNamed("RaidGroupButton", 1, 40, SkinMember)
        if type(RaidGroupFrame_Update) == "function" then
            hooksecurefunc("RaidGroupFrame_Update", function()
                ForEachNamed("RaidGroupButton", 1, 40, SkinMember)
            end)
        end

        -- Pullouts are generated on drag-out and their rows on update.
        local function SkinPullout(po)
            local pn = po and po.GetName and po:GetName()
            if not pn then return end
            local bd = _G[pn .. "MenuBackdrop"]
            if bd and not ZUI.skinned[bd] then
                ZUI.skinned[bd] = true
                if bd.NineSlice then bd.NineSlice:SetAlpha(0) end
                SkinBackdrop(bd, "windowBg", 0.9)
            end
            for i = 1, 40 do
                local bn = pn .. "Button" .. i
                if not _G[bn] then break end
                for _, bar in ipairs({ "HealthBar", "ManaBar" }) do
                    local sb = _G[bn .. bar]
                    if sb and not ZUI.skinned[sb] then
                        HideRegions(bn .. bar, { "Frame" })
                        SkinStatusBar(sb, { backdrop = false })
                    end
                end
            end
        end
        if type(RaidPullout_Update) == "function" then
            hooksecurefunc("RaidPullout_Update", SkinPullout)
        end
        for i = 1, (NUM_RAID_PULLOUT_FRAMES or 0) do
            SkinPullout(_G["RaidPullout" .. i])
        end
    end)
end

-- ============================================================
-- BAGS
-- ============================================================
-- WHY THIS USED TO DO NOTHING. The old body hung everything off
-- ContainerFrame_GenerateFrame, which was the 1.14 entry point for
-- building a bag. 1.15 backported the retail container system and that
-- global no longer exists, so `type(...) == "function"` was false, the
-- hook never installed, and the only bags that ever got skinned were the
-- ones already open at login - i.e. none. Silent, because a missing hook
-- looks exactly like a hook that never fired.
--
-- The replacement does not depend on any one build's entry point. Every
-- ContainerFrame exists at login whether or not it is shown, so each one
-- gets an OnShow hook; the frame skins itself the first time it appears
-- and re-crops its slots on every open after that (slots are reused
-- across bags, so their contents - and their count - change).
Modules.bags = function()
    -- ZacUI's own combined bag replaces these frames outright, so skinning
    -- them as well would be work nobody ever sees.
    if ZacUIDB.modules and ZacUIDB.modules.inventory then return end
    -- Dedicated bag addons replace the container frames entirely - our
    -- skin would fight them for nothing. Defer when one is present.
    for _, bagAddon in ipairs({ "Baganator", "Bagnon", "AdiBags", "ArkInventory",
                                "Baggins", "OneBag3", "Combuctor" }) do
        if ns.AddonLoaded(bagAddon) then
            Print("bags: " .. bagAddon .. " detected - ZacUI defers bag styling to it.")
            return
        end
    end

    local function SkinSlots(frame, name)
        -- Slot count varies per bag and changes when you swap a bag, so
        -- this runs on every show rather than once. SkinIconButton fences
        -- itself, so repeats are free.
        for j = 1, 36 do
            local slot = _G[name .. "Item" .. j]
            if slot then SkinIconButton(slot) end
        end
    end

    local function SkinBag(frame)
        if not frame then return end
        local name = frame.GetName and frame:GetName()
        if not name then return end
        if not ZUI.skinned[frame] then
            ZUI.skinned[frame] = true
            StripTextures(frame)
            StripFrameChrome(frame)
            SkinBackdrop(frame, "windowBg", 0.97)
            -- Close button naming differs by generation: the classic
            -- global, the keyed field, or a child of the portrait header.
            local close = _G[name .. "CloseButton"] or frame.CloseButton
                or (frame.PortraitContainer and frame.PortraitContainer.CloseButton)
            if close then SkinCloseButton(close) end
            -- The money frame and the bag-name plate are separate art.
            for _, sfx in ipairs({ "BackgroundTop", "BackgroundMiddle1",
                                   "BackgroundMiddle2", "BackgroundBottom",
                                   "Portrait", "PortraitButton", "Bg" }) do
                local t = _G[name .. sfx] or frame[sfx]
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
            local title = _G[name .. "Name"] or (frame.Title)
            if title and title.SetTextColor then
                local a = Col("accent")
                title:SetTextColor(a.r, a.g, a.b, 1)
            end
        end
        SkinSlots(frame, name)
    end

    -- EVERY generation's entry point, all optional. Whichever this build
    -- actually has will fire; the others cost a type() check at login.
    if type(ContainerFrame_GenerateFrame) == "function" then
        hooksecurefunc("ContainerFrame_GenerateFrame", SkinBag)
    end
    if type(ContainerFrame_Update) == "function" then
        hooksecurefunc("ContainerFrame_Update", SkinBag)
    end

    -- The reliable path on 1.15: the frames all exist from login, hidden.
    -- Hooking OnShow needs no knowledge of how Blizzard decides to open
    -- them, which is the part that keeps changing.
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local cf = _G["ContainerFrame" .. i]
        if cf then
            cf:HookScript("OnShow", SkinBag)
            if cf:IsShown() then SkinBag(cf) end
        end
    end

    -- The bank shares the container templates for its own bag frames.
    if type(BankFrameItemButton_Update) == "function" then
        hooksecurefunc("BankFrameItemButton_Update", function(btn)
            if btn then SkinIconButton(btn) end
        end)
    end
end

-- TRADE
Modules.trade = function()
    SkinPanel(TradeFrame, { buttons = { "TradeFrameTradeButton", "TradeFrameCancelButton" }})
    for i = 1, 7 do
        -- Row strips kill the grey NameFrame bars (the "weird" Blizzard
        -- slot look); names are FontStrings and survive.
        local mineRow = _G["TradePlayerItem" .. i]
        local theirRow = _G["TradeRecipientItem" .. i]
        if mineRow then StripTextures(mineRow) end
        if theirRow then StripTextures(theirRow) end
        local mine   = _G["TradePlayerItem" .. i .. "ItemButton"]
        local theirs = _G["TradeRecipientItem" .. i .. "ItemButton"]
        if mine then SkinIconButton(mine) end
        if theirs then SkinIconButton(theirs) end
    end
    if TradeHighlightPlayer then StripTextures(TradeHighlightPlayer) end
    if TradeHighlightRecipient then StripTextures(TradeHighlightRecipient) end
    -- 11509: TradeFrame moved to ButtonFrameTemplate and grew four named
    -- InsetFrameTemplate boxes plus separate ENCHANT-slot highlights -
    -- none existed on the old client, and their default grey inset art
    -- is exactly the "trade window looks off" residue. Insets die deep
    -- (their NineSlice hides in child frames); highlights get the same
    -- strip the item highlights always had.
    for _, iname in ipairs({ "TradeRecipientItemsInset", "TradeRecipientEnchantInset",
                             "TradePlayerItemsInset", "TradePlayerEnchantInset" }) do
        local inset = _G[iname]
        if inset then StripDeep(inset, 1) end
    end
    if TradeHighlightPlayerEnchant then StripTextures(TradeHighlightPlayerEnchant) end
    if TradeHighlightRecipientEnchant then StripTextures(TradeHighlightRecipientEnchant) end

    -- ============================================================
    -- THE ZACUI LOOK, ON BLIZZARD'S OWN GEOMETRY
    -- ============================================================
    -- Not a cover, unlike the other windows, and that is forced: the
    -- gold / silver / copper boxes (TradePlayerInputMoneyFrame) are a
    -- FORBIDDEN frame in this client. An addon may not touch it at all -
    -- not move it, not skin it, not even call a method on it - and an
    -- opaque cover would sit on top of it and eat every click. So the
    -- window keeps Blizzard's layout, every piece of stock art goes, and
    -- ZacUI draws the rest underneath: a card per side with the name as
    -- its header, a box per item row, the money row, the "will not be
    -- traded" slot set apart, and a green wash on a side once it has
    -- accepted. Nothing here ever reaches TradePlayerInputMoneyFrame.
    local tf = TradeFrame
    local UI, GetColor = ns.UI, ns.GetColor
    if not (tf and UI and GetColor) or tf._zTradeLook then return end
    tf._zTradeLook = true

    -- Stock art the strips above never reach: the portraits and the
    -- recipient's half-frame (portrait ring, corner, side bar, grey wash)
    -- are loose textures on TradeFrame; the money insets and the gold
    -- edge round their money are frames of their own.
    for _, n in ipairs({ "TradeFramePlayerPortrait", "TradeFrameRecipientPortrait",
            "TradeRecipientPortraitFrame", "TradeRecipientBotLeftCorner",
            "TradeRecipientLeftBorder", "TradeRecipientBG" }) do
        local t = _G[n]
        if t and t.SetAlpha then
            t:SetAlpha(0)
            if t.Hide then t:Hide() end
        end
    end
    for _, n in ipairs({ "TradeFrameInset", "TradePlayerInputMoneyInset",
            "TradeRecipientMoneyInset", "TradeRecipientMoneyBg" }) do
        local fr = _G[n]
        if fr then
            StripDeep(fr, 1)
            if fr.NineSlice then fr.NineSlice:SetAlpha(0) end
        end
    end
    if tf.Inset then StripDeep(tf.Inset, 1) end

    local base = tf:GetFrameLevel()

    -- A texture in a palette colour, remembered so a colour change
    -- repaints it with the rest of the card.
    local function Tex(card, layer, sub, cat, key, alpha)
        local t = card:CreateTexture(nil, layer, nil, sub)
        t._zui_own = true
        t:SetTexture(ns.FLAT)
        t._zCat, t._zKey, t._zAlpha = cat, key, alpha
        card._zTex[#card._zTex + 1] = t
        return t
    end
    local function PaintCard(card)
        UI.PaintBox(card)
        for _, t in ipairs(card._zTex) do
            local c = GetColor(t._zCat, t._zKey)
            t:SetVertexColor(c.r, c.g, c.b, t._zAlpha or c.a or 1)
        end
    end

    -- One side of the trade. x1 / x2 are Blizzard's column edges.
    -- rowX is where Blizzard puts that side's rows (153 wide).
    local function Side(x1, x2, rowX, nameText, rowPrefix, enchantText, highlight, enchantHighlight)
        local card = UI.Box(tf, "ui", "cardBg")
        card:SetFrameLevel(base)
        card:SetPoint("TOPLEFT", tf, "TOPLEFT", x1, -26)
        card:SetPoint("BOTTOMRIGHT", tf, "TOPLEFT", x2, -414)
        card._zTex = {}

        -- Header: the character's name, a hairline under it.
        local head = Tex(card, "BACKGROUND", -6, "ui", "headerBg")
        head:SetPoint("TOPLEFT", 1, -1)
        head:SetPoint("TOPRIGHT", -1, -1)
        head:SetHeight(26)
        local rule = Tex(card, "BORDER", 0, "ui", "accent", 0.6)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
        rule:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
        -- TradeFrame's own strings would sit UNDER the card (a child
        -- frame draws over its parent's regions), so they move onto it.
        if nameText then
            nameText:SetParent(card)
            nameText:SetDrawLayer("OVERLAY")
            nameText:ClearAllPoints()
            nameText:SetPoint("LEFT", head, "LEFT", 8, 0)
            nameText:SetPoint("RIGHT", head, "RIGHT", -66, 0)
            nameText:SetJustifyH("LEFT")
            if nameText.SetWordWrap then nameText:SetWordWrap(false) end
        end

        -- The money row sits at Blizzard's fixed -58 .. -82.
        local money = Tex(card, "BACKGROUND", -5, "ui", "elementBg")
        money:SetPoint("TOPLEFT", tf, "TOPLEFT", x1 + 4, -57)
        money:SetPoint("BOTTOMRIGHT", tf, "TOPLEFT", x2 - 4, -83)

        -- A box behind each item row (icon and name), and the untraded
        -- slot set apart under a rule of its own.
        -- The row's right edge to the card's inner edge.
        local dx = (x2 - 4) - (rowX + 153)
        for i = 1, 7 do
            local row = _G[rowPrefix .. i]
            if row then
                local bg = Tex(card, "BACKGROUND", -5, "ui", "elementBg")
                bg:SetPoint("TOPLEFT", row, "TOPLEFT", -3, 2)
                bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", dx, -2)
                local nm = _G[rowPrefix .. i .. "Name"]
                if nm then
                    nm:ClearAllPoints()
                    nm:SetPoint("LEFT", row, "LEFT", 44, 0)
                    nm:SetPoint("RIGHT", row, "RIGHT", dx - 4, 0)
                    nm:SetHeight(30)
                    nm:SetJustifyH("LEFT")
                end
            end
        end
        local sep = Tex(card, "BORDER", 0, "ui", "border")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -(353 - 26))
        sep:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -(353 - 26))
        if enchantText then
            enchantText:SetParent(card)
            enchantText:SetDrawLayer("OVERLAY")
            enchantText:ClearAllPoints()
            enchantText:SetPoint("TOPLEFT", tf, "TOPLEFT", x1 + 8, -358)
            enchantText:SetWidth(x2 - x1 - 16)
            enchantText:SetJustifyH("LEFT")
        end

        -- Accepted: Blizzard shows this frame when that side has clicked
        -- Trade, so a wash and ring on it follow the state for free. It
        -- is stretched over the whole card; the separate enchant-slot
        -- highlight would only double it, so that one stays invisible.
        if highlight then
            highlight:ClearAllPoints()
            highlight:SetAllPoints(card)
            highlight:SetFrameLevel(base + 1)
            local wash = highlight:CreateTexture(nil, "BACKGROUND", nil, -4)
            wash._zui_own = true
            wash:SetAllPoints()
            wash:SetTexture(ns.FLAT)
            local ring = CreateFrame("Frame", nil, highlight)
            ring:SetAllPoints()
            UI.Border(ring, "ui", "borderSelected")
            ring._zPaint = UI.PaintBox
            local tag = UI.Font(highlight, UI.F.SMALL, { cat = "text", key = "green",
                text = "Accepted", justify = "RIGHT" })
            tag:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
            highlight._zPaint = function()
                local g = GetColor("ui", "borderSelected")
                wash:SetVertexColor(g.r, g.g, g.b, 0.14)
                ring:_zPaint()
                tag:_zPaint()
            end
            highlight:_zPaint()
        end
        if enchantHighlight then enchantHighlight:SetAlpha(0) end

        card._zPaint = PaintCard
        card:_zPaint()
        return card
    end

    Side(4, 166, 14, TradeFramePlayerNameText, "TradePlayerItem",
        TradeFramePlayerEnchantText, TradeHighlightPlayer, TradeHighlightPlayerEnchant)
    Side(175, 338, 182, TradeFrameRecipientNameText, "TradeRecipientItem",
        TradeFrameRecipientEnchantText, TradeHighlightRecipient, TradeHighlightRecipientEnchant)

    -- The window's own title, in the header band the panel skin drew.
    local title = tf.TitleText or (tf.TitleContainer and tf.TitleContainer.TitleText)
        or _G.TradeFrameTitleText
    if title and title.SetText and (title:GetText() or "") == "" then
        title:SetText(TRADE or "Trade")
    end
end

-- LOOT
Modules.loot = function()
    SkinPanel(LootFrame)
    for i = 1, (LOOTFRAME_NUMBUTTONS or 4) do
        local b = _G["LootButton" .. i]
        if b then SkinIconButton(b) end
    end
    if LootFrameDownButton then SkinArrowButton(LootFrameDownButton, "down") end
    if LootFrameUpButton then SkinArrowButton(LootFrameUpButton, "up") end
end

-- GOSSIP + QUEST GIVER
