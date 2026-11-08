-- Blz_World - the world map, the objective tracker and the PvP windows.
-- Part of ZacUI; load order is set by the TOC.
--
-- Everything in this file is guarded frame-by-frame. Classic Era has been
-- backporting retail templates for several patches, so which of these
-- globals exists varies by build - and a nil index in a login module takes
-- every module after it down with it. `if X then` everywhere is not
-- defensive clutter here, it is the interface contract.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local ForEachNamed = ns.ForEachNamed
local LiftDarkText = ns.LiftDarkText
local Modules = ns.Modules
local RegisterLoD = ns.RegisterLoD
local SkinAllScrollBarsUnder = ns.SkinAllScrollBarsUnder
local SkinBackdrop = ns.SkinBackdrop
local SkinBottomTabs = ns.SkinBottomTabs
local SkinButton = ns.SkinButton
local SkinCloseButton = ns.SkinCloseButton
local SkinPanel = ns.SkinPanel
local SkinStatusBar = ns.SkinStatusBar
local StripDeep = ns.StripDeep
local StripFrameChrome = ns.StripFrameChrome
local StripTextures = ns.StripTextures
local ZUI = ns.ZUI

-- ============================================================
-- WORLD MAP
-- ============================================================
Modules.worldmap = function()
    local map = WorldMapFrame
    if map and not ZUI.skinned[map] then
        ZUI.skinned[map] = true

        -- THE SCROLL CONTAINER IS SACRED. It holds the actual map canvas,
        -- its pins and its overlay tiles; a StripTextures anywhere inside
        -- it deletes the map itself. Only the chrome AROUND it is touched
        -- - the same rule the talent tree taught us.
        local chrome = map.BorderFrame or map
        StripFrameChrome(chrome)
        if chrome ~= map then StripTextures(chrome) end
        if map.NineSlice then map.NineSlice:SetAlpha(0) end
        if map.BorderFrame and map.BorderFrame.NineSlice then
            map.BorderFrame.NineSlice:SetAlpha(0)
        end

        -- A dark plate behind the whole window, under the canvas. At
        -- sublevel -8 it renders below every map tile, so the map still
        -- draws normally and only the margins go dark.
        SkinBackdrop(map, "windowBg", 0.95)

        local close = WorldMapFrameCloseButton
            or (map.BorderFrame and map.BorderFrame.CloseButton)
            or map.CloseButton
        if close then SkinCloseButton(close) end

        -- Forever's (modern) map hangs the quest-panel toggle over the
        -- canvas as one of its overlay frames, drawn as two arrow
        -- pictures: skinned as text buttons they were empty dark boxes
        -- (2026-11-07). There it keeps Blizzard's arrows; the Classic
        -- map has no overlay frames and is treated as before.
        local modernToggle = map.SidePanelToggle and type(map.overlayFrames) == "table"
        for _, key in ipairs({ "SidePanelToggle", "NavBar", "TitleCanvasSpacerFrame" }) do
            local piece = map[key]
            if piece and not (modernToggle and key == "SidePanelToggle") then StripTextures(piece) end
        end
        if map.SidePanelToggle and not modernToggle then
            for _, b in ipairs({ map.SidePanelToggle.OpenButton,
                                 map.SidePanelToggle.CloseButton }) do
                if b then SkinButton(b) end
            end
        end

        -- 1.15 replaced the old windowed map with the canvas + NavBar
        -- version, so the pre-canvas furniture (WorldMapZoomOutButton,
        -- WorldMapContinentDropDown, the size toggles) is gone. Rather
        -- than list names that resolve to nil on every login, the buttons
        -- and dropdowns that DO exist are found structurally - which also
        -- survives the next time Blizzard renames them.
        local function SkinChrome(root, depth)
            if not root or (depth or 0) > 3 or not root.GetChildren then return end
            for _, child in ipairs({ root:GetChildren() }) do
                local otype = child.GetObjectType and child:GetObjectType()
                if otype == "Button" and child.GetFontString and child:GetFontString() then
                    SkinButton(child)
                elseif otype == "EditBox" then
                    if ns.SkinEditBox then ns.SkinEditBox(child) end
                end
                SkinChrome(child, (depth or 0) + 1)
            end
        end
        if map.BorderFrame then SkinChrome(map.BorderFrame, 0) end
        if map.NavBar then SkinChrome(map.NavBar, 0) end
        SkinAllScrollBarsUnder(map, 0)
    end

    -- Battlefield minimap is load-on-demand and has its own tab and close.
    RegisterLoD("Blizzard_BattlefieldMinimap", function()
        local bm = BattlefieldMinimap
        if not bm or ZUI.skinned[bm] then return end
        ZUI.skinned[bm] = true
        for _, n in ipairs({ "BattlefieldMinimapCorner", "BattlefieldMinimapBackground" }) do
            local t = _G[n]
            if t then t:SetAlpha(0) end
        end
        StripTextures(BattlefieldMinimapTab)
        if BattlefieldMinimapTab then SkinBackdrop(BattlefieldMinimapTab, "windowBg", 0.9) end
        if BattlefieldMinimapCloseButton then
            SkinCloseButton(BattlefieldMinimapCloseButton)
        end
        ns.AddPixelBorder(bm)
    end)
end

-- ============================================================
-- OBJECTIVE TRACKER
-- ============================================================
-- Classic Era's tracker is QuestWatchFrame: a bare stack of font strings
-- with no background of its own. There is nothing to strip, so this module
-- is entirely about legibility - Blizzard's objective colour is a dim
-- grey-brown that vanishes against snow and against Silithus.
Modules.tracker = function()
    -- COLOUR IS NOT OURS TO TAKE HERE. Blizzard tints watch lines by quest
    -- difficulty and dims completed objectives, and both are information.
    -- So this only LIFTS text that is too dark to read against the world,
    -- and leaves anything already legible exactly as the game set it -
    -- the same rule the quest log uses.
    local function PaintLine(fs)
        if not fs or not fs.SetTextColor then return end
        local r, g, b = fs:GetTextColor()
        if r and r < 0.45 and g < 0.45 and b < 0.45 then
            local c = Col("text")
            fs:SetTextColor(c.r, c.g, c.b, 1)
        end
        -- The outline is the real win: the tracker sits on open world with
        -- no backing of its own, and Blizzard ships it unshadowed. A font
        -- is set once per line: SetFont re-lays the text out even when
        -- nothing changed, and this runs on every quest-log update.
        if fs.GetFont and not fs._zOutlined then
            local font, size = fs:GetFont()
            if font then
                -- (in ZacUI's font, kept up when it changes)
                if ns.FollowFont then ns.FollowFont(fs, size or 11, "OUTLINE")
                else fs:SetFont(font, size or 11, "OUTLINE") end
                fs._zOutlined = true
            end
        end
    end

    -- the line frames, each looked up once it exists (no 60 string
    -- builds per repaint)
    local lines = {}
    local function Repaint()
        for i = 1, 60 do
            local fs = lines[i]
            if not fs then
                fs = _G["QuestWatchLine" .. i]
                if not fs then break end    -- the lines come in a contiguous run
                lines[i] = fs
            end
            PaintLine(fs)
        end
    end

    Repaint()
    -- The tracker rebuilds its lines whenever the quest log changes -
    -- which is every rep tick and every loot on raid trash, in bursts;
    -- one repaint a fifth of a second after the last of them is enough.
    if type(QuestWatch_Update) == "function" then
        local pending = false
        hooksecurefunc("QuestWatch_Update", function()
            if pending then return end
            pending = true
            C_Timer.After(0.2, function() pending = false Repaint() end)
        end)
    end

    if QuestTimerFrame then
        StripTextures(QuestTimerFrame)
        ForEachNamed("QuestTimer", 1, 10, function(fs) PaintLine(fs) end)
    end
end

-- ============================================================
-- PVP
-- ============================================================
Modules.pvp = function()
    -- Scoreboard. The row art is a striped sheet; flattening it makes the
    -- columns readable and the sort headers land where you expect.
    local score = WorldStateScoreFrame
    if score and not ZUI.skinned[score] then
        SkinPanel(score, { buttons = { "WorldStateScoreFrameLeaveButton" } })
        ForEachNamed("WorldStateScoreButton", 1, 25, function(row, i, name)
            StripTextures(row)
            local hl = row.GetHighlightTexture and row:GetHighlightTexture()
            if hl then
                hl:SetColorTexture(1, 1, 1, 0.08)
                hl:SetAlpha(1)   -- re-shown: StripTextures Hide()s it
                hl:Show()
            end
            -- Alternating rows, ours rather than Blizzard's sheet.
            if not row._zui_stripe then
                local t = row:CreateTexture(nil, "BACKGROUND")
                t._zui_own = true
                t:SetAllPoints()
                t:SetTexture(ns.FLAT)
                local c = Col("elementBg")
                t:SetVertexColor(c.r, c.g, c.b, (i % 2 == 0) and 0.35 or 0.15)
                row._zui_stripe = t
            end
        end)
        -- Tab layout, not bare SkinButton: flat tabs at Blizzard's overlap
        -- offsets drew through each other.
        SkinBottomTabs("WorldStateScoreFrameTab", 5)
        for _, n in ipairs({ "WorldStateScoreFrameName", "WorldStateScoreFrameKills",
                             "WorldStateScoreFrameDeaths", "WorldStateScoreFrameHK",
                             "WorldStateScoreFrameDK", "WorldStateScoreFrameBonus" }) do
            local h = _G[n]
            if h then
                StripTextures(h)
                SkinButton(h)
            end
        end
        SkinAllScrollBarsUnder(score, 0)
    end

    -- The always-up strip (flag captures, node counts). Its background is
    -- a carved bar; a flat plate reads better over the world.
    if WorldStateAlwaysUpFrame then
        StripTextures(WorldStateAlwaysUpFrame)
    end

    for _, n in ipairs({ "PVPParentFrame", "PVPFrame", "PVPBattlegroundFrame",
                         "PVPHonorFrame", "BattlefieldFrame" }) do
        local f = _G[n]
        if f and not ZUI.skinned[f] then
            SkinPanel(f)
        end
    end
    for _, n in ipairs({ "PVPBattlegroundFrameJoinButton", "PVPBattlegroundFrameGroupJoinButton",
                         "BattlefieldFrameJoinButton", "BattlefieldFrameGroupJoinButton",
                         "BattlefieldFrameCancelButton" }) do
        local b = _G[n]
        if b then SkinButton(b) end
    end
    SkinBottomTabs("PVPParentFrameTab", 4)

    -- The pop-up that asks whether you are entering the battleground.
    if PVPReadyDialog and not ZUI.skinned[PVPReadyDialog] then
        ZUI.skinned[PVPReadyDialog] = true
        StripTextures(PVPReadyDialog)
        StripFrameChrome(PVPReadyDialog)
        SkinBackdrop(PVPReadyDialog, "windowBg", 0.97)
        for _, key in ipairs({ "enterButton", "leaveButton" }) do
            if PVPReadyDialog[key] then SkinButton(PVPReadyDialog[key]) end
        end
        if PVPReadyDialogEnterBattleButton then SkinButton(PVPReadyDialogEnterBattleButton) end
        if PVPReadyDialogLeaveQueueButton then SkinButton(PVPReadyDialogLeaveQueueButton) end
    end

    -- Honor / rank progress bars, where this build has them.
    for _, n in ipairs({ "PVPFrameHonorProgress", "PVPHonorFrameProgressBar" }) do
        local bar = _G[n]
        if bar then SkinStatusBar(bar) end
    end
end
