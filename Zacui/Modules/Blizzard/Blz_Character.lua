-- Blz_Character - character sheet, inspect window and spellbook.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local ForEachNamed = ns.ForEachNamed
local HideRegions = ns.HideRegions
local Modules = ns.Modules
local RegisterLoD = ns.RegisterLoD
local SkinArrowButton = ns.SkinArrowButton
local SkinBackdrop = ns.SkinBackdrop
local SkinIconButton = ns.SkinIconButton
local SkinPanel = ns.SkinPanel
local SkinScrollFrame = ns.SkinScrollFrame
local SkinStatusBar = ns.SkinStatusBar
local StripTextures = ns.StripTextures
local ZUI = ns.ZUI
local Col = ns.Col

-- ============================================================
-- WOW FOREVER'S CHARACTER SHEET, FINISHED IN PLACE (2026-11-16)
-- ============================================================
-- Zac on his Forever client, ZacUI's style, the game's own sheet restyled
-- in place: "inspect and character pane both look half assed". What was
-- still the game's, piece by piece (Blizzard_UIPanels_Game/Camelot/
-- CharacterFrame.xml, PaperDollFrame.xml), and what the reference UI does
-- with each on this sheet:
--   the rock strip under the level line   a plain file: named here, faded
--   the class emblem behind the stats     set from Lua: named here, faded
--   the ring round the three small tabs   Blz_Sweep's rule; each tab gets
--     over the stats                      ZacUI's box, its icon cropped,
--                                         the picked one an accent wash
--   the yellow arrow that folds the       ZacUI's arrow, turned the way the
--     stats pane away                     pane will go
--   empty gear slots drawn as bare        a dark square behind each, like
--     outlines over the scene             every ZacUI slot
-- The scene behind the model and its dark veil stay the game's.
-- Region and widget calls on the game's own pieces only; what was done is
-- kept in weak tables; nothing is hidden, moved or re-parented.
local slotBacked = setmetatable({}, { __mode = "k" })
function ns.ForeverSlotBack(b)
    if type(b) ~= "table" or slotBacked[b] or not b.CreateTexture then return end
    slotBacked[b] = true
    local t = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    t._zui_own = true
    t:SetAllPoints(b)
    local c = Col("elementBg")
    t:SetColorTexture(c.r, c.g, c.b, 0.9)
end
ns.FOREVER_SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
                     "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand",
                     "Ranged", "Ammo" }

-- THE ITEM LEVEL ON EACH GEAR SLOT (ZacUI's own sheet shows it on the other
-- clients; on Forever that sheet stands down, so the game's slots carry it):
-- a small number in the slot's corner, in the item's quality colour; no
-- item, no number. Read when the sheet shows, when gear changes and when an
-- inspect arrives - never on a timer.
local levelText = setmetatable({}, { __mode = "k" })
local function SlotLevel(slot, unit)
    if type(slot) ~= "table" or not slot.GetID then return end
    local fs = levelText[slot]
    local id = slot:GetID()
    local link = (type(id) == "number" and GetInventoryItemLink) and GetInventoryItemLink(unit, id) or nil
    local lvl
    if type(link) == "string" then
        local get = (C_Item and C_Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo
        if type(get) == "function" then
            local ok, v = pcall(get, link)
            if ok and type(v) == "number" and not (issecretvalue and issecretvalue(v)) then lvl = v end
        end
    end
    if not lvl or lvl < 1 then
        if fs then fs:SetText("") end
        return
    end
    if not fs then
        fs = slot:CreateFontString(nil, "OVERLAY")
        fs._zui_own = true
        fs:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
        local path = (ns.Media and ns.Media.FontPath and ns.Media.FontPath()) or STANDARD_TEXT_FONT
        if not pcall(fs.SetFont, fs, path, 11, "OUTLINE") then fs:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE") end
        levelText[slot] = fs
    end
    local r, g, b = 1, 1, 1
    local q = GetInventoryItemQuality and GetInventoryItemQuality(unit, id)
    local qc = type(q) == "number" and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if qc then r, g, b = qc.r, qc.g, qc.b end
    fs:SetTextColor(r, g, b, 1)
    fs:SetText(tostring(math.floor(lvl + 0.5)))
end
function ns.ForeverSlotLevels(prefix, unit)
    if type(unit) ~= "string" then return end
    for _, slot in ipairs(ns.FOREVER_SLOTS) do
        pcall(SlotLevel, _G[prefix .. slot .. "Slot"], unit)
    end
end
local function InspectUnitNow()
    local f = _G.InspectFrame
    local u = type(f) == "table" and rawget(f, "unit")
    return type(u) == "string" and u or "target"
end
local levelWatch
local function WatchLevels()
    if levelWatch then return end
    levelWatch = CreateFrame("Frame")
    levelWatch:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    pcall(levelWatch.RegisterEvent, levelWatch, "INSPECT_READY")
    levelWatch:SetScript("OnEvent", function(_, event)
        if event == "INSPECT_READY" then
            if _G.InspectFrame and _G.InspectFrame:IsShown() then
                ns.ForeverSlotLevels("Inspect", InspectUnitNow())
                -- (an item the client had not cached yet: once more, shortly)
                C_Timer.After(0.6, function()
                    if _G.InspectFrame and _G.InspectFrame:IsShown() then ns.ForeverSlotLevels("Inspect", InspectUnitNow()) end
                end)
            end
        elseif CharacterFrame and CharacterFrame:IsShown() then
            ns.ForeverSlotLevels("Character", "player")
        end
    end)
    if PaperDollFrame and PaperDollFrame.HookScript then
        PaperDollFrame:HookScript("OnShow", function() ns.ForeverSlotLevels("Character", "player") end)
    end
end
ns.ForeverWatchLevels = WatchLevels

local sheetDone = false
function ns.ForeverSheet()
    local S = ns.Sweep
    if not (S and S.Gone and CharacterFrame) then return end
    -- the rock strip and its lower edge
    local host = PaperDollFrame and rawget(PaperDollFrame, "TopBackgroundStripHost")
    if type(host) == "table" then
        S.Gone(rawget(host, "TopBackgroundStrip"))
        S.Gone(rawget(host, "TopBackgroundStripBottomEdge"))
    end
    -- the class emblem behind the stats list
    local box = _G.CharacterStatsPaneScrollBox
    if type(box) == "table" then S.Gone(rawget(box, "ClassBackground")) end
    if sheetDone then return end
    sheetDone = true
    WatchLevels()
    ns.ForeverSlotLevels("Character", "player")
    -- the three small tabs over the stats
    local tabs = _G.PaperDollSidebarTabs
    if type(tabs) == "table" then
        S.Page(tabs, { depth = 2, bars = false })
        local a = Col("accent")
        for i = 1, 4 do
            local tab = _G["PaperDollSidebarTab" .. i]
            if type(tab) == "table" and not ZUI.skinned[tab] then
                ZUI.skinned[tab] = true
                SkinBackdrop(tab, "elementBg", 0.95)
                -- (its icon is a piece of an art sheet, set by name: never
                -- cropped - a crop there cut the picture to a sliver)
                local ck = tab.GetCheckedTexture and tab:GetCheckedTexture()
                if type(ck) == "table" and ck.SetColorTexture then
                    ck:SetColorTexture(a.r, a.g, a.b, 0.28)
                    ck:ClearAllPoints()
                    ck:SetAllPoints(tab)
                end
            end
        end
    end
    -- the equipment manager: each gear slot's pull-out arrow (yellow tabs
    -- beside the slots while the manager is open - Zac: "the equipment
    -- manager on zui style uses default arrows"), and its New Set button
    for _, slot in ipairs(ns.FOREVER_SLOTS) do
        local sb = _G["Character" .. slot .. "Slot"]
        local pb = type(sb) == "table" and rawget(sb, "popoutButton")
        if type(pb) == "table" and ns.SkinArrowButton and not ZUI.skinned[pb] then
            local dir = rawget(sb, "flyoutDirection") or (rawget(sb, "verticalFlyout") and "UP") or "RIGHT"
            ns.SkinArrowButton(pb, string.lower(tostring(dir)))
            -- (the game hands the button its own pictures again on every
            -- hover and click: kept away)
            for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
                S.Gone(pb[get] and pb[get](pb))
            end
        end
    end
    local pane = PaperDollFrame and rawget(PaperDollFrame, "EquipmentManagerPane")
    local new = type(pane) == "table" and rawget(pane, "NewSet")
    if type(new) == "table" and not ZUI.skinned[new] then
        ZUI.skinned[new] = true
        S.Gone(rawget(new, "StateTexture"))
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
            S.Gone(new[get] and new[get](new))
        end
        SkinBackdrop(new, "buttonBg", 0.95)
    end
    -- the arrow that folds the stats pane away
    local btn = rawget(CharacterFrame, "RightPaneToggleButton")
    if type(btn) == "table" and ns.SkinArrowButton then
        ns.SkinArrowButton(btn, "left")
        local function Turn()
            local ar = btn._zui_arrow
            if not (ar and ar.SetTexCoord) then return end
            local folded = CharacterFrame.IsRightPaneCollapsed and CharacterFrame:IsRightPaneCollapsed()
            if folded then ar:SetTexCoord(1, 0, 0, 1) else ar:SetTexCoord(0, 1, 0, 1) end
            -- (the game hands the button its own arrow picture again each time)
            for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture" }) do
                local t = btn[get] and btn[get](btn)
                if t and t.SetAlpha then t:SetAlpha(0) end
            end
        end
        if type(CharacterFrame.UpdateRightPaneToggleButton) == "function" then
            hooksecurefunc(CharacterFrame, "UpdateRightPaneToggleButton", Turn)
        end
        Turn()
    end
end

Modules.character = function()
    SkinPanel(CharacterFrame, { tabs = "CharacterFrameTab", tabCount = 5 })
    -- Forever: side tabs of the modern shape down the window's edge get the
    -- same flat look as the social window's (Blz_Windows SkinSideTab)
    if _G.ZACUI_IS_FOREVER and CharacterFrame and ns.SkinSideTab then
        for _, child in ipairs({ CharacterFrame:GetChildren() }) do
            if child.SelectedTexture and child.Icon and child.Background then ns.SkinSideTab(child) end
        end
        -- (2026-11-15, Zac's Forever sheet: the six mode tabs down its side
        -- still the game's gold rings. They are not the window's children
        -- but its tab holder's - CharacterFrame.ModeTabs - so the walk above
        -- never met them.)
        local holder = rawget(CharacterFrame, "ModeTabs") or _G.CharacterFrameModeTabs
        if type(holder) == "table" and holder.GetChildren then
            for _, tab in ipairs({ holder:GetChildren() }) do
                if type(rawget(tab, "SelectedTexture")) == "table" and type(rawget(tab, "Icon")) == "table"
                    and type(rawget(tab, "Background")) == "table" then
                    ns.SkinSideTab(tab)
                end
            end
        end
    end
    -- Forever's Currency page (Blizzard_TokenUI/Camelot: a ScrollBox of
    -- pooled rows): each row flat as it is handed out - the header's bar
    -- picture goes for a flat backing (its +/- state icon stays), an
    -- entry's hover and selected pictures become flat washes; the
    -- currency icon, name, count and watched check are left as they are.
    local tf = _G.TokenFrame
    local box = tf and rawget(tf, "ScrollBox")
    if _G.ZACUI_MODERN and type(box) == "table" and ScrollUtil and ScrollUtil.AddInitializedFrameCallback
        and not tf._zTokenRows then
        tf._zTokenRows = true
        -- (the callback comes as (owner, row, data) on a new row and as
        -- (row, data) over the existing ones)
        local function SkinRow(a, b)
            local row = (type(b) == "table" and b.GetRegions) and b or a
            if type(row) ~= "table" or not row.GetRegions or row._zTokenSkin then return end
            row._zTokenSkin = true
            local bh = rawget(row, "BackgroundHighlight")
            if type(bh) == "table" and bh.TextureRegions then
                for _, t in ipairs(bh.TextureRegions) do t:SetColorTexture(1, 1, 1, 0.08) end
            elseif rawget(row, "Name") and rawget(row, "StateIcon") then
                -- a header: its bar pictures are the row's own plain regions
                for _, r in ipairs({ row:GetRegions() }) do
                    if r.IsObjectType and r:IsObjectType("Texture") and r ~= row.StateIcon then r:SetAlpha(0) end
                end
                SkinBackdrop(row, "elementBg", 0.9)
            end
        end
        ScrollUtil.AddInitializedFrameCallback(box, SkinRow, tf, true)
    end
    -- WoW FOREVER'S CHARACTER PAGES, IN PLACE (2026-11-15, Zac on ZacUI's
    -- look: "none of this is styled" - Statistics, Currency, PvP, Skills).
    -- They are the modern client's own pages, built from shared pieces: the
    -- two pane backgrounds on the window, a list of headers and rows, a side
    -- pane with a title and a divider. Blz_Sweep's rules take those pieces
    -- wherever they are used, so the pages are only named here; their lists'
    -- rows are taken as the lists hand them out. The paperdoll and reputation
    -- pages wear ZacUI's own pages (Zacui_Windows) and are not swept: a
    -- cover is skipped with everything under it.
    if _G.ZACUI_IS_FOREVER and CharacterFrame and ns.Sweep then
        local S = ns.Sweep
        -- the window's two pane hosts carry the page backgrounds
        for _, key in ipairs({ "LeftPaneHost", "RightPaneHost" }) do
            local host = rawget(CharacterFrame, key) or _G["CharacterFrame" .. key]
            if type(host) == "table" then S.Page(host, { depth = 1, bars = false }) end
        end
        -- (2026-11-15, later that night: ZacUI's own character sheet stands
        -- down on Forever - Core_Flavor win_character - so the game's sheet,
        -- its stats panes (the pet's is one of them: Forever has no pet
        -- page of its own) and the reputation page are swept like the rest.
        -- The rock strip over the model is the sheet's own decoration: a
        -- rule of this page's, not everyone's.)
        local RULES = { { "ui-background-rock", "gone" }, { "_ui-frame-innertoptile", "gone" } }
        local PAGES = { "PaperDollFrame", "ReputationFrame", "SkillsFrame", "StatisticsFrame",
                        "TokenFrame", "PVPRankFrame", "CharacterStatsPane", "CharacterStatsPaneScrollBox",
                        "CharacterStatsPanePetScrollBox" }
        S.Pages(PAGES, { rules = RULES })
        -- (the statistics and currency pages come with their own addons)
        if not ZUI._charPagesWatch then
            ZUI._charPagesWatch = true
            local watch = CreateFrame("Frame")
            watch:RegisterEvent("ADDON_LOADED")
            watch:SetScript("OnEvent", function() S.Pages(PAGES, { rules = RULES }) end)
        end
    end
    if PaperDollFrame then StripTextures(PaperDollFrame) end
    if _G.ZACUI_IS_FOREVER and ns.ForeverSheet then pcall(ns.ForeverSheet) end

    local slots = {
        "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard",
        "Wrist", "Hands", "Waist", "Legs", "Feet",
        "Finger0", "Finger1", "Trinket0", "Trinket1",
        "MainHand", "SecondaryHand", "Ranged", "Ammo",
    }
    for _, slot in ipairs(slots) do
        local b = _G["Character" .. slot .. "Slot"]
        if b then
            SkinIconButton(b)
            if _G.ZACUI_IS_FOREVER and ns.ForeverSlotBack then ns.ForeverSlotBack(b) end
        end
    end

    if CharacterAttributesFrame then StripTextures(CharacterAttributesFrame) end
    for i = 1, 7 do
        local statRow = _G["CharacterStatFrame" .. i]
        if statRow then StripTextures(statRow) end
    end
    if ReputationFrame then StripTextures(ReputationFrame) end
    if SkillFrame then StripTextures(SkillFrame) end
    -- true: both lists hang UNNAMED scrollbar-trough art on the scrollframe
    SkinScrollFrame("ReputationListScrollFrame", true)
    SkinScrollFrame("SkillListScrollFrame", true)
    SkinScrollFrame("SkillDetailScrollFrame", true)
    if PetPaperDollFrame then StripTextures(PetPaperDollFrame) end

    -- HONOR TAB: its own eight quadrant textures were never stripped - the
    -- whole page stayed Blizzard art. The rank icon is a region on the same
    -- frame, so it is spared by name rather than swept with the rest.
    if HonorFrame then
        for _, region in ipairs({ HonorFrame:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture")
                and region ~= HonorFramePvPIcon then
                region:SetTexture(nil)
                region:Hide()
            end
        end
    end
    if HonorFrameProgressBar then SkinStatusBar(HonorFrameProgressBar) end

    -- REPUTATION rows: the carved bar frame is two named textures per row.
    -- Standing colour and the watched check are information and stay.
    ForEachNamed("ReputationBar", 1, 15, function(bar, _, name)
        HideRegions(name, { "ReputationBarLeft", "ReputationBarRight" })
        SkinStatusBar(bar, { backdrop = false })
    end)
    if ReputationDetailFrame and not ZUI.skinned[ReputationDetailFrame] then
        ZUI.skinned[ReputationDetailFrame] = true
        StripTextures(ReputationDetailFrame)
        SkinBackdrop(ReputationDetailFrame, "windowBg", 0.97)
    end

    -- SKILLS: only the bar BORDER is chrome. Background and FillBar carry
    -- Blizzard's per-skill colour coding, so no backdrop replaces them.
    ForEachNamed("SkillRankFrame", 1, 12, function(bar, _, name)
        HideRegions(name, { "BorderNormal" })
        SkinStatusBar(bar, { backdrop = false })
    end)
    if SkillDetailStatusBar then
        HideRegions("SkillDetailStatusBar", { "Border" })
        SkinStatusBar(SkillDetailStatusBar, { backdrop = false })
    end
    if SkillFrameExpandButtonFrame then StripTextures(SkillFrameExpandButtonFrame) end
end

-- INSPECT (right-click -> Inspect) - lives in Blizzard_InspectUI, a
-- LOAD-ON-DEMAND addon: the frame does not exist until the first
-- inspect of the session, so no login pass can ever see it - the same
-- timing class as the TimeManager clock. Routed through RegisterLoD;
-- runs immediately when the addon is already loaded. Mirrors the
-- character recipe: same frame family, Inspect-prefixed names.
Modules.inspect = function()
    local function SkinInspect()
        local f = InspectFrame
        if not f or ZUI.skinned[f] then return end
        -- (2026-11-16 07:21, Zac's WoW Forever inspect window: the line
        -- under the title "need[s] to be placed better" - it ran through
        -- the level line. The game writes the level 40 down from the top
        -- of this window and the skin's title bar ended at 46. On WoW
        -- Forever the bar is as tall as the character window's title bar
        -- (30: UIF_Panels' PANEL_LINES), so its foot is over the words,
        -- which sit in the row between it and the gear, as on the
        -- character window.)
        SkinPanel(f, { tabs = "InspectFrameTab", tabCount = 3 })
        if InspectPaperDollFrame then StripTextures(InspectPaperDollFrame) end
        local slots = {
            "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard",
            "Wrist", "Hands", "Waist", "Legs", "Feet",
            "Finger0", "Finger1", "Trinket0", "Trinket1",
            "MainHand", "SecondaryHand", "Ranged", "Ammo",
        }
        for _, slot in ipairs(slots) do
            local b = _G["Inspect" .. slot .. "Slot"]
            if b then
                SkinIconButton(b)
                if _G.ZACUI_IS_FOREVER and ns.ForeverSlotBack then ns.ForeverSlotBack(b) end
            end
        end
        if InspectHonorFrame then StripTextures(InspectHonorFrame) end
        -- WoW Forever's inspect window, in place (2026-11-15: ZacUI's own
        -- stands down there - Core_Flavor win_inspect): its gear slots'
        -- rings, the model's inner frame and its pages by Blz_Sweep's
        -- rules, its side tabs flat like the character window's.
        if _G.ZACUI_IS_FOREVER and ns.Sweep then
            ns.Sweep.Page(f, { depth = 8 })
            -- (the model's carved frame: plain files, named here as well as
            -- ruled - Blizzard_InspectUI/Camelot/InspectPaperDollFrame.xml)
            if ns.Sweep.Gone then
                for _, side in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Left", "Right",
                                        "Top", "Bottom", "Bottom2" }) do
                    ns.Sweep.Gone(_G["InspectModelFrameBorder" .. side])
                end
            end
            -- (the title rule used to run through the level line and was
            -- hidden here; the title bar now ends over the words - see
            -- SkinPanel's lineY above - so its rule is drawn like any
            -- other window's)
            -- (each slot's item level, as on the character sheet)
            if ns.ForeverWatchLevels then
                ns.ForeverWatchLevels()
                if InspectPaperDollFrame and InspectPaperDollFrame.HookScript then
                    InspectPaperDollFrame:HookScript("OnShow", function()
                        local u = rawget(f, "unit")
                        ns.ForeverSlotLevels("Inspect", type(u) == "string" and u or "target")
                    end)
                end
            end
            local holder = rawget(f, "ModeTabs") or _G.InspectUITabs
            if type(holder) == "table" and holder.GetChildren and ns.SkinSideTab then
                for _, tab in ipairs({ holder:GetChildren() }) do
                    if type(rawget(tab, "SelectedTexture")) == "table" and type(rawget(tab, "Icon")) == "table"
                        and type(rawget(tab, "Background")) == "table" then
                        ns.SkinSideTab(tab)
                    end
                end
            end
        end
        -- Inspect talent tab: the tree background is CONTENT ART on
        -- this frame family (the class the taxi doctrine exists for).
        -- The classifier already covers its generic widgets; the
        -- container stays untouched rather than risking the tree.
    end
    RegisterLoD("Blizzard_InspectUI", SkinInspect)
    -- BELT + SUSPENDERS (the "inspect was never styled" fix): if the
    -- ADDON_LOADED listener is ever missed - the LoD addon can arrive
    -- preloaded, or load off a code path that beats our registration -
    -- the InspectUnit hook catches the first actual inspect and skins
    -- one frame later, when the window exists. SkinInspect is fenced-
    -- idempotent, so double coverage costs nothing.
    if type(InspectUnit) == "function" then
        hooksecurefunc("InspectUnit", function()
            C_Timer.After(0, SkinInspect)
        end)
    end
    -- OnShow catch as the third net: covers inspects opened through
    -- paths that bypass the global InspectUnit (addons, unit popups).
    if InspectFrame then
        SkinInspect()
    end
end

-- SPELLBOOK
Modules.spellbook = function()
    SkinPanel(SpellBookFrame, { tabs = "SpellBookFrameTabButton", tabCount = 3 })
    if SpellBookPrevPageButton then SkinArrowButton(SpellBookPrevPageButton, "left") end
    if SpellBookNextPageButton then SkinArrowButton(SpellBookNextPageButton, "right") end
    for i = 1, 8 do
        local tab = _G["SpellBookSkillLineTab" .. i]
        if tab then SkinIconButton(tab, true) end
    end
end

-- QUEST LOG
