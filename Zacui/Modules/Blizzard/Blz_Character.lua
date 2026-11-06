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

Modules.character = function()
    SkinPanel(CharacterFrame, { tabs = "CharacterFrameTab", tabCount = 5 })
    if PaperDollFrame then StripTextures(PaperDollFrame) end

    local slots = {
        "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard",
        "Wrist", "Hands", "Waist", "Legs", "Feet",
        "Finger0", "Finger1", "Trinket0", "Trinket1",
        "MainHand", "SecondaryHand", "Ranged", "Ammo",
    }
    for _, slot in ipairs(slots) do
        local b = _G["Character" .. slot .. "Slot"]
        if b then SkinIconButton(b) end
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
            if b then SkinIconButton(b) end
        end
        if InspectHonorFrame then StripTextures(InspectHonorFrame) end
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
