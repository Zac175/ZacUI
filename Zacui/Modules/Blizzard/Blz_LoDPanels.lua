-- Blz_LoDPanels - load-on-demand Blizzard windows: talents, trade skills,
-- crafting, the auction house, macros, the raid UI and friends.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local AnchorPanel = ns.AnchorPanel
local Col = ns.Col
local CropIconsUnder = ns.CropIconsUnder
local FindScrollBarUnder = ns.FindScrollBarUnder
local HideRegions = ns.HideRegions
local KillTexture = ns.KillTexture
local Modules = ns.Modules
local Print = ns.Print
local RegisterLoD = ns.RegisterLoD
local SharpenIcon = ns.SharpenIcon
local SkinAllScrollBarsUnder = ns.SkinAllScrollBarsUnder
local SkinAnyScrollBar = ns.SkinAnyScrollBar
local SkinArrowButton = ns.SkinArrowButton
local SkinBackdrop = ns.SkinBackdrop
local SkinBlizzCheck = ns.SkinBlizzCheck
local SkinButton = ns.SkinButton
local SkinDropdown = ns.SkinDropdown
local SkinEditBox = ns.SkinEditBox
local SkinIconButton = ns.SkinIconButton
local SkinModernScrollBar = ns.SkinModernScrollBar
local SkinPanel = ns.SkinPanel
local SkinScrollFrame = ns.SkinScrollFrame
local SkinStatusBar = ns.SkinStatusBar
local StripDeep = ns.StripDeep
local StripTextures = ns.StripTextures
local TintBorder = ns.TintBorder
local ZUI = ns.ZUI

-- Profession windows share a family of child-frame chrome the window strip
-- never reaches: the "All" expand tab, the rank bar's carved border and the
-- detail header strip. The rank bar's own Background is state tinting and
-- stays. Every name guarded - Craft lacks some of TradeSkill's pieces.
local function SkinSkillChrome(p)
    local expand = _G[p .. "ExpandButtonFrame"]
    if expand then StripTextures(expand) end
    local rank = _G[p .. "RankFrame"]
    if rank then
        HideRegions(p .. "RankFrame", { "BorderNormal" })
        SkinStatusBar(rank, { backdrop = false })
    end
    local child = _G[p .. "DetailScrollChildFrame"]
    if child then StripTextures(child) end
end

Modules.panels = function()
    RegisterLoD("Blizzard_TalentUI", function()
        -- Mode 3 (CONTENT-ART) via the one entry point: painted tree art
        -- kept and zoomed, dark background under it, standard chrome.
        local tf = TalentFrame or PlayerTalentFrame
        if not tf or ZUI.skinned[tf] then return end
        -- Prefix from the frame's OWN name: when both globals exist the
        -- old either/or guess picked "TalentFrame" while the children were
        -- named PlayerTalentFrame* - which is exactly how the real
        -- scrollbar (PlayerTalentFrameScrollFrameScrollBar) went unskinned.
        local prefix = (tf.GetName and tf:GetName()) or "TalentFrame"

        local pieces = {}
        for _, corner in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight" }) do
            local piece = _G[prefix .. "Background" .. corner]
            if piece then pieces[#pieces + 1] = piece end
        end
        -- No artZoom: cropping the four quadrants INDEPENDENTLY breaks
        -- the composite image at the seams - the "weird background". The
        -- art renders at native coords on the inset dark fill.
        SkinPanel(tf, { keepArt = pieces,
                        noPanel = true, tabs = prefix .. "Tab", tabCount = 3 })
        if tf.Inset then StripDeep(tf.Inset, 1) end

        -- Ownership chrome sweep: kept art is now TAGGED (adopted), so
        -- any untagged texture on the frame or its non-Button children is
        -- Blizzard leftover chrome - killed at skin and on every show.
        -- The ScrollFrame subtree stays sacred (tree-art law).
        local function TalentChromeKill(f, depth)
            if not f or (depth or 0) > 2 then return end
            if f.GetRegions then
                for _, region in ipairs({ f:GetRegions() }) do
                    if region.IsObjectType and region:IsObjectType("Texture")
                        and not region._zui_own then
                        region:SetTexture(nil)
                        region:SetAlpha(0)
                    end
                end
            end
            if f.GetChildren then
                for _, child in ipairs({ f:GetChildren() }) do
                    local ot = child.GetObjectType and child:GetObjectType()
                    -- CheckButtons skipped too: the spec tabs are
                    -- CheckButtons, and sweeping them is what killed
                    -- their icons every show.
                    if ot ~= "Button" and ot ~= "CheckButton"
                        and ot ~= "ScrollFrame" then
                        TalentChromeKill(child, (depth or 0) + 1)
                    end
                end
            end
        end
        TalentChromeKill(tf, 0)
        tf:HookScript("OnShow", function(f)
            C_Timer.After(0, function() TalentChromeKill(f, 0) end)
        end)

        local ac = Col("accent")
        local pointsText = _G[prefix .. "TalentPointsText"]
            or _G[prefix .. "UnspentPoints"]
        if pointsText and pointsText.SetTextColor then
            pointsText:SetTextColor(ac.r, ac.g, ac.b, 1)
        end
        -- TALENT STATE IS INFORMATION. The Slot's vertex colour is the
        -- green (learnable) / gold (maxed) cue and RankBorder is the plate
        -- under the rank number; the icon sweep blanked both. The rank plate
        -- gets its art back, and the slot colour moves onto our border.
        for i = 1, (MAX_NUM_TALENTS or 40) do
            local bname = prefix .. "Talent" .. i
            local btn = _G[bname]
            if btn and not ZUI.skinned[btn] then
                local slot = _G[bname .. "Slot"]
                local rankBorder = _G[bname .. "RankBorder"]
                local rankTex = rankBorder and rankBorder.GetTexture and rankBorder:GetTexture()
                SkinIconButton(btn)
                if rankBorder and rankTex then
                    rankBorder:SetTexture(rankTex)
                    rankBorder:SetAlpha(1)
                end
                if slot and slot.SetVertexColor then
                    hooksecurefunc(slot, "SetVertexColor", function(_, r, g, b)
                        if r and g and b then TintBorder(btn, r, g, b, 1) end
                    end)
                    local r, g, b = slot:GetVertexColor()
                    if r then TintBorder(btn, r, g, b, 1) end
                end
            end
        end

        -- Side spec tabs: ADDITIVE ONLY. SkinIconButton's region sweep
        -- killed the spec icon (stored in a region the icon-detect
        -- doesn't recognize on this template) - "no icon visible".
        -- Border added, nothing removed; the icon stays wherever it is.
        for i = 1, 4 do
            local spec = _G["PlayerSpecTab" .. i]
            if spec and not ZUI.skinned[spec] then
                ZUI.skinned[spec] = true
                -- ADOPT the tab's textures (icon included): tagged as
                -- ours, they are untouchable by any ownership sweep.
                for _, region in ipairs({ spec:GetRegions() }) do
                    if region.IsObjectType and region:IsObjectType("Texture") then
                        region._zui_own = true
                    end
                end
                AddPixelBorder(spec)
            end
        end

        -- Dual-spec activate button (the last named talent straggler)
        local activate = _G[prefix .. "ActivateButton"]
            or _G["PlayerTalentFrameActivateButton"]
        if activate then SkinButton(activate) end

        -- Wrapper path when the scrollframe is named: SkinScrollFrame
        -- also strips the named track CAPS around the bar - the leftover
        -- Blizzard borders the direct bar-skinner never touches.
        if _G[prefix .. "ScrollFrame"] then
            SkinScrollFrame(prefix .. "ScrollFrame")
        else
            local bar = FindScrollBarUnder(tf, 0)
            if bar then SkinAnyScrollBar(bar) end
        end
        SkinAllScrollBarsUnder(tf, 0)
    end)
    RegisterLoD("Blizzard_AuctionUI", function()
        -- TAB ROW FIX - runs even with auction addons: the global tab
        -- auto-styler strips tab art regardless of deference, leaving
        -- flat tabs at Blizzard's overlap geometry (flat AND overlapping,
        -- worst of both). Tabs are the one AH element auction addons
        -- don't relayout per-action, so a per-show chain is safe. Covers
        -- Auctionator's appended tabs (Shopping/Selling/Cancelling) too.
        local function FixAHTabs()
            local prev
            for i = 1, 8 do
                local tab = _G["AuctionFrameTab" .. i]
                if tab then
                    local fs = tab.GetFontString and tab:GetFontString()
                    local tw = (fs and fs:GetStringWidth()) or 0
                    if tw <= 1 then tw = 50 end
                    tab._zui_w = math.max(60, math.floor(tw + 16))
                    tab:SetSize(tab._zui_w, 22)
                    if prev then
                        tab:ClearAllPoints()
                        tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", 3, 0)
                    end
                    prev = tab
                end
            end
        end
        AuctionFrame:HookScript("OnShow", function()
            C_Timer.After(0, FixAHTabs)
        end)
        C_Timer.After(0, FixAHTabs)

        -- AUCTION ADDON POLICY: style everything, defer only LAYOUT.
        -- Only the resize/repack passes ever fought Auctionator ("buttons
        -- outside the UI") - cosmetics apply regardless; the geometry
        -- passes below are gated on this flag. (FixAHTabs above is the
        -- one geometry exception: tabs aren't addon-relayouted.)
        local auctionAddon
        local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
        if isLoaded then
            for _, ahAddon in ipairs({ "Auctionator", "TradeSkillMaster", "aux-addon" }) do
                local ok, res = pcall(isLoaded, ahAddon)
                if ok and res then
                    auctionAddon = ahAddon
                    Print("auction house: " .. ahAddon
                        .. " detected - styling applied, layout left to it.")
                    break
                end
            end
        end
        -- The classic AH is the densest widget farm in the game. This is
        -- the full enumeration: action buttons, every sort-column header,
        -- category filter list, search/level edit boxes, all nine money
        -- input boxes, filter checkboxes, the duration dropdown, and the
        -- item rows on all three tabs. Alignment comes from the classic
        -- inset preset; fine-tune live with /zacui inset AuctionFrame.
        SkinPanel(AuctionFrame, { tabs = "AuctionFrameTab", tabCount = 3, buttons = {
            "BrowseSearchButton", "BrowseResetButton", "BrowseBidButton",
            "BrowseBuyoutButton", "BrowseCloseButton",
            "BidBidButton", "BidBuyoutButton", "BidCloseButton",
            "AuctionsCreateAuctionButton", "AuctionsCancelAuctionButton", "AuctionsCloseButton",
        }})
        -- AUCTION-ADDON PANEL FIT: Auctionator's views fill regions the
        -- classic art never covered AND it resizes AuctionFrame per tab -
        -- a static art-inset panel is wrong in at least one state. Near-
        -- zero frame anchors track its resizes automatically ("background
        -- not big enough" cure). Fine-tune: /zacui inset AuctionFrame.
        if auctionAddon and AuctionFrame._zui_panel then
            AnchorPanel(AuctionFrame._zui_panel, AuctionFrame,
                { l = 4, r = 4, t = 4, b = 4 })
            -- Bottom measured from the TAB ROW's top edge, per show: the
            -- tabs half-hang below the window by design, and a fixed b=4
            -- ran the panel border straight through them ("straddling").
            local function FitAHPanelBottom()
                local t1 = AuctionFrameTab1
                local fb = AuctionFrame:GetBottom()
                local offB = 26
                if t1 and t1.GetTop and fb then
                    local tt = t1:GetTop()
                    if tt then offB = math.max(4, math.floor(tt - fb + 2)) end
                end
                AuctionFrame._zui_panel:SetPoint("BOTTOMRIGHT",
                    AuctionFrame, "BOTTOMRIGHT", -4, offB)
            end
            AuctionFrame:HookScript("OnShow", function()
                C_Timer.After(0, FitAHPanelBottom)
            end)
            C_Timer.After(0, FitAHPanelBottom)
        end
        SkinScrollFrame("BrowseScrollFrame")
        SkinScrollFrame("BidScrollFrame")
        SkinScrollFrame("AuctionsScrollFrame")
        SkinScrollFrame("BrowseFilterScrollFrame")
        if BrowsePrevPageButton then SkinArrowButton(BrowsePrevPageButton, "left") end
        if BrowseNextPageButton then SkinArrowButton(BrowseNextPageButton, "right") end

        -- Sort-column headers (all three tabs)
        for _, bname in ipairs({
            "BrowseQualitySort", "BrowseLevelSort", "BrowseDurationSort",
            "BrowseHighBidderSort", "BrowseCurrentBidSort",
            "BidQualitySort", "BidLevelSort", "BidDurationSort",
            "BidBuyoutSort", "BidStatusSort", "BidBidSort",
            "AuctionsQualitySort", "AuctionsDurationSort",
            "AuctionsHighBidderSort", "AuctionsBidSort",
        }) do
            local b = _G[bname]
            if b then
                SkinButton(b)
                -- The sort arrow IS the header's NormalTexture ($parentArrow),
                -- which SkinButton cleared; SortButton_UpdateArrow only moves
                -- its texcoords, so without this no header ever shows a sort.
                local ar = _G[bname .. "Arrow"] or b.Arrow
                if ar and ar.SetTexture then
                    ar:SetTexture("Interface\\Buttons\\UI-SortArrow")
                    ar:SetAlpha(1)
                end
            end
        end

        -- Category filter list (left column). The highlight is also the
        -- SELECTED-category cue (LockHighlight), so it comes back flat.
        local ac = Col("accent")
        for i = 1, 15 do
            local f = _G["AuctionFilterButton" .. i]
            if f then
                SkinButton(f)
                local hl = f.GetHighlightTexture and f:GetHighlightTexture()
                if hl then
                    hl:SetColorTexture(ac.r, ac.g, ac.b, 0.2)
                    hl:SetAlpha(1)
                end
            end
        end

        -- Search + level edit boxes
        for _, ename in ipairs({ "BrowseName", "BrowseMinLevel", "BrowseMaxLevel" }) do
            local eb = _G[ename]
            if eb then SkinEditBox(eb) end
        end
        -- Money inputs (gold/silver/copper triplets)
        -- Silver/copper boxes tuck behind the previous coin icon in the
        -- classic layout; skinned borders made the overlap visible.
        for _, base in ipairs({ "BrowseBidPrice", "BidBidPrice", "StartPrice", "BuyoutPrice" }) do
            for _, coin in ipairs({ "Silver", "Copper" }) do
                local eb = _G[base .. coin]
                if eb and eb.GetPoint and not eb._zui_nudged then
                    eb._zui_nudged = true
                    local pt, rel, rp, x, y = eb:GetPoint(1)
                    if pt and rel then
                        eb:SetPoint(pt, rel, rp, (x or 0) + 4, y or 0)
                    end
                end
            end
        end
        for _, base in ipairs({ "BrowseBidPrice", "BidBidPrice", "StartPrice", "BuyoutPrice" }) do
            for _, coin in ipairs({ "Gold", "Silver", "Copper" }) do
                local eb = _G[base .. coin]
                if eb then SkinEditBox(eb) end
            end
        end

        -- Filter checkboxes
        for _, cname in ipairs({ "IsUsableCheckButton", "ShowOnPlayerCheckButton",
                                 "ExactMatchCheckButton" }) do
            local cb = _G[cname]
            if cb then SkinBlizzCheck(cb) end
        end

        -- Sell-tab duration dropdown (name varies by build)
        for _, dname in ipairs({ "DurationDropDown", "AuctionsDurationDropDown" }) do
            local dd = _G[dname]
            if dd then SkinDropdown(dd) end
        end

        -- AUX-INSPIRED COMPACTION: aux is a full replacement addon (its
        -- own scanner and posting engine) - a skin borrows its DENSITY,
        -- not its engine. Compact fixed-width tabs (the huge-by-design
        -- overlap disease, treated AH-locally), shrunken action buttons
        -- sized to their labels, tight sort headers and filter rows. All
        -- re-asserted one frame after EVERY show, because the AH relayouts
        -- itself constantly ("starts to bug out") and one-time sizing
        -- loses to that.
        local function CompactAH()
            if auctionAddon then return end
            -- Explicit CHAIN: these tabs anchor to the FRAME with
            -- absolute offsets, so the same-point x-rewrite slammed tabs
            -- 2-3 to the frame's left edge (the overlap). Tab 1 keeps its
            -- point; the rest chain off it. Safe: per-show reassert
            -- neutralizes the old race class.
            local prevTab
            for i = 1, 3 do
                local tab = _G["AuctionFrameTab" .. i]
                if tab then
                    tab._zui_w = 86
                    tab:SetSize(86, 22)
                    if prevTab then
                        tab:ClearAllPoints()
                        tab:SetPoint("TOPLEFT", prevTab, "TOPRIGHT", 3, 0)
                    end
                    prevTab = tab
                end
            end
            for _, bname in ipairs({
                "BrowseSearchButton", "BrowseResetButton", "BrowseBidButton",
                "BrowseBuyoutButton", "BrowseCloseButton",
                "BidBidButton", "BidBuyoutButton", "BidCloseButton",
                "AuctionsCreateAuctionButton", "AuctionsCancelAuctionButton",
                "AuctionsCloseButton",
            }) do
                local b = _G[bname]
                if b then
                    local fs = b.GetFontString and b:GetFontString()
                    local tw = (fs and fs:GetStringWidth()) or 0
                    if tw <= 1 then tw = 50 end
                    b:SetSize(math.max(60, math.floor(tw + 14)), 20)
                end
            end
            -- Trio REPACKS: shrunken widths were pushing anchor-chained
            -- buttons outside the frame. Each row re-chains leftward off
            -- its Close button's own Blizzard anchor - bounded by
            -- construction.
            local function ChainLeft(anchorBtn, ...)
                local prev = anchorBtn
                for _, b in ipairs({ ... }) do
                    if b and prev then
                        b:ClearAllPoints()
                        b:SetPoint("RIGHT", prev, "LEFT", -3, 0)
                        prev = b
                    end
                end
            end
            if not auctionAddon then
                ChainLeft(BrowseCloseButton, BrowseBuyoutButton, BrowseBidButton)
                ChainLeft(BidCloseButton, BidBuyoutButton, BidBidButton)
                ChainLeft(AuctionsCloseButton, AuctionsCancelAuctionButton,
                    AuctionsCreateAuctionButton)
            end

            for _, hname in ipairs({
                "BrowseQualitySort", "BrowseLevelSort", "BrowseDurationSort",
                "BrowseHighBidderSort", "BrowseCurrentBidSort",
                "BidQualitySort", "BidLevelSort", "BidDurationSort",
                "BidBuyoutSort", "BidStatusSort", "BidBidSort",
                "AuctionsQualitySort", "AuctionsDurationSort",
                "AuctionsHighBidderSort", "AuctionsBidSort",
            }) do
                local h = _G[hname]
                if h then h:SetHeight(19) end
            end
            for i = 1, 15 do
                local f = _G["AuctionFilterButton" .. i]
                if f then f:SetHeight(18) end
            end
        end
        AuctionFrame:HookScript("OnShow", function()
            C_Timer.After(0, CompactAH)
        end)
        C_Timer.After(0, CompactAH)

        -- Item rows on all three tabs: strip row art, crop the item icon
        local rowSets = {
            { prefix = "BrowseButton",   count = NUM_BROWSE_TO_DISPLAY or 8 },
            { prefix = "BidButton",      count = NUM_BIDS_TO_DISPLAY or 9 },
            { prefix = "AuctionsButton", count = NUM_AUCTIONS_TO_DISPLAY or 9 },
        }
        for _, set in ipairs(rowSets) do
            for i = 1, set.count do
                local row = _G[set.prefix .. i]
                if row then
                    StripTextures(row)
                    -- Re-shown flat: the row highlight is also the selected-
                    -- auction cue (LockHighlight), and the strip hid it.
                    local hl = row.GetHighlightTexture and row:GetHighlightTexture()
                    if hl then
                        hl:SetColorTexture(1, 1, 1, 0.08)
                        hl:SetAlpha(1)
                        hl:Show()
                    end
                end
                local item = _G[set.prefix .. i .. "Item"]
                if item then SkinIconButton(item) end
            end
        end
    end)
    RegisterLoD("Blizzard_TradeSkillUI", function()
        SkinPanel(TradeSkillFrame, { buttons = {
            "TradeSkillCreateButton", "TradeSkillCreateAllButton", "TradeSkillCancelButton",
        }})
        SkinScrollFrame("TradeSkillListScrollFrame", true)
        SkinScrollFrame("TradeSkillDetailScrollFrame", true)
        for i = 1, 8 do
            local r = _G["TradeSkillReagent" .. i]
            if r then SkinIconButton(r) end
        end
        if TradeSkillSkillIcon then SkinIconButton(TradeSkillSkillIcon) end
        SkinSkillChrome("TradeSkill")
    end)
    RegisterLoD("Blizzard_CraftUI", function()
        SkinPanel(CraftFrame, { buttons = { "CraftCreateButton", "CraftCancelButton" }})
        SkinScrollFrame("CraftListScrollFrame", true)
        SkinScrollFrame("CraftDetailScrollFrame", true)
        for i = 1, 8 do
            local r = _G["CraftReagent" .. i]
            if r then SkinIconButton(r) end
        end
        if CraftIcon then SkinIconButton(CraftIcon) end
        SkinSkillChrome("Craft")
    end)
    RegisterLoD("Blizzard_MacroUI", function()
        SkinPanel(MacroFrame, { tabs = "MacroFrameTab", tabCount = 2, buttons = {
            "MacroSaveButton", "MacroCancelButton", "MacroDeleteButton",
            "MacroNewButton", "MacroExitButton", "MacroEditButton",
        }})
        SkinScrollFrame("MacroButtonScrollFrame")
        SkinScrollFrame("MacroPopupScrollFrame")
        SkinScrollFrame("MacroFrameScrollFrame")
        -- Modern builds hang keyed bars off the frame instead
        if MacroFrame then
            SkinModernScrollBar(MacroFrame.ScrollBar)
            if MacroFrame.MacroSelector then
                SkinModernScrollBar(MacroFrame.MacroSelector.ScrollBar)
            end
            -- Icon grids are pooled and rebuilt per-open: crop on every
            -- show (idempotent, pure region ops).
            MacroFrame:HookScript("OnShow", function(f)
                C_Timer.After(0, function() CropIconsUnder(f, 0) end)
            end)
            CropIconsUnder(MacroFrame, 0)
        end
        -- Guaranteed body texture: whatever layering ate the fitted
        -- panel on this template, a direct frame texture renders under
        -- all children unconditionally.
        if MacroFrame then
            SkinBackdrop(MacroFrame, "windowBg", 0.97)
            if MacroFrame.Inset then StripDeep(MacroFrame.Inset, 1) end
        end
        -- The type-your-macro area: its Blizzard-backdrop border also
        -- falls to the black-lines rule; explicit treatment here for the
        -- background fill and the popup's name box.
        if MacroFrameTextBackground then
            SkinBackdrop(MacroFrameTextBackground, "elementBg", 0.6)
        end
        if MacroFrameSelectedMacroBackground then
            StripTextures(MacroFrameSelectedMacroBackground)
        end
        if MacroPopupEditBox then SkinEditBox(MacroPopupEditBox) end
        if MacroPopupFrame then
            -- 11509: the icon picker is the retail IconSelectorPopup -
            -- keyed BorderBox buttons/edit box, pooled icon ScrollBox.
            -- All guarded; classic builds no-op every branch.
            local bb = MacroPopupFrame.BorderBox
            if bb then
                if bb.OkayButton then SkinButton(bb.OkayButton) end
                if bb.CancelButton then SkinButton(bb.CancelButton) end
                if bb.IconSelectorEditBox then SkinEditBox(bb.IconSelectorEditBox) end
            end
            SkinAllScrollBarsUnder(MacroPopupFrame, 0)
            MacroPopupFrame:HookScript("OnShow", function(f)
                C_Timer.After(0, function()
                    CropIconsUnder(f, 0)
                    SkinAllScrollBarsUnder(f, 0)
                end)
            end)
        end
    end)
    -- (The standalone-Bartender4 branch that lived here is gone: running
    -- first, its thinner skin fenced every button and the real skin in
    -- Modules/AddOns/Skin_Bartender4.lua never ran.)

    RegisterLoD("Blizzard_BindingUI", function()
        SkinPanel(KeyBindingFrame, { buttons = {
            "KeyBindingFrameDefaultButton", "KeyBindingFrameUnbindButton",
            "KeyBindingFrameOkayButton", "KeyBindingFrameCancelButton",
        }})
        SkinScrollFrame("KeyBindingFrameScrollFrame")
    end)
end
