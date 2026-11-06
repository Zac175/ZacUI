-- Blz_Hooks - the hooks framework. Instead of hunting frames by name we
-- hook the machinery every widget passes through, so anything born at
-- any moment self-skins.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local ApplyFonts = ns.ApplyFonts
local Modules = ns.Modules
local SkinAnyScrollBar = ns.SkinAnyScrollBar
local SkinButton = ns.SkinButton
local SkinDropdown = ns.SkinDropdown
local StripTextures = ns.StripTextures
local ZUI = ns.ZUI

Modules.fonts = ApplyFonts

-- HOOKS FRAMEWORK - "every time the game calls this, skin it": instead of
-- hunting frames by name, hook the machinery every widget passes through.
-- Anything created at ANY time - load-on-demand, third-party, future
-- patches - self-skins the moment the game uses it. Each hook body is a
-- guarded table-lookup fast path (skinned frames early-return), safe on
-- hot paths.
Modules.hooks = function()
    -- Every classic-template scrollframe fires this whenever its content
    -- range changes (i.e. the first time it matters). Catches talent,
    -- chat config, and every scrollbar we never named.
    if type(ScrollFrame_OnScrollRangeChanged) == "function" then
        hooksecurefunc("ScrollFrame_OnScrollRangeChanged", function(sf)
            if not sf then return end
            local name = sf.GetName and sf:GetName()
            local bar = sf.ScrollBar or (name and _G[name .. "ScrollBar"])
            if bar then SkinAnyScrollBar(bar) end
        end)
    end

    -- Every Blizzard dropdown announces itself when opened.
    if type(ToggleDropDownMenu) == "function" then
        hooksecurefunc("ToggleDropDownMenu", function(_, _, dropDownFrame)
            if dropDownFrame and dropDownFrame.GetName and dropDownFrame:GetName() then
                SkinDropdown(dropDownFrame)
            end
        end)
    end

    -- Selected / deselected Blizzard tabs: green selected look instead
    -- of the stripped art (which left the selected tab indistinguishable).
    if type(PanelTemplates_SelectTab) == "function" and ns.PaintSelected then
        hooksecurefunc("PanelTemplates_SelectTab", function(tab)
            if tab and ZUI.skinned[tab] then ns.PaintSelected(tab, true) end
        end)
    end
    if type(PanelTemplates_DeselectTab) == "function" and ns.PaintSelected then
        hooksecurefunc("PanelTemplates_DeselectTab", function(tab)
            if tab and ZUI.skinned[tab] then ns.PaintSelected(tab, false) end
        end)
    end

    -- Every panel tab announces itself when Blizzard sizes it. Unskinned
    -- tabs get the look on the spot. NAMED "<Prefix>Tab<n>" tabs also get
    -- the tab geometry (label width + 3px gap): flat art at Blizzard's
    -- built-in -15/-16px overlap drew bordered tabs through each other.
    -- The AH strip is excluded - Blz_LoDPanels lays that one out itself.
    if type(PanelTemplates_TabResize) == "function" then
        hooksecurefunc("PanelTemplates_TabResize", function(tab)
            if tab and not ZUI.skinned[tab] and tab.GetObjectType
                and tab:GetObjectType() == "Button" then
                local tn = tab.GetName and tab:GetName()
                local prefix = tn and tn:match("^(.+Tab)%d+$")
                if prefix and prefix ~= "AuctionFrameTab" and ns.SkinBottomTabs then
                    local n = 0
                    for i = 1, 16 do
                        if _G[prefix .. i] then n = i end
                    end
                    ns.SkinBottomTabs(prefix, n)
                end
                if not ZUI.skinned[tab] then
                    StripTextures(tab)
                    SkinButton(tab)
                end
            end
        end)
    end
end

-- MINIMAP: square, bordered, decluttered, wheel zoom, zone strip, bare
-- day/clock text, mail top-left, friends/guild bar. Targeted removals
-- only - NO default-deny prune (v2.1's prune is the prime suspect for
-- the vanished zone title).
-- Shared by the minimap module and the TimeManager skin: hide-forever
-- for close buttons that only toggle from elsewhere (clock popouts,
-- stray minimap Xs). Names vary by build, so callers pass every variant.
