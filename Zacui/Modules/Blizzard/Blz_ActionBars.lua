-- Blz_ActionBars - action buttons, pet and stance bars, the main bar art,
-- the micro menu and the bag strip.
-- Part of ZacUI; load order is set by the TOC.
--
-- SCOPE, deliberately narrow: this module makes buttons look like ZacUI
-- buttons and deletes the gryphon-and-brass frame around them. It does
-- NOT move, resize, restack or re-page anything. Every one of those is a
-- protected write, and on 11509 the bar layout belongs to Edit Mode
-- (doctrine 8). A skin that also tries to be a bar mod is how you get
-- "ADDON_ACTION_BLOCKED" in the middle of a fight.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local ForEachNamed = ns.ForEachNamed
local HideRegions = ns.HideRegions
local Modules = ns.Modules
local SkinSecureIcon = ns.SkinSecureIcon
local SkinStatusBar = ns.SkinStatusBar
local StyleButtonText = ns.StyleButtonText
local InCombat = ns.InCombat
local TintBorder = ns.TintBorder
local ZUI = ns.ZUI

-- The bar families this client ships. Named explicitly rather than
-- discovered: a loop over _G looking for "Button%d" also finds every
-- other addon's buttons, and skinning those without being asked is rude.
-- Era ships four extra bars, a pet bar and a stance bar. MultiBar5-7,
-- PossessButton and OverrideActionBarButton are Dragonflight/vehicle
-- families that do not exist on this client - listing them only made the
-- module look like it covered ground it does not.
-- ShapeshiftButton and StanceButton are the same row under two names
-- across builds; both are probed and whichever exists is skinned.
local BUTTON_BARS = {
    { "ActionButton",             1, 12 },
    { "MultiBarBottomLeftButton", 1, 12 },
    { "MultiBarBottomRightButton",1, 12 },
    { "MultiBarLeftButton",       1, 12 },
    { "MultiBarRightButton",      1, 12 },
    { "PetActionButton",          1, 10 },
    { "ShapeshiftButton",         1, 10 },
    { "StanceButton",             1, 10 },
}

-- Main bar chrome. Every entry is a TEXTURE, not a frame - see the secure
-- contract in UIF_Bars. Killing textures is safe in combat; hiding the
-- frames that own them is not.
local BAR_ART = {
    "MainMenuBarTexture0", "MainMenuBarTexture1",
    "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
    "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1",
    "MainMenuMaxLevelBar2", "MainMenuMaxLevelBar3",
    "MainMenuXPBarTextureLeftCap", "MainMenuXPBarTextureRightCap",
    "MainMenuXPBarTextureMid",
    "ReputationWatchBarTexture0", "ReputationWatchBarTexture1",
    "ReputationWatchBarTexture2", "ReputationWatchBarTexture3",
    "ReputationXPBarTexture0", "ReputationXPBarTexture1",
    "ReputationXPBarTexture2", "ReputationXPBarTexture3",
    "SlidingActionBarTexture0", "SlidingActionBarTexture1",
    "StanceBarLeft", "StanceBarMiddle", "StanceBarRight",
    "PetActionBarFrameBackground",
    "ActionBarUpButtonNormalTexture", "ActionBarDownButtonNormalTexture",
}

-- EQUIPPED-ITEM CUE, rebuilt. Blizzard shows it by vertex-colouring the
-- slot ring, which the skin removes - so the cue moves onto our border
-- instead of being lost. Driven by events rather than an OnUpdate, and
-- never during combat: it only ever writes to textures we created, but
-- allocating and painting on a protected frame mid-fight is the exact
-- thing this module promises not to do.
local EQUIPPED = { r = 0.35, g = 0.65, b = 1.0 }
local function RefreshEquipped()
    if InCombat() then return end
    for _, bar in ipairs(BUTTON_BARS) do
        ForEachNamed(bar[1], bar[2], bar[3], function(btn)
            if not btn._zui_borderTex then return end
            local slot = btn.action or (btn.GetAttribute and btn:GetAttribute("action"))
            if slot and IsEquippedAction and IsEquippedAction(slot) then
                TintBorder(btn, EQUIPPED.r, EQUIPPED.g, EQUIPPED.b, 1)
            else
                TintBorder(btn)
            end
        end)
    end
end

-- UNDER A GAME LOOK (2026-11-08, Zac: "there is no blizzard art on action
-- bars"): Classic WoW UI, Blizzard style and WoW Forever draw the game's
-- own art, so Blizzard's own bars stay exactly as the game draws them -
-- the gryphons, the bar art, the button rings, the XP strip. Nothing runs:
-- no skin, no hook, nothing of Blizzard's touched (Core_Look's rule for
-- the game's own UI under a game look, decided once a session like every
-- look answer). ZacUI's own bars wear the look's kit (Zacui_Bars).
function ns.BlizzardBarsStock()
    local L = ns.Look
    return (L and L.Stock and L.Stock("bars")) and true or false
end

Modules.actionbars = function()
    if ns.BlizzardBarsStock() then return end

    -- BUTTONS -----------------------------------------------------------
    for _, bar in ipairs(BUTTON_BARS) do
        ForEachNamed(bar[1], bar[2], bar[3], function(btn, _, name)
            SkinSecureIcon(btn)
            StyleButtonText(name)
            -- The floating background is a separate frame-level texture on
            -- classic buttons and survives the region sweep. NormalTexture
            -- is already handled by SkinSecureIcon, which knows whether the
            -- caller asked to keep it - listing it here would override that.
            HideRegions(name, { "FloatingBG" })
            local cd = _G[name .. "Cooldown"]
            if cd and cd.SetDrawEdge then cd:SetDrawEdge(false) end
        end)
    end

    -- Pet buttons carry an extra auto-cast shine that sits proud of the
    -- icon once the ring is gone.
    ForEachNamed("PetActionButton", 1, 10, function(btn, i, name)
        -- The shine IS the autocast-enabled indicator, so it stays legible.
        local shine = _G[name .. "Shine"]
        if shine then shine:SetAlpha(0.8) end
        if btn.AutoCastable then btn.AutoCastable:SetAlpha(0.5) end
    end)

    -- BAR ART -----------------------------------------------------------
    for _, texName in ipairs(BAR_ART) do
        local t = _G[texName]
        if t and t.SetTexture then
            t:SetTexture(nil)
            t:SetAlpha(0)
        end
    end
    -- Keyed art on the newer bar containers, same treatment.
    for _, frameName in ipairs({ "MainMenuBar", "MainMenuBarArtFrame",
                                 "StatusTrackingBarManager", "StanceBarFrame",
                                 "PetActionBarFrame", "MultiBarBottomLeft",
                                 "MultiBarBottomRight" }) do
        local f = _G[frameName]
        if f and f.GetRegions then
            for _, region in ipairs({ f:GetRegions() }) do
                if region.IsObjectType and region:IsObjectType("Texture")
                    and not region._zui_own then
                    region:SetTexture(nil)
                    region:SetAlpha(0)
                end
            end
        end
    end

    -- XP AND REPUTATION -------------------------------------------------
    -- Kept, not hidden: they are information. Flattened to the palette so
    -- they read as one strip rather than two carved troughs.
    for _, barName in ipairs({ "MainMenuExpBar", "ReputationWatchStatusBar",
                               "MainMenuBarMaxLevelBar" }) do
        local bar = _G[barName]
        if bar then SkinStatusBar(bar, { bgAlpha = 0.9 }) end
    end
    if ExhaustionTick then
        -- The rested-XP tick keeps its own art; only its glow is dropped,
        -- because it renders as a bright smear over a flat bar.
        local normal = ExhaustionTick.GetNormalTexture and ExhaustionTick:GetNormalTexture()
        if normal then normal:SetAlpha(0.6) end
        -- Rested XP is information, not decoration. 0.35 on a flat dark
        -- bar made it unreadable; this is dimmed enough to sit behind the
        -- fill and still be countable.
        if ExhaustionLevelFillBar then ExhaustionLevelFillBar:SetAlpha(0.7) end
    end

    -- PAGE ARROWS AND PAGE NUMBER ---------------------------------------
    for _, n in ipairs({ "ActionBarUpButton", "ActionBarDownButton" }) do
        local b = _G[n]
        if b and not ZUI.skinned[b] then
            ns.SkinArrowButton(b, n:find("Up") and "up" or "down")
        end
    end
    if MainMenuBarPageNumber then
        local c = Col("text")
        MainMenuBarPageNumber:SetTextColor(c.r, c.g, c.b, 1)
    end

    -- BAG STRIP ---------------------------------------------------------
    -- keepNormal: on bag slots the NormalTexture IS the bag artwork.
    -- Killing it is the classic "my bags went invisible" bug.
    if MainMenuBarBackpackButton then
        SkinSecureIcon(MainMenuBarBackpackButton, { keepNormal = true })
    end
    -- The globals are CharacterBag0Slot..CharacterBag3Slot, NOT
    -- CharacterBag0..3 - the numbered helper cannot express a suffix, and
    -- with the wrong names the whole bag strip was silently never skinned.
    -- keepNormal is essential here and the NormalTexture must NOT then be
    -- hidden: on a bag slot that texture IS the bag artwork.
    for i = 0, 3 do
        local slot = _G["CharacterBag" .. i .. "Slot"]
        if slot then SkinSecureIcon(slot, { keepNormal = true }) end
    end
    -- The key ring's NormalTexture IS its icon (same trap as the bag
    -- slots): hiding it left an empty 1px border. Border only.
    if KeyRingButton and not KeyRingButton._zui_borderTex then
        ns.AddPixelBorder(KeyRingButton)
    end

    -- MICRO MENU --------------------------------------------------------
    -- Blizzard's micro buttons draw their icon THROUGH the normal texture
    -- on a shared sheet, with per-button texcoords. Cropping or replacing
    -- either one slides the sheet and shows the wrong glyph, so this is
    -- the one place the module only removes the surrounding art and
    -- leaves the button itself completely alone.
    for _, n in ipairs({ "CharacterMicroButton", "SpellbookMicroButton",
                         "TalentMicroButton", "QuestLogMicroButton",
                         "SocialsMicroButton", "WorldMapMicroButton",
                         "MainMenuMicroButton", "HelpMicroButton",
                         "LFGMicroButton", "GuildMicroButton",
                         "PVPMicroButton",
                         -- WoW Forever's (Blizzard_MicroMenu/Camelot); nil elsewhere
                         "ProfessionMicroButton", "LegacyMicroButton", "LFDMicroButton",
                         "CollectionsMicroButton", "EJMicroButton", "StoreMicroButton" }) do
        local b = _G[n]
        if b then
            HideRegions(n, { "Border", "Flash" })
            if b.Background then b.Background:SetAlpha(0) end
            if b.PushedBackground then b.PushedBackground:SetAlpha(0) end
        end
    end

    -- EQUIPPED CUE ------------------------------------------------------
    -- Era has no vehicle or possess bars, and 1.15 replaced the global
    -- ActionButton_Update with a mixin method - so there is no "late
    -- arriving button" case left to catch, and the old hook here could
    -- never have fired. What IS needed is keeping the equipped tint in
    -- step with the bars, which is these three events.
    if not ZUI._equipWatch then
        ZUI._equipWatch = CreateFrame("Frame")
        ZUI._equipWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
        ZUI._equipWatch:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        ZUI._equipWatch:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        ZUI._equipWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
        ZUI._equipWatch:SetScript("OnEvent", function()
            -- Coalesced: an equipment swap fires several of these at once.
            if ZUI._equipQueued then return end
            ZUI._equipQueued = true
            C_Timer.After(0.1, function()
                ZUI._equipQueued = nil
                RefreshEquipped()
            end)
        end)
    end
    RefreshEquipped()
end
