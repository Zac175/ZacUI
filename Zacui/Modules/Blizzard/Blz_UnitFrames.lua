-- Blz_UnitFrames - player, target, target-of-target, pet and party frames,
-- plus every cast bar in the game.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE ONE DECISION worth explaining: bar COLOURS are left alone. Blizzard
-- drives health colour from hostility and reaction, mana colour from power
-- type, and the target's bar from whether it can be attacked. All of that
-- is information the player reads at a glance mid-fight. ZacUI replaces
-- the TEXTURE and the frame around it, never the tint.
--
-- The same rule applies to STATE ART, and it is easy to get wrong because
-- it looks like chrome. The combat glow, the resting zzz, the target flash
-- and the uninterruptible-cast shield all live on the frame texture layer
-- next to the gryphons - but every one of them is the only cue for
-- something the player needs. They are kept; only the ornamental frame,
-- background and name plate are removed.
--
-- Geometry is untouched for the same reason as the action bars: these are
-- secure unit frames, and their position belongs to Edit Mode.

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local Col = ns.Col
local FLAT = ns.FLAT
local ForEachNamed = ns.ForEachNamed
local HideRegions = ns.HideRegions
local Modules = ns.Modules
local SharpenIcon = ns.SharpenIcon
local SkinStatusBar = ns.SkinStatusBar
local Untouchable = ns.Untouchable
local ZUI = ns.ZUI

-- A dark plate BEHIND a unit frame's bars, sized to the bars rather than
-- to the frame: a classic unit frame's rect is mostly portrait socket and
-- transparent margin, and filling the rect paints a black slab around the
-- portrait.
local function BackPlate(frame, top, bottom, pad)
    if not frame or not top or frame._zui_plate then return end
    pad = pad or 2
    local plate = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    plate._zui_own = true
    plate:SetTexture(FLAT)
    plate:SetPoint("TOPLEFT", top, "TOPLEFT", -pad, pad)
    plate:SetPoint("BOTTOMRIGHT", bottom or top, "BOTTOMRIGHT", pad, -pad)
    local c = Col("windowBg")
    plate:SetVertexColor(c.r, c.g, c.b, 0.85)
    frame._zui_plate = plate
    return plate
end

-- Art that carries state rather than decoration. Never stripped.
local KEEP = {
    PlayerStatusTexture = true,   -- in combat
    PlayerRestIcon = true,        -- resting / rested XP
    PlayerAttackIcon = true,
    TargetFrameFlash = true,      -- target is attacking you
    PetFrameFlash = true,
    PetAttackModeTexture = true,
}

local function SkinPortrait(portrait)
    if not portrait then return end
    -- Round portraits sit in a carved socket. Squaring the crop and adding
    -- our border makes them match every other icon in the UI.
    if portrait.SetTexCoord then portrait:SetTexCoord(0.15, 0.85, 0.15, 0.85) end
end

-- One unit frame, described by what it actually owns. Passing the names in
-- keeps the per-frame differences (ToT has no mana bar, pet has no level)
-- as data instead of five near-identical functions.
local function SkinUnit(frame, spec)
    if not frame or Untouchable(frame) or ZUI.skinned[frame] then return end
    ZUI.skinned[frame] = true
    local name = frame.GetName and frame:GetName()

    for _, texName in ipairs(spec.art or {}) do
        local t = _G[texName]
        if t and t.SetTexture and not KEEP[texName] then
            t:SetTexture(nil)
            t:SetAlpha(0)
        end
    end
    if name then
        -- No "Flash" in this list: on unit frames the flash is the
        -- attacking-you indicator, not chrome.
        HideRegions(name, { "Texture", "Background", "Border",
                            "VehicleTexture", "FrameTexture" })
    end
    -- Keyed art on the newer template generation.
    for _, key in ipairs({ "FrameTexture", "Background", "Border", "VehicleFrame",
                           "PortraitFrame" }) do
        local piece = frame[key]
        if piece and piece.SetAlpha then piece:SetAlpha(0) end
    end
    if frame.TargetFrameContainer and frame.TargetFrameContainer.FrameTexture then
        frame.TargetFrameContainer.FrameTexture:SetAlpha(0)
    end
    if frame.PlayerFrameContainer then
        for _, region in ipairs({ frame.PlayerFrameContainer:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end
    end

    local health = spec.health and _G[spec.health]
    local mana   = spec.mana and _G[spec.mana]
    if health then SkinStatusBar(health, { bgAlpha = 0.85 }) end
    if mana then SkinStatusBar(mana, { bgAlpha = 0.85 }) end
    -- One plate spanning BOTH bars. Anchored to health alone it stopped at
    -- the health bar's bottom edge and left the mana bar sitting on the
    -- open world with nothing behind it.
    if health then BackPlate(frame, health, mana, 2) end

    SkinPortrait(spec.portrait and _G[spec.portrait])

    -- The name plate behind the unit name is part of the removed art, so
    -- the name now sits on the world. Give it an outline or it disappears
    -- over bright ground.
    local nameFS = spec.name and _G[spec.name]
    if nameFS and nameFS.GetFont then
        local font, size = nameFS:GetFont()
        if font then nameFS:SetFont(font, size or 10, "OUTLINE") end
        local c = Col("text")
        nameFS:SetTextColor(c.r, c.g, c.b, 1)
    end

    for _, extra in ipairs(spec.bars or {}) do
        local b = _G[extra]
        if b then SkinStatusBar(b) end
    end
end

Modules.unitframes = function()
    SkinUnit(PlayerFrame, {
        art = { "PlayerFrameTexture", "PlayerFrameBackground",
                "PlayerFrameVehicleTexture", "PlayerStatusTexture",
                "PlayerRestIcon", "PlayerAttackBackground" },
        health = "PlayerFrameHealthBar", mana = "PlayerFrameManaBar",
        portrait = "PlayerPortrait", name = "PlayerName",
    })
    SkinUnit(TargetFrame, {
        art = { "TargetFrameTextureFrameTexture", "TargetFrameBackground",
                "TargetFrameNameBackground", "TargetFrameFlash" },
        health = "TargetFrameHealthBar", mana = "TargetFrameManaBar",
        portrait = "TargetFramePortrait", name = "TargetFrameTextureFrameName",
    })
    SkinUnit(TargetFrameToT, {
        art = { "TargetFrameToTTextureFrameTexture", "TargetFrameToTBackground" },
        health = "TargetFrameToTHealthBar", mana = "TargetFrameToTManaBar",
        portrait = "TargetFrameToTPortrait", name = "TargetFrameToTTextureFrameName",
    })
    SkinUnit(PetFrame, {
        art = { "PetFrameTexture", "PetFrameBackground", "PetFrameFlash" },
        health = "PetFrameHealthBar", mana = "PetFrameManaBar",
        portrait = "PetPortrait", name = "PetName",
    })
    ForEachNamed("PartyMemberFrame", 1, 4, function(frame, i, name)
        SkinUnit(frame, {
            art = { name .. "Texture", name .. "Background", name .. "Flash",
                    name .. "VehicleTexture" },
            health = name .. "HealthBar", mana = name .. "ManaBar",
            portrait = name .. "Portrait", name = name .. "Name",
        })
        local pet = _G[name .. "PetFrame"]
        if pet then
            SkinUnit(pet, {
                art = { name .. "PetFrameTexture", name .. "PetFrameFlash" },
                health = name .. "PetFrameHealthBar",
                portrait = name .. "PetFramePortrait",
            })
        end
    end)

    -- Combo points, druid mana, runes and the rest of the class widgetry
    -- keep their own art - it is class-specific iconography, not chrome.
    -- Only the trough behind them is flattened.
    -- Druid mana in forms is the only extra power bar Era has. The class
    -- widgetry lists here previously (MonkStaggerBar, RuneFrame) belong to
    -- later expansions and never existed on this client.
    if PlayerFrameAlternateManaBar and PlayerFrameAlternateManaBar.SetStatusBarTexture then
        SkinStatusBar(PlayerFrameAlternateManaBar)
    end
    -- PetFrameHappiness is a Frame with its own icon sheet, not a bar -
    -- there is nothing here to flatten, and its icon is the state cue.
end

-- ============================================================
-- CAST BARS
-- ============================================================
local function SkinCastBar(bar, opts)
    if not bar or Untouchable(bar) or ZUI.skinned[bar] then return end
    opts = opts or {}
    SkinStatusBar(bar, { bgAlpha = 0.9 })

    local name = bar.GetName and bar:GetName()
    if name then
        HideRegions(name, { "Border", "Flash", "Background" })
    end
    -- BorderShield is deliberately absent from this list: it is the
    -- uninterruptible indicator, and on a target cast bar that is the
    -- single most important thing the bar tells you.
    for _, key in ipairs({ "Border", "Flash", "Background",
                           "TextBorder", "Spark" }) do
        local piece = bar[key]
        if piece and piece.SetAlpha then
            -- The spark survives at reduced strength: it is the only cue
            -- for where the cast currently is on a flat bar.
            piece:SetAlpha(key == "Spark" and 0.5 or 0)
        end
    end

    -- The cast icon is hidden by default on the player bar in classic;
    -- when an addon or a later build shows it, crop it like every icon.
    local icon = bar.Icon or (name and _G[name .. "Icon"])
    if icon and icon.SetTexCoord then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        SharpenIcon(icon)
    end

    local text = bar.Text or (name and _G[name .. "Text"])
    if text and text.GetFont then
        local font, size = text:GetFont()
        if font then text:SetFont(font, size or 11, "OUTLINE") end
        local c = Col("text")
        text:SetTextColor(c.r, c.g, c.b, 1)
    end
end

Modules.castbar = function()
    -- Era has exactly three: the player bar, the pet bar and the target's.
    -- No focus frame, and party members have no cast bar on this client.
    SkinCastBar(CastingBarFrame)
    SkinCastBar(PetCastingBarFrame)
    SkinCastBar(TargetFrameSpellBar)

    -- Breath, fatigue and feign death share MirrorTimer1..3. They are
    -- created up front but only anchored when they fire, so they can be
    -- skinned at login safely.
    ForEachNamed("MirrorTimer", 1, 3, function(frame, i, name)
        local bar = _G[name .. "StatusBar"]
        if bar then
            SkinStatusBar(bar, { bgAlpha = 0.9 })
            HideRegions(name .. "StatusBar", { "Border" })
        end
        local border = _G[name .. "Border"]
        if border then border:SetAlpha(0) end
        local text = _G[name .. "Text"]
        if text then
            local c = Col("text")
            text:SetTextColor(c.r, c.g, c.b, 1)
        end
    end)

    -- No late-arrival hook: 1.15 moved cast bar setup onto a mixin, and
    -- OnLoad only ever fires at XML parse time anyway - so the hook that
    -- used to be here could not have caught anything even where the global
    -- still existed. Era creates all three bars up front.
end
