-- UIF_Bars - primitives for the HUD: status bars, secure buttons, and the
-- safety rails that keep us out of trouble on protected frames.
-- Part of ZacUI; load order is set by the TOC.
--
-- THE SECURE-FRAME CONTRACT. Action buttons, unit frames and the main bar
-- are secure or client-managed. What is safe, and what is not:
--   SAFE    reading, CreateTexture on them, SetTexture / SetVertexColor /
--           SetTexCoord / SetAlpha / Hide / SetPoint on TEXTURE and
--           FONTSTRING REGIONS, hooking scripts, SetStatusBarTexture.
--   UNSAFE  SetPoint / ClearAllPoints / SetParent / Show / Hide / SetScale
--           / SetSize on the FRAME itself while in combat, and anything at
--           all on a frame that reports IsForbidden.
-- The region/frame distinction is the whole point: regions are not
-- protected, so re-anchoring a hotkey string is fine while re-anchoring
-- the button it sits on is not.
-- Every helper here restricts itself to the safe column. Nothing in the
-- HUD modules moves a secure frame - if you want it somewhere else, that
-- is Edit Mode's job (doctrine 8).

local ADDON_NAME, ns = ...

-- shared state from earlier ZacUI files
local AddPixelBorder = ns.AddPixelBorder
local Col = ns.Col
local FLAT = ns.FLAT
local KillTexture = ns.KillTexture
local SharpenIcon = ns.SharpenIcon
local TEX_NORM = ns.TEX_NORM
local ZUI = ns.ZUI

-- A frame we must never write to, for any reason.
-- Also used as the gate before anything that allocates on a secure frame.
local function InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function Untouchable(frame)
    if not frame then return true end
    if frame.IsForbidden and frame:IsForbidden() then return true end
    -- IsProtected covers the frames the client manages that carry no
    -- give-away name prefix. Checking only IsForbidden and the
    -- NamePlate/Compact/EditMode prefixes left that whole class open.
    if frame.IsProtected and frame:IsProtected() and InCombat() then return true end
    local name = frame.GetName and frame:GetName()
    if name and (name:find("^NamePlate") or name:find("^Compact")
        or name:find("^EditMode")) then
        return true
    end
    return false
end

-- Hide a list of texture regions by global name suffix. Region writes are
-- safe on protected frames; frame writes are not, which is why every art
-- removal in the HUD modules goes through this rather than StripTextures.
local function HideRegions(base, suffixes)
    for _, sfx in ipairs(suffixes) do
        local t = _G[base .. sfx]
        if t and t.SetTexture then
            t:SetTexture(nil)
            t:SetAlpha(0)
        end
    end
end

-- STATUS BAR: flat fill texture, dark backing, 1px border. Keeps whatever
-- colour the game is driving the bar with (class colour, hostility,
-- reaction) - overriding those loses real information.
local function SkinStatusBar(bar, opts)
    if not bar or Untouchable(bar) or ZUI.skinned[bar] then return end
    if not bar.SetStatusBarTexture then return end
    ZUI.skinned[bar] = true
    opts = opts or {}

    -- the global status bar texture (Fonts & Textures), ZacUI's gradient
    -- by default; tracked so a change lands without a reload
    bar:SetStatusBarTexture((ns.Media and ns.Media.BarPath(TEX_NORM)) or TEX_NORM)
    if ns.Media then ns.Media.TrackBar(bar) end
    local tex = bar:GetStatusBarTexture()
    if tex then
        tex:SetHorizTile(false)
        tex:SetVertTile(false)
    end

    if opts.backdrop ~= false and not bar._zui_bg then
        local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
        bg._zui_own = true
        bg:SetAllPoints()
        bg:SetTexture(FLAT)
        local c = Col("elementBg")
        bg:SetVertexColor(c.r * 0.5, c.g * 0.5, c.b * 0.5, opts.bgAlpha or 0.8)
        bar._zui_bg = bg
    end
    if opts.border ~= false then AddPixelBorder(bar) end
    return bar
end

-- DECLARED BEFORE ITS CALLER, deliberately. A Lua local is only
-- visible AFTER its declaration point, so defining this below
-- SkinSecureIcon compiled the call as a nil GLOBAL - fine at load,
-- fatal the first time an item button was skinned. Third time this
-- project has hit that; luac cannot catch it.
-- QUALITY COLOUR, preserved rather than deleted. Blizzard draws item
-- quality as a chunky ring texture (IconBorder) that cannot be flattened,
-- only hidden - but the colour it carries is real information, especially
-- in a bank or an auction list. So the ring is hidden and its colour is
-- moved onto our 1px border, kept in sync by hooking the two calls
-- Blizzard uses to drive it.
local function AdoptQualityBorder(btn, border)
    border = border or btn.IconBorder
    if not border or btn._zui_quality then return end
    btn._zui_quality = true

    local function Sync()
        if border:IsShown() and border:GetAlpha() > 0 then
            local r, g, b = border:GetVertexColor()
            ns.TintBorder(btn, r, g, b, 1)
        else
            ns.TintBorder(btn)
        end
    end
    if border.SetVertexColor then hooksecurefunc(border, "SetVertexColor", Sync) end
    if border.Show then hooksecurefunc(border, "Show", Sync) end
    if border.Hide then hooksecurefunc(border, "Hide", Sync) end
    Sync()
    border:SetTexture(nil)
end

-- ICON BUTTON on a secure frame. Same idea as SkinIconButton but it never
-- calls a frame method - only region methods - so it is safe on action
-- buttons, bag slots and anything else the client protects.
local ICON_KEYS = { "icon", "Icon", "IconTexture" }
local function SkinSecureIcon(btn, opts)
    if not btn or Untouchable(btn) or ZUI.skinned[btn] then return end
    ZUI.skinned[btn] = true
    opts = opts or {}

    local name = btn.GetName and btn:GetName()
    local icon
    for _, key in ipairs(ICON_KEYS) do
        icon = icon or btn[key]
    end
    if not icon and name then
        icon = _G[name .. "Icon"] or _G[name .. "IconTexture"]
    end

    -- The NormalTexture on a classic action button is the grey slot ring.
    -- On some buttons (bag slots, the keyring) it is the ARTWORK itself,
    -- and killing it empties the slot - so it is only cropped there.
    local normal = btn.GetNormalTexture and btn:GetNormalTexture()
    if normal then
        if opts.keepNormal then
            if normal.SetTexCoord then normal:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            SharpenIcon(normal)
        else
            KillTexture(normal)
        end
    end
    if name then
        HideRegions(name, { "FloatingBG", "Shine", "Flash", "SlotBackground" })
    end
    if btn.Border then btn.Border:SetAlpha(0) end
    if btn.SlotArt then btn.SlotArt:SetAlpha(0) end
    if btn.SlotBackground then btn.SlotBackground:SetAlpha(0) end
    if btn.IconMask then btn.IconMask:Hide() end

    if icon and icon.SetTexCoord then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetDrawLayer("ARTWORK")
    end
    SharpenIcon(icon)

    AddPixelBorder(btn)
    -- Quality colour moves onto the border we just added instead of being
    -- thrown away with the rest of the ring art.
    if btn.IconBorder then AdoptQualityBorder(btn, btn.IconBorder) end

    -- Pushed/highlight are flat colour washes rather than Blizzard's
    -- textured overlays, which read as mud once the slot ring is gone.
    local pushed = btn.GetPushedTexture and btn:GetPushedTexture()
    if pushed then
        pushed:SetColorTexture(1, 1, 1, 0.18)
        pushed:SetBlendMode("ADD")
    end
    local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
    if hl then
        hl:SetColorTexture(1, 1, 1, 0.12)
        hl:SetBlendMode("ADD")
    end
    local checked = btn.GetCheckedTexture and btn:GetCheckedTexture()
    if checked then
        local a = Col("accent")
        checked:SetColorTexture(a.r, a.g, a.b, 0.35)
    end
    return btn
end

-- Re-anchor and recolour a button's small text: count, hotkey, macro name.
-- These are FontString regions, so this is region work and safe on secure
-- buttons. Note Blizzard re-anchors the hotkey on every update, so the
-- position here is a starting point rather than a guarantee.
local function StyleButtonText(name)
    local hotkey = _G[name .. "HotKey"]
    local count  = _G[name .. "Count"]
    local macro  = _G[name .. "Name"]
    if hotkey then
        hotkey:SetDrawLayer("OVERLAY", 2)
        hotkey:ClearAllPoints()
        hotkey:SetPoint("TOPRIGHT", 0, -2)
        local c = Col("text")
        hotkey:SetTextColor(c.r, c.g, c.b, 0.9)
    end
    if count then
        count:SetDrawLayer("OVERLAY", 2)
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    if macro then
        macro:SetDrawLayer("OVERLAY", 2)
        local c = Col("text")
        macro:SetTextColor(c.r, c.g, c.b, 0.8)
    end
end

-- Walk a numbered family of globals: ("ActionButton", 1, 12) -> each one.
local function ForEachNamed(prefix, from, to, fn)
    for i = from, to do
        local f = _G[prefix .. i]
        if f then fn(f, i, prefix .. i) end
    end
end

-- shared with later ZacUI files
ns.AdoptQualityBorder = AdoptQualityBorder
ns.InCombat = InCombat
ns.ForEachNamed = ForEachNamed
ns.HideRegions = HideRegions
ns.SkinSecureIcon = SkinSecureIcon
ns.SkinStatusBar = SkinStatusBar
ns.StyleButtonText = StyleButtonText
ns.Untouchable = Untouchable
