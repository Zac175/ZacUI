-- Blz_AddonList - the addon list window.
-- Part of ZacUI; load order is set by the TOC.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Modules = ns.Modules
local SkinAllScrollBarsUnder = ns.SkinAllScrollBarsUnder
local SkinButton = ns.SkinButton
local SkinDropdown = ns.SkinDropdown
local SkinEditBox = ns.SkinEditBox
local SkinPanel = ns.SkinPanel
local SkinScrollFrame = ns.SkinScrollFrame

Modules.addons = function()
    if not AddonList then return end
    SkinPanel(AddonList)
    -- Explicit appends (hole-in-ipairs law): legacy global OR keyed
    -- child, whichever this build has.
    local btns = {}
    local function AddBtn(b)
        if b then btns[#btns + 1] = b end
    end
    AddBtn(AddonListOkayButton or AddonList.OkayButton)
    AddBtn(AddonListCancelButton or AddonList.CancelButton)
    AddBtn(AddonListEnableAllButton or AddonList.EnableAllButton)
    AddBtn(AddonListDisableAllButton or AddonList.DisableAllButton)
    for _, b in ipairs(btns) do SkinButton(b) end
    if AddonCharacterDropDown then SkinDropdown(AddonCharacterDropDown) end
    if AddonList.SearchBox then SkinEditBox(AddonList.SearchBox) end
    SkinScrollFrame("AddonListScrollFrame")
    -- Pooled ScrollBox bars build lazily - sweep now and on every show.
    SkinAllScrollBarsUnder(AddonList, 0)
    AddonList:HookScript("OnShow", function(f)
        C_Timer.After(0, function() SkinAllScrollBarsUnder(f, 0) end)
    end)
end

-- GLOBAL SWEEP - the lean-ElvUI move: one EnumerateFrames pass at login
-- skins widgets by KIND instead of by name, catching every menu, option
-- and dialog ever, named or not:
--   * Sliders that are scrollbars (name/parent heuristic) -> media thumb
--   * Classic panel-signature Buttons (Left/Middle/Right art + label)
--   * ChatConfig checkboxes
-- Runs LAST so targeted modules win first. One bounded pass, login only.
