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
-- the Look (Core_Look): read once per skin call, never per tick
local Look = ns.Look

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

    -- Classic (opts.look: the part, a look table or nil): the fill is the
    -- look's bar file unless a texture was chosen on Fonts & Textures,
    -- the backing the same file darkened (the vanilla recessed bar), the
    -- edge the look's border
    local lk = Look.Pick(opts.look)
    if lk.id ~= "zacui" then
        local fill = (ns.Media and ns.Media.BarPath(lk.barTexture)) or lk.barTexture
        bar:SetStatusBarTexture(fill)
        if ns.Media then ns.Media.TrackBar(bar) end
        local tex = bar:GetStatusBarTexture()
        if tex and tex.SetHorizTile then
            tex:SetHorizTile(false)
            tex:SetVertTile(false)
        end
        if opts.backdrop ~= false and not bar._zui_bg then
            local bg = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
            bg._zui_own = true
            bg:SetAllPoints()
            bg:SetTexture(lk.barBacking == "same" and fill or FLAT)
            bg:SetVertexColor(0.25, 0.25, 0.25, opts.bgAlpha or 0.8)
            bar._zui_bg = bg
        end
        if opts.border ~= false then AddPixelBorder(bar, nil, nil, lk) end
        return bar
    end

    -- the global status bar texture (Fonts & Textures), ZacUI's gradient
    -- by default; tracked so a change lands without a reload
    bar:SetStatusBarTexture((ns.Media and ns.Media.BarPath(lk.barTexture)) or TEX_NORM)
    if ns.Media then ns.Media.TrackBar(bar) end
    local tex = bar:GetStatusBarTexture()
    -- (feature-detected: a client or a bar whose fill is not a texture
    -- object has no tiling switch)
    if tex and tex.SetHorizTile then
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

-- THE MAINLINE ACTION BUTTON (WoW Forever, 2026-11-07). Forever builds
-- its action, stance and pet buttons from the modern (Mainline)
-- ActionButtonTemplate, and that template hangs its hover, pushed and
-- checked layers from the top-left corner at a fixed 46x45 (the Classic
-- one stretches them over the button). On ZacUI's smaller buttons the
-- flat washes below therefore sat off the bottom-right corner, bigger
-- than the button. It also carries art the Classic one has not: the slot
-- art behind the icon, the "new spell" frame, a spell highlight at the
-- same 46x45. So every layer is pinned to the button itself and the
-- extra art goes. SlotArt is the tell: no Classic template has it, so
-- Classic Era and TBC never come here. Region calls only (secure-safe).
local function PinToButton(btn, tex)
    if tex and tex.ClearAllPoints and tex.SetAllPoints then
        tex:ClearAllPoints()
        tex:SetAllPoints(btn)
    end
end
local function FitMainlineButton(btn, icon)
    for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetCheckedTexture" }) do
        if btn[get] then PinToButton(btn, btn[get](btn)) end
    end
    PinToButton(btn, btn.SpellHighlightTexture)
    PinToButton(btn, btn.Flash)
    PinToButton(btn, btn.QuickKeybindHighlightTexture)
    -- the pet autocast ring is a 45px frame of its own (an unprotected
    -- child: placed out of combat only, like every frame call here)
    local ac = btn.AutoCastOverlay
    if ac and ac.SetAllPoints and not InCombat() then
        ac:ClearAllPoints()
        ac:SetAllPoints(btn)
    end
    if btn.NewActionTexture then btn.NewActionTexture:SetAlpha(0) end
    -- the rounded corner mask is for Blizzard's 45px frame art; on a
    -- square cropped icon it only nicks the corners
    if icon and btn.IconMask and icon.RemoveMaskTexture then
        pcall(icon.RemoveMaskTexture, icon, btn.IconMask)
    end
    -- Blizzard re-runs its art pass on its own bars (Edit Mode, bar art
    -- on/off): the frame ring and the pushed layer come back at 46x45,
    -- so they are put back on the button and the ring hidden again
    if btn.UpdateButtonArt and not btn._zui_artHook then
        btn._zui_artHook = true
        hooksecurefunc(btn, "UpdateButtonArt", function(self)
            local n = self.GetNormalTexture and self:GetNormalTexture()
            if n then n:SetAlpha(0) end
            PinToButton(self, n)
            local p = self.GetPushedTexture and self:GetPushedTexture()
            if p then
                p:SetColorTexture(1, 1, 1, 0.18)
                p:SetBlendMode("ADD")
                PinToButton(self, p)
            end
        end)
    end
end

-- THE CLASSIC RING on an icon button: the vanilla template's NormalTexture
-- is 66x66 on a 36 button, centred one pixel down; this keeps that ratio
-- whatever the button's size (region calls only). Re-run when the button
-- is resized (AB.StyleButton does).
local function FitClassicRing(btn, normal, ring)
    normal = normal or (btn.GetNormalTexture and btn:GetNormalTexture())
    if not (normal and normal.SetSize and normal.ClearAllPoints) then return end
    ring = ring or (Look.Get("classic") or {}).iconRing
    if not ring then return end
    local w = btn.GetWidth and btn:GetWidth() or 0
    local h = btn.GetHeight and btn:GetHeight() or 0
    if type(w) ~= "number" or w <= 0 then w = 36 end
    if type(h) ~= "number" or h <= 0 then h = w end
    normal:ClearAllPoints()
    normal:SetSize(w * ring.scale, h * ring.scale)
    normal:SetPoint("CENTER", btn, "CENTER", 0, h * ring.dy)
end
ns.FitClassicRing = FitClassicRing

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

    -- Classic (opts.look: the part): Blizzard's ring stays - set to the
    -- Quickslot file explicitly, scaled with the button as the vanilla
    -- template draws it (66 on 36), so a Mainline atlas on Forever reads
    -- the same; the icon uncropped and sharpened; pushed / highlight /
    -- checked / quality ring as the game draws them; no strips (so the
    -- border walks find nothing and do nothing). Region calls only.
    local lk = Look.Pick(opts.look, "bars")
    if lk.iconButton == "stock" then
        local ring = lk.iconRing
        local normal = btn.GetNormalTexture and btn:GetNormalTexture()
        if normal and ring and not opts.keepNormal then
            normal:SetTexture(ring.normal)
            if normal.SetTexCoord then normal:SetTexCoord(0, 1, 0, 1) end
            normal:SetAlpha(1)
            ns.FitClassicRing(btn, normal, ring)
        end
        if icon and icon.SetTexCoord then
            icon:SetTexCoord(lk.iconCrop, 1 - lk.iconCrop, lk.iconCrop, 1 - lk.iconCrop)
        end
        SharpenIcon(icon)
        -- a look-alike button made with flat placeholders for its states
        -- (the settings preview's sample) gets the template's own files
        if ring then
            for key, get in pairs({ pushed = "GetPushedTexture", highlight = "GetHighlightTexture", checked = "GetCheckedTexture" }) do
                local t = btn[get] and btn[get](btn)
                if t and t.GetTexture and t:GetTexture() == FLAT then
                    t:SetTexture(ring[key])
                    if key ~= "pushed" then t:SetBlendMode("ADD") end
                end
            end
        end
        if btn.SlotArt then btn.SlotArt:SetAlpha(0) end
        if btn.SlotBackground then btn.SlotBackground:SetAlpha(0) end
        if btn.NewActionTexture then btn.NewActionTexture:SetAlpha(0) end
        -- Forever's Mainline template re-runs its art pass (Edit Mode, bar
        -- art on/off) and puts its atlas ring back: the Quickslot file again
        if btn.SlotArt and btn.UpdateButtonArt and not btn._zui_artHook and ring then
            btn._zui_artHook = true
            hooksecurefunc(btn, "UpdateButtonArt", function(self)
                local n = self.GetNormalTexture and self:GetNormalTexture()
                if n then
                    n:SetTexture(ring.normal)
                    n:SetAlpha(1)
                    FitClassicRing(self, n, ring)
                end
                if self.SlotArt then self.SlotArt:SetAlpha(0) end
                if self.SlotBackground then self.SlotBackground:SetAlpha(0) end
            end)
        end
        rawset(btn, "_zLook", lk.id)
        return btn
    end

    -- The NormalTexture on a classic action button is the grey slot ring.
    -- On some buttons (bag slots, the keyring) it is the ARTWORK itself,
    -- and killing it empties the slot - so it is only cropped there.
    local normal = btn.GetNormalTexture and btn:GetNormalTexture()
    -- ...but on a bag slot with a picture of its own (the client's
    -- ItemButtonTemplate: the bag in $parentIconTexture, the NormalTexture
    -- the 64 x 64 grey Quickslot frame round it; Forever's bag-border
    -- atlas) the NormalTexture is only the frame, and it stood as the big
    -- grey slot round ZacUI's border (Zac on TBC Anniversary, 2026-11-08).
    -- Hidden by alpha, never emptied: the picture is the icon. The key
    -- ring (its NormalTexture is its picture, no icon) keeps it.
    if normal and opts.keepNormal and type(icon) == "table" and icon ~= normal
        and icon.SetTexCoord and normal.SetAlpha then
        normal:SetAlpha(0)
    elseif normal then
        if opts.keepNormal then
            if normal.SetTexCoord then ns.Look.CropIcon(normal, nil, nil, { border = false }) end
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
        ns.Look.CropIcon(icon, nil, nil, { border = false })
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
    if btn.SlotArt then FitMainlineButton(btn, icon) end
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
