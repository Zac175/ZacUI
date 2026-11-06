-- Blz_Gossip - quest and gossip pages (the parchment fight) and the flight map.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local HideNamed = ns.HideNamed
local LiftDarkText = ns.LiftDarkText
local Modules = ns.Modules
local PinTextLight = ns.PinTextLight
local RecolorParchmentFonts = ns.RecolorParchmentFonts
local RecolorQuestInfoStrings = ns.RecolorQuestInfoStrings
local SkinAllScrollBarsUnder = ns.SkinAllScrollBarsUnder
local SkinBackdrop = ns.SkinBackdrop
local SkinButton = ns.SkinButton
local SkinIconButton = ns.SkinIconButton
local SkinPanel = ns.SkinPanel
local SkinScrollFrame = ns.SkinScrollFrame
local StripTextures = ns.StripTextures
local ZUI = ns.ZUI

Modules.gossip = function()
    RecolorParchmentFonts()
    -- Scroll machinery, both generations: the classic named frames were
    -- never routed to the wrapper, and modern ScrollBoxes never fire the
    -- classic range-changed hook - so the gossip bar stayed stock.
    SkinScrollFrame("GossipGreetingScrollFrame")
    SkinScrollFrame("QuestGreetingScrollFrame")
    if GossipFrame then SkinAllScrollBarsUnder(GossipFrame, 0) end
    if QuestFrame then SkinAllScrollBarsUnder(QuestFrame, 0) end

    -- The known quest/gossip body strings, pinned once: Blizzard's
    -- updaters can write black to these at any point in any paint chain;
    -- the pin wins every such write.
    for _, sname in ipairs({
        "GossipGreetingText",
        "QuestInfoTitleHeader", "QuestInfoDescriptionHeader",
        "QuestInfoDescriptionText", "QuestInfoObjectivesHeader",
        "QuestInfoObjectivesText", "QuestInfoGroupSize",
        "QuestInfoRewardText", "QuestInfoItemChooseText",
        "QuestInfoItemReceiveText", "QuestInfoSpellLearnText",
        "QuestInfoRequiredMoneyText", "QuestInfoTimerText",
        "QuestProgressTitleText", "QuestProgressText",
        "QuestProgressRequiredItemsText", "QuestProgressRequiredMoneyText",
    }) do
        PinTextLight(_G[sname])
    end
    for i = 1, 10 do
        PinTextLight(_G["QuestInfoObjective" .. i])
    end

    -- The quest-title lines next to the ! are KNOWN elements - recolored
    -- structurally and unconditionally on every repaint, not left to a
    -- depth/threshold walk that kept missing them: classic named title
    -- buttons plus the modern pooled ScrollBox children.
    local function LiftQuestTitles()
        local tc = Col("text")
        for i = 1, 32 do
            for _, base in ipairs({ "GossipTitleButton", "QuestTitleButton" }) do
                local btn = _G[base .. i]
                if btn then
                    local fs = btn.GetFontString and btn:GetFontString()
                    if fs then PinTextLight(fs) end
                end
            end
        end
        local gp = GossipFrame and GossipFrame.GreetingPanel
        local box = gp and gp.ScrollBox
        local target = box and box.ScrollTarget
        if target and target.GetChildren then
            for _, child in ipairs({ target:GetChildren() }) do
                local fs = child.GetFontString and child:GetFontString()
                if fs then PinTextLight(fs) end
                LiftDarkText(child, 0)
            end
        end
    end
    if type(QuestInfo_Display) == "function" then
        hooksecurefunc("QuestInfo_Display", function()
            RecolorQuestInfoStrings()
            C_Timer.After(0, function()
                RecolorQuestInfoStrings()
                LiftDarkText(QuestFrame, 0)
                LiftDarkText(GossipFrame, 0)
                LiftQuestTitles()
            end)
        end)
    end
    -- Quest-title lift must run AFTER Blizzard paints (deferred) and on
    -- every REPOPULATION, not just show: options refresh mid-conversation
    -- with no OnShow, and the old synchronous lift ran before the titles
    -- were even set - both ways the black text survived.
    local function RefreshGossip()
        C_Timer.After(0, function()
            LiftDarkText(GossipFrame, 0)
            LiftQuestTitles()
            if GossipFrame then SkinAllScrollBarsUnder(GossipFrame, 0) end
        end)
    end
    if GossipFrame then
        GossipFrame:HookScript("OnShow", RefreshGossip)
        if GossipFrame.Update then
            hooksecurefunc(GossipFrame, "Update", RefreshGossip)
        end
    end
    if type(GossipFrameUpdate) == "function" then
        hooksecurefunc("GossipFrameUpdate", RefreshGossip)
    end
    if QuestFrameGreetingPanel then
        QuestFrameGreetingPanel:HookScript("OnShow", function(f)
            C_Timer.After(0, function()
                LiftDarkText(f, 0)
                LiftQuestTitles()
            end)
        end)
    end
    -- MEASURED panel fit: 74 cut the buttons off, 12 and 42 were still
    -- guesses. Stop guessing - the panel bottom anchors to the actual
    -- button row's measured position on THIS build, every show.
    local function FitBottom(frame)
        if not (frame and frame._zui_panel and frame.GetBottom) then return end
        local lowest
        for _, bname in ipairs({ "QuestFrameAcceptButton", "QuestFrameDeclineButton",
                                 "QuestFrameCompleteQuestButton", "QuestFrameCompleteButton",
                                 "QuestFrameGoodbyeButton", "QuestFrameCancelButton",
                                 "QuestFrameGreetingGoodbyeButton",
                                 "GossipFrameGreetingGoodbyeButton" }) do
            local btn = _G[bname]
            if btn and btn:IsShown() and btn.GetBottom then
                local bb = btn:GetBottom()
                if bb and (not lowest or bb < lowest) then lowest = bb end
            end
        end
        -- 11509: the gossip Goodbye lost its global name - it's keyed as
        -- GreetingPanel.GoodbyeButton now, and missing it here left the
        -- panel bottom guessing on gossip pages.
        local keyedGoodbye = GossipFrame and GossipFrame.GreetingPanel
            and GossipFrame.GreetingPanel.GoodbyeButton
        if keyedGoodbye and keyedGoodbye:IsShown() and keyedGoodbye.GetBottom then
            local bb = keyedGoodbye:GetBottom()
            if bb and (not lowest or bb < lowest) then lowest = bb end
        end
        -- Right edge measured from the SCROLLBAR itself: a bar cannot sit
        -- off a background that anchors to it. (r=32 was a guess that
        -- landed inside the bar's position.)
        local rightmost
        for _, sname in ipairs({ "QuestDetailScrollFrameScrollBar",
                                 "QuestRewardScrollFrameScrollBar",
                                 "QuestProgressScrollFrameScrollBar",
                                 "QuestGreetingScrollFrameScrollBar",
                                 "GossipGreetingScrollFrameScrollBar" }) do
            local bar = _G[sname]
            if bar and bar:IsShown() and bar.GetRight then
                local br = bar:GetRight()
                if br and (not rightmost or br > rightmost) then rightmost = br end
            end
        end
        local fb, fr = frame:GetBottom(), frame:GetRight()
        local offB = 42
        if lowest and fb then
            offB = math.max(0, math.floor(lowest - fb - 10))
        end
        local offR = 32
        if rightmost and fr then
            offR = math.max(2, math.floor(fr - rightmost - 6))
        end
        frame._zui_panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -offR, offB)
    end

    -- QuestFrame panels repaint their strings per stage (detail /
    -- progress / reward) - each gets a deferred lift on show.
    for _, pname in ipairs({ "QuestFrame", "QuestFrameDetailPanel",
                             "QuestFrameProgressPanel", "QuestFrameRewardPanel",
                             "GossipFrame" }) do
        local pf = _G[pname]
        if pf then
            pf:HookScript("OnShow", function(f)
                C_Timer.After(0, function()
                    LiftDarkText(f, 0)
                    FitBottom(QuestFrame)
                    FitBottom(GossipFrame)
                end)
            end)
        end
    end
    if ItemTextFrame then
        ItemTextFrame:HookScript("OnShow", function(f)
            C_Timer.After(0, function() LiftDarkText(f, 0) end)
        end)
    end
    SkinPanel(GossipFrame, { buttons = { "GossipFrameGreetingGoodbyeButton" },
                             subStrip = { "GossipFrameGreetingPanel" }})
    -- 11509 keyed spellings of the same two targets (the globals above
    -- are gone on the new client; both paths kept for older builds).
    if GossipFrame and GossipFrame.GreetingPanel then
        StripTextures(GossipFrame.GreetingPanel)
        if GossipFrame.GreetingPanel.GoodbyeButton then
            SkinButton(GossipFrame.GreetingPanel.GoodbyeButton)
        end
    end
    SkinScrollFrame("GossipGreetingScrollFrame")
    SkinScrollFrame("QuestDetailScrollFrame")
    SkinScrollFrame("QuestRewardScrollFrame")
    SkinScrollFrame("QuestProgressScrollFrame")
    SkinScrollFrame("QuestGreetingScrollFrame")
    SkinScrollFrame("ItemTextScrollFrame")
    -- Quest reward/required item rows: same NameFrame treatment.
    -- There is no QuestInfoItem<n> global on 1.15: rewards are
    -- <rewardsFrame>QuestInfoItem<n>, built lazily by QuestInfo_GetRewardButton
    -- - skin what exists, then every button the moment it is made.
    for _, rf in ipairs({ QuestInfoRewardsFrame, MapQuestInfoRewardsFrame }) do
        if rf and rf.RewardButtons then
            for _, b in ipairs(rf.RewardButtons) do SkinIconButton(b) end
        end
    end
    if type(QuestInfo_GetRewardButton) == "function" then
        hooksecurefunc("QuestInfo_GetRewardButton", function(rf, index)
            local b = rf and rf.RewardButtons and rf.RewardButtons[index]
            if b then SkinIconButton(b) end
        end)
    end
    for i = 1, 6 do
        local item = _G["QuestProgressItem" .. i]
        if item then SkinIconButton(item) end
    end
    -- MATERIAL: stone/marble/bronze quests Show() and retexture the panel's
    -- Material* quadrants on every page, undoing the one-time strip.
    if type(QuestFrame_SetMaterial) == "function" then
        hooksecurefunc("QuestFrame_SetMaterial", function(f)
            local n = f and f.GetName and f:GetName()
            if n then
                HideNamed(n, { "MaterialTopLeft", "MaterialTopRight",
                               "MaterialBotLeft", "MaterialBotRight" })
            end
        end)
    end
    SkinPanel(QuestFrame, { buttons = {
        "QuestFrameAcceptButton", "QuestFrameDeclineButton",
        "QuestFrameCompleteButton", "QuestFrameCompleteQuestButton",
        "QuestFrameGoodbyeButton", "QuestFrameGreetingGoodbyeButton",
    }, subStrip = {
        "QuestFrameDetailPanel", "QuestFrameRewardPanel",
        "QuestFrameProgressPanel", "QuestFrameGreetingPanel",
    }})

    -- NPC PORTRAIT side panel (quests that show the giver's model): its
    -- frame tiles, corners, nameplate and the text box are all Blizzard art.
    -- Region-only on the model frame; the model itself draws above.
    if QuestNPCModel and not ZUI.skinned[QuestNPCModel] then
        ZUI.skinned[QuestNPCModel] = true
        StripTextures(QuestNPCModel)
        SkinBackdrop(QuestNPCModel, "windowBg", 0.97)
        if QuestNPCModelTextFrame then
            StripTextures(QuestNPCModelTextFrame)
            SkinBackdrop(QuestNPCModelTextFrame, "windowBg", 0.97)
        end
        SkinScrollFrame("QuestNPCModelTextScrollFrame")
    end
end

-- TAXI (flight master) - Mode 3 CONTENT-ART, and the frame that WROTE
-- the map-preservation doctrine: the flight map is a texture living ON
-- TaxiFrame itself, not on a child frame, so any strip pass would erase
-- it with no recovery short of /reload. keepArt carries it through the
-- strip; noPanel puts the dark background against the MAP rect (+36
-- above for the title band, 8px breathing room on the other sides)
-- instead of the frame rect - classic TaxiFrame is mostly transparent
-- margin. /zacui inset TaxiFrame still wins when set, like every panel.
Modules.taxi = function()
    local tf = TaxiFrame
    if not tf or ZUI.skinned[tf] then return end
    local map = TaxiMap
        or (tf.GetName and tf:GetName() and _G[tf:GetName() .. "Map"])
    if not (map and map.IsObjectType and map:IsObjectType("Texture")) then
        -- No identifiable map region on this build: leave the frame
        -- COMPLETELY stock. A fitted panel is a child frame and child
        -- frames render above the parent's regions - "fallback" skinning
        -- here would paint over the flight map. Guessing near a map is
        -- never worth it; fence it so no pass meddles later.
        ZUI.skinned[tf] = true
        return
    end
    SkinPanel(tf, { keepArt = { map }, noPanel = true })
    -- Anchor the art background to the MAP region, unless the user has
    -- pinned their own inset for this frame - then the stored-inset
    -- geometry SkinPanel already applied stays in charge.
    local ins = ZacUIDB and ZacUIDB.insets and ZacUIDB.insets.TaxiFrame
    if not ins and tf._zui_artbg then
        tf._zui_artbg:ClearAllPoints()
        tf._zui_artbg:SetPoint("TOPLEFT", map, "TOPLEFT", -8, 36)
        tf._zui_artbg:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", 8, -8)
    end
end

-- MOVER REGISTRY - one mechanism for every movable element. Opt-in by
-- design: until a position is SAVED for a key, ZacUI never touches that
-- frame's anchor. Saved positions are applied at login, re-applied after
-- Blizzard's top-frame reflow (zoning re-anchors BuffFrame et al.), and
-- for loot rolls re-asserted inside the OnShow hook. Everything here is
-- an ordinary insecure frame - unit frames and action bars are
-- deliberately ABSENT: Edit Mode (1.15.9) owns those, and fighting a
-- secure position manager buys taint for nothing.
