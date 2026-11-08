-- UIF_Widgets - compound widget skinners: recursive strippers, icon
-- cropping, both scrollbar generations, and the bottom-tab layout.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local HideNamed = ns.HideNamed
local SharpenIcon = ns.SharpenIcon
local SkinArrowButton = ns.SkinArrowButton
local SkinBackdrop = ns.SkinBackdrop
local SkinButton = ns.SkinButton
local StripTextures = ns.StripTextures
local TEX_THUMB = ns.TEX_THUMB
local ZUI = ns.ZUI
local Look = ns.Look

-- Recursively nil every texture REGION under a frame (bounded depth).
-- Callers use it BEFORE creating their own textures, on decor trees where
-- Blizzard hides art inside child frames a single-level strip can't reach.
local function StripDeep(root, depth)
    if not root or depth > 3 then return end
    StripTextures(root)
    if root.GetChildren then
        for _, child in ipairs({ root:GetChildren() }) do
            StripDeep(child, depth + 1)
        end
    end
end

-- Crop every keyed .Icon under a frame to the standard zoom and kill the
-- grey NormalTexture ring on its carrier. For pooled icon grids (macro
-- selector, icon picker) whose entries are unnamed and created per-open.
local function CropIconsUnder(root, depth)
    if not root or depth > 5 or not root.GetChildren then return end
    for _, child in ipairs({ root:GetChildren() }) do
        local icon = child.Icon or child.icon
        if icon and icon.SetTexCoord then
            ns.Look.CropIcon(icon, nil, nil, { border = false })
        end
        SharpenIcon(icon)
        -- Crop, NEVER kill: classic macro buttons render the icon itself
        -- through the NormalTexture - killing it deleted every icon on
        -- the macros page. Cropping trims the grey edge either way.
        if (icon or child.GetNormalTexture) and child.GetNormalTexture then
            local nt = child:GetNormalTexture()
            if nt and nt.GetTexture and nt:GetTexture() and nt.SetTexCoord then
                ns.Look.CropIcon(nt, nil, nil, { border = false })
                SharpenIcon(nt)
            end
        end
        CropIconsUnder(child, depth + 1)
    end
end

-- Modern keyed ScrollBar (retail-style template used by 1.15 LoD panels):
-- bar.Track.Thumb is a textured BUTTON, bar.Back/bar.Forward are atlas
-- arrow buttons, and there is no GetThumbTexture. The classic path did
-- literally nothing on these - the "still broken bars/thumbs/buttons".
local function SkinModernScrollBar(bar, look)
    if not bar or ZUI.skinned[bar] then return end
    ZUI.skinned[bar] = true
    -- Classic: Blizzard's own track, thumb and arrows stay
    if Look.Pick(look).scrollbar == "stock" then return end

    -- Kill ALL Blizzard art under the bar first (border strips, caps and
    -- arrow atlases hide in child frames key-guessing never reached).
    StripDeep(bar, 0)

    -- Thumb: keyed if present, else the first Button under the track.
    local track = bar.Track
    local thumb = (track and track.Thumb) or bar.Thumb
    if not thumb and track and track.GetChildren then
        for _, child in ipairs({ track:GetChildren() }) do
            if child.IsObjectType and child:IsObjectType("Button") then
                thumb = child
                break
            end
        end
    end
    if thumb then
        local t = thumb:CreateTexture(nil, "ARTWORK")
        t._zui_own = true
        t:SetAllPoints()
        t:SetTexture(TEX_THUMB)
        local a = Col("accent")
        t:SetVertexColor(a.r * 0.7, a.g * 0.7, a.b * 0.7, 0.9)
    end

    -- Arrows: keyed if present; otherwise any Button child of the bar
    -- (outside the track) is an arrow, oriented by which half it sits in.
    local up = bar.Back or bar.ScrollUpButton
    local down = bar.Forward or bar.ScrollDownButton
    if not (up and down) then
        local cy = (bar:GetTop() or 0) - ((bar:GetHeight() or 0) / 2)
        for _, child in ipairs({ bar:GetChildren() }) do
            if child ~= track and child.IsObjectType
                and child:IsObjectType("Button") and child ~= thumb then
                local ct = child:GetTop() or 0
                if ct >= cy and not up then
                    up = child
                elseif not down then
                    down = child
                end
            end
        end
    end
    if up then SkinArrowButton(up, "up") end
    if down then SkinArrowButton(down, "down") end
end

-- Skin any scrollbar OBJECT, no global name needed: classic slider bars
-- (thumb via GetThumbTexture, arrows found structurally) or modern keyed
-- bars. Deliberately touches ONLY the bar - never the scrollframe's
-- regions (the talent-tree lesson).
local function SkinAnyScrollBar(bar, look)
    if not bar or ZUI.skinned[bar] then return end
    if not bar.GetThumbTexture then
        SkinModernScrollBar(bar, look)
        return
    end
    ZUI.skinned[bar] = true
    -- Classic: Blizzard's own track, thumb and arrows stay
    if Look.Pick(look).scrollbar == "stock" then return end
    StripTextures(bar)
    local thumb = bar:GetThumbTexture()
    if thumb then
        thumb:SetTexture(TEX_THUMB)
        local a = Col("accent")
        thumb:SetVertexColor(a.r * 0.7, a.g * 0.7, a.b * 0.7, 0.9)
        thumb:SetWidth(8)
        -- The strip above Hide()s every region, the thumb included, and a
        -- hidden texture stays hidden whatever it is retextured with.
        thumb:SetAlpha(1)
        thumb:Show()
    end
    local cy = (bar:GetTop() or 0) - ((bar:GetHeight() or 0) / 2)
    for _, child in ipairs({ bar:GetChildren() }) do
        if child.IsObjectType and child:IsObjectType("Button") then
            local ct = child:GetTop() or 0
            SkinArrowButton(child, ct >= cy and "up" or "down")
        end
    end
end

-- stripOwn: also strip the scrollframe's OWN texture regions. Opt-in,
-- because the talent tree paints its background on the scrollframe itself;
-- the reputation / skill / trainer lists hang UNNAMED trough art there that
-- the named-cap hide can never reach.
local function SkinScrollFrame(scrollName, stripOwn)
    -- Thin wrapper: strip the classic named track caps that live on the
    -- SCROLLFRAME side, then route the bar - whichever generation - into
    -- the one bar skinner. (The old duplicated classic body is gone.)
    -- CAPS DIE FIRST, unconditionally: the hooks framework often skins
    -- the bar before this wrapper runs, and gating the cap hides behind
    -- "bar not yet skinned" left default track borders on exactly the
    -- frames the hooks reached first (talents).
    local sf = _G[scrollName]
    if sf and not sf._zui_capsHidden then
        sf._zui_capsHidden = true
        HideNamed(scrollName, { "Top", "Bottom", "Middle" })
        HideNamed(scrollName .. "ScrollBar", { "Top", "Bottom", "Middle", "Track" })
    end
    if sf and stripOwn and not sf._zui_ownStripped then
        sf._zui_ownStripped = true
        StripTextures(sf)
    end
    local bar = _G[scrollName .. "ScrollBar"] or (sf and sf.ScrollBar)
    if not bar or ZUI.skinned[bar] then return end
    SkinAnyScrollBar(bar)

    local track = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    track:SetPoint("TOPLEFT", 3, 0)
    track:SetPoint("BOTTOMRIGHT", -3, 0)
    track:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
    SkinBackdrop(track, "elementBg", 0.6)
end

-- Skin EVERY scrollbar under a root, both generations, any depth. Bars
-- are self-contained widgets - safe to reach even inside layered panels
-- whose content we otherwise never touch (SettingsPanel doctrine).
local function SkinAllScrollBarsUnder(root, depth)
    if not root or (depth or 0) > 5 or not root.GetChildren then return end
    for _, child in ipairs({ root:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "Slider"
            and child.GetThumbTexture then
            SkinAnyScrollBar(child)
        elseif child.ScrollBar then
            SkinAnyScrollBar(child.ScrollBar)
        end
        SkinAllScrollBarsUnder(child, (depth or 0) + 1)
    end
end

-- Shared: find a scrollbar of either generation anywhere under a frame.
local function FindScrollBarUnder(root, depth)
    if not root or (depth or 0) > 4 or not root.GetChildren then return nil end
    for _, child in ipairs({ root:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "Slider"
            and child.GetThumbTexture then
            return child
        end
        if child.ScrollBar then return child.ScrollBar end
        local found = FindScrollBarUnder(child, (depth or 0) + 1)
        if found then return found end
    end
    return nil
end

-- BOTTOM TABS, attempt #6 - the complete picture, learned the hard way:
-- Blizzard's classic tabs are HUGE by design (TabResize pads ~60px for
-- side-wing art) and OVERLAP by design (XML anchors carry negative X so
-- the wings interleave). Strip the art and both defects become visible.
-- Every prior fix replaced Blizzard's topology and lost a race somewhere;
-- the correct recipe KEEPS the topology and adjusts exactly two numbers:
--   width  -> label + 28, at least 64 (measured one frame after show, when strings
--             are measurable)
--   gap    -> rewrite each tab's EXISTING first point with x = +3,
--             same point, same relative frame, same everything else
-- A TabResize post-hook pins widths so Blizzard can't re-pad them.
-- ONE RECORD PER PREFIX. The hooks and the classifier now route tabs here
-- too, so a prefix can arrive more than once (and with more tabs the second
-- time - Auctionator appends). Re-entry rebuilds the list and re-lays it
-- out, but never re-strips a skinned tab (that erased SkinButton's own fill)
-- and never stacks a second OnShow hook.
ZUI._tabSets = ZUI._tabSets or {}
-- Height of a skinned Blizzard tab. 22 read as a row of tiny buttons;
-- 26 matches ZacUI's own in-window tabs.
local TAB_H_SKIN = 26
local function SkinBottomTabs(prefix, count)
    local set = ZUI._tabSets[prefix]
    if not set then
        set = { count = 0 }
        ZUI._tabSets[prefix] = set
    end
    if count > set.count then set.count = count end

    local tabs, inSet = {}, {}
    for i = 1, set.count do
        local tab = _G[prefix .. i]
        if tab then
            if not ZUI.skinned[tab] then
                StripTextures(tab)
                SkinButton(tab)
            end
            tabs[#tabs + 1] = tab
            inSet[tab] = true
        end
    end
    if #tabs == 0 then return end

    -- Gap rewrite only for tabs chained to a SIBLING tab: a tab anchored
    -- to the frame keeps its point (the AH lesson). RIGHT-side chains get
    -- the 3px gap; a LEFT-to-LEFT chain is Blizzard standing a tab in for a
    -- hidden sibling (the pet tab) and must stay flush.
    local function Adjust()
        for idx, tab in ipairs(tabs) do
            local fs = tab.GetFontString and tab:GetFontString()
            local tw = fs and fs:GetStringWidth() or 0
            if tw > 1 then
                tab._zui_w = math.max(64, math.floor(tw + 28))
                tab:SetSize(tab._zui_w, TAB_H_SKIN)
            end
            -- Selected look for whichever tab is current when the row is
            -- laid out (the Select/Deselect hooks keep it right after).
            local parent = tab:GetParent()
            local num = tonumber(((tab.GetName and tab:GetName()) or ""):match("(%d+)$"))
            if ns.PaintSelected and parent and parent.selectedTab and num then
                ns.PaintSelected(tab, parent.selectedTab == num)
            end
            if idx > 1 then
                local pt, rel, rp, _, y = tab:GetPoint(1)
                if pt and rel and inSet[rel] then
                    local gap = (rp and rp:find("RIGHT")) and 3 or 0
                    tab:SetPoint(pt, rel, rp, gap, y)
                end
            end
        end
    end
    set.Adjust = Adjust

    local host = tabs[1]:GetParent()
    if host then
        if not set.hooked then
            set.hooked = true
            host:HookScript("OnShow", function()
                C_Timer.After(0, function() if set.Adjust then set.Adjust() end end)
            end)
        end
        if host:IsVisible() then
            C_Timer.After(0, Adjust)
        end
    end

    -- PetTab_Update re-anchors CharacterFrameTab3 at Blizzard's -16 overlap
    -- on every pet summon/dismiss, long after the OnShow layout ran.
    if prefix == "CharacterFrameTab" and not ZUI._petTabHooked
        and type(PetTab_Update) == "function" then
        ZUI._petTabHooked = true
        hooksecurefunc("PetTab_Update", function()
            C_Timer.After(0, function() if set.Adjust then set.Adjust() end end)
        end)
    end

    if not ZUI._tabPinHooked and type(PanelTemplates_TabResize) == "function" then
        ZUI._tabPinHooked = true
        hooksecurefunc("PanelTemplates_TabResize", function(tab)
            if tab and ZUI.skinned[tab] and tab._zui_w then
                tab:SetSize(tab._zui_w, TAB_H_SKIN)
            end
        end)
        if type(PanelTemplates_UpdateTabs) == "function" then
            hooksecurefunc("PanelTemplates_UpdateTabs", function(frame)
                if not (frame and frame.numTabs and frame.GetName and frame:GetName()) then return end
                for i = 1, frame.numTabs do
                    local tab = _G[frame:GetName() .. "Tab" .. i]
                    if tab and ZUI.skinned[tab] and tab._zui_w then
                        tab:SetSize(tab._zui_w, TAB_H_SKIN)
                    end
                end
            end)
        end
    end
end


-- shared with later ZacUI files
ns.CropIconsUnder = CropIconsUnder
ns.FindScrollBarUnder = FindScrollBarUnder
ns.SkinAllScrollBarsUnder = SkinAllScrollBarsUnder
ns.SkinAnyScrollBar = SkinAnyScrollBar
ns.SkinModernScrollBar = SkinModernScrollBar
ns.SkinScrollFrame = SkinScrollFrame
ns.StripDeep = StripDeep
ns.SkinBottomTabs = SkinBottomTabs
